unit gittan.merge;

{** A conflicted file as the merge editor shows it: the file cut into
  chunks, the lines both sides agree on and the conflicts git left, and
  for each conflict the lines of the user's side (mine) and of the side
  that came in (theirs), which the user picks line by line into the
  result. Mine is git's ours, except in a rebase, where it is git's
  theirs (see TGittanConflictSide). A conflict with nothing picked stays
  in the result as git wrote it, markers and all. Nothing here needs
  the LCL; tested in tests/testmerge.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, gittan.conflicts, gittan.discard;

type
  {** The two sides of a conflict, in the user's terms. }
  TGittanMergeSide = (msMine, msTheirs);

  {** How much of one side of a conflict is picked. }
  TGittanPickState = (psNone, psSome, psAll);

  {** A run of the file: lines both sides agree on (Conflict False, the
    lines in Lines), or a conflict, Lines then its lines as the file
    holds them (the markers, both sides and the base), Sides the lines
    of mine and theirs, Names the names git wrote on the markers,
    Picked which lines of each side go into the result, Taken whether a
    side goes in at all (a side with no lines can be taken too, which
    resolves the conflict as that side's deletion) and TheirsFirst the
    order, theirs before mine when theirs was taken first. }
  TGittanMergeChunk = record
    Conflict: boolean;
    Lines: TStringArray;
    Sides: array[TGittanMergeSide] of TStringArray;
    Names: array[TGittanMergeSide] of string;
    Picked: array[TGittanMergeSide] of TBooleanDynArray;
    Taken: array[TGittanMergeSide] of boolean;
    TheirsFirst: boolean;
  end;

  {** A row of the two panes above the result, side by side: a line of
    a chunk both sides agree on (Line the index in Lines, on both
    sides), a conflict's header row (Header), or a row of a conflict,
    Mine and Theirs the index of the side's line on it or -1 where the
    shorter side is padded. }
  TGittanMergeRow = record
    Chunk: integer;
    Header: boolean;
    Line, Mine, Theirs: integer;
  end;
  TGittanMergeRows = array of TGittanMergeRow;

const
  {** Where a line of the result comes from, as Origins answers it. }
  moCommon = 0;
  moMine = 1;
  moTheirs = 2;
  moConflict = 3;

type
  { TGittanMerge }

  TGittanMerge = class
  private
    FChunks: array of TGittanMergeChunk;
    FFileLines: TStringArray;
    function GetChunk(AIndex: integer): TGittanMergeChunk;
    function GetChunkCount: integer;
    procedure TakeSide(AChunk: integer; ASide: TGittanMergeSide; ATaken: boolean);
  public
    {** Cuts ALines, the file's lines as they are on disk, into chunks.
      ARebase: git is rebasing, so its theirs is the user's side. }
    constructor Create(ALines: TStrings; ARebase: boolean);
    {** The chunk's index of every conflict, in order. }
    function Conflicts: TIntegerDynArray;
    {** Whether a side of the conflict in chunk AChunk is taken. }
    function Resolved(AChunk: integer): boolean;
    {** How many conflicts have a side taken. }
    function ResolvedCount: integer;
    {** How much of ASide of the conflict in chunk AChunk is picked. }
    function PickState(AChunk: integer; ASide: TGittanMergeSide): TGittanPickState;
    {** Picks or drops line ALine of ASide of the conflict in chunk
      AChunk; the side is taken while any of its lines is picked. }
    procedure Pick(AChunk: integer; ASide: TGittanMergeSide; ALine: integer; AOn: boolean);
    {** Picks or drops every line of ASide of the conflict in AChunk;
      for a side without lines, takes it or not. }
    procedure PickAll(AChunk: integer; ASide: TGittanMergeSide; AOn: boolean);
    {** Picks ASide whole, and drops the other, in every conflict. }
    procedure PickEverywhere(ASide: TGittanMergeSide);
    {** The rows of the two panes above the result. }
    function Rows: TGittanMergeRows;
    {** The result: the lines both sides agree on, the lines picked of
      each conflict with a side taken, and every other conflict as the
      file holds it. }
    function Output: TStringArray;
    {** For each line of Output, where it comes from (moCommon, moMine,
      moTheirs, or moConflict for a conflict not resolved). }
    function Origins: TIntegerDynArray;
    {** For each chunk, the line of Output it starts on. }
    function OutputStarts: TIntegerDynArray;
    {** The result as a block to write over the file AFileName:
      NewLines the file as it was read, OldLines AResult, from Line 1,
      so DiscardBlock refuses it when the file changed since, and Undo
      Discard puts the conflicts back. }
    function ResultBlock(const AResult: TStringArray; const AFileName: string): TGittanDiscard;
    property ChunkCount: integer read GetChunkCount;
    property Chunks[AIndex: integer]: TGittanMergeChunk read GetChunk;
    property FileLines: TStringArray read FFileLines;
  end;

{** Reads the file AFileName into ALines as DiscardBlock reads it, split
  at LF with a CR at the end taken off, so the result block matches the
  file. False when it cannot be read. }
function ReadMergeFile(const AFileName: string; ALines: TStrings): boolean;

implementation

uses
  gittan.textfile;

function ReadMergeFile(const AFileName: string; ALines: TStrings): boolean;
var
  i: integer;
begin
  ALines.Clear;
  try
    SplitLf(ReadFileBytes(AFileName), ALines);
  except
    Exit(False);
  end;
  for i := 0 to ALines.Count - 1 do
    ALines[i] := BareLine(ALines[i]);
  Result := True;
end;

procedure Append(var ALines: TStringArray; const AText: string);
begin
  SetLength(ALines, Length(ALines) + 1);
  ALines[High(ALines)] := AText;
end;

{ TGittanMerge }

constructor TGittanMerge.Create(ALines: TStrings; ARebase: boolean);
var
  Diff: TStringList;
  Roles: TIntegerDynArray;
  i, n: integer;
  Ours, Theirs: TGittanMergeSide;
  InConflict: boolean;

  procedure StartChunk(AConflict: boolean);
  begin
    n := Length(FChunks);
    SetLength(FChunks, n + 1);
    FChunks[n] := Default(TGittanMergeChunk);
    FChunks[n].Conflict := AConflict;
  end;

begin
  inherited Create;
  if ARebase then
  begin
    Ours := msTheirs;
    Theirs := msMine;
  end
  else
  begin
    Ours := msMine;
    Theirs := msTheirs;
  end;
  SetLength(FFileLines, ALines.Count);
  { ConflictRoles reads diff lines; every line of the file is one the
    diff would keep. }
  Diff := TStringList.Create;
  try
    for i := 0 to ALines.Count - 1 do
    begin
      FFileLines[i] := ALines[i];
      Diff.Add(' ' + ALines[i]);
    end;
    Roles := ConflictRoles(Diff);
  finally
    Diff.Free;
  end;
  n := -1;
  InConflict := False;
  for i := 0 to High(FFileLines) do
  begin
    if Roles[i] = crNone then
    begin
      if (n < 0) or InConflict then
        StartChunk(False);
      InConflict := False;
    end
    else if (Roles[i] = crMarker) and (Copy(FFileLines[i], 1, 7) = '<<<<<<<') then
    begin
      StartChunk(True);
      InConflict := True;
      FChunks[n].Names[Ours] := Trim(Copy(FFileLines[i], 9, MaxInt));
    end;
    Append(FChunks[n].Lines, FFileLines[i]);
    case Roles[i] of
      crOurs: Append(FChunks[n].Sides[Ours], FFileLines[i]);
      crTheirs: Append(FChunks[n].Sides[Theirs], FFileLines[i]);
      crMarker:
        if Copy(FFileLines[i], 1, 7) = '>>>>>>>' then
        begin
          FChunks[n].Names[Theirs] := Trim(Copy(FFileLines[i], 9, MaxInt));
          { The next line starts a chunk of its own, even another
            conflict's. }
          InConflict := True;
        end;
    end;
  end;
  for n := 0 to High(FChunks) do
  begin
    SetLength(FChunks[n].Picked[msMine], Length(FChunks[n].Sides[msMine]));
    SetLength(FChunks[n].Picked[msTheirs], Length(FChunks[n].Sides[msTheirs]));
  end;
end;

function TGittanMerge.GetChunk(AIndex: integer): TGittanMergeChunk;
begin
  Result := FChunks[AIndex];
end;

function TGittanMerge.GetChunkCount: integer;
begin
  Result := Length(FChunks);
end;

function TGittanMerge.Conflicts: TIntegerDynArray;
var
  i: integer;
begin
  Result := nil;
  for i := 0 to High(FChunks) do
    if FChunks[i].Conflict then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := i;
    end;
end;

function TGittanMerge.Resolved(AChunk: integer): boolean;
begin
  Result := FChunks[AChunk].Conflict and
    (FChunks[AChunk].Taken[msMine] or FChunks[AChunk].Taken[msTheirs]);
end;

function TGittanMerge.ResolvedCount: integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to High(FChunks) do
    if Resolved(i) then
      Inc(Result);
end;

function TGittanMerge.PickState(AChunk: integer; ASide: TGittanMergeSide): TGittanPickState;
var
  i, n: integer;
begin
  with FChunks[AChunk] do
  begin
    if not Taken[ASide] then
      Exit(psNone);
    n := 0;
    for i := 0 to High(Picked[ASide]) do
      if Picked[ASide][i] then
        Inc(n);
    if n = Length(Picked[ASide]) then
      Result := psAll
    else
      Result := psSome;
  end;
end;

{ Taking a side of a conflict with nothing taken yet puts it first. }
procedure TGittanMerge.TakeSide(AChunk: integer; ASide: TGittanMergeSide; ATaken: boolean);
begin
  with FChunks[AChunk] do
  begin
    if ATaken and not Taken[ASide] and not Taken[msMine] and not Taken[msTheirs] then
      TheirsFirst := ASide = msTheirs;
    Taken[ASide] := ATaken;
  end;
end;

procedure TGittanMerge.Pick(AChunk: integer; ASide: TGittanMergeSide; ALine: integer; AOn: boolean);
var
  i: integer;
  Any: boolean;
begin
  if (AChunk < 0) or (AChunk > High(FChunks)) or not FChunks[AChunk].Conflict or
    (ALine < 0) or (ALine > High(FChunks[AChunk].Picked[ASide])) then
    Exit;
  FChunks[AChunk].Picked[ASide][ALine] := AOn;
  Any := False;
  for i := 0 to High(FChunks[AChunk].Picked[ASide]) do
    Any := Any or FChunks[AChunk].Picked[ASide][i];
  TakeSide(AChunk, ASide, Any);
end;

procedure TGittanMerge.PickAll(AChunk: integer; ASide: TGittanMergeSide; AOn: boolean);
var
  i: integer;
begin
  if (AChunk < 0) or (AChunk > High(FChunks)) or not FChunks[AChunk].Conflict then
    Exit;
  for i := 0 to High(FChunks[AChunk].Picked[ASide]) do
    FChunks[AChunk].Picked[ASide][i] := AOn;
  TakeSide(AChunk, ASide, AOn);
end;

procedure TGittanMerge.PickEverywhere(ASide: TGittanMergeSide);
var
  i: integer;
  Other: TGittanMergeSide;
begin
  if ASide = msMine then
    Other := msTheirs
  else
    Other := msMine;
  for i := 0 to High(FChunks) do
    if FChunks[i].Conflict then
    begin
      PickAll(i, Other, False);
      PickAll(i, ASide, True);
    end;
end;

function TGittanMerge.Rows: TGittanMergeRows;
var
  c, i, n, Count: integer;

  procedure Add(AHeader: boolean; ALine, AMine, ATheirs: integer);
  begin
    if n > High(Result) then
      SetLength(Result, n * 2 + 16);
    Result[n].Chunk := c;
    Result[n].Header := AHeader;
    Result[n].Line := ALine;
    Result[n].Mine := AMine;
    Result[n].Theirs := ATheirs;
    Inc(n);
  end;

begin
  Result := nil;
  n := 0;
  for c := 0 to High(FChunks) do
    if not FChunks[c].Conflict then
    begin
      for i := 0 to High(FChunks[c].Lines) do
        Add(False, i, -1, -1);
    end
    else
    begin
      Add(True, -1, -1, -1);
      Count := Length(FChunks[c].Sides[msMine]);
      if Length(FChunks[c].Sides[msTheirs]) > Count then
        Count := Length(FChunks[c].Sides[msTheirs]);
      for i := 0 to Count - 1 do
      begin
        if i <= High(FChunks[c].Sides[msMine]) then
          if i <= High(FChunks[c].Sides[msTheirs]) then
            Add(False, -1, i, i)
          else
            Add(False, -1, i, -1)
        else
          Add(False, -1, -1, i);
      end;
    end;
  SetLength(Result, n);
end;

function TGittanMerge.Output: TStringArray;
var
  c, i: integer;

  procedure AddSide(ASide: TGittanMergeSide);
  var
    j: integer;
  begin
    if not FChunks[c].Taken[ASide] then
      Exit;
    for j := 0 to High(FChunks[c].Sides[ASide]) do
      if FChunks[c].Picked[ASide][j] then
        Append(Result, FChunks[c].Sides[ASide][j]);
  end;

begin
  Result := nil;
  for c := 0 to High(FChunks) do
    if FChunks[c].Conflict and Resolved(c) then
    begin
      if FChunks[c].TheirsFirst then
      begin
        AddSide(msTheirs);
        AddSide(msMine);
      end
      else
      begin
        AddSide(msMine);
        AddSide(msTheirs);
      end;
    end
    else
      for i := 0 to High(FChunks[c].Lines) do
        Append(Result, FChunks[c].Lines[i]);
end;

function TGittanMerge.Origins: TIntegerDynArray;
var
  c, i, n: integer;

  procedure Add(AOrigin: integer);
  begin
    SetLength(Result, n + 1);
    Result[n] := AOrigin;
    Inc(n);
  end;

  procedure AddSide(ASide: TGittanMergeSide; AOrigin: integer);
  var
    j: integer;
  begin
    if FChunks[c].Taken[ASide] then
      for j := 0 to High(FChunks[c].Picked[ASide]) do
        if FChunks[c].Picked[ASide][j] then
          Add(AOrigin);
  end;

begin
  Result := nil;
  n := 0;
  for c := 0 to High(FChunks) do
    if FChunks[c].Conflict and Resolved(c) then
    begin
      if FChunks[c].TheirsFirst then
      begin
        AddSide(msTheirs, moTheirs);
        AddSide(msMine, moMine);
      end
      else
      begin
        AddSide(msMine, moMine);
        AddSide(msTheirs, moTheirs);
      end;
    end
    else
      for i := 0 to High(FChunks[c].Lines) do
        if FChunks[c].Conflict then
          Add(moConflict)
        else
          Add(moCommon);
end;

function TGittanMerge.OutputStarts: TIntegerDynArray;
var
  c, j, Line: integer;
  s: TGittanMergeSide;
begin
  Result := nil;
  SetLength(Result, Length(FChunks));
  Line := 0;
  for c := 0 to High(FChunks) do
  begin
    Result[c] := Line;
    if FChunks[c].Conflict and Resolved(c) then
    begin
      for s := Low(TGittanMergeSide) to High(TGittanMergeSide) do
        if FChunks[c].Taken[s] then
          for j := 0 to High(FChunks[c].Picked[s]) do
            if FChunks[c].Picked[s][j] then
              Inc(Line);
    end
    else
      Inc(Line, Length(FChunks[c].Lines));
  end;
end;

function TGittanMerge.ResultBlock(const AResult: TStringArray;
  const AFileName: string): TGittanDiscard;
begin
  Result.FileName := AFileName;
  Result.Line := 1;
  Result.NewLines := Copy(FFileLines);
  Result.OldLines := Copy(AResult);
  Result.Resolved := False;
end;

end.
