{ ---------------------------------------------------------------------------
  Discarding a change
  ---------------------------------------------------------------------------
  Included by umain.pp. Every block of changed lines in the change view
  gets a button in a gutter band of its own (gutterTagDiscard, next to
  the text, on the new side only) on its first row; a click on it, or
  File > Discard Change on the block the caret is in, puts the lines
  back to how they are in the version compared against: the block's
  deleted lines are written over its added ones (gittan.discard, which
  checks the file still holds them first), after a question, and the
  repository is refreshed so the view shows the result. The blocks
  discarded are kept, so File > Undo Discard writes them back, the
  latest first. The band is shown for a tracked text file against a
  commit or a snapshot, not against a range (the right side is not the
  work tree then), nor for a new file (discarding its one block would
  empty it) or a conflict. }

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

{ The row of the first line of every block (FBlockRows from
  FBlockStarts), from the rows of the view just built: in the unified
  view the line's own row, side by side the row the line is on either
  side (the other side has a filler there). The rows follow the diff, so
  one pass finds them all. }
procedure TForm1.FindBlockRows;
var
  b, r: integer;
begin
  SetLength(FBlockRows, Length(FBlockStarts));
  for b := 0 to High(FBlockRows) do
    FBlockRows[b] := -1;
  b := 0;
  for r := 0 to High(FRows) do
  begin
    if b > High(FBlockStarts) then
      Break;
    if (FRows[r].Line = FBlockStarts[b]) or
      ((r <= High(FRowsOld)) and (FRowsOld[r].Line = FBlockStarts[b])) then
    begin
      FBlockRows[b] := r;
      Inc(b);
    end;
  end;
end;

{ The block the line on row ARow is in, or -1 for an unchanged line, a
  gap or a filler with nothing on the other side. }
function TForm1.BlockAtRow(ARow: integer): integer;
var
  Line, b: integer;
begin
  Result := -1;
  if (ARow < 0) or (ARow > High(FRows)) then
    Exit;
  Line := FRows[ARow].Line;
  if (Line < 0) and (ARow <= High(FRowsOld)) then
    Line := FRowsOld[ARow].Line;
  if (Line < 0) or (Line >= FChangeLines.Count) or (FChangeLines[Line][1] = ' ') then
    Exit;
  for b := High(FBlockStarts) downto 0 do
    if FBlockStarts[b] <= Line then
      Exit(b);
end;

