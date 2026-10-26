{ The window's own title bar (GTK 3, Linux).

  Under Wayland GTK decorates its windows itself (client-side
  decoration): a title bar of its own, the shadow, the rounded corners
  and the invisible resize border in the shadow. InstallTitleBar gives
  the form's window an empty box as its title bar
  (gtk_window_set_titlebar), so GTK keeps the shadow, the corners and the
  resize border and the strip is gone, and TGittanGtkTitleBar, aligned
  at the top of the form, takes its place: the bar of gittan.owntitlebar
  (the menu button, the tabs and the caption buttons) with the GTK parts
  of it. GTK only takes the
  title bar from a window it has not realized, and the LCL realizes the
  form's window as it creates it (which InstallTitleBar makes it do,
  since the form has no handle yet while it is created), so the window
  is unrealized first (it is not shown yet) and realized again at once:
  the LCL reads the window's GdkWindow when it shows the form.

  The bar takes the mouse itself: a press on an empty part followed by a
  drag past a few pixels starts the compositor's move
  (gtk_window_begin_move_drag, as GTK's own title bar does), a double
  click maximizes or restores, a right click opens the window menu
  (gdk_window_show_window_menu), and the caption buttons iconify,
  maximize and close through GTK. The bar does not capture the mouse
  (csCaptureMouse), since the compositor takes it with the move and the
  release would never come.

  The menu stays on the window, so commands are found in it and its
  shortcuts work, but its names are hidden (HideNativeMenu hides the
  menu bar's items, kept hidden through the show_all the LCL runs when
  it shows the form, and lets the bar be a pixel high: the LCL subtracts
  the bar's height from the form's, and takes a height of 0 as the menu
  height of its own) and the bar's menu button drops a copy of the menu
  as a popup. The caption glyphs are drawn with lines.

  The unit uses GTK; umain keeps it behind LCLGtk3. }
unit gittan.gtktitlebar;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Menus, Types, Forms,
  gittan.owntitlebar;

type

  { TGittanGtkTitleBar }

  TGittanGtkTitleBar = class(TGittanOwnTitleBar)
  private
    FPressPoint: TPoint;
    FDragArmed: boolean;
    procedure BeginMove;
    procedure ShowWindowMenu;
  protected
    function Maximized: boolean; override;
    procedure DrawGlyph(AGlyph: TGittanTitleGlyph; const AR: TRect;
      AColor: TColor); override;
    procedure CaptionButtonClick(APart: TGittanTitlePart); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** Maximizes the window, or restores it when it is maximized. }
    procedure ToggleMaximized;
    {** Hides the names of the form's menu bar, which the bar shows
      instead; after the menu is built. }
    procedure HideNativeMenu;
  end;

{** Makes the form's window keep GTK's decoration without its title bar
  and lets ABar, at the top of the form, stand for the title bar. }
procedure InstallTitleBar(AForm: TCustomForm; ABar: TGittanGtkTitleBar);

implementation

uses
  LazGtk3, LazGdk3, LazGObject2, LazGLib2, gtk3widgets, gtk3procs;

