{ ---------------------------------------------------------------------------
  The change view
  ---------------------------------------------------------------------------
  Included by umain.pp. FChangeLines holds the diff of the shown file with
  the whole file as context, one line per entry with its ' ', '+' or '-'
  marker. BuildChangeView turns it into the rows of the editor: every
  line, or with View > Hide Unchanged Lines the changed ones with a few
  lines around them and one gap row before each run of hidden lines (a
  click on it opens the run). The hidden lines stay in the text, marked
  hidden (LinesHidden, the editor's folding mechanism, with folding
  itself turned off), so the lexer parses the whole file and a comment
  or string that starts in a hidden line still ends where it should.
  With View > Side by Side the rows are split over two editors: the old
  side with the deleted lines, the new side with the added ones, and a
  filler row opposite each line the other side has, so the two scroll in
  step.

  The lexer's code tree gives the view its symbols: a gap row names the
  symbol the block of changes after it is in, as git's hunk headers do,
  and the file header names the symbol the caret is in. The tree is
  known only when the background parse of the text ends, so the headings
  are found then (UpdateSymbolHeadings, from AdapterParseDone) and the
  view is built once more with them in its gap rows. }

{ The index is the diff line, the value its number in the old file (0
  for an added line) or the new file (0 for a deleted line). }
procedure NumberLines(ALines: TStrings; out AOld, ANew: TIntegerDynArray);
var
  i, o, n: integer;
begin
  SetLength(AOld, ALines.Count);
  SetLength(ANew, ALines.Count);
  o := 0;
  n := 0;
  for i := 0 to ALines.Count - 1 do
  begin
    AOld[i] := 0;
    ANew[i] := 0;
    if ALines[i][1] <> '+' then
    begin
      Inc(o);
      AOld[i] := o;
    end;
    if ALines[i][1] <> '-' then
    begin
      Inc(n);
      ANew[i] := n;
    end;
  end;
end;

procedure TForm1.BuildChangeView;
var
  n, i, j, k, r, d0, a0, Dels, Adds: integer;
  Keep: array of boolean;
  OldNum, NewNum: TIntegerDynArray;
  Rows, LeftRows, RightRows: TGittanRows;
  Lexer: TecSyntAnalyzer;

  procedure AddRow(var ARows: TGittanRows; ALine, AFrom, ATo: integer;
    AHidden: boolean = False);
  begin
    SetLength(ARows, Length(ARows) + 1);
    ARows[High(ARows)].Line := ALine;
    ARows[High(ARows)].GapFrom := AFrom;
    ARows[High(ARows)].GapTo := ATo;
    ARows[High(ARows)].Hidden := AHidden;
  end;

  function Marker(const ARow: TGittanRow): char;
  begin
    if ARow.Line < 0 then
      Result := ' '
    else
      Result := FChangeLines[ARow.Line][1];
  end;

