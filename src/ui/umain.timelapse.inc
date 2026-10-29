{ ---------------------------------------------------------------------------
  Time-lapse
  ---------------------------------------------------------------------------
  Included by umain.pp. Go > Time-lapse (Cmd+Alt+H) plays the shown
  file through every version its history has, oldest first: the
  commits come from TGittanRepo.FileTimeline (along the first parents,
  through renames) in a TGittanTimelapseJob, which builds the versions
  (TGittanTimelapse) from the file as HistoryRef has it. The view is the
  history view (gvHistory) with FTimelapse set: the rows of one version
  in FChangeLines, FRows and FNewNum, each row's GapFrom the commit its
  line came in with, so the blame band, the initials, the hint and a
  click on the band work as in Code History. A line has the faint tint
  of its commit; the lines the version shown brought in have the
  stronger one and the diff's strip, and the change navigator steps
  through them. While it plays, a step first shows the lines the next
  commit takes away struck through on the deleted color, then the next
  version, and scrolls to what changed when it is out of view.

  The bar under the editor (TGittanTimelapseBar) has the play button,
  the commit of the version shown and a track with a dot per version in
  its commit's color; a click or a drag on it shows that version. Space
  plays and pauses, Left and Right step back and forward, while the
  editor has the focus. Showing anything else ends the time-lapse. }

procedure TRepoFrame.MenuTimelapseClick(Sender: TObject);
var
  Path: string;
begin
  Path := ShownRelPath;
  if (FRepo.Root = '') or not (FView in [gvChanges, gvFile]) or (Path = '') then
  begin
    StatusNote(rsTimelapseNeedsFile);
    Exit;
  end;
  AbandonHistoryJob;
  AbandonTimelapseJob;
  FHistoryPath := Path;
  FHistoryRef := HistoryRef;
  FHistoryName := Path;
  FTimelapseJob := TGittanTimelapseJob.Create(FRepo.Root, Path, FHistoryRef);
  FTimelapseJob.OnDone := @TimelapseJobDone;
  FTimelapseJob.Start;
  FStatus.ShowBusy(rsTimelapseLoading);
end;

procedure TRepoFrame.AbandonTimelapseJob;
begin
  if FTimelapseJob = nil then
    Exit;
  FTimelapseJob.Stop(False);
  FBlameZombies.Add(FTimelapseJob);
  FTimelapseJob := nil;
  FStatus.ClearMessage;
end;

{ The versions are read: the oldest is shown, and played when there are
  more. The job is freed from the message loop, as a history job is. }
procedure TRepoFrame.TimelapseJobDone(Sender: TObject);
var
  Job: TGittanTimelapseJob;
begin
  Job := TGittanTimelapseJob(Sender);
  if Job <> FTimelapseJob then
    Exit;
  FTimelapseJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  if Job.Timelapse = nil then
  begin
    if Job.Binary then
      StatusNote(rsTimelapseBinary)
    else if Job.Error <> '' then
    begin
      { The error goes to the banner: the busy message must go too. }
      FStatus.ClearMessage;
      StatusNote(Job.Error, True);
    end
    else
      StatusNote(rsNoTimelapse);
    Exit;
  end;
  FStatus.ClearMessage;
  EndTimelapse;
  FHistory.Free;
  FHistory := Job.TakeHistory;
  FHistoryRows := nil;
  FHistoryMore := False;
  FTimelapse := Job.TakeTimelapse;
  FView := gvHistory;
  FManualLexer := False;
  FCurrentPath := '';
  SetOverscroll(0);
  FSummary.Notice := '';
  FHeader.SetTitle(Format(rsTimelapseTitle, [FHistoryName]));
  { The band names the commits of the lines, not a blame. }
  FBlameOld := nil;
  FBlameNew := nil;
  FTimelapseBar.SetCount(FTimelapse.Count);
  FTimelapseBar.Visible := True;
  ApplyLayout;
  Edit.LineTop := 0;
  ShowTimelapseVersion(FTimelapse.Count - 1, False);
  ShowEditor;
  FileTree.Selected := nil;
  FSummary.Selected := '';
  { Go to Definition and the hover look the file up by this name. }
  Edit.FileName := IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(FHistoryPath);
  UpdateStatus;
  if Edit.CanFocus then
    Edit.SetFocus;
  if FTimelapse.Count > 1 then
    SetTimelapsePlaying(True);
end;

{ Stops playing and drops the versions and the bar; a job still reading
  them is given up. }
procedure TRepoFrame.EndTimelapse;
begin
  AbandonTimelapseJob;
  FTimelapseTimer.Enabled := False;
  if FTimelapse = nil then
    Exit;
  FreeAndNil(FTimelapse);
  FTimelapseBar.Playing := False;
  FTimelapseBar.Visible := False;
end;

