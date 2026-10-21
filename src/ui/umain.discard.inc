{ ---------------------------------------------------------------------------
  Discarding a change
  ---------------------------------------------------------------------------
  Included by umain.pp. The mouse resting on a changed row of the
  change view (PillPause, over the text of the new side) shows two
  pills at the row's right end (FDiscardPills, a TGittanHoverPills),
  Keep with a check mark and Discard with an arrow going back round a
  circle, both for the block of changed lines the row is in. Keep shows the change as plain code for the rest of the
  session (gittan.keep): the keeps of every file are in FKeeps,
  ShowChanges applies them to FChangeLines (the diff as git gave it
  stays in FRawChangeLines), and the view is built from the result, so
  a kept line has no color, no strip and no button, the navigator does
  not count it and Hide Unchanged Lines folds it away; FKeptOf says
  which lines are kept, and the mouse resting on one gets an Unkeep
  pill, the header an "Unkeep n" pill for the whole file. The Discard
  pill, or File > Discard Change on the block the caret is in, puts
  the block's lines back to how they are in the
  version compared against: its deleted lines are written over its
  added ones (gittan.discard, which checks the file still holds them
  first), after a question, and the repository is refreshed so the
  view shows the result. The blocks discarded are kept, so File > Undo
  Discard writes them back, the latest first.
  The pills are offered for a tracked text file against a commit or a
  snapshot, not against a range (the right side is not the work tree
  then), nor for a new file (discarding its one block would empty it)
  or a conflict (CanDiscard). A conflicted file has a gutter band of
  its own instead (gutterTagDiscard, next to the text, on the new side
  only) with a fork button on each conflict's first row, which resolves
  one conflict at a time (CanResolveBlocks, see umain.conflicts.inc). }

