unit gittan.batch;

{** Batch operations: work done in several repositories at once, which
  the Batch tab of the forge view (uforge, gittan.batchpage) runs on the
  repositories the user picks from those the welcome view shows.

  BatchRows gives those repositories as the tab lists them: the
  repository list's folders and repositories in its order, every folder
  open, then the recent repositories the list does not have under a
  heading of their own.

  The overview (RepoStatus, TGittanStatusJob) reads, without fetching or
  changing anything, what is left undone in a repository: the branch,
  what git is in the middle of, the changed and untracked files, the
  stashes, the branches ahead of their upstream and the branches with
  commits on no remote, or that it has no remote at all.

  The identity check (RepoIdentity, TGittanIdentityJob) reads who a
  repository commits as and whether it signs, and the host and owner of
  its remote; MarkOddIdentities marks the repositories whose e-mail
  differs from the one the others of the same owner use, the way a work
  repository committed to with a private address stands out.

  Maintenance (ScanMaintenance, TGittanMaintScanJob) finds what is worth
  tidying in a repository: its remote's HEAD as the remote has it now
  against the local refs/remotes/<remote>/HEAD (a default branch
  renamed on the forge leaves the old one), worktrees whose folder is
  gone, and loose objects or packs enough to pack; RunMaintTask and
  TGittanMaintRunJob do it (`git remote set-head --auto`, `git worktree
  prune`, `git gc`).

  The last operation deletes the local branches whose branch on the
  remote is gone. TGittanGoneScanJob fetches, with --prune, the remotes
  each repository's local branches track (skipFetchAll or not) and
  lists its local branches whose upstream is gone
  (TGittanRepo.GoneBranches), the current one left out, each with how
  far its work reached the default branch (GoneMergeState): merged,
  squashed into it, or not merged. TGittanGoneDeleteJob deletes the
  branches it is given (`git branch -D`, since the user picked each),
  and tells per branch whether it went and the commit it was at. Both
  run in a thread and fill an array sized before they start, a
  repository or a branch at a time, so the owner can show what is done
  while the rest runs (Finished, OnProgress). Nothing here needs the
  LCL; tested in tests/testbatch.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.git, gittan.job, gittan.repolist, gittan.forge, gittan.worktrees,
  gittan.repoinfo;

type
  {** A row of the Batch tab's repositories: a folder of the repository
    list (or the heading of the recent ones, with an empty Path), or a
    repository, by its root; Caption is what is shown and Depth how far
    it is indented, 0 at the top. }
  TGittanBatchRow = record
    IsFolder: boolean;
    Caption: string;
    Path: string;
    Depth: integer;
  end;
  TGittanBatchRows = array of TGittanBatchRow;

  {** How far a gone branch's work reached the default branch: its tip
    is in it or in HEAD (gmMerged), a squash of its changes since it
    left it is (gmSquashed, what a squash merge on the forge leaves), or
    neither (gmNotMerged, deleting it may lose work). }
  TGittanGoneMerge = (gmMerged, gmSquashed, gmNotMerged);

  {** A local branch whose upstream is gone, and what a deletion did:
    Deleted with the commit it was at in Was, or Error with git's
    reason. }
  TGittanGoneBranch = record
    Name: string;
    Merge: TGittanGoneMerge;
    Deleted: boolean;
    Was: string;
    Error: string;
  end;
  TGittanGoneBranches = array of TGittanGoneBranch;

  {** What a scan found in a repository: its gone branches; FetchError
    when the fetch failed (the branches are then as of the last fetch);
    Error when the repository could not be read at all. }
  TGittanGoneRepo = record
    Path: string;
    Caption: string;
    Branches: TGittanGoneBranches;
    FetchError: string;
    Error: string;
  end;
  TGittanGoneRepos = array of TGittanGoneRepo;

  {** A local branch and a count of commits: how far it is ahead of its
    upstream, or how many of its commits are on no remote. }
  TGittanBranchCount = record
    Name: string;
    Count: integer;
  end;
  TGittanBranchCounts = array of TGittanBranchCount;

  {** What is left undone in a repository (RepoStatus): the branch
    checked out ('' when HEAD is detached, Detached then), what git is
    in the middle of (TGittanRepo.Operation), the tracked files changed
    (staged or not, conflicts too) and the untracked ones, the stashes,
    the branches ahead of their upstream (Unpushed), the branches with
    no upstream that have commits on no remote (Unshared), whether it
    has no remote at all (NoRemote; Unshared is then empty, since every
    commit is on none), and Error when it, or a part of it (the
    stashes, the branches), could not be read. A branch whose upstream
    is gone counts as one with no upstream. }
  TGittanRepoStatus = record
    Path: string;
    Caption: string;
    Branch: string;
    Detached: boolean;
    Operation: string;
    Changed, Untracked, Stashes: integer;
    Unpushed: TGittanBranchCounts;
    Unshared: TGittanBranchCounts;
    NoRemote: boolean;
    Error: string;
  end;
  TGittanRepoStatuses = array of TGittanRepoStatus;

  {** Who a repository commits as (RepoIdentity): user.name and
    user.email as git resolves them, where the e-mail is set
    (EmailScope: local, worktree, global, system or command; '' when
    nowhere), whether commits are signed (commit.gpgsign) and with what
    (SignFormat, gpg.format, openpgp when unset; SigningKey,
    user.signingkey), the host and owner of its remote (origin, else
    the first) as "github.com/acme" ('' when it has none or it is a
    local path), Odd when the other repositories of that owner commit
    under another e-mail (MarkOddIdentities), and Error when it could
    not be read. }
  TGittanRepoIdentity = record
    Path: string;
    Caption: string;
    Name: string;
    Email: string;
    EmailScope: string;
    Sign: boolean;
    SignFormat: string;
    SigningKey: string;
    Owner: string;
    Odd: boolean;
    Error: string;
  end;
  TGittanRepoIdentities = array of TGittanRepoIdentity;

  {** A maintenance task: point the remote's HEAD where the remote's
    points (mtSetHead), forget the worktrees whose folder is gone
    (mtPruneWorktrees), pack the objects (mtPack). }
  TGittanMaintTask = (mtSetHead, mtPruneWorktrees, mtPack);

  {** A task a repository needs, with what was found: for mtSetHead the
    remote and the branch its HEAD points at locally (Have, '' when it
    is not set) and on the remote (Want); for mtPruneWorktrees the
    folders gone; for mtPack the loose objects, the packs and the size
    in KiB (after a run, the size then in AfterKiB). Done or Error once
    it ran. }
  TGittanMaintItem = record
    Task: TGittanMaintTask;
    Remote: string;
    Have: string;
    Want: string;
    Worktrees: TStringArray;
    Loose, Packs: integer;
    SizeKiB, AfterKiB: int64;
    Done: boolean;
    Error: string;
  end;
  TGittanMaintItems = array of TGittanMaintItem;

  {** What a maintenance scan found in a repository: the tasks it needs;
    RemoteError when the remote could not be asked; Error when the
    repository, or a part the scan reads (its worktrees, its objects),
    could not be read. }
  TGittanMaintRepo = record
    Path: string;
    Caption: string;
    Items: TGittanMaintItems;
    RemoteError: string;
    Error: string;
  end;
  TGittanMaintRepos = array of TGittanMaintRepo;

  {** A task to run: the repository's root and the item the scan gave. }
  TGittanMaintRef = record
    Path: string;
    Item: TGittanMaintItem;
  end;
  TGittanMaintRefs = array of TGittanMaintRef;

  {** A branch to delete: the repository's root and the branch. }
  TGittanBranchRef = record
    Path: string;
    Branch: string;
  end;
  TGittanBranchRefs = array of TGittanBranchRef;

  { TGittanBatchJob }

  {** The base of the batch jobs: Count items, done in order, Finished of
    them done so far; OnProgress after each, in the main thread. }
  TGittanBatchJob = class(TGittanJob)
  private
    FFinished: integer;
    FOnProgress: TNotifyEvent;
    procedure NotifyProgress;
  protected
    {** Counts an item done and tells the main thread. }
    procedure ItemDone;
    {** Whether the job was told to end; what a git that goes to the
      network asks as it runs, so a stalled connection does not hold
      the job. }
    function Cancelled: boolean;
    procedure Detach; override;
  public
    {** The items done, whose results may be read now. }
    function Finished: integer;
    property OnProgress: TNotifyEvent read FOnProgress write FOnProgress;
  end;

  { TGittanGoneScanJob }

  {** Fetches each repository (with Fetch, else not) and finds its gone
    branches; Repos holds what it found, a repository at a time. }
  TGittanGoneScanJob = class(TGittanBatchJob)
  private
    FRepos: TGittanGoneRepos;
    FFetch: boolean;
  protected
    procedure Execute; override;
  public
    {** A job for the repositories at APaths, captioned ACaptions (the
      path's folder name where a caption is missing). }
    constructor Create(const APaths, ACaptions: array of string; AFetch: boolean = True);
    property Repos: TGittanGoneRepos read FRepos;
  end;

  { TGittanStatusJob }

  {** Reads each repository's status (RepoStatus); Repos holds them, a
    repository at a time. }
  TGittanStatusJob = class(TGittanBatchJob)
  private
    FRepos: TGittanRepoStatuses;
  protected
    procedure Execute; override;
  public
    {** A job for the repositories at APaths, captioned ACaptions. }
    constructor Create(const APaths, ACaptions: array of string);
    property Repos: TGittanRepoStatuses read FRepos;
  end;

  { TGittanIdentityJob }

  {** Reads who each repository commits as (RepoIdentity); Repos holds
    them, a repository at a time. }
  TGittanIdentityJob = class(TGittanBatchJob)
  private
    FRepos: TGittanRepoIdentities;
  protected
    procedure Execute; override;
  public
    {** A job for the repositories at APaths, captioned ACaptions. }
    constructor Create(const APaths, ACaptions: array of string);
    property Repos: TGittanRepoIdentities read FRepos;
  end;

  { TGittanMaintScanJob }

  {** Finds what each repository needs (ScanMaintenance); Repos holds
    it, a repository at a time. }
  TGittanMaintScanJob = class(TGittanBatchJob)
  private
    FRepos: TGittanMaintRepos;
  protected
    procedure Execute; override;
  public
    {** A job for the repositories at APaths, captioned ACaptions. }
    constructor Create(const APaths, ACaptions: array of string);
    property Repos: TGittanMaintRepos read FRepos;
  end;

  { TGittanMaintRunJob }

  {** Runs the tasks given (RunMaintTask), in order; Refs holds each with
    Done or Error, a task at a time. Never given up halfway. }
  TGittanMaintRunJob = class(TGittanBatchJob)
  private
    FRefs: TGittanMaintRefs;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARefs: TGittanMaintRefs);
    property Refs: TGittanMaintRefs read FRefs;
  end;

  { TGittanGoneDeleteJob }

  {** Deletes the branches given, each with `git branch -D`; Branches
    holds per branch whether it went. }
  TGittanGoneDeleteJob = class(TGittanBatchJob)
  private
    FRefs: TGittanBranchRefs;
    FResults: TGittanGoneBranches;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARefs: TGittanBranchRefs);
    property Refs: TGittanBranchRefs read FRefs;
    {** Per branch of Refs, in its order: Deleted and Was, or Error. }
    property Branches: TGittanGoneBranches read FResults;
  end;

{** The repositories the Batch tab offers: AList's entries in its order,
  every folder open, then the recent repositories (ARecent, roots) that
  AList does not have, under a folder row ARecentCaption, one deeper. No
  recent heading when every recent one is in the list. }
function BatchRows(AList: TGittanRepoList; ARecent: TStrings;
  const ARecentCaption: string): TGittanBatchRows;

{** The repositories in the folder row AIndex of ARows: the rows after it
  that are deeper, by their paths; the row's own path when it is a
  repository. }
function BatchRowRepos(const ARows: TGittanBatchRows; AIndex: integer): TStringArray;

{** How far the work of the local branch ABranch of ARepo reached
  ADefault (a ref such as origin/main, '' for none): merged when its tip
  is in ADefault or in HEAD; squashed when ADefault has a commit with
  the same changes as all the branch made since it left it (a commit
  made for the comparison, reachable from nothing, `git cherry`);
  else not merged. }
function GoneMergeState(ARepo: TGittanRepo; const ABranch, ADefault: string): TGittanGoneMerge;

{** What is left undone in the repository at APath, captioned ACaption
  (its folder's name when empty), read with git and nothing fetched. }
function RepoStatus(const APath, ACaption: string): TGittanRepoStatus;

{** Whether AStatus has nothing to say: on a branch, nothing in progress,
  nothing changed, stashed, unpushed or unshared, a remote, no error. }
function StatusClean(const AStatus: TGittanRepoStatus): boolean;

{** Who the repository at APath commits as, captioned ACaption (its
  folder's name when empty); Odd is left False. }
function RepoIdentity(const APath, ACaption: string): TGittanRepoIdentity;

{** "github.com/acme" of a remote's URL such as git@github.com:acme/r.git
  (the group path on a forge with subgroups, "gitlab.com/a/b" of
  gitlab.com/a/b/r); the host alone when the path has one part; empty
  for a local path. An ssh URL's host is the one ASshConfig (an
  ssh_config's text, SshHostName) connects to, so github-work:acme/r
  with a Host github-work block naming github.com is github.com/acme. }
function RemoteOwner(const AUrl: string; const ASshConfig: string = ''): string;

{** Whether A and B commit as the same: name, e-mail (in any case) and
  signing alike; never for one that could not be read. }
function SameIdentity(const A, B: TGittanRepoIdentity): boolean;

{** Marks Odd each repository of AIds whose e-mail differs from the one
  most of the others of its owner use; when no e-mail is used most, all
  of that owner's repositories. An owner whose repositories all use one
  e-mail, and a repository with no owner or an Error, are not marked. }
procedure MarkOddIdentities(var AIds: TGittanRepoIdentities);

const
  {** Loose objects, or packs, from which ScanMaintenance offers to pack. }
  MaintLooseLimit = 1000;
  MaintPackLimit = 10;
  {** The seconds ssh waits for a connection in what the batch jobs run
    against a remote (ConnectTimeout), unless the user runs ssh their
    own way. }
  BatchConnectTimeout = 20;

{** What the repository at APath needs, captioned ACaption: mtSetHead
  when its remote (origin, else the first) has a HEAD that the local
  refs/remotes/<remote>/HEAD does not point at (`git ls-remote
  --symref`, the one thing here that goes to the network), when
  ACheckRemote; mtPruneWorktrees when worktrees are prunable;
  mtPack from ALooseLimit loose objects or APackLimit packs. ACancel,
  when given, is asked as ls-remote runs, and True ends it. }
function ScanMaintenance(const APath, ACaption: string; ACheckRemote: boolean = True;
  ALooseLimit: integer = MaintLooseLimit; APackLimit: integer = MaintPackLimit;
  ACancel: TGittanCancelEvent = nil): TGittanMaintRepo;

{** Runs AItem's task in the repository at APath: Done, else Error with
  git's reason; for mtPack the size then in AfterKiB (Loose, Packs and
  SizeKiB stay as they were found). mtSetHead fetches the branch Want
  of the remote first, which set-head needs as a remote-tracking ref. }
procedure RunMaintTask(const APath: string; var AItem: TGittanMaintItem);

{** Scans the repository at APath as TGittanGoneScanJob does: with
  AFetch, `git fetch --prune --multiple` of the remotes its local
  branches track, asking ACancel as it runs. }
function ScanGoneRepo(const APath, ACaption: string; AFetch: boolean;
  ACancel: TGittanCancelEvent = nil): TGittanGoneRepo;

{** Deletes the local branch ABranch of the repository at APath (`git
  branch -D`): Deleted, with the commit it was at, or Error. }
function DeleteGoneBranch(const APath, ABranch: string): TGittanGoneBranch;

implementation

{ ---------------------------------------------------------------------------
  The rows
  --------------------------------------------------------------------------- }

function BatchRows(AList: TGittanRepoList; ARecent: TStrings;
  const ARecentCaption: string): TGittanBatchRows;
var
  n: integer;

  procedure Add(AIsFolder: boolean; const ACaption, APath: string; ADepth: integer);
  begin
    if n > High(Result) then
      SetLength(Result, 2 * n + 8);
    Result[n].IsFolder := AIsFolder;
    Result[n].Caption := ACaption;
    Result[n].Path := APath;
    Result[n].Depth := ADepth;
    Inc(n);
  end;

  procedure AddEntries(AFolder: TGittanRepoEntry; ADepth: integer);
  var
    i: integer;
    Entry: TGittanRepoEntry;
  begin
    for i := 0 to AFolder.Count - 1 do
    begin
      Entry := AFolder[i];
      Add(Entry.IsFolder, Entry.Caption, Entry.Path, ADepth);
      if Entry.IsFolder then
        AddEntries(Entry, ADepth + 1);
    end;
  end;

var
  Path: string;
  Heading: boolean;
begin
  Result := nil;
  n := 0;
  if AList <> nil then
    AddEntries(AList.Root, 0);
  Heading := False;
  if ARecent <> nil then
    for Path in ARecent do
    begin
      if (Path = '') or ((AList <> nil) and (AList.Find(Path) <> nil)) then
        Continue;
      if not Heading then
      begin
        Add(True, ARecentCaption, '', 0);
        Heading := True;
      end;
      Add(False, ExtractFileName(ExcludeTrailingPathDelimiter(Path)),
        RepoListPath(Path), 1);
    end;
  SetLength(Result, n);
end;

function BatchRowRepos(const ARows: TGittanBatchRows; AIndex: integer): TStringArray;
var
  i, n: integer;
begin
  Result := nil;
  if (AIndex < 0) or (AIndex > High(ARows)) then
    Exit;
  if not ARows[AIndex].IsFolder then
  begin
    SetLength(Result, 1);
    Result[0] := ARows[AIndex].Path;
    Exit;
  end;
  SetLength(Result, Length(ARows));
  n := 0;
  i := AIndex + 1;
  while (i <= High(ARows)) and (ARows[i].Depth > ARows[AIndex].Depth) do
  begin
    if not ARows[i].IsFolder then
    begin
      Result[n] := ARows[i].Path;
      Inc(n);
    end;
    Inc(i);
  end;
  SetLength(Result, n);
end;

{ ---------------------------------------------------------------------------
  Gone branches
  --------------------------------------------------------------------------- }

function GitOut(const ADir: string; const AArgs: array of string; out AOutput: string): boolean;
var
  Err: string;
begin
  Result := RunGitIn(ADir, AArgs, AOutput, Err);
  AOutput := Trim(AOutput);
end;

{ RemoteEnvironmentIn with ssh's ConnectTimeout added to the batch mode
  Gittan sets; nothing changed when the user runs ssh their own way. }
function BatchRemoteEnv(const ADir: string): TStringArray;
var
  i: integer;
begin
  Result := RemoteEnvironmentIn(ADir);
  for i := 0 to High(Result) do
    if Copy(Result[i], 1, Length('GIT_SSH_COMMAND=')) = 'GIT_SSH_COMMAND=' then
      Result[i] := Result[i] + ' -o ConnectTimeout=' + IntToStr(BatchConnectTimeout);
end;

{ Fetches, with --prune, the remotes the local branches of the
  repository at ARoot track: not --all, which leaves out a remote with
  remote.<name>.skipFetchAll, whose gone branches would then not be
  seen. True with nothing to fetch. }
function FetchTracked(const ARoot: string; ACancel: TGittanCancelEvent;
  out AError: string): boolean;
var
  Output, Name: string;
  Remotes, Lines: TStringList;
  Args: array of string;
begin
  AError := '';
  Result := True;
  Remotes := TStringList.Create;
  Lines := TStringList.Create;
  try
    if not GitOut(ARoot, ['remote'], Output) then
      Exit;
    Remotes.Text := Output;
    { %(upstream:remotename) is '.' for a branch that tracks a local one. }
    if not GitOut(ARoot, ['for-each-ref', '--format=%(upstream:remotename)', 'refs/heads'],
      Output) then
      Exit;
    Lines.Text := Output;
    Args := ['fetch', '--prune', '--multiple'];
    for Name in Remotes do
      if (Name <> '') and (Lines.IndexOf(Name) >= 0) then
        Args := Concat(Args, [Name]);
    if Length(Args) = 3 then
      Exit;
    Result := RunGitEnv(ARoot, Args, BatchRemoteEnv(ARoot), Output, AError, '', nil, ACancel);
    if not Result and (AError = '') then
      AError := 'git fetch failed.';
  finally
    Lines.Free;
    Remotes.Free;
  end;
end;

function GoneMergeState(ARepo: TGittanRepo; const ABranch, ADefault: string): TGittanGoneMerge;
var
  Root, Base, Tree, Squash, Cherry: string;
begin
  Result := gmNotMerged;
  Root := ARepo.Root;
  if (Root = '') or (ABranch = '') then
    Exit;
  if ARepo.IsAncestor('refs/heads/' + ABranch, 'HEAD') or
    ((ADefault <> '') and ARepo.IsAncestor('refs/heads/' + ABranch, ADefault)) then
    Exit(gmMerged);
  if ADefault = '' then
    Exit;
  { The branch's changes since it left the default branch as one
    commit on the merge base, which git cherry finds in the default
    branch when a squash of them is there. }
  if not GitOut(Root, ['merge-base', ADefault, 'refs/heads/' + ABranch], Base) or
    (Base = '') then
    Exit;
  if not GitOut(Root, ['rev-parse', 'refs/heads/' + ABranch + '^{tree}'], Tree) or
    (Tree = '') then
    Exit;
  if not GitOut(Root, ['-c', 'user.name=Gittan', '-c', 'user.email=gittan@localhost',
    'commit-tree', Tree, '-p', Base, '-m', 'squash of ' + ABranch], Squash) or
    (Squash = '') then
    Exit;
  if GitOut(Root, ['cherry', ADefault, Squash], Cherry) and (Copy(Cherry, 1, 2) = '- ') then
    Result := gmSquashed;
end;

function ScanGoneRepo(const APath, ACaption: string; AFetch: boolean;
  ACancel: TGittanCancelEvent): TGittanGoneRepo;
var
  Repo: TGittanRepo;
  Names: TStringList;
  Current, DefaultRef, Err: string;
  i, n: integer;
begin
  Result := Default(TGittanGoneRepo);
  Result.Path := APath;
  Result.Caption := ACaption;
  if Result.Caption = '' then
    Result.Caption := ExtractFileName(ExcludeTrailingPathDelimiter(APath));
  if not DirectoryExists(APath) then
  begin
    Result.Error := 'The folder is not there.';
    Exit;
  end;
  Repo := TGittanRepo.Create;
  Names := TStringList.Create;
  try
    if not Repo.Open(APath) then
    begin
      Result.Error := Trim(Repo.Error);
      if Result.Error = '' then
        Result.Error := 'Not a git repository.';
      Exit;
    end;
    if AFetch and not FetchTracked(Repo.Root, ACancel, Err) then
      Result.FetchError := Trim(Err);
    if not Repo.GoneBranches(Names) then
    begin
      Result.Error := Trim(Repo.Error);
      Exit;
    end;
    Current := Repo.Branch;
    DefaultRef := Repo.DefaultBranch;
    SetLength(Result.Branches, Names.Count);
    n := 0;
    for i := 0 to Names.Count - 1 do
    begin
      if Names[i] = Current then
        Continue;
      Result.Branches[n] := Default(TGittanGoneBranch);
      Result.Branches[n].Name := Names[i];
      Result.Branches[n].Merge := GoneMergeState(Repo, Names[i], DefaultRef);
      Inc(n);
    end;
    SetLength(Result.Branches, n);
  finally
    Names.Free;
    Repo.Free;
  end;
end;

{ "ahead 2, behind 1", "ahead 3", "behind 1", "gone" or '': the ahead
  count, 0 when there is none. }
function AheadOf(const ATrack: string): integer;
var
  p, q: integer;
begin
  Result := 0;
  p := Pos('ahead ', ATrack);
  if p = 0 then
    Exit;
  Inc(p, Length('ahead '));
  q := p;
  while (q <= Length(ATrack)) and (ATrack[q] in ['0'..'9']) do
    Inc(q);
  Result := StrToIntDef(Copy(ATrack, p, q - p), 0);
end;

function RepoStatus(const APath, ACaption: string): TGittanRepoStatus;
var
  Repo: TGittanRepo;
  Lines: TStringList;
  Output, Line, Name, Upstream, Track, Count: string;
  Fields: TStringArray;
  Stashes: TGittanStashes;
  Ahead: integer;

  procedure AddCount(var AList: TGittanBranchCounts; const AName: string; ACount: integer);
  begin
    SetLength(AList, Length(AList) + 1);
    AList[High(AList)].Name := AName;
    AList[High(AList)].Count := ACount;
  end;

begin
  Result := Default(TGittanRepoStatus);
  Result.Path := APath;
  Result.Caption := ACaption;
  if Result.Caption = '' then
    Result.Caption := ExtractFileName(ExcludeTrailingPathDelimiter(APath));
  if not DirectoryExists(APath) then
  begin
    Result.Error := 'The folder is not there.';
    Exit;
  end;
  Repo := TGittanRepo.Create;
  Lines := TStringList.Create;
  try
    if not Repo.Open(APath) then
    begin
      Result.Error := Trim(Repo.Error);
      if Result.Error = '' then
        Result.Error := 'Not a git repository.';
      Exit;
    end;
    Result.Branch := Repo.Branch(Result.Detached);
    if Result.Detached then
      Result.Branch := '';
    Result.Operation := Repo.Operation;

    { A line a file, quoted when its name needs it, so a name with a
      line break is one line too. }
    { =all: each file of a new folder counts, as the page says files. }
    if not GitOut(APath, ['status', '--porcelain', '--untracked-files=all'], Output) then
    begin
      Result.Error := 'git status failed.';
      Exit;
    end;
    Lines.Text := Output;
    for Line in Lines do
      if Copy(Line, 1, 2) = '??' then
        Inc(Result.Untracked)
      else if Line <> '' then
        Inc(Result.Changed);

    if Repo.Stashes(Stashes) then
      Result.Stashes := Length(Stashes)
    else
      Result.Error := 'git stash list failed.';

    if GitOut(APath, ['remote'], Output) then
      Result.NoRemote := Output = ''
    else if Result.Error = '' then
      Result.Error := 'git remote failed.';
    { lstrip=2, not short: short gives heads/foo when a tag foo exists. }
    if not GitOut(APath, ['for-each-ref', '--format=%(refname:lstrip=2)%09%(upstream:short)%09' +
      '%(upstream:track,nobracket)', 'refs/heads'], Output) then
    begin
      if Result.Error = '' then
        Result.Error := 'git for-each-ref failed.';
    end
    else
    begin
      Lines.Text := Output;
      for Line in Lines do
      begin
        Fields := Line.Split([#9]);
        if Length(Fields) = 0 then
          Continue;
        Name := Fields[0];
        Upstream := '';
        Track := '';
        if Length(Fields) > 1 then
          Upstream := Fields[1];
        if Length(Fields) > 2 then
          Track := Fields[2];
        { An upstream deleted on the remote is no upstream: its commits
          are counted against every remote below. }
        if (Upstream <> '') and (Track <> 'gone') then
        begin
          Ahead := AheadOf(Track);
          if Ahead > 0 then
            AddCount(Result.Unpushed, Name, Ahead);
        end
        else if not Result.NoRemote then
        begin
          if not GitOut(APath, ['rev-list', '--count', 'refs/heads/' + Name,
            '--not', '--remotes'], Count) then
          begin
            if Result.Error = '' then
              Result.Error := 'git rev-list failed.';
          end
          else if StrToIntDef(Count, 0) > 0 then
            AddCount(Result.Unshared, Name, StrToIntDef(Count, 0));
        end;
      end;
    end;
  finally
    Lines.Free;
    Repo.Free;
  end;
end;

function StatusClean(const AStatus: TGittanRepoStatus): boolean;
begin
  Result := (AStatus.Error = '') and not AStatus.Detached and (AStatus.Operation = '') and
    (AStatus.Changed = 0) and (AStatus.Untracked = 0) and (AStatus.Stashes = 0) and
    (Length(AStatus.Unpushed) = 0) and (Length(AStatus.Unshared) = 0) and not AStatus.NoRemote;
end;

{ ---------------------------------------------------------------------------
  Identity
  --------------------------------------------------------------------------- }

function RemoteOwner(const AUrl: string; const ASshConfig: string): string;
var
  Host, RepoPath: string;
  p: integer;
begin
  Host := RemoteHost(AUrl);
  if Host = '' then
    Exit('');
  { Over ssh: host:path, or a scheme with ssh in it, as gittan.forge
    tells. }
  p := Pos('://', AUrl);
  if (ASshConfig <> '') and ((p = 0) or (Pos('ssh', LowerCase(Copy(AUrl, 1, p - 1))) > 0)) then
    Host := LowerCase(SshHostName(Host, ASshConfig));
  RepoPath := RemoteRepoPath(AUrl);
  p := LastDelimiter('/', RepoPath);
  if p > 1 then
    Result := Host + '/' + Copy(RepoPath, 1, p - 1)
  else
    Result := Host;
end;

function RepoIdentity(const APath, ACaption: string): TGittanRepoIdentity;
var
  Output, RemoteName: string;
  Lines: TStringList;
  p: integer;
begin
  Result := Default(TGittanRepoIdentity);
  Result.Path := APath;
  Result.Caption := ACaption;
  if Result.Caption = '' then
    Result.Caption := ExtractFileName(ExcludeTrailingPathDelimiter(APath));
  if not DirectoryExists(APath) then
  begin
    Result.Error := 'The folder is not there.';
    Exit;
  end;
  if not GitOut(APath, ['rev-parse', '--git-dir'], Output) then
  begin
    Result.Error := 'Not a git repository.';
    Exit;
  end;
  if GitOut(APath, ['config', '--get', 'user.name'], Output) then
    Result.Name := Output;
  { --show-scope since git 2.26: "local<TAB>me@example.com". }
  if GitOut(APath, ['config', '--show-scope', '--get', 'user.email'], Output) then
  begin
    p := Pos(#9, Output);
    if p > 0 then
    begin
      Result.EmailScope := Copy(Output, 1, p - 1);
      Result.Email := Copy(Output, p + 1, MaxInt);
    end
    else
      Result.Email := Output;
  end
  else if GitOut(APath, ['config', '--get', 'user.email'], Output) then
    Result.Email := Output;
  Result.Sign := GitOut(APath, ['config', '--type=bool', '--get', 'commit.gpgsign'], Output) and
    (Output = 'true');
  if not GitOut(APath, ['config', '--get', 'gpg.format'], Result.SignFormat) or
    (Result.SignFormat = '') then
    Result.SignFormat := 'openpgp';
  if not GitOut(APath, ['config', '--get', 'user.signingkey'], Result.SigningKey) then
    Result.SigningKey := '';

  { origin, else the first remote. }
  if not GitOut(APath, ['remote', 'get-url', 'origin'], Output) then
  begin
    Output := '';
    if GitOut(APath, ['remote'], RemoteName) and (RemoteName <> '') then
    begin
      Lines := TStringList.Create;
      try
        Lines.Text := RemoteName;
        if not GitOut(APath, ['remote', 'get-url', Lines[0]], Output) then
          Output := '';
      finally
        Lines.Free;
      end;
    end;
  end;
  Result.Owner := RemoteOwner(Output, UserSshConfig);
end;

function SameIdentity(const A, B: TGittanRepoIdentity): boolean;
begin
  Result := (A.Error = '') and (B.Error = '') and (A.Name = B.Name) and
    SameText(A.Email, B.Email) and (A.Sign = B.Sign) and
    (not A.Sign or ((A.SignFormat = B.SignFormat) and (A.SigningKey = B.SigningKey)));
end;

procedure MarkOddIdentities(var AIds: TGittanRepoIdentities);
var
  Seen: array of boolean;
  Emails: TStringList;
  i, j, k, Best, BestCount: integer;
  Tie: boolean;

  function Counts(AIndex: integer): boolean;
  begin
    Result := (AIds[AIndex].Error = '') and (AIds[AIndex].Owner <> '');
  end;

begin
  SetLength(Seen, Length(AIds));
  for i := 0 to High(AIds) do
    AIds[i].Odd := False;
  Emails := TStringList.Create;
  try
    for i := 0 to High(AIds) do
    begin
      if Seen[i] or not Counts(i) then
        Continue;
      { The e-mails of i's owner, each with how many use it. }
      Emails.Clear;
      for j := i to High(AIds) do
        if Counts(j) and SameText(AIds[j].Owner, AIds[i].Owner) then
        begin
          Seen[j] := True;
          k := Emails.IndexOf(LowerCase(AIds[j].Email));
          if k < 0 then
            k := Emails.Add(LowerCase(AIds[j].Email));
          Emails.Objects[k] := TObject(PtrInt(Emails.Objects[k]) + 1);
        end;
      if Emails.Count < 2 then
        Continue;
      Best := 0;
      BestCount := 0;
      Tie := False;
      for k := 0 to Emails.Count - 1 do
        if PtrInt(Emails.Objects[k]) > BestCount then
        begin
          Best := k;
          BestCount := PtrInt(Emails.Objects[k]);
          Tie := False;
        end
        else if PtrInt(Emails.Objects[k]) = BestCount then
          Tie := True;
      for j := i to High(AIds) do
        if Counts(j) and SameText(AIds[j].Owner, AIds[i].Owner) then
          AIds[j].Odd := Tie or (LowerCase(AIds[j].Email) <> Emails[Best]);
    end;
  finally
    Emails.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Maintenance
  --------------------------------------------------------------------------- }

{ The loose objects, packs and size in KiB of `git count-objects -v`. }
function ReadObjects(const APath: string; out ALoose, APacks: integer; out AKiB: int64): boolean;
var
  Output: string;
  Lines: TStringList;
  Line: string;
begin
  ALoose := 0;
  APacks := 0;
  AKiB := 0;
  Result := GitOut(APath, ['count-objects', '-v'], Output);
  if not Result then
    Exit;
  AKiB := ParseCountObjects(Output);
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for Line in Lines do
      if Copy(Line, 1, 7) = 'count: ' then
        ALoose := StrToIntDef(Trim(Copy(Line, 8, MaxInt)), 0)
      else if Copy(Line, 1, 7) = 'packs: ' then
        APacks := StrToIntDef(Trim(Copy(Line, 8, MaxInt)), 0);
  finally
    Lines.Free;
  end;
end;

{ The branch the remote's HEAD names in `git ls-remote --symref` output
  ("ref: refs/heads/main<TAB>HEAD"), '' when none. }
function SymrefHead(const AOutput: string): string;
var
  Lines: TStringList;
  Line: string;
  p: integer;
begin
  Result := '';
  Lines := TStringList.Create;
  try
    Lines.Text := AOutput;
    for Line in Lines do
      if Copy(Line, 1, 16) = 'ref: refs/heads/' then
      begin
        p := Pos(#9, Line);
        if p = 0 then
          p := Length(Line) + 1;
        Exit(Copy(Line, 17, p - 17));
      end;
  finally
    Lines.Free;
  end;
end;

function ScanMaintenance(const APath, ACaption: string; ACheckRemote: boolean;
  ALooseLimit: integer; APackLimit: integer; ACancel: TGittanCancelEvent): TGittanMaintRepo;
var
  Output, Err, Remote, Root: string;
  Lines: TStringList;
  Item: TGittanMaintItem;
  Trees: TGittanWorktrees;
  i: integer;

  procedure Add(const AItem: TGittanMaintItem);
  begin
    SetLength(Result.Items, Length(Result.Items) + 1);
    Result.Items[High(Result.Items)] := AItem;
  end;

begin
  Result := Default(TGittanMaintRepo);
  Result.Path := APath;
  Result.Caption := ACaption;
  if Result.Caption = '' then
    Result.Caption := ExtractFileName(ExcludeTrailingPathDelimiter(APath));
  if not DirectoryExists(APath) then
  begin
    Result.Error := 'The folder is not there.';
    Exit;
  end;
  if not GitOut(APath, ['rev-parse', '--show-toplevel'], Root) then
  begin
    Result.Error := 'Not a git repository.';
    Exit;
  end;

  { The remote's HEAD: origin, else the first remote. }
  if ACheckRemote and GitOut(APath, ['remote'], Output) and (Output <> '') then
  begin
    Lines := TStringList.Create;
    try
      Lines.Text := Output;
      if Lines.IndexOf('origin') >= 0 then
        Remote := 'origin'
      else
        Remote := Lines[0];
    finally
      Lines.Free;
    end;
    if RunGitEnv(APath, ['ls-remote', '--symref', Remote, 'HEAD'], BatchRemoteEnv(APath),
      Output, Err, '', nil, ACancel) then
    begin
      Item := Default(TGittanMaintItem);
      Item.Task := mtSetHead;
      Item.Remote := Remote;
      Item.Want := SymrefHead(Output);
      if GitOut(APath, ['symbolic-ref', '-q', 'refs/remotes/' + Remote + '/HEAD'], Output) and
        (Copy(Output, 1, Length('refs/remotes/' + Remote + '/')) = 'refs/remotes/' + Remote + '/')
      then
        Item.Have := Copy(Output, Length('refs/remotes/' + Remote + '/') + 1, MaxInt);
      if (Item.Want <> '') and (Item.Have <> Item.Want) then
        Add(Item);
    end
    else
    begin
      Result.RemoteError := Trim(Err);
      if Result.RemoteError = '' then
        Result.RemoteError := 'git ls-remote failed.';
    end;
  end;

  { Worktrees whose folder is gone. }
  if ListWorktrees(APath, Trees, Err) then
  begin
    Item := Default(TGittanMaintItem);
    Item.Task := mtPruneWorktrees;
    for i := 0 to High(Trees) do
      if Trees[i].Prunable and not Trees[i].Locked then
      begin
        SetLength(Item.Worktrees, Length(Item.Worktrees) + 1);
        Item.Worktrees[High(Item.Worktrees)] := Trees[i].Path;
      end;
    if Length(Item.Worktrees) > 0 then
      Add(Item);
  end
  else
  begin
    Result.Error := Trim(Err);
    if Result.Error = '' then
      Result.Error := 'git worktree list failed.';
  end;

  { Objects enough to pack. }
  Item := Default(TGittanMaintItem);
  Item.Task := mtPack;
  if not ReadObjects(APath, Item.Loose, Item.Packs, Item.SizeKiB) then
  begin
    if Result.Error = '' then
      Result.Error := 'git count-objects failed.';
  end
  else if (Item.Loose >= ALooseLimit) or (Item.Packs >= APackLimit) then
    Add(Item);
end;

procedure RunMaintTask(const APath: string; var AItem: TGittanMaintItem);
var
  Output, Err: string;
  p, Loose, Packs: integer;
begin
  AItem.Done := False;
  AItem.Error := '';
  Err := '';
  case AItem.Task of
    mtSetHead:
      { set-head needs refs/remotes/<remote>/<want>, which a branch
        made on the remote since the last fetch does not have yet. }
      AItem.Done := ((AItem.Want = '') or RunGitEnv(APath, ['fetch', '--', AItem.Remote,
        AItem.Want], BatchRemoteEnv(APath), Output, Err)) and
        RunGitEnv(APath, ['remote', 'set-head', AItem.Remote, '--auto'],
        BatchRemoteEnv(APath), Output, Err);
    mtPruneWorktrees:
      AItem.Done := PruneWorktrees(APath, Err);
    mtPack:
    begin
      AItem.Done := RunGitIn(APath, ['gc', '--quiet'], Output, Err);
      if AItem.Done then
        ReadObjects(APath, Loose, Packs, AItem.AfterKiB);
    end;
  end;
  if AItem.Done then
    Exit;
  AItem.Error := Trim(Err);
  p := Pos(#10, AItem.Error);
  if p > 0 then
    AItem.Error := Trim(Copy(AItem.Error, 1, p - 1));
  if Copy(AItem.Error, 1, 7) = 'error: ' then
    Delete(AItem.Error, 1, 7)
  else if Copy(AItem.Error, 1, 7) = 'fatal: ' then
    Delete(AItem.Error, 1, 7);
  if AItem.Error = '' then
    AItem.Error := 'git failed.';
end;

function DeleteGoneBranch(const APath, ABranch: string): TGittanGoneBranch;
var
  Output, Err: string;
  p: integer;
begin
  Result := Default(TGittanGoneBranch);
  Result.Name := ABranch;
  GitOut(APath, ['rev-parse', '--short', 'refs/heads/' + ABranch], Result.Was);
  Result.Deleted := RunGitIn(APath, ['branch', '-D', '--', ABranch], Output, Err);
  if Result.Deleted then
    Exit;
  Result.Was := '';
  Result.Error := Trim(Err);
  { git's first line is its reason ("error: ... checked out at ..."). }
  p := Pos(#10, Result.Error);
  if p > 0 then
    Result.Error := Trim(Copy(Result.Error, 1, p - 1));
  if Copy(Result.Error, 1, 7) = 'error: ' then
    Delete(Result.Error, 1, 7);
end;

{ ---------------------------------------------------------------------------
  TGittanBatchJob
  --------------------------------------------------------------------------- }

procedure TGittanBatchJob.NotifyProgress;
begin
  if Assigned(FOnProgress) and not Terminated then
    FOnProgress(Self);
end;

procedure TGittanBatchJob.ItemDone;
begin
  { What the item wrote is out before the count says it is done. }
  WriteBarrier;
  InterLockedIncrement(FFinished);
  if not Terminated then
    Queue(@NotifyProgress);
end;

function TGittanBatchJob.Cancelled: boolean;
begin
  Result := Terminated;
end;

procedure TGittanBatchJob.Detach;
begin
  FOnProgress := nil;
  inherited Detach;
end;

function TGittanBatchJob.Finished: integer;
begin
  Result := FFinished;
  ReadBarrier;
end;

{ ---------------------------------------------------------------------------
  TGittanGoneScanJob
  --------------------------------------------------------------------------- }

constructor TGittanGoneScanJob.Create(const APaths, ACaptions: array of string;
  AFetch: boolean);
var
  i: integer;
begin
  inherited Create(True);
  FFetch := AFetch;
  SetLength(FRepos, Length(APaths));
  for i := 0 to High(APaths) do
  begin
    FRepos[i].Path := APaths[i];
    if i <= High(ACaptions) then
      FRepos[i].Caption := ACaptions[i];
  end;
end;

procedure TGittanGoneScanJob.Execute;
var
  i: integer;
begin
  for i := 0 to High(FRepos) do
  begin
    if Terminated then
      Exit;
    FRepos[i] := ScanGoneRepo(FRepos[i].Path, FRepos[i].Caption, FFetch, @Cancelled);
    ItemDone;
  end;
  Done;
end;

{ ---------------------------------------------------------------------------
  TGittanStatusJob
  --------------------------------------------------------------------------- }

constructor TGittanStatusJob.Create(const APaths, ACaptions: array of string);
var
  i: integer;
begin
  inherited Create(True);
  SetLength(FRepos, Length(APaths));
  for i := 0 to High(APaths) do
  begin
    FRepos[i].Path := APaths[i];
    if i <= High(ACaptions) then
      FRepos[i].Caption := ACaptions[i];
  end;
end;

procedure TGittanStatusJob.Execute;
var
  i: integer;
begin
  for i := 0 to High(FRepos) do
  begin
    if Terminated then
      Exit;
    FRepos[i] := RepoStatus(FRepos[i].Path, FRepos[i].Caption);
    ItemDone;
  end;
  Done;
end;

{ ---------------------------------------------------------------------------
  TGittanIdentityJob
  --------------------------------------------------------------------------- }

constructor TGittanIdentityJob.Create(const APaths, ACaptions: array of string);
var
  i: integer;
begin
  inherited Create(True);
  SetLength(FRepos, Length(APaths));
  for i := 0 to High(APaths) do
  begin
    FRepos[i].Path := APaths[i];
    if i <= High(ACaptions) then
      FRepos[i].Caption := ACaptions[i];
  end;
end;

procedure TGittanIdentityJob.Execute;
var
  i: integer;
begin
  for i := 0 to High(FRepos) do
  begin
    if Terminated then
      Exit;
    FRepos[i] := RepoIdentity(FRepos[i].Path, FRepos[i].Caption);
    ItemDone;
  end;
  Done;
end;

{ ---------------------------------------------------------------------------
  TGittanMaintScanJob
  --------------------------------------------------------------------------- }

constructor TGittanMaintScanJob.Create(const APaths, ACaptions: array of string);
var
  i: integer;
begin
  inherited Create(True);
  SetLength(FRepos, Length(APaths));
  for i := 0 to High(APaths) do
  begin
    FRepos[i].Path := APaths[i];
    if i <= High(ACaptions) then
      FRepos[i].Caption := ACaptions[i];
  end;
end;

procedure TGittanMaintScanJob.Execute;
var
  i: integer;
begin
  for i := 0 to High(FRepos) do
  begin
    if Terminated then
      Exit;
    FRepos[i] := ScanMaintenance(FRepos[i].Path, FRepos[i].Caption, True, MaintLooseLimit,
      MaintPackLimit, @Cancelled);
    ItemDone;
  end;
  Done;
end;

{ ---------------------------------------------------------------------------
  TGittanMaintRunJob
  --------------------------------------------------------------------------- }

constructor TGittanMaintRunJob.Create(const ARefs: TGittanMaintRefs);
begin
  { Never given up halfway: what was asked is done. }
  inherited Create(False);
  FRefs := Copy(ARefs);
end;

procedure TGittanMaintRunJob.Execute;
var
  i: integer;
begin
  for i := 0 to High(FRefs) do
  begin
    RunMaintTask(FRefs[i].Path, FRefs[i].Item);
    ItemDone;
  end;
  Done;
end;

{ ---------------------------------------------------------------------------
  TGittanGoneDeleteJob
  --------------------------------------------------------------------------- }

constructor TGittanGoneDeleteJob.Create(const ARefs: TGittanBranchRefs);
begin
  { Never given up halfway: what was asked is deleted. }
  inherited Create(False);
  FRefs := Copy(ARefs);
  SetLength(FResults, Length(FRefs));
end;

procedure TGittanGoneDeleteJob.Execute;
var
  i: integer;
begin
  for i := 0 to High(FRefs) do
  begin
    FResults[i] := DeleteGoneBranch(FRefs[i].Path, FRefs[i].Branch);
    ItemDone;
  end;
  Done;
end;

end.
