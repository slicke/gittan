unit gittan.statusbar;

{** The status bar: a strip along the bottom of the window laid out as a
  music player's bar, in three zones.

  On the left where you are: a tile with the repository's initial, its
  name over the branch (a chip that drops the branch list) with the base
  the work tree is compared against after it, and the stashes as a chip
  with their count. In the middle the next step towards the remote, as
  the player's transport: a button on each side around the primary one,
  which says what to do next (Pull, Push, Resolve, Continue, or that the
  branch is up to date), over a track line with the commits behind on
  its left and ahead on its right; the track also carries a passing
  message, the progress of a long job, or how far a rebase has come; a
  message that says something is under way (ShowBusy) is in the accent
  color, after an icon for what runs, over a line with a short stretch
  sliding to and fro on it; when none of the buttons can be clicked
  meanwhile it takes their row and the line has the track's. On the
  right what is shown: a newer Gittan, the pull request, the caret's
  position and the changed files.

  The parts give way from the outside in when the window is narrow. It
  paints itself with the palette of the file header, like the other
  bars, since a native status bar keeps the desktop's light look on a
  dark window on macOS. Each part has its own hint and, where it does
  something, its own click. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, ExtCtrls, Forms, LCLIntf;

type
  {** The parts of the bar: the left zone (the tile and name, the
    branch, the base and its cross, the stashes), the transport (the left
    button, the primary one, the right button) over the track (the sync
    counts, or a message or a progress), and the right zone. }
  TGittanStatusPart = (spNone, spRepo, spBranch, spBase, spBaseClose, spStash, spLeft,
    spPrimary, spRight, spSync, spMessage, spProgress, spUpdate, spPull, spPosition, spFiles);

  {** How a message or the pull request reads: in the text color, or
    in green, amber or red. }
  TGittanStatusTone = (stNormal, stGood, stWarn, stBad);

  {** A click on APart, with its rectangle in screen coordinates for a
    popup to open from. }
  TGittanStatusClickEvent = procedure(Sender: TObject; APart: TGittanStatusPart;
    const AScreenRect: TRect) of object;

  {** A transport button. The primary one reads Caption after its icon;
    the side ones show the icon alone, and their caption is for the
    hint. The primary's tone is its fill: the accent for stNormal, a
    step to take; the hover fill with a green icon for stGood, when
    there is nothing to do; amber or red for stWarn and stBad. An empty
    icon hides the button; a disabled one is dimmed and answers no
    click. }
  TGittanStatusButton = record
    Caption, Icon: string;
    Tone: TGittanStatusTone;
    Enabled: boolean;
  end;

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
    FTitle, FBranch, FBase, FPull, FPullNote, FFiles, FPosition, FUpdate: string;
    FOperation, FMessage, FProgressText, FProgressIcon: string;
    FPullChecks, FPullOpen, FPullThreads, FStashes: integer;
    FAhead, FBehind, FProgressPos, FProgressTotal, FOperationPos, FOperationTotal: integer;
    FSyncShown, FBaseClosable: boolean;
    FButtons: array[spLeft..spRight] of TGittanStatusButton;
    FPullTone, FMessageTone: TGittanStatusTone;
    FMessageIcon: string;
    FBusy: boolean;
    FBusyPhase: integer;
    FBusyRect: TRect;
    FHints: array[TGittanStatusPart] of string;
    FRects: array[TGittanStatusPart] of TRect;
    FClickable: set of TGittanStatusPart;
    FHot, FPressed: TGittanStatusPart;
    FTimer, FHintTimer, FBusyTimer: TTimer;
    FHintWindow: TGittanStatusHint;
    FBack, FText, FDim, FLine, FHover, FAccent: TColor;
    FTones: array[TGittanStatusTone] of TColor;
    FOnPartClick: TGittanStatusClickEvent;
    function PartAt(X, Y: integer): TGittanStatusPart;
    function Clickable(APart: TGittanStatusPart): boolean;
    function GetPartHint(APart: TGittanStatusPart): string;
    procedure SetPartHint(APart: TGittanStatusPart; const AValue: string);
    procedure SetHot(AValue: TGittanStatusPart);
    procedure TimerTimer(Sender: TObject);
    procedure BusyTimerTimer(Sender: TObject);
    procedure SetBusy(AValue: boolean);
    function HotHint: string;
    procedure HintTimerTimer(Sender: TObject);
    procedure HideHint;
    procedure Change(var AField: string; const AValue: string);
  protected
    procedure DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
      const AXProportion, AYProportion: double); override;
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
      without one), over the branch; '' hides either. The tile before
      them shows the name's initial. }
    procedure SetRepository(const ATitle, ABranch: string);
    {** The base label ("vs origin/main") after the branch, '' for none;
      AClickable makes the part answer a click (and show a hand), for a
      base that has actions. AClosable puts a cross after it (spBaseClose),
      for a comparison that a click ends. }
    procedure SetBase(const ABase: string; AClickable: boolean = False;
      AClosable: boolean = False);
    {** How many stashes the repository has, shown as a chip with a box
      and the count after the name and the branch; 0 hides it. }
    procedure SetStashes(ACount: integer);
    {** The three transport buttons; see TGittanStatusButton. }
    procedure SetTransport(const ALeft, APrimary, ARight: TGittanStatusButton);
    {** The commits behind and ahead of the upstream on the track's two
      ends, under the transport. With AShown the track is there even
      with neither, and a click on it (spSync) lists what can be done
      with the remote; without AShown there is no track. }
    procedure SetSync(AAhead, ABehind: integer; AShown: boolean);
    {** What git is in the middle of ("Rebasing"), on the track in amber
      with the line filled APos of ATotal when ATotal is above 0; '' for
      nothing. }
    procedure SetOperation(const AText: string; APos, ATotal: integer);
    {** The pull request: its number ("#12", '' for none), its state
      ("Approved", "Draft", '' for none) and its checks: an icon in
      ATone (a check for stGood, a cross for stBad, a clock for stWarn,
      none for stNormal) with AChecks after it when above 0, the failing
      or pending ones. }
    procedure SetPull(const ANumber, ANote: string; ATone: TGittanStatusTone;
      AChecks: integer);
    {** The review threads of the pull request: a speech bubble after the
      checks, in the accent color with AOpen after it while threads are
      open, dimmed when all AAll are resolved or outdated, none without
      threads. }
    procedure SetPullThreads(AOpen, AAll: integer);
    {** The changed files ("3 changed files"), '' for none. }
    procedure SetFiles(const AText: string);
    {** The caret's position ("Ln 12, Col 4"), '' for none. }
    procedure SetPosition(const AText: string);
    {** A newer Gittan ("Build 109 available") as a green badge, '' for
      none. }
    procedure SetUpdate(const AText: string);
    {** Shows AText on the track in ATone, in place of any message before.
      It clears itself after ASeconds; 0 keeps it until the next message
      or ClearMessage. }
    procedure ShowMessage(const AText: string; ATone: TGittanStatusTone = stNormal;
      ASeconds: integer = 6);
    {** Shows AText on the track as something under way, until the next
      message or ClearMessage: in the accent color, after the icon of the
      marker AIcon (HintSparkle for the agent, HintFetch, HintUp and the
      others; '' for none), over a line with a stretch of the accent
      sliding to and fro on it. While none of the transport buttons is
      enabled the text takes their row and the line is the track's;
      otherwise the text is on the track's row under the buttons and the
      line, as wide as the text, right under it. }
    procedure ShowBusy(const AText: string; const AIcon: string = '');
    procedure ClearMessage;
    {** Shows the track line filled APos of ATotal with AText before it,
      in place of the sync counts, in the accent color after the icon of
      the marker AIcon ('' for none); ATotal 0 hides it. The part's hint
      is PartHint[spProgress], or AText while that is empty. }
    procedure SetProgress(const AText: string; APos, ATotal: integer;
      const AIcon: string = '');
    {** Sets the palette: the background, the text, the dim text, the top
      border, the fill of a part under the mouse, the accent (the primary
      button, the progress), and the green, amber and red of the tones. }
    procedure SetColors(ABack, AText, ADim, ALine, AHover, AAccent, AGood, AWarn,
      ABad: TColor);
    {** Where APart is on the screen, for a list dropped from it by
      something other than a click (a menu item); an empty rectangle at
      the bar's left edge when the part is not shown. }
    function PartScreenRect(APart: TGittanStatusPart): TRect;
    {** The hint shown over APart; the message's hint is its full text. }
    property PartHint[APart: TGittanStatusPart]: string read GetPartHint write SetPartHint;
    {** The parts that answer a click; the bar shows a hand and a fill over
      them. }
    property OnPartClick: TGittanStatusClickEvent read FOnPartClick write FOnPartClick;
  end;

{** A transport button, for SetTransport. }
function StatusButton(const ACaption, AIcon: string; ATone: TGittanStatusTone = stNormal;
  AEnabled: boolean = True): TGittanStatusButton;

{** The parts that answer a click. A transport button answers one while
  it is enabled, the base while it has actions. }
const
  StatusClickable = [spRepo, spBranch, spStash, spLeft, spPrimary, spRight, spSync,
    spUpdate, spPull, spFiles];

  {** Markers at the start of a hint line, drawn as icons: a green check,
    a red cross, an amber clock, a globe for a link, two arrows for a
    switch, a folder, a branch, a pull request, a speech bubble for
    review comments, an arrow up beside one down for the commits to
    push and pull, a box for the stashes, and for the transport two
    arrows round a circle (fetch), an arrow down (pull), an arrow up
    (push), a triangle (continue), a triangle at a bar (skip) and a
    warning triangle (conflicts); a sparkle for the agent; a magnifying
    glass for the indexing; an arrow
    bending back to the left (undo) and one bending on to the right
    (redo). Each is followed by a space. }
  HintPassed = '✓';
  HintFailed = '✕';
  HintPending = '◷';
  HintLink = '🌐';
  HintSwitch = '⇄';
  HintFolder = '📁';
  HintBranch = '⑂';
  HintPull = '⤴';
  HintComment = '💬';
  HintSync = '⇅';
  HintStash = '📦';
  HintFetch = '⟳';
  HintDown = '↓';
  HintUp = '↑';
  HintPlay = '▶';
  HintSkip = '⏭';
  HintWarn = '⚠';
  HintSparkle = '✦';
  HintSearch = '🔍';
  HintUndo = '↶';
  HintRedo = '↷';

{** Draws the icon of the marker AIcon (HintPassed and the others above)
  in AColor, in a square a little smaller than ASize centered on a line
  ASize high at X, Y. The welcome view draws its folders with it too. }
procedure DrawStatusIcon(ACanvas: TCanvas; const AIcon: string; X, Y, ASize: integer;
  AColor: TColor);

{** Fills ARect in AColor with round corners ARadius across and no
  border, as a hovered chip or row is drawn in the status bar and the
  summary; the pen is solid and the brush clear again after. }
procedure FillHover(ACanvas: TCanvas; const ARect: TRect; ARadius: integer; AColor: TColor);

{** The small chevron pointing down, in AColor and centered on CX, CY,
  that ends a chip dropping a list. }
procedure DrawChevron(ACanvas: TCanvas; CX, CY: integer; AColor: TColor);

implementation

uses
  Math, gittan.textfit, gittan.theme;

const
  BarHeight = 56;
  Pad = 12;
  Gap = 10;
  ChipPadX = 6;
  ChipPadY = 2;
  ChevronWidth = 12;
  { Between an icon and its text. }
  IconGap = 5;
  { The tile with the initial, and the room after it. }
  TileSize = 34;
  TileRadius = 7;
  TileFontSize = 15;
  TileGap = 8;
  { The rows of the left zone. }
  RowGap = 1;
  { The transport: the side buttons are circles of PrimaryHeight, the
    primary a pill of it. }
  PrimaryHeight = 26;
  { The room at each end of the primary button's caption. }
  PrimaryPad = 11;
  ButtonGap = 12;
  { The track under the transport. }
  TrackGap = 4;
  TrackWidth = 220;
  TrackNarrow = 140;
  TrackHeight = 3;
  { The stretch that slides on the track while something is under way:
    its width as a part of the track, the timer's step in ms and the
    steps of one sweep there and back. }
  BusyPart = 4;
  BusyStep = 40;
  BusySweep = 44;
  { The name and the branch are cut to these. }
  NameMax = 220;
  BranchMax = 200;

function StatusButton(const ACaption, AIcon: string; ATone: TGittanStatusTone;
  AEnabled: boolean): TGittanStatusButton;
begin
  Result.Caption := ACaption;
  Result.Icon := AIcon;
  Result.Tone := ATone;
  Result.Enabled := AEnabled;
end;

function SameButton(const A, B: TGittanStatusButton): boolean;
begin
  Result := (A.Caption = B.Caption) and (A.Icon = B.Icon) and (A.Tone = B.Tone) and
    (A.Enabled = B.Enabled);
end;

{ The first character of S, UTF-8 sequences kept whole, in upper case
  when it is ASCII. }
function Initial(const S: string): string;
var
  n: integer;
begin
  if S = '' then
    Exit('');
  n := 1;
  while (n < Length(S)) and (Ord(S[n + 1]) and $C0 = $80) do
    Inc(n);
  Result := UpperCase(Copy(S, 1, n));
end;

{ S cut to AWidth on ACanvas with an ellipsis; nothing when not even
  one character fits. }
function Ellipsize(ACanvas: TCanvas; const S: string; AWidth: integer): string;
begin
  Result := FitTextRight(ACanvas, S, AWidth);
  if Result = Ellipsis then
    Result := '';
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
  for M in [HintPassed, HintFailed, HintPending, HintLink, HintSwitch, HintFolder, HintBranch, HintPull,
    HintComment, HintSync, HintStash, HintFetch, HintDown, HintUp, HintPlay, HintSkip,
    HintWarn, HintSearch, HintUndo, HintRedo] do
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
procedure FillHover(ACanvas: TCanvas; const ARect: TRect; ARadius: integer; AColor: TColor);
begin
  ACanvas.Pen.Style := psClear;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := AColor;
  ACanvas.RoundRect(ARect, ARadius, ARadius);
  ACanvas.Pen.Style := psSolid;
  ACanvas.Brush.Style := bsClear;
end;

procedure DrawChevron(ACanvas: TCanvas; CX, CY: integer; AColor: TColor);
begin
  ACanvas.Pen.Color := AColor;
  ACanvas.Pen.Width := 1;
  ACanvas.Polyline([Point(CX - 3, CY - 1), Point(CX, CY + 2), Point(CX + 3, CY - 1)]);
end;

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
  end
  else if AIcon = HintComment then
  begin
    { A speech bubble: a rounded box with a tail at the lower left. }
    ACanvas.Pen.Color := AColor;
    ACanvas.Pen.Width := 1;
    ACanvas.RoundRect(L, T + 1, L + S, T + S - 3, 4, 4);
    ACanvas.Polyline([Point(L + 3, T + S - 4), Point(L + 3, T + S), Point(L + 7, T + S - 4)]);
  end
  else if AIcon = HintSync then
  begin
    { An arrow up on the left and one down on the right. }
    ACanvas.Pen.Color := AColor;
    ACanvas.Pen.Width := 1;
    ACanvas.Line(L + 3, T + 1, L + 3, T + S);
    ACanvas.Polyline([Point(L, T + 4), Point(L + 3, T + 1), Point(L + 6, T + 4)]);
    ACanvas.Line(L + S - 3, T, L + S - 3, T + S - 1);
    ACanvas.Polyline([Point(L + S - 6, T + S - 4), Point(L + S - 3, T + S - 1),
      Point(L + S, T + S - 4)]);
  end
  else if AIcon = HintStash then
  begin
    { A box: the lid across the top, the body under it with a short
      handle in the middle. }
    ACanvas.Pen.Color := AColor;
    ACanvas.Pen.Width := 1;
    ACanvas.RoundRect(L, T, L + S, T + S div 3 + 1, 2, 2);
    ACanvas.Rectangle(L + 1, T + S div 3, L + S - 1, T + S);
    ACanvas.Line(CX - 2, T + S div 3 + 3, CX + 3, T + S div 3 + 3);
  end
  else if AIcon = HintFetch then
  begin
    { Two arcs round a circle, each with an arrowhead at its clockwise
      end, as a refresh icon. }
    ACanvas.Pen.Color := AColor;
    ACanvas.Pen.Width := 1;
    ACanvas.Arc(L, T, L + S, T + S, 20 * 16, 140 * 16);
    ACanvas.Arc(L, T, L + S, T + S, 200 * 16, 140 * 16);
    ACanvas.Polyline([Point(L + S - 4, T + 1), Point(L + S - 1, T + 4), Point(L + S - 4, T + 6)]);
    ACanvas.Polyline([Point(L + 3, T + S - 2), Point(L, T + S - 5), Point(L + 3, T + S - 7)]);
  end
  else if AIcon = HintDown then
  begin
    ACanvas.Pen.Color := AColor;
    ACanvas.Line(CX, T + 1, CX, T + S - 1);
    ACanvas.Polyline([Point(CX - 4, T + S - 5), Point(CX, T + S - 1), Point(CX + 4, T + S - 5)]);
  end
  else if AIcon = HintUp then
  begin
    ACanvas.Pen.Color := AColor;
    ACanvas.Line(CX, T + 1, CX, T + S - 1);
    ACanvas.Polyline([Point(CX - 4, T + 5), Point(CX, T + 1), Point(CX + 4, T + 5)]);
  end
  else if AIcon = HintPlay then
  begin
    { A filled triangle pointing right. }
    ACanvas.Pen.Color := AColor;
    ACanvas.Pen.Width := 1;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := AColor;
    ACanvas.Polygon([Point(L + 3, T + 1), Point(L + S - 1, CY), Point(L + 3, T + S - 1)]);
    ACanvas.Brush.Style := bsClear;
  end
  else if AIcon = HintSkip then
  begin
    { A filled triangle at a bar. }
    ACanvas.Pen.Color := AColor;
    ACanvas.Pen.Width := 1;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := AColor;
    ACanvas.Polygon([Point(L + 1, T + 1), Point(L + S - 4, CY), Point(L + 1, T + S - 1)]);
    ACanvas.Brush.Style := bsClear;
    ACanvas.Pen.Width := 2;
    ACanvas.Line(L + S - 2, T + 1, L + S - 2, T + S - 1);
  end
  else if AIcon = HintWarn then
  begin
    { A warning triangle with a mark in it. }
    ACanvas.Pen.Color := AColor;
    ACanvas.Pen.Width := 1;
    ACanvas.Polygon([Point(CX, T), Point(L + S, T + S - 1), Point(L, T + S - 1)]);
    ACanvas.Pen.Width := 2;
    ACanvas.Line(CX, T + 4, CX, T + S - 6);
    ACanvas.Line(CX, T + S - 4, CX, T + S - 2);
  end
  else if AIcon = HintSparkle then
  begin
    { A star of four points, its sides drawn in to the middle, filled,
      as the filter field's action has it. }
    ACanvas.Pen.Color := AColor;
    ACanvas.Pen.Width := 1;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := AColor;
    ACanvas.Polygon([Point(CX, T), Point(CX + S div 6, CY - S div 6), Point(L + S, CY),
      Point(CX + S div 6, CY + S div 6), Point(CX, T + S), Point(CX - S div 6, CY + S div 6),
      Point(L, CY), Point(CX - S div 6, CY - S div 6)]);
    ACanvas.Brush.Style := bsClear;
  end
  else if AIcon = HintSearch then
  begin
    { A magnifying glass: the lens on the upper left, the handle down to
      the lower right. }
    ACanvas.Pen.Color := AColor;
    ACanvas.Pen.Width := 1;
    ACanvas.Ellipse(L, T, L + S * 2 div 3 + 1, T + S * 2 div 3 + 1);
    ACanvas.Pen.Width := 2;
    ACanvas.Line(L + S * 2 div 3 - 1, T + S * 2 div 3 - 1, L + S - 1, T + S - 1);
  end
  else if (AIcon = HintUndo) or (AIcon = HintRedo) then
  begin
    { The upper half of a circle, with an arrowhead pointing down at its
      left end (undo) or its right end (redo). }
    ACanvas.Pen.Color := AColor;
    ACanvas.Pen.Width := 1;
    ACanvas.Arc(L + 1, T + 2, L + S - 1, T + S + 2, 0, 180 * 16);
    if AIcon = HintUndo then
      ACanvas.Polyline([Point(L - 2, CY - 1), Point(L + 1, CY + 3), Point(L + 4, CY - 1)])
    else
      ACanvas.Polyline([Point(L + S - 4, CY - 1), Point(L + S - 1, CY + 3),
        Point(L + S + 2, CY - 1)]);
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
        Inc(H, LineH + Px(HintIconGap));
      W := Max(W, H);
    end;
    W := Min(W, MaxWidth);
    H := Lines.Count * LineH + Max(0, Lines.Count - 1) * Px(HintLineGap);
    Result := Rect(0, 0, W + 2 * Px(HintPad), H + 2 * Px(HintPad));
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
    Y := Px(HintPad);
    for i := 0 to Lines.Count - 1 do
    begin
      SplitLine(Lines[i], LineIcon, LineText);
      X := Px(HintPad);
      if LineIcon <> '' then
      begin
        DrawIcon(LineIcon, X, Y, LineH);
        Inc(X, LineH + Px(HintIconGap));
      end;
      if (i = 0) and (Lines.Count > 1) then
        Canvas.Font.Style := [fsBold]
      else
        Canvas.Font.Style := [];
      Canvas.Font.Color := FText;
      Canvas.Brush.Style := bsClear;
      Canvas.TextOut(X, Y, LineText);
      Inc(Y, LineH + Px(HintLineGap));
    end;
  finally
    Lines.Free;
  end;
end;

{ TGittanStatusBar }

{ TGittanStatusBar }

constructor TGittanStatusBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Height := Px(BarHeight);
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.OnTimer := @TimerTimer;
  FBusyTimer := TTimer.Create(Self);
  FBusyTimer.Enabled := False;
  FBusyTimer.Interval := BusyStep;
  FBusyTimer.OnTimer := @BusyTimerTimer;
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

procedure TGittanStatusBar.SetBase(const ABase: string; AClickable, AClosable: boolean);
begin
  if AClickable then
    Include(FClickable, spBase)
  else
    Exclude(FClickable, spBase);
  AClosable := AClosable and (ABase <> '');
  if AClosable then
    Include(FClickable, spBaseClose)
  else
    Exclude(FClickable, spBaseClose);
  if AClosable <> FBaseClosable then
  begin
    FBaseClosable := AClosable;
    Invalidate;
  end;
  Change(FBase, ABase);
end;

procedure TGittanStatusBar.SetStashes(ACount: integer);
begin
  if ACount = FStashes then
    Exit;
  FStashes := ACount;
  Invalidate;
end;

procedure TGittanStatusBar.SetTransport(const ALeft, APrimary, ARight: TGittanStatusButton);
begin
  if SameButton(FButtons[spLeft], ALeft) and SameButton(FButtons[spPrimary], APrimary) and
    SameButton(FButtons[spRight], ARight) then
    Exit;
  FButtons[spLeft] := ALeft;
  FButtons[spPrimary] := APrimary;
  FButtons[spRight] := ARight;
  Invalidate;
end;

procedure TGittanStatusBar.SetSync(AAhead, ABehind: integer; AShown: boolean);
begin
  if (FAhead = AAhead) and (FBehind = ABehind) and (FSyncShown = AShown) then
    Exit;
  FAhead := AAhead;
  FBehind := ABehind;
  FSyncShown := AShown;
  Invalidate;
end;

procedure TGittanStatusBar.SetOperation(const AText: string; APos, ATotal: integer);
begin
  if (FOperation = AText) and (FOperationPos = APos) and (FOperationTotal = ATotal) then
    Exit;
  FOperation := AText;
  FOperationPos := APos;
  FOperationTotal := ATotal;
  Invalidate;
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

procedure TGittanStatusBar.SetPullThreads(AOpen, AAll: integer);
begin
  if (FPullOpen = AOpen) and (FPullThreads = AAll) then
    Exit;
  FPullOpen := AOpen;
  FPullThreads := AAll;
  Invalidate;
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
  FMessageIcon := '';
  SetBusy(False);
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

procedure TGittanStatusBar.ShowBusy(const AText: string; const AIcon: string);
begin
  FTimer.Enabled := False;
  if (FMessage = AText) and FBusy and (FMessageIcon = AIcon) then
    Exit;
  FMessage := AText;
  FMessageTone := stNormal;
  FMessageIcon := AIcon;
  SetBusy(AText <> '');
  Repaint;
end;

procedure TGittanStatusBar.ClearMessage;
begin
  FTimer.Enabled := False;
  SetBusy(False);
  FMessageIcon := '';
  Change(FMessage, '');
end;

procedure TGittanStatusBar.SetBusy(AValue: boolean);
begin
  if FBusy = AValue then
    Exit;
  FBusy := AValue;
  FBusyPhase := 0;
  FBusyRect := Rect(0, 0, 0, 0);
  FBusyTimer.Enabled := AValue;
end;

{ Only the stretch on the line moves, and whatever moves the line
  paints the bar whole, so each tick paints the line's rectangle alone
  (FBusyRect, from the last Paint): a job of minutes would otherwise
  have the bar measure every part 25 times a second. }
procedure TGittanStatusBar.BusyTimerTimer(Sender: TObject);
begin
  FBusyPhase := (FBusyPhase + 1) mod BusySweep;
  if not IsVisible then
    Exit;
  if HandleAllocated and not IsRectEmpty(FBusyRect) then
    InvalidateRect(Handle, @FBusyRect, False)
  else
    Invalidate;
end;

procedure TGittanStatusBar.TimerTimer(Sender: TObject);
begin
  ClearMessage;
end;

procedure TGittanStatusBar.SetProgress(const AText: string; APos, ATotal: integer;
  const AIcon: string);
begin
  if (FProgressText = AText) and (FProgressPos = APos) and (FProgressTotal = ATotal) and
    (FProgressIcon = AIcon) then
    Exit;
  FProgressText := AText;
  FProgressIcon := AIcon;
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

function TGittanStatusBar.Clickable(APart: TGittanStatusPart): boolean;
begin
  Result := APart in FClickable;
  if Result and (APart in [spLeft, spPrimary, spRight]) then
    Result := FButtons[APart].Enabled;
end;

function TGittanStatusBar.HotHint: string;
begin
  case FHot of
    spMessage: Result := FMessage;
    spProgress:
    begin
      Result := FHints[spProgress];
      if Result = '' then
        Result := FProgressText;
    end;
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
  R := FHintWindow.CalcHintRect(Max(200, Width - 2 * Px(Pad)), Tip, nil);
  P := ClientToScreen(Point(FRects[FHot].Left, FRects[FHot].Top));
  Types.OffsetRect(R, P.X, P.Y - R.Bottom - 4);
  MaxRight := ClientToScreen(Point(Width - Px(Pad), 0)).X;
  if R.Right > MaxRight then
    Types.OffsetRect(R, Max(ClientToScreen(Point(Px(Pad), 0)).X - R.Left,
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
  tested against are always those of the last paint. The three zones are
  measured first with every part shown; while they do not fit, the parts
  give way one step at a time, from the outside in (the caret's position
  and the pull request's state first, the track and the update badge
  last). Then the left zone is drawn from the left edge, the right zone
  from the right edge, and the transport and the track centered between
  them. }
procedure TGittanStatusBar.Paint;
var
  P: TGittanStatusPart;
  TextH, IconW, X, Y, W, Right, LeftW, MidW, RightW, MidX, MidTop, MidH: integer;
  Row1Y, Row2Y, TrackW, NumW, Avail, Step, TrackLeft, Fill, BusyW, BusyY: integer;
  ShowName, ShowBase, ShowStash, ShowPull, ShowPullNote, ShowFiles, ShowPosition,
    ShowUpdate, ShowTrack, TransportShown, TrackNumbers, TrackLine, TrackBusy,
    BusyTop: boolean;
  Title, Branch, Base, TrackText, TrackIcon, Behind, Ahead, Checks, Threads: string;
  TrackTone: TGittanStatusTone;
  TrackPart: TGittanStatusPart;
  TrackPos, TrackTotal: integer;

  { The room the icon before a busy message takes. }
  function TrackIconWidth: integer;
  begin
    if TrackIcon = '' then
      Result := 0
    else
      Result := IconW;
  end;

  function ChipRect(AX, AY, AWidth, AHeight: integer): TRect;
  begin
    Result := Rect(AX, AY, AX + AWidth, AY + AHeight);
  end;

  { The fill under the mouse, for a part that answers a click. }
  procedure DrawHot(APart: TGittanStatusPart);
  begin
    if (FHot = APart) and Clickable(APart) then
      FillHover(Canvas, FRects[APart], 6, FHover);
  end;

  function BadgeWidth(const S: string): integer;
  begin
    Result := Canvas.TextWidth(S) + 2 * (Px(ChipPadX) + 2);
  end;

  { A badge: the text in its tone on a tint of it, the corners round. }
  procedure DrawBadge(APart: TGittanStatusPart; AX, AY: integer; const S: string;
    ATone: TGittanStatusTone);
  var
    R: TRect;
  begin
    R := ChipRect(AX, AY - Px(ChipPadY), BadgeWidth(S), TextH + 2 * Px(ChipPadY));
    FRects[APart] := R;
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    if (FHot = APart) and Clickable(APart) then
      Canvas.Brush.Color := MixColor(FBack, FTones[ATone], 0.3)
    else
      Canvas.Brush.Color := MixColor(FBack, FTones[ATone], 0.18);
    Canvas.RoundRect(R, R.Height, R.Height);
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := FTones[ATone];
    Canvas.TextOut(AX + Px(ChipPadX) + 2, AY, S);
  end;

  { A dim text, in a chip rectangle for the mouse. }
  procedure DrawText(APart: TGittanStatusPart; AX, AY: integer; const S: string;
    AColor: TColor);
  begin
    FRects[APart] := ChipRect(AX - Px(ChipPadX), AY - Px(ChipPadY), Canvas.TextWidth(S) +
      2 * Px(ChipPadX), TextH + 2 * Px(ChipPadY));
    DrawHot(APart);
    Canvas.Font.Color := AColor;
    Canvas.TextOut(AX, AY, S);
  end;

  { The cross after the base, a square of the text's height on its row,
    on a filled circle under the mouse. }
  procedure DrawClose(AX, AY: integer);
  var
    R: TRect;
    Inset: integer;
  begin
    R := ChipRect(AX, AY, TextH, TextH);
    FRects[spBaseClose] := R;
    if FHot = spBaseClose then
    begin
      Canvas.Pen.Style := psClear;
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := FHover;
      Canvas.Ellipse(R);
      Canvas.Pen.Style := psSolid;
      Canvas.Brush.Style := bsClear;
      Canvas.Pen.Color := FText;
    end
    else
      Canvas.Pen.Color := FDim;
    Inset := TextH * 3 div 10;
    Canvas.Pen.Width := Max(1, Px(3) div 2);
    Canvas.Line(R.Left + Inset, R.Top + Inset, R.Right - Inset, R.Bottom - Inset);
    Canvas.Line(R.Right - Inset, R.Top + Inset, R.Left + Inset, R.Bottom - Inset);
    Canvas.Pen.Width := 1;
  end;

  { A side button without an icon keeps its place, so the primary one
    stays in the middle. }
  function ButtonWidth(APart: TGittanStatusPart): integer;
  begin
    if (FButtons[APart].Icon = '') and (APart = spPrimary) then
      Exit(0);
    if APart = spPrimary then
    begin
      { The caption is bold, so it is measured bold. }
      Canvas.Font.Style := [fsBold];
      Result := 2 * Px(PrimaryPad) + IconW + Canvas.TextWidth(FButtons[APart].Caption);
      Canvas.Font.Style := [];
    end
    else
      Result := Px(PrimaryHeight);
  end;

  { A side button is a circle with the icon in it, filled under the
    mouse; the primary a pill filled in its tone with the icon and the
    caption. }
  procedure DrawButton(APart: TGittanStatusPart; AX, AY: integer);
  var
    B: TGittanStatusButton;
    R: TRect;
    FillColor, Ink: TColor;
    Hot: boolean;
  begin
    B := FButtons[APart];
    if B.Icon = '' then
      Exit;
    R := ChipRect(AX, AY, ButtonWidth(APart), Px(PrimaryHeight));
    FRects[APart] := R;
    Hot := (FHot = APart) and Clickable(APart);
    if APart = spPrimary then
    begin
      case B.Tone of
        stGood: FillColor := FHover;
        stWarn: FillColor := FTones[stWarn];
        stBad: FillColor := FTones[stBad];
        else
          FillColor := FAccent;
      end;
      if Hot then
        FillColor := MixColor(FillColor, FText, 0.12);
      if not B.Enabled then
        FillColor := MixColor(FBack, FillColor, 0.5);
      case B.Tone of
        stGood: Ink := FDim;
        stWarn: Ink := RGBToColor(26, 26, 26);
        else
          Ink := clWhite;
      end;
      Canvas.Pen.Style := psClear;
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := FillColor;
      Canvas.RoundRect(R, Px(PrimaryHeight), Px(PrimaryHeight));
      Canvas.Pen.Style := psSolid;
      Canvas.Brush.Style := bsClear;
      X := AX + Px(PrimaryPad);
      if B.Tone = stGood then
        DrawStatusIcon(Canvas, B.Icon, X, AY + (Px(PrimaryHeight) - TextH) div 2, TextH,
          FTones[stGood])
      else
        DrawStatusIcon(Canvas, B.Icon, X, AY + (Px(PrimaryHeight) - TextH) div 2, TextH, Ink);
      Canvas.Font.Style := [fsBold];
      Canvas.Font.Color := Ink;
      Canvas.TextOut(X + IconW, AY + (Px(PrimaryHeight) - TextH) div 2, B.Caption);
      Canvas.Font.Style := [];
    end
    else
    begin
      if Hot then
      begin
        Canvas.Pen.Style := psClear;
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := FHover;
        Canvas.Ellipse(R);
        Canvas.Pen.Style := psSolid;
        Canvas.Brush.Style := bsClear;
        Ink := FText;
      end
      else
        Ink := FDim;
      if not B.Enabled then
        Ink := MixColor(FBack, FDim, 0.45);
      DrawStatusIcon(Canvas, B.Icon, AX + (Px(PrimaryHeight) - (TextH - 4)) div 2,
        AY + (Px(PrimaryHeight) - TextH) div 2, TextH, Ink);
    end;
  end;

  function PullWidth: integer;
  begin
    Result := IconW + Canvas.TextWidth(FPull);
    if ShowPullNote and (FPullNote <> '') then
      Inc(Result, Px(Gap) div 2 + Canvas.TextWidth(FPullNote));
    if FPullTone <> stNormal then
      Inc(Result, Px(Gap) div 2 + IconW - Px(IconGap) + Canvas.TextWidth(Checks));
    if FPullThreads > 0 then
      Inc(Result, Px(Gap) div 2 + IconW - Px(IconGap) + Canvas.TextWidth(Threads));
    Inc(Result, 2 * Px(ChipPadX));
  end;

  { The width of the left zone with the parts shown now. }
  function LeftWidth: integer;
  var
    Block, Row2: integer;
  begin
    if (FTitle = '') and (FBranch = '') then
      Exit(0);
    Result := Px(TileSize) + Px(TileGap);
    Block := 0;
    Canvas.Font.Style := [fsBold];
    if ShowName and (Title <> '') then
      Block := Canvas.TextWidth(Title) + 2 * Px(ChipPadX);
    Canvas.Font.Style := [];
    Row2 := 0;
    if Branch <> '' then
      Row2 := IconW + Canvas.TextWidth(Branch) + Px(ChevronWidth) + 2 * Px(ChipPadX);
    if ShowBase and (Base <> '') then
    begin
      Inc(Row2, Px(Gap) div 2 + Canvas.TextWidth(Base) + 2 * Px(ChipPadX));
      if FBaseClosable then
        Inc(Row2, TextH);
    end;
    Inc(Result, Max(Block, Row2));
    if ShowStash and (FStashes > 0) then
      Inc(Result, Px(Gap) + IconW + Canvas.TextWidth(IntToStr(FStashes)) + 2 * Px(ChipPadX));
  end;

  { The width of the transport and the track, the wider of the two. }
  function MidWidth: integer;
  var
    T: integer;
  begin
    Result := 0;
    if TransportShown then
      Result := ButtonWidth(spLeft) + ButtonWidth(spPrimary) + ButtonWidth(spRight) +
        2 * Px(ButtonGap);
    if not ShowTrack then
      Exit;
    if TrackNumbers then
      T := 2 * NumW + 2 * Px(Gap) + TrackW
    else
    begin
      T := TrackIconWidth + Canvas.TextWidth(TrackText);
      if TrackLine then
        Inc(T, Px(Gap) + TrackW);
      if BusyTop then
        T := Max(T, TrackW);
    end;
    Result := Max(Result, T);
  end;

  function RightWidth: integer;
  begin
    Result := 0;
    if ShowFiles and (FFiles <> '') then
      Inc(Result, Canvas.TextWidth(FFiles) + 2 * Px(ChipPadX) + Px(Gap));
    if ShowPosition and (FPosition <> '') then
      Inc(Result, Canvas.TextWidth(FPosition) + 2 * Px(ChipPadX) + Px(Gap));
    if ShowPull and (FPull <> '') then
      Inc(Result, PullWidth + Px(Gap));
    if ShowUpdate and (FUpdate <> '') then
      Inc(Result, BadgeWidth(FUpdate) + Px(Gap));
    if Result > 0 then
      Dec(Result, Px(Gap));
  end;

  function Needed: integer;
  begin
    LeftW := LeftWidth;
    MidW := MidWidth;
    RightW := RightWidth;
    Result := LeftW + MidW + RightW;
    if MidW > 0 then
      Inc(Result, 2 * Px(Gap));
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
  Canvas.Font.Style := [];
  Canvas.Brush.Style := bsClear;
  TextH := Canvas.TextHeight('Xg');
  IconW := TextH - 4 + Px(IconGap);

  { What the track carries: a message first, then a progress, then the
    operation, else the sync counts. }
  Checks := '';
  if FPullChecks > 0 then
    Checks := IntToStr(FPullChecks);
  Threads := '';
  if FPullOpen > 0 then
    Threads := IntToStr(FPullOpen);
  TrackNumbers := False;
  TrackLine := False;
  TrackBusy := False;
  TrackText := '';
  TrackIcon := '';
  TrackTone := stNormal;
  TrackPart := spNone;
  TrackPos := 0;
  TrackTotal := 0;
  if FMessage <> '' then
  begin
    TrackText := FMessage;
    TrackTone := FMessageTone;
    TrackPart := spMessage;
    TrackIcon := FMessageIcon;
    TrackBusy := FBusy;
  end
  else if FProgressTotal > 0 then
  begin
    TrackText := FProgressText;
    TrackLine := True;
    TrackPart := spProgress;
    TrackPos := FProgressPos;
    TrackTotal := FProgressTotal;
    TrackTone := stNormal;
    TrackIcon := FProgressIcon;
  end
  else if FOperation <> '' then
  begin
    TrackText := FOperation;
    TrackLine := FOperationTotal > 0;
    TrackPos := FOperationPos;
    TrackTotal := FOperationTotal;
    TrackTone := stWarn;
  end
  else if FSyncShown then
  begin
    TrackNumbers := True;
    TrackPart := spSync;
  end;
  ShowTrack := TrackNumbers or (TrackText <> '');
  TransportShown := FButtons[spPrimary].Icon <> '';
  { Something under way that leaves none of the buttons to click takes
    their row, with its line on its own under it; one that leaves them
    (the agent's) goes under them, the line under its text. }
  BusyTop := False;
  if TrackBusy then
  begin
    BusyTop := True;
    for P := spLeft to spRight do
      if FButtons[P].Enabled and (FButtons[P].Icon <> '') then
        BusyTop := False;
    if BusyTop then
      TransportShown := False;
  end;
  Behind := '↓' + IntToStr(FBehind);
  Ahead := '↑' + IntToStr(FAhead);
  NumW := Max(Canvas.TextWidth(Behind), Canvas.TextWidth(Ahead));
  Title := Ellipsize(Canvas, FTitle, Px(NameMax));
  Branch := Ellipsize(Canvas, FBranch, Px(BranchMax));
  Base := FBase;
  TrackW := Px(TrackWidth);
  ShowName := True;
  ShowBase := True;
  ShowStash := True;
  ShowPull := True;
  ShowPullNote := True;
  ShowFiles := True;
  ShowPosition := True;
  ShowUpdate := True;

  { Giving way, from the outside in. }
  Avail := Width - 2 * Px(Pad);
  Step := 0;
  while (Needed > Avail) and (Step < 9) do
  begin
    Inc(Step);
    case Step of
      1: ShowPosition := False;
      2: ShowPullNote := False;
      3: ShowFiles := False;
      4:
      begin
        ShowStash := False;
        ShowBase := False;
      end;
      5: ShowName := False;
      6: TrackW := Px(TrackNarrow);
      7: ShowPull := False;
      { A busy message keeps its text and its line. }
      8: if not TrackBusy and (TrackNumbers or TrackLine) then
          ShowTrack := False;
      9: ShowUpdate := False;
    end;
  end;
  if Needed > Avail then
  begin
    { A message is cut to what is left. }
    if (TrackText <> '') and not TrackLine then
    begin
      TrackText := Ellipsize(Canvas, TrackText, Max(40, Avail - LeftW - RightW -
        2 * Px(Gap) - TrackIconWidth));
      Needed;
    end;
  end;

  { The rows. }
  Row1Y := (Height - 2 * TextH - Px(RowGap)) div 2;
  Row2Y := Row1Y + TextH + Px(RowGap);
  MidH := 0;
  if TransportShown then
    MidH := Px(PrimaryHeight);
  if ShowTrack then
  begin
    if MidH > 0 then
      Inc(MidH, Px(TrackGap));
    Inc(MidH, TextH);
  end;
  if BusyTop then
    MidH := Px(PrimaryHeight) + Px(TrackGap) + TextH;
  MidTop := (Height - MidH) div 2;

  { Left: the tile, the name over the branch and the base, the stashes. }
  X := Px(Pad);
  if LeftW > 0 then
  begin
    FRects[spRepo] := ChipRect(X, (Height - Px(TileSize)) div 2, Px(TileSize), Px(TileSize));
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    if (FHot = spRepo) and Clickable(spRepo) then
      Canvas.Brush.Color := MixColor(FBack, FAccent, 0.3)
    else
      Canvas.Brush.Color := MixColor(FBack, FAccent, 0.18);
    Canvas.RoundRect(FRects[spRepo], Px(TileRadius) * 2, Px(TileRadius) * 2);
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Size := TileFontSize;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := FAccent;
    Title := Initial(ExtractFileName(FTitle));
    if Title = '' then
      Title := Initial(FBranch);
    Canvas.TextOut(X + (Px(TileSize) - Canvas.TextWidth(Title)) div 2,
      (Height - Canvas.TextHeight(Title)) div 2, Title);
    Canvas.Font := Font;
    Canvas.Font.Style := [];
    Title := Ellipsize(Canvas, FTitle, Px(NameMax));
    Inc(X, Px(TileSize) + Px(TileGap));
    W := X;
    if ShowName and (Title <> '') then
    begin
      Canvas.Font.Style := [fsBold];
      if Branch = '' then
        Y := (Height - TextH) div 2
      else
        Y := Row1Y;
      { The name shares the tile's click, so the tile's rectangle grows
        over it. }
      FRects[spRepo].Right := X + Canvas.TextWidth(Title) + 2 * Px(ChipPadX);
      Canvas.Font.Color := FText;
      Canvas.TextOut(X + Px(ChipPadX), Y, Title);
      Canvas.Font.Style := [];
      W := FRects[spRepo].Right;
    end;
    if Branch <> '' then
    begin
      if not (ShowName and (Title <> '')) then
        Y := (Height - TextH) div 2
      else
        Y := Row2Y;
      FRects[spBranch] := ChipRect(X, Y - Px(ChipPadY), IconW + Canvas.TextWidth(Branch) +
        Px(ChevronWidth) + 2 * Px(ChipPadX), TextH + 2 * Px(ChipPadY));
      DrawHot(spBranch);
      DrawStatusIcon(Canvas, HintBranch, X + Px(ChipPadX), Y, TextH, FDim);
      Canvas.Font.Color := FText;
      Canvas.TextOut(X + Px(ChipPadX) + IconW, Y, Branch);
      DrawChevron(Canvas, X + Px(ChipPadX) + IconW + Canvas.TextWidth(Branch) + Px(ChevronWidth) div 2,
        Y + TextH div 2, FDim);
      W := Max(W, FRects[spBranch].Right);
      if ShowBase and (Base <> '') then
      begin
        DrawText(spBase, FRects[spBranch].Right + Px(Gap) div 2 + Px(ChipPadX), Y, Base, FDim);
        W := Max(W, FRects[spBase].Right);
        if FBaseClosable then
        begin
          DrawClose(FRects[spBase].Right, Y);
          W := Max(W, FRects[spBaseClose].Right);
        end;
      end;
    end;
    X := W;
    if ShowStash and (FStashes > 0) then
    begin
      Inc(X, Px(Gap));
      Y := (Height - TextH) div 2;
      FRects[spStash] := ChipRect(X, Y - Px(ChipPadY), IconW +
        Canvas.TextWidth(IntToStr(FStashes)) + 2 * Px(ChipPadX), TextH + 2 * Px(ChipPadY));
      DrawHot(spStash);
      DrawStatusIcon(Canvas, HintStash, X + Px(ChipPadX), Y, TextH, FDim);
      Canvas.Font.Color := FDim;
      Canvas.TextOut(X + Px(ChipPadX) + IconW, Y, IntToStr(FStashes));
      X := FRects[spStash].Right;
    end;
  end;
  LeftW := X;

  { Right, from the right edge: the files, the position, the pull
    request, the update. }
  Right := Width - Px(Pad);
  Y := (Height - TextH) div 2;
  if ShowFiles and (FFiles <> '') then
  begin
    W := Canvas.TextWidth(FFiles);
    DrawText(spFiles, Right - W - Px(ChipPadX), Y, FFiles, FDim);
    Dec(Right, W + 2 * Px(ChipPadX) + Px(Gap));
  end;
  if ShowPosition and (FPosition <> '') then
  begin
    W := Canvas.TextWidth(FPosition);
    DrawText(spPosition, Right - W - Px(ChipPadX), Y, FPosition, FDim);
    Dec(Right, W + 2 * Px(ChipPadX) + Px(Gap));
  end;
  if ShowPull and (FPull <> '') then
  begin
    { The pull request icon, the number, the state dimmed, then the
      checks as an icon in their tone with the count of the failing or
      pending ones, and the review threads as a speech bubble with the
      count of the open ones. }
    W := PullWidth;
    X := Right - W;
    FRects[spPull] := ChipRect(X, Y - Px(ChipPadY), W, TextH + 2 * Px(ChipPadY));
    DrawHot(spPull);
    Inc(X, Px(ChipPadX));
    DrawStatusIcon(Canvas, HintPull, X, Y, TextH, FDim);
    Inc(X, IconW);
    Canvas.Font.Color := FText;
    Canvas.TextOut(X, Y, FPull);
    Inc(X, Canvas.TextWidth(FPull));
    if ShowPullNote and (FPullNote <> '') then
    begin
      Inc(X, Px(Gap) div 2);
      Canvas.Font.Color := FDim;
      Canvas.TextOut(X, Y, FPullNote);
      Inc(X, Canvas.TextWidth(FPullNote));
    end;
    if FPullTone <> stNormal then
    begin
      Inc(X, Px(Gap) div 2);
      case FPullTone of
        stGood: DrawStatusIcon(Canvas, HintPassed, X, Y, TextH, FTones[stGood]);
        stBad: DrawStatusIcon(Canvas, HintFailed, X, Y, TextH, FTones[stBad]);
        stWarn: DrawStatusIcon(Canvas, HintPending, X, Y, TextH, FTones[stWarn]);
      end;
      Inc(X, IconW - Px(IconGap));
      Canvas.Font.Color := FTones[FPullTone];
      Canvas.TextOut(X, Y, Checks);
      Inc(X, Canvas.TextWidth(Checks));
    end;
    if FPullThreads > 0 then
    begin
      Inc(X, Px(Gap) div 2);
      if FPullOpen > 0 then
        Canvas.Font.Color := FAccent
      else
        Canvas.Font.Color := FDim;
      DrawStatusIcon(Canvas, HintComment, X, Y, TextH, Canvas.Font.Color);
      Inc(X, IconW - Px(IconGap));
      Canvas.TextOut(X, Y, Threads);
    end;
    Dec(Right, W + Px(Gap));
  end;
  if ShowUpdate and (FUpdate <> '') then
  begin
    W := BadgeWidth(FUpdate);
    DrawBadge(spUpdate, Right - W, Y, FUpdate, stGood);
    Dec(Right, W + Px(Gap));
  end;
  RightW := Width - Px(Pad) - Right;

  { Middle: the transport over the track, centered in the window while
    the zones leave room for that, else between them. }
  if MidW = 0 then
    Exit;
  MidX := (Width - MidW) div 2;
  if MidX < LeftW + Px(Gap) then
    MidX := LeftW + Px(Gap);
  if MidX + MidW > Right - Px(Gap) then
    MidX := Max(LeftW + Px(Gap), Right - Px(Gap) - MidW);
  Y := MidTop;
  if TransportShown then
  begin
    W := ButtonWidth(spLeft) + ButtonWidth(spPrimary) + ButtonWidth(spRight) + 2 * Px(ButtonGap);
    X := MidX + (MidW - W) div 2;
    DrawButton(spLeft, X, Y);
    Inc(X, ButtonWidth(spLeft) + Px(ButtonGap));
    DrawButton(spPrimary, X, Y);
    Inc(X, ButtonWidth(spPrimary) + Px(ButtonGap));
    DrawButton(spRight, X, Y);
    Inc(Y, Px(PrimaryHeight) + Px(TrackGap));
  end;
  if not ShowTrack then
    Exit;
  if TrackNumbers then
  begin
    W := 2 * NumW + 2 * Px(Gap) + TrackW;
    X := MidX + (MidW - W) div 2;
    FRects[spSync] := ChipRect(X - Px(ChipPadX), Y - Px(ChipPadY), W + 2 * Px(ChipPadX),
      TextH + 2 * Px(ChipPadY));
    DrawHot(spSync);
    if FBehind > 0 then
      Canvas.Font.Color := FText
    else
      Canvas.Font.Color := FDim;
    Canvas.TextOut(X + NumW - Canvas.TextWidth(Behind), Y, Behind);
    TrackLeft := X + NumW + Px(Gap);
    if FAhead > 0 then
      Canvas.Font.Color := FText
    else
      Canvas.Font.Color := FDim;
    Canvas.TextOut(TrackLeft + TrackW + Px(Gap), Y, Ahead);
    TrackLine := True;
    TrackTotal := 0;
  end
  else if TrackBusy then
  begin
    { The icon and the text centered in the accent, in the buttons' row
      or under the buttons; then the line, centered on its own row under
      the text in the buttons' row, else as wide as the text right under
      it. }
    BusyW := TrackIconWidth + Canvas.TextWidth(TrackText);
    X := MidX + (MidW - BusyW) div 2;
    if BusyTop then
      Inc(Y, (Px(PrimaryHeight) - TextH) div 2);
    FRects[spMessage] := ChipRect(X, Y - Px(ChipPadY), BusyW, TextH + 2 * Px(ChipPadY));
    Canvas.Font.Color := FAccent;
    if TrackIcon <> '' then
      DrawStatusIcon(Canvas, TrackIcon, X, Y, TextH, FAccent);
    Canvas.TextOut(X + TrackIconWidth, Y, TrackText);
    if BusyTop then
    begin
      TrackLeft := MidX + (MidW - TrackW) div 2;
      BusyY := MidTop + Px(PrimaryHeight) + Px(TrackGap) + (TextH - Px(TrackHeight)) div 2;
    end
    else
    begin
      TrackLeft := X;
      TrackW := BusyW;
      BusyY := Y + TextH + Px(1);
    end;
    FBusyRect := Rect(TrackLeft, BusyY, TrackLeft + TrackW, BusyY + Px(TrackHeight));
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FHover;
    Canvas.RoundRect(TrackLeft, BusyY, TrackLeft + TrackW, BusyY + Px(TrackHeight),
      Px(TrackHeight), Px(TrackHeight));
    { A stretch of the accent eases from one end to the other and back,
      slowest at the ends. }
    Canvas.Brush.Color := FAccent;
    Fill := Max(Px(TrackHeight), TrackW div BusyPart);
    X := TrackLeft + Round((1 - Cos(2 * Pi * FBusyPhase / BusySweep)) / 2 * (TrackW - Fill));
    Canvas.RoundRect(X, BusyY, X + Fill, BusyY + Px(TrackHeight), Px(TrackHeight),
      Px(TrackHeight));
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsClear;
  end
  else
  begin
    W := TrackIconWidth + Canvas.TextWidth(TrackText);
    if TrackLine then
      Inc(W, Px(Gap) + TrackW);
    X := MidX + (MidW - W) div 2;
    if TrackPart <> spNone then
      FRects[TrackPart] := ChipRect(X, Y - Px(ChipPadY), W, TextH + 2 * Px(ChipPadY));
    Canvas.Font.Color := FTones[TrackTone];
    if TrackPart = spProgress then
      Canvas.Font.Color := FAccent
    else if (TrackTone = stNormal) and (TrackPart <> spMessage) then
      Canvas.Font.Color := FDim;
    if TrackIcon <> '' then
    begin
      DrawStatusIcon(Canvas, TrackIcon, X, Y, TextH, FAccent);
      Inc(X, IconW);
    end;
    Canvas.TextOut(X, Y, TrackText);
    TrackLeft := X + Canvas.TextWidth(TrackText) + Px(Gap);
  end;
  if TrackLine then
  begin
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FHover;
    W := Y + (TextH - Px(TrackHeight)) div 2;
    Canvas.RoundRect(TrackLeft, W, TrackLeft + TrackW, W + Px(TrackHeight), Px(TrackHeight),
      Px(TrackHeight));
    if TrackTotal > 0 then
    begin
      if TrackTone = stWarn then
        Canvas.Brush.Color := FTones[stWarn]
      else
        Canvas.Brush.Color := FAccent;
      Fill := Max(Px(TrackHeight), TrackW * Min(TrackPos, TrackTotal) div TrackTotal);
      Canvas.RoundRect(TrackLeft, W, TrackLeft + Fill, W + Px(TrackHeight), Px(TrackHeight),
        Px(TrackHeight));
    end;
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsClear;
  end;
end;

{ The repository's rectangle grows over its name, which spans both rows
  beside the tile, so the branch chip and the base under the name are
  tested first (the base's cross with them). }
function TGittanStatusBar.PartAt(X, Y: integer): TGittanStatusPart;
var
  P: TGittanStatusPart;
begin
  for P in [spBranch, spBase, spBaseClose] do
    if Types.PtInRect(FRects[P], Point(X, Y)) then
      Exit(P);
  for P := Succ(spNone) to High(P) do
    if Types.PtInRect(FRects[P], Point(X, Y)) then
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
  if Clickable(AValue) then
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

function TGittanStatusBar.PartScreenRect(APart: TGittanStatusPart): TRect;
begin
  if (FRects[APart].Right <= FRects[APart].Left) then
    Result := Rect(0, 0, 0, Height)
  else
    Result := FRects[APart];
  Result.TopLeft := ClientToScreen(Result.TopLeft);
  Result.BottomRight := ClientToScreen(Result.BottomRight);
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
  if (Part = spNone) or (Part <> PartAt(X, Y)) or not Clickable(Part) or
    not Assigned(FOnPartClick) then
    Exit;
  R.TopLeft := ClientToScreen(FRects[Part].TopLeft);
  R.BottomRight := ClientToScreen(FRects[Part].BottomRight);
  FOnPartClick(Self, Part, R);
end;

{ The form scales every control by its DPI after FormCreate, this one's
  height too, which is already the screen's: set it again. }
procedure TGittanStatusBar.DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
  const AXProportion, AYProportion: double);
begin
  inherited DoAutoAdjustLayout(AMode, AXProportion, AYProportion);
  if AMode = lapAutoAdjustForDPI then
    Height := Px(BarHeight);
end;

end.
