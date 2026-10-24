unit gittan.ai;

{** The AI features, through an agent's own command line tool run
  without a session in the repository: Claude Code's claude (claude -p)
  or GitHub Copilot's copilot (the prompt on its input), whichever the
  settings pick. Each runs with the user's own login and settings and
  reads the repository's own instructions (CLAUDE.md, AGENTS.md, and for
  Copilot .github/copilot-instructions.md). Gittan links no API of its
  own.

  The features: a commit message, and a review of the changes shown.
  The commit message: the changes that would be
  committed are collected as a diff (CommitChanges), given to the agent
  on its standard input with the repository's recent subjects, and its
  answer (ReadAgentAnswer) goes into the message field. The review: the
  diff the change view shows, its lines numbered on both sides
  (NumberDiff), so the agent names lines as the view counts them, and
  its findings (ParseReviewFindings) are review threads the change view
  shows as it shows a pull request's. The agent may
  read the repository's files for context, but gets no tool that writes,
  runs a command or goes to the network. The features are off until
  they are turned on in the settings, since the changes go to the
  agent's provider. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.job, gittan.reviews;

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
  {** The most turns claude may take for a review, which reads files to
    check what it finds. }
  ReviewMaxTurns = 20;
  {** The most findings of a review kept; the prompt asks for fewer. }
  ReviewMaxFindings = 10;

{** The agent whose key (AgentCommands) is AKey; Claude Code for any
  other, the first the settings offered. }
  { Only what matters, as a list the change view can place: a model
    asked to review without a limit lists style and praise, and counts
    lines in a hunk wrongly unless they are numbered for it. }
  ReviewPrompt = 'Review the changes given on standard input: a diff with each ' +
    'line numbered, N for a line of the new side and O for a line of the old side. ' +
    'Point out only real problems: bugs, wrong results, crashes, data loss, ' +
    'security holes, races, edge cases the change misses. Leave out style, naming, ' +
    'formatting, praise and summaries. At most 10 findings, fewer is better, and ' +
    'none is a fine answer. You may read the repository''s files to check a ' +
    'finding. Answer with a JSON array alone, no code fences, each finding ' +
    '{"path": the file as the diff names it, "line": the number after N or O, ' +
    '"side": "new" for N or "old" for O, "severity": "bug", "risk" or "question", ' +
    '"body": a few sentences in Markdown}.';

function AgentOfKey(const AKey: string): TGittanAgent;

{** AAgent's command by the path the settings give (ASetting), else as
  found on ToolSearchPath, and for claude else the local install
  ~/.claude/local/claude that earlier versions made; empty when there is
  none. }
function FindAgent(AAgent: TGittanAgent; const ASetting: string): string;

{** The arguments AAgent runs with for APrompt, with AModel when it is
  not empty: claude in print mode with the prompt, JSON output,
  read-only tools and at most AMaxTurns turns; copilot silent, with
  read-only tools allowed (it asks for nothing then) and the prompt on
  its input, which it ignores when -p is given. Neither keeps a
  session. }
function AgentArgs(AAgent: TGittanAgent; const APrompt, AModel: string;
  AMaxTurns: integer): TStringArray;

{** What AAgent is given on its input for APrompt and AChanges: the
  changes for claude, which has the prompt as an argument; the prompt
  and then the changes for copilot. }
function AgentInput(AAgent: TGittanAgent; const APrompt, AChanges: string): string;

{** AgentArgs and AgentInput for a commit message. }
function CommitMessageArgs(AAgent: TGittanAgent; const AModel: string): TStringArray;
function CommitMessageInput(AAgent: TGittanAgent; const AChanges: string): string;

{** AgentArgs and AgentInput for a review. }
function ReviewArgs(AAgent: TGittanAgent; const AModel: string): TStringArray;
function ReviewInput(AAgent: TGittanAgent; const AChanges: string): string;

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

