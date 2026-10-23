unit gittan.sidenav;

{** The rows at the top of the sidebar that open the pages of a
  repository, as a music app lists Home and Explore over the library:
  Home, the summary, Graph, the commit graph, Repository, the page
  about the repository itself, Commands, Files and Pull Requests, the
  last hidden (SetRowVisible) while gh is missing. Each row is an icon and a name; the row
  of the page shown is filled, and the one under the mouse tinted. Set
  Large, the rows are as tall as the music app's, with a larger icon and
  text, so they read as navigation over the list of files and not as
  rows of it; the settings dialog keeps them small. A row added small
  stays at the small size under the large ones, a little apart from
  them: the main window makes Home alone large, so that the tree under
  the rows keeps its room, and the other pages and Recent small. A click raises OnPick with the row's index; whoever owns the sidebar shows the page and
  sets Selected, so the rows follow the view and never lead it. Under
  the rows a Heading names what the sidebar lists below them, as the
  music app writes Library over its playlists: a dim bold title with a
  page icon, set in as the section headers under the tree set their
  chevron and title, over a line, as the headings of the repository
  page.

  With ShowToggle, the first row holds a button at its right end that
  folds the other rows and the heading away, as a music app's sidebar
  folds at the button beside its name: a window with its sidebar and an
  arrow into it, which points out again while they are folded, when
  the first row alone is left over the heading and whatever the sidebar
  lists. Collapsed tells the state and OnCollapse reports a change of
  it.

  It paints itself in the sidebar's shade, as the section headers do,
  and is as high as its rows and the heading, or as the first row while
  folded. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics;

type
  {** What a row's icon shows: a house, a trunk of commits with a
    branch for the graph, a book for the repository, a terminal with
    its prompt for the commands, a page for the files, a pull request
    (a branch's commits meeting the trunk) for the pull requests, a
    clock for the recent repositories, a window of text for the
    settings' Editor page or sliders for its Tools page and for the
    settings themselves. }
  TGittanNavIcon = (niHome, niGraph, niRepository, niCommands, niFiles, niPull, niClock,
    niEditor, niTools);

  {** A click on a row, with its index. }
  TGittanNavPickEvent = procedure(Sender: TObject; AIndex: integer) of object;

  { TGittanSideNav }

  TGittanSideNav = class(TCustomControl)
  private
    FCaptions: array of string;
    FIcons: array of TGittanNavIcon;
    FSmall: array of boolean;
    FHidden: array of boolean;
    FHeading: string;
    FLarge: boolean;
    FRowHeight, FIconSize, FIconGap: integer;
    FSelected, FHot: integer;
    FToggle, FCollapsed, FHotToggle: boolean;
    FCollapseHint, FExpandHint: string;
    FBack, FText, FDim, FHover, FSelectedBack, FLine: TColor;
    FOnPick: TGittanNavPickEvent;
    FOnCollapse: TNotifyEvent;
    procedure SetHeading(const AValue: string);
    procedure SetLarge(AValue: boolean);
    procedure SetCollapsed(AValue: boolean);
    procedure SetHotToggle(AValue: boolean);
    procedure UpdateCursor;
    function ToggleRect: TRect;
    procedure DrawToggle(const R: TRect; AColor: TColor);
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
    procedure DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
      const AXProportion, AYProportion: double); override;
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    {** Adds a row at the end and gives its index; ASmall keeps it at
      the small size under the large rows. }
    function AddRow(const ACaption: string; AIcon: TGittanNavIcon;
      ASmall: boolean = False): integer;
    {** A row's rectangle in screen coordinates, for a list to drop
      from. }
    function RowScreenRect(AIndex: integer): TRect;
    {** Hides a row (its place closes up) or shows it again, for a row
      whose page needs a tool that may be missing. }
    procedure SetRowVisible(AIndex: integer; AVisible: boolean);
    {** The palette: the background, the text, the dim icons and
      heading, the tint under the mouse, the fill of the selected row
      and the line under the heading. }
    procedure SetColors(ABack, AText, ADim, AHover, ASelected, ALine: TColor);
    {** Shows, at the right end of the first row, the button that folds
      the other rows away, with its hint while they show and while they
      are folded. }
    procedure ShowToggle(const ACollapseHint, AExpandHint: string);
    {** Whether the rows after the first are folded away, the first row
      alone left over the heading. }
    property Collapsed: boolean read FCollapsed write SetCollapsed;
    {** A change of Collapsed, by the button or by the owner. }
    property OnCollapse: TNotifyEvent read FOnCollapse write FOnCollapse;
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

uses
  gittan.textfit, gittan.theme;

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
  { The folding button at the right end of the first row: its box,
    tinted under the mouse, holds an icon ToggleIconWidth by
    ToggleIconHeight, a window wider than high. Its right edge stands
    where the rows' icons stand from the left, mirrored. }
  ToggleBox = 20;
  ToggleIconWidth = 16;
  ToggleIconHeight = 12;
  ToggleRadius = 5;
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
  FRowHeight := Px(RowHeight);
  FIconSize := Px(IconSize);
  FIconGap := Px(IconGap);
  Height := 2 * Px(PadY);
  SetColors(clBtnFace, clWindowText, clGrayText, clBtnShadow, clHighlight,
    clBtnShadow);
end;

{ The heading is measured on a bitmap, since the rows and the heading
  are set before the control has a parent and so a canvas. Folded, the
  first row is left. }
procedure TGittanSideNav.FitHeight;
var
  H: integer;
begin
  H := 2 * Px(PadY) + RowsHeight;
  if FHeading <> '' then
    Inc(H, Px(HeadingTop) + MeasureCanvas(Font).TextHeight('Xg') + Px(HeadingGap) + 1 + Px(HeadingBottom));
  Height := H;
end;

procedure TGittanSideNav.SetLarge(AValue: boolean);
begin
  if FLarge = AValue then
    Exit;
  FLarge := AValue;
  if AValue then
  begin
    FRowHeight := Px(LargeRowHeight);
    FIconSize := Px(LargeIconSize);
    FIconGap := Px(LargeIconGap);
  end
  else
  begin
    FRowHeight := Px(RowHeight);
    FIconSize := Px(IconSize);
    FIconGap := Px(IconGap);
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

procedure TGittanSideNav.ShowToggle(const ACollapseHint, AExpandHint: string);
begin
  FToggle := True;
  FCollapseHint := ACollapseHint;
  FExpandHint := AExpandHint;
  ShowHint := True;
  FitHeight;
  Invalidate;
end;

procedure TGittanSideNav.SetCollapsed(AValue: boolean);
begin
  if FCollapsed = AValue then
    Exit;
  FCollapsed := AValue;
  { A row under the mouse is gone with the rows. }
  FHot := -1;
  if FHotToggle then
  begin
    if FCollapsed then
      Hint := FExpandHint
    else
      Hint := FCollapseHint;
  end;
  FitHeight;
  Invalidate;
  if Assigned(FOnCollapse) then
    FOnCollapse(Self);
end;

function TGittanSideNav.ToggleRect: TRect;
var
  Row: TRect;
  R, T: integer;
begin
  if not FToggle or (Length(FCaptions) = 0) then
    Exit(Rect(0, 0, 0, 0));
  Row := RowRect(0);
  R := Row.Right - Px(PadX) + (Px(ToggleBox) - Px(ToggleIconWidth)) div 2;
  T := Row.Top + (Row.Height - Px(ToggleBox)) div 2;
  Result := Rect(R - Px(ToggleBox), T, R, T + Px(ToggleBox));
end;

procedure TGittanSideNav.SetHotToggle(AValue: boolean);
begin
  if FHotToggle = AValue then
    Exit;
  FHotToggle := AValue;
  if not AValue then
    Hint := ''
  else if FCollapsed then
    Hint := FExpandHint
  else
    Hint := FCollapseHint;
  UpdateCursor;
  Invalidate;
end;

procedure TGittanSideNav.UpdateCursor;
begin
  if (FHot >= 0) or FHotToggle then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
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
  SetLength(FHidden, Result + 1);
  FHidden[Result] := False;
  FitHeight;
  Invalidate;
end;

procedure TGittanSideNav.SetRowVisible(AIndex: integer; AVisible: boolean);
begin
  if (AIndex < 0) or (AIndex > High(FHidden)) or (FHidden[AIndex] = not AVisible) then
    Exit;
  FHidden[AIndex] := not AVisible;
  if FHot = AIndex then
    FHot := -1;
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
  UpdateCursor;
  Invalidate;
end;

{ A hidden row takes no height. }
function TGittanSideNav.RowHeightOf(AIndex: integer): integer;
begin
  if FHidden[AIndex] then
    Result := 0
  else if FSmall[AIndex] then
    Result := Px(RowHeight)
  else
    Result := FRowHeight;
end;

{ The first small row stands SmallGap under the large ones, and the rows
  after it with it; a hidden row is skipped. }
function TGittanSideNav.RowTop(AIndex: integer): integer;
var
  i, Prev: integer;
begin
  Result := Px(PadY);
  Prev := -1;
  for i := 0 to AIndex do
  begin
    if FHidden[i] then
      Continue;
    if FSmall[i] and ((Prev < 0) or not FSmall[Prev]) then
      Inc(Result, Px(SmallGap));
    if i < AIndex then
      Inc(Result, RowHeightOf(i));
    Prev := i;
  end;
end;

{ Folded, the first row alone. }
function TGittanSideNav.RowsHeight: integer;
var
  Last: integer;
begin
  if Length(FCaptions) = 0 then
    Exit(0);
  if FCollapsed then
    Last := 0
  else
  begin
    Last := High(FCaptions);
    while (Last > 0) and FHidden[Last] do
      Dec(Last);
  end;
  Result := RowTop(Last) + RowHeightOf(Last) - Px(PadY);
end;

function TGittanSideNav.RowAt(Y: integer): integer;
var
  i: integer;
begin
  Result := -1;
  for i := 0 to High(FCaptions) do
  begin
    if not FHidden[i] and (Y >= RowTop(i)) and (Y < RowTop(i) + RowHeightOf(i)) then
      Exit(i);
    if FCollapsed then
      Exit;
  end;
end;

function TGittanSideNav.RowRect(AIndex: integer): TRect;
begin
  Result := Rect(Px(PadX), RowTop(AIndex), Width - Px(PadX), RowTop(AIndex) + RowHeightOf(AIndex));
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
    niCommands:
    begin
      { A terminal: a window with a prompt's chevron and a cursor line. }
      Canvas.RoundRect(X, Y, X + ASize + 1, Y + ASize + 1, 3, 3);
      Mid := X + ASize * 2 div 7;
      Eave := Y + ASize div 2;
      Canvas.Polyline([Point(Mid, Eave - ASize div 5), Point(Mid + ASize div 5, Eave),
        Point(Mid, Eave + ASize div 5)]);
      Canvas.Line(X + ASize div 2, Y + ASize * 5 div 7, X + ASize - 3, Y + ASize * 5 div 7);
    end;
    niPull:
    begin
      { A pull request: the trunk's two commits down the left, and a
        branch's commit at the right whose line comes in to the top. }
      Eave := Max(2, ASize div 6);  { a commit's radius }
      Mid := X + Eave;  { the trunk }
      Canvas.Line(Mid, Y + 2 * Eave, Mid, Y + ASize - 2 * Eave);
      Canvas.Polyline([Point(X + ASize - Eave - 1, Y + ASize - 2 * Eave),
        Point(X + ASize - Eave - 1, Y + ASize div 2), Point(X + ASize div 2, Y + Eave),
        Point(Mid + 2 * Eave, Y + Eave)]);
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := AColor;
      Canvas.Ellipse(Mid - Eave, Y, Mid + Eave + 1, Y + 2 * Eave + 1);
      Canvas.Ellipse(Mid - Eave, Y + ASize - 2 * Eave, Mid + Eave + 1, Y + ASize + 1);
      Canvas.Ellipse(X + ASize - 2 * Eave - 1, Y + ASize - 2 * Eave, X + ASize,
        Y + ASize + 1);
      Canvas.Brush.Style := bsClear;
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

{ The folding button: a window with its sidebar along the left and an
  arrow in the rest, pointing into the sidebar while the rows show, out
  of it while they are folded. }
procedure TGittanSideNav.DrawToggle(const R: TRect; AColor: TColor);
var
  X, Y, Split, Mid, CX: integer;
begin
  if FHotToggle then
  begin
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FHover;
    Canvas.RoundRect(R, Px(ToggleRadius), Px(ToggleRadius));
  end;
  X := R.Left + (R.Width - Px(ToggleIconWidth)) div 2;
  Y := R.Top + (R.Height - Px(ToggleIconHeight)) div 2;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := AColor;
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  Canvas.RoundRect(X, Y, X + Px(ToggleIconWidth) + 1, Y + Px(ToggleIconHeight) + 1, 3, 3);
  Split := X + Px(ToggleIconWidth) div 3;
  Canvas.Line(Split, Y + 1, Split, Y + Px(ToggleIconHeight));
  Mid := Y + Px(ToggleIconHeight) div 2;
  CX := (Split + X + Px(ToggleIconWidth)) div 2;
  Canvas.Line(CX - 2, Mid, CX + 3, Mid);
  if FCollapsed then
    Canvas.Polyline([Point(CX, Mid - 2), Point(CX + 2, Mid), Point(CX, Mid + 2)])
  else
    Canvas.Polyline([Point(CX, Mid - 2), Point(CX - 2, Mid), Point(CX, Mid + 2)]);
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
    Y := 2 * Px(PadY) + RowsHeight + Px(HeadingTop);
    { The page is drawn one in from X. }
    DrawIcon(niFiles, Px(HeadingLeft) - 1, Y + (TextH - Px(HeadingIconSize)) div 2,
      Px(HeadingIconSize), FDim);
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := FDim;
    Canvas.TextOut(Px(HeadingTextLeft), Y, FHeading);
    Canvas.Font.Style := [];
    Inc(Y, TextH + Px(HeadingGap));
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Color := FLine;
    Canvas.Line(Px(HeadingLeft), Y, Width - Px(HeadingLeft), Y);
  end;
  for i := 0 to High(FCaptions) do
  begin
    if FCollapsed and (i > 0) then
      Break;
    if FHidden[i] then
      Continue;
    R := RowRect(i);
    if FSmall[i] then
    begin
      Canvas.Font := Font;
      Icon := Px(IconSize);
      Gap := Px(IconGap);
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
      Canvas.RoundRect(R, Px(Radius), Px(Radius));
      Canvas.Pen.Style := psSolid;
    end;
    Canvas.Brush.Style := bsClear;
    TextY := R.Top + (R.Height - TextH) div 2;
    if FSmall[i] or not FLarge then
      PenW := 1
    else
      PenW := LargePenWidth;
    if i = FSelected then
      DrawIcon(FIcons[i], R.Left + Px(PadX), R.Top + (R.Height - Icon) div 2, Icon, FText, PenW)
    else
      DrawIcon(FIcons[i], R.Left + Px(PadX), R.Top + (R.Height - Icon) div 2, Icon, FDim, PenW);
    Canvas.Pen.Width := 1;
    Canvas.Font.Color := FText;
    if i = FSelected then
      Canvas.Font.Style := [fsBold]
    else
      Canvas.Font.Style := [];
    Canvas.TextOut(R.Left + Px(PadX) + Icon + Gap, TextY, FCaptions[i]);
  end;
  if FToggle then
  begin
    if FHotToggle then
      DrawToggle(ToggleRect, FText)
    else
      DrawToggle(ToggleRect, FDim);
  end;
  Canvas.Font := Font;
end;

procedure TGittanSideNav.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHotToggle(FToggle and PtInRect(ToggleRect, Point(X, Y)));
  if FHotToggle or (X < Px(PadX)) or (X >= Width - Px(PadX)) then
    SetHot(-1)
  else
    SetHot(RowAt(Y));
end;

procedure TGittanSideNav.MouseLeave;
begin
  inherited MouseLeave;
  SetHotToggle(False);
  SetHot(-1);
end;

{ The button keeps to the right end as the sidebar is sized with the
  splitter. }
procedure TGittanSideNav.Resize;
begin
  inherited Resize;
  Invalidate;
end;

procedure TGittanSideNav.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  Row: integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  if FToggle and PtInRect(ToggleRect, Point(X, Y)) then
  begin
    Collapsed := not Collapsed;
    Exit;
  end;
  Row := RowAt(Y);
  if (Row >= 0) and (X >= Px(PadX)) and (X < Width - Px(PadX)) and Assigned(FOnPick) then
    FOnPick(Self, Row);
end;

{ The form scales every control by its DPI after FormCreate, this one's
  height too, which is already the screen's: set it again. }
procedure TGittanSideNav.DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
  const AXProportion, AYProportion: double);
begin
  inherited DoAutoAdjustLayout(AMode, AXProportion, AYProportion);
  if AMode = lapAutoAdjustForDPI then
    FitHeight;
end;

end.
