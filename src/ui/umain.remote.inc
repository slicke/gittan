{ ---------------------------------------------------------------------------
  Fetch, pull and push
  ---------------------------------------------------------------------------
  File > Fetch, Pull and Push, and the same in a list that drops up from
  the status bar's "↑2 ↓5", with the commit graph last. Each runs in a
  thread (gittan.remotejob), one at a time and not while a commit runs;
  the status bar says what is going on meanwhile, and a notice in the
  middle of the form (gittan.notice) shows what git and the hooks write
  as they run: at once for a push with a pre-push hook, which may run
  the tests, else after NoticeDelay, so a quick fetch shows none. A pull
  that finds the branch diverged asks whether to merge or rebase, a
  push the remote rejects offers to pull first, or, when the upstream
  has commits the branch lacks (as after a rebase of pushed commits), to
  force the push with --force-with-lease; a forced push that finds the
  remote moved since the last fetch offers to fetch. Any other failure
  shows git's reason. The same job also pushes a branch to a remote it
  then tracks, pushes tags, deletes a branch or a tag on a remote,
  clones (umain.clone.inc), and updates and adds submodules
  (umain.submodules.inc). }
const
  saPull = 0;
  saPush = 1;
  saFetch = 2;
  saGraph = 3;
  saForcePush = 4;

procedure TRepoFrame.UpdateRemoteItems;
var
  Can: boolean;
begin
  Can := (FRepo <> nil) and (FRepo.Root <> '') and (FRemoteJob = nil) and
    (FCommitJob = nil);
  { The status bar's buttons are dimmed while a job runs, from its start,
    which also moves what it says into their row. }
  UpdateStatusTransport;
  if FFetchItem = nil then
    Exit;
  FFetchItem.Enabled := Can;
  FPullItem.Enabled := Can;
  FPushItem.Enabled := Can;
  FForcePushItem.Enabled := Can and FHasUpstream;
  FRemotesItem.Enabled := Can;
  FCloneItem.Enabled := (FRemoteJob = nil) and (FCommitJob = nil);
  FInitItem.Enabled := FCloneItem.Enabled;
  UpdateSubmoduleItems;
  UpdateBranchItems;
  UpdateStashItems;
end;

procedure TRepoFrame.StartRemote(AKind: TGittanRemoteKind; AMode: TGittanPullMode;
  const AArg, ARemote: string);
begin
  if (FRepo.Root = '') or (FRemoteJob <> nil) or (FCommitJob <> nil) then
    Exit;
  { Two fetches or a fetch and a pull would fight over the same refs:
    this one waits for the background fetch, which is quick. }
  if FAutoFetchJob <> nil then
  begin
    { One waits; a second is refused rather than put in its place. }
    if FPendingRemote then
    begin
      FStatus.ShowBusy(rsAlreadyWaiting, HintFetch);
      Exit;
    end;
    FPendingRemote := True;
    FPendingKind := AKind;
    FPendingMode := AMode;
    FPendingArg := AArg;
    FPendingRemoteName := ARemote;
    FStatus.ShowBusy(rsWaitingForFetch, HintFetch);
    Exit;
  end;
  FRemoteAhead := FAhead;
  { What a pull brings in is counted from here when it is done. }
  if AKind = rkPull then
    FRemoteHead := FRepo.CommitId('HEAD')
  else
    FRemoteHead := '';
  { Deleting on a remote is a push too, and runs the hook. }
  FNoticeHook := (AKind in [rkPush, rkForcePush, rkPushBranch, rkPushTag, rkDeleteRemote,
    rkDeleteRemoteTag]) and FRepo.HasHook('pre-push');
  FRemoteJob := TGittanRemoteJob.Create(FRepo.Root, AKind, AMode, AArg, ARemote);
  FRemoteJob.OnDone := @RemoteJobDone;
  FRemoteJob.OnOutput := @RemoteJobOutput;
  if AKind = rkLfsFetch then
    FRemoteJob.Refs := FLfsRefs;
  FRemoteJob.Start;
  if FNoticeHook then
    FStatus.ShowBusy(rsRunningHook)
  else
    case AKind of
      rkFetch: FStatus.ShowBusy(rsFetching, HintFetch);
      rkPull: FStatus.ShowBusy(rsPulling, HintDown);
      rkPush: FStatus.ShowBusy(rsPushing, HintUp);
      rkForcePush: FStatus.ShowBusy(rsForcePushing, HintUp);
      rkPushBranch:
        FStatus.ShowBusy(Format(rsPushingTo, [AArg, ARemote]), HintUp);
      rkPushTag:
        if AArg = '' then
          FStatus.ShowBusy(Format(rsPushingTags, [ARemote]), HintUp)
        else
          FStatus.ShowBusy(Format(rsPushingTo, [AArg, ARemote]), HintUp);
      rkDeleteRemote, rkDeleteRemoteTag:
        FStatus.ShowBusy(Format(rsDeletingRemote, [AArg]), HintUp);
      rkSubmoduleUpdate:
        if AArg = '' then
          FStatus.ShowBusy(rsSubUpdatingAll)
        else
          FStatus.ShowBusy(Format(rsSubUpdating, [AArg]));
      rkLfsFetch:
        FStatus.ShowBusy(Format(rsLfsDownloading, [ExtractFileName(AArg)]),
          HintDown);
      rkLfsPull: FStatus.ShowBusy(rsLfsPulling, HintDown);
      rkLfsInstall: FStatus.ShowBusy(rsLfsInstalling);
      rkLfsLock: FStatus.ShowBusy(Format(rsLfsLocking, [AArg]));
      rkLfsUnlock, rkLfsForceUnlock: FStatus.ShowBusy(Format(rsLfsUnlocking, [AArg]));
    end;
  if FNoticeHook then
    ShowRemoteNotice
  else
    FNoticeTimer.Enabled := True;
  UpdateRemoteItems;
  UpdateCommitState;
