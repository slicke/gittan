unit gittan.textfit;

{** Text cut to a width with an ellipsis, for the controls that paint
  their own labels. The cut falls between UTF-8 characters, never
  inside one: a lone lead byte left at the end of a name cut at an "ö"
  is invalid UTF-8, which the widgetsets draw as nothing, a box or a
  replacement glyph. The longest part that fits is found by halving, so
  a long line costs a few measurements, not one per character. }

{$mode objfpc}{$H+}

interface

uses
  Graphics;

const
  Ellipsis = '…';

{** AText cut at the end with an ellipsis until it fits AWidth on
  ACanvas; AText itself when it fits, the ellipsis alone when not even
  one character does. }
function FitTextRight(ACanvas: TCanvas; const AText: string; AWidth: integer): string;

{** AText cut at the start with an ellipsis until it fits AWidth on
  ACanvas, so a long path keeps its end, which is the part that tells;
  AText itself when it fits, the ellipsis alone when not even one
  character does. }
function FitTextLeft(ACanvas: TCanvas; const AText: string; AWidth: integer): string;

{** The number of characters at the start of AText (ACount characters
  long) that fit AWidth on ACanvas, at least 1 when ACount is not 0, so
  a caller breaking a line always moves on. }
function FittingChars(ACanvas: TCanvas; const AText: string; ACount, AWidth: integer): integer;

implementation

uses
  LazUTF8;

function FitTextRight(ACanvas: TCanvas; const AText: string; AWidth: integer): string;
var
  Lo, Hi, Mid: integer;
begin
  Result := AText;
  if ACanvas.TextWidth(Result) <= AWidth then
    Exit;
  { The longest head of Lo characters that fits with the ellipsis. }
  Lo := 0;
  Hi := UTF8Length(AText) - 1;
  while Lo < Hi do
  begin
    Mid := (Lo + Hi + 1) div 2;
    if ACanvas.TextWidth(UTF8Copy(AText, 1, Mid) + Ellipsis) <= AWidth then
      Lo := Mid
    else
      Hi := Mid - 1;
  end;
  Result := UTF8Copy(AText, 1, Lo) + Ellipsis;
end;

function FitTextLeft(ACanvas: TCanvas; const AText: string; AWidth: integer): string;
var
  Len, Lo, Hi, Mid: integer;
begin
  Result := AText;
  if ACanvas.TextWidth(Result) <= AWidth then
    Exit;
  { The longest tail of Lo characters that fits after the ellipsis. }
  Len := UTF8Length(AText);
  Lo := 0;
  Hi := Len - 1;
  while Lo < Hi do
  begin
    Mid := (Lo + Hi + 1) div 2;
    if ACanvas.TextWidth(Ellipsis + UTF8Copy(AText, Len - Mid + 1, Mid)) <= AWidth then
      Lo := Mid
    else
      Hi := Mid - 1;
  end;
  Result := Ellipsis + UTF8Copy(AText, Len - Lo + 1, Lo);
end;

function FittingChars(ACanvas: TCanvas; const AText: string; ACount, AWidth: integer): integer;
var
  Lo, Hi, Mid: integer;
begin
  if ACount = 0 then
    Exit(0);
  Lo := 1;
  Hi := ACount;
  while Lo < Hi do
  begin
    Mid := (Lo + Hi + 1) div 2;
    if ACanvas.TextWidth(UTF8Copy(AText, 1, Mid)) <= AWidth then
      Lo := Mid
    else
      Hi := Mid - 1;
  end;
  Result := Lo;
end;

end.
