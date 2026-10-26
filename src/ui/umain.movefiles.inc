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

procedure TRepoFrame.MenuMoveFileClick(Sender: TObject);
var
  Values: array of string;
  Old, New, Part: string;
  Ok: boolean;
begin
  if not CanMoveFiles then
    Exit;
  Old := FContextPath;
  SetLength(Values, 1);
  Values[0] := Old;
  if not InputQuery(rsMoveTitle, [Format(rsMovePrompt, [Old])], Values) then
    Exit;
  New := StringReplace(Trim(Values[0]), '\', '/', [rfReplaceAll]);
  while Copy(New, 1, 2) = './' do
    Delete(New, 1, 2);
  if (New = Old) or (New = '') then
    Exit;
  { The path stays inside the work tree and out of the git directory. }
  Ok := (New[1] <> '/') and (New[Length(New)] <> '/') and (Pos(':', New) = 0);
  for Part in New.Split(['/']) do
    if (Part = '') or (Part = '.') or (Part = '..') or SameText(Part, '.git') then
      Ok := False;
  if not Ok then
  begin
    StatusNote(rsMoveBadPath, True);
    Exit;
  end;
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
  Answer := QuestionDlg(rsRemoveTitle, Format(rsRemoveAsk, [Path]), mtWarning,
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
