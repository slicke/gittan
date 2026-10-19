{ ---------------------------------------------------------------------------
  Managing branches
  ---------------------------------------------------------------------------
  The branch list (see "Switching branch" in umain.actions.inc) starts
  with New Branch..., which makes a branch at HEAD and switches to it,
  and Delete Gone Branches... when local branches track one deleted on
  its remote. A right click on a branch (or the Menu key) shows what can
  be done with it: switch to it, merge it into the current branch,
  rebase the current branch onto it, show what it changed since it left
  the current one (the range current...branch), what the current one
  changed since it left it (branch...current, as a pull request to it
  would show) or compare the work tree with it, rename or delete it, and
  delete it on its remote. Deleting
  asks first, and asks again for a branch whose commits are in no other
  branch (git -d refuses it), since those commits are then only in the
  reflog. Nothing that moves HEAD is offered while git is in the middle
  of something or a commit, fetch, pull or push runs; deleting a branch
  on its remote goes to the network and runs as a remote job.

  The Branch menu offers the same with the verb first: Switch to
  Branch... (Cmd+B), New Branch..., Merge into <current>..., Rebase
  <current> onto..., Show What a Branch Changed Since It Left
  <current>... and Show What <current> Changed Since It Left... each
  drop the branch list (ShowBranchList) from the status bar's branch in
  the mode that does that with the branch picked. }
const
  bmSwitch = 1;
  bmMerge = 2;
  bmRename = 3;
  bmDelete = 4;
  bmDeleteRemote = 5;
  bmCompareTree = 6;
  bmCompareSince = 7;
  bmRebase = 8;
  bmCurrentSince = 9;

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
    Add(Format(rsBmRebase, [Amp(FBranch), Amp(Ref)]), bmRebase, not Busy);
    FBranchMenu.Items.Add(NewLine);
    Add(Format(rsBmCompareSince, [Amp(Ref), Amp(FBranch)]), bmCompareSince, True);
    Add(Format(rsBmCompareSince, [Amp(FBranch), Amp(Ref)]), bmCurrentSince, True);
    Add(rsBmCompareTree, bmCompareTree, True);
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
    bmCompareTree: SetBase(Ref);
    bmCompareSince: CompareSince(Ref);
    bmCurrentSince: CompareCurrentSince(Ref);
    bmMerge: MergeIntoCurrent(Ref);
    bmRebase: RebaseOntoAsk(Ref);
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

{ What the branch ARef did since it left the current one, through their
  merge base, as a pull request from it would show; HEAD while git is
  in the middle of something, when FBranch may not be HEAD. }
procedure TForm1.CompareSince(const ARef: string);
begin
  if (FOperation = '') and FRepo.HasCommit('refs/heads/' + FBranch) then
    SetBase(FBranch + '...' + ARef)
  else
    SetBase('HEAD...' + ARef);
end;

{ What the current branch did since it left ARef, through their merge
  base, as a pull request to ARef would show. }
procedure TForm1.CompareCurrentSince(const ARef: string);
begin
  if (FOperation = '') and FRepo.HasCommit('refs/heads/' + FBranch) then
    SetBase(ARef + '...' + FBranch)
  else
    SetBase(ARef + '...HEAD');
end;

{ The Branch menu's items: enabled with a repository, the ones that move
  HEAD not while git is in the middle of something or a job runs, and
  captioned with the current branch. Called as the menu opens and
  whenever the repository or a job changes, for the shortcuts. }
procedure TForm1.UpdateBranchItems;
var
  Has, Busy: boolean;
  Current: string;
begin
  if FMergeItem = nil then
    Exit;
  Has := (FRepo <> nil) and (FRepo.Root <> '');
  Busy := (FOperation <> '') or (FCommitJob <> nil) or (FRemoteJob <> nil);
  if Has and (FBranch <> '') then
    Current := StringReplace(FBranch, '&', '&&', [rfReplaceAll])
  else
    Current := rsBmCurrent;
  FSwitchItem.Enabled := Has;
  FNewBranchItem.Enabled := Has and (FOperation = '');
  FMergeItem.Caption := Format(rsBmMergeItem, [Current]);
  FMergeItem.Enabled := Has and not Busy and (FBranch <> '');
  FRebaseItem.Caption := Format(rsBmRebaseItem, [Current]);
  FRebaseItem.Enabled := FMergeItem.Enabled;
  FCompareBranchItem.Caption := Format(rsBmCompareItem, [Current]);
  FCompareBranchItem.Enabled := Has;
  FCompareBackItem.Caption := Format(rsBmCompareBackItem, [Current]);
  FCompareBackItem.Enabled := Has;
end;

procedure TForm1.BranchMenuOpen(Sender: TObject);
begin
  UpdateBranchItems;
end;

