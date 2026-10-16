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

  The unit uses CocoaAll alone; umain keeps it behind LCLCocoa, so the
  other widgetsets never see it. }
unit gittan.titlebar;

{$mode objfpc}{$H+}
{$modeswitch objectivec1}

interface

{** Lets the content of the form whose handle AHandle is reach under
  the title bar and makes the bar transparent. Returns the height of
  the strip the title bar covers, in LCL pixels, or 0 when the handle
  has no window yet. }
function ExtendUnderTitleBar(AHandle: PtrUInt): integer;

implementation

uses
  CocoaAll, cocoa_extra;

function ExtendUnderTitleBar(AHandle: PtrUInt): integer;
var
  Win: NSWindow;
begin
  Result := 0;
  if AHandle = 0 then
    Exit;
  Win := NSView(AHandle).window;
  if Win = nil then
    Exit;
  Win.setStyleMask(Win.styleMask or NSFullSizeContentViewWindowMask);
  Win.setTitlebarAppearsTransparent(True);
  { No line under the title: the content is what is under it. }
  if NSAppKitVersionNumber >= NSAppKitVersionNumber11_0 then
    Win.setTitlebarSeparatorStyle(NSTitlebarSeparatorStyleNone);
  { contentLayoutRect is the content view less the title bar. }
  Result := Round(Win.contentView.frame.size.height -
    Win.contentLayoutRect.size.height);
end;

end.