{** What the change view shows of the repository at ARoot compared with
  ABase (empty for HEAD; ARange when it is a range, A..B or A...B), as
  the agent is given it for a review: the summary and the diff, its
  lines numbered (NumberDiff), cut at MessageDiffKeep. Against a commit
  the diff is the work tree's, made as CommitChanges makes it for
  APaths, every changed file, so untracked files are in it; a range is
  diffed as it is. False, with git's reason in AError, when git failed;
  an empty AText when nothing differs. }
function ReviewChanges(const ARoot, ABase: string; ARange: boolean; APaths: TStrings;
  out AText, AError: string): boolean;

{** ADiff, a unified diff, with every line of its hunks numbered as the
  change view numbers it: a context or added line with "N" and its line
  in the new side, a removed line with "O" and its line in the old side
  ("N12 +text", "O7 -text"); the file headers and hunk headers are left
  as they are. }
function NumberDiff(const ADiff: string): string;

{** The findings of a review in AText, the agent's answer: a JSON array
  of objects with path, line, side ("old" for a line of the old side),
  severity and body, which may come inside a code fence or after a
  sentence. Each with a path, a line and a body is a thread in AThreads
  with AAgent as its agent and its comment's author, at most
  ReviewMaxFindings. False when AText holds no such array; an empty
  array is no finding. }
function ParseReviewFindings(const AText, AAgent: string;
  out AThreads: TGittanReviewThreads): boolean;

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

{** ReadAgentAnswer's answer as the agent gave it, not made a commit
  message. }
function ReadAgentText(AAgent: TGittanAgent; AExited: boolean;
  const AOutput, AErrors: string; out AText, AError: string): boolean;

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

  {** Reviews what the change view shows of the repository at ARoot
    against ABase (see ReviewChanges) with AAgent's command at AExe, in
    a thread. AKey is the caller's, to tell whether the findings are
    still for what is shown when they come. Stop ends the agent. }
  TGittanAIReviewJob = class(TGittanJob)
  private
    FRoot, FExe, FModel, FBase, FKey: string;
    FAgent: TGittanAgent;
    FRange: boolean;
    FPaths: TStringList;
    FOk: boolean;
    FThreads: TGittanReviewThreads;
    FError: string;
    function Cancelled: boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: string; AAgent: TGittanAgent;
      const AExe, AModel, ABase: string; ARange: boolean; APaths: TStrings;
      const AKey: string);
    destructor Destroy; override;
    property Agent: TGittanAgent read FAgent;
    property Key: string read FKey;
    {** Whether the agent answered with findings, none among them too. }
    property Ok: boolean read FOk;
    property Threads: TGittanReviewThreads read FThreads;
    {** Why there are none, when not Ok. }
    property Error: string read FError;
  end;

resourcestring
  rsNothingToReview = 'There are no changes to review.';
  rsReviewNotRead = 'The answer was no list of findings: %s';
  rsNothingToDescribe = 'There are no changes to describe.';
  rsAgentNoAnswer = '%s gave no answer.';
  rsClaudeTurns = 'Claude Code stopped after %d turns without an answer.';

implementation

uses
  Math, fpjson, jsonparser, DateUtils, gittan.git;

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

function AgentArgs(AAgent: TGittanAgent; const APrompt, AModel: string;
  AMaxTurns: integer): TStringArray;
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
      Result := ['-p', APrompt, '--output-format', 'json', '--tools', 'Read,Grep,Glob',
        '--no-session-persistence', '--max-turns', IntToStr(AMaxTurns)];
      if AModel <> '' then
        Result := Concat(Result, ['--model', AModel]);
    end;
  end;
end;

function AgentInput(AAgent: TGittanAgent; const APrompt, AChanges: string): string;
begin
  if AAgent = gaCopilot then
    Result := APrompt + LineEnding + LineEnding + AChanges
  else
    Result := AChanges;
end;

function CommitMessageArgs(AAgent: TGittanAgent; const AModel: string): TStringArray;
begin
  Result := AgentArgs(AAgent, CommitPrompt, AModel, MessageMaxTurns);
end;

