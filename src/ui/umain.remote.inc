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
  push the remote rejects offers to pull first; any other failure shows
  git's reason. }
const
  saPull = 0;
  saPush = 1;
  saFetch = 2;
  saGraph = 3;

procedure TForm1.UpdateRemoteItems;
var
  Can: boolean;
begin
  Can := (FRepo <> nil) and (FRepo.Root <> '') and (FRemoteJob = nil) and
    (FCommitJob = nil);
  if FFetchItem = nil then
    Exit;
  FFetchItem.Enabled := Can;
  FPullItem.Enabled := Can;
  FPushItem.Enabled := Can;
  UpdateBranchItems;
  UpdateStashItems;
end;

procedure TForm1.StartRemote(AKind: TGittanRemoteKind; AMode: TGittanPullMode;
  const AArg: string);
begin
  if (FRepo.Root = '') or (FRemoteJob <> nil) or (FCommitJob <> nil) then
    Exit;
  FRemoteAhead := FAhead;
  { What a pull brings in is counted from here when it is done. }
  if AKind = rkPull then
    FRemoteHead := FRepo.CommitId('HEAD')
  else
    FRemoteHead := '';
  FNoticeHook := (AKind = rkPush) and FRepo.HasHook('pre-push');
  FRemoteJob := TGittanRemoteJob.Create(FRepo.Root, AKind, AMode, AArg);
  FRemoteJob.OnDone := @RemoteJobDone;
  FRemoteJob.OnOutput := @RemoteJobOutput;
  FRemoteJob.Start;
  case AKind of
    rkFetch: FStatus.ShowMessage(rsFetching, stNormal, 0);
    rkPull: FStatus.ShowMessage(rsPulling, stNormal, 0);
    rkPush: if FNoticeHook then
        FStatus.ShowMessage(rsRunningHook, stNormal, 0)
      else
        FStatus.ShowMessage(rsPushing, stNormal, 0);
    rkDeleteRemote: FStatus.ShowMessage(Format(rsDeletingRemote, [AArg]), stNormal, 0);
  end;
  if FNoticeHook then
    ShowRemoteNotice
  else
    FNoticeTimer.Enabled := True;
  UpdateRemoteItems;
  UpdateCommitState;
end;

function TForm1.RemoteNoticeTitle: string;
begin
  Result := '';
  if FRemoteJob = nil then
    Exit;
  case FRemoteJob.Kind of
    rkFetch: Result := rsNoticeFetching;
    rkPull: Result := rsNoticePulling;
    rkPush: if FNoticeHook then
        Result := rsNoticeHook
      else
        Result := rsNoticePushing;
    rkDeleteRemote: Result := Format(rsNoticeDeleting, [FRemoteJob.Arg]);
  end;
end;

{ The notice shows the output in the editor's font, as a terminal
  would. }
procedure TForm1.ShowRemoteNotice;
begin
  FNoticeTimer.Enabled := False;
  if FRemoteJob = nil then
    Exit;
  FNotice.DetailFont.Assign(Edit.Font);
  FNotice.Popup(RemoteNoticeTitle, FRemoteJob.Progress, True);
end;

procedure TForm1.NoticeTimerTimer(Sender: TObject);
begin
  ShowRemoteNotice;
end;

{ Once git itself reports the push, the hook has had its say. }
procedure TForm1.RemoteJobOutput(Sender: TObject);
var
  Job: TGittanRemoteJob;
begin
  Job := TGittanRemoteJob(Sender);
  if Job <> FRemoteJob then
    Exit;
  if FNoticeHook and PushTransferStarted(Job.Progress) then
  begin
    FNoticeHook := False;
    FStatus.ShowMessage(rsPushing, stNormal, 0);
    FNotice.Title := RemoteNoticeTitle;
  end;
  if FNotice.Visible then
    FNotice.Detail := Job.Progress;
end;

{ The tree, the counts and the graph follow at once; then what came of
  it, or the choice git left to the user. }
procedure TForm1.RemoteJobDone(Sender: TObject);
var
  Job: TGittanRemoteJob;
  HookFailed: boolean;
  Count: integer;
