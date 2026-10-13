unit gittan.summary;

{** The repository summary: what Gittan shows when a repository is opened,
  before a file is picked. It lists the changed files with their added and
  deleted line counts and a bar that compares the sizes of the changes,
  under a header with the repository name, branch and totals. With no
  repository open it shows a hint instead.

  It paints itself so it matches the editor's palette in both themes. It
  sizes its height to its content and is meant to sit in a TScrollBox,
  which provides the native scrolling. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, ImgList, gittan.git;

type
  TGittanSelectFileEvent = procedure(Sender: TObject; const APath: string) of object;
  {** A right click on a file's row, with the mouse position in screen
    coordinates for a popup menu. }
  TGittanContextFileEvent = procedure(Sender: TObject; const APath: string;
    const AScreenPos: TPoint) of object;

  { TGittanSummary }

  TGittanSummary = class(TCustomControl)
  private
    FRepoName, FBranch, FBase, FMessage, FHint, FSelected, FNotice: string;
    FStats: TGittanFileStats;
    FImages: TCustomImageList;
    FIcon: TIcon;
    FIconBitmap: TBitmap;
    FIconIndex: array of integer;
    FHot: integer;
    FBack, FText, FDim, FHover, FSelectedBack, FAdded, FDeleted, FLine: TColor;
    FOnSelectFile: TGittanSelectFileEvent;
    FOnContextFile: TGittanContextFileEvent;
    FRowsTop: integer;
    function RowAt(Y: integer): integer;
    procedure SetHot(AValue: integer);
    procedure SetSelected(const AValue: string);
    procedure SetNotice(const AValue: string);
    procedure UpdateHeight;
    procedure PaintNotice(var Y: integer);
    procedure PaintMessage;
    procedure PaintClean(Y: integer);
    procedure PaintHeader(var Y: integer);
    procedure PaintRow(AIndex, ATop: integer);
    procedure PaintBar(X, Y: integer; const AStat: TGittanFileStat; AMax: integer);
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** Shows the changed files AStats of repository AName on ABranch,
      with ABase saying what is compared, as it is to be shown ("vs
      main", "main...feature"; empty for the usual HEAD); AIcons holds
      the image index in Images of each file's badge. }
    procedure SetRepository(const AName, ABranch, ABase: string;
      const AStats: TGittanFileStats; const AIcons: array of integer);
    {** Shows AMessage alone, centered, under AIcon (when it has one) and
      over the dimmer AHint: the view with no repository. }
    procedure SetMessage(const AMessage, AHint: string; AIcon: TIcon);
    {** Sets the palette: the background, the text, the dim text for paths
      and counts, the hovered row, the selected row, the added and deleted
      colors, and the line color for the divider and the empty part of a
      bar. }
    procedure SetColors(ABack, AText, ADim, AHover, ASelected, AAdded,
      ADeleted, ALine: TColor);
    {** The image list the file badges come from. }
    property Images: TCustomImageList read FImages write FImages;
    {** The path of the file whose row is marked: the one the editor last
      showed. Empty marks none. }
    property Selected: string read FSelected write SetSelected;
    {** A line under the header, dimmed: why the summary is shown when
      the user did not ask for it. Empty shows none. }
    property Notice: string read FNotice write SetNotice;
    {** A click on a file's row. }
    property OnSelectFile: TGittanSelectFileEvent read FOnSelectFile write FOnSelectFile;
    {** A right click on a file's row. }
    property OnContextFile: TGittanContextFileEvent read FOnContextFile write FOnContextFile;
  end;

implementation

uses
  Math;

resourcestring
  rsOnBranch = 'on %s';
  rsOneFile = '1 changed file';
  rsManyFiles = '%d changed files';
  rsNoChanges = 'No changes';
  rsClean = 'Working tree clean';
  rsCleanVs = 'No changes %s';
  rsBinary = 'binary';
  rsStaged = 'staged';
  rsPartlyStaged = 'partly staged';

const
  Pad = 24;
  RowHeight = 28;
  IconSize = 16;
  BarWidth = 96;
  BarHeight = 6;
  CountWidth = 56;
  Gap = 12;
  TitleFontSize = 20;
  MessageIconSize = 64;
  CheckSize = 20;

{ TGittanSummary }

constructor TGittanSummary.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FHot := -1;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnFace, clGreen,
    clRed, clBtnShadow);
  SetMessage('', '', nil);
end;

destructor TGittanSummary.Destroy;
begin
  FIconBitmap.Free;
  inherited Destroy;
end;

procedure TGittanSummary.SetRepository(const AName, ABranch, ABase: string;
  const AStats: TGittanFileStats; const AIcons: array of integer);
var
  i: integer;
begin
  FRepoName := AName;
  FBranch := ABranch;
  FBase := ABase;
  FMessage := '';
  FStats := Copy(AStats);
  SetLength(FIconIndex, Length(AIcons));
  for i := 0 to High(AIcons) do
    FIconIndex[i] := AIcons[i];
  FHot := -1;
  { The height follows the content; the scroll box it sits in scrolls. }
  Align := alTop;
  UpdateHeight;
  Invalidate;
end;

procedure TGittanSummary.SetMessage(const AMessage, AHint: string; AIcon: TIcon);
begin
  FMessage := AMessage;
  FHint := AHint;
  FIcon := AIcon;
  FreeAndNil(FIconBitmap);
  FStats := nil;
  FIconIndex := nil;
  FHot := -1;
  { The message is centered in whatever room the scroll box has. }
  Align := alClient;
  Invalidate;
end;

procedure TGittanSummary.SetColors(ABack, AText, ADim, AHover, ASelected,
  AAdded, ADeleted, ALine: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
  FSelectedBack := ASelected;
  FAdded := AAdded;
  FDeleted := ADeleted;
  FLine := ALine;
  Color := ABack;
  Invalidate;
end;

{ The header is measured in Paint, so the height is an estimate from the
  font until the first paint settles it. }
procedure TGittanSummary.UpdateHeight;
var
  Measure: TBitmap;
  TitleHeight, BodyHeight: integer;
begin
  Measure := TBitmap.Create;
  try
    Measure.Canvas.Font := Font;
    BodyHeight := Measure.Canvas.TextHeight('Xg');
    Measure.Canvas.Font.Size := TitleFontSize;
    TitleHeight := Measure.Canvas.TextHeight('Xg');
  finally
    Measure.Free;
  end;
  FRowsTop := Pad + TitleHeight + 6 + BodyHeight + Pad;
  if FNotice <> '' then
    Inc(FRowsTop, RowHeight);
  Height := FRowsTop + Max(Length(FStats), 2) * RowHeight + Pad;
end;

procedure TGittanSummary.SetSelected(const AValue: string);
begin
  if FSelected = AValue then
    Exit;
  FSelected := AValue;
  Invalidate;
end;

procedure TGittanSummary.SetNotice(const AValue: string);
begin
  if FNotice = AValue then
    Exit;
  FNotice := AValue;
  if FMessage = '' then
    UpdateHeight;
  Invalidate;
end;

function TGittanSummary.RowAt(Y: integer): integer;
begin
  Result := -1;
  if (FMessage <> '') or (Y < FRowsTop) then
    Exit;
  Result := (Y - FRowsTop) div RowHeight;
  if Result > High(FStats) then
    Result := -1;
end;

procedure TGittanSummary.SetHot(AValue: integer);
begin
  if FHot = AValue then
    Exit;
  FHot := AValue;
  Invalidate;
end;

{ Repository name and branch on one line, the file count and totals on the
  next, a divider below. Y is advanced past the header. }
procedure TGittanSummary.PaintHeader(var Y: integer);
var
  X, TitleHeight, BodyHeight, Added, Deleted, i: integer;
  Heading: string;
begin
  Canvas.Brush.Style := bsClear;
  Canvas.Font := Font;
  BodyHeight := Canvas.TextHeight('Xg');
  Canvas.Font.Size := TitleFontSize;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FText;
  TitleHeight := Canvas.TextHeight('Xg');
  Canvas.TextOut(Pad, Y, FRepoName);
  X := Pad + Canvas.TextWidth(FRepoName) + Gap;
  Canvas.Font.Size := Font.Size;
  Canvas.Font.Style := [];
  Canvas.Font.Color := FDim;
  if FBranch <> '' then
  begin
    Canvas.TextOut(X, Y + TitleHeight - BodyHeight - 3, Format(rsOnBranch, [FBranch]));
    Inc(X, Canvas.TextWidth(Format(rsOnBranch, [FBranch])) + Gap);
  end;
  if FBase <> '' then
  begin
    Canvas.Font.Color := FText;
    Canvas.TextOut(X, Y + TitleHeight - BodyHeight - 3, FBase);

  end;
  Inc(Y, TitleHeight + 6);

  Added := 0;
  Deleted := 0;
  for i := 0 to High(FStats) do
  begin
    Inc(Added, FStats[i].Added);
    Inc(Deleted, FStats[i].Deleted);
  end;
  X := Pad;
  case Length(FStats) of
    0: Heading := rsNoChanges;
    1: Heading := rsOneFile;
    else
      Heading := Format(rsManyFiles, [Length(FStats)]);
  end;
  Canvas.Font.Color := FDim;
  Canvas.TextOut(X, Y, Heading);
  Inc(X, Canvas.TextWidth(Heading) + Gap);
  if Length(FStats) > 0 then
  begin
    Canvas.Font.Color := FAdded;
    Heading := '+' + IntToStr(Added);
    Canvas.TextOut(X, Y, Heading);
    Inc(X, Canvas.TextWidth(Heading) + Gap div 2);
    Canvas.Font.Color := FDeleted;
    Canvas.TextOut(X, Y, '−' + IntToStr(Deleted));
  end;
  Inc(Y, BodyHeight + Pad div 2);
  Canvas.Pen.Color := FLine;
  Canvas.Line(Pad, Y, Width - Pad, Y);
  Inc(Y, Pad div 2);
end;

{ An info disc with an "i" and the notice text, in the row above the
  files. Y is advanced past it. }
procedure TGittanSummary.PaintNotice(var Y: integer);
var
  X, CenterY: integer;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  X := Pad;
  CenterY := Y + RowHeight div 2;
  Canvas.Pen.Color := FDim;
  Canvas.Brush.Style := bsClear;
  Canvas.Ellipse(X, CenterY - CheckSize div 2, X + CheckSize, CenterY + CheckSize div 2);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FDim;
  Canvas.TextOut(X + (CheckSize - Canvas.TextWidth('i')) div 2,
    CenterY - Canvas.TextHeight('i') div 2, 'i');
  Canvas.Font.Style := [];
  Canvas.TextOut(X + CheckSize + Gap div 2 + 2,
    CenterY - Canvas.TextHeight('Xg') div 2, FNotice);
  Inc(Y, RowHeight);
end;

{ The bar compares this file's change with the largest one: the added part
  in green, the deleted part in red, the rest of the track in the line
  color. A change too small for a pixel still gets one. }
procedure TGittanSummary.PaintBar(X, Y: integer; const AStat: TGittanFileStat;
  AMax: integer);
var
  AddedWidth, DeletedWidth: integer;
begin
  Canvas.Pen.Style := psClear;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FLine;
  Canvas.RoundRect(X, Y, X + BarWidth, Y + BarHeight, BarHeight, BarHeight);
  if AMax = 0 then
    Exit;
  AddedWidth := Round(AStat.Added / AMax * BarWidth);
  if (AStat.Added > 0) and (AddedWidth < 2) then
    AddedWidth := 2;
  DeletedWidth := Round(AStat.Deleted / AMax * BarWidth);
  if (AStat.Deleted > 0) and (DeletedWidth < 2) then
    DeletedWidth := 2;
  DeletedWidth := Min(DeletedWidth, BarWidth - AddedWidth);
  if AddedWidth > 0 then
  begin
    Canvas.Brush.Color := FAdded;
    Canvas.RoundRect(X, Y, X + AddedWidth, Y + BarHeight, BarHeight, BarHeight);
  end;
  if DeletedWidth > 0 then
  begin
    Canvas.Brush.Color := FDeleted;
    Canvas.RoundRect(X + AddedWidth, Y, X + AddedWidth + DeletedWidth,
      Y + BarHeight, BarHeight, BarHeight);
  end;
  Canvas.Pen.Style := psSolid;
end;

{ Badge, directory in dim and file name in full color, then the counts and
  the bar on the right. A path too long for the room loses its directory
  first, then its end. }
procedure TGittanSummary.PaintRow(AIndex, ATop: integer);
var
  Stat: TGittanFileStat;
  X, CountsX, TextY, BodyHeight, Room, MaxChange, i: integer;
  Dir, FileName, Count: string;
begin
  Stat := FStats[AIndex];
  Canvas.Font := Font;
  BodyHeight := Canvas.TextHeight('Xg');
  TextY := ATop + (RowHeight - BodyHeight) div 2;
  if (AIndex = FHot) or (Stat.Path = FSelected) then
  begin
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    if AIndex = FHot then
      Canvas.Brush.Color := FHover
    else
      Canvas.Brush.Color := FSelectedBack;
    Canvas.RoundRect(Pad div 2, ATop, Width - Pad div 2, ATop + RowHeight, 8, 8);
    Canvas.Pen.Style := psSolid;
  end;
  X := Pad;
  if (FImages <> nil) and (AIndex <= High(FIconIndex)) then
    FImages.DrawForPPI(Canvas, X, ATop + (RowHeight - IconSize) div 2,
      FIconIndex[AIndex], IconSize, Font.PixelsPerInch, GetCanvasScaleFactor);
  Inc(X, IconSize + Gap div 2 + 2);

  CountsX := Width - Pad - BarWidth - Gap - 2 * CountWidth - Gap div 2;
  Room := CountsX - Gap - X;
  Dir := ExtractFilePath(Stat.Path);
  FileName := ExtractFileName(Stat.Path);
  Canvas.Brush.Style := bsClear;
  if Canvas.TextWidth(Dir + FileName) > Room then
    Dir := '';
  while (FileName <> '') and (Canvas.TextWidth(FileName + '…') > Room) do
  begin
    FileName := Copy(FileName, 1, Length(FileName) - 1);
    { Keep UTF-8 sequences whole. }
    while (FileName <> '') and (Ord(FileName[Length(FileName)]) and $C0 = $80) do
      FileName := Copy(FileName, 1, Length(FileName) - 1);
    if FileName = ExtractFileName(Stat.Path) then
      Break;
  end;
  if FileName <> ExtractFileName(Stat.Path) then
    FileName := FileName + '…';
  if Dir <> '' then
  begin
    Canvas.Font.Color := FDim;
    Canvas.TextOut(X, TextY, Dir);
    Inc(X, Canvas.TextWidth(Dir));
  end;
  Canvas.Font.Color := FText;
  Canvas.TextOut(X, TextY, FileName);
  Inc(X, Canvas.TextWidth(FileName) + Gap);
  { What the index holds, when the path left room for it. }
  if Stat.Staged then
  begin
    if Stat.Unstaged then
      Count := rsPartlyStaged
    else
      Count := rsStaged;
    if X + Canvas.TextWidth(Count) <= CountsX - Gap then
    begin
      Canvas.Font.Color := FDim;
      Canvas.TextOut(X, TextY, Count);
    end;
  end;

  if Stat.Binary then
  begin
    Canvas.Font.Color := FDim;
    Canvas.TextOut(CountsX + 2 * CountWidth + Gap div 2 - Canvas.TextWidth(rsBinary),
      TextY, rsBinary);
  end
  else
  begin
    { A zero is shown, so the columns stay aligned, but dimmed. }
    if Stat.Added > 0 then
      Canvas.Font.Color := FAdded
    else
      Canvas.Font.Color := FDim;
    Count := '+' + IntToStr(Stat.Added);
    Canvas.TextOut(CountsX + CountWidth - Canvas.TextWidth(Count), TextY, Count);
    if Stat.Deleted > 0 then
      Canvas.Font.Color := FDeleted
    else
      Canvas.Font.Color := FDim;
    Count := '−' + IntToStr(Stat.Deleted);
    Canvas.TextOut(CountsX + 2 * CountWidth + Gap div 2 - Canvas.TextWidth(Count),
      TextY, Count);
  end;

  MaxChange := 0;
  for i := 0 to High(FStats) do
    MaxChange := Max(MaxChange, FStats[i].Added + FStats[i].Deleted);
  PaintBar(Width - Pad - BarWidth, ATop + (RowHeight - BarHeight) div 2, Stat,
    MaxChange);
end;

{ The icon, the message in full color and the hint in dim, as one block
  centered in the control. }
procedure TGittanSummary.PaintMessage;
var
  Y, LineHeight, Total: integer;
  HasIcon: boolean;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  LineHeight := Canvas.TextHeight('Xg');
  HasIcon := (FIcon <> nil) and not FIcon.Empty;
  Total := LineHeight;
  if HasIcon then
    Inc(Total, MessageIconSize + Pad);
  if FHint <> '' then
    Inc(Total, LineHeight + Gap div 2);
  Y := (Height - Total) div 2;
  if HasIcon then
  begin
    { The icon's image for the size in device pixels (so a HiDPI screen
      gets the sharp one) is copied into a bitmap: drawing the icon
      itself goes through its handle, which Cocoa makes from the first,
      smallest image. }
    if FIconBitmap = nil then
    begin
      FIcon.Current := FIcon.GetBestIndexForSize(
        Size(Round(MessageIconSize * GetCanvasScaleFactor),
        Round(MessageIconSize * GetCanvasScaleFactor)));
      FIconBitmap := TBitmap.Create;
      FIconBitmap.LoadFromRawImage(FIcon.RawImage, False);
    end;
    Canvas.StretchDraw(Rect((Width - MessageIconSize) div 2, Y,
      (Width + MessageIconSize) div 2, Y + MessageIconSize), FIconBitmap);
    Inc(Y, MessageIconSize + Pad);
  end;
  Canvas.Font.Color := FText;
  Canvas.TextOut((Width - Canvas.TextWidth(FMessage)) div 2, Y, FMessage);
  if FHint <> '' then
  begin
    Inc(Y, LineHeight + Gap div 2);
    Canvas.Font.Color := FDim;
    Canvas.TextOut((Width - Canvas.TextWidth(FHint)) div 2, Y, FHint);
  end;
end;

{ A green disc with a check mark and "Working tree clean" (or "No changes
  vs base" when the tree is compared against something other than HEAD),
  where the rows would start, so a repository without changes does not
  look unfinished. }
procedure TGittanSummary.PaintClean(Y: integer);
var
  X, CenterY: integer;
  CleanText: string;
begin
  if FBase = '' then
    CleanText := rsClean
  else
    CleanText := Format(rsCleanVs, [FBase]);
  Canvas.Font := Font;
  Canvas.Font.Color := FDim;
  Canvas.Brush.Style := bsClear;
  X := Pad;
  CenterY := Y + RowHeight div 2;
  Canvas.Pen.Style := psClear;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FAdded;
  Canvas.Ellipse(X, CenterY - CheckSize div 2, X + CheckSize, CenterY + CheckSize div 2);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := FBack;
  Canvas.Pen.Width := 2;
  Canvas.Polyline([Point(X + 5, CenterY), Point(X + 9, CenterY + 4),
    Point(X + 15, CenterY - 4)]);
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(X + CheckSize + Gap div 2 + 2,
    CenterY - Canvas.TextHeight('Xg') div 2, CleanText);
end;

procedure TGittanSummary.Paint;
var
  Y, i: integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  if FMessage <> '' then
  begin
    PaintMessage;
    Exit;
  end;
  Y := Pad;
  PaintHeader(Y);
  if FNotice <> '' then
    PaintNotice(Y);
  if Y <> FRowsTop then
  begin
    FRowsTop := Y;
    Height := FRowsTop + Max(Length(FStats), 2) * RowHeight + Pad;
  end;
  if Length(FStats) = 0 then
    PaintClean(FRowsTop);
  for i := 0 to High(FStats) do
    PaintRow(i, FRowsTop + i * RowHeight);
end;

procedure TGittanSummary.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(RowAt(Y));
end;

procedure TGittanSummary.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1);
end;

procedure TGittanSummary.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Row: integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  Row := RowAt(Y);
  if Row < 0 then
    Exit;
  if (Button = mbLeft) and Assigned(FOnSelectFile) then
    FOnSelectFile(Self, FStats[Row].Path)
  else if (Button = mbRight) and Assigned(FOnContextFile) then
    FOnContextFile(Self, FStats[Row].Path, ClientToScreen(Point(X, Y)));
end;

end.
