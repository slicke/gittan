unit gittan.theme;

{** Dark mode support for Gittan.

  This unit tells whether the desktop theme is dark and adapts the colors
  Gittan sets itself: the editor palette and the lexer text colors, which
  the lexer collection tuned for a white background. The native controls
  follow the theme on their own on Cocoa and Qt; on Windows they stay
  light. }

{$mode objfpc}{$H+}

interface

uses
  Graphics;

{** True when the desktop theme is dark, as ThemeServices.IsDarkTheme
  tells: the appearance on Cocoa, AppsUseLightTheme in the registry on
  Windows 10 and later, how dark the system colors are elsewhere. }
function IsDarkMode: boolean;

{** Perceived brightness of an RGB value, 0 to 255. }
function ColorLuminance(C: TColor): double;

{** AColor lightened until it reads on a dark background. Black becomes
  clNone so the editor's own text color applies; a color that is already
  bright is returned as is. System colors are not RGB and are left alone. }
function LightenForDark(AColor: TColor): TColor;

{$IFDEF LCLWin32}
{** Opts the process into uxtheme's dark mode, as Trndi does, so the
  DarkMode_ theme classes resolve. Done before the first window, when the
  desktop is dark at startup; on Windows before 10 1809 nothing happens. }
procedure AllowDarkApp;

{** Gives AWnd the dark Explorer theme (dark scroll bars) or, with ADark
  False, the default one again. }
procedure DarkWindowTheme(AWnd: THandle; ADark: boolean);
{$ENDIF}

implementation

uses
  {$IFDEF LCLWin32}Windows,{$ENDIF}
  LCLType, Themes;

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
  Result := ThemeServices.IsDarkTheme;
end;

{$IFDEF LCLWin32}
const
  WM_THEMECHANGED = $031A;

type
  { uxtheme's ordinal 135: SetPreferredAppMode on Windows 10 1903 and later,
    AllowDarkModeForApp (a BOOL) on 1809; 1 means allow dark in both. }
  TSetPreferredAppMode = function(AMode: integer): integer; stdcall;
  { Ordinal 133. }
  TAllowDarkModeForWindow = function(AWnd: HWND; AAllow: BOOL): BOOL; stdcall;

function SetWindowTheme(AWnd: HWND; ASubAppName, ASubIdList: PWideChar): HRESULT;
  stdcall; external 'uxtheme.dll' name 'SetWindowTheme';

procedure AllowDarkApp;
var
  SetMode: TSetPreferredAppMode;
begin
  Pointer(SetMode) := GetProcAddress(GetModuleHandle('uxtheme.dll'),
    MAKEINTRESOURCE(135));
  if Assigned(SetMode) then
    SetMode(1);
end;

procedure DarkWindowTheme(AWnd: THandle; ADark: boolean);
var
  AllowDark: TAllowDarkModeForWindow;
begin
  if AWnd = 0 then
    Exit;
  Pointer(AllowDark) := GetProcAddress(GetModuleHandle('uxtheme.dll'),
    MAKEINTRESOURCE(133));
  if Assigned(AllowDark) then
    AllowDark(AWnd, ADark);
  if ADark then
    SetWindowTheme(AWnd, PWideChar(UnicodeString('DarkMode_Explorer')), nil)
  else
    SetWindowTheme(AWnd, nil, nil);
  { The window keeps the theme it opened until told it changed. }
  SendMessage(AWnd, WM_THEMECHANGED, 0, 0);
end;
{$ENDIF}

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

end.
