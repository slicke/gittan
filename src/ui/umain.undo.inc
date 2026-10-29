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

{ The branches checked out in the repository's other worktrees, which
  an undo leaves alone; false with AError when git cannot list them,
  since an undo could then move one of them. }
function TRepoFrame.OtherWorktreeBranches(out ABranches: TStringArray;
  out AError: string): boolean;
var
  List: TGittanWorktrees;
  i: integer;
begin
  ABranches := nil;
  Result := ListWorktrees(FRepo.Root, List, AError);
  if not Result then
    Exit;
  for i := 0 to High(List) do
    if (List[i].Branch <> '') and not IsThisWorktree(List[i]) then
      ABranches := Concat(ABranches, [List[i].Branch]);
end;

procedure TRepoFrame.UndoRedo(ARedo: boolean);
var
  Step: TGittanUndoStep;
  Current, Now, Target: TGittanRefState;
  Steps: TGittanGitSteps;
  Elsewhere: TStringArray;
  Err, Base: string;
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
  if not OtherWorktreeBranches(Elsewhere, Err) then
  begin
    BannerError(rsUndoFailed, Err);
    Exit;
  end;
  if ARedo then
    Ok := PlanRefChange(Current, Step.Before, Step.After, Step.Kind, Elsewhere, Steps, Err)
  else
    Ok := PlanRefChange(Current, Step.After, Step.Before, Step.Kind, Elsewhere, Steps, Err);
  if not Ok then
  begin
    StatusNote(Err, True);
    Exit;
  end;
  { HEAD's branch going back off commits its upstream has: the newest
    of them (where HEAD and the upstream meet) is not in the target. }
  if not ARedo and (Current.Branch <> '') and (Target.Branch = Current.Branch) and
    (Target.Head <> Current.Head) and FRepo.MergeBase('@{upstream}', Base) and
    not FRepo.IsAncestor(Base, Target.Head) then
  begin
    if AskDlg(rsUndoPushedTitle, Format(rsUndoPushedAsk,
      [Step.Title, FRepo.Upstream(Current.Branch), Current.Branch]), mtWarning,
      [mrYes, rsUndoAction, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes then
      Exit;
    { git elsewhere may have moved the branches while it asked. }
    if not FRepo.ReadRefState(Now) or not SameRefState(Now, Current) then
    begin
      StatusNote(rsUndoChanged, True);
      Exit;
    end;
  end;
  StopWatcher;
  try
    Screen.Cursor := crHourGlass;
    try
      Ok := FRepo.RunSteps(Steps);
      Err := FRepo.Error;
      { Noted as the step's own state, so the refresh finds no new
        step; a run that stopped halfway is a step of its own. When
        the branches cannot be read, the target stands for them. }
      if Ok and not FRepo.ReadRefState(Now) then
        Now := Target;
      if Ok then
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
