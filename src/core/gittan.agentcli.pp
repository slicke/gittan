unit gittan.agentcli;

{** The agents that are command line tools, Claude Code's claude and
  GitHub Copilot's copilot (TGittanClaude, TGittanCopilot, registered
  with gittan.ai as this unit loads), run without a session in the
  repository root (RunAgentCli in gittan.git) with the task's prompt
  and input, read-only tools and no terminal, so they work with the
  user's own login, plan and settings and read the repository's own
  instructions. Each tool has its own arguments (Args), where the
  prompt and the input go (Input) and how its answer is read
  (ReadAnswer): claude in print mode with JSON output
  (ParseClaudeResult), copilot silent with its answer as its whole
  output. A tool that is told to stop is ended (ACancel), so a job
  given up does not wait for its answer. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.git, gittan.ai;

const
  {** The most turns claude may take for a commit message, each a read
    of a file or the answer. Copilot has no such limit. }
  MessageMaxTurns = 10;
  {** The most turns claude may take for a review, which reads files to
    check what it finds. }
  ReviewMaxTurns = 20;
  {** The most turns claude may take to find where something is, each a
    search or a read. }
  FindMaxTurns = 20;
  {** The most turns claude may take for each task; the second round of
    a find (atLocate) is never a tool's, and has the find's for the
    array's sake. }
  TaskTurns: array[TGittanAITask] of integer = (MessageMaxTurns, ReviewMaxTurns,
    FindMaxTurns, FindMaxTurns);

type
  {** A tool: Path is its command, Model the model it runs with (empty
    for its own choice), Key unused. It reads the repository's files
    itself. }
  TGittanAgentCli = class(TGittanAI)
  public
    class function ReadsFiles: boolean; override;
    {** ASetting, else the command (AgentCommands) found on
      ToolSearchPath. }
    class function Find(const ASetting: string): string; override;
    {** The arguments the command runs with for ATask. }
    function Args(ATask: TGittanAITask): TStringArray; virtual; abstract;
    {** What the command gets on its input for ATask and AInput (the
      changes, the question). }
    function Input(ATask: TGittanAITask; const AInput: string): string; virtual; abstract;
    {** The answer in AText from what the command printed (AOutput on
      standard output, AErrors on standard error) and whether it exited
      with 0 (AExited); else False with the reason in AError: the tool's
      own, what it wrote on standard error, or that it gave no answer. }
    function ReadAnswer(AExited: boolean; const AOutput, AErrors: string;
      out AText, AError: string): boolean; virtual;
    {** Runs the command in ARoot with Args and Input and reads its
      answer (ReadAnswer). }
    function Ask(const ARoot: string; ATask: TGittanAITask; const AInput: string;
      ACancel: TGittanCancelEvent; out AText, AError: string): boolean; override;
    {** The name and the version the command prints for --version
      (VersionOf), empty when it printed none or there is no command. }
    function About: string; override;
  end;

  {** Claude Code: claude -p with the prompt, JSON output, read-only
    tools (Read, Grep, Glob), no session kept and at most TaskTurns
    turns, --model when one is set; the input is the changes alone.
    Its JSON says why when it failed, whatever the exit (claude exits
    with 1 then). Found where its own installer put it too,
    ~/.claude/local/claude of earlier versions. }
  TGittanClaude = class(TGittanAgentCli)
  public
    class function Kind: TGittanAgent; override;
    class function Find(const ASetting: string): string; override;
    function Args(ATask: TGittanAITask): TStringArray; override;
    function Input(ATask: TGittanAITask; const AInput: string): string; override;
    function ReadAnswer(AExited: boolean; const AOutput, AErrors: string;
      out AText, AError: string): boolean; override;
  end;

  {** GitHub Copilot: copilot silent, without color or streaming, asking
    nothing, with the read-only tools view, grep and glob allowed (a run
    without a terminal needs --allow-all-tools, which the three make
    safe), --model= when one is set. It ignores its input when -p is
    given, so the prompt goes on the input before the changes. Its
    answer is its whole output, which counts when it exited with 0. }
  TGittanCopilot = class(TGittanAgentCli)
  public
    class function Kind: TGittanAgent; override;
    function Args(ATask: TGittanAITask): TStringArray; override;
    function Input(ATask: TGittanAITask; const AInput: string): string; override;
    function ReadAnswer(AExited: boolean; const AOutput, AErrors: string;
      out AText, AError: string): boolean; override;
  end;

{** Reads what claude -p --output-format json printed: the answer in
  AText, or why there is none in AError (claude's own error, or the turn
  limit). False when AOutput is no such answer. }
function ParseClaudeResult(const AOutput: string; out AText, AError: string): boolean;

{** The first word of a tool's first line after APrefix ("gh version
  2.62.0 (2024-11-14)" gives 2.62.0 for "gh version", claude's "2.1.0
  (Claude Code)" 2.1.0). }
function VersionOf(const AOutput, APrefix: string): string;

resourcestring
  rsClaudeTurns = 'Claude Code stopped after %d turns without an answer.';
  rsClaudeTurnLimit = 'Claude Code stopped at its turn limit without an answer.';

implementation

uses
  fpjson, jsonparser;

function ParseClaudeResult(const AOutput: string; out AText, AError: string): boolean;
var
  Data: TJSONData;
  Obj: TJSONObject;
  Start: integer;
begin
  AText := '';
  AError := '';
  { A warning may come before the answer; the answer is the last line
    that starts an object. }
  Start := Length(AOutput);
  while (Start > 0) and not ((AOutput[Start] = '{') and ((Start = 1) or
      (AOutput[Start - 1] in [#10, #13]))) do
    Dec(Start);
  if Start = 0 then
    Exit(False);
  try
    Data := GetJSON(Copy(AOutput, Start, MaxInt));
  except
    Exit(False);
  end;
  try
    if not (Data is TJSONObject) then
      Exit(False);
    Obj := TJSONObject(Data);
    if Obj.Get('type', '') <> 'result' then
      Exit(False);
    Result := True;
    AText := Obj.Get('result', '');
    if Obj.Get('is_error', False) or (Obj.Get('subtype', 'success') <> 'success') then
    begin
      if Obj.Get('subtype', '') = 'error_max_turns' then
      begin
        if Obj.Find('num_turns') is TJSONNumber then
          AError := Format(rsClaudeTurns, [Obj.Get('num_turns', 0)])
        else
          AError := rsClaudeTurnLimit;
      end
      else if Trim(AText) <> '' then
        AError := Trim(AText)
      else
        AError := Obj.Get('subtype', Format(rsAgentNoAnswer, [AgentNames[gaClaude]]));
      AText := '';
    end
    else if Trim(AText) = '' then
      AError := Format(rsAgentNoAnswer, [AgentNames[gaClaude]]);
  finally
    Data.Free;
  end;
end;

function VersionOf(const AOutput, APrefix: string): string;
var
  Line: string;
  i: integer;
begin
  Line := Trim(AOutput);
  i := Pos(LineEnding, Line);
  if i > 0 then
    Line := Copy(Line, 1, i - 1);
  if Pos(APrefix, Line) = 1 then
    Delete(Line, 1, Length(APrefix));
  Line := Trim(Line);
  i := Pos(' ', Line);
  if i > 0 then
    Line := Copy(Line, 1, i - 1);
  Result := Line;
end;

{ TGittanAgentCli }

class function TGittanAgentCli.ReadsFiles: boolean;
begin
  Result := True;
end;

class function TGittanAgentCli.Find(const ASetting: string): string;
begin
  Result := ASetting;
  if Result = '' then
    Result := FindTool(AgentCommands[Kind]);
end;

function TGittanAgentCli.ReadAnswer(AExited: boolean; const AOutput, AErrors: string;
  out AText, AError: string): boolean;
begin
  { No answer: stderr says why (not logged in, an unknown option of an
    old version), else whatever was printed. }
  AText := '';
  Result := False;
  if Trim(AErrors) <> '' then
    AError := Trim(AErrors)
  else if Trim(AOutput) <> '' then
    AError := Trim(AOutput)
  else
    AError := Format(rsAgentNoAnswer, [Name]);
end;

function TGittanAgentCli.Ask(const ARoot: string; ATask: TGittanAITask;
  const AInput: string; ACancel: TGittanCancelEvent; out AText, AError: string): boolean;
var
  Output, Errors: string;
  Exited: boolean;
begin
  Exited := RunAgentCli(Path, ARoot, Args(ATask), Input(ATask, AInput), ACancel,
    Output, Errors);
  Result := ReadAnswer(Exited, Output, Errors, AText, AError);
end;

function TGittanAgentCli.About: string;
var
  Output, Error, Version: string;
begin
  Result := '';
  if (Path = '') or not RunAgentCli(Path, GetUserDir, ['--version'], '', nil, Output,
      Error) then
    Exit;
  Version := VersionOf(Output, '');
  if Version <> '' then
    Result := Name + ' ' + Version;
end;

{ TGittanClaude }

class function TGittanClaude.Kind: TGittanAgent;
begin
  Result := gaClaude;
end;

class function TGittanClaude.Find(const ASetting: string): string;
var
  Local: string;
begin
  Result := inherited Find(ASetting);
  if Result <> '' then
    Exit;
  Local := IncludeTrailingPathDelimiter(GetUserDir) + '.claude' + PathDelim + 'local' +
    PathDelim + 'claude';
  {$ifdef windows}
  Local := Local + '.exe';
  {$endif}
  if FileExists(Local) then
    Result := Local;
end;

function TGittanClaude.Args(ATask: TGittanAITask): TStringArray;
begin
  Result := ['-p', Prompt(ATask), '--output-format', 'json', '--tools', 'Read,Grep,Glob',
    '--no-session-persistence', '--max-turns', IntToStr(TaskTurns[ATask])];
  if Model <> '' then
    Result := Concat(Result, ['--model', Model]);
end;

function TGittanClaude.Input(ATask: TGittanAITask; const AInput: string): string;
begin
  Result := AInput;
end;

function TGittanClaude.ReadAnswer(AExited: boolean; const AOutput, AErrors: string;
  out AText, AError: string): boolean;
begin
  { claude exits with 1 on an error it reports in its JSON, so its
    answer is read whatever the exit. }
  if ParseClaudeResult(AOutput, AText, AError) then
    Exit(AError = '');
  Result := inherited ReadAnswer(AExited, AOutput, AErrors, AText, AError);
end;

{ TGittanCopilot }

class function TGittanCopilot.Kind: TGittanAgent;
begin
  Result := gaCopilot;
end;

function TGittanCopilot.Args(ATask: TGittanAITask): TStringArray;
begin
  Result := ['-s', '--no-color', '--stream=off', '--no-ask-user',
    '--available-tools=view,grep,glob', '--allow-all-tools'];
  if Model <> '' then
    Result := Concat(Result, ['--model=' + Model]);
end;

function TGittanCopilot.Input(ATask: TGittanAITask; const AInput: string): string;
begin
  Result := Prompt(ATask) + LineEnding + LineEnding + AInput;
end;

function TGittanCopilot.ReadAnswer(AExited: boolean; const AOutput, AErrors: string;
  out AText, AError: string): boolean;
begin
  if AExited and (Trim(AOutput) <> '') then
  begin
    AText := AOutput;
    AError := '';
    Exit(True);
  end;
  Result := inherited ReadAnswer(AExited, AOutput, AErrors, AText, AError);
end;

initialization
  RegisterAI(TGittanClaude);
  RegisterAI(TGittanCopilot);
end.
