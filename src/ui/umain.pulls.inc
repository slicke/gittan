{ ---------------------------------------------------------------------------
  The Pull Requests page
  ---------------------------------------------------------------------------
  The open pull requests of the repository as the forge lists them
  (gittan.pullpage), in the box, from the sidebar's Pull Requests row,
  View > Pull Requests (Cmd+6) and All Pull Requests in the list the
  status bar's pull request chip drops; the row and the item show only
  while there is a forge (UpdateForgeItems). The page shows what the pull request job
  (umain.actions.inc) last read, the branch's own pull request first,
  and is asked for again each time it is shown; a card compares with
  its pull request as Compare With > Pull Requests does, the one
  compared against leads back to the working tree, and Refresh asks the
  forge again. The summary's row counting the open pull requests the job
  found waiting for the user's review drops a list of them
  (SummaryReviewClick): a pick compares the same way, and All Pull
  Requests opens the page. See spec/github.md. }

procedure TRepoFrame.SetupPullPage;
begin
  FPullPage := TGittanPullPage.Create(Self);
  FPullPage.Parent := FSummaryBox;
  FPullPage.Visible := False;
  FPullPage.OnCompare := @PullPageCompare;
  FPullPage.OnWorkingTree := @PullPageWorkingTree;
  FPullPage.OnRefresh := @PullPageRefresh;
  FPullPage.OnOpenUrl := @SummaryOpenUrl;
  FPullPage.SetForge(ForgeName);
end;

procedure TRepoFrame.MenuPullsClick(Sender: TObject);
begin
  if (FRepo.Root <> '') and Assigned(FForge) then
    ShowPulls;
end;

{ The page takes the summary's place in the box, as the Repository page
  does, and gh is asked again, keeping what it had meanwhile. }
procedure TRepoFrame.ShowPulls;
begin
  if (FRepo.Root = '') or not Assigned(FForge) then
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
procedure TRepoFrame.UpdatePullPage;
begin
  if FPullPage = nil then
    Exit;
  FPullPage.SetRepository(ExtractFileName(FRepo.Root), FRepo.Root);
  FPullPage.SetPulls(FPulls, FPullError, FPullJob <> nil);
  FPullPage.SetBranchPull(FPull, FHasPull);
  FPullPage.SetReviewPulls(FReviewPulls);
  if (FPullRange <> '') and (FRepo.Base = FPullRange) and FRepo.IsRange then
    FPullPage.SetComparing(FPullNumber)
  else
    FPullPage.SetComparing(0);
  if FPullPage.Visible then
    FPullPage.FitHeight(FSummaryBox.ClientHeight);
end;

procedure TRepoFrame.PullPageCompare(Sender: TObject; const APull: TGittanPullRequest);
begin
  ComparePull(APull);
end;

{ The list the summary's "N pull requests need your review" drops: a
  row per pull request, its number and title with who opened it and
  when dimmed, the one compared against checked, then All Pull
  Requests. }
procedure TRepoFrame.SummaryReviewClick(Sender: TObject; const AScreenRect: TRect);
var
  i: integer;
begin
  if (FRepo.Root = '') or (Length(FReviewPulls) = 0) then
    Exit;
  FReviewPopup.Clear;
  FReviewPopup.AddHeader(rsNeedsReviewHeader);
  for i := 0 to High(FReviewPulls) do
    FReviewPopup.Add(Format(rsPullHintTitle, [FReviewPulls[i].Number, FReviewPulls[i].Title]),
      ReviewPullLine(FReviewPulls[i]), (FPullRange <> '') and (FRepo.Base = FPullRange) and
      FRepo.IsRange and (FPullNumber = FReviewPulls[i].Number), i + 1);
  FReviewPopup.Add(rsAllPulls, '', False, 0);
  FReviewPopup.Popup(AScreenRect);
end;

procedure TRepoFrame.ReviewPopupPick(Sender: TObject; AIndex: integer);
var
  Pick: PtrInt;
begin
  Pick := FReviewPopup.TagOf(AIndex);
  if Pick = 0 then
    ShowPulls
  else if (Pick > 0) and (Pick <= Length(FReviewPulls)) then
    ComparePull(FReviewPulls[Pick - 1]);
end;

procedure TRepoFrame.PullPageWorkingTree(Sender: TObject);
begin
  SetBase('');
end;

procedure TRepoFrame.PullPageRefresh(Sender: TObject);
begin
  if (FRepo.Root = '') or (FPullJob <> nil) then
    Exit;
  StartPullJob(True, True);
end;