begin
  Job := TGittanRemoteJob(Sender);
  if Job <> FRemoteJob then
    Exit;
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
  RefreshRepository;
  UpdateRemoteItems;
  UpdateCommitState;
  if Job.Ok then
  begin
    case Job.Kind of
      rkFetch:
        if FHasUpstream and (FBehind = 1) then
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
      rkPush:
        if FRemoteAhead = 1 then
          BannerSuccess(Format(rsPushedOne, [FBranch]))
        else if FRemoteAhead > 1 then
          BannerSuccess(Format(rsPushed, [FRemoteAhead, FBranch]))
        else
          BannerSuccess(Format(rsPushedBranch, [FBranch]));
    end;
    Exit;
  end;
  if Job.Diverged then
    case QuestionDlg(rsPullDivergedTitle, rsPullDiverged, mtConfirmation,
        [mrYes, rsMergeAction, 'IsDefault', mrNo, rsRebaseAction, mrCancel,
        rsCancelButton, 'IsCancel'], 0) of
      mrYes: StartRemote(rkPull, pmMerge);
      mrNo: StartRemote(rkPull, pmRebase);
    end
  else if Job.Rejected then
  begin
    if QuestionDlg(rsPushRejectedTitle, rsPushRejected, mtConfirmation,
      [mrYes, rsPullAction, 'IsDefault', mrCancel, rsCancelButton, 'IsCancel'], 0) = mrYes then
      StartRemote(rkPull, pmAuto);
  end
  else
    ShowRemoteFailure(Job, HookFailed);
end;

{ A failure is told in the notice, which stays: git's reason, a hook's
  output with it, in the editor's font with the end in view and the rest
  a scroll away, under a red title, with the same again and a copy of
  the output as its buttons. The status bar says it too, for a while. }
procedure TForm1.ShowRemoteFailure(AJob: TGittanRemoteJob; AHookFailed: boolean);
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
    rkPush:
      begin
        if AHookFailed then
          Title := rsHookFailed
        else
          Title := rsPushFailed;
        Again := rsPushAgain;
      end;
    else
      Title := Format(rsDeleteRemoteFailed, [AJob.Arg]);
      Again := rsTryAgain;
  end;
  FRetryKind := AJob.Kind;
  FRetryMode := AJob.Mode;
  FRetryArg := AJob.Arg;
  FStatus.ShowMessage(Title, stBad, StatusErrorSeconds);
  FNotice.DetailFont.Assign(Edit.Font);
  FNotice.Popup(Title, AJob.Error, False, nkBad);
  FNotice.SetButtons([Again, rsCopyOutput]);
end;

procedure TForm1.NoticeButton(Sender: TObject; AIndex: integer);
begin
  case AIndex of
    0:
      begin
        FNotice.Close;
        StartRemote(FRetryKind, FRetryMode, FRetryArg);
      end;
    1:
      begin
        Clipboard.AsText := FNotice.Detail;
        StatusNote(rsOutputCopied);
      end;
  end;
end;

{ A job is never broken off: one still running when the repository
  changes goes on without a handler, and quitting waits for it. }
procedure TForm1.StopRemoteJob(AWait: boolean);
begin
  if FRemoteJob = nil then
    Exit;
  FNoticeTimer.Enabled := False;
  FNotice.Close;
  FRemoteJob.Stop(AWait);
  if AWait then
    FRemoteJob.Free
  else
    FBlameZombies.Add(FRemoteJob);
  FRemoteJob := nil;
end;

procedure TForm1.MenuFetchClick(Sender: TObject);
begin
  StartRemote(rkFetch);
end;

procedure TForm1.MenuPullClick(Sender: TObject);
begin
  StartRemote(rkPull);
end;

procedure TForm1.MenuPushClick(Sender: TObject);
begin
  StartRemote(rkPush);
end;

{ The status bar's "↑2 ↓5": pull and push with their counts, fetch,
  and the commit graph, which a click opened before. }
procedure TForm1.SyncClick(const AScreenRect: TRect);

  procedure AddAction(AAction: integer; const ACaption, ADetail: string);
  begin
    FSyncPopup.Add(ACaption, ADetail);
    SetLength(FSyncActions, Length(FSyncActions) + 1);
    FSyncActions[High(FSyncActions)] := AAction;
  end;

var
  Detail: string;
begin
  if FRepo.Root = '' then
    Exit;
  FSyncPopup.Clear;
  FSyncActions := nil;
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
    AddAction(saFetch, rsFetchItem, '');
  end;
  AddAction(saGraph, rsCommitGraphItem, '');
  FSyncPopup.Popup(AScreenRect);
end;

{ The summary's sync line ("↑ 3 not pushed") drops the same list. }
procedure TForm1.SummarySyncClick(Sender: TObject; const AScreenRect: TRect);
begin
  SyncClick(AScreenRect);
end;

procedure TForm1.SyncPopupPick(Sender: TObject; AIndex: integer);
begin
  if (AIndex < 0) or (AIndex > High(FSyncActions)) then
    Exit;
  case FSyncActions[AIndex] of
    saPull: StartRemote(rkPull);
    saPush: StartRemote(rkPush);
    saFetch: StartRemote(rkFetch);
    saGraph: ShowCommitGraph;
  end;
end;
