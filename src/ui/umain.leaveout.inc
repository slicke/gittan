{ ---------------------------------------------------------------------------
  Leaving changes out of a commit
  ---------------------------------------------------------------------------
  Included by umain.pp. While the tree's boxes choose what is committed
  (CommitChoosing), the pills of a changed row in the change view have
  Leave Out between Keep and Discard: the block's changes stay in the
  work tree and out of the commit, which takes the rest of the file
  (TGittanRepo.Commit with the file's text from gittan.leaveout). A
  block left out is drawn in muted tints without its word shades, its
  pill says Include, the file's box is mixed and the header has
  Include All. File > Leave Change Out of Commit (Cmd+Alt+K) does what
  the middle pill does for the block the caret is in, and reads Include
  Change in Commit where the pill reads Include. Leaving out every block of a file unticks it, and
  Include on a block of an unticked file ticks it with that block alone
  (the kept lines, which count as accepted, go in too). FLeftOut holds
  the changes left out of every file by path, as FKeeps the keeps, by
  content, so they survive refreshes; those the file's diff no longer
  holds are dropped when it is shown, and all go after a commit, a click
  on the file's box or on opening a repository. Keeping a block includes
  it, since a kept line shows nothing to tell it is left out. }

{ Whether blocks of the shown file can be left out of the commit: a
  tracked text file compared with HEAD while no commit runs. }
function TRepoFrame.CanLeaveOut: boolean;
begin
  Result := CanDiscard and CommitChoosing and (FCommitJob = nil) and
    (FConflictRoles = nil) and (StatIndexOf(FCurrentPath) >= 0);
end;

{ Whether the shown file goes into the commit at all. }
function TRepoFrame.ShownFileChosen: boolean;
var
  i: integer;
begin
  i := StatIndexOf(FCurrentPath);
  Result := (i >= 0) and CommitChosen(i);
end;

{ FLeftOutOf for the shown diff: for each line of FChangeLines the
  change left out it is, or -1; none while blocks cannot be left out or
  the file is not chosen. The changes the diff no longer holds go. }
procedure TRepoFrame.ApplyLeftOut;
var
  i: integer;
begin
  FLeftOutOf := nil;
  if CanLeaveOut and ShownFileChosen and (FLeftOut.Count(FCurrentPath) > 0) then
  begin
    FLeftOut.Prune(FCurrentPath, FRawChangeLines);
    FLeftOutOf := MatchKeeps(FChangeLines, FLeftOut.Items(FCurrentPath));
  end
  else
  begin
    SetLength(FLeftOutOf, FChangeLines.Count);
    for i := 0 to High(FLeftOutOf) do
      FLeftOutOf[i] := -1;
  end;
end;

{ Whether diff line ALine is a change left out. }
function TRepoFrame.LineLeftOut(ALine: integer): boolean;
begin
  Result := (FView = gvChanges) and (ALine >= 0) and (ALine <= High(FLeftOutOf)) and
    (FLeftOutOf[ALine] >= 0);
end;

{ Whether any line of block ABlock is left out. }
function TRepoFrame.BlockLeftOut(ABlock: integer): boolean;
var
  i: integer;
begin
  Result := False;
  if (ABlock < 0) or (ABlock > High(FBlockStarts)) then
    Exit;
  i := FBlockStarts[ABlock];
  while (i < FChangeLines.Count) and (FChangeLines[i][1] <> ' ') do
  begin
    if LineLeftOut(i) then
      Exit(True);
    Inc(i);
  end;
end;

{ What the middle pill offers for the block: Include in Commit for one
  left out or of a file not ticked, Skip in Commit for the rest. }
function TRepoFrame.LeaveOutCaption(ABlock: integer): string;
begin
  if not ShownFileChosen or BlockLeftOut(ABlock) then
    Result := rsIncludePill
  else
    Result := rsLeaveOutPill;
end;

{ The middle pill's hint, for the caption LeaveOutCaption gives. }
function TRepoFrame.LeaveOutHint(ABlock: integer): string;
begin
  if LeaveOutCaption(ABlock) = rsIncludePill then
    Result := rsIncludePillHint
  else
    Result := rsLeaveOutPillHint;
end;

{ The middle pill: the block goes out of the commit, or back in. }
procedure TRepoFrame.ToggleLeaveOutAt(ABlock: integer);
begin
  if not CanLeaveOut or (ABlock < 0) or (ABlock > High(FBlockStarts)) then
    Exit;
  if LeaveOutCaption(ABlock) = rsIncludePill then
    IncludeBlockAt(ABlock)
  else
    LeaveOutBlockAt(ABlock);
end;

{ Every pair of the block goes out; a file left with nothing to commit
  is unticked instead. }
procedure TRepoFrame.LeaveOutBlockAt(ABlock: integer);
var
  Pairs: TGittanKeepArray;
  k, i: integer;
begin
  Pairs := BlockPairs(FChangeLines, FBlockStarts[ABlock]);
  if Length(Pairs) = 0 then
    Exit;
  for k := 0 to High(Pairs) do
    FLeftOut.Add(FCurrentPath, Pairs[k]);
  if AllLeftOut(FRawChangeLines, FLeftOut.Items(FCurrentPath)) then
  begin
    FLeftOut.Clear(FCurrentPath);
    i := StatIndexOf(FCurrentPath);
    SetCommitChosen(i, False);
    StatusNote(Format(rsLeftOutFile, [FCurrentPath]));
  end
  else
    StatusNote(Format(rsLeftOutBlock, [Pairs[0].Line, FCurrentPath]));
  LeftOutChanged;
end;

{ The block's pairs go back into the commit. In a file not ticked the
  file is ticked with this block alone: every other block shown is left
  out. }
procedure TRepoFrame.IncludeBlockAt(ABlock: integer);
var
  Pairs: TGittanKeepArray;
  b, k, i, Line: integer;
  Drop: array of boolean;
begin
  i := StatIndexOf(FCurrentPath);
  if not CommitChosen(i) then
  begin
    FLeftOut.Clear(FCurrentPath);
    for b := 0 to High(FBlockStarts) do
      if b <> ABlock then
      begin
        Pairs := BlockPairs(FChangeLines, FBlockStarts[b]);
        for k := 0 to High(Pairs) do
          FLeftOut.Add(FCurrentPath, Pairs[k]);
      end;
    SetCommitChosen(i, True);
  end
  else
  begin
    { The changes the block's lines are, each once, from the last. }
    Drop := nil;
    SetLength(Drop, FLeftOut.Count(FCurrentPath));
    Line := FBlockStarts[ABlock];
    while (Line < FChangeLines.Count) and (FChangeLines[Line][1] <> ' ') do
    begin
      if LineLeftOut(Line) and (FLeftOutOf[Line] <= High(Drop)) then
        Drop[FLeftOutOf[Line]] := True;
      Inc(Line);
    end;
    for k := High(Drop) downto 0 do
      if Drop[k] then
        FLeftOut.Remove(FCurrentPath, k);
  end;
  Pairs := BlockPairs(FChangeLines, FBlockStarts[ABlock]);
  if Length(Pairs) > 0 then
    StatusNote(Format(rsIncludedBlock, [Pairs[0].Line, FCurrentPath]));
  LeftOutChanged;
end;

{ The header's Include All: every change of the file goes in. }
procedure TRepoFrame.IncludeFile;
begin
  FLeftOut.Clear(FCurrentPath);
  StatusNote(Format(rsIncludedAll, [FCurrentPath]));
  LeftOutChanged;
end;

{ A keep includes the pairs it keeps (see the comment at the top). }
procedure TRepoFrame.IncludeKept(const APairs: TGittanKeepArray);
var
  Items: TGittanKeepArray;
  k, j: integer;
begin
  Items := FLeftOut.Items(FCurrentPath);
  for j := High(Items) downto 0 do
    for k := 0 to High(APairs) do
      if SameKeep(Items[j], APairs[k]) and (Items[j].Line = APairs[k].Line) then
      begin
        FLeftOut.Remove(FCurrentPath, j);
        Break;
      end;
end;

{ The tree's boxes, the section's count and the view follow. }
procedure TRepoFrame.LeftOutChanged;
begin
  ApplyCommitChecks;
  UpdateCommitState;
  RebuildKeeps;
end;

{ A click on a file's box takes the whole file in or out, so its
  changes left out go; when it is the shown file the view follows. }
procedure TRepoFrame.DropLeftOut(const APath: string);
begin
  if FLeftOut.Count(APath) = 0 then
    Exit;
  FLeftOut.Clear(APath);
  if (FView = gvChanges) and (APath = FCurrentPath) then
    RebuildKeeps;
end;

{ The chosen files with changes left out, as their text to commit: the
  work tree's with those changes as HEAD has them. A file whose changes
  left out are all gone goes in whole. False with the reason in AError
  when a file's diff cannot be taken or does not fit it. }
function TRepoFrame.CommitParts(APaths: TStrings; out AParts: TGittanCommitParts;
  out AError: string): boolean;
var
  Lines: TStringList;
  Stream: TFileStream;
  FileName: string;
  Content, Res: RawByteString;
  i, Found: integer;
begin
  Result := True;
  AParts := nil;
  AError := '';
  Lines := TStringList.Create;
  try
    for i := 0 to APaths.Count - 1 do
    begin
      if FLeftOut.Count(APaths[i]) = 0 then
        Continue;
      if not FRepo.FileChanges(APaths[i], Lines) then
      begin
        AError := FRepo.Error;
        Exit(False);
      end;
      Content := '';
      FileName := IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(APaths[i]);
      if FileExists(FileName) then
      begin
        Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
        try
          SetLength(Content, Stream.Size);
          if Stream.Size > 0 then
            Stream.ReadBuffer(Content[1], Stream.Size);
        finally
          Stream.Free;
        end;
      end;
      if not LeaveOutText(Content, Lines, FLeftOut.Items(APaths[i]), Res, Found, AError) then
      begin
        AError := APaths[i] + ': ' + AError;
        Exit(False);
      end;
      if Found = 0 then
        Continue;
      SetLength(AParts, Length(AParts) + 1);
      AParts[High(AParts)].Path := APaths[i];
      AParts[High(AParts)].Text := Res;
    end;
  finally
    Lines.Free;
  end;
end;

{ The pairs of changed lines the editor's selection touches, in
  APairs, and in AIncluding whether they would go into the commit (all
  of them are left out, or the file is not ticked) rather than out of
  it. A selection ending at the start of a row leaves that row out.
  False when it touches no changed line. }
function TRepoFrame.SelectedPairs(out APairs: TGittanKeepArray;
  out AIncluding: boolean): boolean;
var
  Sel: array of boolean;
  Pairs: TGittanKeepArray;
  i, r, X1, Y1, X2, Y2, b, k, s, Old, OldIdx, NewIdx: integer;
  HasSel, Hit, AllOut: boolean;

  procedure Mark(ALine: integer);
  begin
    if (ALine >= 0) and (ALine < FChangeLines.Count) and (FChangeLines[ALine][1] <> ' ') then
      Sel[ALine] := True;
  end;

begin
  APairs := nil;
  AIncluding := False;
  Result := False;
  if (FView <> gvChanges) or (FChangeLines = nil) then
    Exit;
  Sel := nil;
  SetLength(Sel, FChangeLines.Count);
  Hit := False;
  for i := 0 to Edit.Carets.Count - 1 do
  begin
    Edit.Carets[i].GetRange(X1, Y1, X2, Y2, HasSel);
    if not HasSel then
      Continue;
    if (X2 = 0) and (Y2 > Y1) then
      Dec(Y2);
    for r := Y1 to Y2 do
      if (r <= High(FRows)) and not FRows[r].Hidden then
      begin
        Mark(FRows[r].Line);
        if r <= High(FRowsOld) then
          Mark(FRowsOld[r].Line);
        Hit := True;
      end;
  end;
  if not Hit then
    Exit;
  AllOut := True;
  for b := 0 to High(FBlockStarts) do
  begin
    s := FBlockStarts[b];
    Pairs := BlockPairs(FChangeLines, s);
    Old := 0;
    while (s + Old < FChangeLines.Count) and (FChangeLines[s + Old][1] = '-') do
      Inc(Old);
    for k := 0 to High(Pairs) do
    begin
      OldIdx := -1;
      NewIdx := -1;
      if Pairs[k].HasOld then
        OldIdx := s + k;
      if Pairs[k].HasNew then
        NewIdx := s + Old + k;
      if ((OldIdx >= 0) and Sel[OldIdx]) or ((NewIdx >= 0) and Sel[NewIdx]) then
      begin
        SetLength(APairs, Length(APairs) + 1);
        APairs[High(APairs)] := Pairs[k];
        if not (LineLeftOut(OldIdx) or LineLeftOut(NewIdx)) then
          AllOut := False;
      end;
    end;
  end;
  Result := Length(APairs) > 0;
  AIncluding := Result and (AllOut or not ShownFileChosen);
end;

{ The selected lines out of the commit, or into it: in a file not ticked
  the file is ticked with those lines alone, as Include does for a
  block; one left with nothing to commit is unticked. }
procedure TRepoFrame.ToggleLeaveOutSelection;
var
  Pairs, All, Items: TGittanKeepArray;
  Including, Picked: boolean;
  b, k, j, i: integer;

  procedure LinesNote(const AOne, AMany: string);
  begin
    if Length(Pairs) = 1 then
      StatusNote(Format(AOne, [FCurrentPath]))
    else
      StatusNote(Format(AMany, [Length(Pairs), FCurrentPath]));
  end;

begin
  if not CanLeaveOut or not SelectedPairs(Pairs, Including) then
    Exit;
  i := StatIndexOf(FCurrentPath);
  if Including and not CommitChosen(i) then
  begin
    FLeftOut.Clear(FCurrentPath);
    for b := 0 to High(FBlockStarts) do
    begin
      All := BlockPairs(FChangeLines, FBlockStarts[b]);
      for k := 0 to High(All) do
      begin
        Picked := False;
        for j := 0 to High(Pairs) do
          if SameKeep(All[k], Pairs[j]) and (All[k].Line = Pairs[j].Line) then
            Picked := True;
        if not Picked then
          FLeftOut.Add(FCurrentPath, All[k]);
      end;
    end;
    SetCommitChosen(i, True);
    LinesNote(rsIncludedLine, rsIncludedLines);
  end
  else if Including then
  begin
    Items := FLeftOut.Items(FCurrentPath);
    for j := High(Items) downto 0 do
      for k := 0 to High(Pairs) do
        if SameKeep(Items[j], Pairs[k]) and (Items[j].Line = Pairs[k].Line) then
        begin
          FLeftOut.Remove(FCurrentPath, j);
          Break;
        end;
    LinesNote(rsIncludedLine, rsIncludedLines);
  end
  else
  begin
    Items := FLeftOut.Items(FCurrentPath);
    for k := 0 to High(Pairs) do
    begin
      Picked := False;
      for j := 0 to High(Items) do
        if SameKeep(Items[j], Pairs[k]) and (Items[j].Line = Pairs[k].Line) then
          Picked := True;
      if not Picked then
        FLeftOut.Add(FCurrentPath, Pairs[k]);
    end;
    if AllLeftOut(FRawChangeLines, FLeftOut.Items(FCurrentPath)) then
    begin
      FLeftOut.Clear(FCurrentPath);
      SetCommitChosen(i, False);
      StatusNote(Format(rsLeftOutFile, [FCurrentPath]));
    end
    else
      LinesNote(rsLeftOutLine, rsLeftOutLines);
  end;
  LeftOutChanged;
end;

{ File > Leave Change Out of Commit acts on the selected lines, else on
  the block the caret is in. }
procedure TRepoFrame.MenuLeaveOutClick(Sender: TObject);
var
  Pairs: TGittanKeepArray;
  Including: boolean;
begin
  if SelectedPairs(Pairs, Including) then
    ToggleLeaveOutSelection
  else if Edit.Carets.Count > 0 then
    ToggleLeaveOutAt(BlockAtRow(Edit.Carets[0].PosY));
end;

{ The item follows the caret, as Discard Change does, and is named for
  what it does to the selected lines or the block there (from
  UpdateDiscardItems). }
procedure TRepoFrame.UpdateLeaveOutItem;
var
  Block: integer;
  Pairs: TGittanKeepArray;
  Including: boolean;
begin
  if FLeaveOutItem = nil then
    Exit;
  { A selection over changed lines: the item is for those lines. }
  if CanLeaveOut and SelectedPairs(Pairs, Including) then
  begin
    FLeaveOutItem.Enabled := True;
    if Including then
      FLeaveOutItem.Caption := rsIncludeLinesItem
    else
      FLeaveOutItem.Caption := rsLeaveOutLinesItem;
    Exit;
  end;
  Block := -1;
  if CanLeaveOut and (Edit.Carets.Count > 0) then
    Block := BlockAtRow(Edit.Carets[0].PosY);
  FLeaveOutItem.Enabled := Block >= 0;
  if (Block >= 0) and (LeaveOutCaption(Block) = rsIncludePill) then
    FLeaveOutItem.Caption := rsIncludeItem
  else
    FLeaveOutItem.Caption := rsLeaveOutItem;
end;
