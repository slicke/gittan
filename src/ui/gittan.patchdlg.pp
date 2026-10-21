unit gittan.patchdlg;

{** The dialogs of patches. Create Patch Series lists the commits that
  become patch files (TGittanRepo.PatchCommits), oldest first, with the
  folder they go to (a Choose... button beside it) and whether a cover
  letter comes first; Create is off, with the reason in red, while the
  folder cannot be made. Apply Patches lists the patch files in the
  order they go in, with Add... and Remove beside them, and chooses
  between committing each (git am) and changing the work tree alone
  (git apply); committing is offered only while every file is a mail as
  format-patch writes them (IsMailPatchFile). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs, gittan.git;

{** Asks where the patches of ACommits go, starting with AFolder and
  ACoverLetter. True when Create was pressed, with the choices in them. }
function ChoosePatchSeries(const ACommits: TGittanPatchCommits; var AFolder: string;
  var ACoverLetter: boolean): boolean;

{** Asks how to apply the patch files AFiles (full paths), which the
  dialog may add to, take from or start choosing in AFolder when empty,
  starting with ACommit. True when Apply was pressed, with AFiles in the
  order listed, ACommit as chosen and AFolder the one the last file
  added was in. }
function ChooseApplyPatches(AFiles: TStrings; var ACommit: boolean;
  var AFolder: string): boolean;

{** Lets the user pick patch files in an open dialog starting in
  AFolder; True with them, sorted by name, added to AFiles and AFolder
  the folder they are in. }
function PickPatchFiles(AFiles: TStrings; var AFolder: string): boolean;

implementation

uses
  Graphics;

resourcestring
  rsSeriesTitle = 'Create Patch Series';
  rsSeriesHint = 'Writes a patch file for each commit, numbered in order, to send by mail ' +
    'or to apply with Apply Patches. Merge commits are left out.';
  rsSeriesHintOne = 'Writes the commit as a patch file, to send by mail or to apply with ' +
    'Apply Patches.';
  rsSeriesFolder = 'Folder';
  rsSeriesChoose = 'Choose…';
  rsSeriesChooseTitle = 'Write the Patches To';
  rsSeriesCover = 'Start with a cover letter to fill in (0000-cover-letter.patch)';
  rsSeriesInto = 'Writes %d files into the folder; a file of the same name there is ' +
    'overwritten.';
  rsSeriesIntoNew = 'Makes the folder and writes %d files into it.';
  rsSeriesNoFolder = 'The folder %s does not exist.';
  rsSeriesButton = 'Create';
  rsApplyTitle = 'Apply Patches';
  rsApplyHint = 'Applies the patch files in the order listed. A patch that does not fit ' +
    'the code as it is now is merged, which may leave conflicts to resolve.';
  rsApplyAdd = 'Add…';
  rsApplyRemove = 'Remove';
  rsApplyCommit = 'Commit each patch, with the author and the message it carries (git am)';
  rsApplyTree = 'Change the work tree only, without committing (git apply)';
  rsApplyNotMail = '%s is not a mail as format-patch writes it, so it can only go into the ' +
    'work tree.';
  rsApplyButton = 'Apply';
  rsPickTitle = 'Apply Patches';
  rsPickFilter = 'Patches (*.patch, *.diff, *.eml, *.mbox)|*.patch;*.diff;*.eml;*.mbox|' +
    'All files|*';
  rsCancel = 'Cancel';

const
  Margin = 12;
  LabelWidth = 56;

type

  { TPatchForm: what both dialogs share, a hint at the top, a list in the
    middle and a panel under it that sizes itself, the controls stacked
    by Place, with the buttons last. }

  TPatchForm = class(TForm)
  private
    FHint: TLabel;
    FList: TListBox;
    FBottom: TPanel;
    FOkButton: TButton;
    FNextTop: integer;
    procedure Place(AControl: TControl; ASpaceAbove: integer);
    procedure AddButtons(const AOkCaption: string);
  public
    constructor CreateFor(AOwner: TComponent; const ATitle: string);
  end;

  { TSeriesForm }

  TSeriesForm = class(TPatchForm)
  private
    FFolder: TEdit;
    FCover: TCheckBox;
    FInto, FError: TLabel;
    FCount: integer;
    procedure Check;
    procedure FolderChange(Sender: TObject);
    procedure ChooseClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  { TApplyForm }

  TApplyForm = class(TPatchForm)
  private
    FFiles: TStringList;
    FFolder: string;
    FCommit, FTree: TRadioButton;
    FNote: TLabel;
    FRemove: TButton;
    { The work tree was chosen while committing could be, so a file
      added that makes committing possible again does not undo it. }
    FTreeChosen: boolean;
    procedure Fill;
    procedure Check;
    procedure AddClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure ListSelectionChange(Sender: TObject; User: boolean);
    procedure ModeClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

constructor TPatchForm.CreateFor(AOwner: TComponent; const ATitle: string);
begin
  inherited CreateNew(AOwner);
  Caption := ATitle;
  BorderStyle := bsSizeable;
  Position := poMainFormCenter;
  Width := Scale96ToScreen(600);
  Height := Scale96ToScreen(460);
  Constraints.MinWidth := Scale96ToScreen(440);
  Constraints.MinHeight := Scale96ToScreen(320);

  FHint := TLabel.Create(Self);
  FHint.WordWrap := True;
  FHint.Align := alTop;
  FHint.BorderSpacing.Around := Scale96ToScreen(Margin);
  FHint.Parent := Self;

  FBottom := TPanel.Create(Self);
  FBottom.BevelOuter := bvNone;
  FBottom.AutoSize := True;
  FBottom.Align := alBottom;
  FBottom.BorderSpacing.Left := Scale96ToScreen(Margin);
  FBottom.BorderSpacing.Right := Scale96ToScreen(Margin);
  FBottom.BorderSpacing.Bottom := Scale96ToScreen(Margin);
  FBottom.Parent := Self;

  FList := TListBox.Create(Self);
  FList.Align := alClient;
  FList.BorderSpacing.Left := Scale96ToScreen(Margin);
  FList.BorderSpacing.Right := Scale96ToScreen(Margin);
  FList.Parent := Self;
end;

{ Puts AControl under the ones placed before it in the bottom panel:
  alTop stacks controls by their Top. }
procedure TPatchForm.Place(AControl: TControl; ASpaceAbove: integer);
begin
  AControl.Align := alTop;
  AControl.BorderSpacing.Top := Scale96ToScreen(ASpaceAbove);
  Inc(FNextTop, 1000);
  AControl.Top := FNextTop;
  AControl.Parent := FBottom;
end;

{ The default button on the right on macOS, Cancel on the right elsewhere. }
procedure TPatchForm.AddButtons(const AOkCaption: string);
var
  Row: TPanel;
  Cancel: TButton;
begin
  Row := TPanel.Create(Self);
  Row.BevelOuter := bvNone;
  Row.AutoSize := True;
  Place(Row, 16);
  FOkButton := TButton.Create(Self);
  FOkButton.Caption := AOkCaption;
  FOkButton.ModalResult := mrOK;
  FOkButton.Default := True;
  FOkButton.AutoSize := True;
  FOkButton.Constraints.MinWidth := Scale96ToScreen(84);
  FOkButton.Align := alRight;
  FOkButton.Parent := Row;
  Cancel := TButton.Create(Self);
  Cancel.Caption := rsCancel;
  Cancel.ModalResult := mrCancel;
  Cancel.Cancel := True;
  Cancel.AutoSize := True;
  Cancel.Constraints.MinWidth := Scale96ToScreen(84);
  Cancel.Align := alRight;
  Cancel.Parent := Row;
  {$IFDEF DARWIN}
  Cancel.Left := 0;
  FOkButton.Left := 1000;
  {$ELSE}
  FOkButton.Left := 0;
  Cancel.Left := 1000;
  {$ENDIF}
  Cancel.BorderSpacing.Left := Scale96ToScreen(8);
  FOkButton.BorderSpacing.Left := Scale96ToScreen(8);
end;

{ ---------------------------------------------------------------------------
  Create Patch Series
  --------------------------------------------------------------------------- }

constructor TSeriesForm.Create(AOwner: TComponent);
var
  Row: TPanel;
  Lbl: TLabel;
  Choose: TButton;
begin
  inherited CreateFor(AOwner, rsSeriesTitle);

  { The folder: a caption, the field and Choose... in a row. }
  Row := TPanel.Create(Self);
  Row.BevelOuter := bvNone;
  Row.AutoSize := True;
  Place(Row, 10);
  Lbl := TLabel.Create(Self);
  Lbl.Caption := rsSeriesFolder;
  Lbl.AutoSize := False;
  Lbl.Width := Scale96ToScreen(LabelWidth);
  Lbl.Align := alLeft;
  Lbl.Layout := tlCenter;
  Lbl.Parent := Row;
  Choose := TButton.Create(Self);
  Choose.Caption := rsSeriesChoose;
  Choose.AutoSize := True;
  Choose.Align := alRight;
  Choose.BorderSpacing.Left := Scale96ToScreen(8);
  Choose.OnClick := @ChooseClick;
  Choose.Parent := Row;
  FFolder := TEdit.Create(Self);
  FFolder.Align := alClient;
  FFolder.OnChange := @FolderChange;
  FFolder.Parent := Row;

  FInto := TLabel.Create(Self);
  FInto.WordWrap := True;
  FInto.Font.Color := clGrayText;
  FInto.ShowAccelChar := False;
  Place(FInto, 6);
  FInto.BorderSpacing.Left := Scale96ToScreen(LabelWidth);
  FError := TLabel.Create(Self);
  FError.WordWrap := True;
  FError.Font.Color := clRed;
  FError.ShowAccelChar := False;
  FError.Visible := False;
  Place(FError, 6);
  FError.BorderSpacing.Left := Scale96ToScreen(LabelWidth);
  FCover := TCheckBox.Create(Self);
  FCover.Caption := rsSeriesCover;
  Place(FCover, 10);
  FCover.BorderSpacing.Left := Scale96ToScreen(LabelWidth);
  AddButtons(rsSeriesButton);
end;

procedure TSeriesForm.DoShow;
begin
  inherited DoShow;
  ActiveControl := FOkButton;
end;

{ format-patch makes the folder it writes to, but not the one above it;
  the cover letter is one file more. }
procedure TSeriesForm.Check;
var
  Folder, Err: string;
  n: integer;
begin
  Folder := Trim(FFolder.Text);
  if Folder <> '' then
    Folder := ExcludeTrailingPathDelimiter(ExpandFileName(Folder));
  n := FCount;
  if FCover.Checked then
    Inc(n);
  Err := '';
  if Folder = '' then
    FInto.Caption := ' '
  else if DirectoryExists(Folder) then
    FInto.Caption := Format(rsSeriesInto, [n])
  else if DirectoryExists(ExtractFileDir(Folder)) then
    FInto.Caption := Format(rsSeriesIntoNew, [n])
  else
  begin
    FInto.Caption := ' ';
    Err := Format(rsSeriesNoFolder, [ExtractFileDir(Folder)]);
  end;
  FError.Caption := Err;
  FError.Visible := Err <> '';
  FOkButton.Enabled := (Folder <> '') and (Err = '') and (FCount > 0);
end;

procedure TSeriesForm.FolderChange(Sender: TObject);
begin
  Check;
end;

procedure TSeriesForm.ChooseClick(Sender: TObject);
var
  D: TSelectDirectoryDialog;
begin
  D := TSelectDirectoryDialog.Create(Self);
  try
    D.Title := rsSeriesChooseTitle;
    if DirectoryExists(Trim(FFolder.Text)) then
      D.InitialDir := Trim(FFolder.Text);
    if D.Execute then
      FFolder.Text := D.FileName;
  finally
    D.Free;
  end;
end;

function ChoosePatchSeries(const ACommits: TGittanPatchCommits; var AFolder: string;
  var ACoverLetter: boolean): boolean;
var
  F: TSeriesForm;
  i: integer;
begin
  F := TSeriesForm.Create(Screen.ActiveForm);
  try
    if Length(ACommits) = 1 then
      F.FHint.Caption := rsSeriesHintOne
    else
      F.FHint.Caption := rsSeriesHint;
    for i := 0 to High(ACommits) do
      F.FList.Items.Add(ACommits[i].Short + '   ' + ACommits[i].Subject);
    F.FCount := Length(ACommits);
    F.FFolder.Text := AFolder;
    F.FCover.Checked := ACoverLetter;
    F.FCover.OnClick := @F.FolderChange;
    F.Check;
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      AFolder := ExcludeTrailingPathDelimiter(ExpandFileName(Trim(F.FFolder.Text)));
      ACoverLetter := F.FCover.Checked;
    end;
  finally
    F.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Apply Patches
  --------------------------------------------------------------------------- }

