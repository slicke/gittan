{ ---------------------------------------------------------------------------
  Resolving conflicts
  ---------------------------------------------------------------------------
  A conflicted file offers Use Mine, Use Theirs and Mark Resolved as
  pills in its header (and the toolbar on macOS) and in the file menu.
  Mine is the user's own work and theirs what came in, whichever of
  git's ours and theirs that is (TGittanConflictSide). Taking a side
  asks first, since the edits made to the file are lost; marking a file
  that still has conflict markers asks too. One conflict at a time is
  resolved from the view: every conflict gets a button in the discard
  band (umain.discard.inc) on its "<<<<<<<" row, and the button, File >
  Resolve Conflict (for the one the caret is in) or the editor menu
  drops down a list of what to put in its place, mine, theirs or both in
  either order, with the names git wrote on the markers; the conflict's
  lines are replaced on disk through gittan.discard (ResolveBlock in
  gittan.conflicts gives the block), so the file must still hold them,
  and the block is kept with the discards, so File > Undo Discard puts
  the conflict back. When the file's last conflict goes, the file is
  marked resolved and the view moves on to the next conflicted file, or
  to the Commit section when there is none; resolving a whole file moves
  on the same way. The conflict badge in the status bar drops down the
  conflicted files with the conflicts left in each. What git is in the
  middle of is carried on in the Commit section (umain.commit.inc): a
  merge is committed there with git's message filled in, a rebase,
  cherry-pick, revert or am goes on with Continue (or Skip), and any of
  them can be given up with Abort. These run on the main thread: they
  are local and quick, and nothing else may touch the repository
  meanwhile. }

{ The operation as a noun for the dialogs and notes. }
function OperationNoun(const AOperation: string): string;
begin
  if AOperation = 'merging' then
    Result := rsNounMerge
  else if AOperation = 'rebasing' then
    Result := rsNounRebase
  else if AOperation = 'cherry-picking' then
    Result := rsNounCherryPick
  else if AOperation = 'reverting' then
    Result := rsNounRevert
  else
    Result := rsNounPatches;
end;

{ Whether git is in the middle of something the Commit section carries
  on with Continue rather than a commit of its own. }
function TRepoFrame.ContinueMode: boolean;
begin
  Result := ((FOperation = 'rebasing') and not StrayRebase) or
    (FOperation = 'applying patches') or (FOperation = 'cherry-picking') or
    (FOperation = 'reverting');
end;

{ A rebase left behind: it stopped, and a checkout in a terminal put HEAD
  on another branch (git allows it once the conflicts are resolved). git
  still counts the rebase as going on, and its --continue would set the
  rebased branch to HEAD, so Continue and Skip are off; Abort checks the
  rebased branch out again as it was, and Forget the Rebase (--quit)
  keeps HEAD where it is. }
function TRepoFrame.StrayRebase: boolean;
begin
  Result := (FOperation = 'rebasing') and (FRebaseBranch <> '') and (FBranch <> FRebaseBranch);
end;

{ The operation for the summary and the status bar: "rebasing", or
  "rebasing feature" while the rebase is of a branch HEAD is not on. }
function TRepoFrame.OperationLabel: string;
begin
  if StrayRebase then
    Result := Format(rsOperationOf, [FOperation, FRebaseBranch])
  else
    Result := FOperation;
end;

function TRepoFrame.IsConflictPath(const APath: string): boolean;
var
  i: integer;
begin
  i := StatIndexOf(APath);
  Result := (i >= 0) and (FStats[i].Kind = ckConflict);
end;

{ How many conflicts are left in the file APath on disk, by its markers. }
function TRepoFrame.MarkersLeft(const APath: string): integer;
var
  Lines: TStringList;
  i: integer;
begin
  Result := 0;
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(APath));
    except
      Exit;
    end;
    for i := 0 to Lines.Count - 1 do
      Lines[i] := ' ' + Lines[i];
    Result := ConflictCount(ConflictRoles(Lines), Lines);
  finally
    Lines.Free;
  end;
