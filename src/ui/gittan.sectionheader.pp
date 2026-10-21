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
  OnCheck instead: the Commit section ticks every file with it. }

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
    procedure SetCheckIndex(AValue: integer);
    procedure SetTitle(const AValue: string);
    procedure SetDetail(const AValue: string);
    procedure SetExpanded(AValue: boolean);
  protected
    procedure Paint; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
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
  end;

implementation

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
  Height := HeaderHeight;
  Cursor := crHandPoint;
  FCheckIndex := -1;
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
  X := Pad + ChevronSize;
  Y := Height div 2;
  Canvas.Pen.Color := FDim;
  Canvas.Pen.Width := 2;
  if FExpanded then
  begin
    Canvas.Line(X - ChevronSize, Y - ChevronSize div 2, X, Y + ChevronSize div 2);
    Canvas.Line(X, Y + ChevronSize div 2, X + ChevronSize + 1, Y - ChevronSize div 2 - 1);
  end
  else
  begin
    Canvas.Line(X - ChevronSize div 2, Y - ChevronSize, X + ChevronSize div 2, Y);
    Canvas.Line(X + ChevronSize div 2, Y, X - ChevronSize div 2 - 1, Y + ChevronSize + 1);
  end;
  Canvas.Pen.Width := 1;
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  TextY := (Height - Canvas.TextHeight('Xg')) div 2;
  X := Pad + 2 * ChevronSize + Gap;
  { The title is dim and bold, as the Files heading over the tree. }
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FDim;
  Canvas.TextOut(X, TextY, FTitle);
  Inc(X, Canvas.TextWidth(FTitle) + Gap);
  Canvas.Font.Style := [];
  FCheckRect := Rect(0, 0, 0, 0);
  if (FCheckIndex >= 0) and (FCheckImages <> nil) and
    (FCheckIndex < FCheckImages.Count) then
  begin
    FCheckRect := Bounds(X, (Height - FCheckImages.Height) div 2, FCheckImages.Width,
      FCheckImages.Height);
    FCheckImages.Draw(Canvas, FCheckRect.Left, FCheckRect.Top, FCheckIndex);
    Inc(X, FCheckImages.Width + Gap div 2);
  end;
  if FDetail <> '' then
    Canvas.TextOut(X, TextY, FDetail);
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
  if (Button = mbLeft) and PtInRect(ClientRect, Point(X, Y)) then
  begin
    FExpanded := not FExpanded;
    Invalidate;
    if Assigned(FOnToggle) then
      FOnToggle(Self);
  end;
end;

end.
