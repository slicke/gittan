unit gittan.hoverpills;

{** A strip of pills that appears at the end of the row the mouse is
  on and offers an action or two: made for the change view, where a
  changed row gets Keep and Discard for its block, after a check mark
  or the discard arrow. Show places
  the strip at the right end of an anchor rectangle given in screen
  coordinates (the row, across the text), centered on its height and
  within the parent; a click on a pill raises OnPick with its index in
  the order given to Show; OnLeave says the mouse left the strip, so
  whoever showed it can hide it (Dismiss). It takes no focus and no
  keys. The strip is a child of the form it shows in, placed over
  whatever the form shows, as the popup lists are (see
  gittan.popuplist), and paints itself in the colors SetColors gives:
  the box, its border, the text, the text of the pill under the mouse,
  and the check mark and the arrow. Its font is a size under the
  form's, so the strip stays near the height of a row. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics;

type
  TGittanPillPickEvent = procedure(Sender: TObject; AIndex: integer) of object;

  { TGittanHoverPills }

  TGittanHoverPills = class(TCustomControl)
  private
    FCaptions: array of string;
    FRects: array of TRect;
    FIcons: string;
    FHot, FPressed: integer;
    FBack, FText, FLine, FHotColor, FKeepColor, FDiscardColor: TColor;
    FOnPick: TGittanPillPickEvent;
    FOnLeave: TNotifyEvent;
    function PillAt(X, Y: integer): integer;
    function ArrowWidth(APillHeight: integer): integer;
    procedure DrawArrow(ALeft, ATop, APillHeight: integer; AColor: TColor);
    procedure DrawCheck(ALeft, ATop, APillHeight: integer; AColor: TColor);
    procedure SetHot(AValue: integer);
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    {** Shows the strip with these pills at the right end of AAnchor (a
      rectangle in screen coordinates: the row the mouse is on, across
      the text), centered on its height and kept within the parent.
      AIcons gives each pill its icon by position: 'k' a check mark in
      the keep color, 'd' the discard arrow (an arrow going back round
      a circle, as the band's button) in the discard color, anything
      else none. Showing it again at the same place with the same pills
      changes nothing. }
    procedure Show(const AAnchor: TRect; const ACaptions: array of string;
      const AIcons: string = '');
    {** Hides the strip. }
    procedure Dismiss;
    {** The colors: the box, the text, the border, the text of the pill
      under the mouse, the check mark and the discard arrow. }
    procedure SetColors(ABack, AText, ALine, AHot, AKeep, ADiscard: TColor);
    property OnPick: TGittanPillPickEvent read FOnPick write FOnPick;
    property OnLeave: TNotifyEvent read FOnLeave write FOnLeave;
  end;

implementation

uses
  Math;

const
  { Around the pills, inside the box; between the pills; inside a pill
    beside its text and above and below it; between the arrow and the
    text; and between the anchor's right edge and the box. }
  Pad = 2;
  PillGap = 4;
  PillPad = 8;
  PillRise = 2;
  ArrowGap = 5;
  Offset = 4;
  { The font: a size under the form's on every desktop, so the strip
    stays near the height of a row. }
  PillFontSize = 11;

constructor TGittanHoverPills.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Visible := False;
  Cursor := crHandPoint;
  FHot := -1;
  FPressed := -1;
  ParentFont := False;
  Font.Size := PillFontSize;
  SetColors(clWindow, clWindowText, clBtnShadow, clHighlight, clGreen, clRed);
end;

procedure TGittanHoverPills.SetColors(ABack, AText, ALine, AHot, AKeep, ADiscard: TColor);
begin
  FBack := ABack;
  FText := AText;
  FLine := ALine;
  FHotColor := AHot;
  FKeepColor := AKeep;
  FDiscardColor := ADiscard;
  Invalidate;
end;

{ The arrow is a circle a little lower than the text, plus its head. }
function TGittanHoverPills.ArrowWidth(APillHeight: integer): integer;
begin
  Result := Max(3, (APillHeight - 10) div 2) * 2 + 3;
end;

{ The box is as wide as the pills with their padding; a pill is as wide
  as its text, after the icon when there is one. The box is laid out
  from the anchor's right end, moved left when it would run out of the
  parent. }
procedure TGittanHoverPills.Show(const AAnchor: TRect; const ACaptions: array of string;
  const AIcons: string);
var
  Anchor: TRect;
  i, X, W, H, PillH: integer;
  Same: boolean;
begin
  if Parent = nil then
    Exit;
  Same := Visible and (Length(ACaptions) = Length(FCaptions)) and (AIcons = FIcons);
  if Same then
    for i := 0 to High(ACaptions) do
      Same := Same and (ACaptions[i] = FCaptions[i]);
  FIcons := AIcons;
  SetLength(FCaptions, Length(ACaptions));
  for i := 0 to High(ACaptions) do
    FCaptions[i] := ACaptions[i];
  SetLength(FRects, Length(FCaptions));
  Canvas.Font := Font;
  PillH := Canvas.TextHeight('Xg') + 2 * PillRise;
  H := PillH + 2 * Pad;
  X := Pad;
  for i := 0 to High(FCaptions) do
  begin
    W := Canvas.TextWidth(FCaptions[i]) + 2 * PillPad;
    if (i < Length(FIcons)) and (FIcons[i + 1] in ['k', 'd']) then
      W := W + ArrowWidth(PillH) + ArrowGap;
    FRects[i] := Rect(X, Pad, X + W, Pad + PillH);
    X := X + W + PillGap;
  end;
  W := X - PillGap + Pad;
  Anchor.TopLeft := Parent.ScreenToClient(AAnchor.TopLeft);
  Anchor.BottomRight := Parent.ScreenToClient(AAnchor.BottomRight);
  X := Max(0, Min(Anchor.Right - Offset - W, Parent.ClientWidth - W));
  i := Max(0, Min((Anchor.Top + Anchor.Bottom - H) div 2, Parent.ClientHeight - H));
  if Same and (Left = X) and (Top = i) and (Width = W) and (Height = H) then
    Exit;
  FHot := -1;
  FPressed := -1;
  SetBounds(X, i, W, H);
  Visible := True;
  BringToFront;
  Invalidate;
end;

procedure TGittanHoverPills.Dismiss;
begin
  if not Visible then
    Exit;
  Visible := False;
  FHot := -1;
  FPressed := -1;
end;

function TGittanHoverPills.PillAt(X, Y: integer): integer;
var
  i: integer;
begin
  Result := -1;
  for i := 0 to High(FRects) do
    if PtInRect(FRects[i], Point(X, Y)) then
      Exit(i);
end;

procedure TGittanHoverPills.SetHot(AValue: integer);
begin
  if AValue = FHot then
    Exit;
  FHot := AValue;
  Invalidate;
end;

{ Round from the lower right over the top to the left, where the head
  points down: the band's button (see DrawDiscard in umain.discard.inc). }
procedure TGittanHoverPills.DrawArrow(ALeft, ATop, APillHeight: integer; AColor: TColor);
var
  R, A, Cx, Cy: integer;
begin
  R := Max(3, (APillHeight - 10) div 2);
  A := Max(2, (R * 2) div 3);
  Cx := ALeft + R + 1;
  Cy := ATop + APillHeight div 2;
  Canvas.Pen.Color := AColor;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := Max(1, R div 3);
  Canvas.Brush.Style := bsClear;
  Canvas.Arc(Cx - R, Cy - R, Cx + R, Cy + R, 300 * 16, 240 * 16);
  Canvas.Line(Cx - R, Cy + 1, Cx - R - A, Cy + 1 - A);
  Canvas.Line(Cx - R, Cy + 1, Cx - R + A, Cy + 1 - A);
  Canvas.Pen.Width := 1;
end;

{ A check mark in the arrow's box: down to the low point a third of
  the way in, then up to the top right. }
procedure TGittanHoverPills.DrawCheck(ALeft, ATop, APillHeight: integer; AColor: TColor);
var
  R, Cx, Cy: integer;
begin
  R := Max(3, (APillHeight - 10) div 2);
  Cx := ALeft + R + 1;
  Cy := ATop + APillHeight div 2;
  Canvas.Pen.Color := AColor;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := Max(1, R div 3) + 1;
  Canvas.Brush.Style := bsClear;
  Canvas.Polyline([Point(Cx - R, Cy), Point(Cx - R div 3, Cy + R - 1), Point(Cx + R, Cy - R + 1)]);
  Canvas.Pen.Width := 1;
end;

procedure TGittanHoverPills.Paint;
var
  i, X, TextY: integer;
  R: TRect;
  Ink: TColor;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := FLine;
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(0, 0, Width, Height);
  Canvas.Font := Font;
  for i := 0 to High(FRects) do
  begin
    R := FRects[i];
    Canvas.Pen.Color := FLine;
    Canvas.Pen.Width := 1;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FBack;
    Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, R.Height, R.Height);
    Canvas.Brush.Style := bsClear;
    if (FPressed = i) or ((FPressed < 0) and (FHot = i)) then
      Ink := FHotColor
    else
      Ink := FText;
    X := R.Left + PillPad;
    if (i < Length(FIcons)) and (FIcons[i + 1] in ['k', 'd']) then
    begin
      if FIcons[i + 1] = 'k' then
        DrawCheck(X, R.Top, R.Height, FKeepColor)
      else
        DrawArrow(X, R.Top, R.Height, FDiscardColor);
      X := X + ArrowWidth(R.Height) + ArrowGap;
    end;
    Canvas.Font.Color := Ink;
    TextY := R.Top + (R.Height - Canvas.TextHeight(FCaptions[i])) div 2;
    Canvas.TextOut(X, TextY, FCaptions[i]);
  end;
end;

procedure TGittanHoverPills.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(PillAt(X, Y));
end;

procedure TGittanHoverPills.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FPressed := PillAt(X, Y);
    Invalidate;
  end;
end;

{ The pick fires on release over the pill that was pressed. }
procedure TGittanHoverPills.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  i: integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  i := FPressed;
  FPressed := -1;
  Invalidate;
  if (i >= 0) and (PillAt(X, Y) = i) and Assigned(FOnPick) then
    FOnPick(Self, i);
end;

procedure TGittanHoverPills.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1);
  if Assigned(FOnLeave) then
    FOnLeave(Self);
end;

end.
