unit testgit;

{** Tests of gittan.git. The status parsing is tested on its own; the
  rest runs the real git against a repository made in a temporary folder
  for each test, so git must be on PATH. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.git, gittan.history;

type
  TGitRepoTest = class(TTestCase)
  private
    FDir: string;
    FRepo: TGittanRepo;
    function Git(const AArgs: array of string): string;
    procedure WriteFile(const APath, AContent: string);
    procedure Commit(const AMessage: string);
    procedure MakeHistory;
    function FindStat(const AStats: TGittanFileStats; const APath: string): TGittanFileStat;
    function Joined(AList: TStrings): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestChangeKind;
    procedure TestStageFlags;
    procedure TestOpenNonRepo;
    procedure TestOpenSubfolderFindsRoot;
    procedure TestChangeStats;
    procedure TestFileChanges;
    procedure TestIgnoreWhitespace;
    procedure TestUnbornRepository;
    procedure TestBase;
    procedure TestRange;
    procedure TestFingerprint;
    procedure TestFiles;
    procedure TestGrep;
    procedure TestSnapshot;
    procedure TestBlame;
    procedure TestCommitRange;
    procedure TestLineHistory;
    procedure TestRemoteFor;
    procedure TestFetchPullRequest;
    procedure TestDefaultBranchAndMergeBase;
    procedure TestAheadBehind;
    procedure TestOperation;
  end;

implementation

uses
  Process;

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
  Status, i: integer;
begin
  SetLength(Args, Length(AArgs) + 4);
  Args[0] := '-c';
  Args[1] := 'user.name=Gittan Test';
  Args[2] := '-c';
  Args[3] := 'user.email=test@example.invalid';
  for i := 0 to High(AArgs) do
    Args[i + 4] := AArgs[i];
  if RunCommandIndir(FDir, 'git', Args, Result, Status, [poStderrToOutPut]) <> 0 then
    Fail('git could not be run');
  if Status <> 0 then
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
end;

{ A snapshot holds the untracked files, and the whole tree comparison
  against it sees only what changed since: an untracked file it holds is
  no change, a new one is added, a deleted one deleted; the repository's
  own index stays as it was. }
procedure TGitRepoTest.TestSnapshot;
var
  Id, Status: string;
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
  Status := Git(['status', '--porcelain']);
  AssertTrue('new.txt still untracked', Pos('?? new.txt', Status) > 0);
  AssertTrue('a.txt still unstaged', Pos(' M a.txt', Status) > 0);

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
  Status := Git(['status', '--porcelain']);
  AssertTrue('later.txt untracked for git', Pos('?? later.txt', Status) > 0);

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
  Git(['remote', 'remove', 'origin']);
  AssertEquals('upstream', FRepo.RemoteFor('nobody/nothing'));
end;

{ A bare repository stands in for GitHub: it serves the pull request as
  refs/pull/7/head, as GitHub does. }
procedure TGitRepoTest.TestFetchPullRequest;
var
  Remote, Branch, Head, HeadRef, Output: string;
  Status: integer;
begin
  MakeHistory;
  Remote := FDir + '-remote';
  if RunCommandIndir(FDir, 'git', ['init', '-q', '--bare', Remote], Output, Status,
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
    AssertTrue(FRepo.FetchPullRequest('origin', 7, Branch, HeadRef));
    AssertEquals('refs/gittan/pr/7', HeadRef);
    AssertEquals(Head, Trim(Git(['rev-parse', HeadRef])));
    AssertTrue(FRepo.HasCommit('origin/' + Branch));
    AssertFalse(FRepo.FetchPullRequest('origin', 8, Branch, HeadRef));
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
  Status: integer;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  AssertEquals('', FRepo.DefaultBranch);
  AssertFalse(FRepo.MergeBase('', Hash));
  AssertFalse(FRepo.MergeBase('nothing', Hash));
  Remote := FDir + '-remote';
  if RunCommandIndir(FDir, 'git', ['init', '-q', '--bare', Remote], Output, Status,
    [poStderrToOutPut]) <> 0 then
    Fail('could not make a bare repository');
  try
    Branch := Trim(Git(['rev-parse', '--abbrev-ref', 'HEAD']));
    Base := Trim(Git(['rev-parse', 'HEAD']));
    Git(['remote', 'add', 'origin', Remote]);
    Git(['push', '-q', 'origin', Branch]);
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

procedure TGitRepoTest.TestAheadBehind;
var
  Remote, Branch, Output: string;
  Status, Ahead, Behind: integer;
begin
  MakeHistory;
  AssertTrue(FRepo.Open(FDir));
  AssertFalse(FRepo.AheadBehind(Ahead, Behind));
  Remote := FDir + '-remote';
  if RunCommandIndir(FDir, 'git', ['init', '-q', '--bare', Remote], Output, Status,
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

{ A merge and a rebase that stop on a conflict, each aborted after. }
procedure TGitRepoTest.TestOperation;
var
  Branch, Output: string;
  Stats: TGittanFileStats;
  Status: integer;
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
    'merge', 'topic'], Output, Status, [poStderrToOutPut]);
  AssertTrue('merge stops', Status <> 0);
  AssertEquals('merging', FRepo.Operation);
  AssertTrue(FRepo.ChangeStats(Stats));
  AssertEquals(Ord(ckConflict), Ord(FindStat(Stats, 'a.txt').Kind));
  Git(['merge', '--abort']);
  AssertEquals('', FRepo.Operation);

  Git(['checkout', '-q', 'topic']);
  RunCommandIndir(FDir, 'git', ['-c', 'user.name=T', '-c', 'user.email=t@example.invalid',
    'rebase', Branch], Output, Status, [poStderrToOutPut]);
  AssertTrue('rebase stops', Status <> 0);
  AssertEquals('rebasing', FRepo.Operation);
  AssertEquals('topic', FRepo.RebaseBranch);
  Git(['rebase', '--abort']);
  AssertEquals('', FRepo.Operation);
  AssertEquals('', FRepo.RebaseBranch);
end;

procedure TGitRepoTest.TestCommitRange;
var
  Stats: TGittanFileStats;
  Root, Second: string;
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

initialization
  Randomize;
  RegisterTest(TGitRepoTest);
end.
