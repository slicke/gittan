{ ---------------------------------------------------------------------------
  The Submodules section
  ---------------------------------------------------------------------------
  Under the Repository section sits one for the submodules .gitmodules
  names (gittan.submodules), built like it: a header that folds,
  remembered in the settings, over a tree, hidden while there is nothing
  to list. A row is the submodule's path with the folder icon (dotted
  when git status reports it changed, its checkout moved off the recorded
  commit) and, once its job is done, what its remote holds against the
  recorded commit: "↓3" for three commits the recorded one lacks, "↓"
  for commits not fetched yet, "↑2" for a recorded commit past the
  remote, "⚠" when the remote could not be asked. One TGittanSubmoduleJob
  per submodule asks the remote with ls-remote, so nothing is fetched;
  the jobs run when the list or the recorded commits change and on
  View > Refresh. A click shows the submodule in the editor through
  ShowSubmodule: its URL and branch, the recorded commit, the checked out
  one, the remote's, and the remote's new commits when the submodule
  has them. }
procedure TForm1.SetupSubmodules;
begin
  FSubJobs := TList.Create;
  FSubPanel := TPanel.Create(Self);
  FSubPanel.BevelOuter := bvNone;
  FSubPanel.Caption := '';
  FSubPanel.Align := alBottom;
  FSubPanel.Visible := False;
  { Below the Repository section: alBottom puts the lower Top lower. }
  FSubPanel.Top := FRepoPanel.Top + FRepoPanel.Height + 1;
  FSubPanel.Parent := FTreePanel;
  FSubHeader := TGittanSectionHeader.Create(Self);
  FSubHeader.Title := rsSubmodules;
  FSubHeader.Align := alTop;
  FSubHeader.Expanded := True;
  FSubHeader.OnToggle := @RepoHeaderToggle;
  FSubHeader.Parent := FSubPanel;
  FSubTree := TTreeView.Create(Self);
  FSubTree.BorderStyle := bsNone;
  FSubTree.Images := TreeImages;
  FSubTree.ReadOnly := True;
  FSubTree.Options := FileTree.Options;
  FSubTree.OnSelectionChanged := @SubTreeSelectionChanged;
  FSubTree.Align := alClient;
  FSubTree.Parent := FSubPanel;
end;

{ What the jobs depend on: the submodules with their recorded commits
  and branches, and whether git status reports each one changed, which
  it does when its checkout moved. }
function TForm1.SubmoduleKey: string;
var
  i, j: integer;
begin
  Result := FRepo.Root;
  for i := 0 to High(FSubmodules) do
  begin
    Result := Result + #0 + FSubmodules[i].Path + #1 + FSubmodules[i].Recorded +
      #1 + FSubmodules[i].Branch + #1 + FSubmodules[i].Url;
    for j := 0 to High(FStats) do
      if FStats[j].Path = FSubmodules[i].Path then
        Result := Result + #1 + IntToStr(Ord(FStats[j].Kind));
  end;
end;

{ Lists the submodules again (from ApplySnapshot, so the watcher keeps
  them current) and starts the jobs when what they depend on changed. }
procedure TForm1.FillSubmodules;
var
  List: TGittanSubmodules;
  Err: string;
begin
  if not ListSubmodules(FRepo.Root, List, Err) then
    List := nil;
  FSubmodules := List;
  if SubmoduleKey <> FSubKey then
    StartSubmoduleJobs;
  FillSubmoduleTree;
end;

{ The row of submodule AIndex: its path and what the remote holds. }
function TForm1.SubmoduleRowText(AIndex: integer): string;
var
  Info: TGittanSubmoduleInfo;
begin
  Result := FSubmodules[AIndex].Path;
  if AIndex > High(FSubInfos) then
    Exit;
  Info := FSubInfos[AIndex];
  case Info.State of
    smBehind: Result := Result + '  ↓' + IntToStr(Info.Behind);
    smAhead: Result := Result + '  ↑' + IntToStr(Info.Ahead);
    smDiverged: Result := Result + '  ↓' + IntToStr(Info.Behind) + ' ↑' + IntToStr(Info.Ahead);
    smNotFetched: Result := Result + '  ↓';
    smFailed: Result := Result + '  ⚠';
  end;
end;

{ One row per submodule, Data its index + 1; the shown one stays
  selected. The header counts them, and the ones the remote is ahead of. }
procedure TForm1.FillSubmoduleTree;
var
  Node: TTreeNode;
  RowIcon, Newer, i, j: integer;
