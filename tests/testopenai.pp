unit testopenai;

{** Tests of gittan.openai: the endpoint, the request body, the answers
  and errors of OpenAI's and OpenRouter's shape, and the agent as the
  settings make it (its server, title and what it needs). No server is
  asked; ChatComplete over gittan.http is tried against a fake server
  by hand. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, fpjson, jsonparser, gittan.ai, gittan.openai;

type
  TOpenAITest = class(TTestCase)
  published
    procedure TestAgent;
    procedure TestChatEndpoint;
    procedure TestChatRequestBody;
    procedure TestParseChatAnswer;
    procedure TestParseChatError;
  end;

implementation

procedure TOpenAITest.TestAgent;
var
  AI: TGittanAI;
begin
  AssertTrue(AIClassOf(gaOpenAI) = TGittanOpenAI);
  AssertTrue(TGittanOpenAI.IsApi);
  AssertFalse('the model sees what it is sent alone', TGittanOpenAI.ReadsFiles);
  AssertEquals('the server when the settings name none', OpenAIDefaultUrl,
    TGittanOpenAI.Find(''));
  AssertEquals('http://localhost:11434/v1', TGittanOpenAI.Find(' http://localhost:11434/v1 '));
  AI := TGittanOpenAI.Create(OpenAIDefaultUrl, 'sk-x', 'gpt-4o-mini');
  try
    AssertEquals('the API is named by its model', 'gpt-4o-mini', AI.Title);
    AssertTrue(AI.Available);
    AssertEquals(Format(rsAboutApi, ['gpt-4o-mini', OpenAIDefaultUrl]), AI.About);
    AssertEquals('sk-x', AI.Key);
    AssertTrue('its prompts say it cannot read files', Pos('cannot open the files',
      AI.Prompt(atReview)) > 0);
  finally
    AI.Free;
  end;
  AI := TGittanOpenAI.Create(OpenAIDefaultUrl, '', '');
  try
    AssertEquals('OpenAI-compatible API', AI.Title);
    AssertFalse('a model is needed', AI.Available);
  finally
    AI.Free;
  end;
end;

procedure TOpenAITest.TestChatEndpoint;
begin
  AssertEquals('https://api.openai.com/v1/chat/completions', ChatEndpoint(OpenAIDefaultUrl));
  AssertEquals('https://openrouter.ai/api/v1/chat/completions',
    ChatEndpoint(' https://openrouter.ai/api/v1/ '));
end;

procedure TOpenAITest.TestChatRequestBody;
var
  Data: TJSONData;
begin
  Data := GetJSON(ChatRequestBody('openai/gpt-4o-mini', 'Write the message.',
    'diff --git "a/x" "b/x"'#10'+ändrad'));
  try
    AssertEquals('openai/gpt-4o-mini', Data.FindPath('model').AsString);
    AssertEquals(2, Data.FindPath('messages').Count);
    AssertEquals('system', Data.FindPath('messages[0].role').AsString);
    AssertEquals('Write the message.', Data.FindPath('messages[0].content').AsString);
    AssertEquals('user', Data.FindPath('messages[1].role').AsString);
    AssertEquals('the quotes, the line end and the UTF-8 come through',
      'diff --git "a/x" "b/x"'#10'+ändrad', Data.FindPath('messages[1].content').AsString);
  finally
    Data.Free;
  end;
end;

procedure TOpenAITest.TestParseChatAnswer;
var
  Text, Error: string;
begin
  AssertTrue(ParseChatAnswer('{"id":"x","choices":[{"index":0,"message":{"role":' +
    '"assistant","content":"\nFix the parser\n"},"finish_reason":"stop"}],' +
    '"usage":{"total_tokens":10}}', Text, Error));
  AssertEquals('Fix the parser', Text);
  AssertEquals('', Error);
  AssertTrue('content in parts', ParseChatAnswer('{"choices":[{"message":{"content":' +
    '[{"type":"text","text":"One "},{"type":"text","text":"two"}]}}]}', Text, Error));
  AssertEquals('One two', Text);
  AssertFalse('no text', ParseChatAnswer('{"choices":[{"message":{"role":"assistant",' +
    '"content":null,"reasoning":"..."},"finish_reason":"length"}]}', Text, Error));
  AssertEquals(rsChatEmpty, Error);
  AssertFalse('no choices', ParseChatAnswer('{"object":"list","data":[]}', Text, Error));
  AssertEquals('', Error);
  AssertFalse('not JSON', ParseChatAnswer('<html>Not Found</html>', Text, Error));
  AssertEquals('', Error);
  AssertFalse(ParseChatAnswer('', Text, Error));
end;

procedure TOpenAITest.TestParseChatError;
var
  Text, Error: string;
begin
  AssertFalse(ParseChatAnswer('{"error":{"message":"Invalid API key.","type":' +
    '"invalid_request_error","code":"invalid_api_key"}}', Text, Error));
  AssertEquals('Invalid API key.', Error);
  AssertEquals('', Text);
  AssertFalse('OpenRouter''s', ParseChatAnswer('{"error":{"message":"No endpoints found",' +
    '"code":404},"user_id":"u"}', Text, Error));
  AssertEquals('No endpoints found', Error);
  AssertFalse('an error as a string', ParseChatAnswer('{"error":"model not found"}',
    Text, Error));
  AssertEquals('model not found', Error);
  AssertFalse('an error beside a choice', ParseChatAnswer('{"error":{"message":' +
    '"Rate limited"},"choices":[{"message":{"content":"Half an answer"}}]}', Text, Error));
  AssertEquals('Rate limited', Error);
  AssertEquals('', Text);
end;

initialization
  RegisterTest(TOpenAITest);
end.
