{ ---------------------------------------------------------------------------
  The Project page
  ---------------------------------------------------------------------------
  What the repository is as a project, as a page in the box
  (gittan.projectpage), opened from the sidebar's Project row and View >
  Project (Cmd+7). Each kind shown is a driver (src/proj) that builds
  its own section through a TGittanGitProjectContext: the newest tag
  reachable from HEAD to compare with, the files git tracks, the files
  and submodules as they were at the tag. The kinds are the ones
  LoadRepoCommands found (FRepoProjects): picked on this page, else the
  project line of .gittan/commands.toml, else each driver's Identify;
  the chip at the top right drops the list to pick them from
  (FKindsPopup), kept per repository in the settings. The sections are
  built when the page is shown and, while it shows, on every snapshot;
  a link opens in the browser, a button runs its command as the
  Commands page does, and Add to .gitignore on a check writes the
  pattern. See spec/project-page.md. }

procedure TRepoFrame.SetupProjectPage;
begin
  FProjectPage := TGittanProjectPage.Create(Self);
  FProjectPage.Parent := FSummaryBox;
  FProjectPage.Visible := False;
  FProjectPage.OnOpenUrl := @ProjectPageOpenUrl;
  FProjectPage.OnIgnore := @ProjectPageIgnore;
  FProjectPage.OnRunCommand := @ProjectPageRun;
  FProjectPage.OnPickKinds := @ProjectPagePickKinds;
  FKindsPopup := TGittanPopupList.Create(Self);
  FKindsPopup.Parent := Self;
  FKindsPopup.OnPick := @KindsPopupPick;
end;

{ The names of the kinds shown, "Lazarus, Node". }
function TRepoFrame.ProjectKindNames: string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(FRepoProjects) do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + FRepoProjects[i].Name;
  end;
end;

{ Builds the sections: a context of the repository (a few small git
  runs), then each kind's driver. }
procedure TRepoFrame.LoadProject;
var
  Context: TGittanGitProjectContext;
  Sections: TGittanProjectSections;
begin
  FProjectStale := False;
  if FRepo.Root = '' then
  begin
    FProjectPage.SetRepository('', '');
    Exit;
  end;
  Context := TGittanGitProjectContext.Create(FRepo.Root);
  try
    Sections := ProjectSections(FRepoProjects, Context);
  finally
    Context.Free;
  end;
  FProjectPage.SetRepository(ExtractFileName(FRepo.Root), FRepo.Root);
  FProjectPage.SetSections(Sections, ProjectKindNames,
    App.Settings.ProjectKindsOf(FRepo.Root) <> '');
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

{ A button of a section: its command runs as a command of the Commands
  page does, whose output panel shows it. A driver's command comes from
  the repository's own files as a script of package.json does, so it
  needs no trust. One the Commands page lists too (the kind's, with the
  same line) runs as that one, so its tile shows the run and confirm
  in commands.toml asks; the name first, a build mode's button is the
  one build of a project with one mode. }
procedure TRepoFrame.ProjectPageRun(Sender: TObject; const AProject, AName, ACommand: string);
var
  Cmd: TGittanRepoCommand;
  i, Found: integer;
begin
  Found := -1;
  for i := 0 to High(FRepoCommands) do
    if (FRepoCommands[i].Source = csProject) and (FRepoCommands[i].Project = AProject) and
      (FRepoCommands[i].Command = ACommand) then
      if FRepoCommands[i].Name = AName then
      begin
        Found := i;
        Break;
      end
      else if Found < 0 then
        Found := i;
  if Found >= 0 then
  begin
    RunRepoCommand(Found, False, False);
    Exit;
  end;
  Cmd := Default(TGittanRepoCommand);
  Cmd.Name := AName;
  Cmd.Command := ACommand;
  Cmd.Detail := ACommand;
  Cmd.Source := csProject;
  Cmd.Project := AProject;
  RunCommandRecord(Cmd, False);
end;

{ The list of the kinds: Automatic, which lets the files decide (with
  the kinds they tell), then every kind the drivers know, those shown
  checked, each with the file that identifies it here. }
procedure TRepoFrame.ProjectPagePickKinds(Sender: TObject; const AScreenRect: TRect);
var
  Kinds: TGittanProjectKindClasses;
  Found: TGittanProjects;
  i, j: integer;
  Detected, Manifest: string;
  Shown: boolean;
begin
  if FRepo.Root = '' then
    Exit;
  Found := DetectProjects(FRepo.Root);
  Detected := '';
  for i := 0 to High(Found) do
  begin
    if Detected <> '' then
      Detected := Detected + ', ';
    Detected := Detected + Found[i].Name;
  end;
  if Detected = '' then
    Detected := rsNoProjectKind;
  FKindsPopup.Clear;
  FKindsPopup.Add(rsAutomaticKinds, Detected, App.Settings.ProjectKindsOf(FRepo.Root) = '',
    KindsAutomatic);
  FKindsPopup.AddHeader(rsProjectKinds);
  Kinds := ProjectKinds;
  for i := 0 to High(Kinds) do
  begin
    Shown := False;
    for j := 0 to High(FRepoProjects) do
      if FRepoProjects[j].Kind = Kinds[i] then
        Shown := True;
    if not Kinds[i].Identify(FRepo.Root, Manifest) then
      Manifest := '';
    FKindsPopup.Add(Kinds[i].Name, Manifest, Shown, i);
  end;
  FKindsPopup.Popup(AScreenRect);
end;

{ Automatic forgets what was picked; a kind is taken in or out of the
  kinds shown, which are then kept as picked ("none" when it was the
  last). The commands and the page follow at once. }
procedure TRepoFrame.KindsPopupPick(Sender: TObject; AIndex: integer);
var
  Row: PtrInt;
  Kinds: TGittanProjectKindClasses;
  Names: TStringList;
  i, k: integer;
begin
  if FRepo.Root = '' then
    Exit;
  Row := FKindsPopup.TagOf(AIndex);
  if Row = KindsAutomatic then
    App.Settings.SetProjectKinds(FRepo.Root, '')
  else
  begin
    Kinds := ProjectKinds;
    if (Row < 0) or (Row > High(Kinds)) then
      Exit;
    Names := TStringList.Create;
    try
      for i := 0 to High(FRepoProjects) do
        Names.Add(FRepoProjects[i].Name);
      k := Names.IndexOf(Kinds[Row].Name);
      if k >= 0 then
        Names.Delete(k)
      else
        Names.Add(Kinds[Row].Name);
      if Names.Count = 0 then
        App.Settings.SetProjectKinds(FRepo.Root, 'none')
      else
        App.Settings.SetProjectKinds(FRepo.Root, string.Join(',', Names.ToStringArray));
    finally
      Names.Free;
    end;
  end;
  App.Settings.Save;
  LoadRepoCommands;
  LoadProject;
  if FView = gvProject then
    FProjectPage.FitHeight(FSummaryBox.ClientHeight);
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
