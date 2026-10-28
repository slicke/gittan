{ ---------------------------------------------------------------------------
  Git LFS locks
  ---------------------------------------------------------------------------
  Included by umain.pp. The files that may be locked (FLfsLockable: in
  Git LFS or with the attribute lockable) come with the Git LFS check
  (LfsCheckDone); while there are any and git-lfs is installed, a job
  reads who holds which lock on the LFS server (TGittanLfsLocksJob,
  FLfsLocks), again after a fetch, the background fetch, a lock and an
  unlock. The file menu has Lock File for such a file no one holds,
  Unlock File for one the user holds and Force Unlock for another
  user's (asked first), each a remote job (rkLfsLock, rkLfsUnlock,
  rkLfsForceUnlock); the header says who holds the file shown when it
  is not the user (LockNote). File > Git LFS Locks... lists every lock,
  the user's first: a pick shows the file, a right click offers the
  unlock. See spec/special-views.md. }

const
  lmUnlock = 1;
  lmForceUnlock = 2;
  lmShow = 3;

{ Starts the job, or has it read again when it is done, since a lock
  may have changed meanwhile. Not without git-lfs, which every fetch
  would otherwise run in vain. }
procedure TRepoFrame.StartLfsLocks;
begin
  if (FRepo.Root = '') or not FLfsInstalled or
    (FLfsLockable.Count = 0) and (FLfsLocks = nil) then
    Exit;
  if FLfsLocksJob <> nil then
  begin
    FLfsLocksAgain := True;
    Exit;
  end;
  FLfsLocksAgain := False;
  FLfsLocksJob := TGittanLfsLocksJob.Create(FRepo.Root);
  FLfsLocksJob.OnDone := @LfsLocksDone;
  FLfsLocksJob.Start;
end;

procedure TRepoFrame.LfsLocksDone(Sender: TObject);
var
  Job: TGittanLfsLocksJob;
begin
  Job := TGittanLfsLocksJob(Sender);
  if Job <> FLfsLocksJob then
    Exit;
  FLfsLocksJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  if Job.Root <> FRepo.Root then
    Exit;
  { Offline, or a server without locks: what was known stays. }
  if Job.Ok then
  begin
    FLfsLocks := Job.Locks;
    LockNote;
  end;
  if FView = gvBlob then
    BlobActions;
  if FLfsLocksAgain then
    StartLfsLocks;
end;

{ The pills of a file of the Files page: Open and Save As..., and for
  one of HEAD's that may be locked or is, Lock, Unlock or Force Unlock,
  so a file is locked before it is changed (git-lfs keeps a lockable
  one read-only until then). }
procedure TRepoFrame.BlobActions;
var
  i: integer;
begin
  i := LockOf(FBlobPath);
  { Lock is not offered without git-lfs, which it would only fail for;
    the banner says it is missing. }
  if not FFilesHead or (i < 0) and (not FLfsInstalled or
    (FLfsLockable.IndexOf(FBlobPath) < 0)) then
    FHeader.SetActions([rsBlobOpen, rsBlobSaveAs])
  else if i < 0 then
    FHeader.SetActions([rsBlobOpen, rsBlobSaveAs, rsLfsLockAction])
  else if FLfsLocks[i].Ours then
    FHeader.SetActions([rsBlobOpen, rsBlobSaveAs, rsLfsUnlockAction])
  else
    FHeader.SetActions([rsBlobOpen, rsBlobSaveAs, rsLfsForceUnlockAction]);
  if FHeader.ActionCount > 2 then
    FHeader.SetActionEnabled(2, (FRemoteJob = nil) and (FCommitJob = nil));
end;

procedure TRepoFrame.BlobLockAction;
begin
  if (FView <> gvBlob) or not FFilesHead or (FBlobPath = '') then
    Exit;
  if LockOf(FBlobPath) >= 0 then
    UnlockAsk(FBlobPath)
  else
    StartRemote(rkLfsLock, pmAuto, FBlobPath);
end;

{ Dropped rather than waited for, as the Git LFS check is. }
procedure TRepoFrame.StopLfsLocks;
begin
  FLfsLocksAgain := False;
  if FLfsLocksJob <> nil then
  begin
    FLfsLocksJob.Stop(False);
    FBlameZombies.Add(FLfsLocksJob);
    FLfsLocksJob := nil;
  end;
end;

{ The lock on APath, from the root, -1 when no one holds it. }
function TRepoFrame.LockOf(const APath: string): integer;
begin
  Result := LfsLockIndex(FLfsLocks, APath);
end;

{ The file shown, from the root, as the locks name it: the tree's, one
  of HEAD's on the Files page, or the file of the repository open on
  its own (File > Open). }
