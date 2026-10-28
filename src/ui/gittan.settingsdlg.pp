unit gittan.settingsdlg;

{** The settings dialog (Gittan > Settings on macOS, Tools > Settings
  elsewhere), in pages picked in a sidebar of the main window's kind,
  as the system's settings have: Editor, the editor font and its size,
  the width of a tab and the syntax theme, with a sample; Tools, the
  commands Open in Editor and Open in Terminal run, and the git to run in
  place of the one found on PATH; Hosting, a block per service that hosts
  repositories (GitHub alone so far) with whether its features are on,
  the command line tool they run and, for GitHub, whether its page looks
  for clones beside the recent repositories; AI, whether the AI features show, the
  agent they run, and its command and model, or for the OpenAI-compatible API its
  server, key and model (see gittan.ai);
  and About (also Gittan > About Gittan on macOS, Tools > About Gittan
  elsewhere), the build, a check for a newer one, what Gittan runs on
  and with, for a bug report, and the licenses. The other view options
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
  ExtCtrls, Spin, BGRABitmap, BGRABitmapTypes, ATSynEdit, gittan.lexers, gittan.sidenav, gittan.ai, gittan.update,
  gittan.forge;

type
  {** The pages, in the sidebar's order. }
  TSettingsPage = (pgEditor, pgTools, pgHosting, pgAI, pgAbout);

  {** Shows AFont, the theme ATheme (an index into SyntaxThemes) and a tab
    ATabSize characters wide in the editor while the dialog is open. }
  TSettingsPreview = procedure(AFont: TFont; ATheme, ATabSize: integer) of object;

  {** What the dialog edits besides the font. }
  TSettingsValues = record
    {** An index into SyntaxThemes. }
    Theme: integer;
    TabSize: integer;
    EditorCommand, TerminalCommand: string;
    {** The path of git; empty for the one found on PATH. }
    GitPath: string;
    {** Whether the hosting features are on, for every forge at once. }
    HostingEnabled: boolean;
    {** Each registered forge's (gittan.forge's RegisteredForges, in
      their order) tool's path, empty for the one found on PATH. }
    ForgePaths: TStringArray;
    {** On OK, each registered forge's accounts (TGittanForge.Accounts as
      the dialog read them, in the forges' order) with the one picked
      for each host marked active; the caller switches where that is
      not the tool's. }
    Accounts: TGittanForgeAccountsList;
    {** Whether the open repository is fetched in the background, and
      how many minutes apart. }
    AutoFetch: boolean;
    AutoFetchMinutes: integer;
    {** Whether the forge view looks for clones beside the recent
      repositories. }
    CloneSiblings: boolean;
    {** Whether the AI features show, the agent they run, and each
      agent's command (empty for the one found; for the API its server,
      empty for OpenAIDefaultUrl) and model (empty for its own choice;
      the API needs one), and the API's key. }
    AIEnabled: boolean;
    Agent: TGittanAgent;
    AgentPaths, AgentModels: array[TGittanAgent] of string;
    ApiKey: string;
  end;

{** Shows the dialog with AFont and AValues in it, its bottom right corner
  at ACorner (screen coordinates) so the code in the middle of the window
  stays in view, or over the middle of the window on About, which has
  nothing to preview. APreview gets every change of the font, the theme or the
  tab width. The sample editor takes its lexers from ALexers and its
  colors and zoom from ATemplate, the main editor. On OK the arguments are
  changed and the result is True; on Cancel they are left alone, and the
  caller undoes the preview. APage is the page shown first. }
function EditSettings(AFont: TFont; var AValues: TSettingsValues;
  APreview: TSettingsPreview; ALexers: TGittanLexers; ATemplate: TATSynEdit;
  ACorner: TPoint; APage: TSettingsPage = pgEditor): boolean;

implementation

uses
  Math, StrUtils, Process, Clipbrd, LCLIntf, LCLType, LCLVersion, InterfaceBase, LCLPlatformDef,
  ec_SyntAnal, ATSynEdit_Adapter_EControl, ATSynEdit_Globals,
  gittan.syntaxthemes, gittan.git, gittan.theme,
  gittan.settings, gittan.job;

resourcestring
  rsSettingsTitle = 'Settings';
  rsEditorPage = 'Editor';
  rsToolsPage = 'Tools';
  rsHostingPage = 'Hosting';
  rsAIPage = 'AI';
  rsAboutPage = 'About';
  rsAIEnabled = 'Turn on the AI features';
  rsAINote = 'They run the agent picked here in the repository, with your own ' +
    'login, or ask a model at an OpenAI-compatible API with your key, to write a ' +
    'commit message from the ticked files, review the changes and find where ' +
    'something is. The changes are sent to its provider (Anthropic for Claude ' +
    'Code, GitHub for Copilot, the server named for the API), and when you ask ' +
    'where something is, so is the text of the files an API''s model picks. Off ' +
    'until turned on here.';
  rsAgent = 'Agent';
  rsAgentPath = '%s, %s''s command line tool';
  rsAgentDefault = 'The %s on PATH';
  rsAgentNotFound = 'Not found on PATH; install %s to use the AI features.';
  rsAgentModel = 'Model';
  rsAgentModelDefault = '%s''s default';
  rsClaudeModelNote = 'An alias such as haiku or sonnet, or a model''s full name.';
  rsCopilotModelNote = 'A model''s name, or auto to let Copilot pick.';
  rsApiUrl = 'Server';
  rsApiUrlNote = 'The base URL of an OpenAI-compatible API: OpenAI''s when empty, ' +
    'https://openrouter.ai/api/v1 for OpenRouter, http://localhost:11434/v1 for a ' +
    'local Ollama.';
  rsApiUrlScheme = 'The server is a URL, starting with http:// or https://.';
  rsApiKey = 'API key';
  rsApiKeyNote = 'Kept in Gittan''s settings file. Leave it empty for a local server ' +
    'that needs none.';
  rsApiModelNote = 'The model''s name as the server knows it, such as gpt-4o-mini, ' +
    'or openai/gpt-4o-mini on OpenRouter. The API needs one.';
  rsApiModelMissing = 'Name a model to use the AI features.';
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
  rsAutoFetch = 'Fetch in the background every';
  rsAutoFetchMinutes = 'minutes';
  rsAutoFetchNote = 'Brings in what is new on the remotes of the open repository, so the ' +
    'counts of what to pull stay current. It shows nothing, and waits for the time to pass ' +
    'since the last fetch, from Gittan or anywhere else.';
  rsForgeTool = '%s, %s''s command line tool';
  rsForgeToolDefault = 'The %s on PATH';
  rsToolFound = 'Found: %s';
  rsToolNotFound = 'Not found on PATH.';
  rsForgeNotFound = 'Not found on PATH; the %s features are off.';
  rsHostingEnabled = 'Turn on the hosting features';
  rsForgeAccount = 'Account on %s';
  rsForgeAccountNote = 'Picking another switches %s''s account everywhere, in a terminal ' +
    'too, and the open repositories ask %s again with it.';
  rsForgeNoAccount = '%s is not logged in to any account.';
  rsHostingNote = 'Pull requests, their checks and review comments, and the page ' +
    'of your pull requests, for a repository with a remote on one of the services ' +
    'below. They run the service''s command line tool with its own login.';
  rsCloneSiblings = 'Look for clones beside the recent repositories';
  rsCloneSiblingsNote = 'A pull request on the page of your pull requests links to a clone of its ' +
    'repository among the recent ones. With this on, the repositories in the folders ' +
    'they are in count too.';
  rsToolTyped = 'Run in place of the one on PATH.';
  rsToolMissing = 'There is no such file.';
  rsAboutName = 'Gittan';
  rsAboutTagline = 'Git Tree Analyzer & Navigator';
  rsAboutBuild = 'Build %d';
  rsAboutLocalBuild = 'A local build of %s';
  rsAboutText = 'A free, native git client built around the diff.';
  rsCheckUpdates = 'Check for &Updates';
  rsUpdateChecking = 'Asking GitHub...';
  rsUpdateCurrent = 'This is the latest build.';
  rsUpdateDownload = 'Download %s';
  rsUpdateLatest = 'The latest release is %s';
  rsUpdateFailed = 'Could not ask GitHub: %s';
  rsRunsOn = 'What it runs on and with';
  rsVersionGittan = 'Gittan build %d';
  rsVersionGittanLocal = 'Gittan, a local build of %s';
  rsVersionNotFound = '%s not found';
  rsVersionAIOff = 'The AI features are off';
  rsVersionHostingOff = 'The hosting features are off';
  rsVersionLibraries = 'Free Pascal %s, LCL %s';
  rsCopyVersions = 'Co&py';
  rsWebsite = 'gittan.app';
  rsSource = 'Source code on GitHub';
  rsLicenses = 'Gittan is free software under the GNU General Public License 3. ' +
    'It is built with Free Pascal and Lazarus; ATSynEdit, ATSynEdit_Ex and ' +
    'ATFlatControls (MPL 2.0 or LGPL); EControl (for open source); EncConv, ' +
    'BGRABitmap and MetaDarkStyle (LGPL); LazInk (0BSD) and the lexers of CudaText.';
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
  {** The icon on the About page at 96 dpi. }
  AboutIconSize = 64;
  {** The lines ShowVersions writes, held while they are read. }
  VersionLines = 6;
  GittanSite = 'https://gittan.app';
  GittanSource = 'https://github.com/slicke/gittan';

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
    FSizeEdit, FTabEdit, FAutoFetchEdit: TSpinEdit;
    FThemeBox: TComboBox;
    FEditorEdit, FTerminalEdit, FGitEdit, FAgentEdit, FKeyEdit, FModelEdit: TEdit;
    FGitNote, FAgentLabel, FAgentNote, FKeyLabel, FKeyNote, FModelNote: TLabel;
    FAIBox, FSiblingsBox, FAutoFetchBox: TCheckBox;
    { The Hosting page's switch, and the block of each registered forge
      (FForges, in their order): its tool's field and the note under it. }
    FHostingBox: TCheckBox;
    FForges: TGittanForgeClasses;
    FForgeEdits: array of TEdit;
    FForgeNotes: array of TLabel;
    { Each forge's accounts as read when the page was built, and a list
      per host to pick one, with the forge (an index into FForges) and
      the host it is for. }
    FAccounts: TGittanForgeAccountsList;
    FAccountBoxes: array of TComboBox;
    FAccountForges: array of integer;
    FAccountHosts: TStringArray;
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
    FEditorBox, FToolsBox, FHostingPage, FAIPage, FAboutPage: TPanel;
    { The About page's update check and what it found (FUpdateLink, a
      link when there is a page to go to), its links in the accent
      (FLinkColor), and what Gittan runs on and with, read the first
      time the page shows. }
    FUpdateJob: TGittanUpdateJob;
    FUpdateLink: TLabel;
    FLinks: array of TLabel;
    FLinkColor: TColor;
    FVersionsLabel: TLabel;
    { Whether the versions are in; a change of a tool, a switch or the
      agent drops it, so the page shown again reads them anew. }
    FVersionsRead: boolean;
    { The versions being read (ReadVersions), nil when none is. }
    FVersionsJob: TThread;
    FOK: TButton;
    { Gittan's icon as loaded, and as resampled for the screen's pixels. }
    FAppIcon, FAppIconShown: TBGRABitmap;
    FBox: TWinControl;
    FPreview: TSettingsPreview;
    FNextTop: integer;
    FLoading: boolean;
    FCorner: TPoint;
    { Over the middle of the window that opened it instead, when it opens
      on About, which has nothing to preview. }
    FCentered: boolean;
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
    function AddLink(ARow: TPanel; const ACaption, AUrl: string): TLabel;
    procedure LinkClick(Sender: TObject);
    procedure UpdateClick(Sender: TObject);
    procedure UpdateDone(Sender: TObject);
    procedure ShowUpdateLink(const ACaption, AUrl: string);
    procedure ReadVersions(Data: PtrInt);
    procedure VersionsDone(Sender: TObject);
    procedure CopyVersionsClick(Sender: TObject);
    procedure AppIconPaint(Sender: TObject);
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
    procedure HostingChange(Sender: TObject);
    procedure AddAccounts(AIndex: integer);
    function PickedAccounts: TGittanForgeAccountsList;
    procedure AutoFetchChange(Sender: TObject);
    procedure AgentChange(Sender: TObject);
    procedure ShowAgent;
    { The picked agent's class (AIClassOf), and whether it is an API. }
    function AgentClass: TGittanAIClass;
    function ApiAgent: boolean;
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

{ Gittan's icon at its largest, from the executable's resources (the
  LCL has no application icon on macOS); nil when there is none. }
function LoadAppIcon: TBGRABitmap;
var
  Icon: TIcon;
begin
  Result := nil;
  Icon := TIcon.Create;
  try
    if not Application.Icon.Empty then
      Icon.Assign(Application.Icon)
    else if FindResource(HInstance, 'MAINICON', RT_GROUP_ICON) <> 0 then
      Icon.LoadFromResourceName(HInstance, 'MAINICON');
    if Icon.Empty then
      Exit;
    Icon.Current := Icon.GetBestIndexForSize(Size(1024, 1024));
    Result := TBGRABitmap.Create;
    Result.Assign(Icon);
  finally
    Icon.Free;
  end;
end;

constructor TSettingsForm.Create(AOwner: TComponent);
var
  Row: TPanel;
  Lbl: TLabel;
  Btn, OK, Cancel: TButton;
  Box: TPaintBox;
  Inner: TPanel;
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
  FHostingPage := AddPage(rsHostingPage, niForge);
  FAIPage := AddPage(rsAIPage, niAI);
  FAboutPage := AddPage(rsAboutPage, niAbout);

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
    git with a note on what will run (ShowTool). }
  FBox := FToolsBox;
  AddLabel(rsEditorCommand, 0);
  FEditorEdit := AddEdit(rsEditorDefault);
  AddLabel(rsEditorNote, 4).Font.Color := clGrayText;

  AddLabel(rsTerminalCommand, 16);
  FTerminalEdit := AddEdit(rsTerminalDefault);
  AddLabel(rsTerminalNote, 4).Font.Color := clGrayText;

  FGitEdit := AddTool(rsGitPath, rsGitDefault, FGitNote);

  { The background fetch: the switch, the minutes and their unit on one
    row (alLeft orders by Left), what it does under them. }
  Row := AddRow(16);
  FAutoFetchBox := TCheckBox.Create(Self);
  FAutoFetchBox.Caption := rsAutoFetch;
  FAutoFetchBox.Align := alLeft;
  FAutoFetchBox.OnChange := @AutoFetchChange;
  FAutoFetchBox.Parent := Row;
  FAutoFetchEdit := TSpinEdit.Create(Self);
  FAutoFetchEdit.MinValue := MinAutoFetchMinutes;
  FAutoFetchEdit.MaxValue := MaxAutoFetchMinutes;
  FAutoFetchEdit.Width := Scale96ToScreen(64);
  FAutoFetchEdit.Align := alLeft;
  FAutoFetchEdit.Left := 1000;
  FAutoFetchEdit.BorderSpacing.Left := Scale96ToScreen(6);
  FAutoFetchEdit.Parent := Row;
  Lbl := TLabel.Create(Self);
  Lbl.Caption := rsAutoFetchMinutes;
  Lbl.Align := alLeft;
  Lbl.Left := 2000;
  Lbl.Layout := tlCenter;
  Lbl.BorderSpacing.Left := Scale96ToScreen(6);
  Lbl.Parent := Row;
  Lbl := AddLabel(rsAutoFetchNote, 4);
  Lbl.Font.Color := clGrayText;
  Lbl.WordWrap := True;

  { The Hosting page: a block per registered forge under its name, the
    switch and what it means, then the tool, which follows the switch;
    the first forge's, whose is the forge view, has the clones' switch
    too. }
  FBox := FHostingPage;
  FForges := RegisteredForges;
  FHostingBox := TCheckBox.Create(Self);
  FHostingBox.Caption := rsHostingEnabled;
  FHostingBox.OnChange := @HostingChange;
  Place(FHostingBox, 0);
  Lbl := AddLabel(rsHostingNote, 4);
  Lbl.Font.Color := clGrayText;
  Lbl.WordWrap := True;
  SetLength(FForgeEdits, Length(FForges));
  SetLength(FForgeNotes, Length(FForges));
  SetLength(FAccounts, Length(FForges));
  for i := 0 to High(FForges) do
  begin
    AddLabel(FForges[i].Name, 20).Font.Style := [fsBold];
    FForgeEdits[i] := AddTool(Format(rsForgeTool, [FForges[i].CliName, FForges[i].Name]),
      Format(rsForgeToolDefault, [FForges[i].CliName]), FForgeNotes[i]);
    AddAccounts(i);
  end;
  FSiblingsBox := TCheckBox.Create(Self);
  FSiblingsBox.Caption := rsCloneSiblings;
  Place(FSiblingsBox, 20);
  Lbl := AddLabel(rsCloneSiblingsNote, 4);
  Lbl.Font.Color := clGrayText;
  Lbl.WordWrap := True;

  { The AI page: the switch and what it means, then the agent, its
    command (the API's server), the API's key, shown for it alone, and
    the model, which follow the switch; the labels name the agent
    picked (ShowAgent). }
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
  FKeyLabel := AddLabel(rsApiKey, 16);
  FKeyEdit := AddEdit('');
  FKeyEdit.PasswordChar := '*';
  FKeyNote := AddLabel(rsApiKeyNote, 4);
  FKeyNote.Font.Color := clGrayText;
  FKeyNote.WordWrap := True;
  AddLabel(rsAgentModel, 16);
  FModelEdit := AddEdit('');
  FModelEdit.OnChange := @ToolChange;
  FModelNote := AddLabel('', 4);
  FModelNote.Font.Color := clGrayText;
  FModelNote.WordWrap := True;

  { The About page: the icon, and beside it the name, the build and what
    Gittan is; the update check, its answer beside it; what Gittan runs
    on and with (ReadVersions), Copy and the links; the licenses. }
  FBox := FAboutPage;
  Row := AddRow(0);
  FAppIcon := LoadAppIcon;
  Box := TPaintBox.Create(Self);
  Box.Width := Scale96ToScreen(AboutIconSize);
  Box.Height := Scale96ToScreen(AboutIconSize);
  Box.Align := alLeft;
  Box.BorderSpacing.Right := Scale96ToScreen(14);
  Box.OnPaint := @AppIconPaint;
  Box.Visible := FAppIcon <> nil;
  Box.Parent := Row;
  Inner := TPanel.Create(Self);
  Inner.BevelOuter := bvNone;
  Inner.AutoSize := True;
  Inner.Align := alClient;
  Inner.Parent := Row;
  FBox := Inner;
  Lbl := AddLabel(rsAboutName, 0);
  Lbl.Font.Size := 20;
  Lbl.Font.Style := [fsBold];
  Lbl := AddLabel(rsAboutTagline, 0);
  Lbl.ShowAccelChar := False;
  if CurrentBuild >= 0 then
    Lbl := AddLabel(Format(rsAboutBuild, [CurrentBuild]), 6)
  else
    Lbl := AddLabel(Format(rsAboutLocalBuild, [{$I %DATE%}]), 6);
  Lbl.Font.Color := clGrayText;
  FBox := FAboutPage;
  AddLabel(rsAboutText, 12);

  Row := AddRow(16);
  Btn := TButton.Create(Self);
  Btn.Caption := rsCheckUpdates;
  Btn.AutoSize := True;
  Btn.Align := alLeft;
  Btn.OnClick := @UpdateClick;
  Btn.Parent := Row;
  FUpdateLink := AddLink(Row, '', '');
  FUpdateLink.Layout := tlCenter;
  FUpdateLink.BorderSpacing.Left := Scale96ToScreen(10);

  AddLabel(rsRunsOn, 16);
  FVersionsLabel := AddLabel(DupeString(LineEnding, VersionLines - 1), 4);
  FVersionsLabel.ShowAccelChar := False;
  FVersionsLabel.Font.Color := clGrayText;
  Row := AddRow(8);
  Btn := TButton.Create(Self);
  Btn.Caption := rsCopyVersions;
  Btn.AutoSize := True;
  Btn.Align := alLeft;
  Btn.BorderSpacing.Right := Scale96ToScreen(14);
  Btn.OnClick := @CopyVersionsClick;
  Btn.Parent := Row;
  AddLink(Row, rsWebsite, GittanSite).Layout := tlCenter;
  AddLink(Row, rsSource, GittanSource).Layout := tlCenter;

  Lbl := AddLabel(rsLicenses, 16);
  Lbl.Font.Color := clGrayText;
  Lbl.WordWrap := True;

  { OK on the right on macOS, Cancel on the right elsewhere. }
  FBox := FContent;
  Row := AddRow(16);
  OK := AddButton(Row, rsOK, mrOK);
  OK.Default := True;
  FOK := OK;
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

{ Update jobs dropped by a dialog that closed while they ran, freed once
  they have finished, as the main form frees its jobs: freeing one at
  once would wait for the request, up to FetchSeconds. }
var
  GUpdateZombies: TList;

procedure FreeFinishedUpdateJobs(AWait: boolean);
var
  i: integer;
begin
  for i := GUpdateZombies.Count - 1 downto 0 do
    if AWait or TThread(GUpdateZombies[i]).Finished then
    begin
      TThread(GUpdateZombies[i]).Free;
      GUpdateZombies.Delete(i);
    end;
end;

destructor TSettingsForm.Destroy;
begin
  Application.RemoveAsyncCalls(Self);
  { A check still running is dropped, not waited for. }
  if FUpdateJob <> nil then
  begin
    FUpdateJob.Stop(False);
    GUpdateZombies.Add(FUpdateJob);
    FUpdateJob := nil;
  end;
  if FVersionsJob <> nil then
  begin
    TGittanJob(FVersionsJob).Stop(False);
    GUpdateZombies.Add(FVersionsJob);
    FVersionsJob := nil;
  end;
  FAppIconShown.Free;
  FAppIcon.Free;
  { The lexer belongs to the main form's list. }
  FAdapter.Lexer := nil;
  FFont.Free;
  inherited Destroy;
end;

{ The content has its size once the form has laid itself out, just before
  it shows: the pages are held at the height of the tallest (one not
  shown has its preferred height, not a laid out one), so the form keeps
  its size when the page changes, and goes to its corner, or over the
  middle of the main window when it opens on About. }
procedure TSettingsForm.DoShow;
var
  W, H, Tallest: integer;
  Main: TCustomForm;
begin
  inherited DoShow;
  { The Editor page is laid out when it is the one shown, else (opened on
    About) it has its preferred height too. }
  FEditorBox.GetPreferredSize(W, H, False, True);
  Tallest := Max(FEditorBox.Height, H);
  FToolsBox.GetPreferredSize(W, H, False, True);
  Tallest := Max(Tallest, H);
  FHostingPage.GetPreferredSize(W, H, False, True);
  Tallest := Max(Tallest, H);
  FAIPage.GetPreferredSize(W, H, False, True);
  Tallest := Max(Tallest, H);
  FAboutPage.GetPreferredSize(W, H, False, True);
  Tallest := Max(Tallest, H);
  FEditorBox.Constraints.MinHeight := Tallest;
  FToolsBox.Constraints.MinHeight := Tallest;
  FHostingPage.Constraints.MinHeight := Tallest;
  FAIPage.Constraints.MinHeight := Tallest;
  FAboutPage.Constraints.MinHeight := Tallest;
  if FCentered and (Owner is TCustomForm) then
  begin
    Main := TCustomForm(Owner);
    SetBounds(Main.Left + (Main.Width - Width) div 2,
      Main.Top + (Main.Height - Height) div 2, Width, Height);
  end
  else
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
    FHostingPage.Visible := False;
    FAIPage.Visible := False;
    FAboutPage.Visible := False;
    case TSettingsPage(AIndex) of
      pgEditor: Box := FEditorBox;
      pgTools: Box := FToolsBox;
      pgHosting: Box := FHostingPage;
      pgAI: Box := FAIPage;
      else
        Box := FAboutPage;
    end;
    Box.Top := 0;
    Box.Visible := True;
  finally
    EnableAutoSizing;
  end;
  FNav.Selected := AIndex;
  { The About page's first control is Check for Updates, which the
    focus would make the default button. }
  if (Box = FAboutPage) and not Box.ContainsControl(ActiveControl) then
    ActiveControl := FOK;
  { git, gh and the agent are asked once the page is drawn. }
  if (Box = FAboutPage) and not FVersionsRead then
  begin
    FVersionsRead := True;
    Application.QueueAsyncCall(@ReadVersions, 0);
  end;
end;

{ The sidebar in the main window's shade, its rows in the editor's text
  color in dark mode. }
procedure TSettingsForm.ApplyTheme;
var
  Dark: boolean;
  TextColor: TColor;
  Link: TLabel;
begin
  Dark := IsDarkMode;
  { The main window's accent. }
  if Dark then
    FLinkColor := RGBToColor(100, 160, 240)
  else
    FLinkColor := RGBToColor(0, 110, 230);
  for Link in FLinks do
    if Link.Hint <> '' then
      Link.Font.Color := FLinkColor;
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

{ As TRepoFrame.SetEditorLexer: a change event from line 0 starts the parse. }
procedure TSettingsForm.SetLexer(ALexer: TecSyntAnalyzer);
begin
  FAdapter.Lexer := ALexer;
  if ALexer <> nil then
    FSampleEdit.DoEventChange(0);
  FSampleEdit.Update(True);
end;

{ Shows the chosen sample, its button down and the others up. The text is
  set as TRepoFrame.ShowText sets it, with the wrap info rebuilt. }
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

{ The versions on About name the tools as the fields have them. }
procedure TSettingsForm.ToolChange(Sender: TObject);
var
  i: integer;
  Server: string;
begin
  FVersionsRead := False;
  if Sender = FGitEdit then
  begin
    ShowTool(FGitEdit, FGitNote, 'git', rsToolNotFound);
    Exit;
  end;
  for i := 0 to High(FForges) do
    if Sender = FForgeEdits[i] then
    begin
      ShowTool(FForgeEdits[i], FForgeNotes[i], FForges[i].CliName,
        Format(rsForgeNotFound, [FForges[i].Name]));
      Exit;
    end;
  { An API has no command to look for: its server's note says when the
    server is no URL (a scheme with no host after it is none), its
    model's when the model it needs is missing. }
  if ApiAgent then
  begin
    Server := LowerCase(Trim(FAgentEdit.Text));
    if (Server = '') or (Pos('http://', Server) = 1) and (Length(Server) > 7) or
      (Pos('https://', Server) = 1) and (Length(Server) > 8) then
      FAgentNote.Caption := rsApiUrlNote
    else
      FAgentNote.Caption := rsApiUrlScheme;
    if Trim(FModelEdit.Text) = '' then
      FModelNote.Caption := rsApiModelMissing
    else
      FModelNote.Caption := rsApiModelNote;
    Exit;
  end;
  { A tool's model is not looked for. }
  if Sender = FModelEdit then
    Exit;
  ShowTool(FAgentEdit, FAgentNote, AgentCommands[FAgent],
    Format(rsAgentNotFound, [AgentNames[FAgent]]));
end;

{ The agent and its fields matter only with the features on. }
procedure TSettingsForm.AIChange(Sender: TObject);
begin
  FVersionsRead := False;
  FAgentBox.Enabled := FAIBox.Checked;
  FAgentEdit.Enabled := FAIBox.Checked;
  FKeyEdit.Enabled := FAIBox.Checked;
  FModelEdit.Enabled := FAIBox.Checked;
end;

procedure TSettingsForm.AutoFetchChange(Sender: TObject);
begin
  FAutoFetchEdit.Enabled := FAutoFetchBox.Checked;
end;

{ The tools and the clones' switch matter only with the hosting
  features on. }
procedure TSettingsForm.HostingChange(Sender: TObject);
var
  i: integer;
begin
  FVersionsRead := False;
  for i := 0 to High(FForges) do
    FForgeEdits[i].Enabled := FHostingBox.Checked;
  for i := 0 to High(FAccountBoxes) do
    FAccountBoxes[i].Enabled := FHostingBox.Checked and (FAccountBoxes[i].Items.Count > 1);
  FSiblingsBox.Enabled := FHostingBox.Checked;
end;

{ Forge AIndex's accounts under its tool: a list per host, the active
  one picked, and a note on what picking does; or why there is nothing
  to pick. }
procedure TSettingsForm.AddAccounts(AIndex: integer);
var
  Accounts: TGittanForgeAccounts;
  Hosts: TStringArray;
  Box: TComboBox;
  Lbl: TLabel;
  Note: string;
  i, j: integer;
  Several: boolean;
begin
  Accounts := FForges[AIndex].Accounts;
  FAccounts[AIndex] := Accounts;
  Hosts := nil;
  for i := 0 to High(Accounts) do
    if IndexText(Accounts[i].Host, Hosts) < 0 then
    begin
      SetLength(Hosts, Length(Hosts) + 1);
      Hosts[High(Hosts)] := Accounts[i].Host;
    end;
  Several := False;
  for i := 0 to High(Hosts) do
  begin
    AddLabel(Format(rsForgeAccount, [Hosts[i]]), 12);
    Box := TComboBox.Create(Self);
    Box.Style := csDropDownList;
    for j := 0 to High(Accounts) do
      if Accounts[j].Host = Hosts[i] then
      begin
        Box.Items.Add(Accounts[j].Login);
        if Accounts[j].Active then
          Box.ItemIndex := Box.Items.Count - 1;
      end;
    if Box.ItemIndex < 0 then
      Box.ItemIndex := 0;
    Several := Several or (Box.Items.Count > 1);
    Place(Box, 4);
    SetLength(FAccountBoxes, Length(FAccountBoxes) + 1);
    FAccountBoxes[High(FAccountBoxes)] := Box;
    SetLength(FAccountForges, Length(FAccountForges) + 1);
    FAccountForges[High(FAccountForges)] := AIndex;
    SetLength(FAccountHosts, Length(FAccountHosts) + 1);
    FAccountHosts[High(FAccountHosts)] := Hosts[i];
  end;
  Note := FForges[AIndex].AccountsNote;
  if Note = '' then
    if Several then
      Note := Format(rsForgeAccountNote, [FForges[AIndex].CliName, FForges[AIndex].Name])
    else if Length(Accounts) = 0 then
      Note := Format(rsForgeNoAccount, [FForges[AIndex].CliName]);
  if Note = '' then
    Exit;
  Lbl := AddLabel(Note, 4);
  Lbl.Font.Color := clGrayText;
  Lbl.WordWrap := True;
end;

{ FAccounts with each list's pick as its host's active account. }
function TSettingsForm.PickedAccounts: TGittanForgeAccountsList;
var
  i, j: integer;
begin
  SetLength(Result, Length(FAccounts));
  for i := 0 to High(FAccounts) do
    Result[i] := Copy(FAccounts[i]);
  for i := 0 to High(FAccountBoxes) do
    for j := 0 to High(Result[FAccountForges[i]]) do
      if Result[FAccountForges[i]][j].Host = FAccountHosts[i] then
        Result[FAccountForges[i]][j].Active :=
          Result[FAccountForges[i]][j].Login = FAccountBoxes[i].Text;
end;

function TSettingsForm.AgentClass: TGittanAIClass;
begin
  Result := AIClassOf(FAgent);
end;

function TSettingsForm.ApiAgent: boolean;
begin
  Result := (AgentClass <> nil) and AgentClass.IsApi;
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
  hints and notes that name it; for an API the command field is its
  server, the key's field shows, and ToolChange gives the notes. }
procedure TSettingsForm.ShowAgent;
begin
  FAgentBox.ItemIndex := Ord(FAgent);
  if ApiAgent then
  begin
    FAgentLabel.Caption := rsApiUrl;
    FAgentEdit.TextHint := AgentClass.Find('');
    FModelEdit.TextHint := '';
  end
  else
  begin
    FAgentLabel.Caption := Format(rsAgentPath, [AgentCommands[FAgent],
      AgentNames[FAgent]]);
    FAgentEdit.TextHint := Format(rsAgentDefault, [AgentCommands[FAgent]]);
    FModelEdit.TextHint := Format(rsAgentModelDefault, [AgentNames[FAgent]]);
    if FAgent = gaCopilot then
      FModelNote.Caption := rsCopilotModelNote
    else
      FModelNote.Caption := rsClaudeModelNote;
  end;
  FAgentEdit.Text := FAgentPaths[FAgent];
  FKeyLabel.Visible := ApiAgent;
  FKeyEdit.Visible := ApiAgent;
  FKeyNote.Visible := ApiAgent;
  FModelEdit.Text := FAgentModels[FAgent];
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
    if (AEdit = FAgentEdit) and (AgentClass <> nil) then
      Path := AgentClass.Find('')
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

{ A link in ARow after what is there, to AUrl, which its hint shows; one
  without a URL reads as plain text. }
function TSettingsForm.AddLink(ARow: TPanel; const ACaption, AUrl: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Caption := ACaption;
  Result.ShowAccelChar := False;
  Result.Hint := AUrl;
  Result.ShowHint := AUrl <> '';
  if AUrl <> '' then
    Result.Cursor := crHandPoint;
  Result.OnClick := @LinkClick;
  Result.Align := alLeft;
  Result.Left := ARow.ControlCount * 1000;
  Result.BorderSpacing.Right := Scale96ToScreen(14);
  Result.Parent := ARow;
  SetLength(FLinks, Length(FLinks) + 1);
  FLinks[High(FLinks)] := Result;
end;

procedure TSettingsForm.LinkClick(Sender: TObject);
begin
  if TLabel(Sender).Hint <> '' then
    OpenURL(TLabel(Sender).Hint);
end;

{ The answer beside the button: a link when there is a page to go to,
  else a note. }
procedure TSettingsForm.ShowUpdateLink(const ACaption, AUrl: string);
begin
  FUpdateLink.Caption := ACaption;
  FUpdateLink.Hint := AUrl;
  FUpdateLink.ShowHint := AUrl <> '';
  if AUrl <> '' then
  begin
    FUpdateLink.Cursor := crHandPoint;
    FUpdateLink.Font.Color := FLinkColor;
  end
  else
  begin
    FUpdateLink.Cursor := crDefault;
    FUpdateLink.Font.Color := clGrayText;
  end;
end;

procedure TSettingsForm.UpdateClick(Sender: TObject);
begin
  if FUpdateJob <> nil then
    Exit;
  FreeFinishedUpdateJobs(False);
  ShowUpdateLink(rsUpdateChecking, '');
  FUpdateJob := TGittanUpdateJob.Create;
  FUpdateJob.OnDone := @UpdateDone;
  FUpdateJob.Start;
end;

{ As the main window's check answers from the menu, without the
  snooze: a newer build to download, the latest release when this
  build cannot be compared with it (a local one, or a release tagged
  other than build-<n>), or that this is the latest. }
procedure TSettingsForm.UpdateDone(Sender: TObject);
var
  Latest: TGittanRelease;
begin
  Latest := FUpdateJob.Release;
  if not FUpdateJob.Ok then
    ShowUpdateLink(Format(rsUpdateFailed, [FUpdateJob.Error]), '')
  else if IsNewerRelease(Latest, CurrentBuild) then
    ShowUpdateLink(Format(rsUpdateDownload, [Latest.Name]), Latest.Url)
  else if (CurrentBuild < 0) or (Latest.Build < 0) then
    ShowUpdateLink(Format(rsUpdateLatest, [Latest.Name]), Latest.Url)
  else
    ShowUpdateLink(rsUpdateCurrent, '');
  FreeAndNil(FUpdateJob);
end;

{ The name of the system and its version. }
function SystemName: string;
{$IF defined(LINUX)}
var
  Lines: TStringList;
{$ENDIF}
begin
  {$IF defined(DARWIN)}
  if RunCommand('/usr/bin/sw_vers', ['-productVersion'], Result, [poNoConsole]) then
    Result := 'macOS ' + Trim(Result)
  else
    Result := 'macOS';
  {$ELSEIF defined(WINDOWS)}
  Result := Format('Windows %d.%d.%d', [Win32MajorVersion, Win32MinorVersion,
    Win32BuildNumber]);
  {$ELSEIF defined(LINUX)}
  Result := 'Linux';
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile('/etc/os-release');
      Lines.NameValueSeparator := '=';
      if Lines.Values['PRETTY_NAME'] <> '' then
        Result := AnsiDequotedStr(Lines.Values['PRETTY_NAME'], '"');
    except
      on EFOpenError do ;
    end;
  finally
    Lines.Free;
  end;
  {$ELSE}
  Result := {$I %FPCTARGETOS%};
  {$ENDIF}
end;

type
  { The versions About lists, read in a thread: git, gh and the agent
    each start a process (the agent node, a second or more), which would
    hold the dialog still. The tools are found in the main thread. }
  TVersionsJob = class(TGittanJob)
  protected
    procedure Execute; override;
  public
    GitExe, Platform: string;
    { Each registered forge's tool and whether it is on. }
    Forges: TGittanForgeClasses;
    ForgeExes: TStringArray;
    HostingOn, AIOn: boolean;
    { The agent as the fields set it up, the job's own; nil when none
      is registered. }
    AI: TGittanAI;
    Text: string;
    destructor Destroy; override;
  end;

destructor TVersionsJob.Destroy;
begin
  inherited Destroy;
  AI.Free;
end;

procedure TVersionsJob.Execute;
var
  Forge: TGittanForge;
  Lines: TStringList;
  Version: string;
  Major, Minor, i: integer;
begin
  Lines := TStringList.Create;
  try
    if CurrentBuild >= 0 then
      Lines.Add(Format(rsVersionGittan, [CurrentBuild]))
    else
      Lines.Add(Format(rsVersionGittanLocal, [{$I %DATE%}]));
    if GitVersionOf(GitExe, Version, Major, Minor) then
      Lines.Add('git ' + Version)
    else
      Lines.Add(Format(rsVersionNotFound, ['git']));
    if not HostingOn then
      Lines.Add(rsVersionHostingOff)
    else
      for i := 0 to High(Forges) do
      begin
        Forge := Forges[i].Create(ForgeExes[i]);
        try
          if Forge.Version(Version) then
            Lines.Add(Forge.CliName + ' ' + Version)
          else
            Lines.Add(Format(rsVersionNotFound, [Forge.CliName]));
        finally
          Forge.Free;
        end;
      end;
    if not AIOn or (AI = nil) then
      Lines.Add(rsVersionAIOff)
    else
    begin
      Version := AI.About;
      if Version <> '' then
        Lines.Add(Version)
      else
        Lines.Add(Format(rsVersionNotFound, [AI.Title]));
    end;
    Lines.Add(Format('%s, %s, %s', [SystemName, {$I %FPCTARGETCPU%}, Platform]));
    Lines.Add(Format(rsVersionLibraries, [{$I %FPCVERSION%}, lcl_version]));
    Text := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
  Done;
end;

{ What Gittan runs on and with: the build, git, gh and the agent (as the
  fields name them now), the system and the libraries; VersionLines in
  all. The tools are found here, their versions asked in a TVersionsJob;
  one still running for fields since changed is dropped. }
procedure TSettingsForm.ReadVersions(Data: PtrInt);
var
  Job: TVersionsJob;
  i: integer;
begin
  if FVersionsJob <> nil then
  begin
    TGittanJob(FVersionsJob).Stop(False);
    GUpdateZombies.Add(FVersionsJob);
    FVersionsJob := nil;
  end;
  FreeFinishedUpdateJobs(False);
  Job := TVersionsJob.Create(False);
  { The git and gh the fields name, saved or not, as the notes under
    them find them. }
  Job.GitExe := Trim(FGitEdit.Text);
  if Job.GitExe = '' then
    Job.GitExe := FindTool('git');
  Job.Forges := Copy(FForges);
  SetLength(Job.ForgeExes, Length(FForges));
  for i := 0 to High(FForges) do
  begin
    Job.ForgeExes[i] := Trim(FForgeEdits[i].Text);
    if Job.ForgeExes[i] = '' then
      Job.ForgeExes[i] := FindTool(FForges[i].CliName);
  end;
  Job.HostingOn := FHostingBox.Checked;
  Job.AIOn := FAIBox.Checked;
  if AgentClass <> nil then
    Job.AI := AgentClass.Create(AgentClass.Find(Trim(FAgentEdit.Text)),
      Trim(FKeyEdit.Text), Trim(FModelEdit.Text));
  Job.Platform := LCLPlatformDisplayNames[WidgetSet.LCLPlatform];
  Job.OnDone := @VersionsDone;
  FVersionsJob := Job;
  Job.Start;
end;

procedure TSettingsForm.VersionsDone(Sender: TObject);
begin
  if Sender <> FVersionsJob then
    Exit;
  FVersionsLabel.Caption := TVersionsJob(Sender).Text;
  FVersionsJob := nil;
  GUpdateZombies.Add(Sender);
end;

{ The icon as a square as wide as the box, in the middle of its height
  (alLeft makes the box as high as the text beside it), resampled to
  the screen's pixels (twice its points on a Retina screen), which Cocoa
  then draws pixel for pixel. }
procedure TSettingsForm.AppIconPaint(Sender: TObject);
var
  Box: TPaintBox;
  Side, Y, Pixels: integer;
begin
  Box := TPaintBox(Sender);
  Side := Min(Box.Width, Box.Height);
  Y := (Box.Height - Side) div 2;
  Pixels := Round(Side * Box.GetCanvasScaleFactor);
  if (FAppIconShown = nil) or (FAppIconShown.Width <> Pixels) then
  begin
    FreeAndNil(FAppIconShown);
    FAppIcon.ResampleFilter := rfBestQuality;
    FAppIconShown := FAppIcon.Resample(Pixels, Pixels, rmFineResample) as TBGRABitmap;
  end;
  FAppIconShown.Draw(Box.Canvas, Rect(0, Y, Side, Y + Side), False);
end;

procedure TSettingsForm.CopyVersionsClick(Sender: TObject);
begin
  Clipboard.AsText := FVersionsLabel.Caption;
end;

function EditSettings(AFont: TFont; var AValues: TSettingsValues;
  APreview: TSettingsPreview; ALexers: TGittanLexers; ATemplate: TATSynEdit;
  ACorner: TPoint; APage: TSettingsPage): boolean;
var
  F: TSettingsForm;
  i: integer;
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
    F.FAutoFetchBox.Checked := AValues.AutoFetch;
    F.FAutoFetchEdit.Value := AValues.AutoFetchMinutes;
    F.AutoFetchChange(nil);
    F.ToolChange(F.FGitEdit);
    for i := 0 to High(F.FForges) do
    begin
      if i <= High(AValues.ForgePaths) then
        F.FForgeEdits[i].Text := AValues.ForgePaths[i];
      F.ToolChange(F.FForgeEdits[i]);
    end;
    F.FHostingBox.Checked := AValues.HostingEnabled;
    F.FSiblingsBox.Checked := AValues.CloneSiblings;
    F.HostingChange(nil);
    F.FAIBox.Checked := AValues.AIEnabled;
    F.FAgent := AValues.Agent;
    F.FAgentPaths := AValues.AgentPaths;
    F.FAgentModels := AValues.AgentModels;
    F.FKeyEdit.Text := AValues.ApiKey;
    F.ShowAgent;
    F.AIChange(nil);
    F.FPreview := APreview;
    F.FLexers := ALexers;
    F.FTemplate := ATemplate;
    F.ApplyTheme;
    F.ShowSample;
    F.FCorner := ACorner;
    F.FCentered := APage = pgAbout;
    F.ShowPage(Ord(APage));
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      AFont.Assign(F.FFont);
      AValues.Theme := F.FThemeBox.ItemIndex;
      AValues.TabSize := F.FTabEdit.Value;
      AValues.EditorCommand := Trim(F.FEditorEdit.Text);
      AValues.TerminalCommand := Trim(F.FTerminalEdit.Text);
      AValues.GitPath := Trim(F.FGitEdit.Text);
      AValues.AutoFetch := F.FAutoFetchBox.Checked;
      AValues.AutoFetchMinutes := F.FAutoFetchEdit.Value;
      SetLength(AValues.ForgePaths, Length(F.FForges));
      for i := 0 to High(F.FForges) do
        AValues.ForgePaths[i] := Trim(F.FForgeEdits[i].Text);
      AValues.HostingEnabled := F.FHostingBox.Checked;
      AValues.Accounts := F.PickedAccounts;
      AValues.CloneSiblings := F.FSiblingsBox.Checked;
      AValues.AIEnabled := F.FAIBox.Checked;
      { The fields hold the picked agent's; the other's are as kept. }
      F.AgentChange(nil);
      AValues.Agent := F.FAgent;
      AValues.AgentPaths := F.FAgentPaths;
      AValues.AgentModels := F.FAgentModels;
      AValues.ApiKey := Trim(F.FKeyEdit.Text);
    end;
  finally
    F.Free;
  end;
end;

initialization
  GUpdateZombies := TList.Create;

finalization
  FreeFinishedUpdateJobs(True);
  FreeAndNil(GUpdateZombies);
end.
