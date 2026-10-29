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
  FPullPage.OnContext := @PullPageContext;
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

{ ---------------------------------------------------------------------------
  Acting on a pull request
  ---------------------------------------------------------------------------
  A right click on a card (or the Menu key) shows what can be done
  with the pull request: compare with it, open it on the forge, copy
  its link, and on the forge itself, while it is open: approve it,
  request changes or comment (a review, with words asked for first),
  merge it (with a merge commit, squashed or rebased, asked first) or,
  for a draft, mark it ready for review. The status bar's pull request
  list offers the same for the branch's own (PullChipClick). The forge
  does it in a thread (TGittanPullActionJob, from the forge's
  ActionJob); when it is done a banner says so, or shows the tool's
  words, and the forge is asked for the pull requests again, so the
  page and the chip follow. One action runs at a time. }
const
  pcCompare = 1;
  pcOpen = 2;
  pcCopy = 3;
  pcAct = 10;

procedure TRepoFrame.PullPageContext(Sender: TObject; const APull: TGittanPullRequest;
  const AScreenPos: TPoint);

  function Add(const ACaption: string; ATag: integer; AEnabled: boolean = True): TMenuItem;
  begin
    Result := AddMenuItem(FPullCardPopup.Items, ACaption, ATag, AEnabled, @PullCardMenuClick);
  end;

begin
  if FRepo.Root = '' then
    Exit;
  FActionPull := APull;
  FPullCardPopup.Items.Clear;
  Add(rsComparePull, pcCompare);
  if APull.Url <> '' then
  begin
    Add(Format(rsOpenPullOnForge, [ForgeName]), pcOpen);
    Add(rsCopyPullLink, pcCopy);
  end;
  if CanPullAction(APull, plApprove) then
  begin
    FPullCardPopup.Items.Add(NewLine);
    Add(rsPullApprove, pcAct + Ord(plApprove));
    Add(rsPullRequestChanges, pcAct + Ord(plRequestChanges));
    Add(rsPullComment, pcAct + Ord(plComment));
  end;
  if CanPullAction(APull, plMerge) then
  begin
    FPullCardPopup.Items.Add(NewLine);
    Add(rsPullMerge, pcAct + Ord(plMerge));
    Add(rsPullSquash, pcAct + Ord(plSquash));
    Add(rsPullRebaseMerge, pcAct + Ord(plRebaseMerge));
  end
  else if CanPullAction(APull, plReady) then
  begin
    FPullCardPopup.Items.Add(NewLine);
    Add(rsPullReady, pcAct + Ord(plReady));
  end;
  FPullCardPopup.PopUp(AScreenPos.X, AScreenPos.Y);
end;

procedure TRepoFrame.PullCardMenuClick(Sender: TObject);
var
  Which: integer;
begin
  Which := (Sender as TMenuItem).Tag;
  case Which of
    pcCompare: ComparePull(FActionPull);
    pcOpen: if FActionPull.Url <> '' then
        OpenURL(FActionPull.Url);
    pcCopy: Clipboard.AsText := FActionPull.Url;
    else
      if (Which >= pcAct) and (Which <= pcAct + Ord(High(TGittanPullAction))) then
        StartPullAction(FActionPull, TGittanPullAction(Which - pcAct));
  end;
end;

function TRepoFrame.CanPullAction(const APull: TGittanPullRequest;
  AAction: TGittanPullAction): boolean;
begin
  Result := Assigned(FForge) and FForge.HasPullActions and (FRepo.Root <> '') and
    (FPullActionJob = nil) and (APull.Number > 0) and (APull.Repo <> '') and
    (APull.State = prOpen);
  if Result then
    case AAction of
      plReady: Result := APull.IsDraft;
      plMerge, plSquash, plRebaseMerge: Result := not APull.IsDraft;
    end;
end;

procedure TRepoFrame.StartPullAction(const APull: TGittanPullRequest;
  AAction: TGittanPullAction);
var
  Words: string;
begin
  if not CanPullAction(APull, AAction) or not AskPullAction(APull, AAction, Words) then
    Exit;
  FPullActionJob := FForge.ActionJob(FRepo.Root, APull.Repo, APull.Number, AAction, Words);
  if FPullActionJob = nil then
    Exit;
  FPullActionJob.OnDone := @PullActionDone;
  FPullActionJob.Start;
  FStatus.ShowBusy(Format(rsPullActing, [ForgeName]));
end;

procedure TRepoFrame.PullActionDone(Sender: TObject);
var
  Job: TGittanPullActionJob;
