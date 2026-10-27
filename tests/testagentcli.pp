unit testagentcli;

{** Tests of gittan.agentcli: the arguments and input of claude and
  copilot for each task, the reading of their answers (claude's JSON,
  copilot's output), where they are found, their version line, and
  that they are registered with gittan.ai. No agent is run; they need
  a login. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.ai, gittan.agentcli;

type
  TAgentCliTest = class(TTestCase)
  published
    procedure TestRegistered;
    procedure TestClaudeArgs;
    procedure TestCopilotArgs;
    procedure TestInput;
    procedure TestReviewArgs;
    procedure TestFindArgs;
    procedure TestParseResult;
    procedure TestParseError;
    procedure TestParseNotAnAnswer;
    procedure TestReadClaudeAnswer;
    procedure TestReadCopilotAnswer;
    procedure TestFind;
    procedure TestTitle;
    procedure TestVersionOf;
  end;

implementation

procedure TAgentCliTest.TestRegistered;
begin
  AssertTrue(AIClassOf(gaClaude) = TGittanClaude);
  AssertTrue(AIClassOf(gaCopilot) = TGittanCopilot);
  AssertTrue('a tool reads the files itself', TGittanClaude.ReadsFiles);
  AssertTrue(TGittanCopilot.ReadsFiles);
  AssertFalse('a tool is no API', TGittanClaude.IsApi);
  AssertEquals('Claude Code', TGittanClaude.Name);
  AssertEquals('GitHub Copilot', TGittanCopilot.Name);
end;

procedure TAgentCliTest.TestClaudeArgs;
var
  AI: TGittanAI;
  Args: TStringArray;
  Line: string;
begin
  AI := TGittanClaude.Create('/usr/local/bin/claude', '', '');
  try
    Args := TGittanClaude(AI).Args(atMessage);
    Line := string.Join(' ', Args);
    AssertEquals('-p', Args[0]);
    AssertTrue(Pos('--output-format json', Line) > 0);
    AssertTrue('read-only tools', Pos('--tools Read,Grep,Glob', Line) > 0);
    AssertTrue('no session kept', Pos('--no-session-persistence', Line) > 0);
    AssertTrue(Pos('--max-turns ' + IntToStr(MessageMaxTurns), Line) > 0);
    AssertEquals('no model without one', 0, Pos('--model', Line));
    AssertEquals('the prompt is the task''s', TaskPrompt(atMessage, True), Args[1]);
  finally
    AI.Free;
  end;
  AI := TGittanClaude.Create('claude', '', 'haiku');
  try
    Args := TGittanClaude(AI).Args(atMessage);
    AssertEquals('haiku', Args[High(Args)]);
    AssertEquals('--model', Args[High(Args) - 1]);
  finally
    AI.Free;
  end;
end;

procedure TAgentCliTest.TestCopilotArgs;
var
  AI: TGittanCopilot;
  Args: TStringArray;
  Line: string;
begin
  AI := TGittanCopilot.Create('copilot', '', '');
  try
    Args := AI.Args(atMessage);
    Line := string.Join(' ', Args);
    AssertEquals('the prompt goes on the input, which -p would make it ignore', 0,
      Pos('-p ', Line + ' '));
    AssertTrue('only its answer', Pos('-s', Line) > 0);
    AssertTrue('read-only tools', Pos('--available-tools=view,grep,glob', Line) > 0);
    AssertTrue('asks for nothing', Pos('--allow-all-tools', Line) > 0);
    AssertEquals(0, Pos('--model', Line));
  finally
    AI.Free;
  end;
  AI := TGittanCopilot.Create('copilot', '', 'auto');
  try
    Args := AI.Args(atMessage);
    AssertEquals('--model=auto', Args[High(Args)]);
  finally
    AI.Free;
  end;
end;

procedure TAgentCliTest.TestInput;
var
  Claude, Copilot: TGittanAgentCli;
begin
  Claude := TGittanClaude.Create('claude', '', '');
  Copilot := TGittanCopilot.Create('copilot', '', '');
  try
    AssertEquals('claude has the prompt as an argument', 'the changes',
      Claude.Input(atMessage, 'the changes'));
    AssertTrue('copilot gets the prompt first', Pos('Write the git commit message',
      Copilot.Input(atMessage, 'the changes')) = 1);
    AssertTrue(Pos('the changes', Copilot.Input(atMessage, 'the changes')) > 0);
    AssertTrue('the review prompt for copilot', Pos('Review the changes',
      Copilot.Input(atReview, 'the diff')) = 1);
    AssertEquals('the diff', Claude.Input(atReview, 'the diff'));
    AssertEquals('the question alone for claude', 'the parser',
      Claude.Input(atFind, 'the parser'));
    AssertTrue('copilot gets the prompt, then the question', Pos('Find where',
      Copilot.Input(atFind, 'the parser')) = 1);
    AssertTrue(Pos('the parser', Copilot.Input(atFind, 'the parser')) > 0);
  finally
    Claude.Free;
    Copilot.Free;
  end;
end;

procedure TAgentCliTest.TestReviewArgs;
var
  AI: TGittanClaude;
  Args: TStringArray;
begin
  AI := TGittanClaude.Create('claude', '', '');
  try
    Args := AI.Args(atReview);
    AssertTrue('more turns, to check findings', Pos('--max-turns ' +
      IntToStr(ReviewMaxTurns), string.Join(' ', Args)) > 0);
    AssertTrue('asks for a JSON array', Pos('JSON array', Args[1]) > 0);
    AssertTrue('may read files', Pos('read the repository', Args[1]) > 0);
  finally
    AI.Free;
  end;
end;

procedure TAgentCliTest.TestFindArgs;
var
  AI: TGittanClaude;
  Args: TStringArray;
  Line: string;
begin
  AI := TGittanClaude.Create('claude', '', 'haiku');
  try
    Args := AI.Args(atFind);
    Line := string.Join(' ', Args);
    AssertTrue(Pos('--max-turns ' + IntToStr(FindMaxTurns), Line) > 0);
    AssertTrue(Pos('--model haiku', Line) > 0);
    AssertTrue('read-only tools', Pos('--tools Read,Grep,Glob', Line) > 0);
    AssertTrue('asks for a JSON array', Pos('JSON array', Args[1]) > 0);
  finally
    AI.Free;
  end;
end;

procedure TAgentCliTest.TestParseResult;
var
  Text, Error: string;
begin
  AssertTrue(ParseClaudeResult('{"type":"result","subtype":"success","is_error":false,' +
    '"result":"Fix the parser\n\nIt broke."}', Text, Error));
  AssertEquals('Fix the parser'#10#10'It broke.', Text);
  AssertEquals('', Error);
  { A warning printed before the answer. }
  AssertTrue(ParseClaudeResult('Warning: something' + LineEnding +
    '{"type":"result","subtype":"success","is_error":false,"result":"Fix it"}',
    Text, Error));
  AssertEquals('Fix it', Text);
end;

procedure TAgentCliTest.TestParseError;
var
  Text, Error: string;
begin
  AssertTrue(ParseClaudeResult('{"type":"result","subtype":"success","is_error":true,' +
    '"result":"Not logged in"}', Text, Error));
  AssertEquals('', Text);
  AssertEquals('Not logged in', Error);
  AssertTrue(ParseClaudeResult('{"type":"result","subtype":"error_max_turns",' +
    '"is_error":false,"num_turns":10,"result":""}', Text, Error));
  AssertEquals(Format(rsClaudeTurns, [10]), Error);
  AssertTrue(ParseClaudeResult('{"type":"result","subtype":"success","is_error":false,' +
    '"result":""}', Text, Error));
  AssertEquals('an empty answer is none', Format(rsAgentNoAnswer, ['Claude Code']), Error);
end;

procedure TAgentCliTest.TestParseNotAnAnswer;
var
  Text, Error: string;
begin
  AssertFalse(ParseClaudeResult('', Text, Error));
  AssertFalse(ParseClaudeResult('error: unknown option ''--tools''', Text, Error));
  AssertFalse(ParseClaudeResult('{"type":"system"}', Text, Error));
  AssertFalse(ParseClaudeResult('{not json', Text, Error));
end;

procedure TAgentCliTest.TestReadClaudeAnswer;
var
  AI: TGittanClaude;
  Text, Error: string;
begin
  AI := TGittanClaude.Create('claude', '', '');
  try
    AssertTrue(AI.ReadAnswer(True, '{"type":"result","subtype":"success",' +
      '"is_error":false,"result":"```\nFix it\n```"}', '', Text, Error));
    AssertEquals('the answer as given; the job cleans it', 'Fix it',
      CleanCommitMessage(Text));
    { An error in the JSON, with exit 1. }
    AssertFalse(AI.ReadAnswer(False, '{"type":"result","subtype":"success",' +
      '"is_error":true,"result":"Not logged in"}', '', Text, Error));
    AssertEquals('Not logged in', Error);
    { No JSON: stderr says why. }
    AssertFalse(AI.ReadAnswer(False, '', 'error: unknown option', Text, Error));
    AssertEquals('error: unknown option', Error);
    AssertFalse('nothing at all', AI.ReadAnswer(True, '', '', Text, Error));
    AssertEquals(Format(rsAgentNoAnswer, ['Claude Code']), Error);
  finally
    AI.Free;
  end;
end;

procedure TAgentCliTest.TestReadCopilotAnswer;
var
  AI: TGittanCopilot;
  Text, Error: string;
begin
  AI := TGittanCopilot.Create('copilot', '', '');
  try
    AssertTrue(AI.ReadAnswer(True, #10'Fix it'#10#10'Body'#10, '', Text, Error));
    AssertEquals('Fix it'#10#10'Body', CleanCommitMessage(Text));
    AssertFalse('a failed run is no answer', AI.ReadAnswer(False, 'partial',
      'No authentication information found.', Text, Error));
    AssertEquals('No authentication information found.', Error);
    AssertFalse(AI.ReadAnswer(True, '  ', '', Text, Error));
    AssertEquals(Format(rsAgentNoAnswer, ['GitHub Copilot']), Error);
  finally
    AI.Free;
  end;
end;

procedure TAgentCliTest.TestFind;
var
  AI: TGittanAI;
begin
  AssertEquals('a path given is taken as it is', '/opt/claude',
    TGittanClaude.Find('/opt/claude'));
  AssertEquals('/opt/copilot', TGittanCopilot.Find('/opt/copilot'));
  AI := TGittanClaude.Create('', '', '');
  try
    AssertFalse('no command, not available', AI.Available);
  finally
    AI.Free;
  end;
  AI := TGittanCopilot.Create('/opt/copilot', '', '');
  try
    AssertTrue(AI.Available);
  finally
    AI.Free;
  end;
  AI := TGittanClaude.Create('', '', '');
  try
    AssertEquals('no command, no version', '', AI.About);
  finally
    AI.Free;
  end;
end;


procedure TAgentCliTest.TestTitle;
var
  AI, Copy: TGittanAI;
begin
  AI := TGittanClaude.Create('/opt/claude', '', 'haiku');
  try
    AssertEquals('a tool is named, not its model', 'Claude Code', AI.Title);
    AssertTrue(AI.Kind = gaClaude);
    Copy := AI.Clone;
    try
      AssertTrue(Copy is TGittanClaude);
      AssertEquals('/opt/claude', Copy.Path);
      AssertEquals('haiku', Copy.Model);
    finally
      Copy.Free;
    end;
  finally
    AI.Free;
  end;
end;

procedure TAgentCliTest.TestVersionOf;
begin
  AssertEquals('2.62.0', VersionOf('gh version 2.62.0 (2024-11-14)' + LineEnding +
    'https://github.com/cli/cli/releases/tag/v2.62.0', 'gh version'));
  AssertEquals('2.1.0', VersionOf('2.1.0 (Claude Code)', ''));
  AssertEquals('', VersionOf('', ''));
end;

initialization

  RegisterTest(TAgentCliTest);
end.
