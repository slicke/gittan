{ The window's toolbar and its tabs (macOS).

  The title bar takes the mouse in the strip it covers, so the LCL's own
  controls cannot be put there (see gittan.titlebar.pp). An NSToolbar in
  the unified style can: it makes the strip taller, so the traffic
  lights sit in a row of a tab bar's height, and its items are native
  and take clicks. Its one item is the tab strip, a view of its own
  (TGittanTabStrip) that stretches from the traffic lights to the right
  edge, as Firefox's tabs do: Back and Forward first, two chevrons
  (SetNav; dim while there is nowhere to go), then a tab per open
  repository, the one shown filled, then a plus that opens a new tab.

  The strip draws the tabs itself in the system's colors, so it follows
  the window's appearance; a tab with news (something happened in its
  frame while another was shown) has a blue dot before its name. A
  click on a tab selects it at once; the
  cross on the shown or hovered tab, or a middle click, closes it; the
  plus asks for a new tab; a chevron asks to go back or forward
  (OnBack, OnForward) on its release. At the window's right end a banner hangs
  from the top edge over the title bar, a ribbon with a notch at its
  foot and a globe in it (SetForge; there while there is a forge, in
  the accent while the forge view is shown), which asks for the forge
  view (OnForge); it is a view of its own in the window's frame view
  (TGittanForgeBanner), since the strip, a toolbar item, does not reach
  the top edge, and the strip keeps its tabs out of its room. A press
  on the empty part moves the window and a double click there zooms
  it, as on the title bar. The full path of the tab under the mouse is
  its tooltip, the forge's name the banner's.

  The filter, the change navigator and the actions of the view belong to
  a repository and are in its frame: the field over the tree and the
  file header's pills.

  The unit uses CocoaAll alone; uwindow keeps it behind LCLCocoa, so the
  other widgetsets never see it. }
unit gittan.toolbar;

{$mode objfpc}{$H+}
{$modeswitch objectivec1}

interface

uses
  Classes, CocoaAll;

