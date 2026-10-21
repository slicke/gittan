unit gittan.submoduledlg;

{** The dialog of Add Submodule: the URL to clone (the clipboard's when
  it holds one), the path in the repository it goes to, which follows
  the URL as git clone would name the folder (CloneFolderName), in the
  folder the other submodules share, until it is typed in, and the
  branch it follows, empty for the remote's default. Under them the
  whole path. Add is off, with the reason in red, while the path leaves
  the repository, is taken, or is or is in a submodule, which git
  refuses. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs;

{** Asks for a new submodule of the repository at ARoot, whose
  submodules are at ATaken, starting with AUrl (an empty one takes the
  clipboard's when it looks like one), APath (an empty one follows the
  URL, in AFolder) and ABranch. True when Add was pressed, with the
  choices in them, APath relative to the root with "/" separators. }
function ChooseSubmodule(const ARoot, AFolder: string; const ATaken: TStringArray;
  var AUrl, APath, ABranch: string): boolean;

implementation

uses
  Graphics, Clipbrd, gittan.git, gittan.clonedlg;

resourcestring
  rsSubAddTitle = 'Add Submodule';
  rsSubAddHint = 'Clones a repository into a folder of this one and records the commit it is ' +
    'at. The new submodule and .gitmodules are then changes to commit.';
  rsSubAddUrl = 'URL';
  rsSubAddPath = 'Path';
  rsSubAddBranch = 'Branch';
  rsSubAddBranchHint = 'Empty follows the remote''s default branch.';
  rsSubAddInto = 'Clones into %s';
  rsSubAddOutside = 'The path must be inside the repository.';
  rsSubAddTaken = '%s already exists and is not empty.';
  rsSubAddIsSubmodule = '%s is a submodule already.';
  rsSubAddInSubmodule = 'The path is inside the submodule %s.';
  rsSubAddButton = 'Add';
  rsCancel = 'Cancel';

const
  DialogWidth = 560;
  Margin = 12;
  LabelWidth = 64;

type

  { TSubmoduleForm }

  TSubmoduleForm = class(TForm)
  private
    FRoot, FFolder: string;
    FTaken: TStringArray;
    FHint, FInto, FError, FBranchHint: TLabel;
    FUrl, FPath, FBranch: TEdit;
    FAddButton: TButton;
    FButtons: TPanel;
    FNextTop: integer;
    { The path was typed, so the URL no longer sets it. }
    FPathTyped, FSetting: boolean;
    procedure Row(const ACaption: string; AEdit: TEdit);
    function Note(AColor: TColor): TLabel;
    procedure Check;
    procedure UrlChange(Sender: TObject);
    procedure PathChange(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

{ APath as git submodule add takes it: trimmed, "/" separators, no "./"
  before it and no "/" after it. }
function CleanSubmodulePath(const APath: string): string;
begin
  Result := StringReplace(Trim(APath), '\', '/', [rfReplaceAll]);
  while Copy(Result, 1, 2) = './' do
    Delete(Result, 1, 2);
  while (Result <> '') and (Result[Length(Result)] = '/') do
    SetLength(Result, Length(Result) - 1);
end;

{ Whether APath, cleaned, stays inside the repository and out of .git. }
function InsideRepository(const APath: string): boolean;
var
  Part: string;
begin
  if (APath = '') or (APath[1] = '/') or ((Length(APath) > 1) and (APath[2] = ':')) then
    Exit(False);
  for Part in APath.Split(['/']) do
    if (Part = '..') or (Part = '.') or SameText(Part, '.git') then
      Exit(False);
  Result := True;
end;

constructor TSubmoduleForm.Create(AOwner: TComponent);
var
  Buttons: TPanel;
  Cancel: TButton;
begin
  inherited CreateNew(AOwner);
  Caption := rsSubAddTitle;
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  { The height follows the content; the width stays, so a long path is
    cut at the edge instead of widening the dialog. }
  Constraints.MinWidth := Scale96ToScreen(DialogWidth);
  Constraints.MaxWidth := Scale96ToScreen(DialogWidth);
  AutoSize := True;

  FHint := TLabel.Create(Self);
  FHint.Caption := rsSubAddHint;
  FHint.WordWrap := True;
  FHint.Align := alTop;
  FHint.BorderSpacing.Around := Scale96ToScreen(Margin);
  FHint.Top := 0;
  FHint.Parent := Self;

  FUrl := TEdit.Create(Self);
  FUrl.OnChange := @UrlChange;
  Row(rsSubAddUrl, FUrl);
  FPath := TEdit.Create(Self);
  FPath.OnChange := @PathChange;
  Row(rsSubAddPath, FPath);
  FInto := Note(clGrayText);
  FInto.BorderSpacing.Bottom := Scale96ToScreen(8);
  FBranch := TEdit.Create(Self);
  Row(rsSubAddBranch, FBranch);
  FBranchHint := Note(clGrayText);
  FBranchHint.Caption := rsSubAddBranchHint;

  FError := Note(clRed);
  FError.WordWrap := True;
  FError.BorderSpacing.Top := Scale96ToScreen(8);

  { Add on the right on macOS, Cancel on the right elsewhere. }
  Buttons := TPanel.Create(Self);
  Buttons.BevelOuter := bvNone;
  Buttons.AutoSize := True;
  Buttons.Align := alTop;
  Inc(FNextTop, 1000);
  Buttons.Top := FNextTop;
  Buttons.BorderSpacing.Around := Scale96ToScreen(Margin);
  Buttons.BorderSpacing.Top := Scale96ToScreen(16);
  Buttons.Parent := Self;
  FButtons := Buttons;
  FAddButton := TButton.Create(Self);
  FAddButton.Caption := rsSubAddButton;
  FAddButton.ModalResult := mrOK;
  FAddButton.Default := True;
  FAddButton.AutoSize := True;
  FAddButton.Constraints.MinWidth := Scale96ToScreen(84);
  FAddButton.Align := alRight;
  FAddButton.Parent := Buttons;
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
  FAddButton.Left := 1000;
  {$ELSE}
  FAddButton.Left := 0;
  Cancel.Left := 1000;
  {$ENDIF}
  Cancel.BorderSpacing.Left := Scale96ToScreen(8);
  FAddButton.BorderSpacing.Left := Scale96ToScreen(8);
end;

{ A row under the ones before it: the caption in a column of its own,
  then AEdit filling the rest. }
procedure TSubmoduleForm.Row(const ACaption: string; AEdit: TEdit);
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

{ A line of text under the rows before it, lined up with the fields. }
function TSubmoduleForm.Note(AColor: TColor): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Font.Color := AColor;
  Result.ShowAccelChar := False;
  Result.Align := alTop;
  Inc(FNextTop, 1000);
  Result.Top := FNextTop;
  Result.BorderSpacing.Left := Scale96ToScreen(Margin + LabelWidth);
  Result.BorderSpacing.Right := Scale96ToScreen(Margin);
  Result.Parent := Self;
end;

procedure TSubmoduleForm.DoShow;
begin
  inherited DoShow;
  if FUrl.Text = '' then
    ActiveControl := FUrl
  else
    ActiveControl := FAddButton;
end;

{ Add is on when git would take it; the reason it would not is said
  once there is a URL to add. }
procedure TSubmoduleForm.Check;
var
  Path, Full, Err, Taken: string;
begin
  Path := CleanSubmodulePath(FPath.Text);
  Full := '';
  Err := '';
  if (Path <> '') and not InsideRepository(Path) then
    Err := rsSubAddOutside
  else if Path <> '' then
  begin
    for Taken in FTaken do
      if Path = Taken then
        Err := Format(rsSubAddIsSubmodule, [Taken])
      else if Copy(Path, 1, Length(Taken) + 1) = Taken + '/' then
        Err := Format(rsSubAddInSubmodule, [Taken]);
    Full := IncludeTrailingPathDelimiter(FRoot) + SetDirSeparators(Path);
    if (Err = '') and (FileExists(Full) or (DirectoryExists(Full) and
      FolderHasEntries(Full))) then
      Err := Format(rsSubAddTaken, [Path]);
  end;
  if Full <> '' then
    FInto.Caption := Format(rsSubAddInto, [Full])
  else
    FInto.Caption := ' ';
  if Trim(FUrl.Text) = '' then
    FError.Caption := ''
  else
    FError.Caption := Err;
  { Shown again, an alTop control goes last unless its Top says
    otherwise. }
  if (FError.Caption <> '') and not FError.Visible then
    FError.Top := FButtons.Top - 1;
  FError.Visible := FError.Caption <> '';
  FAddButton.Enabled := (Trim(FUrl.Text) <> '') and (Path <> '') and (Err = '');
end;

procedure TSubmoduleForm.UrlChange(Sender: TObject);
begin
  if not FPathTyped then
  begin
    FSetting := True;
    try
      if CloneFolderName(FUrl.Text) = '' then
        FPath.Text := ''
      else
        FPath.Text := FFolder + CloneFolderName(FUrl.Text);
    finally
      FSetting := False;
    end;
  end;
  Check;
end;

{ A path typed sticks; emptied, it follows the URL again. }
procedure TSubmoduleForm.PathChange(Sender: TObject);
begin
  if not FSetting then
    FPathTyped := FPath.Text <> '';
  Check;
end;

function ChooseSubmodule(const ARoot, AFolder: string; const ATaken: TStringArray;
  var AUrl, APath, ABranch: string): boolean;
var
  F: TSubmoduleForm;
  Clip: string;
begin
  F := TSubmoduleForm.Create(Screen.ActiveForm);
  try
    F.FRoot := ExcludeTrailingPathDelimiter(ARoot);
    F.FFolder := AFolder;
    F.FTaken := ATaken;
    if AUrl = '' then
    begin
      Clip := '';
      if Clipboard.HasFormat(CF_TEXT) then
        Clip := Trim(Clipboard.AsText);
      if LooksLikeCloneUrl(Clip) then
        AUrl := Clip;
    end;
    if APath <> '' then
    begin
      F.FPath.Text := APath;
      F.FPathTyped := True;
    end;
    F.FBranch.Text := ABranch;
    F.FUrl.Text := AUrl;
    F.Check;
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      AUrl := Trim(F.FUrl.Text);
      APath := CleanSubmodulePath(F.FPath.Text);
      ABranch := Trim(F.FBranch.Text);
    end;
  finally
    F.Free;
  end;
end;

end.
