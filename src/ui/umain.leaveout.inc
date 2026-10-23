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
function TForm1.CanLeaveOut: boolean;
begin
  Result := CanDiscard and CommitChoosing and (FCommitJob = nil) and
    (FConflictRoles = nil) and (StatIndexOf(FCurrentPath) >= 0);
end;

{ Whether the shown file goes into the commit at all. }
function TForm1.ShownFileChosen: boolean;
var
  i: integer;
begin
  i := StatIndexOf(FCurrentPath);
  Result := (i >= 0) and CommitChosen(i);
end;

{ FLeftOutOf for the shown diff: for each line of FChangeLines the
  change left out it is, or -1; none while blocks cannot be left out or
  the file is not chosen. The changes the diff no longer holds go. }
procedure TForm1.ApplyLeftOut;
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
function TForm1.LineLeftOut(ALine: integer): boolean;
begin
  Result := (FView = gvChanges) and (ALine >= 0) and (ALine <= High(FLeftOutOf)) and
    (FLeftOutOf[ALine] >= 0);
end;

{ Whether any line of block ABlock is left out. }
function TForm1.BlockLeftOut(ABlock: integer): boolean;
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
function TForm1.LeaveOutCaption(ABlock: integer): string;
begin
  if not ShownFileChosen or BlockLeftOut(ABlock) then
    Result := rsIncludePill
  else
    Result := rsLeaveOutPill;
end;

{ The middle pill's hint, for the caption LeaveOutCaption gives. }
function TForm1.LeaveOutHint(ABlock: integer): string;
begin
  if LeaveOutCaption(ABlock) = rsIncludePill then
    Result := rsIncludePillHint
  else
    Result := rsLeaveOutPillHint;
end;

{ The middle pill: the block goes out of the commit, or back in. }
procedure TForm1.ToggleLeaveOutAt(ABlock: integer);
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
procedure TForm1.LeaveOutBlockAt(ABlock: integer);
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
procedure TForm1.IncludeBlockAt(ABlock: integer);
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
procedure TForm1.IncludeFile;
begin
  FLeftOut.Clear(FCurrentPath);
  StatusNote(Format(rsIncludedAll, [FCurrentPath]));
  LeftOutChanged;
end;

{ A keep includes the pairs it keeps (see the comment at the top). }
procedure TForm1.IncludeKept(const APairs: TGittanKeepArray);
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
procedure TForm1.LeftOutChanged;
begin
  ApplyCommitChecks;
  UpdateCommitState;
  RebuildKeeps;
end;

{ A click on a file's box takes the whole file in or out, so its
  changes left out go; when it is the shown file the view follows. }
procedure TForm1.DropLeftOut(const APath: string);
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
function TForm1.CommitParts(APaths: TStrings; out AParts: TGittanCommitParts;
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

{ File > Leave Change Out of Commit acts on the block the caret is in. }
procedure TForm1.MenuLeaveOutClick(Sender: TObject);
begin
  if Edit.Carets.Count > 0 then
    ToggleLeaveOutAt(BlockAtRow(Edit.Carets[0].PosY));
end;

{ The item follows the caret, as Discard Change does, and is named for
  what it does to the block there (from UpdateDiscardItems). }
procedure TForm1.UpdateLeaveOutItem;
var
  Block: integer;
begin
  if FLeaveOutItem = nil then
    Exit;
  Block := -1;
  if CanLeaveOut and (Edit.Carets.Count > 0) then
    Block := BlockAtRow(Edit.Carets[0].PosY);
  FLeaveOutItem.Enabled := Block >= 0;
  if (Block >= 0) and (LeaveOutCaption(Block) = rsIncludePill) then
    FLeaveOutItem.Caption := rsIncludeItem
  else
    FLeaveOutItem.Caption := rsLeaveOutItem;
end;
