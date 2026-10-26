{ The window's content under its title bar (macOS).

  Cocoa draws the title bar as a strip of its own over the window.
  ExtendUnderTitleBar makes it transparent and lets the content view
  reach up behind it (NSFullSizeContentViewWindowMask), so the form
  paints the strip: the tree panel in its own shade on the left, the
  editor's background on the right, as the sidebars of Finder, Mail or
  Deezer run up to the top edge. The traffic lights and the title stay
  where they are, so the form keeps the strip's height free of controls.

  The title bar keeps the mouse in the strip it covers: a drag there
  moves the window and a double click zooms it, as before, and no LCL
  control under it gets a click (verified 2026-10-16: a panel's
  OnMouseDown never fires there). So the strip is left to the panels'
  own spacing, with nothing in it to click.

  ShowTitleBand puts a progress band along the top edge, over the title
  bar above the traffic lights, as a page's loading bar: two NSBoxes
  (a track and a fill) added to the window's content view, since the
  LCL's own controls are not drawn by Cocoa when they are a few pixels
  high (seen 2026-10-16: a TCustomControl under about 25 px shows
  nothing, a taller one fills its whole bounds with its color).

  Under a full size content view AppKit gives every scroll view that
  reaches under the title bar the bar's height as a top inset, and the
  LCL makes every windowed control one (TCocoaScrollView and its
  TCocoaManualScrollHost). The LCL places their content itself, and a
  view whose inset came after the LCL had placed it was scrolled down
  by the inset (seen 2026-10-26, once the form's content moved into a
  frame: the sidebar and the summary sat a title bar's height low). A
  category on TCocoaScrollView turns the automatic insets off for all
  of them, the frame's, its panels' and those made later alike.

  The unit uses CocoaAll and the LCL's Cocoa units; umain keeps it
  behind LCLCocoa, so the other widgetsets never see it. }
unit gittan.titlebar;

{$mode objfpc}{$H+}
{$modeswitch objectivec1}

interface

{** Lets the content of the form whose handle AHandle is reach under
  the title bar and makes the bar transparent. Returns the height of
  the strip the title bar covers, in LCL pixels, or 0 when the handle
  has no window yet. }
function ExtendUnderTitleBar(AHandle: PtrUInt): integer;

{** Shows the band along the top edge of the form's window, APos of
  ATotal filled (a little at least, past the window's rounded corner),
  in the colors ATrack and AFill (RGB as ColorToRGB gives it). The band
  is made on the first call. }
procedure ShowTitleBand(AHandle: PtrUInt; APos, ATotal: integer;
  ATrack, AFill: longword);

{** Hides the band. }
procedure HideTitleBand(AHandle: PtrUInt);

implementation

uses
  Math, CocoaAll, cocoa_extra, CocoaScrolling;

type
  { No inset from the title bar for the LCL's scroll views (see above). }
  TCocoaScrollViewNoTitleInset = objccategory(TCocoaScrollView)
    function automaticallyAdjustsContentInsets: ObjCBOOL; reintroduce;
  end;

function TCocoaScrollViewNoTitleInset.automaticallyAdjustsContentInsets: ObjCBOOL;
begin
  Result := False;
end;

const
  BandHeight = 3;
  { The least the fill is wide: the window's rounded corner hides the
    first pixels, so a fill of a few of 800 files showed nothing. }
  MinFill = 24;

var
  Track, Fill: NSBox;

function WindowOf(AHandle: PtrUInt): NSWindow;
begin
  if AHandle = 0 then
    Result := nil
  else
    Result := NSView(AHandle).window;
end;

function ExtendUnderTitleBar(AHandle: PtrUInt): integer;
var
  Win: NSWindow;
  NoInsets: NSEdgeInsets;
begin
  Result := 0;
  Win := WindowOf(AHandle);
  if Win = nil then
    Exit;
  Win.setStyleMask(Win.styleMask or NSFullSizeContentViewWindowMask);
  Win.setTitlebarAppearsTransparent(True);
  { No line under the title: the content is what is under it. }
  if NSAppKitVersionNumber >= NSAppKitVersionNumber11_0 then
    Win.setTitlebarSeparatorStyle(NSTitlebarSeparatorStyleNone);
  { The LCL's content view is a scroll view, which under a full size
    content view gets the title bar's height as a top inset, so a
    scroll over the strip moved the whole form down by it. }
  if Win.contentView.isKindOfClass(NSScrollView) then
  begin
    NSScrollView(Win.contentView).setAutomaticallyAdjustsContentInsets(False);
    NoInsets := Default(NSEdgeInsets);
    NSScrollView(Win.contentView).setContentInsets(NoInsets);
  end;
  { contentLayoutRect is the content view less the title bar. }
  Result := Round(Win.contentView.frame.size.height -
    Win.contentLayoutRect.size.height);
end;

function RGBColor(ARGB: longword): NSColor;
begin
  Result := NSColor.colorWithCalibratedRed_green_blue_alpha(
    (ARGB and $FF) / 255, ((ARGB shr 8) and $FF) / 255,
    ((ARGB shr 16) and $FF) / 255, 1);
end;

{ A box with a plain fill and nothing else, along the top edge of the
  view AAbove, over it in AParent, kept at the top as the window
  resizes. }
function MakeBand(AParent, AAbove: NSView): NSBox;
var
  R: NSRect;
begin
  R := AAbove.frame;
  Result := NSBox.alloc.initWithFrame(NSMakeRect(R.origin.x,
    R.origin.y + R.size.height - BandHeight, R.size.width, BandHeight));
  Result.setBoxType(NSBoxCustom);
  Result.setBorderType(NSNoBorder);
  Result.setBorderWidth(0);
  Result.setTitlePosition(NSNoTitle);
  Result.setContentViewMargins(NSMakeSize(0, 0));
  Result.setAutoresizingMask(NSViewWidthSizable or NSViewMinYMargin);
  AParent.addSubview_positioned_relativeTo(Result, NSWindowAbove, AAbove);
end;

procedure ShowTitleBand(AHandle: PtrUInt; APos, ATotal: integer;
  ATrack, AFill: longword);
var
  Win: NSWindow;
  R: NSRect;
begin
  Win := WindowOf(AHandle);
  if Win = nil then
    Exit;
  if Track = nil then
  begin
    { Above the content view, in the window's frame view: a subview of
      the content view (the LCL's scroll view) ends up under its
      content. }
    Track := MakeBand(Win.contentView.superview, Win.contentView);
    Fill := MakeBand(Win.contentView.superview, Track);
  end;
  Track.setFillColor(RGBColor(ATrack));
  Fill.setFillColor(RGBColor(AFill));
  R := Win.contentView.frame;
  if ATotal > 0 then
    R.size.width := Max(MinFill, R.size.width * APos / ATotal)
  else
    R.size.width := 0;
  R.origin.y := R.origin.y + R.size.height - BandHeight;
  R.size.height := BandHeight;
  Fill.setFrame(R);
  Track.setHidden(False);
  Fill.setHidden(False);
end;

procedure HideTitleBand(AHandle: PtrUInt);
begin
  if Track = nil then
    Exit;
  Track.setHidden(True);
  Fill.setHidden(True);
end;

end.
