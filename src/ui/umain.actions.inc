{ ---------------------------------------------------------------------------
  Settings
  ---------------------------------------------------------------------------
  Included by umain.pp. The settings are read in FormCreate and applied
  here before the menu is built, so its check marks match; they are
  written when the window closes. }

{ A path with the home folder shortened to "~", for menus. }
function ShortPath(const APath: string): string;
var
  Home: string;
begin
  Result := APath;
  Home := ExcludeTrailingPathDelimiter(GetUserDir);
  if (Home <> '') and (Copy(APath, 1, Length(Home)) = Home) then
    Result := '~' + Copy(APath, Length(Home) + 1, MaxInt);
end;

{ Starts AExe with AArgs, in ADir when given, and does not wait for it. }
procedure RunDetached(const AExe: string; const AArgs: array of string;
  const ADir: string = '');
var
  P: TProcess;
  S: string;
begin
  P := TProcess.Create(nil);
  try
    P.Executable := AExe;
    P.CurrentDirectory := ADir;
    for S in AArgs do
      P.Parameters.Add(S);
    P.Options := [poNoConsole];
    try
      P.Execute;
    except
      { The command is missing; nothing else to do. }
    end;
  finally
    P.Free;
  end;
end;

procedure TForm1.ApplySettings;
var
  R: TRect;
  i: integer;
begin
  FOnlyChanges := FSettings.OnlyChanges;
  FSideBySide := FSettings.SideBySide;
  FMdPreviewOn := FSettings.MarkdownPreview;
  FWordWrap := FSettings.WordWrap;
  FIgnoreWhitespace := FSettings.IgnoreWhitespace;
  FBlameOn := FSettings.Blame;
  FShowComments := FSettings.ReviewComments;
  FTranslations := FSettings.Translations;
  FSyntaxTheme := FindSyntaxTheme(FSettings.SyntaxTheme);
  if FSyntaxTheme < 0 then
    FSyntaxTheme := DefaultSyntaxTheme;
  if FSyntaxTheme <> DefaultSyntaxTheme then
    FLexers.ApplyTheme(FDark, FSyntaxTheme);
  FRepo.IgnoreWhitespace := FIgnoreWhitespace;
  FContextLines := ContextChoices[1];
  for i := 0 to High(ContextChoices) do
    if ContextChoices[i] = FSettings.ContextLines then
      FContextLines := ContextChoices[i];
  { The window where it was, if that is still on a screen. The sizes are
    kept at 96 DPI: this runs in FormCreate, and the form scales its size
    and the tree's width to the screen's after it, its place not. }
  if (FSettings.Width > 0) and (FSettings.Height > 0) then
  begin
    R := Rect(FSettings.Left, FSettings.Top, FSettings.Left + FSettings.Width,
      FSettings.Top + FSettings.Height);
    if IntersectRect(R, R, Screen.DesktopRect) and (R.Width > 100) and
      (R.Height > 100) then
      SetBounds(FSettings.Left, FSettings.Top, FSettings.Width, FSettings.Height);
  end;
  if FSettings.Maximized then
    WindowState := wsMaximized;
  { The editor font as picked, else the platform's, its size from the
    height of the screen the window is on. }
  FDefaultFontSize := DefaultFontSize(MulDiv(Screen.MonitorFromRect(BoundsRect)
    .BoundsRect.Height, 96, Screen.PixelsPerInch));
  if FSettings.FontName <> '' then
    Edit.Font.Name := FSettings.FontName
  else
    Edit.Font.Name := DefaultFontName;
  if FSettings.FontSize > 0 then
    Edit.Font.Size := FSettings.FontSize
  else
    Edit.Font.Size := FDefaultFontSize;
  FEditOld.Font.Assign(Edit.Font);
  if FSettings.Zoom > 0 then
  begin
    Edit.OptScaleFont := FSettings.Zoom;
    FEditOld.OptScaleFont := FSettings.Zoom;
  end;
  if FSettings.TreeWidth > 80 then
    FTreePanel.Width := FSettings.TreeWidth;
  FSideNav.Collapsed := not FSettings.NavOpen;
  FRepoHeader.Expanded := FSettings.RepoFilesOpen;
  FSubHeader.Expanded := FSettings.SubmodulesOpen;
  FCommitHeader.Expanded := FSettings.CommitOpen;
  FCommitBox.Visible := FCommitHeader.Expanded;
  LayoutRepoFiles;
end;

