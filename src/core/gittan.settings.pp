unit gittan.settings;

{** What Gittan remembers between runs: the window, the tree width, the
  last and recent repositories, and the view options. The settings live in
  one ini file in the user's configuration folder (GetAppConfigDir), so a
  broken file costs nothing but the defaults. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  {** How many repositories File > Open Recent lists. }
  MaxRecent = 10;
  {** How many actions the command palette lists as recently used. }
  MaxPaletteRecent = 8;
  {** The width of a tab in the editor when none was picked: git's own,
    what a diff shows in a terminal and on GitHub. }
  DefaultTabSize = 8;
  {** How often the background fetch runs, in minutes. }
  DefaultAutoFetchMinutes = 10;
  MinAutoFetchMinutes = 1;
  MaxAutoFetchMinutes = 240;
  {** The editor font when none was picked: the platform's own monospaced
    font (what Terminal and Xcode, Visual Studio or the desktop use). }
  DefaultFontName = {$IFDEF DARWIN}'Menlo'{$ELSE}{$IFDEF WINDOWS}'Consolas'
    {$ELSE}'Monospace'{$ENDIF}{$ENDIF};

{** The editor's font size when none was picked, for a screen AHeight
  logical pixels high (points on macOS, pixels at 96 DPI elsewhere; the
  widgetset scales a point size to the screen's DPI itself): a size up on
  a large screen, which is seen from further away. The LCL's Cocoa takes a
  size as points at 96 DPI and hands macOS that many pixels, a third more
  than a native point, so 9 there is what Xcode and Terminal call 12. }
function DefaultFontSize(AHeight: integer): integer;

type

  { TGittanSettings }

  TGittanSettings = class
  private
    FRecent: TStringList;
    FPaletteRecent: TStringList;
    FTabs: TStringList;
    FTrust: TStringList;
    { Each forge's tool, by its name. }
    FForgeClis: TStringList;
    FFileName: string;
  public
    {** The tab shown when the window closed, an index into Tabs. }
    ActiveTab: integer;
    {** The window bounds, or a zero Width when none were saved. }
    Left, Top, Width, Height: integer;
    Maximized: boolean;
    {** The width of the file tree, 0 for the default. }
    TreeWidth: integer;
    {** Whether the sidebar's rows over the file tree, which open the
      pages, are shown; off, the tree starts under the button that
      shows them again. }
    NavOpen: boolean;
    {** Whether the Config section under the tree is unfolded. }
    RepoFilesOpen: boolean;
    {** Whether the Submodules section under it is unfolded. }
    SubmodulesOpen: boolean;
    {** Whether the Commit section under the tree is unfolded. }
    CommitOpen: boolean;
    {** The commit message being written, kept until it is committed,
      and the repository it is for (its root): another repository's
      section starts empty. The message may have several lines. }
    CommitDraft, CommitDraftRepo: string;
    {** The editor font; an empty name and a zero size keep the defaults
      (DefaultFontName, DefaultFontSize). }
    FontName: string;
    FontSize: integer;
    {** The editor's font scale in percent, 0 for the default. }
    Zoom: integer;
    WordWrap: boolean;
    {** Hide the unchanged lines of a file, keeping ContextLines around
      each change. }
    OnlyChanges: boolean;
    ContextLines: integer;
    SideBySide: boolean;
    {** Show a Markdown file's preview beside the editor. }
    MarkdownPreview: boolean;
    {** Leave whitespace changes out of every diff. }
    IgnoreWhitespace: boolean;
    {** Show in the gutter who last changed each line. }
    Blame: boolean;
    {** Show the review comments of the pull request in the change view. }
    ReviewComments: boolean;
    {** Show a translation file (.po) as its originals beside its
      translations. }
    Translations: boolean;
    {** The name of the syntax theme (see gittan.syntaxthemes); empty for
      the default. }
    SyntaxTheme: string;
    {** Command that opens a file from the context menu, with the path
      appended; empty opens it with the desktop's default application. }
    EditorCommand: string;
    {** Command that opens a terminal, with the repository root appended;
      empty opens the platform's default terminal. }
    TerminalCommand: string;
    {** The width of a tab in the editor, in characters; 0 for the
      default (DefaultTabSize). }
    TabSize: integer;
    {** The git to run, as a path to it; empty runs the git found on
      ToolSearchPath (see gittan.git). }
    GitPath: string;
    {** Whether the open repository is fetched in the background once
      AutoFetchMinutes have passed since it was last fetched; on unless
      the user turns it off. }
    AutoFetch: boolean;
    AutoFetchMinutes: integer;
    {** Whether the GitHub page leaves out the user's pull requests that
      nobody but them has commented on or reviewed. }
    HideWithoutFeedback: boolean;
    {** The GitHub page's other filters, all off by default: of the
      user's pull requests only the ones that need attention (changes
      asked for, checks failing), and no drafts; of the ones waiting for
      their review only the ones asked of them in person, and no
      drafts; of the user's only the stale ones. }
    OnlyNeedsAttention, HideDrafts, OnlyAskedOfMe, HideReviewDrafts, OnlyStale: boolean;
    {** Whether the GitHub page looks for a clone of a pull request's
      repository beside the recent repositories too, in the folders they
      are in, besides among them; off unless the user turns it on. }
    CloneSiblings: boolean;
    {** Whether the AI features show (see gittan.ai): off until the user
      turns them on, since they send the changes to the agent's
      provider. }
    AIEnabled: boolean;
    {** The agent they run, by its key (AgentOfKey): claude, copilot
      or openai. }
    AIAgent: string;
    {** Each agent's command, as a path to it (empty runs the one
      TGittanAI.Find finds), and the model it runs with (empty for its
      own choice). }
    ClaudePath, ClaudeModel, CopilotPath, CopilotModel: string;
    {** The OpenAI-compatible API: its server's base URL (empty for
      OpenAIDefaultUrl), the key sent as the bearer token (empty for
      none, as a local server takes) and the model asked, which it
      needs. The key is kept in the settings file as it is. }
    OpenAIUrl, OpenAIKey, OpenAIModel: string;
    {** The day until which a newer Gittan is not pointed out, 0 for no
      such wait: Remind Me Later in the update dialog sets it. Kept as a
      date alone. }
    UpdateSnoozedUntil: TDateTime;
    {** Whether the hosting features are on (pull requests, the forge
      view, review comments), for every forge at once: a forge acts only
      on a repository with a remote on it. On unless the user turns them
      off. }
    HostingEnabled: boolean;
    {** The command line tool of the forge named AName (gittan.forge's
      Name; gh for GitHub) as a path to it, kept in the forge's own
      section; empty runs the one found on ToolSearchPath, and when there
      is none the forge's features are off. }
    function ForgeCliPath(const AName: string): string;
    procedure SetForgeCliPath(const AName, AValue: string);
    {** AFileName names the ini file; empty picks gittan.ini in the
      user's configuration folder. }
    constructor Create(const AFileName: string = '');
    destructor Destroy; override;
    {** Reads the file; missing keys keep their defaults. }
    procedure Load;
    {** Writes the file, creating its folder. Errors are ignored: a read
      only home must not stop the program from closing. }
    procedure Save;
    {** Puts ARoot first in the recent list, dropping a duplicate and the
      oldest beyond MaxRecent. }
    procedure AddRecent(const ARoot: string);
    {** Puts the action AName (as the command palette names it) first in
      PaletteRecent, dropping a duplicate and the oldest beyond
      MaxPaletteRecent. }
    procedure AddPaletteRecent(const AName: string);
    {** Whether the commands file of the repository at ARoot, whose
      text has the hash AHash (CommandsFileHash), has been trusted:
      the file's commands and keys run only then. A repository without
      the file (AHash empty) needs no trust. }
    function CommandsTrusted(const ARoot, AHash: string): boolean;
    {** Trusts the commands file of ARoot as it is now; a change of its
      text asks again. }
    procedure TrustCommands(const ARoot, AHash: string);
    {** The recently opened repositories, newest first. }
    property Recent: TStringList read FRecent;
    {** The actions last run from the command palette, newest first;
      section Palette. }
    property PaletteRecent: TStringList read FPaletteRecent;
    {** The repositories open in the window's tabs when it closed, left
      to right, which open again at the next start; section Tabs. }
    property Tabs: TStringList read FTabs;
    {** The ini file the settings are read from and written to. }
    property FileName: string read FFileName;
  end;

implementation

uses
  {$IFDEF UNIX}BaseUnix,{$ENDIF} Math, IniFiles, md5, gittan.textfile, gittan.forge;

const
  SecWindow = 'Window';
  SecView = 'View';
  SecRecent = 'Recent';
  SecPalette = 'Palette';
  SecTabs = 'Tabs';
  SecUpdate = 'Update';
  SecCommit = 'Commit';
  SecTools = 'Tools';
  SecTrust = 'Trust';
  SecAI = 'AI';
  { A section per forge, the service that hosts the repositories. }
  SecGitHub = 'GitHub';
  SecHosting = 'Hosting';
  ConfigFolder = 'Gittan';

{** The folder the ini file lives in. GetAppConfigDir names it after
  ApplicationName, which the LCL takes from Application.Title, a long name
  with an ampersand; this keeps its parent and names the folder Gittan
  whatever the title says. }
function ConfigDir: string;
begin
  Result := ExtractFilePath(ExcludeTrailingPathDelimiter(GetAppConfigDir(False)))
    + ConfigFolder;
end;

function DefaultFontSize(AHeight: integer): integer;
begin
  Result := {$IFDEF DARWIN}9{$ELSE}10{$ENDIF};
  if AHeight >= 1200 then
    Inc(Result);
  if AHeight >= 1600 then
    Inc(Result);
end;

{ A day written yyyy-mm-dd, in no locale's format; 0 for anything else. }
function ReadDay(const AText: string): TDateTime;
begin
  if (Length(AText) <> 10) or not TryEncodeDate(StrToIntDef(Copy(AText, 1, 4), 0),
    StrToIntDef(Copy(AText, 6, 2), 0), StrToIntDef(Copy(AText, 9, 2), 0), Result) then
    Result := 0;
end;

{ TIniFile trims a value as it writes and reads it, and takes a pair
  of double quotes around it off as it reads, so a quoted path ("C:\
  Program Files\...") came back unquoted. A value that starts or ends
  with a space or a quote is written inside a pair of quotes of its
  own, which the read takes off again; any other is written as it is,
  so the file reads as before. }
function KeepEdges(const AText: string): string;
begin
  Result := AText;
  if (Result <> '') and ((Result[1] <= ' ') or (Result[1] = '"') or
    (Result[Length(Result)] <= ' ') or (Result[Length(Result)] = '"')) then
    Result := '"' + Result + '"';
end;

{ An ini value is one line: a line end is written as \n, and so a
  backslash as \\; UnescapeC reads it. }
function EscapeLines(const AText: string): string;
begin
  Result := StringReplace(AText, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
end;

{ TGittanSettings }

constructor TGittanSettings.Create(const AFileName: string);
begin
  inherited Create;
  FRecent := TStringList.Create;
  FRecent.CaseSensitive := True;
  FPaletteRecent := TStringList.Create;
  FPaletteRecent.CaseSensitive := True;
  FTabs := TStringList.Create;
  FTrust := TStringList.Create;
  FForgeClis := TStringList.Create;
  FForgeClis.CaseSensitive := False;
  if AFileName <> '' then
    FFileName := AFileName
  else
    FFileName := IncludeTrailingPathDelimiter(ConfigDir) + 'gittan.ini';
  ContextLines := 3;
  SubmodulesOpen := True;
  AutoFetch := True;
  AutoFetchMinutes := DefaultAutoFetchMinutes;
  CommitOpen := True;
  Translations := True;
  HostingEnabled := True;
end;

destructor TGittanSettings.Destroy;
begin
  FForgeClis.Free;
  FTrust.Free;
  FRecent.Free;
  FPaletteRecent.Free;
  FTabs.Free;
  inherited Destroy;
end;

function TGittanSettings.ForgeCliPath(const AName: string): string;
var
  i: integer;
begin
  i := FForgeClis.IndexOfName(AName);
  if i < 0 then
    Exit('');
  Result := FForgeClis.ValueFromIndex[i];
end;

procedure TGittanSettings.SetForgeCliPath(const AName, AValue: string);
var
  i: integer;
begin
  i := FForgeClis.IndexOfName(AName);
  if i >= 0 then
    FForgeClis.Delete(i);
  if AValue <> '' then
    FForgeClis.Add(AName + '=' + AValue);
end;

procedure TGittanSettings.Load;
var
  Ini: TIniFile;
  i: integer;
  Forge: TGittanForgeClass;
  S: string;
begin
  if not FileExists(FFileName) then
    Exit;
  try
    Ini := TIniFile.Create(FFileName);
    try
      Left := Ini.ReadInteger(SecWindow, 'Left', 0);
      Top := Ini.ReadInteger(SecWindow, 'Top', 0);
      Width := Ini.ReadInteger(SecWindow, 'Width', 0);
      Height := Ini.ReadInteger(SecWindow, 'Height', 0);
      Maximized := Ini.ReadBool(SecWindow, 'Maximized', False);
      TreeWidth := Ini.ReadInteger(SecWindow, 'TreeWidth', 0);
      NavOpen := Ini.ReadBool(SecWindow, 'Nav', True);
      RepoFilesOpen := Ini.ReadBool(SecWindow, 'RepoFiles', False);
      SubmodulesOpen := Ini.ReadBool(SecWindow, 'Submodules', True);
      CommitOpen := Ini.ReadBool(SecWindow, 'Commit', True);
      CommitDraft := UnescapeC(Ini.ReadString(SecCommit, 'Draft', ''));
      CommitDraftRepo := Ini.ReadString(SecCommit, 'Repo', '');
      FontName := Ini.ReadString(SecView, 'FontName', '');
      FontSize := Ini.ReadInteger(SecView, 'FontSize', 0);
      { Earlier versions wrote the editor's built-in Courier New 9 though
        nobody picked it; it counts as no choice, so the default applies. }
      if SameText(FontName, 'Courier New') and (FontSize = 9) then
      begin
        FontName := '';
        FontSize := 0;
      end;
      Zoom := Ini.ReadInteger(SecView, 'Zoom', 0);
      WordWrap := Ini.ReadBool(SecView, 'WordWrap', False);
      OnlyChanges := Ini.ReadBool(SecView, 'OnlyChanges', False);
      ContextLines := Ini.ReadInteger(SecView, 'ContextLines', 3);
      SideBySide := Ini.ReadBool(SecView, 'SideBySide', False);
      MarkdownPreview := Ini.ReadBool(SecView, 'MarkdownPreview', False);
      IgnoreWhitespace := Ini.ReadBool(SecView, 'IgnoreWhitespace', False);
      ReviewComments := Ini.ReadBool(SecView, 'ReviewComments', True);
      Translations := Ini.ReadBool(SecView, 'Translations', True);
      Blame := Ini.ReadBool(SecView, 'Blame', False);
      SyntaxTheme := Ini.ReadString(SecView, 'SyntaxTheme', '');
      EditorCommand := Ini.ReadString(SecView, 'EditorCommand', '');
      TerminalCommand := Ini.ReadString(SecView, 'TerminalCommand', '');
      TabSize := Ini.ReadInteger(SecView, 'TabSize', 0);
      GitPath := Ini.ReadString(SecTools, 'Git', '');
      AutoFetch := Ini.ReadBool(SecTools, 'AutoFetch', True);
      AutoFetchMinutes := EnsureRange(Ini.ReadInteger(SecTools, 'AutoFetchMinutes',
        DefaultAutoFetchMinutes), MinAutoFetchMinutes, MaxAutoFetchMinutes);
      { One switch for every forge; earlier versions had one per forge,
        GitHub's, and any of them off turned it off. Each forge's tool in
        its own section; earlier versions kept gh's path with git's,
        under its tool's name. }
      HostingEnabled := True;
      for Forge in RegisteredForges do
        HostingEnabled := HostingEnabled and Ini.ReadBool(Forge.Name, 'Enabled', True);
      HostingEnabled := Ini.ReadBool(SecHosting, 'Enabled', HostingEnabled);
      FForgeClis.Clear;
      for Forge in RegisteredForges do
      begin
        SetForgeCliPath(Forge.Name, Ini.ReadString(Forge.Name, 'Cli',
          Ini.ReadString(SecTools, Forge.CliName, '')));
      end;
      HideWithoutFeedback := Ini.ReadBool(SecGitHub, 'HideWithoutFeedback', False);
      OnlyNeedsAttention := Ini.ReadBool(SecGitHub, 'OnlyNeedsAttention', False);
      HideDrafts := Ini.ReadBool(SecGitHub, 'HideDrafts', False);
      OnlyAskedOfMe := Ini.ReadBool(SecGitHub, 'OnlyAskedOfMe', False);
      HideReviewDrafts := Ini.ReadBool(SecGitHub, 'HideReviewDrafts', False);
      OnlyStale := Ini.ReadBool(SecGitHub, 'OnlyStale', False);
      CloneSiblings := Ini.ReadBool(SecGitHub, 'CloneSiblings', False);
      AIEnabled := Ini.ReadBool(SecAI, 'Enabled', False);
      AIAgent := Ini.ReadString(SecAI, 'Agent', '');
      ClaudePath := Ini.ReadString(SecAI, 'Claude', '');
      ClaudeModel := Ini.ReadString(SecAI, 'ClaudeModel', '');
      CopilotPath := Ini.ReadString(SecAI, 'Copilot', '');
      CopilotModel := Ini.ReadString(SecAI, 'CopilotModel', '');
      OpenAIUrl := Ini.ReadString(SecAI, 'OpenAIUrl', '');
      OpenAIKey := Ini.ReadString(SecAI, 'OpenAIKey', '');
      OpenAIModel := Ini.ReadString(SecAI, 'OpenAIModel', '');
      UpdateSnoozedUntil := ReadDay(Ini.ReadString(SecUpdate, 'SnoozedUntil', ''));
      Ini.ReadSectionValues(SecTrust, FTrust);
      FRecent.Clear;
      for i := 0 to MaxRecent - 1 do
      begin
        S := Ini.ReadString(SecRecent, 'Repo' + IntToStr(i), '');
        if S <> '' then
          FRecent.Add(S);
      end;
      FPaletteRecent.Clear;
      for i := 0 to MaxPaletteRecent - 1 do
      begin
        S := Ini.ReadString(SecPalette, 'Recent' + IntToStr(i), '');
        if S <> '' then
          FPaletteRecent.Add(S);
      end;
      FTabs.Clear;
      i := 0;
      repeat
        S := Ini.ReadString(SecTabs, 'Repo' + IntToStr(i), '');
        if S <> '' then
          FTabs.Add(S);
        Inc(i);
      until S = '';
      ActiveTab := Ini.ReadInteger(SecTabs, 'Active', 0);
      if (ActiveTab < 0) or (ActiveTab >= FTabs.Count) then
        ActiveTab := 0;
    finally
      Ini.Free;
    end;
  except
    { A damaged file is treated as none. }
  end;
end;

procedure TGittanSettings.Save;
var
  Ini: TIniFile;
  i: integer;
  Forge: TGittanForgeClass;
begin
  try
    ForceDirectories(ExtractFileDir(FFileName));
    Ini := TIniFile.Create(FFileName);
    try
      Ini.WriteInteger(SecWindow, 'Left', Left);
      Ini.WriteInteger(SecWindow, 'Top', Top);
      Ini.WriteInteger(SecWindow, 'Width', Width);
      Ini.WriteInteger(SecWindow, 'Height', Height);
      Ini.WriteBool(SecWindow, 'Maximized', Maximized);
      Ini.WriteInteger(SecWindow, 'TreeWidth', TreeWidth);
      Ini.WriteBool(SecWindow, 'Nav', NavOpen);
      Ini.WriteBool(SecWindow, 'RepoFiles', RepoFilesOpen);
      Ini.WriteBool(SecWindow, 'Submodules', SubmodulesOpen);
      Ini.WriteBool(SecWindow, 'Commit', CommitOpen);
      if CommitDraft <> '' then
      begin
        Ini.WriteString(SecCommit, 'Draft', KeepEdges(EscapeLines(CommitDraft)));
        Ini.WriteString(SecCommit, 'Repo', KeepEdges(CommitDraftRepo));
      end
      else
        Ini.EraseSection(SecCommit);
      Ini.WriteString(SecView, 'FontName', KeepEdges(FontName));
      Ini.WriteInteger(SecView, 'FontSize', FontSize);
      Ini.WriteInteger(SecView, 'Zoom', Zoom);
      Ini.WriteBool(SecView, 'WordWrap', WordWrap);
      Ini.WriteBool(SecView, 'OnlyChanges', OnlyChanges);
      Ini.WriteInteger(SecView, 'ContextLines', ContextLines);
      Ini.WriteBool(SecView, 'SideBySide', SideBySide);
      Ini.WriteBool(SecView, 'MarkdownPreview', MarkdownPreview);
      Ini.WriteBool(SecView, 'IgnoreWhitespace', IgnoreWhitespace);
      Ini.WriteBool(SecView, 'ReviewComments', ReviewComments);
      Ini.WriteBool(SecView, 'Translations', Translations);
      Ini.WriteBool(SecView, 'Blame', Blame);
      Ini.WriteString(SecView, 'SyntaxTheme', KeepEdges(SyntaxTheme));
      Ini.WriteString(SecView, 'EditorCommand', KeepEdges(EditorCommand));
      Ini.WriteString(SecView, 'TerminalCommand', KeepEdges(TerminalCommand));
      Ini.WriteInteger(SecView, 'TabSize', TabSize);
      Ini.WriteString(SecTools, 'Git', KeepEdges(GitPath));
      Ini.WriteBool(SecTools, 'AutoFetch', AutoFetch);
      Ini.WriteInteger(SecTools, 'AutoFetchMinutes', AutoFetchMinutes);
      Ini.WriteBool(SecHosting, 'Enabled', HostingEnabled);
      for Forge in RegisteredForges do
      begin
        Ini.DeleteKey(SecTools, Forge.CliName);
        Ini.DeleteKey(Forge.Name, 'Enabled');
        Ini.WriteString(Forge.Name, 'Cli', KeepEdges(ForgeCliPath(Forge.Name)));
      end;
      Ini.WriteBool(SecGitHub, 'HideWithoutFeedback', HideWithoutFeedback);
      Ini.WriteBool(SecGitHub, 'OnlyNeedsAttention', OnlyNeedsAttention);
      Ini.WriteBool(SecGitHub, 'HideDrafts', HideDrafts);
      Ini.WriteBool(SecGitHub, 'OnlyAskedOfMe', OnlyAskedOfMe);
      Ini.WriteBool(SecGitHub, 'HideReviewDrafts', HideReviewDrafts);
      Ini.WriteBool(SecGitHub, 'OnlyStale', OnlyStale);
      Ini.WriteBool(SecGitHub, 'CloneSiblings', CloneSiblings);
      Ini.WriteBool(SecAI, 'Enabled', AIEnabled);
      Ini.WriteString(SecAI, 'Agent', AIAgent);
      Ini.WriteString(SecAI, 'Claude', KeepEdges(ClaudePath));
      Ini.WriteString(SecAI, 'ClaudeModel', KeepEdges(ClaudeModel));
      Ini.WriteString(SecAI, 'Copilot', KeepEdges(CopilotPath));
      Ini.WriteString(SecAI, 'CopilotModel', KeepEdges(CopilotModel));
      Ini.WriteString(SecAI, 'OpenAIUrl', KeepEdges(OpenAIUrl));
      Ini.WriteString(SecAI, 'OpenAIKey', KeepEdges(OpenAIKey));
      Ini.WriteString(SecAI, 'OpenAIModel', KeepEdges(OpenAIModel));
      if UpdateSnoozedUntil > 0 then
        Ini.WriteString(SecUpdate, 'SnoozedUntil',
          FormatDateTime('yyyy"-"mm"-"dd', UpdateSnoozedUntil))
      else
        Ini.DeleteKey(SecUpdate, 'SnoozedUntil');
      Ini.EraseSection(SecRecent);
      for i := 0 to FRecent.Count - 1 do
        Ini.WriteString(SecRecent, 'Repo' + IntToStr(i), KeepEdges(FRecent[i]));
      Ini.EraseSection(SecPalette);
      for i := 0 to FPaletteRecent.Count - 1 do
        Ini.WriteString(SecPalette, 'Recent' + IntToStr(i), KeepEdges(FPaletteRecent[i]));
      Ini.EraseSection(SecTabs);
      for i := 0 to FTabs.Count - 1 do
        Ini.WriteString(SecTabs, 'Repo' + IntToStr(i), KeepEdges(FTabs[i]));
      if FTabs.Count > 0 then
        Ini.WriteInteger(SecTabs, 'Active', ActiveTab);
      Ini.EraseSection(SecTrust);
      for i := 0 to FTrust.Count - 1 do
        Ini.WriteString(SecTrust, FTrust.Names[i], FTrust.ValueFromIndex[i]);
      Ini.UpdateFile;
      {$IFDEF UNIX}
      { The API key is in the file as it is, so no one else may read it. }
      if OpenAIKey <> '' then
        FpChmod(FFileName, &600);
      {$ENDIF}
    finally
      Ini.Free;
    end;
  except
    { Nothing to do; the next run starts with what was saved before. }
  end;
end;

{ The key of a root in the Trust section: its MD5, since a path may
  hold what an ini key cannot. }
function TrustKey(const ARoot: string): string;
begin
  Result := MD5Print(MD5String(ARoot));
end;

function TGittanSettings.CommandsTrusted(const ARoot, AHash: string): boolean;
begin
  Result := (AHash = '') or (FTrust.Values[TrustKey(ARoot)] = AHash);
end;

procedure TGittanSettings.TrustCommands(const ARoot, AHash: string);
begin
  if AHash = '' then
    Exit;
  FTrust.Values[TrustKey(ARoot)] := AHash;
end;

procedure TGittanSettings.AddRecent(const ARoot: string);
var
  i: integer;
begin
  i := FRecent.IndexOf(ARoot);
  if i >= 0 then
    FRecent.Delete(i);
  FRecent.Insert(0, ARoot);
  while FRecent.Count > MaxRecent do
    FRecent.Delete(FRecent.Count - 1);
end;

procedure TGittanSettings.AddPaletteRecent(const AName: string);
var
  i: integer;
begin
  i := FPaletteRecent.IndexOf(AName);
  if i >= 0 then
    FPaletteRecent.Delete(i);
  FPaletteRecent.Insert(0, AName);
  while FPaletteRecent.Count > MaxPaletteRecent do
    FPaletteRecent.Delete(FPaletteRecent.Count - 1);
end;

end.
