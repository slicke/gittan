unit gittan.settingsdlg;

{** The settings dialog (Gittan > Settings on macOS, Tools > Settings
  elsewhere): the editor font and its size, the syntax theme, and the
  commands Open in Editor and Open in Terminal run. The other view options
  are in the View menu, and the window remembers its own state.

  The font and the theme are previewed twice: in the main editor, where
  every change goes at once through the caller's preview handler, which puts
  back what it had when the dialog is cancelled; and in a small read-only
  editor in the dialog, with a sample in the language its buttons pick, so
  the colors show whatever the main editor holds and wherever the dialog
  sits. Both use the same lexers, which the theme colors in place. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, Spin, ATSynEdit, gittan.lexers;

type
  {** Shows AFont and the theme ATheme (an index into SyntaxThemes) in the
    editor while the dialog is open. }
  TSettingsPreview = procedure(AFont: TFont; ATheme: integer) of object;

{** Shows the dialog with AFont, ATheme, AEditor and ATerminal in it, its
  bottom right corner at ACorner (screen coordinates) so the code in the
  middle of the window stays in view. APreview gets every change of the
  font or theme. The sample editor takes its lexers from ALexers and its
  colors and zoom from ATemplate, the main editor. On OK the arguments are
  changed and the result is True; on Cancel they are left alone, and the
  caller undoes the preview. }
function EditSettings(AFont: TFont; var ATheme: integer;
  var AEditor, ATerminal: string; APreview: TSettingsPreview;
  ALexers: TGittanLexers; ATemplate: TATSynEdit; ACorner: TPoint): boolean;

implementation

uses
  ec_SyntAnal, ATSynEdit_Adapter_EControl, ATSynEdit_Globals, gittan.syntaxthemes;

resourcestring
  rsSettingsTitle = 'Settings';
  rsEditorFont = 'Editor font';
  rsChangeFont = '&Change...';
  rsSyntaxTheme = 'Syntax theme';
  rsPreview = 'Preview';
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
  {** The sample editor's height at 96 dpi: about a dozen lines. }
  SampleHeight = 210;

type
  TSample = record
    Caption, Lexer, Text: string;
  end;

const
  {** What the preview's buttons show, by the name of the lexer. }
  Samples: array[0..4] of TSample = (
    (Caption: 'Pascal'; Lexer: 'Pascal'; Text:
      '{ Counts the words in a line. }' + LineEnding +
      'function CountWords(const ALine: string): integer;' + LineEnding +
      'var' + LineEnding +
      '  i: integer;' + LineEnding +
      '  InWord: boolean;' + LineEnding +
      'begin' + LineEnding +
      '  Result := 0;' + LineEnding +
      '  InWord := False;' + LineEnding +
      '  for i := 1 to Length(ALine) do' + LineEnding +
      '    if ALine[i] in [#9, '' ''] then' + LineEnding +
      '      InWord := False' + LineEnding +
      '    else if not InWord then' + LineEnding +
      '    begin' + LineEnding +
      '      InWord := True;' + LineEnding +
      '      Inc(Result);' + LineEnding +
      '    end;' + LineEnding +
      'end;'),
    (Caption: 'C++'; Lexer: 'C++'; Text:
      '#include <string>' + LineEnding +
      '#include <vector>' + LineEnding +
      '' + LineEnding +
      '// Splits a line at each separator.' + LineEnding +
      'std::vector<std::string> split(const std::string& line, char sep = '','')' + LineEnding +
      '{' + LineEnding +
      '    std::vector<std::string> parts;' + LineEnding +
      '    std::size_t start = 0;' + LineEnding +
      '    for (std::size_t i = 0; i <= line.size(); ++i) {' + LineEnding +
      '        if (i == line.size() || line[i] == sep) {' + LineEnding +
      '            parts.push_back(line.substr(start, i - start));' + LineEnding +
      '            start = i + 1;' + LineEnding +
      '        }' + LineEnding +
      '    }' + LineEnding +
      '    return parts;' + LineEnding +
      '}'),
    (Caption: 'JavaScript'; Lexer: 'JavaScript'; Text:
      '// Fetches the open issues and counts them by label.' + LineEnding +
      'async function countLabels(repo) {' + LineEnding +
      '  const response = await fetch(`https://api.github.com/repos/${repo}/issues`);' + LineEnding +
      '  if (!response.ok) {' + LineEnding +
      '    throw new Error("Request failed: " + response.status);' + LineEnding +
      '  }' + LineEnding +
      '  const counts = {};' + LineEnding +
      '  for (const issue of await response.json()) {' + LineEnding +
      '    for (const label of issue.labels) {' + LineEnding +
      '      counts[label.name] = (counts[label.name] ?? 0) + 1;' + LineEnding +
      '    }' + LineEnding +
      '  }' + LineEnding +
      '  return counts;' + LineEnding +
      '}'),
    (Caption: 'TypeScript'; Lexer: 'TypeScript'; Text:
      'interface Change {' + LineEnding +
      '  path: string;' + LineEnding +
      '  added: number;' + LineEnding +
      '  removed: number;' + LineEnding +
      '}' + LineEnding +
      '' + LineEnding +
      '/** The changes with the most lines first. */' + LineEnding +
      'export function largest(changes: Change[], count = 5): Change[] {' + LineEnding +
      '  return [...changes]' + LineEnding +
      '    .sort((a, b) => b.added + b.removed - (a.added + a.removed))' + LineEnding +
      '    .slice(0, count);' + LineEnding +
      '}' + LineEnding +
      '' + LineEnding +
      'const total: number = largest([]).length;'),
    (Caption: 'Python'; Lexer: 'Python'; Text:
      'import subprocess' + LineEnding +
      'from pathlib import Path' + LineEnding +
      '' + LineEnding +
      '' + LineEnding +
      'class Repo:' + LineEnding +
      '    """A git repository on disk."""' + LineEnding +
      '' + LineEnding +
      '    def __init__(self, root: Path):' + LineEnding +
      '        self.root = root' + LineEnding +
      '' + LineEnding +
      '    def changed_files(self) -> list[str]:' + LineEnding +
      '        # Paths of the files that differ from HEAD.' + LineEnding +
      '        out = subprocess.run(["git", "diff", "--name-only"], cwd=self.root,' + LineEnding +
      '                             capture_output=True, text=True, check=True)' + LineEnding +
      '        return [line for line in out.stdout.splitlines() if line]')
  );

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
    FSampleEdit: TATSynEdit;
    FAdapter: TATAdapterEControl;
    FLexers: TGittanLexers;
    FTemplate: TATSynEdit;
    FSampleButtons: array[0..High(Samples)] of TToggleBox;
    FSample: integer;
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
    procedure SampleClick(Sender: TObject);
    procedure ShowSample;
    procedure StyleSample;
    procedure SetLexer(ALexer: TecSyntAnalyzer);
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
  Constraints.MinWidth := Scale96ToScreen(520);
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

  { The language buttons, left to right (alLeft orders by Left), then the
    sample. }
  AddLabel(rsPreview, 16);
  Row := AddRow(4);
  for i := 0 to High(Samples) do
  begin
    FSampleButtons[i] := TToggleBox.Create(Self);
    FSampleButtons[i].Caption := Samples[i].Caption;
    FSampleButtons[i].Tag := i;
    FSampleButtons[i].AutoSize := True;
    FSampleButtons[i].Align := alLeft;
    FSampleButtons[i].Left := i * 1000;
    FSampleButtons[i].BorderSpacing.Right := Scale96ToScreen(4);
    FSampleButtons[i].OnClick := @SampleClick;
    FSampleButtons[i].Parent := Row;
  end;
  FSampleEdit := TATSynEdit.Create(Self);
  FSampleEdit.Height := Scale96ToScreen(SampleHeight);
  FSampleEdit.ModeReadOnly := True;
  FSampleEdit.OptCaretVirtual := False;
  FSampleEdit.OptRulerVisible := False;
  FSampleEdit.OptMinimapVisible := False;
  FSampleEdit.OptMicromapVisible := False;
  FSampleEdit.OptUnprintedVisible := False;
  FSampleEdit.OptGutterShowFoldAlways := False;
  FSampleEdit.OptNumbersStyle := TATEditorNumbersStyle.All;
  FSampleEdit.OptShowCurLine := False;
  i := FSampleEdit.Gutter.FindIndexByTag(ATEditorOptions.GutterTagFolding);
  if i >= 0 then
    FSampleEdit.Gutter[i].Visible := False;
  i := FSampleEdit.Gutter.FindIndexByTag(ATEditorOptions.GutterTagLineStates);
  if i >= 0 then
    FSampleEdit.Gutter[i].Visible := False;
  FSampleEdit.TabStop := False;
  Place(FSampleEdit, 6);
  FAdapter := TATAdapterEControl.Create(Self);
  FAdapter.AddEditor(FSampleEdit);

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
  { The lexer belongs to the main form's list. }
  FAdapter.Lexer := nil;
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
  if FLoading then
    Exit;
  if Assigned(FPreview) then
    FPreview(FFont, FThemeBox.ItemIndex);
  StyleSample;
end;

{ The sample in the main editor's colors and zoom and the chosen font,
  highlighted again, since the theme may have recolored the lexer. }
procedure TSettingsForm.StyleSample;
var
  Lexer: TecSyntAnalyzer;
begin
  if FTemplate <> nil then
  begin
    FSampleEdit.Colors := FTemplate.Colors;
    FSampleEdit.OptScaleFont := FTemplate.OptScaleFont;
  end;
  FSampleEdit.Font.Assign(FFont);
  Lexer := FAdapter.Lexer;
  FAdapter.Lexer := nil;
  SetLexer(Lexer);
end;

{ As TForm1.SetEditorLexer: a change event from line 0 starts the parse. }
procedure TSettingsForm.SetLexer(ALexer: TecSyntAnalyzer);
begin
  FAdapter.Lexer := ALexer;
  if ALexer <> nil then
    FSampleEdit.DoEventChange(0);
  FSampleEdit.Update(True);
end;

{ Shows the chosen sample, its button down and the others up. The text is
  set as TForm1.ShowText sets it, with the wrap info rebuilt. }
procedure TSettingsForm.ShowSample;
var
  i: integer;
begin
  FLoading := True;
  try
    for i := 0 to High(FSampleButtons) do
      FSampleButtons[i].Checked := i = FSample;
  finally
    FLoading := False;
  end;
  FAdapter.Lexer := nil;
  FSampleEdit.ModeReadOnly := False;
  FSampleEdit.Text := UTF8Decode(Samples[FSample].Text);
  FSampleEdit.WrapInfo.Clear;
  FSampleEdit.Strings.WrapStructInvalidate;
  FSampleEdit.ModeReadOnly := True;
  if FLexers <> nil then
    FAdapter.Lexer := FLexers.ByName(Samples[FSample].Lexer);
  StyleSample;
end;

procedure TSettingsForm.SampleClick(Sender: TObject);
begin
  if FLoading then
    Exit;
  FSample := TToggleBox(Sender).Tag;
  ShowSample;
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
  ALexers: TGittanLexers; ATemplate: TATSynEdit; ACorner: TPoint): boolean;
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
    F.FLexers := ALexers;
    F.FTemplate := ATemplate;
    F.ShowSample;
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
