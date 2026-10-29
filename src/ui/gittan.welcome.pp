unit gittan.welcome;

{** The welcome view: what Gittan shows while no repository is open, and
  where a failure to open one is reported. Under the wordmark (the mark
  and the name, as gittan.app has them, drawn from
  icons/gittan-wordmark.svg in the view's colors; the title and the
  tagline as text when it cannot be drawn) it offers a button that opens the folder dialog, filled in the
  accent with the shortcut drawn as key caps inside it, one that clones a
  repository and one that makes a new one (the three in a row as wide as
  the column, or under each other when the row does not fit), says under
  them that a folder can be dropped, and lists the recent repositories
  as rows to click, each with its name and path; a repository whose folder
  is gone is listed dimmed, says so, and does not react. An error is shown in red
  under the name, wrapped to the column, so the next attempt is one click
  or one drop away. While a repository opens it shows only that, in place
  of the error, the buttons and the list.

  It paints itself in the editor's palette, like the summary, and sizes
  its height to its content so it can sit in the same TScrollBox: the
  block is centered while there is room and the box scrolls when there
  is not. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, BGRABitmap;

type
  {** A click on a recent repository, with its root. }
  TGittanOpenRecentEvent = procedure(Sender: TObject; const ARoot: string) of object;

  { TGittanWelcome }

  TGittanWelcome = class(TCustomControl)
  private
    FTitle, FTagline, FError, FShortcut, FBusy: string;
    FRecent: TStringList;
    { The wordmark drawn for the colors and the screen's pixels, made in
      the first paint after a change; FLogoFailed when it could not be. }
    FLogo: TBGRABitmap;
    FLogoFailed: boolean;
    FBack, FText, FDim, FHover, FLine, FErrorColor, FAccent: TColor;
    { What the mouse is over: hotNone, a button (hotButton less its
      index) or a row's index. }
    FHot: integer;
    FButtonRects: array[0..2] of TRect;
    FRowRects: array of TRect;
    FContentHeight: integer;
    FOnOpen, FOnClone, FOnInit: TNotifyEvent;
    FOnOpenRecent: TGittanOpenRecentEvent;
    function HotAt(X, Y: integer): integer;
    procedure SetHot(AValue: integer);
    function RecentMissing(AIndex: integer): boolean;
    function FitLeft(const AText: string; AMaxWidth: integer): string;
    function LogoBitmap(APixels: integer): TBGRABitmap;
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
    {** The recent repositories, most recent first; a copy is kept. }
    procedure SetRecent(ARoots: TStrings);
    {** The error shown under the title; empty shows none. }
    procedure SetError(const AMessage: string);
    {** What is being done (a repository opening), shown dim under the
      title in place of the error, the buttons and the recent
      repositories, which take no clicks meanwhile; empty shows them. }
    procedure SetBusy(const AMessage: string);
    {** The palette: the background, the text, the dim text, the hovered
      button or row, the line of the borders and the divider, and the
      error text. }
    procedure SetColors(ABack, AText, ADim, AHover, ALine, AError: TColor);
    {** The fill of the open button, the status bar's primary button's. }
    procedure SetAccent(AAccent: TColor);
    {** Makes the control at least AMin high (the height of the box it
      sits in, so its background covers the box), and no higher than its
      content needs beyond that. }
    procedure FitHeight(AMin: integer);
    {** The application name over the tagline, drawn when the wordmark
      cannot be. }
    property Title: string read FTitle write FTitle;
    {** The dim line under the title, with it. }
    property Tagline: string read FTagline write FTagline;
    {** The shortcut of the open button, drawn as key caps beside it. }
    property Shortcut: string read FShortcut write FShortcut;
    {** A click on the open button. }
    property OnOpen: TNotifyEvent read FOnOpen write FOnOpen;
    {** A click on the clone button. }
    property OnClone: TNotifyEvent read FOnClone write FOnClone;
    {** A click on the button that makes a new repository. }
    property OnInit: TNotifyEvent read FOnInit write FOnInit;
    {** A click on a recent repository. }
    property OnOpenRecent: TGittanOpenRecentEvent read FOnOpenRecent write FOnOpenRecent;
  end;

implementation

uses
  Math, LazUTF8, BGRABitmapTypes, BGRASVG, BGRACanvas2D, gittan.statusbar,
  gittan.textfit, gittan.theme;

const
  { icons/gittan-wordmark.svg, in its light colors. }
  WordmarkSvg = {$I gittan.wordmark.inc};
  WordmarkRed = '#E5484D';
  WordmarkGreen = '#2FA84F';
  WordmarkText = '#1F2937';
  { What a dark background takes in their place, as gittan.app has it;
    the name takes the view's text color in both. }
  WordmarkDarkRed = '#FF6B70';
  WordmarkDarkGreen = '#4ADE80';

resourcestring
  rsOpenButton = 'Open Repository…';
  rsCloneButton = 'Clone…';
  rsInitButton = 'Init…';
  rsRecent = 'Recent';
  rsNotFound = 'not found';
  rsDrop = 'or drop a folder or file here';

const
  hotNone = -1;
  hotButton = -2;
  Pad = 24;
  Gap = 12;
  ColumnWidth = 480;
  LogoWidth = 340;
  TitleFontSize = 20;
  ButtonPadX = 16;
  ButtonPadY = 8;
  ButtonGap = 8;
  ButtonRound = 10;
  RecentGap = 36;
  KeyPadX = 5;
  KeyPadY = 2;
  RowHeight = 44;
  RowPadX = 10;
  FolderSize = 16;

{ TGittanWelcome }

constructor TGittanWelcome.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FRecent := TStringList.Create;
  FHot := hotNone;
  Align := alTop;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnShadow, clRed);
  FAccent := clHighlight;
end;

destructor TGittanWelcome.Destroy;
begin
  FLogo.Free;
  FRecent.Free;
  inherited Destroy;
end;

procedure TGittanWelcome.SetRecent(ARoots: TStrings);
begin
  FRecent.Assign(ARoots);
  { The rows of the last paint are not these. }
  FRowRects := nil;
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

procedure TGittanWelcome.SetBusy(const AMessage: string);
begin
  if FBusy = AMessage then
    Exit;
  FBusy := AMessage;
  FHot := hotNone;
  Cursor := crDefault;
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
  FreeAndNil(FLogo);
  FLogoFailed := False;
  Color := ABack;
  Invalidate;
end;

procedure TGittanWelcome.SetAccent(AAccent: TColor);
begin
  FAccent := AAccent;
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
  if FBusy <> '' then
    Exit(hotNone);
  P := Point(X, Y);
  for i := 0 to High(FButtonRects) do
    if PtInRect(FButtonRects[i], P) then
      Exit(hotButton - i);
  for i := 0 to High(FRowRects) do
    if (i < FRecent.Count) and PtInRect(FRowRects[i], P) and not RecentMissing(i) then
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
begin
  Result := FitTextLeft(Canvas, AText, AMaxWidth);
end;

function HexColor(AColor: TColor): string;
var
  C: TColor;
begin
  C := ColorToRGB(AColor);
  Result := Format('#%.2x%.2x%.2x', [Red(C), Green(C), Blue(C)]);
end;

{ The wordmark APixels wide in the view's colors, kept until the colors
  or the width change; nil when BGRASVG could not draw it. }
function TGittanWelcome.LogoBitmap(APixels: integer): TBGRABitmap;
var
  Source: string;
  Svg: TBGRASVG;
  C2d: TBGRACanvas2D;
  Size: TPointF;
  C: TColor;
begin
  if (FLogo <> nil) and (FLogo.Width = APixels) then
    Exit(FLogo);
  FreeAndNil(FLogo);
  if FLogoFailed then
    Exit(nil);
  Source := StringReplace(WordmarkSvg, WordmarkText, HexColor(FText), [rfReplaceAll]);
  C := ColorToRGB(FBack);
  if Red(C) * 299 + Green(C) * 587 + Blue(C) * 114 < 128000 then
  begin
    Source := StringReplace(Source, WordmarkRed, WordmarkDarkRed, [rfReplaceAll]);
    Source := StringReplace(Source, WordmarkGreen, WordmarkDarkGreen, [rfReplaceAll]);
  end;
  Svg := nil;
  try
    try
      Svg := TBGRASVG.CreateFromString(Source);
      Size := Svg.ViewSizeInUnit[cuPixel];
      FLogo := TBGRABitmap.Create(APixels, Max(1, Round(APixels * Size.Y / Size.X)));
      C2d := TBGRACanvas2D.Create(FLogo);
      try
        Svg.StretchDraw(C2d, 0, 0, FLogo.Width, FLogo.Height, True);
      finally
        C2d.Free;
      end;
    except
      FreeAndNil(FLogo);
      FLogoFailed := True;
    end;
  finally
    Svg.Free;
  end;
  Result := FLogo;
end;

{ The error broken into lines no wider than AWidth with the canvas font:
  at spaces, and inside a word too wide for a line (a path, mostly)
  after a slash, or anywhere when there is no slash either. }
procedure TGittanWelcome.WrapError(AWidth: integer; ALines: TStrings);
var
  Line, Word, Head: string;
  i, Best: integer;
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
      { The longest head that fits, of whole characters, ending after
        a slash when one is there; a head of at least one character, so
        the loop ends. }
      Head := UTF8Copy(Line, 1, FittingChars(Canvas, Line, UTF8Length(Line), AWidth));
      Best := LastDelimiter('/', Head);
      if Best = 0 then
        Best := Length(Head);
      ALines.Add(Copy(Line, 1, Best));
      Line := Copy(Line, Best + 1, MaxInt);
    end;
  end;
  if Line <> '' then
    ALines.Add(Line);
end;

procedure TGittanWelcome.Paint;
var
  ColLeft, ColWidth, Y, BlockTop, Total, LineHeight, TitleHeight, ErrHeight: integer;
  KeyWidth, X, TextY, i, RowWidth, ButtonHeight, ButtonRows, Spare: integer;
  ButtonWidths: array[0..2] of integer;
  Captions: array[0..2] of string;
  Stacked: boolean;
  R: TRect;
  RepoName, Path: string;
  Missing: boolean;
  ErrLines: TStringList;
  Fill, Ink: TColor;
  Logo: TBGRABitmap;
  LogoHeight: integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  LineHeight := Canvas.TextHeight('Xg');
  ColWidth := Min(Px(ColumnWidth), Width - 2 * Px(Pad));
  ColLeft := (Width - ColWidth) div 2;
  { The wordmark in the screen's pixels (twice its points on a Retina
    screen), which Cocoa then draws pixel for pixel. }
  Logo := LogoBitmap(Round(Px(LogoWidth) * GetCanvasScaleFactor));
  LogoHeight := 0;
  if Logo <> nil then
    LogoHeight := Px(LogoWidth) * Logo.Height div Logo.Width;

  { The block's height first, to place it: a little above the middle
    of the room, which looks centered, and never off the top. }
  Canvas.Font.Size := TitleFontSize;
  Canvas.Font.Style := [fsBold];
  TitleHeight := Canvas.TextHeight('Xg');
  Canvas.Font.Size := Font.Size;
  { The buttons as wide as the column, the open button taking what the
    others leave, its shortcut drawn as a key cap inside it at the right;
    under each other, each as wide as the column, when their row does
    not fit. The captions are bold, as the status bar's primary
    button's is, and measured so. }
  Captions[0] := rsOpenButton;
  Captions[1] := rsCloneButton;
  Captions[2] := rsInitButton;
  KeyWidth := 0;
  if FShortcut <> '' then
    KeyWidth := Canvas.TextWidth(FShortcut) + 2 * Px(KeyPadX);
  RowWidth := 2 * Px(ButtonGap);
  for i := 0 to High(Captions) do
  begin
    ButtonWidths[i] := Canvas.TextWidth(Captions[i]) + 2 * Px(ButtonPadX);
    if (i = 0) and (KeyWidth > 0) then
      Inc(ButtonWidths[i], Px(Gap) + KeyWidth);
    Inc(RowWidth, ButtonWidths[i]);
  end;
  Canvas.Font.Style := [];
  Stacked := RowWidth > ColWidth;
  if Stacked then
    for i := 0 to High(Captions) do
      ButtonWidths[i] := ColWidth
  else
    Inc(ButtonWidths[0], ColWidth - RowWidth);
  ButtonHeight := LineHeight + 2 * Px(ButtonPadY);
  if Stacked then
    ButtonRows := Length(Captions)
  else
    ButtonRows := 1;
  { The wordmark's small caps line needs more room under it than the
    tagline does. }
  if Logo <> nil then
    Total := LogoHeight + Px(Gap)
  else
  begin
    Total := TitleHeight + 2;
    if FTagline <> '' then
      Inc(Total, LineHeight);
  end;
  ErrHeight := 0;
  ErrLines := TStringList.Create;
  try
    if FBusy <> '' then
      Inc(Total, Px(Pad) + LineHeight)
    else
    begin
      if FError <> '' then
      begin
        WrapError(ColWidth, ErrLines);
        ErrHeight := ErrLines.Count * LineHeight;
        Inc(Total, Px(Gap) + ErrHeight);
      end;
      Inc(Total, Px(Pad) + ButtonRows * ButtonHeight + (ButtonRows - 1) * Px(ButtonGap));
      Inc(Total, Px(Gap) + LineHeight);
      if FRecent.Count > 0 then
        Inc(Total, Px(RecentGap) + LineHeight + Px(Gap) div 2 + 1 + Px(Gap) div 2 +
          FRecent.Count * Px(RowHeight));
    end;
    FContentHeight := Total + 2 * Px(Pad);
    if Height < FContentHeight then
    begin
      Height := Max(FContentHeight, Constraints.MinHeight);
      Exit;
    end;
    BlockTop := Max(Px(Pad), (Height - Total) * 2 div 5);
    Y := BlockTop;

    if Logo <> nil then
    begin
      Logo.Draw(Canvas, Rect((Width - Px(LogoWidth)) div 2, Y,
        (Width + Px(LogoWidth)) div 2, Y + LogoHeight), False);
      Inc(Y, LogoHeight + Px(Gap));
    end
    else
    begin
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
    end;

    if FBusy <> '' then
    begin
      for i := 0 to High(FButtonRects) do
        FButtonRects[i] := Rect(0, 0, 0, 0);
      FRowRects := nil;
      Inc(Y, Px(Pad));
      Canvas.Font.Color := FDim;
      Canvas.TextOut((Width - Canvas.TextWidth(FBusy)) div 2, Y, FBusy);
      Exit;
    end;

    if FError <> '' then
    begin
      Inc(Y, Px(Gap));
      Canvas.Font.Color := FErrorColor;
      for i := 0 to ErrLines.Count - 1 do
        Canvas.TextOut((Width - Canvas.TextWidth(ErrLines[i])) div 2,
          Y + i * LineHeight, ErrLines[i]);
      Inc(Y, ErrHeight);
    end;

    { The buttons: the open button filled in the accent, the others
      outlined; each caption centered in its button, the open one's in
      what the key cap leaves. }
    Inc(Y, Px(Pad));
    X := ColLeft;
    for i := 0 to High(Captions) do
    begin
      FButtonRects[i] := Rect(X, Y, X + ButtonWidths[i], Y + ButtonHeight);
      R := FButtonRects[i];
      if i = 0 then
      begin
        Fill := FAccent;
        if FHot = hotButton then
          Fill := MixColor(Fill, FText, 0.12);
        Canvas.Pen.Style := psClear;
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := Fill;
        Canvas.RoundRect(R, Px(ButtonRound), Px(ButtonRound));
        Canvas.Pen.Style := psSolid;
        Ink := clWhite;
      end
      else
      begin
        Canvas.Pen.Color := FLine;
        if FHot = hotButton - i then
        begin
          Canvas.Brush.Style := bsSolid;
          Canvas.Brush.Color := FHover;
        end
        else
          Canvas.Brush.Style := bsClear;
        Canvas.RoundRect(R, Px(ButtonRound), Px(ButtonRound));
        Ink := FText;
      end;
      Canvas.Brush.Style := bsClear;
      Spare := R.Right;
      TextY := Y + Px(ButtonPadY);
      if (i = 0) and (FShortcut <> '') then
      begin
        { The shortcut as a key cap: a small rounded frame in a paler
          shade of the fill. }
        Spare := R.Right - Px(ButtonPadX) - KeyWidth;
        Canvas.Pen.Color := MixColor(FAccent, clWhite, 0.45);
        Canvas.RoundRect(Spare, TextY - Px(KeyPadY), R.Right - Px(ButtonPadX),
          TextY + LineHeight + Px(KeyPadY), Px(6), Px(6));
        Canvas.Font.Color := MixColor(FAccent, clWhite, 0.8);
        Canvas.TextOut(Spare + Px(KeyPadX), TextY, FShortcut);
        Dec(Spare, Px(Gap));
      end;
      Canvas.Font.Style := [fsBold];
      Canvas.Font.Color := Ink;
      Canvas.TextOut(R.Left + (Spare - R.Left - Canvas.TextWidth(Captions[i])) div 2,
        TextY, Captions[i]);
      Canvas.Font.Style := [];
      if Stacked then
      begin
        if i < High(Captions) then
          Inc(Y, ButtonHeight + Px(ButtonGap));
      end
      else
        X := R.Right + Px(ButtonGap);
    end;
    Inc(Y, ButtonHeight);

    { What else opens a repository, dim under the buttons. }
    Inc(Y, Px(Gap));
    Canvas.Font.Color := FDim;
    Canvas.TextOut((Width - Canvas.TextWidth(rsDrop)) div 2, Y, rsDrop);
    Inc(Y, LineHeight);

    { The recent repositories: a dim heading over a divider, then a row
      per repository with the folder, the name and the path, and "not
      found" at the right of the name's line when the folder is gone. }
    SetLength(FRowRects, FRecent.Count);
    if FRecent.Count > 0 then
    begin
      Inc(Y, Px(RecentGap));
      Canvas.Font.Color := FDim;
      Canvas.TextOut(ColLeft, Y, rsRecent);
      Inc(Y, LineHeight + Px(Gap) div 2);
      Canvas.Pen.Color := FLine;
      Canvas.Line(ColLeft, Y, ColLeft + ColWidth, Y);
      Inc(Y, 1 + Px(Gap) div 2);
      for i := 0 to FRecent.Count - 1 do
      begin
        FRowRects[i] := Rect(ColLeft - Px(RowPadX), Y, ColLeft + ColWidth + Px(RowPadX), Y + Px(RowHeight));
        Missing := RecentMissing(i);
        if FHot = i then
        begin
          Canvas.Pen.Style := psClear;
          Canvas.Brush.Style := bsSolid;
          Canvas.Brush.Color := FHover;
          Canvas.RoundRect(FRowRects[i], Px(ButtonRound), Px(ButtonRound));
          Canvas.Pen.Style := psSolid;
          Canvas.Brush.Style := bsClear;
        end;
        DrawStatusIcon(Canvas, HintFolder, ColLeft, Y + (Px(RowHeight) - Px(FolderSize)) div 2,
          Px(FolderSize), FDim);
        Canvas.Brush.Style := bsClear;
        X := ColLeft + Px(FolderSize) + Px(Gap);
        RepoName := ExtractFileName(ExcludeTrailingPathDelimiter(FRecent[i]));
        Path := FRecent[i];
        TextY := Y + (Px(RowHeight) - 2 * LineHeight) div 2;
        Spare := ColLeft + ColWidth;
        Canvas.Font.Color := FDim;
        if Missing then
        begin
          Dec(Spare, Canvas.TextWidth(rsNotFound));
          Canvas.TextOut(Spare, TextY, rsNotFound);
          Dec(Spare, Px(Gap));
        end
        else
          Canvas.Font.Color := FText;
        Canvas.TextOut(X, TextY, FitTextRight(Canvas, RepoName, Spare - X));
        Canvas.Font.Color := FDim;
        Canvas.TextOut(X, TextY + LineHeight, FitLeft(Path, ColLeft + ColWidth - X));
        Inc(Y, Px(RowHeight));
      end;
    end;
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
  else if (Hit = hotButton - 1) and Assigned(FOnClone) then
    FOnClone(Self)
  else if (Hit = hotButton - 2) and Assigned(FOnInit) then
    FOnInit(Self)
  else if (Hit >= 0) and Assigned(FOnOpenRecent) then
    FOnOpenRecent(Self, FRecent[Hit]);
end;

end.