constructor TApplyForm.Create(AOwner: TComponent);
var
  Side: TPanel;
  Add: TButton;
begin
  inherited CreateFor(AOwner, rsApplyTitle);
  FHint.Caption := rsApplyHint;
  FFiles := TStringList.Create;

  { Add... and Remove beside the list. }
  Side := TPanel.Create(Self);
  Side.BevelOuter := bvNone;
  Side.AutoSize := True;
  Side.Align := alRight;
  Side.BorderSpacing.Right := Scale96ToScreen(Margin);
  Side.Parent := Self;
  FList.BorderSpacing.Right := Scale96ToScreen(8);
  FList.MultiSelect := True;
  FList.OnSelectionChange := @ListSelectionChange;
  Add := TButton.Create(Self);
  Add.Caption := rsApplyAdd;
  Add.AutoSize := True;
  Add.Constraints.MinWidth := Scale96ToScreen(84);
  Add.Align := alTop;
  Add.OnClick := @AddClick;
  Add.Parent := Side;
  FRemove := TButton.Create(Self);
  FRemove.Caption := rsApplyRemove;
  FRemove.AutoSize := True;
  FRemove.Align := alTop;
  FRemove.Top := 1000;
  FRemove.BorderSpacing.Top := Scale96ToScreen(6);
  FRemove.OnClick := @RemoveClick;
  FRemove.Parent := Side;

  FCommit := TRadioButton.Create(Self);
  FCommit.Caption := rsApplyCommit;
  FCommit.OnClick := @ModeClick;
  Place(FCommit, 12);
  FTree := TRadioButton.Create(Self);
  FTree.Caption := rsApplyTree;
  FTree.OnClick := @ModeClick;
  Place(FTree, 4);
  FNote := TLabel.Create(Self);
  FNote.WordWrap := True;
  FNote.Font.Color := clGrayText;
  FNote.ShowAccelChar := False;
  FNote.Visible := False;
  Place(FNote, 8);
  AddButtons(rsApplyButton);
