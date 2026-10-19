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
function TForm1.ContinueMode: boolean;
begin
  Result := (FOperation = 'rebasing') or (FOperation = 'applying patches') or
    (FOperation = 'cherry-picking') or (FOperation = 'reverting');
end;

function TForm1.IsConflictPath(const APath: string): boolean;
var
  i: integer;
begin
  Result := False;
  if APath = '' then
    Exit;
  for i := 0 to High(FStats) do
    if FStats[i].Path = APath then
      Exit(FStats[i].Kind = ckConflict);
end;

{ How many conflicts are left in the file APath on disk, by its markers. }
function TForm1.MarkersLeft(const APath: string): integer;
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
procedure TForm1.ResolvePath(const APath: string; AAction: integer);
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
    if (Remaining > 0) and (QuestionDlg(rsMarkResolvedTitle, Format(rsMarkersLeft, [APath, Remaining]),
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
    if QuestionDlg(rsResolveTitle, Format(rsResolveAsk, [APath, Side]), mtConfirmation,
      [mrYes, rsResolveAction, 'IsDefault', mrCancel, rsCancelButton, 'IsCancel'], 0) <> mrYes then
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
    ShowNextConflict(APath, (APath = FCurrentPath) and (FView in [gvChanges, gvImage, gvBinary]));
end;

{ ---------------------------------------------------------------------------
  One conflict at a time
  --------------------------------------------------------------------------- }

{ Whether the shown file's conflicts can be resolved one by one: the
  change view of a conflicted file with markers, against the work tree. }
function TForm1.CanResolveBlocks: boolean;
begin
  Result := (FRepo <> nil) and (FView = gvChanges) and (FCurrentPath <> '') and
    (FEditPath = '') and not FRepo.IsRange and (Length(FConflictStarts) > 0) and
    IsConflictPath(FCurrentPath);
end;

{ The row of each conflict's "<<<<<<<" line (FConflictRows from
  FConflictStarts) and of its last line (FConflictEndRows from
  FConflictEnds), as FindBlockRows finds the blocks': the lines are
  added ones, so they are on the new side. }
procedure TForm1.FindConflictRows;

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
function TForm1.ConflictAtRow(ARow: integer): integer;
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
procedure TForm1.ResolveConflictAt(AIndex: integer);
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
  SetHotDiscard(Edit, -1);
  { The button's hint would stay over the list. }
  ClearHover;
  FConflictPopup.Popup(Anchor);
end;

{ Writes the pick over the conflict and refreshes. The last conflict of
  the file marks it resolved and moves on to the next file. }
procedure TForm1.ApplyConflictPick(AIndex: integer; APick: TGittanConflictPick);
var
  B: TGittanDiscard;
  Path, Err: string;
  Remaining: integer;
  Marked: boolean;
begin
  if not CanResolveBlocks or (AIndex < 0) or (AIndex > High(FConflictStarts)) then
    Exit;
  Path := FCurrentPath;
  B := ResolveBlock(FChangeLines, FConflictRoles, FConflictStarts[AIndex], APick,
    IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(Path));
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
  end;
  RefreshRepository;
  UpdateDiscardItems;
  if Marked then
  begin
    StatusNote(Format(rsResolvedLast, [Path]));
    ShowNextConflict(Path, True);
  end
  else if Remaining = 1 then
    StatusNote(Format(rsResolvedBlockOne, [B.Line, Path]))
  else if Remaining > 1 then
    StatusNote(Format(rsResolvedBlock, [B.Line, Path, Remaining]));
end;

procedure TForm1.ConflictPopupPick(Sender: TObject; AIndex: integer);
begin
  if FConflictPopupFiles then
  begin
    if (AIndex >= 0) and (AIndex <= High(FConflictPaths)) and (FConflictPaths[AIndex] <> '') then
      SummarySelectFile(Sender, FConflictPaths[AIndex]);
    Exit;
  end;
  if (AIndex >= 0) and (AIndex <= High(FConflictPicks)) then
    ApplyConflictPick(FResolveIndex, FConflictPicks[AIndex]);
  FResolveIndex := -1;
end;

{ The conflicts left in APath for the list: by its markers, or that it
  is gone (one side deleted it) or holds no markers (ready to be marked
  resolved). }
function TForm1.ConflictDetail(const APath: string): string;
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
procedure TForm1.ConflictBadgeClick(const AScreenRect: TRect);
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
        (FStats[i].Path = FCurrentPath) and (FView in [gvChanges, gvImage, gvBinary]));
      SetLength(FConflictPaths, Index + 1);
      FConflictPaths[Index] := FStats[i].Path;
    end;
  FConflictPopup.Popup(AScreenRect);
end;

{ The conflicted file after (or before, not ANext) AAfter in the tree,
  round the end, other than AAfter itself; '' for none. }
function TForm1.NextConflictFile(const AAfter: string; ANext: boolean): string;
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
procedure TForm1.ShowNextConflict(const AAfter: string; AAdvance: boolean);
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
procedure TForm1.GoToConflict(ANext: boolean);
var
  Rows: TIntegerDynArray;
  Cur, Target, i: integer;
  Other: string;
begin
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
  if FoldingShown then
    Edit.DoUnfoldLine(Target);
  Edit.DoCaretSingle(0, Target);
  Edit.LineTop := Max(0, Target - 3);
  Edit.Update;
  SyncOldSide;
  UpdateChangeNav;
end;

procedure TForm1.MenuNextConflictClick(Sender: TObject);
begin
  GoToConflict(True);
end;

procedure TForm1.MenuPrevConflictClick(Sender: TObject);
begin
  GoToConflict(False);
end;

{ File > Resolve Conflict acts on the conflict the caret is in; the
  item follows the caret (from UpdateDiscardItems). }
procedure TForm1.UpdateResolveItems;
begin
  if FResolveItem = nil then
    Exit;
  FResolveItem.Enabled := CanResolveBlocks and (Edit.Carets.Count > 0) and
    (ConflictAtRow(Edit.Carets[0].PosY) >= 0);
end;

procedure TForm1.MenuResolveHereClick(Sender: TObject);
begin
  if CanResolveBlocks and (Edit.Carets.Count > 0) then
    ResolveConflictAt(ConflictAtRow(Edit.Carets[0].PosY));
end;

{ The editor menu's item acts on the row it was opened on. }
procedure TForm1.MenuResolveEditClick(Sender: TObject);
begin
  if CanResolveBlocks and (FPopupEd = Edit) then
    ResolveConflictAt(ConflictAtRow(FPopupRow));
end;

{ The header's pills on a conflicted file, from HeaderAction. }
function TForm1.ConflictHeaderAction(AIndex: integer): boolean;
begin
  Result := (FEditPath = '') and (FView in [gvChanges, gvImage, gvBinary]) and
    IsConflictPath(FCurrentPath);
  if Result then
    ResolvePath(FCurrentPath, AIndex);
end;

procedure TForm1.MenuResolveMineClick(Sender: TObject);
begin
  ResolvePath(FContextPath, 0);
end;

procedure TForm1.MenuResolveTheirsClick(Sender: TObject);
begin
  ResolvePath(FContextPath, 1);
end;

procedure TForm1.MenuMarkResolvedClick(Sender: TObject);
begin
  ResolvePath(FContextPath, 2);
end;

procedure TForm1.ContinueOperationClick;
var
  Noun: string;
begin
  if (FRepo.Root = '') or not ContinueMode or (FCommitJob <> nil) or (FRemoteJob <> nil) then
    Exit;
  Noun := OperationNoun(FOperation);
  Screen.Cursor := crHourGlass;
  try
    if not FRepo.ContinueOperation then
    begin
      Screen.Cursor := crDefault;
      RefreshRepository;
      MessageDlg(Format(rsContinueFailed, [Noun]), FRepo.Error, mtError, [mbOK], 0);
      Exit;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  RefreshRepository;
  if FConflictFiles > 0 then
    StatusNote(rsStoppedAgain, True)
  else if FOperation <> '' then
    StatusNote(Format(rsContinuedOn, [Noun]))
  else
    StatusNote(Format(rsContinued, [Noun]));
end;

procedure TForm1.SkipOperationClick(Sender: TObject);
begin
  if (FRepo.Root = '') or not ContinueMode then
    Exit;
  if QuestionDlg(rsSkipTitle, rsSkipAsk, mtConfirmation,
    [mrYes, rsSkipButton, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes then
    Exit;
  if FRepo.SkipOperation then
    StatusNote(rsSkipped)
  else
    MessageDlg(rsSkipFailed, FRepo.Error, mtError, [mbOK], 0);
  RefreshRepository;
end;

procedure TForm1.AbortOperationClick(Sender: TObject);
var
  Noun: string;
begin
  if (FRepo.Root = '') or (FOperation = '') then
    Exit;
  Noun := OperationNoun(FOperation);
  if QuestionDlg(rsAbortTitle, Format(rsAbortAsk, [Noun]), mtConfirmation,
    [mrYes, rsAbortButton, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes then
    Exit;
  if FRepo.AbortOperation then
  begin
    { The merge message filled in is not for anything now. }
    if (FMergeMessage <> '') and (FCommitMemo.Text = FMergeMessage) then
      FCommitMemo.Clear;
    FMergeMessage := '';
    StatusNote(Format(rsAborted, [Noun]));
  end
  else
    MessageDlg(Format(rsAbortFailed, [Noun]), FRepo.Error, mtError, [mbOK], 0);
  RefreshRepository;
end;
