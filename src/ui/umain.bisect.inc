{ ---------------------------------------------------------------------------
  Bisect
  ---------------------------------------------------------------------------
  Included by umain.pp. A bisect finds the commit that brought a problem
  in by halving the commits between one known to be bad and one known
  to be good. It starts from the commit menu (umain.commitactions.inc):
  Bisect > Start Bisect: This Is Good, <branch> Is Bad, where git checks
  out the first commit to test at once, or Start Bisect: This Is Bad,
  which waits for a good one. While git is bisecting, the same submenu
  marks the commit it is shown for as Good, Bad or Skip (it cannot be
  tested), and ends the bisect; the graph shows the marks as chips. The
  Commit section has a box over the message (FBisectBox) that says where
  the bisect stands, from the snapshot's TGittanBisect (FBisect): what is
  still to mark, else the commit checked out to test with how many are
  left, else the first bad commit, or the commits it could be when only
  skipped ones stand in the way. Its Good, Bad and Skip mark the commit
  checked out, Show Commit shows the one found, and End Bisect (git
  bisect reset) puts HEAD back where it was. The commands check out
  commits, so they run on the main thread with the watcher stopped, as a
  switch does. }

procedure TForm1.SetupBisect;

  function Row(ATop: integer): TPanel;
  begin
    Result := TPanel.Create(Self);
    Result.BevelOuter := bvNone;
    Result.Caption := '';
    Result.Align := alTop;
    Result.AutoSize := True;
    Result.Top := ATop;
    Result.BorderSpacing.Top := 6;
    Result.Parent := FBisectBox;
  end;

  function Button(ARow: TPanel; const ACaption: string; AAlign: TAlign;
    ALeft: integer): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Caption := ACaption;
    Result.Align := AAlign;
    Result.AutoSize := True;
    Result.Left := ALeft;
    if AAlign = alLeft then
      Result.BorderSpacing.Right := 4;
    Result.OnClick := @BisectButtonClick;
    Result.Parent := ARow;
  end;

