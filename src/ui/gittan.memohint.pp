{ A placeholder for a TMemo on macOS.

  The LCL's Cocoa widgetset shows TextHint for a single-line edit, an
  NSTextField, but not for a memo: its handle is an NSScrollView around
  an NSTextView, which has no public placeholder. (Its private
  placeholderAttributedString takes the text but draws nothing on recent
  macOS.) So the hint is a label of its own: a borderless NSTextField
  that does not take the mouse or the focus, in the placeholder color
  and the view's font, laid in the text view where the first line
  starts, and hidden while the memo holds text.

  The unit uses CocoaAll alone; umain keeps it behind LCLCocoa, so the
  other widgetsets never see it. }
unit gittan.memohint;

{$mode objfpc}{$H+}
{$modeswitch objectivec1}

interface

{** Shows AText dimmed in the empty text view inside AScrollView, the
  handle of a TMemo on Cocoa, in the view's font; empty takes it away. }
procedure SetMemoPlaceholder(AScrollView: PtrUInt; const AText: string);
{** Shows or hides the placeholder SetMemoPlaceholder put in, as the
  memo is empty or not. }
procedure ShowMemoPlaceholder(AScrollView: PtrUInt; AShow: boolean);

implementation

uses
  CocoaAll;

type
  { placeholderTextColor (10.10, older than any macOS the LCL's Cocoa
    widgetset runs on) is not in FPC's headers. }
  NSColorPlaceholder = objccategory external (NSColor)
    class function placeholderTextColor: NSColor; message 'placeholderTextColor';
  end;

const
  { The label's tag, so it is found again among the view's subviews. }
  HintTag = $67686E74;

function TextViewOf(AScrollView: PtrUInt): NSTextView;
var
  Scroll: NSScrollView;
begin
  Result := nil;
  if AScrollView = 0 then
    Exit;
  Scroll := NSScrollView(AScrollView);
  if Scroll.isKindOfClass(NSScrollView) and (Scroll.documentView <> nil) and
    Scroll.documentView.isKindOfClass(NSTextView) then
    Result := NSTextView(Scroll.documentView);
end;

function LabelOf(AView: NSTextView): NSTextField;
var
  V: NSView;
begin
  Result := nil;
  V := AView.viewWithTag(HintTag);
  if (V <> nil) and V.isKindOfClass(NSTextField) then
    Result := NSTextField(V);
end;

{ The label ignores the mouse, so a click on it reaches the text view. }
type
  TGittanHintLabel = objcclass(NSTextField)
    function hitTest(aPoint: NSPoint): NSView; override;
    function tag: NSInteger; override;
  end;

function TGittanHintLabel.hitTest(aPoint: NSPoint): NSView;
begin
  Result := nil;
end;

function TGittanHintLabel.tag: NSInteger;
begin
  Result := HintTag;
end;

procedure SetMemoPlaceholder(AScrollView: PtrUInt; const AText: string);
var
  View: NSTextView;
  Lbl: NSTextField;
  X, Y: Double;
  S: NSString;
begin
  View := TextViewOf(AScrollView);
  if View = nil then
    Exit;
  Lbl := LabelOf(View);
  if AText = '' then
  begin
    if Lbl <> nil then
      Lbl.removeFromSuperview;
    Exit;
  end;
  if Lbl = nil then
  begin
    Lbl := TGittanHintLabel.alloc.initWithFrame(NSMakeRect(0, 0, 10, 10));
    Lbl.setEditable(False);
    Lbl.setSelectable(False);
    Lbl.setBordered(False);
    Lbl.setBezeled(False);
    Lbl.setDrawsBackground(False);
    View.addSubview(Lbl);
    Lbl.release;
  end;
  S := NSString.alloc.initWithUTF8String(PAnsiChar(AText));
  Lbl.setStringValue(S);
  S.release;
  if View.font <> nil then
    Lbl.setFont(View.font);
  Lbl.setTextColor(NSColor.placeholderTextColor);
  Lbl.sizeToFit;
  { Where the text view lays its first line: past the container's inset
    and the line fragment's padding (the view is flipped, so from the
    top). The cell draws its text two points in from its own edge. }
  X := View.textContainerInset.width - 2;
  if View.textContainer <> nil then
    X := X + View.textContainer.lineFragmentPadding;
  Y := View.textContainerInset.height;
  Lbl.setFrameOrigin(NSMakePoint(X, Y));
  Lbl.setHidden(View.string_.length > 0);
end;

procedure ShowMemoPlaceholder(AScrollView: PtrUInt; AShow: boolean);
var
  View: NSTextView;
  Lbl: NSTextField;
begin
  View := TextViewOf(AScrollView);
  if View = nil then
    Exit;
  Lbl := LabelOf(View);
  if Lbl <> nil then
    Lbl.setHidden(not AShow);
end;

end.
