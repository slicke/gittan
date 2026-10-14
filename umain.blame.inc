{ ---------------------------------------------------------------------------
  Blame
  ---------------------------------------------------------------------------
  Included by umain.pp. View > Blame adds a band at the left of the
  gutter of the change view that names, at the first row of each run of
  lines last changed by the same commit, the author and the age of the
  commit; the mouse over the band shows the commit itself. In the
  history view (umain.history.inc) the band names the commit of each
  section the same way, from the history itself, without a blame. A line of
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
  would stall the window. The history jobs (umain.history.inc) are kept
  in the same list. }
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
    if AWait or TThread(FBlameZombies[i]).Finished then
    begin
      TThread(FBlameZombies[i]).Free;
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
  AbandonHistoryJob;
  FreeAndNil(FHistory);
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
  Cols, i: integer;
begin
  Cols := 0;
  if FView = gvHistory then
  begin
    if FHistory <> nil then
      for i := 0 to High(FHistory.Commits) do
        Cols := Max(Cols, Length(UTF8Decode(BlameAuthor(FHistory.Commits[i].Info))));
  end
  else
  begin
    Measure(FBlameOld, Cols);
    Measure(FBlameNew, Cols);
  end;
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
  Shown := FBlameOn and (FView in [gvChanges, gvHistory]);
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

{ The commit of row ARow of AEd for the band: in the history view the
  commit of the row's section, its header and fillers included, so a
  folded section shows its author and age too (the more row has none),
  else the blamed commit (see BlameOfRow). AKey and ASource together
  tell one commit from another: the index in ASource, the history or
  the blame. }
function TForm1.CommitOfRow(AEd: TATSynEdit; ARow: integer; out AInfo: TGittanBlameCommit;
  out AKey: integer; out ASource: TObject): boolean;
var
  Blame: TGittanBlame;
begin
  Result := False;
  AInfo := Default(TGittanBlameCommit);
  AKey := -1;
  ASource := nil;
  if FView = gvHistory then
  begin
    if (AEd <> Edit) or (FHistory = nil) or (ARow < 0) or (ARow > High(FRows)) or
      (FRows[ARow].Line = rowMore) then
      Exit;
    AKey := FRows[ARow].GapFrom;
    if (AKey < 0) or (AKey > High(FHistory.Commits)) then
      Exit;
    ASource := FHistory;
    AInfo := FHistory.Commits[AKey].Info;
    Exit(True);
  end;
  AKey := BlameOfRow(AEd, ARow, Blame);
  if AKey < 0 then
    Exit;
  ASource := Blame;
  AInfo := Blame.Commits[AKey];
  Result := True;
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
  Band, Key: integer;
  Details: TATEditorPosDetails;
  P: TPoint;
  Info: TGittanBlameCommit;
  Src: TObject;
begin
  Result := '';
  Band := AEd.Gutter.FindIndexByTag(gutterTagBlame);
  if (Band < 0) or not AEd.Gutter[Band].Visible or (X < AEd.Gutter[Band].Left) or
    (X >= AEd.Gutter[Band].Right) then
    Exit;
  P := AEd.ClientPosToCaretPos(ATPoint(AEd.RectMain.Left + 1, Y), Details);
  if (P.Y < 0) or Details.BelowAllText then
    Exit;
  if CommitOfRow(AEd, P.Y, Info, Key, Src) then
    Result := BlameHintText(Info);
end;

{ Paints the band: the author at the left and the age at the right of
  the first visible row of each run of rows with the same commit, in the
  gutter's text color, the uncommitted lines in italics. Only the first
  row of a wrapped line counts, and a row without a commit ends a run. }
procedure TForm1.DrawBlame(AEd: TATSynEdit; C: TCanvas);
var
  Band, W, CharW, CharH, TextH, Key, PrevKey, Y: integer;
  Item: TATWrapItem;
  Src, PrevSrc: TObject;
  Info: TGittanBlameCommit;
  Author, Age: string;
  AuthorU: UnicodeString;
begin
  Band := AEd.Gutter.FindIndexByTag(gutterTagBlame);
  if (Band < 0) or not AEd.Gutter[Band].Visible or not (FView in [gvChanges, gvHistory]) then
    Exit;
  if (FView = gvChanges) and (FBlameOld = nil) and (FBlameNew = nil) then
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
    PrevKey := -2;
    PrevSrc := nil;
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
      CommitOfRow(AEd, Item.NLineIndex, Info, Key, Src);
      if (Key = PrevKey) and (Src = PrevSrc) then
        Continue;
      PrevKey := Key;
      PrevSrc := Src;
      if Src = nil then
        Continue;
      AuthorU := UTF8Decode(BlameAuthor(Info));
      if Length(AuthorU) > FBlameCols then
        AuthorU := Copy(AuthorU, 1, FBlameCols - 1) + '…';
      Author := UTF8Encode(AuthorU);
      if Info.Uncommitted then
      begin
        Age := '';
        C.Font.Style := [fsItalic];
      end
      else
      begin
        Age := BlameAge(Info.Time, FBlameNow);
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

{ A click on a cell of the band shows the commit of its row: what it
  changed, in every file, as the diff from its parent; in the history
  view with the file open at the lines. }
procedure TForm1.EditClickGutter(Sender: TObject; ABand, ALine: integer;
  var AHandled: boolean);
var
  Ed: TATSynEdit;
  Key: integer;
  Info: TGittanBlameCommit;
  Src: TObject;
begin
  Ed := TATSynEdit(Sender);
  if (ABand < 0) or (Ed.Gutter[ABand].Tag <> gutterTagBlame) then
    Exit;
  AHandled := True;
  if not CommitOfRow(Ed, ALine, Info, Key, Src) or Info.Uncommitted then
    Exit;
  if FView = gvHistory then
    ShowHistoryCommit(Key)
  else
    ShowBlameCommit(Info.Hash);
end;

{ Compares the commit with its parent, which lists its files and shows
  the one the click was in, if the commit touched it under this path.
  The summary names the commit (see BaseLabel); Compare With > HEAD
  (Working Tree) goes back. }
procedure TForm1.ShowBlameCommit(const AHash: string);
var
  Range: string;
begin
  Range := FRepo.CommitRange(AHash);
  ClearHover;
  FBlameRange := Range;
  SetBase(Range);
end;

{ The hand over a cell that can be clicked, set from the message loop so
  it lands after the editor's own cursor update (see EditMouseMove). }
procedure TForm1.HandCursorAsync(Data: PtrInt);
begin
  if (FHoverBlame <> '') and (TATSynEdit(Data) = FHoverEd) then
    FHoverEd.Cursor := crHandPoint;
end;
