{ ---------------------------------------------------------------------------
  Stashes
  ---------------------------------------------------------------------------
  The Stash menu stashes the local changes (every one, or the files
  ticked in the tree), pops or applies the newest stash, and lists the
  stashes; the status bar shows how many there are as a chip with a
  box, which drops the same list (ShowStashList). A row of the list is
  a stash with its branch, age and whether it holds untracked files,
  the one compared against checked; a pick shows what the stash holds,
  comparing the commit it is against the one it was made on
  (CompareStash, the range StashRange), and a right click (or the Menu
  key) offers what can be done with it: apply, pop, make a branch from
  it, drop. While a stash is compared against, the base label in the
  summary and the status bar is a chip that drops Apply, Pop and Drop,
  as a compared branch drops Merge and Rebase, so looking comes first.
  A stash whose changes clash with the work tree leaves the files in
  conflict, to resolve as after a merge, and is kept. The stashes come
  with every snapshot of the repository (FStashes), so one made or
  dropped in a terminal shows up through the watcher. }
const
  { The tag of the list's New row; a stash's row has its index. }
  StashRowNew = -2;
  smApply = 1;
  smPop = 2;
  smBranch = 3;
  smCompare = 4;
  smDrop = 5;

{ The message as the list and the notes show it, cut to a line. }
function TRepoFrame.StashLabel(const AStash: TGittanStash): string;
begin
  Result := AStash.Message;
  if Length(Result) > 60 then
    Result := UTF8Copy(Result, 1, 57) + '...';
end;

{ The index in FStashes of the stash compared against, -1 for none. }
function TRepoFrame.StashOfBase: integer;
var
  i: integer;
begin
  Result := -1;
  if (FRepo.Root = '') or (FStashRange = '') or (FRepo.Base <> FStashRange) then
    Exit;
  for i := 0 to High(FStashes) do
    if FStashes[i].Id = FStashRangeId then
      Exit(i);
end;

procedure TRepoFrame.ShowStashList(const AScreenRect: TRect);
var
  i: integer;
  Detail: string;
  Compared: integer;
begin
  if FRepo.Root = '' then
    Exit;
  Compared := StashOfBase;
  FStashPopup.Clear;
  FListedStashes := Copy(FStashes);
  if (FFileCount > 0) and RepoReady and (FConflictFiles = 0) then
    FStashPopup.Add(rsStashNewRow, '', False, StashRowNew);
  if Length(FStashes) = 0 then
    FStashPopup.AddHeader(rsNoStashes)
  else
    FStashPopup.AddHeader(rsStashes);
  for i := 0 to High(FStashes) do
  begin
    Detail := FStashes[i].Branch;
    if Detail <> '' then
      Detail := Detail + ' · ';
    Detail := Detail + BlameAge(FStashes[i].Time, DateTimeToUnix(Now, False));
    if FStashes[i].Untracked then
      Detail := Detail + ' · ' + rsStashUntracked;
    FStashPopup.Add(StashLabel(FStashes[i]), Detail, i = Compared, i);
  end;
  FStashPopup.Popup(AScreenRect);
end;

procedure TRepoFrame.StashPopupPick(Sender: TObject; AIndex: integer);
var
  Row: PtrInt;
begin
  Row := FStashPopup.TagOf(AIndex);
  if Row = StashRowNew then
    StashChangesAsk(False)
  else if (Row >= 0) and (Row <= High(FListedStashes)) then
    CompareStash(FListedStashes[Row]);
end;

procedure TRepoFrame.StashContext(Sender: TObject; AIndex: integer; const AScreenPos: TPoint);
var
  Busy: boolean;
  Row: PtrInt;

  procedure Add(const ACaption: string; ATag: integer; AEnabled: boolean);
  begin
    AddMenuItem(FStashMenu.Items, ACaption, ATag, AEnabled, @StashMenuClick);
  end;

begin
  Row := FStashPopup.TagOf(AIndex);
  if (Row < 0) or (Row > High(FListedStashes)) then
    Exit;
  FMenuStash := FListedStashes[Row];
  Busy := not RepoReady;
  FStashMenu.Items.Clear;
  Add(rsSmApply, smApply, not Busy);
  Add(rsSmPop, smPop, not Busy);
  Add(rsSmBranch, smBranch, not Busy);
  FStashMenu.Items.Add(NewLine);
  Add(rsSmCompare, smCompare, not ComparingStash(FMenuStash.Id));
  FStashMenu.Items.Add(NewLine);
  Add(rsSmDrop, smDrop, (FCommitJob = nil) and (FRemoteJob = nil));
  FStashMenu.PopUp(AScreenPos.X, AScreenPos.Y);
end;

