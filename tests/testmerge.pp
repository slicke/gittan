unit testmerge;

{** Tests of gittan.merge. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry, gittan.merge, gittan.discard;

type
  TMergeTest = class(TTestCase)
  private
    FLines: TStringList;
    FDir: string;
    function Load(const ALines: array of string; ARebase: boolean = False): TGittanMerge;
    function Joined(const ALines: TStringArray): string;
    function JoinedInts(const AValues: TIntegerDynArray): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestChunks;
    procedure TestRebaseSwapsSides;
    procedure TestUntouchedKeepsMarkers;
    procedure TestPickLines;
    procedure TestOrderFollowsFirstTaken;
    procedure TestEmptySide;
    procedure TestPickEverywhere;
    procedure TestRows;
    procedure TestOriginsAndStarts;
    procedure TestDiff3Base;
    procedure TestAdjacentConflicts;
    procedure TestResultWrites;
  end;

implementation

uses
  testhelpers, gittan.textfile;

const
  Sample: array[0..10] of string = ('a', '<<<<<<< HEAD', 'm1', 'm2', '=======', 't1',
    '>>>>>>> feature', 'b', '<<<<<<< HEAD', 'x', '=======');

procedure TMergeTest.SetUp;
begin
  FLines := TStringList.Create;
  FDir := '';
end;

procedure TMergeTest.TearDown;
begin
  FLines.Free;
  if FDir <> '' then
    RemoveTree(FDir);
end;

function TMergeTest.Load(const ALines: array of string; ARebase: boolean): TGittanMerge;
var
  i: integer;
begin
  FLines.Clear;
  for i := 0 to High(ALines) do
    FLines.Add(ALines[i]);
  Result := TGittanMerge.Create(FLines, ARebase);
end;

function TMergeTest.Joined(const ALines: TStringArray): string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(ALines) do
  begin
    if i > 0 then
      Result := Result + '|';
    Result := Result + ALines[i];
  end;
end;

function TMergeTest.JoinedInts(const AValues: TIntegerDynArray): string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(AValues) do
    Result := Result + IntToStr(AValues[i]);
end;

procedure TMergeTest.TestChunks;
var
  M: TGittanMerge;
begin
  M := Load(['a', '<<<<<<< HEAD', 'm1', 'm2', '=======', 't1', '>>>>>>> feature', 'b']);
  try
    AssertEquals(3, M.ChunkCount);
    AssertFalse(M.Chunks[0].Conflict);
    AssertEquals('a', Joined(M.Chunks[0].Lines));
    AssertTrue(M.Chunks[1].Conflict);
    AssertEquals('m1|m2', Joined(M.Chunks[1].Sides[msMine]));
    AssertEquals('t1', Joined(M.Chunks[1].Sides[msTheirs]));
    AssertEquals('HEAD', M.Chunks[1].Names[msMine]);
    AssertEquals('feature', M.Chunks[1].Names[msTheirs]);
    AssertEquals(6, Length(M.Chunks[1].Lines));
    AssertEquals('b', Joined(M.Chunks[2].Lines));
    AssertEquals('1', JoinedInts(M.Conflicts));
    AssertEquals(0, M.ResolvedCount);
  finally
    M.Free;
  end;
end;

procedure TMergeTest.TestRebaseSwapsSides;
var
  M: TGittanMerge;
begin
  M := Load(['<<<<<<< upstream', 'u', '=======', 'mine', '>>>>>>> 1234567 (my commit)'], True);
  try
    AssertEquals('mine', Joined(M.Chunks[0].Sides[msMine]));
    AssertEquals('u', Joined(M.Chunks[0].Sides[msTheirs]));
    AssertEquals('1234567 (my commit)', M.Chunks[0].Names[msMine]);
    AssertEquals('upstream', M.Chunks[0].Names[msTheirs]);
  finally
    M.Free;
  end;
end;

procedure TMergeTest.TestUntouchedKeepsMarkers;
var
  M: TGittanMerge;
begin
  M := Load(['a', '<<<<<<< HEAD', 'm', '=======', 't', '>>>>>>> f', 'b']);
  try
    AssertEquals('a|<<<<<<< HEAD|m|=======|t|>>>>>>> f|b', Joined(M.Output));
    { Taking a line and dropping it again leaves the conflict as it was. }
    M.Pick(1, msMine, 0, True);
    M.Pick(1, msMine, 0, False);
    AssertFalse(M.Resolved(1));
    AssertEquals('a|<<<<<<< HEAD|m|=======|t|>>>>>>> f|b', Joined(M.Output));
  finally
    M.Free;
  end;
end;

procedure TMergeTest.TestPickLines;
var
  M: TGittanMerge;
begin
  M := Load(['a', '<<<<<<< HEAD', 'm1', 'm2', '=======', 't1', 't2', '>>>>>>> f', 'b']);
  try
    M.Pick(1, msMine, 1, True);
    AssertTrue(M.Resolved(1));
    AssertTrue(M.PickState(1, msMine) = psSome);
    AssertTrue(M.PickState(1, msTheirs) = psNone);
    AssertEquals('a|m2|b', Joined(M.Output));
    M.Pick(1, msTheirs, 0, True);
    AssertEquals('a|m2|t1|b', Joined(M.Output));
    M.PickAll(1, msMine, True);
    AssertTrue(M.PickState(1, msMine) = psAll);
    AssertEquals('a|m1|m2|t1|b', Joined(M.Output));
    M.PickAll(1, msMine, False);
    AssertEquals('a|t1|b', Joined(M.Output));
    AssertEquals(1, M.ResolvedCount);
    { An index outside the side is left alone. }
    M.Pick(1, msMine, 5, True);
    M.Pick(0, msMine, 0, True);
    AssertEquals('a|t1|b', Joined(M.Output));
  finally
    M.Free;
  end;
end;

procedure TMergeTest.TestOrderFollowsFirstTaken;
var
  M: TGittanMerge;
begin
  M := Load(['<<<<<<< HEAD', 'm', '=======', 't', '>>>>>>> f']);
  try
    M.PickAll(0, msTheirs, True);
    M.PickAll(0, msMine, True);
    AssertEquals('t|m', Joined(M.Output));
    { With both dropped the order starts over. }
    M.PickAll(0, msTheirs, False);
    M.PickAll(0, msMine, False);
    M.PickAll(0, msMine, True);
    M.PickAll(0, msTheirs, True);
    AssertEquals('m|t', Joined(M.Output));
  finally
    M.Free;
  end;
end;

procedure TMergeTest.TestEmptySide;
var
  M: TGittanMerge;
begin
  { Mine deleted the lines theirs changed: taking mine resolves the
    conflict with nothing in its place. }
  M := Load(['a', '<<<<<<< HEAD', '=======', 't', '>>>>>>> f', 'b']);
  try
    AssertEquals(0, Length(M.Chunks[1].Sides[msMine]));
    AssertTrue(M.PickState(1, msMine) = psNone);
    M.PickAll(1, msMine, True);
    AssertTrue(M.Resolved(1));
    AssertTrue(M.PickState(1, msMine) = psAll);
    AssertEquals('a|b', Joined(M.Output));
  finally
    M.Free;
  end;
end;

procedure TMergeTest.TestPickEverywhere;
var
  M: TGittanMerge;
begin
  M := Load(['<<<<<<< HEAD', 'm', '=======', 't', '>>>>>>> f', 'c', '<<<<<<< HEAD', 'n',
    '=======', 'u', '>>>>>>> f']);
  try
    M.Pick(0, msMine, 0, True);
    M.PickEverywhere(msTheirs);
    AssertEquals('t|c|u', Joined(M.Output));
    AssertEquals(2, M.ResolvedCount);
  finally
    M.Free;
  end;
end;

procedure TMergeTest.TestRows;
var
  M: TGittanMerge;
  R: TGittanMergeRows;
begin
  M := Load(['a', '<<<<<<< HEAD', 'm1', 'm2', '=======', 't1', '>>>>>>> f', 'b']);
  try
    R := M.Rows;
    AssertEquals(5, Length(R));
    AssertEquals(0, R[0].Chunk);
    AssertEquals(0, R[0].Line);
    AssertTrue(R[1].Header);
    AssertEquals(1, R[1].Chunk);
    AssertEquals(0, R[2].Mine);
    AssertEquals(0, R[2].Theirs);
    AssertEquals(1, R[3].Mine);
    AssertEquals(-1, R[3].Theirs);
    AssertEquals(-1, R[3].Line);
    AssertEquals(2, R[4].Chunk);
    AssertEquals(0, R[4].Line);
  finally
    M.Free;
  end;
end;

procedure TMergeTest.TestOriginsAndStarts;
var
  M: TGittanMerge;
begin
  M := Load(['a', '<<<<<<< HEAD', 'm1', 'm2', '=======', 't1', '>>>>>>> f', 'b']);
  try
    AssertEquals('03333330', JoinedInts(M.Origins));
    AssertEquals('017', JoinedInts(M.OutputStarts));
    M.Pick(1, msTheirs, 0, True);
    M.Pick(1, msMine, 1, True);
    AssertEquals('a|t1|m2|b', Joined(M.Output));
    AssertEquals('0210', JoinedInts(M.Origins));
    AssertEquals('013', JoinedInts(M.OutputStarts));
  finally
    M.Free;
  end;
end;

procedure TMergeTest.TestDiff3Base;
var
  M: TGittanMerge;
begin
  M := Load(['<<<<<<< HEAD', 'm', '||||||| base', 'o', '=======', 't', '>>>>>>> f']);
  try
    AssertEquals('m', Joined(M.Chunks[0].Sides[msMine]));
    AssertEquals('t', Joined(M.Chunks[0].Sides[msTheirs]));
    M.PickAll(0, msMine, True);
    AssertEquals('m', Joined(M.Output));
  finally
    M.Free;
  end;
end;

procedure TMergeTest.TestAdjacentConflicts;
var
  M: TGittanMerge;
begin
  M := Load(['<<<<<<< HEAD', 'm', '=======', 't', '>>>>>>> f', '<<<<<<< HEAD', 'n',
    '=======', 'u', '>>>>>>> f']);
  try
    AssertEquals(2, M.ChunkCount);
    AssertEquals('01', JoinedInts(M.Conflicts));
    M.PickAll(1, msTheirs, True);
    AssertEquals('<<<<<<< HEAD|m|=======|t|>>>>>>> f|u', Joined(M.Output));
  finally
    M.Free;
  end;
  { One left open at the end keeps its lines. }
  M := Load(Sample);
  try
    AssertEquals(4, M.ChunkCount);
    AssertEquals('x', Joined(M.Chunks[3].Sides[msMine]));
    AssertEquals('', M.Chunks[3].Names[msTheirs]);
    AssertEquals('as written, untouched',
      'a|<<<<<<< HEAD|m1|m2|=======|t1|>>>>>>> feature|b|<<<<<<< HEAD|x|=======',
      Joined(M.Output));
    M.PickAll(3, msMine, True);
    AssertEquals('mine taken, its markers gone',
      'a|<<<<<<< HEAD|m1|m2|=======|t1|>>>>>>> feature|b|x', Joined(M.Output));
  finally
    M.Free;
  end;
end;

procedure TMergeTest.TestResultWrites;
var
  M: TGittanMerge;
  Name, Err: string;
  B: TGittanDiscard;
  Lines: TStringList;
  F: TFileStream;
  Text: RawByteString;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-merge-' + IntToStr(GetProcessID);
  ForceDirectories(FDir);
  Name := IncludeTrailingPathDelimiter(FDir) + 'f.txt';
  Text := 'a'#13#10'<<<<<<< HEAD'#13#10'm'#13#10'======='#13#10't'#13#10'>>>>>>> f'#13#10'b'#13#10;
  F := TFileStream.Create(Name, fmCreate);
  try
    F.WriteBuffer(Text[1], Length(Text));
  finally
    F.Free;
  end;
  Lines := TStringList.Create;
  try
    AssertTrue(ReadMergeFile(Name, Lines));
    AssertEquals('<<<<<<< HEAD', Lines[1]);
    M := TGittanMerge.Create(Lines, False);
    try
      M.PickAll(1, msTheirs, True);
      B := M.ResultBlock(M.Output, Name);
      AssertTrue(DiscardBlock(B, Err));
      AssertTrue(ReadMergeFile(Name, Lines));
      AssertEquals('a|t|b', Lines[0] + '|' + Lines[1] + '|' + Lines[2]);
      AssertEquals(3, Lines.Count);
      { The line ends stay CRLF. }
      AssertEquals('a'#13#10't'#13#10'b'#13#10, string(ReadFileBytes(Name)));
      { Written once, the file no longer holds the conflict. }
      AssertFalse(DiscardBlock(B, Err));
      AssertEquals(rsDiscardStale, Err);
      { Undone, it does. }
      AssertTrue(DiscardBlock(Swapped(B), Err));
      AssertEquals(string(Text), string(ReadFileBytes(Name)));
    finally
      M.Free;
    end;
  finally
    Lines.Free;
  end;
end;

initialization
  RegisterTest(TMergeTest);

end.
