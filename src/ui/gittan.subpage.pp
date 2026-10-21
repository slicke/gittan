unit gittan.subpage;

{** The page of a submodule: what Gittan knows about one submodule,
  painted in the editor's palette like the summary and the Repository
  page, in the same TScrollBox.

  Under the submodule's name it shows where it comes from (the URL, a
  web address being a link, and the branch it follows), then a card
  with what the remote holds against the recorded commit, its color
  telling the state (green up to date, blue new commits, amber not
  checked out or past the remote, red when the remote could not be
  asked), and for a submodule that moved a second card with how. Then
  the recorded, checked out and remote commits in rows, and the lists of
  commits (the ones it moved on to, the ones it no longer has and the
  new ones on the remote) on a line with a dot per commit, as the
  summary lists its recent commits. A click on a commit hands its id to
  OnCopyCommit. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, gittan.submodules, gittan.summary;

type
  {** A commit id clicked on the page. }
  TGittanCopyCommitEvent = procedure(Sender: TObject; const AHash: string) of object;

  {** How a card or a dot is colored. }
  TGittanSubTone = (stnNone, stnGood, stnInfo, stnWarn, stnBad);

  {** The kinds of rows the page lists under its cards. }
  TGittanSubRowKind = (srHeading, srCommit, srLabeled, srMore);

  TGittanSubRow = record
    Kind: TGittanSubRowKind;
    { The label of a labeled row, the title of a heading, the text of a
      "more" row or of a labeled row without a commit. }
    Caption, Text: string;
    Commit: TGittanSubmoduleCommit;
    Tone: TGittanSubTone;
    { Set on the commit rows of one list, which a line joins. }
    First, Last: boolean;
  end;

  { TGittanSubPage }

  TGittanSubPage = class(TCustomControl)
  private
    FPath, FName, FUrl, FWeb, FBranchText: string;
    FCards: array of record
      Title, Detail: string;
      Tone: TGittanSubTone;
    end;
    FRows: array of TGittanSubRow;
    FRowTops: array of integer;
    FBack, FText, FDim, FHover, FLine, FCard, FLink, FGood, FWarn, FBad: TColor;
    FUrlRect: TRect;
    FHot: integer;
    FUrlHot: boolean;
    FContentHeight: integer;
    FOnOpenUrl: TGittanOpenUrlEvent;
    FOnCopyCommit: TGittanCopyCommitEvent;
    procedure AddCard(const ATitle, ADetail: string; ATone: TGittanSubTone);
    procedure AddRow(AKind: TGittanSubRowKind; const ACaption, AText: string;
      ATone: TGittanSubTone);
    procedure AddCommit(const ACaption: string; const ACommit: TGittanSubmoduleCommit;
      ATone: TGittanSubTone);
    procedure AddList(const ATitle: string; const ACommits: TGittanSubmoduleCommits;
      ATotal: integer; ATone: TGittanSubTone);
    function ToneColor(ATone: TGittanSubTone): TColor;
    function FitRight(const AText: string; AMaxWidth: integer): string;
    function LabelWidth: integer;
    function RowAt(Y: integer): integer;
    procedure SetHot(AValue: integer);
    procedure SetUrlHot(AValue: boolean);
    procedure PaintCard(var Y: integer; AIndex: integer);
    procedure PaintRow(AIndex, ATop, ALabelWidth: integer);
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    constructor Create(AOwner: TComponent); override;
    {** Shows ASub with what its job found (AInfo; AChecking while a job
      asks the remote and nothing is known yet) and how it moved
      (AChange, the same commit on both sides when it did not).
      ASuperBranch names the repository's own branch, for a submodule
      that follows it. }
    procedure SetSubmodule(const ASub: TGittanSubmodule; const AInfo: TGittanSubmoduleInfo;
      const AChange: TGittanSubmoduleChange; AChecking: boolean; const ASuperBranch: string);
    {** The palette: the background, the text, the dim text, the fill under
      the mouse, the dividers and the line of a commit list, the fill of
      the cards, the links and the blue of new commits, then the green,
      amber and red of the states. }
    procedure SetColors(ABack, AText, ADim, AHover, ALine, ACard, ALink, AGood, AWarn,
      ABad: TColor);
    {** Makes the control at least AMin high, as the summary does. }
    procedure FitHeight(AMin: integer);
    {** The path of the submodule shown. }
    property Path: string read FPath;
    {** A click on the URL when it is a web address. }
    property OnOpenUrl: TGittanOpenUrlEvent read FOnOpenUrl write FOnOpenUrl;
    {** A click on a commit: its full id. }
    property OnCopyCommit: TGittanCopyCommitEvent read FOnCopyCommit write FOnCopyCommit;
  end;

