unit gittan.ai;

{** The AI features, through an agent's own command line tool run
  without a session in the repository: Claude Code's claude (claude -p)
  or GitHub Copilot's copilot (the prompt on its input), whichever the
  settings pick. Each runs with the user's own login and settings and
  reads the repository's own instructions (CLAUDE.md, AGENTS.md, and for
  Copilot .github/copilot-instructions.md). Gittan links no API of its
  own.

  The first feature writes a commit message: the changes that would be
  committed are collected as a diff (CommitChanges), given to the agent
  on its standard input with the repository's recent subjects, and its
  answer (ReadAgentAnswer) goes into the message field. The agent may
  read the repository's files for context, but gets no tool that writes,
  runs a command or goes to the network. The features are off until
  they are turned on in the settings, since the changes go to the
  agent's provider. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.job;

type
  {** The agents Gittan can run. }
  TGittanAgent = (gaClaude, gaCopilot);

const
  {** What the agents are called in the interface. }
  AgentNames: array[TGittanAgent] of string = ('Claude Code', 'GitHub Copilot');
  {** The names of their command line tools, also their keys in the
    settings (AgentOfKey). }
  AgentCommands: array[TGittanAgent] of string = ('claude', 'copilot');
  {** The most of the diff given to the agent, in bytes; the rest is cut
    at a line end and said to be, the summary of every file still whole. }
  MessageDiffKeep = 80000;
  {** How many of the recent subjects show the agent the repository's
    style. }
  MessageSubjects = 10;
  {** The most turns claude may take, each a read of a file or the
    answer. Copilot has no such limit. }
  MessageMaxTurns = 10;

{** The agent whose key (AgentCommands) is AKey; Claude Code for any
  other, the first the settings offered. }
function AgentOfKey(const AKey: string): TGittanAgent;

{** AAgent's command by the path the settings give (ASetting), else as
  found on ToolSearchPath, and for claude else the local install
  ~/.claude/local/claude that earlier versions made; empty when there is
  none. }
function FindAgent(AAgent: TGittanAgent; const ASetting: string): string;

{** The arguments AAgent runs with for a commit message, with AModel
  when it is not empty: claude in print mode with the prompt, JSON
  output and read-only tools; copilot silent, with read-only tools
  allowed (it asks for nothing then) and the prompt on its input, which
  it ignores when -p is given. Neither keeps a session. }
function CommitMessageArgs(AAgent: TGittanAgent; const AModel: string): TStringArray;

{** What AAgent is given on its input for the changes AChanges: the
  changes for claude, which has the prompt as an argument; the prompt
  and then the changes for copilot. }
function CommitMessageInput(AAgent: TGittanAgent; const AChanges: string): string;

{** What a commit of APaths in the work tree of the repository at ARoot
  would change, amending HEAD with AAmend, as the agent is given it: the
  recent subjects, the summary (diff --stat) and the diff, cut at
  MessageDiffKeep. The diff is made in a temporary index (HEAD's tree,
  the paths added as they are on disk), so untracked files show as the
  commit would take them and the real index is left alone. False, with
  git's reason in AError, when git failed; an empty AText when nothing
  would change. }
function CommitChanges(const ARoot: string; APaths: TStrings; AAmend: boolean;
  out AText, AError: string): boolean;

{** Reads what claude -p --output-format json printed: the answer in
  AText, or why there is none in AError (claude's own error, or the turn
  limit). False when AOutput is no such answer. }
function ParseClaudeResult(const AOutput: string; out AText, AError: string): boolean;

{** AText as a commit message: blank lines around it trimmed, and a code
  fence around the whole of it taken off, which a model adds at times. }
function CleanCommitMessage(const AText: string): string;

{** The commit message in AMessage from what AAgent printed (AOutput on
  standard output, AErrors on standard error) and whether it exited with
  0 (AExited); else False with the reason in AError: the agent's own,
  what it wrote on standard error, or that it gave no answer. }
function ReadAgentAnswer(AAgent: TGittanAgent; AExited: boolean;
  const AOutput, AErrors: string; out AMessage, AError: string): boolean;

type
  {** Writes a commit message for APaths of the repository at ARoot (see
    CommitChanges) with AAgent's command at AExe, in a thread: the agent
    takes some seconds. Stop ends the agent, so leaving the repository
    or quitting does not wait for its answer. }
  TGittanMessageJob = class(TGittanJob)
  private
    FRoot, FExe, FModel: string;
    FAgent: TGittanAgent;
    FPaths: TStringList;
    FAmend: boolean;
    FOk: boolean;
    FMessage, FError: string;
    function Cancelled: boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: string; AAgent: TGittanAgent;
      const AExe, AModel: string; APaths: TStrings; AAmend: boolean);
    destructor Destroy; override;
    property Root: string read FRoot;
    property Agent: TGittanAgent read FAgent;
    {** Whether a message was written. }
    property Ok: boolean read FOk;
    {** The message, when Ok. }
    property Message: string read FMessage;
    {** Why there is none, when not Ok: git's or the agent's reason, or
      that there is nothing to describe. }
    property Error: string read FError;
  end;

