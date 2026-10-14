unit gittan.popuplist;

{** A popup list: a panel that drops down from whatever was clicked and
  offers a choice from a list. Made for the branch under the repository
  name in the summary; any other choice from a list can use it.

  The items are added in order, with headers between groups; one of
  them may be Checked, the current choice, shown with a check mark.
  Popup shows the panel under a rectangle given in screen coordinates
  (above it when there is more room there), focused, with a filter
  field on top when the list is long. Up and Down move in it, Enter or
  a click picks: OnPick comes with the index Add gave the item. Escape,
  a click outside the panel or the application going to the background
  closes it; OnClose comes whenever it hides, after OnPick.

  The panel is a child of the form it pops up in, placed over whatever
  the form shows, instead of a window of its own, which the widgetsets
  place and focus differently. It paints itself in the editor's colors;
  the filter field is a native TEdit so typing works as the desktop
  expects, and the rows sit in a TScrollBox for native scrolling. A
  click outside is seen through the application's user input hook,
  which every widgetset calls before a mouse press is delivered. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, StdCtrls, Forms, LCLType;

type
  TGittanPopupPickEvent = procedure(Sender: TObject; AIndex: integer) of object;

  TGittanPopupItem = record
    Caption, Detail: string;
    Header, Checked: boolean;
  end;

  TGittanPopupList = class;

  { TGittanPopupRows }

  {** The rows of the list, inside the scroll box: painting and the
    mouse are the list's, it only forwards them. }
  TGittanPopupRows = class(TCustomControl)
  private
    FList: TGittanPopupList;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    procedure KeyDown(var Key: word; Shift: TShiftState); override;
  end;

  { TGittanPopupList }

  TGittanPopupList = class(TCustomControl)
  private
    FEdit: TEdit;
    FBox: TScrollBox;
    FRows: TGittanPopupRows;
    FItems: array of TGittanPopupItem;
    { The index in FItems of every row shown: the items that match the
      filter, every one of them while there is none. }
    FShown: TIntegerDynArray;
    { The row (an index into FShown) that is highlighted and that Enter
      picks; -1 for none. }
    FCurrent: integer;
    FAnchor: TRect;
    FAbove, FFilterVisible: boolean;
    FReturnFocus: TWinControl;
    FBack, FText, FDim, FHover, FLine, FAccent: TColor;
    FFilterHint: string;
    FOnPick: TGittanPopupPickEvent;
    FOnClose: TNotifyEvent;
    function Pickable: integer;
    function ContentWidth: integer;
    procedure Fill;
    procedure Layout;
    procedure Arrange;
    function RowAt(Y: integer): integer;
    procedure SetCurrent(AValue: integer);
    procedure Step(ADelta: integer);
    procedure ScrollIntoView;
    procedure PaintRows(ACanvas: TCanvas);
    procedure Dismiss;
    procedure Pick;
    procedure EditChange(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure KeyInput(var Key: word);
    procedure UserInput(Sender: TObject; Msg: cardinal);
    procedure AppDeactivate(Sender: TObject);
    function Owns(AControl: TControl): boolean;
    procedure Hook(AOn: boolean);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** Forgets the items. }
    procedure Clear;
    {** Adds an item and returns its index, the one OnPick reports.
      ADetail is shown dimmed on the right; AChecked marks it as the
      current choice. }
    function Add(const ACaption: string; const ADetail: string = '';
      AChecked: boolean = False): integer;
    {** Adds a header, the dimmed name of the group of items that
      follow. It cannot be picked. }
    procedure AddHeader(const ACaption: string);
    {** Shows the list under AAnchor, a rectangle in screen coordinates
      (the control or the text that was clicked), aligned with its left
      edge, kept within the parent; above it when there is more room
      there. The focus goes to the filter field, or to the rows. }
    procedure Popup(const AAnchor: TRect);
    {** Hides the list without a pick. }
    procedure Close;
    {** The colors: the background, the text, the dim text (headers,
      details), the highlighted row, the border and the divider, and the
      check mark of the current choice. }
    procedure SetColors(ABack, AText, ADim, AHover, ALine, AAccent: TColor);
    {** The hint of the filter field, which is shown when the list has
      more than a few items. }
    property FilterHint: string read FFilterHint write FFilterHint;
    property OnPick: TGittanPopupPickEvent read FOnPick write FOnPick;
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
  end;

implementation

uses
  Math, LCLIntf, LMessages;

resourcestring
  rsNoMatches = 'No matches';
  rsFilterHint = 'Filter';

const
  RowHeight = 26;
  { The most rows shown at once; the rest scroll. }
  MaxVisibleRows = 12;
  { The list gets a filter field when it has more pickable items than
    this. }
  FilterOver = 8;
  Pad = 12;
  Gap = 10;
  { The distance from the anchor. }
  Offset = 4;
  Border = 1;
  CheckWidth = 20;
  MinWidth = 220;
  MaxWidth = 440;
  { Room left of the text for the scroll bar, which overlays on macOS
    and takes space elsewhere. }
  ScrollRoom = 16;

{ TGittanPopupRows }

procedure TGittanPopupRows.Paint;
begin
  FList.PaintRows(Canvas);
end;

procedure TGittanPopupRows.MouseMove(Shift: TShiftState; X, Y: integer);
var
  Row: integer;
begin
  inherited MouseMove(Shift, X, Y);
  Row := FList.RowAt(Y);
  if Row >= 0 then
    FList.SetCurrent(Row);
end;

procedure TGittanPopupRows.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Row: integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  Row := FList.RowAt(Y);
  if (Button = mbLeft) and (Row >= 0) then
  begin
    FList.SetCurrent(Row);
    FList.Pick;
  end;
end;

procedure TGittanPopupRows.KeyDown(var Key: word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  FList.KeyInput(Key);
end;

{ TGittanPopupList }

constructor TGittanPopupList.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Visible := False;
  FCurrent := -1;
  FFilterHint := rsFilterHint;
  FEdit := TEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.OnChange := @EditChange;
  FEdit.OnKeyDown := @EditKeyDown;
  FBox := TScrollBox.Create(Self);
  FBox.Parent := Self;
  FBox.BorderStyle := bsNone;
  FBox.HorzScrollBar.Visible := False;
  FRows := TGittanPopupRows.Create(Self);
  FRows.FList := Self;
  FRows.Parent := FBox;
  FRows.Align := alTop;
  FRows.ControlStyle := FRows.ControlStyle + [csOpaque];
  FRows.TabStop := True;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnShadow, clHighlight);
end;

destructor TGittanPopupList.Destroy;
begin
  Hook(False);
  inherited Destroy;
end;

procedure TGittanPopupList.Clear;
begin
  FItems := nil;
  FShown := nil;
  FCurrent := -1;
end;

function TGittanPopupList.Add(const ACaption: string; const ADetail: string;
  AChecked: boolean): integer;
begin
  Result := Length(FItems);
  SetLength(FItems, Result + 1);
  FItems[Result].Caption := ACaption;
  FItems[Result].Detail := ADetail;
  FItems[Result].Header := False;
  FItems[Result].Checked := AChecked;
end;

procedure TGittanPopupList.AddHeader(const ACaption: string);
begin
  Add(ACaption);
  FItems[High(FItems)].Header := True;
end;

procedure TGittanPopupList.SetColors(ABack, AText, ADim, AHover, ALine,
  AAccent: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
  FLine := ALine;
  FAccent := AAccent;
  Color := ABack;
  FBox.Color := ABack;
  FRows.Color := ABack;
  Invalidate;
  FRows.Invalidate;
end;

function TGittanPopupList.Pickable: integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to High(FItems) do
    if not FItems[i].Header then
      Inc(Result);
end;

{ The width the widest item needs, within MinWidth..MaxWidth and the
  parent. Measured on a bitmap: the panel may have no handle yet. }
function TGittanPopupList.ContentWidth: integer;
var
  Measure: TBitmap;
  i, W: integer;
begin
  Result := MinWidth;
  Measure := TBitmap.Create;
  try
    Measure.Canvas.Font := Font;
    for i := 0 to High(FItems) do
    begin
      W := 2 * (Border + Pad) + CheckWidth + ScrollRoom +
        Measure.Canvas.TextWidth(FItems[i].Caption);
      if FItems[i].Detail <> '' then
        Inc(W, Gap + Measure.Canvas.TextWidth(FItems[i].Detail));
      Result := Max(Result, W);
    end;
  finally
    Measure.Free;
  end;
  Result := Min(Result, MaxWidth);
  if Parent <> nil then
    Result := Min(Result, Parent.ClientWidth - 2 * Pad);
end;

{ The rows that match the filter (any part of the caption, ignoring
  case); the headers are left out while there is a filter, since their
  groups are broken up. The current row is the checked item when it is
  shown, else the first pickable one. }
procedure TGittanPopupList.Fill;
var
  Filter: string;
  i, Count: integer;
begin
  if FFilterVisible then
    Filter := LowerCase(Trim(FEdit.Text))
  else
    Filter := '';
  SetLength(FShown, Length(FItems));
  Count := 0;
  FCurrent := -1;
  for i := 0 to High(FItems) do
  begin
    if Filter <> '' then
    begin
      if FItems[i].Header or (Pos(Filter, LowerCase(FItems[i].Caption)) = 0) then
        Continue;
    end;
    FShown[Count] := i;
    if not FItems[i].Header then
      if (FCurrent < 0) or FItems[i].Checked then
        FCurrent := Count;
    Inc(Count);
  end;
  SetLength(FShown, Count);
  Layout;
  FRows.Invalidate;
  ScrollIntoView;
end;

{ The panel's size from its rows (at most MaxVisibleRows of them), and
  its place against the anchor. }
procedure TGittanPopupList.Layout;
var
  Rows, ListTop, H: integer;
begin
  Rows := Max(1, Min(Length(FShown), MaxVisibleRows));
  if FFilterVisible then
    ListTop := Border + Pad div 2 + FEdit.Height + Pad div 2 + 1
  else
    ListTop := Border + Pad div 2;
  H := ListTop + Rows * RowHeight + Pad div 2 + Border;
  if Parent <> nil then
  begin
    if FAbove then
      Top := Max(0, FAnchor.Top - Offset - H)
    else
      Top := Min(FAnchor.Bottom + Offset, Max(0, Parent.ClientHeight - H));
  end;
  Height := H;
  Arrange;
end;

{ The field across the top when it is shown, the scroll box under it
  with the rows at their full height inside. }
procedure TGittanPopupList.Arrange;
var
  ListTop: integer;
begin
  if (FEdit = nil) or (FBox = nil) or (FRows = nil) then
    Exit;
  FEdit.Visible := FFilterVisible;
  if FFilterVisible then
  begin
    FEdit.SetBounds(Border + Pad, Border + Pad div 2, Width - 2 * (Border + Pad),
      FEdit.Height);
    ListTop := FEdit.Top + FEdit.Height + Pad div 2 + 1;
  end
  else
    ListTop := Border + Pad div 2;
  FBox.SetBounds(Border, ListTop, Width - 2 * Border,
    Max(RowHeight, Height - ListTop - Pad div 2 - Border));
  FRows.Height := Max(1, Length(FShown)) * RowHeight;
end;

procedure TGittanPopupList.Resize;
begin
  inherited Resize;
  Arrange;
end;

procedure TGittanPopupList.Popup(const AAnchor: TRect);
var
  W, RoomBelow, RoomAbove: integer;
begin
  if Parent = nil then
    Exit;
  Dismiss;
  FAnchor.TopLeft := Parent.ScreenToClient(AAnchor.TopLeft);
  FAnchor.BottomRight := Parent.ScreenToClient(AAnchor.BottomRight);
  FFilterVisible := Pickable > FilterOver;
  FEdit.Text := '';
  FEdit.TextHint := FFilterHint;
  W := ContentWidth;
  Width := W;
  Left := Max(0, Min(FAnchor.Left, Parent.ClientWidth - W));
  RoomBelow := Parent.ClientHeight - FAnchor.Bottom - Offset;
  RoomAbove := FAnchor.Top - Offset;
  FAbove := False;
  Fill;
  FAbove := (Height > RoomBelow) and (RoomAbove > RoomBelow);
  if FAbove then
    Layout;
  FReturnFocus := nil;
  if (Screen.ActiveControl <> nil) and not Owns(Screen.ActiveControl) then
  begin
    FReturnFocus := Screen.ActiveControl;
    FReturnFocus.FreeNotification(Self);
  end;
  Visible := True;
  BringToFront;
  if FFilterVisible then
  begin
    if FEdit.CanFocus then
      FEdit.SetFocus;
  end
  else if FRows.CanFocus then
    FRows.SetFocus;
  Hook(True);
end;

procedure TGittanPopupList.Dismiss;
begin
  if not Visible then
    Exit;
  Hook(False);
  Visible := False;
  if (FReturnFocus <> nil) and FReturnFocus.CanFocus then
    FReturnFocus.SetFocus;
  FReturnFocus := nil;
end;

procedure TGittanPopupList.Close;
begin
  if not Visible then
    Exit;
  Dismiss;
  if Assigned(FOnClose) then
    FOnClose(Self);
end;

procedure TGittanPopupList.Pick;
var
  Index: integer;
begin
  if (FCurrent < 0) or (FCurrent > High(FShown)) then
    Exit;
  Index := FShown[FCurrent];
  if FItems[Index].Header then
    Exit;
  Dismiss;
  if Assigned(FOnPick) then
    FOnPick(Self, Index);
  if Assigned(FOnClose) then
    FOnClose(Self);
end;

function TGittanPopupList.RowAt(Y: integer): integer;
begin
  Result := -1;
  if Y < 0 then
    Exit;
  Result := Y div RowHeight;
  if (Result > High(FShown)) or FItems[FShown[Result]].Header then
    Result := -1;
end;

procedure TGittanPopupList.SetCurrent(AValue: integer);
begin
  if FCurrent = AValue then
    Exit;
  FCurrent := AValue;
  FRows.Invalidate;
end;

{ Moves the current row ADelta rows, skipping headers, within the list. }
procedure TGittanPopupList.Step(ADelta: integer);
var
  Row: integer;
begin
  Row := FCurrent;
  repeat
    Inc(Row, ADelta);
    if (Row < 0) or (Row > High(FShown)) then
      Exit;
  until not FItems[FShown[Row]].Header;
  SetCurrent(Row);
  ScrollIntoView;
end;

procedure TGittanPopupList.ScrollIntoView;
var
  RowTop, Pos: integer;
begin
  if FCurrent < 0 then
    Exit;
  RowTop := FCurrent * RowHeight;
  Pos := FBox.VertScrollBar.Position;
  if RowTop < Pos then
    FBox.VertScrollBar.Position := RowTop
  else if RowTop + RowHeight > Pos + FBox.ClientHeight then
    FBox.VertScrollBar.Position := RowTop + RowHeight - FBox.ClientHeight;
end;

procedure TGittanPopupList.EditChange(Sender: TObject);
begin
  if Visible then
    Fill;
end;

procedure TGittanPopupList.EditKeyDown(Sender: TObject; var Key: word;
  Shift: TShiftState);
begin
  KeyInput(Key);
end;

{ Up and Down move, Enter picks, Escape closes, Tab stays put: the
  handled keys are cleared so the field does not act on them. }
procedure TGittanPopupList.KeyInput(var Key: word);
begin
  case Key of
    VK_UP: Step(-1);
    VK_DOWN: Step(1);
    VK_RETURN: Pick;
    VK_ESCAPE: Close;
    VK_TAB: ;
    else
      Exit;
  end;
  Key := 0;
end;

function TGittanPopupList.Owns(AControl: TControl): boolean;
begin
  Result := False;
  while AControl <> nil do
  begin
    if AControl = Self then
      Exit(True);
    AControl := AControl.Parent;
  end;
end;

{ Every mouse press and key goes through here before it is delivered.
  A press on a control outside the panel closes it. The message says
  which it was on most widgetsets; Cocoa passes the last key message
  instead, so the mouse buttons are asked as well. A key goes to the
  focused control, inside the panel while it is up. }
procedure TGittanPopupList.UserInput(Sender: TObject; Msg: cardinal);
begin
  if not Visible then
    Exit;
  if (Sender is TControl) and Owns(TControl(Sender)) then
    Exit;
  if (Msg = LM_LBUTTONDOWN) or (Msg = LM_RBUTTONDOWN) or (Msg = LM_MBUTTONDOWN) or
    (GetKeyState(VK_LBUTTON) < 0) or (GetKeyState(VK_RBUTTON) < 0) or
    (GetKeyState(VK_MBUTTON) < 0) then
    Close;
end;

procedure TGittanPopupList.AppDeactivate(Sender: TObject);
begin
  Close;
end;

procedure TGittanPopupList.Hook(AOn: boolean);
begin
  if AOn then
  begin
    Application.AddOnUserInputHandler(@UserInput, True);
    Application.AddOnDeactivateHandler(@AppDeactivate, True);
  end
  else
  begin
    Application.RemoveOnUserInputHandler(@UserInput);
    Application.RemoveOnDeactivateHandler(@AppDeactivate);
  end;
end;

procedure TGittanPopupList.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FReturnFocus) then
    FReturnFocus := nil;
end;

{ The border around the panel and the divider under the field. }
procedure TGittanPopupList.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := FLine;
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(0, 0, Width, Height);
  if FFilterVisible then
    Canvas.Line(Border, FBox.Top - 1, Width - Border, FBox.Top - 1);
end;

{ Each row: the highlight behind the current one, the check mark of
  the checked item, the caption (dim for a header, which sits at the
  left margin where the check marks go) and the detail dimmed on the
  right. A caption too long for the room loses its end. }
procedure TGittanPopupList.PaintRows(ACanvas: TCanvas);
var
  i, X, Y, TextY, LineHeight, Room, DetailWidth, CenterY: integer;
  Item: TGittanPopupItem;
  Shown: string;
begin
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := FBack;
  ACanvas.FillRect(FRows.ClientRect);
  ACanvas.Font := Font;
  LineHeight := ACanvas.TextHeight('Xg');
  ACanvas.Brush.Style := bsClear;
  if Length(FShown) = 0 then
  begin
    ACanvas.Font.Color := FDim;
    ACanvas.TextOut(Pad + CheckWidth, (RowHeight - LineHeight) div 2, rsNoMatches);
    Exit;
  end;
  for i := 0 to High(FShown) do
  begin
    Item := FItems[FShown[i]];
    Y := i * RowHeight;
    TextY := Y + (RowHeight - LineHeight) div 2;
    CenterY := Y + RowHeight div 2;
    if (i = FCurrent) and not Item.Header then
    begin
      ACanvas.Pen.Style := psClear;
      ACanvas.Brush.Style := bsSolid;
      ACanvas.Brush.Color := FHover;
      ACanvas.RoundRect(Pad div 2, Y + 1, FRows.Width - Pad div 2, Y + RowHeight - 1, 8, 8);
      ACanvas.Pen.Style := psSolid;
      ACanvas.Brush.Style := bsClear;
    end;
    if Item.Checked and not Item.Header then
    begin
      ACanvas.Pen.Color := FAccent;
      ACanvas.Pen.Width := 2;
      X := Pad + 2;
      ACanvas.Polyline([Point(X, CenterY), Point(X + 4, CenterY + 4),
        Point(X + 11, CenterY - 4)]);
      ACanvas.Pen.Width := 1;
    end;
    DetailWidth := 0;
    if Item.Detail <> '' then
      DetailWidth := ACanvas.TextWidth(Item.Detail) + Gap;
    if Item.Header then
    begin
      X := Pad;
      ACanvas.Font.Color := FDim;
    end
    else
    begin
      X := Pad + CheckWidth;
      ACanvas.Font.Color := FText;
    end;
    Room := FRows.Width - Pad - X - DetailWidth;
    Shown := Item.Caption;
    while (Shown <> '') and (ACanvas.TextWidth(Shown + '…') > Room) do
    begin
      Shown := Copy(Shown, 1, Length(Shown) - 1);
      { Keep UTF-8 sequences whole. }
      while (Shown <> '') and (Ord(Shown[Length(Shown)]) and $C0 = $80) do
        Shown := Copy(Shown, 1, Length(Shown) - 1);
    end;
    if Shown <> Item.Caption then
      Shown := Shown + '…';
    ACanvas.TextOut(X, TextY, Shown);
    if Item.Detail <> '' then
    begin
      ACanvas.Font.Color := FDim;
      ACanvas.TextOut(FRows.Width - Pad - ACanvas.TextWidth(Item.Detail), TextY,
        Item.Detail);
    end;
  end;
end;

end.
