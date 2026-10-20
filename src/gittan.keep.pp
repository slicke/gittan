unit gittan.keep;

{** Keeping a change: a changed line the user has looked at and
  accepted is shown as plain code, no longer as a diff, for the rest of
  the session. The file and git are not touched; only the diff the
  view is built from is rewritten.

  A kept change is one pair of a block: the k-th deleted line of the
  block with the k-th added line (as the side-by-side view shows
  them), a deleted line past the added ones, or
  an added line past the deleted ones. Keeping a whole block is
  keeping every pair of it. A keep is kept by its content (TGittanKeep)
  and found again in a fresh diff by it, so it survives the diff being
  taken again after the file changed elsewhere, and goes by itself when
  the lines it names are gone; Line, where the pair was, tells apart
  two pairs with the same text, the nearest wins.

  ApplyKeeps rewrites a diff (the whole file as context, ' ', '-' and
  '+' markers in column 1): a kept pair's deleted line is dropped and
  its added line becomes a context line, so the view paints it as code;
  the unkept pairs around it stay blocks of their own, so a block is
  split around a kept line. TGittanKeeps holds the keeps of every file
  of the session by path. No LCL; tested in tests/testkeep.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types;

type
  {** One pair of a block: the deleted line (HasOld) and the added line
    in its place (HasNew), and the new file's line the pair is at. }
  TGittanKeep = record
    HasOld, HasNew: boolean;
    Old, New: string;
    Line: integer;
  end;
  TGittanKeepArray = array of TGittanKeep;

  { TGittanKeeps }

  {** The keeps of every file, by path. }
  TGittanKeeps = class
  private
    FPaths: TStringList;
    FLists: array of TGittanKeepArray;
    function IndexOf(const APath: string): integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const APath: string; const AKeep: TGittanKeep);
    {** Removes the keep ApplyKeeps numbered AIndex. }
    procedure Remove(const APath: string; AIndex: integer);
    function Count(const APath: string): integer;
    procedure Clear(const APath: string);
    procedure ClearAll;
    {** ApplyKeeps with the file's keeps; AKeptOf gives, for every line
      of the rewritten diff, the keep it comes from, or -1. }
    procedure Apply(const APath: string; ALines: TStrings; out AKeptOf: TIntegerDynArray);
  end;

{** The pairs of the block that starts at diff line AStart, in order. }
function BlockPairs(ALines: TStrings; AStart: integer): TGittanKeepArray;

{** Whether two keeps name the same change (Line aside). }
function SameKeep(const A, B: TGittanKeep): boolean;

{** Rewrites ALines with the kept pairs as plain code (see the unit
  comment). AKeptOf gives, for every line of the result, the index in
  AKeeps of the keep it comes from, or -1. Returns how many keeps
  were found in the diff. }
function ApplyKeeps(ALines: TStrings; const AKeeps: array of TGittanKeep;
  out AKeptOf: TIntegerDynArray): integer;

implementation

uses
  gittan.discard;

function SameKeep(const A, B: TGittanKeep): boolean;
begin
  Result := (A.HasOld = B.HasOld) and (A.HasNew = B.HasNew) and
    (not A.HasOld or (A.Old = B.Old)) and (not A.HasNew or (A.New = B.New));
end;

function BlockPairs(ALines: TStrings; AStart: integer): TGittanKeepArray;
var
  B: TGittanDiscard;
  k, Old, New: integer;
begin
  B := DiffBlock(ALines, AStart, '');
  Old := Length(B.OldLines);
  New := Length(B.NewLines);
  Result := nil;
  if Old > New then
    SetLength(Result, Old)
  else
    SetLength(Result, New);
  for k := 0 to High(Result) do
  begin
    Result[k].HasOld := k < Old;
    Result[k].HasNew := k < New;
    Result[k].Old := '';
    Result[k].New := '';
    if Result[k].HasOld then
      Result[k].Old := B.OldLines[k];
    if Result[k].HasNew then
      Result[k].New := B.NewLines[k];
    if k < New then
      Result[k].Line := B.Line + k
    else
      Result[k].Line := B.Line + New;
  end;
end;

function ApplyKeeps(ALines: TStrings; const AKeeps: array of TGittanKeep;
  out AKeptOf: TIntegerDynArray): integer;
type
  TCandidate = record
    Pair: TGittanKeep;
    Keep: integer;
  end;
var
  Blocks: array of record
    Start, Next: integer;
    Pairs: TGittanKeepArray;
  end;
  Cands: array of TCandidate;
  Starts: array of integer;
  i, j, b, k, Best, Dist: integer;
  Out: TStringList;
  Olds, News: TStringList;
  Kept: TIntegerDynArray;

  procedure Emit(const ALine: string; AKeep: integer);
  begin
    Out.Add(ALine);
    SetLength(AKeptOf, Out.Count);
    AKeptOf[Out.Count - 1] := AKeep;
  end;

  procedure Flush;
  var
    n: integer;
  begin
    for n := 0 to Olds.Count - 1 do
      Emit('-' + Olds[n], -1);
    for n := 0 to News.Count - 1 do
      Emit('+' + News[n], -1);
    Olds.Clear;
    News.Clear;
  end;

begin
  Result := 0;
  AKeptOf := nil;
  Kept := nil;
  { The blocks and their pairs, every pair a candidate for a keep. }
  Blocks := nil;
  Cands := nil;
  Starts := nil;
  i := 0;
  while i < ALines.Count do
  begin
    if ALines[i][1] = ' ' then
    begin
      Inc(i);
      Continue;
    end;
    SetLength(Blocks, Length(Blocks) + 1);
    b := High(Blocks);
    Blocks[b].Start := i;
    Blocks[b].Pairs := BlockPairs(ALines, i);
    SetLength(Starts, b + 1);
    Starts[b] := Length(Cands);
    SetLength(Cands, Length(Cands) + Length(Blocks[b].Pairs));
    for k := 0 to High(Blocks[b].Pairs) do
    begin
      Cands[Starts[b] + k].Pair := Blocks[b].Pairs[k];
      Cands[Starts[b] + k].Keep := -1;
    end;
    while (i < ALines.Count) and (ALines[i][1] <> ' ') do
      Inc(i);
    Blocks[b].Next := i;
  end;
  if Length(Blocks) = 0 then
  begin
    SetLength(AKeptOf, ALines.Count);
    for i := 0 to High(AKeptOf) do
      AKeptOf[i] := -1;
    Exit;
  end;
  { Each keep takes the nearest pair with its content that no keep took. }
  for j := 0 to High(AKeeps) do
  begin
    Best := -1;
    for k := 0 to High(Cands) do
      if (Cands[k].Keep < 0) and SameKeep(Cands[k].Pair, AKeeps[j]) then
      begin
        Dist := Abs(Cands[k].Pair.Line - AKeeps[j].Line);
        if (Best < 0) or (Dist < Abs(Cands[Best].Pair.Line - AKeeps[j].Line)) then
          Best := k;
      end;
    if Best >= 0 then
    begin
      Cands[Best].Keep := j;
      Inc(Result);
    end;
  end;
  Out := TStringList.Create;
  Olds := TStringList.Create;
  News := TStringList.Create;
  try
    i := 0;
    b := 0;
    while i < ALines.Count do
    begin
      if (b > High(Blocks)) or (i < Blocks[b].Start) then
      begin
        Emit(ALines[i], -1);
        Inc(i);
        Continue;
      end;
      SetLength(Kept, Length(Blocks[b].Pairs));
      for k := 0 to High(Kept) do
        Kept[k] := Cands[Starts[b] + k].Keep;
      for k := 0 to High(Blocks[b].Pairs) do
        if Kept[k] < 0 then
        begin
          if Blocks[b].Pairs[k].HasOld then
            Olds.Add(Blocks[b].Pairs[k].Old);
          if Blocks[b].Pairs[k].HasNew then
            News.Add(Blocks[b].Pairs[k].New);
        end
        else
        begin
          Flush;
          if Blocks[b].Pairs[k].HasNew then
            Emit(' ' + Blocks[b].Pairs[k].New, Kept[k]);
        end;
      Flush;
      i := Blocks[b].Next;
      Inc(b);
    end;
    ALines.Assign(Out);
  finally
    News.Free;
    Olds.Free;
    Out.Free;
  end;
end;

{ TGittanKeeps }

constructor TGittanKeeps.Create;
begin
  inherited Create;
  FPaths := TStringList.Create;
  FPaths.CaseSensitive := True;
end;

destructor TGittanKeeps.Destroy;
begin
  FPaths.Free;
  inherited Destroy;
end;

function TGittanKeeps.IndexOf(const APath: string): integer;
begin
  Result := FPaths.IndexOf(APath);
end;

procedure TGittanKeeps.Add(const APath: string; const AKeep: TGittanKeep);
var
  i: integer;
begin
  i := IndexOf(APath);
  if i < 0 then
  begin
    i := FPaths.Add(APath);
    SetLength(FLists, i + 1);
    FLists[i] := nil;
  end;
  SetLength(FLists[i], Length(FLists[i]) + 1);
  FLists[i][High(FLists[i])] := AKeep;
end;

procedure TGittanKeeps.Remove(const APath: string; AIndex: integer);
var
  i, k: integer;
begin
  i := IndexOf(APath);
  if (i < 0) or (AIndex < 0) or (AIndex > High(FLists[i])) then
    Exit;
  for k := AIndex to High(FLists[i]) - 1 do
    FLists[i][k] := FLists[i][k + 1];
  SetLength(FLists[i], Length(FLists[i]) - 1);
end;

function TGittanKeeps.Count(const APath: string): integer;
var
  i: integer;
begin
  i := IndexOf(APath);
  if i < 0 then
    Result := 0
  else
    Result := Length(FLists[i]);
end;

procedure TGittanKeeps.Clear(const APath: string);
var
  i: integer;
begin
  i := IndexOf(APath);
  if i >= 0 then
    FLists[i] := nil;
end;

procedure TGittanKeeps.ClearAll;
begin
  FPaths.Clear;
  FLists := nil;
end;

procedure TGittanKeeps.Apply(const APath: string; ALines: TStrings;
  out AKeptOf: TIntegerDynArray);
var
  i: integer;
begin
  AKeptOf := nil;
  i := IndexOf(APath);
  if (i < 0) or (Length(FLists[i]) = 0) then
  begin
    SetLength(AKeptOf, ALines.Count);
    for i := 0 to High(AKeptOf) do
      AKeptOf[i] := -1;
    Exit;
  end;
  ApplyKeeps(ALines, FLists[i], AKeptOf);
end;

end.