end;

destructor TApplyForm.Destroy;
begin
  FFiles.Free;
  inherited Destroy;
end;

procedure TApplyForm.DoShow;
begin
  inherited DoShow;
  ActiveControl := FOkButton;
end;

{ The list shows the names; the paths are in FFiles. }
procedure TApplyForm.Fill;
var
  i: integer;
begin
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for i := 0 to FFiles.Count - 1 do
      FList.Items.Add(ExtractFileName(FFiles[i]));
  finally
    FList.Items.EndUpdate;
  end;
  Check;
end;

{ Committing takes mails only; the first file that is none is named. }
procedure TApplyForm.Check;
var
  NotMail: string;
  i: integer;
begin
  NotMail := '';
  for i := 0 to FFiles.Count - 1 do
    if (NotMail = '') and not IsMailPatchFile(FFiles[i]) then
      NotMail := ExtractFileName(FFiles[i]);
  FCommit.Enabled := NotMail = '';
  if NotMail <> '' then
    FTree.Checked := True
  else if not FTreeChosen then
    FCommit.Checked := True;
  FNote.Caption := Format(rsApplyNotMail, [NotMail]);
  FNote.Visible := NotMail <> '';
  FRemove.Enabled := FList.SelCount > 0;
  FOkButton.Enabled := FFiles.Count > 0;
