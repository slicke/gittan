{ ---------------------------------------------------------------------------
  The Project page
  ---------------------------------------------------------------------------
  What the repository is as a project (gittan.project: the kinds the
  root's files tell, their dependencies with the versions asked for and
  resolved, the project's version, and the checks worth a warning), as
  a page in the box (gittan.projectpage), opened from the sidebar's
  Project row and View > Project (Cmd+7). The dependencies are compared
  with those at the newest tag reachable from HEAD, so the page says
  what a release will carry that the last one did not; the old files
  are read from the tag with FileBlob. The reports are built when the
  page is shown and, while it shows, on every snapshot, since the files
  may change under it; a dependency's name opens its page on the
  registry, and Add to .gitignore on a check writes the pattern. See
  spec/project-page.md. }

procedure TRepoFrame.SetupProjectPage;
begin
  FProjectPage := TGittanProjectPage.Create(Self);
  FProjectPage.Parent := FSummaryBox;
  FProjectPage.Visible := False;
  FProjectPage.OnOpenUrl := @ProjectPageOpenUrl;
  FProjectPage.OnIgnore := @ProjectPageIgnore;
end;

{ Builds the reports: the tag, the tracked files, and for each kind its
  files as they are at the tag. A few small git runs, so only while the
  page is wanted. }
procedure TRepoFrame.LoadProject;
var
  Reports: TGittanProjectReports;
  Tracked: TStringList;
  Since, OldManifest, OldLock, FileName: string;
  Blob: RawByteString;
  i: integer;
begin
  FProjectStale := False;
  if FRepo.Root = '' then
  begin
    FProjectPage.SetRepository('', '');
    Exit;
  end;
  if not FRepo.NearestTag(Since) then
    Since := '';
  Tracked := TStringList.Create;
  try
    FRepo.TrackedFiles(Tracked);
    SetLength(Reports, Length(FRepoProjects));
    for i := 0 to High(FRepoProjects) do
    begin
      OldManifest := '';
      OldLock := '';
      if Since <> '' then
      begin
        FileName := FRepoProjects[i].Kind.DependencyFile(FRepo.Root);
        if (FileName <> '') and FRepo.FileBlob(FileName, Since, Blob) then
          OldManifest := Blob;
        FileName := FRepoProjects[i].Kind.LockFile(FRepo.Root);
        if (FileName <> '') and FRepo.FileBlob(FileName, Since, Blob) then
          OldLock := Blob;
      end;
      Reports[i] := ProjectReport(FRepoProjects[i], FRepo.Root, OldManifest, OldLock, Since,
        Tracked);
    end;
  finally
    Tracked.Free;
  end;
  FProjectPage.SetRepository(ExtractFileName(FRepo.Root), FRepo.Root);
  FProjectPage.SetReports(Reports);
end;

procedure TRepoFrame.MenuProjectClick(Sender: TObject);
begin
  if FRepo.Root <> '' then
    ShowProject;
end;

{ The page takes the summary's place in the box, as the Commands page
  does. }
procedure TRepoFrame.ShowProject;
begin
  if FRepo.Root = '' then
    Exit;
  if FGraph.Visible then
    FGraph.Close;
  LeaveEditorViews;
  FView := gvProject;
  HideBoxPages;
  if FProjectStale or (FProjectPage.Root <> FRepo.Root) then
    LoadProject;
  FProjectPage.Visible := True;
  FProjectPage.FitHeight(FSummaryBox.ClientHeight);
  FSummaryBox.Visible := True;
  FSummaryBox.VertScrollBar.Position := 0;
  FStatus.SetPosition('');
  { A file picked again after the page must fire the selection event. }
  FileTree.Selected := nil;
  FRepoTree.Selected := nil;
  FSubTree.Selected := nil;
  SetNavRow(navProject);
  UpdateStatus;
end;

procedure TRepoFrame.ProjectPageOpenUrl(Sender: TObject; const AText: string);
begin
  OpenURL(AText);
end;

{ Writes the check's pattern to the root's .gitignore, as the file
  menu's Add to .gitignore does, and takes the tracked files the pattern
  matches out of the index (git rm --cached, the files staying on disk),
  since an ignored file git tracks is still tracked; then reloads, and
  the checks are built again with the snapshot. }
procedure TRepoFrame.ProjectPageIgnore(Sender: TObject; const ACheck: TGittanProjectCheck);
var
  FileName, Pattern: string;
  Tracked: TStringList;
  Paths: TStringList;
  i: integer;

  { Whether the pattern, as the checks write them, covers APath: a
    folder's name with "/" anywhere in the path, "*.ext" by the
    extension, else the one path. }
  function Matches(const APath: string): boolean;
  begin
    if Pattern[Length(Pattern)] = '/' then
      Result := (Pos(Pattern, APath) = 1) or (Pos('/' + Pattern, APath) > 0)
    else if Pos('*.', Pattern) = 1 then
      Result := SameText(ExtractFileExt(APath), Copy(Pattern, 2, MaxInt))
    else
      Result := APath = ACheck.Path;
  end;

begin
  Pattern := ACheck.IgnorePattern;
  if (FRepo.Root = '') or (Pattern = '') then
    Exit;
  FileName := IncludeTrailingPathDelimiter(FRepo.Root) + RepoRootFiles[0];
  if not AddIgnorePattern(FileName, Pattern) then
  begin
    StatusNote(Format(rsIgnoreFailed, [RepoRootFiles[0]]), True);
    Exit;
  end;
  Tracked := TStringList.Create;
  Paths := TStringList.Create;
  try
    FRepo.TrackedFiles(Tracked);
    for i := 0 to Tracked.Count - 1 do
      if Matches(Tracked[i]) then
        Paths.Add(Tracked[i]);
    if (Paths.Count > 0) and not FRepo.RemovePaths(Paths, True) then
      StatusNote(Format(rsIgnoreNotUntracked, [Pattern]), True)
    else if Paths.Count = 1 then
      StatusNote(Format(rsIgnoreAddedUntrackedOne, [Pattern, RepoRootFiles[0], Paths[0]]))
    else if Paths.Count > 1 then
      StatusNote(Format(rsIgnoreAddedUntracked, [Pattern, RepoRootFiles[0], Paths.Count]))
    else
      StatusNote(Format(rsIgnoreAdded, [Pattern, RepoRootFiles[0]]));
  finally
    Paths.Free;
    Tracked.Free;
  end;
  RefreshRepository;
end;
