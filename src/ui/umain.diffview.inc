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
  gap rows' text takes them (SetGapRowTexts). }

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

procedure TRepoFrame.BuildChangeView;
var
  n, i, j, k, r, d0, a0, Dels, Adds, NRows, NLeft, NRight, NBlocks: integer;
  Keep: array of boolean;
  OldNum, NewNum: TIntegerDynArray;
  Rows, LeftRows, RightRows: TGittanRows;
  Lexer: TecSyntAnalyzer;

  { ARows is sized for the most rows it can get and ACount counts the
    ones used, so a file of many thousand lines is not copied once per
    row; the arrays are cut to their count at the end. }
  procedure AddRow(var ARows: TGittanRows; var ACount: integer;
    ALine, AFrom, ATo: integer; AHidden: boolean = False);
  begin
    ARows[ACount].Line := ALine;
    ARows[ACount].GapFrom := AFrom;
    ARows[ACount].GapTo := ATo;
    ARows[ACount].Hidden := AHidden;
    Inc(ACount);
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
  SetLength(FBlockStarts, n);
  NBlocks := 0;
  for i := 0 to n - 1 do
    if (FChangeLines[i][1] <> ' ') and ((i = 0) or (FChangeLines[i - 1][1] = ' ')) then
    begin
      FBlockStarts[NBlocks] := i;
      Inc(NBlocks);
    end;
  SetLength(FBlockStarts, NBlocks);
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
    the run of hidden lines it stands for: at most a gap row per line. }
  SetLength(Rows, 2 * n);
  NRows := 0;
  i := 0;
  while i < n do
  begin
    if Keep[i] then
      AddRow(Rows, NRows, i, 0, 0)
    else
    begin
      j := i;
      while (j + 1 < n) and not Keep[j + 1] do
        Inc(j);
      AddRow(Rows, NRows, rowGap, i, j);
      for k := i to j do
        AddRow(Rows, NRows, k, 0, 0, True);
      i := j;
    end;
    Inc(i);
  end;
  SetLength(Rows, NRows);
  Lexer := App.Lexers.ForFile(FCurrentPath, FRepo.Root);
  FGapTextRounds := 0;
  FBuildingView := True;
  try
    if not FSideBySide then
    begin
      FRows := Rows;
      FRowsOld := nil;
      { The blocks are counted anew: the one under the mouse is no
        longer the one it was. }
      SetHotDiscard(Edit, -1, -1, -1);
      FindConflictRows;
      FillChangeEditor(Edit, Rows, False, OldNum, NewNum, Lexer);
      Exit;
    end;
  { Side by side: a context or gap row goes to both sides; a run of
    deleted lines and the run of added lines after it go to the old and
    the new side, the shorter padded with fillers, so neither side gets
    more rows than the unified view has. }
  SetLength(LeftRows, Length(Rows));
  SetLength(RightRows, Length(Rows));
  NLeft := 0;
  NRight := 0;
  r := 0;
  while r < Length(Rows) do
  begin
    if Marker(Rows[r]) = ' ' then
    begin
      AddRow(LeftRows, NLeft, Rows[r].Line, Rows[r].GapFrom, Rows[r].GapTo, Rows[r].Hidden);
      AddRow(RightRows, NRight, Rows[r].Line, Rows[r].GapFrom, Rows[r].GapTo, Rows[r].Hidden);
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
        AddRow(LeftRows, NLeft, Rows[d0 + k].Line, 0, 0)
      else
        AddRow(LeftRows, NLeft, rowFiller, 0, 0);
      if k < Adds then
        AddRow(RightRows, NRight, Rows[a0 + k].Line, 0, 0)
      else
        AddRow(RightRows, NRight, rowFiller, 0, 0);
    end;
  end;
  SetLength(LeftRows, NLeft);
  SetLength(RightRows, NRight);
    FRows := RightRows;
    FRowsOld := LeftRows;
    SetHotDiscard(Edit, -1, -1, -1);
    FindConflictRows;
    FillChangeEditor(FEditOld, LeftRows, True, OldNum, NewNum, Lexer);
    FillChangeEditor(Edit, RightRows, False, OldNum, NewNum, Lexer);
    FEditOld.LineTop := 0;
  finally
    FBuildingView := False;
    SetFoldBand(Edit, FoldingShown);
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
procedure TRepoFrame.FillChangeEditor(AEd: TATSynEdit; const ARows: TGittanRows;
  AOldSide: boolean; const AOldNum, ANewNum: TIntegerDynArray;
  ALexer: TecSyntAnalyzer);