end;

function TRepoFrame.RemoteNoticeTitle: string;
begin
  Result := '';
  if FRemoteJob = nil then
    Exit;
  if FNoticeHook then
    Exit(rsNoticeHook);
  case FRemoteJob.Kind of
    rkFetch: Result := rsNoticeFetching;
    rkPull: Result := rsNoticePulling;
    rkPush: Result := rsNoticePushing;
    rkForcePush: Result := rsNoticeForcePushing;
    rkPushBranch: Result := Format(rsNoticePushingTo, [FRemoteJob.Arg, FRemoteJob.Remote]);
    rkPushTag:
      if FRemoteJob.Arg = '' then
        Result := Format(rsNoticePushingTo, [rsTheTags, FRemoteJob.Remote])
      else
        Result := Format(rsNoticePushingTo, [FRemoteJob.Arg, FRemoteJob.Remote]);
    rkDeleteRemote: Result := Format(rsNoticeDeleting, [FRemoteJob.Arg]);
    rkDeleteRemoteTag: Result := Format(rsNoticeDeletingOn, [FRemoteJob.Arg,
        FRemoteJob.Remote]);
    rkClone: Result := Format(rsNoticeCloning, [CloneFolderName(FRemoteJob.Arg)]);
    rkSubmoduleUpdate:
      if FRemoteJob.Arg = '' then
        Result := rsNoticeSubUpdatingAll
      else
        Result := Format(rsNoticeSubUpdating, [FRemoteJob.Arg]);
    rkSubmoduleAdd: Result := Format(rsNoticeSubAdding, [FRemoteJob.Path]);
    rkFetchPull: Result := Format(rsNoticeFetchingPull, [StrToIntDef(FRemoteJob.Arg, 0)]);
    rkLfsFetch: Result := Format(rsNoticeLfsDownloading, [ExtractFileName(FRemoteJob.Arg)]);
    rkLfsPull: Result := rsNoticeLfsPulling;
    rkLfsInstall: Result := rsNoticeLfsInstalling;
    rkLfsLock: Result := Format(rsNoticeLfsLocking, [FRemoteJob.Arg]);
    rkLfsUnlock, rkLfsForceUnlock: Result := Format(rsNoticeLfsUnlocking, [FRemoteJob.Arg]);
  end;
end;

{ The notice shows the output in the editor's font, as a terminal
  would. }
procedure TRepoFrame.ShowRemoteNotice;
begin
  FNoticeTimer.Enabled := False;
  if FRemoteJob = nil then
    Exit;
  FNotice.DetailFont.Assign(Edit.Font);
  FNotice.Popup(RemoteNoticeTitle, FRemoteJob.Progress, True);
