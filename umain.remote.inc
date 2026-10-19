{ ---------------------------------------------------------------------------
  Fetch, pull and push
  ---------------------------------------------------------------------------
  File > Fetch, Pull and Push, and the same in a list that drops up from
  the status bar's "↑2 ↓5", with the commit graph last. Each runs in a
  thread (gittan.remotejob), one at a time and not while a commit runs;
  the status bar says what is going on meanwhile. A pull that finds the
  branch diverged asks whether to merge or rebase, a push the remote
  rejects offers to pull first; any other failure shows git's reason. }
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
end;

procedure TForm1.StartRemote(AKind: TGittanRemoteKind; AMode: TGittanPullMode;
  const AArg: string);
begin
  if (FRepo.Root = '') or (FRemoteJob <> nil) or (FCommitJob <> nil) then
    Exit;
  FRemoteAhead := FAhead;
  FRemoteJob := TGittanRemoteJob.Create(FRepo.Root, AKind, AMode, AArg);
  FRemoteJob.OnDone := @RemoteJobDone;
  FRemoteJob.Start;
  case AKind of
    rkFetch: FStatus.ShowMessage(rsFetching, stNormal, 0);
    rkPull: FStatus.ShowMessage(rsPulling, stNormal, 0);
    rkPush: FStatus.ShowMessage(rsPushing, stNormal, 0);
    rkDeleteRemote: FStatus.ShowMessage(Format(rsDeletingRemote, [AArg]), stNormal, 0);
  end;
  UpdateRemoteItems;
  UpdateCommitState;
end;

{ The tree, the counts and the graph follow at once; then what came of
  it, or the choice git left to the user. }
procedure TForm1.RemoteJobDone(Sender: TObject);
var
  Job: TGittanRemoteJob;
begin
  Job := TGittanRemoteJob(Sender);
  if Job <> FRemoteJob then
    Exit;
  FRemoteJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
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
        StatusNote(rsPulled);
      rkDeleteRemote:
        StatusNote(Format(rsDeletedRemote, [Job.Arg]));
      rkPush:
        if FRemoteAhead = 1 then
          StatusNote(Format(rsPushedOne, [FBranch]))
        else if FRemoteAhead > 1 then
          StatusNote(Format(rsPushed, [FRemoteAhead, FBranch]))
        else
          StatusNote(Format(rsPushedBranch, [FBranch]));
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
    case Job.Kind of
      rkFetch: MessageDlg(rsFetchFailed, Job.Error, mtError, [mbOK], 0);
      rkPull: MessageDlg(rsGitPullFailed, Job.Error, mtError, [mbOK], 0);
      rkPush: MessageDlg(rsPushFailed, Job.Error, mtError, [mbOK], 0);
      rkDeleteRemote: MessageDlg(Format(rsDeleteRemoteFailed, [Job.Arg]), Job.Error,
          mtError, [mbOK], 0);
    end;
end;

{ A job is never broken off: one still running when the repository
  changes goes on without a handler, and quitting waits for it. }
procedure TForm1.StopRemoteJob(AWait: boolean);
begin
  if FRemoteJob = nil then
    Exit;
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
