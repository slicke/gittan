unit gittan.commitgraph;

{** The commit graph: a panel in the middle of the form that shows the
  newest commits of every branch as a graph, each in its lane with the
  lines to its parents, the branches and tags on it as chips, its
  subject, author, age and short id, and an arrow on those not pushed
  or not pulled yet. The header names the branch and how far it is from
  its upstream.

  Like the popup list it is a child of the form, placed over whatever
  the form shows. Up and Down move in it, Enter or a click picks a
  commit (OnPick with its id); Escape, the close button, a click outside
  the panel or the application going to the background closes it. The
  rows sit in a TScrollBox for native scrolling. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType, LCLVersion,
  LMessages, gittan.graph;

type
  TGittanGraphPickEvent = procedure(Sender: TObject; const AHash: string) of object;

  TGittanCommitGraph = class;

  { TGittanGraphRows }

  {** The rows, inside the scroll box: painting and the mouse are the
    graph's, it only forwards them. }
  TGittanGraphRows = class(TCustomControl)
  private
    FGraph: TGittanCommitGraph;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    procedure MouseLeave; override;
    procedure KeyDown(var Key: word; Shift: TShiftState); override;
  end;

  { TGittanCommitGraph }

  TGittanCommitGraph = class(TCustomControl)
  private
    FBox: TScrollBox;
    FRows: TGittanGraphRows;
    FCommits: TGittanGraphCommits;
    FLanes: integer;
    FMore: boolean;
    FBranch: string;
    FAhead, FBehind: integer;
    FHasUpstream: boolean;
    { The highlighted row, the one Enter picks; -1 for none. }
    FCurrent: integer;
    FCloseRect: TRect;
    FCloseHot: boolean;
    FReturnFocus: TWinControl;
    FBack, FText, FDim, FHover, FLine, FAccent, FTag: TColor;
    FLaneColors: array of TColor;
    FOnPick: TGittanGraphPickEvent;
    function LaneColor(AIndex: integer): TColor;
    function LaneX(ALane: integer): integer;
    function GraphRight: integer;
    procedure Arrange;
    procedure Place;
    function RowAt(Y: integer): integer;
    procedure SetCurrent(AValue: integer);
    procedure SetCloseHot(AValue: boolean);
    procedure Step(ADelta: integer);
    procedure ScrollIntoView;
    procedure PaintRows(ACanvas: TCanvas);
    procedure PaintRow(ACanvas: TCanvas; AIndex, ATop: integer);
    function PaintRefs(ACanvas: TCanvas; const ARefs: TGittanGraphRefs;
      X, ACenterY, ARight: integer): integer;
    procedure Pick;
    procedure Dismiss;
    procedure KeyInput(var Key: word);
    {$IF lcl_fullversion >= 4990000}
    procedure UserInput(Sender: TObject; var Message: TLMessage);
    {$ELSE}
    procedure UserInput(Sender: TObject; Msg: cardinal);
    {$ENDIF}
    procedure AppDeactivate(Sender: TObject);
    function Owns(AControl: TControl): boolean;
    procedure Hook(AOn: boolean);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** Shows ACommits, laid out by LayoutGraph, in the middle of the
      parent, under a header with ABranch and how many commits it is
      ahead of (AAhead) and behind (ABehind) its upstream when it has
      one; AMore says the log was cut, which the last row says. The
      focus goes to the rows, on the commit HEAD is on. }
    procedure Popup(const ACommits: TGittanGraphCommits; AMore: boolean;
      const ABranch: string; AAhead, ABehind: integer; AHasUpstream: boolean);
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
    property OnPick: TGittanGraphPickEvent read FOnPick write FOnPick;
  end;

implementation

uses
  Math, DateUtils, LazUTF8, LCLIntf, gittan.reviews, gittan.statusbar;

resourcestring
  rsGraphTitle = 'Commit Graph';
  rsGraphNotPushed = '%d not pushed';
  rsGraphNotPulled = '%d not pulled';
  rsGraphInSync = 'up to date with upstream';
  rsGraphMore = 'Showing the newest %d commits';
  rsGraphEmpty = 'No commits yet';

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
  { Room at the right for the scroll bar, which overlays on macOS. }
  ScrollRoom = 8;
  Border = 1;

{ TGittanGraphRows }

procedure TGittanGraphRows.Paint;
begin
  FGraph.PaintRows(Canvas);
end;

procedure TGittanGraphRows.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  FGraph.SetCurrent(FGraph.RowAt(Y));
end;

procedure TGittanGraphRows.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Row: integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  Row := FGraph.RowAt(Y);
  if (Button = mbLeft) and (Row >= 0) then
  begin
    FGraph.SetCurrent(Row);
    FGraph.Pick;
  end;
end;

procedure TGittanGraphRows.MouseLeave;
begin
  inherited MouseLeave;
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
  ControlStyle := ControlStyle + [csOpaque];
  Visible := False;
  FCurrent := -1;
  FBox := TScrollBox.Create(Self);
  FBox.Parent := Self;
  FBox.BorderStyle := bsNone;
  FBox.HorzScrollBar.Visible := False;
  FRows := TGittanGraphRows.Create(Self);
  FRows.FGraph := Self;
  FRows.Parent := FBox;
  FRows.Align := alTop;
  FRows.ControlStyle := FRows.ControlStyle + [csOpaque];
  FRows.TabStop := True;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnShadow,
    clHighlight, clMaroon);
  SetLaneColors([clHighlight]);
