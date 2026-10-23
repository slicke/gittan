{ ---------------------------------------------------------------------------
  The Commands page
  ---------------------------------------------------------------------------
  The repository's own commands (gittan.repocommands: .gittan/commands.ini,
  the scripts of package.json, the targets of a Makefile) as tiles on a
  page in the box (gittan.commandpage), opened from the sidebar's
  Commands row, View > Commands (Cmd+4) and, on macOS, a click on
  "Gittan" in the toolbar. A tile runs its command in a TGittanCommandJob
  through the shell in the root, one at a time, its output drawn by the
  page's console as it comes; a command marked for the terminal opens in
  one instead. A key the file gives a command runs it from any view with
  Ctrl+Cmd (Ctrl+Alt elsewhere), once the file is trusted: a committed
  file could make a key run anything, so its commands wait for Trust
  Commands on the page, and the settings keep the hash of the text
  trusted per root. See spec/repo-commands.md. }

procedure TForm1.SetupCommandPage;
begin
  FCommandPage := TGittanCommandPage.Create(Self);
  FCommandPage.Parent := FSummaryBox;
  FCommandPage.Visible := False;
  {$IFDEF DARWIN}
  FCommandPage.ShortcutPrefix := '⌃⌘';
  {$ELSE}
  FCommandPage.ShortcutPrefix := 'Ctrl+Alt+';
  {$ENDIF}
  FCommandPage.OnRun := @CommandPageRun;
  FCommandPage.OnStop := @CommandPageStop;
  FCommandPage.OnTrust := @CommandPageTrust;
  FCommandPage.OnEditFile := @CommandPageEditFile;
  FCommandPage.OnCopyOutput := @CommandPageCopyOutput;
end;

function TForm1.CommandsTrusted: boolean;
begin
  Result := FSettings.CommandsTrusted(FRepo.Root, FCommandsHash);
end;

{ Reads the commands again (three small files) and hands them to the
  page; from ApplySnapshot, so an edit of the file or a pull that brings
  one is seen. A command of another repository is ended first. }
procedure TForm1.LoadRepoCommands;
begin
  if (FCommandJob <> nil) and (FCommandJob.Root <> FRepo.Root) then
    AbandonCommandJob(False);
  if FRepo.Root = '' then
  begin
    FRepoCommands := nil;
    FCommandsHash := '';
    Exit;
  end;
  FRepoCommands := DiscoverRepoCommands(FRepo.Root);
  FCommandsHash := CommandsFileHash(FRepo.Root);
  FCommandPage.SetRepository(ExtractFileName(FRepo.Root), FRepo.Root);
  FCommandPage.SetCommands(FRepoCommands, FCommandsHash <> '', CommandsTrusted);
end;

procedure TForm1.MenuCommandsClick(Sender: TObject);
begin
  if FRepo.Root <> '' then
    ShowCommands;
end;

{ The page takes the summary's place in the box, as the Repository page
  does. }
procedure TForm1.ShowCommands;
begin
  if FRepo.Root = '' then
    Exit;
  if FGraph.Visible then
    FGraph.Close;
  LeaveEditorViews;
  FView := gvCommands;
  FWelcome.Visible := False;
  FSummary.Visible := False;
  FSubPage.Visible := False;
  FRepoPage.Visible := False;
  if FCommandPage.Root <> FRepo.Root then
    LoadRepoCommands;
  FCommandPage.Visible := True;
  FCommandPage.FitHeight(FSummaryBox.ClientHeight);
  FSummaryBox.Visible := True;
  FSummaryBox.VertScrollBar.Position := 0;
  FStatus.SetPosition('');
  { A file picked again after the page must fire the selection event. }
  FileTree.Selected := nil;
  FRepoTree.Selected := nil;
  FSubTree.Selected := nil;
  SetNavRow(navCommands);
  UpdateStatus;
end;

procedure TForm1.CommandPageRun(Sender: TObject; AIndex: integer);
begin
  RunRepoCommand(AIndex, False);
end;

{ Runs the command at AIndex: in a terminal when it asks for one, else
  in a job whose output the page shows. The file's commands, and the
  keys it gives (AByKey), wait for the file to be trusted: the page is
  shown with its card instead. }
procedure TForm1.RunRepoCommand(AIndex: integer; AByKey: boolean);
var
  Cmd: TGittanRepoCommand;
