{ ---------------------------------------------------------------------------
  Review comments
  ---------------------------------------------------------------------------
  Included by umain.pp. View > Review Comments shows the review threads
  of a pull request on GitHub in the change view, each in a card under
  the line it is on, as GitHub shows them. The pull request is the one
  compared against (Compare With > Pull Requests), whose diff is the one
  the comments were made on, else the branch's own, whose head is mapped
  onto the work tree (MapLine over `git diff -U0 <head> -- path`), so a
  comment follows its line through the changes made since. A comment on
  a removed line is placed when the old side is the pull request's base
  (its own diff, or the merge base with the default branch); one that
  cannot be placed (outdated, on the whole file, on a removed line that
  is not shown) goes to the top of the file.

  The cards are gaps of the editor (TATGaps): room under a line that the
  editor leaves to OnDrawGap, outside the text, so the lexer, the line
  numbers and the rows are untouched. A gap's Tag is the index of its
  thread in FThreads; in the side-by-side view the other side gets an
  empty gap of the same height (Tag -1), so the rows stay in step. A
  resolved or outdated thread starts folded to one line; a click on a
  card folds or unfolds it, a click on "GitHub ↗" opens it in the
  browser. }

const
  { The kinds of the lines of a card, in the Objects of its layout. }
  rlNote = 1;
  rlHeader = 2;
  rlBody = 3;
  rlCode = 4;
  rlRule = 5;
  rlFolded = 6;
  { Room around a card, inside it, and the most it widens to. }
  ReviewMargin = 6;
  ReviewPadX = 12;
  ReviewPadY = 7;
  ReviewMaxWidth = 860;
  ReviewRuleHeight = 11;
  { FThreadRows: a thread of another file, one at the top of this one. }
  threadElsewhere = -2;
  threadOnTop = -1;

{ Everything a card shows, so a poll that finds the same changes
  nothing. }
function ThreadsKey(const AThreads: TGittanReviewThreads; const AHead: string): string;
var
  S: string;
  t, c: integer;
begin
  S := AHead;
  for t := 0 to High(AThreads) do
  begin
    S := S + #1 + AThreads[t].Path + #0 + IntToStr(AThreads[t].Line) + #0 +
      IntToStr(AThreads[t].StartLine) + #0 + BoolToStr(AThreads[t].LeftSide, True) +
      BoolToStr(AThreads[t].Resolved, True) + BoolToStr(AThreads[t].Outdated, True);
    for c := 0 to High(AThreads[t].Comments) do
      S := S + #2 + AThreads[t].Comments[c].Url + #0 + AThreads[t].Comments[c].Body;
  end;
  Result := MD5Print(MD5String(S));
end;

