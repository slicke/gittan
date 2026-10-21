unit gittan.richdiff;

{** The changes of a rendered page marked on the page itself, as a rich
  diff shows a document: the blocks of the new version (paragraphs,
  headings, list items, table rows, code blocks) that are new or changed
  get a class, and the blocks of the old version that are gone are put
  back where they were, with a class of their own, so the preview can
  draw a bar beside them or strike them through.

  Both versions are read as HTML into LazInk's DOM and cut into blocks:
  an element whose children are all inline is one block, a table row is
  one, and a container (a list, a quote, a table, a list item holding a
  nested list) is cut further, the inline text it holds before its
  blocks wrapped in a <div> of its own. Two blocks are the same when
  their HTML is, white space collapsed. The blocks are matched in order
  by their longest common subsequence; in each stretch between matches
  the first new blocks pair with the first old ones and count as
  changed, the rest as added or deleted. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  RichAddedClass = 'gittan-added';
  RichChangedClass = 'gittan-changed';
  RichDeletedClass = 'gittan-deleted';

{** ANewHtml, a page, with its blocks marked against AOldHtml, the page
  it changed from, and the deleted blocks put back, as a whole HTML
  document. Pages too large to compare come back unmarked. }
function MarkRichDiff(const AOldHtml, ANewHtml: string): string;

implementation

uses
  Math, InkDOM;

const
  { The common subsequence takes a table of one cell per pair of blocks
    left after the shared start and end are taken off. }
  MaxCells = 4000000;
  BlockTags: array[0..33] of string = ('address', 'article', 'aside',
    'blockquote', 'details', 'dd', 'div', 'dl', 'dt', 'fieldset', 'figcaption',
    'figure', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hr',
    'li', 'main', 'nav', 'ol', 'p', 'pre', 'section', 'summary', 'table', 'tr',
    'ul', 'tbody');
  { Containers cut into their children even when nothing in them is a
    block of its own. }
  AlwaysCut: array[0..5] of string = ('ul', 'ol', 'table', 'thead', 'tbody', 'tfoot');

type
  TBlocks = record
    Nodes: TInkNodeArray;
    Keys: array of string;
    Count: integer;
  end;

function InList(const AName: string; const AList: array of string): boolean;
var
  S: string;
begin
  for S in AList do
    if S = AName then
      Exit(True);
  Result := False;
end;

function IsBlock(ANode: TInkNode): boolean;
begin
  Result := (ANode.Kind = inkElement) and (InList(ANode.Name, BlockTags) or
    InList(ANode.Name, AlwaysCut));
end;

function HasBlockChild(ANode: TInkNode): boolean;
var
  C: TInkNode;
begin
  C := ANode.FirstChild;
  while C <> nil do
  begin
    if IsBlock(C) then
      Exit(True);
    C := C.NextSibling;
  end;
  Result := False;
end;

function IsBlank(ANode: TInkNode): boolean;
begin
  Result := (ANode.Kind = inkComment) or
    ((ANode.Kind = inkText) and (Trim(ANode.Data) = ''));
end;

{ S with every run of white space one space, and none at the ends. }
function Collapse(const S: string): string;
var
  i, n: integer;
  Space: boolean;
begin
  SetLength(Result, Length(S));
  n := 0;
  Space := False;
  for i := 1 to Length(S) do
    if S[i] in [' ', #9, #10, #13] then
      Space := n > 0
    else
    begin
      if Space then
      begin
        Inc(n);
        Result[n] := ' ';
        Space := False;
      end;
      Inc(n);
      Result[n] := S[i];
    end;
  SetLength(Result, n);
end;

procedure AddBlock(var ABlocks: TBlocks; ANode: TInkNode);
begin
  if ABlocks.Count = Length(ABlocks.Nodes) then
  begin
    SetLength(ABlocks.Nodes, 16 + 2 * ABlocks.Count);
    SetLength(ABlocks.Keys, Length(ABlocks.Nodes));
  end;
  ABlocks.Nodes[ABlocks.Count] := ANode;
  ABlocks.Keys[ABlocks.Count] := Collapse(InkSerializeHTML(ANode));
  Inc(ABlocks.Count);
end;

{ The blocks under ANode, a container, in document order; a run of
  inline children before, between or after its blocks is moved into a
  <div> of its own, which is the block. }
procedure Collect(ANode: TInkNode; var ABlocks: TBlocks);
var
  C, Next, Run, Wrap: TInkNode;
  Empty: boolean;
begin
  C := ANode.FirstChild;
  while C <> nil do
  begin
    if IsBlock(C) then
    begin
      if (C.Name = 'tr') or not (HasBlockChild(C) or InList(C.Name, AlwaysCut)) then
        AddBlock(ABlocks, C)
      else
        Collect(C, ABlocks);
      C := C.NextSibling;
      Continue;
    end;
    { The inline run from C up to the next block. }
    Run := C;
    Empty := True;
    while (C <> nil) and not IsBlock(C) do
    begin
      if not IsBlank(C) then
        Empty := False;
      C := C.NextSibling;
    end;
    if Empty then
      Continue;
    Wrap := TInkNode.Create(inkElement, 'div');
    ANode.InsertBefore(Wrap, Run);
    while Run <> C do
    begin
      Next := Run.NextSibling;
      Run.Remove;
      Wrap.AppendChild(Run);
      Run := Next;
    end;
    AddBlock(ABlocks, Wrap);
  end;
end;

procedure AddClass(ANode: TInkNode; const AClass: string);
var
  Old: string;
begin
  Old := ANode.GetAttribute('class');
  if Old = '' then
    ANode.SetAttribute('class', AClass)
  else
    ANode.SetAttribute('class', Old + ' ' + AClass);
end;

{ A copy of AOld, a deleted block, marked, inside copies of its
  containers up to one named as AInto, where it goes, so a list item
  goes into a list and a row into a table. }
function DeletedCopy(AOld, AInto: TInkNode): TInkNode;
var
  P, Wrap: TInkNode;
begin
  Result := AOld.Clone(True);
  AddClass(Result, RichDeletedClass);
  P := AOld.Parent;
  while (P <> nil) and (P.Name <> AInto.Name) and (P.Name <> 'body') do
  begin
    Wrap := P.Clone(False);
    Wrap.AppendChild(Result);
    Result := Wrap;
    P := P.Parent;
  end;
end;

{ The deleted blocks AOld[AFrom..ATo - 1] put into the new page: after
  APrev, the new block before them, when it sits in the same kind of
  container, else before ANext, the new block after them; at the end of
  ABody when the new page has no blocks. }
procedure PutBack(const AOld: TBlocks; AFrom, ATo: integer; APrev, ANext, ABody: TInkNode);
var
  Last, Into, Copy: TInkNode;
  i: integer;
begin
  Last := nil;
  if (APrev <> nil) and ((ANext = nil) or
    (APrev.Parent.Name = AOld.Nodes[AFrom].Parent.Name)) then
    Last := APrev;
  for i := AFrom to ATo - 1 do
  begin
    if Last <> nil then
      Into := Last.Parent
    else if ANext <> nil then
      Into := ANext.Parent
    else
      Into := ABody;
    Copy := DeletedCopy(AOld.Nodes[i], Into);
    if Last <> nil then
      Into.InsertBefore(Copy, Last.NextSibling)
    else
      Into.InsertBefore(Copy, ANext);
    Last := Copy;
  end;
end;

function MarkRichDiff(const AOldHtml, ANewHtml: string): string;
var
  OldDoc, NewDoc: TInkDocument;
  Old, New: TBlocks;
  Lcs: array of integer;
  Lo, HiOld, HiNew, n, m, i, j, i0, j0, k, w: integer;
  Prev, Next: TInkNode;

  { The common subsequence's length from old block Lo + a, new Lo + b on. }
  function Cell(a, b: integer): integer; inline;
  begin
    Result := Lcs[a * (m + 1) + b];
  end;

begin
  OldDoc := InkParseHTML(AOldHtml);
  NewDoc := InkParseHTML(ANewHtml);
  try
    Old := Default(TBlocks);
    New := Default(TBlocks);
    if (OldDoc.Body = nil) or (NewDoc.Body = nil) then
      Exit(ANewHtml);
    Collect(OldDoc.Body, Old);
    Collect(NewDoc.Body, New);
    { The shared start and end, then the table for what is between. }
    Lo := 0;
    while (Lo < Old.Count) and (Lo < New.Count) and (Old.Keys[Lo] = New.Keys[Lo]) do
      Inc(Lo);
    HiOld := Old.Count;
    HiNew := New.Count;
    while (HiOld > Lo) and (HiNew > Lo) and (Old.Keys[HiOld - 1] = New.Keys[HiNew - 1]) do
    begin
      Dec(HiOld);
      Dec(HiNew);
    end;
    n := HiOld - Lo;
    m := HiNew - Lo;
    if int64(n + 1) * (m + 1) > MaxCells then
      Exit(ANewHtml);
    SetLength(Lcs, (n + 1) * (m + 1));
    for i := n - 1 downto 0 do
      for j := m - 1 downto 0 do
        if Old.Keys[Lo + i] = New.Keys[Lo + j] then
          Lcs[i * (m + 1) + j] := Cell(i + 1, j + 1) + 1
        else
          Lcs[i * (m + 1) + j] := Max(Cell(i + 1, j), Cell(i, j + 1));
    { Walk the table; every stretch between two matches is marked. }
    i := 0;
    j := 0;
    while (i < n) or (j < m) do
    begin
      i0 := i;
      j0 := j;
      while ((i < n) or (j < m)) and not ((i < n) and (j < m) and
        (Old.Keys[Lo + i] = New.Keys[Lo + j]) and (Cell(i, j) = Cell(i + 1, j + 1) + 1)) do
        if (j < m) and ((i = n) or (Cell(i, j + 1) >= Cell(i + 1, j))) then
          Inc(j)
        else
          Inc(i);
      k := Min(i - i0, j - j0);
      for w := j0 to j - 1 do
        if w - j0 < k then
          AddClass(New.Nodes[Lo + w], RichChangedClass)
        else
          AddClass(New.Nodes[Lo + w], RichAddedClass);
      if i - i0 > k then
      begin
        Prev := nil;
        Next := nil;
        if Lo + j > 0 then
          Prev := New.Nodes[Lo + j - 1];
        if Lo + j < New.Count then
          Next := New.Nodes[Lo + j];
        PutBack(Old, Lo + i0 + k, Lo + i, Prev, Next, NewDoc.Body);
      end;
      { Past the match. }
      if (i < n) and (j < m) then
      begin
        Inc(i);
        Inc(j);
      end;
    end;
    Result := InkSerializeHTML(NewDoc);
  finally
    OldDoc.Free;
    NewDoc.Free;
  end;
end;

end.
