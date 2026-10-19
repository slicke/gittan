{ The window's own title bar (Windows).

  Windows draws the caption, and the menu bar under it, in the window's
  non-client area. InstallTitleBar takes that strip into the form's
  client area (WM_NCCALCSIZE keeps the top edge where the window's top
  is; the sides and the bottom keep their frame, so resizing and the
  shadow stay native) and TGittanWinTitleBar, aligned at the top of the
  form, takes its place, as in VS Code or Windows Terminal: the name and
  the menus on the left, the file filter as a rounded search field in
  the middle, and on the right the change navigator, the actions the
  view offers (the file header's pills) and the minimize, maximize and
  close buttons.

  Windows asks the form what is under the mouse (WM_NCHITTEST). The bar
  answers HTTRANSPARENT for everything but its menus, the search field
  and the pills, so the form is asked; the form answers HTCAPTION for
  the bar's empty parts (a drag moves the window, a double click
  maximizes it, a right click opens the system menu) and the caption
  button codes for the buttons, HTMAXBUTTON giving Windows 11 its snap
  layouts. Windows would paint its old buttons for those codes, so the
  form handles the mouse on them itself and the bar paints them, hot and
  pressed.

  The menu stays on the window, under the bar: commands are looked up
  in it and its shortcuts work. A click on a menu name in the bar opens
  that submenu with TrackPopupMenuEx, owned by the form, and Alt with a
  letter opens the menu it underlines there instead of the hidden bar.

  SetBand draws a progress band along the bar's top edge, as the band
  over the title bar on macOS (gittan.titlebar): the bar paints it, in
  the strip above its menus, field and pills.

  The unit uses the Windows API; umain keeps it behind LCLWin32. }
unit gittan.wintitlebar;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, StdCtrls, Menus, Types, Forms,
  gittan.changenav;