{ The link of a note in the summary's conversation. }
procedure TForm1.SummaryOpenUrl(Sender: TObject; const AUrl: string);
begin
  OpenURL(AUrl);
end;

procedure TForm1.MenuReviewCommentsClick(Sender: TObject);
begin
  FShowComments := not FShowComments;
  FReviewItem.Checked := FShowComments;
  if FShowComments then
    StartReviewJob(False)
  else
  begin
    AbandonReviewJob;
    ClearReviews;
    UpdateStatus;
  end;
  RebuildIfChanges;
end;

{ The pull request whose comments the change view shows: the one
  compared against, else the branch's own as long as the view's new side
  is the work tree. }
function TForm1.ReviewTarget(out ANumber: integer; out ARepoPath: string): boolean;
var
  i: integer;
begin
  ANumber := 0;
  ARepoPath := '';
  if not FShowComments or not FHasGitHubCli or (FRepo.Root = '') then
    Exit(False);
  if (FPullRange <> '') and (FRepo.Base = FPullRange) and FRepo.IsRange then
  begin
    ANumber := FPullNumber;
    for i := 0 to High(FPulls) do
      if FPulls[i].Number = FPullNumber then
        ARepoPath := RepoPathOfUrl(FPulls[i].Url);
    if (ARepoPath = '') and FHasPull and (FPull.Number = FPullNumber) then
      ARepoPath := RepoPathOfUrl(FPull.Url);
  end
  else if FHasPull and not FRepo.IsRange then
  begin
    ANumber := FPull.Number;
    ARepoPath := RepoPathOfUrl(FPull.Url);
  end;
  Result := (ANumber > 0) and (ARepoPath <> '');
end;

{ Whether the view is the pull request's own diff, where its lines are
  the view's lines. }
function TForm1.ReviewExact: boolean;
begin
  Result := (FPullRange <> '') and (FRepo.Base = FPullRange) and FRepo.IsRange and
    (FThreadsNumber = FPullNumber);
end;

procedure TForm1.ClearReviews;
begin
  FThreads := nil;
  FThreadRows := nil;
  FThreadsNumber := 0;
  FThreadsRepo := '';
  FThreadsHead := '';
  FThreadsKey := '';
  FReviewError := '';
  FMapDiffKey := '';
  FSummary.SetNotes('', nil);
  FileTree.Invalidate;
end;

{ Fetches the threads of the pull request ReviewTarget names when they
  are not the ones held, or again with AForce (a poll). Threads of
  another pull request are dropped at once. }
procedure TForm1.StartReviewJob(AForce: boolean);
var
  Number: integer;
  RepoPath: string;
begin
  if not ReviewTarget(Number, RepoPath) then
  begin
    AbandonReviewJob;
    if FThreadsNumber <> 0 then
    begin
      ClearReviews;
      RebuildIfChanges;
    end;
    Exit;
  end;
  if (Number <> FThreadsNumber) or (RepoPath <> FThreadsRepo) then
  begin
    if FThreadsNumber <> 0 then
    begin
      ClearReviews;
      RebuildIfChanges;
    end;
  end
  else if not AForce then
    Exit;
  if (FReviewJob <> nil) and (FReviewJob.Number = Number) and
    (FReviewJob.RepoPath = RepoPath) then
    Exit;
  AbandonReviewJob;
  FReviewJob := TGittanReviewJob.Create(FGitHubCli, FRepo.Root, RepoPath, Number);
  FReviewJob.OnDone := @ReviewJobDone;
  FReviewJob.Start;
end;

procedure TForm1.AbandonReviewJob;
begin
  if FReviewJob = nil then
    Exit;
  FReviewJob.Stop;
  FBlameZombies.Add(FReviewJob);
  FReviewJob := nil;
end;

procedure TForm1.ReviewJobDone(Sender: TObject);
var
  Job: TGittanReviewJob;
  Key: string;
begin
  Job := TGittanReviewJob(Sender);
  if Job <> FReviewJob then
    Exit;
  FReviewJob := nil;
  FBlameZombies.Add(Job);
  Application.QueueAsyncCall(@FreeBlameJobsAsync, 0);
  FReviewError := Job.Error;
  if Job.Error <> '' then
  begin
    UpdateStatus;
    Exit;
  end;
  Key := ThreadsKey(Job.Threads, Job.HeadOid);
  FThreads := Job.Threads;
  FThreadsNumber := Job.Number;
  FThreadsRepo := Job.RepoPath;
  if FThreadsHead <> Job.HeadOid then
    FMapDiffKey := '';
  FThreadsHead := Job.HeadOid;
  FSummary.SetNotes(Format(rsConversation, [Job.Number]), Job.Notes);
  UpdateStatus;
  if Key = FThreadsKey then
    Exit;
  FThreadsKey := Key;
  FileTree.Invalidate;
  RebuildIfChanges;
end;

{ Finds the diff line of every thread of the shown file in FThreadRows
  (threadOnTop for one that cannot be placed, threadElsewhere for one of
  another file). Called by BuildChangeView once the lines are numbered. }
procedure TForm1.PlaceThreads;
var
  ByNew, ByOld: TIntegerDynArray;
  i, t, Line: integer;
  Exact, LeftOk, Any: boolean;
  Err: string;
begin
  SetLength(FThreadRows, Length(FThreads));
  for t := 0 to High(FThreadRows) do
    FThreadRows[t] := threadElsewhere;
  if not FShowComments or (FView <> gvChanges) or (FThreadsNumber = 0) or
    (FCurrentPath = '') then
    Exit;
  Exact := ReviewExact;
  { A range other than the pull request's: the new side is some other
    commit. }
  if not Exact and FRepo.IsRange then
    Exit;
  Any := False;
  for t := 0 to High(FThreads) do
    if FThreads[t].Path = FCurrentPath then
    begin
      FThreadRows[t] := threadOnTop;
      Any := True;
    end;
  if not Any then
    Exit;
  if not Exact and (FMapDiffKey <> FThreadsHead + #0 + FCurrentPath) then
  begin
    FMapDiffKey := FThreadsHead + #0 + FCurrentPath;
    { The head may not be here (not fetched): the lines are taken as they
      are then. }
    if (FThreadsHead = '') or not RunGitIn(FRepo.Root, ['diff', '--no-color',
      '--no-ext-diff', '-U0', FThreadsHead, '--', FCurrentPath], FMapDiff, Err) then
      FMapDiff := '';
  end;
  SetLength(ByNew, Length(FNewNum) + 2);
  SetLength(ByOld, Length(FOldNum) + 2);
  for i := 0 to High(ByNew) do
    ByNew[i] := -1;
  for i := 0 to High(ByOld) do
    ByOld[i] := -1;
  for i := 0 to High(FNewNum) do
    if (FNewNum[i] > 0) and (FNewNum[i] <= High(ByNew)) then
      ByNew[FNewNum[i]] := i;
  for i := 0 to High(FOldNum) do
    if (FOldNum[i] > 0) and (FOldNum[i] <= High(ByOld)) then
      ByOld[FOldNum[i]] := i;
  LeftOk := Exact or ((FMergeBase <> '') and (FRepo.Base = FMergeBase) and
    not FRepo.WholeTree);
  for t := 0 to High(FThreads) do
  begin
    if (FThreadRows[t] <> threadOnTop) or (FThreads[t].Line <= 0) then
      Continue;
    Line := FThreads[t].Line;
    if FThreads[t].LeftSide then
    begin
      if LeftOk and (Line <= High(ByOld)) then
        FThreadRows[t] := ByOld[Line];
    end
    else
    begin
      if not Exact then
        Line := MapLine(FMapDiff, Line);
      if (Line > 0) and (Line <= High(ByNew)) then
        FThreadRows[t] := ByNew[Line];
    end;
  end;
end;

{ What keeps a thread's fold apart from its default: the address of its
  first comment. }
function TForm1.ThreadId(AThread: integer): string;
begin
  with FThreads[AThread] do
    if Comments[0].Url <> '' then
      Result := Comments[0].Url
    else
      Result := Path + #0 + IntToStr(OriginalLine) + #0 + Comments[0].Body;
end;

function TForm1.ThreadOpen(AThread: integer): boolean;
begin
  Result := not FThreads[AThread].Resolved and not FThreads[AThread].Outdated;
  if FThreadFlips.IndexOf(ThreadId(AThread)) >= 0 then
    Result := not Result;
end;

{ The fonts of a card: the interface font, scaled with the editor's
  zoom, for the text, and the editor's for code. }
procedure TForm1.ReviewFont(C: TCanvas; AKind: integer);
begin
  if AKind = rlCode then
  begin
    C.Font.Name := Edit.Font.Name;
    C.Font.Size := EditorFontSize(Edit);
    C.Font.Style := [];
  end
  else
  begin
    C.Font.Assign(FHeader.Font);
    if Edit.OptScaleFont > 0 then
      C.Font.Size := Max(6, FHeader.Font.Size * Edit.OptScaleFont div 100);
    if AKind = rlHeader then
      C.Font.Style := [fsBold]
    else
      C.Font.Style := [];
  end;
end;

function TForm1.ReviewLineHeight(AKind: integer): integer;
begin
  if AKind = rlRule then
    Exit(ReviewRuleHeight);
  ReviewFont(FReviewMeasure.Canvas, AKind);
  Result := FReviewMeasure.Canvas.TextHeight('Ag') + 4;
end;

{ AText cut to AWidth with an ellipsis, in C's font. }
function FitText(C: TCanvas; const AText: string; AWidth: integer): string;
var
  n: integer;
begin
  Result := AText;
  if C.TextWidth(Result) <= AWidth then
    Exit;
  n := UTF8Length(AText);
  while (n > 0) and (C.TextWidth(UTF8Copy(AText, 1, n) + '…') > AWidth) do
    Dec(n);
  Result := UTF8Copy(AText, 1, n) + '…';
end;

{ The width of a card in a gap AWidth wide. }
function ReviewCardWidth(AWidth: integer): integer;
begin
  Result := Max(120, Min(AWidth - 2 * ReviewMargin, ReviewMaxWidth));
end;

{ The lines of the card of AThread, AInner wide: the text in Strings,
  the kind in Objects. Text is wrapped at words; code (between ```
  fences) is not. }
procedure TForm1.ReviewLayout(AThread, AInner: integer; ALines: TStrings);
var
  C: TCanvas;
  Note, S, Head: string;
  Parts: TStringList;
  i, k: integer;
  InCode, Blank: boolean;

  procedure Add(const AText: string; AKind: integer);
  begin
    ALines.AddObject(AText, TObject(PtrInt(AKind)));
  end;

  { Breaks AText into lines no wider than AInner, at spaces, or inside a
    word longer than a line. }
  procedure Wrap(const AText: string; AKind: integer);
  var
    Words: TStringList;
    Line, Word, Part: string;
    w, n: integer;
  begin
    ReviewFont(C, AKind);
    if C.TextWidth(AText) <= AInner then
    begin
      Add(AText, AKind);
      Exit;
    end;
    Words := TStringList.Create;
    try
      Words.Delimiter := ' ';
      Words.StrictDelimiter := True;
      Words.DelimitedText := AText;
      Line := '';
      for w := 0 to Words.Count - 1 do
      begin
        Word := Words[w];
        if Line = '' then
          Part := Word
        else
          Part := Line + ' ' + Word;
        if C.TextWidth(Part) <= AInner then
        begin
          Line := Part;
          Continue;
        end;
        if Line <> '' then
          Add(Line, AKind);
        Line := Word;
        while (C.TextWidth(Line) > AInner) and (UTF8Length(Line) > 1) do
        begin
          n := UTF8Length(Line);
          while (n > 1) and (C.TextWidth(UTF8Copy(Line, 1, n)) > AInner) do
            Dec(n);
          Add(UTF8Copy(Line, 1, n), AKind);
          Line := UTF8Copy(Line, n + 1, MaxInt);
        end;
      end;
      if Line <> '' then
        Add(Line, AKind);
    finally
      Words.Free;
    end;
  end;

begin
  ALines.Clear;
  C := FReviewMeasure.Canvas;
  with FThreads[AThread] do
  begin
    if not ThreadOpen(AThread) then
    begin
      if Resolved then
        Note := rsReviewResolved
      else if Outdated then
        Note := rsReviewOutdated
      else
        Note := '';
      { The first line of text of the first comment. }
      S := '';
      Parts := TStringList.Create;
      try
        Parts.Text := Comments[0].Body;
        for i := 0 to Parts.Count - 1 do
          if (Trim(Parts[i]) <> '') and (Copy(Trim(Parts[i]), 1, 3) <> '```') then
          begin
            S := Trim(Parts[i]);
            Break;
          end;
      finally
        Parts.Free;
      end;
      Head := '▸ ';
      if Note <> '' then
        Head := Head + Note + ' · ';
      Head := Head + Comments[0].Author;
      if Length(Comments) > 1 then
        Head := Head + Format(rsReviewReplies, [Length(Comments) - 1]);
      Add(Head + ': ' + S, rlFolded);
      Exit;
    end;
    { What the place of the thread says, when there is something to say. }
    Note := '';
    if Resolved then
      Note := rsReviewResolved;
    if Outdated then
      Note := Note + IfThen(Note <> '', ' · ', '') + rsReviewOutdated;
    if OnFile then
      Note := Note + IfThen(Note <> '', ' · ', '') + rsReviewOnFile
    else if FThreadRows[AThread] = threadOnTop then
    begin
      if Line > 0 then
        k := Line
      else
        k := OriginalLine;
      if LeftSide then
        Note := Note + IfThen(Note <> '', ' · ', '') + Format(rsReviewRemovedLine, [k])
      else if k > 0 then
        Note := Note + IfThen(Note <> '', ' · ', '') + Format(rsReviewLine, [k]);
    end
    else if (StartLine > 0) and (StartLine < Line) then
      Note := Note + IfThen(Note <> '', ' · ', '') + Format(rsReviewLines, [StartLine, Line]);
    if Note <> '' then
      Add(Note, rlNote);
    for k := 0 to High(Comments) do
    begin
      if k > 0 then
        Add('', rlRule);
      Head := Comments[k].Author;
      S := ReviewAge(Comments[k].Created, LocalTimeToUniversal(Now));
      if S <> '' then
        Head := Head + ' · ' + S;
      Add(Head, rlHeader);
      Parts := TStringList.Create;
      try
        Parts.Text := Comments[k].Body;
        while (Parts.Count > 0) and (Trim(Parts[Parts.Count - 1]) = '') do
          Parts.Delete(Parts.Count - 1);
        InCode := False;
        Blank := False;
        for i := 0 to Parts.Count - 1 do
        begin
          S := Parts[i];
          if Copy(TrimLeft(S), 1, 3) = '```' then
          begin
            InCode := not InCode;
            if InCode and (Pos('suggestion', TrimLeft(S)) = 4) then
              Add(rsReviewSuggestion, rlNote);
            Continue;
          end;
          if InCode then
          begin
            Add(StringReplace(S, #9, '    ', [rfReplaceAll]), rlCode);
            Continue;
          end;
          { One blank line between paragraphs, none at the start. }
          if Trim(S) = '' then
          begin
            Blank := True;
            Continue;
          end;
          if Blank and (ALines.Count > 0) and (PtrInt(ALines.Objects[ALines.Count - 1]) <> rlHeader) then
            Add('', rlBody);
          Blank := False;
          Wrap(TrimRight(S), rlBody);
        end;
      finally
        Parts.Free;
      end;
    end;
  end;
end;

function TForm1.ReviewCardHeight(AThread, AWidth: integer): integer;
var
  Lines: TStringList;
  i: integer;
begin
  Lines := TStringList.Create;
  try
    ReviewLayout(AThread, ReviewCardWidth(AWidth) - 2 * ReviewPadX, Lines);
    Result := 2 * ReviewMargin + 2 * ReviewPadY;
    for i := 0 to Lines.Count - 1 do
      Inc(Result, ReviewLineHeight(PtrInt(Lines.Objects[i])));
  finally
    Lines.Free;
  end;
end;

{ The width a gap of AEd has: the one its last paint had, else the text
  area as the editor last laid it out. }
function TForm1.ReviewGapWidth(AEd: TATSynEdit): integer;
begin
  Result := FReviewWidths[Ord(AEd = FEditOld)];
  if Result <= 0 then
    Result := AEd.RectMain.Width;
  if Result <= 0 then
    Result := AEd.ClientWidth - 80;
end;

{ Puts a card under the row of every thread of the shown file. }
procedure TForm1.ApplyReviewGaps;
var
  t, r, Row, H: integer;
  Ed, Other: TATSynEdit;
  Side: boolean;

  function FindRow(const ARows: TGittanRows; ALine: integer): integer;
  var
    i: integer;
  begin
    Result := -1;
    if ALine >= 0 then
      for i := 0 to High(ARows) do
        if (ARows[i].Line = ALine) and not ARows[i].Hidden then
          Exit(i);
  end;

begin
  Edit.Gaps.Clear;
  FEditOld.Gaps.Clear;
  if (FView = gvChanges) and (Length(FThreadRows) = Length(FThreads)) then
  begin
    Side := Length(FRowsOld) > 0;
    for t := 0 to High(FThreads) do
    begin
      if FThreadRows[t] = threadElsewhere then
        Continue;
      Ed := Edit;
      if Side and FThreads[t].LeftSide and (FThreadRows[t] >= 0) then
      begin
        Ed := FEditOld;
        Row := FindRow(FRowsOld, FThreadRows[t]);
      end
      else
        Row := FindRow(FRows, FThreadRows[t]);
      H := ReviewCardHeight(t, ReviewGapWidth(Ed));
      Ed.Gaps.Add(Row, H, nil, nil, t);
      if Side then
      begin
        if Ed = Edit then
          Other := FEditOld
        else
          Other := Edit;
        Other.Gaps.Add(Row, H, nil, nil, -1);
      end;
    end;
  end;
  for r := 0 to 1 do
  begin
    if r = 0 then
      Ed := Edit
    else
      Ed := FEditOld;
    Ed.Update;
  end;
  Application.QueueAsyncCall(@RevealTopGapAsync, 0);
end;

{ The cards at the top of the file are a gap before the first line,
  which the editor shows only while it is scrolled up past that line
  (the position -1); putting the top line at 0, as every build does,
  leaves it out. A view at its top is moved up onto it, once the build's
  own scrolling is done. }
procedure TForm1.RevealTopGapAsync(Data: PtrInt);
var
  Info: TATEditorScrollInfo;
  Ed: TATSynEdit;
  r: integer;
begin
  if FView <> gvChanges then
    Exit;
  for r := 0 to 1 do
  begin
    if r = 0 then
      Ed := Edit
    else
      Ed := FEditOld;
    if not Ed.Visible or (Ed.Gaps.Find(-1, 0) < 0) then
      Continue;
    Info := Ed.ScrollVert;
    if (Info.NPos <> 0) or (Info.NPixelOffset <> 0) then
      Continue;
    Info.NPos := -1;
    Ed.ScrollVert := Info;
    Ed.Update;
  end;
  SyncOldSide;
end;

{ The editor paints a line's gutter over the gaps under it as well, and
  centers the number the change view puts there (gutter decor) in that
  height. Over the cards the gutter is painted plain again and the
  number put back next to its line. Called from OnDrawEditor. }
procedure TForm1.DrawGapGutter(AEd: TATSynEdit; C: TCanvas);
var
  Band, i, d, Line, Y, CharH, Below: integer;
  Decor: PATGutterDecorItem;
begin
  if (AEd.Gaps.Count = 0) or (FView <> gvChanges) then
    Exit;
  Band := AEd.Gutter.FindIndexByTag(ATEditorOptions.GutterTagBookmarks);
  CharH := AEd.TextCharSize.Y;
  C.Font.Name := AEd.Font.Name;
  C.Font.Size := EditorFontSize(AEd);
  C.Font.Style := [];
  C.Clipping := True;
  C.ClipRect := Rect(0, AEd.RectMain.Top, AEd.RectMain.Left, AEd.RectMain.Bottom);
  try
    i := 0;
    while i < AEd.Gaps.Count do
    begin
      Line := AEd.Gaps[i].LineIndex;
      { The gaps of one line, in a row. }
      Below := 0;
      while (i < AEd.Gaps.Count) and (AEd.Gaps[i].LineIndex = Line) do
      begin
        Inc(Below, AEd.Gaps[i].Size);
        Inc(i);
      end;
      if (Line < 0) or not AEd.Strings.IsIndexValid(Line) or AEd.IsLineFolded(Line) then
        Continue;
      Y := AEd.CaretPosToClientPos(Point(0, Line)).Y;
      if (Y + CharH + Below < AEd.RectMain.Top) or (Y >= AEd.RectMain.Bottom) then
        Continue;
      C.Brush.Style := bsSolid;
      C.Brush.Color := AEd.Colors.GutterBG;
      C.FillRect(Rect(0, Y + CharH, AEd.RectMain.Left, Y + CharH + Below));
      if Band < 0 then
        Continue;
      for d := 0 to AEd.GutterDecor.Count - 1 do
      begin
        Decor := AEd.GutterDecor.ItemPtr(d);
        if Decor^.Data.LineNum <> Line then
          Continue;
        C.Brush.Style := bsSolid;
        C.FillRect(Rect(AEd.Gutter[Band].Left, Y, AEd.Gutter[Band].Right, Y + CharH));
        C.Brush.Style := bsClear;
        C.Font.Color := Decor^.Data.TextColor;
        C.TextOut(AEd.Gutter[Band].Right - C.TextWidth(Decor^.Data.TextAll),
          Y + (CharH - C.TextHeight(Decor^.Data.TextAll)) div 2, Decor^.Data.TextAll);
        Break;
      end;
    end;
  finally
    C.Clipping := False;
    C.Brush.Style := bsSolid;
  end;
end;

procedure TForm1.ReviewRelayoutAsync(Data: PtrInt);
begin
  if FView <> gvChanges then
    Exit;
  ApplyReviewGaps;
  SyncOldSide;
end;

procedure TForm1.EditDrawGap(Sender: TObject; C: TCanvas; const ARect: TRect;
  AGap: TATGapItem);
var
  Ed: TATSynEdit;
  Lines: TStringList;
  Card: TRect;
  Fill, Border, Dim, Accent, CodeFill: TColor;
  i, y, H, Kind, W, Side, Right: integer;
  First: boolean;
begin
  Ed := TATSynEdit(Sender);
  C.Brush.Style := bsSolid;
  C.Brush.Color := Ed.Colors.TextBG;
  C.FillRect(ARect);
  if (AGap.Tag < 0) or (AGap.Tag > High(FThreads)) then
    Exit;
  { The card was laid out for another width: lay out again once the
    paint is done. }
  Side := Ord(Ed = FEditOld);
  if FReviewWidths[Side] <> ARect.Width then
  begin
    FReviewWidths[Side] := ARect.Width;
    Application.QueueAsyncCall(@ReviewRelayoutAsync, 0);
  end;
  if FDark then
  begin
    Fill := RGBToColor(37, 37, 38);
    Border := RGBToColor(62, 62, 62);
    Dim := RGBToColor(150, 150, 150);
    CodeFill := RGBToColor(30, 30, 31);
  end
  else
  begin
    Fill := RGBToColor(246, 248, 250);
    Border := RGBToColor(208, 215, 222);
    Dim := RGBToColor(110, 110, 110);
    CodeFill := RGBToColor(234, 238, 242);
  end;
  if ThreadOpen(AGap.Tag) and not FThreads[AGap.Tag].Resolved and
    not FThreads[AGap.Tag].Outdated then
    Accent := FLinkColor
  else
    Accent := Border;
  W := ReviewCardWidth(ARect.Width);
  Card := Rect(ARect.Left + ReviewMargin, ARect.Top + ReviewMargin,
    ARect.Left + ReviewMargin + W, ARect.Bottom - ReviewMargin);
  Lines := TStringList.Create;
  C.Clipping := True;
  C.ClipRect := ARect;
  try
    C.Pen.Width := 1;
    C.Pen.Color := Border;
    C.Brush.Color := Fill;
    C.RoundRect(Card.Left, Card.Top, Card.Right, Card.Bottom, 10, 10);
    C.Brush.Color := Accent;
    C.FillRect(Rect(Card.Left + 1, Card.Top + 4, Card.Left + 4, Card.Bottom - 4));
    ReviewLayout(AGap.Tag, W - 2 * ReviewPadX, Lines);
    y := Card.Top + ReviewPadY;
    First := True;
    for i := 0 to Lines.Count - 1 do
    begin
      Kind := PtrInt(Lines.Objects[i]);
      H := ReviewLineHeight(Kind);
      ReviewFont(C, Kind);
      case Kind of
        rlRule:
          begin
            C.Pen.Color := Border;
            C.Line(Card.Left + ReviewPadX, y + H div 2, Card.Right - ReviewPadX, y + H div 2);
          end;
        rlCode:
          begin
            C.Brush.Style := bsSolid;
            C.Brush.Color := CodeFill;
            C.FillRect(Rect(Card.Left + ReviewPadX - 4, y, Card.Right - ReviewPadX + 4, y + H));
          end;
      end;
      C.Brush.Style := bsClear;
      if Kind in [rlNote, rlFolded] then
        C.Font.Color := Dim
      else
        C.Font.Color := Ed.Colors.TextFont;
      Right := Card.Right - ReviewPadX;
      if First and (Kind in [rlHeader, rlFolded]) then
      begin
        { The link takes the right end of the first header. }
        ReviewFont(C, rlNote);
        Right := Right - C.TextWidth(rsReviewLink) - ReviewPadX;
        ReviewFont(C, Kind);
        if Kind = rlFolded then
          C.Font.Color := Dim
        else
          C.Font.Color := Ed.Colors.TextFont;
      end;
      if Kind <> rlRule then
        C.TextRect(Rect(Card.Left + ReviewPadX, y, Right, y + H),
          Card.Left + ReviewPadX, y + 2, FitText(C, Lines[i], Right - Card.Left - ReviewPadX));
      if First and (Kind in [rlHeader, rlFolded]) then
      begin
        First := False;
        ReviewFont(C, rlNote);
        C.Font.Color := FLinkColor;
        C.Brush.Color := Fill;
        C.Brush.Style := bsSolid;
        C.TextOut(Card.Right - ReviewPadX - C.TextWidth(rsReviewLink), y + 2, rsReviewLink);
        C.Brush.Style := bsClear;
      end;
      Inc(y, H);
    end;
  finally
    C.Clipping := False;
    C.Brush.Style := bsSolid;
    Lines.Free;
  end;
end;

{ A click on "GitHub ↗" opens the thread on GitHub; anywhere else on the
  card it folds or unfolds. APos is in the gap. }
procedure TForm1.EditClickGap(Sender: TObject; AGapItem: TATGapItem; APos: TPoint);
var
  Ed: TATSynEdit;
  Lines: TStringList;
  W, y, i, Kind, H, LinkLeft: integer;
begin
  if (AGapItem = nil) or (AGapItem.Tag < 0) or (AGapItem.Tag > High(FThreads)) then
    Exit;
  Ed := TATSynEdit(Sender);
  W := ReviewCardWidth(ReviewGapWidth(Ed));
  Lines := TStringList.Create;
  try
    ReviewLayout(AGapItem.Tag, W - 2 * ReviewPadX, Lines);
    y := ReviewMargin + ReviewPadY;
    for i := 0 to Lines.Count - 1 do
    begin
      Kind := PtrInt(Lines.Objects[i]);
      H := ReviewLineHeight(Kind);
      if Kind in [rlHeader, rlFolded] then
      begin
        ReviewFont(FReviewMeasure.Canvas, rlNote);
        LinkLeft := ReviewMargin + W - ReviewPadX -
          FReviewMeasure.Canvas.TextWidth(rsReviewLink);
        if (APos.Y >= y) and (APos.Y < y + H) and (APos.X >= LinkLeft) and
          (APos.X <= ReviewMargin + W - ReviewPadX) then
        begin
          if FThreads[AGapItem.Tag].Comments[0].Url <> '' then
            OpenURL(FThreads[AGapItem.Tag].Comments[0].Url);
          Exit;
        end;
        Break;
      end;
      Inc(y, H);
    end;
  finally
    Lines.Free;
  end;
  if APos.X > ReviewMargin + W then
    Exit;
  { Folded when the button is up (see EditMouseUp): a card that changed
    height under a button still down would have the editor select text
    from where the button went down to where it came up. }
  FGapToggle := ThreadId(AGapItem.Tag);
end;

{ The fold asked for by a click on a card, when the button came up. }
procedure TForm1.ToggleThreadNow;
var
  i: integer;
begin
  i := FThreadFlips.IndexOf(FGapToggle);
  if i >= 0 then
    FThreadFlips.Delete(i)
  else
    FThreadFlips.Add(FGapToggle);
  FGapToggle := '';
  Application.QueueAsyncCall(@ReviewRelayoutAsync, 0);
end;

{ The threads of APath the tree marks it with: AOpen neither resolved
  nor outdated, AAll every one; none while the change view shows no
  comments (see PlaceThreads). }
procedure TForm1.FileThreads(const APath: string; out AOpen, AAll: integer);
var
  t: integer;
begin
  AOpen := 0;
  AAll := 0;
  if not FShowComments or (FThreadsNumber = 0) or (FRepo.IsRange and not ReviewExact) then
    Exit;
  for t := 0 to High(FThreads) do
    if FThreads[t].Path = APath then
    begin
      Inc(AAll);
      if not FThreads[t].Resolved and not FThreads[t].Outdated then
        Inc(AOpen);
    end;
end;

{ What the tree's hint of APath adds about its threads. }
function TForm1.FileThreadsHint(const APath: string): string;
var
  Open, All: integer;
begin
  FileThreads(APath, Open, All);
  if Open = 1 then
    Result := rsTreeThreadOpen
  else if Open > 1 then
    Result := Format(rsTreeThreadsOpen, [Open])
  else if All > 0 then
    Result := rsTreeThreadsDone
  else
    Result := '';
end;

{ A file with review comments gets a speech bubble at the right end of
  its row, with the number of open threads, gray when every thread is
  resolved or outdated; after the name when that reaches further. The
  theme (tvoThemedDraw) marks a selected row behind its name alone, so
  the bubble keeps its colors there and nothing is filled under it. }
procedure TForm1.FileTreeAdvancedCustomDrawItem(Sender: TCustomTreeView;
  Node: TTreeNode; State: TCustomDrawState; Stage: TCustomDrawStage;
  var PaintImages, DefaultDraw: boolean);
var
  R: TRect;
  C: TCanvas;
  Open, All, W, X: integer;
  Num: string;
  Tint: TColor;
begin
  DefaultDraw := True;
  if (Stage <> cdPostPaint) or (Node.Data = nil) then
    Exit;
  FileThreads(Node.GetTextPath, Open, All);
  if All = 0 then
    Exit;
  R := Node.DisplayRect(False);
  C := Sender.Canvas;
  if Open > 0 then
    Tint := FLinkColor
  else if FDark then
    Tint := RGBToColor(150, 150, 150)
  else
    Tint := RGBToColor(110, 110, 110);
  Num := '';
  if Open > 0 then
    Num := IntToStr(Open);
  { The icon takes a square 4 px smaller than the row (see DrawStatusIcon). }
  W := R.Height - 4;
  if Num <> '' then
    Inc(W, 3 + C.TextWidth(Num));
  X := Max(R.Right - 8 - W, Node.DisplayTextRight + 8);
  DrawStatusIcon(C, HintComment, X, R.Top, R.Height, Tint);
  if Num <> '' then
  begin
    C.Brush.Style := bsClear;
    C.Font.Color := Tint;
    C.TextOut(X + R.Height - 1, R.Top + (R.Height - C.TextHeight(Num)) div 2, Num);
    C.Brush.Style := bsSolid;
  end;
end;

{ The line the status bar's pull request hint adds: how many threads of
  it are open. }
function TForm1.ReviewHint(ANumber: integer): string;
var
  Open: integer;
begin
  Result := '';
  if not FShowComments then
    Exit;
  if FReviewError <> '' then
    Exit(LineEnding + rsReviewFailed);
  if FThreadsNumber <> ANumber then
    Exit;
  Open := OpenThreads(FThreads);
  if Open = 1 then
    Result := LineEnding + HintComment + ' ' + rsReviewOpenOne
  else if Open > 1 then
    Result := LineEnding + HintComment + ' ' + Format(rsReviewOpen, [Open]);
end;
