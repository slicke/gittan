{ The window's toolbar (macOS).

  The title bar takes the mouse in the strip it covers, so the LCL's own
  controls cannot be put there (see gittan.titlebar.pp). An NSToolbar in
  the unified style can: it makes the strip taller, so the traffic
  lights sit in a row of a tab bar's height, as in Firefox or Safari,
  and its items are native and take clicks. For now it holds the
  application's name after the traffic lights; the tabs of the open
  repositories go there next. The filter, the change navigator and the
  actions of the view belong to a repository and are in its frame: the
  field over the tree and the file header's pills.

  The unit uses CocoaAll alone; uwindow keeps it behind LCLCocoa, so the
  other widgetsets never see it. }
unit gittan.toolbar;

{$mode objfpc}{$H+}
{$modeswitch objectivec1}

interface

uses
  Classes, CocoaAll;

type
  { TGittanToolbar }

  TGittanToolbar = class
  private
    FWindow: NSWindow;
    FToolbar: NSToolbar;
    FDelegate: NSObject;
    FName: string;
    FOnName: TNotifyEvent;
  public
    {** Puts the toolbar on the window of the form whose handle is AHandle,
      named AName on the left, and hides the window's title. Answers nil
      before macOS 11 or without a window. }
    class function Install(AHandle: PtrUInt; const AName: string): TGittanToolbar;
    destructor Destroy; override;
    {** A click on the name at the left. }
    property OnName: TNotifyEvent read FOnName write FOnName;
  end;

implementation

uses
  SysUtils, cocoa_extra;

type
  { The toolbar's delegate and the target of its items. }
  TGittanToolbarDelegate = objcclass(NSObject, NSToolbarDelegateProtocol)
  public
    Owner: TGittanToolbar;
    function toolbar_itemForItemIdentifier_willBeInsertedIntoToolbar(
      toolbar: NSToolbar; itemIdentifier: NSString; flag: ObjCBOOL): NSToolbarItem;
    function toolbarDefaultItemIdentifiers(toolbar: NSToolbar): NSArray;
    function toolbarAllowedItemIdentifiers(toolbar: NSToolbar): NSArray;
    procedure nameClicked(sender: id); message 'gittanNameClicked:';
  end;

const
  IdName = 'gittan.name';

function NSStr(const S: string): NSString;
begin
  Result := NSString.stringWithUTF8String(PChar(S));
end;

{ The name at the left as a button without a border, so a click on it
  reaches ATarget as gittanNameClicked: and it still reads as a label. }
function MakeNameButton(const AText: string; ATarget: id): NSButton;
begin
  Result := NSButton.alloc.initWithFrame(NSMakeRect(0, 0, 10, 10));
  Result.setTitle(NSStr(AText));
  Result.setBordered(False);
  Result.setFont(NSFont.boldSystemFontOfSize(15));
  Result.setTarget(ATarget);
  Result.setAction(objcselector('gittanNameClicked:'));
  Result.sizeToFit;
  Result.autorelease;
end;

{ TGittanToolbarDelegate }

function TGittanToolbarDelegate.toolbar_itemForItemIdentifier_willBeInsertedIntoToolbar(
  toolbar: NSToolbar; itemIdentifier: NSString; flag: ObjCBOOL): NSToolbarItem;
begin
  Result := nil;
  if itemIdentifier.isEqualToString(NSStr(IdName)) then
  begin
    Result := NSToolbarItem.alloc.initWithItemIdentifier(itemIdentifier);
    Result.setView(MakeNameButton(Owner.FName, Self));
    Result.autorelease;
  end;
end;

function TGittanToolbarDelegate.toolbarDefaultItemIdentifiers(toolbar: NSToolbar): NSArray;
begin
  Result := NSArray.arrayWithObjects(NSStr(IdName),
    NSToolbarFlexibleSpaceItemIdentifier, nil);
end;

function TGittanToolbarDelegate.toolbarAllowedItemIdentifiers(toolbar: NSToolbar): NSArray;
begin
  Result := toolbarDefaultItemIdentifiers(toolbar);
end;

procedure TGittanToolbarDelegate.nameClicked(sender: id);
begin
  if Assigned(Owner.FOnName) then
    Owner.FOnName(Owner);
end;

{ TGittanToolbar }

class function TGittanToolbar.Install(AHandle: PtrUInt; const AName: string): TGittanToolbar;
var
  Win: NSWindow;
  Delegate: TGittanToolbarDelegate;
begin
  Result := nil;
  if (AHandle = 0) or (NSAppKitVersionNumber < NSAppKitVersionNumber11_0) then
    Exit;
  Win := NSView(AHandle).window;
  if Win = nil then
    Exit;
  Result := TGittanToolbar.Create;
  Result.FWindow := Win;
  Result.FName := AName;
  Delegate := TGittanToolbarDelegate.alloc.init;
  Delegate.Owner := Result;
  Result.FDelegate := Delegate;
  Result.FToolbar := NSToolbar.alloc.initWithIdentifier(NSStr('gittan.toolbar'));
  Result.FToolbar.setDelegate(Delegate);
  Result.FToolbar.setDisplayMode(NSToolbarDisplayModeIconOnly);
  Result.FToolbar.setAllowsUserCustomization(False);
  Win.setToolbar(Result.FToolbar);
  Win.setToolbarStyle(NSWindowToolbarStyleUnified);
  { The name is on the left and the repository in the status bar. }
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
  if FDelegate <> nil then
    FDelegate.release;
  inherited Destroy;
end;

end.
