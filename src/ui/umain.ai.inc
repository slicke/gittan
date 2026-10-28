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
  kept for that comparison until the next review or Clear AI Review. }

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
