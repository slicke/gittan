unit gittan.pullpage;

{** The Pull Requests page: the open pull requests of the repository as
  gh lists them (gittan.github), each a card with its number and title,
  under them who opened it, its branches, when it was opened and last
  changed, what it changes and its labels, and at the right its state
  (Draft, Approved, Changes requested, Review required) and its checks
  as chips in their colors, and "Needs your review" in the warning
  color on one waiting for the user's review (SetReviewPulls, from the
  same job). The branch's own pull request, when it has
  one, stands first under its own heading, also when it is merged or
  closed and so not among the open ones. A card fills under the mouse
  and a click raises OnCompare with the pull request, for the owner to
  compare with it as Compare With > Pull Requests does; the one
  compared against has a stripe in the link color and says so, and a
  click on it raises OnWorkingTree instead. "GitHub ↗" at the right
  end of a card's second line raises OnOpenUrl. The heading of the open
  ones offers Refresh (OnRefresh). While gh is asked the page says so
  under the name, keeping what it had; gh's failure (no GitHub remote,
  not logged in) shows in the error color.

  It paints itself in the editor's palette, like the Repository page,
  and sizes its height to its content so it can sit in the same
  TScrollBox: Layout paints the content on a measuring canvas to know
  the height before the control is shown, since a height that changes
  in the first paint leaves the box scrolled wrong on Cocoa. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, gittan.github, gittan.summary;

