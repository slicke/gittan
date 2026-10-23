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
procedure TForm1.SetupCommit;
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
  FCommitHeader := TGittanSectionHeader.Create(Self);
  FCommitHeader.Title := rsCommitSection;
  FCommitHeader.Align := alTop;
  FCommitHeader.Expanded := True;
  FCommitHeader.OnToggle := @CommitHeaderToggle;
  FCommitHeader.CheckImages := FCheckImages;
  FCommitHeader.OnCheck := @CommitHeaderCheck;
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

procedure TForm1.FocusTreeAsync(Data: PtrInt);
begin
  if FileTree.CanFocus then
    FileTree.SetFocus;
end;

{ Cocoa shows no TextHint in a memo (see gittan.memohint); the hint is
  set on the text view once the window has made it. }
procedure TForm1.CommitHintAsync(Data: PtrInt);
begin
  {$IFDEF LCLCocoa}
  if FCommitMemo.HandleAllocated then
    SetMemoPlaceholder(FCommitMemo.Handle, FCommitMemo.TextHint);
  {$ENDIF}
end;

{ The first line's length shows once it is past SubjectSoftLimit, in
  the warning color past SubjectHardLimit, where git log --oneline and
  GitHub cut it. }
procedure TForm1.UpdateSubjectCount;
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
procedure TForm1.CommitPushClick(Sender: TObject);
begin
  if FPushItem.Enabled then
    StartRemote(rkPush);
end;