var
  Lines: TStringList;
  Numbers, Kinds: TIntegerDynArray;
  i, Role: integer;
  Marker: char;
  Hidden: boolean;
begin
  Lines := TStringList.Create;
  try
    for i := 0 to High(ARows) do
      case ARows[i].Line of
        rowGap:
          Lines.Add(GapRowText(ARows[i].GapTo - ARows[i].GapFrom + 1,
            GapHeading(ARows[i].GapTo)));
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
        if (Role = crNone) and LineLeftOut(ARows[i].Line) then
        begin
          { A change left out of the commit keeps its strip in a muted
            tint, without its word shades (see umain.leaveout.inc). }
          if Marker = '+' then
          begin
            AEd.Strings.LinesState[i] := TATLineState.Added;
            MarkRow(AEd, i, bmLeftOutAdded);
          end
          else
          begin
            AEd.Strings.LinesState[i] := TATLineState.Changed;
            MarkRow(AEd, i, bmLeftOutDeleted);
          end;
        end
        else if Role = crNone then
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
        if (Role = crNone) and (ARows[i].Line <= High(FWordSpans)) and
          not LineLeftOut(ARows[i].Line) then
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
function TRepoFrame.VisibleRow(ARow: integer): integer;
var
  Last: integer;
begin
  Last := Edit.Strings.Count - 1;
  Result := Max(0, Min(ARow, Last));
  while (Result < Last) and Edit.IsLineFolded(Result) do
    Inc(Result);
end;

{ The row that shows the diff line ALine, on either side, or the gap
  row that hides it; VisibleRow(AFallback) when no row does (ALine -1). }
function TRepoFrame.RowOfLine(ALine, AFallback: integer): integer;
var
  r: integer;
begin
  if ALine >= 0 then
    for r := 0 to High(FRows) do
    begin
      if FRows[r].Hidden or Edit.IsLineFolded(r) then
        Continue;
      if (FRows[r].Line = ALine) or ((r <= High(FRowsOld)) and (FRowsOld[r].Line = ALine)) or
        ((FRows[r].Line = rowGap) and (FRows[r].GapFrom <= ALine) and (ALine <= FRows[r].GapTo)) then
        Exit(Min(r, Edit.Strings.Count - 1));
    end;
  Result := VisibleRow(AFallback);
end;

{ The text of a gap row standing for ACount hidden lines, with
  AHeading, the symbol the changes after the gap are in, after it. The
  row is painted over its text (EditDrawLine), so this is what a copy or
  a search of the text sees. }
function TRepoFrame.GapRowText(ACount: integer; const AHeading: string): string;
begin
  if ACount = 1 then
    Result := rsGapLine
  else
    Result := Format(rsGapLines, [ACount]);
  if AHeading <> '' then
    Result := Result + '      ' + AHeading;
end;

procedure TRepoFrame.GapTextsAsync(Data: PtrInt);
begin
  FGapTextQueued := False;
  if FView <> gvChanges then
    Exit;
  SetGapRowTexts(Edit, FRows);
  if FEditOld.Visible then
    SetGapRowTexts(FEditOld, FRowsOld);
end;

{ Puts the text of every gap row of ARows into AEd again, with the
  headings as they are now, so a copy or a search sees the names the
  parse found after the build. Only rows whose text differs change; the
  editor stays read-only and unmodified, and the change starts a new
  parse, which finds the same names. }
