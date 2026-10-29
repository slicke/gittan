unit gittan.askdlg;

{** Gittan's own dialogs, in place of the LCL's QuestionDlg, MessageDlg,
  InputQuery and InputBox, which on Cocoa laid a message out on one line
  as wide as the screen allowed, put a glyph on every button and set the
  buttons in the middle. These are built in code like the Who Commits
  dialog: a fixed width the text wraps in, an icon for the kind at the
  left (a warning triangle, an error disc, else the application's icon),
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
  answers mrCancel when there is none. }
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
  field is taken too. True when OK was pressed. }
function AskInput(const ATitle, ANote: string; const APrompts: array of string;
  var AValues: array of string; ACheck: TGittanAskCheck = nil;
  const AOkCaption: string = ''; AOptional: boolean = False): boolean;

{** AskInput with one field; AValue goes out as typed. }
function AskText(const ATitle, APrompt: string; var AValue: string;
  ACheck: TGittanAskCheck = nil; const AOkCaption: string = '';
  const ANote: string = ''; AOptional: boolean = False): boolean;

implementation

uses
  Math, Types, LCLType, gittan.app;

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
  IconGap = 14;
  ButtonMinWidth = 84;
  ButtonGap = 8;
  FieldGap = 10;

type
  TAskButton = record
    Caption: string;
    Result: TModalResult;
  end;

  { TAskForm }

  TAskForm = class(TForm)
  private
    FKind: TMsgDlgType;
    FIconBox: TPaintBox;
    FIconBitmap: TBitmap;
    FNextTop: integer;
    FEdits: array of TEdit;
    FError: TLabel;
    FOk: TButton;
    FButtonRow: TPanel;
    FCheck: TGittanAskCheck;
    FOptional: boolean;
    FCancelResult: TModalResult;
    function NextTop: integer;
    procedure IconPaint(Sender: TObject);
    procedure FieldChange(Sender: TObject);
    procedure AddText(const AText: string; ABold: boolean);
    procedure AddButtons(const AButtons: array of TAskButton; ADefault, ACancel: integer);
  protected
    procedure KeyDown(var Key: word; Shift: TShiftState); override;
    procedure DoShow; override;
  public
    constructor CreateAsk(const ATitle: string; AKind: TMsgDlgType);
    destructor Destroy; override;
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
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  KeyPreview := True;
  Constraints.MinWidth := Scale96ToScreen(DialogWidth);
  Constraints.MaxWidth := Scale96ToScreen(DialogWidth);
  AutoSize := True;
  FIconBox := TPaintBox.Create(Self);
  FIconBox.SetBounds(Scale96ToScreen(Margin), Scale96ToScreen(Margin),
    Scale96ToScreen(IconSize), Scale96ToScreen(IconSize));
  FIconBox.OnPaint := @IconPaint;
  FIconBox.Parent := Self;
end;

destructor TAskForm.Destroy;
begin
  FIconBitmap.Free;
  inherited Destroy;
end;

{ The alTop controls keep the order of their tops. }
function TAskForm.NextTop: integer;
begin
  Inc(FNextTop, 1000);
  Result := FNextTop;
end;

{ A label right of the icon, wrapped at the dialog's width; the first
  keeps at least the icon's height under it, so the buttons clear it. }
procedure TAskForm.AddText(const AText: string; ABold: boolean);
var
  Lbl: TLabel;
begin
  Lbl := TLabel.Create(Self);
  Lbl.Caption := AText;
  Lbl.WordWrap := True;
  Lbl.Align := alTop;
  Lbl.Top := NextTop;
  Lbl.BorderSpacing.Left := Scale96ToScreen(Margin + IconSize + IconGap);
  Lbl.BorderSpacing.Right := Scale96ToScreen(Margin);
  if FNextTop = 1000 then
    Lbl.BorderSpacing.Top := Scale96ToScreen(Margin)
  else
    Lbl.BorderSpacing.Top := Scale96ToScreen(FieldGap);
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
  Row.BorderSpacing.Around := Scale96ToScreen(Margin);
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
  cancel button takes the key itself. }
