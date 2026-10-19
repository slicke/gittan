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
  if FSettings.FontName <> '' then
    Edit.Font.Name := FSettings.FontName;
  if FSettings.FontSize > 0 then
    Edit.Font.Size := FSettings.FontSize;
  FEditOld.Font.Assign(Edit.Font);
  if FSettings.Zoom > 0 then
  begin
    Edit.OptScaleFont := FSettings.Zoom;
    FEditOld.OptScaleFont := FSettings.Zoom;
  end;
  { The window where it was, if that is still on a screen. }
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
  if FSettings.TreeWidth > 80 then
    FTreePanel.Width := FSettings.TreeWidth;
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
  FSettings.TreeWidth := FTreePanel.Width;
  FSettings.RepoFilesOpen := FRepoHeader.Expanded;
  FSettings.SubmodulesOpen := FSubHeader.Expanded;
  FSettings.CommitOpen := FCommitHeader.Expanded;
  StopCommitJob(True);
  StopRemoteJob(True);
  SaveCommitDraft;
  FSettings.FontName := Edit.Font.Name;
  FSettings.FontSize := Edit.Font.Size;
  FSettings.Zoom := Edit.OptScaleFont;
  FSettings.WordWrap := FWordWrap;
  FSettings.OnlyChanges := FOnlyChanges;
  FSettings.ContextLines := FContextLines;
  FSettings.SideBySide := FSideBySide;
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
var
  Needle, S: UnicodeString;
  Matches: array of TPoint;
  Count, i, p, Idx: integer;
  Start: TPoint;
  Caret: TATCaretItem;

  function Compare(const A, B: TPoint): integer;
  begin
    Result := A.Y - B.Y;
    if Result = 0 then
      Result := A.X - B.X;
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
    { A hidden line of the change view cannot be shown; a folded one is
      unfolded when the match is in it. }
    if not FoldingShown and Edit.IsLineFolded(i) then
      Continue;
    S := UnicodeLowerCase(Edit.Strings.Lines[i]);
    p := Pos(Needle, S);
    while p > 0 do
    begin
      if Count = Length(Matches) then
        SetLength(Matches, Count * 2);
      Matches[Count] := Point(p - 1, i);
      Inc(Count);
      if Count >= MaxMatches then
        Break;
      p := Pos(Needle, S, p + 1);
    end;
    if Count >= MaxMatches then
      Break;
  end;
  if Count = 0 then
  begin
    FFindBar.SetMatches(0, 0);
    Exit;
  end;
  Caret := Edit.Carets[0];
  Start := Point(Caret.PosX, Caret.PosY);
  if (Caret.EndY >= 0) and (Compare(Point(Caret.EndX, Caret.EndY), Start) < 0) then
    Start := Point(Caret.EndX, Caret.EndY);
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
  { The caret lands after the match, the selection covers it. }
  Edit.DoGotoPos(Point(Matches[Idx].X + Length(Needle), Matches[Idx].Y), Matches[Idx],
    10, 5, True, FoldAction);
  SyncOldSide;
  FFindBar.SetMatches(Idx + 1, Count);
end;

{ ---------------------------------------------------------------------------
  View options
  --------------------------------------------------------------------------- }
procedure TForm1.MenuZoomInClick(Sender: TObject);
begin
  Edit.DoScaleFontDelta(True, True);
end;

procedure TForm1.MenuZoomOutClick(Sender: TObject);
begin
  Edit.DoScaleFontDelta(False, True);
end;

procedure TForm1.MenuZoomResetClick(Sender: TObject);
begin
  Edit.OptScaleFont := 0;
  FEditOld.OptScaleFont := 0;
  UpdateNumberWidth(Edit);
  UpdateNumberWidth(FEditOld);
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
  Edit.Update(True);
  FEditOld.Update(True);
  UpdateNumberWidth(Edit);
  UpdateNumberWidth(FEditOld);
end;

{ The settings dialog previews the font and the theme in the editor and
  puts back the old ones when it is cancelled; the commands are saved with
  the rest when the window closes. }
procedure TForm1.MenuSettingsClick(Sender: TObject);
const
  Margin = 24;
var
  OldFont, F: TFont;
  OldTheme, Theme: integer;
  EditorCmd, TerminalCmd: string;
  Corner: TPoint;