function TRepoFrame.ShownLockPath: string;
begin
  Result := FCurrentPath;
  if (Result = '') and (FView = gvBlob) and FFilesHead then
    Result := FBlobPath;
  if (Result = '') and (FView = gvFile) and (Edit.FileName <> '') and (FRepo.Root <> '') then
    Result := StringReplace(ExtractRelativePath(IncludeTrailingPathDelimiter(FRepo.Root),
      Edit.FileName), PathDelim, '/', [rfReplaceAll]);
end;

{ Another user's lock on the file shown, in the header; a note of its
  own (FLockNote) is taken away when the lock goes, another is left.
  The note it took the place of (FLockNoteWas: the file changed on
  disk) comes back then. }
procedure TRepoFrame.LockNote;
var
  i: integer;
  Note: string;
begin
  i := LockOf(ShownLockPath);
  Note := '';
  if (i >= 0) and not FLfsLocks[i].Ours then
    Note := Format(rsLfsLockedBy, [FLfsLocks[i].Owner]);
  if Note <> '' then
  begin
    if (FLockNote = '') or (FHeader.Note <> FLockNote) then
      FLockNoteWas := FHeader.Note;
    FHeader.SetNote(Note);
  end
  else if (FLockNote <> '') and (FHeader.Note = FLockNote) then
    FHeader.SetNote(FLockNoteWas);
  if Note = '' then
    FLockNoteWas := '';
  FLockNote := Note;
end;

