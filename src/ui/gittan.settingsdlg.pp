unit gittan.settingsdlg;

{** The settings dialog (Gittan > Settings on macOS, Tools > Settings
  elsewhere), in two pages picked in a sidebar of the main window's kind,
  as the system's settings have: Editor, the editor font and its size,
  the width of a tab and the syntax theme, with a sample; Tools, the
  commands Open in Editor and Open in Terminal run, and the git and gh to
  run in place of those found on PATH; and AI, whether the AI features
  show, the agent they run, and its command and model (see gittan.ai). The other view options are in the
  View menu, and the window remembers its own state.

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
  ExtCtrls, Spin, ATSynEdit, gittan.lexers, gittan.sidenav, gittan.ai;

type
  {** Shows AFont, the theme ATheme (an index into SyntaxThemes) and a tab
    ATabSize characters wide in the editor while the dialog is open. }
  TSettingsPreview = procedure(AFont: TFont; ATheme, ATabSize: integer) of object;

  {** What the dialog edits besides the font. }
  TSettingsValues = record
    {** An index into SyntaxThemes. }
    Theme: integer;
    TabSize: integer;
    EditorCommand, TerminalCommand: string;
    {** Paths of git and gh; empty for the ones found on PATH. }
    GitPath, GhPath: string;
    {** Whether the AI features show, the agent they run, and each
      agent's command (empty for the one found) and model (empty for its
      own choice). }
    AIEnabled: boolean;
    Agent: TGittanAgent;
    AgentPaths, AgentModels: array[TGittanAgent] of string;
  end;

{** Shows the dialog with AFont and AValues in it, its bottom right corner
  at ACorner (screen coordinates) so the code in the middle of the window
  stays in view. APreview gets every change of the font, the theme or the
  tab width. The sample editor takes its lexers from ALexers and its
  colors and zoom from ATemplate, the main editor. On OK the arguments are
  changed and the result is True; on Cancel they are left alone, and the
  caller undoes the preview. }
function EditSettings(AFont: TFont; var AValues: TSettingsValues;
  APreview: TSettingsPreview; ALexers: TGittanLexers; ATemplate: TATSynEdit;
  ACorner: TPoint): boolean;

implementation

uses
  Math, ec_SyntAnal, ATSynEdit_Adapter_EControl, ATSynEdit_Globals,
  gittan.syntaxthemes, gittan.git, gittan.theme;

resourcestring
  rsSettingsTitle = 'Settings';
  rsEditorPage = 'Editor';
  rsToolsPage = 'Tools';
  rsAIPage = 'AI';
  rsAIEnabled = 'Turn on the AI features';
  rsAINote = 'They run the agent picked here in the repository, with your own ' +
    'login, to write a commit message from the ticked files. The changes are sent ' +
    'to its provider: Anthropic for Claude Code, GitHub for Copilot. Off until ' +
    'turned on here.';
  rsAgent = 'Agent';
  rsAgentPath = '%s, %s''s command line tool';
  rsAgentDefault = 'The %s on PATH';
  rsAgentNotFound = 'Not found on PATH; install %s to use the AI features.';
  rsAgentModel = 'Model';
  rsAgentModelDefault = '%s''s default';
  rsClaudeModelNote = 'An alias such as haiku or sonnet, or a model''s full name.';
  rsCopilotModelNote = 'A model''s name, or auto to let Copilot pick.';
  rsEditorFont = 'Editor font';
  rsChangeFont = '&Change...';
  rsTabWidth = 'Tab width';
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
  rsGitPath = 'git';
  rsGitDefault = 'The git on PATH';
  rsGhPath = 'gh, GitHub''s command line tool';
  rsGhDefault = 'The gh on PATH';
  rsToolFound = 'Found: %s';
  rsToolNotFound = 'Not found on PATH.';
  rsGhNotFound = 'Not found on PATH; the GitHub features are off.';
  rsToolTyped = 'Run in place of the one on PATH.';
  rsToolMissing = 'There is no such file.';
  rsOK = 'OK';
  rsCancel = 'Cancel';

