unit gittan.forgepage;

{** The forge page: the user's pull requests across every repository
  of a forge (gittan.forge; its name from SetForge), in two columns: at
  the left the open ones they wrote, at the right the open ones
  waiting for their review, under each other when the page is narrow.
  A card has the number and the title, at the right its state (Draft,
  Approved, Changes requested, Review required) and its checks as
  chips, "Asked again" on one the user is asked to review once more
  after reviewing it, and under them the repository, who opened it and
  when it was opened and last changed, with a link to the forge at the
  right end. A checkbox under the left column's heading leaves out the
  user's pull requests nobody but them has commented on or reviewed
  (HideWithoutFeedback, OnHideChange). A card fills under the mouse
  and a click raises OnPick with the pull request, for the owner to
  compare with it when it is the open repository's, else to open it
  on the forge. The line under the title names the login and says
  while the forge is asked, with Refresh (OnRefresh) at its right; the
  forge's failure (not logged in) shows in the error color.

  It paints itself in the editor's palette, like the Pull Requests
  page, and sizes its height to its content so it can sit in the same
  TScrollBox: Layout paints the content on a measuring canvas to know
  the height before the control is shown. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, gittan.forge, gittan.summary;

type
  {** A click on a card: the pull request. }
  TGittanForgePickEvent = procedure(Sender: TObject; const APull: TGittanForgePull) of object;

  { TGittanForgePage }

  TGittanForgePage = class(TCustomControl)
  private
    FForge, FLogin, FError: string;
    FMine, FReview: TGittanForgePulls;
    { FMine as shown: without the ones with no feedback while FHide. }
    FShownMine: TGittanForgePulls;
    FHide: boolean;
    { FLoading while the forge is asked; FAnswered once it has answered,
      so the empty columns say so only then. }
    FLoading, FAnswered: boolean;
    FBack, FText, FDim, FHover, FLine, FLink, FOk, FWarn, FErrorColor, FCard: TColor;
    FLinkRects: array of TRect;
    FLinkUrls: array of string;
    FHot: integer;
    FContentHeight: integer;
    { The canvas the content is painted on: the control's in Paint, a
      measuring one in Layout. }
    FC: TCanvas;
    FOnPick: TGittanForgePickEvent;
    FOnRefresh, FOnHideChange: TNotifyEvent;
    FOnOpenUrl: TGittanOpenUrlEvent;
    function LinkAt(X, Y: integer): integer;
    procedure SetHot(AValue: integer);
    procedure SetHide(AValue: boolean);
    procedure AddLink(const ARect: TRect; const AUrl: string);
    procedure PaintHeading(var Y: integer; const ATitle, ADetail: string; ALeft, ARight: integer);
    procedure PaintAction(ATop: integer; const ACaption, ALink: string);
    procedure PaintToggle(var Y: integer; const ACaption, ALink: string; AChecked: boolean;
      ALeft: integer);
    procedure PaintNote(var Y: integer; const AText: string; AColor: TColor;
      ALeft, ARight: integer);
    function PaintChip(ARight, ATop: integer; const AText: string; AColor: TColor): integer;
    procedure PaintCard(var Y: integer; const APull: TGittanForgePull; ALeft, ARight: integer;
      const ALink: string);
    function PullLine(const APull: TGittanForgePull): string;
    procedure PaintColumn(var Y: integer; const ATitle: string; const APulls: TGittanForgePulls;
      ATotal: integer; const AEmpty, ALinkPrefix: string; AToggle: boolean;
      ALeft, ARight: integer);
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
    {** Makes the control at least AMin high (the height of the box it
      sits in, so its background covers the box), and no higher than its
      content needs beyond that. }
    procedure FitHeight(AMin: integer);
    {** Whether the user's pull requests that nobody but them has
      commented on or reviewed are left out; the checkbox sets it and
      raises OnHideChange. }
    property HideWithoutFeedback: boolean read FHide write SetHide;
    property OnHideChange: TNotifyEvent read FOnHideChange write FOnHideChange;
    property OnPick: TGittanForgePickEvent read FOnPick write FOnPick;
    property OnRefresh: TNotifyEvent read FOnRefresh write FOnRefresh;
    property OnOpenUrl: TGittanOpenUrlEvent read FOnOpenUrl write FOnOpenUrl;
  end;

implementation

uses
  Math, DateUtils, LCLIntf, LCLType, gittan.reviews, gittan.textfit, gittan.theme;

resourcestring
  rsPageTitle = 'Pull requests';
  rsMineGroup = 'Your open pull requests';
  rsReviewGroup = 'Waiting for your review';
  rsOneOpen = '1 open';
  rsManyOpen = '%d open';
  rsSomeOpen = '%d of %d open';
  rsHideQuiet = 'Hide the ones without feedback';
  rsNoFeedback = 'Nobody has commented on or reviewed any of them yet.';
  rsRefresh = 'Refresh';
  rsLoading = 'Asking %s…';
  rsNoMine = 'No open pull requests of yours.';
  rsNoReview = 'Nothing waiting for your review.';
  rsForgeLink = '%s ↗';
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
  Pad = 24;
  Gap = 12;
  TitleFontSize = 20;
  { The page narrower than this puts the columns under each other. }
  TwoColumnsMin = 760;
  { The cards: their padding and corner radius; the chips at their
    right. }
  CardPadX = 14;
  CardPadY = 10;
  CardRadius = 12;
  CardGap = 8;
  ChipPadX = 6;
  ChipPadY = 2;
  ChipRadius = 6;
  { The checkbox: the corner radius of its box. }
  BoxRadius = 4;

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

procedure TGittanForgePage.SetPulls(const AMine, AReview: TGittanForgePulls;
  const AError: string; ALoading: boolean);
begin
  FMine := Copy(AMine);
  FReview := Copy(AReview);
  FError := AError;
  FLoading := ALoading;
  FAnswered := FAnswered or not ALoading;
  FHot := -1;
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

{ A dim bold title with a dim detail after it, over a divider, between
  ALeft and ARight. }
procedure TGittanForgePage.PaintHeading(var Y: integer; const ATitle, ADetail: string;
  ALeft, ARight: integer);
var
  TextH, X: integer;
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
    FC.TextOut(X, Y, ADetail);
  Inc(Y, TextH + Px(Gap) div 2);
  FC.Pen.Style := psSolid;
  FC.Pen.Color := FLine;
  FC.Line(ALeft, Y, ARight, Y);
  Inc(Y, Px(Gap) div 2);
end;

{ ACaption as a link at the right edge of the page, on the line whose
  text starts at ATop. }
procedure TGittanForgePage.PaintAction(ATop: integer; const ACaption, ALink: string);
var
  R: TRect;
begin
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  R := Rect(Width - Px(Pad) - FC.TextWidth(ACaption), ATop, Width - Px(Pad),
    ATop + FC.TextHeight('Xg'));
  AddLink(R, ALink);
  FC.Font.Color := FLink;
  if FHot = High(FLinkRects) then
    FC.Font.Style := [fsUnderline];
  FC.TextOut(R.Left, R.Top, ACaption);
  FC.Font.Style := [];
end;

{ A checkbox with ACaption after it, dim, on a line of its own from
  ALeft; the box filled in the link color with a check while
  AChecked, the caption underlined under the mouse. }
procedure TGittanForgePage.PaintToggle(var Y: integer; const ACaption, ALink: string;
  AChecked: boolean; ALeft: integer);
var
  TextH, BoxW, X: integer;
  Box: TRect;
begin
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  BoxW := Max(10, TextH - 4);
  Box := Rect(ALeft, Y + (TextH - BoxW) div 2, ALeft + BoxW, Y + (TextH - BoxW) div 2 + BoxW);
  X := Box.Right + Px(Gap) div 2;
  AddLink(Rect(ALeft, Y, X + FC.TextWidth(ACaption), Y + TextH), ALink);
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
  FC.TextOut(X, Y, ACaption);
  FC.Font.Style := [];
  Inc(Y, TextH + Px(Gap) div 2);
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

{ The second line of a card: the repository, who opened it, when it
  was opened and last changed. }
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
  Add(APull.Repo);
  if not SameText(APull.Author, FLogin) then
    Add(APull.Author);
  if APull.Created > 0 then
    Add(Format(rsOpened, [ReviewAge(APull.Created, UtcNow)]));
  if (APull.Updated > 0) and (MinutesBetween(APull.Updated, APull.Created) >= 1) then
    Add(Format(rsUpdated, [ReviewAge(APull.Updated, UtcNow)]));
end;

{ A card between ALeft and ARight: the number dimmed and the title in
  bold, the chips of the state and the checks at the right, the second
  line under them with the forge link at its right end. }
procedure TGittanForgePage.PaintCard(var Y: integer; const APull: TGittanForgePull;
  ALeft, ARight: integer; const ALink: string);
var
  R, LinkR: TRect;
  TextH, CardH, Right, X, ChipTop: integer;
  Number, Line, ForgeLink: string;
begin
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  CardH := 2 * Px(CardPadY) + 2 * TextH + 4;
  R := Rect(ALeft, Y, ARight, Y + CardH);
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FCard;
  if Assigned(FOnPick) then
  begin
    AddLink(R, ALink);
    if FHot = High(FLinkRects) then
      FC.Brush.Color := FHover;
  end;
  FC.RoundRect(R, Px(CardRadius), Px(CardRadius));
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;

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
  X := R.Left + Px(CardPadX);
  Number := '#' + IntToStr(APull.Number);
  FC.Font.Color := FDim;
  FC.TextOut(X, R.Top + Px(CardPadY), Number);
  Inc(X, FC.TextWidth(Number) + Px(Gap) div 2);
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  FC.TextOut(X, R.Top + Px(CardPadY), FitTextRight(FC, APull.Title, Max(0, Right - X)));
  FC.Font.Style := [];

  { The second line, with the forge link at its right end. }
  X := R.Left + Px(CardPadX);
  Right := R.Right - Px(CardPadX);
  if (APull.Url <> '') and Assigned(FOnOpenUrl) then
  begin
    ForgeLink := Format(rsForgeLink, [FForge]);
    LinkR := Rect(Right - FC.TextWidth(ForgeLink), R.Top + Px(CardPadY) + TextH + 4,
      Right, R.Top + Px(CardPadY) + 2 * TextH + 4);
    AddLink(LinkR, APull.Url);
    FC.Font.Color := FLink;
    if FHot = High(FLinkRects) then
      FC.Font.Style := [fsUnderline];
    FC.TextOut(LinkR.Left, LinkR.Top, ForgeLink);
    FC.Font.Style := [];
    Right := LinkR.Left - Px(Gap);
  end;
  Line := PullLine(APull);
  FC.Font.Color := FDim;
  FC.TextOut(X, R.Top + Px(CardPadY) + TextH + 4, FitTextRight(FC, Line, Max(0, Right - X)));
  Inc(Y, CardH + Px(CardGap));
end;

{ A column: its heading with the count (of ATotal, when some are left
  out), the checkbox that hides the ones without feedback when
  AToggle, then a card per pull request, or AEmpty once the forge has
  answered. }
procedure TGittanForgePage.PaintColumn(var Y: integer; const ATitle: string;
  const APulls: TGittanForgePulls; ATotal: integer; const AEmpty, ALinkPrefix: string;
  AToggle: boolean; ALeft, ARight: integer);
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
  PaintHeading(Y, ATitle, Detail, ALeft, ARight);
  if AToggle then
    PaintToggle(Y, rsHideQuiet, HideLink, FHide, ALeft);
  if Length(APulls) = 0 then
  begin
    if FAnswered and (FError = '') then
      PaintNote(Y, AEmpty, FDim, ALeft, ARight);
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
  Y, Y2, TextH, TitleH, X, ColW: integer;
  Who, NoMine: string;
  Toggle: boolean;
begin
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FBack;
  FC.FillRect(Rect(0, 0, Width, Height));
  FLinkRects := nil;
  FLinkUrls := nil;
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  Y := Px(Pad);

  { The forge's name with the page's title after it, under them the
    login; while the forge is asked, that it is; Refresh at the right. }
  FC.Font.Size := TitleFontSize;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  TitleH := FC.TextHeight('Xg');
  FC.TextOut(Px(Pad), Y, FForge);
  X := Px(Pad) + FC.TextWidth(FForge) + Px(Gap);
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  FC.Font.Color := FDim;
  FC.TextOut(X, Y + TitleH - TextH - 3, rsPageTitle);
  Inc(Y, TitleH + 2);
  Who := FLogin;
  if FLoading then
  begin
    if Who <> '' then
      Who := Who + ' · ';
    Who := Who + Format(rsLoading, [FForge]);
  end;
  if Assigned(FOnRefresh) and not FLoading then
    PaintAction(Y, rsRefresh, RefreshLink);
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  FC.Font.Color := FDim;
  FC.TextOut(Px(Pad), Y, FitTextLeft(FC, Who, Width - 2 * Px(Pad) - FC.TextWidth(rsRefresh) -
    Px(Gap)));
  Inc(Y, TextH);
  if FError <> '' then
    PaintNote(Y, FError, FErrorColor, Px(Pad), Width - Px(Pad));

  { The checkbox shows once there is something of the user's to hide,
    and stays while it hides all of it. }
  if FHide then
    FShownMine := WithFeedback(FMine)
  else
    FShownMine := Copy(FMine);
  Toggle := Length(FMine) > 0;
  if Length(FMine) > 0 then
    NoMine := rsNoFeedback
  else
    NoMine := rsNoMine;
  if Width >= Px(TwoColumnsMin) then
  begin
    ColW := (Width - 2 * Px(Pad) - 2 * Px(Gap)) div 2;
    Y2 := Y;
    PaintColumn(Y, rsMineGroup, FShownMine, Length(FMine), NoMine, MineLink, Toggle, Px(Pad),
      Px(Pad) + ColW);
    PaintColumn(Y2, rsReviewGroup, FReview, Length(FReview), rsNoReview, ReviewLink, False,
      Width - Px(Pad) - ColW, Width - Px(Pad));
    Y := Max(Y, Y2);
  end
  else
  begin
    PaintColumn(Y, rsMineGroup, FShownMine, Length(FMine), NoMine, MineLink, Toggle, Px(Pad),
      Width - Px(Pad));
    PaintColumn(Y, rsReviewGroup, FReview, Length(FReview), rsNoReview, ReviewLink, False,
      Px(Pad), Width - Px(Pad));
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
