unit gittan.sidenav;

{** The rows at the top of the sidebar that open the pages of a
  repository, as a music app lists Home and Explore over the library:
  Home, the summary, and Repository, the page about the repository
  itself. Each row is an icon and a name; the row of the page shown is
  filled, and the one under the mouse tinted. A click raises OnPick
  with the row's index; whoever owns the sidebar shows the page and
  sets Selected, so the rows follow the view and never lead it. Under
  the rows a Heading names what the sidebar lists below them, as the
  music app writes Library over its playlists: a dim bold title with a
  page icon, set in as the section headers under the tree set their
  chevron and title, over a line, as the headings of the repository
  page.

  It paints itself in the sidebar's shade, as the section headers do,
  and is as high as its rows and the heading. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics;

type
  {** What a row's icon shows: a house, a book for the repository, a
    page for the heading over the files, a window of text for the
    settings' Editor page or sliders for its Tools page. }
  TGittanNavIcon = (niHome, niRepository, niFiles, niEditor, niTools);

  {** A click on a row, with its index. }
  TGittanNavPickEvent = procedure(Sender: TObject; AIndex: integer) of object;

  { TGittanSideNav }

  TGittanSideNav = class(TCustomControl)
  private
    FCaptions: array of string;
    FIcons: array of TGittanNavIcon;
    FHeading: string;
    FSelected, FHot: integer;
    FBack, FText, FDim, FHover, FSelectedBack, FLine: TColor;
    FOnPick: TGittanNavPickEvent;
    procedure SetHeading(const AValue: string);
    procedure FitHeight;
    function RowAt(Y: integer): integer;
    function RowRect(AIndex: integer): TRect;
    procedure SetSelected(AValue: integer);
    procedure SetHot(AValue: integer);
    procedure DrawIcon(AIcon: TGittanNavIcon; X, Y, ASize: integer; AColor: TColor);
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    constructor Create(AOwner: TComponent); override;
    {** Adds a row at the end and gives its index. }
    function AddRow(const ACaption: string; AIcon: TGittanNavIcon): integer;
    {** The palette: the background, the text, the dim icons and
      heading, the tint under the mouse, the fill of the selected row
      and the line under the heading. }
    procedure SetColors(ABack, AText, ADim, AHover, ASelected, ALine: TColor);
    {** The title under the rows, over what the sidebar lists below
      them; none when empty. }
    property Heading: string read FHeading write SetHeading;
    {** The row of the page shown, -1 for none. }
    property Selected: integer read FSelected write SetSelected;
    {** A click on a row. }
    property OnPick: TGittanNavPickEvent read FOnPick write FOnPick;
  end;

{** The sidebar's shade, light or dark: the gutter's, which the tree
  panel, the section headers and the rows take. }
function SidebarShade(ADark: boolean): TColor;

{** Colors ANav as the main window's sidebar, on SidebarShade; AText is
  the text color of a row in dark mode (the editor's), since the light
  one is fixed. }
procedure ThemeSideNav(ANav: TGittanSideNav; ADark: boolean; AText: TColor);

implementation

const
  RowHeight = 26;
  PadX = 8;
  PadY = 6;
  IconSize = 14;
  IconGap = 7;
  Radius = 8;
  { The heading: its text sits HeadingTop under the rows, and the line
    HeadingGap under the text, with HeadingBottom below it. }
  HeadingTop = 10;
  HeadingGap = 5;
  HeadingBottom = 4;
  HeadingIconSize = 12;
  { The icon and the text stand where the section headers under the
    tree (gittan.sectionheader) have their chevron and their title, so
    Files, Repository and Commit line up. }
  HeadingLeft = 10;
  HeadingTextLeft = 26;

function SidebarShade(ADark: boolean): TColor;
begin
  if ADark then
    Result := RGBToColor(37, 37, 38)
  else
    Result := RGBToColor(246, 246, 246);
end;

procedure ThemeSideNav(ANav: TGittanSideNav; ADark: boolean; AText: TColor);
begin
  if ADark then
    ANav.SetColors(SidebarShade(True), AText, RGBToColor(150, 150, 150),
      RGBToColor(50, 50, 51), RGBToColor(62, 62, 64), RGBToColor(62, 62, 62))
  else
    ANav.SetColors(SidebarShade(False), RGBToColor(30, 30, 30), RGBToColor(110, 110, 110),
      RGBToColor(235, 235, 235), RGBToColor(222, 222, 224), RGBToColor(222, 222, 222));
end;

{ TGittanSideNav }

constructor TGittanSideNav.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FSelected := -1;
  FHot := -1;
  Height := 2 * PadY;
  SetColors(clBtnFace, clWindowText, clGrayText, clBtnShadow, clHighlight,
    clBtnShadow);
end;

{ The heading is measured on a bitmap, since the rows and the heading
  are set before the control has a parent and so a canvas. }
procedure TGittanSideNav.FitHeight;
var
  H: integer;
  Bmp: TBitmap;
begin
  H := 2 * PadY + Length(FCaptions) * RowHeight;
  if FHeading <> '' then
  begin
    Bmp := TBitmap.Create;
    try
      Bmp.Canvas.Font := Font;
      Inc(H, HeadingTop + Bmp.Canvas.TextHeight('Xg') + HeadingGap + 1 + HeadingBottom);
    finally
      Bmp.Free;
    end;
  end;
  Height := H;
end;

procedure TGittanSideNav.SetHeading(const AValue: string);
begin
  if FHeading = AValue then
    Exit;
  FHeading := AValue;
  FitHeight;
  Invalidate;
end;

function TGittanSideNav.AddRow(const ACaption: string; AIcon: TGittanNavIcon): integer;
begin
  Result := Length(FCaptions);
  SetLength(FCaptions, Result + 1);
  SetLength(FIcons, Result + 1);
  FCaptions[Result] := ACaption;
  FIcons[Result] := AIcon;
  FitHeight;
  Invalidate;
end;

procedure TGittanSideNav.SetColors(ABack, AText, ADim, AHover, ASelected,
  ALine: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
  FSelectedBack := ASelected;
  FLine := ALine;
  Color := ABack;
  Invalidate;
end;

procedure TGittanSideNav.SetSelected(AValue: integer);
begin
  if (AValue < 0) or (AValue >= Length(FCaptions)) then
    AValue := -1;
  if FSelected = AValue then
    Exit;
  FSelected := AValue;
  Invalidate;
end;

procedure TGittanSideNav.SetHot(AValue: integer);
begin
  if FHot = AValue then
    Exit;
  FHot := AValue;
  if AValue < 0 then
    Cursor := crDefault
  else
    Cursor := crHandPoint;
  Invalidate;
end;

function TGittanSideNav.RowAt(Y: integer): integer;
begin
  Result := (Y - PadY) div RowHeight;
  if (Y < PadY) or (Result < 0) or (Result >= Length(FCaptions)) then
    Result := -1;
end;

function TGittanSideNav.RowRect(AIndex: integer): TRect;
begin
  Result := Rect(PadX, PadY + AIndex * RowHeight, Width - PadX,
    PadY + (AIndex + 1) * RowHeight);
end;

{ The icons are drawn with lines in AColor, in a square ASize wide with
  its top left at X, Y: a house, its roof over a body with a door, a
  closed book, its cover with the spine along the left, and a page with
  its top right corner folded. }
procedure TGittanSideNav.DrawIcon(AIcon: TGittanNavIcon; X, Y, ASize: integer;
  AColor: TColor);
var
  Mid, Eave: integer;
begin
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := AColor;
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  case AIcon of
    niHome:
    begin
      Mid := X + ASize div 2;
      Eave := Y + ASize * 2 div 5;
      Canvas.Polyline([Point(X, Eave + 1), Point(Mid, Y), Point(X + ASize, Eave + 1)]);
      { The body, open at the top where the roof covers it. }
      Canvas.Polyline([Point(X + 2, Eave), Point(X + 2, Y + ASize),
        Point(X + ASize - 2, Y + ASize), Point(X + ASize - 2, Eave)]);
      { The door. }
      Canvas.Rectangle(Mid - 2, Y + ASize - 5, Mid + 2, Y + ASize);
    end;
    niRepository:
    begin
      Canvas.RoundRect(X + 1, Y, X + ASize, Y + ASize + 1, 3, 3);
      Canvas.Line(X + 4, Y + 1, X + 4, Y + ASize);
      Canvas.Line(X + 7, Y + 4, X + ASize - 2, Y + 4);
      Canvas.Line(X + 7, Y + 7, X + ASize - 2, Y + 7);
    end;
    niFiles:
    begin
      Mid := X + 1;  { the left edge; the page is two narrower than high }
      Eave := Mid + ASize - 2;  { the right edge }
      Canvas.Polyline([Point(Mid, Y), Point(Eave - 4, Y), Point(Eave, Y + 4),
        Point(Eave, Y + ASize), Point(Mid, Y + ASize), Point(Mid, Y)]);
      Canvas.Polyline([Point(Eave - 4, Y), Point(Eave - 4, Y + 4), Point(Eave, Y + 4)]);
    end;
    niEditor:
    begin
      { A window with three lines of text, the last one short. }
      Canvas.RoundRect(X, Y, X + ASize + 1, Y + ASize + 1, 3, 3);
      Canvas.Line(X + 3, Y + 4, X + ASize - 2, Y + 4);
      Canvas.Line(X + 3, Y + 7, X + ASize - 2, Y + 7);
      Canvas.Line(X + 3, Y + 10, X + ASize div 2 + 1, Y + 10);
    end;
    niTools:
    begin
      { Two sliders, their knobs at different places. }
      Mid := Y + ASize div 3;
      Eave := Y + ASize * 2 div 3 + 1;
      Canvas.Line(X, Mid, X + ASize + 1, Mid);
      Canvas.Line(X, Eave, X + ASize + 1, Eave);
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := AColor;
      Canvas.Ellipse(X + ASize - 5, Mid - 2, X + ASize, Mid + 3);
      Canvas.Ellipse(X + 2, Eave - 2, X + 7, Eave + 3);
      Canvas.Brush.Style := bsClear;
    end;
  end;
end;

procedure TGittanSideNav.Paint;
var
  i, TextH, TextY, Y: integer;
  R: TRect;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  Canvas.Font := Font;
  TextH := Canvas.TextHeight('Xg');
  if FHeading <> '' then
  begin
    Y := 2 * PadY + Length(FCaptions) * RowHeight + HeadingTop;
    { The page is drawn one in from X. }
    DrawIcon(niFiles, HeadingLeft - 1, Y + (TextH - HeadingIconSize) div 2,
      HeadingIconSize, FDim);
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := FDim;
    Canvas.TextOut(HeadingTextLeft, Y, FHeading);
    Canvas.Font.Style := [];
    Inc(Y, TextH + HeadingGap);
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Color := FLine;
    Canvas.Line(HeadingLeft, Y, Width - HeadingLeft, Y);
  end;
  for i := 0 to High(FCaptions) do
  begin
    R := RowRect(i);
    if (i = FSelected) or (i = FHot) then
    begin
      Canvas.Pen.Style := psClear;
      Canvas.Brush.Style := bsSolid;
      if i = FSelected then
        Canvas.Brush.Color := FSelectedBack
      else
        Canvas.Brush.Color := FHover;
      Canvas.RoundRect(R, Radius, Radius);
      Canvas.Pen.Style := psSolid;
    end;
    Canvas.Brush.Style := bsClear;
    TextY := R.Top + (RowHeight - TextH) div 2;
    if i = FSelected then
      DrawIcon(FIcons[i], R.Left + PadX, R.Top + (RowHeight - IconSize) div 2, IconSize, FText)
    else
      DrawIcon(FIcons[i], R.Left + PadX, R.Top + (RowHeight - IconSize) div 2, IconSize, FDim);
    Canvas.Font.Color := FText;
    if i = FSelected then
      Canvas.Font.Style := [fsBold]
    else
      Canvas.Font.Style := [];
    Canvas.TextOut(R.Left + PadX + IconSize + IconGap, TextY, FCaptions[i]);
  end;
  Canvas.Font.Style := [];
end;

procedure TGittanSideNav.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  if (X < PadX) or (X >= Width - PadX) then
    SetHot(-1)
  else
    SetHot(RowAt(Y));
end;

procedure TGittanSideNav.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1);
end;

procedure TGittanSideNav.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  Row: integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  Row := RowAt(Y);
  if (Row >= 0) and (X >= PadX) and (X < Width - PadX) and Assigned(FOnPick) then
    FOnPick(Self, Row);
end;

end.