type
  {** A click on a card: the pull request. }
  TGittanPullEvent = procedure(Sender: TObject; const APull: TGittanPullRequest) of object;

  { TGittanPullPage }

  TGittanPullPage = class(TCustomControl)
  private
    FName, FRoot: string;
    FPulls: TGittanPullRequests;
    FBranchPull: TGittanPullRequest;
    FHasBranchPull, FLoading: boolean;
    FError: string;
    FComparing: integer;
    { The numbers of the pull requests waiting for the user's review. }
    FReviewNumbers: array of integer;
    FBack, FText, FDim, FHover, FLine, FLink, FOk, FWarn, FErrorColor, FCard: TColor;
    FLinkRects: array of TRect;
    FLinkUrls: array of string;
    FHot: integer;
    FContentHeight: integer;
    { The canvas the content is painted on: the control's in Paint, a
      measuring one in Layout. }
    FC: TCanvas;
    FOnCompare: TGittanPullEvent;
    FOnWorkingTree, FOnRefresh: TNotifyEvent;
    FOnOpenUrl: TGittanOpenUrlEvent;
    function LinkAt(X, Y: integer): integer;
    function NeedsReview(ANumber: integer): boolean;
    procedure SetHot(AValue: integer);
    procedure AddLink(const ARect: TRect; const AUrl: string);
    procedure PaintHeading(var Y: integer; const ATitle, ADetail: string);
    procedure PaintAction(ATop: integer; const ACaption, ALink: string);
    procedure PaintNote(var Y: integer; const AText: string; AColor: TColor);
    function PaintChip(ARight, ATop: integer; const AText: string; AColor: TColor): integer;
    procedure PaintCard(var Y: integer; const APull: TGittanPullRequest; const ALink: string);
    function PullLine(const APull: TGittanPullRequest): string;
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
    {** The repository shown: its name over its root. Another root
      drops the pull requests of the one before. }
    procedure SetRepository(const AName, ARoot: string);
    {** The open pull requests, gh's message when it failed (else ''),
      and whether gh is being asked now. }
    procedure SetPulls(const APulls: TGittanPullRequests; const AError: string;
      ALoading: boolean);
    {** The branch's own pull request, or none (AHas false). }
    procedure SetBranchPull(const APull: TGittanPullRequest; AHas: boolean);
    {** The number of the pull request compared against, 0 for none. }
    procedure SetComparing(ANumber: integer);
    {** The pull requests waiting for the user's review, whose cards get
      a chip saying so; nil for none. }
    procedure SetReviewPulls(const APulls: TGittanPullRequests);
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
    {** The root the pull requests are for. }
    property Root: string read FRoot;
    property OnCompare: TGittanPullEvent read FOnCompare write FOnCompare;
    {** A click on the card compared against. }
    property OnWorkingTree: TNotifyEvent read FOnWorkingTree write FOnWorkingTree;
    property OnRefresh: TNotifyEvent read FOnRefresh write FOnRefresh;
    property OnOpenUrl: TGittanOpenUrlEvent read FOnOpenUrl write FOnOpenUrl;
  end;

implementation

uses
  Math, DateUtils, LCLIntf, LCLType, gittan.reviews, gittan.textfit, gittan.theme;

resourcestring
  rsPageTitle = 'Pull Requests';
  rsBranchGroup = 'This branch';
  rsOpenGroup = 'Open pull requests';
  rsOneOpen = '1 open';
  rsManyOpen = '%d open';
  rsRefresh = 'Refresh';
  rsLoading = 'Asking GitHub…';
  rsNoPulls = 'No open pull requests.';
  rsGitHubLink = 'GitHub ↗';
  rsComparing = 'Comparing';
  rsNeedsReview = 'Needs your review';
  rsChecksOk = '✓ checks';
  rsChecksFailing = '%d failing';
  rsChecksPending = '%d pending';
  rsOpened = 'opened %s';
  rsUpdated = 'updated %s';
  rsChangedFiles = '%d files';
  rsChangedFile = '1 file';
  rsInto = '%s → %s';

const
  CompareLink = 'gittan:compare:';
  BranchLink = 'gittan:branch';
  RefreshLink = 'gittan:refresh';
  Pad = 24;
  Gap = 12;
  TitleFontSize = 20;
  { The cards: their padding, corner radius and the stripe of the one
    compared against; the chips at their right. }
  CardPadX = 14;
  CardPadY = 10;
  CardRadius = 12;
  CardGap = 8;
  StripeWidth = 3;
  ChipPadX = 6;
  ChipPadY = 2;
  ChipRadius = 6;

{ TGittanPullPage }

constructor TGittanPullPage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FHot := -1;
  Align := alTop;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnShadow, clHighlight,
    clGreen, clOlive, clRed);
  FCard := clBtnFace;
end;

procedure TGittanPullPage.SetRepository(const AName, ARoot: string);
begin
  if FRoot <> ARoot then
  begin
    FPulls := nil;
    FHasBranchPull := False;
    FError := '';
    FLoading := False;
    FComparing := 0;
  end;
  FName := AName;
  FRoot := ARoot;
  Layout;
  Invalidate;
end;

procedure TGittanPullPage.SetPulls(const APulls: TGittanPullRequests; const AError: string;
  ALoading: boolean);
var
  i: integer;
begin
  SetLength(FPulls, Length(APulls));
  for i := 0 to High(APulls) do
    FPulls[i] := APulls[i];
  FError := AError;
  FLoading := ALoading;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanPullPage.SetBranchPull(const APull: TGittanPullRequest; AHas: boolean);
begin
  FBranchPull := APull;
  FHasBranchPull := AHas;
  Layout;
  Invalidate;
end;

procedure TGittanPullPage.SetComparing(ANumber: integer);
begin
  if FComparing = ANumber then
    Exit;
  FComparing := ANumber;
  Layout;
  Invalidate;
end;

procedure TGittanPullPage.SetReviewPulls(const APulls: TGittanPullRequests);
var
  i: integer;
  Same: boolean;
begin
  Same := Length(APulls) = Length(FReviewNumbers);
  if Same then
    for i := 0 to High(APulls) do
      if APulls[i].Number <> FReviewNumbers[i] then
        Same := False;
  if Same then
    Exit;
  SetLength(FReviewNumbers, Length(APulls));
  for i := 0 to High(APulls) do
    FReviewNumbers[i] := APulls[i].Number;
  Layout;
  Invalidate;
end;

function TGittanPullPage.NeedsReview(ANumber: integer): boolean;
var
  i: integer;
begin
  Result := False;
  for i := 0 to High(FReviewNumbers) do
    if FReviewNumbers[i] = ANumber then
      Exit(True);
end;

procedure TGittanPullPage.SetColors(ABack, AText, ADim, AHover, ALine, ALink, AOk, AWarn,
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

procedure TGittanPullPage.SetCardColor(ACard: TColor);
begin
  FCard := ACard;
  Invalidate;
end;

procedure TGittanPullPage.FitHeight(AMin: integer);
begin
  Constraints.MinHeight := AMin;
  Layout;
end;

{ The content painted on the measuring canvas, for its height; the
  height is set here, never in Paint. }
procedure TGittanPullPage.Layout;
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

procedure TGittanPullPage.Resize;
begin
  inherited Resize;
  Layout;
end;

function TGittanPullPage.LinkAt(X, Y: integer): integer;
var
  i: integer;
begin
  { The last link added wins: the GitHub link lies on its card. }
  for i := High(FLinkRects) downto 0 do
    if PtInRect(FLinkRects[i], Point(X, Y)) then
      Exit(i);
  Result := -1;
end;

procedure TGittanPullPage.SetHot(AValue: integer);
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

procedure TGittanPullPage.AddLink(const ARect: TRect; const AUrl: string);
begin
  SetLength(FLinkRects, Length(FLinkRects) + 1);
  SetLength(FLinkUrls, Length(FLinkUrls) + 1);
  FLinkRects[High(FLinkRects)] := ARect;
  FLinkUrls[High(FLinkUrls)] := AUrl;
end;

{ A dim bold title with a dim detail after it, over a divider. }
procedure TGittanPullPage.PaintHeading(var Y: integer; const ATitle, ADetail: string);
var
  TextH, X: integer;
begin
  Inc(Y, Px(Pad));
  FC.Font := Font;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FDim;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  FC.TextOut(Px(Pad), Y, ATitle);
  X := Px(Pad) + FC.TextWidth(ATitle) + Px(Gap) div 2;
  FC.Font.Style := [];
  if ADetail <> '' then
    FC.TextOut(X, Y, ADetail);
  Inc(Y, TextH + Px(Gap) div 2);
  FC.Pen.Style := psSolid;
  FC.Pen.Color := FLine;
  FC.Line(Px(Pad), Y, Width - Px(Pad), Y);
  Inc(Y, Px(Gap) div 2);
end;

{ ACaption as a link at the right edge, on the line of a heading whose
  text starts at ATop. }
procedure TGittanPullPage.PaintAction(ATop: integer; const ACaption, ALink: string);
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

{ A paragraph in AColor, wrapped to the width. }
procedure TGittanPullPage.PaintNote(var Y: integer; const AText: string; AColor: TColor);
var
  R: TRect;
  Style: TTextStyle;
begin
  Inc(Y, Px(Gap) div 2);
  FC.Font := Font;
  FC.Font.Color := AColor;
  FC.Brush.Style := bsClear;
  R := Rect(Px(Pad), Y, Width - Px(Pad), Y);
  Style := FC.TextStyle;
  Style.Wordbreak := True;
  Style.SingleLine := False;
  Style.Alignment := taLeftJustify;
  Style.Layout := tlTop;
  DrawText(FC.Handle, PChar(AText), Length(AText), R, DT_CALCRECT or DT_WORDBREAK);
  R.Right := Width - Px(Pad);
  FC.TextRect(R, R.Left, R.Top, AText, Style);
  Y := R.Bottom;
end;

{ A chip ending at ARight with its text in AColor on the hover fill;
  gives its left edge. }
function TGittanPullPage.PaintChip(ARight, ATop: integer; const AText: string;
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

{ The second line of a card: who opened it, its branches, when it was
  opened and last changed, what it changes and its labels. }
function TGittanPullPage.PullLine(const APull: TGittanPullRequest): string;
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
  Add(APull.Author);
  if (APull.HeadRef <> '') and (APull.BaseRef <> '') then
    Add(Format(rsInto, [APull.HeadRef, APull.BaseRef]));
  if APull.Created > 0 then
    Add(Format(rsOpened, [ReviewAge(APull.Created, UtcNow)]));
  if (APull.Updated > 0) and (MinutesBetween(APull.Updated, APull.Created) >= 1) then
    Add(Format(rsUpdated, [ReviewAge(APull.Updated, UtcNow)]));
  if APull.ChangedFiles = 1 then
    Add(Format('+%d −%d in ', [APull.Additions, APull.Deletions]) + rsChangedFile)
  else if APull.ChangedFiles > 1 then
    Add(Format('+%d −%d in ', [APull.Additions, APull.Deletions]) +
      Format(rsChangedFiles, [APull.ChangedFiles]));
  Add(APull.Labels);
end;

{ A card: the number dimmed and the title in bold, the chips of the
  state and the checks at the right, the second line under them with
  the GitHub link at its right end. The card compared against has a
  stripe in the link color and a Comparing chip, and one waiting for
  the user's review a chip saying so. }
procedure TGittanPullPage.PaintCard(var Y: integer; const APull: TGittanPullRequest;
  const ALink: string);
var
  R, LinkR: TRect;
  TextH, CardH, Right, X, ChipTop: integer;
  Number, Note, Line: string;
  Comparing: boolean;
  Tone: TColor;
begin
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  CardH := 2 * Px(CardPadY) + 2 * TextH + 4;
  R := Rect(Px(Pad), Y, Width - Px(Pad), Y + CardH);
  Comparing := (FComparing > 0) and (APull.Number = FComparing);
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FCard;
  if Assigned(FOnCompare) then
  begin
    AddLink(R, ALink);
    if FHot = High(FLinkRects) then
      FC.Brush.Color := FHover;
  end;
  FC.RoundRect(R, Px(CardRadius), Px(CardRadius));
  if Comparing then
  begin
    FC.Brush.Color := FLink;
    FC.RoundRect(R.Left, R.Top + Px(CardPadY), R.Left + Px(StripeWidth) + 2,
      R.Bottom - Px(CardPadY), Px(StripeWidth), Px(StripeWidth));
  end;
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;

  { The chips, right to left: the checks, then the state. }
  Right := R.Right - Px(CardPadX);
  ChipTop := R.Top + Px(CardPadY);
  if APull.ChecksFailed > 0 then
    Right := PaintChip(Right, ChipTop, Format(rsChecksFailing, [APull.ChecksFailed]),
      FErrorColor) - Px(Gap) div 2
  else if APull.ChecksPending > 0 then
    Right := PaintChip(Right, ChipTop, Format(rsChecksPending, [APull.ChecksPending]),
      FWarn) - Px(Gap) div 2
  else if APull.ChecksPassed > 0 then
    Right := PaintChip(Right, ChipTop, rsChecksOk, FOk) - Px(Gap) div 2;
  { The state: merged in the link color, approved in the ok color,
    changes requested in the error color, the rest dimmed. }
  Note := PullRequestNote(APull);
  if Note <> '' then
  begin
    if APull.State = 'MERGED' then
      Tone := FLink
    else if (APull.State = 'CLOSED') or APull.IsDraft then
      Tone := FDim
    else if APull.ReviewDecision = 'APPROVED' then
      Tone := FOk
    else if APull.ReviewDecision = 'CHANGES_REQUESTED' then
      Tone := FErrorColor
    else
      Tone := FDim;
    Right := PaintChip(Right, ChipTop, Note, Tone) - Px(Gap) div 2;
  end;
  if NeedsReview(APull.Number) then
    Right := PaintChip(Right, ChipTop, rsNeedsReview, FWarn) - Px(Gap) div 2;
  if Comparing then
    Right := PaintChip(Right, ChipTop, rsComparing, FLink) - Px(Gap) div 2;

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

  { The second line, with the GitHub link at its right end. }
  X := R.Left + Px(CardPadX);
  Right := R.Right - Px(CardPadX);
  if (APull.Url <> '') and Assigned(FOnOpenUrl) then
  begin
    LinkR := Rect(Right - FC.TextWidth(rsGitHubLink), R.Top + Px(CardPadY) + TextH + 4,
      Right, R.Top + Px(CardPadY) + 2 * TextH + 4);
    AddLink(LinkR, APull.Url);
    FC.Font.Color := FLink;
    if FHot = High(FLinkRects) then
      FC.Font.Style := [fsUnderline];
    FC.TextOut(LinkR.Left, LinkR.Top, rsGitHubLink);
    FC.Font.Style := [];
    Right := LinkR.Left - Px(Gap);
  end;
  Line := PullLine(APull);
  FC.Font.Color := FDim;
  FC.TextOut(X, R.Top + Px(CardPadY) + TextH + 4, FitTextRight(FC, Line, Max(0, Right - X)));
  Inc(Y, CardH + Px(CardGap));
end;

procedure TGittanPullPage.Paint;
begin
  FC := Canvas;
  PaintContent;
end;

procedure TGittanPullPage.PaintContent;
var
  Y, TextH, TitleH, HeadingTop, X, i: integer;
  Detail, Where: string;
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

  { The name with the page's title after it, under them the repository
    on GitHub as the first pull request's address names it, else the
    path; while gh is asked, that it is. }
  FC.Font.Size := TitleFontSize;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  TitleH := FC.TextHeight('Xg');
  FC.TextOut(Px(Pad), Y, FName);
  X := Px(Pad) + FC.TextWidth(FName) + Px(Gap);
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  FC.Font.Color := FDim;
  FC.TextOut(X, Y + TitleH - TextH - 3, rsPageTitle);
  Inc(Y, TitleH + 2);
  Where := '';
  if Length(FPulls) > 0 then
    Where := RepoPathOfUrl(FPulls[0].Url)
  else if FHasBranchPull then
    Where := RepoPathOfUrl(FBranchPull.Url);
  if Where = '' then
    Where := FRoot;
  if FLoading then
    Where := Where + ' · ' + rsLoading;
  FC.TextOut(Px(Pad), Y, FitTextLeft(FC, Where, Width - 2 * Px(Pad)));
  Inc(Y, TextH);

  if FHasBranchPull then
  begin
    PaintHeading(Y, rsBranchGroup, FBranchPull.HeadRef);
    PaintCard(Y, FBranchPull, BranchLink);
  end;

  if Length(FPulls) = 1 then
    Detail := rsOneOpen
  else if Length(FPulls) > 1 then
    Detail := Format(rsManyOpen, [Length(FPulls)])
  else
    Detail := '';
  HeadingTop := Y;
  PaintHeading(Y, rsOpenGroup, Detail);
  if Assigned(FOnRefresh) and not FLoading then
    PaintAction(HeadingTop + Px(Pad), rsRefresh, RefreshLink);
  if FError <> '' then
    PaintNote(Y, FError, FErrorColor)
  else if (Length(FPulls) = 0) and not FLoading then
    PaintNote(Y, rsNoPulls, FDim)
  else
    for i := 0 to High(FPulls) do
      PaintCard(Y, FPulls[i], CompareLink + IntToStr(i));

  { Layout sets the height from this. }
  FContentHeight := Y + Px(Pad);
end;

procedure TGittanPullPage.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(LinkAt(X, Y));
end;

procedure TGittanPullPage.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1);
end;

procedure TGittanPullPage.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  i, n: integer;
  Url: string;

  procedure Pick(const APull: TGittanPullRequest);
  begin
    if (FComparing > 0) and (APull.Number = FComparing) then
    begin
      if Assigned(FOnWorkingTree) then
        FOnWorkingTree(Self);
    end
    else if Assigned(FOnCompare) then
      FOnCompare(Self, APull);
  end;

begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  i := LinkAt(X, Y);
  if i < 0 then
    Exit;
  Url := FLinkUrls[i];
  if Copy(Url, 1, Length(CompareLink)) = CompareLink then
  begin
    n := StrToIntDef(Copy(Url, Length(CompareLink) + 1, MaxInt), -1);
    if (n >= 0) and (n <= High(FPulls)) then
      Pick(FPulls[n]);
  end
  else if Url = BranchLink then
  begin
    if FHasBranchPull then
      Pick(FBranchPull);
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
