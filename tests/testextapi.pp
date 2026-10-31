unit testextapi;

{** Tests of gittan.ext.api against a temporary repository made with the
  real git and the fake host of testextengine: the repository reads,
  git and a program run through the promises, the extension's own
  values and settings, and what a permission left out hides. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.ext.quickjs, gittan.ext.engine,
  gittan.ext.host, gittan.ext.perm, gittan.ext.api, gittan.ext.registry, gittan.git,
  gittan.settings, testextengine;

type
  { The fake host with a repository. }
  TRepoFakeHost = class(TFakeExtHost)
  public
    Root: string;
    Repo: TGittanRepo;
    function ActiveRoot: string; override;
    function RepoFor(const ARoot: string): TGittanRepo; override;
    function StatsFor(const ARoot: string): TGittanFileStats; override;
  end;

  TExtApiTest = class(TTestCase)
  private
    FHost: TRepoFakeHost;
    FDir, FRepoDir: string;
    FSettings: TGittanSettings;
    FEngine: TGittanExtEngine;
    FRepo: TGittanRepo;
    procedure Git(const AArgs: array of string);
    function Load(const AName, AScript: string; AGranted: TExtPermSet): PExtContextInfo;
    function EvalIn(ctx: JSContext; const ASrc: string): string;
    { Runs the engine's queue and the thread's Synchronize until AExpr
      is true in ctx, or a few seconds pass. }
    procedure WaitFor(ctx: JSContext; const AExpr: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSnapshotAndFiles;
    procedure TestRecentAndCommit;
    procedure TestBranchesTagsRemotes;
    procedure TestFileTextAndDiff;
    procedure TestGitRun;
    procedure TestExecRun;
    procedure TestStorage;
    procedure TestSettings;
    procedure TestPermissionsShape;
    procedure TestUiNatives;
  end;

implementation

uses
  testhelpers;

const
  AllPerms: TExtPermSet = [epData, epUI, epTimers, epNet, epExec, epSettings];

{ TRepoFakeHost }

function TRepoFakeHost.ActiveRoot: string;
begin
  Result := Root;
end;

function TRepoFakeHost.RepoFor(const ARoot: string): TGittanRepo;
begin
  if SameFileName(ExcludeTrailingPathDelimiter(ARoot), ExcludeTrailingPathDelimiter(Root)) then
    Result := Repo
  else
    Result := nil;
end;

function TRepoFakeHost.StatsFor(const ARoot: string): TGittanFileStats;
begin
  Result := nil;
  if RepoFor(ARoot) <> nil then
    Repo.ChangeStats(Result);
end;

{ TExtApiTest }

procedure TExtApiTest.Git(const AArgs: array of string);
var
  Output, Error: string;
begin
  Error := '';
  if not RunGitIn(FRepoDir, AArgs, Output, Error) then
    Fail('git ' + AArgs[0] + ': ' + Error);
end;

procedure TExtApiTest.SetUp;
var
  Lines: TStringList;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-extapi-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  FRepoDir := IncludeTrailingPathDelimiter(FDir) + 'repo';
  ForceDirectories(FRepoDir);
  Git(['init', '-q', '-b', 'main']);
  Lines := TStringList.Create;
  try
    Lines.Text := 'one' + LineEnding + 'two' + LineEnding;
    Lines.SaveToFile(IncludeTrailingPathDelimiter(FRepoDir) + 'a.txt');
  finally
    Lines.Free;
  end;
  Git(['add', 'a.txt']);
  Git(['commit', '-q', '-m', 'first', '-m', 'the body']);
  Git(['tag', 'v1']);
  FRepo := TGittanRepo.Create;
  AssertTrue('opens', FRepo.Open(FRepoDir));
  FHost := TRepoFakeHost.Create;
  FHost.Root := FRepo.Root;
  FHost.Repo := FRepo;
  FHost.PermissionAnswer := True;
  SetExtHost(FHost);
  FSettings := TGittanSettings.Create(IncludeTrailingPathDelimiter(FDir) + 'gittan.ini');
  FEngine := TGittanExtEngine.Instance;
  AssertNotNull('engine', FEngine);
end;

procedure TExtApiTest.TearDown;
begin
  FEngine.UnloadExtensions;
  SetExtHost(nil);
  FSettings.Free;
  FRepo.Free;
  RemoveTree(FDir);
end;

function TExtApiTest.Load(const AName, AScript: string; AGranted: TExtPermSet): PExtContextInfo;
var
  FileName, Res: string;
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
  AssertNotNull('context', Result);
  FEngine.BeginRegistration(Result);
  try
    RegisterGittanApi(FEngine, Result, FSettings);
  finally
    FEngine.EndRegistration;
  end;
  Res := string(FEngine.ExtExecuteFile(Result));
  AssertTrue('loads: ' + Res, Pos('Error:', Res) <> 1);
end;

function TExtApiTest.EvalIn(ctx: JSContext; const ASrc: string): string;
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

procedure TExtApiTest.WaitFor(ctx: JSContext; const AExpr: string);
var
  i: integer;
begin
  for i := 1 to 600 do
  begin
    CheckSynchronize(10);
    FEngine.PumpJobs;
    if EvalIn(ctx, 'String(!!(' + AExpr + '))') = 'true' then
      Exit;
  end;
  Fail('timed out waiting for ' + AExpr);
end;

procedure TExtApiTest.TestSnapshotAndFiles;
var
  Info: PExtContextInfo;
  Lines: TStringList;
begin
  Info := Load('snap', 'globalThis.s = Gittan.repo.snapshot(); globalThis.r = Gittan.repo.root();',
    AllPerms);
  AssertEquals('root', FRepo.Root, EvalIn(Info^.Ctx, 'globalThis.r'));
  AssertEquals('branch', 'main', EvalIn(Info^.Ctx, 's.branch'));
  AssertEquals('ok', 'true', EvalIn(Info^.Ctx, 'String(s.ok)'));
  AssertEquals('a head', '40', EvalIn(Info^.Ctx, 'String(s.head.length)'));
  AssertEquals('clean', '0', EvalIn(Info^.Ctx, 'String(s.files.length)'));
  AssertEquals('recent', 'first', EvalIn(Info^.Ctx, 's.recent[0].subject'));
  AssertEquals('refs', 'true', EvalIn(Info^.Ctx, 'String(s.refs.indexOf("v1") >= 0)'));
  Lines := TStringList.Create;
  try
    Lines.Text := 'one' + LineEnding + 'two' + LineEnding + 'three' + LineEnding;
    Lines.SaveToFile(IncludeTrailingPathDelimiter(FRepoDir) + 'a.txt');
  finally
    Lines.Free;
  end;
  AssertEquals('a changed file', 'a.txt:modified:1:0',
    EvalIn(Info^.Ctx, 'var f = Gittan.repo.files(); f[0].path + ":" + f[0].kind + ":" + f[0].added + ":" + f[0].deleted'));
  AssertEquals('other repo', 'undefined',
    EvalIn(Info^.Ctx, 'String(Gittan.repo.snapshot({repo: "/nowhere"}))'));
end;

procedure TExtApiTest.TestRecentAndCommit;
var
  Info: PExtContextInfo;
begin
  Info := Load('recent', 'globalThis.c = Gittan.repo.recent(5); globalThis.d = Gittan.repo.commit(c[0].hash);',
    AllPerms);
  AssertEquals('one commit', '1', EvalIn(Info^.Ctx, 'String(c.length)'));
  AssertEquals('subject', 'first', EvalIn(Info^.Ctx, 'c[0].subject'));
  AssertTrue('an author', EvalIn(Info^.Ctx, 'c[0].author') <> '');
  AssertEquals('details', 'first|the body', EvalIn(Info^.Ctx, 'd.subject + "|" + d.body'));
  AssertEquals('unknown', 'undefined', EvalIn(Info^.Ctx, 'String(Gittan.repo.commit("0000000"))'));
end;

procedure TExtApiTest.TestBranchesTagsRemotes;
var
  Info: PExtContextInfo;
begin
  Git(['remote', 'add', 'origin', FRepoDir]);
  Info := Load('refs', 'globalThis.b = Gittan.repo.branches(); globalThis.t = Gittan.repo.tags();' +
    'globalThis.rm = Gittan.repo.remotes(); globalThis.st = Gittan.repo.stashes();', AllPerms);
  AssertEquals('local', 'main', EvalIn(Info^.Ctx, 'b.local.join(",")'));
  AssertEquals('tag', 'v1', EvalIn(Info^.Ctx, 't[0].name'));
  AssertEquals('lightweight', 'false', EvalIn(Info^.Ctx, 'String(t[0].annotated)'));
  AssertEquals('remote', 'origin', EvalIn(Info^.Ctx, 'rm.join(",")'));
  AssertEquals('no stash', '0', EvalIn(Info^.Ctx, 'String(st.length)'));
end;

procedure TExtApiTest.TestFileTextAndDiff;
var
  Info: PExtContextInfo;
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := 'one' + LineEnding + 'two' + LineEnding + 'three' + LineEnding;
    Lines.SaveToFile(IncludeTrailingPathDelimiter(FRepoDir) + 'a.txt');
  finally
    Lines.Free;
  end;
  Info := Load('text', 'globalThis.head = Gittan.repo.fileText("a.txt", "HEAD");' +
    'globalThis.tree = Gittan.repo.fileText("a.txt");' +
    'globalThis.d = Gittan.repo.diff("a.txt"); globalThis.all = Gittan.repo.diff();', AllPerms);
  AssertEquals('in HEAD', 'one,two', EvalIn(Info^.Ctx, 'head.trim().split(/\r?\n/).join(",")'));
  AssertEquals('in the tree', 'one,two,three', EvalIn(Info^.Ctx, 'tree.trim().split(/\r?\n/).join(",")'));
  AssertEquals('the file diff has the line', 'true', EvalIn(Info^.Ctx, 'String(d.indexOf("+three") >= 0)'));
  AssertEquals('the whole diff too', 'true', EvalIn(Info^.Ctx, 'String(all.indexOf("+three") >= 0)'));
  AssertEquals('missing', 'undefined', EvalIn(Info^.Ctx, 'String(Gittan.repo.fileText("nope.txt"))'));
end;

procedure TExtApiTest.TestGitRun;
var
  Info: PExtContextInfo;
begin
  Info := Load('gitrun', 'Gittan.git.run(["log", "--format=%s", "-n", "1"]).then(function (r) {' +
    'globalThis.out = r.ok + ":" + r.stdout.trim(); });' +
    'Gittan.git.run(["nonsense-command"]).then(function (r) { globalThis.bad = r.ok + ":" + (r.stderr.length > 0); });',
    AllPerms);
  WaitFor(Info^.Ctx, 'globalThis.out && globalThis.bad');
  AssertEquals('the subject', 'true:first', EvalIn(Info^.Ctx, 'globalThis.out'));
  AssertEquals('a failure', 'false:true', EvalIn(Info^.Ctx, 'globalThis.bad'));
end;

procedure TExtApiTest.TestExecRun;
var
  Info: PExtContextInfo;
begin
  Info := Load('exec', 'Gittan.exec.run("git", ["--version"]).then(function (r) {' +
    'globalThis.out = r.ok + ":" + r.stdout.substring(0, 11); });' +
    'Gittan.exec.run("no-such-program-xyz", []).then(function (r) { globalThis.ok = "resolved"; },' +
    'function (e) { globalThis.ok = "rejected:" + String(e); });', AllPerms);
  WaitFor(Info^.Ctx, 'globalThis.out && globalThis.ok');
  AssertEquals('git ran', 'true:git version', EvalIn(Info^.Ctx, 'globalThis.out'));
  AssertEquals('unknown rejected', 'true', EvalIn(Info^.Ctx, 'String(globalThis.ok.indexOf("rejected") === 0)'));
end;

procedure TExtApiTest.TestStorage;
var
  Info: PExtContextInfo;
begin
  Info := Load('store', 'globalThis.before = Gittan.storage.get("url");' +
    'Gittan.storage.set("url", "https://x"); Gittan.storage.setJSON("n", {a: 1});' +
    'globalThis.after = Gittan.storage.get("url"); globalThis.n = Gittan.storage.getJSON("n").a;' +
    'Gittan.storage.remove("url"); globalThis.gone = Gittan.storage.get("url");' +
    'globalThis.dflt = Gittan.storage.getJSON("missing", 7);', AllPerms);
  AssertEquals('nothing before', 'null', EvalIn(Info^.Ctx, 'String(before)'));
  AssertEquals('set', 'https://x', EvalIn(Info^.Ctx, 'after'));
  AssertEquals('json', '1', EvalIn(Info^.Ctx, 'String(n)'));
  AssertEquals('removed', 'null', EvalIn(Info^.Ctx, 'String(gone)'));
  AssertEquals('default', '7', EvalIn(Info^.Ctx, 'String(dflt)'));
  AssertEquals('in the settings', '{"a":1}', FSettings.ExtValue('store', 'n'));
end;

procedure TExtApiTest.TestSettings;
var
  Info: PExtContextInfo;
  Defs: TGittanExtSettingDefs;
begin
  FSettings.SetExtValue('conf', 'url', 'https://set');
  Info := Load('conf', 'Gittan.settings.define([{key: "url", type: "string", label: "Webhook", default: "https://d"},' +
    '{key: "on", type: "bool", default: "1", note: "a note"}, {key: "pick", type: "choice", options: ["a", "b"], default: "b"}]);' +
    'globalThis.u = Gittan.settings.get("url"); globalThis.o = Gittan.settings.get("on");' +
    'globalThis.p = Gittan.settings.get("pick"); globalThis.m = Gittan.settings.get("missing");', AllPerms);
  AssertEquals('stored wins', 'https://set', EvalIn(Info^.Ctx, 'u'));
  AssertEquals('default', '1', EvalIn(Info^.Ctx, 'o'));
  AssertEquals('choice default', 'b', EvalIn(Info^.Ctx, 'p'));
  AssertEquals('missing', 'null', EvalIn(Info^.Ctx, 'String(m)'));
  Defs := FEngine.Registry.SettingsOf('conf');
  AssertEquals('three declared', 3, Length(Defs));
  AssertEquals('label', 'Webhook', Defs[0].Caption);
  AssertTrue('bool kind', Defs[1].Kind = skBool);
  AssertEquals('note', 'a note', Defs[1].Note);
  AssertEquals('options', 2, Length(Defs[2].Options));
end;

procedure TExtApiTest.TestPermissionsShape;
var
  Full, Bare: PExtContextInfo;
begin
  Full := Load('full', '', AllPerms);
  Bare := Load('bare', '', PermBaseline);
  AssertEquals('all listed', 'data,ui,timers,net,exec,settings',
    EvalIn(Full^.Ctx, 'Gittan.api.permissions.join(",")'));
  AssertEquals('id', 'full', EvalIn(Full^.Ctx, 'Gittan.api.extensionId'));
  AssertEquals('git there', 'object', EvalIn(Full^.Ctx, 'typeof Gittan.git'));
  AssertEquals('net there', 'object', EvalIn(Full^.Ctx, 'typeof Gittan.net'));
  AssertEquals('app there', 'object', EvalIn(Full^.Ctx, 'typeof Gittan.app'));
  AssertEquals('baseline listed', 'data,ui,timers', EvalIn(Bare^.Ctx, 'Gittan.api.permissions.join(",")'));
  AssertEquals('no git', 'undefined', EvalIn(Bare^.Ctx, 'typeof Gittan.git'));
  AssertEquals('no net', 'undefined', EvalIn(Bare^.Ctx, 'typeof Gittan.net'));
  AssertEquals('no fetch global', 'undefined', EvalIn(Bare^.Ctx, 'typeof fetch'));
  AssertEquals('no app', 'undefined', EvalIn(Bare^.Ctx, 'typeof Gittan.app'));
  AssertEquals('repo there', 'object', EvalIn(Bare^.Ctx, 'typeof Gittan.repo'));
  AssertEquals('require throws', 'true', EvalIn(Bare^.Ctx,
    'var threw = false; try { Gittan.permissions.require("net"); } catch (e) { threw = true; } String(threw)'));
  AssertEquals('git path', 'true', EvalIn(Full^.Ctx, 'String(Gittan.app.setting("GitPath").length > 0)'));
end;

procedure TExtApiTest.TestUiNatives;
var
  Info: PExtContextInfo;
begin
  Info := Load('ui', 'Gittan.ui.notify("Hello", "world"); Gittan.ui.error("Bad"); ' +
    'Gittan.ui.setStatus("busy", 3); Gittan.ui.addCard({path: "a.txt", line: 2, text: "look", severity: "note"});' +
    'Gittan.ui.clearCards();', AllPerms);
  AssertEquals('notify', 2, FHost.Notified.Count);
  AssertEquals('as a note', 'Hello|world|0', FHost.Notified[0]);
  AssertEquals('as an error', 'Bad||1', FHost.Notified[1]);
  AssertEquals('status', 'busy|3', FHost.Status);
  AssertEquals('card', 'a.txt|2|look|note|ui', FHost.Cards.CommaText);
  AssertEquals('cleared', 'ui', FHost.Cleared);
end;

initialization
  RegisterTest(TExtApiTest);
end.
