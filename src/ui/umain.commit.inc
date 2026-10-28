{ ---------------------------------------------------------------------------
  The Commit section
  ---------------------------------------------------------------------------
  Every changed file in the tree has a check box (its state image), and
  at the bottom of the tree panel sits a section with the message,
  Amend and a Commit button. What is committed is what the views show against HEAD: the
  chosen files as they are in the work tree (TGittanRepo.Commit), so
  the index needs no thought. A file is chosen from the start unless
  git does not track it yet; a click on a box (TTreeView.OnStateClick,
  which leaves the selection alone) or Space on the selected row flips
  it, and a folder's box flips every file under it. Only the flips are
  kept (FCommitOn, FCommitOff), by path, so they outlive the watcher's
  refreshes, and are dropped after a commit. The boxes show only while
  the work tree is compared with HEAD: against another base the tree
  is not what would be committed. The commit runs in a thread
  (gittan.commitjob), since hooks take their time. The message is kept
  in the settings until it is committed, for the repository it was
  written in. }
procedure TRepoFrame.SetupCommit;
begin
  FCommitOn := TStringList.Create;
  FCommitOn.CaseSensitive := True;
  FCommitOn.Sorted := True;
  FCommitOn.Duplicates := dupIgnore;
  FCommitOff := TStringList.Create;
  FCommitOff.CaseSensitive := True;
  FCommitOff.Sorted := True;
  FCommitOff.Duplicates := dupIgnore;
  FCheckImages := TImageList.Create(Self);
  FillCheckIcons(FCheckImages);
  FileTree.StateImages := FCheckImages;
  FileTree.OnStateClick := @FileTreeStateClick;
  FileTree.OnKeyDown := @FileTreeKeyDown;

  FCommitPanel := TPanel.Create(Self);
  FCommitPanel.BevelOuter := bvNone;
  FCommitPanel.Caption := '';
  FCommitPanel.Align := alBottom;
  FCommitPanel.AutoSize := True;
  FCommitPanel.Visible := False;
  { Last in the tree panel, under the Repository and Submodules
    sections, whichever of them show: alBottom orders by the bottom
    edge, and a section shown later would otherwise be put under it. }
  FCommitPanel.Top := MaxInt div 2;
  FCommitPanel.Parent := FTreePanel;
  { A note in it makes it taller, which the sections above give back. }
  FCommitPanel.OnResize := @TreePanelResize;
  FCommitHeader := TGittanSectionHeader.Create(Self);
  FCommitHeader.Title := rsCommitSection;
  FCommitHeader.Align := alTop;
  FCommitHeader.Expanded := True;
  FCommitHeader.OnToggle := @CommitHeaderToggle;
  FCommitHeader.CheckImages := FCheckImages;
  FCommitHeader.OnCheck := @CommitHeaderCheck;
  { AI at the header's right end while the AI features are on
    (umain.ai.inc). }
  FCommitHeader.OnAction := @MessageActionClick;
  { Before it the person, the name and e-mail commits are made under. }
  FCommitHeader.PersonShown := True;
  FCommitHeader.OnPerson := @IdentityClick;
  FCommitHeader.OnMouseEnter := @CommitHeaderEnter;
  FCommitHeader.Parent := FCommitPanel;
  FCommitBox := TPanel.Create(Self);
  FCommitBox.BevelOuter := bvNone;
  FCommitBox.Caption := '';
  FCommitBox.Align := alTop;
  FCommitBox.AutoSize := True;
  FCommitBox.Top := FCommitHeader.Height + 1;
  FCommitBox.ChildSizing.LeftRightSpacing := 8;
  FCommitBox.ChildSizing.TopBottomSpacing := 6;
  FCommitBox.Parent := FCommitPanel;
  SetupBisect;
  FCommitMemo := TMemo.Create(Self);
  FCommitMemo.Align := alTop;
  FCommitMemo.Top := 500;
  FCommitMemo.Height := 84;
  FCommitMemo.WordWrap := True;
  FCommitMemo.ScrollBars := ssAutoVertical;
  FCommitMemo.WantReturns := True;
  FCommitMemo.TextHint := rsCommitMessageHint;
  FCommitMemo.OnChange := @CommitMemoChange;
  FCommitMemo.OnKeyDown := @CommitMemoKeyDown;
  FCommitMemo.Parent := FCommitBox;
  FCommitRow := TPanel.Create(Self);
  FCommitRow.BevelOuter := bvNone;
  FCommitRow.Caption := '';
  FCommitRow.Align := alTop;
  FCommitRow.AutoSize := True;
  FCommitRow.Top := 1000;
  FCommitRow.BorderSpacing.Top := 6;
  FCommitRow.Parent := FCommitBox;
  FCommitAmend := TCheckBox.Create(Self);
  FCommitAmend.Caption := rsCommitAmend;
  FCommitAmend.Align := alLeft;
  FCommitAmend.OnClick := @CommitAmendClick;
  FCommitAmend.Parent := FCommitRow;
  FCommitOptions := TLabel.Create(Self);
  FCommitOptions.Align := alLeft;
  FCommitOptions.Left := 500;
  FCommitOptions.Layout := tlCenter;
  FCommitOptions.BorderSpacing.Left := 2;
  FCommitOptions.Cursor := crHandPoint;
  FCommitOptions.ShowHint := True;
  FCommitOptions.Hint := rsCommitOptionsHint;
  FCommitOptions.OnClick := @CommitOptionsClick;
  FCommitOptions.Parent := FCommitRow;
  FCommitOptionsMenu := TPopupMenu.Create(Self);
  FSignOffItem := TMenuItem.Create(FCommitOptionsMenu);
  FSignOffItem.Caption := rsSignOffItem;
  FSignOffItem.OnClick := @SignOffItemClick;
  FCommitOptionsMenu.Items.Add(FSignOffItem);
  FSkipHooksItem := TMenuItem.Create(FCommitOptionsMenu);
  FSkipHooksItem.Caption := rsSkipHooksItem;
  FSkipHooksItem.OnClick := @SkipHooksItemClick;
  FCommitOptionsMenu.Items.Add(FSkipHooksItem);
  FAbortButton := TButton.Create(Self);
  FAbortButton.Caption := rsAbortButton;
  FAbortButton.Align := alLeft;
  FAbortButton.AutoSize := True;
  FAbortButton.Left := 1000;
  FAbortButton.Visible := False;
  FAbortButton.OnClick := @AbortOperationClick;
  FAbortButton.Parent := FCommitRow;
  FSkipButton := TButton.Create(Self);
  FSkipButton.Caption := rsSkipButton;
  FSkipButton.Align := alLeft;
  FSkipButton.AutoSize := True;
  FSkipButton.Left := 2000;
  FSkipButton.BorderSpacing.Left := 4;
  FSkipButton.Visible := False;
  FSkipButton.OnClick := @SkipOperationClick;
  FSkipButton.Parent := FCommitRow;
  FCommitButton := TButton.Create(Self);
  FCommitButton.Caption := rsCommitButton;
  FCommitButton.Align := alRight;
  FCommitButton.AutoSize := True;
  FCommitButton.OnClick := @CommitButtonClick;
  FCommitButton.Parent := FCommitRow;
  FSubjectCount := TLabel.Create(Self);
  FSubjectCount.Align := alRight;
  FSubjectCount.Left := 0;
  FSubjectCount.Layout := tlCenter;
  FSubjectCount.BorderSpacing.Right := 8;
  FSubjectCount.ShowHint := True;
  FSubjectCount.Hint := Format(rsSubjectCountHint, [SubjectHardLimit]);
  FSubjectCount.Visible := False;
  FSubjectCount.Parent := FCommitRow;
  FCommitNote := TGittanHintBox.Create(Self);
  FCommitNote.Align := alTop;
  FCommitNote.Top := 2000;
  FCommitNote.BorderSpacing.Top := 8;
  FCommitNote.Visible := False;
  FCommitNote.OnLink := @CommitNoteLink;
  FCommitNote.Parent := FCommitBox;
  ColorCommit;
  { Cocoa makes the first text view of a new window its first
    responder, which would be the message field: the tree takes the
    keys once the window is up. }
  Application.QueueAsyncCall(@FocusTreeAsync, 0);
  Application.QueueAsyncCall(@CommitHintAsync, 0);
