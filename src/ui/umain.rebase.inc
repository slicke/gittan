{ ---------------------------------------------------------------------------
  Interactive rebase
  ---------------------------------------------------------------------------
  The commits of the current
  branch since AOnto in a dialog (gittan.rebasedlg), each to be picked,
  reworded, edited, squashed or fixed up into the one below it, or
  dropped, in any order, then replayed onto AOnto by
  TGittanRepo.RebaseInteractive (gittan.rebase builds git's todo list).
  Rebase Interactively from Here... in the commit menu lists the
  commits after that commit (AFromGraph, which opens the graph again
  with the result), and Choose Commits... in the question a rebase of
  the branch onto another asks lists those the rebase would replay. A
  rebase that stops with conflicts, or at a commit to edit, is left to
  the Commit section, whose Continue goes on with it; the stop at an
  edit is said in the status bar and under the Commit button. The
  watcher is stopped meanwhile, as for a switch. }
procedure TForm1.RebaseInteractiveAsk(const AOnto, AName: string; AFromGraph: boolean);
var
  Steps: TGittanRebaseSteps;
  Merges, Ok, Conflicts, Stopped: boolean;
  Pushed, i: integer;
  Title, Note, StoppedAt: string;
begin
  if not RepoReady or (FBranch = '') then
    Exit;
  if not FRepo.RebaseSteps(AOnto, Steps, Merges) then
  begin
    BannerError(rsCaFailed, FRepo.Error);
    Exit;
  end;
  if Length(Steps) = 0 then
  begin
    StatusNote(Format(rsRiNothing, [FBranch, AName]));
    Exit;
  end;
  if Merges then
  begin
    BannerError(rsBmRebaseTitle, Format(rsRiMerges, [FBranch, AName]));
    Exit;
  end;
  Pushed := 0;
  for i := 0 to High(Steps) do
    if Steps[i].Pushed then
      Inc(Pushed);
  if Pushed = 1 then
    Note := rsRiPushedOne
  else if Pushed > 1 then
    Note := Format(rsRiPushed, [Pushed])
  else
    Note := '';
  if AFromGraph then
    Title := Format(rsRiTitleFrom, [FBranch, AName])
  else
    Title := Format(rsBmRebase, [FBranch, AName]);
  if not EditRebase(Steps, Title, Note) then
    Exit;
  StopWatcher;
  try
    Screen.Cursor := crHourGlass;
    try
      Ok := FRepo.RebaseInteractive(AOnto, Steps, Conflicts, Stopped);
    finally
      Screen.Cursor := crDefault;
    end;
    FLoadError := '';
    FSummary.Notice := '';
    RefreshRepository;
  finally
    StartWatcher;
  end;
  if Ok then
  begin
    StatusNote(Format(rsRiDone, [FBranch]));
    BannerSuccess(Format(rsRiDone, [FBranch]));
    if AFromGraph then
      ShowCommitGraph;
  end
  else if Conflicts then
    StatusNote(rsCaConflicts, True)
  else if Stopped then
  begin
    StoppedAt := FRepo.RebaseStoppedAt;
    if StoppedAt <> '' then
      StatusNote(Format(rsRebaseStoppedAt, [Copy(StoppedAt, 1, 7)]))
    else
      BannerError(rsRiStopped, FRepo.Error);
  end
  else
    BannerError(rsCaFailed, FRepo.Error);
end;
