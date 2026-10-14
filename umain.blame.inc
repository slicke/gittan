{ ---------------------------------------------------------------------------
  Blame
  ---------------------------------------------------------------------------
  Included by umain.pp. View > Blame adds a band at the left of the
  gutter of the change view that names, at the first row of each run of
  lines last changed by the same commit, the author and the age of the
  commit; the mouse over the band shows the commit itself. A line of
  the new side (the work tree, or the right commit of a range) is blamed
  in that version, a deleted line in the base. The two blames of a file
  run in a TGittanBlameJob, and the results are kept per commit and
  path until the repository is reloaded, which may change them. The
  editor paints no band of a tag it does not know, so the texts are
  painted over the band from OnDrawEditor. }

procedure TForm1.MenuBlameClick(Sender: TObject);
begin
  FBlameOn := not FBlameOn;
  FBlameItem.Checked := FBlameOn;
  if FBlameOn then
    StartBlame
  else
    ApplyBlame;
end;

{ The cache key of one side of one file. }
function BlameKey(const ARef, APath: string): string;
begin
  Result := ARef + #0 + APath;
end;

{ Blames the shown file: from the cache when both sides are there (a
  side git could not blame is kept as nil, so it is not asked again),
  else in a new job. The band keeps its width while the job runs, so
  the text does not jump when the result comes. }
procedure TForm1.StartBlame;
var
  OldRef, NewRef: string;
  i, j: integer;
begin
  FBlameOld := nil;
  FBlameNew := nil;
  if FBlameOn and (FView = gvChanges) and (FCurrentPath <> '') then
  begin
    FRepo.DiffSides(OldRef, NewRef);
    i := FBlameCache.IndexOf(BlameKey(OldRef, FCurrentPath));
    j := FBlameCache.IndexOf(BlameKey(NewRef, FCurrentPath));
    if (i >= 0) and (j >= 0) then
    begin
      FBlameOld := TGittanBlame(FBlameCache.Objects[i]);
      FBlameNew := TGittanBlame(FBlameCache.Objects[j]);
    end
    else
    begin
      AbandonBlameJob;
      FBlameJob := TGittanBlameJob.Create(FRepo.Root, FCurrentPath, OldRef, NewRef,
        FRepo.IgnoreWhitespace);
      FBlameJob.OnDone := @BlameJobDone;
      FBlameJob.Start;
    end;
  end;
  ApplyBlame;
end;

{ A job that is no longer wanted runs on without a handler until git is
  done, and is freed with the next finished jobs: waiting for it here
  would stall the window. }
procedure TForm1.AbandonBlameJob;
begin
  if FBlameJob = nil then
    Exit;
  FBlameJob.Stop(False);
  FBlameZombies.Add(FBlameJob);
  FBlameJob := nil;
end;

procedure TForm1.FreeFinishedBlameJobs(AWait: boolean);
var
  i: integer;
begin
  for i := FBlameZombies.Count - 1 downto 0 do
    if AWait or TGittanBlameJob(FBlameZombies[i]).Finished then
    begin
      TGittanBlameJob(FBlameZombies[i]).Free;
      FBlameZombies.Delete(i);
    end;
end;

procedure TForm1.FreeBlameJobsAsync(Data: PtrInt);
begin
  FreeFinishedBlameJobs(False);
end;

procedure TForm1.CacheBlame(const ARef, APath: string; ABlame: TGittanBlame);
var
  i: integer;
begin
  i := FBlameCache.IndexOf(BlameKey(ARef, APath));
  if i < 0 then
    FBlameCache.AddObject(BlameKey(ARef, APath), ABlame)
  else
  begin
    FBlameCache.Objects[i].Free;
    FBlameCache.Objects[i] := ABlame;
  end;
end;

{ The job is done: its results go to the cache, and the shown file, if
  it is still the job's, takes them from there. The job itself may not
  have finished yet (its notification is queued from inside Execute),
  so it is freed from the message loop. }
procedure TForm1.BlameJobDone(Sender: TObject);
var
  Job: TGittanBlameJob;
begin
  Job := TGittanBlameJob(Sender);
  if Job <> FBlameJob then
    Exit;
  FBlameJob := nil;
  FBlameZombies.Add(Job);
  CacheBlame(Job.OldRef, Job.Path, Job.TakeOld);
  CacheBlame(Job.NewRef, Job.Path, Job.TakeNew);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  if (Job.Path = FCurrentPath) and (FView = gvChanges) then
    StartBlame;
