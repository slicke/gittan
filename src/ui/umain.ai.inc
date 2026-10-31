{ ---------------------------------------------------------------------------
  The AI features
  ---------------------------------------------------------------------------
  An agent (gittan.ai): a command line tool, Claude Code's claude or
  GitHub Copilot's copilot, run in the repository, or a model at an
  OpenAI-compatible API. Nothing of it shows until the settings turn
  the features on (AI page, off by default, since the changes go to the
  agent's provider) and the agent they pick can be asked (its command
  found; for the API a model named). The first feature is AI at the
  right end of the Commit
  header, and File > Write Commit Message (Shift+Cmd+K): the agent
  writes the message for the ticked files, which goes into the field
  when the field is as it was when it was asked. Either again while it
  writes stops it.

  The second is View > Review Changes with AI (Alt+Cmd+R): the agent
  reviews what the change view compares, and its findings are cards in
  the change view among a pull request's threads (see umain.reviews.inc),
  kept for that comparison until the next review or Clear AI Review.

  The third is the sparkle in the filter field (where something is), the
  fourth Resolve with the agent in a conflict's list (umain.conflicts.inc):
  the agent writes the lines that take the conflict's place, which are
  written as a pick of the list is, so Undo Discard puts it back. The
  fifth is File > Split Changes into Commits: the agent groups the
  changed files into commits with their messages, and a pick from the
  plan ticks one commit's files and fills in its message. The sixth is
  Fix on a finding's card: the agent changes the file as the finding
  asks, written as a discard is, so Undo Discard takes it back. The
  seventh is Go > Explain Line History with AI (and the editor menu's):
  the agent reads the history of the lines (git log -L) and explains
  how they came to be, a card under them among the review's. }

{ The agent the settings pick, made from its fields there: its command
  by the path they give, else where it is found (or the API's server),
  the key and the model. The jobs take their own copies of it, so a
  job that runs on keeps the agent it started with. }
procedure TRepoFrame.FindAI;
var
  Agent: TGittanAgent;
  AIClass: TGittanAIClass;
  Path, Key, Model: string;
begin
  FreeAndNil(FAI);
  Agent := AgentOfKey(App.Settings.AIAgent);
  AIClass := AIClassOf(Agent);
  if AIClass = nil then
    Exit;
  Key := '';
  case Agent of
    gaCopilot:
    begin
      Path := App.Settings.CopilotPath;
      Model := App.Settings.CopilotModel;
    end;
    gaOpenAI:
    begin
      Path := App.Settings.OpenAIUrl;
      Key := App.Settings.OpenAIKey;
      Model := App.Settings.OpenAIModel;
    end;
    else
    begin
      Path := App.Settings.ClaudePath;
      Model := App.Settings.ClaudeModel;
    end;
  end;
  FAI := AIClass.Create(AIClass.Find(Trim(Path)), Trim(Key), Trim(Model));
end;

function TRepoFrame.AIAvailable: boolean;
begin
  Result := App.Settings.AIEnabled and (FAI <> nil) and FAI.Available;
end;

function TRepoFrame.AgentName: string;
begin
  if FAI = nil then
    Result := ''
  else
    Result := FAI.Title;
end;

{ Shown with the features on and nothing for git to carry on with (a
  merge or a rebase has its message); while it writes it stops it,
  otherwise it needs files ticked (or Amend, which describes HEAD) and
  no commit running. The menu item stays in the menu while the features
  are on, disabled when the header has no AI. }
procedure TRepoFrame.UpdateMessageAction;
var
  Shown, Can: boolean;
begin
  if (FCommitHeader = nil) or (FMessageItem = nil) then
    Exit;
  Shown := AIAvailable and (FOperation = '') and CommitChoosing;
  if FMessageJob <> nil then
  begin
    FCommitHeader.Action := rsWritingMessage;
    FCommitHeader.ActionHint := Format(rsWritingMessageHint, [AgentName]);
    FMessageItem.Caption := rsStopMessageMenu;
    Can := True;
  end
  else
  begin
    FCommitHeader.Action := rsWriteMessage;
    FCommitHeader.ActionHint := Format(rsWriteMessageHint, [AgentName]);
    FMessageItem.Caption := rsWriteMessageMenu;
    Can := (FCommitJob = nil) and ((FChosenCount > 0) or FCommitAmend.Checked);
  end;
  if not Shown then
    FCommitHeader.Action := '';
  FCommitHeader.ActionEnabled := Can;
  FMessageItem.Visible := AIAvailable;
  FMessageItem.Enabled := Shown and Can;
  UpdateSplitItem;
  UpdateAIReviewItems;
end;

{ From the header or the menu: the section unfolds, so the message is
  seen when it comes. }
procedure TRepoFrame.MessageActionClick(Sender: TObject);
begin
  if FMessageJob <> nil then
  begin
    AbandonMessageJob;
    FStatus.ShowMessage('', stNormal, 0);
    UpdateCommitState;
  end
  else
  begin
    if not FCommitHeader.Expanded then
    begin
      FCommitHeader.Expanded := True;
      CommitHeaderToggle(nil);
    end;
    StartMessageJob;
  end;
end;

procedure TRepoFrame.StartMessageJob;
var
  Paths: TStringList;
begin
  if (FMessageJob <> nil) or not AIAvailable or (FRepo.Root = '') then
    Exit;
  Paths := TStringList.Create;
  try
    ChosenCommitPaths(Paths);
    FMessageJob := TGittanMessageJob.Create(FRepo.Root, FAI, Paths, FCommitAmend.Checked);
  finally
    Paths.Free;
  end;
  FMessageFrom := FCommitMemo.Text;
  FMessageJob.OnDone := @MessageJobDone;
  FMessageJob.Start;
  FStatus.ShowBusy(Format(rsWritingStatus, [AgentName]), HintSparkle);
  UpdateCommitState;
end;

{ The message goes into the field unless the field was changed while
  the agent wrote; a failure says the agent's reason in a banner. The
  job is freed from the message loop, since its notification comes from
  inside Execute. }
procedure TRepoFrame.MessageJobDone(Sender: TObject);
var
  Job: TGittanMessageJob;
begin
  Job := TGittanMessageJob(Sender);
  if Job <> FMessageJob then
    Exit;
  FMessageJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  FStatus.ShowMessage('', stNormal, 0);
  if not Job.Ok then
    BannerError(Format(rsMessageFailed, [Job.AgentName]), Job.Error)
  else if FCommitMemo.Text <> FMessageFrom then
    StatusNote(Format(rsMessageChanged, [Job.AgentName]))
  else
  begin
    FCommitMemo.Text := Job.Message;
    FCommitMemo.SelStart := 0;
  end;
  UpdateCommitState;
end;

procedure TRepoFrame.AbandonMessageJob;
begin
  if FMessageJob = nil then
    Exit;
  FMessageJob.Stop(False);
  FBlameZombies.Add(FMessageJob);
  FMessageJob := nil;
end;

function TRepoFrame.AIReviewKey: string;
begin
  Result := FRepo.Root + #0 + FRepo.Base + #0 + BoolToStr(FRepo.WholeTree, True);
end;

{ The review's items show while the features are on; Clear while there
  are findings for what is compared. }
procedure TRepoFrame.UpdateAIReviewItems;
begin
  if FAIReviewItem = nil then
    Exit;
  FAIReviewItem.Visible := AIAvailable;
  FAIClearItem.Visible := AIAvailable;
  if FWhyItem <> nil then
  begin
    FWhyItem.Visible := AIAvailable;
    if FWhyJob <> nil then
      FWhyItem.Caption := rsWhyStopMenu
    else
      FWhyItem.Caption := rsWhyMenu;
  end;
  if FAIReviewJob <> nil then
    FAIReviewItem.Caption := rsAIReviewStopMenu
  else
    FAIReviewItem.Caption := rsAIReviewMenu;
  FAIReviewItem.Enabled := FRepo.Root <> '';
  FAIClearItem.Enabled := (Length(FAIThreads) > 0) and (FAIThreadsKey = AIReviewKey);
end;

procedure TRepoFrame.MenuAIReviewClick(Sender: TObject);
begin
  if FAIReviewJob <> nil then
  begin
    AbandonAIReview;
    FStatus.ShowMessage('', stNormal, 0);
    UpdateAIReviewItems;
  end
  else
    StartAIReview;
end;

procedure TRepoFrame.MenuAIClearClick(Sender: TObject);
begin
  FAIThreads := nil;
  FAIThreadsKey := '';
  CollectShownThreads;
  FileTree.Invalidate;
  RebuildIfChanges;
  UpdateAIReviewItems;
end;

{ Reviews what the change view compares: a range as it is, else the
  work tree's changed files against the base. }
procedure TRepoFrame.StartAIReview;
var
  Paths: TStringList;
  i: integer;
begin
  if (FAIReviewJob <> nil) or not AIAvailable or (FRepo.Root = '') then
    Exit;
  Paths := TStringList.Create;
  try
    for i := 0 to High(FStats) do
      Paths.Add(FStats[i].Path);
    FAIReviewJob := TGittanAIReviewJob.Create(FRepo.Root, FAI, FRepo.Base, FRepo.IsRange,
      Paths, AIReviewKey);
  finally
    Paths.Free;
  end;
  FAIReviewJob.OnDone := @AIReviewDone;
  FAIReviewJob.Start;
  FStatus.ShowBusy(Format(rsAIReviewing, [AgentName]), HintSparkle);
  UpdateAIReviewItems;
end;

{ The findings replace those held, and show while their comparison is
  the one shown; the status bar says how many there are. }
procedure TRepoFrame.AIReviewDone(Sender: TObject);
var
  Job: TGittanAIReviewJob;
  Agent: string;
begin
  Job := TGittanAIReviewJob(Sender);
  if Job <> FAIReviewJob then
    Exit;
  FAIReviewJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  FStatus.ShowMessage('', stNormal, 0);
  Agent := Job.AgentName;
  if not Job.Ok then
  begin
    BannerError(Format(rsAIReviewFailed, [Agent]), Job.Error);
    UpdateAIReviewItems;
    Exit;
  end;
  FAIThreads := Job.Threads;
  FAIThreadsKey := Job.Key;
  if Length(FAIThreads) = 0 then
    StatusNote(Format(rsAIReviewNone, [Agent]))
  else if Length(FAIThreads) = 1 then
    StatusNote(Format(rsAIReviewOne, [Agent]))
  else
    StatusNote(Format(rsAIReviewMany, [Agent, Length(FAIThreads)]));
  CollectShownThreads;
  FileTree.Invalidate;
  RebuildIfChanges;
  UpdateAIReviewItems;
end;

procedure TRepoFrame.AbandonAIReview;
begin
  if FAIReviewJob = nil then
    Exit;
  FAIReviewJob.Stop(False);
  FBlameZombies.Add(FAIReviewJob);
  FAIReviewJob := nil;
end;

{ The third is the sparkle in the filter field: the agent is asked
  which files hold what the field says, and they drop from the field to
  be picked. }
procedure TRepoFrame.UpdateFindAction;
begin
  if FSearchBox = nil then
    Exit;
  FSearchBox.ShowAction := AIAvailable;
  FSearchBox.ActionBusy := FFindJob <> nil;
  if FFindJob <> nil then
    FSearchBox.ActionHint := Format(rsFindStopHint, [AgentName])
  else
    FSearchBox.ActionHint := Format(rsFindHint, [AgentName]);
end;

{ The sparkle or Cmd+Enter: asks about the field's text, or stops the
  agent while it looks. }
procedure TRepoFrame.SearchBoxAction(Sender: TObject);
var
  Question: string;
begin
  if FFindJob <> nil then
  begin
    AbandonFindJob;
    FStatus.ShowMessage('', stNormal, 0);
    UpdateFindAction;
    Exit;
  end;
  Question := Trim(FTreeFilter.Text);
  if Question = '' then
  begin
    StatusNote(Format(rsFindEmpty, [AgentName]));
    if FTreeFilter.CanFocus then
      FTreeFilter.SetFocus;
    Exit;
  end;
  StartFindJob(Question);
end;

procedure TRepoFrame.StartFindJob(const AQuestion: string);
begin
  if (FFindJob <> nil) or not AIAvailable or (FRepo.Root = '') then
    Exit;
  FFindJob := TGittanFindJob.Create(FRepo.Root, FAI, AQuestion);
  FFindJob.OnDone := @FindJobDone;
  FFindJob.Start;
  FStatus.ShowBusy(Format(rsFindLooking, [AgentName, AQuestion]),
    HintSparkle);
  UpdateFindAction;
end;

{ The files the agent named that are in the work tree, under the field;
  none is a status note, a failure a banner. The list cuts a caption at
  its end and gives the detail its whole width, so the why is cut to a
  part of the list's width here, and the path at its start, keeping the
  file's name. }
procedure TRepoFrame.FindJobDone(Sender: TObject);
const
  { What the list gives the caption and the detail, at its widest. }
  FindRoom = 360;
  WhyRoom = 170;
var
  Job: TGittanFindJob;
  Agent, Item, Why: string;
  i: integer;
  P: TPoint;
  C: TCanvas;
begin
  Job := TGittanFindJob(Sender);
  if Job <> FFindJob then
    Exit;
  FFindJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  FStatus.ShowMessage('', stNormal, 0);
  UpdateFindAction;
  Agent := Job.AgentName;
  if not Job.Ok then
  begin
    BannerError(Format(rsFindFailed, [Agent]), Job.Error);
    Exit;
  end;
  FFoundFiles := nil;
  for i := 0 to High(Job.Files) do
    if RepoFileExists(Job.Files[i].Path) then
      Insert(Job.Files[i], FFoundFiles, Length(FFoundFiles));
  if Length(FFoundFiles) = 0 then
  begin
    StatusNote(Format(rsFindNone, [Agent, Job.Question]));
    Exit;
  end;
  FFindPopup.Clear;
  FFindPopup.AddHeader(Format(rsFindHeader, [Job.Question]));
  C := MeasureCanvas(Font);
  for i := 0 to High(FFoundFiles) do
  begin
    Why := FitTextRight(C, FFoundFiles[i].Why, Px(WhyRoom));
    Item := FFoundFiles[i].Path;
    if FFoundFiles[i].Line > 0 then
      Item := Item + ':' + IntToStr(FFoundFiles[i].Line);
    Item := FitTextLeft(C, Item, Px(FindRoom) - C.TextWidth(Why) - Px(10));
    FFindPopup.Add(Item, Why, False, i);
  end;
  P := FSearchBox.ClientToScreen(Point(0, 0));
  FFindPopup.Popup(Rect(P.X, P.Y, P.X + FSearchBox.Width, P.Y + FSearchBox.Height));
end;

procedure TRepoFrame.FindPopupPick(Sender: TObject; AIndex: integer);
var
  i: PtrInt;
begin
  i := FFindPopup.TagOf(AIndex);
  if (i < 0) or (i > High(FFoundFiles)) then
    Exit;
  { The question was the agent's, not a filter of the tree. }
  FTreeFilter.Text := '';
  { The file picked, kept now: another find may be done before the
    call and put other files in FFoundFiles. }
  FFoundPick := FFoundFiles[i];
  Application.QueueAsyncCall(@ShowFoundAsync, 0);
end;

{ After the list has closed and given the focus back to the field, so
  the editor keeps the focus ShowFileLine gives it. }
procedure TRepoFrame.ShowFoundAsync(Data: PtrInt);
begin
  ShowFileLine(FFoundPick.Path, FFoundPick.Line);
end;

procedure TRepoFrame.AbandonFindJob;
begin
  if FFindJob = nil then
    Exit;
  FFindJob.Stop(False);
  FBlameZombies.Add(FFindJob);
  FFindJob := nil;
end;

{ The conflict as the view has it now, markers and all, goes to the
  agent; its lines are written over it when they come, as long as the
  file still holds it then (DiscardBlock checks). }
procedure TRepoFrame.StartConflictJob(AIndex: integer);
var
  B: TGittanDiscard;
begin
  if (FConflictJob <> nil) or not AIAvailable or not CanResolveBlocks or (AIndex < 0) or
    (AIndex > High(FConflictStarts)) then
    Exit;
  B := ResolveBlock(FChangeLines, FConflictRoles, FConflictStarts[AIndex], cpOurs,
    IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(FCurrentPath));
  B.OldLines := nil;
  FConflictJob := TGittanConflictJob.Create(FRepo.Root, FAI, FCurrentPath, FOperation,
    FOperation = 'rebasing', B);
  FConflictJob.OnDone := @ConflictJobDone;
  FConflictJob.Start;
  FStatus.ShowBusy(Format(rsResolvingAI, [AgentName, B.Line, FCurrentPath]), HintSparkle);
end;

{ Whether ARelPath, a path in the repository, is the file open to
  edits; FEditPath is a full name. }
function TRepoFrame.EditingRepoPath(const ARelPath: string): boolean;
begin
  Result := (FEditPath <> '') and SameFileName(FEditPath,
    IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(ARelPath));
end;

{ The lines go over the conflict unless the file is being edited; the
  view moves on to the next conflicted file only when this one is shown. }
procedure TRepoFrame.ConflictJobDone(Sender: TObject);
var
  Job: TGittanConflictJob;
begin
  Job := TGittanConflictJob(Sender);
  if Job <> FConflictJob then
    Exit;
  FConflictJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  FStatus.ShowMessage('', stNormal, 0);
  if not Job.Ok then
    BannerError(Format(rsResolveAIFailed, [Job.AgentName]), Job.Error)
  else if EditingRepoPath(Job.Path) then
    StatusNote(Format(rsResolveAIEditing, [Job.AgentName, Job.Path]), True)
  else
    WriteConflictBlock(Job.Block, Job.Path, (Job.Path = FCurrentPath) and
      (FView = gvChanges), Job.AgentName, Job.Why);
end;

procedure TRepoFrame.AbandonConflictJob;
begin
  if FConflictJob = nil then
    Exit;
  FConflictJob.Stop(False);
  FBlameZombies.Add(FConflictJob);
  FConflictJob := nil;
end;

{ ---------------------------------------------------------------------------
  Splitting the changes into commits
  --------------------------------------------------------------------------- }

{ The files a commit could take: the changed ones but the conflicts. }
function ChoosablePaths(const AStats: TGittanFileStats; AList: TStrings): integer;
var
  i: integer;
begin
  AList.Clear;
  for i := 0 to High(AStats) do
    if AStats[i].Kind <> ckConflict then
      AList.Add(AStats[i].Path);
  Result := AList.Count;
end;

procedure TRepoFrame.UpdateSplitItem;
var
  Paths: TStringList;
  Can: boolean;
begin
  if FSplitItem = nil then
    Exit;
  FSplitItem.Visible := AIAvailable;
  if FSplitJob <> nil then
  begin
    FSplitItem.Caption := rsSplitStopMenu;
    FSplitItem.Enabled := True;
    Exit;
  end;
  FSplitItem.Caption := rsSplitMenu;
  Can := AIAvailable and (FOperation = '') and CommitChoosing and (FCommitJob = nil);
  if Can and (FCommitPlan = nil) then
  begin
    Paths := TStringList.Create;
    try
      Can := ChoosablePaths(FStats, Paths) >= 2;
    finally
      Paths.Free;
    end;
  end;
  FSplitItem.Enabled := Can;
end;

{ Stops the agent while it plans; shows the plan held, with what has
  been committed since gone from it; else asks for one. }
procedure TRepoFrame.MenuSplitClick(Sender: TObject);
begin
  if FSplitJob <> nil then
  begin
    AbandonSplitJob;
    FStatus.ShowMessage('', stNormal, 0);
    UpdateSplitItem;
    Exit;
  end;
  PrunePlan;
  if FCommitPlan <> nil then
    ShowPlan
  else
    StartSplitJob;
end;

procedure TRepoFrame.StartSplitJob;
var
  Paths: TStringList;
begin
  if (FSplitJob <> nil) or not AIAvailable or not CommitChoosing or (FOperation <> '') then
    Exit;
  FCommitPlan := nil;
  Paths := TStringList.Create;
  try
    if ChoosablePaths(FStats, Paths) = 0 then
      Exit;
    FSplitJob := TGittanSplitJob.Create(FRepo.Root, FAI, Paths);
  finally
    Paths.Free;
  end;
  FSplitJob.OnDone := @SplitJobDone;
  FSplitJob.Start;
  FStatus.ShowBusy(Format(rsSplitting, [AgentName]), HintSparkle);
  UpdateSplitItem;
end;

{ One commit is ticked and described at once; more are a list to pick
  the first from. }
procedure TRepoFrame.SplitJobDone(Sender: TObject);
var
  Job: TGittanSplitJob;
begin
  Job := TGittanSplitJob(Sender);
  if Job <> FSplitJob then
    Exit;
  FSplitJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  FStatus.ShowMessage('', stNormal, 0);
  if not Job.Ok then
    BannerError(Format(rsSplitFailed, [Job.AgentName]), Job.Error)
  else
  begin
    FCommitPlan := Job.Plan;
    FPlanAgent := Job.AgentName;
    PrunePlan;
    if Length(FCommitPlan) = 1 then
    begin
      ApplyPlannedCommit(0);
      StatusNote(Format(rsPlanOne, [Job.AgentName]));
      FCommitPlan := nil;
    end
    else if FCommitPlan <> nil then
      ShowPlan;
  end;
  UpdateSplitItem;
end;

procedure TRepoFrame.AbandonSplitJob;
begin
  if FSplitJob = nil then
    Exit;
  FSplitJob.Stop(False);
  FBlameZombies.Add(FSplitJob);
  FSplitJob := nil;
end;

procedure TRepoFrame.PrunePlan;
var
  Paths: TStringList;
  i, j: integer;
begin
  Paths := TStringList.Create;
  try
    ChoosablePaths(FStats, Paths);
    Paths.CaseSensitive := True;
    Paths.Sorted := True;
    for i := High(FCommitPlan) downto 0 do
    begin
      for j := High(FCommitPlan[i].Files) downto 0 do
        if Paths.IndexOf(FCommitPlan[i].Files[j]) < 0 then
          Delete(FCommitPlan[i].Files, j, 1);
      if FCommitPlan[i].Files = nil then
        Delete(FCommitPlan, i, 1);
    end;
  finally
    Paths.Free;
  end;
end;

{ Under the Commit header: each commit's subject and how many files it
  takes, then Plan Again. }
procedure TRepoFrame.ShowPlan;
var
  i: integer;
  Subject, Count: string;
  P: TPoint;
begin
  if FCommitPlan = nil then
    Exit;
  FPlanPopup.Clear;
  FPlanPopup.AddHeader(Format(rsPlanHeader, [FPlanAgent]));
  for i := 0 to High(FCommitPlan) do
  begin
    Subject := FCommitPlan[i].Message;
    if Pos(#10, Subject) > 0 then
      Subject := Copy(Subject, 1, Pos(#10, Subject) - 1);
    if Subject = '' then
      Subject := rsPlanNoMessage;
    if Length(FCommitPlan[i].Files) = 1 then
      Count := rsPlanFile
    else
      Count := Format(rsPlanFiles, [Length(FCommitPlan[i].Files)]);
    FPlanPopup.Add(Format('%d. %s', [i + 1, Subject]), Count, False, i);
  end;
  FPlanPopup.AddHeader('');
  FPlanPopup.Add(rsPlanAgain, HintSparkle, False, -2);
  P := FCommitHeader.ClientToScreen(Point(0, 0));
  FPlanPopup.Popup(Rect(P.X, P.Y, P.X + FCommitHeader.Width, P.Y + FCommitHeader.Height));
end;

procedure TRepoFrame.PlanPopupPick(Sender: TObject; AIndex: integer);
var
  i: PtrInt;
begin
  i := FPlanPopup.TagOf(AIndex);
  if i = -2 then
    StartSplitJob
  else if (i >= 0) and (i <= High(FCommitPlan)) then
  begin
    ApplyPlannedCommit(i);
    StatusNote(Format(rsPlanTicked, [i + 1, Length(FCommitPlan)]));
  end;
end;

{ Ticks the plan's commit AIndex, files whole: the changes left out of
  its files go, those of the others stay. Its message goes in the field;
  one without (the files the agent left out) empties the field when it
  holds another commit's of the plan, and leaves what the user typed. }
procedure TRepoFrame.ApplyPlannedCommit(AIndex: integer);
var
  Files: TStringList;
  i: integer;
  Chosen: boolean;
begin
  if not CommitChoosing or (FCommitJob <> nil) or (AIndex < 0) or
    (AIndex > High(FCommitPlan)) then
    Exit;
  Files := TStringList.Create;
  try
    Files.AddStrings(FCommitPlan[AIndex].Files);
    Files.CaseSensitive := True;
    Files.Sorted := True;
    for i := 0 to High(FStats) do
      if FStats[i].Kind <> ckConflict then
      begin
        Chosen := Files.IndexOf(FStats[i].Path) >= 0;
        SetCommitChosen(i, Chosen);
        if Chosen then
          DropLeftOut(FStats[i].Path);
      end;
  finally
    Files.Free;
  end;
  ApplyCommitChecks;
  if FCommitPlan[AIndex].Message <> '' then
    FCommitMemo.Text := FCommitPlan[AIndex].Message
  else
    for i := 0 to High(FCommitPlan) do
      if (FCommitPlan[i].Message <> '') and
        (Trim(FCommitMemo.Text) = Trim(FCommitPlan[i].Message)) then
      begin
        FCommitMemo.Text := '';
        Break;
      end;
  MenuCommitClick(nil);
  FCommitMemo.SelStart := 0;
  UpdateCommitState;
end;

{ ---------------------------------------------------------------------------
  Fixing a finding
  --------------------------------------------------------------------------- }

{ What tells a finding apart, among the review's and the shown: its
  path, its line as the agent gave it and its text. }
function FindingKey(const AThread: TGittanReviewThread): string;
begin
  Result := AThread.Path + #0 + IntToStr(AThread.OriginalLine) + #0 +
    AThread.Comments[0].Body;
end;

procedure TRepoFrame.FixFindingClick(AThread: integer);
var
  Finding: TGittanReviewThread;
begin
  if (AThread < 0) or (AThread > High(FShown)) then
    Exit;
  Finding := FShown[AThread];
  if FFixJob <> nil then
  begin
    if FFixKey = FindingKey(Finding) then
    begin
      AbandonFixJob;
      FStatus.ShowMessage('', stNormal, 0);
      Edit.Invalidate;
      FEditOld.Invalidate;
    end
    else
      StatusNote(Format(rsFixBusy, [AgentName]));
    Exit;
  end;
  if not AIAvailable or FRepo.IsRange or (Finding.Agent = '') then
    Exit;
  FFixKey := FindingKey(Finding);
  FFixJob := TGittanFixJob.Create(FRepo.Root, FAI, FRepo.Base, Finding);
  FFixJob.OnDone := @FixJobDone;
  FFixJob.Start;
  FStatus.ShowBusy(Format(rsFixing, [AgentName, Finding.Line, Finding.Path]), HintSparkle);
  Edit.Invalidate;
  FEditOld.Invalidate;
end;

{ The fix is written as a discard (refused when the file changed since
  it was read, or while it is being edited), so Undo Discard takes it
  back; its finding is marked resolved, which folds its card. }
procedure TRepoFrame.FixJobDone(Sender: TObject);
var
  Job: TGittanFixJob;
  Agent, Err, Why, Key: string;
  i: integer;
begin
  Job := TGittanFixJob(Sender);
  if Job <> FFixJob then
    Exit;
  FFixJob := nil;
  FFixKey := '';
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  FStatus.ShowMessage('', stNormal, 0);
  Agent := Job.AgentName;
  Why := Job.Why;
  if not Job.Ok then
    BannerError(Format(rsFixFailed, [Agent]), Job.Error)
  else if not Job.Changed then
    StatusNote(Format(rsFixNone, [Agent, Why]))
  else if EditingRepoPath(Job.Finding.Path) then
    StatusNote(Format(rsFixEditing, [Agent, Job.Finding.Path]), True)
  else if not DiscardBlock(Job.Block, Err) then
    StatusNote(Format(rsFixWriteFailed, [Err]), True)
  else
  begin
    NoteDiscard(Job.Block);
    Key := FindingKey(Job.Finding);
    for i := 0 to High(FAIThreads) do
      if FindingKey(FAIThreads[i]) = Key then
        FAIThreads[i].Resolved := True;
    if Why = '' then
      Why := rsResolvedAIUndo;
    CollectShownThreads;
    RefreshRepository;
    UpdateDiscardItems;
    RebuildIfChanges;
    StatusNote(Format(rsFixed, [Agent, Job.Finding.Path, Why]));
    Exit;
  end;
  Edit.Invalidate;
  FEditOld.Invalidate;
end;

procedure TRepoFrame.AbandonFixJob;
begin
  if FFixJob = nil then
    Exit;
  FFixJob.Stop(False);
  FBlameZombies.Add(FFixJob);
  FFixJob := nil;
  FFixKey := '';
end;

{ ---------------------------------------------------------------------------
  Explaining lines
  --------------------------------------------------------------------------- }

{ The rows the selection spans when it spans more than one and holds
  ARow (ARow -1 for the caret's), else ARow's alone. A selection that
  ends at the start of a row does not take that row. }
procedure WhyRows(AEd: TATSynEdit; ARow: integer; out AFrom, ATo: integer);
var
  X1, Y1, X2, Y2: integer;
  Sel: boolean;
begin
  if ARow < 0 then
    ARow := AEd.Carets[0].PosY;
  AFrom := ARow;
  ATo := ARow;
  AEd.Carets[0].GetRange(X1, Y1, X2, Y2, Sel);
  if Sel and (X2 = 0) and (Y2 > Y1) then
    Dec(Y2);
  if Sel and (Y2 > Y1) and (ARow >= Y1) and (ARow <= Y2) then
  begin
    AFrom := Y1;
    ATo := Y2;
  end;
end;

procedure TRepoFrame.MenuWhyClick(Sender: TObject);
var
  FromRow, ToRow: integer;
begin
  if FWhyJob <> nil then
  begin
    StartWhyJob(-1, -1);
    Exit;
  end;
  WhyRows(Edit, -1, FromRow, ToRow);
  StartWhyJob(FromRow, ToRow);
end;

procedure TRepoFrame.MenuWhyEditClick(Sender: TObject);
var
  FromRow, ToRow: integer;
begin
  if FWhyJob <> nil then
  begin
    StartWhyJob(-1, -1);
    Exit;
  end;
  if (FPopupEd <> Edit) or (FPopupRow < 0) then
    Exit;
  WhyRows(Edit, FPopupRow, FromRow, ToRow);
  StartWhyJob(FromRow, ToRow);
end;

{ The lines in the commit the history starts from (ChunkLines,
  HistoryRef), as Code History takes them; the card goes under the last
  row that has a line, on the new side, or the old for a removed one. }
procedure TRepoFrame.StartWhyJob(AFromRow, AToRow: integer);
var
  FromLine, ToLine, r, Line: integer;
begin
  if FWhyJob <> nil then
  begin
    AbandonWhyJob;
    FStatus.ShowMessage('', stNormal, 0);
    UpdateAIReviewItems;
    Exit;
  end;
  if not AIAvailable or (FRepo.Root = '') then
    Exit;
  if (FView <> gvChanges) or (FCurrentPath = '') or (FEditPath <> '') then
  begin
    StatusNote(rsWhyNeedsChanges);
    Exit;
  end;
  if not ChunkLines(AFromRow, AToRow, FromLine, ToLine) then
  begin
    StatusNote(rsNoHistoryYet);
    Exit;
  end;
  FWhyThread := Default(TGittanReviewThread);
  FWhyThread.Path := FCurrentPath;
  for r := Min(AToRow, High(FRows)) downto AFromRow do
  begin
    Line := FRows[r].Line;
    if (Line < 0) then
      Continue;
    if (Line <= High(FNewNum)) and (FNewNum[Line] > 0) then
      FWhyThread.Line := FNewNum[Line]
    else if (Line <= High(FOldNum)) and (FOldNum[Line] > 0) then
    begin
      FWhyThread.Line := FOldNum[Line];
      FWhyThread.LeftSide := True;
    end
    else
      Continue;
    Break;
  end;
  FWhyThread.OriginalLine := FWhyThread.Line;
  FWhyKey := AIReviewKey;
  FWhyJob := TGittanWhyJob.Create(FRepo.Root, FAI, FCurrentPath, HistoryRef, FromLine,
    ToLine);
  FWhyJob.OnDone := @WhyJobDone;
  FWhyJob.Start;
  FStatus.ShowBusy(Format(rsWhyLooking, [AgentName, FromLine, ToLine, FCurrentPath]),
    HintSparkle);
  UpdateAIReviewItems;
end;

{ The explanation is a card among the review's findings for the
  comparison it was asked in, in place of one for the same line; it
  goes with them on Clear AI Review. One asked in another comparison
  than the findings held, while theirs is the one shown, is dropped
  rather than drop them. }
procedure TRepoFrame.WhyJobDone(Sender: TObject);
var
  Job: TGittanWhyJob;
  T: TGittanReviewThread;
  i: integer;
begin
  Job := TGittanWhyJob(Sender);
  if Job <> FWhyJob then
    Exit;
  FWhyJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  FStatus.ShowMessage('', stNormal, 0);
  if not Job.Ok then
  begin
    BannerError(Format(rsWhyFailed, [Job.AgentName]), Job.Error);
    UpdateAIReviewItems;
    Exit;
  end;
  if (FAIThreadsKey <> FWhyKey) and (Length(FAIThreads) > 0) and
    (FAIThreadsKey = AIReviewKey) then
  begin
    UpdateAIReviewItems;
    Exit;
  end;
  T := FWhyThread;
  T.Agent := Job.AgentName;
  T.Severity := WhySeverity;
  SetLength(T.Comments, 1);
  T.Comments[0].Author := Job.AgentName;
  T.Comments[0].Body := Job.Text;
  T.Comments[0].Created := LocalTimeToUniversal(Now);
  if FAIThreadsKey <> FWhyKey then
  begin
    FAIThreads := nil;
    FAIThreadsKey := FWhyKey;
  end;
  for i := High(FAIThreads) downto 0 do
    if (FAIThreads[i].Severity = WhySeverity) and (FAIThreads[i].Path = T.Path) and
      (FAIThreads[i].Line = T.Line) and (FAIThreads[i].LeftSide = T.LeftSide) then
      Delete(FAIThreads, i, 1);
  Insert(T, FAIThreads, Length(FAIThreads));
  StatusNote(Format(rsWhyDone, [Job.AgentName, Job.FromLine, Job.ToLine, Job.Path]));
  CollectShownThreads;
  FileTree.Invalidate;
  RebuildIfChanges;
  UpdateAIReviewItems;
end;

procedure TRepoFrame.AbandonWhyJob;
begin
  if FWhyJob = nil then
    Exit;
  FWhyJob.Stop(False);
  FBlameZombies.Add(FWhyJob);
  FWhyJob := nil;
end;
