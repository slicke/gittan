unit gittan.symbolchanges;

{** The symbols a diff changed: the ranges of the lexer's code tree (the
  functions, methods and classes CodeTree lists, each with the rows it
  spans) laid over the rows of the change view, whose markers say which
  rows were added and deleted.

  A changed row belongs to the innermost range around it, so a class
  whose only changes are inside its methods is not itself reported. A
  range whose every row was added (or deleted) is reported as added (or
  deleted) once, and the ranges inside it are not reported again. Then
  the deleted and the added ranges are paired: a pair with the same name
  next to each other (no unchanged row between them) is one rewritten
  symbol, reported as changed with both counts; a pair with the same name
  apart is a move, reported at both ends; a pair with the same body under
  different names is a rename.

  The side-by-side view has two texts. Its rows are aligned (a filler row
  on one side stands for a line the other side has), so the rows of both
  sides count in one row space: the new side gives every change but the
  wholly deleted ranges, which are read from the old side, where the
  filler rows are marked as added lines and on the new side as deleted
  ones. Nothing here needs the LCL. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, gittan.symbols;

type
  {** A range of the code tree: its symbol (see gittan.symbols) and the
    first and last row it spans in the text. }
  TGittanCodeRange = record
    Symbol: TGittanSymbol;
    FromRow, ToRow: integer;
  end;
  TGittanCodeRanges = array of TGittanCodeRange;

  {** The text of one side of the change view: its code tree ranges, one
    marker per row (' ' unchanged, '+' added, '-' deleted; a row past the
    end counts as unchanged) and the text of each row, which only the
    move and rename detection reads and which may be nil. }
  TGittanSideText = record
    Ranges: TGittanCodeRanges;
    Markers: string;
    Lines: TStrings;
  end;

  {** How a symbol changed: lines inside it changed; it was added or
    deleted as a whole; it was moved (scMoved at its new place, scMovedFrom
    at its old one); or it was renamed (scRenamed is the new name,
    scRenamedFrom the old). }
  TGittanSymbolChangeKind = (scChanged, scAdded, scDeleted, scMoved, scMovedFrom,
    scRenamed, scRenamedFrom);

  {** One changed symbol: the index of its range in the side's Ranges
    (OnOld says which side), the lines added and deleted in it (for a
    changed symbol the ones not inside a reported inner range), the index
    in the result of the other end of a move or rename (-1 otherwise),
    and for a move whether the body is the same at both ends. }
  TGittanSymbolChange = record
    Kind: TGittanSymbolChangeKind;
    Range: integer;
    OnOld: boolean;
    Added, Deleted: integer;
    Other: integer;
    Same: boolean;
  end;
  TGittanSymbolChanges = array of TGittanSymbolChange;

{** The index of the innermost range of ARanges that holds row ARow (the
  shortest; among equals the last, which is the inner one in tree order),
  -1 when none does. }
function InnermostRange(const ARanges: TGittanCodeRanges; ARow: integer): integer;

{** The symbols the diff changed, in row order. With ATwoSides the rows
  of AOld are aligned with those of ANew and the wholly deleted ranges
  come from AOld; otherwise AOld is not read. }
function SymbolChanges(const ANew, AOld: TGittanSideText; ATwoSides: boolean): TGittanSymbolChanges;

{** The range of AChange in ANew or AOld. }
function ChangeRange(const AChange: TGittanSymbolChange; const ANew, AOld: TGittanSideText): TGittanCodeRange;

{** What to say about AChange after its name: "+3 −1", "added  +12",
  "deleted  −8", "moved here" (", changed" when the body differs), "moved
  away", "renamed from X" or "renamed to X", with AOtherName the name at
  the other end of a rename. }
function ChangeDetail(const AChange: TGittanSymbolChange; const AOtherName: string): string;

implementation

uses
  Math;

resourcestring
  rsCounts = '+%d  −%d';
  rsAdded = 'added  +%d';
  rsDeleted = 'deleted  −%d';
  rsMovedHere = 'moved here';
  rsMovedChanged = 'moved here, changed';
  rsMovedAway = 'moved away';
  rsRenamedFrom = 'renamed from %s';
  rsRenamedTo = 'renamed to %s';

