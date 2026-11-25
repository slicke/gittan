unit gittan.refmark;

{** The small marks of the commit graph's rows: what a label stands for
  (a local branch, a remote one, a tag) and the disc with an author's
  initials. They are drawn with smooth edges, see gittan.smooth. }

{$mode objfpc}{$H+}

interface

uses
  Types, Graphics;

type
  {** A laptop for a local branch, a cloud for a remote one, a tag. }
  TGittanRefMark = (rmLocal, rmRemote, rmTag);

{** AMark ASize square at ALeft, ATop. }
procedure PaintRefMark(ACanvas: TCanvas; ALeft, ATop, ASize: integer;
  AMark: TGittanRefMark; AColor: TColor; AScale: double);

{** The first letters of the first and the last word of AName. }
function Initials(const AName: string): string;

{** AInitials in a disc ASize across; ACanvas.Font is the text's, and is
  changed. }
procedure PaintInitials(ACanvas: TCanvas; ALeft, ATop, ASize: integer;
  const AInitials: string; AColor: TColor; AScale: double);

{** Black or white, whichever reads better on AColor. }
function InkOn(AColor: TColor): TColor;

implementation

uses
  SysUtils, Math, LazUTF8, BGRABitmap, BGRABitmapTypes, gittan.smooth;

procedure PaintRefMark(ACanvas: TCanvas; ALeft, ATop, ASize: integer;
  AMark: TGittanRefMark; AColor: TColor; AScale: double);
var
  Bmp: TBGRABitmap;
  D, W: single;
  Ink: TBGRAPixel;

  { A point of a 12 by 12 drawing. }
  function At(X, Y: single): TPointF;
  begin
    Result := PointF(X * D / 12 - 0.5, Y * D / 12 - 0.5);
  end;

begin
  if ASize <= 0 then
    Exit;
  Bmp := TBGRABitmap.Create(Max(1, Round(ASize * Max(AScale, 1))),
    Max(1, Round(ASize * Max(AScale, 1))), BGRAPixelTransparent);
  try
    D := Bmp.Width;
    W := D / 12 * 1.2;
    Ink := ColorToBGRA(ColorToRGB(AColor));
    Bmp.LineCap := pecRound;
    Bmp.JoinStyle := pjsRound;
    case AMark of
      rmLocal:
      begin
        Bmp.DrawPolygonAntialias([At(2.2, 2.5), At(9.8, 2.5), At(9.8, 7.8), At(2.2, 7.8)],
          Ink, W);
        Bmp.DrawLineAntialias(At(0.8, 10).X, At(0.8, 10).Y, At(11.2, 10).X, At(11.2, 10).Y,
          Ink, W, True);
      end;
      rmRemote:
        { A cloud as one closed curve around its humps. }
        Bmp.DrawPolygonAntialias(Bmp.ComputeClosedSpline([At(2.8, 9.4), At(0.9, 7.6),
          At(2.3, 5.5), At(4.6, 2.8), At(7.6, 4), At(8.4, 5.2), At(10.9, 6),
          At(10.9, 8.6), At(9.2, 9.4)], ssCrossing), Ink, W);
      rmTag:
      begin
        Bmp.DrawPolygonAntialias([At(1.5, 1.5), At(6.2, 1.5), At(10.8, 6.1), At(6.1, 10.8),
          At(1.5, 6.2)], Ink, W);
        Bmp.FillEllipseAntialias(At(4, 4).X, At(4, 4).Y, W * 0.75, W * 0.75, Ink);
      end;
    end;
    Bmp.Draw(ACanvas, Rect(ALeft, ATop, ALeft + ASize, ATop + ASize), False);
  finally
    Bmp.Free;
  end;
end;

function Initials(const AName: string): string;
var
  Words: TStringArray;
  First, Last: string;
begin
  Words := Trim(AName).Split([' '], TStringSplitOptions.ExcludeEmpty);
  if Length(Words) = 0 then
    Exit('?');
  First := UTF8Copy(Words[0], 1, 1);
  if Length(Words) > 1 then
    Last := UTF8Copy(Words[High(Words)], 1, 1)
  else
    Last := '';
  Result := UTF8UpperCase(First + Last);
end;

procedure PaintInitials(ACanvas: TCanvas; ALeft, ATop, ASize: integer;
  const AInitials: string; AColor: TColor; AScale: double);
begin
  SmoothEllipse(ACanvas, Rect(ALeft, ATop, ALeft + ASize, ATop + ASize), AColor, AScale);
  ACanvas.Brush.Style := bsClear;
  { As high as fits two letters, whatever the text's own size. }
  ACanvas.Font.Height := -Max(7, ASize div 2);
  ACanvas.Font.Style := [fsBold];
  ACanvas.Font.Color := InkOn(AColor);
  ACanvas.TextOut(ALeft + (ASize - ACanvas.TextWidth(AInitials)) div 2,
    ATop + (ASize - ACanvas.TextHeight(AInitials)) div 2, AInitials);
end;

function InkOn(AColor: TColor): TColor;

  function Linear(AChannel: byte): double;
  begin
    Result := Power(AChannel / 255, 2.2);
  end;

var
  C: TColor;
begin
  C := ColorToRGB(AColor);
  { Where black and white have the same contrast. }
  if 0.2126 * Linear(Red(C)) + 0.7152 * Linear(Green(C)) + 0.0722 * Linear(Blue(C)) > 0.179 then
    Result := clBlack
  else
    Result := clWhite;
end;

end.
