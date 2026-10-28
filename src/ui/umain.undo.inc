{ ---------------------------------------------------------------------------
  Undo and Redo
  ---------------------------------------------------------------------------
  Branch > Undo <step> and Redo <step> take back what moved the branches
  and do it again: a commit, an amend, a merge, a cherry-pick, a revert,
  a reset, a pull, a rebase, a switch, a branch made, deleted or renamed,
  whether Gittan or git elsewhere did it. Every snapshot notes where the
  branches are (FUndoHistory.Track in ApplySnapshot); gittan.undo names
  the steps and plans the git commands. A step is only undone while the
  branches are as it left them, never while git is in the middle of
  something or a commit, fetch, pull or push runs, and git refuses a
  switch or a reset --keep an uncommitted change is in the way of, so
  nothing in the work tree is lost; a commit is undone with reset
  --soft, its changes left as they were. Undoing commits the upstream
  already has asks first, since the branch is then behind it. }

procedure TRepoFrame.UpdateUndoItems;

  function Amp(const AText: string): string;
  begin
    Result := StringReplace(AText, '&', '&&', [rfReplaceAll]);
  end;

begin
  if (FUndoItem = nil) or (FUndoHistory = nil) then
    Exit;
  if FUndoHistory.CanUndo then
    FUndoItem.Caption := Format(rsUndoItem, [Amp(FUndoHistory.UndoStep.Title)])
  else
    FUndoItem.Caption := rsUndoNone;
  if FUndoHistory.CanRedo then
    FRedoItem.Caption := Format(rsRedoItem, [Amp(FUndoHistory.RedoStep.Title)])
  else
    FRedoItem.Caption := rsRedoNone;
  FUndoItem.Enabled := (FRepo.Root <> '') and FUndoHistory.CanUndo and not RepoBusy;
  FRedoItem.Enabled := (FRepo.Root <> '') and FUndoHistory.CanRedo and not RepoBusy;
end;

procedure TRepoFrame.UndoRedo(ARedo: boolean);
var
  Step: TGittanUndoStep;
  Current, Now, Target: TGittanRefState;
  Steps: TGittanGitSteps;
  Err: string;
  Ok: boolean;
begin
  if (FRepo.Root = '') or (FUndoHistory = nil) then
    Exit;
  if RepoBusy then
  begin
    StatusNote(rsUndoBusy, True);
    Exit;
  end;
  if ARedo then
  begin
    if not FUndoHistory.CanRedo then
      Exit;
    Step := FUndoHistory.RedoStep;
    Target := Step.After;
  end
  else
  begin
    if not FUndoHistory.CanUndo then
      Exit;
    Step := FUndoHistory.UndoStep;
    Target := Step.Before;
  end;
  if not FRepo.ReadRefState(Current) then
  begin
    BannerError(rsUndoFailed, FRepo.Error);
    Exit;
  end;
  if ARedo then
    Ok := PlanRefChange(Current, Step.Before, Step.After, Step.Kind, Steps, Err)
  else
    Ok := PlanRefChange(Current, Step.After, Step.Before, Step.Kind, Steps, Err);
  if not Ok then
  begin
    StatusNote(Err, True);
    Exit;
  end;
  { HEAD's branch going back off commits its upstream has. }
  if not ARedo and (Current.Branch <> '') and (Target.Branch = Current.Branch) and
    (Target.Head <> Current.Head) and FRepo.IsAncestor(Current.Head, '@{upstream}') and
    not FRepo.IsAncestor(Current.Head, Target.Head) then
    if QuestionDlg(rsUndoPushedTitle, Format(rsUndoPushedAsk,
      [Step.Title, FRepo.Upstream(Current.Branch), Current.Branch]), mtWarning,
      [mrYes, rsUndoAction, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes then
      Exit;
  StopWatcher;
  try
    Screen.Cursor := crHourGlass;
    try
      Ok := FRepo.RunSteps(Steps);
      Err := FRepo.Error;
      { Noted as the step's own state, so the refresh finds no new
        step; a run that stopped halfway is a step of its own. }
      if Ok and FRepo.ReadRefState(Now) then
        if ARedo then
          FUndoHistory.Redone(Now)
        else
          FUndoHistory.Undone(Now);
    finally
      Screen.Cursor := crDefault;
    end;
    FLoadError := '';
    FSummary.Notice := '';
    RefreshRepository;
  finally
    StartWatcher;
  end;
  UpdateUndoItems;
  if Ok then
  begin
    if ARedo then
      StatusNote(Format(rsRedid, [Step.Title]))
    else
      StatusNote(Format(rsUndid, [Step.Title]));
    if FGraph.Visible then
      ShowCommitGraph;
  end
  else if ARedo then
    BannerError(rsRedoFailed, Err)
  else
    BannerError(rsUndoFailed, Err);
end;

procedure TRepoFrame.MenuUndoClick(Sender: TObject);
begin
  UndoRedo(False);
end;

procedure TRepoFrame.MenuRedoClick(Sender: TObject);
begin
  UndoRedo(True);
end;