end;

procedure TRepoFrame.NoticeTimerTimer(Sender: TObject);
begin
  ShowRemoteNotice;
end;

{ Once git itself reports the push, the hook has had its say. }
procedure TRepoFrame.RemoteJobOutput(Sender: TObject);
var
  Job: TGittanRemoteJob;
begin
  Job := TGittanRemoteJob(Sender);
  if Job <> FRemoteJob then
    Exit;
  if FNoticeHook and PushTransferStarted(Job.Progress) then
  begin
    FNoticeHook := False;
    if Job.Kind in [rkDeleteRemote, rkDeleteRemoteTag] then
      FStatus.ShowBusy(Format(rsDeletingRemote, [Job.Arg]), HintUp)
    else
      FStatus.ShowBusy(rsPushing, HintUp);
    FNotice.Title := RemoteNoticeTitle;
  end;
  if FNotice.Visible then
    FNotice.Detail := Job.Progress;
end;

{ The tree, the counts and the graph follow at once; then what came of
  it, or the choice git left to the user. }
procedure TRepoFrame.RemoteJobDone(Sender: TObject);
var
  Job: TGittanRemoteJob;
  HookFailed: boolean;
  Count: integer;
  Msg: string;
  Choice: TModalResult;
begin
  Job := TGittanRemoteJob(Sender);
  if Job <> FRemoteJob then
    Exit;
  MarkNews;
  { The push stopped before git reported anything of its own: the
    pre-push hook said no. }
  HookFailed := FNoticeHook and not PushTransferStarted(Job.Progress);
  FNoticeHook := False;
  FRemoteJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  FNoticeTimer.Enabled := False;
  FNotice.Close;
  FStatus.ShowMessage('', stNormal, 0);
  { Create Pull Request waits only for the push it started, so any
    other job, those that end below too, drops it. }
  if not (Job.Ok and (Job.Kind in [rkPush, rkPushBranch])) then
    FPullAfterPush := '';
  { A clone is of no open repository. }
  if Job.Kind = rkClone then
  begin
    UpdateRemoteItems;
    UpdateCommitState;
    CloneDone(Job);
    Exit;
  end;
  RefreshRepository;
  UpdateRemoteItems;
  UpdateCommitState;
  if Job.Kind = rkFetchPull then
  begin
    PullFetchDone(Job);
    Exit;
  end;
  if Job.Kind in [rkLfsLock, rkLfsUnlock, rkLfsForceUnlock] then
  begin
    LfsLockJobDone(Job);
    Exit;
  end;
  { The file is shown again, as the version downloaded into the store
    left the work tree as it was when it was of a commit. }
  if Job.Kind in [rkLfsFetch, rkLfsPull, rkLfsInstall] then
  begin
    if not Job.Ok then
      ShowRemoteFailure(Job, False)
    else
    begin
      case Job.Kind of
        rkLfsFetch: StatusNote(Format(rsLfsDownloaded, [ExtractFileName(Job.Arg)]));
        rkLfsPull: BannerSuccess(rsLfsPulled);
        rkLfsInstall: BannerSuccess(rsLfsInstalled);
      end;
      if (FView in [gvImage, gvBinary]) and (FCurrentPath <> '') then
        ShowChanges(FCurrentPath);
    end;
    { The work tree may hold files in place of pointers now. }
    FLfsChecked := '';
    CheckLfs;
    Exit;
  end;
  if Job.Kind in [rkSubmoduleUpdate, rkSubmoduleAdd] then
  begin
    SubmoduleRemoteDone(Job);
    if not Job.Ok then
      ShowRemoteFailure(Job, False);
    Exit;
  end;
  { A rebase or merge waits only for the fetch it started. }
  if not (Job.Ok and (Job.Kind = rkFetch)) then
    FAfterFetchRef := '';
  if Job.Ok then
  begin
    if Job.Kind = rkFetch then
      StartLfsLocks;
    case Job.Kind of
      rkFetch:
        if FAfterFetchRef <> '' then
          AfterFetch
        else if FHasUpstream and (FBehind = 1) then
          StatusNote(rsFetchedBehindOne)
        else if FHasUpstream and (FBehind > 1) then
          StatusNote(Format(rsFetchedBehind, [FBehind]))
        else
          StatusNote(rsFetched);
      rkPull:
        begin
          { The upstream's commits the old HEAD lacked: what came in,
            also when a rebase gave the local commits new ids. }
          Count := FRepo.CountCommits(FRemoteHead, '@{upstream}');
          if Count = 0 then
            BannerSuccess(Format(rsPulledNothing, [FBranch]))
          else if Count = 1 then
            BannerSuccess(Format(rsPulledOne, [FBranch]))
          else if Count > 1 then
            BannerSuccess(Format(rsPulledCount, [Count, FBranch]))
          else
            BannerSuccess(rsPulled);
        end;
      rkDeleteRemote:
        StatusNote(Format(rsDeletedRemote, [Job.Arg]));
      rkDeleteRemoteTag:
        StatusNote(Format(rsDeletedRemoteTag, [Job.Arg, Job.Remote]));
      rkForcePush:
        BannerSuccess(Format(rsForcePushed, [FBranch]));
      rkPushBranch:
        PushedBanner(Format(rsPushedBranchTo, [Job.Arg, Job.Remote + '/' + Job.Arg]),
          Job.Arg);
      rkPushTag:
        if Job.Arg = '' then
          BannerSuccess(Format(rsPushedTags, [Job.Remote]))
        else
          BannerSuccess(Format(rsPushedTag, [Job.Arg, Job.Remote]));
      rkPush:
        if FRemoteAhead = 1 then
          PushedBanner(Format(rsPushedOne, [FBranch]), FBranch)
        else if FRemoteAhead > 1 then
          PushedBanner(Format(rsPushed, [FRemoteAhead, FBranch]), FBranch)
        else
          PushedBanner(Format(rsPushedBranch, [FBranch]), FBranch);
    end;
    Exit;
  end;
  { A question names no repository: a frame in the background shows its
    tab before it asks. }
  if Job.Diverged or Job.Rejected or Job.Unseen or Job.Stale then
    FWindow.ShowFrame(Self);
  if Job.Diverged then
    case QuestionDlg(rsPullDivergedTitle, rsPullDiverged, mtConfirmation,
        [mrYes, rsMergeAction, 'IsDefault', mrNo, rsRebaseAction, mrCancel,
        rsCancelButton, 'IsCancel'], 0) of
      mrYes: StartRemote(rkPull, pmMerge);
      mrNo: StartRemote(rkPull, pmRebase);
    end
  else if Job.Rejected and FHasUpstream and (FBehind > 0) then
  begin
    { The upstream's commits the branch lacks are known here: they are
      to be pulled in, or, after a rewrite, replaced. }
    if FBehind = 1 then
      Msg := Format(rsPushRejectedDivergedOne, [FRepo.Upstream(FBranch)])
    else
      Msg := Format(rsPushRejectedDiverged, [FRepo.Upstream(FBranch), FBehind]);
    { Force Push first for a branch rewritten here, whose upstream holds
      only what it replaced. }
    if FRewritten then
      Choice := QuestionDlg(rsPushRejectedTitle, Msg + LineEnding + LineEnding +
        rsPushRejectedForce, mtConfirmation, [mrNo, rsForcePushAction, 'IsDefault', mrYes,
        rsPullAction, mrCancel, rsCancelButton, 'IsCancel'], 0)
    else
      Choice := QuestionDlg(rsPushRejectedTitle, Msg + LineEnding + LineEnding +
        rsPushRejectedForce, mtConfirmation, [mrYes, rsPullAction, 'IsDefault', mrNo,
        rsForcePushAction, mrCancel, rsCancelButton, 'IsCancel'], 0);
    case Choice of
      mrYes: StartRemote(rkPull, pmAuto);
      mrNo: StartRemote(rkForcePush);
    end;
  end
  else if Job.Rejected then
  begin
    if QuestionDlg(rsPushRejectedTitle, rsPushRejected, mtConfirmation,
      [mrYes, rsPullAction, 'IsDefault', mrCancel, rsCancelButton, 'IsCancel'], 0) = mrYes then
      StartRemote(rkPull, pmAuto);
  end
  else if Job.Unseen then
  begin
    if QuestionDlg(rsForceUnseenTitle, Format(rsForceUnseen, [FRepo.Upstream(FBranch)]),
      mtWarning, [mrYes, rsPullAction, 'IsDefault', mrCancel, rsCancelButton, 'IsCancel'],
      0) = mrYes then
      StartRemote(rkPull, pmAuto);
  end
  else if Job.Stale then
  begin
    if QuestionDlg(rsForceStaleTitle, Format(rsForceStale, [FRepo.Upstream(FBranch)]),
      mtWarning, [mrYes, rsFetchItem, 'IsDefault', mrCancel, rsCancelButton, 'IsCancel'],
      0) = mrYes then
      StartRemote(rkFetch);
  end
  else
    ShowRemoteFailure(Job, HookFailed);