const
  MinFontSize = 6;
  MaxFontSize = 72;
  MinTabSize = 1;
  MaxTabSize = 16;
  {** What the size field shows for a font of the default size (0). }
  DefaultFontSize = 13;
  {** The sample editor's height at 96 dpi: about a dozen lines. }
  SampleHeight = 210;
  {** The sidebar's width at 96 dpi, and the space around the content. }
  NavWidth = 150;
  ContentMargin = 16;
  {** The content's least width at 96 dpi: the sample's lines. }
  ContentWidth = 500;

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
    FSizeEdit, FTabEdit: TSpinEdit;
    FThemeBox: TComboBox;
    FEditorEdit, FTerminalEdit, FGitEdit, FGhEdit, FAgentEdit, FModelEdit: TEdit;
    FGitNote, FGhNote, FAgentLabel, FAgentNote, FModelNote: TLabel;
    FAIBox: TCheckBox;
    { The agent picked, and each agent's command and model as edited:
      the fields show the picked one's (ShowAgent). }
    FAgentBox: TComboBox;
    FAgent: TGittanAgent;
    FAgentPaths, FAgentModels: array[TGittanAgent] of string;
    { The sidebar with a row per page, and the content beside it: the
      box of each page, which sizes itself, one shown at a time, and the
      buttons under them. FBox is the one Place puts controls in. }
    FNavPanel, FContent: TPanel;
    FNav: TGittanSideNav;
    FEditorBox, FToolsBox, FAIPage: TPanel;
    FBox: TWinControl;
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
    function AddPage(const ACaption: string; AIcon: TGittanNavIcon): TPanel;
    procedure NavPick(Sender: TObject; AIndex: integer);
    procedure ShowPage(AIndex: integer);
    procedure ApplyTheme;
    function AddTool(const ACaption, AHint: string; out ANote: TLabel): TEdit;
    procedure ShowFont;
    procedure Preview;
    procedure ChangeFontClick(Sender: TObject);
    procedure SizeChange(Sender: TObject);
    procedure TabChange(Sender: TObject);
    procedure ThemeChange(Sender: TObject);
    procedure ToolChange(Sender: TObject);
    procedure AIChange(Sender: TObject);
    procedure AgentChange(Sender: TObject);
    procedure ShowAgent;
    procedure ShowTool(AEdit: TEdit; ANote: TLabel; const AName, ANotFound: string);
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
  Lbl: TLabel;
  Btn, OK, Cancel: TButton;
  i: integer;
  A: TGittanAgent;
begin
  inherited CreateNew(AOwner);
  FFont := TFont.Create;
  Caption := rsSettingsTitle;
  BorderStyle := bsDialog;
  Position := poDesigned;
  AutoSize := True;

  { The sidebar down the left, as high as the form, and the content
    beside it, which sizes itself and so the form (alLeft for both, so
    the form takes their widths; the sidebar's shade is set in
    ApplyTheme). }
  FNavPanel := TPanel.Create(Self);
  FNavPanel.BevelOuter := bvNone;
  FNavPanel.Align := alLeft;
  FNavPanel.Left := 0;
  FNavPanel.Width := Scale96ToScreen(NavWidth);
  FNavPanel.Parent := Self;
  FNav := TGittanSideNav.Create(Self);
  FNav.Align := alTop;
  FNav.BorderSpacing.Top := Scale96ToScreen(8);
  FNav.OnPick := @NavPick;
  FNav.Parent := FNavPanel;
  FContent := TPanel.Create(Self);
  FContent.BevelOuter := bvNone;
  FContent.AutoSize := True;
  FContent.Align := alLeft;
  FContent.Left := 1000;
  FContent.Constraints.MinWidth := Scale96ToScreen(ContentWidth);
  FContent.ChildSizing.LeftRightSpacing := Scale96ToScreen(ContentMargin);
  FContent.ChildSizing.TopBottomSpacing := Scale96ToScreen(ContentMargin);
  FContent.Parent := Self;
  FEditorBox := AddPage(rsEditorPage, niEditor);
  FToolsBox := AddPage(rsToolsPage, niTools);
  FAIPage := AddPage(rsAIPage, niAI);

  { The Editor page: the font's name, then the size and Change... on the
    right, which alRight orders by Left. }
  FBox := FEditorBox;
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

  { The tab width beside its label. }
  Row := AddRow(12);
  Lbl := TLabel.Create(Self);
  Lbl.Caption := rsTabWidth;
  Lbl.Align := alLeft;
  Lbl.Layout := tlCenter;
  Lbl.Parent := Row;
  FTabEdit := TSpinEdit.Create(Self);
  FTabEdit.MinValue := MinTabSize;
  FTabEdit.MaxValue := MaxTabSize;
  FTabEdit.Width := Scale96ToScreen(64);
  FTabEdit.Align := alLeft;
  FTabEdit.Left := 1000;
  FTabEdit.BorderSpacing.Left := Scale96ToScreen(8);
  FTabEdit.OnChange := @TabChange;
  FTabEdit.Parent := Row;

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

  { The Tools page: each command with a note on what an empty field does,
    each tool with a note on what will run (ShowTool). }
  FBox := FToolsBox;
  AddLabel(rsEditorCommand, 0);
  FEditorEdit := AddEdit(rsEditorDefault);
  AddLabel(rsEditorNote, 4).Font.Color := clGrayText;

  AddLabel(rsTerminalCommand, 16);
  FTerminalEdit := AddEdit(rsTerminalDefault);
  AddLabel(rsTerminalNote, 4).Font.Color := clGrayText;

  FGitEdit := AddTool(rsGitPath, rsGitDefault, FGitNote);
  FGhEdit := AddTool(rsGhPath, rsGhDefault, FGhNote);

  { The AI page: the switch and what it means, then the agent, its
    command and its model, which follow the switch; the labels name the
    agent picked (ShowAgent). }
  FBox := FAIPage;
  FAIBox := TCheckBox.Create(Self);
  FAIBox.Caption := rsAIEnabled;
  FAIBox.OnChange := @AIChange;
  Place(FAIBox, 0);
  Lbl := AddLabel(rsAINote, 4);
  Lbl.Font.Color := clGrayText;
  Lbl.WordWrap := True;
  AddLabel(rsAgent, 16);
  FAgentBox := TComboBox.Create(Self);
  FAgentBox.Style := csDropDownList;
  for A in TGittanAgent do
    FAgentBox.Items.Add(AgentNames[A]);
  FAgentBox.OnChange := @AgentChange;
  Place(FAgentBox, 4);
  FAgentLabel := AddLabel('', 16);
  FAgentEdit := AddEdit('');
  FAgentEdit.OnChange := @ToolChange;
  FAgentNote := AddLabel('', 4);
  FAgentNote.Font.Color := clGrayText;
  FAgentNote.WordWrap := True;
  AddLabel(rsAgentModel, 16);
  FModelEdit := AddEdit('');
  FModelNote := AddLabel('', 4);
  FModelNote.Font.Color := clGrayText;

  { OK on the right on macOS, Cancel on the right elsewhere. }
  FBox := FContent;
  Row := AddRow(16);
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

{ The content has its size once the form has laid itself out, just before
  it shows: both pages are held at the height of the taller (the one not
  shown has its preferred height, not a laid out one), so the form keeps
  its size when the page changes, and goes to its corner. }
procedure TSettingsForm.DoShow;
var
  W, H, Tallest: integer;
begin
  inherited DoShow;
  FToolsBox.GetPreferredSize(W, H, False, True);
  Tallest := Max(FEditorBox.Height, H);
  FAIPage.GetPreferredSize(W, H, False, True);
  Tallest := Max(Tallest, H);
  FEditorBox.Constraints.MinHeight := Tallest;
  FToolsBox.Constraints.MinHeight := Tallest;
  FAIPage.Constraints.MinHeight := Tallest;
  SetBounds(FCorner.X - Width, FCorner.Y - Height, Width, Height);
  MakeFullyVisible;
end;

{ Puts AControl under the ones placed before it in FBox: alTop stacks
  controls by their Top. }
procedure TSettingsForm.Place(AControl: TControl; ASpaceAbove: integer);
begin
  AControl.Align := alTop;
  AControl.BorderSpacing.Top := Scale96ToScreen(ASpaceAbove);
  Inc(FNextTop, 1000);
  AControl.Top := FNextTop;
  AControl.Parent := FBox;
end;

{ A row in the sidebar and a box in the content for a page, which sizes
  itself to what Place puts in it; the first page is the one shown. }
function TSettingsForm.AddPage(const ACaption: string; AIcon: TGittanNavIcon): TPanel;
var
  Index: integer;
begin
  Index := FNav.AddRow(ACaption, AIcon);
  FBox := FContent;
  Result := TPanel.Create(Self);
  Result.BevelOuter := bvNone;
  Result.AutoSize := True;
  Result.Visible := Index = 0;
  Place(Result, 0);
  if Index = 0 then
    FNav.Selected := 0;
end;

procedure TSettingsForm.NavPick(Sender: TObject; AIndex: integer);
begin
  ShowPage(AIndex);
end;

{ Shows the page's box over the buttons: a box that was hidden kept the
  Top it was placed with, past the buttons' laid out one, so it goes to
  0 first (alTop orders by Top). The form is laid out once, at the end. }
procedure TSettingsForm.ShowPage(AIndex: integer);
var
  Box: TPanel;
begin
  DisableAutoSizing;
  try
    FEditorBox.Visible := False;
    FToolsBox.Visible := False;
    FAIPage.Visible := False;
    case AIndex of
      0: Box := FEditorBox;
      1: Box := FToolsBox;
      else
        Box := FAIPage;
    end;
    Box.Top := 0;
    Box.Visible := True;
  finally
    EnableAutoSizing;
  end;
  FNav.Selected := AIndex;
end;

{ The sidebar in the main window's shade, its rows in the editor's text
  color in dark mode. }
procedure TSettingsForm.ApplyTheme;
var
  Dark: boolean;
  TextColor: TColor;
begin
  Dark := IsDarkMode;
  FNavPanel.Color := SidebarShade(Dark);
  if FTemplate <> nil then
    TextColor := FTemplate.Colors.TextFont
  else
    TextColor := clWindowText;
  ThemeSideNav(FNav, Dark, TextColor);
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

{ A label, the field (OnChange refreshes the note) and the note, which
  wraps when a path is long. }
function TSettingsForm.AddTool(const ACaption, AHint: string; out ANote: TLabel): TEdit;
begin
  AddLabel(ACaption, 16);
  Result := AddEdit(AHint);
  Result.OnChange := @ToolChange;
  ANote := AddLabel('', 4);
  ANote.Font.Color := clGrayText;
  ANote.WordWrap := True;
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
    FPreview(FFont, FThemeBox.ItemIndex, FTabEdit.Value);
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
  FSampleEdit.OptTabSize := FTabEdit.Value;
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

{ A width typed out of range is left until it is in range again. }
procedure TSettingsForm.TabChange(Sender: TObject);
begin
  if (FTabEdit.Value < MinTabSize) or (FTabEdit.Value > MaxTabSize) then
    Exit;
  Preview;
end;

procedure TSettingsForm.ThemeChange(Sender: TObject);
begin
  Preview;
end;

procedure TSettingsForm.ToolChange(Sender: TObject);
begin
  if Sender = FGitEdit then
    ShowTool(FGitEdit, FGitNote, 'git', rsToolNotFound)
  else if Sender = FGhEdit then
    ShowTool(FGhEdit, FGhNote, 'gh', rsGhNotFound)
  else
    ShowTool(FAgentEdit, FAgentNote, AgentCommands[FAgent],
      Format(rsAgentNotFound, [AgentNames[FAgent]]));
end;

{ The agent and its fields matter only with the features on. }
procedure TSettingsForm.AIChange(Sender: TObject);
begin
  FAgentBox.Enabled := FAIBox.Checked;
  FAgentEdit.Enabled := FAIBox.Checked;
  FModelEdit.Enabled := FAIBox.Checked;
end;

{ What was typed for the agent left is kept, and the fields show the
  one picked. }
procedure TSettingsForm.AgentChange(Sender: TObject);
begin
  FAgentPaths[FAgent] := Trim(FAgentEdit.Text);
  FAgentModels[FAgent] := Trim(FModelEdit.Text);
  FAgent := TGittanAgent(Max(0, FAgentBox.ItemIndex));
  ShowAgent;
end;

{ The picked agent's command and model in the fields, and the labels,
  hints and notes that name it. }
procedure TSettingsForm.ShowAgent;
begin
  FAgentBox.ItemIndex := Ord(FAgent);
  FAgentLabel.Caption := Format(rsAgentPath, [AgentCommands[FAgent], AgentNames[FAgent]]);
  FAgentEdit.TextHint := Format(rsAgentDefault, [AgentCommands[FAgent]]);
  FAgentEdit.Text := FAgentPaths[FAgent];
  FModelEdit.TextHint := Format(rsAgentModelDefault, [AgentNames[FAgent]]);
  FModelEdit.Text := FAgentModels[FAgent];
  if FAgent = gaCopilot then
    FModelNote.Caption := rsCopilotModelNote
  else
    FModelNote.Caption := rsClaudeModelNote;
  ToolChange(FAgentEdit);
end;

{ The note under AEdit for the tool AName: with the field empty, where
  the tool is found on PATH or ANotFound; with a path typed, whether that
  file exists. }
procedure TSettingsForm.ShowTool(AEdit: TEdit; ANote: TLabel;
  const AName, ANotFound: string);
var
  Path: string;
begin
  Path := Trim(AEdit.Text);
  if Path = '' then
  begin
    { claude may be where its own installer put it, off PATH. }
    if AEdit = FAgentEdit then
      Path := FindAgent(FAgent, '')
    else
      Path := FindTool(AName);
    if Path <> '' then
      ANote.Caption := Format(rsToolFound, [Path])
    else
      ANote.Caption := ANotFound;
  end
  else if FileExists(Path) then
    ANote.Caption := rsToolTyped
  else
    ANote.Caption := rsToolMissing;
end;

function EditSettings(AFont: TFont; var AValues: TSettingsValues;
  APreview: TSettingsPreview; ALexers: TGittanLexers; ATemplate: TATSynEdit;
  ACorner: TPoint): boolean;
var
  F: TSettingsForm;
begin
  F := TSettingsForm.Create(Screen.ActiveForm);
  try
    F.FFont.Assign(AFont);
    F.ShowFont;
    F.FLoading := True;
    F.FThemeBox.ItemIndex := AValues.Theme;
    F.FTabEdit.Value := AValues.TabSize;
    F.FLoading := False;
    F.FEditorEdit.Text := AValues.EditorCommand;
    F.FTerminalEdit.Text := AValues.TerminalCommand;
    F.FGitEdit.Text := AValues.GitPath;
    F.FGhEdit.Text := AValues.GhPath;
    F.ToolChange(F.FGitEdit);
    F.ToolChange(F.FGhEdit);
    F.FAIBox.Checked := AValues.AIEnabled;
    F.FAgent := AValues.Agent;
    F.FAgentPaths := AValues.AgentPaths;
    F.FAgentModels := AValues.AgentModels;
    F.ShowAgent;
    F.AIChange(nil);
    F.FPreview := APreview;
    F.FLexers := ALexers;
    F.FTemplate := ATemplate;
    F.ApplyTheme;
    F.ShowSample;
    F.FCorner := ACorner;
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      AFont.Assign(F.FFont);
      AValues.Theme := F.FThemeBox.ItemIndex;
      AValues.TabSize := F.FTabEdit.Value;
      AValues.EditorCommand := Trim(F.FEditorEdit.Text);
      AValues.TerminalCommand := Trim(F.FTerminalEdit.Text);
      AValues.GitPath := Trim(F.FGitEdit.Text);
      AValues.GhPath := Trim(F.FGhEdit.Text);
      AValues.AIEnabled := F.FAIBox.Checked;
      { The fields hold the picked agent's; the other's are as kept. }
      F.AgentChange(nil);
      AValues.Agent := F.FAgent;
      AValues.AgentPaths := F.FAgentPaths;
      AValues.AgentModels := F.FAgentModels;
    end;
  finally
    F.Free;
  end;
end;

end.
