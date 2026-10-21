unit gittan.repopage;

{** The Repository page: what Gittan shows about the repository itself,
  beside the summary of its changes. Under the name and the path it
  lists the facts gittan.repoinfo gathers in three parts: an overview
  (the branch and its upstream, how many commits since when, the
  branches, the tags, the tracked files, the submodules and the size of
  the objects), the remotes with their URLs, a web address among them
  being a link and Edit Remotes... at the right of the heading, and the
  authors with the most commits, each with a bar
  that compares their counts.

  It paints itself in the editor's palette, like the summary, and sizes
  its height to its content so it can sit in the same TScrollBox. While
  the facts are being read it says so under the name, keeping the facts
  read before, so a refresh does not blank the page. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, gittan.repoinfo, gittan.summary;

type

  { TGittanRepoPage }

  TGittanRepoPage = class(TCustomControl)
  private
    FName, FRoot: string;
    FInfo: TGittanRepoInfo;
    FHasInfo, FLoading: boolean;
    FBack, FText, FDim, FHover, FLine, FLink, FBar, FErrorColor: TColor;
    FLinkRects: array of TRect;
    FLinkUrls: array of string;
    FHot: integer;
    FContentHeight: integer;
    FOnOpenUrl: TGittanOpenUrlEvent;
    FOnEditRemotes: TNotifyEvent;
    function LinkAt(X, Y: integer): integer;
    procedure SetHot(AValue: integer);
    function FitLeft(const AText: string; AMaxWidth: integer): string;
    function FitRight(const AText: string; AMaxWidth: integer): string;
    procedure AddLink(const ARect: TRect; const AUrl: string);
    procedure PaintHeading(var Y: integer; const ATitle, ADetail: string);
    procedure PaintAction(ATop: integer; const ACaption, ALink: string);
    procedure PaintRow(var Y: integer; ALabelWidth: integer; const ALabel, AValue: string;
      const AUrl: string = '');
    function OverviewRows(ALabels, AValues: TStrings): integer;
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
  end;

implementation

uses
  Math, DateUtils, gittan.reviews;

resourcestring
  rsOverview = 'Overview';
  rsRemotes = 'Remotes';
  rsContributors = 'Contributors';
  rsBranchLabel = 'Branch';
  rsCommitsLabel = 'Commits';
  rsBranchesLabel = 'Branches';
  rsTagsLabel = 'Tags';
  rsFilesLabel = 'Files';
  rsSubmodulesLabel = 'Submodules';
  rsSizeLabel = 'Size';
  rsUpstreamOf = 'tracks %s';
  rsNoUpstream = 'no upstream';
  rsFirstCommit = 'the first on %s';
  rsLatestCommit = 'the latest %s';
  rsLocalRemote = '%s local · %s remote';
  rsTracked = '%s tracked';
  rsNoRemotes = 'No remotes';
  rsEditRemotes = 'Edit Remotes…';
  rsOneAuthor = '1 author';
  rsAuthors = '%s authors';
  rsLoading = 'Reading the repository…';
  rsNone = 'none';
  rsDetached = 'detached';

const
  { The link of Edit Remotes..., told apart from a web address. }
  EditRemotesLink = 'gittan:remotes';
  Pad = 24;
  Gap = 12;
  RowHeight = 26;
  TitleFontSize = 20;
  BarHeight = 6;
  BarWidth = 160;
  MaxNameWidth = 240;

{ TGittanRepoPage }

constructor TGittanRepoPage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FHot := -1;
  Align := alTop;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnShadow, clHighlight,
    clHighlight, clRed);
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
var
  Cut: integer;
begin
  Result := AText;
  if Canvas.TextWidth(Result) <= AMaxWidth then
    Exit;
  Cut := 1;
  while (Cut < Length(AText)) and
    (Canvas.TextWidth('…' + Copy(AText, Cut + 1, MaxInt)) > AMaxWidth) do
    Inc(Cut);
  Result := '…' + Copy(AText, Cut + 1, MaxInt);
end;

{ AText cut at the end with an ellipsis until it fits AMaxWidth. }
function TGittanRepoPage.FitRight(const AText: string; AMaxWidth: integer): string;
var
  Len: integer;
begin
  Result := AText;
  if Canvas.TextWidth(Result) <= AMaxWidth then
    Exit;
  Len := Length(AText);
  while (Len > 1) and (Canvas.TextWidth(Copy(AText, 1, Len) + '…') > AMaxWidth) do
    Dec(Len);
  Result := Copy(AText, 1, Len) + '…';
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
  Inc(Y, Pad);
  Canvas.Font := Font;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FDim;
  Canvas.Brush.Style := bsClear;
  TextH := Canvas.TextHeight('Xg');
  Canvas.TextOut(Pad, Y, ATitle);
  X := Pad + Canvas.TextWidth(ATitle);
  Canvas.Font.Style := [];
  if ADetail <> '' then
    Canvas.TextOut(X + Gap div 2, Y, ADetail);
  Inc(Y, TextH + Gap div 2);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := FLine;
  Canvas.Line(Pad, Y, Width - Pad, Y);
  Inc(Y, Gap div 2);
