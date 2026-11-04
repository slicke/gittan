{ ---------------------------------------------------------------------------
  Putting changes into their commits
  ---------------------------------------------------------------------------
  Included by umain.pp. A changed block goes into the commit of the
  branch that last wrote its lines (gittan.absorb, what git absorb
  does): the pill Put into Its Commit over a block, or Changes > Put
  Change into Its Commit... for the block the caret is in, asks with
  the commit named and does it for that block alone; Commit > Put
  Changes into Their Commits... builds the plan for every ticked file
  and lists the changes in a dialog (gittan.absorbdlg), each with its
  commit or why it cannot be placed, to put all or some. Both commit
  the changes as fixup commits and replay the branch with them folded
  in, with the watcher stopped as for a rebase; what cannot be placed,
  or is not chosen, stays in the work tree (the rebase stashes it
  meanwhile). A rebase that stops goes to the Commit section as any
  does, and Branch > Undo takes a rebase that went through back.
  Offered while the tree chooses what to commit (CommitChoosing), HEAD
  is on a branch, no file is in conflict, Amend is off and nothing
  runs. }

{ Whether changes can be put into their commits now. }
function TRepoFrame.CanAbsorb: boolean;
begin
  Result := RepoReady and CommitChoosing and (FBranch <> '') and (FConflictFiles = 0) and
    (FCommitAmend <> nil) and not FCommitAmend.Checked;
end;

{ The plan for APaths, with the cursor busy; a failure is said in the
  banner and gives nil. }
function TRepoFrame.AbsorbPlanFor(APaths: TStrings): TGittanAbsorbPlan;
var
  Err: string;
  Ok: boolean;
begin
  Result := TGittanAbsorbPlan.Create;
  Screen.Cursor := crHourGlass;
  try
    Ok := Result.Build(FRepo, APaths, Err);
  finally
    Screen.Cursor := crDefault;
  end;
  if not Ok then
  begin
    FreeAndNil(Result);
    BannerError(rsAbsorbTitle, Err);
  end;
end;

{ How many of the plan's commits are pushed, for the question and the
  dialog; '' when none is. }
function TRepoFrame.AbsorbPushedNote(APlan: TGittanAbsorbPlan): string;
begin
  if APlan.Pushed = 1 then
    Result := rsRiPushedOne
  else if APlan.Pushed > 1 then
    Result := Format(rsRiPushed, [APlan.Pushed])
  else
    Result := '';
end;

{ The pill, or Changes > Put Change into Its Commit: the block goes
  into its commit after a question that names it; a block that cannot
  be placed says why in the banner. The block's raw hunk goes, kept
  lines inside it included. }
procedure TRepoFrame.AbsorbBlockAt(ABlock: integer);
var
  Plan: TGittanAbsorbPlan;
  Paths: TStringList;
  Pairs: TGittanKeepArray;
  Chosen: TBooleanDynArray;
  h: integer;
  Msg, Note: string;
begin
  if not CanAbsorb or not CanLeaveOut or (ABlock < 0) or (ABlock > High(FBlockStarts)) then
    Exit;
  Pairs := BlockPairs(FChangeLines, FBlockStarts[ABlock]);
  if Length(Pairs) = 0 then
    Exit;
  Paths := TStringList.Create;
  try
    Paths.Add(FCurrentPath);
    Plan := AbsorbPlanFor(Paths);
  finally
    Paths.Free;
  end;
  if Plan = nil then
    Exit;
  try
    h := Plan.HunkOf(FCurrentPath, Pairs[0]);
    if h < 0 then
    begin
      BannerError(rsAbsorbTitle, rsDiscardStale);
      Exit;
    end;
    if Plan.Hunks[h].Target < 0 then
    begin
      BannerError(rsAbsorbTitle, Format(rsAbsorbCannot, [Plan.Hunks[h].Line, FCurrentPath,
        Plan.Hunks[h].Reason]));
      Exit;
    end;
    with Plan.Steps[Plan.Hunks[h].Target] do
      Msg := Format(rsAbsorbAsk, [Plan.Hunks[h].Line, FCurrentPath, Short, Subject]);
    Note := AbsorbPushedNote(Plan);
    if Note <> '' then
      Msg := Msg + LineEnding + Note;
    Msg := Msg + LineEnding + rsAbsorbAskRewrites;
    if AskDlg(rsAbsorbTitle, Msg, mtConfirmation, [mrYes, rsAbsorbAction, mrCancel,
      rsCancelButton, 'IsCancel'], 0) <> mrYes then
      Exit;
    Chosen := nil;
    SetLength(Chosen, Length(Plan.Hunks));
    Chosen[h] := True;
    RunAbsorb(Plan, Chosen);
  finally
    Plan.Free;
  end;
