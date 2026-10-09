unit gittan.fileheader;

{** The file header: a bar above the editor that names what it shows. On
  the left the badge and path of the file (the directory dimmed, the file
  name in full color), on the right its added and deleted line counts, the
  lexer, and the change navigator for jumping between the changed blocks.

  It paints itself with the editor's palette in both themes, like the
  summary, and owns the navigator as a child so it can lay out around it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, ImgList, gittan.changenav;

type

  { TGittanFileHeader }

  TGittanFileHeader = class(TCustomControl)
  private
    FPrefix, FName, FLexer: string;
    FIcon: integer;
    FAdded, FDeleted: integer;
    FHasCounts, FBinary: boolean;
    FImages: TCustomImageList;
    FNav: TGittanChangeNav;
    FBack, FText, FDim, FAddedColor, FDeletedColor, FLine: TColor;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    {** Shows APath split into its directory and file name, with the badge
      at AIcon in Images (or none when AIcon is -1). The counts are
      cleared. }
    procedure SetFile(const APath: string; AIcon: integer);
    {** Shows ATitle alone, without a badge. The counts are cleared. }
    procedure SetTitle(const ATitle: string);
    {** Shows the added and deleted line counts, or "binary" when ABinary. }
    procedure SetCounts(AAdded, ADeleted: integer; ABinary: boolean);
    {** The lexer name shown on the right. }
    procedure SetLexer(const ALexer: string);
    {** Shows the navigator at ACurrent of ATotal changes, or hides it when
      ATotal is 0. }
    procedure SetChanges(ACurrent, ATotal: integer);
    {** Sets the palette: the background, the text, the dim text for the
      directory and lexer, the added and deleted colors, and the line color
      for the bottom border. }
    procedure SetColors(ABack, AText, ADim, AAdded, ADeleted, ALine: TColor);
    {** The image list the badge comes from. }
    property Images: TCustomImageList read FImages write FImages;
    {** The navigator, for its colors and click handlers. }
    property Nav: TGittanChangeNav read FNav;
  end;

implementation

resourcestring
  rsBinary = 'binary';

const
  HeaderHeight = 36;
  NavHeight = 26;
  Pad = 12;
  Gap = 12;
  IconSize = 16;

{ TGittanFileHeader }

constructor TGittanFileHeader.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Height := HeaderHeight;
  FIcon := -1;
  FNav := TGittanChangeNav.Create(Self);
  FNav.Parent := Self;
  FNav.Height := NavHeight;
  FNav.Anchors := [akRight, akTop];
  FNav.AnchorSideRight.Control := Self;
  FNav.AnchorSideRight.Side := asrRight;
  FNav.AnchorSideTop.Control := Self;
  FNav.AnchorSideTop.Side := asrCenter;
  FNav.BorderSpacing.Right := Pad - 2;
  FNav.Visible := False;
  SetColors(clWindow, clWindowText, clGrayText, clGreen, clRed, clBtnShadow);
end;

procedure TGittanFileHeader.SetFile(const APath: string; AIcon: integer);
begin
  FPrefix := ExtractFilePath(APath);
  FName := ExtractFileName(APath);
  FIcon := AIcon;
  FHasCounts := False;
  Invalidate;
end;

procedure TGittanFileHeader.SetTitle(const ATitle: string);
begin
  FPrefix := '';
  FName := ATitle;
  FIcon := -1;
  FHasCounts := False;
  Invalidate;
end;

procedure TGittanFileHeader.SetCounts(AAdded, ADeleted: integer; ABinary: boolean);
begin
  FAdded := AAdded;
  FDeleted := ADeleted;
  FBinary := ABinary;
  FHasCounts := True;
  Invalidate;
end;

procedure TGittanFileHeader.SetLexer(const ALexer: string);
begin
  if FLexer = ALexer then
    Exit;
  FLexer := ALexer;
  Invalidate;
end;

procedure TGittanFileHeader.SetChanges(ACurrent, ATotal: integer);
begin
  FNav.Visible := ATotal > 0;
  if ATotal > 0 then
    FNav.SetPosition(ACurrent, ATotal);
  { The room for the path depends on the navigator's width. }
  Invalidate;
end;

procedure TGittanFileHeader.SetColors(ABack, AText, ADim, AAdded, ADeleted,
  ALine: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FAddedColor := AAdded;
  FDeletedColor := ADeleted;
  FLine := ALine;
  Color := ABack;
  Invalidate;
end;

{ Right to left: the navigator, the lexer, the counts; then the badge and
  the path from the left in the room that is left. A path too long for it
  loses its directory first, then its end. }
procedure TGittanFileHeader.Paint;
var
  X, Right, TextY, Room: integer;
  Prefix, FileName, S: string;

  procedure DrawRight(const AText: string; AColor: TColor);
  begin
    if AText = '' then
      Exit;
    Canvas.Font.Color := AColor;
    Dec(Right, Canvas.TextWidth(AText));
    Canvas.TextOut(Right, TextY, AText);
    Dec(Right, Gap);
  end;

begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := FLine;
  Canvas.Line(0, Height - 1, Width, Height - 1);

  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  TextY := (Height - 1 - Canvas.TextHeight('Xg')) div 2;
  Right := Width - Pad;
  if FNav.Visible then
    Dec(Right, FNav.Width + Gap);
  DrawRight(FLexer, FDim);
  if FHasCounts then
    if FBinary then
      DrawRight(rsBinary, FDim)
    else
    begin
      if FDeleted > 0 then
        DrawRight('−' + IntToStr(FDeleted), FDeletedColor)
      else
        DrawRight('−0', FDim);
      Right := Right + Gap div 2;
      if FAdded > 0 then
        DrawRight('+' + IntToStr(FAdded), FAddedColor)
      else
        DrawRight('+0', FDim);
    end;

  X := Pad;
  if (FIcon >= 0) and (FImages <> nil) then
  begin
    FImages.DrawForPPI(Canvas, X, (Height - 1 - IconSize) div 2, FIcon,
      IconSize, Font.PixelsPerInch, GetCanvasScaleFactor);
    Inc(X, IconSize + Gap div 2 + 2);
  end;
  Room := Right - X;
  Prefix := FPrefix;
  FileName := FName;
  if Canvas.TextWidth(Prefix + FileName) > Room then
    Prefix := '';
  if Canvas.TextWidth(FileName) > Room then
  begin
    S := FileName;
    while (S <> '') and (Canvas.TextWidth(S + '…') > Room) do
    begin
      S := Copy(S, 1, Length(S) - 1);
      { Keep UTF-8 sequences whole. }
      while (S <> '') and (Ord(S[Length(S)]) and $C0 = $80) do
        S := Copy(S, 1, Length(S) - 1);
    end;
    FileName := S + '…';
  end;
  if Prefix <> '' then
  begin
    Canvas.Font.Color := FDim;
    Canvas.TextOut(X, TextY, Prefix);
    Inc(X, Canvas.TextWidth(Prefix));
  end;
  Canvas.Font.Color := FText;
  Canvas.TextOut(X, TextY, FileName);
end;

end.
