unit testsubmodules;

{** Tests of gittan.submodules: reading .gitmodules, the index and
  ls-remote, relative URLs, and CheckSubmodule against a repository with
  a submodule whose remote is a folder made for the test; and of
  TGittanRepo's submodule update, sync and add. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.git, gittan.submodules, testhelpers;

type
  TSubmodulesTest = class(TTestCase)
  private
    FDir: string;
    function Git(const ADir: string; const AArgs: array of string): string;
    procedure CommitFile(const ADir, AName, AMessage: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestParseConfig;
    procedure TestIndexEntries;
    procedure TestRemoteRef;
    procedure TestLsRemote;
    procedure TestResolveUrl;
    procedure TestParseLog;
    procedure TestNoSubmodules;
    procedure TestCheck;
    procedure TestCheckNotInitialized;
    procedure TestParseGitlink;
    procedure TestCompare;
    procedure TestParseMoved;
    procedure TestSubmoduleFolder;
    procedure TestUpdateSyncAdd;
  end;

implementation

uses
  Process, testgit;

{ git refuses a local folder as a submodule's remote unless told
  otherwise, and the update and add of TGittanRepo run git themselves:
  every git the tests start is told through the environment. }
procedure AllowFileTransport;
var
  Count, i: integer;
begin
  Count := StrToIntDef(EnvironmentVariable('GIT_CONFIG_COUNT'), 0);
  for i := 0 to Count - 1 do
    if EnvironmentVariable('GIT_CONFIG_KEY_' + IntToStr(i)) = 'protocol.file.allow' then
      Exit;
  SetTestVariable('GIT_CONFIG_KEY_' + IntToStr(Count), 'protocol.file.allow');
  SetTestVariable('GIT_CONFIG_VALUE_' + IntToStr(Count), 'always');
  SetTestVariable('GIT_CONFIG_COUNT', IntToStr(Count + 1));
end;

procedure TSubmodulesTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-submodules-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
end;

procedure TSubmodulesTest.TearDown;
begin
  RemoveTree(FDir);
end;

{ Runs git in ADir with a fixed identity, local folders allowed as
  submodule remotes, and fails the test when it fails. }
function TSubmodulesTest.Git(const ADir: string; const AArgs: array of string): string;
var
  Args: array of string;
  Code, i: integer;
begin
  SetLength(Args, Length(AArgs) + 6);
  Args[0] := '-c';
  Args[1] := 'user.name=Gittan Test';
  Args[2] := '-c';
  Args[3] := 'user.email=test@example.invalid';
  Args[4] := '-c';
  Args[5] := 'protocol.file.allow=always';
  for i := 0 to High(AArgs) do
    Args[i + 6] := ProcessArg(AArgs[i]);
  if RunCommandIndir(ADir, 'git', Args, Result, Code, [poStderrToOutPut]) <> 0 then
    Fail('git could not be run');
  if Code <> 0 then
    Fail('git ' + AArgs[0] + ' failed: ' + Trim(Result));
end;

procedure TSubmodulesTest.CommitFile(const ADir, AName, AMessage: string);
begin
  with TStringList.Create do
  try
    Add(AMessage);
    SaveToFile(IncludeTrailingPathDelimiter(ADir) + AName);
  finally
    Free;
  end;
  Git(ADir, ['add', '-A']);
  Git(ADir, ['commit', '-q', '-m', AMessage]);
end;

procedure TSubmodulesTest.TestParseConfig;
var
  List: TGittanSubmodules;
begin
  ParseSubmoduleConfig('submodule.vendor/a.path'#10'vendor/a'#0 +
    'submodule.vendor/a.url'#10'https://example.com/a.git'#0 +
    'submodule.b.c.path'#10'lib/b c'#0 +
    'submodule.b.c.url'#10'../b.git'#0 +
    'submodule.b.c.branch'#10'main'#0 +
    'submodule.nopath.url'#10'x'#0, List);
  AssertEquals(2, Length(List));
  AssertEquals('vendor/a', List[0].Name);
  AssertEquals('vendor/a', List[0].Path);
  AssertEquals('https://example.com/a.git', List[0].Url);
  AssertEquals('', List[0].Branch);
  AssertEquals('b.c', List[1].Name);
  AssertEquals('lib/b c', List[1].Path);
  AssertEquals('../b.git', List[1].Url);
  AssertEquals('main', List[1].Branch);
end;

procedure TSubmodulesTest.TestIndexEntries;
var
  List: TGittanSubmodules;
begin
  SetLength(List, 2);
  List[0] := Default(TGittanSubmodule);
  List[0].Path := 'vendor/a';
  List[1] := Default(TGittanSubmodule);
  List[1].Path := 'b c';
  ApplyIndexEntries('100644 1111111111111111111111111111111111111111 0'#9'README'#0 +
    '160000 2222222222222222222222222222222222222222 0'#9'vendor/a'#0 +
    '160000 3333333333333333333333333333333333333333 1'#9'b c'#0 +
    '160000 4444444444444444444444444444444444444444 2'#9'b c'#0 +
    '160000 5555555555555555555555555555555555555555 3'#9'b c'#0, List);
  AssertEquals('2222222222222222222222222222222222222222', List[0].Recorded);
  AssertFalse(List[0].Conflict);
  AssertEquals('4444444444444444444444444444444444444444', List[1].Recorded);
  AssertTrue(List[1].Conflict);
end;

procedure TSubmodulesTest.TestRemoteRef;
begin
  AssertEquals('HEAD', SubmoduleRemoteRef('', 'main'));
  AssertEquals('refs/heads/dev', SubmoduleRemoteRef('dev', 'main'));
  AssertEquals('refs/heads/main', SubmoduleRemoteRef('.', 'main'));
  AssertEquals('HEAD', SubmoduleRemoteRef('.', ''));
end;

procedure TSubmodulesTest.TestLsRemote;
const
  Output = 'aaaa'#9'HEAD'#10'bbbb'#9'refs/remotes/origin/HEAD'#10 +
    'cccc'#9'refs/heads/main'#10;
begin
  AssertEquals('aaaa', ParseLsRemote(Output, 'HEAD'));
  AssertEquals('cccc', ParseLsRemote(Output, 'refs/heads/main'));
  AssertEquals('', ParseLsRemote(Output, 'refs/heads/dev'));
end;

procedure TSubmodulesTest.TestResolveUrl;
begin
  AssertEquals('https://github.com/o/x.git',
    ResolveSubmoduleUrl('https://github.com/o/r.git', '../x.git'));
  AssertEquals('https://github.com/o/r.git/x',
    ResolveSubmoduleUrl('https://github.com/o/r.git/', './x'));
  AssertEquals('https://github.com/p/x.git',
    ResolveSubmoduleUrl('https://github.com/o/r.git', '../../p/x.git'));
  AssertEquals('git@github.com:o/x.git',
    ResolveSubmoduleUrl('git@github.com:o/r.git', '../x.git'));
  AssertEquals('git@host:x.git', ResolveSubmoduleUrl('git@host:r.git', '../x.git'));
  AssertEquals('https://example.com/a.git',
    ResolveSubmoduleUrl('https://github.com/o/r.git', 'https://example.com/a.git'));
end;

procedure TSubmodulesTest.TestParseLog;
var
  Commits: TGittanSubmoduleCommits;
begin
  ParseSubmoduleLog('abcdef'#31'abc'#31'2026-10-01'#31'Ann Author'#31'Fix: a | b'#10 +
    'broken line'#10, Commits);
  AssertEquals(1, Length(Commits));
  AssertEquals('abcdef', Commits[0].Hash);
  AssertEquals('abc', Commits[0].Short);
  AssertEquals('2026-10-01', Commits[0].Date);
  AssertEquals('Ann Author', Commits[0].Author);
  AssertEquals('Fix: a | b', Commits[0].Subject);
end;

procedure TSubmodulesTest.TestNoSubmodules;
var
  List: TGittanSubmodules;
  Err: string;
begin
  Git(FDir, ['init', '-q']);
  AssertTrue(ListSubmodules(FDir, List, Err));
  AssertEquals(0, Length(List));
  { An empty .gitmodules is no submodules either. }
  with TStringList.Create do
  try
    SaveToFile(IncludeTrailingPathDelimiter(FDir) + SubmodulesFile);
  finally
    Free;
  end;
  AssertTrue(ListSubmodules(FDir, List, Err));
  AssertEquals(0, Length(List));
end;

{ An upstream repository, a repository with it as the submodule "lib",
  then new commits upstream: first unknown to the submodule, then
  fetched. }
procedure TSubmodulesTest.TestCheck;
var
  Up, Super, First, Lib: string;
  List: TGittanSubmodules;
  Err: string;
  Info: TGittanSubmoduleInfo;
begin
  Up := IncludeTrailingPathDelimiter(FDir) + 'up';
  Super := IncludeTrailingPathDelimiter(FDir) + 'super';
  ForceDirectories(Up);
  ForceDirectories(Super);
  Git(Up, ['init', '-q']);
  CommitFile(Up, 'a.txt', 'first');
  First := Trim(Git(Up, ['rev-parse', 'HEAD']));
  Git(Super, ['init', '-q']);
  Git(Super, ['submodule', 'add', '-q', Up, 'lib']);
  Git(Super, ['commit', '-q', '-m', 'add lib']);

  AssertTrue(Err, ListSubmodules(Super, List, Err));
  AssertEquals(1, Length(List));
  AssertEquals('lib', List[0].Path);
  AssertEquals(Up, List[0].Url);
  AssertEquals(First, List[0].Recorded);

  Info := CheckSubmodule(Super, List[0], '');
  AssertTrue(Info.Error, Info.State = smUpToDate);
  AssertTrue(Info.Initialized);
  AssertEquals(First, Info.CheckedOut);
  AssertEquals(First, Info.Tip);
  AssertEquals('first', Info.Recorded.Subject);

  CommitFile(Up, 'a.txt', 'second');
  CommitFile(Up, 'a.txt', 'third');
  Info := CheckSubmodule(Super, List[0], '');
  AssertTrue(Info.State = smNotFetched);
  AssertEquals(Trim(Git(Up, ['rev-parse', 'HEAD'])), Info.Tip);
  AssertEquals(-1, Info.Behind);

  Git(IncludeTrailingPathDelimiter(Super) + 'lib', ['fetch', '-q']);
  Info := CheckSubmodule(Super, List[0], '');
  AssertTrue(Info.State = smBehind);
  AssertEquals(2, Info.Behind);
  AssertEquals(0, Info.Ahead);
  AssertEquals(2, Length(Info.Incoming));
  AssertEquals('third', Info.Incoming[0].Subject);
  AssertEquals('second', Info.Incoming[1].Subject);
  AssertEquals('third', Info.TipCommit.Subject);
  AssertEquals(0, Length(Info.Outgoing));

  { A recorded commit past the remote's: listed as not on the remote,
    with the branches that have it once one does. }
  Lib := IncludeTrailingPathDelimiter(Super) + 'lib';
  Git(Lib, ['checkout', '-q', Info.Tip]);
  CommitFile(Lib, 'a.txt', 'fourth');
  List[0].Recorded := Trim(Git(Lib, ['rev-parse', 'HEAD']));
  Info := CheckSubmodule(Super, List[0], '');
  AssertTrue(Info.State = smAhead);
  AssertEquals(1, Info.Ahead);
  AssertEquals(0, Info.Behind);
  AssertEquals(1, Length(Info.Outgoing));
  AssertEquals('fourth', Info.Outgoing[0].Subject);
  AssertEquals('third', Info.TipCommit.Subject);
  AssertEquals(0, Length(Info.Holding));
  Git(Lib, ['push', '-q', 'origin', 'HEAD:refs/heads/side']);
  Git(Lib, ['fetch', '-q']);
  Info := CheckSubmodule(Super, List[0], '');
  AssertEquals(1, Length(Info.Holding));
  AssertEquals('origin/side', Info.Holding[0]);

  { A branch the remote does not have. }
  List[0].Branch := 'nope';
  Info := CheckSubmodule(Super, List[0], '');
  AssertTrue(Info.State = smFailed);
  AssertTrue(Info.Error <> '');
end;

{ A clone without --recursive has the submodule listed but not checked
  out: the remote is asked by the URL .gitmodules gives. }
procedure TSubmodulesTest.TestCheckNotInitialized;
var
  Up, Super, Clone: string;
  List: TGittanSubmodules;
  Err: string;
  Info: TGittanSubmoduleInfo;
begin
  Up := IncludeTrailingPathDelimiter(FDir) + 'up';
  Super := IncludeTrailingPathDelimiter(FDir) + 'super';
  Clone := IncludeTrailingPathDelimiter(FDir) + 'clone';
  ForceDirectories(Up);
  ForceDirectories(Super);
  Git(Up, ['init', '-q']);
  CommitFile(Up, 'a.txt', 'first');
  Git(Super, ['init', '-q']);
  Git(Super, ['submodule', 'add', '-q', Up, 'lib']);
  Git(Super, ['commit', '-q', '-m', 'add lib']);
  Git(FDir, ['clone', '-q', Super, Clone]);

  AssertTrue(Err, ListSubmodules(Clone, List, Err));
  AssertEquals(1, Length(List));
  Info := CheckSubmodule(Clone, List[0], '');
  AssertFalse(Info.Initialized);
  AssertEquals('', Info.CheckedOut);
  AssertTrue(Info.Error, Info.State = smUpToDate);

  CommitFile(Up, 'a.txt', 'second');
  Info := CheckSubmodule(Clone, List[0], '');
  AssertTrue(Info.State = smNotFetched);
end;

procedure TSubmodulesTest.TestParseGitlink;
begin
  AssertEquals('2222222222222222222222222222222222222222',
    ParseGitlink('160000 commit 2222222222222222222222222222222222222222'#9'vendor/a'#0));
  AssertEquals('', ParseGitlink('100644 blob 1111111111111111111111111111111111111111'#9'a'#0));
  AssertEquals('', ParseGitlink(''));
end;

{ The submodule checked out at a newer commit than HEAD records, then at
  an older one, then staged, then between two commits of the
  repository. }
procedure TSubmodulesTest.TestCompare;
var
  Up, Super, Lib, First, Third: string;
  List: TGittanSubmodules;
  Err: string;
  Change: TGittanSubmoduleChange;
begin
  Up := IncludeTrailingPathDelimiter(FDir) + 'up';
  Super := IncludeTrailingPathDelimiter(FDir) + 'super';
  Lib := IncludeTrailingPathDelimiter(Super) + 'lib';
  ForceDirectories(Up);
  ForceDirectories(Super);
  Git(Up, ['init', '-q']);
  CommitFile(Up, 'a.txt', 'first');
  First := Trim(Git(Up, ['rev-parse', 'HEAD']));
  Git(Super, ['init', '-q']);
  Git(Super, ['submodule', 'add', '-q', Up, 'lib']);
  Git(Super, ['commit', '-q', '-m', 'add lib']);
  AssertTrue(Err, ListSubmodules(Super, List, Err));

  Change := CompareSubmodule(Super, List[0], 'HEAD', '');
  AssertEquals(First, Change.FromHash);
  AssertEquals(First, Change.ToHash);
  AssertEquals(0, Change.Added);

  CommitFile(Up, 'a.txt', 'second');
  CommitFile(Up, 'a.txt', 'third');
  Third := Trim(Git(Up, ['rev-parse', 'HEAD']));
  Git(Lib, ['fetch', '-q']);
  Git(Lib, ['checkout', '-q', Third]);
  Change := CompareSubmodule(Super, List[0], 'HEAD', '');
  AssertEquals(First, Change.FromHash);
  AssertEquals(Third, Change.ToHash);
  AssertEquals('first', Change.FromCommit.Subject);
  AssertEquals('third', Change.ToCommit.Subject);
  AssertEquals(2, Change.Added);
  AssertEquals(0, Change.Removed);
  AssertEquals(2, Length(Change.Commits));
  AssertEquals('third', Change.Commits[0].Subject);
  AssertEquals('second', Change.Commits[1].Subject);
  AssertEquals(0, Length(Change.Dropped));

  Git(Super, ['add', 'lib']);
  Git(Super, ['commit', '-q', '-m', 'move lib']);
  Git(Lib, ['checkout', '-q', First]);
  Change := CompareSubmodule(Super, List[0], 'HEAD', '');
  AssertEquals(0, Change.Added);
  AssertEquals(2, Change.Removed);
  AssertEquals(2, Length(Change.Dropped));
  AssertEquals('third', Change.Dropped[0].Subject);

  Change := CompareSubmodule(Super, List[0], 'HEAD~1', 'HEAD');
  AssertEquals(First, Change.FromHash);
  AssertEquals(Third, Change.ToHash);
  AssertEquals(2, Change.Added);
end;

procedure TSubmodulesTest.TestParseMoved;
var
  Moved: TStringList;
begin
  Moved := TStringList.Create;
  try
    ParseMovedSubmodules(
      ' 1111111111111111111111111111111111111111 vendor/a (heads/main)'#10 +
      '+2222222222222222222222222222222222222222 lib/my lib (v1.0-2-g2222222)'#10 +
      '-3333333333333333333333333333333333333333 not/here'#10 +
      '+4444444444444444444444444444444444444444 no describe'#10, Moved);
    AssertEquals(2, Moved.Count);
    AssertEquals('lib/my lib', Moved.Names[0]);
    AssertEquals('2222222222222222222222222222222222222222', Moved.ValueFromIndex[0]);
    AssertEquals('no describe', Moved.Names[1]);
    ParseMovedSubmodules('', Moved);
    AssertEquals(0, Moved.Count);
  finally
    Moved.Free;
  end;
end;

procedure TSubmodulesTest.TestSubmoduleFolder;
var
  List: TGittanSubmodules;
begin
  List := nil;
  AssertEquals('none', '', SubmoduleFolder(List));
  SetLength(List, 1);
  List[0].Path := 'vendor/a';
  AssertEquals('vendor/', SubmoduleFolder(List));
  SetLength(List, 3);
  List[1].Path := 'vendor/b/c';
  List[2].Path := 'vendor/bc/d';
  AssertEquals('whole parts only', 'vendor/', SubmoduleFolder(List));
  List[0].Path := 'vendor/b/a';
  List[2].Path := 'vendor/b/d';
  AssertEquals('vendor/b/', SubmoduleFolder(List));
  List[2].Path := 'other/d';
  AssertEquals('no common folder', '', SubmoduleFolder(List));
  List[2].Path := 'd';
  AssertEquals('one at the root', '', SubmoduleFolder(List));
end;

{ A clone without its submodule: an update checks it out and its own
  submodule with it; moved on, the submodule is listed as moved and an
  update moves it back; a sync takes a new URL from .gitmodules into the
  config and the submodule's origin; an add clones a new one and stages
  it with .gitmodules, and refuses a path that is taken. }
procedure TSubmodulesTest.TestUpdateSyncAdd;
var
  Up, Deep, Super, Clone, Lib, Recorded, Output, Branch: string;
  Repo: TGittanRepo;
  Moved: TStringList;
  List: TGittanSubmodules;
  Err: string;
begin
  AllowFileTransport;
  Up := IncludeTrailingPathDelimiter(FDir) + 'up';
  Deep := IncludeTrailingPathDelimiter(FDir) + 'deep';
  Super := IncludeTrailingPathDelimiter(FDir) + 'super';
  Clone := IncludeTrailingPathDelimiter(FDir) + 'clone';
  ForceDirectories(Up);
  ForceDirectories(Deep);
  ForceDirectories(Super);
  Git(Deep, ['init', '-q']);
  CommitFile(Deep, 'd.txt', 'deep');
  Git(Up, ['init', '-q']);
  CommitFile(Up, 'a.txt', 'first');
  Git(Up, ['submodule', 'add', '-q', Deep, 'deep']);
  Git(Up, ['commit', '-q', '-m', 'add deep']);
  Git(Super, ['init', '-q']);
  Git(Super, ['submodule', 'add', '-q', Up, 'lib']);
  Git(Super, ['commit', '-q', '-m', 'add lib']);
  Git(FDir, ['clone', '-q', Super, Clone]);
  Lib := IncludeTrailingPathDelimiter(Clone) + 'lib';

  Repo := TGittanRepo.Create;
  Moved := TStringList.Create;
  try
    AssertTrue(Repo.Open(Clone));
    AssertFalse('not checked out', FileExists(Lib + PathDelim + 'a.txt'));
    AssertTrue(Repo.Error, Repo.UpdateSubmodules(''));
    AssertTrue(FileExists(Lib + PathDelim + 'a.txt'));
    AssertTrue('recursively', FileExists(Lib + PathDelim + 'deep' + PathDelim + 'd.txt'));
    AssertTrue(MovedSubmodules(Clone, '', Moved));
    AssertEquals(0, Moved.Count);

    Recorded := Trim(Git(Lib, ['rev-parse', 'HEAD']));
    CommitFile(Lib, 'b.txt', 'moved on');
    AssertTrue(MovedSubmodules(Clone, '', Moved));
    AssertEquals(1, Moved.Count);
    AssertEquals('lib', Moved.Names[0]);
    AssertEquals(Trim(Git(Lib, ['rev-parse', 'HEAD'])), Moved.ValueFromIndex[0]);
    AssertTrue(MovedSubmodules(Clone, 'lib', Moved));
    AssertEquals('one path', 1, Moved.Count);
    AssertTrue(Repo.Error, Repo.UpdateSubmodules('lib'));
    AssertEquals('back at the recorded commit', Recorded, Trim(Git(Lib, ['rev-parse', 'HEAD'])));

    Git(Clone, ['config', '-f', '.gitmodules', 'submodule.lib.url', Up + '-moved']);
    AssertTrue(Repo.Error, Repo.SyncSubmodules(''));
    AssertEquals(Up + '-moved', Trim(Git(Clone, ['config', 'submodule.lib.url'])));
    AssertEquals(Up + '-moved', Trim(Git(Lib, ['config', 'remote.origin.url'])));
    Git(Clone, ['checkout', '-q', '--', '.gitmodules']);
    AssertTrue(Repo.Error, Repo.SyncSubmodules('lib'));
    AssertEquals(Up, Trim(Git(Lib, ['config', 'remote.origin.url'])));

    AssertTrue(Repo.Error, Repo.AddSubmodule(Deep, 'vendor/deep', ''));
    AssertTrue(FileExists(Clone + PathDelim + 'vendor' + PathDelim + 'deep' + PathDelim +
      'd.txt'));
    AssertTrue(Err, ListSubmodules(Clone, List, Err));
    AssertEquals(2, Length(List));
    AssertEquals('vendor/deep', List[1].Path);
    AssertTrue('recorded in the index', List[1].Recorded <> '');
    Output := Git(Clone, ['status', '--porcelain']);
    AssertTrue(Output, Pos('A  vendor/deep', Output) > 0);
    AssertTrue(Output, Pos('M  .gitmodules', Output) > 0);
    AssertFalse('taken', Repo.AddSubmodule(Deep, 'vendor/deep', ''));
    AssertTrue(Repo.Error <> '');
    AssertFalse('no repository there', Repo.AddSubmodule(Deep + '-nothing', 'other', ''));
    AssertFalse('git removes what it made', DirectoryExists(Clone + PathDelim + 'other'));
    { The branch git made, master or main as init.defaultBranch says. }
    Branch := Trim(Git(Up, ['symbolic-ref', '--short', 'HEAD']));
    AssertTrue(Repo.Error, Repo.AddSubmodule(Up, 'branched', Branch));
    AssertEquals(Branch, Trim(Git(Clone, ['config', '-f', '.gitmodules',
      'submodule.branched.branch'])));
  finally
    Moved.Free;
    Repo.Free;
  end;
end;

initialization
  RegisterTest(TSubmodulesTest);

end.
