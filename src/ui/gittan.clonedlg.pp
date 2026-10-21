unit gittan.clonedlg;

{** The dialog of Clone: the URL to clone from (the clipboard's when it
  holds one), the folder to clone into (with a Choose... button) and the
  name of the new folder in it, which follows the URL as git clone would
  name it (CloneFolderName) until it is typed in. Under them the whole
  path the clone goes to, and whether the submodules come too. Clone is
  off, with the reason in red, while the URL is empty, the folder is not
  there, or the new folder exists and is not empty, which git refuses. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs;

{** Asks where to clone from and to, starting with AUrl, AParent and
  ASubmodules (an empty AUrl takes the clipboard's when it looks like
  one). True when Clone was pressed, with the choices in them and the
  new folder in ATarget. }
function ChooseClone(var AUrl, AParent: string; var ASubmodules: boolean;
  out ATarget: string): boolean;

{** Whether the folder ADir has anything in it. }
function FolderHasEntries(const ADir: string): boolean;

implementation

uses
  Graphics, Clipbrd, gittan.git;

resourcestring
  rsCloneTitle = 'Clone Repository';
  rsCloneHint = 'Copies a repository, with all of its history, into a new folder on this ' +
    'computer and opens it.';
  rsCloneUrl = 'URL';
  rsCloneFolder = 'Folder';
  rsCloneName = 'Name';
  rsCloneChoose = 'Choose…';
  rsCloneChooseTitle = 'Clone Into';
  rsCloneInto = 'Clones into %s';
  rsCloneSubmodules = 'Clone the submodules too';
  rsCloneNoFolder = 'The folder %s does not exist.';
  rsCloneNotEmpty = '%s already exists and is not empty.';
  rsCloneBadName = 'The name cannot hold a slash.';
  rsCloneButton = 'Clone';
  rsCancel = 'Cancel';

const
  DialogWidth = 560;
  Margin = 12;
  LabelWidth = 64;

type

  { TCloneForm }

  TCloneForm = class(TForm)
  private
    FHint, FInto, FError: TLabel;
    FUrl, FParent, FName: TEdit;
    FChoose, FCloneButton: TButton;
    FSubmodules: TCheckBox;
    FNextTop: integer;
    { The name was typed, so the URL no longer sets it. }
    FNameTyped, FSetting: boolean;
    function Row(const ACaption: string; AEdit: TEdit; AButton: TButton): TPanel;
    function Target: string;
    procedure Check;
    procedure UrlChange(Sender: TObject);
    procedure NameChange(Sender: TObject);
    procedure ParentChange(Sender: TObject);
    procedure ChooseClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

function FolderHasEntries(const ADir: string): boolean;
var
  Info: TSearchRec;
begin
  Result := False;
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, Info) = 0 then
  try
    repeat
      if (Info.Name <> '.') and (Info.Name <> '..') then
        Exit(True);
    until FindNext(Info) <> 0;
  finally
    FindClose(Info);
  end;
end;

constructor TCloneForm.Create(AOwner: TComponent);
var
  Buttons: TPanel;
  Cancel: TButton;
