unit testmanifest;

{** Tests of gittan.manifest: the TOML reader, and the dependencies,
  resolved versions and project versions read from the manifests and
  lock files of each kind of project. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.manifest;

type
  TManifestTest = class(TTestCase)
  private
    function Names(const ADeps: TGittanDependencies): string;
    function Find(const ADeps: TGittanDependencies; const AName: string): TGittanDependency;
  published
    procedure TestTomlTables;
    procedure TestTomlMultiLine;
    procedure TestTomlValues;
    procedure TestCargo;
    procedure TestCargoTables;
    procedure TestCargoLock;
    procedure TestPackageJson;
    procedure TestPackageLockV3;
    procedure TestPackageLockV1;
    procedure TestYarnLock;
    procedure TestPnpmLock;
    procedure TestGoMod;
    procedure TestPyproject;
    procedure TestPoetry;
    procedure TestRequirements;
    procedure TestPythonLock;
    procedure TestSplitRequirement;
    procedure TestLpi;
    procedure TestLpiVersion;
  end;

implementation

function TManifestTest.Names(const ADeps: TGittanDependencies): string;
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

function TManifestTest.Find(const ADeps: TGittanDependencies;
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

const
  LE = LineEnding;

procedure TManifestTest.TestTomlTables;
var
  E: TGittanTomlEntries;
begin
  E := ReadToml('top = 1' + LE + '# comment' + LE + '[package]' + LE + 'name = "x" # trailing' +
    LE + '[[bin]]' + LE + 'name = "a"' + LE + '[[bin]]' + LE + 'name = "b"' + LE +
    '[tool."my.thing"]' + LE + '"quoted key" = ''s''' + LE);
  AssertEquals(5, Length(E));
  AssertEquals('', E[0].Table);
  AssertEquals('top', E[0].Key);
  AssertEquals(-1, E[0].Index);
  AssertEquals('package', E[1].Table);
  AssertEquals('"x"', E[1].Value);
  AssertEquals('bin', E[2].Table);
  AssertEquals(0, E[2].Index);
  AssertEquals(1, E[3].Index);
  AssertEquals('tool."my.thing"', E[4].Table);
  AssertEquals('quoted key', E[4].Key);
  AssertEquals('s', TomlString(E[4].Value));
end;

procedure TManifestTest.TestTomlMultiLine;
var
  E: TGittanTomlEntries;
begin
  E := ReadToml('[project]' + LE + 'dependencies = [' + LE + '  "a>=1", # one' + LE +
    '  "b",' + LE + ']' + LE + 'next = 2' + LE);
  AssertEquals(2, Length(E));
  AssertEquals('a>=1 b', string.Join(' ', TomlArrayStrings(E[0].Value)));
  AssertEquals('next', E[1].Key);
end;

procedure TManifestTest.TestTomlValues;
begin
  AssertEquals('1.0', TomlString('"1.0"'));
  AssertEquals('', TomlString('{ version = "1" }'));
  AssertEquals('"1"', TomlInlineValue('{ version = "1", features = ["a", "b"] }', 'version'));
  AssertEquals('["a", "b"]', TomlInlineValue('{ version = "1", features = ["a", "b"] }',
    'features'));
  AssertEquals('', TomlInlineValue('"1"', 'version'));
  AssertEquals(2, Length(TomlArrayStrings('["a", ''b'']')));
  AssertEquals(0, Length(TomlArrayStrings('"a"')));
end;

procedure TManifestTest.TestCargo;
var
  D: TGittanDependencies;
begin
  D := ParseCargoDependencies('[package]' + LE + 'name = "x"' + LE + 'version = "0.3.1"' + LE +
    '[dependencies]' + LE + 'serde = "1.0"' + LE +
    'tokio = { version = "1", features = ["full"] }' + LE + 'local = { path = "../local" }' + LE +
    'shared = { workspace = true }' + LE + '[dev-dependencies]' + LE + 'criterion = "0.5"' + LE +
    '[build-dependencies]' + LE + 'cc = "1"' + LE);
  AssertEquals('serde tokio local shared criterion cc', Names(D));
  AssertEquals('1.0', Find(D, 'serde').Version);
  AssertEquals('1', Find(D, 'tokio').Version);
  AssertEquals('', Find(D, 'local').Version);
  AssertEquals('workspace', Find(D, 'shared').Version);
  AssertEquals('dev', Find(D, 'criterion').Group);
  AssertEquals('build', Find(D, 'cc').Group);
  AssertEquals('', Find(D, 'serde').Group);
  AssertEquals('0.3.1', CargoVersion('[package]' + LE + 'version = "0.3.1"'));
  AssertEquals('', CargoVersion('[dependencies]' + LE + 'version = "9"'));
end;

procedure TManifestTest.TestCargoTables;
var
  D: TGittanDependencies;
begin
  D := ParseCargoDependencies('[dependencies.serde]' + LE + 'version = "1.0"' + LE +
    'features = ["derive"]' + LE + '[target.''cfg(unix)''.dependencies]' + LE + 'libc = "0.2"' +
    LE + '[workspace.dependencies]' + LE + 'anyhow = "1"' + LE + '[dependencies.mine]' + LE +
    'path = "mine"' + LE);
  AssertEquals('serde libc anyhow mine', Names(D));
  AssertEquals('1.0', Find(D, 'serde').Version);
  AssertEquals('0.2', Find(D, 'libc').Version);
  AssertEquals('', Find(D, 'mine').Version);
end;

procedure TManifestTest.TestCargoLock;
var
  D: TGittanDependencies;
begin
  D := ParseCargoLock('version = 3' + LE + LE + '[[package]]' + LE + 'name = "serde"' + LE +
    'version = "1.0.210"' + LE + 'source = "registry"' + LE + LE + '[[package]]' + LE +
    'name = "tokio"' + LE + 'version = "1.40.0"' + LE);
  AssertEquals('serde tokio', Names(D));
  AssertEquals('1.0.210', Find(D, 'serde').Resolved);
  AssertEquals('', Find(D, 'serde').Version);
end;

procedure TManifestTest.TestPackageJson;
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

procedure TManifestTest.TestPackageLockV3;
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

procedure TManifestTest.TestPackageLockV1;
var
  D: TGittanDependencies;
begin
  D := ParsePackageLock('{"lockfileVersion": 1, "dependencies": {"vue": {"version": "2.7.0",' +
    ' "requires": {"csstype": "^2"}}}}');
  AssertEquals('vue', Names(D));
  AssertEquals('2.7.0', Find(D, 'vue').Resolved);
end;

procedure TManifestTest.TestYarnLock;
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

procedure TManifestTest.TestPnpmLock;
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

procedure TManifestTest.TestGoMod;
var
  D: TGittanDependencies;
begin
  D := ParseGoMod('module example.com/x' + LE + LE + 'go 1.22' + LE + LE +
    'require github.com/one/one v1.2.3' + LE + LE + 'require (' + LE +
    #9'github.com/two/two v2.0.0 // indirect' + LE + #9'golang.org/x/text v0.14.0' + LE +
    ')' + LE + 'replace github.com/two/two => ../two' + LE);
  AssertEquals('github.com/one/one github.com/two/two golang.org/x/text', Names(D));
  AssertEquals('v1.2.3', Find(D, 'github.com/one/one').Version);
  AssertEquals('v1.2.3', Find(D, 'github.com/one/one').Resolved);
  AssertEquals('indirect', Find(D, 'github.com/two/two').Group);
  AssertEquals('', Find(D, 'golang.org/x/text').Group);
end;

procedure TManifestTest.TestPyproject;
var
  D: TGittanDependencies;
begin
  D := ParsePyproject('[project]' + LE + 'name = "x"' + LE + 'version = "1.4.0"' + LE +
    'dependencies = [' + LE + '  "requests>=2.0,<3",' + LE + '  "click",' + LE +
    '  "rich[jupyter] ~= 13.0 ; python_version > ''3.8''",' + LE + ']' + LE +
    '[project.optional-dependencies]' + LE + 'test = ["pytest>=8"]' + LE +
    '[dependency-groups]' + LE + 'dev = ["ruff", "mypy==1.10"]' + LE);
  AssertEquals('requests click rich pytest ruff mypy', Names(D));
  AssertEquals('>=2.0,<3', Find(D, 'requests').Version);
  AssertEquals('', Find(D, 'click').Version);
  AssertEquals('~= 13.0', Find(D, 'rich').Version);
  AssertEquals('test', Find(D, 'pytest').Group);
  AssertEquals('dev', Find(D, 'ruff').Group);
  AssertEquals('==1.10', Find(D, 'mypy').Version);
  AssertEquals('1.4.0', PyprojectVersion('[project]' + LE + 'version = "1.4.0"'));
end;

procedure TManifestTest.TestPoetry;
var
  D: TGittanDependencies;
begin
  D := ParsePyproject('[tool.poetry]' + LE + 'name = "x"' + LE + 'version = "0.9"' + LE +
    '[tool.poetry.dependencies]' + LE + 'python = "^3.11"' + LE + 'requests = "^2.31"' + LE +
    'mine = { path = "../mine" }' + LE + 'rich = { version = "^13", optional = true }' + LE +
    '[tool.poetry.dev-dependencies]' + LE + 'black = "*"' + LE +
    '[tool.poetry.group.test.dependencies]' + LE + 'pytest = "^8"' + LE);
  AssertEquals('python is not a dependency', 'requests mine rich black pytest', Names(D));
  AssertEquals('^2.31', Find(D, 'requests').Version);
  AssertEquals('', Find(D, 'mine').Version);
  AssertEquals('^13', Find(D, 'rich').Version);
  AssertEquals('dev', Find(D, 'black').Group);
  AssertEquals('test', Find(D, 'pytest').Group);
  AssertEquals('0.9', PyprojectVersion('[tool.poetry]' + LE + 'version = "0.9"'));
  AssertEquals('the project table wins', '2', PyprojectVersion('[tool.poetry]' + LE +
    'version = "0.9"' + LE + '[project]' + LE + 'version = "2"'));
end;

procedure TManifestTest.TestRequirements;
var
  D: TGittanDependencies;
begin
  D := ParseRequirements('# deps' + LE + '-r base.txt' + LE + 'requests==2.31.0  # pinned' + LE +
    'click>=8' + LE + 'rich[jupyter]' + LE + '-e .' + LE + 'git+https://x/y.git#egg=z' + LE +
    './local' + LE + LE);
  AssertEquals('requests click rich', Names(D));
  AssertEquals('==2.31.0', Find(D, 'requests').Version);
  AssertEquals('>=8', Find(D, 'click').Version);
  AssertEquals('', Find(D, 'rich').Version);
end;

procedure TManifestTest.TestPythonLock;
var
  D: TGittanDependencies;
begin
  D := ParsePythonLock('version = 1' + LE + 'requires-python = ">=3.11"' + LE + LE +
    '[[package]]' + LE + 'name = "requests"' + LE + 'version = "2.32.3"' + LE +
    'source = { registry = "https://pypi.org/simple" }' + LE + 'dependencies = [' + LE +
    '    { name = "certifi" },' + LE + ']' + LE + LE + '[[package]]' + LE + 'name = "certifi"' +
    LE + 'version = "2024.8.30"' + LE + LE + '[package.metadata]' + LE + 'x = 1' + LE);
  AssertEquals('requests certifi', Names(D));
  AssertEquals('2.32.3', Find(D, 'requests').Resolved);
end;

procedure TManifestTest.TestSplitRequirement;
var
  Name, Version: string;
begin
  SplitRequirement('requests', Name, Version);
  AssertEquals('requests', Name);
  AssertEquals('', Version);
  SplitRequirement('Requests_Two.x [a,b] >= 2, < 3 ; sys_platform == "win32"', Name, Version);
  AssertEquals('Requests_Two.x', Name);
  AssertEquals('>= 2, < 3', Version);
  SplitRequirement('pkg @ https://x/pkg.whl', Name, Version);
  AssertEquals('pkg', Name);
  AssertEquals('', Version);
  SplitRequirement('old (>=1)', Name, Version);
  AssertEquals('>=1', Version);
end;

procedure TManifestTest.TestLpi;
var
  D: TGittanDependencies;
begin
  { The old form, Item1 and Item2 with a count; the new one, Item. }
  D := ParseLpiPackages('<CONFIG><ProjectOptions><RequiredPackages Count="2">' +
    '<Item1><PackageName Value="LCL"/></Item1>' +
    '<Item2><PackageName Value="atsynedit_package"/>' +
    '<MinVersion Major="2" Minor="4" Valid="True"/></Item2>' +
    '</RequiredPackages><Units Count="1"><Item><Filename Value="x.pp"/></Item></Units>' +
    '</ProjectOptions></CONFIG>');
  AssertEquals('LCL atsynedit_package', Names(D));
  AssertEquals('', Find(D, 'LCL').Version);
  AssertEquals('>= 2.4', Find(D, 'atsynedit_package').Version);
  D := ParseLpiPackages('<CONFIG><ProjectOptions><RequiredPackages>' +
    '<Item><PackageName Value="LCL"/></Item><Item><PackageName Value="LazUtils"/></Item>' +
    '</RequiredPackages></ProjectOptions></CONFIG>');
  AssertEquals('LCL LazUtils', Names(D));
  AssertEquals(0, Length(ParseLpiPackages('<CONFIG/>')));
end;

procedure TManifestTest.TestLpiVersion;
begin
  AssertEquals('1.2.0', LpiVersion('<CONFIG><ProjectOptions><VersionInfo>' +
    '<UseVersionInfo Value="True"/><MajorVersionNr Value="1"/><MinorVersionNr Value="2"/>' +
    '</VersionInfo></ProjectOptions></CONFIG>'));
  AssertEquals('1.2.3.4', LpiVersion('<VersionInfo><UseVersionInfo Value="True"/>' +
    '<MajorVersionNr Value="1"/><MinorVersionNr Value="2"/><RevisionNr Value="3"/>' +
    '<BuildNr Value="4"/></VersionInfo>'));
  AssertEquals('not in use', '', LpiVersion('<VersionInfo><MajorVersionNr Value="1"/>' +
    '</VersionInfo>'));
  AssertEquals('', LpiVersion('<CONFIG/>'));
end;

initialization
  RegisterTest(TManifestTest);

end.
