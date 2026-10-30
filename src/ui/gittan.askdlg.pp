unit gittan.askdlg;

{** Gittan's own dialogs, in place of the LCL's QuestionDlg, MessageDlg,
  InputQuery and InputBox, which on Cocoa laid a message out on one line
  as wide as the screen allowed, put a glyph on every button and set the
  buttons in the middle. These are built in code like the Who Commits
  dialog: a fixed width the text wraps in, an icon for the kind at the
  left (a warning triangle, an error disc, else the mark of gittan.dialogicon),
  plain buttons at the right in the platform's order, and for input a
  label over each field and a line in red under them saying why OK is
  off. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs, Graphics;

type
  {** Checks the fields of AskInput as they are typed: '' when they may
    be taken, else why not, which shows in red under the fields while OK
    is off. }
  TGittanAskCheck = function(const AValues: array of string): string of object;

{** Asks AMsg under ATitle and answers the modal result of the button
  pressed. AButtons are as QuestionDlg takes them: a modal result, then
  its caption (the usual one for mrOK, mrCancel, mrYes, mrNo and the like
  when left out), then 'IsDefault' or 'IsCancel'. Without a default the
  first button is; without a cancel the mrCancel one is, and Escape
  answers mrCancel when there is none. 'NoCancel' after any button
  leaves Escape and the close box nothing to do: a button must be
  pressed. }
function AskDlg(const ATitle, AMsg: string; AKind: TMsgDlgType;
  const AButtons: array of const): TModalResult;

{** AskDlg with QuestionDlg's help context or keyword, which it does not
  use, so a call to QuestionDlg changes in its name alone. }
function AskDlg(const ATitle, AMsg: string; AKind: TMsgDlgType;
  const AButtons: array of const; AHelpContext: longint): TModalResult;
function AskDlg(const ATitle, AMsg: string; AKind: TMsgDlgType;
  const AButtons: array of const; const AHelpKeyword: string): TModalResult;

{** Tells AMsg under ATitle (the application's title when empty), with
  OK. }
procedure TellDlg(const ATitle, AMsg: string; AKind: TMsgDlgType);

{** Asks for the texts of APrompts (a label over each field) under
  ATitle, with ANote, when given, above them; AValues come in as the
  fields start and go out trimmed of nothing, as typed. OK, named
  AOkCaption when given, is off while the first field is blank or ACheck
  says why the fields cannot be taken; with AOptional a blank first
  field is taken too. The field APathField holds a path and shows its
  end (ShowPathEnd). True when OK was pressed. }
function AskInput(const ATitle, ANote: string; const APrompts: array of string;
  var AValues: array of string; ACheck: TGittanAskCheck = nil;
  const AOkCaption: string = ''; AOptional: boolean = False;
  APathField: integer = -1): boolean;

{** AskInput with one field; AValue goes out as typed. }
function AskText(const ATitle, APrompt: string; var AValue: string;
  ACheck: TGittanAskCheck = nil; const AOkCaption: string = '';
  const ANote: string = ''; AOptional: boolean = False): boolean;

implementation

uses
  Math, Types, LCLType, gittan.dialogicon, gittan.pathfield
  {$IFDEF LCLCocoa}, gittan.titlebar{$ENDIF};

resourcestring
  rsAskOK = 'OK';
  rsAskCancel = 'Cancel';
  rsAskYes = 'Yes';
  rsAskNo = 'No';
  rsAskAbort = 'Abort';
  rsAskRetry = 'Retry';
  rsAskIgnore = 'Ignore';
  rsAskAll = 'All';
  rsAskYesToAll = 'Yes to All';
  rsAskNoToAll = 'No to All';
  rsAskClose = 'Close';

const
  DialogWidth = 460;
  Margin = 16;
  IconSize = 48;
  { The icon's room at the left, as a system dialog has it: its own
    margin, and the gap to the text. }
  IconLeft = 22;
  IconGap = 18;
  ButtonMinWidth = 84;
  ButtonGap = 8;
  FieldGap = 10;
  { The space over the first line of text and the icon. On macOS the
    hidden title bar's strip is over it already, and the title is the
    first line, in bold (AlertHeading), as a system alert has it. }
  {$IFDEF LCLCocoa}
  TopGap = 2;
  AlertHeading = True;
  {$ELSE}
  TopGap = Margin;
  AlertHeading = False;
  {$ENDIF}
  HeadingGap = 4;
  { The right and bottom edges. On macOS the hidden title bar's strip
    leaves some 30 points over the title, so the other edges get as
    much as the icon has at the left, which evens them out. }
  {$IFDEF LCLCocoa}
  EdgeGap = IconLeft;
  {$ELSE}
  EdgeGap = Margin;
  {$ENDIF}

type
  TAskButton = record
    Caption: string;
    Result: TModalResult;
  end;

  { TAskForm }

  TAskForm = class(TForm)
  private
    FKind: TMsgDlgType;
    FNextTop: integer;
    FEdits: array of TEdit;
    FError: TLabel;
    FOk: TButton;
    FButtonRow: TPanel;
    FCheck: TGittanAskCheck;
    FOptional: boolean;
    FPathField: integer;
    FCancelResult: TModalResult;
    FNoCancel, FPressed: boolean;
    function NextTop: integer;
    function IconRect: TRect;
    procedure FieldChange(Sender: TObject);
    procedure AddText(const AText: string; ABold: boolean; AGap: integer = FieldGap);
    procedure AddButtons(const AButtons: array of TAskButton; ADefault, ACancel: integer);
    procedure ButtonClick(Sender: TObject);
  protected
    procedure KeyDown(var Key: word; Shift: TShiftState); override;
    procedure Paint; override;
    procedure CreateWnd; override;
    procedure DoShow; override;
  public
    function CloseQuery: boolean; override;
    constructor CreateAsk(const ATitle: string; AKind: TMsgDlgType);
  end;

function StdCaption(AResult: TModalResult): string;
begin
  case AResult of
    mrOK: Result := rsAskOK;
    mrCancel: Result := rsAskCancel;
    mrYes: Result := rsAskYes;
    mrNo: Result := rsAskNo;
    mrAbort: Result := rsAskAbort;
    mrRetry: Result := rsAskRetry;
    mrIgnore: Result := rsAskIgnore;
    mrAll: Result := rsAskAll;
    mrYesToAll: Result := rsAskYesToAll;
    mrNoToAll: Result := rsAskNoToAll;
    mrClose: Result := rsAskClose;
  else
    Result := '';
  end;
end;

function ConstString(const AValue: TVarRec; out AText: string): boolean;
begin
  Result := True;
  case AValue.VType of
    vtString: AText := AValue.VString^;
    vtAnsiString: AText := AnsiString(AValue.VAnsiString);
    vtUnicodeString: AText := UTF8Encode(UnicodeString(AValue.VUnicodeString));
    vtWideString: AText := UTF8Encode(WideString(AValue.VWideString));
    vtChar: AText := AValue.VChar;
    vtPChar: AText := AValue.VPChar;
  else
    Result := False;
  end;
end;

{ ---------------------------------------------------------------------------
  The form
  --------------------------------------------------------------------------- }

constructor TAskForm.CreateAsk(const ATitle: string; AKind: TMsgDlgType);
begin
  inherited CreateNew(Screen.ActiveForm);
  Caption := ATitle;
  FKind := AKind;
  FCancelResult := mrCancel;
  FPathField := -1;
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  KeyPreview := True;
  Constraints.MinWidth := Scale96ToScreen(DialogWidth);
  Constraints.MaxWidth := Scale96ToScreen(DialogWidth);
  AutoSize := True;
  if AlertHeading and (ATitle <> '') then
    AddText(ATitle, True);
end;

{ The window, once made, looks as a system alert on macOS. }
procedure TAskForm.CreateWnd;
begin
  inherited CreateWnd;
  {$IFDEF LCLCocoa}
  MakeAlertWindow(Handle);
  {$ENDIF}
end;

{ The alTop controls keep the order of their tops. }
function TAskForm.NextTop: integer;
begin
  Inc(FNextTop, 1000);
  Result := FNextTop;
end;

{ A label right of the icon, wrapped at the dialog's width; the first
  keeps at least the icon's height under it, so the buttons clear it. }
procedure TAskForm.AddText(const AText: string; ABold: boolean; AGap: integer);
var
  Lbl: TLabel;
begin
  Lbl := TLabel.Create(Self);
  Lbl.ShowAccelChar := False;
  Lbl.Caption := AText;
  Lbl.WordWrap := True;
  Lbl.Align := alTop;
  Lbl.Top := NextTop;
  Lbl.BorderSpacing.Left := Scale96ToScreen(IconLeft + IconSize + IconGap);
  Lbl.BorderSpacing.Right := Scale96ToScreen(EdgeGap);
  if FNextTop = 1000 then
    Lbl.BorderSpacing.Top := Scale96ToScreen(TopGap)
  else
    Lbl.BorderSpacing.Top := Scale96ToScreen(AGap);
  if ABold then
    Lbl.Font.Style := [fsBold];
  Lbl.Parent := Self;
end;

{ The buttons at the right: on macOS the default rightmost with the
  cancel one left of it and the rest further left, as an alert has them;
  elsewhere the default first and the cancel one last. }
procedure TAskForm.AddButtons(const AButtons: array of TAskButton; ADefault, ACancel: integer);
var
  Row: TPanel;
  Order: array of integer;
  i, n: integer;
  B: TButton;

  procedure Put(AIndex: integer);
  begin
    if AIndex < 0 then
      Exit;
    Order[n] := AIndex;
    Inc(n);
  end;

begin
  Row := TPanel.Create(Self);
  Row.BevelOuter := bvNone;
  Row.AutoSize := True;
  Row.Align := alTop;
  Row.Top := NextTop;
  { Around would add to each side's own spacing: each is set alone. }
  Row.BorderSpacing.Left := Scale96ToScreen(Margin);
  Row.BorderSpacing.Right := Scale96ToScreen(EdgeGap);
  Row.BorderSpacing.Bottom := Scale96ToScreen(EdgeGap);
  Row.BorderSpacing.Top := Scale96ToScreen(Margin + 4);
  Row.Constraints.MinHeight := 1;
  Row.Parent := Self;
  FButtonRow := Row;
  SetLength(Order, Length(AButtons));
  n := 0;
  {$IFDEF DARWIN}
  for i := 0 to High(AButtons) do
    if (i <> ADefault) and (i <> ACancel) then
      Put(i);
  if ACancel <> ADefault then
    Put(ACancel);
  Put(ADefault);
  {$ELSE}
  Put(ADefault);
  for i := 0 to High(AButtons) do
    if (i <> ADefault) and (i <> ACancel) then
      Put(i);
  if ACancel <> ADefault then
    Put(ACancel);
  {$ENDIF}
  { Of the alRight buttons the one furthest left goes rightmost, so the
    last in Order, Left the largest, is the rightmost. }
  for i := 0 to n - 1 do
  begin
    B := TButton.Create(Self);
    B.Caption := AButtons[Order[i]].Caption;
    B.ModalResult := AButtons[Order[i]].Result;
    B.OnClick := @ButtonClick;
    B.AutoSize := True;
    B.Constraints.MinWidth := Scale96ToScreen(ButtonMinWidth);
    B.Align := alRight;
    B.Left := (i + 1) * 1000;
    B.BorderSpacing.Left := Scale96ToScreen(ButtonGap);
    B.Default := Order[i] = ADefault;
    B.Cancel := Order[i] = ACancel;
    B.Parent := Row;
    if Order[i] = ADefault then
      FOk := B;
  end;
  if ACancel >= 0 then
    FCancelResult := AButtons[ACancel].Result;
end;

{ Escape answers the cancel button's result, mrCancel without one; a
  cancel button takes the key itself. Under 'NoCancel' it does nothing. }
procedure TAskForm.KeyDown(var Key: word; Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and (Shift = []) then
  begin
    Key := 0;
    if not FNoCancel then
      ModalResult := FCancelResult;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

{ A button was pressed: the answer is its ModalResult, which the LCL
  sets after OnClick. }
procedure TAskForm.ButtonClick(Sender: TObject);
begin
  FPressed := True;
end;

{ Under 'NoCancel' the close box does not close the dialog. The LCL's
  Close sets a modal form's ModalResult to mrCancel without asking, and
  the modal loop asks here afterwards (CloseModal), so the test is
  whether a button was pressed, not ModalResult; a refusal clears
  ModalResult and the dialog stays. }
function TAskForm.CloseQuery: boolean;
begin
  Result := inherited CloseQuery;
  if FNoCancel and not FPressed then
    Result := False;
end;

{ The icon in the middle of the text's height over the buttons, never
  above the top margin. It is painted on the form, not a control of its
  own: a control would count in the form's AutoSize, and moving it down
  made the form taller, which moved the buttons and the icon again. }
function TAskForm.IconRect: TRect;
var
  S, IconTop, Room: integer;
begin
  S := Scale96ToScreen(IconSize);
  IconTop := Scale96ToScreen(TopGap);
  if FButtonRow <> nil then
  begin
    Room := FButtonRow.Top - FButtonRow.BorderSpacing.Top - IconTop;
    Inc(IconTop, Max(0, (Room - S) div 2));
  end;
  Result := Rect(Scale96ToScreen(IconLeft), IconTop, Scale96ToScreen(IconLeft) + S, IconTop + S);
end;

procedure TAskForm.DoShow;
begin
  inherited DoShow;
  if Length(FEdits) > 0 then
  begin
    ActiveControl := FEdits[0];
    FEdits[0].SelectAll;
    if (FPathField >= 0) and (FPathField <= High(FEdits)) then
      ShowPathEnd(FEdits[FPathField]);
  end
  else if FOk <> nil then
    ActiveControl := FOk;
end;

{ A warning is an amber triangle, an error a red disc, both with an
  exclamation mark; a question or a note has Gittan's mark
  (DialogIcon), in the screen's pixels. }
procedure TAskForm.Paint;
var
  C: TCanvas;
  R: TRect;
  S, Mid, W, X, Y: integer;
  Fill: TColor;
begin
  inherited Paint;
  C := Canvas;
  R := IconRect;
  S := R.Width;
  X := R.Left;
  Y := R.Top;
  Mid := X + S div 2;
  if FKind in [mtWarning, mtError] then
  begin
    if FKind = mtWarning then
      Fill := RGBToColor(245, 166, 35)
    else
      Fill := RGBToColor(229, 72, 77);
    C.Pen.Style := psClear;
    C.Brush.Style := bsSolid;
    C.Brush.Color := Fill;
    if FKind = mtWarning then
      C.Polygon([Point(Mid, Y + S div 12), Point(X + S - S div 24, Y + S - S div 8),
        Point(X + S div 24, Y + S - S div 8)])
    else
      C.Ellipse(X + S div 12, Y + S div 12, X + S - S div 12, Y + S - S div 12);
    C.Brush.Color := clWhite;
    W := Max(3, S div 12);
    if FKind = mtWarning then
    begin
      C.RoundRect(Mid - W div 2, Y + S * 9 div 24, Mid + W div 2 + 1, Y + S * 16 div 24, W, W);
      C.Ellipse(Mid - W div 2, Y + S * 18 div 24, Mid + W div 2 + 1, Y + S * 18 div 24 + W + 1);
    end
    else
    begin
      C.RoundRect(Mid - W div 2, Y + S * 6 div 24, Mid + W div 2 + 1, Y + S * 14 div 24, W, W);
      C.Ellipse(Mid - W div 2, Y + S * 16 div 24, Mid + W div 2 + 1, Y + S * 16 div 24 + W + 1);
    end;
    C.Pen.Style := psSolid;
    Exit;
  end;
  C.StretchDraw(R, DialogIcon(Round(S * GetCanvasScaleFactor)));
end;

procedure TAskForm.FieldChange(Sender: TObject);
var
  Values: array of string;
  i: integer;
  Why: string;
begin
  if FOk = nil then
    Exit;
  Values := nil;
  SetLength(Values, Length(FEdits));
  for i := 0 to High(FEdits) do
    Values[i] := FEdits[i].Text;
  Why := '';
  if Assigned(FCheck) and (FOptional or (Trim(Values[0]) <> '')) then
    Why := FCheck(Values);
  FOk.Enabled := (FOptional or (Trim(Values[0]) <> '')) and (Why = '');
  FError.Caption := Why;
  { A hidden alTop control shown again goes last, under the buttons:
    it is put back over them. }
  if (Why <> '') and not FError.Visible then
  begin
    FError.Visible := True;
    FError.Top := FButtonRow.Top - 1;
  end
  else if Why = '' then
    FError.Visible := False;
end;

{ ---------------------------------------------------------------------------
  The calls
  --------------------------------------------------------------------------- }

function AskDlg(const ATitle, AMsg: string; AKind: TMsgDlgType;
  const AButtons: array of const): TModalResult;
var
  F: TAskForm;
  Buttons: array of TAskButton;
  i, n, Default, Cancel: integer;
  S: string;
  Named, NoCancel: boolean;
begin
  Buttons := nil;
  NoCancel := False;
  Default := -1;
  Cancel := -1;
  i := Low(AButtons);
  while i <= High(AButtons) do
  begin
    if AButtons[i].VType <> vtInteger then
      raise Exception.Create('AskDlg: a modal result expected at ' + IntToStr(i));
    n := Length(Buttons);
    SetLength(Buttons, n + 1);
    Buttons[n].Result := AButtons[i].VInteger;
    Buttons[n].Caption := '';
    Named := False;
    Inc(i);
    while (i <= High(AButtons)) and ConstString(AButtons[i], S) do
    begin
      if SameText(S, 'IsDefault') then
        Default := n
      else if SameText(S, 'IsCancel') then
        Cancel := n
      else if SameText(S, 'NoCancel') then
        NoCancel := True
      else if not Named then
      begin
        Buttons[n].Caption := S;
        Named := True;
      end;
      Inc(i);
    end;
    if Buttons[n].Caption = '' then
      Buttons[n].Caption := StdCaption(Buttons[n].Result);
  end;
  if Length(Buttons) = 0 then
  begin
    SetLength(Buttons, 1);
    Buttons[0].Result := mrOK;
    Buttons[0].Caption := rsAskOK;
  end;
  if Cancel < 0 then
    for i := 0 to High(Buttons) do
      if Buttons[i].Result = mrCancel then
        Cancel := i;
  if Default < 0 then
    Default := 0;
  F := TAskForm.CreateAsk(ATitle, AKind);
  try
    F.AddText(AMsg, False, HeadingGap);
    F.AddButtons(Buttons, Default, Cancel);
    F.FNoCancel := NoCancel;
    Result := F.ShowModal;
    if Result = mrNone then
      Result := F.FCancelResult;
  finally
    F.Free;
  end;
end;

function AskDlg(const ATitle, AMsg: string; AKind: TMsgDlgType;
  const AButtons: array of const; AHelpContext: longint): TModalResult;
begin
  Result := AskDlg(ATitle, AMsg, AKind, AButtons);
end;

function AskDlg(const ATitle, AMsg: string; AKind: TMsgDlgType;
  const AButtons: array of const; const AHelpKeyword: string): TModalResult;
begin
  Result := AskDlg(ATitle, AMsg, AKind, AButtons);
end;

procedure TellDlg(const ATitle, AMsg: string; AKind: TMsgDlgType);
var
  Title: string;
begin
  Title := ATitle;
  if Title = '' then
    Title := Application.Title;
  AskDlg(Title, AMsg, AKind, [mrOK, 'IsDefault', 'IsCancel']);
end;

function AskInput(const ATitle, ANote: string; const APrompts: array of string;
  var AValues: array of string; ACheck: TGittanAskCheck; const AOkCaption: string;
  AOptional: boolean; APathField: integer): boolean;
var
  F: TAskForm;
  Buttons: array[0..1] of TAskButton;
  i: integer;
  Edit: TEdit;
begin
  F := TAskForm.CreateAsk(ATitle, mtConfirmation);
  try
    if ANote <> '' then
      F.AddText(ANote, False, HeadingGap);
    SetLength(F.FEdits, Length(APrompts));
    for i := 0 to High(APrompts) do
    begin
      F.AddText(APrompts[i], False);
      Edit := TEdit.Create(F);
      Edit.Align := alTop;
      Edit.Top := F.NextTop;
      Edit.BorderSpacing.Left := F.Scale96ToScreen(IconLeft + IconSize + IconGap);
      Edit.BorderSpacing.Right := F.Scale96ToScreen(EdgeGap);
      Edit.BorderSpacing.Top := F.Scale96ToScreen(4);
      if i <= High(AValues) then
        Edit.Text := AValues[i];
      Edit.OnChange := @F.FieldChange;
      Edit.Parent := F;
      F.FEdits[i] := Edit;
    end;
    F.FError := TLabel.Create(F);
    F.FError.WordWrap := True;
    F.FError.Align := alTop;
    F.FError.Top := F.NextTop;
    F.FError.BorderSpacing.Left := F.Scale96ToScreen(IconLeft + IconSize + IconGap);
    F.FError.BorderSpacing.Right := F.Scale96ToScreen(EdgeGap);
    F.FError.BorderSpacing.Top := F.Scale96ToScreen(6);
    F.FError.Font.Color := RGBToColor(229, 72, 77);
    F.FError.Visible := False;
    F.FError.Parent := F;
    F.FCheck := ACheck;
    F.FOptional := AOptional;
    F.FPathField := APathField;
    if AOkCaption <> '' then
      Buttons[0].Caption := AOkCaption
    else
      Buttons[0].Caption := rsAskOK;
    Buttons[0].Result := mrOK;
    Buttons[1].Caption := rsAskCancel;
    Buttons[1].Result := mrCancel;
    F.AddButtons(Buttons, 0, 1);
    F.FieldChange(nil);
    Result := F.ShowModal = mrOK;
    if Result then
      for i := 0 to Min(High(AValues), High(F.FEdits)) do
        AValues[i] := F.FEdits[i].Text;
  finally
    F.Free;
  end;
end;

function AskText(const ATitle, APrompt: string; var AValue: string;
  ACheck: TGittanAskCheck; const AOkCaption: string; const ANote: string;
  AOptional: boolean): boolean;
var
  Values: array of string;
begin
  Values := nil;
  SetLength(Values, 1);
  Values[0] := AValue;
  Result := AskInput(ATitle, ANote, [APrompt], Values, ACheck, AOkCaption, AOptional);
  if Result then
    AValue := Values[0];
end;

end.