end;

procedure TRepoFrame.FocusTreeAsync(Data: PtrInt);
begin
  { CanFocus leaves the form out, and SetFocus raises while it is not
    shown. Something that pumps messages in FormCreate runs this before
    the window is up; it is tried again when the window is activated. }
  FFocusTreePending := not (FWindow.Visible and FWindow.Enabled and FileTree.CanFocus);
  if not FFocusTreePending then
    FileTree.SetFocus;
end;

{ The window became active: the tree takes the focus FocusTreeAsync
  could not give it, from the message loop, once Cocoa has made its
  first responder. }
procedure TRepoFrame.FormActivate(Sender: TObject);
begin
  if not FFocusTreePending then
    Exit;
  FFocusTreePending := False;
  Application.QueueAsyncCall(@FocusTreeAsync, 0);
end;

{ Cocoa shows no TextHint in a memo (see gittan.memohint); the hint is
  set on the text view once the window has made it. }
procedure TRepoFrame.CommitHintAsync(Data: PtrInt);
begin
  {$IFDEF LCLCocoa}
  if FCommitMemo.HandleAllocated then
    SetMemoPlaceholder(FCommitMemo.Handle, FCommitMemo.TextHint);
  {$ENDIF}
end;

{ The first line's length shows once it is past SubjectSoftLimit, in
  the warning color past SubjectHardLimit, where git log --oneline and
  GitHub cut it. }
procedure TRepoFrame.UpdateSubjectCount;
var
  Len: integer;
begin
  if FSubjectCount = nil then
    Exit;
  Len := 0;
  if FCommitMemo.Lines.Count > 0 then
    Len := UTF8Length(TrimRight(FCommitMemo.Lines[0]));
  FSubjectCount.Visible := Len > SubjectSoftLimit;
  if not FSubjectCount.Visible then
    Exit;
  FSubjectCount.Caption := Format(rsSubjectCount, [Len, SubjectHardLimit]);
  if Len > SubjectHardLimit then
  begin
    if FDark then
      FSubjectCount.Font.Color := RGBToColor(232, 170, 70)
    else
      FSubjectCount.Font.Color := RGBToColor(178, 106, 0);
  end
  else if FDark then
    FSubjectCount.Font.Color := RGBToColor(150, 150, 150)
  else
    FSubjectCount.Font.Color := RGBToColor(110, 110, 110);