{ The file menu's lock items for FContextPath. }
procedure TRepoFrame.UpdateLockItems;
var
  i: integer;
  Lockable: boolean;
begin
  i := LockOf(FContextPath);
  Lockable := FLfsInstalled and (FContextPath <> '') and
    (FLfsLockable.IndexOf(FContextPath) >= 0);
  FLfsLockItem.Visible := Lockable and (i < 0);
  FLfsUnlockItem.Visible := i >= 0;
  if i >= 0 then
    if FLfsLocks[i].Ours then
      FLfsUnlockItem.Caption := rsLfsUnlockItem
    else
      FLfsUnlockItem.Caption := Format(rsLfsForceUnlockItem,
        [StringReplace(FLfsLocks[i].Owner, '&', '&&', [rfReplaceAll])]);
  FLfsLockItem.Enabled := (FRemoteJob = nil) and (FCommitJob = nil);
  FLfsUnlockItem.Enabled := FLfsLockItem.Enabled;
  FLfsLockSepItem.Visible := FLfsLockItem.Visible or FLfsUnlockItem.Visible;
end;

procedure TRepoFrame.MenuLfsLockClick(Sender: TObject);
begin
  if FContextPath <> '' then
    StartRemote(rkLfsLock, pmAuto, FContextPath);
end;

procedure TRepoFrame.MenuLfsUnlockClick(Sender: TObject);
begin
  if FContextPath <> '' then
    UnlockAsk(FContextPath);
end;

{ The user's own lock goes at once; another user's is asked first, as
  taking it away may lose them their work. }
procedure TRepoFrame.UnlockAsk(const APath: string);
var
  i: integer;
begin
  i := LockOf(APath);
  if i < 0 then
    Exit;
  if FLfsLocks[i].Ours then
    StartRemote(rkLfsUnlock, pmAuto, APath)
  else if QuestionDlg(rsLfsForceUnlockTitle, Format(rsLfsForceUnlockAsk,
    [APath, FLfsLocks[i].Owner]), mtWarning, [mrYes, rsLfsForceUnlockAction,
    mrCancel, rsCancelButton, 'IsDefault', 'IsCancel'], 0) = mrYes then
    StartRemote(rkLfsForceUnlock, pmAuto, APath);
end;

{ The end of a lock or an unlock: the status bar says it, a failure
  (held by someone else, changes not committed) is the remote notice,
  and the locks are read again either way. }
procedure TRepoFrame.LfsLockJobDone(AJob: TGittanRemoteJob);
begin
  if not AJob.Ok then
    ShowRemoteFailure(AJob, False)
  else if AJob.Kind = rkLfsLock then
    StatusNote(Format(rsLfsLocked, [AJob.Arg]))
  else
    StatusNote(Format(rsLfsUnlocked, [AJob.Arg]));
  StartLfsLocks;
end;

procedure TRepoFrame.MenuLfsLocksClick(Sender: TObject);
begin
  if FRepo.Root <> '' then
    ShowLfsLocks(FStatus.PartScreenRect(spBranch));
end;

{ The user's locks first, then everyone else's, each by path. }
procedure TRepoFrame.ShowLfsLocks(const AScreenRect: TRect);
var
  Detail: string;

  procedure AddRows(AOurs: boolean);
  var
    j: integer;
  begin
    for j := 0 to High(FLfsLocks) do
      if FLfsLocks[j].Ours = AOurs then
      begin
        if AOurs then
          Detail := rsLfsLockYou
        else
          Detail := FLfsLocks[j].Owner;
        if FLfsLocks[j].LockedAt > 0 then
          Detail := Detail + ' · ' + BlameAge(DateTimeToUnix(FLfsLocks[j].LockedAt),
            DateTimeToUnix(Now, False));
        FLfsLocksPopup.Add(FLfsLocks[j].Path, Detail, False, j);
      end;
  end;

begin
  FLfsLocksPopup.Clear;
  FListedLocks := Copy(FLfsLocks);
  if Length(FLfsLocks) = 0 then
    FLfsLocksPopup.AddHeader(rsLfsNoLocks)
  else
    FLfsLocksPopup.AddHeader(rsLfsLocksHeader);
  AddRows(True);
  AddRows(False);
  FLfsLocksPopup.Popup(AScreenRect);
  { Shown as known; read again for the next time. }
  StartLfsLocks;
end;

procedure TRepoFrame.LfsLocksPopupPick(Sender: TObject; AIndex: integer);
var
  Row: PtrInt;
begin
  Row := FLfsLocksPopup.TagOf(AIndex);
  if (Row >= 0) and (Row <= High(FListedLocks)) then
    ShowRepoFile(FListedLocks[Row].Path);
end;

procedure TRepoFrame.LfsLocksContext(Sender: TObject; AIndex: integer;
  const AScreenPos: TPoint);
var
  Row: PtrInt;
  Idle: boolean;
begin
  Row := FLfsLocksPopup.TagOf(AIndex);
  if (Row < 0) or (Row > High(FListedLocks)) then
    Exit;
  FMenuLock := FListedLocks[Row].Path;
  Idle := (FRemoteJob = nil) and (FCommitJob = nil);
  FLfsLocksMenu.Items.Clear;
  AddMenuItem(FLfsLocksMenu.Items, rsLfsShowFile, lmShow, True, @LfsLocksMenuClick);
  FLfsLocksMenu.Items.Add(NewLine);
  if FListedLocks[Row].Ours then
    AddMenuItem(FLfsLocksMenu.Items, rsLfsUnlockItem, lmUnlock, Idle, @LfsLocksMenuClick)
  else
    AddMenuItem(FLfsLocksMenu.Items, Format(rsLfsForceUnlockItem,
      [StringReplace(FListedLocks[Row].Owner, '&', '&&', [rfReplaceAll])]), lmForceUnlock,
      Idle, @LfsLocksMenuClick);
  FLfsLocksMenu.PopUp(AScreenPos.X, AScreenPos.Y);
end;

procedure TRepoFrame.LfsLocksMenuClick(Sender: TObject);
var
  Path: string;
begin
  Path := FMenuLock;
  if (FRepo.Root = '') or (Path = '') then
    Exit;
  FLfsLocksPopup.Close;
  case (Sender as TMenuItem).Tag of
    lmShow: ShowRepoFile(Path);
    lmUnlock, lmForceUnlock: UnlockAsk(Path);
  end;
end;

{ A commit of files another user holds is asked first: git-lfs's
  pre-push hook refuses to push it while they hold them. An amend keeps
  what HEAD changed in the commit, so those paths count too. True to go
  on. }
function TRepoFrame.LockedCommitAsk(APaths: TStrings; AAmend: boolean): boolean;
const
  MaxListed = 8;
var
  Path, Msg: string;
  Held, Paths: TStringList;
  i, First: integer;
begin
  Result := True;
  if FLfsLocks = nil then
    Exit;
  First := -1;
  Held := TStringList.Create;
  Paths := TStringList.Create;
  try
    Paths.Sorted := True;
    Paths.Duplicates := dupIgnore;
    Paths.CaseSensitive := True;
    if AAmend then
      FRepo.HeadPaths(Paths);
    Paths.AddStrings(APaths);
    for Path in Paths do
    begin
      i := LockOf(Path);
      if (i >= 0) and not FLfsLocks[i].Ours then
      begin
        if First < 0 then
          First := i;
        Held.Add(Format(rsLfsLockedCommitLine, [Path, FLfsLocks[i].Owner]));
      end;
    end;
    if Held.Count = 0 then
      Exit;
    if Held.Count = 1 then
      Msg := Format(rsLfsLockedCommitOne, [FLfsLocks[First].Path, FLfsLocks[First].Owner])
    else
    begin
      Msg := Format(rsLfsLockedCommitMany, [Held.Count]) + LineEnding;
      for i := 0 to Min(Held.Count, MaxListed) - 1 do
        Msg := Msg + LineEnding + Held[i];
      if Held.Count > MaxListed then
        Msg := Msg + LineEnding + Format(rsLfsLockedCommitMore, [Held.Count - MaxListed]);
    end;
  finally
    Paths.Free;
    Held.Free;
  end;
  Result := QuestionDlg(rsLfsLockedCommitTitle, Msg, mtWarning, [mrYes, rsCommitAnyway,
    mrCancel, rsCancelButton, 'IsDefault', 'IsCancel'], 0) = mrYes;
end;
