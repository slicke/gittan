unit gittan.commitgraph;

{** The commit graph: a panel in the middle of the form that shows the
  newest commits of every branch as a graph, each in its lane with the
  lines to its parents, the branches and tags on it as chips, its
  subject, author, age and short id, and an arrow on those not pushed
  or not pulled yet. The header names the branch and how far it is from
  its upstream, and holds the search field: what is typed there
  (ParseGraphFilter in gittan.graph: words, author:, since:, until:,
  path:, change:) keeps only the commits that match, as a flat list,
  since the lanes of a part of the history mean nothing. The commits a
  path filter asks for come from the owner (OnPathCommits), who asks
  git; those a change filter asks for take longer, so the owner is
  asked (OnChangeCommits) and answers later with SetChangeCommits,
  the list saying meanwhile that it searches;
  when the log shown was cut and a filter is typed, the owner is asked
  for the whole log once (OnMore), as it is by a click on the last row
  that says the log was cut.

  Like the popup list it is a child of the form, placed over whatever
  the form shows. Up and Down move in it, Enter or a click picks a
  commit (OnPick with its id); a right click or the Menu key asks for
  the commit's menu (OnContext, with the commit and where to show it);
  Escape (with an empty field; else it empties the field), the close
  button, a click outside the panel or the application going to the
  background closes it. The rows sit in a TScrollBox for native
  scrolling; a control may not be taller than 32767 px in the LCL, so
  with more rows than fit that the rows control stays at MaxRowsHeight
  and the scroll position is mapped onto the rows (RowShift), which costs
  nothing but a coarser scroll. One commit may be marked (Marked, its
  id), for the owner's "compare with the marked commit": its short id
  is shown in the accent.

  A row can be dragged onto the row of the commit HEAD is on: that row
  is outlined in the accent while the mouse is over it, the box scrolls
  when the mouse nears its top or bottom, and the release there asks the
  owner (OnDrop, with both commits and where to show a menu) what to do,
  a merge of the dragged commit into the branch. Escape gives the drag
  up.

  The Statistics toggle in the header shows, in the place of the rows,
  how many of the commits shown there are per week, as a bar for every
  week with each of the authors with the most commits in a lane color,
  and a row for every author with their count and their weeks; a click
  on an author's row filters the log to them (CommitStats in
  gittan.commitstats). Turned on while the log shown was cut, it asks
  for the whole log first, as a filter does. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, StdCtrls, ExtCtrls,
  LCLType, LMessages, gittan.graph, gittan.commitstats, gittan.popuphook;

