unit gittan.theme;

{** Dark mode support for Gittan.

  This unit tells whether the desktop theme is dark and adapts the colors
  Gittan sets itself: the editor palette and the lexer text colors, which
  the lexer collection tuned for a white background. The native controls
  follow the theme on their own on Cocoa and GTK 3, and on Windows through
  MetaDarkStyle. }

{$mode objfpc}{$H+}

interface

uses
  Graphics;

{** True when the desktop theme is dark, as ThemeServices.IsDarkTheme
  tells: the appearance on Cocoa, how dark the system colors are
  elsewhere. On Windows it is what MetaDarkStyle decided at startup
  (Gittan.lpr), which does not follow a later change, so the editor and
  what Gittan draws stay as dark as the native controls until a restart. }
function IsDarkMode: boolean;

{** Perceived brightness of an RGB value, 0 to 255. }
function ColorLuminance(C: TColor): double;

{** AColor lightened until it reads on a dark background. Black becomes
  clNone so the editor's own text color applies; a color that is already
  bright is returned as is. System colors are not RGB and are left alone. }
function LightenForDark(AColor: TColor): TColor;

{** AFrom moved AWeight of the way to ATo, 0 to 1, channel by channel;
  system colors are resolved first. }
function MixColor(AFrom, ATo: TColor; AWeight: double): TColor;

{** AValue, a length in pixels at 96 DPI, at the screen's DPI, for the
  controls that paint themselves: their text comes in the scaled font,
  so their rows, margins and icons have to grow with it. Cocoa reports
  96 whatever the display, so this is AValue on macOS and at 100 %. }
function Px(AValue: integer): integer;

implementation

uses
  {$IFDEF LCLWin32}uDarkStyleParams,{$ENDIF}
  LCLType, Themes, Forms;

{ Black and the lexers' other dark colors are blended toward white until
  they reach this brightness. The editor's dark text color sits at 224, so
  the result stays a little dimmer than plain text. }
const
  DarkTextLuminance = 170;

function ColorLuminance(C: TColor): double;
begin
  Result := (C and $FF) * 0.3 + ((C shr 8) and $FF) * 0.59 +
    ((C shr 16) and $FF) * 0.11;
end;

function IsDarkMode: boolean;
begin
  {$IFDEF LCLWin32}
  Result := IsDarkModeEnabled;
  {$ELSE}
  Result := ThemeServices.IsDarkTheme;
  {$ENDIF}
end;

{ Every channel is moved the same fraction of its way to 255. Luminance is
  linear in the channels, so the fraction that lands exactly on the target
  brightness is known without iterating. }
function LightenForDark(AColor: TColor): TColor;
var
  Lum, K: double;

  function Up(Channel: byte): byte;
  begin
    Result := Round(Channel + (255 - Channel) * K);
  end;

begin
  Result := AColor;
  if (AColor = clNone) or (AColor = clDefault) or
    ((AColor and SYS_COLOR_BASE) <> 0) then
    Exit;
  if AColor = clBlack then
    Exit(clNone);
  Lum := ColorLuminance(AColor);
  if Lum >= DarkTextLuminance then
    Exit;
  K := (DarkTextLuminance - Lum) / (255 - Lum);
  Result := RGBToColor(Up(Red(AColor)), Up(Green(AColor)), Up(Blue(AColor)));
end;

function MixColor(AFrom, ATo: TColor; AWeight: double): TColor;
var
  f, t: longint;
begin
  f := ColorToRGB(AFrom);
  t := ColorToRGB(ATo);
  Result := RGBToColor(Round(Red(f) + (Red(t) - Red(f)) * AWeight),
    Round(Green(f) + (Green(t) - Green(f)) * AWeight),
    Round(Blue(f) + (Blue(t) - Blue(f)) * AWeight));
end;

function Px(AValue: integer): integer;
begin
  Result := MulDiv(AValue, Screen.PixelsPerInch, 96);
end;

end.
