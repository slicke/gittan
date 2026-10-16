unit gittan.settingsdlg;

{** The settings dialog (Gittan > Settings on macOS, Tools > Settings
  elsewhere): the editor font and its size, the syntax theme, and the
  commands Open in Editor and Open in Terminal run. The other view options
  are in the View menu, and the window remembers its own state.

  The font and the theme are previewed in the editor itself: every change
  goes to OnPreview at once, and the caller puts back what it had when the
  dialog is cancelled. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, Spin;

type
  {** Shows AFont and the theme ATheme (an index into SyntaxThemes) in the
    editor while the dialog is open. }
  TSettingsPreview = procedure(AFont: TFont; ATheme: integer) of object;

{** Shows the dialog with AFont, ATheme, AEditor and ATerminal in it, its
  bottom right corner at ACorner (screen coordinates) so the code in the
  middle of the window stays in view. APreview gets every change of the
  font or theme. On OK the arguments are changed and the result is True; on
  Cancel they are left alone, and the caller undoes the preview. }
function EditSettings(AFont: TFont; var ATheme: integer;
  var AEditor, ATerminal: string; APreview: TSettingsPreview;
  ACorner: TPoint): boolean;

implementation

uses
  gittan.syntaxthemes;

resourcestring
  rsSettingsTitle = 'Settings';
  rsEditorFont = 'Editor font';
  rsChangeFont = '&Change...';
  rsSyntaxTheme = 'Syntax theme';
  rsEditorCommand = 'Open in Editor command';
  rsEditorDefault = 'The default application for the file';
  rsEditorNote = 'The file''s path is appended.';
  rsTerminalCommand = 'Open in Terminal command';
  {$IFDEF DARWIN}
  rsTerminalDefault = 'Terminal';
  {$ELSE}
  {$IFDEF WINDOWS}
  rsTerminalDefault = 'Windows Terminal, else cmd.exe';
  {$ELSE}
  rsTerminalDefault = 'The first terminal on PATH';
  {$ENDIF}
  {$ENDIF}
  rsTerminalNote = 'The repository''s folder is appended.';
  rsOK = 'OK';
  rsCancel = 'Cancel';

const
  MinFontSize = 6;
  MaxFontSize = 72;
  {** What the size field shows for a font of the default size (0). }
  DefaultFontSize = 13;

type

  { TSettingsForm }

  TSettingsForm = class(TForm)
  private
    FFont: TFont;
    FFontLabel: TLabel;
    FSizeEdit: TSpinEdit;
    FThemeBox: TComboBox;
    FEditorEdit, FTerminalEdit: TEdit;
    FPreview: TSettingsPreview;
    FNextTop: integer;
    FLoading: boolean;
    FCorner: TPoint;
    procedure Place(AControl: TControl; ASpaceAbove: integer);
    function AddRow(ASpaceAbove: integer): TPanel;
    function AddLabel(const ACaption: string; ASpaceAbove: integer): TLabel;
    function AddEdit(const AHint: string): TEdit;
    function AddButton(ARow: TPanel; const ACaption: string;
      AResult: TModalResult): TButton;
    procedure ShowFont;
    procedure Preview;
    procedure ChangeFontClick(Sender: TObject);
    procedure SizeChange(Sender: TObject);
    procedure ThemeChange(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

constructor TSettingsForm.Create(AOwner: TComponent);
var
  Row: TPanel;
  Btn, OK, Cancel: TButton;
  i: integer;
begin
  inherited CreateNew(AOwner);
  FFont := TFont.Create;
  Caption := rsSettingsTitle;
  BorderStyle := bsDialog;
  Position := poDesigned;
  AutoSize := True;
  Constraints.MinWidth := Scale96ToScreen(460);
  ChildSizing.LeftRightSpacing := Scale96ToScreen(16);
  ChildSizing.TopBottomSpacing := Scale96ToScreen(12);

  { The name, then the size and Change... on the right, which alRight
    orders by Left. }
  AddLabel(rsEditorFont, 0);
  Row := AddRow(4);
  Btn := TButton.Create(Self);
  Btn.Caption := rsChangeFont;
  Btn.AutoSize := True;
  Btn.Align := alRight;
  Btn.Left := 1000;
  Btn.BorderSpacing.Left := Scale96ToScreen(8);
  Btn.OnClick := @ChangeFontClick;
  Btn.Parent := Row;
  FSizeEdit := TSpinEdit.Create(Self);
  FSizeEdit.MinValue := MinFontSize;
  FSizeEdit.MaxValue := MaxFontSize;
  FSizeEdit.Width := Scale96ToScreen(64);
  FSizeEdit.Align := alRight;
  FSizeEdit.Left := 0;
  FSizeEdit.OnChange := @SizeChange;
  FSizeEdit.Parent := Row;
  FFontLabel := TLabel.Create(Self);
  FFontLabel.Align := alClient;
  FFontLabel.Layout := tlCenter;
  FFontLabel.Parent := Row;

  AddLabel(rsSyntaxTheme, 16);
  FThemeBox := TComboBox.Create(Self);
  FThemeBox.Style := csDropDownList;
  for i := 0 to High(SyntaxThemes) do
    FThemeBox.Items.Add(SyntaxThemes[i].Name);
  FThemeBox.OnChange := @ThemeChange;
  Place(FThemeBox, 4);

  AddLabel(rsEditorCommand, 16);
  FEditorEdit := AddEdit(rsEditorDefault);
  AddLabel(rsEditorNote, 4).Font.Color := clGrayText;

  AddLabel(rsTerminalCommand, 16);
  FTerminalEdit := AddEdit(rsTerminalDefault);
  AddLabel(rsTerminalNote, 4).Font.Color := clGrayText;

  { OK on the right on macOS, Cancel on the right elsewhere. }
  Row := AddRow(20);
  OK := AddButton(Row, rsOK, mrOK);
  OK.Default := True;
  Cancel := AddButton(Row, rsCancel, mrCancel);
  Cancel.Cancel := True;
  {$IFDEF DARWIN}
  Cancel.Left := 0;
  OK.Left := 1000;
  {$ELSE}
  OK.Left := 0;
  Cancel.Left := 1000;
  {$ENDIF}
  Cancel.BorderSpacing.Left := Scale96ToScreen(8);
  OK.BorderSpacing.Left := Scale96ToScreen(8);
end;

destructor TSettingsForm.Destroy;
begin
  FFont.Free;
  inherited Destroy;
end;

{ The form has its size once it has laid itself out, just before it shows. }
procedure TSettingsForm.DoShow;
begin
  inherited DoShow;
  SetBounds(FCorner.X - Width, FCorner.Y - Height, Width, Height);
  MakeFullyVisible;
end;

{ Puts AControl under the ones placed before it: alTop stacks controls by
  their Top. }
procedure TSettingsForm.Place(AControl: TControl; ASpaceAbove: integer);
begin
  AControl.Align := alTop;
  AControl.BorderSpacing.Top := Scale96ToScreen(ASpaceAbove);
  Inc(FNextTop, 1000);
  AControl.Top := FNextTop;
  AControl.Parent := Self;
end;

function TSettingsForm.AddRow(ASpaceAbove: integer): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.BevelOuter := bvNone;
  Result.AutoSize := True;
  Place(Result, ASpaceAbove);
end;

function TSettingsForm.AddLabel(const ACaption: string; ASpaceAbove: integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Caption := ACaption;
  Place(Result, ASpaceAbove);
end;

function TSettingsForm.AddEdit(const AHint: string): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.TextHint := AHint;
  Place(Result, 4);
end;

function TSettingsForm.AddButton(ARow: TPanel; const ACaption: string;
  AResult: TModalResult): TButton;
begin
  Result := TButton.Create(Self);
  Result.Caption := ACaption;
  Result.ModalResult := AResult;
  Result.AutoSize := True;
  Result.Constraints.MinWidth := Scale96ToScreen(84);
  Result.Align := alRight;
  Result.Parent := ARow;
end;

{ The name in the label and the size in its field, without previewing. }
procedure TSettingsForm.ShowFont;
begin
  FLoading := True;
  try
    FFontLabel.Caption := FFont.Name;
    if FFont.Size > 0 then
      FSizeEdit.Value := FFont.Size
    else
      FSizeEdit.Value := DefaultFontSize;
  finally
    FLoading := False;
  end;
end;

procedure TSettingsForm.Preview;
begin
  if not FLoading and Assigned(FPreview) then
    FPreview(FFont, FThemeBox.ItemIndex);
end;

procedure TSettingsForm.ChangeFontClick(Sender: TObject);
var
  Dlg: TFontDialog;
begin
  Dlg := TFontDialog.Create(nil);
  try
    Dlg.Font.Assign(FFont);
    if Dlg.Execute then
    begin
      FFont.Assign(Dlg.Font);
      ShowFont;
      Preview;
    end;
  finally
    Dlg.Free;
  end;
end;

{ A size typed out of range is left until it is in range again. }
procedure TSettingsForm.SizeChange(Sender: TObject);
begin
  if FLoading or (FSizeEdit.Value < MinFontSize) or (FSizeEdit.Value > MaxFontSize) or
    (FSizeEdit.Value = FFont.Size) then
    Exit;
  FFont.Size := FSizeEdit.Value;
  Preview;
end;

procedure TSettingsForm.ThemeChange(Sender: TObject);
begin
  Preview;
end;

function EditSettings(AFont: TFont; var ATheme: integer;
  var AEditor, ATerminal: string; APreview: TSettingsPreview;
  ACorner: TPoint): boolean;
var
  F: TSettingsForm;
begin
  F := TSettingsForm.Create(Screen.ActiveForm);
  try
    F.FFont.Assign(AFont);
    F.ShowFont;
    F.FLoading := True;
    F.FThemeBox.ItemIndex := ATheme;
    F.FLoading := False;
    F.FEditorEdit.Text := AEditor;
    F.FTerminalEdit.Text := ATerminal;
    F.FPreview := APreview;
    F.FCorner := ACorner;
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      AFont.Assign(F.FFont);
      ATheme := F.FThemeBox.ItemIndex;
      AEditor := Trim(F.FEditorEdit.Text);
      ATerminal := Trim(F.FTerminalEdit.Text);
    end;
  finally
    F.Free;
  end;
end;

end.
