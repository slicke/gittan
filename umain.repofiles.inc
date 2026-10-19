{ ---------------------------------------------------------------------------
  The Repository section
  ---------------------------------------------------------------------------
  Under the tree of changed files sits a section with the repository's
  own files (gittan.repofiles): .gitignore and its kin at the root and
  everything under .github, changed or not, so they are at hand when a
  file shows up that should not. It is a header that folds, remembered
  in the settings, over a second tree like the first, in a panel at the
  bottom of the tree panel; the panel is as high as the rows, up to half
  the panel, and hidden while there is nothing to list. The exclude file
  of the git directory, .git/info/exclude, is listed last when it
  exists. A click shows the file through ShowRepoFile, so a changed one
  is selected in the tree above with its diff, and only one of the trees
  keeps a selection. The files listed here are the ones the editor lets
  the user change; see "Editing the repository's files" below. }
procedure TForm1.SetupRepoFiles;
begin
  FRepoPanel := TPanel.Create(Self);
  FRepoPanel.BevelOuter := bvNone;
  FRepoPanel.Caption := '';
  FRepoPanel.Align := alBottom;
  FRepoPanel.Visible := False;
  FRepoPanel.Parent := FTreePanel;
  FRepoHeader := TGittanSectionHeader.Create(Self);
  FRepoHeader.Title := rsRepoFiles;
  FRepoHeader.Align := alTop;
  FRepoHeader.OnToggle := @RepoHeaderToggle;
  FRepoHeader.Parent := FRepoPanel;
  FRepoTree := TTreeView.Create(Self);
  FRepoTree.BorderStyle := bsNone;
  FRepoTree.Images := TreeImages;
  FRepoTree.ReadOnly := True;
  FRepoTree.Options := FileTree.Options;
  FRepoTree.OnSelectionChanged := @RepoTreeSelectionChanged;
  FRepoTree.Align := alClient;
  FRepoTree.Parent := FRepoPanel;
  FTreePanel.OnResize := @TreePanelResize;
  ColorRepoHeader;
  LayoutRepoFiles;
end;

{ The header takes the file header's palette, the gutter's shade. }
procedure TForm1.ColorRepoHeader;
begin
  if FDark then
    FRepoHeader.SetColors(RGBToColor(37, 37, 38), Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(58, 58, 59), RGBToColor(62, 62, 62))
  else
    FRepoHeader.SetColors(RGBToColor(246, 246, 246), RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(232, 232, 232), RGBToColor(222, 222, 222));
  if FSubHeader <> nil then
    if FDark then
      FSubHeader.SetColors(RGBToColor(37, 37, 38), Edit.Colors.TextFont,
        RGBToColor(150, 150, 150), RGBToColor(58, 58, 59), RGBToColor(62, 62, 62))
    else
      FSubHeader.SetColors(RGBToColor(246, 246, 246), RGBToColor(30, 30, 30),
        RGBToColor(110, 110, 110), RGBToColor(232, 232, 232), RGBToColor(222, 222, 222));
end;

{ Fills the section's tree from ListRepoFiles: the root files in their
  fixed order, then .github as a folder, every folder open, then the
  exclude file as one row (Data 2, where the others have 1), since it
  is not under the root. }
procedure TForm1.FillRepoFiles;
var
  Files: TStringList;
  Path, Part: string;
  DirNode, Node: TTreeNode;
  i, Start, Sep, Count: integer;
begin
  Files := TStringList.Create;
  FRepoTree.BeginUpdate;
  try
    FRepoTree.Items.Clear;
    ListRepoFiles(FRepo.Root, Files);
    Count := Files.Count;
    for i := 0 to Count - 1 do
    begin
      Path := Files[i];
      DirNode := nil;
      Start := 1;
      repeat
        Sep := Pos('/', Path, Start);
        if Sep = 0 then
          Break;
        Part := Copy(Path, Start, Sep - Start);
        Start := Sep + 1;
        if DirNode = nil then
          Node := FRepoTree.Items.GetFirstNode
        else
          Node := DirNode.GetFirstChild;
        while (Node <> nil) and (Node.Text <> Part) do
          Node := Node.GetNextSibling;
        if Node = nil then
        begin
          Node := FRepoTree.Items.AddChild(DirNode, Part);
          Node.ImageIndex := iconFolder;
          Node.SelectedIndex := iconFolder;
        end;
        DirNode := Node;
      until False;
      Node := FRepoTree.Items.AddChild(DirNode, Copy(Path, Start, MaxInt));
      Node.Data := Pointer(1);
      Node.ImageIndex := iconFile;
      Node.SelectedIndex := iconFile;
    end;
    if (FExcludePath <> '') and FileExists(FExcludePath) then
    begin
      Node := FRepoTree.Items.AddChild(nil, ExcludeShown);
      Node.Data := Pointer(2);
      Node.ImageIndex := iconFile;
      Node.SelectedIndex := iconFile;
      Inc(Count);
    end;
    FRepoTree.FullExpand;
  finally
    FRepoTree.EndUpdate;
    Files.Free;
  end;
  if Count > 0 then
    FRepoHeader.Detail := IntToStr(Count)
  else
    FRepoHeader.Detail := '';
  FRepoPanel.Visible := Count > 0;
  LayoutRepoFiles;
