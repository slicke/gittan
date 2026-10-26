{ ---------------------------------------------------------------------------
  Settings
  ---------------------------------------------------------------------------
  Included by umain.pp. The settings are read as App is made (gittan.app)
  and applied here before the menu is built, so its check marks match;
  they are written when the window closes. The window's place and size
  are the window's (uwindow). }

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

procedure TRepoFrame.ApplySettings;
var
  i: integer;
begin
  FOnlyChanges := App.Settings.OnlyChanges;
  FSideBySide := App.Settings.SideBySide;
  FMdPreviewOn := App.Settings.MarkdownPreview;
  FWordWrap := App.Settings.WordWrap;
  FIgnoreWhitespace := App.Settings.IgnoreWhitespace;
  FBlameOn := App.Settings.Blame;
  FShowComments := App.Settings.ReviewComments;
  FTranslations := App.Settings.Translations;
  FSyntaxTheme := FindSyntaxTheme(App.Settings.SyntaxTheme);
  if FSyntaxTheme < 0 then
    FSyntaxTheme := DefaultSyntaxTheme;
  if FSyntaxTheme <> DefaultSyntaxTheme then
    App.Lexers.ApplyTheme(FDark, FSyntaxTheme);
  FRepo.IgnoreWhitespace := FIgnoreWhitespace;
  FContextLines := ContextChoices[1];
  for i := 0 to High(ContextChoices) do
    if ContextChoices[i] = App.Settings.ContextLines then
      FContextLines := ContextChoices[i];
  { The editor font as picked, else the platform's, its size from the
    height of the screen the window is on. }
  FDefaultFontSize := DefaultFontSize(MulDiv(Screen.MonitorFromRect(FWindow.BoundsRect)
    .BoundsRect.Height, 96, Screen.PixelsPerInch));
  if App.Settings.FontName <> '' then
    Edit.Font.Name := App.Settings.FontName
  else
    Edit.Font.Name := DefaultFontName;
  if App.Settings.FontSize > 0 then
    Edit.Font.Size := App.Settings.FontSize
  else
    Edit.Font.Size := FDefaultFontSize;
  FEditOld.Font.Assign(Edit.Font);
  if App.Settings.Zoom > 0 then
  begin
    Edit.OptScaleFont := App.Settings.Zoom;
    FEditOld.OptScaleFont := App.Settings.Zoom;
  end;
  if App.Settings.TreeWidth > 80 then
    FTreePanel.Width := App.Settings.TreeWidth;
  FSideNav.Collapsed := not App.Settings.NavOpen;
  FRepoHeader.Expanded := App.Settings.RepoFilesOpen;
  FSubHeader.Expanded := App.Settings.SubmodulesOpen;
  FCommitHeader.Expanded := App.Settings.CommitOpen;
  FCommitBox.Visible := FCommitHeader.Expanded;
  LayoutRepoFiles;
end;

procedure TRepoFrame.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  App.Settings.TreeWidth := MulDiv(FTreePanel.Width, 96, Screen.PixelsPerInch);
  App.Settings.NavOpen := not FSideNav.Collapsed;
  App.Settings.RepoFilesOpen := FRepoHeader.Expanded;
  App.Settings.SubmodulesOpen := FSubHeader.Expanded;
  App.Settings.CommitOpen := FCommitHeader.Expanded;
  StopCommitJob(True);
  StopRemoteJob(True);
  AbandonCommandJob(True);
  SaveCommitDraft;
  { The defaults are not written, so they follow the screen and a later
    Gittan's choice. }
  App.Settings.FontName := Edit.Font.Name;
  if SameText(App.Settings.FontName, DefaultFontName) then
    App.Settings.FontName := '';
  App.Settings.FontSize := Edit.Font.Size;
  if App.Settings.FontSize = FDefaultFontSize then
    App.Settings.FontSize := 0;
  App.Settings.Zoom := Edit.OptScaleFont;
  App.Settings.TabSize := FTabSize;
  if FTabSize = DefaultTabSize then
    App.Settings.TabSize := 0;
  App.Settings.WordWrap := FWordWrap;
  App.Settings.OnlyChanges := FOnlyChanges;
  App.Settings.ContextLines := FContextLines;
  App.Settings.SideBySide := FSideBySide;
  App.Settings.MarkdownPreview := FMdPreviewOn;
  App.Settings.IgnoreWhitespace := FIgnoreWhitespace;
  App.Settings.Blame := FBlameOn;
  App.Settings.ReviewComments := FShowComments;
  App.Settings.Translations := FTranslations;
  App.Settings.SyntaxTheme := SyntaxThemes[FSyntaxTheme].Name;
  App.Settings.Save;
  SaveIndex;
end;

{ ---------------------------------------------------------------------------
  Recent repositories
  --------------------------------------------------------------------------- }
procedure TRepoFrame.RebuildRecentMenu;
var
  Item: TMenuItem;
  i: integer;
begin
  FRecentMenu.Clear;
  for i := 0 to App.Settings.Recent.Count - 1 do
  begin
    Item := TMenuItem.Create(FRecentMenu);
    Item.Caption := ShortPath(App.Settings.Recent[i]);
    Item.Hint := App.Settings.Recent[i];
    Item.OnClick := @MenuRecentClick;
    FRecentMenu.Add(Item);
  end;
  if App.Settings.Recent.Count > 0 then
    FRecentMenu.Add(NewLine);
  Item := TMenuItem.Create(FRecentMenu);
  Item.Caption := rsClearMenu;
  Item.Enabled := App.Settings.Recent.Count > 0;
  Item.OnClick := @MenuClearRecentClick;
  FRecentMenu.Add(Item);
  FWelcome.SetRecent(App.Settings.Recent);
end;

procedure TRepoFrame.MenuRecentClick(Sender: TObject);
begin
  FWindow.OpenRepository(TMenuItem(Sender).Hint);
end;

procedure TRepoFrame.MenuClearRecentClick(Sender: TObject);
begin
  App.Settings.Recent.Clear;
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
procedure TRepoFrame.MenuFindClick(Sender: TObject);
begin
  if not Edit.Visible then
    Exit;
  FFindBar.Activate;
end;

procedure TRepoFrame.MenuFindNextClick(Sender: TObject);
begin
  if FFindBar.SearchText = '' then
    MenuFindClick(Sender)
  else
    FindText(FFindBar.SearchText, True, False);
end;

procedure TRepoFrame.MenuFindPrevClick(Sender: TObject);
begin
  if FFindBar.SearchText = '' then
    MenuFindClick(Sender)
  else
    FindText(FFindBar.SearchText, False, False);
end;

procedure TRepoFrame.FindBarSearch(Sender: TObject; const AText: string;
  ANext, AFromStart: boolean);
begin
  FindText(AText, ANext, AFromStart);
end;

procedure TRepoFrame.FindBarClose(Sender: TObject);
begin
  FFindBar.Visible := False;
  if Edit.Visible and Edit.CanFocus then
    Edit.SetFocus;
end;

procedure TRepoFrame.FindText(const AText: string; ANext, AFromStart: boolean);
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
procedure TRepoFrame.MenuZoomInClick(Sender: TObject);
begin
  Edit.DoScaleFontDelta(True, True);
  EditChangeZoom(Edit);
end;

procedure TRepoFrame.MenuZoomOutClick(Sender: TObject);
begin
  Edit.DoScaleFontDelta(False, True);
  EditChangeZoom(Edit);
end;

procedure TRepoFrame.MenuZoomResetClick(Sender: TObject);
begin
  Edit.OptScaleFont := 0;
  FEditOld.OptScaleFont := 0;
  EditorMetricsChanged;
end;

procedure TRepoFrame.MenuFontClick(Sender: TObject);
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

procedure TRepoFrame.ApplyEditorFont(AFont: TFont);
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
procedure TRepoFrame.CheckGitVersion;
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
  features follow whether gh is there now. APage is the page it opens
  on. }
procedure TRepoFrame.OpenSettings(APage: TSettingsPage);
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
    V.EditorCommand := App.Settings.EditorCommand;
    V.TerminalCommand := App.Settings.TerminalCommand;
    V.GitPath := App.Settings.GitPath;
    V.AutoFetch := App.Settings.AutoFetch;
    V.AutoFetchMinutes := App.Settings.AutoFetchMinutes;
    V.GhPath := App.Settings.GhPath;
    V.GitHubEnabled := App.Settings.GitHubEnabled;
    V.CloneSiblings := App.Settings.CloneSiblings;
    V.AIEnabled := App.Settings.AIEnabled;
    V.Agent := AgentOfKey(App.Settings.AIAgent);
    V.AgentPaths[gaClaude] := App.Settings.ClaudePath;
    V.AgentModels[gaClaude] := App.Settings.ClaudeModel;
    V.AgentPaths[gaCopilot] := App.Settings.CopilotPath;
    V.AgentModels[gaCopilot] := App.Settings.CopilotModel;
    Corner := EditorPanel.ClientToScreen(Point(EditorPanel.ClientWidth -
      Scale96ToForm(Margin), EditorPanel.ClientHeight - Scale96ToForm(Margin)));
    if EditSettings(F, V, @PreviewSettings, App.Lexers, Edit, Corner, APage) then
    begin
      PreviewSettings(F, V.Theme, V.TabSize);
      App.Settings.EditorCommand := V.EditorCommand;
      App.Settings.TerminalCommand := V.TerminalCommand;
      App.Settings.CloneSiblings := V.CloneSiblings;
      App.Settings.AutoFetch := V.AutoFetch;
      App.Settings.AutoFetchMinutes := V.AutoFetchMinutes;
      App.Settings.AIEnabled := V.AIEnabled;
      App.Settings.AIAgent := AgentCommands[V.Agent];
      App.Settings.ClaudePath := V.AgentPaths[gaClaude];
      App.Settings.ClaudeModel := V.AgentModels[gaClaude];
      App.Settings.CopilotPath := V.AgentPaths[gaCopilot];
      App.Settings.CopilotModel := V.AgentModels[gaCopilot];
      FindAgentCli;
      if not AIAvailable then
      begin
        AbandonMessageJob;
        AbandonAIReview;
      end;
      UpdateCommitState;
      if (V.GitPath <> App.Settings.GitPath) or (V.GhPath <> App.Settings.GhPath) or
        (V.GitHubEnabled <> App.Settings.GitHubEnabled) then
      begin
        App.Settings.GitPath := V.GitPath;
        App.Settings.GhPath := V.GhPath;
        App.Settings.GitHubEnabled := V.GitHubEnabled;
        SetGitExe(App.Settings.GitPath);
        FindForge;
        UpdateForgeItems;
        if not Assigned(FForge) then
        begin
          { What the forge that is gone had found. }
          AbandonPullJob;
          FPullKey := '';
          FHasPull := False;
          FPulls := nil;
          FPullError := '';
          FReviewPulls := nil;
          FSummary.SetReviewPulls(nil);
          FPullLogin := '';
          AbandonForgeJob;
          FForgeMine := nil;
          FForgeReview := nil;
          FForgeLogin := '';
          FForgeError := '';
          UpdateForgePage;
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

procedure TRepoFrame.MenuSettingsClick(Sender: TObject);
begin
  OpenSettings(pgEditor);
end;

{ About Gittan is the settings' last page. }
procedure TRepoFrame.MenuAboutClick(Sender: TObject);
begin
  OpenSettings(pgAbout);
end;

procedure TRepoFrame.PreviewSettings(AFont: TFont; ATheme, ATabSize: integer);
begin
  if not Edit.Font.IsEqual(AFont) then
    ApplyEditorFont(AFont);
  if ATheme <> FSyntaxTheme then
    SetSyntaxTheme(ATheme);
  ApplyTabSize(ATabSize);
end;

{ A tab ASize characters wide in both editors; the wrap follows, since
  the width of a line changes with it. }
procedure TRepoFrame.ApplyTabSize(ASize: integer);
begin
  if ASize = FTabSize then
    Exit;
  FTabSize := ASize;
  Edit.OptTabSize := ASize;
  FEditOld.OptTabSize := ASize;
  Edit.Update(True);
  FEditOld.Update(True);
end;

{ The forge, GitHub through gh: gh by the path the settings give, else
  as found on ToolSearchPath; none while the GitHub features are turned
  off, which hides them as a missing gh does. A forge already made with
  the same tool is kept. }
procedure TRepoFrame.FindForge;
var
  Cli: string;
begin
  if not App.Settings.GitHubEnabled then
    Cli := ''
  else if App.Settings.GhPath <> '' then
    Cli := App.Settings.GhPath
  else
    Cli := FindTool(TGittanGitHubForge.CliName);
  if Assigned(FForge) and (FForge.Cli = Cli) then
    Exit;
  FreeAndNil(FForge);
  if Cli <> '' then
    FForge := TGittanGitHubForge.Create(Cli);
end;

{ The forge's name, empty without one (when what is named after it is
  hidden). }
function TRepoFrame.ForgeName: string;
begin
  if Assigned(FForge) then
    Result := FForge.Name
  else
    Result := '';
end;

{ Shows the menu items that need the forge when there is one, named
  after it, and hides them otherwise. The Compare With menu and a
  commit's menu are built when they open and look themselves. }
procedure TRepoFrame.UpdateForgeItems;
var
  i: integer;
begin
  for i := 0 to High(FForgeItems) do
  begin
    FForgeItems[i].Visible := Assigned(FForge);
    if FForgeCaptions[i] <> '' then
      FForgeItems[i].Caption := Format(FForgeCaptions[i], [ForgeName]);
  end;
  if FReviewItem <> nil then
    FReviewItem.Enabled := Assigned(FForge);
  { The Pull Requests and forge pages need the forge too: their rows,
    their menu items, the names they show, and the page itself when the
    forge goes while it shows. }
  if FPullsItem <> nil then
    FPullsItem.Visible := Assigned(FForge);
  if FForgeItem <> nil then
  begin
    FForgeItem.Visible := Assigned(FForge);
    FForgeItem.Caption := Format(rsForgeMenu, [ForgeName]);
  end;
  if FSideNav <> nil then
  begin
    FSideNav.SetRowVisible(navPulls, Assigned(FForge));
    FSideNav.SetRowVisible(navForge, Assigned(FForge));
    FSideNav.SetRowCaption(navForge, ForgeName);
  end;
  if FPullPage <> nil then
    FPullPage.SetForge(ForgeName);
  if FForgePage <> nil then
    FForgePage.SetForge(ForgeName);
  if FSummary <> nil then
    FSummary.ForgeName := ForgeName;
  if not Assigned(FForge) and (FView in [gvPulls, gvForge]) then
    ShowSummary;
end;

procedure TRepoFrame.MenuWrapClick(Sender: TObject);
begin
  FWordWrap := not FWordWrap;
  FWrapItem.Checked := FWordWrap;
  ApplyWrap;
end;

{ View > Folding: the command in the item's Tag, on the ranges of the
  lexer where FoldingShown. The shortcuts reach here in the other views
  too. }
procedure TRepoFrame.MenuFoldClick(Sender: TObject);
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
procedure TRepoFrame.HeaderMenu(Sender: TObject; const AScreenRect: TRect);
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

procedure TRepoFrame.ViewPopupPick(Sender: TObject; AIndex: integer);
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

procedure TRepoFrame.ViewMenuClick(Sender: TObject);
begin
  FFoldMenu.Enabled := FoldingShown and Edit.Visible;
end;

procedure TRepoFrame.MenuOnlyChangesClick(Sender: TObject);
begin
  FOnlyChanges := not FOnlyChanges;
  FOnlyChangesItem.Checked := FOnlyChanges;
  FExpanded := nil;
  RebuildIfChanges;
end;

procedure TRepoFrame.MenuContextLinesClick(Sender: TObject);
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
procedure TRepoFrame.MenuSyntaxThemeClick(Sender: TObject);
begin
  SetSyntaxTheme(TMenuItem(Sender).Tag);
end;

procedure TRepoFrame.SetSyntaxTheme(ATheme: integer);
var
  i: integer;
begin
  FSyntaxTheme := ATheme;
  for i := 0 to High(FThemeItems) do
    FThemeItems[i].Checked := i = FSyntaxTheme;
  ApplyTheme;
end;

procedure TRepoFrame.MenuSideBySideClick(Sender: TObject);
begin
  FSideBySide := not FSideBySide;
  FSideItem.Checked := FSideBySide;
  RebuildIfChanges;
  ApplyLayout;
end;

{ Whitespace changes are left out by git itself (-w on every diff), so
  the counts, the tree and the views all follow: the repository is
  loaded again and the view restored, as on a refresh. }
procedure TRepoFrame.MenuIgnoreSpaceClick(Sender: TObject);
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
procedure TRepoFrame.MenuNextFileClick(Sender: TObject);
begin
  StepFile(True);
end;

procedure TRepoFrame.MenuPrevFileClick(Sender: TObject);
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
function TRepoFrame.StepFile(ANext: boolean): boolean;
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
function TRepoFrame.NeighbourFile(ANext: boolean): TTreeNode;
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
procedure TRepoFrame.EditMouseWheel(Sender: TObject; Shift: TShiftState;
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
procedure TRepoFrame.SetWheelScroll(AOn: boolean);
begin
  Edit.OptMouseWheelScrollVert := AOn;
  FEditOld.OptMouseWheelScrollVert := AOn;
end;

procedure TRepoFrame.SetOverscroll(AValue: integer);
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
procedure TRepoFrame.ShowFileEnd;
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

procedure TRepoFrame.OverscrollTimerTimer(Sender: TObject);
begin
  SetOverscroll(0);
end;

{ The pill that shows the pull: it comes in from the edge of the text the
  pull is at, rising from the bottom for the next file or descending from
  the top for the previous, as the pull grows, and fills from the left,
  until the file is pulled in. The canvas is clipped to the text
  rectangle so the pill comes in from under its edge. }
procedure TRepoFrame.EditDrawEditor(Sender: TObject; C: TCanvas; const ARect: TRect);
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
procedure TRepoFrame.BuildPopups;
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

  { An item (a separator with no caption) shown only while there is a
    forge, its caption AFormat with the forge's name in place of %s. }
  function AddForgeItem(APopup: TPopupMenu; const AFormat: string;
    AClick: TNotifyEvent): TMenuItem;
  begin
    if AFormat = '' then
      Result := AddItem(APopup, '-', nil)
    else
      Result := AddItem(APopup, Format(AFormat, [ForgeName]), AClick);
    SetLength(FForgeItems, Length(FForgeItems) + 1);
    FForgeItems[High(FForgeItems)] := Result;
    SetLength(FForgeCaptions, Length(FForgeCaptions) + 1);
    FForgeCaptions[High(FForgeCaptions)] := AFormat;
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
  AddForgeItem(FFilePopup, rsOpenOnForge, @MenuOpenOnForgeClick);
  AddForgeItem(FFilePopup, rsCopyForgeUrl, @MenuCopyForgeUrlClick);
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
  FLfsTrackMenu := AddItem(FFilePopup, rsLfsTrackMenu, nil);
  FLfsUntrackMenu := AddItem(FFilePopup, rsLfsUntrackMenu, nil);
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
  AddForgeItem(FEditPopup, '', nil);
  FForgeEditItem := AddForgeItem(FEditPopup, rsOpenOnForge, @MenuOpenLineOnForgeClick);
  AddForgeItem(FEditPopup, rsCopyForgeUrl, @MenuCopyLineForgeUrlClick);
  FForgeCommitItem := AddForgeItem(FEditPopup, rsOpenCommitOnForge,
    @MenuOpenCommitOnForgeClick);
  { Shown for a commit whose summary names an issue (EditPopupPopup). }
  FForgeIssueItem := AddItem(FEditPopup, Format(rsOpenIssueOnForge, [0, ForgeName]),
    @MenuOpenIssueOnForgeClick);
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
  AddForgeItem(FStatusPopup, '', nil);
  FOpenPullItem := AddForgeItem(FStatusPopup, rsOpenPull, @MenuOpenPullClick);
  FCopyPullItem := AddForgeItem(FStatusPopup, rsCopyPullUrl, @MenuCopyPullUrlClick);
  FStatus.PopupMenu := FStatusPopup;
  UpdateForgeItems;
end;

procedure TRepoFrame.FilePopupPopup(Sender: TObject);
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
  FillLfsMenus(FContextPath);
  FTickSepItem.Visible := (FFilePopup.PopupComponent = FileTree) and CommitChoosing and
    (FChoosableCount > 0);
  FTickAllItem.Visible := FTickSepItem.Visible;
  FUntickAllItem.Visible := FTickSepItem.Visible;
  FTickAllItem.Enabled := (FChosenCount < FChoosableCount) and (FCommitJob = nil);
  FUntickAllItem.Enabled := (FChosenCount > 0) and (FCommitJob = nil);
end;

procedure TRepoFrame.SummaryContextFile(Sender: TObject; const APath: string;
  const AScreenPos: TPoint);
begin
  FContextPath := APath;
  FContextFromSummary := True;
  FFilePopup.PopUp(AScreenPos.X, AScreenPos.Y);
end;

function TRepoFrame.ContextFullPath: string;
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
procedure TRepoFrame.SummaryBranchClick(Sender: TObject; const AScreenRect: TRect);
begin
  ShowBranchList(blSwitch, AScreenRect);
end;

procedure TRepoFrame.ShowBranchList(AMode: TGittanBranchListMode; const AScreenRect: TRect);
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
procedure TRepoFrame.BranchPopupPick(Sender: TObject; AIndex: integer);
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
procedure TRepoFrame.SwitchBranch(const ABranch: string; ADetach: boolean);
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

procedure TRepoFrame.MenuCopyPathClick(Sender: TObject);
begin
  if FContextPath <> '' then
    Clipboard.AsText := ContextFullPath;
end;

procedure TRepoFrame.MenuCopyRelativePathClick(Sender: TObject);
begin
  if FContextPath <> '' then
    Clipboard.AsText := FContextPath;
end;

procedure TRepoFrame.MenuRevealClick(Sender: TObject);
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
procedure TRepoFrame.EditPopupPopup(Sender: TObject);
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
  FForgeEditItem.Enabled := (FRepo.Root <> '') and (FCurrentPath <> '');
  FForgeCommitItem.Enabled := FPopupHash <> '';
  FForgeIssueItem.Visible := Assigned(FForge) and (FPopupIssue > 0);
  FForgeIssueItem.Caption := Format(rsOpenIssueOnForge, [FPopupIssue, ForgeName]);
  FResolveEditItem.Visible := CanResolveBlocks;
  FResolveEditItem.Enabled := (FPopupEd = Edit) and (ConflictAtRow(FPopupRow) >= 0);
end;

{ The commit the row's blame or history gives, shown against its
  parent, as a click on the blame band does. }
procedure TRepoFrame.MenuShowCommitClick(Sender: TObject);
begin
  if FPopupHash = '' then
    Exit;
  if (FView = gvHistory) and (FPopupKey >= 0) then
    ShowHistoryCommit(FPopupKey)
  else
    ShowBlameCommit(FPopupHash);
end;

procedure TRepoFrame.MenuCopyHashClick(Sender: TObject);
begin
  if FPopupHash <> '' then
    Clipboard.AsText := FPopupHash;
end;

procedure TRepoFrame.MenuEditCopyClick(Sender: TObject);
begin
  FPopupEd.DoCommand(cCommand_ClipboardCopy, TATCommandInvoke.MenuContext);
end;

procedure TRepoFrame.MenuEditSelectAllClick(Sender: TObject);
begin
  FPopupEd.DoCommand(cCommand_SelectAll, TATCommandInvoke.MenuContext);
end;

{ The address of ATarget's page on the forge: the forge's tool only
  prints it. A failure (no remote on the forge, say) is told in the
  status bar instead of going unseen. }
function TRepoFrame.ForgeUrl(const ATarget: TGittanWebTarget; out AUrl: string): boolean;
var
  Err: string;
begin
  AUrl := '';
  Result := False;
  if not Assigned(FForge) or (FRepo.Root = '') then
    Exit;
  Result := FForge.WebUrl(FRepo.Root, ATarget, AUrl, Err);
  if not Result then
  begin
    Err := Trim(Err);
    if Pos(LineEnding, Err) > 0 then
      Err := Copy(Err, 1, Pos(LineEnding, Err) - 1);
    StatusNote(Format(rsForgeFailed, [FForge.CliName, Err]), True);
  end;
end;

procedure TRepoFrame.OpenOnForge(const ATarget: TGittanWebTarget);
var
  Url: string;
begin
  if ForgeUrl(ATarget, Url) then
    OpenURL(Url);
end;

{ A file at ALine when it is above 0, in the version the view shows:
  the right commit of a range (what a blame click or Compare With >
  Other set), else the branch, since the work tree has no page. }
function TRepoFrame.FileWebTarget(const APath: string; ALine: integer): TGittanWebTarget;
var
  OldRef, NewRef: string;
begin
  FRepo.DiffSides(OldRef, NewRef);
  Result := FileTarget(APath, ALine, NewRef, FBranch);
end;

{ The line of the shown file that row ARow of AEd holds, 0 when the row
  is not one of the new side (a gap, a filler, a deleted line, the old
  side, or a history row, whose lines are of several versions). }
function TRepoFrame.FileLineOfRow(AEd: TATSynEdit; ARow: integer): integer;
begin
  if AEd = Edit then
    Result := FileLineOfRow(ARow)
  else
    Result := 0;
end;

procedure TRepoFrame.MenuOpenOnForgeClick(Sender: TObject);
begin
  if FContextPath <> '' then
    OpenOnForge(FileWebTarget(FContextPath, 0));
end;

procedure TRepoFrame.MenuCopyForgeUrlClick(Sender: TObject);
var
  Url: string;
begin
  if (FContextPath <> '') and ForgeUrl(FileWebTarget(FContextPath, 0), Url) then
    Clipboard.AsText := Url;
end;

procedure TRepoFrame.MenuOpenLineOnForgeClick(Sender: TObject);
begin
  if FCurrentPath <> '' then
    OpenOnForge(FileWebTarget(FCurrentPath, FileLineOfRow(FPopupEd, FPopupRow)));
end;

procedure TRepoFrame.MenuCopyLineForgeUrlClick(Sender: TObject);
var
  Url: string;
begin
  if (FCurrentPath <> '') and
    ForgeUrl(FileWebTarget(FCurrentPath, FileLineOfRow(FPopupEd, FPopupRow)), Url) then
    Clipboard.AsText := Url;
end;

procedure TRepoFrame.MenuOpenCommitOnForgeClick(Sender: TObject);
begin
  if FPopupHash <> '' then
    OpenOnForge(CommitTarget(FPopupHash));
end;

{ A number opens the issue or the pull request. }
procedure TRepoFrame.MenuOpenIssueOnForgeClick(Sender: TObject);
begin
  if FPopupIssue > 0 then
    OpenOnForge(IssueTarget(FPopupIssue));
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
procedure TRepoFrame.MenuOpenInEditorClick(Sender: TObject);
begin
  if FContextPath = '' then
    Exit;
  if Trim(App.Settings.EditorCommand) = '' then
    OpenDocument(ContextFullPath)
  else
    RunCommandWith(App.Settings.EditorCommand, [ContextFullPath]);
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

procedure TRepoFrame.ShowCommitGraph(const AFilter: string);
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

procedure TRepoFrame.GraphMore(Sender: TObject);
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

procedure TRepoFrame.GraphPathCommits(Sender: TObject; const APath: string;
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
procedure TRepoFrame.MenuFileHistoryClick(Sender: TObject);
begin
  if FContextPath <> '' then
    ShowCommitGraph(PathFilter(FContextPath))
  else if FContextFolder <> '' then
    ShowCommitGraph(PathFilter(FContextFolder));
end;

{ Go > File History: the same for the shown file. }
procedure TRepoFrame.MenuGoFileHistoryClick(Sender: TObject);
begin
  if FCurrentPath <> '' then
    ShowCommitGraph(PathFilter(FCurrentPath));
end;

procedure TRepoFrame.MenuCommitGraphClick(Sender: TObject);
begin
  ShowCommitGraph;
end;

{ The summary shows the commit, from any page: its card names it and
  leads back to the working tree. }
procedure TRepoFrame.GraphPick(Sender: TObject; const AHash: string);
begin
  ShowBlameCommit(AHash);
  ShowSummary;
end;

{ A click on a commit in the summary of a clean tree shows it against its
  parent, as a pick from the commit graph does. }
procedure TRepoFrame.SummarySelectCommit(Sender: TObject; const AHash: string);
begin
  ShowBlameCommit(AHash);
end;

{ The status bar's parts: the branch drops the branch list up from it,
  as in the summary; the track with the ahead/behind counts drops up
  pull, push, fetch and the commit graph; the transport buttons take
  their step (UpdateStatusTransport); the pull request drops its list;
  the name and the file count go back to the summary. }
procedure TRepoFrame.StatusPartClick(Sender: TObject; APart: TGittanStatusPart;
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
procedure TRepoFrame.StatusStepClick(AStep: TStatusStep; const AScreenRect: TRect);
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

procedure TRepoFrame.MenuCopyBranchClick(Sender: TObject);
begin
  if FBranch <> '' then
    Clipboard.AsText := FBranch;
end;

procedure TRepoFrame.MenuCopyRepoPathClick(Sender: TObject);
begin
  if FRepo.Root <> '' then
    Clipboard.AsText := FRepo.Root;
end;

procedure TRepoFrame.MenuOpenTerminalClick(Sender: TObject);
begin
  OpenTerminal('');
end;

{ The shell line that runs ACommand in ARoot and keeps the terminal
  open after it, for a terminal's -e. }
function ShellLineIn(const ARoot, ACommand: string): string;
begin
  Result := 'cd ' + gittan.cli.ShellQuote(ARoot) + ' && ' + ACommand + '; exec ${SHELL:-sh}';
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
  differently, and given sh -c and the line as arguments of their own:
  after -- for gnome-terminal, whose -e takes one string, -x for
  xfce4-terminal, and -e for the rest (x-terminal-emulator takes -e as
  xterm does, whichever terminal it is). }
procedure TRepoFrame.OpenTerminal(const ACommand: string);
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
  if Trim(App.Settings.TerminalCommand) <> '' then
  begin
    if ACommand = '' then
      RunCommandWith(App.Settings.TerminalCommand, [FRepo.Root])
    else
      RunCommandWith(App.Settings.TerminalCommand, [FRepo.Root, ACommand]);
    Exit;
  end;
  {$IFDEF DARWIN}
  if ACommand = '' then
    RunDetached('open', ['-a', 'Terminal', FRepo.Root])
  else
  begin
    { The line goes into an AppleScript string: its backslashes and
      quotes escaped. }
    Script := 'cd ' + gittan.cli.ShellQuote(FRepo.Root) + ' && ' + ACommand;
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
      else if T = 'gnome-terminal' then
        RunDetached(T, ['--', 'sh', '-c', ShellLineIn(FRepo.Root, ACommand)],
          FRepo.Root)
      else if T = 'xfce4-terminal' then
        RunDetached(T, ['-x', 'sh', '-c', ShellLineIn(FRepo.Root, ACommand)],
          FRepo.Root)
      else
        RunDetached(T, ['-e', 'sh', '-c', ShellLineIn(FRepo.Root, ACommand)],
          FRepo.Root);
      Exit;
    end;
  {$ENDIF}
  {$ENDIF}
end;

{ Tools > Install CLI Command: a gittan command for the terminal that
  starts this executable (see gittan.cli). }
procedure TRepoFrame.MenuInstallCliClick(Sender: TObject);
var
  Msg: string;
begin
  if InstallCli(Application.ExeName, Msg) then
    MessageDlg(Msg, mtInformation, [mbOK], 0)
  else
    MessageDlg(Msg, mtError, [mbOK], 0);
end;

procedure TRepoFrame.MenuUninstallCliClick(Sender: TObject);
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
procedure TRepoFrame.ToolsMenuClick(Sender: TObject);
begin
  FUninstallCliItem.Enabled := CliInstalled;
end;

{ ---------------------------------------------------------------------------
  Comparing against another commit
  ---------------------------------------------------------------------------
  View > Compare With lists the branches and tags, then the snapshots of
  the repository; the chosen one becomes the repository's Base, and every
  diff, count and the watcher follow it. The list is rebuilt with the
  repository, from the refs its snapshot read off the main thread. A
  snapshot item carries Tag 1: the base is then compared with WholeTree,
  since the snapshot holds the untracked files. }
procedure TRepoFrame.RebuildCompareMenu;
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
      Refs.AddStrings(FRefs);
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
  if Assigned(FForge) then
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

procedure TRepoFrame.MenuCompareClick(Sender: TObject);
begin
  SetBase(TMenuItem(Sender).Hint, TMenuItem(Sender).Tag = 1);
end;

procedure TRepoFrame.MenuCompareOtherClick(Sender: TObject);
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
  The forge is on the network, so the job runs in a thread: once per
  repository and branch, and again on View > Refresh (AForce). A job
  still running for something else is abandoned like a blame job. }
procedure TRepoFrame.StartPullJob(AForce: boolean; AKeep: boolean);
var
  Key: string;
begin
  if not Assigned(FForge) then
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
    FReviewPulls := nil;
    FSummary.SetReviewPulls(nil);
  end;
  FPullJob := FForge.PullJob(FRepo.Root, FBranch, FPullLogin);
  FPullJob.OnDone := @PullJobDone;
  FPullJob.Start;
  if not AKeep then
    RebuildPullMenu;
  UpdatePullPage;
end;

{ A poll waits for a job still running; that job's end sets the timer
  again. }
procedure TRepoFrame.PullTimerTimer(Sender: TObject);
begin
  FPullTimer.Enabled := False;
  if (FRepo.Root = '') or (FPullJob <> nil) then
    Exit;
  StartPullJob(True, True);
end;

procedure TRepoFrame.AbandonPullJob;
begin
  { No job, no poll: the next finished job starts the timer again. }
  FPullTimer.Enabled := False;
  if FPullJob = nil then
    Exit;
  FPullJob.Stop(False);
  FBlameZombies.Add(FPullJob);
  FPullJob := nil;
end;

procedure TRepoFrame.PullJobDone(Sender: TObject);
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
  FReviewPulls := Job.ReviewPulls;
  FPullLogin := Job.Login;
  FSummary.SetReviewPulls(FReviewPulls);
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
procedure TRepoFrame.RebuildPullMenu;
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
procedure TRepoFrame.MenuComparePullClick(Sender: TObject);
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
procedure TRepoFrame.ComparePull(const APull: TGittanPullRequest);
begin
  if FRepo.Root = '' then
    Exit;
  StartPullFetch(APull.Number, FRepo.RemoteFor(APull.Repo), APull.BaseRef);
end;

procedure TRepoFrame.StartPullFetch(ANumber: integer; const ARemote, ABaseRef: string);
begin
  if (FRepo.Root = '') or not Assigned(FForge) or (FRemoteJob <> nil) or
    (FCommitJob <> nil) then
    Exit;
  { It would fight the background fetch over the remote's refs too. }
  if FAutoFetchJob <> nil then
  begin
    FPendingRemote := True;
    FPendingKind := rkFetchPull;
    FPendingArg := IntToStr(ANumber);
    FPendingRemoteName := ARemote;
    FPendingBranch := ABaseRef;
    FStatus.ShowMessage(rsWaitingForFetch, stNormal, 0);
    Exit;
  end;
  FNoticeHook := False;
  FRemoteHead := '';
  FRemoteAhead := FAhead;
  FRemoteJob := TGittanRemoteJob.Create(FRepo.Root, rkFetchPull, pmAuto, IntToStr(ANumber),
    ARemote);
  FRemoteJob.Branch := ABaseRef;
  FRemoteJob.PullRef := FForge.PullRef(ANumber);
  FRemoteJob.OnDone := @RemoteJobDone;
  FRemoteJob.OnOutput := @RemoteJobOutput;
  FRemoteJob.Start;
  FStatus.ShowMessage(Format(rsFetchingPull, [ANumber]), stNormal, 0);
  FNoticeTimer.Enabled := True;
  UpdateRemoteItems;
  UpdateCommitState;
end;

procedure TRepoFrame.PullFetchDone(AJob: TGittanRemoteJob);
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
procedure TRepoFrame.PullChipClick(const AScreenRect: TRect);
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
    AddAction(paOpen, Format(rsOpenPullOnForge, [ForgeName]), '');
    AddAction(paCopy, rsCopyPullLink, '');
  end;
  AddAction(paList, rsAllPulls, '');
  FPullPopup.Popup(AScreenRect);
end;

procedure TRepoFrame.PullPopupPick(Sender: TObject; AIndex: integer);
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

procedure TRepoFrame.StatusPopupPopup(Sender: TObject);
begin
  FOpenPullItem.Enabled := FHasPull and (FPull.Url <> '');
  FCopyPullItem.Enabled := FHasPull and (FPull.Url <> '');
end;

procedure TRepoFrame.MenuOpenPullClick(Sender: TObject);
begin
  if FHasPull and (FPull.Url <> '') then
    OpenURL(FPull.Url);
end;

function TRepoFrame.PullChecks(const APull: TGittanPullRequest; out ACount: integer): TGittanStatusTone;
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
function TRepoFrame.PullHint(const APull: TGittanPullRequest): string;

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
  Result := Result + LineEnding + HintLink + ' ' + Format(rsPullHintOpen, [ForgeName]);
end;

procedure TRepoFrame.MenuCopyPullUrlClick(Sender: TObject);
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
procedure TRepoFrame.MenuTakeSnapshotClick(Sender: TObject);
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

function TRepoFrame.SnapshotsFileName: string;
begin
  Result := IndexCacheDir + MD5Print(MD5String(FRepo.Root)) + '.snapshots';
end;

procedure TRepoFrame.LoadSnapshots;
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

procedure TRepoFrame.SaveSnapshots;
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
function TRepoFrame.BaseLabel: string;
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
procedure TRepoFrame.SetBase(const ARef: string; ASnapshot: boolean);
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
