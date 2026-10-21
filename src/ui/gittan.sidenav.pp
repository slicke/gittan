unit gittan.sidenav;

{** The rows at the top of the sidebar that open the pages of a
  repository, as a music app lists Home and Explore over the library:
  Home, the summary, Graph, the commit graph, and Repository, the page
  about the repository itself. Each row is an icon and a name; the row
  of the page shown is filled, and the one under the mouse tinted. Set
  Large, the rows are as tall as the music app's, with a larger icon and
  text, so they read as navigation over the list of files and not as
  rows of it; the settings dialog keeps them small. A row added small
  stays at the small size under the large ones, a little apart from
  them, for what opens a dialog or a list rather than a page: Recent,
  Settings. A click raises OnPick with the row's index; whoever owns the sidebar shows the page and
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
  Classes, SysUtils, Types, Math, Controls, Graphics;

type
  {** What a row's icon shows: a house, a trunk of commits with a
    branch for the graph, a book for the repository, a page for the
    heading over the files, a clock for the recent repositories, a
    window of text for the settings' Editor page or sliders for its
    Tools page and for the settings themselves. }
  TGittanNavIcon = (niHome, niGraph, niRepository, niFiles, niClock, niEditor, niTools);

  {** A click on a row, with its index. }
  TGittanNavPickEvent = procedure(Sender: TObject; AIndex: integer) of object;

  { TGittanSideNav }

  TGittanSideNav = class(TCustomControl)
  private
    FCaptions: array of string;
    FIcons: array of TGittanNavIcon;
    FSmall: array of boolean;
    FHeading: string;
    FLarge: boolean;
    FRowHeight, FIconSize, FIconGap: integer;
    FSelected, FHot: integer;
    FBack, FText, FDim, FHover, FSelectedBack, FLine: TColor;
    FOnPick: TGittanNavPickEvent;
    procedure SetHeading(const AValue: string);
    procedure SetLarge(AValue: boolean);
    procedure FitHeight;
    function RowAt(Y: integer): integer;
    function RowTop(AIndex: integer): integer;
    function RowHeightOf(AIndex: integer): integer;
    function RowsHeight: integer;
    function RowRect(AIndex: integer): TRect;
    procedure SetSelected(AValue: integer);
    procedure SetHot(AValue: integer);
    procedure DrawIcon(AIcon: TGittanNavIcon; X, Y, ASize: integer; AColor: TColor;
      AWidth: integer = 1);
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    constructor Create(AOwner: TComponent); override;
    {** Adds a row at the end and gives its index; ASmall keeps it at
      the small size under the large rows. }
    function AddRow(const ACaption: string; AIcon: TGittanNavIcon;
      ASmall: boolean = False): integer;
    {** A row's rectangle in screen coordinates, for a list to drop
      from. }
    function RowScreenRect(AIndex: integer): TRect;
    {** The palette: the background, the text, the dim icons and
      heading, the tint under the mouse, the fill of the selected row
      and the line under the heading. }
    procedure SetColors(ABack, AText, ADim, AHover, ASelected, ALine: TColor);
    {** The title under the rows, over what the sidebar lists below
      them; none when empty. }
    property Heading: string read FHeading write SetHeading;
    {** Taller rows with a larger icon and text, as the main window's
      sidebar has them; off, the rows are as high as the section
      headers. }
    property Large: boolean read FLarge write SetLarge;
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
  { The rows when Large: as tall as a music app's, the icon and the
    text larger to match. }
  LargeRowHeight = 36;
  LargeIconSize = 18;
  LargeIconGap = 10;
  LargeFontSize = 15;
  LargePenWidth = 2;
  { The small rows stand this far under the large ones. }
  SmallGap = 4;
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
  FRowHeight := RowHeight;
  FIconSize := IconSize;
  FIconGap := IconGap;
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
  H := 2 * PadY + RowsHeight;
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

procedure TGittanSideNav.SetLarge(AValue: boolean);
begin
  if FLarge = AValue then
    Exit;
  FLarge := AValue;
  if AValue then
  begin
    FRowHeight := LargeRowHeight;
    FIconSize := LargeIconSize;
    FIconGap := LargeIconGap;
  end
  else
  begin
    FRowHeight := RowHeight;
    FIconSize := IconSize;
    FIconGap := IconGap;
  end;
  FitHeight;
  Invalidate;
end;

procedure TGittanSideNav.SetHeading(const AValue: string);
begin
  if FHeading = AValue then
    Exit;
  FHeading := AValue;
  FitHeight;
  Invalidate;
end;

function TGittanSideNav.AddRow(const ACaption: string; AIcon: TGittanNavIcon;
  ASmall: boolean): integer;
begin
  Result := Length(FCaptions);
  SetLength(FCaptions, Result + 1);
  SetLength(FIcons, Result + 1);
  SetLength(FSmall, Result + 1);
  FCaptions[Result] := ACaption;
  FIcons[Result] := AIcon;
  FSmall[Result] := ASmall;
  FitHeight;
  Invalidate;
end;

function TGittanSideNav.RowScreenRect(AIndex: integer): TRect;
begin
  Result := RowRect(AIndex);
  Result.TopLeft := ClientToScreen(Result.TopLeft);
  Result.BottomRight := ClientToScreen(Result.BottomRight);
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

function TGittanSideNav.RowHeightOf(AIndex: integer): integer;
begin
  if FSmall[AIndex] then
    Result := RowHeight
  else
    Result := FRowHeight;
end;

{ The first small row stands SmallGap under the large ones. }
function TGittanSideNav.RowTop(AIndex: integer): integer;
var
  i: integer;
begin
  Result := PadY;
  for i := 0 to AIndex - 1 do
    Inc(Result, RowHeightOf(i));
  if FSmall[AIndex] and ((AIndex = 0) or not FSmall[AIndex - 1]) then
    Inc(Result, SmallGap);
end;

function TGittanSideNav.RowsHeight: integer;
begin
  if Length(FCaptions) = 0 then
    Result := 0
  else
    Result := RowTop(High(FCaptions)) + RowHeightOf(High(FCaptions)) - PadY;
end;

function TGittanSideNav.RowAt(Y: integer): integer;
var
  i: integer;
begin
  Result := -1;
  for i := 0 to High(FCaptions) do
    if (Y >= RowTop(i)) and (Y < RowTop(i) + RowHeightOf(i)) then
      Exit(i);
end;

function TGittanSideNav.RowRect(AIndex: integer): TRect;
begin
  Result := Rect(PadX, RowTop(AIndex), Width - PadX, RowTop(AIndex) + RowHeightOf(AIndex));
end;

{ The icons are drawn with lines in AColor, in a square ASize wide with
  its top left at X, Y: a house, its roof over a body with a door, a
  trunk of two commits with a branch leaving the lower one for a third,
  a closed book, its cover with the spine along the left, and a page
  with its top right corner folded. Their parts are set out in shares
  of ASize, since the sidebar draws them Large and the settings small,
  and the lines are AWidth wide: two for the large rows, whose text
  would outweigh a one-pixel line. }
procedure TGittanSideNav.DrawIcon(AIcon: TGittanNavIcon; X, Y, ASize: integer;
  AColor: TColor; AWidth: integer);
var
  Mid, Eave: integer;
begin
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := AColor;
  Canvas.Pen.Width := AWidth;
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
      Canvas.Rectangle(Mid - ASize div 7, Y + ASize - ASize * 5 div 14, Mid + ASize div 7,
        Y + ASize);
    end;
    niGraph:
    begin
      Mid := X + ASize div 3;  { the trunk }
      Eave := Max(2, ASize div 6);  { a commit's radius }
      Canvas.Line(Mid, Y + Eave, Mid, Y + ASize - Eave);
      Canvas.Line(Mid, Y + ASize - Eave, X + ASize - Eave - 1, Y + ASize * 2 div 5);
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := AColor;
      Canvas.Ellipse(Mid - Eave, Y, Mid + Eave + 1, Y + 2 * Eave + 1);
      Canvas.Ellipse(Mid - Eave, Y + ASize - 2 * Eave, Mid + Eave + 1, Y + ASize + 1);
      Canvas.Ellipse(X + ASize - 2 * Eave - 1, Y + ASize * 2 div 5 - Eave, X + ASize,
        Y + ASize * 2 div 5 + Eave + 1);
      Canvas.Brush.Style := bsClear;
    end;
    niRepository:
    begin
      Canvas.RoundRect(X + 1, Y, X + ASize, Y + ASize + 1, 3, 3);
      Mid := X + 1 + (ASize * 3 + 7) div 14;  { the spine }
      Canvas.Line(Mid, Y + 1, Mid, Y + ASize);
      Canvas.Line(X + ASize div 2, Y + ASize * 2 div 7, X + ASize - 2, Y + ASize * 2 div 7);
      Canvas.Line(X + ASize div 2, Y + ASize div 2, X + ASize - 2, Y + ASize div 2);
    end;
    niFiles:
    begin
      Mid := X + 1;  { the left edge; the page is two narrower than high }
      Eave := Mid + ASize - 2;  { the right edge }
      Canvas.Polyline([Point(Mid, Y), Point(Eave - 4, Y), Point(Eave, Y + 4),
        Point(Eave, Y + ASize), Point(Mid, Y + ASize), Point(Mid, Y)]);
      Canvas.Polyline([Point(Eave - 4, Y), Point(Eave - 4, Y + 4), Point(Eave, Y + 4)]);
    end;
    niClock:
    begin
      { A dial with the hands at ten past ten. }
      Canvas.Ellipse(X, Y, X + ASize + 1, Y + ASize + 1);
      Mid := X + ASize div 2;
      Eave := Y + ASize div 2;
      Canvas.Line(Mid, Eave, Mid, Y + 3);
      Canvas.Line(Mid, Eave, Mid + ASize div 4, Eave);
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
  i, TextH, TextY, Y, Icon, Gap, PenW: integer;
  R: TRect;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  Canvas.Font := Font;
  TextH := Canvas.TextHeight('Xg');
  if FHeading <> '' then
  begin
    Y := 2 * PadY + RowsHeight + HeadingTop;
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
    if FSmall[i] then
    begin
      Canvas.Font := Font;
      Icon := IconSize;
      Gap := IconGap;
    end
    else
    begin
      if FLarge then
        Canvas.Font.Size := LargeFontSize;
      Icon := FIconSize;
      Gap := FIconGap;
    end;
    TextH := Canvas.TextHeight('Xg');
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
    TextY := R.Top + (R.Height - TextH) div 2;
    if FSmall[i] or not FLarge then
      PenW := 1
    else
      PenW := LargePenWidth;
    if i = FSelected then
      DrawIcon(FIcons[i], R.Left + PadX, R.Top + (R.Height - Icon) div 2, Icon, FText, PenW)
    else
      DrawIcon(FIcons[i], R.Left + PadX, R.Top + (R.Height - Icon) div 2, Icon, FDim, PenW);
    Canvas.Pen.Width := 1;
    Canvas.Font.Color := FText;
    if i = FSelected then
      Canvas.Font.Style := [fsBold]
    else
      Canvas.Font.Style := [];
    Canvas.TextOut(R.Left + PadX + Icon + Gap, TextY, FCaptions[i]);
  end;
  Canvas.Font := Font;
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
