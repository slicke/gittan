{ ---------------------------------------------------------------------------
  Renaming and removing files
  ---------------------------------------------------------------------------
  Rename or Move... and Remove from Git... in the file menu (the tree,
  the summary's rows, the file header) act on a file git tracks, as
  git mv and git rm do: both are staged and go in with the next commit.
  Remove asks whether to stop tracking the file and keep it on disk
  (git rm --cached) or to delete it too; git refuses to delete a file
  with changes not committed, and its message is shown. }

function TRepoFrame.CanMoveFiles: boolean;
begin
  Result := (FRepo.Root <> '') and (FCommitJob = nil) and (FRemoteJob = nil) and
    (FContextFolder = '') and FRepo.IsTracked(FContextPath);
end;

{ AValue as a path from the top of the repository, slashes for
  backslashes and no leading ./, in ANew; '' when it may be moved to,
  else why not: it stays inside the work tree and out of the git
  directory, and nothing is there yet. }
function MoveTarget(const ARoot, AValue: string; out ANew: string): string;
var
  Part: string;
  Ok: boolean;
begin
  Result := '';
  ANew := StringReplace(Trim(AValue), '\', '/', [rfReplaceAll]);
  while Copy(ANew, 1, 2) = './' do
    Delete(ANew, 1, 2);
  if ANew = '' then
    Exit;
  Ok := (ANew[1] <> '/') and (ANew[Length(ANew)] <> '/') and (Pos(':', ANew) = 0);
  for Part in ANew.Split(['/']) do
    if (Part = '') or (Part = '.') or (Part = '..') or SameText(Part, '.git') then
      Ok := False;
  if not Ok then
    Exit(rsMoveBadPath);
  if FileExists(IncludeTrailingPathDelimiter(ARoot) + ANew) or
    DirectoryExists(IncludeTrailingPathDelimiter(ARoot) + ANew) then
    Result := Format(rsAskPathTaken, [ANew]);
end;

{ The path itself is no move: OK does nothing then, and says nothing. }
function TRepoFrame.CheckMovePath(const AValues: array of string): string;
var
  New: string;
begin
  Result := MoveTarget(FRepo.Root, AValues[0], New);
  if New = FContextPath then
    Result := '';
end;

procedure TRepoFrame.MenuMoveFileClick(Sender: TObject);
var
  Values: array of string;
  Old, New: string;
  Ok: boolean;
begin
  if not CanMoveFiles then
    Exit;
  Old := FContextPath;
  SetLength(Values, 1);
  Values[0] := Old;
  if not AskInput(rsMoveTitle, '', [Format(rsMovePrompt, [Old])], Values, @CheckMovePath,
    rsMoveAction) then
    Exit;
  { The check ran on what was typed; a file made meanwhile is git's to
    refuse. }
  if MoveTarget(FRepo.Root, Values[0], New) = rsMoveBadPath then
  begin
    StatusNote(rsMoveBadPath, True);
    Exit;
  end;
  if (New = Old) or (New = '') then
    Exit;
  StopWatcher;
  try
    Ok := FRepo.MovePath(Old, New);
    FSummary.Notice := '';
    RefreshRepository;
  finally
    StartWatcher;
  end;
  if Ok then
    StatusNote(Format(rsMoved, [Old, New]))
  else
    BannerError(Format(rsMoveFailed, [Old]), FRepo.Error);
end;

procedure TRepoFrame.MenuRemoveFileClick(Sender: TObject);
var
  Paths: TStringList;
  Path: string;
  Answer: TModalResult;
  Ok: boolean;
begin
  if not CanMoveFiles then
    Exit;
  Path := FContextPath;
  Answer := AskDlg(rsRemoveTitle, Format(rsRemoveAsk, [Path]), mtWarning,
    [mrYes, rsRemoveKeepAction, mrNo, rsRemoveDeleteAction, mrCancel, rsCancelButton,
    'IsCancel', 'IsDefault'], 0);
  if not (Answer in [mrYes, mrNo]) then
    Exit;
  StopWatcher;
  try
    Paths := TStringList.Create;
    try
      Paths.Add(Path);
      Ok := FRepo.RemovePaths(Paths, Answer = mrYes);
    finally
      Paths.Free;
    end;
    FSummary.Notice := '';
    RefreshRepository;
  finally
    StartWatcher;
  end;
  if not Ok then
    BannerError(Format(rsRemoveFailed, [Path]), FRepo.Error)
  else if Answer = mrYes then
    StatusNote(Format(rsUntracked, [Path]))
  else
    StatusNote(Format(rsRemoved, [Path]));
end;
