unit gittan.changenav;

{** The change navigator: a pill floating over the editor with a button for
  the previous and the next change and a counter ("2 / 5") between them.

  It paints itself with the editor's colors instead of taking the
  widgetset's button look: on macOS a push button keeps its light bezel on
  a dark editor. It is a windowed control because ATSynEdit never paints
  graphic children. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, LCLType;

type
  {** The parts of the navigator a mouse position can hit. }
  TGittanNavPart = (npNone, npPrev, npCounter, npNext);

  { TGittanChangeNav }

  TGittanChangeNav = class(TCustomControl)
  private
    FCurrent, FTotal: integer;
    FSuffix: string;
    FHot, FPressed: TGittanNavPart;
    FBackColor, FFillColor, FBorderColor, FTextColor, FHotColor: TColor;
    FOnPrev, FOnNext: TNotifyEvent;
    function ButtonWidth: integer;
    function CounterText: string;
    function PartAt(X: integer): TGittanNavPart;
    procedure SetHot(AValue: TGittanNavPart);
    procedure SetSuffix(const AValue: string);
    procedure DrawArrow(ACenterX, ACenterY: integer; AUp: boolean; AColor: TColor);
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    constructor Create(AOwner: TComponent); override;
    {** Sets the colors: ABack is the editor background the pill sits on,
      AFill and ABorder the pill, AText the arrows and counter, AHot the
      arrow under the mouse. }
    procedure SetColors(ABack, AFill, ABorder, AText, AHot: TColor);
    {** Shows ACurrent of ATotal changes; ACurrent is 0 before the first. }
    procedure SetPosition(ACurrent, ATotal: integer);
    {** A word after the counter ("1 / 3 conflicts"), none by default. }
    property Suffix: string read FSuffix write SetSuffix;
    property OnPrev: TNotifyEvent read FOnPrev write FOnPrev;
    property OnNext: TNotifyEvent read FOnNext write FOnNext;
  end;

implementation

const
  NavHeight = 30;
  CounterPadding = 6;

{ TGittanChangeNav }

constructor TGittanChangeNav.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Height := NavHeight;
  Width := 3 * NavHeight;
  Cursor := crHandPoint;
  SetColors(clWindow, clBtnFace, clBtnShadow, clWindowText, clHighlight);
end;

procedure TGittanChangeNav.SetColors(ABack, AFill, ABorder, AText, AHot: TColor);
begin
  FBackColor := ABack;
  FFillColor := AFill;
  FBorderColor := ABorder;
  FTextColor := AText;
  FHotColor := AHot;
  Color := ABack;
  Invalidate;
end;

procedure TGittanChangeNav.SetPosition(ACurrent, ATotal: integer);
var
  Measure: TBitmap;
begin
  FCurrent := ACurrent;
  FTotal := ATotal;
  { The width follows the counter text, measured on a bitmap so it works
    before the handle exists; the right anchor keeps the pill in place
    while it grows. }
  Measure := TBitmap.Create;
  try
    Measure.Canvas.Font := Font;
    Width := 2 * ButtonWidth + Measure.Canvas.TextWidth(CounterText) +
      2 * CounterPadding;
  finally
    Measure.Free;
  end;
  Invalidate;
end;

procedure TGittanChangeNav.SetSuffix(const AValue: string);
begin
  if FSuffix = AValue then
    Exit;
  FSuffix := AValue;
  SetPosition(FCurrent, FTotal);
end;

function TGittanChangeNav.ButtonWidth: integer;
begin
  Result := Height;
end;

{ Before the caret has reached a change there is no current one, and a
  dash says so better than a zero. }
function TGittanChangeNav.CounterText: string;
begin
  if FCurrent = 0 then
    Result := Format('– / %d', [FTotal])
  else
    Result := Format('%d / %d', [FCurrent, FTotal]);
  if FSuffix <> '' then
    Result := Result + ' ' + FSuffix;
end;

function TGittanChangeNav.PartAt(X: integer): TGittanNavPart;
begin
  if X < ButtonWidth then
    Result := npPrev
  else if X >= Width - ButtonWidth then
    Result := npNext
  else
    Result := npCounter;
end;

procedure TGittanChangeNav.SetHot(AValue: TGittanNavPart);
begin
  if FHot = AValue then
    Exit;
  FHot := AValue;
  Invalidate;
end;

{ A triangle with the point up or down, sized from the control height. }
procedure TGittanChangeNav.DrawArrow(ACenterX, ACenterY: integer; AUp: boolean;
  AColor: TColor);
var
  Half, Tall: integer;
begin
  Half := Height div 6;
  Tall := Height div 6;
  Canvas.Pen.Color := AColor;
  Canvas.Brush.Color := AColor;
  Canvas.Brush.Style := bsSolid;
  if AUp then
    Canvas.Polygon([Point(ACenterX - Half, ACenterY + Tall div 2),
      Point(ACenterX + Half, ACenterY + Tall div 2),
      Point(ACenterX, ACenterY - Tall div 2 - 1)])
  else
    Canvas.Polygon([Point(ACenterX - Half, ACenterY - Tall div 2),
      Point(ACenterX + Half, ACenterY - Tall div 2),
      Point(ACenterX, ACenterY + Tall div 2 + 1)]);
end;

procedure TGittanChangeNav.Paint;
var
  R: TRect;
  Counter: string;
  Mid: integer;

  function ArrowColor(APart: TGittanNavPart): TColor;
  begin
    if (FPressed = APart) or ((FPressed = npNone) and (FHot = APart)) then
      Result := FHotColor
    else
      Result := FTextColor;
  end;

begin
  R := ClientRect;
  { The editor's background behind the rounded corners. }
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBackColor;
  Canvas.FillRect(R);
  Canvas.Pen.Color := FBorderColor;
  Canvas.Pen.Width := 1;
  Canvas.Brush.Color := FFillColor;
  Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Height, Height);
  Mid := Height div 2;
  DrawArrow(ButtonWidth div 2 + 1, Mid, True, ArrowColor(npPrev));
  DrawArrow(Width - ButtonWidth div 2 - 1, Mid, False, ArrowColor(npNext));
  Counter := CounterText;
  Canvas.Font := Font;
  Canvas.Font.Color := FTextColor;
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut((Width - Canvas.TextWidth(Counter)) div 2,
    (Height - Canvas.TextHeight(Counter)) div 2, Counter);
end;

procedure TGittanChangeNav.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(PartAt(X));
end;

procedure TGittanChangeNav.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(npNone);
end;

procedure TGittanChangeNav.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FPressed := PartAt(X);
    Invalidate;
  end;
end;

{ The click fires on release over the part that was pressed. }
procedure TGittanChangeNav.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Part: TGittanNavPart;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  Part := FPressed;
  FPressed := npNone;
  Invalidate;
  if Part <> PartAt(X) then
    Exit;
  case Part of
    npPrev: if Assigned(FOnPrev) then
        FOnPrev(Self);
    npNext: if Assigned(FOnNext) then
        FOnNext(Self);
  end;
end;

end.