function CommitMessageInput(AAgent: TGittanAgent; const AChanges: string): string;
begin
  Result := AgentInput(AAgent, CommitPrompt, AChanges);
end;

function ReviewArgs(AAgent: TGittanAgent; const AModel: string): TStringArray;
begin
  Result := AgentArgs(AAgent, ReviewPrompt, AModel, ReviewMaxTurns);
end;

function ReviewInput(AAgent: TGittanAgent; const AChanges: string): string;
begin
  Result := AgentInput(AAgent, ReviewPrompt, AChanges);
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

const
  EmptyTreeId = '4b825dc642cb6eb9a060e54bf8d69288fbee4904';

{ Whether the repository at ARoot has HEAD, and HEAD a parent. }
procedure HeadState(const ARoot: string; out AHasHead, AHasParent: boolean);
var
  Output, Error: string;
begin
  AHasHead := RunGitIn(ARoot, ['rev-parse', '--verify', '-q', 'HEAD^{commit}'], Output,
    Error);
  AHasParent := AHasHead and RunGitIn(ARoot, ['rev-parse', '--verify', '-q',
    'HEAD~1^{commit}'], Output, Error);
end;

{ The summary and the diff of the work tree's APaths against ABase,
  made in a temporary index (HEAD's tree, or none without AHasHead,
  with the paths added as they are on disk), so untracked files are in
  it and the real index is left alone. }
function IndexDiff(const ARoot, ABase: string; AHasHead: boolean; APaths: TStrings;
  out AStat, ADiff, AError: string): boolean;
var
  Index, List, Output, Entry: string;
  Stream: TFileStream;
  i: integer;
begin
  AStat := '';
  ADiff := '';
  AError := '';
  Index := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-ai-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  List := Index + '.paths';
  Index := Index + '.index';
  try
    if AHasHead then
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
    Result := RunGitIn(ARoot, ['diff', '--cached', '--stat=100', ABase], AStat, AError,
      Index) and RunGitIn(ARoot, ['diff', '--cached', '--no-ext-diff', '-M', ABase], ADiff,
      AError, Index);
  finally
    DeleteFile(Index);
    DeleteFile(List);
  end;
end;

function CommitChanges(const ARoot: string; APaths: TStrings; AAmend: boolean;
  out AText, AError: string): boolean;
var
  Base, Stat, Diff, Subjects, Output: string;
  HasHead, HasParent: boolean;
begin
  AText := '';
  HeadState(ARoot, HasHead, HasParent);
  { What the commit is compared with: HEAD, or HEAD's parent for an amend,
    which replaces HEAD; the empty tree before the first commit. }
  if AAmend and HasParent then
    Base := 'HEAD~1'
  else if HasHead and not AAmend then
    Base := 'HEAD'
  else
    Base := EmptyTreeId;
  Result := IndexDiff(ARoot, Base, HasHead, APaths, Stat, Diff, AError);
  if not Result or (Trim(Diff) = '') then
    Exit;
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

function ReviewChanges(const ARoot, ABase: string; ARange: boolean; APaths: TStrings;
  out AText, AError: string): boolean;
var
  Base, Stat, Diff: string;
  HasHead, HasParent: boolean;
begin
  AText := '';
  if ARange then
    Result := RunGitIn(ARoot, ['diff', '--stat=100', ABase], Stat, AError) and
      RunGitIn(ARoot, ['diff', '--no-ext-diff', '-M', ABase], Diff, AError)
  else
  begin
    HeadState(ARoot, HasHead, HasParent);
    Base := ABase;
    if Base = '' then
      if HasHead then
        Base := 'HEAD'
      else
        Base := EmptyTreeId;
    Result := IndexDiff(ARoot, Base, HasHead, APaths, Stat, Diff, AError);
  end;
  if not Result or (Trim(Diff) = '') then
    Exit;
  AText := 'The changes (git diff --stat):' + LineEnding + Stat + LineEnding +
    'The diff, each line numbered (N for the new side, O for the old):' + LineEnding +
    KeepDiff(NumberDiff(Diff));
