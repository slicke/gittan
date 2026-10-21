{ ---------------------------------------------------------------------------
  The Submodules section
  ---------------------------------------------------------------------------
  Under the Config section sits one for the submodules .gitmodules
  names (gittan.submodules), built like it: a header that folds,
  remembered in the settings, over a tree, hidden while there is nothing
  to list. A row is the submodule's path with the folder icon (dotted
  when git status reports it changed, its checkout moved off the recorded
  commit) and, once its job is done, what its remote holds against the
  recorded commit: "↓3" for three commits the recorded one lacks, "↓"
  for commits not fetched yet, "↑2" for a recorded commit past the
  remote, "⚠" when the remote could not be asked. One TGittanSubmoduleJob
  per submodule asks the remote with ls-remote, so nothing is fetched;
  the jobs run when the list or the recorded commits change, on
  View > Refresh, and SubmodulePoll after the last job of a round
  (FSubTimer), keeping the rows meanwhile. A click shows the submodule's
  page (gittan.subpage, in the summary's box under the file header)
  through ShowSubmodule: its URL and branch, a card with what the remote
  holds, the recorded, checked out and remote commits, and the remote's
  new commits when the submodule has them. A submodule git status
  reports changed is shown the same way from its row in the summary or
  its node in the file tree, the page then with a card for how it moved
  (CompareSubmodule) and the commits it moved by. File > Submodules and the section's menu update, sync and add
  submodules (at the end of this file). }
