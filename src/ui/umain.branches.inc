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
  would show) or compare the work tree with it, rename or delete it, set
  its upstream (ShowUpstreamList), and delete it on its remote. Deleting
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
  bmUpstream = 10;

procedure TRepoFrame.BranchContext(Sender: TObject; AIndex: integer; const AScreenPos: TPoint);
var
  BranchName, Ref, Up: string;
  Busy, IsRemote: boolean;

  { A name in a caption, its ampersands doubled. }
  function Amp(const AName: string): string;
  begin
    Result := StringReplace(AName, '&', '&&', [rfReplaceAll]);
  end;

  procedure Add(const ACaption: string; ATag: integer; AEnabled: boolean);
  begin
    AddMenuItem(FBranchMenu.Items, ACaption, ATag, AEnabled, @BranchMenuClick);
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
  Busy := RepoBusy;
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
    Add(rsBmUpstream, bmUpstream, True);
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

procedure TRepoFrame.BranchMenuClick(Sender: TObject);
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
    bmUpstream: ShowUpstreamList(BranchName, FStatus.PartScreenRect(spBranch));
    bmDeleteRemote:
      if QuestionDlg(rsBmDeleteRemoteTitle, Format(rsBmDeleteRemoteAsk, [FMenuBranchUpstream]),
        mtWarning, [mrYes, rsBmDeleteAction, mrCancel, rsCancelButton, 'IsCancel',
        'IsDefault'], 0) = mrYes then
        StartRemote(rkDeleteRemote, pmAuto, FMenuBranchUpstream);
  end;
end;