implementation

uses
  Math, LazUTF8, gittan.repoinfo, gittan.statusbar;

resourcestring
  rsSubPageDefaultBranch = 'the remote''s default branch';
  rsSubPageSameBranch = 'the repository''s own branch (%s)';
  rsSubPageBranch = 'follows %s';
  rsSubPageChecking = 'Asking the remote…';
  rsSubPageCheckingDetail = 'ls-remote looks up its branch; nothing is fetched.';
  rsSubPageNotAsked = 'The remote has not been asked yet';
  rsSubPageConflict = 'In conflict';
  rsSubPageConflictDetail = 'The index holds more than one commit for it.';
  rsSubPageNoRecorded = 'No commit recorded';
  rsSubPageNoRecordedDetail = 'The index records no commit for it.';
  rsSubPageNotInit = 'Not checked out';
  rsSubPageNotInitDetail = 'Update checks out the recorded commit.';
  rsSubPageUpToDate = 'Up to date';
  rsSubPageUpToDateDetail = 'The remote''s branch is at the recorded commit.';
  rsSubPageOneBehind = '1 new commit on the remote';
  rsSubPageBehind = '%d new commits on the remote';
  rsSubPageBehindDetail = 'The remote''s branch has commits the recorded one lacks.';
  rsSubPageAhead = 'The recorded commit is %d past the remote';
  rsSubPageAheadDetail = 'It may not be pushed in the submodule yet.';
  rsSubPageDiverged = '%d new on the remote, %d only in the recorded commit';
  rsSubPageDivergedDetail = 'The remote''s branch and the recorded commit went apart.';
  rsSubPageNotFetched = 'New commits on the remote';
  rsSubPageNotFetchedDetail = 'Fetch in the submodule to list them.';
  rsSubPageFailed = 'Could not ask the remote';
  rsSubPageMoved = 'Changed %s → %s';
  rsSubPageForward = '%d new commits';
  rsSubPageOneForward = '1 new commit';
  rsSubPageBack = 'back by %d commits';
  rsSubPageBoth = '%d new commits, %d dropped';
  rsSubPageUncounted = 'The submodule lacks one of them; fetch in it to list the commits.';
  rsSubPageNone = 'none';
  rsSubPageCommits = 'Commits';
  rsSubPageRecorded = 'Recorded';
  rsSubPageCheckedOut = 'Checked out';
  rsSubPageRemote = 'Remote';
  rsSubPageSameAsRecorded = 'the recorded commit';
  rsSubPageNothing = 'nothing';
  rsSubPageAsking = 'asking…';
  rsSubPageAdded = 'Commits it moved on to';
  rsSubPageDropped = 'Commits it no longer has';
  rsSubPageIncoming = 'New on the remote';
  rsSubPageMore = '… and %d more';

