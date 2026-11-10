unit gittan.identitydlg;

{** The dialog of the name and e-mail commits are made under, and of
  how they are signed: the two fields and whether they are the
  repository's own or, as git suggests, the global ones for every
  repository; then whether to sign commits, with an SSH or a GPG key,
  which key, and a Test that signs a commit of the empty tree to show
  the whole chain works before anything is saved. Save is off while
  either field is empty, since git commits with neither missing, and
  while signing is on without a key, or with GPG when no gpg was found. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs, gittan.signing;

{** Asks for the name and e-mail to commit under, starting with AName,
  AEmail and ALocal (the repository's own rather than the global ones),
  and for the signing, starting with ASigning as read from the config;
  ARoot is the repository, where keys are looked up and the test
  commit made. True when Save was pressed, with the trimmed choices in
  them (ASigning.Key the key id for GPG, the public key's path or the
  key itself for SSH). ASigningChanged says whether the signing was
  changed in the dialog; a key the dialog chose itself for an empty
  field does not count. }
function ChooseIdentity(var AName, AEmail: string; var ALocal: boolean;
  var ASigning: TGittanSigningSetup; const ARoot: string;
  out ASigningChanged: boolean): boolean;

implementation

uses
  Graphics;

resourcestring
  rsIdentityDlgTitle = 'Name and Email';
  rsIdentityDlgHint = 'Commits are made under this name and e-mail. Git keeps them in your ' +
    'global config, for every repository, unless this one has its own.';
  rsIdentityDlgName = 'Name';
  rsIdentityDlgEmail = 'E-mail';
  rsIdentityDlgLocal = 'Only for this repository';
  rsIdentityDlgSave = 'Save';
  rsCancel = 'Cancel';
  rsIdentityDlgSigning = 'Signing';
  rsIdentityDlgSignHint = 'A signature proves a commit is yours; GitHub, GitLab and the ' +
    'others show it as verified. An SSH key needs only ssh-keygen, which macOS, Linux and ' +
    'Windows have; a GPG key needs gpg.';
  rsIdentityDlgSignOff = 'Don''t sign commits';
  rsIdentityDlgSignSsh = 'Sign with an SSH key';
  rsIdentityDlgSignGpg = 'Sign with a GPG key';
  rsIdentityDlgKey = 'Key';
  rsIdentityDlgChoose = 'Choose...';
  rsIdentityDlgTest = 'Test';
  rsIdentityDlgPickKey = 'Choose a Public Key';
  rsIdentityDlgKeyFilter = 'Public keys (*.pub)|*.pub|All files|*';
  rsIdentityDlgAgent = '%s (from the ssh agent)';
  rsIdentityDlgNoGpg = 'gpg was not found. Install GnuPG (Gpg4win on Windows, GPG Suite or ' +
    'Homebrew on macOS) or set gpg.program in your git config, then come back here.';
  rsIdentityDlgGpgFailed = 'gpg could not list your keys: %s';
  rsIdentityDlgNoGpgKeys = 'gpg has no secret key. Make one with "gpg --full-generate-key" ' +
    'and come back here.';
  rsIdentityDlgNoSshKeys = 'No public key was found in ~/.ssh. Make one with "ssh-keygen -t ' +
    'ed25519" or choose a .pub file.';
  rsIdentityDlgTesting = 'Signing a test commit...';
  rsIdentityDlgTestOk = 'Signed and verified%s.';
  rsIdentityDlgTestOkKey = ' with key %s';
  rsIdentityDlgTestUnchecked = 'Signed. Save sets up the allowed signers file, so Gittan can ' +
    'check SSH signatures like this one.';
  rsIdentityDlgTestUnknown = 'Signed, but the key is not among those known here: %s';
  rsIdentityDlgTestFailed = 'Signing failed: %s';

const
  DialogWidth = 480;
  Margin = 12;
  LabelWidth = 64;

type

  { TIdentityForm }

  TIdentityForm = class(TForm)
  private
    FRoot: string;
    FName, FEmail: TEdit;
    FLocal: TCheckBox;
    FSign: TComboBox;
    FKey: TComboBox;
    FChoose, FTest: TButton;
    FResult: TLabel;
    FSaveButton: TButton;
    FNextTop: integer;
    { What FKey's items stand for, in its order: the key ids while GPG
      is chosen, the .pub paths and the agent's keys (key::type base64
      comment, what user.signingkey takes a literal key as) for SSH. }
    FGpgIds, FSshValues: TStringArray;
    { The format the items are for, and the key last chosen for each,
      so a switch of format does not carry a .pub path into the GPG
      key, and back again finds the SSH key. }
    FFilledFormat: TGittanSignFormat;
    FKept: array[TGittanSignFormat] of string;
    FGpgProgram: string;
    FGpgLooked: boolean;
    { The key of an X.509 setup (gpgsm), which the dialog shows under
      GPG; '' for any other. }
    FX509Key: string;
    procedure Row(const ACaption: string; AControl: TControl; AButton: TControl = nil);
    procedure Check(Sender: TObject);
    procedure SignChange(Sender: TObject);
    procedure ChooseClick(Sender: TObject);
    procedure TestClick(Sender: TObject);
    procedure FillKeys;
    function ChosenFormat: TGittanSignFormat;
    function FormatToSave: TGittanSignFormat;
    function KeyValue: string;
    function KeyValueFor(AFormat: TGittanSignFormat): string;
    procedure SetKeyValue(const AValue: string);
    procedure Say(const AText: string);
  protected
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TIdentityForm.Create(AOwner: TComponent);
var
  Note, Head, SignNote: TLabel;
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

  Head := TLabel.Create(Self);
  Head.Caption := rsIdentityDlgSigning;
  Head.Font.Style := [fsBold];
  Head.Align := alTop;
  Inc(FNextTop, 1000);
  Head.Top := FNextTop;
  Head.BorderSpacing.Left := Scale96ToScreen(Margin);
  Head.BorderSpacing.Top := Scale96ToScreen(16);
  Head.Parent := Self;
  SignNote := TLabel.Create(Self);
  SignNote.Caption := rsIdentityDlgSignHint;
  SignNote.WordWrap := True;
  SignNote.Align := alTop;
  Inc(FNextTop, 1000);
  SignNote.Top := FNextTop;
  SignNote.BorderSpacing.Left := Scale96ToScreen(Margin);
  SignNote.BorderSpacing.Right := Scale96ToScreen(Margin);
  SignNote.BorderSpacing.Top := Scale96ToScreen(4);
  SignNote.BorderSpacing.Bottom := Scale96ToScreen(8);
  SignNote.Parent := Self;

  FSign := TComboBox.Create(Self);
  FSign.Style := csDropDownList;
  FSign.Items.Add(rsIdentityDlgSignOff);
  FSign.Items.Add(rsIdentityDlgSignSsh);
  FSign.Items.Add(rsIdentityDlgSignGpg);
  FSign.ItemIndex := 0;
  FSign.OnChange := @SignChange;
  Row('', FSign);
  FKey := TComboBox.Create(Self);
  FKey.Style := csDropDown;
  FKey.OnChange := @Check;
  FKey.OnSelect := @Check;
  FChoose := TButton.Create(Self);
  FChoose.Caption := rsIdentityDlgChoose;
  FChoose.AutoSize := True;
  FChoose.OnClick := @ChooseClick;
  Row(rsIdentityDlgKey, FKey, FChoose);
  FResult := TLabel.Create(Self);
  FResult.WordWrap := True;
  FResult.Align := alTop;
  Inc(FNextTop, 1000);
  FResult.Top := FNextTop;
  FResult.BorderSpacing.Left := Scale96ToScreen(Margin + LabelWidth);
  FResult.BorderSpacing.Right := Scale96ToScreen(Margin);
  FResult.Parent := Self;

  { Save on the right on macOS, Cancel on the right elsewhere; Test at
    the left on both. }
  Buttons := TPanel.Create(Self);
  Buttons.BevelOuter := bvNone;
  Buttons.AutoSize := True;
  Buttons.Align := alTop;
  Inc(FNextTop, 1000);
  Buttons.Top := FNextTop;
  Buttons.BorderSpacing.Around := Scale96ToScreen(Margin);
  Buttons.BorderSpacing.Top := Scale96ToScreen(16);
  Buttons.Parent := Self;
  FTest := TButton.Create(Self);
  FTest.Caption := rsIdentityDlgTest;
  FTest.AutoSize := True;
  FTest.Constraints.MinWidth := Scale96ToScreen(84);
  FTest.Align := alLeft;
  FTest.OnClick := @TestClick;
  FTest.Parent := Buttons;
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
  then AControl filling the rest, and AButton at its right when given. }
