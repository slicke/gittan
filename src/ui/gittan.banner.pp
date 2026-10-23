unit gittan.banner;

{** A banner: a strip at the top of the space right of the tree, over
  the file header or the summary, that tells what went wrong (or, for a
  moment, what went well) without stopping the user as a dialog does.

  It shows one message at a time, the newest: an icon in its tone, the
  title in bold and the first line of the detail dimmed after it. When
  the detail has more lines than that, or is cut, Details unfolds it in
  the detail font under the title. Copy puts the title and the detail
  on the clipboard (not offered for a note or a success without one),
  and the close button takes the message away, which brings back the
  one before it; "+2" before the button counts those. A message can
  carry an action, a link by the close button that runs its handler and
  closes the message (Push after a commit, say). An error stays
  until it is closed; a message given seconds closes itself after them,
  later while the mouse is over the banner.

  It paints itself in colors the form sets, like the file header, and
  raises OnChange when it is shown, hidden or resized, so the form can
  move the space under the title bar onto it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, ExtCtrls;

type
  {** The tone of a message: an error in red, a note in the accent, a
    success in green. }
  TGittanBannerKind = (bkError, bkInfo, bkSuccess);

  { TGittanBanner }

  TGittanBanner = class(TCustomControl)
  private
    type
    TItem = record
      Title, Detail: string;
      Kind: TGittanBannerKind;
      Seconds: integer;
      Action: string;
      OnAction: TNotifyEvent;
    end;

    TPart = (bpNone, bpAction, bpDetails, bpCopy, bpClose);
  private
    FItems: array of TItem;
    FLines: TStringArray;
    FExpanded: boolean;
    FHotPart: TPart;
    FActionRect, FDetailsRect, FCopyRect, FCloseRect: TRect;
    FDetailFont: TFont;
    FTimer: TTimer;
    FBack, FText, FDim, FHover, FLine, FAccent, FBad, FGood: TColor;
    FOnChange: TNotifyEvent;
    function Current: TItem;
    procedure SetHotPart(AValue: TPart);
    procedure TimerTimer(Sender: TObject);
    procedure ShowCurrent;
    procedure UpdateHeight;
    function LineHeight(AFont: TFont): integer;
    function Unfoldable: boolean;
    function PartAt(X, Y: integer): TPart;
    procedure DrawIcon(X, Y: integer; AColor: TColor; AKind: TGittanBannerKind);
    procedure Changed;
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
    {** The palette: the background, the title, the dimmed detail and
      links, the fill under the mouse, the line along the bottom, the
      tone of a note, of an error and of a success, which also tint the
      background. }
    procedure SetColors(ABack, AText, ADim, AHover, ALine, AAccent, ABad,
      AGood: TColor);
    {** Shows a message over the one in view. ADetail may run over
      several lines; ASeconds closes it after that many seconds, 0 never.
      The same message as the one in view is not added again. }
    procedure Add(const ATitle, ADetail: string; AKind: TGittanBannerKind;
      ASeconds: integer = 0);
    {** Shows a message as Add does, with AAction as a link by the close
      button that closes the message and calls AOnAction. }
    procedure AddAction(const ATitle, ADetail: string; AKind: TGittanBannerKind;
      ASeconds: integer; const AAction: string; AOnAction: TNotifyEvent);
    {** Closes the message in view, showing the one before it. }
    procedure CloseCurrent;
    {** Closes every message. }
    procedure Clear;
    {** The detail's font when unfolded: the editor's, so git's output
      lines up. }
    property DetailFont: TFont read FDetailFont;
    {** After it was shown, hidden or resized. }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

uses
  Math, Clipbrd, gittan.textfit, gittan.terminal, gittan.theme;

resourcestring
  rsBannerCopy = 'Copy';
  rsBannerDetails = 'Details';
  rsBannerHide = 'Hide';
  rsBannerMore = '… %d more lines (Copy has them all)';

const
  RowHeight = 36;
  Pad = 12;
  IconSize = 16;
  Gap = 8;
  CloseSize = 22;
  MaxLines = 14;
  MaxItems = 10;
  TintPercent = 14;

{ TGittanBanner }

constructor TGittanBanner.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Height := RowHeight;
  FDetailFont := TFont.Create;
  FDetailFont.Assign(Font);
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.OnTimer := @TimerTimer;
  SetColors(clBtnFace, clWindowText, clGrayText, clBtnShadow, clBtnShadow,
    clHighlight, clRed, clGreen);
end;

destructor TGittanBanner.Destroy;
begin
  FDetailFont.Free;
  inherited Destroy;
end;

procedure TGittanBanner.SetColors(ABack, AText, ADim, AHover, ALine, AAccent,
  ABad, AGood: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
  FLine := ALine;
  FAccent := AAccent;
  FBad := ABad;
  FGood := AGood;
  Invalidate;
end;

function TGittanBanner.Current: TItem;
begin
  Result := FItems[High(FItems)];
end;

procedure TGittanBanner.Add(const ATitle, ADetail: string; AKind: TGittanBannerKind;
  ASeconds: integer);
begin
  AddAction(ATitle, ADetail, AKind, ASeconds, '', nil);
end;

procedure TGittanBanner.AddAction(const ATitle, ADetail: string;
  AKind: TGittanBannerKind; ASeconds: integer; const AAction: string;
  AOnAction: TNotifyEvent);
var
  Item: TItem;
  Detail: string;
begin
  { Output a program wrote in color loses its escape sequences; the
    notice is where it shows in color. }
  Detail := ADetail;
  if Pos(#27, Detail) > 0 then
    Detail := TerminalPlainText(Detail);
  if (Length(FItems) > 0) and (Current.Title = ATitle) and
    (Current.Detail = Detail) and (Current.Kind = AKind) and
    (Current.Action = AAction) then
  begin
    ShowCurrent;
    Exit;
  end;
  if Length(FItems) >= MaxItems then
    Delete(FItems, 0, 1);
  Item.Title := ATitle;
  Item.Detail := Detail;
  Item.Kind := AKind;
  Item.Seconds := ASeconds;
  Item.Action := AAction;
  Item.OnAction := AOnAction;
  Insert(Item, FItems, Length(FItems));
  ShowCurrent;
end;

procedure TGittanBanner.CloseCurrent;
begin
  if Length(FItems) = 0 then
    Exit;
  SetLength(FItems, Length(FItems) - 1);
  ShowCurrent;
end;

procedure TGittanBanner.Clear;
begin
  if Length(FItems) = 0 then
    Exit;
  FItems := nil;
  ShowCurrent;
end;

{ Shows the newest message folded, starts its timer, or hides the
  banner when none is left. }
procedure TGittanBanner.ShowCurrent;
begin
  FExpanded := False;
  FHotPart := bpNone;
  FTimer.Enabled := False;
  if Length(FItems) = 0 then
  begin
    FLines := nil;
    if Visible then
    begin
      Visible := False;
      Changed;
    end;
    Exit;
  end;
  FLines := Trim(Current.Detail).Split([LineEnding, #10]);
  if Current.Seconds > 0 then
  begin
    FTimer.Interval := Current.Seconds * 1000;
    FTimer.Enabled := True;
  end;
  UpdateHeight;
  if not Visible then
  begin
    Visible := True;
    Changed;
  end;
  Invalidate;
end;

procedure TGittanBanner.TimerTimer(Sender: TObject);
begin
  { Not while the user is reading it with the mouse on it. }
  if MouseInClient then
    Exit;
  CloseCurrent;
end;

function TGittanBanner.LineHeight(AFont: TFont): integer;
begin
  if HandleAllocated then
  begin
    Canvas.Font := AFont;
    Result := Canvas.TextHeight('Xg') + 2;
  end
  else
    Result := 16;
end;

procedure TGittanBanner.UpdateHeight;
var
  H: integer;
begin
  H := RowHeight;
  if FExpanded then
    H := H + Min(Length(FLines), MaxLines + 1) * LineHeight(FDetailFont) + Pad;
  if H <> Height then
  begin
    Height := H;
    Changed;
  end;
end;

{ More lines than the first, or the first cut where the row ends: the
  latter is known from the last paint, through FDetailsRect. }
function TGittanBanner.Unfoldable: boolean;
begin
  Result := (Length(FItems) > 0) and not FDetailsRect.IsEmpty;
end;

procedure TGittanBanner.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TGittanBanner.Resize;
begin
  inherited Resize;
  Invalidate;
end;

{ A disc in the tone with a white mark: "!" for an error, "i" for a
  note, a check for a success. }
procedure TGittanBanner.DrawIcon(X, Y: integer; AColor: TColor;
  AKind: TGittanBannerKind);
var
  CX: integer;
begin
  Canvas.Pen.Style := psClear;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := AColor;
  Canvas.Ellipse(X, Y, X + IconSize, Y + IconSize);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := clWhite;
  Canvas.Pen.Width := 2;
  CX := X + IconSize div 2;
  case AKind of
    bkError:
      begin
        Canvas.Line(CX, Y + 4, CX, Y + 9);
        Canvas.Line(CX, Y + 11, CX, Y + 13);
      end;
    bkInfo:
      begin
        Canvas.Line(CX, Y + 4, CX, Y + 6);
        Canvas.Line(CX, Y + 8, CX, Y + 13);
      end;
    bkSuccess:
      begin
        Canvas.Line(X + 4, Y + 8, X + 7, Y + 11);
        Canvas.Line(X + 7, Y + 11, X + 12, Y + 5);
      end;
  end;
  Canvas.Pen.Width := 1;
end;

procedure TGittanBanner.Paint;
var
  Item: TItem;
  Tone, Back: TColor;
  X, Y, TextY, Right, LH, i, Room: integer;
  First, S: string;

  { A link at the right end of the row, from Right leftward. }
  function PlaceLink(const ACaption: string; APart: TPart): TRect;
  var
    W: integer;
  begin
    W := Canvas.TextWidth(ACaption);
    Result := Rect(Right - W - 6, (RowHeight - CloseSize) div 2, Right,
      (RowHeight + CloseSize) div 2);
    if FHotPart = APart then
    begin
      Canvas.Pen.Style := psClear;
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := FHover;
      Canvas.RoundRect(Result, 6, 6);
      Canvas.Pen.Style := psSolid;
    end;
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := Tone;
    Canvas.TextOut(Result.Left + 3, TextY, ACaption);
    Right := Result.Left - Gap div 2;
  end;

begin
  if Length(FItems) = 0 then
  begin
    Canvas.Brush.Color := FBack;
    Canvas.FillRect(ClientRect);
    Exit;
  end;
  Item := Current;
  case Item.Kind of
    bkError: Tone := FBad;
    bkSuccess: Tone := FGood;
    else
      Tone := FAccent;
  end;
  Back := MixColor(FBack, Tone, TintPercent / 100);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Back;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := FLine;
  Canvas.Line(0, Height - 1, Width, Height - 1);

  Canvas.Font := Font;
  TextY := (RowHeight - Canvas.TextHeight('Xg')) div 2;
  DrawIcon(Pad, (RowHeight - IconSize) div 2, Tone, Item.Kind);

  { The close button at the right end, then the count, the action, Copy
    and Details leftward. }
  FCloseRect := Rect(Width - Pad - CloseSize + 4, (RowHeight - CloseSize) div 2,
    Width - Pad + 4, (RowHeight + CloseSize) div 2);
  if FHotPart = bpClose then
  begin
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Color := FHover;
    Canvas.RoundRect(FCloseRect, 6, 6);
    Canvas.Pen.Style := psSolid;
  end;
  Canvas.Pen.Color := FDim;
  Canvas.Pen.Width := 2;
  with FCloseRect do
  begin
    Canvas.Line(Left + 7, Top + 7, Right - 7, Bottom - 7);
    Canvas.Line(Right - 7, Top + 7, Left + 7, Bottom - 7);
  end;
  Canvas.Pen.Width := 1;
  Right := FCloseRect.Left - Gap;
  Canvas.Brush.Style := bsClear;
  if Length(FItems) > 1 then
  begin
    S := '+' + IntToStr(Length(FItems) - 1);
    Canvas.Font.Color := FDim;
    Canvas.TextOut(Right - Canvas.TextWidth(S), TextY, S);
    Right := Right - Canvas.TextWidth(S) - Gap;
  end;
  if (Item.Action <> '') and Assigned(Item.OnAction) then
  begin
    Canvas.Font.Style := [fsBold];
    FActionRect := PlaceLink(Item.Action, bpAction);
    Canvas.Font.Style := [];
  end
  else
    FActionRect := Rect(0, 0, 0, 0);
  { A note or a success that is its title alone has nothing to copy,
    nor one that offers an action, which is the point of it. }
  if (Item.Kind = bkError) or ((Trim(Item.Detail) <> '') and (Item.Action = '')) then
    FCopyRect := PlaceLink(rsBannerCopy, bpCopy)
  else
    FCopyRect := Rect(0, 0, 0, 0);

  { The title, then the first detail line in what is left; Details goes
    in when there is more to see. }
  X := Pad + IconSize + Gap;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FText;
  Canvas.TextOut(X, TextY, Item.Title);
  Inc(X, Canvas.TextWidth(Item.Title) + Gap);
  Canvas.Font.Style := [];
  if Length(FLines) > 0 then
    First := Trim(FLines[0])
  else
    First := '';
  FDetailsRect := Rect(0, 0, 0, 0);
  if (Length(FLines) > 1) or (X + Canvas.TextWidth(First) > Right - Gap) or
    (FExpanded and (First <> '')) then
  begin
    if FExpanded then
      S := rsBannerHide
    else
      S := rsBannerDetails;
    FDetailsRect := PlaceLink(S, bpDetails);
  end;
  if not FExpanded and (First <> '') then
  begin
    Room := Right - Gap - X;
    First := FitTextRight(Canvas, First, Room);
    if Room > 0 then
    begin
      Canvas.Font.Color := FDim;
      Canvas.TextRect(Rect(X, 0, X + Room, RowHeight), X, TextY, First);
    end;
  end;

  if FExpanded then
  begin
    LH := LineHeight(FDetailFont);
    Canvas.Font := FDetailFont;
    Canvas.Font.Color := FText;
    Canvas.Brush.Style := bsClear;
    X := Pad + IconSize + Gap;
    Y := RowHeight;
    for i := 0 to Min(High(FLines), MaxLines - 1) do
    begin
      Canvas.TextRect(Rect(X, Y, Width - Pad, Y + LH), X, Y, FLines[i]);
      Inc(Y, LH);
    end;
    if Length(FLines) > MaxLines then
    begin
      Canvas.Font.Color := FDim;
      Canvas.TextOut(X, Y, Format(rsBannerMore, [Length(FLines) - MaxLines]));
    end;
  end;
end;

function TGittanBanner.PartAt(X, Y: integer): TPart;
var
  P: TPoint;
begin
  P := Point(X, Y);
  if PtInRect(FCloseRect, P) then
    Result := bpClose
  else if PtInRect(FActionRect, P) then
    Result := bpAction
  else if PtInRect(FCopyRect, P) then
    Result := bpCopy
  else if Unfoldable and PtInRect(FDetailsRect, P) then
    Result := bpDetails
  else
    Result := bpNone;
end;

procedure TGittanBanner.SetHotPart(AValue: TPart);
begin
  if FHotPart = AValue then
    Exit;
  FHotPart := AValue;
  if AValue = bpNone then
    Cursor := crDefault
  else
    Cursor := crHandPoint;
  Invalidate;
end;

procedure TGittanBanner.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHotPart(PartAt(X, Y));
end;

procedure TGittanBanner.MouseLeave;
begin
  inherited MouseLeave;
  SetHotPart(bpNone);
end;

procedure TGittanBanner.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  S: string;
  OnAction: TNotifyEvent;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button <> mbLeft) or (Length(FItems) = 0) then
    Exit;
  case PartAt(X, Y) of
    bpClose:
      CloseCurrent;
    bpAction:
      begin
        OnAction := Current.OnAction;
        CloseCurrent;
        if Assigned(OnAction) then
          OnAction(Self);
      end;
    bpCopy:
      begin
        S := Current.Title;
        if Trim(Current.Detail) <> '' then
          S := S + LineEnding + Trim(Current.Detail);
        Clipboard.AsText := S;
      end;
    bpDetails:
      begin
        FExpanded := not FExpanded;
        UpdateHeight;
        Invalidate;
      end;
  end;
end;

end.
