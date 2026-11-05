unit testextengine;

{** Tests of gittan.ext.engine with a host of the tests' own
  (TFakeExtHost): a script's commands reach the registry and run with
  their context, a listener cancels an event or not, the dialogs reach
  the host, a permission left out leaves its natives out, and an unload
  empties the registry. The engine is one for the process (a released
  instance cannot be made again), unloaded between tests. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.ext.quickjs, gittan.ext.engine,
  gittan.ext.host, gittan.ext.registry, gittan.ext.perm, gittan.reviews;

type

  { TFakeExtHost }

  TFakeExtHost = class(TGittanExtHost)
  public
    Alerts, AlertNames, Errors, Logs: TStringList;
    { Each permission prompt as "name|author|perms", each banner as
      "title|detail|0 or 1" and each card as "path|line|text|severity|ext". }
    Asked, Notified, Cards: TStringList;
    { Each answer of a tab or an operation as "seq|ext|json". }
    Delivered: TStringList;
    { What ForgeViewForge answers. }
    ViewForge: string;
    Status, Cleared: string;
    ConfirmAnswer, PermissionAnswer: boolean;
    PromptAnswer: string;
    SelectAnswer, Changed: integer;
    { Run as a permission is asked, while the real host's dialog is up. }
    OnAsk: procedure of object;
    constructor Create;
    destructor Destroy; override;
    procedure Alert(const AName, AText: string); override;
    function Confirm(const AName, AText: string): boolean; override;
    function Prompt(const ACaption, AText, ADefault: string; out AValue: string): boolean; override;
    function Select(const ACaption, AText: string; const AOptions: array of string): integer; override;
    procedure ShowLog(const ATitle, AText: string); override;
    procedure ReportError(const ATitle, ADetail: string); override;
    function AskPermission(const AName, AFile, AAuthor: string;
      const ARequested: TExtPermSet): boolean; override;
    procedure AddCard(const ARoot: string; const ACard: TGittanReviewThread); override;
    procedure ClearCards(const ARoot, AExtId: string); override;
    procedure SetStatus(const ARoot, AText: string; ASeconds: integer); override;
    procedure Notify(const ARoot, ATitle, ADetail: string; AError: boolean); override;
    procedure CommandsChanged; override;
    function ForgeViewForge: string; override;
    procedure Deliver(ASeq: integer; const AExtId, AJson: string); override;
  end;

  { TExtEngineTest }

  TExtEngineTest = class(TTestCase)
  private
    FHost: TFakeExtHost;
    FDir: string;
    FEngine: TGittanExtEngine;
    function Load(const AName, AScript: string; AGranted: TExtPermSet): PExtContextInfo;
    function LoadResult(const AName, AScript: string): string;
    function EvalIn(ctx: JSContext; const ASrc: string): string;
    { The result of a load is the script's last value; an error starts
      with Error:. }
    procedure AssertLoaded(const AMsg, AResult: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCommandRegisteredAndRun;
    procedure TestCommandUnregister;
    procedure TestListenerCancels;
    procedure TestListenerScopedToRepos;
    procedure TestListenerFalseAndObject;
    procedure TestListenerThrowDoesNotCancel;
    procedure TestOff;
    procedure TestUnknownEvent;
    procedure TestDialogsReachHost;
    procedure TestPermissionGate;
    procedure TestUnloadClearsRegistry;
    procedure TestEveryListenerIsCalled;
    procedure TestPayloadWithoutData;
    procedure TestListenerScopedToForges;
    procedure TestForgeTabsAndBatch;
  end;

implementation

uses
  testhelpers;

{ TFakeExtHost }

constructor TFakeExtHost.Create;
begin
  inherited Create;
  Alerts := TStringList.Create;
  AlertNames := TStringList.Create;
  Errors := TStringList.Create;
  Logs := TStringList.Create;
  Asked := TStringList.Create;
  Notified := TStringList.Create;
  Cards := TStringList.Create;
  Delivered := TStringList.Create;
  SelectAnswer := -1;
end;

destructor TFakeExtHost.Destroy;
begin
  Delivered.Free;
  Cards.Free;
  Notified.Free;
  Asked.Free;
  Logs.Free;
  Errors.Free;
  AlertNames.Free;
  Alerts.Free;
  inherited Destroy;
end;

procedure TFakeExtHost.Alert(const AName, AText: string);
begin
  Alerts.Add(AText);
  AlertNames.Add(AName);
end;

function TFakeExtHost.Confirm(const AName, AText: string): boolean;
begin
  Alerts.Add('confirm:' + AText);
  Result := ConfirmAnswer;
end;

function TFakeExtHost.Prompt(const ACaption, AText, ADefault: string;
  out AValue: string): boolean;
begin
  AValue := PromptAnswer;
  Result := PromptAnswer <> '';
end;

function TFakeExtHost.Select(const ACaption, AText: string;
  const AOptions: array of string): integer;
begin
  Result := SelectAnswer;
end;

procedure TFakeExtHost.ShowLog(const ATitle, AText: string);
begin
  Logs.Add(ATitle + ': ' + AText);
end;

procedure TFakeExtHost.ReportError(const ATitle, ADetail: string);
begin
  Errors.Add(ATitle + ': ' + ADetail);
end;

function TFakeExtHost.AskPermission(const AName, AFile, AAuthor: string;
  const ARequested: TExtPermSet): boolean;
begin
  Asked.Add(AName + '|' + AAuthor + '|' + PermSetToCSV(ARequested));
  if Assigned(OnAsk) then
    OnAsk();
  Result := PermissionAnswer;
end;

procedure TFakeExtHost.AddCard(const ARoot: string; const ACard: TGittanReviewThread);
begin
  Cards.Add(ACard.Path + '|' + IntToStr(ACard.Line) + '|' + ACard.Comments[0].Body + '|' +
    ACard.Severity + '|' + ACard.Extension);
end;

procedure TFakeExtHost.ClearCards(const ARoot, AExtId: string);
begin
  Cleared := AExtId;
end;

procedure TFakeExtHost.SetStatus(const ARoot, AText: string; ASeconds: integer);
begin
  Status := AText + '|' + IntToStr(ASeconds);
end;

procedure TFakeExtHost.Notify(const ARoot, ATitle, ADetail: string; AError: boolean);
begin
  Notified.Add(ATitle + '|' + ADetail + '|' + IntToStr(Ord(AError)));
end;

procedure TFakeExtHost.CommandsChanged;
begin
  Inc(Changed);
end;

function TFakeExtHost.ForgeViewForge: string;
begin
  Result := ViewForge;
end;

procedure TFakeExtHost.Deliver(ASeq: integer; const AExtId, AJson: string);
begin
  Delivered.Add(IntToStr(ASeq) + '|' + AExtId + '|' + AJson);
end;

{ TExtEngineTest }

procedure TExtEngineTest.SetUp;
begin
  FHost := TFakeExtHost.Create;
  SetExtHost(FHost);
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-extengine-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
  FEngine := TGittanExtEngine.Instance;
  AssertNotNull('engine', FEngine);
end;

procedure TExtEngineTest.TearDown;
begin
  FEngine.UnloadExtensions;
  SetExtHost(nil);
  FHost := nil;
  RemoveTree(FDir);
end;

function TExtEngineTest.Load(const AName, AScript: string;
  AGranted: TExtPermSet): PExtContextInfo;
var
  FileName: string;
  Lines: TStringList;
begin
  FileName := IncludeTrailingPathDelimiter(FDir) + AName + '.js';
  Lines := TStringList.Create;
  try
    Lines.Text := AScript;
    Lines.SaveToFile(FileName);
  finally
    Lines.Free;
  end;
  Result := FEngine.NewExtensionContext(ExtIdFromPath(FileName), FileName,
    HashScript(AScript), AName, 'tests', AGranted);
  AssertNotNull('context of ' + AName, Result);
end;

function TExtEngineTest.LoadResult(const AName, AScript: string): string;
begin
  Result := string(FEngine.ExtExecuteFile(Load(AName, AScript, PermBaseline + [epData])));
end;

function TExtEngineTest.EvalIn(ctx: JSContext; const ASrc: string): string;
var
  v: JSValue;
  err: RawUtf8;
begin
  v := ctx^.Eval(RawUtf8(ASrc), 'test.js', JS_EVAL_TYPE_GLOBAL, err);
  if v.IsException then
    Exit('exception: ' + string(err));
  Result := string(JS_ToUtf8(ctx, v));
  ctx^.Free(v);
end;

procedure TExtEngineTest.AssertLoaded(const AMsg, AResult: string);
begin
  AssertTrue(AMsg + ': ' + AResult, Pos('Error:', AResult) <> 1);
end;

procedure TExtEngineTest.TestCommandRegisteredAndRun;
var
  Info: PExtContextInfo;
  Cmd: TGittanExtCommand;
begin
  Info := Load('hello', 'Gittan.commands.register({id: "hi", title: "Say Hi", ' +
    'where: ["menu", "file"], run: function (c) { globalThis.ran = c.repo + ":" + c.path; }});',
    PermBaseline);
  AssertLoaded('loads', string(FEngine.ExtExecuteFile(Info)));
  AssertEquals('one command', 1, FEngine.Registry.CommandCount);
  AssertEquals('menus told', 1, FHost.Changed);
  Cmd := FEngine.Registry.Command(0);
  AssertEquals('ext id', 'hello', Cmd.ExtId);
  AssertEquals('id', 'hi', Cmd.Id);
  AssertEquals('title', 'Say Hi', Cmd.Title);
  AssertTrue('in the menu', cwMenu in Cmd.Where);
  AssertTrue('in the file popup', cwFilePopup in Cmd.Where);
  AssertFalse('not in the editor popup', cwEditorPopup in Cmd.Where);
  AssertTrue('runs', FEngine.RunCommand(TGittanExtRegistry.CommandKey('hello', 'hi'),
    '{"repo": "/r", "path": "a.txt"}'));
  AssertEquals('got its context', '/r:a.txt', EvalIn(Info^.Ctx, 'globalThis.ran'));
  AssertFalse('no such command', FEngine.RunCommand('hello'#9'nope', '{}'));
end;

procedure TExtEngineTest.TestCommandUnregister;
var
  Info: PExtContextInfo;
begin
  Info := Load('cmds', 'Gittan.commands.register({id: "a", title: "A", run: function () {}});' +
    'Gittan.commands.register({id: "b", title: "B", run: function () {}});' +
    'globalThis.gone = Gittan.commands.unregister("a");' +
    'globalThis.again = Gittan.commands.unregister("a");', PermBaseline);
  AssertLoaded('loads', string(FEngine.ExtExecuteFile(Info)));
  AssertEquals('one left', 1, FEngine.Registry.CommandCount);
  AssertEquals('b left', 'b', FEngine.Registry.Command(0).Id);
  AssertEquals('was there', 'true', EvalIn(Info^.Ctx, 'globalThis.gone'));
  AssertEquals('not twice', 'false', EvalIn(Info^.Ctx, 'globalThis.again'));
  AssertEquals('menus told each time', 3, FHost.Changed);
end;

procedure TExtEngineTest.TestListenerCancels;
var
  Msg: string;
begin
  AssertLoaded('loads', LoadResult('lint',
    'Gittan.on("commit.before", function (p) { ' +
    'if (p.message.length > 10) return "Subject too long: " + p.message.length; });'));
  AssertEquals('one listener', 1, FEngine.Registry.ListenerCount);
  AssertTrue('listened to', FEngine.Registry.HasListener('commit.before'));
  AssertFalse('another not', FEngine.Registry.HasListener('commit.after'));
  AssertTrue('short goes', FEngine.Fire('commit.before', '{"message": "short"}', Msg));
  AssertEquals('no message', '', Msg);
  AssertFalse('long is stopped', FEngine.Fire('commit.before',
    '{"message": "a rather long subject"}', Msg));
  AssertEquals('its reason', 'Subject too long: 21', Msg);
  AssertTrue('other events untouched', FEngine.Fire('push.before', '{}', Msg));
end;

procedure TExtEngineTest.TestListenerScopedToRepos;
const
  Urls = 'remote.origin.url git@github.com:slicke/gittan.git'#10;
var
  Info: PExtContextInfo;
  Msg: string;
begin
  Info := Load('scoped', 'Gittan.on("commit.before", function () { return "stopped"; });',
    PermBaseline + [epData]);
  Info^.Repos := ['github.com/slicke/*'];
  AssertLoaded('loads', string(FEngine.ExtExecuteFile(Info)));
  AssertTrue('listens for its remote', FEngine.Listens('commit.before', '/a', Urls));
  AssertFalse('not for another', FEngine.Listens('commit.before', '/b', ''));
  AssertTrue('in scope', FEngine.ExtInScope('scoped', '/a', Urls));
  AssertFalse('out of scope', FEngine.ExtInScope('scoped', '/b', ''));
  AssertFalse('its repository is stopped', FEngine.Fire('commit.before', '{}', '/a', Urls, Msg));
  AssertEquals('its reason', 'stopped', Msg);
  AssertTrue('another goes', FEngine.Fire('commit.before', '{}', '/b', '', Msg));
  AssertFalse('unscoped reaches it', FEngine.Fire('commit.before', '{}', Msg));
end;

procedure TExtEngineTest.TestListenerFalseAndObject;
var
  Msg: string;
begin
  AssertLoaded('loads', LoadResult('cancel',
    'Gittan.on("push.before", function (p) { return p.kind === "force" ? false : undefined; });' +
    'Gittan.on("pull.before", function (p) { return {cancel: p.stop, message: "not now"}; });'));
  AssertFalse('false cancels', FEngine.Fire('push.before', '{"kind": "force"}', Msg));
  AssertEquals('no reason', '', Msg);
  AssertTrue('undefined does not', FEngine.Fire('push.before', '{"kind": "push"}', Msg));
  AssertFalse('object cancels', FEngine.Fire('pull.before', '{"stop": true}', Msg));
  AssertEquals('its message', 'not now', Msg);
  AssertTrue('object without cancel does not', FEngine.Fire('pull.before',
    '{"stop": false}', Msg));
end;

procedure TExtEngineTest.TestListenerThrowDoesNotCancel;
var
  Msg: string;
begin
  AssertLoaded('loads', LoadResult('broken',
    'Gittan.on("commit.before", function () { throw new Error("oops"); });'));
  FEngine.ClearOutput;
  AssertTrue('a throw does not cancel', FEngine.Fire('commit.before', '{}', Msg));
  AssertTrue('the throw is in the output: ' + string(FEngine.Output),
    Pos('oops', string(FEngine.Output)) > 0);
end;

procedure TExtEngineTest.TestOff;
var
  Info: PExtContextInfo;
begin
  Info := Load('off', 'function f() {} Gittan.on("repo.changed", f);' +
    'globalThis.first = Gittan.off("repo.changed", f);' +
    'globalThis.second = Gittan.off("repo.changed", f);', PermBaseline);
  AssertLoaded('loads', string(FEngine.ExtExecuteFile(Info)));
  AssertEquals('none left', 0, FEngine.Registry.ListenerCount);
  AssertEquals('was listening', 'true', EvalIn(Info^.Ctx, 'globalThis.first'));
  AssertEquals('not twice', 'false', EvalIn(Info^.Ctx, 'globalThis.second'));
end;

procedure TExtEngineTest.TestUnknownEvent;
var
  Res: string;
begin
  Res := LoadResult('unknown', 'Gittan.on("nope", function () {});');
  AssertTrue('refused: ' + Res, Pos('Error:', Res) = 1);
  AssertTrue('names the event: ' + Res, Pos('unknown event "nope"', Res) > 0);
  AssertEquals('reported to the host', 1, FHost.Errors.Count);
  AssertEquals('nothing kept', 0, FEngine.Registry.ListenerCount);
end;

procedure TExtEngineTest.TestDialogsReachHost;
var
  Info: PExtContextInfo;
begin
  FHost.ConfirmAnswer := True;
  FHost.PromptAnswer := 'typed';
  FHost.SelectAnswer := 1;
  Info := Load('dialogs', 'alert("one"); Gittan.alert("two", 3);' +
    'globalThis.c = Gittan.confirm("sure?");' +
    'globalThis.p = Gittan.prompt("Name", "Your name", "x");' +
    'globalThis.s = Gittan.select("Pick", "One of", "a", "b", "c");' +
    'console.log("logged");', PermBaseline);
  AssertLoaded('loads', string(FEngine.ExtExecuteFile(Info)));
  AssertEquals('alerts', 'one,two3,confirm:sure?', FHost.Alerts.CommaText);
  AssertEquals('alerts name the extension', 'dialogs', FHost.AlertNames[0]);
  AssertEquals('confirm answer', 'true', EvalIn(Info^.Ctx, 'globalThis.c'));
  AssertEquals('prompt answer', 'typed', EvalIn(Info^.Ctx, 'globalThis.p'));
  AssertEquals('select answer', '1', EvalIn(Info^.Ctx, 'globalThis.s'));
  AssertEquals('console.log shown', 1, FHost.Logs.Count);
  AssertTrue('with its text', Pos('logged', FHost.Logs[0]) > 0);
  AssertEquals('under the extension''s name', 'Extension "dialogs" · console.log: logged', FHost.Logs[0]);
end;

procedure TExtEngineTest.TestPermissionGate;
var
  NoUI, WithUI: PExtContextInfo;
begin
  NoUI := Load('noui', '', [epTimers]);
  WithUI := Load('withui', '', PermBaseline);
  AssertEquals('no commands without ui', 'undefined',
    EvalIn(NoUI^.Ctx, 'typeof Gittan.commands'));
  AssertEquals('no registerCommand without ui', 'undefined',
    EvalIn(NoUI^.Ctx, 'typeof Gittan.registerCommand'));
  AssertEquals('no alert without ui', 'undefined', EvalIn(NoUI^.Ctx, 'typeof alert'));
  AssertEquals('on always', 'function', EvalIn(NoUI^.Ctx, 'typeof Gittan.on'));
  AssertEquals('commands with ui', 'object', EvalIn(WithUI^.Ctx, 'typeof Gittan.commands'));
  AssertEquals('alert with ui', 'function', EvalIn(WithUI^.Ctx, 'typeof alert'));
end;

procedure TExtEngineTest.TestUnloadClearsRegistry;
begin
  AssertLoaded('loads', LoadResult('bye',
    'Gittan.commands.register({id: "x", title: "X", run: function () {}});' +
    'Gittan.on("repo.opened", function () {});' +
    'Gittan.on("unload", function () { Gittan.alert("bye"); });'));
  AssertEquals('a command', 1, FEngine.Registry.CommandCount);
  AssertEquals('two listeners', 2, FEngine.Registry.ListenerCount);
  FEngine.UnloadExtensions;
  AssertEquals('unload reached the script', 'bye', FHost.Alerts.CommaText);
  AssertEquals('no command', 0, FEngine.Registry.CommandCount);
  AssertEquals('no listener', 0, FEngine.Registry.ListenerCount);
  AssertEquals('no context', 0, FEngine.ExtensionCount);
end;

procedure TExtEngineTest.TestEveryListenerIsCalled;
var
  Msg: string;
begin
  AssertLoaded('first loads', LoadResult('first',
    'Gittan.on("commit.before", function () { Gittan.alert("first"); return "stop"; });'));
  AssertLoaded('second loads', LoadResult('second',
    'Gittan.on("commit.before", function () { Gittan.alert("second"); return "too"; });'));
  AssertFalse('cancelled', FEngine.Fire('commit.before', '{}', Msg));
  AssertEquals('the first reason', 'stop', Msg);
  AssertEquals('both called', 'first,second', FHost.Alerts.CommaText);
end;

{ A listener without data gets what happened, not the content. }
procedure TExtEngineTest.TestPayloadWithoutData;
var
  NoData, WithData: PExtContextInfo;
  Msg: string;
begin
  NoData := Load('nodata', 'Gittan.on("commit.after", function (p) { globalThis.got = JSON.stringify(p); });',
    PermBaseline);
  AssertLoaded('nodata loads', string(FEngine.ExtExecuteFile(NoData)));
  WithData := Load('withdata', 'Gittan.on("commit.after", function (p) { globalThis.got = JSON.stringify(p); });',
    PermBaseline + [epData]);
  AssertLoaded('withdata loads', string(FEngine.ExtExecuteFile(WithData)));
  FEngine.Fire('commit.after', '{"repo": "/r", "ok": true, "id": "abc", "amend": false, "message": "secret"}', Msg);
  AssertEquals('only what happened', '{"ok":true,"amend":false}', EvalIn(NoData^.Ctx, 'globalThis.got'));
  AssertEquals('everything', '{"repo":"/r","ok":true,"id":"abc","amend":false,"message":"secret"}',
    EvalIn(WithData^.Ctx, 'globalThis.got'));
end;

{ @forges keeps an extension to the repositories whose remotes are on
  those forges (GitHub is registered in the tests, testgithub), and to
  the forge view of those forges. }
procedure TExtEngineTest.TestListenerScopedToForges;
const
  OnGitHub = 'remote.origin.url git@github.com:slicke/gittan.git'#10;
  Elsewhere = 'remote.origin.url https://git.example.net/a/b.git'#10;
var
  Info: PExtContextInfo;
begin
  Info := Load('forged', 'Gittan.on("commit.before", function () { return "stopped"; });',
    PermBaseline + [epData]);
  Info^.Forges := ['github'];
  AssertLoaded('loads', string(FEngine.ExtExecuteFile(Info)));
  AssertTrue('a repository on GitHub', FEngine.ExtInScope('forged', '/a', OnGitHub));
  AssertTrue('listens there', FEngine.Listens('commit.before', '/a', OnGitHub));
  AssertFalse('not on another host', FEngine.ExtInScope('forged', '/b', Elsewhere));
  AssertFalse('not without a remote', FEngine.ExtInScope('forged', '/c', ''));
  AssertFalse('nor listens there', FEngine.Listens('commit.before', '/c', ''));
  AssertTrue('the forge view of GitHub', FEngine.ExtForgeInScope('forged', 'GitHub'));
  AssertFalse('of another forge', FEngine.ExtForgeInScope('forged', 'GitLab'));
  AssertFalse('one not loaded', FEngine.ExtForgeInScope('nope', 'GitHub'));
end;

{ A tab and an operation are kept beside a command of the same id, and
  their functions answer through _deliver, a promise's value or its
  error, with the request's seq. }
procedure TExtEngineTest.TestForgeTabsAndBatch;
var
  Info: PExtContextInfo;
  Tabs: TGittanExtCommands;
begin
  Info := Load('forgy',
    'Gittan.commands.register({id: "prs", title: "Mine", where: "forge", run: function () {}});' +
    'Gittan.forgeTabs.register({id: "prs", title: "Old PRs", description: "Stale ones",' +
    '  render: function (c) { return Promise.resolve({rows: [{title: c.forge + "/" + c.login}]}); },' +
    '  action: function (a, row, c) { return a + ":" + row.title; }});' +
    'Gittan.batch.register({id: "b", title: "Count", run: function (c) {' +
    '  if (c.repo === "/bad") throw new Error("boom"); return c.repo + "!"; }});' +
    'globalThis.typeOk = typeof Gittan._deliver;', PermBaseline);
  AssertLoaded('loads', string(FEngine.ExtExecuteFile(Info)));
  AssertEquals('deliver out of reach', 'undefined', EvalIn(Info^.Ctx, 'globalThis.typeOk'));
  AssertEquals('three', 3, FEngine.Registry.CommandCount);
  Tabs := FEngine.Registry.CommandsIn(cwForgeTab);
  AssertEquals('one tab', 1, Length(Tabs));
  AssertEquals('its title', 'Old PRs', Tabs[0].Title);
  AssertEquals('its note', 'Stale ones', Tabs[0].Note);
  AssertEquals('one operation', 1, Length(FEngine.Registry.CommandsIn(cwBatch)));
  AssertEquals('one forge command', 1, Length(FEngine.Registry.CommandsIn(cwForge)));
  AssertEquals('not in the frames'' menu', 0, Length(FEngine.Registry.CommandsIn(cwMenu)));

  AssertTrue('renders', FEngine.RunCommand(TGittanExtRegistry.KindKey('forgy', 'prs', cwForgeTab),
    '{"seq": 7, "kind": "render", "forge": "GitHub", "login": "octo"}'));
  AssertEquals('rendered', '7|forgy|{"value":{"rows":[{"title":"GitHub/octo"}]}}',
    FHost.Delivered.Text.Trim);
  FHost.Delivered.Clear;
  FEngine.RunCommand(TGittanExtRegistry.KindKey('forgy', 'prs', cwForgeTab),
    '{"seq": 8, "kind": "action", "action": "close", "row": {"title": "x"}}');
  AssertEquals('acted', '8|forgy|{"value":"close:x"}', FHost.Delivered.Text.Trim);
  FHost.Delivered.Clear;
  FEngine.RunCommand(TGittanExtRegistry.KindKey('forgy', 'b', cwBatch), '{"seq": 9, "repo": "/r"}');
  FEngine.RunCommand(TGittanExtRegistry.KindKey('forgy', 'b', cwBatch), '{"seq": 10, "repo": "/bad"}');
  AssertEquals('ran', '9|forgy|{"value":"/r!"}', FHost.Delivered[0]);
  AssertEquals('threw', '10|forgy|{"error":"boom"}', FHost.Delivered[1]);

  AssertEquals('the command goes alone', 'true', EvalIn(Info^.Ctx, 'String(Gittan.commands.unregister("prs"))'));
  AssertEquals('the tab stays', 1, Length(FEngine.Registry.CommandsIn(cwForgeTab)));
  AssertEquals('then the tab', 'true', EvalIn(Info^.Ctx, 'String(Gittan.forgeTabs.unregister("prs"))'));
  AssertEquals('the operation stays', 1, FEngine.Registry.CommandCount);
end;

initialization
  RegisterTest(TExtEngineTest);

finalization
  TGittanExtEngine.ReleaseInstance;

end.