procedure TRepoFrame.SetGapRowTexts(AEd: TATSynEdit; const ARows: TGittanRows);
var
  r: integer;
  S: UnicodeString;
  Wrote: boolean;
begin
  Wrote := False;
  for r := 0 to Min(High(ARows), AEd.Strings.Count - 1) do
  begin
    if (ARows[r].Line <> rowGap) or ARows[r].Hidden then
      Continue;
    S := UTF8Decode(GapRowText(ARows[r].GapTo - ARows[r].GapFrom + 1,
      GapHeading(ARows[r].GapTo)));
    if AEd.Strings.Lines[r] = S then
      Continue;
    if not Wrote then
      AEd.ModeReadOnly := False;
    Wrote := True;
    AEd.Strings.Lines[r] := S;
    AEd.Strings.LinesState[r] := TATLineState.None;
  end;
  if not Wrote then
    Exit;
  AEd.ModeReadOnly := True;
  AEd.Modified := False;
  { The wrap info is rebuilt from the hidden-lines map, as after a build. }
  AEd.Strings.WrapStructInvalidate;
  AEd.Update(True);
end;

{ Lays out the gap row ARow of AEd, whose top is at ATop: the fold
  glyph, "116 unchanged lines" in the window's font a size under the
  editor's (smaller still when the editor's line is low), the chips
  that open the first GapStep hidden lines, the last ones and all of
  them (a short run has Show alone), each only while it fits the text
  area, Down first, and the symbol's name at the right end, left out
  when it would run into the chips. The history view's
  more row (rowMore) has one chip for the older changes. C is left with
  the row's font. False for a row that is not one of these, or in
  another view. }
function TRepoFrame.GapRowLayout(AEd: TATSynEdit; C: TCanvas; ARow, ATop: integer;
  out ALayout: TGapRowLayout): boolean;
var
  CharH, X, PadX, TextH, Count, Right, Gap, W: integer;
  Chip, Rest: TGapChip;
begin
  Result := False;
  ALayout := Default(TGapRowLayout);
  if (ARow < 0) or (ARow > High(FRows)) then
    Exit;
  if not (((FRows[ARow].Line = rowGap) and (FView = gvChanges)) or
    ((FRows[ARow].Line = rowMore) and (FView = gvHistory))) then
    Exit;
  CharH := AEd.TextCharSize.Y;
  C.Font.Assign(FHeader.Font);
  C.Font.Style := [];
  C.Font.Size := Max(MinGapFontSize, EditorFontSize(AEd) - 1);
  TextH := C.TextHeight('Xg');
  while (TextH + Px(2) > CharH) and (C.Font.Size > MinGapFontSize) do
  begin
    C.Font.Size := C.Font.Size - 1;
    TextH := C.TextHeight('Xg');
  end;
  ALayout.ChipHeight := Min(CharH - Px(2), TextH + Px(4));
  ALayout.TextY := ATop + (CharH - TextH) div 2;
  Gap := Max(Px(6), CharH div 2);
  X := AEd.RectMain.Left + Gap;
  ALayout.Icon := Rect(X, ATop, X + CharH, ATop + CharH);
  Inc(X, CharH + Px(4));
  PadX := Max(Px(6), ALayout.ChipHeight div 2);
  if FRows[ARow].Line = rowGap then
  begin
    Count := FRows[ARow].GapTo - FRows[ARow].GapFrom + 1;
    if Count = 1 then
      ALayout.Text := rsGapLine
    else
      ALayout.Text := Format(rsGapLines, [Count]);
    ALayout.TextX := X;
    Inc(X, C.TextWidth(ALayout.Text) + CharH);
    if Count > GapStep then
    begin
      ALayout.ChipText[gcDown] := Format(rsGapDown, [GapStep]);
      ALayout.ChipText[gcUp] := Format(rsGapUp, [GapStep]);
      ALayout.ChipText[gcAll] := rsGapAll;
    end
    else
      ALayout.ChipText[gcAll] := rsGapShow;
    ALayout.Heading := GapHeading(FRows[ARow].GapTo);
  end
  else
    ALayout.ChipText[gcAll] := Format(rsHistoryMore, [HistoryStep]);
  Right := AEd.RectMain.Right - Gap;
  for Chip in TGapChip do
  begin
    if ALayout.ChipText[Chip] = '' then
      Continue;
    W := C.TextWidth(ALayout.ChipText[Chip]) + 2 * PadX;
    if X + W > Right then
    begin
      { A narrow pane: this chip and the ones after it are left out. }
      for Rest := Chip to High(TGapChip) do
        ALayout.ChipText[Rest] := '';
      Break;
    end;
    ALayout.Chips[Chip] := Rect(X, ATop + (CharH - ALayout.ChipHeight) div 2, X + W, 0);
    ALayout.Chips[Chip].Bottom := ALayout.Chips[Chip].Top + ALayout.ChipHeight;
    X := ALayout.Chips[Chip].Right + Px(6);
  end;
  if ALayout.Heading <> '' then
  begin
    ALayout.HeadingX := Right - C.TextWidth(ALayout.Heading);
    if ALayout.HeadingX < X + CharH then
      ALayout.Heading := '';
  end;
  Result := True;
