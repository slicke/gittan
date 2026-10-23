{ ---------------------------------------------------------------------------
  The reflog
  ---------------------------------------------------------------------------
  The Branch menu's Reflog... drops HEAD's reflog from the status bar's
  branch (ShowReflogList): every
  place HEAD has been, newest first, by what git wrote of the move
  ("commit: subject", "reset: moving to HEAD~1"), each with its
  commit's short id and age, the ones on HEAD checked. A commit that
  no branch, tag or remote reaches any more, as after a reset, an
  amend, a rebase or deleting a branch that was not merged, says "only
  in the reflog": what Gittan's questions warn of, and the way back. A
  pick shows the commit, and a right click (or the Menu key) offers to
  compare the work tree with it, make a branch there, reset the current
  branch to it and copy its id. The reflog is read when the list opens,
  not with every snapshot. }
const
  rlShow = 1;
  rlCompare = 2;
  rlBranch = 3;
  rlResetSoft = 4;
  rlResetMixed = 5;
  rlResetHard = 6;
  rlCopy = 7;
  rlBrowse = 8;

{ ASubject with each full commit id in it (git writes one for a reset
  to a commit, "reset: moving to <id>"), SHA-1 or SHA-256, cut to the
  short id. }
function ShortenReflogIds(const ASubject: string): string;
var
  i, Run: integer;
begin
  Result := '';
  Run := 0;
  for i := 1 to Length(ASubject) + 1 do
    if (i <= Length(ASubject)) and (ASubject[i] in ['0'..'9', 'a'..'f']) then
      Inc(Run)
    else
    begin
      if (Run = 40) or (Run = 64) then
        Result := Result + Copy(ASubject, i - Run, 7)
      else
        Result := Result + Copy(ASubject, i - Run, Run);
      if i <= Length(ASubject) then
        Result := Result + ASubject[i];
      Run := 0;
    end;
end;

procedure TForm1.ShowReflogList(const AScreenRect: TRect);
var
  i: integer;
  Head, Detail, Subject: string;
  Now64: int64;
begin
  if FRepo.Root = '' then
    Exit;
  if not FRepo.Reflog(FReflog) then
  begin
    BannerError(rsCaFailed, FRepo.Error);
    Exit;
  end;
  Head := FRepo.CommitId('HEAD');
  Now64 := DateTimeToUnix(Now, False);
  FReflogPopup.Clear;
  if Length(FReflog) = 0 then
    FReflogPopup.AddHeader(rsNoReflog)
  else
    FReflogPopup.AddHeader(rsReflog);
  for i := 0 to High(FReflog) do
  begin
    Subject := ShortenReflogIds(FReflog[i].Subject);
    if UTF8Length(Subject) > 60 then
      Subject := UTF8Copy(Subject, 1, 57) + '...';
    Detail := Copy(FReflog[i].Commit, 1, 7) + ' · ' + BlameAge(FReflog[i].Time, Now64);
    if FReflog[i].Lost then
      Detail := Detail + ' · ' + rsReflogLost;
    FReflogPopup.Add(Subject, Detail, FReflog[i].Commit = Head, i);
  end;
  FReflogPopup.Popup(AScreenRect);
end;

procedure TForm1.ReflogPopupPick(Sender: TObject; AIndex: integer);
var
  Row: PtrInt;
begin
  Row := FReflogPopup.TagOf(AIndex);
  if (Row >= 0) and (Row <= High(FReflog)) then
    ShowBlameCommit(FReflog[Row].Commit);
end;

procedure TForm1.ReflogContext(Sender: TObject; AIndex: integer; const AScreenPos: TPoint);
var
  Busy: boolean;
  Sub: TMenuItem;
  Row: PtrInt;

  function Add(AParent: TMenuItem; const ACaption: string; ATag: integer;
    AEnabled: boolean = True): TMenuItem;
  begin
    Result := TMenuItem.Create(FReflogMenu);
    Result.Caption := ACaption;
    Result.Tag := ATag;
    Result.Enabled := AEnabled;
    Result.OnClick := @ReflogMenuClick;
    if AParent = nil then
      FReflogMenu.Items.Add(Result)
    else
      AParent.Add(Result);
  end;

begin
  Row := FReflogPopup.TagOf(AIndex);
  if (Row < 0) or (Row > High(FReflog)) then
    Exit;
  FMenuReflog := FReflog[Row];
  Busy := RepoBusy;
  FReflogMenu.Items.Clear;
  Add(nil, rsCaShow, rlShow);
  Add(nil, rsCaCompare, rlCompare);
  Add(nil, rsCaBrowse, rlBrowse);
  FReflogMenu.Items.Add(NewLine);
  Add(nil, rsCaBranch, rlBranch, FOperation = '');
  Sub := Add(nil, Format(rsCaReset, [StringReplace(ResetTarget, '&', '&&', [rfReplaceAll])]),
    0, not Busy);
  Sub.OnClick := nil;
  Add(Sub, rsCaResetSoft, rlResetSoft);
  Add(Sub, rsCaResetMixed, rlResetMixed);
  Add(Sub, rsCaResetHard, rlResetHard);
  FReflogMenu.Items.Add(NewLine);
  Add(nil, rsCopyHash, rlCopy);
  FReflogMenu.PopUp(AScreenPos.X, AScreenPos.Y);
end;

procedure TForm1.ReflogMenuClick(Sender: TObject);
var
  E: TGittanReflogEntry;
  Short: string;
begin
  E := FMenuReflog;
  if (FRepo.Root = '') or (E.Commit = '') then
    Exit;
  Short := Copy(E.Commit, 1, 7);
  FReflogPopup.Close;
  case (Sender as TMenuItem).Tag of
    rlShow: ShowBlameCommit(E.Commit);
    rlCompare: SetBase(E.Commit);
    rlBrowse: BrowseCommit(E.Commit, Short, ShortenReflogIds(E.Subject));
    rlBranch: BranchAtAsk(Short, E.Commit);
    rlCopy: Clipboard.AsText := E.Commit;
    rlResetSoft: ResetToAsk(E.Commit, Short, rmSoft);
    rlResetMixed: ResetToAsk(E.Commit, Short, rmMixed);
    rlResetHard: ResetToAsk(E.Commit, Short, rmHard);
  end;
end;

procedure TForm1.MenuReflogClick(Sender: TObject);
begin
  if FRepo.Root <> '' then
    ShowReflogList(FStatus.PartScreenRect(spBranch));
end;