end;

{ AAction: 0 mine, 1 theirs, 2 resolved as it is. }
procedure TRepoFrame.ResolvePath(const APath: string; AAction: integer);
var
  Ok: boolean;
  Remaining: integer;
  Side: string;
begin
  if (FRepo.Root = '') or not IsConflictPath(APath) then
    Exit;
  if AAction = 2 then
  begin
    Remaining := MarkersLeft(APath);
    if (Remaining > 0) and (AskDlg(rsMarkResolvedTitle, Format(rsMarkersLeft, [APath, Remaining]),
      mtConfirmation, [mrYes, rsMarkResolved, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'],
      0) <> mrYes) then
      Exit;
    Ok := FRepo.MarkResolved(APath);
  end
  else
  begin
    if AAction = 0 then
      Side := rsSideMine
    else
      Side := rsSideTheirs;
    { Taking one side drops the other's changes, with no undo: Cancel is
      the default, as for Revert, Remove and Clean. }
    if AskDlg(rsResolveTitle, Format(rsResolveAsk, [APath, Side]), mtConfirmation,
      [mrYes, rsResolveAction, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes then
      Exit;
    if AAction = 0 then
      Ok := FRepo.ResolveConflict(APath, csMine)
    else
      Ok := FRepo.ResolveConflict(APath, csTheirs);
  end;
  if Ok then
    StatusNote(Format(rsResolved, [APath]))
  else
    StatusNote(Format(rsResolveFailed, [APath, FRepo.Error]), True);
  RefreshRepository;
  if Ok then
    ShowNextConflict(APath, (APath = FCurrentPath) and
      (FView in [gvChanges, gvImage, gvBinary, gvMerge]));
end;

{ ---------------------------------------------------------------------------
  One conflict at a time
  --------------------------------------------------------------------------- }

{ Whether the shown file's conflicts can be resolved one by one: the
  change view of a conflicted file with markers, against the work tree. }
function TRepoFrame.CanResolveBlocks: boolean;
begin
  Result := (FRepo <> nil) and (FView = gvChanges) and (FCurrentPath <> '') and
    (FEditPath = '') and not FRepo.IsRange and (Length(FConflictStarts) > 0) and
    IsConflictPath(FCurrentPath);
end;

{ The row of each conflict's "<<<<<<<" line (FConflictRows from
  FConflictStarts) and of its last line (FConflictEndRows from
  FConflictEnds), from the rows of the view just built: the lines are
  added ones, so they are on the new side. }
procedure TRepoFrame.FindConflictRows;

  procedure Find(const ALines: TIntegerDynArray; var ARows: TIntegerDynArray);
  var
    c, r: integer;
  begin
    SetLength(ARows, Length(ALines));
    for c := 0 to High(ARows) do
      ARows[c] := -1;
    c := 0;
    for r := 0 to High(FRows) do
    begin
      if c > High(ALines) then
        Break;
      if FRows[r].Line = ALines[c] then
      begin
        ARows[c] := r;
        Inc(c);
      end;
    end;
  end;

begin
  Find(FConflictStarts, FConflictRows);
  Find(FConflictEnds, FConflictEndRows);
end;

{ The conflict the line on row ARow belongs to, or -1 for a line outside
  every conflict (a deleted line is never inside one). }
function TRepoFrame.ConflictAtRow(ARow: integer): integer;
var
  Line, c: integer;
begin
  Result := -1;
  if (ARow < 0) or (ARow > High(FRows)) then
    Exit;
  Line := FRows[ARow].Line;
  if (Line < 0) or (Line > High(FConflictRoles)) or (FConflictRoles[Line] = crNone) then
    Exit;
  for c := High(FConflictStarts) downto 0 do
    if FConflictStarts[c] <= Line then
      Exit(c);
end;

{ Drops the choice down from the conflict's button: mine, theirs or
  both, with the names on the markers as details. Mine is the user's
  own work, git's theirs in a rebase (see TGittanConflictSide). }
procedure TRepoFrame.ResolveConflictAt(AIndex: integer);
var
  Ours, Theirs, Mine, Incoming: string;
  Rebase: boolean;
  Band, Y, L, R: integer;
  Anchor: TRect;

  procedure AddPick(const ACaption, ADetail: string; APick: TGittanConflictPick);
  var
    i: integer;
  begin
    i := FConflictPopup.Add(ACaption, ADetail);
    SetLength(FConflictPicks, i + 1);
    FConflictPicks[i] := APick;
  end;

begin
  if not CanResolveBlocks or (AIndex < 0) or (AIndex > High(FConflictStarts)) or
    (AIndex > High(FConflictRows)) or (FConflictRows[AIndex] < 0) then
    Exit;
  ConflictSides(FChangeLines, FConflictRoles, FConflictStarts[AIndex], Ours, Theirs);
  Rebase := FOperation = 'rebasing';
  if Rebase then
  begin
    Mine := Theirs;
    Incoming := Ours;
  end
  else
  begin
    Mine := Ours;
    Incoming := Theirs;
  end;
  FResolveIndex := AIndex;
  FConflictPopupFiles := False;
  FConflictPicks := nil;
  FConflictPopup.Clear;
  FConflictPopup.AddHeader(Format(rsResolveBlockTitle, [AIndex + 1, Length(FConflictStarts)]));
  if Rebase then
  begin
    AddPick(rsUseMine, Mine, cpTheirs);
    AddPick(rsUseTheirs, Incoming, cpOurs);
    AddPick(rsUseBothMineFirst, '', cpTheirsThenOurs);
    AddPick(rsUseBothTheirsFirst, '', cpOursThenTheirs);
  end
  else
  begin
    AddPick(rsUseMine, Mine, cpOurs);
    AddPick(rsUseTheirs, Incoming, cpTheirs);
    AddPick(rsUseBothMineFirst, '', cpOursThenTheirs);
    AddPick(rsUseBothTheirsFirst, '', cpTheirsThenOurs);
  end;
  { The agent's, or its stop while it resolves one (umain.ai.inc). }
  FConflictAIItem := -1;
  if AIAvailable then
    if FConflictJob <> nil then
      FConflictAIItem := FConflictPopup.Add(Format(rsResolveAIStop, [AgentName]), HintSparkle)
    else
      FConflictAIItem := FConflictPopup.Add(Format(rsResolveAI, [AgentName]), HintSparkle);
  { Line by line, in three panes (umain.merge.inc). }
  FConflictMergeItem := FConflictPopup.Add(rsMergeEditorPick, '');
  { Under the button, or under the row's start when the band is not
    there to anchor to. }
  Band := Edit.Gutter.FindIndexByTag(gutterTagDiscard);
  if (Band >= 0) and Edit.Gutter[Band].Visible then
  begin
    L := Edit.Gutter[Band].Left;
    R := Edit.Gutter[Band].Right;
  end
  else
  begin
    L := Edit.RectMain.Left;
    R := L + Edit.TextCharSize.Y;
  end;
  Y := Edit.CaretPosToClientPos(Point(0, FConflictRows[AIndex])).Y;
  Anchor := Rect(L, Y, R, Y + Edit.TextCharSize.Y);
  Anchor.TopLeft := Edit.ClientToScreen(Anchor.TopLeft);
  Anchor.BottomRight := Edit.ClientToScreen(Anchor.BottomRight);
  SetHotDiscard(Edit, -1, -1, -1);
  { The button's hint would stay over the list. }
  ClearHover;
  FConflictPopup.Popup(Anchor);
end;

{ Writes the pick over the conflict and refreshes. }
procedure TRepoFrame.ApplyConflictPick(AIndex: integer; APick: TGittanConflictPick);
begin
  if not CanResolveBlocks or (AIndex < 0) or (AIndex > High(FConflictStarts)) then
    Exit;
  WriteConflictBlock(ResolveBlock(FChangeLines, FConflictRoles, FConflictStarts[AIndex],
    APick, IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(FCurrentPath)),
    FCurrentPath, True);
end;

{ Writes ABlock over its conflict in APath (refused when the file no
  longer holds it) and keeps it for Undo Discard. The last conflict of
  the file marks it resolved and, with AAdvance, moves on to the next
  file. AAgent's resolution says what it kept (AWhy) in the status bar. }
procedure TRepoFrame.WriteConflictBlock(const ABlock: TGittanDiscard; const APath: string;
  AAdvance: boolean; const AAgent: string; const AWhy: string);
var
  B: TGittanDiscard;
  Path, Err, Why: string;
  Remaining: integer;
  Marked: boolean;
begin
  B := ABlock;
  Path := APath;
  if not DiscardBlock(B, Err) then
  begin
    StatusNote(Format(rsResolveBlockFailed, [Err]), True);
    Exit;
  end;
  SetLength(FDiscards, Length(FDiscards) + 1);
  FDiscards[High(FDiscards)] := B;
  Remaining := MarkersLeft(Path);
  Marked := False;
  if Remaining = 0 then
  begin
    Marked := FRepo.MarkResolved(Path);
    if not Marked then
      StatusNote(Format(rsResolveFailed, [Path, FRepo.Error]), True);
    { Undo Discard puts the conflict back in the index too. }
    FDiscards[High(FDiscards)].Resolved := Marked;
  end;
  RefreshRepository;
  UpdateDiscardItems;
  if AAgent <> '' then
  begin
    Why := AWhy;
    if Why = '' then
      Why := rsResolvedAIUndo;
    if Marked then
      StatusNote(Format(rsResolvedAILast, [AAgent, Path, Why]))
    else
      StatusNote(Format(rsResolvedAI, [AAgent, B.Line, Path, Why]));
    if Marked then
      ShowNextConflict(Path, AAdvance);
  end
  else if Marked then
  begin
    StatusNote(Format(rsResolvedLast, [Path]));
    ShowNextConflict(Path, AAdvance);
  end
  else if Remaining = 1 then
    StatusNote(Format(rsResolvedBlockOne, [B.Line, Path]))
  else if Remaining > 1 then
    StatusNote(Format(rsResolvedBlock, [B.Line, Path, Remaining]));
end;

procedure TRepoFrame.ConflictPopupPick(Sender: TObject; AIndex: integer);
begin
  if FConflictPopupFiles then
  begin
    if (AIndex >= 0) and (AIndex <= High(FConflictPaths)) and (FConflictPaths[AIndex] <> '') then
      SummarySelectFile(Sender, FConflictPaths[AIndex]);
    Exit;
  end;
  if AIndex = FConflictMergeItem then
    OpenMergeEditor
  else if (FConflictAIItem >= 0) and (AIndex = FConflictAIItem) then
  begin
    if FConflictJob <> nil then
    begin
      AbandonConflictJob;
      FStatus.ShowMessage('', stNormal, 0);
    end
    else
      StartConflictJob(FResolveIndex);
  end
  else if (AIndex >= 0) and (AIndex <= High(FConflictPicks)) then
    ApplyConflictPick(FResolveIndex, FConflictPicks[AIndex]);
  FResolveIndex := -1;
end;

{ The conflicts left in APath for the list: by its markers, or that it
  is gone (one side deleted it) or holds no markers (ready to be marked
  resolved). }
function TRepoFrame.ConflictDetail(const APath: string): string;
var
  n: integer;
begin
  if not FileExists(IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(APath)) then
    Exit(rsConflictGone);
  n := MarkersLeft(APath);
  if n = 0 then
    Result := rsConflictNoMarkers
  else if n = 1 then
    Result := rsConflictInFile
  else
    Result := Format(rsConflictsInFile, [n]);
end;

{ The status bar's conflict badge drops down the conflicted files, the
  shown one checked; a pick shows the file. }
procedure TRepoFrame.ConflictBadgeClick(const AScreenRect: TRect);
var
  i, Index: integer;
begin
  if (FRepo.Root = '') or (FConflictFiles = 0) then
    Exit;
  FConflictPopupFiles := True;
  FConflictPaths := nil;
  FConflictPopup.Clear;
  if FConflictFiles = 1 then
    FConflictPopup.AddHeader(rsOneConflictedFile)
  else
    FConflictPopup.AddHeader(Format(rsConflictedFiles, [FConflictFiles]));
  for i := 0 to High(FStats) do
    if FStats[i].Kind = ckConflict then
    begin
      Index := FConflictPopup.Add(FStats[i].Path, ConflictDetail(FStats[i].Path),
        (FStats[i].Path = FCurrentPath) and (FView in [gvChanges, gvImage, gvBinary, gvMerge]));
      SetLength(FConflictPaths, Index + 1);
      FConflictPaths[Index] := FStats[i].Path;
    end;
  FConflictPopup.Popup(AScreenRect);
end;

{ The conflicted file after (or before, not ANext) AAfter in the tree,
  round the end, other than AAfter itself; '' for none. }
function TRepoFrame.NextConflictFile(const AAfter: string; ANext: boolean): string;
var
  Start, i, k, n: integer;
begin
  Result := '';
  n := Length(FStats);
  if n = 0 then
    Exit;
  Start := -1;
  for i := 0 to n - 1 do
    if FStats[i].Path = AAfter then
      Start := i;
  if (Start < 0) and not ANext then
    Start := n;
  for k := 1 to n do
  begin
    if ANext then
      i := (Start + k) mod n
    else
      i := (Start - k + n) mod n;
    if (FStats[i].Kind = ckConflict) and (FStats[i].Path <> AAfter) then
      Exit(FStats[i].Path);
  end;
end;

{ After AAfter was resolved: the next conflicted file after it in the
  tree (round the end) is shown when AAdvance, the resolved file being
  the one shown; with no conflict left the Commit section is the next
  step, so it gets the focus, the message field for a merge and the
  Continue button for the rest, and the status bar says so. }
procedure TRepoFrame.ShowNextConflict(const AAfter: string; AAdvance: boolean);
var
  Following: string;
begin
  if FRepo.Root = '' then
    Exit;
  if FConflictFiles > 0 then
  begin
    Following := NextConflictFile(AAfter, True);
    if AAdvance and (Following <> '') then
      SummarySelectFile(Self, Following);
    Exit;
  end;
  if FOperation = 'merging' then
  begin
    MenuCommitClick(nil);
    StatusNote(rsAllResolvedCommit);
  end
  else if ContinueMode then
  begin
    if not FCommitHeader.Expanded then
    begin
      FCommitHeader.Expanded := True;
      CommitHeaderToggle(nil);
    end;
    if FCommitButton.CanFocus then
      FCommitButton.SetFocus;
    StatusNote(Format(rsAllResolvedContinue, [OperationNoun(FOperation)]));
  end
  else
    StatusNote(rsAllResolved);
end;

{ Go > Next/Previous Conflict (F6, Shift+F6) and the conflict navigator
  go to the next (or previous) conflict from the caret, as GoToChange
  goes to the next change; past the last (or before the first) they go
  on to the next (or previous) conflicted file in the tree, and wrap
  around in the file when there is no other. }
procedure TRepoFrame.GoToConflict(ANext: boolean);
var
  Rows: TIntegerDynArray;
  Cur, Target, i: integer;
  Other: string;
begin
  { The merge editor steps through its own conflicts, on to the next
    file past its last. }
  if (FView = gvMerge) and FMergeView.GoToConflict(ANext) then
    Exit;
  Rows := nil;
  if (FView = gvChanges) and IsConflictPath(FCurrentPath) then
    Rows := FConflictRows;
  Target := -1;
  if Length(Rows) > 0 then
  begin
    Cur := Edit.Carets[0].PosY;
    if ANext then
    begin
      for i := 0 to High(Rows) do
        if Rows[i] > Cur then
        begin
          Target := Rows[i];
          Break;
        end;
    end
    else
      for i := High(Rows) downto 0 do
        if Rows[i] < Cur then
        begin
          Target := Rows[i];
          Break;
        end;
  end;
  if Target < 0 then
  begin
    Other := NextConflictFile(FCurrentPath, ANext);
    if Other <> '' then
    begin
      SummarySelectFile(Self, Other);
      Rows := nil;
      if (FView = gvChanges) and (FCurrentPath = Other) then
        Rows := FConflictRows;
    end;
    if Length(Rows) = 0 then
      Exit;
    if ANext then
      Target := Rows[0]
    else
      Target := Rows[High(Rows)];
  end;
  ShowChangeAt(Target);
end;

{ The Resolve pill of a conflicted file's row in the summary shows the
  file at its first conflict, where the band's buttons resolve it; a
  file without markers (deleted on one side) shows its header's pills. }
procedure TRepoFrame.SummaryRowAction(Sender: TObject; const APath: string);
begin
  SummarySelectFile(Sender, APath);
  if (FView = gvChanges) and (FCurrentPath = APath) and (Length(FConflictRows) > 0) then
    ShowChangeAt(FConflictRows[0]);
end;

procedure TRepoFrame.MenuNextConflictClick(Sender: TObject);
begin
  GoToConflict(True);
end;

procedure TRepoFrame.MenuPrevConflictClick(Sender: TObject);
begin
  GoToConflict(False);
end;

{ File > Resolve Conflict acts on the conflict the caret is in; the
  item follows the caret (from UpdateDiscardItems). }
procedure TRepoFrame.UpdateResolveItems;
begin
  if FMergeEditorItem <> nil then
    FMergeEditorItem.Enabled := (FView = gvMerge) or CanOpenMerge;
  if FResolveItem = nil then
    Exit;
  FResolveItem.Enabled := CanResolveBlocks and (Edit.Carets.Count > 0) and
    (ConflictAtRow(Edit.Carets[0].PosY) >= 0);
end;

procedure TRepoFrame.MenuResolveHereClick(Sender: TObject);
begin
  if CanResolveBlocks and (Edit.Carets.Count > 0) then
    ResolveConflictAt(ConflictAtRow(Edit.Carets[0].PosY));
end;

{ The editor menu's item acts on the row it was opened on. }
procedure TRepoFrame.MenuResolveEditClick(Sender: TObject);
begin
  if CanResolveBlocks and (FPopupEd = Edit) then
    ResolveConflictAt(ConflictAtRow(FPopupRow));
end;

{ The header's pills on a conflicted file, from HeaderAction. }
function TRepoFrame.ConflictHeaderAction(AIndex: integer): boolean;
begin
  Result := (FEditPath = '') and (FView in [gvChanges, gvImage, gvBinary]) and
    IsConflictPath(FCurrentPath);
  if not Result then
    Exit;
  { The fourth pill, shown while the file has markers. }
  if AIndex = 3 then
    OpenMergeEditor
  else
    ResolvePath(FCurrentPath, AIndex);
end;

procedure TRepoFrame.MenuResolveMineClick(Sender: TObject);
begin
  ResolvePath(FContextPath, 0);
end;

procedure TRepoFrame.MenuResolveTheirsClick(Sender: TObject);
begin
  ResolvePath(FContextPath, 1);
end;

procedure TRepoFrame.MenuMarkResolvedClick(Sender: TObject);
begin
  ResolvePath(FContextPath, 2);
end;

{ The tracked changes go into the commit with the resolved conflicts
  (a rebase goes on with none left out); others than the conflicts' are
  asked about first, as they may be work of another kind. An edit stop
  has no conflicts, and its changes are what it stopped for. }
procedure TRepoFrame.ContinueOperationClick;
var
  Noun, StoppedAt, Shown: string;
  Extras: TStringArray;
  i: integer;
begin
  if (FRepo.Root = '') or not ContinueMode or (FCommitJob <> nil) or (FRemoteJob <> nil) then
    Exit;
  Noun := OperationNoun(FOperation);
  Extras := FRepo.ContinueExtras;
  if Extras <> nil then
  begin
    Shown := '';
    for i := 0 to Min(Length(Extras), 10) - 1 do
      Shown := Shown + LineEnding + '  ' + Extras[i];
    if Length(Extras) > 10 then
      Shown := Shown + LineEnding + '  ' + Format(rsSwitchMore, [Length(Extras) - 10]);
    if AskDlg(rsContinueExtrasTitle, Format(rsContinueExtrasAsk, [Shown]), mtConfirmation,
      [mrYes, rsContinueExtrasButton, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'],
      0) <> mrYes then
      Exit;
  end;
  Screen.Cursor := crHourGlass;
  try
    if not FRepo.ContinueOperation then
    begin
      Screen.Cursor := crDefault;
      RefreshRepository;
      TellDlg(Format(rsContinueFailed, [Noun]), FRepo.Error, mtError);
      Exit;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  RefreshRepository;
  { The banner of the stop that was just got past is not for anything
    now; one that finishes says so in green. }
  FBanner.Clear;
  if FConflictFiles > 0 then
    StatusNote(rsStoppedAgain, True)
  else if FOperation <> '' then
  begin
    { An interactive rebase stops again at a commit to edit. }
    StoppedAt := FRepo.RebaseStoppedAt;
    if (FOperation = 'rebasing') and (StoppedAt <> '') then
      StatusNote(Format(rsRebaseStoppedAt, [Copy(StoppedAt, 1, 7)]))
    else
      StatusNote(Format(rsContinuedOn, [Noun]));
  end
  else
  begin
    StatusNote(Format(rsContinued, [Noun]));
    BannerSuccess(Format(rsContinued, [Noun]));
  end;
end;

procedure TRepoFrame.SkipOperationClick(Sender: TObject);
begin
  if (FRepo.Root = '') or not ContinueMode then
    Exit;
  if AskDlg(rsSkipTitle, rsSkipAsk, mtConfirmation,
    [mrYes, rsSkipButton, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes then
    Exit;
  if FRepo.SkipOperation then
  begin
    FBanner.Clear;
    StatusNote(rsSkipped);
  end
  else
    TellDlg(rsSkipFailed, FRepo.Error, mtError);
  RefreshRepository;
end;

procedure TRepoFrame.AbortOperationClick(Sender: TObject);
var
  Noun: string;
begin
  if (FRepo.Root = '') or (FOperation = '') then
    Exit;
  Noun := OperationNoun(FOperation);
  if StrayRebase then
  begin
    { HEAD is on another branch: offer to forget the rebase too, which
      keeps the branch and the files as they are. }
    case AskDlg(rsAbortTitle, Format(rsStrayAbortAsk, [FRebaseBranch, FBranch]),
        mtConfirmation, [mrYes, rsAbortButton, mrNo, rsQuitButton, mrCancel, rsCancelButton,
        'IsCancel', 'IsDefault'], 0) of
      mrYes: ;
      mrNo:
      begin
        if FRepo.QuitOperation then
        begin
          FBanner.Clear;
          StatusNote(Format(rsQuit, [Noun]));
        end
        else
          TellDlg(Format(rsQuitFailed, [Noun]), FRepo.Error, mtError);
        RefreshRepository;
        Exit;
      end;
      else
        Exit;
    end;
  end
  else if AskDlg(rsAbortTitle, Format(rsAbortAsk, [Noun]), mtConfirmation,
    [mrYes, rsAbortButton, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes then
    Exit;
  if FRepo.AbortOperation then
  begin
    { The merge message filled in is not for anything now. }
    if (FMergeMessage <> '') and (FCommitMemo.Text = FMergeMessage) then
      FCommitMemo.Text := FCommitTemplate;
    FMergeMessage := '';
    FBanner.Clear;
    StatusNote(Format(rsAborted, [Noun]));
  end
  else
    TellDlg(Format(rsAbortFailed, [Noun]), FRepo.Error, mtError);
  RefreshRepository;
end;