end;

{ Paints a gap row over the text the editor has just drawn for it, the
  whole width of the text area whatever the horizontal scroll: the
  row's tint, a fold glyph (two chevrons apart), the description and
  the symbol's name in the dim color, and the chips as pills, the one
  under the mouse in the accent. A row that word wrap splits has them
  on its first part alone, where GapPartAt looks for them, and the tint
  on the others. The editor goes on painting with the canvas's font, so
  it is put back. }
procedure TRepoFrame.EditDrawLine(Sender: TObject; C: TCanvas; ALineIndex, AX, AY: integer;
  const AStr: atString; const ACharSize: TATEditorCharSize;
  constref AExtent: TATIntFixedArray);
var
  Ed: TATSynEdit;
  L: TGapRowLayout;
  P: TGittanPalette;
  Tint: TColor;
  R: TRect;
  Chip: TGapChip;
  Hot: boolean;
  Cx, Cy, S, CharH: integer;
  FontName: string;
  FontSize: integer;
  FontStyle: TFontStyles;
  FontColor: TColor;
  BrushStyle: TBrushStyle;
begin
  Ed := TATSynEdit(Sender);
  if (Ed <> Edit) and (Ed <> FEditOld) then
    Exit;
  FontName := C.Font.Name;
  FontSize := C.Font.Size;
  FontStyle := C.Font.Style;
  FontColor := C.Font.Color;
  BrushStyle := C.Brush.Style;
  if not GapRowLayout(Ed, C, ALineIndex, AY, L) then
  begin
    C.Font.Name := FontName;
    C.Font.Size := FontSize;
    C.Font.Style := FontStyle;
    C.Font.Color := FontColor;
    Exit;
  end;
  CharH := Ed.TextCharSize.Y;
  P := Palette;
  Tint := Ed.Colors.TextBG;
  EditCalcBookmarkColor(Ed, bmGap, Tint);
  R := Rect(Ed.RectMain.Left, AY, Ed.RectMain.Right, AY + CharH);
  C.Brush.Style := bsSolid;
  C.Brush.Color := Tint;
  C.FillRect(R);
  if Ed.CaretPosToClientPos(Point(0, ALineIndex)).Y <> AY then
  begin
    C.Brush.Style := BrushStyle;
    C.Font.Name := FontName;
    C.Font.Size := FontSize;
    C.Font.Style := FontStyle;
    C.Font.Color := FontColor;
    Exit;
  end;
  C.Pen.Style := psSolid;
  C.Pen.Width := Max(1, Px(1));
  C.Pen.Color := P.Dim;
  Cx := (L.Icon.Left + L.Icon.Right) div 2;
  Cy := (L.Icon.Top + L.Icon.Bottom) div 2;
  S := Max(2, CharH div 5);
  C.Line(Cx - S, Cy - 2, Cx, Cy - 2 - S);
  C.Line(Cx, Cy - 2 - S, Cx + S + 1, Cy - 1);
  C.Line(Cx - S, Cy + 2, Cx, Cy + 2 + S);
  C.Line(Cx, Cy + 2 + S, Cx + S + 1, Cy + 1);
  C.Brush.Style := bsClear;
  C.Font.Color := P.Dim;
  if L.Text <> '' then
    C.TextOut(L.TextX, L.TextY, L.Text);
  for Chip in TGapChip do
  begin
    if L.ChipText[Chip] = '' then
      Continue;
    Hot := (Ed = FHotGapEd) and (ALineIndex = FHotGapRow) and (Ord(Chip) = FHotGapChip);
    C.Pen.Width := 1;
    C.Brush.Style := bsSolid;
    if Hot then
    begin
      C.Pen.Color := P.Accent;
      C.Brush.Color := MixColor(P.Pill, P.Accent, 0.18);
    end
    else
    begin
      C.Pen.Color := P.Border;
      C.Brush.Color := P.Pill;
    end;
    R := L.Chips[Chip];
    C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, L.ChipHeight, L.ChipHeight);
    C.Brush.Style := bsClear;
    if Hot then
      C.Font.Color := P.Accent
    else
      C.Font.Color := P.PillText;
    C.TextOut(R.Left + (R.Width - C.TextWidth(L.ChipText[Chip])) div 2, L.TextY,
      L.ChipText[Chip]);
  end;
  if L.Heading <> '' then
  begin
    C.Font.Color := P.Dim;
    C.TextOut(L.HeadingX, L.TextY, L.Heading);
  end;
  C.Pen.Width := 1;
  C.Brush.Style := BrushStyle;
  C.Font.Name := FontName;
  C.Font.Size := FontSize;
  C.Font.Style := FontStyle;
  C.Font.Color := FontColor;
