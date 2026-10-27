unit gittan.imagediff;

{** The change view of an image: the version compared against on the
  left and the new one on the right, side by side, each under a caption
  with its size in pixels and in bytes.

  Both sides are drawn at the same scale, so a change of size shows as
  one: the largest that fits both, a whole number of times up to
  MaxZoom (nearest neighbour, so the pixels of an icon stay sharp), or
  a smooth reduction for an image larger than its half of the view. A
  checkerboard behind the image shows what is transparent, and a
  frame in the diff's red and green marks the old and the new side. A
  side without a version (an added or a deleted file) says so in a
  dotted box; one BGRABitmap cannot decode says that instead. When both
  sides have the same size, the caption of the new side tells how many
  of the pixels differ.

  It paints itself in colors the form sets, like the file header. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, BGRABitmap, BGRABitmapTypes;

type

  { TGittanImageDiff }

  TGittanImageDiff = class(TCustomControl)
  private
    FImages: array[0..1] of TBGRABitmap;
    FScaled: array[0..1] of TBGRABitmap;
    FHas, FBroken, FLfs: array[0..1] of boolean;
    FBytes: array[0..1] of int64;
    FScale: double;
    FDiffering: int64;
    FBack, FText, FDim, FLine, FDeleted, FAdded, FCheckLight, FCheckDark: TColor;
    procedure ClearImages;
    procedure CountDiffering;
    function ImageArea(ASide: integer): TRect;
    function FitScale: double;
    procedure UpdateScaled;
    procedure DrawSide(ABuffer: TBGRABitmap; ASide: integer);
    procedure DrawCaption(ASide: integer);
  protected
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** The two versions as the bytes of their files: AOld the one
      compared against, ANew the new one. AHasOld or AHasNew false for
      a side without a version. A Git LFS pointer is a version not
      downloaded, which says so with the size it gives. }
    procedure SetImages(const AOld, ANew: RawByteString; AHasOld, AHasNew: boolean);
    {** The palette: the background, the captions, the dim details and
      the dotted box, the line under the captions, the old and the new
      side's frame, and the two squares of the checkerboard. }
    procedure SetColors(ABack, AText, ADim, ALine, ADeleted, AAdded, ACheckLight,
      ACheckDark: TColor);
  end;

{** Whether APath names an image the view can show, by its extension.
  SVG is text and keeps the text diff. }
function IsImagePath(const APath: string): boolean;

{** The name of the image format of APath for the file header: the
  extension in upper case and "image" ("PNG image"). }
function ImageFormatName(const APath: string): string;

{** The size of a file for a caption: bytes, else kilo- or megabytes
  with one decimal. }
function ByteSize(ABytes: int64): string;

{** How many pixels differ between AOld and ANew, -1 when a side is nil
  or the sizes differ. Two fully transparent pixels are the same
  whatever their color. }
function DifferingPixels(AOld, ANew: TBGRABitmap): int64;

{** The caption's note of ADiffering of APixels pixels: "same pixels",
  "1.5 % of the pixels differ", or '' when they were not counted (-1). }
function DifferingNote(ADiffering, APixels: int64): string;

resourcestring
  rsBefore = 'Before';
  rsAfter = 'After';
  rsNotInVersion = 'Not in this version';
  rsImageSize = '%d × %d';

implementation

uses
  Math, gittan.git;

resourcestring
  rsCannotRead = 'Cannot read this image';
  rsNotDownloaded = 'Not downloaded (Git LFS)';
  rsSamePixels = 'same pixels';
  rsPixelsDiffer = '%s of the pixels differ';
  rsImage = '%s image';

const
  Pad = 16;
  Gap = 6;
  MaxZoom = 8;
  CheckSize = 8;
  ImageExtensions: array[0..9] of string = ('.png', '.jpg', '.jpeg', '.gif', '.bmp',
    '.ico', '.tga', '.tif', '.tiff', '.pcx');

function IsImagePath(const APath: string): boolean;
var
  Ext, E: string;
begin
  Ext := LowerCase(ExtractFileExt(APath));
  for E in ImageExtensions do
    if Ext = E then
      Exit(True);
  Result := False;
end;

function ImageFormatName(const APath: string): string;
begin
  Result := Format(rsImage, [UpperCase(Copy(ExtractFileExt(APath), 2, MaxInt))]);
end;

function ByteSize(ABytes: int64): string;
begin
  if ABytes < 1024 then
    Result := IntToStr(ABytes) + ' B'
  else if ABytes < 1024 * 1024 then
    Result := FormatFloat('0.0', ABytes / 1024) + ' KB'
  else
    Result := FormatFloat('0.0', ABytes / (1024 * 1024)) + ' MB';
end;

function DifferingPixels(AOld, ANew: TBGRABitmap): int64;
var
  A, B: PBGRAPixel;
  i: integer;
begin
  Result := -1;
  if (AOld = nil) or (ANew = nil) or (AOld.Width <> ANew.Width) or
    (AOld.Height <> ANew.Height) then
    Exit;
  Result := 0;
  A := AOld.Data;
  B := ANew.Data;
  for i := 0 to AOld.NbPixels - 1 do
  begin
    if ((A^.alpha <> 0) or (B^.alpha <> 0)) and (PDWord(A)^ <> PDWord(B)^) then
      Inc(Result);
    Inc(A);
    Inc(B);
  end;
end;

function DifferingNote(ADiffering, APixels: int64): string;
begin
  if ADiffering = 0 then
    Result := rsSamePixels
  else if (ADiffering > 0) and (APixels > 0) then
    Result := Format(rsPixelsDiffer,
      [FormatFloat('0.#', Max(0.1, 100 * ADiffering / APixels)) + ' %'])
  else
    Result := '';
end;

{ TGittanImageDiff }

constructor TGittanImageDiff.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FScale := 0;
  SetColors(clWindow, clWindowText, clGrayText, clBtnShadow, clRed, clGreen, clWhite,
    clSilver);
end;

destructor TGittanImageDiff.Destroy;
begin
  ClearImages;
  inherited Destroy;
end;

procedure TGittanImageDiff.ClearImages;
var
  i: integer;
begin
  for i := 0 to 1 do
  begin
    FreeAndNil(FImages[i]);
    FreeAndNil(FScaled[i]);
    FHas[i] := False;
    FBroken[i] := False;
    FLfs[i] := False;
    FBytes[i] := 0;
  end;
  FScale := 0;
  FDiffering := -1;
end;

procedure TGittanImageDiff.SetImages(const AOld, ANew: RawByteString;
  AHasOld, AHasNew: boolean);
var
  Data: array[0..1] of RawByteString;
  Stream: TStringStream;
  Oid: string;
  Size: int64;
  i: integer;
begin
  ClearImages;
  Data[0] := AOld;
  Data[1] := ANew;
  FHas[0] := AHasOld;
  FHas[1] := AHasNew;
  for i := 0 to 1 do
  begin
    if not FHas[i] then
      Continue;
    FBytes[i] := Length(Data[i]);
    if ParseLfsPointer(Data[i], Oid, Size) then
    begin
      FLfs[i] := True;
      FBroken[i] := True;
      FBytes[i] := Size;
      Continue;
    end;
    Stream := TStringStream.Create(Data[i]);
    try
      try
        FImages[i] := TBGRABitmap.Create(Stream);
      except
        FreeAndNil(FImages[i]);
      end;
    finally
      Stream.Free;
    end;
    FBroken[i] := (FImages[i] = nil) or (FImages[i].Width = 0) or (FImages[i].Height = 0);
    if FBroken[i] then
      FreeAndNil(FImages[i]);
  end;
  CountDiffering;
  Invalidate;
end;

procedure TGittanImageDiff.CountDiffering;
begin
  FDiffering := DifferingPixels(FImages[0], FImages[1]);
end;

procedure TGittanImageDiff.SetColors(ABack, AText, ADim, ALine, ADeleted, AAdded,
  ACheckLight, ACheckDark: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FLine := ALine;
  FDeleted := ADeleted;
  FAdded := AAdded;
  FCheckLight := ACheckLight;
  FCheckDark := ACheckDark;
  Invalidate;
end;

{ The space of side ASide (0 the old, 1 the new) under its caption. }
function TGittanImageDiff.ImageArea(ASide: integer): TRect;
var
  W, AreaTop: integer;
begin
  W := Max(0, (ClientWidth - 3 * Pad) div 2);
  AreaTop := Pad + 2 * Canvas.TextHeight('Xg') + 2 * Gap;
  Result.Left := Pad + ASide * (W + Pad);
  Result.Right := Result.Left + W;
  Result.Top := AreaTop;
  Result.Bottom := Max(AreaTop, ClientHeight - Pad);
end;

{ The scale both sides are drawn at: the largest at which both fit
  their space, a whole number up to MaxZoom when they fit at their
  size. }
function TGittanImageDiff.FitScale: double;
var
  Area: TRect;
  i: integer;
begin
  Result := MaxZoom;
  Area := ImageArea(0);
  for i := 0 to 1 do
    if FImages[i] <> nil then
      Result := Min(Result, Min(Area.Width / FImages[i].Width,
        Area.Height / FImages[i].Height));
  if Result >= 1 then
    Result := Floor(Result);
end;

{ The scaled images are kept until the scale changes. }
procedure TGittanImageDiff.UpdateScaled;
var
  Scale: double;
  i, W, H: integer;
begin
  Scale := FitScale;
  if Scale = FScale then
    Exit;
  FScale := Scale;
  for i := 0 to 1 do
  begin
    FreeAndNil(FScaled[i]);
    if FImages[i] = nil then
      Continue;
    W := Max(1, Round(FImages[i].Width * Scale));
    H := Max(1, Round(FImages[i].Height * Scale));
    if Scale >= 1 then
      FImages[i].ResampleFilter := rfBox
    else
      FImages[i].ResampleFilter := rfBestQuality;
    if Scale >= 1 then
      FScaled[i] := FImages[i].Resample(W, H, rmSimpleStretch)
    else
      FScaled[i] := FImages[i].Resample(W, H, rmFineResample);
  end;
end;

procedure TGittanImageDiff.DrawSide(ABuffer: TBGRABitmap; ASide: integer);
var
  Area, R: TRect;
  X, Y: integer;
  Frame: TColor;
begin
  Area := ImageArea(ASide);
  if (Area.Width <= 0) or (Area.Height <= 0) then
    Exit;
  if FScaled[ASide] = nil then
  begin
    { No version, or none that can be read: a dotted box over the space. }
    R := Area;
    Y := R.Top;
    while Y < R.Bottom do
    begin
      ABuffer.SetPixel(R.Left, Y, ColorToBGRA(FDim));
      ABuffer.SetPixel(R.Right - 1, Y, ColorToBGRA(FDim));
      Inc(Y, 3);
    end;
    X := R.Left;
    while X < R.Right do
    begin
      ABuffer.SetPixel(X, R.Top, ColorToBGRA(FDim));
      ABuffer.SetPixel(X, R.Bottom - 1, ColorToBGRA(FDim));
      Inc(X, 3);
    end;
    Exit;
  end;
  R.Left := Area.Left + (Area.Width - FScaled[ASide].Width) div 2;
  R.Top := Area.Top + (Area.Height - FScaled[ASide].Height) div 2;
  R.Right := R.Left + FScaled[ASide].Width;
  R.Bottom := R.Top + FScaled[ASide].Height;
  { The checkerboard behind the image, then the image, then its frame. }
  Y := R.Top;
  while Y < R.Bottom do
  begin
    X := R.Left;
    while X < R.Right do
    begin
      if Odd((X - R.Left) div CheckSize + (Y - R.Top) div CheckSize) then
        ABuffer.FillRect(X, Y, Min(X + CheckSize, R.Right), Min(Y + CheckSize, R.Bottom),
          ColorToBGRA(FCheckDark), dmSet)
      else
        ABuffer.FillRect(X, Y, Min(X + CheckSize, R.Right), Min(Y + CheckSize, R.Bottom),
          ColorToBGRA(FCheckLight), dmSet);
      Inc(X, CheckSize);
    end;
    Inc(Y, CheckSize);
  end;
  ABuffer.PutImage(R.Left, R.Top, FScaled[ASide], dmDrawWithTransparency);
  if ASide = 0 then
    Frame := FDeleted
  else
    Frame := FAdded;
  ABuffer.Rectangle(R.Left - 2, R.Top - 2, R.Right + 2, R.Bottom + 2, ColorToBGRA(Frame),
    dmSet);
  ABuffer.Rectangle(R.Left - 1, R.Top - 1, R.Right + 1, R.Bottom + 1, ColorToBGRA(Frame),
    dmSet);
end;

{ The caption of a side: Before or After, then the size in pixels and
  in bytes, the zoom when it is not 100 %, and on the new side how many
  pixels differ. A side without a picture says why in the middle of its
  box. }
procedure TGittanImageDiff.DrawCaption(ASide: integer);
var
  Area: TRect;
  Title, Detail, Note: string;
  LineH: integer;
begin
  Area := ImageArea(ASide);
  LineH := Canvas.TextHeight('Xg');
  if ASide = 0 then
    Title := rsBefore
  else
    Title := rsAfter;
  Detail := '';
  Note := '';
  if not FHas[ASide] then
    Note := rsNotInVersion
  else if FLfs[ASide] then
  begin
    Note := rsNotDownloaded;
    Detail := ByteSize(FBytes[ASide]);
  end
  else if FBroken[ASide] then
  begin
    Note := rsCannotRead;
    Detail := ByteSize(FBytes[ASide]);
  end
  else
  begin
    Detail := Format(rsImageSize, [FImages[ASide].Width, FImages[ASide].Height]) +
      '  ·  ' + ByteSize(FBytes[ASide]);
    if (FScale > 0) and (FScale <> 1) then
      Detail := Detail + '  ·  ' + IntToStr(Round(FScale * 100)) + ' %';
    if (ASide = 1) and (FDiffering >= 0) then
      Detail := Detail + '  ·  ' + DifferingNote(FDiffering, FImages[1].NbPixels);
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FText;
  Canvas.TextOut(Area.Left, Pad, Title);
  Canvas.Font.Style := [];
  Canvas.Font.Color := FDim;
  Canvas.TextOut(Area.Left, Pad + LineH + Gap div 2, Detail);
  if Note <> '' then
    Canvas.TextOut((Area.Left + Area.Right - Canvas.TextWidth(Note)) div 2,
      (Area.Top + Area.Bottom - LineH) div 2, Note);
end;

procedure TGittanImageDiff.Paint;
var
  Buffer: TBGRABitmap;
  Area: TRect;
begin
  Canvas.Font := Font;
  UpdateScaled;
  Buffer := TBGRABitmap.Create(ClientWidth, ClientHeight, ColorToBGRA(FBack));
  try
    DrawSide(Buffer, 0);
    DrawSide(Buffer, 1);
    { The line under the captions. }
    Area := ImageArea(0);
    Buffer.HorizLine(Pad, Area.Top - Gap, ClientWidth - Pad - 1, ColorToBGRA(FLine), dmSet);
    Buffer.Draw(Canvas, 0, 0, True);
  finally
    Buffer.Free;
  end;
  DrawCaption(0);
  DrawCaption(1);
end;

procedure TGittanImageDiff.Resize;
begin
  inherited Resize;
  Invalidate;
end;

end.
