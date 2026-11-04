unit gittan.commandpage;

{** The Commands page: the repository's own commands as tiles, grouped
  by where they come from (gittan.repocommands): the commands file,
  the scripts of package.json and the targets of a Makefile. In each,
  the commands that share a group (SplitCommandName: build for
  build:run and build:test, or build-linux for a target) are listed
  under the group's name, with the name after it on the tile, and the
  rest come first under no heading. A tile is one line: a run mark,
  the command's name, its shortcut as a chip and a terminal at the
  right; what runs (the shell line, or a script's text, with the full
  name for a tile in a group) is its hint. It fills under the mouse
  and a click raises OnRun with its index. A section of the file that
  names no script or target is a dimmed tile whose hint says so, and
  it leads nowhere. Each source's heading names its file, and the
  first's offers Edit… or Create… (OnEditFile). While the commands
  file is not trusted its commands are dimmed under a card that says
  why, with a Trust Commands button (OnTrust).

  Under the groups, once a command has run, the output is a panel: a
  bar with its state as a pill (Running with a dot that pulses, Done,
  Failed with the exit code, Stopping…, Stopped, Could not start), the
  command's name and its time, which counts while it runs, and the
  buttons at the right (Stop while it runs, else Run Again and Copy),
  over a console (TGittanConsole, Console, the owner's to fill and to
  give the editor's font) that fills the rest of the box it sits in, at
  least ConsoleMinHeight, so the output shows without scrolling when
  the tiles leave room. The tile of the last run has its mark in the
  state's color.

  The tiles of every group share one grid, so a group of one has a tile
  as wide as the others; the terminal at a tile's right end raises
  OnRunInTerminal, for a command that keeps running (a dev server, a
  watch), also while another runs here.

  It paints itself in the editor's palette, like the Repository page,
  and sizes its height to its content so it can sit in the same
  TScrollBox: Layout paints the content on a measuring canvas to know
  the height before the control is shown, since a height that changes
  in the first paint leaves the box scrolled wrong on Cocoa. FitHeight
  tells it the box's height, which the console grows into. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, ExtCtrls, gittan.repocommands,
  gittan.project, gittan.console;

const
  {** The least height of the console, in 96-DPI pixels. }
  ConsoleMinHeight = 220;

type
  {** A click on a tile, with the command's index. }
  TGittanCommandIndexEvent = procedure(Sender: TObject; AIndex: integer) of object;

  { TGittanCommandPage }

  TGittanCommandPage = class(TCustomControl)
  private
    FName, FRoot: string;
    FCommands: TGittanRepoCommands;
    FProjects: TGittanProjects;
    FFiles: TGittanCommandsFiles;
    FTrusted: boolean;
    FRunName, FRunProject: string;
    FRunSource: TGittanCommandSource;
    FHasRun, FRunning, FRunStarted, FRunKilled, FStopping, FPulse: boolean;
    FExitCode: integer;
    FElapsedMs: int64;
    FRunStart: QWord;
    { Ticks while a command runs: the time counts and the dot pulses. }
    FTimer: TTimer;
    FConsole: TGittanConsole;
    FShortcutPrefix: string;
    FBack, FText, FDim, FHover, FLine, FLink, FOk, FErrorColor, FCard: TColor;
    FLinkRects: array of TRect;
    FLinkUrls: array of string;
    FLinkHints: array of string;
    FHot: integer;
    FContentHeight, FBoxHeight, FOutputTop: integer;
    { The canvas the content is painted on: the control's in Paint, a
      measuring one in Layout. }
    FC: TCanvas;
    FOnRun, FOnRunInTerminal: TGittanCommandIndexEvent;
    FOnStop, FOnTrust, FOnEditFile, FOnCopyOutput: TNotifyEvent;
    function LinkAt(X, Y: integer): integer;
    procedure SetHot(AValue: integer);
    procedure AddLink(const ARect: TRect; const AUrl: string; const AHint: string = '');
    procedure PaintHeading(var Y: integer; const ATitle, ADetail, AState: string;
      AStateColor: TColor);
    procedure PaintAction(ATop: integer; const ACaption, ALink: string);
    procedure PaintNote(var Y: integer; const AText: string; AColor: TColor = clNone);
    procedure PaintFileSection(var Y: integer; const AFile: TGittanCommandsFile);
    procedure PaintTrustCard(var Y: integer);
    procedure PaintTiles(var Y: integer; ASource: TGittanCommandSource;
      const AProject: string = '');
    procedure PaintSubheading(var Y: integer; const ATitle: string);
    procedure PaintGrid(var Y: integer; const AIndexes: array of integer; AShort: boolean);
    procedure PaintButton(const R: TRect; const ACaption, ALink: string;
      AFill, ATextColor: TColor);
    procedure PaintStateMark(X, Y, ASize: integer; AColor: TColor);
    procedure PaintTerminalIcon(X, Y, ASize: integer; AColor: TColor);
    procedure PaintOutput(var Y: integer);
    function RunState(out AColor: TColor): string;
    function RunIndex: integer;
    procedure TimerTick(Sender: TObject);
    function GroupCount(ASource: TGittanCommandSource; const AProject: string = ''): integer;
    function IsRun(const ACommand: TGittanRepoCommand): boolean;
    function ColumnCount: integer;
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
    destructor Destroy; override;
    {** The repository shown: its name over its root. Another root
      drops the commands and the run of the one before. }
    procedure SetRepository(const AName, ARoot: string);
    {** The commands, the kinds of project they are listed under (a
      section each, in this order), the commands files (a section each,
      the first under Commands; ReadCommandsFiles) and whether they are
      trusted. }
    procedure SetCommands(const ACommands: TGittanRepoCommands;
      const AProjects: TGittanProjects; const AFiles: TGittanCommandsFiles;
      ATrusted: boolean);
    {** The command AName of ASource (a script and a target may share
      a name; AProject the kind's name for one of a kind's) is running
      (ARunning), or has ended with AExitCode after AElapsedMs; AStarted
      false when the shell could not start it, AKilled when Stop ended
      it. }
    procedure SetRun(const AName: string; ASource: TGittanCommandSource;
      const AProject: string; ARunning: boolean; AExitCode: integer; AElapsedMs: int64;
      AStarted, AKilled: boolean);
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
    {** A click on a tile's terminal, with the command's index. }
    property OnRunInTerminal: TGittanCommandIndexEvent read FOnRunInTerminal
      write FOnRunInTerminal;
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
  rsNoCommands = 'No commands yet. A .gittan/commands.toml names them, and the scripts of a ' +
    'package.json, the targets of a Makefile and the commands of a Cargo.toml, go.mod, ' +
    'pyproject.toml or Lazarus project are listed by themselves.';
  rsNoManifest = 'named in commands.toml';
  rsNotToml = 'Not read: %s';
  rsTrustTitle = 'This repository''s commands have not been trusted on this computer';
  rsTrustText = 'A committed file could make a shortcut run anything. The commands of ' +
    '.gittan and their shortcuts are off until you trust them; a change of a file asks again.';
  rsTrustButton = 'Trust Commands';
  rsRunning = 'Running';
  rsRunningTile = 'Running… %s';
  rsExitOk = 'Done';
  rsExitCode = 'Failed · exit code %d';
  rsStopping = 'Stopping…';
  rsStopped = 'Stopped';
  rsNoStart = 'Could not start';
  rsStop = 'Stop';
  rsCopy = 'Copy';
  rsRunAgain = 'Run Again';
  rsRunInTerminal = 'Run in Terminal';
  rsTerminalTile = 'in a terminal';
  rsNoSuchTarget = 'no script or target named %s';

const
  RunLink = 'gittan:run:';
  AgainLink = 'gittan:again';
  TerminalLink = 'gittan:terminal:';
  StopLink = 'gittan:stop';
  CopyLink = 'gittan:copy';
  TrustLink = 'gittan:trust';
  EditLink = 'gittan:edit';
  { A tile that leads nowhere (off, or running): its hint shows, nothing
    runs. }
  NoteLink = 'gittan:note';
  Pad = 24;
  Gap = 12;
  TitleFontSize = 20;
  { The tiles: their least width, the gap between them, the padding in
    them, the corner radius; the chip of a shortcut. }
  TileMinWidth = 180;
  TileGap = 10;
  TilePadX = 14;
  TilePadY = 10;
  TileRadius = 12;
  ChipPadX = 6;
  ChipPadY = 2;
  ChipRadius = 6;
  { The run mark at the left of a tile: its width, its height and the
    space after it. }
  MarkW = 7;
  MarkH = 9;
  MarkGap = 10;
  { The terminal at the right end of a tile. }
  TermW = 13;
  TermH = 11;
  CardPad = 14;
  ButtonPadX = 12;
  ButtonPadY = 5;
  { The output's bar: its padding, the gap between its buttons. }
  BarPad = 10;
  { The time the dot of a running command takes to pulse. }
  PulseMs = 600;

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
  ShowHint := True;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := PulseMs;
  FTimer.OnTimer := @TimerTick;
end;

destructor TGittanCommandPage.Destroy;
begin
  inherited Destroy;
end;

procedure TGittanCommandPage.SetRepository(const AName, ARoot: string);
begin
  if FRoot <> ARoot then
  begin
    FCommands := nil;
    FFiles := nil;
    FTrusted := True;
    FHasRun := False;
    FRunning := False;
    FTimer.Enabled := False;
    FConsole.Text := '';
    FConsole.Visible := False;
  end;
  FName := AName;
  FRoot := ARoot;
  Layout;
  Invalidate;
end;

procedure TGittanCommandPage.SetCommands(const ACommands: TGittanRepoCommands;
  const AProjects: TGittanProjects; const AFiles: TGittanCommandsFiles; ATrusted: boolean);
var
  i: integer;
begin
  SetLength(FCommands, Length(ACommands));
  for i := 0 to High(ACommands) do
    FCommands[i] := ACommands[i];
  SetLength(FProjects, Length(AProjects));
  for i := 0 to High(AProjects) do
    FProjects[i] := AProjects[i];
  SetLength(FFiles, Length(AFiles));
  for i := 0 to High(AFiles) do
    FFiles[i] := AFiles[i];
  FTrusted := ATrusted;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanCommandPage.SetRun(const AName: string; ASource: TGittanCommandSource;
  const AProject: string; ARunning: boolean; AExitCode: integer; AElapsedMs: int64;
  AStarted, AKilled: boolean);
begin
  if ARunning and not FRunning then
    FRunStart := GetTickCount64;
  FRunName := AName;
  FRunSource := ASource;
  FRunProject := AProject;
  FHasRun := True;
  FRunning := ARunning;
  FStopping := False;
  FTimer.Enabled := ARunning;
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
  if (AValue < 0) or (FLinkUrls[AValue] = NoteLink) then
    Cursor := crDefault
  else
    Cursor := crHandPoint;
  if AValue >= 0 then
    Hint := FLinkHints[AValue]
  else
    Hint := '';
  Invalidate;
end;

procedure TGittanCommandPage.AddLink(const ARect: TRect; const AUrl: string;
  const AHint: string);
begin
  SetLength(FLinkRects, Length(FLinkRects) + 1);
  SetLength(FLinkUrls, Length(FLinkUrls) + 1);
  SetLength(FLinkHints, Length(FLinkHints) + 1);
  FLinkRects[High(FLinkRects)] := ARect;
  FLinkUrls[High(FLinkUrls)] := AUrl;
  FLinkHints[High(FLinkHints)] := AHint;
end;

function TGittanCommandPage.GroupCount(ASource: TGittanCommandSource;
  const AProject: string): integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to High(FCommands) do
    if (FCommands[i].Source = ASource) and (FCommands[i].Project = AProject) then
      Inc(Result);
end;

{ Whether ACommand is the one that runs or ran last: by name, source
  and kind, so a reload that moves the indexes keeps it, and a kind's
  test is told from a script's. }
function TGittanCommandPage.IsRun(const ACommand: TGittanRepoCommand): boolean;
begin
  Result := (ACommand.Name = FRunName) and (ACommand.Source = FRunSource) and
    (ACommand.Project = FRunProject);
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
procedure TGittanCommandPage.PaintNote(var Y: integer; const AText: string; AColor: TColor);
var
  R: TRect;
  Style: TTextStyle;
begin
  FC.Font := Font;
  if AColor = clNone then
    FC.Font.Color := FDim
  else
    FC.Font.Color := AColor;
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

{ How many tiles a row of the grid holds: as many as fit at
  TileMinWidth. }
function TGittanCommandPage.ColumnCount: integer;
begin
  Result := Max(1, (Width - 2 * Px(Pad) + Px(TileGap)) div (Px(TileMinWidth) + Px(TileGap)));
end;

{ The tiles of one source by name, in the grid every group shares.
  Each has the run mark, the name, under it what runs dimmed, and at
  the right its shortcut as a chip. The running
  one says so; the file's are dimmed and lead nowhere while the file
  is not trusted; none leads anywhere while one runs. }
procedure TGittanCommandPage.PaintSubheading(var Y: integer; const ATitle: string);
begin
  Inc(Y, Px(Gap));
  FC.Font := Font;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  FC.Brush.Style := bsClear;
  FC.TextOut(Px(Pad), Y, FitTextRight(FC, ATitle, Width - 2 * Px(Pad)));
  Inc(Y, FC.TextHeight('Xg') + Px(Gap) div 2);
end;

procedure TGittanCommandPage.PaintTiles(var Y: integer; ASource: TGittanCommandSource;
  const AProject: string);
var
  Indexes, Plain, Members: array of integer;
  Groups: array of string;
  Counts: array of integer;
  i, j, k, g: integer;
  Group, Short: string;
begin
  Indexes := nil;
  for i := 0 to High(FCommands) do
    if (FCommands[i].Source = ASource) and (FCommands[i].Project = AProject) then
    begin
      SetLength(Indexes, Length(Indexes) + 1);
      Indexes[High(Indexes)] := i;
    end;
  if Length(Indexes) = 0 then
    Exit;
  { By name, whatever the order of the file they come from; a group's
    members are then together, its bare name (build before build:run)
    first. }
  for i := 1 to High(Indexes) do
  begin
    j := i;
    while (j > 0) and (CompareText(FCommands[Indexes[j - 1]].Name,
        FCommands[Indexes[j]].Name) > 0) do
    begin
      k := Indexes[j];
      Indexes[j] := Indexes[j - 1];
      Indexes[j - 1] := k;
      Dec(j);
    end;
  end;
  { The groups, in the order the names give, with how many each has. }
  Groups := nil;
  Counts := nil;
  for i := 0 to High(Indexes) do
  begin
    SplitCommandName(FCommands[Indexes[i]], Group, Short);
    g := -1;
    for j := 0 to High(Groups) do
      if CompareText(Groups[j], Group) = 0 then
        g := j;
    if g < 0 then
    begin
      SetLength(Groups, Length(Groups) + 1);
      SetLength(Counts, Length(Counts) + 1);
      g := High(Groups);
      Groups[g] := Group;
    end;
    Inc(Counts[g]);
  end;
  { The commands of no group (a group of one) first, under no heading,
    then each group with its name over it. }
  Plain := nil;
  for g := 0 to High(Groups) do
    if Counts[g] < 2 then
      for i := 0 to High(Indexes) do
      begin
        SplitCommandName(FCommands[Indexes[i]], Group, Short);
        if CompareText(Group, Groups[g]) = 0 then
        begin
          SetLength(Plain, Length(Plain) + 1);
          Plain[High(Plain)] := Indexes[i];
        end;
      end;
  { Back in name order, as the groups' order is the first member's. }
  for i := 1 to High(Plain) do
  begin
    j := i;
    while (j > 0) and (CompareText(FCommands[Plain[j - 1]].Name,
        FCommands[Plain[j]].Name) > 0) do
    begin
      k := Plain[j];
      Plain[j] := Plain[j - 1];
      Plain[j - 1] := k;
      Dec(j);
    end;
  end;
  if Length(Plain) > 0 then
    PaintGrid(Y, Plain, False);
  for g := 0 to High(Groups) do
    if Counts[g] >= 2 then
    begin
      Members := nil;
      for i := 0 to High(Indexes) do
      begin
        SplitCommandName(FCommands[Indexes[i]], Group, Short);
        if CompareText(Group, Groups[g]) = 0 then
        begin
          SetLength(Members, Length(Members) + 1);
          Members[High(Members)] := Indexes[i];
        end;
      end;
      PaintSubheading(Y, Groups[g]);
      PaintGrid(Y, Members, True);
    end;
end;

procedure TGittanCommandPage.PaintGrid(var Y: integer; const AIndexes: array of integer;
  AShort: boolean);
var
  n, Rows, Cols, TileW, TileH, BodyH, i, X, TileY, TextX, NameY, ChipW, ChipH, Right,
  MarkX, MarkY, TermY: integer;
  Detail, Chip, Group, Shown, Tip: string;
  R, ChipR, TermR: TRect;
  Off, Leads, Hot, TermHot, Busy: boolean;
  Cmd: TGittanRepoCommand;
  StateColor: TColor;
begin
  n := Length(AIndexes);
  if n = 0 then
    Exit;
  Cols := ColumnCount;
  Rows := (n + Cols - 1) div Cols;
  TileW := (Width - 2 * Px(Pad) - (Cols - 1) * Px(TileGap)) div Cols;
  FC.Font := Font;
  BodyH := Max(FC.TextHeight('Xg'), Px(TermH));
  TileH := 2 * Px(TilePadY) + BodyH;
  for i := 0 to n - 1 do
  begin
    Cmd := FCommands[AIndexes[i]];
    SplitCommandName(Cmd, Group, Shown);
    if not AShort then
      Shown := Cmd.Name;
    X := Px(Pad) + (i mod Cols) * (TileW + Px(TileGap));
    TileY := Y + (i div Cols) * (TileH + Px(TileGap));
    R := Rect(X, TileY, X + TileW, TileY + TileH);
    NameY := TileY + Px(TilePadY);
    Right := X + TileW - Px(TilePadX);
    { The file's are off while it is not trusted, and a section that
      names no script or target always. }
    Off := ((Cmd.Source = csFile) and not FTrusted) or (Cmd.Command = '');
    Leads := not Off and not FRunning and Assigned(FOnRun);
    Busy := FRunning and IsRun(Cmd);
    { What runs is the tile's hint: the shell line, or a script's text;
      a section that names nothing says so. }
    if Cmd.Command = '' then
      Tip := Format(rsNoSuchTarget, [Cmd.Name])
    else if Cmd.Detail <> '' then
      Tip := Cmd.Detail
    else
      Tip := Cmd.Command;
    if Cmd.Terminal then
      Tip := Tip + ' · ' + rsTerminalTile;
    if AShort then
      Tip := Cmd.Name + LineEnding + Tip;

    { The terminal's link goes first, as LinkAt takes the first that
      holds the point; it leads while another command runs here too.
      It sits at the right end, before the chip. }
    TermHot := False;
    TermY := NameY + (BodyH - Px(TermH)) div 2;
    TermR := Rect(Right - Px(TermW) - Px(4), TermY - Px(4), Right + Px(4),
      TermY + Px(TermH) + Px(4));
    if not Off and Assigned(FOnRunInTerminal) and not Busy then
    begin
      TermHot := FHot = Length(FLinkRects);
      AddLink(TermR, TerminalLink + IntToStr(AIndexes[i]), rsRunInTerminal);
    end;
    Hot := Leads and (FHot = Length(FLinkRects));
    if Leads then
      AddLink(R, RunLink + IntToStr(AIndexes[i]), Tip)
    else
      AddLink(R, NoteLink, Tip);

    { The tile, with a hairline round it; the running one's in the
      link color. }
    FC.Pen.Style := psSolid;
    FC.Pen.Width := 1;
    if Busy then
      FC.Pen.Color := FLink
    else
      FC.Pen.Color := MixColor(FCard, FLine, 0.5);
    FC.Brush.Style := bsSolid;
    if Hot or TermHot then
      FC.Brush.Color := FHover
    else
      FC.Brush.Color := FCard;
    FC.RoundRect(R, Px(TileRadius), Px(TileRadius));
    FC.Brush.Style := bsClear;

    { The run mark, in the link color under the mouse and while it
      runs, in the last run's state color, faint while the tile leads
      nowhere. }
    MarkY := NameY + (BodyH - Px(MarkH)) div 2;
    TextX := X + Px(TilePadX);
    FC.Pen.Style := psClear;
    FC.Brush.Style := bsSolid;
    if Hot or Busy then
      FC.Brush.Color := FLink
    else if FHasRun and IsRun(Cmd) and
      not FRunning then
    begin
      RunState(StateColor);
      FC.Brush.Color := StateColor;
    end
    else if Off then
      FC.Brush.Color := MixColor(FDim, FCard, 0.5)
    else
      FC.Brush.Color := FDim;
    MarkX := TextX;
    FC.Polygon([Point(MarkX, MarkY), Point(MarkX + Px(MarkW), MarkY + Px(MarkH) div 2),
      Point(MarkX, MarkY + Px(MarkH))]);
    FC.Pen.Style := psSolid;
    FC.Brush.Style := bsClear;
    Inc(TextX, Px(MarkW) + Px(MarkGap));

    if Busy then
    begin
      { The time so far, where the chip would be. }
      FC.Font := Font;
      FC.Font.Color := FLink;
      Detail := Format(rsRunningTile, [FormatElapsed(GetTickCount64 - FRunStart)]);
      FC.TextOut(Right - FC.TextWidth(Detail), NameY + (BodyH - FC.TextHeight(Detail)) div 2,
        Detail);
      Right := Right - FC.TextWidth(Detail) - Px(Gap) div 2;
    end
    else
    begin
      { The terminal, in the link color under the mouse. }
      if not Off and Assigned(FOnRunInTerminal) then
      begin
        if TermHot then
          PaintTerminalIcon(Right - Px(TermW), TermY, Px(TermW), FLink)
        else
          PaintTerminalIcon(Right - Px(TermW), TermY, Px(TermW), FDim);
        Right := Right - Px(TermW) - Px(Gap);
      end;
      { The chip of the shortcut. }
      if Cmd.Key <> #0 then
      begin
        Chip := FShortcutPrefix + Cmd.Key;
        FC.Font := Font;
        FC.Font.Size := Max(7, Font.Size - 2);
        if Font.Size <= 0 then
          FC.Font.Size := 9;
        ChipW := FC.TextWidth(Chip) + 2 * Px(ChipPadX);
        ChipH := FC.TextHeight(Chip) + 2 * Px(ChipPadY);
        ChipR := Rect(Right - ChipW, NameY + (BodyH - ChipH) div 2, Right,
          NameY + (BodyH - ChipH) div 2 + ChipH);
        FC.Pen.Style := psClear;
        FC.Brush.Style := bsSolid;
        if Hot or TermHot then
          FC.Brush.Color := FCard
        else
          FC.Brush.Color := FHover;
        FC.RoundRect(ChipR, Px(ChipRadius), Px(ChipRadius));
        FC.Pen.Style := psSolid;
        FC.Brush.Style := bsClear;
        FC.Font.Color := FDim;
        FC.TextOut(ChipR.Left + Px(ChipPadX), ChipR.Top + Px(ChipPadY), Chip);
        Right := ChipR.Left - Px(Gap) div 2;
      end;
    end;

    FC.Font := Font;
    FC.Brush.Style := bsClear;
    FC.Font.Style := [fsBold];
    if Off then
      FC.Font.Color := FDim
    else
      FC.Font.Color := FText;
    FC.TextOut(TextX, NameY + (BodyH - FC.TextHeight('Xg')) div 2,
      FitTextRight(FC, Shown, Right - TextX));
  end;
  Inc(Y, Rows * TileH + (Rows - 1) * Px(TileGap));
end;

procedure TGittanCommandPage.TimerTick(Sender: TObject);
begin
  FPulse := not FPulse;
  Invalidate;
end;

{ What the panel's pill says of the last run, and its color. }
function TGittanCommandPage.RunState(out AColor: TColor): string;
begin
  if FRunning and FStopping then
  begin
    Result := rsStopping;
    AColor := FDim;
  end
  else if FRunning then
  begin
    Result := rsRunning;
    AColor := FLink;
  end
  else if not FRunStarted then
  begin
    Result := rsNoStart;
    AColor := FErrorColor;
  end
  else if FRunKilled then
  begin
    Result := rsStopped;
    AColor := FDim;
  end
  else if FExitCode = 0 then
  begin
    Result := rsExitOk;
    AColor := FOk;
  end
  else
  begin
    Result := Format(rsExitCode, [FExitCode]);
    AColor := FErrorColor;
  end;
end;

{ The index of the command that ran last, for Run Again; -1 when it is
  gone or leads nowhere now. }
function TGittanCommandPage.RunIndex: integer;
var
  i: integer;
begin
  for i := 0 to High(FCommands) do
    if IsRun(FCommands[i]) and (FCommands[i].Command <> '') then
    begin
      if (FCommands[i].Source = csFile) and not FTrusted then
        Exit(-1);
      Exit(i);
    end;
  Result := -1;
end;

{ A button: AFill, a shade lighter under the mouse, ACaption in
  ATextColor; clNone as the fill draws an outline in the divider color. }
procedure TGittanCommandPage.PaintButton(const R: TRect; const ACaption, ALink: string;
  AFill, ATextColor: TColor);
var
  Hot: boolean;
begin
  AddLink(R, ALink);
  Hot := FHot = High(FLinkRects);
  if AFill = clNone then
  begin
    FC.Pen.Style := psSolid;
    FC.Pen.Color := FLine;
    if Hot then
    begin
      FC.Brush.Style := bsSolid;
      FC.Brush.Color := FHover;
    end
    else
      FC.Brush.Style := bsClear;
  end
  else
  begin
    FC.Pen.Style := psClear;
    FC.Brush.Style := bsSolid;
    if Hot then
      FC.Brush.Color := MixColor(AFill, FText, 0.2)
    else
      FC.Brush.Color := AFill;
  end;
  FC.RoundRect(R, Px(ChipRadius) * 2, Px(ChipRadius) * 2);
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;
  FC.Font := Font;
  FC.Font.Color := ATextColor;
  FC.TextOut(R.Left + (R.Width - FC.TextWidth(ACaption)) div 2,
    R.Top + (R.Height - FC.TextHeight(ACaption)) div 2, ACaption);
end;

{ The mark of the state in a square of ASize at X, Y: a dot while it
  runs (faint every other tick, so it pulses), a tick when it is done, a
  cross when it failed or could not start, a square when it was
  stopped. }
procedure TGittanCommandPage.PaintStateMark(X, Y, ASize: integer; AColor: TColor);
var
  W: integer;
begin
  W := Max(2, Px(2));
  if FRunning and not FStopping then
  begin
    FC.Pen.Style := psClear;
    FC.Brush.Style := bsSolid;
    if FPulse then
      FC.Brush.Color := MixColor(AColor, FCard, 0.6)
    else
      FC.Brush.Color := AColor;
    FC.Ellipse(X + 1, Y + 1, X + ASize - 1, Y + ASize - 1);
  end
  else if FRunKilled or FStopping then
  begin
    FC.Pen.Style := psClear;
    FC.Brush.Style := bsSolid;
    FC.Brush.Color := AColor;
    FC.Rectangle(X + 2, Y + 2, X + ASize - 2, Y + ASize - 2);
  end
  else
  begin
    FC.Pen.Style := psSolid;
    FC.Pen.Width := W;
    FC.Pen.Color := AColor;
    if FRunStarted and (FExitCode = 0) then
      FC.PolyLine([Point(X + 1, Y + ASize div 2), Point(X + ASize * 2 div 5, Y + ASize - 2),
        Point(X + ASize - 1, Y + 2)])
    else
    begin
      FC.Line(X + 2, Y + 2, X + ASize - 2, Y + ASize - 2);
      FC.Line(X + ASize - 2, Y + 2, X + 2, Y + ASize - 2);
    end;
    FC.Pen.Width := 1;
  end;
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;
end;

{ A terminal in a box ASize wide at X, Y, as the sidebar's Commands
  row has it: a window with a prompt's chevron and a cursor line. }
procedure TGittanCommandPage.PaintTerminalIcon(X, Y, ASize: integer; AColor: TColor);
var
  H, Mid, MidY: integer;
begin
  H := ASize * TermH div TermW;
  FC.Pen.Style := psSolid;
  FC.Pen.Width := 1;
  FC.Pen.Color := AColor;
  FC.Brush.Style := bsClear;
  FC.RoundRect(X, Y, X + ASize, Y + H, 3, 3);
  Mid := X + ASize * 2 div 7;
  MidY := Y + H div 2;
  FC.Polyline([Point(Mid, MidY - H div 5), Point(Mid + H div 5, MidY),
    Point(Mid, MidY + H div 5)]);
  FC.Line(X + ASize div 2, Y + H * 5 div 7, X + ASize - 3, Y + H * 5 div 7);
end;

{ The output's panel: the bar with the state, the name, the time and
  the buttons, over the console, which fills the box down to its
  bottom when there is room for ConsoleMinHeight. }
procedure TGittanCommandPage.PaintOutput(var Y: integer);
var
  PL, PR, PT, BarH, BtnH, TextH, X, Right, MarkS, PillW, ConsoleH, Elapsed, BtnW: integer;
  State, Time: string;
  StateColor, Border: TColor;
  R, Pill: TRect;
begin
  Inc(Y, Px(Pad));
  FOutputTop := Y;
  PL := Px(Pad);
  PR := Width - Px(Pad);
  PT := Y;
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  BtnH := TextH + 2 * Px(ButtonPadY);
  BarH := BtnH + 2 * Px(BarPad);
  State := RunState(StateColor);
  if FRunning then
    Elapsed := GetTickCount64 - FRunStart
  else
    Elapsed := FElapsedMs;
  if FRunStarted then
    Time := FormatElapsed(Elapsed)
  else
    Time := '';
  ConsoleH := Max(Px(ConsoleMinHeight), FBoxHeight - (PT + BarH + 1) - Px(Pad) -
    Px(TileRadius) div 2);

  { The frame in the page's color, the console's, with the bar on top
    in the card's. }
  if FRunning and not FStopping then
    Border := FLink
  else
    Border := MixColor(FCard, FLine, 0.5);
  R := Rect(PL, PT, PR, PT + BarH + 1 + ConsoleH + Px(TileRadius) div 2);
  FC.Pen.Style := psSolid;
  FC.Pen.Color := Border;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FBack;
  FC.RoundRect(R, Px(TileRadius), Px(TileRadius));
  FC.Pen.Style := psClear;
  FC.Brush.Color := FCard;
  FC.RoundRect(PL + 1, PT + 1, PR - 1, PT + BarH + Px(TileRadius), Px(TileRadius) - 1,
    Px(TileRadius) - 1);
  FC.Brush.Color := FBack;
  FC.FillRect(Rect(PL + 1, PT + BarH, PR - 1, PT + BarH + Px(TileRadius) + 1));
  FC.Pen.Style := psSolid;
  FC.Pen.Color := Border;
  FC.Line(PL, PT + BarH, PR, PT + BarH);
  FC.Brush.Style := bsClear;

  { The buttons, from the right. }
  Right := PR - Px(BarPad);
  if FRunning then
  begin
    if not FStopping and Assigned(FOnStop) then
    begin
      BtnW := FC.TextWidth(rsStop) + 2 * Px(ButtonPadX) + Px(8);
      PaintButton(Rect(Right - BtnW, PT + Px(BarPad), Right, PT + Px(BarPad) + BtnH),
        rsStop, StopLink, FErrorColor, clWhite);
      Dec(Right, BtnW + Px(Gap) div 2);
    end;
  end
  else
  begin
    if Assigned(FOnCopyOutput) then
    begin
      BtnW := FC.TextWidth(rsCopy) + 2 * Px(ButtonPadX);
      PaintButton(Rect(Right - BtnW, PT + Px(BarPad), Right, PT + Px(BarPad) + BtnH),
        rsCopy, CopyLink, clNone, FText);
      Dec(Right, BtnW + Px(Gap) div 2);
    end;
    if Assigned(FOnRun) and (RunIndex >= 0) then
    begin
      BtnW := FC.TextWidth(rsRunAgain) + 2 * Px(ButtonPadX);
      PaintButton(Rect(Right - BtnW, PT + Px(BarPad), Right, PT + Px(BarPad) + BtnH),
        rsRunAgain, AgainLink, FLink, FBack);
      Dec(Right, BtnW + Px(Gap) div 2);
    end;
  end;

  { The pill: the mark and the state, in the state's color on a tint
    of it. }
  FC.Font := Font;
  FC.Font.Style := [fsBold];
  MarkS := Px(10);
  X := PL + Px(BarPad) + Px(4);
  PillW := Px(ButtonPadX) + MarkS + Px(6) + FC.TextWidth(State) + Px(ButtonPadX);
  Pill := Rect(X, PT + Px(BarPad), X + PillW, PT + Px(BarPad) + BtnH);
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := MixColor(FCard, StateColor, 0.18);
  FC.RoundRect(Pill, BtnH, BtnH);
  FC.Brush.Style := bsClear;
  PaintStateMark(Pill.Left + Px(ButtonPadX), Pill.Top + (BtnH - MarkS) div 2, MarkS, StateColor);
  FC.Font.Color := StateColor;
  FC.TextOut(Pill.Left + Px(ButtonPadX) + MarkS + Px(6), Pill.Top + (BtnH - TextH) div 2, State);

  { The command's name, its time after it. }
  X := Pill.Right + Px(Gap);
  FC.Font.Color := FText;
  FC.TextOut(X, Pill.Top + (BtnH - TextH) div 2, FitTextRight(FC, FRunName,
    Max(0, Right - Px(Gap) - X)));
  Inc(X, FC.TextWidth(FRunName));
  FC.Font.Style := [];
  if (Time <> '') and (X + FC.TextWidth(' · ' + Time) < Right - Px(Gap)) then
  begin
    FC.Font.Color := FDim;
    FC.TextOut(X, Pill.Top + (BtnH - TextH) div 2, ' · ' + Time);
  end;

  R := Rect(PL + Px(BarPad), PT + BarH + Px(4), PR - Px(4), PT + BarH + 1 + ConsoleH);
  if FConsole.BoundsRect <> R then
    FConsole.BoundsRect := R;
  Y := R.Bottom + Px(TileRadius) div 2;
end;

procedure TGittanCommandPage.Paint;
begin
  FC := Canvas;
  PaintContent;
end;

{ A commands file's tiles, under a note in the error color when it is
  no TOML. }
procedure TGittanCommandPage.PaintFileSection(var Y: integer; const AFile: TGittanCommandsFile);
begin
  if AFile.Error <> '' then
    PaintNote(Y, Format(rsNotToml, [AFile.Error]), FErrorColor);
  if GroupCount(csFile, AFile.Path) > 0 then
    PaintTiles(Y, csFile, AFile.Path);
end;

procedure TGittanCommandPage.PaintContent;
var
  Y, TextH, TitleH, HeadingTop, X, i: integer;
  Main: boolean;
begin
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FBack;
  FC.FillRect(Rect(0, 0, Width, Height));
  FLinkRects := nil;
  FLinkUrls := nil;
  FLinkHints := nil;
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

  { The files' commands under Commands, commands.toml's there and each
    other file's in a section of its own, with the trust card over them while they are not trusted;
    with no commands at all the page says so here. }
  HeadingTop := Y;
  Main := (Length(FFiles) > 0) and (FFiles[0].Path = CommandsPath);
  PaintHeading(Y, rsFileGroup, CommandsPath, '', FDim);
  if Assigned(FOnEditFile) then
    if Main then
      PaintAction(HeadingTop + Px(Pad), rsEditFile, EditLink)
    else
      PaintAction(HeadingTop + Px(Pad), rsCreateFile, EditLink);
  if (Length(FFiles) > 0) and not FTrusted then
    PaintTrustCard(Y);
  if Main then
    PaintFileSection(Y, FFiles[0]);
  if Length(FCommands) = 0 then
    PaintNote(Y, rsNoCommands);
  for i := Ord(Main) to High(FFiles) do
  begin
    PaintHeading(Y, ChangeFileExt(ExtractFileName(FFiles[i].Path), ''), FFiles[i].Path, '', FDim);
    PaintFileSection(Y, FFiles[i]);
  end;

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
  { A section per kind of project, its name over the file that told
    it; a kind the commands file asked for with no file says so. }
  for i := 0 to High(FProjects) do
    if GroupCount(csProject, FProjects[i].Name) > 0 then
    begin
      if FProjects[i].Manifest <> '' then
        PaintHeading(Y, FProjects[i].Name, FProjects[i].Manifest, '', FDim)
      else
        PaintHeading(Y, FProjects[i].Name, rsNoManifest, '', FDim);
      PaintTiles(Y, csProject, FProjects[i].Name);
    end;

  { The output of the last run, in its panel. }
  FOutputTop := -1;
  if FHasRun then
    PaintOutput(Y);

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
  else if Copy(FLinkUrls[i], 1, Length(TerminalLink)) = TerminalLink then
  begin
    n := StrToIntDef(Copy(FLinkUrls[i], Length(TerminalLink) + 1, MaxInt), -1);
    if Assigned(FOnRunInTerminal) and (n >= 0) and (n <= High(FCommands)) then
      FOnRunInTerminal(Self, n);
  end
  else if FLinkUrls[i] = AgainLink then
  begin
    n := RunIndex;
    if Assigned(FOnRun) and (n >= 0) then
      FOnRun(Self, n);
  end
  else if FLinkUrls[i] = StopLink then
  begin
    if Assigned(FOnStop) then
    begin
      FStopping := True;
      FOnStop(Self);
      Invalidate;
    end;
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