end;

{ Forgets every blame: after a reload of the repository the work tree,
  and HEAD, may be something else. A running job would store its result
  after the clearing, so it is dropped too. }
procedure TForm1.ClearBlameCache;
var
  i: integer;
begin
  AbandonBlameJob;
  FBlameOld := nil;
  FBlameNew := nil;
  for i := 0 to FBlameCache.Count - 1 do
    FBlameCache.Objects[i].Free;
  FBlameCache.Clear;
end;

procedure TForm1.StopBlame;
begin
  ClearBlameCache;
  FreeFinishedBlameJobs(True);
  FreeAndNil(FBlameZombies);
  FreeAndNil(FBlameCache);
end;

{ The author of a commit as the band names it. }
function BlameAuthor(const ACommit: TGittanBlameCommit): string;
begin
  if ACommit.Uncommitted then
    Result := rsNotCommitted
  else
    Result := ACommit.Author;
end;

{ Shows or hides the band on both editors, sized to the longest author
  of the shown file's commits (up to BlameMaxAuthorCols characters) and
  the age. Without a blame yet the width is kept. }
procedure TForm1.ApplyBlame;

  procedure Measure(ABlame: TGittanBlame; var ACols: integer);
  var
    i: integer;
  begin
    if ABlame = nil then
      Exit;
    for i := 0 to High(ABlame.Commits) do
      ACols := Max(ACols, Length(UTF8Decode(BlameAuthor(ABlame.Commits[i]))));
  end;

var
  Cols: integer;
begin
  Cols := 0;
  Measure(FBlameOld, Cols);
  Measure(FBlameNew, Cols);
  if Cols > 0 then
    FBlameCols := Min(BlameMaxAuthorCols, Cols);
  FBlameNow := DateTimeToUnix(Now, False);
  SetBlameBand(Edit);
  SetBlameBand(FEditOld);
end;

{ The band's width is in pixels of the editor's font at its zoom, and
  the editor keeps it as set (its own bands are resized from their
  options at every paint). A change of width moves the text, so the
  wrap info is rebuilt. }
procedure TForm1.SetBlameBand(AEd: TATSynEdit);
var
  Band, W: integer;
  Shown: boolean;
begin
  Band := AEd.Gutter.FindIndexByTag(gutterTagBlame);
  if Band < 0 then
    Exit;
  Shown := FBlameOn and (FView = gvChanges);
  W := (FBlameCols + BlameAgeCols + 4) * EditorCharWidth(AEd);
  if (AEd.Gutter[Band].Visible <> Shown) or (AEd.Gutter[Band].Size <> W) then
  begin
    AEd.Gutter[Band].Visible := Shown;
    AEd.Gutter[Band].Size := W;
    AEd.Update(True);
  end;
  AEd.Invalidate;
end;

{ The commit of row ARow of AEd, as an index into ABlame's commits, or
  -1 with ABlame nil for a row without one: a gap, a filler, a line of
  a side git could not blame, or a row beyond the rows. The old side,
  and a deleted line in the unified view, are blamed in the base, the
  rest in the new side. }
function TForm1.BlameOfRow(AEd: TATSynEdit; ARow: integer; out ABlame: TGittanBlame): integer;
var
  Rows: TGittanRows;
  Line, FileLine: integer;
begin
  Result := -1;
  ABlame := nil;
  if AEd = FEditOld then
    Rows := FRowsOld
  else
    Rows := FRows;
  if (ARow < 0) or (ARow > High(Rows)) then
    Exit;
  Line := Rows[ARow].Line;
  if (Line < 0) or (Line > High(FOldNum)) then
    Exit;
  if (AEd = FEditOld) or (FChangeLines[Line][1] = '-') then
  begin
    ABlame := FBlameOld;
    FileLine := FOldNum[Line];
  end
  else
  begin
    ABlame := FBlameNew;
    FileLine := FNewNum[Line];
  end;
  if ABlame <> nil then
    Result := ABlame.CommitOf(FileLine);
  if Result < 0 then
    ABlame := nil;
end;

function TForm1.BlameHintText(const ACommit: TGittanBlameCommit): string;
begin
  if ACommit.Uncommitted then
    Result := rsNotCommittedYet
  else
    Result := Copy(ACommit.Hash, 1, 7) + '  ' + ACommit.Author + '  ' +
      BlameDate(ACommit.Time) + LineEnding + ACommit.Summary;
