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
    procedure WaitFor(ctx: JSContext; const AExpr: string; const AShow: string = '');
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSnapshotAndFiles;
    procedure TestRecentAndCommit;
    procedure TestBranchesTagsRemotes;
    procedure TestFileTextAndDiff;
    procedure TestAsyncReads;
    procedure TestGitRun;
    procedure TestExecRun;
    procedure TestExecWithoutData;
    procedure TestRunInput;
    procedure TestStorage;
    procedure TestSettings;
    procedure TestPermissionsShape;
    procedure TestUiNatives;
    procedure TestUiMessage;
    procedure TestForge;
  end;

implementation

uses
  {$IFDEF UNIX}BaseUnix,{$ENDIF} testhelpers;

const
  AllPerms: TExtPermSet = [epData, epUI, epTimers, epNet, epExec, epSettings, epForge];

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
  FSettings := TGittanSettings.Create(FDir);
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

{ AShow, when given, is evaluated into the message of a timeout. Thirty
  seconds by the clock, not a count of CheckSynchronize calls, which
  return at once while there is something to synchronize: a Windows
  runner took over six to answer three git commands at once, git looking
  through PATH for commands like an unknown one. }
procedure TExtApiTest.WaitFor(ctx: JSContext; const AExpr: string; const AShow: string);
var
  GiveUpAt: QWord;
