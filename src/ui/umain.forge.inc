{ ---------------------------------------------------------------------------
  The forge page: the user's pull requests across every repository
  ---------------------------------------------------------------------------
  The sidebar's row and the View menu's item named after the forge
  (GitHub, Cmd+7) open the forge page (gittan.forgepage): the open pull
  requests the user wrote at the left, the open ones waiting for their
  review at the right, across every repository of the forge, read by
  the forge's AccountJob (gittan.forge; GitHub's runs one GraphQL query
  through gh) each time the page is shown and on Refresh, the page
  keeping what it had meanwhile; the row and the item show only while
  there is a forge (UpdateForgeItems).
  The ones the user has reviewed are left out, unless they are asked
  again (NeedsMyReview); the page's checkbox leaves out the user's own
  that nobody else has answered, kept in the settings
  (HideWithoutFeedback). A card of a pull request of the open
  repository (HasRemoteFor) compares with it as the Pull Requests page
  does; one of another repository with a clone among the recent ones,
  or beside them while CloneSiblings is on (the job's FindClones and
  AddSiblingRepositories), opens that clone and compares with it there;
  any other opens on the forge. GitHub is the only forge so far. See
  spec/github.md. }

procedure TRepoFrame.SetupForgePage;
begin
  FForgePage := TGittanForgePage.Create(Self);
  FForgePage.Parent := FSummaryBox;
  FForgePage.Visible := False;
  FForgePage.SetForge(ForgeName);
  FForgePage.OnPick := @ForgePagePick;
  FForgePage.OnRefresh := @ForgePageRefresh;
  FForgePage.HideWithoutFeedback := App.Settings.HideWithoutFeedback;
  FForgePage.OnHideChange := @ForgePageHideChange;
  FForgePage.OnOpenUrl := @SummaryOpenUrl;
end;

procedure TRepoFrame.MenuForgeClick(Sender: TObject);
begin
  if (FRepo.Root <> '') and Assigned(FForge) then
    ShowForge;
end;

{ The page takes the summary's place in the box, as the Pull Requests
  page does, and the forge is asked again, keeping what it had. }
procedure TRepoFrame.ShowForge;
begin
  if (FRepo.Root = '') or not Assigned(FForge) then
    Exit;
  if FGraph.Visible then
    FGraph.Close;
  LeaveEditorViews;
  FView := gvForge;
  HideBoxPages;
  UpdateForgePage;
  FForgePage.Visible := True;
  FForgePage.FitHeight(FSummaryBox.ClientHeight);
  FSummaryBox.Visible := True;
  FSummaryBox.VertScrollBar.Position := 0;
  FStatus.SetPosition('');
  { A file picked again after the page must fire the selection event. }
  FileTree.Selected := nil;
  FRepoTree.Selected := nil;
  FSubTree.Selected := nil;
  SetNavRow(navForge);
  StartForgeJob;
  UpdateStatus;
end;

{ What the job last read, to the page, and whether one runs. }
procedure TRepoFrame.UpdateForgePage;
begin
  if FForgePage = nil then
    Exit;
  FForgePage.SetLogin(FForgeLogin);
  FForgePage.SetOpenRoot(FRepo.Root);
  FForgePage.SetPulls(FForgeMine, FForgeReview, FForgeError, FForgeJob <> nil);
  if FForgePage.Visible then
    FForgePage.FitHeight(FSummaryBox.ClientHeight);
end;

{ Asks the forge, one job at a time: a start while one runs waits for
  its answer. }
procedure TRepoFrame.StartForgeJob;
begin
  if not Assigned(FForge) or (FRepo.Root = '') or (FForgeJob <> nil) then
    Exit;
  FForgeJob := FForge.AccountJob(FRepo.Root);
  FForgeJob.Clones.Assign(App.Settings.Recent);
  FForgeJob.Siblings := App.Settings.CloneSiblings;
  FForgeJob.OnDone := @ForgeJobDone;
  FForgeJob.Start;
  UpdateForgePage;
end;

procedure TRepoFrame.AbandonForgeJob;
begin
  if FForgeJob = nil then
    Exit;
  FForgeJob.Stop(False);
  FBlameZombies.Add(FForgeJob);
  FForgeJob := nil;
end;

procedure TRepoFrame.ForgeJobDone(Sender: TObject);
var
  Job: TGittanForgeJob;
begin
  Job := TGittanForgeJob(Sender);
  if Job <> FForgeJob then
    Exit;
  FForgeJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  FForgeError := Job.Error;
  if FForgeError = '' then
  begin
    FForgeLogin := Job.Login;
    FForgeMine := Job.Mine;
    FForgeReview := Job.Review;
    { The pull request job asks the forge for the same login; spare it. }
    if FPullLogin = '' then
      FPullLogin := Job.Login;
  end;
  UpdateForgePage;
end;

{ The forge page's pull request as the open repository's are kept. }
function ForgePullRequest(const APull: TGittanForgePull): TGittanPullRequest;
begin
  Result := Default(TGittanPullRequest);
  Result.Number := APull.Number;
  Result.Repo := APull.Repo;
  Result.Title := APull.Title;
  Result.Url := APull.Url;
  Result.HeadRef := APull.HeadRef;
  Result.BaseRef := APull.BaseRef;
  Result.Author := APull.Author;
  Result.State := APull.State;
  Result.ReviewDecision := APull.ReviewDecision;
  Result.IsDraft := APull.IsDraft;
  Result.Created := APull.Created;
  Result.Updated := APull.Updated;
end;

{ A card: compare with the pull request when the open repository has a
  remote for its repository, else open its clone and compare there when
  it has one, else open it on the forge. }
procedure TRepoFrame.ForgePagePick(Sender: TObject; const APull: TGittanForgePull);
begin
  if (FRepo.Root <> '') and (APull.Repo <> '') and FRepo.HasRemoteFor(APull.Repo) then
    ComparePull(ForgePullRequest(APull))
  else if (APull.Clone <> '') and DirectoryExists(APull.Clone) then
  begin
    FForgeClonePull := ForgePullRequest(APull);
    OpenRepository(APull.Clone, @ForgeCloneOpened);
  end
  else if APull.Url <> '' then
    SummaryOpenUrl(Self, APull.Url);
end;

procedure TRepoFrame.ForgeCloneOpened(Sender: TObject);
begin
  if (FRepo.Root <> '') and FRepo.HasRemoteFor(FForgeClonePull.Repo) then
    ComparePull(FForgeClonePull);
end;

procedure TRepoFrame.ForgePageRefresh(Sender: TObject);
begin
  StartForgeJob;
end;

{ The checkbox: the settings keep it, and the page's new height. }
procedure TRepoFrame.ForgePageHideChange(Sender: TObject);
begin
  App.Settings.HideWithoutFeedback := FForgePage.HideWithoutFeedback;
  if FForgePage.Visible then
    FForgePage.FitHeight(FSummaryBox.ClientHeight);
end;