end;

{ What is under the mouse at X, Y of AEd: gapPartNone when it is not on a
  gap row, else ARow is the row and the answer Ord of the chip, gapPartHeading
  on the symbol's name, or gapPartRow elsewhere on the row. The layout
  takes the editor's canvas, whose font is put back. }
function TRepoFrame.GapPartAt(AEd: TATSynEdit; X, Y: integer; out ARow: integer): integer;
var
  Details: TATEditorPosDetails;
  L: TGapRowLayout;
  Chip: TGapChip;
  RowTop: integer;
  Saved: TFont;
begin
  Result := gapPartNone;
  ARow := AEd.ClientPosToCaretPos(ATPoint(X, Y), Details).Y;
  if (ARow < 0) or Details.BelowAllText or (X < AEd.RectMain.Left) or
    (X >= AEd.RectMain.Right) then
    Exit;
  RowTop := AEd.CaretPosToClientPos(Point(0, ARow)).Y;
  Saved := TFont.Create;
  try
    Saved.Assign(AEd.Canvas.Font);
    if not GapRowLayout(AEd, AEd.Canvas, ARow, RowTop, L) then
      Exit;
    Result := gapPartRow;
    for Chip in TGapChip do
      if (L.ChipText[Chip] <> '') and L.Chips[Chip].Contains(Point(X, Y)) then
        Exit(Ord(Chip));
    if (L.Heading <> '') and (X >= L.HeadingX) and
      (X < L.HeadingX + AEd.Canvas.TextWidth(L.Heading)) then
      Result := gapPartHeading;
  finally
    AEd.Canvas.Font.Assign(Saved);
    Saved.Free;
  end;
end;

{ The hint of a chip of gap row ARow (APart from GapPartAt): what it
  opens; '' off the chips. }
function TRepoFrame.GapPartHint(ARow, APart: integer): string;
var
  Count: integer;
begin
  Result := '';
  if (APart < 0) or (ARow < 0) or (ARow > High(FRows)) or (FRows[ARow].Line <> rowGap) then
    Exit;
  Count := FRows[ARow].GapTo - FRows[ARow].GapFrom + 1;
  case TGapChip(APart) of
    gcDown: Result := Format(rsGapDownHint, [GapStep]);
    gcUp: Result := Format(rsGapUpHint, [GapStep]);
    gcAll:
      if Count = 1 then
        Result := rsGapOneHint
      else
        Result := Format(rsGapAllHint, [Count]);
  end;
end;

{ The gap row and the part of it under the mouse, for the chip's accent
  and the hand cursor (HandCursorAsync); a change repaints, and leaving
  the rows puts the arrow back. }
procedure TRepoFrame.SetHotGap(AEd: TATSynEdit; ARow, APart: integer);
var
  Old: TATSynEdit;
begin
  if (AEd = FHotGapEd) and (ARow = FHotGapRow) and (APart = FHotGapChip) then
    Exit;
  Old := FHotGapEd;
  FHotGapEd := AEd;
  FHotGapRow := ARow;
  FHotGapChip := APart;
  if Old <> nil then
  begin
    Old.Invalidate;
    if Old <> AEd then
      Old.Cursor := crDefault;
  end;
  if AEd <> nil then
  begin
    AEd.Invalidate;
    if APart = gapPartHeading then
      AEd.Cursor := crDefault;
  end;
end;

{ The heading of the gap row that hides the diff lines up to AGapTo: the
  name of the symbol around the first block of changes after the gap,
  as far as UpdateSymbolHeadings has found the names; '' for no block
  (the gap runs to the end) or no symbol. }
function TRepoFrame.GapHeading(AGapTo: integer): string;
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
function TRepoFrame.RowMarkers(const ARows: TGittanRows; AOldSide: boolean): string;
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
function TRepoFrame.RowTexts(AEd: TATSynEdit): TStringList;
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
procedure TRepoFrame.UpdateSymbolHeadings;
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
  { The gap rows paint the names as they are now (EditDrawLine), so a
    repaint shows them. Their text takes them too, for a copy or a
    search; a lexer that reads a heading as code could name the blocks
    differently each time, so twice a build at most. }
  if FGapTextRounds < 2 then
  begin
    Inc(FGapTextRounds);
    { The adapter is still in its parse-done handler, and a change of
      the text starts a parse; the text is written from the message
      loop. }
    if not FGapTextQueued then
    begin
      FGapTextQueued := True;
      Application.QueueAsyncCall(@GapTextsAsync, 0);
    end;
  end;
  Edit.Invalidate;
  if FEditOld.Visible then
    FEditOld.Invalidate;
end;

{ The file header names the symbol the caret is in, from the code tree
  of the last parse while the text is the one it parsed. }
procedure TRepoFrame.UpdateSymbolCrumb;
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
procedure TRepoFrame.ExpandGap(AFrom, ATo: integer);
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

{ A click on a gap row opens it: on one of its chips (see GapRowLayout)
  the first or the last GapStep lines, elsewhere the whole run; in the
  history view a click on a commit header or the more row acts (see
  HistoryClick). Cmd+click (Ctrl+click elsewhere) goes to the definition
  of the clicked word. The editor put the caret on the clicked position
  on mouse down. }
procedure TRepoFrame.EditMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
var
  Row, Part, From, To_: integer;
begin
  if Button <> mbLeft then
    Exit;
  { A click on a review comment's card (see EditClickGap). }
  if FGapLink <> '' then
  begin
    Application.QueueAsyncCall(@OpenGapLinkAsync, 0);
    Exit;
  end;
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
  Part := GapPartAt(TATSynEdit(Sender), X, Y, Row);
  { A click on the symbol's name opens nothing. }
  if (Part = gapPartNone) or (Part = gapPartHeading) or (FRows[Row].Line <> rowGap) then
    Exit;
  From := FRows[Row].GapFrom;
  To_ := FRows[Row].GapTo;
  if Part = Ord(gcDown) then
    To_ := From + GapStep - 1
  else if Part = Ord(gcUp) then
    From := To_ - GapStep + 1;
  SetHotGap(nil, -1, gapPartNone);
  ExpandGap(From, To_);
end;


{ The two sides scroll together. The event fires after a paint, so the
  other side is moved only when it differs; its own event then finds
  nothing to do. }
procedure TRepoFrame.EditorScroll(Sender: TObject);
var
  Src, Dst: TATSynEdit;
begin
  if Sender = Edit then
    PillsScrolled;
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
procedure TRepoFrame.MatchScrollPixels(ASrc, ADst: TATSynEdit);
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
procedure TRepoFrame.SyncOldSide;
begin
  if not FEditOld.Visible then
    Exit;
  SyncOldSideAsync(0);
  Application.QueueAsyncCall(@SyncOldSideAsync, 0);
end;

procedure TRepoFrame.SyncOldSideAsync(Data: PtrInt);
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

{ The width the two sides share: the panel's, less the Markdown preview
  and its splitter when they are shown. }
function TRepoFrame.SidesWidth: integer;
begin
  Result := EditorPanel.ClientWidth - FSideSplitter.Width;
  if FMdPreview.Visible then
    Dec(Result, FMdPreview.Width + FMdSplitter.Width);
end;

{ The old side and the Markdown preview keep their shares of the width
  when the panel resizes. }
procedure TRepoFrame.EditorPanelResize(Sender: TObject);
begin
  if FGraph <> nil then
    FGraph.Recenter;
  if FNotice <> nil then
    FNotice.Recenter;
  if FMdPreview.Visible then
    FMdPreview.Width := Round(EditorPanel.ClientWidth * FMdRatio);
  if FEditOld.Visible then
    FEditOld.Width := Round(SidesWidth * FSideRatio);
end;

procedure TRepoFrame.SideSplitterMoved(Sender: TObject);
begin
  if SidesWidth > 0 then
    FSideRatio := FEditOld.Width / SidesWidth;
end;

{ Shows the old side next to the editor in the side-by-side change view
  and the translation view, hides it in every other view. Word wrap is
  off while the two sides are shown: wrapped rows would not line up. }
procedure TRepoFrame.ApplyLayout;
var
  Side: boolean;
begin
  Side := SidesShown;
  if Side then
    FEditOld.Width := Round(SidesWidth * FSideRatio);
  FEditOld.Visible := Side;
  FSideSplitter.Visible := Side;
  if Side then
    FSideSplitter.Left := FEditOld.Width + 1;
  ApplyWrap;
end;

procedure TRepoFrame.ApplyWrap;
var
  Mode: TATEditorWrapMode;
begin
  if FWordWrap and not SidesShown then
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
procedure TRepoFrame.RebuildIfChanges;
var
  TopLine, CaretY, CaretLine, Row: integer;
begin
  if (FView <> gvChanges) or (FCurrentPath = '') then
    Exit;
  TopLine := Edit.LineTop;
  CaretY := Edit.Carets[0].PosY;
  { The rows change with the layout (Hide Unchanged Lines, side by side):
    the caret stays on its diff line, as far from the top as it was. }
  CaretLine := LineAtRow(CaretY);
  { On a gap: its first hidden line, shown or in a gap again after. }
  if (CaretLine < 0) and (CaretY >= 0) and (CaretY <= High(FRows)) and
    (FRows[CaretY].Line = rowGap) then
    CaretLine := FRows[CaretY].GapFrom;
  KeepFolds;
  ApplyLayout;
  BuildChangeView;
  if Edit.Strings.Count > 0 then
  begin
    Row := RowOfLine(CaretLine, CaretY);
    Edit.DoCaretSingle(0, Row);
    Edit.LineTop := Max(0, Min(Row - (CaretY - TopLine), Edit.Strings.Count - 1));
  end;
  Edit.Update;
  SyncOldSide;
  UpdateChangeNav;
end;
