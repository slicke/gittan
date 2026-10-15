{ ---------------------------------------------------------------------------
  The Repository section
  ---------------------------------------------------------------------------
  Under the tree of changed files sits a section with the repository's
  own files (gittan.repofiles): .gitignore and its kin at the root and
  everything under .github, changed or not, so they are at hand when a
  file shows up that should not. It is a header that folds, remembered
  in the settings, over a second tree like the first, in a panel at the
  bottom of the tree panel; the panel is as high as the rows, up to half
  the panel, and hidden while there is nothing to list. A click shows the
  file through ShowRepoFile, so a changed one is selected in the tree
  above with its diff, and only one of the trees keeps a selection. }
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
end;

{ Fills the section's tree from ListRepoFiles: the root files in their
  fixed order, then .github as a folder, every folder open. }
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

{ The panel is the header alone while folded, else the header and the
  rows in view, within half the tree panel. }
procedure TForm1.LayoutRepoFiles;
var
  Rows, RowHeight, H: integer;
  Node: TTreeNode;
begin
  H := FRepoHeader.Height;
  FRepoTree.Visible := FRepoHeader.Expanded;
  if FRepoHeader.Expanded then
  begin
    Rows := 0;
    Node := FRepoTree.Items.GetFirstVisibleNode;
    while Node <> nil do
    begin
      Inc(Rows);
      Node := Node.GetNextVisible;
    end;
    RowHeight := FRepoTree.DefaultItemHeight;
    if RowHeight < 8 then
      RowHeight := 20;
    H := H + Min(Rows * RowHeight + 4, FTreePanel.ClientHeight div 2);
  end;
  FRepoPanel.Height := H;
end;

procedure TForm1.RepoHeaderToggle(Sender: TObject);
begin
  LayoutRepoFiles;
end;

procedure TForm1.TreePanelResize(Sender: TObject);
begin
  LayoutRepoFiles;
end;

procedure TForm1.RepoTreeSelectionChanged(Sender: TObject);
var
  Node: TTreeNode;
begin
  Node := FRepoTree.Selected;
  if (Node = nil) or (Node.Data = nil) or (FRepo.Root = '') then
    Exit;
  ShowRepoFile(Node.GetTextPath);
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
    FileName := FRepo.GitDir;
    if FileName = '' then
    begin
      StatusNote(FRepo.Error, True);
      Exit;
    end;
    FileName := IncludeTrailingPathDelimiter(FileName) + SetDirSeparators(ExcludeFile);
    Shown := '.git/' + ExcludeFile;
  end
  else
  begin
    Shown := RepoRootFiles[0];
    FileName := IncludeTrailingPathDelimiter(FRepo.Root) + Shown;
  end;
  if AddIgnorePattern(FileName, Item.Hint) then
  begin
    StatusNote(Format(rsIgnoreAdded, [Item.Hint, Shown]));
    RefreshRepository;
  end
  else
    StatusNote(Format(rsIgnoreFailed, [Shown]), True);
end;
