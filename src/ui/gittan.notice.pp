unit gittan.notice;

{** A notice: a panel in the middle of the form that says what is going
  on, with the application icon above a title and the last lines of a
  detail text under it, such as what a pre-push hook writes while it
  runs, or why a push or a commit failed, drawn by a TGittanConsole
  with the colors the hook asks for. Like the popup list and the commit graph
  it is a child of the form, placed over whatever the form shows; unlike
  them it takes no focus, so a commit message being typed goes on, and
  it stays when the application goes to the background, so a long hook
  is still in view on coming back.

  A busy notice animates the dots after its title and follows the end
  of its detail. One that is not busy (a report, nkBad for a failure
  with its title in red) shows more lines, which the wheel scrolls, and
  buttons at the bottom right (SetButtons, OnButton with the index; the
  first is the default, filled). Its close button or a click outside
  it closes it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, ExtCtrls, LCLType,
  gittan.console, gittan.popuphook;

type
  {** How the notice's title is colored. }
  TGittanNoticeKind = (nkNormal, nkBad);

  {** A click on the button at AIndex in SetButtons' list. }
  TGittanNoticeButtonEvent = procedure(Sender: TObject; AIndex: integer) of object;

  { TGittanNotice }

  TGittanNotice = class(TCustomControl)
  private
    FTitle, FDetail: string;
    FKind: TGittanNoticeKind;
    FBusy, FCloseHot: boolean;
    FDots: integer;
    FIcon: TIcon;
    FIconBitmap: TBitmap;
    FConsole: TGittanConsole;
    FBack, FText, FDim, FHover, FLine, FAccent, FBad: TColor;
    FCloseRect: TRect;
    FTimer: TTimer;
    { How many detail lines fit. }
    FShown: integer;
    FButtons: TStringArray;
    FButtonRects: array of TRect;
    FHotButton: integer;
    FOnButton: TGittanNoticeButtonEvent;
    FHook: TGittanPopupHook;
    procedure SetCloseHot(AValue: boolean);
    procedure SetHotButton(AValue: integer);
    procedure SetTitle(const AValue: string);
    procedure SetDetail(const AValue: string);
    procedure SetBusy(AValue: boolean);
    procedure TimerTimer(Sender: TObject);
    function MaxShown: integer;
    function ButtonAt(X, Y: integer): integer;
    function GetDetailFont: TFont;
    function GetPlainDetail: string;
    procedure Place;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: integer;
      MousePos: TPoint): boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** The application icon, drawn above the title; nil draws none. The
      icon stays the caller's. }
    procedure SetIcon(AIcon: TIcon);
    {** The palette: AAccent fills the default button, ABad colors the
      title of an nkBad notice. }
    procedure SetColors(ABack, AText, ADim, AHover, ALine, AAccent, ABad: TColor);
    {** Shows the notice with ATitle over ADetail's last lines, in the
      middle of the parent, busy (with the dots moving) when ABusy, and
      without buttons until SetButtons gives some. }
    procedure Popup(const ATitle, ADetail: string; ABusy: boolean;
      AKind: TGittanNoticeKind = nkNormal);
    {** The buttons at the bottom right, the first the default. }
    procedure SetButtons(const ACaptions: array of string);
    procedure Close;
    {** Keeps it in the middle when the parent is resized. }
    procedure Recenter;
    property Title: string read FTitle write SetTitle;
    {** The text whose last lines are shown, as a terminal shows it,
      with its colors. }
    property Detail: string read FDetail write SetDetail;
    {** Detail without its escape sequences, for the clipboard. }
    property PlainDetail: string read GetPlainDetail;
    property Busy: boolean read FBusy write SetBusy;
    property Kind: TGittanNoticeKind read FKind;
    {** The detail's font: the editor's, so a hook's output lines up. }
    property DetailFont: TFont read GetDetailFont;
    property OnButton: TGittanNoticeButtonEvent read FOnButton write FOnButton;
  end;

implementation

uses
  Math, LCLIntf, gittan.theme;

const
  Pad = 24;
  Gap = 12;
  Margin = 40;
  BusyWidth = 560;
  ReportWidth = 760;
  IconSize = 48;
  CloseSize = 24;
  BusyLines = 8;
  ReportLines = 18;
  Border = 1;
  DotPause = 400;
  ButtonPadX = 14;
  ButtonPadY = 6;
  ButtonGap = 8;

{ TGittanNotice }

constructor TGittanNotice.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { Unlike the lists, the notice stays up when Gittan goes to the
    background. }
  FHook := TGittanPopupHook.Create(Self, @Close, False);
  ControlStyle := ControlStyle + [csOpaque];
  Visible := False;
  FConsole := TGittanConsole.Create(Self);
  FConsole.Parent := Self;
  FConsole.Visible := False;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := DotPause;
  FTimer.OnTimer := @TimerTimer;
  FDots := 3;
  FHotButton := -1;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnShadow, clHighlight, clRed);
end;

destructor TGittanNotice.Destroy;
begin
  FHook.Hook(False);
  FIconBitmap.Free;
  inherited Destroy;
end;

procedure TGittanNotice.SetIcon(AIcon: TIcon);
begin
  FIcon := AIcon;
  FreeAndNil(FIconBitmap);
  Invalidate;
end;

procedure TGittanNotice.SetColors(ABack, AText, ADim, AHover, ALine, AAccent, ABad: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
  FLine := ALine;
  FAccent := AAccent;
  FBad := ABad;
  Color := ABack;
  FConsole.SetColors(ABack, AText, ALine);
  Invalidate;
end;

function TGittanNotice.GetDetailFont: TFont;
begin
  Result := FConsole.Font;
end;

function TGittanNotice.GetPlainDetail: string;
begin
  Result := FConsole.PlainText;
end;

procedure TGittanNotice.SetTitle(const AValue: string);
begin
  if FTitle = AValue then
    Exit;
  FTitle := AValue;
  Invalidate;
end;

procedure TGittanNotice.SetDetail(const AValue: string);
begin
  if FDetail = AValue then
    Exit;
  FDetail := AValue;
  FConsole.Text := AValue;
  if Visible then
    Place;
  Invalidate;
end;

procedure TGittanNotice.SetBusy(AValue: boolean);
begin
  if FBusy = AValue then
    Exit;
  FBusy := AValue;
  FConsole.FollowEnd := AValue;
  FTimer.Enabled := AValue and Visible;
  if Visible then
    Place;
  Invalidate;
end;

procedure TGittanNotice.TimerTimer(Sender: TObject);
begin
  FDots := FDots mod 3 + 1;
  Invalidate;
end;

function TGittanNotice.MaxShown: integer;
begin
  if FBusy then
    Result := BusyLines
  else
    Result := ReportLines;
end;

procedure TGittanNotice.Popup(const ATitle, ADetail: string; ABusy: boolean;
  AKind: TGittanNoticeKind);
begin
  FTitle := ATitle;
  FDetail := ADetail;
  FBusy := ABusy;
  FKind := AKind;
  FButtons := nil;
  FHotButton := -1;
  FCloseHot := False;
  { The view is at the end, where a failure says what went wrong. }
  FConsole.Text := ADetail;
  FConsole.FollowEnd := ABusy;
  Place;
  Visible := True;
  BringToFront;
  FTimer.Enabled := ABusy;
  Invalidate;
  FHook.Hook(True);
end;

procedure TGittanNotice.SetButtons(const ACaptions: array of string);
var
  i: integer;
begin
  SetLength(FButtons, Length(ACaptions));
  for i := 0 to High(ACaptions) do
    FButtons[i] := ACaptions[i];
  FHotButton := -1;
  if Visible then
    Place;
  Invalidate;
end;

procedure TGittanNotice.Close;
begin
  if not Visible then
    Exit;
  FHook.Hook(False);
  FTimer.Enabled := False;
  Visible := False;
end;

procedure TGittanNotice.Recenter;
begin
  if Visible then
    Place;
end;

{ In the middle of the parent, as wide as it allows up to BusyWidth or
  ReportWidth, as high as the icon, the title, the detail lines and the
  buttons need; the console under the title scrolls the lines that do
  not fit. }
procedure TGittanNotice.Place;
var
  W, H, TitleHeight, LineHeight, ButtonHeight, Room, X, i, DetailTop: integer;
begin
  if Parent = nil then
    Exit;
  if FBusy then
    W := Px(BusyWidth)
  else
    W := Px(ReportWidth);
  W := Max(240, Min(W, Parent.ClientWidth - 2 * Px(Margin)));
  Canvas.Font := Font;
  ButtonHeight := Canvas.TextHeight('Xg') + 2 * Px(ButtonPadY);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Size := Max(Font.Size, 13) + 1;
  TitleHeight := Canvas.TextHeight('Xg');
  Canvas.Font := FConsole.Font;
  LineHeight := Max(1, Canvas.TextHeight('Xg'));
  H := 2 * Px(Pad) + TitleHeight;
  if (FIcon <> nil) and not FIcon.Empty then
    Inc(H, Px(IconSize) + Px(Gap));
  DetailTop := H - Px(Pad) + Px(Gap);
  if Length(FButtons) > 0 then
    Inc(H, Px(Gap) + ButtonHeight);
  Room := Parent.ClientHeight - 2 * Px(Margin) - H - Px(Gap);
  FShown := Max(0, Min(Min(FConsole.LineCount, MaxShown), Room div LineHeight));
  if FShown > 0 then
    Inc(H, Px(Gap) + FShown * LineHeight);
  SetBounds((Parent.ClientWidth - W) div 2, (Parent.ClientHeight - H) div 2, W, H);
  { The bar goes in the right padding, as far in as the close button. }
  FConsole.SetBounds(Px(Pad), DetailTop, W - Px(Pad) - Px(Pad) div 2, FShown * LineHeight);
  FConsole.Visible := FShown > 0;
  FCloseRect := Rect(W - Px(Pad) - Px(CloseSize) + 10, Px(Pad) - Px(CloseSize) div 2 - 2,
    W - Px(Pad) + 10, Px(Pad) + Px(CloseSize) div 2 - 2);
  { The buttons from the right: the first, the default, at the right
    end, as macOS places it. }
  SetLength(FButtonRects, Length(FButtons));
  Canvas.Font := Font;
  X := W - Px(Pad);
  for i := 0 to High(FButtons) do
  begin
    FButtonRects[i] := Rect(X - Canvas.TextWidth(FButtons[i]) - 2 * Px(ButtonPadX),
      H - Px(Pad) - ButtonHeight, X, H - Px(Pad));
    X := FButtonRects[i].Left - Px(ButtonGap);
  end;
end;

function TGittanNotice.ButtonAt(X, Y: integer): integer;
var
  i: integer;
begin
  for i := 0 to High(FButtonRects) do
    if PtInRect(FButtonRects[i], Point(X, Y)) then
      Exit(i);
  Result := -1;
end;

procedure TGittanNotice.SetCloseHot(AValue: boolean);
begin
  if FCloseHot = AValue then
    Exit;
  FCloseHot := AValue;
  Invalidate;
end;

procedure TGittanNotice.SetHotButton(AValue: integer);
begin
  if FHotButton = AValue then
    Exit;
  FHotButton := AValue;
  if AValue >= 0 then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  Invalidate;
end;

procedure TGittanNotice.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetCloseHot(PtInRect(FCloseRect, Point(X, Y)));
  SetHotButton(ButtonAt(X, Y));
end;

procedure TGittanNotice.MouseLeave;
begin
  inherited MouseLeave;
  SetCloseHot(False);
  SetHotButton(-1);
end;

procedure TGittanNotice.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  Index: integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  if PtInRect(FCloseRect, Point(X, Y)) then
    Close
  else
  begin
    Index := ButtonAt(X, Y);
    if (Index >= 0) and Assigned(FOnButton) then
      FOnButton(Self, Index);
  end;
end;

function TGittanNotice.DoMouseWheel(Shift: TShiftState; WheelDelta: integer;
  MousePos: TPoint): boolean;
begin
  { Over the title or the buttons: the console scrolls. }
  Result := True;
  FConsole.Wheel(WheelDelta);
end;

procedure TGittanNotice.Paint;
var
  X, Y, i: integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := FLine;
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(0, 0, Width, Height);
  Y := Px(Pad);

  if (FIcon <> nil) and not FIcon.Empty then
  begin
    { As in the welcome view: the image for the size in device pixels,
      copied into a bitmap, since the icon's handle is made from its
      smallest image. }
    if FIconBitmap = nil then
    begin
      FIcon.Current := FIcon.GetBestIndexForSize(
        Size(Round(Px(IconSize) * GetCanvasScaleFactor), Round(Px(IconSize) * GetCanvasScaleFactor)));
      FIconBitmap := TBitmap.Create;
      FIconBitmap.LoadFromRawImage(FIcon.RawImage, False);
    end;
    Canvas.StretchDraw(Rect((Width - Px(IconSize)) div 2, Y, (Width + Px(IconSize)) div 2,
      Y + Px(IconSize)), FIconBitmap);
    Inc(Y, Px(IconSize) + Px(Gap));
  end;

  { The dots follow the title without moving it. }
  Canvas.Font := Font;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Size := Max(Font.Size, 13) + 1;
  if FKind = nkBad then
    Canvas.Font.Color := FBad
  else
    Canvas.Font.Color := FText;
  X := (Width - Canvas.TextWidth(FTitle)) div 2;
  Canvas.TextOut(X, Y, FTitle);
  if FBusy then
    Canvas.TextOut(X + Canvas.TextWidth(FTitle), Y, StringOfChar('.', FDots));

  Canvas.Font := Font;
  for i := 0 to High(FButtons) do
  begin
    with FButtonRects[i] do
    begin
      Canvas.Brush.Style := bsSolid;
      if i = 0 then
      begin
        Canvas.Brush.Color := FAccent;
        Canvas.Pen.Color := FAccent;
        Canvas.Font.Color := clWhite;
      end
      else
      begin
        if i = FHotButton then
          Canvas.Brush.Color := FHover
        else
          Canvas.Brush.Color := FBack;
        Canvas.Pen.Color := FLine;
        Canvas.Font.Color := FText;
      end;
      Canvas.RoundRect(Left, Top, Right, Bottom, 8, 8);
      Canvas.Brush.Style := bsClear;
      Canvas.TextOut(Left + Px(ButtonPadX), Top + Px(ButtonPadY), FButtons[i]);
    end;
  end;

  if FCloseHot then
  begin
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FHover;
    Canvas.RoundRect(FCloseRect, 6, 6);
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsClear;
  end;
  Canvas.Pen.Color := FDim;
  Canvas.Pen.Width := 2;
  with FCloseRect do
  begin
    Canvas.Line(Left + 8, Top + 8, Right - 8, Bottom - 8);
    Canvas.Line(Right - 8, Top + 8, Left + 8, Bottom - 8);
  end;
  Canvas.Pen.Width := 1;
end;

end.
