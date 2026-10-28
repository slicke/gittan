unit testworktrees;

{** Tests of gittan.worktrees: the porcelain list read, and a worktree
  added, listed, locked, removed and pruned in a repository made for
  the test. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.git, gittan.worktrees, testhelpers;

type
  TWorktreesTest = class(TTestCase)
  private
    FDir: string;
    procedure Git(const AArgs: array of string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestParse;
    procedure TestSuggestPath;
    procedure TestAddListRemove;
  end;

implementation

procedure TWorktreesTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-worktrees-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
end;

procedure TWorktreesTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TWorktreesTest.Git(const AArgs: array of string);
var
  Output, Err: string;
begin
  if not RunGitIn(IncludeTrailingPathDelimiter(FDir) + 'repo', AArgs, Output, Err) then
    Fail('git ' + AArgs[0] + ' failed: ' + Err);
end;

procedure TWorktreesTest.TestParse;
var
  List: TGittanWorktrees;
begin
  List := ParseWorktreeList(
    'worktree /home/x/repo'#10'HEAD 1111111111111111111111111111111111111111'#10 +
    'branch refs/heads/main'#10#10 +
    'worktree /home/x/repo-feature'#10'HEAD 2222222222222222222222222222222222222222'#10 +
    'branch refs/heads/feature/x'#10'locked moved to a laptop'#10#10 +
    'worktree /home/x/gone'#10'HEAD 3333333333333333333333333333333333333333'#10 +
    'detached'#10'prunable gitdir file points to non-existent location'#10#10 +
    'worktree /home/x/bare.git'#10'bare'#10);
  AssertEquals(4, Length(List));
  AssertEquals('/home/x/repo', List[0].Path);
  AssertTrue('main', List[0].Main);
  AssertEquals('main', List[0].Branch);
  AssertEquals('1111111111111111111111111111111111111111', List[0].Head);
  AssertFalse(List[0].Locked);
  AssertEquals('/home/x/repo-feature', List[1].Path);
  AssertFalse('not main', List[1].Main);
  AssertEquals('feature/x', List[1].Branch);
  AssertTrue('locked', List[1].Locked);
  AssertEquals('moved to a laptop', List[1].LockReason);
  AssertTrue('detached', List[2].Detached);
  AssertEquals('', List[2].Branch);
  AssertTrue('prunable', List[2].Prunable);
  AssertEquals('gitdir file points to non-existent location', List[2].PruneReason);
  AssertTrue('bare', List[3].Bare);
  AssertEquals('', List[3].Head);
  AssertEquals(0, Length(ParseWorktreeList('')));
end;

procedure TWorktreesTest.TestSuggestPath;
var
  Root: string;
begin
  Root := IncludeTrailingPathDelimiter(FDir) + 'repo';
  ForceDirectories(Root);
  AssertEquals(IncludeTrailingPathDelimiter(FDir) + 'repo-feature-x',
    SuggestWorktreePath(Root, 'feature/x'));
  AssertEquals(IncludeTrailingPathDelimiter(FDir) + 'repo-wt', SuggestWorktreePath(Root, ''));
  ForceDirectories(IncludeTrailingPathDelimiter(FDir) + 'repo-wt');
  AssertEquals(IncludeTrailingPathDelimiter(FDir) + 'repo-wt-2', SuggestWorktreePath(Root, ''));
end;

procedure TWorktreesTest.TestAddListRemove;
var
  Root, Other, Err: string;
  List: TGittanWorktrees;
  Dirty: boolean;
begin
  Root := IncludeTrailingPathDelimiter(FDir) + 'repo';
  ForceDirectories(Root);
  Git(['init', '-q', '-b', 'main']);
  with TStringList.Create do
    try
      Text := 'a'#10;
      SaveToFile(IncludeTrailingPathDelimiter(Root) + 'a.txt');
    finally
      Free;
    end;
  Git(['add', 'a.txt']);
  Git(['commit', '-q', '-m', 'first']);
  AssertTrue(Err, ListWorktrees(Root, List, Err));
  AssertEquals(1, Length(List));
  AssertTrue(List[0].Main);
  AssertEquals('main', List[0].Branch);

  { A new branch in a new folder. }
  Other := IncludeTrailingPathDelimiter(FDir) + 'repo-feature';
  AssertTrue(Err, AddWorktree(Root, Other, 'feature', True, '', Err));
  AssertTrue('folder', DirectoryExists(Other));
  AssertTrue('file', FileExists(IncludeTrailingPathDelimiter(Other) + 'a.txt'));
  AssertTrue(Err, ListWorktrees(Root, List, Err));
  AssertEquals(2, Length(List));
  AssertEquals('feature', List[1].Branch);
  AssertFalse(List[1].Main);
  AssertEquals(List[0].Head, List[1].Head);
  { Listed from the other worktree too. }
  AssertTrue(Err, ListWorktrees(Other, List, Err));
  AssertEquals(2, Length(List));

  { A branch checked out elsewhere is refused. }
  AssertFalse(AddWorktree(Root, IncludeTrailingPathDelimiter(FDir) + 'again', 'feature', False,
    '', Err));
  AssertTrue(Err, Err <> '');

  { Locked, then a change keeps it from being removed without force. }
  AssertTrue(Err, LockWorktree(Root, Other, True, Err));
  AssertTrue(Err, ListWorktrees(Root, List, Err));
  AssertTrue('locked', List[1].Locked);
  AssertFalse(RemoveWorktree(Root, Other, False, Err, Dirty));
  AssertTrue('dirty for the lock', Dirty);
  AssertTrue(Err, LockWorktree(Root, Other, False, Err));
  with TStringList.Create do
    try
      Text := 'b'#10;
      SaveToFile(IncludeTrailingPathDelimiter(Other) + 'b.txt');
    finally
      Free;
    end;
  AssertFalse(RemoveWorktree(Root, Other, False, Err, Dirty));
  AssertTrue('dirty', Dirty);
  { Force removes it with the change and a lock both. }
  AssertTrue(Err, LockWorktree(Root, Other, True, Err));
  AssertTrue(Err, RemoveWorktree(Root, Other, True, Err, Dirty));
  AssertFalse('folder gone', DirectoryExists(Other));
  AssertTrue(Err, ListWorktrees(Root, List, Err));
  AssertEquals(1, Length(List));
  { The branch stays, and is free to check out in a worktree again. }
  Git(['rev-parse', '--verify', 'refs/heads/feature']);
  AssertTrue(Err, AddWorktree(Root, Other, 'feature', False, '', Err));
  AssertTrue(Err, ListWorktrees(Root, List, Err));
  AssertEquals('feature', List[1].Branch);
  AssertTrue(Err, RemoveWorktree(Root, Other, False, Err, Dirty));

  { A folder that goes away is prunable, and pruned; with no branch git
    makes one named after the folder. }
  AssertTrue(Err, AddWorktree(Root, Other, '', False, '', Err));
  RemoveTree(Other);
  AssertTrue(Err, ListWorktrees(Root, List, Err));
  AssertEquals(2, Length(List));
  AssertEquals('repo-feature', List[1].Branch);
  AssertTrue('prunable', List[1].Prunable);
  AssertTrue(Err, PruneWorktrees(Root, Err));
  AssertTrue(Err, ListWorktrees(Root, List, Err));
  AssertEquals(1, Length(List));
end;

initialization
  RegisterTest(TWorktreesTest);

end.