end;

{ ACaption as a link at the right edge, on the line of a heading whose
  text starts at ATop. }
procedure TGittanRepoPage.PaintAction(ATop: integer; const ACaption, ALink: string);
var
  R: TRect;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  R := Rect(Width - Pad - Canvas.TextWidth(ACaption), ATop, Width - Pad,
    ATop + Canvas.TextHeight('Xg'));
  AddLink(R, ALink);
  Canvas.Font.Color := FLink;
  if FHot = High(FLinkRects) then
    Canvas.Font.Style := [fsUnderline];
  Canvas.TextOut(R.Left, R.Top, ACaption);
  Canvas.Font.Style := [];
end;

{ A row of a dim label in a column ALabelWidth wide and a value after
  it; a value with AUrl is drawn as a link. }
procedure TGittanRepoPage.PaintRow(var Y: integer; ALabelWidth: integer;
  const ALabel, AValue: string; const AUrl: string);
var
  TextH, TextY, X, Room: integer;
  Shown: string;
  R: TRect;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  TextH := Canvas.TextHeight('Xg');
  TextY := Y + (RowHeight - TextH) div 2;
  Canvas.Font.Color := FDim;
  Canvas.TextOut(Pad, TextY, FitRight(ALabel, ALabelWidth - Gap div 2));
  X := Pad + ALabelWidth;
  Room := Width - Pad - X;
  if AUrl <> '' then
  begin
    Shown := FitRight(AValue, Room);
    R := Rect(X, TextY, X + Canvas.TextWidth(Shown), TextY + TextH);
    AddLink(R, AUrl);
    Canvas.Font.Color := FLink;
    if FHot = High(FLinkRects) then
      Canvas.Font.Style := [fsUnderline];
    Canvas.TextOut(X, TextY, Shown);
    Canvas.Font.Style := [];
  end
  else
  begin
    Canvas.Font.Color := FText;
    Canvas.TextOut(X, TextY, FitRight(AValue, Room));
  end;
  Inc(Y, RowHeight);
end;

{ The labels and values of the overview, in order; the width of the
  widest label is given. }
function TGittanRepoPage.OverviewRows(ALabels, AValues: TStrings): integer;
var
  Value, Tags: string;
  i: integer;
  Settings: TFormatSettings;
begin
  Settings := DefaultFormatSettings;
  ALabels.Clear;
  AValues.Clear;
  if FInfo.Branch <> '' then
  begin
    Value := FInfo.Branch;
    if FInfo.Upstream <> '' then
      Value := Value + ' · ' + Format(rsUpstreamOf, [FInfo.Upstream])
    else
      Value := Value + ' · ' + rsNoUpstream;
  end
  else
    Value := rsDetached;
  ALabels.Add(rsBranchLabel);
  AValues.Add(Value);
  Value := GroupDigits(FInfo.Commits);
  if FInfo.FirstCommit > 0 then
    Value := Value + ' · ' + Format(rsFirstCommit,
      [FormatDateTime('d mmm yyyy', UniversalTimeToLocal(FInfo.FirstCommit), Settings)]);
  if FInfo.LastCommit > 0 then
    Value := Value + ' · ' + Format(rsLatestCommit,
      [ReviewAge(FInfo.LastCommit, LocalTimeToUniversal(Now))]);
  ALabels.Add(rsCommitsLabel);
  AValues.Add(Value);
  ALabels.Add(rsBranchesLabel);
  AValues.Add(Format(rsLocalRemote, [GroupDigits(FInfo.LocalBranches),
    GroupDigits(FInfo.RemoteBranches)]));
  if FInfo.Tags = 0 then
    Value := rsNone
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
    Value := GroupDigits(FInfo.Tags);
    if Tags <> '' then
      Value := Value + ' · ' + Tags;
  end;
  ALabels.Add(rsTagsLabel);
  AValues.Add(Value);
  ALabels.Add(rsFilesLabel);
  AValues.Add(Format(rsTracked, [GroupDigits(FInfo.Files)]));
  if FInfo.Submodules > 0 then
  begin
    ALabels.Add(rsSubmodulesLabel);
    AValues.Add(GroupDigits(FInfo.Submodules));
  end;
  ALabels.Add(rsSizeLabel);
  AValues.Add(FormatKiB(FInfo.SizeKiB));
  Result := 0;
  Canvas.Font := Font;
  for i := 0 to ALabels.Count - 1 do
    Result := Max(Result, Canvas.TextWidth(ALabels[i]));
end;

