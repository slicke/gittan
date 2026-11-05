unit gittan.extpage;

{** An extension's tab of the forge view (uforge; Gittan.forgeTabs.register
  in spec/extensions.md): the tab's title and what it is for, Refresh,
  then what the extension's render gave (SetModel, read by
  gittan.ext.views): a paragraph, and a card per row with its title (a
  link when the row has a url or a repository), a tag at its right, its
  detail in the row's severity and its actions as pills; Loading while
  render runs, Working while an action does, its error in the error
  color. Painted in the forge view's palette (ForgePalette), its height
  measured on a measuring canvas before it is shown (Layout), as the
  batch page's. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, gittan.ext.views, gittan.cardpage;

type
  {** An action of a row picked: the row's index and the action's id. }
  TGittanExtActionEvent = procedure(Sender: TObject; ARow: integer; const AAction: string)
    of object;
  {** A row's title clicked: its url, or its repository's root. }
  TGittanExtOpenEvent = procedure(Sender: TObject; const ATarget: string) of object;

  { TGittanExtTabPage }

  TGittanExtTabPage = class(TGittanCardPage)
  private
    FTitle, FNote, FSource, FError, FBusyText: string;
    FModel: TExtTabModel;
    FHasModel, FBusy: boolean;
    FOnRefresh: TNotifyEvent;
    FOnAction: TGittanExtActionEvent;
    FOnOpenUrl, FOnOpenRepo: TGittanExtOpenEvent;
    function SeverityColor(ASeverity: TExtSeverity): TColor;
    procedure PaintRow(var Y: integer; AIndex, ALeft, ARight: integer);
  protected
    procedure PaintContent; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    {** Shows the tab ATitle with ANote under it and ASource (which
      extension it is from) dim after the puzzle piece, nothing of
      another tab's kept. }
    procedure SetTab(const ATitle, ANote, ASource: string);
    {** Render runs (Loading) or an action does (Working); the model
      shown stays meanwhile. }
    procedure SetBusy(ABusy, AAction: boolean);
    {** What render gave. }
    procedure SetModel(const AModel: TExtTabModel);
    {** What failed, '' for nothing; the model shown stays. }
    procedure SetError(const AError: string);
    {** The row at AIndex as the extension gave it, for an action. }
    function RowJson(AIndex: integer): string;
    property OnRefresh: TNotifyEvent read FOnRefresh write FOnRefresh;
    property OnAction: TGittanExtActionEvent read FOnAction write FOnAction;
    property OnOpenUrl: TGittanExtOpenEvent read FOnOpenUrl write FOnOpenUrl;
    property OnOpenRepo: TGittanExtOpenEvent read FOnOpenRepo write FOnOpenRepo;
  end;

implementation

uses
  Math, LCLIntf, LCLType, gittan.forgepage, gittan.textfit, gittan.theme, gittan.puzzle;

resourcestring
  rsRefresh = 'Refresh';
  rsLoading = 'Loading…';
  rsWorking = 'Working…';
  rsNothing = 'Nothing to show.';
  rsOpen = 'Open';

const
  RefreshPillLink = 'refresh';
  RowOpenLink = 'o:';
  RowActionLink = 'a:';
  Pad = 24;
  Gap = 12;
  TitleFontSize = 20;
  MaxContentWidth = 960;
  CardPadX = 14;
  CardPadY = 10;
  CardRadius = 12;
  CardGap = 8;
  TagPadX = 6;

constructor TGittanExtTabPage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
end;

procedure TGittanExtTabPage.SetTab(const ATitle, ANote, ASource: string);
begin
  FTitle := ATitle;
  FNote := ANote;
  FSource := ASource;
  FModel := Default(TExtTabModel);
  FHasModel := False;
  FError := '';
  FBusy := False;
  FHot := -1;
  Layout;
end;

procedure TGittanExtTabPage.SetBusy(ABusy, AAction: boolean);
begin
  FBusy := ABusy;
  if AAction then
    FBusyText := rsWorking
  else
    FBusyText := rsLoading;
  if ABusy then
    FError := '';
  Layout;
end;

procedure TGittanExtTabPage.SetModel(const AModel: TExtTabModel);
begin
  FModel := AModel;
  FHasModel := True;
  FBusy := False;
  FError := '';
  FHot := -1;
  Layout;
end;

procedure TGittanExtTabPage.SetError(const AError: string);
begin
  FError := AError;
  FBusy := False;
  Layout;
end;

function TGittanExtTabPage.RowJson(AIndex: integer): string;
begin
  if (AIndex >= 0) and (AIndex <= High(FModel.Rows)) then
    Result := FModel.Rows[AIndex].Json
  else
    Result := 'null';
end;

function TGittanExtTabPage.SeverityColor(ASeverity: TExtSeverity): TColor;
begin
  case ASeverity of
    esOk: Result := FOk;
    esWarn: Result := FWarn;
    esError: Result := FErrorColor;
    else
      Result := FDim;
  end;
end;

{ A row's card: the title in bold, a link (Open at the right) when the
  row has a url or a repository; the tag at the right of the title; the
  detail, wrapped, in the row's severity; the actions as pills. }
procedure TGittanExtTabPage.PaintRow(var Y: integer; AIndex, ALeft, ARight: integer);
var
  Row: TExtTabRow;
  TextH, H, Inner, RowTop, TagW, OpenW, X, PillsRight, Lines, i: integer;
  R, HeadR, PillR: TRect;
  Hot, CanOpen: boolean;
begin
  Row := FModel.Rows[AIndex];
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  Inner := ARight - ALeft - 2 * Px(CardPadX);
  H := 2 * Px(CardPadY) + TextH;
  if Row.Detail <> '' then
    Inc(H, Px(4) + WrappedHeight(Row.Detail, Inner));
  { The actions' pills wrap as the Batch page's operations do; the
    lines are counted with the same test the painting below makes, so
    the card is as tall as its pills. }
  PillsRight := ALeft + Px(CardPadX) + Inner;
  if Length(Row.Actions) > 0 then
  begin
    Lines := 1;
    X := ALeft + Px(CardPadX);
    for i := 0 to High(Row.Actions) do
    begin
      if (X > ALeft + Px(CardPadX)) and (X + PillWidth(Row.Actions[i].Title) > PillsRight) then
      begin
        X := ALeft + Px(CardPadX);
        Inc(Lines);
      end;
      Inc(X, PillWidth(Row.Actions[i].Title) + Px(6));
    end;
    Inc(H, Px(8) + TextH + 2 * Px(PillPadY) +
      (Lines - 1) * (TextH + 2 * Px(PillPadY) + Px(6)));
  end;
  R := Rect(ALeft, Y, ARight, Y + H);
  HeadR := Rect(ALeft, Y, ARight, Y + Px(CardPadY) + TextH + Px(4));
  CanOpen := (Row.Url <> '') or (Row.Repo <> '');
  Hot := False;
  if CanOpen then
  begin
    AddLink(HeadR, RowOpenLink + IntToStr(AIndex));
    Hot := FHot = High(FLinkRects);
  end;
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FCard;
  FC.RoundRect(R, Px(CardRadius), Px(CardRadius));
  if Hot then
  begin
    FC.Brush.Color := FHover;
    FC.RoundRect(HeadR, Px(CardRadius), Px(CardRadius));
  end;
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;

  RowTop := Y + Px(CardPadY);
  X := ARight - Px(CardPadX);
  OpenW := 0;
  if CanOpen then
  begin
    OpenW := FC.TextWidth(rsOpen);
    if Hot then
      FC.Font.Color := FLink
    else
      FC.Font.Color := FDim;
    FC.TextOut(X - OpenW, RowTop, rsOpen);
    Dec(X, OpenW + Px(Gap));
  end;
  TagW := 0;
  if Row.Tag <> '' then
  begin
    FC.Font.Color := SeverityColor(Row.Severity);
    TagW := FC.TextWidth(Row.Tag) + 2 * Px(TagPadX);
    FC.Pen.Color := FLine;
    FC.RoundRect(Rect(X - TagW, RowTop - 1, X, RowTop + TextH + 1), Px(8), Px(8));
    FC.TextOut(X - TagW + Px(TagPadX), RowTop, Row.Tag);
    Dec(X, TagW + Px(Gap));
  end;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  FC.TextOut(ALeft + Px(CardPadX), RowTop, FitTextLeft(FC, Row.Title, X - ALeft - Px(CardPadX)));
  FC.Font.Style := [];
  Inc(RowTop, TextH);
  if Row.Detail <> '' then
  begin
    Inc(RowTop, Px(4));
    if Row.Severity = esInfo then
      PaintText(RowTop, Row.Detail, FDim, ALeft + Px(CardPadX), ALeft + Px(CardPadX) + Inner)
    else
      PaintText(RowTop, Row.Detail, SeverityColor(Row.Severity), ALeft + Px(CardPadX),
        ALeft + Px(CardPadX) + Inner);
  end;
  if Length(Row.Actions) > 0 then
  begin
    Inc(RowTop, Px(8) + Px(PillPadY));
    X := ALeft + Px(CardPadX);
    for i := 0 to High(Row.Actions) do
    begin
      if (X > ALeft + Px(CardPadX)) and (X + PillWidth(Row.Actions[i].Title) > PillsRight) then
      begin
        X := ALeft + Px(CardPadX);
        Inc(RowTop, TextH + 2 * Px(PillPadY) + Px(6));
      end;
      PillR := PaintPill(X, RowTop, Row.Actions[i].Title,
        RowActionLink + IntToStr(AIndex) + ':' + Row.Actions[i].Id, False, not FBusy);
      X := PillR.Right + Px(6);
    end;
    Inc(RowTop, TextH + Px(PillPadY));
  end;
  Y := RowTop + Px(CardPadY) + Px(CardGap);
end;

procedure TGittanExtTabPage.PaintContent;
var
  Y, L, R, TextH, TitleH, i, Piece: integer;
  PillR: TRect;
begin
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FBack;
  FC.FillRect(Rect(0, 0, Width, Height));
  FLinkRects := nil;
  FLinkUrls := nil;
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  L := Max(Px(Pad), (Width - Px(MaxContentWidth)) div 2);
  R := Width - L;
  Y := Px(Pad);

  FC.Font.Size := TitleFontSize;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  TitleH := FC.TextHeight('Xg');
  FC.TextOut(L, Y, FitTextLeft(FC, FTitle, R - L));
  FC.Font := Font;
  Inc(Y, TitleH + 2);
  if FNote <> '' then
    PaintText(Y, FNote, FDim, L, R);
  { Which extension the tab is from, after the piece the strip shows. }
  if FSource <> '' then
  begin
    Inc(Y, Px(4));
    Piece := Px(11);
    PaintPuzzle(FC, L, Y + (TextH - Piece) div 2, Piece, FDim);
    FC.Brush.Style := bsClear;
    FC.Font.Color := FDim;
    FC.TextOut(L + Piece + Px(6), Y, FitTextLeft(FC, FSource, R - L - Piece - Px(6)));
    Inc(Y, TextH);
  end;
  Inc(Y, Px(Gap) + Px(PillPadY));

  PillR := PaintPill(L, Y, rsRefresh, RefreshPillLink, False, not FBusy);
  FC.Font.Color := FDim;
  if FBusy then
    FC.TextOut(PillR.Right + Px(Gap), Y, FBusyText);
  Inc(Y, TextH + Px(PillPadY) + Px(Gap));

  if FError <> '' then
  begin
    PaintText(Y, FError, FErrorColor, L, R);
    Inc(Y, Px(Gap));
  end;
  if FHasModel then
  begin
    if FModel.Text <> '' then
    begin
      PaintText(Y, FModel.Text, FText, L, R);
      Inc(Y, Px(Gap));
    end;
    for i := 0 to High(FModel.Rows) do
      PaintRow(Y, i, L, R);
    if (Length(FModel.Rows) = 0) and (FModel.Text = '') then
    begin
      if FModel.Empty <> '' then
        PaintText(Y, FModel.Empty, FDim, L, R)
      else
        PaintText(Y, rsNothing, FDim, L, R);
      Inc(Y, Px(Gap));
    end;
  end;
  FContentHeight := Y + Px(Pad);
end;

procedure TGittanExtTabPage.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  i, p, a: integer;
  Url, Rest: string;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  i := LinkAt(X, Y);
  if i < 0 then
    Exit;
  Url := FLinkUrls[i];
  if Url = RefreshPillLink then
  begin
    if Assigned(FOnRefresh) then
      FOnRefresh(Self);
  end
  else if Copy(Url, 1, Length(RowActionLink)) = RowActionLink then
  begin
    Rest := Copy(Url, Length(RowActionLink) + 1, MaxInt);
    p := Pos(':', Rest);
    a := StrToIntDef(Copy(Rest, 1, p - 1), -1);
    if (a >= 0) and (a <= High(FModel.Rows)) and Assigned(FOnAction) then
      FOnAction(Self, a, Copy(Rest, p + 1, MaxInt));
  end
  else if Copy(Url, 1, Length(RowOpenLink)) = RowOpenLink then
  begin
    a := StrToIntDef(Copy(Url, Length(RowOpenLink) + 1, MaxInt), -1);
    if (a < 0) or (a > High(FModel.Rows)) then
      Exit;
    if FModel.Rows[a].Url <> '' then
    begin
      if Assigned(FOnOpenUrl) then
        FOnOpenUrl(Self, FModel.Rows[a].Url);
    end
    else if Assigned(FOnOpenRepo) then
      FOnOpenRepo(Self, FModel.Rows[a].Repo);
  end;
end;

end.