begin
  n := FChangeLines.Count;
  NumberLines(FChangeLines, OldNum, NewNum);
  FOldNum := OldNum;
  FNewNum := NewNum;
  PlaceThreads;
  WordDiff(FChangeLines, FIgnoreWhitespace, FWordSpans);
  { The blocks of changed lines, which the headings are kept by. The
    code tree of the text goes with the text, which is replaced here. }
  FBlockStarts := nil;
  for i := 0 to n - 1 do
    if (FChangeLines[i][1] <> ' ') and ((i = 0) or (FChangeLines[i - 1][1] = ' ')) then
    begin
      SetLength(FBlockStarts, Length(FBlockStarts) + 1);
      FBlockStarts[High(FBlockStarts)] := i;
    end;
  FRangesValid := False;
  { Which diff lines are shown: all, or the changed ones with their
    context and the gaps the user opened. }
  SetLength(Keep, n);
  if not FOnlyChanges then
    for i := 0 to n - 1 do
      Keep[i] := True
  else
  begin
    for i := 0 to n - 1 do
      Keep[i] := False;
    for i := 0 to n - 1 do
      if FChangeLines[i][1] <> ' ' then
        for j := Max(0, i - FContextLines) to Min(n - 1, i + FContextLines) do
          Keep[j] := True;
    k := 0;
    while k + 1 <= High(FExpanded) do
    begin
      for j := Max(0, FExpanded[k]) to Min(n - 1, FExpanded[k + 1]) do
        Keep[j] := True;
      Inc(k, 2);
    end;
    { A line with review comments stays, so its card shows. }
    for k := 0 to High(FThreadRows) do
      if (FThreadRows[k] >= 0) and (FThreadRows[k] < n) then
        Keep[FThreadRows[k]] := True;
  end;
  { The rows of the unified view: a shown line, or a gap row followed by
    the run of hidden lines it stands for. }
  Rows := nil;
  i := 0;
  while i < n do
  begin
    if Keep[i] then
      AddRow(Rows, i, 0, 0)
    else
    begin
      j := i;
      while (j + 1 < n) and not Keep[j + 1] do
        Inc(j);
      AddRow(Rows, rowGap, i, j);
      for k := i to j do
        AddRow(Rows, k, 0, 0, True);
      i := j;
    end;
    Inc(i);
  end;
  Lexer := FLexers.ForFile(FCurrentPath, FRepo.Root);
  FBuildingView := True;
  try
    if not FSideBySide then
    begin
      FRows := Rows;
      FRowsOld := nil;
      FindBlockRows;
      FillChangeEditor(Edit, Rows, False, OldNum, NewNum, Lexer);
      Exit;
    end;
  { Side by side: a context or gap row goes to both sides; a run of
    deleted lines and the run of added lines after it go to the old and
    the new side, the shorter padded with fillers. }
  LeftRows := nil;
  RightRows := nil;
  r := 0;
  while r < Length(Rows) do
  begin
    if Marker(Rows[r]) = ' ' then
    begin
      AddRow(LeftRows, Rows[r].Line, Rows[r].GapFrom, Rows[r].GapTo, Rows[r].Hidden);
      AddRow(RightRows, Rows[r].Line, Rows[r].GapFrom, Rows[r].GapTo, Rows[r].Hidden);
      Inc(r);
      Continue;
    end;
    d0 := r;
    while (r < Length(Rows)) and (Marker(Rows[r]) = '-') do
      Inc(r);
    Dels := r - d0;
    a0 := r;
    while (r < Length(Rows)) and (Marker(Rows[r]) = '+') do
      Inc(r);
    Adds := r - a0;
    for k := 0 to Max(Dels, Adds) - 1 do
    begin
      if k < Dels then
        AddRow(LeftRows, Rows[d0 + k].Line, 0, 0)
      else
        AddRow(LeftRows, rowFiller, 0, 0);
      if k < Adds then
        AddRow(RightRows, Rows[a0 + k].Line, 0, 0)
      else
        AddRow(RightRows, rowFiller, 0, 0);
    end;
  end;
    FRows := RightRows;
    FRowsOld := LeftRows;
    FindBlockRows;
    FillChangeEditor(FEditOld, LeftRows, True, OldNum, NewNum, Lexer);
    FillChangeEditor(Edit, RightRows, False, OldNum, NewNum, Lexer);
    FEditOld.LineTop := 0;
  finally
    FBuildingView := False;
    ApplyReviewGaps;
    { In case a parse ended during the build. }
    UpdateSymbolHeadings;
  end;
end;

{ Puts ARows into AEd: the text, the hidden lines, the line colors and
  states, and the line numbers (from the old file on the old side, else
  from the new). A deleted line in the unified view has no number; a
  gap, filler, commit header, more or hidden row has neither number nor
  state. The history view (umain.history.inc) builds its rows into the
  same fields and fills the editor through here too. }
