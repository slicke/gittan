unit testprojpython;

{** Tests of gittan.proj.python: its parsers as functions of the text, and its
  section of the Project page built in a temporary folder. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.manifest, gittan.project,
  gittan.proj.python, testhelpers;

type
  TProjPythonTest = class(TTestCase)
  private
    FDir: string;
    procedure Put(const ARel, AText: string);
    function Names(const ADeps: TGittanDependencies): string;
    function Find(const ADeps: TGittanDependencies; const AName: string): TGittanDependency;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPyproject;
    procedure TestPoetry;
    procedure TestRequirements;
    procedure TestPythonLock;
    procedure TestSplitRequirement;
    procedure TestPythonInfo;
    procedure TestPythonTool;
    procedure TestPythonSection;
  end;

implementation

const
  LE = LineEnding;

procedure TProjPythonTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-projpython-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
end;

procedure TProjPythonTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TProjPythonTest.Put(const ARel, AText: string);
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

function TProjPythonTest.Names(const ADeps: TGittanDependencies): string;
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

function TProjPythonTest.Find(const ADeps: TGittanDependencies;
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

procedure TProjPythonTest.TestPyproject;
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

procedure TProjPythonTest.TestPoetry;
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

procedure TProjPythonTest.TestRequirements;
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

procedure TProjPythonTest.TestPythonLock;
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

procedure TProjPythonTest.TestSplitRequirement;
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

procedure TProjPythonTest.TestPythonInfo;
var
  I: TPythonInfo;
begin
  I := ParsePythonInfo('[project]' + LE + 'name = "x"' + LE + 'requires-python = ">=3.11"' + LE +
    '[project.scripts]' + LE + 'xtool = "x.cli:main"' + LE + '[build-system]' + LE +
    'build-backend = "hatchling.build"' + LE);
  AssertEquals('x', I.Name);
  AssertEquals('>=3.11', I.RequiresPython);
  AssertEquals('hatchling.build', I.BuildBackend);
  AssertEquals(1, Length(I.Scripts));
  AssertEquals('xtool', I.Scripts[0].Name);
  AssertEquals('x.cli:main', I.Scripts[0].Target);
  I := ParsePythonInfo('[tool.poetry]' + LE + 'name = "y"' + LE + '[tool.poetry.dependencies]' +
    LE + 'python = "^3.10"' + LE);
  AssertEquals('y', I.Name);
  AssertEquals('^3.10', I.RequiresPython);
end;

procedure TProjPythonTest.TestPythonTool;
var
  RunPrefix: string;
begin
  Put('requirements.txt', '');
  AssertEquals('', PythonTool(FDir, RunPrefix));
  AssertEquals('', RunPrefix);
  Put('poetry.lock', '');
  AssertEquals('poetry', PythonTool(FDir, RunPrefix));
  AssertEquals('poetry run ', RunPrefix);
end;

procedure TProjPythonTest.TestPythonSection;
var
  C: TGittanProjectContext;
  Sec: TGittanProjectSection;
  i, Scripts: integer;
begin
  Put('pyproject.toml', '[project]' + LE + 'name = "x"' + LE + 'dependencies = ["click"]' + LE +
    '[project.scripts]' + LE + 'xtool = "x.cli:main"' + LE);
  Put('uv.lock', '');
  C := TGittanProjectContext.Create(FDir, '', nil);
  try
    Sec := TGittanPythonKind.Section(C, 'pyproject.toml');
  finally
    C.Free;
  end;
  Scripts := -1;
  for i := 0 to High(Sec.Blocks) do
    if Sec.Blocks[i].Title = 'Programs' then
      Scripts := i;
  AssertTrue(Scripts > 0);
  AssertEquals('uv run xtool', Sec.Blocks[Scripts].Rows[0].Cells[2].Command);
  AssertEquals('uv', Sec.Blocks[0].Rows[1].Cells[1].Text);
end;

initialization
  RegisterTest(TProjPythonTest);

end.