begin
  Job := TGittanPullActionJob(Sender);
  if Job <> FPullActionJob then
    Exit;
  FPullActionJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  FStatus.ShowMessage('', stNormal, 0);
  MarkNews;
  if Job.Ok then
    BannerSuccess(Format(rsPullActionDone, [gittan.forge.PullActionDone(Job.Action), Job.Number]))
  else
    BannerError(Format(rsPullActionFailed, [ForgeName]), Job.Error);
  { The pull request as it is now: the page, the chip and the summary
    follow the job; a merge may have deleted the branch on the remote,
    which the job sees after the next fetch. A poll running may have
    read it from before the action, so it gives way. }
  if FRepo.Root <> '' then
    StartPullJob(True, True);
end;

procedure TRepoFrame.AbandonPullAction;
begin
  if FPullActionJob = nil then
    Exit;
  FPullActionJob.Stop(False);
  FBlameZombies.Add(FPullActionJob);
  FPullActionJob := nil;
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
  RemoteFor gives), and a branch with commits not pushed the same (Push
  and Open, Open Anyway); the page opens when the push worked. A push
  that worked otherwise offers the page in its banner, for a branch
  other than the default one that has no pull request. }

{ Not for the default branch, a branch with an open pull request (one
  merged or closed may be followed by another; another branch's among
  the open ones the forge listed, FPulls, by its name on its remote),
  the current branch before its first commit, during a merge or rebase,
  or while a push or a commit runs. }
function TRepoFrame.CanCreatePull(const ABranch: string): boolean;
var
  Remote, Default, RemoteBranch: string;
  i: integer;
begin
  Result := Assigned(FForge) and (FRepo.Root <> '') and (ABranch <> '') and
    (FOperation = '') and (FRemoteJob = nil) and (FCommitJob = nil) and
    not ((ABranch = FBranch) and FHasPull and (FPull.State = prOpen)) and
    not ((ABranch = FBranch) and (FSnapHead = ''));
  if Result and (FDefaultBranch <> '') and
    FRepo.SplitRemoteRef(FDefaultBranch, Remote, Default) then
    Result := ABranch <> Default;
  if Result and (ABranch <> FBranch) then
  begin
    if not FRepo.SplitRemoteRef(FRepo.Upstream(ABranch), Remote, RemoteBranch) then
      RemoteBranch := ABranch;
    for i := 0 to High(FPulls) do
      if (FPulls[i].State = prOpen) and (FPulls[i].HeadRef = RemoteBranch) then
        Exit(False);
  end;
end;

procedure TRepoFrame.CreatePull(const ABranch: string);
var
  Up, Remote, RemoteBranch: string;
  Ahead: integer;
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
    if AskDlg(rsNewPullTitle, Format(rsNewPullPush, [ABranch, Remote, ForgeName]),
      mtConfirmation, [mrYes, rsPushAndOpen, 'IsDefault', mrCancel, rsCancelButton,
      'IsCancel'], 0) <> mrYes then
      Exit;
    FPullAfterPush := ABranch;
    StartRemote(rkPushBranch, pmAuto, ABranch, Remote);
    Exit;
  end;
  { Another branch (the one a push banner offered) is counted against
    its upstream here, as the snapshot counts the current one, when it
    is pushed to the branch of its own name, as rkPushBranch pushes. }
  Ahead := 0;
  if ABranch = FBranch then
  begin
    if FHasUpstream then
      Ahead := FAhead;
  end
  else if RemoteBranch = ABranch then
    Ahead := FRepo.CountCommits(Up, 'refs/heads/' + ABranch);
  if Ahead > 0 then
    case AskDlg(rsNewPullTitle, Format(rsNewPullAhead, [Ahead, ABranch]),
        mtConfirmation, [mrYes, rsPushAndOpen, 'IsDefault', mrNo, rsOpenAnyway,
        mrCancel, rsCancelButton, 'IsCancel'], 0) of
      mrYes:
      begin
        FPullAfterPush := ABranch;
        if ABranch = FBranch then
          StartRemote(rkPush)
        else
          StartRemote(rkPushBranch, pmAuto, ABranch, Remote);
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
  forge's own. A remote pushed to on no host of the forge's (the forge
  found by another remote) gives no page, but a note. }
procedure TRepoFrame.OpenNewPull(const ABranch: string);
var
  Remote, RemoteBranch, Url, Err: string;
begin
  { The forge may have gone while the push ran (hosting turned off). }
  if not Assigned(FForge) then
    Exit;
  if not FRepo.SplitRemoteRef(FRepo.Upstream(ABranch), Remote, RemoteBranch) then
  begin
    Remote := '';
    RemoteBranch := ABranch;
  end;
  Url := '';
  if (Remote <> '') and RunGitIn(FRepo.Root, ['remote', 'get-url', '--push', Remote],
    Url, Err) then
  begin
    Url := Trim(Url);
    if ForgeClassFor('remote.' + Remote + '.pushurl ' + Url) <> FForge.ClassType then
    begin
      StatusNote(Format(rsNewPullOtherHost, [Remote, ForgeName]), True);
      Exit;
    end;
    Url := RemoteRepoPath(Url);
  end
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
