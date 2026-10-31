unit gittan.brushcache;

{** The LCL's brush cache without its theme change fault. When the system's
  appearance or colors change, the widgetset calls UpdateHandleObjects(True)
  (Cocoa, GTK 2 and 3, Windows on WM_SYSCOLORCHANGE), which clears
  BrushResourceCache, and the cache deletes every brush it holds, also
  the ones a TBrush still uses. On Cocoa a brush selected in no device
  context goes at once. The TBrush asks for a new handle on its next use,
  but first looks its old one up in the cache to let it go, and once a new
  brush has been made at the old one's address it lets go of that one:
  its count runs out while another TBrush still uses it, the cache deletes
  it, and the next canvas to select that TBrush's handle reads a freed
  object (an access violation in CheckGDIObj, seen when a label's font
  changed after a switch between light and dark).

  TGittanBrushCache takes a brush that is still in use out of the cache
  without deleting it, so its address cannot come back for another brush;
  the TBrush drops the handle on its next use and the brush is left over,
  a few dozen small objects for each change of the appearance. A brush
  nothing uses is deleted as before. The unit puts it in place of the
  LCL's as it loads; the LCL's own is left as it is, since freeing it
  would delete the brushes in use the same way. }

{$mode objfpc}{$H+}

interface

uses
  Graphics, LCLResCache;

type
  TGittanBrushCache = class(TBrushHandleCache)
  protected
    procedure RemoveItem(Item: TResourceCacheItem); override;
  end;

implementation

procedure TGittanBrushCache.RemoveItem(Item: TResourceCacheItem);
begin
  if Item.ReferenceCount = 0 then
  begin
    inherited RemoveItem(Item);
    Exit;
  end;
  { TResourceCache.RemoveItem, without TBrushHandleCache's DeleteObject. }
  if not FDestroying then
  begin
    while Item.FirstDescriptor <> nil do
      Item.FirstDescriptor.Free;
    FItems.Remove(Item);
  end;
end;

initialization
  BrushResourceCache := TGittanBrushCache.Create;

end.
