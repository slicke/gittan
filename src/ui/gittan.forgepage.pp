unit gittan.forgepage;

{** The forge page: the user's pull requests across every repository
  of a forge (gittan.forge; its name from SetForge), a section at a
  time (Section, the owner's tabs, SectionCaption): the open ones they
  wrote, or the open ones waiting for their review, no wider than
  MaxContentWidth, centered in a wider page.
  A card has a pull request glyph (in the ok color, dim for a draft),
  the number and the title, at the right its state (Draft, Approved,
  Changes requested, Review required) and its checks as chips, "Asked
  again" on one the user is asked to review once more after reviewing
  it, and under them the repository, who opened it and how long ago it
  was opened and last changed, with a link to the forge at the right
  end while the card is under the mouse, and under that link one to
  the pull request's local clone (its Clone) when it is not the open
  repository (SetOpenRoot). A checkbox at the right of the left
  section's heading, or under it when it does not fit there, leaves out
  the user's pull requests nobody but them has commented on or reviewed
  (HideWithoutFeedback, OnHideChange). A card fills under the mouse
  and a click raises OnPick with the pull request, as one on its
  clone's link does, for the owner to compare with it when it is the
  open repository's, else in its clone, else to open it on the forge.
  An empty section says so in a card of its own with a large dim glyph.
  The head has the login's initial in a disc, the forge's name and the
  page's title with Refresh (OnRefresh) after them, a dot pulsing in
  its place while the forge is asked, and under them the login with the
  counts, or that the forge is asked; the forge's failure (not logged
  in) shows in the error color.

  It paints itself in the editor's palette, like the Pull Requests
  page, and sizes its height to its content so it can sit in the same
  TScrollBox: Layout paints the content on a measuring canvas to know
  the height before the control is shown. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, ExtCtrls, gittan.forge, gittan.summary;

const
  {** The sections: the user's open pull requests and those waiting for
    their review. }
  fsMine = 0;
  fsReview = 1;
  SectionCount = 2;

type
  {** A click on a card: the pull request. }
  TGittanForgePickEvent = procedure(Sender: TObject; const APull: TGittanForgePull) of object;

  { TGittanForgePage }

  TGittanForgePage = class(TCustomControl)
  private
    FForge, FLogin, FError, FOpenRoot: string;
    FMine, FReview: TGittanForgePulls;
    { FMine as shown: without the ones with no feedback while FHide. }
    FShownMine: TGittanForgePulls;
    FHide: boolean;
    { The section shown: fsMine or fsReview. }
    FSection: integer;
    { FLoading while the forge is asked; FAnswered once it has answered,
      so an empty section says so only then. }
    FLoading, FAnswered: boolean;
    FBack, FText, FDim, FHover, FLine, FLink, FOk, FWarn, FErrorColor, FCard: TColor;
    FLinkRects: array of TRect;
    FLinkUrls: array of string;
    FHot: integer;
    FContentHeight: integer;
    { The dot that pulses in Refresh's place while the forge is asked:
      its timer, its step and where it is painted. }
    FPulse: TTimer;
    FPhase: integer;
    FDotRect: TRect;
    { The canvas the content is painted on: the control's in Paint, a
      measuring one in Layout. }
    FC: TCanvas;
    FOnPick: TGittanForgePickEvent;
    FOnRefresh, FOnHideChange: TNotifyEvent;
    FOnOpenUrl: TGittanOpenUrlEvent;
    function LinkAt(X, Y: integer): integer;
    procedure SetHot(AValue: integer);
    procedure SetHide(AValue: boolean);
    procedure SetSection(AValue: integer);
    procedure PulseTimer(Sender: TObject);
    procedure AddLink(const ARect: TRect; const AUrl: string);
    procedure PaintAvatar(ALeft, ATop, ASize: integer);
    procedure PaintRefresh(ALeft, ATop, ASize: integer);
    procedure PaintPullGlyph(ALeft, ATop, ASize: integer; AColor: TColor);
    procedure PaintCheckGlyph(ALeft, ATop, ASize: integer; AColor: TColor);
    procedure PaintHeading(var Y: integer; const ATitle, ADetail: string; AToggle: boolean;
      ALeft, ARight: integer);
    function ToggleWidth(const ACaption: string): integer;
    procedure PaintToggle(ALeft, ATop: integer; const ACaption, ALink: string;
      AChecked: boolean);
    procedure PaintNote(var Y: integer; const AText: string; AColor: TColor;
      ALeft, ARight: integer);
    procedure PaintEmpty(var Y: integer; const ATitle, AText: string; ACheck: boolean;
      ALeft, ARight: integer);
    function PaintChip(ARight, ATop: integer; const AText: string; AColor: TColor): integer;
    procedure PaintCard(var Y: integer; const APull: TGittanForgePull; ALeft, ARight: integer;
      const ALink: string);
    function PullLine(const APull: TGittanForgePull): string;
    procedure PaintSection(var Y: integer; const ATitle: string; const APulls: TGittanForgePulls;
      ATotal: integer; const AEmptyTitle, AEmpty, ALinkPrefix: string; AEmptyCheck,
      AToggle: boolean; ALeft, ARight: integer);
    procedure PaintContent;
    procedure Layout;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    constructor Create(AOwner: TComponent); override;
    {** The forge shown, by name: the page's title and its links. }
    procedure SetForge(const AName: string);
    {** The login the forge knows the user as; empty before it answered. }
    procedure SetLogin(const ALogin: string);
    {** The root of the open repository, empty when none is open: a card
      whose clone it is has no link to it, since its click compares
      there. }
    procedure SetOpenRoot(const ARoot: string);
    {** The pull requests the user wrote and those waiting for their
      review, the forge's message when it failed (else ''), and whether
      it is being asked now. }
    procedure SetPulls(const AMine, AReview: TGittanForgePulls; const AError: string;
      ALoading: boolean);
    {** The palette: the background, the text, the dim text, the fill
      under the mouse, the dividers, the links, the ok, the warning and
      the error colors. }
    procedure SetColors(ABack, AText, ADim, AHover, ALine, ALink, AOk, AWarn, AError: TColor);
    {** The fill of the cards. }
    procedure SetCardColor(ACard: TColor);
    {** The palette of the dark or the light appearance: the editor's
      background and text, the dim text, the hover, the dividers, the
      link color and the ok, warning and error tones the Pull Requests
      page has, and the cards' fill. }
    procedure SetTheme(ADark: boolean);
    {** Makes the control at least AMin high (the height of the box it
      sits in, so its background covers the box), and no higher than its
      content needs beyond that. }
    procedure FitHeight(AMin: integer);
    {** Whether the user's pull requests that nobody but them has
      commented on or reviewed are left out; the checkbox sets it and
      raises OnHideChange. }
    property HideWithoutFeedback: boolean read FHide write SetHide;
    {** The section shown, fsMine (the default) or fsReview. }
    property Section: integer read FSection write SetSection;
    property OnHideChange: TNotifyEvent read FOnHideChange write FOnHideChange;
    property OnPick: TGittanForgePickEvent read FOnPick write FOnPick;
    property OnRefresh: TNotifyEvent read FOnRefresh write FOnRefresh;
    property OnOpenUrl: TGittanOpenUrlEvent read FOnOpenUrl write FOnOpenUrl;
  end;

{** A section's name, for its tab. }
function SectionCaption(ASection: integer): string;

implementation

uses
  Math, DateUtils, LCLIntf, LCLType, gittan.reviews, gittan.textfit, gittan.theme;

resourcestring
  rsPageTitle = 'Pull requests';
  rsMineTab = 'Open';
  rsReviewTab = 'Waiting for review';
  rsMineGroup = 'Your open pull requests';
  rsReviewGroup = 'Waiting for your review';
  rsOneOpen = '1 open';
  rsManyOpen = '%d open';
  rsSomeOpen = '%d of %d open';
  rsToReview = '%d to review';
  rsHideQuiet = 'Only with feedback';
  rsNoFeedback = 'Nobody has commented on or reviewed any of them yet.';
  rsLoading = 'Asking %s…';
  rsNoMine = 'No open pull requests of yours.';
  rsCaughtUp = 'All caught up';
  rsNoReview = 'Nothing waiting for your review.';
  rsForgeLink = '%s ↗';
  rsCloneLink = 'Open %s';
  rsDraft = 'Draft';
  rsApproved = 'Approved';
  rsChangesRequested = 'Changes requested';
  rsReviewRequired = 'Review required';
  rsAskedAgain = 'Asked again';
  rsChecksOk = '✓ checks';
  rsChecksFailing = 'checks failing';
  rsChecksPending = 'checks pending';
  rsOpened = 'opened %s';
  rsUpdated = 'updated %s';

const
  MineLink = 'gittan:mine:';
  ReviewLink = 'gittan:review:';
  RefreshLink = 'gittan:refresh';
  HideLink = 'gittan:hide';
  RefreshGlyph = '↻';
  Pad = 24;
  Gap = 12;
  TitleFontSize = 20;
  { The content no wider than this, centered in a wider page. }
  MaxContentWidth = 960;
  { The cards: their padding and corner radius; the chips at their
    right; the room between the glyph and the text. }
  CardPadX = 14;
  CardPadY = 10;
  CardRadius = 12;
  CardGap = 8;
  GlyphGap = 10;
  ChipPadX = 6;
  ChipPadY = 2;
  ChipRadius = 6;
  { An empty section's card: its glyph and the room above and below. }
  EmptyGlyph = 30;
  EmptyPadY = 22;
  { The checkbox: the corner radius of its box. }
  BoxRadius = 4;
  { The dot pulsing while the forge is asked: its size, its timer's
    step and the steps of one pulse. }
  DotSize = 8;
  PulseStep = 40;
  PulseSteps = 36;

function SectionCaption(ASection: integer): string;
begin
  if ASection = fsReview then
    Result := rsReviewTab
  else
    Result := rsMineTab;
end;

{ TGittanForgePage }

constructor TGittanForgePage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FHot := -1;
  Align := alTop;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnShadow, clHighlight,
    clGreen, clOlive, clRed);
  FCard := clBtnFace;
  FPulse := TTimer.Create(Self);
  FPulse.Enabled := False;
  FPulse.Interval := PulseStep;
  FPulse.OnTimer := @PulseTimer;
end;

procedure TGittanForgePage.SetForge(const AName: string);
begin
  FForge := AName;
  Layout;
  Invalidate;
end;

procedure TGittanForgePage.SetLogin(const ALogin: string);
begin
  if FLogin = ALogin then
    Exit;
  FLogin := ALogin;
  Layout;
  Invalidate;
end;

procedure TGittanForgePage.SetOpenRoot(const ARoot: string);
begin
  if FOpenRoot = ARoot then
    Exit;
  FOpenRoot := ARoot;
  Layout;
  Invalidate;
end;

procedure TGittanForgePage.SetPulls(const AMine, AReview: TGittanForgePulls;
  const AError: string; ALoading: boolean);
begin
  FMine := Copy(AMine);
  FReview := Copy(AReview);
  FError := AError;
  FLoading := ALoading;
  FAnswered := FAnswered or not ALoading;
  FHot := -1;
  FPhase := 0;
  FPulse.Enabled := ALoading;
  Layout;
  Invalidate;
end;

procedure TGittanForgePage.SetHide(AValue: boolean);
begin
  if FHide = AValue then
    Exit;
  FHide := AValue;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanForgePage.SetSection(AValue: integer);
begin
  if FSection = AValue then
    Exit;
  FSection := AValue;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanForgePage.PulseTimer(Sender: TObject);
begin
  FPhase := (FPhase + 1) mod PulseSteps;
  if HandleAllocated then
    InvalidateRect(Handle, @FDotRect, False);
end;

procedure TGittanForgePage.SetColors(ABack, AText, ADim, AHover, ALine, ALink, AOk, AWarn,
  AError: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
  FLine := ALine;
  FLink := ALink;
  FOk := AOk;
  FWarn := AWarn;
  FErrorColor := AError;
  Color := ABack;
  Invalidate;
end;

procedure TGittanForgePage.SetCardColor(ACard: TColor);
begin
  FCard := ACard;
  Invalidate;
end;

procedure TGittanForgePage.SetTheme(ADark: boolean);
begin
  if ADark then
  begin
    SetColors(RGBToColor(30, 30, 30), RGBToColor(224, 224, 224), RGBToColor(150, 150, 150),
      RGBToColor(50, 50, 51), RGBToColor(62, 62, 62), RGBToColor(78, 161, 255),
      RGBToColor(63, 185, 80), RGBToColor(227, 179, 65), RGBToColor(248, 81, 73));
    SetCardColor(RGBToColor(40, 40, 41));
  end
  else
  begin
    SetColors(clWhite, RGBToColor(30, 30, 30), RGBToColor(110, 110, 110),
      RGBToColor(235, 235, 235), RGBToColor(222, 222, 222), RGBToColor(0, 102, 204),
      RGBToColor(26, 127, 55), RGBToColor(154, 103, 0), RGBToColor(207, 34, 46));
    SetCardColor(RGBToColor(245, 245, 246));
  end;
end;

procedure TGittanForgePage.FitHeight(AMin: integer);
begin
  Constraints.MinHeight := AMin;
  Layout;
end;

{ The content painted on the measuring canvas, for its height; the
  height is set here, never in Paint. }
procedure TGittanForgePage.Layout;
var
  H: integer;
begin
  if (Parent = nil) or (Width <= 0) then
    Exit;
  FC := MeasureCanvas(Font);
  PaintContent;
  H := Max(FContentHeight, Constraints.MinHeight);
  if Height <> H then
    Height := H;
  Invalidate;
end;

procedure TGittanForgePage.Resize;
begin
  inherited Resize;
  Layout;
end;

function TGittanForgePage.LinkAt(X, Y: integer): integer;
var
  i: integer;
begin
  { The last link added wins: the forge link lies on its card. }
  for i := High(FLinkRects) downto 0 do
    if PtInRect(FLinkRects[i], Point(X, Y)) then
      Exit(i);
  Result := -1;
end;

procedure TGittanForgePage.SetHot(AValue: integer);
begin
  if FHot = AValue then
    Exit;
  FHot := AValue;
  if AValue < 0 then
    Cursor := crDefault
  else
    Cursor := crHandPoint;
  Invalidate;
end;

procedure TGittanForgePage.AddLink(const ARect: TRect; const AUrl: string);
begin
  SetLength(FLinkRects, Length(FLinkRects) + 1);
  SetLength(FLinkUrls, Length(FLinkUrls) + 1);
  FLinkRects[High(FLinkRects)] := ARect;
  FLinkUrls[High(FLinkUrls)] := AUrl;
end;

{ A disc ASize across with the login's initial in it, in the link
  color; empty in the hover fill before the forge has said who. }
procedure TGittanForgePage.PaintAvatar(ALeft, ATop, ASize: integer);
var
  Initial: string;
begin
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  if FLogin <> '' then
    FC.Brush.Color := FLink
  else
    FC.Brush.Color := FHover;
  FC.Ellipse(ALeft, ATop, ALeft + ASize, ATop + ASize);
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;
  if FLogin = '' then
    Exit;
  Initial := UpperCase(Copy(FLogin, 1, 1));
  FC.Font := Font;
  FC.Font.Height := -ASize div 2;
  FC.Font.Style := [fsBold];
  FC.Font.Color := clWhite;
  FC.TextOut(ALeft + (ASize - FC.TextWidth(Initial)) div 2,
    ATop + (ASize - FC.TextHeight(Initial)) div 2, Initial);
  FC.Font := Font;
end;

{ Refresh as a round button ASize across, filled under the mouse; while
  the forge is asked, a dot pulsing in its place instead. }
procedure TGittanForgePage.PaintRefresh(ALeft, ATop, ASize: integer);
var
  R: TRect;
  D: integer;
begin
  R := Rect(ALeft, ATop, ALeft + ASize, ATop + ASize);
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  if FLoading then
  begin
    FDotRect := R;
    D := Px(DotSize);
    FC.Pen.Style := psClear;
    FC.Brush.Style := bsSolid;
    FC.Brush.Color := MixColor(FHover, FLink,
      0.25 + 0.75 * (1 - Cos(2 * Pi * FPhase / PulseSteps)) / 2);
    FC.Ellipse(R.Left + (ASize - D) div 2, R.Top + (ASize - D) div 2,
      R.Left + (ASize - D) div 2 + D, R.Top + (ASize - D) div 2 + D);
    FC.Pen.Style := psSolid;
    FC.Brush.Style := bsClear;
    Exit;
  end;
  if not Assigned(FOnRefresh) then
    Exit;
  AddLink(R, RefreshLink);
  FC.Font.Color := FDim;
  if FHot = High(FLinkRects) then
  begin
    FC.Pen.Style := psClear;
    FC.Brush.Style := bsSolid;
    FC.Brush.Color := FHover;
    FC.Ellipse(R);
    FC.Pen.Style := psSolid;
    FC.Brush.Style := bsClear;
    FC.Font.Color := FText;
  end;
  FC.TextOut(R.Left + (ASize - FC.TextWidth(RefreshGlyph)) div 2,
    R.Top + (ASize - FC.TextHeight(RefreshGlyph)) div 2, RefreshGlyph);
end;

{ A pull request glyph in a square ASize across: at the left a branch
  between two rings, at the right a ring with a line up from it that
  turns left into an arrow. }
procedure TGittanForgePage.PaintPullGlyph(ALeft, ATop, ASize: integer; AColor: TColor);
var
  W, Rad, X1, X2, YT, YB, XA, A: integer;
begin
  W := Max(1, ASize div 12);
  Rad := Max(2, ASize * 3 div 20);
  X1 := ALeft + ASize div 5;
  X2 := ALeft + ASize * 4 div 5;
  YT := ATop + Rad + W;
  YB := ATop + ASize - Rad - W;
  XA := (X1 + X2) div 2 + W;
  A := Max(2, ASize div 6);
  FC.Pen.Style := psSolid;
  FC.Pen.Color := AColor;
  FC.Pen.Width := W;
  FC.Brush.Style := bsClear;
  FC.Ellipse(X1 - Rad, YT - Rad, X1 + Rad + 1, YT + Rad + 1);
  FC.Ellipse(X1 - Rad, YB - Rad, X1 + Rad + 1, YB + Rad + 1);
  FC.Line(X1, YT + Rad, X1, YB - Rad);
  FC.Ellipse(X2 - Rad, YB - Rad, X2 + Rad + 1, YB + Rad + 1);
  FC.Line(X2, YB - Rad, X2, YT);
  FC.Line(X2, YT, XA, YT);
  FC.Line(XA, YT, XA + A, YT - A);
  FC.Line(XA, YT, XA + A, YT + A);
  FC.Pen.Width := 1;
end;

{ A check in a ring ASize across. }
procedure TGittanForgePage.PaintCheckGlyph(ALeft, ATop, ASize: integer; AColor: TColor);
var
  W: integer;
begin
  W := Max(1, Round(ASize / 12));
  FC.Pen.Style := psSolid;
  FC.Pen.Color := AColor;
  FC.Pen.Width := W;
  FC.Brush.Style := bsClear;
  FC.Ellipse(ALeft + W, ATop + W, ALeft + ASize - W, ATop + ASize - W);
  FC.Line(ALeft + ASize * 3 div 10, ATop + ASize div 2,
    ALeft + ASize * 9 div 20, ATop + ASize * 13 div 20);
  FC.Line(ALeft + ASize * 9 div 20, ATop + ASize * 13 div 20,
    ALeft + ASize * 7 div 10, ATop + ASize * 7 div 20);
  FC.Pen.Width := 1;
end;

{ A dim bold title with a dim detail after it, over a divider, between
  ALeft and ARight; with AToggle the checkbox that hides the pull
  requests without feedback, at the right of the title's line when it
  fits there, else on a line of its own under the divider. }
procedure TGittanForgePage.PaintHeading(var Y: integer; const ATitle, ADetail: string;
  AToggle: boolean; ALeft, ARight: integer);
var
  TextH, X, ToggleW: integer;
  OnLine: boolean;
begin
  Inc(Y, Px(Pad));
  FC.Font := Font;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FDim;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  FC.TextOut(ALeft, Y, ATitle);
  X := ALeft + FC.TextWidth(ATitle) + Px(Gap) div 2;
  FC.Font.Style := [];
  if ADetail <> '' then
  begin
    FC.TextOut(X, Y, ADetail);
    Inc(X, FC.TextWidth(ADetail));
  end;
  ToggleW := 0;
  if AToggle then
    ToggleW := ToggleWidth(rsHideQuiet);
  OnLine := AToggle and (X + Px(Gap) + ToggleW <= ARight);
  if OnLine then
    PaintToggle(ARight - ToggleW, Y, rsHideQuiet, HideLink, FHide);
  Inc(Y, TextH + Px(Gap) div 2);
  FC.Pen.Style := psSolid;
  FC.Pen.Color := FLine;
  FC.Line(ALeft, Y, ARight, Y);
  Inc(Y, Px(Gap) div 2);
  if AToggle and not OnLine then
  begin
    PaintToggle(ALeft, Y, rsHideQuiet, HideLink, FHide);
    Inc(Y, TextH + Px(Gap) div 2);
  end;
end;

{ The width of the checkbox with ACaption after it. }
function TGittanForgePage.ToggleWidth(const ACaption: string): integer;
begin
  FC.Font := Font;
  Result := Max(10, FC.TextHeight('Xg') - 4) + Px(Gap) div 2 + FC.TextWidth(ACaption);
end;

{ A checkbox with ACaption after it, dim, on the line at ATop from
  ALeft; the box filled in the link color with a check while AChecked,
  the caption underlined under the mouse. }
procedure TGittanForgePage.PaintToggle(ALeft, ATop: integer; const ACaption, ALink: string;
  AChecked: boolean);
var
  TextH, BoxW, X: integer;
  Box: TRect;
begin
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  BoxW := Max(10, TextH - 4);
  Box := Rect(ALeft, ATop + (TextH - BoxW) div 2, ALeft + BoxW,
    ATop + (TextH - BoxW) div 2 + BoxW);
  X := Box.Right + Px(Gap) div 2;
  AddLink(Rect(ALeft, ATop, X + FC.TextWidth(ACaption), ATop + TextH), ALink);
  FC.Pen.Style := psSolid;
  if AChecked then
  begin
    FC.Pen.Color := FLink;
    FC.Brush.Style := bsSolid;
    FC.Brush.Color := FLink;
    FC.RoundRect(Box, Px(BoxRadius), Px(BoxRadius));
    FC.Pen.Color := FBack;
    FC.Pen.Width := Max(1, Px(2));
    FC.Line(Box.Left + BoxW * 2 div 9, Box.Top + BoxW div 2,
      Box.Left + BoxW * 4 div 9, Box.Top + BoxW * 7 div 10);
    FC.Line(Box.Left + BoxW * 4 div 9, Box.Top + BoxW * 7 div 10,
      Box.Left + BoxW * 7 div 9, Box.Top + BoxW * 3 div 10);
    FC.Pen.Width := 1;
  end
  else
  begin
    FC.Pen.Color := FDim;
    FC.Brush.Style := bsClear;
    FC.RoundRect(Box, Px(BoxRadius), Px(BoxRadius));
  end;
  FC.Brush.Style := bsClear;
  FC.Font.Color := FDim;
  if FHot = High(FLinkRects) then
    FC.Font.Style := [fsUnderline];
  FC.TextOut(X, ATop, ACaption);
  FC.Font.Style := [];
end;

{ A paragraph in AColor, wrapped between ALeft and ARight. }
procedure TGittanForgePage.PaintNote(var Y: integer; const AText: string; AColor: TColor;
  ALeft, ARight: integer);
var
  R: TRect;
  Style: TTextStyle;
begin
  Inc(Y, Px(Gap) div 2);
  FC.Font := Font;
  FC.Font.Color := AColor;
  FC.Brush.Style := bsClear;
  R := Rect(ALeft, Y, ARight, Y);
  Style := FC.TextStyle;
  Style.Wordbreak := True;
  Style.SingleLine := False;
  Style.Alignment := taLeftJustify;
  Style.Layout := tlTop;
  DrawText(FC.Handle, PChar(AText), Length(AText), R, DT_CALCRECT or DT_WORDBREAK);
  R.Right := ARight;
  FC.TextRect(R, R.Left, R.Top, AText, Style);
  Y := R.Bottom;
end;

{ An empty section: a card between ALeft and ARight with a large dim
  glyph (a check in a ring with ACheck, else a pull request's), ATitle
  in bold under it when there is one, and AText dim, wrapped, all
  centered. }
procedure TGittanForgePage.PaintEmpty(var Y: integer; const ATitle, AText: string;
  ACheck: boolean; ALeft, ARight: integer);
var
  R, TR: TRect;
  TextH, G, H, TextY: integer;
  Style: TTextStyle;
begin
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  G := Px(EmptyGlyph);
  TR := Rect(ALeft + Px(CardPadX), 0, ARight - Px(CardPadX), 0);
  DrawText(FC.Handle, PChar(AText), Length(AText), TR, DT_CALCRECT or DT_WORDBREAK);
  H := 2 * Px(EmptyPadY) + G + Px(Gap) + TR.Bottom;
  if ATitle <> '' then
    Inc(H, TextH + 4);
  R := Rect(ALeft, Y, ARight, Y + H);
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FCard;
  FC.RoundRect(R, Px(CardRadius), Px(CardRadius));
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;
  if ACheck then
    PaintCheckGlyph((ALeft + ARight - G) div 2, R.Top + Px(EmptyPadY), G, FDim)
  else
    PaintPullGlyph((ALeft + ARight - G) div 2, R.Top + Px(EmptyPadY), G, FDim);
  TextY := R.Top + Px(EmptyPadY) + G + Px(Gap);
  if ATitle <> '' then
  begin
    FC.Font.Style := [fsBold];
    FC.Font.Color := FText;
    FC.TextOut((ALeft + ARight - FC.TextWidth(ATitle)) div 2, TextY, ATitle);
    FC.Font.Style := [];
    Inc(TextY, TextH + 4);
  end;
  FC.Font.Color := FDim;
  TR := Rect(ALeft + Px(CardPadX), TextY, ARight - Px(CardPadX), R.Bottom);
  Style := FC.TextStyle;
  Style.Wordbreak := True;
  Style.SingleLine := False;
  Style.Alignment := taCenter;
  Style.Layout := tlTop;
  FC.TextRect(TR, TR.Left, TR.Top, AText, Style);
  Inc(Y, H + Px(CardGap));
end;

{ A chip ending at ARight with its text in AColor on the hover fill;
  gives its left edge. }
function TGittanForgePage.PaintChip(ARight, ATop: integer; const AText: string;
  AColor: TColor): integer;
var
  R: TRect;
  W, H: integer;
begin
  FC.Font := Font;
  FC.Font.Size := Max(7, Font.Size - 2);
  if Font.Size <= 0 then
    FC.Font.Size := 9;
  W := FC.TextWidth(AText) + 2 * Px(ChipPadX);
  H := FC.TextHeight(AText) + 2 * Px(ChipPadY);
  R := Rect(ARight - W, ATop, ARight, ATop + H);
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FHover;
  FC.RoundRect(R, Px(ChipRadius), Px(ChipRadius));
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;
  FC.Font.Color := AColor;
  FC.TextOut(R.Left + Px(ChipPadX), R.Top + Px(ChipPadY), AText);
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  Result := R.Left;
end;

{ The second line of a card after the repository: who opened it, how
  long ago it was opened and last changed. }
function TGittanForgePage.PullLine(const APull: TGittanForgePull): string;
var
  UtcNow: TDateTime;

  procedure Add(const APart: string);
  begin
    if APart = '' then
      Exit;
    if Result <> '' then
      Result := Result + ' · ';
    Result := Result + APart;
  end;

begin
  Result := '';
  UtcNow := LocalTimeToUniversal(Now);
  if not SameText(APull.Author, FLogin) then
    Add(APull.Author);
  if APull.Created > 0 then
    Add(Format(rsOpened, [RelativeAge(APull.Created, UtcNow)]));
  if (APull.Updated > 0) and (MinutesBetween(APull.Updated, APull.Created) >= 1) then
    Add(Format(rsUpdated, [RelativeAge(APull.Updated, UtcNow)]));
end;

{ A card between ALeft and ARight: the pull request glyph, the number
  dimmed and the title in bold, the chips of the state and the checks
  at the right, the second line under them with the repository first
  and the forge link at its right end while the card is under the
  mouse, and the link to its clone under that, which ALink, the card's
  own, picks too. The card and its links are under the mouse
  together. }
procedure TGittanForgePage.PaintCard(var Y: integer; const APull: TGittanForgePull;
  ALeft, ARight: integer; const ALink: string);
var
  R, LinkR: TRect;
  TextH, CardH, Right, X, TextX, LineY, ChipTop, First, Links: integer;
  Number, Repo, Rest, ForgeLink, CloneLink: string;
  Lines: integer;
  HasClone, HasForge, Hot: boolean;
  GlyphColor: TColor;
begin
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  HasClone := (APull.Clone <> '') and Assigned(FOnPick) and
    not SameFileName(APull.Clone, FOpenRoot);
  HasForge := (APull.Url <> '') and Assigned(FOnOpenUrl);
  Lines := 2;
  if HasClone then
    Lines := 3;
  CardH := 2 * Px(CardPadY) + Lines * TextH + 4 * (Lines - 1);
  R := Rect(ALeft, Y, ARight, Y + CardH);
  First := Length(FLinkRects);
  Links := Ord(Assigned(FOnPick)) + Ord(HasForge) + Ord(HasClone);
  Hot := (FHot >= First) and (FHot < First + Links);
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FCard;
  if Assigned(FOnPick) then
  begin
    AddLink(R, ALink);
    if Hot then
      FC.Brush.Color := FHover;
  end;
  FC.RoundRect(R, Px(CardRadius), Px(CardRadius));
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;

  if APull.IsDraft then
    GlyphColor := FDim
  else
    GlyphColor := FOk;
  PaintPullGlyph(R.Left + Px(CardPadX), R.Top + Px(CardPadY), TextH, GlyphColor);
  TextX := R.Left + Px(CardPadX) + TextH + Px(GlyphGap);

  { The chips, right to left: the checks, the state, asked again. }
  Right := R.Right - Px(CardPadX);
  ChipTop := R.Top + Px(CardPadY);
  case APull.Checks of
    chkFailed: Right := PaintChip(Right, ChipTop, rsChecksFailing, FErrorColor) - Px(Gap) div 2;
    chkPending: Right := PaintChip(Right, ChipTop, rsChecksPending, FWarn) - Px(Gap) div 2;
    chkPassed: Right := PaintChip(Right, ChipTop, rsChecksOk, FOk) - Px(Gap) div 2;
  end;
  if APull.IsDraft then
    Right := PaintChip(Right, ChipTop, rsDraft, FDim) - Px(Gap) div 2
  else
    case APull.ReviewDecision of
      rdApproved: Right := PaintChip(Right, ChipTop, rsApproved, FOk) - Px(Gap) div 2;
      rdChangesRequested:
        Right := PaintChip(Right, ChipTop, rsChangesRequested, FErrorColor) - Px(Gap) div 2;
      rdReviewRequired: Right := PaintChip(Right, ChipTop, rsReviewRequired, FDim) - Px(Gap) div 2;
    end;
  if APull.Requested and (APull.MyReview <> rvNone) then
    Right := PaintChip(Right, ChipTop, rsAskedAgain, FWarn) - Px(Gap) div 2;

  { The number and the title. }
  X := TextX;
  Number := '#' + IntToStr(APull.Number);
  FC.Font.Color := FDim;
  FC.TextOut(X, R.Top + Px(CardPadY), Number);
  Inc(X, FC.TextWidth(Number) + Px(Gap) div 2);
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  FC.TextOut(X, R.Top + Px(CardPadY), FitTextRight(FC, APull.Title, Max(0, Right - X)));
  FC.Font.Style := [];

  { The second line: the repository, the rest dim, and the forge link
    at its right end, there to click whether shown or not, since the
    mouse on it shows it. }
  LineY := R.Top + Px(CardPadY) + TextH + 4;
  Right := R.Right - Px(CardPadX);
  if HasForge then
  begin
    ForgeLink := Format(rsForgeLink, [FForge]);
    LinkR := Rect(Right - FC.TextWidth(ForgeLink), LineY, Right, LineY + TextH);
    AddLink(LinkR, APull.Url);
    if Hot or not Assigned(FOnPick) then
    begin
      FC.Font.Color := FLink;
      if FHot = High(FLinkRects) then
        FC.Font.Style := [fsUnderline];
      FC.TextOut(LinkR.Left, LinkR.Top, ForgeLink);
      FC.Font.Style := [];
      Right := LinkR.Left - Px(Gap);
    end;
  end;
  FC.Font.Color := FText;
  Repo := FitTextRight(FC, APull.Repo, Max(0, Right - TextX));
  FC.TextOut(TextX, LineY, Repo);
  X := TextX + FC.TextWidth(Repo);
  Rest := PullLine(APull);
  if (Rest <> '') and (Repo = APull.Repo) then
  begin
    FC.Font.Color := FDim;
    FC.TextOut(X, LineY, FitTextRight(FC, ' · ' + Rest, Max(0, Right - X)));
  end;

  { The clone's link, under the forge's, its path cut at its start to
    the card. }
  if HasClone then
  begin
    Right := R.Right - Px(CardPadX);
    CloneLink := Format(rsCloneLink, [FitTextLeft(FC, ShortPath(APull.Clone),
      Max(0, Right - TextX - FC.TextWidth(Format(rsCloneLink, ['']))))]);
    LinkR := Rect(Right - FC.TextWidth(CloneLink), LineY + TextH + 4,
      Right, LineY + 2 * TextH + 4);
    AddLink(LinkR, ALink);
    FC.Font.Color := FLink;
    if FHot = High(FLinkRects) then
      FC.Font.Style := [fsUnderline];
    FC.TextOut(LinkR.Left, LinkR.Top, CloneLink);
    FC.Font.Style := [];
  end;
  Inc(Y, CardH + Px(CardGap));
end;

{ A section: its heading with the count (of ATotal, when some are left
  out) and the checkbox that hides the ones without feedback when
  AToggle, then a card per pull request, or, once the forge has
  answered, an empty card with AEmptyTitle and AEmpty, its glyph a
  check with AEmptyCheck. }
procedure TGittanForgePage.PaintSection(var Y: integer; const ATitle: string;
  const APulls: TGittanForgePulls; ATotal: integer; const AEmptyTitle, AEmpty,
  ALinkPrefix: string; AEmptyCheck, AToggle: boolean; ALeft, ARight: integer);
var
  Detail: string;
  i: integer;
begin
  if ATotal > Length(APulls) then
    Detail := Format(rsSomeOpen, [Length(APulls), ATotal])
  else if Length(APulls) = 1 then
    Detail := rsOneOpen
  else if Length(APulls) > 1 then
    Detail := Format(rsManyOpen, [Length(APulls)])
  else
    Detail := '';
  PaintHeading(Y, ATitle, Detail, AToggle, ALeft, ARight);
  if Length(APulls) = 0 then
  begin
    if FAnswered and (FError = '') then
      PaintEmpty(Y, AEmptyTitle, AEmpty, AEmptyCheck, ALeft, ARight);
  end
  else
    for i := 0 to High(APulls) do
      PaintCard(Y, APulls[i], ALeft, ARight, ALinkPrefix + IntToStr(i));
end;

procedure TGittanForgePage.Paint;
begin
  FC := Canvas;
  PaintContent;
end;

procedure TGittanForgePage.PaintContent;
var
  Y, TextH, TitleH, X, L, R, AvatarD, ButtonD: integer;
  Who, NoMine: string;

  procedure AddWho(const APart: string);
  begin
    if Who <> '' then
      Who := Who + ' · ';
    Who := Who + APart;
  end;

begin
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FBack;
  FC.FillRect(Rect(0, 0, Width, Height));
  FLinkRects := nil;
  FLinkUrls := nil;
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  L := Max(Px(Pad), (Width - Px(MaxContentWidth)) div 2);
  R := Width - L;
  Y := Px(Pad);

  { The head: the avatar, the forge's name with the page's title and
    Refresh after it, under them the login with the counts, or that
    the forge is asked. }
  FC.Font.Size := TitleFontSize;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  TitleH := FC.TextHeight('Xg');
  AvatarD := TitleH + 2 + TextH;
  FC.TextOut(L + AvatarD + Px(Gap), Y, FForge);
  X := L + AvatarD + Px(Gap) + FC.TextWidth(FForge) + Px(Gap);
  PaintAvatar(L, Y, AvatarD);
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  FC.Font.Color := FDim;
  FC.TextOut(X, Y + TitleH - TextH - 3, rsPageTitle);
  Inc(X, FC.TextWidth(rsPageTitle) + Px(Gap) div 2);
  ButtonD := TextH + Px(8);
  PaintRefresh(X, Y + TitleH - TextH - 3 + (TextH - ButtonD) div 2, ButtonD);
  Who := FLogin;
  if FLoading then
    AddWho(Format(rsLoading, [FForge]))
  else if FAnswered and (FError = '') then
  begin
    if Length(FMine) = 1 then
      AddWho(rsOneOpen)
    else
      AddWho(Format(rsManyOpen, [Length(FMine)]));
    AddWho(Format(rsToReview, [Length(FReview)]));
  end;
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  FC.Font.Color := FDim;
  X := L + AvatarD + Px(Gap);
  FC.TextOut(X, Y + TitleH + 2, FitTextLeft(FC, Who, R - X));
  Inc(Y, AvatarD);
  if FError <> '' then
    PaintNote(Y, FError, FErrorColor, L, R);

  { The section: the checkbox shows once there is something of the
    user's to hide, and stays while it hides all of it. }
  if FHide then
    FShownMine := WithFeedback(FMine)
  else
    FShownMine := Copy(FMine);
  if FSection = fsReview then
    PaintSection(Y, rsReviewGroup, FReview, Length(FReview), rsCaughtUp, rsNoReview,
      ReviewLink, True, False, L, R)
  else
  begin
    if Length(FMine) > 0 then
      NoMine := rsNoFeedback
    else
      NoMine := rsNoMine;
    PaintSection(Y, rsMineGroup, FShownMine, Length(FMine), '', NoMine, MineLink, False,
      Length(FMine) > 0, L, R);
  end;

  { Layout sets the height from this. }
  FContentHeight := Y + Px(Pad);
end;

procedure TGittanForgePage.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(LinkAt(X, Y));
end;

procedure TGittanForgePage.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1);
end;

procedure TGittanForgePage.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  i, n: integer;
  Url: string;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  i := LinkAt(X, Y);
  if i < 0 then
    Exit;
  Url := FLinkUrls[i];
  if Copy(Url, 1, Length(MineLink)) = MineLink then
  begin
    n := StrToIntDef(Copy(Url, Length(MineLink) + 1, MaxInt), -1);
    if (n >= 0) and (n <= High(FShownMine)) and Assigned(FOnPick) then
      FOnPick(Self, FShownMine[n]);
  end
  else if Copy(Url, 1, Length(ReviewLink)) = ReviewLink then
  begin
    n := StrToIntDef(Copy(Url, Length(ReviewLink) + 1, MaxInt), -1);
    if (n >= 0) and (n <= High(FReview)) and Assigned(FOnPick) then
      FOnPick(Self, FReview[n]);
  end
  else if Url = HideLink then
  begin
    SetHide(not FHide);
    if Assigned(FOnHideChange) then
      FOnHideChange(Self);
  end
  else if Url = RefreshLink then
  begin
    if Assigned(FOnRefresh) then
      FOnRefresh(Self);
  end
  else if Assigned(FOnOpenUrl) then
    FOnOpenUrl(Self, Url);
end;

end.
