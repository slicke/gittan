{ ---------------------------------------------------------------------------
  The sidebar's pages: Home and Repository
  ---------------------------------------------------------------------------
  Two rows at the top of the sidebar (gittan.sidenav), under the filter
  field, open the pages of a repository as a music app's sidebar has
  Home and Explore over the library: Home is the summary, what the
  repository's name in the status bar shows, and Repository is a page
  about the repository itself (gittan.repopage): its branch and
  upstream, how many commits since when, branches, tags, tracked files,
  submodules and the size of its objects, then its remotes, a web
  address among them being a link, and the authors with the most
  commits. The facts are read by a TGittanRepoInfoJob (gittan.repoinfo)
  off the main thread each time the page is shown and after each
  refresh while it is; the page keeps the facts read before meanwhile.
  The row of the page shown is filled; a file in the editor fills none.
  View > Repository Info (Cmd+Shift+I) opens the page too. }

const
  { How many authors and tags the page lists. }
  MaxContributors = 8;
  MaxNewestTags = 3;

procedure TForm1.SetupSideNav;
begin
  FSideNav := TGittanSideNav.Create(Self);
  FSideNav.AddRow(rsNavHome, niHome);
  FSideNav.AddRow(rsNavRepository, niRepository);
  FSideNav.Heading := rsNavFiles;
  FSideNav.OnPick := @SideNavPick;
  { Under the filter field: the alTop controls keep the order of their
    tops. }
  FSideNav.Top := FTreeFilter.Top + FTreeFilter.Height + 1;
  FSideNav.Align := alTop;
  FSideNav.Parent := FTreePanel;
end;

procedure TForm1.SideNavPick(Sender: TObject; AIndex: integer);
begin
  case AIndex of
    navHome: MenuSummaryClick(Sender);
    navRepository: MenuRepoInfoClick(Sender);
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
  FWelcome.Visible := False;
  FSummary.Visible := False;
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
  FSideNav.Selected := navRepository;
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
