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

end.
