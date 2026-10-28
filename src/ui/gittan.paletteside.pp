unit gittan.paletteside;

{** The buttons beside the command palette: a column of tiles, each an
  icon over a short name, shown to the left and to the right of the
  palette while it is open, for the actions wanted most often without
  typing. A tile is an action of the menus: dimmed while its item is
  disabled, its hint the item's whole caption with its shortcut, and a
  click raises OnClick with the tile's index. Painted in the palette's
  own colors, with a border, as the popup lists are. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Forms;

type
  TGittanPaletteSideClick = procedure(Sender: TObject; AIndex: integer) of object;

  TGittanPaletteTile = record
    Caption, Icon, Hint: string;
    Enabled: boolean;
    Data: TObject;
  end;

  { TGittanPaletteSide }

  TGittanPaletteSide = class(TCustomControl)
  private
    FTiles: array of TGittanPaletteTile;
    FHot, FPressed: integer;
    FBack, FText, FDim, FHover, FLine: TColor;
    FOnClick: TGittanPaletteSideClick;
    function TileRect(AIndex: integer): TRect;
    function TileAt(X, Y: integer): integer;
    procedure SetHot(AValue: integer);
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
    procedure Clear;
    {** Adds a tile: ACaption under the icon of the status bar's marker
      AIcon (gittan.statusbar), AHint when the mouse rests on it, AData
      the caller's. Returns its index. }
    function Add(const ACaption, AIcon, AHint: string; AEnabled: boolean;
      AData: TObject): integer;
    function DataOf(AIndex: integer): TObject;
    function TileEnabled(AIndex: integer): boolean;
    {** The size the tiles need, set as the control's own. }
    procedure Fit;
    procedure SetColors(ABack, AText, ADim, AHover, ALine: TColor);
    property OnClick: TGittanPaletteSideClick read FOnClick write FOnClick;
  end;

implementation

uses
  gittan.statusbar, gittan.theme;

const
  TileWidth = 84;
  TileHeight = 54;
  Pad = 4;
  IconSize = 20;
  Radius = 8;

constructor TGittanPaletteSide.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Visible := False;
  ShowHint := True;
  ParentShowHint := False;
  FHot := -1;
  FPressed := -1;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnShadow);
end;

procedure TGittanPaletteSide.Clear;
begin
  FTiles := nil;
  FHot := -1;
  FPressed := -1;
  Hint := '';
  Invalidate;
end;

function TGittanPaletteSide.Add(const ACaption, AIcon, AHint: string; AEnabled: boolean;
  AData: TObject): integer;
begin
  Result := Length(FTiles);
  SetLength(FTiles, Result + 1);
  FTiles[Result].Caption := ACaption;
  FTiles[Result].Icon := AIcon;
  FTiles[Result].Hint := AHint;
  FTiles[Result].Enabled := AEnabled;
  FTiles[Result].Data := AData;
  Invalidate;
end;

function TGittanPaletteSide.DataOf(AIndex: integer): TObject;
begin
  if (AIndex < 0) or (AIndex > High(FTiles)) then
    Exit(nil);
  Result := FTiles[AIndex].Data;
end;

function TGittanPaletteSide.TileEnabled(AIndex: integer): boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FTiles)) and FTiles[AIndex].Enabled;
end;

procedure TGittanPaletteSide.Fit;
begin
  SetBounds(Left, Top, Px(TileWidth) + 2 * Px(Pad),
    Length(FTiles) * Px(TileHeight) + 2 * Px(Pad));
end;

procedure TGittanPaletteSide.SetColors(ABack, AText, ADim, AHover, ALine: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
  FLine := ALine;
  Color := ABack;
  Invalidate;
end;

function TGittanPaletteSide.TileRect(AIndex: integer): TRect;
begin
  Result := Rect(Px(Pad), Px(Pad) + AIndex * Px(TileHeight), Width - Px(Pad),
    Px(Pad) + (AIndex + 1) * Px(TileHeight));
end;

function TGittanPaletteSide.TileAt(X, Y: integer): integer;
var
  i: integer;
begin
  for i := 0 to High(FTiles) do
    if PtInRect(TileRect(i), Point(X, Y)) then
      Exit(i);
  Result := -1;
end;

procedure TGittanPaletteSide.SetHot(AValue: integer);
begin
  if FHot = AValue then
    Exit;
  FHot := AValue;
  Application.CancelHint;
  if AValue >= 0 then
    Hint := FTiles[AValue].Hint
  else
    Hint := '';
  if TileEnabled(AValue) then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  Invalidate;
end;

{ The border and the tiles: the fill under the mouse on an enabled one,
  the icon centered over the name, both dimmed on a disabled one. }
procedure TGittanPaletteSide.Paint;
var
  i, TextH, IconY, Y: integer;
  R: TRect;
  C: TColor;
  S: string;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.Pen.Color := FLine;
  Canvas.Rectangle(ClientRect);
  Canvas.Font := Font;
  TextH := Canvas.TextHeight('Xg');
  for i := 0 to High(FTiles) do
  begin
    R := TileRect(i);
    if (i = FHot) and FTiles[i].Enabled then
      FillHover(Canvas, R, Px(Radius), FHover);
    if FTiles[i].Enabled then
      C := FText
    else
      C := FDim;
    IconY := R.Top + (R.Height - Px(IconSize) - TextH - Px(Pad)) div 2;
    DrawStatusIcon(Canvas, FTiles[i].Icon, (R.Left + R.Right - Px(IconSize)) div 2 + 2,
      IconY, Px(IconSize), C);
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := C;
    S := FTiles[i].Caption;
    Y := IconY + Px(IconSize) + Px(Pad);
    Canvas.TextOut((R.Left + R.Right - Canvas.TextWidth(S)) div 2, Y, S);
  end;
end;

procedure TGittanPaletteSide.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(TileAt(X, Y));
end;

procedure TGittanPaletteSide.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1);
end;

procedure TGittanPaletteSide.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
    FPressed := TileAt(X, Y);
end;

{ The click fires on release over the tile that was pressed. }
procedure TGittanPaletteSide.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Tile: integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  Tile := FPressed;
  FPressed := -1;
  if (Button = mbLeft) and (Tile >= 0) and (Tile = TileAt(X, Y)) and TileEnabled(Tile) and
    Assigned(FOnClick) then
    FOnClick(Self, Tile);
end;

end.
