unit gittan.hintbox;

{** A hint box: a line or two of text in a tinted box with rounded
  corners, with an icon before it if one is set: an image from a list,
  or a marker of the status bar (gittan.statusbar's HintBranch and the
  others) drawn in a color. Made for the note under the Commit button,
  which says what keeps a commit back, as "Tick the files to commit."
  with the tree's ticked box beside it, so the words point at the
  boxes. A warning (Warn) takes the second palette, for what has to be
  dealt with first, such as conflicts.

  It wraps its text to its width and takes the height that needs
  (AutoSize, aligned at the top), in colors the form sets. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, Controls, Graphics, ImgList, LCLType, LCLIntf,
  gittan.statusbar;

type

  { TGittanHintBox }

  TGittanHintBox = class(TCustomControl)
  private
    FText, FGlyph: string;
    FImages: TCustomImageList;
    FIcon: integer;
    FWarn: boolean;
    FBack, FLine, FWarnBack, FWarnLine, FGlyphColor: TColor;
    FLastWidth: integer;
    procedure SetText(const AValue: string);
    procedure SetImages(AValue: TCustomImageList);
    procedure SetIcon(AValue: integer);
    procedure SetGlyph(const AValue: string);
    procedure SetGlyphColor(AValue: TColor);
    procedure SetWarn(AValue: boolean);
    procedure Changed;
    function HasIcon: boolean;
    function TextLeft: integer;
    function TextHeight(AWidth: integer): integer;
  protected
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: integer;
      WithThemeSpace: boolean); override;
    procedure Resize; override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    {** The fill and the edge of the box, then those of a warning; the
      text takes Font.Color. }
    procedure SetColors(ABack, ALine, AWarnBack, AWarnLine: TColor);
    property Text: string read FText write SetText;
    {** Where Icon comes from. }
    property Images: TCustomImageList read FImages write SetImages;
    {** The image before the text, or -1 for none. }
    property Icon: integer read FIcon write SetIcon;
    {** A status bar marker drawn before the text in GlyphColor, in
      place of an image; empty for none. }
    property Glyph: string read FGlyph write SetGlyph;
    property GlyphColor: TColor read FGlyphColor write SetGlyphColor;
    {** Whether the box takes the warning palette. }
    property Warn: boolean read FWarn write SetWarn;
  end;

implementation

const
  PadX = 8;
  PadY = 6;
  IconSize = 16;
  Gap = 6;
  Corner = 10;

{ TGittanHintBox }

constructor TGittanHintBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FIcon := -1;
  FGlyphColor := clGrayText;
  AutoSize := True;
  Height := IconSize + 2 * PadY;
  SetColors(clInfoBk, clBtnShadow, clInfoBk, clBtnShadow);
end;

procedure TGittanHintBox.SetColors(ABack, ALine, AWarnBack, AWarnLine: TColor);
begin
  FBack := ABack;
  FLine := ALine;
  FWarnBack := AWarnBack;
  FWarnLine := AWarnLine;
  Invalidate;
end;

{ The text or the icon changed, so may the height. }
procedure TGittanHintBox.Changed;
begin
  InvalidatePreferredSize;
  AdjustSize;
  Invalidate;
end;

procedure TGittanHintBox.SetText(const AValue: string);
begin
  if FText = AValue then
    Exit;
  FText := AValue;
  Changed;
end;

procedure TGittanHintBox.SetImages(AValue: TCustomImageList);
begin
  if FImages = AValue then
    Exit;
  FImages := AValue;
  Changed;
end;

procedure TGittanHintBox.SetIcon(AValue: integer);
begin
  if FIcon = AValue then
    Exit;
  FIcon := AValue;
  Changed;
end;

procedure TGittanHintBox.SetGlyph(const AValue: string);
begin
  if FGlyph = AValue then
    Exit;
  FGlyph := AValue;
  Changed;
end;

procedure TGittanHintBox.SetGlyphColor(AValue: TColor);
begin
  if FGlyphColor = AValue then
    Exit;
  FGlyphColor := AValue;
  Invalidate;
end;

procedure TGittanHintBox.SetWarn(AValue: boolean);
begin
  if FWarn = AValue then
    Exit;
  FWarn := AValue;
  Invalidate;
end;

function TGittanHintBox.HasIcon: boolean;
begin
  Result := (FGlyph <> '') or ((FIcon >= 0) and (FImages <> nil));
end;

function TGittanHintBox.TextLeft: integer;
begin
  Result := PadX;
  if HasIcon then
    Inc(Result, IconSize + Gap);
end;

{ The height of the text wrapped to AWidth, measured on a bitmap since
  the box may have no handle yet. }
function TGittanHintBox.TextHeight(AWidth: integer): integer;
var
  Bmp: TBitmap;
  R: TRect;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(1, 1);
    Bmp.Canvas.Font := Font;
    R := Rect(0, 0, Max(AWidth, 1), 0);
    DrawText(Bmp.Canvas.Handle, PChar(FText), Length(FText), R,
      DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
    Result := R.Bottom - R.Top;
  finally
    Bmp.Free;
  end;
end;

procedure TGittanHintBox.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: integer; WithThemeSpace: boolean);
begin
  PreferredWidth := Width;
  PreferredHeight := Max(TextHeight(Width - TextLeft - PadX), IconSize) + 2 * PadY;
end;

{ A new width wraps the text anew. }
procedure TGittanHintBox.Resize;
begin
  inherited Resize;
  if Width <> FLastWidth then
  begin
    FLastWidth := Width;
    InvalidatePreferredSize;
    AdjustSize;
  end;
end;

procedure TGittanHintBox.Paint;
var
  R: TRect;
  Style: TTextStyle;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Parent.Brush.Color;
  Canvas.FillRect(ClientRect);
  Canvas.AntialiasingMode := amOn;
  if FWarn then
  begin
    Canvas.Brush.Color := FWarnBack;
    Canvas.Pen.Color := FWarnLine;
  end
  else
  begin
    Canvas.Brush.Color := FBack;
    Canvas.Pen.Color := FLine;
  end;
  Canvas.Pen.Width := 1;
  Canvas.RoundRect(0, 0, Width, Height, Corner, Corner);
  if FGlyph <> '' then
    DrawStatusIcon(Canvas, FGlyph, PadX, PadY - 1, IconSize + 2, FGlyphColor)
  else if HasIcon then
    FImages.DrawForPPI(Canvas, PadX, PadY, FIcon, IconSize,
      Font.PixelsPerInch, GetCanvasScaleFactor);
  Canvas.Pen.Width := 1;
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  R := Rect(TextLeft, PadY, Width - PadX, Height - PadY);
  { One line sits in the middle of the icon. }
  if TextHeight(R.Right - R.Left) < IconSize then
    OffsetRect(R, 0, (IconSize - Canvas.TextHeight('Xg')) div 2);
  Style := Canvas.TextStyle;
  Style.Wordbreak := True;
  Style.SingleLine := False;
  Style.Clipping := False;
  Canvas.TextRect(R, R.Left, R.Top, FText, Style);
end;

end.
