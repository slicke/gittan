{ ---------------------------------------------------------------------------
  The Config section
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
procedure TRepoFrame.SetupRepoFiles;
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
procedure TRepoFrame.ColorRepoHeader;
var
  P: TGittanPalette;
begin
  P := Palette;
  FRepoHeader.SetColors(P.Shade, P.Text, P.Dim, P.Raised, P.Line);
  if FSubHeader <> nil then
    FSubHeader.SetColors(P.Shade, P.Text, P.Dim, P.Raised, P.Line);
end;

{ Fills the section's tree from ListRepoFiles: the root files in their
  fixed order, then .github as a folder, every folder open, then the
  exclude file as one row (Data 2, where the others have 1), since it
  is not under the root. }
procedure TRepoFrame.FillRepoFiles;
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
  each while both the Repository and the Submodules sections show. The
  tree of changed files gives way last: it keeps room for its rows as
  long as the open sections keep MinSectionRows each. }
procedure TRepoFrame.LayoutRepoFiles;
const
  { The least the tree of changed files keeps of the panel. }
  MinFileTree = 80;
  { The rows an open section keeps before the tree of changed files
    gives up any of its own. }
  MinSectionRows = 2;
var
  Limit, Room, Open, TreeKeep, TreeRows: integer;
  Node: TTreeNode;

  { A panel at the bottom grows or shrinks at its top edge: alBottom
    orders the panels by their bottom edges, and one that kept its top
    could end up above the one it stood under. }
  procedure SetHeight(APanel: TPanel; AHeight: integer);
  begin
    APanel.SetBounds(APanel.Left, APanel.Top + APanel.Height - AHeight, APanel.Width, AHeight);
  end;

  function Opened(APanel: TPanel; AHeader: TGittanSectionHeader): boolean;
  begin
    Result := (APanel <> nil) and APanel.Visible and AHeader.Expanded;
  end;

  function SectionHeight(AHeader: TGittanSectionHeader; ATree: TTreeView): integer;
  var
    Rows, RowHeight: integer;
    Node: TTreeNode;
  begin
    Result := AHeader.Height;
    RowHeight := ATree.DefaultItemHeight;
    if RowHeight < 8 then
      RowHeight := 20;
    { A list with no room for a row is not shown at all: a tree view
      laid out 0 px high never draws its rows on Cocoa, even once it
      has room. }
    ATree.Visible := AHeader.Expanded and (Limit >= RowHeight);
    if not ATree.Visible then
      Exit;
    Rows := 0;
    Node := ATree.Items.GetFirstVisibleNode;
    while Node <> nil do
    begin
      Inc(Rows);
      Node := Node.GetNextVisible;
    end;
    Result := Result + Min(Rows * RowHeight + 4, Limit);
  end;

begin
  Limit := FTreePanel.ClientHeight div 2;
  if (FSubPanel <> nil) and FSubPanel.Visible and FRepoPanel.Visible then
    Limit := FTreePanel.ClientHeight div 3;
  { The lists share what the page rows, the headers and the Commit
    section leave, less the tree of changed files' share, which got
    nothing when the window was low (nine submodules and the Commit
    section took it all, and the tree never drew again). }
  Room := FTreePanel.ClientHeight;
  if FSideNav <> nil then
    Dec(Room, FSideNav.Top + FSideNav.Height);
  if (FCommitPanel <> nil) and FCommitPanel.Visible then
    Dec(Room, FCommitPanel.Height);
  if FRepoPanel.Visible then
    Dec(Room, FRepoHeader.Height);
  if (FSubPanel <> nil) and FSubPanel.Visible then
    Dec(Room, FSubHeader.Height);
  Open := Ord(Opened(FRepoPanel, FRepoHeader)) + Ord(Opened(FSubPanel, FSubHeader));
  { What the tree of changed files keeps: its rows (the changes' header
    row and the placeholder fit in MinFileTree), less what the open
    sections need to keep their least. }
  TreeRows := 0;
  Node := FileTree.Items.GetFirstVisibleNode;
  while Node <> nil do
  begin
    Inc(TreeRows);
    Node := Node.GetNextVisible;
  end;
  TreeKeep := Max(Px(MinFileTree), TreeRows * Max(FileTree.DefaultItemHeight, 8) + 4);
  TreeKeep := Max(Px(MinFileTree), Min(TreeKeep,
    Room - Open * (MinSectionRows * Max(FRepoTree.DefaultItemHeight, 8) + 4)));
  Dec(Room, TreeKeep);
  if Open > 0 then
    Limit := Min(Limit, Max(0, Room) div Open);
  SetHeight(FRepoPanel, SectionHeight(FRepoHeader, FRepoTree));
  if FSubPanel <> nil then
    SetHeight(FSubPanel, SectionHeight(FSubHeader, FSubTree));
end;

procedure TRepoFrame.RepoHeaderToggle(Sender: TObject);
begin
  LayoutRepoFiles;