end;

destructor TGittanCommitGraph.Destroy;
begin
  Hook(False);
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

function TGittanCommitGraph.LaneColor(AIndex: integer): TColor;
begin
  if Length(FLaneColors) = 0 then
    Exit(FAccent);
  Result := FLaneColors[AIndex mod Length(FLaneColors)];
end;

function TGittanCommitGraph.LaneX(ALane: integer): integer;
begin
  Result := Pad + Min(ALane, MaxLanes - 1) * LaneWidth + LaneWidth div 2;
end;

{ Where the text starts, right of the widest row's lanes. }
function TGittanCommitGraph.GraphRight: integer;
begin
  Result := Pad + Max(1, Min(FLanes, MaxLanes)) * LaneWidth + Gap;
end;

procedure TGittanCommitGraph.Popup(const ACommits: TGittanGraphCommits;
  AMore: boolean; const ABranch: string; AAhead, ABehind: integer;
  AHasUpstream: boolean);
var
  i, r: integer;
begin
  if Parent = nil then
    Exit;
  Dismiss;
  FCommits := ACommits;
  FLanes := GraphWidth(ACommits);
  FMore := AMore;
  FBranch := ABranch;
  FAhead := AAhead;
  FBehind := ABehind;
  FHasUpstream := AHasUpstream;
  FCurrent := -1;
  FCloseHot := False;
  for r := 0 to High(FCommits) do
  begin
    for i := 0 to High(FCommits[r].Refs) do
      if FCommits[r].Refs[i].Kind = grHead then
        FCurrent := r;
    if FCurrent >= 0 then
      Break;
  end;
  if (FCurrent < 0) and (Length(FCommits) > 0) then
    FCurrent := 0;
  Place;
  FReturnFocus := nil;
  if (Screen.ActiveControl <> nil) and not Owns(Screen.ActiveControl) then
  begin
    FReturnFocus := Screen.ActiveControl;
    FReturnFocus.FreeNotification(Self);
  end;
  Visible := True;
  BringToFront;
  FBox.VertScrollBar.Position := 0;
  ScrollIntoView;
  if FRows.CanFocus then
    FRows.SetFocus;
  Hook(True);
end;

{ In the middle of the parent, as wide as it allows up to MaxPanelWidth
  and as high as it allows, and no higher than the rows need. }
procedure TGittanCommitGraph.Place;
var
  W, H: integer;
begin
  if Parent = nil then
    Exit;
  W := Max(200, Min(MaxPanelWidth, Parent.ClientWidth - 2 * Margin));
  H := HeaderHeight + Max(1, Length(FCommits) + Ord(FMore)) * RowHeight + Pad div 2 + Border;
  H := Max(HeaderHeight + RowHeight, Min(H, Parent.ClientHeight - 2 * Margin));
  SetBounds((Parent.ClientWidth - W) div 2, (Parent.ClientHeight - H) div 2, W, H);
  Arrange;
end;

procedure TGittanCommitGraph.Recenter;
begin
  if Visible then
    Place;
end;

procedure TGittanCommitGraph.Arrange;
begin
  if (FBox = nil) or (FRows = nil) then
    Exit;
  FBox.SetBounds(Border, HeaderHeight, Width - 2 * Border,
    Max(RowHeight, Height - HeaderHeight - Border));
  FRows.Height := Max(1, Length(FCommits) + Ord(FMore)) * RowHeight;
  FCloseRect := Rect(Width - Pad - CloseSize + 4, (HeaderHeight - CloseSize) div 2,
    Width - Pad + 4, (HeaderHeight + CloseSize) div 2);
end;

procedure TGittanCommitGraph.Resize;
begin
  inherited Resize;
  Arrange;
end;

procedure TGittanCommitGraph.Dismiss;
begin
  if not Visible then
    Exit;
  Hook(False);
  Visible := False;
  if (FReturnFocus <> nil) and FReturnFocus.CanFocus then
    FReturnFocus.SetFocus;
  FReturnFocus := nil;
end;

procedure TGittanCommitGraph.Close;
begin
  Dismiss;
end;

procedure TGittanCommitGraph.Pick;
var
  Hash: string;
begin
  if (FCurrent < 0) or (FCurrent > High(FCommits)) then
    Exit;
  Hash := FCommits[FCurrent].Hash;
  Dismiss;
  if Assigned(FOnPick) then
    FOnPick(Self, Hash);
end;

function TGittanCommitGraph.RowAt(Y: integer): integer;
begin
  Result := -1;
  if Y < 0 then
    Exit;
  Result := Y div RowHeight;
  if Result > High(FCommits) then
    Result := -1;
end;

procedure TGittanCommitGraph.SetCurrent(AValue: integer);
begin
  if FCurrent = AValue then
    Exit;
  FCurrent := AValue;
  if AValue >= 0 then
    FRows.Cursor := crHandPoint
  else
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

procedure TGittanCommitGraph.Step(ADelta: integer);
begin
  if Length(FCommits) = 0 then
    Exit;
  SetCurrent(EnsureRange(FCurrent + ADelta, 0, High(FCommits)));
  ScrollIntoView;
end;

procedure TGittanCommitGraph.ScrollIntoView;
var
  RowTop, Pos: integer;
begin
  if FCurrent < 0 then
    Exit;
  RowTop := FCurrent * RowHeight;
  Pos := FBox.VertScrollBar.Position;
  if RowTop < Pos then
    FBox.VertScrollBar.Position := RowTop
  else if RowTop + RowHeight > Pos + FBox.ClientHeight then
    FBox.VertScrollBar.Position := RowTop + RowHeight - FBox.ClientHeight;
end;

{ Up and Down move a row, Page Up and Page Down a box, Home and End to
  the ends, Enter picks, Escape closes. }
procedure TGittanCommitGraph.KeyInput(var Key: word);
var
  Page: integer;
begin
  Page := Max(1, FBox.ClientHeight div RowHeight - 1);
  case Key of
    VK_UP: Step(-1);
    VK_DOWN: Step(1);
    VK_PRIOR: Step(-Page);
    VK_NEXT: Step(Page);
    VK_HOME: Step(-Length(FCommits));
    VK_END: Step(Length(FCommits));
    VK_RETURN: Pick;
    VK_ESCAPE: Close;
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
  if FCloseHot then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
end;

procedure TGittanCommitGraph.MouseLeave;
begin
  inherited MouseLeave;
  SetCloseHot(False);
end;

procedure TGittanCommitGraph.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button = mbLeft) and PtInRect(FCloseRect, Point(X, Y)) then
    Close;