end;

{ The hint for the mouse at X, Y of AEd: the commit of the row under it
  when X is on the band, else empty. The row is found from Y alone, at
  the first column of the text. }
function TForm1.BlameHintAt(AEd: TATSynEdit; X, Y: integer): string;
var
  Band, Commit: integer;
  Details: TATEditorPosDetails;
  P: TPoint;
  Blame: TGittanBlame;
begin
  Result := '';
  Band := AEd.Gutter.FindIndexByTag(gutterTagBlame);
  if (Band < 0) or not AEd.Gutter[Band].Visible or (X < AEd.Gutter[Band].Left) or
    (X >= AEd.Gutter[Band].Right) then
    Exit;
  P := AEd.ClientPosToCaretPos(ATPoint(AEd.RectMain.Left + 1, Y), Details);
  if (P.Y < 0) or Details.BelowAllText then
    Exit;
  Commit := BlameOfRow(AEd, P.Y, Blame);
  if Commit >= 0 then
    Result := BlameHintText(Blame.Commits[Commit]);
end;

{ Paints the band: the author at the left and the age at the right of
  the first visible row of each run of rows with the same commit, in the
  gutter's text color, the uncommitted lines in italics. Only the first
  row of a wrapped line counts, and a row without a commit ends a run. }
procedure TForm1.DrawBlame(AEd: TATSynEdit; C: TCanvas);
var
  Band, W, CharW, CharH, TextH, Commit, PrevCommit, Y: integer;
  Item: TATWrapItem;
  Blame, PrevBlame: TGittanBlame;
  Author, Age: string;
  AuthorU: UnicodeString;
begin
  Band := AEd.Gutter.FindIndexByTag(gutterTagBlame);
  if (Band < 0) or not AEd.Gutter[Band].Visible or (FView <> gvChanges) then
    Exit;
  if (FBlameOld = nil) and (FBlameNew = nil) then
    Exit;
  CharW := EditorCharWidth(AEd);
  CharH := AEd.TextCharSize.Y;
  C.Font.Name := AEd.Font.Name;
  C.Font.Size := EditorFontSize(AEd);
  C.Font.Color := AEd.Colors.GutterFont;
  C.Brush.Style := bsClear;
  C.Clipping := True;
  C.ClipRect := Rect(AEd.Gutter[Band].Left, AEd.RectMain.Top, AEd.Gutter[Band].Right,
    AEd.RectMain.Bottom);
  try
    PrevCommit := -2;
    PrevBlame := nil;
    W := AEd.WrapInfo.FindIndexOfLineNumber(AEd.LineTop);
    while W < AEd.WrapInfo.Count do
    begin
      Item := AEd.WrapInfo[W];
      Inc(W);
      if not Item.bInitial then
        Continue;
      Y := AEd.CaretPosToClientPos(Point(0, Item.NLineIndex)).Y;
      if Y >= AEd.RectMain.Bottom then
        Break;
      Commit := BlameOfRow(AEd, Item.NLineIndex, Blame);
      if (Commit = PrevCommit) and (Blame = PrevBlame) then
        Continue;
      PrevCommit := Commit;
      PrevBlame := Blame;
      if Commit < 0 then
        Continue;
      AuthorU := UTF8Decode(BlameAuthor(Blame.Commits[Commit]));
      if Length(AuthorU) > FBlameCols then
        AuthorU := Copy(AuthorU, 1, FBlameCols - 1) + '…';
      Author := UTF8Encode(AuthorU);
      if Blame.Commits[Commit].Uncommitted then
      begin
        Age := '';
        C.Font.Style := [fsItalic];
      end
      else
      begin
        Age := BlameAge(Blame.Commits[Commit].Time, FBlameNow);
        C.Font.Style := [];
      end;
      TextH := C.TextHeight(Author);
      C.TextOut(AEd.Gutter[Band].Left + CharW, Y + (CharH - TextH) div 2, Author);
      if Age <> '' then
        C.TextOut(AEd.Gutter[Band].Right - CharW - C.TextWidth(Age),
          Y + (CharH - TextH) div 2, Age);
    end;
  finally
    C.Clipping := False;
    C.Font.Style := [];
  end;
end;
