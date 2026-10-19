{ ---------------------------------------------------------------------------
  Managing branches
  ---------------------------------------------------------------------------
  The branch list (see "Switching branch" in umain.actions.inc) starts
  with New Branch..., which makes a branch at HEAD and switches to it,
  and Delete Gone Branches... when local branches track one deleted on
  its remote. A right click on a branch (or the Menu key) shows what can
  be done with it: switch to it, merge it into the current branch,
  rename or delete it, and delete it on its remote. Deleting asks first,
  and asks again for a branch whose commits are in no other branch (git
  -d refuses it), since those commits are then only in the reflog.
  Nothing that moves HEAD is offered while git is in the middle of
  something or a commit, fetch, pull or push runs; deleting a branch on
  its remote goes to the network and runs as a remote job. }
const
  bmSwitch = 1;
  bmMerge = 2;
  bmRename = 3;
  bmDelete = 4;
  bmDeleteRemote = 5;

procedure TForm1.BranchContext(Sender: TObject; AIndex: integer; const AScreenPos: TPoint);
var
  BranchName, Ref, Up: string;
  Busy, IsRemote: boolean;

  { A name in a caption, its ampersands doubled. }
  function Amp(const AName: string): string;
  begin
    Result := StringReplace(AName, '&', '&&', [rfReplaceAll]);
  end;

  procedure Add(const ACaption: string; ATag: integer; AEnabled: boolean);
  var
    Item: TMenuItem;
  begin
    Item := TMenuItem.Create(FBranchMenu);
    Item.Caption := ACaption;
    Item.Tag := ATag;
    Item.Enabled := AEnabled;
    Item.OnClick := @BranchMenuClick;
    FBranchMenu.Items.Add(Item);
  end;

begin
  if (AIndex < 0) or (AIndex >= FBranchNames.Count) then
    Exit;
  BranchName := FBranchNames[AIndex];
  if (BranchName = '') or (BranchName[1] = ':') then
    Exit;
  Ref := FBranchRefs[AIndex];
  IsRemote := Ref <> '';
  if not IsRemote then
    Ref := BranchName;
  FMenuBranch := BranchName;
  FMenuBranchRef := Ref;
  Busy := (FOperation <> '') or (FCommitJob <> nil) or (FRemoteJob <> nil);
  FBranchMenu.Items.Clear;
  if BranchName <> FBranch then
  begin
    Add(Format(rsBmSwitch, [Amp(BranchName)]), bmSwitch, not Busy);
    Add(Format(rsBmMerge, [Amp(Ref), Amp(FBranch)]), bmMerge, not Busy);
  end;
  if not IsRemote then
  begin
    FBranchMenu.Items.Add(NewLine);
    Add(rsBmRename, bmRename, (BranchName <> FBranch) or (FOperation = ''));
    Add(rsBmDelete, bmDelete, BranchName <> FBranch);
    Up := FRepo.Upstream(BranchName);
  end
  else
    Up := Ref;
  FMenuBranchUpstream := Up;
  if Up <> '' then
  begin
    FBranchMenu.Items.Add(NewLine);
    Add(Format(rsBmDeleteRemote, [Amp(Up)]), bmDeleteRemote, FRemoteJob = nil);
  end;
  FBranchMenu.PopUp(AScreenPos.X, AScreenPos.Y);
end;

procedure TForm1.BranchMenuClick(Sender: TObject);
var
  BranchName, Ref: string;
begin
  BranchName := FMenuBranch;
  Ref := FMenuBranchRef;
  if (FRepo.Root = '') or (BranchName = '') then
    Exit;
  FBranchPopup.Close;
  case (Sender as TMenuItem).Tag of
    bmSwitch: SwitchBranch(BranchName);
    bmMerge: MergeIntoCurrent(Ref);
    bmRename: RenameBranchAsk(BranchName);
    bmDelete: DeleteBranchAsk(BranchName);
    bmDeleteRemote:
      if QuestionDlg(rsBmDeleteRemoteTitle, Format(rsBmDeleteRemoteAsk, [FMenuBranchUpstream]),
        mtWarning, [mrYes, rsBmDeleteAction, mrCancel, rsCancelButton, 'IsCancel',
        'IsDefault'], 0) = mrYes then
        StartRemote(rkDeleteRemote, pmAuto, FMenuBranchUpstream);
  end;
end;

