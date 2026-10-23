{ ---------------------------------------------------------------------------
  The sidebar's pages: Home and Repository
  ---------------------------------------------------------------------------
  The rows at the top of the sidebar (gittan.sidenav), under the filter
  field, open the pages of a repository as a music app's sidebar has
  Home and Explore over the library: Home is the summary, what the
  repository's name in the status bar shows, Commands the page of the
  repository's own commands (umain.commands.inc), Files the files of
  HEAD (umain.files.inc), and Repository is a
  page about the repository itself (gittan.repopage): its branch and
  upstream, how many commits since when, branches, tags, tracked files,
  submodules and the size of its objects, then its remotes, a web
  address among them being a link, and the authors with the most
  commits. The facts are read by a TGittanRepoInfoJob (gittan.repoinfo)
  off the main thread each time the page is shown and after each
  refresh while it is; the page keeps the facts read before meanwhile.
  The row of the page shown is filled; a file in the editor fills none.
  View > Repository Info (Cmd+Shift+I) opens the page too. The tiles and
  the authors lead on (RepoPageOpenTarget): the commits to the commit
  graph, the branches and the tags to their lists, dropped from the
  tile, the files to the Files page, the
  submodules to a submodule's page (from a list when there are more),
  an author to the commit graph filtered to them. }

const
  { How many authors and tags the page lists. }
  MaxContributors = 8;
  MaxNewestTags = 3;

procedure TForm1.SetupSideNav;
begin
  FSideNav := TGittanSideNav.Create(Self);
  FSideNav.Large := True;
  FSideNav.AddRow(rsNavHome, niHome);
  FSideNav.AddRow(rsNavGraph, niGraph);
  FSideNav.AddRow(rsNavRepository, niRepository);
  FSideNav.AddRow(rsNavCommands, niCommands);
  FSideNav.AddRow(rsNavFiles, niFiles);
  FSideNav.AddRow(rsNavRecent, niClock, True);
  FSideNav.AddRow(rsNavSettings, niTools, True);
  FSideNav.Heading := rsNavChanges;
  FSideNav.ShowToggle(rsNavHide, rsNavShow);
  FSideNav.OnPick := @SideNavPick;
  FNavViewRow := -1;
  { A press on a row leaves the graph open, so that the Graph row can
    close it on the release; the page rows close it themselves. }
  FGraph.Keeper := FSideNav;
  FGraph.OnClose := @GraphClosed;
  { Under the filter field: the alTop controls keep the order of their
    tops. }
  FSideNav.Top := FTreeFilter.Top + FTreeFilter.Height + 1;
  FSideNav.Align := alTop;
  FSideNav.Parent := FTreePanel;
end;

procedure TForm1.SideNavPick(Sender: TObject; AIndex: integer);
begin
  if (AIndex <> navGraph) and FGraph.Visible then
    FGraph.Close;
  case AIndex of
    navHome: MenuSummaryClick(Sender);
    navGraph: MenuCommitGraphClick(Sender);
    navRepository: MenuRepoInfoClick(Sender);
    navCommands: MenuCommandsClick(Sender);
    navFiles: MenuFilesClick(Sender);
    navRecent: ShowRecentList(FSideNav.RowScreenRect(AIndex));
    navSettings: MenuSettingsClick(Sender);
  end;
end;

{ The Recent row's list: the recent repositories as File > Open Recent
  names them, the open one checked, then Open Repository... }
procedure TForm1.ShowRecentList(const AAnchor: TRect);
var
  i: integer;
begin
  FRecentPopup.Clear;
  if FSettings.Recent.Count = 0 then
    FRecentPopup.AddHeader(rsNoRecent);
  for i := 0 to FSettings.Recent.Count - 1 do
    FRecentPopup.Add(ShortPath(FSettings.Recent[i]), '',
      (FRepo.Root <> '') and SameFileName(FSettings.Recent[i], FRepo.Root));
  FRecentPopup.Add(StripHotkey(rsOpenRepo));
  FRecentPopup.Popup(AAnchor);
end;

procedure TForm1.RecentPopupPick(Sender: TObject; AIndex: integer);
begin
  if AIndex < FSettings.Recent.Count then
    OpenRepository(FSettings.Recent[AIndex])
  else
    MenuOpenRepoClick(Sender);
end;

{ The row of the view shown; the Graph row stands in for it while the
  commit graph is open, and takes over again when it closes. }
procedure TForm1.SetNavRow(ARow: integer);
begin
  FNavViewRow := ARow;
  { At startup the sidebar is not built yet. }
  if FSideNav = nil then
    Exit;
  if FGraph.Visible then
    FSideNav.Selected := navGraph
  else
    FSideNav.Selected := ARow;
