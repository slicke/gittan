unit gittan.imagediff;

{** The change view of an image: the version compared against on the
  left and the new one on the right, side by side, each under a caption
  with its size in pixels and in bytes; or, when both can be read, the
  two laid over each other in one area (TGittanImageMode, chosen with
  the pills under the captions): Swipe draws the old one to the left of
  a divider the mouse drags and the new one to its right, Onion Skin
  draws the new one over the old with an opacity a slider sets, and
  Difference, for two images of the same size, draws where they differ,
  black where a pixel is the same.

  Both sides are drawn at the same scale, so a change of size shows as
  one: the largest that fits both, a whole number of times up to
  MaxZoom (nearest neighbour, so the pixels of an icon stay sharp), or
  a smooth reduction for an image larger than its half of the view. A
  checkerboard behind the image shows what is transparent, and a
  frame in the diff's red and green marks the old and the new side. A
  side without a version (an added or a deleted file) says so in a
  dotted box; one that cannot be decoded says that instead. When both
  sides have the same size, the caption of the new side tells how many
  of the pixels differ.

  It paints itself in colors the form sets, like the file header. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, BGRABitmap, BGRABitmapTypes;

type

  {** How the two versions are shown: side by side, or over each other
    with a divider to drag, with the new one's opacity to set, or as
    their difference. }
  TGittanImageMode = (imSideBySide, imSwipe, imOnion, imDifference);

  { TGittanImageDiff }

  TGittanImageDiff = class(TCustomControl)
  private
  type
    TDrag = (dgNone, dgDivider, dgKnob);
  private
    FImages: array[0..1] of TBGRABitmap;
    FScaled: array[0..1] of TBGRABitmap;
    FDiff, FScaledDiff: TBGRABitmap;
    FDiffTried: boolean;
    FHas, FBroken, FLfs: array[0..1] of boolean;
    FBytes: array[0..1] of int64;
    FScale: double;
    FDiffering: int64;
    FMode: TGittanImageMode;
    FSplit: double;
    FOpacity: byte;
    FDrag: TDrag;
    FHot: integer;
    FKnobHot: boolean;
    FOnModeChange: TNotifyEvent;
    FBack, FText, FDim, FLine, FDeleted, FAdded, FCheckLight, FCheckDark, FAccent: TColor;
    procedure ClearImages;
    procedure CountDiffering;
    function CanOverlay: boolean;
    function CanDifference: boolean;
    function Overlay: boolean;
    function ModeEnabled(AMode: TGittanImageMode): boolean;
    function ShownMode: TGittanImageMode;
    function LineHeight: integer;
    function AreaTop: integer;
    function ColumnLeft(ASide: integer): integer;
    function ImageArea(ASide: integer): TRect;
    function ImageRect(ASide: integer): TRect;
    function OverlayRect: TRect;
    function DividerX: integer;
    function ModeRect(AMode: TGittanImageMode): TRect;
    function ModeAt(X, Y: integer): integer;
    function SliderShown: boolean;
    function SliderRect: TRect;
    function SliderValue: double;
    procedure SetSliderAt(X: integer);
    procedure SetSplitAt(X: integer);
    procedure SetMode(AValue: TGittanImageMode);
    function FitScale: double;
    procedure UpdateScaled;
    procedure DrawChecker(ABuffer: TBGRABitmap; const R: TRect);
    procedure DrawSide(ABuffer: TBGRABitmap; ASide: integer);
    procedure DrawOverlay(ABuffer: TBGRABitmap);
    procedure DrawModes(ABuffer: TBGRABitmap);
    procedure DrawCaption(ASide: integer);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
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
      side's frame, the two squares of the checkerboard, and the accent
      of the chosen mode, the divider and the slider. }
    procedure SetColors(ABack, AText, ADim, ALine, ADeleted, AAdded, ACheckLight,
      ACheckDark, AAccent: TColor);
    {** Whether the modes apply: both versions decoded. Without that the
      sides are shown side by side whatever Mode says. }
    property Overlays: boolean read CanOverlay;
    {** How the versions are shown. Difference falls back to side by
      side while the sizes differ. }
    property Mode: TGittanImageMode read FMode write SetMode;
    {** Raised when Mode changes, from the pills or the property. }
    property OnModeChange: TNotifyEvent read FOnModeChange write FOnModeChange;
  end;