{ The branch list's own rows: New Branch... and Delete Gone Branches.... }
function TForm1.BranchAction(const AName: string): boolean;
var
  Values: array of string;
begin
  Result := (AName = BranchNew) or (AName = BranchGone);
  if not Result or (FRepo.Root = '') then
    Exit;
  if AName = BranchGone then
  begin
    DeleteGoneBranches;
    Exit;
  end;
  SetLength(Values, 1);
  Values[0] := '';
  if not InputQuery(rsCaBranchTitle, [rsBmNewPrompt], Values) or (Trim(Values[0]) = '') then
    Exit;
  StopWatcher;
  if FRepo.CreateBranch(Trim(Values[0]), 'HEAD', True) then
  begin
    FSummary.Notice := '';
    RefreshRepository;
    StatusNote(Format(rsCaBranched, [Trim(Values[0])]));
  end
  else
    MessageDlg(rsCaFailed, FRepo.Error, mtError, [mbOK], 0);
  StartWatcher;
end;

procedure TForm1.RenameBranchAsk(const AName: string);
var
  Values: array of string;
begin
  SetLength(Values, 1);
  Values[0] := AName;
  if not InputQuery(rsBmRenameTitle, [Format(rsBmRenamePrompt, [AName])], Values) or
    (Trim(Values[0]) = '') or (Trim(Values[0]) = AName) then
    Exit;
  StopWatcher;
  if FRepo.RenameBranch(AName, Trim(Values[0])) then
  begin
    RefreshRepository;
    StatusNote(Format(rsBmRenamed, [AName, Trim(Values[0])]));
  end
  else
    MessageDlg(rsCaFailed, FRepo.Error, mtError, [mbOK], 0);
  StartWatcher;
end;

{ Asks, deletes with -d, and asks again with -D when git says the
  branch is not merged. }
procedure TForm1.DeleteBranchAsk(const AName: string);
var
  NotMerged, Ok: boolean;
begin
  if QuestionDlg(rsBmDeleteTitle, Format(rsBmDeleteAsk, [AName]), mtConfirmation,
    [mrYes, rsBmDeleteAction, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes then
    Exit;
  Ok := FRepo.DeleteBranch(AName, False, NotMerged);
  if not Ok and NotMerged and (QuestionDlg(rsBmDeleteTitle, Format(rsBmNotMerged, [AName]),
    mtWarning, [mrYes, rsBmDeleteAction, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'],
    0) = mrYes) then
    Ok := FRepo.DeleteBranch(AName, True, NotMerged)
  else if not Ok and NotMerged then
    Exit;
  if Ok then
  begin
    if FGoneBranches.IndexOf(AName) >= 0 then
      FGoneBranches.Delete(FGoneBranches.IndexOf(AName));
    RefreshRepository;
    StatusNote(Format(rsBmDeleted, [AName]));
  end
  else
    MessageDlg(rsCaFailed, FRepo.Error, mtError, [mbOK], 0);
end;

{ The branches whose upstream is gone, the current one left out: the
  merged ones go with -d, then those that are not merged, listed, after
  a second question. }
procedure TForm1.DeleteGoneBranches;
var
  Names, Unmerged: TStringList;
  NotMerged: boolean;
  Deleted, i: integer;
begin
  Names := TStringList.Create;
  Unmerged := TStringList.Create;
  try
    Names.Assign(FGoneToDelete);
    if Names.Count = 0 then
      Exit;
    if QuestionDlg(rsBmGoneTitle, Format(rsBmGoneAsk, [Names.Count]) + LineEnding +
      LineEnding + Names.Text, mtConfirmation, [mrYes, rsBmDeleteAction, mrCancel,
      rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes then
      Exit;
    Deleted := 0;
    for i := 0 to Names.Count - 1 do
      if FRepo.DeleteBranch(Names[i], False, NotMerged) then
        Inc(Deleted)
      else if NotMerged then
        Unmerged.Add(Names[i]);
    if (Unmerged.Count > 0) and (QuestionDlg(rsBmGoneTitle, Format(rsBmGoneUnmerged,
      [Unmerged.Count]) + LineEnding + LineEnding + Unmerged.Text, mtWarning,
      [mrYes, rsBmDeleteAction, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'], 0) = mrYes) then
      for i := 0 to Unmerged.Count - 1 do
        if FRepo.DeleteBranch(Unmerged[i], True, NotMerged) then
          Inc(Deleted);
    for i := FGoneBranches.Count - 1 downto 0 do
      if not FRepo.HasCommit('refs/heads/' + FGoneBranches[i]) then
        FGoneBranches.Delete(i);
    RefreshRepository;
    if Deleted = 1 then
      StatusNote(rsBmGoneDeletedOne)
    else
      StatusNote(Format(rsBmGoneDeleted, [Deleted]));
  finally
    Names.Free;
    Unmerged.Free;
  end;
end;

{ A merge of ARef into the branch HEAD is on, with git's message; one
  that stops with conflicts leaves them to the Commit section. }
procedure TForm1.MergeIntoCurrent(const ARef: string);
var
  Ok, Conflicts: boolean;
begin
  StopWatcher;
  Screen.Cursor := crHourGlass;
  try
    Ok := FRepo.MergeRef(ARef, Conflicts);
  finally
    Screen.Cursor := crDefault;
  end;
  FSummary.Notice := '';
  RefreshRepository;
  StartWatcher;
  if Ok then
    StatusNote(Format(rsCaMerged, [ARef]))
  else if Conflicts then
    StatusNote(rsCaConflicts, True)
  else
    MessageDlg(rsCaFailed, FRepo.Error, mtError, [mbOK], 0);
end;