procedure TIdentityForm.Row(const ACaption: string; AControl: TControl; AButton: TControl);
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
  if AButton <> nil then
  begin
    AButton.Align := alRight;
    AButton.BorderSpacing.Left := Scale96ToScreen(6);
    AButton.Parent := Panel;
  end;
  AControl.Align := alClient;
  AControl.Parent := Panel;
end;

procedure TIdentityForm.DoShow;
begin
  inherited DoShow;
  if Trim(FName.Text) = '' then
    ActiveControl := FName
  else if Trim(FEmail.Text) = '' then
    ActiveControl := FEmail
  else if FSaveButton.Enabled then
    ActiveControl := FSaveButton
  else
    ActiveControl := FSign;
end;

function TIdentityForm.ChosenFormat: TGittanSignFormat;
begin
  case FSign.ItemIndex of
    1: Result := sfSsh;
    2: Result := sfOpenPgp;
  else
    Result := sfNone;
  end;
end;

{ X.509 stays as it was while its key is the one chosen; another key
  under GPG is an OpenPGP one. }
function TIdentityForm.FormatToSave: TGittanSignFormat;
begin
  Result := ChosenFormat;
  if (Result = sfOpenPgp) and (FX509Key <> '') and (KeyValue = FX509Key) then
    Result := sfX509;