begin
  inherited CreateNew(AOwner);
  Caption := rsCloneTitle;
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  { The height follows the content; the width stays, so a long path is
    cut at the edge instead of widening the dialog. }
  Constraints.MinWidth := Scale96ToScreen(DialogWidth);
  Constraints.MaxWidth := Scale96ToScreen(DialogWidth);
  AutoSize := True;

  FHint := TLabel.Create(Self);
  FHint.Caption := rsCloneHint;
  FHint.WordWrap := True;
  FHint.Align := alTop;
  FHint.BorderSpacing.Around := Scale96ToScreen(Margin);
  FHint.Top := 0;
  FHint.Parent := Self;

  FUrl := TEdit.Create(Self);
  FUrl.OnChange := @UrlChange;
  Row(rsCloneUrl, FUrl, nil);
  FParent := TEdit.Create(Self);
  FParent.OnChange := @ParentChange;
  FChoose := TButton.Create(Self);
  FChoose.Caption := rsCloneChoose;
  FChoose.OnClick := @ChooseClick;
  Row(rsCloneFolder, FParent, FChoose);
  FName := TEdit.Create(Self);
  FName.OnChange := @NameChange;
  Row(rsCloneName, FName, nil);

  FInto := TLabel.Create(Self);
  FInto.Font.Color := clGrayText;
  FInto.ShowAccelChar := False;
  FInto.Align := alTop;
  Inc(FNextTop, 1000);
  FInto.Top := FNextTop;
  FInto.BorderSpacing.Left := Scale96ToScreen(Margin + LabelWidth);
  FInto.BorderSpacing.Right := Scale96ToScreen(Margin);
  FInto.Parent := Self;

  FSubmodules := TCheckBox.Create(Self);
  FSubmodules.Caption := rsCloneSubmodules;
  FSubmodules.Align := alTop;
  Inc(FNextTop, 1000);
  FSubmodules.Top := FNextTop;
  FSubmodules.BorderSpacing.Left := Scale96ToScreen(Margin + LabelWidth);
  FSubmodules.BorderSpacing.Top := Scale96ToScreen(10);
  FSubmodules.Parent := Self;

  FError := TLabel.Create(Self);
  FError.WordWrap := True;
  FError.Font.Color := clRed;
  FError.ShowAccelChar := False;
  FError.Align := alTop;
  Inc(FNextTop, 1000);
  FError.Top := FNextTop;
  FError.BorderSpacing.Left := Scale96ToScreen(Margin + LabelWidth);
  FError.BorderSpacing.Right := Scale96ToScreen(Margin);
  FError.BorderSpacing.Top := Scale96ToScreen(8);
  FError.Parent := Self;

  { Clone on the right on macOS, Cancel on the right elsewhere. }
  Buttons := TPanel.Create(Self);
  Buttons.BevelOuter := bvNone;
  Buttons.AutoSize := True;
  Buttons.Align := alTop;
  Inc(FNextTop, 1000);
  Buttons.Top := FNextTop;
  Buttons.BorderSpacing.Around := Scale96ToScreen(Margin);
  Buttons.BorderSpacing.Top := Scale96ToScreen(16);
  Buttons.Parent := Self;
  FCloneButton := TButton.Create(Self);
  FCloneButton.Caption := rsCloneButton;
  FCloneButton.ModalResult := mrOK;
  FCloneButton.Default := True;
  FCloneButton.AutoSize := True;
  FCloneButton.Constraints.MinWidth := Scale96ToScreen(84);
  FCloneButton.Align := alRight;
  FCloneButton.Parent := Buttons;
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
  FCloneButton.Left := 1000;
  {$ELSE}
  FCloneButton.Left := 0;
  Cancel.Left := 1000;
  {$ENDIF}
  Cancel.BorderSpacing.Left := Scale96ToScreen(8);
  FCloneButton.BorderSpacing.Left := Scale96ToScreen(8);
end;

{ A row under the ones before it: the caption in a column of its own,
  then AEdit filling the rest, and AButton after it. }
function TCloneForm.Row(const ACaption: string; AEdit: TEdit; AButton: TButton): TPanel;
var
  Lbl: TLabel;
begin
  Result := TPanel.Create(Self);
  Result.BevelOuter := bvNone;
  Result.Align := alTop;
  Inc(FNextTop, 1000);
  Result.Top := FNextTop;
  Result.BorderSpacing.Left := Scale96ToScreen(Margin);
  Result.BorderSpacing.Right := Scale96ToScreen(Margin);
  Result.BorderSpacing.Bottom := Scale96ToScreen(6);
  Result.AutoSize := True;
  Result.Parent := Self;
  Lbl := TLabel.Create(Self);
  Lbl.Caption := ACaption;
  Lbl.AutoSize := False;
  Lbl.Width := Scale96ToScreen(LabelWidth);
  Lbl.Align := alLeft;
  Lbl.Layout := tlCenter;
  Lbl.Parent := Result;
  if AButton <> nil then
  begin
    AButton.AutoSize := True;
    AButton.Align := alRight;
    AButton.BorderSpacing.Left := Scale96ToScreen(8);
    AButton.Parent := Result;
  end;
  AEdit.Align := alClient;
  AEdit.Parent := Result;