end;

{ The number after AMark ('-' or '+') in the hunk header AHeader. }
function HunkStart(const AHeader: string; AMark: char): integer;
var
  p, q: integer;
begin
  Result := 0;
  p := Pos(' ' + AMark, AHeader);
  if p = 0 then
    Exit;
  q := p + 2;
  while (q <= Length(AHeader)) and (AHeader[q] in ['0'..'9']) do
    Inc(q);
  Result := StrToIntDef(Copy(AHeader, p + 2, q - p - 2), 0);
end;

function NumberDiff(const ADiff: string): string;
var
  Lines: TStringList;
  Text: TStringBuilder;
  i, OldLine, NewLine: integer;
  S: string;
  InHunk: boolean;
begin
  Lines := TStringList.Create;
  Text := TStringBuilder.Create;
  try
    Lines.Text := ADiff;
    InHunk := False;
    OldLine := 0;
    NewLine := 0;
    for i := 0 to Lines.Count - 1 do
    begin
      S := Lines[i];
      if Copy(S, 1, 2) = '@@' then
      begin
        InHunk := True;
        OldLine := HunkStart(S, '-');
        NewLine := HunkStart(S, '+');
      end
      else if Copy(S, 1, 5) = 'diff ' then
        InHunk := False
      else if InHunk and (S <> '') and (S[1] = '-') then
      begin
        S := 'O' + IntToStr(OldLine) + ' ' + S;
        Inc(OldLine);
      end
      else if InHunk and (S <> '') and (S[1] = '+') then
      begin
        S := 'N' + IntToStr(NewLine) + ' ' + S;
        Inc(NewLine);
      end
      else if InHunk and ((S = '') or (S[1] = ' ')) then
      begin
        S := 'N' + IntToStr(NewLine) + ' ' + S;
        Inc(OldLine);
        Inc(NewLine);
      end;
      Text.Append(S);
      Text.Append(#10);
    end;
    Result := Text.ToString;
  finally
    Text.Free;
    Lines.Free;
  end;
end;

function ParseReviewFindings(const AText, AAgent: string;
  out AThreads: TGittanReviewThreads): boolean;
var
  Data: TJSONData;
  Item: TJSONObject;
  Thread: TGittanReviewThread;
  First, Last, i, n: integer;
  Body: string;
begin
  AThreads := nil;
  { The array from its first bracket to its last, whatever is around it. }
  First := Pos('[', AText);
  Last := LastDelimiter(']', AText);
  if (First = 0) or (Last < First) then
    Exit(False);
  try
    Data := GetJSON(Copy(AText, First, Last - First + 1));
  except
    Exit(False);
  end;
  try
    Result := Data is TJSONArray;
    if not Result then
      Exit;
    n := 0;
    SetLength(AThreads, Min(Data.Count, ReviewMaxFindings));
    for i := 0 to Data.Count - 1 do
    begin
      if n >= Length(AThreads) then
        Break;
      if not (Data.Items[i] is TJSONObject) then
        Continue;
      Item := TJSONObject(Data.Items[i]);
      Body := Trim(Item.Get('body', ''));
      Thread := Default(TGittanReviewThread);
      Thread.Path := Item.Get('path', '');
      { A path as git prints it in a diff header. }
      if (Copy(Thread.Path, 1, 2) = 'a/') or (Copy(Thread.Path, 1, 2) = 'b/') then
        Delete(Thread.Path, 1, 2);
      if Item.Find('line') is TJSONNumber then
        Thread.Line := Item.Get('line', 0)
      else
        Thread.Line := StrToIntDef(Item.Get('line', ''), 0);
      if (Thread.Path = '') or (Thread.Line <= 0) or (Body = '') then
        Continue;
      Thread.OriginalLine := Thread.Line;
      Thread.LeftSide := SameText(Item.Get('side', ''), 'old');
      Thread.Agent := AAgent;
      Thread.Severity := LowerCase(Item.Get('severity', ''));
      SetLength(Thread.Comments, 1);
      Thread.Comments[0].Author := AAgent;
      Thread.Comments[0].Body := StringReplace(Body, #13#10, #10, [rfReplaceAll]);
      Thread.Comments[0].Created := LocalTimeToUniversal(Now);
      AThreads[n] := Thread;
      Inc(n);
    end;
    SetLength(AThreads, n);
  finally
    Data.Free;
  end;
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
    Lines.Text := Trim(AText); //split on LF, CR or CRLF, whatever the agent wrote
    if (Lines.Count >= 2) and (Copy(Trim(Lines[0]), 1, 3) = '```') and
      (Trim(Lines[Lines.Count - 1]) = '```') then
    begin
      Lines.Delete(Lines.Count - 1);
      Lines.Delete(0);
    end;
    Lines.LineBreak := #10; //a commit message's lines end in LF on Windows too
    Result := Trim(Lines.Text);
  finally
    Lines.Free;
  end;
end;

function ReadAgentText(AAgent: TGittanAgent; AExited: boolean;
  const AOutput, AErrors: string; out AText, AError: string): boolean;
begin
  AText := '';
  AError := '';
  { claude exits with 1 on an error it reports in its JSON, so its
    answer is read whatever the exit; copilot's silent answer is its
    whole output, and counts only when it exited with 0. }
  if AAgent = gaClaude then
  begin
    if ParseClaudeResult(AOutput, AText, AError) then
      Exit(AError = '');
  end
  else if AExited and (Trim(AOutput) <> '') then
  begin
    AText := AOutput;
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

function ReadAgentAnswer(AAgent: TGittanAgent; AExited: boolean;
  const AOutput, AErrors: string; out AMessage, AError: string): boolean;
var
  Text: string;
begin
  AMessage := '';
  Result := ReadAgentText(AAgent, AExited, AOutput, AErrors, Text, AError);
  if not Result then
    Exit;
  AMessage := CleanCommitMessage(Text);
  if AMessage = '' then
  begin
    AError := Format(rsAgentNoAnswer, [AgentNames[AAgent]]);
    Result := False;
  end;
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

{ TGittanAIReviewJob }

constructor TGittanAIReviewJob.Create(const ARoot: string; AAgent: TGittanAgent;
  const AExe, AModel, ABase: string; ARange: boolean; APaths: TStrings;
  const AKey: string);
begin
  { Given up on Stop: Execute asks Cancelled while the agent runs. }
  inherited Create(True);
  FRoot := ARoot;
  FAgent := AAgent;
  FExe := AExe;
  FModel := AModel;
  FBase := ABase;
  FRange := ARange;
  FPaths := TStringList.Create;
  FPaths.AddStrings(APaths);
  FKey := AKey;
end;

destructor TGittanAIReviewJob.Destroy;
begin
  inherited Destroy;
  FPaths.Free;
end;

function TGittanAIReviewJob.Cancelled: boolean;
begin
  Result := Terminated;
end;

procedure TGittanAIReviewJob.Execute;
var
  Changes, Output, Errors, Answer: string;
  Exited: boolean;
begin
  if not ReviewChanges(FRoot, FBase, FRange, FPaths, Changes, FError) then
  begin
    Done;
    Exit;
  end;
  if Changes = '' then
  begin
    FError := rsNothingToReview;
    Done;
    Exit;
  end;
  if Terminated then
    Exit;
  Exited := RunAgentCli(FExe, FRoot, ReviewArgs(FAgent, FModel),
    ReviewInput(FAgent, Changes), @Cancelled, Output, Errors);
  if Terminated then
    Exit;
  if ReadAgentText(FAgent, Exited, Output, Errors, Answer, FError) then
  begin
    FOk := ParseReviewFindings(Answer, AgentNames[FAgent], FThreads);
    if not FOk then
      FError := Format(rsReviewNotRead, [Copy(Trim(Answer), 1, 300)]);
  end;
  Done;
end;

end.