procedure TRepoFrame.StashMenuClick(Sender: TObject);
var
  Stash: TGittanStash;
begin
  Stash := FMenuStash;
  if (FRepo.Root = '') or (Stash.Id = '') then
    Exit;
  FStashPopup.Close;
  case (Sender as TMenuItem).Tag of
    smApply: ApplyStash(Stash, False);
    smPop: ApplyStash(Stash, True);
    smBranch: BranchFromStashAsk(Stash);
    smCompare: CompareStash(Stash);
    smDrop: DropStashAsk(Stash);
  end;
end;

{ Asks for a message, which may be left empty (git then names the
  stash after HEAD), and stashes every change, or with AChosenOnly the
  files ticked in the tree. git makes no stash when there is nothing
  to save, which the count of stashes after the refresh tells. }
procedure TRepoFrame.StashChangesAsk(AChosenOnly: boolean);
var
  Paths: TStringList;
  Values: array of string;
  Prompt, Err: string;
  Before, Count: integer;
  Ok: boolean;
begin
  if not RepoReady or (FConflictFiles > 0) then
    Exit;
  Paths := TStringList.Create;
  try
    if AChosenOnly then
    begin
      if not CommitChoosing then
        Exit;
      ChosenCommitPaths(Paths);
      if Paths.Count = 0 then
        Exit;
      Prompt := Format(rsStashPromptChosen, [Paths.Count]);
      Count := Paths.Count;
    end
    else
    begin
      Prompt := rsStashPrompt;
      Count := FFileCount;
    end;
    SetLength(Values, 1);
    Values[0] := '';
    if not InputQuery(rsStashTitle, [Prompt], Values) then
      Exit;
    Before := Length(FStashes);
    StopWatcher;
    try
      if AChosenOnly then
        Ok := FRepo.Stash(Trim(Values[0]), Paths)
      else
        Ok := FRepo.Stash(Trim(Values[0]));
      Err := FRepo.Error;
      FSummary.Notice := '';
      RefreshRepository;
    finally
      StartWatcher;
    end;
    if not Ok then
      BannerError(rsStashFailed, Err)
    else if Length(FStashes) = Before then
      StatusNote(rsNothingToStash)
    else if Count = 1 then
      StatusNote(rsStashedOne)
    else
      StatusNote(Format(rsStashed, [Count]));
  finally
    Paths.Free;
  end;
end;

{ Back to the work tree after the stash went in, so the views show
  the changes it brought: a compared stash (this one or another) is a
  range, which shows the stash's commit, not the tree. The stash comes
  by value here and in the others that refresh, since one given as
  FStashes[i] is gone with the array once the refresh lists them
  again. }
procedure TRepoFrame.ApplyStash(AStash: TGittanStash; APop: boolean);
var
  Ok, Conflicts: boolean;
  Err: string;
begin
  if not RepoReady then
    Exit;
  StopWatcher;
  try
    Screen.Cursor := crHourGlass;
    try
      Ok := FRepo.StashApply(AStash.Id, APop, Conflicts);
    finally
      Screen.Cursor := crDefault;
    end;
    { The refresh runs git too, which may leave a reason of its own. }
    Err := FRepo.Error;
    FSummary.Notice := '';
    if (FStashRange <> '') and (FRepo.Base = FStashRange) then
      SetBase('')
    else
      RefreshRepository;
  finally
    StartWatcher;
  end;
  if Ok and APop then
    StatusNote(Format(rsStashPopped, [StashLabel(AStash)]))
  else if Ok then
    StatusNote(Format(rsStashApplied, [StashLabel(AStash)]))
  else if Conflicts then
    BannerError(rsStashConflictsTitle, rsStashConflictsKept + LineEnding + LineEnding + Err)
  else
    BannerError(rsStashApplyFailed, Err);
end;