end;

procedure TApplyForm.AddClick(Sender: TObject);
begin
  if PickPatchFiles(FFiles, FFolder) then
    Fill;
end;

procedure TApplyForm.RemoveClick(Sender: TObject);
var
  i: integer;
begin
  for i := FList.Items.Count - 1 downto 0 do
    if FList.Selected[i] then
      FFiles.Delete(i);
  Fill;
end;

procedure TApplyForm.ListSelectionChange(Sender: TObject; User: boolean);
begin
  FRemove.Enabled := FList.SelCount > 0;
end;

procedure TApplyForm.ModeClick(Sender: TObject);
begin
  if FCommit.Enabled then
    FTreeChosen := FTree.Checked;
end;

function PickPatchFiles(AFiles: TStrings; var AFolder: string): boolean;
var
  D: TOpenDialog;
  Picked: TStringList;
begin
  D := TOpenDialog.Create(nil);
  Picked := TStringList.Create;
  try
    D.Title := rsPickTitle;
    D.Filter := rsPickFilter;
    D.Options := D.Options + [ofAllowMultiSelect, ofFileMustExist];
    if DirectoryExists(AFolder) then
      D.InitialDir := AFolder;
    Result := D.Execute and (D.Files.Count > 0);
    if Result then
    begin
      { format-patch numbers its files, so by name is their order. }
      Picked.Assign(D.Files);
      Picked.Sort;
      AFiles.AddStrings(Picked);
      AFolder := ExtractFileDir(Picked[Picked.Count - 1]);
    end;
  finally
    Picked.Free;
    D.Free;
  end;
end;

function ChooseApplyPatches(AFiles: TStrings; var ACommit: boolean;
  var AFolder: string): boolean;
var
  F: TApplyForm;
begin
  F := TApplyForm.Create(Screen.ActiveForm);
  try
    F.FFolder := AFolder;
    F.FFiles.Assign(AFiles);
    F.FTreeChosen := not ACommit;
    F.FTree.Checked := not ACommit;
    F.Fill;
    Result := (F.ShowModal = mrOK) and (F.FFiles.Count > 0);
    AFolder := F.FFolder;
    if Result then
    begin
      AFiles.Assign(F.FFiles);
      ACommit := F.FCommit.Checked;
    end;
  finally
    F.Free;
  end;
end;

end.
