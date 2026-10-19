unit gittan.fileheader;

{** The file header: a bar above the editor that names what it shows. On
  the left the badge and path of the file (the directory dimmed, the file
  name in full color, a dot after it while the editor holds unsaved
  changes), on the right its added and deleted line counts, the lexer,
  the actions the view offers as pills (Edit, Save, Revert) and the
  change navigator for jumping between the changed blocks.

  It paints itself with the editor's palette in both themes, like the
  summary, and owns the navigator as a child so it can lay out around it.
  The pills are painted here and hit-tested on the mouse, as the
  navigator does with its arrows.

  On macOS the window's toolbar shows the pills and the navigator
  instead (gittan.toolbar.pp): ShowControls off leaves them out here,
  and OnControlsChange tells when they, or the header's visibility,
  changed, so the toolbar can follow. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, ImgList, Types, gittan.changenav;

type
  {** A click on the action pill at AIndex, in the order of SetActions. }
  TGittanHeaderActionEvent = procedure(Sender: TObject; AIndex: integer) of object;

  { TGittanFileHeader }

  TGittanFileHeader = class(TCustomControl)
  private
    FPrefix, FName, FLexer, FStage, FSymbol, FNote: string;
    FIcon: integer;
    FAdded, FDeleted: integer;
    FHasCounts, FBinary, FModified: boolean;
    FImages: TCustomImageList;
    FNav, FConflictNav: TGittanChangeNav;
    FBack, FText, FDim, FAddedColor, FDeletedColor, FLine: TColor;
    FFill, FBorder, FHotColor: TColor;
    FActions: array of string;
    FActionsEnabled: array of boolean;
    FActionRects: array of TRect;
    FHot, FPressed: integer;
    FOnAction: TGittanHeaderActionEvent;
    FShowControls: boolean;
    FChangeCurrent, FChangeTotal: integer;
    FConflictCurrent, FConflictTotal: integer;
    FOnControlsChange: TNotifyEvent;
    procedure ControlsChanged;
    procedure SetShowControls(AValue: boolean);
    function GetActionCount: integer;
    function GetActionCaption(AIndex: integer): string;
    function GetActionEnabled(AIndex: integer): boolean;
    function ActionAt(X, Y: integer): integer;
    procedure SetHot(AValue: integer);
  protected
    procedure Paint; override;
    procedure VisibleChanged; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    constructor Create(AOwner: TComponent); override;
    {** Shows APath split into its directory and file name, with the badge
      at AIcon in Images (or none when AIcon is -1). The counts, the
      actions, the note and the modified dot are cleared. }
    procedure SetFile(const APath: string; AIcon: integer);
    {** Shows ATitle alone, without a badge. The counts, the actions, the
      note and the modified dot are cleared. }
    procedure SetTitle(const ATitle: string);
    {** Shows the added and deleted line counts, or "binary" when ABinary. }
    procedure SetCounts(AAdded, ADeleted: integer; ABinary: boolean);
    {** Shows "staged" or "partly staged" before the counts, or nothing
      when AStaged is false. }
    procedure SetStage(AStaged, AUnstaged: boolean);
    {** The lexer name shown on the right. }
    procedure SetLexer(const ALexer: string);
    {** The symbol the caret is in, shown dimmed after the file name, or
      '' for none. }
    procedure SetSymbol(const ASymbol: string);
    {** Shows the navigator at ACurrent of ATotal changes, or hides it when
      ATotal is 0. }
    procedure SetChanges(ACurrent, ATotal: integer);
    {** Shows ACurrent of ATotal conflicts in the conflict navigator, or
      hides it when ATotal is 0. }
    procedure SetConflicts(ACurrent, ATotal: integer);
    {** The action pills, left to right, all enabled; none for an empty
      array. A click fires OnAction with the index. }
    procedure SetActions(const ACaptions: array of string);
    {** Enables or dims the pill at AIndex. }
    procedure SetActionEnabled(AIndex: integer; AEnabled: boolean);
    {** Shows the dot after the file name that marks unsaved changes. }
    procedure SetModified(AModified: boolean);
    {** A warning shown in the deleted color left of the pills, or '' for
      none. }
    procedure SetNote(const ANote: string);
    {** Sets the palette: the background, the text, the dim text for the
      directory and lexer, the added and deleted colors, and the line color
      for the bottom border. }
    procedure SetColors(ABack, AText, ADim, AAdded, ADeleted, ALine: TColor);
    {** The pills' colors: the fill, the border and the text under the
      mouse. }
    procedure SetPillColors(AFill, ABorder, AHot: TColor);
    {** The image list the badge comes from. }
    property Images: TCustomImageList read FImages write FImages;
    {** The navigator, for its colors and click handlers. }
    property Nav: TGittanChangeNav read FNav;
    {** The conflict navigator, left of the other one while SetConflicts
      gave it a count, for its colors, suffix and click handlers. }
    property ConflictNav: TGittanChangeNav read FConflictNav;
    property OnAction: TGittanHeaderActionEvent read FOnAction write FOnAction;
    {** Whether the pills and the navigator are shown here; True by default. }
    property ShowControls: boolean read FShowControls write SetShowControls;
    property ActionCount: integer read GetActionCount;
    property ActionCaption[AIndex: integer]: string read GetActionCaption;
    property ActionEnabled[AIndex: integer]: boolean read GetActionEnabled;
    {** The navigator's position as SetChanges gave it. }
    property ChangeCurrent: integer read FChangeCurrent;
    property ChangeTotal: integer read FChangeTotal;
    {** The conflict navigator's position as SetConflicts gave it. }
    property ConflictCurrent: integer read FConflictCurrent;
    property ConflictTotal: integer read FConflictTotal;
    {** The actions, their states, the navigator's position or the
      header's visibility changed. }
    property OnControlsChange: TNotifyEvent read FOnControlsChange write FOnControlsChange;
  end;

implementation

resourcestring
  rsBinary = 'binary';
  rsStaged = 'staged';
  rsPartlyStaged = 'partly staged';

const
  HeaderHeight = 36;
  NavHeight = 26;
  PillHeight = 24;
  PillPad = 10;
  PillGap = 6;
  Pad = 12;
  Gap = 12;
  IconSize = 16;
  DotSize = 7;
  SymbolSep = '  ›  ';

{ TGittanFileHeader }

constructor TGittanFileHeader.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Height := HeaderHeight;
  FIcon := -1;
  FHot := -1;
  FPressed := -1;
  FShowControls := True;
  FNav := TGittanChangeNav.Create(Self);
  FNav.Parent := Self;
  FNav.Height := NavHeight;
  FNav.Anchors := [akRight, akTop];
  FNav.AnchorSideRight.Control := Self;
  FNav.AnchorSideRight.Side := asrRight;
  FNav.AnchorSideTop.Control := Self;
  FNav.AnchorSideTop.Side := asrCenter;
  FNav.BorderSpacing.Right := Pad - 2;
  FNav.Visible := False;
  { Left of the change navigator; a file with conflicts has changes, so
    the one it is anchored to is shown whenever it is. }
  FConflictNav := TGittanChangeNav.Create(Self);
  FConflictNav.Parent := Self;
  FConflictNav.Height := NavHeight;
  FConflictNav.Anchors := [akRight, akTop];
  FConflictNav.AnchorSideRight.Control := FNav;
  FConflictNav.AnchorSideRight.Side := asrLeft;
  FConflictNav.AnchorSideTop.Control := Self;
  FConflictNav.AnchorSideTop.Side := asrCenter;
  FConflictNav.BorderSpacing.Right := Gap div 2;
  FConflictNav.Visible := False;
  SetColors(clWindow, clWindowText, clGrayText, clGreen, clRed, clBtnShadow);
  SetPillColors(clBtnFace, clBtnShadow, clHighlight);
end;

procedure TGittanFileHeader.SetFile(const APath: string; AIcon: integer);
begin
  FPrefix := ExtractFilePath(APath);
  FName := ExtractFileName(APath);
  FIcon := AIcon;
  FHasCounts := False;
  FStage := '';
  FSymbol := '';
  FNote := '';
  FModified := False;
  SetActions([]);
end;

procedure TGittanFileHeader.SetTitle(const ATitle: string);
begin
  FPrefix := '';
  FName := ATitle;
  FIcon := -1;
  FHasCounts := False;
  FStage := '';
  FSymbol := '';
  FNote := '';
  FModified := False;
  SetActions([]);
end;

procedure TGittanFileHeader.SetStage(AStaged, AUnstaged: boolean);
begin
  if not AStaged then
    FStage := ''
  else if AUnstaged then
    FStage := rsPartlyStaged
  else
    FStage := rsStaged;
  Invalidate;
end;

procedure TGittanFileHeader.SetCounts(AAdded, ADeleted: integer; ABinary: boolean);
begin
  FAdded := AAdded;
  FDeleted := ADeleted;
  FBinary := ABinary;
  FHasCounts := True;
  Invalidate;
end;

procedure TGittanFileHeader.SetLexer(const ALexer: string);
begin
  if FLexer = ALexer then
    Exit;
  FLexer := ALexer;
  Invalidate;
end;

procedure TGittanFileHeader.SetSymbol(const ASymbol: string);
begin
  if FSymbol = ASymbol then
    Exit;
  FSymbol := ASymbol;
  Invalidate;
end;

procedure TGittanFileHeader.SetChanges(ACurrent, ATotal: integer);
begin
  FChangeCurrent := ACurrent;
  FChangeTotal := ATotal;
  FNav.Visible := FShowControls and (ATotal > 0);
  if ATotal > 0 then
    FNav.SetPosition(ACurrent, ATotal);
  { The room for the path depends on the navigator's width. }
  Invalidate;
  ControlsChanged;
end;

procedure TGittanFileHeader.SetConflicts(ACurrent, ATotal: integer);
begin
  FConflictCurrent := ACurrent;
  FConflictTotal := ATotal;
  FConflictNav.Visible := FShowControls and (ATotal > 0);
  if ATotal > 0 then
    FConflictNav.SetPosition(ACurrent, ATotal);
  Invalidate;
  ControlsChanged;
end;

procedure TGittanFileHeader.ControlsChanged;
begin
  if Assigned(FOnControlsChange) then
    FOnControlsChange(Self);
end;

procedure TGittanFileHeader.VisibleChanged;
begin
  inherited VisibleChanged;
  ControlsChanged;
end;

procedure TGittanFileHeader.SetShowControls(AValue: boolean);
begin
  if FShowControls = AValue then
    Exit;
  FShowControls := AValue;
  FNav.Visible := AValue and (FChangeTotal > 0);
  FConflictNav.Visible := AValue and (FConflictTotal > 0);
  SetHot(-1);
  Invalidate;
end;

function TGittanFileHeader.GetActionCount: integer;
begin
  Result := Length(FActions);
end;

function TGittanFileHeader.GetActionCaption(AIndex: integer): string;
begin
  Result := FActions[AIndex];
end;

function TGittanFileHeader.GetActionEnabled(AIndex: integer): boolean;
begin
  Result := FActionsEnabled[AIndex];
end;

procedure TGittanFileHeader.SetActions(const ACaptions: array of string);
var
  i: integer;
begin
  SetLength(FActions, Length(ACaptions));
  SetLength(FActionsEnabled, Length(ACaptions));
  SetLength(FActionRects, Length(ACaptions));
  for i := 0 to High(ACaptions) do
  begin
    FActions[i] := ACaptions[i];
    FActionsEnabled[i] := True;
    FActionRects[i] := Rect(0, 0, 0, 0);
  end;
  FHot := -1;
  FPressed := -1;
  Cursor := crDefault;
  Invalidate;
  ControlsChanged;
end;

procedure TGittanFileHeader.SetActionEnabled(AIndex: integer; AEnabled: boolean);
begin
  if (AIndex < 0) or (AIndex > High(FActionsEnabled)) then
    Exit;
  if FActionsEnabled[AIndex] = AEnabled then
    Exit;
  FActionsEnabled[AIndex] := AEnabled;
  Invalidate;
  ControlsChanged;
end;

procedure TGittanFileHeader.SetModified(AModified: boolean);
begin
  if FModified = AModified then
    Exit;
  FModified := AModified;
  Invalidate;
end;

procedure TGittanFileHeader.SetNote(const ANote: string);
begin
  if FNote = ANote then
    Exit;
  FNote := ANote;
  Invalidate;
end;

procedure TGittanFileHeader.SetColors(ABack, AText, ADim, AAdded, ADeleted,
  ALine: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FAddedColor := AAdded;
  FDeletedColor := ADeleted;
  FLine := ALine;
  Color := ABack;
  Invalidate;
end;

procedure TGittanFileHeader.SetPillColors(AFill, ABorder, AHot: TColor);
begin
  FFill := AFill;
  FBorder := ABorder;
  FHotColor := AHot;
  Invalidate;
end;

{ The pill under the point, -1 for none; a dimmed pill is not hit. }
function TGittanFileHeader.ActionAt(X, Y: integer): integer;
var
  i: integer;
begin
  if not FShowControls then
    Exit(-1);
  for i := 0 to High(FActionRects) do
    if FActionsEnabled[i] and FActionRects[i].Contains(Point(X, Y)) then
      Exit(i);
  Result := -1;
end;

procedure TGittanFileHeader.SetHot(AValue: integer);
begin
  if FHot = AValue then
    Exit;
  FHot := AValue;
  if AValue >= 0 then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  Invalidate;
end;

procedure TGittanFileHeader.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(ActionAt(X, Y));
end;

procedure TGittanFileHeader.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1);
end;

procedure TGittanFileHeader.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FPressed := ActionAt(X, Y);
    Invalidate;
  end;
end;

{ The click fires on release over the pill that was pressed. }
procedure TGittanFileHeader.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Index: integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  Index := FPressed;
  FPressed := -1;
  Invalidate;
  if (Index < 0) or (Index <> ActionAt(X, Y)) then
    Exit;
  if Assigned(FOnAction) then
    FOnAction(Self, Index);
end;

{ Right to left: the navigator, the pills, the note, the lexer, the
  counts; then the badge and the path from the left in the room that is
  left, the modified dot after the name, and the symbol the caret is in
  after that when it fits. A path too long for the room loses its
  directory first, then its end. }
procedure TGittanFileHeader.Paint;
var
  X, Right, TextY, Room, i, W, PillTop: integer;
  Prefix, FileName, S: string;
  R: TRect;

  procedure DrawRight(const AText: string; AColor: TColor);
  begin
    if AText = '' then
      Exit;
    Canvas.Font.Color := AColor;
    Dec(Right, Canvas.TextWidth(AText));
    Canvas.TextOut(Right, TextY, AText);
    Dec(Right, Gap);
  end;

begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := FLine;
  Canvas.Line(0, Height - 1, Width, Height - 1);

  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  TextY := (Height - 1 - Canvas.TextHeight('Xg')) div 2;
  Right := Width - Pad;
  if FNav.Visible then
    Dec(Right, FNav.Width + Gap);
  if FConflictNav.Visible then
    Dec(Right, FConflictNav.Width + Gap div 2);
  { The pills, the last one rightmost. }
  PillTop := (Height - 1 - PillHeight) div 2;
  for i := High(FActions) downto 0 do
  begin
    if not FShowControls then
      Break;
    W := Canvas.TextWidth(FActions[i]) + 2 * PillPad;
    R := Rect(Right - W, PillTop, Right, PillTop + PillHeight);
    FActionRects[i] := R;
    Canvas.Pen.Color := FBorder;
    Canvas.Pen.Width := 1;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FFill;
    Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, PillHeight, PillHeight);
    Canvas.Brush.Style := bsClear;
    if not FActionsEnabled[i] then
      Canvas.Font.Color := FDim
    else if (FPressed = i) or ((FPressed < 0) and (FHot = i)) then
      Canvas.Font.Color := FHotColor
    else
      Canvas.Font.Color := FText;
    Canvas.TextOut(R.Left + PillPad, TextY, FActions[i]);
    Right := R.Left;
    if i = 0 then
      Dec(Right, Gap)
    else
      Dec(Right, PillGap);
  end;
  DrawRight(FNote, FDeletedColor);
  DrawRight(FLexer, FDim);
  if FHasCounts then
    if FBinary then
      DrawRight(rsBinary, FDim)
    else
    begin
      if FDeleted > 0 then
        DrawRight('−' + IntToStr(FDeleted), FDeletedColor)
      else
        DrawRight('−0', FDim);
      Right := Right + Gap div 2;
      if FAdded > 0 then
        DrawRight('+' + IntToStr(FAdded), FAddedColor)
      else
        DrawRight('+0', FDim);
    end;
  DrawRight(FStage, FDim);

  X := Pad;
  if (FIcon >= 0) and (FImages <> nil) then
  begin
    FImages.DrawForPPI(Canvas, X, (Height - 1 - IconSize) div 2, FIcon,
      IconSize, Font.PixelsPerInch, GetCanvasScaleFactor);
    Inc(X, IconSize + Gap div 2 + 2);
  end;
  Room := Right - X;
  if FModified then
    Dec(Room, DotSize + Gap div 2);
  Prefix := FPrefix;
  FileName := FName;
  if Canvas.TextWidth(Prefix + FileName) > Room then
    Prefix := '';
  if Canvas.TextWidth(FileName) > Room then
  begin
    S := FileName;
    while (S <> '') and (Canvas.TextWidth(S + '…') > Room) do
    begin
      S := Copy(S, 1, Length(S) - 1);
      { Keep UTF-8 sequences whole. }
      while (S <> '') and (Ord(S[Length(S)]) and $C0 = $80) do
        S := Copy(S, 1, Length(S) - 1);
    end;
    FileName := S + '…';
  end;
  if Prefix <> '' then
  begin
    Canvas.Font.Color := FDim;
    Canvas.TextOut(X, TextY, Prefix);
    Inc(X, Canvas.TextWidth(Prefix));
  end;
  Canvas.Font.Color := FText;
  Canvas.TextOut(X, TextY, FileName);
  Inc(X, Canvas.TextWidth(FileName));
  if FModified then
  begin
    Inc(X, Gap div 2);
    Canvas.Pen.Color := FText;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FText;
    PillTop := (Height - 1 - DotSize) div 2;
    Canvas.Ellipse(X, PillTop, X + DotSize, PillTop + DotSize);
    Canvas.Brush.Style := bsClear;
    Inc(X, DotSize);
  end;
  if FSymbol = '' then
    Exit;
  S := SymbolSep + FSymbol;
  if X + Canvas.TextWidth(S) > Right then
    Exit;
  Canvas.Font.Color := FDim;
  Canvas.TextOut(X, TextY, S);
end;

end.