end;

{ A failure is told in the notice, which stays: git's reason, a hook's
  output with it, in the editor's font with the end in view and the rest
  a scroll away, under a red title, with the same again and a copy of
  the output as its buttons. The status bar says it too, for a while. }
procedure TRepoFrame.ShowRemoteFailure(AJob: TGittanRemoteJob; AHookFailed: boolean);
var
  Title, Again: string;
begin
  case AJob.Kind of
    rkFetch:
      begin
        Title := rsFetchFailed;
        Again := rsFetchAgain;
      end;
    rkPull:
      begin
        Title := rsGitPullFailed;
        Again := rsPullAgain;
      end;
    rkPush, rkForcePush, rkPushBranch, rkPushTag:
      begin
        if AHookFailed then
          Title := rsHookFailed
        else
          Title := rsPushFailed;
        Again := rsPushAgain;
      end;
    rkClone:
      begin
        Title := rsCloneFailed;
        Again := rsCloneAgain;
      end;
    rkSubmoduleUpdate:
      begin
        Title := rsSubUpdateFailed;
        Again := rsSubUpdateAgain;
      end;
    rkSubmoduleAdd:
      begin
        Title := rsSubAddFailed;
        Again := rsTryAgain;
      end;
    rkFetchPull:
      begin
        Title := Format(rsPullFailed, [StrToIntDef(AJob.Arg, 0)]);
        Again := rsTryAgain;
      end;
    rkLfsFetch, rkLfsPull:
      begin
        Title := rsLfsDownloadFailed;
        Again := rsTryAgain;
      end;
    rkLfsInstall:
      begin
        Title := rsLfsInstallFailed;
        Again := rsTryAgain;
      end;
    rkLfsLock:
      begin
        Title := Format(rsLfsLockFailed, [AJob.Arg]);
        Again := rsTryAgain;
      end;
    rkLfsUnlock, rkLfsForceUnlock:
      begin
        Title := Format(rsLfsUnlockFailed, [AJob.Arg]);
        Again := rsTryAgain;
      end;
    else
      if AHookFailed then
        Title := rsHookFailed
      else
        Title := Format(rsDeleteRemoteFailed, [AJob.Arg]);
      Again := rsTryAgain;
  end;
  FRetryKind := AJob.Kind;
  FRetryMode := AJob.Mode;
  FRetryArg := AJob.Arg;
  FRetryRemote := AJob.Remote;
  FRetryRoot := AJob.Root;
  FRetrySubmodules := AJob.Submodules;
  FRetryPath := AJob.Path;
  FRetryBranch := AJob.Branch;
  FRetryRefs := AJob.Refs;
  FNoticeCommit := False;
  FStatus.ShowMessage(Title, stBad, StatusErrorSeconds);
  FNotice.DetailFont.Assign(Edit.Font);
  FNotice.Popup(Title, AJob.Error, False, nkBad);
  MarkNews;
  FNotice.SetButtons([Again, rsCopyOutput]);
