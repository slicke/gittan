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
    {** The keeps of the file, in the order they were added. }
    function Items(const APath: string): TGittanKeepArray;
    {** Drops the keeps of the file that ALines does not hold. }
    procedure Prune(const APath: string; ALines: TStrings);
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

{** For every line of ALines, the index in AKeeps of the keep its pair
  is (both lines of a pair get it), or -1: each keep takes the nearest
  pair with its content that no keep took. }
function MatchKeeps(ALines: TStrings; const AKeeps: array of TGittanKeep): TIntegerDynArray;

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

function MatchKeeps(ALines: TStrings; const AKeeps: array of TGittanKeep): TIntegerDynArray;
type
  TCandidate = record
    Pair: TGittanKeep;
    Start, Index, Keep: integer;
  end;
var
  Cands: array of TCandidate;
  Pairs: TGittanKeepArray;
  i, j, k, n, Best, Dist, Old: integer;
begin
  Result := nil;
  SetLength(Result, ALines.Count);
  for i := 0 to High(Result) do
    Result[i] := -1;
  { Every pair of every block is a candidate for a keep. }
  Cands := nil;
  i := 0;
  while i < ALines.Count do
  begin
    if ALines[i][1] = ' ' then
    begin
      Inc(i);
      Continue;
    end;
    Pairs := BlockPairs(ALines, i);
    n := Length(Cands);
    SetLength(Cands, n + Length(Pairs));
    for k := 0 to High(Pairs) do
    begin
      Cands[n + k].Pair := Pairs[k];
      Cands[n + k].Start := i;
      Cands[n + k].Index := k;
      Cands[n + k].Keep := -1;
    end;
    while (i < ALines.Count) and (ALines[i][1] <> ' ') do
      Inc(i);
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
      Cands[Best].Keep := j;
  end;
  { A pair's deleted line is the Index-th of its block, its added line
    the Index-th after the deleted ones. }
  for k := 0 to High(Cands) do
    if Cands[k].Keep >= 0 then
    begin
      i := Cands[k].Start;
      Old := 0;
      while (i + Old < ALines.Count) and (ALines[i + Old][1] = '-') do
        Inc(Old);
      if Cands[k].Pair.HasOld then
        Result[i + Cands[k].Index] := Cands[k].Keep;
      if Cands[k].Pair.HasNew then
        Result[i + Old + Cands[k].Index] := Cands[k].Keep;
    end;
end;

function ApplyKeeps(ALines: TStrings; const AKeeps: array of TGittanKeep;
  out AKeptOf: TIntegerDynArray): integer;
var
  Match: TIntegerDynArray;
  Pairs: TGittanKeepArray;
  i, k, Keep, Old: integer;
  Out: TStringList;
  Olds, News: TStringList;

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
  Match := MatchKeeps(ALines, AKeeps);
  Out := TStringList.Create;
  Olds := TStringList.Create;
  News := TStringList.Create;
  try
    i := 0;
    while i < ALines.Count do
    begin
      if ALines[i][1] = ' ' then
      begin
        Emit(ALines[i], -1);
        Inc(i);
        Continue;
      end;
      Pairs := BlockPairs(ALines, i);
      Old := 0;
      while (i + Old < ALines.Count) and (ALines[i + Old][1] = '-') do
        Inc(Old);
      for k := 0 to High(Pairs) do
      begin
        if Pairs[k].HasOld then
          Keep := Match[i + k]
        else
          Keep := Match[i + Old + k];
        if Keep < 0 then
        begin
          if Pairs[k].HasOld then
            Olds.Add(Pairs[k].Old);
          if Pairs[k].HasNew then
            News.Add(Pairs[k].New);
        end
        else
        begin
          Inc(Result);
          Flush;
          if Pairs[k].HasNew then
            Emit(' ' + Pairs[k].New, Keep);
        end;
      end;
      Flush;
      while (i < ALines.Count) and (ALines[i][1] <> ' ') do
        Inc(i);
    end;
    ALines.Assign(Out);
    SetLength(AKeptOf, ALines.Count);
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

function TGittanKeeps.Items(const APath: string): TGittanKeepArray;
var
  i: integer;
begin
  i := IndexOf(APath);
  if i < 0 then
    Result := nil
  else
    Result := Copy(FLists[i]);
end;

procedure TGittanKeeps.Prune(const APath: string; ALines: TStrings);
var
  Match: TIntegerDynArray;
  Found: array of boolean;
  i, k, n: integer;
begin
  i := IndexOf(APath);
  if (i < 0) or (Length(FLists[i]) = 0) then
    Exit;
  Match := MatchKeeps(ALines, FLists[i]);
  Found := nil;
  SetLength(Found, Length(FLists[i]));
  for k := 0 to High(Match) do
    if Match[k] >= 0 then
      Found[Match[k]] := True;
  n := 0;
  for k := 0 to High(FLists[i]) do
    if Found[k] then
    begin
      FLists[i][n] := FLists[i][k];
      Inc(n);
    end;
  SetLength(FLists[i], n);
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
