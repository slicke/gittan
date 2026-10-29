unit gittan.dialogicon;

{** The icon Gittan's dialogs and notices show for themselves: the braid
  graph alone, a red and a green strand crossing with a ring at each
  end, without the application icon's tile, so it sits on the dialog's
  own background in either appearance (the crossing's gap is a mask in
  the red strand, not a white stroke). PNGs of 48, 96 and 144 pixels
  from icons/gittan-dialog.svg, compiled in from gittan.dialogicon.inc
  (make dialogicon); the one for the size in device pixels is read once
  and kept. }

{$mode objfpc}{$H+}

interface

uses
  Graphics;

{** The icon at least APixels device pixels wide (the largest when none
  is), to draw with StretchDraw at the size in LCL pixels. Owned by the
  unit. }
function DialogIcon(APixels: integer): TGraphic;

implementation

uses
  Classes, SysUtils;

{$I gittan.dialogicon.inc}

var
  GIcons: array[0..2] of TPortableNetworkGraphic;

function LoadIcon(const ABytes: array of byte): TPortableNetworkGraphic;
var
  Stream: TMemoryStream;
begin
  Result := TPortableNetworkGraphic.Create;
  Stream := TMemoryStream.Create;
  try
    Stream.WriteBuffer(ABytes[0], Length(ABytes));
    Stream.Position := 0;
    Result.LoadFromStream(Stream);
  finally
    Stream.Free;
  end;
end;

function DialogIcon(APixels: integer): TGraphic;
var
  i: integer;
begin
  if APixels <= 48 then
    i := 0
  else if APixels <= 96 then
    i := 1
  else
    i := 2;
  if GIcons[i] = nil then
    case i of
      0: GIcons[i] := LoadIcon(DialogIcon48);
      1: GIcons[i] := LoadIcon(DialogIcon96);
      else
        GIcons[i] := LoadIcon(DialogIcon144);
    end;
  Result := GIcons[i];
end;

procedure FreeIcons;
var
  i: integer;
begin
  for i := 0 to High(GIcons) do
    FreeAndNil(GIcons[i]);
end;

finalization
  FreeIcons;
end.
