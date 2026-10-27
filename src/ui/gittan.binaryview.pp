unit gittan.binaryview;

{** The view of a binary file, which has no text to show: a page with
  the file's extension on it, "Binary file" under it and the size, in
  the change view the size before and after (or that the file is new or
  deleted), in the middle of the view.

  It paints itself in colors the form sets, like the image view. The
  page is drawn on the canvas, not on a bitmap, so it stays sharp on a
  Retina screen. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics;

type

  { TGittanBinaryView }

  TGittanBinaryView = class(TCustomControl)
  private
    FExt, FDetail, FNote: string;
    FBack, FText, FDim, FPage: TColor;
  protected
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    {** A changed file APath: AHasOld and AHasNew say which versions
      there are, AOldSize and ANewSize their sizes in bytes. }
    procedure SetChange(const APath: string; AHasOld, AHasNew: boolean;
      AOldSize, ANewSize: int64);
    {** A file opened by itself, of ASize bytes. }
    procedure SetFile(const APath: string; ASize: int64);
    {** A line under the size, such as that the file is not downloaded
      from Git LFS; SetChange and SetFile clear it. }
    procedure SetNote(const ANote: string);
    {** The palette: the background, the title, the details and the
      page's outline, and the page's fill. }
    procedure SetColors(ABack, AText, ADim, APage: TColor);
  end;

implementation

uses
  Math, gittan.imagediff;

resourcestring
  rsBinaryFile = 'Binary file';
  rsNewFile = 'New file · %s';
  rsDeletedFile = 'Deleted · %s';
  rsSizeChange = '%s → %s';
  rsSameSize = '%s, same size';

const
  PageW = 56;
  PageH = 72;
  Fold = 16;
  Gap = 12;

{ The extension in capitals for the page, BIN without one. }
function PageLabel(const APath: string): string;
begin
  Result := UpperCase(Copy(ExtractFileExt(APath), 2, MaxInt));
  if (Result = '') or (Length(Result) > 5) then
    Result := 'BIN';
end;

{ TGittanBinaryView }

constructor TGittanBinaryView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace);
end;

procedure TGittanBinaryView.SetChange(const APath: string; AHasOld, AHasNew: boolean;
  AOldSize, ANewSize: int64);
begin
  FExt := PageLabel(APath);
  if AHasOld and AHasNew then
  begin
    if AOldSize = ANewSize then
      FDetail := Format(rsSameSize, [ByteSize(ANewSize)])
    else
      FDetail := Format(rsSizeChange, [ByteSize(AOldSize), ByteSize(ANewSize)]);
  end
  else if AHasNew then
    FDetail := Format(rsNewFile, [ByteSize(ANewSize)])
  else if AHasOld then
    FDetail := Format(rsDeletedFile, [ByteSize(AOldSize)])
  else
    FDetail := '';
  FNote := '';
  Invalidate;
end;

procedure TGittanBinaryView.SetFile(const APath: string; ASize: int64);
begin
  FExt := PageLabel(APath);
  FDetail := ByteSize(ASize);
  FNote := '';
  Invalidate;
end;

procedure TGittanBinaryView.SetNote(const ANote: string);
begin
  FNote := ANote;
  Invalidate;
end;

procedure TGittanBinaryView.SetColors(ABack, AText, ADim, APage: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FPage := APage;
  Invalidate;
end;

procedure TGittanBinaryView.Paint;
var
  LineH, Total, X, Y, W: integer;
  Page: array[0..4] of TPoint;
  FoldPts: array[0..2] of TPoint;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  LineH := Canvas.TextHeight('Xg');
  { The page, the title and the detail, centered as a block. }
  Total := PageH + Gap + LineH + LineH div 2 + LineH;
  if FNote <> '' then
    Inc(Total, LineH + LineH div 4);
  X := (ClientWidth - PageW) div 2;
  Y := Max(0, (ClientHeight - Total) div 2);
  { A page with its top right corner folded down. }
  Page[0] := Point(X, Y);
  Page[1] := Point(X + PageW - Fold, Y);
  Page[2] := Point(X + PageW, Y + Fold);
  Page[3] := Point(X + PageW, Y + PageH);
  Page[4] := Point(X, Y + PageH);
  Canvas.Pen.Color := FDim;
  Canvas.Pen.Width := 1;
  Canvas.Brush.Color := FPage;
  Canvas.Polygon(Page);
  FoldPts[0] := Point(X + PageW - Fold, Y);
  FoldPts[1] := Point(X + PageW - Fold, Y + Fold);
  FoldPts[2] := Point(X + PageW, Y + Fold);
  Canvas.Brush.Color := FBack;
  Canvas.Polygon(FoldPts);
  { The extension on the lower half of the page. }
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FDim;
  W := Canvas.TextWidth(FExt);
  Canvas.TextOut(X + (PageW - W) div 2, Y + PageH - LineH - LineH div 2, FExt);
  { The title and the detail. }
  Y := Y + PageH + Gap;
  Canvas.Font.Color := FText;
  W := Canvas.TextWidth(rsBinaryFile);
  Canvas.TextOut((ClientWidth - W) div 2, Y, rsBinaryFile);
  Canvas.Font.Style := [];
  Canvas.Font.Color := FDim;
  W := Canvas.TextWidth(FDetail);
  Canvas.TextOut((ClientWidth - W) div 2, Y + LineH + LineH div 2, FDetail);
  if FNote <> '' then
  begin
    W := Canvas.TextWidth(FNote);
    Canvas.TextOut((ClientWidth - W) div 2, Y + 2 * LineH + LineH div 2 + LineH div 4, FNote);
  end;
end;

procedure TGittanBinaryView.Resize;
begin
  inherited Resize;
  Invalidate;
end;

end.
