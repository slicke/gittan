unit gittan.welcome;

{** The welcome view: what Gittan shows while no repository is open, and
  where a failure to open one is reported. Under the wordmark (the icon
  beside the name and the tagline, gittan.app's lockup, from
  icons/wordmark/gittan-wordmark-<theme>.png, the dark one on a dark
  background; the title and the tagline as text when it cannot be
  read) it offers a button that opens the folder dialog, filled in the
  accent with the shortcut drawn as key caps inside it, one that clones a
  repository and one that makes a new one (the three in a row as wide as
  the column, or under each other when the row does not fit), says under
  them that a folder can be dropped, and lists the repository list
  (gittan.repolist, App.RepoList) and the recent repositories as rows to
  click, each repository with its name and path; a repository whose
  folder is gone is listed dimmed, says so, and does not react.

  The repository list is a tree: a folder's row folds it in and out on a
  click, a repository's opens it. A row of the list, or a recent one, can
  be dragged to another place in the list (into a folder when dropped on
  its row's middle, before or after a row else), which moves it there or
  adds it; a right-click on the list, on its + or on a recent row asks
  the frame for the menu (OnListMenu). What the view changes itself it
  tells with OnListChanged, for the frame to save and show everywhere. An error is shown in red
  under the name, wrapped to the column, so the next attempt is one click
  or one drop away. While a repository opens it shows only that, in place
  of the error, the buttons and the list, with the status bar's busy line
  under it once the open has taken BusyDelay.

  It paints itself in the editor's palette, like the summary, and sizes
  its height to its content so it can sit in the same TScrollBox: the
  block is centered while there is room and the box scrolls when there
  is not. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, ExtCtrls, BGRABitmap, gittan.repolist;

type
  {** A click on a recent repository, with its root. }
  TGittanOpenRecentEvent = procedure(Sender: TObject; const ARoot: string) of object;
  {** A right-click at the screen's APos: on AEntry of the repository list,
    on the recent repository ARoot, or on neither (the list's heading, its
    + or what is left of it). }
  TGittanListMenuEvent = procedure(Sender: TObject; AEntry: TGittanRepoEntry;
    const ARoot: string; const APos: TPoint) of object;

  {** Where a drag would put what it carries in the repository list. }
  TGittanListDrop = record
    Valid, Into: boolean;
    Folder: TGittanRepoEntry;
    Index: integer;
    { The row filled for Into, else the line drawn. }
    Mark: TRect;
  end;

  { TGittanWelcome }

  TGittanWelcome = class(TCustomControl)
  private
    FTitle, FTagline, FError, FShortcut, FBusy: string;
    FRecent: TStringList;
    FList: TGittanRepoList;
    { The list's rows and where the last paint put them, the area a drop
      lands in and the + over it. }
    FRows: TGittanRepoRows;
    FListRects: array of TRect;
    FListArea, FAddRect: TRect;
    FListTop: integer;
    { The row the left button went down on (a HitAt value), where, and
      the drag it started: the entry or the recent root carried. }
    FDown: integer;
    FDownPos: TPoint;
    FDragging: boolean;
    FDragEntry: TGittanRepoEntry;
    FDragRoot: string;
    FDrop: TGittanListDrop;
    { The wordmark for the background and the screen's pixels, made in
      the first paint after a change; FLogoFailed when it could not be. }
    FLogo: TBGRABitmap;
    FLogoFailed: boolean;
    FBack, FText, FDim, FHover, FLine, FErrorColor, FAccent: TColor;
    { What the mouse is over: hotNone, a button (hotButton less its
      index) or a row's index. }
    FHot: integer;
    FButtonRects: array[0..2] of TRect;
    FRowRects: array of TRect;
    FContentHeight, FLaidWidth: integer;
    { The canvas Render measures on: the control's as it paints, else the
      measuring one. }
    FC: TCanvas;
    { The busy line: its timer, the step it is at (-1 until BusyDelay
      has passed since SetBusy, FBusyStart), and where the last paint
      put it, which a tick paints alone. }
    FBusyTimer: TTimer;
    FBusyPhase: integer;
    FBusyStart: QWord;
    FBusyRect: TRect;
    FOnOpen, FOnClone, FOnInit: TNotifyEvent;
    FOnOpenRecent: TGittanOpenRecentEvent;
    FOnListMenu: TGittanListMenuEvent;
    FOnListChanged: TNotifyEvent;
    function HitAt(X, Y: integer; AMissing: boolean): integer;
    function HotAt(X, Y: integer): integer;
    function ListMissing(AIndex: integer): boolean;
    procedure ComputeDrop(X, Y: integer);
    procedure EndDrag;
    procedure Changed;
    function ListHeight(ALineHeight: integer): integer;
    function FoldedHeight(AFolder: TGittanRepoEntry; AHidden: boolean): integer;
    procedure PaintRepoRow(const R: TRect; ALeft, ARight: integer; const AName,
      APath: string; AHot, AMissing: boolean; ALineHeight: integer);
    procedure PaintList(var Y: integer; AColLeft, AColWidth, ALineHeight: integer);
    procedure SetHot(AValue: integer);
    procedure BusyTimerTimer(Sender: TObject);
    function RecentMissing(AIndex: integer): boolean;
    function FitLeft(const AText: string; AMaxWidth: integer): string;
    function LogoBitmap(APixels: integer): TBGRABitmap;
    procedure WrapError(AWidth: integer; ALines: TStrings);
    procedure Render(ADraw: boolean);
    procedure Layout;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** The recent repositories, most recent first; a copy is kept. }
    procedure SetRecent(ARoots: TStrings);
    {** The repository list to show, nil for none; it is not copied, so
      ListChanged must follow every change of it. }
    procedure SetRepoList(AList: TGittanRepoList);
    {** The repository list changed: its rows are read again. }
    procedure ListChanged;
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
    {** A right-click on the repository list or a recent repository. }
    property OnListMenu: TGittanListMenuEvent read FOnListMenu write FOnListMenu;
    {** The view changed the repository list: a folder folded, or a
      drag moved or added a repository. }
    property OnListChanged: TNotifyEvent read FOnListChanged write FOnListChanged;
  end;

implementation

uses
  Math, LazUTF8, LCLIntf, BGRABitmapTypes, gittan.statusbar,
  gittan.textfit, gittan.theme;

{ WordmarkDark and WordmarkLight, icons/wordmark/gittan-wordmark-<theme>.png
  as byte arrays (make wordmark). }
{$I gittan.wordmark.inc}

resourcestring
  rsOpenButton = 'Open Repository…';
  rsCloneButton = 'Clone…';
  rsInitButton = 'Init…';
  rsRecent = 'Recent';
  rsRepositories = 'Repositories';
  rsListEmpty = 'Drag a recent repository here, or add one with +';
  rsNotFound = 'not found';
  rsDrop = 'or drop a folder or file here';

const
  { What HitAt finds: nothing, a button (hotButton less its index), the
    list's +, a row of the list (hotList less its index) or a recent
    row's index. }
  hotNone = -1;
  hotButton = -2;
  hotAdd = -5;
  hotList = -100;
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
  FolderRowHeight = 30;
  Indent = 20;
  DragStart = 5;
  { The busy line under the opening's text: shown once an open has
    taken this many ms, so a quick one does not flash it; its width and
    height. }
  BusyDelay = 400;
  BusyWidth = 120;
  BusyHeight = 3;

{ TGittanWelcome }

constructor TGittanWelcome.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FRecent := TStringList.Create;
  FHot := hotNone;
  FDown := hotNone;
  Align := alTop;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnShadow, clRed);
  FAccent := clHighlight;
  FBusyTimer := TTimer.Create(Self);
  FBusyTimer.Enabled := False;
  FBusyTimer.Interval := BusyStep;
  FBusyTimer.OnTimer := @BusyTimerTimer;
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
  Layout;
  Invalidate;
end;

procedure TGittanWelcome.SetRepoList(AList: TGittanRepoList);
begin
  FList := AList;
  ListChanged;
end;

procedure TGittanWelcome.ListChanged;
begin
  EndDrag;
  if FList <> nil then
    FRows := FList.Rows
  else
    FRows := nil;
  { The rows of the last paint are not these, and an entry they named may
    be gone. }
  FListRects := nil;
  FDown := hotNone;
  FHot := hotNone;
  Cursor := crDefault;
  Layout;
  Invalidate;
end;

procedure TGittanWelcome.Changed;
begin
  ListChanged;
  if Assigned(FOnListChanged) then
    FOnListChanged(Self);
end;

procedure TGittanWelcome.SetError(const AMessage: string);
begin
  if FError = AMessage then
    Exit;
  FError := AMessage;
  Layout;
  Invalidate;
end;

procedure TGittanWelcome.SetBusy(const AMessage: string);
begin
  if FBusy = AMessage then
    Exit;
  FBusy := AMessage;
  FBusyPhase := -1;
  FBusyStart := GetTickCount64;
  FBusyRect := Rect(0, 0, 0, 0);
  FBusyTimer.Enabled := AMessage <> '';
  FHot := hotNone;
  Cursor := crDefault;
  Layout;
  Invalidate;
end;

procedure TGittanWelcome.BusyTimerTimer(Sender: TObject);
begin
  if FBusyPhase < 0 then
  begin
    if GetTickCount64 - FBusyStart < BusyDelay then
      Exit;
    FBusyPhase := 0;
  end
  else
    FBusyPhase := (FBusyPhase + 1) mod BusySweep;
  if not IsVisible then
    Exit;
  if HandleAllocated and not IsRectEmpty(FBusyRect) then
    InvalidateRect(Handle, @FBusyRect, False)
  else
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
  Layout;
end;

function TGittanWelcome.RecentMissing(AIndex: integer): boolean;
begin
  Result := not DirectoryExists(FRecent[AIndex]);
end;

function TGittanWelcome.ListMissing(AIndex: integer): boolean;
begin
  Result := not FRows[AIndex].Entry.IsFolder and
    not DirectoryExists(FRows[AIndex].Entry.Path);
end;

{ What is at X, Y; a repository whose folder is gone only when
  AMissing. }
function TGittanWelcome.HitAt(X, Y: integer; AMissing: boolean): integer;
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
  if PtInRect(FAddRect, P) then
    Exit(hotAdd);
  for i := 0 to High(FListRects) do
    if (i < Length(FRows)) and PtInRect(FListRects[i], P) and
      (AMissing or not ListMissing(i)) then
      Exit(hotList - i);
  for i := 0 to High(FRowRects) do
    if (i < FRecent.Count) and PtInRect(FRowRects[i], P) and
      (AMissing or not RecentMissing(i)) then
      Exit(i);
  Result := hotNone;
end;

function TGittanWelcome.HotAt(X, Y: integer): integer;
begin
  Result := HitAt(X, Y, False);
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

{ The wordmark APixels wide for the background, the dark one on a dark
  background, kept until the colors or the width change; nil when its
  PNG could not be read. }
function TGittanWelcome.LogoBitmap(APixels: integer): TBGRABitmap;
var
  Stream: TMemoryStream;
  Png: TBGRABitmap;
  C: TColor;
begin
  if (FLogo <> nil) and (FLogo.Width = APixels) then
    Exit(FLogo);
  FreeAndNil(FLogo);
  if FLogoFailed then
    Exit(nil);
  Png := nil;
  Stream := TMemoryStream.Create;
  try
    try
      C := ColorToRGB(FBack);
      if Red(C) * 299 + Green(C) * 587 + Blue(C) * 114 < 128000 then
        Stream.WriteBuffer(WordmarkDark[0], Length(WordmarkDark))
      else
        Stream.WriteBuffer(WordmarkLight[0], Length(WordmarkLight));
      Stream.Position := 0;
      Png := TBGRABitmap.Create(Stream);
      Png.ResampleFilter := rfBestQuality;
      FLogo := Png.Resample(APixels, Max(1, Round(APixels * Png.Height / Png.Width)),
        rmFineResample) as TBGRABitmap;
    except
      FreeAndNil(FLogo);
      FLogoFailed := True;
    end;
  finally
    Png.Free;
    Stream.Free;
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
    if (Line <> '') and (FC.TextWidth(Line + ' ' + Word) <= AWidth) then
    begin
      Line := Line + ' ' + Word;
      Continue;
    end;
    if Line <> '' then
      ALines.Add(Line);
    Line := Word;
    while FC.TextWidth(Line) > AWidth do
    begin
      { The longest head that fits, of whole characters, ending after
        a slash when one is there; a head of at least one character, so
        the loop ends. }
      Head := UTF8Copy(Line, 1, FittingChars(FC, Line, UTF8Length(Line), AWidth));
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

{ The height of the list's part: the gap and the heading over the divider,
  then its rows, or the line that says how to fill it. }
function TGittanWelcome.ListHeight(ALineHeight: integer): integer;
var
  i: integer;
begin
  Result := Px(RecentGap) + ALineHeight + Px(Gap) div 2 + 1 + Px(Gap) div 2;
  if Length(FRows) = 0 then
    Inc(Result, Px(FolderRowHeight));
  for i := 0 to High(FRows) do
    if FRows[i].Entry.IsFolder then
      Inc(Result, Px(FolderRowHeight))
    else
      Inc(Result, Px(RowHeight));
end;

{ How much taller the list would be with every folder open: the rows
  inside AFolder hidden by a collapsed folder (all of them when
  AHidden). }
function TGittanWelcome.FoldedHeight(AFolder: TGittanRepoEntry; AHidden: boolean): integer;
var
  i: integer;
  E: TGittanRepoEntry;
begin
  Result := 0;
  for i := 0 to AFolder.Count - 1 do
  begin
    E := AFolder[i];
    if AHidden then
      if E.IsFolder then
        Inc(Result, Px(FolderRowHeight))
      else
        Inc(Result, Px(RowHeight));
    if E.IsFolder then
      Inc(Result, FoldedHeight(E, AHidden or E.Collapsed));
  end;
end;

{ A repository's row in R, its folder at ALeft and its text up to ARight:
  the name over the path, "not found" at the right of the name's line
  when the folder is gone; filled when hot. }
procedure TGittanWelcome.PaintRepoRow(const R: TRect; ALeft, ARight: integer;
  const AName, APath: string; AHot, AMissing: boolean; ALineHeight: integer);
var
  X, TextY, Spare: integer;
begin
  if AHot then
  begin
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FHover;
    Canvas.RoundRect(R, Px(ButtonRound), Px(ButtonRound));
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsClear;
  end;
  DrawStatusIcon(Canvas, HintFolder, ALeft, R.Top + (R.Height - Px(FolderSize)) div 2,
    Px(FolderSize), FDim);
  Canvas.Brush.Style := bsClear;
  X := ALeft + Px(FolderSize) + Px(Gap);
  TextY := R.Top + (R.Height - 2 * ALineHeight) div 2;
  Spare := ARight;
  Canvas.Font.Color := FDim;
  if AMissing then
  begin
    Dec(Spare, Canvas.TextWidth(rsNotFound));
    Canvas.TextOut(Spare, TextY, rsNotFound);
    Dec(Spare, Px(Gap));
  end
  else
    Canvas.Font.Color := FText;
  Canvas.TextOut(X, TextY, FitTextRight(Canvas, AName, Spare - X));
  Canvas.Font.Color := FDim;
  Canvas.TextOut(X, TextY + ALineHeight, FitLeft(APath, ARight - X));
end;

{ The repository list from Y on: the dim heading with the + at its right
  over a divider, then a row per entry shown, a folder's with a chevron
  (pointing down while open), its name and how many repositories it
  holds, a repository's as a recent one's, both indented by depth; the
  line that says how to fill it while it is empty; and where a drag would
  drop. }
procedure TGittanWelcome.PaintList(var Y: integer; AColLeft, AColWidth,
  ALineHeight: integer);
var
  i, X, H, CX, CY, S: integer;
  E: TGittanRepoEntry;
  R: TRect;
  Count: string;
begin
  SetLength(FListRects, Length(FRows));
  FAddRect := Rect(0, 0, 0, 0);
  FListArea := FAddRect;
  if FList = nil then
    Exit;
  Inc(Y, Px(RecentGap));
  FListTop := Y;
  Canvas.Font.Color := FDim;
  Canvas.TextOut(AColLeft, Y, rsRepositories);
  { The + as a small button at the heading's right. }
  S := ALineHeight + 2 * Px(KeyPadY);
  FAddRect := Rect(AColLeft + AColWidth - S, Y - Px(KeyPadY), AColLeft + AColWidth,
    Y - Px(KeyPadY) + S);
  if FHot = hotAdd then
  begin
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FHover;
    Canvas.RoundRect(FAddRect, Px(6), Px(6));
    Canvas.Pen.Style := psSolid;
  end;
  CX := (FAddRect.Left + FAddRect.Right) div 2;
  CY := (FAddRect.Top + FAddRect.Bottom) div 2;
  Canvas.Pen.Color := FDim;
  Canvas.Pen.Width := Max(1, Px(2) div 2 + 1);
  Canvas.Line(CX - S div 4, CY, CX + S div 4 + 1, CY);
  Canvas.Line(CX, CY - S div 4, CX, CY + S div 4 + 1);
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  Inc(Y, ALineHeight + Px(Gap) div 2);
  Canvas.Pen.Color := FLine;
  Canvas.Line(AColLeft, Y, AColLeft + AColWidth, Y);
  Inc(Y, 1 + Px(Gap) div 2);
  FListArea := Rect(AColLeft - Px(RowPadX), Y, AColLeft + AColWidth + Px(RowPadX), Y);

  if Length(FRows) = 0 then
  begin
    H := Px(FolderRowHeight);
    Canvas.Font.Color := FDim;
    Canvas.TextOut(AColLeft, Y + (H - ALineHeight) div 2,
      FitTextRight(Canvas, rsListEmpty, AColWidth));
    Inc(Y, H);
  end;
  for i := 0 to High(FRows) do
  begin
    E := FRows[i].Entry;
    X := AColLeft + FRows[i].Depth * Px(Indent);
    if E.IsFolder then
      H := Px(FolderRowHeight)
    else
      H := Px(RowHeight);
    R := Rect(X - Px(RowPadX), Y, AColLeft + AColWidth + Px(RowPadX), Y + H);
    FListRects[i] := R;
    if E.IsFolder then
    begin
      if FHot = hotList - i then
      begin
        Canvas.Pen.Style := psClear;
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := FHover;
        Canvas.RoundRect(R, Px(ButtonRound), Px(ButtonRound));
        Canvas.Pen.Style := psSolid;
        Canvas.Brush.Style := bsClear;
      end;
      { The chevron in the folder icon's place, a repository's. }
      CX := X + Px(FolderSize) div 2;
      CY := Y + H div 2;
      Canvas.Pen.Color := FDim;
      Canvas.Pen.Width := Max(1, Px(3) div 2);
      if E.Collapsed then
        Canvas.Polyline([Point(CX - Px(2), CY - Px(4)), Point(CX + Px(2), CY),
          Point(CX - Px(2), CY + Px(4))])
      else
        Canvas.Polyline([Point(CX - Px(4), CY - Px(2)), Point(CX, CY + Px(2)),
          Point(CX + Px(4), CY - Px(2))]);
      Canvas.Pen.Width := 1;
      Count := IntToStr(E.RepoCount);
      Canvas.Font.Color := FDim;
      Canvas.TextOut(AColLeft + AColWidth - Canvas.TextWidth(Count),
        Y + (H - ALineHeight) div 2, Count);
      Canvas.Font.Style := [fsBold];
      Canvas.Font.Color := FText;
      S := X + Px(FolderSize) + Px(Gap);
      Canvas.TextOut(S, Y + (H - ALineHeight) div 2, FitTextRight(Canvas, E.Caption,
        AColLeft + AColWidth - Canvas.TextWidth(Count) - Px(Gap) - S));
      Canvas.Font.Style := [];
    end
    else
      PaintRepoRow(R, X, AColLeft + AColWidth, E.Caption, E.Path,
        FHot = hotList - i, ListMissing(i), ALineHeight);
    Inc(Y, H);
  end;
  FListArea.Bottom := Y;

  if FDragging and FDrop.Valid then
  begin
    Canvas.Pen.Color := FAccent;
    if FDrop.Into then
    begin
      Canvas.Pen.Width := 2;
      Canvas.Brush.Style := bsClear;
      Canvas.RoundRect(FDrop.Mark, Px(ButtonRound), Px(ButtonRound));
    end
    else
    begin
      Canvas.Pen.Width := 2;
      Canvas.Line(FDrop.Mark.Left, FDrop.Mark.Top, FDrop.Mark.Right, FDrop.Mark.Top);
    end;
    Canvas.Pen.Width := 1;
  end;
end;

{ Measures the content (FContentHeight) on the measuring canvas, or with
  ADraw paints it, on the control's. The two share the code, so the height
  set before a paint is the one the paint needs. }
procedure TGittanWelcome.Render(ADraw: boolean);
var
  ColLeft, ColWidth, Y, BlockTop, Total, LineHeight, TitleHeight, ErrHeight: integer;
  KeyWidth, X, TextY, i, RowWidth, ButtonHeight, ButtonRows, Spare, LogoW: integer;
  OpenNeed: integer;
  ButtonWidths: array[0..2] of integer;
  Captions: array[0..2] of string;
  Stacked: boolean;
  R: TRect;
  ErrLines: TStringList;
  Fill, Ink: TColor;
  Logo: TBGRABitmap;
  LogoHeight: integer;
begin
  if ADraw then
  begin
    FC := Canvas;
    FC.Brush.Style := bsSolid;
    FC.Brush.Color := FBack;
    FC.FillRect(ClientRect);
  end
  else
    FC := MeasureCanvas(Font);
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  LineHeight := FC.TextHeight('Xg');
  ColWidth := Min(Px(ColumnWidth), Width - 2 * Px(Pad));
  ColLeft := (Width - ColWidth) div 2;
  { The wordmark in the screen's pixels (twice its points on a Retina
    screen), which Cocoa then draws pixel for pixel; no wider than the
    column. }
  LogoW := Max(1, Min(Px(LogoWidth), ColWidth));
  Logo := LogoBitmap(Round(LogoW * GetCanvasScaleFactor));
  LogoHeight := 0;
  if Logo <> nil then
    LogoHeight := LogoW * Logo.Height div Logo.Width;

  { The block's height first, to place it: a little above the middle
    of the room, which looks centered, and never off the top. }
  FC.Font.Size := TitleFontSize;
  FC.Font.Style := [fsBold];
  TitleHeight := FC.TextHeight('Xg');
  FC.Font.Size := Font.Size;
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
    KeyWidth := FC.TextWidth(FShortcut) + 2 * Px(KeyPadX);
  RowWidth := 2 * Px(ButtonGap);
  for i := 0 to High(Captions) do
  begin
    ButtonWidths[i] := FC.TextWidth(Captions[i]) + 2 * Px(ButtonPadX);
    if (i = 0) and (KeyWidth > 0) then
      Inc(ButtonWidths[i], Px(Gap) + KeyWidth);
    Inc(RowWidth, ButtonWidths[i]);
  end;
  FC.Font.Style := [];
  OpenNeed := ButtonWidths[0];
  Stacked := RowWidth > ColWidth;
  if Stacked then
    for i := 0 to High(Captions) do
      ButtonWidths[i] := ColWidth
  else
    Inc(ButtonWidths[0], ColWidth - RowWidth);
  { A column too narrow for the open button's caption and its key cap
    drops the key cap rather than draw the caption over it. }
  if ButtonWidths[0] < OpenNeed then
    KeyWidth := 0;
  ButtonHeight := LineHeight + 2 * Px(ButtonPadY);
  if Stacked then
    ButtonRows := Length(Captions)
  else
    ButtonRows := 1;
  { The wordmark's tagline needs more room under it than the
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
    { The busy line's room is kept from the start, so the text does not
      move when it shows. }
    if FBusy <> '' then
      Inc(Total, Px(Pad) + LineHeight + Px(Gap) + Px(BusyHeight))
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
      if FList <> nil then
        Inc(Total, ListHeight(LineHeight));
      if FRecent.Count > 0 then
        Inc(Total, Px(RecentGap) + LineHeight + Px(Gap) div 2 + 1 + Px(Gap) div 2 +
          FRecent.Count * Px(RowHeight));
    end;
    FContentHeight := Total + 2 * Px(Pad);
    if not ADraw then
      Exit;
    { Placed as if every folder of the list were open, so folding one
      does not move the rows under the pointer. }
    Spare := Total;
    if FList <> nil then
      Inc(Spare, FoldedHeight(FList.Root, False));
    BlockTop := Max(Px(Pad), (Height - Spare) * 2 div 5);
    Y := BlockTop;

    if Logo <> nil then
    begin
      Logo.Draw(Canvas, Rect((Width - LogoW) div 2, Y,
        (Width + LogoW) div 2, Y + LogoHeight), False);
      Inc(Y, LogoHeight + Px(Gap));
    end
    else
    begin
      FC.Font.Size := TitleFontSize;
      FC.Font.Style := [fsBold];
      FC.Font.Color := FText;
      FC.TextOut((Width - FC.TextWidth(FTitle)) div 2, Y, FTitle);
      Inc(Y, TitleHeight + 2);
      FC.Font.Size := Font.Size;
      FC.Font.Style := [];
      if FTagline <> '' then
      begin
        FC.Font.Color := FDim;
        FC.TextOut((Width - FC.TextWidth(FTagline)) div 2, Y, FTagline);
        Inc(Y, LineHeight);
      end;
    end;

    if FBusy <> '' then
    begin
      for i := 0 to High(FButtonRects) do
        FButtonRects[i] := Rect(0, 0, 0, 0);
      FRowRects := nil;
      FListRects := nil;
      FAddRect := Rect(0, 0, 0, 0);
      FListArea := FAddRect;
      Inc(Y, Px(Pad));
      FC.Font.Color := FDim;
      FC.TextOut((Width - FC.TextWidth(FBusy)) div 2, Y, FBusy);
      Inc(Y, LineHeight + Px(Gap));
      FBusyRect := Rect((Width - Px(BusyWidth)) div 2, Y, (Width + Px(BusyWidth)) div 2,
        Y + Px(BusyHeight));
      if FBusyPhase >= 0 then
        DrawBusyTrack(FC, FBusyRect, FBusyPhase, FHover, FAccent);
      Exit;
    end;

    if FError <> '' then
    begin
      Inc(Y, Px(Gap));
      FC.Font.Color := FErrorColor;
      for i := 0 to ErrLines.Count - 1 do
        FC.TextOut((Width - FC.TextWidth(ErrLines[i])) div 2,
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
        FC.Pen.Style := psClear;
        FC.Brush.Style := bsSolid;
        FC.Brush.Color := Fill;
        FC.RoundRect(R, Px(ButtonRound), Px(ButtonRound));
        FC.Pen.Style := psSolid;
        Ink := clWhite;
      end
      else
      begin
        FC.Pen.Color := FLine;
        if FHot = hotButton - i then
        begin
          FC.Brush.Style := bsSolid;
          FC.Brush.Color := FHover;
        end
        else
          FC.Brush.Style := bsClear;
        FC.RoundRect(R, Px(ButtonRound), Px(ButtonRound));
        Ink := FText;
      end;
      FC.Brush.Style := bsClear;
      Spare := R.Right;
      TextY := Y + Px(ButtonPadY);
      if (i = 0) and (KeyWidth > 0) then
      begin
        { The shortcut as a key cap: a small rounded frame in a paler
          shade of the fill. }
        Spare := R.Right - Px(ButtonPadX) - KeyWidth;
        FC.Pen.Color := MixColor(FAccent, clWhite, 0.45);
        FC.RoundRect(Spare, TextY - Px(KeyPadY), R.Right - Px(ButtonPadX),
          TextY + LineHeight + Px(KeyPadY), Px(6), Px(6));
        FC.Font.Color := MixColor(FAccent, clWhite, 0.8);
        FC.TextOut(Spare + Px(KeyPadX), TextY, FShortcut);
        Dec(Spare, Px(Gap));
      end;
      FC.Font.Style := [fsBold];
      FC.Font.Color := Ink;
      FC.TextOut(R.Left + (Spare - R.Left - FC.TextWidth(Captions[i])) div 2,
        TextY, Captions[i]);
      FC.Font.Style := [];
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
    FC.Font.Color := FDim;
    FC.TextOut((Width - FC.TextWidth(rsDrop)) div 2, Y, rsDrop);
    Inc(Y, LineHeight);

    PaintList(Y, ColLeft, ColWidth, LineHeight);

    { The recent repositories: a dim heading over a divider, then a row
      per repository with the folder, the name and the path, and "not
      found" at the right of the name's line when the folder is gone. }
    SetLength(FRowRects, FRecent.Count);
    if FRecent.Count > 0 then
    begin
      Inc(Y, Px(RecentGap));
      FC.Font.Color := FDim;
      FC.TextOut(ColLeft, Y, rsRecent);
      Inc(Y, LineHeight + Px(Gap) div 2);
      FC.Pen.Color := FLine;
      FC.Line(ColLeft, Y, ColLeft + ColWidth, Y);
      Inc(Y, 1 + Px(Gap) div 2);
      for i := 0 to FRecent.Count - 1 do
      begin
        FRowRects[i] := Rect(ColLeft - Px(RowPadX), Y, ColLeft + ColWidth + Px(RowPadX), Y + Px(RowHeight));
        PaintRepoRow(FRowRects[i], ColLeft, ColLeft + ColWidth,
          ExtractFileName(ExcludeTrailingPathDelimiter(FRecent[i])), FRecent[i],
          FHot = i, RecentMissing(i), LineHeight);
        Inc(Y, Px(RowHeight));
      end;
    end;
  finally
    ErrLines.Free;
  end;
end;

procedure TGittanWelcome.Paint;
begin
  Render(True);
end;

{ The height the content needs, set before a paint: a TScrollBox under
  Cocoa scrolls wrong when a child grows in its paint. }
procedure TGittanWelcome.Layout;
begin
  Render(False);
  Height := Max(FContentHeight, Constraints.MinHeight);
end;

procedure TGittanWelcome.Resize;
begin
  inherited Resize;
  { The width decides whether the buttons stack and how the error wraps. }
  if FLaidWidth <> Width then
  begin
    FLaidWidth := Width;
    Layout;
  end;
end;

{ Where a drop at X, Y would put what is dragged: into a folder over the
  middle of its row; before a row over its upper half; after it over its
  lower half, which for an open folder with entries is before its first;
  at the end of the list under the last row or on the line of an empty
  list. Not valid outside the list or for a folder put inside itself. }
procedure TGittanWelcome.ComputeDrop(X, Y: integer);
var
  i, H, Depth: integer;
  R: TRect;
  E: TGittanRepoEntry;
begin
  FDrop.Valid := False;
  FDrop.Into := False;
  if (FList = nil) or not PtInRect(Rect(FListArea.Left, FListArea.Top,
    FListArea.Right, FListArea.Bottom + Px(Gap)), Point(X, Y)) then
    Exit;
  FDrop.Folder := FList.Root;
  FDrop.Index := -1;
  Depth := 0;
  FDrop.Mark := Rect(FListArea.Left + Px(RowPadX), FListArea.Bottom,
    FListArea.Right - Px(RowPadX), FListArea.Bottom);
  if Length(FRows) = 0 then
  begin
    FDrop.Into := True;
    FDrop.Mark := FListArea;
  end;
  for i := 0 to Min(High(FRows), High(FListRects)) do
  begin
    R := FListRects[i];
    if Y >= R.Bottom then
      Continue;
    E := FRows[i].Entry;
    Depth := FRows[i].Depth;
    H := R.Bottom - R.Top;
    if E.IsFolder and (Y >= R.Top + H div 4) and (Y < R.Bottom - H div 4) then
    begin
      FDrop.Folder := E;
      FDrop.Index := -1;
      FDrop.Into := True;
      FDrop.Mark := R;
    end
    else if Y < R.Top + H div 2 then
    begin
      FDrop.Folder := E.Parent;
      FDrop.Index := E.Parent.IndexOf(E);
      FDrop.Mark := Rect(R.Left + Px(RowPadX), R.Top, R.Right - Px(RowPadX), R.Top);
    end
    else
    begin
      if E.IsFolder and not E.Collapsed and (E.Count > 0) then
      begin
        FDrop.Folder := E;
        FDrop.Index := 0;
        Inc(Depth);
      end
      else
      begin
        FDrop.Folder := E.Parent;
        FDrop.Index := E.Parent.IndexOf(E) + 1;
      end;
      FDrop.Mark := Rect(FListArea.Left + Px(RowPadX) + Depth * Px(Indent), R.Bottom,
        R.Right - Px(RowPadX), R.Bottom);
    end;
    Break;
  end;
  FDrop.Valid := (FDragEntry = nil) or not FDragEntry.Contains(FDrop.Folder);
end;

procedure TGittanWelcome.EndDrag;
begin
  if FDragging then
  begin
    FDragging := False;
    Cursor := crDefault;
    Invalidate;
  end;
  FDragEntry := nil;
  FDragRoot := '';
  FDrop.Valid := False;
end;

procedure TGittanWelcome.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Hit: integer;
  E: TGittanRepoEntry;
  Root: string;
begin
  inherited MouseDown(Button, Shift, X, Y);
  Hit := HitAt(X, Y, True);
  if Button = mbLeft then
  begin
    FDown := Hit;
    FDownPos := Point(X, Y);
    Exit;
  end;
  if (Button <> mbRight) or (FBusy <> '') or (FList = nil) or
    not Assigned(FOnListMenu) then
    Exit;
  E := nil;
  Root := '';
  if Hit <= hotList then
    E := FRows[hotList - Hit].Entry
  else if Hit >= 0 then
    Root := FRecent[Hit]
  else if (Hit <> hotAdd) and not PtInRect(Rect(FListArea.Left, FListTop,
    FListArea.Right, FListArea.Bottom), Point(X, Y)) then
    Exit;
  FOnListMenu(Self, E, Root, ClientToScreen(Point(X, Y)));
end;

procedure TGittanWelcome.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  if (ssLeft in Shift) and (FDown <> hotNone) and (FList <> nil) and not FDragging and
    ((FDown <= hotList) or ((FDown >= 0) and not RecentMissing(FDown))) and
    (Max(Abs(X - FDownPos.X), Abs(Y - FDownPos.Y)) >= Px(DragStart)) then
  begin
    FDragging := True;
    if FDown <= hotList then
      FDragEntry := FRows[hotList - FDown].Entry
    else
      FDragRoot := FRecent[FDown];
    SetHot(hotNone);
  end;
  if FDragging then
  begin
    ComputeDrop(X, Y);
    if FDrop.Valid then
      Cursor := crDrag
    else
      Cursor := crNoDrop;
    Invalidate;
    Exit;
  end;
  SetHot(HotAt(X, Y));
end;

procedure TGittanWelcome.MouseLeave;
begin
  inherited MouseLeave;
  if not FDragging then
    SetHot(hotNone);
end;

procedure TGittanWelcome.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Hit, Down: integer;
  E: TGittanRepoEntry;
  Drop: TGittanListDrop;
  Moved: boolean;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  Down := FDown;
  FDown := hotNone;
  if FDragging then
  begin
    ComputeDrop(X, Y);
    Drop := FDrop;
    E := FDragEntry;
    if (E = nil) and Drop.Valid then
      E := FList.Find(FDragRoot);
    Moved := False;
    if Drop.Valid then
      if E <> nil then
        Moved := FList.Move(E, Drop.Folder, Drop.Index)
      else
        Moved := FList.AddRepo(Drop.Folder, FDragRoot, Drop.Index) <> nil;
    EndDrag;
    if Moved then
      Changed;
    SetHot(HotAt(X, Y));
    Exit;
  end;
  Hit := HotAt(X, Y);
  if Hit <> Down then
    Exit;
  if (Hit = hotButton) and Assigned(FOnOpen) then
    FOnOpen(Self)
  else if (Hit = hotButton - 1) and Assigned(FOnClone) then
    FOnClone(Self)
  else if (Hit = hotButton - 2) and Assigned(FOnInit) then
    FOnInit(Self)
  else if (Hit = hotAdd) and Assigned(FOnListMenu) then
    FOnListMenu(Self, nil, '', ClientToScreen(Point(FAddRect.Left, FAddRect.Bottom)))
  else if Hit <= hotList then
  begin
    E := FRows[hotList - Hit].Entry;
    if E.IsFolder then
    begin
      E.Collapsed := not E.Collapsed;
      Changed;
    end
    else if Assigned(FOnOpenRecent) then
      FOnOpenRecent(Self, E.Path);
  end
  else if (Hit >= 0) and Assigned(FOnOpenRecent) then
    FOnOpenRecent(Self, FRecent[Hit]);
end;

end.
