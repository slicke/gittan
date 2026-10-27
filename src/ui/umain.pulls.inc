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

{ ---------------------------------------------------------------------------
  A new pull request
  ---------------------------------------------------------------------------
  Branch > Create Pull Request... and the status bar's item open the
  forge's page for a new pull request from the current branch (a
  wtNewPull target): GitHub's compare page, the form unfolded. A branch
  not on a remote yet is offered the push first (push -u to the remote
  RemoteFor gives), and the current branch with commits not pushed the
  same (Push and Open, Open Anyway); the page opens when the push
  worked. A push that worked otherwise offers the page in its banner,
  for a branch other than the default one that has no pull request. }

{ Not for the default branch, a branch with an open pull request (one
  merged or closed may be followed by another), during a merge or
  rebase, or while a push or a commit runs. }
function TRepoFrame.CanCreatePull(const ABranch: string): boolean;
var
  Remote, Default: string;
begin
  Result := Assigned(FForge) and (FRepo.Root <> '') and (ABranch <> '') and
    (FOperation = '') and (FRemoteJob = nil) and (FCommitJob = nil) and
    not ((ABranch = FBranch) and FHasPull and (FPull.State = prOpen));
  if Result and (FDefaultBranch <> '') and
    FRepo.SplitRemoteRef(FDefaultBranch, Remote, Default) then
    Result := ABranch <> Default;
end;

procedure TRepoFrame.CreatePull(const ABranch: string);
var
  Up, Remote, RemoteBranch: string;
begin
  if not CanCreatePull(ABranch) then
  begin
    if Assigned(FForge) and (ABranch = FBranch) and FHasPull and (FPull.State = prOpen) then
      StatusNote(Format(rsNewPullHasOne, [ABranch, FPull.Number]));
    Exit;
  end;
  if not FRepo.HasCommit('refs/heads/' + ABranch) then
  begin
    StatusNote(rsUpstreamDetached, True);
    Exit;
  end;
  Up := FRepo.Upstream(ABranch);
  if (Up = '') or not FRepo.SplitRemoteRef(Up, Remote, RemoteBranch) then
  begin
    Remote := FRepo.RemoteFor('');
    if Remote = '' then
    begin
      StatusNote(Format(rsNewPullNoRemote, [ABranch]), True);
      Exit;
    end;
    if QuestionDlg(rsNewPullTitle, Format(rsNewPullPush, [ABranch, Remote, ForgeName]),
      mtConfirmation, [mrYes, rsPushAndOpen, 'IsDefault', mrCancel, rsCancelButton,
      'IsCancel'], 0) <> mrYes then
      Exit;
    FPullAfterPush := ABranch;
    StartRemote(rkPushBranch, pmAuto, ABranch, Remote);
    Exit;
  end;
  if (ABranch = FBranch) and FHasUpstream and (FAhead > 0) then
    case QuestionDlg(rsNewPullTitle, Format(rsNewPullAhead, [FAhead, ABranch]),
        mtConfirmation, [mrYes, rsPushAndOpen, 'IsDefault', mrNo, rsOpenAnyway,
        mrCancel, rsCancelButton, 'IsCancel'], 0) of
      mrYes:
      begin
        FPullAfterPush := ABranch;
        StartRemote(rkPush);
        Exit;
      end;
      mrNo: ;
      else
        Exit;
    end;
  OpenNewPull(ABranch);
end;

{ The branch as its upstream names it on its remote, in the repository
  the remote's push URL holds, which is a fork when it is not the
  forge's own. }
procedure TRepoFrame.OpenNewPull(const ABranch: string);
var
  Remote, RemoteBranch, Url, Err: string;
begin
  if not FRepo.SplitRemoteRef(FRepo.Upstream(ABranch), Remote, RemoteBranch) then
  begin
    Remote := '';
    RemoteBranch := ABranch;
  end;
  Url := '';
  if (Remote <> '') and RunGitIn(FRepo.Root, ['remote', 'get-url', '--push', Remote],
    Url, Err) then
    Url := RemoteRepoPath(Url)
  else
    Url := '';
  OpenOnForge(NewPullTarget(RemoteBranch, Url));
end;

{ A push's success, with Create Pull Request by it when ABranch could
  have one; the page itself when the push was asked for to open it. }
procedure TRepoFrame.PushedBanner(const ATitle, ABranch: string);
begin
  if (FPullAfterPush <> '') and (FPullAfterPush = ABranch) then
  begin
    FPullAfterPush := '';
    BannerSuccess(ATitle);
    OpenNewPull(ABranch);
    Exit;
  end;
  FPullAfterPush := '';
  if not CanCreatePull(ABranch) then
  begin
    BannerSuccess(ATitle);
    Exit;
  end;
  MarkNews;
  FPushedBranch := ABranch;
  FBanner.AddAction(ATitle, '', bkSuccess, BannerActionSeconds, rsNewPullAction,
    @NewPullBannerClick);
end;

procedure TRepoFrame.MenuNewPullClick(Sender: TObject);
begin
  CreatePull(FBranch);
end;

procedure TRepoFrame.NewPullBannerClick(Sender: TObject);
begin
  if FPushedBranch <> '' then
    CreatePull(FPushedBranch);
end;
