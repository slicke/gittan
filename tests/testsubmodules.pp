unit testsubmodules;

{** Tests of gittan.submodules: reading .gitmodules, the index and
  ls-remote, relative URLs, and CheckSubmodule against a repository with
  a submodule whose remote is a folder made for the test. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.submodules;

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
  end;

implementation

uses
  Process;

procedure RemoveTree(const ADir: string);
var
  Info: TSearchRec;
begin
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, Info) = 0 then
  try
    repeat
      if (Info.Name = '.') or (Info.Name = '..') then
        Continue;
      if Info.Attr and faDirectory <> 0 then
        RemoveTree(IncludeTrailingPathDelimiter(ADir) + Info.Name)
      else
        DeleteFile(IncludeTrailingPathDelimiter(ADir) + Info.Name);
    until FindNext(Info) <> 0;
  finally
    FindClose(Info);
  end;
  RemoveDir(ADir);
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
  Status, i: integer;
begin
  SetLength(Args, Length(AArgs) + 6);
  Args[0] := '-c';
  Args[1] := 'user.name=Gittan Test';
  Args[2] := '-c';
  Args[3] := 'user.email=test@example.invalid';
  Args[4] := '-c';
  Args[5] := 'protocol.file.allow=always';
  for i := 0 to High(AArgs) do
    Args[i + 6] := AArgs[i];
  if RunCommandIndir(ADir, 'git', Args, Result, Status, [poStderrToOutPut]) <> 0 then
    Fail('git could not be run');
  if Status <> 0 then
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
  Up, Super, First: string;
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

initialization
  RegisterTest(TSubmodulesTest);
end.
