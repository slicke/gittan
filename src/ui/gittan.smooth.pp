{ Filled shapes with smooth edges.

  Cocoa smooths what a TCanvas fills, GDI on Windows and the LCL's GTK 3
  canvas do not: a pill or a disc drawn with RoundRect or Ellipse there
  has stepped edges, which shows on the status bar's main button and the
  large check of a clean tree. These draw the shape with BGRABitmap's
  antialiasing into a transparent bitmap at the canvas's scale factor
  (2 on a Retina screen) and lay that over the canvas, as the notice's
  sparkle and the avatars are drawn. }
unit gittan.smooth;

{$mode objfpc}{$H+}

interface

uses
  Types, Graphics;

{** Fills R in AColor with corners rounded as RoundRect's with
  ADiameter: R's height gives a pill. }
procedure SmoothRoundRect(ACanvas: TCanvas; const R: TRect; ADiameter: integer;
  AColor: TColor; AScale: double);

{** Fills the ellipse in R in AColor. }
procedure SmoothEllipse(ACanvas: TCanvas; const R: TRect; AColor: TColor;
  AScale: double);

{** A disc ASize across at X, Y in AFill with a check in AInk, its line
  APenWidth wide, as a clean tree shows it. }
procedure SmoothCheckDisc(ACanvas: TCanvas; X, Y, ASize: integer;
  AFill, AInk: TColor; APenWidth: single; AScale: double);

{** A line AWidth wide that leaves AX, AY upright, turns in a quarter
  circle of at most ARadius and reaches BX, BY level. }
procedure SmoothBend(ACanvas: TCanvas; AX, AY, BX, BY, ARadius, AWidth: integer;
  AColor: TColor; AScale: double);

{** A ring of dashes around X, Y. }
procedure SmoothDashRing(ACanvas: TCanvas; X, Y, ARadius: integer; AWidth: single;
  AColor: TColor; AScale: double);

implementation

uses
  Math, BGRABitmap, BGRABitmapTypes;

function NewLayer(const R: TRect; AScale: double; out S: single): TBGRABitmap;
begin
  S := Max(AScale, 1);
  Result := TBGRABitmap.Create(Max(1, Round((R.Right - R.Left) * S)),
    Max(1, Round((R.Bottom - R.Top) * S)), BGRAPixelTransparent);
end;

function Pixel(AColor: TColor): TBGRAPixel;
begin
  Result := ColorToBGRA(ColorToRGB(AColor));
end;

procedure SmoothRoundRect(ACanvas: TCanvas; const R: TRect; ADiameter: integer;
  AColor: TColor; AScale: double);
var
  Bmp: TBGRABitmap;
  S, Radius: single;
begin
  if (R.Right <= R.Left) or (R.Bottom <= R.Top) then
    Exit;
  Bmp := NewLayer(R, AScale, S);
  try
    Radius := Min(ADiameter * S / 2, Min(Bmp.Width, Bmp.Height) / 2);
    Bmp.FillRoundRectAntialias(-0.5, -0.5, Bmp.Width - 0.5, Bmp.Height - 0.5,
      Radius, Radius, Pixel(AColor));
    Bmp.Draw(ACanvas, R, False);
  finally
    Bmp.Free;
  end;
end;

procedure SmoothEllipse(ACanvas: TCanvas; const R: TRect; AColor: TColor;
  AScale: double);
var
  Bmp: TBGRABitmap;
  S: single;
begin
  if (R.Right <= R.Left) or (R.Bottom <= R.Top) then
    Exit;
  Bmp := NewLayer(R, AScale, S);
  try
    Bmp.FillEllipseAntialias((Bmp.Width - 1) / 2, (Bmp.Height - 1) / 2,
      Bmp.Width / 2, Bmp.Height / 2, Pixel(AColor));
    Bmp.Draw(ACanvas, R, False);
  finally
    Bmp.Free;
  end;
end;

procedure SmoothCheckDisc(ACanvas: TCanvas; X, Y, ASize: integer;
  AFill, AInk: TColor; APenWidth: single; AScale: double);
var
  Bmp: TBGRABitmap;
  R: TRect;
  S, D, C: single;
begin
  if ASize <= 0 then
    Exit;
  R := Rect(X, Y, X + ASize, Y + ASize);
  Bmp := NewLayer(R, AScale, S);
  try
    D := Bmp.Width;
    C := (D - 1) / 2;
    Bmp.FillEllipseAntialias(C, C, D / 2, D / 2, Pixel(AFill));
    Bmp.LineCap := pecRound;
    Bmp.JoinStyle := pjsRound;
    Bmp.DrawPolyLineAntialias([PointF(D * 0.27, D * 0.5),
      PointF(D * 0.44, D * 0.67), PointF(D * 0.74, D * 0.33)],
      Pixel(AInk), APenWidth * S);
    Bmp.Draw(ACanvas, R, False);
  finally
    Bmp.Free;
  end;
end;

procedure SmoothBend(ACanvas: TCanvas; AX, AY, BX, BY, ARadius, AWidth: integer;
  AColor: TColor; AScale: double);
const
  Steps = 12;
var
  Bmp: TBGRABitmap;
  R: TRect;
  S, Turn, DX, DY, A: single;
  Points: array[0..Steps + 2] of TPointF;
  i: integer;

  { A point of the canvas in the bitmap, whose pixels have their middle
    at whole numbers. }
  function At(X, Y: single): TPointF;
  begin
    Result := PointF((X - R.Left) * S - 0.5, (Y - R.Top) * S - 0.5);
  end;

begin
  { Not past AY, where the next piece of the line begins. }
  R := Rect(Min(AX, BX) - AWidth, Min(AY, BY - AWidth), Max(AX, BX) + AWidth,
    Max(AY, BY + AWidth));
  DX := Sign(BX - AX);
  DY := Sign(BY - AY);
  Turn := Min(ARadius, Min(Abs(BX - AX), Abs(BY - AY)));
  Bmp := NewLayer(R, AScale, S);
  try
    Points[0] := At(AX, AY);
    for i := 0 to Steps do
    begin
      A := Pi / 2 * i / Steps;
      Points[i + 1] := At(AX + DX * Turn * (1 - Cos(A)), BY - DY * Turn * (1 - Sin(A)));
    end;
    Points[Steps + 2] := At(BX, BY);
    Bmp.LineCap := pecFlat;
    Bmp.JoinStyle := pjsRound;
    Bmp.DrawPolyLineAntialias(Points, Pixel(AColor), AWidth * S);
    Bmp.Draw(ACanvas, R, False);
  finally
    Bmp.Free;
  end;
end;

procedure SmoothDashRing(ACanvas: TCanvas; X, Y, ARadius: integer; AWidth: single;
  AColor: TColor; AScale: double);
const
  Dashes = 6;
  Steps = 4;
var
  Bmp: TBGRABitmap;
  R: TRect;
  S, C, A: single;
  Points: array[0..Steps] of TPointF;
  i, k: integer;
begin
  R := Rect(X - ARadius - 1, Y - ARadius - 1, X + ARadius + 1, Y + ARadius + 1);
  Bmp := NewLayer(R, AScale, S);
  try
    C := (Bmp.Width - 1) / 2;
    Bmp.LineCap := pecFlat;
    Bmp.JoinStyle := pjsRound;
    for i := 0 to Dashes - 1 do
    begin
      for k := 0 to Steps do
      begin
        A := 2 * Pi * (i + 0.6 * k / Steps) / Dashes;
        Points[k] := PointF(C + Cos(A) * (ARadius - AWidth / 2) * S,
          C + Sin(A) * (ARadius - AWidth / 2) * S);
      end;
      Bmp.DrawPolyLineAntialias(Points, Pixel(AColor), AWidth * S);
    end;
    Bmp.Draw(ACanvas, R, False);
  finally
    Bmp.Free;
  end;
end;

end.