end;

function TGittanCommitGraph.Owns(AControl: TControl): boolean;
begin
  Result := False;
  while AControl <> nil do
  begin
    if AControl = Self then
      Exit(True);
    AControl := AControl.Parent;
  end;
end;

{ As in the popup list: a mouse press on a control outside the panel
  closes it; Cocoa passes the last key message instead of the press, so
  the buttons are asked as well. }
{$IF lcl_fullversion >= 4990000}
procedure TGittanCommitGraph.UserInput(Sender: TObject; var Message: TLMessage);
var
  Msg: cardinal;
begin
  Msg := Message.msg;
{$ELSE}
procedure TGittanCommitGraph.UserInput(Sender: TObject; Msg: cardinal);
begin
{$ENDIF}
  if not Visible then
    Exit;
  if (Sender is TControl) and Owns(TControl(Sender)) then
    Exit;
  if (Msg = LM_LBUTTONDOWN) or (Msg = LM_RBUTTONDOWN) or (Msg = LM_MBUTTONDOWN) or
    (GetKeyState(VK_LBUTTON) < 0) or (GetKeyState(VK_RBUTTON) < 0) or
    (GetKeyState(VK_MBUTTON) < 0) then
    Close;
end;

procedure TGittanCommitGraph.AppDeactivate(Sender: TObject);
begin
  Close;
