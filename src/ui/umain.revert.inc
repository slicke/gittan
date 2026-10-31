{ ---------------------------------------------------------------------------
  Reverting files
  ---------------------------------------------------------------------------
  Revert Changes... in the file menu (the tree, the summary's rows, the
  file header) puts a changed file back as HEAD has it, or every changed
  file under a folder of the tree; File > Revert File... does it to the
  file shown. A new or untracked file is deleted, a rename goes back.
  It asks first. Discard (umain.discard.inc) puts back one block against
  the version compared with; Revert is whole files against HEAD, so
  it is offered only while the work tree is compared
  with HEAD. Before anything changes, what was on disk is saved as blobs
  (TGittanRepo.RevertFiles), and File > Undo Revert writes the latest
  revert back. }

{ The changed files the file menu acts on: the file, or every one under
  the folder of the tree. }
procedure TRepoFrame.RevertTargets(AList: TStrings);
var
  i: integer;
  Prefix: string;
begin
  AList.Clear;
  if FContextFolder <> '' then
  begin
    Prefix := FContextFolder + '/';
    for i := 0 to High(FStats) do
      if Copy(FStats[i].Path, 1, Length(Prefix)) = Prefix then
        AList.Add(FStats[i].Path);
  end
  else if IsChangedPath(FContextPath) then
    AList.Add(FContextPath);
end;

function TRepoFrame.CanRevert: boolean;
begin
  Result := (FRepo.Root <> '') and (FRepo.Base = '') and (FCommitJob = nil) and
    (FRemoteJob = nil);
end;

procedure TRepoFrame.RevertPaths(APaths: TStrings; const ALabel: string);
var
  Saved: TStringList;
begin
  if not CanRevert or (APaths.Count = 0) then
    Exit;
  if AskDlg(rsRevertTitle, Format(rsRevertFilesAsk, [ALabel]), mtWarning,
    [mrYes, rsRevertFilesAction, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes then
    Exit;
  { The merge editor's ticks for the file go with the changes. }
  if (FMergePath <> '') and (APaths.IndexOf(FMergePath) >= 0) then
    ClearMerge;
  Saved := TStringList.Create;
  StopWatcher;
  try
    if FRepo.RevertFiles(APaths, Saved) then
    begin
      FRevertUndo.AddObject(ALabel, Saved);
      Saved := nil;
      StatusNote(Format(rsReverted, [ALabel]));
    end
    else
    begin
      { What was saved before git failed can still come back. }
      if Saved.Count > 0 then
      begin
        FRevertUndo.AddObject(ALabel, Saved);
        Saved := nil;
      end;
      BannerError(rsRevertFailed, FRepo.Error);
    end;
    Saved.Free;
    FSummary.Notice := '';
    RefreshRepository;
  finally
    StartWatcher;
  end;
  UpdateDiscardItems;
end;

procedure TRepoFrame.MenuRevertChangesClick(Sender: TObject);
var
  Paths: TStringList;
  Shown: string;
begin
  Paths := TStringList.Create;
  try
    RevertTargets(Paths);
    if Paths.Count = 1 then
      Shown := Paths[0]
    else
      Shown := Format(rsRevertCount, [Paths.Count, FContextFolder]);
    RevertPaths(Paths, Shown);
  finally
    Paths.Free;
  end;
end;

{ File > Revert File: the file the view shows. }
procedure TRepoFrame.MenuRevertFileClick(Sender: TObject);
var
  Paths: TStringList;
begin
  if not IsChangedPath(FCurrentPath) then
    Exit;
  Paths := TStringList.Create;
  try
    Paths.Add(FCurrentPath);
    RevertPaths(Paths, FCurrentPath);
  finally
    Paths.Free;
  end;
end;

procedure TRepoFrame.MenuUndoRevertClick(Sender: TObject);
var
  Saved: TStringList;
  Shown: string;
begin
  if FRevertUndo.Count = 0 then
    Exit;
  Shown := FRevertUndo[FRevertUndo.Count - 1];
  Saved := TStringList(FRevertUndo.Objects[FRevertUndo.Count - 1]);
  FRevertUndo.Delete(FRevertUndo.Count - 1);
  StopWatcher;
  try
    try
      if FRepo.RestoreReverted(Saved) then
        StatusNote(Format(rsRevertUndone, [Shown]))
      else
        StatusNote(Format(rsRevertUndoFailed, [FRepo.Error]), True);
    finally
      Saved.Free;
    end;
    RefreshRepository;
  finally
    StartWatcher;
  end;
  UpdateDiscardItems;
end;

function TRepoFrame.IsChangedPath(const APath: string): boolean;
begin
  Result := StatIndexOf(APath) >= 0;
end;

{ The reverts of the previous repository are not for this one. }
procedure TRepoFrame.ClearRevertUndo;
var
  i: integer;
begin
  for i := 0 to FRevertUndo.Count - 1 do
    FRevertUndo.Objects[i].Free;
  FRevertUndo.Clear;
end;
