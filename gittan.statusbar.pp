unit gittan.statusbar;

{** The status bar: a strip along the bottom of the window in three zones.

  On the left the repository: its name, the branch as a chip that drops
  the branch list, the commits ahead of and behind the upstream, what git
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
    spBase, spMessage, spProgress, spPull, spFiles, spPosition);

  {** How a message or the pull request reads: in the text color, or
    in green, amber or red. }
  TGittanStatusTone = (stNormal, stGood, stWarn, stBad);

  {** A click on APart, with its rectangle in screen coordinates for a
    popup to open from. }
  TGittanStatusClickEvent = procedure(Sender: TObject; APart: TGittanStatusPart;
    const AScreenRect: TRect) of object;

  { TGittanStatusBar }

  TGittanStatusBar = class(TCustomControl)
  private
    FTitle, FBranch, FOperation, FBase, FPull, FFiles, FPosition: string;
    FMessage, FProgressText, FConflicts: string;
    FAhead, FBehind, FProgressPos, FProgressTotal: integer;
    FPullTone, FMessageTone: TGittanStatusTone;
    FHints: array[TGittanStatusPart] of string;
    FRects: array[TGittanStatusPart] of TRect;
    FClickable: set of TGittanStatusPart;
    FHot, FPressed: TGittanStatusPart;
    FTimer: TTimer;
    FBack, FText, FDim, FLine, FHover, FAccent: TColor;
    FTones: array[TGittanStatusTone] of TColor;
    FOnPartClick: TGittanStatusClickEvent;
    function PartAt(X, Y: integer): TGittanStatusPart;
    function GetPartHint(APart: TGittanStatusPart): string;
    procedure SetPartHint(APart: TGittanStatusPart; const AValue: string);
    procedure SetHot(AValue: TGittanStatusPart);
    procedure TimerTimer(Sender: TObject);
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
    {** The pull request's status line, '' for none, and its tone. }
    procedure SetPull(const AText: string; ATone: TGittanStatusTone);
    {** The changed files ("3 changed files"), '' for none. }
    procedure SetFiles(const AText: string);
    {** The caret's position ("Ln 12, Col 4"), '' for none. }
    procedure SetPosition(const AText: string);
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
  StatusClickable = [spRepo, spBranch, spConflicts, spPull, spFiles];

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
  DotSize = 7;
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

{ TGittanStatusBar }

constructor TGittanStatusBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Height := BarHeight;
  ShowHint := True;
  ParentShowHint := False;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.OnTimer := @TimerTimer;
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

procedure TGittanStatusBar.SetPull(const AText: string; ATone: TGittanStatusTone);
begin
  if FPullTone <> ATone then
  begin
    FPullTone := ATone;
    Invalidate;
  end;
  Change(FPull, AText);
end;

procedure TGittanStatusBar.SetFiles(const AText: string);
begin
  Change(FFiles, AText);
end;

procedure TGittanStatusBar.SetPosition(const AText: string);
begin
  Change(FPosition, AText);
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
  if FHot = APart then
    Hint := AValue;
end;

{ Every part is measured and placed here, so the rectangles the mouse is
  tested against are always those of the last paint. The right zone is
  placed first, right to left; the left zone takes what it needs of the
  rest, giving up the base and then the name while a message needs the
  room; the middle gets what is left. }
procedure TGittanStatusBar.Paint;
var
  P: TGittanStatusPart;
  TextH, TextY, X, Right, LeftEnd, W, Room, MidWant: integer;
  Sync, S: string;
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
      Inc(Result, Canvas.TextWidth(FTitle) + Gap);
    if FBranch <> '' then
      Inc(Result, Canvas.TextWidth(FBranch) + ChevronWidth + 2 * ChipPadX + Gap);
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

  { Right zone, right to left: position, files, pull request. }
  Right := Width - Pad;
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
    { The pull request gives way first when the window is narrow. }
    W := Canvas.TextWidth(FPull) + DotSize + 6;
    if Right - W > Width div 3 then
    begin
      FRects[spPull] := ChipRect(Right - W - ChipPadX, W + 2 * ChipPadX);
      DrawHot(spPull);
      Canvas.Pen.Style := psClear;
      Canvas.Brush.Style := bsSolid;
      if FPullTone = stNormal then
        Canvas.Brush.Color := FDim
      else
        Canvas.Brush.Color := FTones[FPullTone];
      Canvas.Ellipse(Right - W, TextY + (TextH - DotSize) div 2,
        Right - W + DotSize, TextY + (TextH - DotSize) div 2 + DotSize);
      Canvas.Pen.Style := psSolid;
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Color := FText;
      Canvas.TextOut(Right - W + DotSize + 6, TextY, FPull);
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

  X := Pad;
  if ShowTitle and (FTitle <> '') then
  begin
    S := Ellipsize(Canvas, FTitle, Right - X);
    DrawText(spRepo, X, S, FText);
    Inc(X, Canvas.TextWidth(S) + Gap);
  end;
  if (FBranch <> '') and (X < Right - ChevronWidth - 2 * ChipPadX) then
  begin
    S := Ellipsize(Canvas, FBranch, Right - X - ChevronWidth - 2 * ChipPadX);
    W := Canvas.TextWidth(S) + ChevronWidth;
    FRects[spBranch] := ChipRect(X - ChipPadX, W + 2 * ChipPadX);
    DrawHot(spBranch);
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
  { A new part has its own hint; the old one is taken down so the new one
    comes up after the usual pause. }
  Application.CancelHint;
  if AValue = spMessage then
    Hint := FMessage
  else if AValue = spProgress then
    Hint := FProgressText
  else
    Hint := FHints[AValue];
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
end;

procedure TGittanStatusBar.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
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
