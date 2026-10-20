{ ---------------------------------------------------------------------------
  A newer Gittan
  ---------------------------------------------------------------------------
  A build from CI knows its number (gittan.update). A little after start,
  and every UpdatePoll ms after that, a TGittanUpdateJob asks GitHub for
  the latest release; when it is newer, the status bar shows a green
  badge ("Build 109 available") unless Remind Me Later was chosen less
  than UpdateSnoozeDays ago. A click on the badge, or Tools > Check for
  Updates, opens the dialog: Download opens the release's page, Remind Me
  Later hides the badge for UpdateSnoozeDays. The menu's check always
  answers, also when Gittan is up to date, a local build or offline. A
  local build never checks by itself. }

procedure TForm1.StartUpdateCheck(AManual: boolean);
begin
  { A check under way answers the menu too when it ends. }
  FUpdateManual := FUpdateManual or AManual;
  if FUpdateJob <> nil then
    Exit;
  FUpdateTimer.Enabled := False;
  FUpdateJob := TGittanUpdateJob.Create;
  FUpdateJob.OnDone := @UpdateJobDone;
  FUpdateJob.Start;
end;

procedure TForm1.UpdateTimerTimer(Sender: TObject);
begin
  FUpdateTimer.Enabled := False;
  StartUpdateCheck(False);
end;

procedure TForm1.AbandonUpdateJob;
begin
  FUpdateTimer.Enabled := False;
  if FUpdateJob = nil then
    Exit;
  FUpdateJob.Stop(False);
  FBlameZombies.Add(FUpdateJob);
  FUpdateJob := nil;
end;

procedure TForm1.UpdateJobDone(Sender: TObject);
var
  Job: TGittanUpdateJob;
  Manual: boolean;
begin
  Job := TGittanUpdateJob(Sender);
  if Job <> FUpdateJob then
    Exit;
  FUpdateJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  Manual := FUpdateManual;
  FUpdateManual := False;
  if CurrentBuild >= 0 then
  begin
    FUpdateTimer.Interval := UpdatePoll;
    FUpdateTimer.Enabled := True;
  end;
  if Job.Ok then
  begin
    FUpdateRelease := Job.Release;
    FHasUpdate := IsNewerRelease(FUpdateRelease, CurrentBuild);
    ShowUpdateBadge;
  end;
  if not Manual then
    Exit;
  if not Job.Ok then
    BannerError(rsUpdateTitle, Format(rsUpdateFailed, [Job.Error]))
  else if FHasUpdate then
    UpdateDialog
  else if CurrentBuild < 0 then
  begin
    if QuestionDlg(rsUpdateTitle, Format(rsUpdateLocalBuild, [FUpdateRelease.Name]),
      mtInformation, [mrYes, rsUpdateOpenPage, mrCancel, rsUpdateClose, 'IsDefault'],
      0) = mrYes then
      OpenURL(FUpdateRelease.Url);
  end
  else
    BannerInfo(Format(rsUpdateCurrent, [CurrentBuild]));
end;

procedure TForm1.ShowUpdateBadge;
begin
  if FHasUpdate and (Date >= FSettings.UpdateSnoozedUntil) then
  begin
    FStatus.SetUpdate(Format(rsUpdateBadge, [FUpdateRelease.Build]));
    FStatus.PartHint[spUpdate] := Format(rsUpdateHint, [FUpdateRelease.Name,
      CurrentBuild]) + LineEnding + HintLink + ' ' + rsUpdateHintClick;
  end
  else
    FStatus.SetUpdate('');
end;

procedure TForm1.UpdateDialog;
begin
  case QuestionDlg(rsUpdateTitle, Format(rsUpdateAvailable, [FUpdateRelease.Name,
      CurrentBuild]), mtInformation, [mrYes, rsUpdateDownload, 'IsDefault',
      mrIgnore, Format(rsUpdateLater, [UpdateSnoozeDays]), mrCancel, rsUpdateNotNow,
      'IsCancel'], 0) of
    mrYes:
      OpenURL(FUpdateRelease.Url);
    mrIgnore:
    begin
      FSettings.UpdateSnoozedUntil := Date + UpdateSnoozeDays;
      ShowUpdateBadge;
    end;
  end;
end;

procedure TForm1.MenuCheckUpdatesClick(Sender: TObject);
begin
  StartUpdateCheck(True);
end;
