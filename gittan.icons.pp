unit gittan.icons;

{** Icons for Gittan's file tree.

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

{** Image index of the folder icon with a dot in the color of AKind: the
  most severe change among the files inside the folder. }
function FolderIcon(AKind: TGittanChangeKind): integer;

{** The kind of a folder icon from FolderIcon, false for any other index. }
function FolderIconKind(AIndex: integer; out AKind: TGittanChangeKind): boolean;

{** The more severe of two kinds: a conflict before a deletion, then a
  modification, a rename, an addition, and last an untracked file. }
function WorseKind(A, B: TGittanChangeKind): TGittanChangeKind;

{** Fills the empty list AImages with the folder icon at iconFolder, the
  change badges at ChangeIcon and the dotted folders at FolderIcon. }
procedure FillTreeIcons(AImages: TCustomImageList);

implementation

uses
  Graphics, BGRABitmap, BGRABitmapTypes;

const
  BadgeLetter: array[TGittanChangeKind] of string = ('M', 'A', 'D', 'R', 'U', '!');
  Severity: array[TGittanChangeKind] of integer = (3, 1, 4, 2, 0, 5);
  KindCount = Ord(High(TGittanChangeKind)) + 1;

function ChangeIcon(AKind: TGittanChangeKind): integer;
begin
  Result := iconFolder + 1 + Ord(AKind);
end;

function FolderIcon(AKind: TGittanChangeKind): integer;
begin
  Result := iconFolder + 1 + KindCount + Ord(AKind);
end;

function FolderIconKind(AIndex: integer; out AKind: TGittanChangeKind): boolean;
begin
  Result := (AIndex >= FolderIcon(Low(TGittanChangeKind))) and
    (AIndex <= FolderIcon(High(TGittanChangeKind)));
  if Result then
    AKind := TGittanChangeKind(AIndex - FolderIcon(Low(TGittanChangeKind)));
end;

function WorseKind(A, B: TGittanChangeKind): TGittanChangeKind;
begin
  if Severity[B] > Severity[A] then
    Result := B
  else
    Result := A;
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

{ The folder with a dot in the kind's color over its lower right corner.
  A transparent ring around the dot keeps it apart from the folder. }
function DrawDottedFolder(ASize: integer; AKind: TGittanChangeKind): TBGRABitmap;
var
  s: single;
begin
  Result := DrawFolder(ASize);
  s := ASize / 16;
  Result.EraseEllipseAntialias(12 * s, 12 * s, 4.5 * s, 4.5 * s, 255);
  Result.FillEllipseAntialias(12 * s, 12 * s, 3.5 * s, 3.5 * s, BadgeColor(AKind));
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
  for Kind := Low(TGittanChangeKind) to High(TGittanChangeKind) do
    AddIcon(AImages, DrawDottedFolder(16, Kind), DrawDottedFolder(32, Kind));
end;

end.