procedure TForm1.SetupSubmodules;

  function AddItem(const ACaption: string; AClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(FSubPopup);
    Result.Caption := ACaption;
    Result.OnClick := AClick;
    FSubPopup.Items.Add(Result);
  end;

begin
  FSubUpdatePill := -1;
  FSubJobs := TList.Create;
  FSubTimer := TTimer.Create(Self);
  FSubTimer.Enabled := False;
  FSubTimer.Interval := SubmodulePoll;
  FSubTimer.OnTimer := @SubTimerTimer;
  FSubPanel := TPanel.Create(Self);
  FSubPanel.BevelOuter := bvNone;
  FSubPanel.Caption := '';
  FSubPanel.Align := alBottom;
  FSubPanel.Visible := False;
  { Below the Config section: alBottom puts the lower Top lower. }
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
  { A right click selects the row, so the menu acts on the one shown. }
  FSubPopup := TPopupMenu.Create(Self);
  FSubPopup.OnPopup := @SubPopupPopup;
  FSubUpdateItem := AddItem(rsSubUpdateItem, @MenuSubUpdateClick);
  FSubSyncItem := AddItem(rsSubSyncItem, @MenuSubSyncClick);
  AddItem('-', nil);
  FSubOpenItem := AddItem(rsSubOpenItem, @MenuSubOpenClick);
  AddItem(rsCopyPath, @MenuSubCopyPathClick);
  FSubTree.PopupMenu := FSubPopup;
  { The Config section was colored before this header existed. }
  ColorRepoHeader;
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
  Err, FromSide, ToSide: string;
  i, j: integer;
begin
  if not ListSubmodules(FRepo.Root, List, Err) then
    List := nil;
  FSubmodules := List;
  { Only the changed ones are compared; that reads the submodule alone. }
  FRepo.DiffSides(FromSide, ToSide);
  SetLength(FSubChanges, Length(FSubmodules));
  for i := 0 to High(FSubmodules) do
  begin
    FSubChanges[i] := Default(TGittanSubmoduleChange);
    for j := 0 to High(FStats) do
      if FStats[j].Path = FSubmodules[i].Path then
      begin
        FSubChanges[i] := CompareSubmodule(FRepo.Root, FSubmodules[i], FromSide, ToSide);
        Break;
      end;
  end;
  if SubmoduleKey <> FSubKey then
    StartSubmoduleJobs;
  FillSubmoduleTree;
end;

function TForm1.SubmoduleAt(const APath: string): integer;
var
  i: integer;
begin
  for i := 0 to High(FSubmodules) do
    if FSubmodules[i].Path = APath then
      Exit(i);
  Result := -1;
end;

function TForm1.SubmoduleMoveText(AIndex: integer): string;

  function Short(const AHash: string): string;
  begin
    if AHash = '' then
      Result := rsSubNone
    else
      Result := Copy(AHash, 1, 7);
  end;

begin
  Result := '';
  if (AIndex < 0) or (AIndex > High(FSubChanges)) then
    Exit;
  with FSubChanges[AIndex] do
    if FromHash <> ToHash then
      Result := Short(FromHash) + ' → ' + Short(ToHash);
end;

{ The shown submodule's node stays selected in the tree it was picked
  in; after a refresh, which empties both, it is selected in the file
  tree when it is changed, else in the Submodules section: one selection
  among the trees. }
procedure TForm1.SelectShownSubmodule;
var
  Node, InFiles, InSubs: TTreeNode;
  FileHandler, SubHandler: TNotifyEvent;
begin
  if FView <> gvSubmodule then
    Exit;
  InFiles := nil;
  Node := FileTree.Items.GetFirstNode;
  while (Node <> nil) and (InFiles = nil) do
  begin
    if (Node.Data = nil) and (Node.GetTextPath = FSubShown) then
      InFiles := Node;
    Node := Node.GetNext;
  end;
  InSubs := FSubTree.Items.GetFirstNode;
  while (InSubs <> nil) and (SubmoduleAt(FSubShown) + 1 <> integer(PtrUInt(InSubs.Data))) do
    InSubs := InSubs.GetNextSibling;
  if (InSubs <> nil) and (FSubTree.Selected = InSubs) then
    InFiles := nil
  else if InFiles <> nil then
    InSubs := nil;
  FileHandler := FileTree.OnSelectionChanged;
  SubHandler := FSubTree.OnSelectionChanged;
  FileTree.OnSelectionChanged := nil;
  FSubTree.OnSelectionChanged := nil;
  try
    FileTree.Selected := InFiles;
    FSubTree.Selected := InSubs;
    FRepoTree.Selected := nil;
  finally
    FileTree.OnSelectionChanged := FileHandler;
    FSubTree.OnSelectionChanged := SubHandler;
  end;
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
    end;
  finally
    FSubTree.EndUpdate;
    FSubTree.OnSelectionChanged := @SubTreeSelectionChanged;
  end;
  SelectShownSubmodule;
  if Newer > 0 then
    FSubHeader.Detail := Format(rsSubmodulesNewer, [Length(FSubmodules), Newer])
  else if Length(FSubmodules) > 0 then
    FSubHeader.Detail := IntToStr(Length(FSubmodules))
  else
    FSubHeader.Detail := '';
  FSubPanel.Visible := Length(FSubmodules) > 0;
  LayoutRepoFiles;
  UpdateSubmoduleItems;
end;

{ One job per submodule, so a slow remote holds up only its own row.
  The rows keep nothing of the previous jobs unless AKeep. }
procedure TForm1.StartSubmoduleJobs(AKeep: boolean);
var
  Job: TGittanSubmoduleJob;
  i: integer;
begin
  AbandonSubmoduleJobs;
  FSubKey := SubmoduleKey;
  if Length(FSubInfos) <> Length(FSubmodules) then
    AKeep := False;
  SetLength(FSubInfos, Length(FSubmodules));
  for i := 0 to High(FSubmodules) do
  begin
    if not AKeep or (FSubInfos[i].Path <> FSubmodules[i].Path) then
    begin
      FSubInfos[i] := Default(TGittanSubmoduleInfo);
      FSubInfos[i].Path := FSubmodules[i].Path;
    end;
    Job := TGittanSubmoduleJob.Create(FRepo.Root, FSubmodules[i], FBranch);
    Job.OnDone := @SubmoduleJobDone;
    FSubJobs.Add(Job);
    Job.Start;
  end;
end;

{ A poll waits for jobs still running; their end sets the timer again. }
procedure TForm1.SubTimerTimer(Sender: TObject);
begin
  FSubTimer.Enabled := False;
  if (FRepo.Root = '') or (FSubJobs.Count > 0) or (Length(FSubmodules) = 0) then
    Exit;
  StartSubmoduleJobs(True);
end;

procedure TForm1.AbandonSubmoduleJobs;
var
  i: integer;
begin
  { No jobs, no poll: the next round's end starts the timer again. }
  if FSubTimer <> nil then
    FSubTimer.Enabled := False;
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
  submodule and the result differs (a poll that finds the same leaves
  the caret alone). The job is freed from the message loop, as a blame
  job. The last job of a round sets the poll. }
{ What the view shows of a job's result, to tell whether a poll changed
  it. }
function SubmoduleInfoKey(const AInfo: TGittanSubmoduleInfo): string;
begin
  Result := IntToStr(Ord(AInfo.State)) + #0 + AInfo.CheckedOut + #0 + AInfo.Tip +
    #0 + IntToStr(AInfo.Behind) + #0 + IntToStr(AInfo.Ahead) + #0 + AInfo.Error +
    #0 + BoolToStr(AInfo.Initialized, True);
end;

procedure TForm1.SubmoduleJobDone(Sender: TObject);
var
  Job: TGittanSubmoduleJob;
  Node: TTreeNode;
  i: integer;
  Same: boolean;
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
      Same := SubmoduleInfoKey(FSubInfos[i]) = SubmoduleInfoKey(Job.Info);
      FSubInfos[i] := Job.Info;
      Node := FSubTree.Items.GetFirstNode;
      while (Node <> nil) and (Node.Data <> Pointer(PtrInt(i + 1))) do
        Node := Node.GetNextSibling;
      if Node <> nil then
        Node.Text := SubmoduleRowText(i);
      if (FView = gvSubmodule) and (FSubShown = FSubmodules[i].Path) and not Same then
        ShowSubmodule(i);
      Break;
    end;
  { The count of newer ones in the header. }
  if FSubJobs.Count = 0 then
  begin
    FillSubmoduleTree;
    FSubTimer.Enabled := True;
  end;
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
{ Shows submodule AIndex on its page in the summary's box, under the
  file header, which names it, with an Open pill that opens it as a
  repository of its own when it is checked out and an Update pill while
  it is not checked out at the recorded commit. The page keeps its
  scroll position while it shows the same submodule. }
procedure TForm1.ShowSubmodule(AIndex: integer);
var
  Sub: TGittanSubmodule;
  Info: TGittanSubmoduleInfo;
  Change: TGittanSubmoduleChange;
  Checking, Same: boolean;
  Actions: TStringArray;
  i: integer;
begin
  if (AIndex < 0) or (AIndex > High(FSubmodules)) then
    Exit;
  Sub := FSubmodules[AIndex];
  Info := Default(TGittanSubmoduleInfo);
  if AIndex <= High(FSubInfos) then
    Info := FSubInfos[AIndex];
  { A poll keeps the previous result shown while it runs. }
  Checking := False;
  if Info.State = smUnknown then
    for i := 0 to FSubJobs.Count - 1 do
      if TGittanSubmoduleJob(FSubJobs[i]).Sub.Path = Sub.Path then
        Checking := True;
  Change := Default(TGittanSubmoduleChange);
  if AIndex <= High(FSubChanges) then
    Change := FSubChanges[AIndex];
  Same := (FView = gvSubmodule) and FSubPage.Visible and (FSubPage.Path = Sub.Path);
  LeaveEditorViews;
  FSummary.Notice := '';
  FCurrentPath := '';
  FManualLexer := False;
  FView := gvSubmodule;
  FSubShown := Sub.Path;
  FWelcome.Visible := False;
  FSummary.Visible := False;
  FRepoPage.Visible := False;
  FSubPage.SetSubmodule(Sub, Info, Change, Checking, FBranch);
  FSubPage.Visible := True;
  FSubPage.FitHeight(FSummaryBox.ClientHeight);
  FSummaryBox.Visible := True;
  if not Same then
    FSummaryBox.VertScrollBar.Position := 0;
  SetNavRow(-1);
  FStatus.SetPosition('');
  FHeader.SetFile(Sub.Path, iconFolder);
  { Update while it is not checked out, or checked out elsewhere than
    the recorded commit. }
  Actions := nil;
  FSubUpdatePill := -1;
  if (Sub.Recorded <> '') and not Sub.Conflict and not Checking and
    (not Info.Initialized or (Info.CheckedOut <> Sub.Recorded)) then
  begin
    FSubUpdatePill := 0;
    SetLength(Actions, 1);
    Actions[0] := rsSubUpdateAction;
  end;
  if Info.Initialized then
  begin
    SetLength(Actions, Length(Actions) + 1);
    Actions[High(Actions)] := rsSubOpen;
  end;
  if Length(Actions) > 0 then
    FHeader.SetActions(Actions);
  FHeader.SetChanges(0, 0);
  FHeader.SetConflicts(0, 0);
  FHeader.Visible := True;
  PlaceUnderTitleBar;
  SelectShownSubmodule;
  FSummary.Selected := Sub.Path;
  UpdateStatus;
end;

{ A click on a commit of the submodule's page copies its id. }
procedure TForm1.SubPageCopyCommit(Sender: TObject; const AHash: string);
begin
  Clipboard.AsText := AHash;
  StatusNote(Format(rsSubCopied, [Copy(AHash, 1, 7)]), False);
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

{ ---------------------------------------------------------------------------
  Updating, syncing and adding submodules
  ---------------------------------------------------------------------------
  File > Submodules updates them all (git submodule update --init
  --recursive), syncs their URLs from .gitmodules and adds one; the
  section's menu updates or syncs the row it was opened on, and a
  submodule shown while it is not checked out, or checked out elsewhere
  than the recorded commit, has an Update pill. An update and an add go
  to the network, so they run in the remote job with its notice
  (umain.remote.inc hands them back to SubmoduleRemoteDone); an update
  that would move a submodule back to the recorded commit asks first.
  A sync only writes the config. Then the remotes are asked again. }

function TForm1.CanSubmoduleAction: boolean;
begin
  Result := (FRepo <> nil) and (FRepo.Root <> '') and (FRemoteJob = nil) and
    (FCommitJob = nil);
end;

procedure TForm1.UpdateSubmoduleItems;
var
  Can: boolean;
begin
  if FSubAddItem = nil then
    Exit;
  Can := CanSubmoduleAction;
  FSubUpdateAllItem.Enabled := Can and (Length(FSubmodules) > 0);
  FSubSyncAllItem.Enabled := FSubUpdateAllItem.Enabled;
  FSubAddItem.Enabled := Can;
end;

{ What changed in the submodules is asked of their remotes again, and
  the shown one is shown again, as View > Refresh does. }
procedure TForm1.RecheckSubmodules;
begin
  if FRepo.Root = '' then
    Exit;
  StartSubmoduleJobs;
  FillSubmoduleTree;
  if FView = gvSubmodule then
    RestoreSubmodule;
end;

{ Every submodule with APath empty. One checked out at another commit
  than the recorded one is moved back by the update, which may be what
  was not wanted: the user moved it to record the new commit. }
procedure TForm1.UpdateSubmodulesAsk(const APath: string);
var
  Moved: TStringList;
  List: string;
  i, Index: integer;
begin
  if not CanSubmoduleAction then
    Exit;
  Moved := TStringList.Create;
  try
    if MovedSubmodules(FRepo.Root, APath, Moved) and (Moved.Count > 0) then
    begin
      List := '';
      for i := 0 to Moved.Count - 1 do
      begin
        List := List + LineEnding + Moved.Names[i] + '  ' + Copy(Moved.ValueFromIndex[i], 1, 7);
        Index := SubmoduleAt(Moved.Names[i]);
        if Index >= 0 then
          List := List + ' → ' + Copy(FSubmodules[Index].Recorded, 1, 7);
      end;
      if QuestionDlg(rsSubUpdateTitle, rsSubUpdateMoved + LineEnding + List + LineEnding +
        LineEnding + rsSubUpdateMovedKeep, mtWarning, [mrYes, rsSubUpdateAction, mrCancel,
        rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes then
        Exit;
    end;
  finally
    Moved.Free;
  end;
  StartRemote(rkSubmoduleUpdate, pmAuto, APath);
end;

procedure TForm1.SyncSubmodulesNow(const APath: string);
var
  Ok: boolean;
begin
  if not CanSubmoduleAction then
    Exit;
  Screen.Cursor := crHourGlass;
  try
    Ok := FRepo.SyncSubmodules(APath);
  finally
    Screen.Cursor := crDefault;
  end;
  if not Ok then
    BannerError(rsSubSyncFailed, FRepo.Error)
  else if APath = '' then
    StatusNote(rsSubSyncedAll)
  else
    StatusNote(Format(rsSubSynced, [APath]));
  RecheckSubmodules;
end;

{ The dialog starts with AUrl, APath and ABranch: empty from the menu,
  what failed for Try Again. The add runs as a clone does, its notice
  shown at once. }
procedure TForm1.AddSubmoduleAsk(const AUrl, APath, ABranch: string);
var
  Url, Path, Branch: string;
  Taken: TStringArray;
  i: integer;
begin
  if not CanSubmoduleAction then
    Exit;
  Url := AUrl;
  Path := APath;
  Branch := ABranch;
  SetLength(Taken, Length(FSubmodules));
  for i := 0 to High(FSubmodules) do
    Taken[i] := FSubmodules[i].Path;
  if not ChooseSubmodule(FRepo.Root, SubmoduleFolder(FSubmodules), Taken, Url, Path,
    Branch) then
    Exit;
  if not CanSubmoduleAction then
    Exit;
  FNoticeHook := False;
  FRemoteHead := '';
  FRemoteAhead := FAhead;
  FRemoteJob := TGittanRemoteJob.Create(FRepo.Root, rkSubmoduleAdd, pmAuto, Url);
  FRemoteJob.Path := Path;
  FRemoteJob.Branch := Branch;
  FRemoteJob.OnDone := @RemoteJobDone;
  FRemoteJob.OnOutput := @RemoteJobOutput;
  FRemoteJob.Start;
  FStatus.ShowMessage(Format(rsSubAdding, [Path]), stNormal, 0);
  ShowRemoteNotice;
  UpdateRemoteItems;
  UpdateCommitState;
end;

{ From RemoteJobDone after the refresh, for an update or an add that
  went through: the submodules are asked again, and a new one is shown. }
procedure TForm1.SubmoduleRemoteDone(AJob: TGittanRemoteJob);
var
  Index: integer;
begin
  RecheckSubmodules;
  if not AJob.Ok then
    Exit;
  if AJob.Kind = rkSubmoduleAdd then
  begin
    Index := SubmoduleAt(AJob.Path);
    if Index >= 0 then
      ShowSubmodule(Index);
    BannerSuccess(Format(rsSubAddedOk, [AJob.Path]));
  end
  else if AJob.Arg = '' then
    BannerSuccess(rsSubUpdatedAll)
  else
    BannerSuccess(Format(rsSubUpdated, [AJob.Arg]));
end;

{ The submodule of the section's selected row, -1 for none. }
function TForm1.PopupSubmodule: integer;
begin
  Result := -1;
  if (FSubTree.Selected <> nil) and (FSubTree.Selected.Data <> nil) then
    Result := integer(PtrUInt(FSubTree.Selected.Data)) - 1;
  if Result > High(FSubmodules) then
    Result := -1;
end;

procedure TForm1.SubPopupPopup(Sender: TObject);
var
  Index: integer;
  Can: boolean;
begin
  Index := PopupSubmodule;
  Can := (Index >= 0) and CanSubmoduleAction;
  FSubUpdateItem.Enabled := Can and (FSubmodules[Index].Recorded <> '');
  FSubSyncItem.Enabled := Can;
  FSubOpenItem.Enabled := (Index >= 0) and (Index <= High(FSubInfos)) and
    FSubInfos[Index].Initialized;
end;

procedure TForm1.MenuSubUpdateAllClick(Sender: TObject);
begin
  UpdateSubmodulesAsk('');
end;

procedure TForm1.MenuSubSyncAllClick(Sender: TObject);
begin
  SyncSubmodulesNow('');
end;

procedure TForm1.MenuSubAddClick(Sender: TObject);
begin
  AddSubmoduleAsk('', '', '');
end;

procedure TForm1.MenuSubUpdateClick(Sender: TObject);
begin
  if PopupSubmodule >= 0 then
    UpdateSubmodulesAsk(FSubmodules[PopupSubmodule].Path);
end;

procedure TForm1.MenuSubSyncClick(Sender: TObject);
begin
  if PopupSubmodule >= 0 then
    SyncSubmodulesNow(FSubmodules[PopupSubmodule].Path);
end;

procedure TForm1.MenuSubOpenClick(Sender: TObject);
begin
  if PopupSubmodule < 0 then
    Exit;
  OpenRepository(IncludeTrailingPathDelimiter(FRepo.Root) +
    SetDirSeparators(FSubmodules[PopupSubmodule].Path));
end;

procedure TForm1.MenuSubCopyPathClick(Sender: TObject);
begin
  if PopupSubmodule >= 0 then
    Clipboard.AsText := IncludeTrailingPathDelimiter(FRepo.Root) +
      SetDirSeparators(FSubmodules[PopupSubmodule].Path);
end;
