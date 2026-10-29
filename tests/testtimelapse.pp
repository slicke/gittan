unit testtimelapse;

{** Tests of gittan.timelapse: the versions made from a history and the
  newest text (each one checked against git's own copy of the file in a
  repository made for the test, through a change, an addition, a
  deletion, a rename and a merge), the commit each line came in with and
  the one that took it away, and a history that does not fit the text. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.git, gittan.history,
  gittan.timelapse, testhelpers;

type
  TTimelapseTest = class(TTestCase)
  private
    FDir: string;
    procedure Git(const AArgs: array of string);
    function GitOut(const AArgs: array of string): string;
    procedure WriteFile(const AName, AText: string);
    procedure Commit(const AMessage: string);
    function VersionText(T: TGittanTimelapse; ACommit: integer): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRepository;
    procedure TestLongHistory;
    procedure TestMisfitStops;
    procedure TestNotCommitted;
  end;

implementation

procedure TTimelapseTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-timelapse-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
end;

procedure TTimelapseTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TTimelapseTest.Git(const AArgs: array of string);
begin
  GitOut(AArgs);
end;

function TTimelapseTest.GitOut(const AArgs: array of string): string;
var
  Err: string;
begin
  if not RunGitIn(FDir, AArgs, Result, Err) then
    Fail('git ' + AArgs[0] + ' failed: ' + Err);
end;

{ The text as given, with LF line ends on every platform. }
procedure TTimelapseTest.WriteFile(const AName, AText: string);
var
  F: TFileStream;
begin
  F := TFileStream.Create(IncludeTrailingPathDelimiter(FDir) + AName, fmCreate);
  try
    if AText <> '' then
      F.WriteBuffer(AText[1], Length(AText));
  finally
    F.Free;
  end;
end;

procedure TTimelapseTest.Commit(const AMessage: string);
begin
  Git(['add', '-A']);
  Git(['commit', '-q', '-m', AMessage]);
end;

{ The version of commit ACommit as the file's text, every line ended. }
function TTimelapseTest.VersionText(T: TGittanTimelapse; ACommit: integer): string;
var
  Ids: TGittanEntryIds;
  i: integer;
begin
  Result := '';
  Ids := T.Lines(ACommit);
  for i := 0 to High(Ids) do
    Result := Result + T.Text(Ids[i]) + #10;
end;

procedure TTimelapseTest.TestRepository;
const
  Summaries: array[0..5] of string = ('merge', 'rename', 'delete', 'top', 'change', 'start');
var
  Repo: TGittanRepo;
  History: TGittanHistory;
  T: TGittanTimelapse;
  Log, Text, Path, Err, Blob: string;
  Ids: TGittanEntryIds;
  c: integer;
begin
  Git(['init', '-q', '-b', 'main']);
  WriteFile('a.txt', 'one'#10'two'#10'three'#10);
  Commit('start');
  WriteFile('a.txt', 'one'#10'TWO'#10'three'#10'four'#10);
  Commit('change');
  WriteFile('a.txt', 'zero'#10'one'#10'TWO'#10'three'#10'four'#10);
  Commit('top');
  WriteFile('a.txt', 'zero'#10'one'#10'TWO'#10'four'#10);
  Commit('delete');
  Git(['mv', 'a.txt', 'b.txt']);
  WriteFile('b.txt', 'zero'#10'one'#10'TWO'#10'four'#10'five'#10);
  Commit('rename');
  { A side branch changes the file; the merge brings it in, and only
    the merge is on the first parents. }
  Git(['checkout', '-q', '-b', 'side']);
  WriteFile('b.txt', 'zero'#10'one'#10'TWO'#10'middle'#10'four'#10'five'#10);
  Commit('side');
  Git(['checkout', '-q', 'main']);
  WriteFile('other.txt', 'x'#10);
  Commit('other');
  Git(['merge', '-q', '--no-ff', '-m', 'merge', 'side']);

  Repo := TGittanRepo.Create;
  History := TGittanHistory.Create;
  T := TGittanTimelapse.Create;
  try
    AssertTrue(Repo.Open(FDir));
    AssertTrue(Repo.FileTimeline('b.txt', '', 1000, Log, Text));
    AssertTrue(History.Parse(Log));
    AssertTrue(T.Build(History, Text));
    AssertEquals('one version per commit that changed it', 6, T.Count);
    AssertEquals(6, History.Count);
    for c := 0 to History.Count - 1 do
    begin
      AssertEquals(Summaries[c], History.Commits[c].Info.Summary);
      if c <= 1 then
        Path := 'b.txt'
      else
        Path := 'a.txt';
      if not RunGitIn(FDir, ['cat-file', 'blob', History.Commits[c].Info.Hash + ':' + Path],
        Blob, Err) then
        Fail(Err);
      AssertEquals('version of ' + Summaries[c], Blob, VersionText(T, c));
    end;
    { The newest version: zero one TWO middle four five. }
    Ids := T.Lines(0);
    AssertEquals(6, Length(Ids));
    AssertEquals('zero came with top', 3, T.Born(Ids[0]));
    AssertEquals('one is as old as the history', 5, T.Born(Ids[1]));
    AssertEquals('TWO came with change', 4, T.Born(Ids[2]));
    AssertEquals('middle came with the merge', 0, T.Born(Ids[3]));
    AssertEquals('five came with the rename', 1, T.Born(Ids[5]));
    AssertEquals(-1, T.Died(Ids[1]));
    { two was replaced by change, three taken away by delete. }
    Ids := T.Lines(5);
    AssertEquals('two', T.Text(Ids[1]));
    AssertEquals(4, T.Died(Ids[1]));
    AssertEquals('three', T.Text(Ids[2]));
    AssertEquals(2, T.Died(Ids[2]));
    AssertEquals('a line kept is one entry', T.Lines(0)[1], Ids[0]);
  finally
    T.Free;
    History.Free;
    Repo.Free;
  end;
end;

{ More commits than one stretch between versions kept whole: every
  version, asked for in any order, is git's copy of the file. Each commit
  drops lines at the top, adds one at the end and changes the last. }
procedure TTimelapseTest.TestLongHistory;
const
  Commits = TimelapseMarkEvery + 8;
  Order: array[0..5] of integer = (0, Commits - 1, TimelapseMarkEvery,
    TimelapseMarkEvery - 1, TimelapseMarkEvery + 3, TimelapseMarkEvery + 1);
var
  Repo: TGittanRepo;
  History: TGittanHistory;
  T: TGittanTimelapse;
  Log, Text, Body, Err, Blob: string;
  Blobs: array of string;
  c, j: integer;

  function BlobOf(ACommit: integer): string;
  begin
    if not RunGitIn(FDir, ['cat-file', 'blob', History.Commits[ACommit].Info.Hash + ':a.txt'],
      Result, Err) then
      Fail(Err);
  end;

  { The entry of version ACommit with the text AText, -1 for none. }
  function EntryOf(ACommit: integer; const AText: string): integer;
  var
    Ids: TGittanEntryIds;
    i: integer;
  begin
    Result := -1;
    Ids := T.Lines(ACommit);
    for i := 0 to High(Ids) do
      if T.Text(Ids[i]) = AText then
        Exit(Ids[i]);
  end;

begin
  Git(['init', '-q', '-b', 'main']);
  for c := 0 to Commits - 1 do
  begin
    Body := '';
    for j := c mod 7 to c + 2 do
      Body := Body + 'line ' + IntToStr(j) + #10;
    WriteFile('a.txt', Body + 'version ' + IntToStr(c div 5) + #10);
    Commit('c' + IntToStr(c));
  end;
  Repo := TGittanRepo.Create;
  History := TGittanHistory.Create;
  T := TGittanTimelapse.Create;
  try
    AssertTrue(Repo.Open(FDir));
    AssertTrue(Repo.FileTimeline('a.txt', '', 1000, Log, Text));
    AssertTrue(History.Parse(Log));
    AssertTrue(T.Build(History, Text));
    AssertEquals(Commits, T.Count);
    SetLength(Blobs, Commits);
    for c := 0 to Commits - 1 do
      Blobs[c] := BlobOf(c);
    { Back through the history, as the time-lapse steps. }
    for c := 0 to Commits - 1 do
      AssertEquals('version ' + IntToStr(c), Blobs[c], VersionText(T, c));
    { Forward, as it plays, and across the stretches. }
    for c := Commits - 1 downto 0 do
      AssertEquals('version ' + IntToStr(c), Blobs[c], VersionText(T, c));
    for j := 0 to High(Order) do
      AssertEquals('version ' + IntToStr(Order[j]), Blobs[Order[j]], VersionText(T, Order[j]));
    { "line 9" is in both versions around the first mark, kept between. }
    AssertTrue(EntryOf(TimelapseMarkEvery - 1, 'line 9') >= 0);
    AssertEquals('a line kept is one entry across a mark',
      EntryOf(TimelapseMarkEvery - 1, 'line 9'), EntryOf(TimelapseMarkEvery, 'line 9'));
  finally
    T.Free;
    History.Free;
    Repo.Free;
  end;
end;

{ The newest commit says it added a line the text does not have there:
  only its own version is kept. }
procedure TTimelapseTest.TestMisfitStops;
const
  HashA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  HashB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
var
  History: TGittanHistory;
  T: TGittanTimelapse;
begin
  History := TGittanHistory.Create;
  T := TGittanTimelapse.Create;
  try
    AssertTrue(History.Parse(
      #1 + HashA + #31'Anna'#31'2'#31'second'#10 +
      '@@ -1 +1 @@'#10 + '-old'#10 + '+new'#10 +
      #1 + HashB + #31'Bo'#31'1'#31'first'#10 +
      '@@ -0,0 +1 @@'#10 + '+old'#10));
    AssertTrue(T.Build(History, 'other'#10));
    AssertEquals(1, T.Count);
    AssertEquals(1, History.Count);
    AssertEquals('other', T.Text(T.Lines(0)[0]));
    AssertEquals(0, T.Born(T.Lines(0)[0]));
  finally
    T.Free;
    History.Free;
  end;
end;

{ A file HEAD lacks gives no time-lapse and no error, and its code
  history says it is not committed, so the frame says that instead of
  showing git's refusal. }
procedure TTimelapseTest.TestNotCommitted;
var
  Job: TGittanTimelapseJob;
  HJob: TGittanHistoryJob;
begin
  Git(['init', '-q', '-b', 'main']);
  WriteFile('b.txt', 'one'#10);
  Commit('start');
  WriteFile('new.txt', 'fresh'#10);
  Job := TGittanTimelapseJob.Create(FDir, 'new.txt', '');
  try
    Job.Start;
    Job.WaitFor;
    CheckSynchronize(0);
    AssertNull('no time-lapse', Job.Timelapse);
    AssertEquals('no error', '', Job.Error);
    AssertFalse(Job.Binary);
  finally
    Job.Free;
  end;
  { Code History says the same through NotCommitted. }
  HJob := TGittanHistoryJob.Create(FDir, 'new.txt', '', 1, 1, 10, False);
  try
    HJob.Start;
    HJob.WaitFor;
    CheckSynchronize(0);
    AssertTrue('not committed', HJob.NotCommitted);
    AssertNull(HJob.History);
    AssertEquals('', HJob.Error);
  finally
    HJob.Free;
  end;
  HJob := TGittanHistoryJob.Create(FDir, 'b.txt', '', 1, 1, 10, False);
  try
    HJob.Start;
    HJob.WaitFor;
    CheckSynchronize(0);
    AssertFalse(HJob.NotCommitted);
    AssertNotNull(HJob.Error, HJob.History);
  finally
    HJob.Free;
  end;
  { A tracked file still plays. }
  Job := TGittanTimelapseJob.Create(FDir, 'b.txt', '');
  try
    Job.Start;
    Job.WaitFor;
    CheckSynchronize(0);
    AssertEquals(Job.Error, '', Job.Error);
    AssertNotNull('a time-lapse', Job.Timelapse);
  finally
    Job.Free;
  end;
end;

initialization
  RegisterTest(TTimelapseTest);

end.
