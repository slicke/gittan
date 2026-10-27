{ ---------------------------------------------------------------------------
  Code history
  ---------------------------------------------------------------------------
  Included by umain.pp. Go > Code History (Cmd+Shift+H) shows how a piece
  of the shown file changed over its last commits: the selected lines,
  else the function (any range the lexer puts in its code tree) around
  the caret, else the whole file. The commits come from `git log -L`
  through TGittanRepo.LineHistory, HistoryStep at a time, in a
  TGittanHistoryJob; the changes not committed yet count as the newest
  of them. The view (gvHistory) is the piece as it is now with the past
  of every line under it (TGittanHistory.Layers): a line that a commit
  changed is followed by the version it replaced, in italics, then the
  version before that, and so on; a line a commit removed is kept, in
  strike-through, after the line it followed. Every version has the
  tint of the commit it comes from (HistoryColor, six hues in turn),
  the words that changed from one version to the next are shaded, and
  the blame band names the commit's author and age at every run of rows.
  A legend at the top lists the commits with their color, hash, date,
  author, summary and line counts; a click on one shows the commit
  against its parent with the file open at the lines, as a click on a
  blame cell does. A last row (rowMore) fetches HistoryStep more commits
  while git had more. The rows go into FChangeLines, FRows, FOldNum and
  FNewNum like a file's changes (GapFrom holds the commit of a row, -1
  for none), so FillChangeEditor, the navigator, Find and Go to
  Definition work as they do there; Side by Side and Hide Unchanged
  Lines do not apply. }

procedure TRepoFrame.MenuHistoryClick(Sender: TObject);
var
  Path, Title: string;
  FromRow, ToRow, FromLine, ToLine: integer;
begin
  Path := ShownRelPath;
  if (FRepo.Root = '') or not (FView in [gvChanges, gvFile]) or (Path = '') then
  begin
    StatusNote(rsHistoryNeedsFile);
    Exit;
  end;
  if ChunkRows(FromRow, ToRow, Title) then
  begin
    if not ChunkLines(FromRow, ToRow, FromLine, ToLine) then
    begin
      StatusNote(rsNoHistoryYet);
      Exit;
    end;
    if Title = '' then
      Title := Format(rsHistoryLines, [FromLine, ToLine]);
    Title := Format(rsHistoryIn, [Title, ExtractFileName(Path)]);
  end
  else
  begin
    { The whole file, as a range git clamps to its end: the layers need
      the one range that -L follows, not the hunks of git log -p. }
    FromLine := 1;
    ToLine := WholeFileLines;
    Title := Path;
  end;
  FHistoryPath := Path;
  FHistoryRef := HistoryRef;
  FHistoryFrom := FromLine;
  FHistoryTo := ToLine;
  FHistoryName := Title;
  FHistoryMax := HistoryStep;
  FHistoryTopLine := 0;
  FHistoryCaretY := 0;
  StartHistory;
end;

{ The editor rows of the piece of code to follow: the selection when it
  spans more than one row (a word selected by Go to Symbol or a double
  click is not the piece), else the innermost code tree range around the
  caret, named. False for neither, when the whole file is followed. A
  selection that ends at the start of a row does not include that row. }
function TRepoFrame.ChunkRows(out AFrom, ATo: integer; out AName: string): boolean;
var
  X1, Y1, X2, Y2: integer;
  Sel: boolean;
begin
  AName := '';
  Edit.Carets[0].GetRange(X1, Y1, X2, Y2, Sel);
  if Sel and (Y2 > Y1) then
  begin
    AFrom := Y1;
    ATo := Y2;
    if X2 = 0 then
      Dec(ATo);
    if ATo > AFrom then
      Exit(True);
  end;
  Result := EnclosingRange(FAdapter, Edit.Carets[0].PosY, AFrom, ATo, AName);
end;