procedure TGittanRepoPage.Paint;
var
  Y, TextH, TitleH, LabelWidth, i, Most, X, TextY, BarX, BarW, CountW, NameW,
    HeadingTop: integer;
  Labels, Values: TStringList;
  Detail, Count: string;
  R: TRect;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  FLinkRects := nil;
  FLinkUrls := nil;
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  TextH := Canvas.TextHeight('Xg');
  Y := Pad;

  { The name and the path, as the summary's header. }
  Canvas.Font.Size := TitleFontSize;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FText;
  TitleH := Canvas.TextHeight('Xg');
  Canvas.TextOut(Pad, Y, FName);
  Inc(Y, TitleH + 2);
  Canvas.Font.Size := Font.Size;
  Canvas.Font.Style := [];
  Canvas.Font.Color := FDim;
  Canvas.TextOut(Pad, Y, FitLeft(FRoot, Width - 2 * Pad));
  Inc(Y, TextH);
  if FLoading or (FHasInfo and not FInfo.Ok) then
  begin
    Inc(Y, Gap div 2);
    if FLoading then
    begin
      Canvas.Font.Color := FDim;
      Canvas.TextOut(Pad, Y, rsLoading);
    end
    else
    begin
      Canvas.Font.Color := FErrorColor;
      Canvas.TextOut(Pad, Y, FitRight(Trim(FInfo.Error), Width - 2 * Pad));
    end;
    Inc(Y, TextH);
  end;

  if FHasInfo then
  begin
    Labels := TStringList.Create;
    Values := TStringList.Create;
    try
      LabelWidth := OverviewRows(Labels, Values);
      { The remotes' names share the column. }
      for i := 0 to High(FInfo.Remotes) do
        LabelWidth := Max(LabelWidth, Canvas.TextWidth(FInfo.Remotes[i].Name));
      LabelWidth := Min(LabelWidth, MaxNameWidth) + Gap;
      PaintHeading(Y, rsOverview, '');
      for i := 0 to Labels.Count - 1 do
        PaintRow(Y, LabelWidth, Labels[i], Values[i]);

      HeadingTop := Y;
      PaintHeading(Y, rsRemotes, '');
      if Assigned(FOnEditRemotes) then
        PaintAction(HeadingTop + Pad, rsEditRemotes, EditRemotesLink);
      if Length(FInfo.Remotes) = 0 then
        PaintRow(Y, LabelWidth, '', rsNoRemotes)
      else
        for i := 0 to High(FInfo.Remotes) do
          PaintRow(Y, LabelWidth, FInfo.Remotes[i].Name, FInfo.Remotes[i].Url,
            FInfo.Remotes[i].Web);

      if FInfo.Authors = 1 then
        Detail := rsOneAuthor
      else
        Detail := Format(rsAuthors, [GroupDigits(FInfo.Authors)]);
      PaintHeading(Y, rsContributors, Detail);
      { A row per author: the name, a bar against the most commits of
        any of them, and the count at the right edge. }
      Most := 0;
      for i := 0 to High(FInfo.Contributors) do
        Most := Max(Most, FInfo.Contributors[i].Commits);
      if Length(FInfo.Contributors) = 0 then
        PaintRow(Y, LabelWidth, '', rsNone);
      for i := 0 to High(FInfo.Contributors) do
      begin
        Canvas.Font := Font;
        Canvas.Brush.Style := bsClear;
        TextY := Y + (RowHeight - TextH) div 2;
        Count := GroupDigits(FInfo.Contributors[i].Commits);
        CountW := Canvas.TextWidth(Count);
        BarW := Min(BarWidth, Max(40, Width - 2 * Pad - MaxNameWidth - CountW - 2 * Gap));
        NameW := Width - 2 * Pad - BarW - CountW - 2 * Gap;
        Canvas.Font.Color := FText;
        Canvas.TextOut(Pad, TextY, FitRight(FInfo.Contributors[i].Name, NameW));
        BarX := Width - Pad - CountW - Gap - BarW;
        R := Rect(BarX, Y + (RowHeight - BarHeight) div 2, BarX + BarW,
          Y + (RowHeight + BarHeight) div 2);
        Canvas.Pen.Style := psClear;
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := FHover;
        Canvas.RoundRect(R, BarHeight, BarHeight);
        if Most > 0 then
        begin
          R.Right := BarX + Max(BarHeight, BarW * FInfo.Contributors[i].Commits div Most);
          Canvas.Brush.Color := FBar;
          Canvas.RoundRect(R, BarHeight, BarHeight);
        end;
        Canvas.Pen.Style := psSolid;
        Canvas.Brush.Style := bsClear;
        Canvas.Font.Color := FDim;
        X := Width - Pad - CountW;
        Canvas.TextOut(X, TextY, Count);
        Inc(Y, RowHeight);
      end;
    finally
      Labels.Free;
      Values.Free;
    end;
  end;

  FContentHeight := Y + Pad;
  if Height < FContentHeight then
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
  i: integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  i := LinkAt(X, Y);
  if i < 0 then
    Exit;
  if FLinkUrls[i] = EditRemotesLink then
  begin
    if Assigned(FOnEditRemotes) then
      FOnEditRemotes(Self);
  end
  else if Assigned(FOnOpenUrl) then
    FOnOpenUrl(Self, FLinkUrls[i]);
end;

end.
