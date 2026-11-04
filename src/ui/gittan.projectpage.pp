unit gittan.projectpage;

{** The Project page: what the repository is as a project, in the box
  the summary shares, painted like the Repository and Commands pages.
  It knows no kind of project: each driver (src/proj) builds its own
  section of gittan.project's model, and the page paints whatever
  blocks it is given. A section is a heading (the kind's name, a detail,
  a state at the right end) over its blocks: facts (a dim label and a
  value per row, with a button after it when the driver gives one), a
  table (column headers when it has them, subheading rows, the last
  column at the right end when it asks), the checks in a card with Add
  to .gitignore, or a dim note. A cell with a Url is a link, one with a
  Command a button that runs it, and its Hint is the tooltip.

  At the right of the title, a chip names the kinds shown, and says
  whether the files told them or the user picked them; a click asks
  the frame for the list to pick from (OnPickKinds). The page keeps no
  repository of its own: the frame hands it the sections
  (umain.project.inc). See spec/project-page.md. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, gittan.project;

type
  {** A click that carries a text: the address to open. }
  TGittanProjectTextEvent = procedure(Sender: TObject; const AText: string) of object;
  {** Add to .gitignore clicked on a check. }
  TGittanProjectCheckEvent = procedure(Sender: TObject;
    const ACheck: TGittanProjectCheck) of object;
  {** A button clicked: the command's name and its shell line. }
  TGittanProjectRunEvent = procedure(Sender: TObject; const AName, ACommand: string) of object;
  {** The kinds' chip clicked, with its rectangle on the screen. }
  TGittanProjectAnchorEvent = procedure(Sender: TObject; const AScreenRect: TRect) of object;

  { TGittanProjectPage }

  TGittanProjectPage = class(TCustomControl)
  private type
    TLinkKind = (lkHint, lkUrl, lkRun, lkIgnore, lkKinds);
    TLink = record
      Rect: TRect;
      Kind: TLinkKind;
      Text, Command, Hint: string;
      Check: TGittanProjectCheck;
    end;
  private
    FName, FRoot, FKinds: string;
    FPicked: boolean;
    FSections: TGittanProjectSections;
    FBack, FText, FDim, FHover, FLine, FLink, FOk, FWarn, FErrorColor, FCard: TColor;
    FLinks: array of TLink;
    FHot: integer;
    FContentHeight: integer;
    { The canvas the content is painted on: the control's in Paint, a
      measuring one in Layout. }
    FC: TCanvas;
    FOnOpenUrl: TGittanProjectTextEvent;
    FOnIgnore: TGittanProjectCheckEvent;
    FOnRunCommand: TGittanProjectRunEvent;
    FOnPickKinds: TGittanProjectAnchorEvent;
    function LinkAt(X, Y: integer): integer;
    procedure SetHot(AValue: integer);
    function AddLink(const ARect: TRect; AKind: TLinkKind; const AText: string;
      const ACommand: string = ''; const AHint: string = ''): integer;
    function StyleColor(AStyle: TGittanProjectStyle): TColor;
    procedure PaintHeading(var Y: integer; const ATitle, ADetail, AState: string;
      AStateColor: TColor);
    procedure PaintSubheading(var Y: integer; const ATitle: string);
    procedure PaintNote(var Y: integer; const AText: string);
    function CellWidth(const ACell: TGittanProjectCell): integer;
    procedure PaintCell(const ACell: TGittanProjectCell; X, Y, AWidth, ARowH: integer);
    procedure PaintFacts(var Y: integer; const ABlock: TGittanProjectBlock);
    procedure PaintTable(var Y: integer; const ABlock: TGittanProjectBlock);
    procedure PaintChecks(var Y: integer; const AChecks: TGittanProjectChecks);
    procedure PaintKindsChip(ATop, ATitleH: integer);
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
      drops the sections. }
    procedure SetRepository(const AName, ARoot: string);
    {** The sections, in this order; AKinds names the kinds for the chip
      and APicked says the user picked them. }
    procedure SetSections(const ASections: TGittanProjectSections; const AKinds: string;
      APicked: boolean);
    {** The palette: the background, the text, the dim text, the fill
      under the mouse, the dividers, the links (and a changed version),
      the ok state, the warning state and the error state. }
    procedure SetColors(ABack, AText, ADim, AHover, ALine, ALink, AOk, AWarn, AError: TColor);
    {** The fill of the checks' card, the buttons and the chip. }
    procedure SetCardColor(ACard: TColor);
    {** Makes the control at least AMin high (the height of the box it
      sits in, so its background covers the box), and no higher than
      its content needs beyond that. }
    procedure FitHeight(AMin: integer);
    {** The root the sections are for. }
    property Root: string read FRoot;
    property OnOpenUrl: TGittanProjectTextEvent read FOnOpenUrl write FOnOpenUrl;
    {** Add to .gitignore clicked on a check: its pattern goes in, and
      the files it is about leave the index. }
    property OnIgnore: TGittanProjectCheckEvent read FOnIgnore write FOnIgnore;
    property OnRunCommand: TGittanProjectRunEvent read FOnRunCommand write FOnRunCommand;
    property OnPickKinds: TGittanProjectAnchorEvent read FOnPickKinds write FOnPickKinds;
  end;

implementation

uses
  Math, LCLIntf, LCLType, gittan.textfit, gittan.theme;

resourcestring
  rsPageTitle = 'Project';
  rsNoProject = 'No kind of project is shown. Gittan looks for a .lpi, package.json, ' +
    'Cargo.toml, go.mod, pyproject.toml, setup.py or requirements.txt at the root; pick a kind ' +
    'with the button at the top right when the files do not tell it.';
  rsChecks = 'Checks';
  rsIgnore = 'Add to .gitignore';
  rsIgnoreHint = 'Writes %s to .gitignore and stops tracking the files it matches; they ' +
    'stay on disk';
  rsNoKinds = 'No kind';
  rsKindsPicked = 'Picked: %s';
  rsKindsFound = 'Found: %s';
  rsKindsHint = 'The kinds of project this page shows. Pick them yourself when the files do ' +
    'not tell it, or tell it wrong.';

const
  Pad = 24;
  Gap = 12;
  TitleFontSize = 20;
  { A row: the padding above and below its text, the gap between
    columns, and the most of the width one column may take. }
  RowPadY = 3;
  ColGap = 18;
  MaxColShare = 0.45;
  { A button in a cell, and the chip. }
  ButtonPadX = 10;
  ButtonPadY = 1;
  ButtonRadius = 10;
  ChipPadX = 10;
  ChipPadY = 3;
  { The checks' card: its padding, its corner radius, the warning
    mark's size and the gap after it. }
  CardPad = 14;
  CardRadius = 12;
  MarkSize = 8;
  MarkGap = 10;

{ TGittanProjectPage }

constructor TGittanProjectPage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FHot := -1;
  Align := alTop;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnShadow, clHighlight,
    clGreen, clOlive, clRed);
  FCard := clBtnFace;
  ShowHint := True;
end;

procedure TGittanProjectPage.SetRepository(const AName, ARoot: string);
begin
  if FRoot <> ARoot then
    FSections := nil;
  FName := AName;
  FRoot := ARoot;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanProjectPage.SetSections(const ASections: TGittanProjectSections;
  const AKinds: string; APicked: boolean);
begin
  FSections := Copy(ASections);
  FKinds := AKinds;
  FPicked := APicked;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanProjectPage.SetColors(ABack, AText, ADim, AHover, ALine, ALink, AOk, AWarn,
  AError: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
  FLine := ALine;
  FLink := ALink;
  FOk := AOk;
  FWarn := AWarn;
  FErrorColor := AError;
  Color := ABack;
  Invalidate;
end;

procedure TGittanProjectPage.SetCardColor(ACard: TColor);
begin
  FCard := ACard;
  Invalidate;
end;

procedure TGittanProjectPage.FitHeight(AMin: integer);
begin
  Constraints.MinHeight := AMin;
  Layout;
end;

procedure TGittanProjectPage.Layout;
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

procedure TGittanProjectPage.Resize;
begin
  inherited Resize;
  Layout;
end;

function TGittanProjectPage.LinkAt(X, Y: integer): integer;
var
  i: integer;
begin
  for i := 0 to High(FLinks) do
    if PtInRect(FLinks[i].Rect, Point(X, Y)) then
      Exit(i);
  Result := -1;
end;

procedure TGittanProjectPage.SetHot(AValue: integer);
begin
  if FHot = AValue then
    Exit;
  FHot := AValue;
  if (AValue < 0) or (FLinks[AValue].Kind = lkHint) then
    Cursor := crDefault
  else
    Cursor := crHandPoint;
  if AValue >= 0 then
    Hint := FLinks[AValue].Hint
  else
    Hint := '';
  Invalidate;
end;

function TGittanProjectPage.AddLink(const ARect: TRect; AKind: TLinkKind; const AText: string;
  const ACommand: string; const AHint: string): integer;
begin
  SetLength(FLinks, Length(FLinks) + 1);
  Result := High(FLinks);
  FLinks[Result] := Default(TLink);
  FLinks[Result].Rect := ARect;
  FLinks[Result].Kind := AKind;
  FLinks[Result].Text := AText;
  FLinks[Result].Command := ACommand;
  FLinks[Result].Hint := AHint;
end;

function TGittanProjectPage.StyleColor(AStyle: TGittanProjectStyle): TColor;
begin
  case AStyle of
    psDim: Result := FDim;
    psLink: Result := FLink;
    psOk: Result := FOk;
    psWarn: Result := FWarn;
    psError: Result := FErrorColor;
    else
      Result := FText;
  end;
end;

{ A dim bold title with a dim detail after it and a state in its own
  color at the right end, over a divider. }
procedure TGittanProjectPage.PaintHeading(var Y: integer; const ATitle, ADetail,
  AState: string; AStateColor: TColor);
var
  TextH, X, StateW: integer;
begin
  Inc(Y, Px(Pad));
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  StateW := 0;
  if AState <> '' then
  begin
    StateW := FC.TextWidth(AState);
    FC.Font.Color := AStateColor;
    FC.TextOut(Width - Px(Pad) - StateW, Y, AState);
    StateW := StateW + Px(Gap);
  end;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FDim;
  FC.TextOut(Px(Pad), Y, ATitle);
  X := Px(Pad) + FC.TextWidth(ATitle) + Px(Gap) div 2;
  FC.Font.Style := [];
  if ADetail <> '' then
    FC.TextOut(X, Y, FitTextRight(FC, ADetail, Max(0, Width - Px(Pad) - StateW - X)));
  Inc(Y, TextH + Px(Gap) div 2);
  FC.Pen.Style := psSolid;
  FC.Pen.Color := FLine;
  FC.Line(Px(Pad), Y, Width - Px(Pad), Y);
  Inc(Y, Px(Gap) div 2);
end;

procedure TGittanProjectPage.PaintSubheading(var Y: integer; const ATitle: string);
begin
  Inc(Y, Px(Gap));
  FC.Font := Font;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  FC.Brush.Style := bsClear;
  FC.TextOut(Px(Pad), Y, FitTextRight(FC, ATitle, Width - 2 * Px(Pad)));
  Inc(Y, FC.TextHeight('Xg') + Px(Gap) div 2);
end;

{ A dim paragraph, wrapped to the width. }
procedure TGittanProjectPage.PaintNote(var Y: integer; const AText: string);
var
  R: TRect;
  Style: TTextStyle;
begin
  Inc(Y, Px(Gap) div 2);
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

{ The width ACell's text needs: bold for a strong one, a button's
  padding. }
function TGittanProjectPage.CellWidth(const ACell: TGittanProjectCell): integer;
begin
  FC.Font := Font;
  if ACell.Style = psStrong then
    FC.Font.Style := [fsBold];
  Result := FC.TextWidth(ACell.Text);
  if ACell.Style = psButton then
    Inc(Result, 2 * Px(ButtonPadX));
  FC.Font.Style := [];
end;

{ ACell at X on the row at Y, within AWidth: a link, a button or text,
  with its hint as the tooltip. }
procedure TGittanProjectPage.PaintCell(const ACell: TGittanProjectCell; X, Y, AWidth,
  ARowH: integer);
var
  Shown: string;
  R: TRect;
  i, TextH: integer;
begin
  if (ACell.Text = '') or (AWidth <= 0) then
    Exit;
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  if ACell.Style = psButton then
  begin
    R := Rect(X, Y + (ARowH - TextH - 2 * Px(ButtonPadY)) div 2, X + Min(AWidth,
      CellWidth(ACell)), 0);
    R.Bottom := R.Top + TextH + 2 * Px(ButtonPadY);
    i := AddLink(R, lkRun, ACell.CommandName, ACell.Command, ACell.Hint);
    FC.Pen.Style := psClear;
    FC.Brush.Style := bsSolid;
    if FHot = i then
      FC.Brush.Color := FLink
    else
      FC.Brush.Color := FCard;
    FC.RoundRect(R, Px(ButtonRadius), Px(ButtonRadius));
    FC.Pen.Style := psSolid;
    FC.Brush.Style := bsClear;
    if FHot = i then
      FC.Font.Color := FBack
    else
      FC.Font.Color := FLink;
    FC.TextOut(R.Left + Px(ButtonPadX), R.Top + Px(ButtonPadY),
      FitTextRight(FC, ACell.Text, R.Right - R.Left - 2 * Px(ButtonPadX)));
    Exit;
  end;
  if ACell.Style = psStrong then
    FC.Font.Style := [fsBold];
  FC.Font.Color := StyleColor(ACell.Style);
  Shown := FitTextRight(FC, ACell.Text, AWidth);
  R := Rect(X, Y, X + FC.TextWidth(Shown), Y + ARowH);
  i := -1;
  if ACell.Url <> '' then
    i := AddLink(R, lkUrl, ACell.Url, '', ACell.Hint)
  else if (ACell.Hint <> '') or (Shown <> ACell.Text) then
  begin
    { A cut text has the whole as its hint. }
    if ACell.Hint = '' then
      AddLink(R, lkHint, '', '', ACell.Text)
    else if Shown <> ACell.Text then
      AddLink(R, lkHint, '', '', ACell.Text + LineEnding + ACell.Hint)
    else
      AddLink(R, lkHint, '', '', ACell.Hint);
  end;
  if (i >= 0) and (FHot = i) then
  begin
    FC.Font.Color := FLink;
    FC.Font.Style := FC.Font.Style + [fsUnderline];
  end;
  FC.TextOut(X, Y + Px(RowPadY), Shown);
  FC.Font.Style := [];
end;

{ Facts: the labels in a column as wide as the widest, the value after
  it, and any further cell (a button) after the value. }
procedure TGittanProjectPage.PaintFacts(var Y: integer; const ABlock: TGittanProjectBlock);
var
  LabelW, RowH, i, k, X, W: integer;
  Row: TGittanProjectRow;
begin
  FC.Font := Font;
  RowH := FC.TextHeight('Xg') + 2 * Px(RowPadY);
  LabelW := 0;
  for i := 0 to High(ABlock.Rows) do
    if Length(ABlock.Rows[i].Cells) > 0 then
      LabelW := Max(LabelW, CellWidth(ABlock.Rows[i].Cells[0]));
  LabelW := Min(LabelW, Round((Width - 2 * Px(Pad)) * MaxColShare));
  Inc(Y, Px(Gap) div 2);
  for i := 0 to High(ABlock.Rows) do
  begin
    Row := ABlock.Rows[i];
    if Row.Heading <> '' then
    begin
      PaintSubheading(Y, Row.Heading);
      Continue;
    end;
    X := Px(Pad);
    for k := 0 to High(Row.Cells) do
    begin
      if k = 0 then
        W := LabelW
      else
        W := Min(CellWidth(Row.Cells[k]), Width - Px(Pad) - X);
      PaintCell(Row.Cells[k], X, Y, W, RowH);
      Inc(X, W + Px(ColGap));
      if X >= Width - Px(Pad) then
        Break;
    end;
    Inc(Y, RowH);
  end;
end;

{ A table: each column as wide as its widest cell (within MaxColShare
  of the width), the last at the right end when the block asks, the
  headers dimmed over the rows when it has them. }
procedure TGittanProjectPage.PaintTable(var Y: integer; const ABlock: TGittanProjectBlock);
var
  Widths: array of integer;
  n, i, k, X, RowH, Avail, Total, Last, W: integer;
  Row: TGittanProjectRow;
begin
  FC.Font := Font;
  RowH := FC.TextHeight('Xg') + 2 * Px(RowPadY);
  n := Length(ABlock.Columns);
  for i := 0 to High(ABlock.Rows) do
    n := Max(n, Length(ABlock.Rows[i].Cells));
  if n = 0 then
    Exit;
  SetLength(Widths, n);
  for k := 0 to n - 1 do
  begin
    Widths[k] := 0;
    if k < Length(ABlock.Columns) then
      Widths[k] := FC.TextWidth(ABlock.Columns[k]);
  end;
  for i := 0 to High(ABlock.Rows) do
    for k := 0 to High(ABlock.Rows[i].Cells) do
      Widths[k] := Max(Widths[k], CellWidth(ABlock.Rows[i].Cells[k]));
  Avail := Width - 2 * Px(Pad);
  for k := 0 to n - 1 do
    Widths[k] := Min(Widths[k], Round(Avail * MaxColShare));
  { Too wide together: the widest gives way until they fit. }
  Total := 0;
  for k := 0 to n - 1 do
    Inc(Total, Widths[k]);
  Inc(Total, (n - 1) * Px(ColGap));
  while Total > Avail do
  begin
    Last := 0;
    for k := 1 to n - 1 do
      if Widths[k] > Widths[Last] then
        Last := k;
    W := Min(Widths[Last] - Px(ColGap), Total - Avail);
    if W <= 0 then
      Break;
    Dec(Widths[Last], W);
    Dec(Total, W);
  end;
  Inc(Y, Px(Gap) div 2);
  { The headers. }
  if Length(ABlock.Columns) > 0 then
  begin
    X := Px(Pad);
    FC.Font := Font;
    FC.Font.Color := FDim;
    FC.Brush.Style := bsClear;
    for k := 0 to n - 1 do
    begin
      if (k < Length(ABlock.Columns)) and (ABlock.Columns[k] <> '') then
        if ABlock.RightLast and (k = n - 1) then
          FC.TextOut(Width - Px(Pad) - FC.TextWidth(ABlock.Columns[k]), Y + Px(RowPadY),
            ABlock.Columns[k])
        else
          FC.TextOut(X, Y + Px(RowPadY), FitTextRight(FC, ABlock.Columns[k], Widths[k]));
      Inc(X, Widths[k] + Px(ColGap));
    end;
    Inc(Y, RowH);
    FC.Pen.Color := FLine;
    FC.Line(Px(Pad), Y - 1, Width - Px(Pad), Y - 1);
  end;
  for i := 0 to High(ABlock.Rows) do
  begin
    Row := ABlock.Rows[i];
    if Row.Heading <> '' then
    begin
      PaintSubheading(Y, Row.Heading);
      Continue;
    end;
    X := Px(Pad);
    for k := 0 to High(Row.Cells) do
    begin
      if ABlock.RightLast and (k = n - 1) then
        PaintCell(Row.Cells[k], Width - Px(Pad) - Min(Widths[k], CellWidth(Row.Cells[k])), Y,
          Widths[k], RowH)
      else
        PaintCell(Row.Cells[k], X, Y, Widths[k], RowH);
      Inc(X, Widths[k] + Px(ColGap));
    end;
    Inc(Y, RowH);
  end;
end;

{ The checks in a card: a warning mark, the text wrapped, and Add to
  .gitignore at the right when a pattern would settle it. }
procedure TGittanProjectPage.PaintChecks(var Y: integer; const AChecks: TGittanProjectChecks);
var
  i, TextH, CardTop, LinkW, TextRight, MarkY, L: integer;
  R, LR: TRect;
  Style: TTextStyle;
  Tops, Bottoms: array of integer;
begin
  if Length(AChecks) = 0 then
    Exit;
  PaintSubheading(Y, rsChecks);
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  LinkW := FC.TextWidth(rsIgnore);
  Style := FC.TextStyle;
  Style.Wordbreak := True;
  Style.SingleLine := False;
  Style.Alignment := taLeftJustify;
  Style.Layout := tlTop;
  { Measure every row first, then the card behind them, then the
    rows. }
  CardTop := Y;
  SetLength(Tops, Length(AChecks));
  SetLength(Bottoms, Length(AChecks));
  Y := CardTop + Px(CardPad);
  for i := 0 to High(AChecks) do
  begin
    Tops[i] := Y;
    TextRight := Width - Px(Pad) - Px(CardPad);
    if AChecks[i].IgnorePattern <> '' then
      TextRight := TextRight - LinkW - Px(ColGap);
    R := Rect(Px(Pad) + Px(CardPad) + Px(MarkSize) + Px(MarkGap), Y, TextRight, Y);
    DrawText(FC.Handle, PChar(AChecks[i].Text), Length(AChecks[i].Text), R,
      DT_CALCRECT or DT_WORDBREAK);
    Bottoms[i] := Max(R.Bottom, Y + TextH);
    Y := Bottoms[i] + Px(Gap) div 2;
  end;
  Y := Y - Px(Gap) div 2 + Px(CardPad);
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FCard;
  FC.RoundRect(Px(Pad), CardTop, Width - Px(Pad), Y, Px(CardRadius), Px(CardRadius));
  FC.Pen.Style := psSolid;
  for i := 0 to High(AChecks) do
  begin
    MarkY := Tops[i] + (TextH - Px(MarkSize)) div 2;
    FC.Pen.Style := psClear;
    FC.Brush.Style := bsSolid;
    FC.Brush.Color := FWarn;
    FC.Ellipse(Px(Pad) + Px(CardPad), MarkY, Px(Pad) + Px(CardPad) + Px(MarkSize) + 1,
      MarkY + Px(MarkSize) + 1);
    FC.Pen.Style := psSolid;
    FC.Brush.Style := bsClear;
    TextRight := Width - Px(Pad) - Px(CardPad);
    if AChecks[i].IgnorePattern <> '' then
    begin
      LR := Rect(TextRight - LinkW, Tops[i], TextRight, Tops[i] + TextH);
      L := AddLink(LR, lkIgnore, AChecks[i].IgnorePattern, '',
        Format(rsIgnoreHint, [AChecks[i].IgnorePattern]));
      FLinks[L].Check := AChecks[i];
      FC.Font.Color := FLink;
      if FHot = L then
        FC.Font.Style := [fsUnderline];
      FC.TextOut(LR.Left, LR.Top, rsIgnore);
      FC.Font.Style := [];
      TextRight := TextRight - LinkW - Px(ColGap);
    end;
    FC.Font.Color := FText;
    R := Rect(Px(Pad) + Px(CardPad) + Px(MarkSize) + Px(MarkGap), Tops[i], TextRight, Bottoms[i]);
    FC.TextRect(R, R.Left, R.Top, AChecks[i].Text, Style);
  end;
  Inc(Y, Px(Gap) div 2);
end;

{ The chip at the right of the title line: what kinds are shown and
  whether they were picked, a caret after it. }
procedure TGittanProjectPage.PaintKindsChip(ATop, ATitleH: integer);
var
  ChipText: string;
  R: TRect;
  TextH, W, i, Mid: integer;
begin
  if not Assigned(FOnPickKinds) then
    Exit;
  if FKinds = '' then
    ChipText := rsNoKinds
  else if FPicked then
    ChipText := Format(rsKindsPicked, [FKinds])
  else
    ChipText := Format(rsKindsFound, [FKinds]);
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  W := FC.TextWidth(ChipText) + 2 * Px(ChipPadX) + Px(10);
  W := Min(W, (Width - 2 * Px(Pad)) div 2);
  R := Rect(Width - Px(Pad) - W, ATop + (ATitleH - TextH) div 2 - Px(ChipPadY), Width - Px(Pad),
    0);
  R.Bottom := R.Top + TextH + 2 * Px(ChipPadY);
  i := AddLink(R, lkKinds, '', '', rsKindsHint);
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  if FHot = i then
    FC.Brush.Color := FHover
  else
    FC.Brush.Color := FCard;
  FC.RoundRect(R, Px(ButtonRadius) * 2, Px(ButtonRadius) * 2);
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;
  if FPicked then
    FC.Font.Color := FLink
  else
    FC.Font.Color := FText;
  FC.TextOut(R.Left + Px(ChipPadX), R.Top + Px(ChipPadY),
    FitTextRight(FC, ChipText, W - 2 * Px(ChipPadX) - Px(10)));
  { The caret: a small chevron down. }
  Mid := R.Top + (R.Bottom - R.Top) div 2;
  FC.Pen.Color := FDim;
  FC.Line(R.Right - Px(ChipPadX) - Px(6), Mid - Px(2), R.Right - Px(ChipPadX) - Px(3), Mid + Px(1));
  FC.Line(R.Right - Px(ChipPadX) - Px(3), Mid + Px(1), R.Right - Px(ChipPadX), Mid - Px(2));
end;

procedure TGittanProjectPage.Paint;
begin
  FC := Canvas;
  PaintContent;
end;

procedure TGittanProjectPage.PaintContent;
var
  Y, TextH, TitleH, X, i, b: integer;
begin
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FBack;
  FC.FillRect(Rect(0, 0, Width, Height));
  FLinks := nil;
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  Y := Px(Pad);

  { The name, "Project" after it, the chip at the right, the root
    under them. }
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
  PaintKindsChip(Y, TitleH);
  Inc(Y, TitleH + 2);
  FC.Font := Font;
  FC.Font.Color := FDim;
  FC.Brush.Style := bsClear;
  FC.TextOut(Px(Pad), Y, FitTextLeft(FC, FRoot, Width - 2 * Px(Pad)));
  Inc(Y, TextH);

  if Length(FSections) = 0 then
  begin
    Inc(Y, Px(Pad));
    PaintNote(Y, rsNoProject);
  end;
  for i := 0 to High(FSections) do
  begin
    PaintHeading(Y, FSections[i].Name, FSections[i].Detail, FSections[i].State,
      StyleColor(FSections[i].StateStyle));
    for b := 0 to High(FSections[i].Blocks) do
    begin
      if FSections[i].Blocks[b].Kind = pbChecks then
      begin
        PaintChecks(Y, FSections[i].Blocks[b].Checks);
        Continue;
      end;
      if FSections[i].Blocks[b].Title <> '' then
        PaintSubheading(Y, FSections[i].Blocks[b].Title);
      case FSections[i].Blocks[b].Kind of
        pbFacts: PaintFacts(Y, FSections[i].Blocks[b]);
        pbTable: PaintTable(Y, FSections[i].Blocks[b]);
        pbNote: PaintNote(Y, FSections[i].Blocks[b].Text);
        else ;
      end;
    end;
  end;

  FContentHeight := Y + Px(Pad);
end;

procedure TGittanProjectPage.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(LinkAt(X, Y));
end;

procedure TGittanProjectPage.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1);
end;

procedure TGittanProjectPage.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  i: integer;
  R: TRect;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  i := LinkAt(X, Y);
  if i < 0 then
    Exit;
  case FLinks[i].Kind of
    lkUrl:
      if Assigned(FOnOpenUrl) then
        FOnOpenUrl(Self, FLinks[i].Text);
    lkRun:
      if Assigned(FOnRunCommand) then
        FOnRunCommand(Self, FLinks[i].Text, FLinks[i].Command);
    lkIgnore:
      if Assigned(FOnIgnore) then
        FOnIgnore(Self, FLinks[i].Check);
    lkKinds:
      if Assigned(FOnPickKinds) then
      begin
        R := FLinks[i].Rect;
        R.TopLeft := ClientToScreen(R.TopLeft);
        R.BottomRight := ClientToScreen(R.BottomRight);
        FOnPickKinds(Self, R);
      end;
    else ;
  end;
end;

end.
