{ ---------------------------------------------------------------------------
  The merge editor
  ---------------------------------------------------------------------------
  Included by umain.pp. A conflicted file with markers can be resolved
  in three panes (gittan.mergeview): mine and theirs above, a box on
  every line of a conflict, and the result under them. It opens from the
  header's Merge Editor pill, File > Open in Merge Editor or the
  conflict's list in the band, and stays on for the conflicted files
  shown after it, until its Close pill; a file without markers, or one
  that is no conflict any more, shows the change view as before. The
  view is FView gvMerge, in the editor's place under the file header,
  whose pills are All Mine, All Theirs (Reset instead of the two once
  the result is edited by hand), Save and Close.

  Save writes the result over the file as one block (ResultBlock in
  gittan.merge, through gittan.discard, so a file that changed since
  it was read is left alone) and keeps it with the discards, so File >
  Undo Discard puts the conflicts back. When no markers are left the
  file is marked resolved and the next conflicted file is shown, as a
  pick in the change view does. A refresh while the file is unchanged
  on disk keeps the ticks; leaving the file with ticks or edits not
  saved asks first, and so does a file changed outside Gittan
  meanwhile, which Save then writes over. }

{ Whether two lists of lines are the same. }
function SameLines(const A, B: TStringArray): boolean;
var
  i: integer;
begin
  Result := Length(A) = Length(B);
  i := 0;
  while Result and (i < Length(A)) do
  begin
    Result := A[i] = B[i];
    Inc(i);
  end;
end;

function LinesOf(AList: TStrings): TStringArray;
var
  i: integer;
begin
  SetLength(Result, AList.Count);
  for i := 0 to AList.Count - 1 do
    Result[i] := AList[i];
end;

{ Whether the shown file can be opened in the merge editor: a conflicted
  text file with markers, against the work tree. }
function TRepoFrame.CanOpenMerge: boolean;
begin
  Result := (FRepo <> nil) and (FRepo.Root <> '') and (FCurrentPath <> '') and
    (FEditPath = '') and not FRepo.IsRange and (Length(FConflictStarts) > 0) and
    IsConflictPath(FCurrentPath) and not IsImagePath(FCurrentPath);
end;

procedure TRepoFrame.OpenMergeEditor;
begin
  if not CanOpenMerge then
    Exit;
  FMergeMode := True;
  ShowMergeView(FCurrentPath);
end;

{ Back to the change view of the file; ticks not saved are asked about. }
procedure TRepoFrame.CloseMergeEditor;
var
  Path: string;
begin
  Path := FMergePath;
  { A save that failed keeps the editor open, and leaving it asks again. }
  if not FlushMerge then
  begin
    FMergeAsked := False;
    Exit;
  end;
  FMergeMode := False;
  HideMergeView;
  ClearMerge;
  FMergePath := '';
  if (Path <> '') and IsChangedPath(Path) then
    ShowChanges(Path)
  else
    ShowSummary;
end;

procedure TRepoFrame.ShowMergeView(const APath: string);
var
  Lines: TStringList;
  Same: boolean;
begin
  Lines := TStringList.Create;
  try
    if not ReadMergeFile(IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(APath),
      Lines) then
    begin
      StatusNote(Format(rsMergeSaveFailed, [rsDiscardNoFile]), True);
      FMergeMode := False;
      ShowChanges(APath);
      Exit;
    end;
    { A refresh of the same file, unchanged on disk, keeps the ticks;
      changed, they stay when the user keeps them. }
    Same := (FMergeView.Merge <> nil) and (FMergePath = APath);
    if Same and not SameLines(FMergeView.Merge.FileLines, LinesOf(Lines)) then
      Same := KeepMergeChoices(LinesOf(Lines));
    FMergeAsked := False;
    LeaveEdit;
    AbandonHistoryJob;
    EndTimelapse;
    FView := gvMerge;
    FMergePath := APath;
    FSymbolBar.Visible := False;
    FFindBar.Visible := False;
    FSummaryBox.Visible := False;
    SetNavRow(-1);
    FImageDiff.Visible := False;
    FBinaryView.Visible := False;
    HideMarkdownPreview;
    Edit.Visible := False;
    FEditOld.Visible := False;
    FSideSplitter.Visible := False;
    FHeader.Visible := True;
    RestyleMergeView;
    if not Same then
    begin
      FMergeKeep := nil;
      FMergeView.Lexer := App.Lexers.ForFile(APath, FRepo.Root);
      FMergeView.Load(TGittanMerge.Create(Lines, FOperation = 'rebasing'));
    end;
  finally
    Lines.Free;
  end;
  ApplyLayout;
  FMergeView.Visible := True;
  FMergeView.BringToFront;
  SetMergeActions;
  FSummary.Selected := APath;
  Edit.FileName := IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(APath);
  UpdateChangeNav;
  UpdateDiscardItems;
  UpdateStatus;
