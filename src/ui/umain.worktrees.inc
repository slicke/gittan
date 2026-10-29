{ ---------------------------------------------------------------------------
  Worktrees
  ---------------------------------------------------------------------------
  Branch > Worktrees... drops the repository's worktrees (gittan.
  worktrees) from the status bar's branch: Add Worktree... first, then
  a row per worktree, the repository's own first, with its folder's
  name, and as its detail the branch (or the commit while HEAD is
  detached), "this one" for the one open here, "locked" and "folder is
  gone" where they apply. A pick opens the worktree in a tab (the
  window finds the tab that has it, else opens one); the one open here
  is checked. A right click offers Open in New Tab, Reveal in Finder,
  Lock or Unlock, Remove... (not the repository's own, nor the one
  open here) and Prune Worktrees, which forgets the ones whose folders
  are gone. Add Worktree... asks the folder (beside the repository,
  named after it, SuggestWorktreePath) and a branch: one that exists
  is checked out there, another is made from HEAD, none lets git name
  one after the folder; the new worktree opens in a tab. Remove asks
  first, and again with git's reason when the worktree has changes not
  committed or is locked, since only --force removes it then. }
const
  wtRowAdd = -1;
  wmOpen = 1;
  wmReveal = 2;
  wmLock = 3;
  wmUnlock = 4;
  wmRemove = 5;
  wmPrune = 6;