{ The rows of the innermost range of AAdapter's code tree (see CodeTree)
  that holds row ARow, with the range's name. Waits for the parse. }
function TRepoFrame.EnclosingRange(AAdapter: TATAdapterEControl; ARow: integer;
  out AFrom, ATo: integer; out AName: string): boolean;
var
  Client: TecClientSyntAnalyzer;
  R: TecTextRange;
  i, Y1, Y2: integer;
begin
  Result := False;
  AFrom := 0;
  ATo := 0;
  AName := '';
  HoldRefresh;
  try
    WaitForParse(AAdapter);
  finally
    ReleaseRefresh;
  end;
  Client := AAdapter.AnClient;
  if Client = nil then
    Exit;
  Client.CriSecForData.Enter;
  try
    for i := 0 to Client.PublicData.FoldRanges.Count - 1 do
    begin
      R := TecTextRange(Client.PublicData.FoldRanges[i]);
      if not InCodeTree(Client, R) or (R.EndIdx < 0) then
        Continue;
      Y1 := Client.PublicData.Tokens._GetItemPtr(R.StartIdx)^.Range.PointStart.Y;
      Y2 := Client.PublicData.Tokens._GetItemPtr(R.EndIdx)^.Range.PointEnd.Y;
      if (ARow < Y1) or (ARow > Y2) then
        Continue;
      if Result and (Y2 - Y1 >= ATo - AFrom) then
        Continue;
      AFrom := Y1;
      ATo := Y2;
      AName := Trim(UTF8Encode(Client.GetRangeName(R, Client.PublicData.Tokens)));
      AName := StringReplace(AName, #13, ' ', [rfReplaceAll]);
      AName := StringReplace(AName, #10, ' ', [rfReplaceAll]);
      Result := True;
    end;
  finally
    Client.CriSecForData.Leave;
  end;
end;

{ The lines of the file, as HistoryRef has it, that the editor rows
  AFromRow..AToRow show: in the file view the rows themselves; in the
  change view the numbers of the rows in the right commit of a range, or
  else in the base, so the lines added in the work tree, which the base
  does not have, do not shift the range. False when no row has a number
  there: the lines are all new. }
function TRepoFrame.ChunkLines(AFromRow, AToRow: integer; out AFrom, ATo: integer): boolean;
var
  Nums: TIntegerDynArray;
  r, Line, n: integer;
begin
  AFrom := 0;
  ATo := 0;
  if FView = gvFile then
  begin
    AFrom := AFromRow + 1;
    ATo := AToRow + 1;
    Exit(True);
  end;
  if FRepo.IsRange then
    Nums := FNewNum
  else
    Nums := FOldNum;
  for r := AFromRow to Min(AToRow, High(FRows)) do
  begin
    Line := FRows[r].Line;
    if (Line < 0) or (Line > High(Nums)) then
      Continue;
    n := Nums[Line];
    if n = 0 then
      Continue;
    if (AFrom = 0) or (n < AFrom) then
      AFrom := n;
    if n > ATo then
      ATo := n;
  end;
  Result := AFrom > 0;
end;

{ The commit the lines are counted in, and the history starts from: the
  right commit of a range, else the base (HEAD by default). }
function TRepoFrame.HistoryRef: string;
var
  OldRef, NewRef: string;
begin
  FRepo.DiffSides(OldRef, NewRef);
  if FRepo.IsRange then
    Result := NewRef
  else
    Result := OldRef;
end;

{ Fetches the commits, one more than shown to know whether there are
  older ones. A job still running is given up, as in StartBlame. }
procedure TRepoFrame.StartHistory;
begin
  AbandonHistoryJob;
  FHistoryJob := TGittanHistoryJob.Create(FRepo.Root, FHistoryPath, FHistoryRef,
    FHistoryFrom, FHistoryTo, FHistoryMax + 1, FRepo.IgnoreWhitespace);
  FHistoryJob.OnDone := @HistoryJobDone;
  FHistoryJob.Start;
  FStatus.ShowBusy(rsHistoryLoading);
end;

procedure TRepoFrame.AbandonHistoryJob;
begin
  if FHistoryJob = nil then
    Exit;
  FHistoryJob.Stop(False);
  FBlameZombies.Add(FHistoryJob);
  FHistoryJob := nil;
  { Its "Loading history..." is no longer true. }
  FStatus.ClearMessage;
end;

{ The job is done: the commits, and the uncommitted changes before them,
  make the view. The job is freed from the message loop, as a blame
  job is. }
procedure TRepoFrame.HistoryJobDone(Sender: TObject);
var
  Job: TGittanHistoryJob;
begin
  Job := TGittanHistoryJob(Sender);
  if Job <> FHistoryJob then
    Exit;
  FHistoryJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  if Job.History = nil then
  begin
    if Job.Error <> '' then
      StatusNote(Job.Error, True)
    else
      StatusNote(rsNoHistory);
    Exit;
  end;
  FStatus.ClearMessage;
  FHistory.Free;
  FHistory := Job.Take;
  FHistoryMore := FHistory.Count > FHistoryMax;
  FHistory.Truncate(FHistoryMax);
  AddUncommittedHistory;
  FHistoryRows := FHistory.Layers;
  ShowHistory;
end;

{ Puts the changes of the lines not committed yet first, as a commit of
  their own, when the history is counted from HEAD and the work tree
  changed any of the lines: the file's diff against HEAD, cut to the
  lines of the range (an added line between two of them included), as
  a hunk. Read afresh, since the view may be rebuilt on a refresh. }
procedure TRepoFrame.AddUncommittedHistory;
var
  Lines: TStringList;
  OldNum, NewNum: TIntegerDynArray;
  First, Last, i: integer;
  AnyChange: boolean;
  Commit: TGittanHistoryCommit;
begin
  if (FRepo.Base <> '') or FRepo.IsRange then
    Exit;
  Lines := TStringList.Create;
  try
    if not FRepo.FileChanges(FHistoryPath, Lines) or (Lines.Count = 0) then
      Exit;
    NumberLines(Lines, OldNum, NewNum);
    First := -1;
    Last := -1;
    AnyChange := False;
    for i := 0 to Lines.Count - 1 do
      if (OldNum[i] >= FHistoryFrom) and (OldNum[i] <= FHistoryTo) then
      begin
        if First < 0 then
          First := i;
        Last := i;
      end;
    if First < 0 then
      Exit;
    for i := First to Last do
      if Lines[i][1] <> ' ' then
        AnyChange := True;
    if not AnyChange then
      Exit;
    Commit := Default(TGittanHistoryCommit);
    Commit.Info.Uncommitted := True;
    SetLength(Commit.Hunks, 1);
    Commit.Hunks[0].OldStart := 0;
    Commit.Hunks[0].NewStart := 0;
    SetLength(Commit.Hunks[0].Lines, Last - First + 1);
    for i := First to Last do
    begin
      Commit.Hunks[0].Lines[i - First] := Lines[i];
      if (Commit.Hunks[0].OldStart = 0) and (OldNum[i] > 0) then
        Commit.Hunks[0].OldStart := OldNum[i];
      if (Commit.Hunks[0].NewStart = 0) and (NewNum[i] > 0) then
        Commit.Hunks[0].NewStart := NewNum[i];
    end;
    FHistory.Prepend(Commit);
  finally
    Lines.Free;
  end;
end;

{ Shows the history in the editor, with the header naming the piece and
  counting the lines added and deleted over all the commits shown. }
procedure TRepoFrame.ShowHistory;
var
  Added, Deleted, a, d, c: integer;
begin
  FView := gvHistory;
  FManualLexer := False;
  FCurrentPath := '';
  SetOverscroll(0);
  FSummary.Notice := '';
  Added := 0;
  Deleted := 0;
  for c := 0 to High(FHistory.Commits) do
  begin
    HistoryCounts(c, a, d);
    Inc(Added, a);
    Inc(Deleted, d);
  end;
  FHeader.SetTitle(Format(rsHistoryTitle, [FHistoryName]));
  FHeader.SetCounts(Added, Deleted, False);
  { The band names the commits of the history, not a blame. }
  FBlameOld := nil;
  FBlameNew := nil;
  ApplyLayout;
  BuildHistoryView;
  UpdateChangeNav;
  ShowEditor;
  FileTree.Selected := nil;
  FSummary.Selected := '';
  { Go to Definition and the hover look the file up by this name. }
  Edit.FileName := IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(FHistoryPath);
  if Edit.Strings.Count > 0 then
  begin
    Edit.DoCaretSingle(0, VisibleRow(FHistoryCaretY));
    Edit.LineTop := Min(FHistoryTopLine, Edit.Strings.Count - 1);
  end;
  UpdateStatus;
  Edit.Update;
end;

{ Builds the rows of the history view (see the top of this file) into
  the fields of the change view and fills the editor: the legend, a
  blank row, then the layered rows, each tinted by its commit, an older
  version in italics and a removed line struck through, with the words
  that changed between a version and the one before it shaded. }
procedure TRepoFrame.BuildHistoryView;
var
  Rows: TGittanRows;
  OldNum, NewNum: TIntegerDynArray;
  Pair: TStringList;
  Spans: TGittanLineSpans;
  First, c, i, k, r: integer;
  Row: TGittanHistoryRow;

  procedure AddRow(ALine, ACommit: integer);
  begin
    SetLength(Rows, Length(Rows) + 1);
    Rows[High(Rows)].Line := ALine;
    Rows[High(Rows)].GapFrom := ACommit;
    Rows[High(Rows)].GapTo := ACommit;
    Rows[High(Rows)].Hidden := False;
  end;

  procedure Style(ARow: integer; AStyles: byte);
  var
    Part: TATLinePart;
  begin
    InitLinePart(Part);
    Part.FontStyles := AStyles;
    Edit.Attribs.Add(Point(0, ARow), Point(Max(1, Edit.Strings.LinesLen[ARow]), 0),
      TATMarkerTags.Init(tagHistoryStyle, 0), @Part);
  end;

begin
  FChangeLines.Clear;
  FExpanded := nil;
  FWordSpans := nil;
  FHistoryUser := FRepo.UserName;
  Rows := nil;
  for c := 0 to High(FHistory.Commits) do
    AddRow(rowCommit, c);
  AddRow(rowFiller, -1);
  First := Length(Rows);
  FChangeLines.Capacity := Length(FHistoryRows);
  SetLength(OldNum, Length(FHistoryRows));
  SetLength(NewNum, Length(FHistoryRows));
  for i := 0 to High(FHistoryRows) do
  begin
    k := FChangeLines.Add(' ' + FHistoryRows[i].Text);
    OldNum[k] := 0;
    NewNum[k] := FHistoryRows[i].Line;
    AddRow(k, FHistoryRows[i].Commit);
  end;
  if FHistoryMore then
    AddRow(rowMore, -1);
  FOldNum := OldNum;
  FNewNum := NewNum;
  FRows := Rows;
  FRowsOld := nil;
  FillChangeEditor(Edit, Rows, False, OldNum, NewNum,
    App.Lexers.ForFile(FHistoryPath, FRepo.Root));
  { The tints, styles and shades on top of the plain rows. }
  for c := 0 to High(FHistory.Commits) do
    MarkSwatch(Edit, c, c);
  Pair := TStringList.Create;
  try
    for i := 0 to High(FHistoryRows) do
    begin
      Row := FHistoryRows[i];
      r := First + i;
      if Row.Commit >= 0 then
        MarkRow(Edit, r, bmHistoryBase + Row.Commit);
      case Row.Kind of
        hrOld: Style(r, afsFontItalic);
        hrRemoved: Style(r, afsFontCrossed);
      end;
      { An older version follows the version that replaced it. }
      if (Row.Kind = hrOld) and (i > 0) then
      begin
        Pair.Clear;
        Pair.Add('-' + Row.Text);
        Pair.Add('+' + FHistoryRows[i - 1].Text);
        WordDiff(Pair, FIgnoreWhitespace, Spans);
        if Length(Spans) = 2 then
        begin
          MarkHistoryWords(Edit, r, Spans[0], Row.Commit);
          MarkHistoryWords(Edit, r - 1, Spans[1], FHistoryRows[i - 1].Commit);
        end;
      end;
    end;
  finally
    Pair.Free;
  end;
end;

{ Shades ASpans of row ARow in the word tone of commit ACommit. }
procedure TRepoFrame.MarkHistoryWords(AEd: TATSynEdit; ARow: integer;
  const ASpans: TGittanSpans; ACommit: integer);
var
  Part: TATLinePart;
  i: integer;
begin
  if ASpans = nil then
    Exit;
  InitLinePart(Part);
  Part.ColorBG := HistoryColor(ACommit, htWord);
  for i := 0 to High(ASpans) do
    AEd.Attribs.Add(Point(ASpans[i].Start, ARow), Point(ASpans[i].Len, 0),
      TATMarkerTags.Init(tagHistoryWord, HistoryTagEx(ACommit)), @Part);
end;

{ Colors the swatch, the first character of legend row ARow, in the
  swatch tone of commit ACommit. }
procedure TRepoFrame.MarkSwatch(AEd: TATSynEdit; ARow, ACommit: integer);
var
  Part: TATLinePart;
begin
  InitLinePart(Part);
  Part.ColorFont := HistoryColor(ACommit, htSwatch);
  AEd.Attribs.Add(Point(0, ARow), Point(1, 0),
    TATMarkerTags.Init(tagHistorySwatch, HistoryTagEx(ACommit)), @Part);
end;

{ How many lines commit AIndex added and deleted in the range. }
procedure TRepoFrame.HistoryCounts(AIndex: integer; out AAdded, ADeleted: integer);
var
  h, i: integer;
begin
  AAdded := 0;
  ADeleted := 0;
  for h := 0 to High(FHistory.Commits[AIndex].Hunks) do
    for i := 0 to High(FHistory.Commits[AIndex].Hunks[h].Lines) do
      case FHistory.Commits[AIndex].Hunks[h].Lines[i][1] of
        '+': Inc(AAdded);
        '-': Inc(ADeleted);
      end;
end;

{ AText with its accented letters composed: macOS gives git a user
  name in decomposed form (an "o" and a combining diaeresis for "ö"),
  which the editor paints as two characters, since it draws cell by
  cell. The canvas composes them on its own, so the blame band needs
  nothing of the kind. }
function ComposedText(const AText: string): string;
begin
  {$IFDEF DARWIN}
  Result := GetDarwinNormalizedFilename(AText, 2);
  {$ELSE}
  Result := AText;
  {$ENDIF}
end;

{ The initials band is shown in the history view, on the new side,
  which is the only one the view uses; its width follows the zoom, as
  the blame band's does. }
procedure TRepoFrame.SetInitialBand(AEd: TATSynEdit);
var
  Band, W: integer;
  Shown: boolean;
begin
  Band := AEd.Gutter.FindIndexByTag(gutterTagInitial);
  if Band < 0 then
    Exit;
  Shown := (FView = gvHistory) and (AEd = Edit);
  W := InitialCols * EditorCharWidth(AEd);
  if (AEd.Gutter[Band].Visible <> Shown) or (AEd.Gutter[Band].Size <> W) then
  begin
    AEd.Gutter[Band].Visible := Shown;
    AEd.Gutter[Band].Size := W;
    AEd.Update(True);
  end;
end;

{ The first letter of AName in upper case, composed (see ComposedText),
  or empty for an empty name. }
function NameInitial(const AName: string): string;
var
  Name: string;
begin
  Name := Trim(ComposedText(AName));
  if Name = '' then
    Exit('');
  Result := UTF8UpperCase(UTF8Copy(Name, 1, 1));
end;

{ Paints the initials band: on every row with a commit, its legend row
  included, the initial of the commit's author (the user's for the
  changes not committed yet) on a flat rounded badge in the tint of the
  commit's rows, the letter in its swatch tone, so the badge reads as
  part of its row. A line older than the history has no badge. Only the
  first row of a wrapped line gets one. }
procedure TRepoFrame.DrawInitials(AEd: TATSynEdit; C: TCanvas);
var
  Band, W, CharH, Y, Key, Radius, Pad: integer;
  Item: TATWrapItem;
  Info: TGittanBlameCommit;
  Src: TObject;
  Letter: string;
  Badge: TRect;
begin
  Band := AEd.Gutter.FindIndexByTag(gutterTagInitial);
  if (Band < 0) or not AEd.Gutter[Band].Visible or (FView <> gvHistory) or
    (AEd <> Edit) then
    Exit;
  CharH := AEd.TextCharSize.Y;
  Pad := Max(1, CharH div 10);
  Radius := Max(2, CharH div 3);
  C.Font.Name := AEd.Font.Name;
  C.Font.Size := EditorFontSize(AEd);
  C.Font.Style := [fsBold];
  C.Pen.Style := psClear;
  C.Clipping := True;
  C.ClipRect := Rect(AEd.Gutter[Band].Left, AEd.RectMain.Top, AEd.Gutter[Band].Right,
    AEd.RectMain.Bottom);
  try
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
      if not CommitOfRow(AEd, Item.NLineIndex, Info, Key, Src) then
        Continue;
      if Info.Uncommitted then
        Letter := NameInitial(FHistoryUser)
      else
        Letter := NameInitial(Info.Author);
      if Letter = '' then
        Continue;
      Badge := Rect(AEd.Gutter[Band].Left + Pad * 2, Y + Pad,
        AEd.Gutter[Band].Right - Pad * 2, Y + CharH - Pad);
      C.Brush.Style := bsSolid;
      C.Brush.Color := HistoryColor(Key, htRow);
      C.RoundRect(Badge, Radius, Radius);
      C.Brush.Style := bsClear;
      C.Font.Color := HistoryColor(Key, htSwatch);
      C.TextOut((Badge.Left + Badge.Right - C.TextWidth(Letter)) div 2,
        (Badge.Top + Badge.Bottom - C.TextHeight(Letter)) div 2, Letter);
    end;
  finally
    C.Clipping := False;
    C.Font.Style := [];
    C.Pen.Style := psSolid;
  end;
end;

{ The legend row of commit AIndex: the swatch (colored by MarkSwatch),
  its short hash, date, author and summary ("Not committed" for the
  uncommitted changes), and the lines it added and deleted. }
function TRepoFrame.HistoryHeaderText(AIndex: integer): string;
var
  Info: TGittanBlameCommit;
  Added, Deleted: integer;
begin
  if (FHistory = nil) or (AIndex < 0) or (AIndex > High(FHistory.Commits)) then
    Exit('');
  Info := FHistory.Commits[AIndex].Info;
  Result := '■  ';
  if Info.Uncommitted then
    Result := Result + rsNotCommitted
  else
    Result := Result + Copy(Info.Hash, 1, 7) + '  ' + BlameDate(Info.Time) + '  ' +
      ComposedText(Info.Author) + '  ' + ComposedText(Info.Summary);
  HistoryCounts(AIndex, Added, Deleted);
  Result := Result + '   ' + Format(rsHistoryCounts, [Added, Deleted]);
end;

{ A click on a legend row shows its commit; a click on the more row
  fetches HistoryStep older commits, at the same scroll position. }
procedure TRepoFrame.HistoryClick(ARow: integer);
begin
  if (FHistory = nil) or (ARow < 0) or (ARow > High(FRows)) then
    Exit;
  case FRows[ARow].Line of
    rowCommit: ShowHistoryCommit(FRows[ARow].GapFrom);
    rowMore:
      begin
        Inc(FHistoryMax, HistoryStep);
        FHistoryTopLine := Edit.LineTop;
        FHistoryCaretY := Edit.Carets[0].PosY;
        StartHistory;
      end;
  end;
end;

{ Shows commit AIndex of the history against its parent, which lists
  its files, and opens the file at the first line of the commit's hunk.
  Compare With > HEAD (Working Tree) goes back. }
procedure TRepoFrame.ShowHistoryCommit(AIndex: integer);
var
  Commit: TGittanHistoryCommit;
  Path: string;
  Target, i: integer;
begin
  if (FHistory = nil) or (AIndex < 0) or (AIndex > High(FHistory.Commits)) then
    Exit;
  Commit := FHistory.Commits[AIndex];
  if Commit.Info.Uncommitted then
    Exit;
  Path := FHistoryPath;
  Target := Commit.Hunks[0].NewStart;
  if Target = 0 then
    Target := Commit.Hunks[0].OldStart;
  ShowSummary;
  ShowBlameCommit(Commit.Info.Hash);
  ShowRepoFile(Path);
  if FView <> gvChanges then
    Exit;
  for i := 0 to High(FRows) do
    if (FRows[i].Line >= 0) and (FNewNum[FRows[i].Line] >= Target) then
    begin
      Edit.DoCaretSingle(0, VisibleRow(i));
      Edit.LineTop := Max(0, i - 3);
      Edit.Update;
      SyncOldSide;
      Break;
    end;
end;
