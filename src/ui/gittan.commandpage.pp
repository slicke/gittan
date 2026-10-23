unit gittan.commandpage;

{** The Commands page: the repository's own commands as tiles, grouped
  by where they come from (gittan.repocommands): the commands file,
  the scripts of package.json and the targets of a Makefile. A tile
  has the command's name, under it what runs dimmed, and at the right
  its shortcut as a chip; it fills under the mouse and a click raises
  OnRun with its index. A section of the file that names no script or
  target is a dimmed tile that says so and leads nowhere. Each group's heading names its file, and the
  first's offers Edit… or Create… (OnEditFile). While the commands
  file is not trusted its commands are dimmed under a card that says
  why, with a Trust Commands button (OnTrust).

  Under the groups, once a command has run, the Output section names it
  and its state (running, the exit code and the time, stopped, could
  not start) with Stop while it runs, else Copy, over a console
  (TGittanConsole, Console, the owner's to fill and to give the
  editor's font) that fills the rest of the box it sits in, at least
  ConsoleMinHeight.

  It paints itself in the editor's palette, like the Repository page,
  and sizes its height to its content so it can sit in the same
  TScrollBox: Layout paints the content on a measuring canvas to know
  the height before the control is shown, since a height that changes
  in the first paint leaves the box scrolled wrong on Cocoa. FitHeight
  tells it the box's height, which the console grows into. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, gittan.repocommands, gittan.console;

const
  {** The least height of the console, in 96-DPI pixels. }
  ConsoleMinHeight = 160;

type
  {** A click on a tile, with the command's index. }
  TGittanCommandIndexEvent = procedure(Sender: TObject; AIndex: integer) of object;

  { TGittanCommandPage }

  TGittanCommandPage = class(TCustomControl)
  private
    FName, FRoot: string;
    FCommands: TGittanRepoCommands;
    FHasFile, FTrusted: boolean;
    FRunName: string;
    FHasRun, FRunning, FRunStarted, FRunKilled: boolean;
    FExitCode: integer;
    FElapsedMs: int64;
    FConsole: TGittanConsole;
    FShortcutPrefix: string;
    FBack, FText, FDim, FHover, FLine, FLink, FOk, FErrorColor, FCard: TColor;
    FLinkRects: array of TRect;
    FLinkUrls: array of string;
    FHot: integer;
    FContentHeight, FBoxHeight, FOutputTop: integer;
    { The canvas the content is painted on: the control's in Paint, a
      measuring one in Layout. }
    FC: TCanvas;
    FOnRun: TGittanCommandIndexEvent;
    FOnStop, FOnTrust, FOnEditFile, FOnCopyOutput: TNotifyEvent;
    function LinkAt(X, Y: integer): integer;
    procedure SetHot(AValue: integer);
    procedure AddLink(const ARect: TRect; const AUrl: string);
    procedure PaintHeading(var Y: integer; const ATitle, ADetail, AState: string;
      AStateColor: TColor);
    procedure PaintAction(ATop: integer; const ACaption, ALink: string);
    procedure PaintNote(var Y: integer; const AText: string);
    procedure PaintTrustCard(var Y: integer);
    procedure PaintTiles(var Y: integer; ASource: TGittanCommandSource);
    function GroupCount(ASource: TGittanCommandSource): integer;
    procedure PaintContent;
    procedure Layout;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    constructor Create(AOwner: TComponent); override;
    {** The repository shown: its name over its root. Another root
      drops the commands and the run of the one before. }
    procedure SetRepository(const AName, ARoot: string);
    {** The commands, whether the commands file exists and whether it
      is trusted. }
    procedure SetCommands(const ACommands: TGittanRepoCommands; AHasFile, ATrusted: boolean);
    {** The command AName is running (ARunning), or has ended with
      AExitCode after AElapsedMs; AStarted false when the shell could
      not start it, AKilled when Stop ended it. }
    procedure SetRun(const AName: string; ARunning: boolean; AExitCode: integer;
      AElapsedMs: int64; AStarted, AKilled: boolean);
    {** The palette: the background, the text, the dim text, the fill
      under the mouse, the dividers, the links, the ok state and the
      error state. }
    procedure SetColors(ABack, AText, ADim, AHover, ALine, ALink, AOk, AError: TColor);
    {** The fill of the tiles and the trust card. }
    procedure SetCardColor(ACard: TColor);
    {** Makes the control at least AMin high (the height of the box it
      sits in, so its background covers the box and the console fills
      the rest), and no higher than its content needs beyond that. }
    procedure FitHeight(AMin: integer);
    {** The console the output goes to. }
    property Console: TGittanConsole read FConsole;
    {** What a shortcut's chip starts with: "⌃⌘" or "Ctrl+Alt+". }
    property ShortcutPrefix: string read FShortcutPrefix write FShortcutPrefix;
    {** Whether a command is running. }
    property Running: boolean read FRunning;
    {** The root the commands are for. }
    property Root: string read FRoot;
    {** Where the Output section starts, for the box to scroll to; -1
      while nothing has run. }
    property OutputTop: integer read FOutputTop;
    property OnRun: TGittanCommandIndexEvent read FOnRun write FOnRun;
    property OnStop: TNotifyEvent read FOnStop write FOnStop;
    property OnTrust: TNotifyEvent read FOnTrust write FOnTrust;
    {** Edit… or Create… at the right of the first group's heading. }
    property OnEditFile: TNotifyEvent read FOnEditFile write FOnEditFile;
    property OnCopyOutput: TNotifyEvent read FOnCopyOutput write FOnCopyOutput;
  end;

{** AMs as the page says a time: "340 ms", "2.3 s", "1:05". }
function FormatElapsed(AMs: int64): string;

implementation

uses
  Math, LCLIntf, LCLType, gittan.textfit, gittan.theme;

resourcestring
  rsPageTitle = 'Commands';
  rsFileGroup = 'Commands';
  rsScriptsGroup = 'Scripts';
  rsTargetsGroup = 'Targets';
  rsPackageJson = 'package.json';
  rsMakefile = 'Makefile';
  rsEditFile = 'Edit…';
  rsCreateFile = 'Create…';
  rsNoCommands = 'No commands yet. A .gittan/commands.ini names them, and the scripts of a ' +
    'package.json and the targets of a Makefile are listed by themselves.';
  rsTrustTitle = 'This repository''s commands.ini has not been trusted on this computer';
  rsTrustText = 'A committed file could make a shortcut run anything. Its commands and ' +
    'their shortcuts are off until you trust it; a change of the file asks again.';
  rsTrustButton = 'Trust Commands';
  rsOutput = 'Output';
  rsRunning = 'running';
  rsRunningTile = 'Running…';
  rsExitOk = 'done';
  rsExitCode = 'exit code %d';
  rsStopped = 'stopped';
  rsNoStart = 'could not start';
  rsStop = 'Stop';
  rsCopy = 'Copy';
  rsTerminalTile = 'in a terminal';
  rsNoSuchTarget = 'no script or target named %s';

const
  RunLink = 'gittan:run:';
  StopLink = 'gittan:stop';
  CopyLink = 'gittan:copy';
  TrustLink = 'gittan:trust';
  EditLink = 'gittan:edit';
  Pad = 24;
  Gap = 12;
  TitleFontSize = 20;
  { The tiles: their least width, the gap between them, the padding in
    them, the corner radius; the chip of a shortcut. }
  TileMinWidth = 220;
  TileGap = 10;
  TilePadX = 14;
  TilePadY = 10;
  TileRadius = 12;
  ChipPadX = 6;
  ChipPadY = 2;
  ChipRadius = 6;
  CardPad = 14;
  ButtonPadX = 12;
  ButtonPadY = 5;

function FormatElapsed(AMs: int64): string;
var
  Settings: TFormatSettings;
begin
  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := '.';
  if AMs < 1000 then
    Result := IntToStr(AMs) + ' ms'
  else if AMs < 60000 then
    Result := FormatFloat('0.0', AMs / 1000, Settings) + ' s'
  else
    Result := Format('%d:%.2d', [AMs div 60000, (AMs mod 60000) div 1000]);
end;

{ TGittanCommandPage }

constructor TGittanCommandPage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FHot := -1;
  FExitCode := -1;
  FOutputTop := -1;
  Align := alTop;
  FShortcutPrefix := 'Ctrl+Alt+';
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnShadow, clHighlight,
    clGreen, clRed);
  FCard := clBtnFace;
  FConsole := TGittanConsole.Create(Self);
  FConsole.Parent := Self;
  FConsole.Visible := False;
end;

procedure TGittanCommandPage.SetRepository(const AName, ARoot: string);
begin
  if FRoot <> ARoot then
  begin
    FCommands := nil;
    FHasFile := False;
    FTrusted := True;
    FHasRun := False;
    FRunning := False;
    FConsole.Text := '';
    FConsole.Visible := False;
  end;
  FName := AName;
  FRoot := ARoot;
  Layout;
  Invalidate;
end;

procedure TGittanCommandPage.SetCommands(const ACommands: TGittanRepoCommands;
  AHasFile, ATrusted: boolean);
var
  i: integer;
begin
  SetLength(FCommands, Length(ACommands));
  for i := 0 to High(ACommands) do
    FCommands[i] := ACommands[i];
  FHasFile := AHasFile;
  FTrusted := ATrusted;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanCommandPage.SetRun(const AName: string; ARunning: boolean;
  AExitCode: integer; AElapsedMs: int64; AStarted, AKilled: boolean);
begin
  FRunName := AName;
  FHasRun := True;
  FRunning := ARunning;
  FExitCode := AExitCode;
  FElapsedMs := AElapsedMs;
  FRunStarted := AStarted;
  FRunKilled := AKilled;
  FConsole.Visible := True;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanCommandPage.SetColors(ABack, AText, ADim, AHover, ALine, ALink, AOk,
  AError: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
  FLine := ALine;
  FLink := ALink;
  FOk := AOk;
  FErrorColor := AError;
  Color := ABack;
  Invalidate;
end;

procedure TGittanCommandPage.SetCardColor(ACard: TColor);
begin
  FCard := ACard;
  Invalidate;
end;

procedure TGittanCommandPage.FitHeight(AMin: integer);
begin
  FBoxHeight := AMin;
  Constraints.MinHeight := AMin;
  { The console's height follows the box's. }
  Layout;
end;

{ The content painted on the measuring canvas, for its height and the
  console's place; the height is set here, never in Paint. }
procedure TGittanCommandPage.Layout;
var
  H: integer;
begin
  if (Parent = nil) or (Width <= 0) then
    Exit;
  FC := MeasureCanvas(Font);
  PaintContent;
  H := Max(FContentHeight, Constraints.MinHeight);
  if Height <> H then
    Height := H;
  Invalidate;
end;

procedure TGittanCommandPage.Resize;
begin
  inherited Resize;
  Layout;
end;

function TGittanCommandPage.LinkAt(X, Y: integer): integer;
var
  i: integer;
begin
  for i := 0 to High(FLinkRects) do
    if PtInRect(FLinkRects[i], Point(X, Y)) then
      Exit(i);
  Result := -1;
end;

procedure TGittanCommandPage.SetHot(AValue: integer);
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

procedure TGittanCommandPage.AddLink(const ARect: TRect; const AUrl: string);
begin
  SetLength(FLinkRects, Length(FLinkRects) + 1);
  SetLength(FLinkUrls, Length(FLinkUrls) + 1);
  FLinkRects[High(FLinkRects)] := ARect;
  FLinkUrls[High(FLinkUrls)] := AUrl;
end;

function TGittanCommandPage.GroupCount(ASource: TGittanCommandSource): integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to High(FCommands) do
    if FCommands[i].Source = ASource then
      Inc(Result);
end;

{ A dim bold title with a dim detail after it and, after that, a state
  in its own color, over a divider. }
procedure TGittanCommandPage.PaintHeading(var Y: integer; const ATitle, ADetail,
  AState: string; AStateColor: TColor);
var
  TextH, X: integer;
begin
  Inc(Y, Px(Pad));
  FC.Font := Font;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FDim;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  FC.TextOut(Px(Pad), Y, ATitle);
  X := Px(Pad) + FC.TextWidth(ATitle) + Px(Gap) div 2;
  FC.Font.Style := [];
  if ADetail <> '' then
  begin
    FC.TextOut(X, Y, ADetail);
    Inc(X, FC.TextWidth(ADetail) + Px(Gap) div 2);
  end;
  if AState <> '' then
  begin
    FC.Font.Color := AStateColor;
    FC.TextOut(X, Y, FitTextRight(FC, AState, Max(0, Width - Px(Pad) * 4 - X)));
  end;
  Inc(Y, TextH + Px(Gap) div 2);
  FC.Pen.Style := psSolid;
  FC.Pen.Color := FLine;
  FC.Line(Px(Pad), Y, Width - Px(Pad), Y);
  Inc(Y, Px(Gap) div 2);
end;

{ ACaption as a link at the right edge, on the line of a heading whose
  text starts at ATop. }
procedure TGittanCommandPage.PaintAction(ATop: integer; const ACaption, ALink: string);
var
  R: TRect;
begin
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  R := Rect(Width - Px(Pad) - FC.TextWidth(ACaption), ATop, Width - Px(Pad),
    ATop + FC.TextHeight('Xg'));
  AddLink(R, ALink);
  FC.Font.Color := FLink;
  if FHot = High(FLinkRects) then
    FC.Font.Style := [fsUnderline];
  FC.TextOut(R.Left, R.Top, ACaption);
  FC.Font.Style := [];
end;

{ A dim paragraph, wrapped to the width. }
procedure TGittanCommandPage.PaintNote(var Y: integer; const AText: string);
var
  R: TRect;
  Style: TTextStyle;
begin
  FC.Font := Font;
  FC.Font.Color := FDim;
  FC.Brush.Style := bsClear;
  R := Rect(Px(Pad), Y, Width - Px(Pad), Y);
  Style := FC.TextStyle;
  Style.Wordbreak := True;
  Style.SingleLine := False;
  Style.Alignment := taLeftJustify;
  Style.Layout := tlTop;
  DrawText(FC.Handle, PChar(AText), Length(AText), R, DT_CALCRECT or DT_WORDBREAK);
  R.Right := Width - Px(Pad);
  FC.TextRect(R, R.Left, R.Top, AText, Style);
  Y := R.Bottom;
end;

{ The card that says the file is not trusted, with the button. }
procedure TGittanCommandPage.PaintTrustCard(var Y: integer);
var
  R, Inner, B: TRect;
  Style: TTextStyle;
  TextH, CardTop: integer;
begin
  CardTop := Y;
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  Inner := Rect(Px(Pad) + Px(CardPad), CardTop + Px(CardPad), Width - Px(Pad) - Px(CardPad), 0);
  { Measure the text first, then paint the card behind it. }
  Style := FC.TextStyle;
  Style.Wordbreak := True;
  Style.SingleLine := False;
  Style.Alignment := taLeftJustify;
  Style.Layout := tlTop;
  R := Rect(Inner.Left, Inner.Top + TextH + 4, Inner.Right, Inner.Top + TextH + 4);
  DrawText(FC.Handle, PChar(rsTrustText), Length(rsTrustText), R, DT_CALCRECT or DT_WORDBREAK);
  B := Rect(Inner.Left, R.Bottom + Px(Gap), Inner.Left + FC.TextWidth(rsTrustButton) +
    2 * Px(ButtonPadX), R.Bottom + Px(Gap) + TextH + 2 * Px(ButtonPadY));
  Y := B.Bottom + Px(CardPad);

  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FCard;
  FC.RoundRect(Px(Pad), CardTop, Width - Px(Pad), Y, Px(TileRadius), Px(TileRadius));
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  FC.TextOut(Inner.Left, Inner.Top, FitTextRight(FC, rsTrustTitle,
    Inner.Right - Inner.Left));
  FC.Font.Style := [];
  FC.Font.Color := FDim;
  R.Right := Inner.Right;
  FC.TextRect(R, R.Left, R.Top, rsTrustText, Style);

  { The button: filled in the link color, its text in the background. }
  AddLink(B, TrustLink);
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  if FHot = High(FLinkRects) then
    FC.Brush.Color := MixColor(FLink, FText, 0.2)
  else
    FC.Brush.Color := FLink;
  FC.RoundRect(B, Px(ChipRadius) * 2, Px(ChipRadius) * 2);
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;
  FC.Font.Color := FBack;
  FC.TextOut(B.Left + Px(ButtonPadX), B.Top + Px(ButtonPadY), rsTrustButton);
  FC.Font.Color := FText;
  Inc(Y, Px(Gap));
end;

{ The tiles of one source: as many in a row as fit at TileMinWidth,
  the rows as even as they can be. Each has the name, under it what
  runs dimmed, and at the right its shortcut as a chip. The running
  one says so; the file's are dimmed and lead nowhere while the file
  is not trusted; none leads anywhere while one runs. }
procedure TGittanCommandPage.PaintTiles(var Y: integer; ASource: TGittanCommandSource);
var
  Indexes: array of integer;
  n, MaxCols, Rows, Cols, TileW, TileH, BodyH, i, X, TileY, Inner, ChipW, ChipH, Right: integer;
  Detail, Chip: string;
  R, ChipR: TRect;
  Off, Leads: boolean;
begin
  Indexes := nil;
  for i := 0 to High(FCommands) do
    if FCommands[i].Source = ASource then
    begin
      SetLength(Indexes, Length(Indexes) + 1);
      Indexes[High(Indexes)] := i;
    end;
  n := Length(Indexes);
  if n = 0 then
    Exit;
  MaxCols := Max(1, (Width - 2 * Px(Pad) + Px(TileGap)) div (Px(TileMinWidth) + Px(TileGap)));
  Rows := (n + MaxCols - 1) div MaxCols;
  Cols := (n + Rows - 1) div Rows;
  TileW := (Width - 2 * Px(Pad) - (Cols - 1) * Px(TileGap)) div Cols;
  FC.Font := Font;
  BodyH := FC.TextHeight('Xg');
  TileH := 2 * Px(TilePadY) + 2 * BodyH + 4;
  for i := 0 to n - 1 do
  begin
    X := Px(Pad) + (i mod Cols) * (TileW + Px(TileGap));
    TileY := Y + (i div Cols) * (TileH + Px(TileGap));
    R := Rect(X, TileY, X + TileW, TileY + TileH);
    { The file's are off while it is not trusted, and a section that
      names no script or target always. }
    Off := ((ASource = csFile) and not FTrusted) or (FCommands[Indexes[i]].Command = '');
    Leads := not Off and not FRunning and Assigned(FOnRun);
    FC.Pen.Style := psClear;
    FC.Brush.Style := bsSolid;
    FC.Brush.Color := FCard;
    if Leads then
    begin
      if FHot = Length(FLinkRects) then
        FC.Brush.Color := FHover;
      AddLink(R, RunLink + IntToStr(Indexes[i]));
    end;
    FC.RoundRect(R, Px(TileRadius), Px(TileRadius));
    FC.Pen.Style := psSolid;
    FC.Brush.Style := bsClear;
    Right := X + TileW - Px(TilePadX);
    { The chip of the shortcut, dimmed while the file is not trusted. }
    if FCommands[Indexes[i]].Key <> #0 then
    begin
      Chip := FShortcutPrefix + FCommands[Indexes[i]].Key;
      FC.Font := Font;
      FC.Font.Size := Max(7, Font.Size - 2);
      if Font.Size <= 0 then
        FC.Font.Size := 9;
      ChipW := FC.TextWidth(Chip) + 2 * Px(ChipPadX);
      ChipH := FC.TextHeight(Chip) + 2 * Px(ChipPadY);
      ChipR := Rect(Right - ChipW, TileY + Px(TilePadY), Right, TileY + Px(TilePadY) + ChipH);
      FC.Pen.Style := psClear;
      FC.Brush.Style := bsSolid;
      FC.Brush.Color := FHover;
      FC.RoundRect(ChipR, Px(ChipRadius), Px(ChipRadius));
      FC.Pen.Style := psSolid;
      FC.Brush.Style := bsClear;
      FC.Font.Color := FDim;
      FC.TextOut(ChipR.Left + Px(ChipPadX), ChipR.Top + Px(ChipPadY), Chip);
      FC.Font := Font;
      FC.Brush.Style := bsClear;
      Right := ChipR.Left - Px(Gap) div 2;
    end;
    Inner := Right - (X + Px(TilePadX));
    FC.Font.Style := [fsBold];
    if Off then
      FC.Font.Color := FDim
    else
      FC.Font.Color := FText;
    FC.TextOut(X + Px(TilePadX), TileY + Px(TilePadY), FitTextRight(FC,
      FCommands[Indexes[i]].Name, Inner));
    FC.Font.Style := [];
    Inner := X + TileW - Px(TilePadX) - (X + Px(TilePadX));
    if FRunning and (FCommands[Indexes[i]].Name = FRunName) and
      (FCommands[Indexes[i]].Source = ASource) then
    begin
      Detail := rsRunningTile;
      FC.Font.Color := FLink;
    end
    else
    begin
      if FCommands[Indexes[i]].Command = '' then
        Detail := Format(rsNoSuchTarget, [FCommands[Indexes[i]].Name])
      else
        Detail := FCommands[Indexes[i]].Detail;
      if FCommands[Indexes[i]].Terminal then
        Detail := Detail + ' · ' + rsTerminalTile;
      FC.Font.Color := FDim;
    end;
    FC.TextOut(X + Px(TilePadX), TileY + Px(TilePadY) + BodyH + 4, FitTextRight(FC,
      Detail, Inner));
  end;
  Inc(Y, Rows * TileH + (Rows - 1) * Px(TileGap));
end;

procedure TGittanCommandPage.Paint;
begin
  FC := Canvas;
  PaintContent;
end;

procedure TGittanCommandPage.PaintContent;
var
  Y, TextH, TitleH, HeadingTop, ConsoleH, X: integer;
  State: string;
  StateColor: TColor;
  R: TRect;
begin
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FBack;
  FC.FillRect(Rect(0, 0, Width, Height));
  FLinkRects := nil;
  FLinkUrls := nil;
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  Y := Px(Pad);

  { The name with the page's title after it, the path under them. }
  FC.Font.Size := TitleFontSize;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  TitleH := FC.TextHeight('Xg');
  FC.TextOut(Px(Pad), Y, FName);
  X := Px(Pad) + FC.TextWidth(FName) + Px(Gap);
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  FC.Font.Color := FDim;
  FC.TextOut(X, Y + TitleH - TextH - 3, rsPageTitle);
  Inc(Y, TitleH + 2);
  FC.TextOut(Px(Pad), Y, FitTextLeft(FC, FRoot, Width - 2 * Px(Pad)));
  Inc(Y, TextH);

  { The file's commands, with the trust card over them while the file
    is not trusted; with no commands at all the page says so here. }
  HeadingTop := Y;
  PaintHeading(Y, rsFileGroup, CommandsPath, '', FDim);
  if Assigned(FOnEditFile) then
    if FHasFile then
      PaintAction(HeadingTop + Px(Pad), rsEditFile, EditLink)
    else
      PaintAction(HeadingTop + Px(Pad), rsCreateFile, EditLink);
  if FHasFile and not FTrusted then
    PaintTrustCard(Y);
  if GroupCount(csFile) > 0 then
    PaintTiles(Y, csFile)
  else if Length(FCommands) = 0 then
    PaintNote(Y, rsNoCommands);

  if GroupCount(csPackage) > 0 then
  begin
    PaintHeading(Y, rsScriptsGroup, rsPackageJson, '', FDim);
    PaintTiles(Y, csPackage);
  end;
  if GroupCount(csMake) > 0 then
  begin
    PaintHeading(Y, rsTargetsGroup, rsMakefile, '', FDim);
    PaintTiles(Y, csMake);
  end;

  { The output of the last run, in the console under its heading. }
  FOutputTop := -1;
  if FHasRun then
  begin
    if FRunning then
    begin
      State := rsRunning;
      StateColor := FLink;
    end
    else if not FRunStarted then
    begin
      State := rsNoStart;
      StateColor := FErrorColor;
    end
    else if FRunKilled then
    begin
      State := rsStopped + ' · ' + FormatElapsed(FElapsedMs);
      StateColor := FDim;
    end
    else if FExitCode = 0 then
    begin
      State := rsExitOk + ' · ' + FormatElapsed(FElapsedMs);
      StateColor := FOk;
    end
    else
    begin
      State := Format(rsExitCode, [FExitCode]) + ' · ' + FormatElapsed(FElapsedMs);
      StateColor := FErrorColor;
    end;
    HeadingTop := Y;
    FOutputTop := Y;
    PaintHeading(Y, rsOutput, FRunName, State, StateColor);
    if FRunning then
    begin
      if Assigned(FOnStop) then
        PaintAction(HeadingTop + Px(Pad), rsStop, StopLink);
    end
    else if Assigned(FOnCopyOutput) then
      PaintAction(HeadingTop + Px(Pad), rsCopy, CopyLink);
    { As high as the box less the heading, so the console fills the
      box once it is scrolled to the heading, as a terminal pane. }
    ConsoleH := Max(Px(ConsoleMinHeight), FBoxHeight - (Y - FOutputTop) - Px(Pad));
    R := Rect(Px(Pad), Y, Width - Px(Pad), Y + ConsoleH);
    if FConsole.BoundsRect <> R then
      FConsole.BoundsRect := R;
    Inc(Y, ConsoleH);
  end;

  { Layout sets the height from this. }
  FContentHeight := Y + Px(Pad);
end;

procedure TGittanCommandPage.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(LinkAt(X, Y));
end;

procedure TGittanCommandPage.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1);
end;

procedure TGittanCommandPage.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  i, n: integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  i := LinkAt(X, Y);
  if i < 0 then
    Exit;
  if Copy(FLinkUrls[i], 1, Length(RunLink)) = RunLink then
  begin
    n := StrToIntDef(Copy(FLinkUrls[i], Length(RunLink) + 1, MaxInt), -1);
    if Assigned(FOnRun) and (n >= 0) and (n <= High(FCommands)) then
      FOnRun(Self, n);
  end
  else if FLinkUrls[i] = StopLink then
  begin
    if Assigned(FOnStop) then
      FOnStop(Self);
  end
  else if FLinkUrls[i] = CopyLink then
  begin
    if Assigned(FOnCopyOutput) then
      FOnCopyOutput(Self);
  end
  else if FLinkUrls[i] = TrustLink then
  begin
    if Assigned(FOnTrust) then
      FOnTrust(Self);
  end
  else if FLinkUrls[i] = EditLink then
    if Assigned(FOnEditFile) then
      FOnEditFile(Self);
end;

end.