procedure TForm1.FillChangeEditor(AEd: TATSynEdit; const ARows: TGittanRows;
  AOldSide: boolean; const AOldNum, ANewNum: TIntegerDynArray;
  ALexer: TecSyntAnalyzer);
var
  Lines: TStringList;
  Numbers, Kinds: TIntegerDynArray;
  i, Down, Up, All, Heading, Role: integer;
  Marker: char;
  Hidden: boolean;
begin
  Lines := TStringList.Create;
  try
    for i := 0 to High(ARows) do
      case ARows[i].Line of
        rowGap:
          Lines.Add(GapRowText(ARows[i].GapTo - ARows[i].GapFrom + 1,
            GapHeading(ARows[i].GapTo), Down, Up, All, Heading));
        rowFiller: Lines.Add('');
        rowCommit: Lines.Add(HistoryHeaderText(ARows[i].GapFrom));
        rowMore: Lines.Add(Format(rsHistoryMore, [HistoryStep]));
        else
          Lines.Add(Copy(FChangeLines[ARows[i].Line], 2, MaxInt));
      end;
    ShowText(AEd, Lines.Text, ALexer);
  finally
    Lines.Free;
  end;
  SetLength(Numbers, Length(ARows));
  SetLength(Kinds, Length(ARows));
  Hidden := False;
  for i := 0 to High(ARows) do
  begin
    Numbers[i] := 0;
    Kinds[i] := 0;
    if ARows[i].Hidden then
    begin
      AEd.Strings.LinesHidden[i, AEd.EditorIndex] := True;
      Hidden := True;
      Continue;
    end;
    case ARows[i].Line of
      rowGap: MarkRow(AEd, i, bmGap);
      rowFiller: MarkRow(AEd, i, bmFiller);
      rowCommit:
        begin
          MarkRow(AEd, i, bmCommit);
          MarkHeader(AEd, i);
        end;
      rowMore: MarkRow(AEd, i, bmGap);
      else
      begin
        Marker := FChangeLines[ARows[i].Line][1];
        Role := crNone;
        if not AOldSide and (FView = gvChanges) and (ARows[i].Line <= High(FConflictRoles)) then
          Role := FConflictRoles[ARows[i].Line];
        if Role = crNone then
          MarkLine(AEd, i, Marker)
        else
        begin
          { A line of a conflict takes the tint of its role instead of
            the diff's; the strip still shows what is new. }
          if Marker = '+' then
            AEd.Strings.LinesState[i] := TATLineState.Added;
          MarkRow(AEd, i, bmConflictMarker + Role - crMarker);
          if Role = crMarker then
            MarkHeader(AEd, i);
        end;
        if (Role = crNone) and (ARows[i].Line <= High(FWordSpans)) then
          MarkWords(AEd, i, FWordSpans[ARows[i].Line], Marker, 0);
        if AOldSide then
        begin
          Numbers[i] := AOldNum[ARows[i].Line];
          if Marker = '-' then
            Kinds[i] := bmDeleted;
        end
        else
        begin
          Numbers[i] := ANewNum[ARows[i].Line];
          if Marker = '+' then
            Kinds[i] := bmAdded;
        end;
      end;
    end;
  end;
  SetRowNumbers(AEd, Numbers, Kinds);
  if Hidden then
  begin
    { The wrap info skips hidden lines only while the editor has a fold
      range at all; the lexer adds its ranges later, from a background
      parse, and plain text never gets any. A range over the whole text,
      tagged persistent so the adapter carries it across its parses,
      makes the hidden rows count from the first build. The range is
      never folded, and the fold band that would draw it is hidden. }
    AEd.Fold.Add(1, 0, 1, AEd.Strings.Count - 1, False, '', cTagPersistentFoldRange);
    { The wrap info maps the rows on screen; it must be rebuilt from
      the hidden-lines map. }
    AEd.Strings.WrapStructInvalidate;
    AEd.Update(True);
  end;
end;

{ The row at ARow, or the first shown row after it: a caret on a hidden
  row would make the editor unfold the lexer range around it, and show
  the hidden lines. }
function TForm1.VisibleRow(ARow: integer): integer;
var
  Last: integer;
begin
  Last := Edit.Strings.Count - 1;
  Result := Max(0, Min(ARow, Last));
  while (Result < Last) and Edit.IsLineFolded(Result) do
    Inc(Result);
end;

{ The text of a gap row standing for ACount hidden lines: how many, and
  for a run longer than GapStep the three ways to open it, each a few
  lines on: ADown opens the first GapStep lines (the text above goes on
  down), AUp the last ones (the text below goes on up), AAll the whole
  run. The three are the columns the labels start at, in UTF-16 units
  as the editor counts them, or -1 for a short run, where a click
  anywhere opens it. AHeading, the symbol the changes after the gap are
  in, ends the row, from column AHeadingCol (-1 without one); a click on
  it does nothing. }
function TForm1.GapRowText(ACount: integer; const AHeading: string;
  out ADown, AUp, AAll, AHeadingCol: integer): string;
const
  Sep = '   ';
  HeadingSep = '      ';
begin
  if ACount = 1 then
    Result := rsGapLine
  else
    Result := Format(rsGapLines, [ACount]);
  ADown := -1;
  AUp := -1;
  AAll := -1;
  AHeadingCol := -1;
  if ACount > GapStep then
  begin
    Result := Result + Sep;
    ADown := Length(UTF8Decode(Result));
    Result := Result + Format(rsGapDown, [GapStep]) + Sep;
    AUp := Length(UTF8Decode(Result));
    Result := Result + Format(rsGapUp, [GapStep]) + Sep;
    AAll := Length(UTF8Decode(Result));
    Result := Result + rsGapAll;
  end;
  if AHeading = '' then
    Exit;
  Result := Result + HeadingSep;
  AHeadingCol := Length(UTF8Decode(Result));
  Result := Result + AHeading;
end;

{ The heading of the gap row that hides the diff lines up to AGapTo: the
  name of the symbol around the first block of changes after the gap,
  as far as UpdateSymbolHeadings has found the names; '' for no block
  (the gap runs to the end) or no symbol. }
function TForm1.GapHeading(AGapTo: integer): string;
var
  b: integer;
begin
  Result := '';
  for b := 0 to High(FBlockStarts) do
    if FBlockStarts[b] > AGapTo then
    begin
      if b <= High(FHeadings) then
        Result := FHeadings[b];
      Exit;
    end;
end;

{ One marker per row of ARows: the diff line's own, ' ' for a gap or
  another row that stands for no line, and for a filler row of the
  side-by-side view the marker of the line it stands opposite ('-' on
  the new side, '+' on the old), so a symbol on one side counts the
  lines the other side has. }
function TForm1.RowMarkers(const ARows: TGittanRows; AOldSide: boolean): string;
var
  i: integer;
begin
  SetLength(Result, Length(ARows));
  for i := 0 to High(ARows) do
    if ARows[i].Line >= 0 then
      Result[i + 1] := FChangeLines[ARows[i].Line][1]
    else if ARows[i].Line = rowFiller then
    begin
      if AOldSide then
        Result[i + 1] := '+'
      else
        Result[i + 1] := '-';
    end
    else
      Result[i + 1] := ' ';
end;

{ The rows of AEd as UTF-8, for the move and rename detection. }
function TForm1.RowTexts(AEd: TATSynEdit): TStringList;
var
  i: integer;
begin
  Result := TStringList.Create;
  Result.Capacity := AEd.Strings.Count;
  for i := 0 to AEd.Strings.Count - 1 do
    Result.Add(UTF8Encode(AEd.Strings.Lines[i]));
end;

{ The parse of the change view's text ended: keeps the code tree of each
  side and names the block of changes after every gap by the innermost
  range around the block's first line, on the new side, or on the old
  side for a block of deleted lines the new side shows as fillers. New
  names rebuild the view, at the same place, so the gap rows show them;
  the parse of that text finds the same names and ends it. A lexer that
  reads a heading as code could name the blocks differently each time,
  so a file is rebuilt for its headings only twice. }
procedure TForm1.UpdateSymbolHeadings;
var
  RowOf, RowOfOld: TIntegerDynArray;
  Names: array of string;
  b, i, r, Line: integer;
  Differ: boolean;
begin
  { A parse may end while the view is being built, with one side's text
    replaced and the other's not yet; the build calls here when it is
    done. The text ends with an empty line after the last row. }
  if FBuildingView or (FView <> gvChanges) or (FAdapter.Tag = 0) or
    (Edit.Strings.Count <> Length(FRows) + 1) then
    Exit;
  if FEditOld.Visible and ((FAdapterOld.Tag = 0) or
    (FEditOld.Strings.Count <> Length(FRowsOld) + 1)) then
    Exit;
  FCodeRanges := CodeRanges(FAdapter, Edit);
  if FEditOld.Visible then
    FOldRanges := CodeRanges(FAdapterOld, FEditOld)
  else
    FOldRanges := nil;
  FRangesValid := True;
  UpdateSymbolCrumb;
  SetLength(RowOf, FChangeLines.Count);
  SetLength(RowOfOld, FChangeLines.Count);
  for i := 0 to High(RowOf) do
  begin
    RowOf[i] := -1;
    RowOfOld[i] := -1;
  end;
  for r := 0 to High(FRows) do
    if FRows[r].Line >= 0 then
      RowOf[FRows[r].Line] := r;
  for r := 0 to High(FRowsOld) do
    if FRowsOld[r].Line >= 0 then
      RowOfOld[FRowsOld[r].Line] := r;
  SetLength(Names, Length(FBlockStarts));
  for b := 0 to High(FBlockStarts) do
  begin
    Names[b] := '';
    Line := FBlockStarts[b];
    r := RowOf[Line];
    if r >= 0 then
      i := InnermostRange(FCodeRanges, r)
    else
      i := -1;
    if i >= 0 then
      Names[b] := FCodeRanges[i].Symbol.Name
    else if RowOfOld[Line] >= 0 then
    begin
      i := InnermostRange(FOldRanges, RowOfOld[Line]);
      if i >= 0 then
        Names[b] := FOldRanges[i].Symbol.Name;
    end;
  end;
  Differ := Length(Names) <> Length(FHeadings);
  for b := 0 to High(Names) do
    if not Differ and (Names[b] <> FHeadings[b]) then
      Differ := True;
  if not Differ then
    Exit;
  FHeadings := Names;
  if FOnlyChanges and (FHeadingRebuilds < 2) then
  begin
    Inc(FHeadingRebuilds);
    { The adapter is still in its parse-done handler; the text is
      replaced from the message loop. }
    Application.QueueAsyncCall(@RebuildForHeadingsAsync, 0);
  end;
end;

procedure TForm1.RebuildForHeadingsAsync(Data: PtrInt);
begin
  if FView = gvChanges then
    RebuildIfChanges;
end;

{ The file header names the symbol the caret is in, from the code tree
  of the last parse while the text is the one it parsed. }
procedure TForm1.UpdateSymbolCrumb;
var
  i: integer;
begin
  i := -1;
  if (FView = gvChanges) and FRangesValid and (Edit.Carets.Count > 0) then
    i := InnermostRange(FCodeRanges, Edit.Carets[0].PosY);
  if i >= 0 then
    FHeader.SetSymbol(FCodeRanges[i].Symbol.Name)
  else
    FHeader.SetSymbol('');
end;

{ Opens the hidden lines AFrom..ATo of the diff: the view is rebuilt with
  them kept, at the same scroll position. }
procedure TForm1.ExpandGap(AFrom, ATo: integer);
var
  TopLine, CaretY: integer;
begin
  SetLength(FExpanded, Length(FExpanded) + 2);
  FExpanded[High(FExpanded) - 1] := AFrom;
  FExpanded[High(FExpanded)] := ATo;
  TopLine := Edit.LineTop;
  CaretY := Edit.Carets[0].PosY;
  BuildChangeView;
  Edit.DoCaretSingle(0, VisibleRow(CaretY));
  Edit.LineTop := TopLine;
  Edit.Update;
  SyncOldSide;
  UpdateChangeNav;
end;

{ A click on a gap row opens it: on one of its labels (see GapRowText)
  the first or the last GapStep lines, elsewhere the whole run; in the
  history view a click on a commit header or the more row acts (see
  HistoryClick). Cmd+click (Ctrl+click elsewhere) goes to the definition
  of the clicked word. The editor put the caret on the clicked position
  on mouse down. }
procedure TForm1.EditMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
var
  Row, Col, From, To_, Down, Up, All, Heading: integer;
begin
  if Button <> mbLeft then
    Exit;
  { A click on a review comment's card (see EditClickGap). }
  if FGapToggle <> '' then
  begin
    ToggleThreadNow;
    Exit;
  end;
  if ssModifier in Shift then
  begin
    if TATSynEdit(Sender).Carets[0].EndY < 0 then
      GoToDefinition(TATSynEdit(Sender));
    Exit;
  end;
  if FView = gvHistory then
  begin
    HistoryClick(TATSynEdit(Sender).Carets[0].PosY);
    Exit;
  end;
  if FView <> gvChanges then
    Exit;
  Row := TATSynEdit(Sender).Carets[0].PosY;
  if (Row < 0) or (Row > High(FRows)) or (FRows[Row].Line <> rowGap) then
    Exit;
  From := FRows[Row].GapFrom;
  To_ := FRows[Row].GapTo;
  Col := TATSynEdit(Sender).Carets[0].PosX;
  GapRowText(To_ - From + 1, GapHeading(To_), Down, Up, All, Heading);
  if (Heading >= 0) and (Col >= Heading) then
    Exit;
  if (All >= 0) and (Col < All) then
  begin
    if Col >= Up then
      From := To_ - GapStep + 1
    else if Col >= Down then
      To_ := From + GapStep - 1;
  end;
  ExpandGap(From, To_);
end;


{ The two sides scroll together. The event fires after a paint, so the
  other side is moved only when it differs; its own event then finds
  nothing to do. }
procedure TForm1.EditorScroll(Sender: TObject);
var
  Src, Dst: TATSynEdit;
begin
  if FSyncingScroll or not FEditOld.Visible then
    Exit;
  Src := TATSynEdit(Sender);
  if Src = Edit then
    Dst := FEditOld
  else
    Dst := Edit;
  FSyncingScroll := True;
  try
    if Dst.LineTop <> Src.LineTop then
      Dst.LineTop := Src.LineTop;
    MatchScrollPixels(Src, Dst);
    if Dst.ColumnLeft <> Src.ColumnLeft then
      Dst.ColumnLeft := Src.ColumnLeft;
  finally
    FSyncingScroll := False;
  end;
end;

{ The top line puts the two sides in step to the line. Within a line
  they can still be apart: the pixels scrolled into it, or with the
  review comments' cards (umain.reviews.inc), into the gaps under it or
  over the first line (position -1), which both sides have the same. }
procedure TForm1.MatchScrollPixels(ASrc, ADst: TATSynEdit);
var
  Info: TATEditorScrollInfo;
begin
  Info := ADst.ScrollVert;
  if (Info.NPos = ASrc.ScrollVert.NPos) and
    (Info.NPixelOffset = ASrc.ScrollVert.NPixelOffset) then
    Exit;
  Info.NPos := ASrc.ScrollVert.NPos;
  Info.NPixelOffset := ASrc.ScrollVert.NPixelOffset;
  Info.SmoothPos := ASrc.ScrollVert.SmoothPos;
  ADst.ScrollVert := Info;
  ADst.Update;
end;

{ The scroll event fires for the user's scrolling only; after the view
  is built or moved by the program the old side is put in step here.
  An old side that was just shown has no layout yet and ignores the
  scroll position, so the sync is repeated from the message loop. }
procedure TForm1.SyncOldSide;
begin
  if not FEditOld.Visible then
    Exit;
  SyncOldSideAsync(0);
  Application.QueueAsyncCall(@SyncOldSideAsync, 0);
end;

procedure TForm1.SyncOldSideAsync(Data: PtrInt);
begin
  if not FEditOld.Visible then
    Exit;
  FSyncingScroll := True;
  try
    { A scroll position needs the wrap info, which the first paint would
      build; an old side shown a moment ago has none yet. The resize that
      follows showing it makes the editor restore its line top at the
      next paint, from LineTopTodo, so that is set as well. }
    FEditOld.HandleNeeded;
    FEditOld.UpdateWrapInfo(True);
    FEditOld.LineTop := Edit.LineTop;
    FEditOld.LineTopTodo := Edit.LineTop;
    MatchScrollPixels(Edit, FEditOld);
    if FEditOld.ColumnLeft <> Edit.ColumnLeft then
      FEditOld.ColumnLeft := Edit.ColumnLeft;
    FEditOld.Invalidate;
  finally
    FSyncingScroll := False;
  end;
end;

{ The old side keeps its share of the width when the panel resizes. }
procedure TForm1.EditorPanelResize(Sender: TObject);
begin
  if FEditOld.Visible then
    FEditOld.Width := Round((EditorPanel.ClientWidth - FSideSplitter.Width) * FSideRatio);
end;

procedure TForm1.SideSplitterMoved(Sender: TObject);
begin
  if EditorPanel.ClientWidth > FSideSplitter.Width then
    FSideRatio := FEditOld.Width / (EditorPanel.ClientWidth - FSideSplitter.Width);
end;

{ Shows the old side next to the editor in the side-by-side change view,
  hides it in every other view. Word wrap is off while the two sides are
  shown: wrapped rows would not line up. }
procedure TForm1.ApplyLayout;
var
  Side: boolean;
begin
  Side := FSideBySide and (FView = gvChanges);
  if Side then
    FEditOld.Width := Round((EditorPanel.ClientWidth - FSideSplitter.Width) * FSideRatio);
  FEditOld.Visible := Side;
  FSideSplitter.Visible := Side;
  if Side then
    FSideSplitter.Left := FEditOld.Width + 1;
  ApplyWrap;
end;

procedure TForm1.ApplyWrap;
var
  Mode: TATEditorWrapMode;
begin
  if FWordWrap and not (FSideBySide and (FView = gvChanges)) then
    Mode := TATEditorWrapMode.ModeOn
  else
    Mode := TATEditorWrapMode.ModeOff;
  if Edit.OptWrapMode <> Mode then
    Edit.OptWrapMode := Mode;
  if FEditOld.OptWrapMode <> Mode then
    FEditOld.OptWrapMode := Mode;
end;

{ After a view option changed: the change view is built again at the
  same place, other views are left alone. }
procedure TForm1.RebuildIfChanges;
var
  TopLine, CaretY: integer;
begin
  if (FView <> gvChanges) or (FCurrentPath = '') then
    Exit;
  TopLine := Edit.LineTop;
  CaretY := Edit.Carets[0].PosY;
  ApplyLayout;
  BuildChangeView;
  if Edit.Strings.Count > 0 then
  begin
    Edit.DoCaretSingle(0, VisibleRow(CaretY));
    Edit.LineTop := Min(TopLine, Edit.Strings.Count - 1);
  end;
  Edit.Update;
  SyncOldSide;
  UpdateChangeNav;
end;
