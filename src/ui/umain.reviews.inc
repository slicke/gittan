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
  thread in FShown; in the side-by-side view the other side gets an
  empty gap of the same height (Tag -1), so the rows stay in step. A
  resolved or outdated thread starts folded to one line; a click on a
  card folds or unfolds it, a click on "GitHub ↗" opens it in the
  browser.

  The view shows FShown: the pull request's threads while they apply
  (PullThreadsShown) and the findings of an AI review (umain.ai.inc)
  while the comparison is the one they were made for. A finding is on
  the view's own lines, so it is placed as it is, without the mapping;
  its card has the agent's color and no link. }

const
  { The kinds of the lines of a card, in the Objects of its layout. }
  rlNote = 1;
  rlHeader = 2;
  rlBody = 3;
  rlCode = 4;
  rlRule = 5;
  rlFolded = 6;
  { Markdown, as LazInk's inline markup, wrapped as it is drawn. }
  rlMarkup = 7;
  { The summary of a <details> block, as markup, after "▸" or "▾". }
  rlDetails = 8;
  { Room around a card, inside it, and the most it widens to. }
  ReviewMargin = 6;
  ReviewPadX = 12;
  ReviewPadY = 7;
  ReviewMaxWidth = 860;
  ReviewRuleHeight = 11;
  { How far the text in a <details> block is indented, per level. }
  ReviewIndent = 14;
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
procedure TRepoFrame.SummaryOpenUrl(Sender: TObject; const AUrl: string);
begin
  OpenCommentLink(AUrl);
end;

{ Whether APath (with /) is a file of the work tree, for LinkFilePaths
  and the links of a comment, which anyone can write: a path that ..
  takes out of the root is none (an absolute one is read under it). }
function TRepoFrame.RepoFileExists(const APath: string): boolean;
var
  Root, Full: string;
begin
  if (FRepo.Root = '') or (APath = '') then
    Exit(False);
  Root := IncludeTrailingPathDelimiter(ExpandFileName(FRepo.Root));
  Full := ExpandFileName(Root + SetDirSeparators(APath));
  Result := (Copy(Full, 1, Length(Root)) = Root) and FileExists(Full) and
    not DirectoryExists(Full);
end;

{ A link in a comment: a file of the repository (LinkFilePaths, or the
  forge's address of one of a repository a remote holds) is shown at its
  line, anything else goes to the browser. }
procedure TRepoFrame.OpenCommentLink(const AUrl: string);
var
  Repo, Path: string;
  Line: integer;
begin
  { Gittan's own link, which LinkFilePaths gives a file that is there,
    or one a comment wrote in its place: a file of the work tree only,
    and never the browser. }
  if FileOfLink(AUrl, Path, Line) then
  begin
    if RepoFileExists(Path) then
      ShowFileLine(Path, Line);
  end
  else if Assigned(FForge) and FForge.FileOfWebUrl(AUrl, Repo, Path, Line) and
    FRepo.HasRemoteFor(Repo) and RepoFileExists(Path) then
    ShowFileLine(Path, Line)
  else
    OpenURL(AUrl);
end;

{ Shows the file APath of the repository (ShowRepoFile) with the caret
  on line ALine (0 for none) of it, in the middle of the view: in the
  change view the row of the new
  side that holds it, the gap that hides it opened. }
procedure TRepoFrame.ShowFileLine(const APath: string; ALine: integer);

  function RowOf(ALine: integer): integer;
  var
    i: integer;
  begin
    for i := 0 to Edit.Strings.Count - 1 do
      if FileLineOfRow(i) = ALine then
        Exit(i);
    Result := -1;
  end;

var
  Row, i: integer;
begin
  if APath <> ShownRelPath then
    ShowRepoFile(APath);
  if (ALine <= 0) or not Edit.Visible or (ShownRelPath <> APath) then
    Exit;
  Row := RowOf(ALine);
  if Row < 0 then
    Exit;
  if (FView = gvChanges) and Edit.IsLineFolded(Row) and (Row <= High(FRows)) then
    for i := 0 to High(FRows) do
      if (FRows[i].Line = rowGap) and (FRows[i].GapFrom <= FRows[Row].Line) and
        (FRows[Row].Line <= FRows[i].GapTo) then
      begin
        ExpandGap(FRows[i].GapFrom, FRows[i].GapTo);
        Row := RowOf(ALine);
        if Row < 0 then
          Exit;
        Break;
      end;
  { As a symbol picked in another file: the wrap info of the text just
    loaded, and no line top kept from showing it. The editor centers a
    row only when it is out of sight (an indent of 100 or more, negative
    to count from the top either way), so the view starts at the top: a
    row in the first screen stays where it is. }
  Edit.UpdateWrapInfo(True);
  Edit.LineTopTodo := 0;
  Edit.LineTop := 0;
  Edit.DoGotoPos(Point(0, Row), Point(-1, -1), 10, -100, True, FoldAction);
  { An editor not painted since it was shown (no bottom line yet) only
    takes the caret from DoGotoPos, neither scrolled nor told of the
    move: the top is set from its height, and the caret's position
    passed on to the header and the status bar. }
  if Edit.LineBottom <= 0 then
  begin
    Edit.LineTop := Max(0, Row - Edit.GetVisibleLines div 2);
    EditChangeCaretPos(Edit);
  end;
  if Edit.CanFocus then
    Edit.SetFocus;
end;

procedure TRepoFrame.MenuReviewCommentsClick(Sender: TObject);
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
function TRepoFrame.ReviewTarget(out ANumber: integer; out ARepoPath: string): boolean;
var
  i: integer;
begin
  ANumber := 0;
  ARepoPath := '';
  if not FShowComments or not Assigned(FForge) or (FRepo.Root = '') then
    Exit(False);
  if (FPullRange <> '') and (FRepo.Base = FPullRange) and FRepo.IsRange then
  begin
    ANumber := FPullNumber;
    for i := 0 to High(FPulls) do
      if FPulls[i].Number = FPullNumber then
        ARepoPath := FPulls[i].Repo;
    if (ARepoPath = '') and FHasPull and (FPull.Number = FPullNumber) then
      ARepoPath := FPull.Repo;
  end
  else if FHasPull and not FRepo.IsRange then
  begin
    ANumber := FPull.Number;
    ARepoPath := FPull.Repo;
  end;
  Result := (ANumber > 0) and (ARepoPath <> '');
end;

{ Whether the view is the pull request's own diff, where its lines are
  the view's lines. }
function TRepoFrame.ReviewExact: boolean;
begin
  Result := (FPullRange <> '') and (FRepo.Base = FPullRange) and FRepo.IsRange and
    (FThreadsNumber = FPullNumber);
end;

procedure TRepoFrame.ClearReviews;
begin
  FThreads := nil;
  FThreadRows := nil;
  FThreadsNumber := 0;
  FThreadsRepo := '';
  FThreadsHead := '';
  FThreadsKey := '';
  FReviewError := '';
  FMapDiffKey := '';
  FReviewSegments.Clear;
  FSummary.SetNotes('', nil);
  CollectShownThreads;
  FileTree.Invalidate;
end;

{ Fetches the threads of the pull request ReviewTarget names when they
  are not the ones held, or again with AForce (a poll). Threads of
  another pull request are dropped at once. }
procedure TRepoFrame.StartReviewJob(AForce: boolean);
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
  FReviewJob := FForge.ReviewJob(FRepo.Root, RepoPath, Number);
  FReviewJob.OnDone := @ReviewJobDone;
  FReviewJob.Start;
end;

procedure TRepoFrame.AbandonReviewJob;
begin
  if FReviewJob = nil then
    Exit;
  FReviewJob.Stop;
  FBlameZombies.Add(FReviewJob);
  FReviewJob := nil;
end;

procedure TRepoFrame.ReviewJobDone(Sender: TObject);
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
  { The bodies of the threads gone are dropped with the rest. }
  FReviewSegments.Clear;
  CollectShownThreads;
  FileTree.Invalidate;
  RebuildIfChanges;
end;

{ Finds the diff line of every thread of the shown file in FThreadRows
  (threadOnTop for one that cannot be placed, threadElsewhere for one of
  another file). Called by BuildChangeView once the lines are numbered. }
procedure TRepoFrame.PlaceThreads;
var
  ByNew, ByOld: TIntegerDynArray;
  i, t, Line: integer;
  Exact, LeftOk, Any, AnyPull: boolean;
  Err: string;
begin
  CollectShownThreads;
  SetLength(FThreadRows, Length(FShown));
  for t := 0 to High(FThreadRows) do
    FThreadRows[t] := threadElsewhere;
  if (FView <> gvChanges) or (FCurrentPath = '') then
    Exit;
  Exact := ReviewExact;
  Any := False;
  AnyPull := False;
  for t := 0 to High(FShown) do
    if FShown[t].Path = FCurrentPath then
    begin
      FThreadRows[t] := threadOnTop;
      Any := True;
      if FShown[t].Agent = '' then
        AnyPull := True;
    end;
  if not Any then
    Exit;
  if AnyPull and not Exact and (FMapDiffKey <> FThreadsHead + #0 + FCurrentPath) then
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
  for t := 0 to High(FShown) do
  begin
    if (FThreadRows[t] <> threadOnTop) or (FShown[t].Line <= 0) then
      Continue;
    Line := FShown[t].Line;
    if FShown[t].LeftSide then
    begin
      { A finding's old side is the view's own. }
      if (LeftOk or (FShown[t].Agent <> '')) and (Line <= High(ByOld)) then
        FThreadRows[t] := ByOld[Line];
    end
    else
    begin
      if not Exact and (FShown[t].Agent = '') then
        Line := MapLine(FMapDiff, Line);
      if (Line > 0) and (Line <= High(ByNew)) then
        FThreadRows[t] := ByNew[Line];
    end;
  end;
end;

{ Whether the pull request's threads apply to what the view shows: the
  comments are on, and the new side is the work tree or the pull
  request's own head. }
function TRepoFrame.PullThreadsShown: boolean;
begin
  Result := FShowComments and (FThreadsNumber <> 0) and (ReviewExact or
    not FRepo.IsRange);
end;

{ FShown: the pull request's threads while they apply, then the AI
  review's findings while the comparison is the one they were made for. }
procedure TRepoFrame.CollectShownThreads;
begin
  FShown := nil;
  if PullThreadsShown then
    FShown := Copy(FThreads);
  if (Length(FAIThreads) > 0) and (FAIThreadsKey = AIReviewKey) then
    FShown := Concat(FShown, FAIThreads);
end;

{ What keeps a thread's fold apart from its default: the address of its
  first comment. }
function TRepoFrame.ThreadId(AThread: integer): string;
begin
  with FShown[AThread] do
    if Comments[0].Url <> '' then
      Result := Comments[0].Url
    else
      Result := Path + #0 + IntToStr(OriginalLine) + #0 + Comments[0].Body;
end;

function TRepoFrame.ThreadOpen(AThread: integer): boolean;
begin
  Result := not FShown[AThread].Resolved and not FShown[AThread].Outdated;
  if FThreadFlips.IndexOf(ThreadId(AThread)) >= 0 then
    Result := not Result;
end;

{ How much a finding weighs, as its card says it; empty for a thread of
  GitHub's, which has none, and a word the agent made up is shown as it
  came. }
function SeverityLabel(const ASeverity: string): string;
begin
  if ASeverity = 'bug' then
    Result := rsSeverityBug
  else if ASeverity = 'risk' then
    Result := rsSeverityRisk
  else if ASeverity = 'question' then
    Result := rsSeverityQuestion
  else
    Result := ASeverity;
end;

{ Who wrote comment AComment of AThread as its card names them: an AI
  agent with a sparkle before its name. }
function TRepoFrame.ThreadAuthor(AThread, AComment: integer): string;
begin
  Result := FShown[AThread].Comments[AComment].Author;
  if FShown[AThread].Agent <> '' then
    Result := '✦ ' + Result;
end;

{ The stripe of an open finding's card, apart from GitHub's link color:
  a violet that reads on either background. }
function TRepoFrame.AgentColor: TColor;
begin
  if FDark then
    Result := RGBToColor(163, 113, 247)
  else
    Result := RGBToColor(130, 80, 223);
end;

{ The fonts of a card: the interface font, scaled with the editor's
  zoom, for the text, and the editor's for code. }
procedure TRepoFrame.ReviewFont(C: TCanvas; AKind: integer);
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

function TRepoFrame.ReviewLineHeight(AKind: integer): integer;
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

{ What a line of a card's layout has in its Objects: its kind, how
  deep in <details> blocks it is, the block it is the summary of (its
  part in CommentParts, -1 for none) and the comment it is in. }
function ReviewRow(AKind, ADepth, ADetail, AComment: integer): TObject;
begin
  Result := TObject(PtrInt(AKind or (Min(ADepth, 15) shl 4) or ((ADetail + 1) shl 8) or
    (AComment shl 20)));
end;

function RowKind(AObject: TObject): integer;
begin
  Result := PtrUInt(AObject) and $F;
end;

function RowDepth(AObject: TObject): integer;
begin
  Result := (PtrUInt(AObject) shr 4) and $F;
end;

function RowDetail(AObject: TObject): integer;
begin
  Result := ((PtrUInt(AObject) shr 8) and $FFF) - 1;
end;

function RowComment(AObject: TObject): integer;
begin
  Result := (PtrUInt(AObject) shr 20) and $FFF;
end;

{ The key in FThreadFlips of <details> block ADetail of comment AComment
  of AThread: there when the block is open. }
function TRepoFrame.DetailsKey(AThread, AComment, ADetail: integer): string;
begin
  Result := ThreadId(AThread) + '#' + IntToStr(AComment) + '#' + IntToStr(ADetail);
end;

{ The parts of a comment's body as its card shows them, kept by the body
  (FReviewSegments, emptied when the threads or the work tree change,
  since the paths it links are the files there), since a card is laid
  out at every paint, with their
  depth in <details> blocks in the Objects (ReviewRow, comment 0): the
  summary of a block as rlDetails, the text between fences as one
  rlMarkup each (CommentParts, then LazInk's inline markup, with only
  the inline HTML it trusts), a fence's lines as rlCode, and the label
  of a suggestion as rlNote before its code. }
function TRepoFrame.ReviewSegments(const ABody: string): TStrings;
var
  Parts: TGittanCommentParts;
  Lines: TStringList;
  Prose: string;
  k, i, Depth: integer;
  InCode: boolean;

  procedure FlushProse;
  begin
    if Trim(Prose) <> '' then
      Result.AddObject(MarkdownToInk(LinkFilePaths(Prose, @RepoFileExists), [imoInlineHTML]),
        ReviewRow(rlMarkup, Depth, -1, 0));
    Prose := '';
  end;

begin
  Result := TStrings(FReviewSegments.Items[ABody]);
  if Result <> nil then
    Exit;
  Result := TStringList.Create;
  FReviewSegments.Add(ABody, Result);
  Parts := CommentParts(ABody);
  Lines := TStringList.Create;
  try
    for k := 0 to High(Parts) do
    begin
      Depth := Parts[k].Depth;
      if Parts[k].Kind = cpDetails then
      begin
        Result.AddObject(MarkdownToInk(Parts[k].Text, [imoInlineHTML]),
          ReviewRow(rlDetails, Depth, k, 0));
        Continue;
      end;
      Lines.Text := Parts[k].Text;
      Prose := '';
      InCode := False;
      for i := 0 to Lines.Count - 1 do
      begin
        if Copy(TrimLeft(Lines[i]), 1, 3) = '```' then
        begin
          InCode := not InCode;
          if InCode then
          begin
            FlushProse;
            if Pos('suggestion', TrimLeft(Lines[i])) = 4 then
              Result.AddObject(rsReviewSuggestion, ReviewRow(rlNote, Depth, -1, 0));
          end;
          Continue;
        end;
        if InCode then
          Result.AddObject(StringReplace(Lines[i], #9, '    ', [rfReplaceAll]),
            ReviewRow(rlCode, Depth, -1, 0))
        else
          Prose := Prose + Lines[i] + LineEnding;
      end;
      FlushProse;
    end;
  finally
    Lines.Free;
  end;
end;

{ How LazInk draws the text of a card: links in the link color. }
function TRepoFrame.ReviewInkOptions: THTMLOptions;
begin
  Result := DefaultHTMLOptions;
  Result.LinkColor := FLinkColor;
end;

{ The height of line I of a card laid out AInner wide: a kind's line
  height, or the height Markdown takes wrapped at that width less its
  indent. }
function TRepoFrame.ReviewRowHeight(ALines: TStrings; I, AInner: integer): integer;
var
  C: TCanvas;
begin
  if not (RowKind(ALines.Objects[I]) in [rlMarkup, rlDetails]) then
    Exit(ReviewLineHeight(RowKind(ALines.Objects[I])));
  C := FReviewMeasure.Canvas;
  ReviewFont(C, rlBody);
  Result := HTMLTextExtentOpt(C, Rect(0, 0, Max(40, AInner - RowDepth(ALines.Objects[I]) * ReviewIndent),
    100000), [], ALines[I], ReviewInkOptions, FReviewInk).cy + 4;
end;

{ The lines of the card of AThread, AInner wide: the text in Strings,
  the kind and the rest in Objects (ReviewRow). Headers and notes are
  wrapped at words; the Markdown of a comment is one rlMarkup that
  LazInk wraps; code (between ``` fences) is not wrapped. A <details>
  block is its summary after "▸", and with "▾" the lines in it too
  when it is open (DetailsKey in FThreadFlips). }
procedure TRepoFrame.ReviewLayout(AThread, AInner: integer; ALines: TStrings);
var
  C: TCanvas;
  Note, S, Head: string;
  Parts: TStringList;
  Segs: TStrings;
  i, k, Depth, HideBelow: integer;

  procedure Add(const AText: string; AKind: integer);
  begin
    ALines.AddObject(AText, ReviewRow(AKind, 0, -1, 0));
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
  with FShown[AThread] do
  begin
    if not ThreadOpen(AThread) then
    begin
      if Resolved then
        Note := rsReviewResolved
      else if Outdated then
        Note := rsReviewOutdated
      else
        Note := '';
      { The first line of text of the first comment, without its
        markup. }
      S := '';
      Parts := TStringList.Create;
      try
        Parts.Text := CommentMarkdown(Comments[0].Body);
        for i := 0 to Parts.Count - 1 do
          if (Trim(Parts[i]) <> '') and (Copy(Trim(Parts[i]), 1, 3) <> '```') then
          begin
            S := Trim(HTMLPlainText(MarkdownToInk(Parts[i], [imoInlineHTML])));
            Break;
          end;
      finally
        Parts.Free;
      end;
      Head := '▸ ';
      if Note <> '' then
        Head := Head + Note + ' · ';
      Head := Head + ThreadAuthor(AThread, 0);
      if Length(Comments) > 1 then
        Head := Head + Format(rsReviewReplies, [Length(Comments) - 1]);
      Add(Head + ': ' + S, rlFolded);
      Exit;
    end;
    { What the place of the thread says, when there is something to say:
      for a finding, first how much it weighs. }
    Note := SeverityLabel(Severity);
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
      Head := ThreadAuthor(AThread, k);
      S := ReviewAge(Comments[k].Created, LocalTimeToUniversal(Now));
      if S <> '' then
        Head := Head + ' · ' + S;
      Add(Head, rlHeader);
      Segs := ReviewSegments(Comments[k].Body);
      { The lines deeper than a closed block are left out. }
      HideBelow := MaxInt;
      for i := 0 to Segs.Count - 1 do
      begin
        Depth := RowDepth(Segs.Objects[i]);
        if Depth > HideBelow then
          Continue;
        HideBelow := MaxInt;
        S := Segs[i];
        if RowKind(Segs.Objects[i]) = rlDetails then
        begin
          if FThreadFlips.IndexOf(DetailsKey(AThread, k, RowDetail(Segs.Objects[i]))) >= 0 then
            S := '▾ ' + S
          else
          begin
            S := '▸ ' + S;
            HideBelow := Depth;
          end;
        end;
        ALines.AddObject(S, ReviewRow(RowKind(Segs.Objects[i]), Depth,
          RowDetail(Segs.Objects[i]), k));
      end;
    end;
  end;
end;

function TRepoFrame.ReviewCardHeight(AThread, AWidth: integer): integer;
var
  Lines: TStringList;
  i: integer;
begin
  Lines := TStringList.Create;
  try
    ReviewLayout(AThread, ReviewCardWidth(AWidth) - 2 * ReviewPadX, Lines);
    Result := 2 * ReviewMargin + 2 * ReviewPadY;
    for i := 0 to Lines.Count - 1 do
      Inc(Result, ReviewRowHeight(Lines, i, ReviewCardWidth(AWidth) - 2 * ReviewPadX));
  finally
    Lines.Free;
  end;
end;

{ The width a gap of AEd has: the one its last paint had, else the text
  area as the editor last laid it out. }
function TRepoFrame.ReviewGapWidth(AEd: TATSynEdit): integer;
begin
  Result := FReviewWidths[Ord(AEd = FEditOld)];
  if Result <= 0 then
    Result := AEd.RectMain.Width;
  if Result <= 0 then
    Result := AEd.ClientWidth - 80;
end;

{ Puts a card under the row of every thread of the shown file. }
procedure TRepoFrame.ApplyReviewGaps;
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
  if (FView = gvChanges) and (Length(FThreadRows) = Length(FShown)) then
  begin
    Side := Length(FRowsOld) > 0;
    for t := 0 to High(FShown) do
    begin
      if FThreadRows[t] = threadElsewhere then
        Continue;
      Ed := Edit;
      if Side and FShown[t].LeftSide and (FThreadRows[t] >= 0) then
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
procedure TRepoFrame.RevealTopGapAsync(Data: PtrInt);
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
  number put back next to its line. The block staples, the lines the
  editor draws down a block of code after the text, run through the
  cards under its lines, so the cards are painted again over them.
  Called from OnDrawEditor, which comes after both. }
procedure TRepoFrame.DrawGapGutter(AEd: TATSynEdit; C: TCanvas);
var
  Band, i, g, First, d, Line, Y, CharH, Below, GapTop: integer;
  Decor: PATGutterDecorItem;
begin
  if (AEd.Gaps.Count = 0) or (FView <> gvChanges) then
    Exit;
  Band := AEd.Gutter.FindIndexByTag(ATEditorOptions.GutterTagBookmarks);
  CharH := AEd.TextCharSize.Y;
  try
    i := 0;
    while i < AEd.Gaps.Count do
    begin
      Line := AEd.Gaps[i].LineIndex;
      { The gaps of one line, in a row. }
      First := i;
      Below := 0;
      while (i < AEd.Gaps.Count) and (AEd.Gaps[i].LineIndex = Line) do
      begin
        Inc(Below, AEd.Gaps[i].Size);
        Inc(i);
      end;
      if Line < 0 then
      begin
        { The gaps before the first line end where it starts. }
        if AEd.Strings.Count = 0 then
          Continue;
        Y := -1;
        GapTop := AEd.CaretPosToClientPos(Point(0, 0)).Y - Below;
      end
      else
      begin
        if not AEd.Strings.IsIndexValid(Line) or AEd.IsLineFolded(Line) then
          Continue;
        Y := AEd.CaretPosToClientPos(Point(0, Line)).Y;
        { Under the last row of a wrapped line. }
        GapTop := AEd.CaretPosToClientPos(Point(AEd.Strings.LinesLen[Line], Line)).Y + CharH;
      end;
      if (GapTop + Below < AEd.RectMain.Top) or (GapTop >= AEd.RectMain.Bottom) then
        Continue;
      for g := First to i - 1 do
      begin
        EditDrawGap(AEd, C, Rect(AEd.RectMain.Left, GapTop, AEd.RectMain.Right,
          GapTop + AEd.Gaps[g].Size), AEd.Gaps[g]);
        Inc(GapTop, AEd.Gaps[g].Size);
      end;
      if Line < 0 then
        Continue;
      C.Font.Name := AEd.Font.Name;
      C.Font.Size := EditorFontSize(AEd);
      C.Font.Style := [];
      C.Clipping := True;
      C.ClipRect := Rect(0, AEd.RectMain.Top, AEd.RectMain.Left, AEd.RectMain.Bottom);
      C.Brush.Style := bsSolid;
      C.Brush.Color := AEd.Colors.GutterBG;
      C.FillRect(Rect(0, GapTop - Below, AEd.RectMain.Left, GapTop));
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

procedure TRepoFrame.ReviewRelayoutAsync(Data: PtrInt);
begin
  if FView <> gvChanges then
    Exit;
  ApplyReviewGaps;
  SyncOldSide;
end;

procedure TRepoFrame.EditDrawGap(Sender: TObject; C: TCanvas; const ARect: TRect;
  AGap: TATGapItem);
var
  Ed: TATSynEdit;
  Lines: TStringList;
  Card: TRect;
  Fill, Border, Dim, Accent, CodeFill: TColor;
  i, y, H, Kind, W, Side, Right, Indent, k: integer;
  First, HasLink: boolean;
begin
  Ed := TATSynEdit(Sender);
  C.Brush.Style := bsSolid;
  C.Brush.Color := Ed.Colors.TextBG;
  C.FillRect(ARect);
  if (AGap.Tag < 0) or (AGap.Tag > High(FShown)) then
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
  HasLink := FShown[AGap.Tag].Comments[0].Url <> '';
  if not ThreadOpen(AGap.Tag) or FShown[AGap.Tag].Resolved or
    FShown[AGap.Tag].Outdated then
    Accent := Border
  else if FShown[AGap.Tag].Agent <> '' then
    Accent := AgentColor
  else
    Accent := FLinkColor;
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
      Kind := RowKind(Lines.Objects[i]);
      H := ReviewRowHeight(Lines, i, W - 2 * ReviewPadX);
      { A line in a <details> block is indented, a rule down the left of
        each level. }
      Indent := RowDepth(Lines.Objects[i]) * ReviewIndent;
      k := RowDepth(Lines.Objects[i]);
      C.Pen.Color := Border;
      while k > 0 do
      begin
        C.Line(Card.Left + ReviewPadX + (k - 1) * ReviewIndent + 4, y,
          Card.Left + ReviewPadX + (k - 1) * ReviewIndent + 4, y + H);
        Dec(k);
      end;
      ReviewFont(C, Kind);
      if Kind in [rlMarkup, rlDetails] then
      begin
        ReviewFont(C, rlBody);
        if Kind = rlDetails then
          C.Font.Color := Dim
        else
          C.Font.Color := Ed.Colors.TextFont;
        C.Brush.Style := bsClear;
        HTMLDrawOpt(C, Rect(Card.Left + ReviewPadX + Indent, y + 2, Card.Right - ReviewPadX, y + H), [],
          Lines[i], ReviewInkOptions, FReviewInk);
        Inc(y, H);
        Continue;
      end;
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
            C.FillRect(Rect(Card.Left + ReviewPadX + Indent - 4, y, Card.Right - ReviewPadX + 4, y + H));
          end;
      end;
      C.Brush.Style := bsClear;
      if Kind in [rlNote, rlFolded] then
        C.Font.Color := Dim
      else
        C.Font.Color := Ed.Colors.TextFont;
      Right := Card.Right - ReviewPadX;
      if First and HasLink and (Kind in [rlHeader, rlFolded]) then
      begin
        { The link takes the right end of the first header. }
        ReviewFont(C, rlNote);
        Right := Right - C.TextWidth(Format(rsReviewLink, [ForgeName])) - ReviewPadX;
        ReviewFont(C, Kind);
        if Kind = rlFolded then
          C.Font.Color := Dim
        else
          C.Font.Color := Ed.Colors.TextFont;
      end;
      if Kind <> rlRule then
        C.TextRect(Rect(Card.Left + ReviewPadX + Indent, y, Right, y + H),
          Card.Left + ReviewPadX + Indent, y + 2,
          FitText(C, Lines[i], Right - Card.Left - ReviewPadX - Indent));
      if First and HasLink and (Kind in [rlHeader, rlFolded]) then
      begin
        First := False;
        ReviewFont(C, rlNote);
        C.Font.Color := FLinkColor;
        C.Brush.Color := Fill;
        C.Brush.Style := bsSolid;
        C.TextOut(Card.Right - ReviewPadX - C.TextWidth(Format(rsReviewLink, [ForgeName])), y + 2,
          Format(rsReviewLink, [ForgeName]));
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

{ A click on "GitHub ↗" opens the thread on GitHub, one on a link in a
  comment opens the link, one on the summary of a <details> block opens
  or closes the block; anywhere else on the card it folds or unfolds.
  APos is in the gap. }
procedure TRepoFrame.EditClickGap(Sender: TObject; AGapItem: TATGapItem; APos: TPoint);
var
  Ed: TATSynEdit;
  Lines: TStringList;
  W, y, i, Kind, H, LinkLeft: integer;
  LinkDone: boolean;
  Hit: THTMLHitInfo;
begin
  if (AGapItem = nil) or (AGapItem.Tag < 0) or (AGapItem.Tag > High(FShown)) then
    Exit;
  Ed := TATSynEdit(Sender);
  W := ReviewCardWidth(ReviewGapWidth(Ed));
  Lines := TStringList.Create;
  try
    ReviewLayout(AGapItem.Tag, W - 2 * ReviewPadX, Lines);
    y := ReviewMargin + ReviewPadY;
    LinkDone := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Kind := RowKind(Lines.Objects[i]);
      H := ReviewRowHeight(Lines, i, W - 2 * ReviewPadX);
      { The summary of a <details> block opens or closes it, when the
        button is up, as a card folds. }
      if (Kind = rlDetails) and (APos.Y >= y) and (APos.Y < y + H) and
        (APos.X <= ReviewMargin + W) then
      begin
        FGapToggle := DetailsKey(AGapItem.Tag, RowComment(Lines.Objects[i]),
          RowDetail(Lines.Objects[i]));
        Exit;
      end;
      if not LinkDone and (Kind in [rlHeader, rlFolded]) then
      begin
        LinkDone := True;
        if FShown[AGapItem.Tag].Comments[0].Url <> '' then
        begin
          ReviewFont(FReviewMeasure.Canvas, rlNote);
          LinkLeft := ReviewMargin + W - ReviewPadX -
            FReviewMeasure.Canvas.TextWidth(Format(rsReviewLink, [ForgeName]));
          if (APos.Y >= y) and (APos.Y < y + H) and (APos.X >= LinkLeft) and
            (APos.X <= ReviewMargin + W - ReviewPadX) then
          begin
            OpenURL(FShown[AGapItem.Tag].Comments[0].Url);
            Exit;
          end;
        end;
      end;
      { A link in the text opens, when it goes to the web or to a file. }
      if (Kind = rlMarkup) and (APos.Y >= y) and (APos.Y < y + H) then
      begin
        ReviewFont(FReviewMeasure.Canvas, rlBody);
        Hit := HTMLHitTest(FReviewMeasure.Canvas, Rect(ReviewMargin + ReviewPadX +
          RowDepth(Lines.Objects[i]) * ReviewIndent, y + 2,
          ReviewMargin + W - ReviewPadX, y + H), Lines[i], ReviewInkOptions,
          APos.X, APos.Y, FReviewInk);
        if Hit.OnLink and (AnsiStartsText('https://', Hit.LinkName) or
          AnsiStartsText('http://', Hit.LinkName) or AnsiStartsText('mailto:', Hit.LinkName) or
          AnsiStartsText(FileLinkScheme, Hit.LinkName)) then
        begin
          FGapLink := Hit.LinkName;
          Exit;
        end;
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

{ The link a click on a card asked for (FGapLink), once the button is
  up and the editor done with it: a file shown in its place would get
  the caret where the button came up. }
procedure TRepoFrame.OpenGapLinkAsync(Data: PtrInt);
var
  Link: string;
begin
  Link := FGapLink;
  FGapLink := '';
  if Link <> '' then
    OpenCommentLink(Link);
end;

{ The fold asked for by a click on a card or on a <details> block in
  it (DetailsKey), when the button came up. }
procedure TRepoFrame.ToggleThreadNow;
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
  nor outdated, AAll every one, of those the change view shows
  (FShown). }
procedure TRepoFrame.FileThreads(const APath: string; out AOpen, AAll: integer);
var
  t: integer;
begin
  AOpen := 0;
  AAll := 0;
  for t := 0 to High(FShown) do
    if FShown[t].Path = APath then
    begin
      Inc(AAll);
      if not FShown[t].Resolved and not FShown[t].Outdated then
        Inc(AOpen);
    end;
end;

{ What the tree's hint of APath adds about its threads. }
function TRepoFrame.FileThreadsHint(const APath: string): string;
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
procedure TRepoFrame.FileTreeAdvancedCustomDrawItem(Sender: TCustomTreeView;
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
function TRepoFrame.ReviewHint(ANumber: integer): string;
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