{ Whether AWorktree is the one open in this frame: its folder is the
  repository's root, or the root as the system resolves it. }
function TRepoFrame.IsThisWorktree(const AWorktree: TGittanWorktree): boolean;
var
  Root, Path: string;
begin
  Root := ExcludeTrailingPathDelimiter(FRepo.Root);
  Path := ExcludeTrailingPathDelimiter(AWorktree.Path);
  Result := SameFileName(Root, Path) or SameFileName(ExpandFileName(Root), ExpandFileName(Path));
end;

procedure TRepoFrame.MenuWorktreesClick(Sender: TObject);
begin
  if FRepo.Root <> '' then
    ShowWorktreeList(MenuListAnchor);
end;

procedure TRepoFrame.ShowWorktreeList(const AScreenRect: TRect);
var
  i: integer;
  Detail, Err: string;
begin
  if FRepo.Root = '' then
    Exit;
  if not ListWorktrees(FRepo.Root, FListedWorktrees, Err) then
  begin
    BannerError(rsWtListFailed, Err);
    Exit;
  end;
  FWorktreePopup.Clear;
  FWorktreePopup.Add(rsWtAddRow, '', False, wtRowAdd);
  FWorktreePopup.AddHeader(rsWtHeader);
  for i := 0 to High(FListedWorktrees) do
    with FListedWorktrees[i] do
    begin
      if Bare then
        Detail := rsWtBare
      else if Branch <> '' then
        Detail := Branch
      else if Head <> '' then
        Detail := Format(rsWtDetached, [Copy(Head, 1, 7)])
      else
        Detail := '';
      if IsThisWorktree(FListedWorktrees[i]) then
        Detail := Detail + ' · ' + rsWtThisOne
      else if Main then
        Detail := Detail + ' · ' + rsWtMain;
      if Locked then
        Detail := Detail + ' · ' + rsWtLocked;
      if Prunable then
        Detail := Detail + ' · ' + rsWtGone;
      FWorktreePopup.Add(ExtractFileName(ExcludeTrailingPathDelimiter(Path)), Detail,
        IsThisWorktree(FListedWorktrees[i]), i);
    end;
  FWorktreePopup.Popup(AScreenRect);
end;

procedure TRepoFrame.WorktreePopupPick(Sender: TObject; AIndex: integer);
var
  Row: PtrInt;
begin
  Row := FWorktreePopup.TagOf(AIndex);
  if Row = wtRowAdd then
    AddWorktreeAsk
  else if (Row >= 0) and (Row <= High(FListedWorktrees)) then
    OpenWorktree(FListedWorktrees[Row]);
end;

{ The worktree in a tab; one whose folder is gone, or a bare one, has
  nothing to open. }
procedure TRepoFrame.OpenWorktree(const AWorktree: TGittanWorktree);
begin
  if AWorktree.Bare or AWorktree.Prunable or not DirectoryExists(AWorktree.Path) then
  begin
    StatusNote(Format(rsWtCannotOpen, [AWorktree.Path]), True);
    Exit;
  end;
  if IsThisWorktree(AWorktree) then
    Exit;
  FWindow.OpenRepository(AWorktree.Path);
end;

procedure TRepoFrame.WorktreeContext(Sender: TObject; AIndex: integer;
  const AScreenPos: TPoint);
var
  Row: PtrInt;
  This, Gone, Prunable: boolean;
  i: integer;

  procedure Add(const ACaption: string; ATag: integer; AEnabled: boolean);
  begin
    AddMenuItem(FWorktreeMenu.Items, ACaption, ATag, AEnabled, @WorktreeMenuClick);
  end;

begin
  Row := FWorktreePopup.TagOf(AIndex);
  if (Row < 0) or (Row > High(FListedWorktrees)) then
    Exit;
  FMenuWorktree := FListedWorktrees[Row];
  This := IsThisWorktree(FMenuWorktree);
  Gone := FMenuWorktree.Prunable or not DirectoryExists(FMenuWorktree.Path);
  Prunable := False;
  for i := 0 to High(FListedWorktrees) do
    if FListedWorktrees[i].Prunable then
      Prunable := True;
  FWorktreeMenu.Items.Clear;
  Add(rsWtOpen, wmOpen, not This and not Gone and not FMenuWorktree.Bare);
  Add(rsReveal, wmReveal, not Gone);
  FWorktreeMenu.Items.Add(NewLine);
  if FMenuWorktree.Locked then
    Add(rsWtUnlock, wmUnlock, not FMenuWorktree.Main)
  else
    Add(rsWtLock, wmLock, not FMenuWorktree.Main);
  Add(rsWtRemove, wmRemove, not FMenuWorktree.Main and not This);
  FWorktreeMenu.Items.Add(NewLine);
  Add(rsWtPrune, wmPrune, Prunable);
  FWorktreeMenu.PopUp(AScreenPos.X, AScreenPos.Y);
end;

procedure TRepoFrame.WorktreeMenuClick(Sender: TObject);
var
  Wt: TGittanWorktree;
  Err: string;
begin
  Wt := FMenuWorktree;
  if (FRepo.Root = '') or (Wt.Path = '') then
    Exit;
  FWorktreePopup.Close;
  case (Sender as TMenuItem).Tag of
    wmOpen:
      OpenWorktree(Wt);
    wmReveal:
      {$IFDEF DARWIN}
      RunDetached('open', ['-R', ExcludeTrailingPathDelimiter(Wt.Path)]);
      {$ELSE}
      {$IFDEF WINDOWS}
      RunDetached('explorer.exe', ['/select,' + ExcludeTrailingPathDelimiter(Wt.Path)]);
      {$ELSE}
      RunDetached('xdg-open', [ExtractFileDir(ExcludeTrailingPathDelimiter(Wt.Path))]);
      {$ENDIF}
      {$ENDIF}
    wmLock, wmUnlock:
      if LockWorktree(FRepo.Root, Wt.Path, (Sender as TMenuItem).Tag = wmLock, Err) then
      begin
        if (Sender as TMenuItem).Tag = wmLock then
          StatusNote(Format(rsWtLockedNote, [ExtractFileName(ExcludeTrailingPathDelimiter(Wt.Path))]))
        else
          StatusNote(Format(rsWtUnlockedNote, [ExtractFileName(ExcludeTrailingPathDelimiter(Wt.Path))]));
      end
      else
        BannerError(rsWtFailed, Err);
    wmRemove:
      RemoveWorktreeAsk(Wt);
    wmPrune:
      if PruneWorktrees(FRepo.Root, Err) then
        StatusNote(rsWtPruned)
      else
        BannerError(rsWtFailed, Err);
  end;
end;

{ The folder as AddWorktreeAsk takes it: relative to the folder the
  repository is in. }
function WorktreeFolder(const ARoot, AFolder: string): string;
begin
  Result := Trim(AFolder);
  if (Result <> '') and not FilenameIsAbsolute(Result) then
    Result := ExpandFileName(IncludeTrailingPathDelimiter(ExtractFileDir(
      ExcludeTrailingPathDelimiter(ARoot))) + Result);
end;

{ The folder must not be there yet; a branch, when named, must be one
  git takes (an existing one is checked out, another made). }
function TRepoFrame.CheckWorktree(const AValues: array of string): string;
var
  Folder, Branch: string;
begin
  Result := '';
  Folder := WorktreeFolder(FRepo.Root, AValues[0]);
  if DirectoryExists(Folder) or FileExists(Folder) then
    Exit(Format(rsWtFolderExists, [Folder]));
  Branch := Trim(AValues[1]);
  if (Branch <> '') and not FRepo.IsBranchName(Branch) then
    Result := rsAskBadBranch;
end;

procedure TRepoFrame.AddWorktreeAsk;
var
  Values: array of string;
  Folder, Branch, Err: string;
  New: boolean;
begin
  if FRepo.Root = '' then
    Exit;
  SetLength(Values, 2);
  Values[0] := SuggestWorktreePath(FRepo.Root, '');
  Values[1] := '';
  if not AskInput(rsWtAddTitle, '', [rsWtFolderPrompt, rsWtBranchPrompt], Values,
    @CheckWorktree, rsWtAddAction) then
    Exit;
  Folder := Trim(Values[0]);
  Branch := Trim(Values[1]);
  if Folder = '' then
    Exit;
  Folder := WorktreeFolder(FRepo.Root, Folder);
  if DirectoryExists(Folder) or FileExists(Folder) then
  begin
    BannerError(rsWtAddFailed, Format(rsWtFolderExists, [Folder]));
    Exit;
  end;
  { A branch that exists is checked out there; another is made from
    HEAD. }
  New := (Branch <> '') and not FRepo.HasCommit('refs/heads/' + Branch);
  Screen.Cursor := crHourGlass;
  try
    if not AddWorktree(FRepo.Root, Folder, Branch, New, '', Err) then
    begin
      BannerError(rsWtAddFailed, Err);
      Exit;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  StatusNote(Format(rsWtAdded, [ExtractFileName(ExcludeTrailingPathDelimiter(Folder))]));
  FWindow.OpenRepository(Folder);
end;

procedure TRepoFrame.RemoveWorktreeAsk(const AWorktree: TGittanWorktree);
var
  Folder, Err: string;
  Dirty: boolean;
begin
  if (FRepo.Root = '') or AWorktree.Main or IsThisWorktree(AWorktree) then
    Exit;
  Folder := ExtractFileName(ExcludeTrailingPathDelimiter(AWorktree.Path));
  { Its tab would be left on a folder that is gone, with any edit not
    saved there. }
  if FWindow.HasOpen(AWorktree.Path) then
  begin
    StatusNote(Format(rsWtRemoveOpen, [Folder]), True);
    Exit;
  end;
  if AskDlg(rsWtRemoveTitle, Format(rsWtRemoveAsk, [Folder, AWorktree.Path]), mtWarning,
    [mrYes, rsWtRemoveAction, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes then
    Exit;
  if not RemoveWorktree(FRepo.Root, AWorktree.Path, False, Err, Dirty) then
  begin
    if not Dirty then
    begin
      BannerError(rsWtFailed, Err);
      Exit;
    end;
    { Changes not committed, or a lock: git wants --force, which loses
      them. }
    if AskDlg(rsWtRemoveTitle, Format(rsWtRemoveForceAsk, [Folder, Trim(Err)]), mtWarning,
      [mrYes, rsWtRemoveAnyway, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes then
      Exit;
    if not RemoveWorktree(FRepo.Root, AWorktree.Path, True, Err, Dirty) then
    begin
      BannerError(rsWtFailed, Err);
      Exit;
    end;
  end;
  StatusNote(Format(rsWtRemoved, [Folder]));
end;
