unit testai;

{** Tests of gittan.ai: the changes a commit message is written for,
  made against a repository in a temporary folder with the real git, the
  arguments and input of each agent, and the reading of their answers.
  No agent is run; they need a login and the network. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.git, gittan.ai;

type
  TAiTest = class(TTestCase)
  private
    FDir: string;
    procedure Git(const AArgs: array of string);
    procedure WriteFile(const AName, AContent: string);
    function Changes(const APaths: array of string; AAmend: boolean = False): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestChangesOfChosenPaths;
    procedure TestChangesBeforeFirstCommit;
    procedure TestChangesAmend;
    procedure TestNoChanges;
    procedure TestLongDiffIsCut;
    procedure TestParseResult;
    procedure TestParseError;
    procedure TestParseNotAnAnswer;
    procedure TestCleanMessage;
    procedure TestArgs;
    procedure TestCopilotArgs;
    procedure TestInput;
    procedure TestAgentOfKey;
    procedure TestReadClaudeAnswer;
    procedure TestReadCopilotAnswer;
  end;

implementation

procedure RemoveTree(const ADir: string);
var
  Info: TSearchRec;
begin
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, Info) = 0 then
  try
    repeat
      if (Info.Name = '.') or (Info.Name = '..') then
        Continue;
      if Info.Attr and faDirectory <> 0 then
        RemoveTree(IncludeTrailingPathDelimiter(ADir) + Info.Name)
      else
        DeleteFile(IncludeTrailingPathDelimiter(ADir) + Info.Name);
    until FindNext(Info) <> 0;
  finally
    FindClose(Info);
  end;
  RemoveDir(ADir);
end;

procedure TAiTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-ai-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
  Git(['init', '-q']);
end;

procedure TAiTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TAiTest.Git(const AArgs: array of string);
var
  Output, Error: string;
begin
  Error := '';
  AssertTrue('git ' + AArgs[0] + ': ' + Error, RunGitIn(FDir, AArgs, Output, Error));
end;

