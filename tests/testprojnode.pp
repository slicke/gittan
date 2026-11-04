unit testprojnode;

{** Tests of gittan.proj.node: its parsers as functions of the text, and its
  section of the Project page built in a temporary folder. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.manifest, gittan.project,
  gittan.proj.node, testhelpers;

type
  TProjNodeTest = class(TTestCase)
  private
    FDir: string;
    procedure Put(const ARel, AText: string);
    function Names(const ADeps: TGittanDependencies): string;
    function Find(const ADeps: TGittanDependencies; const AName: string): TGittanDependency;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPackageJson;
    procedure TestPackageLockV3;
    procedure TestPackageLockV1;
    procedure TestYarnLock;
    procedure TestPnpmLock;
    procedure TestNodeInfo;
    procedure TestNodeManager;
    procedure TestNodeSection;
    procedure TestNodeLockOfManager;
    procedure TestNodeUnknownManager;
  end;

implementation

const
  LE = LineEnding;

procedure TProjNodeTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-projnode-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
end;

procedure TProjNodeTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TProjNodeTest.Put(const ARel, AText: string);
var
  Name: string;
  F: TFileStream;
begin
  Name := IncludeTrailingPathDelimiter(FDir) + SetDirSeparators(ARel);
  ForceDirectories(ExtractFileDir(Name));
  F := TFileStream.Create(Name, fmCreate);
  try
    if AText <> '' then
      F.WriteBuffer(AText[1], Length(AText));
  finally
    F.Free;
  end;
end;

function TProjNodeTest.Names(const ADeps: TGittanDependencies): string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(ADeps) do
  begin
    if i > 0 then
      Result := Result + ' ';
    Result := Result + ADeps[i].Name;
  end;
end;

function TProjNodeTest.Find(const ADeps: TGittanDependencies;
  const AName: string): TGittanDependency;
var
  i: integer;
begin
  for i := 0 to High(ADeps) do
    if ADeps[i].Name = AName then
      Exit(ADeps[i]);
  Fail('no dependency ' + AName);
  Result := Default(TGittanDependency);
end;

procedure TProjNodeTest.TestPackageJson;
var
  D: TGittanDependencies;
begin
  D := ParsePackageDependencies('{"name": "x", "version": "2.0.0", "dependencies": {"vue": "^3.4"},' +
    ' "devDependencies": {"vite": "^5"}, "peerDependencies": {"react": ">=18"},' +
    ' "optionalDependencies": {"fsevents": "*"}}');
  AssertEquals('vue vite react fsevents', Names(D));
  AssertEquals('^3.4', Find(D, 'vue').Version);
  AssertEquals('dev', Find(D, 'vite').Group);
  AssertEquals('peer', Find(D, 'react').Group);
  AssertEquals('optional', Find(D, 'fsevents').Group);
  AssertEquals('2.0.0', PackageVersion('{"version": "2.0.0"}'));
  AssertEquals(0, Length(ParsePackageDependencies('not json')));
  AssertEquals('', PackageVersion(''));
end;

procedure TProjNodeTest.TestPackageLockV3;
var
  D: TGittanDependencies;
begin
  D := ParsePackageLock('{"lockfileVersion": 3, "packages": {"": {"name": "x"},' +
    ' "node_modules/vue": {"version": "3.4.21"},' +
    ' "node_modules/vue/node_modules/csstype": {"version": "3.1.3"},' +
    ' "node_modules/@vitejs/plugin-vue": {"version": "5.0.4"}}}');
  AssertEquals('the nested one is left out', 'vue @vitejs/plugin-vue', Names(D));
  AssertEquals('3.4.21', Find(D, 'vue').Resolved);
end;

procedure TProjNodeTest.TestPackageLockV1;
var
  D: TGittanDependencies;
begin
  D := ParsePackageLock('{"lockfileVersion": 1, "dependencies": {"vue": {"version": "2.7.0",' +
    ' "requires": {"csstype": "^2"}}}}');
  AssertEquals('vue', Names(D));
  AssertEquals('2.7.0', Find(D, 'vue').Resolved);
end;

procedure TProjNodeTest.TestYarnLock;
var
  D: TGittanDependencies;
begin
  D := ParseYarnLock('# yarn lockfile v1' + LE + LE + 'vue@^3.4, vue@^3.0:' + LE +
    '  version "3.4.21"' + LE + '  resolved "https://x"' + LE + LE +
    '"@vitejs/plugin-vue@^5":' + LE + '  version "5.0.4"' + LE);
  AssertEquals('vue @vitejs/plugin-vue', Names(D));
  AssertEquals('3.4.21', Find(D, 'vue').Resolved);
  { The berry form. }
  D := ParseYarnLock('"vue@npm:^3.4":' + LE + '  version: 3.4.21' + LE + '  resolution: "x"' + LE);
  AssertEquals('vue', Names(D));
  AssertEquals('3.4.21', Find(D, 'vue').Resolved);
end;

procedure TProjNodeTest.TestPnpmLock;
var
  D: TGittanDependencies;
begin
  D := ParsePnpmLock('lockfileVersion: ''9.0''' + LE + 'importers:' + LE + '  .:' + LE +
    '    dependencies:' + LE + '      vue:' + LE + '        specifier: ^3.4' + LE +
    'packages:' + LE + '  vue@3.4.21:' + LE + '    resolution: {integrity: x}' + LE +
    '  ''@vitejs/plugin-vue@5.0.4(vite@5.1.0)'':' + LE + '    resolution: {integrity: y}' + LE +
    'snapshots:' + LE + '  other@1.0.0:' + LE);
  AssertEquals('vue @vitejs/plugin-vue', Names(D));
  AssertEquals('3.4.21', Find(D, 'vue').Resolved);
  AssertEquals('5.0.4', Find(D, '@vitejs/plugin-vue').Resolved);
  { The older form with a slash. }
  D := ParsePnpmLock('packages:' + LE + '  /vue/3.2.0:' + LE + '    dev: false' + LE +
    '  /@scope/name/1.0.0:' + LE);
  AssertEquals('vue @scope/name', Names(D));
  AssertEquals('1.0.0', Find(D, '@scope/name').Resolved);
end;

procedure TProjNodeTest.TestNodeInfo;
var
  I: TNodeInfo;
begin
  I := ParseNodeInfo('{"name": "x", "type": "module", "packageManager": "pnpm@9.1.0",' +
    ' "engines": {"node": ">=20", "npm": ">=10"}, "workspaces": {"packages": ["apps/*", "libs/*"]}}');
  AssertEquals('x', I.Name);
  AssertEquals('module', I.ModuleType);
  AssertEquals('pnpm@9.1.0', I.PackageManager);
  AssertEquals('node >=20, npm >=10', string.Join(', ', I.Engines));
  AssertEquals('apps/* libs/*', string.Join(' ', I.Workspaces));
  I := ParseNodeInfo('{"workspaces": ["a"]}');
  AssertEquals('a', string.Join(' ', I.Workspaces));
  AssertEquals('', ParseNodeInfo('nope').Name);
end;

procedure TProjNodeTest.TestNodeManager;
begin
  Put('package.json', '{}');
  AssertEquals('npm', NodePackageManager(FDir));
  Put('yarn.lock', '');
  AssertEquals('yarn', NodePackageManager(FDir));
  Put('package.json', '{"packageManager": "pnpm@9.1.0"}');
  AssertEquals('the field wins', 'pnpm@9.1.0', NodePackageManager(FDir));
end;

procedure TProjNodeTest.TestNodeSection;
var
  C: TGittanProjectContext;
  Sec: TGittanProjectSection;
  R: TGittanProjectRow;
begin
  Put('package.json', '{"name": "x", "packageManager": "pnpm@9.1.0", "dependencies": {"vue": "^3"}}');
  Put('pnpm-lock.yaml', 'packages:' + LE + '  vue@3.4.0:' + LE);
  C := TGittanProjectContext.Create(FDir, '', nil);
  try
    Sec := TGittanNodeKind.Section(C, 'package.json');
  finally
    C.Free;
  end;
  AssertTrue(Sec.Blocks[0].Kind = pbFacts);
  R := Sec.Blocks[0].Rows[1];
  AssertEquals('Package manager', R.Cells[0].Text);
  AssertEquals('pnpm@9.1.0', R.Cells[1].Text);
  AssertEquals('pnpm install', R.Cells[2].Command);
  AssertEquals('3.4.0', Sec.Blocks[1].Rows[0].Cells[2].Text);
  AssertEquals('no commands of its own', 0, Length(TGittanNodeKind.Commands(FDir)));
end;

procedure TProjNodeTest.TestNodeLockOfManager;
begin
  Put('package.json', '{"packageManager": "pnpm@9.1.0"}');
  Put('package-lock.json', '{}');
  Put('pnpm-lock.yaml', '');
  AssertEquals('the lock of the manager named', 'pnpm-lock.yaml', TGittanNodeKind.LockFile(FDir));
  Put('package.json', '{"packageManager": "yarn@4.1.0"}');
  AssertEquals('without its lock: the first there', 'package-lock.json',
    TGittanNodeKind.LockFile(FDir));
  Put('package.json', '{}');
  AssertEquals('pnpm by its lock, npm''s lock there too', 'pnpm-lock.yaml',
    TGittanNodeKind.LockFile(FDir));
  AssertEquals('pnpm', NodeTool('pnpm@9.1.0+sha512.abc'));
  AssertEquals('npm', NodeTool('npm'));
  AssertEquals('', NodeTool('rm -rf ~; npm'));
  AssertEquals('', NodeTool('evil@1'));
end;

procedure TProjNodeTest.TestNodeUnknownManager;
var
  C: TGittanProjectContext;
  Sec: TGittanProjectSection;
  R: TGittanProjectRow;
begin
  Put('package.json', '{"name": "x", "packageManager": "x; touch pwned@1"}');
  C := TGittanProjectContext.Create(FDir, '', nil);
  try
    Sec := TGittanNodeKind.Section(C, 'package.json');
  finally
    C.Free;
  end;
  R := Sec.Blocks[0].Rows[1];
  AssertEquals('Package manager', R.Cells[0].Text);
  AssertEquals('shown as written', 'x; touch pwned@1', R.Cells[1].Text);
  AssertEquals('no Install button', 2, Length(R.Cells));
end;

initialization
  RegisterTest(TProjNodeTest);

end.
