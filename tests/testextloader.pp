unit testextloader;

{** Tests of gittan.ext.loader against a folder of scripts and the
  fake host of testextengine: what loads, what is turned off, what is
  asked for and remembered, and what a reload picks up. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.ext.engine, gittan.ext.host,
  gittan.ext.loader, gittan.ext.perm, gittan.settings, testextengine;

type
  TExtLoaderTest = class(TTestCase)
  private
    FHost: TFakeExtHost;
    FDir: string;
    FSettings: TGittanSettings;
    FLoader: TGittanExtLoader;
    procedure Put(const AName, AScript: string);
    procedure EditModule;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLoadsInNameOrder;
    procedure TestTurnedOff;
    procedure TestInvalidManifest;
    procedure TestPermissionAskedAndKept;
    procedure TestPermissionDenied;
    procedure TestChangedWhileAsked;
    procedure TestReloadPicksUpEdits;
    procedure TestScriptErrorListed;
    procedure TestThrowDropsWhatWasRegistered;
    procedure TestCaseTwinRefused;
    procedure TestCaseTwinWithEqualsRefused;
    procedure TestNameRefused;
  end;

implementation

uses
  testhelpers;

procedure TExtLoaderTest.SetUp;
begin
  FHost := TFakeExtHost.Create;
  SetExtHost(FHost);
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-extloader-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
  FSettings := TGittanSettings.Create(FDir);
  FLoader := TGittanExtLoader.Create(FSettings);
end;

procedure TExtLoaderTest.TearDown;
begin
  FLoader.Unload;
  FLoader.Free;
  FSettings.Free;
  SetExtHost(nil);
  RemoveTree(FDir);
end;

procedure TExtLoaderTest.Put(const AName, AScript: string);
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := AScript;
    ForceDirectories(ExtractFileDir(IncludeTrailingPathDelimiter(FLoader.Dir) + AName));
    Lines.SaveToFile(IncludeTrailingPathDelimiter(FLoader.Dir) + AName);
  finally
    Lines.Free;
  end;
end;

procedure TExtLoaderTest.TestLoadsInNameOrder;
begin
  Put('b.js', '/* @name Bee */ Gittan.alert("b");');
  Put('a.js', '/* @name Ay */ Gittan.alert("a");');
  FLoader.Load;
  AssertEquals('both listed', 2, FLoader.Count);
  AssertEquals('a first', 'a', FLoader.Info(0).Id);
  AssertEquals('its name', 'Ay', FLoader.Info(0).DisplayName);
  AssertTrue('a loaded', FLoader.Info(0).Loaded);
  AssertTrue('b loaded', FLoader.Info(1).Loaded);
  AssertEquals('run in that order', 'a,b', FHost.Alerts.CommaText);
  AssertEquals('two contexts', 2, TGittanExtEngine.Instance.ExtensionCount);
  AssertEquals('menus told once at the end', 1, FHost.Changed);
end;

procedure TExtLoaderTest.TestTurnedOff;
var
  Inf: TGittanExtInfo;
begin
  Put('off.js', '/* @name Off */ Gittan.alert("off");');
  FSettings.SetExtEnabled('off', False);
  FLoader.Load;
  AssertTrue('listed', FLoader.FindInfo('off', Inf));
  AssertFalse('not on', Inf.Enabled);
  AssertFalse('not loaded', Inf.Loaded);
  AssertEquals('not run', '', FHost.Alerts.CommaText);
  AssertEquals('no context', 0, TGittanExtEngine.Instance.ExtensionCount);
end;

procedure TExtLoaderTest.TestInvalidManifest;
var
  Inf: TGittanExtInfo;
begin
  Put('bad.js', '/* @name Bad' + LineEnding + '@perms teleport */ Gittan.alert("bad");');
  FLoader.Load;
  AssertTrue('listed', FLoader.FindInfo('bad', Inf));
  AssertFalse('not loaded', Inf.Loaded);
  AssertTrue('says why: ' + Inf.Error, Inf.Error <> '');
  AssertEquals('reported', 1, FHost.Errors.Count);
  AssertEquals('not run', '', FHost.Alerts.CommaText);
end;

procedure TExtLoaderTest.TestPermissionAskedAndKept;
var
  Inf: TGittanExtInfo;
begin
  Put('net.js', '/* @name Net' + LineEnding + '@copyright (c) Someone' + LineEnding +
    '@perms net */ Gittan.alert("net");');
  FHost.PermissionAnswer := True;
  FLoader.Load;
  AssertEquals('asked once', 1, FHost.Asked.Count);
  AssertEquals('for what', 'Net|(c) Someone|net', FHost.Asked[0]);
  AssertTrue('loaded', FLoader.FindInfo('net', Inf) and Inf.Loaded);
  AssertTrue('net granted', epNet in Inf.Granted);
  AssertTrue('kept', FSettings.HasExtPerm('net'));
  AssertEquals('as net', 'net', FSettings.ExtPerm('net', 'Granted'));
  AssertEquals('with the author', '(c) Someone', FSettings.ExtPerm('net', 'Author'));
  FLoader.Reload;
  AssertEquals('not asked again', 1, FHost.Asked.Count);
  AssertTrue('loaded again', FLoader.FindInfo('net', Inf) and Inf.Loaded);
  FSettings.ClearExtPerm('net');
  FLoader.Reload;
  AssertEquals('asked after a reset', 2, FHost.Asked.Count);
  Put('net.js', '/* @name Net' + LineEnding + '@copyright (c) Someone' + LineEnding +
    '@perms net */ Gittan.alert("net, edited");');
  FLoader.Reload;
  AssertEquals('asked after an edit', 3, FHost.Asked.Count);
  { A module in a subfolder runs under the grant too. }
  Put('lib' + PathDelim + 'util.js', 'export const x = 1;');
  FLoader.Reload;
  AssertEquals('asked after a module came', 4, FHost.Asked.Count);
  FLoader.Reload;
  AssertEquals('not asked for the same module', 4, FHost.Asked.Count);
  Put('lib' + PathDelim + 'util.js', 'export const x = 2;');
  FLoader.Reload;
  AssertEquals('asked after a module''s edit', 5, FHost.Asked.Count);
end;

procedure TExtLoaderTest.EditModule;
begin
  Put('lib' + PathDelim + 'util.js', 'export const x = 2;');
end;

{ A module edited while the question is up runs with what was not shown:
  the grant goes and the file is not loaded. }
procedure TExtLoaderTest.TestChangedWhileAsked;
var
  Inf: TGittanExtInfo;
begin
  Put('net.js', '/* @name Net' + LineEnding + '@perms net */ Gittan.alert("net");');
  Put('lib' + PathDelim + 'util.js', 'export const x = 1;');
  FHost.PermissionAnswer := True;
  FHost.OnAsk := @EditModule;
  FLoader.Load;
  FHost.OnAsk := nil;
  AssertTrue('found', FLoader.FindInfo('net', Inf));
  AssertFalse('not loaded', Inf.Loaded);
  AssertFalse('no grant kept', FSettings.HasExtPerm('net'));
  FLoader.Reload;
  AssertEquals('asked again', 2, FHost.Asked.Count);
  AssertTrue('loaded then', FLoader.FindInfo('net', Inf) and Inf.Loaded);
end;

procedure TExtLoaderTest.TestPermissionDenied;
var
  Inf: TGittanExtInfo;
begin
  Put('exec.js', '/* @name Exec' + LineEnding + '@perms exec */ Gittan.alert("exec");');
  FHost.PermissionAnswer := False;
  FLoader.Load;
  AssertTrue('listed', FLoader.FindInfo('exec', Inf));
  AssertFalse('not loaded', Inf.Loaded);
  AssertTrue('says why', Inf.Error <> '');
  AssertFalse('nothing kept', FSettings.HasExtPerm('exec'));
  AssertEquals('not run', '', FHost.Alerts.CommaText);
  FLoader.Reload;
  AssertEquals('asked again', 2, FHost.Asked.Count);
end;

procedure TExtLoaderTest.TestReloadPicksUpEdits;
begin
  Put('one.js', '/* @name One */ Gittan.commands.register({id: "a", title: "A", run: function () {}});');
  FLoader.Load;
  AssertEquals('one command', 1, TGittanExtEngine.Instance.Registry.CommandCount);
  Put('one.js', '/* @name One */ Gittan.commands.register({id: "b", title: "B", run: function () {}});' +
    'Gittan.commands.register({id: "c", title: "C", run: function () {}});');
  Put('two.js', '/* @name Two */');
  FLoader.Reload;
  AssertEquals('two listed', 2, FLoader.Count);
  AssertEquals('the new commands', 2, TGittanExtEngine.Instance.Registry.CommandCount);
  AssertEquals('b', 'b', TGittanExtEngine.Instance.Registry.Command(0).Id);
  DeleteFile(IncludeTrailingPathDelimiter(FLoader.Dir) + 'one.js');
  FLoader.Reload;
  AssertEquals('one listed', 1, FLoader.Count);
  AssertEquals('no command', 0, TGittanExtEngine.Instance.Registry.CommandCount);
end;

procedure TExtLoaderTest.TestScriptErrorListed;
var
  Inf: TGittanExtInfo;
begin
  Put('broken.js', '/* @name Broken */ this is not javascript');
  FLoader.Load;
  AssertTrue('listed', FLoader.FindInfo('broken', Inf));
  AssertFalse('not loaded', Inf.Loaded);
  AssertTrue('the error: ' + Inf.Error, Pos('SyntaxError', Inf.Error) > 0);
  AssertEquals('reported once', 1, FHost.Errors.Count);
end;

{ A script that throws after it registered something is shown as not
  loaded, so what it registered goes too; a script whose last value is
  a string starting with Error: did not throw and is loaded. }
procedure TExtLoaderTest.TestThrowDropsWhatWasRegistered;
var
  Inf: TGittanExtInfo;
  Engine: TGittanExtEngine;
begin
  Put('half.js', '/* @name Half */' + LineEnding +
    'Gittan.on("commit.before", function () { return "stopped"; });' + LineEnding +
    'Gittan.commands.register({id: "x", title: "X", run: function () {}});' + LineEnding +
    'setInterval(function () {}, 60000);' + LineEnding +
    'throw new Error("late");');
  Put('says.js', '/* @name Says */' + LineEnding + '"Error: not one";');
  FLoader.Load;
  Engine := TGittanExtEngine.Instance;
  AssertTrue(FLoader.FindInfo('half', Inf));
  AssertFalse('not loaded', Inf.Loaded);
  AssertTrue(Inf.Error, Pos('late', Inf.Error) > 0);
  AssertEquals('its listener gone', 0, Engine.Registry.ListenerCount);
  AssertEquals('its command gone', 0, Engine.Registry.CommandCount);
  AssertTrue(FLoader.FindInfo('says', Inf));
  AssertTrue('a string is no error', Inf.Loaded);
  AssertEquals('one context, the one that loaded', 1, Engine.ExtensionCount);
end;

{ Test.js and test.js share the id test; the second is refused, so one
  context and one set of grants and values go with it. A file system
  that folds case (macOS and Windows as installed) keeps one file of
  the two, and there the one loads. }
procedure TExtLoaderTest.TestCaseTwinRefused;
var
  Found: TSearchRec;
  Files, Loaded, i: integer;
begin
  Put('Test.js', '/* @name Upper */ Gittan.alert("upper");');
  Put('test.js', '/* @name Lower */ Gittan.alert("lower");');
  Files := 0;
  if FindFirst(IncludeTrailingPathDelimiter(FLoader.Dir) + '*.js', faAnyFile, Found) = 0 then
  begin
    repeat
      Inc(Files);
    until FindNext(Found) <> 0;
    FindClose(Found);
  end;
  FLoader.Load;
  AssertEquals('each file listed', Files, FLoader.Count);
  Loaded := 0;
  for i := 0 to FLoader.Count - 1 do
    if FLoader.Info(i).Loaded then
      Inc(Loaded)
    else
      AssertTrue('the twin says which file it matched: ' + FLoader.Info(i).Error,
        Pos('.js', FLoader.Info(i).Error) > 0);
  AssertEquals('one of them loaded', 1, Loaded);
  AssertEquals('one context', 1, TGittanExtEngine.Instance.ExtensionCount);
  AssertEquals('one run', 1, FHost.Alerts.Count);
  AssertEquals('the twin reported', Files - 1, FHost.Errors.Count);
end;

{ An id with an = is matched whole, so A=B.js and a=b.js collide as
  Test.js and test.js do. }
procedure TExtLoaderTest.TestCaseTwinWithEqualsRefused;
var
  Found: TSearchRec;
  Files, Loaded, i: integer;
begin
  Put('A=B.js', '/* @name Upper */ Gittan.alert("upper");');
  Put('a=b.js', '/* @name Lower */ Gittan.alert("lower");');
  Files := 0;
  if FindFirst(IncludeTrailingPathDelimiter(FLoader.Dir) + '*.js', faAnyFile, Found) = 0 then
  begin
    repeat
      Inc(Files);
    until FindNext(Found) <> 0;
    FindClose(Found);
  end;
  FLoader.Load;
  AssertEquals('each file listed', Files, FLoader.Count);
  Loaded := 0;
  for i := 0 to FLoader.Count - 1 do
    if FLoader.Info(i).Loaded then
      Inc(Loaded)
    else
      AssertTrue('the twin says which file it matched: ' + FLoader.Info(i).Error,
        Pos('=', FLoader.Info(i).Error) > 0);
  AssertEquals('one of them loaded', 1, Loaded);
  AssertEquals('one run', 1, FHost.Alerts.Count);
  AssertEquals('the twin reported', Files - 1, FHost.Errors.Count);
end;

{ A name with what the old ini file could not hold (=, a ; first, ]) loads,
  its values kept under it; one with a control character, which a file
  name holds on Unix alone, does not. }
