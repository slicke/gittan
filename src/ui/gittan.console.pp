unit gittan.console;

{** A console: a control that draws what a program wrote for a terminal,
  such as a git hook's output, in its font (the editor's, given by the
  owner) with the colors, bold, underline and the like of its escape
  sequences (read by gittan.terminal), so a hook's red cross is red
  and no "[31m" shows.

  The 16 colors are those of a terminal theme for the background it is
  given, a light or a dark one, so they read on either; the 256 colors
  and 24-bit ones are drawn as they are. Lines too long for it are cut
  at its right edge. It shows the lines from TopLine, trailing blank
  ones left out; the wheel scrolls them, and a thin bar at the right
  says where they are. With FollowEnd (while the program runs) it keeps
  the end in view and does not scroll. Text sets the text, Append adds
  to it as the program writes, and PlainText is the text without its
  sequences, for the clipboard. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, gittan.terminal;

type
  { TGittanConsole }

  TGittanConsole = class(TCustomControl)
  private
    FTerminal: TGittanTerminal;
    FText: string;
    FBack, FFore, FBar: TColor;
    FPalette: array[0..15] of TColor;
    FTop: integer;
    FFollowEnd: boolean;
    procedure SetText(const AValue: string);
    procedure SetFollowEnd(AValue: boolean);
    function Shown: integer;
    function ColorOf(AColor: longint; ADefault: TColor): TColor;
  protected
    procedure Paint; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: integer;
      MousePos: TPoint): boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** The background, the text in the default color and the scroll
      bar; the background chooses the light or the dark 16 colors. }
    procedure SetColors(ABack, AText, ABar: TColor);
    {** Adds what the program wrote next; the end stays in view when it
      was in view or FollowEnd is on. }
    procedure Append(const AChunk: string);
    {** The lines without the trailing blank ones. }
    function LineCount: integer;
    {** The height of a line in the font. }
    function LineHeight: integer;
    procedure ScrollTo(ATop: integer);
    {** Scrolls as the wheel turned by AWheelDelta over it would, unless
      FollowEnd is on. }
    procedure Wheel(AWheelDelta: integer);
    {** The text as the program wrote it; setting it shows its end. }
    property Text: string read FText write SetText;
    function PlainText: string;
    property TopLine: integer read FTop;
    property FollowEnd: boolean read FFollowEnd write SetFollowEnd;
    property Font;
  end;

implementation

uses
  Math;