end;

procedure TRepoFrame.NoticeButton(Sender: TObject; AIndex: integer);
begin
  case AIndex of
    0:
      begin
        FNotice.Close;
        { The message and the files chosen stay after a failed commit;
          a notice of one is closed when another repository opens. }
        if FNoticeCommit then
        begin
          StartCommit;
          Exit;
        end;
        { The failure was of the repository that was open then; a clone
          is of none. }
        if (FRetryKind <> rkClone) and (FRetryRoot <> FRepo.Root) then
          Exit;
        if FRetryKind = rkClone then
          StartClone(FRetryArg, FRetryRoot, FRetrySubmodules)
        { The dialog again, as the URL or path may be what was wrong. }
        else if FRetryKind = rkSubmoduleAdd then
          AddSubmoduleAsk(FRetryArg, FRetryPath, FRetryBranch)
        else if FRetryKind = rkFetchPull then
          StartPullFetch(StrToIntDef(FRetryArg, 0), FRetryRemote, FRetryBranch)
        else if FRetryKind = rkLfsFetch then
          StartLfsDownload(FRetryArg, FRetryRefs)
        else
          StartRemote(FRetryKind, FRetryMode, FRetryArg, FRetryRemote);
      end;
    1:
      begin
        Clipboard.AsText := FNotice.PlainDetail;
        StatusNote(rsOutputCopied);
      end;
  end;
