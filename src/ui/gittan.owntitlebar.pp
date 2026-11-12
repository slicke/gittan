{ A title bar the form draws itself (Windows and GTK 3).

  TGittanOwnTitleBar, aligned at the top of the window, stands in for
  the window's caption, as Firefox's tab bar does: a menu button on the
  left, Back and Forward after it, two chevrons (SetNav; dim while there
  is nowhere to go, OnBack, OnForward), then a tab per open repository and a plus that opens a new tab,
  a banner before the caption buttons, a ribbon hanging from the top
  edge with a notch at its foot and a globe in it (SetForge: there
  while there is a forge, in the accent while the forge view is shown,
  OnForge), and on the
  right the minimize, maximize and close buttons. It lays out
  and paints all of that, tells which part a point is in and runs the
  menu button and the tabs. The empty part is the caption: it moves the
  window, and a double click maximizes it.

  The menu button drops the window's menu as a popup: one item per menu
  of the menu bar, each with its items under it. The popup is built
  anew each time from the menu bar's menu (MenuOf), whose top items'
  OnClick runs first as a menu bar runs it when the menu opens, so the
  checks and the enabled states are those of the moment; each item of
  the popup clicks the item it copies, so the menu's own handlers run
  with their own item as Sender. The menu bar itself stays on the
  window, hidden, for its shortcuts.

  Alt alone or F10 shows TGittanMenuStrip above the bar instead (OpenMenu),
  a menu bar of its own drawn in the bar's colors: the menus' names, each
  dropping its menu copied the same way, Left and Right moving between
  them, also while one is open (a descendant's TrackMenu sees the keys and
  the mouse in the open menu). Alt and a letter shows it with that menu
  open (OpenMenuByKey). It goes again once a menu closes, the focus
  leaves it or the window is deactivated, and gives the focus back to the
  control that had it.

  The tabs: the shown one is a filled, rounded box, a hovered one a
  fainter box, the others their names with a faint line between two of
  them; a tab with news has a dot in the accent before its name; the cross on the shown and the hovered tab, or a middle click,
  closes one (OnTabClose), a press on a tab shows it (OnTabSelect), the
  plus asks for a new one (OnNewTab). The tooltip is the path of the tab
  under the mouse. At the right of the empty part a dim tip (SetTip,
  the command palette's key) is drawn while the tabs and the plus leave
  it room.

  What the window system does differs: how the window is moved,
  maximized, minimized and closed, which glyphs the caption buttons get.
  A descendant per widgetset supplies that through Maximized,
  CaptionButtonClick and DrawGlyph: gittan.wintitlebar on Windows, where
  the window's non-client messages answer the mouse on the empty parts
  and the caption buttons, and gittan.gtktitlebar on GTK 3, where the bar
  takes the mouse itself and asks GTK.

  SetBand draws a progress band along the bar's top edge, as the band
  over the title bar on macOS (gittan.titlebar): the bar paints it, in
  the strip above its tabs.

  TGittanTabBar is the same bar as a row of tabs under the window's own
  title bar and menu bar (Qt, as on Haiku): no menu button and no caption
  buttons, the window system keeping its caption and the menu bar. }
unit gittan.owntitlebar;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Menus, Types, Forms, gittan.avatar;

type
  {** Something done to the tab at AIndex, in the order of SetTabs. }
  TGittanTitleTabEvent = procedure(Sender: TObject; AIndex: integer) of object;

  {** What a point of the bar is: the menu button, a tab, a tab's cross,
    the plus, a caption button, or nothing (the caption, a drag area). }
  TGittanTitlePart = (tpNone, tpMenu, tpBack, tpForward, tpTab, tpTabClose, tpPlus,
    tpForge, tpMinimize, tpMaximize, tpClose);

  {** The glyphs a descendant draws: the caption buttons' (restore for
    maximize while the window is maximized). }
  TGittanTitleGlyph = (tgMinimize, tgMaximize, tgRestore, tgClose);

  TGittanOwnTitleBar = class;

  { TGittanMenuStrip }

  {** The menu bar Alt shows above the title bar: the names of the
    window's menus in a row, each dropping its menu as a popup, gone
    again once a command is chosen or it loses the focus. }
  TGittanMenuStrip = class(TCustomControl)
  private
    FBar: TGittanOwnTitleBar;
    { The visible top items of the menu bar, and where their names are. }
    FItems: array of TMenuItem;
    FRects: array of TRect;
    { The name under the mouse or chosen with the keys, the one whose
      menu is open, and the one to open once the open one has closed
      (Left, Right, or the mouse on another name). }
    FHot, FOpen, FStepTo: integer;
    { The menu to open next is on its way (OpenAsync): the strip stays. }
    FPending: boolean;
    { Kept shown (View > Menu Bar): it then gives the focus back rather
      than going, and has the caption buttons. }
    FPinned: boolean;
    { The caption buttons under the mouse and pressed, where the strip
      sees the mouse on them itself (GTK); a press on the empty part
      that a drag past a few pixels turns into a move of the window. }
    FButtonHot, FButtonPressed: TGittanTitlePart;
    FDragArmed: boolean;
    FPressPoint: TPoint;
    { Shown from the keyboard: the names underline their accelerators. }
    FKeys: boolean;
    FPopup: TPopupMenu;
    { The control that had the focus before, which gets it back. }
    FPrevFocus: TWinControl;
    procedure Collect;
    function IndexAt(X, Y: integer): integer;
    function IndexOfKey(AKey: char): integer;
    procedure SetHot(AIndex: integer);
    procedure SetPrevFocus(AControl: TWinControl);
    procedure SetPinned(AValue: boolean);
    procedure ShowStrip;
    procedure PopupItemClick(Sender: TObject);
    procedure PopupClose(Sender: TObject);
    procedure OpenAsync(Data: PtrInt);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure CreateWnd; override;
    procedure DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
      const AXProportion, AYProportion: double); override;
    procedure Paint; override;
    procedure KeyDown(var Key: word; Shift: TShiftState); override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    procedure DoExit; override;
    procedure ExitAsync(Data: PtrInt);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** Shows the strip over the title bar with the focus, the name at
      AIndex marked; AKeys underlines the accelerators. }
    procedure Activate(AIndex: integer; AKeys: boolean);
    {** Drops the menu of the name at AIndex under it. }
    procedure OpenItem(AIndex: integer);
    {** Hides the strip; ARestore gives the focus back to the control
      that had it. }
    procedure Dismiss(ARestore: boolean);
    {** While a menu is open: opens the next menu (ADelta 1) or the one
      before (-1) once it has closed. True when the caller is to close
      the open one. }
    function StepMenu(ADelta: integer): boolean;
    {** While a menu is open: the mouse at AScreen over another name opens
      that one once the open one has closed. True when the caller is to
      close the open one. }
    function HoverAt(const AScreen: TPoint): boolean;
    {** The open menu has closed: the next opens when one was asked for
      (StepMenu, HoverAt), else the strip goes. The popup's OnClose calls
      it; a descendant that pops the menu up itself calls it from the
      menu's own signal. Once per menu: a second call does nothing. }
    procedure MenuClosed;
    {** Whether a menu of the strip is open, or the next on its way. }
    function MenuOpen: boolean;
    {** The index of the name at X, Y of the strip, -1 for none. }
    function NameAt(X, Y: integer): integer;
    {** The caption button at X, Y of the strip, which has them while it
      is kept (Pinned); tpNone for none. }
    function CaptionPart(X, Y: integer): TGittanTitlePart;
    {** Where the caption button APart is, empty while the strip has
      none. }
    function ButtonRect(APart: TGittanTitlePart): TRect;
    {** Kept shown over the title bar (View > Menu Bar), rather than
      shown by Alt and gone once done with. }
    property Pinned: boolean read FPinned write SetPinned;
  end;

  { TGittanOwnTitleBar }

  TGittanOwnTitleBar = class(TCustomControl)
  private
    FSplitControl: TControl;
    FCaptions, FHints: array of string;
    FMarks: array of boolean;
    { The tabs an extension added (the forge view's): a puzzle piece
      before the name. }
    FExts: array of boolean;
    FTabActive: integer;
    { The tabs are a view's own (the forge view's): no cross, no plus. }
    FFixed: boolean;
    FMenuRect, FBackRect, FForwardRect, FPlusRect, FForgeRect, FMinRect, FMaxRect,
    FCloseRect: TRect;
    { Back and Forward: whether each can be gone to, and their hints. }
    FCanBack, FCanForward: boolean;
    FBackHint, FForwardHint: string;
    { The globe: whether it is there, whether the forge view is shown,
      its hint, and the user's picture, drawn in the globe's place when
      the forge has given one. }
    FForgeVisible, FForgeShown: boolean;
    FForgeHint: string;
    { What waits for the user in the forge view, counted in a badge. }
    FForgeCount: integer;
    FAvatar: TGittanAvatar;
    FHotPart, FPressedPart, FHotButton, FPressedButton: TGittanTitlePart;
    FHotIndex, FPressedIndex: integer;
    FMenuOpen: boolean;
    FPopup: TPopupMenu;
    { The menu bar Alt shows, made the first time. }
    FStrip: TGittanMenuStrip;
    FActive: boolean;
    FSide, FMain, FText, FDim, FTabFill, FTabBorder, FButtonHot, FMark: TColor;
    FBandPos, FBandTotal: integer;
    FBandTrack, FBandFill: TColor;
    FTitle, FTip: string;
    FOnTabSelect, FOnTabClose: TGittanTitleTabEvent;
    FOnNewTab, FOnForge, FOnForgeMenu, FOnBack, FOnForward: TNotifyEvent;
    procedure SetActive(AValue: boolean);
    function BandFillWidth(APos, ATotal: integer): integer;
    function MenuOf(AForm: TCustomForm): TMainMenu;
    function TabsLimit: integer;
    function TabsStart: integer;
    function NavEnabled(APart: TGittanTitlePart): boolean;
    function TabWidth: integer;
    function TabsShown: integer;
    function TabRect(AIndex: integer): TRect;
    function CrossRect(const ATab: TRect): TRect;
    function Strip: TGittanMenuStrip;
    function GetPinnedMenu: boolean;
    procedure SetPinnedMenu(AValue: boolean);
    procedure PopupItemClick(Sender: TObject);
    procedure PopupClose(Sender: TObject);
    procedure DropMenu(AOnly: TMenuItem);
  protected
    { A row of tabs only (TGittanTabBar): no menu button, no caption
      buttons. }
    FTabsOnly: boolean;
    procedure DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
      const AXProportion, AYProportion: double); override;
    {** The part at a point of the bar, with the index of the tab. }
    function PartAt(X, Y: integer; out AIndex: integer): TGittanTitlePart;
    procedure SetHot(APart: TGittanTitlePart; AIndex: integer);
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    {** Whether the window is maximized: the maximize button then shows
      the restore glyph. }
    function Maximized: boolean; virtual; abstract;
    {** Draws AGlyph centered in AR on ACanvas (the bar's, or the menu
      strip's) in AColor, and leaves the canvas's font as the bar's. }
    procedure DrawGlyph(ACanvas: TCanvas; AGlyph: TGittanTitleGlyph; const AR: TRect;
      AColor: TColor); virtual; abstract;
    {** A click released on a caption button the bar itself saw the mouse
      on (on Windows the form sees it instead, and this is not called). }
    procedure CaptionButtonClick(APart: TGittanTitlePart); virtual;
    {** Drops APopup, a menu of AStrip, under AName, the name's place in
      the strip; a descendant lets Left, Right and the mouse on the
      strip's names move to another menu while it is open (StepMenu,
      HoverAt). It may return before the menu has closed (GTK) or after
      (Windows). }
    procedure TrackMenu(AStrip: TGittanMenuStrip; APopup: TPopupMenu;
      const AName: TRect); virtual;
    {** What a press on the menu strip's empty part does where the strip
      sees it itself (GTK): moves the window (a drag), maximizes or
      restores it (a double click), drops the window menu (a right
      click). Nothing here: on Windows the form answers it as caption. }
    procedure WindowMove; virtual;
    procedure WindowZoom; virtual;
    procedure WindowMenu; virtual;
    {** The menu strip has a new handle: when it is made, and again when
      the LCL makes its window anew (a DPI change). Windows lets the
      form answer the mouse on its empty part and its buttons. }
    procedure StripMade(AStrip: TGittanMenuStrip); virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** The caption button under the mouse or pressed, tpNone for none;
      set by a form that sees the mouse there itself (Windows). }
    procedure SetButtonState(AHot, APressed: TGittanTitlePart);
    {** Places the menu button, the tabs, the plus and the caption
      buttons; again after the tabs changed. }
    procedure Layout;
    {** Shows the menu bar over the bar with its first name marked (Alt
      alone, F10), or hides it again while it is shown. }
    procedure OpenMenu;
    {** Shows the menu bar and drops the menu whose name has the
      accelerator AKey; False when none has it. }
    function OpenMenuByKey(AKey: char): boolean;
    {** Whether the menu bar has the keys (Alt showed it or gave it the
      focus, or a menu of it is open): the window leaves them to it. }
    function MenuActive: boolean;
    {** The menu bar kept shown over the bar (View > Menu Bar); Alt then
      gives it the focus. }
    property PinnedMenu: boolean read GetPinnedMenu write SetPinnedMenu;
    {** The menu bar Alt shows, nil before it was first needed. }
    property MenuStrip: TGittanMenuStrip read FStrip;
    {** Repaints the menu strip too, which draws the caption buttons while
      it is kept, with the bar's state. }
    procedure Invalidate; override;
    {** The tabs, left to right: ACaptions are their names, AHints their
      tooltips (the paths), AMarks those with news (a dot before the
      name), AActive the one shown; AFixed when they are a view's own,
      which cannot be closed or added to: no cross and no plus. }
    procedure SetTabs(const ACaptions, AHints: array of string;
      const AMarks, AExts: array of boolean; AActive: integer; AFixed: boolean = False);
    {** The banner before the caption buttons: shown while AVisible
      (there is a forge), in the accent while AShown (the forge view is
      shown), AHint its hint (the forge's name, with the login when it
      is known); APicture the bytes of the user's picture, drawn as a
      disc in the globe's place, '' for the globe; ACount what waits
      for the user there (pull requests to review), counted in a badge
      at the globe's corner while the view is not shown, 0 for none. }
    procedure SetForge(AVisible, AShown: boolean; const AHint: string;
      const APicture: string = ''; ACount: integer = 0);
    {** The chevrons: whether there is somewhere to go back (ABack) and
      forward (AForward) to, a dim chevron taking no click; ABackHint
      and AForwardHint their hints. }
    procedure SetNav(ABack, AForward: boolean; const ABackHint, AForwardHint: string);
    {** The dim tip at the right of the empty part, left out where the
      tabs and the plus reach it and while the tabs are fixed. }
    procedure SetTip(const ATip: string);
    {** The bar's colors: the shade over the sidebar and the background
      over the rest, the text and the dim text, the shown tab's fill and
      border, a caption button (or a hovered tab) under the mouse, and
      the dot of a tab with news. }
    procedure SetColors(ASide, AMain, AText, ADim, ATabFill, ATabBorder,
      AButtonHot, AMark: TColor);
    {** Shows the band along the top edge, APos of ATotal filled, in the
      colors ATrack and AFill; ATotal 0 hides it. }
    procedure SetBand(APos, ATotal: integer; ATrack, AFill: TColor);
    {** The control whose right edge ends the sidebar's shade. }
    property SplitControl: TControl read FSplitControl write FSplitControl;
    {** The application's name, the menu button's tooltip. }
    property Title: string read FTitle write FTitle;
    {** Whether the window is the active one; the text dims when not. }
    property Active: boolean read FActive write SetActive;
    {** The caption button SetButtonState last gave as pressed. }
    property PressedButton: TGittanTitlePart read FPressedButton;
    {** The dim text color, for a descendant's glyphs. }
    property DimColor: TColor read FDim;
    property OnTabSelect: TGittanTitleTabEvent read FOnTabSelect write FOnTabSelect;
    property OnTabClose: TGittanTitleTabEvent read FOnTabClose write FOnTabClose;
    property OnNewTab: TNotifyEvent read FOnNewTab write FOnNewTab;
    {** The banner: the forge view, or back from it. }
    property OnForge: TNotifyEvent read FOnForge write FOnForge;
    {** A right click on the globe: the menu of the forge's accounts, at
      the mouse. }
    property OnForgeMenu: TNotifyEvent read FOnForgeMenu write FOnForgeMenu;
    {** The chevrons: back, forward. }
    property OnBack: TNotifyEvent read FOnBack write FOnBack;
    property OnForward: TNotifyEvent read FOnForward write FOnForward;
  end;

  {** The bar as a row of tabs under the window's own title bar and menu
    bar, where the window system keeps them (Qt). }
  TGittanTabBar = class(TGittanOwnTitleBar)
  protected
    function Maximized: boolean; override;
    procedure DrawGlyph(ACanvas: TCanvas; AGlyph: TGittanTitleGlyph; const AR: TRect;
      AColor: TColor); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

const
  {** The bar's height at 96 dpi. }
  TitleBarHeight = 40;

implementation

uses
  Math, LCLIntf, LCLType, LazUTF8, gittan.statusbar, gittan.theme, gittan.puzzle;

const
  Pad = 8;
  Gap = 6;
  MenuButtonWidth = 36;
  TabHeight = 30;
  MaxTabWidth = 220;
  MinTabWidth = 64;
  TabGap = 3;
  PlusSize = 26;
  { A chevron's button, square, and the gap between the two. }
  NavSize = 26;
  NavGap = 2;
  { The banner: its width, the room it leaves under it, the depth of
    the notch at its foot, and the globe in it. }
  ForgeWidth = 30;
  ForgeFoot = 4;
  ForgeNotch = 7;
  ForgeIconSize = 20;
  { The badge that counts what waits in the forge view: its height (its
    width too, up to nine) and its digits' font size. }
  ForgeBadgeSize = 13;
  ForgeBadgeFont = 7;
  CrossSize = 18;
  ButtonWidth = 46;
  BandHeight = 3;
  { The least the band's fill is wide: a rounded window corner (Windows
    11, GNOME) hides its first pixels. }
  MinBandFill = 16;
  CloseHot = $1C2BC4; { RGB(196, 43, 28) }
  { The menu bar: its height and the room either side of a name. }
  StripHeight = 28;
  StripItemPad = 9;
  { How far a press on the strip's empty part moves before the window
    follows it (GTK), as GTK's drag threshold. }
  StripDragThreshold = 8;

{ TGittanOwnTitleBar }

constructor TGittanOwnTitleBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAvatar := TGittanAvatar.Create;
  ControlStyle := ControlStyle + [csOpaque];
  { Not Scale96ToForm: the bar has no form yet. }
  Height := Scale96ToScreen(TitleBarHeight);
  FHotIndex := -1;
  FPressedIndex := -1;
  FTabActive := -1;
  FActive := True;
  ShowHint := True;
  FPopup := TPopupMenu.Create(Self);
  FPopup.OnClose := @PopupClose;
  SetColors(clBtnFace, clWindow, clWindowText, clGrayText, clBtnFace,
    clBtnShadow, clBtnFace, clHighlight);
end;

procedure TGittanOwnTitleBar.SetActive(AValue: boolean);
begin
  if FActive = AValue then
    Exit;
  FActive := AValue;
  { The menu bar goes with the window's activation, but not for its own
    menu, which may take it on some window systems. }
  if not FActive and (FStrip <> nil) and not FStrip.MenuOpen then
    FStrip.Dismiss(False);
  Invalidate;
end;

procedure TGittanOwnTitleBar.SetColors(ASide, AMain, AText, ADim, ATabFill,
  ATabBorder, AButtonHot, AMark: TColor);
begin
  FMark := AMark;
  FSide := ASide;
  FMain := AMain;
  FText := AText;
  FDim := ADim;
  FTabFill := ATabFill;
  FTabBorder := ATabBorder;
  FButtonHot := AButtonHot;
  Color := AMain;
  Invalidate;
end;

procedure TGittanOwnTitleBar.SetTabs(const ACaptions, AHints: array of string;
  const AMarks, AExts: array of boolean; AActive: integer; AFixed: boolean);
var
  i: integer;
begin
  FFixed := AFixed;
  SetLength(FCaptions, Length(ACaptions));
  SetLength(FHints, Length(ACaptions));
  SetLength(FMarks, Length(ACaptions));
  SetLength(FExts, Length(ACaptions));
  for i := 0 to High(ACaptions) do
  begin
    FCaptions[i] := ACaptions[i];
    FMarks[i] := (i <= High(AMarks)) and AMarks[i];
    FExts[i] := (i <= High(AExts)) and AExts[i];
    if i <= High(AHints) then
      FHints[i] := AHints[i]
    else
      FHints[i] := '';
  end;
  FTabActive := AActive;
  if FHotIndex > High(FCaptions) then
    SetHot(tpNone, -1);
  Layout;
  Invalidate;
end;

function TGittanOwnTitleBar.BandFillWidth(APos, ATotal: integer): integer;
begin
  if ATotal <= 0 then
    Result := 0
  else
    Result := Max(Scale96ToForm(MinBandFill), Width * Min(APos, ATotal) div ATotal);
end;

{ Called for every file indexed: only the band is repainted, and only
  when its fill grows by a pixel or its colors change. }
procedure TGittanOwnTitleBar.SetBand(APos, ATotal: integer; ATrack, AFill: TColor);
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

procedure TGittanOwnTitleBar.SetButtonState(AHot, APressed: TGittanTitlePart);
begin
  if (FHotButton = AHot) and (FPressedButton = APressed) then
    Exit;
  FHotButton := AHot;
  FPressedButton := APressed;
  Invalidate;
end;

function TGittanOwnTitleBar.MenuOf(AForm: TCustomForm): TMainMenu;
begin
  Result := nil;
  if AForm <> nil then
    Result := AForm.Menu;
end;

{ Where the tabs and the plus end: the globe when it is there, else the
  minimize button. }
procedure TGittanOwnTitleBar.SetTip(const ATip: string);
begin
  if ATip = FTip then
    Exit;
  FTip := ATip;
  Invalidate;
end;

function TGittanOwnTitleBar.TabsLimit: integer;
begin
  if FForgeVisible then
    Result := FForgeRect.Left
  else
    Result := FMinRect.Left;
end;

{ Where the first tab starts: after the chevrons. }
function TGittanOwnTitleBar.TabsStart: integer;
begin
  Result := FForwardRect.Right + Scale96ToForm(Gap);
end;

function TGittanOwnTitleBar.NavEnabled(APart: TGittanTitlePart): boolean;
begin
  Result := ((APart = tpBack) and FCanBack) or ((APart = tpForward) and FCanForward);
end;

{ The tabs share the room between the chevrons and the plus, which
  follows the last of them (when they are not fixed), evenly, within
  MinTabWidth and MaxTabWidth. }
function TGittanOwnTitleBar.TabWidth: integer;
var
  Room: integer;
begin
  Room := TabsLimit - Scale96ToForm(Gap) - TabsStart;
  if not FFixed then
    Dec(Room, Scale96ToForm(PlusSize + Gap));
  if Length(FCaptions) = 0 then
    Exit(Scale96ToForm(MaxTabWidth));
  Result := Max(Scale96ToForm(MinTabWidth), Min(Scale96ToForm(MaxTabWidth),
    Room div Length(FCaptions)));
end;

{ How many tabs fit before the limit, with room for the plus after them
  (when they are not fixed); those after are not drawn, so the plus
  stays clear of the caption buttons in a narrow window. }
function TGittanOwnTitleBar.TabsShown: integer;
var
  Limit: integer;
begin
  Limit := TabsLimit;
  if not FFixed then
    Dec(Limit, Scale96ToForm(PlusSize + Gap));
  Result := 0;
  while (Result < Length(FCaptions)) and (TabRect(Result).Right <= Limit) do
    Inc(Result);
end;

function TGittanOwnTitleBar.TabRect(AIndex: integer): TRect;
var
  W, X, H: integer;
begin
  W := TabWidth;
  X := TabsStart + AIndex * W;
  H := Scale96ToForm(TabHeight);
  Result := Types.Rect(X, (Height - H) div 2 + 1, X + W - Scale96ToForm(TabGap),
    (Height + H) div 2 + 1);
end;

function TGittanOwnTitleBar.CrossRect(const ATab: TRect): TRect;
var
  S: integer;
begin
  S := Scale96ToForm(CrossSize);
  Result := Types.Rect(ATab.Right - S - Scale96ToForm(6), ATab.Top + (ATab.Height - S) div 2,
    ATab.Right - Scale96ToForm(6), ATab.Top + (ATab.Height - S) div 2 + S);
end;

{ From the right the caption buttons; from the left the menu button,
  the chevrons, the tabs and the plus after them. }
procedure TGittanOwnTitleBar.Layout;
var
  W, H, X, S: integer;
begin
  { Setting the height in Create resizes the bar before it has a form to
    scale by. }
  if GetParentForm(Self) = nil then
    Exit;
  H := Height;
  W := Scale96ToForm(ButtonWidth);
  { A row of tabs only: the caption buttons and the menu button take no
    room, their rects empty at the edges; the same for the caption
    buttons while the menu strip is kept, which has them. }
  if FTabsOnly or PinnedMenu then
    W := 0;
  FCloseRect := Types.Rect(Width - W, 0, Width, H);
  FMaxRect := Types.Rect(FCloseRect.Left - W, 0, FCloseRect.Left, H);
  FMinRect := Types.Rect(FMaxRect.Left - W, 0, FMaxRect.Left, H);
  S := Scale96ToForm(ForgeWidth);
  X := FMinRect.Left - Scale96ToForm(Gap) - S;
  if FForgeVisible then
    FForgeRect := Types.Rect(X, 0, X + S, H - Scale96ToForm(ForgeFoot))
  else
    FForgeRect := Types.Rect(0, 0, 0, 0);
  S := Scale96ToForm(PlusSize);
  { No menu button beside a menu bar: Qt's, or the strip kept shown. }
  if FTabsOnly or PinnedMenu then
    FMenuRect := Types.Rect(Scale96ToForm(Pad - Gap), (H - S) div 2,
      Scale96ToForm(Pad - Gap), (H + S) div 2)
  else
    FMenuRect := Types.Rect(Scale96ToForm(Pad), (H - S) div 2,
      Scale96ToForm(Pad + MenuButtonWidth), (H + S) div 2);
  X := FMenuRect.Right + Scale96ToForm(Gap);
  W := Scale96ToForm(NavSize);
  FBackRect := Types.Rect(X, (H - W) div 2 + 1, X + W, (H + W) div 2 + 1);
  X := FBackRect.Right + Scale96ToForm(NavGap);
  FForwardRect := Types.Rect(X, FBackRect.Top, X + W, FBackRect.Bottom);
  X := TabsStart + TabsShown * TabWidth;
  if FFixed or (X + S > TabsLimit) then
    FPlusRect := Types.Rect(0, 0, 0, 0)
  else
    FPlusRect := Types.Rect(X, (H - S) div 2 + 1, X + S, (H + S) div 2 + 1);
end;

procedure TGittanOwnTitleBar.Resize;
begin
  inherited Resize;
  Layout;
end;

function TGittanOwnTitleBar.PartAt(X, Y: integer; out AIndex: integer): TGittanTitlePart;
var
  i: integer;
  P: TPoint;
  R: TRect;
begin
  AIndex := -1;
  P := Types.Point(X, Y);
  if FCloseRect.Contains(P) then
    Exit(tpClose);
  if FMaxRect.Contains(P) then
    Exit(tpMaximize);
  if FMinRect.Contains(P) then
    Exit(tpMinimize);
  if FMenuRect.Contains(P) then
    Exit(tpMenu);
  if FBackRect.Contains(P) then
    Exit(tpBack);
  if FForwardRect.Contains(P) then
    Exit(tpForward);
  if FForgeVisible and FForgeRect.Contains(P) then
    Exit(tpForge);
  if FPlusRect.Contains(P) then
    Exit(tpPlus);
  for i := 0 to TabsShown - 1 do
  begin
    R := TabRect(i);
    if R.Contains(P) then
    begin
      AIndex := i;
      if not FFixed and CrossRect(R).Contains(P) then
        Exit(tpTabClose);
      Exit(tpTab);
    end;
  end;
  Result := tpNone;
end;

procedure TGittanOwnTitleBar.SetHot(APart: TGittanTitlePart; AIndex: integer);
begin
  if (FHotPart = APart) and (FHotIndex = AIndex) then
    Exit;
  if (AIndex >= 0) and (AIndex <> FHotIndex) and (AIndex <= High(FHints)) then
  begin
    Hint := FHints[AIndex];
    Application.CancelHint;
  end
  else if APart = tpMenu then
    Hint := FTitle
  else if APart = tpBack then
    Hint := FBackHint
  else if APart = tpForward then
    Hint := FForwardHint
  else if APart = tpForge then
    Hint := FForgeHint
  else if AIndex < 0 then
    Hint := '';
  FHotPart := APart;
  FHotIndex := AIndex;
  Invalidate;
end;

procedure TGittanOwnTitleBar.MouseMove(Shift: TShiftState; X, Y: integer);
var
  Index: integer;
  Part: TGittanTitlePart;
begin
  inherited MouseMove(Shift, X, Y);
  Part := PartAt(X, Y, Index);
  SetHot(Part, Index);
end;

{ A press is forgotten with the mouse gone: without capture (GTK) the
  release outside is never seen. }
procedure TGittanOwnTitleBar.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(tpNone, -1);
  if FPressedPart <> tpNone then
  begin
    FPressedPart := tpNone;
    FPressedIndex := -1;
    Invalidate;
  end;
end;

{ A tab is shown as it is pressed; the menu button drops the menu at
  once; the cross, the plus and the caption buttons act on release. }
procedure TGittanOwnTitleBar.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Index: integer;
  Part: TGittanTitlePart;
begin
  inherited MouseDown(Button, Shift, X, Y);
  Part := PartAt(X, Y, Index);
  if Button = mbMiddle then
  begin
    FPressedPart := Part;
    FPressedIndex := Index;
    Exit;
  end;
  if Button <> mbLeft then
    Exit;
  case Part of
    tpMenu: DropMenu(nil);
    tpTab:
      if Assigned(FOnTabSelect) then
        FOnTabSelect(Self, Index);
    tpBack, tpForward:
      if NavEnabled(Part) then
      begin
        FPressedPart := Part;
        FPressedIndex := Index;
        Invalidate;
      end;
    tpTabClose, tpPlus, tpForge, tpMinimize, tpMaximize, tpClose:
      begin
        FPressedPart := Part;
        FPressedIndex := Index;
        Invalidate;
      end;
  end;
end;

procedure TGittanOwnTitleBar.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Index: integer;
  Part, Pressed: TGittanTitlePart;
begin
  inherited MouseUp(Button, Shift, X, Y);
  Pressed := FPressedPart;
  FPressedPart := tpNone;
  Part := PartAt(X, Y, Index);
  { A middle click on a tab closes it. }
  if Button = mbMiddle then
  begin
    if not FFixed and (Part in [tpTab, tpTabClose]) and (Pressed in [tpTab, tpTabClose]) and
      (Index = FPressedIndex) and Assigned(FOnTabClose) then
      FOnTabClose(Self, Index);
    Exit;
  end;
  if (Button = mbRight) and (Part = tpForge) and Assigned(FOnForgeMenu) then
    FOnForgeMenu(Self);
  if Button <> mbLeft then
    Exit;
  Invalidate;
  if (Part <> Pressed) or (Index <> FPressedIndex) then
    Exit;
  case Part of
    tpBack:
      if FCanBack and Assigned(FOnBack) then
        FOnBack(Self);
    tpForward:
      if FCanForward and Assigned(FOnForward) then
        FOnForward(Self);
    tpTabClose:
      if Assigned(FOnTabClose) then
        FOnTabClose(Self, Index);
    tpPlus:
      if Assigned(FOnNewTab) then
        FOnNewTab(Self);
    tpForge:
      if Assigned(FOnForge) then
        FOnForge(Self);
    tpMinimize, tpMaximize, tpClose:
      CaptionButtonClick(Part);
  end;
end;

destructor TGittanOwnTitleBar.Destroy;
begin
  FAvatar.Free;
  inherited Destroy;
end;

procedure TGittanOwnTitleBar.SetForge(AVisible, AShown: boolean; const AHint: string;
  const APicture: string; ACount: integer);
begin
  FForgeVisible := AVisible;
  FForgeShown := AShown;
  FForgeHint := AHint;
  FForgeCount := ACount;
  { Under the pointer, the hint follows at once. }
  if FHotPart = tpForge then
    Hint := FForgeHint;
  FAvatar.SetData(APicture);
  Layout;
  Invalidate;
end;

procedure TGittanOwnTitleBar.SetNav(ABack, AForward: boolean;
  const ABackHint, AForwardHint: string);
begin
  if (ABack = FCanBack) and (AForward = FCanForward) and (ABackHint = FBackHint) and
    (AForwardHint = FForwardHint) then
    Exit;
  FCanBack := ABack;
  FCanForward := AForward;
  FBackHint := ABackHint;
  FForwardHint := AForwardHint;
  if FHotPart = tpBack then
    Hint := FBackHint
  else if FHotPart = tpForward then
    Hint := FForwardHint;
  Invalidate;
end;

procedure TGittanOwnTitleBar.CaptionButtonClick(APart: TGittanTitlePart);
begin
end;

{ ASource's items as items of ATarget, owned by AOwner, that run AClick:
  captions, keys, checks and enabled states as they are now, and
  submenus copied in turn. A separator stays one. Each item's Tag is
  the item it copies. }
procedure CopyMenuItems(ASource, ATarget: TMenuItem; AOwner: TComponent;
  AClick: TNotifyEvent);
var
  i: integer;
  Src, Item: TMenuItem;
begin
  for i := 0 to ASource.Count - 1 do
  begin
    Src := ASource.Items[i];
    if not Src.Visible then
      Continue;
    Item := TMenuItem.Create(AOwner);
    Item.Caption := Src.Caption;
    if not Src.IsLine then
    begin
      Item.ShortCut := Src.ShortCut;
      Item.Enabled := Src.Enabled;
      Item.Checked := Src.Checked;
      Item.RadioItem := Src.RadioItem;
      Item.GroupIndex := Src.GroupIndex;
      Item.Tag := PtrInt(Src);
      if Src.Count > 0 then
        CopyMenuItems(Src, Item, AOwner, AClick)
      else
        Item.OnClick := AClick;
    end;
    ATarget.Add(Item);
  end;
end;

procedure TGittanOwnTitleBar.PopupItemClick(Sender: TObject);
begin
  TMenuItem(TMenuItem(Sender).Tag).Click;
end;

procedure TGittanOwnTitleBar.PopupClose(Sender: TObject);
begin
  FMenuOpen := False;
  SetHot(tpNone, -1);
  Invalidate;
end;

{ The popup under the menu button: every menu of the menu bar as a
  submenu, or AOnly's items alone. A top item's OnClick runs first, as
  the menu bar runs it when the menu opens (the Branch menu names the
  current branch in its items, the Tools menu checks the CLI command). }
procedure TGittanOwnTitleBar.DropMenu(AOnly: TMenuItem);
var
  Menu: TMainMenu;
  Item: TMenuItem;
  i: integer;
  P: TPoint;
begin
  Menu := MenuOf(GetParentForm(Self));
  if Menu = nil then
    Exit;
  FPopup.Items.Clear;
  if AOnly <> nil then
  begin
    if Assigned(AOnly.OnClick) then
      AOnly.Click;
    CopyMenuItems(AOnly, FPopup.Items, FPopup, @PopupItemClick);
  end
  else
    for i := 0 to Menu.Items.Count - 1 do
    begin
      if not Menu.Items[i].Visible then
        Continue;
      if Assigned(Menu.Items[i].OnClick) then
        Menu.Items[i].Click;
      Item := TMenuItem.Create(FPopup);
      Item.Caption := Menu.Items[i].Caption;
      CopyMenuItems(Menu.Items[i], Item, FPopup, @PopupItemClick);
      FPopup.Items.Add(Item);
    end;
  FMenuOpen := True;
  Invalidate;
  Update;
  P := ClientToScreen(Types.Point(FMenuRect.Left, Height));
  FPopup.PopUp(P.X, P.Y);
end;

function TGittanOwnTitleBar.Strip: TGittanMenuStrip;
begin
  if FStrip = nil then
  begin
    FStrip := TGittanMenuStrip.Create(Self);
    FStrip.Visible := False;
    FStrip.Align := alTop;
    FStrip.Parent := Parent;
    { StripMade comes from its CreateWnd, when it gets its window. }
  end;
  Result := FStrip;
end;

procedure TGittanOwnTitleBar.TrackMenu(AStrip: TGittanMenuStrip; APopup: TPopupMenu;
  const AName: TRect);
var
  P: TPoint;
begin
  P := AStrip.ClientToScreen(Types.Point(AName.Left, AStrip.Height));
  APopup.PopUp(P.X, P.Y);
end;

function TGittanOwnTitleBar.MenuActive: boolean;
begin
  Result := (FStrip <> nil) and FStrip.Visible and (FStrip.Focused or FStrip.MenuOpen);
end;

procedure TGittanOwnTitleBar.Invalidate;
begin
  inherited Invalidate;
  if (FStrip <> nil) and FStrip.Visible then
    FStrip.Invalidate;
end;

procedure TGittanOwnTitleBar.WindowMove;
begin
end;

procedure TGittanOwnTitleBar.StripMade(AStrip: TGittanMenuStrip);
begin
end;

procedure TGittanOwnTitleBar.WindowZoom;
begin
end;

procedure TGittanOwnTitleBar.WindowMenu;
begin
end;

function TGittanOwnTitleBar.GetPinnedMenu: boolean;
begin
  Result := (FStrip <> nil) and FStrip.Pinned;
end;

procedure TGittanOwnTitleBar.SetPinnedMenu(AValue: boolean);
begin
  if FTabsOnly or (Parent = nil) or (not AValue and (FStrip = nil)) then
    Exit;
  Strip.Pinned := AValue;
  { The menu button goes while the strip is kept, the tabs moving left
    into its room. }
  if FMenuOpen then
    FPopup.Close;
  SetHot(tpNone, -1);
  Layout;
  Invalidate;
end;

procedure TGittanOwnTitleBar.OpenMenu;
begin
  if FTabsOnly or (Parent = nil) then
    Exit;
  if MenuActive then
    FStrip.Dismiss(True)
  else
    Strip.Activate(0, True);
end;

function TGittanOwnTitleBar.OpenMenuByKey(AKey: char): boolean;
var
  Index: integer;
begin
  Result := False;
  if FTabsOnly or (Parent = nil) then
    Exit;
  { A strip not shown yet has no handle, and Collect measures the names
    on its canvas: without one it gathers nothing and the key is lost. }
  Strip.HandleNeeded;
  FStrip.Collect;
  Index := FStrip.IndexOfKey(AKey);
  if Index < 0 then
    Exit;
  FStrip.Activate(Index, True);
  FStrip.OpenItem(Index);
  Result := True;
end;

procedure TGittanOwnTitleBar.Paint;
var
  Split, i, TextY, Mid, W, L: integer;
  R, C: TRect;
  Ink, GlobeInk: TColor;
  Glyph: TGittanTitleGlyph;
  Shown, Hover: boolean;
  Badge: string;

  procedure DrawButton(APart: TGittanTitlePart; const AR: TRect; AGlyph: TGittanTitleGlyph);
  var
    Back, Fore: TColor;
  begin
    Fore := Ink;
    if (FHotButton = APart) or (FPressedButton = APart) or (FHotPart = APart) or
      (FPressedPart = APart) then
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
    DrawGlyph(Canvas, AGlyph, AR, Fore);
  end;

  procedure Line(X1, Y1, X2, Y2: integer; AColor: TColor);
  begin
    Canvas.Pen.Color := AColor;
    Canvas.Pen.Width := Max(1, Scale96ToForm(1));
    Canvas.Line(X1, Y1, X2, Y2);
  end;

  procedure HotBox(const AR: TRect; AColor: TColor);
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := AColor;
    Canvas.Pen.Color := AColor;
    Canvas.RoundRect(AR.Left, AR.Top, AR.Right, AR.Bottom, Scale96ToForm(8),
      Scale96ToForm(8));
  end;

  procedure DrawChevron(APart: TGittanTitlePart; const AR: TRect);
  var
    CX, CY, D, Dir: integer;
    Chevron: TColor;
  begin
    if NavEnabled(APart) and ((FHotPart = APart) or (FPressedPart = APart)) then
      HotBox(AR, FButtonHot);
    if NavEnabled(APart) then
      Chevron := Ink
    else
      Chevron := MixColor(FMain, FDim, 0.45);
    CX := (AR.Left + AR.Right) div 2;
    CY := (AR.Top + AR.Bottom) div 2;
    D := Scale96ToForm(4);
    if APart = tpBack then
      Dir := -1
    else
      Dir := 1;
    Canvas.Pen.Color := Chevron;
    Canvas.Pen.Width := Max(1, Scale96ToForm(2) * 3 div 4);
    Canvas.Line(CX - Dir * D div 2, CY - 2 * D, CX + Dir * D, CY);
    Canvas.Line(CX + Dir * D, CY, CX - Dir * D div 2, CY + 2 * D);
    Canvas.Pen.Width := 1;
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
  TextY := (Height - Canvas.TextHeight('Xg')) div 2 + 1;

  { The menu button: three lines. }
  if not FTabsOnly and not PinnedMenu then
  begin
    if FMenuOpen or (FHotPart = tpMenu) then
      HotBox(FMenuRect, FButtonHot);
    Mid := (FMenuRect.Left + FMenuRect.Right) div 2;
    W := Scale96ToForm(7);
    for i := -1 to 1 do
    begin
      L := (FMenuRect.Top + FMenuRect.Bottom) div 2 + i * Scale96ToForm(5);
      Line(Mid - W, L, Mid + W, L, Ink);
    end;
  end;

  { The chevrons, on a box under the mouse; dim while there is nowhere
    to go. }
  DrawChevron(tpBack, FBackRect);
  DrawChevron(tpForward, FForwardRect);

  for i := 0 to TabsShown - 1 do
  begin
    R := TabRect(i);
    Shown := i = FTabActive;
    Hover := (FHotIndex = i) and (FHotPart in [tpTab, tpTabClose]);
    if Shown then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := FTabFill;
      Canvas.Pen.Color := FTabBorder;
      Canvas.Pen.Width := 1;
      Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Scale96ToForm(10),
        Scale96ToForm(10));
    end
    else if Hover then
      HotBox(R, FButtonHot)
    { A faint line parts two tabs that are neither shown nor hovered. }
    else if (i < High(FCaptions)) and (i + 1 <> FTabActive) and
      not ((FHotIndex = i + 1) and (FHotPart in [tpTab, tpTabClose])) then
      Line(R.Right + Scale96ToForm(TabGap) div 2, R.Top + Scale96ToForm(7),
        R.Right + Scale96ToForm(TabGap) div 2, R.Bottom - Scale96ToForm(7), FTabBorder);
    Canvas.Brush.Style := bsClear;
    if Shown then
      Canvas.Font.Color := Ink
    else
      Canvas.Font.Color := FDim;
    C := CrossRect(R);
    if FFixed then
      C.Left := R.Right - Scale96ToForm(6);
    { News: a dot before the name, which moves over for it. }
    L := R.Left + Scale96ToForm(10);
    if FMarks[i] then
    begin
      W := Scale96ToForm(6);
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := FMark;
      Canvas.Pen.Color := FMark;
      Canvas.Ellipse(L, (R.Top + R.Bottom - W) div 2, L + W, (R.Top + R.Bottom + W) div 2);
      Canvas.Brush.Style := bsClear;
      Inc(L, W + Scale96ToForm(5));
    end;
    if FExts[i] then
    begin
      W := Scale96ToForm(11);
      PaintPuzzle(Canvas, L, (R.Top + R.Bottom - W) div 2, W, Canvas.Font.Color);
      Canvas.Brush.Style := bsClear;
      Inc(L, W + Scale96ToForm(5));
    end;
    Canvas.TextRect(Types.Rect(L, R.Top, C.Left - Scale96ToForm(4), R.Bottom), L, TextY,
      FCaptions[i]);
    if not FFixed and (Shown or Hover) then
    begin
      if Hover and (FHotPart = tpTabClose) then
      begin
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := FTabBorder;
        Canvas.Pen.Color := FTabBorder;
        Canvas.Ellipse(C);
      end;
      W := Scale96ToForm(4);
      Line(C.Left + W + 1, C.Top + W + 1, C.Right - W, C.Bottom - W, FDim);
      Line(C.Right - W - 1, C.Top + W + 1, C.Left + W, C.Bottom - W, FDim);
    end;
  end;

  { The plus, unless there is no room for it. }
  if not FFixed and not FPlusRect.IsEmpty then
  begin
    if FHotPart = tpPlus then
      HotBox(FPlusRect, FButtonHot);
    Mid := (FPlusRect.Left + FPlusRect.Right) div 2;
    L := (FPlusRect.Top + FPlusRect.Bottom) div 2;
    W := Scale96ToForm(6);
    Line(Mid - W, L, Mid + W + 1, L, FDim);
    Line(Mid, L - W, Mid, L + W + 1, FDim);
  end;
  Canvas.Pen.Width := 1;

  { The tip, right-aligned before the banner or the caption buttons,
    while it is clear of the last tab and the plus. }
  if not FFixed and (FTip <> '') then
  begin
    L := TabsStart + TabsShown * TabWidth;
    if not FPlusRect.IsEmpty then
      L := FPlusRect.Right;
    W := Canvas.TextWidth(FTip);
    Mid := TabsLimit - Scale96ToForm(Pad + Gap) - W;
    if Mid >= L + Scale96ToForm(16) then
    begin
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Color := FDim;
      Canvas.TextOut(Mid, TextY, FTip);
    end;
  end;

  { The banner: a ribbon from the top edge with a notch at its foot, in
    the accent with a white globe while the forge view is shown, else a
    little of the text color in the background, a little more under the
    mouse, as on macOS: the tab fill is the background itself in the
    light theme. }
  if FForgeVisible then
  begin
    R := FForgeRect;
    Canvas.Brush.Style := bsSolid;
    if FForgeShown then
      Canvas.Brush.Color := FMark
    else if FHotPart = tpForge then
      Canvas.Brush.Color := MixColor(FMain, FText, 0.16)
    else
      Canvas.Brush.Color := MixColor(FMain, FText, 0.08);
    Canvas.Pen.Color := Canvas.Brush.Color;
    Canvas.Pen.Width := 1;
    W := Scale96ToForm(ForgeNotch);
    Canvas.Polygon([Types.Point(R.Left, R.Top), Types.Point(R.Right - 1, R.Top),
      Types.Point(R.Right - 1, R.Bottom), Types.Point((R.Left + R.Right) div 2, R.Bottom - W),
      Types.Point(R.Left, R.Bottom)]);
    L := Scale96ToForm(ForgeIconSize);
    if FAvatar.HasImage then
    begin
      { The user's picture as a disc on a little of the text color, so
        one with a clear background still reads as a disc, with a white
        ring round it while the forge view is shown. }
      C := Types.Rect(R.Left + (R.Width - L) div 2, (R.Bottom - W - L) div 2 + 1, 0, 0);
      C.Right := C.Left + L;
      C.Bottom := C.Top + L;
      Canvas.Pen.Style := psClear;
      Canvas.Brush.Color := MixColor(Canvas.Brush.Color, FText, 0.12);
      Canvas.Ellipse(C);
      Canvas.Pen.Style := psSolid;
      Canvas.Brush.Style := bsClear;
      FAvatar.Draw(Canvas, C.Left, C.Top, L, GetCanvasScaleFactor);
      if FForgeShown then
      begin
        Canvas.Pen.Color := clWhite;
        Canvas.Pen.Width := Scale96ToForm(2);
        Canvas.Ellipse(C);
      end;
      Canvas.Brush.Style := bsSolid;
    end
    else
    begin
      if FForgeShown then
        GlobeInk := clWhite
      else if FHotPart = tpForge then
        GlobeInk := Ink
      else
        GlobeInk := FDim;
      { The icon is a square ASize - 4 wide at its left. }
      DrawStatusIcon(Canvas, HintLink, R.Left + (R.Width - (L - 4)) div 2,
        (R.Bottom - W - L) div 2 + 1, L, GlobeInk);
    end;
    Canvas.Pen.Width := 1;
    { What waits for the user, in a disc of the mark color at the top
      right corner of the globe or the picture: the number up to nine,
      "9+" in a wider one beyond; none while the view is shown, where
      its tab has the dot. }
    if (FForgeCount > 0) and not FForgeShown then
    begin
      if FForgeCount > 9 then
        Badge := '9+'
      else
        Badge := IntToStr(FForgeCount);
      Canvas.Font := Font;
      Canvas.Font.Size := ForgeBadgeFont;
      Canvas.Font.Style := [fsBold];
      L := Scale96ToForm(ForgeBadgeSize);
      C.Right := R.Right - 1;
      C.Left := C.Right - Max(L, Canvas.TextWidth(Badge) + Scale96ToForm(6));
      C.Top := Max(R.Top, (R.Bottom - W - Scale96ToForm(ForgeIconSize)) div 2 - Scale96ToForm(3));
      C.Bottom := C.Top + L;
      Canvas.Pen.Style := psClear;
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := FMark;
      Canvas.RoundRect(C.Left, C.Top, C.Right + 1, C.Bottom + 1, L, L);
      Canvas.Pen.Style := psSolid;
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Color := clWhite;
      Canvas.TextOut(C.Left + (C.Width - Canvas.TextWidth(Badge)) div 2,
        C.Top + (C.Height - Canvas.TextHeight(Badge)) div 2, Badge);
      Canvas.Font := Font;
      Canvas.Brush.Style := bsSolid;
    end;
  end;

  if not FTabsOnly and not PinnedMenu then
  begin
    DrawButton(tpMinimize, FMinRect, tgMinimize);
    if Maximized then
      Glyph := tgRestore
    else
      Glyph := tgMaximize;
    DrawButton(tpMaximize, FMaxRect, Glyph);
    DrawButton(tpClose, FCloseRect, tgClose);
  end;

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

{ The form scales every control by its DPI after FormCreate, this one's
  height too, which is already the screen's: set it again. }
procedure TGittanOwnTitleBar.DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
  const AXProportion, AYProportion: double);
begin
  inherited DoAutoAdjustLayout(AMode, AXProportion, AYProportion);
  if AMode = lapAutoAdjustForDPI then
    Height := Scale96ToScreen(TitleBarHeight);
end;

{ TGittanMenuStrip }

{ S without its accelerator marks (&& stays one &), with AKey the
  position in the result of the letter after the first single &, 0 for
  none. }
function MenuText(const S: string; out AKey: integer): string;
var
  i: integer;
begin
  Result := '';
  AKey := 0;
  i := 1;
  while i <= Length(S) do
  begin
    if (S[i] = '&') and (i < Length(S)) then
    begin
      Inc(i);
      if (S[i] <> '&') and (AKey = 0) then
        AKey := Length(Result) + 1;
    end;
    Result := Result + S[i];
    Inc(i);
  end;
end;

{ Each window the strip gets, not the first alone, is told to the bar:
  Windows subclasses it, and a window made anew has lost that. }
procedure TGittanMenuStrip.CreateWnd;
begin
  inherited CreateWnd;
  FBar.StripMade(Self);
end;

constructor TGittanMenuStrip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBar := AOwner as TGittanOwnTitleBar;
  ControlStyle := ControlStyle + [csOpaque];
  TabStop := False;
  FHot := -1;
  FOpen := -1;
  FStepTo := -1;
  FButtonHot := tpNone;
  FButtonPressed := tpNone;
  FPopup := TPopupMenu.Create(Self);
  FPopup.OnClose := @PopupClose;
end;

destructor TGittanMenuStrip.Destroy;
begin
  Application.RemoveAsyncCalls(Self);
  SetPrevFocus(nil);
  inherited Destroy;
end;

procedure TGittanMenuStrip.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FPrevFocus) then
    FPrevFocus := nil;
end;

{ Kept from the start, the strip is made in FormCreate, which scales its
  height once more afterwards; the height is set again, as the bar's. }
procedure TGittanMenuStrip.DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
  const AXProportion, AYProportion: double);
begin
  inherited DoAutoAdjustLayout(AMode, AXProportion, AYProportion);
  if AMode = lapAutoAdjustForDPI then
    Height := Scale96ToScreen(StripHeight);
end;

procedure TGittanMenuStrip.SetPrevFocus(AControl: TWinControl);
begin
  if FPrevFocus <> nil then
    FPrevFocus.RemoveFreeNotification(Self);
  if AControl = Self then
    AControl := nil;
  FPrevFocus := AControl;
  if FPrevFocus <> nil then
    FPrevFocus.FreeNotification(Self);
end;

{ The menu bar's visible top items, and their names' places. }
procedure TGittanMenuStrip.Collect;
var
  Form: TCustomForm;
  i, X, W, K: integer;
begin
  SetLength(FItems, 0);
  SetLength(FRects, 0);
  Form := GetParentForm(Self);
  if (Form = nil) or (Form.Menu = nil) or not HandleAllocated then
    Exit;
  Canvas.Font := FBar.Font;
  X := Scale96ToForm(Pad);
  for i := 0 to Form.Menu.Items.Count - 1 do
  begin
    if not Form.Menu.Items[i].Visible then
      Continue;
    W := Canvas.TextWidth(MenuText(Form.Menu.Items[i].Caption, K)) +
      2 * Scale96ToForm(StripItemPad);
    SetLength(FItems, Length(FItems) + 1);
    SetLength(FRects, Length(FRects) + 1);
    FItems[High(FItems)] := Form.Menu.Items[i];
    FRects[High(FRects)] := Types.Rect(X, Scale96ToForm(2), X + W,
      Height - Scale96ToForm(2));
    Inc(X, W);
  end;
  if FHot > High(FItems) then
    FHot := -1;
end;

function TGittanMenuStrip.IndexAt(X, Y: integer): integer;
var
  i: integer;
begin
  Result := -1;
  if (Y < 0) or (Y >= Height) then
    Exit;
  for i := 0 to High(FRects) do
    if (X >= FRects[i].Left) and (X < FRects[i].Right) then
      Exit(i);
end;

function TGittanMenuStrip.NameAt(X, Y: integer): integer;
begin
  if CaptionPart(X, Y) <> tpNone then
    Result := -1
  else
    Result := IndexAt(X, Y);
end;

function TGittanMenuStrip.ButtonRect(APart: TGittanTitlePart): TRect;
var
  W, i: integer;
begin
  Result := Types.Rect(0, 0, 0, 0);
  if not FPinned then
    Exit;
  W := Scale96ToForm(ButtonWidth);
  case APart of
    tpClose: i := 1;
    tpMaximize: i := 2;
    tpMinimize: i := 3;
  else
    Exit;
  end;
  Result := Types.Rect(Width - i * W, 0, Width - (i - 1) * W, Height);
end;

function TGittanMenuStrip.CaptionPart(X, Y: integer): TGittanTitlePart;
var
  Part: TGittanTitlePart;
begin
  for Part in [tpMinimize, tpMaximize, tpClose] do
    if ButtonRect(Part).Contains(Types.Point(X, Y)) then
      Exit(Part);
  Result := tpNone;
end;

function TGittanMenuStrip.IndexOfKey(AKey: char): integer;
var
  i, K: integer;
  S: string;
begin
  Result := -1;
  for i := 0 to High(FItems) do
  begin
    S := MenuText(FItems[i].Caption, K);
    if (K > 0) and (UpCase(S[K]) = UpCase(AKey)) then
      Exit(i);
  end;
end;

procedure TGittanMenuStrip.SetHot(AIndex: integer);
begin
  if FHot = AIndex then
    Exit;
  FHot := AIndex;
  Invalidate;
end;

{ Over the title bar, which moves down by the strip's height while it is
  shown; the focus is the strip's, the control that had it noted. }
procedure TGittanMenuStrip.ShowStrip;
begin
  if Visible or (Parent = nil) then
    Exit;
  Height := Scale96ToForm(StripHeight);
  Parent.DisableAlign;
  try
    Visible := True;
    Top := 0;
    FBar.Top := Height;
  finally
    Parent.EnableAlign;
  end;
end;

procedure TGittanMenuStrip.SetPinned(AValue: boolean);
begin
  if FPinned = AValue then
    Exit;
  FPinned := AValue;
  if FPinned then
    ShowStrip
  else if Visible and not Focused and not MenuOpen then
    Visible := False;
end;

procedure TGittanMenuStrip.Activate(AIndex: integer; AKeys: boolean);
begin
  if Parent = nil then
    Exit;
  if not Focused then
    SetPrevFocus(Screen.ActiveControl);
  ShowStrip;
  Collect;
  if Length(FItems) = 0 then
  begin
    Dismiss(True);
    Exit;
  end;
  FKeys := AKeys;
  FHot := Max(0, Min(AIndex, High(FItems)));
  Invalidate;
  if CanFocus then
    SetFocus;
end;

procedure TGittanMenuStrip.Dismiss(ARestore: boolean);
begin
  Application.RemoveAsyncCalls(Self);
  FHot := -1;
  FOpen := -1;
  FStepTo := -1;
  FPending := False;
  if not Visible then
    Exit;
  { The focus goes back before the strip hides, which would hand it on
    to a control of its own choosing, and before a chosen command runs,
    which acts on the focused control (Edit > Copy). }
  if ARestore and (FPrevFocus <> nil) and FPrevFocus.CanFocus then
    FPrevFocus.SetFocus;
  SetPrevFocus(nil);
  if FPinned then
  begin
    FKeys := False;
    Invalidate;
  end
  else
    Visible := False;
end;

{ The menu under its name, its top item's OnClick run first, as a menu
  bar runs it when the menu opens. }
procedure TGittanMenuStrip.OpenItem(AIndex: integer);
var
  Src: TMenuItem;
begin
  if (FOpen >= 0) or (AIndex < 0) or (AIndex > High(FItems)) then
    Exit;
  Src := FItems[AIndex];
  if not Src.Enabled then
    Exit;
  if Assigned(Src.OnClick) then
    Src.Click;
  FPopup.Items.Clear;
  CopyMenuItems(Src, FPopup.Items, FPopup, @PopupItemClick);
  if FPopup.Items.Count = 0 then
    Exit;
  FOpen := AIndex;
  FHot := AIndex;
  FStepTo := -1;
  Invalidate;
  Update;
  FBar.TrackMenu(Self, FPopup, FRects[AIndex]);
end;

procedure TGittanMenuStrip.OpenAsync(Data: PtrInt);
begin
  FPending := False;
  if Visible then
    OpenItem(Data);
end;

procedure TGittanMenuStrip.PopupItemClick(Sender: TObject);
var
  Item: TMenuItem;
begin
  Item := TMenuItem(TMenuItem(Sender).Tag);
  Dismiss(True);
  Item.Click;
end;

{ Closed for another menu (Left, Right, the mouse on another name): that
  one opens; else (Escape, a click elsewhere, a command chosen) the
  strip goes. }
procedure TGittanMenuStrip.PopupClose(Sender: TObject);
begin
  MenuClosed;
end;

procedure TGittanMenuStrip.MenuClosed;
var
  Index: integer;
begin
  if FOpen < 0 then
    Exit;
  FOpen := -1;
  if FStepTo >= 0 then
  begin
    Index := FStepTo;
    FStepTo := -1;
    FHot := Index;
    Invalidate;
    FPending := True;
    Application.QueueAsyncCall(@OpenAsync, Index);
  end
  else
    Dismiss(True);
end;

function TGittanMenuStrip.MenuOpen: boolean;
begin
  Result := (FOpen >= 0) or FPending;
end;

function TGittanMenuStrip.StepMenu(ADelta: integer): boolean;
var
  N: integer;
begin
  N := Length(FItems);
  Result := (FOpen >= 0) and (N > 1);
  if Result then
  begin
    FStepTo := (FOpen + ADelta + N) mod N;
    FKeys := True;
  end;
end;

function TGittanMenuStrip.HoverAt(const AScreen: TPoint): boolean;
var
  P: TPoint;
  Index: integer;
begin
  Result := False;
  if (FOpen < 0) or not HandleAllocated then
    Exit;
  P := ScreenToClient(AScreen);
  Index := IndexAt(P.X, P.Y);
  if (Index < 0) or (Index = FOpen) or not FItems[Index].Enabled then
    Exit;
  FStepTo := Index;
  Result := True;
end;

procedure TGittanMenuStrip.KeyDown(var Key: word; Shift: TShiftState);
var
  N, Index: integer;
begin
  inherited KeyDown(Key, Shift);
  N := Length(FItems);
  if (Key = 0) or (N = 0) then
    Exit;
  case Key of
    VK_LEFT: SetHot((Max(FHot, 0) - 1 + N) mod N);
    VK_RIGHT: SetHot((FHot + 1) mod N);
    VK_HOME: SetHot(0);
    VK_END: SetHot(N - 1);
    VK_DOWN, VK_UP, VK_RETURN, VK_SPACE: OpenItem(Max(FHot, 0));
    VK_ESCAPE: Dismiss(True);
    VK_A..VK_Z, VK_0..VK_9:
      begin
        if Shift * [ssCtrl, ssMeta, ssShift] <> [] then
          Exit;
        Index := IndexOfKey(Chr(Key));
        if Index < 0 then
          Exit;
        FKeys := True;
        SetHot(Index);
        OpenItem(Index);
      end;
    else
      Exit;
  end;
  Key := 0;
end;

procedure TGittanMenuStrip.MouseMove(Shift: TShiftState; X, Y: integer);
var
  Index: integer;
begin
  inherited MouseMove(Shift, X, Y);
  Index := NameAt(X, Y);
  if (FOpen < 0) and (Index >= 0) then
    SetHot(Index);
  if CaptionPart(X, Y) <> FButtonHot then
  begin
    FButtonHot := CaptionPart(X, Y);
    Invalidate;
  end;
  if FDragArmed and (ssLeft in Shift) and
    ((Abs(X - FPressPoint.X) >= Scale96ToForm(StripDragThreshold)) or
    (Abs(Y - FPressPoint.Y) >= Scale96ToForm(StripDragThreshold))) then
  begin
    FDragArmed := False;
    FBar.WindowMove;
  end;
  { A click on a name of the kept strip may take the focus; the control
    that has it now gets it back once the menu is done with. }
  if not Focused and (FOpen < 0) then
    SetPrevFocus(Screen.ActiveControl);
end;

{ A press is forgotten with the mouse gone: without capture (GTK) the
  release outside is never seen. }
procedure TGittanMenuStrip.MouseLeave;
begin
  inherited MouseLeave;
  FDragArmed := False;
  if (FButtonHot <> tpNone) or (FButtonPressed <> tpNone) then
  begin
    FButtonHot := tpNone;
    FButtonPressed := tpNone;
    Invalidate;
  end;
  if not Focused and (FOpen < 0) then
    SetHot(-1);
end;

procedure TGittanMenuStrip.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Index: integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  Index := NameAt(X, Y);
  if Index >= 0 then
  begin
    if Button = mbLeft then
    begin
      SetHot(Index);
      OpenItem(Index);
    end;
    Exit;
  end;
  { The caption buttons act on release; the empty part is the caption
    (on Windows the form answers it, and this is not called). }
  if CaptionPart(X, Y) <> tpNone then
  begin
    if Button = mbLeft then
    begin
      FButtonPressed := CaptionPart(X, Y);
      Invalidate;
    end;
    Exit;
  end;
  case Button of
    mbLeft:
      if ssDouble in Shift then
      begin
        FDragArmed := False;
        FBar.WindowZoom;
      end
      else
      begin
        FDragArmed := True;
        FPressPoint := Types.Point(X, Y);
      end;
    mbRight: FBar.WindowMenu;
  end;
end;

procedure TGittanMenuStrip.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Pressed: TGittanTitlePart;
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragArmed := False;
  Pressed := FButtonPressed;
  if Pressed = tpNone then
    Exit;
  FButtonPressed := tpNone;
  Invalidate;
  if (Button = mbLeft) and (CaptionPart(X, Y) = Pressed) then
    FBar.CaptionButtonClick(Pressed);
end;

{ The focus went elsewhere: the strip goes, once the focus has moved, but
  not for its own menu, which may take it on some window systems. }
procedure TGittanMenuStrip.DoExit;
begin
  inherited DoExit;
  if FOpen < 0 then
    Application.QueueAsyncCall(@ExitAsync, 0);
end;

procedure TGittanMenuStrip.ExitAsync(Data: PtrInt);
begin
  if Visible and not MenuOpen and (FStepTo < 0) and not Focused then
    Dismiss(False);
end;

procedure TGittanMenuStrip.Paint;
var
  Split, i, K, TextY, X1, X2, Y: integer;
  R: TRect;
  S: string;
  Ink: TColor;

  procedure PaintButton(APart: TGittanTitlePart; AGlyph: TGittanTitleGlyph;
    AInk: TColor);
  var
    BR: TRect;
    Fore: TColor;
  begin
    BR := ButtonRect(APart);
    Fore := AInk;
    if (FBar.FHotButton = APart) or (FBar.FPressedButton = APart) or
      (FButtonHot = APart) or (FButtonPressed = APart) then
    begin
      Canvas.Brush.Style := bsSolid;
      if APart = tpClose then
      begin
        Canvas.Brush.Color := CloseHot;
        Fore := clWhite;
      end
      else
        Canvas.Brush.Color := FBar.FButtonHot;
      Canvas.FillRect(BR);
    end;
    FBar.DrawGlyph(Canvas, AGlyph, BR, Fore);
    Canvas.Font := FBar.Font;
  end;

begin
  Collect;
  if (FBar.FSplitControl <> nil) and (FBar.FSplitControl.Parent <> nil) then
    Split := FBar.FSplitControl.Left + FBar.FSplitControl.Width
  else
    Split := 0;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBar.FSide;
  Canvas.FillRect(Types.Rect(0, 0, Split, Height));
  Canvas.Brush.Color := FBar.FMain;
  Canvas.FillRect(Types.Rect(Split, 0, Width, Height));
  Canvas.Font := FBar.Font;
  TextY := (Height - Canvas.TextHeight('Xg')) div 2;
  for i := 0 to High(FItems) do
  begin
    R := FRects[i];
    if (i = FHot) or (i = FOpen) then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := FBar.FButtonHot;
      Canvas.Pen.Color := FBar.FButtonHot;
      Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Scale96ToForm(8),
        Scale96ToForm(8));
    end;
    if FBar.FActive and FItems[i].Enabled then
      Ink := FBar.FText
    else
      Ink := FBar.FDim;
    S := MenuText(FItems[i].Caption, K);
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := Ink;
    X1 := R.Left + Scale96ToForm(StripItemPad);
    Canvas.TextOut(X1, TextY, S);
    { The accelerator underlined, as a menu bar shows it from the keys. }
    if FKeys and (K > 0) then
    begin
      Inc(X1, Canvas.TextWidth(Copy(S, 1, K - 1)));
      X2 := X1 + Canvas.TextWidth(Copy(S, K, UTF8CodepointSize(@S[K])));
      Y := TextY + Canvas.TextHeight('X');
      Canvas.Pen.Color := Ink;
      Canvas.Pen.Width := Max(1, Scale96ToForm(1));
      Canvas.Line(X1, Y, X2, Y);
      Canvas.Pen.Width := 1;
    end;
  end;
  { The caption buttons while the strip is kept, in the bar's state (the
    form sees the mouse on them on Windows) or the strip's own. }
  if FPinned then
  begin
    if FBar.FActive then
      Ink := FBar.FText
    else
      Ink := FBar.FDim;
    PaintButton(tpMinimize, tgMinimize, Ink);
    if FBar.Maximized then
      PaintButton(tpMaximize, tgRestore, Ink)
    else
      PaintButton(tpMaximize, tgMaximize, Ink);
    PaintButton(tpClose, tgClose, Ink);
  end;
end;

{ TGittanTabBar }

constructor TGittanTabBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTabsOnly := True;
end;

function TGittanTabBar.Maximized: boolean;
begin
  Result := False;
end;

procedure TGittanTabBar.DrawGlyph(ACanvas: TCanvas; AGlyph: TGittanTitleGlyph; const AR: TRect;
  AColor: TColor);
begin
end;

end.