procedure TAskForm.KeyDown(var Key: word; Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and (Shift = []) then
  begin
    Key := 0;
    ModalResult := FCancelResult;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TAskForm.DoShow;
begin
  inherited DoShow;
  if Length(FEdits) > 0 then
  begin
    ActiveControl := FEdits[0];
    FEdits[0].SelectAll;
  end
  else if FOk <> nil then
    ActiveControl := FOk;
end;

{ A warning is an amber triangle, an error a red disc, both with an
  exclamation mark; a question or a note has the application's icon, in
  the screen's pixels. }
procedure TAskForm.IconPaint(Sender: TObject);
var
  C: TCanvas;
  S, Mid, W: integer;
  AppIcon: TIcon;
  Fill: TColor;
begin
  C := FIconBox.Canvas;
  S := FIconBox.Width;
  Mid := S div 2;
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
      C.Polygon([Point(Mid, S div 12), Point(S - S div 24, S - S div 8),
        Point(S div 24, S - S div 8)])
    else
      C.Ellipse(S div 12, S div 12, S - S div 12, S - S div 12);
    C.Brush.Color := clWhite;
    W := Max(3, S div 12);
    if FKind = mtWarning then
    begin
      C.RoundRect(Mid - W div 2, S * 9 div 24, Mid + W div 2 + 1, S * 16 div 24, W, W);
      C.Ellipse(Mid - W div 2, S * 18 div 24, Mid + W div 2 + 1, S * 18 div 24 + W + 1);
    end
    else
    begin
      C.RoundRect(Mid - W div 2, S * 6 div 24, Mid + W div 2 + 1, S * 14 div 24, W, W);
      C.Ellipse(Mid - W div 2, S * 16 div 24, Mid + W div 2 + 1, S * 16 div 24 + W + 1);
    end;
    C.Pen.Style := psSolid;
    Exit;
  end;
  AppIcon := App.Icon;
  if (AppIcon = nil) or AppIcon.Empty then
    Exit;
  if FIconBitmap = nil then
  begin
    AppIcon.Current := AppIcon.GetBestIndexForSize(Size(Round(S * GetCanvasScaleFactor),
      Round(S * GetCanvasScaleFactor)));
    FIconBitmap := TBitmap.Create;
    FIconBitmap.LoadFromRawImage(AppIcon.RawImage, False);
  end;
  C.StretchDraw(Rect(0, 0, S, S), FIconBitmap);
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
  Named: boolean;
begin
  Buttons := nil;
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
    F.AddText(AMsg, False);
    F.AddButtons(Buttons, Default, Cancel);
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
  AOptional: boolean): boolean;
var
  F: TAskForm;
  Buttons: array[0..1] of TAskButton;
  i: integer;
  Edit: TEdit;
begin
  F := TAskForm.CreateAsk(ATitle, mtConfirmation);
  try
    if ANote <> '' then
      F.AddText(ANote, False);
    SetLength(F.FEdits, Length(APrompts));
    for i := 0 to High(APrompts) do
    begin
      F.AddText(APrompts[i], False);
      Edit := TEdit.Create(F);
      Edit.Align := alTop;
      Edit.Top := F.NextTop;
      Edit.BorderSpacing.Left := F.Scale96ToScreen(Margin + IconSize + IconGap);
      Edit.BorderSpacing.Right := F.Scale96ToScreen(Margin);
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
    F.FError.BorderSpacing.Left := F.Scale96ToScreen(Margin + IconSize + IconGap);
    F.FError.BorderSpacing.Right := F.Scale96ToScreen(Margin);
    F.FError.BorderSpacing.Top := F.Scale96ToScreen(6);
    F.FError.Font.Color := RGBToColor(229, 72, 77);
    F.FError.Visible := False;
    F.FError.Parent := F;
    F.FCheck := ACheck;
    F.FOptional := AOptional;
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