end;

{ The key as git wants it: for GPG the id behind the item chosen, else
  what was typed (an id, or a fingerprint); for SSH the text itself,
  a .pub path or a key, the agent note dropped. }
function TIdentityForm.KeyValue: string;
begin
  Result := KeyValueFor(ChosenFormat);
end;

function TIdentityForm.KeyValueFor(AFormat: TGittanSignFormat): string;
var
  i: integer;
begin
  Result := Trim(FKey.Text);
  { The item picked, else the first with the text typed. }
  i := FKey.ItemIndex;
  if (i < 0) or (i >= FKey.Items.Count) or (FKey.Items[i] <> FKey.Text) then
    i := FKey.Items.IndexOf(FKey.Text);
  if (AFormat = sfOpenPgp) and (i >= 0) and (i <= High(FGpgIds)) then
    Result := FGpgIds[i]
  else if (AFormat = sfSsh) and (i >= 0) and (i <= High(FSshValues)) then
    Result := FSshValues[i];
end;

procedure TIdentityForm.SetKeyValue(const AValue: string);
var
  i: integer;
begin
  if ChosenFormat = sfOpenPgp then
  begin
    for i := 0 to High(FGpgIds) do
      if (AValue <> '') and (Pos(UpperCase(AValue), UpperCase(FGpgIds[i])) > 0) or
        (Pos(UpperCase(FGpgIds[i]), UpperCase(AValue)) > 0) then
      begin
        FKey.ItemIndex := i;
        Exit;
      end;
  end
  else if ChosenFormat = sfSsh then
  begin
    { An agent's key shows as its item, not as the key's text. }
    for i := 0 to High(FSshValues) do
      if (AValue <> '') and (FSshValues[i] = AValue) then
      begin
        FKey.ItemIndex := i;
        Exit;
      end;
  end;
  FKey.Text := AValue;
end;

{ The label stays in place, a blank line when there is nothing to say,
  so a hidden control does not fall below the buttons when it shows. }
