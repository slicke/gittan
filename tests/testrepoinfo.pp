unit testrepoinfo;

{** Tests of gittan.repoinfo: the parsing of what git prints for the
  Repository page, the web address of a remote, the number formats, and
  one gathering against a small repository made with the real git. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.repoinfo, testhelpers;

type
  TRepoInfoTest = class(TTestCase)
  published
    procedure TestRemotes;
    procedure TestRemoteWebUrl;
    procedure TestShortlog;
    procedure TestShortlogMerge;
    procedure TestNameKey;
    procedure TestCountObjects;
    procedure TestTags;
    procedure TestCountLines;
    procedure TestGroupDigits;
    procedure TestFormatKiB;
    procedure TestFileCategory;
    procedure TestParseComposition;
  end;

  TRepoInfoRepoTest = class(TTestCase)
  private
    FDir: string;
    procedure Git(const AArgs: array of string);
    procedure Put(const ARel, AText: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestGather;
    procedure TestGatherEmpty;
    procedure TestGatherNotARepo;
  end;

implementation

uses
  Process, DateUtils;

{ TRepoInfoTest }

procedure TRepoInfoTest.TestRemotes;
var
  R: TGittanRemotes;
begin
  R := ParseRemotes('origin'#9'git@github.com:bjorn/gittan.git (fetch)'#10 +
    'origin'#9'git@github.com:bjorn/gittan.git (push)'#10 +
    'mirror'#9'https://example.org/git/gittan (fetch)'#10 +
    'mirror'#9'ssh://git@example.org/gittan (push)'#10 +
    'mirror'#9'ssh://git@example.org/second (push)'#10);
  AssertEquals('remotes', 2, Length(R));
  AssertEquals('origin', R[0].Name);
  AssertEquals('git@github.com:bjorn/gittan.git', R[0].Url);
  AssertEquals('git@github.com:bjorn/gittan.git', R[0].PushUrl);
  AssertEquals('the first push URL', 'ssh://git@example.org/gittan', R[1].PushUrl);
  AssertEquals('https://github.com/bjorn/gittan', R[0].Web);
  AssertEquals('mirror', R[1].Name);
  AssertEquals('https://example.org/git/gittan', R[1].Url);
  AssertEquals('https://example.org/git/gittan', R[1].Web);
  AssertEquals('none', 0, Length(ParseRemotes('')));
end;

procedure TRepoInfoTest.TestRemoteWebUrl;
begin
  AssertEquals('https://github.com/a/b', RemoteWebUrl('https://github.com/a/b.git'));
  AssertEquals('https://github.com/a/b', RemoteWebUrl('https://github.com/a/b/'));
  AssertEquals('https://gitlab.com/a/b', RemoteWebUrl('git@gitlab.com:a/b.git'));
  AssertEquals('https://host.example/a/b', RemoteWebUrl('ssh://git@host.example:2222/a/b.git'));
  AssertEquals('https://github.com/a/b', RemoteWebUrl('https://user:token@github.com/a/b.git'));
  AssertEquals('local path', '', RemoteWebUrl('/Users/bjorn/repos/b.git'));
  AssertEquals('relative path', '', RemoteWebUrl('../b'));
  AssertEquals('windows path', '', RemoteWebUrl('C:\repos\b'));
  AssertEquals('file url', '', RemoteWebUrl('file:///tmp/b'));
  AssertEquals('empty', '', RemoteWebUrl(''));
end;

procedure TRepoInfoTest.TestShortlog;
var
  C: TGittanContributors;
  Total: integer;
begin
  C := ParseShortlog('   120'#9'Björn Lindh'#10'    15'#9'Sam Okafor'#10'     2'#9'Inés Moreau'#10, 2, Total);
  AssertEquals('kept', 2, Length(C));
  AssertEquals('authors', 3, Total);
  AssertEquals('Björn Lindh', C[0].Name);
  AssertEquals(120, C[0].Commits);
  AssertEquals('Sam Okafor', C[1].Name);
  AssertEquals(15, C[1].Commits);
  C := ParseShortlog('', 5, Total);
  AssertEquals(0, Length(C));
  AssertEquals(0, Total);
end;

procedure TRepoInfoTest.TestShortlogMerge;
var
  C: TGittanContributors;
  Total: integer;
begin
  { The same name composed (ö) and decomposed (o + U+0308), and in
    another case: one author, named as the one with most commits, and
    the merged one moves up past a name that had more than any part. }
  C := ParseShortlog('    10'#9'Sam Okafor'#10'     7'#9'Bjo'#$CC#$88'rn Lindh'#10 +
    '     4'#9'Bj'#$C3#$B6'rn Lindh'#10'     1'#9'BJÖRN LINDH'#10, 5, Total);
  AssertEquals('authors', 2, Total);
  AssertEquals('merged', 2, Length(C));
  AssertEquals('Bjo'#$CC#$88'rn Lindh', C[0].Name);
  AssertEquals(12, C[0].Commits);
  AssertEquals('Sam Okafor', C[1].Name);
  AssertEquals(10, C[1].Commits);
end;

procedure TRepoInfoTest.TestNameKey;
begin
  AssertEquals('bjorn lindh', NameKey('Bj'#$C3#$B6'rn Lindh'));
  AssertEquals(NameKey('Bj'#$C3#$B6'rn Lindh'), NameKey('Bjo'#$CC#$88'rn Lindh'));
  AssertEquals('ines moreau', NameKey('In'#$C3#$A9's Moreau'));
  AssertEquals('lukasz', NameKey(#$C5#$81'ukasz'));
  AssertEquals('plain', NameKey('Plain'));
  AssertEquals('', NameKey(''));
  { Letters outside the tables are kept as they are. }
  AssertEquals(#$E6#$9D#$8E, NameKey(#$E6#$9D#$8E));
end;

procedure TRepoInfoTest.TestCountObjects;
begin
  AssertEquals(1536, ParseCountObjects('count: 12'#10'size: 512'#10'in-pack: 300'#10 +
    'packs: 1'#10'size-pack: 1024'#10'prune-packable: 0'#10'garbage: 0'#10'size-garbage: 0'#10));
  AssertEquals(0, ParseCountObjects(''));
end;

procedure TRepoInfoTest.TestTags;
var
  T: TGittanTagInfos;
begin
  T := ParseTags('v1.2.0'#9'1700000000'#10'v1.1.0'#9'1690000000'#10'odd line'#10);
  AssertEquals(2, Length(T));
  AssertEquals('v1.2.0', T[0].Name);
  AssertEquals(1700000000, DateTimeToUnix(T[0].Date));
  AssertEquals('v1.1.0', T[1].Name);
end;

procedure TRepoInfoTest.TestCountLines;
begin
  AssertEquals(3, CountLines('a'#10'b'#10#10'c'#10));
  AssertEquals(0, CountLines(''));
  AssertEquals(1, CountLines('only'));
end;

procedure TRepoInfoTest.TestGroupDigits;
begin
  AssertEquals('0', GroupDigits(0));
  AssertEquals('999', GroupDigits(999));
  AssertEquals('1'#$E2#$80#$89'000', GroupDigits(1000));
  AssertEquals('1'#$E2#$80#$89'234'#$E2#$80#$89'567', GroupDigits(1234567));
  AssertEquals('-12'#$E2#$80#$89'345', GroupDigits(-12345));
end;

procedure TRepoInfoTest.TestFormatKiB;
begin
  AssertEquals('312 KiB', FormatKiB(312));
  AssertEquals('1 MiB', FormatKiB(1024));
  AssertEquals('4.21 MiB', FormatKiB(4311));
  AssertEquals('1.02 GiB', FormatKiB(1069547));
  AssertEquals('0 KiB', FormatKiB(0));
end;

procedure TRepoInfoTest.TestFileCategory;
begin
  AssertTrue('code', FileCategory('src/core/gittan.git.pp') = fcCode);
  AssertTrue('tests folder', FileCategory('tests/testgit.pp') = fcTest);
  AssertTrue('test folder deep', FileCategory('lib/Test/data.json') = fcTest);
  AssertTrue('test name', FileCategory('web/app.test.ts') = fcTest);
  AssertTrue('a doc under tests', FileCategory('tests/README.md') = fcTest);
  AssertTrue('markdown', FileCategory('README.md') = fcDocs);
  AssertTrue('text', FileCategory('docs/notes.TXT') = fcDocs);
  AssertTrue('a file named test', FileCategory('test') = fcCode);
  AssertTrue('testing folder', FileCategory('testing/a.pp') = fcCode);
  AssertTrue('contest', FileCategory('contest.pp') = fcCode);
end;

procedure TRepoInfoTest.TestParseComposition;
var
  C: TGittanComposition;
begin
  C := ParseComposition('a.pp'#0'b.png'#0'tests/t.pp'#0'README.md'#0,
    'a.pp'#0'120'#10'tests/t.pp'#0'30'#10'README.md'#0'8'#10);
  AssertEquals('code files', 2, C[fcCode].Files);
  AssertEquals('code lines', 120, C[fcCode].Lines);
  AssertEquals('test files', 1, C[fcTest].Files);
  AssertEquals('test lines', 30, C[fcTest].Lines);
  AssertEquals('doc files', 1, C[fcDocs].Files);
  AssertEquals('doc lines', 8, C[fcDocs].Lines);
  C := ParseComposition('', '');
  AssertEquals('none', 0, C[fcCode].Files);
end;

{ TRepoInfoRepoTest }

procedure TRepoInfoRepoTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-repoinfo-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
end;

procedure TRepoInfoRepoTest.TearDown;
begin
  RemoveTree(FDir);
end;

{ Runs git in the test folder with a fixed identity and fails the test
  when it fails. }
procedure TRepoInfoRepoTest.Git(const AArgs: array of string);
var
  Args: array of string;
  Output: string;
  Code, i: integer;
begin
  SetLength(Args, Length(AArgs) + 4);
  Args[0] := '-c';
  Args[1] := 'user.name=Gittan Test';
  Args[2] := '-c';
  Args[3] := 'user.email=test@example.invalid';
  for i := 0 to High(AArgs) do
    Args[i + 4] := AArgs[i];
  if RunCommandIndir(FDir, 'git', Args, Output, Code, [poStderrToOutPut]) <> 0 then
    Fail('git could not be run');
  if Code <> 0 then
    Fail('git failed: ' + Output);
end;

procedure TRepoInfoRepoTest.Put(const ARel, AText: string);
begin
  with TStringList.Create do
  try
    Text := AText;
    SaveToFile(IncludeTrailingPathDelimiter(FDir) + ARel);
  finally
    Free;
  end;
end;

procedure TRepoInfoRepoTest.TestGather;
var
  Info: TGittanRepoInfo;
  Big: string;
  i: integer;
begin
  Git(['init', '-q', '-b', 'main']);
  Put('a.txt', 'one');
  Git(['add', 'a.txt']);
  Git(['commit', '-q', '-m', 'first']);
  { Some kilobytes that do not compress: git for Windows counts the
    objects' bytes rather than their disk blocks, and a few tiny loose
    objects make less than the one KiB count-objects counts in. }
  RandSeed := 1;
  SetLength(Big, 8192);
  for i := 1 to Length(Big) do
    Big[i] := Chr(Ord('a') + Random(26));
  Put('b.txt', Big);
  Git(['add', 'b.txt']);
  Git(['-c', 'user.name=Other', 'commit', '-q', '-m', 'second']);
  Git(['tag', 'v1']);
  Git(['branch', 'topic']);
  Git(['remote', 'add', 'origin', 'https://github.com/example/demo.git']);
  Info := GatherRepoInfo(FDir, 5, 5);
  AssertTrue('ok: ' + Info.Error, Info.Ok);
  AssertEquals('branch', 'main', Info.Branch);
  AssertEquals('commits', 2, Info.Commits);
  AssertEquals('files', 2, Info.Files);
  AssertEquals('local branches', 2, Info.LocalBranches);
  AssertEquals('remote branches', 0, Info.RemoteBranches);
  AssertEquals('tags', 1, Info.Tags);
  AssertEquals('newest tags', 1, Length(Info.NewestTags));
  AssertEquals('v1', Info.NewestTags[0].Name);
  AssertEquals('authors', 2, Info.Authors);
  AssertEquals('contributors', 2, Length(Info.Contributors));
  AssertEquals('submodules', 0, Info.Submodules);
  AssertEquals('remotes', 1, Length(Info.Remotes));
  AssertEquals('origin', Info.Remotes[0].Name);
  AssertEquals('https://github.com/example/demo', Info.Remotes[0].Web);
  AssertTrue('first commit', Info.FirstCommit > 0);
  AssertTrue('last commit', Info.LastCommit >= Info.FirstCommit);
  AssertTrue('size', Info.SizeKiB > 0);
  AssertEquals('text files', 2, Info.Composition[fcDocs].Files);
  AssertEquals('text lines', 2, Info.Composition[fcDocs].Lines);
  AssertEquals('code files', 0, Info.Composition[fcCode].Files);
end;

procedure TRepoInfoRepoTest.TestGatherEmpty;
var
  Info: TGittanRepoInfo;
begin
  Git(['init', '-q', '-b', 'main']);
  Info := GatherRepoInfo(FDir, 5, 5);
  AssertTrue('ok: ' + Info.Error, Info.Ok);
  AssertEquals('commits', 0, Info.Commits);
  AssertEquals('authors', 0, Info.Authors);
  AssertEquals('files', 0, Info.Files);
  AssertEquals('tags', 0, Info.Tags);
  AssertEquals('remotes', 0, Length(Info.Remotes));
end;

procedure TRepoInfoRepoTest.TestGatherNotARepo;
var
  Info: TGittanRepoInfo;
begin
  Info := GatherRepoInfo(FDir, 5, 5);
  AssertFalse('not ok', Info.Ok);
  AssertTrue('error', Info.Error <> '');
end;

initialization
  RegisterTest(TRepoInfoTest);
  RegisterTest(TRepoInfoRepoTest);

end.
