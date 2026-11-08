unit gittan.settings;

{** What Gittan remembers between runs, in two JSON files in the user's
  configuration folder (ConfigDir): settings.json holds what the user
  picks (the editor, the diffs, the tools, hosting, AI, the extensions'
  values), state.json what Gittan keeps for itself (the window, the tabs,
  the recent repositories, the commit draft, the trust given to commands
  files and extensions). Each is read whole and written whole through a
  temporary file renamed over it, with the keys Gittan does not know kept
  as they were, so a newer build's keys outlast an older one. A missing or
  broken file costs nothing but the defaults. Earlier builds kept one ini
  file, gittan.ini, which is not read: OldIniFound tells it is there with
  neither JSON file, so the window can say the settings started over. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson;

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
  {** The files in ConfigDir, and the ini file of earlier builds. }
  SettingsFileName = 'settings.json';
  StateFileName = 'state.json';
  OldIniFileName = 'gittan.ini';
  {** The version of the files' layout, written as "version" in both. }
  SettingsVersion = 1;
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

{** The folder the settings live in: the user's configuration folder,
  named Gittan whatever the application's title says. }
function ConfigDir: string;

type

  { TGittanSettings }

  TGittanSettings = class
  private
    FRecent: TStringList;
    FPaletteRecent: TStringList;
    FTabs: TStringList;
    FBatchRepos: TStringList;
    { The two files as read, which Save writes back with the fields put
      in, so a key it does not know stays. What has no field of its own
      lives in them alone: the forges' values (hosting.forges), the
      extensions' (extensions) and their grants (extensionGrants), the
      trust (trust) and the project kinds (projectKinds). }
    FSettingsDoc, FStateDoc: TJSONObject;
    FDir: string;
    FOldIniFound: boolean;
    function ForgeObj(const AForge: string; ACreate: boolean): TJSONObject;
    function ExtObj(const AId: string; ACreate: boolean): TJSONObject;
    function GrantObj(const AId: string; ACreate: boolean): TJSONObject;
    procedure PutSettings;
    procedure PutState;
    function WriteState: boolean;
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
    {** Whether the Commit section's note that ticked files go into the
      commit was put away with Don't Show Again. }
    TickHintHidden: boolean;
    {** Whether the commit graph's tip on dragging a commit onto the
      branch was put away with Don't Show Again. }
    GraphTipHidden: boolean;
    {** The commit graph's toggles: follow only the first parent of a
      merge, and leave the merges out. }
    GraphFirstParent, GraphNoMerges: boolean;
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
      each change; on at first, so a large file shows its changes. }
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
    {** How a changed image is shown: side, swipe, onion or difference
      (gittan.imagediff's ImageModeOf); empty for side by side. }
    ImageMode: string;
    {** Show the merge base as a pane of the merge editor, when the
      conflict markers hold it. }
    MergeBase: boolean;
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
    {** What makes one of the user's pull requests need attention on the
      GitHub page (its filter and its order): changes asked for, checks
      failing; both on by default. }
    ChangesNeedAttention, ChecksNeedAttention: boolean;
    {** The order of the GitHub page's sections, as Ord of a
      TGittanPullOrder (gittan.forge): 0, the last changed first, by
      default; the ones waiting for review never 2 (attention first). }
    MineOrder, ReviewOrder: integer;
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
      Name; gh for GitHub) as a path to it, kept as cli in the forge's
      object (hosting.forges.<Name>); empty runs the one found on
      ToolSearchPath, and when there is none the forge's features are
      off. }
    function ForgeCliPath(const AName: string): string;
    procedure SetForgeCliPath(const AName, AValue: string);
    {** What the forge view keeps for the forge AForge (by its Name),
      in the forge's object under AKey with its first letter in lower
      case: MineFilters and ReviewFilters (the keys of the filters on,
      joined with commas, see gittan.forge), IgnoredChecks (the names of
      the checks that do not count, joined with bars) and Presets (the
      user's own presets, see ParsePresets); empty for none, and an
      empty value set drops the key. }
    function ForgeValue(const AForge, AKey: string): string;
    procedure SetForgeValue(const AForge, AKey, AValue: string);
    {** The folder the extensions (gittan.ext.loader) are read from:
      extensions beside the settings. }
    function ExtensionsDir: string;
    {** The file the forge user's picture is kept in between starts
      (SaveForgePicture in gittan.forge), beside the settings. }
    function ForgePictureFile: string;
    {** Whether the extension AId (ExtIdFromPath, its file's name in
      lower case) loads; on unless turned off in the settings dialog:
      extensions.<id>.enabled false in settings.json. }
    function ExtEnabled(const AId: string): boolean;
    procedure SetExtEnabled(const AId: string; AValue: boolean);
    {** What was granted to the extension AId (gittan.ext.grant): under
      AKey Hash (the SHA-256 of the file approved), Granted (the
      permissions, as PermSetToCSV) and Author; empty for none. Kept in
      state.json, extensionGrants.<id>, the key in lower case.
      ClearExtPerm forgets it, so the next load asks again. }
    function ExtPerm(const AId, AKey: string): string;
    procedure SetExtPerm(const AId, AKey, AValue: string);
    procedure ClearExtPerm(const AId: string);
    {** Whether a grant is stored for AId. }
    function HasExtPerm(const AId: string): boolean;
    {** An extension's own value (Gittan.storage, its settings page),
      extensions.<id>.values in settings.json, a JSON string kept as it
      is, line ends and all; empty for none, and an empty value set drops
      the key. A key tells case, as a JavaScript object's does, and must
      pass ValidExtKey, or SetExtValue raises EArgumentException.
      ExtValueKeys lists the keys set, in the order they were first
      set. }
    function ExtValue(const AId, AKey: string): string;
    procedure SetExtValue(const AId, AKey, AValue: string);
    procedure ExtValueKeys(const AId: string; AKeys: TStrings);
    {** ADir is the folder of the files; empty picks ConfigDir. }
    constructor Create(const ADir: string = '');
    destructor Destroy; override;
    {** Reads both files; a missing key, or one of another JSON type,
      keeps its default. }
    procedure Load;
    {** Writes both files, creating their folder; settings.json is its
      owner's alone on Unix (&600), since the API key is in it as it is.
      Errors are ignored: a read only home must not stop the program
      from closing. }
    procedure Save;
    {** Puts ARoot first in the recent list, dropping a duplicate and the
      oldest beyond MaxRecent. }
    procedure AddRecent(const ARoot: string);
    {** Takes ARoot out of the recent list. }
    procedure RemoveRecent(const ARoot: string);
    {** Writes the recent lists (Recent, PaletteRecent) into state.json
      at once, so a removal from the recent list outlasts a run that does
      not close normally. The file is read again first and the rest of it
      kept as it is there, so what another instance saved since Load
      stays; settings.json is left as it is, and errors are ignored as in
      Save. }
    procedure SaveRecent;
    {** Puts the action AName (as the command palette names it) first in
      PaletteRecent, dropping a duplicate and the oldest beyond
      MaxPaletteRecent. }
    procedure AddPaletteRecent(const AName: string);
    {** Whether the commands files of the repository at ARoot, whose
      text has the hash AHash (CommandsFileHash), have been trusted:
      the files' commands and keys run only then. A repository without
      one (AHash empty) needs no trust. }
    function CommandsTrusted(const ARoot, AHash: string): boolean;
    {** Trusts the commands file of ARoot as it is now; a change of its
      text asks again. }
    procedure TrustCommands(const ARoot, AHash: string);
    {** The kinds of project picked for ARoot on the Project page ("rust,
      go", "none"); '' when none were picked and the files decide. }
    function ProjectKindsOf(const ARoot: string): string;
    {** Keeps AValue as the kinds picked for ARoot; '' forgets them. }
    procedure SetProjectKinds(const ARoot, AValue: string);
    {** The recently opened repositories, newest first. }
    property Recent: TStringList read FRecent;
    {** The actions last run from the command palette, newest first. }
    property PaletteRecent: TStringList read FPaletteRecent;
    {** The repositories open in the window's tabs when it closed, left
      to right, which open again at the next start. }
    property Tabs: TStringList read FTabs;
    {** The repositories picked on the forge view's Batch tab, by their
      roots, kept in state.json (batch.repos). }
    property BatchRepos: TStringList read FBatchRepos;
  public
    {** The operation shown on the Batch tab, by its key (overview, gone,
      identity, maintenance or an extension's; '', the overview, by
      default), kept in state.json (batch.operation), so an extension's
      is found again once the extensions are loaded. }
    BatchOperation: string;
    {** The folder of the files, and the files. }
    property Dir: string read FDir;
    function SettingsFile: string;
    function StateFile: string;
    {** Whether Load found an earlier build's gittan.ini in the folder
      and neither settings.json nor state.json: the settings started
      over, and the window says so once. }
    property OldIniFound: boolean read FOldIniFound;
  end;

{** Whether AKey can be an extension's id or the key of one of its
  values: not empty, and no control character (a line end, a tab), so
  the files stay one key to a line and readable. }
function ValidExtKey(const AKey: string): boolean;

{** A list for the extensions' values as the settings dialog edits them,
  "id" + #9 + "key" as a name with the value after it: the name and the
  value are parted by #31, which ValidExtKey keeps out of an id and a key
  (an = is in a key as any other character), and the names tell case
  (Token and token are two keys). The caller frees it. }
function NewExtValueList: TStringList;

resourcestring
  rsBadExtKey = 'The key "%s" cannot be stored: a key is not empty and has no line end, tab or other control character.';

implementation

uses
  Math, jsonparser, gittan.textfile;

const
  ConfigFolder = 'Gittan';
  { How fpjson lays the files out: two spaces, "key": value. }
  JsonLayout = [foSkipWhiteSpace, foSkipWhiteSpaceOnlyLeading];

{** The folder the files live in. GetAppConfigDir names it after
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

function ValidExtKey(const AKey: string): boolean;
var
  c: char;
begin
  Result := AKey <> '';
  for c in AKey do
    if (c < ' ') or (c = #127) then
      Exit(False);
end;

function NewExtValueList: TStringList;
begin
  Result := TStringList.Create;
  Result.NameValueSeparator := #31;
  Result.CaseSensitive := True;
end;

{ A key of the forge view's (MineFilters) as the file has it
  (mineFilters), and so a grant's (Hash as hash). }
function JsonKey(const AKey: string): string;
begin
  Result := AKey;
  if Result <> '' then
    Result[1] := LowerCase(Result[1]);
end;

{ Reading: the member AName of AObj when it is of the type asked, else
  the default; AObj may be nil. }

function ObjOf(AObj: TJSONObject; const AName: string): TJSONObject;
var
  D: TJSONData;
begin
  Result := nil;
  if AObj = nil then
    Exit;
  D := AObj.Find(AName);
  if D is TJSONObject then
    Result := TJSONObject(D);
end;

function StrOf(AObj: TJSONObject; const AName: string; const ADefault: string = ''): string;
var
  D: TJSONData;
begin
  Result := ADefault;
  if AObj = nil then
    Exit;
  D := AObj.Find(AName);
  if D is TJSONString then
    Result := D.AsString;
end;

function IntOf(AObj: TJSONObject; const AName: string; ADefault: integer = 0): integer;
var
  D: TJSONData;
begin
  Result := ADefault;
  if AObj = nil then
    Exit;
  D := AObj.Find(AName);
  if (D is TJSONIntegerNumber) or (D is TJSONInt64Number) then
  begin
    if (D.AsInt64 >= Low(integer)) and (D.AsInt64 <= High(integer)) then
      Result := D.AsInteger;
  end;
end;

function BoolOf(AObj: TJSONObject; const AName: string; ADefault: boolean): boolean;
var
  D: TJSONData;
begin
  Result := ADefault;
  if AObj = nil then
    Exit;
  D := AObj.Find(AName);
  if D is TJSONBoolean then
    Result := D.AsBoolean;
end;

{ The strings of the array AName into AList (cleared first), at most
  AMax of them when AMax > 0; what is not a string, or is empty, is
  skipped. }
procedure ListOf(AObj: TJSONObject; const AName: string; AList: TStrings; AMax: integer = 0);
var
  D: TJSONData;
  i: integer;
begin
  AList.Clear;
  if AObj = nil then
    Exit;
  D := AObj.Find(AName);
  if not (D is TJSONArray) then
    Exit;
  for i := 0 to TJSONArray(D).Count - 1 do
    if (TJSONArray(D)[i] is TJSONString) and (TJSONArray(D)[i].AsString <> '') and
      ((AMax <= 0) or (AList.Count < AMax)) then
      AList.Add(TJSONArray(D)[i].AsString);
end;

{ Writing. }

{ The object AName of AObj, made (in place of a member of another type)
  when it is not there. }
function ChildOf(AObj: TJSONObject; const AName: string): TJSONObject;
var
  D: TJSONData;
begin
  D := AObj.Find(AName);
  if D is TJSONObject then
    Exit(TJSONObject(D));
  Result := TJSONObject.Create;
  AObj.Elements[AName] := Result;
end;

procedure DropKey(AObj: TJSONObject; const AName: string);
var
  i: integer;
begin
  if AObj = nil then
    Exit;
  i := AObj.IndexOfName(AName);
  if i >= 0 then
    AObj.Delete(i);
end;

{ AValue under AName in AObj, or no AName for an empty AValue; AObj
  goes from AParent under AObjName once it is empty. }
procedure PutOrDrop(AParent: TJSONObject; const AObjName: string; AObj: TJSONObject;
  const AName, AValue: string);
begin
  if AValue <> '' then
    AObj.Strings[AName] := AValue
  else
  begin
    DropKey(AObj, AName);
    if AObj.Count = 0 then
      DropKey(AParent, AObjName);
  end;
end;

function ListJson(AList: TStrings): TJSONArray;
var
  S: string;
begin
  Result := TJSONArray.Create;
  for S in AList do
    Result.Add(S);
end;

{ The file AFileName as a JSON object; an empty one when it is missing,
  cannot be read or is not an object. }
function ReadDoc(const AFileName: string): TJSONObject;
var
  Data: TJSONData;
  Text: RawByteString;
begin
  Result := nil;
  if FileExists(AFileName) then
    try
      { The bytes are UTF-8 whatever the system's code page is. }
      Text := ReadFileBytes(AFileName);
      SetCodePage(Text, CP_UTF8, False);
      Data := GetJSON(UTF8String(Text));
      if Data is TJSONObject then
        Result := TJSONObject(Data)
      else
        Data.Free;
    except
      { A damaged file is treated as none. }
    end;
  if Result = nil then
    Result := TJSONObject.Create;
end;

{ TGittanSettings }

constructor TGittanSettings.Create(const ADir: string);
begin
  inherited Create;
  FRecent := TStringList.Create;
  FRecent.CaseSensitive := True;
  FPaletteRecent := TStringList.Create;
  FPaletteRecent.CaseSensitive := True;
  FTabs := TStringList.Create;
  FBatchRepos := TStringList.Create;
  FBatchRepos.CaseSensitive := True;
  FSettingsDoc := TJSONObject.Create;
  FStateDoc := TJSONObject.Create;
  if ADir <> '' then
    FDir := ExcludeTrailingPathDelimiter(ADir)
  else
    FDir := ConfigDir;
  ContextLines := 3;
  OnlyChanges := True;
  NavOpen := True;
  SubmodulesOpen := True;
  AutoFetch := True;
  AutoFetchMinutes := DefaultAutoFetchMinutes;
  ChangesNeedAttention := True;
  ChecksNeedAttention := True;
  CommitOpen := True;
  ReviewComments := True;
  Translations := True;
  HostingEnabled := True;
end;

destructor TGittanSettings.Destroy;
begin
  FSettingsDoc.Free;
  FStateDoc.Free;
  FRecent.Free;
  FPaletteRecent.Free;
  FTabs.Free;
  FBatchRepos.Free;
  inherited Destroy;
end;

function TGittanSettings.SettingsFile: string;
begin
  Result := IncludeTrailingPathDelimiter(FDir) + SettingsFileName;
end;

function TGittanSettings.StateFile: string;
begin
  Result := IncludeTrailingPathDelimiter(FDir) + StateFileName;
end;

function TGittanSettings.ForgeObj(const AForge: string; ACreate: boolean): TJSONObject;
begin
  if ACreate then
    Result := ChildOf(ChildOf(ChildOf(FSettingsDoc, 'hosting'), 'forges'), AForge)
  else
    Result := ObjOf(ObjOf(ObjOf(FSettingsDoc, 'hosting'), 'forges'), AForge);
end;

function TGittanSettings.ExtObj(const AId: string; ACreate: boolean): TJSONObject;
begin
  if ACreate then
    Result := ChildOf(ChildOf(FSettingsDoc, 'extensions'), AId)
  else
    Result := ObjOf(ObjOf(FSettingsDoc, 'extensions'), AId);
end;

function TGittanSettings.GrantObj(const AId: string; ACreate: boolean): TJSONObject;
begin
  if ACreate then
    Result := ChildOf(ChildOf(FStateDoc, 'extensionGrants'), AId)
  else
    Result := ObjOf(ObjOf(FStateDoc, 'extensionGrants'), AId);
end;

function TGittanSettings.ForgeValue(const AForge, AKey: string): string;
begin
  Result := StrOf(ForgeObj(AForge, False), JsonKey(AKey));
end;

procedure TGittanSettings.SetForgeValue(const AForge, AKey, AValue: string);
begin
  if (AValue = '') and (ForgeObj(AForge, False) = nil) then
    Exit;
  PutOrDrop(ObjOf(ObjOf(FSettingsDoc, 'hosting'), 'forges'), AForge,
    ForgeObj(AForge, True), JsonKey(AKey), AValue);
end;

function TGittanSettings.ForgeCliPath(const AName: string): string;
begin
  Result := StrOf(ForgeObj(AName, False), 'cli');
end;

procedure TGittanSettings.SetForgeCliPath(const AName, AValue: string);
begin
  SetForgeValue(AName, 'cli', AValue);
end;

procedure TGittanSettings.Load;
var
  O, Sub: TJSONObject;
begin
  FreeAndNil(FSettingsDoc);
  FreeAndNil(FStateDoc);
  FOldIniFound := not FileExists(SettingsFile) and not FileExists(StateFile) and
    FileExists(IncludeTrailingPathDelimiter(FDir) + OldIniFileName);
  FSettingsDoc := ReadDoc(SettingsFile);
  FStateDoc := ReadDoc(StateFile);

  O := ObjOf(FSettingsDoc, 'editor');
  FontName := StrOf(O, 'fontName');
  FontSize := IntOf(O, 'fontSize');
  Zoom := IntOf(O, 'zoom');
  TabSize := IntOf(O, 'tabSize');
  WordWrap := BoolOf(O, 'wordWrap', False);
  SyntaxTheme := StrOf(O, 'syntaxTheme');
  O := ObjOf(FSettingsDoc, 'diff');
  OnlyChanges := BoolOf(O, 'onlyChanges', True);
  ContextLines := Max(0, IntOf(O, 'contextLines', 3));
  SideBySide := BoolOf(O, 'sideBySide', False);
  IgnoreWhitespace := BoolOf(O, 'ignoreWhitespace', False);
  Blame := BoolOf(O, 'blame', False);
  MarkdownPreview := BoolOf(O, 'markdownPreview', False);
  ReviewComments := BoolOf(O, 'reviewComments', True);
  Translations := BoolOf(O, 'translations', True);
  ImageMode := StrOf(O, 'imageMode');
  MergeBase := BoolOf(O, 'mergeBase', False);
  O := ObjOf(FSettingsDoc, 'tools');
  GitPath := StrOf(O, 'git');
  EditorCommand := StrOf(O, 'editor');
  TerminalCommand := StrOf(O, 'terminal');
  AutoFetch := BoolOf(O, 'autoFetch', True);
  AutoFetchMinutes := EnsureRange(IntOf(O, 'autoFetchMinutes', DefaultAutoFetchMinutes),
    MinAutoFetchMinutes, MaxAutoFetchMinutes);
  O := ObjOf(FSettingsDoc, 'hosting');
  HostingEnabled := BoolOf(O, 'enabled', True);
  CloneSiblings := BoolOf(O, 'cloneSiblings', False);
  ChangesNeedAttention := BoolOf(O, 'changesNeedAttention', True);
  ChecksNeedAttention := BoolOf(O, 'checksNeedAttention', True);
  MineOrder := EnsureRange(IntOf(O, 'mineOrder'), 0, 2);
  ReviewOrder := EnsureRange(IntOf(O, 'reviewOrder'), 0, 1);
  O := ObjOf(FSettingsDoc, 'ai');
  AIEnabled := BoolOf(O, 'enabled', False);
  AIAgent := StrOf(O, 'agent');
  Sub := ObjOf(O, 'claude');
  ClaudePath := StrOf(Sub, 'path');
  ClaudeModel := StrOf(Sub, 'model');
  Sub := ObjOf(O, 'copilot');
  CopilotPath := StrOf(Sub, 'path');
  CopilotModel := StrOf(Sub, 'model');
  Sub := ObjOf(O, 'openai');
  OpenAIUrl := StrOf(Sub, 'url');
  OpenAIKey := StrOf(Sub, 'key');
  OpenAIModel := StrOf(Sub, 'model');

  O := ObjOf(FStateDoc, 'window');
  Left := IntOf(O, 'left');
  Top := IntOf(O, 'top');
  Width := Max(0, IntOf(O, 'width'));
  Height := Max(0, IntOf(O, 'height'));
  Maximized := BoolOf(O, 'maximized', False);
  TreeWidth := Max(0, IntOf(O, 'treeWidth'));
  NavOpen := BoolOf(O, 'nav', True);
  RepoFilesOpen := BoolOf(O, 'repoFiles', False);
  SubmodulesOpen := BoolOf(O, 'submodules', True);
  CommitOpen := BoolOf(O, 'commit', True);
  O := ObjOf(FStateDoc, 'graph');
  GraphFirstParent := BoolOf(O, 'firstParent', False);
  GraphNoMerges := BoolOf(O, 'noMerges', False);
  O := ObjOf(FStateDoc, 'tips');
  TickHintHidden := BoolOf(O, 'tickHintHidden', False);
  GraphTipHidden := BoolOf(O, 'graphTipHidden', False);
  O := ObjOf(FStateDoc, 'commitDraft');
  CommitDraft := StrOf(O, 'text');
  CommitDraftRepo := StrOf(O, 'repo');
  UpdateSnoozedUntil := ReadDay(StrOf(ObjOf(FStateDoc, 'update'), 'snoozedUntil'));
  ListOf(FStateDoc, 'recent', FRecent, MaxRecent);
  ListOf(FStateDoc, 'paletteRecent', FPaletteRecent, MaxPaletteRecent);
  O := ObjOf(FStateDoc, 'tabs');
  ListOf(O, 'open', FTabs);
  ActiveTab := IntOf(O, 'active');
  ListOf(ObjOf(FStateDoc, 'batch'), 'repos', FBatchRepos);
  BatchOperation := StrOf(ObjOf(FStateDoc, 'batch'), 'operation');
  { Kept by its index before. }
  if BatchOperation = '' then
    case IntOf(ObjOf(FStateDoc, 'batch'), 'operation') of
      1: BatchOperation := 'gone';
      2: BatchOperation := 'identity';
      3: BatchOperation := 'maintenance';
    end;
  if (ActiveTab < 0) or (ActiveTab >= FTabs.Count) then
    ActiveTab := 0;
end;

procedure TGittanSettings.PutSettings;
var
  O, Sub: TJSONObject;
begin
  FSettingsDoc.Integers['version'] := SettingsVersion;
  O := ChildOf(FSettingsDoc, 'editor');
  O.Strings['fontName'] := FontName;
  O.Integers['fontSize'] := FontSize;
  O.Integers['zoom'] := Zoom;
  O.Integers['tabSize'] := TabSize;
  O.Booleans['wordWrap'] := WordWrap;
  O.Strings['syntaxTheme'] := SyntaxTheme;
  O := ChildOf(FSettingsDoc, 'diff');
  O.Booleans['onlyChanges'] := OnlyChanges;
  O.Integers['contextLines'] := ContextLines;
  O.Booleans['sideBySide'] := SideBySide;
  O.Booleans['ignoreWhitespace'] := IgnoreWhitespace;
  O.Booleans['blame'] := Blame;
  O.Booleans['markdownPreview'] := MarkdownPreview;
  O.Booleans['reviewComments'] := ReviewComments;
  O.Booleans['translations'] := Translations;
  O.Strings['imageMode'] := ImageMode;
  O.Booleans['mergeBase'] := MergeBase;
  O := ChildOf(FSettingsDoc, 'tools');
  O.Strings['git'] := GitPath;
  O.Strings['editor'] := EditorCommand;
  O.Strings['terminal'] := TerminalCommand;
  O.Booleans['autoFetch'] := AutoFetch;
  O.Integers['autoFetchMinutes'] := AutoFetchMinutes;
  O := ChildOf(FSettingsDoc, 'hosting');
  O.Booleans['enabled'] := HostingEnabled;
  O.Booleans['cloneSiblings'] := CloneSiblings;
  O.Booleans['changesNeedAttention'] := ChangesNeedAttention;
  O.Booleans['checksNeedAttention'] := ChecksNeedAttention;
  O.Integers['mineOrder'] := MineOrder;
  O.Integers['reviewOrder'] := ReviewOrder;
  O := ChildOf(FSettingsDoc, 'ai');
  O.Booleans['enabled'] := AIEnabled;
  O.Strings['agent'] := AIAgent;
  Sub := ChildOf(O, 'claude');
  Sub.Strings['path'] := ClaudePath;
  Sub.Strings['model'] := ClaudeModel;
  Sub := ChildOf(O, 'copilot');
  Sub.Strings['path'] := CopilotPath;
  Sub.Strings['model'] := CopilotModel;
  Sub := ChildOf(O, 'openai');
  Sub.Strings['url'] := OpenAIUrl;
  Sub.Strings['key'] := OpenAIKey;
  Sub.Strings['model'] := OpenAIModel;
end;

procedure TGittanSettings.PutState;
var
  O: TJSONObject;
begin
  FStateDoc.Integers['version'] := SettingsVersion;
  O := ChildOf(FStateDoc, 'window');
  O.Integers['left'] := Left;
  O.Integers['top'] := Top;
  O.Integers['width'] := Width;
  O.Integers['height'] := Height;
  O.Booleans['maximized'] := Maximized;
  O.Integers['treeWidth'] := TreeWidth;
  O.Booleans['nav'] := NavOpen;
  O.Booleans['repoFiles'] := RepoFilesOpen;
  O.Booleans['submodules'] := SubmodulesOpen;
  O.Booleans['commit'] := CommitOpen;
  O := ChildOf(FStateDoc, 'graph');
  O.Booleans['firstParent'] := GraphFirstParent;
  O.Booleans['noMerges'] := GraphNoMerges;
  O := ChildOf(FStateDoc, 'tips');
  O.Booleans['tickHintHidden'] := TickHintHidden;
  O.Booleans['graphTipHidden'] := GraphTipHidden;
  if CommitDraft <> '' then
  begin
    O := ChildOf(FStateDoc, 'commitDraft');
    O.Strings['text'] := CommitDraft;
    O.Strings['repo'] := CommitDraftRepo;
  end
  else
  begin
    { No draft: its members go, a key of a newer build's stays. }
    O := ObjOf(FStateDoc, 'commitDraft');
    DropKey(O, 'text');
    DropKey(O, 'repo');
    if (O = nil) or (O.Count = 0) then
      DropKey(FStateDoc, 'commitDraft');
  end;
  if UpdateSnoozedUntil > 0 then
    ChildOf(FStateDoc, 'update').Strings['snoozedUntil'] :=
      FormatDateTime('yyyy"-"mm"-"dd', UpdateSnoozedUntil)
  else
    DropKey(ObjOf(FStateDoc, 'update'), 'snoozedUntil');
  FStateDoc.Arrays['recent'] := ListJson(FRecent);
  FStateDoc.Arrays['paletteRecent'] := ListJson(FPaletteRecent);
  O := ChildOf(FStateDoc, 'tabs');
  O.Arrays['open'] := ListJson(FTabs);
  O.Integers['active'] := ActiveTab;
  ChildOf(FStateDoc, 'batch').Arrays['repos'] := ListJson(FBatchRepos);
  ChildOf(FStateDoc, 'batch').Strings['operation'] := BatchOperation;
end;

function TGittanSettings.WriteState: boolean;
begin
  PutState;
  Result := WriteFileReplacing(StateFile, FStateDoc.FormatJSON(JsonLayout) + LineEnding);
end;

procedure TGittanSettings.Save;
begin
  try
    PutSettings;
    { The API key is in the file as it is, so no one else may read it. }
    WriteFileReplacing(SettingsFile, FSettingsDoc.FormatJSON(JsonLayout) + LineEnding, &600);
    WriteState;
  except
    { Nothing to do; the next run starts with what was saved before. }
  end;
end;

procedure TGittanSettings.SaveRecent;
var
  Doc: TJSONObject;
begin
  { The file as it is now, which another instance may have written since
    Load, with the recent lists put in, and nothing else. }
  try
    Doc := ReadDoc(StateFile);
    try
      Doc.Integers['version'] := SettingsVersion;
      Doc.Arrays['recent'] := ListJson(FRecent);
      Doc.Arrays['paletteRecent'] := ListJson(FPaletteRecent);
      WriteFileReplacing(StateFile, Doc.FormatJSON(JsonLayout) + LineEnding);
    finally
      Doc.Free;
    end;
  except
    { As in Save. }
  end;
end;

function TGittanSettings.ExtensionsDir: string;
begin
  Result := IncludeTrailingPathDelimiter(FDir) + 'extensions';
end;

function TGittanSettings.ForgePictureFile: string;
begin
  Result := IncludeTrailingPathDelimiter(FDir) + 'forge-picture';
end;

function TGittanSettings.ExtEnabled(const AId: string): boolean;
begin
  Result := BoolOf(ExtObj(AId, False), 'enabled', True);
end;

procedure TGittanSettings.SetExtEnabled(const AId: string; AValue: boolean);
begin
  if not AValue then
    ExtObj(AId, True).Booleans['enabled'] := False
  else if ExtObj(AId, False) <> nil then
  begin
    DropKey(ExtObj(AId, False), 'enabled');
    if ExtObj(AId, False).Count = 0 then
      DropKey(ObjOf(FSettingsDoc, 'extensions'), AId);
  end;
end;

function TGittanSettings.ExtPerm(const AId, AKey: string): string;
begin
  Result := StrOf(GrantObj(AId, False), JsonKey(AKey));
end;

procedure TGittanSettings.SetExtPerm(const AId, AKey, AValue: string);
begin
  if (AValue = '') and (GrantObj(AId, False) = nil) then
    Exit;
  PutOrDrop(ObjOf(FStateDoc, 'extensionGrants'), AId, GrantObj(AId, True),
    JsonKey(AKey), AValue);
end;

procedure TGittanSettings.ClearExtPerm(const AId: string);
begin
  DropKey(ObjOf(FStateDoc, 'extensionGrants'), AId);
end;

function TGittanSettings.HasExtPerm(const AId: string): boolean;
begin
  Result := ExtPerm(AId, 'Hash') <> '';
end;

function TGittanSettings.ExtValue(const AId, AKey: string): string;
begin
  Result := StrOf(ObjOf(ExtObj(AId, False), 'values'), AKey);
end;

procedure TGittanSettings.SetExtValue(const AId, AKey, AValue: string);
var
  Ext: TJSONObject;
begin
  if not ValidExtKey(AKey) then
    raise EArgumentException.CreateFmt(rsBadExtKey, [AKey]);
  if (AValue = '') and (ObjOf(ExtObj(AId, False), 'values') = nil) then
    Exit;
  Ext := ExtObj(AId, True);
  PutOrDrop(Ext, 'values', ChildOf(Ext, 'values'), AKey, AValue);
  if Ext.Count = 0 then
    DropKey(ObjOf(FSettingsDoc, 'extensions'), AId);
end;

procedure TGittanSettings.ExtValueKeys(const AId: string; AKeys: TStrings);
var
  Values: TJSONObject;
  i: integer;
begin
  Values := ObjOf(ExtObj(AId, False), 'values');
  if Values <> nil then
    for i := 0 to Values.Count - 1 do
      if Values.Items[i] is TJSONString then
        AKeys.Add(Values.Names[i]);
end;

function TGittanSettings.CommandsTrusted(const ARoot, AHash: string): boolean;
begin
  Result := (AHash = '') or (StrOf(ObjOf(FStateDoc, 'trust'), ARoot) = AHash);
end;

procedure TGittanSettings.TrustCommands(const ARoot, AHash: string);
begin
  if AHash = '' then
    Exit;
  ChildOf(FStateDoc, 'trust').Strings[ARoot] := AHash;
end;

function TGittanSettings.ProjectKindsOf(const ARoot: string): string;
begin
  Result := StrOf(ObjOf(FStateDoc, 'projectKinds'), ARoot);
end;

procedure TGittanSettings.SetProjectKinds(const ARoot, AValue: string);
begin
  if AValue <> '' then
    ChildOf(FStateDoc, 'projectKinds').Strings[ARoot] := AValue
  else
    DropKey(ObjOf(FStateDoc, 'projectKinds'), ARoot);
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

procedure TGittanSettings.RemoveRecent(const ARoot: string);
var
  i: integer;
begin
  i := FRecent.IndexOf(ARoot);
  if i >= 0 then
    FRecent.Delete(i);
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