{ The block whose button is under the mouse at X, Y of AEd, or -1. The
  button is on the first screen row of the block's first row. }
function TForm1.DiscardAt(AEd: TATSynEdit; X, Y: integer): integer;
var
  Band, b, RowTop: integer;
  Details: TATEditorPosDetails;
  P: TPoint;
begin
  Result := -1;
  if (AEd <> Edit) or not CanDiscard then
    Exit;
  Band := AEd.Gutter.FindIndexByTag(gutterTagDiscard);
  if (Band < 0) or not AEd.Gutter[Band].Visible or (X < AEd.Gutter[Band].Left) or
    (X >= AEd.Gutter[Band].Right) then
    Exit;
  P := AEd.ClientPosToCaretPos(ATPoint(AEd.RectMain.Left + 1, Y), Details);
  if (P.Y < 0) or Details.BelowAllText then
    Exit;
  for b := 0 to High(FBlockRows) do
    if FBlockRows[b] = P.Y then
    begin
      RowTop := AEd.CaretPosToClientPos(Point(0, P.Y)).Y;
      if (Y >= RowTop) and (Y < RowTop + AEd.TextCharSize.Y) then
        Result := b;
      Exit;
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
  Shown := (AEd = Edit) and CanDiscard;
  W := AEd.TextCharSize.Y + EditorCharWidth(AEd);
  if (AEd.Gutter[Band].Visible <> Shown) or (AEd.Gutter[Band].Size <> W) then
  begin
    AEd.Gutter[Band].Visible := Shown;
    AEd.Gutter[Band].Size := W;
    AEd.Update(True);
  end;
  AEd.Invalidate;
end;

{ Paints the buttons: an arrow going back round a circle on the first
  screen row of each block in view, in the gutter's text color, the one
  under the mouse on a disc in the caret row's gutter color. }
procedure TForm1.DrawDiscard(AEd: TATSynEdit; C: TCanvas);
var
  Band, W, b, CharH, Y, Cx, Cy, R, A: integer;
  Item: TATWrapItem;
begin
  Band := AEd.Gutter.FindIndexByTag(gutterTagDiscard);
  if (Band < 0) or not AEd.Gutter[Band].Visible or (AEd <> Edit) or not CanDiscard or
    (Length(FBlockRows) = 0) then
    Exit;
  CharH := AEd.TextCharSize.Y;
  R := Max(3, (CharH - 6) div 2);
  A := Max(2, (R * 2) div 3);
  C.Clipping := True;
  C.ClipRect := Rect(AEd.Gutter[Band].Left, AEd.RectMain.Top, AEd.Gutter[Band].Right,
    AEd.RectMain.Bottom);
  try
    b := 0;
    W := AEd.WrapInfo.FindIndexOfLineNumber(AEd.LineTop);
    while (W < AEd.WrapInfo.Count) and (b <= High(FBlockRows)) do
    begin
      Item := AEd.WrapInfo[W];
      Inc(W);
      if not Item.bInitial then
        Continue;
      Y := AEd.CaretPosToClientPos(Point(0, Item.NLineIndex)).Y;
      if Y >= AEd.RectMain.Bottom then
        Break;
      while (b <= High(FBlockRows)) and (FBlockRows[b] < Item.NLineIndex) do
        Inc(b);
      if (b > High(FBlockRows)) or (FBlockRows[b] <> Item.NLineIndex) then
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
      { Round from the lower right over the top to the left, where the
        head points down. }
      C.Arc(Cx - R, Cy - R, Cx + R, Cy + R, 300 * 16, 240 * 16);
      C.Line(Cx - R, Cy + 1, Cx - R - A, Cy + 1 - A);
      C.Line(Cx - R, Cy + 1, Cx - R + A, Cy + 1 - A);
      Inc(b);
    end;
  finally
    C.Clipping := False;
    C.Pen.Width := 1;
    C.Pen.Style := psSolid;
    C.Brush.Style := bsSolid;
  end;
end;

{ The button under the mouse is lit; the band is on Edit only. }
procedure TForm1.SetHotDiscard(AEd: TATSynEdit; ABlock: integer);
begin
  if ABlock = FHotDiscard then
    Exit;
  FHotDiscard := ABlock;
  Edit.Invalidate;
end;

{ What discarding the block does, for the hint and the question: the
  lines put back (or removed, when nothing is put back) and what they
  go back to. }
function TForm1.DiscardBackText(ABlock: integer): string;
var
  n: integer;
begin
  n := 0;
  if (ABlock >= 0) and (ABlock <= High(FBlockStarts)) then
    n := DiscardCount(DiffBlock(FChangeLines, FBlockStarts[ABlock], ''));
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
procedure TForm1.DiscardBlockAt(ABlock: integer);
var
  B: TGittanDiscard;
  Path, Err: string;
begin
  if not CanDiscard or (ABlock < 0) or (ABlock > High(FBlockStarts)) then
    Exit;
  Path := FCurrentPath;
  B := DiffBlock(FChangeLines, FBlockStarts[ABlock],
    IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(Path));
  if QuestionDlg(rsAppName, Format(rsDiscardAsk, [ExtractFileName(Path),
    DiscardBackText(ABlock)]), mtConfirmation,
    [mrYes, rsDiscardAction, 'IsDefault', mrCancel, rsCancelButton, 'IsCancel'], 0) <> mrYes then
    Exit;
  SetHotDiscard(Edit, -1);
  if not DiscardBlock(B, Err) then
  begin
    StatusNote(Format(rsDiscardFailed, [Err]), True);
    Exit;
  end;
  SetLength(FDiscards, Length(FDiscards) + 1);
  FDiscards[High(FDiscards)] := B;
  RefreshRepository;
  StatusNote(Format(rsDiscarded, [B.Line, Path]));
  UpdateDiscardItems;
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
  if FRevertFileItem <> nil then
  begin
    FRevertFileItem.Enabled := CanRevert and IsChangedPath(FCurrentPath) and
      (FView in [gvChanges, gvImage, gvBinary, gvTranslation]);
    FUndoRevertItem.Enabled := FRevertUndo.Count > 0;
  end;
end;

procedure TForm1.FileMenuClick(Sender: TObject);
begin
  UpdateDiscardItems;
  UpdateRemoteItems;
end;
