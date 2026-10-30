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
  saved asks first. }

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
  FlushMerge;
  FMergeMode := False;
  HideMergeView;
  FMergeView.Clear;
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
  i: integer;
  Old: TStringArray;
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
    { A refresh of the same file, unchanged on disk, keeps the ticks. }
    Same := (FMergeView.Merge <> nil) and (FMergePath = APath);
    if Same then
    begin
      Old := FMergeView.Merge.FileLines;
      Same := Length(Old) = Lines.Count;
      i := 0;
      while Same and (i < Lines.Count) do
      begin
        Same := Old[i] = Lines[i];
        Inc(i);
      end;
    end;
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

procedure TRepoFrame.HideMergeView;
begin
  if (FMergeView <> nil) and FMergeView.Visible then
    FMergeView.Visible := False;
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
  SetLength(FDiscards, Length(FDiscards) + 1);
  FDiscards[High(FDiscards)] := B;
  { What is on disk now is read again. }
  FMergeView.Clear;
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
  saved asks whether to save them. }
procedure TRepoFrame.FlushMerge;
begin
  if not MergeDirty or (FMergePath = '') then
    Exit;
  HoldRefresh;
  try
    if AskDlg(rsAppName, Format(rsMergeSaveAsk, [FMergePath]), mtConfirmation,
      [mrYes, rsSaveAction, 'IsDefault', mrNo, rsDontSave, 'NoCancel'], 0) = mrYes then
      SaveMerge(False);
    FMergeView.Clear;
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
