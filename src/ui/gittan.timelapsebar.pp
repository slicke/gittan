unit gittan.timelapsebar;

{** The time-lapse bar under the editor: a play button, the commit of
  the version shown (its hash, date, author and summary) with a counter,
  and a track with a dot per version, oldest at the left, and a knob on
  the one shown that can be dragged.

  It paints itself with the colors the frame gives it, as the change
  navigator does, and tells the frame what the user did: OnSeek when a
  click or a drag on the track picked another version, OnPlay when the
  play button was clicked. The frame sets the position and whether it
  plays; neither fires an event. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, LCLType;

type
  {** The color of version AIndex's dot. }
  TGittanTimelapseColorEvent = function(AIndex: integer): TColor of object;

  { TGittanTimelapseBar }

  TGittanTimelapseBar = class(TCustomControl)
  private
    FCount, FPosition: integer;
    FPlaying, FDragging, FPlayPressed, FPlayHot: boolean;
    FInfo, FCounter: string;
    FBackColor, FTextColor, FDimColor, FLineColor, FAccentColor: TColor;
    FOnColor: TGittanTimelapseColorEvent;
    FOnSeek, FOnPlay: TNotifyEvent;
    function PlayRect: TRect;
    function TrackLeft: integer;
    function TrackRight: integer;
    function TrackY: integer;
    function XOf(AIndex: integer): integer;
    function IndexAt(X: integer): integer;
    function DotColor(AIndex: integer): TColor;
    procedure SeekTo(X: integer);
    procedure SetPlaying(AValue: boolean);
    procedure SetPosition(AValue: integer);
  protected
    procedure DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
      const AXProportion, AYProportion: double); override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    {** ABack is the bar, AText the commit, ADim the counter and the
      track's far side, ALine the line above the bar, AAccent the play
      button. }
    procedure SetColors(ABack, AText, ADim, ALine, AAccent: TColor);
    {** Shows ACount versions, the position at the oldest. }
    procedure SetCount(ACount: integer);
    {** What the bar says about the version shown, and its counter. }
    procedure SetInfo(const AInfo, ACounter: string);
    property Position: integer read FPosition write SetPosition;
    property Playing: boolean read FPlaying write SetPlaying;
    property OnColor: TGittanTimelapseColorEvent read FOnColor write FOnColor;
    property OnSeek: TNotifyEvent read FOnSeek write FOnSeek;
    property OnPlay: TNotifyEvent read FOnPlay write FOnPlay;
  end;

implementation

uses
  Math, Types, gittan.textfit, gittan.theme;

const
  BarHeight = 52;
  Margin = 14;
  PlaySize = 28;
  TextTop = 7;
  TrackBottom = 14;
  KnobRadius = 6;
  DotRadius = 2;
  { Dots closer than this are left out; the track alone shows the time. }
  DotSpacing = 6;

{ TGittanTimelapseBar }

constructor TGittanTimelapseBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Height := Px(BarHeight);
  SetColors(clBtnFace, clWindowText, clGrayText, clBtnShadow, clHighlight);
end;

procedure TGittanTimelapseBar.SetColors(ABack, AText, ADim, ALine, AAccent: TColor);
begin
  FBackColor := ABack;
  FTextColor := AText;
  FDimColor := ADim;
  FLineColor := ALine;
  FAccentColor := AAccent;
  Color := ABack;
  Invalidate;
end;

procedure TGittanTimelapseBar.SetCount(ACount: integer);
begin
  FCount := Max(0, ACount);
  FPosition := 0;
  FDragging := False;
  Invalidate;
end;

procedure TGittanTimelapseBar.SetInfo(const AInfo, ACounter: string);
begin
  FInfo := AInfo;
  FCounter := ACounter;
  Invalidate;
end;

procedure TGittanTimelapseBar.SetPosition(AValue: integer);
begin
  AValue := Max(0, Min(AValue, FCount - 1));
  if FPosition = AValue then
    Exit;
  FPosition := AValue;
  Invalidate;
end;

procedure TGittanTimelapseBar.SetPlaying(AValue: boolean);
begin
  if FPlaying = AValue then
    Exit;
  FPlaying := AValue;
  Invalidate;
end;

function TGittanTimelapseBar.PlayRect: TRect;
var
  Y: integer;
begin
  Y := (Height - Px(PlaySize)) div 2;
  Result := Rect(Px(Margin), Y, Px(Margin) + Px(PlaySize), Y + Px(PlaySize));
end;

function TGittanTimelapseBar.TrackLeft: integer;
begin
  Result := PlayRect.Right + Px(Margin);
end;

function TGittanTimelapseBar.TrackRight: integer;
begin
  Result := Max(TrackLeft + 1, Width - Px(Margin) - Px(KnobRadius));
end;

function TGittanTimelapseBar.TrackY: integer;
begin
  Result := Height - Px(TrackBottom);
end;

function TGittanTimelapseBar.XOf(AIndex: integer): integer;
begin
  if FCount <= 1 then
    Exit(TrackLeft);
  Result := TrackLeft + MulDiv(TrackRight - TrackLeft, AIndex, FCount - 1);
end;

function TGittanTimelapseBar.IndexAt(X: integer): integer;
begin
  if FCount <= 1 then
    Exit(0);
  Result := Round((X - TrackLeft) * (FCount - 1) / Max(1, TrackRight - TrackLeft));
  Result := Max(0, Min(Result, FCount - 1));
end;

function TGittanTimelapseBar.DotColor(AIndex: integer): TColor;
begin
  if Assigned(FOnColor) then
    Result := FOnColor(AIndex)
  else
    Result := FAccentColor;
end;

procedure TGittanTimelapseBar.SeekTo(X: integer);
var
  Index: integer;
begin
  Index := IndexAt(X);
  if Index = FPosition then
    Exit;
  FPosition := Index;
  Invalidate;
  if Assigned(FOnSeek) then
    FOnSeek(Self);
end;

procedure TGittanTimelapseBar.Paint;
var
  R: TRect;
  TextLeft, TextRight, Y, X, i, Mid, Third, CounterW, InfoW: integer;
  Knob: TColor;
begin
  R := ClientRect;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBackColor;
  Canvas.FillRect(R);
  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := FLineColor;
  Canvas.Line(0, 0, Width, 0);
  { The play button: a disc with a triangle, or two bars while it
    plays. }
  R := PlayRect;
  if FPlayHot or FPlayPressed then
    Canvas.Brush.Color := MixColor(FAccentColor, FTextColor, 0.25)
  else
    Canvas.Brush.Color := FAccentColor;
  Canvas.Pen.Style := psClear;
  Canvas.Ellipse(R);
  Canvas.Brush.Color := FBackColor;
  Mid := (R.Top + R.Bottom) div 2;
  Third := (R.Right - R.Left) div 3;
  if FPlaying then
  begin
    Canvas.FillRect(Rect(R.Left + Third, Mid - Third + Third div 4,
      R.Left + Third + Third div 3 + 1, Mid + Third - Third div 4));
    Canvas.FillRect(Rect(R.Right - Third - Third div 3 - 1, Mid - Third + Third div 4,
      R.Right - Third, Mid + Third - Third div 4));
  end
  else
    Canvas.Polygon([Point(R.Left + Third + Third div 4, Mid - Third + Third div 4),
      Point(R.Left + Third + Third div 4, Mid + Third - Third div 4),
      Point(R.Right - Third + Third div 4, Mid)]);
  Canvas.Pen.Style := psSolid;
  { The commit of the version shown, and the counter right of it. }
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  TextLeft := TrackLeft;
  TextRight := Width - Px(Margin);
  CounterW := Canvas.TextWidth(FCounter);
  Canvas.Font.Color := FDimColor;
  Canvas.TextOut(TextRight - CounterW, Px(TextTop), FCounter);
  InfoW := TextRight - CounterW - Px(Margin) - TextLeft;
  Canvas.Font.Color := FTextColor;
  Canvas.TextOut(TextLeft, Px(TextTop), FitTextRight(Canvas, FInfo, InfoW));
  if FCount = 0 then
    Exit;
  { The track: passed in the knob's color, ahead dimmed. }
  Knob := DotColor(FPosition);
  Y := TrackY;
  X := XOf(FPosition);
  Canvas.Brush.Style := bsSolid;
  Canvas.Pen.Style := psClear;
  Canvas.Brush.Color := FLineColor;
  Canvas.RoundRect(TrackLeft, Y - Px(2), TrackRight, Y + Px(2), Px(4), Px(4));
  Canvas.Brush.Color := MixColor(FLineColor, Knob, 0.6);
  Canvas.RoundRect(TrackLeft, Y - Px(2), Max(TrackLeft + Px(4), X), Y + Px(2), Px(4), Px(4));
  if (FCount > 1) and ((TrackRight - TrackLeft) div (FCount - 1) >= Px(DotSpacing)) then
    for i := 0 to FCount - 1 do
    begin
      if i = FPosition then
        Continue;
      if i < FPosition then
        Canvas.Brush.Color := DotColor(i)
      else
        Canvas.Brush.Color := MixColor(FLineColor, DotColor(i), 0.35);
      Canvas.Ellipse(XOf(i) - Px(DotRadius), Y - Px(DotRadius), XOf(i) + Px(DotRadius) + 1,
        Y + Px(DotRadius) + 1);
    end;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := FBackColor;
  Canvas.Pen.Width := Px(2);
  Canvas.Brush.Color := Knob;
  Canvas.Ellipse(X - Px(KnobRadius), Y - Px(KnobRadius), X + Px(KnobRadius) + 1,
    Y + Px(KnobRadius) + 1);
  Canvas.Pen.Width := 1;
end;

procedure TGittanTimelapseBar.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  if PtInRect(PlayRect, Point(X, Y)) then
  begin
    FPlayPressed := True;
    Invalidate;
    Exit;
  end;
  if (FCount > 0) and (X >= TrackLeft - Px(KnobRadius)) and (Y >= Height div 2) then
  begin
    FDragging := True;
    SeekTo(X);
  end;
end;

procedure TGittanTimelapseBar.MouseMove(Shift: TShiftState; X, Y: integer);
var
  Hot: boolean;
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging then
  begin
    SeekTo(X);
    Exit;
  end;
  Hot := PtInRect(PlayRect, Point(X, Y));
  if Hot <> FPlayHot then
  begin
    FPlayHot := Hot;
    Invalidate;
  end;
  if Hot or ((FCount > 0) and (X >= TrackLeft - Px(KnobRadius)) and (Y >= Height div 2)) then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
end;

{ The play button fires on release over it. }
procedure TGittanTimelapseBar.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Play: boolean;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  FDragging := False;
  Play := FPlayPressed and PtInRect(PlayRect, Point(X, Y));
  FPlayPressed := False;
  Invalidate;
  if Play and Assigned(FOnPlay) then
    FOnPlay(Self);
end;

procedure TGittanTimelapseBar.MouseLeave;
begin
  inherited MouseLeave;
  if FPlayHot then
  begin
    FPlayHot := False;
    Invalidate;
  end;
end;

{ The form scales every control by its DPI after FormCreate, this one's
  height too, which is already the screen's: set it again. }
procedure TGittanTimelapseBar.DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
  const AXProportion, AYProportion: double);
begin
  inherited DoAutoAdjustLayout(AMode, AXProportion, AYProportion);
  if AMode = lapAutoAdjustForDPI then
    Height := Px(BarHeight);
end;

end.