resourcestring
  rsNothingToDescribe = 'There are no changes to describe.';
  rsAgentNoAnswer = '%s gave no answer.';
  rsClaudeTurns = 'Claude Code stopped after %d turns without an answer.';

implementation

uses
  fpjson, jsonparser, gittan.git;

const
  { Short, whatever the repository's own messages are like: a model told
    only to follow the conventions wrote pages, describing every file it
    read. }
  CommitPrompt = 'Write the git commit message for the changes given on standard ' +
    'input, which are what will be committed. Keep it short: a subject line of at ' +
    'most 72 characters and, only when the change needs explaining, a blank line ' +
    'and a body of a few lines wrapped at 72 columns. Say what changed and why, ' +
    'not what each file or line does. Take the style (language, tense, prefixes) ' +
    'from the recent commit subjects given. Read the repository''s files only when ' +
    'the diff alone leaves the change unclear. Answer with the message alone, ' +
    'ready for git commit: no preamble, no explanation, no code fences, no ' +
    'trailers.';

function AgentOfKey(const AKey: string): TGittanAgent;
var
  A: TGittanAgent;
begin
  for A in TGittanAgent do
    if SameText(AKey, AgentCommands[A]) then
      Exit(A);
  Result := gaClaude;
end;

function FindAgent(AAgent: TGittanAgent; const ASetting: string): string;
var
  Local: string;
begin
  if ASetting <> '' then
    Exit(ASetting);
  Result := FindTool(AgentCommands[AAgent]);
  if (Result <> '') or (AAgent <> gaClaude) then
    Exit;
  Local := IncludeTrailingPathDelimiter(GetUserDir) + '.claude' + PathDelim + 'local' +
    PathDelim + 'claude';
  {$ifdef windows}
  Local := Local + '.exe';
  {$endif}
  if FileExists(Local) then
    Result := Local;
end;

function CommitMessageArgs(AAgent: TGittanAgent; const AModel: string): TStringArray;
begin
  case AAgent of
    gaCopilot:
    begin
      Result := ['-s', '--no-color', '--stream=off', '--no-ask-user',
        '--available-tools=view,grep,glob', '--allow-all-tools'];
      if AModel <> '' then
        Result := Concat(Result, ['--model=' + AModel]);
    end;
    else
    begin
      Result := ['-p', CommitPrompt, '--output-format', 'json', '--tools', 'Read,Grep,Glob',
        '--no-session-persistence', '--max-turns', IntToStr(MessageMaxTurns)];
      if AModel <> '' then
        Result := Concat(Result, ['--model', AModel]);
    end;
  end;
end;

function CommitMessageInput(AAgent: TGittanAgent; const AChanges: string): string;
begin
  if AAgent = gaCopilot then
    Result := CommitPrompt + LineEnding + LineEnding + AChanges
  else
    Result := AChanges;
end;

{ ADiff up to MessageDiffKeep bytes, cut at a line end, with a line that
  says it was. }
function KeepDiff(const ADiff: string): string;
var
  Cut: integer;