procedure TAiTest.WriteFile(const AName, AContent: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Text := AContent;
    L.SaveToFile(IncludeTrailingPathDelimiter(FDir) + AName);
  finally
    L.Free;
  end;
end;

function TAiTest.Changes(const APaths: array of string; AAmend: boolean): string;
var
  Paths: TStringList;
  Error: string;
  S: string;
begin
  Error := '';
  Paths := TStringList.Create;
  try
    for S in APaths do
      Paths.Add(S);
    AssertTrue('CommitChanges: ' + Error, CommitChanges(FDir, Paths, AAmend, Result, Error));
  finally
    Paths.Free;
  end;
end;

procedure TAiTest.TestChangesOfChosenPaths;
var
  Text, Output, Error: string;
begin
  WriteFile('a.txt', 'one');
  WriteFile('b.txt', 'two');
  Git(['add', '.']);
  Git(['commit', '-q', '-m', 'Add a and b']);
  WriteFile('a.txt', 'one changed');
  WriteFile('b.txt', 'two changed');
  WriteFile('new file.txt', 'brand new');
  Git(['add', 'b.txt']);
  Text := Changes(['a.txt', 'new file.txt']);
  AssertTrue('the subjects', Pos('Add a and b', Text) > 0);
  AssertTrue('a tracked file', Pos('+one changed', Text) > 0);
  AssertTrue('an untracked file', Pos('+brand new', Text) > 0);
  AssertTrue('the summary', Pos('git diff --stat', Text) > 0);
  AssertEquals('a file not chosen is left out', 0, Pos('two changed', Text));
  { The real index is left as it was. }
  AssertTrue(RunGitIn(FDir, ['diff', '--cached', '--name-only'], Output, Error));
  AssertEquals('b.txt', Trim(Output));
end;

procedure TAiTest.TestChangesBeforeFirstCommit;
var
  Text: string;
begin
  WriteFile('first.txt', 'hello');
  Text := Changes(['first.txt']);
  AssertTrue(Pos('+hello', Text) > 0);
  AssertEquals('no subjects without a commit', 0, Pos('Recent commit', Text));
end;

procedure TAiTest.TestChangesAmend;
var
  Text: string;
begin
  WriteFile('a.txt', 'one');
  Git(['add', '.']);
  Git(['commit', '-q', '-m', 'First']);
  WriteFile('a.txt', 'two');
  Git(['commit', '-q', '-am', 'Second']);
  { Amending with nothing new describes HEAD's own change. }
  Text := Changes([], True);
  AssertTrue(Pos('-one', Text) > 0);
  AssertTrue(Pos('+two', Text) > 0);
  AssertTrue(Pos('amends HEAD', Text) > 0);
end;

procedure TAiTest.TestNoChanges;
begin
  WriteFile('a.txt', 'one');
  Git(['add', '.']);
  Git(['commit', '-q', '-m', 'First']);
  AssertEquals('', Changes(['a.txt']));
end;

procedure TAiTest.TestLongDiffIsCut;
var
  Text, Big: string;
  i: integer;
begin
  Big := '';
  for i := 1 to MessageDiffKeep div 20 do
    Big := Big + Format('line number %8d', [i]) + LineEnding;
  WriteFile('big.txt', Big);
  Text := Changes(['big.txt']);
  AssertTrue('said to be cut', Pos('The diff is cut here', Text) > 0);
  AssertTrue('near the limit', Length(Text) < MessageDiffKeep + 2000);
  AssertTrue('the summary is whole', Pos('big.txt', Text) > 0);
end;

procedure TAiTest.TestParseResult;
var
  Text, Error: string;
begin
  AssertTrue(ParseClaudeResult('{"type":"result","subtype":"success","is_error":false,' +
    '"result":"Fix the tree\n\nIt drew twice.","session_id":"x","total_cost_usd":0.01}',
    Text, Error));
  AssertEquals('', Error);
  AssertEquals('Fix the tree'#10#10'It drew twice.', Text);
  { A warning line before the answer. }
  AssertTrue(ParseClaudeResult('Warning: something' + LineEnding +
    '{"type":"result","subtype":"success","is_error":false,"result":"Ok"}', Text, Error));
  AssertEquals('Ok', Text);
end;

procedure TAiTest.TestParseError;
var
  Text, Error: string;
begin
  AssertTrue(ParseClaudeResult('{"type":"result","subtype":"success","is_error":true,' +
    '"result":"Invalid API key - Please run /login"}', Text, Error));
  AssertEquals('', Text);
  AssertEquals('Invalid API key - Please run /login', Error);
  AssertTrue(ParseClaudeResult('{"type":"result","subtype":"error_max_turns",' +
    '"is_error":true,"num_turns":11}', Text, Error));
  AssertEquals(Format(rsClaudeTurns, [11]), Error);
  AssertTrue(ParseClaudeResult('{"type":"result","subtype":"success","is_error":false,' +
    '"result":"  "}', Text, Error));
  AssertEquals(Format(rsAgentNoAnswer, ['Claude Code']), Error);
end;

procedure TAiTest.TestParseNotAnAnswer;
var
  Text, Error: string;
begin
  AssertFalse(ParseClaudeResult('', Text, Error));
  AssertFalse(ParseClaudeResult('error: unknown option ''--tools''', Text, Error));
  AssertFalse(ParseClaudeResult('{"type":"system"}', Text, Error));
  AssertFalse(ParseClaudeResult('{not json', Text, Error));
end;

procedure TAiTest.TestCleanMessage;
begin
  AssertEquals('Subject'#10#10'Body', CleanCommitMessage(#10'Subject'#10#10'Body'#10#10));
  AssertEquals('Subject'#10#10'Body', CleanCommitMessage('```'#10'Subject'#10#10'Body'#10'```'));
  AssertEquals('Subject', CleanCommitMessage('```text'#10'Subject'#10'```'#10));
  { A fence inside the body stays. }
  AssertEquals('Subject'#10#10'```'#10'code'#10'```', CleanCommitMessage(
    'Subject'#10#10'```'#10'code'#10'```'));
end;

procedure TAiTest.TestArgs;
var
  Args: TStringArray;
  Line: string;
begin
  Args := CommitMessageArgs(gaClaude, '');
  Line := string.Join(' ', Args);
  AssertEquals('-p', Args[0]);
  AssertTrue(Pos('--output-format json', Line) > 0);
  AssertTrue('read-only tools', Pos('--tools Read,Grep,Glob', Line) > 0);
  AssertEquals('no model without one', 0, Pos('--model', Line));
  AssertTrue('the message is asked to be short', Pos('at most 72 characters', Args[1]) > 0);
  Args := CommitMessageArgs(gaClaude, 'haiku');
  AssertEquals('haiku', Args[High(Args)]);
  AssertEquals('--model', Args[High(Args) - 1]);
end;

procedure TAiTest.TestCopilotArgs;
var
  Args: TStringArray;
  Line: string;
begin
  Args := CommitMessageArgs(gaCopilot, '');
  Line := string.Join(' ', Args);
  AssertEquals('the prompt goes on the input, which -p would make it ignore', 0,
    Pos('-p ', Line + ' '));
  AssertTrue('only its answer', Pos('-s', Line) > 0);
  AssertTrue('read-only tools', Pos('--available-tools=view,grep,glob', Line) > 0);
  AssertTrue('asks for nothing', Pos('--allow-all-tools', Line) > 0);
  AssertEquals(0, Pos('--model', Line));
  Args := CommitMessageArgs(gaCopilot, 'auto');
  AssertEquals('--model=auto', Args[High(Args)]);
end;

procedure TAiTest.TestInput;
begin
  AssertEquals('claude has the prompt as an argument', 'the changes',
    CommitMessageInput(gaClaude, 'the changes'));
  AssertTrue('copilot gets the prompt first', Pos('Write the git commit message',
    CommitMessageInput(gaCopilot, 'the changes')) = 1);
  AssertTrue(Pos('the changes', CommitMessageInput(gaCopilot, 'the changes')) > 0);
end;

procedure TAiTest.TestAgentOfKey;
begin
  AssertTrue(AgentOfKey('copilot') = gaCopilot);
  AssertTrue(AgentOfKey('Copilot') = gaCopilot);
  AssertTrue(AgentOfKey('claude') = gaClaude);
  AssertTrue('an unknown key is Claude Code', AgentOfKey('') = gaClaude);
end;

procedure TAiTest.TestReadClaudeAnswer;
var
  Msg, Error: string;
begin
  AssertTrue(ReadAgentAnswer(gaClaude, True, '{"type":"result","subtype":"success",' +
    '"is_error":false,"result":"```\nFix it\n```"}', '', Msg, Error));
  AssertEquals('Fix it', Msg);
  { An error in the JSON, with exit 1. }
  AssertFalse(ReadAgentAnswer(gaClaude, False, '{"type":"result","subtype":"success",' +
    '"is_error":true,"result":"Not logged in"}', '', Msg, Error));
  AssertEquals('Not logged in', Error);
  { No JSON: stderr says why. }
  AssertFalse(ReadAgentAnswer(gaClaude, False, '', 'error: unknown option', Msg, Error));
  AssertEquals('error: unknown option', Error);
end;

procedure TAiTest.TestReadCopilotAnswer;
var
  Msg, Error: string;
begin
  AssertTrue(ReadAgentAnswer(gaCopilot, True, #10'Fix it'#10#10'Body'#10, '', Msg, Error));
  AssertEquals('Fix it'#10#10'Body', Msg);
  AssertFalse('a failed run is no answer', ReadAgentAnswer(gaCopilot, False,
    'partial', 'No authentication information found.', Msg, Error));
  AssertEquals('No authentication information found.', Error);
  AssertFalse(ReadAgentAnswer(gaCopilot, True, '  ', '', Msg, Error));
  AssertEquals(Format(rsAgentNoAnswer, ['GitHub Copilot']), Error);
end;

initialization
  RegisterTest(TAiTest);
end.
