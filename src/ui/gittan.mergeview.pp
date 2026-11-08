unit gittan.mergeview;

{** The merge editor: a conflicted file in three panes, the user's side
  (mine) and the side that came in (theirs) next to each other above,
  row for row, and the result under them across the width; a fourth,
  the merge base both sides started from, can be shown between mine
  and theirs when git wrote it into the markers (ShowBase, HasBase). Each
  conflict starts with a header row in the two panes above, and each of
  its lines has a box in the band left of the text: a tick puts the line
  into the result, and the header's box takes or drops the whole side
  (a side without lines too, which resolves the conflict as its
  deletion). The result follows the ticks (gittan.merge); it can be
  edited by hand as well, and from then on the boxes are off until the
  result is reset to the ticks. A conflict with nothing ticked stays in
  the result as git wrote it.

  The two panes above scroll together, and the result follows them to
  the same chunk of the file while it is not edited by hand. The rows
  take the bookmark kinds the form gives (KindMine and the others), so
  the form's own colors paint them; the band, the headers and the
  captions are drawn in colors the form sets, like the file header. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Controls, ExtCtrls, Graphics, LCLType,
  ATSynEdit, ATSynEdit_Adapter_EControl, ATSynEdit_Bookmarks, ATSynEdit_Globals,
  ATSynEdit_WrapInfo, ATScrollBar, ATStringProc, ec_SyntAnal, gittan.merge;

type
  { TGittanMergeCaption }

  {** The strip over a pane: its title in the text color and a detail
    after it, dimmed. }
  TGittanMergeCaption = class(TCustomControl)
  private
    FTitle, FDetail: string;
    FBack, FText, FDim, FLine: TColor;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetText(const ATitle, ADetail: string);
    procedure SetColors(ABack, AText, ADim, ALine: TColor);
  end;

  { TGittanMergeView }

  TGittanMergeView = class(TCustomControl)
  private
    FMerge: TGittanMerge;
    FRows: TGittanMergeRows;
    FStarts: TIntegerDynArray;
    FTop: TPanel;
    FMinePanel, FBasePanel, FTheirsPanel: TPanel;
    FMineCap, FBaseCap, FTheirsCap, FResultCap: TGittanMergeCaption;
    FEditMine, FEditBase, FEditTheirs, FEditResult: TATSynEdit;
    FAdapterMine, FAdapterBase, FAdapterTheirs, FAdapterResult: TATAdapterEControl;
    FSideSplitter, FBaseSplitter, FTopSplitter: TSplitter;
    FEdited, FFilling, FSyncing, FShowBase: boolean;
    FKindMine, FKindTheirs, FKindBase, FKindMarker, FKindFiller, FKindHeader: integer;
    FBack, FText, FDim, FLine, FAccent: TColor;
    FConflict, FPill, FPillText, FBorder: TColor;
    FMineTitle, FTheirsTitle, FBaseTitle, FResultTitle: string;
    FHeaderText, FEditedText, FResolvedText, FNoLinesText: string;
    FOnPicked, FOnEdited: TNotifyEvent;
    FTopRatio, FSideRatio, FBaseRatio: double;
    { The header row GoToConflict went to last and the top row that left
      in view, so the next step goes on from that conflict while the
      panes are not scrolled since. }
    FGoneRow, FGoneTop: integer;
    procedure ShowConflictRow(ARow: integer);
    procedure SetupEditor(AEd: TATSynEdit);
    procedure FillSide(AEd: TATSynEdit; ASide: TGittanMergeSide);
    procedure FillBase;
    procedure FillPanes;
    function BaseShown: boolean;
    procedure SetShowBase(AValue: boolean);
    procedure LayoutBase;
    procedure FillResult(AKeepTop: boolean);
    procedure SetText(AEd: TATSynEdit; const AText: string);
    procedure UpdateCaptions;
    function SideOf(AEd: TATSynEdit): TGittanMergeSide;
    function BandRect(AEd: TATSynEdit): TRect;
    procedure Toggle(AEd: TATSynEdit; ARow: integer);
    procedure EditDraw(Sender: TObject; C: TCanvas; const ARect: TRect);
    procedure DrawHeader(AEd: TATSynEdit; C: TCanvas; ATop: integer;
      const ATitle, AName: string; AEmpty: boolean);
    procedure EditClickGutter(Sender: TObject; ABand, ALine: integer; var AHandled: boolean);
    procedure EditMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure EditScroll(Sender: TObject);
    procedure ResultChange(Sender: TObject);
    procedure SplitterMoved(Sender: TObject);
    procedure SetLexer(ALexer: TecSyntAnalyzer);
    function GetLexer: TecSyntAnalyzer;
    function ConflictNumber(AChunk: integer): integer;
  protected
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** Shows AMerge, which the view owns from now on. }
    procedure Load(AMerge: TGittanMerge);
    {** Drops the merge shown. }
    procedure Clear;
    {** The result as the pane holds it, a line each. }
    function ResultLines: TStringArray;
    {** Sets the result to the ticks again, dropping what was typed. }
    procedure ResetResult;
    {** Ticks one side whole in every conflict, the other dropped. }
    procedure PickEverywhere(ASide: TGittanMergeSide);
    {** Goes to the next (or previous) conflict from the top of the
      panes, or from the one it went to last while they stay put; False
      when there is none that way. }
    function GoToConflict(ANext: boolean): boolean;
    {** Goes to the first (or the last, not AFirst) conflict; False when
      there is none. }
    function GoToEdgeConflict(AFirst: boolean): boolean;
    {** Which conflict the panes show at their top, 0-based, or -1
      above the first. }
    function CurrentConflict: integer;
    {** Whether the merge shown has the base in its markers, so the
      base pane can be shown. }
    function HasBase: boolean;
    {** Takes the font, zoom, tab size and bookmark colors of AFrom, and
      the scroll bars' theme AScrollTheme (nil leaves them); the form
      gives each editor its colors itself. }
    procedure Restyle(AFrom: TATSynEdit; AScrollTheme: PATScrollbarTheme);
    procedure SetColors(ABack, AText, ADim, ALine, AAccent: TColor);
    {** The colors of the conflicts' headers: the conflict's (the fork
      and the bar down the band), and the pill with the side's name. }
    procedure SetHeaderColors(AConflict, APill, APillText, ABorder: TColor);
    {** The bookmark kinds the rows take, which the form colors. }
    procedure SetKinds(AMine, ATheirs, ABase, AMarker, AFiller, AHeader: integer);
    {** The titles: the panes' captions and the conflict headers
      (Format with the number and the count; the side's name follows as
      a pill), the
      note of a result edited by hand, the count of the resolved (with
      the resolved and the count), and what a header says of a side
      without lines. }
    procedure SetTexts(const AMine, ATheirs, ABase, AResult, AHeader, AEdited, AResolved,
      ANoLines: string);
    property Merge: TGittanMerge read FMerge;
    property Edited: boolean read FEdited;
    {** Show the base pane between mine and theirs, for a merge whose
      markers hold the base (HasBase); without one the panes stay two
      whatever this says. }
    property ShowBase: boolean read FShowBase write SetShowBase;
    property EditMine: TATSynEdit read FEditMine;
    property EditBase: TATSynEdit read FEditBase;
    property EditTheirs: TATSynEdit read FEditTheirs;
    property EditResult: TATSynEdit read FEditResult;
    property Lexer: TecSyntAnalyzer read GetLexer write SetLexer;
    {** A tick changed the result. }
    property OnPicked: TNotifyEvent read FOnPicked write FOnPicked;
    {** The result was typed in for the first time since it was set. }
    property OnEdited: TNotifyEvent read FOnEdited write FOnEdited;
  end;

implementation

uses
  gittan.theme;

const
  gutterTagPick = 201;

{ TGittanMergeCaption }

constructor TGittanMergeCaption.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Height := Px(24);
  FBack := clBtnFace;
  FText := clWindowText;
  FDim := clGrayText;
  FLine := clGrayText;
end;

procedure TGittanMergeCaption.SetText(const ATitle, ADetail: string);
begin
  if (ATitle = FTitle) and (ADetail = FDetail) then
    Exit;
  FTitle := ATitle;
  FDetail := ADetail;
  Invalidate;
end;

procedure TGittanMergeCaption.SetColors(ABack, AText, ADim, ALine: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FLine := ALine;
  Invalidate;
end;

procedure TGittanMergeCaption.Paint;
var
  X, Y: integer;
begin
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := FLine;
  Canvas.Line(0, ClientHeight - 1, ClientWidth, ClientHeight - 1);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FText;
  X := Px(10);
  Y := (ClientHeight - Canvas.TextHeight('Ag')) div 2;
  Canvas.TextOut(X, Y, FTitle);
  Inc(X, Canvas.TextWidth(FTitle) + Px(8));
  Canvas.Font.Style := [];
  Canvas.Font.Color := FDim;
  Canvas.TextRect(Rect(X, 0, ClientWidth - Px(6), ClientHeight), X, Y, FDetail);
  Canvas.Brush.Style := bsSolid;
end;

{ TGittanMergeView }

constructor TGittanMergeView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTopRatio := 0.55;
  FSideRatio := 0.5;
  FBaseRatio := 1 / 3;
  FGoneRow := -1;
  FBack := clWindow;
  FText := clWindowText;
  FDim := clGrayText;
  FLine := clGrayText;
  FAccent := clHighlight;
  FConflict := clPurple;
  FPill := clBtnFace;
  FPillText := clBtnText;
  FBorder := clGrayText;
  FMineTitle := 'Mine';
  FTheirsTitle := 'Theirs';
  FBaseTitle := 'Base';
  FResultTitle := 'Result';
  FHeaderText := 'Conflict %d of %d';
  FEditedText := 'edited by hand';
  FResolvedText := '%d of %d resolved';
  FNoLinesText := 'no lines';

  FTop := TPanel.Create(Self);
  FTop.Parent := Self;
  FTop.Align := alTop;
  FTop.BevelOuter := bvNone;
  FTop.Height := 200;

  FMinePanel := TPanel.Create(Self);
  FMinePanel.Parent := FTop;
  FMinePanel.Align := alLeft;
  FMinePanel.BevelOuter := bvNone;
  FMinePanel.Width := 200;
  FMineCap := TGittanMergeCaption.Create(Self);
  FMineCap.Parent := FMinePanel;
  FMineCap.Align := alTop;
  FEditMine := TATSynEdit.Create(Self);
  FEditMine.Parent := FMinePanel;
  FEditMine.Align := alClient;

  FSideSplitter := TSplitter.Create(Self);
  FSideSplitter.Parent := FTop;
  FSideSplitter.Align := alLeft;
  FSideSplitter.Left := FMinePanel.Width + 1;
  FSideSplitter.Width := Px(4);
  FSideSplitter.ResizeStyle := rsUpdate;
  FSideSplitter.OnMoved := @SplitterMoved;

  { The base pane and its splitter, right of the first splitter; both
    hidden until a merge with a base is shown with ShowBase on. }
  FBasePanel := TPanel.Create(Self);
  FBasePanel.Parent := FTop;
  FBasePanel.Align := alLeft;
  FBasePanel.BevelOuter := bvNone;
  FBasePanel.Width := 200;
  FBasePanel.Left := FSideSplitter.Left + FSideSplitter.Width + 1;
  FBasePanel.Visible := False;
  FBaseCap := TGittanMergeCaption.Create(Self);
  FBaseCap.Parent := FBasePanel;
  FBaseCap.Align := alTop;
  FEditBase := TATSynEdit.Create(Self);
  FEditBase.Parent := FBasePanel;
  FEditBase.Align := alClient;

  FBaseSplitter := TSplitter.Create(Self);
  FBaseSplitter.Parent := FTop;
  FBaseSplitter.Align := alLeft;
  FBaseSplitter.Left := FBasePanel.Left + FBasePanel.Width + 1;
  FBaseSplitter.Width := Px(4);
  FBaseSplitter.ResizeStyle := rsUpdate;
  FBaseSplitter.OnMoved := @SplitterMoved;
  FBaseSplitter.Visible := False;

  FTheirsPanel := TPanel.Create(Self);
  FTheirsPanel.Parent := FTop;
  FTheirsPanel.Align := alClient;
  FTheirsPanel.BevelOuter := bvNone;
  FTheirsCap := TGittanMergeCaption.Create(Self);
  FTheirsCap.Parent := FTheirsPanel;
  FTheirsCap.Align := alTop;
  FEditTheirs := TATSynEdit.Create(Self);
  FEditTheirs.Parent := FTheirsPanel;
  FEditTheirs.Align := alClient;

  FTopSplitter := TSplitter.Create(Self);
  FTopSplitter.Parent := Self;
  FTopSplitter.Align := alTop;
  FTopSplitter.Top := FTop.Height + 1;
  FTopSplitter.Height := Px(4);
  FTopSplitter.ResizeStyle := rsUpdate;
  FTopSplitter.OnMoved := @SplitterMoved;

  FResultCap := TGittanMergeCaption.Create(Self);
  FResultCap.Parent := Self;
  FResultCap.Align := alTop;
  FResultCap.Top := FTopSplitter.Top + FTopSplitter.Height + 1;
  FEditResult := TATSynEdit.Create(Self);
  FEditResult.Parent := Self;
  FEditResult.Align := alClient;

  FAdapterMine := TATAdapterEControl.Create(Self);
  FAdapterMine.AddEditor(FEditMine);
  FAdapterBase := TATAdapterEControl.Create(Self);
  FAdapterBase.AddEditor(FEditBase);
  FAdapterTheirs := TATAdapterEControl.Create(Self);
  FAdapterTheirs.AddEditor(FEditTheirs);
  FAdapterResult := TATAdapterEControl.Create(Self);
  FAdapterResult.AddEditor(FEditResult);

  SetupEditor(FEditMine);
  SetupEditor(FEditBase);
  SetupEditor(FEditTheirs);
  SetupEditor(FEditResult);
  FEditResult.ModeReadOnly := False;
  FEditResult.OnChange := @ResultChange;
  FEditResult.OnScroll := nil;
end;

destructor TGittanMergeView.Destroy;
begin
  FreeAndNil(FMerge);
  inherited Destroy;
end;

procedure TGittanMergeView.SetupEditor(AEd: TATSynEdit);
var
  Band: integer;
begin
  AEd.ModeReadOnly := True;
  AEd.OptBorderVisible := False;
  AEd.OptScrollbarsNew := True;
  AEd.OptCaretVirtual := False;
  AEd.OptRulerVisible := False;
  AEd.OptUnprintedVisible := False;
  AEd.OptMinimapVisible := False;
  AEd.OptMicromapVisible := False;
  AEd.OptWrapMode := TATEditorWrapMode.ModeOff;
  AEd.OptNumbersStyle := TATEditorNumbersStyle.All;
  AEd.OptGutterShowFoldAlways := False;
  {$IFDEF LCLGtk3}
  AEd.DoubleBuffered := True;
  AEd.OptCaretBlinkEnabled := False;
  {$ENDIF}
  Band := AEd.Gutter.FindIndexByTag(ATEditorOptions.GutterTagFolding);
  if Band >= 0 then
    AEd.Gutter[Band].Visible := False;
  Band := AEd.Gutter.FindIndexByTag(ATEditorOptions.GutterTagLineStates);
  if Band >= 0 then
    AEd.Gutter[Band].Visible := False;
  AEd.OnDrawEditor := @EditDraw;
  if AEd <> FEditResult then
  begin
    { The rows above are no lines of the file: the numbers would count
      the headers and the padding. The band of boxes takes their place. }
    Band := AEd.Gutter.FindIndexByTag(ATEditorOptions.GutterTagNumbers);
    if Band >= 0 then
      AEd.Gutter[Band].Visible := False;
    AEd.Gutter.Add(-1, Px(26), gutterTagPick, False, True);
    AEd.OnClickGutter := @EditClickGutter;
    AEd.OnMouseUp := @EditMouseUp;
    AEd.OnScroll := @EditScroll;
  end;
  AEd.Gutter.Update;
end;

procedure TGittanMergeView.SetColors(ABack, AText, ADim, ALine, AAccent: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FLine := ALine;
  FAccent := AAccent;
  Color := ALine;
  FTop.Color := ALine;
  FMinePanel.Color := ALine;
  FBasePanel.Color := ALine;
  FTheirsPanel.Color := ALine;
  FMineCap.SetColors(ABack, AText, ADim, ALine);
  FBaseCap.SetColors(ABack, AText, ADim, ALine);
  FTheirsCap.SetColors(ABack, AText, ADim, ALine);
  FResultCap.SetColors(ABack, AText, ADim, ALine);
  Invalidate;
end;

procedure TGittanMergeView.SetHeaderColors(AConflict, APill, APillText, ABorder: TColor);
begin
  FConflict := AConflict;
  FPill := APill;
  FPillText := APillText;
  FBorder := ABorder;
  FEditMine.Invalidate;
  FEditBase.Invalidate;
  FEditTheirs.Invalidate;
end;

procedure TGittanMergeView.SetKinds(AMine, ATheirs, ABase, AMarker, AFiller, AHeader: integer);
begin
  FKindMine := AMine;
  FKindTheirs := ATheirs;
  FKindBase := ABase;
  FKindMarker := AMarker;
  FKindFiller := AFiller;
  FKindHeader := AHeader;
end;

procedure TGittanMergeView.SetTexts(const AMine, ATheirs, ABase, AResult, AHeader, AEdited,
  AResolved, ANoLines: string);
begin
  FNoLinesText := ANoLines;
  FMineTitle := AMine;
  FTheirsTitle := ATheirs;
  FBaseTitle := ABase;
  FResultTitle := AResult;
  FHeaderText := AHeader;
  FEditedText := AEdited;
  FResolvedText := AResolved;
  UpdateCaptions;
end;

procedure TGittanMergeView.Restyle(AFrom: TATSynEdit; AScrollTheme: PATScrollbarTheme);
var
  Ed: TATSynEdit;
begin
  for Ed in [FEditMine, FEditBase, FEditTheirs, FEditResult] do
  begin
    Ed.Font.Assign(AFrom.Font);
    Ed.OptScaleFont := AFrom.OptScaleFont;
    Ed.OptTabSize := AFrom.OptTabSize;
    Ed.OnCalcBookmarkColor := AFrom.OnCalcBookmarkColor;
    if AScrollTheme <> nil then
    begin
      Ed.ScrollbarVert.Theme := AScrollTheme;
      Ed.ScrollbarHorz.Theme := AScrollTheme;
      Ed.ScrollbarVert.Update;
      Ed.ScrollbarHorz.Update;
    end;
    Ed.Update(True);
  end;
  FMineCap.Font.Assign(Font);
  FBaseCap.Font.Assign(Font);
  FTheirsCap.Font.Assign(Font);
  FResultCap.Font.Assign(Font);
end;

procedure TGittanMergeView.SetLexer(ALexer: TecSyntAnalyzer);
var
  Ed: TATSynEdit;
begin
  FAdapterMine.Lexer := ALexer;
  FAdapterBase.Lexer := ALexer;
  FAdapterTheirs.Lexer := ALexer;
  FAdapterResult.Lexer := ALexer;
  { Assigning a lexer parses nothing yet; a change from line 0 starts
    the adapter's parse. }
  for Ed in [FEditMine, FEditBase, FEditTheirs, FEditResult] do
  begin
    if ALexer <> nil then
      Ed.DoEventChange(0);
    Ed.Update;
  end;
end;

function TGittanMergeView.GetLexer: TecSyntAnalyzer;
begin
  Result := FAdapterResult.Lexer;
end;

procedure TGittanMergeView.Resize;
begin
  inherited Resize;
  FTop.Height := Max(Px(80), Round(ClientHeight * FTopRatio));
  FMinePanel.Width := Max(Px(80), Round(FTop.ClientWidth * FSideRatio));
  if FBasePanel.Visible then
    FBasePanel.Width := Max(Px(80), Round(FTop.ClientWidth * FBaseRatio));
end;

procedure TGittanMergeView.SplitterMoved(Sender: TObject);
begin
  if ClientHeight > 0 then
    FTopRatio := FTop.Height / ClientHeight;
  if FTop.ClientWidth > 0 then
  begin
    FSideRatio := FMinePanel.Width / FTop.ClientWidth;
    if FBasePanel.Visible then
      FBaseRatio := FBasePanel.Width / FTop.ClientWidth;
  end;
end;

{ Whether the base pane is up: asked for, and the merge has a base. }
function TGittanMergeView.BaseShown: boolean;
begin
  Result := FShowBase and (FMerge <> nil) and FMerge.HasBase;
end;

function TGittanMergeView.HasBase: boolean;
begin
  Result := (FMerge <> nil) and FMerge.HasBase;
end;

{ Shows or hides the base pane and its splitter, and shares the width
  out again: three panes get a third each, two a half, unless the first
  splitter was moved to a width that still fits. }
procedure TGittanMergeView.LayoutBase;
var
  Shown: boolean;
begin
  Shown := BaseShown;
  if Shown = FBasePanel.Visible then
    Exit;
  FBasePanel.Visible := Shown;
  FBaseSplitter.Visible := Shown;
  if Shown then
  begin
    if FSideRatio > 0.4 then
    begin
      FSideRatio := 1 / 3;
      FBaseRatio := 1 / 3;
    end;
  end
  else if FSideRatio < 0.4 then
    FSideRatio := 0.5;
  Resize;
end;

procedure TGittanMergeView.SetShowBase(AValue: boolean);
var
  TopRow: integer;
begin
  if AValue = FShowBase then
    Exit;
  FShowBase := AValue;
  if FMerge = nil then
    Exit;
  { The rows change their padding with the base; the panes stay on the
    same chunk, as close as the new rows allow. }
  TopRow := FEditMine.LineTop;
  FillPanes;
  FEditMine.LineTop := Min(TopRow, Max(0, High(FRows)));
  FEditMine.Update;
  EditScroll(FEditMine);
end;

{ A read-only ATSynEdit ignores Text, so the mode is lifted for the
  load; the wrap info is rebuilt in full, as ShowText in umain does. }
procedure TGittanMergeView.SetText(AEd: TATSynEdit; const AText: string);
var
  RO: boolean;
  i: integer;
begin
  RO := AEd.ModeReadOnly;
  AEd.BookmarkDeleteAll_2;
  AEd.ModeReadOnly := False;
  AEd.Text := UTF8Decode(AText);
  AEd.WrapInfo.Clear;
  AEd.Strings.WrapStructInvalidate;
  AEd.Update(True);
  AEd.ModeReadOnly := RO;
  AEd.Modified := False;
  for i := 0 to AEd.Strings.Count - 1 do
    AEd.Strings.LinesState[i] := TATLineState.None;
end;

function JoinLines(const ALines: TStringArray): string;
var
  B: TStringBuilder;
  i: integer;
begin
  B := TStringBuilder.Create;
  try
    for i := 0 to High(ALines) do
    begin
      if i > 0 then
        B.Append(#10);
      B.Append(ALines[i]);
    end;
    Result := B.ToString;
  finally
    B.Free;
  end;
end;

procedure TGittanMergeView.FillSide(AEd: TATSynEdit; ASide: TGittanMergeSide);
var
  Lines: TStringArray;
  i, Index, Kind: integer;
  Chunk: TGittanMergeChunk;
begin
  Lines := nil;
  SetLength(Lines, Length(FRows));
  for i := 0 to High(FRows) do
  begin
    Chunk := FMerge.Chunks[FRows[i].Chunk];
    if FRows[i].Header then
      Lines[i] := ''
    else if not Chunk.Conflict then
      Lines[i] := Chunk.Lines[FRows[i].Line]
    else
    begin
      if ASide = msMine then
        Index := FRows[i].Mine
      else
        Index := FRows[i].Theirs;
      if Index >= 0 then
        Lines[i] := Chunk.Sides[ASide][Index]
      else
        Lines[i] := '';
    end;
  end;
  SetText(AEd, JoinLines(Lines));
  if ASide = msMine then
    Kind := FKindMine
  else
    Kind := FKindTheirs;
  for i := 0 to High(FRows) do
  begin
    if not FMerge.Chunks[FRows[i].Chunk].Conflict then
      Continue;
    if FRows[i].Header then
      AEd.BookmarkSetForLine_2(i, FKindHeader, '', TATBookmarkAutoDelete.DontDelete, False, 0)
    else if ((ASide = msMine) and (FRows[i].Mine >= 0)) or
      ((ASide = msTheirs) and (FRows[i].Theirs >= 0)) then
      AEd.BookmarkSetForLine_2(i, Kind, '', TATBookmarkAutoDelete.DontDelete, False, 0)
    else
      AEd.BookmarkSetForLine_2(i, FKindFiller, '', TATBookmarkAutoDelete.DontDelete, False, 0);
  end;
  AEd.Update;
end;

{ The base pane: the base's lines of each conflict on its rows, with
  no boxes to tick, since the base goes into the result by neither
  side. }
procedure TGittanMergeView.FillBase;
var
  Lines: TStringArray;
  i: integer;
  Chunk: TGittanMergeChunk;
begin
  Lines := nil;
  SetLength(Lines, Length(FRows));
  for i := 0 to High(FRows) do
  begin
    Chunk := FMerge.Chunks[FRows[i].Chunk];
    if FRows[i].Header then
      Lines[i] := ''
    else if not Chunk.Conflict then
      Lines[i] := Chunk.Lines[FRows[i].Line]
    else if FRows[i].Base >= 0 then
      Lines[i] := Chunk.Base[FRows[i].Base]
    else
      Lines[i] := '';
  end;
  SetText(FEditBase, JoinLines(Lines));
  for i := 0 to High(FRows) do
  begin
    if not FMerge.Chunks[FRows[i].Chunk].Conflict then
      Continue;
    if FRows[i].Header then
      FEditBase.BookmarkSetForLine_2(i, FKindHeader, '', TATBookmarkAutoDelete.DontDelete, False, 0)
    else if FRows[i].Base >= 0 then
      FEditBase.BookmarkSetForLine_2(i, FKindBase, '', TATBookmarkAutoDelete.DontDelete, False, 0)
    else
      FEditBase.BookmarkSetForLine_2(i, FKindFiller, '', TATBookmarkAutoDelete.DontDelete, False, 0);
  end;
  FEditBase.Update;
end;

{ The rows for the panes above, with the base when it is shown, and the
  panes filled from them. }
procedure TGittanMergeView.FillPanes;
begin
  FRows := FMerge.Rows(BaseShown);
  LayoutBase;
  FillSide(FEditMine, msMine);
  FillSide(FEditTheirs, msTheirs);
  if BaseShown then
    FillBase
  else
    SetText(FEditBase, '');
end;

{ The result from the ticks; AKeepTop keeps the pane where it was. }
procedure TGittanMergeView.FillResult(AKeepTop: boolean);
var
  Origins: TIntegerDynArray;
  i, TopRow, Kind: integer;
begin
  TopRow := FEditResult.LineTop;
  FFilling := True;
  try
    SetText(FEditResult, JoinLines(FMerge.Output));
    FEdited := False;
  finally
    FFilling := False;
  end;
  FStarts := FMerge.OutputStarts;
  Origins := FMerge.Origins;
  for i := 0 to Min(High(Origins), FEditResult.Strings.Count - 1) do
  begin
    case Origins[i] of
      moMine: Kind := FKindMine;
      moTheirs: Kind := FKindTheirs;
      moConflict: Kind := FKindMarker;
      else
        Continue;
    end;
    FEditResult.BookmarkSetForLine_2(i, Kind, '', TATBookmarkAutoDelete.DontDelete, False, 0);
  end;
  if AKeepTop then
    FEditResult.LineTop := TopRow
  else
    EditScroll(FEditMine);
  FEditResult.Update;
  UpdateCaptions;
end;

procedure TGittanMergeView.Load(AMerge: TGittanMerge);
begin
  FreeAndNil(FMerge);
  FMerge := AMerge;
  FillPanes;
  FEditMine.LineTop := 0;
  FEditBase.LineTop := 0;
  FEditTheirs.LineTop := 0;
  FEditResult.DoCaretSingle(0, 0);
  FillResult(False);
  FEditResult.LineTop := 0;
end;

procedure TGittanMergeView.Clear;
begin
  FreeAndNil(FMerge);
  FRows := nil;
  FStarts := nil;
  FEdited := False;
  FFilling := True;
  try
    SetText(FEditMine, '');
    SetText(FEditBase, '');
    SetText(FEditTheirs, '');
    SetText(FEditResult, '');
  finally
    FFilling := False;
  end;
  LayoutBase;
end;

function TGittanMergeView.ResultLines: TStringArray;
var
  i: integer;
begin
  Result := nil;
  SetLength(Result, FEditResult.Strings.Count);
  for i := 0 to FEditResult.Strings.Count - 1 do
    Result[i] := UTF8Encode(FEditResult.Strings.Lines[i]);
  { The editor holds one empty line for an empty text. }
  if (Length(Result) = 1) and (Result[0] = '') then
    Result := nil;
end;

procedure TGittanMergeView.ResetResult;
begin
  if FMerge <> nil then
    FillResult(True);
end;

procedure TGittanMergeView.PickEverywhere(ASide: TGittanMergeSide);
begin
  if (FMerge = nil) or FEdited then
    Exit;
  FMerge.PickEverywhere(ASide);
  FEditMine.Invalidate;
  FEditTheirs.Invalidate;
  FillResult(False);
  if Assigned(FOnPicked) then
    FOnPicked(Self);
end;

procedure TGittanMergeView.ResultChange(Sender: TObject);
begin
  if FFilling or FEdited then
    Exit;
  FEdited := True;
  FEditMine.Invalidate;
  FEditTheirs.Invalidate;
  UpdateCaptions;
  if Assigned(FOnEdited) then
    FOnEdited(Self);
end;

function TGittanMergeView.ConflictNumber(AChunk: integer): integer;
var
  c: integer;
begin
  Result := 0;
  if FMerge = nil then
    Exit;
  for c := 0 to Min(AChunk, FMerge.ChunkCount - 1) do
    if FMerge.Chunks[c].Conflict then
      Inc(Result);
end;

procedure TGittanMergeView.UpdateCaptions;
var
  Mine, Theirs, Base, Detail: string;
  c, Count: integer;
begin
  Mine := '';
  Theirs := '';
  Base := '';
  Count := 0;
  if FMerge <> nil then
  begin
    for c := 0 to FMerge.ChunkCount - 1 do
      if FMerge.Chunks[c].Conflict then
      begin
        Inc(Count);
        if Mine = '' then
          Mine := FMerge.Chunks[c].Names[msMine];
        if Theirs = '' then
          Theirs := FMerge.Chunks[c].Names[msTheirs];
        if Base = '' then
          Base := FMerge.Chunks[c].BaseName;
      end;
  end;
  FMineCap.SetText(FMineTitle, Mine);
  FBaseCap.SetText(FBaseTitle, Base);
  FTheirsCap.SetText(FTheirsTitle, Theirs);
  if FEdited then
    Detail := FEditedText
  else if FMerge <> nil then
    Detail := Format(FResolvedText, [FMerge.ResolvedCount, Count])
  else
    Detail := '';
  FResultCap.SetText(FResultTitle, Detail);
end;

function TGittanMergeView.SideOf(AEd: TATSynEdit): TGittanMergeSide;
begin
  if AEd = FEditTheirs then
    Result := msTheirs
  else
    Result := msMine;
end;

function TGittanMergeView.BandRect(AEd: TATSynEdit): TRect;
var
  Band: integer;
begin
  Band := AEd.Gutter.FindIndexByTag(gutterTagPick);
  if Band < 0 then
    Exit(Rect(0, 0, 0, 0));
  Result := Rect(AEd.Gutter[Band].Left, AEd.RectMain.Top, AEd.Gutter[Band].Right,
    AEd.RectMain.Bottom);
end;

{ A tick on row ARow of a pane above: a line of a conflict ticks or
  drops that line, the header the whole side. Off while the result is
  edited by hand, which a new result would overwrite. }
procedure TGittanMergeView.Toggle(AEd: TATSynEdit; ARow: integer);
var
  Side: TGittanMergeSide;
  Row: TGittanMergeRow;
  Index: integer;
begin
  if (FMerge = nil) or FEdited or (AEd = FEditBase) or (ARow < 0) or (ARow > High(FRows)) then
    Exit;
  Row := FRows[ARow];
  if not FMerge.Chunks[Row.Chunk].Conflict then
    Exit;
  Side := SideOf(AEd);
  if Row.Header then
    FMerge.PickAll(Row.Chunk, Side, FMerge.PickState(Row.Chunk, Side) <> psAll)
  else
  begin
    if Side = msMine then
      Index := Row.Mine
    else
      Index := Row.Theirs;
    if Index < 0 then
      Exit;
    FMerge.Pick(Row.Chunk, Side, Index, not FMerge.Chunks[Row.Chunk].Picked[Side][Index]);
  end;
  FEditMine.Invalidate;
  FEditTheirs.Invalidate;
  FillResult(True);
  EditScroll(AEd);
  if Assigned(FOnPicked) then
    FOnPicked(Self);
end;

procedure TGittanMergeView.EditClickGutter(Sender: TObject; ABand, ALine: integer;
  var AHandled: boolean);
var
  Ed: TATSynEdit;
begin
  Ed := TATSynEdit(Sender);
  if (ABand < 0) or (Ed.Gutter[ABand].Tag <> gutterTagPick) then
    Exit;
  AHandled := True;
  Toggle(Ed, ALine);
end;

{ A click anywhere on a header row takes or drops the side, as its box
  does. }
procedure TGittanMergeView.EditMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
var
  Ed: TATSynEdit;
  P: TPoint;
  Details: TATEditorPosDetails;
begin
  Ed := TATSynEdit(Sender);
  if (Button <> mbLeft) or (X < Ed.RectMain.Left) or (FMerge = nil) then
    Exit;
  P := Ed.ClientPosToCaretPos(ATPoint(X, Y), Details);
  if (P.Y < 0) or Details.BelowAllText or (P.Y > High(FRows)) or not FRows[P.Y].Header then
    Exit;
  Toggle(Ed, P.Y);
end;

{ The two panes above keep the same top row; the result shows the line
  the chunk at their top starts on, as far into it as they are, while
  it holds the ticks' result. }
procedure TGittanMergeView.EditScroll(Sender: TObject);
var
  Src, Other: TATSynEdit;
  TopRow, Line, Offset, i: integer;
  Row: TGittanMergeRow;
begin
  if FSyncing or (FMerge = nil) then
    Exit;
  Src := TATSynEdit(Sender);
  FSyncing := True;
  try
    TopRow := Src.LineTop;
    for Other in [FEditMine, FEditBase, FEditTheirs] do
      if (Other <> Src) and Other.Visible and (Other.LineTop <> TopRow) then
      begin
        Other.LineTop := TopRow;
        Other.Update;
      end;
    if FEdited or (TopRow < 0) or (TopRow > High(FRows)) then
      Exit;
    Row := FRows[TopRow];
    Line := FStarts[Row.Chunk];
    if not FMerge.Chunks[Row.Chunk].Conflict then
      Inc(Line, Row.Line)
    else if FMerge.Resolved(Row.Chunk) then
    begin
      { The rows of the conflict above the top, past its header. }
      Offset := 0;
      i := TopRow - 1;
      while (i >= 0) and (FRows[i].Chunk = Row.Chunk) and not FRows[i].Header do
      begin
        Inc(Offset);
        Dec(i);
      end;
      if Row.Chunk < High(FStarts) then
        Offset := Min(Offset, Max(0, FStarts[Row.Chunk + 1] - Line - 1));
      Inc(Line, Offset);
    end;
    if FEditResult.LineTop <> Line then
    begin
      FEditResult.LineTop := Line;
      FEditResult.Update;
    end;
  finally
    FSyncing := False;
  end;
end;

function TGittanMergeView.CurrentConflict: integer;
var
  TopRow: integer;
begin
  Result := -1;
  if FMerge = nil then
    Exit;
  TopRow := FEditMine.LineTop;
  if (TopRow >= 0) and (TopRow <= High(FRows)) then
    Result := ConflictNumber(FRows[TopRow].Chunk) - 1;
end;

function TGittanMergeView.GoToConflict(ANext: boolean): boolean;
var
  TopRow, i: integer;
begin
  Result := False;
  if FMerge = nil then
    Exit;
  TopRow := FEditMine.LineTop;
  if (FGoneRow >= 0) and (FGoneRow <= High(FRows)) and FRows[FGoneRow].Header and
    (TopRow = FGoneTop) then
    TopRow := FGoneRow;
  i := -1;
  if ANext then
  begin
    for i := TopRow + 1 to High(FRows) do
      if FRows[i].Header then
        Break;
    if (i > High(FRows)) or not FRows[i].Header then
      Exit;
  end
  else
  begin
    for i := TopRow - 1 downto 0 do
      if FRows[i].Header then
        Break;
    if (i < 0) or not FRows[i].Header then
      Exit;
  end;
  ShowConflictRow(i);
  Result := True;
end;

function TGittanMergeView.GoToEdgeConflict(AFirst: boolean): boolean;
var
  i: integer;
begin
  Result := False;
  if FMerge = nil then
    Exit;
  if AFirst then
  begin
    for i := 0 to High(FRows) do
      if FRows[i].Header then
      begin
        ShowConflictRow(i);
        Exit(True);
      end;
  end
  else
    for i := High(FRows) downto 0 do
      if FRows[i].Header then
      begin
        ShowConflictRow(i);
        Exit(True);
      end;
end;

{ A line of the chunk before stays in view above the header. }
procedure TGittanMergeView.ShowConflictRow(ARow: integer);
begin
  FEditMine.LineTop := Max(0, ARow - 2);
  FEditMine.Update;
  EditScroll(FEditMine);
  FGoneRow := ARow;
  FGoneTop := FEditMine.LineTop;
end;

{ A conflict's header row, painted over the empty line the editor drew
  for it, the way the change view paints a run of hidden lines: a fork
  (two branches into one) in the conflict's color, the title in the
  window's font a size under the editor's, the side's name as a pill
  and, for a side without lines, a note saying so in the dim color. The
  row's tint is its bookmark kind's. The editor's font is put back. }
procedure TGittanMergeView.DrawHeader(AEd: TATSynEdit; C: TCanvas; ATop: integer;
  const ATitle, AName: string; AEmpty: boolean);
var
  CharH, TextH, TextY, X, Cx, Cy, R, PadX, PillH, W, Right: integer;
begin
  CharH := AEd.TextCharSize.Y;
  C.Font.Assign(Font);
  C.Font.Style := [];
  if AEd.OptScaleFont > 0 then
    C.Font.Size := Max(8, AEd.Font.Size * AEd.OptScaleFont div 100 - 1)
  else
    C.Font.Size := Max(8, ATEditorScaleFont(AEd.Font.Size) - 1);
  TextH := C.TextHeight('Xg');
  while (TextH + Px(2) > CharH) and (C.Font.Size > 8) do
  begin
    C.Font.Size := C.Font.Size - 1;
    TextH := C.TextHeight('Xg');
  end;
  TextY := ATop + (CharH - TextH) div 2;
  Right := AEd.RectMain.Right - Px(6);
  X := AEd.RectMain.Left + Max(Px(6), CharH div 2);
  Cx := X + CharH div 2;
  Cy := ATop + CharH div 2;
  R := Max(3, (CharH - 6) div 2);
  C.Pen.Style := psSolid;
  C.Pen.Width := Max(1, R div 3);
  C.Pen.Color := FConflict;
  C.Line(Cx - R, Cy - R, Cx, Cy);
  C.Line(Cx + R, Cy - R, Cx, Cy);
  C.Line(Cx, Cy, Cx, Cy + R + 1);
  C.Pen.Width := 1;
  Inc(X, CharH + Px(4));
  C.Brush.Style := bsClear;
  C.Font.Color := FText;
  C.TextOut(X, TextY, ATitle);
  Inc(X, C.TextWidth(ATitle) + Px(8));
  if AName <> '' then
  begin
    PillH := Min(CharH - Px(2), TextH + Px(4));
    PadX := Max(Px(6), PillH div 2);
    W := C.TextWidth(AName) + 2 * PadX;
    if X + W <= Right then
    begin
      C.Pen.Color := FBorder;
      C.Brush.Style := bsSolid;
      C.Brush.Color := FPill;
      C.RoundRect(X, ATop + (CharH - PillH) div 2, X + W, ATop + (CharH - PillH) div 2 + PillH,
        PillH, PillH);
      C.Brush.Style := bsClear;
      C.Font.Color := FPillText;
      C.TextOut(X + PadX, TextY, AName);
      Inc(X, W + Px(8));
    end;
  end;
  if AEmpty and (X + C.TextWidth(FNoLinesText) <= Right) then
  begin
    C.Font.Color := FDim;
    C.TextOut(X, TextY, FNoLinesText);
  end;
  C.Font.Assign(AEd.Font);
  C.Brush.Style := bsSolid;
end;

{ The band's boxes: on a header row one for the side as a whole (a dash
  when some of its lines are ticked), on each line of a conflict one
  for the line; dimmed while the result is edited by hand. The header
  rows carry their title too: the conflict's number and the name git
  wrote for the side. }
procedure TGittanMergeView.EditDraw(Sender: TObject; C: TCanvas; const ARect: TRect);
var
  Ed: TATSynEdit;
  Band: TRect;
  W, Row, Y, CharH, S, Cx, Cy, Index, Count: integer;
  Item: TATWrapItem;
  Side: TGittanMergeSide;
  Chunk: TGittanMergeChunk;
  State: TGittanPickState;
  Box: TRect;
  Title: string;
  Ink: TColor;
  IsBase: boolean;

  procedure DrawBox(AState: TGittanPickState);
  begin
    Box := Rect(Cx - S div 2, Cy - S div 2, Cx - S div 2 + S, Cy - S div 2 + S);
    C.Pen.Style := psSolid;
    C.Pen.Width := 1;
    if AState = psNone then
    begin
      C.Brush.Style := bsClear;
      C.Pen.Color := Ink;
      C.Rectangle(Box);
      Exit;
    end;
    C.Brush.Style := bsSolid;
    if FEdited then
      C.Brush.Color := FDim
    else
      C.Brush.Color := FAccent;
    C.Pen.Color := C.Brush.Color;
    C.RoundRect(Box, Px(3), Px(3));
    C.Pen.Color := clWhite;
    C.Pen.Width := Max(2, S div 7);
    if AState = psAll then
    begin
      C.Line(Box.Left + S div 5, Cy, Cx - S div 10, Box.Bottom - S div 4);
      C.Line(Cx - S div 10, Box.Bottom - S div 4, Box.Right - S div 5, Box.Top + S div 4);
    end
    else
      C.Line(Box.Left + S div 4, Cy, Box.Right - S div 4, Cy);
    C.Pen.Width := 1;
  end;

begin
  Ed := TATSynEdit(Sender);
  if (FMerge = nil) or (Ed = FEditResult) then
    Exit;
  Band := BandRect(Ed);
  if Band.Right <= Band.Left then
    Exit;
  IsBase := Ed = FEditBase;
  Side := SideOf(Ed);
  CharH := Ed.TextCharSize.Y;
  S := Max(Px(9), Min(Px(14), CharH - Px(4)));
  if FEdited then
    Ink := FDim
  else
    Ink := FText;
  Count := ConflictNumber(MaxInt);
  C.Clipping := True;
  C.ClipRect := Rect(Band.Left, Ed.RectMain.Top, Ed.RectMain.Right, Ed.RectMain.Bottom);
  try
    W := Ed.WrapInfo.FindIndexOfLineNumber(Ed.LineTop);
    while (W >= 0) and (W < Ed.WrapInfo.Count) do
    begin
      Item := Ed.WrapInfo[W];
      Inc(W);
      if not Item.bInitial then
        Continue;
      Row := Item.NLineIndex;
      Y := Ed.CaretPosToClientPos(Point(0, Row)).Y;
      if Y >= Ed.RectMain.Bottom then
        Break;
      if (Row < 0) or (Row > High(FRows)) then
        Continue;
      Chunk := FMerge.Chunks[FRows[Row].Chunk];
      if not Chunk.Conflict then
        Continue;
      Cx := (Band.Left + Band.Right) div 2;
      Cy := Y + CharH div 2;
      { The bar down the band's left edge, the conflict's color from
        its header to its last row. }
      C.Pen.Style := psClear;
      C.Brush.Style := bsSolid;
      C.Brush.Color := FConflict;
      C.FillRect(Band.Left + 1, Y, Band.Left + 4, Y + CharH);
      if FRows[Row].Header then
      begin
        Title := Format(FHeaderText, [ConflictNumber(FRows[Row].Chunk), Count]);
        { The base's header names what git wrote after its marker, and
          has no box: the base is picked from neither side. }
        if IsBase then
        begin
          if Chunk.BaseName <> '' then
            DrawHeader(Ed, C, Y, Title, Chunk.BaseName, Length(Chunk.Base) = 0)
          else
            DrawHeader(Ed, C, Y, Title, FBaseTitle, Length(Chunk.Base) = 0);
        end
        else
        begin
          State := FMerge.PickState(FRows[Row].Chunk, Side);
          DrawBox(State);
          DrawHeader(Ed, C, Y, Title, Chunk.Names[Side], Length(Chunk.Sides[Side]) = 0);
        end;
        Continue;
      end;
      if IsBase then
        Continue;
      if Side = msMine then
        Index := FRows[Row].Mine
      else
        Index := FRows[Row].Theirs;
      if Index < 0 then
        Continue;
      if Chunk.Taken[Side] and Chunk.Picked[Side][Index] then
        DrawBox(psAll)
      else
        DrawBox(psNone);
    end;
  finally
    C.Clipping := False;
    C.Pen.Width := 1;
    C.Pen.Style := psSolid;
    C.Brush.Style := bsSolid;
  end;
end;

end.