end;

procedure TRepoFrame.FileTreeFolded(Sender: TObject; Node: TTreeNode);
begin
  if not FTreeFolding then
    LayoutRepoFiles;
end;

procedure TRepoFrame.TreePanelResize(Sender: TObject);
begin
  LayoutRepoFiles;
  {$IFDEF OWNBAR}
  { The title bar's shade follows the sidebar's width. }
  if OwnBar <> nil then
    OwnBar.Invalidate;
  {$ENDIF}
end;

procedure TRepoFrame.RepoTreeSelectionChanged(Sender: TObject);
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
procedure TRepoFrame.SelectRepoNode(const APath: string);
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
procedure TRepoFrame.FillIgnoreMenus(const APath: string);
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
  i := StatIndexOf(APath);
  Untracked := (i >= 0) and (FStats[i].Kind = ckUntracked);
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
procedure TRepoFrame.MenuIgnoreClick(Sender: TObject);
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
  Git LFS in .gitattributes
  ---------------------------------------------------------------------------
  Track with Git LFS offers the file's patterns (LfsTrackPatterns: its
  extension, the file itself) that the root .gitattributes does not
  track yet, for a file in the work tree; Stop Tracking those of its
  patterns it tracks (LfsPatternsOf). They write the file as git lfs
  track and untrack do, without git-lfs; files already committed are
  left as they are, and move when they are committed next. The pattern
  is kept in the item's Hint, as for the ignore menus; the caption
  shows a [[:space:]] as the space it stands for. }
procedure TRepoFrame.FillLfsMenus(const APath: string);
var
  Attrs, Pattern: string;
  Tracked: TStringArray;

  procedure AddTo(AMenu: TMenuItem; const APattern: string; AClick: TNotifyEvent);
  var
    Item: TMenuItem;
  begin
    Item := TMenuItem.Create(AMenu);
    Item.Caption := StringReplace(StringReplace(APattern, '[[:space:]]', ' ', [rfReplaceAll]),
      '&', '&&', [rfReplaceAll]);
    Item.Hint := APattern;
    Item.OnClick := AClick;
    AMenu.Add(Item);
  end;

begin
  FLfsTrackMenu.Clear;
  FLfsUntrackMenu.Clear;
  Attrs := '';
  if (FRepo.Root <> '') and (APath <> '') then
    try
      if FileExists(IncludeTrailingPathDelimiter(FRepo.Root) + RepoRootFiles[1]) then
        Attrs := ReadFileBytes(IncludeTrailingPathDelimiter(FRepo.Root) + RepoRootFiles[1]);
    except
      Attrs := '';
    end;
  Tracked := LfsTrackedPatterns(Attrs);
  if (APath <> '') and FileExists(ContextFullPath) then
    for Pattern in LfsTrackPatterns(APath) do
      if AnsiIndexStr(Pattern, Tracked) < 0 then
        AddTo(FLfsTrackMenu, Pattern, @MenuLfsTrackClick);
  if APath <> '' then
    for Pattern in LfsPatternsOf(Attrs, APath) do
      AddTo(FLfsUntrackMenu, Pattern, @MenuLfsUntrackClick);
  FLfsTrackMenu.Enabled := FLfsTrackMenu.Count > 0;
  FLfsUntrackMenu.Enabled := FLfsUntrackMenu.Count > 0;
end;

{ The banner reads the state again: the repository may have files in
  Git LFS now, or none. }
procedure TRepoFrame.MenuLfsTrackClick(Sender: TObject);
var
  Item: TMenuItem;
begin
  Item := Sender as TMenuItem;
  if FRepo.Root = '' then
    Exit;
  if AddLfsTrack(IncludeTrailingPathDelimiter(FRepo.Root) + RepoRootFiles[1], Item.Hint) then
  begin
    StatusNote(Format(rsLfsTracked, [Item.Hint]));
    FLfsChecked := '';
    RefreshRepository;
  end
  else
    StatusNote(Format(rsIgnoreFailed, [RepoRootFiles[1]]), True);
end;

procedure TRepoFrame.MenuLfsUntrackClick(Sender: TObject);
var
  Item: TMenuItem;
begin
  Item := Sender as TMenuItem;
  if FRepo.Root = '' then
    Exit;
  if RemoveLfsTrack(IncludeTrailingPathDelimiter(FRepo.Root) + RepoRootFiles[1], Item.Hint) then
  begin
    StatusNote(Format(rsLfsUntracked, [Item.Hint]));
    FLfsChecked := '';
    RefreshRepository;
  end
  else
    StatusNote(Format(rsIgnoreFailed, [RepoRootFiles[1]]), True);
end;

