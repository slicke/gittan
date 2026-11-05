unit gittan.puzzle;

{** The puzzle piece that marks what an extension added to the forge
  view: its tabs in the window's tab strip, its operations' pills on the
  Batch tab and the head of its tab (spec/extensions.md). A square body
  with a knob on its top and one on its right, three shapes filled in
  one color, so they read as one at any size; PuzzleParts gives them for
  a box of a size, for the Cocoa tab strip's paths, PaintPuzzle draws
  them on an LCL canvas, which smooths them on macOS and GTK. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics;

type
  {** A rectangle in a box's own coordinates, y down. }
  TPuzzleRect = record
    X, Y, W, H: double;
  end;

{** The body (a rounded square, its corner's radius ARadius), the top
  knob and the right knob (circles in their squares) of a piece in a box
  ASize wide and high. }
procedure PuzzleParts(ASize: double; out ABody, ATop, ARight: TPuzzleRect;
  out ARadius: double);

{** The piece in AColor in the box of ASize at ALeft, ATop; the canvas's
  pen and brush are left as they were. }
procedure PaintPuzzle(ACanvas: TCanvas; ALeft, ATop, ASize: integer; AColor: TColor);

implementation

procedure PuzzleParts(ASize: double; out ABody, ATop, ARight: TPuzzleRect;
  out ARadius: double);
const
  Knob = 0.34;
begin
  ABody.X := 0;
  ABody.Y := 0.24 * ASize;
  ABody.W := 0.76 * ASize;
  ABody.H := 0.76 * ASize;
  ATop.W := Knob * ASize;
  ATop.H := ATop.W;
  ATop.X := ABody.X + (ABody.W - ATop.W) / 2;
  ATop.Y := 0;
  ARight.W := ATop.W;
  ARight.H := ATop.W;
  ARight.X := ASize - ARight.W;
  ARight.Y := ABody.Y + (ABody.H - ARight.H) / 2;
  ARadius := 0.08 * ASize;
end;

procedure PaintPuzzle(ACanvas: TCanvas; ALeft, ATop, ASize: integer; AColor: TColor);
var
  Body, KnobTop, KnobRight: TPuzzleRect;
  Radius: double;
  B: TRect;
  OldBrush: TBrushStyle;
  OldBrushColor, OldPenColor: TColor;
  OldPen: TPenStyle;

  function R(const AR: TPuzzleRect): TRect;
  begin
    Result := Rect(ALeft + Round(AR.X), ATop + Round(AR.Y), ALeft + Round(AR.X + AR.W),
      ATop + Round(AR.Y + AR.H));
  end;

begin
  if ASize < 4 then
    Exit;
  PuzzleParts(ASize, Body, KnobTop, KnobRight, Radius);
  OldBrush := ACanvas.Brush.Style;
  OldBrushColor := ACanvas.Brush.Color;
  OldPen := ACanvas.Pen.Style;
  OldPenColor := ACanvas.Pen.Color;
  try
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := AColor;
    ACanvas.Pen.Style := psSolid;
    ACanvas.Pen.Color := AColor;
    B := R(Body);
    ACanvas.RoundRect(B.Left, B.Top, B.Right, B.Bottom, Round(2 * Radius), Round(2 * Radius));
    B := R(KnobTop);
    ACanvas.Ellipse(B.Left, B.Top, B.Right, B.Bottom);
    B := R(KnobRight);
    ACanvas.Ellipse(B.Left, B.Top, B.Right, B.Bottom);
  finally
    ACanvas.Brush.Style := OldBrush;
    ACanvas.Brush.Color := OldBrushColor;
    ACanvas.Pen.Style := OldPen;
    ACanvas.Pen.Color := OldPenColor;
  end;
end;

end.
