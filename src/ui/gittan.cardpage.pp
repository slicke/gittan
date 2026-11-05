unit gittan.cardpage;

{** What the forge view's pages that paint themselves share: the Batch
  tab's (gittan.batchpage) and an extension's tab (gittan.extpage). The
  forge palette (ForgePalette), the links painted (AddLink, LinkAt) with
  the one under the mouse (SetHot), pills, wrapped paragraphs, and the
  height measured on a measuring canvas before the page is shown
  (Layout), never grown in its first Paint. A page paints its content in
  PaintContent, on FC, and sets FContentHeight there. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics;

const
  {** A pill's padding, and the puzzle piece an extension's pill has
    before its text. }
  PillPadX = 10;
  PillPadY = 3;
  PuzzleSide = 11;
  PuzzleGap = 5;

type

  { TGittanCardPage }

  TGittanCardPage = class(TCustomControl)
  protected
    FBack, FText, FDim, FHover, FLine, FLink, FOk, FWarn, FErrorColor, FCard: TColor;
    FLinkRects: array of TRect;
    FLinkUrls: array of string;
    FHot, FContentHeight: integer;
    { The canvas the content is painted on: the control's in Paint, a
      measuring one in Layout. }
    FC: TCanvas;
    procedure AddLink(const ARect: TRect; const AUrl: string);
    function LinkAt(X, Y: integer): integer;
    procedure SetHot(AValue: integer);
    function PillWidth(const AText: string; AExt: boolean = False): integer;
    {** A button as a pill, its text at ALeft, ATop: APrimary in the link
      color, else outlined; AExt with the puzzle piece before the text; a
      link only while AEnabled, dim otherwise. Gives its rectangle. }
    function PaintPill(ALeft, ATop: integer; const AText, ALink: string;
      APrimary, AEnabled: boolean; AExt: boolean = False): TRect;
    {** A paragraph in AColor, wrapped between ALeft and ARight. }
    procedure PaintText(var Y: integer; const AText: string; AColor: TColor;
      ALeft, ARight: integer);
    {** The height of AText wrapped in AWidth, in the canvas's font. }
    function WrappedHeight(const AText: string; AWidth: integer): integer;
    {** Paints everything on FC, links added as it goes, and sets
      FContentHeight. }
    procedure PaintContent; virtual; abstract;
    {** The content painted on the measuring canvas, for its height; the
      height is set here, never in Paint. }
    procedure Layout;
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetTheme(ADark: boolean);
    {** At least AMin high, the view's height, measured again. }
    procedure FitHeight(AMin: integer);
  end;

implementation

uses
  Math, LCLIntf, LCLType, gittan.forgepage, gittan.textfit, gittan.theme, gittan.puzzle;

constructor TGittanCardPage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FHot := -1;
  Align := alTop;
  SetTheme(False);
end;

procedure TGittanCardPage.SetTheme(ADark: boolean);
var
  P: TGittanForgePalette;
begin
  P := ForgePalette(ADark);
  FBack := P.Back;
  FText := P.Text;
  FDim := P.Dim;
  FHover := P.Hover;
  FLine := P.Line;
  FLink := P.Link;
  FOk := P.Ok;
  FWarn := P.Warn;
  FErrorColor := P.Error;
  FCard := P.Card;
  Color := FBack;
  Invalidate;
end;

procedure TGittanCardPage.AddLink(const ARect: TRect; const AUrl: string);
begin
  SetLength(FLinkRects, Length(FLinkRects) + 1);
  SetLength(FLinkUrls, Length(FLinkUrls) + 1);
  FLinkRects[High(FLinkRects)] := ARect;
  FLinkUrls[High(FLinkUrls)] := AUrl;
end;

function TGittanCardPage.LinkAt(X, Y: integer): integer;
var
  i: integer;
begin
  { The last link added wins: a card's rows and pills lie on it. }
  for i := High(FLinkRects) downto 0 do
    if PtInRect(FLinkRects[i], Point(X, Y)) then
      Exit(i);
  Result := -1;
end;

procedure TGittanCardPage.SetHot(AValue: integer);
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

function TGittanCardPage.PillWidth(const AText: string; AExt: boolean): integer;
begin
  FC.Font := Font;
  Result := FC.TextWidth(AText) + 2 * Px(PillPadX);
  if AExt then
    Inc(Result, Px(PuzzleSide) + Px(PuzzleGap));
end;

function TGittanCardPage.PaintPill(ALeft, ATop: integer; const AText, ALink: string;
  APrimary, AEnabled, AExt: boolean): TRect;
var
  TextH: integer;
  Hot: boolean;
begin
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  Result := Rect(ALeft, ATop - Px(PillPadY), ALeft + PillWidth(AText, AExt),
    ATop + TextH + Px(PillPadY));
  Hot := False;
  if AEnabled then
  begin
    AddLink(Result, ALink);
    Hot := FHot = High(FLinkRects);
  end;
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsSolid;
  if not AEnabled then
  begin
    FC.Pen.Color := MixColor(FBack, FLine, 0.6);
    FC.Brush.Color := FBack;
    FC.Font.Color := MixColor(FBack, FDim, 0.7);
  end
  else if APrimary then
  begin
    FC.Pen.Color := FLink;
    if Hot then
      FC.Brush.Color := MixColor(FBack, FLink, 0.3)
    else
      FC.Brush.Color := MixColor(FBack, FLink, 0.18);
    FC.Font.Color := FLink;
  end
  else
  begin
    FC.Pen.Color := FLine;
    if Hot then
    begin
      FC.Brush.Color := FHover;
      FC.Font.Color := FText;
    end
    else
    begin
      FC.Brush.Color := FBack;
      FC.Font.Color := FDim;
    end;
  end;
  FC.RoundRect(Result, Result.Height, Result.Height);
  FC.Brush.Style := bsClear;
  if AExt then
  begin
    { An extension's: the puzzle piece before the text, in its color. }
    PaintPuzzle(FC, Result.Left + Px(PillPadX), ATop + (TextH - Px(PuzzleSide)) div 2,
      Px(PuzzleSide), FC.Font.Color);
    FC.Brush.Style := bsClear;
    FC.TextOut(Result.Left + Px(PillPadX) + Px(PuzzleSide) + Px(PuzzleGap), ATop, AText);
  end
  else
    FC.TextOut(Result.Left + Px(PillPadX), ATop, AText);
  FC.Font := Font;
end;

procedure TGittanCardPage.PaintText(var Y: integer; const AText: string; AColor: TColor;
  ALeft, ARight: integer);
var
  R: TRect;
  Style: TTextStyle;
begin
  FC.Font := Font;
  FC.Font.Color := AColor;
  FC.Brush.Style := bsClear;
  R := Rect(ALeft, Y, ARight, Y + WrappedHeight(AText, ARight - ALeft));
  Style := FC.TextStyle;
  Style.Wordbreak := True;
  Style.SingleLine := False;
  Style.Alignment := taLeftJustify;
  Style.Layout := tlTop;
  FC.TextRect(R, R.Left, R.Top, AText, Style);
  Y := R.Bottom;
end;

function TGittanCardPage.WrappedHeight(const AText: string; AWidth: integer): integer;
var
  R: TRect;
begin
  R := Rect(0, 0, AWidth, 0);
  DrawText(FC.Handle, PChar(AText), Length(AText), R, DT_CALCRECT or DT_WORDBREAK);
  Result := Max(R.Bottom, FC.TextHeight('Xg'));
end;

procedure TGittanCardPage.Layout;
var
  H: integer;
begin
  if (Parent = nil) or (Width <= 0) then
  begin
    Invalidate;
    Exit;
  end;
  FC := MeasureCanvas(Font);
  PaintContent;
  H := Max(FContentHeight, Constraints.MinHeight);
  if Height <> H then
    Height := H;
  Invalidate;
end;

procedure TGittanCardPage.FitHeight(AMin: integer);
begin
  Constraints.MinHeight := AMin;
  Layout;
end;

procedure TGittanCardPage.Paint;
begin
  FC := Canvas;
  PaintContent;
end;

procedure TGittanCardPage.Resize;
begin
  inherited Resize;
  Layout;
end;

procedure TGittanCardPage.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(LinkAt(X, Y));
end;

procedure TGittanCardPage.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1);
end;

end.