{ Shows the version of commit ACommit, its new lines marked, or with
  ALeaving the version before it with the lines ACommit takes away
  marked. Filling the editor may run the message loop, where a key or
  the timer would start another version over the rows being filled;
  that one is dropped, and the bar keeps showing the version that is
  shown. }
procedure TRepoFrame.ShowTimelapseVersion(ACommit: integer; ALeaving: boolean);
begin
  if (FTimelapse = nil) or FTimelapseFilling then
    Exit;
  FTimelapseFilling := True;
  try
    FillTimelapseVersion(ACommit, ALeaving);
  finally
    FTimelapseFilling := False;
  end;
end;

procedure TRepoFrame.FillTimelapseVersion(ACommit: integer; ALeaving: boolean);
var
  Ids: TGittanEntryIds;
  Rows: TGittanRows;
  OldNum, NewNum: TIntegerDynArray;
  Part: TATLinePart;
  Info: TGittanBlameCommit;
  Shown, Born, First, RowTop, InView, Added, Deleted, i: integer;
  Marker: char;
begin
  ACommit := Max(0, Min(ACommit, FTimelapse.Count - 1));
  ALeaving := ALeaving and (ACommit < FTimelapse.Count - 1);
  FTimelapseCommit := ACommit;
  FTimelapseLeaving := ALeaving;
  if ALeaving then
    Shown := ACommit + 1
  else
    Shown := ACommit;
  Ids := FTimelapse.Lines(Shown);
  FChangeLines.Clear;
  FExpanded := nil;
  FWordSpans := nil;
  FHistoryUser := '';
  SetLength(Rows, Length(Ids));
  SetLength(OldNum, Length(Ids));
  SetLength(NewNum, Length(Ids));
  for i := 0 to High(Ids) do
  begin
    Born := FTimelapse.Born(Ids[i]);
    if ALeaving and (FTimelapse.Died(Ids[i]) = ACommit) then
      Marker := '-'
    else if not ALeaving and (Born = ACommit) then
      Marker := '+'
    else
      Marker := ' ';
    FChangeLines.Add(Marker + FTimelapse.Text(Ids[i]));
    OldNum[i] := 0;
    NewNum[i] := i + 1;
    Rows[i].Line := i;
    Rows[i].GapFrom := Born;
    Rows[i].GapTo := Born;
    Rows[i].Hidden := False;
  end;
  FOldNum := OldNum;
  FNewNum := NewNum;
  FRows := Rows;
  FRowsOld := nil;
  RowTop := Edit.LineTop;
  FillChangeEditor(Edit, Rows, False, OldNum, NewNum,
    App.Lexers.ForFile(FHistoryPath, FRepo.Root));
  { The message loop may have ended the time-lapse meanwhile. }
  if (FTimelapse = nil) or (FView <> gvHistory) or (FChangeLines.Count <> Length(Ids)) then
    Exit;
  { The tints on top: the commit's faint one, its stronger one for a
    new line, and a line on its way out struck through. }
  First := -1;
  InitLinePart(Part);
  Part.FontStyles := afsFontCrossed;
  for i := 0 to High(Ids) do
  begin
    Born := Rows[i].GapFrom mod Length(HistoryLight);
    case FChangeLines[i][1] of
      ' ': MarkRow(Edit, i, bmHistoryBase + Born);
      '+': MarkRow(Edit, i, bmHistoryNew + Born);
      '-': Edit.Attribs.Add(Point(0, i), Point(Max(1, Edit.Strings.LinesLen[i]), 0),
          TATMarkerTags.Init(tagHistoryStyle, 0), @Part);
    end;
    if (First < 0) and (FChangeLines[i][1] <> ' ') then
      First := i;
  end;
  { What changed stays in view: when it is out of it, it comes to a
    quarter down. }
  if Edit.Strings.Count > 0 then
  begin
    InView := Max(1, Edit.GetVisibleLines);
    if (First >= 0) and ((First < RowTop) or (First >= RowTop + InView - 1)) then
      RowTop := Max(0, First - InView div 4);
    if First >= 0 then
      Edit.DoCaretSingle(0, First)
    else
      Edit.DoCaretSingle(0, Min(RowTop, Edit.Strings.Count - 1));
    Edit.LineTop := Min(RowTop, Edit.Strings.Count - 1);
  end;
  HistoryCounts(ACommit, Added, Deleted);
  FHeader.SetCounts(Added, Deleted, False);
  Info := FHistory.Commits[ACommit].Info;
  FTimelapseBar.Position := FTimelapse.Count - 1 - ACommit;
  FTimelapseBar.SetInfo(Copy(Info.Hash, 1, 7) + '   ' + BlameDate(Info.Time) + '   ' +
    ComposedText(Info.Author) + '   ' + ComposedText(Info.Summary),
    Format(rsTimelapseCounter, [FTimelapse.Count - ACommit, FTimelapse.Count]));
  UpdateChangeNav;
  Edit.Update;
