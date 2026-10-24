{ ---------------------------------------------------------------------------
  The AI features
  ---------------------------------------------------------------------------
  An agent's command line tool, Claude Code's claude or GitHub Copilot's
  copilot, run in the repository (gittan.ai). Nothing of it shows until
  the settings turn the features on (AI page, off by default, since the
  changes go to the agent's provider) and the command of the agent they
  pick is found. The first feature is AI at the right end of the Commit
  header, and File > Write Commit Message (Shift+Cmd+K): the agent
  writes the message for the ticked files, which goes into the field
  when the field is as it was when it was asked. Either again while it
  writes stops it.

  The second is View > Review Changes with AI (Alt+Cmd+R): the agent
  reviews what the change view compares, and its findings are cards in
  the change view among a pull request's threads (see umain.reviews.inc),
  kept for that comparison until the next review or Clear AI Review. }

{ The agent the settings pick, its command by the path they give, else
  where it is found, and its model. }
procedure TForm1.FindAgentCli;
begin
  FAgent := AgentOfKey(FSettings.AIAgent);
  if FAgent = gaCopilot then
  begin
    FAgentCli := FindAgent(FAgent, FSettings.CopilotPath);
    FAgentModel := FSettings.CopilotModel;
  end
  else
  begin
    FAgentCli := FindAgent(FAgent, FSettings.ClaudePath);
    FAgentModel := FSettings.ClaudeModel;
  end;
end;

function TForm1.AIAvailable: boolean;
begin
  Result := FSettings.AIEnabled and (FAgentCli <> '');
end;

{ Shown with the features on and nothing for git to carry on with (a
  merge or a rebase has its message); while it writes it stops it,
  otherwise it needs files ticked (or Amend, which describes HEAD) and
  no commit running. The menu item stays in the menu while the features
  are on, disabled when the header has no AI. }
procedure TForm1.UpdateMessageAction;
var
  Shown, Can: boolean;
begin
  if (FCommitHeader = nil) or (FMessageItem = nil) then
    Exit;
  Shown := AIAvailable and (FOperation = '') and CommitChoosing;
  if FMessageJob <> nil then
  begin
    FCommitHeader.Action := rsWritingMessage;
    FCommitHeader.ActionHint := Format(rsWritingMessageHint, [AgentNames[FAgent]]);
    FMessageItem.Caption := rsStopMessageMenu;
    Can := True;
  end
  else
  begin
    FCommitHeader.Action := rsWriteMessage;
    FCommitHeader.ActionHint := Format(rsWriteMessageHint, [AgentNames[FAgent]]);
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
procedure TForm1.MessageActionClick(Sender: TObject);
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

procedure TForm1.StartMessageJob;
var
  Paths: TStringList;
begin
  if (FMessageJob <> nil) or not AIAvailable or (FRepo.Root = '') then
    Exit;
  Paths := TStringList.Create;
  try
    ChosenCommitPaths(Paths);
    FMessageJob := TGittanMessageJob.Create(FRepo.Root, FAgent, FAgentCli, FAgentModel,
      Paths, FCommitAmend.Checked);
  finally
    Paths.Free;
  end;
  FMessageFrom := FCommitMemo.Text;
  FMessageJob.OnDone := @MessageJobDone;
  FMessageJob.Start;
  FStatus.ShowMessage(Format(rsWritingStatus, [AgentNames[FAgent]]), stNormal, 0);
  UpdateCommitState;
end;

{ The message goes into the field unless the field was changed while
  the agent wrote; a failure says the agent's reason in a banner. The
  job is freed from the message loop, since its notification comes from
  inside Execute. }
procedure TForm1.MessageJobDone(Sender: TObject);
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
    BannerError(Format(rsMessageFailed, [AgentNames[Job.Agent]]), Job.Error)
  else if FCommitMemo.Text <> FMessageFrom then
    StatusNote(Format(rsMessageChanged, [AgentNames[Job.Agent]]))
  else
  begin
    FCommitMemo.Text := Job.Message;
    FCommitMemo.SelStart := 0;
  end;
  UpdateCommitState;
end;

procedure TForm1.AbandonMessageJob;
begin
  if FMessageJob = nil then
    Exit;
  FMessageJob.Stop(False);
  FBlameZombies.Add(FMessageJob);
  FMessageJob := nil;
end;

function TForm1.AIReviewKey: string;
begin
  Result := FRepo.Root + #0 + FRepo.Base + #0 + BoolToStr(FRepo.WholeTree, True);
end;

{ The review's items show while the features are on; Clear while there
  are findings for what is compared. }
procedure TForm1.UpdateAIReviewItems;
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

procedure TForm1.MenuAIReviewClick(Sender: TObject);
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

procedure TForm1.MenuAIClearClick(Sender: TObject);
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
procedure TForm1.StartAIReview;
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
    FAIReviewJob := TGittanAIReviewJob.Create(FRepo.Root, FAgent, FAgentCli, FAgentModel,
      FRepo.Base, FRepo.IsRange, Paths, AIReviewKey);
  finally
    Paths.Free;
  end;
  FAIReviewJob.OnDone := @AIReviewDone;
  FAIReviewJob.Start;
  FStatus.ShowMessage(Format(rsAIReviewing, [AgentNames[FAgent]]), stNormal, 0);
  UpdateAIReviewItems;
end;

{ The findings replace those held, and show while their comparison is
  the one shown; the status bar says how many there are. }
procedure TForm1.AIReviewDone(Sender: TObject);
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
  Agent := AgentNames[Job.Agent];
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

procedure TForm1.AbandonAIReview;
begin
  if FAIReviewJob = nil then
    Exit;
  FAIReviewJob.Stop(False);
  FBlameZombies.Add(FAIReviewJob);
  FAIReviewJob := nil;
end;