end;

{ Leaving the view asks about ticks not saved, unless FlushMerge asked
  on the way here. }
procedure TRepoFrame.HideMergeView;
begin
  if (FMergeView <> nil) and FMergeView.Visible then
  begin
    if not FMergeAsked then
      FlushMerge;
    FMergeView.Visible := False;
  end;
end;

procedure TRepoFrame.ClearMerge;
begin
  FMergeView.Clear;
  FMergeKeep := nil;
end;

{ The file shown in the merge editor as it is on disk now. }
function TRepoFrame.ReadMergeLines(out ALines: TStringArray): boolean;
var
  Lines: TStringList;
begin
  ALines := nil;
  Lines := TStringList.Create;
  try
    Result := ReadMergeFile(IncludeTrailingPathDelimiter(FRepo.Root) +
      SetDirSeparators(FMergePath), Lines);
    if Result then
      ALines := LinesOf(Lines);
  finally
    Lines.Free;
  end;
end;

{ The file in the merge editor changed on disk, to ADisk: the ticks and
  edits stay when they were kept against this text before, or when the
  user keeps them; Save then writes over the change. }
function TRepoFrame.KeepMergeChoices(const ADisk: TStringArray): boolean;
begin
  if (FMergeKeep <> nil) and SameLines(ADisk, FMergeKeep) then
    Exit(True);
  Result := False;
  if not MergeDirty then
    Exit;
  HoldRefresh;
  try
    Result := AskDlg(rsAppName, Format(rsMergeChangedAsk, [FMergePath]), mtConfirmation,
      [mrYes, rsMergeKeepChoices, 'IsDefault', mrNo, rsMergeReadAgain, 'NoCancel'], 0) = mrYes;
  finally
    ReleaseRefresh;
  end;
  if Result then
    FMergeKeep := Copy(ADisk);
end;

