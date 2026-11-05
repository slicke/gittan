unit testbatch;

{** Tests of gittan.batch: the rows of the repository list and the recent
  repositories, a folder's repositories, and in a clone of a repository
  made for the test the branches deleted on the remote found after a
  fetch (merged, squashed, not merged; the current one and one still on
  the remote left out), deleted, and a deletion git refuses; and the
  overview of what is left undone in a repository: clean, with changes,
  untracked files, a stash, a branch ahead of its upstream and one on
  no remote, in the middle of a merge, and without a remote. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.git, gittan.repolist, gittan.batch,
  testhelpers;

type
  TBatchTest = class(TTestCase)
  private
    FDir, FWork, FRemote: string;
    procedure Git(const ADir: string; const AArgs: array of string);
    function GitOut(const ADir: string; const AArgs: array of string): string;
    procedure CommitFile(const AName, AText, AMessage: string);
    procedure MakeRepos;
    function FindBranch(const ARepo: TGittanGoneRepo; const AName: string): integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRows;
    procedure TestRowsNoRecentHeading;
    procedure TestRowRepos;
    procedure TestScan;
    procedure TestScanNotARepo;
    procedure TestDelete;
    procedure TestDeleteRefused;
    procedure TestJobs;
    procedure TestStatusClean;
    procedure TestStatusUndone;
    procedure TestStatusOperation;
    procedure TestStatusNoRemote;
    procedure TestStatusJob;
  end;

implementation

procedure TBatchTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-batch-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
  FWork := IncludeTrailingPathDelimiter(FDir) + 'work';
  FRemote := IncludeTrailingPathDelimiter(FDir) + 'remote.git';
end;

procedure TBatchTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TBatchTest.Git(const ADir: string; const AArgs: array of string);
var
  Output, Err: string;
begin
  if not RunGitIn(ADir, AArgs, Output, Err) then
    Fail('git ' + AArgs[0] + ' failed: ' + Err);
end;

function TBatchTest.GitOut(const ADir: string; const AArgs: array of string): string;
var
  Err: string;
begin
  if not RunGitIn(ADir, AArgs, Result, Err) then
    Result := '';
  Result := Trim(Result);
end;

procedure TBatchTest.CommitFile(const AName, AText, AMessage: string);
begin
  with TStringList.Create do
    try
      Text := AText;
      SaveToFile(IncludeTrailingPathDelimiter(FWork) + AName);
    finally
      Free;
    end;
  Git(FWork, ['add', AName]);
  Git(FWork, ['commit', '-q', '-m', AMessage]);
end;

{ A work repository with a bare remote: main; merged, merged into main
  by a fast-forward; squash, two commits squashed into one on main; wip,
  not merged; keep, still on the remote; current, checked out. Then
  merged, squash, wip and current are deleted on the remote alone, so
  only a fetch with --prune finds them gone. }
procedure TBatchTest.MakeRepos;
var
  Name: string;
begin
  ForceDirectories(FWork);
  ForceDirectories(FRemote);
  Git(FRemote, ['init', '-q', '--bare']);
  Git(FRemote, ['symbolic-ref', 'HEAD', 'refs/heads/main']);
  Git(FWork, ['init', '-q']);
  Git(FWork, ['symbolic-ref', 'HEAD', 'refs/heads/main']);
  Git(FWork, ['remote', 'add', 'origin', FRemote]);
  CommitFile('a.txt', 'a', 'first');
  Git(FWork, ['push', '-q', '-u', 'origin', 'main']);

  Git(FWork, ['switch', '-q', '-c', 'merged']);
  CommitFile('b.txt', 'b', 'merged work');
  Git(FWork, ['push', '-q', '-u', 'origin', 'merged']);
  Git(FWork, ['switch', '-q', 'main']);
  Git(FWork, ['merge', '-q', '--ff-only', 'merged']);

  Git(FWork, ['switch', '-q', '-c', 'squash']);
  CommitFile('c.txt', 'c', 'squash one');
  CommitFile('d.txt', 'd', 'squash two');
  Git(FWork, ['push', '-q', '-u', 'origin', 'squash']);
  Git(FWork, ['switch', '-q', 'main']);
  Git(FWork, ['merge', '-q', '--squash', 'squash']);
  Git(FWork, ['commit', '-q', '-m', 'squashed']);
  Git(FWork, ['push', '-q', 'origin', 'main']);

  Git(FWork, ['switch', '-q', '-c', 'wip']);
  CommitFile('e.txt', 'e', 'wip');
  Git(FWork, ['push', '-q', '-u', 'origin', 'wip']);

  Git(FWork, ['switch', '-q', '-c', 'keep', 'main']);
  Git(FWork, ['push', '-q', '-u', 'origin', 'keep']);

  Git(FWork, ['switch', '-q', '-c', 'current', 'main']);
  Git(FWork, ['push', '-q', '-u', 'origin', 'current']);

  for Name in ['merged', 'squash', 'wip', 'current'] do
    Git(FRemote, ['branch', '-q', '-D', Name]);
end;

function TBatchTest.FindBranch(const ARepo: TGittanGoneRepo; const AName: string): integer;
begin
  for Result := 0 to High(ARepo.Branches) do
    if ARepo.Branches[Result].Name = AName then
      Exit;
  Result := -1;
end;

procedure TBatchTest.TestRows;
var
  List: TGittanRepoList;
  Folder: TGittanRepoEntry;
  Recent: TStringList;
  Rows: TGittanBatchRows;
begin
  List := TGittanRepoList.Create('');
  Recent := TStringList.Create;
  try
    List.AddRepo(nil, '/src/top');
    Folder := List.AddFolder(nil, 'Work');
    Folder.Collapsed := True;
    List.AddRepo(Folder, '/src/one');
    List.AddRepo(List.AddFolder(Folder, 'Inner'), '/src/two');
    Recent.Add('/src/one');
    Recent.Add('/src/three');
    Rows := BatchRows(List, Recent, 'Recent');
    AssertEquals(7, Length(Rows));
    AssertEquals('/src/top', Rows[0].Path);
    AssertTrue(Rows[1].IsFolder);
    AssertEquals('Work', Rows[1].Caption);
    { A collapsed folder's repositories are there too. }
    AssertEquals('/src/one', Rows[2].Path);
    AssertEquals(1, Rows[2].Depth);
    AssertEquals('Inner', Rows[3].Caption);
    AssertEquals('/src/two', Rows[4].Path);
    AssertEquals(2, Rows[4].Depth);
    { The recent one the list has is not listed again. }
    AssertTrue(Rows[5].IsFolder);
    AssertEquals('Recent', Rows[5].Caption);
    AssertEquals('', Rows[5].Path);
    AssertEquals('/src/three', Rows[6].Path);
    AssertEquals('three', Rows[6].Caption);
    AssertEquals(1, Rows[6].Depth);
  finally
    Recent.Free;
    List.Free;
  end;
end;

procedure TBatchTest.TestRowsNoRecentHeading;
var
  List: TGittanRepoList;
  Recent: TStringList;
  Rows: TGittanBatchRows;
begin
  List := TGittanRepoList.Create('');
  Recent := TStringList.Create;
  try
    List.AddRepo(nil, '/src/one');
    Recent.Add('/src/one');
    Rows := BatchRows(List, Recent, 'Recent');
    AssertEquals(1, Length(Rows));
    AssertEquals(0, Length(BatchRows(nil, nil, 'Recent')));
  finally
    Recent.Free;
    List.Free;
  end;
end;

procedure TBatchTest.TestRowRepos;
var
  List: TGittanRepoList;
  Folder: TGittanRepoEntry;
  Rows: TGittanBatchRows;
  Paths: TStringArray;
begin
  List := TGittanRepoList.Create('');
  try
    Folder := List.AddFolder(nil, 'Work');
    List.AddRepo(Folder, '/src/one');
    List.AddRepo(List.AddFolder(Folder, 'Inner'), '/src/two');
    List.AddRepo(nil, '/src/top');
    Rows := BatchRows(List, nil, 'Recent');
    Paths := BatchRowRepos(Rows, 0);
    AssertEquals(2, Length(Paths));
    AssertEquals('/src/one', Paths[0]);
    AssertEquals('/src/two', Paths[1]);
    Paths := BatchRowRepos(Rows, 2);
    AssertEquals(1, Length(Paths));
    AssertEquals('/src/two', Paths[0]);
    Paths := BatchRowRepos(Rows, 4);
    AssertEquals(1, Length(Paths));
    AssertEquals('/src/top', Paths[0]);
    AssertEquals(0, Length(BatchRowRepos(Rows, 9)));
  finally
    List.Free;
  end;
end;

procedure TBatchTest.TestScan;
var
  Repo: TGittanGoneRepo;
  i: integer;
begin
  MakeRepos;
  { Without a fetch the remote's deletions are not seen yet. }
  Repo := ScanGoneRepo(FWork, 'work', False);
  AssertEquals('', Repo.Error);
  AssertEquals(0, Length(Repo.Branches));

  Repo := ScanGoneRepo(FWork, '', True);
  AssertEquals('', Repo.Error);
  AssertEquals('', Repo.FetchError);
  AssertEquals('work', Repo.Caption);
  AssertEquals(3, Length(Repo.Branches));
  AssertEquals(-1, FindBranch(Repo, 'current'));
  AssertEquals(-1, FindBranch(Repo, 'keep'));
  i := FindBranch(Repo, 'merged');
  AssertTrue(i >= 0);
  AssertTrue(Repo.Branches[i].Merge = gmMerged);
  i := FindBranch(Repo, 'squash');
  AssertTrue(i >= 0);
  AssertTrue(Repo.Branches[i].Merge = gmSquashed);
  i := FindBranch(Repo, 'wip');
  AssertTrue(i >= 0);
  AssertTrue(Repo.Branches[i].Merge = gmNotMerged);
end;

procedure TBatchTest.TestScanNotARepo;
var
  Repo: TGittanGoneRepo;
begin
  Repo := ScanGoneRepo(IncludeTrailingPathDelimiter(FDir) + 'missing', '', True);
  AssertTrue(Repo.Error <> '');
  AssertEquals('missing', Repo.Caption);
  ForceDirectories(IncludeTrailingPathDelimiter(FDir) + 'plain');
  Repo := ScanGoneRepo(IncludeTrailingPathDelimiter(FDir) + 'plain', '', False);
  { A folder inside no repository; the temporary folder may lie in one
    on some machines, which then answers for it. }
  if GitOut(IncludeTrailingPathDelimiter(FDir) + 'plain', ['rev-parse', '--show-toplevel']) = '' then
    AssertTrue(Repo.Error <> '');
end;

procedure TBatchTest.TestDelete;
var
  Branch: TGittanGoneBranch;
  Tip: string;
begin
  MakeRepos;
  Tip := GitOut(FWork, ['rev-parse', '--short', 'wip']);
  Branch := DeleteGoneBranch(FWork, 'wip');
  AssertTrue(Branch.Error, Branch.Deleted);
  AssertEquals(Tip, Branch.Was);
  AssertEquals('', GitOut(FWork, ['branch', '--list', 'wip']));
end;

procedure TBatchTest.TestDeleteRefused;
var
  Branch: TGittanGoneBranch;
begin
  MakeRepos;
  { The branch checked out cannot go. }
  Branch := DeleteGoneBranch(FWork, 'current');
  AssertFalse(Branch.Deleted);
  AssertTrue(Branch.Error <> '');
  AssertEquals('', Branch.Was);
  AssertTrue(Pos('error: ', Branch.Error) = 0);
  Branch := DeleteGoneBranch(FWork, 'nosuch');
  AssertFalse(Branch.Deleted);
end;

procedure TBatchTest.TestJobs;
var
  Scan: TGittanGoneScanJob;
  Del: TGittanGoneDeleteJob;
  Refs: TGittanBranchRefs;
begin
  MakeRepos;
  Scan := TGittanGoneScanJob.Create([FWork, IncludeTrailingPathDelimiter(FDir) + 'missing'],
    ['Work']);
  try
    Scan.Start;
    Scan.WaitFor;
    AssertEquals(2, Scan.Finished);
    AssertEquals('Work', Scan.Repos[0].Caption);
    AssertEquals(3, Length(Scan.Repos[0].Branches));
    AssertTrue(Scan.Repos[1].Error <> '');
  finally
    Scan.Free;
  end;
  Refs := nil;
  SetLength(Refs, 2);
  Refs[0].Path := FWork;
  Refs[0].Branch := 'merged';
  Refs[1].Path := FWork;
  Refs[1].Branch := 'current';
  Del := TGittanGoneDeleteJob.Create(Refs);
  try
    Del.Start;
    Del.WaitFor;
    AssertEquals(2, Del.Finished);
    AssertTrue(Del.Branches[0].Deleted);
    AssertFalse(Del.Branches[1].Deleted);
  finally
    Del.Free;
  end;
end;

{ MakeRepos's work repository on main, fetched and pruned, with the
  gone branches deleted: nothing left undone. }
procedure TBatchTest.TestStatusClean;
var
  Status: TGittanRepoStatus;
begin
  MakeRepos;
  Git(FWork, ['switch', '-q', 'main']);
  Git(FWork, ['fetch', '-q', '--prune']);
  Git(FWork, ['branch', '-q', '-D', 'merged', 'squash', 'wip', 'current']);
  Status := RepoStatus(FWork, '');
  AssertEquals('', Status.Error);
  AssertEquals('work', Status.Caption);
  AssertEquals('main', Status.Branch);
  AssertFalse(Status.Detached);
  AssertEquals(0, Status.Changed);
  AssertEquals(0, Status.Untracked);
  AssertEquals(0, Status.Stashes);
  AssertEquals(0, Length(Status.Unpushed));
  AssertEquals(0, Length(Status.Unshared));
  AssertFalse(Status.NoRemote);
  AssertTrue(StatusClean(Status));
end;

procedure TBatchTest.TestStatusUndone;
var
  Status: TGittanRepoStatus;
begin
  MakeRepos;
  Git(FWork, ['switch', '-q', 'main']);
  Git(FWork, ['branch', '-q', '-D', 'merged', 'squash', 'wip', 'current']);
  { keep one ahead of its upstream; local, never pushed, two commits on
    no remote; empty, never pushed, none. }
  Git(FWork, ['switch', '-q', 'keep']);
  CommitFile('k.txt', 'k', 'keep ahead');
  Git(FWork, ['switch', '-q', '-c', 'local', 'main']);
  CommitFile('l1.txt', 'l', 'local one');
  CommitFile('l2.txt', 'l', 'local two');
  Git(FWork, ['switch', '-q', '-c', 'empty', 'main']);
  Git(FWork, ['switch', '-q', 'main']);
  { A stash, then a change, a staged file and two untracked. }
  with TStringList.Create do
    try
      Text := 'changed';
      SaveToFile(IncludeTrailingPathDelimiter(FWork) + 'a.txt');
      Git(FWork, ['stash', '-q']);
      SaveToFile(IncludeTrailingPathDelimiter(FWork) + 'a.txt');
      SaveToFile(IncludeTrailingPathDelimiter(FWork) + 'new.txt');
      Git(FWork, ['add', 'new.txt']);
      SaveToFile(IncludeTrailingPathDelimiter(FWork) + 'u1.txt');
      SaveToFile(IncludeTrailingPathDelimiter(FWork) + 'u2.txt');
    finally
      Free;
    end;
  Status := RepoStatus(FWork, 'Work');
  AssertEquals('', Status.Error);
  AssertEquals('Work', Status.Caption);
  AssertEquals(2, Status.Changed);
  AssertEquals(2, Status.Untracked);
  AssertEquals(1, Status.Stashes);
  AssertEquals(1, Length(Status.Unpushed));
  AssertEquals('keep', Status.Unpushed[0].Name);
  AssertEquals(1, Status.Unpushed[0].Count);
  AssertEquals(1, Length(Status.Unshared));
  AssertEquals('local', Status.Unshared[0].Name);
  AssertEquals(2, Status.Unshared[0].Count);
  AssertFalse(StatusClean(Status));

  { A detached HEAD has no branch. }
  Git(FWork, ['stash', '-q', '-u']);
  Git(FWork, ['switch', '-q', '--detach', 'main']);
  Status := RepoStatus(FWork, '');
  AssertTrue(Status.Detached);
  AssertEquals('', Status.Branch);
  AssertFalse(StatusClean(Status));
end;

procedure TBatchTest.TestStatusOperation;
var
  Status: TGittanRepoStatus;
  Output, Err: string;
begin
  MakeRepos;
  Git(FWork, ['switch', '-q', 'main']);
  Git(FWork, ['switch', '-q', '-c', 'one']);
  CommitFile('a.txt', 'one', 'one');
  Git(FWork, ['switch', '-q', '-c', 'two', 'main']);
  CommitFile('a.txt', 'two', 'two');
  { Stops on the conflict in a.txt. }
  AssertFalse(RunGitIn(FWork, ['merge', '-q', 'one'], Output, Err));
  Status := RepoStatus(FWork, '');
  AssertEquals('merging', Status.Operation);
  AssertTrue(Status.Changed > 0);
  AssertFalse(StatusClean(Status));
end;

procedure TBatchTest.TestStatusNoRemote;
var
  Status: TGittanRepoStatus;
begin
  ForceDirectories(FWork);
  Git(FWork, ['init', '-q']);
  CommitFile('a.txt', 'a', 'first');
  Git(FWork, ['switch', '-q', '-c', 'side']);
  CommitFile('b.txt', 'b', 'side');
  Status := RepoStatus(FWork, '');
  AssertEquals('', Status.Error);
  AssertTrue(Status.NoRemote);
  { Every commit is on no remote: not told branch by branch. }
  AssertEquals(0, Length(Status.Unshared));
  AssertFalse(StatusClean(Status));
  Status := RepoStatus(IncludeTrailingPathDelimiter(FDir) + 'missing', '');
  AssertTrue(Status.Error <> '');
  AssertFalse(StatusClean(Status));
end;

procedure TBatchTest.TestStatusJob;
var
  Job: TGittanStatusJob;
begin
  MakeRepos;
  Job := TGittanStatusJob.Create([FWork, IncludeTrailingPathDelimiter(FDir) + 'missing'],
    ['Work', '']);
  try
    Job.Start;
    Job.WaitFor;
    AssertEquals(2, Job.Finished);
    AssertEquals('Work', Job.Repos[0].Caption);
    AssertEquals('current', Job.Repos[0].Branch);
    AssertTrue(Job.Repos[1].Error <> '');
    AssertEquals('missing', Job.Repos[1].Caption);
  finally
    Job.Free;
  end;
end;

initialization
  RegisterTest(TBatchTest);
end.
