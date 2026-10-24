unit gittan.sectionheader;

{** A section header: a row with a disclosure chevron, a dim bold
  title as the Files heading over the tree, and a dimmed detail, which
  folds and unfolds what sits under it. Made for the Config section
  under the tree of changed files.

  It paints itself in colors the form sets, like the file header, since
  a native header would keep the desktop's look on a themed panel. A
  click flips Expanded and raises OnToggle; whoever owns the section
  shows or hides the content and sizes it. It can show a check box
  between the title and the detail (CheckIndex, an image of
  CheckImages, as the rows under it draw theirs), whose click raises
  OnCheck instead: the Commit section ticks every file with it. It can
  also show an action at the right end (Action), a link in ActionColor
  underlined under the mouse, whose click raises OnAction instead: the
  Commit section's AI. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, ImgList;

type

  { TGittanSectionHeader }

  TGittanSectionHeader = class(TCustomControl)
  private
    FTitle, FDetail: string;
    FExpanded, FHot: boolean;
    FBack, FText, FDim, FHover, FLine: TColor;
    FOnToggle: TNotifyEvent;
    FCheckImages: TCustomImageList;
    FCheckIndex: integer;
    { The check box as last painted, empty without one. }
    FCheckRect: TRect;
    FOnCheck: TNotifyEvent;
    FAction, FActionHint: string;
    FActionEnabled, FActionHot: boolean;
    FActionColor: TColor;
    { The action as last painted, empty without one. }
    FActionRect: TRect;
    FOnAction: TNotifyEvent;
    procedure SetCheckIndex(AValue: integer);
    procedure SetAction(const AValue: string);
    procedure SetActionEnabled(AValue: boolean);
    procedure SetActionColor(AValue: TColor);
    function OverAction(X, Y: integer): boolean;
    procedure SetTitle(const AValue: string);
    procedure SetDetail(const AValue: string);
    procedure SetExpanded(AValue: boolean);
  protected
    procedure DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
      const AXProportion, AYProportion: double); override;
    procedure Paint; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    constructor Create(AOwner: TComponent); override;
    {** The palette: the background, the text (kept for the rows that
      set it), the dim chevron, title and detail, the fill under the
      mouse and the line along the top. }
    procedure SetColors(ABack, AText, ADim, AHover, ALine: TColor);
    {** The name of the section. }
    property Title: string read FTitle write SetTitle;
    {** Shown dimmed after the title: a count, say. }
    property Detail: string read FDetail write SetDetail;
    {** Whether the section is unfolded; the chevron points down then.
      Setting it does not raise OnToggle. }
    property Expanded: boolean read FExpanded write SetExpanded;
    {** After a click flipped Expanded. }
    property OnToggle: TNotifyEvent read FOnToggle write FOnToggle;
    {** Where the check box's image comes from. }
    property CheckImages: TCustomImageList read FCheckImages write FCheckImages;
    {** The check box's image in CheckImages, -1 (the default) for none. }
    property CheckIndex: integer read FCheckIndex write SetCheckIndex;
    {** A click on the check box, which leaves Expanded alone. }
    property OnCheck: TNotifyEvent read FOnCheck write FOnCheck;
    {** The action's text at the right end, '' (the default) for none. }
    property Action: string read FAction write SetAction;
    {** The hint shown over the action, and only there. }
    property ActionHint: string read FActionHint write FActionHint;
    {** Whether a click on the action raises OnAction; a disabled one is
      dimmed and its click does nothing, not even fold. }
    property ActionEnabled: boolean read FActionEnabled write SetActionEnabled;
    {** The action's color while it is enabled: the link color. }
    property ActionColor: TColor read FActionColor write SetActionColor;
    {** A click on the action, which leaves Expanded alone. }
    property OnAction: TNotifyEvent read FOnAction write FOnAction;
  end;

implementation


uses
  gittan.theme;
const
  HeaderHeight = 26;
  Pad = 10;
  ChevronSize = 4;
  Gap = 8;

{ TGittanSectionHeader }

constructor TGittanSectionHeader.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Height := Px(HeaderHeight);
  Cursor := crHandPoint;
  FCheckIndex := -1;
  FActionEnabled := True;
  FActionColor := clHighlight;
  ShowHint := True;
  SetColors(clBtnFace, clWindowText, clGrayText, clBtnFace, clBtnShadow);
end;

procedure TGittanSectionHeader.SetColors(ABack, AText, ADim, AHover, ALine: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
  FLine := ALine;
  Invalidate;
end;

procedure TGittanSectionHeader.SetCheckIndex(AValue: integer);
begin
  if FCheckIndex = AValue then
    Exit;
  FCheckIndex := AValue;
  Invalidate;
end;

procedure TGittanSectionHeader.SetAction(const AValue: string);
begin
  if FAction = AValue then
    Exit;
  FAction := AValue;
  if FAction = '' then
  begin
    FActionHot := False;
    Hint := '';
  end;
  Invalidate;
end;

procedure TGittanSectionHeader.SetActionEnabled(AValue: boolean);
begin
  if FActionEnabled = AValue then
    Exit;
  FActionEnabled := AValue;
  Invalidate;
end;

procedure TGittanSectionHeader.SetActionColor(AValue: TColor);
begin
  if FActionColor = AValue then
    Exit;
  FActionColor := AValue;
  Invalidate;
end;

{ The action takes the header's height and a few pixels either side,
  being short. }
function TGittanSectionHeader.OverAction(X, Y: integer): boolean;
begin
  Result := not FActionRect.IsEmpty and PtInRect(Rect(FActionRect.Left - 4, 0,
    FActionRect.Right + 4, Height), Point(X, Y));
end;

procedure TGittanSectionHeader.SetTitle(const AValue: string);
begin
  if FTitle = AValue then
    Exit;
  FTitle := AValue;
  Invalidate;
end;

procedure TGittanSectionHeader.SetDetail(const AValue: string);
begin
  if FDetail = AValue then
    Exit;
  FDetail := AValue;
  Invalidate;
end;

procedure TGittanSectionHeader.SetExpanded(AValue: boolean);
begin
  if FExpanded = AValue then
    Exit;
  FExpanded := AValue;
  Invalidate;
end;

procedure TGittanSectionHeader.Paint;
var
  X, Y, TextY: integer;
begin
  Canvas.Brush.Style := bsSolid;
  if FHot then
    Canvas.Brush.Color := FHover
  else
    Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := FLine;
  Canvas.Pen.Width := 1;
  Canvas.Line(0, 0, Width, 0);
  { The chevron: to the right while folded, down while unfolded. }
  X := Px(Pad) + Px(ChevronSize);
  Y := Height div 2;
  Canvas.Pen.Color := FDim;
  Canvas.Pen.Width := 2;
  if FExpanded then
  begin
    Canvas.Line(X - Px(ChevronSize), Y - Px(ChevronSize) div 2, X, Y + Px(ChevronSize) div 2);
    Canvas.Line(X, Y + Px(ChevronSize) div 2, X + Px(ChevronSize) + 1, Y - Px(ChevronSize) div 2 - 1);
  end
  else
  begin
    Canvas.Line(X - Px(ChevronSize) div 2, Y - Px(ChevronSize), X + Px(ChevronSize) div 2, Y);
    Canvas.Line(X + Px(ChevronSize) div 2, Y, X - Px(ChevronSize) div 2 - 1, Y + Px(ChevronSize) + 1);
  end;
  Canvas.Pen.Width := 1;
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  TextY := (Height - Canvas.TextHeight('Xg')) div 2;
  X := Px(Pad) + 2 * Px(ChevronSize) + Px(Gap);
  { The title is dim and bold, as the Files heading over the tree. }
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FDim;
  Canvas.TextOut(X, TextY, FTitle);
  Inc(X, Canvas.TextWidth(FTitle) + Px(Gap));
  Canvas.Font.Style := [];
  FCheckRect := Rect(0, 0, 0, 0);
  if (FCheckIndex >= 0) and (FCheckImages <> nil) and
    (FCheckIndex < FCheckImages.Count) then
  begin
    FCheckRect := Bounds(X, (Height - FCheckImages.Height) div 2, FCheckImages.Width,
      FCheckImages.Height);
    FCheckImages.Draw(Canvas, FCheckRect.Left, FCheckRect.Top, FCheckIndex);
    Inc(X, FCheckImages.Width + Px(Gap) div 2);
  end;
  if FDetail <> '' then
    Canvas.TextOut(X, TextY, FDetail);
  { The action at the right end, as a link. }
  FActionRect := Rect(0, 0, 0, 0);
  if FAction <> '' then
  begin
    if FActionEnabled then
      Canvas.Font.Color := FActionColor
    else
      Canvas.Font.Color := FDim;
    if FActionHot and FActionEnabled then
      Canvas.Font.Style := [fsUnderline];
    X := Width - Px(Pad) - Canvas.TextWidth(FAction);
    FActionRect := Bounds(X, TextY, Canvas.TextWidth(FAction), Canvas.TextHeight(FAction));
    Canvas.TextOut(X, TextY, FAction);
    Canvas.Font.Style := [];
  end;
end;

procedure TGittanSectionHeader.MouseEnter;
begin
  inherited MouseEnter;
  FHot := True;
  Invalidate;
end;

procedure TGittanSectionHeader.MouseLeave;
begin
  inherited MouseLeave;
  FHot := False;
  FActionHot := False;
  Invalidate;
end;

{ The action is underlined under the mouse, and the hint is its own
  there and none elsewhere. }
procedure TGittanSectionHeader.MouseMove(Shift: TShiftState; X, Y: integer);
var
  Over: boolean;
begin
  inherited MouseMove(Shift, X, Y);
  Over := OverAction(X, Y);
  if Over = FActionHot then
    Exit;
  FActionHot := Over;
  if Over then
    Hint := FActionHint
  else
    Hint := '';
  Invalidate;
end;

procedure TGittanSectionHeader.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  { The box takes a few pixels around it too, being small. }
  if (Button = mbLeft) and not FCheckRect.IsEmpty and Assigned(FOnCheck) and
    PtInRect(Rect(FCheckRect.Left - 3, 0, FCheckRect.Right + 3, Height), Point(X, Y)) then
  begin
    FOnCheck(Self);
    Exit;
  end;
  if (Button = mbLeft) and OverAction(X, Y) then
  begin
    if FActionEnabled and Assigned(FOnAction) then
      FOnAction(Self);
    Exit;
  end;
  if (Button = mbLeft) and PtInRect(ClientRect, Point(X, Y)) then
  begin
    FExpanded := not FExpanded;
    Invalidate;
    if Assigned(FOnToggle) then
      FOnToggle(Self);
  end;
end;

{ The form scales every control by its DPI after FormCreate, this one's
  height too, which is already the screen's: set it again. }
procedure TGittanSectionHeader.DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
  const AXProportion, AYProportion: double);
begin
  inherited DoAutoAdjustLayout(AMode, AXProportion, AYProportion);
  if AMode = lapAutoAdjustForDPI then
    Height := Px(HeaderHeight);
end;

end.