end;

{ The Push the banner after a commit offers: as File > Push, while
  nothing else runs. }
procedure TRepoFrame.CommitPushClick(Sender: TObject);
begin
  if FPushItem.Enabled then
    StartRemote(rkPush);
end;

{ The header in the other sections' palette, the note in a box tinted
  with the accent of the tree's boxes, or red for conflicts; the native
  controls keep the desktop's look. }
procedure TRepoFrame.ColorCommit;
var
  P: TGittanPalette;
begin
  if FCommitHeader = nil then
    Exit;
  P := Palette;
  FCommitHeader.SetColors(P.Shade, P.Text, P.Dim, P.Raised, P.Line);
  FCommitHeader.ActionColor := P.Accent;
  if FDark then
    FCommitNote.Font.Color := RGBToColor(200, 200, 200)
  else
    FCommitNote.Font.Color := RGBToColor(60, 60, 60);
  FCommitNote.LinkColor := P.Accent;
  FCommitNote.SetColors(P.NoteInfo, P.NoteInfoLine, P.NoteError, P.NoteErrorLine);
  FCommitNote.GlyphColor := P.Dim;
  UpdateCommitOptions;
  FBisectNote.Font.Color := FCommitNote.Font.Color;
  FBisectNote.SetColors(P.NoteInfo, P.NoteInfoLine, P.NoteError, P.NoteErrorLine);
  UpdateSubjectCount;
end;

{ The header's box ticks every file that can be chosen, or none when
  all of them were, as a folder's box does for the files under it. }
procedure TRepoFrame.CommitHeaderCheck(Sender: TObject);
begin
  SetAllChosen(FCommitHeader.CheckIndex <> checkOn);
end;

{ Chooses every changed file (AValue) or none, the filter's hidden ones
  too, as the header's count counts them; the changes left out of the
  files go, as with a folder's box. }
procedure TRepoFrame.SetAllChosen(AValue: boolean);
var
  i: integer;
begin
  if not CommitChoosing or (FCommitJob <> nil) then
    Exit;
  for i := 0 to High(FStats) do
    if FStats[i].Kind <> ckConflict then
    begin
      SetCommitChosen(i, AValue);
      DropLeftOut(FStats[i].Path);
    end;
  ApplyCommitChecks;
  UpdateCommitState;
end;

procedure TRepoFrame.MenuTickAllClick(Sender: TObject);
begin
  SetAllChosen(True);
end;

procedure TRepoFrame.MenuUntickAllClick(Sender: TObject);
begin
  SetAllChosen(False);
end;

procedure TRepoFrame.CommitHeaderToggle(Sender: TObject);
begin
  FCommitBox.Visible := FCommitHeader.Expanded;
  LayoutRepoFiles;
end;

{ Whether the tree's boxes choose what to commit: the work tree is
  compared with HEAD, so the tree is what a commit would take. }
function TRepoFrame.CommitChoosing: boolean;
begin
  Result := (FRepo.Root <> '') and (FRepo.Base = '') and not ContinueMode;
end;

{ Whether FStats[AIndex] is chosen: as flipped, else unless git does
  not track it yet. }
function TRepoFrame.CommitChosen(AIndex: integer): boolean;
var
  Path: string;
begin
  Path := FStats[AIndex].Path;
  if FCommitOn.IndexOf(Path) >= 0 then
    Exit(True);
  if FCommitOff.IndexOf(Path) >= 0 then
    Exit(False);
  Result := FStats[AIndex].Kind <> ckUntracked;
end;

procedure TRepoFrame.SetCommitChosen(AIndex: integer; AValue: boolean);
var
  Path: string;
  i: integer;
begin
  Path := FStats[AIndex].Path;
  i := FCommitOn.IndexOf(Path);
  if i >= 0 then
    FCommitOn.Delete(i);
  i := FCommitOff.IndexOf(Path);
  if i >= 0 then
    FCommitOff.Delete(i);
  if AValue = (FStats[AIndex].Kind <> ckUntracked) then
    Exit;
  if AValue then
    FCommitOn.Add(Path)
  else
    FCommitOff.Add(Path);
end;

{ The index in FStats of the file at ANode, -1 for a folder or a file
  that cannot be chosen: a conflict, which a commit refuses until it is
  resolved. A submodule's node is a leaf with a stat of its own. }
function TRepoFrame.CommitStatOf(ANode: TTreeNode): integer;
var
  i: integer;
begin
  Result := -1;
  if ANode.Count > 0 then
    Exit;
  i := StatIndexOf(ANode.GetTextPath);
  if (i >= 0) and (FStats[i].Kind <> ckConflict) then
    Result := i;
end;

{ Sets every node's box: a file's from CommitChosen, mixed when changes
  of it are left out (see umain.leaveout.inc), a folder's from the
  files under it, none for a conflict or while not choosing. }
procedure TRepoFrame.ApplyCommitChecks;
var
  Node: TTreeNode;
  Choosing: boolean;

  function Mark(ANode: TTreeNode): integer;
  var
    Child: TTreeNode;
    AllOn, AllOff: boolean;
    State, i: integer;
  begin
    Result := -1;
    if ANode.Count > 0 then
    begin
      AllOn := True;
      AllOff := True;
      Child := ANode.GetFirstChild;
      while Child <> nil do
      begin
        State := Mark(Child);
        if State >= 0 then
        begin
          if Result < 0 then
            Result := checkOn;
          AllOn := AllOn and (State = checkOn);
          AllOff := AllOff and (State = checkOff);
        end;
        Child := Child.GetNextSibling;
      end;
      if Result >= 0 then
        if AllOn then
          Result := checkOn
        else if AllOff then
          Result := checkOff
        else
          Result := checkMixed;
    end
    else if Choosing then
    begin
      i := CommitStatOf(ANode);
      if i >= 0 then
        if not CommitChosen(i) then
          Result := checkOff
        else if FLeftOut.Count(FStats[i].Path) > 0 then
          Result := checkMixed
        else
          Result := checkOn;
    end;
    ANode.StateIndex := Result;
  end;

begin
  Choosing := CommitChoosing;
  FileTree.BeginUpdate;
  try
    Node := FileTree.Items.GetFirstNode;
    while Node <> nil do
    begin
      Mark(Node);
      Node := Node.GetNextSibling;
    end;
  finally
    FileTree.EndUpdate;
  end;
end;

{ A file's box flips it, a mixed one takes it whole; a folder's chooses
  every file under it, or none when all of them were. Either way the
  changes left out of the files go. }
procedure TRepoFrame.FlipCommitNode(ANode: TTreeNode);
var
  Value: boolean;

  procedure SetAll(ANode: TTreeNode);
  var
    Child: TTreeNode;
    i: integer;
  begin
    if ANode.Count = 0 then
    begin
      i := CommitStatOf(ANode);
      if i >= 0 then
      begin
        SetCommitChosen(i, Value);
        DropLeftOut(FStats[i].Path);
      end;
      Exit;
    end;
    Child := ANode.GetFirstChild;
    while Child <> nil do
    begin
      SetAll(Child);
      Child := Child.GetNextSibling;
    end;
  end;

begin
  if (ANode = nil) or (ANode.StateIndex < 0) or (FCommitJob <> nil) then
    Exit;
  Value := ANode.StateIndex <> checkOn;
  SetAll(ANode);
  ApplyCommitChecks;
  UpdateCommitState;
end;

procedure TRepoFrame.FileTreeStateClick(Sender: TObject; Node: TTreeNode);
begin
  FlipCommitNode(Node);
end;

procedure TRepoFrame.FileTreeKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if (Key = VK_SPACE) and (Shift = []) and (FileTree.Selected <> nil) then
  begin
    FlipCommitNode(FileTree.Selected);
    Key := 0;
  end;
end;

{ The chosen files, from every changed file, not only those the
  filter leaves in the tree; the header's count says how many. }
procedure TRepoFrame.ChosenCommitPaths(AList: TStrings);
var
  i: integer;
begin
  AList.Clear;
  for i := 0 to High(FStats) do
    if (FStats[i].Kind <> ckConflict) and CommitChosen(i) then
      AList.Add(FStats[i].Path);
end;

{ The header's count, the button and the note follow the choice, the
  message, Amend and what the repository is in the middle of. The note
  says why the button is off, when that is not plain to see. }
procedure TRepoFrame.UpdateCommitState;
var
  Chosen, Total, i: integer;
  Whole, Continuing, Busy, Can: boolean;
  Note: string;
begin
  if FCommitPanel = nil then
    Exit;
  FCommitPanel.Visible := FRepo.Root <> '';
  if FRepo.Root = '' then
    Exit;
  Chosen := 0;
  Total := 0;
  for i := 0 to High(FStats) do
    if FStats[i].Kind <> ckConflict then
    begin
      Inc(Total);
      if CommitChosen(i) then
        Inc(Chosen);
    end;
  Whole := (FOperation = 'merging') or (FOperation = 'cherry-picking') or
    (FOperation = 'reverting');
  Continuing := ContinueMode;
  Busy := (FCommitJob <> nil) or (FRemoteJob <> nil);
  { A merge is committed with git's message, filled into an empty field
    once; it goes when the merge does. }
  if FOperation = 'merging' then
  begin
    if (FMergeMessage = '') and (Trim(FCommitMemo.Text) = '') then
    begin
      FMergeMessage := FRepo.MergeMessage;
      if FMergeMessage <> '' then
        FCommitMemo.Text := FMergeMessage;
    end;
  end
  else if FMergeMessage <> '' then
  begin
    if FCommitMemo.Text = FMergeMessage then
      FCommitMemo.Clear;
    FMergeMessage := '';
  end;
  Note := '';
  Can := not Busy;
  if FRepo.Base <> '' then
  begin
    Note := rsCommitNotHead;
    Can := False;
  end
  else if FConflictFiles > 0 then
  begin
    if FConflictFiles = 1 then
      Note := rsCommitConflictOne
    else
      Note := Format(rsCommitConflicts, [FConflictFiles]);
    Can := False;
  end
  else if Continuing then
  begin
    { An interactive rebase stopped at a commit to edit says which. }
    Note := '';
    if FOperation = 'rebasing' then
      Note := FRepo.RebaseStoppedAt;
    if Note <> '' then
      Note := Format(rsRebaseEditNote, [Copy(Note, 1, 7)])
    else
      Note := Format(rsContinueNote, [OperationNoun(FOperation)]);
  end
  else if Whole then
    Note := Format(rsCommitWhole, [FOperation])
  else if (Chosen = 0) and not FCommitAmend.Checked then
  begin
    if Total > 0 then
      Note := rsCommitNothing;
    Can := False;
  end;
  { A rebase left behind by a checkout: a commit on this branch is fine,
    the note says what the Abort button does instead. }
  if (Note = '') and StrayRebase then
    Note := Format(rsStrayRebaseNote, [FRebaseBranch, FBranch]);
  if not Continuing and (Trim(FCommitMemo.Text) = '') then
    Can := False;
  if CommitChoosing and (Total > 0) then
  begin
    FCommitHeader.Detail := Format(rsCommitCount, [Chosen, Total]);
    if Chosen = 0 then
      FCommitHeader.CheckIndex := checkOff
    else if Chosen = Total then
      FCommitHeader.CheckIndex := checkOn
    else
      FCommitHeader.CheckIndex := checkMixed;
  end
  else
  begin
    FCommitHeader.Detail := '';
    FCommitHeader.CheckIndex := -1;
  end;
  FChosenCount := Chosen;
  FChoosableCount := Total;
  if FCommitJob <> nil then
    FCommitButton.Caption := rsCommitting
  else if Continuing then
    FCommitButton.Caption := rsContinueButton
  else if FOperation = 'merging' then
    FCommitButton.Caption := rsCommitMergeButton
  else if FCommitAmend.Checked then
    FCommitButton.Caption := rsCommitAmendButton
  else
    FCommitButton.Caption := rsCommitButton;
  FCommitButton.Enabled := Can;
  { git keeps the message of a commit it carries on with. A fetch, pull
    or push leaves the message alone, so it can be written meanwhile;
    Amend waits, since a pull may move HEAD, whose message it reads. }
  FCommitMemo.ReadOnly := (FCommitJob <> nil) or Continuing;
  FCommitMemo.Enabled := not Continuing;
  FCommitAmend.Visible := FOperation = '';
  FCommitAmend.Enabled := not Busy;
  { A merge's commit takes them too; carrying on with a rebase or a
    cherry-pick does not commit through Commit. }
  FCommitOptions.Visible := not Continuing;
  FCommitOptions.Enabled := not Busy;
  FAbortButton.Visible := (FOperation <> '') and (FOperation <> 'bisecting');
  FAbortButton.Enabled := not Busy;
  FSkipButton.Visible := Continuing;
  FSkipButton.Enabled := not Busy;
  UpdateMessageAction;
  FCommitNote.Text := Note;
  { The conflicts lead on to the first of them. }
  if (FRepo.Base = '') and (FConflictFiles > 0) then
    FCommitNote.Link := Format(rsNextConflictLink, [ShortCutToText(ShortCut(VK_F6, []))])
  else
    FCommitNote.Link := '';
  { "Tick the files" beside a ticked box and the conflicts beside their
    badge, as the tree draws them, the base beside a branch. }
  FCommitNote.Warn := (FRepo.Base = '') and (FConflictFiles > 0);
  if Note = rsCommitNotHead then
    FCommitNote.Glyph := HintBranch
  else
    FCommitNote.Glyph := '';
  if Note = rsCommitNothing then
  begin
    FCommitNote.Images := FCheckImages;
    FCommitNote.Icon := checkOn;
  end
  else if FCommitNote.Warn then
  begin
    FCommitNote.Images := TreeImages;
    FCommitNote.Icon := ChangeIcon(ckConflict);
  end
  else
    FCommitNote.Icon := -1;
  FCommitNote.Visible := Note <> '';
  UpdateBisectState;
  if FCommitItem <> nil then
    FCommitItem.Enabled := FRepo.Root <> '';
  if FIdentityItem <> nil then
    FIdentityItem.Enabled := FRepo.Root <> '';
end;

procedure TRepoFrame.CommitNoteLink(Sender: TObject);
begin
  GoToConflict(True);
end;

procedure TRepoFrame.CommitMemoChange(Sender: TObject);
begin
  UpdateCommitState;
  UpdateSubjectCount;
  {$IFDEF LCLCocoa}
  if FCommitMemo.HandleAllocated then
    ShowMemoPlaceholder(FCommitMemo.Handle, FCommitMemo.Lines.Text = '');
  {$ENDIF}
end;

procedure TRepoFrame.CommitMemoKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (ssModifier in Shift) then
  begin
    Key := 0;
    if FCommitButton.Enabled then
      CommitButtonClick(Sender);
  end;
end;

{ "⌄" alone, or the option that is on ("2 options" for both) before it
  in the accent, so a commit that would be signed off or skip the hooks
  says so beside Amend. }
procedure TRepoFrame.UpdateCommitOptions;
var
  Shown: string;
begin
  if FCommitOptions = nil then
    Exit;
  Shown := '';
  if FSignOff then
    Shown := rsSignOffShort;
  { Both would not fit beside Amend and Commit; the menu says which. }
  if FSkipHooks then
    if Shown = '' then
      Shown := rsSkipHooksShort
    else
      Shown := Format(rsCommitOptionsCount, [2]);
  if Shown = '' then
    FCommitOptions.Caption := '⌄'
  else
    FCommitOptions.Caption := Shown + ' ⌄';
  if Shown = '' then
    FCommitOptions.Font.Color := Palette.Dim
  else
    FCommitOptions.Font.Color := Palette.Accent;
end;

{ The menu under the label, its items ticked as they are; Sign Off is
  read again, as git config may have changed it from outside. }
procedure TRepoFrame.CommitOptionsClick(Sender: TObject);
var
  At: TPoint;
begin
  if (FRepo.Root = '') or not FCommitOptions.Enabled then
    Exit;
  FSignOff := FRepo.SignOff;
  FSignOffItem.Checked := FSignOff;
  FSkipHooksItem.Checked := FSkipHooks;
  UpdateCommitOptions;
  At := FCommitOptions.ClientToScreen(Point(0, FCommitOptions.Height));
  FCommitOptionsMenu.PopUp(At.X, At.Y);
end;

procedure TRepoFrame.SignOffItemClick(Sender: TObject);
begin
  if not FRepo.SetSignOff(not FSignOff) then
    StatusNote(FRepo.Error, True);
  FSignOff := FRepo.SignOff;
  UpdateCommitOptions;
end;

procedure TRepoFrame.SkipHooksItemClick(Sender: TObject);
begin
  FSkipHooks := not FSkipHooks;
  UpdateCommitOptions;
end;

{ Amend takes HEAD's message into an empty field, and gives it back
  when it is turned off unchanged. }
procedure TRepoFrame.CommitAmendClick(Sender: TObject);
var
  Message: string;
begin
  if FCommitAmend.Checked then
  begin
    if (Trim(FCommitMemo.Text) = '') and FRepo.HeadMessage(Message) then
    begin
      FCommitMemo.Text := Message;
      FAmendMessage := FCommitMemo.Text;
    end;
  end
  else if (FAmendMessage <> '') and (FCommitMemo.Text = FAmendMessage) then
    FCommitMemo.Clear;
  if not FCommitAmend.Checked then
    FAmendMessage := '';
  UpdateCommitState;
end;

procedure TRepoFrame.CommitButtonClick(Sender: TObject);
begin
  if ContinueMode then
    ContinueOperationClick
  else
    StartCommit;
end;

{ File > Commit: the section unfolded and the message field focused. }
procedure TRepoFrame.MenuCommitClick(Sender: TObject);
begin
  if FRepo.Root = '' then
    Exit;
  if not FCommitHeader.Expanded then
  begin
    FCommitHeader.Expanded := True;
    CommitHeaderToggle(nil);
  end;
  if FCommitMemo.CanFocus then
  begin
    FCommitMemo.SetFocus;
    FCommitMemo.SelStart := Length(FCommitMemo.Text);
  end;
end;

function TRepoFrame.EditIdentity: boolean;
var
  Who, Mail: string;
  Local: boolean;
begin
  Who := FRepo.UserName;
  Mail := FRepo.UserEmail;
  Local := FRepo.HasLocalIdentity;
  Result := ChooseIdentity(Who, Mail, Local);
  if not Result then
    Exit;
  Result := FRepo.SetIdentity(Who, Mail, not Local);
  if not Result then
    StatusNote(FRepo.Error, True);
end;

{ git refuses to commit without a name and an e-mail; a fresh machine
  has neither, so they are asked for once, kept in the global config as
  git itself would tell one to unless the repository is to have its
  own. }
function TRepoFrame.EnsureIdentity: boolean;
begin
  if (FRepo.UserName <> '') and (FRepo.UserEmail <> '') then
    Exit(True);
  Result := EditIdentity;
end;

procedure TRepoFrame.IdentityClick(Sender: TObject);
begin
  if FRepo.Root <> '' then
    EditIdentity;
end;

{ The hint over the person says who commits; read as the mouse comes
  in, so a change made with git outside is seen too. }
procedure TRepoFrame.CommitHeaderEnter(Sender: TObject);
var
  Who, Mail, Where: string;
begin
  Who := FRepo.UserName;
  Mail := FRepo.UserEmail;
  if (Who = '') or (Mail = '') then
    FCommitHeader.PersonHint := rsIdentityNone
  else
  begin
    Where := '';
    if FRepo.HasLocalIdentity then
      Where := rsIdentityHintLocal;
    FCommitHeader.PersonHint := Format(rsIdentityHint, [Who, Mail, Where]);
  end;
end;

procedure TRepoFrame.StartCommit;
var
  Paths: TStringList;
  Parts: TGittanCommitParts;
  Options: TGittanCommitOptions;
  Err: string;
begin
  if (FCommitJob <> nil) or (FRemoteJob <> nil) or not FCommitButton.Enabled or
    not EnsureIdentity then
    Exit;
  Paths := TStringList.Create;
  try
    ChosenCommitPaths(Paths);
    if not LockedCommitAsk(Paths, FCommitAmend.Checked) then
      Exit;
    { The files with changes left out go in as their text without them
      (see umain.leaveout.inc). }
    if not CommitParts(Paths, Parts, Err) then
    begin
      BannerError(rsCommitFailed, Err);
      Exit;
    end;
    Options := [];
    if FSignOff then
      Include(Options, coSignOff);
    if FSkipHooks then
      Include(Options, coNoVerify);
    FCommitJob := TGittanCommitJob.Create(FRepo.Root, FCommitMemo.Text, Paths,
      FCommitAmend.Checked, Parts, Options);
  finally
    Paths.Free;
  end;
  FCommitJob.OnDone := @CommitJobDone;
  FCommitJob.Start;
  FStatus.ShowBusy(rsCommitting);
  UpdateCommitState;
  UpdateRemoteItems;
end;

{ The ticked files committed as a fixup of ACommit, as StartCommit
  commits them, with "fixup! <subject>" as the message, which git's
  autosquash and the interactive rebase's dialog read (AutosquashSteps
  in gittan.rebase). The message being written stays in the memo. Not
  while Amend is ticked, which the next commit would then amend the
  fixup with, nor while a file is still in conflict. }
procedure TRepoFrame.StartFixupCommit(const ACommit: TGittanGraphCommit);
var
  Paths: TStringList;
  Parts: TGittanCommitParts;
  Options: TGittanCommitOptions;
  Err: string;
begin
  if (FCommitJob <> nil) or (FRemoteJob <> nil) or RepoBusy or not CommitChoosing or
    (FChosenCount = 0) or FCommitAmend.Checked or (FConflictFiles > 0) or
    not EnsureIdentity then
    Exit;
  Paths := TStringList.Create;
  try
    ChosenCommitPaths(Paths);
    if (Paths.Count = 0) or not LockedCommitAsk(Paths, False) then
      Exit;
    if not CommitParts(Paths, Parts, Err) then
    begin
      BannerError(rsCommitFailed, Err);
      Exit;
    end;
    Options := [];
    if FSignOff then
      Include(Options, coSignOff);
    if FSkipHooks then
      Include(Options, coNoVerify);
    FCommitJob := TGittanCommitJob.Create(FRepo.Root, 'fixup! ' + ACommit.Subject, Paths,
      False, Parts, Options);
  finally
    Paths.Free;
  end;
  FFixupJob := FCommitJob;
  FFixupHash := ACommit.Hash;
  FFixupShort := ACommit.Short;
  if Length(ACommit.Parents) > 0 then
    FFixupParent := ACommit.Parents[0]
  else
    FFixupParent := '';
  FCommitJob.OnDone := @CommitJobDone;
  FCommitJob.Start;
  FStatus.ShowBusy(rsCommitting);
  UpdateCommitState;
  UpdateRemoteItems;
end;

{ Fold It In in the banner of a fixup commit: the interactive rebase
  from the parent of the commit fixed up, which puts the fixup after
  it; only while HEAD still has the fixup (a branch switched to since
  may have the commit fixed up without it). }
procedure TRepoFrame.FixupFoldClick(Sender: TObject);
begin
  if (FFixupParent <> '') and (FFixupId <> '') and FRepo.IsAncestor(FFixupId, 'HEAD') then
    RebaseInteractiveAsk(FFixupParent, Copy(FFixupParent, 1, 7), False);
end;

{ Done: on success the message, Amend and the flips go, and the tree
  shows what is left; on failure all stay, and git's reason (a hook's
  output, say) is shown in full. The job is freed from the message loop,
  since its notification comes from inside Execute. A fixup commit
  leaves the message, Amend and the options alone, and offers the
  rebase that folds it in. }
procedure TRepoFrame.CommitJobDone(Sender: TObject);
var
  Job: TGittanCommitJob;
  Subject: string;
  Amended, Fixup, Merges: boolean;
  Steps: TGittanRebaseSteps;
begin
  Job := TGittanCommitJob(Sender);
  if Job <> FCommitJob then
    Exit;
  FCommitJob := nil;
  Fixup := Job = FFixupJob;
  FFixupJob := nil;
  MarkNews;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  if Job.Ok then
  begin
    Subject := FCommitMemo.Lines.Text;
    if FCommitMemo.Lines.Count > 0 then
      Subject := FCommitMemo.Lines[0];
    Amended := FCommitAmend.Checked;
    if not Fixup then
    begin
      FCommitMemo.Clear;
      FCommitAmend.Checked := False;
      FAmendMessage := '';
      FMergeMessage := '';
      FSkipHooks := False;
      UpdateCommitOptions;
    end;
    FCommitOn.Clear;
    FCommitOff.Clear;
    FLeftOut.ClearAll;
  end
  else
    FStatus.ShowMessage('', stNormal, 0);
  RefreshRepository;
  UpdateCommitState;
  UpdateRemoteItems;
  if not Job.Ok then
    ShowCommitFailure(Job.Error)
  else if Fixup then
  begin
    FStatus.ShowMessage('', stNormal, 0);
    FFixupId := Job.Id;
    { Folded in by the interactive rebase, which takes no merges. }
    if (FFixupParent <> '') and (not FRepo.RebaseSteps(FFixupParent, Steps, Merges) or
      Merges) then
      FFixupParent := '';
    if FFixupParent <> '' then
      FBanner.AddAction(Format(rsFixupCommitted, [FFixupShort]), Job.Message, bkSuccess,
        BannerActionSeconds, rsFixupFold, @FixupFoldClick)
    else
      StatusNote(Format(rsCommitted, [Copy(Job.Id, 1, 7), Job.Message]));
  end
  { A branch that can be pushed as it is (it has an upstream and is not
    behind it, so an amended pushed commit is left to Force Push) is
    offered the push in a banner; otherwise the status bar says it. }
  else if not Amended and FHasUpstream and (FAhead > 0) and (FBehind = 0) and
    FPushItem.Enabled then
  begin
    FStatus.ShowMessage('', stNormal, 0);
    FBanner.AddAction(Format(rsCommittedTitle, [Copy(Job.Id, 1, 7)]), Subject,
      bkSuccess, BannerActionSeconds, rsPushAction, @CommitPushClick);
  end
  else
    StatusNote(Format(rsCommitted, [Copy(Job.Id, 1, 7), Subject]));
end;

procedure TRepoFrame.ShowCommitFailure(const AError: string);
begin
  FNoticeCommit := True;
  FStatus.ShowMessage(rsCommitFailed, stBad, StatusErrorSeconds);
  FNotice.DetailFont.Assign(Edit.Font);
  FNotice.Popup(rsCommitFailed, AError, False, nkBad);
  MarkNews;
  FNotice.SetButtons([rsCommitAgain, rsCopyOutput]);
end;

{ A commit is never broken off: one still running when the repository
  changes goes on in FDroppedCommits, and quitting waits for it and for
  those. The message of one that was made is no draft any more. }
procedure TRepoFrame.StopCommitJob(AWait: boolean);
var
  Job: TGittanCommitJob;
  i: integer;
begin
  if AWait then
  begin
    { Stop's wait lets queued calls through: another dropped job's
      DroppedCommitDone would take it out of the list being walked, and
      FCommitJob's CommitDone refresh the repository being closed. }
    for i := 0 to FDroppedCommits.Count - 1 do
      TGittanCommitJob(FDroppedCommits[i]).OnDone := nil;
    if FCommitJob <> nil then
      FCommitJob.OnDone := nil;
    for i := 0 to FDroppedCommits.Count - 1 do
    begin
      Job := TGittanCommitJob(FDroppedCommits[i]);
      Job.Stop(True);
      ForgetCommitted(Job);
      Job.Free;
    end;
    FDroppedCommits.Clear;
  end;
  if FCommitJob = nil then
    Exit;
  FCommitJob.Stop(AWait);
  if AWait then
  begin
    ForgetCommitted(FCommitJob);
    FCommitJob.Free;
  end
  else
  begin
    FCommitJob.OnDone := @DroppedCommitDone;
    FDroppedCommits.Add(FCommitJob);
  end;
  { Freed now or later: a job made at its address is no fixup. }
  if FFixupJob = FCommitJob then
    FFixupJob := nil;
  FCommitJob := nil;
end;

{ A commit that ends after its repository was left: its message was
  saved as the draft when it was left, and may be in the field again
  when the repository was opened again since. Kept out of FBlameZombies
  until now, since freeing a finished job drops its notification. }
procedure TRepoFrame.DroppedCommitDone(Sender: TObject);
var
  Job: TGittanCommitJob;
begin
  Job := TGittanCommitJob(Sender);
  FDroppedCommits.Remove(Job);
  ForgetCommitted(Job);
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
end;

{ Clears the draft slot and the field where they still hold the message
  AJob committed. }
procedure TRepoFrame.ForgetCommitted(AJob: TGittanCommitJob);

  function Same(const AText: string): boolean;
  begin
    Result := Trim(AdjustLineBreaks(AText)) = Trim(AdjustLineBreaks(AJob.Message));
  end;

begin
  if not AJob.Ok then
    Exit;
  if (App.Settings.CommitDraftRepo = AJob.Root) and Same(App.Settings.CommitDraft) then
  begin
    App.Settings.CommitDraft := '';
    App.Settings.CommitDraftRepo := '';
  end;
  if (FCommitMemo <> nil) and (FCommitDraftFor = AJob.Root) and
    Same(FCommitMemo.Text) then
    FCommitMemo.Clear;
end;

{ The message goes to the settings' one slot for the repository it was
  written in; an empty field clears the slot only when it is that
  repository's, so opening another one keeps the draft. }
procedure TRepoFrame.SaveCommitDraft;
begin
  if (FCommitMemo = nil) or (FCommitDraftFor = '') then
    Exit;
  if Trim(FCommitMemo.Text) <> '' then
  begin
    App.Settings.CommitDraft := FCommitMemo.Text;
    App.Settings.CommitDraftRepo := FCommitDraftFor;
  end
  else if App.Settings.CommitDraftRepo = FCommitDraftFor then
  begin
    App.Settings.CommitDraft := '';
    App.Settings.CommitDraftRepo := '';
  end;
end;

{ After a repository is opened: its draft, if the slot holds one, and
  nothing chosen by hand. }
procedure TRepoFrame.LoadCommitDraft;
begin
  FCommitOn.Clear;
  FCommitOff.Clear;
  FCommitAmend.Checked := False;
  FAmendMessage := '';
  FMergeMessage := '';
  FCommitDraftFor := FRepo.Root;
  FSignOff := FRepo.SignOff;
  FSkipHooks := False;
  UpdateCommitOptions;
  if (FRepo.Root <> '') and (App.Settings.CommitDraftRepo = FRepo.Root) then
    FCommitMemo.Text := App.Settings.CommitDraft
  else
    FCommitMemo.Clear;
  UpdateCommitState;
end;
