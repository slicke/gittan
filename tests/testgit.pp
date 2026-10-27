unit testgit;

{** Tests of gittan.git. The status parsing is tested on its own; the
  rest runs the real git against a repository made in a temporary folder
  for each test, so git must be on PATH. }

{$mode objfpc}{$H+}

interface

uses
  { gittan.repoinfo first: its ParseTags is not the one tested here. }
  Classes, SysUtils, fpcunit, testregistry, gittan.repoinfo, gittan.git, gittan.history,
  gittan.graph, gittan.rebase, gittan.blame, gittan.conflicts, gittan.discard;

type
  TGitRepoTest = class(TTestCase)
  private
    FDir: string;
    FRepo: TGittanRepo;
    FCollected: string;
    function Git(const AArgs: array of string): string;
    procedure WriteFile(const APath, AContent: string);
    procedure Commit(const AMessage: string);
    procedure MakeHistory;
    function FindStat(const AStats: TGittanFileStats; const APath: string): TGittanFileStat;
    function Joined(AList: TStrings): string;
    procedure Collect(const AText: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestWindowsArg;
    procedure TestInsteadOf;
    procedure TestChangeKind;
    procedure TestStageFlags;
    procedure TestOpenNonRepo;
    procedure TestOpenSubfolderFindsRoot;
    procedure TestChangeStats;
    procedure TestChangeStatsUnreadable;
    procedure TestFileChanges;
    procedure TestIgnoreWhitespace;
    procedure TestSuppressBlankEmpty;
    procedure TestUnbornRepository;
    procedure TestBase;
    procedure TestRange;
    procedure TestFingerprint;
    procedure TestFiles;
    procedure TestGrep;
    procedure TestSnapshot;
    procedure TestSnapshotNoIndex;
    procedure TestBlame;
    procedure TestBlameSha256;
    procedure TestInputClosed;
    procedure TestConflictCrlf;
    procedure TestCommitRange;
    procedure TestLineHistory;
    procedure TestRemoteFor;
    procedure TestUserName;
    procedure TestFileBlob;
    procedure TestFileSize;
    procedure TestLfsPointer;
    procedure TestLfsFiles;
    procedure TestLfsDownload;
    procedure TestLastFetch;
    procedure TestFetchPullRequest;
    procedure TestDefaultBranchAndMergeBase;
    procedure TestAheadBehind;
    procedure TestCommitIdAndCount;
    procedure TestSyncCommits;
    procedure TestRecentCommits;
    procedure TestGraphCommits;
    procedure TestPathCommits;
    procedure TestOperation;
    procedure TestBranchesAndSwitch;
    procedure TestGoneBranches;
    procedure TestGoneUpstreams;
    procedure TestCommit;
    procedure TestCommitAmendAndHook;
    procedure TestCommitUnborn;
    procedure TestCommitParts;
    procedure TestCommitMerge;
    procedure TestToolSearchPath;
    procedure TestNodeManagerBins;
    procedure TestPushFetchPull;
    procedure TestPushHook;
    procedure TestPullDiverged;
    procedure TestRemoteEnvironment;
    procedure TestEnvironmentUtf8;
    procedure TestResolveMerge;
    procedure TestResolveRebase;
    procedure TestMarkResolvedAndAbort;
    procedure TestUnresolve;
    procedure TestContinueExtras;
    procedure TestSkip;
    procedure TestCommitActions;
    procedure TestCommitActionConflicts;
    procedure TestBranchManagement;
    procedure TestSwitchBlocked;
    procedure TestRevertFiles;
    procedure TestMoveAndRemove;
    procedure TestRebaseOnto;
    procedure TestBehindDefault;
    procedure TestUpstreamInReflog;
    procedure TestRebaseOntoConflicts;
    procedure TestRebaseStray;
    procedure TestRebaseInteractive;
    procedure TestRebaseInteractiveEdit;
    procedure TestRebaseInteractiveConflicts;
    procedure TestStashes;
    procedure TestStashConflicts;
    procedure TestForcePush;
    procedure TestParseGitVersion;
    procedure TestGitNotRun;
    procedure TestUpstream;
    procedure TestParseTags;
    procedure TestTags;
    procedure TestParseReflog;
    procedure TestReflog;
    procedure TestReflogMany;
    procedure TestParseCleanPreview;
    procedure TestClean;
    procedure TestParseTreeEntries;
    procedure TestTreeEntries;
    procedure TestCloneFolderName;
    procedure TestLooksLikeCloneUrl;
    procedure TestCloneAndInit;
    procedure TestEditRemotes;
    procedure TestParseBisectRefs;
    procedure TestBisect;
    procedure TestIsMailPatch;
    procedure TestPatches;
  end;

{** Sets a variable in the test's own environment, where every git the
  tests start finds it. }
procedure SetTestVariable(const AName, AValue: string);

implementation

uses
  {$ifdef unix}BaseUnix,{$endif} Types, Process;

const
  { A name git quotes C-style in its line output, to check that the -z
    forms come through as they are. Windows forbids a quote in a file
    name, so there the test settles for an apostrophe. }
  QuoteName = {$ifdef MSWINDOWS}'q''uote.txt'{$else}'q"uote.txt'{$endif};

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

procedure TGitRepoTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-test-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
  FRepo := TGittanRepo.Create;
end;

procedure TGitRepoTest.TearDown;
begin
  FRepo.Free;
  RemoveTree(FDir);
end;

{ Runs git in the test folder with a fixed identity and fails the test
  when it fails. }
function TGitRepoTest.Git(const AArgs: array of string): string;
var
  Args: array of string;
  Code, i: integer;
begin
  SetLength(Args, Length(AArgs) + 4);
  Args[0] := '-c';
  Args[1] := 'user.name=Gittan Test';
  Args[2] := '-c';
  Args[3] := 'user.email=test@example.invalid';
  for i := 0 to High(AArgs) do
    Args[i + 4] := ProcessArg(AArgs[i]);
  if RunCommandIndir(FDir, 'git', Args, Result, Code, [poStderrToOutPut]) <> 0 then
    Fail('git could not be run');
  if Code <> 0 then
    Fail('git ' + AArgs[0] + ' failed: ' + Trim(Result));
end;

{ Writes AContent as it is, so the line endings are what the test says. }
procedure TGitRepoTest.WriteFile(const APath, AContent: string);
var
  Stream: TFileStream;
  FileName: string;
begin
  FileName := IncludeTrailingPathDelimiter(FDir) + SetDirSeparators(APath);
  ForceDirectories(ExtractFileDir(FileName));
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    if AContent <> '' then
      Stream.WriteBuffer(AContent[1], Length(AContent));
  finally
    Stream.Free;
  end;
end;

procedure TGitRepoTest.Commit(const AMessage: string);
begin
  Git(['add', '-A']);
  Git(['commit', '-q', '-m', AMessage]);
end;

{ One commit with the files the tests change. }
procedure TGitRepoTest.MakeHistory;
begin
  Git(['init', '-q']);
  WriteFile('a.txt', 'one'#10'two'#10'three'#10);
  WriteFile('dir sp/fil å.txt', 'a'#10);
  WriteFile(QuoteName, 'x'#10);
  WriteFile('del.txt', 'gone'#10);
  WriteFile('staged.txt', 'old'#10);
  Commit('files');
end;

function TGitRepoTest.FindStat(const AStats: TGittanFileStats;
  const APath: string): TGittanFileStat;
var
  i: integer;
begin
  for i := 0 to High(AStats) do
    if AStats[i].Path = APath then
      Exit(AStats[i]);
  Fail('not in the stats: ' + APath);
  Result := Default(TGittanFileStat);
end;

function TGitRepoTest.Joined(AList: TStrings): string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to AList.Count - 1 do
    Result := Result + AList[i] + '|';
end;

{ As the C runtime of Windows reads it back: 2n backslashes and a quote
  are n backslashes and the end of the quotes, 2n+1 and a quote are n and
  a quote; other backslashes are themselves. }
procedure TGitRepoTest.TestInsteadOf;
begin
  { The longest prefix wins; a URL no rule fits stays as it is; the
    rules' lines are left out. }
  AssertEquals('remote.origin.url git@github.com:slicke/gittan.git'#10 +
    'remote.up.url https://example.org/a.git'#10 +
    'remote.work.url https://ghe.example.com/team/x'#10,
    ApplyInsteadOf('url.git@github.com:.insteadof gh:'#10 +
    'remote.origin.url gh:slicke/gittan.git'#10 +
    'url.https://ghe.example.com/.insteadof work:'#10 +
    'url.https://ghe.example.com/team/.insteadof work:t/'#10 +
    'remote.up.url https://example.org/a.git'#10 +
    'remote.work.url work:t/x'#10));
  AssertEquals('', ApplyInsteadOf(''));
end;

procedure TGitRepoTest.TestWindowsArg;
begin
  AssertEquals('plain', WindowsArg('plain'));
  AssertEquals('C:\dir\a.txt', WindowsArg('C:\dir\a.txt'));
  AssertEquals('""', WindowsArg(''));
  AssertEquals('"two words"', WindowsArg('two words'));
  AssertEquals('"\"quoted\" subject"', WindowsArg('"quoted" subject'));
  AssertEquals('"say \"hi\""', WindowsArg('say "hi"'));
  AssertEquals('"a\\\"b"', WindowsArg('a\"b'));
  AssertEquals('"C:\my dir\\"', WindowsArg('C:\my dir\'));
  AssertEquals('"tab'#9'here"', WindowsArg('tab'#9'here'));
end;

procedure TGitRepoTest.TestChangeKind;
begin
  AssertTrue(TGittanRepo.ChangeKind(' M') = ckModified);
  AssertTrue(TGittanRepo.ChangeKind('M ') = ckModified);
  AssertTrue(TGittanRepo.ChangeKind('MM') = ckModified);
  AssertTrue('type change counts as modified', TGittanRepo.ChangeKind(' T') = ckModified);
  AssertTrue(TGittanRepo.ChangeKind('A ') = ckAdded);
  AssertTrue(TGittanRepo.ChangeKind('AM') = ckAdded);
  AssertTrue(TGittanRepo.ChangeKind('D ') = ckDeleted);
  AssertTrue(TGittanRepo.ChangeKind(' D') = ckDeleted);
  AssertTrue('deleted after rename', TGittanRepo.ChangeKind('RD') = ckDeleted);
  AssertTrue(TGittanRepo.ChangeKind('R ') = ckRenamed);
  AssertTrue(TGittanRepo.ChangeKind('RM') = ckRenamed);
  AssertTrue(TGittanRepo.ChangeKind('C ') = ckRenamed);
  AssertTrue(TGittanRepo.ChangeKind('??') = ckUntracked);
  AssertTrue(TGittanRepo.ChangeKind('UU') = ckConflict);
  AssertTrue(TGittanRepo.ChangeKind('AU') = ckConflict);
  AssertTrue(TGittanRepo.ChangeKind('AA') = ckConflict);
  AssertTrue(TGittanRepo.ChangeKind('DD') = ckConflict);
  AssertTrue('empty is modified', TGittanRepo.ChangeKind('') = ckModified);
end;

procedure TGitRepoTest.TestStageFlags;
begin
  AssertEquals(flagUnstaged, TGittanRepo.StageFlags(' M'));
  AssertEquals(flagStaged, TGittanRepo.StageFlags('M '));
  AssertEquals(flagStaged or flagUnstaged, TGittanRepo.StageFlags('MM'));
  AssertEquals(flagStaged, TGittanRepo.StageFlags('A '));
  AssertEquals(flagStaged, TGittanRepo.StageFlags('R '));
  AssertEquals(0, TGittanRepo.StageFlags('??'));
  AssertEquals(0, TGittanRepo.StageFlags('!!'));
  AssertEquals(0, TGittanRepo.StageFlags(''));
  { Unmerged: both columns name the sides of the conflict. }
  AssertEquals(0, TGittanRepo.StageFlags('UU'));
  AssertEquals(0, TGittanRepo.StageFlags('AA'));
  AssertEquals(0, TGittanRepo.StageFlags('DU'));
end;

procedure TGitRepoTest.TestOpenNonRepo;
begin
  AssertFalse(FRepo.Open(FDir));
  AssertEquals('Not a git repository: ' + FDir, FRepo.Error);
  AssertEquals('', FRepo.Root);
  AssertFalse(FRepo.Open(IncludeTrailingPathDelimiter(FDir) + 'missing'));
  AssertEquals(1, Pos('Folder not found: ', FRepo.Error));
end;

procedure TGitRepoTest.TestOpenSubfolderFindsRoot;
var
  Top: string;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(IncludeTrailingPathDelimiter(FDir) + 'dir sp'));
  Top := Trim(Git(['rev-parse', '--show-toplevel']));
  AssertEquals(Top, FRepo.Root);
  AssertTrue(FileExists(IncludeTrailingPathDelimiter(FRepo.Root) + 'a.txt'));
  FRepo.Close;
  AssertEquals('', FRepo.Root);
end;

{ An untracked file that cannot be read when it is counted (gone since
  git listed it, or no permission) counts nothing instead of raising out
  of ChangeStats, which ended the watcher's thread. Root reads a file
  with mode 0, so the test has nothing to show then (a CI container). }
procedure TGitRepoTest.TestChangeStatsUnreadable;
var
  Stats: TGittanFileStats;
  S: TGittanFileStat;
  FileName: string;
begin
  {$ifdef unix}
  if FpGeteuid = 0 then
    Exit;
  MakeHistory;
  WriteFile('locked.txt', 'l1'#10'l2'#10);
  FileName := IncludeTrailingPathDelimiter(FDir) + 'locked.txt';
  AssertEquals(0, FpChmod(FileName, 0));
  try
    AssertTrue(FRepo.Open(FDir));
    AssertTrue(FRepo.ChangeStats(Stats));
    S := FindStat(Stats, 'locked.txt');
    AssertTrue(S.Kind = ckUntracked);
    AssertEquals(0, S.Added);
  finally
    FpChmod(FileName, &644);
  end;
  {$endif}
end;

procedure TGitRepoTest.TestChangeStats;
var
  Stats: TGittanFileStats;
  S: TGittanFileStat;
begin
  MakeHistory;
  WriteFile('a.txt', 'one'#10'zwei'#10'three'#10);
  Git(['mv', 'dir sp/fil å.txt', 'dir sp/ny.txt']);
  WriteFile(QuoteName, 'x'#10'y'#10);
  Git(['rm', '-q', 'del.txt']);
  WriteFile('staged.txt', 'new'#10);
  Git(['add', 'staged.txt']);
  WriteFile('new.txt', 'n1'#10'n2');
  WriteFile('bin.dat', 'ab'#0'cd');
  WriteFile('newdir/sub/inner.txt', 'i'#10);
  AssertTrue(FRepo.Open(FDir));
  AssertTrue(FRepo.ChangeStats(Stats));
  AssertEquals(8, Length(Stats));

  S := FindStat(Stats, 'a.txt');
  AssertTrue(S.Kind = ckModified);
  AssertEquals(1, S.Added);
  AssertEquals(1, S.Deleted);
  AssertFalse(S.Staged);
  AssertTrue(S.Unstaged);

  S := FindStat(Stats, 'dir sp/ny.txt');
  AssertTrue('a rename is listed under its new path', S.Kind = ckRenamed);
  AssertTrue(S.Staged);
  AssertEquals('the new path of a rename gets the counts', 1, S.Added);

  S := FindStat(Stats, QuoteName);
  AssertTrue(S.Kind = ckModified);
  AssertEquals(1, S.Added);
  AssertEquals(0, S.Deleted);

  S := FindStat(Stats, 'del.txt');
  AssertTrue(S.Kind = ckDeleted);
  AssertEquals(1, S.Deleted);
  AssertTrue(S.Staged);

  S := FindStat(Stats, 'staged.txt');
  AssertTrue(S.Kind = ckModified);
  AssertTrue(S.Staged);
  AssertFalse(S.Unstaged);

  S := FindStat(Stats, 'new.txt');
  AssertTrue(S.Kind = ckUntracked);
  AssertEquals('an unterminated last line counts', 2, S.Added);
  AssertFalse(S.Staged or S.Unstaged);

  S := FindStat(Stats, 'bin.dat');
  AssertTrue(S.Kind = ckUntracked);
  AssertTrue(S.Binary);
  AssertEquals(0, S.Added);

  S := FindStat(Stats, 'newdir/sub/inner.txt');
  AssertTrue('a file in an untracked directory is listed by itself, not as the directory',
    S.Kind = ckUntracked);
  AssertEquals(1, S.Added);
end;

procedure TGitRepoTest.TestFileChanges;
var
  Lines: TStringList;
begin
  MakeHistory;
  WriteFile('a.txt', 'one'#10'zwei'#10'three'#10);
  WriteFile('new.txt', 'n1'#10'n2');
  Git(['rm', '-q', 'del.txt']);
  AssertTrue(FRepo.Open(FDir));
  Lines := TStringList.Create;
  try
    AssertTrue(FRepo.FileChanges('a.txt', Lines));
    AssertEquals(' one|-two|+zwei| three|', Joined(Lines));
    AssertTrue(FRepo.FileChanges('new.txt', Lines));
    AssertEquals('an untracked file is all new', '+n1|+n2|', Joined(Lines));
    AssertTrue(FRepo.FileChanges('del.txt', Lines));
    AssertEquals('a deleted file is all gone', '-gone|', Joined(Lines));
    AssertTrue(FRepo.FileChanges('staged.txt', Lines));
    AssertEquals('an unchanged tracked file is shown as it is', ' old|', Joined(Lines));
  finally
    Lines.Free;
  end;
end;

procedure TGitRepoTest.TestIgnoreWhitespace;
var
  Lines: TStringList;
  Stats: TGittanFileStats;
begin
  MakeHistory;
  WriteFile('a.txt', 'one'#10'two  '#10'three'#10);
  AssertTrue(FRepo.Open(FDir));
  Lines := TStringList.Create;
  try
    AssertTrue(FRepo.FileChanges('a.txt', Lines));
    AssertEquals(' one|-two|+two  | three|', Joined(Lines));
    FRepo.IgnoreWhitespace := True;
    AssertTrue(FRepo.FileChanges('a.txt', Lines));
    AssertEquals('with -w the file has no changes', ' one| two  | three|', Joined(Lines));
    AssertTrue(FRepo.ChangeStats(Stats));
    AssertEquals(1, Length(Stats));
    AssertEquals(0, Stats[0].Added + Stats[0].Deleted);
  finally
    Lines.Free;
  end;
end;

procedure TGitRepoTest.TestSuppressBlankEmpty;
var
  Lines: TStringList;
begin
  Git(['init', '-q']);
  WriteFile('a.txt', 'one'#10#10'two'#10'three'#10);
  Commit('first');
  Git(['config', 'diff.suppressBlankEmpty', 'true']);
  WriteFile('a.txt', 'one'#10#10'two'#10'drei'#10);
  AssertTrue(FRepo.Open(FDir));
  Lines := TStringList.Create;
  try
    AssertTrue(FRepo.FileChanges('a.txt', Lines));
    AssertEquals('the blank context line is kept', ' one| | two|-three|+drei|',
      Joined(Lines));
  finally
    Lines.Free;
  end;
end;

procedure TGitRepoTest.TestUnbornRepository;
var
  Stats: TGittanFileStats;
  Lines: TStringList;
begin
  Git(['init', '-q']);
  WriteFile('first.txt', 'hello'#10);
  AssertTrue(FRepo.Open(FDir));
  AssertTrue('the branch is named before its first commit', FRepo.Branch <> '');
  AssertTrue(FRepo.ChangeStats(Stats));
  AssertEquals(1, Length(Stats));
  AssertTrue(Stats[0].Kind = ckUntracked);
  Git(['add', 'first.txt']);
  AssertTrue('the empty tree stands in for HEAD', FRepo.ChangeStats(Stats));
  AssertEquals(1, Length(Stats));
  AssertTrue(Stats[0].Kind = ckAdded);
  AssertEquals(1, Stats[0].Added);
  Lines := TStringList.Create;
  try
    AssertTrue(FRepo.FileChanges('first.txt', Lines));
    AssertEquals('+hello|', Joined(Lines));
  finally
    Lines.Free;
  end;
  AssertTrue(FRepo.Fingerprint <> '');
end;

procedure TGitRepoTest.TestBase;
var
  Stats: TGittanFileStats;
  Refs: TStringList;
begin
  MakeHistory;
  Git(['tag', 'first']);
  WriteFile('a.txt', 'one'#10'two'#10'three'#10'four'#10);
  Commit('second');
  WriteFile('new.txt', 'n'#10);
  AssertTrue(FRepo.Open(FDir));
  AssertTrue(FRepo.ChangeStats(Stats));
  AssertEquals('against HEAD only the untracked file', 1, Length(Stats));

  FRepo.Base := 'first';
  AssertTrue(FRepo.ChangeStats(Stats));
  AssertEquals(2, Length(Stats));
  AssertTrue(FindStat(Stats, 'a.txt').Kind = ckModified);
  AssertEquals(1, FindStat(Stats, 'a.txt').Added);
  AssertFalse('no stage flags against a base', FindStat(Stats, 'a.txt').Staged);
  AssertTrue(FindStat(Stats, 'new.txt').Kind = ckUntracked);

  Refs := TStringList.Create;
  try
    AssertTrue(FRepo.Refs(Refs));
    AssertTrue(Refs.IndexOf('first') >= 0);
    AssertTrue(Refs.IndexOf(FRepo.Branch) >= 0);
  finally
    Refs.Free;
  end;

  FRepo.Base := 'no-such-ref';
  AssertFalse('an unknown base is an error', FRepo.ChangeStats(Stats));
  AssertTrue(FRepo.Error <> '');
end;

{ A range compares two commits: the work tree and its untracked files
  are out, a file without a diff comes from the right commit, and the
  three-dot form takes the branch's changes since the merge base. }
procedure TGitRepoTest.TestRange;
var
  Stats: TGittanFileStats;
  Lines: TStringList;
  Main: string;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  Main := FRepo.Branch;
  Git(['tag', 'first']);
  Git(['checkout', '-q', '-b', 'feature']);
  WriteFile('a.txt', 'one'#10'two'#10'three'#10'four'#10);
  Commit('on feature');
  Git(['checkout', '-q', Main]);

  WriteFile('del.txt', 'gone'#10'later'#10);
  Commit('on main');
  WriteFile('new.txt', 'n'#10);

  FRepo.Base := 'first..feature';
  AssertTrue(FRepo.IsRange);
  AssertTrue(FRepo.ChangeStats(Stats));
  AssertEquals('only the commits count', 1, Length(Stats));
  AssertEquals('a.txt', Stats[0].Path);
  AssertEquals(1, Stats[0].Added);
  Lines := TStringList.Create;
  try
    AssertTrue(FRepo.FileChanges('a.txt', Lines));
    AssertEquals(4, Lines.Count);
    AssertEquals('+four', Lines[3]);
    { The merge base of main and feature is "first", so main's own
      commit is left out; del.txt has no diff and is read from feature. }
    FRepo.Base := Main + '...feature';
    AssertTrue(FRepo.ChangeStats(Stats));
    AssertEquals(1, Length(Stats));
    AssertEquals('a.txt', Stats[0].Path);
    AssertTrue(FRepo.FileChanges('del.txt', Lines));
    AssertEquals(1, Lines.Count);
    AssertEquals(' gone', Lines[0]);
    FRepo.Base := Main + '..feature';
    AssertTrue(FRepo.ChangeStats(Stats));
    AssertEquals('two commits apart', 2, Length(Stats));
  finally
    Lines.Free;
  end;
  AssertTrue(FRepo.Fingerprint <> '');
end;

procedure TGitRepoTest.TestFingerprint;

var
  A, B: string;
begin
  MakeHistory;
  WriteFile('a.txt', 'one'#10'zwei'#10'three'#10);
  WriteFile('new.txt', 'n'#10);
  AssertTrue(FRepo.Open(FDir));
  A := FRepo.Fingerprint;
  AssertTrue(A <> '');
  AssertEquals('stable while nothing changes', A, FRepo.Fingerprint);
  { An edit that keeps the size and the line count. }
  WriteFile('a.txt', 'one'#10'drei'#10'three'#10);
  B := FRepo.Fingerprint;
  AssertTrue('content change seen', A <> B);
  WriteFile('new.txt', 'm'#10);
  A := FRepo.Fingerprint;
  AssertTrue('untracked content change seen', A <> B);
  Git(['commit', '-q', '--amend', '--allow-empty', '-m', 'files again']);
  B := FRepo.Fingerprint;
  AssertTrue('a moved HEAD seen', A <> B);
  Git(['add', 'a.txt']);
  A := FRepo.Fingerprint;
  AssertTrue('staging seen', A <> B);
  { A fetch moves the upstream alone, which the ahead and behind counts
    follow. }
  Git(['branch', 'up']);
  Git(['branch', '-q', '--set-upstream-to=up']);
  A := FRepo.Fingerprint;
  Git(['update-ref', 'refs/heads/up', Trim(Git(['commit-tree', 'HEAD^{tree}', '-p', 'HEAD',
    '-m', 'fetched'])), 'HEAD']);
  B := FRepo.Fingerprint;
  AssertTrue('a moved upstream seen', A <> B);
  { A bisect started on a clean tree moves nothing else. }
  Git(['bisect', 'start']);
  A := FRepo.Fingerprint;
  AssertTrue('an operation begun seen', A <> B);
  Git(['bisect', 'reset']);
end;

{ A snapshot holds the untracked files, and the whole tree comparison
  against it sees only what changed since: an untracked file it holds is
  no change, a new one is added, a deleted one deleted; the repository's
  own index stays as it was. }
{ A repository with nothing staged since init has no index file; the
  temporary index must then be absent, not empty, which git refuses
  (GetTempFileName makes the file on Windows). }
procedure TGitRepoTest.TestSnapshotNoIndex;
var
  Id: string;
  Stats: TGittanFileStats;
begin
  Git(['init', '-q']);
  WriteFile('a.txt', 'a'#10);
  AssertTrue(FRepo.Open(FDir));
  AssertTrue(FRepo.Error, FRepo.TakeSnapshot(Id));
  AssertTrue('a.txt is in the snapshot', Pos('a.txt', Git(['ls-tree', '--name-only', Id])) > 0);
  FRepo.Base := Id;
  FRepo.WholeTree := True;
  AssertTrue(FRepo.Error, FRepo.ChangeStats(Stats));
  AssertEquals('nothing since the snapshot', 0, Length(Stats));
end;

procedure TGitRepoTest.TestSnapshot;
var
  Id, Porcelain: string;
  Stats: TGittanFileStats;
  Lines: TStringList;
begin
  MakeHistory;
  WriteFile('a.txt', 'one'#10'zwei'#10'three'#10);
  WriteFile('new.txt', 'n'#10);
  AssertTrue(FRepo.Open(FDir));
  AssertTrue(FRepo.TakeSnapshot(Id));
  AssertEquals('a full id', 40, Length(Id));
  AssertTrue(FRepo.HasCommit(Id));
  AssertFalse(FRepo.HasCommit('no-such-ref'));
  Porcelain := Git(['status', '--porcelain']);
  AssertTrue('new.txt still untracked', Pos('?? new.txt', Porcelain) > 0);
  AssertTrue('a.txt still unstaged', Pos(' M a.txt', Porcelain) > 0);

  FRepo.Base := Id;
  FRepo.WholeTree := True;
  AssertTrue(FRepo.ChangeStats(Stats));
  AssertEquals('nothing since the snapshot', 0, Length(Stats));

  WriteFile('new.txt', 'n'#10'm'#10);
  WriteFile('later.txt', 'l'#10);
  DeleteFile(IncludeTrailingPathDelimiter(FDir) + 'del.txt');
  AssertTrue(FRepo.ChangeStats(Stats));
  AssertEquals(3, Length(Stats));
  AssertTrue(FindStat(Stats, 'new.txt').Kind = ckModified);
  AssertEquals(1, FindStat(Stats, 'new.txt').Added);
  AssertTrue('new since the snapshot is added, not untracked',
    FindStat(Stats, 'later.txt').Kind = ckAdded);
  AssertEquals(1, FindStat(Stats, 'later.txt').Added);
  AssertTrue(FindStat(Stats, 'del.txt').Kind = ckDeleted);
  Lines := TStringList.Create;
  try
    AssertTrue(FRepo.FileChanges('new.txt', Lines));
    AssertEquals(' n|+m|', Joined(Lines));
    AssertTrue(FRepo.FileChanges('later.txt', Lines));
    AssertEquals('+l|', Joined(Lines));
  finally
    Lines.Free;
  end;
  Porcelain := Git(['status', '--porcelain']);
  AssertTrue('later.txt untracked for git', Pos('?? later.txt', Porcelain) > 0);

  { Without WholeTree the snapshot's untracked file reads as deleted and
    untracked at once: what WholeTree is for. }
  FRepo.WholeTree := False;
  AssertTrue(FRepo.ChangeStats(Stats));
  AssertTrue(FindStat(Stats, 'later.txt').Kind = ckUntracked);
end;

procedure TGitRepoTest.TestFiles;
var
  L: TStringList;
begin
  MakeHistory;
  WriteFile('new/untracked.txt', 'x');
  WriteFile('ignored.log', 'x');
  WriteFile('.gitignore', '*.log'#10);
  AssertTrue(FRepo.Open(FDir));
  L := TStringList.Create;
  try
    AssertTrue(FRepo.Files(L));
    AssertTrue('tracked file listed', L.IndexOf('a.txt') >= 0);
    AssertTrue('untracked file listed', L.IndexOf('new/untracked.txt') >= 0);
    AssertTrue('ignore file listed', L.IndexOf('.gitignore') >= 0);
    AssertEquals('ignored file left out', -1, L.IndexOf('ignored.log'));
  finally
    L.Free;
  end;
end;

{ Whole words over the tracked and untracked files, as path, row and
  text; case only on request; no match is an empty success. }
procedure TGitRepoTest.TestGrep;
var
  Words: TStringList;
  Output: string;
begin
  MakeHistory;
  WriteFile('b.txt', 'twofold'#10'Two words'#10);
  WriteFile('new/u.txt', 'two'#10);
  { A user's color setting must not reach the output that is parsed. }
  Git(['config', 'color.grep', 'always']);
  AssertTrue(FRepo.Open(FDir));
  Words := TStringList.Create;
  try
    Words.Add('two');
    AssertTrue(FRepo.Grep(Words, False, Output));
    AssertTrue('tracked row', Pos('a.txt'#0'2'#0'two'#10, Output) > 0);
    AssertTrue('untracked row', Pos('new/u.txt'#0'1'#0'two'#10, Output) > 0);
    AssertEquals('whole words only', 0, Pos('twofold', Output));
    AssertEquals('case kept', 0, Pos('Two words', Output));
    AssertTrue(FRepo.Grep(Words, True, Output));
    AssertTrue('case ignored', Pos('b.txt'#0'2'#0'Two words'#10, Output) > 0);
    Words[0] := 'nothingatall';
    AssertTrue('no match is no failure', FRepo.Grep(Words, False, Output));
    AssertEquals('', Output);
  finally
    Words.Free;
  end;
end;

{ Each side of a diff blamed in its version: the base names the commit
  of every line, the work tree the uncommitted ones under zeros. An
  untracked file cannot be blamed. }
procedure TGitRepoTest.TestBlame;
var
  Output, Left, Right, Head: string;
begin
  MakeHistory;
  Git(['tag', 'first']);
  WriteFile('a.txt', 'one'#10'two'#10'three'#10'four'#10);
  Commit('second');
  WriteFile('a.txt', 'one'#10'two'#10'three'#10'four'#10'five'#10);
  WriteFile('new.txt', 'n'#10);
  AssertTrue(FRepo.Open(FDir));
  Head := Trim(Git(['rev-parse', 'HEAD']));

  FRepo.DiffSides(Left, Right);
  AssertEquals('HEAD', Left);
  AssertEquals('the work tree', '', Right);
  AssertTrue(FRepo.Blame('a.txt', '', Output));
  AssertTrue('the commit of line four', Pos(Head + ' 4 4', Output) > 0);
  AssertTrue('line five is not committed',
    Pos(StringOfChar('0', 40) + ' 5 5', Output) > 0);
  AssertTrue(Pos('author Gittan Test', Output) > 0);
  AssertTrue(Pos('summary second', Output) > 0);

  AssertTrue(FRepo.Blame('a.txt', 'first', Output));
  AssertTrue('three lines in the first commit', Pos(' 3 3', Output) > 0);
  AssertFalse(Pos(' 4 4', Output) > 0);
  AssertTrue(Pos('summary files', Output) > 0);

  AssertFalse('untracked', FRepo.Blame('new.txt', '', Output));
  AssertFalse('not in the commit', FRepo.Blame('new.txt', 'first', Output));

  FRepo.Base := 'first..HEAD';
  FRepo.DiffSides(Left, Right);
  AssertEquals('first', Left);
  AssertEquals('HEAD', Right);

  { A three-dot range is diffed from the merge base, not from its left
    end. }
  Git(['tag', 'second']);
  Git(['checkout', '-q', '-f', 'first']);
  WriteFile('b.txt', 'b'#10);
  Commit('third');
  Git(['tag', 'third']);
  FRepo.Base := 'second...third';
  FRepo.DiffSides(Left, Right);
  AssertEquals('the merge base', Trim(Git(['rev-parse', 'first'])), Left);
  AssertEquals('third', Right);
end;

{ The blame of a repository with SHA-256 ids reads as one with SHA-1. }
procedure TGitRepoTest.TestBlameSha256;
var
  Output, Head: string;
  Blame: TGittanBlame;
begin
  Git(['init', '-q', '--object-format=sha256']);
  WriteFile('a.txt', 'one'#10'two'#10);
  Commit('first');
  WriteFile('a.txt', 'one'#10'two'#10'three'#10);
  AssertTrue(FRepo.Open(FDir));
  Head := Trim(Git(['rev-parse', 'HEAD']));
  AssertEquals(64, Length(Head));
  AssertTrue(FRepo.Blame('a.txt', '', Output));
  Blame := TGittanBlame.Create;
  try
    AssertTrue(Blame.Parse(Output));
    AssertEquals(3, Blame.LineCount);
    AssertEquals(Head, Blame.Commits[Blame.CommitOf(1)].Hash);
    AssertEquals('first', Blame.Commits[Blame.CommitOf(2)].Summary);
    AssertTrue(Blame.Commits[Blame.CommitOf(3)].Uncommitted);
  finally
    Blame.Free;
  end;
end;

{ Nothing is written to git, so a hook or alias that reads its input
  gets the end of it at once rather than waiting for ever. }
procedure TGitRepoTest.TestInputClosed;
var
  Output, Err: string;
begin
  AssertTrue(Err, RunGitIn(FDir, ['-c', 'alias.readall=!cat; echo read', 'readall'],
    Output, Err));
  AssertEquals('read', Trim(Output));
end;

{ The range of a commit runs from its parent; a root commit, which has
  none, from the empty tree, so every file of it reads as added. }
procedure TGitRepoTest.TestRemoteFor;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  AssertEquals('', FRepo.RemoteFor('foo/bar'));
  Git(['remote', 'add', 'upstream', 'https://github.com/Foo/Bar.git']);
  Git(['remote', 'add', 'origin', 'git@github.com:me/bar.git']);
  AssertEquals('upstream', FRepo.RemoteFor('foo/bar'));
  AssertEquals('origin', FRepo.RemoteFor('me/bar'));
  { Unknown: origin when there is one, else the first remote git lists. }
  AssertEquals('origin', FRepo.RemoteFor('nobody/nothing'));
  AssertEquals('origin', FRepo.RemoteFor(''));
  { HasRemoteFor never falls back, and wants the whole path. }
  AssertTrue(FRepo.HasRemoteFor('foo/bar'));
  AssertTrue(FRepo.HasRemoteFor('ME/BAR'));
  AssertFalse(FRepo.HasRemoteFor('foo/ba'));
  AssertFalse(FRepo.HasRemoteFor('nobody/nothing'));
  AssertFalse(FRepo.HasRemoteFor(''));
  Git(['remote', 'remove', 'origin']);
  AssertEquals('upstream', FRepo.RemoteFor('nobody/nothing'));
  AssertFalse(FRepo.HasRemoteFor('me/bar'));
  { Another owner whose name ends with the one asked for is not it. }
  Git(['remote', 'add', 'fork', 'https://github.com/notme/bar.git']);
  AssertFalse(FRepo.HasRemoteFor('me/bar'));
  AssertEquals('upstream', FRepo.RemoteFor('me/bar'));
  AssertTrue(FRepo.HasRemoteFor('notme/bar'));
end;

procedure TGitRepoTest.TestUserName;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  Git(['config', 'user.name', '  Björn Lindh ']);
  AssertEquals('Björn Lindh', FRepo.UserName);
  AssertTrue(FRepo.SetIdentity('Gittan Test', 'test@example.invalid', False));
  AssertEquals('Gittan Test', FRepo.UserName);
  AssertEquals('test@example.invalid', FRepo.UserEmail);
  AssertTrue(FRepo.HasLocalIdentity);
  Git(['config', '--unset', 'user.name']);
  Git(['config', '--unset', 'user.email']);
  AssertFalse(FRepo.HasLocalIdentity);
  { A key with several values is replaced, and the global choice takes
    every local one out (the global config is the test's own, see
    gittantests.lpr). }
  Git(['config', '--add', 'user.name', 'Someone Else']);
  Git(['config', '--add', 'user.name', 'Someone Else']);
  AssertTrue('local over two', FRepo.SetIdentity('Gittan Local', 'local@example.invalid', False));
  AssertEquals('Gittan Local', FRepo.UserName);
  Git(['config', '--add', 'user.name', 'Someone Else']);
  AssertTrue('global over two', FRepo.SetIdentity('Gittan Global', 'global@example.invalid', True));
  AssertFalse('local left', FRepo.HasLocalIdentity);
  AssertEquals('Gittan Global', FRepo.UserName);
  AssertEquals('global@example.invalid', FRepo.UserEmail);
end;

{ The bytes come back as they are, a NUL and a CR LF included. }
procedure TGitRepoTest.TestFileBlob;
var
  Data: RawByteString;
begin
  MakeHistory;
  WriteFile('pic.bin', 'one'#0#13#10'two');
  Git(['add', 'pic.bin']);
  Git(['commit', '-q', '-m', 'Add pic']);
  WriteFile('pic.bin', 'three');
  AssertTrue(FRepo.Open(FDir));
  AssertTrue(FRepo.FileBlob('pic.bin', 'HEAD', Data));
  AssertEquals('one'#0#13#10'two', Data);
  AssertTrue(FRepo.FileBlob('pic.bin', '', Data));
  AssertEquals('three', Data);
  AssertFalse(FRepo.FileBlob('none.bin', 'HEAD', Data));
  AssertFalse(FRepo.FileBlob('none.bin', '', Data));
end;

procedure TGitRepoTest.TestFileSize;
var
  Size: int64;
  {$ifdef unix}Info: TSearchRec;{$endif}
begin
  MakeHistory;
  WriteFile('pic.bin', 'one'#0#13#10'two');
  Git(['add', 'pic.bin']);
  Git(['commit', '-q', '-m', 'Add pic']);
  WriteFile('pic.bin', 'three');
  AssertTrue(FRepo.Open(FDir));
  AssertTrue(FRepo.FileSize('pic.bin', 'HEAD', Size));
  AssertEquals(9, Size);
  AssertTrue(FRepo.FileSize('pic.bin', '', Size));
  AssertEquals(5, Size);
  AssertFalse(FRepo.FileSize('none.bin', 'HEAD', Size));
  AssertFalse(FRepo.FileSize('none.bin', '', Size));
  {$ifdef unix}
  { A name FindFirst reads as a pattern is that file alone, not a
    neighbour it matches; Windows allows no * in a name. }
  WriteFile('aXb.bin', 'neighbour');
  AssertFalse('gone, the neighbour aside', FRepo.FileSize('a*b.bin', '', Size));
  WriteFile('a*b.bin', 'ab');
  AssertTrue(FRepo.FileSize('a*b.bin', '', Size));
  AssertEquals(2, Size);
  { Found after the neighbours it matches, whichever the folder lists
    first. }
  WriteFile('a0b.bin', 'zero');
  WriteFile('azb.bin', 'zed');
  AssertTrue(FRepo.FileSize('a*b.bin', '', Size));
  AssertEquals(2, Size);
  AssertTrue(StatExact(FDir + PathDelim + 'a*b.bin', Info));
  AssertEquals('a*b.bin', Info.Name);
  FindClose(Info);
  {$endif}
  {$ifdef darwin}
  { A folder that spells a name otherwise (case does not count on
    macOS's file system) still has the file. }
  AssertTrue('another case', StatExact(FDir + PathDelim + 'PIC.BIN', Info));
  FindClose(Info);
  {$endif}
  AssertTrue(IsBinaryFile(FDir + PathDelim + 'pic.bin') = False);
  WriteFile('pic.bin', 'a'#0'b');
  AssertTrue(IsBinaryFile(FDir + PathDelim + 'pic.bin'));
  AssertFalse(IsBinaryFile(FDir + PathDelim + 'none.bin'));
end;

function LfsPointer(const AOid: string; ASize: int64): string;
begin
  Result := 'version https://git-lfs.github.com/spec/v1'#10'oid sha256:' + AOid + #10 +
    'size ' + IntToStr(ASize) + #10;
end;

procedure TGitRepoTest.TestLfsPointer;
var
  Oid: string;
  Size: int64;
begin
  AssertTrue(ParseLfsPointer(LfsPointer(StringOfChar('a', 64), 12345), Oid, Size));
  AssertEquals(StringOfChar('a', 64), Oid);
  AssertEquals(12345, Size);
  AssertTrue('an extension', ParseLfsPointer('version https://git-lfs.github.com/spec/v1'#10 +
    'ext-0-foo sha256:' + StringOfChar('c', 64) + #10'oid sha256:' + StringOfChar('b', 64) +
    #10'size 0'#10, Oid, Size));
  AssertEquals(StringOfChar('b', 64), Oid);
  AssertEquals(0, Size);
  AssertTrue('hawser', ParseLfsPointer('version https://hawser.github.com/spec/v1'#10 +
    'oid sha256:' + StringOfChar('1', 64) + #10'size 3'#10, Oid, Size));
  AssertFalse('no last line feed', ParseLfsPointer(Copy(LfsPointer(StringOfChar('a', 64), 1),
    1, 108), Oid, Size));
  AssertEquals('', Oid);
  AssertFalse('another version', ParseLfsPointer(StringReplace(LfsPointer(StringOfChar('a', 64), 1),
    'v1', 'v2', []), Oid, Size));
  AssertFalse('upper case', ParseLfsPointer(LfsPointer(StringOfChar('A', 64), 1), Oid, Size));
  AssertFalse('short oid', ParseLfsPointer(LfsPointer(StringOfChar('a', 63), 1), Oid, Size));
  AssertFalse('negative size', ParseLfsPointer(LfsPointer(StringOfChar('a', 64), -1), Oid, Size));
  AssertFalse('no size', ParseLfsPointer('version https://git-lfs.github.com/spec/v1'#10 +
    'oid sha256:' + StringOfChar('a', 64) + #10, Oid, Size));
  AssertFalse('too long', ParseLfsPointer(LfsPointer(StringOfChar('a', 64), 1) +
    'x-pad ' + StringOfChar('x', 1000) + #10, Oid, Size));
  AssertFalse('text', ParseLfsPointer('version 1'#10, Oid, Size));
  AssertFalse('empty', ParseLfsPointer('', Oid, Size));
end;

{ git-lfs is not needed: without its filter git keeps the pointer as it
  is, which is what git holds with it, and the object is put in the
  store by hand. }
procedure TGitRepoTest.TestLfsFiles;
var
  OldOid, NewOid: string;
  Data: RawByteString;
  Size: int64;
  Missing: boolean;
  Stats: TGittanFileStats;
  Tree: TGittanRepo;
  State: TGittanLfsState;

  procedure Store(const AOid, AContent: string);
  var
    Stream: TFileStream;
  begin
    ForceDirectories(ExtractFileDir(FRepo.LfsObjectFile(AOid)));
    Stream := TFileStream.Create(FRepo.LfsObjectFile(AOid), fmCreate);
    try
      Stream.WriteBuffer(AContent[1], Length(AContent));
    finally
      Stream.Free;
    end;
  end;

begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  AssertTrue(FRepo.LfsState(State));
  AssertEquals('no file in Git LFS', 0, State.Files);
  AssertFalse('not looked for without one', State.Installed);
  OldOid := StringOfChar('a', 64);
  NewOid := StringOfChar('b', 64);
  WriteFile('.gitattributes', '*.psd filter=lfs diff=lfs merge=lfs -text'#10);
  WriteFile('art.psd', LfsPointer(OldOid, 9));
  Commit('Add art');
  WriteFile('art.psd', LfsPointer(NewOid, 7));
  AssertTrue(FRepo.Open(FDir));
  WriteFile('real.psd', 'real'#0'content');
  Git(['add', 'real.psd']);
  Git(['commit', '-q', '-m', 'Add art']);
  AssertTrue(FRepo.LfsState(State));
  AssertEquals(2, State.Files);
  AssertEquals('the pointer in the work tree', 1, State.Pointers);
  AssertEquals('art.psd real.psd', string.Join(' ', State.Lockable));
  AssertEquals(FindTool('git-lfs') <> '', State.Installed);
  AssertFalse('the tests'' config has no filter', State.SetUp);
  Git(['config', 'filter.lfs.process', 'git-lfs filter-process']);
  AssertTrue(FRepo.LfsState(State));
  AssertTrue(State.SetUp);
  Git(['config', '--unset', 'filter.lfs.process']);
  Git(['rm', '-q', 'real.psd']);
  Git(['commit', '-q', '-m', 'Drop the real one']);
  { A lockable file outside Git LFS may be locked too, once. }
  WriteFile('.gitattributes', '*.psd filter=lfs diff=lfs merge=lfs -text'#10 +
    '*.psd lockable'#10'plan.txt lockable'#10);
  WriteFile('plan.txt', 'plan'#10);
  Git(['add', '.gitattributes', 'plan.txt']);
  AssertTrue(FRepo.LfsState(State));
  AssertEquals(1, State.Files);
  AssertEquals('art.psd plan.txt', string.Join(' ', State.Lockable));
  Git(['rm', '-q', '--cached', 'plan.txt']);
  WriteFile('.gitattributes', '*.psd filter=lfs diff=lfs merge=lfs -text'#10);
  Git(['add', '.gitattributes']);
  DeleteFile(FDir + PathDelim + 'plan.txt');
  AssertEquals(ExpandFileName(IncludeTrailingPathDelimiter(FRepo.GitDir) + 'lfs') + PathDelim +
    'objects' + PathDelim + 'aa' + PathDelim + 'aa' + PathDelim + OldOid,
    FRepo.LfsObjectFile(OldOid));
  { Not downloaded: the pointer. }
  AssertTrue(FRepo.FileBlob('art.psd', 'HEAD', Data));
  AssertEquals(LfsPointer(OldOid, 9), Data);
  AssertTrue(FRepo.FileBlob('art.psd', '', Data));
  AssertEquals(LfsPointer(NewOid, 7), Data);
  AssertTrue(FRepo.LfsMissing('art.psd', 'HEAD'));
  AssertTrue(FRepo.LfsMissing('art.psd', ''));
  AssertFalse(FRepo.LfsMissing('a.txt', 'HEAD'));
  AssertFalse(FRepo.LfsMissing('a.txt', ''));
  AssertFalse(FRepo.LfsMissing('none.psd', 'HEAD'));
  { FileSize tells the same, from the one read of the pointer. }
  AssertTrue(FRepo.FileSize('art.psd', 'HEAD', Size, Missing));
  AssertEquals(9, Size);
  AssertTrue(Missing);
  AssertTrue(FRepo.FileSize('a.txt', '', Size, Missing));
  AssertFalse(Missing);
  Store(OldOid, 'old'#0'image');
  Store(NewOid, 'new'#0'img');
  AssertFalse(FRepo.LfsMissing('art.psd', 'HEAD'));
  AssertFalse(FRepo.LfsMissing('art.psd', ''));
  AssertTrue(FRepo.FileBlob('art.psd', 'HEAD', Data));
  AssertEquals('old'#0'image', Data);
  AssertTrue(FRepo.FileBlob('art.psd', '', Data));
  AssertEquals('new'#0'img', Data);
  AssertTrue(FRepo.FileSize('art.psd', 'HEAD', Size, Missing));
  AssertFalse(Missing);
  AssertTrue(FRepo.FileSize('art.psd', 'HEAD', Size));
  AssertEquals(9, Size);
  AssertTrue(FRepo.FileSize('art.psd', '', Size));
  AssertEquals(7, Size);
  AssertTrue(FRepo.FileSize('a.txt', 'HEAD', Size));
  AssertEquals(14, Size);
  { Binary, not the pointers' lines. }
  AssertTrue(FRepo.ChangeStats(Stats));
  AssertTrue(FindStat(Stats, 'art.psd').Binary);
  AssertEquals(0, FindStat(Stats, 'art.psd').Added);
  { A linked worktree reads the store of the common folder. }
  Git(['worktree', 'add', '-q', 'wt']);
  Tree := TGittanRepo.Create;
  try
    AssertTrue(Tree.Open(FDir + PathDelim + 'wt'));
    AssertTrue(Tree.FileBlob('art.psd', 'HEAD', Data));
    AssertEquals('old'#0'image', Data);
  finally
    Tree.Free;
  end;
  { The store folder is found once per open: lfs.storage set later
    counts from the next. }
  Git(['config', 'lfs.storage', 'elsewhere']);
  AssertTrue(FRepo.Open(FDir));
  AssertEquals(ExpandFileName(IncludeTrailingPathDelimiter(FRepo.GitDir) + 'elsewhere') + PathDelim +
    'objects' + PathDelim + 'aa' + PathDelim + 'aa' + PathDelim + OldOid,
    FRepo.LfsObjectFile(OldOid));
  AssertTrue(FRepo.FileBlob('art.psd', 'HEAD', Data));
  AssertEquals(LfsPointer(OldOid, 9), Data);
end;

{ With git-lfs (GitHub's runners have it) a real download from a remote
  in a folder, which git-lfs serves itself; without it the message that
  says so. The clone checks out with smudge skipped, as
  GIT_LFS_SKIP_SMUDGE would, so only pointers come. }
procedure TGitRepoTest.TestLfsDownload;
var
  Data: RawByteString;
  State: TGittanLfsState;
begin
  Git(['init', '-q', 'up']);
  if FindTool('git-lfs') = '' then
  begin
    AssertTrue(FRepo.Open(FDir + PathDelim + 'up'));
    AssertFalse(FRepo.LfsDownload('art.psd', ['']));
    AssertTrue(FRepo.Error, Pos('Git LFS is not installed', FRepo.Error) = 1);
    Exit;
  end;
  Git(['-C', 'up', 'lfs', 'install', '--local']);
  WriteFile('up/.gitattributes', '*.psd filter=lfs diff=lfs merge=lfs -text'#10);
  WriteFile('up/art.psd', 'one'#0'image');
  WriteFile('up/a,b [v2].psd', 'odd'#0'name');
  Git(['-C', 'up', 'add', '-A']);
  Git(['-C', 'up', 'commit', '-q', '-m', 'one']);
  WriteFile('up/art.psd', 'two'#0'image!');
  Git(['-C', 'up', 'commit', '-q', '-a', '-m', 'two']);
  Git(['clone', '-q', '--no-checkout', 'up', 'down']);
  Git(['-C', 'down', 'lfs', 'install', '--local', '--skip-smudge']);
  Git(['-C', 'down', 'reset', '-q', '--hard']);
  Git(['-C', 'down', 'lfs', 'install', '--local', '--force']);
  AssertTrue(FRepo.Open(FDir + PathDelim + 'down'));
  AssertTrue(FRepo.LfsMissing('art.psd', ''));
  AssertTrue(FRepo.LfsMissing('art.psd', 'HEAD~1'));
  AssertTrue(FRepo.Error, FRepo.LfsDownload('art.psd', ['HEAD~1', '']));
  AssertFalse(FRepo.LfsMissing('art.psd', ''));
  AssertFalse(FRepo.LfsMissing('art.psd', 'HEAD~1'));
  AssertTrue(FRepo.FileBlob('art.psd', '', Data));
  AssertEquals('two'#0'image!', Data);
  AssertTrue(FRepo.FileBlob('art.psd', 'HEAD~1', Data));
  AssertEquals('one'#0'image', Data);
  { A name git-lfs would read as two patterns, one with a set in it. }
  AssertTrue(FRepo.LfsMissing('a,b [v2].psd', ''));
  AssertTrue(FRepo.Error, FRepo.LfsDownload('a,b [v2].psd', ['']));
  AssertFalse(FRepo.LfsMissing('a,b [v2].psd', ''));
  AssertTrue(FRepo.FileBlob('a,b [v2].psd', '', Data));
  AssertEquals('odd'#0'name', Data);
  { The whole work tree again: a pointer back in place of the file. }
  Git(['-C', 'down', 'lfs', 'install', '--local', '--skip-smudge']);
  DeleteFile(FDir + PathDelim + 'down' + PathDelim + 'art.psd');
  Git(['-C', 'down', 'checkout', '-q', '--', 'art.psd']);
  Git(['-C', 'down', 'lfs', 'install', '--local', '--force']);
  AssertTrue(FRepo.LfsState(State));
  AssertEquals(1, State.Pointers);
  AssertTrue(State.SetUp);
  AssertTrue(FRepo.Error, FRepo.LfsPull);
  AssertTrue(FRepo.LfsState(State));
  AssertEquals(0, State.Pointers);
  Git(['-C', 'down', 'remote', 'remove', 'origin']);
  AssertFalse(FRepo.LfsDownload('art.psd', ['HEAD']));
  AssertEquals('The repository has no remote to download from.', FRepo.Error);
end;

{ The repository fetched from itself writes FETCH_HEAD, in the root's
  .git and in a linked worktree's own folder. }
procedure TGitRepoTest.TestLastFetch;
var
  Tree: TGittanRepo;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  AssertEquals('never fetched', 0, FRepo.LastFetch, 0);
  Git(['remote', 'add', 'self', '.']);
  Git(['fetch', '-q', 'self']);
  AssertTrue('just now', Abs(Now - FRepo.LastFetch) < 1 / 24 / 60);
  Git(['worktree', 'add', '-q', 'wt']);
  Tree := TGittanRepo.Create;
  try
    AssertTrue(Tree.Open(FDir + PathDelim + 'wt'));
    AssertEquals('the worktree never fetched', 0, Tree.LastFetch, 0);
  finally
    Tree.Free;
  end;
end;

{ A bare repository stands in for GitHub: it serves the pull request as
  refs/pull/7/head, as GitHub does. }
procedure TGitRepoTest.TestFetchPullRequest;
var
  Remote, Branch, Head, HeadRef, Output: string;
  Code: integer;
begin
  MakeHistory;
  Remote := FDir + '-remote';
  if RunCommandIndir(FDir, 'git', ['init', '-q', '--bare', Remote], Output, Code,
    [poStderrToOutPut]) = 0 then
  try
    Branch := Trim(Git(['rev-parse', '--abbrev-ref', 'HEAD']));
    Git(['remote', 'add', 'origin', Remote]);
    Git(['push', '-q', 'origin', Branch]);
    WriteFile('a.txt', 'one'#10'two'#10'three'#10'four'#10);
    Commit('the pull request');
    Head := Trim(Git(['rev-parse', 'HEAD']));
    Git(['push', '-q', 'origin', 'HEAD:refs/pull/7/head']);
    Git(['reset', '-q', '--hard', 'HEAD^']);
    AssertTrue(FRepo.Open(FDir));
    AssertTrue(FRepo.FetchPullRequest('origin', 7, 'refs/pull/7/head', Branch, HeadRef));
    AssertEquals('refs/gittan/pr/7', HeadRef);
    AssertEquals(Head, Trim(Git(['rev-parse', HeadRef])));
    AssertTrue(FRepo.HasCommit('origin/' + Branch));
    AssertFalse(FRepo.FetchPullRequest('origin', 8, 'refs/pull/8/head', Branch, HeadRef));
    FRepo.Base := 'origin/' + Branch + '...' + HeadRef;
    AssertTrue(FRepo.IsRange);
  finally
    RemoveTree(Remote);
  end
  else
    Fail('could not make a bare repository');
end;

{ A bare repository as the remote; the test's branch is pushed to it. }
procedure TGitRepoTest.TestDefaultBranchAndMergeBase;
var
  Remote, Branch, Base, Hash: string;
  Output: string;
  Code: integer;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  AssertEquals('', FRepo.DefaultBranch);
  AssertFalse(FRepo.MergeBase('', Hash));
  AssertFalse(FRepo.MergeBase('nothing', Hash));
  Remote := FDir + '-remote';
  if RunCommandIndir(FDir, 'git', ['init', '-q', '--bare', Remote], Output, Code,
    [poStderrToOutPut]) <> 0 then
    Fail('could not make a bare repository');
  try
    Branch := Trim(Git(['rev-parse', '--abbrev-ref', 'HEAD']));
    Base := Trim(Git(['rev-parse', 'HEAD']));
    Git(['remote', 'add', 'origin', Remote]);
    Git(['push', '-q', 'origin', Branch]);
    { Populate the origin/* remote-tracking refs the way a clone or fetch
      does: a plain push no longer updates them on git 2.55, where it still
      did on older git. }
    Git(['fetch', '-q', 'origin']);
    { No origin/HEAD yet: main or master on the remote, when the branch
      is one of them, is the fallback. }
    if (Branch = 'main') or (Branch = 'master') then
      AssertEquals('origin/' + Branch, FRepo.DefaultBranch);
    Git(['remote', 'set-head', 'origin', Branch]);
    AssertEquals('origin/' + Branch, FRepo.DefaultBranch);
    Git(['checkout', '-q', '-b', 'topic']);
    WriteFile('a.txt', 'one'#10'two'#10'three'#10'four'#10);
    Commit('on topic');
    AssertTrue(FRepo.MergeBase('origin/' + Branch, Hash));
    AssertEquals(Base, Hash);
  finally
    RemoveTree(Remote);
  end;
end;

procedure TGitRepoTest.TestCommitIdAndCount;
var
  First: string;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  First := FRepo.CommitId('HEAD');
  AssertEquals('a full id', 40, Length(First));
  AssertEquals(Trim(Git(['rev-parse', 'HEAD'])), First);
  AssertEquals('no such ref', '', FRepo.CommitId('no-such-ref'));
  WriteFile('a.txt', 'one'#10'two'#10'three'#10'four'#10);
  Commit('second');
  WriteFile('a.txt', 'one'#10'two'#10'three'#10'four'#10'five'#10);
  Commit('third');
  AssertEquals(2, FRepo.CountCommits(First, 'HEAD'));
  AssertEquals(0, FRepo.CountCommits('HEAD', First));
  AssertEquals(-1, FRepo.CountCommits('no-such-ref', 'HEAD'));
end;

procedure TGitRepoTest.TestAheadBehind;
var
  Remote, Branch, Output: string;
  Code, Ahead, Behind: integer;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  AssertFalse(FRepo.AheadBehind(Ahead, Behind));
  Remote := FDir + '-remote';
  if RunCommandIndir(FDir, 'git', ['init', '-q', '--bare', Remote], Output, Code,
    [poStderrToOutPut]) <> 0 then
    Fail('could not make a bare repository');
  try
    Branch := Trim(Git(['rev-parse', '--abbrev-ref', 'HEAD']));
    Git(['remote', 'add', 'origin', Remote]);
    Git(['push', '-q', '-u', 'origin', Branch]);
    AssertTrue(FRepo.AheadBehind(Ahead, Behind));
    AssertEquals(0, Ahead);
    AssertEquals(0, Behind);
    WriteFile('a.txt', 'one'#10'two'#10'three'#10'four'#10);
    Commit('ahead one');
    WriteFile('a.txt', 'one'#10'two'#10'three'#10'four'#10'five'#10);
    Commit('ahead two');
    AssertTrue(FRepo.AheadBehind(Ahead, Behind));
    AssertEquals(2, Ahead);
    AssertEquals(0, Behind);
    { The remote moves on without us: push the two from a detached
      commit of their own, then drop one locally. }
    Git(['push', '-q', 'origin', 'HEAD:' + Branch]);
    Git(['reset', '-q', '--hard', 'HEAD^']);
    AssertTrue(FRepo.AheadBehind(Ahead, Behind));
    AssertEquals(0, Ahead);
    AssertEquals(1, Behind);
  finally
    RemoveTree(Remote);
  end;
end;

procedure TGitRepoTest.TestSyncCommits;
var
  Remote, Branch, Output: string;
  Code: integer;
  Commits: TGittanCommitLines;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  AssertFalse(FRepo.SyncCommits(True, Commits));
  Remote := FDir + '-remote';
  if RunCommandIndir(FDir, 'git', ['init', '-q', '--bare', Remote], Output, Code,
    [poStderrToOutPut]) <> 0 then
    Fail('could not make a bare repository');
  try
    Branch := Trim(Git(['rev-parse', '--abbrev-ref', 'HEAD']));
    Git(['remote', 'add', 'origin', Remote]);
    Git(['push', '-q', '-u', 'origin', Branch]);
    AssertTrue(FRepo.SyncCommits(True, Commits));
    AssertEquals(0, Length(Commits));
    WriteFile('a.txt', 'one'#10'two'#10'three'#10'four'#10);
    Commit('ahead one');
    WriteFile('a.txt', 'one'#10'two'#10'three'#10'four'#10'five'#10);
    Commit('ahead two');
    AssertTrue(FRepo.SyncCommits(True, Commits));
    AssertEquals(2, Length(Commits));
    AssertEquals('ahead two', Commits[0].Subject);
    AssertEquals('ahead one', Commits[1].Subject);
    AssertEquals(Trim(Git(['rev-parse', 'HEAD'])), Commits[0].Hash);
    AssertEquals(Trim(Git(['rev-parse', '--short', 'HEAD'])), Commits[0].Short);
    AssertTrue(Length(Commits[0].Short) < Length(Commits[0].Hash));
    AssertTrue(FRepo.SyncCommits(False, Commits));
    AssertEquals(0, Length(Commits));
    { Only the newest when asked for one. }
    AssertTrue(FRepo.SyncCommits(True, Commits, 1));
    AssertEquals(1, Length(Commits));
    AssertEquals('ahead two', Commits[0].Subject);
    { The remote moves on without us, as in TestAheadBehind. }
    Git(['push', '-q', 'origin', 'HEAD:' + Branch]);
    Git(['reset', '-q', '--hard', 'HEAD^']);
    AssertTrue(FRepo.SyncCommits(True, Commits));
    AssertEquals(0, Length(Commits));
    AssertTrue(FRepo.SyncCommits(False, Commits));
    AssertEquals(1, Length(Commits));
    AssertEquals('ahead two', Commits[0].Subject);
  finally
    RemoveTree(Remote);
  end;
end;

procedure TGitRepoTest.TestRecentCommits;
var
  Remote, Branch, Output: string;
  Code: integer;
  Commits: TGittanCommitLines;
  Snap: TGittanRepoSnapshot;
begin
  Git(['init', '-q']);
  AssertTrue(FRepo.Open(FDir));
  { Nothing before the first commit. }
  AssertFalse(FRepo.RecentCommits(Commits));
  AssertEquals(0, Length(Commits));
  MakeHistory;
  WriteFile('a.txt', 'one'#10'two'#10'three'#10'four'#10);
  Commit('"quoted" subject · ok');
  AssertTrue(FRepo.RecentCommits(Commits));
  AssertEquals(2, Length(Commits));
  AssertEquals('"quoted" subject · ok', Commits[0].Subject);
  AssertEquals('files', Commits[1].Subject);
  AssertEquals(Trim(Git(['rev-parse', 'HEAD'])), Commits[0].Hash);
  AssertEquals(Trim(Git(['rev-parse', '--short', 'HEAD'])), Commits[0].Short);
  AssertEquals(Trim(Git(['log', '-1', '--format=%an'])), Commits[0].Author);
  AssertTrue(Commits[0].Date > 0);
  { No upstream: nothing counts as not pushed. }
  AssertFalse(Commits[0].Unpushed);
  AssertTrue(FRepo.RecentCommits(Commits, 1));
  AssertEquals(1, Length(Commits));
  { A clean tree carries them in the snapshot. }
  AssertTrue(FRepo.Snapshot(Snap));
  AssertEquals(2, Length(Snap.Recent));
  Remote := FDir + '-remote';
  if RunCommandIndir(FDir, 'git', ['init', '-q', '--bare', Remote], Output, Code,
    [poStderrToOutPut]) <> 0 then
    Fail('could not make a bare repository');
  try
    Branch := Trim(Git(['rev-parse', '--abbrev-ref', 'HEAD']));
    Git(['remote', 'add', 'origin', Remote]);
    Git(['push', '-q', '-u', 'origin', Branch]);
    WriteFile('a.txt', 'one'#10);
    Commit('ahead');
    AssertTrue(FRepo.RecentCommits(Commits));
    AssertEquals(3, Length(Commits));
    AssertTrue(Commits[0].Unpushed);
    AssertFalse(Commits[1].Unpushed);
    AssertFalse(Commits[2].Unpushed);
    { A changed tree leaves them out. }
    WriteFile('a.txt', 'changed'#10);
    AssertTrue(FRepo.Snapshot(Snap));
    AssertEquals(0, Length(Snap.Recent));
  finally
    RemoveTree(Remote);
  end;
end;

{ A branch merged back: the merge has two parents, the root none; the
  refs come through, and against an upstream the commits on one side
  only are marked. }
procedure TGitRepoTest.TestGraphCommits;
var
  Remote, Branch, Output: string;
  Code, i: integer;
  Commits: TGittanGraphCommits;
begin
  Git(['init', '-q']);
  AssertTrue(FRepo.Open(FDir));
  AssertFalse(FRepo.GraphCommits(Commits));
  MakeHistory;
  Branch := Trim(Git(['rev-parse', '--abbrev-ref', 'HEAD']));
  Git(['checkout', '-q', '-b', 'side']);
  WriteFile('b.txt', 'side'#10);
  Commit('on side');
  Git(['checkout', '-q', Branch]);
  WriteFile('a.txt', 'main'#10);
  Git(['add', '-A']);
  Git(['commit', '-q', '-m', 'on main', '-m', 'A body'#10#10'of two paragraphs']);
  Git(['merge', '-q', '--no-ff', '-m', 'merge side', 'side']);
  Git(['tag', 'v1']);
  AssertTrue(FRepo.GraphCommits(Commits));
  AssertEquals(4, Length(Commits));
  AssertEquals('merge side', Commits[0].Subject);
  AssertEquals('', Commits[0].Body);
  for i := 0 to High(Commits) do
    if Commits[i].Subject = 'on main' then
      AssertEquals('A body'#10#10'of two paragraphs', Commits[i].Body);
  AssertEquals(2, Length(Commits[0].Parents));
  AssertEquals(0, Length(Commits[3].Parents));
  AssertEquals('files', Commits[3].Subject);
  AssertEquals(Trim(Git(['log', '-1', '--format=%an'])), Commits[0].Author);
  AssertTrue(Commits[0].Date > 0);
  AssertEquals(2, Length(Commits[0].Refs));
  AssertEquals(Branch, Commits[0].Refs[0].Name);
  AssertTrue(Commits[0].Refs[0].Kind = grHead);
  AssertEquals('v1', Commits[0].Refs[1].Name);
  AssertEquals(2, GraphWidth(Commits));
  AssertFalse(Commits[0].Unpushed);
  Remote := FDir + '-remote';
  if RunCommandIndir(FDir, 'git', ['init', '-q', '--bare', Remote], Output, Code,
    [poStderrToOutPut]) <> 0 then
    Fail('could not make a bare repository');
  try
    Git(['remote', 'add', 'origin', Remote]);
    Git(['push', '-q', '-u', 'origin', Branch]);
    Git(['reset', '-q', '--hard', 'HEAD~1']);
    WriteFile('c.txt', 'ahead'#10);
    Commit('ahead');
    AssertTrue(FRepo.GraphCommits(Commits));
    AssertEquals('ahead', Commits[0].Subject);
    AssertTrue(Commits[0].Unpushed);
    AssertEquals('merge side', Commits[1].Subject);
    AssertTrue(Commits[1].Unpulled);
    AssertFalse(Commits[1].Unpushed);
  finally
    RemoveTree(Remote);
  end;
end;

{ A file is followed through its rename; a folder lists what changed
  under it. }
procedure TGitRepoTest.TestPathCommits;
var
  Hashes: TStringList;
begin
  Hashes := TStringList.Create;
  try
    Git(['init', '-q']);
    AssertTrue(FRepo.Open(FDir));
    AssertFalse(FRepo.PathCommits('a.txt', Hashes));
    MakeHistory;
    WriteFile('a.txt', 'one'#10'two'#10'three'#10'four'#10);
    Commit('a again');
    Git(['mv', 'a.txt', 'b.txt']);
    Commit('renamed');
    WriteFile('dir sp/other.txt', 'b'#10);
    Commit('in the folder');
    AssertTrue(FRepo.PathCommits('b.txt', Hashes));
    AssertEquals(3, Hashes.Count);
    AssertEquals(Trim(Git(['rev-parse', 'HEAD~1'])), Hashes[0]);
    AssertEquals(Trim(Git(['rev-parse', 'HEAD~3'])), Hashes[2]);
    AssertTrue(FRepo.PathCommits('dir sp', Hashes));
    AssertEquals(2, Hashes.Count);
    AssertEquals(Trim(Git(['rev-parse', 'HEAD'])), Hashes[0]);
    AssertTrue(FRepo.PathCommits('missing.txt', Hashes));
    AssertEquals(0, Hashes.Count);
    AssertTrue(FRepo.PathCommits(QuoteName, Hashes));
    AssertEquals(1, Hashes.Count);
  finally
    Hashes.Free;
  end;
end;

{ A merge and a rebase that stop on a conflict, each aborted after. }
procedure TGitRepoTest.TestOperation;
var
  Branch, Output: string;
  Stats: TGittanFileStats;
  Code, Step, Total: integer;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  AssertEquals('', FRepo.Operation);
  AssertEquals('', FRepo.RebaseBranch);
  AssertTrue(DirectoryExists(FRepo.GitDir));
  Branch := Trim(Git(['rev-parse', '--abbrev-ref', 'HEAD']));
  Git(['checkout', '-q', '-b', 'topic']);
  WriteFile('a.txt', 'topic'#10);
  Commit('topic');
  Git(['checkout', '-q', Branch]);
  WriteFile('a.txt', 'main'#10);
  Commit('main');

  { git merge fails on the conflict, so it runs without the helper. }
  RunCommandIndir(FDir, 'git', ['-c', 'user.name=T', '-c', 'user.email=t@example.invalid',
    'merge', 'topic'], Output, Code, [poStderrToOutPut]);
  AssertTrue('merge stops', Code <> 0);
  AssertEquals('merging', FRepo.Operation);
  AssertTrue(FRepo.ChangeStats(Stats));
  AssertEquals(Ord(ckConflict), Ord(FindStat(Stats, 'a.txt').Kind));
  Git(['merge', '--abort']);
  AssertEquals('', FRepo.Operation);

  Git(['checkout', '-q', 'topic']);
  RunCommandIndir(FDir, 'git', ['-c', 'user.name=T', '-c', 'user.email=t@example.invalid',
    'rebase', Branch], Output, Code, [poStderrToOutPut]);
  AssertTrue('rebase stops', Code <> 0);
  AssertEquals('rebasing', FRepo.Operation);
  AssertEquals('topic', FRepo.RebaseBranch);
  { The one commit of topic is the first and the last to replay. }
  AssertTrue('progress', FRepo.OperationProgress(Step, Total));
  AssertEquals(1, Step);
  AssertEquals(1, Total);
  Git(['rebase', '--abort']);
  AssertEquals('', FRepo.Operation);
  AssertEquals('', FRepo.RebaseBranch);
  AssertFalse('no progress', FRepo.OperationProgress(Step, Total));
  AssertEquals(0, Total);
end;

procedure TGitRepoTest.TestCommitRange;
var
  Stats: TGittanFileStats;
  Root, Second, Third, Body: string;
  Details: TGittanCommitLine;
begin
  MakeHistory;
  Root := Trim(Git(['rev-parse', 'HEAD']));
  WriteFile('a.txt', 'one'#10'two'#10'three'#10'four'#10);
  Commit('second');
  Second := Trim(Git(['rev-parse', 'HEAD']));
  AssertTrue(FRepo.Open(FDir));
  AssertEquals(Second + '^..' + Second, FRepo.CommitRange(Second));
  AssertEquals('4b825dc642cb6eb9a060e54bf8d69288fbee4904..' + Root, FRepo.CommitRange(Root));

  FRepo.Base := FRepo.CommitRange(Second);
  AssertTrue(FRepo.ChangeStats(Stats));
  AssertEquals(1, Length(Stats));
  AssertEquals('a.txt', Stats[0].Path);
  AssertEquals(1, Stats[0].Added);

  FRepo.Base := FRepo.CommitRange(Root);
  AssertTrue(FRepo.ChangeStats(Stats));
  AssertEquals(5, Length(Stats));
  AssertTrue(FindStat(Stats, 'a.txt').Kind = ckAdded);
  AssertEquals(3, FindStat(Stats, 'a.txt').Added);

  { The details of a commit: the subject, the author, and the body
    without the blank line after the subject. }
  WriteFile('a.txt', 'one'#10);
  Git(['add', '-A']);
  Git(['commit', '-q', '-m', 'Third: cut', '-m', 'Why it goes.'#10'Second line.']);
  Third := Trim(Git(['rev-parse', 'HEAD']));
  AssertTrue(FRepo.CommitDetails(Third, Details, Body));
  AssertEquals(Third, Details.Hash);
  AssertEquals(Copy(Third, 1, Length(Details.Short)), Details.Short);
  AssertEquals('Third: cut', Details.Subject);
  AssertEquals('Gittan Test', Details.Author);
  AssertTrue(Details.Date > 0);
  AssertEquals('Why it goes.'#10'Second line.', Body);
  AssertTrue(FRepo.CommitDetails(Root, Details, Body));
  AssertEquals('', Body);
  AssertFalse(FRepo.CommitDetails('0123456789abcdef0123456789abcdef01234567', Details, Body));
end;

{ The history of a range follows the lines through the commits that
  changed them and leaves out the commits that changed other lines; the
  history of the whole file has every commit. The output is read by
  TGittanHistory, so it is checked through that. }
procedure TGitRepoTest.TestLineHistory;
var
  Output, First, Third: string;
  H: TGittanHistory;
begin
  Git(['init', '-q']);
  WriteFile('f.txt', 'head'#10'begin'#10'  a'#10'end'#10'tail'#10);
  Commit('first');
  First := Trim(Git(['rev-parse', 'HEAD']));
  WriteFile('f.txt', 'head'#10'begin'#10'  b'#10'end'#10'tail'#10);
  Commit('second');
  WriteFile('f.txt', 'head'#10'begin'#10'  b'#10'  c'#10'end'#10'tail'#10);
  Commit('third');
  Third := Trim(Git(['rev-parse', 'HEAD']));
  WriteFile('f.txt', 'head'#10'begin'#10'  b'#10'  c'#10'end'#10'tail changed'#10);
  Commit('fourth');
  AssertTrue(FRepo.Open(FDir));

  H := TGittanHistory.Create;
  try
    { begin..end in HEAD is lines 2..5. }
    AssertTrue(FRepo.LineHistory('f.txt', '', 2, 5, 10, Output));
    AssertTrue(H.Parse(Output));
    AssertEquals('the commit of the tail is not among them', 3, H.Count);
    AssertEquals(Third, H.Commits[0].Info.Hash);
    AssertEquals('third', H.Commits[0].Info.Summary);
    AssertEquals('Gittan Test', H.Commits[0].Info.Author);
    AssertTrue(H.Commits[0].Info.Time > 0);
    AssertEquals(1, Length(H.Commits[0].Hunks));
    AssertEquals(2, H.Commits[0].Hunks[0].NewStart);
    AssertEquals('+  c', H.Commits[0].Hunks[0].Lines[2]);
    AssertEquals('second', H.Commits[1].Info.Summary);
    AssertEquals('-  a', H.Commits[1].Hunks[0].Lines[1]);
    AssertEquals('+  b', H.Commits[1].Hunks[0].Lines[2]);
    AssertEquals(First, H.Commits[2].Info.Hash);

    AssertTrue(FRepo.LineHistory('f.txt', '', 2, 5, 2, Output));
    AssertTrue(H.Parse(Output));
    AssertEquals('at most two', 2, H.Count);

    { The range in an older commit, and the whole file. }
    AssertTrue(FRepo.LineHistory('f.txt', Third + '^', 2, 4, 10, Output));
    AssertTrue(H.Parse(Output));
    AssertEquals(2, H.Count);
    AssertEquals('second', H.Commits[0].Info.Summary);

    AssertTrue(FRepo.LineHistory('f.txt', '', 0, 0, 10, Output));
    AssertTrue(H.Parse(Output));
    AssertEquals(4, H.Count);
    AssertEquals('fourth', H.Commits[0].Info.Summary);
    AssertEquals('line 6 with three lines of context', 3, H.Commits[0].Hunks[0].OldStart);

    { An end past the file is clamped by git, a start past it is an error. }
    AssertTrue(FRepo.LineHistory('f.txt', '', 2, 50, 10, Output));
    AssertFalse('past the end', FRepo.LineHistory('f.txt', '', 40, 50, 10, Output));
    AssertFalse('unknown file', FRepo.LineHistory('nope.txt', '', 1, 2, 10, Output));
  finally
    H.Free;
  end;
end;

{ The local branches are listed and switched to; a switch git refuses
  (an unknown name, a local change it would overwrite) fails with its
  reason and leaves the branch alone. }
{ The file APath as HEAD has it, or '' when HEAD has no such file. }
function HeadFile(const ADir, APath: string): string;
var
  Code: integer;
begin
  if (RunCommandIndir(ADir, 'git', ['show', 'HEAD:' + APath], Result, Code, []) <> 0) or
    (Code <> 0) then
    Result := '';
end;

{ Only the chosen files go in, as they are in the work tree, whatever
  the index holds; the rest stays as it was, staged or untracked. }
procedure TGitRepoTest.TestCommit;
const
  Message = 'Subject'#10#10'# not a comment'#10'body';
var
  Paths: TStringList;
  Id, Text: string;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  WriteFile('a.txt', 'changed'#10);
  WriteFile('staged.txt', 'staged'#10);
  Git(['add', 'staged.txt']);
  WriteFile('staged.txt', 'work tree'#10);
  WriteFile('dir sp/fil å.txt', 'left staged'#10);
  Git(['add', 'dir sp/fil å.txt']);
  Git(['rm', '-q', 'del.txt']);
  Git(['mv', QuoteName, 'moved.txt']);
  WriteFile('br[a].txt', 'literal'#10);
  WriteFile('bra.txt', 'not chosen'#10);
  Paths := TStringList.Create;
  try
    AssertFalse('nothing chosen', FRepo.Commit(Message, Paths, False, Id));
    AssertTrue(FRepo.Error <> '');
    Paths.Add('a.txt');
    Paths.Add('staged.txt');
    Paths.Add('del.txt');
    Paths.Add('moved.txt');
    Paths.Add('br[a].txt');
    AssertTrue(FRepo.Error, FRepo.Commit(Message, Paths, False, Id));
  finally
    Paths.Free;
  end;
  AssertEquals(Trim(Git(['rev-parse', 'HEAD'])), Id);
  AssertEquals('changed'#10, HeadFile(FDir, 'a.txt'));
  AssertEquals('the work tree, not the index', 'work tree'#10, HeadFile(FDir, 'staged.txt'));
  AssertEquals('', HeadFile(FDir, 'del.txt'));
  AssertEquals('the old path of the rename', '', HeadFile(FDir, QuoteName));
  AssertEquals('x'#10, HeadFile(FDir, 'moved.txt'));
  AssertEquals('literal'#10, HeadFile(FDir, 'br[a].txt'));
  AssertEquals('', HeadFile(FDir, 'bra.txt'));
  AssertEquals('a'#10, HeadFile(FDir, 'dir sp/fil å.txt'));
  Text := Git(['status', '--porcelain', '-z']);
  AssertEquals('M  dir sp/fil å.txt'#0'?? bra.txt'#0, Text);
  AssertTrue(FRepo.HeadMessage(Text));
  AssertEquals(Message, Text);
end;

{ Amend without paths changes only the message; a hook that fails
  stops the commit, with its output as the error (its color sequence at
  the start kept), and the untracked file added for it is untracked
  again. }
procedure TGitRepoTest.TestCommitAmendAndHook;
var
  Paths: TStringList;
  Parent, Id, Text, Hook: string;
  Code: integer;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  WriteFile('a.txt', 'staged'#10);
  Git(['add', 'a.txt']);
  Parent := Trim(Git(['rev-parse', 'HEAD~0']));
  Paths := TStringList.Create;
  try
    AssertTrue(FRepo.Error, FRepo.Commit('renamed', Paths, True, Id));
    AssertTrue(Id <> Parent);
    AssertTrue(FRepo.HeadMessage(Text));
    AssertEquals('renamed', Text);
    AssertEquals('one'#10'two'#10'three'#10, HeadFile(FDir, 'a.txt'));
    AssertEquals('M  a.txt'#0, Git(['status', '--porcelain', '-z']));

    WriteFile('.git/hooks/pre-commit',
      '#!/bin/sh'#10'printf ''\033[31mhook says no\033[0m\n'' >&2'#10'exit 1'#10);
    Hook := IncludeTrailingPathDelimiter(FDir) + SetDirSeparators('.git/hooks/pre-commit');
    {$ifdef UNIX}
    RunCommandIndir(FDir, 'chmod', ['+x', Hook], Text, Code, []);
    {$endif}
    WriteFile('new.txt', 'new'#10);
    Paths.Add('new.txt');
    AssertFalse(FRepo.Commit('blocked', Paths, False, Id));
    AssertEquals(FRepo.Error, 1, Pos(#27'[31mhook says no', FRepo.Error));
    AssertEquals('M  a.txt'#0'?? new.txt'#0, Git(['status', '--porcelain', '-z']));
    { Past the hook, signed off. }
    AssertTrue(FRepo.Error, FRepo.Commit('past the hook', Paths, False, Id, nil,
      [coNoVerify, coSignOff]));
    AssertTrue(FRepo.HeadMessage(Text));
    AssertEquals(Text, 1, Pos('past the hook'#10#10'Signed-off-by: ', Text));
    AssertEquals('new'#10, HeadFile(FDir, 'new.txt'));

    AssertFalse(FRepo.SignOff);
    AssertTrue(FRepo.SetSignOff(True));
    AssertTrue(FRepo.SignOff);
    AssertEquals('true', Trim(Git(['config', '--local', 'gittan.signOff'])));
    AssertTrue(FRepo.SetSignOff(False));
    AssertFalse(FRepo.SignOff);
    AssertTrue('off when off', FRepo.SetSignOff(False));
  finally
    Paths.Free;
  end;
end;

procedure TGitRepoTest.TestCommitUnborn;
var
  Paths: TStringList;
  Id: string;
begin
  Git(['init', '-q']);
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  WriteFile('first.txt', 'first'#10);
  WriteFile('later.txt', 'later'#10);
  Paths := TStringList.Create;
  try
    Paths.Add('first.txt');
    AssertTrue(FRepo.Error, FRepo.Commit('first', Paths, False, Id));
  finally
    Paths.Free;
  end;
  AssertEquals('first'#10, HeadFile(FDir, 'first.txt'));
  AssertEquals('?? later.txt'#0, Git(['status', '--porcelain', '-z']));
end;

{ A part goes in with its own text, the work tree's mode and the rest
  of the chosen files; the real index then holds the committed text, so
  what was left out shows as not staged, and a staged file not chosen
  stays staged. A hook that fails leaves the index as it was; an amend
  takes parts too. }
procedure TGitRepoTest.TestCommitParts;
var
  Paths: TStringList;
  Parts: TGittanCommitParts;
  Parent, Id, Text, Hook: string;
  Code: integer;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  Parent := Trim(Git(['rev-parse', 'HEAD']));
  WriteFile('a.txt', 'ONE'#10'two'#10'THREE'#10);
  {$ifdef UNIX}
  RunCommandIndir(FDir, 'chmod', ['+x', 'a.txt'], Text, Code, []);
  {$endif}
  WriteFile('staged.txt', 'staged'#10);
  Git(['add', 'staged.txt']);
  WriteFile('new.txt', 'new'#10);
  Parts := nil;
  SetLength(Parts, 1);
  Parts[0].Path := 'a.txt';
  Parts[0].Text := 'ONE'#10'two'#10'three'#10;
  Paths := TStringList.Create;
  try
    Paths.Add('a.txt');
    Paths.Add('new.txt');
    AssertTrue(FRepo.Error, FRepo.Commit('part', Paths, False, Id, Parts));
    AssertEquals(Trim(Git(['rev-parse', 'HEAD'])), Id);
    AssertEquals(Parent, Trim(Git(['rev-parse', 'HEAD~1'])));
    AssertEquals('ONE'#10'two'#10'three'#10, HeadFile(FDir, 'a.txt'));
    AssertEquals('new'#10, HeadFile(FDir, 'new.txt'));
    AssertEquals('old'#10, HeadFile(FDir, 'staged.txt'));
    {$ifdef UNIX}
    AssertEquals('the mode of the work tree', '100755', Copy(Git(['ls-tree', 'HEAD', 'a.txt']), 1, 6));
    {$endif}
    AssertEquals(' M a.txt'#0'M  staged.txt'#0, Git(['status', '--porcelain', '-z']));

    WriteFile('.git/hooks/pre-commit',
      '#!/bin/sh'#10'echo "hook says no" >&2'#10'exit 1'#10);
    Hook := IncludeTrailingPathDelimiter(FDir) + SetDirSeparators('.git/hooks/pre-commit');
    {$ifdef UNIX}
    RunCommandIndir(FDir, 'chmod', ['+x', Hook], Text, Code, []);
    {$endif}
    Paths.Clear;
    Paths.Add('a.txt');
    Parts[0].Text := 'ONE'#10'two'#10'THREE'#10;
    AssertFalse(FRepo.Commit('blocked', Paths, False, Id, Parts));
    AssertTrue(FRepo.Error, Pos('hook says no', FRepo.Error) > 0);
    AssertEquals(' M a.txt'#0'M  staged.txt'#0, Git(['status', '--porcelain', '-z']));

    { Through the temporary index too: past the hook, signed off. }
    AssertTrue(FRepo.Error, FRepo.Commit('amended', Paths, True, Id, Parts,
      [coNoVerify, coSignOff]));
    AssertEquals(Parent, Trim(Git(['rev-parse', 'HEAD~1'])));
    AssertEquals('ONE'#10'two'#10'THREE'#10, HeadFile(FDir, 'a.txt'));
    AssertEquals('the amended commit keeps its files', 'new'#10, HeadFile(FDir, 'new.txt'));
    AssertTrue(FRepo.HeadMessage(Text));
    AssertEquals(Text, 1, Pos('amended'#10#10'Signed-off-by: ', Text));
    AssertEquals('M  staged.txt'#0, Git(['status', '--porcelain', '-z']));
  finally
    Paths.Free;
  end;
end;

{ A merge cannot commit some files only: while a conflict is left it
  is refused, once it is resolved the chosen files are added and the
  whole index committed, with both parents. }
procedure TGitRepoTest.TestCommitMerge;
var
  Paths: TStringList;
  Parts: TGittanCommitParts;
  Branch, Output, Id: string;
  Code: integer;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  Branch := Trim(Git(['rev-parse', '--abbrev-ref', 'HEAD']));
  Git(['checkout', '-q', '-b', 'topic']);
  WriteFile('a.txt', 'topic'#10);
  Commit('topic');
  Git(['checkout', '-q', Branch]);
  WriteFile('a.txt', 'main'#10);
  Commit('main');
  RunCommandIndir(FDir, 'git', ['merge', 'topic'], Output, Code, [poStderrToOutPut]);
  AssertTrue('merge stops', Code <> 0);
  WriteFile('a.txt', 'both'#10);
  WriteFile('extra.txt', 'extra'#10);
  Paths := TStringList.Create;
  try
    Paths.Add('a.txt');
    Paths.Add('extra.txt');
    AssertFalse(FRepo.Commit('merged', Paths, False, Id));
    AssertTrue(FRepo.Error, Pos('a.txt', FRepo.Error) > 0);
    Git(['add', 'a.txt']);
    { A part goes into the index the merge commits. }
    WriteFile('extra.txt', 'extra'#10'left out'#10);
    SetLength(Parts, 1);
    Parts[0].Path := 'extra.txt';
    Parts[0].Text := 'extra'#10;
    AssertTrue(FRepo.Error, FRepo.Commit('merged', Paths, False, Id, Parts));
  finally
    Paths.Free;
  end;
  AssertEquals('', FRepo.Operation);
  AssertEquals(Trim(Git(['rev-parse', 'topic'])), Trim(Git(['rev-parse', 'HEAD^2'])));
  AssertEquals('both'#10, HeadFile(FDir, 'a.txt'));
  AssertEquals('extra'#10, HeadFile(FDir, 'extra.txt'));
  AssertEquals(' M extra.txt'#0, Git(['status', '--porcelain', '-z']));
end;

{ Gittan's PATH comes first and no folder twice; git is found on it,
  and the hooks git runs get it as their PATH. }
procedure TGitRepoTest.TestToolSearchPath;
var
  Dirs: TStringList;
  Paths: TStringList;
  Own, Id, Text: string;
  Code: integer;
begin
  Own := GetEnvironmentVariable('PATH');
  AssertTrue(ToolSearchPath, Pos(Own, ToolSearchPath) = 1);
  Dirs := TStringList.Create;
  try
    Dirs.Sorted := True;
    Dirs.Duplicates := dupError;
    for Text in Copy(ToolSearchPath, Length(Own) + 1, MaxInt).Split([PathSeparator]) do
      if Text <> '' then
      begin
        AssertTrue('not in PATH already: ' + Text,
          Pos(PathSeparator + Text + PathSeparator, PathSeparator + Own + PathSeparator) = 0);
        Dirs.Add(Text);
      end;
  finally
    Dirs.Free;
  end;
  AssertTrue(FindTool('git') <> '');
  AssertEquals('', FindTool('no-such-tool-gittan'));
  AssertEquals('git runs by the git found', FindTool('git'), GitExe);
  SetGitExe('/no/such/git');
  AssertEquals('/no/such/git', GitExe);
  SetGitExe('');
  AssertEquals('back to the git found', FindTool('git'), GitExe);
  {$ifdef UNIX}
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  WriteFile('.git/hooks/pre-commit', '#!/bin/sh'#10'printf %s "$PATH" > ../hook-path'#10);
  RunCommandIndir(FDir, 'chmod', ['+x', '.git/hooks/pre-commit'], Text, Code, []);
  WriteFile('a.txt', 'hooked'#10);
  Paths := TStringList.Create;
  try
    Paths.Add('a.txt');
    AssertTrue(FRepo.Error, FRepo.Commit('hooked', Paths, False, Id));
  finally
    Paths.Free;
  end;
  Dirs := TStringList.Create;
  try
    Dirs.LoadFromFile(ExtractFileDir(ExcludeTrailingPathDelimiter(FDir)) + '/hook-path');
    { git puts its own exec path first. }
    AssertTrue(Dirs.Text, Pos(ToolSearchPath, Dirs.Text) > 0);
  finally
    Dirs.Free;
    DeleteFile(ExtractFileDir(ExcludeTrailingPathDelimiter(FDir)) + '/hook-path');
  end;
  {$endif}
end;

{ A second clone of ARemote in AOther commits AFile and pushes, so the
  remote moves on without the test's repository. }
procedure PushFromOther(const ARemote, AOther, AFile: string);
var
  Output: string;
  Code: integer;
  Lines: TStringList;
begin
  if not DirectoryExists(AOther) then
    RunCommandIndir(ExtractFileDir(AOther), 'git', ['clone', '-q', ARemote, AOther],
      Output, Code, [poStderrToOutPut]);
  RunCommandIndir(AOther, 'git', ['pull', '-q', '--ff-only'], Output, Code,
    [poStderrToOutPut]);
  Lines := TStringList.Create;
  try
    Lines.Text := AFile;
    Lines.SaveToFile(IncludeTrailingPathDelimiter(AOther) + AFile);
  finally
    Lines.Free;
  end;
  RunCommandIndir(AOther, 'git', ['add', '-A'], Output, Code, [poStderrToOutPut]);
  RunCommandIndir(AOther, 'git', ['-c', 'user.name=Other', '-c',
    'user.email=other@example.invalid', 'commit', '-q', '-m', AFile], Output, Code,
    [poStderrToOutPut]);
  if Code <> 0 then
    raise Exception.Create('other commit failed: ' + Output);
  RunCommandIndir(AOther, 'git', ['push', '-q'], Output, Code, [poStderrToOutPut]);
  if Code <> 0 then
    raise Exception.Create('other push failed: ' + Output);
end;

{ A push without an upstream makes one; a fetch sees what another clone
  pushed, a pull fast-forwards to it; a push behind the remote is
  rejected. }
{ nvm's default alias is followed through the alias files to a version
  folder, a bare number means the newest version that starts with it,
  and no alias or one naming a version not installed gives the newest
  installed; fnm's default alias is its own folder. }
{ The node folders are named with PathDelim, a backslash on Windows, so
  the expected ones are too. Windows allows no * in a file name, so there
  the default alias names lts/iron itself rather than going through lts/*. }
procedure TGitRepoTest.TestNodeManagerBins;
var
  Nvm, Fnm, Versions: string;
begin
  Nvm := FDir + '-nvm';
  Fnm := FDir + '-fnm';
  Versions := Nvm + '/versions/node/';
  try
    AssertEquals('', NvmNodeBin(Nvm));
    ForceDirectories(Versions + 'v18.20.8/bin');
    ForceDirectories(Versions + 'v20.20.2/bin');
    ForceDirectories(Versions + 'v20.9.0/bin');
    ForceDirectories(Versions + 'v24.21.0/bin');
    ForceDirectories(Versions + 'v9.11.2/bin');
    AssertEquals('newest without alias', SetDirSeparators(Versions + 'v24.21.0/bin'), NvmNodeBin(Nvm));
    ForceDirectories(Nvm + '/alias/lts');
    {$ifdef windows}
    WriteFile('../' + ExtractFileName(Nvm) + '/alias/default', 'lts/iron'#10);
    {$else}
    WriteFile('../' + ExtractFileName(Nvm) + '/alias/default', 'lts/*'#10);
    WriteFile('../' + ExtractFileName(Nvm) + '/alias/lts/*', 'lts/iron'#10);
    {$endif}
    WriteFile('../' + ExtractFileName(Nvm) + '/alias/lts/iron', 'v20.20.2'#10);
    AssertEquals('through the aliases', SetDirSeparators(Versions + 'v20.20.2/bin'), NvmNodeBin(Nvm));
    WriteFile('../' + ExtractFileName(Nvm) + '/alias/default', '20'#10);
    AssertEquals('newest 20', SetDirSeparators(Versions + 'v20.20.2/bin'), NvmNodeBin(Nvm));
    WriteFile('../' + ExtractFileName(Nvm) + '/alias/default', '20.9'#10);
    AssertEquals('newest 20.9', SetDirSeparators(Versions + 'v20.9.0/bin'), NvmNodeBin(Nvm));
    WriteFile('../' + ExtractFileName(Nvm) + '/alias/default', 'v16.20.2'#10);
    AssertEquals('not installed', SetDirSeparators(Versions + 'v24.21.0/bin'), NvmNodeBin(Nvm));
    WriteFile('../' + ExtractFileName(Nvm) + '/alias/default', 'loop'#10);
    WriteFile('../' + ExtractFileName(Nvm) + '/alias/loop', 'loop'#10);
    AssertEquals('alias loop', SetDirSeparators(Versions + 'v24.21.0/bin'), NvmNodeBin(Nvm));

    AssertEquals('', FnmNodeBin(Fnm));
    ForceDirectories(Fnm + '/node-versions/v22.0.0/installation/bin');
    ForceDirectories(Fnm + '/node-versions/v23.1.0/installation/bin');
    AssertEquals(SetDirSeparators(Fnm + '/node-versions/v23.1.0/installation/bin'), FnmNodeBin(Fnm));
    ForceDirectories(Fnm + '/aliases/default/bin');
    AssertEquals(SetDirSeparators(Fnm + '/aliases/default/bin'), FnmNodeBin(Fnm));
  finally
    RemoveTree(Nvm);
    RemoveTree(Fnm);
  end;
end;

procedure TGitRepoTest.Collect(const AText: string);
begin
  FCollected := FCollected + AText;
end;

procedure TGitRepoTest.TestPushFetchPull;
var
  Remote, Other, Output: string;
  Code, Ahead, Behind: integer;
  Rejected, Diverged: boolean;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  AssertFalse('no remote', FRepo.Push(Rejected));
  AssertFalse(Rejected);
  Remote := FDir + '-remote';
  Other := FDir + '-other';
  RunCommandIndir(FDir, 'git', ['init', '-q', '--bare', Remote], Output, Code,
    [poStderrToOutPut]);
  try
    Git(['remote', 'add', 'origin', Remote]);
    AssertTrue(FRepo.Error, FRepo.Push(Rejected));
    AssertTrue('upstream set', FRepo.AheadBehind(Ahead, Behind));
    AssertEquals(0, Ahead);
    WriteFile('a.txt', 'pushed'#10);
    Commit('to push');
    AssertTrue(FRepo.AheadBehind(Ahead, Behind));
    AssertEquals(1, Ahead);
    AssertTrue(FRepo.Error, FRepo.Push(Rejected));
    AssertTrue(FRepo.AheadBehind(Ahead, Behind));
    AssertEquals(0, Ahead);

    PushFromOther(Remote, Other, 'other.txt');
    AssertTrue(FRepo.AheadBehind(Ahead, Behind));
    AssertEquals('not fetched yet', 0, Behind);
    AssertTrue(FRepo.Error, FRepo.Fetch);
    AssertTrue(FRepo.AheadBehind(Ahead, Behind));
    AssertEquals(1, Behind);
    AssertTrue(FRepo.Error, FRepo.Pull(pmAuto, Diverged));
    AssertTrue(FRepo.AheadBehind(Ahead, Behind));
    AssertEquals(0, Behind);
    AssertTrue(FileExists(IncludeTrailingPathDelimiter(FDir) + 'other.txt'));

    PushFromOther(Remote, Other, 'more.txt');
    WriteFile('a.txt', 'mine'#10);
    Commit('mine');
    AssertFalse(FRepo.Push(Rejected));
    AssertTrue(FRepo.Error, Rejected);
  finally
    RemoveTree(Remote);
    RemoveTree(Other);
  end;
end;

{ A pre-push hook that refuses (husky's, say) stops the push, with its
  output as the error and not as a rejection; the hook runs with
  Gittan's PATH, so it finds node wherever nvm or the like put it. }
procedure TGitRepoTest.TestPushHook;
var
  Remote, Output, Text: string;
  Code: integer;
  Rejected: boolean;
  Lines: TStringList;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  Remote := FDir + '-remote';
  RunCommandIndir(FDir, 'git', ['init', '-q', '--bare', Remote], Output, Code,
    [poStderrToOutPut]);
  try
    Git(['remote', 'add', 'origin', Remote]);
    AssertFalse('no hook yet', FRepo.HasHook('pre-push'));
    WriteFile('.git/hooks/pre-push',
      '#!/bin/sh'#10'printf %s "$PATH" > ../hook-path'#10'echo "hook says no"'#10'exit 1'#10);
    {$ifdef UNIX}
    RunCommandIndir(FDir, 'chmod', ['+x', '.git/hooks/pre-push'], Text, Code, []);
    {$endif}
    AssertTrue('hook', FRepo.HasHook('pre-push'));
    AssertFalse('other hook', FRepo.HasHook('pre-commit'));
    FRepo.OnOutput := @Collect;
    AssertFalse(FRepo.Push(Rejected));
    AssertFalse(Rejected);
    AssertTrue(FRepo.Error, Pos('hook says no', FRepo.Error) > 0);
    AssertTrue(FCollected, Pos('hook says no', FCollected) > 0);
    AssertTrue(FCollected, Pos('failed to push', FCollected) > 0);
    { husky keeps the hooks under core.hooksPath. }
    Git(['config', 'core.hooksPath', '.husky/_']);
    AssertFalse('hooksPath empty', FRepo.HasHook('pre-push'));
    WriteFile('.husky/_/pre-push', '#!/bin/sh'#10'exit 0'#10);
    AssertTrue('hooksPath', FRepo.HasHook('pre-push'));
    Git(['config', '--unset', 'core.hooksPath']);
    AssertEquals('nothing pushed', '', Trim(Git(['ls-remote', '--heads', 'origin'])));
    {$ifdef UNIX}
    Lines := TStringList.Create;
    try
      Lines.LoadFromFile(ExtractFileDir(ExcludeTrailingPathDelimiter(FDir)) + '/hook-path');
      AssertTrue(Lines.Text, Pos(ToolSearchPath, Lines.Text) > 0);
    finally
      Lines.Free;
      DeleteFile(ExtractFileDir(ExcludeTrailingPathDelimiter(FDir)) + '/hook-path');
    end;
    {$endif}
    DeleteFile(IncludeTrailingPathDelimiter(FDir) + SetDirSeparators('.git/hooks/pre-push'));
    AssertTrue(FRepo.Error, FRepo.Push(Rejected));
  finally
    RemoveTree(Remote);
  end;
end;

{ Told nothing, a pull only fast-forwards and says when the branch has
  diverged; merge and rebase then join the two, the rebase with a local
  change stashed for the time it runs. The config is set here, so the
  user's own pull settings do not count. }
procedure TGitRepoTest.TestPullDiverged;
var
  Remote, Other, Output: string;
  Code: integer;
  Rejected, Diverged: boolean;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  Remote := FDir + '-remote';
  Other := FDir + '-other';
  RunCommandIndir(FDir, 'git', ['init', '-q', '--bare', Remote], Output, Code,
    [poStderrToOutPut]);
  try
    Git(['remote', 'add', 'origin', Remote]);
    AssertTrue(FRepo.Error, FRepo.Push(Rejected));
    PushFromOther(Remote, Other, 'one.txt');
    WriteFile('a.txt', 'mine'#10);
    Commit('mine');
    Git(['config', 'pull.rebase', 'false']);
    Git(['config', 'pull.ff', 'only']);
    AssertFalse(FRepo.Pull(pmAuto, Diverged));
    AssertTrue(FRepo.Error, Diverged);
    AssertTrue(FRepo.Error, FRepo.Pull(pmMerge, Diverged));
    { A merge commit: its second parent is there (Git fails otherwise). }
    Git(['rev-parse', '-q', '--verify', 'HEAD^2']);
    AssertTrue(FRepo.Error, FRepo.Push(Rejected));

    PushFromOther(Remote, Other, 'two.txt');
    WriteFile('a.txt', 'mine again'#10);
    Commit('mine again');
    WriteFile('del.txt', 'local change'#10);
    AssertTrue(FRepo.Error, FRepo.Pull(pmRebase, Diverged));
    RunCommandIndir(FDir, 'git', ['rev-parse', '-q', '--verify', 'HEAD^2'], Output, Code, []);
    AssertTrue('no merge commit', Code <> 0);
    AssertTrue(FileExists(IncludeTrailingPathDelimiter(FDir) + 'two.txt'));
    AssertEquals(' M del.txt'#0, Git(['status', '--porcelain', '-z']));
  finally
    RemoveTree(Remote);
    RemoveTree(Other);
  end;
end;

procedure TGitRepoTest.TestRemoteEnvironment;
var
  Env: TStringArray;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  Env := FRepo.RemoteEnvironment;
  if (GetEnvironmentVariable('GIT_SSH_COMMAND') = '') and
    (GetEnvironmentVariable('GIT_SSH') = '') then
  begin
    AssertEquals(1, Length(Env));
    AssertEquals('GIT_SSH_COMMAND=ssh -o BatchMode=yes', Env[0]);
  end;
  Git(['config', 'core.sshCommand', 'ssh -i key']);
  AssertEquals('the user runs ssh their own way', 0, Length(FRepo.RemoteEnvironment));
end;

{ Sets a variable in the test's own environment, as the shell that
  started Gittan would have. On Windows the process has one environment,
  which SetEnvironmentVariableW changes (the Windows unit's
  SetEnvironmentVariable is the ANSI one, which could not carry an ö).
  On Unix the RTL's GetEnvironmentString reads envp, the array the
  program started with, while a libc-based lookup (fpgetenv on macOS)
  reads libc's own, so both get the variable: in envp in the place of
  the one the program started with, if it had it (a process given the
  name twice may read the first), else in a longer copy of envp, last. }
{$ifdef windows}
function SetEnvironmentVariableW(AName, AValue: PWideChar): LongBool; stdcall;
  external 'kernel32' name 'SetEnvironmentVariableW';
{$else}
function setenv(AName, AValue: PChar; AOverwrite: longint): longint; cdecl;
  external 'c';
{$endif}
procedure SetTestVariable(const AName, AValue: string);
{$ifndef windows}
var
  Count: integer;
  Wider: PPChar;
{$endif}
begin
  {$ifdef windows}
  SetEnvironmentVariableW(PWideChar(UnicodeString(AName)),
    PWideChar(UnicodeString(AValue)));
  {$else}
  setenv(PChar(AName), PChar(AValue), 1);
  Count := 0;
  while envp[Count] <> nil do
  begin
    if StrLComp(envp[Count], PChar(AName + '='), Length(AName) + 1) = 0 then
    begin
      envp[Count] := StrNew(PChar(AName + '=' + AValue));
      Exit;
    end;
    Inc(Count);
  end;
  Wider := GetMem((Count + 2) * SizeOf(PChar));
  Move(envp^, Wider^, Count * SizeOf(PChar));
  Wider[Count] := StrNew(PChar(AName + '=' + AValue));
  Wider[Count + 1] := nil;
  envp := Wider;
  {$endif}
end;

{ A variable with a non-ASCII value reaches git as it is: on Windows the
  RTL's own environment functions turn the ö of USERPROFILE=C:\Users\Björn
  into ÷, and git could not lock C:/Users/Bj÷rn/.gitconfig. The alias
  runs in git's shell, which prints what git was given. }
procedure TGitRepoTest.TestEnvironmentUtf8;
var
  Env, Output, Err: string;
  Found: boolean;
begin
  SetTestVariable('GITTAN_TEST_NAME', 'Björn');
  AssertEquals('Björn', EnvironmentVariable('GITTAN_TEST_NAME'));
  AssertEquals('', EnvironmentVariable('GITTAN_TEST_UNSET'));
  Found := False;
  for Env in EnvironmentStrings do
    if Env = 'GITTAN_TEST_NAME=Björn' then
      Found := True;
  AssertTrue('GITTAN_TEST_NAME=Björn in EnvironmentStrings', Found);
  AssertTrue(Err, RunGitIn(FDir, ['-c', 'alias.gittan-env=!echo "$GITTAN_TEST_NAME"',
    'gittan-env'], Output, Err));
  AssertEquals('Björn', Trim(Output));
end;

{ Two branches that change a.txt each their own way, topic also
  deleting del.txt where the default branch changes it; the default
  branch is checked out. Answers its name. }
function MakeDiverged(ATest: TGitRepoTest): string;
begin
  ATest.MakeHistory;
  ATest.Git(['config', 'user.name', 'Gittan Test']);
  ATest.Git(['config', 'user.email', 'test@example.invalid']);
  Result := Trim(ATest.Git(['rev-parse', '--abbrev-ref', 'HEAD']));
  ATest.Git(['checkout', '-q', '-b', 'topic']);
  ATest.WriteFile('a.txt', 'topic'#10);
  ATest.Git(['rm', '-q', 'del.txt']);
  ATest.Commit('topic');
  ATest.Git(['checkout', '-q', Result]);
  ATest.WriteFile('a.txt', 'main'#10);
  ATest.WriteFile('del.txt', 'changed'#10);
  ATest.Commit('main');
end;

{ git stops on a conflict with a failure, so it runs without the helper. }
procedure GitStops(const ADir: string; const AArgs: array of string);
var
  Output: string;
  Code: integer;
begin
  RunCommandIndir(ADir, 'git', AArgs, Output, Code, [poStderrToOutPut]);
  if Code = 0 then
    raise Exception.Create('git did not stop: ' + Output);
end;

{ The file's bytes as they are: a TStringList's Text would end every line
  with LineEnding, CRLF on Windows, whatever the file has. }
function FileText(const AFileName: string): string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(AFileName, fmOpenRead);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

{ A conflict in a file with CRLF line ends, with the base between the
  sides: the change view's lines have no CRs left, so every marker reads
  as one, and resolving it keeps the file's line ends. }
procedure TGitRepoTest.TestConflictCrlf;
var
  Lines: TStringList;
  Roles: TIntegerDynArray;
  Block: TGittanDiscard;
  Err: string;
  i: integer;
begin
  Git(['init', '-q', '-b', 'main']);
  Git(['config', 'core.autocrlf', 'false']);
  Git(['config', 'merge.conflictStyle', 'diff3']);
  WriteFile('f.txt', 'one'#13#10'two'#13#10'three'#13#10);
  Commit('base');
  Git(['checkout', '-q', '-b', 'other']);
  WriteFile('f.txt', 'one'#13#10'TWO other'#13#10'three'#13#10);
  Commit('other');
  Git(['checkout', '-q', 'main']);
  WriteFile('f.txt', 'one'#13#10'TWO main'#13#10'three'#13#10);
  Commit('main');
  GitStops(FDir, ['merge', 'other']);
  AssertTrue(FRepo.Open(FDir));
  Lines := TStringList.Create;
  try
    AssertTrue(FRepo.FileChanges('f.txt', Lines));
    { Line by line: Text would join them with LineEnding, CRLF on
      Windows. }
    for i := 0 to Lines.Count - 1 do
      AssertEquals('no CR left in line ' + IntToStr(i), 0, Pos(#13, Lines[i]));
    Roles := ConflictRoles(Lines);
    AssertEquals(1, ConflictCount(Roles, Lines));
    AssertEquals('the four markers', 4, Ord(Roles[1] = crMarker) + Ord(Roles[3] = crMarker) +
      Ord(Roles[5] = crMarker) + Ord(Roles[7] = crMarker));
    AssertEquals(crOurs, Roles[2]);
    AssertEquals(crBase, Roles[4]);
    AssertEquals(crTheirs, Roles[6]);
    Block := ResolveBlock(Lines, Roles, 1, cpOurs, FRepo.Root + PathDelim + 'f.txt');
    AssertTrue(Err, DiscardBlock(Block, Err));
  finally
    Lines.Free;
  end;
  AssertEquals('one'#13#10'TWO main'#13#10'three'#13#10, FileText(FDir + PathDelim + 'f.txt'));
end;

procedure TGitRepoTest.TestResolveMerge;
var
  Branch: string;
begin
  Branch := MakeDiverged(Self);
  { git comments the conflicts out of the message with this. }
  Git(['config', 'core.commentChar', ';']);
  AssertTrue(FRepo.Open(FDir));
  GitStops(FDir, ['merge', 'topic']);
  AssertEquals('merging', FRepo.Operation);
  AssertTrue(FRepo.MergeMessage, Pos('Merge branch ''topic''', FRepo.MergeMessage) = 1);
  AssertEquals('the comments left out', 0, Pos('Conflicts', FRepo.MergeMessage));
  AssertFalse('conflicts left', FRepo.ContinueOperation);
  AssertEquals('merging', FRepo.Operation);
  AssertTrue(FRepo.Error, FRepo.ResolveConflict('a.txt', csTheirs));
  AssertEquals('topic'#10, FileText(IncludeTrailingPathDelimiter(FDir) + 'a.txt'));
  AssertTrue(FRepo.Error, FRepo.ResolveConflict('del.txt', csTheirs));
  AssertFalse('theirs deleted it', FileExists(IncludeTrailingPathDelimiter(FDir) + 'del.txt'));
  AssertTrue(FRepo.Error, FRepo.ContinueOperation);
  AssertEquals('', FRepo.Operation);
  AssertEquals(Trim(Git(['rev-parse', 'topic'])), Trim(Git(['rev-parse', 'HEAD^2'])));
  AssertEquals(Branch, FRepo.Branch);
end;

{ In a rebase mine is the commit being replayed, git's theirs. }
procedure TGitRepoTest.TestResolveRebase;
var
  Branch: string;
begin
  Branch := MakeDiverged(Self);
  AssertTrue(FRepo.Open(FDir));
  Git(['checkout', '-q', 'topic']);
  GitStops(FDir, ['rebase', Branch]);
  AssertEquals('rebasing', FRepo.Operation);
  AssertTrue(FRepo.Error, FRepo.ResolveConflict('a.txt', csMine));
  AssertEquals('topic'#10, FileText(IncludeTrailingPathDelimiter(FDir) + 'a.txt'));
  AssertTrue(FRepo.Error, FRepo.ResolveConflict('del.txt', csMine));
  AssertFalse(FileExists(IncludeTrailingPathDelimiter(FDir) + 'del.txt'));
  AssertTrue(FRepo.Error, FRepo.ContinueOperation);
  AssertEquals('', FRepo.Operation);
  AssertEquals('topic', FRepo.Branch);
  AssertEquals(Trim(Git(['rev-parse', Branch])), Trim(Git(['rev-parse', 'HEAD^'])));
end;

procedure TGitRepoTest.TestMarkResolvedAndAbort;
begin
  MakeDiverged(Self);
  AssertTrue(FRepo.Open(FDir));
  GitStops(FDir, ['merge', 'topic']);
  WriteFile('a.txt', 'both'#10);
  AssertTrue(FRepo.Error, FRepo.MarkResolved('a.txt'));
  { Deleted on disk: resolved as deleted. }
  DeleteFile(IncludeTrailingPathDelimiter(FDir) + 'del.txt');
  AssertTrue(FRepo.Error, FRepo.MarkResolved('del.txt'));
  AssertEquals('', Git(['ls-files', '-u']));
  AssertTrue(FRepo.Error, FRepo.AbortOperation);
  AssertEquals('', FRepo.Operation);
  AssertEquals('main'#10, FileText(IncludeTrailingPathDelimiter(FDir) + 'a.txt'));
  AssertFalse('nothing to abort', FRepo.AbortOperation);
end;

{ Undo Discard of the pick that took a file's last conflict: the markers
  are written back and the file is in conflict again, edited or deleted. }
procedure TGitRepoTest.TestUnresolve;
begin
  MakeDiverged(Self);
  AssertTrue(FRepo.Open(FDir));
  GitStops(FDir, ['merge', 'topic']);
  WriteFile('a.txt', 'both'#10);
  AssertTrue(FRepo.Error, FRepo.MarkResolved('a.txt'));
  DeleteFile(IncludeTrailingPathDelimiter(FDir) + 'del.txt');
  AssertTrue(FRepo.Error, FRepo.MarkResolved('del.txt'));
  AssertEquals('', Git(['ls-files', '-u']));
  WriteFile('a.txt', '<<<<<<< HEAD'#10'main'#10'======='#10'topic'#10'>>>>>>> topic'#10);
  AssertTrue(FRepo.Error, FRepo.Unresolve('a.txt'));
  AssertEquals('<<<<<<< HEAD'#10'main'#10'======='#10'topic'#10'>>>>>>> topic'#10,
    FileText(IncludeTrailingPathDelimiter(FDir) + 'a.txt'));
  AssertTrue(FRepo.Error, FRepo.Unresolve('del.txt'));
  AssertEquals(5, Length(Trim(Git(['ls-files', '-u'])).Split([#10])));
  AssertFalse('conflicts again', FRepo.ContinueOperation);
  { Nothing kept for a file that never was in conflict. }
  WriteFile('new.txt', 'new'#10);
  Git(['add', 'new.txt']);
  AssertFalse(FRepo.Unresolve('new.txt'));
end;

{ At a stop with conflicts, the files changed besides them; the
  resolved ones are no extras, edited again or not. }
procedure TGitRepoTest.TestContinueExtras;
var
  Branch: string;
  Extras: TStringArray;
begin
  Branch := MakeDiverged(Self);
  AssertTrue(FRepo.Open(FDir));
  Git(['checkout', '-q', 'topic']);
  GitStops(FDir, ['rebase', Branch]);
  AssertTrue(FRepo.Error, FRepo.ResolveConflict('a.txt', csMine));
  AssertTrue(FRepo.Error, FRepo.ResolveConflict('del.txt', csMine));
  AssertEquals(0, Length(FRepo.ContinueExtras));
  WriteFile('a.txt', 'topic, edited'#10);
  WriteFile('staged.txt', 'new'#10);
  WriteFile('dir sp/fil å.txt', 'b'#10);
  Extras := FRepo.ContinueExtras;
  AssertEquals(2, Length(Extras));
  AssertEquals('dir sp/fil å.txt', Extras[0]);
  AssertEquals('staged.txt', Extras[1]);
  AssertTrue(FRepo.Error, FRepo.ContinueOperation);
  AssertEquals('', FRepo.Operation);
  AssertEquals('new', Trim(Git(['show', 'HEAD:staged.txt'])));
end;

procedure TGitRepoTest.TestSkip;
var
  Branch: string;
begin
  Branch := MakeDiverged(Self);
  AssertTrue(FRepo.Open(FDir));
  GitStops(FDir, ['merge', 'topic']);
  AssertFalse('a merge has nothing to skip', FRepo.SkipOperation);
  Git(['merge', '--abort']);
  Git(['checkout', '-q', 'topic']);
  GitStops(FDir, ['rebase', Branch]);
  AssertTrue(FRepo.Error, FRepo.SkipOperation);
  AssertEquals('', FRepo.Operation);
  AssertEquals(Trim(Git(['rev-parse', Branch])), Trim(Git(['rev-parse', 'HEAD'])));
end;

{ Two commits on side are replayed onto main, a local change stashed
  along; with an upstream that has the first of them, that one counts as
  pushed. }
procedure TGitRepoTest.TestRebaseOnto;
var
  Main, Base: string;
  Count, Pushed: integer;
  Conflicts: boolean;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  Main := FRepo.Branch;
  Git(['checkout', '-q', '-b', 'side']);
  WriteFile('b.txt', 'b'#10);
  Commit('side one');
  WriteFile('c.txt', 'c'#10);
  Commit('side two');
  Git(['checkout', '-q', Main]);
  WriteFile('d.txt', 'd'#10);
  Commit('main');
  Base := Trim(Git(['rev-parse', 'HEAD']));
  Git(['checkout', '-q', 'side']);

  AssertTrue(FRepo.Error, FRepo.CommitsToRebase(Main, Count, Pushed));
  AssertEquals(2, Count);
  AssertEquals('no upstream', 0, Pushed);
  AssertTrue(FRepo.CommitsToRebase('HEAD', Count, Pushed));
  AssertEquals('nothing since itself', 0, Count);
  AssertFalse(FRepo.CommitsToRebase('no-such-ref', Count, Pushed));
  Git(['branch', 'pub', 'HEAD~1']);
  Git(['branch', '-u', 'pub']);
  AssertTrue(FRepo.Error, FRepo.CommitsToRebase(Main, Count, Pushed));
  AssertEquals(2, Count);
  AssertEquals('side one is on pub', 1, Pushed);

  WriteFile('a.txt', 'edited'#10);
  AssertTrue(FRepo.Error, FRepo.RebaseOnto(Main, Conflicts));
  AssertFalse(Conflicts);
  AssertEquals('', FRepo.Operation);
  AssertEquals('side', FRepo.Branch);
  AssertEquals('on top of main', Base, Trim(Git(['rev-parse', 'HEAD~2'])));
  AssertEquals('side two', Trim(Git(['log', '-1', '--format=%s'])));
  AssertEquals('the local change came back', 'edited'#10,
    FileText(IncludeTrailingPathDelimiter(FDir) + 'a.txt'));
  AssertTrue(FRepo.CommitsToRebase(Main, Count, Pushed));
  AssertEquals(2, Count);
  AssertEquals('rewritten, so no longer on pub', 0, Pushed);
end;

{ How far a branch is behind the default branch: the commits of
  origin/main it lacks, none for a branch that tracks it, for the
  default branch's own name, or on a detached HEAD. A branch without an
  upstream also counts its commits on no remote. }
procedure TGitRepoTest.TestBehindDefault;
var
  Main: string;
  Snap: TGittanRepoSnapshot;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  Main := FRepo.Branch;
  Git(['remote', 'add', 'origin', 'https://example.invalid/repo.git']);
  Git(['checkout', '-q', '-b', 'side']);
  WriteFile('b.txt', 'b'#10);
  Commit('side');
  Git(['checkout', '-q', Main]);
  WriteFile('c.txt', 'c'#10);
  Commit('main one');
  WriteFile('d.txt', 'd'#10);
  Commit('main two');
  Git(['update-ref', 'refs/remotes/origin/main', 'HEAD']);
  Git(['checkout', '-q', 'side']);

  AssertEquals('origin/main', FRepo.DefaultBranch);
  AssertEquals(2, FRepo.BehindDefault('side', 'origin/main'));
  AssertTrue(FRepo.Snapshot(Snap));
  AssertEquals(2, Snap.BehindDefault);
  AssertEquals('side is on no remote', 1, Snap.NotOnRemote);
  AssertEquals(1, FRepo.NotOnRemotes);
  AssertTrue('its commit is not pushed', Snap.Recent[0].Unpushed);
  AssertFalse('the history is on origin/main', Snap.Recent[1].Unpushed);
  AssertEquals('the default branch itself', 0, FRepo.BehindDefault('main', 'origin/main'));
  AssertEquals('no default branch', 0, FRepo.BehindDefault('side', ''));
  Git(['branch', '-q', '-u', 'origin/main']);
  AssertEquals('tracks it', 0, FRepo.BehindDefault('side', 'origin/main'));
  AssertTrue(FRepo.Snapshot(Snap));
  AssertEquals('with an upstream', -1, Snap.NotOnRemote);
  Git(['branch', '-q', '--unset-upstream']);
  Git(['checkout', '-q', '--detach']);
  AssertTrue(FRepo.Snapshot(Snap));
  AssertEquals('detached', 0, Snap.BehindDefault);
  AssertEquals('detached', -1, Snap.NotOnRemote);
end;

{ An amend of a pushed commit leaves the upstream's tip in the branch's
  reflog, so the branch counts as rewritten; a commit pushed to the
  upstream from elsewhere does not, so a pull is the next step then. }
procedure TGitRepoTest.TestUpstreamInReflog;
var
  Snap: TGittanRepoSnapshot;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  Git(['checkout', '-q', '-b', 'side']);
  WriteFile('b.txt', 'b'#10);
  Commit('side');
  Git(['branch', 'pub']);
  Git(['branch', '-q', '-u', 'pub']);
  AssertFalse('nothing to replace', FRepo.Snapshot(Snap) and Snap.Rewritten);

  Git(['commit', '-q', '--amend', '-m', 'side, amended']);
  AssertTrue(FRepo.UpstreamInReflog('side'));
  AssertTrue(FRepo.Snapshot(Snap));
  AssertEquals(1, Snap.Ahead);
  AssertEquals(1, Snap.Behind);
  AssertTrue('amended', Snap.Rewritten);

  Git(['checkout', '-q', 'pub']);
  WriteFile('c.txt', 'c'#10);
  Commit('pushed from elsewhere');
  Git(['checkout', '-q', 'side']);
  AssertFalse(FRepo.UpstreamInReflog('side'));
  AssertTrue(FRepo.Snapshot(Snap));
  AssertFalse('a commit the branch never had', Snap.Rewritten);
  AssertFalse('no upstream', FRepo.UpstreamInReflog('pub'));
end;

{ A rebase that stops with conflicts is left for the Commit section,
  and can be aborted. }
procedure TGitRepoTest.TestRebaseOntoConflicts;
var
  Branch: string;
  Conflicts: boolean;
begin
  Branch := MakeDiverged(Self);
  AssertTrue(FRepo.Open(FDir));
  Git(['checkout', '-q', 'topic']);
  AssertFalse(FRepo.RebaseOnto(Branch, Conflicts));
  AssertTrue('conflicts', Conflicts);
  AssertEquals('rebasing', FRepo.Operation);
  AssertEquals('topic', FRepo.RebaseBranch);
  AssertTrue(FRepo.Error, FRepo.AbortOperation);
  AssertEquals('', FRepo.Operation);
  AssertEquals('topic', FRepo.Branch);
end;

{ A rebase left behind: it stopped with conflicts, they were resolved,
  and a checkout in a terminal put HEAD on another branch, where a commit
  was made. git still has the rebase going, of the topic branch, while
  HEAD is on the other one, which the snapshot tells apart; --quit
  forgets the rebase and keeps HEAD, the commit and the files. }
procedure TGitRepoTest.TestRebaseStray;
var
  Branch, Head: string;
  Conflicts: boolean;
  Snap: TGittanRepoSnapshot;
begin
  Branch := MakeDiverged(Self);
  AssertTrue(FRepo.Open(FDir));
  Git(['checkout', '-q', 'topic']);
  AssertFalse(FRepo.RebaseOnto(Branch, Conflicts));
  AssertTrue('conflicts', Conflicts);
  { Stopped: HEAD is detached, the snapshot names the rebased branch. }
  AssertTrue(FRepo.Snapshot(Snap));
  AssertTrue('detached', Snap.Detached);
  AssertEquals(FRepo.CommitId('HEAD'), Snap.Head);
  AssertEquals('rebasing', Snap.Operation);
  AssertEquals('topic', Snap.RebaseBranch);
  AssertTrue(FRepo.ResolveConflict('a.txt', csMine));
  AssertTrue(FRepo.MarkResolved('del.txt'));
  Git(['checkout', '-q', Branch]);
  WriteFile('b.txt', 'on main'#10);
  Commit('on main');
  Head := Trim(Git(['rev-parse', 'HEAD']));
  AssertTrue(FRepo.Snapshot(Snap));
  AssertFalse('detached', Snap.Detached);
  AssertEquals(Branch, Snap.Branch);
  AssertEquals('rebasing', Snap.Operation);
  AssertEquals('topic', Snap.RebaseBranch);
  AssertTrue(FRepo.Error, FRepo.QuitOperation);
  AssertEquals('', FRepo.Operation);
  AssertEquals(Branch, FRepo.Branch);
  AssertEquals(Head, Trim(Git(['rev-parse', 'HEAD'])));
  AssertEquals('on main', Trim(Git(['log', '-1', '--format=%s', 'HEAD'])));
  AssertEquals('topic', Trim(Git(['log', '-1', '--format=%s', 'topic'])));
  AssertFalse(FRepo.QuitOperation);
end;

{ The commits after the first, replayed in another order: the fourth
  squashed into the third with the messages joined, then the second
  with another message. }
procedure TGitRepoTest.TestRebaseInteractive;
var
  First, Main: string;
  Steps: TGittanRebaseSteps;
  Swap: TGittanRebaseStep;
  Merges, Conflicts, Stopped: boolean;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  First := Trim(Git(['rev-parse', 'HEAD']));
  Main := Trim(Git(['rev-parse', '--abbrev-ref', 'HEAD']));
  WriteFile('b.txt', 'b'#10);
  Commit('second');
  WriteFile('c.txt', 'c'#10);
  Commit('third'#10#10'third body');
  WriteFile('d.txt', 'd'#10);
  Commit('fourth');
  AssertTrue(FRepo.Open(FDir));
  AssertTrue(FRepo.Error, FRepo.RebaseSteps(First, Steps, Merges));
  AssertFalse('merges', Merges);
  AssertEquals(3, Length(Steps));
  AssertEquals('second', Steps[0].Subject);
  AssertEquals('third', Steps[1].Subject);
  AssertEquals('third body', Steps[1].Body);
  AssertEquals('third' + LineEnding + LineEnding + 'third body', Steps[1].Message);
  AssertEquals('fourth', Steps[2].Subject);
  AssertEquals('Gittan Test', Steps[2].Author);
  AssertFalse('pushed', Steps[0].Pushed);
  AssertTrue(Steps[0].Action = raPick);

  Steps[0].Action := raReword;
  Steps[0].Message := 'second, reworded';
  Steps[2].Action := raSquash;
  Swap := Steps[0];
  Steps[0] := Steps[1];
  Steps[1] := Steps[2];
  Steps[2] := Swap;
  AssertTrue(FRepo.Error, FRepo.RebaseInteractive(First, Steps, Conflicts, Stopped));
  AssertFalse(Conflicts);
  AssertFalse(Stopped);
  AssertEquals('', FRepo.Operation);
  AssertEquals(Main, FRepo.Branch);
  AssertEquals('second, reworded|third|files', Trim(Git(['log', '--format=%s', '-n', '3'])).Replace(#10, '|'));
  AssertEquals('third'#10#10'third body'#10#10'fourth', Trim(Git(['log', '-1', '--format=%B',
    'HEAD~1'])));
  AssertEquals('c.txt d.txt', Trim(Git(['diff', '--name-only', 'HEAD~2', 'HEAD~1'])).Replace(#10, ' '));
  AssertEquals('b.txt', Trim(Git(['diff', '--name-only', 'HEAD~1', 'HEAD'])));
  AssertFalse('files left', DirectoryExists(IncludeTrailingPathDelimiter(FRepo.GitDir) +
    'gittan-rebase'));

  { A merge among the commits is reported. }
  Git(['checkout', '-q', '-b', 'side', First]);
  WriteFile('s.txt', 's'#10);
  Commit('side');
  Git(['checkout', '-q', Main]);
  Git(['merge', '-q', '--no-ff', '-m', 'merge side', 'side']);
  AssertTrue(FRepo.Error, FRepo.RebaseSteps(First, Steps, Merges));
  AssertTrue('merges', Merges);
  AssertEquals(4, Length(Steps));
end;

{ An edit stops the rebase after the commit, with nothing in conflict;
  the Commit section's Continue amends what is changed into it. }
procedure TGitRepoTest.TestRebaseInteractiveEdit;
var
  First: string;
  Steps: TGittanRebaseSteps;
  Merges, Conflicts, Stopped: boolean;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  First := Trim(Git(['rev-parse', 'HEAD']));
  WriteFile('b.txt', 'b'#10);
  Commit('second');
  WriteFile('c.txt', 'c'#10);
  Commit('third');
  AssertTrue(FRepo.Open(FDir));
  AssertTrue(FRepo.Error, FRepo.RebaseSteps(First, Steps, Merges));
  Steps[0].Action := raEdit;
  AssertFalse(FRepo.RebaseInteractive(First, Steps, Conflicts, Stopped));
  AssertTrue('stopped', Stopped);
  AssertFalse('conflicts', Conflicts);
  AssertEquals('rebasing', FRepo.Operation);
  AssertEquals(Steps[0].Hash, FRepo.RebaseStoppedAt);
  WriteFile('b.txt', 'edited'#10);
  AssertEquals('an edit stop takes them unasked', 0, Length(FRepo.ContinueExtras));
  AssertTrue(FRepo.Error, FRepo.ContinueOperation);
  AssertEquals('', FRepo.Operation);
  AssertEquals('', FRepo.RebaseStoppedAt);
  AssertEquals('third|second|files', Trim(Git(['log', '--format=%s', '-n', '3'])).Replace(#10, '|'));
  AssertEquals('edited', Trim(Git(['show', 'HEAD~1:b.txt'])));
  AssertFalse('files left', DirectoryExists(IncludeTrailingPathDelimiter(FRepo.GitDir) +
    'gittan-rebase'));
end;

{ Two commits to the same lines in the other order clash; the abort
  puts the branch back. }
procedure TGitRepoTest.TestRebaseInteractiveConflicts;
var
  First, Head: string;
  Steps: TGittanRebaseSteps;
  Swap: TGittanRebaseStep;
  Merges, Conflicts, Stopped: boolean;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  First := Trim(Git(['rev-parse', 'HEAD']));
  WriteFile('a.txt', 'second'#10);
  Commit('second');
  WriteFile('a.txt', 'third'#10);
  Commit('third');
  Head := Trim(Git(['rev-parse', 'HEAD']));
  AssertTrue(FRepo.Open(FDir));
  AssertTrue(FRepo.Error, FRepo.RebaseSteps(First, Steps, Merges));
  Swap := Steps[0];
  Steps[0] := Steps[1];
  Steps[1] := Swap;
  AssertFalse(FRepo.RebaseInteractive(First, Steps, Conflicts, Stopped));
  AssertTrue('conflicts', Conflicts);
  AssertFalse('stopped', Stopped);
  AssertEquals('rebasing', FRepo.Operation);
  AssertTrue(FRepo.Error, FRepo.AbortOperation);
  AssertEquals('', FRepo.Operation);
  AssertEquals(Head, Trim(Git(['rev-parse', 'HEAD'])));
  AssertFalse('files left', DirectoryExists(IncludeTrailingPathDelimiter(FRepo.GitDir) +
    'gittan-rebase'));
end;

procedure TGitRepoTest.TestCommitActions;
var
  First, Side, Main: string;
  Conflicts: boolean;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  First := Trim(Git(['rev-parse', 'HEAD']));
  Main := FRepo.Branch;
  AssertTrue(FRepo.IsBranchName('feature/x'));
  AssertFalse(FRepo.IsBranchName('bad..name'));
  AssertFalse(FRepo.IsBranchName(''));

  AssertTrue(FRepo.Error, FRepo.CreateBranch('side', First, False));
  AssertEquals('not switched', Main, FRepo.Branch);
  AssertFalse('taken', FRepo.CreateBranch('side', First, False));
  AssertFalse(FRepo.CreateBranch('bad..name', First, False));
  AssertTrue(FRepo.Error, FRepo.CreateTag('v1', First, ''));
  AssertEquals('commit', Trim(Git(['cat-file', '-t', 'v1'])));
  AssertTrue(FRepo.Error, FRepo.CreateTag('v2', First, 'Release two'));
  AssertEquals('annotated', 'tag', Trim(Git(['cat-file', '-t', 'v2'])));

  Git(['checkout', '-q', 'side']);
  WriteFile('b.txt', 'b'#10);
  Commit('side change');
  Side := Trim(Git(['rev-parse', 'HEAD']));
  Git(['checkout', '-q', Main]);
  AssertTrue(FRepo.IsAncestor(First, Side));
  AssertFalse(FRepo.IsAncestor(Side, 'HEAD'));

  AssertTrue(FRepo.Error, FRepo.CherryPick(Side, Conflicts));
  AssertFalse(Conflicts);
  AssertEquals('side change', Trim(Git(['log', '-1', '--format=%s'])));
  AssertTrue(FileExists(IncludeTrailingPathDelimiter(FDir) + 'b.txt'));
  AssertTrue(FRepo.Error, FRepo.RevertCommit('HEAD', Conflicts));
  AssertFalse(FileExists(IncludeTrailingPathDelimiter(FDir) + 'b.txt'));
  AssertTrue(Pos('Revert', Git(['log', '-1', '--format=%s'])) = 1);

  AssertTrue(FRepo.Error, FRepo.Reset(First, rmSoft));
  AssertEquals(First, Trim(Git(['rev-parse', 'HEAD'])));
  AssertTrue(FRepo.Error, FRepo.MergeRef('side', Conflicts));
  AssertEquals('a fast-forward', Side, Trim(Git(['rev-parse', 'HEAD'])));
  WriteFile('a.txt', 'local'#10);
  AssertTrue(FRepo.Error, FRepo.Reset(First, rmMixed));
  AssertEquals('local'#10, FileText(IncludeTrailingPathDelimiter(FDir) + 'a.txt'));
  AssertTrue(FileExists(IncludeTrailingPathDelimiter(FDir) + 'b.txt'));
  AssertTrue(FRepo.Error, FRepo.Reset(First, rmHard));
  { The mixed reset left b.txt untracked, and a hard one keeps those. }
  AssertEquals('?? b.txt'#0, Git(['status', '--porcelain', '-z']));
  AssertEquals('one'#10'two'#10'three'#10, FileText(IncludeTrailingPathDelimiter(FDir) + 'a.txt'));

  AssertFalse('the switch would overwrite b.txt', FRepo.CreateBranch('new', Side, True));
  AssertFalse('nor is the branch made', FRepo.HasCommit('refs/heads/new'));
  DeleteFile(IncludeTrailingPathDelimiter(FDir) + 'b.txt');
  AssertTrue(FRepo.Error, FRepo.CreateBranch('new', Side, True));
  AssertEquals('new', FRepo.Branch);
  AssertEquals(Side, Trim(Git(['rev-parse', 'HEAD'])));
end;

{ A cherry-pick or merge that stops with conflicts says so, and leaves
  git in the middle of it. }
procedure TGitRepoTest.TestCommitActionConflicts;
var
  Conflicts: boolean;
begin
  MakeDiverged(Self);
  AssertTrue(FRepo.Open(FDir));
  AssertFalse(FRepo.CherryPick('topic', Conflicts));
  AssertTrue(FRepo.Error, Conflicts);
  AssertTrue(FRepo.Error <> '');
  AssertEquals('cherry-picking', FRepo.Operation);
  AssertTrue(FRepo.AbortOperation);
  AssertFalse(FRepo.MergeRef('topic', Conflicts));
  AssertTrue(Conflicts);
  AssertEquals('merging', FRepo.Operation);
  AssertTrue(FRepo.AbortOperation);
  AssertFalse('no such commit', FRepo.CherryPick('nothing', Conflicts));
  AssertFalse(Conflicts);
end;

procedure TGitRepoTest.TestBranchManagement;
var
  Remote, Main, R, B: string;
  Code: integer;
  NotMerged, Rejected: boolean;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  Main := FRepo.Branch;
  Remote := FDir + '-remote';
  RunCommandIndir(FDir, 'git', ['init', '-q', '--bare', Remote], R, Code,
    [poStderrToOutPut]);
  try
    Git(['remote', 'add', 'origin', Remote]);
    { A remote's name may have a slash of its own. }
    Git(['remote', 'add', 'team/fork', Remote]);
    AssertTrue(FRepo.SplitRemoteRef('origin/feature/x', R, B));
    AssertEquals('origin', R);
    AssertEquals('feature/x', B);
    AssertTrue(FRepo.SplitRemoteRef('team/fork/y', R, B));
    AssertEquals('team/fork', R);
    AssertEquals('y', B);
    AssertFalse(FRepo.SplitRemoteRef('nowhere/z', R, B));
    Git(['remote', 'remove', 'team/fork']);

    AssertTrue(FRepo.CreateBranch('work', 'HEAD', True));
    AssertTrue(FRepo.Push(Rejected));
    AssertEquals('origin/work', FRepo.Upstream('work'));
    AssertEquals('', FRepo.Upstream(Main));
    AssertTrue(FRepo.Error, FRepo.RenameBranch('work', 'job'));
    AssertEquals('job', FRepo.Branch);
    AssertEquals('the upstream goes along', 'origin/work', FRepo.Upstream('job'));
    AssertFalse(FRepo.RenameBranch('job', 'bad..name'));

    WriteFile('a.txt', 'only on job'#10);
    Commit('only on job');
    Git(['checkout', '-q', Main]);
    AssertFalse(FRepo.DeleteBranch('job', False, NotMerged));
    AssertTrue(FRepo.Error, NotMerged);
    AssertTrue(FRepo.Error, FRepo.DeleteBranch('job', True, NotMerged));
    AssertFalse(FRepo.HasCommit('refs/heads/job'));
    AssertFalse('the current one', FRepo.DeleteBranch(Main, True, NotMerged));
    AssertFalse(NotMerged);

    AssertTrue(FRepo.HasCommit('refs/remotes/origin/work'));
    { A tag of the same name on the remote makes the bare name
      ambiguous. }
    Git(['tag', 'work']);
    Git(['push', '-q', 'origin', 'refs/tags/work']);
    AssertTrue(FRepo.Error, FRepo.DeleteRemoteBranch('origin/work'));
    AssertFalse(FRepo.HasCommit('refs/remotes/origin/work'));
    RunCommandIndir(Remote, 'git', ['rev-parse', '--verify', '-q', 'refs/heads/work'], R,
      Code, []);
    AssertTrue('gone from the remote', Code <> 0);
    AssertFalse(FRepo.DeleteRemoteBranch('nowhere/work'));
  finally
    RemoveTree(Remote);
  end;
end;

{ A switch the local changes block names the files; a stash clears the
  way, and --merge brings them along. }
procedure TGitRepoTest.TestSwitchBlocked;
var
  Main: string;
  Files: TStringList;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  Main := FRepo.Branch;
  Git(['checkout', '-q', '-b', 'other']);
  WriteFile('a.txt', 'one'#10'two'#10'three'#10'four'#10);
  Commit('four');
  Git(['checkout', '-q', Main]);
  WriteFile('a.txt', 'zero'#10'one'#10'two'#10'three'#10);
  WriteFile('new.txt', 'untracked'#10);
  Files := TStringList.Create;
  try
    AssertFalse(FRepo.Switch('other'));
    AssertTrue(FRepo.Error, SwitchBlockedFiles(FRepo.Error, Files));
    AssertEquals('a.txt', Files.Text.Trim);
    AssertFalse(SwitchBlockedFiles('fatal: invalid reference: x', Files));

    AssertTrue(FRepo.Error, FRepo.Switch('other', True));
    AssertEquals('other', FRepo.Branch);
    AssertEquals('both changes', 'zero'#10'one'#10'two'#10'three'#10'four'#10,
      FileText(IncludeTrailingPathDelimiter(FDir) + 'a.txt'));

    Git(['checkout', '-q', '-f', Main]);
    WriteFile('a.txt', 'local'#10);
    AssertTrue(FRepo.Error, FRepo.Stash('before switching'));
    AssertEquals('', Git(['status', '--porcelain']));
    AssertTrue(Pos('before switching', Git(['stash', 'list'])) > 0);
    AssertTrue(FRepo.Switch('other'));
  finally
    Files.Free;
  end;
end;

{ Modified, staged, deleted, added, untracked and renamed files go back
  to HEAD; what was on disk comes back with RestoreReverted. }
procedure TGitRepoTest.TestRevertFiles;
var
  Paths, Saved: TStringList;
  Root: string;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  Root := IncludeTrailingPathDelimiter(FDir);
  WriteFile('a.txt', 'changed'#10);
  WriteFile('staged.txt', 'staged'#10);
  Git(['add', 'staged.txt']);
  DeleteFile(Root + 'del.txt');
  WriteFile('added.txt', 'added'#10);
  Git(['add', 'added.txt']);
  WriteFile('un=tracked.txt', 'untracked'#10);
  Git(['mv', QuoteName, 'moved.txt']);
  WriteFile('dir sp/fil å.txt', 'kept'#10);
  Paths := TStringList.Create;
  Saved := TStringList.Create;
  try
    Paths.Add('a.txt');
    Paths.Add('staged.txt');
    Paths.Add('del.txt');
    Paths.Add('added.txt');
    Paths.Add('un=tracked.txt');
    Paths.Add('moved.txt');
    AssertTrue(FRepo.Error, FRepo.RevertFiles(Paths, Saved));
    AssertEquals('the old path of the rename too', 7, Saved.Count);
    AssertEquals('one'#10'two'#10'three'#10, FileText(Root + 'a.txt'));
    AssertEquals('old'#10, FileText(Root + 'staged.txt'));
    AssertEquals('gone'#10, FileText(Root + 'del.txt'));
    AssertFalse(FileExists(Root + 'added.txt'));
    AssertFalse(FileExists(Root + 'un=tracked.txt'));
    AssertFalse(FileExists(Root + 'moved.txt'));
    AssertEquals('x'#10, FileText(Root + QuoteName));
    AssertEquals('not chosen', 'M "dir sp/fil \303\245.txt"', Trim(Git(['-c',
      'core.quotepath=true', 'status', '--porcelain'])));

    AssertTrue(FRepo.Error, FRepo.RestoreReverted(Saved));
    AssertEquals('changed'#10, FileText(Root + 'a.txt'));
    AssertEquals('staged'#10, FileText(Root + 'staged.txt'));
    AssertFalse('it was deleted', FileExists(Root + 'del.txt'));
    AssertEquals('added'#10, FileText(Root + 'added.txt'));
    AssertEquals('untracked'#10, FileText(Root + 'un=tracked.txt'));
    AssertEquals('x'#10, FileText(Root + 'moved.txt'));
  finally
    Paths.Free;
    Saved.Free;
  end;
end;

procedure TGitRepoTest.TestBranchesAndSwitch;
var
  Branch: string;
  Local, Remote: TStringList;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  Branch := Trim(Git(['rev-parse', '--abbrev-ref', 'HEAD']));
  Git(['branch', 'topic']);
  Local := TStringList.Create;
  Remote := TStringList.Create;
  try
    AssertTrue(FRepo.Branches(Local, Remote));
    AssertEquals(2, Local.Count);
    AssertTrue(Local.IndexOf(Branch) >= 0);
    AssertTrue(Local.IndexOf('topic') >= 0);
    AssertEquals(0, Remote.Count);
  finally
    Local.Free;
    Remote.Free;
  end;
  AssertTrue(FRepo.Switch('topic'));
  AssertEquals('topic', FRepo.Branch);
  AssertFalse(FRepo.Switch('nothing'));
  AssertTrue(FRepo.Error <> '');
  AssertEquals('topic', FRepo.Branch);
  WriteFile('a.txt', 'topic'#10);
  Commit('topic');
  AssertTrue(FRepo.Switch(Branch));
  AssertEquals(Branch, FRepo.Branch);
  WriteFile('a.txt', 'local'#10);
  AssertFalse('a local change the switch would overwrite', FRepo.Switch('topic'));
  AssertTrue(Pos('overwritten', FRepo.Error) > 0);
  AssertEquals(Branch, FRepo.Branch);
end;

{ A branch whose upstream ref is missing is gone; one tracking a ref
  that is there, or tracking nothing, is not. No remote is reached:
  the config and the remote-tracking ref are set by hand. }
procedure TGitRepoTest.TestGoneBranches;
var
  Gone: TStringList;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  Git(['branch', 'topic']);
  Git(['branch', 'kept']);
  Git(['branch', 'loose']);
  Git(['remote', 'add', 'origin', FDir + '-nowhere']);
  Git(['update-ref', 'refs/remotes/origin/kept', 'HEAD']);
  Git(['branch', '-q', '-u', 'origin/kept', 'kept']);
  Git(['config', 'branch.topic.remote', 'origin']);
  Git(['config', 'branch.topic.merge', 'refs/heads/topic']);
  Gone := TStringList.Create;
  try
    AssertTrue(FRepo.GoneBranches(Gone));
    AssertEquals(1, Gone.Count);
    AssertEquals('topic', Gone[0]);
  finally
    Gone.Free;
  end;
end;

{ The branch is deleted on the remote behind our back, as GitHub does
  after a merge: the remote-tracking ref stays, so only the remote
  knows. }
procedure TGitRepoTest.TestGoneUpstreams;
var
  Remote, Branch, Output: string;
  Code: integer;
  Gone: TStringList;

  function GoneText: string;
  begin
    GoneUpstreamsIn(FDir, Gone);
    Result := Trim(Gone.Text);
  end;

begin
  Gone := TStringList.Create;
  MakeHistory;
  Remote := FDir + '-remote';
  if RunCommandIndir(FDir, 'git', ['init', '-q', '--bare', Remote], Output, Code,
    [poStderrToOutPut]) <> 0 then
    Fail('could not make a bare repository');
  try
    Branch := Trim(Git(['rev-parse', '--abbrev-ref', 'HEAD']));
    AssertEquals('no upstream', '', GoneText);
    Git(['remote', 'add', 'origin', Remote]);
    Git(['push', '-q', '-u', 'origin', Branch]);
    Git(['branch', 'topic']);
    Git(['push', '-q', '-u', 'origin', 'topic']);
    Git(['branch', 'loose']);
    AssertEquals('still there', '', GoneText);
    if RunCommandIndir(Remote, 'git', ['update-ref', '-d', 'refs/heads/' + Branch],
      Output, Code, [poStderrToOutPut]) <> 0 then
      Fail('could not delete the branch on the remote');
    AssertTrue(Trim(Git(['rev-parse', 'origin/' + Branch])) <> '');
    AssertEquals('deleted on the remote', Branch, GoneText);
  finally
    RemoveTree(Remote);
  end;
  try
    AssertEquals('remote unreachable', '', GoneText);
  finally
    Gone.Free;
  end;
end;

{ A stash of everything, of some files, listed with its branch, message
  and untracked files, applied, dropped, popped and made into a branch. }
procedure TGitRepoTest.TestStashes;
var
  List: TGittanStashes;
  Paths: TStringList;
  Branch, Msg: string;
  Conflicts: boolean;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  AssertTrue(FRepo.Stashes(List));
  AssertEquals(0, Length(List));

  ParseStashSubject('On main: my work', Branch, Msg);
  AssertEquals('main', Branch);
  AssertEquals('my work', Msg);
  ParseStashSubject('WIP on feature/x: 1234abc files', Branch, Msg);
  AssertEquals('feature/x', Branch);
  AssertEquals('1234abc files', Msg);
  ParseStashSubject('On (no branch): loose', Branch, Msg);
  AssertEquals('', Branch);
  AssertEquals('loose', Msg);
  ParseStashSubject('odd', Branch, Msg);
  AssertEquals('', Branch);
  AssertEquals('odd', Msg);

  { Nothing to stash is no failure, and makes no stash. }
  AssertTrue(FRepo.Error, FRepo.Stash('nothing'));
  AssertTrue(FRepo.Stashes(List));
  AssertEquals(0, Length(List));

  WriteFile('a.txt', 'one'#10'two'#10'three'#10'four'#10);
  WriteFile('new.txt', 'untracked'#10);
  AssertTrue(FRepo.Error, FRepo.Stash('all of it'));
  AssertEquals('', Git(['status', '--porcelain']));
  AssertTrue(FRepo.Stashes(List));
  AssertEquals(1, Length(List));
  AssertEquals(0, List[0].Index);
  AssertEquals(FRepo.Branch, List[0].Branch);
  AssertEquals('all of it', List[0].Message);
  AssertTrue('holds new.txt', List[0].Untracked);
  AssertTrue(List[0].Time > 0);
  AssertEquals(0, FRepo.StashIndex(List[0].Id));
  AssertEquals(-1, FRepo.StashIndex('0000000000000000000000000000000000000000'));
  AssertTrue('made on HEAD', FRepo.CommitId(List[0].Id + '^') = FRepo.CommitId('HEAD'));
  { The range of a stash with untracked files runs to a commit that
    holds them too. }
  AssertTrue(FRepo.StashRange(List[0].Id, Branch));
  AssertTrue(Branch, Pos(List[0].Id + '^..', Branch) = 1);
  AssertTrue('another commit', Branch <> List[0].Id + '^..' + List[0].Id);
  AssertEquals('a.txt'#10'new.txt'#10, Git(['diff', '--name-only', Branch]));
  { Gittan's own commits need no identity of the user's: with a name
    git refuses, the range still gets the commit with the untracked
    files, and a snapshot is made. }
  Git(['config', 'user.name', '<>']);
  AssertTrue(FRepo.StashRange(List[0].Id, Msg));
  AssertTrue('the commit with the untracked files', Msg <> List[0].Id + '^..' + List[0].Id);
  AssertTrue(FRepo.Error, FRepo.TakeSnapshot(Msg));
  Git(['config', '--unset', 'user.name']);
  AssertEquals('what the stash holds', 'untracked'#10, Git(['show',
    Copy(Branch, Pos('..', Branch) + 2, MaxInt) + ':new.txt']));
  AssertFalse(FRepo.StashRange('0000000000000000000000000000000000000000', Branch));

  { Some files only: the others stay as they are. }
  WriteFile('a.txt', 'one'#10'two'#10'three'#10'five'#10);
  WriteFile('del.txt', 'changed too'#10);
  Paths := TStringList.Create;
  try
    Paths.Add('a.txt');
    AssertTrue(FRepo.Error, FRepo.Stash('', Paths));
  finally
    Paths.Free;
  end;
  AssertEquals(' M del.txt', TrimRight(Git(['status', '--porcelain'])));
  AssertTrue(FRepo.Stashes(List));
  AssertEquals(2, Length(List));
  AssertEquals('the newest first', 'all of it', List[1].Message);
  AssertEquals(1, List[1].Index);
  AssertTrue('named after HEAD', Pos('files', List[0].Message) > 0);
  AssertFalse('nothing untracked', List[0].Untracked);
  AssertTrue(FRepo.StashRange(List[0].Id, Branch));
  AssertEquals('the plain range', List[0].Id + '^..' + List[0].Id, Branch);
  AssertEquals(1, FRepo.StashIndex(List[1].Id));

  { Apply keeps the stash, drop takes it away. }
  AssertTrue(FRepo.Error, FRepo.StashApply(List[0].Id, False, Conflicts));
  AssertEquals('one'#10'two'#10'three'#10'five'#10,
    FileText(IncludeTrailingPathDelimiter(FDir) + 'a.txt'));
  AssertEquals(2, Length(List));
  AssertEquals(0, FRepo.StashIndex(List[0].Id));
  AssertTrue(FRepo.Error, FRepo.StashDrop(List[0].Id));
  AssertEquals(-1, FRepo.StashIndex(List[0].Id));
  AssertEquals(0, FRepo.StashIndex(List[1].Id));
  AssertFalse(FRepo.StashDrop(List[0].Id));
  AssertFalse(FRepo.StashApply(List[0].Id, True, Conflicts));
  AssertFalse(Conflicts);

  { Pop puts the untracked file back too and drops the stash. }
  Git(['checkout', '-q', '--', '.']);
  Git(['clean', '-q', '-f']);
  AssertTrue(FRepo.Error, FRepo.StashApply(List[1].Id, True, Conflicts));
  AssertEquals('one'#10'two'#10'three'#10'four'#10,
    FileText(IncludeTrailingPathDelimiter(FDir) + 'a.txt'));
  AssertEquals('untracked'#10, FileText(IncludeTrailingPathDelimiter(FDir) + 'new.txt'));
  AssertTrue(FRepo.Stashes(List));
  AssertEquals(0, Length(List));

  { A branch from a stash starts where the stash was made, with its
    changes, and the stash goes. }
  AssertTrue(FRepo.Error, FRepo.Stash('for a branch'));
  AssertTrue(FRepo.Stashes(List));
  AssertEquals(1, Length(List));
  AssertFalse(FRepo.StashBranch('bad..name', List[0].Id));
  AssertTrue(FRepo.Error, FRepo.StashBranch('from-stash', List[0].Id));
  AssertEquals('from-stash', FRepo.Branch);
  AssertEquals('one'#10'two'#10'three'#10'four'#10,
    FileText(IncludeTrailingPathDelimiter(FDir) + 'a.txt'));
  AssertTrue(FRepo.Stashes(List));
  AssertEquals(0, Length(List));
end;

{ A stash whose changes clash with the work tree leaves the file in
  conflict and keeps the stash. }
procedure TGitRepoTest.TestStashConflicts;
var
  List: TGittanStashes;
  Conflicts: boolean;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  WriteFile('a.txt', 'one'#10'two'#10'stashed'#10);
  AssertTrue(FRepo.Error, FRepo.Stash('clash'));
  WriteFile('a.txt', 'one'#10'two'#10'committed'#10);
  Commit('committed');
  AssertTrue(FRepo.Stashes(List));
  AssertEquals(1, Length(List));
  AssertFalse(FRepo.StashApply(List[0].Id, True, Conflicts));
  AssertTrue(FRepo.Error, Conflicts);
  AssertTrue('left in conflict', Pos('UU a.txt', Git(['status', '--porcelain'])) > 0);
  AssertEquals('the stash is kept', 0, FRepo.StashIndex(List[0].Id));
  AssertEquals('', FRepo.Operation);
  Git(['checkout', '-q', 'HEAD', '--', 'a.txt']);
  AssertTrue(FRepo.Error, FRepo.StashDrop(List[0].Id));
end;

{ A rebase rewrites a pushed commit: a plain push is rejected, the
  forced one goes through while the remote is where the last fetch saw
  it, and is refused as stale once someone else pushed. }
procedure TGitRepoTest.TestForcePush;
var
  Remote, Other, Output: string;
  Code, Ahead, Behind: integer;
  Rejected, Stale, Unseen: boolean;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  AssertFalse('no upstream', FRepo.ForcePush(Stale, Unseen));
  AssertFalse(Stale);
  AssertFalse(Unseen);
  Remote := FDir + '-remote';
  Other := FDir + '-other';
  RunCommandIndir(FDir, 'git', ['init', '-q', '--bare', Remote], Output, Code,
    [poStderrToOutPut]);
  try
    Git(['remote', 'add', 'origin', Remote]);
    WriteFile('a.txt', 'pushed'#10);
    Commit('to rewrite');
    AssertTrue(FRepo.Error, FRepo.Push(Rejected));
    Git(['commit', '-q', '--amend', '-m', 'rewritten']);
    AssertTrue(FRepo.AheadBehind(Ahead, Behind));
    AssertEquals(1, Ahead);
    AssertEquals(1, Behind);
    AssertFalse(FRepo.Push(Rejected));
    AssertTrue(Rejected);
    AssertTrue(FRepo.Error, FRepo.ForcePush(Stale, Unseen));
    AssertTrue(FRepo.AheadBehind(Ahead, Behind));
    AssertEquals(0, Ahead);
    AssertEquals(0, Behind);
    AssertEquals('rewritten', Trim(Git(['log', '-1', '--format=%s', 'origin/' +
      FRepo.Branch])));

    PushFromOther(Remote, Other, 'other.txt');
    Git(['commit', '-q', '--amend', '-m', 'again']);
    AssertFalse('the remote moved', FRepo.ForcePush(Stale, Unseen));
    AssertTrue(FRepo.Error, Stale);
    AssertFalse(Unseen);

    { Fetched, so the lease holds, but never taken into the branch. }
    AssertTrue(FRepo.Error, FRepo.Fetch);
    AssertFalse('fetched, not taken in', FRepo.ForcePush(Stale, Unseen));
    AssertFalse(Stale);
    AssertTrue(FRepo.Error, Unseen);
    AssertTrue(FRepo.Error, FRepo.Pull(pmRebase, Rejected));
    AssertTrue('taken in', FRepo.ForcePush(Stale, Unseen));
  finally
    RemoveTree(Remote);
    RemoveTree(Other);
  end;
end;

procedure TGitRepoTest.TestParseGitVersion;
var
  Version: string;
  Major, Minor: integer;
begin
  AssertTrue(ParseGitVersion('git version 2.39.5 (Apple Git-154)'#10, Version, Major, Minor));
  AssertEquals('2.39.5', Version);
  AssertEquals(2, Major);
  AssertEquals(39, Minor);
  AssertTrue(ParseGitVersion('git version 2.30.1.windows.1', Version, Major, Minor));
  AssertEquals('2.30.1', Version);
  AssertEquals(30, Minor);
  AssertTrue(ParseGitVersion('git version 3.0', Version, Major, Minor));
  AssertEquals(3, Major);
  AssertFalse(ParseGitVersion('hub version 2.14', Version, Major, Minor));
  AssertFalse(ParseGitVersion('git version abc', Version, Major, Minor));
  AssertTrue(GitVersionSupported(2, 30));
  AssertTrue(GitVersionSupported(2, 54));
  AssertTrue(GitVersionSupported(3, 0));
  AssertFalse(GitVersionSupported(2, 29));
  AssertFalse(GitVersionSupported(1, 99));
  AssertTrue('the git the tests run', GitVersion(Version, Major, Minor));
  AssertTrue(Version, GitVersionSupported(Major, Minor));
end;

procedure TGitRepoTest.TestGitNotRun;
var
  Output, Err, Missing: string;
begin
  AssertEquals('git was not found. Install git, or set the path of one under Tools in ' +
    'the settings.', GitNotRunMessage('git'));
  AssertTrue(Pos('Could not run git at /x/git.', GitNotRunMessage('/x/git')) = 1);
  AssertTrue(IsMissingDeveloperTools('xcode-select: note: No developer tools were found, ' +
    'requesting install.'));
  AssertTrue(IsMissingDeveloperTools('xcrun: error: invalid active developer path ' +
    '(/Library/Developer/CommandLineTools), missing xcrun at: ' +
    '/Library/Developer/CommandLineTools/usr/bin/xcrun'));
  AssertFalse(IsMissingDeveloperTools('fatal: not a git repository'));
  Missing := IncludeTrailingPathDelimiter(FDir) + 'no-such-git';
  SetGitExe(Missing);
  try
    AssertFalse(RunGitIn(FDir, ['--version'], Output, Err));
    AssertEquals(GitNotRunMessage(Missing), Err);
    AssertFalse(FRepo.Open(FDir));
    AssertEquals(GitNotRunMessage(Missing), FRepo.Error);
  finally
    SetGitExe('');
  end;
  AssertTrue('git again', RunGitIn(FDir, ['--version'], Output, Err));
end;

procedure TGitRepoTest.TestUpstream;
var
  Remote, Output, Main: string;
  Code: integer;
  List: TStringList;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  Main := FRepo.Branch;
  Remote := FDir + '-remote';
  RunCommandIndir(FDir, 'git', ['init', '-q', '--bare', Remote], Output, Code,
    [poStderrToOutPut]);
  List := TStringList.Create;
  try
    AssertTrue(FRepo.Remotes(List));
    AssertEquals(0, List.Count);
    AssertEquals('', FRepo.PushRemote);
    Git(['remote', 'add', 'upstream', Remote]);
    Git(['remote', 'add', 'origin', Remote]);
    AssertTrue(FRepo.Remotes(List));
    AssertEquals('origin|upstream|', Joined(List));
    AssertEquals('origin', FRepo.PushRemote);

    Git(['branch', 'topic']);
    AssertTrue(FRepo.Error, FRepo.PushBranch('topic', 'upstream'));
    AssertEquals('upstream/topic', FRepo.Upstream('topic'));
    AssertEquals('', FRepo.Upstream(Main));
    AssertTrue(FRepo.Error, FRepo.SetUpstream(Main, 'upstream/topic'));
    AssertEquals('upstream/topic', FRepo.Upstream(Main));
    AssertEquals('the current branch''s remote', 'upstream', FRepo.PushRemote);
    AssertTrue(FRepo.Error, FRepo.SetUpstream(Main, ''));
    AssertEquals('', FRepo.Upstream(Main));
    AssertFalse('no such branch', FRepo.SetUpstream(Main, 'origin/nothing'));
  finally
    List.Free;
    RemoveTree(Remote);
  end;
end;

procedure TGitRepoTest.TestParseTags;
var
  Tags: TGittanTags;
begin
  Tags := ParseTags('v2'#31'aaa'#31'ccc'#31'1700000000'#31'Release: 2'#10 +
    'v1'#31'bbb'#31#31'1600000000'#31'commit subject'#10'broken'#31'x'#10);
  AssertEquals(2, Length(Tags));
  AssertEquals('v2', Tags[0].Name);
  AssertTrue(Tags[0].Annotated);
  AssertEquals('an annotated tag names the commit', 'ccc', Tags[0].Commit);
  AssertEquals(1700000000, Tags[0].Time);
  AssertEquals('Release: 2', Tags[0].Subject);
  AssertFalse(Tags[1].Annotated);
  AssertEquals('bbb', Tags[1].Commit);
  AssertEquals('commit subject', Tags[1].Subject);
end;

procedure TGitRepoTest.TestTags;
var
  Remote, Output, Head, First: string;
  Code: integer;
  Tags: TGittanTags;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  First := FRepo.CommitId('HEAD');
  AssertTrue(FRepo.CreateTag('v1', 'HEAD', ''));
  WriteFile('a.txt', 'later'#10);
  Commit('later');
  Head := FRepo.CommitId('HEAD');
  AssertTrue(FRepo.CreateTag('v2', 'HEAD', 'Second release'));
  AssertTrue(FRepo.Tags(Tags));
  AssertEquals(2, Length(Tags));
  { Newest first, and the highest version first when both were made in
    the same second. }
  AssertEquals('v2', Tags[0].Name);
  AssertEquals(Head, Tags[0].Commit);
  AssertTrue(Tags[0].Annotated);
  AssertEquals('Second release', Tags[0].Subject);
  AssertEquals(First, Tags[1].Commit);
  AssertEquals('files', Tags[1].Subject);

  AssertTrue(FRepo.Error, FRepo.Switch('v1', False, True));
  AssertEquals(First, FRepo.CommitId('HEAD'));
  AssertEquals('', Trim(Git(['branch', '--show-current'])));
  AssertFalse('a tag is no branch', FRepo.Switch('v2'));

  Remote := FDir + '-remote';
  RunCommandIndir(FDir, 'git', ['init', '-q', '--bare', Remote], Output, Code,
    [poStderrToOutPut]);
  try
    Git(['remote', 'add', 'origin', Remote]);
    AssertTrue(FRepo.Error, FRepo.PushTag('origin', 'v1'));
    RunCommandIndir(Remote, 'git', ['tag'], Output, Code, [poStderrToOutPut]);
    AssertEquals('v1', Trim(Output));
    AssertTrue(FRepo.Error, FRepo.PushTag('origin', ''));
    RunCommandIndir(Remote, 'git', ['tag'], Output, Code, [poStderrToOutPut]);
    AssertEquals('v1'#10'v2', Trim(AdjustLineBreaks(Output, tlbsLF)));
    AssertTrue(FRepo.Error, FRepo.DeleteRemoteTag('origin', 'v2'));
    RunCommandIndir(Remote, 'git', ['tag'], Output, Code, [poStderrToOutPut]);
    AssertEquals('v1', Trim(Output));
    AssertTrue(FRepo.Error, FRepo.DeleteTag('v2'));
    AssertTrue(FRepo.Tags(Tags));
    AssertEquals(1, Length(Tags));
    AssertFalse(FRepo.DeleteTag('v2'));
  finally
    RemoveTree(Remote);
  end;
end;

procedure TGitRepoTest.TestParseReflog;
var
  Log: TGittanReflog;
begin
  Log := ParseReflog('aaa'#31'HEAD@{1700000000}'#31'reset: moving to HEAD~1'#10 +
    'bbb'#31'HEAD@{1600000000}'#31'commit: a: b'#10'broken'#31'x'#10);
  AssertEquals(2, Length(Log));
  AssertEquals('aaa', Log[0].Commit);
  AssertEquals(1700000000, Log[0].Time);
  AssertEquals('reset: moving to HEAD~1', Log[0].Subject);
  AssertEquals('commit: a: b', Log[1].Subject);
  AssertFalse(Log[1].Lost);
end;

procedure TGitRepoTest.TestReflog;
var
  Log: TGittanReflog;
  First, Second: string;
begin
  Git(['init', '-q']);
  AssertTrue(FRepo.Open(FDir));
  AssertTrue('an unborn HEAD has an empty reflog', FRepo.Reflog(Log));
  AssertEquals(0, Length(Log));
  MakeHistory;
  First := FRepo.CommitId('HEAD');
  WriteFile('a.txt', 'later'#10);
  Commit('later');
  Second := FRepo.CommitId('HEAD');
  AssertTrue(FRepo.Error, FRepo.Reset(First, rmHard));
  AssertTrue(FRepo.Error, FRepo.Reflog(Log));
  AssertEquals(3, Length(Log));
  AssertEquals(First, Log[0].Commit);
  AssertEquals('reset: moving to ' + First, Log[0].Subject);
  AssertTrue(Log[0].Time > 0);
  AssertFalse(Log[0].Lost);
  AssertEquals(Second, Log[1].Commit);
  AssertEquals('commit: later', Log[1].Subject);
  AssertTrue('only the reflog keeps it', Log[1].Lost);
  AssertFalse(Log[2].Lost);
  AssertTrue(FRepo.Reflog(Log, 1));
  AssertEquals(1, Length(Log));

  AssertTrue(FRepo.Error, FRepo.CreateBranch('saved', Second, False));
  AssertTrue(FRepo.Reflog(Log));
  AssertFalse('a branch keeps it now', Log[1].Lost);
end;

{ More commits only in the reflog than one command line takes on
  Windows (about 41 characters an id, 32767 at most): every one is
  still marked lost. The commits are written as files and stored by
  one hash-object, with no pipe to git's input; the reflog is written
  as git writes it, newest last. }
procedure TGitRepoTest.TestReflogMany;
const
  Count = 950;
var
  Args: array of string;
  Tree, Line, Prev: string;
  Ids: TStringList;
  Log: TGittanReflog;
  F: TextFile;
  i, Lost: integer;
begin
  MakeHistory;
  Tree := Trim(Git(['rev-parse', 'HEAD^{tree}']));
  SetLength(Args, Count + 4);
  Args[0] := 'hash-object';
  Args[1] := '-w';
  Args[2] := '-t';
  Args[3] := 'commit';
  for i := 1 to Count do
  begin
    WriteFile('c/' + IntToStr(i), 'tree ' + Tree + #10 +
      'author Gittan Test <test@example.invalid> 1700000000 +0000'#10 +
      'committer Gittan Test <test@example.invalid> 1700000000 +0000'#10#10 +
      IntToStr(i) + #10);
    Args[3 + i] := 'c/' + IntToStr(i);
  end;
  Ids := TStringList.Create;
  try
    Ids.Text := Git(Args);
    AssertEquals(Count, Ids.Count);
    Prev := Trim(Git(['rev-parse', 'HEAD']));
    AssignFile(F, IncludeTrailingPathDelimiter(FDir) + SetDirSeparators('.git/logs/HEAD'));
    Append(F);
    try
      for i := 0 to Ids.Count - 1 do
      begin
        Line := Prev + ' ' + Ids[i] + ' Gittan Test <test@example.invalid> 1700000000 +0000'#9 +
          'commit: ' + IntToStr(i + 1);
        Write(F, Line, #10);
        Prev := Ids[i];
      end;
    finally
      CloseFile(F);
    end;
  finally
    Ids.Free;
  end;
  AssertTrue(FRepo.Open(FDir));
  AssertTrue(FRepo.Error, FRepo.Reflog(Log, 1000));
  AssertEquals(Count + 1, Length(Log));
  Lost := 0;
  for i := 0 to High(Log) do
    if Log[i].Lost then
      Inc(Lost);
  AssertEquals('every commit only the reflog keeps', Count, Lost);
  AssertFalse('HEAD''s commit is on a branch', Log[High(Log)].Lost);
end;

procedure TGitRepoTest.TestMoveAndRemove;
var
  Stats: TGittanFileStats;
  Paths: TStringList;
  Id: string;
  i, n: integer;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  AssertTrue(FRepo.IsTracked('a.txt'));
  AssertTrue(FRepo.IsTracked('dir sp/fil å.txt'));
  AssertFalse('a folder is no file', FRepo.IsTracked('dir sp'));
  WriteFile('new.txt', 'n'#10);
  AssertFalse(FRepo.IsTracked('new.txt'));

  { Into a folder that is not there yet; git shows it as a rename. }
  AssertTrue(FRepo.Error, FRepo.MovePath('a.txt', 'moved/b.txt'));
  AssertFalse(FileExists(FDir + PathDelim + 'a.txt'));
  AssertTrue(FileExists(FDir + PathDelim + 'moved' + PathDelim + 'b.txt'));
  AssertTrue(FRepo.ChangeStats(Stats));
  AssertTrue(FindStat(Stats, 'moved/b.txt').Kind = ckRenamed);
  AssertFalse('untracked', FRepo.MovePath('new.txt', 'other.txt'));
  AssertFalse('the target exists', FRepo.MovePath(QuoteName, 'new.txt'));

  Paths := TStringList.Create;
  try
    { Kept on disk, untracked from now on. }
    Paths.Add(QuoteName);
    AssertTrue(FRepo.Error, FRepo.RemovePaths(Paths, True));
    AssertTrue(FileExists(FDir + PathDelim + QuoteName));
    AssertFalse(FRepo.IsTracked(QuoteName));
    AssertEquals('D  ' + QuoteName + #0'?? ' + QuoteName + #0,
      Git(['status', '--porcelain', '-z', '--', QuoteName]));
    { Listed once, as the deletion to commit. }
    AssertTrue(FRepo.ChangeStats(Stats));
    AssertTrue(FindStat(Stats, QuoteName).Kind = ckDeleted);
    n := 0;
    for i := 0 to High(Stats) do
      if Stats[i].Path = QuoteName then
        Inc(n);
    AssertEquals(1, n);
    { The commit takes it out of HEAD and leaves it on disk, untracked. }
    AssertTrue(FRepo.Error, FRepo.Commit('untrack', Paths, False, Id));
    AssertEquals('?? ' + QuoteName + #0, Git(['status', '--porcelain', '-z', '--',
      QuoteName]));
    AssertTrue('the rename stays out', Pos('R  a.txt -> moved/b.txt', Git(['status', '--porcelain'])) > 0);
    AssertEquals('', Git(['ls-tree', '--name-only', 'HEAD', '--', QuoteName]));

    Paths[0] := 'del.txt';
    AssertTrue(FRepo.Error, FRepo.RemovePaths(Paths, False));
    AssertFalse(FileExists(FDir + PathDelim + 'del.txt'));
    AssertTrue(FRepo.ChangeStats(Stats));
    AssertTrue(FindStat(Stats, 'del.txt').Kind = ckDeleted);

    { git keeps a file with changes not committed from being deleted. }
    WriteFile('staged.txt', 'changed'#10);
    Paths[0] := 'staged.txt';
    AssertFalse(FRepo.RemovePaths(Paths, False));
    AssertTrue(FileExists(FDir + PathDelim + 'staged.txt'));
  finally
    Paths.Free;
  end;
end;

procedure TGitRepoTest.TestParseCleanPreview;
var
  Paths: TStringList;
begin
  Paths := TStringList.Create;
  try
    ParseCleanPreview('Would remove a.txt'#10'Would remove build/'#10 +
      'Would skip repository sub/'#10'Would remove "q\"uote \303\245\t.txt"'#10, Paths);
    AssertEquals('a.txt|build/|q"uote å'#9'.txt|', Joined(Paths));
  finally
    Paths.Free;
  end;
  AssertEquals('plain', UnquoteCPath('plain'));
  AssertEquals('a\b', UnquoteCPath('"a\\b"'));
end;

procedure TGitRepoTest.TestClean;
var
  Paths: TStringList;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  WriteFile('.gitignore', '*.log'#10'build/'#10);
  Git(['add', '.gitignore']);
  Commit('ignore');
  WriteFile('new.txt', 'n'#10);
  WriteFile('newdir/x.txt', 'x'#10);
  WriteFile(QuoteName + '.new', 'q'#10);
  WriteFile('run.log', 'l'#10);
  WriteFile('build/out.o', 'o'#10);
  Paths := TStringList.Create;
  try
    AssertTrue(FRepo.Error, FRepo.CleanPreview(cnUntracked, Paths));
    Paths.Sort;
    AssertEquals('new.txt|newdir/|' + QuoteName + '.new|', Joined(Paths));
    AssertTrue(FRepo.Error, FRepo.CleanPreview(cnIgnored, Paths));
    Paths.Sort;
    AssertEquals('build/|run.log|', Joined(Paths));
    AssertTrue(FRepo.Error, FRepo.CleanPreview(cnAll, Paths));
    AssertEquals(5, Paths.Count);

    { Only the paths chosen go, and an ignored file stays when the
      untracked ones are cleaned. }
    Paths.Clear;
    Paths.Add('newdir/');
    Paths.Add(QuoteName + '.new');
    Paths.Add('run.log');
    AssertTrue(FRepo.Error, FRepo.Clean(cnUntracked, Paths));
    AssertFalse(DirectoryExists(FDir + PathDelim + 'newdir'));
    AssertFalse(FileExists(FDir + PathDelim + QuoteName + '.new'));
    AssertTrue(FileExists(FDir + PathDelim + 'new.txt'));
    AssertTrue('not untracked, so not cleaned as one', FileExists(FDir + PathDelim + 'run.log'));

    Paths.Clear;
    Paths.Add('build/');
    AssertTrue(FRepo.Error, FRepo.Clean(cnIgnored, Paths));
    AssertFalse(DirectoryExists(FDir + PathDelim + 'build'));
    AssertTrue(FileExists(FDir + PathDelim + 'run.log'));
    AssertTrue(FRepo.Error, FRepo.CleanPreview(cnAll, Paths));
    Paths.Sort;
    AssertEquals('new.txt|run.log|', Joined(Paths));
  finally
    Paths.Free;
  end;
end;

procedure TGitRepoTest.TestParseTreeEntries;
var
  List: TGittanTreeEntries;
begin
  List := ParseTreeEntries('100644 blob aaa     12'#9'a.txt'#0 +
    '120000 blob bbb      5'#9'link'#0'040000 tree ccc       -'#9'src'#0 +
    '160000 commit ddd       -'#9'sub'#0'100755 blob eee   7'#9'z run.sh'#0 +
    'broken'#0, 'dir');
  AssertEquals(5, Length(List));
  AssertEquals('folders first', 'src', List[0].Name);
  AssertTrue(List[0].Kind = tkFolder);
  AssertEquals(-1, List[0].Size);
  AssertEquals('dir/src', List[0].Path);
  AssertEquals('a.txt', List[1].Name);
  AssertTrue(List[1].Kind = tkFile);
  AssertEquals(12, List[1].Size);
  AssertEquals('aaa', List[1].Id);
  AssertFalse(List[1].Executable);
  AssertTrue(List[2].Kind = tkLink);
  AssertTrue(List[3].Kind = tkSubmodule);
  AssertEquals('z run.sh', List[4].Name);
  AssertTrue(List[4].Executable);
  List := ParseTreeEntries('100644 blob aaa 1'#9'a'#0, '');
  AssertEquals('a', List[0].Path);
end;

procedure TGitRepoTest.TestTreeEntries;
var
  List: TGittanTreeEntries;
  First: string;
  Data: RawByteString;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  First := FRepo.CommitId('HEAD');
  WriteFile('dir sp/new.txt', 'later'#10);
  Git(['rm', '-q', 'del.txt']);
  Git(['add', '.']);
  Commit('later');
  AssertTrue(FRepo.Error, FRepo.TreeEntries(First, '', List));
  AssertEquals(5, Length(List));
  AssertEquals('dir sp', List[0].Name);
  AssertTrue(List[0].Kind = tkFolder);
  AssertEquals('a.txt', List[1].Name);
  AssertEquals(14, List[1].Size);
  AssertEquals('del.txt', List[2].Name);
  AssertTrue(FRepo.Error, FRepo.TreeEntries(First, 'dir sp', List));
  AssertEquals(1, Length(List));
  AssertEquals('dir sp/fil å.txt', List[0].Path);
  AssertTrue(FRepo.TreeEntries('HEAD', 'dir sp', List));
  AssertEquals(2, Length(List));
  AssertTrue(FRepo.FileBlob('del.txt', First, Data));
  AssertEquals('gone'#10, Data);
  AssertFalse('no such folder', FRepo.TreeEntries('HEAD', 'nope', List));
end;

procedure TGitRepoTest.TestCloneFolderName;
begin
  AssertEquals('gittan', CloneFolderName('https://github.com/bjorn/gittan.git'));
  AssertEquals('gittan', CloneFolderName('https://github.com/bjorn/gittan/'));
  AssertEquals('gittan', CloneFolderName('git@github.com:bjorn/gittan.git'));
  AssertEquals('b', CloneFolderName('ssh://git@host.example:2222/a/b.git'));
  AssertEquals('repo', CloneFolderName('/Users/bjorn/repo/.git'));
  AssertEquals('repo', CloneFolderName('C:\repos\repo'));
  AssertEquals('host.example', CloneFolderName('https://host.example:8080/'));
  AssertEquals('host.example', CloneFolderName('ssh://me@host.example'));
  AssertEquals('b', CloneFolderName('  ../b.bundle  '));
  AssertEquals('', CloneFolderName(''));
end;

procedure TGitRepoTest.TestLooksLikeCloneUrl;
begin
  AssertTrue(LooksLikeCloneUrl('https://github.com/a/b.git'));
  AssertTrue(LooksLikeCloneUrl(' git@github.com:a/b.git'#10));
  AssertTrue(LooksLikeCloneUrl('ssh://git@host:22/a/b'));
  AssertTrue(LooksLikeCloneUrl('file:///tmp/b'));
  AssertFalse('a sentence', LooksLikeCloneUrl('see https://github.com/a/b'));
  AssertFalse('two lines', LooksLikeCloneUrl('https://a/b'#10'https://c/d'));
  AssertFalse('a scheme alone', LooksLikeCloneUrl('https://'));
  AssertFalse('a mail address', LooksLikeCloneUrl('me@example.com'));
  AssertFalse('a path', LooksLikeCloneUrl('/Users/bjorn/b'));
  AssertFalse('empty', LooksLikeCloneUrl(''));
end;

procedure TGitRepoTest.TestCloneAndInit;
var
  Target, Err, Fresh: string;
begin
  MakeHistory;
  Target := FDir + '-clone';
  Fresh := FDir + '-new';
  try
    AssertTrue(Err, CloneRepository(FDir, Target, True, Err));
    AssertTrue(FileExists(Target + PathDelim + 'a.txt'));
    AssertTrue(FRepo.Open(Target));
    { The temporary folder may be reached through a link (/var on macOS). }
    AssertEquals(ExtractFileName(Target), ExtractFileName(ExcludeTrailingPathDelimiter(FRepo.Root)));
    AssertEquals('origin', FRepo.PushRemote);
    AssertFalse('the folder is not empty', CloneRepository(FDir, Target, False, Err));
    AssertTrue(Err <> '');
    AssertFalse('no parent', CloneRepository(FDir, Target + PathDelim + 'x' + PathDelim + 'y',
      False, Err));
    AssertFalse('no repository there', CloneRepository(FDir + '-nothing', Fresh, False, Err));
    AssertFalse('git removes what it made', DirectoryExists(Fresh));

    AssertFalse('no folder', InitRepository(Fresh, Err));
    ForceDirectories(Fresh);
    AssertTrue(Err, InitRepository(Fresh, Err));
    AssertTrue(FRepo.Open(Fresh));
    AssertEquals(ExtractFileName(Fresh), ExtractFileName(ExcludeTrailingPathDelimiter(FRepo.Root)));
  finally
    RemoveTree(Target);
    RemoveTree(Fresh);
  end;
end;

procedure TGitRepoTest.TestEditRemotes;
var
  R: TGittanRemotes;
  Err: string;
  Local, Remote: TStringList;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  AssertTrue(FRepo.Error, FRepo.AddRemote('origin', 'https://example.invalid/a.git'));
  AssertFalse('taken', FRepo.AddRemote('origin', 'https://example.invalid/b.git'));
  AssertTrue(FRepo.Error <> '');
  AssertFalse('no name', FRepo.AddRemote('bad name', 'https://example.invalid/b.git'));
  AssertTrue(ReadRemotes(FDir, R, Err));
  AssertEquals(1, Length(R));
  AssertEquals('https://example.invalid/a.git', R[0].Url);
  AssertEquals('https://example.invalid/a.git', R[0].PushUrl);

  AssertTrue(FRepo.Error, FRepo.SetRemoteUrls('origin', 'https://example.invalid/c.git',
    'git@example.invalid:c.git'));
  AssertTrue(ReadRemotes(FDir, R, Err));
  AssertEquals('https://example.invalid/c.git', R[0].Url);
  AssertEquals('git@example.invalid:c.git', R[0].PushUrl);
  AssertTrue(FRepo.Error, FRepo.SetRemoteUrls('origin', 'https://example.invalid/d.git', ''));
  AssertTrue(ReadRemotes(FDir, R, Err));
  AssertEquals('https://example.invalid/d.git', R[0].PushUrl);
  AssertTrue('without a push URL to unset', FRepo.SetRemoteUrls('origin',
    'https://example.invalid/d.git', 'https://example.invalid/d.git'));

  { A rename takes the remote-tracking branches and the upstream along. }
  Git(['update-ref', 'refs/remotes/origin/main', 'HEAD']);
  Git(['config', 'branch.' + FRepo.Branch + '.remote', 'origin']);
  Git(['config', 'branch.' + FRepo.Branch + '.merge', 'refs/heads/main']);
  AssertTrue(FRepo.Error, FRepo.RenameRemote('origin', 'upstream'));
  AssertEquals('upstream/main', FRepo.Upstream(FRepo.Branch));
  Local := TStringList.Create;
  Remote := TStringList.Create;
  try
    AssertTrue(FRepo.Branches(Local, Remote));
    AssertEquals('upstream/main|', Joined(Remote));
    AssertTrue(FRepo.Error, FRepo.RemoveRemote('upstream'));
    AssertTrue(FRepo.Branches(Local, Remote));
    AssertEquals(0, Remote.Count);
    AssertEquals('', FRepo.Upstream(FRepo.Branch));
    AssertFalse('gone', FRepo.RemoveRemote('upstream'));
  finally
    Local.Free;
    Remote.Free;
  end;
  AssertTrue(ReadRemotes(FDir, R, Err));
  AssertEquals(0, Length(R));
end;

procedure TGitRepoTest.TestParseBisectRefs;
var
  Bad: string;
  Good, Skipped: TStringArray;
begin
  ParseBisectRefs('b1 refs/bisect/bad'#10'g1 refs/bisect/good-g1'#10 +
    'g2 refs/bisect/good-g2'#10's1 refs/bisect/skip-s1'#10'odd'#10, Bad, Good, Skipped);
  AssertEquals('b1', Bad);
  AssertEquals(2, Length(Good));
  AssertEquals('g2', Good[1]);
  AssertEquals(1, Length(Skipped));
  AssertEquals('s1', Skipped[0]);
  ParseBisectRefs('', Bad, Good, Skipped);
  AssertEquals('', Bad);
  AssertEquals(0, Length(Good));
end;

{ Eight commits c1..c8, the bug in c5: bad from c5 on. }
procedure TGitRepoTest.TestBisect;
var
  Ids: array[1..8] of string;
  State: TGittanBisect;
  Graph: TGittanGraphCommits;
  i: integer;

  function HasRef(const ARefs: TGittanGraphRefs; const AName: string): boolean;
  var
    Ref: TGittanGraphRef;
  begin
    Result := False;
    for Ref in ARefs do
      if (Ref.Kind = grBisect) and (Ref.Name = AName) then
        Result := True;
  end;

  function Buggy: boolean;
  var
    Text: TStringList;
  begin
    Text := TStringList.Create;
    try
      Text.LoadFromFile(FDir + PathDelim + 'n.txt');
      Result := StrToInt(Trim(Text.Text)) >= 5;
    finally
      Text.Free;
    end;
  end;

begin
  Git(['init', '-q']);
  for i := 1 to 8 do
  begin
    WriteFile('n.txt', IntToStr(i) + #10);
    Commit('c' + IntToStr(i));
  end;
  AssertTrue(FRepo.Open(FDir));
  for i := 8 downto 1 do
    Ids[i] := FRepo.CommitId('HEAD~' + IntToStr(8 - i));
  AssertEquals('', FRepo.Operation);

  { Started with the bad commit alone, it waits for a good one. }
  AssertTrue(FRepo.Error, FRepo.BisectStart(Ids[8], ''));
  AssertEquals('bisecting', FRepo.Operation);
  AssertTrue(FRepo.BisectState(State));
  AssertEquals(Ids[8], State.Bad);
  AssertEquals(0, Length(State.Good));
  AssertEquals(-1, State.Left);
  AssertTrue(FRepo.GraphCommits(Graph));
  AssertTrue('the graph shows the mark', HasRef(Graph[0].Refs, 'bad'));
  AssertTrue(FRepo.Error, FRepo.BisectMark(Ids[1], bmGood));
  AssertTrue(FRepo.BisectState(State));
  AssertEquals(6, State.Left);
  AssertTrue('git checked out one to test', FRepo.CommitId('HEAD') <> Ids[8]);

  { Marking what is checked out leads to c5. }
  for i := 1 to 8 do
  begin
    if State.Found <> '' then
      Break;
    if Buggy then
      AssertTrue(FRepo.Error, FRepo.BisectMark('HEAD', bmBad))
    else
      AssertTrue(FRepo.Error, FRepo.BisectMark('HEAD', bmGood));
    AssertTrue(FRepo.BisectState(State));
  end;
  AssertEquals(Ids[5], State.Found);
  AssertEquals('c5', State.Subject);
  AssertEquals(0, State.Left);
  AssertFalse('a bad commit is not good too', FRepo.BisectMark(Ids[5], bmGood));
  AssertTrue(FRepo.Error, FRepo.BisectEnd);
  AssertEquals('', FRepo.Operation);
  AssertEquals(Ids[8], FRepo.CommitId('HEAD'));

  { Skipping the neighbours of the bug leaves suspects instead. }
  AssertTrue(FRepo.Error, FRepo.BisectStart(Ids[8], Ids[1]));
  AssertTrue(FRepo.Error, FRepo.BisectMark(Ids[3], bmGood));
  AssertTrue(FRepo.Error, FRepo.BisectMark(Ids[7], bmBad));
  AssertTrue(FRepo.Error, FRepo.BisectMark(Ids[4], bmSkip));
  AssertTrue(FRepo.Error, FRepo.BisectMark(Ids[6], bmBad));
  AssertTrue(FRepo.BisectState(State));
  AssertEquals(1, State.Left);
  AssertTrue('only skipped ones left counts as marked', FRepo.BisectMark(Ids[5], bmSkip));
  AssertTrue(FRepo.BisectState(State));
  AssertEquals(0, State.Left);
  AssertEquals('', State.Found);
  AssertEquals(3, Length(State.Suspects));
  AssertEquals(Ids[6], State.Suspects[2]);
  AssertTrue(FRepo.Error, FRepo.BisectEnd);
  AssertEquals('', FRepo.Operation);
end;

procedure TGitRepoTest.TestIsMailPatch;
begin
  AssertTrue(IsMailPatch('From 1234abcd Mon Sep 17 00:00:00 2001'#10'From: A <a@b>'#10));
  AssertTrue('blank lines first', IsMailPatch(#10#10'From 1234 Mon'#10));
  AssertTrue('a header alone', IsMailPatch('Date: today'#10'From: A <a@b>'#10 +
    'Subject: [PATCH] x'#10'  folded on'#10#10'body'#10));
  AssertTrue('any case', IsMailPatch('FROM: A'#10'SUBJECT: x'#10));
  AssertFalse('no subject', IsMailPatch('From: A <a@b>'#10#10'Subject: x'#10));
  AssertFalse('a plain diff', IsMailPatch('diff --git a/x b/x'#10'--- a/x'#10'+++ b/x'#10));
  AssertFalse('the header ends at a line that is none', IsMailPatch('From: A'#10 +
    'not a header'#10'Subject: x'#10));
  AssertFalse(IsMailPatch(''));
  AssertFalse(IsMailPatchFile(FDir + PathDelim + 'missing.patch'));
end;

procedure TGitRepoTest.TestPatches;
var
  First, Second, Last, Out: string;
  Commits: TGittanPatchCommits;
  Files, One: TStringList;
  Conflicts: boolean;
  Applied: integer;
begin
  MakeHistory;
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
  AssertTrue(FRepo.Open(FDir));
  First := Trim(Git(['rev-parse', 'HEAD']));
  WriteFile('a.txt', 'one'#10'TWO'#10'three'#10);
  Commit('second');
  Second := Trim(Git(['rev-parse', 'HEAD']));
  WriteFile('b.txt', 'b'#10);
  Commit('third');
  Last := Trim(Git(['rev-parse', 'HEAD']));

  AssertTrue(FRepo.Error, FRepo.PatchCommits('', Last, Commits));
  AssertEquals(1, Length(Commits));
  AssertEquals('third', Commits[0].Subject);
  AssertEquals(Last, Commits[0].Hash);
  AssertTrue(FRepo.Error, FRepo.PatchCommits(Second, Last, Commits));
  AssertEquals(2, Length(Commits));
  AssertEquals('oldest first', 'second', Commits[0].Subject);
  AssertTrue(FRepo.Error, FRepo.PatchCommits(First, Last, Commits));
  AssertEquals('from the root commit', 3, Length(Commits));
  AssertEquals('files', Commits[0].Subject);

  Out := FDir + PathDelim + 'out';
  Files := TStringList.Create;
  One := TStringList.Create;
  try
    AssertTrue(FRepo.Error, FRepo.FormatPatches('', Last, Out + '1', True, Files));
    AssertEquals(2, Files.Count);
    AssertEquals('0000-cover-letter.patch', ExtractFileName(Files[0]));
    AssertEquals('0001-third.patch', ExtractFileName(Files[1]));
    AssertTrue(FRepo.Error, FRepo.FormatPatches(First, Last, Out + '2', False, Files));
    AssertEquals('from the root commit', 3, Files.Count);
    AssertTrue(FRepo.Error, FRepo.FormatPatches(Second, Last, Out, False, Files));
    AssertEquals(2, Files.Count);
    AssertEquals('0001-second.patch', ExtractFileName(Files[0]));
    AssertEquals('0002-third.patch', ExtractFileName(Files[1]));
    AssertTrue(FileExists(Files[1]));
    AssertTrue(IsMailPatchFile(Files[0]));
    { A folder given relative is the root's, not this process's. }
    AssertTrue(FRepo.Error, FRepo.FormatPatches(Second, Last, 'rel', False, One));
    AssertEquals(2, One.Count);
    { Root has git's slashes on Windows; the names are expanded. }
    AssertEquals(ExpandFileName(IncludeTrailingPathDelimiter(FRepo.Root) + 'rel' + PathDelim +
      '0001-second.patch'), One[0]);
    AssertTrue(FileExists(One[0]));
    One.Clear;

    { Committed, as their author made them. }
    Git(['reset', '-q', '--hard', First]);
    AssertTrue(FRepo.Error, FRepo.ApplyPatches(Files, True, Conflicts, Applied));
    AssertEquals(2, Applied);
    AssertEquals('third'#10'second'#10'files'#10, Git(['log', '--format=%s']));

    { Into the work tree alone. }
    Git(['reset', '-q', '--hard', First]);
    AssertTrue(FRepo.Error, FRepo.ApplyPatches(Files, False, Conflicts, Applied));
    AssertEquals(2, Applied);
    AssertFalse(Conflicts);
    AssertEquals(First, Trim(Git(['rev-parse', 'HEAD'])));
    AssertEquals(' M a.txt'#10'?? b.txt'#10, Git(['status', '--porcelain', '--',
      'a.txt', 'b.txt']));

    { Changed but not staged, what --3way alone would refuse. }
    Git(['reset', '-q', '--hard', First]);
    Git(['clean', '-q', '-f', 'b.txt']);
    WriteFile('a.txt', 'one'#10'two'#10'three'#10'four'#10);
    One.Add(Files[0]);
    AssertTrue(FRepo.Error, FRepo.ApplyPatches(One, False, Conflicts, Applied));
    AssertEquals(1, Applied);

    { A patch that does not fit merges with conflicts; the rest wait. }
    Git(['reset', '-q', '--hard', First]);
    WriteFile('a.txt', 'one'#10'deux'#10'three'#10);
    Commit('deux');
    AssertFalse(FRepo.ApplyPatches(Files, False, Conflicts, Applied));
    AssertTrue(Conflicts);
    AssertEquals(1, Applied);
    AssertFalse('the second waits', FileExists(FDir + PathDelim + 'b.txt'));
    AssertTrue(Pos('a.txt', Git(['ls-files', '-u'])) > 0);
    AssertEquals('', FRepo.Operation);

    { An am stops there, for the Commit section to carry on. }
    Git(['reset', '-q', '--hard']);
    AssertFalse(FRepo.ApplyPatches(Files, True, Conflicts, Applied));
    AssertTrue(Conflicts);
    AssertEquals(0, Applied);
    AssertEquals('applying patches', FRepo.Operation);
    AssertTrue(FRepo.Error, FRepo.AbortOperation);
    AssertEquals('', FRepo.Operation);
    AssertEquals('deux', Trim(Git(['log', '-1', '--format=%s'])));
  finally
    One.Free;
    Files.Free;
  end;
end;

initialization
  Randomize;
  RegisterTest(TGitRepoTest);
end.