const
  Pad = 24;
  Gap = 12;
  RowHeight = 30;
  TitleFontSize = 20;
  CardTitleSize = 14;
  CardPadX = 16;
  CardPadY = 12;
  CardRadius = 12;
  DiscSize = 12;
  DotSize = 8;
  IconSize = 16;
  HeadingTopGap = 18;
  { The least room for a commit's subject before its author is dropped. }
  SubjectRoom = 220;

function Short(const AHash: string): string;
begin
  if AHash = '' then
    Result := rsSubPageNone
  else
    Result := Copy(AHash, 1, 7);
end;

{ TGittanSubPage }

constructor TGittanSubPage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Align := alTop;
  FHot := -1;
  SetColors(clWhite, clBlack, clGray, clSilver, clSilver, clWhite, clBlue, clGreen,
    clOlive, clRed);
end;

procedure TGittanSubPage.SetColors(ABack, AText, ADim, AHover, ALine, ACard, ALink,
  AGood, AWarn, ABad: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
  FLine := ALine;
  FCard := ACard;
  FLink := ALink;
  FGood := AGood;
  FWarn := AWarn;
  FBad := ABad;
  Color := ABack;
  Invalidate;
end;

procedure TGittanSubPage.FitHeight(AMin: integer);
begin
  Constraints.MinHeight := AMin;
  Height := Max(FContentHeight, AMin);
end;

procedure TGittanSubPage.AddCard(const ATitle, ADetail: string; ATone: TGittanSubTone);
begin
  SetLength(FCards, Length(FCards) + 1);
  FCards[High(FCards)].Title := ATitle;
  FCards[High(FCards)].Detail := ADetail;
  FCards[High(FCards)].Tone := ATone;
end;

procedure TGittanSubPage.AddRow(AKind: TGittanSubRowKind; const ACaption, AText: string;
  ATone: TGittanSubTone);
var
  Row: TGittanSubRow;
begin
  Row := Default(TGittanSubRow);
  Row.Kind := AKind;
  Row.Caption := ACaption;
  Row.Text := AText;
  Row.Tone := ATone;
  SetLength(FRows, Length(FRows) + 1);
  FRows[High(FRows)] := Row;
end;

{ A labeled row: the commit when the submodule has it, else its short id
  as the text. }
procedure TGittanSubPage.AddCommit(const ACaption: string;
  const ACommit: TGittanSubmoduleCommit; ATone: TGittanSubTone);
begin
  AddRow(srLabeled, ACaption, '', ATone);
  FRows[High(FRows)].Commit := ACommit;
end;

{ A heading and the commits under it on a line, with "… and n more"
  when ATotal is more than are listed. }
procedure TGittanSubPage.AddList(const ATitle: string; const ACommits: TGittanSubmoduleCommits;
  ATotal: integer; ATone: TGittanSubTone);
var
  i: integer;
begin
  if Length(ACommits) = 0 then
    Exit;
  AddRow(srHeading, ATitle, '', stnNone);
  for i := 0 to High(ACommits) do
  begin
    AddRow(srCommit, '', '', ATone);
    FRows[High(FRows)].Commit := ACommits[i];
    FRows[High(FRows)].First := i = 0;
    FRows[High(FRows)].Last := i = High(ACommits);
  end;
  if ATotal > Length(ACommits) then
    AddRow(srMore, '', Format(rsSubPageMore, [ATotal - Length(ACommits)]), stnNone);
end;

procedure TGittanSubPage.SetSubmodule(const ASub: TGittanSubmodule;
  const AInfo: TGittanSubmoduleInfo; const AChange: TGittanSubmoduleChange;
  AChecking: boolean; const ASuperBranch: string);
var
  Detail: string;
  Tip: TGittanSubmoduleCommit;
  i: integer;
begin
  if FPath <> ASub.Path then
    FHot := -1;
  FPath := ASub.Path;
  FName := ExtractFileName(StringReplace(ASub.Path, '/', PathDelim, [rfReplaceAll]));
  if FName = '' then
    FName := ASub.Path;
  FUrl := ASub.Url;
  FWeb := RemoteWebUrl(ASub.Url);
  if ASub.Branch = '' then
    FBranchText := Format(rsSubPageBranch, [rsSubPageDefaultBranch])
  else if ASub.Branch = '.' then
    FBranchText := Format(rsSubPageBranch, [Format(rsSubPageSameBranch, [ASuperBranch])])
  else
    FBranchText := Format(rsSubPageBranch, [ASub.Branch]);

  { The cards: the state first, then how it moved. }
  FCards := nil;
  if ASub.Conflict then
    AddCard(rsSubPageConflict, rsSubPageConflictDetail, stnBad)
  else if ASub.Recorded = '' then
    AddCard(rsSubPageNoRecorded, rsSubPageNoRecordedDetail, stnWarn);
  if AChecking then
    AddCard(rsSubPageChecking, rsSubPageCheckingDetail, stnNone)
  else
    case AInfo.State of
      smUpToDate: AddCard(rsSubPageUpToDate, rsSubPageUpToDateDetail, stnGood);
      smBehind:
        if AInfo.Behind = 1 then
          AddCard(rsSubPageOneBehind, rsSubPageBehindDetail, stnInfo)
        else
          AddCard(Format(rsSubPageBehind, [AInfo.Behind]), rsSubPageBehindDetail, stnInfo);
      smAhead: AddCard(Format(rsSubPageAhead, [AInfo.Ahead]), rsSubPageAheadDetail, stnWarn);
      smDiverged: AddCard(Format(rsSubPageDiverged, [AInfo.Behind, AInfo.Ahead]),
          rsSubPageDivergedDetail, stnWarn);
      smNotFetched: AddCard(rsSubPageNotFetched, rsSubPageNotFetchedDetail, stnInfo);
      smFailed: AddCard(rsSubPageFailed, Trim(AInfo.Error), stnBad);
      else
        AddCard(rsSubPageNotAsked, '', stnNone);
    end;
  if not AChecking and (AInfo.State <> smUnknown) and not AInfo.Initialized and
    (ASub.Recorded <> '') and not ASub.Conflict then
    AddCard(rsSubPageNotInit, rsSubPageNotInitDetail, stnWarn);
  if AChange.FromHash <> AChange.ToHash then
  begin
    if (AChange.Added > 0) and (AChange.Removed > 0) then
      Detail := Format(rsSubPageBoth, [AChange.Added, AChange.Removed])
    else if AChange.Added = 1 then
      Detail := rsSubPageOneForward
    else if AChange.Added > 0 then
      Detail := Format(rsSubPageForward, [AChange.Added])
    else if AChange.Removed > 0 then
      Detail := Format(rsSubPageBack, [AChange.Removed])
    else if (AChange.FromHash <> '') and (AChange.ToHash <> '') then
      Detail := rsSubPageUncounted
    else
      Detail := '';
    AddCard(Format(rsSubPageMoved, [Short(AChange.FromHash), Short(AChange.ToHash)]),
      Detail, stnInfo);
  end;

  { The commits in rows. }
  FRows := nil;
  AddRow(srHeading, rsSubPageCommits, '', stnNone);
  if ASub.Recorded = '' then
    AddRow(srLabeled, rsSubPageRecorded, rsSubPageNone, stnNone)
  else if AInfo.Recorded.Hash <> '' then
    AddCommit(rsSubPageRecorded, AInfo.Recorded, stnNone)
  else
    AddRow(srLabeled, rsSubPageRecorded, Short(ASub.Recorded), stnNone);
  if AChecking then
    AddRow(srLabeled, rsSubPageCheckedOut, rsSubPageAsking, stnNone)
  else if not AInfo.Initialized then
    AddRow(srLabeled, rsSubPageCheckedOut, rsSubPageNothing, stnWarn)
  else if AInfo.CheckedOut = ASub.Recorded then
    AddRow(srLabeled, rsSubPageCheckedOut, rsSubPageSameAsRecorded, stnNone)
  else if AInfo.Current.Hash <> '' then
    AddCommit(rsSubPageCheckedOut, AInfo.Current, stnInfo)
  else
    AddRow(srLabeled, rsSubPageCheckedOut, Short(AInfo.CheckedOut), stnInfo);
  if AChecking then
    AddRow(srLabeled, rsSubPageRemote, rsSubPageAsking, stnNone)
  else if AInfo.Tip <> '' then
  begin
    { The remote's commit is described when it is among the new ones,
      which are newest first, or is the recorded one. }
    Tip := Default(TGittanSubmoduleCommit);
    for i := 0 to High(AInfo.Incoming) do
      if AInfo.Incoming[i].Hash = AInfo.Tip then
        Tip := AInfo.Incoming[i];
    if (Tip.Hash = '') and (AInfo.Recorded.Hash = AInfo.Tip) then
      Tip := AInfo.Recorded;
    if (Tip.Hash = '') and (AInfo.Current.Hash = AInfo.Tip) then
      Tip := AInfo.Current;
    if AInfo.Tip = ASub.Recorded then
      AddRow(srLabeled, rsSubPageRemote, rsSubPageSameAsRecorded, stnGood)
    else if Tip.Hash <> '' then
      AddCommit(rsSubPageRemote, Tip, stnInfo)
    else
      AddRow(srLabeled, rsSubPageRemote, Short(AInfo.Tip), stnInfo);
  end
  else
    AddRow(srLabeled, rsSubPageRemote, rsSubPageNone, stnNone);

  if AChange.FromHash <> AChange.ToHash then
  begin
    AddList(rsSubPageAdded, AChange.Commits, AChange.Added, stnInfo);
    AddList(rsSubPageDropped, AChange.Dropped, AChange.Removed, stnWarn);
  end;
  { Moved to the remote's commit, the list above has the same ones. }
  if AChange.ToHash <> AInfo.Tip then
    AddList(rsSubPageIncoming, AInfo.Incoming, AInfo.Behind, stnInfo);
  if FHot > High(FRows) then
    FHot := -1;
  Invalidate;
end;

function TGittanSubPage.ToneColor(ATone: TGittanSubTone): TColor;
begin
  case ATone of
    stnGood: Result := FGood;
    stnInfo: Result := FLink;
    stnWarn: Result := FWarn;
    stnBad: Result := FBad;
    else
      Result := FDim;
  end;
end;

{ AText cut at the end with an ellipsis until it fits AMaxWidth. }
function TGittanSubPage.FitRight(const AText: string; AMaxWidth: integer): string;
var
  n: integer;
begin
  Result := AText;
  if Canvas.TextWidth(Result) <= AMaxWidth then
    Exit;
  n := UTF8Length(AText);
  while (n > 0) and (Canvas.TextWidth(UTF8Copy(AText, 1, n) + '…') > AMaxWidth) do
    Dec(n);
  Result := TrimRight(UTF8Copy(AText, 1, n)) + '…';
end;

{ The column of the labels of the labeled rows. }
function TGittanSubPage.LabelWidth: integer;
var
  i: integer;
begin
  Canvas.Font := Font;
  Result := 0;
  for i := 0 to High(FRows) do
    if FRows[i].Kind = srLabeled then
      Result := Max(Result, Canvas.TextWidth(FRows[i].Caption));
  Inc(Result, IconSize + Gap div 2 + 2 + Gap * 2);
end;

function TGittanSubPage.RowAt(Y: integer): integer;
var
  i: integer;
begin
  for i := 0 to Min(High(FRows), High(FRowTops)) do
    if (FRows[i].Kind in [srCommit, srLabeled]) and (FRows[i].Commit.Hash <> '') and
      (Y >= FRowTops[i]) and (Y < FRowTops[i] + RowHeight) then
      Exit(i);
  Result := -1;
end;

procedure TGittanSubPage.SetHot(AValue: integer);
begin
  if FHot = AValue then
    Exit;
  FHot := AValue;
  Invalidate;
end;

procedure TGittanSubPage.SetUrlHot(AValue: boolean);
begin
  if FUrlHot = AValue then
    Exit;
  FUrlHot := AValue;
  Invalidate;
end;

{ A rounded card in the card fill with a disc in the tone's color, the
  title larger and the detail dimmed under it. }
procedure TGittanSubPage.PaintCard(var Y: integer; AIndex: integer);
var
  TitleH, BodyH, CardH, TextX, DiscY: integer;
  R: TRect;
begin
  Canvas.Font := Font;
  BodyH := Canvas.TextHeight('Xg');
  Canvas.Font.Size := CardTitleSize;
  Canvas.Font.Style := [fsBold];
  TitleH := Canvas.TextHeight('Xg');
  CardH := CardPadY * 2 + TitleH;
  if FCards[AIndex].Detail <> '' then
    Inc(CardH, BodyH + 2);
  R := Rect(Pad, Y, Width - Pad, Y + CardH);
  Canvas.Pen.Style := psClear;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FCard;
  Canvas.RoundRect(R, CardRadius, CardRadius);
  { The disc, ringed in a lighter shade of the tone while asking. }
  DiscY := Y + CardPadY + (TitleH - DiscSize) div 2;
  Canvas.Brush.Color := ToneColor(FCards[AIndex].Tone);
  Canvas.Ellipse(R.Left + CardPadX, DiscY, R.Left + CardPadX + DiscSize, DiscY + DiscSize);
  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Style := bsClear;
  TextX := R.Left + CardPadX + DiscSize + Gap;
  Canvas.Font.Color := FText;
  Canvas.TextOut(TextX, Y + CardPadY, FitRight(FCards[AIndex].Title, R.Right - CardPadX - TextX));
  if FCards[AIndex].Detail <> '' then
  begin
    Canvas.Font := Font;
    Canvas.Font.Color := FDim;
    Canvas.TextOut(TextX, Y + CardPadY + TitleH + 2,
      FitRight(FCards[AIndex].Detail, R.Right - CardPadX - TextX));
  end;
  Inc(Y, CardH);
end;

{ A row of the list under the cards. A heading is a dim bold title over
  a divider; a commit of a list a dot on the list's line, the subject,
  the author and date dimmed and the short id at the right; a labeled
  row the label in its column, then the commit the same way or a text. }
procedure TGittanSubPage.PaintRow(AIndex, ATop, ALabelWidth: integer);
var
  Row: TGittanSubRow;
  TextH, TextY, X, Right, CenterX, CenterY, MetaW: integer;
  Meta: string;
begin
  Row := FRows[AIndex];
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  TextH := Canvas.TextHeight('Xg');
  TextY := ATop + (RowHeight - TextH) div 2;
  CenterX := Pad + IconSize div 2;
  CenterY := ATop + RowHeight div 2;
  case Row.Kind of
    srHeading:
      begin
        Canvas.Font.Style := [fsBold];
        Canvas.Font.Color := FDim;
        TextY := ATop + RowHeight - TextH - 6;
        Canvas.TextOut(Pad, TextY, Row.Caption);
        Canvas.Pen.Color := FLine;
        Canvas.Line(Pad, ATop + RowHeight - 1, Width - Pad, ATop + RowHeight - 1);
        Exit;
      end;
    srMore:
      begin
        Canvas.Font.Color := FDim;
        Canvas.TextOut(Pad + IconSize + Gap div 2 + 2, TextY, Row.Text);
        Exit;
      end;
  end;
  if AIndex = FHot then
  begin
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FHover;
    Canvas.RoundRect(Pad div 2, ATop, Width - Pad div 2, ATop + RowHeight, 8, 8);
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsClear;
  end;
  { The dot: filled in the tone's color, a ring when the tone is none. }
  if Row.Kind = srCommit then
  begin
    Canvas.Pen.Width := 2;
    Canvas.Pen.Color := FLine;
    if not Row.First then
      Canvas.Line(CenterX, ATop, CenterX, CenterY);
    if not Row.Last then
      Canvas.Line(CenterX, CenterY, CenterX, ATop + RowHeight);
  end;
  Canvas.Pen.Width := 2;
  Canvas.Brush.Style := bsSolid;
  if Row.Tone = stnNone then
  begin
    Canvas.Pen.Color := FDim;
    if AIndex = FHot then
      Canvas.Brush.Color := FHover
    else
      Canvas.Brush.Color := FBack;
  end
  else
  begin
    Canvas.Pen.Color := ToneColor(Row.Tone);
    Canvas.Brush.Color := ToneColor(Row.Tone);
  end;
  Canvas.Ellipse(CenterX - DotSize div 2 - 1, CenterY - DotSize div 2 - 1,
    CenterX + DotSize div 2 + 1, CenterY + DotSize div 2 + 1);
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;

  X := Pad + IconSize + Gap div 2 + 2;
  if Row.Kind = srLabeled then
  begin
    Canvas.Font.Color := FDim;
    Canvas.TextOut(X, TextY, Row.Caption);
    X := Pad + ALabelWidth;
  end;
  Right := Width - Pad;
  if Row.Commit.Hash = '' then
  begin
    Canvas.Font.Color := FDim;
    Canvas.TextOut(X, TextY, FitRight(Row.Text, Right - X));
    Exit;
  end;
  { The short id at the right, in the link color under the mouse, since
    a click copies it. }
  if AIndex = FHot then
    Canvas.Font.Color := FLink
  else
    Canvas.Font.Color := FDim;
  Canvas.TextOut(Right - Canvas.TextWidth(Row.Commit.Short), TextY, Row.Commit.Short);
  Dec(Right, Canvas.TextWidth('0000000') + Gap + Gap div 2);
  Meta := Row.Commit.Author;
  if Row.Commit.Date <> '' then
  begin
    if Meta <> '' then
      Meta := Meta + ' · ';
    Meta := Meta + Row.Commit.Date;
  end;
  { The subject keeps room for a few words: the author goes first, then
    the date. }
  if Right - Canvas.TextWidth(Meta) - Gap - X < SubjectRoom then
    Meta := Row.Commit.Date;
  if Right - Canvas.TextWidth(Meta) - Gap - X < SubjectRoom div 2 then
    Meta := '';
  if Meta <> '' then
  begin
    MetaW := Canvas.TextWidth(Meta);
    Canvas.Font.Color := FDim;
    Canvas.TextOut(Right - MetaW, TextY, Meta);
    Dec(Right, MetaW + Gap + Gap div 2);
  end;
  Canvas.Font.Color := FText;
  Canvas.TextOut(X, TextY, FitRight(Row.Commit.Subject, Right - X));
end;

procedure TGittanSubPage.Paint;
var
  Y, X, TextH, TitleH, IconW, i, LabelW: integer;
  Shown: string;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  TextH := Canvas.TextHeight('Xg');
  Y := Pad;

  { The name, then where it comes from: the URL with a globe when it is
    a web address, else a folder, and the branch it follows. }
  Canvas.Font.Size := TitleFontSize;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FText;
  TitleH := Canvas.TextHeight('Xg');
  Canvas.TextOut(Pad, Y, FName);
  Inc(Y, TitleH + 4);
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  IconW := TextH - 4 + 5;
  X := Pad;
  FUrlRect := Rect(0, 0, 0, 0);
  if FUrl <> '' then
  begin
    if FWeb <> '' then
      DrawStatusIcon(Canvas, HintLink, X, Y, TextH, FDim)
    else
      DrawStatusIcon(Canvas, HintFolder, X, Y, TextH, FDim);
    Canvas.Pen.Width := 1;
    Canvas.Brush.Style := bsClear;
    Inc(X, IconW);
    Shown := FitRight(FUrl, Max(80, (Width - 2 * Pad) * 2 div 3));
    if FWeb <> '' then
    begin
      FUrlRect := Rect(X, Y, X + Canvas.TextWidth(Shown), Y + TextH);
      Canvas.Font.Color := FLink;
      if FUrlHot then
        Canvas.Font.Style := [fsUnderline];
    end
    else
      Canvas.Font.Color := FText;
    Canvas.TextOut(X, Y, Shown);
    Canvas.Font.Style := [];
    Inc(X, Canvas.TextWidth(Shown) + Gap * 2);
  end;
  if X + IconW + Canvas.TextWidth(FBranchText) > Width - Pad then
  begin
    Inc(Y, TextH + 6);
    X := Pad;
  end;
  DrawStatusIcon(Canvas, HintBranch, X, Y, TextH, FDim);
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := FDim;
  Canvas.TextOut(X + IconW, Y, FitRight(FBranchText, Width - Pad - X - IconW));
  Inc(Y, TextH + Pad);

  for i := 0 to High(FCards) do
  begin
    PaintCard(Y, i);
    Inc(Y, Gap div 2 + 2);
  end;
  Inc(Y, HeadingTopGap - Gap div 2 - 2);

  LabelW := LabelWidth;
  SetLength(FRowTops, Length(FRows));
  for i := 0 to High(FRows) do
  begin
    if (FRows[i].Kind = srHeading) and (i > 0) then
      Inc(Y, HeadingTopGap);
    FRowTops[i] := Y;
    PaintRow(i, Y, LabelW);
    Inc(Y, RowHeight);
    if FRows[i].Kind = srHeading then
      Inc(Y, 4);
  end;

  FContentHeight := Y + Pad;
  if Height < FContentHeight then
    Height := Max(FContentHeight, Constraints.MinHeight);
end;

procedure TGittanSubPage.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetUrlHot(PtInRect(FUrlRect, Point(X, Y)));
  SetHot(RowAt(Y));
  if FUrlHot or (FHot >= 0) then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
end;

procedure TGittanSubPage.MouseLeave;
begin
  inherited MouseLeave;
  SetUrlHot(False);
  SetHot(-1);
  Cursor := crDefault;
end;

procedure TGittanSubPage.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  i: integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  if PtInRect(FUrlRect, Point(X, Y)) then
  begin
    if Assigned(FOnOpenUrl) then
      FOnOpenUrl(Self, FWeb);
    Exit;
  end;
  i := RowAt(Y);
  if (i >= 0) and Assigned(FOnCopyCommit) then
    FOnCopyCommit(Self, FRows[i].Commit.Hash);
end;

end.
