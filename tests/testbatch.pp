unit testbatch;

{** Tests of gittan.batch: the rows of the repository list and the recent
  repositories, a folder's repositories, and in a clone of a repository
  made for the test the branches deleted on the remote found after a
  fetch (merged, squashed, not merged; the current one and one still on
  the remote left out), deleted, and a deletion git refuses; and the
  overview of what is left undone in a repository: clean, with changes,
  untracked files (each of a new folder), a stash, a branch ahead of
  its upstream and one on no remote, one whose upstream is gone with
  work on no remote, a branch beside a tag of its name, in the middle
  of a merge, and without a remote; a branch that tracks a local one
  never gone, a remote with skipFetchAll still fetched; and who a
  repository commits as, the owner of a remote's URL (an ssh alias by
  its HostName) and the
  repositories that commit under another e-mail than the others of
  their owner; and maintenance: a remote's HEAD moved on the remote
  (to a branch not fetched yet too), a
  worktree whose folder is gone and loose objects found, each done and
  then no longer found, a remote that cannot be reached, and the jobs. }

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
    procedure MakeClone;
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
    procedure TestScanTagAndLocalUpstream;
    procedure TestScanSkipFetchAll;
    procedure TestDelete;
    procedure TestDeleteRefused;
    procedure TestJobs;
    procedure TestStatusClean;
    procedure TestStatusUndone;
    procedure TestStatusOperation;
    procedure TestStatusNoRemote;
    procedure TestStatusGoneUpstream;
    procedure TestStatusUntrackedFolder;
    procedure TestStatusJob;
    procedure TestIdentity;
    procedure TestIdentityLocal;
    procedure TestRemoteOwner;
    procedure TestRemoteOwnerSshAlias;
    procedure TestSameIdentity;
    procedure TestOddIdentities;
    procedure TestIdentityJob;
    procedure TestMaintSetHead;
    procedure TestMaintSetHeadUnfetched;
    procedure TestMaintWorktrees;
    procedure TestMaintPack;
    procedure TestMaintRemoteError;
    procedure TestMaintNotARepo;
    procedure TestMaintJobs;
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
const
  { A typed array: FPC 3.2.2 makes ['merged', ..., 'current'] an array
    of shortstrings as long as its first, so current came out curren. }
  GoneNames: array[0..3] of string = ('merged', 'squash', 'wip', 'current');
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

  for Name in GoneNames do
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
    AssertEquals(RepoListPath('/src/top'), Rows[0].Path);
    AssertTrue(Rows[1].IsFolder);
    AssertEquals('Work', Rows[1].Caption);
    { A collapsed folder's repositories are there too. }
    AssertEquals(RepoListPath('/src/one'), Rows[2].Path);
    AssertEquals(1, Rows[2].Depth);
    AssertEquals('Inner', Rows[3].Caption);
    AssertEquals(RepoListPath('/src/two'), Rows[4].Path);
    AssertEquals(2, Rows[4].Depth);
    { The recent one the list has is not listed again. }
    AssertTrue(Rows[5].IsFolder);
    AssertEquals('Recent', Rows[5].Caption);
    AssertEquals('', Rows[5].Path);
    AssertEquals(RepoListPath('/src/three'), Rows[6].Path);
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
    AssertEquals(RepoListPath('/src/one'), Paths[0]);
    AssertEquals(RepoListPath('/src/two'), Paths[1]);
    Paths := BatchRowRepos(Rows, 2);
    AssertEquals(1, Length(Paths));
    AssertEquals(RepoListPath('/src/two'), Paths[0]);
    Paths := BatchRowRepos(Rows, 4);
    AssertEquals(1, Length(Paths));
    AssertEquals(RepoListPath('/src/top'), Paths[0]);
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
  St: TGittanRepoStatus;
begin
  MakeRepos;
  Git(FWork, ['switch', '-q', 'main']);
  Git(FWork, ['fetch', '-q', '--prune']);
  Git(FWork, ['branch', '-q', '-D', 'merged', 'squash', 'wip', 'current']);
  St := RepoStatus(FWork, '');
  AssertEquals('', St.Error);
  AssertEquals('work', St.Caption);
  AssertEquals('main', St.Branch);
  AssertFalse(St.Detached);
  AssertEquals(0, St.Changed);
  AssertEquals(0, St.Untracked);
  AssertEquals(0, St.Stashes);
  AssertEquals(0, Length(St.Unpushed));
  AssertEquals(0, Length(St.Unshared));
  AssertFalse(St.NoRemote);
  AssertTrue(StatusClean(St));
end;

{ A tag named as a branch (keep, wip), and a branch that tracks a
  local branch deleted since: wip is still gone by its own name, the
  local one is not gone from any remote. }
procedure TBatchTest.TestScanTagAndLocalUpstream;
var
  Repo: TGittanGoneRepo;
begin
  MakeRepos;
  Git(FWork, ['tag', 'wip', 'main']);
  Git(FWork, ['tag', 'keep', 'main']);
  Git(FWork, ['branch', '-q', 'base', 'main']);
  Git(FWork, ['branch', '-q', '--track', 'onbase', 'base']);
  Git(FWork, ['branch', '-q', '-D', 'base']);
  Repo := ScanGoneRepo(FWork, '', True);
  AssertEquals('', Repo.Error);
  AssertEquals('', Repo.FetchError);
  AssertTrue(FindBranch(Repo, 'wip') >= 0);
  AssertEquals(-1, FindBranch(Repo, 'heads/wip'));
  AssertEquals(-1, FindBranch(Repo, 'onbase'));
  AssertEquals(-1, FindBranch(Repo, 'keep'));
  AssertEquals(3, Length(Repo.Branches));
end;

{ origin skipped by fetch --all is fetched all the same. }
procedure TBatchTest.TestScanSkipFetchAll;
var
  Repo: TGittanGoneRepo;
begin
  MakeRepos;
  Git(FWork, ['config', 'remote.origin.skipFetchAll', 'true']);
  Repo := ScanGoneRepo(FWork, '', True);
  AssertEquals('', Repo.FetchError);
  AssertEquals(3, Length(Repo.Branches));
  AssertTrue(FindBranch(Repo, 'wip') >= 0);
end;

procedure TBatchTest.TestStatusUndone;
var
  St: TGittanRepoStatus;
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
  St := RepoStatus(FWork, 'Work');
  AssertEquals('', St.Error);
  AssertEquals('Work', St.Caption);
  AssertEquals(2, St.Changed);
  AssertEquals(2, St.Untracked);
  AssertEquals(1, St.Stashes);
  AssertEquals(1, Length(St.Unpushed));
  AssertEquals('keep', St.Unpushed[0].Name);
  AssertEquals(1, St.Unpushed[0].Count);
  AssertEquals(1, Length(St.Unshared));
  AssertEquals('local', St.Unshared[0].Name);
  AssertEquals(2, St.Unshared[0].Count);
  AssertFalse(StatusClean(St));

  { A detached HEAD has no branch. }
  Git(FWork, ['stash', '-q', '-u']);
  Git(FWork, ['switch', '-q', '--detach', 'main']);
  St := RepoStatus(FWork, '');
  AssertTrue(St.Detached);
  AssertEquals('', St.Branch);
  AssertFalse(StatusClean(St));
end;

procedure TBatchTest.TestStatusOperation;
var
  St: TGittanRepoStatus;
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
  St := RepoStatus(FWork, '');
  AssertEquals('merging', St.Operation);
  AssertTrue(St.Changed > 0);
  AssertFalse(StatusClean(St));
end;

procedure TBatchTest.TestStatusNoRemote;
var
  St: TGittanRepoStatus;
begin
  ForceDirectories(FWork);
  Git(FWork, ['init', '-q']);
  CommitFile('a.txt', 'a', 'first');
  Git(FWork, ['switch', '-q', '-c', 'side']);
  CommitFile('b.txt', 'b', 'side');
  St := RepoStatus(FWork, '');
  AssertEquals('', St.Error);
  AssertTrue(St.NoRemote);
  { Every commit is on no remote: not told branch by branch. }
  AssertEquals(0, Length(St.Unshared));
  AssertFalse(StatusClean(St));
  St := RepoStatus(IncludeTrailingPathDelimiter(FDir) + 'missing', '');
  AssertTrue(St.Error <> '');
  AssertFalse(StatusClean(St));
end;

{ wip's upstream is deleted on the remote: its commit is on no remote,
  not "pushed" because nothing is ahead of a ref that is gone. A tag of
  the name of keep, ahead of its upstream, leaves its name as it is. }
procedure TBatchTest.TestStatusGoneUpstream;
var
  St: TGittanRepoStatus;
begin
  MakeRepos;
  Git(FWork, ['switch', '-q', 'main']);
  Git(FWork, ['branch', '-q', '-D', 'merged', 'squash', 'current']);
  Git(FWork, ['fetch', '-q', '--prune', 'origin']);
  Git(FWork, ['tag', 'keep', 'main']);
  Git(FWork, ['switch', '-q', 'keep']);
  CommitFile('k.txt', 'k', 'keep ahead');
  Git(FWork, ['switch', '-q', 'main']);
  St := RepoStatus(FWork, '');
  AssertEquals('', St.Error);
  AssertEquals(1, Length(St.Unpushed));
  AssertEquals('keep', St.Unpushed[0].Name);
  AssertEquals(1, Length(St.Unshared));
  AssertEquals('wip', St.Unshared[0].Name);
  AssertEquals(1, St.Unshared[0].Count);
  AssertFalse(StatusClean(St));
end;

{ A new folder's files count one each. }
procedure TBatchTest.TestStatusUntrackedFolder;
var
  St: TGittanRepoStatus;
begin
  ForceDirectories(FWork);
  Git(FWork, ['init', '-q']);
  CommitFile('a.txt', 'a', 'first');
  ForceDirectories(IncludeTrailingPathDelimiter(FWork) + 'new');
  with TStringList.Create do
    try
      Text := 'n';
      SaveToFile(IncludeTrailingPathDelimiter(FWork) + 'new' + PathDelim + 'one.txt');
      SaveToFile(IncludeTrailingPathDelimiter(FWork) + 'new' + PathDelim + 'two.txt');
      SaveToFile(IncludeTrailingPathDelimiter(FWork) + 'top.txt');
    finally
      Free;
    end;
  St := RepoStatus(FWork, '');
  AssertEquals('', St.Error);
  AssertEquals(3, St.Untracked);
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

procedure TBatchTest.TestIdentity;
var
  Id: TGittanRepoIdentity;
begin
  MakeRepos;
  { The test run's global config (another test may have changed its
    name and e-mail), no signing. }
  Id := RepoIdentity(FWork, 'Work');
  AssertEquals('', Id.Error);
  AssertEquals('Work', Id.Caption);
  AssertEquals(GitOut(FWork, ['config', 'user.name']), Id.Name);
  AssertTrue(Id.Email <> '');
  AssertEquals(GitOut(FWork, ['config', 'user.email']), Id.Email);
  AssertEquals('global', Id.EmailScope);
  AssertFalse(Id.Sign);
  AssertEquals('openpgp', Id.SignFormat);
  { origin is a local path: no owner. }
  AssertEquals('', Id.Owner);
  AssertFalse(Id.Odd);
  Id := RepoIdentity(IncludeTrailingPathDelimiter(FDir) + 'missing', '');
  AssertTrue(Id.Error <> '');
  AssertEquals('missing', Id.Caption);
  Id := RepoIdentity(FDir, '');
  AssertTrue(Id.Error <> '');
end;

procedure TBatchTest.TestIdentityLocal;
var
  Id: TGittanRepoIdentity;
begin
  ForceDirectories(FWork);
  Git(FWork, ['init', '-q']);
  Git(FWork, ['config', 'user.name', 'Me At Work']);
  Git(FWork, ['config', 'user.email', 'me@work.example']);
  Git(FWork, ['config', 'commit.gpgsign', 'yes']);
  Git(FWork, ['config', 'gpg.format', 'ssh']);
  Git(FWork, ['config', 'user.signingkey', '~/.ssh/id_ed25519.pub']);
  Git(FWork, ['remote', 'add', 'upstream', 'git@github.com:acme/tool.git']);
  Id := RepoIdentity(FWork, '');
  AssertEquals('', Id.Error);
  AssertEquals('Me At Work', Id.Name);
  AssertEquals('me@work.example', Id.Email);
  AssertEquals('local', Id.EmailScope);
  AssertTrue(Id.Sign);
  AssertEquals('ssh', Id.SignFormat);
  AssertEquals('~/.ssh/id_ed25519.pub', Id.SigningKey);
  { No origin: the first remote. }
  AssertEquals('github.com/acme', Id.Owner);
  Git(FWork, ['remote', 'add', 'origin', 'https://gitlab.com/group/sub/tool.git']);
  AssertEquals('gitlab.com/group/sub', RepoIdentity(FWork, '').Owner);
end;

procedure TBatchTest.TestRemoteOwner;
begin
  AssertEquals('github.com/acme', RemoteOwner('git@github.com:acme/tool.git'));
  AssertEquals('github.com/acme', RemoteOwner('https://github.com/acme/tool'));
  AssertEquals('github.com/acme', RemoteOwner('ssh://git@GitHub.com:22/acme/tool.git'));
  AssertEquals('gitlab.com/a/b', RemoteOwner('https://gitlab.com/a/b/tool.git'));
  AssertEquals('example.com', RemoteOwner('git@example.com:tool.git'));
  AssertEquals('', RemoteOwner('/srv/git/tool.git'));
  AssertEquals('', RemoteOwner('file:///srv/git/tool.git'));
  AssertEquals('', RemoteOwner(''));
end;

procedure TBatchTest.TestRemoteOwnerSshAlias;
const
  Config = 'Host github-work' + LineEnding + '  HostName github.com' + LineEnding +
    '  IdentityFile ~/.ssh/work' + LineEnding;
begin
  AssertEquals('github.com/acme', RemoteOwner('github-work:acme/x.git', Config));
  AssertEquals('github.com/acme', RemoteOwner('git@github-work:acme/x.git', Config));
  AssertEquals('github.com/acme', RemoteOwner('ssh://git@github-work/acme/x', Config));
  AssertEquals('github.com/acme', RemoteOwner('git@github.com:acme/x.git', Config));
  { Not over ssh: the host as it is. }
  AssertEquals('github-work/acme', RemoteOwner('https://github-work/acme/x', Config));
  AssertEquals('github-work/acme', RemoteOwner('github-work:acme/x.git'));
end;

procedure TBatchTest.TestSameIdentity;
var
  A, B: TGittanRepoIdentity;
begin
  A := Default(TGittanRepoIdentity);
  A.Name := 'Me';
  A.Email := 'me@example.com';
  A.SignFormat := 'openpgp';
  B := A;
  B.Email := 'ME@example.com';
  B.SigningKey := 'unused while not signing';
  AssertTrue(SameIdentity(A, B));
  B.Sign := True;
  AssertFalse(SameIdentity(A, B));
  A.Sign := True;
  AssertFalse(SameIdentity(A, B));
  A.SigningKey := B.SigningKey;
  AssertTrue(SameIdentity(A, B));
  B.Name := 'Someone';
  AssertFalse(SameIdentity(A, B));
  B := A;
  B.Error := 'gone';
  AssertFalse(SameIdentity(A, B));
end;

procedure TBatchTest.TestOddIdentities;
var
  Ids: TGittanRepoIdentities;

  procedure Add(const AOwner, AEmail: string; const AError: string = '');
  begin
    SetLength(Ids, Length(Ids) + 1);
    Ids[High(Ids)] := Default(TGittanRepoIdentity);
    Ids[High(Ids)].Owner := AOwner;
    Ids[High(Ids)].Email := AEmail;
    Ids[High(Ids)].Error := AError;
    Ids[High(Ids)].Odd := True;
  end;

begin
  Ids := nil;
  { acme: two on the work address, one private, which stands out. }
  Add('github.com/acme', 'me@acme.example');
  Add('github.com/me', 'me@home.example');
  Add('github.com/ACME', 'Me@Acme.example');
  Add('github.com/acme', 'me@home.example');
  { me: one address; no owner; could not be read. }
  Add('github.com/me', 'me@home.example');
  Add('', 'other@example.com');
  Add('github.com/acme', 'x@y.example', 'broken');
  { tie: one each, both marked. }
  Add('gitlab.com/t', 'a@example.com');
  Add('gitlab.com/t', 'b@example.com');
  MarkOddIdentities(Ids);
  AssertFalse(Ids[0].Odd);
  AssertFalse(Ids[1].Odd);
  AssertFalse(Ids[2].Odd);
  AssertTrue(Ids[3].Odd);
  AssertFalse(Ids[4].Odd);
  AssertFalse(Ids[5].Odd);
  AssertFalse(Ids[6].Odd);
  AssertTrue(Ids[7].Odd);
  AssertTrue(Ids[8].Odd);
end;

procedure TBatchTest.TestIdentityJob;
var
  Job: TGittanIdentityJob;
begin
  MakeRepos;
  Job := TGittanIdentityJob.Create([FWork, IncludeTrailingPathDelimiter(FDir) + 'missing'],
    ['Work', '']);
  try
    Job.Start;
    Job.WaitFor;
    AssertEquals(2, Job.Finished);
    AssertEquals('Work', Job.Repos[0].Caption);
    AssertEquals(GitOut(FWork, ['config', 'user.email']), Job.Repos[0].Email);
    AssertTrue(Job.Repos[1].Error <> '');
    AssertEquals('missing', Job.Repos[1].Caption);
  finally
    Job.Free;
  end;
end;

{ A bare remote with main and trunk, HEAD on main, and FWork a clone of
  it, whose origin/HEAD is then main. }
procedure TBatchTest.MakeClone;
var
  Seed: string;
begin
  Seed := IncludeTrailingPathDelimiter(FDir) + 'seed';
  ForceDirectories(Seed);
  ForceDirectories(FRemote);
  Git(FRemote, ['init', '-q', '--bare']);
  Git(FRemote, ['symbolic-ref', 'HEAD', 'refs/heads/main']);
  Git(Seed, ['init', '-q']);
  Git(Seed, ['symbolic-ref', 'HEAD', 'refs/heads/main']);
  with TStringList.Create do
    try
      Text := 'a';
      SaveToFile(IncludeTrailingPathDelimiter(Seed) + 'a.txt');
    finally
      Free;
    end;
  Git(Seed, ['add', 'a.txt']);
  Git(Seed, ['commit', '-q', '-m', 'first']);
  Git(Seed, ['branch', 'trunk']);
  Git(Seed, ['push', '-q', FRemote, 'main', 'trunk']);
  Git(FDir, ['clone', '-q', FRemote, FWork]);
end;

function FindTask(const ARepo: TGittanMaintRepo; ATask: TGittanMaintTask): integer;
begin
  for Result := 0 to High(ARepo.Items) do
    if ARepo.Items[Result].Task = ATask then
      Exit;
  Result := -1;
end;

procedure TBatchTest.TestMaintSetHead;
var
  Repo: TGittanMaintRepo;
  i: integer;
begin
  MakeClone;
  Repo := ScanMaintenance(FWork, '');
  AssertEquals('', Repo.Error);
  AssertEquals('', Repo.RemoteError);
  AssertEquals('work', Repo.Caption);
  AssertEquals(-1, FindTask(Repo, mtSetHead));
  { The default branch is renamed on the forge. }
  Git(FRemote, ['symbolic-ref', 'HEAD', 'refs/heads/trunk']);
  Repo := ScanMaintenance(FWork, '');
  i := FindTask(Repo, mtSetHead);
  AssertTrue(i >= 0);
  AssertEquals('origin', Repo.Items[i].Remote);
  AssertEquals('main', Repo.Items[i].Have);
  AssertEquals('trunk', Repo.Items[i].Want);
  RunMaintTask(FWork, Repo.Items[i]);
  AssertEquals('', Repo.Items[i].Error);
  AssertTrue(Repo.Items[i].Done);
  AssertEquals('refs/remotes/origin/trunk', GitOut(FWork, ['symbolic-ref',
    'refs/remotes/origin/HEAD']));
  AssertEquals(-1, FindTask(ScanMaintenance(FWork, ''), mtSetHead));
  { Not set at all. }
  Git(FWork, ['remote', 'set-head', 'origin', '--delete']);
  i := FindTask(ScanMaintenance(FWork, ''), mtSetHead);
  AssertTrue(i >= 0);
  AssertEquals('', ScanMaintenance(FWork, '').Items[i].Have);
  { Not asked without ACheckRemote. }
  AssertEquals(-1, FindTask(ScanMaintenance(FWork, '', False), mtSetHead));
end;

{ The remote's HEAD moved to a branch made there after the clone, which
  set-head --auto alone refuses (no refs/remotes/origin/next yet). }
procedure TBatchTest.TestMaintSetHeadUnfetched;
var
  Repo: TGittanMaintRepo;
  i: integer;
begin
  MakeClone;
  Git(FRemote, ['branch', 'next', 'main']);
  Git(FRemote, ['symbolic-ref', 'HEAD', 'refs/heads/next']);
  Repo := ScanMaintenance(FWork, '');
  i := FindTask(Repo, mtSetHead);
  AssertTrue(i >= 0);
  AssertEquals('next', Repo.Items[i].Want);
  RunMaintTask(FWork, Repo.Items[i]);
  AssertEquals('', Repo.Items[i].Error);
  AssertTrue(Repo.Items[i].Done);
  AssertEquals('refs/remotes/origin/next', GitOut(FWork, ['symbolic-ref',
    'refs/remotes/origin/HEAD']));
end;

procedure TBatchTest.TestMaintWorktrees;
var
  Repo: TGittanMaintRepo;
  Tree: string;
  i: integer;
begin
  MakeClone;
  Tree := IncludeTrailingPathDelimiter(FDir) + 'tree';
  Git(FWork, ['worktree', 'add', '-q', Tree, 'trunk']);
  AssertEquals(-1, FindTask(ScanMaintenance(FWork, '', False), mtPruneWorktrees));
  RemoveTree(Tree);
  Repo := ScanMaintenance(FWork, '', False);
  i := FindTask(Repo, mtPruneWorktrees);
  AssertTrue(i >= 0);
  AssertEquals(1, Length(Repo.Items[i].Worktrees));
  AssertEquals('tree', ExtractFileName(ExcludeTrailingPathDelimiter(Repo.Items[i].Worktrees[0])));
  RunMaintTask(FWork, Repo.Items[i]);
  AssertTrue(Repo.Items[i].Done);
  AssertEquals(-1, FindTask(ScanMaintenance(FWork, '', False), mtPruneWorktrees));
end;

procedure TBatchTest.TestMaintPack;

  { Text zlib cannot shrink much, so the loose objects come to some KiB:
    on Windows count-objects adds up the files' sizes, not disk blocks,
    and two one-letter files came to 0 KiB there. }
  function Noise(ASeed: cardinal): string;
  var
    k: integer;
  begin
    SetLength(Result, 8192);
    for k := 1 to Length(Result) do
    begin
      ASeed := ASeed * 1103515245 + 12345;
      Result[k] := Chr(33 + (ASeed shr 16) mod 90);
    end;
  end;

var
  Repo: TGittanMaintRepo;
  i: integer;
begin
  ForceDirectories(FWork);
  Git(FWork, ['init', '-q']);
  CommitFile('a.txt', Noise(1), 'first');
  CommitFile('b.txt', Noise(2), 'second');
  { Under the limits: nothing to pack. }
  AssertEquals(-1, FindTask(ScanMaintenance(FWork, '', False), mtPack));
  Repo := ScanMaintenance(FWork, '', False, 1, 1);
  i := FindTask(Repo, mtPack);
  AssertTrue(i >= 0);
  AssertTrue(Repo.Items[i].Loose > 0);
  AssertTrue(Repo.Items[i].SizeKiB > 0);
  RunMaintTask(FWork, Repo.Items[i]);
  AssertEquals('', Repo.Items[i].Error);
  AssertTrue(Repo.Items[i].Done);
  AssertTrue(Repo.Items[i].Loose > 0);
  AssertTrue(Repo.Items[i].AfterKiB > 0);
  AssertEquals('count: 0', GitOut(FWork, ['count-objects', '-v']).Split([#10])[0]);
end;

procedure TBatchTest.TestMaintRemoteError;
var
  Repo: TGittanMaintRepo;
begin
  ForceDirectories(FWork);
  Git(FWork, ['init', '-q']);
  Git(FWork, ['remote', 'add', 'origin', IncludeTrailingPathDelimiter(FDir) + 'nowhere.git']);
  Repo := ScanMaintenance(FWork, '');
  AssertEquals('', Repo.Error);
  AssertTrue(Repo.RemoteError <> '');
  AssertEquals(0, Length(Repo.Items));
end;

procedure TBatchTest.TestMaintNotARepo;
begin
  AssertTrue(ScanMaintenance(IncludeTrailingPathDelimiter(FDir) + 'missing', '').Error <> '');
  AssertTrue(ScanMaintenance(FDir, '').Error <> '');
end;

procedure TBatchTest.TestMaintJobs;
var
  Scan: TGittanMaintScanJob;
  RunJob: TGittanMaintRunJob;
  Refs: TGittanMaintRefs;
  i: integer;
begin
  MakeClone;
  Git(FRemote, ['symbolic-ref', 'HEAD', 'refs/heads/trunk']);
  Scan := TGittanMaintScanJob.Create([FWork, IncludeTrailingPathDelimiter(FDir) + 'missing'],
    ['Work', '']);
  try
    Scan.Start;
    Scan.WaitFor;
    AssertEquals(2, Scan.Finished);
    AssertEquals('Work', Scan.Repos[0].Caption);
    i := FindTask(Scan.Repos[0], mtSetHead);
    AssertTrue(i >= 0);
    AssertTrue(Scan.Repos[1].Error <> '');
    SetLength(Refs, 1);
    Refs[0].Path := FWork;
    Refs[0].Item := Scan.Repos[0].Items[i];
  finally
    Scan.Free;
  end;
  RunJob := TGittanMaintRunJob.Create(Refs);
  try
    RunJob.Start;
    RunJob.WaitFor;
    AssertEquals(1, RunJob.Finished);
    AssertTrue(RunJob.Refs[0].Item.Done);
  finally
    RunJob.Free;
  end;
end;

initialization
  RegisterTest(TBatchTest);
end.