{ ---------------------------------------------------------------------------
  Editing the repository's files
  ---------------------------------------------------------------------------
  The editor is a viewer, except for the files the Config section
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
function TRepoFrame.RepoFileName(const AFileName: string): boolean;
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
procedure TRepoFrame.BeginEdit(const AFileName: string);
begin
  FEditPath := AFileName;
  FEditStamp := FileAge(AFileName);
  Edit.ModeReadOnly := False;
  FHeader.SetActions([rsRevertAction, rsSaveAction]);
  UpdateEditState;
end;

{ Offers to save unsaved changes before the editor's text is replaced.
  Declining drops them; there is no way to stay, since the caller is
  already on its way elsewhere, so Escape and the close box do nothing
  rather than drop them unasked. }
procedure TRepoFrame.FlushEdit;
begin
  if (FEditPath = '') or not Edit.Modified then
    Exit;
  HoldRefresh;
  try
    if AskDlg(rsAppName, Format(rsSaveAsk, [ExtractFileName(FEditPath)]),
      mtConfirmation, [mrYes, rsSaveAction, 'IsDefault', mrNo, rsDontSave,
      'NoCancel'], 0) = mrYes then
      SaveEdit(False)
    else
      Edit.Modified := False;
  finally
    ReleaseRefresh;
  end;
end;

{ Ends the edit: the editor is read-only again. The pills go with the
  next title the header gets. }
procedure TRepoFrame.LeaveEdit;
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
procedure TRepoFrame.UpdateEditState;
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
function TRepoFrame.SaveEdit(ARefresh: boolean): boolean;
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
  { A .gitattributes may make files lockable or put them in Git LFS,
    which the check reads again, as after Track with Git LFS. }
  if SameText(Shown, RepoRootFiles[1]) then
    FLfsChecked := '';
  StatusNote(Format(rsSaved, [Shown]));
  Result := True;
  if ARefresh then
    RefreshRepository;
end;

{ Drops the changes and loads the file from disk again, at the same
  place, after asking: the undo history goes with them. }
procedure TRepoFrame.RevertEdit;
var
  TopLine: integer;
begin
  if (FEditPath = '') or not Edit.Modified then
    Exit;
  if AskDlg(rsAppName, Format(rsRevertAsk, [ExtractFileName(FEditPath)]),
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
procedure TRepoFrame.HeaderAction(Sender: TObject; AIndex: integer);
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
  { Open and Save As... on a file of the Files page (umain.files.inc). }
  if FView = gvBlob then
  begin
    if AIndex = 0 then
      OpenBlobOutside
    else if AIndex = 1 then
      SaveBlobAs
    else
      BlobLockAction;
    Exit;
  end;
  if FView = gvMerge then
  begin
    MergeHeaderAction(AIndex);
    Exit;
  end;
  if ConflictHeaderAction(AIndex) then
    Exit;
  { Download, the one pill of an image or binary file in Git LFS. }
  if (FView in [gvImage, gvBinary]) and (FLfsSides <> nil) then
  begin
    StartLfsDownload(FCurrentPath, FLfsSides);
    Exit;
  end;
  if FView = gvSubmodule then
  begin
    if AIndex = FSubUpdatePill then
      UpdateSubmodulesAsk(FSubShown)
    else
      OpenShownSubmodule;
    Exit;
  end;
  if (FView <> gvChanges) or (FCurrentPath = '') or (FRepo.Root = '') then
    Exit;
  { Unkeep shows the file's kept changes again (see umain.discard.inc). }
  if (FHeaderUnkeep >= 0) and (AIndex = FHeaderUnkeep) then
  begin
    UnkeepFile;
    Exit;
  end;
  { Include All takes the file's changes left out back into the commit
    (see umain.leaveout.inc). }
  if (FHeaderInclude >= 0) and (AIndex = FHeaderInclude) then
  begin
    IncludeFile;
    Exit;
  end;
  Path := FCurrentPath;
  FileTree.Selected := nil;
  OpenFile(IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(Path));
  SelectRepoNode(Path);
end;

procedure TRepoFrame.EditChangeModified(Sender: TObject);
begin
  UpdateEditState;
end;

procedure TRepoFrame.MenuSaveClick(Sender: TObject);
begin
  if FEditPath <> '' then
    SaveEdit(True);
end;

{ Unsaved changes hold the window open until they are saved or dropped,
  the merge editor's ticks and edits too. }
procedure TRepoFrame.FormCloseQuery(Sender: TObject; var CanClose: boolean);
begin
  CanClose := True;
  if (FEditPath <> '') and Edit.Modified then
    case AskDlg(rsAppName, Format(rsSaveAsk, [ExtractFileName(FEditPath)]),
        mtConfirmation, [mrYes, rsSaveAction, 'IsDefault', mrNo, rsDontSave,
        mrCancel, rsCancelButton, 'IsCancel'], 0) of
      mrYes: CanClose := SaveEdit(False);
      mrNo: Edit.Modified := False;
      else
        CanClose := False;
    end;
  if CanClose then
    CanClose := FlushMerge(True);
end;