type
  {** Something done to the tab at AIndex, in the order of SetTabs. }
  TGittanTabEvent = procedure(Sender: TObject; AIndex: integer) of object;

  { TGittanToolbar }

  TGittanToolbar = class
  private
    FWindow: NSWindow;
    FToolbar: NSToolbar;
    FDelegate: NSObject;
    FStrip: NSView;
    FDragArea: NSView;
    FCaptions, FHints: array of string;
    FMarks: array of boolean;
    FActive: integer;
    { The tabs are a view's own (the forge view's): no cross, no plus. }
    FFixed: boolean;
    { The tab under the mouse (-1 for none), whether the mouse is on its
      cross, on the plus; the cross or plus pressed (-1 for none,
      PlusPart for the plus). }
    FHot: integer;
    FHotClose, FHotPlus: boolean;
    FPressed: integer;
    { Back and Forward: whether each can be gone to, their tooltips, the
      chevron under the mouse (NavNone, NavBack, NavForward). }
    FCanBack, FCanForward: boolean;
    FBackHint, FForwardHint: string;
    FHotNav: integer;
    { The banner: its view (made when first shown), whether it is there,
      whether the forge view is shown, the mouse on it and pressed. }
    FBanner: NSView;
    FForgeVisible, FForgeShown, FBannerHot, FBannerPressed: boolean;
    FOnSelect, FOnClose: TGittanTabEvent;
    FOnNew, FOnForge, FOnBack, FOnForward: TNotifyEvent;
    function GlobeRoom: double;
    function NavRect(ANav: integer; const ABounds: NSRect): NSRect;
    function NavEnabled(ANav: integer): boolean;
    procedure DrawNav(ANav: integer; const ABounds: NSRect);
    function TabWidth(AWidth: double): double;
    function TabRect(AIndex: integer; const ABounds: NSRect): NSRect;
    function CloseRect(const ATab: NSRect): NSRect;
    function PlusRect(const ABounds: NSRect): NSRect;
    procedure HitTest(const APoint: NSPoint; const ABounds: NSRect;
      out AIndex: integer; out AClose, APlus: boolean; out ANav: integer);
    procedure MakeBanner;
    procedure DrawBanner(const ABounds: NSRect);
    procedure BannerDown;
    procedure BannerUp(AEvent: NSEvent);
    procedure BannerHover(AHot: boolean);
    procedure Draw(const ABounds: NSRect);
    procedure MouseDown(AEvent: NSEvent);
    procedure MouseUp(AEvent: NSEvent);
    procedure OtherMouseUp(AEvent: NSEvent);
    procedure MouseMoved(AEvent: NSEvent);
    procedure MouseExited;
    function DragAt(const APoint: NSPoint; AView: NSView): boolean;
  public
    {** Puts the toolbar with the tab strip on the window of the form
      whose handle is AHandle and hides the window's title. Answers nil
      before macOS 11 or without a window. }
    class function Install(AHandle: PtrUInt): TGittanToolbar;
    destructor Destroy; override;
    {** The tabs, left to right: ACaptions are their names, AHints their
      tooltips (the paths), AMarks those with news (a dot before the
      name), AActive the one shown; AFixed when they are a view's own,
      which cannot be closed or added to: no cross and no plus. }
    procedure SetTabs(const ACaptions, AHints: array of string;
      const AMarks: array of boolean; AActive: integer; AFixed: boolean = False);
    {** The banner at the right end: shown while AVisible (there is a
      forge), in the accent while AShown (the forge view is shown),
      AHint its tooltip (the forge's name). }
    procedure SetForge(AVisible, AShown: boolean; const AHint: string);
    {** The chevrons: whether there is somewhere to go back (ABack) and
      forward (AForward) to, a dim chevron taking no click; ABackHint
      and AForwardHint their tooltips. }
    procedure SetNav(ABack, AForward: boolean; const ABackHint, AForwardHint: string);
    {** A click on a tab: show it. }
    property OnSelect: TGittanTabEvent read FOnSelect write FOnSelect;
    {** The cross or a middle click on a tab: close it. }
    property OnClose: TGittanTabEvent read FOnClose write FOnClose;
    {** The plus: a new tab. }
    property OnNew: TNotifyEvent read FOnNew write FOnNew;
    {** The banner: the forge view, or back from it. }
    property OnForge: TNotifyEvent read FOnForge write FOnForge;
    {** The chevrons: back, forward. }
    property OnBack: TNotifyEvent read FOnBack write FOnBack;
    property OnForward: TNotifyEvent read FOnForward write FOnForward;
  end;

implementation

uses
  SysUtils, Math, cocoa_extra;

type
  NSColorSystemBlue = objccategory external (NSColor)
    class function systemBlueColor: NSColor; message 'systemBlueColor'; { 10.10 }
  end;

  NSWindowDrag = objccategory external (NSWindow)
    procedure performWindowDragWithEvent(event: NSEvent);
      message 'performWindowDragWithEvent:'; { 10.11 }
  end;

  { The toolbar's delegate. }
  TGittanToolbarDelegate = objcclass(NSObject, NSToolbarDelegateProtocol)
  public
    Owner: TGittanToolbar;
    function toolbar_itemForItemIdentifier_willBeInsertedIntoToolbar(
      toolbar: NSToolbar; itemIdentifier: NSString; flag: ObjCBOOL): NSToolbarItem;
    function toolbarDefaultItemIdentifiers(toolbar: NSToolbar): NSArray;
    function toolbarAllowedItemIdentifiers(toolbar: NSToolbar): NSArray;
  end;

  { The banner: the toolbar draws it and takes its mouse. }
  TGittanForgeBanner = objcclass(NSView)
  public
    Owner: TGittanToolbar;
    function isFlipped: ObjCBOOL; override;
    function mouseDownCanMoveWindow: ObjCBOOL; override;
    function acceptsFirstMouse(event: NSEvent): ObjCBOOL; override;
    procedure drawRect(dirtyRect: NSRect); override;
    procedure mouseDown(event: NSEvent); override;
    procedure mouseUp(event: NSEvent); override;
    procedure mouseEntered(event: NSEvent); override;
    procedure mouseExited(event: NSEvent); override;
  end;

  { The title bar's row outside the strip: the toolbar holds its item
    to its own height, and the row above and below it took no drag. }
  TGittanDragArea = objcclass(NSView)
  public
    Owner: TGittanToolbar;
    function hitTest(aPoint: NSPoint): NSView; override;
    function mouseDownCanMoveWindow: ObjCBOOL; override;
    function acceptsFirstMouse(event: NSEvent): ObjCBOOL; override;
    procedure mouseDown(event: NSEvent); override;
  end;

  { The tab strip: the toolbar draws it and takes its mouse. }
  TGittanTabStrip = objcclass(NSView)
  public
    Owner: TGittanToolbar;
    function isFlipped: ObjCBOOL; override;
    function mouseDownCanMoveWindow: ObjCBOOL; override;
    function acceptsFirstMouse(event: NSEvent): ObjCBOOL; override;
    procedure drawRect(dirtyRect: NSRect); override;
    procedure mouseDown(event: NSEvent); override;
    procedure mouseUp(event: NSEvent); override;
    procedure otherMouseUp(event: NSEvent); override;
    procedure mouseMoved(event: NSEvent); override;
    procedure mouseExited(event: NSEvent); override;
  end;

const
  IdTabs = 'gittan.tabs';
  StripHeight = 30;
  { A tab's width: shared out evenly, within these. }
  MaxTabWidth = 220;
  MinTabWidth = 64;
  { The gap between tabs, the room the plus takes after the last. }
  TabGap = 3;
  PlusWidth = 30;
  CrossSize = 16;
  { The banner: its width, how far it stays from the window's right
    edge, how far it hangs (from the top edge), the depth of the notch
    at its foot; the room the strip leaves it at its right end. }
  BannerWidth = 30;
  BannerRight = 14;
  BannerHeight = 44;
  BannerNotch = 8;
  GlobeWidth = 40;
  { FPressed for the plus and the chevrons. }
  PlusPart = -2;
  BackPart = -3;
  ForwardPart = -4;
  { The chevrons: none, back, forward; a chevron's button, the gap
    between the two, the room they take before the first tab. }
  NavNone = 0;
  NavBack = 1;
  NavForward = 2;
  NavWidth = 26;
  NavHeight = 24;
  NavGap = 2;
  NavRoom = 2 * NavWidth + NavGap + 10;

function NSStr(const S: string): NSString;
begin
  Result := NSString.stringWithUTF8String(PChar(S));
end;

{ Whether the strip is drawn on a dark window: the label color the
  appearance resolves is light then. }
function DarkAppearance: boolean;
var
  C: NSColor;
begin
  C := NSColor.labelColor.colorUsingColorSpace(NSColorSpace.sRGBColorSpace);
  Result := (C <> nil) and (C.redComponent > 0.5);
end;

procedure StrokeLine(X1, Y1, X2, Y2: double; AColor: NSColor; AWidth: double);
var
  P: NSBezierPath;
begin
  P := NSBezierPath.bezierPath;
  P.moveToPoint(NSMakePoint(X1, Y1));
  P.lineToPoint(NSMakePoint(X2, Y2));
  P.setLineWidth(AWidth);
  P.setLineCapStyle(NSRoundLineCapStyle);
  AColor.setStroke;
  P.stroke;
end;

{ Strokes the oval in R in the stroke color set. }
procedure StrokeOval(const R: NSRect; AWidth: double);
var
  P: NSBezierPath;
begin
  P := NSBezierPath.bezierPathWithOvalInRect(R);
  P.setLineWidth(AWidth);
  P.stroke;
end;

function PointIn(const P: NSPoint; const R: NSRect): boolean;
begin
  Result := (P.x >= R.origin.x) and (P.x < R.origin.x + R.size.width) and
    (P.y >= R.origin.y) and (P.y < R.origin.y + R.size.height);
end;

{ TGittanToolbarDelegate }

function TGittanToolbarDelegate.toolbar_itemForItemIdentifier_willBeInsertedIntoToolbar(
  toolbar: NSToolbar; itemIdentifier: NSString; flag: ObjCBOOL): NSToolbarItem;
begin
  Result := nil;
  if itemIdentifier.isEqualToString(NSStr(IdTabs)) then
  begin
    Result := NSToolbarItem.alloc.initWithItemIdentifier(itemIdentifier);
    Result.setView(Owner.FStrip);
    { Between these it takes the width the toolbar has; at the least
      Back and Forward, a tab, the plus and the globe. }
    Result.setMinSize(NSMakeSize(NavRoom + MinTabWidth + PlusWidth + GlobeWidth, StripHeight));
    Result.setMaxSize(NSMakeSize(100000, StripHeight));
    Result.autorelease;
  end;
end;

function TGittanToolbarDelegate.toolbarDefaultItemIdentifiers(toolbar: NSToolbar): NSArray;
begin
  Result := NSArray.arrayWithObjects(NSStr(IdTabs), nil);
end;

function TGittanToolbarDelegate.toolbarAllowedItemIdentifiers(toolbar: NSToolbar): NSArray;
begin
  Result := toolbarDefaultItemIdentifiers(toolbar);
end;

{ TGittanForgeBanner }

function TGittanForgeBanner.isFlipped: ObjCBOOL;
begin
  Result := True;
end;

function TGittanForgeBanner.mouseDownCanMoveWindow: ObjCBOOL;
begin
  Result := False;
end;

function TGittanForgeBanner.acceptsFirstMouse(event: NSEvent): ObjCBOOL;
begin
  Result := True;
end;

procedure TGittanForgeBanner.drawRect(dirtyRect: NSRect);
begin
  if Owner <> nil then
    Owner.DrawBanner(bounds);
end;

procedure TGittanForgeBanner.mouseDown(event: NSEvent);
begin
  if Owner <> nil then
    Owner.BannerDown;
end;

procedure TGittanForgeBanner.mouseUp(event: NSEvent);
begin
  if Owner <> nil then
    Owner.BannerUp(event);
end;

procedure TGittanForgeBanner.mouseEntered(event: NSEvent);
begin
  if Owner <> nil then
    Owner.BannerHover(True);
end;

procedure TGittanForgeBanner.mouseExited(event: NSEvent);
begin
  if Owner <> nil then
    Owner.BannerHover(False);
end;

{ TGittanDragArea }

{ It covers the window's frame view and answers only the points where a
  press moves the window (DragAt), so the rest falls through. }
function TGittanDragArea.hitTest(aPoint: NSPoint): NSView;
begin
  if (Owner <> nil) and (superview <> nil) and Owner.DragAt(aPoint, superview) then
    Result := Self
  else
    Result := nil;
end;

function TGittanDragArea.mouseDownCanMoveWindow: ObjCBOOL;
begin
  Result := False;
end;

function TGittanDragArea.acceptsFirstMouse(event: NSEvent): ObjCBOOL;
begin
  Result := True;
end;

procedure TGittanDragArea.mouseDown(event: NSEvent);
begin
  if window = nil then
    Exit;
  if event.clickCount = 2 then
    window.performZoom(nil)
  else
    window.performWindowDragWithEvent(event);
end;

{ TGittanTabStrip }

function TGittanTabStrip.isFlipped: ObjCBOOL;
begin
  Result := True;
end;

{ The strip moves the window itself from its empty part (MouseDown). }
function TGittanTabStrip.mouseDownCanMoveWindow: ObjCBOOL;
begin
  Result := False;
end;

{ A click on a tab of a window in the background selects it too. }
function TGittanTabStrip.acceptsFirstMouse(event: NSEvent): ObjCBOOL;
begin
  Result := True;
end;

procedure TGittanTabStrip.drawRect(dirtyRect: NSRect);
begin
  if Owner <> nil then
    Owner.Draw(bounds);
end;

procedure TGittanTabStrip.mouseDown(event: NSEvent);
begin
  if Owner <> nil then
    Owner.MouseDown(event);
end;

procedure TGittanTabStrip.mouseUp(event: NSEvent);
begin
  if Owner <> nil then
    Owner.MouseUp(event);
end;

procedure TGittanTabStrip.otherMouseUp(event: NSEvent);
begin
  if Owner <> nil then
    Owner.OtherMouseUp(event);
end;

procedure TGittanTabStrip.mouseMoved(event: NSEvent);
begin
  if Owner <> nil then
    Owner.MouseMoved(event);
end;

procedure TGittanTabStrip.mouseExited(event: NSEvent);
begin
  if Owner <> nil then
    Owner.MouseExited;
end;

{ TGittanToolbar }

class function TGittanToolbar.Install(AHandle: PtrUInt): TGittanToolbar;
var
  Win: NSWindow;
  Delegate: TGittanToolbarDelegate;
  Strip: TGittanTabStrip;
  Area: NSTrackingArea;
  Frame: NSView;
begin
  Result := nil;
  if (AHandle = 0) or (NSAppKitVersionNumber < NSAppKitVersionNumber11_0) then
    Exit;
  Win := NSView(AHandle).window;
  if Win = nil then
    Exit;
  Result := TGittanToolbar.Create;
  Result.FWindow := Win;
  Result.FHot := -1;
  Result.FPressed := -1;
  Result.FHotNav := NavNone;
  Strip := TGittanTabStrip.alloc.initWithFrame(NSMakeRect(0, 0, 400, StripHeight));
  Strip.Owner := Result;
  Area := NSTrackingArea.alloc.initWithRect_options_owner_userInfo(NSZeroRect,
    NSTrackingMouseMoved or NSTrackingMouseEnteredAndExited or
    NSTrackingActiveAlways or NSTrackingInVisibleRect, Strip, nil);
  Strip.addTrackingArea(Area);
  Area.release;
  Result.FStrip := Strip;
  Delegate := TGittanToolbarDelegate.alloc.init;
  Delegate.Owner := Result;
  Result.FDelegate := Delegate;
  Result.FToolbar := NSToolbar.alloc.initWithIdentifier(NSStr('gittan.toolbar'));
  Result.FToolbar.setDelegate(Delegate);
  Result.FToolbar.setDisplayMode(NSToolbarDisplayModeIconOnly);
  Result.FToolbar.setAllowsUserCustomization(False);
  Win.setToolbar(Result.FToolbar);
  Win.setToolbarStyle(NSWindowToolbarStyleUnified);
  { The tabs name the repositories, as does the status bar. }
  Win.setTitleVisibility(NSWindowTitleHidden);
  Frame := Win.contentView.superview;
  if Frame <> nil then
  begin
    Result.FDragArea := TGittanDragArea.alloc.initWithFrame(Frame.bounds);
    TGittanDragArea(Result.FDragArea).Owner := Result;
    Result.FDragArea.setAutoresizingMask(NSViewWidthSizable or NSViewHeightSizable);
    Frame.addSubview_positioned_relativeTo(Result.FDragArea, NSWindowAbove, nil);
  end;
end;

destructor TGittanToolbar.Destroy;
begin
  if FDragArea <> nil then
  begin
    TGittanDragArea(FDragArea).Owner := nil;
    FDragArea.removeFromSuperview;
    FDragArea.release;
  end;
  if FBanner <> nil then
  begin
    TGittanForgeBanner(FBanner).Owner := nil;
    FBanner.removeFromSuperview;
    FBanner.release;
  end;
  if FWindow <> nil then
    FWindow.setToolbar(nil);
  if FToolbar <> nil then
  begin
    FToolbar.setDelegate(nil);
    FToolbar.release;
  end;
  if FStrip <> nil then
  begin
    TGittanTabStrip(FStrip).Owner := nil;
    FStrip.release;
  end;
  if FDelegate <> nil then
    FDelegate.release;
  inherited Destroy;
end;

procedure TGittanToolbar.SetForge(AVisible, AShown: boolean; const AHint: string);
begin
  if AVisible and (FBanner = nil) then
    MakeBanner;
  FForgeVisible := AVisible;
  FForgeShown := AShown;
  if FBanner <> nil then
  begin
    FBanner.setHidden(not AVisible);
    FBanner.setToolTip(NSStr(AHint));
    FBanner.setNeedsDisplay_(True);
  end;
  if not AVisible then
  begin
    FBannerHot := False;
    FBannerPressed := False;
  end;
  if FStrip <> nil then
    FStrip.setNeedsDisplay_(True);
end;

{ In the window's frame view, over the toolbar and the content alike,
  at the top right and kept there as the window resizes (the frame
  view's origin is at its bottom). }
procedure TGittanToolbar.MakeBanner;
var
  Frame: NSView;
  Area: NSTrackingArea;
  B: NSRect;
begin
  Frame := FWindow.contentView.superview;
  if Frame = nil then
    Exit;
  B := Frame.bounds;
  FBanner := TGittanForgeBanner.alloc.initWithFrame(NSMakeRect(
    B.size.width - BannerRight - BannerWidth, B.size.height - BannerHeight,
    BannerWidth, BannerHeight));
  TGittanForgeBanner(FBanner).Owner := Self;
  FBanner.setAutoresizingMask(NSViewMinXMargin or NSViewMinYMargin);
  Area := NSTrackingArea.alloc.initWithRect_options_owner_userInfo(NSZeroRect,
    NSTrackingMouseEnteredAndExited or NSTrackingActiveAlways or NSTrackingInVisibleRect,
    FBanner, nil);
  FBanner.addTrackingArea(Area);
  Area.release;
  Frame.addSubview_positioned_relativeTo(FBanner, NSWindowAbove, nil);
end;

{ A ribbon hanging from the top edge with a notch at its foot and a
  globe in it: faint, a little stronger under the mouse, in the accent
  with a white globe while the forge view is shown. }
procedure TGittanToolbar.DrawBanner(const ABounds: NSRect);
var
  P: NSBezierPath;
  W, H, S, X, Y: double;
  Fill, Ink: NSColor;
  G: NSRect;
begin
  W := ABounds.size.width;
  H := ABounds.size.height;
  P := NSBezierPath.bezierPath;
  P.moveToPoint(NSMakePoint(0, 0));
  P.lineToPoint(NSMakePoint(W, 0));
  P.lineToPoint(NSMakePoint(W, H));
  P.lineToPoint(NSMakePoint(W / 2, H - BannerNotch));
  P.lineToPoint(NSMakePoint(0, H));
  P.closePath;
  P.setLineJoinStyle(NSRoundLineJoinStyle);
  if FForgeShown then
  begin
    Fill := NSColor.systemBlueColor;
    if FBannerHot then
      Fill := Fill.colorWithAlphaComponent(0.85);
    Ink := NSColor.whiteColor;
  end
  else
  begin
    if FBannerHot or FBannerPressed then
      Fill := NSColor.labelColor.colorWithAlphaComponent(0.16)
    else
      Fill := NSColor.labelColor.colorWithAlphaComponent(0.08);
    if FBannerHot then
      Ink := NSColor.labelColor
    else
      Ink := NSColor.secondaryLabelColor;
  end;
  Fill.setFill;
  P.fill;
  { The globe in the ribbon's body, above the notch: a circle, a
    narrower one in it and a line across. }
  S := 16;
  X := (W - S) / 2;
  Y := (H - BannerNotch - S) / 2 + 3;
  G := NSMakeRect(X, Y, S, S);
  Ink.setStroke;
  StrokeOval(G, 1.3);
  StrokeOval(NSMakeRect(X + S * 5 / 14, Y, S * 4 / 14, S), 1.3);
  StrokeLine(X, Y + S / 2, X + S, Y + S / 2, Ink, 1.3);
end;

procedure TGittanToolbar.BannerDown;
begin
  FBannerPressed := True;
  FBanner.setNeedsDisplay_(True);
end;

{ The release on the banner asks for the forge view. }
procedure TGittanToolbar.BannerUp(AEvent: NSEvent);
var
  P: NSPoint;
  Pressed: boolean;
begin
  Pressed := FBannerPressed;
  FBannerPressed := False;
  FBanner.setNeedsDisplay_(True);
  P := FBanner.convertPoint_fromView(AEvent.locationInWindow, nil);
  if Pressed and PointIn(P, FBanner.bounds) and Assigned(FOnForge) then
    FOnForge(Self);
end;

procedure TGittanToolbar.BannerHover(AHot: boolean);
begin
  FBannerHot := AHot;
  FBanner.setNeedsDisplay_(True);
end;

procedure TGittanToolbar.SetTabs(const ACaptions, AHints: array of string;
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
  FActive := AActive;
  if FHot > High(FCaptions) then
    FHot := -1;
  if FStrip <> nil then
    FStrip.setNeedsDisplay_(True);
end;

procedure TGittanToolbar.SetNav(ABack, AForward: boolean;
  const ABackHint, AForwardHint: string);
begin
  if (ABack = FCanBack) and (AForward = FCanForward) and (ABackHint = FBackHint) and
    (AForwardHint = FForwardHint) then
    Exit;
  FCanBack := ABack;
  FCanForward := AForward;
  FBackHint := ABackHint;
  FForwardHint := AForwardHint;
  if FStrip <> nil then
    FStrip.setNeedsDisplay_(True);
end;

function TGittanToolbar.NavRect(ANav: integer; const ABounds: NSRect): NSRect;
begin
  Result := NSMakeRect(Ord(ANav = NavForward) * (NavWidth + NavGap),
    (ABounds.size.height - NavHeight) / 2, NavWidth, NavHeight);
end;

function TGittanToolbar.NavEnabled(ANav: integer): boolean;
begin
  Result := ((ANav = NavBack) and FCanBack) or ((ANav = NavForward) and FCanForward);
end;

{ A chevron pointing left (back) or right (forward), on a rounded shade
  under the mouse; dim while there is nowhere to go. }
procedure TGittanToolbar.DrawNav(ANav: integer; const ABounds: NSRect);
var
  R: NSRect;
  Ink: NSColor;
  CX, CY, D: double;
begin
  R := NavRect(ANav, ABounds);
  if NavEnabled(ANav) and (FHotNav = ANav) then
  begin
    NSColor.labelColor.colorWithAlphaComponent(0.10).setFill;
    NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius(R, 5, 5).fill;
  end;
  if NavEnabled(ANav) then
    Ink := NSColor.secondaryLabelColor
  else
    Ink := NSColor.labelColor.colorWithAlphaComponent(0.22);
  CX := R.origin.x + R.size.width / 2;
  CY := R.origin.y + R.size.height / 2;
  D := 3.5;
  if ANav = NavBack then
  begin
    StrokeLine(CX + D / 2, CY - 2 * D, CX - D, CY, Ink, 1.6);
    StrokeLine(CX - D, CY, CX + D / 2, CY + 2 * D, Ink, 1.6);
  end
  else
  begin
    StrokeLine(CX - D / 2, CY - 2 * D, CX + D, CY, Ink, 1.6);
    StrokeLine(CX + D, CY, CX - D / 2, CY + 2 * D, Ink, 1.6);
  end;
end;

{ What the banner keeps the tabs out of. }
function TGittanToolbar.GlobeRoom: double;
begin
  if FForgeVisible then
    Result := GlobeWidth
  else
    Result := 0;
end;

function TGittanToolbar.TabWidth(AWidth: double): double;
begin
  if Length(FCaptions) = 0 then
    Exit(MaxTabWidth);
  if FFixed then
    Result := (AWidth - NavRoom - GlobeRoom) / Length(FCaptions)
  else
    Result := (AWidth - NavRoom - PlusWidth - GlobeRoom) / Length(FCaptions);
  Result := Max(MinTabWidth, Min(MaxTabWidth, Result));
end;

function TGittanToolbar.TabRect(AIndex: integer; const ABounds: NSRect): NSRect;
var
  W: double;
begin
  W := TabWidth(ABounds.size.width);
  Result := NSMakeRect(NavRoom + AIndex * W, 3, W - TabGap, ABounds.size.height - 6);
end;

function TGittanToolbar.CloseRect(const ATab: NSRect): NSRect;
begin
  Result := NSMakeRect(ATab.origin.x + ATab.size.width - CrossSize - 6,
    ATab.origin.y + (ATab.size.height - CrossSize) / 2, CrossSize, CrossSize);
end;

function TGittanToolbar.PlusRect(const ABounds: NSRect): NSRect;
var
  X: double;
begin
  X := NavRoom + Length(FCaptions) * TabWidth(ABounds.size.width);
  Result := NSMakeRect(X + 2, (ABounds.size.height - 22) / 2, 22, 22);
end;

procedure TGittanToolbar.HitTest(const APoint: NSPoint; const ABounds: NSRect;
  out AIndex: integer; out AClose, APlus: boolean; out ANav: integer);
var
  i: integer;
  R: NSRect;
begin
  AIndex := -1;
  AClose := False;
  APlus := False;
  ANav := NavNone;
  if PointIn(APoint, NavRect(NavBack, ABounds)) then
    ANav := NavBack
  else if PointIn(APoint, NavRect(NavForward, ABounds)) then
    ANav := NavForward;
  if ANav <> NavNone then
    Exit;
  APlus := not FFixed and PointIn(APoint, PlusRect(ABounds));
  if APlus then
    Exit;
  for i := 0 to High(FCaptions) do
  begin
    R := TabRect(i, ABounds);
    if PointIn(APoint, R) then
    begin
      AIndex := i;
      AClose := not FFixed and PointIn(APoint, CloseRect(R));
      Exit;
    end;
  end;
end;

{ The shown tab is a filled, rounded box, as is a hovered one, fainter;
  the others are their names alone, a faint line between two of them. The cross shows on the shown and
  the hovered tab, on a round shade while the mouse is on it. }
procedure TGittanToolbar.Draw(const ABounds: NSRect);
var
  i: integer;
  R, C, T: NSRect;
  Dark, Shown, Hover: boolean;
  Fill, Text, Cross: NSColor;
  Para: NSMutableParagraphStyle;
  Font: NSFont;
  Attrs: NSDictionary;
  LineH: double;
begin
  Dark := DarkAppearance;
  Font := NSFont.systemFontOfSize(12);
  LineH := Font.ascender - Font.descender;
  Para := NSMutableParagraphStyle.alloc.init;
  Para.setLineBreakMode(NSLineBreakByTruncatingTail);
  try
    DrawNav(NavBack, ABounds);
    DrawNav(NavForward, ABounds);
    for i := 0 to High(FCaptions) do
    begin
      R := TabRect(i, ABounds);
      Shown := i = FActive;
      Hover := (i = FHot) and not Shown;
      if Shown or Hover then
      begin
        if Shown and Dark then
          Fill := NSColor.whiteColor.colorWithAlphaComponent(0.13)
        else if Shown then
          Fill := NSColor.whiteColor.colorWithAlphaComponent(0.85)
        else
          Fill := NSColor.labelColor.colorWithAlphaComponent(0.06);
        Fill.setFill;
        NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius(R, 6, 6).fill;
        if Shown and not Dark then
        begin
          NSColor.blackColor.colorWithAlphaComponent(0.10).setStroke;
          NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius(
            NSInsetRect(R, 0.5, 0.5), 6, 6).stroke;
        end;
      end;
      { A faint line parts two tabs that are neither shown nor hovered. }
      if (i < High(FCaptions)) and not Shown and (i <> FHot) and (i + 1 <> FActive) and
        (i + 1 <> FHot) then
        StrokeLine(R.origin.x + R.size.width + TabGap / 2, R.origin.y + 6,
          R.origin.x + R.size.width + TabGap / 2, R.origin.y + R.size.height - 6,
          NSColor.labelColor.colorWithAlphaComponent(0.15), 1);
      if Shown then
        Text := NSColor.labelColor
      else
        Text := NSColor.secondaryLabelColor;
      Attrs := NSDictionary.dictionaryWithObjectsAndKeys(Font, NSFontAttributeName,
        Text, NSForegroundColorAttributeName, Para, NSParagraphStyleAttributeName, nil);
      T := NSMakeRect(R.origin.x + 10, R.origin.y + (R.size.height - LineH) / 2,
        R.size.width - 20 - Ord(not FFixed) * CrossSize, LineH);
      { News: a dot before the name, which moves over for it. }
      if FMarks[i] then
      begin
        NSColor.systemBlueColor.setFill;
        NSBezierPath.bezierPathWithOvalInRect(NSMakeRect(T.origin.x,
          R.origin.y + R.size.height / 2 - 3, 6, 6)).fill;
        T.origin.x := T.origin.x + 11;
        T.size.width := T.size.width - 11;
      end;
      NSStr(FCaptions[i]).drawInRect_withAttributes(T, Attrs);
      if not FFixed and (Shown or (i = FHot)) then
      begin
        C := CloseRect(R);
        if (i = FHot) and FHotClose then
        begin
          NSColor.labelColor.colorWithAlphaComponent(0.15).setFill;
          NSBezierPath.bezierPathWithOvalInRect(C).fill;
        end;
        Cross := NSColor.secondaryLabelColor;
        StrokeLine(C.origin.x + 5, C.origin.y + 5, C.origin.x + C.size.width - 5,
          C.origin.y + C.size.height - 5, Cross, 1.3);
        StrokeLine(C.origin.x + C.size.width - 5, C.origin.y + 5, C.origin.x + 5,
          C.origin.y + C.size.height - 5, Cross, 1.3);
      end;
    end;
    if FFixed then
      Exit;
    C := PlusRect(ABounds);
    if FHotPlus then
    begin
      NSColor.labelColor.colorWithAlphaComponent(0.10).setFill;
      NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius(C, 5, 5).fill;
    end;
    Cross := NSColor.secondaryLabelColor;
    StrokeLine(C.origin.x + C.size.width / 2, C.origin.y + 6,
      C.origin.x + C.size.width / 2, C.origin.y + C.size.height - 6, Cross, 1.4);
    StrokeLine(C.origin.x + 6, C.origin.y + C.size.height / 2,
      C.origin.x + C.size.width - 6, C.origin.y + C.size.height / 2, Cross, 1.4);
  finally
    Para.release;
  end;
end;

{ A tab is selected as it is pressed; the cross, the plus and a chevron
  act on the release, if the mouse is still on them. The empty part
  moves the window, and a double click there zooms it; so does a dim
  chevron. }
procedure TGittanToolbar.MouseDown(AEvent: NSEvent);
var
  P: NSPoint;
  Index, Nav: integer;
  InCross, InPlus: boolean;
begin
  P := FStrip.convertPoint_fromView(AEvent.locationInWindow, nil);
  HitTest(P, FStrip.bounds, Index, InCross, InPlus, Nav);
  FPressed := -1;
  if NavEnabled(Nav) then
  begin
    if Nav = NavBack then
      FPressed := BackPart
    else
      FPressed := ForwardPart;
  end
  else if InPlus then
    FPressed := PlusPart
  else if (Index >= 0) and InCross then
    FPressed := Index
  else if Index >= 0 then
  begin
    if Assigned(FOnSelect) then
      FOnSelect(Self, Index);
  end
  else if AEvent.clickCount = 2 then
    FWindow.performZoom(nil)
  else
    FWindow.performWindowDragWithEvent(AEvent);
end;

procedure TGittanToolbar.MouseUp(AEvent: NSEvent);
var
  P: NSPoint;
  Index, Pressed, Nav: integer;
  InCross, InPlus: boolean;
begin
  Pressed := FPressed;
  FPressed := -1;
  if Pressed = -1 then
    Exit;
  P := FStrip.convertPoint_fromView(AEvent.locationInWindow, nil);
  HitTest(P, FStrip.bounds, Index, InCross, InPlus, Nav);
  if (Pressed = BackPart) and (Nav = NavBack) then
  begin
    if FCanBack and Assigned(FOnBack) then
      FOnBack(Self);
  end
  else if (Pressed = ForwardPart) and (Nav = NavForward) then
  begin
    if FCanForward and Assigned(FOnForward) then
      FOnForward(Self);
  end
  else if (Pressed = PlusPart) and InPlus then
  begin
    if Assigned(FOnNew) then
      FOnNew(Self);
  end
  else if (Pressed >= 0) and InCross and (Index = Pressed) then
  begin
    if Assigned(FOnClose) then
      FOnClose(Self, Index);
  end;
end;

{ A middle click closes the tab under the mouse. }
procedure TGittanToolbar.OtherMouseUp(AEvent: NSEvent);
var
  P: NSPoint;
  Index, Nav: integer;
  InCross, InPlus: boolean;
begin
  if (AEvent.buttonNumber <> 2) or FFixed then
    Exit;
  P := FStrip.convertPoint_fromView(AEvent.locationInWindow, nil);
  HitTest(P, FStrip.bounds, Index, InCross, InPlus, Nav);
  if (Index >= 0) and Assigned(FOnClose) then
    FOnClose(Self, Index);
end;

procedure TGittanToolbar.MouseMoved(AEvent: NSEvent);
var
  P: NSPoint;
  Index, Nav: integer;
  InCross, InPlus: boolean;
begin
  P := FStrip.convertPoint_fromView(AEvent.locationInWindow, nil);
  HitTest(P, FStrip.bounds, Index, InCross, InPlus, Nav);
  if (Index = FHot) and (InCross = FHotClose) and (InPlus = FHotPlus) and
    (Nav = FHotNav) then
    Exit;
  if (Index <> FHot) or (Nav <> FHotNav) then
    if Nav = NavBack then
      FStrip.setToolTip(NSStr(FBackHint))
    else if Nav = NavForward then
      FStrip.setToolTip(NSStr(FForwardHint))
    else if (Index >= 0) and (FHints[Index] <> '') then
      FStrip.setToolTip(NSStr(FHints[Index]))
    else
      FStrip.setToolTip(nil);
  FHot := Index;
  FHotClose := InCross;
  FHotPlus := InPlus;
  FHotNav := Nav;
  FStrip.setNeedsDisplay_(True);
end;

{ Whether a press at APoint, in AView's coordinates, moves the window:
  in the title bar's row (above the content's layout rect, which leaves
  it out), outside the strip and the traffic lights; not in full screen,
  where the row is not the window's. The banner is above the area. }
function TGittanToolbar.DragAt(const APoint: NSPoint; AView: NSView): boolean;
var
  P: NSPoint;
  Button: NSButton;
  B: NSWindowButton;
begin
  Result := False;
  if (FWindow.styleMask and NSFullScreenWindowMask) <> 0 then
    Exit;
  P := AView.convertPoint_toView(APoint, nil);
  if P.y < FWindow.contentLayoutRect.origin.y + FWindow.contentLayoutRect.size.height then
    Exit;
  if (FStrip.window = FWindow) and
    PointIn(FStrip.convertPoint_fromView(P, nil), FStrip.bounds) then
    Exit;
  for B := NSWindowCloseButton to NSWindowZoomButton do
  begin
    Button := FWindow.standardWindowButton(B);
    if (Button <> nil) and
      PointIn(Button.convertPoint_fromView(P, nil), Button.bounds) then
      Exit;
  end;
  Result := True;
end;

procedure TGittanToolbar.MouseExited;
begin
  FHot := -1;
  FHotClose := False;
  FHotPlus := False;
  FHotNav := NavNone;
  FStrip.setNeedsDisplay_(True);
end;

end.