begin
  if Length(ADiff) <= MessageDiffKeep then
    Exit(ADiff);
  Cut := MessageDiffKeep;
  while (Cut > 0) and (ADiff[Cut] <> #10) do
    Dec(Cut);
  Result := Copy(ADiff, 1, Cut) + Format('[The diff is cut here: %d of its %d bytes ' +
    'are left out. The summary above lists every file.]', [Length(ADiff) - Cut,
    Length(ADiff)]) + LineEnding;
end;

function CommitChanges(const ARoot: string; APaths: TStrings; AAmend: boolean;
  out AText, AError: string): boolean;
var
  Index, List, Base, Output, Stat, Diff, Subjects, Entry: string;
  HasHead, HasParent: boolean;
  Stream: TFileStream;
  i: integer;
begin
  AText := '';
  HasHead := RunGitIn(ARoot, ['rev-parse', '--verify', '-q', 'HEAD^{commit}'], Output,
    AError);
  HasParent := HasHead and RunGitIn(ARoot, ['rev-parse', '--verify', '-q',
    'HEAD~1^{commit}'], Output, AError);
  AError := '';
  { What the commit is compared with: HEAD, or HEAD's parent for an amend,
    which replaces HEAD; the empty tree before the first commit. }
  if AAmend and HasParent then
    Base := 'HEAD~1'
  else if HasHead and not AAmend then
    Base := 'HEAD'
  else
    Base := '4b825dc642cb6eb9a060e54bf8d69288fbee4904';
  Index := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-message-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  List := Index + '.paths';
  Index := Index + '.index';
  try
    if HasHead then
      Result := RunGitIn(ARoot, ['read-tree', 'HEAD'], Output, AError, Index)
    else
      Result := RunGitIn(ARoot, ['read-tree', '--empty'], Output, AError, Index);
    if not Result then
      Exit;
    if APaths.Count > 0 then
    begin
      { The paths in a file, NUL separated, as TGittanRepo.Commit gives
        them, so no command line grows with them. }
      Stream := TFileStream.Create(List, fmCreate);
      try
        for i := 0 to APaths.Count - 1 do
        begin
          Entry := APaths[i] + #0;
          Stream.WriteBuffer(Entry[1], Length(Entry));
        end;
      finally
        Stream.Free;
      end;
      Result := RunGitIn(ARoot, ['--literal-pathspecs', 'add', '-A',
        '--pathspec-from-file=' + List, '--pathspec-file-nul'], Output, AError, Index);
      if not Result then
        Exit;
    end;
    Result := RunGitIn(ARoot, ['diff', '--cached', '--stat=100', Base], Stat, AError,
      Index) and RunGitIn(ARoot, ['diff', '--cached', '--no-ext-diff', '-M', Base], Diff,
      AError, Index);
    if not Result or (Trim(Diff) = '') then
      Exit;
  finally
    DeleteFile(Index);
    DeleteFile(List);
  end;
  Subjects := '';
  if HasHead then
    RunGitIn(ARoot, ['log', '-n', IntToStr(MessageSubjects), '--format=%s', 'HEAD'],
      Subjects, Output);
  if Trim(Subjects) <> '' then
    AText := 'Recent commit subjects of the repository, newest first:' + LineEnding +
      Subjects + LineEnding;
  if AAmend then
    AText := AText + 'The commit amends HEAD, so its changes are those of HEAD and ' +
      'the work tree together.' + LineEnding + LineEnding;
  AText := AText + 'The changes (git diff --stat):' + LineEnding + Stat + LineEnding +
    'The diff:' + LineEnding + KeepDiff(Diff);
end;

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
        AError := Format(rsClaudeTurns, [Obj.Get('num_turns', MessageMaxTurns)])
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

function CleanCommitMessage(const AText: string): string;
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := Trim(AText);
    if (Lines.Count >= 2) and (Copy(Trim(Lines[0]), 1, 3) = '```') and
      (Trim(Lines[Lines.Count - 1]) = '```') then
    begin
      Lines.Delete(Lines.Count - 1);
      Lines.Delete(0);
    end;
    Result := Trim(Lines.Text);
  finally
    Lines.Free;
  end;
end;

function ReadAgentAnswer(AAgent: TGittanAgent; AExited: boolean;
  const AOutput, AErrors: string; out AMessage, AError: string): boolean;
var
  Answer: string;
begin
  AMessage := '';
  AError := '';
  { claude exits with 1 on an error it reports in its JSON, so its
    answer is read whatever the exit; copilot's silent answer is its
    whole output, and counts only when it exited with 0. }
  if AAgent = gaClaude then
  begin
    if ParseClaudeResult(AOutput, Answer, AError) then
    begin
      if AError = '' then
        AMessage := CleanCommitMessage(Answer);
      Exit(AError = '');
    end;
  end
  else if AExited then
  begin
    AMessage := CleanCommitMessage(AOutput);
    if AMessage <> '' then
      Exit(True);
  end;
  { No answer: stderr says why (not logged in, an unknown option of an
    old version), else whatever was printed. }
  Result := False;
  if Trim(AErrors) <> '' then
    AError := Trim(AErrors)
  else if Trim(AOutput) <> '' then
    AError := Trim(AOutput)
  else
    AError := Format(rsAgentNoAnswer, [AgentNames[AAgent]]);
end;

{ TGittanMessageJob }

constructor TGittanMessageJob.Create(const ARoot: string; AAgent: TGittanAgent;
  const AExe, AModel: string; APaths: TStrings; AAmend: boolean);
begin
  { Given up on Stop: Execute asks Cancelled while the agent runs. }
  inherited Create(True);
  FRoot := ARoot;
  FAgent := AAgent;
  FExe := AExe;
  FModel := AModel;
  FPaths := TStringList.Create;
  FPaths.AddStrings(APaths);
  FAmend := AAmend;
end;

destructor TGittanMessageJob.Destroy;
begin
  inherited Destroy;
  FPaths.Free;
end;

function TGittanMessageJob.Cancelled: boolean;
begin
  Result := Terminated;
end;

procedure TGittanMessageJob.Execute;
var
  Changes, Output, Errors: string;
  Exited: boolean;
begin
  if not CommitChanges(FRoot, FPaths, FAmend, Changes, FError) then
  begin
    Done;
    Exit;
  end;
  if Changes = '' then
  begin
    FError := rsNothingToDescribe;
    Done;
    Exit;
  end;
  if Terminated then
    Exit;
  Exited := RunAgentCli(FExe, FRoot, CommitMessageArgs(FAgent, FModel),
    CommitMessageInput(FAgent, Changes), @Cancelled, Output, Errors);
  if Terminated then
    Exit;
  FOk := ReadAgentAnswer(FAgent, Exited, Output, Errors, FMessage, FError);
  Done;
end;

end.
