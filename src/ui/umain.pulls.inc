{ ---------------------------------------------------------------------------
  The Pull Requests page
  ---------------------------------------------------------------------------
  The open pull requests of the repository as gh lists them
  (gittan.pullpage), in the box, from the sidebar's Pull Requests row,
  View > Pull Requests (Cmd+6) and All Pull Requests in the list the
  status bar's pull request chip drops; the row and the item show only
  with gh (UpdateGitHubItems). The page shows what the pull request job
  (umain.actions.inc) last read, the branch's own pull request first,
  and is asked for again each time it is shown; a card compares with
  its pull request as Compare With > Pull Requests does, the one
  compared against leads back to the working tree, and Refresh asks gh
  again. See spec/github.md. }

procedure TForm1.SetupPullPage;
begin
  FPullPage := TGittanPullPage.Create(Self);
  FPullPage.Parent := FSummaryBox;
  FPullPage.Visible := False;
  FPullPage.OnCompare := @PullPageCompare;
  FPullPage.OnWorkingTree := @PullPageWorkingTree;
  FPullPage.OnRefresh := @PullPageRefresh;
  FPullPage.OnOpenUrl := @SummaryOpenUrl;
end;

procedure TForm1.MenuPullsClick(Sender: TObject);
begin
  if (FRepo.Root <> '') and FHasGitHubCli then
    ShowPulls;
end;

{ The page takes the summary's place in the box, as the Repository page
  does, and gh is asked again, keeping what it had meanwhile. }
procedure TForm1.ShowPulls;
begin
  if (FRepo.Root = '') or not FHasGitHubCli then
    Exit;
  if FGraph.Visible then
    FGraph.Close;
  LeaveEditorViews;
  FView := gvPulls;
  HideBoxPages;
  UpdatePullPage;
  FPullPage.Visible := True;
  FPullPage.FitHeight(FSummaryBox.ClientHeight);
  FSummaryBox.Visible := True;
  FSummaryBox.VertScrollBar.Position := 0;
  FStatus.SetPosition('');
  { A file picked again after the page must fire the selection event. }
  FileTree.Selected := nil;
  FRepoTree.Selected := nil;
  FSubTree.Selected := nil;
  SetNavRow(navPulls);
  StartPullJob(True, True);
  UpdateStatus;
end;

{ What the job knows, to the page: the open pull requests, gh's message
  when it failed, whether it is being asked, the branch's own pull
  request and the one compared against. }
procedure TForm1.UpdatePullPage;
begin
  if FPullPage = nil then
    Exit;
  FPullPage.SetRepository(ExtractFileName(FRepo.Root), FRepo.Root);
  FPullPage.SetPulls(FPulls, FPullError, FPullJob <> nil);
  FPullPage.SetBranchPull(FPull, FHasPull);
  if (FPullRange <> '') and (FRepo.Base = FPullRange) and FRepo.IsRange then
    FPullPage.SetComparing(FPullNumber)
  else
    FPullPage.SetComparing(0);
  if FPullPage.Visible then
    FPullPage.FitHeight(FSummaryBox.ClientHeight);
end;

procedure TForm1.PullPageCompare(Sender: TObject; const APull: TGittanPullRequest);
begin
  ComparePull(APull);
end;

procedure TForm1.PullPageWorkingTree(Sender: TObject);
begin
  SetBase('');
end;

procedure TForm1.PullPageRefresh(Sender: TObject);
begin
  if (FRepo.Root = '') or (FPullJob <> nil) then
    Exit;
  StartPullJob(True, True);
end;
