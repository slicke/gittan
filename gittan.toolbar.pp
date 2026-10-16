{ The window's toolbar (macOS).

  The title bar takes the mouse in the strip it covers, so the LCL's own
  controls cannot be put there (see gittan.titlebar.pp). An NSToolbar in
  the unified style can: it makes the strip taller and holds native items
  that take clicks, as Finder, Mail or Deezer do. From the left: the
  application's name after the traffic lights, the file filter as a
  native search field (rounded, with a magnifier and a clear button) in
  the middle, and on the right the change navigator (the counter, then
  the previous and next arrows) and the actions the view offers (Edit,
  Revert, Save, Open), which the file header shows as pills elsewhere.

  The navigator and the actions come and go with the view: Update
  removes the items after the fixed ones and inserts the ones wanted
  when the set changed, and sets the counter, the captions and the
  enabled states in place.

  The unit uses CocoaAll alone; umain keeps it behind LCLCocoa, so the
  other widgetsets never see it. }
unit gittan.toolbar;

{$mode objfpc}{$H+}
{$modeswitch objectivec1}

interface

uses
  Classes, CocoaAll;

type
  {** A key the search field passes on: VK_ESCAPE when it is already
    empty, VK_RETURN or VK_DOWN. }
  TGittanToolbarKeyEvent = procedure(Sender: TObject; var Key: word) of object;
  {** A click on the action at AIndex, in the order of SetActions. }
  TGittanToolbarActionEvent = procedure(Sender: TObject; AIndex: integer) of object;

  { TGittanToolbar }

  TGittanToolbar = class
  private
    FWindow: NSWindow;
    FToolbar: NSToolbar;
    FDelegate: NSObject;
    FSearch: NSSearchField;
    FCounter: NSTextField;
    FActions: array of string;
    FEnabled: array of boolean;
    FCurrent, FTotal: integer;
    FOnSearchChange: TNotifyEvent;
    FOnSearchKey: TGittanToolbarKeyEvent;
    FOnAction: TGittanToolbarActionEvent;
    FOnPrev, FOnNext: TNotifyEvent;
    function GetSearchText: string;
    procedure Update;
  public
    {** Puts the toolbar on the window of the form whose handle is AHandle,
      named AName on the left, with AHint in the empty search field, and
      hides the window's title. Answers nil before macOS 11 or without a
      window. }
    class function Install(AHandle: PtrUInt; const AName, AHint: string): TGittanToolbar;
    destructor Destroy; override;
    {** The action buttons, left to right, each enabled as AEnabled says;
      none for an empty array. }
    procedure SetActions(const ACaptions: array of string;
      const AEnabled: array of boolean);
    {** Shows the navigator at ACurrent of ATotal changes, or hides it when
      ATotal is 0. }
    procedure SetChanges(ACurrent, ATotal: integer);
    {** Focuses the search field with its text selected. }
    procedure FocusSearch;
    property SearchText: string read GetSearchText;
    property OnSearchChange: TNotifyEvent read FOnSearchChange write FOnSearchChange;
    property OnSearchKey: TGittanToolbarKeyEvent read FOnSearchKey write FOnSearchKey;
    property OnAction: TGittanToolbarActionEvent read FOnAction write FOnAction;
    property OnPrev: TNotifyEvent read FOnPrev write FOnPrev;
    property OnNext: TNotifyEvent read FOnNext write FOnNext;
  end;

implementation

uses
  SysUtils, LCLType, cocoa_extra;

