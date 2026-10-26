unit gittan.identitydlg;

{** The dialog of the name and e-mail commits are made under: the two
  fields and whether they are the repository's own or, as git suggests,
  the global ones for every repository. Save is off while either field
  is empty, since git commits with neither missing. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs;

{** Asks for the name and e-mail to commit under, starting with AName,
  AEmail and ALocal (the repository's own rather than the global ones).
  True when Save was pressed, with the trimmed choices in them. }
function ChooseIdentity(var AName, AEmail: string; var ALocal: boolean): boolean;

implementation

uses
  Graphics;

resourcestring
  rsIdentityDlgTitle = 'Who Commits?';
  rsIdentityDlgHint = 'Commits are made under this name and e-mail. Git keeps them in your ' +
    'global config, for every repository, unless this one has its own.';
  rsIdentityDlgName = 'Name';
  rsIdentityDlgEmail = 'E-mail';
  rsIdentityDlgLocal = 'Only for this repository';
  rsIdentityDlgSave = 'Save';
  rsCancel = 'Cancel';

const
  DialogWidth = 440;
  Margin = 12;
  LabelWidth = 64;

type

  { TIdentityForm }

  TIdentityForm = class(TForm)
  private
    FName, FEmail: TEdit;
    FLocal: TCheckBox;
    FSaveButton: TButton;
    FNextTop: integer;
    procedure Row(const ACaption: string; AEdit: TEdit);
    procedure Check(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TIdentityForm.Create(AOwner: TComponent);
var
  Note: TLabel;
  Buttons: TPanel;
  Cancel: TButton;
begin
  inherited CreateNew(AOwner);
  Caption := rsIdentityDlgTitle;
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  Constraints.MinWidth := Scale96ToScreen(DialogWidth);
  Constraints.MaxWidth := Scale96ToScreen(DialogWidth);
  AutoSize := True;

  Note := TLabel.Create(Self);
  Note.Caption := rsIdentityDlgHint;
  Note.WordWrap := True;
  Note.Align := alTop;
  Note.BorderSpacing.Around := Scale96ToScreen(Margin);
  Note.Top := 0;
  Note.Parent := Self;

  FName := TEdit.Create(Self);
  FName.OnChange := @Check;
  Row(rsIdentityDlgName, FName);
  FEmail := TEdit.Create(Self);
  FEmail.OnChange := @Check;
  Row(rsIdentityDlgEmail, FEmail);

  FLocal := TCheckBox.Create(Self);
  FLocal.Caption := rsIdentityDlgLocal;
  FLocal.Align := alTop;
  Inc(FNextTop, 1000);
  FLocal.Top := FNextTop;
  FLocal.BorderSpacing.Left := Scale96ToScreen(Margin + LabelWidth);
  FLocal.BorderSpacing.Right := Scale96ToScreen(Margin);
  FLocal.BorderSpacing.Top := Scale96ToScreen(4);
  FLocal.Parent := Self;

  { Save on the right on macOS, Cancel on the right elsewhere. }
  Buttons := TPanel.Create(Self);
  Buttons.BevelOuter := bvNone;
  Buttons.AutoSize := True;
  Buttons.Align := alTop;
  Inc(FNextTop, 1000);
  Buttons.Top := FNextTop;
  Buttons.BorderSpacing.Around := Scale96ToScreen(Margin);
  Buttons.BorderSpacing.Top := Scale96ToScreen(16);
  Buttons.Parent := Self;
  FSaveButton := TButton.Create(Self);
  FSaveButton.Caption := rsIdentityDlgSave;
  FSaveButton.ModalResult := mrOK;
  FSaveButton.Default := True;
  FSaveButton.AutoSize := True;
  FSaveButton.Constraints.MinWidth := Scale96ToScreen(84);
  FSaveButton.Align := alRight;
  FSaveButton.Parent := Buttons;
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
  FSaveButton.Left := 1000;
  {$ELSE}
  FSaveButton.Left := 0;
  Cancel.Left := 1000;
  {$ENDIF}
  Cancel.BorderSpacing.Left := Scale96ToScreen(8);
  FSaveButton.BorderSpacing.Left := Scale96ToScreen(8);
end;

{ A row under the ones before it: the caption in a column of its own,
  then AEdit filling the rest. }
procedure TIdentityForm.Row(const ACaption: string; AEdit: TEdit);
var
  Panel: TPanel;
  Lbl: TLabel;
begin
  Panel := TPanel.Create(Self);
  Panel.BevelOuter := bvNone;
  Panel.Align := alTop;
  Inc(FNextTop, 1000);
  Panel.Top := FNextTop;
  Panel.BorderSpacing.Left := Scale96ToScreen(Margin);
  Panel.BorderSpacing.Right := Scale96ToScreen(Margin);
  Panel.BorderSpacing.Bottom := Scale96ToScreen(6);
  Panel.AutoSize := True;
  Panel.Parent := Self;
  Lbl := TLabel.Create(Self);
  Lbl.Caption := ACaption;
  Lbl.AutoSize := False;
  Lbl.Width := Scale96ToScreen(LabelWidth);
  Lbl.Align := alLeft;
  Lbl.Layout := tlCenter;
  Lbl.Parent := Panel;
  AEdit.Align := alClient;
  AEdit.Parent := Panel;
end;

procedure TIdentityForm.DoShow;
begin
  inherited DoShow;
  if Trim(FName.Text) = '' then
    ActiveControl := FName
  else if Trim(FEmail.Text) = '' then
    ActiveControl := FEmail
  else
    ActiveControl := FSaveButton;
end;

procedure TIdentityForm.Check(Sender: TObject);
begin
  FSaveButton.Enabled := (Trim(FName.Text) <> '') and (Trim(FEmail.Text) <> '');
end;

function ChooseIdentity(var AName, AEmail: string; var ALocal: boolean): boolean;
var
  F: TIdentityForm;
begin
  F := TIdentityForm.Create(Screen.ActiveForm);
  try
    F.FName.Text := AName;
    F.FEmail.Text := AEmail;
    F.FLocal.Checked := ALocal;
    F.Check(nil);
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      AName := Trim(F.FName.Text);
      AEmail := Trim(F.FEmail.Text);
      ALocal := F.FLocal.Checked;
    end;
  finally
    F.Free;
  end;
end;

end.