procedure TExtLoaderTest.TestNameRefused;
var
  Inf: TGittanExtInfo;
begin
  Put('a=b.js', '/* @name Eq */ Gittan.alert("eq");');
  Put(';c.js', '/* @name Semi */ Gittan.alert("semi");');
  Put('d]e.js', '/* @name Bracket */ Gittan.alert("bracket");');
  {$IFDEF UNIX}
  Put('t'#9'b.js', '/* @name Tab */ Gittan.alert("tab");');
  {$ENDIF}
  FLoader.Load;
  AssertTrue('= listed', FLoader.FindInfo('a=b', Inf));
  AssertTrue('= loaded', Inf.Loaded);
  AssertTrue('; listed', FLoader.FindInfo(';c', Inf));
  AssertTrue('; loaded', Inf.Loaded);
  AssertTrue('] listed', FLoader.FindInfo('d]e', Inf));
  AssertTrue('] loaded', Inf.Loaded);
  {$IFDEF UNIX}
  AssertTrue('tab listed', FLoader.FindInfo('t'#9'b', Inf));
  AssertFalse('tab not loaded', Inf.Loaded);
  AssertTrue('says why: ' + Inf.Error, Pos('Rename the file', Inf.Error) > 0);
  AssertEquals('one reported', 1, FHost.Errors.Count);
  {$ENDIF}
  AssertEquals('the three ran', 3, FHost.Alerts.Count);
  AssertTrue(FHost.Alerts.IndexOf('eq') >= 0);
  AssertTrue(FHost.Alerts.IndexOf('semi') >= 0);
  AssertTrue(FHost.Alerts.IndexOf('bracket') >= 0);
  FSettings.SetExtValue('d]e', 'k', 'v');
  FSettings.SetExtEnabled('d]e', False);
  FSettings.Save;
  FSettings.SetExtValue('d]e', 'k', '');
  FSettings.Load;
  AssertEquals('its value through the file', 'v', FSettings.ExtValue('d]e', 'k'));
  AssertFalse('turned off through the file', FSettings.ExtEnabled('d]e'));
end;

initialization
  RegisterTest(TExtLoaderTest);

end.
