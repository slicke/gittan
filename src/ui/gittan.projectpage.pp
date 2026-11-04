unit gittan.projectpage;

{** The Project page: what the repository is as a project (gittan.project)
  in the box the summary shares, painted like the Repository and
  Commands pages. One section per kind of project found at the root:
  the kind's name, the file that told it and the project's own version
  as the heading, with how many dependencies changed since the last
  tag at its right; then the dependencies as rows, the name (a link to
  the package on its registry), what the manifest asks for, what the
  lock file resolved it to, and at the right end what changed since
  the tag (added, removed, or the old version → the new), the plain
  ones first and each group (Development, Build, ...) under its own
  subheading; then the checks worth a warning, each with Add to
  .gitignore when a pattern would settle it. The page keeps no
  repository of its own: the frame hands it the reports
  (umain.project.inc). See spec/project-page.md. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, gittan.project, gittan.manifest;

type
  {** A click that carries a text: the address to open. }
  TGittanProjectTextEvent = procedure(Sender: TObject; const AText: string) of object;
  {** Add to .gitignore clicked on a check. }
  TGittanProjectCheckEvent = procedure(Sender: TObject;
    const ACheck: TGittanProjectCheck) of object;

  { TGittanProjectPage }

  TGittanProjectPage = class(TCustomControl)
  private
    FName, FRoot: string;
    FReports: TGittanProjectReports;
    FBack, FText, FDim, FHover, FLine, FLink, FOk, FWarn, FErrorColor, FCard: TColor;
    FLinkRects: array of TRect;
    FLinkUrls: array of string;
    FLinkHints: array of string;
    FHot: integer;
    FContentHeight: integer;
    { The report being painted, for the checks' links. }
    FReportIndex: integer;
    { The canvas the content is painted on: the control's in Paint, a
      measuring one in Layout. }
    FC: TCanvas;
    FOnOpenUrl: TGittanProjectTextEvent;
    FOnIgnore: TGittanProjectCheckEvent;
    function LinkAt(X, Y: integer): integer;
    procedure SetHot(AValue: integer);
    procedure AddLink(const ARect: TRect; const AUrl: string; const AHint: string = '');
    procedure PaintHeading(var Y: integer; const ATitle, ADetail, AState: string;
      AStateColor: TColor);
    procedure PaintSubheading(var Y: integer; const ATitle: string);
    procedure PaintNote(var Y: integer; const AText: string);
    procedure PaintDependencies(var Y: integer; const AReport: TGittanProjectReport);
    procedure PaintRows(var Y: integer; const AReport: TGittanProjectReport;
      const AIndexes: array of integer; const ARemoved: array of integer;
      ANameW, AVersionW: integer);
    procedure PaintChecks(var Y: integer; const AReport: TGittanProjectReport);
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
      drops the reports. }
    procedure SetRepository(const AName, ARoot: string);
    {** The reports, one section each, in this order. }
    procedure SetReports(const AReports: TGittanProjectReports);
    {** The palette: the background, the text, the dim text, the fill
      under the mouse, the dividers, the links (and a changed
      version), the ok state (added), the warning state (the checks)
      and the error state (removed). }
    procedure SetColors(ABack, AText, ADim, AHover, ALine, ALink, AOk, AWarn, AError: TColor);
    {** The fill of the checks' card. }
    procedure SetCardColor(ACard: TColor);
    {** Makes the control at least AMin high (the height of the box it
      sits in, so its background covers the box), and no higher than
      its content needs beyond that. }
    procedure FitHeight(AMin: integer);
    {** The root the reports are for. }
    property Root: string read FRoot;
    {** A dependency's name clicked: the package's page. }
    property OnOpenUrl: TGittanProjectTextEvent read FOnOpenUrl write FOnOpenUrl;
    {** Add to .gitignore clicked on a check: its pattern goes in, and
      the files it is about leave the index. }
    property OnIgnore: TGittanProjectCheckEvent read FOnIgnore write FOnIgnore;
  end;

{** How the page names a dependency group: Development for dev, and
  so on; a group of another name as it is, with a capital. }
function GroupTitle(const AGroup: string): string;

implementation

uses
  Math, LCLIntf, LCLType, gittan.textfit, gittan.theme;

resourcestring
  rsPageTitle = 'Project';
  rsNoProject = 'No project files recognized at the root. Gittan looks for a Cargo.toml, ' +
    'go.mod, package.json, pyproject.toml, setup.py, requirements.txt or a Lazarus .lpi, and ' +
    'a line "project = rust" in .gittan/commands.ini names the kind when the files do not.';
  rsNoDependencies = 'No dependencies in %s.';
  rsNoDependencyFile = 'No dependency list to read for this kind.';
  rsChangesSince = '%d changed since %s';
  rsOneChangeSince = '1 changed since %s';
  rsNoChangesSince = 'no changes since %s';
  rsAdded = 'added';
  rsRemoved = 'removed';
  rsChecks = 'Checks';
  rsIgnore = 'Add to .gitignore';
  rsIgnoreHint = 'Writes %s to .gitignore and stops tracking the files it matches; they ' +
    'stay on disk';
  rsChangedHint = '%s was %s at %s';
  rsAddedHint = '%s is new since %s';
  rsRemovedHint = '%s was %s at %s and is gone';
  rsGroupDev = 'Development';
  rsGroupBuild = 'Build';
  rsGroupPeer = 'Peer';
  rsGroupOptional = 'Optional';
  rsGroupIndirect = 'Indirect';
  rsDependencies = '%d dependencies';
  rsOneDependency = '1 dependency';

const
  UrlLink = 'url:';
  IgnoreLink = 'ignore:';
  Pad = 24;
  Gap = 12;
  TitleFontSize = 20;
  { A dependency's row: the padding above and below its text, the gap
    between its columns, and the most of the width the name and the
    version asked for may take. }
  RowPadY = 3;
  ColGap = 18;
  NameShare = 0.4;
  VersionShare = 0.2;
  { The checks' card: its padding, its corner radius, the warning
    mark's size and the gap after it. }
  CardPad = 14;
  CardRadius = 12;
  MarkSize = 8;
  MarkGap = 10;

function GroupTitle(const AGroup: string): string;
begin
  if AGroup = 'dev' then
    Result := rsGroupDev
  else if AGroup = 'build' then
    Result := rsGroupBuild
  else if AGroup = 'peer' then
    Result := rsGroupPeer
  else if AGroup = 'optional' then
    Result := rsGroupOptional
  else if AGroup = 'indirect' then
    Result := rsGroupIndirect
  else if AGroup = '' then
    Result := ''
  else
    Result := UpperCase(Copy(AGroup, 1, 1)) + Copy(AGroup, 2, MaxInt);
end;

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
    FReports := nil;
  FName := AName;
  FRoot := ARoot;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanProjectPage.SetReports(const AReports: TGittanProjectReports);
var
  i: integer;
begin
  SetLength(FReports, Length(AReports));
  for i := 0 to High(AReports) do
    FReports[i] := AReports[i];
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

{ The content painted on the measuring canvas, for its height; the
  height is set here, never in Paint. }
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
  for i := 0 to High(FLinkRects) do
    if PtInRect(FLinkRects[i], Point(X, Y)) then
      Exit(i);
  Result := -1;
end;

procedure TGittanProjectPage.SetHot(AValue: integer);
begin
  if FHot = AValue then
    Exit;
  FHot := AValue;
  if (AValue < 0) or (FLinkUrls[AValue] = '') then
    Cursor := crDefault
  else
    Cursor := crHandPoint;
  if AValue >= 0 then
    Hint := FLinkHints[AValue]
  else
    Hint := '';
  Invalidate;
end;

procedure TGittanProjectPage.AddLink(const ARect: TRect; const AUrl: string;
  const AHint: string);
begin
  SetLength(FLinkRects, Length(FLinkRects) + 1);
  SetLength(FLinkUrls, Length(FLinkUrls) + 1);
  SetLength(FLinkHints, Length(FLinkHints) + 1);
  FLinkRects[High(FLinkRects)] := ARect;
  FLinkUrls[High(FLinkUrls)] := AUrl;
  FLinkHints[High(FLinkHints)] := AHint;
end;

{ A dim bold title with a dim detail after it and, after that, a state
  in its own color at the right end, over a divider. }
procedure TGittanProjectPage.PaintHeading(var Y: integer; const ATitle, ADetail,
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
    FC.TextOut(Max(X, Width - Px(Pad) - FC.TextWidth(AState)), Y,
      FitTextRight(FC, AState, Max(0, Width - Px(Pad) - X)));
  end;
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

{ The change of the dependency AName in AGroup since the tag, or
  nil-like: AKind unset and false. }
function ChangeOf(const AReport: TGittanProjectReport; const AName, AGroup: string;
  out AChange: TGittanDependencyChange): boolean;
var
  i: integer;
begin
  for i := 0 to High(AReport.Changes) do
    if (AReport.Changes[i].Name = AName) and (AReport.Changes[i].Group = AGroup) then
    begin
      AChange := AReport.Changes[i];
      Exit(True);
    end;
  Result := False;
end;

{ The rows of the dependencies at AIndexes and, after them, the removed
  ones at ARemoved (indexes into the report's changes): the name as a
  link, the version asked for, the version resolved, and the change at
  the right end. }
procedure TGittanProjectPage.PaintRows(var Y: integer; const AReport: TGittanProjectReport;
  const AIndexes: array of integer; const ARemoved: array of integer;
  ANameW, AVersionW: integer);
var
  TextH, RowH, i, X, Right: integer;
  D: TGittanDependency;
  Ch: TGittanDependencyChange;
  Url, Note, NoteHint: string;
  NoteColor: TColor;
  R: TRect;
  Kind: TGittanProjectKindClass;

  procedure Row(const AName, AVersion, AResolved: string; ADimName: boolean);
  var
    NameShown: string;
  begin
    FC.Font := Font;
    FC.Brush.Style := bsClear;
    X := Px(Pad);
    Right := Width - Px(Pad);
    { The note at the right end first, so the columns stop before it. }
    if Note <> '' then
    begin
      FC.Font.Color := NoteColor;
      FC.TextOut(Right - FC.TextWidth(Note), Y + Px(RowPadY), Note);
      R := Rect(Right - FC.TextWidth(Note), Y, Right, Y + RowH);
      if NoteHint <> '' then
        AddLink(R, '', NoteHint);
      Right := Right - FC.TextWidth(Note) - Px(ColGap);
    end;
    FC.Font.Style := [fsBold];
    if ADimName then
      FC.Font.Color := FDim
    else
      FC.Font.Color := FText;
    NameShown := FitTextRight(FC, AName, ANameW);
    if (Url <> '') and not ADimName then
    begin
      R := Rect(X, Y, X + FC.TextWidth(NameShown), Y + RowH);
      AddLink(R, UrlLink + Url, Url);
      if FHot = High(FLinkRects) then
      begin
        FC.Font.Color := FLink;
        FC.Font.Style := [fsBold, fsUnderline];
      end;
    end;
    FC.TextOut(X, Y + Px(RowPadY), NameShown);
    FC.Font.Style := [];
    Inc(X, ANameW + Px(ColGap));
    FC.Font.Color := FDim;
    if AVersion <> '' then
      FC.TextOut(X, Y + Px(RowPadY), FitTextRight(FC, AVersion, AVersionW));
    Inc(X, AVersionW + Px(ColGap));
    FC.Font.Color := FText;
    if (AResolved <> '') and (X < Right) then
      FC.TextOut(X, Y + Px(RowPadY), FitTextRight(FC, AResolved, Right - X));
    Inc(Y, RowH);
  end;

begin
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  RowH := TextH + 2 * Px(RowPadY);
  Kind := ProjectKindByName(AReport.Name);
  for i := 0 to High(AIndexes) do
  begin
    D := AReport.Dependencies[AIndexes[i]];
    if Kind <> nil then
      Url := Kind.PackageUrl(D.Name)
    else
      Url := '';
    Note := '';
    NoteHint := '';
    NoteColor := FDim;
    if ChangeOf(AReport, D.Name, D.Group, Ch) then
      case Ch.Kind of
        dcAdded:
        begin
          Note := rsAdded;
          NoteColor := FOk;
          NoteHint := Format(rsAddedHint, [D.Name, AReport.Since]);
        end;
        dcChanged:
        begin
          Note := Ch.OldVersion + ' → ' + Ch.NewVersion;
          NoteColor := FLink;
          NoteHint := Format(rsChangedHint, [D.Name, Ch.OldVersion, AReport.Since]);
        end;
        dcRemoved: ;
      end;
    { The resolved version has its column when the lock file gave one
      that differs from what is asked for (go.mod asks for the exact
      version); else what is asked for stands alone. }
    if (D.Resolved <> '') and (D.Resolved <> D.Version) then
      Row(D.Name, D.Version, D.Resolved, False)
    else
      Row(D.Name, D.Version, '', False);
  end;
  for i := 0 to High(ARemoved) do
  begin
    Ch := AReport.Changes[ARemoved[i]];
    Url := '';
    Note := rsRemoved;
    NoteColor := FErrorColor;
    NoteHint := Format(rsRemovedHint, [Ch.Name, Ch.OldVersion, AReport.Since]);
    Row(Ch.Name, Ch.OldVersion, '', True);
  end;
end;

{ The dependencies of a report by group: the plain ones first under no
  heading, then each group under its title, the removed ones of a group
  at its end. }
procedure TGittanProjectPage.PaintDependencies(var Y: integer;
  const AReport: TGittanProjectReport);
var
  Groups: array of string;
  i, g, NameW, VersionW, Inner: integer;
  Indexes, Removed: array of integer;

  function GroupIndex(const AGroup: string): integer;
  var
    k: integer;
  begin
    for k := 0 to High(Groups) do
      if Groups[k] = AGroup then
        Exit(k);
    SetLength(Groups, Length(Groups) + 1);
    Groups[High(Groups)] := AGroup;
    Result := High(Groups);
  end;

begin
  if AReport.DependencyFile = '' then
  begin
    PaintNote(Y, rsNoDependencyFile);
    Exit;
  end;
  if (Length(AReport.Dependencies) = 0) and (Length(AReport.Changes) = 0) then
  begin
    PaintNote(Y, Format(rsNoDependencies, [AReport.DependencyFile]));
    Exit;
  end;
  { The columns: as wide as the widest name and version, within their
    share of the width. }
  FC.Font := Font;
  FC.Font.Style := [fsBold];
  NameW := 0;
  for i := 0 to High(AReport.Dependencies) do
    NameW := Max(NameW, FC.TextWidth(AReport.Dependencies[i].Name));
  for i := 0 to High(AReport.Changes) do
    if AReport.Changes[i].Kind = dcRemoved then
      NameW := Max(NameW, FC.TextWidth(AReport.Changes[i].Name));
  FC.Font.Style := [];
  VersionW := 0;
  for i := 0 to High(AReport.Dependencies) do
    VersionW := Max(VersionW, FC.TextWidth(AReport.Dependencies[i].Version));
  for i := 0 to High(AReport.Changes) do
    if AReport.Changes[i].Kind = dcRemoved then
      VersionW := Max(VersionW, FC.TextWidth(AReport.Changes[i].OldVersion));
  Inner := Width - 2 * Px(Pad);
  NameW := Min(NameW, Round(Inner * NameShare));
  VersionW := Min(VersionW, Round(Inner * VersionShare));
  { The groups in the order they first come, the plain one first. }
  Groups := nil;
  GroupIndex('');
  for i := 0 to High(AReport.Dependencies) do
    GroupIndex(AReport.Dependencies[i].Group);
  for i := 0 to High(AReport.Changes) do
    if AReport.Changes[i].Kind = dcRemoved then
      GroupIndex(AReport.Changes[i].Group);
  for g := 0 to High(Groups) do
  begin
    Indexes := nil;
    Removed := nil;
    for i := 0 to High(AReport.Dependencies) do
      if AReport.Dependencies[i].Group = Groups[g] then
      begin
        SetLength(Indexes, Length(Indexes) + 1);
        Indexes[High(Indexes)] := i;
      end;
    for i := 0 to High(AReport.Changes) do
      if (AReport.Changes[i].Kind = dcRemoved) and (AReport.Changes[i].Group = Groups[g]) then
      begin
        SetLength(Removed, Length(Removed) + 1);
        Removed[High(Removed)] := i;
      end;
    if (Length(Indexes) = 0) and (Length(Removed) = 0) then
      Continue;
    if Groups[g] <> '' then
      PaintSubheading(Y, GroupTitle(Groups[g]))
    else
      Inc(Y, Px(Gap) div 2);
    PaintRows(Y, AReport, Indexes, Removed, NameW, VersionW);
  end;
end;

{ The checks in a card: a warning mark, the text wrapped, and Add to
  .gitignore at the right when a pattern would settle it. }
procedure TGittanProjectPage.PaintChecks(var Y: integer; const AReport: TGittanProjectReport);
var
  i, TextH, CardTop, LinkW, TextRight, MarkY: integer;
  R, L: TRect;
  Style: TTextStyle;
  Tops, Bottoms: array of integer;
begin
  if Length(AReport.Checks) = 0 then
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
  SetLength(Tops, Length(AReport.Checks));
  SetLength(Bottoms, Length(AReport.Checks));
  Y := CardTop + Px(CardPad);
  for i := 0 to High(AReport.Checks) do
  begin
    Tops[i] := Y;
    TextRight := Width - Px(Pad) - Px(CardPad);
    if AReport.Checks[i].IgnorePattern <> '' then
      TextRight := TextRight - LinkW - Px(ColGap);
    R := Rect(Px(Pad) + Px(CardPad) + Px(MarkSize) + Px(MarkGap), Y, TextRight, Y);
    DrawText(FC.Handle, PChar(AReport.Checks[i].Text), Length(AReport.Checks[i].Text), R,
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
  for i := 0 to High(AReport.Checks) do
  begin
    { The mark: a disc in the warning color. }
    MarkY := Tops[i] + (TextH - Px(MarkSize)) div 2;
    FC.Pen.Style := psClear;
    FC.Brush.Style := bsSolid;
    FC.Brush.Color := FWarn;
    FC.Ellipse(Px(Pad) + Px(CardPad), MarkY, Px(Pad) + Px(CardPad) + Px(MarkSize) + 1,
      MarkY + Px(MarkSize) + 1);
    FC.Pen.Style := psSolid;
    FC.Brush.Style := bsClear;
    TextRight := Width - Px(Pad) - Px(CardPad);
    if AReport.Checks[i].IgnorePattern <> '' then
    begin
      L := Rect(TextRight - LinkW, Tops[i], TextRight, Tops[i] + TextH);
      { The link names the check by its section and index, so the
        click finds the record. }
      AddLink(L, IgnoreLink + IntToStr(FReportIndex) + ':' + IntToStr(i),
        Format(rsIgnoreHint, [AReport.Checks[i].IgnorePattern]));
      FC.Font.Color := FLink;
      if FHot = High(FLinkRects) then
        FC.Font.Style := [fsUnderline];
      FC.TextOut(L.Left, L.Top, rsIgnore);
      FC.Font.Style := [];
      TextRight := TextRight - LinkW - Px(ColGap);
    end;
    FC.Font.Color := FText;
    R := Rect(Px(Pad) + Px(CardPad) + Px(MarkSize) + Px(MarkGap), Tops[i], TextRight, Bottoms[i]);
    FC.TextRect(R, R.Left, R.Top, AReport.Checks[i].Text, Style);
  end;
  Inc(Y, Px(Gap) div 2);
end;

procedure TGittanProjectPage.Paint;
begin
  FC := Canvas;
  PaintContent;
end;

procedure TGittanProjectPage.PaintContent;
var
  Y, TextH, TitleH, X, i, n: integer;
  Detail, State: string;
  StateColor: TColor;
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

  { The name, "Project" after it, the root under them. }
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

  if Length(FReports) = 0 then
  begin
    Inc(Y, Px(Pad));
    PaintNote(Y, rsNoProject);
  end;
  for i := 0 to High(FReports) do
  begin
    Detail := FReports[i].Manifest;
    if FReports[i].Version <> '' then
      Detail := Detail + ' · ' + FReports[i].Version;
    n := Length(FReports[i].Dependencies);
    if n = 1 then
      Detail := Detail + ' · ' + rsOneDependency
    else if n > 1 then
      Detail := Detail + ' · ' + Format(rsDependencies, [n]);
    State := '';
    StateColor := FDim;
    if FReports[i].Since <> '' then
    begin
      n := Length(FReports[i].Changes);
      if n = 0 then
        State := Format(rsNoChangesSince, [FReports[i].Since])
      else
      begin
        if n = 1 then
          State := Format(rsOneChangeSince, [FReports[i].Since])
        else
          State := Format(rsChangesSince, [n, FReports[i].Since]);
        StateColor := FLink;
      end;
    end;
    PaintHeading(Y, FReports[i].Name, Detail, State, StateColor);
    PaintDependencies(Y, FReports[i]);
    FReportIndex := i;
    PaintChecks(Y, FReports[i]);
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
  i, r, c: integer;
  Parts: TStringArray;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  i := LinkAt(X, Y);
  if i < 0 then
    Exit;
  if Copy(FLinkUrls[i], 1, Length(UrlLink)) = UrlLink then
  begin
    if Assigned(FOnOpenUrl) then
      FOnOpenUrl(Self, Copy(FLinkUrls[i], Length(UrlLink) + 1, MaxInt));
  end
  else if Copy(FLinkUrls[i], 1, Length(IgnoreLink)) = IgnoreLink then
  begin
    Parts := Copy(FLinkUrls[i], Length(IgnoreLink) + 1, MaxInt).Split([':']);
    if Assigned(FOnIgnore) and (Length(Parts) = 2) then
    begin
      r := StrToIntDef(Parts[0], -1);
      c := StrToIntDef(Parts[1], -1);
      if (r >= 0) and (r <= High(FReports)) and (c >= 0) and (c <= High(FReports[r].Checks)) then
        FOnIgnore(Self, FReports[r].Checks[c]);
    end;
  end;
end;

end.