begin
  FSubTree.OnSelectionChanged := nil;
  FSubTree.BeginUpdate;
  try
    FSubTree.Items.Clear;
    Newer := 0;
    for i := 0 to High(FSubmodules) do
    begin
      Node := FSubTree.Items.AddChild(nil, SubmoduleRowText(i));
      Node.Data := Pointer(PtrInt(i + 1));
      RowIcon := iconFolder;
      for j := 0 to High(FStats) do
        if FStats[j].Path = FSubmodules[i].Path then
          RowIcon := FolderIcon(FStats[j].Kind);
      Node.ImageIndex := RowIcon;
      Node.SelectedIndex := RowIcon;
      if (i <= High(FSubInfos)) and (FSubInfos[i].State in [smBehind, smDiverged, smNotFetched]) then
        Inc(Newer);
      if (FView = gvSubmodule) and (FSubmodules[i].Path = FSubShown) then
        FSubTree.Selected := Node;
    end;
  finally
    FSubTree.EndUpdate;
    FSubTree.OnSelectionChanged := @SubTreeSelectionChanged;
  end;
  if Newer > 0 then
    FSubHeader.Detail := Format(rsSubmodulesNewer, [Length(FSubmodules), Newer])
  else if Length(FSubmodules) > 0 then
    FSubHeader.Detail := IntToStr(Length(FSubmodules))
  else
    FSubHeader.Detail := '';
  FSubPanel.Visible := Length(FSubmodules) > 0;
  LayoutRepoFiles;
end;

{ One job per submodule, so a slow remote holds up only its own row.
  The rows keep nothing of the previous jobs. }
procedure TForm1.StartSubmoduleJobs;
var
  Job: TGittanSubmoduleJob;
  i: integer;
begin
  AbandonSubmoduleJobs;
  FSubKey := SubmoduleKey;
  SetLength(FSubInfos, Length(FSubmodules));
  for i := 0 to High(FSubmodules) do
  begin
    FSubInfos[i] := Default(TGittanSubmoduleInfo);
    FSubInfos[i].Path := FSubmodules[i].Path;
    Job := TGittanSubmoduleJob.Create(FRepo.Root, FSubmodules[i], FBranch);
    Job.OnDone := @SubmoduleJobDone;
    FSubJobs.Add(Job);
    Job.Start;
  end;
end;

procedure TForm1.AbandonSubmoduleJobs;
var
  i: integer;
begin
  if FSubJobs = nil then
    Exit;
  for i := 0 to FSubJobs.Count - 1 do
  begin
    TGittanSubmoduleJob(FSubJobs[i]).Stop(False);
    FBlameZombies.Add(FSubJobs[i]);
  end;
  FSubJobs.Clear;
end;

{ The job's result goes to its row, and to the view when it shows the
  submodule. The job is freed from the message loop, as a blame job. }
procedure TForm1.SubmoduleJobDone(Sender: TObject);
var
  Job: TGittanSubmoduleJob;
  Node: TTreeNode;
  i, TopLine: integer;
begin
  Job := TGittanSubmoduleJob(Sender);
  if FSubJobs.IndexOf(Job) < 0 then
    Exit;
  FSubJobs.Remove(Job);
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  for i := 0 to High(FSubmodules) do
    if (FSubmodules[i].Path = Job.Info.Path) and (i <= High(FSubInfos)) then
    begin
      FSubInfos[i] := Job.Info;
      Node := FSubTree.Items.GetFirstNode;
      while (Node <> nil) and (Node.Data <> Pointer(PtrInt(i + 1))) do
        Node := Node.GetNextSibling;
      if Node <> nil then
        Node.Text := SubmoduleRowText(i);
      if (FView = gvSubmodule) and (FSubShown = FSubmodules[i].Path) then
      begin
        TopLine := Edit.LineTop;
        ShowSubmodule(i);
        Edit.LineTop := Min(TopLine, Max(Edit.Strings.Count - 1, 0));
      end;
      Break;
    end;
  { The count of newer ones in the header. }
  if FSubJobs.Count = 0 then
    FillSubmoduleTree;
end;

procedure TForm1.SubTreeSelectionChanged(Sender: TObject);
var
  Node: TTreeNode;
begin
  Node := FSubTree.Selected;
  if (Node = nil) or (Node.Data = nil) or (FRepo.Root = '') then
    Exit;
  { One selection among the trees. }
  FileTree.Selected := nil;
  FRepoTree.Selected := nil;
  ShowSubmodule(integer(PtrUInt(Node.Data)) - 1);
end;

{ A commit as a line of the view: short id, date, author, summary. }
function SubmoduleCommitText(const ACommit: TGittanSubmoduleCommit): string;
begin
  Result := ACommit.Short + '  ' + ACommit.Date + '  ' + ACommit.Author + '  ' +
    ACommit.Subject;
end;

{ Shows submodule AIndex in the editor as text: where it comes from,
  then the recorded, checked out and remote commits, then the remote's
  new commits. The header names it, with an Open pill that opens it as a
  repository of its own when it is checked out. }
