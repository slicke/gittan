{ A field holding a path shows its end, the part that tells one folder
  from another, rather than its start, which is the same home folder
  in every one.

  On Cocoa a TEdit is an NSTextField: its cell is set to truncate at the
  head, so a field without the focus shows "…/scratch/demo" with the
  end in view. A field that takes the focus gets a field editor that
  selects the whole text and scrolls to its start as it comes, after
  the LCL's OnEnter, so the end is scrolled into view from the message
  loop once it has come, the selection kept. Elsewhere the caret goes
  to the end. }
unit gittan.pathfield;

{$mode objfpc}{$H+}
{$IFDEF LCLCocoa}
{$modeswitch objectivec1}
{$ENDIF}

interface

uses
  StdCtrls;

{** Shows the end of AEdit's path, now and whenever it takes the focus:
  call it once the field has its handle (in the dialog's DoShow) and
  after the text is set. It takes AEdit's OnEnter when that is free. }
procedure ShowPathEnd(AEdit: TEdit);

implementation

uses
  Classes, Forms, LazUTF8{$IFDEF LCLCocoa}, CocoaAll{$ENDIF};

type
  { The fields ShowPathEnd looks after, told when one is freed, so a
    call from the message loop never reaches one that is gone. }
  TPathEndHook = class(TComponent)
  private
    FEdits: TList;
    procedure EditEnter(Sender: TObject);
    procedure ScrollAsync(Data: PtrInt);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Watch(AEdit: TEdit);
  end;

var
  GHook: TPathEndHook;

constructor TPathEndHook.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEdits := TList.Create;
end;

destructor TPathEndHook.Destroy;
begin
  FEdits.Free;
  inherited Destroy;
end;

procedure TPathEndHook.Watch(AEdit: TEdit);
begin
  if FEdits.IndexOf(AEdit) >= 0 then
    Exit;
  FEdits.Add(AEdit);
  AEdit.FreeNotification(Self);
  if not Assigned(AEdit.OnEnter) then
    AEdit.OnEnter := @EditEnter;
end;

procedure TPathEndHook.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if Operation = opRemove then
    FEdits.Remove(AComponent);
end;

procedure TPathEndHook.EditEnter(Sender: TObject);
begin
  Application.QueueAsyncCall(@ScrollAsync, PtrInt(Sender));
end;

procedure TPathEndHook.ScrollAsync(Data: PtrInt);
var
  Edit: TEdit;
  {$IFDEF LCLCocoa}
  Field: NSObject;
  Editor: NSText;
  {$ENDIF}
begin
  if FEdits.IndexOf(Pointer(Data)) < 0 then
    Exit;
  Edit := TEdit(Data);
  if not Edit.HandleAllocated then
    Exit;
  {$IFDEF LCLCocoa}
  Field := NSObject(Edit.Handle);
  if not Field.isKindOfClass(NSTextField) then
    Exit;
  Editor := NSTextField(Field).currentEditor;
  if Editor <> nil then
    Editor.scrollRangeToVisible(NSMakeRange(Editor.string_.length, 0));
  {$ELSE}
  Edit.SelStart := UTF8Length(Edit.Text);
  Edit.SelLength := 0;
  {$ENDIF}
end;

procedure ShowPathEnd(AEdit: TEdit);
{$IFDEF LCLCocoa}
var
  Field: NSObject;
{$ENDIF}
begin
  if (AEdit = nil) or not AEdit.HandleAllocated then
    Exit;
  if GHook = nil then
    GHook := TPathEndHook.Create(Application);
  GHook.Watch(AEdit);
  {$IFDEF LCLCocoa}
  Field := NSObject(AEdit.Handle);
  if Field.isKindOfClass(NSTextField) then
    NSTextField(Field).cell.setLineBreakMode(NSLineBreakByTruncatingHead);
  if AEdit.Focused then
    GHook.EditEnter(AEdit);
  {$ELSE}
  AEdit.SelStart := UTF8Length(AEdit.Text);
  AEdit.SelLength := 0;
  {$ENDIF}
end;

end.
