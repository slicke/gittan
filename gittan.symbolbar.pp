unit gittan.symbolbar;

{** The symbol bar: a row under the file header with a filter field and
  a list of the symbols of the shown file (the functions, methods and
  classes of the lexer's code tree, indented by nesting), or of the
  whole repository, each with where it is. Typing filters the list, the
  names matched at a word start first, Up and Down move in it, Enter or
  a double click picks: the bar raises OnPick with the symbol's index in
  the list SetSymbols got, and OnClose for Escape or the cross. It knows
  nothing about the text.

  The field and the list are native controls so typing, scrolling and
  the keyboard work as the desktop expects; the row paints itself in the
  editor's colors like the find bar. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, StdCtrls, LCLType, Types;

type
  TGittanPickEvent = procedure(Sender: TObject; AIndex: integer) of object;

  { TGittanSymbolBar }

  TGittanSymbolBar = class(TCustomControl)
  private
    FEdit: TEdit;
    FList: TListBox;
    FNames, FDetails: TStringList;
    FDepths: TIntegerDynArray;
    { The index in FNames of every row the list shows. }
    FShown: TIntegerDynArray;
    FBack, FText, FDim, FLine: TColor;
    FOnPick: TGittanPickEvent;
    FOnClose: TNotifyEvent;
    FCloseHot: boolean;
    function CloseRect: TRect;
    procedure Fill;
    procedure Pick;
    procedure Close;
    procedure EditChange(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure ListKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure ListDblClick(Sender: TObject);
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
    {** The symbols to list, in file order, each with its nesting depth.
      ADetails, when given, says where each symbol is (the symbols of
      the repository): it is shown after the name, nothing is indented,
      and the list stays empty until something is typed. }
    procedure SetSymbols(ANames: TStrings; const ADepths: TIntegerDynArray;
      ADetails: TStrings = nil);
    {** Shows the bar, focuses the field and selects its text so typing
      replaces the previous filter. }
    procedure Activate;
    {** The colors: the background, the text, the dim text, and the
      bottom border line. }
    procedure SetColors(ABack, AText, ADim, ALine: TColor);
    property OnPick: TGittanPickEvent read FOnPick write FOnPick;
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
  end;

implementation

uses
  Math;

resourcestring
  rsSymbolHint = 'Symbol';
  rsRepoSymbolHint = 'Symbol in repository';
  rsNoSymbols = 'No symbols';
  rsTypeToSearch = 'Type to search';
  rsMoreSymbols = '… %d more';

const
  { The most rows the list shows; a native list with thousands of rows
    is slow to fill. }
  MaxRows = 300;
  DetailSep = '  ·  ';
  RowHeight = 38;
  { The list's height; its native row height is unknown until it has a
    handle, so a fixed one is used. }
  ListHeight = 220;
  Pad = 12;
  Gap = 10;
  EditWidth = 240;
  CloseSize = 16;

{ TGittanSymbolBar }

constructor TGittanSymbolBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FNames := TStringList.Create;
  FDetails := TStringList.Create;
  FEdit := TEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.Width := EditWidth;
  FEdit.TextHint := rsSymbolHint;
  FEdit.OnChange := @EditChange;
  FEdit.OnKeyDown := @EditKeyDown;
  FList := TListBox.Create(Self);
  FList.Parent := Self;
  FList.BorderStyle := bsNone;
  FList.OnKeyDown := @ListKeyDown;
  FList.OnDblClick := @ListDblClick;
  Height := RowHeight + ListHeight + Pad;
  SetColors(clWindow, clWindowText, clGrayText, clBtnShadow);
end;

destructor TGittanSymbolBar.Destroy;
begin
  FNames.Free;
  FDetails.Free;
  inherited Destroy;
end;

procedure TGittanSymbolBar.SetSymbols(ANames: TStrings; const ADepths: TIntegerDynArray;
  ADetails: TStrings);
begin
  FNames.Assign(ANames);
  FDepths := Copy(ADepths);
  if ADetails = nil then
    FDetails.Clear
  else
    FDetails.Assign(ADetails);
  if FDetails.Count > 0 then
    FEdit.TextHint := rsRepoSymbolHint
  else
    FEdit.TextHint := rsSymbolHint;
  Fill;
end;

procedure TGittanSymbolBar.Activate;
begin
  Visible := True;
  if FEdit.CanFocus then
    FEdit.SetFocus;
  FEdit.SelectAll;
end;

procedure TGittanSymbolBar.SetColors(ABack, AText, ADim, ALine: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FLine := ALine;
  Color := ABack;
  Invalidate;
end;

{ Whether C begins a word: not a letter, digit or underscore (a
  non-ASCII byte counts as a letter), so a filter matched after it
  matches at the start of an identifier. }
function IsWordBreak(C: char): boolean;
begin
  Result := not (C in ['A'..'Z', 'a'..'z', '0'..'9', '_', #128..#255]);
end;

{ The rows that match the filter (any part of the name, ignoring case),
  those matched at the start of a word first, at most MaxRows of them,
  indented by depth while there is no filter. The symbols of the
  repository need a filter: there are too many to list. The first row is
  selected so Enter picks it. }
procedure TGittanSymbolBar.Fill;
var
  Filter, Row, Low: string;
  i, p, Pass, Count, Matches: integer;
  AtWordStart: boolean;
begin
  Filter := LowerCase(Trim(FEdit.Text));
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    SetLength(FShown, FNames.Count);
    Count := 0;
    Matches := 0;
    if (Filter = '') and (FDetails.Count > 0) then
      FList.Items.Add(rsTypeToSearch)
    else
      for Pass := 0 to 1 do
      begin
        if (Filter = '') and (Pass = 1) then
          Break;
        for i := 0 to FNames.Count - 1 do
        begin
          Row := FNames[i];
          if Filter <> '' then
          begin
            Low := LowerCase(Row);
            p := Pos(Filter, Low);
            if p = 0 then
              Continue;
            { The first pass takes the matches at a word start, the
              second the rest. }
            AtWordStart := False;
            while (p > 0) and not AtWordStart do
            begin
              AtWordStart := (p = 1) or IsWordBreak(Low[p - 1]);
              p := Pos(Filter, Low, p + 1);
            end;
            if AtWordStart <> (Pass = 0) then
              Continue;
          end;
          Inc(Matches);
          if Count >= MaxRows then
            Continue;
          if (Filter = '') and (i <= High(FDepths)) then
            Row := StringOfChar(' ', 3 * FDepths[i]) + Row;
          if i < FDetails.Count then
            Row := Row + DetailSep + FDetails[i];
          FList.Items.Add(Row);
          FShown[Count] := i;
          Inc(Count);
        end;
      end;
    SetLength(FShown, Count);
    if Matches > Count then
      FList.Items.Add(Format(rsMoreSymbols, [Matches - Count]))
    else if FList.Items.Count = 0 then
      FList.Items.Add(rsNoSymbols);
  finally
    FList.Items.EndUpdate;
  end;
  if Count > 0 then
    FList.ItemIndex := 0;
end;


procedure TGittanSymbolBar.Pick;
begin
  if (FList.ItemIndex >= 0) and (FList.ItemIndex <= High(FShown)) and
    Assigned(FOnPick) then
    FOnPick(Self, FShown[FList.ItemIndex]);
end;

procedure TGittanSymbolBar.Close;
begin
  if Assigned(FOnClose) then
    FOnClose(Self);
end;

procedure TGittanSymbolBar.EditChange(Sender: TObject);
begin
  Fill;
end;

{ Up and Down move in the list without leaving the field. }
procedure TGittanSymbolBar.EditKeyDown(Sender: TObject; var Key: word;
  Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        Pick;
        Key := 0;
      end;
    VK_ESCAPE:
      begin
        Close;
        Key := 0;
      end;
    VK_UP:
      begin
        if FList.ItemIndex > 0 then
          FList.ItemIndex := FList.ItemIndex - 1;
        Key := 0;
      end;
    VK_DOWN:
      begin
        if FList.ItemIndex < High(FShown) then
          FList.ItemIndex := FList.ItemIndex + 1;
        Key := 0;
      end;
  end;
end;

procedure TGittanSymbolBar.ListKeyDown(Sender: TObject; var Key: word;
  Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        Pick;
        Key := 0;
      end;
    VK_ESCAPE:
      begin
        Close;
        Key := 0;
      end;
  end;
end;

procedure TGittanSymbolBar.ListDblClick(Sender: TObject);
begin
  Pick;
end;

function TGittanSymbolBar.CloseRect: TRect;
begin
  Result.Left := Width - Pad - CloseSize;
  Result.Top := (RowHeight - CloseSize) div 2;
  Result.Right := Result.Left + CloseSize;
  Result.Bottom := Result.Top + CloseSize;
end;

{ The field on the left of the top row, the cross on its right; the
  list under them, over the full width. }
procedure TGittanSymbolBar.Resize;
begin
  inherited Resize;
  { The constructor resizes before the children exist. }
  if (FEdit = nil) or (FList = nil) then
    Exit;
  FEdit.Left := Pad;
  FEdit.Top := (RowHeight - FEdit.Height) div 2;
  FEdit.Width := Min(EditWidth, Max(80, Width - 3 * Pad - CloseSize));
  FList.Left := Pad;
  FList.Top := RowHeight;
  FList.Width := Max(10, Width - 2 * Pad);
  FList.Height := Max(10, Height - RowHeight - Pad);
end;

procedure TGittanSymbolBar.Paint;
var
  R: TRect;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := FLine;
  Canvas.Line(0, Height - 1, Width, Height - 1);
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

procedure TGittanSymbolBar.MouseMove(Shift: TShiftState; X, Y: integer);
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

procedure TGittanSymbolBar.MouseLeave;
begin
  inherited MouseLeave;
  if FCloseHot then
  begin
    FCloseHot := False;
    Invalidate;
  end;
end;

procedure TGittanSymbolBar.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button = mbLeft) and CloseRect.Contains(Point(X, Y)) then
    Close;
end;

end.
