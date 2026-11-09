{ The window's own title bar (Windows).

  Windows draws the caption, and the menu bar under it, in the window's
  non-client area. InstallTitleBar takes that strip into the form's
  client area (WM_NCCALCSIZE keeps the top edge where the window's top
  is; the sides and the bottom keep their frame, so resizing and the
  shadow stay native) and TGittanWinTitleBar, aligned at the top of the
  form, takes its place: the bar of gittan.owntitlebar (the menu button,
  the tabs and the caption buttons) with the Windows parts of it.

  Windows asks the form what is under the mouse (WM_NCHITTEST). The bar
  answers HTTRANSPARENT for everything but its menu button, its tabs and
  its plus, so the form is asked; the form answers HTCAPTION for
  the bar's empty parts (a drag moves the window, a double click
  maximizes it, a right click opens the system menu) and the caption
  button codes for the buttons, HTMAXBUTTON giving Windows 11 its snap
  layouts. Windows would paint its old buttons for those codes, so the
  form handles the mouse on them itself and the bar paints them, hot and
  pressed, in Segoe Fluent Icons.

  The menu stays on the window, under the bar: commands are looked up
  in it and its shortcuts work. The bar's menu button drops a copy of it
  as a popup; Alt alone and F10 show the bar's own menu bar over it
  instead of the hidden one, and Alt with a letter shows it with the
  menu it underlines open. While a menu of it is open (TrackPopupMenuEx,
  modal) a message filter hook lets Left and Right and the mouse on
  another name move to the next menu, as in a menu bar.
  Windows still draws the hidden bar, and the line under it (white in
  dark mode; MetaDarkStyle paints over it at the top of the client area,
  now the window's top), over the client area when the window is
  activated or deactivated: WM_NCACTIVATE is passed on with -1, which
  asks for no repaint, and after it and WM_NCPAINT the form has the
  strip down to the line painted again (HideMenuBar).

  The unit uses the Windows API; umain keeps it behind LCLWin32. }
unit gittan.wintitlebar;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Menus, Types, Forms,
  gittan.owntitlebar;

