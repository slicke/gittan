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
  with their own item as Sender. Alt and a letter drops the menu with
  that accelerator the same way, from the menu button (OpenMenuByKey).
  The menu bar itself stays on the window, hidden, for its shortcuts.

  The tabs: the shown one is a filled, rounded box, a hovered one a
  fainter box, the others their names with a faint line between two of
  them; a tab with news has a dot in the accent before its name; the cross on the shown and the hovered tab, or a middle click,
  closes one (OnTabClose), a press on a tab shows it (OnTabSelect), the
  plus asks for a new one (OnNewTab). The tooltip is the path of the tab
  under the mouse.

  What the window system does differs: how the window is moved,
  maximized, minimized and closed, which glyphs the caption buttons get.
  A descendant per widgetset supplies that through Maximized,
  CaptionButtonClick and DrawGlyph: gittan.wintitlebar on Windows, where
  the window's non-client messages answer the mouse on the empty parts
  and the caption buttons, and gittan.gtktitlebar on GTK 3, where the bar
  takes the mouse itself and asks GTK.

  SetBand draws a progress band along the bar's top edge, as the band
  over the title bar on macOS (gittan.titlebar): the bar paints it, in
  the strip above its tabs. }
unit gittan.owntitlebar;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Menus, Types, Forms;

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

  { TGittanOwnTitleBar }

  TGittanOwnTitleBar = class(TCustomControl)
  private
    FSplitControl: TControl;
    FCaptions, FHints: array of string;
    FMarks: array of boolean;
    FTabActive: integer;
    { The tabs are a view's own (the forge view's): no cross, no plus. }
    FFixed: boolean;
    FMenuRect, FBackRect, FForwardRect, FPlusRect, FForgeRect, FMinRect, FMaxRect,
    FCloseRect: TRect;
    { Back and Forward: whether each can be gone to, and their hints. }
    FCanBack, FCanForward: boolean;
    FBackHint, FForwardHint: string;
    { The globe: whether it is there, whether the forge view is shown,
      and its hint. }
    FForgeVisible, FForgeShown: boolean;
    FForgeHint: string;
    FHotPart, FPressedPart, FHotButton, FPressedButton: TGittanTitlePart;
    FHotIndex, FPressedIndex: integer;
    FMenuOpen: boolean;
    FPopup: TPopupMenu;
    FActive: boolean;
    FSide, FMain, FText, FDim, FTabFill, FTabBorder, FButtonHot, FMark: TColor;
    FBandPos, FBandTotal: integer;
    FBandTrack, FBandFill: TColor;
    FTitle: string;
    FOnTabSelect, FOnTabClose: TGittanTitleTabEvent;
    FOnNewTab, FOnForge, FOnBack, FOnForward: TNotifyEvent;
    procedure SetActive(AValue: boolean);
    function BandFillWidth(APos, ATotal: integer): integer;
    function MenuOf(AForm: TCustomForm): TMainMenu;
    function TabsLimit: integer;
    function TabsStart: integer;
    function NavEnabled(APart: TGittanTitlePart): boolean;
    function TabWidth: integer;
    function TabRect(AIndex: integer): TRect;
    function CrossRect(const ATab: TRect): TRect;
    procedure CopyItems(ASource, ATarget: TMenuItem);
    procedure PopupItemClick(Sender: TObject);
    procedure PopupClose(Sender: TObject);
    procedure DropMenu(AOnly: TMenuItem);
  protected
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
    {** Draws AGlyph centered in AR in AColor, and leaves the canvas's
      font as it found it. }
    procedure DrawGlyph(AGlyph: TGittanTitleGlyph; const AR: TRect;
      AColor: TColor); virtual; abstract;
    {** A click released on a caption button the bar itself saw the mouse
      on (on Windows the form sees it instead, and this is not called). }
    procedure CaptionButtonClick(APart: TGittanTitlePart); virtual;
  public
    constructor Create(AOwner: TComponent); override;
    {** The caption button under the mouse or pressed, tpNone for none;
      set by a form that sees the mouse there itself (Windows). }
    procedure SetButtonState(AHot, APressed: TGittanTitlePart);
    {** Places the menu button, the tabs, the plus and the caption
      buttons; again after the tabs changed. }
    procedure Layout;
    {** Drops the whole menu from the menu button. }
    procedure OpenMenu;
    {** Drops the menu whose name has the accelerator AKey; False when
      none has it. }
    function OpenMenuByKey(AKey: char): boolean;
    {** The tabs, left to right: ACaptions are their names, AHints their
      tooltips (the paths), AMarks those with news (a dot before the
      name), AActive the one shown; AFixed when they are a view's own,
      which cannot be closed or added to: no cross and no plus. }
    procedure SetTabs(const ACaptions, AHints: array of string;
      const AMarks: array of boolean; AActive: integer; AFixed: boolean = False);
    {** The banner before the caption buttons: shown while AVisible
      (there is a forge), in the accent while AShown (the forge view is
      shown), AHint its hint (the forge's name). }
    procedure SetForge(AVisible, AShown: boolean; const AHint: string);
    {** The chevrons: whether there is somewhere to go back (ABack) and
      forward (AForward) to, a dim chevron taking no click; ABackHint
      and AForwardHint their hints. }
    procedure SetNav(ABack, AForward: boolean; const ABackHint, AForwardHint: string);
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
    {** The chevrons: back, forward. }
    property OnBack: TNotifyEvent read FOnBack write FOnBack;
    property OnForward: TNotifyEvent read FOnForward write FOnForward;
  end;

const
  {** The bar's height at 96 dpi. }
  TitleBarHeight = 40;

implementation

uses
  Math, LCLIntf, LCLType, gittan.statusbar, gittan.theme;

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
  CrossSize = 18;
  ButtonWidth = 46;
  BandHeight = 3;
  { The least the band's fill is wide: a rounded window corner (Windows
    11, GNOME) hides its first pixels. }
  MinBandFill = 16;
  CloseHot = $1C2BC4; { RGB(196, 43, 28) }

{ TGittanOwnTitleBar }

constructor TGittanOwnTitleBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
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
  const AMarks: array of boolean; AActive: integer; AFixed: boolean);
var
  i: integer;
begin
  FFixed := AFixed;
  SetLength(FCaptions, Length(ACaptions));
  SetLength(FHints, Length(ACaptions));
  SetLength(FMarks, Length(ACaptions));
  for i := 0 to High(ACaptions) do
  begin
    FCaptions[i] := ACaptions[i];
    FMarks[i] := (i <= High(AMarks)) and AMarks[i];
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
  FMenuRect := Types.Rect(Scale96ToForm(Pad), (H - S) div 2,
    Scale96ToForm(Pad + MenuButtonWidth), (H + S) div 2);
  X := FMenuRect.Right + Scale96ToForm(Gap);
  W := Scale96ToForm(NavSize);
  FBackRect := Types.Rect(X, (H - W) div 2 + 1, X + W, (H + W) div 2 + 1);
  X := FBackRect.Right + Scale96ToForm(NavGap);
  FForwardRect := Types.Rect(X, FBackRect.Top, X + W, FBackRect.Bottom);
  X := TabsStart + Length(FCaptions) * TabWidth;
  if FFixed then
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
  for i := 0 to High(FCaptions) do
  begin
    R := TabRect(i);
    if R.Right > TabsLimit then
      Break;
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
    tpMenu: OpenMenu;
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

procedure TGittanOwnTitleBar.SetForge(AVisible, AShown: boolean; const AHint: string);
begin
  FForgeVisible := AVisible;
  FForgeShown := AShown;
  FForgeHint := AHint;
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

{ ASource's items as items of ATarget that click them: captions, keys,
  checks and enabled states as they are now, and submenus copied in
  turn. A separator stays one. }
procedure TGittanOwnTitleBar.CopyItems(ASource, ATarget: TMenuItem);
var
  i: integer;
  Src, Item: TMenuItem;
begin
  for i := 0 to ASource.Count - 1 do
  begin
    Src := ASource.Items[i];
    if not Src.Visible then
      Continue;
    Item := TMenuItem.Create(FPopup);
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
        CopyItems(Src, Item)
      else
        Item.OnClick := @PopupItemClick;
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
    CopyItems(AOnly, FPopup.Items);
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
      CopyItems(Menu.Items[i], Item);
      FPopup.Items.Add(Item);
    end;
  FMenuOpen := True;
  Invalidate;
  Update;
  P := ClientToScreen(Types.Point(FMenuRect.Left, Height));
  FPopup.PopUp(P.X, P.Y);
end;

procedure TGittanOwnTitleBar.OpenMenu;
begin
  DropMenu(nil);
end;

function TGittanOwnTitleBar.OpenMenuByKey(AKey: char): boolean;
var
  Menu: TMainMenu;
  i, p: integer;
  S: string;
begin
  Result := False;
  Menu := MenuOf(GetParentForm(Self));
  if Menu = nil then
    Exit;
  for i := 0 to Menu.Items.Count - 1 do
  begin
    if not Menu.Items[i].Visible then
      Continue;
    S := Menu.Items[i].Caption;
    p := System.Pos('&', S);
    if (p > 0) and (p < Length(S)) and (UpCase(S[p + 1]) = UpCase(AKey)) then
    begin
      DropMenu(Menu.Items[i]);
      Exit(True);
    end;
  end;
end;

procedure TGittanOwnTitleBar.Paint;
var
  Split, i, TextY, Mid, W, L: integer;
  R, C: TRect;
  Ink, GlobeInk: TColor;
  Glyph: TGittanTitleGlyph;
  Shown, Hover: boolean;

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
    DrawGlyph(AGlyph, AR, Fore);
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
  if FMenuOpen or (FHotPart = tpMenu) then
    HotBox(FMenuRect, FButtonHot);
  Mid := (FMenuRect.Left + FMenuRect.Right) div 2;
  W := Scale96ToForm(7);
  for i := -1 to 1 do
  begin
    L := (FMenuRect.Top + FMenuRect.Bottom) div 2 + i * Scale96ToForm(5);
    Line(Mid - W, L, Mid + W, L, Ink);
  end;

  { The chevrons, on a box under the mouse; dim while there is nowhere
    to go. }
  DrawChevron(tpBack, FBackRect);
  DrawChevron(tpForward, FForwardRect);

  for i := 0 to High(FCaptions) do
  begin
    R := TabRect(i);
    if R.Right > TabsLimit then
      Break;
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

  { The plus. }
  if not FFixed then
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
    if FForgeShown then
      GlobeInk := clWhite
    else if FHotPart = tpForge then
      GlobeInk := Ink
    else
      GlobeInk := FDim;
    { The icon is a square ASize - 4 wide at its left. }
    DrawStatusIcon(Canvas, HintLink, R.Left + (R.Width - (L - 4)) div 2,
      (R.Bottom - W - L) div 2 + 1, L, GlobeInk);
    Canvas.Pen.Width := 1;
  end;

  DrawButton(tpMinimize, FMinRect, tgMinimize);
  if Maximized then
    Glyph := tgRestore
  else
    Glyph := tgMaximize;
  DrawButton(tpMaximize, FMaxRect, Glyph);
  DrawButton(tpClose, FCloseRect, tgClose);

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

end.
