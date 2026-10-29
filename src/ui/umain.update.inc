{ ---------------------------------------------------------------------------
  A newer Gittan
  ---------------------------------------------------------------------------
  A build from CI knows its number (gittan.update). The check itself,
  a little after start and every UpdatePoll ms after that, is App's
  (gittan.app); when the latest release is newer, the status bar shows a
  green badge ("Build 109 available") unless Remind Me Later was chosen
  less than UpdateSnoozeDays ago. A click on the badge, or Tools > Check
  for Updates, opens the dialog: Download opens the release's page,
  Remind Me Later hides the badge for UpdateSnoozeDays. The menu's check
  always answers, also when Gittan is up to date, a local build or
  offline. A local build never checks by itself. }

procedure TRepoFrame.UpdateChecked(Sender: TObject; AManual: boolean);
begin
  if App.UpdateOk then
    ShowUpdateBadge;
  if not AManual then
    Exit;
  if not App.UpdateOk then
    BannerError(rsUpdateTitle, Format(rsUpdateFailed, [App.UpdateError]))
  else if App.HasUpdate then
    UpdateDialog
  else if CurrentBuild < 0 then
  begin
    if AskDlg(rsUpdateTitle, Format(rsUpdateLocalBuild, [App.UpdateRelease.Name]),
      mtInformation, [mrYes, rsUpdateOpenPage, mrCancel, rsUpdateClose, 'IsDefault'],
      0) = mrYes then
      OpenURL(App.UpdateRelease.Url);
  end
  { A release tagged other than build-<n> cannot be compared, and says
    nothing of whether this build is current. }
  else if App.UpdateRelease.Build < 0 then
    BannerInfo(Format(rsUpdateNoBuild, [App.UpdateRelease.Name, CurrentBuild]))
  else
    BannerInfo(Format(rsUpdateCurrent, [CurrentBuild]));
end;

procedure TRepoFrame.ShowUpdateBadge;
begin
  if App.UpdateDue then
  begin
    FStatus.SetUpdate(Format(rsUpdateBadge, [App.UpdateRelease.Build]));
    FStatus.PartHint[spUpdate] := Format(rsUpdateHint, [App.UpdateRelease.Name,
      CurrentBuild]) + LineEnding + HintLink + ' ' + rsUpdateHintClick;
  end
  else
    FStatus.SetUpdate('');
end;

procedure TRepoFrame.UpdateDialog;
begin
  case AskDlg(rsUpdateTitle, Format(rsUpdateAvailable, [App.UpdateRelease.Name,
      CurrentBuild]), mtInformation, [mrYes, rsUpdateDownload, 'IsDefault',
      mrIgnore, Format(rsUpdateLater, [UpdateSnoozeDays]), mrCancel, rsUpdateNotNow,
      'IsCancel'], 0) of
    mrYes:
      OpenURL(App.UpdateRelease.Url);
    mrIgnore:
    begin
      App.SnoozeUpdate;
      ShowUpdateBadge;
    end;
  end;
end;

procedure TRepoFrame.MenuCheckUpdatesClick(Sender: TObject);
begin
  App.CheckForUpdate(True);
end;