begin
  GiveUpAt := GetTickCount64 + 30000;
  repeat
    CheckSynchronize(10);
    FEngine.PumpJobs;
    if EvalIn(ctx, 'String(!!(' + AExpr + '))') = 'true' then
      Exit;
  until GetTickCount64 >= GiveUpAt;
  if AShow <> '' then
    Fail('timed out waiting for ' + AExpr + ': ' + EvalIn(ctx, AShow))
  else
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
  with TStringList.Create do
  try
    Text := 'secret';
    SaveToFile(IncludeTrailingPathDelimiter(FDir) + 'outside.txt');
  finally
    Free;
  end;
  AssertEquals('outside the repository', 'undefined',
    EvalIn(Info^.Ctx, 'String(Gittan.repo.fileText("../outside.txt"))'));
  {$IFDEF UNIX}
  { A link in the work tree to the folder around it. }
  AssertEquals('link made', 0, fpSymlink(PChar(FDir),
    PChar(IncludeTrailingPathDelimiter(FRepoDir) + 'out')));
  try
    AssertEquals('through a link', 'undefined',
      EvalIn(Info^.Ctx, 'String(Gittan.repo.fileText("out/outside.txt"))'));
  finally
    { Before TearDown's RemoveTree, which would follow it. }
    fpUnlink(PChar(IncludeTrailingPathDelimiter(FRepoDir) + 'out'));
  end;
  {$ENDIF}
end;

{ The same reads on the promise thread, for a long file's blame or diff
  that would hold the window. }
procedure TExtApiTest.TestAsyncReads;
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
  with TStringList.Create do
  try
    Text := 'secret';
    SaveToFile(IncludeTrailingPathDelimiter(FDir) + 'outside.txt');
  finally
    Free;
  end;
  Info := Load('async', 'Promise.all([Gittan.repo.diffAsync("a.txt"), Gittan.repo.diffAsync(),' +
    'Gittan.repo.blameAsync("a.txt", "HEAD"), Gittan.repo.fileTextAsync("a.txt", "HEAD"),' +
    'Gittan.repo.fileTextAsync("../outside.txt"), Gittan.repo.blameAsync("nope.txt")])' +
    '.then(function (r) { globalThis.r = r; globalThis.done = true; });', AllPerms);
  WaitFor(Info^.Ctx, 'globalThis.done');
  AssertEquals('the file diff', 'true', EvalIn(Info^.Ctx, 'String(r[0].indexOf("+three") >= 0)'));
  AssertEquals('the whole diff', 'true', EvalIn(Info^.Ctx, 'String(r[1].indexOf("+three") >= 0)'));
  AssertEquals('the blame', 'true', EvalIn(Info^.Ctx, 'String(r[2].indexOf("summary first") >= 0)'));
  AssertEquals('the text in HEAD', 'one,two', EvalIn(Info^.Ctx, 'r[3].trim().split(/\r?\n/).join(",")'));
  AssertEquals('outside the repository', 'undefined', EvalIn(Info^.Ctx, 'String(r[4])'));
  AssertEquals('a failed blame', 'undefined', EvalIn(Info^.Ctx, 'String(r[5])'));
  AssertEquals('the state is the facade''s alone', 'undefined',
    EvalIn(Info^.Ctx, 'typeof Gittan._repoState'));
end;

procedure TExtApiTest.TestGitRun;
var
  Info: PExtContextInfo;
begin
  Info := Load('gitrun', 'Gittan.git.run(["log", "--format=%s", "-n", "1"]).then(function (r) {' +
    'globalThis.out = r.ok + ":" + r.stdout.trim(); });' +
    'Gittan.git.run(["nonsense-command"]).then(function (r) { globalThis.bad = r.ok + ":" + (r.stderr.length > 0); });' +
    'Gittan.git.run(["rev-parse", "--verify", "no-such-ref"]).then(function (r) {' +
    'globalThis.code = r.status; globalThis.codeErr = r.stderr; }, function (e) { globalThis.code = "rejected: " + e; });',
    AllPerms);
  { Each set at all, not truthy: a status of 0 is a wrong answer to show,
    not a wait that never ends. }
  WaitFor(Info^.Ctx, 'globalThis.out !== undefined && globalThis.bad !== undefined && ' +
    'globalThis.code !== undefined',
    'JSON.stringify({out: globalThis.out, bad: globalThis.bad, code: globalThis.code})');
  AssertEquals('the subject', 'true:first', EvalIn(Info^.Ctx, 'globalThis.out'));
  AssertEquals('a failure', 'false:true', EvalIn(Info^.Ctx, 'globalThis.bad'));
  AssertEquals('git''s own exit status (' + EvalIn(Info^.Ctx, 'String(globalThis.codeErr)') + ')',
    '128', EvalIn(Info^.Ctx, 'String(globalThis.code)'));
end;

{ exec without data: git.run, exec.run and gh.run run in the shown
  repository when no repo is named, so they need its root, which data
  alone gave. Gittan.repo stays out. }
procedure TExtApiTest.TestExecWithoutData;
var
  Info: PExtContextInfo;
begin
  Info := Load('execonly', 'Gittan.git.run(["log", "--format=%s", "-n", "1"]).then(function (r) {' +
    'globalThis.out = r.ok + ":" + r.stdout.trim(); }, function (e) { globalThis.out = "rejected:" + String(e); });' +
    'Gittan.exec.run("git", ["rev-parse", "--is-inside-work-tree"]).then(function (r) {' +
    'globalThis.inside = r.stdout.trim(); }, function (e) { globalThis.inside = "rejected:" + String(e); });',
    PermBaseline + [epExec]);
  WaitFor(Info^.Ctx, 'globalThis.out && globalThis.inside');
  AssertEquals('git in the shown repository', 'true:first', EvalIn(Info^.Ctx, 'globalThis.out'));
  AssertEquals('a program there too', 'true', EvalIn(Info^.Ctx, 'globalThis.inside'));
  AssertEquals('no repo without data', 'undefined', EvalIn(Info^.Ctx, 'typeof Gittan.repo'));
end;

{ {input} goes to the standard input: git hash-object reads it all,
  git cat-file --batch-check writes as it reads (a megabyte of answers
  to a hundred kilobytes of names, which filled both pipes when the
  input was written first), and git --version never reads it, which
  breaks the pipe without ending the tests. Built with FPC 3.3.1 (trunk,
  as fpcupdeluxe makes it) it times out: there TProcess.CloseInput
  closes nothing once Input has been used, so the tools that read to
  the end never get it (https://gitlab.com/freepascal.org/fpc/source/-/issues/41845,
  open as of 2026-11-01); 3.2.x, which CI and the releases use, closes it. }
procedure TExtApiTest.TestRunInput;
var
  Info: PExtContextInfo;
begin
  Info := Load('input', 'Gittan.git.run(["hash-object", "--stdin"], {input: "hello\n"}).then(function (r) {' +
    'globalThis.hash = r.stdout.trim(); });' +
    'Gittan.exec.run("git", ["hash-object", "--stdin"], {input: "hello\n"}).then(function (r) {' +
    'globalThis.ehash = r.stdout.trim(); });' +
    'Gittan.git.run(["cat-file", "--batch-check"], {input: "HEAD\n".repeat(20000)}).then(function (r) {' +
    'globalThis.lines = r.ok + ":" + r.stdout.trim().split("\n").length; });' +
    'Gittan.git.run(["--version"], {input: "x".repeat(4 * 1024 * 1024)}).then(function (r) {' +
    'globalThis.unread = r.ok + ":" + r.stdout.substring(0, 11); });', AllPerms);
  WaitFor(Info^.Ctx, 'globalThis.hash && globalThis.ehash && globalThis.lines && globalThis.unread');
  AssertEquals('git read it', 'ce013625030ba8dba906f756967f9e9ca394464a', EvalIn(Info^.Ctx, 'globalThis.hash'));
  AssertEquals('a program too', 'ce013625030ba8dba906f756967f9e9ca394464a', EvalIn(Info^.Ctx, 'globalThis.ehash'));
  AssertEquals('written as it was read', 'true:20000', EvalIn(Info^.Ctx, 'globalThis.lines'));
  AssertEquals('an input not read', 'true:git version', EvalIn(Info^.Ctx, 'globalThis.unread'));
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
    'globalThis.dflt = Gittan.storage.getJSON("missing", 7);' +
    'Gittan.storage.set("text", "a\n[Trust]\nx=1");' +
    'Gittan.storage.set("a=b", "eq");' +
    'try { Gittan.storage.set("", "v"); globalThis.bad = "stored"; } catch (e) { globalThis.bad = String(e); }' +
    'try { Gittan.storage.get("c\nd"); globalThis.badGet = "read"; } catch (e) { globalThis.badGet = String(e); }' +
    'try { Gittan.settings.define([{key: "s\tt", type: "string"}]); globalThis.badDef = "defined"; } catch (e) { globalThis.badDef = String(e); }' +
    'try { Gittan.settings.define([{key: "", type: "string"}]); globalThis.emptyDef = "defined"; } catch (e) { globalThis.emptyDef = String(e); }' +
    'globalThis.done = true;', AllPerms);
  AssertEquals('nothing before', 'null', EvalIn(Info^.Ctx, 'String(before)'));
  AssertEquals('set', 'https://x', EvalIn(Info^.Ctx, 'after'));
  AssertEquals('json', '1', EvalIn(Info^.Ctx, 'String(n)'));
  AssertEquals('removed', 'null', EvalIn(Info^.Ctx, 'String(gone)'));
  AssertEquals('default', '7', EvalIn(Info^.Ctx, 'String(dflt)'));
  AssertEquals('in the settings', '{"a":1}', FSettings.ExtValue('store', 'n'));
  AssertEquals('line ends kept', 'a' + #10 + '[Trust]' + #10 + 'x=1', FSettings.ExtValue('store', 'text'));
  AssertEquals('= in a key', 'eq', FSettings.ExtValue('store', 'a=b'));
  AssertTrue('an empty key refused: ' + EvalIn(Info^.Ctx, 'bad'),
    Pos('Gittan.storage.set: The key ""', EvalIn(Info^.Ctx, 'bad')) > 0);
  AssertTrue('a line end refused on read: ' + EvalIn(Info^.Ctx, 'badGet'),
    Pos('Gittan.storage.get: The key "c', EvalIn(Info^.Ctx, 'badGet')) > 0);
  AssertTrue('a tab refused in define: ' + EvalIn(Info^.Ctx, 'badDef'),
    Pos('Gittan.settings.define: The key "s', EvalIn(Info^.Ctx, 'badDef')) > 0);
  AssertTrue('an empty key refused in define: ' + EvalIn(Info^.Ctx, 'emptyDef'),
    Pos('Gittan.settings.define: The key ""', EvalIn(Info^.Ctx, 'emptyDef')) > 0);
  AssertEquals('nothing declared', 0, Length(FEngine.Registry.SettingsOf('store')));
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
  AssertEquals('all listed', 'data,ui,timers,net,exec,settings,forge',
    EvalIn(Full^.Ctx, 'Gittan.api.permissions.join(",")'));
  AssertEquals('id', 'full', EvalIn(Full^.Ctx, 'Gittan.api.extensionId'));
  AssertEquals('git there', 'object', EvalIn(Full^.Ctx, 'typeof Gittan.git'));
  AssertEquals('net there', 'object', EvalIn(Full^.Ctx, 'typeof Gittan.net'));
  AssertEquals('app there', 'object', EvalIn(Full^.Ctx, 'typeof Gittan.app'));
  AssertEquals('baseline listed', 'ui,timers', EvalIn(Bare^.Ctx, 'Gittan.api.permissions.join(",")'));
  AssertEquals('no git', 'undefined', EvalIn(Bare^.Ctx, 'typeof Gittan.git'));
  AssertEquals('no net', 'undefined', EvalIn(Bare^.Ctx, 'typeof Gittan.net'));
  AssertEquals('no fetch global', 'undefined', EvalIn(Bare^.Ctx, 'typeof fetch'));
  AssertEquals('no app', 'undefined', EvalIn(Bare^.Ctx, 'typeof Gittan.app'));
  AssertEquals('no repo without data', 'undefined', EvalIn(Bare^.Ctx, 'typeof Gittan.repo'));
  AssertEquals('storage without data', 'object', EvalIn(Bare^.Ctx, 'typeof Gittan.storage'));
  AssertEquals('settings without data', 'object', EvalIn(Bare^.Ctx, 'typeof Gittan.settings'));
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

{ Gittan.ui.message: the dialog's shape reaches the host, its answer the
  script, and a shape that is wrong throws without a dialog. }
procedure TExtApiTest.TestUiMessage;
var
  Info: PExtContextInfo;
begin
  FHost.MessageAnswer := 1;
  Info := Load('msg', 'globalThis.a = Gittan.ui.message({title: "Push?", text: "To main", kind: "warn",' +
    ' buttons: ["Push Anyway", "Cancel"], default: 1, cancel: 1});' +
    'globalThis.b = Gittan.ui.message("plain");' +
    'globalThis.bad = [{text: "x", kind: "loud"}, {text: "x", buttons: [""]}, {text: "x", buttons: ["a"], cancel: 1},' +
    ' {}, {text: "x", buttons: "a"}, {text: "x", buttons: ["1","2","3","4","5","6","7"]}].map(function (o) {' +
    ' try { Gittan.ui.message(o); return "no"; } catch (e) { return "threw"; } }).join(",");', AllPerms);
  AssertEquals('answer', '1', EvalIn(Info^.Ctx, 'String(globalThis.a)'));
  AssertEquals('a number', 'number', EvalIn(Info^.Ctx, 'typeof globalThis.a'));
  AssertEquals('two dialogs', 2, FHost.Messages.Count);
  AssertEquals('the shape', 'msg|Push?|To main|1|Push Anyway,Cancel|1|1', FHost.Messages[0]);
  AssertEquals('a text alone', 'msg||plain|0||0|-1', FHost.Messages[1]);
  AssertEquals('wrong shapes throw', 'threw,threw,threw,threw,threw,threw', EvalIn(Info^.Ctx, 'globalThis.bad'));
end;

{ Gittan.forge and Gittan.forges.gh: only with forge; the forge of the
  repository by its remotes, of the forge view while it is shown, or
  the one named; the tool run is the forge's, here git in gh's place
  so no test runs gh, and gh.run refuses where the forge is not
  GitHub. }
procedure TExtApiTest.TestForge;
var
  Bare, Info: PExtContextInfo;
begin
  Bare := Load('noforge', '', PermBaseline + [epExec]);
  AssertEquals('no forge without it', 'undefined', EvalIn(Bare^.Ctx, 'typeof Gittan.forge'));
  AssertEquals('nor the forges', 'undefined', EvalIn(Bare^.Ctx, 'typeof Gittan.forges'));
  FSettings.SetForgeCliPath('GitHub', GitExe);
  Info := Load('forge', 'Gittan.forges.gh.run(["--version"]).then(function (r) { globalThis.local = "ran"; },' +
    'function (e) { globalThis.local = String(e.message); });', PermBaseline + [epForge]);
  AssertEquals('no exec needed', 'undefined', EvalIn(Info^.Ctx, 'typeof Gittan.exec'));
  AssertEquals('no forge for a repository without a remote', 'null',
    EvalIn(Info^.Ctx, 'JSON.stringify(Gittan.forge.info())'));
  WaitFor(Info^.Ctx, 'globalThis.local');
  AssertEquals('gh refused there', 'Gittan.forges.gh.run: here is on no forge, not on GitHub',
    EvalIn(Info^.Ctx, 'globalThis.local'));
  Git(['remote', 'add', 'origin', 'https://github.com/slicke/gittan.git']);
  AssertEquals('on GitHub now', 'GitHub:gh:true',
    EvalIn(Info^.Ctx, 'var i = Gittan.forge.info(); i.name + ":" + i.cli + ":" + i.ready'));
  { git stands in for gh: "status" is a command of both, and git's
    names the branch only in a repository. }
  EvalIn(Info^.Ctx, 'Gittan.forges.gh.run(["status"]).then(function (r) {' +
    'globalThis.inRepo = String(r.stdout.indexOf("branch") >= 0); }, function (e) { globalThis.inRepo = "rejected:" + e; });' +
    'Gittan.forge.cli(["--version"]).then(function (r) { globalThis.ver = "ran"; },' +
    'function (e) { globalThis.ver = String((e && e.message) || e); });' +
    'Gittan.forge.cli(["alias", "set", "--shell", "x", "echo"]).then(function (r) { globalThis.alias = "ran"; },' +
    'function (e) { globalThis.alias = String((e && e.message) || e); });');
  WaitFor(Info^.Ctx, 'globalThis.inRepo && globalThis.ver && globalThis.alias');
  AssertEquals('in the repository', 'true', EvalIn(Info^.Ctx, 'globalThis.inRepo'));
  AssertEquals('no command gh does not open', 'Gittan.forge.cli: gh --version is not open to extensions',
    EvalIn(Info^.Ctx, 'globalThis.ver'));
  AssertEquals('no alias', 'Gittan.forge.cli: gh alias is not open to extensions',
    EvalIn(Info^.Ctx, 'globalThis.alias'));
  FHost.ViewForge := 'GitHub';
  FHost.Root := '';
  AssertEquals('the forge view''s', 'GitHub', EvalIn(Info^.Ctx, 'Gittan.forge.info().name'));
  AssertEquals('one named', 'GitHub', EvalIn(Info^.Ctx, 'Gittan.forge.info({forge: "github"}).name'));
  { A folder that is gone is refused, not swapped for the home folder;
    a saved tool that is gone is not ready. }
  EvalIn(Info^.Ctx, 'Gittan.forge.cli(["status"], {forge: "GitHub", repo: "/no/such/folder"}).then(' +
    'function (r) { globalThis.gone = "ran"; }, function (e) { globalThis.gone = String((e && e.message) || e); });');
  WaitFor(Info^.Ctx, 'globalThis.gone');
  AssertEquals('no folder', 'Gittan.forge.cli: /no/such/folder is not a folder',
    EvalIn(Info^.Ctx, 'globalThis.gone'));
  FSettings.SetForgeCliPath('GitHub', '/no/such/gh');
  AssertEquals('a tool that is gone', 'false:/no/such/gh was not found',
    EvalIn(Info^.Ctx, 'var i = Gittan.forge.info(); i.ready + ":" + i.reason'));
  EvalIn(Info^.Ctx, 'Gittan.forge.cli(["status"]).then(function (r) { globalThis.nogh = "ran"; },' +
    'function (e) { globalThis.nogh = String((e && e.message) || e); });');
  WaitFor(Info^.Ctx, 'globalThis.nogh');
  AssertEquals('rejected', 'Gittan.forge.cli: /no/such/gh was not found',
    EvalIn(Info^.Ctx, 'globalThis.nogh'));
  FSettings.HostingEnabled := False;
  AssertEquals('off in the settings', 'false', EvalIn(Info^.Ctx, 'String(Gittan.forge.info().ready)'));
end;

initialization
  RegisterTest(TExtApiTest);

end.