const
  { How far a press on an empty part moves before the window follows
    it, as GTK's drag threshold. }
  DragThreshold = 8;

var
  { The bar the window's signals are connected to; nil once it is gone,
    so a late signal finds nothing. }
  LiveBar: TGittanGtkTitleBar;

{ The GTK window of the form the bar is on; nil before it has one,
  unless AForce makes the form create it. }
function FormWindow(ABar: TControl; AForce: boolean = False): PGtkWindow;
var
  Form: TCustomForm;
begin
  Result := nil;
  Form := GetParentForm(ABar);
  if (Form = nil) or not (AForce or Form.HandleAllocated) then
    Exit;
  Result := PGtkWindow(TGtk3Widget(Form.Handle).Widget);
  if not Gtk3IsGtkWindow(PGObject(Result)) then
    Result := nil;
end;

procedure ActiveChanged(AObject: PGObject; AParam: PGParamSpec; AData: gpointer); cdecl;
begin
  if (LiveBar <> nil) and (AData = Pointer(LiveBar)) then
    LiveBar.Active := gtk_window_is_active(PGtkWindow(AObject));
end;

function StateChanged(AWidget: PGtkWidget; AEvent: PGdkEventWindowState;
  AData: gpointer): gboolean; cdecl;
begin
  { The maximize button's glyph follows the state. }
  if (LiveBar <> nil) and (AData = Pointer(LiveBar)) then
    LiveBar.Invalidate;
  Result := False;
end;

procedure InstallTitleBar(AForm: TCustomForm; ABar: TGittanGtkTitleBar);
var
  Win: PGtkWindow;
  Box: PGtkWidget;
begin
  LiveBar := ABar;
  Win := FormWindow(ABar, True);
  if Win = nil then
    Exit;
  if gtk_widget_get_realized(PGtkWidget(Win)) and
    not gtk_widget_get_mapped(PGtkWidget(Win)) then
    gtk_widget_unrealize(PGtkWidget(Win));
  Box := PGtkWidget(gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0));
  gtk_widget_show(Box);
  gtk_window_set_titlebar(Win, Box);
  { Realized again, with the decoration: the LCL's ShowHide reads the
    window's GdkWindow before it shows the form. }
  if not gtk_widget_get_realized(PGtkWidget(Win)) then
    gtk_widget_realize(PGtkWidget(Win));
  g_signal_connect_data(PGObject(Win), 'notify::is-active',
    TGCallback(@ActiveChanged), ABar, nil, G_CONNECT_DEFAULT);
  g_signal_connect_data(PGObject(Win), 'window-state-event',
    TGCallback(@StateChanged), ABar, nil, G_CONNECT_DEFAULT);
  ABar.Active := gtk_window_is_active(Win);
end;

{ TGittanGtkTitleBar }

constructor TGittanGtkTitleBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle - [csCaptureMouse];
end;

destructor TGittanGtkTitleBar.Destroy;
begin
  if LiveBar = Self then
    LiveBar := nil;
  inherited Destroy;
end;

function TGittanGtkTitleBar.Maximized: boolean;
var
  Win: PGtkWindow;
begin
  Win := FormWindow(Self);
  Result := (Win <> nil) and gtk_window_is_maximized(Win);
end;

procedure TGittanGtkTitleBar.ToggleMaximized;
var
  Win: PGtkWindow;
begin
  Win := FormWindow(Self);
  if Win = nil then
    Exit;
  if gtk_window_is_maximized(Win) then
    gtk_window_unmaximize(Win)
  else
    gtk_window_maximize(Win);
end;

procedure TGittanGtkTitleBar.CaptionButtonClick(APart: TGittanTitlePart);
var
  Win: PGtkWindow;
  Form: TCustomForm;
begin
  Win := FormWindow(Self);
  if Win = nil then
    Exit;
  case APart of
    tpMinimize: gtk_window_iconify(Win);
    tpMaximize: ToggleMaximized;
    tpClose:
      begin
        Form := GetParentForm(Self);
        if Form <> nil then
          Form.Close;
      end;
  end;
end;

{ The compositor moves the window from here; the bar sees no more of
  this press. }
procedure TGittanGtkTitleBar.BeginMove;
var
  Win: PGtkWindow;
  P: TPoint;
begin
  Win := FormWindow(Self);
  if Win = nil then
    Exit;
  P := Mouse.CursorPos;
  SetHot(tpNone, -1);
  gtk_window_begin_move_drag(Win, 1, P.X, P.Y, gtk_get_current_event_time);
end;

procedure TGittanGtkTitleBar.ShowWindowMenu;
var
  Win: PGtkWindow;
  Event: PGdkEvent;
begin
  Win := FormWindow(Self);
  if Win = nil then
    Exit;
  Event := gtk_get_current_event;
  if Event = nil then
    Exit;
  gdk_window_show_window_menu(gtk_widget_get_window(PGtkWidget(Win)), Event);
  gdk_event_free(Event);
end;

procedure TGittanGtkTitleBar.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Index: integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if PartAt(X, Y, Index) <> tpNone then
    Exit;
  case Button of
    mbLeft:
      if ssDouble in Shift then
      begin
        FDragArmed := False;
        ToggleMaximized;
      end
      else
      begin
        FDragArmed := True;
        FPressPoint := Types.Point(X, Y);
      end;
    mbRight: ShowWindowMenu;
  end;
end;

procedure TGittanGtkTitleBar.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragArmed and (ssLeft in Shift) and
    ((Abs(X - FPressPoint.X) >= Scale96ToForm(DragThreshold)) or
    (Abs(Y - FPressPoint.Y) >= Scale96ToForm(DragThreshold))) then
  begin
    FDragArmed := False;
    BeginMove;
  end;
end;

procedure TGittanGtkTitleBar.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
begin
  FDragArmed := False;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TGittanGtkTitleBar.MouseLeave;
begin
  FDragArmed := False;
  inherited MouseLeave;
end;

{ Lines a pixel wide, as the caption buttons of GNOME and Windows 11
  draw them: a dash, a square, two squares, a cross; a magnifier and a
  small cross for the search field. }
procedure TGittanGtkTitleBar.DrawGlyph(AGlyph: TGittanTitleGlyph; const AR: TRect;
  AColor: TColor);
var
  CX, CY, H, D, R: integer;
begin
  CX := (AR.Left + AR.Right) div 2;
  CY := (AR.Top + AR.Bottom) div 2;
  H := Scale96ToForm(5);
  Canvas.Pen.Color := AColor;
  Canvas.Pen.Width := 1;
  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Style := bsClear;
  case AGlyph of
    tgMinimize:
      Canvas.Line(CX - H, CY, CX + H + 1, CY);
    tgMaximize:
      Canvas.Rectangle(CX - H, CY - H, CX + H + 1, CY + H + 1);
    tgRestore:
      begin
        { The front square, and the back one's top and right edges
          behind it. }
        D := Scale96ToForm(2);
        Canvas.Rectangle(CX - H, CY - H + D, CX + H - D + 1, CY + H + 1);
        Canvas.Polyline([Types.Point(CX - H + D, CY - H + D - 1),
          Types.Point(CX - H + D, CY - H), Types.Point(CX + H, CY - H),
          Types.Point(CX + H, CY + H - D), Types.Point(CX + H - D + 1, CY + H - D)]);
      end;
    tgClose:
      begin
        Canvas.Line(CX - H, CY - H, CX + H + 1, CY + H + 1);
        Canvas.Line(CX - H, CY + H, CX + H + 1, CY - H - 1);
      end;
    tgSearch:
      begin
        { The glass up and left of the center, the handle down and
          right. }
        R := Scale96ToForm(4);
        Canvas.Ellipse(CX - R - 1, CY - R - 1, CX + R - 1, CY + R - 1);
        D := Scale96ToForm(2);
        Canvas.Line(CX + D, CY + D, CX + R + D, CY + R + D);
      end;
    tgClear:
      begin
        D := Scale96ToForm(3);
        Canvas.Line(CX - D, CY - D, CX + D + 1, CY + D + 1);
        Canvas.Line(CX - D, CY + D, CX + D + 1, CY - D - 1);
      end;
  end;
end;

procedure TGittanGtkTitleBar.HideNativeMenu;
var
  Form: TCustomForm;
  Menu: TMainMenu;
  i: integer;
begin
  Form := GetParentForm(Self);
  if (Form = nil) or not Form.HandleAllocated then
    Exit;
  Menu := Form.Menu;
  if Menu = nil then
    Exit;
  for i := 0 to Menu.Items.Count - 1 do
  begin
    Menu.Items[i].HandleNeeded;
    if Menu.Items[i].HandleAllocated then
    begin
      { The LCL shows the form with show_all, which skips these. }
      gtk_widget_set_no_show_all(TGtk3MenuItem(Menu.Items[i].Handle).Widget, True);
      gtk_widget_hide(TGtk3MenuItem(Menu.Items[i].Handle).Widget);
    end;
  end;
  if TGtk3Widget(Form.Handle) is TGtk3Window then
    gtk_widget_set_size_request(PGtkWidget(TGtk3Window(Form.Handle).GetMenuBar), 1, 1);
end;

end.
