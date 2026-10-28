unit gittan.searchbox;

{** A search field: a rounded box with a magnifier on the left and,
  while there is text, a cross on the right that clears it, around a
  native edit without a border (Edit), so typing, selection and the
  input methods stay the widgetset's. It is the filter field over the
  tree (Go > Filter Files), the same on every widgetset, as the search
  fields of Finder or Firefox look.

  The box paints itself in the colors SetColors gives it, on its
  parent's color; a click on it outside the edit focuses the edit, a
  click on the cross empties it and focuses it. While ShowAction is on a
  sparkle stands left of the cross, its hint ActionHint, and a click on
  it raises OnAction; ActionBusy draws it lit, while what it started
  runs. OnChange is the edit's,
  passed on after the box has shown or hidden the cross. Its height is
  PreferredHeight at the screen's DPI, more when the widgetset's edit
  is taller (GTK 3's is 34 px even without a frame). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, StdCtrls, Forms, Math,
  gittan.theme;

type

  { TGittanSearchBox }

  TGittanSearchBox = class(TCustomControl)
  private
    FEdit: TEdit;
    FFill, FBorder, FDim, FHot: TColor;
    FHotClear, FHotAction: boolean;
    FShowAction, FActionBusy: boolean;
    FActionHint: string;
    FOnChange, FOnAction: TNotifyEvent;
    function ClearRect: TRect;
    function ActionRect: TRect;
    procedure SetShowAction(AValue: boolean);
    procedure SetActionBusy(AValue: boolean);
    function GlassWidth: integer;
    procedure EditChange(Sender: TObject);
    procedure EditResize(Sender: TObject);
    procedure PlaceEdit;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    procedure DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
      const AXProportion, AYProportion: double); override;
  public
    constructor Create(AOwner: TComponent); override;
    {** The box's fill and border, the edit's text, and the dim color of
      the magnifier and the cross, darker (AHot) under the mouse. }
    procedure SetColors(AFill, ABorder, AText, ADim, AHot: TColor);
    {** Sets the height from PreferredHeight and the edit's own. }
    procedure FitHeight;
    {** The edit inside: its Text, TextHint, OnKeyDown, focus. }
    property Edit: TEdit read FEdit;
    {** Whether the sparkle shows, left of the cross. }
    property ShowAction: boolean read FShowAction write SetShowAction;
    {** Draws the sparkle lit, while what OnAction started runs. }
    property ActionBusy: boolean read FActionBusy write SetActionBusy;
    {** The hint over the sparkle; the box has none elsewhere. }
    property ActionHint: string read FActionHint write FActionHint;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    {** A click on the sparkle. }
    property OnAction: TNotifyEvent read FOnAction write FOnAction;
  end;

const
  {** The box's height at 96 DPI. }
  PreferredHeight = 28;

implementation

const
  ClearSize = 22;
  ActionSize = 20;

constructor TGittanSearchBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque] - [csSetCaption];
  FEdit := TEdit.Create(Self);
  FEdit.BorderStyle := bsNone;
  FEdit.OnChange := @EditChange;
  FEdit.OnResize := @EditResize;
  FEdit.Parent := Self;
  SetColors(clWindow, clBtnShadow, clWindowText, clGrayText, clWindowText);
  FitHeight;
end;

procedure TGittanSearchBox.SetColors(AFill, ABorder, AText, ADim, AHot: TColor);
begin
  FFill := AFill;
  FBorder := ABorder;
  FDim := ADim;
  FHot := AHot;
  FEdit.Color := AFill;
  FEdit.Font.Color := AText;
  Invalidate;
end;

procedure TGittanSearchBox.FitHeight;
begin
  Height := Max(Px(PreferredHeight), FEdit.Height + 4);
  PlaceEdit;
end;

function TGittanSearchBox.GlassWidth: integer;
begin
  Result := Px(26);
end;

function TGittanSearchBox.ClearRect: TRect;
var
  S: integer;
begin
  S := Px(ClearSize);
  Result := Types.Rect(Width - S - Px(3), (Height - S) div 2, Width - Px(3),
    (Height - S) div 2 + S);
end;

{ Left of the cross, whose place is kept while the field is empty. }
function TGittanSearchBox.ActionRect: TRect;
var
  S: integer;
begin
  if not FShowAction then
    Exit(Default(TRect));
  S := Px(ActionSize);
  Result := ClearRect;
  Result := Types.Rect(Result.Left - S, (Height - S) div 2, Result.Left,
    (Height - S) div 2 + S);
end;

procedure TGittanSearchBox.SetShowAction(AValue: boolean);
begin
  if FShowAction = AValue then
    Exit;
  FShowAction := AValue;
  FHotAction := False;
  Hint := '';
  PlaceEdit;
  Invalidate;
end;

procedure TGittanSearchBox.SetActionBusy(AValue: boolean);
begin
  if FActionBusy = AValue then
    Exit;
  FActionBusy := AValue;
  Invalidate;
end;

{ Between the magnifier and the cross, or the sparkle, centered in the
  box's height. }
procedure TGittanSearchBox.PlaceEdit;
var
  L, R: integer;
begin
  L := GlassWidth;
  R := Width - Px(ClearSize) - Px(4);
  if FShowAction then
    Dec(R, Px(ActionSize));
  FEdit.SetBounds(L, (Height - FEdit.Height) div 2, Max(10, R - L), FEdit.Height);
end;

procedure TGittanSearchBox.Resize;
begin
  inherited Resize;
  PlaceEdit;
end;

{ The widgetset gives the edit its height once it has a handle (GTK 3's
  is 34 px even without a frame): the box grows to keep its border
  clear of it. }
procedure TGittanSearchBox.EditResize(Sender: TObject);
begin
  if Height < FEdit.Height + 4 then
    FitHeight;
end;

procedure TGittanSearchBox.EditChange(Sender: TObject);
begin
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TGittanSearchBox.Paint;
var
  R, C: TRect;
  CX, CY, Rad, D, E: integer;
  Back: TColor;
begin
  if Parent <> nil then
    Back := Parent.Color
  else
    Back := Color;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Back;
  Canvas.FillRect(ClientRect);
  R := ClientRect;
  Canvas.Brush.Color := FFill;
  Canvas.Pen.Color := FBorder;
  Canvas.Pen.Width := 1;
  Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Px(12), Px(12));

  { The magnifier: the glass up and left, the handle down and right. }
  Canvas.Pen.Color := FDim;
  Canvas.Pen.Width := Max(1, Px(1));
  Canvas.Brush.Style := bsClear;
  CX := GlassWidth div 2 + Px(1);
  CY := Height div 2;
  Rad := Px(5);
  Canvas.Ellipse(CX - Rad - 1, CY - Rad - 1, CX + Rad - 1, CY + Rad - 1);
  D := Px(3);
  Canvas.Line(CX + D, CY + D, CX + Rad + D - 1, CY + Rad + D - 1);

  if FShowAction then
  begin
    { A sparkle: a star of four points, its sides drawn in to the
      middle, filled, as the AI page of the settings has it. }
    C := ActionRect;
    CX := (C.Left + C.Right) div 2;
    CY := (C.Top + C.Bottom) div 2;
    Rad := Px(6);
    E := Max(1, Px(2));
    if FHotAction or FActionBusy then
      Canvas.Pen.Color := FHot
    else
      Canvas.Pen.Color := FDim;
    Canvas.Pen.Width := 1;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := Canvas.Pen.Color;
    Canvas.Polygon([Types.Point(CX, CY - Rad), Types.Point(CX + E, CY - E),
      Types.Point(CX + Rad, CY), Types.Point(CX + E, CY + E), Types.Point(CX, CY + Rad),
      Types.Point(CX - E, CY + E), Types.Point(CX - Rad, CY), Types.Point(CX - E, CY - E)]);
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Width := Max(1, Px(1));
  end;

  if FEdit.Text <> '' then
  begin
    C := ClearRect;
    CX := (C.Left + C.Right) div 2;
    CY := (C.Top + C.Bottom) div 2;
    D := Px(4);
    if FHotClear then
      Canvas.Pen.Color := FHot
    else
      Canvas.Pen.Color := FDim;
    Canvas.Line(CX - D, CY - D, CX + D + 1, CY + D + 1);
    Canvas.Line(CX - D, CY + D, CX + D + 1, CY - D - 1);
  end;
  Canvas.Pen.Width := 1;
end;

procedure TGittanSearchBox.MouseMove(Shift: TShiftState; X, Y: integer);
var
  Hot, HotAction: boolean;
begin
  inherited MouseMove(Shift, X, Y);
  Hot := (FEdit.Text <> '') and ClearRect.Contains(Types.Point(X, Y));
  HotAction := FShowAction and ActionRect.Contains(Types.Point(X, Y));
  if (Hot <> FHotClear) or (HotAction <> FHotAction) then
  begin
    FHotClear := Hot;
    FHotAction := HotAction;
    if HotAction then
      Hint := FActionHint
    else
      Hint := '';
    Invalidate;
  end;
end;

procedure TGittanSearchBox.MouseLeave;
begin
  inherited MouseLeave;
  if FHotClear or FHotAction then
  begin
    FHotClear := False;
    FHotAction := False;
    Hint := '';
    Invalidate;
  end;
end;

procedure TGittanSearchBox.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  if FShowAction and ActionRect.Contains(Types.Point(X, Y)) then
  begin
    if Assigned(FOnAction) then
      FOnAction(Self);
    Exit;
  end;
  if (FEdit.Text <> '') and ClearRect.Contains(Types.Point(X, Y)) then
    FEdit.Text := '';
  if FEdit.CanFocus then
    FEdit.SetFocus;
end;

{ The form scales every control after FormCreate, this one's height too,
  which is already the screen's: set it again. }
procedure TGittanSearchBox.DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
  const AXProportion, AYProportion: double);
begin
  inherited DoAutoAdjustLayout(AMode, AXProportion, AYProportion);
  if AMode = lapAutoAdjustForDPI then
    FitHeight;
end;

end.