end;

{ A section's panel is the header alone while folded, else the header
  and the rows in view, within half the tree panel, or a third of it
  each while both the Repository and the Submodules sections show. }
procedure TForm1.LayoutRepoFiles;
var
  Limit: integer;

  function SectionHeight(AHeader: TGittanSectionHeader; ATree: TTreeView): integer;
  var
    Rows, RowHeight: integer;
    Node: TTreeNode;
  begin
    Result := AHeader.Height;
    ATree.Visible := AHeader.Expanded;
    if not AHeader.Expanded then
      Exit;
    Rows := 0;
    Node := ATree.Items.GetFirstVisibleNode;
    while Node <> nil do
    begin
      Inc(Rows);
      Node := Node.GetNextVisible;
    end;
    RowHeight := ATree.DefaultItemHeight;
    if RowHeight < 8 then
      RowHeight := 20;
    Result := Result + Min(Rows * RowHeight + 4, Limit);
  end;

begin
  Limit := FTreePanel.ClientHeight div 2;
  if (FSubPanel <> nil) and FSubPanel.Visible and FRepoPanel.Visible then
    Limit := FTreePanel.ClientHeight div 3;
  FRepoPanel.Height := SectionHeight(FRepoHeader, FRepoTree);
  if FSubPanel <> nil then
    FSubPanel.Height := SectionHeight(FSubHeader, FSubTree);
end;

procedure TForm1.RepoHeaderToggle(Sender: TObject);
begin
  LayoutRepoFiles;
end;

procedure TForm1.TreePanelResize(Sender: TObject);
begin
  LayoutRepoFiles;
  {$IFDEF OWNBAR}
  { The title bar's shade follows the sidebar's width. }
  if FOwnBar <> nil then
    FOwnBar.Invalidate;
  {$ENDIF}
end;

procedure TForm1.RepoTreeSelectionChanged(Sender: TObject);
var
  Node: TTreeNode;
begin
  Node := FRepoTree.Selected;
  if (Node = nil) or (Node.Data = nil) or (FRepo.Root = '') then
    Exit;
  FSubTree.Selected := nil;
  if Node.Data = Pointer(2) then
  begin
    { The exclude file is never in the tree above: it is not tracked. }
    FileTree.Selected := nil;
    OpenFile(FExcludePath);
    Exit;
  end;
  ShowRepoFile(Node.GetTextPath);
end;

{ Selects the row of APath in the section without showing the file, or
  clears the selection for '', as after a refresh rebuilt the rows. }
procedure TForm1.SelectRepoNode(const APath: string);
var
  Node: TTreeNode;
begin
  FRepoTree.OnSelectionChanged := nil;
  try
    FRepoTree.Selected := nil;
    if APath = '' then
      Exit;
    Node := FRepoTree.Items.GetFirstNode;
    while Node <> nil do
    begin
      if (Node.Data <> nil) and (Node.GetTextPath = APath) then
      begin
        FRepoTree.Selected := Node;
        Exit;
      end;
      Node := Node.GetNext;
    end;
  finally
    FRepoTree.OnSelectionChanged := @RepoTreeSelectionChanged;
  end;
end;

