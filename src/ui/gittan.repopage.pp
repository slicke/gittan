unit gittan.repopage;

{** The Repository page: what Gittan shows about the repository itself,
  beside the summary of its changes. Under the name and the path it
  The name comes with the branch after it, as the summary's header has
  it, and what the branch tracks; the path under them. Then the facts
  gittan.repoinfo gathers: tiles, each a count large with its name over
  it and a detail under it (the commits with the dates of the first and
  the latest, the local and remote branches, the tags with the newest,
  the tracked files, the submodules and the size of the objects), the
  composition of the tracked files (all of them and their lines, then
  code, tests and documentation with a bar of their share), the
  remotes with a globe for a web address, which is a link, and Edit
  Remotes... at the right of the heading, and the authors with the most
  commits, each with a disc of their initials and a bar in a color of
  the commit graph's lanes that compares their counts.

  The tiles and the authors lead on (OnOpenTarget, a fill under the
  mouse): the commits to the commit graph, the branches and the tags to
  their lists, the files to the tree of HEAD, the submodules to their
  pages, an author to the commit graph filtered to them. The size is a
  fact alone.

  It paints itself in the editor's palette, like the summary, and sizes
  its height to its content so it can sit in the same TScrollBox. While
  the facts are being read it says so under the name, keeping the facts
  read before, so a refresh does not blank the page. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, gittan.repoinfo, gittan.summary;

type
  {** What a tile or an author's row leads to. }
  TGittanRepoTarget = (rtCommits, rtBranches, rtTags, rtFiles, rtSubmodules, rtAuthor);
  {** A click on a tile or an author's row: the target, the author's name
    for rtAuthor, and the tile or row in screen coordinates, for a list
    to drop down from. }
  TGittanRepoTargetEvent = procedure(Sender: TObject; ATarget: TGittanRepoTarget;
    const AName: string; const AScreenRect: TRect) of object;

  { TGittanRepoPage }

  TGittanRepoPage = class(TCustomControl)
  private
    FName, FRoot: string;
    FInfo: TGittanRepoInfo;
    FHasInfo, FLoading: boolean;
    FBack, FText, FDim, FHover, FLine, FLink, FBar, FErrorColor, FCard: TColor;
    FLaneColors: array of TColor;
    FLinkRects: array of TRect;
    FLinkUrls: array of string;
    FHot: integer;
    FContentHeight: integer;
    FOnOpenUrl: TGittanOpenUrlEvent;
    FOnEditRemotes: TNotifyEvent;
    FOnOpenTarget: TGittanRepoTargetEvent;
    function LinkAt(X, Y: integer): integer;
    procedure SetHot(AValue: integer);
    function FitLeft(const AText: string; AMaxWidth: integer): string;
    function FitRight(const AText: string; AMaxWidth: integer): string;
    procedure AddLink(const ARect: TRect; const AUrl: string);
    procedure PaintHeading(var Y: integer; const ATitle, ADetail: string);
    procedure PaintAction(ATop: integer; const ACaption, ALink: string);
    procedure PaintRemote(var Y: integer; const ARemote: TGittanRemote; ANameWidth: integer);
    procedure PaintTiles(var Y: integer);
    procedure PaintContributors(var Y: integer);
    procedure PaintComposition(var Y: integer);
    function LaneColor(AIndex: integer): TColor;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    constructor Create(AOwner: TComponent); override;
    {** The repository shown: its name over its root. Another root
      drops the facts of the one before. }
    procedure SetRepository(const AName, ARoot: string);
    {** The facts, once read. }
    procedure SetInfo(const AInfo: TGittanRepoInfo);
    {** Whether the facts are being read: a note under the name. }
    procedure SetLoading(AValue: boolean);
    {** The palette: the background, the text, the dim text, the fill
      under the mouse, the dividers, the links, the bars of the
      contributors and the error text. }
    procedure SetColors(ABack, AText, ADim, AHover, ALine, ALink, ABar, AError: TColor);
    {** The fill of the tiles. }
    procedure SetCardColor(ACard: TColor);
    {** The colors of the contributors, in order: the commit graph's lane
      colors. Without them every bar takes the bar color. }
    procedure SetLaneColors(const AColors: array of TColor);
    {** Makes the control at least AMin high (the height of the box it
      sits in, so its background covers the box), and no higher than its
      content needs beyond that. }
    procedure FitHeight(AMin: integer);
    {** Whether facts are shown. }
    property HasInfo: boolean read FHasInfo;
    {** The root the facts are for. }
    property Root: string read FRoot;
    {** A click on a remote's web address. }
    property OnOpenUrl: TGittanOpenUrlEvent read FOnOpenUrl write FOnOpenUrl;
    {** A click on Edit Remotes... at the right of the remotes' heading. }
    property OnEditRemotes: TNotifyEvent read FOnEditRemotes write FOnEditRemotes;
    {** A click on a tile that leads on or on an author's row; while it
      is set they take a fill under the mouse. }
    property OnOpenTarget: TGittanRepoTargetEvent read FOnOpenTarget write FOnOpenTarget;
  end;

implementation

uses
  Math, DateUtils, LazUTF8, gittan.reviews, gittan.statusbar, gittan.textfit, gittan.theme;

resourcestring
  rsRemotes = 'Remotes';
  rsContributors = 'Contributors';
  rsComposition = 'Composition';
  rsAllFiles = 'All files';
  rsOneFileCount = '1 file';
  rsFilesCount = '%s files';
  rsOneLine = '1 line';
  rsLinesCount = '%s lines';
  rsCommitsLabel = 'Commits';
  rsBranchesLabel = 'Branches';
  rsTagsLabel = 'Tags';
  rsFilesLabel = 'Files';
  rsSubmodulesLabel = 'Submodules';
  rsSizeLabel = 'Size';
  rsUpstreamOf = 'tracks %s';
  rsNoUpstream = 'no upstream';
  rsSince = 'since %s';
  rsLastCommit = 'last commit %s';
  rsLocal = 'local';
  rsRemoteBranches = '%s remote';
  rsTracked = 'tracked';
  rsNoTags = 'none yet';
  rsObjects = 'of objects';
  rsCheckedIn = 'in .gitmodules';
  rsPushUrl = 'pushes to %s';
  rsNoRemotes = 'No remotes';
  rsEditRemotes = 'Edit Remotes…';
  rsOneAuthor = '1 author';
  rsAuthors = '%s authors';
  rsLoading = 'Reading the repository…';
  rsNone = 'none';
  rsDetached = 'detached';

const
  { The link of Edit Remotes..., told apart from a web address, and the
    links of the tiles (the target's ordinal after it) and the authors
    (the name after it). }
  EditRemotesLink = 'gittan:remotes';
  TileLink = 'gittan:tile:';
  AuthorLink = 'gittan:author:';
  Pad = 24;
  Gap = 12;
  RowHeight = 26;
  TitleFontSize = 20;
  BarHeight = 6;
  BarWidth = 360;
  MaxNameWidth = 240;
  { The tiles: their least width, the gap between them, the padding in
    them, the corner radius and the size of the count. }
  TileMinWidth = 150;
  TileGap = 10;
  TilePadX = 14;
  TilePadY = 10;
  TileRadius = 12;
  TileValueSize = 18;
  { The disc of a contributor's initials, and the rows of the lists. }
  AvatarSize = 24;
  ContributorRow = 34;
  RemoteRow = 30;
  DotSize = 8;

{ TGittanRepoPage }

constructor TGittanRepoPage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FHot := -1;
  Align := alTop;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnShadow, clHighlight,
    clHighlight, clRed);
  FCard := clBtnFace;
end;

procedure TGittanRepoPage.SetCardColor(ACard: TColor);
begin
  FCard := ACard;
  Invalidate;
end;

procedure TGittanRepoPage.SetLaneColors(const AColors: array of TColor);
var
  i: integer;
begin
  SetLength(FLaneColors, Length(AColors));
  for i := 0 to High(AColors) do
    FLaneColors[i] := AColors[i];
  Invalidate;
end;

function TGittanRepoPage.LaneColor(AIndex: integer): TColor;
begin
  if Length(FLaneColors) = 0 then
    Result := FBar
  else
    Result := FLaneColors[AIndex mod Length(FLaneColors)];
end;

procedure TGittanRepoPage.SetRepository(const AName, ARoot: string);
begin
  if FRoot <> ARoot then
  begin
    FHasInfo := False;
    FInfo := Default(TGittanRepoInfo);
  end;
  FName := AName;
  FRoot := ARoot;
  Invalidate;
end;

procedure TGittanRepoPage.SetInfo(const AInfo: TGittanRepoInfo);
begin
  FInfo := AInfo;
  FHasInfo := True;
  FLoading := False;
  FHot := -1;
  Invalidate;
end;

procedure TGittanRepoPage.SetLoading(AValue: boolean);
begin
  if FLoading = AValue then
    Exit;
  FLoading := AValue;
  Invalidate;
end;

procedure TGittanRepoPage.SetColors(ABack, AText, ADim, AHover, ALine, ALink, ABar,
  AError: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
  FLine := ALine;
  FLink := ALink;
  FBar := ABar;
  FErrorColor := AError;
  Color := ABack;
  Invalidate;
end;

procedure TGittanRepoPage.FitHeight(AMin: integer);
begin
  Constraints.MinHeight := AMin;
  Height := Max(FContentHeight, AMin);
end;

function TGittanRepoPage.LinkAt(X, Y: integer): integer;
var
  i: integer;
begin
  for i := 0 to High(FLinkRects) do
    if PtInRect(FLinkRects[i], Point(X, Y)) then
      Exit(i);
  Result := -1;
end;

procedure TGittanRepoPage.SetHot(AValue: integer);
begin
  if FHot = AValue then
    Exit;
  FHot := AValue;
  if AValue < 0 then
    Cursor := crDefault
  else
    Cursor := crHandPoint;
  Invalidate;
end;

{ AText cut from the left with an ellipsis until it fits AMaxWidth, so a
  long path keeps its end, which is the part that tells. }
function TGittanRepoPage.FitLeft(const AText: string; AMaxWidth: integer): string;
begin
  Result := FitTextLeft(Canvas, AText, AMaxWidth);
end;

{ AText cut at the end with an ellipsis until it fits AMaxWidth. }
function TGittanRepoPage.FitRight(const AText: string; AMaxWidth: integer): string;
begin
  Result := FitTextRight(Canvas, AText, AMaxWidth);
end;

procedure TGittanRepoPage.AddLink(const ARect: TRect; const AUrl: string);
begin
  SetLength(FLinkRects, Length(FLinkRects) + 1);
  SetLength(FLinkUrls, Length(FLinkUrls) + 1);
  FLinkRects[High(FLinkRects)] := ARect;
  FLinkUrls[High(FLinkUrls)] := AUrl;
end;

{ A dim title with a dim detail after it, over a divider. }
procedure TGittanRepoPage.PaintHeading(var Y: integer; const ATitle, ADetail: string);
var
  TextH, X: integer;
begin
  Inc(Y, Px(Pad));
  Canvas.Font := Font;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FDim;
  Canvas.Brush.Style := bsClear;
  TextH := Canvas.TextHeight('Xg');
  Canvas.TextOut(Px(Pad), Y, ATitle);
  X := Px(Pad) + Canvas.TextWidth(ATitle);
  Canvas.Font.Style := [];
  if ADetail <> '' then
    Canvas.TextOut(X + Px(Gap) div 2, Y, ADetail);
  Inc(Y, TextH + Px(Gap) div 2);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := FLine;
  Canvas.Line(Px(Pad), Y, Width - Px(Pad), Y);
  Inc(Y, Px(Gap) div 2);
end;

{ ACaption as a link at the right edge, on the line of a heading whose
  text starts at ATop. }
procedure TGittanRepoPage.PaintAction(ATop: integer; const ACaption, ALink: string);
var
  R: TRect;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  R := Rect(Width - Px(Pad) - Canvas.TextWidth(ACaption), ATop, Width - Px(Pad),
    ATop + Canvas.TextHeight('Xg'));
  AddLink(R, ALink);
  Canvas.Font.Color := FLink;
  if FHot = High(FLinkRects) then
    Canvas.Font.Style := [fsUnderline];
  Canvas.TextOut(R.Left, R.Top, ACaption);
  Canvas.Font.Style := [];
end;

{ A remote: a globe for a web address, else a folder, the name in bold
  in a column ANameWidth wide, then the URL, a link when it is a web
  address; a push URL of its own goes dimmed on a line under it. }
procedure TGittanRepoPage.PaintRemote(var Y: integer; const ARemote: TGittanRemote;
  ANameWidth: integer);
var
  TextH, TextY, X, IconW: integer;
  Shown: string;
  R: TRect;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  TextH := Canvas.TextHeight('Xg');
  TextY := Y + (Px(RemoteRow) - TextH) div 2;
  IconW := TextH - 4 + 6;
  if ARemote.Web <> '' then
    DrawStatusIcon(Canvas, HintLink, Px(Pad), TextY, TextH, FDim)
  else
    DrawStatusIcon(Canvas, HintFolder, Px(Pad), TextY, TextH, FDim);
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  X := Px(Pad) + IconW;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FText;
  Canvas.TextOut(X, TextY, FitRight(ARemote.Name, ANameWidth - Px(Gap)));
  Canvas.Font.Style := [];
  Inc(X, ANameWidth);
  Shown := FitRight(ARemote.Url, Width - Px(Pad) - X);
  if ARemote.Web <> '' then
  begin
    R := Rect(X, TextY, X + Canvas.TextWidth(Shown), TextY + TextH);
    AddLink(R, ARemote.Web);
    Canvas.Font.Color := FLink;
    if FHot = High(FLinkRects) then
      Canvas.Font.Style := [fsUnderline];
  end
  else
    Canvas.Font.Color := FText;
  Canvas.TextOut(X, TextY, Shown);
  Canvas.Font.Style := [];
  Inc(Y, Px(RemoteRow));
  if (ARemote.PushUrl <> '') and (ARemote.PushUrl <> ARemote.Url) then
  begin
    Canvas.Font.Color := FDim;
    Canvas.TextOut(X, Y - 4, FitRight(Format(rsPushUrl, [ARemote.PushUrl]), Width - Px(Pad) - X));
    Inc(Y, TextH + 2);
  end;
end;

{ The tiles: as many in a row as fit at TileMinWidth, the rows as even
  as they can be. Each has its name dimmed, the count large and a
  detail dimmed under it. }
procedure TGittanRepoPage.PaintTiles(var Y: integer);
var
  Labels, Values, Details: array of string;
  Targets: array of integer;
  n, MaxCols, Rows, Cols, TileW, TileH, BodyH, ValueH, i, X, TileY, Inner: integer;
  Tags: string;
  Settings: TFormatSettings;
  R: TRect;

  { ATarget -1 for a tile that leads nowhere. }
  procedure Add(const ALabel, AValue, ADetail: string; ATarget: integer);
  begin
    SetLength(Labels, Length(Labels) + 1);
    SetLength(Values, Length(Values) + 1);
    SetLength(Details, Length(Details) + 1);
    SetLength(Targets, Length(Targets) + 1);
    Labels[High(Labels)] := ALabel;
    Values[High(Values)] := AValue;
    Details[High(Details)] := ADetail;
    Targets[High(Targets)] := ATarget;
  end;

  { Leads on only when the repository has a commit. }
  function WithCommits(ATarget: TGittanRepoTarget): integer;
  begin
    if FInfo.Commits > 0 then
      Result := Ord(ATarget)
    else
      Result := -1;
  end;

begin
  Settings := DefaultFormatSettings;
  Labels := nil;
  Values := nil;
  Details := nil;
  Targets := nil;
  if FInfo.FirstCommit > 0 then
    Add(rsCommitsLabel, GroupDigits(FInfo.Commits), Format(rsSince,
      [FormatDateTime('d mmm yyyy', UniversalTimeToLocal(FInfo.FirstCommit), Settings)]),
      WithCommits(rtCommits))
  else
    Add(rsCommitsLabel, GroupDigits(FInfo.Commits), '', WithCommits(rtCommits));
  Add(rsBranchesLabel, GroupDigits(FInfo.LocalBranches), rsLocal + ' · ' +
    Format(rsRemoteBranches, [GroupDigits(FInfo.RemoteBranches)]), Ord(rtBranches));
  if FInfo.Tags = 0 then
    Tags := rsNoTags
  else
  begin
    Tags := '';
    for i := 0 to High(FInfo.NewestTags) do
    begin
      if Tags <> '' then
        Tags := Tags + ', ';
      Tags := Tags + FInfo.NewestTags[i].Name;
    end;
    if Length(FInfo.NewestTags) < FInfo.Tags then
      Tags := Tags + ', …';
  end;
  Add(rsTagsLabel, GroupDigits(FInfo.Tags), Tags, WithCommits(rtTags));
  Add(rsFilesLabel, GroupDigits(FInfo.Files), rsTracked, WithCommits(rtFiles));
  if FInfo.Submodules > 0 then
    Add(rsSubmodulesLabel, GroupDigits(FInfo.Submodules), rsCheckedIn, Ord(rtSubmodules));
  Add(rsSizeLabel, FormatKiB(FInfo.SizeKiB), rsObjects, -1);

  n := Length(Labels);
  MaxCols := Max(1, (Width - 2 * Px(Pad) + Px(TileGap)) div (Px(TileMinWidth) + Px(TileGap)));
  Rows := (n + MaxCols - 1) div MaxCols;
  Cols := (n + Rows - 1) div Rows;
  TileW := (Width - 2 * Px(Pad) - (Cols - 1) * Px(TileGap)) div Cols;
  Canvas.Font := Font;
  BodyH := Canvas.TextHeight('Xg');
  Canvas.Font.Size := TileValueSize;
  Canvas.Font.Style := [fsBold];
  ValueH := Canvas.TextHeight('Xg');
  TileH := 2 * Px(TilePadY) + 2 * BodyH + ValueH + 2;
  for i := 0 to n - 1 do
  begin
    X := Px(Pad) + (i mod Cols) * (TileW + Px(TileGap));
    TileY := Y + (i div Cols) * (TileH + Px(TileGap));
    R := Rect(X, TileY, X + TileW, TileY + TileH);
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FCard;
    if (Targets[i] >= 0) and Assigned(FOnOpenTarget) then
    begin
      if FHot = Length(FLinkRects) then
        Canvas.Brush.Color := FHover;
      AddLink(R, TileLink + IntToStr(Targets[i]));
    end;
    Canvas.RoundRect(R, Px(TileRadius), Px(TileRadius));
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsClear;
    Inner := TileW - 2 * Px(TilePadX);
    Canvas.Font := Font;
    Canvas.Font.Color := FDim;
    Canvas.TextOut(X + Px(TilePadX), TileY + Px(TilePadY), FitRight(Labels[i], Inner));
    Canvas.Font.Size := TileValueSize;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := FText;
    Canvas.TextOut(X + Px(TilePadX), TileY + Px(TilePadY) + BodyH, FitRight(Values[i], Inner));
    Canvas.Font := Font;
    Canvas.Font.Color := FDim;
    if Details[i] <> '' then
      Canvas.TextOut(X + Px(TilePadX), TileY + Px(TilePadY) + BodyH + ValueH + 2,
        FitRight(Details[i], Inner));
  end;
  Inc(Y, Rows * TileH + (Rows - 1) * Px(TileGap));
end;

{ The initials of AName: the first letters of its first and last word,
  in capitals. }
function Initials(const AName: string): string;
var
  Words: TStringArray;
  First, Last: string;
begin
  Words := Trim(AName).Split([' '], TStringSplitOptions.ExcludeEmpty);
  if Length(Words) = 0 then
    Exit('?');
  First := UTF8Copy(Words[0], 1, 1);
  if Length(Words) > 1 then
    Last := UTF8Copy(Words[High(Words)], 1, 1)
  else
    Last := '';
  Result := UTF8UpperCase(First + Last);
end;

{ A row per author: a disc with their initials in their color, the name,
  a bar in the same color against the most commits of any of them, and
  the count at the right edge with the share of all commits dimmed. }
procedure TGittanRepoPage.PaintContributors(var Y: integer);
var
  i, Most, TextH, TextY, NameCol, X, BarX, BarRight, BarW, ShareW, CountW,
    CenterY, InitialsH: integer;
  Count, Share, Mark: string;
  R: TRect;
begin
  Canvas.Font := Font;
  TextH := Canvas.TextHeight('Xg');
  Most := 0;
  NameCol := 0;
  for i := 0 to High(FInfo.Contributors) do
  begin
    Most := Max(Most, FInfo.Contributors[i].Commits);
    NameCol := Max(NameCol, Canvas.TextWidth(FInfo.Contributors[i].Name));
  end;
  NameCol := Min(NameCol, Px(MaxNameWidth)) + 2 * Px(Gap);
  ShareW := Canvas.TextWidth('100%');
  for i := 0 to High(FInfo.Contributors) do
  begin
    CenterY := Y + Px(ContributorRow) div 2;
    TextY := CenterY - TextH div 2;
    { The row leads to the author's commits, filled under the mouse. }
    if Assigned(FOnOpenTarget) then
    begin
      R := Rect(Px(Pad) - 6, Y + 1, Width - Px(Pad) + 6, Y + Px(ContributorRow) - 1);
      if FHot = Length(FLinkRects) then
      begin
        Canvas.Pen.Style := psClear;
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := FHover;
        Canvas.RoundRect(R, 8, 8);
        Canvas.Pen.Style := psSolid;
        Canvas.Brush.Style := bsClear;
      end;
      AddLink(R, AuthorLink + FInfo.Contributors[i].Name);
    end;
    { The disc and the initials, in the background color so they read
      on the lighter hues of a dark theme and the deeper of a light one. }
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := LaneColor(i);
    Canvas.Ellipse(Px(Pad), CenterY - Px(AvatarSize) div 2, Px(Pad) + Px(AvatarSize),
      CenterY + Px(AvatarSize) div 2);
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsClear;
    Mark := Initials(FInfo.Contributors[i].Name);
    Canvas.Font.Size := Max(8, Font.Size - 3);
    if Font.Size <= 0 then
      Canvas.Font.Size := 9;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := FBack;
    InitialsH := Canvas.TextHeight(Mark);
    Canvas.TextOut(Px(Pad) + (Px(AvatarSize) - Canvas.TextWidth(Mark)) div 2,
      CenterY - InitialsH div 2, Mark);
    Canvas.Font := Font;
    Canvas.Brush.Style := bsClear;

    X := Px(Pad) + Px(AvatarSize) + Px(Gap);
    Canvas.Font.Color := FText;
    Canvas.TextOut(X, TextY, FitRight(FInfo.Contributors[i].Name, NameCol - Px(Gap)));

    { The bar, left out when there is no room for it, then the count and
      the share right after it, in columns of their own. }
    BarX := X + NameCol;
    BarRight := Width - Px(Pad) - ShareW - 2 * Px(Gap) - Canvas.TextWidth('00 000');
    BarW := Min(Px(BarWidth), BarRight - BarX);
    if BarW < 40 then
      BarW := 0;
    if FInfo.Commits > 0 then
      Share := IntToStr(Round(FInfo.Contributors[i].Commits * 100 / FInfo.Commits)) + '%'
    else
      Share := '';
    Count := GroupDigits(FInfo.Contributors[i].Commits);
    CountW := Canvas.TextWidth(Count);
    X := BarX + BarW + Px(Gap) + Canvas.TextWidth('00 000');
    Canvas.Font.Color := FText;
    Canvas.TextOut(X - CountW, TextY, Count);
    Canvas.Font.Color := FDim;
    Canvas.TextOut(X + Px(Gap) + ShareW - Canvas.TextWidth(Share), TextY, Share);

    if BarW > 0 then
    begin
      R := Rect(BarX, CenterY - Px(BarHeight) div 2, BarX + BarW, CenterY + Px(BarHeight) div 2);
      Canvas.Pen.Style := psClear;
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := FHover;
      Canvas.RoundRect(R, Px(BarHeight), Px(BarHeight));
      if Most > 0 then
      begin
        R.Right := BarX + Max(Px(BarHeight), BarW * FInfo.Contributors[i].Commits div Most);
        Canvas.Brush.Color := LaneColor(i);
        Canvas.RoundRect(R, Px(BarHeight), Px(BarHeight));
      end;
      Canvas.Pen.Style := psSolid;
      Canvas.Brush.Style := bsClear;
    end;
    Inc(Y, Px(ContributorRow));
  end;
end;

{ The tracked files and their lines: All files, a divider, then a row
  per category with a dot in its color, the files dimmed, a bar of its
  share of the lines in the same color, the lines and the share. }
procedure TGittanRepoPage.PaintComposition(var Y: integer);
var
  Cat: TGittanFileCategory;
  AllFiles: integer;
  AllLines: int64;
  TextH, NameX, NameCol, FilesCol, LinesW, LinesRight, ShareW, BarX, BarW, CenterY,
    TextY: integer;
  Share: string;
  R: TRect;

  function FilesText(ACount: integer): string;
  begin
    if ACount = 1 then
      Result := rsOneFileCount
    else
      Result := Format(rsFilesCount, [GroupDigits(ACount)]);
  end;

  function LinesText(ACount: int64): string;
  begin
    if ACount = 1 then
      Result := rsOneLine
    else
      Result := Format(rsLinesCount, [GroupDigits(ACount)]);
  end;

  { The name, the files and the lines of a row; Y is its top. }
  procedure Row(const AName: string; AFiles: integer; ALines: int64; ABold: boolean);
  begin
    CenterY := Y + Px(RemoteRow) div 2;
    TextY := CenterY - TextH div 2;
    Canvas.Font := Font;
    Canvas.Brush.Style := bsClear;
    if ABold then
      Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := FText;
    Canvas.TextOut(NameX, TextY, AName);
    Canvas.TextOut(LinesRight - Canvas.TextWidth(LinesText(ALines)), TextY, LinesText(ALines));
    Canvas.Font.Style := [];
    Canvas.Font.Color := FDim;
    Canvas.TextOut(NameX + NameCol, TextY, FilesText(AFiles));
  end;

begin
  AllFiles := 0;
  AllLines := 0;
  for Cat := Low(Cat) to High(Cat) do
  begin
    Inc(AllFiles, FInfo.Composition[Cat].Files);
    Inc(AllLines, FInfo.Composition[Cat].Lines);
  end;
  Canvas.Font := Font;
  TextH := Canvas.TextHeight('Xg');
  NameX := Px(Pad) + Px(DotSize) + Px(Gap) div 2;
  Canvas.Font.Style := [fsBold];
  NameCol := Canvas.TextWidth(rsAllFiles);
  Canvas.Font.Style := [];
  for Cat := Low(Cat) to High(Cat) do
    NameCol := Max(NameCol, Canvas.TextWidth(CategoryName(Cat)));
  Inc(NameCol, 2 * Px(Gap));
  FilesCol := Canvas.TextWidth(Format(rsFilesCount, [GroupDigits(Max(AllFiles, 10000))])) +
    2 * Px(Gap);
  { The bar, left out when there is no room for it, then the lines and
  the share right after it, as the contributors have them. }
  ShareW := Canvas.TextWidth('100%');
  Canvas.Font.Style := [fsBold];
  LinesW := Canvas.TextWidth(LinesText(Max(AllLines, 1000000)));
  BarX := NameX + NameCol + FilesCol;
  BarW := Min(Px(BarWidth), Width - Px(Pad) - ShareW - 2 * Px(Gap) - LinesW - BarX);
  if BarW < 40 then
    BarW := 0;
  LinesRight := BarX + BarW + Px(Gap) + LinesW;

  Row(rsAllFiles, AllFiles, AllLines, True);
  Inc(Y, Px(RemoteRow));
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := FLine;
  Canvas.Line(NameX, Y, LinesRight + Px(Gap) + ShareW, Y);
  Inc(Y, Px(Gap) div 2);
  for Cat := Low(Cat) to High(Cat) do
  begin
    Row(CategoryName(Cat), FInfo.Composition[Cat].Files, FInfo.Composition[Cat].Lines, False);
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := LaneColor(Ord(Cat));
    Canvas.Ellipse(Px(Pad), CenterY - Px(DotSize) div 2, Px(Pad) + Px(DotSize),
      CenterY + Px(DotSize) div 2);
    if BarW > 0 then
    begin
      R := Rect(BarX, CenterY - Px(BarHeight) div 2, BarX + BarW, CenterY + Px(BarHeight) div 2);
      Canvas.Brush.Color := FHover;
      Canvas.RoundRect(R, Px(BarHeight), Px(BarHeight));
      if (AllLines > 0) and (FInfo.Composition[Cat].Lines > 0) then
      begin
        R.Right := BarX + Max(Px(BarHeight), Round(BarW * FInfo.Composition[Cat].Lines / AllLines));
        Canvas.Brush.Color := LaneColor(Ord(Cat));
        Canvas.RoundRect(R, Px(BarHeight), Px(BarHeight));
      end;
    end;
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsClear;
    if AllLines > 0 then
      Share := IntToStr(Round(FInfo.Composition[Cat].Lines * 100 / AllLines)) + '%'
    else
      Share := '';
    Canvas.Font := Font;
    Canvas.Font.Color := FDim;
    Canvas.TextOut(LinesRight + Px(Gap) + ShareW - Canvas.TextWidth(Share), TextY, Share);
    Inc(Y, Px(RemoteRow));
  end;
end;

procedure TGittanRepoPage.Paint;
var
  Y, TextH, TitleH, NameW, i, X, TextY, HeadingTop: integer;
  Detail: string;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  FLinkRects := nil;
  FLinkUrls := nil;
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  TextH := Canvas.TextHeight('Xg');
  Y := Px(Pad);

  { The name with the branch after it, as the summary's header has it,
    and what the branch tracks; the path under them. }
  Canvas.Font.Size := TitleFontSize;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FText;
  TitleH := Canvas.TextHeight('Xg');
  Canvas.TextOut(Px(Pad), Y, FName);
  X := Px(Pad) + Canvas.TextWidth(FName) + Px(Gap);
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  if FHasInfo then
  begin
    TextY := Y + TitleH - TextH - 3;
    if FInfo.Branch <> '' then
    begin
      DrawStatusIcon(Canvas, HintBranch, X, TextY, TextH, FDim);
      Canvas.Pen.Width := 1;
      Canvas.Brush.Style := bsClear;
      Inc(X, TextH - 4 + 5);
      Canvas.Font.Color := FText;
      Canvas.TextOut(X, TextY, FInfo.Branch);
      Inc(X, Canvas.TextWidth(FInfo.Branch) + Px(Gap));
      if FInfo.Upstream <> '' then
        Detail := Format(rsUpstreamOf, [FInfo.Upstream])
      else
        Detail := rsNoUpstream;
    end
    else
      Detail := rsDetached;
    if FInfo.LastCommit > 0 then
      Detail := Detail + ' · ' + Format(rsLastCommit,
        [ReviewAge(FInfo.LastCommit, LocalTimeToUniversal(Now))]);
    Canvas.Font.Color := FDim;
    Canvas.TextOut(X, TextY, FitRight(Detail, Max(0, Width - Px(Pad) - X)));
  end;
  Inc(Y, TitleH + 2);
  Canvas.Font.Color := FDim;
  Canvas.TextOut(Px(Pad), Y, FitLeft(FRoot, Width - 2 * Px(Pad)));
  Inc(Y, TextH);
  if FLoading or (FHasInfo and not FInfo.Ok) then
  begin
    Inc(Y, Px(Gap) div 2);
    if FLoading then
    begin
      Canvas.Font.Color := FDim;
      Canvas.TextOut(Px(Pad), Y, rsLoading);
    end
    else
    begin
      Canvas.Font.Color := FErrorColor;
      Canvas.TextOut(Px(Pad), Y, FitRight(Trim(FInfo.Error), Width - 2 * Px(Pad)));
    end;
    Inc(Y, TextH);
  end;

  if FHasInfo then
  begin
    Inc(Y, Px(Pad));
    PaintTiles(Y);

    PaintHeading(Y, rsComposition, '');
    PaintComposition(Y);

    HeadingTop := Y;
    PaintHeading(Y, rsRemotes, '');
    if Assigned(FOnEditRemotes) then
      PaintAction(HeadingTop + Px(Pad), rsEditRemotes, EditRemotesLink);
    Canvas.Font := Font;
    Canvas.Font.Style := [fsBold];
    NameW := 0;
    for i := 0 to High(FInfo.Remotes) do
      NameW := Max(NameW, Canvas.TextWidth(FInfo.Remotes[i].Name));
    NameW := Min(NameW, Px(MaxNameWidth)) + 2 * Px(Gap);
    if Length(FInfo.Remotes) = 0 then
    begin
      Canvas.Font := Font;
      Canvas.Font.Color := FDim;
      Canvas.TextOut(Px(Pad), Y + (Px(RemoteRow) - TextH) div 2, rsNoRemotes);
      Inc(Y, Px(RemoteRow));
    end
    else
      for i := 0 to High(FInfo.Remotes) do
        PaintRemote(Y, FInfo.Remotes[i], NameW);

    if FInfo.Authors = 1 then
      Detail := rsOneAuthor
    else
      Detail := Format(rsAuthors, [GroupDigits(FInfo.Authors)]);
    PaintHeading(Y, rsContributors, Detail);
    if Length(FInfo.Contributors) = 0 then
    begin
      Canvas.Font := Font;
      Canvas.Font.Color := FDim;
      Canvas.TextOut(Px(Pad), Y + (Px(RowHeight) - TextH) div 2, rsNone);
      Inc(Y, Px(RowHeight));
    end
    else
      PaintContributors(Y);
  end;

  { FitHeight sizes the page from the paint before, which a new width
    may have changed: tiles wrapped into fewer rows leave it too tall.
    The height follows what was painted, up or down; it does not depend
    on the height, so this paint is the last. }
  FContentHeight := Y + Px(Pad);
  if Height <> Max(FContentHeight, Constraints.MinHeight) then
    Height := Max(FContentHeight, Constraints.MinHeight);
end;

procedure TGittanRepoPage.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(LinkAt(X, Y));
end;

procedure TGittanRepoPage.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1);
end;

procedure TGittanRepoPage.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  i, n: integer;
  R: TRect;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  i := LinkAt(X, Y);
  if i < 0 then
    Exit;
  R := Rect(ClientToScreen(FLinkRects[i].TopLeft).X, ClientToScreen(FLinkRects[i].TopLeft).Y,
    ClientToScreen(FLinkRects[i].BottomRight).X, ClientToScreen(FLinkRects[i].BottomRight).Y);
  if Copy(FLinkUrls[i], 1, Length(TileLink)) = TileLink then
  begin
    n := StrToIntDef(Copy(FLinkUrls[i], Length(TileLink) + 1, MaxInt), -1);
    if Assigned(FOnOpenTarget) and (n >= Ord(Low(TGittanRepoTarget))) and
      (n <= Ord(High(TGittanRepoTarget))) then
      FOnOpenTarget(Self, TGittanRepoTarget(n), '', R);
  end
  else if Copy(FLinkUrls[i], 1, Length(AuthorLink)) = AuthorLink then
  begin
    if Assigned(FOnOpenTarget) then
      FOnOpenTarget(Self, rtAuthor, Copy(FLinkUrls[i], Length(AuthorLink) + 1, MaxInt), R);
  end
  else if FLinkUrls[i] = EditRemotesLink then
  begin
    if Assigned(FOnEditRemotes) then
      FOnEditRemotes(Self);
  end
  else if Assigned(FOnOpenUrl) then
    FOnOpenUrl(Self, FLinkUrls[i]);
end;

end.