begin
  OldFont := TFont.Create;
  F := TFont.Create;
  try
    OldFont.Assign(Edit.Font);
    F.Assign(Edit.Font);
    OldTheme := FSyntaxTheme;
    Theme := FSyntaxTheme;
    EditorCmd := FSettings.EditorCommand;
    TerminalCmd := FSettings.TerminalCommand;
    Corner := EditorPanel.ClientToScreen(Point(EditorPanel.ClientWidth -
      Scale96ToForm(Margin), EditorPanel.ClientHeight - Scale96ToForm(Margin)));
    if EditSettings(F, Theme, EditorCmd, TerminalCmd, @PreviewSettings, FLexers,
      Edit, Corner) then
    begin
      PreviewSettings(F, Theme);
      FSettings.EditorCommand := EditorCmd;
      FSettings.TerminalCommand := TerminalCmd;
    end
    else
      PreviewSettings(OldFont, OldTheme);
  finally
    F.Free;
    OldFont.Free;
  end;
end;

procedure TForm1.PreviewSettings(AFont: TFont; ATheme: integer);
begin
  if not Edit.Font.IsEqual(AFont) then
    ApplyEditorFont(AFont);
  if ATheme <> FSyntaxTheme then
    SetSyntaxTheme(ATheme);
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
{ The caret goes to the file's first (or last) change; a file without
  any, such as an image or a binary file, is left as it is, since
  GoToChange would step on to the file after it. }
procedure TForm1.MenuNextFileClick(Sender: TObject);
begin
  if StepFile(True) and (Length(ChangeBlocks) > 0) then
    GoToChange(True);
end;

procedure TForm1.MenuPrevFileClick(Sender: TObject);
begin
  if StepFile(False) and (Length(ChangeBlocks) > 0) then
    GoToChange(False);
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
  if FHasGitHubCli then
  begin
    AddItem(FFilePopup, rsOpenOnGitHub, @MenuOpenOnGitHubClick);
    AddItem(FFilePopup, rsCopyGitHubUrl, @MenuCopyGitHubUrlClick);
  end;
  Item := TMenuItem.Create(FFilePopup);
  Item.Caption := '-';
  FFilePopup.Items.Add(Item);
  FResolveMineItem := AddItem(FFilePopup, rsResolveMineItem, @MenuResolveMineClick);
  FResolveTheirsItem := AddItem(FFilePopup, rsResolveTheirsItem, @MenuResolveTheirsClick);
  FMarkResolvedItem := AddItem(FFilePopup, rsMarkResolvedItem, @MenuMarkResolvedClick);
  Item := TMenuItem.Create(FFilePopup);
  Item.Caption := '-';
  FFilePopup.Items.Add(Item);
  { Filled with the patterns for the file when the menu pops up. }
  FIgnoreMenu := AddItem(FFilePopup, rsAddToIgnore, nil);
  FExcludeMenu := AddItem(FFilePopup, rsAddToExclude, nil);
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
  FShowCommitItem := AddItem(FEditPopup, rsShowCommit, @MenuShowCommitClick);
  FCopyHashItem := AddItem(FEditPopup, rsCopyHash, @MenuCopyHashClick);
  if FHasGitHubCli then
  begin
    Item := TMenuItem.Create(FEditPopup);
    Item.Caption := '-';
    FEditPopup.Items.Add(Item);
    FGitHubEditItem := AddItem(FEditPopup, rsOpenOnGitHub, @MenuOpenLineOnGitHubClick);
    AddItem(FEditPopup, rsCopyGitHubUrl, @MenuCopyLineGitHubUrlClick);
    FGitHubCommitItem := AddItem(FEditPopup, rsOpenCommitOnGitHub,
      @MenuOpenCommitOnGitHubClick);
    FGitHubIssueItem := AddItem(FEditPopup, Format(rsOpenIssueOnGitHub, [0]),
      @MenuOpenIssueOnGitHubClick);
  end;
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
  if FHasGitHubCli then
  begin
    Item := TMenuItem.Create(FStatusPopup);
    Item.Caption := '-';
    FStatusPopup.Items.Add(Item);
    FOpenPullItem := AddItem(FStatusPopup, rsOpenPull, @MenuOpenPullClick);
    FCopyPullItem := AddItem(FStatusPopup, rsCopyPullUrl, @MenuCopyPullUrlClick);
  end;
  FStatus.PopupMenu := FStatusPopup;
end;

procedure TForm1.FilePopupPopup(Sender: TObject);
var
  i: integer;
  Exists: boolean;
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
  Exists := (FContextPath <> '') and FileExists(ContextFullPath);
  for i := 0 to FFilePopup.Items.Count - 1 do
    FFilePopup.Items[i].Enabled := FContextPath <> '';
  FRevealItem.Enabled := Exists;
  FOpenItem.Enabled := Exists;
  FResolveMineItem.Enabled := IsConflictPath(FContextPath);
  FResolveTheirsItem.Enabled := FResolveMineItem.Enabled;
  FMarkResolvedItem.Enabled := FResolveMineItem.Enabled;
  FillIgnoreMenus(FContextPath);
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
  the others. }