procedure TIdentityForm.Say(const AText: string);
begin
  if AText = '' then
    FResult.Caption := ' '
  else
    FResult.Caption := AText;
end;

{ The keys to pick from for the format chosen: the public key files of
  ~/.ssh and the agent's keys, or gpg's secret keys as "id — user id".
  gpg is looked for once; without it the GPG choice says so. }
procedure TIdentityForm.FillKeys;
var
  Keys: TStringArray;
  Key, Error, Comment: string;
  Parts: TStringArray;
  Kept: string;
begin
  { The items are still those of the format filled last, and are read
    as that format's. }
  if FFilledFormat <> sfNone then
    FKept[FFilledFormat] := KeyValueFor(FFilledFormat);
  FFilledFormat := ChosenFormat;
  Kept := FKept[ChosenFormat];
  FKey.Items.Clear;
  FGpgIds := nil;
  FSshValues := nil;
  Say('');
  case ChosenFormat of
    sfSsh:
    begin
      for Key in SshPublicKeys do
      begin
        FKey.Items.Add(Key);
        SetLength(FSshValues, Length(FSshValues) + 1);
        FSshValues[High(FSshValues)] := Key;
      end;
      for Key in SshAgentKeys do
      begin
        Parts := Key.Split([' '], TStringSplitOptions.ExcludeEmpty);
        if Length(Parts) >= 3 then
          Comment := Parts[2]
        else
          Comment := Parts[0];
        { The item shows the comment, the key itself stands behind it,
          with key:: before it: git takes a bare key as one only when
          it starts with ssh-, so an ecdsa or sk- key would be read as
          a file's path. }
        { Two keys of one machine often share the comment: the second
          names its type and the end of the key, so each item is one
          key. }
        if (FKey.Items.IndexOf(SysUtils.Format(rsIdentityDlgAgent, [Comment])) >= 0) and
          (Length(Parts) >= 2) then
          Comment := Comment + ', ' + Parts[0] + ' …' +
            Copy(Parts[1], Length(Parts[1]) - 5, 6);
        FKey.Items.Add(SysUtils.Format(rsIdentityDlgAgent, [Comment]));
        SetLength(FSshValues, Length(FSshValues) + 1);
        FSshValues[High(FSshValues)] := 'key::' + Key;
      end;
      if FKey.Items.Count = 0 then
        Say(rsIdentityDlgNoSshKeys);
    end;
    sfOpenPgp:
    begin
      if not FGpgLooked then
      begin
        FGpgProgram := GpgProgramFor(FRoot);
        FGpgLooked := True;
      end;
      if FGpgProgram = '' then
        Say(rsIdentityDlgNoGpg)
      else if not GpgSecretKeys(FGpgProgram, Keys, Error) then
        Say(SysUtils.Format(rsIdentityDlgGpgFailed, [Trim(Error)]))
      else
      begin
        for Key in Keys do
        begin
          Parts := Key.Split([#31]);
          SetLength(FGpgIds, Length(FGpgIds) + 1);
          FGpgIds[High(FGpgIds)] := Parts[0];
          if Length(Parts) > 1 then
            FKey.Items.Add(Parts[0] + ' — ' + Parts[1])
          else
            FKey.Items.Add(Parts[0]);
        end;
        if Length(Keys) = 0 then
          Say(rsIdentityDlgNoGpgKeys);
      end;
    end;
  end;
  SetKeyValue(Kept);
  if (FKey.Text = '') and (FKey.Items.Count > 0) then
    FKey.ItemIndex := 0;
end;

procedure TIdentityForm.SignChange(Sender: TObject);
begin
  FillKeys;
  Check(nil);
end;

procedure TIdentityForm.ChooseClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(nil);
  try
    D.Title := rsIdentityDlgPickKey;
    D.Filter := rsIdentityDlgKeyFilter;
    D.Options := D.Options + [ofFileMustExist];
    D.InitialDir := IncludeTrailingPathDelimiter(GetUserDir) + '.ssh';
    if not DirectoryExists(D.InitialDir) then
      D.InitialDir := GetUserDir;
    if D.Execute then
    begin
      FKey.Text := D.FileName;
      Check(nil);
    end;
  finally
    D.Free;
  end;
end;

{ A commit of the empty tree, signed as chosen, then read back the way
  the graph reads a commit, so the answer says whether Gittan will show
  it verified too. }
procedure TIdentityForm.TestClick(Sender: TObject);
var
  Setup: TGittanSigningSetup;
  Id, Error, KeyText: string;
  Commits: TGittanSignedCommits;
begin
  Setup := Default(TGittanSigningSetup);
  Setup.Sign := True;
  Setup.Format := FormatToSave;
  Setup.Key := KeyValue;
  Say(rsIdentityDlgTesting);
  Application.ProcessMessages;
  if not TestSigning(FRoot, Setup, Id, Error) then
  begin
    Say(SysUtils.Format(rsIdentityDlgTestFailed, [Trim(Error)]));
    Exit;
  end;
  if not CommitSignatures(FRoot, [Id], nil, Commits, Error, []) or (Length(Commits) <> 1) then
  begin
    Say(SysUtils.Format(rsIdentityDlgTestFailed, [Trim(Error)]));
    Exit;
  end;
  case Commits[0].Signature.State of
    ssGood:
    begin
      KeyText := '';
      if Commits[0].Signature.Key <> '' then
        KeyText := SysUtils.Format(rsIdentityDlgTestOkKey, [Commits[0].Signature.Key]);
      Say(SysUtils.Format(rsIdentityDlgTestOk, [KeyText]));
    end;
    ssUnknownKey:
      Say(SysUtils.Format(rsIdentityDlgTestUnknown, [Commits[0].Signature.Key]));
  else
    Say(rsIdentityDlgTestUnchecked);
  end;
end;

procedure TIdentityForm.Check(Sender: TObject);
var
  Signing: boolean;
begin
  Signing := ChosenFormat <> sfNone;
  FKey.Enabled := Signing;
  FChoose.Visible := ChosenFormat = sfSsh;
  FTest.Enabled := Signing and (KeyValue <> '');
  FSaveButton.Enabled := (Trim(FName.Text) <> '') and (Trim(FEmail.Text) <> '') and
    (not Signing or ((KeyValue <> '') and ((FormatToSave <> sfOpenPgp) or (FGpgProgram <> ''))));
end;

function ChooseIdentity(var AName, AEmail: string; var ALocal: boolean;
  var ASigning: TGittanSigningSetup; const ARoot: string;
  out ASigningChanged: boolean): boolean;
var
  F: TIdentityForm;
  WasSign: integer;
  WasKey: string;
begin
  ASigningChanged := False;
  F := TIdentityForm.Create(Screen.ActiveForm);
  try
    F.FRoot := ARoot;
    F.FName.Text := AName;
    F.FEmail.Text := AEmail;
    F.FLocal.Checked := ALocal;
    if ASigning.Sign then
      case ASigning.Format of
        sfSsh: F.FSign.ItemIndex := 1;
      else
        F.FSign.ItemIndex := 2;
      end
    else
      F.FSign.ItemIndex := 0;
    if ASigning.Sign and (ASigning.Format = sfX509) then
      F.FX509Key := ASigning.Key;
    F.FillKeys;
    F.SetKeyValue(ASigning.Key);
    F.Check(nil);
    { As shown, the key FillKeys chose for an empty field included:
      only a choice made in the dialog counts as a change. }
    WasSign := F.FSign.ItemIndex;
    WasKey := F.KeyValue;
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      ASigningChanged := (F.FSign.ItemIndex <> WasSign) or (F.KeyValue <> WasKey);
      AName := Trim(F.FName.Text);
      AEmail := Trim(F.FEmail.Text);
      ALocal := F.FLocal.Checked;
      ASigning.Sign := F.ChosenFormat <> sfNone;
      if ASigning.Sign then
      begin
        ASigning.Format := F.FormatToSave;
        ASigning.Key := F.KeyValue;
      end;
    end;
  finally
    F.Free;
  end;
end;

end.