end;

procedure TForm1.GraphClosed(Sender: TObject);
begin
  if FSideNav <> nil then
    FSideNav.Selected := FNavViewRow;
end;

procedure TForm1.RepoPageOpenTarget(Sender: TObject; ATarget: TGittanRepoTarget;
  const AName: string; const AScreenRect: TRect);
var
  i: integer;
begin
  if FRepo.Root = '' then
    Exit;
  case ATarget of
    rtCommits:
      ShowCommitGraph('');
    rtBranches:
      ShowBranchList(blSwitch, AScreenRect);
    rtTags:
      ShowTagList(AScreenRect);
    rtFiles:
      ShowFiles;
    rtSubmodules:
      if Length(FSubmodules) = 1 then
        ShowSubmodule(0)
      else if Length(FSubmodules) > 1 then
      begin
        FSubListPopup.Clear;
        FSubListPopup.AddHeader(rsSubmodulesHeader);
        SetLength(FSubListRows, Length(FSubmodules));
        for i := 0 to High(FSubmodules) do
          FSubListRows[i] := FSubListPopup.Add(FSubmodules[i].Path, FSubmodules[i].Branch);
        FSubListPopup.Popup(AScreenRect);
      end;
    rtAuthor:
      if Pos(' ', AName) > 0 then
        ShowCommitGraph('author:"' + AName + '"')
      else
        ShowCommitGraph('author:' + AName);
  end;
end;

procedure TForm1.SubListPopupPick(Sender: TObject; AIndex: integer);
var
  i: integer;
begin
  for i := 0 to Min(High(FSubListRows), High(FSubmodules)) do
    if FSubListRows[i] = AIndex then
    begin
      ShowSubmodule(i);
      Exit;
    end;
end;

procedure TForm1.MenuRepoInfoClick(Sender: TObject);
begin
  if FRepo.Root <> '' then
    ShowRepoInfo;
end;

{ The page takes the summary's place in the box, as the welcome view
  does, and the facts are read again. }
procedure TForm1.ShowRepoInfo;
begin
  if FRepo.Root = '' then
    Exit;
  LeaveEditorViews;
  FView := gvRepoInfo;
  HideBoxPages;
  FRepoPage.SetRepository(ExtractFileName(FRepo.Root), FRepo.Root);
  FRepoPage.Visible := True;
  FRepoPage.FitHeight(FSummaryBox.ClientHeight);
  FSummaryBox.Visible := True;
  FSummaryBox.VertScrollBar.Position := 0;
  FStatus.SetPosition('');
  { A file picked again after the page must fire the selection event. }
  FileTree.Selected := nil;
  FRepoTree.Selected := nil;
  FSubTree.Selected := nil;
  SetNavRow(navRepository);
  StartRepoInfoJob;
  UpdateStatus;
end;

{ One job at a time; a start while one runs is remembered and run
  when it is done, so the page ends up with the latest facts. }
procedure TForm1.StartRepoInfoJob;
begin
  if FRepo.Root = '' then
    Exit;
  if FRepoInfoJob <> nil then
  begin
    FRepoInfoAgain := True;
    Exit;
  end;
  FRepoInfoJob := TGittanRepoInfoJob.Create(FRepo.Root, MaxContributors, MaxNewestTags);
  FRepoInfoJob.OnDone := @RepoInfoJobDone;
  FRepoPage.SetLoading(True);
  FRepoInfoJob.Start;
end;

{ The job is dropped; its result, if it comes, is thrown away. It is
  freed later from the zombie list, as a blame job is. }
procedure TForm1.AbandonRepoInfoJob;
begin
  FRepoInfoAgain := False;
  if FRepoInfoJob = nil then
    Exit;
  FRepoInfoJob.Stop(False);
  FBlameZombies.Add(FRepoInfoJob);
  FRepoInfoJob := nil;
  FRepoPage.SetLoading(False);
end;

procedure TForm1.RepoInfoJobDone(Sender: TObject);
var
  Job: TGittanRepoInfoJob;
begin
  Job := TGittanRepoInfoJob(Sender);
  if Job <> FRepoInfoJob then
    Exit;
  FRepoInfoJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  if Job.Root = FRepo.Root then
  begin
    FRepoPage.SetRepository(ExtractFileName(FRepo.Root), FRepo.Root);
    FRepoPage.SetInfo(Job.Info);
    if FRepoPage.Visible then
      FRepoPage.FitHeight(FSummaryBox.ClientHeight);
  end
  else
    FRepoPage.SetLoading(False);
  if FRepoInfoAgain then
  begin
    FRepoInfoAgain := False;
    StartRepoInfoJob;
  end;
end;
