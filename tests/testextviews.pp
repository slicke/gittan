unit testextviews;

{** Tests of gittan.ext.views: a delivered answer read, a tab's model in
  each of its shapes, and an operation's result. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, fpjson, gittan.ext.views;

type
  TExtViewsTest = class(TTestCase)
  published
    procedure TestReadAnswer;
    procedure TestTabModel;
    procedure TestTabModelShapes;
    procedure TestBatchResult;
    procedure TestBatchResultFalsy;
    procedure TestWebUrlOnly;
  end;

implementation

procedure TExtViewsTest.TestReadAnswer;
var
  V: TJSONData;
  Err: string;
begin
  AssertTrue('a value', ReadExtAnswer('{"value": "x"}', V, Err));
  try
    AssertEquals('its text', 'x', V.AsString);
  finally
    V.Free;
  end;
  AssertTrue('null', ReadExtAnswer('{"value": null}', V, Err));
  try
    AssertTrue('as null', V.JSONType = jtNull);
  finally
    V.Free;
  end;
  AssertFalse('an error', ReadExtAnswer('{"error": "boom"}', V, Err));
  AssertEquals('its message', 'boom', Err);
  AssertNull('no value', V);
  AssertFalse('not JSON', ReadExtAnswer('nope', V, Err));
end;

procedure TExtViewsTest.TestTabModel;
var
  V: TJSONData;
  M: TExtTabModel;
begin
  V := GetJSON('{"text": "Stale", "empty": "None", "rows": [' +
    '{"title": "#12 Fix", "detail": "3 weeks", "tag": "draft", "url": "https://x/12",' +
    ' "severity": "warn", "actions": [{"id": "close", "title": "Close"}, {"title": "no id"}, {"id": "ping"}]},' +
    '"plain", 42, {}]}');
  try
    AssertTrue('a model', ExtTabModelOf(V, M));
  finally
    V.Free;
  end;
  AssertEquals('text', 'Stale', M.Text);
  AssertEquals('empty', 'None', M.Empty);
  AssertEquals('two rows: a number and an empty object are none', 2, Length(M.Rows));
  AssertEquals('title', '#12 Fix', M.Rows[0].Title);
  AssertEquals('detail', '3 weeks', M.Rows[0].Detail);
  AssertEquals('tag', 'draft', M.Rows[0].Tag);
  AssertEquals('url', 'https://x/12', M.Rows[0].Url);
  AssertTrue('warn', M.Rows[0].Severity = esWarn);
  AssertEquals('two actions, one without an id left out', 2, Length(M.Rows[0].Actions));
  AssertEquals('its title', 'Close', M.Rows[0].Actions[0].Title);
  AssertEquals('the id for a title', 'ping', M.Rows[0].Actions[1].Title);
  AssertTrue('the row kept for an action', Pos('"#12 Fix"', M.Rows[0].Json) > 0);
  AssertEquals('a string row', 'plain', M.Rows[1].Title);
end;

procedure TExtViewsTest.TestTabModelShapes;
var
  V: TJSONData;
  M: TExtTabModel;
begin
  V := GetJSON('[{"title": "a"}]');
  try
    AssertTrue('a list of rows', ExtTabModelOf(V, M));
    AssertEquals('one', 1, Length(M.Rows));
  finally
    V.Free;
  end;
  V := GetJSON('"just words"');
  try
    AssertTrue('a string', ExtTabModelOf(V, M));
    AssertEquals('as the text', 'just words', M.Text);
  finally
    V.Free;
  end;
  V := TJSONNull.Create;
  try
    AssertFalse('null is no model', ExtTabModelOf(V, M));
  finally
    V.Free;
  end;
  V := GetJSON('{"done": true}');
  try
    AssertFalse('an object without rows or text', ExtTabModelOf(V, M));
  finally
    V.Free;
  end;
end;

procedure TExtViewsTest.TestBatchResult;
var
  V: TJSONData;
  R: TExtBatchResult;
begin
  R := ExtBatchResultOf(nil);
  AssertFalse('nothing', R.Said);
  V := GetJSON('"  "');
  try
    AssertFalse('blank says nothing', ExtBatchResultOf(V).Said);
  finally
    V.Free;
  end;
  V := GetJSON('"2 open pull requests"');
  try
    R := ExtBatchResultOf(V);
    AssertTrue('said', R.Said);
    AssertEquals('text', '2 open pull requests', R.Text);
    AssertTrue('info', R.Severity = esInfo);
  finally
    V.Free;
  end;
  V := GetJSON('{"text": "No branch protection", "severity": "error", "url": "https://x"}');
  try
    R := ExtBatchResultOf(V);
    AssertTrue('error', R.Severity = esError);
    AssertEquals('url', 'https://x', R.Url);
  finally
    V.Free;
  end;
end;

procedure TExtViewsTest.TestBatchResultFalsy;

  function SaidOf(const AJson: string): boolean;
  var
    V: TJSONData;
  begin
    V := GetJSON(AJson);
    try
      Result := ExtBatchResultOf(V).Said;
    finally
      V.Free;
    end;
  end;

begin
  AssertFalse('false says nothing', SaidOf('false'));
  AssertFalse('true says nothing', SaidOf('true'));
  AssertFalse('0 says nothing', SaidOf('0'));
  AssertTrue('3 is said', SaidOf('3'));
end;

procedure TExtViewsTest.TestWebUrlOnly;
var
  V: TJSONData;
  M: TExtTabModel;
begin
  AssertEquals('https', 'https://x/1', ExtWebUrl('https://x/1'));
  AssertEquals('http in capitals', 'HTTP://x', ExtWebUrl('HTTP://x'));
  AssertEquals('file', '', ExtWebUrl('file:///Applications/Calculator.app'));
  AssertEquals('a path', '', ExtWebUrl('/Users/x/run.command'));
  AssertEquals('another scheme', '', ExtWebUrl('vscode://file/x'));
  V := GetJSON('[{"title": "a", "url": "file:///etc/passwd"}]');
  try
    AssertTrue('a model', ExtTabModelOf(V, M));
    AssertEquals('the row keeps no file link', '', M.Rows[0].Url);
  finally
    V.Free;
  end;
  V := GetJSON('{"text": "x", "url": "ssh://h"}');
  try
    AssertEquals('the result keeps no other scheme', '', ExtBatchResultOf(V).Url);
  finally
    V.Free;
  end;
end;

initialization
  RegisterTest(TExtViewsTest);

end.