{ Whether the shown file's blocks can be discarded. }
function TForm1.CanDiscard: boolean;
var
  i: integer;
begin
  Result := False;
  if (FRepo = nil) or (FView <> gvChanges) or (FCurrentPath = '') or FRepo.IsRange then
    Exit;
  for i := 0 to High(FStats) do
    if FStats[i].Path = FCurrentPath then
      Exit(not FStats[i].Binary and (FStats[i].Kind in [ckModified, ckRenamed, ckDeleted]));
end;

{ The diff line on row ARow: the new side's, or the old side's where
  the new side has a filler; -1 for a gap or a filler with nothing on
  the other side. }
function TForm1.LineAtRow(ARow: integer): integer;
begin
  Result := -1;
  if (ARow < 0) or (ARow > High(FRows)) then
    Exit;
  Result := FRows[ARow].Line;
  if (Result < 0) and (ARow <= High(FRowsOld)) then
    Result := FRowsOld[ARow].Line;
  if (Result < 0) or (Result >= FChangeLines.Count) then
    Result := -1;
end;

{ The block the line on row ARow is in, or -1 for an unchanged line, a
  gap or a filler with nothing on the other side. }
function TForm1.BlockAtRow(ARow: integer): integer;
var
  Line, b: integer;
begin
  Result := -1;
  Line := LineAtRow(ARow);
  if (Line < 0) or (FChangeLines[Line][1] = ' ') then
    Exit;
  for b := High(FBlockStarts) downto 0 do
    if FBlockStarts[b] <= Line then
      Exit(b);
end;

{ The block the mouse is on at X, Y of AEd, or -1, in ARow the row it
  is on, and in AKeep the kept change the row shows as code, or -1.
  Every row of a block counts, across the text, since the pills are for
  its block. For a conflicted file the result is the conflict whose
  button is under the mouse: on the band, on the first screen row of
  the conflict's first row. }
function TForm1.DiscardAt(AEd: TATSynEdit; X, Y: integer; out ARow: integer;
  out AKeep: integer): integer;
var
  Band, b, RowTop, Line: integer;
  Details: TATEditorPosDetails;
  P: TPoint;
  Resolve: boolean;
begin
  Result := -1;
  ARow := -1;
  AKeep := -1;
  if AEd <> Edit then
    Exit;
  Resolve := CanResolveBlocks;
  if Resolve then
  begin
    Band := AEd.Gutter.FindIndexByTag(gutterTagDiscard);
    if (Band < 0) or not AEd.Gutter[Band].Visible or (X < AEd.Gutter[Band].Left) or
      (X >= AEd.Gutter[Band].Right) then
      Exit;
  end
  else if not CanDiscard or (X < AEd.RectMain.Left) or (X >= AEd.RectMain.Right) then
    Exit;
  P := AEd.ClientPosToCaretPos(ATPoint(AEd.RectMain.Left + 1, Y), Details);
  if (P.Y < 0) or Details.BelowAllText or (Details.OnGapItem <> nil) then
    Exit;
  if Resolve then
  begin
    for b := 0 to High(FConflictRows) do
      if FConflictRows[b] = P.Y then
      begin
        RowTop := AEd.CaretPosToClientPos(Point(0, P.Y)).Y;
        if (Y >= RowTop) and (Y < RowTop + AEd.TextCharSize.Y) then
        begin
          Result := b;
          ARow := P.Y;
        end;
        Exit;
      end;
    Exit;
  end;
  Result := BlockAtRow(P.Y);
  if Result >= 0 then
    ARow := P.Y
  else
  begin
    Line := LineAtRow(P.Y);
    if (Line >= 0) and (Line <= High(FKeptOf)) and (FKeptOf[Line] >= 0) then
    begin
      AKeep := FKeptOf[Line];
      ARow := P.Y;
    end;
  end;
end;

{ The band's width is a line's height plus a character's width, so the
  button is a circle with some room. A change of width moves the text,
  so the wrap info is rebuilt. }
procedure TForm1.SetDiscardBand(AEd: TATSynEdit);
var
  Band, W: integer;
  Shown: boolean;
begin
  Band := AEd.Gutter.FindIndexByTag(gutterTagDiscard);
  if Band < 0 then
    Exit;
  Shown := (AEd = Edit) and CanResolveBlocks;
  if (AEd = Edit) and not Shown and not CanDiscard then
    SetHotDiscard(Edit, -1, -1, -1);
  W := AEd.TextCharSize.Y + EditorCharWidth(AEd);
  if (AEd.Gutter[Band].Visible <> Shown) or (AEd.Gutter[Band].Size <> W) then
  begin
    AEd.Gutter[Band].Visible := Shown;
    AEd.Gutter[Band].Size := W;
    AEd.Update(True);
  end;
  AEd.Invalidate;
end;

{ Paints the fork buttons of a conflicted file on the first screen row
  of each conflict in view: two branches coming together into one, in
  the gutter's text color, the one under the mouse on a disc in the
  caret row's gutter color; and a bar in the conflict color runs down
  the band's left edge from the conflict's first row to its last, so a
  conflict stands out from the changes around it when the file is
  long. }
procedure TForm1.DrawDiscard(AEd: TATSynEdit; C: TCanvas);
var
  Band, W, b, CharH, Y, Cx, Cy, R, Y2: integer;
  Item: TATWrapItem;
  Rows: TIntegerDynArray;
begin
  Band := AEd.Gutter.FindIndexByTag(gutterTagDiscard);
  if (Band < 0) or not AEd.Gutter[Band].Visible or (AEd <> Edit) or not CanResolveBlocks then
    Exit;
  Rows := FConflictRows;
  if Length(Rows) = 0 then
    Exit;
  CharH := AEd.TextCharSize.Y;
  R := Max(3, (CharH - 6) div 2);
  C.Clipping := True;
  C.ClipRect := Rect(AEd.Gutter[Band].Left, AEd.RectMain.Top, AEd.Gutter[Band].Right,
    AEd.RectMain.Bottom);
  try
    C.Pen.Style := psClear;
    C.Brush.Style := bsSolid;
    C.Brush.Color := KindColor(ckConflict);
    for b := 0 to High(Rows) do
    begin
      if (Rows[b] < 0) or (b > High(FConflictEndRows)) or (FConflictEndRows[b] < 0) then
        Continue;
      Y := AEd.CaretPosToClientPos(Point(0, Rows[b])).Y;
      Y2 := AEd.CaretPosToClientPos(Point(0, FConflictEndRows[b])).Y + CharH;
      if (Y2 <= AEd.RectMain.Top) or (Y >= AEd.RectMain.Bottom) then
        Continue;
      C.FillRect(AEd.Gutter[Band].Left + 1, Max(Y, AEd.RectMain.Top),
        AEd.Gutter[Band].Left + 4, Min(Y2, AEd.RectMain.Bottom));
    end;
    b := 0;
    W := AEd.WrapInfo.FindIndexOfLineNumber(AEd.LineTop);
    while (W < AEd.WrapInfo.Count) and (b <= High(Rows)) do
    begin
      Item := AEd.WrapInfo[W];
      Inc(W);
      if not Item.bInitial then
        Continue;
      Y := AEd.CaretPosToClientPos(Point(0, Item.NLineIndex)).Y;
      if Y >= AEd.RectMain.Bottom then
        Break;
      while (b <= High(Rows)) and (Rows[b] < Item.NLineIndex) do
        Inc(b);
      if (b > High(Rows)) or (Rows[b] <> Item.NLineIndex) then
        Continue;
      Cx := (AEd.Gutter[Band].Left + AEd.Gutter[Band].Right) div 2;
      Cy := Y + CharH div 2;
      if b = FHotDiscard then
      begin
        C.Pen.Style := psClear;
        C.Brush.Style := bsSolid;
        C.Brush.Color := AEd.Colors.GutterCaretBG;
        C.Ellipse(Cx - R - 3, Cy - R - 3, Cx + R + 4, Cy + R + 4);
        C.Pen.Color := AEd.Colors.GutterCaretFont;
      end
      else
        C.Pen.Color := AEd.Colors.GutterFont;
      C.Pen.Style := psSolid;
      C.Pen.Width := Max(1, R div 3);
      C.Brush.Style := bsClear;
      { Two branches from the top corners into the middle, one line on
        down from there. }
      C.Line(Cx - R, Cy - R, Cx, Cy);
      C.Line(Cx + R, Cy - R, Cx, Cy);
      C.Line(Cx, Cy, Cx, Cy + R + 1);
      Inc(b);
    end;
  finally
    C.Clipping := False;
    C.Pen.Width := 1;
    C.Pen.Style := psSolid;
    C.Brush.Style := bsSolid;
  end;
end;

{ The block under the mouse is kept and the pills follow the row: at
  once while they are up, after the pause when a new row is entered,
  so a mouse passing through the diff raises none; for a conflicted
  file the conflict whose button is under the mouse is lit. Edit only. }
procedure TForm1.SetHotDiscard(AEd: TATSynEdit; ABlock, AKeep, ARow: integer);
begin
  if (ABlock = FHotDiscard) and (AKeep = FHotKeep) and (ARow = FHotRow) then
    Exit;
  if (ABlock <> FHotDiscard) and CanResolveBlocks then
    Edit.Invalidate;
  FHotDiscard := ABlock;
  FHotKeep := AKeep;
  FHotRow := ARow;
  FPillTimer.Enabled := False;
  if (ABlock < 0) and (AKeep < 0) then
    FDiscardPills.Dismiss
  else if FDiscardPills.Visible then
    ShowDiscardPills
  else
    FPillTimer.Enabled := True;
end;

{ The mouse has rested on the row. }
procedure TForm1.PillTimerTimer(Sender: TObject);
begin
  FPillTimer.Enabled := False;
  ShowDiscardPills;
end;

{ The pills at the right end of the hot row: Keep and Discard for the
  block the row is in; on a kept line, Unkeep. A conflict's button has
  none. }
procedure TForm1.ShowDiscardPills;
var
  Y: integer;
  Anchor: TRect;
begin
  if ((FHotDiscard < 0) and (FHotKeep < 0)) or (FHotRow < 0) or
    (FHotDiscard > High(FBlockStarts)) or CanResolveBlocks or not CanDiscard then
  begin
    FDiscardPills.Dismiss;
    Exit;
  end;
  Y := Edit.CaretPosToClientPos(Point(0, FHotRow)).Y;
  Anchor := Rect(Edit.RectMain.Left, Y, Edit.RectMain.Right, Y + Edit.TextCharSize.Y);
  Anchor.TopLeft := Edit.ClientToScreen(Anchor.TopLeft);
  Anchor.BottomRight := Edit.ClientToScreen(Anchor.BottomRight);
  FPillChoose := (FHotKeep < 0) and CanLeaveOut;
  if FHotKeep >= 0 then
    FDiscardPills.Show(Anchor, [rsUnkeepPill])
  else if FPillChoose then
    FDiscardPills.Show(Anchor, [rsKeepPill, LeaveOutCaption(FHotDiscard), rsDiscardAction], 'k d')
  else
    FDiscardPills.Show(Anchor, [rsKeepPill, rsDiscardAction], 'kd');
end;

{ Whether the mouse is over the pills, which are a child of the form. }
function TForm1.MouseOnDiscardPills: boolean;
begin
  Result := FDiscardPills.Visible and
    PtInRect(FDiscardPills.BoundsRect, ScreenToClient(Mouse.CursorPos));
end;

{ Whether the mouse is over Edit's text. }
function TForm1.MouseOnDiscardRows: boolean;
var
  P: TPoint;
begin
  P := Edit.ScreenToClient(Mouse.CursorPos);
  Result := (P.X >= Edit.RectMain.Left) and (P.X < Edit.RectMain.Right) and
    (P.Y >= Edit.RectMain.Top) and (P.Y < Edit.RectMain.Bottom);
end;

{ A pill: Unkeep on a kept line, else Keep, Leave Out or Include (see
  umain.leaveout.inc) or Discard for the block. The pills go before the
  question. }
procedure TForm1.DiscardPillsPick(Sender: TObject; AIndex: integer);
var
  Block, Keep: integer;
begin
  Block := FHotDiscard;
  Keep := FHotKeep;
  SetHotDiscard(Edit, -1, -1, -1);
  if Keep >= 0 then
    UnkeepAt(Keep)
  else if AIndex = 0 then
    KeepBlockAt(Block)
  else if FPillChoose and (AIndex = 1) then
    ToggleLeaveOutAt(Block)
  else
    DiscardBlockAt(Block);
end;

{ The mouse left the pills: back onto the rows, where EditMouseMove
  follows it, or away, which lets the block go. }
procedure TForm1.DiscardPillsLeave(Sender: TObject);
begin
  if not MouseOnDiscardRows then
    SetHotDiscard(Edit, -1, -1, -1);
end;

{ What discarding the block does, for the question: the lines put back
  (or removed, when nothing is put back) and what they go back to. }
function TForm1.DiscardBackText(const ABlock: TGittanDiscard): string;
var
  n: integer;
begin
  n := DiscardCount(ABlock);
  if n = 1 then
    Result := Format(rsDiscardBackOne, [DiscardBaseName])
  else
    Result := Format(rsDiscardBackMany, [n, DiscardBaseName]);
end;

{ What the lines go back to: HEAD, or the base as the summary names it. }
function TForm1.DiscardBaseName: string;
begin
  Result := BaseLabel;
  if Result = '' then
    Result := 'HEAD'
  else
    Delete(Result, 1, Length(Format(rsVsBase, [''])));
end;

{ Asks, writes the block's old lines over its new ones and refreshes. }
procedure TForm1.DiscardThis(const ABlock: TGittanDiscard);
var
  Path, Err: string;
begin
  Path := FCurrentPath;
  if QuestionDlg(rsAppName, Format(rsDiscardAsk, [ExtractFileName(Path),
    DiscardBackText(ABlock)]), mtConfirmation,
    [mrYes, rsDiscardAction, 'IsDefault', mrCancel, rsCancelButton, 'IsCancel'], 0) <> mrYes then
    Exit;
  SetHotDiscard(Edit, -1, -1, -1);
  if not DiscardBlock(ABlock, Err) then
  begin
    StatusNote(Format(rsDiscardFailed, [Err]), True);
    Exit;
  end;
  SetLength(FDiscards, Length(FDiscards) + 1);
  FDiscards[High(FDiscards)] := ABlock;
  RefreshRepository;
  StatusNote(Format(rsDiscarded, [ABlock.Line, Path]));
  UpdateDiscardItems;
end;

{ The whole block. }
procedure TForm1.DiscardBlockAt(ABlock: integer);
begin
  if not CanDiscard or (ABlock < 0) or (ABlock > High(FBlockStarts)) then
    Exit;
  DiscardThis(DiffBlock(FChangeLines, FBlockStarts[ABlock],
    IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(FCurrentPath)));
end;

{ Keeps every pair of the block. }
procedure TForm1.KeepBlockAt(ABlock: integer);
var
  Pairs: TGittanKeepArray;
  k: integer;
begin
  if not CanDiscard or (ABlock < 0) or (ABlock > High(FBlockStarts)) then
    Exit;
  Pairs := BlockPairs(FChangeLines, FBlockStarts[ABlock]);
  if Length(Pairs) = 0 then
    Exit;
  for k := 0 to High(Pairs) do
    FKeeps.Add(FCurrentPath, Pairs[k]);
  IncludeKept(Pairs);
  StatusNote(Format(rsKeptBlock, [Pairs[0].Line, FCurrentPath]));
  RebuildKeeps;
end;

{ Shows the kept change numbered AKeep (by FKeptOf) as a change again. }
procedure TForm1.UnkeepAt(AKeep: integer);
var
  Line, i, n: integer;
begin
  if (FView <> gvChanges) or (FCurrentPath = '') then
    Exit;
  Line := 0;
  while (Line <= High(FKeptOf)) and (FKeptOf[Line] <> AKeep) do
    Inc(Line);
  if Line <= High(FKeptOf) then
  begin
    { The line's number in the file: the diff lines before it that are
      in the file. }
    n := 1;
    for i := 0 to Line - 1 do
      if FChangeLines[i][1] <> '-' then
        Inc(n);
    StatusNote(Format(rsUnkept, [n, FCurrentPath]));
  end;
  FKeeps.Remove(FCurrentPath, AKeep);
  RebuildKeeps;
end;

{ The header's Unkeep pill: every change of the file is shown again. }
procedure TForm1.UnkeepFile;
begin
  if (FView <> gvChanges) or (FCurrentPath = '') then
    Exit;
  FKeeps.Clear(FCurrentPath);
  StatusNote(Format(rsUnkeptAll, [FCurrentPath]));
  RebuildKeeps;
end;

{ The keeps changed: the diff is taken from git's again, the keeps
  applied, and the view built again at the same place; the blocks are
  others now, so their headings are found again after the parse. }
procedure TForm1.RebuildKeeps;
begin
  FChangeLines.Assign(FRawChangeLines);
  FKeeps.Apply(FCurrentPath, FChangeLines, FKeptOf);
  ApplyLeftOut;
  FHeadings := nil;
  FHeadingRebuilds := 0;
  SetChangeActions;
  RebuildIfChanges;
end;

{ The header's pills in the change view: Edit for one of the
  repository's own files, Include All while changes of the file are
  left out of the commit (FHeaderInclude), and Unkeep with the count
  while the file has kept changes (FHeaderUnkeep is its index, for
  HeaderAction). A conflicted file has its own pills (see
  ShowChanges). }
procedure TForm1.SetChangeActions;
var
  Captions: array of string;
  n: integer;
begin
  FHeaderUnkeep := -1;
  FHeaderInclude := -1;
  if FConflictRoles <> nil then
    Exit;
  Captions := nil;
  if IsRepoFile(FCurrentPath) then
    Captions := [rsEditAction];
  if CanLeaveOut and ShownFileChosen and (FLeftOut.Count(FCurrentPath) > 0) then
  begin
    FHeaderInclude := Length(Captions);
    SetLength(Captions, Length(Captions) + 1);
    Captions[High(Captions)] := rsIncludeAllAction;
  end;
  n := FKeeps.Count(FCurrentPath);
  if n > 0 then
  begin
    FHeaderUnkeep := Length(Captions);
    SetLength(Captions, Length(Captions) + 1);
    Captions[High(Captions)] := Format(rsUnkeepAction, [n]);
  end;
  FHeader.SetActions(Captions);
end;

{ Writes the latest discarded block back, shows its file when another
  is shown, and refreshes. A block the file no longer holds the lines of
  is dropped too: an older one is no better. }
procedure TForm1.MenuUndoDiscardClick(Sender: TObject);
var
  B: TGittanDiscard;
  Path, Err: string;
  Ok: boolean;
begin
  if Length(FDiscards) = 0 then
    Exit;
  B := Swapped(FDiscards[High(FDiscards)]);
  SetLength(FDiscards, Length(FDiscards) - 1);
  Ok := DiscardBlock(B, Err);
  UpdateDiscardItems;
  if not Ok then
  begin
    StatusNote(Format(rsUndoDiscardFailed, [Err]), True);
    Exit;
  end;
  Path := ExtractRelativePath(IncludeTrailingPathDelimiter(FRepo.Root), B.FileName);
  Path := StringReplace(Path, PathDelim, '/', [rfReplaceAll]);
  RefreshRepository;
  if (FView <> gvChanges) or (FCurrentPath <> Path) then
    ShowRepoFile(Path);
  StatusNote(Format(rsDiscardUndone, [B.Line, Path]));
end;

{ File > Discard Change acts on the block the caret is in. }
procedure TForm1.MenuDiscardClick(Sender: TObject);
begin
  if Edit.Carets.Count > 0 then
    DiscardBlockAt(BlockAtRow(Edit.Carets[0].PosY));
end;

{ The two items follow the caret (from UpdateChangeNav) and the discards
  made; the menu asks once more as it opens. }
procedure TForm1.UpdateDiscardItems;
begin
  if FDiscardItem = nil then
    Exit;
  FDiscardItem.Enabled := CanDiscard and (Edit.Carets.Count > 0) and
    (BlockAtRow(Edit.Carets[0].PosY) >= 0);
  FUndoDiscardItem.Enabled := Length(FDiscards) > 0;
  UpdateLeaveOutItem;
  UpdateResolveItems;
  if FRevertFileItem <> nil then
  begin
    FRevertFileItem.Enabled := CanRevert and IsChangedPath(FCurrentPath) and
      (FView in [gvChanges, gvImage, gvBinary, gvTranslation]);
    FUndoRevertItem.Enabled := FRevertUndo.Count > 0;
    FCleanItem.Enabled := CanClean;
    FApplyPatchesItem.Enabled := CanApplyPatches;
  end;
end;

procedure TForm1.FileMenuClick(Sender: TObject);
begin
  UpdateDiscardItems;
  UpdateRemoteItems;
end;