{** Whether APath names an image the view can show, by its extension:
  every format BGRABitmap reads, AVIF only when libavif can be loaded.
  SVG is text and keeps the text diff. }
function IsImagePath(const APath: string): boolean;

{** AData, the bytes of an image file, decoded; nil when it cannot be.
  The format is told from the bytes. A WebP goes through LazInk's
  decoder, which needs no library, the rest (and a WebP it cannot
  decode) through BGRABitmap. }
function DecodeImage(const AData: RawByteString): TBGRABitmap;

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

{** Where AOld and ANew differ, pixel by pixel: each drawn on black,
  then the difference of the two, so a pixel the same in both is black
  and one that differs shows by how much. nil when a side is nil or the
  sizes differ. }
function DifferenceImage(AOld, ANew: TBGRABitmap): TBGRABitmap;

{** The mode's caption for a pill or a menu item. }
function ImageModeCaption(AMode: TGittanImageMode): string;

{** The mode's name in the settings (side, swipe, onion, difference). }
function ImageModeName(AMode: TGittanImageMode): string;

{** The mode a settings name stands for; side by side for one unknown. }
function ImageModeOf(const AName: string): TGittanImageMode;

resourcestring
  rsBefore = 'Before';
  rsAfter = 'After';
  rsNotInVersion = 'Not in this version';
  rsImageSize = '%d × %d';
  rsModeSideBySide = 'Side by Side';
  rsModeSwipe = 'Swipe';
  rsModeOnion = 'Onion Skin';
  rsModeDifference = 'Difference';

implementation

uses
  Math, LibAvif, BGRAOpenRaster, BGRAPaintNet, BGRAPhoxo, InkWebP, gittan.git, gittan.theme;

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
  { The pills of the modes and the slider, at 96 DPI. }
  PillPad = 10;
  PillGap = 6;
  PillRise = 3;
  SliderWidth = 140;
  SliderGap = 20;
  KnobRadius = 6;
  GrabWidth = 6;
  ModeNames: array[TGittanImageMode] of string = ('side', 'swipe', 'onion', 'difference');
  ImageExtensions: array[0..23] of string = ('.png', '.jpg', '.jpeg', '.gif', '.bmp',
    '.ico', '.cur', '.tga', '.tif', '.tiff', '.pcx', '.webp', '.psd', '.pdd', '.xpm',
    '.pnm', '.pbm', '.pgm', '.ppm', '.xwd', '.ora', '.pdn', '.lzp', '.oxo');
var
  AvifChecked, AvifLoaded: boolean;

{ Whether libavif, which BGRABitmap reads AVIF with, can be loaded;
  tried once. }
function AvifReadable: boolean;
begin
  if not AvifChecked then
  begin
    AvifChecked := True;
    try
      AvifLoaded := LibAvifLoad;
    except
      AvifLoaded := False;
    end;
  end;
  Result := AvifLoaded;
end;

function IsImagePath(const APath: string): boolean;
var
  Ext, E: string;
begin
  Ext := LowerCase(ExtractFileExt(APath));
  for E in ImageExtensions do
    if Ext = E then
      Exit(True);
  Result := (Ext = '.avif') and AvifReadable;
end;

function DecodeImage(const AData: RawByteString): TBGRABitmap;
var
  Stream: TStringStream;
  WebP: TInkWebP;
begin
  Result := nil;
  Stream := TStringStream.Create(AData);
  try
    try
      if InkIsWebP(Copy(AData, 1, 12)) then
      begin
        WebP := TInkWebP.Create(Stream);
        try
          if WebP.Decoded then
          begin
            Result := TBGRABitmap.Create;
            Result.Assign(WebP.Bitmap);
          end;
        finally
          WebP.Free;
        end;
      end;
      { what LazInk cannot decode BGRABitmap may, a WebP with libwebp }
      if Result = nil then
      begin
        Stream.Position := 0;
        Result := TBGRABitmap.Create(Stream);
      end;
    except
      FreeAndNil(Result);
    end;
  finally
    Stream.Free;
  end;
  if (Result <> nil) and ((Result.Width = 0) or (Result.Height = 0)) then
    FreeAndNil(Result);
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


function DifferenceImage(AOld, ANew: TBGRABitmap): TBGRABitmap;
var
  Other: TBGRABitmap;
begin
  Result := nil;
  if (AOld = nil) or (ANew = nil) or (AOld.Width <> ANew.Width) or
    (AOld.Height <> ANew.Height) then
    Exit;
  Result := TBGRABitmap.Create(AOld.Width, AOld.Height, BGRABlack);
  Result.PutImage(0, 0, AOld, dmDrawWithTransparency);
  Other := TBGRABitmap.Create(ANew.Width, ANew.Height, BGRABlack);
  try
    Other.PutImage(0, 0, ANew, dmDrawWithTransparency);
    Result.BlendImage(0, 0, Other, boDifference);
  finally
    Other.Free;
  end;
end;

function ImageModeCaption(AMode: TGittanImageMode): string;
begin
  case AMode of
    imSwipe: Result := rsModeSwipe;
    imOnion: Result := rsModeOnion;
    imDifference: Result := rsModeDifference;
    else
      Result := rsModeSideBySide;
  end;
end;

function ImageModeName(AMode: TGittanImageMode): string;
begin
  Result := ModeNames[AMode];
end;

function ImageModeOf(const AName: string): TGittanImageMode;
var
  m: TGittanImageMode;
begin
  Result := imSideBySide;
  for m := Low(TGittanImageMode) to High(TGittanImageMode) do
    if SameText(AName, ModeNames[m]) then
      Exit(m);
end;

{ TGittanImageDiff }

constructor TGittanImageDiff.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FScale := 0;
  FSplit := 0.5;
  FOpacity := 128;
  FHot := -1;
  SetColors(clWindow, clWindowText, clGrayText, clBtnShadow, clRed, clGreen, clWhite,
    clSilver, clHighlight);
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
  FreeAndNil(FDiff);
  FreeAndNil(FScaledDiff);
  FDiffTried := False;
  FScale := 0;
  FDiffering := -1;
end;

procedure TGittanImageDiff.SetImages(const AOld, ANew: RawByteString;
  AHasOld, AHasNew: boolean);
var
  Data: array[0..1] of RawByteString;
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
    FImages[i] := DecodeImage(Data[i]);
    FBroken[i] := FImages[i] = nil;
  end;
  CountDiffering;
  FDrag := dgNone;
  Invalidate;
end;

procedure TGittanImageDiff.CountDiffering;
begin
  FDiffering := DifferingPixels(FImages[0], FImages[1]);
end;

procedure TGittanImageDiff.SetColors(ABack, AText, ADim, ALine, ADeleted, AAdded,
  ACheckLight, ACheckDark, AAccent: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FLine := ALine;
  FDeleted := ADeleted;
  FAdded := AAdded;
  FCheckLight := ACheckLight;
  FCheckDark := ACheckDark;
  FAccent := AAccent;
  Invalidate;
end;

{ The modes apply once both versions are decoded. }
function TGittanImageDiff.CanOverlay: boolean;
begin
  Result := (FImages[0] <> nil) and (FImages[1] <> nil);
end;

function TGittanImageDiff.CanDifference: boolean;
begin
  Result := CanOverlay and (FImages[0].Width = FImages[1].Width) and
    (FImages[0].Height = FImages[1].Height);
end;

{ Whether the sides share one area: a mode other than side by side that
  applies to these two versions. }
function TGittanImageDiff.Overlay: boolean;
begin
  case FMode of
    imSwipe, imOnion: Result := CanOverlay;
    imDifference: Result := CanDifference;
    else
      Result := False;
  end;
end;

function TGittanImageDiff.ModeEnabled(AMode: TGittanImageMode): boolean;
begin
  if AMode = imDifference then
    Result := CanDifference
  else
    Result := True;
end;

{ The mode the pills show as chosen: Mode while it applies, else side
  by side, which is what the sides fall back to. }
function TGittanImageDiff.ShownMode: TGittanImageMode;
begin
  if Overlay then
    Result := FMode
  else
    Result := imSideBySide;
end;

procedure TGittanImageDiff.SetMode(AValue: TGittanImageMode);
begin
  if AValue = FMode then
    Exit;
  FMode := AValue;
  { The scale depends on the area, which the mode sets. }
  FScale := 0;
  FDrag := dgNone;
  Invalidate;
  if Assigned(FOnModeChange) then
    FOnModeChange(Self);
end;

function TGittanImageDiff.LineHeight: integer;
begin
  Result := Canvas.TextHeight('Xg');
end;

{ Where the images begin: under the two caption lines, and under the
  row of mode pills when the modes apply. }
function TGittanImageDiff.AreaTop: integer;
begin
  Result := Pad + 2 * LineHeight + 2 * Gap;
  if CanOverlay then
    Result := Result + LineHeight + 2 * Px(PillRise) + 2 * Gap;
end;

{ The left edge of a side's column, where its caption starts. }
function TGittanImageDiff.ColumnLeft(ASide: integer): integer;
begin
  Result := Pad + ASide * (Max(0, (ClientWidth - 3 * Pad) div 2) + Pad);
end;

{ The space of side ASide (0 the old, 1 the new) under its caption: its
  half of the width, or the whole width when the sides share one area. }
function TGittanImageDiff.ImageArea(ASide: integer): TRect;
var
  AT: integer;
begin
  AT := AreaTop;
  if Overlay then
  begin
    Result.Left := Pad;
    Result.Right := Max(Pad, ClientWidth - Pad);
  end
  else
  begin
    Result.Left := ColumnLeft(ASide);
    Result.Right := Result.Left + Max(0, (ClientWidth - 3 * Pad) div 2);
  end;
  Result.Top := AT;
  Result.Bottom := Max(AT, ClientHeight - Pad);
end;

{ Where the scaled image of ASide is drawn: centred in its area. Empty
  when there is none. }
function TGittanImageDiff.ImageRect(ASide: integer): TRect;
var
  Area: TRect;
begin
  Result := Rect(0, 0, 0, 0);
  if FScaled[ASide] = nil then
    Exit;
  Area := ImageArea(ASide);
  Result.Left := Area.Left + (Area.Width - FScaled[ASide].Width) div 2;
  Result.Top := Area.Top + (Area.Height - FScaled[ASide].Height) div 2;
  Result.Right := Result.Left + FScaled[ASide].Width;
  Result.Bottom := Result.Top + FScaled[ASide].Height;
end;

{ The rectangle both images cover when they share one area. }
function TGittanImageDiff.OverlayRect: TRect;
begin
  UnionRect(Result, ImageRect(0), ImageRect(1));
end;

function TGittanImageDiff.DividerX: integer;
var
  R: TRect;
begin
  R := OverlayRect;
  Result := R.Left + Round(FSplit * R.Width);
end;

{ The pill of a mode in the row under the captions, from the left. }
function TGittanImageDiff.ModeRect(AMode: TGittanImageMode): TRect;
var
  m: TGittanImageMode;
  X, RowTop: integer;
begin
  Canvas.Font := Font;
  Canvas.Font.Style := [];
  RowTop := Pad + 2 * LineHeight + 2 * Gap;
  X := Pad;
  for m := Low(TGittanImageMode) to High(TGittanImageMode) do
  begin
    Result := Rect(X, RowTop, X + Canvas.TextWidth(ImageModeCaption(m)) + 2 * Px(PillPad),
      RowTop + LineHeight + 2 * Px(PillRise));
    if m = AMode then
      Exit;
    X := Result.Right + Px(PillGap);
  end;
end;

{ The index of the mode whose pill is at X, Y, -1 for none. }
function TGittanImageDiff.ModeAt(X, Y: integer): integer;
var
  m: TGittanImageMode;
begin
  Result := -1;
  if not CanOverlay then
    Exit;
  for m := Low(TGittanImageMode) to High(TGittanImageMode) do
    if PtInRect(ModeRect(m), Point(X, Y)) then
      Exit(Ord(m));
end;

{ The slider sets the divider in Swipe and the opacity in Onion Skin. }
function TGittanImageDiff.SliderShown: boolean;
begin
  Result := Overlay and (FMode in [imSwipe, imOnion]);
end;

{ The slider's track, right of the pills on their row. }
function TGittanImageDiff.SliderRect: TRect;
var
  Last: TRect;
begin
  Last := ModeRect(High(TGittanImageMode));
  Result.Left := Last.Right + Px(SliderGap);
  Result.Right := Result.Left + Px(SliderWidth);
  Result.Top := Last.Top;
  Result.Bottom := Last.Bottom;
end;

function TGittanImageDiff.SliderValue: double;
begin
  if FMode = imOnion then
    Result := FOpacity / 255
  else
    Result := FSplit;
end;

procedure TGittanImageDiff.SetSliderAt(X: integer);
var
  R: TRect;
  V: double;
begin
  R := SliderRect;
  V := EnsureRange((X - R.Left) / Max(1, R.Width), 0, 1);
  if FMode = imOnion then
    FOpacity := Round(V * 255)
  else
    FSplit := V;
  Invalidate;
end;

procedure TGittanImageDiff.SetSplitAt(X: integer);
var
  R: TRect;
begin
  R := OverlayRect;
  FSplit := EnsureRange((X - R.Left) / Max(1, R.Width), 0, 1);
  Invalidate;
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

{ The scaled images are kept until the scale changes. The difference
  is made the first time its mode is shown, and scaled like them. }
procedure TGittanImageDiff.UpdateScaled;

  function ScaledOf(ASource: TBGRABitmap; AScale: double): TBGRABitmap;
  var
    W, H: integer;
  begin
    W := Max(1, Round(ASource.Width * AScale));
    H := Max(1, Round(ASource.Height * AScale));
    if AScale >= 1 then
    begin
      ASource.ResampleFilter := rfBox;
      Result := ASource.Resample(W, H, rmSimpleStretch);
    end
    else
    begin
      ASource.ResampleFilter := rfBestQuality;
      Result := ASource.Resample(W, H, rmFineResample);
    end;
  end;

var
  Scale: double;
  i: integer;
begin
  if (FMode = imDifference) and (FDiff = nil) and not FDiffTried then
  begin
    FDiffTried := True;
    FDiff := DifferenceImage(FImages[0], FImages[1]);
  end;
  Scale := FitScale;
  if Scale <> FScale then
  begin
    FScale := Scale;
    for i := 0 to 1 do
    begin
      FreeAndNil(FScaled[i]);
      if FImages[i] <> nil then
        FScaled[i] := ScaledOf(FImages[i], Scale);
    end;
    FreeAndNil(FScaledDiff);
  end;
  if (FScaledDiff = nil) and (FDiff <> nil) and (FMode = imDifference) then
    FScaledDiff := ScaledOf(FDiff, FScale);
end;

{ The checkerboard that shows transparency, over R. }
procedure TGittanImageDiff.DrawChecker(ABuffer: TBGRABitmap; const R: TRect);
var
  X, Y: integer;
begin
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
  R := ImageRect(ASide);
  { The checkerboard behind the image, then the image, then its frame. }
  DrawChecker(ABuffer, R);
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

{ The two versions in one area: the old left of the divider and the new
  right of it (Swipe), the new over the old at its opacity (Onion Skin),
  or their difference. A frame in the line color marks the area. }
procedure TGittanImageDiff.DrawOverlay(ABuffer: TBGRABitmap);
var
  U, R0, R1: TRect;
  X, MidY: integer;
  Accent: TBGRAPixel;
begin
  U := OverlayRect;
  if (U.Width <= 0) or (U.Height <= 0) then
    Exit;
  R0 := ImageRect(0);
  R1 := ImageRect(1);
  DrawChecker(ABuffer, U);
  Accent := ColorToBGRA(FAccent);
  case FMode of
    imSwipe:
    begin
      X := DividerX;
      ABuffer.ClipRect := Rect(U.Left, U.Top, X, U.Bottom);
      ABuffer.PutImage(R0.Left, R0.Top, FScaled[0], dmDrawWithTransparency);
      ABuffer.ClipRect := Rect(X, U.Top, U.Right, U.Bottom);
      ABuffer.PutImage(R1.Left, R1.Top, FScaled[1], dmDrawWithTransparency);
      ABuffer.NoClip;
    end;
    imOnion:
    begin
      ABuffer.PutImage(R0.Left, R0.Top, FScaled[0], dmDrawWithTransparency);
      ABuffer.PutImage(R1.Left, R1.Top, FScaled[1], dmDrawWithTransparency, FOpacity);
    end;
    imDifference:
      if FScaledDiff <> nil then
        ABuffer.PutImage(U.Left, U.Top, FScaledDiff, dmSet);
  end;
  ABuffer.Rectangle(U.Left - 1, U.Top - 1, U.Right + 1, U.Bottom + 1, ColorToBGRA(FLine),
    dmSet);
  if FMode = imSwipe then
  begin
    { The divider, with a knob in the middle to take hold of. }
    X := DividerX;
    MidY := (U.Top + U.Bottom) div 2;
    ABuffer.FillRect(X - 1, U.Top - Gap, X + 1, U.Bottom + Gap, Accent, dmSet);
    ABuffer.FillEllipseAntialias(X, MidY, Px(KnobRadius) + 1.5, Px(KnobRadius) + 1.5,
      ColorToBGRA(FBack));
    ABuffer.FillEllipseAntialias(X, MidY, Px(KnobRadius), Px(KnobRadius), Accent);
  end;
end;

{ The pills of the modes, the one shown filled in the accent, one that
  does not apply dimmed, and the slider after them. The captions are
  drawn afterwards on the canvas. }
procedure TGittanImageDiff.DrawModes(ABuffer: TBGRABitmap);
var
  m: TGittanImageMode;
  R: TRect;
  Radius, KnobX, MidY: integer;
  Fill: TBGRAPixel;
begin
  if not CanOverlay then
    Exit;
  for m := Low(TGittanImageMode) to High(TGittanImageMode) do
  begin
    R := ModeRect(m);
    Radius := R.Height div 2;
    if m = ShownMode then
      ABuffer.FillRoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, Radius, Radius,
        ColorToBGRA(FAccent))
    else if ModeEnabled(m) then
      ABuffer.RoundRectAntialias(R.Left + 0.5, R.Top + 0.5, R.Right - 0.5, R.Bottom - 0.5,
        Radius, Radius, ColorToBGRA(FLine), 1);
  end;
  if not SliderShown then
    Exit;
  R := SliderRect;
  MidY := (R.Top + R.Bottom) div 2;
  KnobX := R.Left + Round(SliderValue * R.Width);
  Fill := ColorToBGRA(FAccent);
  ABuffer.FillRoundRectAntialias(R.Left, MidY - Px(2), R.Right, MidY + Px(2), Px(2), Px(2),
    ColorToBGRA(FLine));
  ABuffer.FillRoundRectAntialias(R.Left, MidY - Px(2), KnobX, MidY + Px(2), Px(2), Px(2),
    Fill);
  ABuffer.FillEllipseAntialias(KnobX, MidY, Px(KnobRadius) + 1.5, Px(KnobRadius) + 1.5,
    ColorToBGRA(FBack));
  ABuffer.FillEllipseAntialias(KnobX, MidY, Px(KnobRadius), Px(KnobRadius), Fill);
end;

{ The caption of a side: Before or After, then the size in pixels and
  in bytes, the zoom when it is not 100 %, and on the new side how many
  pixels differ. A side without a picture says why in the middle of its
  box. }
procedure TGittanImageDiff.DrawCaption(ASide: integer);
var
  Area: TRect;
  Title, Detail, Note: string;
  LineH, ColLeft: integer;
begin
  Area := ImageArea(ASide);
  ColLeft := ColumnLeft(ASide);
  LineH := LineHeight;
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
  Canvas.TextOut(ColLeft, Pad, Title);
  Canvas.Font.Style := [];
  Canvas.Font.Color := FDim;
  Canvas.TextOut(ColLeft, Pad + LineH + Gap div 2, Detail);
  if Note <> '' then
    Canvas.TextOut((Area.Left + Area.Right - Canvas.TextWidth(Note)) div 2,
      (Area.Top + Area.Bottom - LineH) div 2, Note);
end;

procedure TGittanImageDiff.Paint;
var
  Buffer: TBGRABitmap;
  m: TGittanImageMode;
  R: TRect;
  AT: integer;
begin
  Canvas.Font := Font;
  UpdateScaled;
  Buffer := TBGRABitmap.Create(ClientWidth, ClientHeight, ColorToBGRA(FBack));
  try
    if Overlay then
      DrawOverlay(Buffer)
    else
    begin
      DrawSide(Buffer, 0);
      DrawSide(Buffer, 1);
    end;
    DrawModes(Buffer);
    { The line under the captions. }
    AT := AreaTop;
    Buffer.HorizLine(Pad, AT - Gap, ClientWidth - Pad - 1, ColorToBGRA(FLine), dmSet);
    Buffer.Draw(Canvas, 0, 0, True);
  finally
    Buffer.Free;
  end;
  DrawCaption(0);
  DrawCaption(1);
  if CanOverlay then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Style := [];
    for m := Low(TGittanImageMode) to High(TGittanImageMode) do
    begin
      R := ModeRect(m);
      if m = ShownMode then
        Canvas.Font.Color := FBack
      else if not ModeEnabled(m) then
        Canvas.Font.Color := MixColor(FDim, FBack, 0.5)
      else if Ord(m) = FHot then
        Canvas.Font.Color := FText
      else
        Canvas.Font.Color := FDim;
      Canvas.TextOut(R.Left + Px(PillPad), R.Top + Px(PillRise),
        ImageModeCaption(m));
    end;
  end;
end;

procedure TGittanImageDiff.Resize;
begin
  inherited Resize;
  Invalidate;
end;

procedure TGittanImageDiff.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  i: integer;
  R: TRect;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  i := ModeAt(X, Y);
  if i >= 0 then
  begin
    if ModeEnabled(TGittanImageMode(i)) then
      Mode := TGittanImageMode(i);
    Exit;
  end;
  if SliderShown then
  begin
    R := SliderRect;
    InflateRect(R, Px(KnobRadius), 0);
    if PtInRect(R, Point(X, Y)) then
    begin
      FDrag := dgKnob;
      SetSliderAt(X);
      Exit;
    end;
  end;
  if Overlay and (FMode = imSwipe) then
  begin
    R := OverlayRect;
    InflateRect(R, Px(GrabWidth), Gap);
    if PtInRect(R, Point(X, Y)) then
    begin
      FDrag := dgDivider;
      SetSplitAt(X);
    end;
  end;
end;

procedure TGittanImageDiff.MouseMove(Shift: TShiftState; X, Y: integer);
var
  Hot: integer;
  KnobHot: boolean;
  R: TRect;
begin
  inherited MouseMove(Shift, X, Y);
  case FDrag of
    dgKnob: SetSliderAt(X);
    dgDivider: SetSplitAt(X);
    else
    begin
      Hot := ModeAt(X, Y);
      if (Hot >= 0) and not ModeEnabled(TGittanImageMode(Hot)) then
        Hot := -1;
      KnobHot := False;
      if SliderShown then
      begin
        R := SliderRect;
        InflateRect(R, Px(KnobRadius), 0);
        KnobHot := PtInRect(R, Point(X, Y));
      end;
      if (Hot <> FHot) or (KnobHot <> FKnobHot) then
      begin
        FHot := Hot;
        FKnobHot := KnobHot;
        Invalidate;
      end;
      if (Hot >= 0) or KnobHot then
        Cursor := crHandPoint
      else if Overlay and (FMode = imSwipe) and (Abs(X - DividerX) <= Px(GrabWidth)) and
        (Y >= OverlayRect.Top - Gap) and (Y <= OverlayRect.Bottom + Gap) then
        Cursor := crSizeWE
      else
        Cursor := crDefault;
    end;
  end;
end;

procedure TGittanImageDiff.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDrag := dgNone;
end;

procedure TGittanImageDiff.MouseLeave;
begin
  inherited MouseLeave;
  if (FHot >= 0) or FKnobHot then
  begin
    FHot := -1;
    FKnobHot := False;
    Invalidate;
  end;
  Cursor := crDefault;
end;

initialization
  { these register their readers only when asked }
  RegisterOpenRasterFormat;
  RegisterPaintNetFormat;
  RegisterPhoxoFormat;

end.
