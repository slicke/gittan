unit gittan.absorbdlg;

{** The dialog of Commit > Put Changes into Their Commits...: the
  changes of the chosen files (TGittanAbsorbPlan) in a list, each
  ticked with the commit it goes into, "a.txt:12 → a1b2c3 Add parser",
  or dimmed and unticked with why it cannot be placed; Tick All and
  Untick All set the boxes of those that can; a note under the list
  says that the branch is rewritten and that Undo takes it back, and
  how many of the commits are pushed already; Put, which counts the
  ticked rows, is off while none is. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, StdCtrls, ExtCtrls, CheckLst, gittan.absorb;

{** Shows APlan's hunks and asks which go. True when Put was pressed,
  with AChosen (one per hunk, as AbsorbRun takes them) as the boxes
  were left; ANote is said under the list, '' for nothing. }
function ChooseAbsorb(APlan: TGittanAbsorbPlan; out AChosen: TBooleanDynArray;
  const ANote: string): boolean;

implementation

uses
  Graphics;

resourcestring
  rsAbsorbDlgTitle = 'Put Changes into Their Commits';
  rsAbsorbDlgHint = 'Each change goes into the commit of this branch that last changed ' +
    'its lines, as a fixup commit that is folded in at once. A change that cannot be ' +
    'placed stays in the work tree.';
  rsAbsorbRow = '%s:%d  →  %s  %s';
  rsAbsorbRowCannot = '%s:%d  —  %s';
  rsAbsorbTickAll = 'Tick All';
  rsAbsorbUntickAll = 'Untick All';
  rsAbsorbCount = '%d of %d ticked';
  rsAbsorbCountNone = 'None of the changes can be placed';
  rsAbsorbRewrites = 'The commits after the oldest one changed are rewritten; ' +
    'Branch > Undo takes it back.';
  rsAbsorbButton = 'Put';
  rsAbsorbButtonN = 'Put %d';
  rsCancel = 'Cancel';

const
  DialogWidth = 640;
  DialogHeight = 480;
  Margin = 12;

type

  { TAbsorbForm }

  TAbsorbForm = class(TForm)
  private
    FPlan: TGittanAbsorbPlan;
    FHint, FCount, FNote: TLabel;
    FList: TCheckListBox;
    FTickAll, FUntickAll, FPutButton: TButton;
    FBottom: TPanel;
    FNextTop: integer;
    procedure Fill;
    procedure Count;
    procedure Place(AControl: TControl; ASpaceAbove: integer);
    procedure ListClickCheck(Sender: TObject);
    procedure TickClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TAbsorbForm.Create(AOwner: TComponent);
var
  Row: TPanel;
  Cancel: TButton;
begin
  inherited CreateNew(AOwner);
  Caption := rsAbsorbDlgTitle;
  BorderStyle := bsSizeable;
  Position := poMainFormCenter;
  Width := Scale96ToScreen(DialogWidth);
  Height := Scale96ToScreen(DialogHeight);
  Constraints.MinWidth := Scale96ToScreen(440);
  Constraints.MinHeight := Scale96ToScreen(300);

  FHint := TLabel.Create(Self);
  FHint.Caption := rsAbsorbDlgHint;
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
  FUntickAll.Caption := rsAbsorbUntickAll;
  FUntickAll.AutoSize := True;
  FUntickAll.Align := alRight;
  FUntickAll.Left := 1000;
  FUntickAll.BorderSpacing.Left := Scale96ToScreen(8);
  FUntickAll.Tag := 0;
  FUntickAll.OnClick := @TickClick;
  FUntickAll.Parent := Row;
  FTickAll := TButton.Create(Self);
  FTickAll.Caption := rsAbsorbTickAll;
  FTickAll.AutoSize := True;
  FTickAll.Align := alRight;
  FTickAll.Left := 0;
  FTickAll.Tag := 1;
  FTickAll.OnClick := @TickClick;
  FTickAll.Parent := Row;

  FNote := TLabel.Create(Self);
  FNote.WordWrap := True;
  Place(FNote, 12);

  { Put on the right on macOS, Cancel on the right elsewhere. }
  Row := TPanel.Create(Self);
  Row.BevelOuter := bvNone;
  Row.AutoSize := True;
  Place(Row, 16);
  FPutButton := TButton.Create(Self);
  FPutButton.Caption := rsAbsorbButton;
  FPutButton.ModalResult := mrOK;
  FPutButton.Default := True;
  FPutButton.AutoSize := True;
  FPutButton.Constraints.MinWidth := Scale96ToScreen(84);
  FPutButton.Align := alRight;
  FPutButton.Parent := Row;
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
  FPutButton.Left := 1000;
  {$ELSE}
  FPutButton.Left := 0;
  Cancel.Left := 1000;
  {$ENDIF}
  Cancel.BorderSpacing.Left := Scale96ToScreen(8);
  FPutButton.BorderSpacing.Left := Scale96ToScreen(8);
end;

{ Puts AControl under the ones placed before it in the bottom panel:
  alTop stacks controls by their Top. }
procedure TAbsorbForm.Place(AControl: TControl; ASpaceAbove: integer);
begin
  AControl.Align := alTop;
  AControl.BorderSpacing.Top := Scale96ToScreen(ASpaceAbove);
  Inc(FNextTop, 1000);
  AControl.Top := FNextTop;
  AControl.Parent := FBottom;
end;

procedure TAbsorbForm.DoShow;
begin
  inherited DoShow;
  ActiveControl := FList;
end;

{ A row per hunk: ticked and enabled with its commit, else dimmed with
  the reason. }
procedure TAbsorbForm.Fill;
var
  i: integer;
begin
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for i := 0 to High(FPlan.Hunks) do
      with FPlan.Hunks[i] do
        if Target >= 0 then
        begin
          FList.Items.Add(Format(rsAbsorbRow, [Path, Line, FPlan.Steps[Target].Short,
            FPlan.Steps[Target].Subject]));
          FList.Checked[i] := True;
        end
        else
        begin
          FList.Items.Add(Format(rsAbsorbRowCannot, [Path, Line, Reason]));
          FList.Checked[i] := False;
          FList.ItemEnabled[i] := False;
        end;
  finally
    FList.Items.EndUpdate;
  end;
  Count;
end;

procedure TAbsorbForm.Count;
var
  i, n, Can: integer;
begin
  n := 0;
  Can := 0;
  for i := 0 to FList.Items.Count - 1 do
  begin
    if FList.ItemEnabled[i] then
      Inc(Can);
    if FList.Checked[i] then
      Inc(n);
  end;
  if Can = 0 then
    FCount.Caption := rsAbsorbCountNone
  else
    FCount.Caption := Format(rsAbsorbCount, [n, Can]);
  if n > 0 then
    FPutButton.Caption := Format(rsAbsorbButtonN, [n])
  else
    FPutButton.Caption := rsAbsorbButton;
  FPutButton.Enabled := n > 0;
  FTickAll.Enabled := n < Can;
  FUntickAll.Enabled := n > 0;
end;

procedure TAbsorbForm.ListClickCheck(Sender: TObject);
begin
  Count;
end;

{ The boxes of the rows that can be placed; a disabled row stays. }
procedure TAbsorbForm.TickClick(Sender: TObject);
begin
  if (Sender as TButton).Tag = 1 then
    FList.CheckAll(cbChecked, False, False)
  else
    FList.CheckAll(cbUnchecked, False, False);
  Count;
end;

function ChooseAbsorb(APlan: TGittanAbsorbPlan; out AChosen: TBooleanDynArray;
  const ANote: string): boolean;
var
  F: TAbsorbForm;
  i: integer;
begin
  AChosen := nil;
  F := TAbsorbForm.Create(Screen.ActiveForm);
  try
    F.FPlan := APlan;
    if ANote = '' then
      F.FNote.Caption := rsAbsorbRewrites
    else
      F.FNote.Caption := rsAbsorbRewrites + ' ' + ANote;
    F.Fill;
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      SetLength(AChosen, F.FList.Items.Count);
      for i := 0 to F.FList.Items.Count - 1 do
        AChosen[i] := F.FList.Checked[i] and F.FList.ItemEnabled[i];
    end;
  finally
    F.Free;
  end;
end;

end.
