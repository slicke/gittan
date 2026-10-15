unit gittan.welcome;

{** The welcome view: what Gittan shows while no repository is open, and
  where a failure to open one is reported. Under the application icon and
  the name it offers a button that opens the folder dialog, with the
  shortcut drawn as key caps beside it, and lists the recent repositories
  as rows to click, each with its name and path; a repository whose folder
  is gone is listed dimmed and does not react. An error is shown in red
  under the name, wrapped to the column, so the next attempt is one click
  or one drop away.

  It paints itself in the editor's palette, like the summary, and sizes
  its height to its content so it can sit in the same TScrollBox: the
  block is centered while there is room and the box scrolls when there
  is not. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics;

type
  {** A click on a recent repository, with its root. }
  TGittanOpenRecentEvent = procedure(Sender: TObject; const ARoot: string) of object;

  { TGittanWelcome }

  TGittanWelcome = class(TCustomControl)
  private
    FTitle, FTagline, FError, FShortcut: string;
    FRecent: TStringList;
    FIcon: TIcon;
    FIconBitmap: TBitmap;
    FBack, FText, FDim, FHover, FLine, FErrorColor: TColor;
    { What the mouse is over: hotNone, hotButton or a row's index. }
    FHot: integer;
    FButtonRect: TRect;
    FRowRects: array of TRect;
    FContentHeight: integer;
    FOnOpen: TNotifyEvent;
    FOnOpenRecent: TGittanOpenRecentEvent;
    function HotAt(X, Y: integer): integer;
    procedure SetHot(AValue: integer);
    function RecentMissing(AIndex: integer): boolean;
    function FitLeft(const AText: string; AMaxWidth: integer): string;
    procedure WrapError(AWidth: integer; ALines: TStrings);
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** The application icon, drawn above the title; nil draws none. The
      icon stays the caller's. }
    procedure SetIcon(AIcon: TIcon);
    {** The recent repositories, most recent first; a copy is kept. }
    procedure SetRecent(ARoots: TStrings);
    {** The error shown under the title; empty shows none. }
    procedure SetError(const AMessage: string);
    {** The palette: the background, the text, the dim text, the hovered
      button or row, the line of the borders and the divider, and the
      error text. }
    procedure SetColors(ABack, AText, ADim, AHover, ALine, AError: TColor);
    {** Makes the control at least AMin high (the height of the box it
      sits in, so its background covers the box), and no higher than its
      content needs beyond that. }
    procedure FitHeight(AMin: integer);
    {** The application name over the tagline. }
    property Title: string read FTitle write FTitle;
    {** The dim line under the title. }
    property Tagline: string read FTagline write FTagline;
    {** The shortcut of the open button, drawn as key caps beside it. }
    property Shortcut: string read FShortcut write FShortcut;
    {** A click on the open button. }
    property OnOpen: TNotifyEvent read FOnOpen write FOnOpen;
    {** A click on a recent repository. }
    property OnOpenRecent: TGittanOpenRecentEvent read FOnOpenRecent write FOnOpenRecent;
  end;

implementation

uses
  Math, gittan.statusbar;

resourcestring
  rsOpenButton = 'Open Repository…';
  rsRecent = 'Recent';
  rsNotFound = 'not found';
  rsDrop = 'or drop a folder or file here';

const
  hotNone = -1;
  hotButton = -2;
  Pad = 24;
  Gap = 12;
  ColumnWidth = 480;
  IconSize = 64;
  TitleFontSize = 20;
  ButtonPadX = 14;
  ButtonPadY = 6;
  KeyPadX = 5;
  KeyPadY = 2;
  RowHeight = 44;
  RowPadX = 10;
  FolderSize = 20;

{ TGittanWelcome }

constructor TGittanWelcome.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FRecent := TStringList.Create;
  FHot := hotNone;
  Align := alTop;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnShadow, clRed);
end;

destructor TGittanWelcome.Destroy;
begin
  FIconBitmap.Free;
  FRecent.Free;
  inherited Destroy;
end;

procedure TGittanWelcome.SetIcon(AIcon: TIcon);
begin
  FIcon := AIcon;
  FreeAndNil(FIconBitmap);
  Invalidate;
end;

procedure TGittanWelcome.SetRecent(ARoots: TStrings);
begin
  FRecent.Assign(ARoots);
  FHot := hotNone;
  Invalidate;
end;

procedure TGittanWelcome.SetError(const AMessage: string);
begin
  if FError = AMessage then
    Exit;
  FError := AMessage;
  Invalidate;
end;

procedure TGittanWelcome.SetColors(ABack, AText, ADim, AHover, ALine,
  AError: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
  FLine := ALine;
  FErrorColor := AError;
  Color := ABack;
  Invalidate;
end;

procedure TGittanWelcome.FitHeight(AMin: integer);
begin
  Constraints.MinHeight := AMin;
  Height := Max(FContentHeight, AMin);
end;

function TGittanWelcome.RecentMissing(AIndex: integer): boolean;
begin
  Result := not DirectoryExists(FRecent[AIndex]);
end;

function TGittanWelcome.HotAt(X, Y: integer): integer;
var
  P: TPoint;
  i: integer;
begin
  P := Point(X, Y);
  if PtInRect(FButtonRect, P) then
    Exit(hotButton);
  for i := 0 to High(FRowRects) do
    if PtInRect(FRowRects[i], P) and not RecentMissing(i) then
      Exit(i);
  Result := hotNone;
end;

procedure TGittanWelcome.SetHot(AValue: integer);
begin
  if FHot = AValue then
    Exit;
  FHot := AValue;
  if AValue = hotNone then
    Cursor := crDefault
  else
    Cursor := crHandPoint;
  Invalidate;
end;

{ AText cut from the left with an ellipsis until it fits AMaxWidth, so a
  long path keeps its end, which is the part that tells. }
function TGittanWelcome.FitLeft(const AText: string; AMaxWidth: integer): string;
var
  Cut: integer;
begin
  Result := AText;
  if Canvas.TextWidth(Result) <= AMaxWidth then
    Exit;
  Cut := 1;
  while (Cut < Length(AText)) and
    (Canvas.TextWidth('…' + Copy(AText, Cut + 1, MaxInt)) > AMaxWidth) do
    Inc(Cut);
  Result := '…' + Copy(AText, Cut + 1, MaxInt);
end;

{ The error broken into lines no wider than AWidth with the canvas font:
  at spaces, and inside a word too wide for a line (a path, mostly)
  after a slash, or anywhere when there is no slash either. }
procedure TGittanWelcome.WrapError(AWidth: integer; ALines: TStrings);
var
  Line, Word, Rest: string;
  i, Cut, Best: integer;
  Words: TStringArray;
begin
  ALines.Clear;
  Line := '';
  Words := FError.Split([' '], TStringSplitOptions.ExcludeEmpty);
  for i := 0 to High(Words) do
  begin
    Word := Words[i];
    if (Line <> '') and (Canvas.TextWidth(Line + ' ' + Word) <= AWidth) then
    begin
      Line := Line + ' ' + Word;
      Continue;
    end;
    if Line <> '' then
      ALines.Add(Line);
    Line := Word;
    while Canvas.TextWidth(Line) > AWidth do
    begin
      { The longest head that fits, ending after a slash when one is
        there; a head of at least one character, so the loop ends. }
      Best := 0;
      Cut := 1;
      while (Cut < Length(Line)) and (Canvas.TextWidth(Copy(Line, 1, Cut)) <= AWidth) do
      begin
        if Line[Cut] = '/' then
          Best := Cut;
        Inc(Cut);
      end;
      if Best = 0 then
        Best := Max(1, Cut - 1);
      Rest := Copy(Line, Best + 1, MaxInt);
      ALines.Add(Copy(Line, 1, Best));
      Line := Rest;
    end;
  end;
  if Line <> '' then
    ALines.Add(Line);
end;

procedure TGittanWelcome.Paint;
var
  ColLeft, ColWidth, Y, BlockTop, Total, LineHeight, TitleHeight, ErrHeight: integer;
  ButtonWidth, KeyWidth, X, TextY, i, NameWidth: integer;
  R: TRect;
  RepoName, Path: string;
  Missing, HasIcon: boolean;
  ErrLines: TStringList;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  LineHeight := Canvas.TextHeight('Xg');
  ColWidth := Min(ColumnWidth, Width - 2 * Pad);
  ColLeft := (Width - ColWidth) div 2;
  HasIcon := (FIcon <> nil) and not FIcon.Empty;

  { The block's height first, to place it: a little above the middle
    of the room, which looks centered, and never off the top. }
  Canvas.Font.Size := TitleFontSize;
  Canvas.Font.Style := [fsBold];
  TitleHeight := Canvas.TextHeight('Xg');
  Canvas.Font.Size := Font.Size;
  Canvas.Font.Style := [];
  Total := 0;
  if HasIcon then
    Inc(Total, IconSize + Gap);
  Inc(Total, TitleHeight + 2);
  if FTagline <> '' then
    Inc(Total, LineHeight);
  ErrHeight := 0;
  ErrLines := TStringList.Create;
  try
    if FError <> '' then
    begin
      WrapError(ColWidth, ErrLines);
      ErrHeight := ErrLines.Count * LineHeight;
      Inc(Total, Gap + ErrHeight);
    end;
    Inc(Total, Pad + LineHeight + 2 * ButtonPadY);
    if FRecent.Count > 0 then
      Inc(Total, Pad + LineHeight + Gap div 2 + 1 + Gap div 2 + FRecent.Count * RowHeight);
    Inc(Total, Pad + LineHeight);
    FContentHeight := Total + 2 * Pad;
    if Height < FContentHeight then
    begin
      Height := Max(FContentHeight, Constraints.MinHeight);
      Exit;
    end;
    BlockTop := Max(Pad, (Height - Total) * 2 div 5);
    Y := BlockTop;

    if HasIcon then
    begin
      { The icon's image for the size in device pixels (so a HiDPI screen
        gets the sharp one) is copied into a bitmap: drawing the icon
        itself goes through its handle, which Cocoa makes from the first,
        smallest image. }
      if FIconBitmap = nil then
      begin
        FIcon.Current := FIcon.GetBestIndexForSize(
          Size(Round(IconSize * GetCanvasScaleFactor), Round(IconSize * GetCanvasScaleFactor)));
        FIconBitmap := TBitmap.Create;
        FIconBitmap.LoadFromRawImage(FIcon.RawImage, False);
      end;
      Canvas.StretchDraw(Rect((Width - IconSize) div 2, Y, (Width + IconSize) div 2,
        Y + IconSize), FIconBitmap);
      Inc(Y, IconSize + Gap);
    end;

    Canvas.Font.Size := TitleFontSize;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := FText;
    Canvas.TextOut((Width - Canvas.TextWidth(FTitle)) div 2, Y, FTitle);
    Inc(Y, TitleHeight + 2);
    Canvas.Font.Size := Font.Size;
    Canvas.Font.Style := [];
    if FTagline <> '' then
    begin
      Canvas.Font.Color := FDim;
      Canvas.TextOut((Width - Canvas.TextWidth(FTagline)) div 2, Y, FTagline);
      Inc(Y, LineHeight);
    end;

    if FError <> '' then
    begin
      Inc(Y, Gap);
      Canvas.Font.Color := FErrorColor;
      for i := 0 to ErrLines.Count - 1 do
        Canvas.TextOut((Width - Canvas.TextWidth(ErrLines[i])) div 2,
          Y + i * LineHeight, ErrLines[i]);
      Inc(Y, ErrHeight);
    end;

    { The open button and its shortcut, as one centered group. }
    Inc(Y, Pad);
    ButtonWidth := Canvas.TextWidth(rsOpenButton) + 2 * ButtonPadX;
    KeyWidth := 0;
    if FShortcut <> '' then
      KeyWidth := Gap + Canvas.TextWidth(FShortcut) + 2 * KeyPadX;
    X := (Width - ButtonWidth - KeyWidth) div 2;
    FButtonRect := Rect(X, Y, X + ButtonWidth, Y + LineHeight + 2 * ButtonPadY);
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Color := FLine;
    if FHot = hotButton then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := FHover;
    end
    else
      Canvas.Brush.Style := bsClear;
    Canvas.RoundRect(FButtonRect, 10, 10);
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := FText;
    Canvas.TextOut(X + ButtonPadX, Y + ButtonPadY, rsOpenButton);
    if FShortcut <> '' then
    begin
      { The shortcut as a key cap: a small rounded frame in dim. }
      X := FButtonRect.Right + Gap;
      TextY := Y + ButtonPadY;
      R := Rect(X, TextY - KeyPadY, X + KeyWidth - Gap, TextY + LineHeight + KeyPadY);
      Canvas.Pen.Color := FLine;
      Canvas.RoundRect(R, 6, 6);
      Canvas.Font.Color := FDim;
      Canvas.TextOut(X + KeyPadX, TextY, FShortcut);
    end;
    Inc(Y, LineHeight + 2 * ButtonPadY);

    { The recent repositories: a dim heading over a divider, then a row
      per repository with the folder, the name and the path. }
    SetLength(FRowRects, FRecent.Count);
    if FRecent.Count > 0 then
    begin
      Inc(Y, Pad);
      Canvas.Font.Color := FDim;
      Canvas.TextOut(ColLeft, Y, rsRecent);
      Inc(Y, LineHeight + Gap div 2);
      Canvas.Pen.Color := FLine;
      Canvas.Line(ColLeft, Y, ColLeft + ColWidth, Y);
      Inc(Y, 1 + Gap div 2);
      for i := 0 to FRecent.Count - 1 do
      begin
        FRowRects[i] := Rect(ColLeft - RowPadX, Y, ColLeft + ColWidth + RowPadX, Y + RowHeight);
        Missing := RecentMissing(i);
        if FHot = i then
        begin
          Canvas.Pen.Style := psClear;
          Canvas.Brush.Style := bsSolid;
          Canvas.Brush.Color := FHover;
          Canvas.RoundRect(FRowRects[i], 10, 10);
          Canvas.Pen.Style := psSolid;
          Canvas.Brush.Style := bsClear;
        end;
        DrawStatusIcon(Canvas, HintFolder, ColLeft + 2, Y + (RowHeight - FolderSize) div 2,
          FolderSize, FDim);
        Canvas.Brush.Style := bsClear;
        X := ColLeft + FolderSize + Gap;
        RepoName := ExtractFileName(ExcludeTrailingPathDelimiter(FRecent[i]));
        Path := FRecent[i];
        TextY := Y + (RowHeight - 2 * LineHeight) div 2;
        if Missing then
          Canvas.Font.Color := FDim
        else
          Canvas.Font.Color := FText;
        Canvas.TextOut(X, TextY, RepoName);
        NameWidth := Canvas.TextWidth(RepoName);
        Canvas.Font.Color := FDim;
        if Missing then
          Canvas.TextOut(X + NameWidth + Gap div 2, TextY, '· ' + rsNotFound);
        Canvas.TextOut(X, TextY + LineHeight, FitLeft(Path, ColLeft + ColWidth - X));
        Inc(Y, RowHeight);
      end;
    end;

    Inc(Y, Pad);
    Canvas.Font.Color := FDim;
    Canvas.TextOut((Width - Canvas.TextWidth(rsDrop)) div 2, Y, rsDrop);
  finally
    ErrLines.Free;
  end;
end;

procedure TGittanWelcome.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(HotAt(X, Y));
end;

procedure TGittanWelcome.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(hotNone);
end;

procedure TGittanWelcome.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Hit: integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  Hit := HotAt(X, Y);
  if (Hit = hotButton) and Assigned(FOnOpen) then
    FOnOpen(Self)
  else if (Hit >= 0) and Assigned(FOnOpenRecent) then
    FOnOpenRecent(Self, FRecent[Hit]);
end;

end.
