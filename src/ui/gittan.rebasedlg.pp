unit gittan.rebasedlg;

{** The dialog of an interactive rebase: the commits a rebase
  replays in a list, newest first as
  the commit graph shows them, each with its action (Pick, Reword,
  Edit, Squash, Fixup or Drop), its subject, its author and its short
  id; under it the action of the highlighted commit in a box, Move Up
  and Move Down, which change the order they are replayed in, and its
  message in a field, where it can be rewritten: a Pick whose message
  is changed becomes a Reword, and a Reword given its message back a
  Pick. In the list P, R, E, S, F and D set the action, Delete drops,
  and Alt+Up and Alt+Down move. A squash or fixup with no commit kept
  below it to fold into is said under the list and keeps the Rebase
  button off (CheckRebaseSteps). The steps come and go in replay
  order (gittan.rebase), oldest first; a row's step is counted from
  the end. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, gittan.rebase;

{** Shows ASteps, oldest first, in the dialog titled ATitle with the
  note ANote under the list (the push that must be forced; none when
  empty). True when Rebase was pressed, with ASteps as the dialog left
  them: their order, actions and messages. }
function EditRebase(var ASteps: TGittanRebaseSteps; const ATitle, ANote: string): boolean;

implementation

uses
  LCLType, Graphics, Math;

resourcestring
  rsRebaseHint = 'The commits are replayed from the bottom up. Squash and Fixup fold a ' +
    'commit into the one below it; Edit stops after it so it can be amended.';
  rsColAction = 'Action';
  rsColCommit = 'Commit';
  rsColAuthor = 'Author';
  rsColId = 'Id';
  rsActionLabel = 'Action';
  rsMoveUp = 'Move Up';
  rsMoveDown = 'Move Down';
  rsMessageLabel = 'Message';
  rsRebaseButton = 'Rebase';
  rsCancel = 'Cancel';
  rsActionPick = 'Pick';
  rsActionReword = 'Reword';
  rsActionEdit = 'Edit';
  rsActionSquash = 'Squash';
  rsActionFixup = 'Fixup';
  rsActionDrop = 'Drop';

const
  DialogWidth = 760;
  DialogHeight = 580;
  Margin = 12;
  MessageHeight = 96;

type

  { TRebaseForm }

  TRebaseForm = class(TForm)
  private
    FSteps: TGittanRebaseSteps;
    FHint, FActionLabel, FMessageLabel, FNote, FError: TLabel;
    FList: TListView;
    FActionBox: TComboBox;
    FUpButton, FDownButton, FRebaseButton: TButton;
    FMemo: TMemo;
    FBottom: TPanel;
    FNextTop: integer;
    FLoading: boolean;
    function StepIndex(ARow: integer): integer;
    function CurrentRow: integer;
    procedure Fill;
    procedure ShowStep(ARow: integer);
    procedure ShowRow(ARow: integer);
    procedure SelectRow(ARow: integer);
    procedure SetStepAction(AStep: integer; AAction: TGittanRebaseAction);
    procedure Check;
    procedure Place(AControl: TControl; ASpaceAbove: integer);
    function AddLabel(const ACaption: string; ASpaceAbove: integer): TLabel;
    procedure ListSelect(Sender: TObject; Item: TListItem; Selected: boolean);
    procedure ListResize(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure ActionBoxChange(Sender: TObject);
    procedure MemoChange(Sender: TObject);
    procedure MoveClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

function ActionCaption(AAction: TGittanRebaseAction): string;
begin
  case AAction of
    raPick: Result := rsActionPick;
    raReword: Result := rsActionReword;
    raEdit: Result := rsActionEdit;
    raSquash: Result := rsActionSquash;
    raFixup: Result := rsActionFixup;
    else
      Result := rsActionDrop;
  end;
end;

{ The first line of a message, what the list shows as the subject. }
function FirstLine(const AText: string): string;
var
  p: integer;
begin
  Result := Trim(AText);
  p := Pos(#10, Result);
  if p > 0 then
    Result := TrimRight(Copy(Result, 1, p - 1));
  Result := StringReplace(Result, #13, '', [rfReplaceAll]);
end;

constructor TRebaseForm.Create(AOwner: TComponent);
var
  Row: TPanel;
  Cancel: TButton;
  Act: TGittanRebaseAction;
begin
  inherited CreateNew(AOwner);
  BorderStyle := bsSizeable;
  Position := poMainFormCenter;
  Width := Scale96ToScreen(DialogWidth);
  Height := Scale96ToScreen(DialogHeight);
  Constraints.MinWidth := Scale96ToScreen(520);
  Constraints.MinHeight := Scale96ToScreen(400);

  FHint := TLabel.Create(Self);
  FHint.Caption := rsRebaseHint;
  FHint.WordWrap := True;
  FHint.Align := alTop;
  FHint.BorderSpacing.Around := Scale96ToScreen(Margin);
  FHint.Parent := Self;

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

  FList := TListView.Create(Self);
  FList.ViewStyle := vsReport;
  FList.RowSelect := True;
  FList.ReadOnly := True;
  FList.HideSelection := False;
  FList.MultiSelect := False;
  FList.ShowColumnHeaders := True;
  with FList.Columns.Add do
  begin
    Caption := rsColAction;
    Width := Scale96ToScreen(80);
  end;
  with FList.Columns.Add do
  begin
    Caption := rsColCommit;
    Width := Scale96ToScreen(380);
  end;
  with FList.Columns.Add do
  begin
    Caption := rsColAuthor;
    Width := Scale96ToScreen(150);
  end;
  with FList.Columns.Add do
  begin
    Caption := rsColId;
    Width := Scale96ToScreen(80);
  end;
  FList.Align := alClient;
  FList.BorderSpacing.Left := Scale96ToScreen(Margin);
  FList.BorderSpacing.Right := Scale96ToScreen(Margin);
  FList.OnSelectItem := @ListSelect;
  FList.OnResize := @ListResize;
  FList.OnKeyDown := @ListKeyDown;
  FList.Parent := Self;

  { The action and the move buttons in a row. }
  Row := TPanel.Create(Self);
  Row.BevelOuter := bvNone;
  Row.AutoSize := True;
  Place(Row, 8);
  FActionLabel := TLabel.Create(Self);
  FActionLabel.Caption := rsActionLabel;
  FActionLabel.Align := alLeft;
  FActionLabel.Layout := tlCenter;
  FActionLabel.Left := 0;
  FActionLabel.Parent := Row;
  FActionBox := TComboBox.Create(Self);
  FActionBox.Style := csDropDownList;
  for Act := Low(TGittanRebaseAction) to High(TGittanRebaseAction) do
    FActionBox.Items.Add(ActionCaption(Act));
  FActionBox.Width := Scale96ToScreen(120);
  FActionBox.Align := alLeft;
  FActionBox.Left := 100;
  FActionBox.BorderSpacing.Left := Scale96ToScreen(8);
  FActionBox.OnChange := @ActionBoxChange;
  FActionBox.Parent := Row;
  FUpButton := TButton.Create(Self);
  FUpButton.Caption := rsMoveUp;
  FUpButton.AutoSize := True;
  FUpButton.Align := alLeft;
  FUpButton.Left := 200;
  FUpButton.BorderSpacing.Left := Scale96ToScreen(16);
  FUpButton.Tag := 1;
  FUpButton.OnClick := @MoveClick;
  FUpButton.Parent := Row;
  FDownButton := TButton.Create(Self);
  FDownButton.Caption := rsMoveDown;
  FDownButton.AutoSize := True;
  FDownButton.Align := alLeft;
  FDownButton.Left := 300;
  FDownButton.BorderSpacing.Left := Scale96ToScreen(8);
  FDownButton.Tag := -1;
  FDownButton.OnClick := @MoveClick;
  FDownButton.Parent := Row;

  FMessageLabel := AddLabel(rsMessageLabel, 12);
  FMemo := TMemo.Create(Self);
  FMemo.Height := Scale96ToScreen(MessageHeight);
  FMemo.ScrollBars := ssAutoVertical;
  FMemo.WantReturns := True;
  FMemo.WantTabs := False;
  FMemo.OnChange := @MemoChange;
  Place(FMemo, 4);

  FNote := AddLabel('', 8);
  FNote.WordWrap := True;
  FNote.Visible := False;
  FError := AddLabel('', 8);
  FError.WordWrap := True;
  FError.Font.Color := clRed;
  FError.Visible := False;

  { Rebase on the right on macOS, Cancel on the right elsewhere. }
  Row := TPanel.Create(Self);
  Row.BevelOuter := bvNone;
  Row.AutoSize := True;
  Place(Row, 16);
  FRebaseButton := TButton.Create(Self);
  FRebaseButton.Caption := rsRebaseButton;
  FRebaseButton.ModalResult := mrOK;
  FRebaseButton.Default := True;
  FRebaseButton.AutoSize := True;
  FRebaseButton.Constraints.MinWidth := Scale96ToScreen(84);
  FRebaseButton.Align := alRight;
  FRebaseButton.Parent := Row;
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
  FRebaseButton.Left := 1000;
  {$ELSE}
  FRebaseButton.Left := 0;
  Cancel.Left := 1000;
  {$ENDIF}
  Cancel.BorderSpacing.Left := Scale96ToScreen(8);
  FRebaseButton.BorderSpacing.Left := Scale96ToScreen(8);
end;

{ Puts AControl under the ones placed before it in the bottom panel:
  alTop stacks controls by their Top. }
procedure TRebaseForm.Place(AControl: TControl; ASpaceAbove: integer);
begin
  AControl.Align := alTop;
  AControl.BorderSpacing.Top := Scale96ToScreen(ASpaceAbove);
  Inc(FNextTop, 1000);
  AControl.Top := FNextTop;
  AControl.Parent := FBottom;
end;

function TRebaseForm.AddLabel(const ACaption: string; ASpaceAbove: integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Caption := ACaption;
  Place(Result, ASpaceAbove);
end;

procedure TRebaseForm.DoShow;
begin
  inherited DoShow;
  if FList.Items.Count > 0 then
    SelectRow(0);
  ActiveControl := FList;
end;

{ The rows show the steps newest first; the last step is the first
  row. }
function TRebaseForm.StepIndex(ARow: integer): integer;
begin
  Result := High(FSteps) - ARow;
end;

function TRebaseForm.CurrentRow: integer;
begin
  if FList.Selected <> nil then
    Result := FList.Selected.Index
  else
    Result := -1;
end;

procedure TRebaseForm.Fill;
var
  Row: integer;
  Item: TListItem;
begin
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for Row := 0 to High(FSteps) do
    begin
      Item := FList.Items.Add;
      Item.Caption := '';
      Item.SubItems.Add('');
      Item.SubItems.Add('');
      Item.SubItems.Add('');
      ShowRow(Row);
    end;
  finally
    FList.Items.EndUpdate;
  end;
end;

{ A row's columns as its step is. }
procedure TRebaseForm.ShowRow(ARow: integer);
var
  Item: TListItem;
begin
  if (ARow < 0) or (ARow >= FList.Items.Count) then
    Exit;
  Item := FList.Items[ARow];
  with FSteps[StepIndex(ARow)] do
  begin
    Item.Caption := ActionCaption(Action);
    Item.SubItems[0] := FirstLine(Message);
    Item.SubItems[1] := Author;
    Item.SubItems[2] := Short;
  end;
end;

{ The box and the field as the highlighted step is. Up moves a step
  later in the replay, which the last step cannot go; Down earlier. }
procedure TRebaseForm.ShowStep(ARow: integer);
var
  Step: integer;
begin
  FLoading := True;
  try
    if (ARow < 0) or (ARow > High(FSteps)) then
    begin
      FActionBox.ItemIndex := -1;
      FActionBox.Enabled := False;
      FMemo.Clear;
      FMemo.Enabled := False;
      FUpButton.Enabled := False;
      FDownButton.Enabled := False;
      Exit;
    end;
    Step := StepIndex(ARow);
    FActionBox.Enabled := True;
    FActionBox.ItemIndex := Ord(FSteps[Step].Action);
    FMemo.Enabled := True;
    FMemo.Text := FSteps[Step].Message;
    FUpButton.Enabled := Step < High(FSteps);
    FDownButton.Enabled := Step > 0;
  finally
    FLoading := False;
  end;
end;

procedure TRebaseForm.SelectRow(ARow: integer);
begin
  if (ARow < 0) or (ARow >= FList.Items.Count) then
    Exit;
  FList.Selected := FList.Items[ARow];
  FList.ItemFocused := FList.Items[ARow];
  FList.Items[ARow].MakeVisible(False);
  ShowStep(ARow);
end;

{ The subject column takes what the others leave, so no row runs
  past the list. }
procedure TRebaseForm.ListResize(Sender: TObject);
var
  Rest, i: integer;
begin
  if FList.Columns.Count < 4 then
    Exit;
  Rest := FList.ClientWidth - Scale96ToScreen(4);
  for i := 0 to FList.Columns.Count - 1 do
    if i <> 1 then
      Dec(Rest, FList.Columns[i].Width);
  FList.Columns[1].Width := Max(Scale96ToScreen(120), Rest);
end;

procedure TRebaseForm.ListSelect(Sender: TObject; Item: TListItem; Selected: boolean);
begin
  if Selected then
    ShowStep(Item.Index)
  else if FList.Selected = nil then
    ShowStep(-1);
end;

procedure TRebaseForm.SetStepAction(AStep: integer; AAction: TGittanRebaseAction);
begin
  if (AStep < 0) or (AStep > High(FSteps)) then
    Exit;
  FSteps[AStep].Action := AAction;
  ShowRow(High(FSteps) - AStep);
  if CurrentRow = High(FSteps) - AStep then
  begin
    FLoading := True;
    FActionBox.ItemIndex := Ord(AAction);
    FLoading := False;
  end;
  Check;
end;

{ A squash or fixup that folds into nothing is said and keeps Rebase
  off. }
procedure TRebaseForm.Check;
var
  Error: string;
begin
  FRebaseButton.Enabled := CheckRebaseSteps(FSteps, Error);
  FError.Caption := Error;
  FError.Visible := Error <> '';
end;

procedure TRebaseForm.ListKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
var
  Step: integer;
  Act: TGittanRebaseAction;
begin
  Step := StepIndex(CurrentRow);
  if (CurrentRow < 0) or (Step < 0) then
    Exit;
  if (Shift = [ssAlt]) and (Key in [VK_UP, VK_DOWN]) then
  begin
    if Key = VK_UP then
      MoveClick(FUpButton)
    else
      MoveClick(FDownButton);
    Key := 0;
    Exit;
  end;
  if Shift <> [] then
    Exit;
  case Key of
    Ord('P'): Act := raPick;
    Ord('R'): Act := raReword;
    Ord('E'): Act := raEdit;
    Ord('S'): Act := raSquash;
    Ord('F'): Act := raFixup;
    { Backspace is the key a Mac keyboard labels Delete. }
    Ord('D'), VK_DELETE, VK_BACK: Act := raDrop;
    else
      Exit;
  end;
  SetStepAction(Step, Act);
  Key := 0;
end;

procedure TRebaseForm.ActionBoxChange(Sender: TObject);
begin
  if FLoading or (FActionBox.ItemIndex < 0) or (CurrentRow < 0) then
    Exit;
  SetStepAction(StepIndex(CurrentRow), TGittanRebaseAction(FActionBox.ItemIndex));
end;

{ A Pick given another message is a Reword, and a Reword given its own
  back a Pick; the other actions keep the message as it is. }
procedure TRebaseForm.MemoChange(Sender: TObject);
var
  Step: integer;
begin
  if FLoading or (CurrentRow < 0) then
    Exit;
  Step := StepIndex(CurrentRow);
  FSteps[Step].Message := FMemo.Text;
  if (FSteps[Step].Action = raPick) and not MessageUnchanged(FSteps[Step]) then
    SetStepAction(Step, raReword)
  else if (FSteps[Step].Action = raReword) and MessageUnchanged(FSteps[Step]) then
    SetStepAction(Step, raPick)
  else
    ShowRow(CurrentRow);
end;

{ Swaps the highlighted step with its neighbor: Tag 1 moves it later
  in the replay (up in the list), -1 earlier. }
procedure TRebaseForm.MoveClick(Sender: TObject);
var
  Step, Other: integer;
  Swap: TGittanRebaseStep;
begin
  if CurrentRow < 0 then
    Exit;
  Step := StepIndex(CurrentRow);
  Other := Step + (Sender as TControl).Tag;
  if (Other < 0) or (Other > High(FSteps)) then
    Exit;
  Swap := FSteps[Step];
  FSteps[Step] := FSteps[Other];
  FSteps[Other] := Swap;
  ShowRow(High(FSteps) - Step);
  ShowRow(High(FSteps) - Other);
  SelectRow(High(FSteps) - Other);
  Check;
  FList.SetFocus;
end;

function EditRebase(var ASteps: TGittanRebaseSteps; const ATitle, ANote: string): boolean;
var
  F: TRebaseForm;
begin
  F := TRebaseForm.Create(Screen.ActiveForm);
  try
    F.Caption := ATitle;
    F.FSteps := Copy(ASteps);
    F.FNote.Caption := ANote;
    F.FNote.Visible := ANote <> '';
    F.Fill;
    F.Check;
    Result := F.ShowModal = mrOK;
    if Result then
      ASteps := F.FSteps;
  finally
    F.Free;
  end;
end;

end.