procedure TForm1.ShowSubmodule(AIndex: integer);
var
  Sub: TGittanSubmodule;
  Info: TGittanSubmoduleInfo;
  Checking: boolean;
  Lines: TStringList;
  Line: string;
  i: integer;

  procedure Add(const ALabel, AText: string);
  begin
    Lines.Add(Format('%-13s%s', [ALabel, AText]));
  end;

  function Short(const AHash: string): string;
  begin
    Result := Copy(AHash, 1, 7);
  end;

begin
  if (AIndex < 0) or (AIndex > High(FSubmodules)) then
    Exit;
  Sub := FSubmodules[AIndex];
  Info := Default(TGittanSubmoduleInfo);
  if AIndex <= High(FSubInfos) then
    Info := FSubInfos[AIndex];
  Checking := False;
  for i := 0 to FSubJobs.Count - 1 do
    if TGittanSubmoduleJob(FSubJobs[i]).Sub.Path = Sub.Path then
      Checking := True;
  Lines := TStringList.Create;
  try
    Add(rsSubUrl, Sub.Url);
    if Sub.Branch = '' then
      Add(rsSubBranch, rsSubDefaultBranch)
    else if Sub.Branch = '.' then
      Add(rsSubBranch, Format(rsSubSameBranch, [FBranch]))
    else
      Add(rsSubBranch, Sub.Branch);
    Lines.Add('');
    if Sub.Recorded = '' then
      Add(rsSubRecorded, rsSubNoRecorded)
    else if Info.Recorded.Hash <> '' then
      Add(rsSubRecorded, SubmoduleCommitText(Info.Recorded))
    else
      Add(rsSubRecorded, Short(Sub.Recorded));
    if Sub.Conflict then
      Add('', rsSubConflict);
    if Checking then
      Add(rsSubCheckedOut, rsSubChecking)
    else if not Info.Initialized then
      Add(rsSubCheckedOut, rsSubNotInitialized)
    else if Info.CheckedOut = Sub.Recorded then
      Add(rsSubCheckedOut, rsSubSameAsRecorded)
    else if Info.Current.Hash <> '' then
      Add(rsSubCheckedOut, SubmoduleCommitText(Info.Current))
    else
      Add(rsSubCheckedOut, Short(Info.CheckedOut));
    if Checking then
      Line := rsSubChecking
    else
      case Info.State of
        smUpToDate: Line := Short(Info.Tip) + '  ' + rsSubUpToDate;
        smBehind: Line := Short(Info.Tip) + '  ' + Format(rsSubBehind, [Info.Behind]);
        smAhead: Line := Short(Info.Tip) + '  ' + Format(rsSubAhead, [Info.Ahead]);
        smDiverged: Line := Short(Info.Tip) + '  ' +
            Format(rsSubDiverged, [Info.Behind, Info.Ahead]);
        smNotFetched: Line := Short(Info.Tip) + '  ' + rsSubNotFetched;
        smFailed: Line := Format(rsSubFailed, [Info.Error]);
        else
          Line := '';
      end;
    Add(rsSubRemote, Line);
    if Length(Info.Incoming) > 0 then
    begin
      Lines.Add('');
      Lines.Add(rsSubIncoming);
      for i := 0 to High(Info.Incoming) do
        Lines.Add(SubmoduleCommitText(Info.Incoming[i]));
      if Info.Behind > Length(Info.Incoming) then
        Lines.Add(Format(rsSubMore, [Info.Behind - Length(Info.Incoming)]));
    end;
    FSummary.Notice := '';
    FCurrentPath := '';
    FManualLexer := False;
    FView := gvSubmodule;
    FSubShown := Sub.Path;
    ShowText(Edit, Lines.Text, nil);
  finally
    Lines.Free;
  end;
  FHeader.SetFile(Sub.Path, iconFolder);
  if Info.Initialized then
    FHeader.SetActions([rsSubOpen]);
  UpdateChangeNav;
  ShowEditor;
  FileTree.Selected := nil;
  FSummary.Selected := '';
  UpdateStatus;
end;

{ The Open pill: the submodule as a repository of its own. }
procedure TForm1.OpenShownSubmodule;
begin
  if (FRepo.Root = '') or (FSubShown = '') then
    Exit;
  OpenRepository(IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(FSubShown));
end;

{ After a refresh: the shown submodule again, or the summary when it is
  gone. }
procedure TForm1.RestoreSubmodule;
var
  i: integer;
begin
  for i := 0 to High(FSubmodules) do
    if FSubmodules[i].Path = FSubShown then
    begin
      ShowSubmodule(i);
      Exit;
    end;
  ShowSummary;
end;
