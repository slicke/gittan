unit gittan.avatar;

{** The forge user's picture as the forge sent it, decoded once and
  drawn as a disc wherever the user is shown: the head of the forge page
  (gittan.forgepage) and the banner in the window's chrome (the own
  title bar; the macOS toolbar decodes the same bytes with NSImage). The
  bytes are PNG or JPEG, read with BGRABitmap; the disc is resampled to
  the pixels asked for and cut round with a mask, kept until the size
  changes; bytes PictureFits refuses (no PNG or JPEG, or too large a
  side) are no picture. See spec/github.md. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, BGRABitmap;

type

  { TGittanAvatar }

  TGittanAvatar = class
  private
    FData: string;
    FImage, FDisc: TBGRABitmap;
  public
    destructor Destroy; override;
    {** The picture's bytes, '' for none; the same bytes keep what was
      decoded. True when they changed. }
    function SetData(const AData: string): boolean;
    {** Whether there is a picture that could be read. }
    function HasImage: boolean;
    {** Draws the picture cut round in the square ASize wide at ALeft,
      ATop on ACanvas, in ASize * AScale pixels (the canvas's scale
      factor). Nothing without a picture. }
    procedure Draw(ACanvas: TCanvas; ALeft, ATop, ASize: integer; AScale: double);
  end;

implementation

uses
  Math, BGRABitmapTypes, gittan.forge;

destructor TGittanAvatar.Destroy;
begin
  FDisc.Free;
  FImage.Free;
  inherited Destroy;
end;

function TGittanAvatar.SetData(const AData: string): boolean;
var
  Stream: TStringStream;
begin
  Result := AData <> FData;
  if not Result then
    Exit;
  FData := AData;
  FreeAndNil(FDisc);
  FreeAndNil(FImage);
  { Only a PNG or JPEG of a size worth drawing, its size read from its
    header: the decoder makes the whole bitmap before the pixels. }
  if not PictureFits(AData) then
    Exit;
  Stream := TStringStream.Create(AData);
  try
    try
      FImage := TBGRABitmap.Create(Stream);
      if (FImage.Width = 0) or (FImage.Height = 0) then
        FreeAndNil(FImage);
    except
      FreeAndNil(FImage);
    end;
  finally
    Stream.Free;
  end;
end;

function TGittanAvatar.HasImage: boolean;
begin
  Result := FImage <> nil;
end;

procedure TGittanAvatar.Draw(ACanvas: TCanvas; ALeft, ATop, ASize: integer; AScale: double);
var
  Pixels: integer;
  Mask: TBGRABitmap;
begin
  if FImage = nil then
    Exit;
  Pixels := Max(1, Round(ASize * AScale));
  if (FDisc = nil) or (FDisc.Width <> Pixels) then
  begin
    FreeAndNil(FDisc);
    FImage.ResampleFilter := rfBestQuality;
    FDisc := FImage.Resample(Pixels, Pixels, rmFineResample) as TBGRABitmap;
    Mask := TBGRABitmap.Create(Pixels, Pixels, BGRAPixelTransparent);
    try
      Mask.FillEllipseAntialias((Pixels - 1) / 2, (Pixels - 1) / 2, Pixels / 2, Pixels / 2,
        BGRAWhite);
      FDisc.ApplyMask(Mask);
    finally
      Mask.Free;
    end;
  end;
  FDisc.Draw(ACanvas, Rect(ALeft, ATop, ALeft + ASize, ATop + ASize), False);
end;

end.
