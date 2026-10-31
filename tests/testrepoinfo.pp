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
    procedure TestAdjustLineCounts;
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
    procedure TestGatherWorkTree;
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
  AssertTrue('npm manifest', FileCategory('package.json') = fcConfig);
  AssertTrue('npm lock', FileCategory('web/package-lock.json') = fcConfig);
  AssertTrue('composer lock', FileCategory('composer.lock') = fcConfig);
  AssertTrue('yarn lock', FileCategory('yarn.lock') = fcConfig);
  AssertTrue('yaml', FileCategory('.github/workflows/ci.YML') = fcConfig);
  AssertTrue('gemfile', FileCategory('Gemfile') = fcConfig);
  AssertTrue('makefile', FileCategory('Makefile') = fcConfig);
  AssertTrue('cmake', FileCategory('src/CMakeLists.txt') = fcConfig);
  AssertTrue('requirements over text', FileCategory('requirements.txt') = fcConfig);
  AssertTrue('dotfile', FileCategory('.gitignore') = fcConfig);
  AssertTrue('dot script', FileCategory('.eslintrc.js') = fcCode);
  AssertTrue('a manifest under tests', FileCategory('tests/fixture/package.json') = fcTest);
  AssertTrue('forge template', FileCategory('.github/ISSUE_TEMPLATE/bug.md') = fcConfig);
  AssertTrue('forge script', FileCategory('.gitlab/ci/build.sh') = fcConfig);
  AssertTrue('forge folder deeper', FileCategory('src/.github/a.md') = fcDocs);
end;

procedure TRepoInfoTest.TestParseComposition;
var
  C: TGittanComposition;
begin
  C := ParseComposition('a.pp'#0'b.png'#0'tests/t.pp'#0'README.md'#0'package.json'#0,
    'a.pp'#0'120'#10'tests/t.pp'#0'30'#10'README.md'#0'8'#10'package.json'#0'12'#10);
  AssertEquals('code files', 2, C[fcCode].Files);
  AssertEquals('code lines', 120, C[fcCode].Lines);
  AssertEquals('test files', 1, C[fcTest].Files);
  AssertEquals('test lines', 30, C[fcTest].Lines);
  AssertEquals('doc files', 1, C[fcDocs].Files);
  AssertEquals('doc lines', 8, C[fcDocs].Lines);
  AssertEquals('config files', 1, C[fcConfig].Files);
  AssertEquals('config lines', 12, C[fcConfig].Lines);
  C := ParseComposition('', '');
  AssertEquals('none', 0, C[fcCode].Files);
  { A line feed in a name: the lines stay with the whole name. }
  C := ParseComposition('src/a'#10'tests/b.pp'#0'c'#10#0,
    'src/a'#10'tests/b.pp'#0'5'#10'c'#10#0'7'#10);
  AssertEquals('code lines', 12, C[fcCode].Lines);
  AssertEquals('test lines', 0, C[fcTest].Lines);
end;

procedure TRepoInfoTest.TestAdjustLineCounts;
var
  C: string;
begin
  C := AdjustLineCounts('abc', 'abc:a.pp'#0'10'#10'abc:gone.pp'#0'4'#10'abc:bin.pp'#0'6'#10 +
    'abc:same.pp'#0'3'#10, '5'#9'2'#9'a.pp'#0'0'#9'4'#9'gone.pp'#0'7'#9'0'#9'new.pp'#0 +
    '-'#9'-'#9'bin.pp'#0);
  AssertEquals('changed, removed, made, binary, untouched',
    'a.pp'#0'13'#10'new.pp'#0'7'#10'same.pp'#0'3'#10, C);
  AssertEquals('no change', 'x'#0'1'#10, AdjustLineCounts('h', 'h:x'#0'1'#10, ''));
  AssertEquals('none', '', AdjustLineCounts('h', '', ''));
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
  ForceDirectories(IncludeTrailingPathDelimiter(FDir) + 'src');
  ForceDirectories(IncludeTrailingPathDelimiter(FDir) + 'tests');
  Put('src/x.pp', 'begin'#10'end.');
  Put('tests/t.pp', 'test');
  Git(['add', 'b.txt', 'src/x.pp', 'tests/t.pp']);
  Git(['-c', 'user.name=Other', 'commit', '-q', '-m', 'second']);
  Git(['tag', 'v1']);
  Git(['branch', 'topic']);
  Git(['remote', 'add', 'origin', 'https://github.com/example/demo.git']);
  Info := GatherRepoInfo(FDir, 5, 5);
  AssertTrue('ok: ' + Info.Error, Info.Ok);
  AssertEquals('branch', 'main', Info.Branch);
  AssertEquals('commits', 2, Info.Commits);
  AssertEquals('files', 4, Info.Files);
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
  AssertEquals('code files', 1, Info.Composition[fcCode].Files);
  AssertEquals('code lines', 2, Info.Composition[fcCode].Lines);
  AssertEquals('test files', 1, Info.Composition[fcTest].Files);
  AssertEquals('test lines', 1, Info.Composition[fcTest].Lines);
end;

procedure TRepoInfoRepoTest.TestGatherWorkTree;
var
  Info: TGittanRepoInfo;
begin
  Git(['init', '-q', '-b', 'main']);
  ForceDirectories(IncludeTrailingPathDelimiter(FDir) + 'src');
  Put('src/x.pp', 'begin'#10'end.');
  Put('a.txt', 'one');
  Git(['add', '-A']);
  Git(['commit', '-q', '-m', 'first']);
  Info := GatherRepoInfo(FDir, 5, 5);
  AssertEquals('code lines', 2, Info.Composition[fcCode].Lines);
  { The working tree's lines, read again with the commit's kept. }
  Put('src/x.pp', 'begin'#10'  a;'#10'  b;'#10'end.');
  Put('b.md', 'x'#10'y'#10'z');
  Git(['add', 'b.md']);
  DeleteFile(IncludeTrailingPathDelimiter(FDir) + 'a.txt');
  Info := GatherRepoInfo(FDir, 5, 5);
  AssertEquals('code lines', 4, Info.Composition[fcCode].Lines);
  AssertEquals('doc lines', 3, Info.Composition[fcDocs].Lines);
  { A new commit is counted anew. }
  Git(['commit', '-q', '-a', '-m', 'second']);
  Put('src/x.pp', 'end.');
  Info := GatherRepoInfo(FDir, 5, 5);
  AssertEquals('code lines after the commit', 1, Info.Composition[fcCode].Lines);
  AssertEquals('doc lines after the commit', 3, Info.Composition[fcDocs].Lines);
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
