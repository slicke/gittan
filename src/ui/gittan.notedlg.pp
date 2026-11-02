unit gittan.notedlg;

{** The dialog of a commit's note (git notes): a hint, the text in a
  memo and Save; an emptied text removes the note, which the hint says. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls;

{** Asks for the note of the commit ACommitLabel (its short id or name),
  starting with AText; True when Save was pressed, with the text in
  AText as typed (trimmed of its blank ends). }
function EditCommitNote(const ACommitLabel: string; var AText: string): boolean;

implementation

uses
  Graphics, LCLType;

resourcestring
  rsNoteTitle = 'Note on %s';
  rsNoteHint = 'A note is kept beside the commit (git notes), not in it, so adding one ' +
    'rewrites no history. Leave the text empty to remove the note.';
  rsNoteSave = 'Save';
  rsNoteCancel = 'Cancel';

const
  Margin = 16;

type

  { TNoteForm }

  TNoteForm = class(TForm)
  private
    FMemo: TMemo;
    FOkButton: TButton;
    procedure MemoKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
  protected
    procedure DoShow; override;
  public
    constructor CreateFor(AOwner: TComponent; const ATitle: string);
  end;

constructor TNoteForm.CreateFor(AOwner: TComponent; const ATitle: string);
var
  Lbl: TLabel;
  Row: TPanel;
  Cancel: TButton;
begin
  inherited CreateNew(AOwner);
  Caption := ATitle;
  BorderStyle := bsSizeable;
  Position := poMainFormCenter;
  Width := Scale96ToScreen(520);
  Height := Scale96ToScreen(360);
  Constraints.MinWidth := Scale96ToScreen(360);
  Constraints.MinHeight := Scale96ToScreen(240);

  Lbl := TLabel.Create(Self);
  Lbl.WordWrap := True;
  Lbl.Align := alTop;
  Lbl.Caption := rsNoteHint;
  Lbl.BorderSpacing.Around := Scale96ToScreen(Margin);
  Lbl.Parent := Self;

  Row := TPanel.Create(Self);
  Row.BevelOuter := bvNone;
  Row.AutoSize := True;
  Row.Align := alBottom;
  Row.BorderSpacing.Left := Scale96ToScreen(Margin);
  Row.BorderSpacing.Right := Scale96ToScreen(Margin);
  Row.BorderSpacing.Bottom := Scale96ToScreen(Margin);
  Row.Parent := Self;
  FOkButton := TButton.Create(Self);
  FOkButton.Caption := rsNoteSave;
  FOkButton.ModalResult := mrOK;
  FOkButton.Default := True;
  FOkButton.AutoSize := True;
  FOkButton.Constraints.MinWidth := Scale96ToScreen(84);
  FOkButton.Align := alRight;
  FOkButton.Parent := Row;
  Cancel := TButton.Create(Self);
  Cancel.Caption := rsNoteCancel;
  Cancel.ModalResult := mrCancel;
  Cancel.Cancel := True;
  Cancel.AutoSize := True;
  Cancel.Constraints.MinWidth := Scale96ToScreen(84);
  Cancel.Align := alRight;
  Cancel.Parent := Row;
  { The default button on the right on macOS, Cancel on the right
    elsewhere. }
  {$IFDEF DARWIN}
  Cancel.Left := 0;
  FOkButton.Left := 1000;
  {$ELSE}
  FOkButton.Left := 0;
  Cancel.Left := 1000;
  {$ENDIF}
  Cancel.BorderSpacing.Left := Scale96ToScreen(8);
  FOkButton.BorderSpacing.Left := Scale96ToScreen(8);

  FMemo := TMemo.Create(Self);
  FMemo.Align := alClient;
  FMemo.ScrollBars := ssAutoVertical;
  FMemo.WantReturns := True;
  FMemo.WantTabs := False;
  FMemo.BorderSpacing.Left := Scale96ToScreen(Margin);
  FMemo.BorderSpacing.Right := Scale96ToScreen(Margin);
  FMemo.BorderSpacing.Bottom := Scale96ToScreen(Margin);
  FMemo.OnKeyDown := @MemoKeyDown;
  FMemo.Parent := Self;
end;

procedure TNoteForm.DoShow;
begin
  inherited DoShow;
  ActiveControl := FMemo;
  FMemo.SelStart := Length(FMemo.Text);
end;

{ Return makes a line in the memo, so Cmd+Return (Ctrl+Return elsewhere)
  saves. }
procedure TNoteForm.MemoKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift * [ssCtrl, ssMeta] <> []) then
  begin
    Key := 0;
    ModalResult := mrOK;
  end;
end;

function EditCommitNote(const ACommitLabel: string; var AText: string): boolean;
var
  F: TNoteForm;
begin
  F := TNoteForm.CreateFor(Screen.ActiveForm, Format(rsNoteTitle, [ACommitLabel]));
  try
    F.FMemo.Text := AText;
    Result := F.ShowModal = mrOK;
    if Result then
      AText := Trim(AdjustLineBreaks(F.FMemo.Text, tlbsLF));
  finally
    F.Free;
  end;
end;

end.