{ The list drops from the status bar's branch, where a click drops it. }
procedure TForm1.MenuBranchListClick(Sender: TObject);
var
  Mode: TGittanBranchListMode;
begin
  if FRepo.Root = '' then
    Exit;
  Mode := TGittanBranchListMode((Sender as TMenuItem).Tag);
  if (Mode in [blMerge, blRebase]) and
    ((FOperation <> '') or (FCommitJob <> nil) or (FRemoteJob <> nil) or (FBranch = '')) then
    Exit;
  ShowBranchList(Mode, FStatus.PartScreenRect(spBranch));
end;

procedure TForm1.MenuNewBranchClick(Sender: TObject);
begin
  if (FRepo.Root <> '') and (FOperation = '') then
    BranchAction(BranchNew);
end;

{ A rebase of the current branch onto ARef: it says how many commits
  are replayed, and that the next push must be forced when some of
  them are pushed already, since they are rewritten. Local changes go
  along (--autostash). One that stops with conflicts leaves them to the
  Commit section, as a merge does. }
procedure TForm1.RebaseOntoAsk(const ARef: string);
var
  Branch, Msg: string;
  Count, Pushed: integer;
  Ok, Conflicts: boolean;
begin
  Branch := FBranch;
  if (FRepo.Root = '') or (Branch = '') or (FOperation <> '') or (FCommitJob <> nil) or
    (FRemoteJob <> nil) then
    Exit;
  if not FRepo.CommitsToRebase(ARef, Count, Pushed) then
  begin
    MessageDlg(rsCaFailed, FRepo.Error, mtError, [mbOK], 0);
    Exit;
  end;
  if Count = 0 then
  begin
    StatusNote(Format(rsBmRebaseNothing, [Branch, ARef]));
    Exit;
  end;
  if Count = 1 then
    Msg := Format(rsBmRebaseAskOne, [Branch, ARef, ARef])
  else
    Msg := Format(rsBmRebaseAsk, [Branch, ARef, Count, ARef]);
  if Pushed = 1 then
    Msg := Msg + ' ' + rsBmRebasePushedOne
  else if Pushed > 1 then
    Msg := Msg + ' ' + Format(rsBmRebasePushed, [Pushed]);
  if QuestionDlg(rsBmRebaseTitle, Msg, mtConfirmation, [mrYes, rsRebaseAction, 'IsDefault',
    mrCancel, rsCancelButton, 'IsCancel'], 0) <> mrYes then
    Exit;
  StopWatcher;
  Screen.Cursor := crHourGlass;
  try
    Ok := FRepo.RebaseOnto(ARef, Conflicts);
  finally
    Screen.Cursor := crDefault;
  end;
  FSummary.Notice := '';
  RefreshRepository;
  StartWatcher;
  if Ok then
    StatusNote(Format(rsBmRebased, [Branch, ARef]))
  else if Conflicts then
    StatusNote(rsCaConflicts, True)
  else
    MessageDlg(rsCaFailed, FRepo.Error, mtError, [mbOK], 0);
end;

{ ---------------------------------------------------------------------------
  Acting on what is compared
  ---------------------------------------------------------------------------
  While the base is a branch compared through its merge base with the
  current one (current...branch, what Show What <branch> Changed Since
  <current> shows: what merging it would bring), the base label in the
  summary and the status bar is a chip that drops down Merge <branch>
  into <current> and Rebase <current> onto <branch>, so looking comes
  first and the action is at hand. Not while git is in the middle of
  something or a job runs, nor for a pull request's or a blame range. }
function TForm1.BaseActionRef: string;
var
  Base, LeftSide: string;
  Dots: integer;
begin
  Result := '';
  Base := FRepo.Base;
  Dots := Pos('...', Base);
  if (FRepo.Root = '') or (FBranch = '') or (Dots = 0) or (Base = FPullRange) or
    (Base = FBlameRange) or (FOperation <> '') or (FCommitJob <> nil) or (FRemoteJob <> nil) then
    Exit;
  LeftSide := Copy(Base, 1, Dots - 1);
  if (LeftSide = FBranch) or (LeftSide = 'HEAD') then
    Result := Copy(Base, Dots + 3, MaxInt);
end;

procedure TForm1.BaseClick(const AScreenRect: TRect);
var
  Ref: string;
begin
  Ref := BaseActionRef;
  if Ref = '' then
    Exit;
  FBaseActionRef := Ref;
  FBasePopup.Clear;
  FBasePopup.AddHeader(Format(rsVsSince, [Ref, FBranch]));
  FBaseMergeIndex := FBasePopup.Add(Format(rsBmMerge, [Ref, FBranch]));
  FBaseRebaseIndex := FBasePopup.Add(Format(rsBmRebase, [FBranch, Ref]));
  FBasePopup.Popup(AScreenRect);
end;

procedure TForm1.SummaryBaseClick(Sender: TObject; const AScreenRect: TRect);
begin
  BaseClick(AScreenRect);
end;

{ The compared branch stays the base through the merge or rebase, so
  the summary shows what is left of the difference: nothing after a
  merge or a rebase that went through. }
procedure TForm1.BasePopupPick(Sender: TObject; AIndex: integer);
begin
  if (FBaseActionRef = '') or (BaseActionRef <> FBaseActionRef) then
    Exit;
  if AIndex = FBaseMergeIndex then
    MergeIntoCurrent(FBaseActionRef)
  else if AIndex = FBaseRebaseIndex then
    RebaseOntoAsk(FBaseActionRef);
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