{ The header in the other sections' palette, the note in a box tinted
  with the accent of the tree's boxes, or red for conflicts; the native
  controls keep the desktop's look. }
procedure TForm1.ColorCommit;
begin
  if FCommitHeader = nil then
    Exit;
  if FDark then
  begin
    FCommitHeader.SetColors(RGBToColor(37, 37, 38), Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(58, 58, 59), RGBToColor(62, 62, 62));
    FCommitNote.Font.Color := RGBToColor(200, 200, 200);
    FCommitNote.LinkColor := RGBToColor(100, 160, 240);
    FCommitNote.SetColors(RGBToColor(33, 44, 58), RGBToColor(44, 66, 92),
      RGBToColor(56, 34, 36), RGBToColor(100, 50, 54));
    FCommitNote.GlyphColor := RGBToColor(150, 150, 150);
    FBisectNote.Font.Color := FCommitNote.Font.Color;
    FBisectNote.SetColors(RGBToColor(33, 44, 58), RGBToColor(44, 66, 92),
      RGBToColor(56, 34, 36), RGBToColor(100, 50, 54));
  end
  else
  begin
    FCommitHeader.SetColors(RGBToColor(246, 246, 246), RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(232, 232, 232), RGBToColor(222, 222, 222));
    FCommitNote.Font.Color := RGBToColor(60, 60, 60);
    FCommitNote.LinkColor := RGBToColor(0, 110, 230);
    FCommitNote.SetColors(RGBToColor(234, 243, 252), RGBToColor(200, 222, 245),
      RGBToColor(253, 236, 236), RGBToColor(242, 198, 198));
    FCommitNote.GlyphColor := RGBToColor(110, 110, 110);
    FBisectNote.Font.Color := FCommitNote.Font.Color;
    FBisectNote.SetColors(RGBToColor(234, 243, 252), RGBToColor(200, 222, 245),
      RGBToColor(253, 236, 236), RGBToColor(242, 198, 198));
  end;
  UpdateSubjectCount;
end;

{ The header's box ticks every file that can be chosen, or none when
  all of them were, as a folder's box does for the files under it. }
procedure TForm1.CommitHeaderCheck(Sender: TObject);
begin
  SetAllChosen(FCommitHeader.CheckIndex <> checkOn);
end;

{ Chooses every changed file (AValue) or none, the filter's hidden ones
  too, as the header's count counts them; the changes left out of the
  files go, as with a folder's box. }
procedure TForm1.SetAllChosen(AValue: boolean);
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

procedure TForm1.MenuTickAllClick(Sender: TObject);
begin
  SetAllChosen(True);
end;

procedure TForm1.MenuUntickAllClick(Sender: TObject);
begin
  SetAllChosen(False);
end;

procedure TForm1.CommitHeaderToggle(Sender: TObject);
begin
  FCommitBox.Visible := FCommitHeader.Expanded;
  LayoutRepoFiles;
end;

{ Whether the tree's boxes choose what to commit: the work tree is
  compared with HEAD, so the tree is what a commit would take. }
function TForm1.CommitChoosing: boolean;
begin
  Result := (FRepo.Root <> '') and (FRepo.Base = '') and not ContinueMode;
end;

{ Whether FStats[AIndex] is chosen: as flipped, else unless git does
  not track it yet. }
function TForm1.CommitChosen(AIndex: integer): boolean;
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

procedure TForm1.SetCommitChosen(AIndex: integer; AValue: boolean);
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
function TForm1.CommitStatOf(ANode: TTreeNode): integer;
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
procedure TForm1.ApplyCommitChecks;
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
procedure TForm1.FlipCommitNode(ANode: TTreeNode);
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

procedure TForm1.FileTreeStateClick(Sender: TObject; Node: TTreeNode);
begin
  FlipCommitNode(Node);
end;

procedure TForm1.FileTreeKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if (Key = VK_SPACE) and (Shift = []) and (FileTree.Selected <> nil) then
  begin
    FlipCommitNode(FileTree.Selected);
    Key := 0;
  end;
end;

{ The chosen files, from every changed file, not only those the
  filter leaves in the tree; the header's count says how many. }
procedure TForm1.ChosenCommitPaths(AList: TStrings);
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
procedure TForm1.UpdateCommitState;
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
  FAbortButton.Visible := (FOperation <> '') and (FOperation <> 'bisecting');
  FAbortButton.Enabled := not Busy;
  FSkipButton.Visible := Continuing;
  FSkipButton.Enabled := not Busy;
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
end;

procedure TForm1.CommitNoteLink(Sender: TObject);
begin
  GoToConflict(True);
end;

procedure TForm1.CommitMemoChange(Sender: TObject);
begin
  UpdateCommitState;
  UpdateSubjectCount;
  {$IFDEF LCLCocoa}
  if FCommitMemo.HandleAllocated then
    ShowMemoPlaceholder(FCommitMemo.Handle, FCommitMemo.Lines.Text = '');
  {$ENDIF}
end;

procedure TForm1.CommitMemoKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (ssModifier in Shift) then
  begin
    Key := 0;
    if FCommitButton.Enabled then
      CommitButtonClick(Sender);
  end;
end;

{ Amend takes HEAD's message into an empty field, and gives it back
  when it is turned off unchanged. }
procedure TForm1.CommitAmendClick(Sender: TObject);
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

procedure TForm1.CommitButtonClick(Sender: TObject);
begin
  if ContinueMode then
    ContinueOperationClick
  else
    StartCommit;
end;

{ File > Commit: the section unfolded and the message field focused. }
procedure TForm1.MenuCommitClick(Sender: TObject);
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

{ git refuses to commit without a name and an e-mail; a fresh machine
  has neither, so they are asked for once and kept in the global config,
  as git itself would tell one to. }
function TForm1.EnsureIdentity: boolean;
var
  Values: array of string;
begin
  if (FRepo.UserName <> '') and (FRepo.UserEmail <> '') then
    Exit(True);
  SetLength(Values, 2);
  Values[0] := FRepo.UserName;
  Values[1] := FRepo.UserEmail;
  Result := InputQuery(rsIdentityTitle, [rsIdentityName, rsIdentityEmail], Values) and
    (Trim(Values[0]) <> '') and (Trim(Values[1]) <> '');
  if not Result then
    Exit;
  Result := FRepo.SetIdentity(Trim(Values[0]), Trim(Values[1]), True);
  if not Result then
    StatusNote(FRepo.Error, True);
end;

procedure TForm1.StartCommit;
var
  Paths: TStringList;
  Parts: TGittanCommitParts;
  Err: string;
begin
  if (FCommitJob <> nil) or (FRemoteJob <> nil) or not FCommitButton.Enabled or
    not EnsureIdentity then
    Exit;
  Paths := TStringList.Create;
  try
    ChosenCommitPaths(Paths);
    { The files with changes left out go in as their text without them
      (see umain.leaveout.inc). }
    if not CommitParts(Paths, Parts, Err) then
    begin
      BannerError(rsCommitFailed, Err);
      Exit;
    end;
    FCommitJob := TGittanCommitJob.Create(FRepo.Root, FCommitMemo.Text, Paths,
      FCommitAmend.Checked, Parts);
  finally
    Paths.Free;
  end;
  FCommitJob.OnDone := @CommitJobDone;
  FCommitJob.Start;
  FStatus.ShowMessage(rsCommitting, stNormal, 0);
  UpdateCommitState;
  UpdateRemoteItems;
end;

{ Done: on success the message, Amend and the flips go, and the tree
  shows what is left; on failure all stay, and git's reason (a hook's
  output, say) is shown in full. The job is freed from the message loop,
  since its notification comes from inside Execute. }
procedure TForm1.CommitJobDone(Sender: TObject);
var
  Job: TGittanCommitJob;
  Subject: string;
  Amended: boolean;
begin
  Job := TGittanCommitJob(Sender);
  if Job <> FCommitJob then
    Exit;
  FCommitJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  if Job.Ok then
  begin
    Subject := FCommitMemo.Lines.Text;
    if FCommitMemo.Lines.Count > 0 then
      Subject := FCommitMemo.Lines[0];
    Amended := FCommitAmend.Checked;
    FCommitMemo.Clear;
    FCommitAmend.Checked := False;
    FAmendMessage := '';
    FMergeMessage := '';
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

procedure TForm1.ShowCommitFailure(const AError: string);
begin
  FNoticeCommit := True;
  FStatus.ShowMessage(rsCommitFailed, stBad, StatusErrorSeconds);
  FNotice.DetailFont.Assign(Edit.Font);
  FNotice.Popup(rsCommitFailed, AError, False, nkBad);
  FNotice.SetButtons([rsCommitAgain, rsCopyOutput]);
end;

{ A commit is never broken off: one still running when the repository
  changes goes on in FDroppedCommits, and quitting waits for it and for
  those. The message of one that was made is no draft any more. }
procedure TForm1.StopCommitJob(AWait: boolean);
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
  FCommitJob := nil;
end;

{ A commit that ends after its repository was left: its message was
  saved as the draft when it was left, and may be in the field again
  when the repository was opened again since. Kept out of FBlameZombies
  until now, since freeing a finished job drops its notification. }
procedure TForm1.DroppedCommitDone(Sender: TObject);
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
procedure TForm1.ForgetCommitted(AJob: TGittanCommitJob);

  function Same(const AText: string): boolean;
  begin
    Result := Trim(AdjustLineBreaks(AText)) = Trim(AdjustLineBreaks(AJob.Message));
  end;

begin
  if not AJob.Ok then
    Exit;
  if (FSettings.CommitDraftRepo = AJob.Root) and Same(FSettings.CommitDraft) then
  begin
    FSettings.CommitDraft := '';
    FSettings.CommitDraftRepo := '';
  end;
  if (FCommitMemo <> nil) and (FCommitDraftFor = AJob.Root) and
    Same(FCommitMemo.Text) then
    FCommitMemo.Clear;
end;

{ The message goes to the settings' one slot for the repository it was
  written in; an empty field clears the slot only when it is that
  repository's, so opening another one keeps the draft. }
procedure TForm1.SaveCommitDraft;
begin
  if (FCommitMemo = nil) or (FCommitDraftFor = '') then
    Exit;
  if Trim(FCommitMemo.Text) <> '' then
  begin
    FSettings.CommitDraft := FCommitMemo.Text;
    FSettings.CommitDraftRepo := FCommitDraftFor;
  end
  else if FSettings.CommitDraftRepo = FCommitDraftFor then
  begin
    FSettings.CommitDraft := '';
    FSettings.CommitDraftRepo := '';
  end;
end;

{ After a repository is opened: its draft, if the slot holds one, and
  nothing chosen by hand. }
procedure TForm1.LoadCommitDraft;
begin
  FCommitOn.Clear;
  FCommitOff.Clear;
  FCommitAmend.Checked := False;
  FAmendMessage := '';
  FMergeMessage := '';
  FCommitDraftFor := FRepo.Root;
  if (FRepo.Root <> '') and (FSettings.CommitDraftRepo = FRepo.Root) then
    FCommitMemo.Text := FSettings.CommitDraft
  else
    FCommitMemo.Clear;
  UpdateCommitState;
end;