end;

{ Whether commit ACommit takes away lines of the version before it. }
function TRepoFrame.TimelapseTakesAway(ACommit: integer): boolean;
var
  Ids: TGittanEntryIds;
  i: integer;
begin
  Result := False;
  Ids := FTimelapse.Lines(ACommit + 1);
  for i := 0 to High(Ids) do
    if FTimelapse.Died(Ids[i]) = ACommit then
      Exit(True);
end;

{ The milliseconds a version is shown while playing: a long history goes
  faster, so the whole plays in about 40 seconds or less. }
function TRepoFrame.TimelapseStepTime: integer;
begin
  Result := Max(250, Min(1500, 40000 div Max(1, FTimelapse.Count)));
end;

{ Plays or pauses; a pause during a step shows the version the step was
  going to. }
procedure TRepoFrame.SetTimelapsePlaying(APlaying: boolean);
begin
  FTimelapseTimer.Enabled := False;
  APlaying := APlaying and (FTimelapse <> nil);
  FTimelapseBar.Playing := APlaying;
  if not APlaying then
  begin
    if (FTimelapse <> nil) and FTimelapseLeaving then
      ShowTimelapseVersion(FTimelapseCommit, False);
    Exit;
  end;
  FTimelapseTimer.Interval := TimelapseStepTime;
  FTimelapseTimer.Enabled := True;
end;

{ The next stage: the version a leaving step was going to, else the
  next newer version, through the lines it takes away when it does. At
  the newest version the play ends. }
procedure TRepoFrame.TimelapseTimerTimer(Sender: TObject);
var
  Step: integer;
begin
  FTimelapseTimer.Enabled := False;
  if FTimelapse = nil then
    Exit;
  Step := TimelapseStepTime;
  if FTimelapseLeaving then
  begin
    ShowTimelapseVersion(FTimelapseCommit, False);
    FTimelapseTimer.Interval := Step * 3 div 5;
  end
  else if FTimelapseCommit <= 0 then
  begin
    SetTimelapsePlaying(False);
    Exit;
  end
  else if TimelapseTakesAway(FTimelapseCommit - 1) then
  begin
    ShowTimelapseVersion(FTimelapseCommit - 1, True);
    FTimelapseTimer.Interval := Step * 2 div 5;
  end
  else
  begin
    ShowTimelapseVersion(FTimelapseCommit - 1, False);
    FTimelapseTimer.Interval := Step;
  end;
  FTimelapseTimer.Enabled := True;
end;

{ The play button: plays from the oldest version again once it has
  reached the newest. }
procedure TRepoFrame.TimelapsePlay(Sender: TObject);
begin
  if FTimelapse = nil then
    Exit;
  if FTimelapseBar.Playing then
  begin
    SetTimelapsePlaying(False);
    Exit;
  end;
  if (FTimelapseCommit = 0) and (FTimelapse.Count > 1) then
    ShowTimelapseVersion(FTimelapse.Count - 1, False);
  SetTimelapsePlaying(True);
end;

{ A click or a drag on the track; playing goes on from there. }
procedure TRepoFrame.TimelapseSeek(Sender: TObject);
begin
  if FTimelapse = nil then
    Exit;
  ShowTimelapseVersion(FTimelapse.Count - 1 - FTimelapseBar.Position, False);
  SetTimelapsePlaying(FTimelapseBar.Playing);
end;

{ ADelta versions forward in time (newer), or back for a negative one;
  pauses. }
procedure TRepoFrame.TimelapseStep(ADelta: integer);
begin
  if FTimelapse = nil then
    Exit;
  FTimelapseBar.Playing := False;
  FTimelapseTimer.Enabled := False;
  ShowTimelapseVersion(FTimelapseCommit - ADelta, False);
end;

{ The dot of version AIndex of the bar, oldest first: its commit's
  swatch. }
function TRepoFrame.TimelapseDotColor(AIndex: integer): TColor;
begin
  if FTimelapse = nil then
    Exit(clNone);
  Result := HistoryColor(FTimelapse.Count - 1 - AIndex, htSwatch);
end;

{ Space, Left and Right while the time-lapse is shown and the editor or
  the bar has the focus, which the editor gets when it starts. }
function TRepoFrame.TimelapseKey(Key: word; Shift: TShiftState): boolean;
begin
  Result := False;
  if (FTimelapse = nil) or (FView <> gvHistory) or
    (Shift * [ssShift, ssCtrl, ssAlt, ssMeta] <> []) or
    ((FWindow.ActiveControl <> Edit) and (FWindow.ActiveControl <> FTimelapseBar)) then
    Exit;
  case Key of
    VK_SPACE: TimelapsePlay(nil);
    VK_LEFT: TimelapseStep(-1);
    VK_RIGHT: TimelapseStep(1);
    else
      Exit;
  end;
  Result := True;
end;