end;

{ A job is never broken off: one still running when the repository
  changes goes on without a handler, and quitting waits for it. }
procedure TRepoFrame.StopRemoteJob(AWait: boolean);
begin
  FPendingRemote := False;
  StopLfsLocks;
  { The Git LFS check reads only, and is dropped rather than waited for. }
  if FLfsCheckJob <> nil then
  begin
    FLfsCheckJob.Stop(False);
    FBlameZombies.Add(FLfsCheckJob);
    FLfsCheckJob := nil;
  end;
  if FAutoFetchJob <> nil then
  begin
    FAutoFetchJob.Stop(AWait);
    if AWait then
      FAutoFetchJob.Free
    else
      FBlameZombies.Add(FAutoFetchJob);
    FAutoFetchJob := nil;
  end;
  if FRemoteJob = nil then
    Exit;
  FNoticeTimer.Enabled := False;
  FNotice.Close;
  FAfterFetchRef := '';
  FRemoteJob.Stop(AWait);
  if AWait then
    FRemoteJob.Free
  else
    FBlameZombies.Add(FRemoteJob);
  FRemoteJob := nil;
end;

{ ---------------------------------------------------------------------------
  Git LFS in the banner
  ---------------------------------------------------------------------------
  Once per commit checked out (the root and HEAD, FLfsChecked), after
  every snapshot that changed something, a job reads where the
  repository stands with Git LFS (TGittanRepo.LfsState). A repository
  with files in Git LFS gets a banner while something is wrong, the
  worst first: git-lfs not installed (a link to its site) or not set up
  (Set Up runs git lfs install), both red, as a commit would put the
  files' content in git; else, when files of the work tree are their
  pointers, a note with Download All (git lfs pull). A banner closed
  is not shown again until what it says changes (FLfsShown). }
procedure TRepoFrame.CheckLfs;
var
  Key: string;
begin
  if FRepo.Root = '' then
    Exit;
  Key := FRepo.Root + #0 + FSnapHead;
  { A check under way for another commit: LfsCheckDone sees the key
    changed and reads again. }
  if FLfsCheckJob <> nil then
  begin
    if Key <> FLfsChecked then
      FLfsChecked := '';
    Exit;
  end;
  if Key = FLfsChecked then
    Exit;
  FLfsChecked := Key;
  FLfsCheckJob := TGittanLfsCheckJob.Create(FRepo.Root, Key);
  FLfsCheckJob.OnDone := @LfsCheckDone;
  FLfsCheckJob.Start;
end;

procedure TRepoFrame.LfsCheckDone(Sender: TObject);
var
  Job: TGittanLfsCheckJob;
  State: TGittanLfsState;
  Title, Detail, ActionText, Key: string;
  Kind: TGittanBannerKind;
  Handler: TNotifyEvent;
