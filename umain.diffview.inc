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
  step. }

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
  WordDiff(FChangeLines, FIgnoreWhitespace, FWordSpans);
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
  if not FSideBySide then
  begin
    FRows := Rows;
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
  FillChangeEditor(FEditOld, LeftRows, True, OldNum, NewNum, Lexer);
  FillChangeEditor(Edit, RightRows, False, OldNum, NewNum, Lexer);
  FEditOld.LineTop := 0;
end;

{ Puts ARows into AEd: the text, the hidden lines, the line colors and
  states, and the line numbers (from the old file on the old side, else
  from the new). A deleted line in the unified view has no number; a
  gap, filler or hidden row has neither number nor state. }
procedure TForm1.FillChangeEditor(AEd: TATSynEdit; const ARows: TGittanRows;
  AOldSide: boolean; const AOldNum, ANewNum: TIntegerDynArray;
  ALexer: TecSyntAnalyzer);
var
  Lines: TStringList;
  Numbers, Kinds: TIntegerDynArray;
  i, Count: integer;
  Marker: char;
  Hidden: boolean;
begin
  Lines := TStringList.Create;
  try
    for i := 0 to High(ARows) do
      case ARows[i].Line of
        rowGap:
          begin
            Count := ARows[i].GapTo - ARows[i].GapFrom + 1;
            if Count = 1 then
              Lines.Add(rsGapLine)
            else
              Lines.Add(Format(rsGapLines, [Count]));
          end;
        rowFiller: Lines.Add('');
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
      else
      begin
        Marker := FChangeLines[ARows[i].Line][1];
        MarkLine(AEd, i, Marker);
        if ARows[i].Line <= High(FWordSpans) then
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

{ A click on a gap row opens it; Cmd+click (Ctrl+click elsewhere) goes
  to the definition of the clicked word. The editor put the caret on the
  clicked position on mouse down. }
procedure TForm1.EditMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
var
  Row: integer;
begin
  if Button <> mbLeft then
    Exit;
  if ssModifier in Shift then
  begin
    if TATSynEdit(Sender).Carets[0].EndY < 0 then
      GoToDefinition(TATSynEdit(Sender));
    Exit;
  end;
  if FView <> gvChanges then
    Exit;
  Row := TATSynEdit(Sender).Carets[0].PosY;
  if (Row >= 0) and (Row <= High(FRows)) and (FRows[Row].Line = rowGap) then
    ExpandGap(FRows[Row].GapFrom, FRows[Row].GapTo);
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
    if Dst.ColumnLeft <> Src.ColumnLeft then
      Dst.ColumnLeft := Src.ColumnLeft;
  finally
    FSyncingScroll := False;
  end;
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
