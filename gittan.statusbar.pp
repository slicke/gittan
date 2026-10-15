unit gittan.statusbar;

{** The status bar: a strip along the bottom of the window in three zones.

  On the left the repository: its name, the branch as a chip that drops
  the branch list, the commits ahead of and behind the upstream (a click
  lists them), what git
  is in the middle of and the conflicted files as tinted badges, and the
  base the work tree is compared against. In the middle a passing message,
  which clears itself after a while, or the progress of a long job. On the
  right the branch's pull request, the number of changed files and the
  caret's line and column.

  It paints itself with the palette of the file header, like the other
  bars, since a native status bar keeps the desktop's light look on a dark
  window on macOS. Each part has its own hint and, where it does
  something, its own click. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, ExtCtrls, Forms;

type
  {** The parts of the bar, from left to right. }
  TGittanStatusPart = (spNone, spRepo, spBranch, spSync, spOperation, spConflicts,
    spBase, spMessage, spProgress, spPull, spFiles, spPosition, spUpdate);

  {** How a message or the pull request reads: in the text color, or
    in green, amber or red. }
  TGittanStatusTone = (stNormal, stGood, stWarn, stBad);

  {** A click on APart, with its rectangle in screen coordinates for a
    popup to open from. }
  TGittanStatusClickEvent = procedure(Sender: TObject; APart: TGittanStatusPart;
    const AScreenRect: TRect) of object;

  { TGittanStatusHint }

  {** The bar's hint window. A line may start with one of the Hint*
    markers below and a space; the marker is drawn as an icon in its
    color instead. With more than one line the first, the title, is
    bold. }
  TGittanStatusHint = class(THintWindow)
  private
    FBack, FText, FLine: TColor;
    FTones: array[TGittanStatusTone] of TColor;
    procedure SplitLine(const ALine: string; out AIcon, AText: string);
    procedure DrawIcon(const AIcon: string; X, Y, ASize: integer);
  protected
    procedure Paint; override;
  public
    function CalcHintRect(MaxWidth: integer; const AHint: string;
      AData: pointer): TRect; override;
  end;

  { TGittanStatusBar }

  TGittanStatusBar = class(TCustomControl)
  private
    FTitle, FBranch, FOperation, FBase, FPull, FPullNote, FFiles, FPosition: string;
    FUpdate: string;
    FPullChecks: integer;
    FMessage, FProgressText, FConflicts: string;
    FAhead, FBehind, FProgressPos, FProgressTotal: integer;
    FPullTone, FMessageTone: TGittanStatusTone;
    FHints: array[TGittanStatusPart] of string;
    FRects: array[TGittanStatusPart] of TRect;
    FClickable: set of TGittanStatusPart;
    FHot, FPressed: TGittanStatusPart;
    FTimer, FHintTimer: TTimer;
    FHintWindow: TGittanStatusHint;
    FBack, FText, FDim, FLine, FHover, FAccent: TColor;
    FTones: array[TGittanStatusTone] of TColor;
    FOnPartClick: TGittanStatusClickEvent;
    function PartAt(X, Y: integer): TGittanStatusPart;
    function GetPartHint(APart: TGittanStatusPart): string;
    procedure SetPartHint(APart: TGittanStatusPart; const AValue: string);
    procedure SetHot(AValue: TGittanStatusPart);
    procedure TimerTimer(Sender: TObject);
    function HotHint: string;
    procedure HintTimerTimer(Sender: TObject);
    procedure HideHint;
    procedure Change(var AField: string; const AValue: string);
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    constructor Create(AOwner: TComponent); override;
    {** The name on the left (the repository, or the path of a file opened
      without one) and the branch; '' hides either. }
    procedure SetRepository(const ATitle, ABranch: string);
    {** The commits ahead of and behind the upstream; 0 hides either. }
    procedure SetSync(AAhead, ABehind: integer);
    {** What git is in the middle of ("merging") and the conflicted files
      ("2 conflicted files"), each '' for none. }
    procedure SetState(const AOperation, AConflicts: string);
    {** The base label ("vs origin/main"), '' for none. }
    procedure SetBase(const ABase: string);
    {** The pull request: its number ("#12", '' for none), its state
      ("Approved", "Draft", '' for none) and its checks: an icon in
      ATone (a check for stGood, a cross for stBad, a clock for stWarn,
      none for stNormal) with AChecks after it when above 0, the failing
      or pending ones. }
    procedure SetPull(const ANumber, ANote: string; ATone: TGittanStatusTone;
      AChecks: integer);
    {** The changed files ("3 changed files"), '' for none. }
    procedure SetFiles(const AText: string);
    {** The caret's position ("Ln 12, Col 4"), '' for none. }
    procedure SetPosition(const AText: string);
    {** A newer Gittan ("Build 109 available") as a green badge at the
      right edge, '' for none. }
    procedure SetUpdate(const AText: string);
    {** Shows AText in the middle in ATone, in place of any message before.
      It clears itself after ASeconds; 0 keeps it until the next message
      or ClearMessage, for a message that says something is under way. }
    procedure ShowMessage(const AText: string; ATone: TGittanStatusTone = stNormal;
      ASeconds: integer = 6);
    procedure ClearMessage;
    {** Shows a bar filled APos of ATotal with AText before it, in place of
      a message; ATotal 0 hides it. }
    procedure SetProgress(const AText: string; APos, ATotal: integer);
    {** Sets the palette: the background, the text, the dim text, the top
      border, the fill of a part under the mouse, the progress bar, and
      the green, amber and red of the tones. }
    procedure SetColors(ABack, AText, ADim, ALine, AHover, AAccent, AGood, AWarn,
      ABad: TColor);
    {** The hint shown over APart; the message's hint is its full text. }
    property PartHint[APart: TGittanStatusPart]: string read GetPartHint write SetPartHint;
    {** The parts that answer a click; the bar shows a hand and a fill over
      them. }
    property OnPartClick: TGittanStatusClickEvent read FOnPartClick write FOnPartClick;
  end;

{** The parts that answer a click. }
const
  StatusClickable = [spRepo, spBranch, spSync, spConflicts, spPull, spFiles, spUpdate];

  {** Markers at the start of a hint line, drawn as icons: a green check,
    a red cross, an amber clock, a globe for a link, two arrows for a
    switch, a folder, a branch and a pull request. Each is followed by a
    space. }
  HintPassed = '✓';
  HintFailed = '✕';
  HintPending = '◷';
  HintLink = '🌐';
  HintSwitch = '⇄';
  HintFolder = '📁';
  HintBranch = '⑂';
  HintPull = '⤴';

{** Draws the icon of the marker AIcon (HintPassed and the others above)
  in AColor, in a square a little smaller than ASize centered on a line
  ASize high at X, Y. The welcome view draws its folders with it too. }
procedure DrawStatusIcon(ACanvas: TCanvas; const AIcon: string; X, Y, ASize: integer;
  AColor: TColor);

implementation

uses
  Math;

const
  BarHeight = 26;
  Pad = 10;
  Gap = 14;
  ChipPadX = 6;
  ChipPadY = 2;
  ChevronWidth = 12;
  { Between the icon of the name or the branch and its text. }
  IconGap = 5;
  ProgressWidth = 80;
  ProgressHeight = 4;
  { Below this the middle is too narrow for a message to say anything. }
  MinMessageRoom = 60;

{ AColor laid over ABack at AAlpha (0 to 1), for the badges' tint. }
function Blend(AColor, ABack: TColor; AAlpha: double): TColor;

  function Mix(A, B: byte): byte;
  begin
    Result := Round(B + (A - B) * AAlpha);
  end;

begin
  AColor := ColorToRGB(AColor);
  ABack := ColorToRGB(ABack);
  Result := RGBToColor(Mix(Red(AColor), Red(ABack)), Mix(Green(AColor), Green(ABack)),
    Mix(Blue(AColor), Blue(ABack)));
end;

{ S cut to AWidth on ACanvas with an ellipsis, keeping UTF-8 sequences
  whole. }
function Ellipsize(ACanvas: TCanvas; const S: string; AWidth: integer): string;
begin
  Result := S;
  if ACanvas.TextWidth(Result) <= AWidth then
    Exit;
  while (Result <> '') and (ACanvas.TextWidth(Result + '…') > AWidth) do
  begin
    Result := Copy(Result, 1, Length(Result) - 1);
    while (Result <> '') and (Ord(Result[Length(Result)]) and $C0 = $80) do
      Result := Copy(Result, 1, Length(Result) - 1);
  end;
  if Result = '' then
    Exit;
  Result := Result + '…';
end;

const
  HintPad = 8;
  HintLineGap = 3;
  HintIconGap = 6;

{ TGittanStatusHint }

procedure TGittanStatusHint.SplitLine(const ALine: string; out AIcon, AText: string);
var
  M: string;
begin
  AIcon := '';
  AText := ALine;
  for M in [HintPassed, HintFailed, HintPending, HintLink, HintSwitch, HintFolder, HintBranch, HintPull] do
    if Copy(ALine, 1, Length(M) + 1) = M + ' ' then
    begin
      AIcon := M;
      AText := Copy(ALine, Length(M) + 2, MaxInt);
      Exit;
    end;
end;

{ The icons are drawn with lines rather than taken from a font, so they
  have the palette's colors and the same weight on every system. ASize
  is the line height; the icon takes a square a little smaller,
  centered. }
procedure DrawStatusIcon(ACanvas: TCanvas; const AIcon: string; X, Y, ASize: integer;
  AColor: TColor);
var
  S, L, T, CX, CY: integer;
begin
  S := ASize - 4;
  L := X;
  T := Y + (ASize - S) div 2;
  CX := L + S div 2;
  CY := T + S div 2;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Width := 2;
  if AIcon = HintPassed then
  begin
    ACanvas.Pen.Color := AColor;
    ACanvas.Polyline([Point(L + 1, CY), Point(L + S * 2 div 5, T + S - 2),
      Point(L + S - 1, T + 2)]);
  end
  else if AIcon = HintFailed then
  begin
    ACanvas.Pen.Color := AColor;
    ACanvas.Line(L + 2, T + 2, L + S - 2, T + S - 2);
    ACanvas.Line(L + S - 2, T + 2, L + 2, T + S - 2);
  end
  else if AIcon = HintPending then
  begin
    ACanvas.Pen.Color := AColor;
    ACanvas.Pen.Width := 1;
    ACanvas.Ellipse(L, T, L + S, T + S);
    ACanvas.Line(CX, CY, CX, T + 3);
    ACanvas.Line(CX, CY, L + S - 4, CY);
  end
  else if AIcon = HintLink then
  begin
    { A globe: the outline, a meridian and the equator with two
      parallels. }
    ACanvas.Pen.Color := AColor;
    ACanvas.Pen.Width := 1;
    ACanvas.Ellipse(L, T, L + S, T + S);
    ACanvas.Ellipse(CX - S div 4, T, CX + S div 4 + 1, T + S);
    ACanvas.Line(L, CY, L + S, CY);
    ACanvas.Line(L + 2, T + S div 4 + 1, L + S - 2, T + S div 4 + 1);
    ACanvas.Line(L + 2, T + S - S div 4 - 1, L + S - 2, T + S - S div 4 - 1);
  end
  else if AIcon = HintSwitch then
  begin
    { Two arrows, the upper to the right and the lower to the left. }
    ACanvas.Pen.Color := AColor;
    ACanvas.Pen.Width := 1;
    ACanvas.Line(L, T + S div 4, L + S, T + S div 4);
    ACanvas.Polyline([Point(L + S - 4, T + S div 4 - 3), Point(L + S - 1, T + S div 4),
      Point(L + S - 4, T + S div 4 + 3)]);
    ACanvas.Line(L, T + S - S div 4, L + S, T + S - S div 4);
    ACanvas.Polyline([Point(L + 3, T + S - S div 4 - 3), Point(L, T + S - S div 4),
      Point(L + 3, T + S - S div 4 + 3)]);
  end
  else if AIcon = HintFolder then
  begin
    { A folder: the tab on the upper left, then the body. }
    ACanvas.Pen.Color := AColor;
    ACanvas.Pen.Width := 1;
    ACanvas.Polygon([Point(L, T + 2), Point(L + S * 2 div 5, T + 2),
      Point(L + S div 2, T + 4), Point(L + S, T + 4), Point(L + S, T + S - 1),
      Point(L, T + S - 1)]);
    ACanvas.Line(L, T + 6, L + S, T + 6);
  end
  else if AIcon = HintBranch then
  begin
    { A branch: the stem on the left with a dot at each end, and a
      dot on the right whose line bends down into the stem. }
    ACanvas.Pen.Color := AColor;
    ACanvas.Pen.Width := 1;
    ACanvas.Line(L + 3, T + 4, L + 3, T + S - 3);
    ACanvas.Polyline([Point(L + S - 2, T + 5), Point(L + S - 2, T + S div 2),
      Point(L + 4, T + S - 4)]);
    ACanvas.Ellipse(L + 1, T, L + 5, T + 4);
    ACanvas.Ellipse(L + 1, T + S - 4, L + 5, T + S);
    ACanvas.Ellipse(L + S - 4, T + 1, L + S, T + 5);
  end
  else if AIcon = HintPull then
  begin
    { A pull request, as GitHub draws it: the stem on the left with a
      dot at each end, and on the right a dot at the bottom whose line
      rises and bends over to the top of the stem. }
    ACanvas.Pen.Color := AColor;
    ACanvas.Pen.Width := 1;
    ACanvas.Line(L + 3, T + 4, L + 3, T + S - 3);
    ACanvas.Polyline([Point(L + S - 2, T + S - 4), Point(L + S - 2, T + 4),
      Point(L + S - 4, T + 2), Point(L + 6, T + 2)]);
    ACanvas.Ellipse(L + 1, T, L + 5, T + 4);
    ACanvas.Ellipse(L + 1, T + S - 4, L + 5, T + S);
    ACanvas.Ellipse(L + S - 4, T + S - 4, L + S, T + S);
  end;
  ACanvas.Pen.Width := 1;
end;

procedure TGittanStatusHint.DrawIcon(const AIcon: string; X, Y, ASize: integer);
var
  C: TColor;
begin
  if AIcon = HintPassed then
    C := FTones[stGood]
  else if AIcon = HintFailed then
    C := FTones[stBad]
  else if AIcon = HintPending then
    C := FTones[stWarn]
  else
    C := FTones[stNormal];
  DrawStatusIcon(Canvas, AIcon, X, Y, ASize, C);
end;

function TGittanStatusHint.CalcHintRect(MaxWidth: integer; const AHint: string;
  AData: pointer): TRect;
var
  Lines: TStringList;
  i, W, H, LineH: integer;
  LineIcon, LineText: string;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := AHint;
    Canvas.Font := Font;
    LineH := Canvas.TextHeight('Xg');
    W := 0;
    for i := 0 to Lines.Count - 1 do
    begin
      SplitLine(Lines[i], LineIcon, LineText);
      if (i = 0) and (Lines.Count > 1) then
        Canvas.Font.Style := [fsBold];
      H := Canvas.TextWidth(LineText);
      Canvas.Font.Style := [];
      if LineIcon <> '' then
        Inc(H, LineH + HintIconGap);
      W := Max(W, H);
    end;
    W := Min(W, MaxWidth);
    H := Lines.Count * LineH + Max(0, Lines.Count - 1) * HintLineGap;
    Result := Rect(0, 0, W + 2 * HintPad, H + 2 * HintPad);
  finally
    Lines.Free;
  end;
end;

procedure TGittanStatusHint.Paint;
var
  Lines: TStringList;
  i, Y, X, LineH: integer;
  LineIcon, LineText: string;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.Pen.Color := FLine;
  Canvas.Pen.Width := 1;
  Canvas.Rectangle(ClientRect);
  Lines := TStringList.Create;
  try
    Lines.Text := Caption;
    Canvas.Font := Font;
    LineH := Canvas.TextHeight('Xg');
    Y := HintPad;
    for i := 0 to Lines.Count - 1 do
    begin
      SplitLine(Lines[i], LineIcon, LineText);
      X := HintPad;
      if LineIcon <> '' then
      begin
        DrawIcon(LineIcon, X, Y, LineH);
        Inc(X, LineH + HintIconGap);
      end;
      if (i = 0) and (Lines.Count > 1) then
        Canvas.Font.Style := [fsBold]
      else
        Canvas.Font.Style := [];
      Canvas.Font.Color := FText;
      Canvas.Brush.Style := bsClear;
      Canvas.TextOut(X, Y, LineText);
      Inc(Y, LineH + HintLineGap);
    end;
  finally
    Lines.Free;
  end;
end;

{ TGittanStatusBar }

constructor TGittanStatusBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Height := BarHeight;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.OnTimer := @TimerTimer;
  { The bar shows its hints itself (see SetHot), so the LCL's own stays
    off. }
  ShowHint := False;
  ParentShowHint := False;
  FHintTimer := TTimer.Create(Self);
  FHintTimer.Enabled := False;
  FHintTimer.Interval := Application.HintPause;
  FHintTimer.OnTimer := @HintTimerTimer;
  FClickable := StatusClickable;
  SetColors(clBtnFace, clWindowText, clGrayText, clBtnShadow, clBtnHighlight,
    clHighlight, clGreen, clOlive, clRed);
end;

procedure TGittanStatusBar.Change(var AField: string; const AValue: string);
begin
  if AField = AValue then
    Exit;
  AField := AValue;
  Invalidate;
end;

procedure TGittanStatusBar.SetRepository(const ATitle, ABranch: string);
begin
  Change(FTitle, ATitle);
  Change(FBranch, ABranch);
end;

procedure TGittanStatusBar.SetSync(AAhead, ABehind: integer);
begin
  if (FAhead = AAhead) and (FBehind = ABehind) then
    Exit;
  FAhead := AAhead;
  FBehind := ABehind;
  Invalidate;
end;

procedure TGittanStatusBar.SetState(const AOperation, AConflicts: string);
begin
  Change(FOperation, AOperation);
  Change(FConflicts, AConflicts);
end;

procedure TGittanStatusBar.SetBase(const ABase: string);
begin
  Change(FBase, ABase);
end;

procedure TGittanStatusBar.SetPull(const ANumber, ANote: string;
  ATone: TGittanStatusTone; AChecks: integer);
begin
  if (FPullTone <> ATone) or (FPullChecks <> AChecks) then
  begin
    FPullTone := ATone;
    FPullChecks := AChecks;
    Invalidate;
  end;
  Change(FPull, ANumber);
  Change(FPullNote, ANote);
end;

procedure TGittanStatusBar.SetFiles(const AText: string);
begin
  Change(FFiles, AText);
end;

procedure TGittanStatusBar.SetPosition(const AText: string);
begin
  Change(FPosition, AText);
end;

procedure TGittanStatusBar.SetUpdate(const AText: string);
begin
  Change(FUpdate, AText);
end;

procedure TGittanStatusBar.ShowMessage(const AText: string; ATone: TGittanStatusTone;
  ASeconds: integer);
begin
  FMessage := AText;
  FMessageTone := ATone;
  FTimer.Enabled := False;
  if (AText <> '') and (ASeconds > 0) then
  begin
    FTimer.Interval := ASeconds * 1000;
    FTimer.Enabled := True;
  end;
  { A message is often shown just before a long call on the main thread
    ("Looking for ..."), so it is painted at once. }
  Repaint;
end;

procedure TGittanStatusBar.ClearMessage;
begin
  FTimer.Enabled := False;
  Change(FMessage, '');
end;

procedure TGittanStatusBar.TimerTimer(Sender: TObject);
begin
  ClearMessage;
end;

procedure TGittanStatusBar.SetProgress(const AText: string; APos, ATotal: integer);
begin
  if (FProgressText = AText) and (FProgressPos = APos) and (FProgressTotal = ATotal) then
    Exit;
  FProgressText := AText;
  FProgressPos := APos;
  FProgressTotal := ATotal;
  Invalidate;
end;

procedure TGittanStatusBar.SetColors(ABack, AText, ADim, ALine, AHover, AAccent,
  AGood, AWarn, ABad: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FLine := ALine;
  FHover := AHover;
  FAccent := AAccent;
  FTones[stNormal] := AText;
  FTones[stGood] := AGood;
  FTones[stWarn] := AWarn;
  FTones[stBad] := ABad;
  Color := ABack;
  Invalidate;
end;

function TGittanStatusBar.GetPartHint(APart: TGittanStatusPart): string;
begin
  Result := FHints[APart];
end;

procedure TGittanStatusBar.SetPartHint(APart: TGittanStatusPart; const AValue: string);
begin
  FHints[APart] := AValue;
end;

function TGittanStatusBar.HotHint: string;
begin
  case FHot of
    spMessage: Result := FMessage;
    spProgress: Result := FProgressText;
    else
      Result := FHints[FHot];
  end;
end;

{ The hint goes above the part, left aligned with it and kept inside the
  bar's width, since below the bar is outside the window. }
procedure TGittanStatusBar.HintTimerTimer(Sender: TObject);
var
  Tip: string;
  R: TRect;
  P: TPoint;
  MaxRight: integer;
begin
  FHintTimer.Enabled := False;
  Tip := HotHint;
  if (FHot = spNone) or (Tip = '') then
    Exit;
  if FHintWindow = nil then
    FHintWindow := TGittanStatusHint.Create(Self);
  FHintWindow.Font := Font;
  FHintWindow.FBack := FBack;
  FHintWindow.FText := FText;
  FHintWindow.FLine := FLine;
  FHintWindow.FTones := FTones;
  FHintWindow.FTones[stNormal] := FDim;
  R := FHintWindow.CalcHintRect(Max(200, Width - 2 * Pad), Tip, nil);
  P := ClientToScreen(Point(FRects[FHot].Left, 0));
  Types.OffsetRect(R, P.X, P.Y - R.Bottom - 4);
  MaxRight := ClientToScreen(Point(Width - Pad, 0)).X;
  if R.Right > MaxRight then
    Types.OffsetRect(R, Max(ClientToScreen(Point(Pad, 0)).X - R.Left,
      MaxRight - R.Right), 0);
  FHintWindow.ActivateHint(R, Tip);
end;

procedure TGittanStatusBar.HideHint;
begin
  FHintTimer.Enabled := False;
  if (FHintWindow <> nil) and FHintWindow.Visible then
    FHintWindow.Hide;
end;

{ Every part is measured and placed here, so the rectangles the mouse is
  tested against are always those of the last paint. The right zone is
  placed first, right to left; the left zone takes what it needs of the
  rest, giving up the base and then the name while a message needs the
  room; the middle gets what is left. }
procedure TGittanStatusBar.Paint;
var
  P: TGittanStatusPart;
  TextH, TextY, X, Right, LeftEnd, W, Room, MidWant, IconW: integer;
  Sync, S, Checks: string;
  ShowTitle, ShowBase: boolean;

  function ChipRect(AX, AWidth: integer): TRect;
  begin
    Result := Rect(AX, TextY - ChipPadY, AX + AWidth, TextY + TextH + ChipPadY);
  end;

  { The fill under a clickable part while the mouse is over it. }
  procedure DrawHot(APart: TGittanStatusPart);
  begin
    if (FHot <> APart) or not (APart in FClickable) then
      Exit;
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FHover;
    Canvas.RoundRect(FRects[APart], 8, 8);
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsClear;
  end;

  { Text in a rectangle with the chip's padding; clickable parts get the
    padding so their fill does not hug the letters. }
  procedure DrawText(APart: TGittanStatusPart; AX: integer; const AText: string;
    AColor: TColor);
  begin
    FRects[APart] := ChipRect(AX - ChipPadX, Canvas.TextWidth(AText) + 2 * ChipPadX);
    DrawHot(APart);
    Canvas.Font.Color := AColor;
    Canvas.TextOut(AX, TextY, AText);
  end;

  { A badge: the text in its tone on a tint of the tone. }
  procedure DrawBadge(APart: TGittanStatusPart; AX: integer; const AText: string;
    ATone: TGittanStatusTone);
  begin
    FRects[APart] := ChipRect(AX, Canvas.TextWidth(AText) + 2 * ChipPadX);
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    if FHot = APart then
      Canvas.Brush.Color := Blend(FTones[ATone], FBack, 0.32)
    else
      Canvas.Brush.Color := Blend(FTones[ATone], FBack, 0.18);
    Canvas.RoundRect(FRects[APart], 8, 8);
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := FTones[ATone];
    Canvas.TextOut(AX + ChipPadX, TextY, AText);
  end;

  function BadgeWidth(const AText: string): integer;
  begin
    Result := Canvas.TextWidth(AText) + 2 * ChipPadX;
  end;

  function LeftWidth(ATitle, ABase: boolean): integer;
  begin
    Result := 0;
    if ATitle and (FTitle <> '') then
      Inc(Result, IconW + Canvas.TextWidth(FTitle) + Gap);
    if FBranch <> '' then
      Inc(Result, IconW + Canvas.TextWidth(FBranch) + ChevronWidth + 2 * ChipPadX + Gap);
    if Sync <> '' then
      Inc(Result, Canvas.TextWidth(Sync) + Gap);
    if FOperation <> '' then
      Inc(Result, BadgeWidth(FOperation) + Gap div 2);
    if FConflicts <> '' then
      Inc(Result, BadgeWidth(FConflicts) + Gap div 2);
    if ABase and (FBase <> '') then
      Inc(Result, Canvas.TextWidth(FBase) + Gap);
  end;

begin
  for P := Low(P) to High(P) do
    FRects[P] := Rect(0, 0, 0, 0);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := FLine;
  Canvas.Line(0, 0, Width, 0);
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  TextH := Canvas.TextHeight('Xg');
  TextY := (Height + 1 - TextH) div 2;
  IconW := TextH - 4 + IconGap;

  { Right zone, right to left: a newer Gittan, position, files, pull
    request. }
  Right := Width - Pad;
  if FUpdate <> '' then
  begin
    W := BadgeWidth(FUpdate);
    DrawBadge(spUpdate, Right - W, FUpdate, stGood);
    Dec(Right, W + Gap);
  end;
  if FPosition <> '' then
  begin
    W := Canvas.TextWidth(FPosition);
    DrawText(spPosition, Right - W, FPosition, FDim);
    Dec(Right, W + Gap);
  end;
  if FFiles <> '' then
  begin
    W := Canvas.TextWidth(FFiles);
    DrawText(spFiles, Right - W, FFiles, FDim);
    Dec(Right, W + Gap + ChipPadX);
  end;
  if FPull <> '' then
  begin
    { The pull request icon, the number, the state dimmed, then the
      checks as an icon in their tone with the count of the failing or
      pending ones. It gives way first when the window is narrow. }
    Checks := '';
    if FPullChecks > 0 then
      Checks := IntToStr(FPullChecks);
    W := IconW + Canvas.TextWidth(FPull);
    if FPullNote <> '' then
      Inc(W, Gap div 2 + Canvas.TextWidth(FPullNote));
    if FPullTone <> stNormal then
      Inc(W, Gap div 2 + IconW - IconGap + Canvas.TextWidth(Checks));
    if Right - W > Width div 3 then
    begin
      X := Right - W;
      FRects[spPull] := ChipRect(X - ChipPadX, W + 2 * ChipPadX);
      DrawHot(spPull);
      DrawStatusIcon(Canvas, HintPull, X, TextY, TextH, FDim);
      Inc(X, IconW);
      Canvas.Font.Color := FText;
      Canvas.TextOut(X, TextY, FPull);
      Inc(X, Canvas.TextWidth(FPull));
      if FPullNote <> '' then
      begin
        Inc(X, Gap div 2);
        Canvas.Font.Color := FDim;
        Canvas.TextOut(X, TextY, FPullNote);
        Inc(X, Canvas.TextWidth(FPullNote));
      end;
      if FPullTone <> stNormal then
      begin
        Inc(X, Gap div 2);
        case FPullTone of
          stGood: DrawStatusIcon(Canvas, HintPassed, X, TextY, TextH, FTones[stGood]);
          stBad: DrawStatusIcon(Canvas, HintFailed, X, TextY, TextH, FTones[stBad]);
          stWarn: DrawStatusIcon(Canvas, HintPending, X, TextY, TextH, FTones[stWarn]);
        end;
        Inc(X, IconW - IconGap);
        Canvas.Font.Color := FTones[FPullTone];
        Canvas.TextOut(X, TextY, Checks);
      end;
      Dec(Right, W + Gap + ChipPadX);
    end;
  end;

  { Left zone. }
  Sync := '';
  if FAhead > 0 then
    Sync := '↑' + IntToStr(FAhead);
  if FBehind > 0 then
    Sync := Trim(Sync + ' ↓' + IntToStr(FBehind));
  if FMessage <> '' then
    MidWant := Min(Canvas.TextWidth(FMessage), 240)
  else if FProgressTotal > 0 then
    MidWant := Canvas.TextWidth(FProgressText) + ProgressWidth + 6
  else
    MidWant := 0;
  Room := Right - Pad;
  if MidWant > 0 then
    Dec(Room, MidWant + Gap);
  ShowBase := LeftWidth(True, True) <= Room;
  ShowTitle := ShowBase or (LeftWidth(True, False) <= Room);

  { The name and the branch each have an icon before them, a folder and
    a branch, inside the part so it takes the fill too. }
  X := Pad;
  if ShowTitle and (FTitle <> '') then
  begin
    S := Ellipsize(Canvas, FTitle, Right - X - IconW);
    FRects[spRepo] := ChipRect(X - ChipPadX, IconW + Canvas.TextWidth(S) + 2 * ChipPadX);
    DrawHot(spRepo);
    DrawStatusIcon(Canvas, HintFolder, X, TextY, TextH, FDim);
    Inc(X, IconW);
    Canvas.Font.Color := FText;
    Canvas.TextOut(X, TextY, S);
    Inc(X, Canvas.TextWidth(S) + Gap);
  end;
  if (FBranch <> '') and (X < Right - IconW - ChevronWidth - 2 * ChipPadX) then
  begin
    S := Ellipsize(Canvas, FBranch, Right - X - IconW - ChevronWidth - 2 * ChipPadX);
    W := IconW + Canvas.TextWidth(S) + ChevronWidth;
    FRects[spBranch] := ChipRect(X - ChipPadX, W + 2 * ChipPadX);
    DrawHot(spBranch);
    DrawStatusIcon(Canvas, HintBranch, X, TextY, TextH, FDim);
    Inc(X, IconW);
    Canvas.Font.Color := FText;
    Canvas.TextOut(X, TextY, S);
    Inc(X, Canvas.TextWidth(S) + ChevronWidth div 2 + 1);
    Canvas.Pen.Color := FDim;
    Canvas.Polyline([Point(X - 3, TextY + TextH div 2 - 1),
      Point(X, TextY + TextH div 2 + 2), Point(X + 3, TextY + TextH div 2 - 1)]);
    Inc(X, ChevronWidth div 2 + ChipPadX + Gap - 1);
  end;
  if (Sync <> '') and (X + Canvas.TextWidth(Sync) <= Right) then
  begin
    DrawText(spSync, X, Sync, FDim);
    Inc(X, Canvas.TextWidth(Sync) + Gap);
  end;
  if (FOperation <> '') and (X + BadgeWidth(FOperation) <= Right) then
  begin
    DrawBadge(spOperation, X, FOperation, stWarn);
    Inc(X, BadgeWidth(FOperation) + Gap div 2);
  end;
  if (FConflicts <> '') and (X + BadgeWidth(FConflicts) <= Right) then
  begin
    DrawBadge(spConflicts, X, FConflicts, stBad);
    Inc(X, BadgeWidth(FConflicts) + Gap div 2);
  end;
  if (FOperation <> '') or (FConflicts <> '') then
    Inc(X, Gap div 2);
  if ShowBase and (FBase <> '') and (X + Canvas.TextWidth(FBase) <= Right) then
  begin
    DrawText(spBase, X, FBase, FDim);
    Inc(X, Canvas.TextWidth(FBase) + Gap);
  end;
  LeftEnd := X;

  { Middle: the message, else the progress. }
  Room := Right - LeftEnd;
  if Room < MinMessageRoom then
    Exit;
  if FMessage <> '' then
  begin
    S := Ellipsize(Canvas, FMessage, Room);
    FRects[spMessage] := ChipRect(LeftEnd, Canvas.TextWidth(S));
    if FMessageTone = stNormal then
      Canvas.Font.Color := FText
    else
      Canvas.Font.Color := FTones[FMessageTone];
    Canvas.TextOut(LeftEnd, TextY, S);
  end
  else if FProgressTotal > 0 then
  begin
    S := Ellipsize(Canvas, FProgressText, Room - ProgressWidth - 6);
    X := LeftEnd;
    if S <> '' then
    begin
      Canvas.Font.Color := FDim;
      Canvas.TextOut(X, TextY, S);
      Inc(X, Canvas.TextWidth(S) + 6);
    end;
    FRects[spProgress] := ChipRect(LeftEnd, X + ProgressWidth - LeftEnd);
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FHover;
    W := (Height - ProgressHeight) div 2;
    Canvas.RoundRect(X, W, X + ProgressWidth, W + ProgressHeight,
      ProgressHeight, ProgressHeight);
    Canvas.Brush.Color := FAccent;
    Canvas.RoundRect(X, W, X + Max(ProgressHeight, ProgressWidth *
      Min(FProgressPos, FProgressTotal) div FProgressTotal), W + ProgressHeight,
      ProgressHeight, ProgressHeight);
    Canvas.Pen.Style := psSolid;
  end;
end;

function TGittanStatusBar.PartAt(X, Y: integer): TGittanStatusPart;
var
  P: TGittanStatusPart;
begin
  for P := Succ(spNone) to High(P) do
    if (X >= FRects[P].Left) and (X < FRects[P].Right) and (FRects[P].Right > 0) then
      Exit(P);
  Result := spNone;
end;

procedure TGittanStatusBar.SetHot(AValue: TGittanStatusPart);
begin
  if FHot = AValue then
    Exit;
  FHot := AValue;
  { A new part has its own hint: the old one is taken down and the new
    one comes up after the usual pause. The bar shows them itself, since
    the LCL's hint, which follows controls, never came up again once the
    mouse had moved within the bar. }
  HideHint;
  if HotHint <> '' then
    FHintTimer.Enabled := True;
  if AValue in FClickable then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  Invalidate;
end;

procedure TGittanStatusBar.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(PartAt(X, Y));
end;

procedure TGittanStatusBar.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(spNone);
  HideHint;
end;

procedure TGittanStatusBar.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  HideHint;
  if Button = mbLeft then
    FPressed := PartAt(X, Y);
end;

{ The click fires on release over the part that was pressed. }
procedure TGittanStatusBar.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Part: TGittanStatusPart;
  R: TRect;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  Part := FPressed;
  FPressed := spNone;
  if (Part = spNone) or (Part <> PartAt(X, Y)) or not (Part in FClickable) or
    not Assigned(FOnPartClick) then
    Exit;
  R.TopLeft := ClientToScreen(FRects[Part].TopLeft);
  R.BottomRight := ClientToScreen(FRects[Part].BottomRight);
  FOnPartClick(Self, Part, R);
end;

end.
