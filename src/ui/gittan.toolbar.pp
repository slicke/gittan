{ The window's toolbar and its tabs (macOS).

  The title bar takes the mouse in the strip it covers, so the LCL's own
  controls cannot be put there (see gittan.titlebar.pp). An NSToolbar in
  the unified style can: it makes the strip taller, so the traffic
  lights sit in a row of a tab bar's height, and its items are native
  and take clicks. Its one item is the tab strip, a view of its own
  (TGittanTabStrip) that stretches from the traffic lights to the right
  edge, as Firefox's tabs do: a tab per open repository, the one shown
  filled, then a plus that opens a new tab.

  The strip draws the tabs itself in the system's colors, so it follows
  the window's appearance; a tab with news (something happened in its
  frame while another was shown) has a blue dot before its name. A
  click on a tab selects it at once; the
  cross on the shown or hovered tab, or a middle click, closes it; the
  plus asks for a new tab. At the strip's right end a globe (SetForge;
  there while there is a forge, filled while the forge view is shown)
  asks for the forge view (OnForge). A press on the empty part moves
  the window and a double click there zooms it, as on the title bar.
  The full path of the tab under the mouse is its tooltip, the forge's
  name the globe's.

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
    FCaptions, FHints: array of string;
    FMarks: array of boolean;
    FActive: integer;
    { The tab under the mouse (-1 for none), whether the mouse is on its
      cross, on the plus; the cross or plus pressed (-1 for none,
      PlusPart for the plus). }
    FHot: integer;
    FHotClose, FHotPlus, FHotGlobe: boolean;
    FPressed: integer;
    { The globe: whether it is there, whether the forge view is shown,
      and its tooltip. }
    FForgeVisible, FForgeShown: boolean;
    FForgeHint: string;
    FOnSelect, FOnClose: TGittanTabEvent;
    FOnNew, FOnForge: TNotifyEvent;
    function GlobeRoom: double;
    function TabWidth(AWidth: double): double;
    function TabRect(AIndex: integer; const ABounds: NSRect): NSRect;
    function CloseRect(const ATab: NSRect): NSRect;
    function PlusRect(const ABounds: NSRect): NSRect;
    function GlobeRect(const ABounds: NSRect): NSRect;
    procedure HitTest(const APoint: NSPoint; const ABounds: NSRect;
      out AIndex: integer; out AClose, APlus, AGlobe: boolean);
    procedure Draw(const ABounds: NSRect);
    procedure MouseDown(AEvent: NSEvent);
    procedure MouseUp(AEvent: NSEvent);
    procedure OtherMouseUp(AEvent: NSEvent);
    procedure MouseMoved(AEvent: NSEvent);
    procedure MouseExited;
  public
    {** Puts the toolbar with the tab strip on the window of the form
      whose handle is AHandle and hides the window's title. Answers nil
      before macOS 11 or without a window. }
    class function Install(AHandle: PtrUInt): TGittanToolbar;
    destructor Destroy; override;
    {** The tabs, left to right: ACaptions are their names, AHints their
      tooltips (the paths), AMarks those with news (a dot before the
      name), AActive the one shown. }
    procedure SetTabs(const ACaptions, AHints: array of string;
      const AMarks: array of boolean; AActive: integer);
    {** The globe at the right end: shown while AVisible (there is a
      forge), filled while AShown (the forge view is shown), AHint its
      tooltip (the forge's name). }
    procedure SetForge(AVisible, AShown: boolean; const AHint: string);
    {** A click on a tab: show it. }
    property OnSelect: TGittanTabEvent read FOnSelect write FOnSelect;
    {** The cross or a middle click on a tab: close it. }
    property OnClose: TGittanTabEvent read FOnClose write FOnClose;
    {** The plus: a new tab. }
    property OnNew: TNotifyEvent read FOnNew write FOnNew;
    {** The globe: the forge view, or back from it. }
    property OnForge: TNotifyEvent read FOnForge write FOnForge;
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
  { The room the globe takes at the right end, and its button. }
  GlobeWidth = 34;
  GlobeSize = 24;
  { FPressed for the plus and for the globe. }
  PlusPart = -2;
  GlobePart = -3;

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
    { Between these it takes the width the toolbar has. }
    Result.setMinSize(NSMakeSize(PlusWidth + MinTabWidth, StripHeight));
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
end;

destructor TGittanToolbar.Destroy;
begin
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
  FForgeVisible := AVisible;
  FForgeShown := AShown;
  FForgeHint := AHint;
  if not AVisible then
    FHotGlobe := False;
  if FStrip <> nil then
    FStrip.setNeedsDisplay_(True);
end;

procedure TGittanToolbar.SetTabs(const ACaptions, AHints: array of string;
  const AMarks: array of boolean; AActive: integer);
var
  i: integer;
begin
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

{ What the globe keeps the tabs out of. }
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
  Result := (AWidth - PlusWidth - GlobeRoom) / Length(FCaptions);
  Result := Max(MinTabWidth, Min(MaxTabWidth, Result));
end;

function TGittanToolbar.TabRect(AIndex: integer; const ABounds: NSRect): NSRect;
var
  W: double;
begin
  W := TabWidth(ABounds.size.width);
  Result := NSMakeRect(AIndex * W, 3, W - TabGap, ABounds.size.height - 6);
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
  X := Length(FCaptions) * TabWidth(ABounds.size.width);
  Result := NSMakeRect(X + 2, (ABounds.size.height - 22) / 2, 22, 22);
end;

{ The globe's button, at the right end. }
function TGittanToolbar.GlobeRect(const ABounds: NSRect): NSRect;
begin
  Result := NSMakeRect(ABounds.size.width - GlobeWidth + (GlobeWidth - GlobeSize) / 2,
    (ABounds.size.height - GlobeSize) / 2, GlobeSize, GlobeSize);
end;

procedure TGittanToolbar.HitTest(const APoint: NSPoint; const ABounds: NSRect;
  out AIndex: integer; out AClose, APlus, AGlobe: boolean);
var
  i: integer;
  R: NSRect;
begin
  AIndex := -1;
  AClose := False;
  APlus := False;
  AGlobe := FForgeVisible and PointIn(APoint, GlobeRect(ABounds));
  if AGlobe then
    Exit;
  APlus := PointIn(APoint, PlusRect(ABounds));
  if APlus then
    Exit;
  for i := 0 to High(FCaptions) do
  begin
    R := TabRect(i, ABounds);
    if PointIn(APoint, R) then
    begin
      AIndex := i;
      AClose := PointIn(APoint, CloseRect(R));
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
        R.size.width - 20 - CrossSize, LineH);
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
      if Shown or (i = FHot) then
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
    { The globe: filled as the shown tab while the forge view is shown,
      fainter under the mouse; a circle with a narrower one in it and
      a line across, as the sidebar drew it. }
    if FForgeVisible then
    begin
      C := GlobeRect(ABounds);
      if FForgeShown or FHotGlobe then
      begin
        if FForgeShown and Dark then
          Fill := NSColor.whiteColor.colorWithAlphaComponent(0.13)
        else if FForgeShown then
          Fill := NSColor.whiteColor.colorWithAlphaComponent(0.85)
        else
          Fill := NSColor.labelColor.colorWithAlphaComponent(0.10);
        Fill.setFill;
        NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius(C, 5, 5).fill;
        if FForgeShown and not Dark then
        begin
          NSColor.blackColor.colorWithAlphaComponent(0.10).setStroke;
          NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius(
            NSInsetRect(C, 0.5, 0.5), 5, 5).stroke;
        end;
      end;
      if FForgeShown then
        Cross := NSColor.labelColor
      else
        Cross := NSColor.secondaryLabelColor;
      Cross.setStroke;
      R := NSInsetRect(C, 5, 5);
      StrokeOval(R, 1.3);
      StrokeOval(NSMakeRect(R.origin.x + R.size.width * 5 / 14, R.origin.y,
        R.size.width * 4 / 14, R.size.height), 1.3);
      StrokeLine(R.origin.x, R.origin.y + R.size.height / 2, R.origin.x + R.size.width,
        R.origin.y + R.size.height / 2, Cross, 1.3);
    end;
  finally
    Para.release;
  end;
end;

{ A tab is selected as it is pressed; the cross and the plus act on the
  release, if the mouse is still on them. The empty part moves the
  window, and a double click there zooms it. }
procedure TGittanToolbar.MouseDown(AEvent: NSEvent);
var
  P: NSPoint;
  Index: integer;
  InCross, InPlus, InGlobe: boolean;
begin
  P := FStrip.convertPoint_fromView(AEvent.locationInWindow, nil);
  HitTest(P, FStrip.bounds, Index, InCross, InPlus, InGlobe);
  FPressed := -1;
  if InGlobe then
    FPressed := GlobePart
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
  Index, Pressed: integer;
  InCross, InPlus, InGlobe: boolean;
begin
  Pressed := FPressed;
  FPressed := -1;
  if Pressed = -1 then
    Exit;
  P := FStrip.convertPoint_fromView(AEvent.locationInWindow, nil);
  HitTest(P, FStrip.bounds, Index, InCross, InPlus, InGlobe);
  if (Pressed = GlobePart) and InGlobe then
  begin
    if Assigned(FOnForge) then
      FOnForge(Self);
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
  Index: integer;
  InCross, InPlus, InGlobe: boolean;
begin
  if AEvent.buttonNumber <> 2 then
    Exit;
  P := FStrip.convertPoint_fromView(AEvent.locationInWindow, nil);
  HitTest(P, FStrip.bounds, Index, InCross, InPlus, InGlobe);
  if (Index >= 0) and Assigned(FOnClose) then
    FOnClose(Self, Index);
end;

procedure TGittanToolbar.MouseMoved(AEvent: NSEvent);
var
  P: NSPoint;
  Index: integer;
  InCross, InPlus, InGlobe: boolean;
begin
  P := FStrip.convertPoint_fromView(AEvent.locationInWindow, nil);
  HitTest(P, FStrip.bounds, Index, InCross, InPlus, InGlobe);
  if (Index = FHot) and (InCross = FHotClose) and (InPlus = FHotPlus) and
    (InGlobe = FHotGlobe) then
    Exit;
  if (Index <> FHot) or (InGlobe <> FHotGlobe) then
    if Index >= 0 then
      FStrip.setToolTip(NSStr(FHints[Index]))
    else if InGlobe then
      FStrip.setToolTip(NSStr(FForgeHint))
    else
      FStrip.setToolTip(nil);
  FHot := Index;
  FHotClose := InCross;
  FHotPlus := InPlus;
  FHotGlobe := InGlobe;
  FStrip.setNeedsDisplay_(True);
end;

procedure TGittanToolbar.MouseExited;
begin
  FHot := -1;
  FHotClose := False;
  FHotPlus := False;
  FHotGlobe := False;
  FStrip.setNeedsDisplay_(True);
end;

end.