const
  ScrollBarWidth = 4;
  BarGap = 8;

  { The 16 colors of VS Code's terminal, $RRGGBB. }
  DarkPalette: array[0..15] of longint = ($000000, $CD3131, $0DBC79, $E5E510,
    $2472C8, $BC3FBC, $11A8CD, $E5E5E5, $666666, $F14C4C, $23D18B, $F5F543,
    $3B8EEA, $D670D6, $29B8DB, $E5E5E5);
  LightPalette: array[0..15] of longint = ($000000, $CD3131, $00BC00, $949800,
    $0451A5, $BC05BC, $0598BC, $555555, $666666, $CD3131, $14CE14, $B5BA00,
    $0451A5, $BC05BC, $0598BC, $A5A5A5);

function RGBColor(ARGB: longint): TColor;
begin
  Result := RGBToColor((ARGB shr 16) and $FF, (ARGB shr 8) and $FF, ARGB and $FF);
end;

function Blend(A, B: TColor; APercent: integer): TColor;
var
  CA, CB: TColor;
begin
  CA := ColorToRGB(A);
  CB := ColorToRGB(B);
  Result := RGBToColor(
    (Red(CA) * (100 - APercent) + Red(CB) * APercent) div 100,
    (Green(CA) * (100 - APercent) + Green(CB) * APercent) div 100,
    (Blue(CA) * (100 - APercent) + Blue(CB) * APercent) div 100);
end;

{ TGittanConsole }

constructor TGittanConsole.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FTerminal := TGittanTerminal.Create;
  SetColors(clWindow, clWindowText, clBtnShadow);
end;

destructor TGittanConsole.Destroy;
begin
  FTerminal.Free;
  inherited Destroy;
end;

procedure TGittanConsole.SetColors(ABack, AText, ABar: TColor);
var
  C: TColor;
  i: integer;
begin
  FBack := ABack;
  FFore := AText;
  FBar := ABar;
  Color := ABack;
  C := ColorToRGB(ABack);
  for i := 0 to 15 do
    if Red(C) * 299 + Green(C) * 587 + Blue(C) * 114 < 128000 then
      FPalette[i] := RGBColor(DarkPalette[i])
    else
      FPalette[i] := RGBColor(LightPalette[i]);
  Invalidate;
end;

function TGittanConsole.ColorOf(AColor: longint; ADefault: TColor): TColor;
begin
  if AColor = TermDefault then
    Result := ADefault
  else if AColor and TermRGB <> 0 then
    Result := RGBColor(AColor and $FFFFFF)
  else if AColor < 16 then
    Result := FPalette[AColor]
  else
    Result := RGBColor(TermPaletteRGB(AColor));
end;

procedure TGittanConsole.SetText(const AValue: string);
begin
  FText := AValue;
  FTerminal.Clear;
  FTerminal.Append(AValue);
  FTop := MaxInt;
  Invalidate;
end;

procedure TGittanConsole.Append(const AChunk: string);
var
  AtEnd: boolean;
begin
  if AChunk = '' then
    Exit;
  AtEnd := FFollowEnd or (FTop >= LineCount - Shown);
  FText := FText + AChunk;
  FTerminal.Append(AChunk);
  if AtEnd then
    FTop := MaxInt;
  Invalidate;
end;

procedure TGittanConsole.SetFollowEnd(AValue: boolean);
begin
  FFollowEnd := AValue;
  if AValue then
    FTop := MaxInt;
  Invalidate;
end;

function TGittanConsole.PlainText: string;
begin
  Result := FTerminal.PlainText;
end;

function TGittanConsole.LineCount: integer;
begin
  Result := FTerminal.Count;
  while (Result > 0) and (Trim(FTerminal[Result - 1].Text) = '') do
    Dec(Result);
end;

function TGittanConsole.LineHeight: integer;
begin
  if not HandleAllocated then
    Exit(Max(16, Abs(Font.Height) + 4));
  Canvas.Font := Font;
  Result := Max(1, Canvas.TextHeight('Xg'));
end;

function TGittanConsole.Shown: integer;
begin
  Result := Max(1, ClientHeight div LineHeight);
end;

procedure TGittanConsole.ScrollTo(ATop: integer);
begin
  ATop := Max(0, Min(ATop, LineCount - Shown));
  if ATop = FTop then
    Exit;
  FTop := ATop;
  Invalidate;
end;

procedure TGittanConsole.Wheel(AWheelDelta: integer);
begin
  if FFollowEnd or (LineCount <= Shown) then
    Exit;
  FTop := Max(0, Min(FTop, LineCount - Shown));
  ScrollTo(FTop - Sign(AWheelDelta) * Max(1, Abs(AWheelDelta) div 40));
end;

function TGittanConsole.DoMouseWheel(Shift: TShiftState; WheelDelta: integer;
  MousePos: TPoint): boolean;
begin
  Result := True;
  Wheel(WheelDelta);
end;

procedure TGittanConsole.Paint;
var
  LH, Count, InView, Right, X, Y, i, j, W, BarTop, BarHeight: integer;
  Line: TGittanTermLine;
  Fore, Back, Swap: TColor;
  Styles: TFontStyles;
  S: string;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  LH := LineHeight;
  Count := LineCount;
  InView := Max(1, ClientHeight div LH);
  { MaxInt, from Text or Append, is the end. }
  if FFollowEnd then
    FTop := MaxInt;
  FTop := Max(0, Min(FTop, Count - InView));
  Right := ClientWidth;
  if Count > InView then
    Dec(Right, ScrollBarWidth + BarGap);

  for i := FTop to Min(Count - 1, FTop + InView - 1) do
  begin
    Line := FTerminal[i];
    Y := (i - FTop) * LH;
    X := 0;
    for j := 0 to High(Line.Spans) do
    begin
      if X >= Right then
        Break;
      with Line.Spans[j] do
      begin
        S := Copy(Line.Text, Start, Len);
        Fore := ColorOf(Style.Fore, FFore);
        Back := ColorOf(Style.Back, FBack);
        if taInverse in Style.Attrs then
        begin
          Swap := Fore;
          Fore := Back;
          Back := Swap;
        end;
        if taDim in Style.Attrs then
          Fore := Blend(Fore, Back, 50);
        Styles := [];
        if taBold in Style.Attrs then
          Include(Styles, fsBold);
        if taItalic in Style.Attrs then
          Include(Styles, fsItalic);
        if taUnderline in Style.Attrs then
          Include(Styles, fsUnderline);
        if taStrike in Style.Attrs then
          Include(Styles, fsStrikeOut);
        Canvas.Font.Style := Styles;
        Canvas.Font.Color := Fore;
        W := Canvas.TextWidth(S);
        if Back <> FBack then
        begin
          Canvas.Brush.Style := bsSolid;
          Canvas.Brush.Color := Back;
          Canvas.FillRect(Rect(X, Y, Min(X + W, Right), Y + LH));
        end;
        Canvas.Brush.Style := bsClear;
        Canvas.TextRect(Rect(X, Y, Right, Y + LH), X, Y, S);
        Inc(X, W);
      end;
    end;
  end;

  { A thin bar at the right says where the lines in view are. }
  if Count > InView then
  begin
    BarHeight := Max(12, InView * LH * InView div Count);
    BarTop := (InView * LH - BarHeight) * FTop div Max(1, Count - InView);
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FBar;
    Canvas.RoundRect(ClientWidth - ScrollBarWidth, BarTop, ClientWidth,
      BarTop + BarHeight, ScrollBarWidth, ScrollBarWidth);
    Canvas.Pen.Style := psSolid;
  end;
end;

end.
