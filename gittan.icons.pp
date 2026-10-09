unit gittan.icons;

{** Icons for Gittan's file tree and editor buttons.

  The icons are drawn at startup with BGRABitmap instead of being shipped as
  image files: a folder, and one badge per change kind carrying the letter
  git status uses for it. Every icon is drawn at 16 and 32 pixels so it stays
  sharp on a HiDPI screen. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, ImgList, gittan.git;

const
  {** Image index of the folder icon. }
  iconFolder = 0;

{** Image index of the badge for AKind. }
function ChangeIcon(AKind: TGittanChangeKind): integer;

{** Fills the empty list AImages with the folder icon at iconFolder and the
  change badges at ChangeIcon. }
procedure FillTreeIcons(AImages: TCustomImageList);

const
  {** Image index of the "next change" arrow in the list FillButtonIcons fills. }
  iconArrowDown = 0;

{** Fills the empty list AImages with the icons of the editor's buttons. }
procedure FillButtonIcons(AImages: TCustomImageList);

implementation

uses
  Graphics, BGRABitmap, BGRABitmapTypes;

const
  BadgeLetter: array[TGittanChangeKind] of string = ('M', 'A', 'D', 'R', 'U', '!');

function ChangeIcon(AKind: TGittanChangeKind): integer;
begin
  Result := iconFolder + 1 + Ord(AKind);
end;

{ Green for new content, red for removed, blue for a move, purple for a
  conflict and orange for the common case, a modified file. }
function BadgeColor(AKind: TGittanChangeKind): TBGRAPixel;
begin
  case AKind of
    ckAdded, ckUntracked: Result := BGRA($2E, $A0, $43);
    ckDeleted: Result := BGRA($D8, $3A, $3A);
    ckRenamed: Result := BGRA($2F, $80, $D8);
    ckConflict: Result := BGRA($9B, $3F, $C8);
    else
      Result := BGRA($E0, $8A, $1E);
  end;
end;

{ A folder: a tab above a body, in a neutral blue-gray. Coordinates are in
  16ths of the icon so the 32 pixel version is the same shape. }
function DrawFolder(ASize: integer): TBGRABitmap;
var
  s: single;
  Color: TBGRAPixel;
begin
  Result := TBGRABitmap.Create(ASize, ASize, BGRAPixelTransparent);
  s := ASize / 16;
  Color := BGRA($7A, $8C, $A6);
  Result.FillRoundRectAntialias(1 * s, 2 * s, 8 * s, 7 * s, 1.5 * s, 1.5 * s, Color);
  Result.FillRoundRectAntialias(1 * s, 4 * s, 15 * s, 13 * s, 1.5 * s, 1.5 * s, Color);
end;

{ A rounded square in the kind's color with its letter in white. }
function DrawBadge(ASize: integer; AKind: TGittanChangeKind): TBGRABitmap;
var
  s: single;
begin
  Result := TBGRABitmap.Create(ASize, ASize, BGRAPixelTransparent);
  s := ASize / 16;
  Result.FillRoundRectAntialias(1 * s, 1 * s, 15 * s, 15 * s, 3 * s, 3 * s,
    BadgeColor(AKind));
  Result.FontName := 'default';
  Result.FontStyle := [fsBold];
  Result.FontQuality := fqFineAntialiasing;
  Result.FontFullHeight := Round(12 * s);
  Result.TextOut(ASize / 2, (ASize - Result.FontFullHeight) / 2,
    BadgeLetter[AKind], BGRAWhite, taCenter);
end;

{ A down arrow in dark gray. The push button it sits on stays light in both
  themes on macOS (the glass bezel takes the editor's white background), and
  a caption would follow the theme's text color and turn white on white. }
function DrawArrowDown(ASize: integer): TBGRABitmap;
var
  s: single;
  Color: TBGRAPixel;
begin
  Result := TBGRABitmap.Create(ASize, ASize, BGRAPixelTransparent);
  s := ASize / 16;
  Color := BGRA($40, $40, $40);
  Result.FillRoundRectAntialias(6.5 * s, 2 * s, 9.5 * s, 9 * s, s, s, Color);
  Result.FillPolyAntialias([PointF(2.5 * s, 7.5 * s), PointF(13.5 * s, 7.5 * s),
    PointF(8 * s, 13.5 * s)], Color);
end;

{ Adds one icon drawn at 16 and 32 pixels and frees the bitmaps. }
procedure AddIcon(AImages: TCustomImageList; ASmall, ALarge: TBGRABitmap);
begin
  try
    AImages.AddMultipleResolutions([TCustomBitmap(ASmall.Bitmap),
      TCustomBitmap(ALarge.Bitmap)]);
  finally
    ALarge.Free;
    ASmall.Free;
  end;
end;

procedure FillTreeIcons(AImages: TCustomImageList);
var
  Kind: TGittanChangeKind;
begin
  AImages.Width := 16;
  AImages.Height := 16;
  AImages.RegisterResolutions([16, 32]);
  AddIcon(AImages, DrawFolder(16), DrawFolder(32));
  for Kind := Low(TGittanChangeKind) to High(TGittanChangeKind) do
    AddIcon(AImages, DrawBadge(16, Kind), DrawBadge(32, Kind));
end;

procedure FillButtonIcons(AImages: TCustomImageList);
begin
  AImages.Width := 16;
  AImages.Height := 16;
  AImages.RegisterResolutions([16, 32]);
  AddIcon(AImages, DrawArrowDown(16), DrawArrowDown(32));
end;

end.