procedure TForm1.SummaryBranchClick(Sender: TObject; const AScreenRect: TRect);
var
  Local, Remote, Gone: TStringList;
  i, Slash: integer;
  Short, Detail: string;
  HasRemoteHeader: boolean;
begin
  if FRepo.Root = '' then
    Exit;
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
    if FOperation = '' then
    begin
      FBranchPopup.Add(rsBmNew);
      FBranchNames.Add(BranchNew);
      FBranchRefs.Add('');
    end;
    if FGoneToDelete.Count > 0 then
    begin
      FBranchPopup.Add(rsBmGone, IntToStr(FGoneToDelete.Count));
      FBranchNames.Add(BranchGone);
      FBranchRefs.Add('');
    end;
    FBranchPopup.AddHeader(rsBranches);
    FBranchNames.Add('');
    FBranchRefs.Add('');
    for i := 0 to Local.Count - 1 do
    begin
      if Gone.IndexOf(Local[i]) >= 0 then
        Detail := rsBranchGone
      else
        Detail := '';
      FBranchPopup.Add(Local[i], Detail, Local[i] = FBranch);
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

procedure TForm1.BranchPopupPick(Sender: TObject; AIndex: integer);
begin
  if (AIndex < 0) or (AIndex >= FBranchNames.Count) then
    Exit;
  if BranchAction(FBranchNames[AIndex]) then
    Exit;
  if (FBranchNames[AIndex] <> '') and (FBranchNames[AIndex] <> FBranch) then
    SwitchBranch(FBranchNames[AIndex]);
end;

{ The watcher is stopped meanwhile, as for a new base, and the views
  are refreshed from the new branch. Git's first line says why a
  switch was refused; the rest lists the files. }
procedure TForm1.SwitchBranch(const ABranch: string);
var
  Reason: string;
