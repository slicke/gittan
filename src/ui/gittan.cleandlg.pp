unit gittan.cleandlg;

{** The dialog of Clean: a box chooses what goes (untracked files,
  ignored files or
  both), and the list under it shows what `git clean -n` says would go
  for that choice (TGittanRepo.CleanPreview), a folder whose every file
  goes as one row ending in a slash, each with a box, all ticked. Tick
  All and Untick All set every box; Delete, which counts the ticked
  rows, is off while none is. git keeps no copy of what it cleans, which
  the dialog says above the buttons. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, CheckLst, gittan.git;

{** Shows what ARepo would clean, starting with AKind. True when Delete
  was pressed, with AKind as the box left it and APaths the ticked
  paths, in the list's order. }
function ChooseClean(ARepo: TGittanRepo; var AKind: TGittanCleanKind;
  APaths: TStrings): boolean;

implementation

uses
  Graphics;

resourcestring
  rsCleanTitle = 'Clean';
  rsCleanHint = 'Deletes files git does not track from the work tree. The list shows what ' +
    'git clean would delete; a folder ending in a slash goes with everything in it.';
  rsCleanKindLabel = 'Delete';
  rsCleanUntracked = 'Untracked files';
  rsCleanIgnored = 'Ignored files';
  rsCleanAll = 'Untracked and ignored files';
  rsCleanTickAll = 'Tick All';
  rsCleanUntickAll = 'Untick All';
  rsCleanCount = '%d of %d ticked';
  rsCleanNone = 'Nothing to clean';
  rsCleanForGood = 'They are deleted for good: git keeps no copy, and they do not go to the trash.';
  rsCleanButton = 'Delete';
  rsCleanButtonN = 'Delete %d';
  rsCancel = 'Cancel';

const
  DialogWidth = 620;
  DialogHeight = 520;
  Margin = 12;

type

  { TCleanForm }

  TCleanForm = class(TForm)
  private
    FRepo: TGittanRepo;
    FHint, FKindLabel, FCount, FForGood, FError: TLabel;
    FKindBox: TComboBox;
    FList: TCheckListBox;
    FTickAll, FUntickAll, FDeleteButton: TButton;
    FBottom: TPanel;
    FNextTop: integer;
    function Kind: TGittanCleanKind;
    procedure Fill;
    procedure Count;
    procedure Place(AControl: TControl; ASpaceAbove: integer);
    procedure KindBoxChange(Sender: TObject);
    procedure ListClickCheck(Sender: TObject);
    procedure TickClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TCleanForm.Create(AOwner: TComponent);
var
  Row: TPanel;
  Cancel: TButton;
begin
  inherited CreateNew(AOwner);
  Caption := rsCleanTitle;
  BorderStyle := bsSizeable;
  Position := poMainFormCenter;
  Width := Scale96ToScreen(DialogWidth);
  Height := Scale96ToScreen(DialogHeight);
  Constraints.MinWidth := Scale96ToScreen(420);
  Constraints.MinHeight := Scale96ToScreen(320);

  FHint := TLabel.Create(Self);
  FHint.Caption := rsCleanHint;
  FHint.WordWrap := True;
  FHint.Align := alTop;
  FHint.BorderSpacing.Around := Scale96ToScreen(Margin);
  FHint.Parent := Self;

  { What goes, in a row under the hint. }
  Row := TPanel.Create(Self);
  Row.BevelOuter := bvNone;
  Row.AutoSize := True;
  Row.Align := alTop;
  Row.Top := 1000;
  Row.BorderSpacing.Left := Scale96ToScreen(Margin);
  Row.BorderSpacing.Right := Scale96ToScreen(Margin);
  Row.BorderSpacing.Bottom := Scale96ToScreen(8);
  Row.Parent := Self;
  FKindLabel := TLabel.Create(Self);
  FKindLabel.Caption := rsCleanKindLabel;
  FKindLabel.Align := alLeft;
  FKindLabel.Layout := tlCenter;
  FKindLabel.Parent := Row;
  FKindBox := TComboBox.Create(Self);
  FKindBox.Style := csDropDownList;
  FKindBox.Items.Add(rsCleanUntracked);
  FKindBox.Items.Add(rsCleanIgnored);
  FKindBox.Items.Add(rsCleanAll);
  FKindBox.Width := Scale96ToScreen(240);
  FKindBox.Align := alLeft;
  FKindBox.Left := 100;
  FKindBox.BorderSpacing.Left := Scale96ToScreen(8);
  FKindBox.OnChange := @KindBoxChange;
  FKindBox.Parent := Row;

  { Everything under the list in one panel that sizes itself, the
    controls stacked by Place. }
  FBottom := TPanel.Create(Self);
  FBottom.BevelOuter := bvNone;
  FBottom.AutoSize := True;
  FBottom.Align := alBottom;
  FBottom.BorderSpacing.Left := Scale96ToScreen(Margin);
  FBottom.BorderSpacing.Right := Scale96ToScreen(Margin);
  FBottom.BorderSpacing.Bottom := Scale96ToScreen(Margin);
  FBottom.Parent := Self;

  FList := TCheckListBox.Create(Self);
  FList.Align := alClient;
  FList.BorderSpacing.Left := Scale96ToScreen(Margin);
  FList.BorderSpacing.Right := Scale96ToScreen(Margin);
  FList.OnClickCheck := @ListClickCheck;
  FList.Parent := Self;

  { The count and the tick buttons in a row. }
  Row := TPanel.Create(Self);
  Row.BevelOuter := bvNone;
  Row.AutoSize := True;
  Place(Row, 8);
  FCount := TLabel.Create(Self);
  FCount.Align := alLeft;
  FCount.Layout := tlCenter;
  FCount.Parent := Row;
  FUntickAll := TButton.Create(Self);
  FUntickAll.Caption := rsCleanUntickAll;
  FUntickAll.AutoSize := True;
  FUntickAll.Align := alRight;
  FUntickAll.Left := 1000;
  FUntickAll.BorderSpacing.Left := Scale96ToScreen(8);
  FUntickAll.Tag := 0;
  FUntickAll.OnClick := @TickClick;
  FUntickAll.Parent := Row;
  FTickAll := TButton.Create(Self);
  FTickAll.Caption := rsCleanTickAll;
  FTickAll.AutoSize := True;
  FTickAll.Align := alRight;
  FTickAll.Left := 0;
  FTickAll.Tag := 1;
  FTickAll.OnClick := @TickClick;
  FTickAll.Parent := Row;

  FError := TLabel.Create(Self);
  FError.WordWrap := True;
  FError.Font.Color := clRed;
  FError.Visible := False;
  Place(FError, 8);
  FForGood := TLabel.Create(Self);
  FForGood.Caption := rsCleanForGood;
  FForGood.WordWrap := True;
  Place(FForGood, 12);

  { Delete on the right on macOS, Cancel on the right elsewhere. }
  Row := TPanel.Create(Self);
  Row.BevelOuter := bvNone;
  Row.AutoSize := True;
  Place(Row, 16);
  FDeleteButton := TButton.Create(Self);
  FDeleteButton.Caption := rsCleanButton;
  FDeleteButton.ModalResult := mrOK;
  FDeleteButton.AutoSize := True;
  FDeleteButton.Constraints.MinWidth := Scale96ToScreen(84);
  FDeleteButton.Align := alRight;
  FDeleteButton.Parent := Row;
  Cancel := TButton.Create(Self);
  Cancel.Caption := rsCancel;
  Cancel.ModalResult := mrCancel;
  Cancel.Cancel := True;
  Cancel.Default := True;
  Cancel.AutoSize := True;
  Cancel.Constraints.MinWidth := Scale96ToScreen(84);
  Cancel.Align := alRight;
  Cancel.Parent := Row;
  {$IFDEF DARWIN}
  Cancel.Left := 0;
  FDeleteButton.Left := 1000;
  {$ELSE}
  FDeleteButton.Left := 0;
  Cancel.Left := 1000;
  {$ENDIF}
  Cancel.BorderSpacing.Left := Scale96ToScreen(8);
  FDeleteButton.BorderSpacing.Left := Scale96ToScreen(8);
end;

{ Puts AControl under the ones placed before it in the bottom panel:
  alTop stacks controls by their Top. }
procedure TCleanForm.Place(AControl: TControl; ASpaceAbove: integer);
begin
  AControl.Align := alTop;
  AControl.BorderSpacing.Top := Scale96ToScreen(ASpaceAbove);
  Inc(FNextTop, 1000);
  AControl.Top := FNextTop;
  AControl.Parent := FBottom;
end;

procedure TCleanForm.DoShow;
begin
  inherited DoShow;
  ActiveControl := FList;
end;

function TCleanForm.Kind: TGittanCleanKind;
begin
  if FKindBox.ItemIndex < 0 then
    Result := cnUntracked
  else
    Result := TGittanCleanKind(FKindBox.ItemIndex);
end;

{ The list as git clean -n gives it for the chosen kind, every row
  ticked; a failure is said under the list. }
procedure TCleanForm.Fill;
var
  Paths: TStringList;
  Ok: boolean;
  i: integer;
begin
  Paths := TStringList.Create;
  try
    Screen.Cursor := crHourGlass;
    try
      Ok := FRepo.CleanPreview(Kind, Paths);
    finally
      Screen.Cursor := crDefault;
    end;
    FList.Items.BeginUpdate;
    try
      FList.Items.Assign(Paths);
      for i := 0 to FList.Items.Count - 1 do
        FList.Checked[i] := True;
    finally
      FList.Items.EndUpdate;
    end;
    if Ok then
      FError.Caption := ''
    else
      FError.Caption := FRepo.Error;
    FError.Visible := FError.Caption <> '';
  finally
    Paths.Free;
  end;
  Count;
end;

procedure TCleanForm.Count;
var
  i, n: integer;
begin
  n := 0;
  for i := 0 to FList.Items.Count - 1 do
    if FList.Checked[i] then
      Inc(n);
  if FList.Items.Count = 0 then
    FCount.Caption := rsCleanNone
  else
    FCount.Caption := Format(rsCleanCount, [n, FList.Items.Count]);
  if n > 0 then
    FDeleteButton.Caption := Format(rsCleanButtonN, [n])
  else
    FDeleteButton.Caption := rsCleanButton;
  FDeleteButton.Enabled := n > 0;
  FTickAll.Enabled := n < FList.Items.Count;
  FUntickAll.Enabled := n > 0;
end;

procedure TCleanForm.KindBoxChange(Sender: TObject);
begin
  Fill;
end;

procedure TCleanForm.ListClickCheck(Sender: TObject);
begin
  Count;
end;

procedure TCleanForm.TickClick(Sender: TObject);
begin
  if (Sender as TButton).Tag = 1 then
    FList.CheckAll(cbChecked, False, False)
  else
    FList.CheckAll(cbUnchecked, False, False);
  Count;
end;

function ChooseClean(ARepo: TGittanRepo; var AKind: TGittanCleanKind;
  APaths: TStrings): boolean;
var
  F: TCleanForm;
  i: integer;
begin
  APaths.Clear;
  F := TCleanForm.Create(Screen.ActiveForm);
  try
    F.FRepo := ARepo;
    { OnChange would fill the list here already on some widgetsets. }
    F.FKindBox.OnChange := nil;
    F.FKindBox.ItemIndex := Ord(AKind);
    F.FKindBox.OnChange := @F.KindBoxChange;
    F.Fill;
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      AKind := F.Kind;
      for i := 0 to F.FList.Items.Count - 1 do
        if F.FList.Checked[i] then
          APaths.Add(F.FList.Items[i]);
      Result := APaths.Count > 0;
    end;
  finally
    F.Free;
  end;
end;

end.