{ ---------------------------------------------------------------------------
  Add to .gitignore
  ---------------------------------------------------------------------------
  The file menu offers to hide an untracked file: the patterns that would
  (IgnorePatterns: the file itself, its extension, its folder) as the
  items of two submenus, one for .gitignore at the root, one for
  .git/info/exclude, which is not committed. A tracked file cannot be
  ignored, so the menus are disabled for anything else. The pattern is
  kept in the item's Hint, since the caption doubles ampersands. }
procedure TForm1.FillIgnoreMenus(const APath: string);
var
  Patterns: TStringArray;
  Untracked: boolean;
  i: integer;

  procedure AddTo(AMenu: TMenuItem; const APattern: string);
  var
    Item: TMenuItem;
  begin
    Item := TMenuItem.Create(AMenu);
    Item.Caption := StringReplace(APattern, '&', '&&', [rfReplaceAll]);
    Item.Hint := APattern;
    Item.OnClick := @MenuIgnoreClick;
    AMenu.Add(Item);
  end;

begin
  FIgnoreMenu.Clear;
  FExcludeMenu.Clear;
  Untracked := False;
  for i := 0 to High(FStats) do
    if FStats[i].Path = APath then
    begin
      Untracked := FStats[i].Kind = ckUntracked;
      Break;
    end;
  Patterns := IgnorePatterns(APath);
  for i := 0 to High(Patterns) do
  begin
    AddTo(FIgnoreMenu, Patterns[i]);
    AddTo(FExcludeMenu, Patterns[i]);
  end;
  FIgnoreMenu.Enabled := Untracked and (Length(Patterns) > 0);
  FExcludeMenu.Enabled := FIgnoreMenu.Enabled;
end;

{ Writes the pattern and reloads: the file leaves the tree, and a
  .gitignore joins it as changed. }
procedure TForm1.MenuIgnoreClick(Sender: TObject);
var
  Item: TMenuItem;
  FileName, Shown: string;
begin
  Item := Sender as TMenuItem;
  if FRepo.Root = '' then
    Exit;
  if Item.Parent = FExcludeMenu then
  begin
    FileName := FExcludePath;
    Shown := ExcludeShown;
  end
  else
  begin
    Shown := RepoRootFiles[0];
    FileName := IncludeTrailingPathDelimiter(FRepo.Root) + Shown;
  end;
  if (FileName <> '') and AddIgnorePattern(FileName, Item.Hint) then
  begin
    StatusNote(Format(rsIgnoreAdded, [Item.Hint, Shown]));
    RefreshRepository;
  end
  else
    StatusNote(Format(rsIgnoreFailed, [Shown]), True);
end;

{ ---------------------------------------------------------------------------
  Editing the repository's files
  ---------------------------------------------------------------------------
  The editor is a viewer, except for the files the Repository section
  lists: a .gitignore or a workflow is what one wants to touch while
  looking at a change, so the file view of one of them is open to edits.
  OpenFile asks RepoFileName and calls BeginEdit, which lifts read-only
  mode and puts Revert and Save pills in the header (Cmd+Z and Shift+Cmd+Z
  undo and redo through the editor's own keymap); the diff view of such a
  file offers an Edit pill that opens the file view. A dot after the
  file name, the pills and File > Save (Cmd+S) follow Edit.Modified
  through UpdateEditState. Whatever replaces the editor's text (OpenFile,
  ShowText, ShowSummary, OpenRepository) first runs FlushEdit, which
  offers to save unsaved changes, then LeaveEdit; closing the window
  asks through FormCloseQuery, with a Cancel. A save writes the file
  with the encoding and line ends it was read with, notes it in the
  status bar and refreshes the repository, so the tree shows the result
  at once; the watcher otherwise leaves an edit alone (RefreshRepository)
  and the header says when the file changed on disk behind it. }

{ Whether AFileName, a full name, is one of the repository's own files:
  the exclude file, or a file under the root that IsRepoFile accepts. }
function TForm1.RepoFileName(const AFileName: string): boolean;
var
  Root, Rel: string;
begin
  if (AFileName <> '') and (AFileName = FExcludePath) then
    Exit(True);
  if FRepo.Root = '' then
    Exit(False);
  Root := IncludeTrailingPathDelimiter(FRepo.Root);
  if Copy(AFileName, 1, Length(Root)) <> Root then
    Exit(False);
  Rel := Copy(AFileName, Length(Root) + 1, MaxInt);
  Result := IsRepoFile(StringReplace(Rel, PathDelim, '/', [rfReplaceAll]));
end;

{ Opens the loaded file AFileName to edits. }
procedure TForm1.BeginEdit(const AFileName: string);
begin
  FEditPath := AFileName;
  FEditStamp := FileAge(AFileName);
  Edit.ModeReadOnly := False;
  FHeader.SetActions([rsRevertAction, rsSaveAction]);
  UpdateEditState;
end;

{ Offers to save unsaved changes before the editor's text is replaced.
  Declining drops them; there is no way to stay, since the caller is
  already on its way elsewhere. }
procedure TForm1.FlushEdit;
begin
  if (FEditPath = '') or not Edit.Modified then
    Exit;
  if QuestionDlg(rsAppName, Format(rsSaveAsk, [ExtractFileName(FEditPath)]),
    mtConfirmation, [mrYes, rsSaveAction, 'IsDefault', mrNo, rsDontSave], 0) = mrYes then
    SaveEdit(False)
  else
    Edit.Modified := False;
end;

{ Ends the edit: the editor is read-only again. The pills go with the
  next title the header gets. }
procedure TForm1.LeaveEdit;
begin
  if FEditPath = '' then
    Exit;
  FEditPath := '';
  Edit.ModeReadOnly := True;
  Edit.Modified := False;
  UpdateEditState;
end;

{ The dot, the pills and File > Save follow whether there is anything to
  save. The pills are left alone outside an edit: the diff view has one
  of its own. }
procedure TForm1.UpdateEditState;
var
  Dirty: boolean;
begin
  Dirty := (FEditPath <> '') and Edit.Modified;
  FHeader.SetModified(Dirty);
  if FEditPath <> '' then
  begin
    FHeader.SetActionEnabled(0, Dirty);
    FHeader.SetActionEnabled(1, Dirty);
  end;
  if FSaveItem <> nil then
    FSaveItem.Enabled := Dirty;
end;

{ Writes the edited file; ARefresh reloads the repository so the tree
  shows the result at once. False when the write failed, which the
  status bar says. }
function TForm1.SaveEdit(ARefresh: boolean): boolean;
var
  Shown: string;
begin
  Result := False;
  if FEditPath = '' then
    Exit;
  Shown := ExtractFileName(FEditPath);
  try
    Edit.SaveToFile(FEditPath);
  except
    on E: Exception do
    begin
      StatusNote(Format(rsSaveFailed, [Shown, E.Message]), True);
      Exit;
    end;
  end;
  FEditStamp := FileAge(FEditPath);
  FHeader.SetNote('');
  StatusNote(Format(rsSaved, [Shown]));
  Result := True;
  if ARefresh then
    RefreshRepository;
end;

{ Drops the changes and loads the file from disk again, at the same
  place, after asking: the undo history goes with them. }
procedure TForm1.RevertEdit;
var
  TopLine: integer;
begin
  if (FEditPath = '') or not Edit.Modified then
    Exit;
  if QuestionDlg(rsAppName, Format(rsRevertAsk, [ExtractFileName(FEditPath)]),
    mtConfirmation, [mrYes, rsRevertAction, mrCancel, rsCancelButton, 'IsCancel'], 0) <> mrYes then
    Exit;
  TopLine := Edit.LineTop;
  Edit.Modified := False;
  OpenFile(FEditPath);
  Edit.LineTop := Min(TopLine, Max(Edit.Strings.Count - 1, 0));
end;

{ A pill in the header: Revert or Save during an edit, else Edit on the
  diff view of a repository file, which opens its file view; the file
  stays selected in the section, not in the tree above, so a click there
  brings the diff back. }
procedure TForm1.HeaderAction(Sender: TObject; AIndex: integer);
var
  Path: string;
begin
  if FEditPath <> '' then
  begin
    if AIndex = 0 then
      RevertEdit
    else
      SaveEdit(True);
    Exit;
  end;
  if ConflictHeaderAction(AIndex) then
    Exit;
  if FView = gvSubmodule then
  begin
    OpenShownSubmodule;
    Exit;
  end;
  if (FView <> gvChanges) or (FCurrentPath = '') or (FRepo.Root = '') then
    Exit;
  Path := FCurrentPath;
  FileTree.Selected := nil;
  OpenFile(IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(Path));
  SelectRepoNode(Path);
end;

procedure TForm1.EditChangeModified(Sender: TObject);
begin
  UpdateEditState;
end;

procedure TForm1.MenuSaveClick(Sender: TObject);
begin
  if FEditPath <> '' then
    SaveEdit(True);
end;

{ Unsaved changes hold the window open until they are saved or dropped. }
procedure TForm1.FormCloseQuery(Sender: TObject; var CanClose: boolean);
begin
  CanClose := True;
  if (FEditPath = '') or not Edit.Modified then
    Exit;
  case QuestionDlg(rsAppName, Format(rsSaveAsk, [ExtractFileName(FEditPath)]),
      mtConfirmation, [mrYes, rsSaveAction, 'IsDefault', mrNo, rsDontSave,
      mrCancel, rsCancelButton, 'IsCancel'], 0) of
    mrYes: CanClose := SaveEdit(False);
    mrNo: Edit.Modified := False;
    else
      CanClose := False;
  end;
end;
