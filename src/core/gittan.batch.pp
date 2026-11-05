unit gittan.batch;

{** Batch operations: work done in several repositories at once, which
  the Batch tab of the forge view (uforge, gittan.batchpage) runs on the
  repositories the user picks from those the welcome view shows.

  BatchRows gives those repositories as the tab lists them: the
  repository list's folders and repositories in its order, every folder
  open, then the recent repositories the list does not have under a
  heading of their own.

  The first operation deletes the local branches whose branch on the
  remote is gone. TGittanGoneScanJob fetches each repository with
  --prune and lists its local branches whose upstream is gone
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
  Classes, SysUtils, gittan.git, gittan.job, gittan.repolist;

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

{** Scans the repository at APath as TGittanGoneScanJob does. }
function ScanGoneRepo(const APath, ACaption: string; AFetch: boolean): TGittanGoneRepo;

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

function ScanGoneRepo(const APath, ACaption: string; AFetch: boolean): TGittanGoneRepo;
var
  Repo: TGittanRepo;
  Names: TStringList;
  Current, DefaultRef: string;
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
    if AFetch and not Repo.Fetch then
      Result.FetchError := Trim(Repo.Error);
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
    FRepos[i] := ScanGoneRepo(FRepos[i].Path, FRepos[i].Caption, FFetch);
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
