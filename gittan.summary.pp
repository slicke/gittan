unit gittan.summary;

{** The repository summary: what Gittan shows when a repository is opened,
  before a file is picked. It lists the changed files with their added and
  deleted line counts and a bar that compares the sizes of the changes,
  under a header with the repository name, branch and totals. Between the
  two, the conversation of the pull request when there is one: its
  comments and the text its reviews were submitted with, which are on no
  line, so the change view has no place for them. A clean tree shows,
  instead of the totals, a large check with how far the branch is from
  its upstream, and its newest commits instead of rows while some are
  not pushed; otherwise the check stands alone in the middle, as the
  empty view's icon does.

  It paints itself so it matches the editor's palette in both themes. It
  sizes its height to its content and is meant to sit in a TScrollBox,
  which provides the native scrolling. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, ImgList, gittan.git, gittan.icons,
  gittan.reviews, gittan.statusbar;

type
  TGittanSelectFileEvent = procedure(Sender: TObject; const APath: string) of object;
  {** A right click on a file's row, with the mouse position in screen
    coordinates for a popup menu. }
  TGittanContextFileEvent = procedure(Sender: TObject; const APath: string;
    const AScreenPos: TPoint) of object;
  {** A click on the branch in the header, with its rectangle in screen
    coordinates for a popup to drop down from. }
  TGittanBranchClickEvent = procedure(Sender: TObject; const AScreenRect: TRect) of object;
  {** A click on a commit's row, with its id. }
  TGittanSelectCommitEvent = procedure(Sender: TObject; const AHash: string) of object;
  {** A click on a link to AUrl. }
  TGittanOpenUrlEvent = procedure(Sender: TObject; const AUrl: string) of object;

  {** A note of the conversation as laid out: its wrapped text, and its
    top and height below the start of the section. }
  TGittanSummaryNoteBox = record
    Top, Height: integer;
    Lines: array of string;
    LinkRect: TRect;
  end;

  { TGittanSummary }

  TGittanSummary = class(TCustomControl)
  private
    FRepoName, FBranch, FBase, FSelected, FNotice: string;
    FStats: TGittanFileStats;
    FImages: TCustomImageList;
    FIconIndex: array of integer;
    { What a row shows in place of its counts and bar, '' for those. }
    FRowTexts: array of string;
    FHot: integer;
    FBack, FText, FDim, FHover, FSelectedBack, FAdded, FDeleted, FLine, FLink: TColor;
    FNotesTitle: string;
    FNotes: TGittanPullNotes;
    FNoteBoxes: array of TGittanSummaryNoteBox;
    { The width the notes were laid out at, -1 when they are to be laid
      out again; their height, title included, 0 without notes. }
    FNotesWidth, FNotesHeight: integer;
    { The note whose link is under the mouse, -1 for none. }
    FLinkHot: integer;
    { The newest commits, shown under a clean tree, with how far the
      branch is from its upstream; FCommitHot is the row under the
      mouse, -1 for none. }
    FCommits: TGittanCommitLines;
    FAhead, FBehind: integer;
    FHasUpstream: boolean;
    { The upstream is deleted on the remote: the sync line says so, in
      red after a cross, in place of the counts. }
    FUpstreamGone: boolean;
    FCommitsTop, FCommitHot: integer;
    FOnSelectCommit: TGittanSelectCommitEvent;
    FMeasure: TBitmap;
    FOnSelectFile: TGittanSelectFileEvent;
    FOnContextFile: TGittanContextFileEvent;
    FOnBranchClick: TGittanBranchClickEvent;
    FOnOpenUrl: TGittanOpenUrlEvent;
    FRowsTop: integer;
    { The height the content needs; the control is at least as high as
      the box it fills, see FitHeight. }
    FContentHeight: integer;
    { The branch's chip in the header, in client coordinates; empty
      without a branch. }
    FBranchRect: TRect;
    FBranchHot: boolean;
    { The base label's chip, drawn as one while BaseClickable, with its
      hover state. }
    FBaseRect: TRect;
    FBaseHot, FBaseClickable: boolean;
    FOnBaseClick: TGittanBranchClickEvent;
    function BranchClickable: boolean;
    procedure SetBranchHot(AValue: boolean);
    procedure SetBaseHot(AValue: boolean);
    procedure SetBaseClickable(AValue: boolean);
    function RowAt(Y: integer): integer;
    function CommitAt(Y: integer): integer;
    procedure SetCommitHot(AValue: integer);
    function ShowsCommits: boolean;
    procedure PlaceCommits;
    procedure PaintCommits;
    procedure PaintCommit(AIndex, ATop, AHashWidth: integer);
    procedure SetHot(AValue: integer);
    procedure SetLinkHot(AValue: integer);
    function LinkAt(X, Y: integer): integer;
    procedure LayoutNotes;
    procedure PaintNotes(var Y: integer);
    procedure SetSelected(const AValue: string);
    procedure SetNotice(const AValue: string);
    procedure UpdateHeight;
    procedure PaintNotice(var Y: integer);
    function CentersClean: boolean;
    function CleanText: string;
    function HeaderBlockHeight(ACanvas: TCanvas): integer;
    function CenterBlockHeight(ACanvas: TCanvas): integer;
    procedure DrawCheck(X, Y, ASize: integer);
    procedure PaintCleanHeader(Y: integer);
    procedure PaintCleanCentered;
    function PaintSync(X, Y: integer; ADraw: boolean = True): integer;
    procedure PaintHeader(var Y: integer);
    procedure PaintRow(AIndex, ATop: integer);
    procedure PaintBar(X, Y: integer; const AStat: TGittanFileStat; AMax: integer);
    procedure PaintKinds(Y, ALeft, ARight: integer);
    function BarWidth: integer;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** Shows the changed files AStats of repository AName on ABranch,
      with ABase saying what is compared, as it is to be shown ("vs
      main", "main...feature"; empty for the usual HEAD); AIcons holds
      the image index in Images of each file's badge, and ATexts what to
      show in place of a row's counts and bar, such as the commits a
      submodule moved between; empty for the counts. }
    procedure SetRepository(const AName, ABranch, ABase: string;
      const AStats: TGittanFileStats; const AIcons: array of integer;
      const ATexts: array of string);
    {** Sets the palette: the background, the text, the dim text for paths
      and counts, the hovered row, the selected row, the added and deleted
      colors, and the line color for the divider and the empty part of a
      bar. }
    procedure SetColors(ABack, AText, ADim, AHover, ASelected, AAdded,
      ADeleted, ALine: TColor);
    {** Makes the control at least AMin high (the height of the box it
      sits in, so its background covers the box), and no higher than
      its content needs beyond that: a minimum constraint alone would
      leave it at an old, larger height when the box shrinks, and the
      box would scroll. }
    procedure FitHeight(AMin: integer);
    {** Shows ANotes, the conversation of a pull request, under the
      heading ATitle; no notes shows none. }
    procedure SetNotes(const ATitle: string; const ANotes: TGittanPullNotes);
    {** Shows ACommits, the newest commits of HEAD, under "Working tree
      clean", and after it how many commits the branch is ahead of
      (AAhead) and behind (ABehind) its upstream when it has one
      (AHasUpstream). The commits show only while there are no changed
      files and some are not pushed. }
    procedure SetCommits(const ACommits: TGittanCommitLines;
      AAhead, ABehind: integer; AHasUpstream: boolean);
    {** Whether the upstream is deleted on the remote, which the sync
      line then says in place of the counts. }
    procedure SetUpstreamGone(AGone: boolean);
    {** The color of the notes' links. }
    property LinkColor: TColor read FLink write FLink;
    {** The image list the file badges come from. }
    property Images: TCustomImageList read FImages write FImages;
    {** The path of the file whose row is marked: the one the editor last
      showed. Empty marks none. }
    property Selected: string read FSelected write SetSelected;
    {** A line under the header, dimmed: why the summary is shown when
      the user did not ask for it. Empty shows none. }
    property Notice: string read FNotice write SetNotice;
    {** A click on a file's row. }
    property OnSelectFile: TGittanSelectFileEvent read FOnSelectFile write FOnSelectFile;
    {** A right click on a file's row. }
    property OnContextFile: TGittanContextFileEvent read FOnContextFile write FOnContextFile;
    {** A click on the branch in the header. While it is set the branch
      is drawn as a chip with a chevron, highlighted under the mouse. }
    property OnBranchClick: TGittanBranchClickEvent read FOnBranchClick write FOnBranchClick;
    {** A click on the base label in the header, which is drawn as a chip
      with a chevron while BaseClickable is set (for a base that has
      actions, such as a branch to merge). }
    property OnBaseClick: TGittanBranchClickEvent read FOnBaseClick write FOnBaseClick;
    property BaseClickable: boolean read FBaseClickable write SetBaseClickable;
    {** A click on a commit's row. }
    property OnSelectCommit: TGittanSelectCommitEvent read FOnSelectCommit write FOnSelectCommit;
    {** A click on a note's link to GitHub. }
    property OnOpenUrl: TGittanOpenUrlEvent read FOnOpenUrl write FOnOpenUrl;
  end;

implementation

uses
  Math, DateUtils, LazUTF8;

resourcestring
  rsOneFile = '1 changed file';
  rsManyFiles = '%d changed files';
  rsClean = 'Working tree clean';
  rsCleanVs = 'No changes %s';
  rsRecentCommits = 'Recent commits';
  rsNotPushed = '%d not pushed';
  rsNotPulled = '%d not pulled';
  rsInSync = 'up to date with upstream';
  rsUpstreamGone = '✕ upstream deleted on remote';
  rsBinary = 'binary';
  rsStaged = 'staged';
  rsPartlyStaged = 'partly staged';
  rsNoteCommented = 'commented';
  rsNoteApproved = 'approved';
  rsNoteChangesRequested = 'requested changes';
  rsNoteDismissed = 'review dismissed';
  rsNoteLink = 'GitHub ↗';

const
  { The count of each kind in the header, after a dot in its color. }
  KindCount: array[TGittanChangeKind] of string = ('%d modified', '%d added',
    '%d deleted', '%d renamed', '%d untracked', '%d conflicted');
  Pad = 24;
  RowHeight = 30;
  IconSize = 16;
  { The row bars take a share of the width, within these. }
  MinBarWidth = 96;
  MaxBarWidth = 200;
  TotalBarWidth = 140;
  BarHeight = 6;
  DotSize = 8;
  CountWidth = 56;
  Gap = 12;
  TitleFontSize = 20;
  CheckSize = 20;
  { "Working tree clean", larger than the body; its check in the header
    and alone in the middle. }
  CleanFontSize = 15;
  HeaderCheck = 34;
  CenterCheck = 64;
  ChipPadX = 6;
  ChipPadY = 3;
  ChevronWidth = 14;
  { Between the branch icon and the name, as in the status bar. }
  IconGap = 5;
  { A note's card: room inside it, between cards, the colored stripe at
    its left, and the most lines of text it shows (the rest is on
    GitHub). }
  NotePadX = 12;
  NotePadY = 8;
  NoteGap = 8;
  NoteStripe = 3;
  NoteMaxLines = 12;

{ TGittanSummary }

constructor TGittanSummary.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FHot := -1;
  FLinkHot := -1;
  FCommitHot := -1;
  FNotesWidth := -1;
  FLink := clHighlight;
  FMeasure := TBitmap.Create;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnFace, clGreen,
    clRed, clBtnShadow);
  { The height follows the content; the scroll box it sits in scrolls. }
  Align := alTop;
  UpdateHeight;
end;

destructor TGittanSummary.Destroy;
begin
  FMeasure.Free;
  inherited Destroy;
end;

procedure TGittanSummary.SetRepository(const AName, ABranch, ABase: string;
  const AStats: TGittanFileStats; const AIcons: array of integer;
  const ATexts: array of string);
var
  i: integer;
begin
  SetLength(FRowTexts, Length(ATexts));
  for i := 0 to High(ATexts) do
    FRowTexts[i] := ATexts[i];
  FRepoName := AName;
  FBranch := ABranch;
  FBase := ABase;
  FStats := Copy(AStats);
  SetLength(FIconIndex, Length(AIcons));
  for i := 0 to High(AIcons) do
    FIconIndex[i] := AIcons[i];
  FHot := -1;
  UpdateHeight;
  Invalidate;
end;

procedure TGittanSummary.SetCommits(const ACommits: TGittanCommitLines;
  AAhead, ABehind: integer; AHasUpstream: boolean);
begin
  FCommits := Copy(ACommits);
  FAhead := AAhead;
  FBehind := ABehind;
  FHasUpstream := AHasUpstream;
  FCommitHot := -1;
  UpdateHeight;
  Invalidate;
end;

{ The commits are listed while some wait to be pushed; a branch that is
  pushed, or has no upstream to push to, has nothing to act on, so its
  clean state stands alone. }
procedure TGittanSummary.SetUpstreamGone(AGone: boolean);
begin
  if FUpstreamGone = AGone then
    Exit;
  FUpstreamGone := AGone;
  Invalidate;
end;

function TGittanSummary.ShowsCommits: boolean;
begin
  Result := (Length(FStats) = 0) and (Length(FCommits) > 0) and FHasUpstream
    and (FAhead > 0);
end;

{ Under a clean tree the commits take the place of the file rows, after
  their heading. Sets FCommitsTop and FContentHeight from FRowsTop. }
procedure TGittanSummary.PlaceCommits;
var
  BodyHeight: integer;
begin
  FMeasure.Canvas.Font := Font;
  BodyHeight := FMeasure.Canvas.TextHeight('Xg');
  FCommitsTop := FRowsTop + BodyHeight + NoteGap;
  if ShowsCommits then
    FContentHeight := FCommitsTop + Length(FCommits) * RowHeight + Pad
  else if CentersClean then
    FContentHeight := FRowsTop + CenterBlockHeight(FMeasure.Canvas) + 2 * Pad
  else
    FContentHeight := FRowsTop + Max(Length(FStats), 2) * RowHeight + Pad;
end;

{ A clean tree with nothing else to show: no commits, no conversation. }
function TGittanSummary.CentersClean: boolean;
begin
  Result := (Length(FStats) = 0) and not ShowsCommits and (Length(FNotes) = 0);
end;

{ "Working tree clean", or "No changes vs base" when the tree is
  compared against something other than HEAD. }
function TGittanSummary.CleanText: string;
begin
  if FBase = '' then
    Result := rsClean
  else
    Result := Format(rsCleanVs, [FBase]);
end;

{ The height of the header under the title: the totals line, the clean
  check with its text and the sync line, or nothing when the clean
  state stands in the middle. }
function TGittanSummary.HeaderBlockHeight(ACanvas: TCanvas): integer;
var
  BodyHeight: integer;
begin
  ACanvas.Font := Font;
  BodyHeight := ACanvas.TextHeight('Xg');
  if Length(FStats) > 0 then
    Exit(BodyHeight);
  if CentersClean then
    Exit(0);
  ACanvas.Font.Size := CleanFontSize;
  Result := ACanvas.TextHeight('Xg');
  if FHasUpstream then
    Inc(Result, 2 + BodyHeight);
  Result := Max(Result, HeaderCheck);
end;

{ The height of the clean state in the middle: the check, the text and
  the sync line. }
function TGittanSummary.CenterBlockHeight(ACanvas: TCanvas): integer;
var
  BodyHeight: integer;
begin
  ACanvas.Font := Font;
  BodyHeight := ACanvas.TextHeight('Xg');
  ACanvas.Font.Size := CleanFontSize;
  Result := CenterCheck + Gap + ACanvas.TextHeight('Xg');
  if FHasUpstream then
    Inc(Result, 4 + BodyHeight);
end;

procedure TGittanSummary.SetColors(ABack, AText, ADim, AHover, ASelected,
  AAdded, ADeleted, ALine: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
  FSelectedBack := ASelected;
  FAdded := AAdded;
  FDeleted := ADeleted;
  FLine := ALine;
  Color := ABack;
  Invalidate;
end;

{ The header is measured in Paint, so the height is an estimate from the
  font until the first paint settles it. }
procedure TGittanSummary.UpdateHeight;
var
  Measure: TBitmap;
  TitleHeight, BodyHeight: integer;
begin
  Measure := TBitmap.Create;
  try
    Measure.Canvas.Font := Font;
    BodyHeight := Measure.Canvas.TextHeight('Xg');
    Measure.Canvas.Font.Size := TitleFontSize;
    TitleHeight := Measure.Canvas.TextHeight('Xg');
  finally
    Measure.Free;
  end;
  FRowsTop := Pad + TitleHeight + 6 + HeaderBlockHeight(FMeasure.Canvas) + Pad;
  if FNotice <> '' then
    Inc(FRowsTop, RowHeight);
  LayoutNotes;
  Inc(FRowsTop, FNotesHeight);
  PlaceCommits;
  Height := Max(FContentHeight, Constraints.MinHeight);
end;

procedure TGittanSummary.FitHeight(AMin: integer);
begin
  Constraints.MinHeight := AMin;
  Height := Max(FContentHeight, AMin);
end;

procedure TGittanSummary.SetNotes(const ATitle: string; const ANotes: TGittanPullNotes);
begin
  FNotesTitle := ATitle;
  FNotes := Copy(ANotes);
  FNotesWidth := -1;
  FLinkHot := -1;
  UpdateHeight;
  Invalidate;
end;

{ Lays the notes out at the control's width, when it changed: each
  note's text wrapped at words (inside a word longer than a line too),
  at most NoteMaxLines lines with an ellipsis after. }
procedure TGittanSummary.LayoutNotes;
var
  C: TCanvas;
  Inner, LineHeight, i, At: integer;
  Paras: TStringList;
  Box: TGittanSummaryNoteBox;

  procedure Add(const AText: string);
  begin
    SetLength(Box.Lines, Length(Box.Lines) + 1);
    Box.Lines[High(Box.Lines)] := AText;
  end;

  procedure Wrap(const AText: string);
  var
    Words: TStringList;
    Line, Part: string;
    w, n: integer;
  begin
    if C.TextWidth(AText) <= Inner then
    begin
      Add(AText);
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
        if Line = '' then
          Part := Words[w]
        else
          Part := Line + ' ' + Words[w];
        if C.TextWidth(Part) <= Inner then
        begin
          Line := Part;
          Continue;
        end;
        if Line <> '' then
          Add(Line);
        Line := Words[w];
        while (C.TextWidth(Line) > Inner) and (UTF8Length(Line) > 1) do
        begin
          n := UTF8Length(Line);
          while (n > 1) and (C.TextWidth(UTF8Copy(Line, 1, n)) > Inner) do
            Dec(n);
          Add(UTF8Copy(Line, 1, n));
          Line := UTF8Copy(Line, n + 1, MaxInt);
        end;
      end;
      if Line <> '' then
        Add(Line);
    finally
      Words.Free;
    end;
  end;

begin
  if FNotesWidth = Width then
    Exit;
  FNotesWidth := Width;
  FNoteBoxes := nil;
  FNotesHeight := 0;
  if Length(FNotes) = 0 then
    Exit;
  C := FMeasure.Canvas;
  C.Font := Font;
  LineHeight := C.TextHeight('Xg');
  Inner := Max(40, Width - 2 * Pad - 2 * NotePadX - NoteStripe);
  { The section's heading. }
  At := LineHeight + NoteGap;
  SetLength(FNoteBoxes, Length(FNotes));
  Paras := TStringList.Create;
  try
    for i := 0 to High(FNotes) do
    begin
      Box := Default(TGittanSummaryNoteBox);
      Paras.Text := FNotes[i].Body;
      while (Paras.Count > 0) and (Length(Box.Lines) <= NoteMaxLines) do
      begin
        Wrap(TrimRight(Paras[0]));
        Paras.Delete(0);
      end;
      if (Length(Box.Lines) > NoteMaxLines) or (Paras.Count > 0) then
      begin
        SetLength(Box.Lines, Min(Length(Box.Lines), NoteMaxLines));
        Add('…');
      end;
      Box.Top := At;
      { The header line, then the text under a little room. }
      Box.Height := 2 * NotePadY + LineHeight;
      if Length(Box.Lines) > 0 then
        Inc(Box.Height, 4 + Length(Box.Lines) * LineHeight);
      FNoteBoxes[i] := Box;
      Inc(At, Box.Height + NoteGap);
    end;
  finally
    Paras.Free;
  end;
  FNotesHeight := At + Pad div 2;
end;

{ The heading, then a card per note: a stripe in the color of the
  review's outcome, the author in bold, what they did and when, the link
  to GitHub at the right, and the text under them. Y is advanced past
  the section. }
procedure TGittanSummary.PaintNotes(var Y: integer);
var
  i, k, X, LineHeight, At: integer;
  Card: TRect;
  What, Age: string;
  Tone: TColor;
begin
  LayoutNotes;
  if Length(FNoteBoxes) = 0 then
    Exit;
  Canvas.Font := Font;
  LineHeight := Canvas.TextHeight('Xg');
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FDim;
  Canvas.TextOut(Pad, Y, FNotesTitle);
  for i := 0 to High(FNoteBoxes) do
  begin
    At := Y + FNoteBoxes[i].Top;
    Card := Rect(Pad, At, Width - Pad, At + FNoteBoxes[i].Height);
    case FNotes[i].Kind of
      pnApproved:
      begin
        What := rsNoteApproved;
        Tone := FAdded;
      end;
      pnChangesRequested:
      begin
        What := rsNoteChangesRequested;
        Tone := FDeleted;
      end;
      pnDismissed:
      begin
        What := rsNoteDismissed;
        Tone := FDim;
      end;
      else
      begin
        What := rsNoteCommented;
        Tone := FLine;
      end;
    end;
    Canvas.Pen.Color := FLine;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FSelectedBack;
    Canvas.RoundRect(Card, 8, 8);
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Color := Tone;
    Canvas.RoundRect(Card.Left, Card.Top, Card.Left + 2 * NoteStripe, Card.Bottom, 4, 4);
    Canvas.Brush.Color := FSelectedBack;
    Canvas.FillRect(Card.Left + NoteStripe, Card.Top + 1, Card.Left + 2 * NoteStripe,
      Card.Bottom - 1);
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsClear;

    X := Card.Left + NoteStripe + NotePadX;
    At := Card.Top + NotePadY;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := FText;
    Canvas.TextOut(X, At, FNotes[i].Author);
    Inc(X, Canvas.TextWidth(FNotes[i].Author) + Gap div 2);
    Canvas.Font.Style := [];
    if FNotes[i].Kind in [pnApproved, pnChangesRequested] then
      Canvas.Font.Color := Tone
    else
      Canvas.Font.Color := FDim;
    Canvas.TextOut(X, At, What);
    Inc(X, Canvas.TextWidth(What));
    Age := ReviewAge(FNotes[i].Created, LocalTimeToUniversal(Now));
    if Age <> '' then
    begin
      Canvas.Font.Color := FDim;
      Canvas.TextOut(X, At, ' · ' + Age);
    end;
    FNoteBoxes[i].LinkRect := Rect(0, 0, 0, 0);
    if FNotes[i].Url <> '' then
    begin
      FNoteBoxes[i].LinkRect := Rect(Card.Right - NotePadX - Canvas.TextWidth(rsNoteLink),
        At, Card.Right - NotePadX, At + LineHeight);
      Canvas.Font.Color := FLink;
      if i = FLinkHot then
        Canvas.Font.Style := [fsUnderline];
      Canvas.TextOut(FNoteBoxes[i].LinkRect.Left, At, rsNoteLink);
      Canvas.Font.Style := [];
    end;

    Inc(At, LineHeight + 4);
    Canvas.Font.Color := FText;
    X := Card.Left + NoteStripe + NotePadX;
    for k := 0 to High(FNoteBoxes[i].Lines) do
    begin
      Canvas.TextOut(X, At, FNoteBoxes[i].Lines[k]);
      Inc(At, LineHeight);
    end;
  end;
  Inc(Y, FNotesHeight);
end;

function TGittanSummary.LinkAt(X, Y: integer): integer;
var
  i: integer;
begin
  Result := -1;
  for i := 0 to High(FNoteBoxes) do
    if PtInRect(FNoteBoxes[i].LinkRect, Point(X, Y)) then
      Exit(i);
end;

procedure TGittanSummary.SetLinkHot(AValue: integer);
begin
  if FLinkHot = AValue then
    Exit;
  FLinkHot := AValue;
  Invalidate;
end;

procedure TGittanSummary.SetSelected(const AValue: string);
begin
  if FSelected = AValue then
    Exit;
  FSelected := AValue;
  Invalidate;
end;

procedure TGittanSummary.SetNotice(const AValue: string);
begin
  if FNotice = AValue then
    Exit;
  FNotice := AValue;
  UpdateHeight;
  Invalidate;
end;

function TGittanSummary.BranchClickable: boolean;
begin
  Result := Assigned(FOnBranchClick) and (FBranch <> '');
end;

procedure TGittanSummary.SetBaseClickable(AValue: boolean);
begin
  if FBaseClickable = AValue then
    Exit;
  FBaseClickable := AValue;
  Invalidate;
end;

procedure TGittanSummary.SetBaseHot(AValue: boolean);
begin
  if FBaseHot = AValue then
    Exit;
  FBaseHot := AValue;
  if AValue then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  Invalidate;
end;

procedure TGittanSummary.SetBranchHot(AValue: boolean);
begin
  if FBranchHot = AValue then
    Exit;
  FBranchHot := AValue;
  if AValue then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  Invalidate;
end;

function TGittanSummary.RowAt(Y: integer): integer;
begin
  Result := -1;
  if Y < FRowsTop then
    Exit;
  Result := (Y - FRowsTop) div RowHeight;
  if Result > High(FStats) then
    Result := -1;
end;

function TGittanSummary.CommitAt(Y: integer): integer;
begin
  Result := -1;
  if not ShowsCommits or (Y < FCommitsTop) then
    Exit;
  Result := (Y - FCommitsTop) div RowHeight;
  if Result > High(FCommits) then
    Result := -1;
end;

procedure TGittanSummary.SetCommitHot(AValue: integer);
begin
  if FCommitHot = AValue then
    Exit;
  FCommitHot := AValue;
  Invalidate;
end;

procedure TGittanSummary.SetHot(AValue: integer);
begin
  if FHot = AValue then
    Exit;
  FHot := AValue;
  Invalidate;
end;

{ Repository name and branch on one line, the file count and totals on the
  next (the clean state instead, unless it stands in the middle), a
  divider below. Y is advanced past the header. }
procedure TGittanSummary.PaintHeader(var Y: integer);
var
  X, TitleHeight, BodyHeight, TextY, IconW, Added, Deleted, i: integer;
  Heading: string;
begin
  Canvas.Brush.Style := bsClear;
  Canvas.Font := Font;
  BodyHeight := Canvas.TextHeight('Xg');
  Canvas.Font.Size := TitleFontSize;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FText;
  TitleHeight := Canvas.TextHeight('Xg');
  Canvas.TextOut(Pad, Y, FRepoName);
  X := Pad + Canvas.TextWidth(FRepoName) + Gap;
  Canvas.Font.Size := Font.Size;
  Canvas.Font.Style := [];
  FBranchRect := Rect(0, 0, 0, 0);
  { The branch as the status bar shows it: a branch icon, the name in
    the text color, and a dimmed chevron when a click drops the list.
    The chip is filled while the mouse is over it. }
  if FBranch <> '' then
  begin
    TextY := Y + TitleHeight - BodyHeight - 3;
    IconW := BodyHeight - 4 + IconGap;
    if BranchClickable then
    begin
      FBranchRect := Rect(X - ChipPadX, TextY - ChipPadY,
        X + IconW + Canvas.TextWidth(FBranch) + ChevronWidth + ChipPadX,
        TextY + BodyHeight + ChipPadY);
      if FBranchHot then
      begin
        Canvas.Pen.Style := psClear;
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := FHover;
        Canvas.RoundRect(FBranchRect, 8, 8);
        Canvas.Pen.Style := psSolid;
        Canvas.Brush.Style := bsClear;
      end;
    end;
    DrawStatusIcon(Canvas, HintBranch, X, TextY, BodyHeight, FDim);
    Canvas.Pen.Width := 1;
    Canvas.Brush.Style := bsClear;
    Inc(X, IconW);
    Canvas.Font.Color := FText;
    Canvas.TextOut(X, TextY, FBranch);
    Inc(X, Canvas.TextWidth(FBranch));
    if BranchClickable then
    begin
      Inc(X, ChevronWidth div 2 + 1);
      Canvas.Pen.Color := FDim;
      Canvas.Polyline([Point(X - 3, TextY + BodyHeight div 2 - 1),
        Point(X, TextY + BodyHeight div 2 + 2), Point(X + 3, TextY + BodyHeight div 2 - 1)]);
      Inc(X, ChevronWidth div 2 + ChipPadX);
    end;
    Inc(X, Gap);
  end;
  FBaseRect := Rect(0, 0, 0, 0);
  if FBase <> '' then
  begin
    TextY := Y + TitleHeight - BodyHeight - 3;
    { A base with actions is a chip like the branch, with a chevron. }
    if FBaseClickable and Assigned(FOnBaseClick) then
    begin
      FBaseRect := Rect(X - ChipPadX, TextY - ChipPadY,
        X + Canvas.TextWidth(FBase) + ChevronWidth + ChipPadX, TextY + BodyHeight + ChipPadY);
      if FBaseHot then
      begin
        Canvas.Pen.Style := psClear;
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := FHover;
        Canvas.RoundRect(FBaseRect, 8, 8);
        Canvas.Pen.Style := psSolid;
        Canvas.Brush.Style := bsClear;
      end;
    end;
    Canvas.Font.Color := FText;
    Canvas.TextOut(X, TextY, FBase);
    if FBaseRect.Right > FBaseRect.Left then
    begin
      Inc(X, Canvas.TextWidth(FBase) + ChevronWidth div 2 + 1);
      Canvas.Pen.Width := 1;
      Canvas.Pen.Color := FDim;
      Canvas.Polyline([Point(X - 3, TextY + BodyHeight div 2 - 1),
        Point(X, TextY + BodyHeight div 2 + 2), Point(X + 3, TextY + BodyHeight div 2 - 1)]);
    end;
  end;
  Inc(Y, TitleHeight + 6);

  Added := 0;
  Deleted := 0;
  for i := 0 to High(FStats) do
  begin
    Inc(Added, FStats[i].Added);
    Inc(Deleted, FStats[i].Deleted);
  end;
  X := Pad;
  if (Length(FStats) = 0) and not CentersClean then
    PaintCleanHeader(Y);
  if Length(FStats) > 0 then
  begin
    if Length(FStats) = 1 then
      Heading := rsOneFile
    else
      Heading := Format(rsManyFiles, [Length(FStats)]);
    Canvas.Font.Color := FDim;
    Canvas.TextOut(X, Y, Heading);
    Inc(X, Canvas.TextWidth(Heading) + Gap);
    Canvas.Font.Color := FAdded;
    Heading := '+' + IntToStr(Added);
    Canvas.TextOut(X, Y, Heading);
    Inc(X, Canvas.TextWidth(Heading) + Gap div 2);
    Canvas.Font.Color := FDeleted;
    Heading := '−' + IntToStr(Deleted);
    Canvas.TextOut(X, Y, Heading);
    Inc(X, Canvas.TextWidth(Heading) + Gap);
    { The whole change as one bar: the added share in green, the
      deleted in red. }
    if Added + Deleted > 0 then
    begin
      Canvas.Pen.Style := psClear;
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := FDeleted;
      Canvas.RoundRect(X, Y + (BodyHeight - BarHeight) div 2, X + TotalBarWidth,
        Y + (BodyHeight + BarHeight) div 2, BarHeight, BarHeight);
      if Added > 0 then
      begin
        Canvas.Brush.Color := FAdded;
        Canvas.RoundRect(X, Y + (BodyHeight - BarHeight) div 2,
          X + Max(BarHeight, Round(Added / (Added + Deleted) * TotalBarWidth)),
          Y + (BodyHeight + BarHeight) div 2, BarHeight, BarHeight);
      end;
      Canvas.Pen.Style := psSolid;
      Canvas.Brush.Style := bsClear;
      Inc(X, TotalBarWidth + Gap);
    end;
    PaintKinds(Y, X, Width - Pad);
  end;
  Inc(Y, HeaderBlockHeight(Canvas) + Pad div 2);
  Canvas.Pen.Color := FLine;
  Canvas.Line(Pad, Y, Width - Pad, Y);
  Inc(Y, Pad div 2);
end;

{ How many files of each kind, as a dot in the kind's color and a dim
  count, right-aligned at ARight on the line at Y; left out when they
  would not fit between ALeft and ARight. }
procedure TGittanSummary.PaintKinds(Y, ALeft, ARight: integer);
var
  Counts: array[TGittanChangeKind] of integer;
  Kind: TGittanChangeKind;
  i, X, BodyHeight, Total: integer;
  KindText: string;
begin
  for Kind := Low(Kind) to High(Kind) do
    Counts[Kind] := 0;
  for i := 0 to High(FStats) do
    Inc(Counts[FStats[i].Kind]);
  Canvas.Font.Color := FDim;
  BodyHeight := Canvas.TextHeight('Xg');
  Total := 0;
  for Kind := Low(Kind) to High(Kind) do
    if Counts[Kind] > 0 then
      Inc(Total, DotSize + Gap div 2 + Canvas.TextWidth(Format(KindCount[Kind],
        [Counts[Kind]])) + Gap);
  Dec(Total, Gap);
  if (Total <= 0) or (ALeft + Total > ARight) then
    Exit;
  X := ARight - Total;
  for Kind := Low(Kind) to High(Kind) do
    if Counts[Kind] > 0 then
    begin
      Canvas.Pen.Style := psClear;
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := KindColor(Kind);
      Canvas.Ellipse(X, Y + (BodyHeight - DotSize) div 2, X + DotSize,
        Y + (BodyHeight + DotSize) div 2);
      Canvas.Pen.Style := psSolid;
      Canvas.Brush.Style := bsClear;
      Inc(X, DotSize + Gap div 2);
      KindText := Format(KindCount[Kind], [Counts[Kind]]);
      Canvas.TextOut(X, Y, KindText);
      Inc(X, Canvas.TextWidth(KindText) + Gap);
    end;
end;

{ The bars of the rows share the width: a sixth of it, within bounds. }
function TGittanSummary.BarWidth: integer;
begin
  Result := Min(MaxBarWidth, Max(MinBarWidth, Width div 6));
end;

{ An info disc with an "i" and the notice text, in the row above the
  files. Y is advanced past it. }
procedure TGittanSummary.PaintNotice(var Y: integer);
var
  X, CenterY: integer;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  X := Pad;
  CenterY := Y + RowHeight div 2;
  Canvas.Pen.Color := FDim;
  Canvas.Brush.Style := bsClear;
  Canvas.Ellipse(X, CenterY - CheckSize div 2, X + CheckSize, CenterY + CheckSize div 2);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FDim;
  Canvas.TextOut(X + (CheckSize - Canvas.TextWidth('i')) div 2,
    CenterY - Canvas.TextHeight('i') div 2, 'i');
  Canvas.Font.Style := [];
  Canvas.TextOut(X + CheckSize + Gap div 2 + 2,
    CenterY - Canvas.TextHeight('Xg') div 2, FNotice);
  Inc(Y, RowHeight);
end;

{ The bar compares this file's change with the largest one: the added part
  in green, the deleted part in red, the rest of the track in the line
  color. A change too small for a pixel still gets one. }
procedure TGittanSummary.PaintBar(X, Y: integer; const AStat: TGittanFileStat;
  AMax: integer);
var
  AddedWidth, DeletedWidth: integer;
begin
  Canvas.Pen.Style := psClear;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FLine;
  Canvas.RoundRect(X, Y, X + BarWidth, Y + BarHeight, BarHeight, BarHeight);
  if AMax = 0 then
    Exit;
  AddedWidth := Round(AStat.Added / AMax * BarWidth);
  if (AStat.Added > 0) and (AddedWidth < 2) then
    AddedWidth := 2;
  DeletedWidth := Round(AStat.Deleted / AMax * BarWidth);
  if (AStat.Deleted > 0) and (DeletedWidth < 2) then
    DeletedWidth := 2;
  DeletedWidth := Min(DeletedWidth, BarWidth - AddedWidth);
  if AddedWidth > 0 then
  begin
    Canvas.Brush.Color := FAdded;
    Canvas.RoundRect(X, Y, X + AddedWidth, Y + BarHeight, BarHeight, BarHeight);
  end;
  if DeletedWidth > 0 then
  begin
    Canvas.Brush.Color := FDeleted;
    Canvas.RoundRect(X + AddedWidth, Y, X + AddedWidth + DeletedWidth,
      Y + BarHeight, BarHeight, BarHeight);
  end;
  Canvas.Pen.Style := psSolid;
end;

{ Badge, directory in dim and file name in full color, then the counts and
  the bar on the right. A path too long for the room loses its directory
  first, then its end. }
procedure TGittanSummary.PaintRow(AIndex, ATop: integer);
var
  Stat: TGittanFileStat;
  X, CountsX, TextY, BodyHeight, Room, MaxChange, i: integer;
  Dir, FileName, Count, RowText: string;
begin
  Stat := FStats[AIndex];
  Canvas.Font := Font;
  BodyHeight := Canvas.TextHeight('Xg');
  TextY := ATop + (RowHeight - BodyHeight) div 2;
  if (AIndex = FHot) or (Stat.Path = FSelected) then
  begin
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    if AIndex = FHot then
      Canvas.Brush.Color := FHover
    else
      Canvas.Brush.Color := FSelectedBack;
    Canvas.RoundRect(Pad div 2, ATop, Width - Pad div 2, ATop + RowHeight, 8, 8);
    Canvas.Pen.Style := psSolid;
  end;
  X := Pad;
  if (FImages <> nil) and (AIndex <= High(FIconIndex)) then
    FImages.DrawForPPI(Canvas, X, ATop + (RowHeight - IconSize) div 2,
      FIconIndex[AIndex], IconSize, Font.PixelsPerInch, GetCanvasScaleFactor);
  Inc(X, IconSize + Gap div 2 + 2);

  CountsX := Width - Pad - BarWidth - Gap - 2 * CountWidth - Gap div 2;
  RowText := '';
  if AIndex <= High(FRowTexts) then
    RowText := FRowTexts[AIndex];
  if RowText <> '' then
    CountsX := Min(CountsX, Width - Pad - Canvas.TextWidth(RowText));
  Room := CountsX - Gap - X;
  Dir := ExtractFilePath(Stat.Path);
  FileName := ExtractFileName(Stat.Path);
  Canvas.Brush.Style := bsClear;
  if Canvas.TextWidth(Dir + FileName) > Room then
    Dir := '';
  while (FileName <> '') and (Canvas.TextWidth(FileName + '…') > Room) do
  begin
    FileName := Copy(FileName, 1, Length(FileName) - 1);
    { Keep UTF-8 sequences whole. }
    while (FileName <> '') and (Ord(FileName[Length(FileName)]) and $C0 = $80) do
      FileName := Copy(FileName, 1, Length(FileName) - 1);
    if FileName = ExtractFileName(Stat.Path) then
      Break;
  end;
  if FileName <> ExtractFileName(Stat.Path) then
    FileName := FileName + '…';
  if Dir <> '' then
  begin
    Canvas.Font.Color := FDim;
    Canvas.TextOut(X, TextY, Dir);
    Inc(X, Canvas.TextWidth(Dir));
  end;
  Canvas.Font.Color := FText;
  Canvas.TextOut(X, TextY, FileName);
  Inc(X, Canvas.TextWidth(FileName) + Gap);
  { What the index holds, when the path left room for it. }
  if Stat.Staged then
  begin
    if Stat.Unstaged then
      Count := rsPartlyStaged
    else
      Count := rsStaged;
    if X + Canvas.TextWidth(Count) <= CountsX - Gap then
    begin
      Canvas.Font.Color := FDim;
      Canvas.TextOut(X, TextY, Count);
    end;
  end;

  if RowText <> '' then
  begin
    Canvas.Font.Color := FDim;
    Canvas.TextOut(Width - Pad - Canvas.TextWidth(RowText), TextY, RowText);
    Exit;
  end;
  if Stat.Binary then
  begin
    Canvas.Font.Color := FDim;
    Canvas.TextOut(CountsX + 2 * CountWidth + Gap div 2 - Canvas.TextWidth(rsBinary),
      TextY, rsBinary);
  end
  else
  begin
    { A zero is shown, so the columns stay aligned, but dimmed. }
    if Stat.Added > 0 then
      Canvas.Font.Color := FAdded
    else
      Canvas.Font.Color := FDim;
    Count := '+' + IntToStr(Stat.Added);
    Canvas.TextOut(CountsX + CountWidth - Canvas.TextWidth(Count), TextY, Count);
    if Stat.Deleted > 0 then
      Canvas.Font.Color := FDeleted
    else
      Canvas.Font.Color := FDim;
    Count := '−' + IntToStr(Stat.Deleted);
    Canvas.TextOut(CountsX + 2 * CountWidth + Gap div 2 - Canvas.TextWidth(Count),
      TextY, Count);
  end;

  MaxChange := 0;
  for i := 0 to High(FStats) do
    if (i > High(FRowTexts)) or (FRowTexts[i] = '') then
      MaxChange := Max(MaxChange, FStats[i].Added + FStats[i].Deleted);
  PaintBar(Width - Pad - BarWidth, ATop + (RowHeight - BarHeight) div 2, Stat,
    MaxChange);
end;

{ A green disc ASize across at X, Y with a check mark cut out of it. }
procedure TGittanSummary.DrawCheck(X, Y, ASize: integer);
var
  CenterY: integer;
begin
  CenterY := Y + ASize div 2;
  Canvas.Pen.Style := psClear;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FAdded;
  Canvas.Ellipse(X, Y, X + ASize, Y + ASize);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := FBack;
  Canvas.Pen.Width := Max(2, ASize div 10);
  Canvas.Polyline([Point(X + ASize * 27 div 100, CenterY),
    Point(X + ASize * 44 div 100, CenterY + ASize * 17 div 100),
    Point(X + ASize * 74 div 100, CenterY - ASize * 17 div 100)]);
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
end;

{ The clean state in the header, in place of the totals: a large check,
  the clean text larger than the body, and how far the branch is from
  its upstream under it, so the state of the tree reads before the
  commits below it. }
procedure TGittanSummary.PaintCleanHeader(Y: integer);
var
  X, BlockHeight, BodyHeight, TextHeight, TextY: integer;
begin
  BlockHeight := HeaderBlockHeight(Canvas);
  Canvas.Font := Font;
  BodyHeight := Canvas.TextHeight('Xg');
  Canvas.Font.Size := CleanFontSize;
  TextHeight := Canvas.TextHeight('Xg');
  DrawCheck(Pad, Y + (BlockHeight - HeaderCheck) div 2, HeaderCheck);
  X := Pad + HeaderCheck + Gap;
  TextY := Y + (BlockHeight - TextHeight - IfThen(FHasUpstream, 2 + BodyHeight, 0)) div 2;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := FText;
  Canvas.TextOut(X, TextY, CleanText);
  Canvas.Font := Font;
  PaintSync(X, TextY + TextHeight + 2);
end;

{ The clean state alone, when there is nothing to list: a check as large
  as the empty view's icon, the clean text and the sync line under it,
  centered in the control, below the header. }
procedure TGittanSummary.PaintCleanCentered;
var
  BlockTop, CenterX, TextHeight: integer;
begin
  BlockTop := Max(FRowsTop + Pad, (Height - CenterBlockHeight(Canvas)) div 2);
  CenterX := Width div 2;
  DrawCheck(CenterX - CenterCheck div 2, BlockTop, CenterCheck);
  Inc(BlockTop, CenterCheck + Gap);
  Canvas.Font := Font;
  Canvas.Font.Size := CleanFontSize;
  Canvas.Font.Color := FText;
  Canvas.Brush.Style := bsClear;
  TextHeight := Canvas.TextHeight('Xg');
  Canvas.TextOut(CenterX - Canvas.TextWidth(CleanText) div 2, BlockTop, CleanText);
  Inc(BlockTop, TextHeight + 4);
  Canvas.Font := Font;
  PaintSync(CenterX - PaintSync(0, 0, False) div 2, BlockTop);
end;

{ How far the branch is from its upstream at X: the commits not pushed
  in the color their dots have in the list, the ones not pulled in the
  text color, or that there is nothing to either, the parts apart by
  dots. Nothing without an upstream. Returns the width; ADraw False only
  measures. }
function TGittanSummary.PaintSync(X, Y: integer; ADraw: boolean): integer;
var
  StartX: integer;

  procedure Part(const AText: string; AColor: TColor);
  begin
    if X > StartX then
    begin
      if ADraw then
      begin
        Canvas.Font.Color := FDim;
        Canvas.TextOut(X, Y, ' · ');
      end;
      Inc(X, Canvas.TextWidth(' · '));
    end;
    if ADraw then
    begin
      Canvas.Font.Color := AColor;
      Canvas.TextOut(X, Y, AText);
    end;
    Inc(X, Canvas.TextWidth(AText));
  end;

begin
  StartX := X;
  Canvas.Brush.Style := bsClear;
  if FHasUpstream and FUpstreamGone then
    Part(rsUpstreamGone, FDeleted)
  else if FHasUpstream then
  begin
    if FAhead > 0 then
      Part('↑ ' + Format(rsNotPushed, [FAhead]), FLink);
    if FBehind > 0 then
      Part('↓ ' + Format(rsNotPulled, [FBehind]), FText);
    if (FAhead = 0) and (FBehind = 0) then
      Part(rsInSync, FDim);
  end;
  Result := X - StartX;
end;

{ The heading, then a row per commit, the dots joined by a line down the
  icon column so they read as a history. The short ids line up at the
  right, as wide as the widest. }
procedure TGittanSummary.PaintCommits;
var
  i, HashWidth, BodyHeight, LineX: integer;
begin
  Canvas.Font := Font;
  BodyHeight := Canvas.TextHeight('Xg');
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FDim;
  Canvas.TextOut(Pad, FCommitsTop - NoteGap - BodyHeight, rsRecentCommits);
  Canvas.Font.Style := [];
  HashWidth := 0;
  for i := 0 to High(FCommits) do
    HashWidth := Max(HashWidth, Canvas.TextWidth(FCommits[i].Short));
  for i := 0 to High(FCommits) do
    if i = FCommitHot then
    begin
      Canvas.Pen.Style := psClear;
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := FHover;
      Canvas.RoundRect(Pad div 2, FCommitsTop + i * RowHeight, Width - Pad div 2,
        FCommitsTop + (i + 1) * RowHeight, 8, 8);
      Canvas.Pen.Style := psSolid;
    end;
  if Length(FCommits) > 1 then
  begin
    LineX := Pad + IconSize div 2;
    Canvas.Pen.Color := FLine;
    Canvas.Pen.Width := 2;
    Canvas.Line(LineX, FCommitsTop + RowHeight div 2, LineX,
      FCommitsTop + High(FCommits) * RowHeight + RowHeight div 2);
    Canvas.Pen.Width := 1;
  end;
  for i := 0 to High(FCommits) do
    PaintCommit(i, FCommitsTop + i * RowHeight, HashWidth);
end;

{ A dot on the line, filled in the link color when the commit is not
  pushed, a ring otherwise; the subject, cut to fit with an ellipsis;
  the author and age dimmed, dropped when the subject would get too
  little room; the short id at the right. }
procedure TGittanSummary.PaintCommit(AIndex, ATop, AHashWidth: integer);
var
  Commit: TGittanCommitLine;
  X, CenterX, CenterY, TextY, Right, Room, n: integer;
  Meta, Subject: string;
begin
  Commit := FCommits[AIndex];
  Canvas.Font := Font;
  TextY := ATop + (RowHeight - Canvas.TextHeight('Xg')) div 2;
  CenterX := Pad + IconSize div 2;
  CenterY := ATop + RowHeight div 2;
  Canvas.Brush.Style := bsSolid;
  if Commit.Unpushed then
  begin
    Canvas.Pen.Color := FLink;
    Canvas.Brush.Color := FLink;
  end
  else
  begin
    Canvas.Pen.Color := FDim;
    if AIndex = FCommitHot then
      Canvas.Brush.Color := FHover
    else
      Canvas.Brush.Color := FBack;
  end;
  Canvas.Pen.Width := 2;
  Canvas.Ellipse(CenterX - DotSize div 2 - 1, CenterY - DotSize div 2 - 1,
    CenterX + DotSize div 2 + 1, CenterY + DotSize div 2 + 1);
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;

  Right := Width - Pad;
  Canvas.Font.Color := FDim;
  Canvas.TextOut(Right - Canvas.TextWidth(Commit.Short), TextY, Commit.Short);
  Dec(Right, AHashWidth + Gap + Gap div 2);

  X := Pad + IconSize + Gap div 2 + 2;
  Meta := Commit.Author;
  if Commit.Date > 0 then
  begin
    if Meta <> '' then
      Meta := Meta + ' · ';
    Meta := Meta + ReviewAge(Commit.Date, LocalTimeToUniversal(Now));
  end;
  if Right - Canvas.TextWidth(Meta) - Gap - X < Width div 3 then
    Meta := ReviewAge(Commit.Date, LocalTimeToUniversal(Now));
  if Right - Canvas.TextWidth(Meta) - Gap - X < Width div 4 then
    Meta := '';
  if Meta <> '' then
  begin
    Canvas.TextOut(Right - Canvas.TextWidth(Meta), TextY, Meta);
    Dec(Right, Canvas.TextWidth(Meta) + Gap + Gap div 2);
  end;

  Room := Right - X;
  Subject := Commit.Subject;
  if Canvas.TextWidth(Subject) > Room then
  begin
    n := UTF8Length(Subject);
    while (n > 0) and (Canvas.TextWidth(UTF8Copy(Subject, 1, n) + '…') > Room) do
      Dec(n);
    Subject := TrimRight(UTF8Copy(Subject, 1, n)) + '…';
  end;
  Canvas.Font.Color := FText;
  Canvas.TextOut(X, TextY, Subject);
end;

procedure TGittanSummary.Paint;
var
  Y, i: integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  Y := Pad;
  PaintHeader(Y);
  if FNotice <> '' then
    PaintNotice(Y);
  PaintNotes(Y);
  if Y <> FRowsTop then
  begin
    FRowsTop := Y;
    PlaceCommits;
    Height := Max(FContentHeight, Constraints.MinHeight);
  end;
  if CentersClean then
    PaintCleanCentered;
  if ShowsCommits then
    PaintCommits;
  for i := 0 to High(FStats) do
    PaintRow(i, FRowsTop + i * RowHeight);
end;

procedure TGittanSummary.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(RowAt(Y));
  SetCommitHot(CommitAt(Y));
  SetLinkHot(LinkAt(X, Y));
  SetBranchHot(BranchClickable and PtInRect(FBranchRect, Point(X, Y)));
  SetBaseHot((FBaseRect.Right > FBaseRect.Left) and PtInRect(FBaseRect, Point(X, Y)));
  if FLinkHot >= 0 then
    Cursor := crHandPoint
  else if not (FBranchHot or FBaseHot) then
    Cursor := crDefault;
end;

procedure TGittanSummary.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1);
  SetCommitHot(-1);
  SetLinkHot(-1);
  SetBranchHot(False);
  SetBaseHot(False);
end;

procedure TGittanSummary.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Row: integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button = mbLeft) and BranchClickable and PtInRect(FBranchRect, Point(X, Y)) then
  begin
    FOnBranchClick(Self, Rect(ClientToScreen(FBranchRect.TopLeft).X,
      ClientToScreen(FBranchRect.TopLeft).Y, ClientToScreen(FBranchRect.BottomRight).X,
      ClientToScreen(FBranchRect.BottomRight).Y));
    Exit;
  end;
  if (Button = mbLeft) and (FBaseRect.Right > FBaseRect.Left) and Assigned(FOnBaseClick) and
    PtInRect(FBaseRect, Point(X, Y)) then
  begin
    FOnBaseClick(Self, Rect(ClientToScreen(FBaseRect.TopLeft).X,
      ClientToScreen(FBaseRect.TopLeft).Y, ClientToScreen(FBaseRect.BottomRight).X,
      ClientToScreen(FBaseRect.BottomRight).Y));
    Exit;
  end;
  if (Button = mbLeft) and Assigned(FOnOpenUrl) and (LinkAt(X, Y) >= 0) then
  begin
    FOnOpenUrl(Self, FNotes[LinkAt(X, Y)].Url);
    Exit;
  end;
  Row := CommitAt(Y);
  if (Row >= 0) and (Button = mbLeft) and Assigned(FOnSelectCommit) then
  begin
    FOnSelectCommit(Self, FCommits[Row].Hash);
    Exit;
  end;
  Row := RowAt(Y);
  if Row < 0 then
    Exit;
  if (Button = mbLeft) and Assigned(FOnSelectFile) then
    FOnSelectFile(Self, FStats[Row].Path)
  else if (Button = mbRight) and Assigned(FOnContextFile) then
    FOnContextFile(Self, FStats[Row].Path, ClientToScreen(Point(X, Y)));
end;

end.