type
  NSToolbarItemTitle = objccategory external (NSToolbarItem)
    procedure setTitle(newValue: NSString); message 'setTitle:'; { 10.15 }
  end;

  NSSegmentedControlTracking = objccategory external (NSSegmentedControl)
    procedure setTrackingMode(newValue: NSSegmentSwitchTracking);
      message 'setTrackingMode:';
  end;

  NSFontDigits = objccategory external (NSFont)
    class function monospacedDigitSystemFontOfSize_weight(fontSize: Double;
      weight: Double): NSFont; message 'monospacedDigitSystemFontOfSize:weight:'; { 10.11 }
  end;

  NSToolbarCentered = objccategory external (NSToolbar)
    procedure setCenteredItemIdentifier(newValue: NSString);
      message 'setCenteredItemIdentifier:'; { 10.14 }
  end;

  { The toolbar's delegate and the target of its items. }
  TGittanToolbarDelegate = objcclass(NSObject, NSToolbarDelegateProtocol,
    NSTextFieldDelegateProtocol)
  public
    Owner: TGittanToolbar;
    function toolbar_itemForItemIdentifier_willBeInsertedIntoToolbar(
      toolbar: NSToolbar; itemIdentifier: NSString; flag: ObjCBOOL): NSToolbarItem;
    function toolbarDefaultItemIdentifiers(toolbar: NSToolbar): NSArray;
    function toolbarAllowedItemIdentifiers(toolbar: NSToolbar): NSArray;
    function control_textView_doCommandBySelector(control: NSControl;
      textView: NSTextView; commandSelector: SEL): ObjCBOOL;
    procedure searchChanged(sender: id); message 'gittanSearchChanged:';
    procedure actionClicked(sender: id); message 'gittanActionClicked:';
    procedure navClicked(sender: id); message 'gittanNavClicked:';
  end;

const
  IdName = 'gittan.name';
  IdSearch = 'gittan.search';
  IdCounter = 'gittan.counter';
  IdNav = 'gittan.nav';
  IdAction = 'gittan.action.';
  { The items before the navigator and the actions: the name, a flexible
    space, the search field and a flexible space. }
  FixedItems = 4;
  MaxActions = 4;
  SearchWidth = 320;

function NSStr(const S: string): NSString;
begin
  Result := NSString.stringWithUTF8String(PChar(S));
end;

function SymbolImage(const AName: string): NSImage;
begin
  Result := NSImage.imageWithSystemSymbolName_accessibilityDescription(
    NSStr(AName), nil);
end;

{ A label that cannot be edited or selected, without a border or a
  background. }
function MakeLabel(const AText: string; AFont: NSFont): NSTextField;
begin
  Result := NSTextField.alloc.initWithFrame(NSMakeRect(0, 0, 10, 10));
  Result.setStringValue(NSStr(AText));
  Result.setEditable(False);
  Result.setSelectable(False);
  Result.setBezeled(False);
  Result.setBordered(False);
  Result.setDrawsBackground(False);
  Result.setFont(AFont);
  Result.sizeToFit;
  Result.autorelease;
end;

{ TGittanToolbarDelegate }

function TGittanToolbarDelegate.toolbar_itemForItemIdentifier_willBeInsertedIntoToolbar(
  toolbar: NSToolbar; itemIdentifier: NSString; flag: ObjCBOOL): NSToolbarItem;
var
  Search: NSSearchToolbarItem;
  Seg: NSSegmentedControl;
  Index: integer;
begin
  Result := nil;
  if itemIdentifier.isEqualToString(NSStr(IdName)) then
  begin
    Result := NSToolbarItem.alloc.initWithItemIdentifier(itemIdentifier);
    Result.setView(MakeLabel('Gittan', NSFont.boldSystemFontOfSize(15)));
  end
  else if itemIdentifier.isEqualToString(NSStr(IdSearch)) then
  begin
    Search := NSSearchToolbarItem.alloc.initWithItemIdentifier(itemIdentifier);
    Search.setSearchField(Owner.FSearch);
    { The item makes itself the field's delegate. }
    Owner.FSearch.setDelegate(NSTextFieldDelegateProtocol(Self));
    Search.setPreferredWidthForSearchField(SearchWidth);
    Result := Search;
  end
  else if itemIdentifier.isEqualToString(NSStr(IdCounter)) then
  begin
    Result := NSToolbarItem.alloc.initWithItemIdentifier(itemIdentifier);
    Result.setView(Owner.FCounter);
  end
  else if itemIdentifier.isEqualToString(NSStr(IdNav)) then
  begin
    Seg := NSSegmentedControl.alloc.initWithFrame(NSMakeRect(0, 0, 10, 10));
    Seg.setSegmentCount(2);
    Seg.setImage_forSegment(SymbolImage('chevron.up'), 0);
    Seg.setImage_forSegment(SymbolImage('chevron.down'), 1);
    Seg.setTrackingMode(NSSegmentSwitchTrackingMomentary);
    Seg.setTarget(Self);
    Seg.setAction(objcselector('gittanNavClicked:'));
    Seg.sizeToFit;
    Seg.autorelease;
    Result := NSToolbarItem.alloc.initWithItemIdentifier(itemIdentifier);
    Result.setView(Seg);
  end
  else if itemIdentifier.hasPrefix(NSStr(IdAction)) then
  begin
    Index := StrToIntDef(System.Copy(itemIdentifier.UTF8String, Length(IdAction) + 1,
      MaxInt), -1);
    Result := NSToolbarItem.alloc.initWithItemIdentifier(itemIdentifier);
    Result.setTag(Index);
    Result.setTarget(Self);
    Result.setAction(objcselector('gittanActionClicked:'));
    Result.setAutovalidates(False);
    Result.setBordered(True);
    { The caption is set by Update. }
    Result.setTitle(NSStr(' '));
  end;
  if Result <> nil then
    Result.autorelease;
end;

function TGittanToolbarDelegate.toolbarDefaultItemIdentifiers(toolbar: NSToolbar): NSArray;
begin
  Result := NSArray.arrayWithObjects(NSStr(IdName),
    NSToolbarFlexibleSpaceItemIdentifier, NSStr(IdSearch),
    NSToolbarFlexibleSpaceItemIdentifier, nil);
end;

function TGittanToolbarDelegate.toolbarAllowedItemIdentifiers(toolbar: NSToolbar): NSArray;
var
  A: NSMutableArray;
  i: integer;
begin
  A := NSMutableArray.arrayWithArray(toolbarDefaultItemIdentifiers(toolbar));
  A.addObject(NSStr(IdCounter));
  A.addObject(NSStr(IdNav));
  for i := 0 to MaxActions - 1 do
    A.addObject(NSStr(IdAction + IntToStr(i)));
  Result := A;
end;

{ Escape in an empty field, Enter and Down are passed on; Escape with
  text is the field's own and clears it. }
function TGittanToolbarDelegate.control_textView_doCommandBySelector(
  control: NSControl; textView: NSTextView; commandSelector: SEL): ObjCBOOL;
var
  Key: word;
begin
  Result := False;
  if commandSelector = objcselector('cancelOperation:') then
  begin
    if Owner.FSearch.stringValue.length > 0 then
      Exit;
    Key := VK_ESCAPE;
  end
  else if commandSelector = objcselector('insertNewline:') then
    Key := VK_RETURN
  else if commandSelector = objcselector('moveDown:') then
    Key := VK_DOWN
  else
    Exit;
  if Assigned(Owner.FOnSearchKey) then
    Owner.FOnSearchKey(Owner, Key);
  Result := Key = 0;
end;

procedure TGittanToolbarDelegate.searchChanged(sender: id);
begin
  if Assigned(Owner.FOnSearchChange) then
    Owner.FOnSearchChange(Owner);
end;

procedure TGittanToolbarDelegate.actionClicked(sender: id);
begin
  if Assigned(Owner.FOnAction) then
    Owner.FOnAction(Owner, NSToolbarItem(sender).tag);
end;

procedure TGittanToolbarDelegate.navClicked(sender: id);
begin
  if NSSegmentedControl(sender).selectedSegment = 0 then
  begin
    if Assigned(Owner.FOnPrev) then
      Owner.FOnPrev(Owner);
  end
  else if Assigned(Owner.FOnNext) then
    Owner.FOnNext(Owner);
end;

{ TGittanToolbar }

class function TGittanToolbar.Install(AHandle: PtrUInt;
  const AName, AHint: string): TGittanToolbar;
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
  Delegate := TGittanToolbarDelegate.alloc.init;
  Delegate.Owner := Result;
  Result.FDelegate := Delegate;

  Result.FSearch := NSSearchField.alloc.initWithFrame(NSMakeRect(0, 0, SearchWidth, 22));
  Result.FSearch.setPlaceholderString(NSStr(AHint));
  Result.FSearch.setSendsSearchStringImmediately(True);
  Result.FSearch.setSendsWholeSearchString(False);
  Result.FSearch.setTarget(Delegate);
  Result.FSearch.setAction(objcselector('gittanSearchChanged:'));
  Result.FSearch.setDelegate(NSTextFieldDelegateProtocol(Delegate));
  Result.FCounter := MakeLabel('– / 0',
    NSFont.monospacedDigitSystemFontOfSize_weight(NSFont.systemFontSize, 0));
  Result.FCounter.setTextColor(NSColor.secondaryLabelColor);
  Result.FCounter.retain;

  Result.FToolbar := NSToolbar.alloc.initWithIdentifier(NSStr('gittan.toolbar'));
  Result.FToolbar.setDelegate(Delegate);
  Result.FToolbar.setDisplayMode(NSToolbarDisplayModeIconOnly);
  Result.FToolbar.setAllowsUserCustomization(False);
  Result.FToolbar.setCenteredItemIdentifier(NSStr(IdSearch));
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
  if FSearch <> nil then
  begin
    FSearch.setDelegate(nil);
    FSearch.setTarget(nil);
    FSearch.release;
  end;
  if FCounter <> nil then
    FCounter.release;
  if FDelegate <> nil then
    FDelegate.release;
  inherited Destroy;
end;

function TGittanToolbar.GetSearchText: string;
begin
  Result := FSearch.stringValue.UTF8String;
end;

procedure TGittanToolbar.SetActions(const ACaptions: array of string;
  const AEnabled: array of boolean);
var
  i, N: integer;
begin
  N := Length(ACaptions);
  if N > MaxActions then
    N := MaxActions;
  SetLength(FActions, N);
  SetLength(FEnabled, N);
  for i := 0 to N - 1 do
  begin
    FActions[i] := ACaptions[i];
    FEnabled[i] := (i > High(AEnabled)) or AEnabled[i];
  end;
  Update;
end;

procedure TGittanToolbar.SetChanges(ACurrent, ATotal: integer);
begin
  FCurrent := ACurrent;
  FTotal := ATotal;
  Update;
end;

procedure TGittanToolbar.FocusSearch;
begin
  FWindow.makeFirstResponder(FSearch);
  FSearch.selectText(nil);
end;

{ The items after the fixed ones are the counter and the arrows while
  there are changes, then one per action. They are inserted again when
  that set changed; the counter, the captions and the enabled states are
  set on the items in place. }
procedure TGittanToolbar.Update;
var
  Wanted: TStringList;
  Items: NSArray;
  Item: NSToolbarItem;
  Id: string;
  Same: boolean;
  i: integer;
begin
  Wanted := TStringList.Create;
  try
    if FTotal > 0 then
    begin
      Wanted.Add(IdCounter);
      Wanted.Add(IdNav);
    end;
    for i := 0 to High(FActions) do
      Wanted.Add(IdAction + IntToStr(i));
    Items := FToolbar.items;
    Same := Items.count = NSUInteger(FixedItems + Wanted.Count);
    if Same then
      for i := 0 to Wanted.Count - 1 do
        if NSToolbarItem(Items.objectAtIndex(FixedItems + i)).itemIdentifier.UTF8String
          <> Wanted[i] then
        begin
          Same := False;
          Break;
        end;
    if not Same then
    begin
      for i := integer(Items.count) - 1 downto FixedItems do
        FToolbar.removeItemAtIndex(i);
      for i := 0 to Wanted.Count - 1 do
        FToolbar.insertItemWithItemIdentifier_atIndex(NSStr(Wanted[i]),
          FixedItems + i);
    end;
  finally
    Wanted.Free;
  end;

  if FCurrent > 0 then
    FCounter.setStringValue(NSStr(Format('%d / %d', [FCurrent, FTotal])))
  else
    FCounter.setStringValue(NSStr(Format('– / %d', [FTotal])));
  FCounter.sizeToFit;
  Items := FToolbar.items;
  for i := FixedItems to integer(Items.count) - 1 do
  begin
    Item := NSToolbarItem(Items.objectAtIndex(i));
    Id := Item.itemIdentifier.UTF8String;
    if Copy(Id, 1, Length(IdAction)) = IdAction then
      if (Item.tag >= 0) and (Item.tag <= High(FActions)) then
      begin
        Item.setTitle(NSStr(FActions[Item.tag]));
        Item.setToolTip(NSStr(FActions[Item.tag]));
        Item.setEnabled(FEnabled[Item.tag]);
      end;
  end;
end;

end.