end;

{ Commit > Put Changes into Their Commits...: the plan for the ticked
  files, in the dialog. }
procedure TRepoFrame.MenuAbsorbClick(Sender: TObject);
var
  Plan: TGittanAbsorbPlan;
  Paths: TStringList;
  Chosen: TBooleanDynArray;
begin
  if not CanAbsorb then
    Exit;
  Paths := TStringList.Create;
  try
    ChosenCommitPaths(Paths);
    if Paths.Count = 0 then
      Exit;
    Plan := AbsorbPlanFor(Paths);
  finally
    Paths.Free;
  end;
  if Plan = nil then
    Exit;
  try
    if Length(Plan.Hunks) = 0 then
    begin
      StatusNote(rsAbsorbNoChanges);
      Exit;
    end;
    if ChooseAbsorb(Plan, Chosen, AbsorbPushedNote(Plan)) then
      RunAbsorb(Plan, Chosen);
  finally
    Plan.Free;
  end;
end;

{ Changes > Put Change into Its Commit...: the block the caret is in. }
procedure TRepoFrame.MenuAbsorbChangeClick(Sender: TObject);
begin
  if Edit.Carets.Count > 0 then
    AbsorbBlockAt(BlockAtRow(Edit.Carets[0].PosY));
end;

{ The fixup commits and the rebase, as RebaseInteractiveAsk runs one:
  the watcher stopped, the repository read again after, the result in
  a banner or the status bar. The Commit section's Sign Off and Skip
  Hooks apply to the fixup commits. }
procedure TRepoFrame.RunAbsorb(APlan: TGittanAbsorbPlan; const AChosen: TBooleanDynArray);
var
  Options: TGittanCommitOptions;
  Ok, Conflicts, Stopped: boolean;
  Commits, i, First: integer;
  Err, StoppedAt: string;
begin
  Options := [];
  if FSignOff then
    Include(Options, coSignOff);
  if FSkipHooks then
    Include(Options, coNoVerify);
  First := -1;
  for i := 0 to High(AChosen) do
    if AChosen[i] and (APlan.Hunks[i].Target >= 0) and (First < 0) then
      First := i;
  StopWatcher;
  try
    Screen.Cursor := crHourGlass;
    try
      Ok := AbsorbRun(FRepo, APlan, AChosen, Options, Commits, Conflicts, Stopped, Err);
    finally
      Screen.Cursor := crDefault;
    end;
    FLoadError := '';
    FSummary.Notice := '';
    RefreshRepository;
  finally
    StartWatcher;
  end;
  UpdateCommitState;
  UpdateRemoteItems;
  if Ok then
  begin
    FSkipHooks := False;
    UpdateCommitOptions;
    { The commit's id is new after the rebase, so the subject alone. }
    if (Commits = 1) and (First >= 0) then
      Err := Format(rsAbsorbDoneOne, [APlan.Steps[APlan.Hunks[First].Target].Subject])
    else
      Err := Format(rsAbsorbDone, [Commits]);
    StatusNote(Err);
    BannerSuccess(Err);
  end
  else if Conflicts and (FRepo.Operation = '') then
    { The rebase went through and the stash it put back clashed: there
      is no rebase to continue, only the files to resolve. }
    BannerError(rsAbsorbFailed, Err)
  else if Conflicts then
    StatusNote(rsCaConflicts, True)
  else if Stopped then
  begin
    StoppedAt := FRepo.RebaseStoppedAt;
    if StoppedAt <> '' then
      StatusNote(Format(rsRebaseStoppedAt, [Copy(StoppedAt, 1, 7)]))
    else
      BannerError(rsRiStopped, Err);
  end
  else
    BannerError(rsAbsorbFailed, Err);
end;

{ The Commit and Changes menu items: the first while changes can be
  put into their commits and files are ticked, the second for the
  block the caret is in. }
procedure TRepoFrame.UpdateAbsorbItems;
begin
  if FAbsorbItem = nil then
    Exit;
  FAbsorbItem.Enabled := CanAbsorb and (FChosenCount > 0);
  FAbsorbChangeItem.Enabled := CanAbsorb and CanLeaveOut and (Edit.Carets.Count > 0) and
    (BlockAtRow(Edit.Carets[0].PosY) >= 0);
end;
