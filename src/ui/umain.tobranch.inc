{ ---------------------------------------------------------------------------
  Moving changes to a new branch
  ---------------------------------------------------------------------------
  Branch > Move Included Files to New Branch... takes the files ticked
  in the tree, Move Changes to New Branch... in the file menu a file or
  the changed files under a folder of the tree: after a name and a
  message they are committed on a new branch made at HEAD, and HEAD
  goes back to where it was, so the files are as HEAD has them again
  and the other changes stay (TGittanRepo.MoveToBranch, run by the
  commit job, since the hooks run). A file with changes left out goes
  with the rest of them only, and the changes left out stay behind. The
  banner that says so offers the switch to the branch. Offered while
  the tree's boxes choose a commit (the work tree against HEAD), with
  no file in conflict and Amend not ticked, and not while git is in the
  middle of something or a commit or a remote job runs. }

function TRepoFrame.CanMoveToBranch: boolean;
begin
  Result := (FRepo <> nil) and RepoReady and CommitChoosing and (FConflictFiles = 0) and
    not FCommitAmend.Checked;
end;

function TRepoFrame.CheckMoveBranch(const AValues: array of string): string;
begin
  Result := BranchNameProblem(Trim(AValues[0]));
  if (Result = '') and (Trim(AValues[1]) = '') then
    Result := rsToBranchMoveNoMessage;
end;

{ The message field starts with the subject written in the Commit
  section; left as it is, the whole message there is the commit's, with
  the co-authors, and the field is cleared as after a commit. }
procedure TRepoFrame.MoveToBranchAsk(APaths: TStrings);
var
  Values: array of string;
  Parts, Rest: TGittanCommitParts;
  Options: TGittanCommitOptions;
  Note, NewName, Msg, MemoSubject, Err: string;
  UsedMemo: boolean;
begin
  if not CanMoveToBranch or (APaths.Count = 0) or not EnsureIdentity then
    Exit;
  if APaths.Count = 1 then
    Note := Format(rsToBranchMoveNoteOne, [APaths[0]])
  else
    Note := Format(rsToBranchMoveNoteMany, [APaths.Count]);
  MemoSubject := '';
  if not MessageBlank and (FCommitMemo.Lines.Count > 0) then
    MemoSubject := Trim(FCommitMemo.Lines[0]);
  SetLength(Values, 2);
  Values[0] := '';
  Values[1] := MemoSubject;
  if not AskInput(rsToBranchMoveTitle, Note, [rsToBranchMoveNamePrompt, rsToBranchMoveMessagePrompt], Values,
    @CheckMoveBranch, rsToBranchMoveAction) then
    Exit;
  NewName := Trim(Values[0]);
  { The dialog is modal, but a watcher's snapshot may have come. }
  if (NewName = '') or (CheckMoveBranch(Values) <> '') or not CanMoveToBranch then
    Exit;
  UsedMemo := (MemoSubject <> '') and (Trim(Values[1]) = MemoSubject);
  if UsedMemo then
    Msg := WithCoAuthors(FCommitMemo.Text, FCoAuthors)
  else
    Msg := Trim(Values[1]);
  if not LockedCommitAsk(APaths, False) then
    Exit;
  if not CommitParts(APaths, Parts, Err) or not CommitParts(APaths, Rest, Err, True) then
  begin
    BannerError(rsToBranchMoveFailed, Err);
    Exit;
  end;
  { An extension may stop this commit as it may any other. }
  if ExtListens('commit.before') and not ExtFire('commit.before',
    TJSONObject.Create(['message', Msg, 'paths', ListJson(APaths), 'amend', False])) then
    Exit;
  Options := [];
  if FSignOff then
    Include(Options, coSignOff);
  if FSkipHooks then
    Include(Options, coNoVerify);
  FCommitJob := TGittanCommitJob.Create(FRepo.Root, Msg, APaths, False, Parts, Options);
  FCommitJob.MoveTo(NewName, Rest);
  if UsedMemo then
    FCommitJob.Draft := FCommitMemo.Text;
  FMoveUsedMemo := UsedMemo;
  FMoveBranch := NewName;
  FCommitJob.OnDone := @CommitJobDone;
  FCommitJob.Start;
  FStatus.ShowBusy(Format(rsToBranchMoving, [NewName]));
  UpdateCommitState;
  UpdateRemoteItems;
end;

{ What CommitJobDone says of a move that was committed: back where it
  was, with the switch to the branch on offer, or still on the new
  branch, with why. }
procedure TRepoFrame.MoveToBranchDone(AJob: TGittanCommitJob);
var
  Title: string;
begin
  FStatus.ShowMessage('', stNormal, 0);
  FMoveBranch := AJob.Branch;
  if not AJob.Back then
  begin
    MarkNews;
    FBanner.DetailFont.Assign(Edit.Font);
    FBanner.Add(Format(rsToBranchMoveStayed, [AJob.Branch]), AJob.Error, bkInfo);
    Exit;
  end;
  { Moved and back, but a file's left-out changes are not in it. }
  if AJob.Error <> '' then
  begin
    BannerError(Format(rsToBranchMoveUnwritten, [AJob.Branch]), AJob.Error);
    Exit;
  end;
  if AJob.Paths.Count = 1 then
    Title := Format(rsToBranchMovedOne, [AJob.Paths[0], AJob.Branch])
  else
    Title := Format(rsToBranchMovedMany, [AJob.Paths.Count, AJob.Branch]);
  FBanner.AddAction(Title, Format(rsCommitted, [Copy(AJob.Id, 1, 7), AJob.Message]),
    bkSuccess, BannerActionSeconds, Format(rsToBranchMoveSwitch, [AJob.Branch]), @MoveSwitchClick);
end;

procedure TRepoFrame.MoveSwitchClick(Sender: TObject);
begin
  if (FMoveBranch <> '') and RepoReady and FRepo.HasCommit('refs/heads/' + FMoveBranch) then
    SwitchBranch(FMoveBranch, False);
end;

procedure TRepoFrame.MenuMoveIncludedClick(Sender: TObject);
var
  Paths: TStringList;
begin
  if not CanMoveToBranch then
    Exit;
  Paths := TStringList.Create;
  try
    ChosenCommitPaths(Paths);
    MoveToBranchAsk(Paths);
  finally
    Paths.Free;
  end;
end;

{ The file menu: the file, or the changed files under the folder. }
procedure TRepoFrame.MenuMoveChangesClick(Sender: TObject);
var
  Paths: TStringList;
begin
  Paths := TStringList.Create;
  try
    RevertTargets(Paths);
    MoveToBranchAsk(Paths);
  finally
    Paths.Free;
  end;
end;
