{ ---------------------------------------------------------------------------
  Patches
  ---------------------------------------------------------------------------
  Create Patch... in the commit menu writes the commit as a patch file,
  and Create Patch Series with Marked <name>... every commit from the
  older of the two to the newer, both included, when one is in the
  other's history (the mark of umain.commitactions.inc): the dialog
  (gittan.patchdlg) lists them and asks for the folder, and the files
  are shown in Finder (or the file manager) when written. File > Apply
  Patches... picks patch files and the dialog chooses between committing
  each (git am) and changing the work tree alone (git apply). An am
  that stops is carried on in the Commit section, as a rebase is; a
  patch that goes into the work tree with conflicts leaves them to
  resolve as a merge does. The folders and the choices are kept until
  another repository is opened. }

{ The folder patches are written to: the last one's, else <name>-patches
  beside the repository, so they land neither in its work tree nor
  loose among the folders next to it. }
function TForm1.PatchFolder: string;
begin
  Result := FPatchFolder;
  if Result = '' then
    Result := ExcludeTrailingPathDelimiter(FRepo.Root) + '-patches';
end;

procedure TForm1.CreatePatches(const AOlder, ANewer: string);
var
  Commits: TGittanPatchCommits;
  Files: TStringList;
  Folder: string;
  Ok: boolean;
begin
  if FRepo.Root = '' then
    Exit;
  if not FRepo.PatchCommits(AOlder, ANewer, Commits) then
  begin
    BannerError(rsPatchFailed, FRepo.Error);
    Exit;
  end;
  if Length(Commits) = 0 then
  begin
    BannerError(rsPatchFailed, rsPatchOnlyMerges);
    Exit;
  end;
  Folder := PatchFolder;
  if not ChoosePatchSeries(Commits, Folder, FPatchCover) then
    Exit;
  FPatchFolder := Folder;
  Files := TStringList.Create;
  try
    Screen.Cursor := crHourGlass;
    try
      Ok := FRepo.FormatPatches(AOlder, ANewer, Folder, FPatchCover, Files);
    finally
      Screen.Cursor := crDefault;
    end;
    if not Ok or (Files.Count = 0) then
    begin
      BannerError(rsPatchFailed, FRepo.Error);
      Exit;
    end;
    if Files.Count = 1 then
      StatusNote(Format(rsPatchWritten, [ShortPath(Files[0])]))
    else
      StatusNote(Format(rsPatchesWritten, [Files.Count, ShortPath(Folder)]));
    {$IFDEF DARWIN}
    RunDetached('open', ['-R', Files[Files.Count - 1]]);
    {$ELSE}
    {$IFDEF WINDOWS}
    RunDetached('explorer.exe', ['/select,' + Files[Files.Count - 1]]);
    {$ELSE}
    RunDetached('xdg-open', [Folder]);
    {$ENDIF}
    {$ENDIF}
  finally
    Files.Free;
  end;
end;

{ am moves HEAD, so nothing else may be under way; apply goes along. }
function TForm1.CanApplyPatches: boolean;
begin
  Result := RepoReady;
end;

procedure TForm1.MenuApplyPatchesClick(Sender: TObject);
var
  Files: TStringList;
  Ok, Conflicts: boolean;
  Applied, Failed: integer;
  FailedName: string;
begin
  if not CanApplyPatches then
    Exit;
  Files := TStringList.Create;
  try
    if FApplyFolder = '' then
      FApplyFolder := PatchFolder;
    if not PickPatchFiles(Files, FApplyFolder) or
      not ChooseApplyPatches(Files, FApplyCommit, FApplyFolder) then
      Exit;
    StopWatcher;
    try
      Screen.Cursor := crHourGlass;
      try
        Ok := FRepo.ApplyPatches(Files, FApplyCommit, Conflicts, Applied);
      finally
        Screen.Cursor := crDefault;
      end;
      FLoadError := '';
      FSummary.Notice := '';
      RefreshRepository;
    finally
      StartWatcher;
    end;
    { The file that stopped it: the one after those that went in, or for
      apply's conflicts the last that went in. }
    Failed := Applied;
    if Conflicts and not FApplyCommit then
      Dec(Failed);
    if Failed > Files.Count - 1 then
      Failed := Files.Count - 1;
    if Failed < 0 then
      Failed := 0;
    FailedName := ExtractFileName(Files[Failed]);
    if Ok then
    begin
      if FApplyCommit and (Files.Count = 1) then
        StatusNote(rsPatchCommitted)
      else if FApplyCommit then
        StatusNote(Format(rsPatchesCommitted, [Applied]))
      else if Files.Count = 1 then
        StatusNote(rsPatchApplied)
      else
        StatusNote(Format(rsPatchesApplied, [Applied]));
    end
    else if Conflicts and FApplyCommit then
      StatusNote(rsPatchAmConflicts, True)
    else if Conflicts then
      StatusNote(Format(rsPatchConflicts, [FailedName]), True)
    else if FRepo.Operation = 'applying patches' then
      BannerError(Format(rsPatchStopped, [FailedName]), FRepo.Error)
    else if Applied > 0 then
      BannerError(Format(rsPatchPartly, [Applied, Files.Count, FailedName]), FRepo.Error)
    else
      BannerError(rsApplyFailed, FRepo.Error);
  finally
    Files.Free;
  end;
end;