type
  {** A click on the action at AIndex, in the order of SetActions. }
  TGittanTitleActionEvent = procedure(Sender: TObject; AIndex: integer) of object;

  {** What a point of the bar is: a menu name, the search field, the clear
    button, an action, a caption button, or nothing (a drag area). }
  TGittanTitlePart = (tpNone, tpMenu, tpSearch, tpClear, tpAction,
    tpMinimize, tpMaximize, tpClose);

  { TGittanWinTitleBar }

  TGittanWinTitleBar = class(TCustomControl)
  private
    FSearch: TCustomEdit;
    FNav: TGittanChangeNav;
    FSplitControl: TControl;
    FActions: array of string;
    FEnabled: array of boolean;
    FActionRects: array of TRect;
    FMenuRects: array of TRect;
    FMenuItems: array of TMenuItem;
    FSearchRect, FClearRect, FMinRect, FMaxRect, FCloseRect: TRect;
    FHotPart, FPressedPart, FHotButton, FPressedButton: TGittanTitlePart;
    FHotIndex, FPressedIndex, FOpenMenu: integer;
    FActive: boolean;
    FSide, FMain, FText, FDim, FPillFill, FPillBorder, FHotColor: TColor;
    FSearchFill, FSearchBorder, FButtonHot: TColor;
    FBandPos, FBandTotal: integer;
    FBandTrack, FBandFill: TColor;
    FGlyphFont, FTitle: string;
    FOnAction: TGittanTitleActionEvent;
    procedure SetSearch(AValue: TCustomEdit);
    procedure SetActive(AValue: boolean);
    function PartAt(X, Y: integer; out AIndex: integer): TGittanTitlePart;
    function BandFillWidth(APos, ATotal: integer): integer;
    function MenuOf(AForm: TCustomForm): TMainMenu;
    procedure SetHot(APart: TGittanTitlePart; AIndex: integer);
    procedure OpenMenu(AIndex: integer);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** The part of the window the point of the bar is, as WM_NCHITTEST
      wants it: HTCLIENT, HTCAPTION or a caption button's code. }
    function HitCode(X, Y: integer): integer;
    {** The caption button under the mouse or pressed, tpNone for none;
      set by the form, which sees the mouse there. }
    procedure SetButtonState(AHot, APressed: TGittanTitlePart);
    {** Places the menus, the search field, the navigator and the pills;
      again after the menu changed. }
    procedure Layout;
    {** Opens the menu whose name has the accelerator AKey; False when
      none has it. }
    function OpenMenuByKey(AKey: char): boolean;
    {** The action buttons, left to right, each enabled as AEnabled says;
      none for an empty array. }
    procedure SetActions(const ACaptions: array of string;
      const AEnabled: array of boolean);
    {** Shows the navigator at ACurrent of ATotal changes, or hides it when
      ATotal is 0. }
    procedure SetChanges(ACurrent, ATotal: integer);
    {** The bar's colors: the shade over the sidebar and the background
      over the rest, the text and the dim text, the pills' fill, border
      and text under the mouse, the search field's fill and border, and a
      caption button under the mouse. }
    procedure SetColors(ASide, AMain, AText, ADim, APillFill, APillBorder, AHot,
      ASearchFill, ASearchBorder, AButtonHot: TColor);
    {** Shows the band along the top edge, APos of ATotal filled, in the
      colors ATrack and AFill; ATotal 0 hides it. }
    procedure SetBand(APos, ATotal: integer; ATrack, AFill: TColor);
    {** The filter field, borderless, laid out inside the rounded box. }
    property Search: TCustomEdit read FSearch write SetSearch;
    {** The control whose right edge ends the sidebar's shade. }
    property SplitControl: TControl read FSplitControl write FSplitControl;
    property Nav: TGittanChangeNav read FNav;
    {** The name on the left. }
    property Title: string read FTitle write FTitle;
    {** Whether the window is the active one; the text dims when not. }
    property Active: boolean read FActive write SetActive;
    property OnAction: TGittanTitleActionEvent read FOnAction write FOnAction;
  end;

{** Takes the title bar's strip of the form's window into its client area
  and lets ABar, at the top of the form, stand for the title bar. }
procedure InstallTitleBar(AForm: TCustomForm; ABar: TGittanWinTitleBar);

implementation

uses
  Windows, Messages, LCLType, LCLIntf, Math;

const
  BarHeight = 40;
  Pad = 12;
  Gap = 8;
  MenuPad = 8;
  SearchWidth = 320;
  SearchHeight = 28;
  SearchMin = 140;
  PillHeight = 24;
  PillPad = 10;
  PillGap = 6;
  ButtonWidth = 46;
  NavHeight = 26;
  BandHeight = 3;
  { The least the band's fill is wide: Windows 11 rounds the window's
    corners, which hide its first pixels. }
  MinBandFill = 16;
  { Segoe Fluent Icons (Windows 11) and Segoe MDL2 Assets (Windows 10). }
  GlyphMinimize = #$EE#$A4#$A1;
  GlyphMaximize = #$EE#$A4#$A2;
  GlyphRestore = #$EE#$A4#$A3;
  GlyphClose = #$EE#$A2#$BB;
  GlyphSearch = #$EE#$9C#$A1;
  GlyphClear = #$EE#$9C#$91;
  CloseHot = $1C2BC4; { RGB(196, 43, 28) }

  WM_NCMOUSELEAVE = $02A2;
  TME_NONCLIENT = $00000010;
  SM_CXPADDEDBORDER = 92;

var
  Bar: TGittanWinTitleBar;
  FormWnd: HWND;
  OldFormProc, OldBarProc: WNDPROC;

{ The window's maximized state, from its handle; False before it has one. }
function Zoomed(AControl: TWinControl): boolean;
begin
  Result := (FormWnd <> 0) and IsZoomed(FormWnd);
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
        Bar.SetButtonState(Part, Bar.FPressedButton);
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
        if Part = Bar.FPressedButton then
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
      { Alt and a letter would open the hidden menu bar; the bar opens
        the menu instead. Alt alone and F10 do nothing. }
      if (WParam and $FFF0 = SC_KEYMENU) and (Bar <> nil) then
      begin
        if (LParam <> 0) and (LParam <> Ord(' ')) then
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
  ControlStyle := ControlStyle + [csOpaque];
  { Not Scale96ToForm: the bar has no form yet. }
  Height := Scale96ToScreen(BarHeight);
  FHotIndex := -1;
  FPressedIndex := -1;
  FOpenMenu := -1;
  FActive := True;
  FNav := TGittanChangeNav.Create(Self);
  FNav.Parent := Self;
  FNav.Height := Scale96ToScreen(NavHeight);
  FNav.Visible := False;
  if Screen.Fonts.IndexOf('Segoe Fluent Icons') >= 0 then
    FGlyphFont := 'Segoe Fluent Icons'
  else
    FGlyphFont := 'Segoe MDL2 Assets';
  SetColors(clBtnFace, clWindow, clWindowText, clGrayText, clBtnFace,
    clBtnShadow, clHighlight, clWindow, clBtnShadow, clBtnFace);
end;

destructor TGittanWinTitleBar.Destroy;
begin
  { The form's window outlives the bar for a while. }
  if Bar = Self then
    Bar := nil;
  inherited Destroy;
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

procedure TGittanWinTitleBar.SetSearch(AValue: TCustomEdit);
begin
  FSearch := AValue;
  if FSearch = nil then
    Exit;
  FSearch.Parent := Self;
  FSearch.Align := alNone;
  FSearch.BorderStyle := bsNone;
  FSearch.BorderSpacing.Around := 0;
  FSearch.BorderSpacing.Top := 0;
  Layout;
end;

procedure TGittanWinTitleBar.SetActive(AValue: boolean);
begin
  if FActive = AValue then
    Exit;
  FActive := AValue;
  Invalidate;
end;

procedure TGittanWinTitleBar.SetColors(ASide, AMain, AText, ADim, APillFill,
  APillBorder, AHot, ASearchFill, ASearchBorder, AButtonHot: TColor);
begin
  FSide := ASide;
  FMain := AMain;
  FText := AText;
  FDim := ADim;
  FPillFill := APillFill;
  FPillBorder := APillBorder;
  FHotColor := AHot;
  FSearchFill := ASearchFill;
  FSearchBorder := ASearchBorder;
  FButtonHot := AButtonHot;
  Color := AMain;
  if FSearch <> nil then
  begin
    FSearch.Color := ASearchFill;
    FSearch.Font.Color := AText;
  end;
  Invalidate;
end;

procedure TGittanWinTitleBar.SetActions(const ACaptions: array of string;
  const AEnabled: array of boolean);
var
  i: integer;
  Same: boolean;
begin
  Same := Length(ACaptions) = Length(FActions);
  if Same then
    for i := 0 to High(ACaptions) do
      if (FActions[i] <> ACaptions[i]) or
        (FEnabled[i] <> ((i > High(AEnabled)) or AEnabled[i])) then
        Same := False;
  if Same then
    Exit;
  SetLength(FActions, Length(ACaptions));
  SetLength(FEnabled, Length(ACaptions));
  SetLength(FActionRects, Length(ACaptions));
  for i := 0 to High(ACaptions) do
  begin
    FActions[i] := ACaptions[i];
    FEnabled[i] := (i > High(AEnabled)) or AEnabled[i];
  end;
  FHotPart := tpNone;
  FPressedPart := tpNone;
  Layout;
  Invalidate;
end;

procedure TGittanWinTitleBar.SetChanges(ACurrent, ATotal: integer);
begin
  if ATotal > 0 then
    FNav.SetPosition(ACurrent, ATotal);
  if FNav.Visible <> (ATotal > 0) then
  begin
    FNav.Visible := ATotal > 0;
    Layout;
    Invalidate;
  end;
end;

function TGittanWinTitleBar.BandFillWidth(APos, ATotal: integer): integer;
begin
  if ATotal <= 0 then
    Result := 0
  else
    Result := Max(Scale96ToForm(MinBandFill), Width * Min(APos, ATotal) div ATotal);
end;

{ Called for every file indexed: only the band is repainted, and only
  when its fill grows by a pixel or its colors change. }
procedure TGittanWinTitleBar.SetBand(APos, ATotal: integer; ATrack, AFill: TColor);
var
  R: TRect;
  Same: boolean;
begin
  Same := ((ATotal > 0) = (FBandTotal > 0)) and (ATrack = FBandTrack) and
    (AFill = FBandFill) and
    (BandFillWidth(APos, ATotal) = BandFillWidth(FBandPos, FBandTotal));
  FBandPos := APos;
  FBandTotal := ATotal;
  FBandTrack := ATrack;
  FBandFill := AFill;
  if Same or not HandleAllocated then
    Exit;
  R := Types.Rect(0, 0, Width, Scale96ToForm(BandHeight));
  InvalidateRect(Handle, @R, False);
end;

procedure TGittanWinTitleBar.SetButtonState(AHot, APressed: TGittanTitlePart);
begin
  if (FHotButton = AHot) and (FPressedButton = APressed) then
    Exit;
  FHotButton := AHot;
  FPressedButton := APressed;
  Invalidate;
end;

function TGittanWinTitleBar.MenuOf(AForm: TCustomForm): TMainMenu;
begin
  Result := nil;
  if AForm <> nil then
    Result := AForm.Menu;
end;

{ Right to left: the caption buttons, the pills, the navigator; from the
  left the name and the menus; the search field centered on the bar in
  the room that is left, narrower when there is little. }
procedure TGittanWinTitleBar.Layout;
var
  Right, LeftEdge, X, W, H, i, Room, SearchW: integer;
  Menu: TMainMenu;
  Item: TMenuItem;
  S: string;
begin
  if not HandleAllocated then
    Exit;
  H := Height;
  Canvas.Font := Font;
  W := Scale96ToForm(ButtonWidth);
  FCloseRect := Types.Rect(Width - W, 0, Width, H);
  FMaxRect := Types.Rect(FCloseRect.Left - W, 0, FCloseRect.Left, H);
  FMinRect := Types.Rect(FMaxRect.Left - W, 0, FMaxRect.Left, H);
  Right := FMinRect.Left - Scale96ToForm(Gap);
  for i := High(FActions) downto 0 do
  begin
    W := Canvas.TextWidth(FActions[i]) + 2 * Scale96ToForm(PillPad);
    FActionRects[i] := Types.Rect(Right - W, (H - Scale96ToForm(PillHeight)) div 2,
      Right, (H + Scale96ToForm(PillHeight)) div 2);
    Right := FActionRects[i].Left - Scale96ToForm(PillGap);
  end;
  if FNav.Visible then
  begin
    FNav.SetBounds(Right - FNav.Width, (H - FNav.Height) div 2, FNav.Width,
      FNav.Height);
    Right := FNav.Left - Scale96ToForm(Gap);
  end;

  { The name is bold. }
  Canvas.Font.Style := [fsBold];
  X := Scale96ToForm(Pad) + Canvas.TextWidth(FTitle) +
    Scale96ToForm(Pad);
  Canvas.Font.Style := [];
  Menu := MenuOf(GetParentForm(Self));
  SetLength(FMenuRects, 0);
  SetLength(FMenuItems, 0);
  if Menu <> nil then
    for i := 0 to Menu.Items.Count - 1 do
    begin
      Item := Menu.Items[i];
      if not Item.Visible then
        Continue;
      S := StripHotkey(Item.Caption);
      W := Canvas.TextWidth(S) + 2 * Scale96ToForm(MenuPad);
      SetLength(FMenuRects, Length(FMenuRects) + 1);
      SetLength(FMenuItems, Length(FMenuItems) + 1);
      FMenuRects[High(FMenuRects)] := Types.Rect(X, (H - Scale96ToForm(PillHeight)) div 2,
        X + W, (H + Scale96ToForm(PillHeight)) div 2);
      FMenuItems[High(FMenuItems)] := Item;
      Inc(X, W);
    end;
  LeftEdge := X + Scale96ToForm(Gap);

  Room := Right - LeftEdge;
  SearchW := Min(Scale96ToForm(SearchWidth), Room);
  if SearchW < Scale96ToForm(SearchMin) then
    FSearchRect := Types.Rect(0, 0, 0, 0)
  else
  begin
    X := (Width - SearchW) div 2;
    X := Max(LeftEdge, Min(X, Right - SearchW));
    FSearchRect := Types.Rect(X, (H - Scale96ToForm(SearchHeight)) div 2, X + SearchW,
      (H + Scale96ToForm(SearchHeight)) div 2);
  end;
  W := Scale96ToForm(SearchHeight);
  FClearRect := Types.Rect(FSearchRect.Right - W, FSearchRect.Top, FSearchRect.Right,
    FSearchRect.Bottom);
  if FSearch <> nil then
  begin
    FSearch.Visible := not FSearchRect.IsEmpty;
    if FSearch.Visible then
      FSearch.SetBounds(FSearchRect.Left + W, FSearchRect.Top +
        (FSearchRect.Height - FSearch.Height) div 2, FSearchRect.Width - 2 * W,
        FSearch.Height);
  end;
end;

procedure TGittanWinTitleBar.Resize;
begin
  inherited Resize;
  Layout;
end;

function TGittanWinTitleBar.PartAt(X, Y: integer; out AIndex: integer): TGittanTitlePart;
var
  i: integer;
  P: TPoint;
begin
  AIndex := -1;
  P := Types.Point(X, Y);
  if FCloseRect.Contains(P) then
    Exit(tpClose);
  if FMaxRect.Contains(P) then
    Exit(tpMaximize);
  if FMinRect.Contains(P) then
    Exit(tpMinimize);
  for i := 0 to High(FMenuRects) do
    if FMenuRects[i].Contains(P) then
    begin
      AIndex := i;
      Exit(tpMenu);
    end;
  for i := 0 to High(FActionRects) do
    if FActionRects[i].Contains(P) then
    begin
      AIndex := i;
      Exit(tpAction);
    end;
  if (FSearch <> nil) and (FSearch.Text <> '') and FClearRect.Contains(P) then
    Exit(tpClear);
  if FSearchRect.Contains(P) then
    Exit(tpSearch);
  Result := tpNone;
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

procedure TGittanWinTitleBar.SetHot(APart: TGittanTitlePart; AIndex: integer);
begin
  if (FHotPart = APart) and (FHotIndex = AIndex) then
    Exit;
  FHotPart := APart;
  FHotIndex := AIndex;
  if APart = tpSearch then
    Cursor := crIBeam
  else
    Cursor := crDefault;
  Invalidate;
end;

procedure TGittanWinTitleBar.MouseMove(Shift: TShiftState; X, Y: integer);
var
  Index: integer;
  Part: TGittanTitlePart;
begin
  inherited MouseMove(Shift, X, Y);
  Part := PartAt(X, Y, Index);
  if (Part = tpAction) and not FEnabled[Index] then
    Part := tpNone;
  SetHot(Part, Index);
end;

procedure TGittanWinTitleBar.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(tpNone, -1);
end;

procedure TGittanWinTitleBar.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Index: integer;
  Part: TGittanTitlePart;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  Part := PartAt(X, Y, Index);
  case Part of
    tpMenu: OpenMenu(Index);
    tpSearch:
      if (FSearch <> nil) and FSearch.CanFocus then
        FSearch.SetFocus;
    tpAction, tpClear:
      begin
        FPressedPart := Part;
        FPressedIndex := Index;
        Invalidate;
      end;
  end;
end;

{ A pill or the clear button acts on release over itself. }
procedure TGittanWinTitleBar.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Index: integer;
  Part, Pressed: TGittanTitlePart;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  Pressed := FPressedPart;
  FPressedPart := tpNone;
  Invalidate;
  Part := PartAt(X, Y, Index);
  if (Part <> Pressed) or (Index <> FPressedIndex) then
    Exit;
  case Part of
    tpClear:
      begin
        FSearch.Text := '';
        if FSearch.CanFocus then
          FSearch.SetFocus;
      end;
    tpAction:
      if FEnabled[Index] and Assigned(FOnAction) then
        FOnAction(Self, Index);
  end;
end;

{ The submenu under the name at AIndex, owned by the form so that its
  commands go where the menu bar's would. TrackPopupMenuEx returns when
  the menu closes. }
procedure TGittanWinTitleBar.OpenMenu(AIndex: integer);
var
  Form: TCustomForm;
  Menu: HMENU;
  P: TPoint;
begin
  Form := GetParentForm(Self);
  if (Form = nil) or (AIndex < 0) or (AIndex > High(FMenuItems)) then
    Exit;
  Menu := GetMenu(Form.Handle);
  if Menu = 0 then
    Exit;
  P := ClientToScreen(Types.Point(FMenuRects[AIndex].Left, Height));
  FOpenMenu := AIndex;
  Invalidate;
  Update;
  { The menu bar holds the visible items only, as FMenuItems does. }
  TrackPopupMenuEx(GetSubMenu(Menu, AIndex), TPM_LEFTALIGN or TPM_TOPALIGN or
    TPM_LEFTBUTTON, P.X, P.Y, Form.Handle, nil);
  FOpenMenu := -1;
  SetHot(tpNone, -1);
  Invalidate;
end;

function TGittanWinTitleBar.OpenMenuByKey(AKey: char): boolean;
var
  i, p: integer;
  S: string;
begin
  Result := False;
  for i := 0 to High(FMenuItems) do
  begin
    S := FMenuItems[i].Caption;
    p := System.Pos('&', S);
    if (p > 0) and (p < Length(S)) and (UpCase(S[p + 1]) = UpCase(AKey)) then
    begin
      OpenMenu(i);
      Exit(True);
    end;
  end;
end;

procedure TGittanWinTitleBar.Paint;
var
  Split, i, TextY, W: integer;
  R: TRect;
  Ink: TColor;
  Glyph: string;

  procedure FillPill(const AR: TRect; AFill, ABorder: TColor);
  begin
    Canvas.Pen.Color := ABorder;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := AFill;
    Canvas.RoundRect(AR.Left, AR.Top, AR.Right, AR.Bottom, AR.Height, AR.Height);
  end;

  procedure DrawGlyph(const AR: TRect; const AGlyph: string; AColor: TColor);
  begin
    Canvas.Font.Name := FGlyphFont;
    Canvas.Font.Height := -Scale96ToForm(10);
    Canvas.Font.Color := AColor;
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(AR.Left + (AR.Width - Canvas.TextWidth(AGlyph)) div 2,
      AR.Top + (AR.Height - Canvas.TextHeight(AGlyph)) div 2, AGlyph);
    Canvas.Font := Font;
  end;

  procedure DrawButton(APart: TGittanTitlePart; const AR: TRect; const AGlyph: string);
  var
    Back, Fore: TColor;
  begin
    Fore := Ink;
    if (FHotButton = APart) or (FPressedButton = APart) then
    begin
      if APart = tpClose then
      begin
        Back := CloseHot;
        Fore := clWhite;
      end
      else
        Back := FButtonHot;
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := Back;
      Canvas.FillRect(AR);
    end;
    DrawGlyph(AR, AGlyph, Fore);
  end;

begin
  if FSplitControl <> nil then
    Split := FSplitControl.Left + FSplitControl.Width
  else
    Split := 0;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FSide;
  Canvas.FillRect(Types.Rect(0, 0, Split, Height));
  Canvas.Brush.Color := FMain;
  Canvas.FillRect(Types.Rect(Split, 0, Width, Height));
  if FActive then
    Ink := FText
  else
    Ink := FDim;

  Canvas.Font := Font;
  TextY := (Height - Canvas.TextHeight('Xg')) div 2;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := Ink;
  Canvas.TextOut(Scale96ToForm(Pad), TextY, FTitle);
  Canvas.Font.Style := [];

  for i := 0 to High(FMenuRects) do
  begin
    R := FMenuRects[i];
    if (FOpenMenu = i) or ((FHotPart = tpMenu) and (FHotIndex = i)) then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := FButtonHot;
      Canvas.Pen.Color := FButtonHot;
      Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, 8, 8);
    end;
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := Ink;
    Canvas.TextOut(R.Left + Scale96ToForm(MenuPad), TextY,
      StripHotkey(FMenuItems[i].Caption));
  end;

  if not FSearchRect.IsEmpty then
  begin
    FillPill(FSearchRect, FSearchFill, FSearchBorder);
    W := FSearchRect.Height;
    DrawGlyph(Types.Rect(FSearchRect.Left, FSearchRect.Top, FSearchRect.Left + W,
      FSearchRect.Bottom), GlyphSearch, FDim);
    if (FSearch <> nil) and (FSearch.Text <> '') then
      if FHotPart = tpClear then
        DrawGlyph(FClearRect, GlyphClear, Ink)
      else
        DrawGlyph(FClearRect, GlyphClear, FDim);
  end;

  for i := 0 to High(FActions) do
  begin
    R := FActionRects[i];
    FillPill(R, FPillFill, FPillBorder);
    Canvas.Brush.Style := bsClear;
    if not FEnabled[i] then
      Canvas.Font.Color := FDim
    else if ((FPressedPart = tpAction) and (FPressedIndex = i)) or
      ((FPressedPart = tpNone) and (FHotPart = tpAction) and (FHotIndex = i)) then
      Canvas.Font.Color := FHotColor
    else
      Canvas.Font.Color := Ink;
    Canvas.TextOut(R.Left + Scale96ToForm(PillPad), TextY, FActions[i]);
  end;

  DrawButton(tpMinimize, FMinRect, GlyphMinimize);
  if Zoomed(Self) then
    Glyph := GlyphRestore
  else
    Glyph := GlyphMaximize;
  DrawButton(tpMaximize, FMaxRect, Glyph);
  DrawButton(tpClose, FCloseRect, GlyphClose);

  if FBandTotal > 0 then
  begin
    W := BandFillWidth(FBandPos, FBandTotal);
    i := Scale96ToForm(BandHeight);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FBandFill;
    Canvas.FillRect(Types.Rect(0, 0, W, i));
    Canvas.Brush.Color := FBandTrack;
    Canvas.FillRect(Types.Rect(W, 0, Width, i));
  end;
end;

end.
