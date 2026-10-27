unit gittan.repocommands;

{** The commands of a repository: what the Commands page lists as
  buttons and runs from the repository's root. They come from three
  places: .gittan/commands.ini, written by hand and committed, where a
  section names a command, its shell line, a key for its shortcut and
  whether it runs in a terminal; the scripts of a package.json, each
  run through the package manager the lock file tells (npm, pnpm, yarn
  or bun); and the targets of a Makefile, each run by make. A section
  of the file with no command line and the name of a script or a target
  gives that one its key, so a repository can give its own make test a
  shortcut without writing it again. Nothing here needs the LCL; tested
  in tests/testrepocommands.pp.

  A committed file lets a clone say what a key does on this computer,
  so the file's commands run only once the user has trusted it:
  CommandsFileHash names the file's content, which the settings keep for
  the roots trusted, and a change of the file asks again.

  TGittanCommandJob runs a command in a thread through the user's shell
  (a login shell, so the PATH is the terminal's) with its output read as
  it writes, told to the main thread, and its exit code at the end;
  Kill ends it and what it started, forced when it has not ended
  KillGraceMs later. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.job;

const
  {** The folder of the repository's own Gittan files, at the root. }
  CommandsFolder = '.gittan';
  {** The commands file inside it. }
  CommandsFile = 'commands.ini';
  {** The file as a path relative to the root, with "/". }
  CommandsPath = CommandsFolder + '/' + CommandsFile;
  {** How much of a command's output the job keeps: the newest bytes. }
  OutputKeep = 1024 * 1024;
  {** How long a command may take to end after Kill before it is made
    to: SIGKILL where Kill sent SIGTERM. }
  KillGraceMs = 3000;

type
  {** Where a command comes from: the commands file, package.json, a
    Makefile. }
  TGittanCommandSource = (csFile, csPackage, csMake);

  TGittanRepoCommand = record
    {** The section's name, the script's or the target's. }
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
    Source: TGittanCommandSource;
  end;
  TGittanRepoCommands = array of TGittanRepoCommand;

{** The commands of the commands file's text: a [name] section per
  command with command =, key = and terminal = lines; ";" and "#" start
  a comment. A section without a command line has an empty Command and
  stands for a script's or a target's key. Keys are kept as capitals;
  anything but a letter or a digit is no key. }
function ParseCommandsFile(const AText: string): TGittanRepoCommands;

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

{** The commands of the repository at ARoot: the file's first, then the
  scripts, then the targets, with the keys the file gives them. A file
  section with no command line that names no script or target is kept
  among the file's, with an empty Command, so the page can say so.
  Reads the three files; nothing runs. }
function DiscoverRepoCommands(const ARoot: string): TGittanRepoCommands;

{** The SHA-256 of the commands file's text under ARoot, '' without the
  file: a hash that cannot be collided, so a trusted file cannot be
  swapped for another of the same hash. }
function CommandsFileHash(const ARoot: string): string;

{** What a new commands file holds: an example with its lines commented
  out. }
function CommandsFileTemplate: string;

{** The index of the command with the key AKey in ACommands, -1 for
  none; a section without a command never matches. }
function CommandByKey(const ACommands: TGittanRepoCommands; AKey: char): integer;

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
  Process, fpjson, jsonparser, gittan.git, gittan.textfile, gittan.sha256;

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

function IsTrue(const AValue: string): boolean;
var
  S: string;
begin
  S := LowerCase(Trim(AValue));
  Result := (S = 'true') or (S = 'yes') or (S = '1') or (S = 'on');
end;

function ParseCommandsFile(const AText: string): TGittanRepoCommands;
var
  Start, P: integer;
  Line, Name, Field, Value: string;
  InSection: boolean;
begin
  Result := nil;
  Start := 1;
  InSection := False;
  while NextLine(AText, Start, Line) do
  begin
    Line := Trim(Line);
    if (Line = '') or (Line[1] = ';') or (Line[1] = '#') then
      Continue;
    if Line[1] = '[' then
    begin
      P := Pos(']', Line);
      if P < 2 then
        Continue;
      Name := Trim(Copy(Line, 2, P - 2));
      if Name = '' then
        Continue;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Default(TGittanRepoCommand);
      Result[High(Result)].Name := Name;
      Result[High(Result)].Source := csFile;
      InSection := True;
      Continue;
    end;
    if not InSection then
      Continue;
    P := Pos('=', Line);
    if P = 0 then
      Continue;
    Field := LowerCase(Trim(Copy(Line, 1, P - 1)));
    Value := Trim(Copy(Line, P + 1, MaxInt));
    if Field = 'command' then
    begin
      Result[High(Result)].Command := Value;
      Result[High(Result)].Detail := Value;
    end
    else if Field = 'key' then
      Result[High(Result)].Key := KeyOf(Value)
    else if Field = 'terminal' then
      Result[High(Result)].Terminal := IsTrue(Value);
  end;
end;

function CommandsFileTemplate: string;
begin
  Result :=
    '; Gittan runs these from the repository root: a section per command,' + LineEnding +
    '; with a key for its shortcut (Ctrl+Cmd on macOS, Ctrl+Alt elsewhere).' + LineEnding +
    '; A section named as a package.json script or a Makefile target with' + LineEnding +
    '; no command line gives that one a key.' + LineEnding +
    ';' + LineEnding +
    '; [test]' + LineEnding +
    '; command = npm test' + LineEnding +
    '; key = T' + LineEnding +
    ';' + LineEnding +
    '; [dev]' + LineEnding +
    '; command = npm run dev' + LineEnding +
    '; terminal = true' + LineEnding;
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

function DiscoverRepoCommands(const ARoot: string): TGittanRepoCommands;
var
  Root, Runner, Name: string;
  FileOnes, Scripts, Targets: TGittanRepoCommands;
  TargetNames: TStringArray;
  Taken: array of boolean;
  i, j, n: integer;
  Used: set of char;

  { A file section without a command line that names ACommand gives it
    the key and the terminal flag, and is taken by it. }
  procedure TakeFromFile(var ACommand: TGittanRepoCommand);
  var
    k: integer;
  begin
    for k := 0 to High(FileOnes) do
      if (FileOnes[k].Command = '') and (FileOnes[k].Name = ACommand.Name) then
      begin
        ACommand.Key := FileOnes[k].Key;
        ACommand.Terminal := FileOnes[k].Terminal;
        Taken[k] := True;
        Exit;
      end;
  end;

  procedure Add(const ACommand: TGittanRepoCommand);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := ACommand;
  end;

begin
  Result := nil;
  if ARoot = '' then
    Exit;
  Root := IncludeTrailingPathDelimiter(ARoot);
  FileOnes := ParseCommandsFile(ReadIfExists(Root + CommandsFolder + PathDelim + CommandsFile));
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
  for Name in ['Makefile', 'makefile', 'GNUmakefile'] do
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

function CommandsFileHash(const ARoot: string): string;
var
  Name: string;
begin
  Name := IncludeTrailingPathDelimiter(ARoot) + CommandsFolder + PathDelim + CommandsFile;
  if (ARoot = '') or not FileExists(Name) then
    Result := ''
  else
    Result := SHA256Print(SHA256String(ReadFileBytes(Name)));
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
      else if FKilled and not FForced and P.Running and
        (GetTickCount64 - FKilledAt >= KillGraceMs) then
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
      else if P.Running then
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
