{ ---------------------------------------------------------------------------
  The forge page: the user's pull requests across every repository
  ---------------------------------------------------------------------------
  The sidebar's GitHub row and View > GitHub (Cmd+7) open the forge page
  (gittan.forgepage): the open pull requests the user wrote at the
  left, the open ones waiting for their review at the right, across
  every repository of the forge, read by a TGittanForgeJob
  (gittan.forge; GitHub through gh, with one GraphQL query) each time
  the page is shown and on Refresh, the page keeping what it had
  meanwhile; the row and the item show only with gh (UpdateGitHubItems).
  The ones the user has reviewed are left out, unless they are asked
  again (NeedsMyReview); the page's checkbox leaves out the user's own
  that nobody else has answered, kept in the settings
  (HideWithoutFeedback). A card of a pull request of the open
  repository (HasRemoteFor) compares with it as the Pull Requests page
  does; one of another repository opens on the forge. GitHub is the
  only forge so far; another adds a kind and a job to gittan.forge and
  a page per forge here. See spec/github.md. }

procedure TForm1.SetupForgePage;
begin
  FForgePage := TGittanForgePage.Create(Self);
  FForgePage.Parent := FSummaryBox;
  FForgePage.Visible := False;
  FForgePage.SetForge(ForgeName(fkGitHub));
  FForgePage.OnPick := @ForgePagePick;
  FForgePage.OnRefresh := @ForgePageRefresh;
  FForgePage.HideWithoutFeedback := FSettings.HideWithoutFeedback;
  FForgePage.OnHideChange := @ForgePageHideChange;
  FForgePage.OnOpenUrl := @SummaryOpenUrl;
end;

procedure TForm1.MenuForgeClick(Sender: TObject);
begin
  if (FRepo.Root <> '') and FHasGitHubCli then
    ShowForge;
end;

{ The page takes the summary's place in the box, as the Pull Requests
  page does, and the forge is asked again, keeping what it had. }
procedure TForm1.ShowForge;
begin
  if (FRepo.Root = '') or not FHasGitHubCli then
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
procedure TForm1.UpdateForgePage;
begin
  if FForgePage = nil then
    Exit;
  FForgePage.SetLogin(FForgeLogin);
  FForgePage.SetPulls(FForgeMine, FForgeReview, FForgeError, FForgeJob <> nil);
  if FForgePage.Visible then
    FForgePage.FitHeight(FSummaryBox.ClientHeight);
end;

{ Asks the forge, one job at a time: a start while one runs waits for
  its answer. }
procedure TForm1.StartForgeJob;
begin
  if not FHasGitHubCli or (FRepo.Root = '') or (FForgeJob <> nil) then
    Exit;
  FForgeJob := TGittanGitHubForgeJob.Create(FGitHubCli, FRepo.Root);
  FForgeJob.OnDone := @ForgeJobDone;
  FForgeJob.Start;
  UpdateForgePage;
end;

procedure TForm1.AbandonForgeJob;
begin
  if FForgeJob = nil then
    Exit;
  FForgeJob.Stop(False);
  FBlameZombies.Add(FForgeJob);
  FForgeJob := nil;
end;

procedure TForm1.ForgeJobDone(Sender: TObject);
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
    { The pull request job asks gh for the same login; spare it. }
    if FGitHubLogin = '' then
      FGitHubLogin := Job.Login;
  end;
  UpdateForgePage;
end;

{ A card: compare with the pull request when the open repository has a
  remote for its repository, else open it on the forge. }
procedure TForm1.ForgePagePick(Sender: TObject; const APull: TGittanForgePull);
var
  Pull: TGittanPullRequest;
begin
  if (FRepo.Root <> '') and (APull.Repo <> '') and FRepo.HasRemoteFor(APull.Repo) then
  begin
    Pull := Default(TGittanPullRequest);
    Pull.Number := APull.Number;
    Pull.Title := APull.Title;
    Pull.Url := APull.Url;
    Pull.HeadRef := APull.HeadRef;
    Pull.BaseRef := APull.BaseRef;
    Pull.Author := APull.Author;
    Pull.State := APull.State;
    Pull.ReviewDecision := APull.ReviewDecision;
    Pull.IsDraft := APull.IsDraft;
    Pull.Created := APull.Created;
    Pull.Updated := APull.Updated;
    ComparePull(Pull);
  end
  else if APull.Url <> '' then
    SummaryOpenUrl(Self, APull.Url);
end;

procedure TForm1.ForgePageRefresh(Sender: TObject);
begin
  StartForgeJob;
end;

{ The checkbox: the settings keep it, and the page's new height. }
procedure TForm1.ForgePageHideChange(Sender: TObject);
begin
  FSettings.HideWithoutFeedback := FForgePage.HideWithoutFeedback;
  if FForgePage.Visible then
    FForgePage.FitHeight(FSummaryBox.ClientHeight);
end;
