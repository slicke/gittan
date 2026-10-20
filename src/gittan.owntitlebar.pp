{ A title bar the form draws itself (Windows and GTK 3).

  TGittanOwnTitleBar, aligned at the top of the form, stands in for the
  window's caption, as in VS Code or Windows Terminal: the name and the
  menus on the left, the file filter as a rounded search field in the
  middle, and on the right the change navigator, the actions the view
  offers (the file header's pills) and the minimize, maximize and close
  buttons. It lays out and paints all of that, tells which part a point
  is in and runs the pills, the search field and the menu names.

  What the window system does differs: how the window is moved,
  maximized, minimized and closed, how a menu drops down, which glyphs
  the caption buttons get. A descendant per widgetset supplies that
  through Maximized, ShowMenu, CaptionButtonClick and DrawGlyph:
  gittan.wintitlebar on Windows, where the window's non-client messages
  answer the mouse on the empty parts and the caption buttons, and
  gittan.gtktitlebar on GTK 3, where the bar takes the mouse itself and
  asks GTK.

  SetBand draws a progress band along the bar's top edge, as the band
  over the title bar on macOS (gittan.titlebar): the bar paints it, in
  the strip above its menus, field and pills. }
unit gittan.owntitlebar;

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

  {** The glyphs a descendant draws: the caption buttons' (restore for
    maximize while the window is maximized), the search field's
    magnifier and its clear button. }
  TGittanTitleGlyph = (tgMinimize, tgMaximize, tgRestore, tgClose, tgSearch,
    tgClear);

  { TGittanOwnTitleBar }

  TGittanOwnTitleBar = class(TCustomControl)
  private
    FSearch: TCustomEdit;
    FNav, FConflictNav: TGittanChangeNav;
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
    FTitle: string;
    FOnAction: TGittanTitleActionEvent;
    procedure SetSearch(AValue: TCustomEdit);
    procedure SetActive(AValue: boolean);
    function BandFillWidth(APos, ATotal: integer): integer;
    function MenuOf(AForm: TCustomForm): TMainMenu;
  protected
    {** The part at a point of the bar, with the index of the menu name or
      the action; a disabled action still counts. }
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
    {** Drops the submenu of AItem, the AIndexth visible item of the main
      menu, down from ARect, the name's rectangle in the bar; the name is
      drawn as open until MenuClosed is called, when the menu has gone. }
    procedure ShowMenu(AIndex: integer; AItem: TMenuItem; const ARect: TRect);
      virtual; abstract;
    {** A click released on a caption button the bar itself saw the mouse
      on (on Windows the form sees it instead, and this is not called). }
    procedure CaptionButtonClick(APart: TGittanTitlePart); virtual;
    {** The menu ShowMenu opened has closed: the name is drawn plain. }
    procedure MenuClosed;
  public
    constructor Create(AOwner: TComponent); override;
    {** The caption button under the mouse or pressed, tpNone for none;
      set by a form that sees the mouse there itself (Windows). }
    procedure SetButtonState(AHot, APressed: TGittanTitlePart);
    {** Places the menus, the search field, the navigator and the pills;
      again after the menu changed. }
    procedure Layout;
    {** Opens the menu with the name at AIndex, in the order of the main
      menu's visible items. }
    procedure OpenMenu(AIndex: integer);
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
    {** Shows ACurrent of ATotal conflicts in the conflict navigator, or
      hides it when ATotal is 0. }
    procedure SetConflicts(ACurrent, ATotal: integer);
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
    {** The conflict navigator, left of the other one while SetConflicts
      gave it a count. }
    property ConflictNav: TGittanChangeNav read FConflictNav;
    {** The name on the left. }
    property Title: string read FTitle write FTitle;
    {** Whether the window is the active one; the text dims when not. }
    property Active: boolean read FActive write SetActive;
    {** The caption button SetButtonState last gave as pressed. }
    property PressedButton: TGittanTitlePart read FPressedButton;
    {** The dim text color, for a descendant's glyphs. }
    property DimColor: TColor read FDim;
    property OnAction: TGittanTitleActionEvent read FOnAction write FOnAction;
  end;

const
  {** The bar's height at 96 dpi. }
  TitleBarHeight = 40;

implementation

uses
  Math, LCLIntf;

const
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
  FOpenMenu := -1;
  FActive := True;
  FNav := TGittanChangeNav.Create(Self);
  FNav.Parent := Self;
  FNav.Height := Scale96ToScreen(NavHeight);
  FNav.Visible := False;
  FConflictNav := TGittanChangeNav.Create(Self);
  FConflictNav.Parent := Self;
  FConflictNav.Height := Scale96ToScreen(NavHeight);
  FConflictNav.Visible := False;
  SetColors(clBtnFace, clWindow, clWindowText, clGrayText, clBtnFace,
    clBtnShadow, clHighlight, clWindow, clBtnShadow, clBtnFace);
end;

procedure TGittanOwnTitleBar.SetSearch(AValue: TCustomEdit);
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

procedure TGittanOwnTitleBar.SetActive(AValue: boolean);
begin
  if FActive = AValue then
    Exit;
  FActive := AValue;
  Invalidate;
end;

procedure TGittanOwnTitleBar.SetColors(ASide, AMain, AText, ADim, APillFill,
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

procedure TGittanOwnTitleBar.SetActions(const ACaptions: array of string;
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

procedure TGittanOwnTitleBar.SetChanges(ACurrent, ATotal: integer);
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

procedure TGittanOwnTitleBar.SetConflicts(ACurrent, ATotal: integer);
begin
  if ATotal > 0 then
    FConflictNav.SetPosition(ACurrent, ATotal);
  if FConflictNav.Visible <> (ATotal > 0) then
  begin
    FConflictNav.Visible := ATotal > 0;
    Layout;
    Invalidate;
  end;
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

{ Right to left: the caption buttons, the pills, the navigator; from the
  left the name and the menus; the search field centered on the bar in
  the room that is left, narrower when there is little. }
procedure TGittanOwnTitleBar.Layout;
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
  if FConflictNav.Visible then
  begin
    FConflictNav.SetBounds(Right - FConflictNav.Width, (H - FConflictNav.Height) div 2,
      FConflictNav.Width, FConflictNav.Height);
    Right := FConflictNav.Left - Scale96ToForm(Gap);
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

procedure TGittanOwnTitleBar.Resize;
begin
  inherited Resize;
  Layout;
end;

function TGittanOwnTitleBar.PartAt(X, Y: integer; out AIndex: integer): TGittanTitlePart;
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

procedure TGittanOwnTitleBar.SetHot(APart: TGittanTitlePart; AIndex: integer);
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

procedure TGittanOwnTitleBar.MouseMove(Shift: TShiftState; X, Y: integer);
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

procedure TGittanOwnTitleBar.MouseDown(Button: TMouseButton; Shift: TShiftState;
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
    tpAction, tpClear, tpMinimize, tpMaximize, tpClose:
      begin
        FPressedPart := Part;
        FPressedIndex := Index;
        Invalidate;
      end;
  end;
end;

{ A pill, the clear button or a caption button acts on release over
  itself. }
procedure TGittanOwnTitleBar.MouseUp(Button: TMouseButton; Shift: TShiftState;
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
    tpMinimize, tpMaximize, tpClose:
      CaptionButtonClick(Part);
  end;
end;

procedure TGittanOwnTitleBar.CaptionButtonClick(APart: TGittanTitlePart);
begin
end;

{ The name is drawn as open before the menu drops, in case the
  widgetset's menu runs a loop of its own until it closes. }
procedure TGittanOwnTitleBar.OpenMenu(AIndex: integer);
begin
  if (AIndex < 0) or (AIndex > High(FMenuItems)) then
    Exit;
  FOpenMenu := AIndex;
  Invalidate;
  Update;
  ShowMenu(AIndex, FMenuItems[AIndex], FMenuRects[AIndex]);
end;

procedure TGittanOwnTitleBar.MenuClosed;
begin
  FOpenMenu := -1;
  SetHot(tpNone, -1);
  Invalidate;
end;

function TGittanOwnTitleBar.OpenMenuByKey(AKey: char): boolean;
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

procedure TGittanOwnTitleBar.Paint;
var
  Split, i, TextY, W: integer;
  R: TRect;
  Ink: TColor;
  Glyph: TGittanTitleGlyph;

  procedure FillPill(const AR: TRect; AFill, ABorder: TColor);
  begin
    Canvas.Pen.Color := ABorder;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := AFill;
    Canvas.RoundRect(AR.Left, AR.Top, AR.Right, AR.Bottom, AR.Height, AR.Height);
  end;

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
    DrawGlyph(tgSearch, Types.Rect(FSearchRect.Left, FSearchRect.Top,
      FSearchRect.Left + W, FSearchRect.Bottom), FDim);
    if (FSearch <> nil) and (FSearch.Text <> '') then
      if FHotPart = tpClear then
        DrawGlyph(tgClear, FClearRect, Ink)
      else
        DrawGlyph(tgClear, FClearRect, FDim);
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

end.
