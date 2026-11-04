unit gittan.repocommands;

{** The commands of a repository: what the Commands page lists as
  buttons and runs from the repository's root. They come from four
  places: the commands files, .gittan/commands.toml and each .toml in
  .gittan/commands/, written by hand and committed, where a table under
  [commands] names a command, its shell line, a key for its shortcut and
  whether it runs in a terminal; the scripts of a package.json, each
  run through the package manager the lock file tells (npm, pnpm, yarn
  or bun); the targets of a Makefile, each run by make; and the
  commands of the kinds of project the root's files tell (gittan.project:
  cargo build for a Cargo.toml, go test ./... for a go.mod, lazbuild for
  a .lpi), each under its kind's name. A table of a file with no run
  line and the name of a script, a target or a kind's command gives
  that one its key, so a repository can give its own make test a
  shortcut without writing it again, and a line project = ["rust", "go"]
  of commands.toml keeps the kinds to those named ("none" for no kind)
  when the files would tell another. The TOML is read by toml-fp
  (vendor/toml-fp). Nothing here needs the LCL; tested in
  tests/testrepocommands.pp and tests/testproject.pp.

  A committed file lets a clone say what a key does on this computer,
  so the files' commands run only once the user has trusted them:
  CommandsFileHash names the files' content, which the settings keep for
  the roots trusted, and a change of any of them asks again.

  TGittanCommandJob runs a command in a thread through the user's shell
  (a login shell, so the PATH is the terminal's) with its output read as
  it writes, told to the main thread, and its exit code at the end;
  Kill ends it and what it started, forced when it has not ended
  KillGraceMs later. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.job, gittan.project;

const
  {** The folder of the repository's own Gittan files, at the root. }
  CommandsFolder = '.gittan';
  {** The commands file inside it. }
  CommandsFile = 'commands.toml';
  {** The file as a path relative to the root, with "/". }
  CommandsPath = CommandsFolder + '/' + CommandsFile;
  {** The folder inside it whose .toml files are commands files too, a
    section of the page each. }
  CommandsSubFolder = 'commands';
  {** How much of a command's output the job keeps: the newest bytes. }
  OutputKeep = 1024 * 1024;
  {** How long a command may take to end after Kill before it is made
    to: SIGKILL where Kill sent SIGTERM. }
  KillGraceMs = 3000;

type
  {** Where a command comes from: the commands file, package.json, a
    Makefile, a kind of project's tools. }
  TGittanCommandSource = (csFile, csPackage, csMake, csProject);

  TGittanRepoCommand = record
    {** The table's name, the script's or the target's. }
    Name: string;
    {** The shell line that runs it. }
    Command: string;
    {** What the page shows under the name: the shell line, or a
      script's text for package.json. }
    Detail: string;
    {** The shortcut's key, 'A'..'Z' or '0'..'9'; #0 for none. }
    Key: char;
    {** Runs in a terminal window instead of under the page. }
    Terminal: boolean;
    {** A line the file gives that says what it does, for the tile's
      hint; '' for none. }
    Description: string;
    {** Asks before it runs: the file's confirm = true, or a question of
      its own (ConfirmText, '' for the plain one). }
    Confirm: boolean;
    ConfirmText: string;
    {** The file's hidden = true: it is not listed, nor a script, target
      or kind's command it names. Only ParseCommandsToml gives it;
      DiscoverRepoCommands leaves such ones out. }
    Hidden: boolean;
    {** run is a table of lines per system and has none for this one:
      Command is empty, and the page says so. }
    Elsewhere: boolean;
    {** A section with no run line whose name an earlier section already
      took: the command line of the script, target or
      kind's command they both name ("make test"). It is listed
      without a command, as one that names nothing is; '' otherwise. }
    Overlaps: string;
    Source: TGittanCommandSource;
    {** The kind's name for csProject ("Rust"); the file's path for
      csFile (".gittan/commands.toml", TGittanCommandsFile.Path); '' for the
      rest. }
    Project: string;
  end;
  TGittanRepoCommands = array of TGittanRepoCommand;

  {** A commands file as read: its path relative to the root with "/",
    its text, its commands (Project set to Path) and, for the first
    file, the kinds of project it asks for. Error is what the TOML reader
    said when the text is not TOML, which gives no commands. }
  TGittanCommandsFile = record
    Path, Text, Error: string;
    Commands: TGittanRepoCommands;
    HasProjects: boolean;
    Projects: TStringArray;
  end;
  TGittanCommandsFiles = array of TGittanCommandsFile;

{** The commands of a commands.toml's text: a table per command under
  [commands], [commands.test], with run = the shell line, key = one
  letter or digit, terminal = true, description = a line for the hint,
  confirm = true or a question to ask before it runs, and hidden = true;
  a string as the table's value, lint = "npm run lint" under
  [commands], is its run line. run may be a table of lines per system,
  run = { windows = "...", unix = "..." }: the line of ASystem (macos,
  windows, linux, freebsd, haiku; '' for the system Gittan runs on),
  else unix's on any system but Windows, else default's; with none of
  them Command is empty and Elsewhere true. A table without a run line
  has an empty Command and stands for a script's or a target's key.
  Keys are kept as capitals; anything but a letter or a digit is no
  key. TOML keeps no order, so they come sorted by name. AError is the
  reader's message when the text is not TOML, with no commands. }
function ParseCommandsToml(const AText: string; out AError: string;
  const ASystem: string = ''): TGittanRepoCommands;

{** The system Gittan runs on as a key of a run table: macos, windows,
  linux, freebsd, haiku, or unix for another Unix. }
function CommandsSystem: string;

{** The same as people write it: macOS, Windows, Linux. }
function CommandsSystemTitle: string;

{** The kinds of project a commands.toml's text asks for: true with
  ANames when it has project = ["rust", "go"] or project = "rust, go"
  ("none" gives true and no names), false without, when the files
  decide. }
function ParseCommandsTomlProjects(const AText: string; out ANames: TStringArray): boolean;

{** The commands files under ARoot, read and parsed: commands.toml, then
  the .toml files of .gittan/commands by name. }
function ReadCommandsFiles(const ARoot: string): TGittanCommandsFiles;

{** The scripts of a package.json's text, in its order: Name is the
  script's name and Detail its text; Command is empty, DiscoverRepoCommands
  fills it with the runner. None when the text is not JSON or has no
  scripts. }
function ParsePackageScripts(const AJson: string): TGittanRepoCommands;

{** The targets of a Makefile's text, in order, each once: the names
  before the colon of a rule line, when every one of them is a plain
  name (no "." first, no "/", "%", "$" or "="). Lines of a recipe,
  assignments and pattern rules give none. }
function ParseMakefileTargets(const AText: string): TStringArray;

{** The command that runs a package script under ARoot: "npm run", or
  pnpm's, yarn's or bun's when their lock file is there. }
function PackageRunner(const ARoot: string): string;

{** The commands of the repository at ARoot: the files' first, file by
  file, then the scripts, then the targets, then each kind of project's
  in the order the kinds are registered, with the keys the files give
  them. A file's table with no run line that names no script, target
  or kind's command is kept among the file's, with an empty Command, so
  the page can say so. AProjects is the kinds found, as the file's
  project line keeps them (ProjectsOfRoot); AFiles the commands files
  read (ReadCommandsFiles). Reads the root's files; nothing runs. }
function DiscoverRepoCommands(const ARoot: string; out AProjects: TGittanProjects;
  out AFiles: TGittanCommandsFiles; const AChoice: string = ''): TGittanRepoCommands;
function DiscoverRepoCommands(const ARoot: string; out AProjects: TGittanProjects;
  const AChoice: string = ''): TGittanRepoCommands;
function DiscoverRepoCommands(const ARoot: string): TGittanRepoCommands;

{** The kinds of project at ARoot. AChoice, what the user picked on the
  Project page ("rust, go", "none"; '' for none picked), comes first;
  else a "project =" line of the commands file; else DetectProjects,
  the kinds whose Identify says so. A kind named that does not identify
  the root is listed with no manifest. }
function ProjectsOfRoot(const ARoot: string; const AChoice: string = ''): TGittanProjects;

{** The SHA-256 of the commands files' text, '' without one: a hash that
  cannot be collided, so trusted files cannot be swapped for others of
  the same hash. Each file's path goes in with its text, so a file added
  to .gittan/commands asks again. }
function CommandsHashOf(const AFiles: TGittanCommandsFiles): string;
function CommandsFileHash(const ARoot: string): string;

{** What a new commands.toml holds: an example with its lines commented
  out. }
function CommandsFileTemplate: string;

{** The index of the command with the key AKey in ACommands, -1 for
  none; a section without a command never matches. }
function CommandByKey(const ACommands: TGittanRepoCommands; AKey: char): integer;

{** The group of a command's name, for the page to list the commands
  that share one under a heading: AGroup is what comes before the first
  ":" (build for build:run, npm's way of naming), or before the first
  "-" for a Makefile target (build for build-linux; a target cannot have
  a colon), and AShort the rest. A name with no separator, or one that
  starts or ends with it, is a group of its own name with AShort the
  whole name, so build belongs with build:run and build:test. }
procedure SplitCommandName(const ACommand: TGittanRepoCommand; out AGroup, AShort: string);

type

  { TGittanCommandJob }

  {** Runs ACommand through the shell in ARoot. OnOutput is called in
    the main thread as the command writes (at most once per piece read,
    never after Stop), OnDone when it has ended. }
  TGittanCommandJob = class(TGittanJob)
  private
    FRoot, FCommand: string;
    FOutput: string;
    FLock: TRTLCriticalSection;
    FOutputPending, FKill: boolean;
    FStarted, FKilled: boolean;
    FExitCode: integer;
    FStartedAt, FEndedAt, FKilledAt: QWord;
    FForced: boolean;
    FOnOutput: TNotifyEvent;
    function GetOutput: string;
    function GetElapsedMs: int64;
    procedure AddOutput(const AChunk: string);
    procedure NotifyOutput;
    {$ifdef unix}
    procedure ForkChild(Sender: TObject);
    {$endif}
  protected
    procedure Execute; override;
    procedure Detach; override;
  public
    constructor Create(const ARoot, ACommand: string);
    destructor Destroy; override;
    {** Ends the command and what it started; OnDone follows as for an
      end of its own, with Killed set. One that is still running
      KillGraceMs later, as one that ignores SIGTERM, is ended by
      force. }
    procedure Kill;
    property Root: string read FRoot;
    property Command: string read FCommand;
    {** What the command has written so far, the newest OutputKeep
      bytes. }
    property Output: string read GetOutput;
    {** Whether the shell could be started. }
    property Started: boolean read FStarted;
    {** Whether Kill ended it. }
    property Killed: boolean read FKilled;
    {** The exit code once it has ended; -1 before and when it could
      not start. }
    property ExitCode: integer read FExitCode;
    {** How long it has run, or ran. }
    property ElapsedMs: int64 read GetElapsedMs;
    property OnOutput: TNotifyEvent read FOnOutput write FOnOutput;
  end;

implementation

uses
  {$ifdef unix}BaseUnix,{$endif}
  Process, fpjson, jsonparser, TOML.Types, TOML.Parser, gittan.git, gittan.textfile,
  gittan.sha256;

{ ---------------------------------------------------------------------------
  The commands file
  --------------------------------------------------------------------------- }

function KeyOf(const AValue: string): char;
var
  S: string;
begin
  S := UpperCase(Trim(AValue));
  if (Length(S) = 1) and (S[1] in ['A'..'Z', '0'..'9']) then
    Result := S[1]
  else
    Result := #0;
end;

{ The names of a project value: an array of strings, or one string of
  names split on commas and spaces; "none" left out. }
function ProjectNames(AValue: TTOMLValue): TStringArray;
var
  Item: TTOMLValue;
  Parts: TStringArray;
  S: string;
begin
  Result := nil;
  Parts := nil;
  if AValue is TTOMLString then
    Parts := AValue.AsString.Split([',', ' '], TStringSplitOptions.ExcludeEmpty)
  else if AValue is TTOMLArray then
    for Item in TTOMLArray(AValue).Items do
      if Item is TTOMLString then
      begin
        SetLength(Parts, Length(Parts) + 1);
        Parts[High(Parts)] := Trim(Item.AsString);
      end;
  for S in Parts do
    if (S <> '') and not SameText(S, 'none') then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := S;
    end;
end;

{ By the bytes of the names, so the order is the same on every system
  and in every locale. }
function CompareOrdinal(AList: TStringList; A, B: integer): integer;
begin
  Result := CompareStr(AList[A], AList[B]);
end;

{ The text read as TOML; nil with AError when it is not. }
function ReadTomlText(const AText: string; out AError: string): TTOMLTable;
begin
  AError := '';
  try
    Result := ParseTOMLString(AText);
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := nil;
    end;
  end;
end;

function CommandsSystem: string;
begin
  {$if defined(darwin)}
  Result := 'macos';
  {$elseif defined(windows)}
  Result := 'windows';
  {$elseif defined(linux)}
  Result := 'linux';
  {$elseif defined(freebsd)}
  Result := 'freebsd';
  {$elseif defined(haiku)}
  Result := 'haiku';
  {$else}
  Result := 'unix';
  {$endif}
end;

function CommandsSystemTitle: string;
begin
  case CommandsSystem of
    'macos': Result := 'macOS';
    'windows': Result := 'Windows';
    'linux': Result := 'Linux';
    'freebsd': Result := 'FreeBSD';
    'haiku': Result := 'Haiku';
    else
      Result := 'Unix';
  end;
end;

{ The line of a run table for ASystem: its own, else unix's on any
  system but Windows, else default's; '' with none. }
function RunLineFor(ATable: TTOMLTable; const ASystem: string): string;
var
  Field: TTOMLValue;
  Key: string;
  Keys: array[0..2] of string;
begin
  { Not an array constructor: FPC 3.2.2 gets a for-in over a
    constructor of strings wrong. }
  Keys[0] := ASystem;
  Keys[1] := 'unix';
  Keys[2] := 'default';
  for Key in Keys do
  begin
    if (Key = 'unix') and (ASystem = 'windows') then
      Continue;
    if ATable.TryGetValue(Key, Field) and (Field is TTOMLString) and
      (Trim(Field.AsString) <> '') then
      Exit(Field.AsString);
  end;
  Result := '';
end;

function ParseCommandsToml(const AText: string; out AError: string;
  const ASystem: string): TGittanRepoCommands;
var
  Doc, Table: TTOMLTable;
  Value, Field: TTOMLValue;
  Names: TStringList;
  Cmd: TGittanRepoCommand;
  Name, System: string;
begin
  Result := nil;
  System := LowerCase(ASystem);
  if System = '' then
    System := CommandsSystem;
  Doc := ReadTomlText(AText, AError);
  if Doc = nil then
    Exit;
  Names := TStringList.Create;
  try
    if not (Doc.TryGetValue('commands', Value) and (Value is TTOMLTable)) then
      Exit;
    Table := TTOMLTable(Value);
    for Name in Table.Items.Keys do
      Names.Add(Name);
    { By name, so the first of two that ask for one key is the same at
      every read. }
    Names.CustomSort(@CompareOrdinal);
    for Name in Names do
    begin
      Value := Table.Items[Name];
      if Name = '' then
        Continue;
      Cmd := Default(TGittanRepoCommand);
      Cmd.Name := Name;
      Cmd.Source := csFile;
      if Value is TTOMLString then
        Cmd.Command := Value.AsString
      else if Value is TTOMLTable then
      begin
        if TTOMLTable(Value).TryGetValue('run', Field) then
          if Field is TTOMLString then
            Cmd.Command := Field.AsString
          else if Field is TTOMLTable then
          begin
            Cmd.Command := RunLineFor(TTOMLTable(Field), System);
            Cmd.Elsewhere := Cmd.Command = '';
          end;
        if TTOMLTable(Value).TryGetValue('key', Field) then
          if Field is TTOMLString then
            Cmd.Key := KeyOf(Field.AsString)
          else if (Field is TTOMLInteger) and (Field.AsInteger >= 0) and (Field.AsInteger <= 9) then
            Cmd.Key := Chr(Ord('0') + Field.AsInteger);
        if TTOMLTable(Value).TryGetValue('terminal', Field) and (Field is TTOMLBoolean) then
          Cmd.Terminal := Field.AsBoolean;
        if TTOMLTable(Value).TryGetValue('description', Field) and (Field is TTOMLString) then
          Cmd.Description := Trim(Field.AsString);
        if TTOMLTable(Value).TryGetValue('confirm', Field) then
          if Field is TTOMLBoolean then
            Cmd.Confirm := Field.AsBoolean
          else if (Field is TTOMLString) and (Trim(Field.AsString) <> '') then
          begin
            Cmd.Confirm := True;
            Cmd.ConfirmText := Trim(Field.AsString);
          end;
        if TTOMLTable(Value).TryGetValue('hidden', Field) and (Field is TTOMLBoolean) then
          Cmd.Hidden := Field.AsBoolean;
      end
      else
        Continue;
      { A run line of blanks runs nothing: a table that gives a key. }
      if Trim(Cmd.Command) = '' then
        Cmd.Command := '';
      Cmd.Detail := Cmd.Command;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Cmd;
    end;
  finally
    Names.Free;
    Doc.Free;
  end;
end;

function ParseCommandsTomlProjects(const AText: string; out ANames: TStringArray): boolean;
var
  Doc: TTOMLTable;
  Value: TTOMLValue;
  Error: string;
begin
  ANames := nil;
  Result := False;
  Doc := ReadTomlText(AText, Error);
  if Doc = nil then
    Exit;
  try
    if Doc.TryGetValue('project', Value) then
      if (Value is TTOMLString) or (Value is TTOMLArray) then
      begin
        Result := True;
        ANames := ProjectNames(Value);
      end;
  finally
    Doc.Free;
  end;
end;

function ReadCommandsFiles(const ARoot: string): TGittanCommandsFiles;
var
  Root, Sub: string;
  Names: TStringList;
  Info: TSearchRec;
  i: integer;

  procedure AddFile(const APath: string; AMain: boolean);
  var
    F: TGittanCommandsFile;
    i: integer;
  begin
    F := Default(TGittanCommandsFile);
    F.Path := APath;
    { A file that cannot be read gives no commands and says why. }
    try
      F.Text := ReadFileBytes(Root + SetDirSeparators(APath));
      F.Commands := ParseCommandsToml(F.Text, F.Error);
    except
      on E: Exception do
      begin
        F.Text := '';
        F.Commands := nil;
        F.Error := E.Message;
      end;
    end;
    if AMain then
      F.HasProjects := ParseCommandsTomlProjects(F.Text, F.Projects);
    for i := 0 to High(F.Commands) do
      F.Commands[i].Project := APath;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := F;
  end;

begin
  Result := nil;
  if ARoot = '' then
    Exit;
  Root := IncludeTrailingPathDelimiter(ARoot);
  if FileExists(Root + CommandsFolder + PathDelim + CommandsFile) then
    AddFile(CommandsPath, True);
  Sub := Root + CommandsFolder + PathDelim + CommandsSubFolder + PathDelim;
  Names := TStringList.Create;
  try
    { Every name, as a mask is case-sensitive on Unix and CI.TOML would
      be found on Windows only; a hidden file (an editor's, macOS's ._)
      is left out. }
    if FindFirst(Sub + '*', faAnyFile, Info) = 0 then
      try
        repeat
          if (Info.Attr and faDirectory = 0) and (Info.Name[1] <> '.') and
            (LowerCase(ExtractFileExt(Info.Name)) = '.toml') then
            Names.Add(Info.Name);
        until FindNext(Info) <> 0;
      finally
        FindClose(Info);
      end;
    Names.CustomSort(@CompareOrdinal);
    for i := 0 to Names.Count - 1 do
      AddFile(CommandsFolder + '/' + CommandsSubFolder + '/' + Names[i], False);
  finally
    Names.Free;
  end;
end;

function CommandsFileTemplate: string;
begin
  Result :=
    '# Gittan runs these from the repository root: a table per command' + LineEnding +
    '# under [commands], with run the shell line, key one letter or digit' + LineEnding +
    '# for its shortcut (Ctrl+Cmd on macOS, Ctrl+Alt elsewhere),' + LineEnding +
    '# terminal = true for one that opens in a terminal, description a' + LineEnding +
    '# line for its hint, confirm = true (or a question) to ask before it' + LineEnding +
    '# runs and hidden = true to leave it off the page. run may be a line' + LineEnding +
    '# per system: run = { windows = "...", unix = "..." } (macos, linux' + LineEnding +
    '# and default too). A table named as' + LineEnding +
    '# a package.json script, a Makefile target or a command of the' + LineEnding +
    '# project''s tools (cargo test, go test) with no run line gives that' + LineEnding +
    '# one a key; a name with a colon is quoted, [commands."build:run"].' + LineEnding +
    '# Each .toml file in .gittan/commands/ adds a section of its own.' + LineEnding +
    '#' + LineEnding +
    '# project = ["rust", "go"] before the first table keeps the kinds of' + LineEnding +
    '# project to those named; project = "none" lists none.' + LineEnding +
    '#' + LineEnding +
    '# [commands.test]' + LineEnding +
    '# run = "npm test"' + LineEnding +
    '# key = "T"' + LineEnding +
    '# description = "The unit tests"' + LineEnding +
    '#' + LineEnding +
    '# [commands.dev]' + LineEnding +
    '# run = "npm run dev"' + LineEnding +
    '# terminal = true' + LineEnding +
    '#' + LineEnding +
    '# [commands.clean]' + LineEnding +
    '# run = { windows = "rmdir /s /q build", unix = "rm -rf build" }' + LineEnding +
    '# confirm = "Remove the build folder?"' + LineEnding;
end;

{ ---------------------------------------------------------------------------
  package.json and the Makefile
  --------------------------------------------------------------------------- }

function ParsePackageScripts(const AJson: string): TGittanRepoCommands;
var
  Data: TJSONData;
  Scripts: TJSONData;
  i: integer;
begin
  Result := nil;
  if Trim(AJson) = '' then
    Exit;
  try
    Data := GetJSON(AJson);
  except
    Exit;
  end;
  try
    if not (Data is TJSONObject) then
      Exit;
    Scripts := TJSONObject(Data).Find('scripts');
    if not (Scripts is TJSONObject) then
      Exit;
    for i := 0 to TJSONObject(Scripts).Count - 1 do
      if TJSONObject(Scripts).Items[i].JSONType = jtString then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Default(TGittanRepoCommand);
        Result[High(Result)].Name := TJSONObject(Scripts).Names[i];
        Result[High(Result)].Detail := TJSONObject(Scripts).Items[i].AsString;
        Result[High(Result)].Source := csPackage;
      end;
  finally
    Data.Free;
  end;
end;

{ A plain target name: letters, digits, "_", "-" and "." after the first
  character, which is not a ".". }
function PlainTarget(const AName: string): boolean;
var
  i: integer;
begin
  if (AName = '') or (AName[1] = '.') then
    Exit(False);
  for i := 1 to Length(AName) do
    if not (AName[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', '+']) then
      Exit(False);
  Result := True;
end;

function ParseMakefileTargets(const AText: string): TStringArray;
var
  Start, P, i: integer;
  Line, Head, Name: string;
  Names: TStringArray;
  Seen: TStringList;

  procedure AddTarget(const ATarget: string);
  begin
    if Seen.IndexOf(ATarget) >= 0 then
      Exit;
    Seen.Add(ATarget);
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := ATarget;
  end;

begin
  Result := nil;
  Seen := TStringList.Create;
  try
    Seen.CaseSensitive := True;
    Start := 1;
    while NextLine(AText, Start, Line) do
    begin
      if (Line = '') or (Line[1] in [#9, ' ', '#']) then
        Continue;
      P := Pos(':', Line);
      if P < 2 then
        Continue;
      { "::" is a double-colon rule; ":=" an assignment. }
      if (P < Length(Line)) and (Line[P + 1] = '=') then
        Continue;
      Head := Trim(Copy(Line, 1, P - 1));
      if Head = '' then
        Continue;
      Names := Head.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
      for i := 0 to High(Names) do
        if not PlainTarget(Names[i]) then
        begin
          Names := nil;
          Break;
        end;
      for Name in Names do
        AddTarget(Name);
    end;
  finally
    Seen.Free;
  end;
end;

function PackageRunner(const ARoot: string): string;
var
  Root: string;
begin
  Root := IncludeTrailingPathDelimiter(ARoot);
  if FileExists(Root + 'pnpm-lock.yaml') then
    Result := 'pnpm run'
  else if FileExists(Root + 'yarn.lock') then
    Result := 'yarn run'
  else if FileExists(Root + 'bun.lockb') or FileExists(Root + 'bun.lock') then
    Result := 'bun run'
  else
    Result := 'npm run';
end;

function ReadIfExists(const AFileName: string): string;
begin
  if FileExists(AFileName) then
    Result := ReadFileBytes(AFileName)
  else
    Result := '';
end;

function CommandByKey(const ACommands: TGittanRepoCommands; AKey: char): integer;
var
  i: integer;
begin
  for i := 0 to High(ACommands) do
    if (AKey <> #0) and (ACommands[i].Key = AKey) and (ACommands[i].Command <> '') then
      Exit(i);
  Result := -1;
end;

procedure SplitCommandName(const ACommand: TGittanRepoCommand; out AGroup, AShort: string);
var
  Sep: char;
  p: integer;
begin
  if ACommand.Source = csMake then
    Sep := '-'
  else
    Sep := ':';
  p := Pos(Sep, ACommand.Name);
  if (p > 1) and (p < Length(ACommand.Name)) then
  begin
    AGroup := Copy(ACommand.Name, 1, p - 1);
    AShort := Copy(ACommand.Name, p + 1, MaxInt);
  end
  else
  begin
    AGroup := ACommand.Name;
    AShort := ACommand.Name;
  end;
end;

{ ProjectsOfRoot with the commands files read: the first one's project
  line. }
function ProjectsOfFiles(const ARoot: string; const AFiles: TGittanCommandsFiles;
  const AChoice: string): TGittanProjects;
begin
  if Trim(AChoice) <> '' then
    Exit(ProjectsNamed(ARoot, SplitProjectChoice(AChoice)));
  if (Length(AFiles) > 0) and AFiles[0].HasProjects then
    Exit(ProjectsNamed(ARoot, AFiles[0].Projects));
  Result := DetectProjects(ARoot);
end;

function ProjectsOfRoot(const ARoot: string; const AChoice: string): TGittanProjects;
begin
  if Trim(AChoice) <> '' then
    Result := ProjectsNamed(ARoot, SplitProjectChoice(AChoice))
  else
    Result := ProjectsOfFiles(ARoot, ReadCommandsFiles(ARoot), '');
end;

function DiscoverRepoCommands(const ARoot: string): TGittanRepoCommands;
var
  Projects: TGittanProjects;
  Files: TGittanCommandsFiles;
begin
  Result := DiscoverRepoCommands(ARoot, Projects, Files);
end;

function DiscoverRepoCommands(const ARoot: string; out AProjects: TGittanProjects;
  const AChoice: string): TGittanRepoCommands;
var
  Files: TGittanCommandsFiles;
begin
  Result := DiscoverRepoCommands(ARoot, AProjects, Files, AChoice);
end;

function DiscoverRepoCommands(const ARoot: string; out AProjects: TGittanProjects;
  out AFiles: TGittanCommandsFiles; const AChoice: string): TGittanRepoCommands;
const
  { A typed array, not an array constructor: FPC 3.2.2 gets a for-in
    over a constructor of strings wrong. }
  MakefileNames: array[0..2] of string = ('Makefile', 'makefile', 'GNUmakefile');
var
  Root, Runner, Name: string;
  FileOnes, Scripts, Targets, Kinds: TGittanRepoCommands;
  TargetNames: TStringArray;
  KindOnes: TGittanProjectCommands;
  Taken: array of boolean;
  i, j, n: integer;
  Used: set of char;
  F: TGittanCommandsFile;

  { A file section without a command line that names ACommand gives it
    the key, the terminal flag, the description, the question and
    whether it is hidden, and is taken by it. One whose run lines are
    for other systems is a command of its own. }
  procedure TakeFromFile(var ACommand: TGittanRepoCommand);
  var
    k: integer;
  begin
    for k := 0 to High(FileOnes) do
      if (FileOnes[k].Command = '') and not FileOnes[k].Elsewhere and
        (FileOnes[k].Name = ACommand.Name) then
      begin
        ACommand.Key := FileOnes[k].Key;
        ACommand.Terminal := FileOnes[k].Terminal;
        if FileOnes[k].Description <> '' then
          ACommand.Description := FileOnes[k].Description;
        ACommand.Confirm := FileOnes[k].Confirm;
        ACommand.ConfirmText := FileOnes[k].ConfirmText;
        ACommand.Hidden := FileOnes[k].Hidden;
        Taken[k] := True;
        Exit;
      end;
  end;

  { The command line of the script, target or kind's command named
    AName, '' for none. }
  function LineNamed(const AName: string): string;
  var
    k: integer;
  begin
    for k := 0 to High(Scripts) do
      if Scripts[k].Name = AName then
        Exit(Scripts[k].Command);
    for k := 0 to High(Targets) do
      if Targets[k].Name = AName then
        Exit(Targets[k].Command);
    for k := 0 to High(Kinds) do
      if Kinds[k].Name = AName then
        Exit(Kinds[k].Command);
    Result := '';
  end;

  procedure Add(const ACommand: TGittanRepoCommand);
  begin
    { A hidden one is not listed and its key runs nothing; a hidden
      section that names nothing is still shown, as a misspelling. }
    if ACommand.Hidden and ((ACommand.Command <> '') or ACommand.Elsewhere) then
      Exit;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := ACommand;
  end;

begin
  Result := nil;
  AProjects := nil;
  AFiles := nil;
  if ARoot = '' then
    Exit;
  Root := IncludeTrailingPathDelimiter(ARoot);
  AFiles := ReadCommandsFiles(ARoot);
  FileOnes := nil;
  for F in AFiles do
    for i := 0 to High(F.Commands) do
    begin
      SetLength(FileOnes, Length(FileOnes) + 1);
      FileOnes[High(FileOnes)] := F.Commands[i];
    end;
  SetLength(Taken, Length(FileOnes));
  Scripts := ParsePackageScripts(ReadIfExists(Root + 'package.json'));
  if Length(Scripts) > 0 then
  begin
    Runner := PackageRunner(ARoot);
    for i := 0 to High(Scripts) do
    begin
      Scripts[i].Command := Runner + ' ' + Scripts[i].Name;
      TakeFromFile(Scripts[i]);
    end;
  end;
  TargetNames := nil;
  for Name in MakefileNames do
    if FileExists(Root + Name) then
    begin
      TargetNames := ParseMakefileTargets(ReadFileBytes(Root + Name));
      Break;
    end;
  SetLength(Targets, Length(TargetNames));
  for i := 0 to High(TargetNames) do
  begin
    Targets[i] := Default(TGittanRepoCommand);
    Targets[i].Name := TargetNames[i];
    Targets[i].Command := 'make ' + TargetNames[i];
    Targets[i].Source := csMake;
    TakeFromFile(Targets[i]);
  end;
  { Each kind of project's commands, under the kind's name. }
  Kinds := nil;
  AProjects := ProjectsOfFiles(ARoot, AFiles, AChoice);
  for j := 0 to High(AProjects) do
  begin
    KindOnes := AProjects[j].Kind.Commands(ARoot);
    for i := 0 to High(KindOnes) do
    begin
      SetLength(Kinds, Length(Kinds) + 1);
      Kinds[High(Kinds)] := Default(TGittanRepoCommand);
      Kinds[High(Kinds)].Name := KindOnes[i].Name;
      Kinds[High(Kinds)].Command := KindOnes[i].Command;
      Kinds[High(Kinds)].Terminal := KindOnes[i].Terminal;
      Kinds[High(Kinds)].Source := csProject;
      Kinds[High(Kinds)].Project := AProjects[j].Name;
      TakeFromFile(Kinds[High(Kinds)]);
    end;
  end;
  { A section left over that names what an earlier file's section took
    says so, rather than naming nothing. }
  for i := 0 to High(FileOnes) do
    if not Taken[i] and (FileOnes[i].Command = '') and not FileOnes[i].Elsewhere then
      FileOnes[i].Overlaps := LineNamed(FileOnes[i].Name);
  { The file's own commands, in its order, with a section that names
    no script or target among them, without a command: the page shows
    it as such, so a misspelt or dropped name is seen. }
  for i := 0 to High(FileOnes) do
    if (FileOnes[i].Command <> '') or not Taken[i] then
      Add(FileOnes[i]);
  for i := 0 to High(Scripts) do
    Add(Scripts[i]);
  for i := 0 to High(Targets) do
    Add(Targets[i]);
  for i := 0 to High(Kinds) do
    Add(Kinds[i]);
  { The first command with a key keeps it; a section without a command
    holds none. }
  Used := [];
  n := 0;
  for j := 0 to High(Result) do
    if (Result[j].Key <> #0) and (Result[j].Command <> '') then
      if Result[j].Key in Used then
        Result[j].Key := #0
      else
      begin
        Include(Used, Result[j].Key);
        Inc(n);
      end;
end;

function CommandsHashOf(const AFiles: TGittanCommandsFiles): string;
var
  F: TGittanCommandsFile;
  All: string;
begin
  if Length(AFiles) = 0 then
    Exit('');
  { The path and the text's length before each text, so no two sets of
    files join to the same string. }
  All := '';
  for F in AFiles do
    All := All + F.Path + #0 + IntToStr(Length(F.Text)) + #0 + F.Text;
  Result := SHA256Print(SHA256String(All));
end;

function CommandsFileHash(const ARoot: string): string;
begin
  Result := CommandsHashOf(ReadCommandsFiles(ARoot));
end;

{ ---------------------------------------------------------------------------
  Running a command
  --------------------------------------------------------------------------- }

constructor TGittanCommandJob.Create(const ARoot, ACommand: string);
begin
  inherited Create(False);
  FRoot := ARoot;
  FCommand := ACommand;
  FExitCode := -1;
  InitCriticalSection(FLock);
end;

destructor TGittanCommandJob.Destroy;
begin
  { Stop waits for the thread, which uses the lock. }
  inherited Destroy;
  DoneCriticalSection(FLock);
end;

function TGittanCommandJob.GetOutput: string;
begin
  EnterCriticalSection(FLock);
  try
    Result := FOutput;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TGittanCommandJob.GetElapsedMs: int64;
begin
  if FStartedAt = 0 then
    Result := 0
  else if FEndedAt = 0 then
    Result := GetTickCount64 - FStartedAt
  else
    Result := FEndedAt - FStartedAt;
end;

{ The thread adds what was read, keeping the newest OutputKeep bytes,
  and queues one notification while none is pending. }
procedure TGittanCommandJob.AddOutput(const AChunk: string);
var
  Tell: boolean;
begin
  EnterCriticalSection(FLock);
  try
    FOutput := FOutput + AChunk;
    if Length(FOutput) > OutputKeep then
      FOutput := Copy(FOutput, Length(FOutput) - OutputKeep + 1, OutputKeep);
    Tell := not FOutputPending;
    FOutputPending := True;
  finally
    LeaveCriticalSection(FLock);
  end;
  if Tell then
    Queue(@NotifyOutput);
end;

procedure TGittanCommandJob.NotifyOutput;
begin
  EnterCriticalSection(FLock);
  FOutputPending := False;
  LeaveCriticalSection(FLock);
  if Assigned(FOnOutput) then
    FOnOutput(Self);
end;

{ OnOutput goes with OnDone: no output is told after Stop. }
procedure TGittanCommandJob.Detach;
begin
  inherited Detach;
  FOnOutput := nil;
end;

procedure TGittanCommandJob.Kill;
begin
  FKill := True;
end;

{$ifdef unix}
{ In the child, before the shell starts: a session of its own, so the
  shell and what it starts are a process group that EndProcess ends
  together. }
procedure TGittanCommandJob.ForkChild(Sender: TObject);
begin
  FpSetsid;
end;
{$endif}

{ AForce, on Unix, sends SIGKILL, which a command cannot ignore. }
procedure EndProcess(P: TProcess; AForce: boolean);
{$ifdef unix}
var
  Signal: cint;
{$else}
var
  Output: string;
{$endif}
begin
  {$ifdef unix}
  { The group is not there yet when the child has not reached setsid. }
  if AForce then
    Signal := SIGKILL
  else
    Signal := SIGTERM;
  if FpKill(-P.ProcessID, Signal) <> 0 then
    FpKill(P.ProcessID, Signal);
  {$else}
  { cmd.exe's children (node under npm) go with it. }
  RunCommand('taskkill', ['/PID', IntToStr(P.ProcessID), '/T', '/F'], Output,
    [poNoConsole, poUsePipes]);
  {$endif}
end;

{ Whether the process group of a command that was killed still has
  members once the shell has gone: a child that ignores SIGTERM outlives
  a shell that does not. taskkill /F leaves none on Windows. }
function GroupLives(P: TProcess): boolean;
begin
  {$ifdef unix}
  Result := FpKill(-P.ProcessID, 0) = 0;
  {$else}
  Result := False;
  {$endif}
end;

procedure TGittanCommandJob.Execute;
var
  P: TProcess;
  Env, Shell: string;
  Chunk: string;
  N: longint;
begin
  Chunk := '';
  FStartedAt := GetTickCount64;
  P := TProcess.Create(nil);
  try
    {$ifdef windows}
    Shell := EnvironmentVariable('ComSpec');
    if Shell = '' then
      Shell := 'cmd.exe';
    P.Executable := Shell;
    P.Parameters.Add('/c');
    P.Parameters.Add(ProcessArg(FCommand));
    {$else}
    Shell := EnvironmentVariable('SHELL');
    if (Shell = '') or not FileExists(Shell) then
      Shell := '/bin/sh';
    P.Executable := Shell;
    P.Parameters.Add('-l');
    P.Parameters.Add('-c');
    P.Parameters.Add(FCommand);
    {$endif}
    P.CurrentDirectory := FRoot;
    { Gittan's environment, with the PATH a terminal would have outside
      Windows, and the colors a terminal would get. }
    for Env in EnvironmentStrings do
    begin
      {$ifndef windows}
      if Copy(Env, 1, 5) = 'PATH=' then
        Continue;
      {$endif}
      if (Copy(Env, 1, 12) = 'FORCE_COLOR=') or (Copy(Env, 1, 15) = 'CLICOLOR_FORCE=') then
        Continue;
      P.Environment.Add(Env);
    end;
    {$ifndef windows}
    P.Environment.Add('PATH=' + ToolSearchPath);
    if EnvironmentVariable('TERM') = '' then
      P.Environment.Add('TERM=xterm-256color');
    {$endif}
    P.Environment.Add('FORCE_COLOR=1');
    P.Environment.Add('CLICOLOR_FORCE=1');
    P.Options := [poNoConsole, poUsePipes, poStderrToOutPut];
    {$ifdef unix}
    P.OnForkEvent := @ForkChild;
    {$endif}
    try
      P.Execute;
      FStarted := True;
    except
      on E: Exception do
      begin
        AddOutput(E.Message + LineEnding);
        FEndedAt := GetTickCount64;
        Done;
        Exit;
      end;
    end;
    { Nothing is written to the command: one that reads its input would
      otherwise wait for ever. }
    P.CloseInput;
    repeat
      { Asked on every pass: a command that writes all the time would
        otherwise never be ended. }
      if FKill and not FKilled and P.Running then
      begin
        FKilled := True;
        FKilledAt := GetTickCount64;
        EndProcess(P, False);
      end
      else if FKilled and not FForced and
        (GetTickCount64 - FKilledAt >= KillGraceMs) and
        (P.Running or GroupLives(P)) then
      begin
        FForced := True;
        EndProcess(P, True);
      end;
      N := P.Output.NumBytesAvailable;
      if N > 0 then
      begin
        SetLength(Chunk, N);
        N := P.Output.Read(Chunk[1], N);
        if N > 0 then
        begin
          SetLength(Chunk, N);
          AddOutput(Chunk);
        end;
      end
      else if P.Running or (FKilled and not FForced and GroupLives(P)) then
        Sleep(30)
      else
        Break;
    until False;
    { ExitStatus is the raw wait status on Unix; ExitCode the code. }
    FExitCode := P.ExitCode;
    FEndedAt := GetTickCount64;
  finally
    P.Free;
  end;
  Done;
end;

end.