procedure TForm1.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  FSettings.Maximized := WindowState = wsMaximized;
  if FSettings.Maximized then
  begin
    FSettings.Left := RestoredLeft;
    FSettings.Top := RestoredTop;
    FSettings.Width := RestoredWidth;
    FSettings.Height := RestoredHeight;
  end
  else
  begin
    FSettings.Left := Left;
    FSettings.Top := Top;
    FSettings.Width := Width;
    FSettings.Height := Height;
  end;
  FSettings.Width := MulDiv(FSettings.Width, 96, Screen.PixelsPerInch);
  FSettings.Height := MulDiv(FSettings.Height, 96, Screen.PixelsPerInch);
  FSettings.TreeWidth := MulDiv(FTreePanel.Width, 96, Screen.PixelsPerInch);
  FSettings.NavOpen := not FSideNav.Collapsed;
  FSettings.RepoFilesOpen := FRepoHeader.Expanded;
  FSettings.SubmodulesOpen := FSubHeader.Expanded;
  FSettings.CommitOpen := FCommitHeader.Expanded;
  StopCommitJob(True);
  StopRemoteJob(True);
  AbandonCommandJob(True);
  SaveCommitDraft;
  { The defaults are not written, so they follow the screen and a later
    Gittan's choice. }
  FSettings.FontName := Edit.Font.Name;
  if SameText(FSettings.FontName, DefaultFontName) then
    FSettings.FontName := '';
  FSettings.FontSize := Edit.Font.Size;
  if FSettings.FontSize = FDefaultFontSize then
    FSettings.FontSize := 0;
  FSettings.Zoom := Edit.OptScaleFont;
  FSettings.TabSize := FTabSize;
  if FTabSize = DefaultTabSize then
    FSettings.TabSize := 0;
  FSettings.WordWrap := FWordWrap;
  FSettings.OnlyChanges := FOnlyChanges;
  FSettings.ContextLines := FContextLines;
  FSettings.SideBySide := FSideBySide;
  FSettings.MarkdownPreview := FMdPreviewOn;
  FSettings.IgnoreWhitespace := FIgnoreWhitespace;
  FSettings.Blame := FBlameOn;
  FSettings.ReviewComments := FShowComments;
  FSettings.Translations := FTranslations;
  FSettings.SyntaxTheme := SyntaxThemes[FSyntaxTheme].Name;
  FSettings.Save;
  SaveIndex;
end;

{ ---------------------------------------------------------------------------
  Recent repositories
  --------------------------------------------------------------------------- }
procedure TForm1.RebuildRecentMenu;
var
  Item: TMenuItem;
  i: integer;
begin
  FRecentMenu.Clear;
  for i := 0 to FSettings.Recent.Count - 1 do
  begin
    Item := TMenuItem.Create(FRecentMenu);
    Item.Caption := ShortPath(FSettings.Recent[i]);
    Item.Hint := FSettings.Recent[i];
    Item.OnClick := @MenuRecentClick;
    FRecentMenu.Add(Item);
  end;
  if FSettings.Recent.Count > 0 then
    FRecentMenu.Add(NewLine);
  Item := TMenuItem.Create(FRecentMenu);
  Item.Caption := rsClearMenu;
  Item.Enabled := FSettings.Recent.Count > 0;
  Item.OnClick := @MenuClearRecentClick;
  FRecentMenu.Add(Item);
  FWelcome.SetRecent(FSettings.Recent);
end;

procedure TForm1.MenuRecentClick(Sender: TObject);
begin
  OpenRepository(TMenuItem(Sender).Hint);
end;

procedure TForm1.MenuClearRecentClick(Sender: TObject);
begin
  FSettings.Recent.Clear;
  RebuildRecentMenu;
end;

{ ---------------------------------------------------------------------------
  Find
  ---------------------------------------------------------------------------
  The bar searches the editor's text, case-insensitively, by plain
  substring. The matches are listed afresh on every search, which is
  quick enough for the files a diff shows; the one to show is the first
  after (or before) the caret, or the selection start while a match is
  selected, so retyping extends the current match in place. }
procedure TForm1.MenuFindClick(Sender: TObject);
begin
  if not Edit.Visible then
    Exit;
  FFindBar.Activate;
end;

procedure TForm1.MenuFindNextClick(Sender: TObject);
begin
  if FFindBar.SearchText = '' then
    MenuFindClick(Sender)
  else
    FindText(FFindBar.SearchText, True, False);
end;

procedure TForm1.MenuFindPrevClick(Sender: TObject);
begin
  if FFindBar.SearchText = '' then
    MenuFindClick(Sender)
  else
    FindText(FFindBar.SearchText, False, False);
end;

procedure TForm1.FindBarSearch(Sender: TObject; const AText: string;
  ANext, AFromStart: boolean);
begin
  FindText(AText, ANext, AFromStart);
end;

procedure TForm1.FindBarClose(Sender: TObject);
begin
  FFindBar.Visible := False;
  if Edit.Visible and Edit.CanFocus then
    Edit.SetFocus;
end;

procedure TForm1.FindText(const AText: string; ANext, AFromStart: boolean);
type
  { A match: X and Y in the editor, Old when it is in the old side's
    text. The two sides of Side by Side have the same rows, so the
    matches are ordered by row, the old side first, then by column. }
  TMatch = record
    X, Y: integer;
    Old: boolean;
  end;
var
  Needle: UnicodeString;
  Matches: array of TMatch;
  Count, i, Idx: integer;
  Start: TMatch;
  Ed: TATSynEdit;
  Caret: TATCaretItem;

  function Compare(const A, B: TMatch): integer;
  begin
    Result := A.Y - B.Y;
    if Result = 0 then
      Result := Ord(B.Old) - Ord(A.Old);
    if Result = 0 then
      Result := A.X - B.X;
  end;

  procedure Search(AEd: TATSynEdit; ARow: integer; AOld: boolean);
  var
    S: UnicodeString;
    p: integer;
  begin
    S := UnicodeLowerCase(AEd.Strings.Lines[ARow]);
    p := Pos(Needle, S);
    while (p > 0) and (Count < MaxMatches) do
    begin
      if Count = Length(Matches) then
        SetLength(Matches, Count * 2);
      Matches[Count].X := p - 1;
      Matches[Count].Y := ARow;
      Matches[Count].Old := AOld;
      Inc(Count);
      p := Pos(Needle, S, p + 1);
    end;
  end;

  { The deleted lines of Side by Side are only in the old side's text;
    its other lines are the new side's too and are found there. }
  function DeletedRow(ARow: integer): boolean;
  begin
    Result := FEditOld.Visible and (ARow <= High(FRowsOld)) and
      (ARow < FEditOld.Strings.Count) and (FRowsOld[ARow].Line >= 0) and
      (FChangeLines[FRowsOld[ARow].Line][1] = '-');
  end;

begin
  if not Edit.Visible then
    Exit;
  Needle := UnicodeLowerCase(UTF8Decode(AText));
  if Needle = '' then
  begin
    FFindBar.SetMatches(0, 0);
    Exit;
  end;
  Count := 0;
  SetLength(Matches, 64);
  for i := 0 to Edit.Strings.Count - 1 do
  begin
    if DeletedRow(i) then
      Search(FEditOld, i, True);
    { A hidden line of the change view cannot be shown; a folded one is
      unfolded when the match is in it. }
    if FoldingShown or not Edit.IsLineFolded(i) then
      Search(Edit, i, False);
    if Count >= MaxMatches then
      Break;
  end;
  if Count = 0 then
  begin
    FFindBar.SetMatches(0, 0);
    Exit;
  end;
  { The search goes on from the side the user is in, or else the side of
    the last match. }
  if FEditOld.Visible and (FEditOld.Focused or (FFindInOld and not Edit.Focused)) then
    Ed := FEditOld
  else
    Ed := Edit;
  Caret := Ed.Carets[0];
  Start.X := Caret.PosX;
  Start.Y := Caret.PosY;
  Start.Old := Ed = FEditOld;
  if (Caret.EndY >= 0) and ((Caret.EndY < Start.Y) or
    ((Caret.EndY = Start.Y) and (Caret.EndX < Start.X))) then
  begin
    Start.X := Caret.EndX;
    Start.Y := Caret.EndY;
  end;
  { A caret, not a selection, at the start of a new side's row has not
    passed the old side's line beside it, where the view puts it on a
    new file. }
  if FEditOld.Visible and not Start.Old and (Start.X = 0) and (Caret.EndY < 0) then
  begin
    Start.Old := True;
    Start.X := -1;
  end;
  Idx := -1;
  if ANext then
  begin
    for i := 0 to Count - 1 do
      if (Compare(Matches[i], Start) > 0) or
        (AFromStart and (Compare(Matches[i], Start) = 0)) then
      begin
        Idx := i;
        Break;
      end;
    if Idx < 0 then
      Idx := 0;
  end
  else
  begin
    for i := Count - 1 downto 0 do
      if Compare(Matches[i], Start) < 0 then
      begin
        Idx := i;
        Break;
      end;
    if Idx < 0 then
      Idx := Count - 1;
  end;
  FFindInOld := Matches[Idx].Old;
  if FFindInOld then
    Ed := FEditOld
  else
    Ed := Edit;
  { The caret lands after the match, the selection covers it. }
  Ed.DoGotoPos(Point(Matches[Idx].X + Length(Needle), Matches[Idx].Y),
    Point(Matches[Idx].X, Matches[Idx].Y), 10, 5, True, FoldAction);
  { The old side follows the new one (SyncOldSide), so a match in the
    old side scrolls the new side there first. }
  if FFindInOld then
  begin
    Edit.LineTop := FEditOld.LineTop;
    Edit.ColumnLeft := FEditOld.ColumnLeft;
    Edit.Update;
  end;
  SyncOldSide;
  FFindBar.SetMatches(Idx + 1, Count);
end;

{ ---------------------------------------------------------------------------
  View options
  --------------------------------------------------------------------------- }
{ DoScaleFontDelta fires no OnChangeZoom (only the wheel and the
  editor's own keys do), so the menu's zoom calls the handler itself. }
procedure TForm1.MenuZoomInClick(Sender: TObject);
begin
  Edit.DoScaleFontDelta(True, True);
  EditChangeZoom(Edit);
end;

procedure TForm1.MenuZoomOutClick(Sender: TObject);
begin
  Edit.DoScaleFontDelta(False, True);
  EditChangeZoom(Edit);
end;

procedure TForm1.MenuZoomResetClick(Sender: TObject);
begin
  Edit.OptScaleFont := 0;
  FEditOld.OptScaleFont := 0;
  EditorMetricsChanged;
end;

procedure TForm1.MenuFontClick(Sender: TObject);
var
  Dlg: TFontDialog;
begin
  Dlg := TFontDialog.Create(nil);
  try
    Dlg.Font.Assign(Edit.Font);
    if Dlg.Execute then
      ApplyEditorFont(Dlg.Font);
  finally
    Dlg.Free;
  end;
end;

procedure TForm1.ApplyEditorFont(AFont: TFont);
begin
  Edit.Font.Assign(AFont);
  FEditOld.Font.Assign(AFont);
  if FCommandPage <> nil then
    FCommandPage.Console.Font.Assign(AFont);
  Edit.Update(True);
  FEditOld.Update(True);
  EditorMetricsChanged;
end;

{ A git older than MinGitMajor.MinGitMinor is said in the banner, at
  start and when the settings name another git. One that cannot be run,
  or names no version, is left to the errors of the git calls. }
procedure TForm1.CheckGitVersion;
var
  Version: string;
  Major, Minor: integer;
begin
  if GitVersion(Version, Major, Minor) and not GitVersionSupported(Major, Minor) then
    BannerError(Format(rsGitTooOld, [Version, MinGitMajor, MinGitMinor]),
      Format(rsGitTooOldDetail, [MinGitMajor, MinGitMinor, GitExe]));
end;

{ The settings dialog previews the font, the theme and the tab width in
  the editor and puts back the old ones when it is cancelled; the commands
  are saved with the rest when the window closes. A new git or gh runs
  from here on: the repository is read again with it, and the GitHub
  features follow whether gh is there now. }
procedure TForm1.MenuSettingsClick(Sender: TObject);
const
  Margin = 24;
var
  OldFont, F: TFont;
  OldTheme, OldTabSize: integer;
  V: TSettingsValues;
  Corner: TPoint;
begin
  OldFont := TFont.Create;
  F := TFont.Create;
  try
    OldFont.Assign(Edit.Font);
    F.Assign(Edit.Font);
    OldTheme := FSyntaxTheme;
    OldTabSize := FTabSize;
    V.Theme := FSyntaxTheme;
    V.TabSize := FTabSize;
    V.EditorCommand := FSettings.EditorCommand;
    V.TerminalCommand := FSettings.TerminalCommand;
    V.GitPath := FSettings.GitPath;
    V.GhPath := FSettings.GhPath;
    Corner := EditorPanel.ClientToScreen(Point(EditorPanel.ClientWidth -
      Scale96ToForm(Margin), EditorPanel.ClientHeight - Scale96ToForm(Margin)));
    if EditSettings(F, V, @PreviewSettings, FLexers, Edit, Corner) then
    begin
      PreviewSettings(F, V.Theme, V.TabSize);
      FSettings.EditorCommand := V.EditorCommand;
      FSettings.TerminalCommand := V.TerminalCommand;
      if (V.GitPath <> FSettings.GitPath) or (V.GhPath <> FSettings.GhPath) then
      begin
        FSettings.GitPath := V.GitPath;
        FSettings.GhPath := V.GhPath;
        SetGitExe(FSettings.GitPath);
        FindGitHubCli;
        UpdateGitHubItems;
        if not FHasGitHubCli then
        begin
          { What the gh that is gone had found. }
          AbandonPullJob;
          FPullKey := '';
          FHasPull := False;
          FPulls := nil;
          FPullError := '';
          ClearReviews;
        end;
        MenuRefreshClick(nil);
        CheckGitVersion;
      end;
    end
    else
      PreviewSettings(OldFont, OldTheme, OldTabSize);
  finally
    F.Free;
    OldFont.Free;
  end;
end;

procedure TForm1.PreviewSettings(AFont: TFont; ATheme, ATabSize: integer);
begin
  if not Edit.Font.IsEqual(AFont) then
    ApplyEditorFont(AFont);
  if ATheme <> FSyntaxTheme then
    SetSyntaxTheme(ATheme);
  ApplyTabSize(ATabSize);
end;

{ A tab ASize characters wide in both editors; the wrap follows, since
  the width of a line changes with it. }
procedure TForm1.ApplyTabSize(ASize: integer);
begin
  if ASize = FTabSize then
    Exit;
  FTabSize := ASize;
  Edit.OptTabSize := ASize;
  FEditOld.OptTabSize := ASize;
  Edit.Update(True);
  FEditOld.Update(True);
end;

{ gh by the path the settings give, else as found on ToolSearchPath. }
procedure TForm1.FindGitHubCli;
begin
  if FSettings.GhPath <> '' then
    FGitHubCli := FSettings.GhPath
  else
    FGitHubCli := FindTool('gh');
  FHasGitHubCli := FGitHubCli <> '';
end;

{ Shows the menu items that need gh when there is one, hides them
  otherwise. The Compare With menu and a commit's menu are built when
  they open and look at the flag themselves. }
procedure TForm1.UpdateGitHubItems;
var
  Item: TMenuItem;
begin
  for Item in FGitHubItems do
    Item.Visible := FHasGitHubCli;
  if FReviewItem <> nil then
    FReviewItem.Enabled := FHasGitHubCli;
  { The Pull Requests page needs gh too: its row, its menu item, and
    the page itself when gh goes while it shows. }
  if FPullsItem <> nil then
    FPullsItem.Visible := FHasGitHubCli;
  if FSideNav <> nil then
    FSideNav.SetRowVisible(navPulls, FHasGitHubCli);
  if not FHasGitHubCli and (FView = gvPulls) then
    ShowSummary;
end;

procedure TForm1.MenuWrapClick(Sender: TObject);
begin
  FWordWrap := not FWordWrap;
  FWrapItem.Checked := FWordWrap;
  ApplyWrap;
end;

{ View > Folding: the command in the item's Tag, on the ranges of the
  lexer where FoldingShown. The shortcuts reach here in the other views
  too. }
procedure TForm1.MenuFoldClick(Sender: TObject);
begin
  if not FoldingShown or not Edit.Visible then
    Exit;
  Edit.DoCommand(TMenuItem(Sender).Tag, TATCommandInvoke.MenuMain);
  Edit.Update;
end;

{ AShortCut as the menus show it: the macOS symbols (⌃⌥⇧⌘ before the
  key) on macOS, ShortCutToText elsewhere; '' for none. }
function ShortcutLabel(AShortCut: TShortCut): string;
{$IFDEF DARWIN}
var
  Key: word;
  Shift: TShiftState;
{$ENDIF}
begin
  if AShortCut = 0 then
    Exit('');
  {$IFDEF DARWIN}
  ShortCutToKey(AShortCut, Key, Shift);
  Result := '';
  if ssCtrl in Shift then
    Result := Result + '⌃';
  if ssAlt in Shift then
    Result := Result + '⌥';
  if ssShift in Shift then
    Result := Result + '⇧';
  if ssMeta in Shift then
    Result := Result + '⌘';
  Result := Result + ShortCutToText(ShortCut(Key, []));
  {$ELSE}
  Result := ShortCutToText(AShortCut);
  {$ENDIF}
end;

{ The file header's View chip drops the view's modes, checked as in the
  View menu, and the file's histories from the Go menu, each with its
  shortcut, so the chip also teaches them; only the items the menus
  enable now. A pick clicks the menu item. }
procedure TForm1.HeaderMenu(Sender: TObject; const AScreenRect: TRect);
var
  n: integer;

  procedure AddRow(AItem: TMenuItem);
  begin
    if (AItem = nil) or not AItem.Enabled or not AItem.Visible then
      Exit;
    SetLength(FViewItems, n + 1);
    SetLength(FViewRows, n + 1);
    FViewItems[n] := AItem;
    FViewRows[n] := FViewPopup.Add(StringReplace(AItem.Caption, '&', '', [rfReplaceAll]),
      ShortcutLabel(AItem.ShortCut), AItem.Checked);
    Inc(n);
  end;

begin
  ViewMenuClick(nil);
  FViewPopup.Clear;
  FViewItems := nil;
  FViewRows := nil;
  n := 0;
  FViewPopup.AddHeader(rsViewHeader);
  AddRow(FOnlyChangesItem);
  AddRow(FSideItem);
  AddRow(FWrapItem);
  AddRow(FIgnoreSpaceItem);
  AddRow(FBlameItem);
  AddRow(FTranslationsItem);
  AddRow(FReviewItem);
  FViewPopup.AddHeader(rsHistoryHeader);
  AddRow(FCodeHistoryItem);
  AddRow(FGoFileHistoryItem);
  FViewPopup.Popup(AScreenRect);
end;

procedure TForm1.ViewPopupPick(Sender: TObject; AIndex: integer);
var
  i: integer;
begin
  for i := 0 to High(FViewRows) do
    if FViewRows[i] = AIndex then
    begin
      FViewItems[i].Click;
      Exit;
    end;
end;

procedure TForm1.ViewMenuClick(Sender: TObject);
begin
  FFoldMenu.Enabled := FoldingShown and Edit.Visible;
end;

procedure TForm1.MenuOnlyChangesClick(Sender: TObject);
begin
  FOnlyChanges := not FOnlyChanges;
  FOnlyChangesItem.Checked := FOnlyChanges;
  FExpanded := nil;
  RebuildIfChanges;
end;

procedure TForm1.MenuContextLinesClick(Sender: TObject);
var
  i: integer;
begin
  FContextLines := TMenuItem(Sender).Tag;
  for i := 0 to High(FContextItems) do
    FContextItems[i].Checked := FContextItems[i].Tag = FContextLines;
  if FOnlyChanges then
    RebuildIfChanges;
end;

{ The lexer formats carry the colors, so the editors only need a repaint,
  which ApplyTheme does with the rest of the palette. }
procedure TForm1.MenuSyntaxThemeClick(Sender: TObject);
begin
  SetSyntaxTheme(TMenuItem(Sender).Tag);
end;

procedure TForm1.SetSyntaxTheme(ATheme: integer);
var
  i: integer;
begin
  FSyntaxTheme := ATheme;
  for i := 0 to High(FThemeItems) do
    FThemeItems[i].Checked := i = FSyntaxTheme;
  ApplyTheme;
end;

procedure TForm1.MenuSideBySideClick(Sender: TObject);
begin
  FSideBySide := not FSideBySide;
  FSideItem.Checked := FSideBySide;
  RebuildIfChanges;
  ApplyLayout;
end;

{ Whitespace changes are left out by git itself (-w on every diff), so
  the counts, the tree and the views all follow: the repository is
  loaded again and the view restored, as on a refresh. }
procedure TForm1.MenuIgnoreSpaceClick(Sender: TObject);
begin
  FIgnoreWhitespace := not FIgnoreWhitespace;
  FIgnoreSpaceItem.Checked := FIgnoreWhitespace;
  FRepo.IgnoreWhitespace := FIgnoreWhitespace;
  FExpanded := nil;
  RefreshRepository;
end;

{ ---------------------------------------------------------------------------
  Stepping through the files
  --------------------------------------------------------------------------- }
{ The caret goes to the file's first change, as selecting the file in
  the tree does, or going back, to its last; a file without any, such as
  an image or a binary file, is left as it is. }
procedure TForm1.MenuNextFileClick(Sender: TObject);
begin
  StepFile(True);
end;

procedure TForm1.MenuPrevFileClick(Sender: TObject);
var
  Blocks: TIntegerDynArray;
begin
  if not StepFile(False) then
    Exit;
  Blocks := ChangeBlocks;
  if Length(Blocks) > 0 then
    ShowChangeAt(Blocks[High(Blocks)]);
end;

{ Selects the next (or previous) file in the tree, wrapping around, which
  shows its changes. Returns false when there is no other file. }
function TForm1.StepFile(ANext: boolean): boolean;
var
  Node: TTreeNode;
begin
  Node := NeighbourFile(ANext);
  Result := Node <> nil;
  if not Result then
    Exit;
  FileTree.Selected := Node;
  Node.MakeVisible;
end;

{ The file node after (or before) the selected one in the tree, wrapping
  around; nil when there is no other file. }
function TForm1.NeighbourFile(ANext: boolean): TTreeNode;
var
  Files: TList;
  Node: TTreeNode;
  Idx: integer;
begin
  Result := nil;
  if FRepo.Root = '' then
    Exit;
  Files := TList.Create;
  try
    Node := FileTree.Items.GetFirstNode;
    while Node <> nil do
    begin
      if Node.Data <> nil then
        Files.Add(Node);
      Node := Node.GetNext;
    end;
    if Files.Count = 0 then
      Exit;
    Idx := Files.IndexOf(FileTree.Selected);
    if ANext then
    begin
      Inc(Idx);
      if Idx >= Files.Count then
        Idx := 0;
    end
    else
    begin
      Dec(Idx);
      if Idx < 0 then
        Idx := Files.Count - 1;
    end;
    Node := TTreeNode(Files[Idx]);
    if Node <> FileTree.Selected then
      Result := Node;
  finally
    Files.Free;
  end;
end;

{ Scrolling on past the bottom of a file pulls in the next one, and past
  the top the previous one. The event fires before the editor scrolls, so
  a wheel step that is already at the edge counts toward the pull; one
  that scrolls, or goes the other way, starts over. FOverscroll is the
  delta pulled so far, positive downwards. A pill at the edge of the text
  comes in with the pull (see EditDrawEditor), and when the pull is
  complete the next file is shown from its top, or the previous one from
  its bottom. The gesture's momentum runs on after the jump, so the pull
  is disarmed until the wheel has paused, and the editor's own scrolling
  is off meanwhile (SetWheelScroll). }
procedure TForm1.EditMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
var
  Now: QWord;
  Down, AtEdge: boolean;
begin
  Now := GetTickCount64;
  if not FOverscrollArmed then
  begin
    FOverscrollArmed := Now - FOverscrollTick >= OverscrollPause;
    if FOverscrollArmed then
      SetWheelScroll(True);
  end;
  FOverscrollTick := Now;
  if not FOverscrollArmed or (FView <> gvChanges) or
    (Shift - [ssLeft] <> []) then
    Exit;
  Down := WheelDelta < 0;
  if Down then
    AtEdge := Edit.ScrollVert.SmoothPos >= Edit.ScrollVert.SmoothPosLast
  else
    AtEdge := Edit.ScrollVert.SmoothPos <= 0;
  if (WheelDelta = 0) or not AtEdge or (NeighbourFile(Down) = nil) then
  begin
    SetOverscroll(0);
    Exit;
  end;
  { A file that fits in the window is at both edges: a pull the other
    way starts over. }
  if (FOverscroll <> 0) and ((FOverscroll > 0) <> Down) then
    SetOverscroll(0);
  SetOverscroll(FOverscroll - WheelDelta);
  if Abs(FOverscroll) < OverscrollNeeded then
    Exit;
  FOverscrollArmed := False;
  SetWheelScroll(False);
  SetOverscroll(0);
  if StepFile(Down) and not Down then
    ShowFileEnd;
end;

{ The editor scrolls on every wheel event after this handler, whatever
  Handled says: the one that completes a pull would scroll the file just
  pulled in away from its edge, and so would the momentum after it, so
  the editors' wheel scrolling is off from the jump until the wheel has
  paused. }
procedure TForm1.SetWheelScroll(AOn: boolean);
begin
  Edit.OptMouseWheelScrollVert := AOn;
  FEditOld.OptMouseWheelScrollVert := AOn;
end;

procedure TForm1.SetOverscroll(AValue: integer);
begin
  if AValue = FOverscroll then
    Exit;
  FOverscroll := AValue;
  { Restarted on every change: the pull is forgotten after a quiet
    spell. }
  FOverscrollTimer.Enabled := False;
  FOverscrollTimer.Enabled := AValue <> 0;
  Edit.Invalidate;
end;

{ Shows the end of the file just pulled in: the caret on its last line
  and the last page in view, so scrolling on upwards reads the file
  backwards and Previous Change finds its last change. The scroll needs
  the wrap info of the text just loaded, which the first paint would
  build, and the line top the editor kept from the resize of showing the
  file would win at that paint. The editor keeps the line top within the
  last page, so the last line's puts that page in view. }
procedure TForm1.ShowFileEnd;
var
  Last: integer;
begin
  Last := Edit.Strings.Count - 1;
  { The editor's trailing empty line is no line of the file. }
  if Edit.Strings.IsLastLineFake then
    Dec(Last);
  if Last < 0 then
    Exit;
  Edit.UpdateWrapInfo(True);
  Edit.LineTopTodo := 0;
  Edit.DoCaretSingle(0, Last);
  Edit.LineTop := Last;
  Edit.Update;
  SyncOldSide;
  UpdateChangeNav;
end;

procedure TForm1.OverscrollTimerTimer(Sender: TObject);
begin
  SetOverscroll(0);
end;

{ The pill that shows the pull: it comes in from the edge of the text the
  pull is at, rising from the bottom for the next file or descending from
  the top for the previous, as the pull grows, and fills from the left,
  until the file is pulled in. The canvas is clipped to the text
  rectangle so the pill comes in from under its edge. }
procedure TForm1.EditDrawEditor(Sender: TObject; C: TCanvas; const ARect: TRect);
var
  Node: TTreeNode;
  Pill: string;
  W, H, Pad, Y: integer;
  Part: double;
  Down: boolean;
  R: TRect;
begin
  DrawGapGutter(TATSynEdit(Sender), C);
  DrawBlame(TATSynEdit(Sender), C);
  DrawInitials(TATSynEdit(Sender), C);
  DrawDiscard(TATSynEdit(Sender), C);
  if (Sender <> Edit) or (FOverscroll = 0) or (FView <> gvChanges) then
    Exit;
  Down := FOverscroll > 0;
  Node := NeighbourFile(Down);
  if Node = nil then
    Exit;
  if Down then
    Pill := Format(rsPullNext, [ExtractFileName(Node.GetTextPath)])
  else
    Pill := Format(rsPullPrev, [ExtractFileName(Node.GetTextPath)]);
  Part := Min(1.0, Abs(FOverscroll) / OverscrollNeeded);
  C.Font.Assign(FHeader.Font);
  C.Font.Color := FPullText;
  H := C.TextHeight(Pill) + 10;
  Pad := H div 2 + 4;
  W := C.TextWidth(Pill) + 2 * Pad;
  R := Rect(0, 0, W, H);
  if Down then
    Y := ARect.Bottom - Round(Part * (H + 12))
  else
    Y := ARect.Top - H + Round(Part * (H + 12));
  R.Offset((ARect.Left + ARect.Right - W) div 2, Y);
  C.Clipping := True;
  C.ClipRect := ARect;
  try
    C.Pen.Width := 1;
    C.Pen.Color := FPullBorder;
    C.Brush.Style := bsSolid;
    C.Brush.Color := FPullFill;
    C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, H, H);
    { The fill from the left: the same pill in the bar color, clipped to
      the part pulled so far. }
    C.ClipRect := Rect(R.Left, Max(R.Top, ARect.Top),
      R.Left + Round(Part * W), Min(R.Bottom, ARect.Bottom));
    C.Brush.Color := FPullBar;
    C.Pen.Color := FPullBar;
    C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, H, H);
    C.ClipRect := ARect;
    C.Pen.Color := FPullBorder;
    C.Brush.Style := bsClear;
    C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, H, H);
    C.TextOut(R.Left + Pad, R.Top + 5, Pill);
  finally
    C.Clipping := False;
  end;
end;

{ ---------------------------------------------------------------------------
  Context menus
  ---------------------------------------------------------------------------
  The file menu pops up over the tree (its right click selects the node),
  the summary's rows and the header; FContextPath names the file it is
  about. The status bar has a menu of its own. }
procedure TForm1.BuildPopups;
var
  Item: TMenuItem;

  function AddItem(APopup: TPopupMenu; const ACaption: string;
    AClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(APopup);
    Result.Caption := ACaption;
    Result.OnClick := AClick;
    APopup.Items.Add(Result);
  end;

  { An item (a separator with no caption) shown only when gh is there. }
  function AddGitHubItem(APopup: TPopupMenu; const ACaption: string;
    AClick: TNotifyEvent): TMenuItem;
  begin
    if ACaption = '' then
      Result := AddItem(APopup, '-', nil)
    else
      Result := AddItem(APopup, ACaption, AClick);
    SetLength(FGitHubItems, Length(FGitHubItems) + 1);
    FGitHubItems[High(FGitHubItems)] := Result;
  end;

begin
  FFilePopup := TPopupMenu.Create(Self);
  FFilePopup.OnPopup := @FilePopupPopup;
  AddItem(FFilePopup, rsCopyPath, @MenuCopyPathClick);
  AddItem(FFilePopup, rsCopyRelativePath, @MenuCopyRelativePathClick);
  Item := TMenuItem.Create(FFilePopup);
  Item.Caption := '-';
  FFilePopup.Items.Add(Item);
  FRevealItem := AddItem(FFilePopup, rsReveal, @MenuRevealClick);
  FOpenItem := AddItem(FFilePopup, rsOpenInEditor, @MenuOpenInEditorClick);
  FFileHistoryItem := AddItem(FFilePopup, rsFileHistoryItem, @MenuFileHistoryClick);
  AddGitHubItem(FFilePopup, rsOpenOnGitHub, @MenuOpenOnGitHubClick);
  AddGitHubItem(FFilePopup, rsCopyGitHubUrl, @MenuCopyGitHubUrlClick);
  Item := TMenuItem.Create(FFilePopup);
  Item.Caption := '-';
  FFilePopup.Items.Add(Item);
  FRevertItem := AddItem(FFilePopup, rsRevertChangesItem, @MenuRevertChangesClick);
  FMoveItem := AddItem(FFilePopup, rsMoveItem, @MenuMoveFileClick);
  FRemoveItem := AddItem(FFilePopup, rsRemoveItem, @MenuRemoveFileClick);
  FResolveMineItem := AddItem(FFilePopup, rsResolveMineItem, @MenuResolveMineClick);
  FResolveTheirsItem := AddItem(FFilePopup, rsResolveTheirsItem, @MenuResolveTheirsClick);
  FMarkResolvedItem := AddItem(FFilePopup, rsMarkResolvedItem, @MenuMarkResolvedClick);
  Item := TMenuItem.Create(FFilePopup);
  Item.Caption := '-';
  FFilePopup.Items.Add(Item);
  { Filled with the patterns for the file when the menu pops up. }
  FIgnoreMenu := AddItem(FFilePopup, rsAddToIgnore, nil);
  FExcludeMenu := AddItem(FFilePopup, rsAddToExclude, nil);
  { Over the tree while it chooses what to commit (FilePopupPopup). }
  FTickSepItem := TMenuItem.Create(FFilePopup);
  FTickSepItem.Caption := '-';
  FFilePopup.Items.Add(FTickSepItem);
  FTickAllItem := AddItem(FFilePopup, rsTickAllItem, @MenuTickAllClick);
  FUntickAllItem := AddItem(FFilePopup, rsUntickAllItem, @MenuUntickAllClick);
  FileTree.PopupMenu := FFilePopup;
  FRepoTree.PopupMenu := FFilePopup;
  FHeader.PopupMenu := FFilePopup;

  { The editors' menu replaces ATSynEdit's own, whose cut, paste, delete,
    undo and redo a read-only viewer never enables. }
  FEditPopup := TPopupMenu.Create(Self);
  FEditPopup.OnPopup := @EditPopupPopup;
  AddItem(FEditPopup, rsEditCopy, @MenuEditCopyClick);
  AddItem(FEditPopup, rsEditSelectAll, @MenuEditSelectAllClick);
  Item := TMenuItem.Create(FEditPopup);
  Item.Caption := '-';
  FEditPopup.Items.Add(Item);
  { Shown for a conflicted file only. }
  FResolveEditItem := AddItem(FEditPopup, rsResolveHere, @MenuResolveEditClick);
  FShowCommitItem := AddItem(FEditPopup, rsShowCommit, @MenuShowCommitClick);
  FCopyHashItem := AddItem(FEditPopup, rsCopyHash, @MenuCopyHashClick);
  AddGitHubItem(FEditPopup, '', nil);
  FGitHubEditItem := AddGitHubItem(FEditPopup, rsOpenOnGitHub, @MenuOpenLineOnGitHubClick);
  AddGitHubItem(FEditPopup, rsCopyGitHubUrl, @MenuCopyLineGitHubUrlClick);
  FGitHubCommitItem := AddGitHubItem(FEditPopup, rsOpenCommitOnGitHub,
    @MenuOpenCommitOnGitHubClick);
  { Shown for a commit whose summary names an issue (EditPopupPopup). }
  FGitHubIssueItem := AddItem(FEditPopup, Format(rsOpenIssueOnGitHub, [0]),
    @MenuOpenIssueOnGitHubClick);
  Edit.PopupText := FEditPopup;
  FEditOld.PopupText := FEditPopup;

  FStatusPopup := TPopupMenu.Create(Self);
  FStatusPopup.OnPopup := @StatusPopupPopup;
  AddItem(FStatusPopup, rsCopyBranch, @MenuCopyBranchClick);
  AddItem(FStatusPopup, rsCopyRepoPath, @MenuCopyRepoPathClick);
  Item := TMenuItem.Create(FStatusPopup);
  Item.Caption := '-';
  FStatusPopup.Items.Add(Item);
  AddItem(FStatusPopup, rsOpenTerminal, @MenuOpenTerminalClick);
  AddGitHubItem(FStatusPopup, '', nil);
  FOpenPullItem := AddGitHubItem(FStatusPopup, rsOpenPull, @MenuOpenPullClick);
  FCopyPullItem := AddGitHubItem(FStatusPopup, rsCopyPullUrl, @MenuCopyPullUrlClick);
  FStatus.PopupMenu := FStatusPopup;
  UpdateGitHubItems;
end;

procedure TForm1.FilePopupPopup(Sender: TObject);
var
  i: integer;
  Exists: boolean;
  Targets: TStringList;
begin
  if FContextFromSummary then
    FContextFromSummary := False
  else if FFilePopup.PopupComponent = FHeader then
    FContextPath := FCurrentPath
  else if FFilePopup.PopupComponent = FRepoTree then
  begin
    FContextPath := '';
    if (FRepoTree.Selected <> nil) and (FRepoTree.Selected.Data <> nil) then
      FContextPath := FRepoTree.Selected.GetTextPath;
  end
  else
    FContextPath := SelectedPath;
  { A folder of the tree: only Revert Changes acts on it. }
  FContextFolder := '';
  if (FFilePopup.PopupComponent = FileTree) and (FContextPath = '') and
    (FileTree.Selected <> nil) and (FileTree.Selected.Count > 0) then
    FContextFolder := FileTree.Selected.GetTextPath;
  Exists := (FContextPath <> '') and FileExists(ContextFullPath);
  for i := 0 to FFilePopup.Items.Count - 1 do
    FFilePopup.Items[i].Enabled := FContextPath <> '';
  FRevealItem.Enabled := Exists;
  FOpenItem.Enabled := Exists;
  FFileHistoryItem.Enabled := (FContextPath <> '') or (FContextFolder <> '');
  Targets := TStringList.Create;
  try
    RevertTargets(Targets);
    FRevertItem.Enabled := CanRevert and (Targets.Count > 0);
  finally
    Targets.Free;
  end;
  FRemoveItem.Enabled := CanMoveFiles;
  FMoveItem.Enabled := FRemoveItem.Enabled and Exists;
  FResolveMineItem.Enabled := IsConflictPath(FContextPath);
  FResolveTheirsItem.Enabled := FResolveMineItem.Enabled;
  FMarkResolvedItem.Enabled := FResolveMineItem.Enabled;
  FillIgnoreMenus(FContextPath);
  FTickSepItem.Visible := (FFilePopup.PopupComponent = FileTree) and CommitChoosing and
    (FChoosableCount > 0);
  FTickAllItem.Visible := FTickSepItem.Visible;
  FUntickAllItem.Visible := FTickSepItem.Visible;
  FTickAllItem.Enabled := (FChosenCount < FChoosableCount) and (FCommitJob = nil);
  FUntickAllItem.Enabled := (FChosenCount > 0) and (FCommitJob = nil);
end;

procedure TForm1.SummaryContextFile(Sender: TObject; const APath: string;
  const AScreenPos: TPoint);
begin
  FContextPath := APath;
  FContextFromSummary := True;
  FFilePopup.PopUp(AScreenPos.X, AScreenPos.Y);
end;

function TForm1.ContextFullPath: string;
begin
  Result := IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(FContextPath);
end;

{ ---------------------------------------------------------------------------
  Switching branch
  ---------------------------------------------------------------------------
  A click on the branch in the summary drops the branch list down from
  it: the local branches with the current one checked (one whose
  upstream is gone says "deleted on remote"), then the
  remote-tracking ones that have no local branch yet (shown with their
  remote, switched to by their name alone, which makes the local branch).
  Picking one runs git switch; what git refuses (a local change it would
  overwrite, an operation in progress) is told in the summary's notice.
  The list starts with its actions (umain.branches.inc); FBranchRefs
  holds, per row, the remote-tracking branch of a remote row, '' for
  the others. The Branch menu drops the same list for its other verbs
  (AMode, kept in FBranchListMode for the pick): then the header says
  what the pick does, the current branch and the actions are left out,
  and nothing is checked. }
procedure TForm1.SummaryBranchClick(Sender: TObject; const AScreenRect: TRect);
begin
  ShowBranchList(blSwitch, AScreenRect);
end;

procedure TForm1.ShowBranchList(AMode: TGittanBranchListMode; const AScreenRect: TRect);
var
  Local, Remote, Gone: TStringList;
  i, Slash: integer;
  Short, Detail: string;
  HasRemoteHeader: boolean;
begin
  if FRepo.Root = '' then
    Exit;
  FBranchListMode := AMode;
  HasRemoteHeader := False;
  Local := TStringList.Create;
  Remote := TStringList.Create;
  Gone := TStringList.Create;
  try
    if not FRepo.Branches(Local, Remote) then
    begin
      FSummary.Notice := FRepo.Error;
      Exit;
    end;
    FRepo.GoneBranches(Gone);
    { What the remotes said, which a stale remote-tracking ref hides
      from git. }
    for i := 0 to FGoneBranches.Count - 1 do
      if Gone.IndexOf(FGoneBranches[i]) < 0 then
        Gone.Add(FGoneBranches[i]);
    FBranchPopup.Clear;
    FBranchNames.Clear;
    FBranchRefs.Clear;
    FGoneToDelete.Clear;
    for i := 0 to Local.Count - 1 do
      if (Gone.IndexOf(Local[i]) >= 0) and (Local[i] <> FBranch) then
        FGoneToDelete.Add(Local[i]);
    if (AMode = blSwitch) and (FOperation = '') then
    begin
      FBranchPopup.Add(rsBmNew);
      FBranchNames.Add(BranchNew);
      FBranchRefs.Add('');
    end;
    if (AMode = blSwitch) and (FGoneToDelete.Count > 0) then
    begin
      FBranchPopup.Add(rsBmGone, IntToStr(FGoneToDelete.Count));
      FBranchNames.Add(BranchGone);
      FBranchRefs.Add('');
    end;
    case AMode of
      blMerge: FBranchPopup.AddHeader(Format(rsBmMergeHeader, [FBranch]));
      blRebase: FBranchPopup.AddHeader(Format(rsBmRebaseHeader, [FBranch]));
      blBranchSince: FBranchPopup.AddHeader(Format(rsBmCompareHeader, [FBranch]));
      blCurrentSince: FBranchPopup.AddHeader(Format(rsBmCompareBackHeader, [FBranch]));
      else
        FBranchPopup.AddHeader(rsBranches);
    end;
    FBranchNames.Add('');
    FBranchRefs.Add('');
    for i := 0 to Local.Count - 1 do
    begin
      if (AMode <> blSwitch) and (Local[i] = FBranch) then
        Continue;
      if Gone.IndexOf(Local[i]) >= 0 then
        Detail := rsBranchGone
      else
        Detail := '';
      FBranchPopup.Add(Local[i], Detail, (AMode = blSwitch) and (Local[i] = FBranch));
      FBranchNames.Add(Local[i]);
      FBranchRefs.Add('');
    end;
    for i := 0 to Remote.Count - 1 do
    begin
      Slash := Pos('/', Remote[i]);
      Short := Copy(Remote[i], Slash + 1, MaxInt);
      if (Slash = 0) or (Local.IndexOf(Short) >= 0) then
        Continue;
      if not HasRemoteHeader then
      begin
        FBranchPopup.AddHeader(rsRemoteBranches);
        FBranchNames.Add('');
        FBranchRefs.Add('');
        HasRemoteHeader := True;
      end;
      FBranchPopup.Add(Remote[i]);
      FBranchNames.Add(Short);
      FBranchRefs.Add(Remote[i]);
    end;
  finally
    Local.Free;
    Remote.Free;
    Gone.Free;
  end;
  FBranchPopup.Popup(AScreenRect);
end;

{ A remote row goes by its remote-tracking ref for anything but a
  switch, which makes the local branch from it. }
procedure TForm1.BranchPopupPick(Sender: TObject; AIndex: integer);
var
  Ref: string;
begin
  if (AIndex < 0) or (AIndex >= FBranchNames.Count) then
    Exit;
  if BranchAction(FBranchNames[AIndex]) then
    Exit;
  if (FBranchNames[AIndex] = '') or (FBranchNames[AIndex] = FBranch) then
    Exit;
  Ref := FBranchRefs[AIndex];
  if Ref = '' then
    Ref := FBranchNames[AIndex];
  case FBranchListMode of
    blMerge: MergeIntoCurrent(Ref);
    blRebase: RebaseOntoAsk(Ref);
    blBranchSince: CompareSince(Ref);
    blCurrentSince: CompareCurrentSince(Ref);
    else
      SwitchBranch(FBranchNames[AIndex]);
  end;
end;

{ The watcher is stopped meanwhile, as for a new base, and the views
  are refreshed from the new branch. When local changes block the
  switch, a dialog names the files git listed and offers to stash
  them and switch, or to bring them along merged
  into the branch's version (`git switch --merge`, which may leave
  conflicts); any other refusal is shown with git's whole message.
  With ADetach ABranch is a tag (or any commit) and HEAD is left on it
  without a branch. }
procedure TForm1.SwitchBranch(const ABranch: string; ADetach: boolean);
var
  Files: TStringList;
  Shown, Switch: string;
  i: integer;

  procedure Switched(const ANote: string);
  begin
    FLoadError := '';
    FSummary.Notice := '';
    RefreshRepository;
    StatusNote(ANote);
  end;

begin
  if FRepo.Root = '' then
    Exit;
  if ADetach then
    Switch := rsCheckedOutDetached
  else
    Switch := rsSwitched;
  StopWatcher;
  try
    Files := TStringList.Create;
    try
      if FRepo.Switch(ABranch, False, ADetach) then
        Switched(Format(Switch, [ABranch]))
      else if SwitchBlockedFiles(FRepo.Error, Files) then
      begin
        Shown := '';
        for i := 0 to Min(Files.Count, 10) - 1 do
          Shown := Shown + LineEnding + '  ' + Files[i];
        if Files.Count > 10 then
          Shown := Shown + LineEnding + '  ' + Format(rsSwitchMore, [Files.Count - 10]);
        case QuestionDlg(rsSwitchBlockedTitle, Format(rsSwitchBlocked, [ABranch]) + LineEnding +
            Shown, mtWarning, [mrYes, rsStashAndSwitch, 'IsDefault', mrNo, rsBringChanges,
            mrCancel, rsCancelButton, 'IsCancel'], 0) of
          mrYes:
            if not FRepo.Stash(Format(rsStashMessage, [ABranch])) then
              BannerError(rsStashFailed, FRepo.Error)
            else if FRepo.Switch(ABranch, False, ADetach) then
              Switched(Format(rsStashedSwitched, [ABranch]))
            else
            begin
              RefreshRepository;
              BannerError(Format(rsSwitchFailed, [ABranch]), FRepo.Error + LineEnding +
                LineEnding + rsStashKept);
            end;
          mrNo:
            if FRepo.Switch(ABranch, True, ADetach) then
              Switched(Format(rsSwitchedAlong, [ABranch]))
            else
              BannerError(Format(rsSwitchFailed, [ABranch]), FRepo.Error);
        end;
      end
      else
        BannerError(Format(rsSwitchFailed, [ABranch]), FRepo.Error);
    finally
      Files.Free;
    end;
  finally
    StartWatcher;
  end;
end;

procedure TForm1.MenuCopyPathClick(Sender: TObject);
begin
  if FContextPath <> '' then
    Clipboard.AsText := ContextFullPath;
end;

procedure TForm1.MenuCopyRelativePathClick(Sender: TObject);
begin
  if FContextPath <> '' then
    Clipboard.AsText := FContextPath;
end;

procedure TForm1.MenuRevealClick(Sender: TObject);
begin
  if FContextPath = '' then
    Exit;
  {$IFDEF DARWIN}
  RunDetached('open', ['-R', ContextFullPath]);
  {$ELSE}
  {$IFDEF WINDOWS}
  RunDetached('explorer.exe', ['/select,' + ContextFullPath]);
  {$ELSE}
  RunDetached('xdg-open', [ExtractFileDir(ContextFullPath)]);
  {$ENDIF}
  {$ENDIF}
end;

{ ---------------------------------------------------------------------------
  The editor menu, and GitHub
  ---------------------------------------------------------------------------
  ATSynEdit pops the menu up itself, so the editor under the mouse and
  the row there are found here, before the items are enabled. }
procedure TForm1.EditPopupPopup(Sender: TObject);
var
  P: TPoint;
  Details: TATEditorPosDetails;
  Info: TGittanBlameCommit;
  Key: integer;
  Src: TObject;
begin
  FPopupEd := Edit;
  if (FEditOld <> nil) and FEditOld.Visible and
    PtInRect(FEditOld.ClientRect, FEditOld.ScreenToClient(Mouse.CursorPos)) then
    FPopupEd := FEditOld;
  P := FPopupEd.ScreenToClient(Mouse.CursorPos);
  P := FPopupEd.ClientPosToCaretPos(ATPoint(P.X, P.Y), Details);
  FPopupRow := P.Y;
  if (P.Y < 0) or Details.BelowAllText then
    FPopupRow := -1;
  FPopupHash := '';
  FPopupKey := -1;
  FPopupIssue := 0;
  if (FPopupRow >= 0) and CommitOfRow(FPopupEd, FPopupRow, Info, Key, Src) and
    not Info.Uncommitted then
  begin
    FPopupHash := Info.Hash;
    if FView = gvHistory then
      FPopupKey := Key;
    FPopupIssue := IssueNumber(Info.Summary);
  end;
  FShowCommitItem.Enabled := FPopupHash <> '';
  FCopyHashItem.Enabled := FPopupHash <> '';
  FGitHubEditItem.Enabled := (FRepo.Root <> '') and (FCurrentPath <> '');
  FGitHubCommitItem.Enabled := FPopupHash <> '';
  FGitHubIssueItem.Visible := FHasGitHubCli and (FPopupIssue > 0);
  FGitHubIssueItem.Caption := Format(rsOpenIssueOnGitHub, [FPopupIssue]);
  FResolveEditItem.Visible := CanResolveBlocks;
  FResolveEditItem.Enabled := (FPopupEd = Edit) and (ConflictAtRow(FPopupRow) >= 0);
end;

{ The commit the row's blame or history gives, shown against its
  parent, as a click on the blame band does. }
procedure TForm1.MenuShowCommitClick(Sender: TObject);
begin
  if FPopupHash = '' then
    Exit;
  if (FView = gvHistory) and (FPopupKey >= 0) then
    ShowHistoryCommit(FPopupKey)
  else
    ShowBlameCommit(FPopupHash);
end;

procedure TForm1.MenuCopyHashClick(Sender: TObject);
begin
  if FPopupHash <> '' then
    Clipboard.AsText := FPopupHash;
end;

procedure TForm1.MenuEditCopyClick(Sender: TObject);
begin
  FPopupEd.DoCommand(cCommand_ClipboardCopy, TATCommandInvoke.MenuContext);
end;

procedure TForm1.MenuEditSelectAllClick(Sender: TObject);
begin
  FPopupEd.DoCommand(cCommand_SelectAll, TATCommandInvoke.MenuContext);
end;

{ The address of the page of the repository on GitHub that gh browse
  finds for AArgs: gh only prints it (--no-browser). A failure (no
  GitHub remote, say) is told in the status bar instead of going
  unseen. }
function TForm1.GitHubUrl(const AArgs: array of string; out AUrl: string): boolean;
var
  Args: array of string;
  Err: string;
  i: integer;
begin
  AUrl := '';
  Result := False;
  if not FHasGitHubCli or (FRepo.Root = '') then
    Exit;
  SetLength(Args, Length(AArgs) + 2);
  Args[0] := 'browse';
  Args[1] := '--no-browser';
  for i := 0 to High(AArgs) do
    Args[i + 2] := AArgs[i];
  Result := RunGitHubCli(FGitHubCli, FRepo.Root, Args, AUrl, Err) and (Trim(AUrl) <> '');
  AUrl := Trim(AUrl);
  if not Result then
  begin
    Err := Trim(Err);
    if Pos(LineEnding, Err) > 0 then
      Err := Copy(Err, 1, Pos(LineEnding, Err) - 1);
    StatusNote(Format(rsGitHubFailed, [Err]), True);
  end;
end;

procedure TForm1.OpenOnGitHub(const AArgs: array of string);
var
  Url: string;
begin
  if GitHubUrl(AArgs, Url) then
    OpenURL(Url);
end;

{ The gh browse arguments for a file, at ALine when it is above 0, in
  the version the view shows: the right commit of a range (what a blame
  click or Compare With > Other set), else the branch, since the work
  tree has no page. }
function TForm1.FileGitHubArgs(const APath: string; ALine: integer): TStringArray;
var
  Target, OldRef, NewRef: string;
begin
  Target := APath;
  if ALine > 0 then
    Target := Target + ':' + IntToStr(ALine);
  FRepo.DiffSides(OldRef, NewRef);
  if NewRef <> '' then
    Result := [Target, '--commit=' + NewRef]
  else if FBranch <> '' then
    Result := [Target, '--branch', FBranch]
  else
    Result := [Target];
end;

{ The line of the shown file that row ARow of AEd holds, 0 when the row
  is not one of the new side (a gap, a filler, a deleted line, the old
  side, or a history row, whose lines are of several versions). }
function TForm1.FileLineOfRow(AEd: TATSynEdit; ARow: integer): integer;
begin
  if AEd = Edit then
    Result := FileLineOfRow(ARow)
  else
    Result := 0;
end;

procedure TForm1.MenuOpenOnGitHubClick(Sender: TObject);
begin
  if FContextPath <> '' then
    OpenOnGitHub(FileGitHubArgs(FContextPath, 0));
end;

procedure TForm1.MenuCopyGitHubUrlClick(Sender: TObject);
var
  Url: string;
begin
  if (FContextPath <> '') and GitHubUrl(FileGitHubArgs(FContextPath, 0), Url) then
    Clipboard.AsText := Url;
end;

procedure TForm1.MenuOpenLineOnGitHubClick(Sender: TObject);
begin
  if FCurrentPath <> '' then
    OpenOnGitHub(FileGitHubArgs(FCurrentPath, FileLineOfRow(FPopupEd, FPopupRow)));
end;

procedure TForm1.MenuCopyLineGitHubUrlClick(Sender: TObject);
var
  Url: string;
begin
  if (FCurrentPath <> '') and
    GitHubUrl(FileGitHubArgs(FCurrentPath, FileLineOfRow(FPopupEd, FPopupRow)), Url) then
    Clipboard.AsText := Url;
end;

procedure TForm1.MenuOpenCommitOnGitHubClick(Sender: TObject);
begin
  if FPopupHash <> '' then
    OpenOnGitHub([FPopupHash]);
end;

{ gh browse with a number opens the issue or the pull request. }
procedure TForm1.MenuOpenIssueOnGitHubClick(Sender: TObject);
begin
  if FPopupIssue > 0 then
    OpenOnGitHub([IntToStr(FPopupIssue)]);
end;

{ Runs ACommand, words separated by spaces, with AArgs appended. }
procedure RunCommandWith(const ACommand: string; const AArgs: array of string);
var
  Words: TStringList;
  Args: array of string;
  i: integer;
begin
  Words := TStringList.Create;
  try
    Words.Delimiter := ' ';
    Words.StrictDelimiter := False;
    Words.DelimitedText := Trim(ACommand);
    if Words.Count = 0 then
      Exit;
    SetLength(Args, Words.Count - 1 + Length(AArgs));
    for i := 1 to Words.Count - 1 do
      Args[i - 1] := Words[i];
    for i := 0 to High(AArgs) do
      Args[Words.Count - 1 + i] := AArgs[i];
    RunDetached(Words[0], Args);
  finally
    Words.Free;
  end;
end;

{ The editor command from the settings, with the path appended; the
  desktop's default application when none is set. }
procedure TForm1.MenuOpenInEditorClick(Sender: TObject);
begin
  if FContextPath = '' then
    Exit;
  if Trim(FSettings.EditorCommand) = '' then
    OpenDocument(ContextFullPath)
  else
    RunCommandWith(FSettings.EditorCommand, [ContextFullPath]);
end;

{ The commit graph: the newest GraphLimit commits of every branch, in
  the middle of the form. A click on the status bar's ahead/behind
  counts opens it, as View > Commit Graph does; picking a commit shows
  it against its parent, as a click on a blame band does. With a filter
  (Show History in a file's menu, Go > File History) the graph gets up
  to GraphSearchLimit commits at once, since a filter looks through the
  whole history; it asks for the same (GraphMore) when a filter is typed
  into a graph that was cut, or the last row is clicked. The commits
  that touched a path come from TGittanRepo.PathCommits. }
const
  GraphLimit = 500;
  GraphSearchLimit = 50000;

procedure TForm1.ShowCommitGraph(const AFilter: string);
var
  Commits: TGittanGraphCommits;
  Limit: integer;
begin
  if FRepo.Root = '' then
    Exit;
  if FGraph.Visible and (AFilter = '') then
  begin
    FGraph.Close;
    Exit;
  end;
  if AFilter = '' then
    Limit := GraphLimit
  else
    Limit := GraphSearchLimit;
  Screen.Cursor := crHourGlass;
  try
    FRepo.GraphCommits(Commits, Limit);
  finally
    Screen.Cursor := crDefault;
  end;
  FGraph.Marked := FMarkHash;
  FGraph.Popup(Commits, Length(Commits) >= Limit, FBranch, FAhead, FBehind,
    FHasUpstream, AFilter);
  if FGraph.Visible then
    FSideNav.Selected := navGraph;
end;

procedure TForm1.GraphMore(Sender: TObject);
var
  Commits: TGittanGraphCommits;
begin
  if FRepo.Root = '' then
    Exit;
  Screen.Cursor := crHourGlass;
  try
    FRepo.GraphCommits(Commits, GraphSearchLimit);
  finally
    Screen.Cursor := crDefault;
  end;
  FGraph.Replace(Commits, Length(Commits) >= GraphSearchLimit);
end;

procedure TForm1.GraphPathCommits(Sender: TObject; const APath: string;
  AHashes: TStrings);
begin
  if FRepo.Root <> '' then
    FRepo.PathCommits(APath, AHashes, GraphSearchLimit);
end;

{ The filter that keeps the commits touching APath: quoted when the path
  has a space, as ParseGraphFilter reads it. }
function PathFilter(const APath: string): string;
begin
  if Pos(' ', APath) > 0 then
    Result := 'path:"' + APath + '"'
  else
    Result := 'path:' + APath;
end;

{ Show History in the file menu: the graph with the commits that touched
  the file, or the folder of the tree. }
procedure TForm1.MenuFileHistoryClick(Sender: TObject);
begin
  if FContextPath <> '' then
    ShowCommitGraph(PathFilter(FContextPath))
  else if FContextFolder <> '' then
    ShowCommitGraph(PathFilter(FContextFolder));
end;

{ Go > File History: the same for the shown file. }
procedure TForm1.MenuGoFileHistoryClick(Sender: TObject);
begin
  if FCurrentPath <> '' then
    ShowCommitGraph(PathFilter(FCurrentPath));
end;

procedure TForm1.MenuCommitGraphClick(Sender: TObject);
begin
  ShowCommitGraph;
end;

{ The summary shows the commit, from any page: its card names it and
  leads back to the working tree. }
procedure TForm1.GraphPick(Sender: TObject; const AHash: string);
begin
  ShowBlameCommit(AHash);
  ShowSummary;
end;

{ A click on a commit in the summary of a clean tree shows it against its
  parent, as a pick from the commit graph does. }
procedure TForm1.SummarySelectCommit(Sender: TObject; const AHash: string);
begin
  ShowBlameCommit(AHash);
end;

{ The status bar's parts: the branch drops the branch list up from it,
  as in the summary; the track with the ahead/behind counts drops up
  pull, push, fetch and the commit graph; the transport buttons take
  their step (UpdateStatusTransport); the pull request drops its list;
  the name and the file count go back to the summary. }
procedure TForm1.StatusPartClick(Sender: TObject; APart: TGittanStatusPart;
  const AScreenRect: TRect);
begin
  case APart of
    spRepo, spFiles:
      MenuSummaryClick(Sender);
    spBranch:
      SummaryBranchClick(Sender, AScreenRect);
    spBase:
      BaseClick(AScreenRect);
    spSync:
      SyncClick(AScreenRect);
    spStash:
      ShowStashList(AScreenRect);
    spPull:
      PullChipClick(AScreenRect);
    spUpdate:
      UpdateDialog;
    spLeft, spPrimary, spRight:
      StatusStepClick(FStatusSteps[APart], AScreenRect);
  end;
end;

{ Resolve drops down the conflicted files, as the conflict badge did;
  the rest run the menu items and the Commit section's buttons. }
procedure TForm1.StatusStepClick(AStep: TStatusStep; const AScreenRect: TRect);
begin
  case AStep of
    stepFetch: MenuFetchClick(nil);
    stepPull: MenuPullClick(nil);
    stepPush: MenuPushClick(nil);
    stepForcePush: ForcePushAsk;
    stepContinue: ContinueOperationClick;
    stepCommit: CommitButtonClick(nil);
    stepAbort: AbortOperationClick(nil);
    stepSkip: SkipOperationClick(nil);
    stepResolve: ConflictBadgeClick(AScreenRect);
  end;
end;

procedure TForm1.MenuCopyBranchClick(Sender: TObject);
begin
  if FBranch <> '' then
    Clipboard.AsText := FBranch;
end;

procedure TForm1.MenuCopyRepoPathClick(Sender: TObject);
begin
  if FRepo.Root <> '' then
    Clipboard.AsText := FRepo.Root;
end;

procedure TForm1.MenuOpenTerminalClick(Sender: TObject);
begin
  OpenTerminal('');
end;

{ The shell line that runs ACommand in ARoot and keeps the terminal
  open after it, for a terminal's -e. }
function ShellLineIn(const ARoot, ACommand: string): string;
begin
  Result := 'cd ' + QuotedStr(ARoot) + ' && ' + ACommand + '; exec ${SHELL:-sh}';
end;

{ A terminal in the repository root, running ACommand there when it is
  not empty (a command of the repository marked for the terminal, see
  umain.commands.inc). The terminal command from the settings file gets
  the root appended, and the command after it; the platform's terminal
  when none is set. On macOS Terminal is told through osascript to
  cd into the root and run the command; on Windows Windows Terminal
  or cmd.exe runs it with /K, so the window stays; on Linux the first
  terminal found on PATH is started in the root, since every terminal
  starts in its working directory but each names the option
  differently, and given the command with -e. }
procedure TForm1.OpenTerminal(const ACommand: string);
{$IF not defined(DARWIN) and not defined(WINDOWS)}
const
  Terminals: array[0..4] of string = ('x-terminal-emulator', 'gnome-terminal',
    'konsole', 'xfce4-terminal', 'xterm');
var
  T: string;
{$ENDIF}
{$IFDEF DARWIN}
var
  Script: string;
{$ENDIF}
begin
  if FRepo.Root = '' then
    Exit;
  if Trim(FSettings.TerminalCommand) <> '' then
  begin
    if ACommand = '' then
      RunCommandWith(FSettings.TerminalCommand, [FRepo.Root])
    else
      RunCommandWith(FSettings.TerminalCommand, [FRepo.Root, ACommand]);
    Exit;
  end;
  {$IFDEF DARWIN}
  if ACommand = '' then
    RunDetached('open', ['-a', 'Terminal', FRepo.Root])
  else
  begin
    { The line goes into an AppleScript string: its backslashes and
      quotes escaped. }
    Script := 'cd ' + QuotedStr(FRepo.Root) + ' && ' + ACommand;
    Script := StringReplace(Script, '\', '\\', [rfReplaceAll]);
    Script := StringReplace(Script, '"', '\"', [rfReplaceAll]);
    RunDetached('osascript', ['-e', 'tell application "Terminal" to do script "' +
      Script + '"', '-e', 'tell application "Terminal" to activate']);
  end;
  {$ELSE}
  {$IFDEF WINDOWS}
  if FindDefaultExecutablePath('wt.exe') <> '' then
  begin
    if ACommand = '' then
      RunDetached('wt.exe', ['-d', FRepo.Root])
    else
      RunDetached('wt.exe', ['-d', FRepo.Root, 'cmd.exe', '/K', ACommand]);
  end
  else if ACommand = '' then
    RunDetached('cmd.exe', ['/C', 'start', 'cmd.exe'], FRepo.Root)
  else
    RunDetached('cmd.exe', ['/C', 'start', 'cmd.exe', '/K', ACommand], FRepo.Root);
  {$ELSE}
  for T in Terminals do
    if FindDefaultExecutablePath(T) <> '' then
    begin
      if ACommand = '' then
        RunDetached(T, [], FRepo.Root)
      else
        RunDetached(T, ['-e', 'sh -c ' + QuotedStr(ShellLineIn(FRepo.Root, ACommand))],
          FRepo.Root);
      Exit;
    end;
  {$ENDIF}
  {$ENDIF}
end;

{ Tools > Install CLI Command: a gittan command for the terminal that
  starts this executable (see gittan.cli). }
procedure TForm1.MenuInstallCliClick(Sender: TObject);
var
  Msg: string;
begin
  if InstallCli(Application.ExeName, Msg) then
    MessageDlg(Msg, mtInformation, [mbOK], 0)
  else
    MessageDlg(Msg, mtError, [mbOK], 0);
end;

procedure TForm1.MenuUninstallCliClick(Sender: TObject);
var
  Msg: string;
begin
  if UninstallCli(Msg) then
    MessageDlg(Msg, mtInformation, [mbOK], 0)
  else
    MessageDlg(Msg, mtError, [mbOK], 0);
end;

{ Uninstall is offered only while Gittan's own script is installed; the
  menu's OnClick runs as it opens. }
procedure TForm1.ToolsMenuClick(Sender: TObject);
begin
  FUninstallCliItem.Enabled := CliInstalled;
end;

{ ---------------------------------------------------------------------------
  Comparing against another commit
  ---------------------------------------------------------------------------
  View > Compare With lists the branches and tags, then the snapshots of
  the repository; the chosen one becomes the repository's Base, and every
  diff, count and the watcher follow it. The list is rebuilt with the
  repository. A snapshot item carries Tag 1: the base is then compared
  with WholeTree, since the snapshot holds the untracked files. }
procedure TForm1.RebuildCompareMenu;
var
  Refs: TStringList;
  Item: TMenuItem;
  i: integer;

  function AddRef(const ACaption, ARef: string; ASnapshot: boolean): TMenuItem;
  begin
    Result := TMenuItem.Create(FCompareMenu);
    Result.Caption := ACaption;
    Result.Hint := ARef;
    Result.Tag := Ord(ASnapshot);
    Result.RadioItem := True;
    Result.Checked := (ARef = FRepo.Base) and (ASnapshot = FRepo.WholeTree);
    Result.OnClick := @MenuCompareClick;
    FCompareMenu.Add(Result);
  end;

begin
  if FCompareMenu = nil then
    Exit;
  FCompareMenu.Clear;
  AddRef(rsWorkingTree, '', False);
  if FMergeBase <> '' then
    AddRef(Format(rsMergeBase, [FDefaultBranch]), FMergeBase, False);
  Refs := TStringList.Create;
  try
    if FRepo.Root <> '' then
      FRepo.Refs(Refs);
    if (FRepo.Base <> '') and not FRepo.WholeTree and (FRepo.Base <> FPullRange) and
      (FRepo.Base <> FStashRange) and (FRepo.Base <> FMergeBase) and
      (Refs.IndexOf(FRepo.Base) < 0) then
      Refs.Insert(0, FRepo.Base);
    if Refs.Count > 0 then
      FCompareMenu.Add(NewLine);
    for i := 0 to Min(Refs.Count, 40) - 1 do
      AddRef(Refs[i], Refs[i], False);
  finally
    Refs.Free;
  end;
  if FSnapshots.Count > 0 then
    FCompareMenu.Add(NewLine);
  for i := 0 to FSnapshots.Count - 1 do
    AddRef(Format(rsSnapshot, [TGittanSnapshots.Caption(FSnapshots[i].Time, Now)]),
      FSnapshots[i].Id, True);
  FCompareMenu.Add(NewLine);
  Item := TMenuItem.Create(FCompareMenu);
  Item.Caption := rsTakeSnapshot;
  Item.ShortCut := ShortCut(VK_N, [ssModifier, ssShift]);
  Item.OnClick := @MenuTakeSnapshotClick;
  FCompareMenu.Add(Item);
  FPullMenu := nil;
  if FHasGitHubCli then
  begin
    FPullMenu := TMenuItem.Create(FCompareMenu);
    FPullMenu.Caption := rsPullRequests;
    FCompareMenu.Add(FPullMenu);
    RebuildPullMenu;
  end;
  Item := TMenuItem.Create(FCompareMenu);
  Item.Caption := rsOtherRef;
  Item.OnClick := @MenuCompareOtherClick;
  FCompareMenu.Add(Item);
  FCompareMenu.Enabled := FRepo.Root <> '';
end;

procedure TForm1.MenuCompareClick(Sender: TObject);
begin
  SetBase(TMenuItem(Sender).Hint, TMenuItem(Sender).Tag = 1);
end;

procedure TForm1.MenuCompareOtherClick(Sender: TObject);
var
  Ref: string;
begin
  if FRepo.Root = '' then
    Exit;
  Ref := Trim(InputBox(StringReplace(rsCompareWith, '&', '', []), rsRefPrompt, FRepo.Base));
  SetBase(Ref);
end;

{ ---------------------------------------------------------------------------
  Pull requests
  ---------------------------------------------------------------------------
  gh goes to the network, so the job runs in a thread: once per
  repository and branch, and again on View > Refresh (AForce). A job
  still running for something else is abandoned like a blame job. }
procedure TForm1.StartPullJob(AForce: boolean; AKeep: boolean);
var
  Key: string;
begin
  if not FHasGitHubCli then
    Exit;
  Key := FRepo.Root + #0 + FBranch;
  if (FRepo.Root = '') or (not AForce and (Key = FPullKey)) then
    Exit;
  AbandonPullJob;
  FPullKey := Key;
  if not AKeep then
  begin
    FHasPull := False;
    FPulls := nil;
    FPullError := '';
    FGoneBranches.Clear;
    FSummary.SetUpstreamGone(False);
  end;
  FPullJob := TGittanPullRequestJob.Create(FGitHubCli, FRepo.Root, FBranch);
  FPullJob.OnDone := @PullJobDone;
  FPullJob.Start;
  if not AKeep then
    RebuildPullMenu;
  UpdatePullPage;
end;

{ A poll waits for a job still running; that job's end sets the timer
  again. }
procedure TForm1.PullTimerTimer(Sender: TObject);
begin
  FPullTimer.Enabled := False;
  if (FRepo.Root = '') or (FPullJob <> nil) then
    Exit;
  StartPullJob(True, True);
end;

procedure TForm1.AbandonPullJob;
begin
  { No job, no poll: the next finished job starts the timer again. }
  FPullTimer.Enabled := False;
  if FPullJob = nil then
    Exit;
  FPullJob.Stop(False);
  FBlameZombies.Add(FPullJob);
  FPullJob := nil;
end;

procedure TForm1.PullJobDone(Sender: TObject);
var
  Job: TGittanPullRequestJob;
begin
  Job := TGittanPullRequestJob(Sender);
  if Job <> FPullJob then
    Exit;
  FPullJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  FHasPull := Job.HasPull;
  FPull := Job.Pull;
  FPulls := Job.Pulls;
  FPullError := Job.Error;
  FGoneBranches.Assign(Job.GoneBranches);
  FSummary.SetUpstreamGone(FGoneBranches.IndexOf(FBranch) >= 0);
  UpdateStatus;
  RebuildPullMenu;
  UpdatePullPage;
  { The review comments follow at the same pace. }
  StartReviewJob(True);
  { Ask again later, more often while checks run; not when gh failed
    (no GitHub remote, not logged in), which a refresh retries. }
  if FPullError = '' then
  begin
    if FHasPull and (FPull.ChecksPending > 0) then
      FPullTimer.Interval := PullPollPending
    else
      FPullTimer.Interval := PullPollIdle;
    FPullTimer.Enabled := True;
  end;
end;

{ Compare With > Pull Requests: one radio item per open pull request,
  the one compared against checked; a note while the job runs, when
  there are none, or when gh failed. }
procedure TForm1.RebuildPullMenu;
var
  Item: TMenuItem;
  i: integer;
  Note: string;
begin
  if FPullMenu = nil then
    Exit;
  FPullMenu.Clear;
  if FPullJob <> nil then
    Note := rsPullLoading
  else if FPullError <> '' then
    Note := FPullError
  else if Length(FPulls) = 0 then
    Note := rsNoPulls
  else
    Note := '';
  if Note <> '' then
  begin
    Item := TMenuItem.Create(FPullMenu);
    Item.Caption := Note;
    Item.Enabled := False;
    FPullMenu.Add(Item);
    Exit;
  end;
  for i := 0 to High(FPulls) do
  begin
    Item := TMenuItem.Create(FPullMenu);
    if FPulls[i].IsDraft then
      Item.Caption := Format(rsPullDraftItem, [FPulls[i].Number, FPulls[i].Title])
    else
      Item.Caption := Format(rsPullItem, [FPulls[i].Number, FPulls[i].Title]);
    Item.Hint := FPulls[i].Url;
    Item.Tag := i;
    Item.RadioItem := True;
    Item.Checked := (FPullRange <> '') and (FRepo.Base = FPullRange) and
      (FPulls[i].Number = FPullNumber);
    Item.OnClick := @MenuComparePullClick;
    FPullMenu.Add(Item);
  end;
end;

{ Fetches the pull request's head into a ref of Gittan's own, and its
  base branch, and compares the two with the three-dot range, as GitHub
  shows a pull request: what the branch adds since it left the base. }
procedure TForm1.MenuComparePullClick(Sender: TObject);
var
  i: integer;
begin
  i := TMenuItem(Sender).Tag;
  if (FRepo.Root = '') or (i < 0) or (i > High(FPulls)) then
    Exit;
  ComparePull(FPulls[i]);
end;

{ Fetches APull and compares with it: the range from where it left its
  base to its head, what GitHub shows as its changes. The fetch is a
  remote job (umain.remote.inc), so the window goes on while it runs;
  PullFetchDone compares. Not while another remote job or a commit
  runs. }
procedure TForm1.ComparePull(const APull: TGittanPullRequest);
begin
  if FRepo.Root = '' then
    Exit;
  StartPullFetch(APull.Number, FRepo.RemoteFor(RepoPathOfUrl(APull.Url)), APull.BaseRef);
end;

procedure TForm1.StartPullFetch(ANumber: integer; const ARemote, ABaseRef: string);
begin
  if (FRepo.Root = '') or (FRemoteJob <> nil) or (FCommitJob <> nil) then
    Exit;
  FNoticeHook := False;
  FRemoteHead := '';
  FRemoteAhead := FAhead;
  FRemoteJob := TGittanRemoteJob.Create(FRepo.Root, rkFetchPull, pmAuto, IntToStr(ANumber),
    ARemote);
  FRemoteJob.Branch := ABaseRef;
  FRemoteJob.OnDone := @RemoteJobDone;
  FRemoteJob.OnOutput := @RemoteJobOutput;
  FRemoteJob.Start;
  FStatus.ShowMessage(Format(rsFetchingPull, [ANumber]), stNormal, 0);
  FNoticeTimer.Enabled := True;
  UpdateRemoteItems;
  UpdateCommitState;
end;

procedure TForm1.PullFetchDone(AJob: TGittanRemoteJob);
begin
  if not AJob.Ok then
  begin
    ShowRemoteFailure(AJob, False);
    Exit;
  end;
  FPullRange := AJob.Remote + '/' + AJob.Branch + '...' + AJob.HeadRef;
  FPullNumber := StrToIntDef(AJob.Arg, 0);
  SetBase(FPullRange);
end;

{ The rows of the list a click on the status bar's pull request drops
  down. }
const
  paCompare = 1;
  paWorkingTree = 2;
  paOpen = 3;
  paCopy = 4;
  paList = 5;

{ A click on the status bar's pull request: compare with it, which
  shows its changes as GitHub does and its review comments where they
  were made (with how many are open), back to the working tree, or open
  it on GitHub. }
procedure TForm1.PullChipClick(const AScreenRect: TRect);
var
  Comparing: boolean;
  Detail: string;
  Open: integer;

  procedure AddAction(AAction: integer; const ACaption, ADetail: string;
    AChecked: boolean = False);
  begin
    FPullPopup.Add(ACaption, ADetail, AChecked);
    SetLength(FPullActions, Length(FPullActions) + 1);
    FPullActions[High(FPullActions)] := AAction;
  end;

begin
  if not FHasPull or (FRepo.Root = '') then
    Exit;
  Comparing := (FPullRange <> '') and (FRepo.Base = FPullRange) and FRepo.IsRange and
    (FPullNumber = FPull.Number);
  Detail := '';
  if FShowComments and (FThreadsNumber = FPull.Number) then
  begin
    Open := OpenThreads(FThreads);
    if Open = 1 then
      Detail := rsReviewOpenOne
    else if Open > 1 then
      Detail := Format(rsReviewOpen, [Open]);
  end;
  FPullPopup.Clear;
  FPullActions := nil;
  FPullPopup.AddHeader(Format(rsPullHintTitle, [FPull.Number, FPull.Title]));
  SetLength(FPullActions, 1);
  FPullActions[0] := 0;
  AddAction(paCompare, rsComparePull, Detail, Comparing);
  AddAction(paWorkingTree, rsCompareWorkingTree, '', (FRepo.Base = '') and
    not FRepo.WholeTree);
  if FPull.Url <> '' then
  begin
    AddAction(paOpen, rsOpenPullOnGitHub, '');
    AddAction(paCopy, rsCopyPullLink, '');
  end;
  AddAction(paList, rsAllPulls, '');
  FPullPopup.Popup(AScreenRect);
end;

procedure TForm1.PullPopupPick(Sender: TObject; AIndex: integer);
begin
  if (AIndex < 0) or (AIndex > High(FPullActions)) or not FHasPull then
    Exit;
  case FPullActions[AIndex] of
    paCompare:
      if not ((FPullRange <> '') and (FRepo.Base = FPullRange) and
        (FPullNumber = FPull.Number)) then
        ComparePull(FPull);
    paWorkingTree: SetBase('');
    paOpen: MenuOpenPullClick(Sender);
    paCopy: MenuCopyPullUrlClick(Sender);
    paList: ShowPulls;
  end;
end;

procedure TForm1.StatusPopupPopup(Sender: TObject);
begin
  FOpenPullItem.Enabled := FHasPull and (FPull.Url <> '');
  FCopyPullItem.Enabled := FHasPull and (FPull.Url <> '');
end;

procedure TForm1.MenuOpenPullClick(Sender: TObject);
begin
  if FHasPull and (FPull.Url <> '') then
    OpenURL(FPull.Url);
end;

function TForm1.PullChecks(const APull: TGittanPullRequest; out ACount: integer): TGittanStatusTone;
begin
  ACount := 0;
  if APull.ChecksFailed > 0 then
  begin
    ACount := APull.ChecksFailed;
    Result := stBad;
  end
  else if APull.ChecksPending > 0 then
  begin
    ACount := APull.ChecksPending;
    Result := stWarn;
  end
  else if APull.ChecksPassed > 0 then
    Result := stGood
  else
    Result := stNormal;
end;

{ One line per outcome of the checks, as gh counts them for the status
  line (a skipped one passed), worst first, each with its icon. }
function TForm1.PullHint(const APull: TGittanPullRequest): string;

  procedure AddChecks(ACount: integer; const AIcon, AOne, AMany: string);
  begin
    if ACount = 1 then
      Result := Result + LineEnding + AIcon + ' ' + AOne
    else if ACount > 1 then
      Result := Result + LineEnding + AIcon + ' ' + Format(AMany, [ACount]);
  end;

begin
  Result := Format(rsPullHintTitle, [APull.Number, APull.Title]);
  AddChecks(APull.ChecksFailed, HintFailed, rsPullHintFailedOne, rsPullHintFailed);
  AddChecks(APull.ChecksPending, HintPending, rsPullHintPendingOne, rsPullHintPending);
  AddChecks(APull.ChecksPassed, HintPassed, rsPullHintPassedOne, rsPullHintPassed);
  Result := Result + ReviewHint(APull.Number);
  Result := Result + LineEnding + HintLink + ' ' + rsPullHintOpen;
end;

procedure TForm1.MenuCopyPullUrlClick(Sender: TObject);
begin
  if FHasPull and (FPull.Url <> '') then
    Clipboard.AsText := FPull.Url;
end;

{ ---------------------------------------------------------------------------
  Snapshots
  ---------------------------------------------------------------------------
  Compare With > Take Snapshot (Cmd+Shift+N) records the work tree as it
  is, untracked files included, as a commit no branch points at
  (TGittanRepo.TakeSnapshot) and compares against it, so the views show
  only what changes from here on: what one wants while someone or
  something else is editing the tree. The snapshots of a repository are
  kept in a file in the cache folder, named by a hash of the root like
  the symbol index, newest first; LoadSnapshots drops the ones git has
  pruned since. A failed snapshot is noted in the summary. }
procedure TForm1.MenuTakeSnapshotClick(Sender: TObject);
var
  Id: string;
begin
  if FRepo.Root = '' then
    Exit;
  if not FRepo.TakeSnapshot(Id) then
  begin
    FSummary.Notice := Format(rsSnapshotFailed, [FRepo.Error]);
    ShowSummary;
    Exit;
  end;
  FSnapshots.Add(Id, Now);
  SaveSnapshots;
  SetBase(Id, True);
end;

function TForm1.SnapshotsFileName: string;
begin
  Result := IndexCacheDir + MD5Print(MD5String(FRepo.Root)) + '.snapshots';
end;

procedure TForm1.LoadSnapshots;
var
  i, Count: integer;
begin
  FSnapshots.Load(SnapshotsFileName);
  Count := FSnapshots.Count;
  for i := FSnapshots.Count - 1 downto 0 do
    if not FRepo.HasCommit(FSnapshots[i].Id) then
      FSnapshots.Delete(i);
  if FSnapshots.Count <> Count then
    SaveSnapshots;
end;

procedure TForm1.SaveSnapshots;
begin
  try
    FSnapshots.Save(SnapshotsFileName);
  except
    { The cache folder cannot be written; the list lives for the session. }
  end;
end;

{ What the work tree is compared against, for the summary, the status
  bar and the repository diff: "vs base", or the range itself, which
  says both sides; '' against HEAD. }
function TForm1.BaseLabel: string;
var
  i: integer;
begin
  if FRepo.Base = '' then
    Result := ''
  else if (FRepo.Base = FBlameRange) and FRepo.IsRange then
    Result := Format(rsVsBase, [Format(rsCommit,
      [Copy(FRepo.Base, Pos('..', FRepo.Base) + 2, 7)])])
  else if (FRepo.Base = FPullRange) and FRepo.IsRange then
    Result := Format(rsVsBase, [Format(rsVsPull, [FPullNumber])])
  else if (FRepo.Base = FStashRange) and (StashOfBase >= 0) then
    Result := Format(rsVsBase, [Format(rsVsStash, [StashLabel(FStashes[StashOfBase])])])
  else if (FRepo.Base = FStashRange) and FRepo.IsRange then
    Result := Format(rsVsBase, [Format(rsVsStash, [Copy(FStashRangeId, 1, 7)])])
  else if FRepo.IsRange and (Pos('...', FRepo.Base) > 0) then
    { "main...feature" reads as what feature changed since main. }
    Result := Format(rsVsSince, [Copy(FRepo.Base, Pos('...', FRepo.Base) + 3, MaxInt),
      Copy(FRepo.Base, 1, Pos('...', FRepo.Base) - 1)])
  else if FRepo.IsRange then
    Result := FRepo.Base
  else if FRepo.WholeTree then
  begin
    i := FSnapshots.IndexOf(FRepo.Base);
    if i >= 0 then
      Result := Format(rsVsBase, [Format(rsVsSnapshot,
        [TGittanSnapshots.Caption(FSnapshots[i].Time, Now)])])
    else
      Result := Format(rsVsBase, [Copy(FRepo.Base, 1, 7)]);
  end
  else if FRepo.Base = FMergeBase then
    Result := Format(rsVsBase, [Format(rsVsMergeBase, [FDefaultBranch])])
  else
    Result := Format(rsVsBase, [FRepo.Base]);
end;

{ A base git cannot resolve is reported in the summary and the previous
  one is kept. ASnapshot compares the whole tree, see TakeSnapshot. }
procedure TForm1.SetBase(const ARef: string; ASnapshot: boolean);
var
  Prev: string;
  PrevSnapshot: boolean;
begin
  if (FRepo.Root = '') or ((ARef = FRepo.Base) and (ASnapshot = FRepo.WholeTree)) then
    Exit;
  Prev := FRepo.Base;
  PrevSnapshot := FRepo.WholeTree;
  StopWatcher;
  try
    if ARef <> FBlameRange then
      FBlameRange := '';
    FRepo.Base := ARef;
    FRepo.WholeTree := ASnapshot;
    FLoadError := '';
    RefreshRepository;
    if FLoadError <> '' then
    begin
      FRepo.Base := Prev;
      FRepo.WholeTree := PrevSnapshot;
      FBlameRange := '';
      RefreshRepository;
      FSummary.Notice := FLoadError;
      ShowSummary;
    end;
  finally
    StartWatcher;
  end;
  { Comparing with a pull request shows its comments. }
  StartReviewJob(False);
end;