begin
  FBisect.Left := -1;
  FBisectBox := TPanel.Create(Self);
  FBisectBox.BevelOuter := bvNone;
  FBisectBox.Caption := '';
  FBisectBox.Align := alTop;
  FBisectBox.AutoSize := True;
  FBisectBox.Top := 0;
  FBisectBox.BorderSpacing.Bottom := 8;
  FBisectBox.Visible := False;
  FBisectBox.Parent := FCommitBox;
  FBisectNote := TGittanHintBox.Create(Self);
  FBisectNote.Align := alTop;
  FBisectNote.Parent := FBisectBox;
  { The marks on a row of their own, so the panel's width takes them. }
  FBisectRow := Row(1000);
  FBisectGood := Button(FBisectRow, rsBisectGood, alLeft, 0);
  FBisectBad := Button(FBisectRow, rsBisectBad, alLeft, 1000);
  FBisectSkip := Button(FBisectRow, rsBisectSkip, alLeft, 2000);
  FBisectEndRow := Row(2000);
  FBisectShow := Button(FBisectEndRow, rsBisectShow, alLeft, 0);
  FBisectEnd := Button(FBisectEndRow, rsBisectEnd, alRight, 1000);
end;

{ How many more marks the commits left take at most: each halves them. }
function BisectSteps(ALeft: integer): integer;
begin
  Result := 0;
  while ALeft > 0 do
  begin
    Inc(Result);
    ALeft := ALeft div 2;
  end;
end;

{ The box shows while git bisects; Good, Bad and Skip while there is
  something to mark, Show Commit once the first bad commit is found. }
procedure TForm1.UpdateBisectState;
var
  Note, Ids: string;
  Busy, Done: boolean;
  i: integer;
begin
  if FBisectBox = nil then
    Exit;
  FBisectBox.Visible := FOperation = 'bisecting';
  if not FBisectBox.Visible then
    Exit;
  Busy := (FCommitJob <> nil) or (FRemoteJob <> nil);
  Done := (FBisect.Found <> '') or (Length(FBisect.Suspects) > 0);
  if FBisect.Found <> '' then
    Note := Format(rsBisectFound, [Copy(FBisect.Found, 1, 7), FBisect.Subject])
  else if Length(FBisect.Suspects) > 0 then
  begin
    Ids := '';
    for i := 0 to High(FBisect.Suspects) do
    begin
      if Ids <> '' then
        Ids := Ids + ', ';
      Ids := Ids + Copy(FBisect.Suspects[i], 1, 7);
    end;
    Note := Format(rsBisectSuspects, [Ids]);
  end
  else if FBisect.Left > 1 then
    Note := Format(rsBisectTest, [Copy(FRepo.CommitId('HEAD'), 1, 7), FBisect.Left,
      BisectSteps(FBisect.Left)])
  else if FBisect.Left = 1 then
    Note := Format(rsBisectTestLast, [Copy(FRepo.CommitId('HEAD'), 1, 7)])
  else if (FBisect.Bad <> '') then
    Note := Format(rsBisectWaitGood, [Copy(FBisect.Bad, 1, 7)])
  else if Length(FBisect.Good) > 0 then
    Note := rsBisectWaitBad
  else
    Note := rsBisectWaitBoth;
  FBisectNote.Text := Note;
  FBisectRow.Visible := not Done;
  FBisectShow.Visible := FBisect.Found <> '';
  FBisectGood.Enabled := not Busy;
  FBisectBad.Enabled := not Busy;
  FBisectSkip.Enabled := not Busy;
  FBisectEnd.Enabled := not Busy;
end;

procedure TForm1.BisectButtonClick(Sender: TObject);
begin
  if Sender = FBisectGood then
    BisectMarkCommit('HEAD', bmGood)
  else if Sender = FBisectBad then
    BisectMarkCommit('HEAD', bmBad)
  else if Sender = FBisectSkip then
    BisectMarkCommit('HEAD', bmSkip)
  else if Sender = FBisectShow then
  begin
    if FBisect.Found <> '' then
      ShowBlameCommit(FBisect.Found);
  end
  else if Sender = FBisectEnd then
    BisectEndClick;
end;

{ Runs AStep, a bisect command, with the watcher stopped and the
  repository read again after it; false, with git's reason in a banner,
  when git refused. }
function TForm1.RunBisect(AStep: TBisectStep; const ACommit: string;
  AMark: TGittanBisectMark; const AGood: string): boolean;
begin
  Result := False;
  if (FRepo.Root = '') or (FCommitJob <> nil) or (FRemoteJob <> nil) then
    Exit;
  StopWatcher;
  try
    Screen.Cursor := crHourGlass;
    try
      case AStep of
        bsStart: Result := FRepo.BisectStart(ACommit, AGood);
        bsMark: Result := FRepo.BisectMark(ACommit, AMark);
        else
          Result := FRepo.BisectEnd;
      end;
    finally
      Screen.Cursor := crDefault;
    end;
    FLoadError := '';
    FSummary.Notice := '';
    RefreshRepository;
  finally
    StartWatcher;
  end;
  if not Result then
    BannerError(rsCaFailed, FRepo.Error);
end;

{ Says where the bisect stands after a mark or a start: the first bad
  commit, or the suspects, in a banner, else what was marked. }
procedure TForm1.BisectReport(const ADone: string);
begin
  if FBisect.Found <> '' then
    BannerSuccess(Format(rsBisectFound, [Copy(FBisect.Found, 1, 7), FBisect.Subject]))
  else if Length(FBisect.Suspects) > 0 then
    BannerInfo(rsBisectOnlySkipped, FBisectNote.Text)
  else
    StatusNote(ADone);
end;

procedure TForm1.BisectMarkCommit(const ACommit: string; AMark: TGittanBisectMark);
var
  Short, Done: string;
begin
  if FOperation <> 'bisecting' then
    Exit;
  Short := Copy(FRepo.CommitId(ACommit), 1, 7);
  if not RunBisect(bsMark, ACommit, AMark, '') then
    Exit;
  case AMark of
    bmGood: Done := Format(rsBisectMarkedGood, [Short]);
    bmBad: Done := Format(rsBisectMarkedBad, [Short]);
    else
      Done := Format(rsBisectSkipped, [Short]);
  end;
  BisectReport(Done);
end;

{ ABad and AGood as BisectStart takes them. }
function TForm1.BisectStartAt(const ABad, AGood: string): boolean;
begin
  Result := False;
  if FOperation <> '' then
    Exit;
  Result := RunBisect(bsStart, ABad, bmBad, AGood);
  if Result then
    BisectReport(rsBisectStarted);
end;

procedure TForm1.BisectEndClick;
begin
  if FOperation <> 'bisecting' then
    Exit;
  if not RunBisect(bsEnd, '', bmBad, '') then
    Exit;
  FBanner.Clear;
  if FBranch <> '' then
    StatusNote(Format(rsBisectEnded, [FBranch]))
  else
    StatusNote(rsBisectEndedDetached);
end;
