{ ---------------------------------------------------------------------------
  Clone, init and remotes
  ---------------------------------------------------------------------------
  File > Clone Repository... (and Clone... in the welcome view) asks for
  the URL and the folder (gittan.clonedlg) and clones in the remote job,
  its progress in the notice as a fetch's is, shown at once since a
  clone takes a while; the clone is opened when it is done, and a
  failure is told in the notice with Clone Again. File > Init
  Repository... (Init... in the welcome view) makes a repository of a
  folder chosen in the folder dialog and opens it; a folder that is one
  already is just opened, and one inside another repository is asked
  about first. File > Remotes... and Edit Remotes... on the Repository
  page open the Remotes dialog (gittan.remotesdlg), which changes the
  remotes with git at once; a remote added with its fetch asked for is
  fetched when the dialog closes. }

{ The folder the clone dialog and the init dialog start in: the last
  clone's, else the one the most recent repository is in, else home. }
function TRepoFrame.CloneParent: string;
begin
  Result := FCloneParent;
  if (Result <> '') and DirectoryExists(Result) then
    Exit;
  if App.Settings.Recent.Count > 0 then
  begin
    Result := ExtractFileDir(ExcludeTrailingPathDelimiter(App.Settings.Recent[0]));
    if DirectoryExists(Result) then
      Exit;
  end;
  Result := ExcludeTrailingPathDelimiter(GetUserDir);
end;

procedure TRepoFrame.StartClone(const AUrl, ATarget: string; ASubmodules: boolean);
begin
  if (FRemoteJob <> nil) or (FCommitJob <> nil) then
    Exit;
  FNoticeHook := False;
  FRemoteJob := TGittanRemoteJob.Create(ATarget, rkClone, pmAuto, AUrl);
  FRemoteJob.Submodules := ASubmodules;
  FRemoteJob.OnDone := @RemoteJobDone;
  FRemoteJob.OnOutput := @RemoteJobOutput;
  FRemoteJob.Start;
  FStatus.ShowBusy(Format(rsCloning, [CloneFolderName(AUrl)]), HintDown);
  ShowRemoteNotice;
  UpdateRemoteItems;
  UpdateCommitState;
end;

{ From RemoteJobDone, the job no longer the running one. }
procedure TRepoFrame.CloneDone(AJob: TGittanRemoteJob);
begin
  if not AJob.Ok then
  begin
    ShowRemoteFailure(AJob, False);
    Exit;
  end;
  FWindow.OpenRepository(AJob.Root, @ClonedOpened);
end;

{ The notes after a clone or an init wait for the repository, which
  opens in a thread. }
{ Sender is the frame the repository opened in, which may be another
  one (TRepoWindow.OpenRepository). }
procedure TRepoFrame.ClonedOpened(Sender: TObject);
begin
  with TRepoFrame(Sender) do
    BannerSuccess(Format(rsCloned, [ExtractFileName(FRepo.Root)]));
end;

procedure TRepoFrame.InitAlreadyOpened(Sender: TObject);
begin
  with TRepoFrame(Sender) do
    StatusNote(Format(rsInitAlready, [ExtractFileName(FRepo.Root)]));
end;

procedure TRepoFrame.InitDoneOpened(Sender: TObject);
begin
  with TRepoFrame(Sender) do
    BannerSuccess(Format(rsInitDone, [ExtractFileName(FRepo.Root)]));
end;

procedure TRepoFrame.MenuCloneClick(Sender: TObject);
var
  Url, Folder, Target: string;
  Submodules: boolean;
begin
  if (FRemoteJob <> nil) or (FCommitJob <> nil) then
    Exit;
  Url := '';
  Folder := CloneParent;
  Submodules := FCloneSubmodules;
  if not ChooseClone(Url, Folder, Submodules, Target) then
    Exit;
  FCloneParent := Folder;
  FCloneSubmodules := Submodules;
  StartClone(Url, Target, Submodules);
end;

{ A folder with a .git of its own is a repository already; git init
  there would only say it reinitialized it. }
procedure TRepoFrame.MenuInitClick(Sender: TObject);
var
  Dir, Err, Title: string;
  Probe: TGittanRepo;
  Inside: boolean;
begin
  if (FRemoteJob <> nil) or (FCommitJob <> nil) then
    Exit;
  Title := DirDialog.Title;
  DirDialog.Title := rsInitTitle;
  try
    DirDialog.InitialDir := CloneParent;
    if not DirDialog.Execute then
      Exit;
    Dir := ExcludeTrailingPathDelimiter(DirDialog.FileName);
  finally
    DirDialog.Title := Title;
  end;
  if FileExists(Dir + PathDelim + '.git') or DirectoryExists(Dir + PathDelim + '.git') then
  begin
    FWindow.OpenRepository(Dir, @InitAlreadyOpened);
    Exit;
  end;
  Probe := TGittanRepo.Create;
  try
    Inside := Probe.Open(Dir);
    if Inside and (AskDlg(rsInitTitle, Format(rsInitInside, [Dir,
      ExcludeTrailingPathDelimiter(Probe.Root)]), mtWarning, [mrYes, rsInitAction, mrCancel,
      rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes) then
      Exit;
  finally
    Probe.Free;
  end;
  if not InitRepository(Dir, Err) then
  begin
    { With no repository open the welcome view says it, as it says a
      folder that could not be opened. }
    if FRepo.Root = '' then
      ShowWelcome(Format(rsInitFailed, [Dir]) + ': ' + Trim(Err))
    else
      BannerError(Format(rsInitFailed, [Dir]), Err);
    Exit;
  end;
  FWindow.OpenRepository(Dir, @InitDoneOpened);
end;

function TRepoFrame.CanEditRemotes: boolean;
begin
  Result := (FRepo.Root <> '') and (FRemoteJob = nil) and (FCommitJob = nil);
end;

{ The status bar's upstream, the counts and the Repository page follow
  the change. }
procedure TRepoFrame.EditRemotesAsk;
var
  Fetch: boolean;
begin
  if not CanEditRemotes then
    Exit;
  if not EditRemotes(FRepo, Fetch) then
    Exit;
  RefreshRepository;
  if Fetch then
    StartRemote(rkFetch);
end;

procedure TRepoFrame.MenuRemotesClick(Sender: TObject);
begin
  EditRemotesAsk;
end;

procedure TRepoFrame.RepoPageEditRemotes(Sender: TObject);
begin
  EditRemotesAsk;
end;