type
  { What Analyze finds out about one range. }
  TRangeFacts = record
    Added, Deleted: integer;
    DirectAdded, DirectDeleted: integer;
    Whole, Listed: boolean;
    Kind: TGittanSymbolChangeKind;
  end;
  TRangeFactsArray = array of TRangeFacts;

function MarkerAt(const AMarkers: string; ARow: integer): char;
begin
  if (ARow >= 0) and (ARow < Length(AMarkers)) then
    Result := AMarkers[ARow + 1]
  else
    Result := ' ';
end;

function Span(const R: TGittanCodeRange): integer;
begin
  Result := R.ToRow - R.FromRow + 1;
end;

function Contains(const AOuter, AInner: TGittanCodeRange): boolean;
begin
  Result := (AOuter.FromRow <= AInner.FromRow) and (AInner.ToRow <= AOuter.ToRow);
end;

function InnermostRange(const ARanges: TGittanCodeRanges; ARow: integer): integer;
var
  i: integer;
begin
  Result := -1;
  for i := 0 to High(ARanges) do
    if (ARanges[i].FromRow <= ARow) and (ARow <= ARanges[i].ToRow) and
      ((Result < 0) or (Span(ARanges[i]) <= Span(ARanges[Result]))) then
      Result := i;
end;

{ The indices of ARanges by start row, an outer range before the ranges
  inside it, so that assigning the rows to the ranges in this order
  leaves every row with its innermost range. The lexer lists them by
  start already, so an insertion sort is quick. }
function OuterFirst(const ARanges: TGittanCodeRanges): TIntegerDynArray;
var
  i, j: integer;

  function Before(A, B: integer): boolean;
  begin
    if ARanges[A].FromRow <> ARanges[B].FromRow then
      Result := ARanges[A].FromRow < ARanges[B].FromRow
    else
      Result := Span(ARanges[A]) > Span(ARanges[B]);
  end;

begin
  SetLength(Result, Length(ARanges));
  for i := 0 to High(Result) do
  begin
    j := i;
    while (j > 0) and Before(i, Result[j - 1]) do
    begin
      Result[j] := Result[j - 1];
      Dec(j);
    end;
    Result[j] := i;
  end;
end;

{ Counts the added and the deleted rows of every range of ASide, as a
  whole and the ones no inner range holds, and decides which ranges are
  reported and as what. }
procedure Analyze(const ASide: TGittanSideText; out AFacts: TRangeFactsArray);
var
  Order, Owner: TIntegerDynArray;
  Rows, i, j, k, r, Total: integer;
  M: char;
begin
  SetLength(AFacts, Length(ASide.Ranges));
  Rows := Length(ASide.Markers);
  for i := 0 to High(ASide.Ranges) do
    Rows := Max(Rows, ASide.Ranges[i].ToRow + 1);
  SetLength(Owner, Rows);
  for r := 0 to Rows - 1 do
    Owner[r] := -1;
  Order := OuterFirst(ASide.Ranges);
  for k := 0 to High(Order) do
  begin
    i := Order[k];
    for r := Max(0, ASide.Ranges[i].FromRow) to ASide.Ranges[i].ToRow do
      Owner[r] := i;
  end;
  for i := 0 to High(ASide.Ranges) do
  begin
    AFacts[i] := Default(TRangeFacts);
    for r := Max(0, ASide.Ranges[i].FromRow) to ASide.Ranges[i].ToRow do
      case MarkerAt(ASide.Markers, r) of
        '+': Inc(AFacts[i].Added);
        '-': Inc(AFacts[i].Deleted);
      end;
    Total := Span(ASide.Ranges[i]);
    AFacts[i].Whole := (Total > 0) and
      ((AFacts[i].Added = Total) or (AFacts[i].Deleted = Total));
  end;
  for r := 0 to Rows - 1 do
  begin
    M := MarkerAt(ASide.Markers, r);
    if (M = ' ') or (Owner[r] < 0) then
      Continue;
    if M = '+' then
      Inc(AFacts[Owner[r]].DirectAdded)
    else
      Inc(AFacts[Owner[r]].DirectDeleted);
  end;
  for i := 0 to High(ASide.Ranges) do
    if AFacts[i].Whole then
    begin
      { The outermost whole range stands for the ones inside it. }
      AFacts[i].Listed := True;
      for j := 0 to High(ASide.Ranges) do
        if (j <> i) and AFacts[j].Whole and Contains(ASide.Ranges[j], ASide.Ranges[i]) and
          ((Span(ASide.Ranges[j]) > Span(ASide.Ranges[i])) or (j < i)) then
        begin
          AFacts[i].Listed := False;
          Break;
        end;
      if AFacts[i].Added > 0 then
        AFacts[i].Kind := scAdded
      else
        AFacts[i].Kind := scDeleted;
    end
    else
    begin
      AFacts[i].Listed := AFacts[i].DirectAdded + AFacts[i].DirectDeleted > 0;
      AFacts[i].Kind := scChanged;
      AFacts[i].Added := AFacts[i].DirectAdded;
      AFacts[i].Deleted := AFacts[i].DirectDeleted;
    end;