begin
  Job := TGittanLfsCheckJob(Sender);
  if Job <> FLfsCheckJob then
    Exit;
  FLfsCheckJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  { Another repository, or a commit checked out meanwhile: read again. }
  if Job.Root <> FRepo.Root then
    Exit;
  if Job.Head <> FLfsChecked then
  begin
    CheckLfs;
    Exit;
  end;
  { Read again with the next snapshot. }
  if not Job.Ok then
  begin
    FLfsChecked := '';
    Exit;
  end;
  State := Job.State;
  FLfsLockable.Clear;
  FLfsLockable.AddStrings(State.Lockable);
  FLfsInstalled := State.Installed;
  if FLfsInstalled then
    StartLfsLocks
  else
    FLfsLocks := nil;
  { The note and the pills follow: locks gone with git-lfs, a file that
    may be locked now or no longer. }
  LockNote;
  if FView = gvBlob then
    BlobActions;
  Key := '';
  Kind := bkError;
  Handler := nil;
  if State.Files = 0 then
  else if not State.Installed then
  begin
    Title := rsLfsMissingTitle;
    Detail := Format(rsLfsMissingDetail, [State.Files]);
    ActionText := rsLfsGetAction;
    Handler := @LfsGetClick;
    Key := 'missing';
  end
  else if not State.SetUp then
  begin
    Title := rsLfsNotSetUpTitle;
    Detail := Format(rsLfsNotSetUpDetail, [State.Files]);
    ActionText := rsLfsSetUpAction;
    Handler := @LfsInstallClick;
    Key := 'setup';
  end
  else if State.Pointers > 0 then
  begin
    if State.Pointers = 1 then
      Title := rsLfsPointersOne
    else
      Title := Format(rsLfsPointers, [State.Pointers]);
    Detail := rsLfsPointersDetail;
    ActionText := rsLfsPullAction;
    Handler := @LfsPullClick;
    Kind := bkInfo;
    Key := 'pointers' + IntToStr(State.Pointers);
  end;
  if Key = FLfsShown then
    Exit;
  FLfsShown := Key;
  if Key <> '' then
    FBanner.AddAction(Title, Detail, Kind, 0, ActionText, Handler);
end;

procedure TRepoFrame.LfsGetClick(Sender: TObject);
begin
  OpenURL('https://git-lfs.com');
end;

procedure TRepoFrame.LfsInstallClick(Sender: TObject);
begin
  StartRemote(rkLfsInstall);
end;

procedure TRepoFrame.LfsPullClick(Sender: TObject);
begin
  StartRemote(rkLfsPull);
end;

{ ---------------------------------------------------------------------------
  The background fetch
  ---------------------------------------------------------------------------
  Once AutoFetchMinutes have passed since the repository was last
  fetched (FETCH_HEAD, so a fetch from the menu or a terminal counts
  too), a plain fetch runs in a job of its own, with no notice and no
  message, and only a repository with a remote is fetched. When it is
  done the counts follow; a failure (offline, a key that needs its
  passphrase) is left unsaid, as the next one may well work. A fetch,
  pull or push asked for meanwhile waits for it (see StartRemote).

  A failure leaves FETCH_HEAD as it was, so the try itself is kept
  (FAutoFetchTried): the next waits AutoFetchMinutes, twice that after
  two failures in a row and so on, up to AutoFetchBackoffMax times; a
  repository without a remote waits as after a failure. Nothing runs
  git before the wait is over. }
procedure TRepoFrame.AutoFetchTimerTimer(Sender: TObject);
const
  AutoFetchBackoffMax = 8;
var
  Last: TDateTime;
  Wait: integer;
begin
  if not App.Settings.AutoFetch or (FRepo.Root = '') or (FAutoFetchJob <> nil) or
    (FRemoteJob <> nil) then
    Exit;
  if FAutoFetchFails > 0 then
  begin
    Wait := App.Settings.AutoFetchMinutes * Min(AutoFetchBackoffMax,
      1 shl Min(FAutoFetchFails - 1, 3));
    if (Now - FAutoFetchTried) * MinsPerDay < Wait then
      Exit;
  end;
  Last := FRepo.LastFetch;
  if (Last > 0) and ((Now - Last) * MinsPerDay < App.Settings.AutoFetchMinutes) then
    Exit;
  FAutoFetchTried := Now;
  if FRepo.RemoteFor('') = '' then
  begin
    FAutoFetchFails := 1;
    Exit;
  end;
  FAutoFetchJob := TGittanRemoteJob.Create(FRepo.Root, rkFetch);
  FAutoFetchJob.OnDone := @AutoFetchDone;
  FAutoFetchJob.Start;
end;

procedure TRepoFrame.AutoFetchDone(Sender: TObject);
var
  Job: TGittanRemoteJob;
begin
  Job := TGittanRemoteJob(Sender);
  if Job <> FAutoFetchJob then
    Exit;
  FAutoFetchJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  if Job.Root = FRepo.Root then
    if Job.Ok then
      FAutoFetchFails := 0
    else
      Inc(FAutoFetchFails);
  if Job.Ok and (Job.Root = FRepo.Root) then
  begin
    RefreshRepository;
    StartLfsLocks;
  end;
  if FPendingRemote then
  begin
    FPendingRemote := False;
    FStatus.ShowMessage('', stNormal, 0);
    if FPendingKind = rkFetchPull then
      StartPullFetch(StrToIntDef(FPendingArg, 0), FPendingRemoteName, FPendingBranch)
    else
      StartRemote(FPendingKind, FPendingMode, FPendingArg, FPendingRemoteName);
  end;