{ The panes take the editor's font, zoom, colors and scroll bars. }
procedure TRepoFrame.RestyleMergeView;
begin
  if FMergeView = nil then
    Exit;
  FMergeView.Font.Assign(Font);
  ApplyEditorColors(FMergeView.EditMine);
  ApplyEditorColors(FMergeView.EditTheirs);
  ApplyEditorColors(FMergeView.EditResult);
  FMergeView.Restyle(Edit, @FScrollbarTheme);
end;

procedure TRepoFrame.SetMergeActions;
begin
  if FMergeView.Edited then
    FHeader.SetActions([rsMergeReset, rsMergeSave, rsMergeClose])
  else
    FHeader.SetActions([rsMergeAllMine, rsMergeAllTheirs, rsMergeSave, rsMergeClose]);
end;

procedure TRepoFrame.MergeHeaderAction(AIndex: integer);
begin
  if FMergeView.Edited then
    case AIndex of
      0:
      begin
        FMergeView.ResetResult;
        SetMergeActions;
      end;
      1: SaveMerge(True);
      2: CloseMergeEditor;
    end
  else
    case AIndex of
      0: FMergeView.PickEverywhere(msMine);
      1: FMergeView.PickEverywhere(msTheirs);
      2: SaveMerge(True);
      3: CloseMergeEditor;
    end;
end;

{ A tick or the first key typed in the result: the pills follow. }
procedure TRepoFrame.MergeChanged(Sender: TObject);
begin
  SetMergeActions;
end;

{ Whether the merge editor holds anything the file does not: a tick or
  an edit. }
function TRepoFrame.MergeDirty: boolean;
begin
  Result := (FMergeView <> nil) and (FMergeView.Merge <> nil) and
    (FMergeView.Edited or (FMergeView.Merge.ResolvedCount > 0));
end;

{ Writes the result over the file. With ARefresh the repository is
  refreshed and the status bar says what is left, and a file with no
  conflict left is marked resolved and the next conflicted one shown;
  without (on the way out of the file) the write is all. }
function TRepoFrame.SaveMerge(ARefresh: boolean): boolean;
var
  B: TGittanDiscard;
  Path, Err: string;
  Remaining, i: integer;
  Marked, Same: boolean;
begin
  Result := False;
  if (FMergeView.Merge = nil) or (FMergePath = '') or (FRepo.Root = '') then
    Exit;
  Path := FMergePath;
  B := FMergeView.Merge.ResultBlock(FMergeView.ResultLines,
    IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(Path));
  { Kept over a change on disk: written over that. }
  if FMergeKeep <> nil then
    B.NewLines := Copy(FMergeKeep);
  Same := Length(B.OldLines) = Length(B.NewLines);
  i := 0;
  while Same and (i <= High(B.OldLines)) do
  begin
    Same := B.OldLines[i] = B.NewLines[i];
    Inc(i);
  end;
  if Same then
  begin
    StatusNote(rsMergeNothing);
    Exit(True);
  end;
  if not DiscardBlock(B, Err) then
  begin
    StatusNote(Format(rsMergeSaveFailed, [Err]), True);
    Exit;
  end;
  Result := True;
  NoteDiscard(B);
  { What is on disk now is read again. }
  ClearMerge;
  Marked := ResolveIfDone(Path, Remaining);
  if Marked then
    StatusNote(Format(rsResolvedLast, [Path]))
  else if Remaining = 1 then
    StatusNote(Format(rsMergeSavedOne, [Path]))
  else if Remaining > 1 then
    StatusNote(Format(rsMergeSaved, [Path, Remaining]));
  if not ARefresh then
  begin
    UpdateDiscardItems;
    Exit;
  end;
  RefreshRepository;
  UpdateDiscardItems;
  if Marked then
    ShowNextConflict(Path, True);
end;

{ Leaving the file shown in the merge editor with ticks or edits not
  saved asks whether to save them; a file changed on disk since it was
  read is named so, and Save writes over it. With ACancel (a close) the
  question has Cancel, and Don't Save leaves the ticks for a close that
  is called off. False when the result stays: Cancel, or a save that
  failed (the status bar says why), so the next leave asks again. }
function TRepoFrame.FlushMerge(ACancel: boolean): boolean;
var
  Disk: TStringArray;
  Outside: boolean;
  Ask: string;
  Answer: TModalResult;
begin
  Result := True;
  if not ACancel then
    FMergeAsked := True;
  if not MergeDirty or (FMergePath = '') then
    Exit;
  Outside := ReadMergeLines(Disk) and not SameLines(Disk, FMergeView.Merge.FileLines) and
    not SameLines(Disk, FMergeKeep);
  if Outside then
    Ask := Format(rsMergeChangedSaveAsk, [FMergePath])
  else
    Ask := Format(rsMergeSaveAsk, [FMergePath]);
  HoldRefresh;
  try
    if ACancel then
      Answer := AskDlg(rsAppName, Ask, mtConfirmation, [mrYes, rsSaveAction, 'IsDefault',
        mrNo, rsDontSave, mrCancel, rsCancelButton, 'IsCancel'], 0)
    else
      Answer := AskDlg(rsAppName, Ask, mtConfirmation, [mrYes, rsSaveAction, 'IsDefault',
        mrNo, rsDontSave, 'NoCancel'], 0);
    case Answer of
      mrYes:
      begin
        if Outside then
          FMergeKeep := Disk;
        Result := SaveMerge(False);
        if Result then
          ClearMerge;
      end;
      mrNo:
        if not ACancel then
          ClearMerge;
      else
        Result := False;
    end;
  finally
    ReleaseRefresh;
  end;
end;

{ File > Open in Merge Editor closes it again while it is shown. }
procedure TRepoFrame.MenuMergeEditorClick(Sender: TObject);
begin
  if FView = gvMerge then
    CloseMergeEditor
  else
    OpenMergeEditor;
end;
