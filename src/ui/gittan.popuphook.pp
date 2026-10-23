unit gittan.popuphook;

{** What the panels that drop over the form share (the popup lists, the
  commit graph, the notice): they are children of the form, not windows
  of their own, so nothing closes them as a popup is closed. While one is
  up a TGittanPopupHook watches the application's input: a mouse press
  on a control outside the panel, or the application going to the
  background, calls the panel's close method. It also keeps the control
  that had the focus before the panel took it, to give it back. }

{$mode objfpc}{$H+}

interface

uses
  Classes, Controls, Forms, LCLType, LCLVersion, LMessages;

type
  TGittanPopupClose = procedure of object;

  { TGittanPopupHook }

  TGittanPopupHook = class(TComponent)
  private
    FPanel: TControl;
    FOnOutside: TGittanPopupClose;
    FDeactivate: boolean;
    FKeeper: TControl;
    FReturnFocus: TWinControl;
    FHooked: boolean;
    { Lazarus 4.99 passes the whole message, by reference. }
    {$IF lcl_fullversion >= 4990000}
    procedure UserInput(Sender: TObject; var Message: TLMessage);
    {$ELSE}
    procedure UserInput(Sender: TObject; Msg: cardinal);
    {$ENDIF}
    procedure AppDeactivate(Sender: TObject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    {** A hook for APanel, which owns it. AOnOutside closes the panel;
      ADeactivate says whether the application going to the background
      calls it too. }
    constructor Create(APanel: TControl; AOnOutside: TGittanPopupClose;
      ADeactivate: boolean); reintroduce;
    destructor Destroy; override;
    {** Whether AControl is the panel or inside it. }
    function Owns(AControl: TControl): boolean;
    {** Starts (AOn) or stops watching the input; call it when the panel
      shows and hides. }
    procedure Hook(AOn: boolean);
    {** Remembers the focused control when it is outside the panel, before
      the panel takes the focus. }
    procedure SaveFocus;
    {** Gives the focus back to the control SaveFocus remembered, when it
      can still take it. }
    procedure RestoreFocus;
    {** A control whose presses leave the panel open, as its own do. }
    property Keeper: TControl read FKeeper write FKeeper;
  end;

implementation

uses
  LCLIntf;

constructor TGittanPopupHook.Create(APanel: TControl; AOnOutside: TGittanPopupClose;
  ADeactivate: boolean);
begin
  inherited Create(APanel);
  FPanel := APanel;
  FOnOutside := AOnOutside;
  FDeactivate := ADeactivate;
end;

destructor TGittanPopupHook.Destroy;
begin
  Hook(False);
  inherited Destroy;
end;

function TGittanPopupHook.Owns(AControl: TControl): boolean;
begin
  Result := False;
  while AControl <> nil do
  begin
    if AControl = FPanel then
      Exit(True);
    AControl := AControl.Parent;
  end;
end;

{ Every mouse press and key goes through here before it is delivered.
  A press on a control outside the panel (and not on the Keeper) closes
  it. The message says which it was on most widgetsets; Cocoa passes the
  last key message instead, so the mouse buttons are asked as well. }
{$IF lcl_fullversion >= 4990000}
procedure TGittanPopupHook.UserInput(Sender: TObject; var Message: TLMessage);
var
  Msg: cardinal;
begin
  Msg := Message.msg;
{$ELSE}
procedure TGittanPopupHook.UserInput(Sender: TObject; Msg: cardinal);
begin
{$ENDIF}
  if not FPanel.Visible then
    Exit;
  if (Sender is TControl) and (Owns(TControl(Sender)) or
    ((FKeeper <> nil) and (Sender = FKeeper))) then
    Exit;
  if (Msg = LM_LBUTTONDOWN) or (Msg = LM_RBUTTONDOWN) or (Msg = LM_MBUTTONDOWN) or
    (GetKeyState(VK_LBUTTON) < 0) or (GetKeyState(VK_RBUTTON) < 0) or
    (GetKeyState(VK_MBUTTON) < 0) then
    FOnOutside;
end;

procedure TGittanPopupHook.AppDeactivate(Sender: TObject);
begin
  FOnOutside;
end;

procedure TGittanPopupHook.Hook(AOn: boolean);
begin
  if AOn = FHooked then
    Exit;
  FHooked := AOn;
  if AOn then
  begin
    Application.AddOnUserInputHandler(@UserInput, True);
    if FDeactivate then
      Application.AddOnDeactivateHandler(@AppDeactivate, True);
  end
  else
  begin
    Application.RemoveOnUserInputHandler(@UserInput);
    if FDeactivate then
      Application.RemoveOnDeactivateHandler(@AppDeactivate);
  end;
end;

procedure TGittanPopupHook.SaveFocus;
begin
  if FReturnFocus <> nil then
    FReturnFocus.RemoveFreeNotification(Self);
  FReturnFocus := nil;
  if (Screen.ActiveControl <> nil) and not Owns(Screen.ActiveControl) then
  begin
    FReturnFocus := Screen.ActiveControl;
    FReturnFocus.FreeNotification(Self);
  end;
end;

procedure TGittanPopupHook.RestoreFocus;
begin
  if (FReturnFocus <> nil) and FReturnFocus.CanFocus then
    FReturnFocus.SetFocus;
  if FReturnFocus <> nil then
    FReturnFocus.RemoveFreeNotification(Self);
  FReturnFocus := nil;
end;

procedure TGittanPopupHook.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FReturnFocus) then
    FReturnFocus := nil;
end;

end.