end;

procedure TCloneForm.DoShow;
begin
  inherited DoShow;
  if FUrl.Text = '' then
    ActiveControl := FUrl
  else
    ActiveControl := FCloneButton;
end;

function TCloneForm.Target: string;
begin
  Result := '';
  if (Trim(FParent.Text) <> '') and (Trim(FName.Text) <> '') then
    Result := IncludeTrailingPathDelimiter(ExpandFileName(Trim(FParent.Text))) +
      Trim(FName.Text);
end;

{ Clone is on when git would take it; the reason it would not is said
  once there is a URL to clone. }
procedure TCloneForm.Check;
var
  Folder, NewName, Err, Path: string;
begin
  Folder := Trim(FParent.Text);
  NewName := Trim(FName.Text);
  Path := Target;
  Err := '';
  if (Folder = '') or not DirectoryExists(Folder) then
    Err := Format(rsCloneNoFolder, [Folder])
  else if (Pos('/', NewName) > 0) or (Pos(PathDelim, NewName) > 0) then
    Err := rsCloneBadName
  else if (Path <> '') and (FileExists(Path) or (DirectoryExists(Path) and
    FolderHasEntries(Path))) then
    Err := Format(rsCloneNotEmpty, [Path]);
  if Path <> '' then
    FInto.Caption := Format(rsCloneInto, [Path])
  else
    FInto.Caption := ' ';
  if Trim(FUrl.Text) = '' then
    FError.Caption := ''
  else
    FError.Caption := Err;
  FError.Visible := FError.Caption <> '';
  FCloneButton.Enabled := (Trim(FUrl.Text) <> '') and (NewName <> '') and (Err = '');
end;

procedure TCloneForm.UrlChange(Sender: TObject);
begin
  if not FNameTyped then
  begin
    FSetting := True;
    try
      FName.Text := CloneFolderName(FUrl.Text);
    finally
      FSetting := False;
    end;
  end;
  Check;
end;

{ A name typed sticks; emptied, it follows the URL again. }
procedure TCloneForm.NameChange(Sender: TObject);
begin
  if not FSetting then
    FNameTyped := FName.Text <> '';
  Check;
end;

procedure TCloneForm.ParentChange(Sender: TObject);
begin
  Check;
end;

procedure TCloneForm.ChooseClick(Sender: TObject);
var
  D: TSelectDirectoryDialog;
begin
  D := TSelectDirectoryDialog.Create(Self);
  try
    D.Title := rsCloneChooseTitle;
    if DirectoryExists(Trim(FParent.Text)) then
      D.InitialDir := Trim(FParent.Text);
    if D.Execute then
      FParent.Text := D.FileName;
  finally
    D.Free;
  end;
end;

function ChooseClone(var AUrl, AParent: string; var ASubmodules: boolean;
  out ATarget: string): boolean;
var
  F: TCloneForm;
  Clip: string;
begin
  ATarget := '';
  F := TCloneForm.Create(Screen.ActiveForm);
  try
    if AUrl = '' then
    begin
      Clip := '';
      if Clipboard.HasFormat(CF_TEXT) then
        Clip := Trim(Clipboard.AsText);
      if LooksLikeCloneUrl(Clip) then
        AUrl := Clip;
    end;
    F.FParent.Text := AParent;
    F.FUrl.Text := AUrl;
    F.FSubmodules.Checked := ASubmodules;
    F.Check;
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      AUrl := Trim(F.FUrl.Text);
      AParent := ExpandFileName(Trim(F.FParent.Text));
      ASubmodules := F.FSubmodules.Checked;
      ATarget := F.Target;
    end;
  finally
    F.Free;
  end;
end;

end.
