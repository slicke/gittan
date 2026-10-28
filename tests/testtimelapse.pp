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
    procedure TestMisfitStops;
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

initialization
  RegisterTest(TTimelapseTest);

end.
