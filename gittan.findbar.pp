unit gittan.findbar;

{** The find bar: a row under the file header with a text field, the
  previous and next buttons with a match counter (the change navigator's
  pill, reused), a "Not found" note and a close cross. It knows nothing
  about the text it searches: it raises OnSearch when the text changes or
  Enter is pressed, and the form answers with SetMatches.

  The field is a native TEdit so typing, selection and the clipboard work
  as the desktop expects; the rest paints itself in the editor's colors. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, StdCtrls, LCLType, gittan.changenav;

type
  {** The search text and the direction: ANext is false for Shift+Enter
    and the previous button. AFromStart asks for a fresh search from the
    caret, as when the text was edited; otherwise the next match after
    the current one. }
  TGittanSearchEvent = procedure(Sender: TObject; const AText: string;
    ANext, AFromStart: boolean) of object;

  { TGittanFindBar }

  TGittanFindBar = class(TCustomControl)
  private
    FEdit: TEdit;
    FNav: TGittanChangeNav;
    FNotFound: boolean;
    FBack, FText, FDim, FLine: TColor;
    FOnSearch: TGittanSearchEvent;
    FOnClose: TNotifyEvent;
    FCloseHot: boolean;
    function CloseRect: TRect;
    procedure EditChange(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure NavPrev(Sender: TObject);
    procedure NavNext(Sender: TObject);
    procedure Search(ANext, AFromStart: boolean);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    constructor Create(AOwner: TComponent); override;
    {** Shows the bar, focuses the field and selects its text so typing
      replaces the previous search. }
    procedure Activate;
    {** Shows ACurrent of ATotal matches on the pill, or "Not found" when
      ATotal is 0 and there is a search text. }
    procedure SetMatches(ACurrent, ATotal: integer);
    {** The colors: the background, the text, the dim text for the note,
      and the bottom border line. }
    procedure SetColors(ABack, AText, ADim, ALine: TColor);
    {** The pill, for its colors. }
    property Nav: TGittanChangeNav read FNav;
    {** The search text as typed. }
    function SearchText: string;
    property OnSearch: TGittanSearchEvent read FOnSearch write FOnSearch;
    {** The cross was clicked or Escape pressed; the owner hides the bar
      and returns the focus to the editor. }
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
  end;

implementation

uses
  Math;

resourcestring
  rsNotFound = 'Not found';
  rsFindHint = 'Find';

const
  BarHeight = 38;
  Pad = 12;
  Gap = 10;
  NavHeight = 26;
  EditWidth = 240;
  CloseSize = 16;

{ TGittanFindBar }

constructor TGittanFindBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Height := BarHeight;
  FEdit := TEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.Width := EditWidth;
  FEdit.TextHint := rsFindHint;
  FEdit.OnChange := @EditChange;
  FEdit.OnKeyDown := @EditKeyDown;
  FNav := TGittanChangeNav.Create(Self);
  FNav.Parent := Self;
  FNav.Height := NavHeight;
  FNav.OnPrev := @NavPrev;
  FNav.OnNext := @NavNext;
  FNav.Visible := False;
  SetColors(clWindow, clWindowText, clGrayText, clBtnShadow);
end;

procedure TGittanFindBar.Activate;
begin
  Visible := True;
  if FEdit.CanFocus then
    FEdit.SetFocus;
  FEdit.SelectAll;
end;

function TGittanFindBar.SearchText: string;
begin
  Result := FEdit.Text;
end;

procedure TGittanFindBar.SetMatches(ACurrent, ATotal: integer);
begin
  FNotFound := (ATotal = 0) and (FEdit.Text <> '');
  FNav.Visible := ATotal > 0;
  if ATotal > 0 then
    FNav.SetPosition(ACurrent, ATotal);
  Invalidate;
end;

procedure TGittanFindBar.SetColors(ABack, AText, ADim, ALine: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FLine := ALine;
  Color := ABack;
  Invalidate;
end;

procedure TGittanFindBar.Search(ANext, AFromStart: boolean);
begin
  if Assigned(FOnSearch) then
    FOnSearch(Self, FEdit.Text, ANext, AFromStart);
end;

{ Typing searches at once, from the caret, so the first match appears
  while the word is still being typed. }
procedure TGittanFindBar.EditChange(Sender: TObject);
begin
  Search(True, True);
end;

procedure TGittanFindBar.EditKeyDown(Sender: TObject; var Key: word;
  Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        Search(not (ssShift in Shift), False);
        Key := 0;
      end;
    VK_ESCAPE:
      begin
        if Assigned(FOnClose) then
          FOnClose(Self);
        Key := 0;
      end;
  end;
end;

procedure TGittanFindBar.NavPrev(Sender: TObject);
begin
  Search(False, False);
end;

procedure TGittanFindBar.NavNext(Sender: TObject);
begin
  Search(True, False);
end;

function TGittanFindBar.CloseRect: TRect;
begin
  Result.Left := Width - Pad - CloseSize;
  Result.Top := (Height - 1 - CloseSize) div 2;
  Result.Right := Result.Left + CloseSize;
  Result.Bottom := Result.Top + CloseSize;
end;

{ The field on the left, the pill after it, the note after the pill; the
  cross on the right. }
procedure TGittanFindBar.Resize;
begin
  inherited Resize;
  { The constructor resizes before the children exist. }
  if (FEdit = nil) or (FNav = nil) then
    Exit;
  FEdit.Left := Pad;
  FEdit.Top := (Height - 1 - FEdit.Height) div 2;
  FEdit.Width := Min(EditWidth, Max(80, Width - 3 * Pad - FNav.Width - CloseSize));
  FNav.Left := FEdit.Left + FEdit.Width + Gap;
  FNav.Top := (Height - 1 - FNav.Height) div 2;
end;

procedure TGittanFindBar.Paint;
var
  R: TRect;
  X, TextY: integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := FLine;
  Canvas.Line(0, Height - 1, Width, Height - 1);
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  TextY := (Height - 1 - Canvas.TextHeight('Xg')) div 2;
  if FNotFound then
  begin
    X := FEdit.Left + FEdit.Width + Gap;
    Canvas.Font.Color := FDim;
    Canvas.TextOut(X, TextY, rsNotFound);
  end;
  { The cross: two strokes, brighter under the mouse. }
  R := CloseRect;
  if FCloseHot then
    Canvas.Pen.Color := FText
  else
    Canvas.Pen.Color := FDim;
  Canvas.Pen.Width := 2;
  Canvas.Line(R.Left + 4, R.Top + 4, R.Right - 4, R.Bottom - 4);
  Canvas.Line(R.Right - 4, R.Top + 4, R.Left + 4, R.Bottom - 4);
  Canvas.Pen.Width := 1;
end;

procedure TGittanFindBar.MouseMove(Shift: TShiftState; X, Y: integer);
var
  Hot: boolean;
begin
  inherited MouseMove(Shift, X, Y);
  Hot := CloseRect.Contains(Point(X, Y));
  if Hot <> FCloseHot then
  begin
    FCloseHot := Hot;
    Invalidate;
  end;
end;

procedure TGittanFindBar.MouseLeave;
begin
  inherited MouseLeave;
  if FCloseHot then
  begin
    FCloseHot := False;
    Invalidate;
  end;
end;

procedure TGittanFindBar.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button = mbLeft) and CloseRect.Contains(Point(X, Y)) and Assigned(FOnClose) then
    FOnClose(Self);
end;

end.