type

  { TGittanWinTitleBar }

  TGittanWinTitleBar = class(TGittanOwnTitleBar)
  private
    FGlyphFont: string;
  protected
    function Maximized: boolean; override;
    procedure DrawGlyph(AGlyph: TGittanTitleGlyph; const AR: TRect;
      AColor: TColor); override;
    procedure CreateWnd; override;
    procedure TrackMenu(AStrip: TGittanMenuStrip; APopup: TPopupMenu;
      X, Y: integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** The part of the window the point of the bar is, as WM_NCHITTEST
      wants it: HTCLIENT, HTCAPTION or a caption button's code. }
    function HitCode(X, Y: integer): integer;
  end;

{** Takes the title bar's strip of the form's window into its client area
  and lets ABar, at the top of the form, stand for the title bar. }
procedure InstallTitleBar(AForm: TCustomForm; ABar: TGittanWinTitleBar);

implementation

uses
  Windows, Messages, LCLType, LCLIntf;

const
  { Segoe Fluent Icons (Windows 11) and Segoe MDL2 Assets (Windows 10). }
  GlyphMinimize = #$EE#$A4#$A1;
  GlyphMaximize = #$EE#$A4#$A2;
  GlyphRestore = #$EE#$A4#$A3;
  GlyphClose = #$EE#$A2#$BB;

  WM_NCMOUSELEAVE = $02A2;
  TME_NONCLIENT = $00000010;
  SM_CXPADDEDBORDER = 92;

var
  Bar: TGittanWinTitleBar;
  FormWnd: HWND;
  OldFormProc, OldBarProc: WNDPROC;
  { Where the client area would start under the menu bar, from the
    window's top, as WM_NCCALCSIZE found it. }
  MenuBottom: integer;
  { The hook while a menu of the menu strip is open, and the strip. }
  MenuHook: HHOOK;
  HookStrip: TGittanMenuStrip;

const
  MsgfMenu = 2;
  MnGetHMenu = $01E1;

function EndMenuLoop: BOOL; stdcall; external 'user32' name 'EndMenu';

{ The open menus' windows of this thread, counted; ADeepest the topmost,
  the submenu opened last. }
function OpenMenuWindows(out ADeepest: HWND): integer;
var
  W: HWND;
  Pid: DWORD;
begin
  Result := 0;
  ADeepest := 0;
  W := FindWindowExW(0, 0, '#32768', nil);
  while W <> 0 do
  begin
    if IsWindowVisible(W) and (GetWindowThreadProcessId(W, @Pid) = GetCurrentThreadId) then
    begin
      if ADeepest = 0 then
        ADeepest := W;
      Inc(Result);
    end;
    W := FindWindowExW(0, W, '#32768', nil);
  end;
end;

{ Whether the item marked in the menu of the window AMenuWnd opens a
  submenu, which Right then opens. }
function MarkedHasSubmenu(AMenuWnd: HWND): boolean;
var
  M: HMENU;
  i: integer;
begin
  Result := False;
  if AMenuWnd = 0 then
    Exit;
  M := HMENU(SendMessageW(AMenuWnd, MnGetHMenu, 0, 0));
  if M = 0 then
    Exit;
  for i := 0 to GetMenuItemCount(M) - 1 do
    if GetMenuState(M, i, MF_BYPOSITION) and MF_HILITE <> 0 then
      Exit(GetSubMenu(M, i) <> 0);
end;

{ The menu's modal loop: Left in the strip's menu itself and Right on an
  item without a submenu go to the menu beside it, and the mouse on
  another name of the strip to that one; the open menu ends, and the
  strip opens the next once it has. }
function MenuFilter(Code: longint; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  Msg: PMsg;
  Deepest: HWND;
  Step: boolean;
begin
  if (Code = MsgfMenu) and (HookStrip <> nil) then
  begin
    Msg := PMsg(LParam);
    Step := False;
    case Msg^.message of
      WM_KEYDOWN:
        if Msg^.wParam = VK_LEFT then
        begin
          if OpenMenuWindows(Deepest) <= 1 then
            Step := HookStrip.StepMenu(-1);
        end
        else if Msg^.wParam = VK_RIGHT then
        begin
          OpenMenuWindows(Deepest);
          if not MarkedHasSubmenu(Deepest) then
            Step := HookStrip.StepMenu(1);
        end;
      WM_MOUSEMOVE:
        Step := HookStrip.HoverAt(Msg^.pt);
    end;
    if Step then
    begin
      EndMenuLoop;
      Exit(1);
    end;
  end;
  Result := CallNextHookEx(MenuHook, Code, WParam, LParam);
end;

{ The resize border's thickness, as Windows sizes it for the window. }
function FrameThickness(AWnd: HWND; AVertical: boolean): integer;
type
  TGetDpiForWindow = function(hwnd: HWND): UINT; stdcall;
  TGetSystemMetricsForDpi = function(nIndex: integer; dpi: UINT): integer; stdcall;
var
  User: HMODULE;
  GetDpi: TGetDpiForWindow;
  GetMetrics: TGetSystemMetricsForDpi;
  Dpi: UINT;
  Index: integer;
begin
  if AVertical then
    Index := SM_CYFRAME
  else
    Index := SM_CXFRAME;
  User := GetModuleHandle('user32.dll');
  Pointer(GetDpi) := GetProcAddress(User, 'GetDpiForWindow');
  Pointer(GetMetrics) := GetProcAddress(User, 'GetSystemMetricsForDpi');
  if Assigned(GetDpi) and Assigned(GetMetrics) then
  begin
    Dpi := GetDpi(AWnd);
    Result := GetMetrics(Index, Dpi) + GetMetrics(SM_CXPADDEDBORDER, Dpi);
  end
  else
    Result := GetSystemMetrics(Index) + GetSystemMetrics(SM_CXPADDEDBORDER);
end;

function PartCode(APart: TGittanTitlePart): integer;
begin
  case APart of
    tpMinimize: Result := HTMINBUTTON;
    tpMaximize: Result := HTMAXBUTTON;
    tpClose: Result := HTCLOSE;
  else
    Result := HTNOWHERE;
  end;
end;

function CodePart(ACode: integer): TGittanTitlePart;
begin
  case ACode of
    HTMINBUTTON: Result := tpMinimize;
    HTMAXBUTTON: Result := tpMaximize;
    HTCLOSE: Result := tpClose;
  else
    Result := tpNone;
  end;
end;

{ Has the strip of the form where Windows draws the hidden menu bar and
  the line under it painted again, over what it drew. }
procedure HideMenuBar(AWnd: HWND);
var
  W: TRect;
  P: TPoint;
  R: TRect;
begin
  if MenuBottom <= 0 then
    Exit;
  Windows.GetWindowRect(AWnd, W);
  P := Types.Point(0, 0);
  Windows.ClientToScreen(AWnd, P);
  { The line is the row above MenuBottom; a row more below it. }
  R.Top := 0;
  R.Bottom := W.Top + MenuBottom + 1 - P.Y;
  R.Left := 0;
  R.Right := W.Right - W.Left;
  RedrawWindow(AWnd, @R, 0, RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN);
end;

{ The bar's own window: the parts that take clicks are its own, the rest
  goes to the form, which knows the caption and the buttons. }
function BarProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  P: TPoint;
begin
  if (Msg = WM_NCHITTEST) and (Bar <> nil) then
  begin
    P := Types.Point(GET_X_LPARAM(LParam), GET_Y_LPARAM(LParam));
    Windows.ScreenToClient(Wnd, P);
    if Bar.HitCode(P.X, P.Y) <> HTCLIENT then
      Exit(HTTRANSPARENT);
  end;
  Result := CallWindowProcW(OldBarProc, Wnd, Msg, WParam, LParam);
end;

function FormProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  Params: PNCCalcSizeParams;
  Top, Border: integer;
  P: TPoint;
  R: TRect;
  Track: TTrackMouseEvent;
  Part: TGittanTitlePart;
begin
  case Msg of
    WM_NCCALCSIZE:
      if WParam <> 0 then
      begin
        { The frame on three sides as Windows has it; none at the top,
          where the bar is. A maximized window reaches past the screen
          by its frame, which would cut the bar. }
        Params := PNCCalcSizeParams(LParam);
        Top := Params^.rgrc[0].Top;
        Result := CallWindowProcW(OldFormProc, Wnd, Msg, WParam, LParam);
        MenuBottom := Params^.rgrc[0].Top - Top;
        Params^.rgrc[0].Top := Top;
        if IsZoomed(Wnd) then
          Inc(Params^.rgrc[0].Top, FrameThickness(Wnd, True));
        Exit;
      end;
    WM_NCHITTEST:
      begin
        Result := CallWindowProcW(OldFormProc, Wnd, Msg, WParam, LParam);
        if (Result <> HTCLIENT) or (Bar = nil) then
          Exit;
        P := Types.Point(GET_X_LPARAM(LParam), GET_Y_LPARAM(LParam));
        Windows.ScreenToClient(Wnd, P);
        { The top edge resizes, as the frame would. }
        if not IsZoomed(Wnd) then
        begin
          Border := FrameThickness(Wnd, True);
          Windows.GetClientRect(Wnd, R);
          if P.Y < Border then
          begin
            if P.X < Border * 2 then
              Exit(HTTOPLEFT)
            else if P.X >= R.Right - Border * 2 then
              Exit(HTTOPRIGHT)
            else
              Exit(HTTOP);
          end;
        end;
        P := Bar.ScreenToClient(Types.Point(GET_X_LPARAM(LParam), GET_Y_LPARAM(LParam)));
        if (P.Y >= 0) and (P.Y < Bar.Height) and (P.X >= 0) and (P.X < Bar.Width) then
          Result := Bar.HitCode(P.X, P.Y);
        Exit;
      end;
    WM_NCMOUSEMOVE:
      if Bar <> nil then
      begin
        Part := CodePart(WParam);
        Bar.SetButtonState(Part, Bar.PressedButton);
        if Part <> tpNone then
        begin
          Track.cbSize := SizeOf(Track);
          Track.dwFlags := TME_LEAVE or TME_NONCLIENT;
          Track.hwndTrack := Wnd;
          Track.dwHoverTime := 0;
          TrackMouseEvent(Track);
          Exit(0);
        end;
      end;
    WM_NCMOUSELEAVE:
      if Bar <> nil then
        Bar.SetButtonState(tpNone, tpNone);
    WM_NCLBUTTONDOWN, WM_NCLBUTTONDBLCLK:
      if CodePart(WParam) <> tpNone then
      begin
        Bar.SetButtonState(CodePart(WParam), CodePart(WParam));
        Exit(0);
      end;
    WM_NCLBUTTONUP:
      if CodePart(WParam) <> tpNone then
      begin
        Part := CodePart(WParam);
        if Part = Bar.PressedButton then
          case Part of
            tpMinimize: PostMessage(Wnd, WM_SYSCOMMAND, SC_MINIMIZE, 0);
            tpMaximize:
              if IsZoomed(Wnd) then
                PostMessage(Wnd, WM_SYSCOMMAND, SC_RESTORE, 0)
              else
                PostMessage(Wnd, WM_SYSCOMMAND, SC_MAXIMIZE, 0);
            tpClose: PostMessage(Wnd, WM_SYSCOMMAND, SC_CLOSE, 0);
          end;
        Bar.SetButtonState(Part, tpNone);
        Exit(0);
      end;
    WM_SYSCOMMAND:
      { Alt and a letter would open the hidden menu bar; the bar shows
        its own with that menu open instead, and Alt alone or F10 (no
        letter) shows it with the focus, or hides it again. }
      if (WParam and $FFF0 = SC_KEYMENU) and (Bar <> nil) then
      begin
        if LParam = 0 then
          Bar.OpenMenu
        else if LParam <> Ord(' ') then
          Bar.OpenMenuByKey(Chr(LParam and $FF));
        if LParam <> Ord(' ') then
          Exit(0);
      end;
    WM_ACTIVATE:
      if Bar <> nil then
        Bar.Active := LOWORD(WParam) <> WA_INACTIVE;
    WM_SIZE:
      if Bar <> nil then
        Bar.Invalidate;
    WM_NCACTIVATE:
      begin
        Result := CallWindowProcW(OldFormProc, Wnd, Msg, WParam, -1);
        HideMenuBar(Wnd);
        Exit;
      end;
    WM_NCPAINT:
      begin
        Result := CallWindowProcW(OldFormProc, Wnd, Msg, WParam, LParam);
        HideMenuBar(Wnd);
        Exit;
      end;
  end;
  Result := CallWindowProcW(OldFormProc, Wnd, Msg, WParam, LParam);
end;

procedure InstallTitleBar(AForm: TCustomForm; ABar: TGittanWinTitleBar);
begin
  Bar := ABar;
  FormWnd := AForm.Handle;
  OldFormProc := WNDPROC(SetWindowLongPtrW(FormWnd, GWLP_WNDPROC,
    LONG_PTR(@FormProc)));
  OldBarProc := WNDPROC(SetWindowLongPtrW(ABar.Handle, GWLP_WNDPROC,
    LONG_PTR(@BarProc)));
  ABar.Active := GetActiveWindow = FormWnd;
  { Windows asks for the frame again. }
  SetWindowPos(FormWnd, 0, 0, 0, 0, 0, SWP_FRAMECHANGED or SWP_NOMOVE or
    SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
end;

{ TGittanWinTitleBar }

constructor TGittanWinTitleBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  if Screen.Fonts.IndexOf('Segoe Fluent Icons') >= 0 then
    FGlyphFont := 'Segoe Fluent Icons'
  else
    FGlyphFont := 'Segoe MDL2 Assets';
end;

destructor TGittanWinTitleBar.Destroy;
begin
  { The form's window outlives the bar for a while. }
  if Bar = Self then
    Bar := nil;
  inherited Destroy;
end;

procedure TGittanWinTitleBar.TrackMenu(AStrip: TGittanMenuStrip; APopup: TPopupMenu;
  X, Y: integer);
begin
  HookStrip := AStrip;
  MenuHook := SetWindowsHookExW(WH_MSGFILTER, HOOKPROC(@MenuFilter), 0,
    GetCurrentThreadId);
  try
    { The LCL's popup is TrackPopupMenuEx, which returns once the menu
      has closed. }
    inherited TrackMenu(AStrip, APopup, X, Y);
  finally
    if MenuHook <> 0 then
      UnhookWindowsHookEx(MenuHook);
    MenuHook := 0;
    HookStrip := nil;
  end;
end;

procedure TGittanWinTitleBar.CreateWnd;
begin
  inherited CreateWnd;
  { InstallTitleBar subclasses the window; a new one (after a DPI change
    recreated it) is subclassed again. }
  if (Bar = Self) and (FormWnd <> 0) then
    OldBarProc := Windows.WNDPROC(SetWindowLongPtrW(Handle, GWLP_WNDPROC,
      LONG_PTR(@BarProc)));
end;

{ The window's maximized state, from its handle; False before it has one. }
function TGittanWinTitleBar.Maximized: boolean;
begin
  Result := (FormWnd <> 0) and IsZoomed(FormWnd);
end;

function TGittanWinTitleBar.HitCode(X, Y: integer): integer;
var
  Index: integer;
begin
  case PartAt(X, Y, Index) of
    tpNone: Result := HTCAPTION;
    tpMinimize, tpMaximize, tpClose: Result := PartCode(PartAt(X, Y, Index));
  else
    Result := HTCLIENT;
  end;
end;

procedure TGittanWinTitleBar.DrawGlyph(AGlyph: TGittanTitleGlyph; const AR: TRect;
  AColor: TColor);
var
  S: string;
begin
  case AGlyph of
    tgMinimize: S := GlyphMinimize;
    tgMaximize: S := GlyphMaximize;
    tgRestore: S := GlyphRestore;
  else
    S := GlyphClose;
  end;
  Canvas.Font.Name := FGlyphFont;
  Canvas.Font.Height := -Scale96ToForm(10);
  Canvas.Font.Color := AColor;
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(AR.Left + (AR.Width - Canvas.TextWidth(S)) div 2,
    AR.Top + (AR.Height - Canvas.TextHeight(S)) div 2, S);
  Canvas.Font := Font;
end;

end.
