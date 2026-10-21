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
function TForm1.CloneParent: string;
begin
  Result := FCloneParent;
  if (Result <> '') and DirectoryExists(Result) then
    Exit;
  if FSettings.Recent.Count > 0 then
  begin
    Result := ExtractFileDir(ExcludeTrailingPathDelimiter(FSettings.Recent[0]));
    if DirectoryExists(Result) then
      Exit;
  end;
  Result := ExcludeTrailingPathDelimiter(GetUserDir);
end;

procedure TForm1.StartClone(const AUrl, ATarget: string; ASubmodules: boolean);
begin
  if (FRemoteJob <> nil) or (FCommitJob <> nil) then
    Exit;
  FNoticeHook := False;
  FRemoteJob := TGittanRemoteJob.Create(ATarget, rkClone, pmAuto, AUrl);
  FRemoteJob.Submodules := ASubmodules;
  FRemoteJob.OnDone := @RemoteJobDone;
  FRemoteJob.OnOutput := @RemoteJobOutput;
  FRemoteJob.Start;
  FStatus.ShowMessage(Format(rsCloning, [CloneFolderName(AUrl)]), stNormal, 0);
  ShowRemoteNotice;
  UpdateRemoteItems;
  UpdateCommitState;
end;

{ From RemoteJobDone, the job no longer the running one. }
procedure TForm1.CloneDone(AJob: TGittanRemoteJob);
begin
  if not AJob.Ok then
  begin
    ShowRemoteFailure(AJob, False);
    Exit;
  end;
  OpenRepository(AJob.Root);
  if FRepo.Root <> '' then
    BannerSuccess(Format(rsCloned, [ExtractFileName(ExcludeTrailingPathDelimiter(AJob.Root))]));
end;

procedure TForm1.MenuCloneClick(Sender: TObject);
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
procedure TForm1.MenuInitClick(Sender: TObject);
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
    OpenRepository(Dir);
    if FRepo.Root <> '' then
      StatusNote(Format(rsInitAlready, [ExtractFileName(Dir)]));
    Exit;
  end;
  Probe := TGittanRepo.Create;
  try
    Inside := Probe.Open(Dir);
    if Inside and (QuestionDlg(rsInitTitle, Format(rsInitInside, [Dir,
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
  OpenRepository(Dir);
  if FRepo.Root <> '' then
    BannerSuccess(Format(rsInitDone, [ExtractFileName(Dir)]));
end;

function TForm1.CanEditRemotes: boolean;
begin
  Result := (FRepo.Root <> '') and (FRemoteJob = nil) and (FCommitJob = nil);
end;

{ The status bar's upstream, the counts and the Repository page follow
  the change. }
procedure TForm1.EditRemotesAsk;
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

procedure TForm1.MenuRemotesClick(Sender: TObject);
begin
  EditRemotesAsk;
end;

procedure TForm1.RepoPageEditRemotes(Sender: TObject);
begin
  EditRemotesAsk;
end;
