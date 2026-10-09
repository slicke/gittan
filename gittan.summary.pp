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
  Classes, SysUtils, Controls, Graphics, ImgList, gittan.git;

type
  TGittanSelectFileEvent = procedure(Sender: TObject; const APath: string) of object;

  { TGittanSummary }

  TGittanSummary = class(TCustomControl)
  private
    FRepoName, FBranch, FMessage: string;
    FStats: TGittanFileStats;
    FImages: TCustomImageList;
    FIconIndex: array of integer;
    FHot: integer;
    FBack, FText, FDim, FHover, FAdded, FDeleted, FLine: TColor;
    FOnSelectFile: TGittanSelectFileEvent;
    FRowsTop: integer;
    function RowAt(Y: integer): integer;
    procedure SetHot(AValue: integer);
    procedure UpdateHeight;
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
    {** Shows the changed files AStats of repository AName on ABranch;
      AIcons holds the image index in Images of each file's badge. }
    procedure SetRepository(const AName, ABranch: string;
      const AStats: TGittanFileStats; const AIcons: array of integer);
    {** Shows AMessage alone, centered: the view with no repository. }
    procedure SetMessage(const AMessage: string);
    {** Sets the palette: the background, the text, the dim text for paths
      and counts, the hovered row, the added and deleted colors, and the
      line color for the divider and the empty part of a bar. }
    procedure SetColors(ABack, AText, ADim, AHover, AAdded, ADeleted, ALine: TColor);
    {** The image list the file badges come from. }
    property Images: TCustomImageList read FImages write FImages;
    {** A click on a file's row. }
    property OnSelectFile: TGittanSelectFileEvent read FOnSelectFile write FOnSelectFile;
  end;

implementation

uses
  Math;

resourcestring
  rsOnBranch = 'on %s';
  rsOneFile = '1 changed file';
  rsManyFiles = '%d changed files';
  rsNoChanges = 'No changes';
  rsBinary = 'binary';

const
  Pad = 24;
  RowHeight = 28;
  IconSize = 16;
  BarWidth = 96;
  BarHeight = 6;
  CountWidth = 56;
  Gap = 12;
  TitleFontSize = 20;

{ TGittanSummary }

constructor TGittanSummary.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FHot := -1;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clGreen, clRed, clBtnShadow);
  SetMessage('');
end;

procedure TGittanSummary.SetRepository(const AName, ABranch: string;
  const AStats: TGittanFileStats; const AIcons: array of integer);
var
  i: integer;
begin
  FRepoName := AName;
  FBranch := ABranch;
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

procedure TGittanSummary.SetMessage(const AMessage: string);
begin
  FMessage := AMessage;
  FStats := nil;
  FIconIndex := nil;
  FHot := -1;
  { The message is centered in whatever room the scroll box has. }
  Align := alClient;
  Invalidate;
end;

procedure TGittanSummary.SetColors(ABack, AText, ADim, AHover, AAdded, ADeleted,
  ALine: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
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
  Height := FRowsTop + Length(FStats) * RowHeight + Pad;
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
    Canvas.TextOut(X, Y + TitleHeight - BodyHeight - 3, Format(rsOnBranch, [FBranch]));
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
  if AIndex = FHot then
  begin
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FHover;
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

procedure TGittanSummary.Paint;
var
  Y, i: integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  if FMessage <> '' then
  begin
    Canvas.Font := Font;
    Canvas.Font.Color := FDim;
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut((Width - Canvas.TextWidth(FMessage)) div 2,
      (Height - Canvas.TextHeight(FMessage)) div 2, FMessage);
    Exit;
  end;
  Y := Pad;
  PaintHeader(Y);
  if Y <> FRowsTop then
  begin
    FRowsTop := Y;
    Height := FRowsTop + Length(FStats) * RowHeight + Pad;
  end;
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
  if (Button = mbLeft) and (Row >= 0) and Assigned(FOnSelectFile) then
    FOnSelectFile(Self, FStats[Row].Path);
end;

end.
