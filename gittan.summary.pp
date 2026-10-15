unit gittan.summary;

{** The repository summary: what Gittan shows when a repository is opened,
  before a file is picked. It lists the changed files with their added and
  deleted line counts and a bar that compares the sizes of the changes,
  under a header with the repository name, branch and totals.

  It paints itself so it matches the editor's palette in both themes. It
  sizes its height to its content and is meant to sit in a TScrollBox,
  which provides the native scrolling. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, ImgList, gittan.git, gittan.icons;

type
  TGittanSelectFileEvent = procedure(Sender: TObject; const APath: string) of object;
  {** A right click on a file's row, with the mouse position in screen
    coordinates for a popup menu. }
  TGittanContextFileEvent = procedure(Sender: TObject; const APath: string;
    const AScreenPos: TPoint) of object;
  {** A click on the branch in the header, with its rectangle in screen
    coordinates for a popup to drop down from. }
  TGittanBranchClickEvent = procedure(Sender: TObject; const AScreenRect: TRect) of object;

  { TGittanSummary }

  TGittanSummary = class(TCustomControl)
  private
    FRepoName, FBranch, FBase, FSelected, FNotice: string;
    FStats: TGittanFileStats;
    FImages: TCustomImageList;
    FIconIndex: array of integer;
    FHot: integer;
    FBack, FText, FDim, FHover, FSelectedBack, FAdded, FDeleted, FLine: TColor;
    FOnSelectFile: TGittanSelectFileEvent;
    FOnContextFile: TGittanContextFileEvent;
    FOnBranchClick: TGittanBranchClickEvent;
    FRowsTop: integer;
    { The height the content needs; the control is at least as high as
      the box it fills, see FitHeight. }
    FContentHeight: integer;
    { The branch's chip in the header, in client coordinates; empty
      without a branch. }
    FBranchRect: TRect;
    FBranchHot: boolean;
    function BranchClickable: boolean;
    procedure SetBranchHot(AValue: boolean);
    function RowAt(Y: integer): integer;
    procedure SetHot(AValue: integer);
    procedure SetSelected(const AValue: string);
    procedure SetNotice(const AValue: string);
    procedure UpdateHeight;
    procedure PaintNotice(var Y: integer);
    procedure PaintClean(Y: integer);
    procedure PaintHeader(var Y: integer);
    procedure PaintRow(AIndex, ATop: integer);
    procedure PaintBar(X, Y: integer; const AStat: TGittanFileStat; AMax: integer);
    procedure PaintKinds(Y, ALeft, ARight: integer);
    function BarWidth: integer;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    constructor Create(AOwner: TComponent); override;
    {** Shows the changed files AStats of repository AName on ABranch,
      with ABase saying what is compared, as it is to be shown ("vs
      main", "main...feature"; empty for the usual HEAD); AIcons holds
      the image index in Images of each file's badge. }
    procedure SetRepository(const AName, ABranch, ABase: string;
      const AStats: TGittanFileStats; const AIcons: array of integer);
    {** Sets the palette: the background, the text, the dim text for paths
      and counts, the hovered row, the selected row, the added and deleted
      colors, and the line color for the divider and the empty part of a
      bar. }
    procedure SetColors(ABack, AText, ADim, AHover, ASelected, AAdded,
      ADeleted, ALine: TColor);
    {** Makes the control at least AMin high (the height of the box it
      sits in, so its background covers the box), and no higher than
      its content needs beyond that: a minimum constraint alone would
      leave it at an old, larger height when the box shrinks, and the
      box would scroll. }
    procedure FitHeight(AMin: integer);
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
    {** A click on the branch in the header. While it is set the branch
      is drawn as a chip with a chevron, highlighted under the mouse. }
    property OnBranchClick: TGittanBranchClickEvent read FOnBranchClick write FOnBranchClick;
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
  { The count of each kind in the header, after a dot in its color. }
  KindCount: array[TGittanChangeKind] of string = ('%d modified', '%d added',
    '%d deleted', '%d renamed', '%d untracked', '%d conflicted');
  Pad = 24;
  RowHeight = 30;
  IconSize = 16;
  { The row bars take a share of the width, within these. }
  MinBarWidth = 96;
  MaxBarWidth = 200;
  TotalBarWidth = 140;
  BarHeight = 6;
  DotSize = 8;
  CountWidth = 56;
  Gap = 12;
  TitleFontSize = 20;
  CheckSize = 20;
  ChipPadX = 6;
  ChipPadY = 3;
  ChevronWidth = 14;

{ TGittanSummary }

constructor TGittanSummary.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FHot := -1;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnFace, clGreen,
    clRed, clBtnShadow);
  { The height follows the content; the scroll box it sits in scrolls. }
  Align := alTop;
  UpdateHeight;
end;

procedure TGittanSummary.SetRepository(const AName, ABranch, ABase: string;
  const AStats: TGittanFileStats; const AIcons: array of integer);
var
  i: integer;
begin
  FRepoName := AName;
  FBranch := ABranch;
  FBase := ABase;
  FStats := Copy(AStats);
  SetLength(FIconIndex, Length(AIcons));
  for i := 0 to High(AIcons) do
    FIconIndex[i] := AIcons[i];
  FHot := -1;
  UpdateHeight;
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
  FContentHeight := FRowsTop + Max(Length(FStats), 2) * RowHeight + Pad;
  Height := Max(FContentHeight, Constraints.MinHeight);
end;

procedure TGittanSummary.FitHeight(AMin: integer);
begin
  Constraints.MinHeight := AMin;
  Height := Max(FContentHeight, AMin);
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
  UpdateHeight;
  Invalidate;
end;

function TGittanSummary.BranchClickable: boolean;
begin
  Result := Assigned(FOnBranchClick) and (FBranch <> '');
end;

procedure TGittanSummary.SetBranchHot(AValue: boolean);
begin
  if FBranchHot = AValue then
    Exit;
  FBranchHot := AValue;
  if AValue then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  Invalidate;
end;

function TGittanSummary.RowAt(Y: integer): integer;
begin
  Result := -1;
  if Y < FRowsTop then
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
  X, TitleHeight, BodyHeight, TextY, Added, Deleted, i: integer;
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
  FBranchRect := Rect(0, 0, 0, 0);
  if FBranch <> '' then
  begin
    Heading := Format(rsOnBranch, [FBranch]);
    TextY := Y + TitleHeight - BodyHeight - 3;
    if BranchClickable then
    begin
      { A chip with a chevron, so the branch reads as something to
        click; filled while the mouse is over it. }
      FBranchRect := Rect(X - ChipPadX, TextY - ChipPadY,
        X + Canvas.TextWidth(Heading) + ChevronWidth + ChipPadX, TextY + BodyHeight + ChipPadY);
      if FBranchHot then
      begin
        Canvas.Pen.Style := psClear;
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := FHover;
        Canvas.RoundRect(FBranchRect, 8, 8);
        Canvas.Pen.Style := psSolid;
        Canvas.Brush.Style := bsClear;
        Canvas.Font.Color := FText;
      end;
      Canvas.TextOut(X, TextY, Heading);
      Inc(X, Canvas.TextWidth(Heading) + ChevronWidth div 2);
      Canvas.Pen.Color := Canvas.Font.Color;
      Canvas.Polyline([Point(X - 3, TextY + BodyHeight div 2 - 1),
        Point(X, TextY + BodyHeight div 2 + 2), Point(X + 3, TextY + BodyHeight div 2 - 1)]);
      Inc(X, ChevronWidth div 2 + ChipPadX + Gap);
      Canvas.Font.Color := FDim;
    end
    else
    begin
      Canvas.TextOut(X, TextY, Heading);
      Inc(X, Canvas.TextWidth(Heading) + Gap);
    end;
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
    Heading := '−' + IntToStr(Deleted);
    Canvas.TextOut(X, Y, Heading);
    Inc(X, Canvas.TextWidth(Heading) + Gap);
    { The whole change as one bar: the added share in green, the
      deleted in red. }
    if Added + Deleted > 0 then
    begin
      Canvas.Pen.Style := psClear;
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := FDeleted;
      Canvas.RoundRect(X, Y + (BodyHeight - BarHeight) div 2, X + TotalBarWidth,
        Y + (BodyHeight + BarHeight) div 2, BarHeight, BarHeight);
      if Added > 0 then
      begin
        Canvas.Brush.Color := FAdded;
        Canvas.RoundRect(X, Y + (BodyHeight - BarHeight) div 2,
          X + Max(BarHeight, Round(Added / (Added + Deleted) * TotalBarWidth)),
          Y + (BodyHeight + BarHeight) div 2, BarHeight, BarHeight);
      end;
      Canvas.Pen.Style := psSolid;
      Canvas.Brush.Style := bsClear;
      Inc(X, TotalBarWidth + Gap);
    end;
    PaintKinds(Y, X, Width - Pad);
  end;
  Inc(Y, BodyHeight + Pad div 2);
  Canvas.Pen.Color := FLine;
  Canvas.Line(Pad, Y, Width - Pad, Y);
  Inc(Y, Pad div 2);
end;

{ How many files of each kind, as a dot in the kind's color and a dim
  count, right-aligned at ARight on the line at Y; left out when they
  would not fit between ALeft and ARight. }
procedure TGittanSummary.PaintKinds(Y, ALeft, ARight: integer);
var
  Counts: array[TGittanChangeKind] of integer;
  Kind: TGittanChangeKind;
  i, X, BodyHeight, Total: integer;
  KindText: string;
begin
  for Kind := Low(Kind) to High(Kind) do
    Counts[Kind] := 0;
  for i := 0 to High(FStats) do
    Inc(Counts[FStats[i].Kind]);
  Canvas.Font.Color := FDim;
  BodyHeight := Canvas.TextHeight('Xg');
  Total := 0;
  for Kind := Low(Kind) to High(Kind) do
    if Counts[Kind] > 0 then
      Inc(Total, DotSize + Gap div 2 + Canvas.TextWidth(Format(KindCount[Kind],
        [Counts[Kind]])) + Gap);
  Dec(Total, Gap);
  if (Total <= 0) or (ALeft + Total > ARight) then
    Exit;
  X := ARight - Total;
  for Kind := Low(Kind) to High(Kind) do
    if Counts[Kind] > 0 then
    begin
      Canvas.Pen.Style := psClear;
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := KindColor(Kind);
      Canvas.Ellipse(X, Y + (BodyHeight - DotSize) div 2, X + DotSize,
        Y + (BodyHeight + DotSize) div 2);
      Canvas.Pen.Style := psSolid;
      Canvas.Brush.Style := bsClear;
      Inc(X, DotSize + Gap div 2);
      KindText := Format(KindCount[Kind], [Counts[Kind]]);
      Canvas.TextOut(X, Y, KindText);
      Inc(X, Canvas.TextWidth(KindText) + Gap);
    end;
end;

{ The bars of the rows share the width: a sixth of it, within bounds. }
function TGittanSummary.BarWidth: integer;
begin
  Result := Min(MaxBarWidth, Max(MinBarWidth, Width div 6));
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
  Y := Pad;
  PaintHeader(Y);
  if FNotice <> '' then
    PaintNotice(Y);
  if Y <> FRowsTop then
  begin
    FRowsTop := Y;
    FContentHeight := FRowsTop + Max(Length(FStats), 2) * RowHeight + Pad;
    Height := Max(FContentHeight, Constraints.MinHeight);
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
  SetBranchHot(BranchClickable and PtInRect(FBranchRect, Point(X, Y)));
end;

procedure TGittanSummary.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1);
  SetBranchHot(False);
end;

procedure TGittanSummary.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Row: integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button = mbLeft) and BranchClickable and PtInRect(FBranchRect, Point(X, Y)) then
  begin
    FOnBranchClick(Self, Rect(ClientToScreen(FBranchRect.TopLeft).X,
      ClientToScreen(FBranchRect.TopLeft).Y, ClientToScreen(FBranchRect.BottomRight).X,
      ClientToScreen(FBranchRect.BottomRight).Y));
    Exit;
  end;
  Row := RowAt(Y);
  if Row < 0 then
    Exit;
  if (Button = mbLeft) and Assigned(FOnSelectFile) then
    FOnSelectFile(Self, FStats[Row].Path)
  else if (Button = mbRight) and Assigned(FOnContextFile) then
    FOnContextFile(Self, FStats[Row].Path, ClientToScreen(Point(X, Y)));
end;

end.