end;

procedure TGittanCommitGraph.Hook(AOn: boolean);
begin
  if AOn then
  begin
    Application.AddOnUserInputHandler(@UserInput, True);
    Application.AddOnDeactivateHandler(@AppDeactivate, True);
  end
  else
  begin
    Application.RemoveOnUserInputHandler(@UserInput);
    Application.RemoveOnDeactivateHandler(@AppDeactivate);
  end;
end;

procedure TGittanCommitGraph.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FReturnFocus) then
    FReturnFocus := nil;
end;

{ The border, the header (the title, the branch and how far it is from
  its upstream, the close button) and the divider under it. }
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
  Canvas.Line(Border, HeaderHeight - 1, Width - Border, HeaderHeight - 1);

  Canvas.Font := Font;
  BodyHeight := Canvas.TextHeight('Xg');
  CenterY := HeaderHeight div 2;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Size := Max(Font.Size, 13) + 1;
  Canvas.Font.Color := FText;
  Canvas.TextOut(Pad, CenterY - Canvas.TextHeight('Xg') div 2, rsGraphTitle);
  X := Pad + Canvas.TextWidth(rsGraphTitle) + 2 * Gap;
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
  Canvas.Pen.Color := FDim;
  Canvas.Pen.Width := 2;
  with FCloseRect do
  begin
    Canvas.Line(Left + 8, Top + 8, Right - 8, Bottom - 8);
    Canvas.Line(Right - 8, Top + 8, Left + 8, Bottom - 8);
  end;
  Canvas.Pen.Width := 1;
end;

{ Only the rows the box shows are painted: the log may have hundreds. }
procedure TGittanCommitGraph.PaintRows(ACanvas: TCanvas);
var
  First, Last, i: integer;
  R: TRect;
begin
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := FBack;
  ACanvas.FillRect(FRows.ClientRect);
  ACanvas.Font := Font;
  if Length(FCommits) = 0 then
  begin
    ACanvas.Brush.Style := bsClear;
    ACanvas.Font.Color := FDim;
    ACanvas.TextOut(Pad, (RowHeight - ACanvas.TextHeight('Xg')) div 2, rsGraphEmpty);
    Exit;
  end;
  R := ACanvas.ClipRect;
  if IsRectEmpty(R) then
    R := FRows.ClientRect;
  First := Max(0, R.Top div RowHeight);
  Last := Min(High(FCommits), R.Bottom div RowHeight);
  for i := First to Last do
    PaintRow(ACanvas, i, i * RowHeight);
  if FMore and (R.Bottom >= Length(FCommits) * RowHeight) then
  begin
    ACanvas.Brush.Style := bsClear;
    ACanvas.Font.Color := FDim;
    ACanvas.TextOut(GraphRight, Length(FCommits) * RowHeight +
      (RowHeight - ACanvas.TextHeight('Xg')) div 2,
      Format(rsGraphMore, [Length(FCommits)]));
  end;
end;

{ The row's highlight, its half of every line through it, its dot (a
  ring around it on the commit HEAD is on), then from the left the refs
  and the subject, from the right the short id with an arrow when the
  commit is not pushed or not pulled, and the author and age, dropped
  when the subject would get too little room. }
procedure TGittanCommitGraph.PaintRow(ACanvas: TCanvas; AIndex, ATop: integer);
var
  C: TGittanGraphCommit;
  i, CenterY, Bottom, X, Right, TextY, Room, n: integer;
  IsHead: boolean;
  Meta, Subject, Mark: string;