begin
  if (FRepo.Root = '') or (AIndex < 0) or (AIndex > High(FRepoCommands)) then
    Exit;
  Cmd := FRepoCommands[AIndex];
  { A section that names no script or target has nothing to run. }
  if Cmd.Command = '' then
    Exit;
  if not CommandsTrusted and (AByKey or (Cmd.Source = csFile)) then
  begin
    ShowCommands;
    Exit;
  end;
  if Cmd.Terminal then
  begin
    OpenTerminal(Cmd.Command);
    Exit;
  end;
  if FCommandJob <> nil then
  begin
    StatusNote(Format(rsCommandStillRunning, [FCommandName]), True);
    ShowCommands;
    Exit;
  end;
  FCommandName := Cmd.Name;
  FCommandRead := 0;
  FCommandJob := TGittanCommandJob.Create(FRepo.Root, Cmd.Command);
  FCommandJob.OnOutput := @CommandJobOutput;
  FCommandJob.OnDone := @CommandJobDone;
  FCommandPage.Console.Text := '';
  FCommandPage.Console.FollowEnd := True;
  FCommandPage.SetRun(Cmd.Name, True, -1, 0, True, False);
  FCommandJob.Start;
  ShowCommands;
  { The output's heading at the top of the box, the console under it. }
  if FCommandPage.OutputTop >= 0 then
    FSummaryBox.VertScrollBar.Position := Max(0, FCommandPage.OutputTop - Px(8));
end;

{ What the command wrote since the last piece goes to the console; the
  whole text again when the job cut its start. }
procedure TForm1.CommandJobOutput(Sender: TObject);
var
  Written: string;
begin
  if Sender <> FCommandJob then
    Exit;
  Written := FCommandJob.Output;
  if (Length(Written) >= FCommandRead) and (Length(Written) < OutputKeep) then
    FCommandPage.Console.Append(Copy(Written, FCommandRead + 1, MaxInt))
  else
    FCommandPage.Console.Text := Written;
  FCommandRead := Length(Written);
end;

procedure TForm1.CommandJobDone(Sender: TObject);
var
  Job: TGittanCommandJob;
begin
  Job := TGittanCommandJob(Sender);
  if Job <> FCommandJob then
    Exit;
  CommandJobOutput(Job);
  FCommandJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  FCommandPage.Console.FollowEnd := False;
  FCommandPage.SetRun(FCommandName, False, Job.ExitCode, Job.ElapsedMs, Job.Started,
    Job.Killed);
  if FCommandPage.Visible then
    FCommandPage.FitHeight(FSummaryBox.ClientHeight);
  { The page says it in red too, so the status bar's note is enough. }
  if not Job.Started then
    FStatus.ShowMessage(Format(rsCommandNoStart, [FCommandName]), stBad, StatusErrorSeconds)
  else if Job.Killed then
    StatusNote(Format(rsCommandStopped, [FCommandName]))
  else if Job.ExitCode = 0 then
    StatusNote(Format(rsCommandDone, [FCommandName, FormatElapsed(Job.ElapsedMs)]))
  else
    FStatus.ShowMessage(Format(rsCommandFailed, [FCommandName, Job.ExitCode]), stBad,
      StatusErrorSeconds);
end;

{ Ends the command and drops the job: its end, if it comes, is thrown
  away. AWait, as on quitting, waits for it; else it goes to the zombie
  list as a blame job does. }
procedure TForm1.AbandonCommandJob(AWait: boolean);
var
  Job: TGittanCommandJob;
begin
  if FCommandJob = nil then
    Exit;
  Job := FCommandJob;
  FCommandJob := nil;
  Job.Kill;
  Job.Stop(AWait);
  if AWait then
    Job.Free
  else
  begin
    FBlameZombies.Add(Job);
    Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  end;
  FCommandPage.Console.FollowEnd := False;
  FCommandPage.SetRun(FCommandName, False, -1, Job.ElapsedMs, True, True);
end;

{ Stop on the page: the job ends it, and its end comes as Killed. }
procedure TForm1.CommandPageStop(Sender: TObject);
begin
  if FCommandJob <> nil then
    FCommandJob.Kill;
end;

procedure TForm1.CommandPageTrust(Sender: TObject);
begin
  if FRepo.Root = '' then
    Exit;
  FSettings.TrustCommands(FRepo.Root, FCommandsHash);
  FSettings.Save;
  FCommandPage.SetCommands(FRepoCommands, FCommandsHash <> '', CommandsTrusted);
end;

{ Edit… or Create…: the file opens in the editor as a Config file does;
  a new one is written with its commented example first, and the
  Config section lists it. }
procedure TForm1.CommandPageEditFile(Sender: TObject);
var
  FileName: string;
  F: TFileStream;
  Template: string;
begin
  if FRepo.Root = '' then
    Exit;
  FileName := IncludeTrailingPathDelimiter(FRepo.Root) + CommandsFolder + PathDelim + CommandsFile;
  if not FileExists(FileName) then
  begin
    try
      ForceDirectories(ExtractFileDir(FileName));
      Template := CommandsFileTemplate;
      F := TFileStream.Create(FileName, fmCreate);
      try
        F.WriteBuffer(Template[1], Length(Template));
      finally
        F.Free;
      end;
    except
      on E: Exception do
      begin
        StatusNote(E.Message, True);
        Exit;
      end;
    end;
    FillRepoFiles;
    LoadRepoCommands;
  end;
  ShowRepoFile(CommandsPath);
end;

procedure TForm1.CommandPageCopyOutput(Sender: TObject);
begin
  Clipboard.AsText := FCommandPage.Console.PlainText;
end;

{ A key of a command, with Ctrl+Cmd on macOS and Ctrl+Alt elsewhere;
  true when it ran one. }
function TForm1.CommandKey(AKey: word; AShift: TShiftState): boolean;
var
  i: integer;
begin
  Result := False;
  {$IFDEF DARWIN}
  if AShift * [ssShift, ssAlt, ssCtrl, ssMeta] <> [ssCtrl, ssMeta] then
    Exit;
  {$ELSE}
  if AShift * [ssShift, ssAlt, ssCtrl, ssMeta] <> [ssCtrl, ssAlt] then
    Exit;
  {$ENDIF}
  if not (((AKey >= VK_A) and (AKey <= VK_Z)) or ((AKey >= VK_0) and (AKey <= VK_9))) then
    Exit;
  i := CommandByKey(FRepoCommands, Chr(AKey));
  if i < 0 then
    Exit;
  RunRepoCommand(i, True);
  Result := True;
end;
