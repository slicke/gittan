{ ---------------------------------------------------------------------------
  Clean
  ---------------------------------------------------------------------------
  File > Clean... deletes files git does not track: the dialog
  (gittan.cleandlg) chooses untracked files,
  ignored ones or both and lists what git clean -n says would go for
  that choice, each with a box; the ticked ones are deleted with git
  clean. Unlike a revert nothing is saved first, since ignored files
  are mostly what a build makes, often a lot of it; the dialog says so.
  The choice of kind is kept until another repository is opened. }

function TRepoFrame.CanClean: boolean;
begin
  Result := (FRepo.Root <> '') and (FCommitJob = nil) and (FRemoteJob = nil);
end;

procedure TRepoFrame.MenuCleanClick(Sender: TObject);
var
  Paths: TStringList;
  Ok: boolean;
begin
  if not CanClean then
    Exit;
  Paths := TStringList.Create;
  try
    if not ChooseClean(FRepo, FCleanKind, Paths) then
      Exit;
    StopWatcher;
    try
      Screen.Cursor := crHourGlass;
      try
        Ok := FRepo.Clean(FCleanKind, Paths);
      finally
        Screen.Cursor := crDefault;
      end;
      FSummary.Notice := '';
      RefreshRepository;
    finally
      StartWatcher;
    end;
    if Ok then
    begin
      if Paths.Count = 1 then
        StatusNote(Format(rsCleanedOne, [Paths[0]]))
      else
        StatusNote(Format(rsCleaned, [Paths.Count]));
    end
    else
      BannerError(rsCleanFailed, FRepo.Error);
  finally
    Paths.Free;
  end;
end;
