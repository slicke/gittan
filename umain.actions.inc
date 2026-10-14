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
    FileTree.Width := FSettings.TreeWidth;
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
  FSettings.TreeWidth := FileTree.Width;
  FSettings.FontName := Edit.Font.Name;
  FSettings.FontSize := Edit.Font.Size;
  FSettings.Zoom := Edit.OptScaleFont;
  FSettings.WordWrap := FWordWrap;
  FSettings.OnlyChanges := FOnlyChanges;
  FSettings.ContextLines := FContextLines;
  FSettings.SideBySide := FSideBySide;
  FSettings.IgnoreWhitespace := FIgnoreWhitespace;
  FSettings.Blame := FBlameOn;
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
    { A hidden line of the change view cannot be shown. }
    if Edit.IsLineFolded(i) then
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
    10, 5, True, TATEditorActionIfFolded.Ignore);
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
    begin
      Edit.Font.Assign(Dlg.Font);
      FEditOld.Font.Assign(Dlg.Font);
      Edit.Update(True);
      FEditOld.Update(True);
      UpdateNumberWidth(Edit);
      UpdateNumberWidth(FEditOld);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TForm1.MenuWrapClick(Sender: TObject);
begin
  FWordWrap := not FWordWrap;
  FWrapItem.Checked := FWordWrap;
  ApplyWrap;
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
procedure TForm1.MenuNextFileClick(Sender: TObject);
begin
  if StepFile(True) then
    GoToChange(True);
end;

procedure TForm1.MenuPrevFileClick(Sender: TObject);
begin
  if StepFile(False) then
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

{ Scrolling on past the bottom of a file pulls in the next one. The event
  fires before the editor scrolls, so a wheel step that is already at the
  bottom counts toward the pull; one that scrolls, or scrolls up, starts
  over. A pill at the bottom of the text rises with the pull (see
  EditDrawEditor), and when the pull is complete the next file is shown
  from its top. The gesture's momentum runs on after the jump, so the
  pull is disarmed until the wheel has paused. }
procedure TForm1.EditMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
var
  Now: QWord;
  AtBottom: boolean;
begin
  if (FView <> gvChanges) or (Shift - [ssLeft] <> []) then
    Exit;
  Now := GetTickCount64;
  if not FOverscrollArmed then
    FOverscrollArmed := Now - FOverscrollTick >= OverscrollPause;
  FOverscrollTick := Now;
  if not FOverscrollArmed then
    Exit;
  AtBottom := Edit.ScrollVert.SmoothPos >= Edit.ScrollVert.SmoothPosLast;
  if (WheelDelta >= 0) or not AtBottom or (NeighbourFile(True) = nil) then
  begin
    SetOverscroll(0);
    Exit;
  end;
  SetOverscroll(FOverscroll - WheelDelta);
  if FOverscroll < OverscrollNeeded then
    Exit;
  FOverscrollArmed := False;
  SetOverscroll(0);
  StepFile(True);
end;

procedure TForm1.SetOverscroll(AValue: integer);
begin
  if AValue = FOverscroll then
    Exit;
  FOverscroll := AValue;
  { Restarted on every change: the pull is forgotten after a quiet
    spell. }
  FOverscrollTimer.Enabled := False;
  FOverscrollTimer.Enabled := AValue > 0;
  Edit.Invalidate;
end;

procedure TForm1.OverscrollTimerTimer(Sender: TObject);
begin
  SetOverscroll(0);
end;

{ The pill that shows the pull: it rises from the bottom edge of the text
  as the pull grows, and fills from the left, until the next file is
  pulled in. The canvas is clipped to the text rectangle so the pill
  comes up from under its edge. }
procedure TForm1.EditDrawEditor(Sender: TObject; C: TCanvas; const ARect: TRect);
var
  Node: TTreeNode;
  Pill: string;
  W, H, Pad: integer;
  Part: double;
  R: TRect;
begin
  DrawBlame(TATSynEdit(Sender), C);
  if (Sender <> Edit) or (FOverscroll <= 0) or (FView <> gvChanges) then
    Exit;
  Node := NeighbourFile(True);
  if Node = nil then
    Exit;
  Pill := Format(rsPullNext, [ExtractFileName(Node.GetTextPath)]);
  Part := Min(1.0, FOverscroll / OverscrollNeeded);
  C.Font.Assign(FHeader.Font);
  C.Font.Color := FPullText;
  H := C.TextHeight(Pill) + 10;
  Pad := H div 2 + 4;
  W := C.TextWidth(Pill) + 2 * Pad;
  R := Rect(0, 0, W, H);
  R.Offset((ARect.Left + ARect.Right - W) div 2,
    ARect.Bottom - Round(Part * (H + 12)));
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
  FileTree.PopupMenu := FFilePopup;
  FHeader.PopupMenu := FFilePopup;

  FStatusPopup := TPopupMenu.Create(Self);
  AddItem(FStatusPopup, rsCopyBranch, @MenuCopyBranchClick);
  AddItem(FStatusPopup, rsCopyRepoPath, @MenuCopyRepoPathClick);
  Item := TMenuItem.Create(FStatusPopup);
  Item.Caption := '-';
  FStatusPopup.Items.Add(Item);
  AddItem(FStatusPopup, rsOpenTerminal, @MenuOpenTerminalClick);
  StatusBar.PopupMenu := FStatusPopup;
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
  else
    FContextPath := SelectedPath;
  Exists := (FContextPath <> '') and FileExists(ContextFullPath);
  for i := 0 to FFilePopup.Items.Count - 1 do
    FFilePopup.Items[i].Enabled := FContextPath <> '';
  FRevealItem.Enabled := Exists;
  FOpenItem.Enabled := Exists;
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

{ The editor command from the settings file, with the path appended; the
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

{ A click on the status bar goes back to the summary. }
procedure TForm1.StatusBarClick(Sender: TObject);
begin
  MenuSummaryClick(Sender);
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
  Refs := TStringList.Create;
  try
    if FRepo.Root <> '' then
      FRepo.Refs(Refs);
    if (FRepo.Base <> '') and not FRepo.WholeTree and (Refs.IndexOf(FRepo.Base) < 0) then
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
end;