procedure TRepoFrame.DropStashAsk(AStash: TGittanStash);
begin
  if (FCommitJob <> nil) or (FRemoteJob <> nil) then
    Exit;
  if QuestionDlg(rsDropStashTitle, Format(rsDropStashAsk, [StashLabel(AStash)]), mtWarning,
    [mrYes, rsDropAction, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes then
    Exit;
  StopWatcher;
  try
    if FRepo.StashDrop(AStash.Id) then
    begin
      if ComparingStash(AStash.Id) then
        SetBase('')
      else
        RefreshRepository;
      StatusNote(Format(rsStashDropped, [StashLabel(AStash)]));
    end
    else
      BannerError(rsCaFailed, FRepo.Error);
  finally
    StartWatcher;
  end;
end;

procedure TRepoFrame.BranchFromStashAsk(AStash: TGittanStash);
var
  Values: array of string;
begin
  if not RepoReady then
    Exit;
  SetLength(Values, 1);
  Values[0] := '';
  if not InputQuery(rsStashBranchTitle, [rsStashBranchPrompt], Values) or
    (Trim(Values[0]) = '') then
    Exit;
  StopWatcher;
  try
    if FRepo.StashBranch(Trim(Values[0]), AStash.Id) then
    begin
      FLoadError := '';
      FSummary.Notice := '';
      if ComparingStash(AStash.Id) then
        SetBase('')
      else
        RefreshRepository;
      StatusNote(Format(rsStashBranched, [Trim(Values[0])]));
    end
    else
      BannerError(rsCaFailed, FRepo.Error);
  finally
    StartWatcher;
  end;
end;

{ Whether the stash AId is the one compared against. }
function TRepoFrame.ComparingStash(const AId: string): boolean;
begin
  Result := (FStashRange <> '') and (FRepo.Base = FStashRange) and (FStashRangeId = AId);
end;

procedure TRepoFrame.CompareStash(AStash: TGittanStash);
var
  Range: string;
begin
  if ComparingStash(AStash.Id) then
    Exit;
  if not FRepo.StashRange(AStash.Id, Range) then
  begin
    BannerError(rsCaFailed, FRepo.Error);
    Exit;
  end;
  FStashRange := Range;
  FStashRangeId := AStash.Id;
  SetBase(FStashRange);
end;

{ The base chip while a stash is compared against: Apply, Pop and
  Drop. }
procedure TRepoFrame.StashBaseClick(const AScreenRect: TRect);
var
  i: integer;
begin
  i := StashOfBase;
  if i < 0 then
    Exit;
  FBaseStashId := FStashes[i].Id;
  FBaseActionRef := '';
  FBasePopup.Clear;
  FBasePopup.AddHeader(Format(rsVsStash, [StashLabel(FStashes[i])]));
  FBaseApplyIndex := FBasePopup.Add(rsSmApply);
  FBasePopIndex := FBasePopup.Add(rsSmPop);
  FBaseDropIndex := FBasePopup.Add(rsSmDrop);
  FBasePopup.Popup(AScreenRect);
end;

procedure TRepoFrame.StashBasePick(AIndex: integer);
var
  i: integer;
begin
  i := StashOfBase;
  if (i < 0) or (FStashes[i].Id <> FBaseStashId) then
    Exit;
  if AIndex = FBaseApplyIndex then
    ApplyStash(FStashes[i], False)
  else if AIndex = FBasePopIndex then
    ApplyStash(FStashes[i], True)
  else if AIndex = FBaseDropIndex then
    DropStashAsk(FStashes[i]);
end;

{ The Stash menu's items: stashing with changes to stash (the ticked
  files only while the tree chooses what to commit), popping and
  applying with a stash, none while git is in the middle of something
  or a commit, fetch, pull or push runs. Called as the menu opens and
  whenever the repository or a job changes, for the shortcuts. }
procedure TRepoFrame.UpdateStashItems;
var
  Has, Busy: boolean;
  Chosen, i: integer;
begin
  if FStashAllItem = nil then
    Exit;
  Has := (FRepo <> nil) and (FRepo.Root <> '');
  Busy := not Has or not RepoReady;
  Chosen := 0;
  if Has and CommitChoosing then
    for i := 0 to High(FStats) do
      if (FStats[i].Kind <> ckConflict) and CommitChosen(i) then
        Inc(Chosen);
  FStashAllItem.Enabled := not Busy and (FFileCount > 0) and (FConflictFiles = 0);
  FStashChosenItem.Enabled := not Busy and (Chosen > 0) and (FConflictFiles = 0);
  FPopStashItem.Enabled := not Busy and (Length(FStashes) > 0);
  FApplyStashItem.Enabled := FPopStashItem.Enabled;
  FStashListItem.Enabled := Has;
end;

procedure TRepoFrame.StashMenuOpen(Sender: TObject);
begin
  UpdateStashItems;
end;

procedure TRepoFrame.MenuStashAllClick(Sender: TObject);
begin
  StashChangesAsk(False);
end;

procedure TRepoFrame.MenuStashChosenClick(Sender: TObject);
begin
  StashChangesAsk(True);
end;

procedure TRepoFrame.MenuPopStashClick(Sender: TObject);
begin
  if Length(FStashes) > 0 then
    ApplyStash(FStashes[0], True);
end;

procedure TRepoFrame.MenuApplyStashClick(Sender: TObject);
begin
  if Length(FStashes) > 0 then
    ApplyStash(FStashes[0], False);
end;

procedure TRepoFrame.MenuStashListClick(Sender: TObject);
begin
  if FRepo.Root <> '' then
    ShowStashList(FStatus.PartScreenRect(spStash));
end;