{ The branch list's own rows: New Branch... and Delete Gone Branches.... }
function TRepoFrame.BranchAction(const AName: string): boolean;
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
  NewBranchAsk(rsBmNewPrompt, 'HEAD');
end;

procedure TRepoFrame.RenameBranchAsk(const AName: string);
var
  Values: array of string;
begin
  SetLength(Values, 1);
  Values[0] := AName;
  if not InputQuery(rsBmRenameTitle, [Format(rsBmRenamePrompt, [AName])], Values) or
    (Trim(Values[0]) = '') or (Trim(Values[0]) = AName) then
    Exit;
  StopWatcher;
  try
    if FRepo.RenameBranch(AName, Trim(Values[0])) then
    begin
      RefreshRepository;
      StatusNote(Format(rsBmRenamed, [AName, Trim(Values[0])]));
    end
    else
      BannerError(rsCaFailed, FRepo.Error);
  finally
    StartWatcher;
  end;
end;

{ Asks, deletes with -d, and asks again with -D when git says the
  branch is not merged. }
procedure TRepoFrame.DeleteBranchAsk(const AName: string);
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
    BannerError(rsCaFailed, FRepo.Error);
end;

{ The branches whose upstream is gone, the current one left out: the
  merged ones go with -d, then those that are not merged, listed, after
  a second question. }
procedure TRepoFrame.DeleteGoneBranches;
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
procedure TRepoFrame.CompareSince(const ARef: string);
begin
  if (FOperation = '') and FRepo.HasCommit('refs/heads/' + FBranch) then
    SetBase(FBranch + '...' + ARef)
  else
    SetBase('HEAD...' + ARef);
end;

{ What the current branch did since it left ARef, through their merge
  base, as a pull request to ARef would show. }
procedure TRepoFrame.CompareCurrentSince(const ARef: string);
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
procedure TRepoFrame.UpdateBranchItems;
var
  Has, Busy: boolean;
  Current: string;
begin
  if FMergeItem = nil then
    Exit;
  Has := (FRepo <> nil) and (FRepo.Root <> '');
  Busy := RepoBusy;
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
  FUpstreamItem.Caption := Format(rsBmUpstreamItem, [Current]);
  FUpstreamItem.Enabled := Has and (FBranch <> '') and (FOperation = '');
  FTagsItem.Enabled := Has;
  FNewTagItem.Enabled := Has;
  FPushTagsItem.Enabled := Has and (FRemoteJob = nil) and (FCommitJob = nil);
  FReflogItem.Enabled := Has;
  FWorktreesItem.Enabled := Has;
  FNewPullItem.Enabled := CanCreatePull(FBranch);
end;

{ ---------------------------------------------------------------------------
  The upstream of a branch
  ---------------------------------------------------------------------------
  Set Upstream... drops a list for a local branch: per remote that has
  no branch of its name, Push to <remote>/<branch>, which pushes it there
  and tracks it (a remote job); Stop Tracking its upstream when it has
  one; then the remote-tracking branches, the upstream checked, a pick
  of which tracks it without pushing. }
procedure TRepoFrame.ShowUpstreamList(const ABranch: string; const AScreenRect: TRect);
var
  Remotes, Local, Remote: TStringList;
  Up: string;
  i: integer;

  procedure AddRow(const ARow: string);
  begin
    FUpstreamRows.Add(ARow);
  end;

begin
  if (FRepo.Root = '') or (ABranch = '') then
    Exit;
  if not FRepo.HasCommit('refs/heads/' + ABranch) then
  begin
    StatusNote(rsUpstreamDetached, True);
    Exit;
  end;
  Remotes := TStringList.Create;
  Local := TStringList.Create;
  Remote := TStringList.Create;
  try
    if not FRepo.Remotes(Remotes) or not FRepo.Branches(Local, Remote) then
    begin
      BannerError(rsCaFailed, FRepo.Error);
      Exit;
    end;
    if Remotes.Count = 0 then
    begin
      StatusNote(rsNoRemote, True);
      Exit;
    end;
    Up := FRepo.Upstream(ABranch);
    FUpstreamBranch := ABranch;
    FUpstreamPopup.Clear;
    FUpstreamRows.Clear;
    FUpstreamPopup.AddHeader(Format(rsUpstreamHeader, [ABranch]));
    AddRow('');
    if (FRemoteJob = nil) and (FCommitJob = nil) then
      for i := 0 to Remotes.Count - 1 do
        if Remote.IndexOf(Remotes[i] + '/' + ABranch) < 0 then
        begin
          FUpstreamPopup.Add(Format(rsUpstreamPush, [Remotes[i], ABranch]), rsPushNewBranch);
          AddRow('+' + Remotes[i]);
        end;
    if Up <> '' then
    begin
      FUpstreamPopup.Add(Format(rsUpstreamStop, [Up]));
      AddRow('-');
    end;
    if Remote.Count > 0 then
    begin
      FUpstreamPopup.AddHeader(rsUpstreamTrack);
      AddRow('');
    end;
    for i := 0 to Remote.Count - 1 do
    begin
      FUpstreamPopup.Add(Remote[i], '', Remote[i] = Up);
      AddRow('=' + Remote[i]);
    end;
    FUpstreamPopup.Popup(AScreenRect);
  finally
    Remotes.Free;
    Local.Free;
    Remote.Free;
  end;
end;

procedure TRepoFrame.UpstreamPopupPick(Sender: TObject; AIndex: integer);
var
  Row, Branch, Ref: string;
begin
  if (AIndex < 0) or (AIndex >= FUpstreamRows.Count) or (FRepo.Root = '') then
    Exit;
  Row := FUpstreamRows[AIndex];
  Branch := FUpstreamBranch;
  if (Row = '') or (Branch = '') then
    Exit;
  Ref := Copy(Row, 2, MaxInt);
  case Row[1] of
    '+': StartRemote(rkPushBranch, pmAuto, Branch, Ref);
    '-':
      if FRepo.SetUpstream(Branch, '') then
      begin
        RefreshRepository;
        StatusNote(Format(rsUpstreamStopped, [Branch]));
      end
      else
        BannerError(rsCaFailed, FRepo.Error);
    '=':
      if FRepo.SetUpstream(Branch, Ref) then
      begin
        RefreshRepository;
        StatusNote(Format(rsUpstreamSet, [Branch, Ref]));
      end
      else
        BannerError(rsCaFailed, FRepo.Error);
  end;
end;

procedure TRepoFrame.MenuUpstreamClick(Sender: TObject);
begin
  if (FRepo.Root <> '') and (FBranch <> '') then
    ShowUpstreamList(FBranch, FStatus.PartScreenRect(spBranch));
end;

procedure TRepoFrame.BranchMenuOpen(Sender: TObject);
begin
  UpdateBranchItems;
end;

{ The list drops from the status bar's branch, where a click drops it. }
procedure TRepoFrame.MenuBranchListClick(Sender: TObject);
var
  Mode: TGittanBranchListMode;
begin
  if FRepo.Root = '' then
    Exit;
  Mode := TGittanBranchListMode((Sender as TMenuItem).Tag);
  if (Mode in [blMerge, blRebase]) and
    (RepoBusy or (FBranch = '')) then
    Exit;
  ShowBranchList(Mode, FStatus.PartScreenRect(spBranch));
end;

procedure TRepoFrame.MenuNewBranchClick(Sender: TObject);
begin
  if (FRepo.Root <> '') and (FOperation = '') then
    BranchAction(BranchNew);
end;

{ A rebase of the current branch onto ARef: it says how many commits
  are replayed, and that the next push must be forced when some of
  them are pushed already, since they are rewritten. Local changes go
  along (--autostash). One that stops with conflicts leaves them to the
  Commit section, as a merge does. Choose Commits... opens the
  interactive rebase's dialog with the same commits instead. }
procedure TRepoFrame.RebaseOntoAsk(const ARef: string);
var
  Branch, Msg: string;
  Count, Pushed: integer;
  Ok, Conflicts: boolean;
begin
  Branch := FBranch;
  if not RepoReady or (Branch = '') then
    Exit;
  if not FRepo.CommitsToRebase(ARef, Count, Pushed) then
  begin
    BannerError(rsCaFailed, FRepo.Error);
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
  case QuestionDlg(rsBmRebaseTitle, Msg, mtConfirmation, [mrYes, rsRebaseAction, 'IsDefault',
    mrNo, rsRebaseChoose, mrCancel, rsCancelButton, 'IsCancel'], 0) of
    mrNo:
    begin
      RebaseInteractiveAsk(ARef, ARef, False);
      Exit;
    end;
    mrYes: ;
    else
      Exit;
  end;
  StopWatcher;
  try
    Screen.Cursor := crHourGlass;
    try
      Ok := FRepo.RebaseOnto(ARef, Conflicts);
    finally
      Screen.Cursor := crDefault;
    end;
    FSummary.Notice := '';
    RefreshRepository;
  finally
    StartWatcher;
  end;
  if Ok then
    StatusNote(Format(rsBmRebased, [Branch, ARef]))
  else if Conflicts then
    StatusNote(rsCaConflicts, True)
  else
    BannerError(rsCaFailed, FRepo.Error);
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
function TRepoFrame.BaseActionRef: string;
var
  Base, LeftSide: string;
  Dots: integer;
begin
  Result := '';
  Base := FRepo.Base;
  Dots := Pos('...', Base);
  if (FRepo.Root = '') or (FBranch = '') or (Dots = 0) or (Base = FPullRange) or
    (Base = FBlameRange) or RepoBusy then
    Exit;
  LeftSide := Copy(Base, 1, Dots - 1);
  if (LeftSide = FBranch) or (LeftSide = 'HEAD') then
    Result := Copy(Base, Dots + 3, MaxInt);
end;

{ A commit compared with its parent (a click in the commit graph, the
  blame band or the summary's commits), with its card in the summary. }
function TRepoFrame.BlameShown: boolean;
begin
  Result := (FRepo.Root <> '') and (FBlameRange <> '') and (FRepo.Base = FBlameRange) and
    (FBlameCommit.Hash <> '');
end;

procedure TRepoFrame.SummaryBackClick(Sender: TObject);
begin
  SetBase('');
end;

procedure TRepoFrame.BaseClick(const AScreenRect: TRect);
var
  Ref: string;
begin
  FBaseBackIndex := -1;
  FBaseCopyIndex := -1;
  if StashOfBase >= 0 then
  begin
    StashBaseClick(AScreenRect);
    Exit;
  end;
  if BlameShown then
  begin
    FBaseStashId := '';
    FBaseActionRef := '';
    FBasePopup.Clear;
    FBasePopup.AddHeader(Format(rsCommit, [FBlameCommit.Short]));
    FBaseBackIndex := FBasePopup.Add(rsBackToTree);
    FBaseCopyIndex := FBasePopup.Add(rsCopyCommitId);
    FBasePopup.Popup(AScreenRect);
    Exit;
  end;
  Ref := BaseActionRef;
  if Ref = '' then
    Exit;
  FBaseStashId := '';
  FBaseActionRef := Ref;
  FBasePopup.Clear;
  FBasePopup.AddHeader(Format(rsVsSince, [Ref, FBranch]));
  FBaseMergeIndex := FBasePopup.Add(Format(rsBmMerge, [Ref, FBranch]));
  FBaseRebaseIndex := FBasePopup.Add(Format(rsBmRebase, [FBranch, Ref]));
  FBasePopup.Popup(AScreenRect);
end;

procedure TRepoFrame.SummaryBaseClick(Sender: TObject; const AScreenRect: TRect);
begin
  BaseClick(AScreenRect);
end;

{ The compared branch stays the base through the merge or rebase, so
  the summary shows what is left of the difference: nothing after a
  merge or a rebase that went through. }
procedure TRepoFrame.BasePopupPick(Sender: TObject; AIndex: integer);
begin
  if FBaseStashId <> '' then
  begin
    StashBasePick(AIndex);
    Exit;
  end;
  if (FBaseBackIndex >= 0) and (AIndex = FBaseBackIndex) then
  begin
    if BlameShown then
      SetBase('');
    Exit;
  end;
  if (FBaseCopyIndex >= 0) and (AIndex = FBaseCopyIndex) then
  begin
    if BlameShown then
      Clipboard.AsText := FBlameCommit.Hash;
    Exit;
  end;
  if (FBaseActionRef = '') or (BaseActionRef <> FBaseActionRef) then
    Exit;
  if AIndex = FBaseMergeIndex then
    MergeIntoCurrent(FBaseActionRef)
  else if AIndex = FBaseRebaseIndex then
    RebaseOntoAsk(FBaseActionRef);
end;

{ The count is as of the last fetch, so the default branch is fetched
  first, and the rebase or merge is of what the remote has now. }
procedure TRepoFrame.SummaryBehindAction(Sender: TObject; ARebase: boolean);
begin
  if not RepoReady or (FDefaultBranch = '') or (FBranch = '') then
    Exit;
  FAfterFetchRef := FDefaultBranch;
  FAfterFetchBranch := FBranch;
  FAfterFetchRebase := ARebase;
  StartRemote(rkFetch);
end;

procedure TRepoFrame.AfterFetch;
var
  Ref: string;
begin
  Ref := FAfterFetchRef;
  FAfterFetchRef := '';
  if (Ref = '') or (FAfterFetchBranch <> FBranch) or (FOperation <> '') then
    Exit;
  if FAfterFetchRebase then
    RebaseOntoAsk(Ref)
  else
    MergeIntoCurrent(Ref);
end;

{ A merge of ARef into the branch HEAD is on, with git's message; one
  that stops with conflicts leaves them to the Commit section. }
procedure TRepoFrame.MergeIntoCurrent(const ARef: string);
var
  Ok, Conflicts: boolean;
begin
  StopWatcher;
  try
    Screen.Cursor := crHourGlass;
    try
      Ok := FRepo.MergeRef(ARef, Conflicts);
    finally
      Screen.Cursor := crDefault;
    end;
    FSummary.Notice := '';
    RefreshRepository;
  finally
    StartWatcher;
  end;
  if Ok then
    StatusNote(Format(rsCaMerged, [ARef]))
  else if Conflicts then
    StatusNote(rsCaConflicts, True)
  else
    BannerError(rsCaFailed, FRepo.Error);
end;