begin
  if FRepo.Root = '' then
    Exit;
  StopWatcher;
  if FRepo.Switch(ABranch) then
  begin
    FLoadError := '';
    FSummary.Notice := '';
    RefreshRepository;
  end
  else
  begin
    Reason := FRepo.Error;
    if Pos(#10, Reason) > 0 then
      Reason := Copy(Reason, 1, Pos(#10, Reason) - 1);
    if Copy(Reason, 1, 7) = 'error: ' then
      Delete(Reason, 1, 7)
    else if Copy(Reason, 1, 7) = 'fatal: ' then
      Delete(Reason, 1, 7);
    FSummary.Notice := Reason;
    ShowSummary;
  end;
  StartWatcher;
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
  if FGitHubEditItem <> nil then
    FGitHubEditItem.Enabled := (FRepo.Root <> '') and (FCurrentPath <> '');
  if FGitHubCommitItem <> nil then
    FGitHubCommitItem.Enabled := FPopupHash <> '';
  if FGitHubIssueItem <> nil then
  begin
    FGitHubIssueItem.Visible := FPopupIssue > 0;
    FGitHubIssueItem.Caption := Format(rsOpenIssueOnGitHub, [FPopupIssue]);
  end;
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
var
  Line: integer;
begin
  Result := 0;
  if (AEd <> Edit) or (ARow < 0) then
    Exit;
  case FView of
    gvFile:
      Result := ARow + 1;
    gvChanges:
      if ARow <= High(FRows) then
      begin
        Line := FRows[ARow].Line;
        if (Line >= 0) and (Line <= High(FNewNum)) then
          Result := FNewNum[Line];
      end;
  end;
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

{ Runs ACommand, words separated by spaces, with APath appended. }
procedure RunCommandWith(const ACommand, APath: string);
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
    SetLength(Args, Words.Count);
    for i := 1 to Words.Count - 1 do
      Args[i - 1] := Words[i];
    Args[High(Args)] := APath;
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
    RunCommandWith(FSettings.EditorCommand, ContextFullPath);
end;

{ The commit graph: the newest GraphLimit commits of every branch, in
  the middle of the form. A click on the status bar's ahead/behind
  counts opens it, as View > Commit Graph does; picking a commit shows
  it against its parent, as a click on a blame band does. }
const
  GraphLimit = 500;

procedure TForm1.ShowCommitGraph;
var
  Commits: TGittanGraphCommits;
begin
  if FRepo.Root = '' then
    Exit;
  if FGraph.Visible then
  begin
    FGraph.Close;
    Exit;
  end;
  Screen.Cursor := crHourGlass;
  try
    FRepo.GraphCommits(Commits, GraphLimit);
  finally
    Screen.Cursor := crDefault;
  end;
  FGraph.Popup(Commits, Length(Commits) >= GraphLimit, FBranch, FAhead, FBehind,
    FHasUpstream);
end;

procedure TForm1.MenuCommitGraphClick(Sender: TObject);
begin
  ShowCommitGraph;
end;

procedure TForm1.GraphPick(Sender: TObject; const AHash: string);
begin
  ShowBlameCommit(AHash);
end;

{ A click on a commit in the summary of a clean tree shows it against its
  parent, as a pick from the commit graph does. }
procedure TForm1.SummarySelectCommit(Sender: TObject; const AHash: string);
begin
  ShowBlameCommit(AHash);
end;

{ The status bar's parts: the branch drops the branch list up from it,
  as in the summary; the ahead/behind counts drop up pull, push, fetch
  and the commit graph; the
  pull request opens on GitHub; the conflicts show the first conflicted
  file; the name and the file count go back to the summary. }
procedure TForm1.StatusPartClick(Sender: TObject; APart: TGittanStatusPart;
  const AScreenRect: TRect);
var
  i: integer;
begin
  case APart of
    spRepo, spFiles:
      MenuSummaryClick(Sender);
    spBranch:
      SummaryBranchClick(Sender, AScreenRect);
    spSync:
      SyncClick(AScreenRect);
    spPull:
      PullChipClick(AScreenRect);
    spUpdate:
      UpdateDialog;
    spConflicts:
      for i := 0 to High(FStats) do
        if FStats[i].Kind = ckConflict then
        begin
          SummarySelectFile(Sender, FStats[i].Path);
          Break;
        end;
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

{ The terminal command from the settings file, with the repository root
  appended; the platform's terminal when none is set. On Linux the first
  terminal found on PATH is started in the root, since every terminal
  starts in its working directory but each names the option differently. }
procedure TForm1.MenuOpenTerminalClick(Sender: TObject);
{$IF not defined(DARWIN) and not defined(WINDOWS)}
const
  Terminals: array[0..4] of string = ('x-terminal-emulator', 'gnome-terminal',
    'konsole', 'xfce4-terminal', 'xterm');
var
  T: string;
{$ENDIF}
begin
  if FRepo.Root = '' then
    Exit;
  if Trim(FSettings.TerminalCommand) <> '' then
  begin
    RunCommandWith(FSettings.TerminalCommand, FRepo.Root);
    Exit;
  end;
  {$IFDEF DARWIN}
  RunDetached('open', ['-a', 'Terminal', FRepo.Root]);
  {$ELSE}
  {$IFDEF WINDOWS}
  if FindDefaultExecutablePath('wt.exe') <> '' then
    RunDetached('wt.exe', ['-d', FRepo.Root])
  else
    RunDetached('cmd.exe', ['/C', 'start', 'cmd.exe'], FRepo.Root);
  {$ELSE}
  for T in Terminals do
    if FindDefaultExecutablePath(T) <> '' then
    begin
      RunDetached(T, [], FRepo.Root);
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
      (FRepo.Base <> FMergeBase) and (Refs.IndexOf(FRepo.Base) < 0) then
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
  base to its head, what GitHub shows as its changes. }
procedure TForm1.ComparePull(const APull: TGittanPullRequest);
var
  Pull: TGittanPullRequest;
  Remote, HeadRef: string;
begin
  if FRepo.Root = '' then
    Exit;
  Pull := APull;
  FStatus.ShowMessage(Format(rsFetchingPull, [Pull.Number]), stNormal, 0);
  Remote := FRepo.RemoteFor(RepoPathOfUrl(Pull.Url));
  FStatus.ClearMessage;
  if not FRepo.FetchPullRequest(Remote, Pull.Number, Pull.BaseRef, HeadRef) then
  begin
    FSummary.Notice := Format(rsPullFailed, [Pull.Number, FRepo.Error]);
    ShowSummary;
    UpdateStatus;
    Exit;
  end;
  FPullRange := Remote + '/' + Pull.BaseRef + '...' + HeadRef;
  FPullNumber := Pull.Number;
  SetBase(FPullRange);
end;

{ The rows of the list a click on the status bar's pull request drops
  down. }
const
  paCompare = 1;
  paWorkingTree = 2;
  paOpen = 3;
  paCopy = 4;

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
  end;
end;

procedure TForm1.StatusPopupPopup(Sender: TObject);
begin
  if FOpenPullItem <> nil then
    FOpenPullItem.Enabled := FHasPull and (FPull.Url <> '');
  if FCopyPullItem <> nil then
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
  StartWatcher;
  { Comparing with a pull request shows its comments. }
  StartReviewJob(False);
end;