end;

{ The file's versions ARefs (an empty one for the work tree) from Git
  LFS, for the header's Download. }
procedure TRepoFrame.StartLfsDownload(const APath: string; const ARefs: TStringArray);
begin
  FLfsRefs := ARefs;
  StartRemote(rkLfsFetch, pmAuto, APath);
end;

procedure TRepoFrame.MenuFetchClick(Sender: TObject);
begin
  StartRemote(rkFetch);
end;

procedure TRepoFrame.MenuPullClick(Sender: TObject);
begin
  StartRemote(rkPull);
end;

procedure TRepoFrame.MenuPushClick(Sender: TObject);
begin
  StartRemote(rkPush);
end;

{ Asks first, naming what the upstream loses: its commits the branch
  lacks, as the last fetch saw them. With none a plain push does. }
procedure TRepoFrame.ForcePushAsk;
var
  Up, Msg: string;
begin
  if (FRepo.Root = '') or (FRemoteJob <> nil) or (FCommitJob <> nil) then
    Exit;
  if not FHasUpstream then
  begin
    StatusNote(Format(rsForceNoUpstream, [FBranch]), True);
    Exit;
  end;
  if FBehind = 0 then
  begin
    StartRemote(rkPush);
    Exit;
  end;
  Up := FRepo.Upstream(FBranch);
  if FBehind = 1 then
    Msg := Format(rsForceAskOne, [FBranch, Up, Up])
  else
    Msg := Format(rsForceAsk, [FBranch, Up, FBehind, Up]);
  if QuestionDlg(rsForcePushTitle, Msg, mtWarning, [mrYes, rsForcePushAction, mrCancel,
    rsCancelButton, 'IsCancel', 'IsDefault'], 0) = mrYes then
    StartRemote(rkForcePush);
end;

procedure TRepoFrame.MenuForcePushClick(Sender: TObject);
begin
  ForcePushAsk;
end;

{ The status bar's "↑2 ↓5": pull and push with their counts, fetch,
  and the commit graph, which a click opened before. }
procedure TRepoFrame.SyncClick(const AScreenRect: TRect);

  procedure AddAction(AAction: integer; const ACaption, ADetail: string);
  begin
    FSyncPopup.Add(ACaption, ADetail, False, AAction);
  end;

var
  Detail: string;
begin
  if FRepo.Root = '' then
    Exit;
  FSyncPopup.Clear;
  if FRemoteJob = nil then
  begin
    Detail := '';
    if FHasUpstream and (FBehind > 0) then
      Detail := '↓' + IntToStr(FBehind);
    AddAction(saPull, rsGitPullItem, Detail);
    Detail := '';
    if not FHasUpstream then
      Detail := rsPushNewBranch
    else if FAhead > 0 then
      Detail := '↑' + IntToStr(FAhead);
    AddAction(saPush, rsPushItem, Detail);
    { Diverged, as after a rebase of pushed commits. }
    if FHasUpstream and (FAhead > 0) and (FBehind > 0) then
      AddAction(saForcePush, rsForcePushItem, Format(rsForcePushDetail, [FBehind]));
    AddAction(saFetch, rsFetchItem, '');
  end;
  AddAction(saGraph, rsCommitGraphItem, '');
  FSyncPopup.Popup(AScreenRect);
end;

{ The summary's sync line ("↑ 3 not pushed") drops the same list. }
procedure TRepoFrame.SummarySyncClick(Sender: TObject; const AScreenRect: TRect);
begin
  SyncClick(AScreenRect);
end;

procedure TRepoFrame.SyncPopupPick(Sender: TObject; AIndex: integer);
begin
  case FSyncPopup.TagOf(AIndex) of
    saPull: StartRemote(rkPull);
    saPush: StartRemote(rkPush);
    saForcePush: ForcePushAsk;
    saFetch: StartRemote(rkFetch);
    saGraph: ShowCommitGraph;
  end;
end;
