unit gittan.coauthorsdlg;

{** The dialog of the people credited in the next commit with a
  Co-authored-by line each: a list with a box per person, those chosen
  ticked, then the people credited before and the repository's recent
  authors to tick, and a field to add someone as "Name <e-mail>". }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, StdCtrls, ExtCtrls, CheckLst;

{** Asks who the co-authors are, starting with AChosen ticked and
  AKnown (the people credited before, the repository's recent authors)
  to tick, each person once. True when OK was pressed, with the ticked
  people in AChosen, in the list's order. }
function ChooseCoAuthors(var AChosen: TStringArray; const AKnown: TStringArray): boolean;

{** Whether AText names a person as "Name <e-mail>": a name, then an
  address with an @ in angle brackets. }
function IsPerson(const AText: string): boolean;

implementation

uses
  LCLType, Graphics;

resourcestring
  rsCoAuthorsDlgTitle = 'Co-authors';
  rsCoAuthorsDlgHint = 'Each person ticked is credited in the commit with a Co-authored-by ' +
    'line. Add someone as Name <e-mail>.';
  rsCoAuthorsDlgAdd = 'Add';
  rsCoAuthorsDlgPerson = 'Name <e-mail>';
  rsCoAuthorsDlgOK = 'OK';
  rsCancel = 'Cancel';

const
  DialogWidth = 440;
  Margin = 12;
  ListRows = 8;

type

  { TCoAuthorsForm }

  TCoAuthorsForm = class(TForm)
  private
    FList: TCheckListBox;
    FPerson: TEdit;
    FAddButton, FOKButton: TButton;
    FNextTop: integer;
    procedure AddClick(Sender: TObject);
    procedure PersonChange(Sender: TObject);
    procedure PersonKeyPress(Sender: TObject; var Key: char);
    procedure Put(const APerson: string; AChecked: boolean);
  protected
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

function IsPerson(const AText: string): boolean;
var
  S: string;
  i: integer;
begin
  S := Trim(AText);
  i := Pos('<', S);
  Result := (i > 1) and (Trim(Copy(S, 1, i - 1)) <> '') and (S[Length(S)] = '>') and
    (Pos('@', Copy(S, i + 1, Length(S) - i - 1)) > 1) and
    (Pos('>', Copy(S, i + 1, MaxInt)) = Length(S) - i);
end;

constructor TCoAuthorsForm.Create(AOwner: TComponent);
var
  Note: TLabel;
  Row, Buttons: TPanel;
  Cancel: TButton;
begin
  inherited CreateNew(AOwner);
  Caption := rsCoAuthorsDlgTitle;
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  Constraints.MinWidth := Scale96ToScreen(DialogWidth);
  Constraints.MaxWidth := Scale96ToScreen(DialogWidth);
  AutoSize := True;

  Note := TLabel.Create(Self);
  Note.Caption := rsCoAuthorsDlgHint;
  Note.WordWrap := True;
  Note.Align := alTop;
  Note.BorderSpacing.Around := Scale96ToScreen(Margin);
  Note.Top := 0;
  Note.Parent := Self;

  FList := TCheckListBox.Create(Self);
  FList.Align := alTop;
  Inc(FNextTop, 1000);
  FList.Top := FNextTop;
  FList.Height := Scale96ToScreen(ListRows * 22);
  FList.BorderSpacing.Left := Scale96ToScreen(Margin);
  FList.BorderSpacing.Right := Scale96ToScreen(Margin);
  FList.Parent := Self;

  { The field and Add on one row under the list. }
  Row := TPanel.Create(Self);
  Row.BevelOuter := bvNone;
  Row.Align := alTop;
  Inc(FNextTop, 1000);
  Row.Top := FNextTop;
  Row.AutoSize := True;
  Row.BorderSpacing.Left := Scale96ToScreen(Margin);
  Row.BorderSpacing.Right := Scale96ToScreen(Margin);
  Row.BorderSpacing.Top := Scale96ToScreen(8);
  Row.Parent := Self;
  FAddButton := TButton.Create(Self);
  FAddButton.Caption := rsCoAuthorsDlgAdd;
  FAddButton.AutoSize := True;
  FAddButton.Constraints.MinWidth := Scale96ToScreen(72);
  FAddButton.Align := alRight;
  FAddButton.Enabled := False;
  FAddButton.OnClick := @AddClick;
  FAddButton.Parent := Row;
  FPerson := TEdit.Create(Self);
  FPerson.TextHint := rsCoAuthorsDlgPerson;
  FPerson.Align := alClient;
  FPerson.BorderSpacing.Right := Scale96ToScreen(8);
  FPerson.OnChange := @PersonChange;
  FPerson.OnKeyPress := @PersonKeyPress;
  FPerson.Parent := Row;

  { OK on the right on macOS, Cancel on the right elsewhere. }
  Buttons := TPanel.Create(Self);
  Buttons.BevelOuter := bvNone;
  Buttons.AutoSize := True;
  Buttons.Align := alTop;
  Inc(FNextTop, 1000);
  Buttons.Top := FNextTop;
  Buttons.BorderSpacing.Around := Scale96ToScreen(Margin);
  Buttons.BorderSpacing.Top := Scale96ToScreen(16);
  Buttons.Parent := Self;
  FOKButton := TButton.Create(Self);
  FOKButton.Caption := rsCoAuthorsDlgOK;
  FOKButton.ModalResult := mrOK;
  FOKButton.Default := True;
  FOKButton.AutoSize := True;
  FOKButton.Constraints.MinWidth := Scale96ToScreen(84);
  FOKButton.Align := alRight;
  FOKButton.Parent := Buttons;
  Cancel := TButton.Create(Self);
  Cancel.Caption := rsCancel;
  Cancel.ModalResult := mrCancel;
  Cancel.Cancel := True;
  Cancel.AutoSize := True;
  Cancel.Constraints.MinWidth := Scale96ToScreen(84);
  Cancel.Align := alRight;
  Cancel.Parent := Buttons;
  {$IFDEF DARWIN}
  Cancel.Left := 0;
  FOKButton.Left := 1000;
  {$ELSE}
  FOKButton.Left := 0;
  Cancel.Left := 1000;
  {$ENDIF}
  Cancel.BorderSpacing.Left := Scale96ToScreen(8);
  FOKButton.BorderSpacing.Left := Scale96ToScreen(8);
end;

{ APerson into the list once: ticked as asked, or ticked when it is
  there already and AChecked says so. }
procedure TCoAuthorsForm.Put(const APerson: string; AChecked: boolean);
var
  i: integer;
begin
  if Trim(APerson) = '' then
    Exit;
  i := FList.Items.IndexOf(Trim(APerson));
  if i < 0 then
    i := FList.Items.Add(Trim(APerson));
  if AChecked then
    FList.Checked[i] := True;
end;

{ The person typed goes into the list, ticked, and the field empties
  for the next one. }
procedure TCoAuthorsForm.AddClick(Sender: TObject);
begin
  if not IsPerson(FPerson.Text) then
    Exit;
  Put(FPerson.Text, True);
  FList.ItemIndex := FList.Items.IndexOf(Trim(FPerson.Text));
  FPerson.Text := '';
  FPerson.SetFocus;
end;

procedure TCoAuthorsForm.PersonChange(Sender: TObject);
begin
  FAddButton.Enabled := IsPerson(FPerson.Text);
end;

{ Return in the field adds, rather than pressing OK. }
procedure TCoAuthorsForm.PersonKeyPress(Sender: TObject; var Key: char);
begin
  if (Key = #13) and (Trim(FPerson.Text) <> '') then
  begin
    Key := #0;
    AddClick(nil);
  end;
end;

procedure TCoAuthorsForm.DoShow;
begin
  inherited DoShow;
  if FList.Items.Count = 0 then
    ActiveControl := FPerson
  else
    ActiveControl := FList;
end;

function ChooseCoAuthors(var AChosen: TStringArray; const AKnown: TStringArray): boolean;
var
  F: TCoAuthorsForm;
  i, n: integer;
begin
  F := TCoAuthorsForm.Create(Screen.ActiveForm);
  try
    for i := 0 to High(AChosen) do
      F.Put(AChosen[i], True);
    for i := 0 to High(AKnown) do
      F.Put(AKnown[i], False);
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      AChosen := nil;
      n := 0;
      for i := 0 to F.FList.Items.Count - 1 do
        if F.FList.Checked[i] then
        begin
          SetLength(AChosen, n + 1);
          AChosen[n] := F.FList.Items[i];
          Inc(n);
        end;
    end;
  finally
    F.Free;
  end;
end;

end.