type
  TGittanGraphPickEvent = procedure(Sender: TObject; const AHash: string) of object;
  TGittanGraphContextEvent = procedure(Sender: TObject; const ACommit: TGittanGraphCommit;
    const AScreenPos: TPoint) of object;
  {** ASource was dragged onto ATarget, the commit HEAD is on, and let
    go at AScreenPos. }
  TGittanGraphDropEvent = procedure(Sender: TObject;
    const ASource, ATarget: TGittanGraphCommit; const AScreenPos: TPoint) of object;
  {** Asked for the ids of the commits that touched APath, added to
    AHashes. }
  TGittanGraphPathEvent = procedure(Sender: TObject; const APath: string;
    AHashes: TStrings) of object;
  TGittanGraphChangeEvent = procedure(Sender: TObject;
    const AChanges: TStringArray) of object;

  TGittanCommitGraph = class;

  { TGittanGraphBox }

  {** The scroll box: a scroll repaints the rows, since with the mapped
    scroll position more than the exposed strip changes. }
  TGittanGraphBox = class(TScrollBox)
  private
    FGraph: TGittanCommitGraph;
  protected
    procedure WMVScroll(var Message: TLMVScroll); message LM_VSCROLL;
  end;

  { TGittanGraphRows }

  {** The rows, inside the scroll box: painting and the mouse are the
    graph's, it only forwards them. }
  TGittanGraphRows = class(TCustomControl)
  private
    FGraph: TGittanCommitGraph;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    procedure MouseLeave; override;
    procedure KeyDown(var Key: word; Shift: TShiftState); override;
  end;

  { TGittanCommitGraph }

  TGittanCommitGraph = class(TCustomControl)
  private
    FBox: TGittanGraphBox;
    FRows: TGittanGraphRows;
    FEdit: TEdit;
    FTimer: TTimer;
    FCommits: TGittanGraphCommits;
    { Per commit, worked out once since a paint of a row has to be quick
      while it scrolls: the author and age, the age alone, the subject
      as it was last cut to fit, with the room it was cut for (-1 before
      the first paint), and for the filter the text the words are
      looked for in and the author, both in lower case. }
    FMetaFull, FMetaAge, FSubjects, FSearch, FAuthorKeys: array of string;
    FSubjectRoom: TIntegerDynArray;
    { The length of the longest short id, which follows core.abbrev and
      the size of the repository (seven at least): the column is as
      wide as that many zeros. }
    FIdChars: integer;
    { The commit of every row shown: all of them, or those the filter
      keeps. }
    FShown: TIntegerDynArray;
    FFilter: TGittanGraphFilter;
    FFiltered: boolean;
    { The commits touching the paths of the filter, and the paths they
      were asked for. }
    FPathHashes: TStringList;
    FPathKey: string;
    { The commits making the changes of the filter: the changes they are
      wanted for (FChangeKey, '' for none), those they were found for
      (FChangeDone), and git's reason when the search failed. }
    FChangeHashes: TStringList;
    FChangeKey, FChangeDone, FChangeError: string;
    FLanes: integer;
    FMore, FAskedMore: boolean;
    FBranch: string;
    FAhead, FBehind: integer;
    FHasUpstream: boolean;
    { The highlighted row, the one Enter picks; -1 for none. }
    FCurrent: integer;
    FMarked: string;
    { A drag: the row the left button went down on (-1 for none) and
      where, whether the mouse has gone far enough from there for a
      drag, the row it would be dropped on (-1 for none), and the timer
      that scrolls the box while the mouse is near its top or bottom.
      FDragGivenUp: a drag given up with the button still down, whose
      release then does nothing. }
    FPressRow, FDropRow: integer;
    FPressPoint: TPoint;
    FDragging, FDragGivenUp: boolean;
    FDragTimer: TTimer;
    FCloseRect: TRect;
    FCloseHot, FFooterHot: boolean;
    { The statistics shown in the place of the rows while FStatsOn, the
      toggle's place in the header, and the week and author under the
      mouse (-1 for none). }
    FStatsOn, FStatsHot: boolean;
    FStats: TGittanCommitStats;
    FStatsRect: TRect;
    FStatsWeek, FStatsAuthor: integer;
    { The most commits one author made in one week, which the authors'
      bars are drawn against. }
    FStatsAuthorMax: integer;
    FHook: TGittanPopupHook;
    FBack, FText, FDim, FHover, FLine, FAccent, FTag: TColor;
    FLaneColors: array of TColor;
    FOnPick: TGittanGraphPickEvent;
    FOnContext: TGittanGraphContextEvent;
    FOnDrop: TGittanGraphDropEvent;
    FOnMore: TNotifyEvent;
    FOnPathCommits: TGittanGraphPathEvent;
    FOnChangeCommits: TGittanGraphChangeEvent;
    FOnClose: TNotifyEvent;
    procedure Context(const AScreenPos: TPoint);
    function LaneColor(AIndex: integer): TColor;
    function LaneX(ALane: integer): integer;
    function ShownLanes: integer;
    function GraphRight: integer;
    function HasFooter: boolean;
    function ContentHeight: integer;
    function TotalHeight: integer;
    function PhysHeight: integer;
    function RowShift: integer;
    function LogicalTop: integer;
    procedure SetLogicalTop(AValue: integer);
    procedure Scrolled;
    procedure ScrollAsync(Data: PtrInt);
    function FooterClickable: boolean;
    function FooterText: string;
    function ChangePending: boolean;
    procedure Load(const ACommits: TGittanGraphCommits; AMore: boolean;
      const AKeep: string);
    function CurrentHash: string;
    procedure ApplyFilter;
    procedure More;
    procedure Arrange;
    procedure Place;
    function RowAt(Y: integer): integer;
    function FooterAt(Y: integer): boolean;
    procedure SetCurrent(AValue: integer);
    procedure SetCloseHot(AValue: boolean);
    procedure SetFooterHot(AValue: boolean);
    procedure SetMarked(const AValue: string);
    procedure SetStatsOn(AValue: boolean);
    procedure SetStatsHot(AValue: boolean);
    procedure CountStats;
    function StatsPlot(out ALeft, ARight: integer): boolean;
    function StatsAuthorsTop: integer;
    procedure StatsHover(X, Y: integer);
    procedure StatsClick(X, Y: integer);
    procedure PaintStats(ACanvas: TCanvas);
    procedure Step(ADelta: integer);
    procedure ScrollIntoView;
    procedure PaintRows(ACanvas: TCanvas);
    procedure PaintRow(ACanvas: TCanvas; ARow, ATop: integer);
    function PaintRefs(ACanvas: TCanvas; const ARefs: TGittanGraphRefs;
      X, ACenterY, ARight: integer): integer;
    function FitText(ACanvas: TCanvas; const AText: string; ARoom: integer): string;
    procedure Pick;
    procedure Dismiss;
    function IsHeadRow(ARow: integer): boolean;
    procedure SetDropRow(AValue: integer);
    function DragMove(Shift: TShiftState; X, Y: integer): boolean;
    procedure Drop(X, Y: integer);
    procedure EndDrag;
    procedure GiveUpDrag;
    procedure DragTimerTick(Sender: TObject);
    procedure KeyInput(var Key: word);
    procedure EditChange(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure TimerTick(Sender: TObject);
    function GetKeeper: TControl;
    procedure SetKeeper(AValue: TControl);
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
    {** Shows ACommits, laid out by LayoutGraph, in the middle of the
      parent, under a header with ABranch and how many commits it is
      ahead of (AAhead) and behind (ABehind) its upstream when it has
      one; AMore says the log was cut, which the last row says. AFilter
      goes into the search field. The focus goes to the field, the
      highlight to the commit HEAD is on. }
    procedure Popup(const ACommits: TGittanGraphCommits; AMore: boolean;
      const ABranch: string; AAhead, ABehind: integer; AHasUpstream: boolean;
      const AFilter: string = '');
    {** Puts ACommits in the place of the ones shown, the answer to
      OnMore: the filter and the highlighted commit stay. }
    procedure Replace(const ACommits: TGittanGraphCommits; AMore: boolean);
    {** The answer to OnChangeCommits: AHashes are the commits making
      AChanges, or AError says why git could not look (AHashes then
      empty). An answer for changes the filter no longer asks for is
      dropped. }
    procedure SetChangeCommits(const AChanges: TStringArray; AHashes: TStrings;
      const AError: string);
    {** Hides the panel without a pick. }
    procedure Close;
    {** Keeps the panel in the middle of the parent after it resized. }
    procedure Recenter;
    {** The colors: the background, the text, the dim text, the
      highlighted row, the border and the dividers, the accent (the
      current branch, the commits not pushed) and the tags. }
    procedure SetColors(ABack, AText, ADim, AHover, ALine, AAccent, ATag: TColor);
    {** The colors the lanes take in turn. }
    procedure SetLaneColors(const AColors: array of TColor);
    {** The id of the commit marked for a comparison, '' for none. }
    property Marked: string read FMarked write SetMarked;
    property OnPick: TGittanGraphPickEvent read FOnPick write FOnPick;
    {** A right click on a commit, or the Menu key on the highlighted one:
      the panel stays open under the menu the handler shows at
      AScreenPos. }
    property OnContext: TGittanGraphContextEvent read FOnContext write FOnContext;
    {** A commit was dragged onto the one HEAD is on: the panel stays
      open under the menu the handler shows at AScreenPos. }
    property OnDrop: TGittanGraphDropEvent read FOnDrop write FOnDrop;
    {** The whole log is wanted: the handler answers with Replace. Asked
      once per Popup. }
    property OnMore: TNotifyEvent read FOnMore write FOnMore;
    {** The commits that touched a path of the filter are wanted. }
    property OnPathCommits: TGittanGraphPathEvent read FOnPathCommits write FOnPathCommits;
    {** The commits making the changes of the filter are wanted: the
      handler starts the search (dropping one still running) and
      answers with SetChangeCommits. }
    property OnChangeCommits: TGittanGraphChangeEvent
      read FOnChangeCommits write FOnChangeCommits;
    {** The panel went away, however it was closed. }
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
    {** A control whose clicks leave the panel open, as its own do, so
      that a row of it can close the panel on the click's release
      instead of the press closing it and the release opening it again. }
    property Keeper: TControl read GetKeeper write SetKeeper;
  end;

implementation

uses
  Math, DateUtils, LazUTF8, LazFileUtils, LCLIntf, gittan.reviews, gittan.statusbar,
  gittan.repoinfo, gittan.theme;

resourcestring
  rsGraphTitle = 'Commit Graph';
  rsGraphNotPushed = '%d not pushed';
  rsGraphNotPulled = '%d not pulled';
  rsGraphInSync = 'up to date with upstream';
  rsGraphMore = 'Showing the newest %d commits';
  rsGraphLoadAll = 'Load all';
  rsGraphMatches = '%d of %d commits match';
  rsGraphMatchesCut = '%d of the newest %d commits match';
  rsGraphEmpty = 'No commits yet';
  rsGraphNoMatch = 'No commits match';
  rsGraphFilterHint = 'Search (author: since: until: path: change:)';
  rsGraphSearchingChanges = 'Searching the history for the change...';
  rsGraphChangeFailed = 'git could not search: %s';
  rsGraphStats = 'Statistics';
  rsStatsSummary = '%s commits by %s authors';
  rsStatsSummaryOne = '%s commits by one author';
  rsStatsCut = 'the newest %d';
  rsStatsMatching = 'those the search keeps';
  rsStatsWeek = 'Week of %s: %s commits';
  rsStatsAll = 'All authors';
  rsStatsMostWeek = 'at most %s a week';
  rsStatsNoTime = 'No commit has a time';

const
  { Room around the panel within the form, and its widest. }
  Margin = 40;
  MaxPanelWidth = 1000;
  HeaderHeight = 48;
  Pad = 16;
  Gap = 10;
  RowHeight = 28;
  LaneWidth = 16;
  { The most lanes drawn; a commit further right sits at the last. }
  MaxLanes = 12;
  DotRadius = 4;
  HeadRadius = 7;
  ChipPadX = 6;
  ChipGap = 5;
  ChipMaxChars = 28;
  CloseSize = 24;
  EditWidth = 300;
  { Room at the right for the scroll bar, which overlays on macOS. }
  ScrollRoom = 8;
  Border = 1;
  { The tallest the rows control gets (the LCL sends a size in 16 bits,
    so a control over 32767 px fails); more rows than that are reached
    through RowShift. }
  MaxRowsHeight = 32000;
  { How long typing may pause before the filter is applied. }
  FilterDelay = 200;
  { How far the mouse goes with the button down before a drag starts,
    and how often a drag near the top or bottom scrolls the box. }
  DragThreshold = 5;
  DragScrollInterval = 40;
  { The statistics: the height of the weeks' bars, the column of the
    names and counts left of the weeks, the narrowest a week is drawn,
    and how many authors of a week the line above the bars names. }
  ChartHeight = 140;
  StatsLabelWidth = 260;
  MinWeekWidth = 3;
  WeekAuthors = 3;
  DateFormat = 'yyyy-mm-dd';

{ TGittanGraphBox }

procedure TGittanGraphBox.WMVScroll(var Message: TLMVScroll);
begin
  inherited WMVScroll(Message);
  if FGraph <> nil then
    FGraph.Scrolled;
end;

{ TGittanGraphRows }

procedure TGittanGraphRows.Paint;
begin
  FGraph.PaintRows(Canvas);
end;

procedure TGittanGraphRows.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
    FGraph.FDragGivenUp := False;
  if (Button = mbLeft) and not FGraph.FStatsOn then
  begin
    FGraph.FPressRow := FGraph.RowAt(Y);
    FGraph.FPressPoint := Point(X, Y);
  end;
end;

{ The mouse over empty space under the rows keeps the row the keys
  chose, which Enter and the Menu key act on. }
procedure TGittanGraphRows.MouseMove(Shift: TShiftState; X, Y: integer);
var
  Row: integer;
begin
  inherited MouseMove(Shift, X, Y);
  if FGraph.FStatsOn then
  begin
    FGraph.StatsHover(X, Y);
    Exit;
  end;
  if FGraph.DragMove(Shift, X, Y) then
    Exit;
  Row := FGraph.RowAt(Y);
  if Row >= 0 then
    FGraph.SetCurrent(Row);
  FGraph.SetFooterHot(FGraph.FooterAt(Y) and FGraph.FooterClickable);
end;

procedure TGittanGraphRows.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Row: integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FGraph.FStatsOn then
  begin
    if Button = mbLeft then
      FGraph.StatsClick(X, Y);
    Exit;
  end;
  if (Button = mbLeft) and FGraph.FDragging then
  begin
    FGraph.Drop(X, Y);
    Exit;
  end;
  if (Button = mbLeft) and FGraph.FDragGivenUp then
  begin
    FGraph.FDragGivenUp := False;
    Exit;
  end;
  if Button = mbLeft then
    FGraph.EndDrag;
  Row := FGraph.RowAt(Y);
  if (Button = mbLeft) and (Row >= 0) then
  begin
    FGraph.SetCurrent(Row);
    FGraph.Pick;
  end
  else if (Button = mbLeft) and FGraph.FooterAt(Y) and FGraph.FooterClickable then
    FGraph.More
  else if (Button = mbRight) and (Row >= 0) then
  begin
    FGraph.SetCurrent(Row);
    FGraph.Context(ClientToScreen(Point(X, Y)));
  end;
end;

procedure TGittanGraphRows.MouseLeave;
begin
  inherited MouseLeave;
  FGraph.SetFooterHot(False);
  if FGraph.FStatsOn then
    FGraph.StatsHover(-1, -1);
  if not FGraph.FDragging then
    Cursor := crDefault;
end;

procedure TGittanGraphRows.KeyDown(var Key: word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  FGraph.KeyInput(Key);
end;

{ TGittanCommitGraph }

constructor TGittanCommitGraph.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHook := TGittanPopupHook.Create(Self, @Close, True);
  ControlStyle := ControlStyle + [csOpaque];
  Visible := False;
  FCurrent := -1;
  FPressRow := -1;
  FDropRow := -1;
  FStatsWeek := -1;
  FStatsAuthor := -1;
  FPathHashes := TStringList.Create;
  FPathHashes.Sorted := True;
  FPathHashes.Duplicates := dupIgnore;
  FPathHashes.CaseSensitive := True;
  FChangeHashes := TStringList.Create;
  FChangeHashes.Sorted := True;
  FChangeHashes.Duplicates := dupIgnore;
  FChangeHashes.CaseSensitive := True;
  FBox := TGittanGraphBox.Create(Self);
  FBox.FGraph := Self;
  FBox.Parent := Self;
  FBox.BorderStyle := bsNone;
  FBox.HorzScrollBar.Visible := False;
  FRows := TGittanGraphRows.Create(Self);
  FRows.FGraph := Self;
  FRows.Parent := FBox;
  FRows.Align := alTop;
  FRows.ControlStyle := FRows.ControlStyle + [csOpaque];
  FRows.TabStop := True;
  FEdit := TEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.TextHint := rsGraphFilterHint;
  FEdit.OnChange := @EditChange;
  FEdit.OnKeyDown := @EditKeyDown;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := FilterDelay;
  FTimer.OnTimer := @TimerTick;
  FDragTimer := TTimer.Create(Self);
  FDragTimer.Enabled := False;
  FDragTimer.Interval := DragScrollInterval;
  FDragTimer.OnTimer := @DragTimerTick;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnShadow,
    clHighlight, clMaroon);
  SetLaneColors([clHighlight]);
end;

destructor TGittanCommitGraph.Destroy;
begin
  Application.RemoveAsyncCalls(Self);
  FHook.Hook(False);
  FPathHashes.Free;
  FChangeHashes.Free;
  inherited Destroy;
end;

procedure TGittanCommitGraph.SetColors(ABack, AText, ADim, AHover, ALine,
  AAccent, ATag: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
  FLine := ALine;
  FAccent := AAccent;
  FTag := ATag;
  Color := ABack;
  FBox.Color := ABack;
  FRows.Color := ABack;
  Invalidate;
  FRows.Invalidate;
end;

procedure TGittanCommitGraph.SetLaneColors(const AColors: array of TColor);
var
  i: integer;
begin
  SetLength(FLaneColors, Length(AColors));
  for i := 0 to High(AColors) do
    FLaneColors[i] := AColors[i];
  FRows.Invalidate;
end;

procedure TGittanCommitGraph.SetMarked(const AValue: string);
begin
  if FMarked = AValue then
    Exit;
  FMarked := AValue;
  FRows.Invalidate;
end;

function TGittanCommitGraph.LaneColor(AIndex: integer): TColor;
begin
  if Length(FLaneColors) = 0 then
    Exit(FAccent);
  Result := FLaneColors[AIndex mod Length(FLaneColors)];
end;

function TGittanCommitGraph.LaneX(ALane: integer): integer;
begin
  Result := Px(Pad) + Min(ALane, MaxLanes - 1) * Px(LaneWidth) + Px(LaneWidth) div 2;
end;

{ The lanes drawn: one while the filter shows a flat list. }
function TGittanCommitGraph.ShownLanes: integer;
begin
  if FFiltered then
    Result := 1
  else
    Result := FLanes;
end;

{ Where the text starts, right of the widest row's lanes. }
function TGittanCommitGraph.GraphRight: integer;
begin
  Result := Px(Pad) + Max(1, Min(ShownLanes, MaxLanes)) * Px(LaneWidth) + Px(Gap);
end;

{ A last row for the cut of the log or the count of the matches. }
function TGittanCommitGraph.HasFooter: boolean;
begin
  Result := (Length(FShown) > 0) and (FMore or FFiltered);
end;

{ The height of every row and the footer, or of the statistics. }
function TGittanCommitGraph.ContentHeight: integer;
begin
  if FStatsOn and (Length(FShown) > 0) then
    Result := StatsAuthorsTop + Length(FStats.Authors) * Px(RowHeight) + Px(Pad) div 2
  else
    Result := Max(1, Length(FShown) + Ord(HasFooter)) * Px(RowHeight);
end;

{ What the rows control gets of the content: all of it unless it is
  taller than a control may be. }
function TGittanCommitGraph.TotalHeight: integer;
begin
  Result := ContentHeight;
end;

function TGittanCommitGraph.PhysHeight: integer;
begin
  Result := Min(TotalHeight, MaxRowsHeight);
end;

{ How far the rows are above where the box has scrolled to: 0 while the
  rows control holds them all, else the scroll position mapped from the
  control's height onto the height of every row, less the position. }
function TGittanCommitGraph.RowShift: integer;
var
  Page, Pos, Total, Phys: integer;
begin
  Result := 0;
  Total := TotalHeight;
  Phys := PhysHeight;
  Page := FBox.ClientHeight;
  if (Total <= Phys) or (Phys <= Page) then
    Exit;
  Pos := FBox.VertScrollBar.Position;
  Result := int64(Pos) * (Total - Page) div (Phys - Page) - Pos;
end;

{ The row pixel at the top of the box. }
function TGittanCommitGraph.LogicalTop: integer;
begin
  Result := FBox.VertScrollBar.Position + RowShift;
end;

procedure TGittanCommitGraph.SetLogicalTop(AValue: integer);
var
  Page, Total, Phys: integer;
begin
  Total := TotalHeight;
  Phys := PhysHeight;
  Page := FBox.ClientHeight;
  AValue := Max(0, AValue);
  if (Total <= Phys) or (Phys <= Page) then
    FBox.VertScrollBar.Position := AValue
  else
    FBox.VertScrollBar.Position := int64(AValue) * (Phys - Page) div (Total - Page);
  FRows.Invalidate;
end;

procedure TGittanCommitGraph.Scrolled;
begin
  if TotalHeight > PhysHeight then
    FRows.Invalidate;
end;

{ The box takes a new height of the rows control in its own time, so a
  position set at once is clamped to the old range: it is set again
  from the message loop. }
procedure TGittanCommitGraph.ScrollAsync(Data: PtrInt);
begin
  if Visible then
    ScrollIntoView;
end;

function TGittanCommitGraph.FooterClickable: boolean;
begin
  Result := HasFooter and FMore and not FFiltered and not FAskedMore and Assigned(FOnMore);
end;

function TGittanCommitGraph.FooterText: string;
begin
  if FFiltered then
  begin
    if FMore then
      Result := Format(rsGraphMatchesCut, [Length(FShown), Length(FCommits)])
    else
      Result := Format(rsGraphMatches, [Length(FShown), Length(FCommits)]);
  end
  else
  begin
    Result := Format(rsGraphMore, [Length(FCommits)]);
    if FooterClickable then
      Result := Result + ' · ' + rsGraphLoadAll;
  end;
end;

{ AText with its accented letters composed, as the history view does:
  macOS gives git a user name in decomposed form, which is not what is
  typed into the field. }
function Composed(const AText: string): string;
begin
  {$IFDEF DARWIN}
  Result := GetDarwinNormalizedFilename(AText, 2);
  {$ELSE}
  Result := AText;
  {$ENDIF}
end;

{ Takes ACommits with what every row needs; every commit is shown, the
  highlight on the one with the id AKeep, else on the one HEAD is on,
  else on the first. }
procedure TGittanCommitGraph.Load(const ACommits: TGittanGraphCommits;
  AMore: boolean; const AKeep: string);
var
  i, r: integer;
begin
  FCommits := ACommits;
  FLanes := GraphWidth(ACommits);
  FMore := AMore;
  SetLength(FMetaFull, Length(FCommits));
  SetLength(FMetaAge, Length(FCommits));
  SetLength(FSubjects, Length(FCommits));
  SetLength(FSubjectRoom, Length(FCommits));
  SetLength(FSearch, Length(FCommits));
  SetLength(FAuthorKeys, Length(FCommits));
  SetLength(FShown, Length(FCommits));
  FIdChars := 7;
  for r := 0 to High(FCommits) do
  begin
    FIdChars := Max(FIdChars, Length(FCommits[r].Short));
    FMetaAge[r] := '';
    if FCommits[r].Date > 0 then
      FMetaAge[r] := ReviewAge(FCommits[r].Date, LocalTimeToUniversal(Now));
    FMetaFull[r] := FCommits[r].Author;
    if (FMetaFull[r] <> '') and (FMetaAge[r] <> '') then
      FMetaFull[r] := FMetaFull[r] + ' · ';
    FMetaFull[r] := FMetaFull[r] + FMetaAge[r];
    FSubjectRoom[r] := -1;
    FAuthorKeys[r] := UTF8LowerCase(Composed(FCommits[r].Author));
    FSearch[r] := UTF8LowerCase(Composed(FCommits[r].Subject + #10 + FCommits[r].Body)) +
      #10 + FAuthorKeys[r] + #10 + FCommits[r].Hash;
    FShown[r] := r;
  end;
  FCurrent := -1;
  for r := 0 to High(FCommits) do
    if (AKeep <> '') and (FCommits[r].Hash = AKeep) then
      FCurrent := r;
  for r := 0 to High(FCommits) do
  begin
    if FCurrent >= 0 then
      Break;
    for i := 0 to High(FCommits[r].Refs) do
      if FCommits[r].Refs[i].Kind = grHead then
        FCurrent := r;
  end;
  if (FCurrent < 0) and (Length(FCommits) > 0) then
    FCurrent := 0;
end;

function TGittanCommitGraph.CurrentHash: string;
begin
  Result := '';
  if (FCurrent >= 0) and (FCurrent <= High(FShown)) then
    Result := FCommits[FShown[FCurrent]].Hash;
end;

procedure TGittanCommitGraph.Popup(const ACommits: TGittanGraphCommits;
  AMore: boolean; const ABranch: string; AAhead, ABehind: integer;
  AHasUpstream: boolean; const AFilter: string);
begin
  if Parent = nil then
    Exit;
  Dismiss;
  FBranch := ABranch;
  FAhead := AAhead;
  FBehind := ABehind;
  FHasUpstream := AHasUpstream;
  FCloseHot := False;
  FFooterHot := False;
  FAskedMore := False;
  FStatsOn := False;
  FStatsHot := False;
  FPathKey := '';
  FPathHashes.Clear;
  FChangeKey := '';
  FChangeDone := '';
  FChangeError := '';
  FChangeHashes.Clear;
  Load(ACommits, AMore, '');
  FEdit.Text := AFilter;
  ApplyFilter;
  Place;
  FHook.SaveFocus;
  Visible := True;
  BringToFront;
  FBox.VertScrollBar.Position := 0;
  ScrollIntoView;
  if FEdit.CanFocus then
    FEdit.SetFocus
  else if FRows.CanFocus then
    FRows.SetFocus;
  FHook.Hook(True);
end;

procedure TGittanCommitGraph.Replace(const ACommits: TGittanGraphCommits; AMore: boolean);
begin
  { The rows a press or a drag was on move. }
  GiveUpDrag;
  Load(ACommits, AMore, CurrentHash);
  ApplyFilter;
  Place;
  Application.QueueAsyncCall(@ScrollAsync, 0);
end;

{ The changes of a filter as one string, '' for none. }
function ChangeKeyOf(const AChanges: TStringArray): string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(AChanges) do
    Result := Result + AChanges[i] + #1;
end;

procedure TGittanCommitGraph.SetChangeCommits(const AChanges: TStringArray;
  AHashes: TStrings; const AError: string);
var
  Key: string;
begin
  Key := ChangeKeyOf(AChanges);
  if (Key = '') or (Key <> FChangeKey) then
    Exit;
  FChangeHashes.Clear;
  if AHashes <> nil then
    FChangeHashes.AddStrings(AHashes);
  FChangeDone := Key;
  FChangeError := AError;
  if Visible then
    ApplyFilter;
end;

{ Whether the changes the filter asks for are still being looked for. }
function TGittanCommitGraph.ChangePending: boolean;
begin
  Result := (FChangeKey <> '') and (FChangeKey <> FChangeDone);
end;

{ Reads the field and keeps the rows that match. Lower case and composed
  on both sides, so neither the case nor how an ö is written matters
  (the Repository page gives an author's name as git has it). The commits of a path come from
  the owner, asked again only when the paths change; those of a change
  come later (SetChangeCommits), and until then no commit is shown.
  When the log shown
  was cut, the owner is asked for all of it first (once), and answers
  with Replace, which comes back here. The highlight stays on the same
  commit when it is still shown. }
procedure TGittanCommitGraph.ApplyFilter;
var
  Current, Key: string;
  i, n: integer;
  Hashes: TStringList;
begin
  FTimer.Enabled := False;
  FFilter := ParseGraphFilter(FEdit.Text);
  for i := 0 to High(FFilter.Words) do
    FFilter.Words[i] := UTF8LowerCase(Composed(FFilter.Words[i]));
  for i := 0 to High(FFilter.Authors) do
    FFilter.Authors[i] := UTF8LowerCase(Composed(FFilter.Authors[i]));
  FFiltered := not GraphFilterEmpty(FFilter);
  if FFiltered and FMore and not FAskedMore and Assigned(FOnMore) then
  begin
    More;
    Exit;
  end;
  Key := '';
  for i := 0 to High(FFilter.Paths) do
    Key := Key + FFilter.Paths[i] + #1;
  if Key <> FPathKey then
  begin
    FPathHashes.Clear;
    if Assigned(FOnPathCommits) then
    begin
      Hashes := TStringList.Create;
      Screen.Cursor := crHourGlass;
      try
        for i := 0 to High(FFilter.Paths) do
        begin
          Hashes.Clear;
          FOnPathCommits(Self, FFilter.Paths[i], Hashes);
          FPathHashes.AddStrings(Hashes);
        end;
      finally
        Screen.Cursor := crDefault;
        Hashes.Free;
      end;
    end;
    FPathKey := Key;
  end;
  Key := '';
  if Assigned(FOnChangeCommits) then
    Key := ChangeKeyOf(FFilter.Changes);
  if Key <> FChangeKey then
  begin
    FChangeKey := Key;
    { None to search for (the filter cleared, or back to the one done)
      stops a search still running. }
    if ChangePending then
      FOnChangeCommits(Self, FFilter.Changes)
    else if Assigned(FOnChangeCommits) then
      FOnChangeCommits(Self, nil);
  end;
  Current := CurrentHash;
  SetLength(FShown, Length(FCommits));
  n := 0;
  if not ChangePending then
    for i := 0 to High(FCommits) do
      if not FFiltered or (MatchesGraphFilter(FFilter, FSearch[i], FAuthorKeys[i],
        FCommits[i].Date) and ((Length(FFilter.Paths) = 0) or
        (FPathHashes.IndexOf(FCommits[i].Hash) >= 0)) and ((FChangeKey = '') or
        (FChangeHashes.IndexOf(FCommits[i].Hash) >= 0))) then
    begin
      FShown[n] := i;
      Inc(n);
    end;
  SetLength(FShown, n);
  FCurrent := -1;
  for i := 0 to High(FShown) do
    if FCommits[FShown[i]].Hash = Current then
      FCurrent := i;
  if FStatsOn then
  begin
    CountStats;
    Place;
  end;
  Arrange;
  if FCurrent < 0 then
  begin
    if n > 0 then
      FCurrent := 0;
    FBox.VertScrollBar.Position := 0;
  end
  else
    ScrollIntoView;
  FRows.Invalidate;
  Invalidate;
end;

procedure TGittanCommitGraph.More;
begin
  if FAskedMore or not Assigned(FOnMore) then
    Exit;
  FAskedMore := True;
  SetFooterHot(False);
  FOnMore(Self);
end;

procedure TGittanCommitGraph.EditChange(Sender: TObject);
begin
  FTimer.Enabled := False;
  FTimer.Enabled := True;
end;

procedure TGittanCommitGraph.TimerTick(Sender: TObject);
begin
  ApplyFilter;
end;

{ The field passes the keys that move in the list and pick on to it;
  Home and End only while it is empty, since they move its caret
  otherwise. Escape empties it first and closes the panel when it is
  empty. }
procedure TGittanCommitGraph.EditKeyDown(Sender: TObject; var Key: word;
  Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and FDragging then
  begin
    GiveUpDrag;
    Key := 0;
    Exit;
  end;
  case Key of
    VK_UP, VK_DOWN, VK_PRIOR, VK_NEXT, VK_RETURN, VK_APPS:
      KeyInput(Key);
    VK_HOME, VK_END:
      if FEdit.Text = '' then
        KeyInput(Key);
    VK_ESCAPE:
    begin
      if FEdit.Text <> '' then
      begin
        FEdit.Text := '';
        ApplyFilter;
      end
      else
        Close;
      Key := 0;
    end;
  end;
end;

{ In the middle of the parent, as wide as it allows up to MaxPanelWidth
  and as high as it allows, and no higher than the rows need. }
procedure TGittanCommitGraph.Place;
var
  W, H: integer;
begin
  if Parent = nil then
    Exit;
  W := Max(200, Min(Px(MaxPanelWidth), Parent.ClientWidth - 2 * Px(Margin)));
  H := Px(HeaderHeight) + ContentHeight + Px(Pad) div 2 + Border;
  H := Max(Px(HeaderHeight) + Px(RowHeight), Min(H, Parent.ClientHeight - 2 * Px(Margin)));
  SetBounds((Parent.ClientWidth - W) div 2, (Parent.ClientHeight - H) div 2, W, H);
  Arrange;
end;

procedure TGittanCommitGraph.Recenter;
begin
  if Visible then
    Place;
end;

procedure TGittanCommitGraph.Arrange;
var
  W: integer;
begin
  if (FBox = nil) or (FRows = nil) or (FEdit = nil) then
    Exit;
  FBox.SetBounds(Border, Px(HeaderHeight), Width - 2 * Border,
    Max(Px(RowHeight), Height - Px(HeaderHeight) - Border));
  FRows.Height := PhysHeight;
  FCloseRect := Rect(Width - Px(Pad) - Px(CloseSize) + 4, (Px(HeaderHeight) - Px(CloseSize)) div 2,
    Width - Px(Pad) + 4, (Px(HeaderHeight) + Px(CloseSize)) div 2);
  W := Min(Px(EditWidth), Width div 3);
  FEdit.SetBounds(FCloseRect.Left - Px(Gap) - W, (Px(HeaderHeight) - FEdit.Height) div 2, W,
    FEdit.Height);
  if HandleAllocated then
  begin
    Canvas.Font := Font;
    W := Canvas.TextWidth(rsGraphStats) + 4 * Px(ChipPadX);
  end
  else
    W := 90;
  FStatsRect := Rect(FEdit.Left - Px(Gap) - W, FEdit.Top, FEdit.Left - Px(Gap), FEdit.Top + FEdit.Height);
end;

procedure TGittanCommitGraph.Resize;
begin
  inherited Resize;
  { The weeks that fit follow the width. }
  if FStatsOn then
    CountStats;
  Arrange;
end;

procedure TGittanCommitGraph.Dismiss;
begin
  FTimer.Enabled := False;
  EndDrag;
  if not Visible then
    Exit;
  FHook.Hook(False);
  Visible := False;
  FHook.RestoreFocus;
  if Assigned(FOnClose) then
    FOnClose(Self);
end;

procedure TGittanCommitGraph.Close;
begin
  Dismiss;
end;

procedure TGittanCommitGraph.Context(const AScreenPos: TPoint);
begin
  if (FCurrent >= 0) and (FCurrent <= High(FShown)) and Assigned(FOnContext) then
    FOnContext(Self, FCommits[FShown[FCurrent]], AScreenPos);
end;

procedure TGittanCommitGraph.Pick;
var
  Hash: string;
begin
  Hash := CurrentHash;
  if Hash = '' then
    Exit;
  Dismiss;
  if Assigned(FOnPick) then
    FOnPick(Self, Hash);
end;

{ ---------------------------------------------------------------------------
  Dragging a commit onto HEAD's
  --------------------------------------------------------------------------- }

function TGittanCommitGraph.IsHeadRow(ARow: integer): boolean;
var
  i: integer;
begin
  Result := False;
  if (ARow < 0) or (ARow > High(FShown)) then
    Exit;
  for i := 0 to High(FCommits[FShown[ARow]].Refs) do
    if FCommits[FShown[ARow]].Refs[i].Kind = grHead then
      Exit(True);
end;

{ Only HEAD's row takes a drop, and not from itself. }
procedure TGittanCommitGraph.SetDropRow(AValue: integer);
begin
  if (AValue = FPressRow) or not IsHeadRow(AValue) then
    AValue := -1;
  if FDragging then
    if AValue >= 0 then
      FRows.Cursor := crDrag
    else
      FRows.Cursor := crNoDrop;
  if FDropRow = AValue then
    Exit;
  FDropRow := AValue;
  FRows.Invalidate;
end;

{ The mouse moved over the rows with the button down on one: true while
  that is a drag, which keeps the pressed row highlighted. The drag
  starts once the mouse is DragThreshold away from the press, so a
  click that shakes a little still picks. }
function TGittanCommitGraph.DragMove(Shift: TShiftState; X, Y: integer): boolean;
begin
  Result := False;
  if FPressRow < 0 then
    Exit;
  if not (ssLeft in Shift) then
  begin
    EndDrag;
    Exit;
  end;
  if not FDragging then
  begin
    if (Abs(X - FPressPoint.X) < Px(DragThreshold)) and
      (Abs(Y - FPressPoint.Y) < Px(DragThreshold)) then
      Exit;
    FDragging := True;
    SetCurrent(FPressRow);
    FDragTimer.Enabled := True;
  end;
  SetDropRow(RowAt(Y));
  Result := True;
end;

procedure TGittanCommitGraph.Drop(X, Y: integer);
var
  Source, Target: integer;
begin
  Source := FPressRow;
  SetDropRow(RowAt(Y));
  Target := FDropRow;
  EndDrag;
  if (Target >= 0) and (Source >= 0) and (Source <= High(FShown)) and Assigned(FOnDrop) then
    FOnDrop(Self, FCommits[FShown[Source]], FCommits[FShown[Target]],
      FRows.ClientToScreen(Point(X, Y)));
end;

{ A drag ended with the button still down (Escape, the rows replaced):
  its release picks nothing. A press not yet a drag is forgotten. }
procedure TGittanCommitGraph.GiveUpDrag;
begin
  FDragGivenUp := FDragging;
  EndDrag;
end;

procedure TGittanCommitGraph.EndDrag;
begin
  FDragTimer.Enabled := False;
  FPressRow := -1;
  if FDragging then
  begin
    FDragging := False;
    if FCurrent >= 0 then
      FRows.Cursor := crHandPoint
    else
      FRows.Cursor := crDefault;
  end;
  SetDropRow(-1);
end;

{ The mouse within a row of the box's top or bottom scrolls it half a
  row a tick, and the row under the mouse is looked for again, since
  the rows moved under it. }
procedure TGittanCommitGraph.DragTimerTick(Sender: TObject);
var
  P: TPoint;
  InBox: integer;
begin
  if not FDragging then
    Exit;
  InBox :=FBox.ScreenToClient(Mouse.CursorPos).Y;
  if InBox < Px(RowHeight) then
    SetLogicalTop(LogicalTop - Px(RowHeight) div 2)
  else if InBox > FBox.ClientHeight - Px(RowHeight) then
    SetLogicalTop(Min(LogicalTop + Px(RowHeight) div 2,
      Max(0, TotalHeight - FBox.ClientHeight)))
  else
    Exit;
  P := FRows.ScreenToClient(Mouse.CursorPos);
  SetDropRow(RowAt(P.Y));
end;

function TGittanCommitGraph.RowAt(Y: integer): integer;
begin
  Result := -1;
  if (Y < 0) or FStatsOn then
    Exit;
  Result := (Y + RowShift) div Px(RowHeight);
  if Result > High(FShown) then
    Result := -1;
end;

function TGittanCommitGraph.FooterAt(Y: integer): boolean;
begin
  Result := not FStatsOn and HasFooter and (Y >= 0) and ((Y + RowShift) div Px(RowHeight) = Length(FShown));
end;

procedure TGittanCommitGraph.SetCurrent(AValue: integer);
begin
  if FCurrent = AValue then
    Exit;
  FCurrent := AValue;
  if AValue >= 0 then
    FRows.Cursor := crHandPoint
  else if not FFooterHot then
    FRows.Cursor := crDefault;
  FRows.Invalidate;
end;

procedure TGittanCommitGraph.SetCloseHot(AValue: boolean);
begin
  if FCloseHot = AValue then
    Exit;
  FCloseHot := AValue;
  Invalidate;
end;

procedure TGittanCommitGraph.SetFooterHot(AValue: boolean);
begin
  if FFooterHot = AValue then
    Exit;
  FFooterHot := AValue;
  if AValue then
    FRows.Cursor := crHandPoint
  else if FCurrent < 0 then
    FRows.Cursor := crDefault;
  FRows.Invalidate;
end;

procedure TGittanCommitGraph.Step(ADelta: integer);
begin
  if Length(FShown) = 0 then
    Exit;
  SetCurrent(EnsureRange(FCurrent + ADelta, 0, High(FShown)));
  ScrollIntoView;
end;

{ The footer comes along with the last row, so End shows it. }
procedure TGittanCommitGraph.ScrollIntoView;
var
  RowTop, RowBottom, Pos: integer;
begin
  if (FCurrent < 0) or FStatsOn then
    Exit;
  RowTop := FCurrent * Px(RowHeight);
  RowBottom := RowTop + Px(RowHeight);
  if (FCurrent = High(FShown)) and HasFooter then
    Inc(RowBottom, Px(RowHeight));
  Pos := LogicalTop;
  if RowTop < Pos then
    SetLogicalTop(RowTop)
  else if RowBottom > Pos + FBox.ClientHeight then
    SetLogicalTop(RowBottom - FBox.ClientHeight);
end;

{ Up and Down move a row, Page Up and Page Down a box, Home and End to
  the ends, Enter picks, the Menu key opens the commit's menu under its
  row, Escape closes. }
procedure TGittanCommitGraph.KeyInput(var Key: word);
var
  Page: integer;
begin
  Page := Max(1, FBox.ClientHeight div Px(RowHeight) - 1);
  if (Key = VK_ESCAPE) and FDragging then
  begin
    GiveUpDrag;
    Key := 0;
    Exit;
  end;
  { The statistics have no rows to move to: the keys scroll. }
  if FStatsOn then
  begin
    case Key of
      VK_UP: SetLogicalTop(LogicalTop - Px(RowHeight));
      VK_DOWN: SetLogicalTop(LogicalTop + Px(RowHeight));
      VK_PRIOR: SetLogicalTop(LogicalTop - Page * Px(RowHeight));
      VK_NEXT: SetLogicalTop(LogicalTop + Page * Px(RowHeight));
      VK_HOME: SetLogicalTop(0);
      VK_END: SetLogicalTop(TotalHeight);
      VK_ESCAPE: Close;
      VK_RETURN, VK_APPS, VK_TAB: ;
      else
        Exit;
    end;
    Key := 0;
    Exit;
  end;
  case Key of
    VK_UP: Step(-1);
    VK_DOWN: Step(1);
    VK_PRIOR: Step(-Page);
    VK_NEXT: Step(Page);
    VK_HOME: Step(-Length(FShown));
    VK_END: Step(Length(FShown));
    VK_RETURN: Pick;
    VK_ESCAPE: Close;
    VK_APPS:
      if FCurrent >= 0 then
        Context(FRows.ClientToScreen(Point(LaneX(ShownLanes),
          (FCurrent + 1) * Px(RowHeight) - RowShift)));
    VK_TAB: ;
    else
      Exit;
  end;
  Key := 0;
end;

procedure TGittanCommitGraph.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetCloseHot(PtInRect(FCloseRect, Point(X, Y)));
  SetStatsHot(PtInRect(FStatsRect, Point(X, Y)));
  if FCloseHot or FStatsHot then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
end;

procedure TGittanCommitGraph.MouseLeave;
begin
  inherited MouseLeave;
  SetCloseHot(False);
  SetStatsHot(False);
end;

procedure TGittanCommitGraph.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button = mbLeft) and PtInRect(FCloseRect, Point(X, Y)) then
    Close
  else if (Button = mbLeft) and PtInRect(FStatsRect, Point(X, Y)) then
    SetStatsOn(not FStatsOn);
end;

function TGittanCommitGraph.GetKeeper: TControl;
begin
  Result := FHook.Keeper;
end;

procedure TGittanCommitGraph.SetKeeper(AValue: TControl);
begin
  FHook.Keeper := AValue;
end;

{ The border, the header (the title, the branch and how far it is from
  its upstream, the search field, the close button) and the divider
  under it. }
procedure TGittanCommitGraph.Paint;
var
  X, Y, BodyHeight, CenterY: integer;

  procedure Part(const AText: string; AColor: TColor);
  begin
    Canvas.Font.Color := FDim;
    Canvas.TextOut(X, Y, ' · ');
    Inc(X, Canvas.TextWidth(' · '));
    Canvas.Font.Color := AColor;
    Canvas.TextOut(X, Y, AText);
    Inc(X, Canvas.TextWidth(AText));
  end;

begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := FLine;
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(0, 0, Width, Height);
  Canvas.Line(Border, Px(HeaderHeight) - 1, Width - Border, Px(HeaderHeight) - 1);

  Canvas.Font := Font;
  BodyHeight := Canvas.TextHeight('Xg');
  CenterY := Px(HeaderHeight) div 2;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Size := Max(Font.Size, 13) + 1;
  Canvas.Font.Color := FText;
  Canvas.TextOut(Px(Pad), CenterY - Canvas.TextHeight('Xg') div 2, rsGraphTitle);
  X := Px(Pad) + Canvas.TextWidth(rsGraphTitle) + 2 * Px(Gap);
  Canvas.Font := Font;
  Y := CenterY - BodyHeight div 2;
  if FBranch <> '' then
  begin
    DrawStatusIcon(Canvas, HintBranch, X, Y, BodyHeight, FDim);
    Canvas.Pen.Width := 1;
    Canvas.Brush.Style := bsClear;
    Inc(X, BodyHeight - 4 + 5);
    Canvas.Font.Color := FText;
    Canvas.TextOut(X, Y, FBranch);
    Inc(X, Canvas.TextWidth(FBranch));
    if FHasUpstream then
    begin
      if FAhead > 0 then
        Part('↑ ' + Format(rsGraphNotPushed, [FAhead]), FAccent);
      if FBehind > 0 then
        Part('↓ ' + Format(rsGraphNotPulled, [FBehind]), FText);
      if (FAhead = 0) and (FBehind = 0) then
        Part(rsGraphInSync, FDim);
    end;
  end;

  if FCloseHot then
  begin
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FHover;
    Canvas.RoundRect(FCloseRect, 6, 6);
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsClear;
  end;
  { The Statistics toggle: outlined, filled in the accent while on. }
  Canvas.Font := Font;
  if FStatsOn then
  begin
    Canvas.Pen.Color := FAccent;
    Canvas.Brush.Color := FAccent;
  end
  else
  begin
    Canvas.Pen.Color := FLine;
    if FStatsHot then
      Canvas.Brush.Color := FHover
    else
      Canvas.Brush.Color := FBack;
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.RoundRect(FStatsRect, 8, 8);
  Canvas.Brush.Style := bsClear;
  if FStatsOn then
    Canvas.Font.Color := FBack
  else
    Canvas.Font.Color := FText;
  Canvas.TextOut((FStatsRect.Left + FStatsRect.Right - Canvas.TextWidth(rsGraphStats)) div 2,
    (FStatsRect.Top + FStatsRect.Bottom - BodyHeight) div 2, rsGraphStats);

  Canvas.Pen.Color := FDim;
  Canvas.Pen.Width := 2;
  with FCloseRect do
  begin
    Canvas.Line(Left + 8, Top + 8, Right - 8, Bottom - 8);
    Canvas.Line(Right - 8, Top + 8, Left + 8, Bottom - 8);
  end;
  Canvas.Pen.Width := 1;
end;

{ Only the rows the box shows are painted: the log may have thousands.
  The footer, when there is one, says the log was cut (a click loads
  all of it) or how many commits match the filter. }
procedure TGittanCommitGraph.PaintRows(ACanvas: TCanvas);
var
  First, Last, i, FootTop, Up: integer;
  R: TRect;
begin
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := FBack;
  ACanvas.FillRect(FRows.ClientRect);
  ACanvas.Font := Font;
  if FStatsOn and (Length(FShown) > 0) then
  begin
    PaintStats(ACanvas);
    Exit;
  end;
  if Length(FShown) = 0 then
  begin
    ACanvas.Brush.Style := bsClear;
    ACanvas.Font.Color := FDim;
    if ChangePending then
      ACanvas.TextOut(Px(Pad), (Px(RowHeight) - ACanvas.TextHeight('Xg')) div 2,
        rsGraphSearchingChanges)
    else if (FChangeKey <> '') and (FChangeError <> '') then
      ACanvas.TextOut(Px(Pad), (Px(RowHeight) - ACanvas.TextHeight('Xg')) div 2,
        Format(rsGraphChangeFailed, [FChangeError]))
    else if FFiltered then
      ACanvas.TextOut(Px(Pad), (Px(RowHeight) - ACanvas.TextHeight('Xg')) div 2, rsGraphNoMatch)
    else
      ACanvas.TextOut(Px(Pad), (Px(RowHeight) - ACanvas.TextHeight('Xg')) div 2, rsGraphEmpty);
    Exit;
  end;
  R := ACanvas.ClipRect;
  if IsRectEmpty(R) then
    R := FRows.ClientRect;
  Up := RowShift;
  First := Max(0, (R.Top + Up) div Px(RowHeight));
  Last := Min(High(FShown), (R.Bottom + Up) div Px(RowHeight));
  for i := First to Last do
    PaintRow(ACanvas, i, i * Px(RowHeight) - Up);
  if HasFooter and (R.Bottom + Up >= Length(FShown) * Px(RowHeight)) then
  begin
    FootTop := Length(FShown) * Px(RowHeight) - Up;
    if FFooterHot then
    begin
      ACanvas.Pen.Style := psClear;
      ACanvas.Brush.Style := bsSolid;
      ACanvas.Brush.Color := FHover;
      ACanvas.RoundRect(Px(Pad) div 2, FootTop + 1, FRows.Width - Px(Pad) div 2,
        FootTop + Px(RowHeight) - 1, 8, 8);
      ACanvas.Pen.Style := psSolid;
    end;
    ACanvas.Brush.Style := bsClear;
    if FooterClickable then
      ACanvas.Font.Color := FAccent
    else
      ACanvas.Font.Color := FDim;
    ACanvas.TextOut(GraphRight, FootTop + (Px(RowHeight) - ACanvas.TextHeight('Xg')) div 2,
      FooterText);
  end;
end;

{ The row's highlight, its half of every line through it (none in the
  flat list of a filter), its dot (a ring around it on the commit HEAD
  is on), then from the left the refs and the subject, from the right
  the short id (in the accent on the marked commit) with an arrow when
  the commit is not pushed or not pulled, and the author and age,
  dropped when the subject would get too little room. }
procedure TGittanCommitGraph.PaintRow(ACanvas: TCanvas; ARow, ATop: integer);
var
  C: TGittanGraphCommit;
  i, Index, CenterY, Bottom, X, Right, TextY, Room: integer;
  IsHead: boolean;
  Meta, Mark: string;
begin
  Index := FShown[ARow];
  C := FCommits[Index];
  CenterY := ATop + Px(RowHeight) div 2;
  Bottom := ATop + Px(RowHeight);
  if ARow = FCurrent then
  begin
    ACanvas.Pen.Style := psClear;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := FHover;
    ACanvas.RoundRect(Px(Pad) div 2, ATop + 1, FRows.Width - Px(Pad) div 2, Bottom - 1, 8, 8);
    ACanvas.Pen.Style := psSolid;
  end;
  { The row a drag would be dropped on, outlined in the accent. }
  if ARow = FDropRow then
  begin
    ACanvas.Pen.Style := psSolid;
    ACanvas.Pen.Color := FAccent;
    ACanvas.Pen.Width := 2;
    ACanvas.Brush.Style := bsClear;
    ACanvas.RoundRect(Px(Pad) div 2 + 1, ATop + 2, FRows.Width - Px(Pad) div 2 - 1,
      Bottom - 2, 8, 8);
    ACanvas.Pen.Width := 1;
  end;

  if not FFiltered then
  begin
    ACanvas.Pen.Width := 2;
    for i := 0 to High(C.TopEdges) do
    begin
      ACanvas.Pen.Color := LaneColor(C.TopEdges[i].Color);
      ACanvas.Line(LaneX(C.TopEdges[i].FromLane), ATop, LaneX(C.TopEdges[i].ToLane), CenterY);
    end;
    for i := 0 to High(C.BottomEdges) do
    begin
      ACanvas.Pen.Color := LaneColor(C.BottomEdges[i].Color);
      ACanvas.Line(LaneX(C.BottomEdges[i].FromLane), CenterY,
        LaneX(C.BottomEdges[i].ToLane), Bottom);
    end;
    ACanvas.Pen.Width := 1;
  end;

  IsHead := False;
  for i := 0 to High(C.Refs) do
    if C.Refs[i].Kind = grHead then
      IsHead := True;
  if FFiltered then
    X := LaneX(0)
  else
    X := LaneX(C.Lane);
  if IsHead then
  begin
    ACanvas.Pen.Color := FText;
    ACanvas.Pen.Width := 2;
    if ARow = FCurrent then
      ACanvas.Brush.Color := FHover
    else
      ACanvas.Brush.Color := FBack;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Ellipse(X - Px(HeadRadius), CenterY - Px(HeadRadius), X + Px(HeadRadius) + 1,
      CenterY + Px(HeadRadius) + 1);
    ACanvas.Pen.Width := 1;
  end;
  ACanvas.Pen.Style := psClear;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := LaneColor(C.Color);
  ACanvas.Ellipse(X - Px(DotRadius), CenterY - Px(DotRadius), X + Px(DotRadius) + 1,
    CenterY + Px(DotRadius) + 1);
  ACanvas.Pen.Style := psSolid;
  ACanvas.Brush.Style := bsClear;

  ACanvas.Font := Font;
  TextY := CenterY - ACanvas.TextHeight('Xg') div 2;
  Right := FRows.Width - Px(Pad) - Px(ScrollRoom);
  if (FMarked <> '') and (C.Hash = FMarked) then
  begin
    ACanvas.Font.Style := [fsBold];
    ACanvas.Font.Color := FAccent;
  end
  else
    ACanvas.Font.Color := FDim;
  ACanvas.TextOut(Right - ACanvas.TextWidth(C.Short), TextY, C.Short);
  ACanvas.Font.Style := [];
  Dec(Right, ACanvas.TextWidth(StringOfChar('0', FIdChars)) + 4);
  Mark := '';
  if C.Unpushed then
  begin
    Mark := '↑';
    ACanvas.Font.Color := FAccent;
  end
  else if C.Unpulled then
  begin
    Mark := '↓';
    ACanvas.Font.Color := FText;
  end;
  if Mark <> '' then
    ACanvas.TextOut(Right - ACanvas.TextWidth(Mark), TextY, Mark);
  Dec(Right, ACanvas.TextWidth('↑') + Px(Gap) + Px(Gap) div 2);

  X := GraphRight;
  Meta := FMetaFull[Index];
  if Right - ACanvas.TextWidth(Meta) - Px(Gap) - X < FRows.Width div 3 then
    Meta := FMetaAge[Index];
  if Right - ACanvas.TextWidth(Meta) - Px(Gap) - X < FRows.Width div 4 then
    Meta := '';
  if Meta <> '' then
  begin
    ACanvas.Font.Color := FDim;
    ACanvas.TextOut(Right - ACanvas.TextWidth(Meta), TextY, Meta);
    Dec(Right, ACanvas.TextWidth(Meta) + Px(Gap) + Px(Gap) div 2);
  end;

  X := PaintRefs(ACanvas, C.Refs, X, CenterY, Right);
  ACanvas.Font := Font;
  Room := Right - X;
  if FSubjectRoom[Index] <> Room then
  begin
    FSubjects[Index] := FitText(ACanvas, C.Subject, Room);
    FSubjectRoom[Index] := Room;
  end;
  ACanvas.Font.Color := FText;
  ACanvas.TextOut(X, TextY, FSubjects[Index]);
end;

{ ---------------------------------------------------------------------------
  Statistics
  --------------------------------------------------------------------------- }

procedure TGittanCommitGraph.SetStatsHot(AValue: boolean);
begin
  if FStatsHot = AValue then
    Exit;
  FStatsHot := AValue;
  Invalidate;
end;

{ Statistics of the newest commits alone would mislead, so a log that
  was cut is asked for whole first, as a filter asks for it; the answer
  (Replace) counts them again. }
procedure TGittanCommitGraph.SetStatsOn(AValue: boolean);
begin
  if FStatsOn = AValue then
    Exit;
  FStatsOn := AValue;
  FStatsWeek := -1;
  FStatsAuthor := -1;
  FRows.Cursor := crDefault;
  if FStatsOn then
  begin
    if FMore and not FAskedMore and Assigned(FOnMore) then
      More;
    CountStats;
  end;
  Place;
  FBox.VertScrollBar.Position := 0;
  ScrollIntoView;
  FRows.Invalidate;
  Invalidate;
end;

{ The weeks are as many as fit at MinWeekWidth each, in local time. }
procedure TGittanCommitGraph.CountStats;
var
  L, R, i, j: integer;
begin
  StatsPlot(L, R);
  FStats := CommitStats(FCommits, FShown, Max(1, (R - L) div Px(MinWeekWidth)),
    Now - LocalTimeToUniversal(Now));
  FStatsAuthorMax := 1;
  for i := 0 to High(FStats.Authors) do
    for j := 0 to High(FStats.Authors[i].Weeks) do
      FStatsAuthorMax := Max(FStatsAuthorMax, FStats.Authors[i].Weeks[j]);
  FStatsWeek := -1;
  FStatsAuthor := -1;
end;

{ Where the weeks are drawn, right of the names and counts. }
function TGittanCommitGraph.StatsPlot(out ALeft, ARight: integer): boolean;
begin
  ALeft := Px(Pad) + Min(Px(StatsLabelWidth), (Width - 2 * Border) * 2 div 5);
  ARight := Width - 2 * Border - Px(Pad) - Px(ScrollRoom);
  Result := ARight - ALeft >= Px(MinWeekWidth);
end;

{ The line over the bars, the bars and the dates under them come
  first; the authors' rows start here. }
function TGittanCommitGraph.StatsAuthorsTop: integer;
begin
  Result := Px(Pad) div 2 + Px(RowHeight) + Px(Gap) div 2 + Px(ChartHeight) + Px(RowHeight) + Px(Gap);
end;

procedure TGittanCommitGraph.StatsHover(X, Y: integer);
var
  L, R, Week, Author, ChartTop: integer;
begin
  Week := -1;
  Author := -1;
  if (X >= 0) and StatsPlot(L, R) then
  begin
    Inc(Y, RowShift);
    ChartTop := Px(Pad) div 2 + Px(RowHeight) + Px(Gap) div 2;
    if (Length(FStats.Weeks) > 0) and (X >= L) and (X < R) and (Y >= ChartTop) and
      (Y < StatsAuthorsTop) then
      Week := Min(High(FStats.Weeks), Trunc((X - L) / ((R - L) / Length(FStats.Weeks))));
    if Y >= StatsAuthorsTop then
    begin
      Author := (Y - StatsAuthorsTop) div Px(RowHeight);
      if Author > High(FStats.Authors) then
        Author := -1;
    end;
  end;
  if Author >= 0 then
    FRows.Cursor := crHandPoint
  else
    FRows.Cursor := crDefault;
  if (Week = FStatsWeek) and (Author = FStatsAuthor) then
    Exit;
  FStatsWeek := Week;
  FStatsAuthor := Author;
  FRows.Invalidate;
end;

{ A click on an author shows their commits: the search keeps its paths
  and names the author in the place of what else it held. }
procedure TGittanCommitGraph.StatsClick(X, Y: integer);
var
  Search: string;
  i: integer;

  function Quoted(const APrefix, AValue: string): string;
  begin
    if Pos(' ', AValue) > 0 then
      Result := APrefix + '"' + AValue + '"'
    else
      Result := APrefix + AValue;
  end;

begin
  StatsHover(X, Y);
  if FStatsAuthor < 0 then
    Exit;
  Search := '';
  for i := 0 to High(FFilter.Paths) do
    Search := Search + Quoted('path:', FFilter.Paths[i]) + ' ';
  for i := 0 to High(FFilter.Changes) do
    Search := Search + Quoted('change:', FFilter.Changes[i]) + ' ';
  FEdit.Text := Search + Quoted('author:', FStats.Authors[FStatsAuthor].Name);
  FEdit.SelStart := Length(FEdit.Text);
  SetStatsOn(False);
  ApplyFilter;
end;

{ The line over the bars says how many commits and authors there are
  and over which days, or for the week under the mouse its count and
  the authors with the most commits in it. Under it a bar for every
  week, each author's part of it in their color (the authors with the
  most commits in the lane colors, the others dim), with the first and
  the last week's dates under them; then a row for every author with
  their count and their weeks as small bars, drawn against the most one
  author made in a week. }
procedure TGittanCommitGraph.PaintStats(ACanvas: TCanvas);
var
  Up, TextH, L, R, n, i, a, Most, Sum, X0, X1, Y, RowTop, ChartTop, ChartBottom,
    CountW, Best, k: integer;
  ColW: double;
  Line, Part, Count: string;
  Done: array of boolean;
  Clip: TRect;

  function AuthorColor(AIndex: integer): TColor;
  begin
    if AIndex < Length(FLaneColors) then
      Result := LaneColor(AIndex)
    else
      Result := FDim;
  end;

  procedure WeekX(AWeek: integer; out AX0, AX1: integer);
  begin
    AX0 := L + Round(AWeek * ColW);
    AX1 := L + Round((AWeek + 1) * ColW);
    if AX1 - AX0 >= Px(MinWeekWidth) then
      Dec(AX1);
    AX1 := Max(AX1, AX0 + 1);
  end;

  procedure Fill(AX0, AY0, AX1, AY1: integer; AColor: TColor);
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := AColor;
    ACanvas.FillRect(AX0, AY0, AX1, AY1);
  end;

begin
  Up := RowShift;
  ACanvas.Font := Font;
  TextH := ACanvas.TextHeight('Xg');
  StatsPlot(L, R);
  n := Length(FStats.Weeks);
  if n > 0 then
    ColW := (R - L) / n
  else
    ColW := 1;
  Clip := ACanvas.ClipRect;
  if IsRectEmpty(Clip) then
    Clip := FRows.ClientRect;

  { The line over the bars. }
  if (FStatsWeek >= 0) and (FStatsWeek < n) then
  begin
    Line := Format(rsStatsWeek, [FormatDateTime(DateFormat,
      FStats.FirstWeek + 7 * FStatsWeek), GroupDigits(FStats.Weeks[FStatsWeek])]);
    Done := nil;
    SetLength(Done, Length(FStats.Authors));
    for k := 1 to WeekAuthors do
    begin
      Best := -1;
      for a := 0 to High(FStats.Authors) do
        if not Done[a] and (FStats.Authors[a].Weeks[FStatsWeek] > 0) and ((Best < 0) or
          (FStats.Authors[a].Weeks[FStatsWeek] > FStats.Authors[Best].Weeks[FStatsWeek])) then
          Best := a;
      if Best < 0 then
        Break;
      Done[Best] := True;
      if k = 1 then
        Line := Line + ' · '
      else
        Line := Line + ', ';
      Line := Line + FStats.Authors[Best].Name + ' ' +
        IntToStr(FStats.Authors[Best].Weeks[FStatsWeek]);
    end;
  end
  else
  begin
    if Length(FStats.Authors) = 1 then
      Line := Format(rsStatsSummaryOne, [GroupDigits(FStats.Commits)])
    else
      Line := Format(rsStatsSummary, [GroupDigits(FStats.Commits),
        GroupDigits(Length(FStats.Authors))]);
    if FStats.Newest > 0 then
      Line := Line + ' · ' + FormatDateTime(DateFormat, FStats.Oldest) + ' – ' +
        FormatDateTime(DateFormat, FStats.Newest);
    if FMore then
      Line := Line + ' · ' + Format(rsStatsCut, [Length(FCommits)]);
    if FFiltered then
      Line := Line + ' · ' + rsStatsMatching;
  end;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Color := FDim;
  ACanvas.TextOut(Px(Pad), Px(Pad) div 2 + (Px(RowHeight) - TextH) div 2 - Up,
    FitText(ACanvas, Line, FRows.Width - 2 * Px(Pad) - Px(ScrollRoom)));

  { The bars, with the names column left of them. }
  ChartTop := Px(Pad) div 2 + Px(RowHeight) + Px(Gap) div 2 - Up;
  ChartBottom := ChartTop + Px(ChartHeight);
  Most := 1;
  for i := 0 to n - 1 do
    Most := Max(Most, FStats.Weeks[i]);
  ACanvas.Font.Style := [fsBold];
  ACanvas.Font.Color := FText;
  Count := GroupDigits(FStats.Commits);
  CountW := ACanvas.TextWidth(Count);
  ACanvas.TextOut(L - Px(Gap) - CountW, ChartTop, Count);
  ACanvas.TextOut(Px(Pad), ChartTop, FitText(ACanvas, rsStatsAll, L - 2 * Px(Gap) - Px(Pad) - CountW));
  ACanvas.Font.Style := [];
  ACanvas.Font.Color := FDim;
  if n = 0 then
    ACanvas.TextOut(L, ChartTop, rsStatsNoTime);
  if (FStatsWeek >= 0) and (FStatsWeek < n) then
  begin
    WeekX(FStatsWeek, X0, X1);
    Fill(X0 - 1, ChartTop, X1 + 1, ChartBottom, FHover);
  end;
  for i := 0 to n - 1 do
  begin
    if FStats.Weeks[i] = 0 then
      Continue;
    WeekX(i, X0, X1);
    Sum := 0;
    Y := ChartBottom;
    for a := 0 to High(FStats.Authors) do
    begin
      if FStats.Authors[a].Weeks[i] = 0 then
        Continue;
      Inc(Sum, FStats.Authors[a].Weeks[i]);
      RowTop := ChartBottom - Max(1, Round(Sum * (Px(ChartHeight) - 2) / Most));
      if RowTop < Y then
        Fill(X0, RowTop, X1, Y, AuthorColor(a));
      Y := RowTop;
    end;
  end;
  ACanvas.Pen.Color := FLine;
  ACanvas.Line(L, ChartBottom, R, ChartBottom);
  ACanvas.Brush.Style := bsClear;
  if n > 0 then
  begin
    ACanvas.Font.Color := FDim;
    ACanvas.TextOut(Px(Pad), ChartTop + TextH + 4, FitText(ACanvas,
      Format(rsStatsMostWeek, [GroupDigits(Most)]), L - 2 * Px(Gap) - Px(Pad)));
    Part := FormatDateTime(DateFormat, FStats.FirstWeek);
    ACanvas.TextOut(L, ChartBottom + 4, Part);
    if n > 1 then
    begin
      Line := FormatDateTime(DateFormat, FStats.FirstWeek + 7 * (n - 1));
      if R - ACanvas.TextWidth(Line) > L + ACanvas.TextWidth(Part) + Px(Gap) then
        ACanvas.TextOut(R - ACanvas.TextWidth(Line), ChartBottom + 4, Line);
    end;
  end;
  Y := StatsAuthorsTop - Px(Gap) div 2 - Up;
  ACanvas.Pen.Color := FLine;
  ACanvas.Line(Px(Pad) div 2, Y, FRows.Width - Px(Pad) div 2, Y);

  { The authors, only those in view. }
  for a := Max(0, (Clip.Top + Up - StatsAuthorsTop) div Px(RowHeight)) to
    Min(High(FStats.Authors), (Clip.Bottom + Up - StatsAuthorsTop) div Px(RowHeight)) do
  begin
    RowTop := StatsAuthorsTop + a * Px(RowHeight) - Up;
    if a = FStatsAuthor then
    begin
      ACanvas.Pen.Style := psClear;
      ACanvas.Brush.Style := bsSolid;
      ACanvas.Brush.Color := FHover;
      ACanvas.RoundRect(Px(Pad) div 2, RowTop + 1, FRows.Width - Px(Pad) div 2, RowTop + Px(RowHeight) - 1, 8, 8);
      ACanvas.Pen.Style := psSolid;
    end;
    ACanvas.Pen.Style := psClear;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := AuthorColor(a);
    Y := RowTop + Px(RowHeight) div 2;
    ACanvas.RoundRect(Px(Pad), Y - 5, Px(Pad) + 10, Y + 5, 4, 4);
    ACanvas.Pen.Style := psSolid;
    ACanvas.Brush.Style := bsClear;
    Count := GroupDigits(FStats.Authors[a].Total);
    CountW := ACanvas.TextWidth(Count);
    ACanvas.Font.Color := FDim;
    ACanvas.TextOut(L - Px(Gap) - CountW, Y - TextH div 2, Count);
    ACanvas.Font.Color := FText;
    ACanvas.TextOut(Px(Pad) + 18, Y - TextH div 2, FitText(ACanvas, FStats.Authors[a].Name,
      L - 2 * Px(Gap) - Px(Pad) - 18 - CountW));
    for i := 0 to n - 1 do
      if FStats.Authors[a].Weeks[i] > 0 then
      begin
        WeekX(i, X0, X1);
        Fill(X0, RowTop + Px(RowHeight) - 5 - Max(1, Round(FStats.Authors[a].Weeks[i] *
          (Px(RowHeight) - 10) / FStatsAuthorMax)), X1, RowTop + Px(RowHeight) - 5, AuthorColor(a));
      end;
    ACanvas.Brush.Style := bsClear;
  end;
end;

{ AText cut to fit ARoom with an ellipsis. A subject can be a whole
  paragraph, and measuring is slow, so it is first cut to as many
  characters as could fit at a third of the width of an "n", then the
  longest start that fits is found by halving. }
function TGittanCommitGraph.FitText(ACanvas: TCanvas; const AText: string;
  ARoom: integer): string;
var
  Lo, Hi, Mid, MaxChars: integer;
  S: string;
begin
  if ARoom <= 0 then
    Exit('');
  MaxChars := ARoom div Max(1, ACanvas.TextWidth('n') div 3) + 1;
  if UTF8Length(AText) > MaxChars then
    S := UTF8Copy(AText, 1, MaxChars)
  else
  begin
    S := AText;
    if ACanvas.TextWidth(S) <= ARoom then
      Exit(S);
  end;
  { The longest start of S that fits with the ellipsis: Lo fits, Hi
    does not. }
  Lo := 0;
  Hi := UTF8Length(S) + 1;
  while Hi - Lo > 1 do
  begin
    Mid := (Lo + Hi) div 2;
    if ACanvas.TextWidth(UTF8Copy(S, 1, Mid) + '…') <= ARoom then
      Lo := Mid
    else
      Hi := Mid;
  end;
  if Lo = 0 then
    Result := ''
  else
    Result := TrimRight(UTF8Copy(S, 1, Lo)) + '…';
end;

{ The refs as chips from X: the branch HEAD is on filled in the accent,
  other local branches outlined in it, remote branches in the dim color,
  tags in the tag color, a bisect's marks red for bad, green for good
  and dim for skip, in shades that read on either background; a long
  name is cut. The chips stop before
  ARight less some room for the subject. Returns where the subject goes. }
function TGittanCommitGraph.PaintRefs(ACanvas: TCanvas; const ARefs: TGittanGraphRefs;
  X, ACenterY, ARight: integer): integer;
var
  i, W, H, TextH: integer;
  RefName: string;
  Edge, Fill, Ink: TColor;
  Filled: boolean;
begin
  Result := X;
  if Length(ARefs) = 0 then
    Exit;
  ACanvas.Font := Font;
  TextH := ACanvas.TextHeight('Xg');
  H := TextH + 4;
  for i := 0 to High(ARefs) do
  begin
    RefName := ARefs[i].Name;
    if UTF8Length(RefName) > ChipMaxChars then
      RefName := UTF8Copy(RefName, 1, ChipMaxChars - 1) + '…';
    Filled := ARefs[i].Kind = grHead;
    if Filled then
      ACanvas.Font.Style := [fsBold]
    else
      ACanvas.Font.Style := [];
    W := ACanvas.TextWidth(RefName) + 2 * Px(ChipPadX);
    if X + W > ARight - 80 then
      Break;
    case ARefs[i].Kind of
      grHead, grBranch: Edge := FAccent;
      grRemote: Edge := FDim;
      grBisect:
        if RefName = 'bad' then
          Edge := RGBToColor(214, 76, 76)
        else if RefName = 'good' then
          Edge := RGBToColor(56, 158, 92)
        else
          Edge := FDim;
      else
        Edge := FTag;
    end;
    if Filled then
    begin
      Fill := FAccent;
      Ink := FBack;
    end
    else
    begin
      Fill := FBack;
      Ink := Edge;
    end;
    ACanvas.Pen.Color := Edge;
    if Filled then
    begin
      ACanvas.Brush.Style := bsSolid;
      ACanvas.Brush.Color := Fill;
    end
    else
      ACanvas.Brush.Style := bsClear;
    ACanvas.RoundRect(X, ACenterY - H div 2, X + W, ACenterY - H div 2 + H, H, H);
    ACanvas.Brush.Style := bsClear;
    ACanvas.Font.Color := Ink;
    ACanvas.TextOut(X + Px(ChipPadX), ACenterY - TextH div 2, RefName);
    Inc(X, W + Px(ChipGap));
  end;
  Result := X + Px(ChipGap);
end;

end.