begin
  C := FCommits[AIndex];
  CenterY := ATop + RowHeight div 2;
  Bottom := ATop + RowHeight;
  if AIndex = FCurrent then
  begin
    ACanvas.Pen.Style := psClear;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := FHover;
    ACanvas.RoundRect(Pad div 2, ATop + 1, FRows.Width - Pad div 2, Bottom - 1, 8, 8);
    ACanvas.Pen.Style := psSolid;
  end;

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

  IsHead := False;
  for i := 0 to High(C.Refs) do
    if C.Refs[i].Kind = grHead then
      IsHead := True;
  X := LaneX(C.Lane);
  if IsHead then
  begin
    ACanvas.Pen.Color := FText;
    ACanvas.Pen.Width := 2;
    if AIndex = FCurrent then
      ACanvas.Brush.Color := FHover
    else
      ACanvas.Brush.Color := FBack;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Ellipse(X - HeadRadius, CenterY - HeadRadius, X + HeadRadius + 1,
      CenterY + HeadRadius + 1);
    ACanvas.Pen.Width := 1;
  end;
  ACanvas.Pen.Style := psClear;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := LaneColor(C.Color);
  ACanvas.Ellipse(X - DotRadius, CenterY - DotRadius, X + DotRadius + 1,
    CenterY + DotRadius + 1);
  ACanvas.Pen.Style := psSolid;
  ACanvas.Brush.Style := bsClear;

  ACanvas.Font := Font;
  TextY := CenterY - ACanvas.TextHeight('Xg') div 2;
  Right := FRows.Width - Pad - ScrollRoom;
  ACanvas.Font.Color := FDim;
  ACanvas.TextOut(Right - ACanvas.TextWidth(C.Short), TextY, C.Short);
  Dec(Right, ACanvas.TextWidth('0000000') + 4);
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
  Dec(Right, ACanvas.TextWidth('↑') + Gap + Gap div 2);

  X := GraphRight;
  Meta := C.Author;
  if C.Date > 0 then
  begin
    if Meta <> '' then
      Meta := Meta + ' · ';
    Meta := Meta + ReviewAge(C.Date, LocalTimeToUniversal(Now));
  end;
  if Right - ACanvas.TextWidth(Meta) - Gap - X < FRows.Width div 3 then
    Meta := ReviewAge(C.Date, LocalTimeToUniversal(Now));
  if Right - ACanvas.TextWidth(Meta) - Gap - X < FRows.Width div 4 then
    Meta := '';
  if Meta <> '' then
  begin
    ACanvas.Font.Color := FDim;
    ACanvas.TextOut(Right - ACanvas.TextWidth(Meta), TextY, Meta);
    Dec(Right, ACanvas.TextWidth(Meta) + Gap + Gap div 2);
  end;

  X := PaintRefs(ACanvas, C.Refs, X, CenterY, Right);
  ACanvas.Font := Font;
  Room := Right - X;
  Subject := C.Subject;
  if ACanvas.TextWidth(Subject) > Room then
  begin
    n := UTF8Length(Subject);
    while (n > 0) and (ACanvas.TextWidth(UTF8Copy(Subject, 1, n) + '…') > Room) do
      Dec(n);
    if n > 0 then
      Subject := TrimRight(UTF8Copy(Subject, 1, n)) + '…'
    else
      Subject := '';
  end;
  ACanvas.Font.Color := FText;
  ACanvas.TextOut(X, TextY, Subject);
end;

{ The refs as chips from X: the branch HEAD is on filled in the accent,
  other local branches outlined in it, remote branches in the dim color,
  tags in the tag color; a long name is cut. The chips stop before
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
    W := ACanvas.TextWidth(RefName) + 2 * ChipPadX;
    if X + W > ARight - 80 then
      Break;
    case ARefs[i].Kind of
      grHead, grBranch: Edge := FAccent;
      grRemote: Edge := FDim;
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
    ACanvas.TextOut(X + ChipPadX, ACenterY - TextH div 2, RefName);
    Inc(X, W + ChipGap);
  end;
  Result := X + ChipGap;
end;

end.
