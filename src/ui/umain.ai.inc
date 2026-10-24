{ ---------------------------------------------------------------------------
  The AI features
  ---------------------------------------------------------------------------
  An agent's command line tool, Claude Code's claude or GitHub Copilot's
  copilot, run in the repository (gittan.ai). Nothing of it shows until
  the settings turn the features on (AI page, off by default, since the
  changes go to the agent's provider) and the command of the agent they
  pick is found. The first feature is the Write button in the commit
  row: the agent writes the message for the ticked files, which goes
  into the field when the field is as it was when the button was
  clicked. A click while it writes stops it. }

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
  merge or a rebase has its message); while it writes the button stops
  it, otherwise it needs files ticked (or Amend, which describes HEAD)
  and no commit running. }
procedure TForm1.UpdateMessageButton;
begin
  if FMessageButton = nil then
    Exit;
  FMessageButton.Visible := AIAvailable and (FOperation = '') and CommitChoosing;
  if FMessageJob <> nil then
  begin
    FMessageButton.Caption := rsWritingMessage;
    FMessageButton.Hint := Format(rsWritingMessageHint, [AgentNames[FAgent]]);
    FMessageButton.Enabled := True;
  end
  else
  begin
    FMessageButton.Caption := rsWriteMessage;
    FMessageButton.Hint := Format(rsWriteMessageHint, [AgentNames[FAgent]]);
    FMessageButton.Enabled := (FCommitJob = nil) and ((FChosenCount > 0) or
      FCommitAmend.Checked);
  end;
end;

procedure TForm1.MessageButtonClick(Sender: TObject);
begin
  if FMessageJob <> nil then
  begin
    AbandonMessageJob;
    FStatus.ShowMessage('', stNormal, 0);
    UpdateCommitState;
  end
  else
    StartMessageJob;
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