end;

function ChangeRange(const AChange: TGittanSymbolChange; const ANew, AOld: TGittanSideText): TGittanCodeRange;
begin
  if AChange.OnOld then
    Result := AOld.Ranges[AChange.Range]
  else
    Result := ANew.Ranges[AChange.Range];
end;

{ The rows of R in ASide with their whitespace taken out and the blank
  rows left out, one per line; ARows counts the rows kept. With
  ASkipFirst the first row, the header that names the symbol, is left
  out, so a renamed symbol's body compares equal. }
function BodyText(const ASide: TGittanSideText; const ARange: TGittanCodeRange;
  ASkipFirst: boolean; out ARows: integer): string;
var
  r, i: integer;
  S, Kept: string;
begin
  Result := '';
  ARows := 0;
  if ASide.Lines = nil then
    Exit;
  for r := Max(0, ARange.FromRow + Ord(ASkipFirst)) to Min(ARange.ToRow, ASide.Lines.Count - 1) do
  begin
    S := ASide.Lines[r];
    Kept := '';
    for i := 1 to Length(S) do
      if not (S[i] in [' ', #9, #13, #10]) then
        Kept := Kept + S[i];
    if Kept = '' then
      Continue;
    Result := Result + Kept + #10;
    Inc(ARows);
  end;
end;

function SymbolChanges(const ANew, AOld: TGittanSideText; ATwoSides: boolean): TGittanSymbolChanges;
var
  NewFacts, OldFacts: TRangeFactsArray;
  Drop: array of boolean;
  i, j, k, n, Lo, Hi, r, RowsA, RowsB: integer;
  C: TGittanSymbolChange;
  RA, RB: TGittanCodeRange;
  Adjacent: boolean;

  procedure Add(ARange: integer; AOnOld: boolean; const AFacts: TRangeFacts);
  begin
    SetLength(Result, Length(Result) + 1);
    with Result[High(Result)] do
    begin
      Kind := AFacts.Kind;
      Range := ARange;
      OnOld := AOnOld;
      Added := AFacts.Added;
      Deleted := AFacts.Deleted;
      Other := -1;
      Same := False;
    end;
  end;

  function SideOf(const AChange: TGittanSymbolChange): TGittanSideText;
  begin
    if AChange.OnOld then
      Result := AOld
    else
      Result := ANew;
  end;

  { Whether A sorts before B: by start row; at the same row the deleted
    copy on the old side first. }
  function Before(const A, B: TGittanSymbolChange): boolean;
  var
    FA, FB: integer;
  begin
    FA := ChangeRange(A, ANew, AOld).FromRow;
    FB := ChangeRange(B, ANew, AOld).FromRow;
    if FA <> FB then
      Result := FA < FB
    else
      Result := A.OnOld and not B.OnOld;
  end;

begin
  Result := nil;
  Analyze(ANew, NewFacts);
  for i := 0 to High(NewFacts) do
    if NewFacts[i].Listed then
      Add(i, False, NewFacts[i]);
  if ATwoSides then
  begin
    Analyze(AOld, OldFacts);
    for i := 0 to High(OldFacts) do
      if OldFacts[i].Listed and (OldFacts[i].Kind = scDeleted) then
        Add(i, True, OldFacts[i]);
  end;
  { In row order. }
  for i := 1 to High(Result) do
  begin
    C := Result[i];
    j := i;
    while (j > 0) and Before(C, Result[j - 1]) do
    begin
      Result[j] := Result[j - 1];
      Dec(j);
    end;
    Result[j] := C;
  end;
  { A deleted and an added range with the same name: next to each other
    they are one rewritten symbol, apart a move. }
  SetLength(Drop, Length(Result));
  for i := 0 to High(Result) do
  begin
    Drop[i] := False;
    if Result[i].Kind <> scDeleted then
      Continue;
    RA := ChangeRange(Result[i], ANew, AOld);
    for j := 0 to High(Result) do
    begin
      if (Result[j].Kind <> scAdded) or Drop[j] then
        Continue;
      RB := ChangeRange(Result[j], ANew, AOld);
      if Trim(RA.Symbol.Name) <> Trim(RB.Symbol.Name) then
        Continue;
      Lo := Min(RA.ToRow, RB.ToRow) + 1;
      Hi := Max(RA.FromRow, RB.FromRow) - 1;
      Adjacent := True;
      for r := Lo to Hi do
        if MarkerAt(ANew.Markers, r) = ' ' then
        begin
          Adjacent := False;
          Break;
        end;
      if Adjacent then
      begin
        Result[j].Kind := scChanged;
        Result[j].Deleted := Result[i].Deleted;
        Drop[i] := True;
      end
      else
      begin
        Result[i].Kind := scMovedFrom;
        Result[j].Kind := scMoved;
        Result[i].Other := j;
        Result[j].Other := i;
        Result[j].Same := BodyText(SideOf(Result[i]), RA, False, RowsA) =
          BodyText(SideOf(Result[j]), RB, False, RowsB);
        Result[i].Same := Result[j].Same;
      end;
      Break;
    end;
  end;
  { The rest with the same body under another name: a rename. The header
    row is left out of the body, and a body of one row proves nothing. }
  for i := 0 to High(Result) do
  begin
    if (Result[i].Kind <> scDeleted) or Drop[i] then
      Continue;
    RA := ChangeRange(Result[i], ANew, AOld);
    for j := 0 to High(Result) do
    begin
      if (Result[j].Kind <> scAdded) or Drop[j] then
        Continue;
      RB := ChangeRange(Result[j], ANew, AOld);
      if (BodyText(SideOf(Result[i]), RA, True, RowsA) <>
        BodyText(SideOf(Result[j]), RB, True, RowsB)) or (RowsA < 2) then
        Continue;
      Result[i].Kind := scRenamedFrom;
      Result[j].Kind := scRenamed;
      Result[i].Other := j;
      Result[j].Other := i;
      Break;
    end;
  end;
  { Take the merged deleted copies out, keeping the Other links right. }
  n := 0;
  for i := 0 to High(Result) do
    if not Drop[i] then
    begin
      Result[n] := Result[i];
      Inc(n);
    end;
  SetLength(Result, n);
  for i := 0 to High(Result) do
    if Result[i].Other >= 0 then
    begin
      k := Result[i].Other;
      for j := 0 to k - 1 do
        if Drop[j] then
          Dec(Result[i].Other);
    end;
end;

function ChangeDetail(const AChange: TGittanSymbolChange; const AOtherName: string): string;
begin
  case AChange.Kind of
    scAdded: Result := Format(rsAdded, [AChange.Added]);
    scDeleted: Result := Format(rsDeleted, [AChange.Deleted]);
    scMoved:
      if AChange.Same then
        Result := rsMovedHere
      else
        Result := rsMovedChanged;
    scMovedFrom: Result := rsMovedAway;
    scRenamed: Result := Format(rsRenamedFrom, [AOtherName]);
    scRenamedFrom: Result := Format(rsRenamedTo, [AOtherName]);
    else
      Result := Format(rsCounts, [AChange.Added, AChange.Deleted]);
  end;
end;

end.
