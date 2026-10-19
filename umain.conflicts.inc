{ ---------------------------------------------------------------------------
  Resolving conflicts
  ---------------------------------------------------------------------------
  A conflicted file offers Use Mine, Use Theirs and Mark Resolved as
  pills in its header (and the toolbar on macOS) and in the file menu.
  Mine is the user's own work and theirs what came in, whichever of
  git's ours and theirs that is (TGittanConflictSide). Taking a side
  asks first, since the edits made to the file are lost; marking a file
  that still has conflict markers asks too. What git is in the middle of
  is carried on in the Commit section (umain.commit.inc): a merge is
  committed there with git's message filled in, a rebase, cherry-pick,
  revert or am goes on with Continue (or Skip), and any of them can be
  given up with Abort. These run on the main thread: they are local and
  quick, and nothing else may touch the repository meanwhile. }

{ The operation as a noun for the dialogs and notes. }
function OperationNoun(const AOperation: string): string;
begin
  if AOperation = 'merging' then
    Result := rsNounMerge
  else if AOperation = 'rebasing' then
    Result := rsNounRebase
  else if AOperation = 'cherry-picking' then
    Result := rsNounCherryPick
  else if AOperation = 'reverting' then
    Result := rsNounRevert
  else
    Result := rsNounPatches;
end;

{ Whether git is in the middle of something the Commit section carries
  on with Continue rather than a commit of its own. }
function TForm1.ContinueMode: boolean;
begin
  Result := (FOperation = 'rebasing') or (FOperation = 'applying patches') or
    (FOperation = 'cherry-picking') or (FOperation = 'reverting');
end;

function TForm1.IsConflictPath(const APath: string): boolean;
var
  i: integer;
begin
  Result := False;
  if APath = '' then
    Exit;
  for i := 0 to High(FStats) do
    if FStats[i].Path = APath then
      Exit(FStats[i].Kind = ckConflict);
end;

{ How many conflicts are left in the file APath on disk, by its markers. }
function TForm1.MarkersLeft(const APath: string): integer;
var
  Lines: TStringList;
  i: integer;
begin
  Result := 0;
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(APath));
    except
      Exit;
    end;
    for i := 0 to Lines.Count - 1 do
      Lines[i] := ' ' + Lines[i];
    Result := ConflictCount(ConflictRoles(Lines), Lines);
  finally
    Lines.Free;
  end;
end;

{ AAction: 0 mine, 1 theirs, 2 resolved as it is. }
procedure TForm1.ResolvePath(const APath: string; AAction: integer);
var
  Ok: boolean;
  Remaining: integer;
  Side: string;
begin
  if (FRepo.Root = '') or not IsConflictPath(APath) then
    Exit;
  if AAction = 2 then
  begin
    Remaining := MarkersLeft(APath);
    if (Remaining > 0) and (QuestionDlg(rsMarkResolvedTitle, Format(rsMarkersLeft, [APath, Remaining]),
      mtConfirmation, [mrYes, rsMarkResolved, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'],
      0) <> mrYes) then
      Exit;
    Ok := FRepo.MarkResolved(APath);
  end
  else
  begin
    if AAction = 0 then
      Side := rsSideMine
    else
      Side := rsSideTheirs;
    if QuestionDlg(rsResolveTitle, Format(rsResolveAsk, [APath, Side]), mtConfirmation,
      [mrYes, rsResolveAction, 'IsDefault', mrCancel, rsCancelButton, 'IsCancel'], 0) <> mrYes then
      Exit;
    if AAction = 0 then
      Ok := FRepo.ResolveConflict(APath, csMine)
    else
      Ok := FRepo.ResolveConflict(APath, csTheirs);
  end;
  if Ok then
    StatusNote(Format(rsResolved, [APath]))
  else
    StatusNote(Format(rsResolveFailed, [APath, FRepo.Error]), True);
  RefreshRepository;
end;

{ The header's pills on a conflicted file, from HeaderAction. }
function TForm1.ConflictHeaderAction(AIndex: integer): boolean;
begin
  Result := (FEditPath = '') and (FView in [gvChanges, gvImage, gvBinary]) and
    IsConflictPath(FCurrentPath);
  if Result then
    ResolvePath(FCurrentPath, AIndex);
end;

procedure TForm1.MenuResolveMineClick(Sender: TObject);
begin
  ResolvePath(FContextPath, 0);
end;

procedure TForm1.MenuResolveTheirsClick(Sender: TObject);
begin
  ResolvePath(FContextPath, 1);
end;

procedure TForm1.MenuMarkResolvedClick(Sender: TObject);
begin
  ResolvePath(FContextPath, 2);
end;

procedure TForm1.ContinueOperationClick;
var
  Noun: string;
begin
  if (FRepo.Root = '') or not ContinueMode or (FCommitJob <> nil) or (FRemoteJob <> nil) then
    Exit;
  Noun := OperationNoun(FOperation);
  Screen.Cursor := crHourGlass;
  try
    if not FRepo.ContinueOperation then
    begin
      Screen.Cursor := crDefault;
      RefreshRepository;
      MessageDlg(Format(rsContinueFailed, [Noun]), FRepo.Error, mtError, [mbOK], 0);
      Exit;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  RefreshRepository;
  if FConflictFiles > 0 then
    StatusNote(rsStoppedAgain, True)
  else if FOperation <> '' then
    StatusNote(Format(rsContinuedOn, [Noun]))
  else
    StatusNote(Format(rsContinued, [Noun]));
end;

procedure TForm1.SkipOperationClick(Sender: TObject);
begin
  if (FRepo.Root = '') or not ContinueMode then
    Exit;
  if QuestionDlg(rsSkipTitle, rsSkipAsk, mtConfirmation,
    [mrYes, rsSkipButton, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes then
    Exit;
  if FRepo.SkipOperation then
    StatusNote(rsSkipped)
  else
    MessageDlg(rsSkipFailed, FRepo.Error, mtError, [mbOK], 0);
  RefreshRepository;
end;

procedure TForm1.AbortOperationClick(Sender: TObject);
var
  Noun: string;
begin
  if (FRepo.Root = '') or (FOperation = '') then
    Exit;
  Noun := OperationNoun(FOperation);
  if QuestionDlg(rsAbortTitle, Format(rsAbortAsk, [Noun]), mtConfirmation,
    [mrYes, rsAbortButton, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes then
    Exit;
  if FRepo.AbortOperation then
  begin
    { The merge message filled in is not for anything now. }
    if (FMergeMessage <> '') and (FCommitMemo.Text = FMergeMessage) then
      FCommitMemo.Clear;
    FMergeMessage := '';
    StatusNote(Format(rsAborted, [Noun]));
  end
  else
    MessageDlg(Format(rsAbortFailed, [Noun]), FRepo.Error, mtError, [mbOK], 0);
  RefreshRepository;
end;
