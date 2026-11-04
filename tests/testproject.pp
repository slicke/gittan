unit testproject;

{** Tests of gittan.project: the kinds of project told by the files at
  a root, their commands, the registry, and how DiscoverRepoCommands in
  gittan.repocommands lists them and lets the commands file keep them
  to some kinds. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.project, gittan.repocommands,
  testhelpers;

type
  TProjectTest = class(TTestCase)
  private
    FDir: string;
    procedure Put(const ARel, AText: string);
    function Names(const ACommands: TGittanProjectCommands): string;
    function CommandOf(const ACommands: TGittanProjectCommands; const AName: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRegistry;
    procedure TestNothing;
    procedure TestRust;
    procedure TestRustLibrary;
    procedure TestGo;
    procedure TestGoLibrary;
    procedure TestLazarusOne;
    procedure TestLazarusSeveral;
    procedure TestLazarusProgramOnly;
    procedure TestPythonPlain;
    procedure TestPythonUv;
    procedure TestPythonPoetry;
    procedure TestPythonRequirements;
    procedure TestSeveralKinds;
    procedure TestDiscoverLists;
    procedure TestDiscoverKeyFromFile;
    procedure TestProjectLine;
    procedure TestProjectLineNone;
    procedure TestProjectLineUnknown;
  end;

implementation

procedure TProjectTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-project-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
end;

procedure TProjectTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TProjectTest.Put(const ARel, AText: string);
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

function TProjectTest.Names(const ACommands: TGittanProjectCommands): string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(ACommands) do
  begin
    if i > 0 then
      Result := Result + ' ';
    Result := Result + ACommands[i].Name;
  end;
end;

function TProjectTest.CommandOf(const ACommands: TGittanProjectCommands;
  const AName: string): string;
var
  i: integer;
begin
  for i := 0 to High(ACommands) do
    if ACommands[i].Name = AName then
      Exit(ACommands[i].Command);
  Result := '';
end;

procedure TProjectTest.TestRegistry;
var
  Kinds: TGittanProjectKindClasses;
begin
  Kinds := ProjectKinds;
  AssertEquals('four kinds built in', 4, Length(Kinds));
  AssertEquals('Lazarus', Kinds[0].Name);
  AssertEquals('Rust', Kinds[1].Name);
  AssertEquals('Go', Kinds[2].Name);
  AssertEquals('Python', Kinds[3].Name);
  AssertTrue('by name, any case', ProjectKindByName('rust') = Kinds[1]);
  AssertTrue('unknown', ProjectKindByName('cobol') = nil);
  { Registering one again changes nothing. }
  RegisterProjectKind(Kinds[0]);
  AssertEquals(4, Length(ProjectKinds));
end;

procedure TProjectTest.TestNothing;
begin
  Put('README.md', '# hi');
  AssertEquals('no kind', 0, Length(DetectProjects(FDir)));
  AssertEquals('no root', 0, Length(DetectProjects('')));
  AssertEquals('missing root', 0, Length(DetectProjects(FDir + '-missing')));
end;

procedure TProjectTest.TestRust;
var
  P: TGittanProjects;
  C: TGittanProjectCommands;
begin
  Put('Cargo.toml', '[package]' + LineEnding + 'name = "x"' + LineEnding);
  Put('src/main.rs', 'fn main() {}');
  P := DetectProjects(FDir);
  AssertEquals(1, Length(P));
  AssertEquals('Rust', P[0].Name);
  AssertEquals('Cargo.toml', P[0].Manifest);
  C := P[0].Kind.Commands(FDir);
  AssertEquals('build run test check clippy fmt doc', Names(C));
  AssertEquals('cargo run', CommandOf(C, 'run'));
end;

procedure TProjectTest.TestRustLibrary;
var
  C: TGittanProjectCommands;
begin
  Put('Cargo.toml', '[package]' + LineEnding + 'name = "x"' + LineEnding);
  Put('src/lib.rs', '');
  C := DetectProjects(FDir)[0].Kind.Commands(FDir);
  AssertEquals('no run without a binary', 'build test check clippy fmt doc', Names(C));
  Put('Cargo.toml', '[package]' + LineEnding + '[[bin]]' + LineEnding + 'name = "x"' + LineEnding);
  C := DetectProjects(FDir)[0].Kind.Commands(FDir);
  AssertEquals('a [[bin]] runs', 'build run test check clippy fmt doc', Names(C));
end;

procedure TProjectTest.TestGo;
var
  P: TGittanProjects;
  C: TGittanProjectCommands;
begin
  Put('go.mod', 'module example.com/x' + LineEnding);
  Put('main.go', '// a tool' + LineEnding + 'package main' + LineEnding);
  P := DetectProjects(FDir);
  AssertEquals(1, Length(P));
  AssertEquals('Go', P[0].Name);
  AssertEquals('go.mod', P[0].Manifest);
  C := P[0].Kind.Commands(FDir);
  AssertEquals('build run test vet fmt', Names(C));
  AssertEquals('go test ./...', CommandOf(C, 'test'));
end;

procedure TProjectTest.TestGoLibrary;
var
  C: TGittanProjectCommands;
begin
  Put('go.mod', 'module example.com/x' + LineEnding);
  Put('x.go', 'package x' + LineEnding);
  C := DetectProjects(FDir)[0].Kind.Commands(FDir);
  AssertEquals('no run without package main', 'build test vet fmt', Names(C));
end;

procedure TProjectTest.TestLazarusOne;
var
  P: TGittanProjects;
  C: TGittanProjectCommands;
begin
  Put('Gittan.lpi', '<CONFIG/>');
  Put('Gittan.lpr', 'program Gittan; begin end.');
  P := DetectProjects(FDir);
  AssertEquals(1, Length(P));
  AssertEquals('Lazarus', P[0].Name);
  AssertEquals('Gittan.lpi', P[0].Manifest);
  C := P[0].Kind.Commands(FDir);
  AssertEquals('build', Names(C));
  AssertTrue('lazbuild of the project: ' + C[0].Command,
    Pos('lazbuild', C[0].Command) > 0);
  AssertTrue(Pos(' Gittan.lpi', C[0].Command) > 0);
end;

procedure TProjectTest.TestLazarusSeveral;
var
  P: TGittanProjects;
  C: TGittanProjectCommands;
begin
  Put('b.lpi', '<CONFIG/>');
  Put('a.lpi', '<CONFIG/>');
  P := DetectProjects(FDir);
  AssertEquals('a.lpi +1', P[0].Manifest);
  C := P[0].Kind.Commands(FDir);
  AssertEquals('one per project, grouped under build', 'build:a build:b', Names(C));
end;

procedure TProjectTest.TestLazarusProgramOnly;
var
  P: TGittanProjects;
  C: TGittanProjectCommands;
begin
  Put('tool.lpr', 'program tool; begin end.');
  P := DetectProjects(FDir);
  AssertEquals('tool.lpr', P[0].Manifest);
  C := P[0].Kind.Commands(FDir);
  AssertEquals('build', Names(C));
  AssertEquals('fpc tool.lpr', C[0].Command);
end;

procedure TProjectTest.TestPythonPlain;
var
  P: TGittanProjects;
  C: TGittanProjectCommands;
begin
  Put('pyproject.toml', '[project]' + LineEnding + 'name = "x"' + LineEnding +
    '[tool.ruff]' + LineEnding + '[tool.pytest.ini_options]' + LineEnding);
  P := DetectProjects(FDir);
  AssertEquals('Python', P[0].Name);
  AssertEquals('pyproject.toml', P[0].Manifest);
  C := P[0].Kind.Commands(FDir);
  AssertEquals('install test lint fmt', Names(C));
  AssertEquals('pip install -e .', CommandOf(C, 'install'));
  AssertEquals('pytest', CommandOf(C, 'test'));
  AssertEquals('ruff check .', CommandOf(C, 'lint'));
end;

procedure TProjectTest.TestPythonUv;
var
  C: TGittanProjectCommands;
begin
  Put('pyproject.toml', '[project]' + LineEnding + 'name = "x"' + LineEnding);
  Put('uv.lock', '');
  Put('tests/test_x.py', '');
  Put('tox.ini', '');
  C := DetectProjects(FDir)[0].Kind.Commands(FDir);
  AssertEquals('install test tox', Names(C));
  AssertEquals('uv sync', CommandOf(C, 'install'));
  AssertEquals('uv run pytest', CommandOf(C, 'test'));
end;

procedure TProjectTest.TestPythonPoetry;
var
  C: TGittanProjectCommands;
begin
  Put('pyproject.toml', '[tool.poetry]' + LineEnding + 'name = "x"' + LineEnding +
    '[tool.mypy]' + LineEnding);
  C := DetectProjects(FDir)[0].Kind.Commands(FDir);
  AssertEquals('install typecheck', Names(C));
  AssertEquals('poetry install', CommandOf(C, 'install'));
  AssertEquals('poetry run mypy .', CommandOf(C, 'typecheck'));
end;

procedure TProjectTest.TestPythonRequirements;
var
  P: TGittanProjects;
  C: TGittanProjectCommands;
begin
  Put('requirements.txt', 'requests' + LineEnding);
  Put('conftest.py', '');
  P := DetectProjects(FDir);
  AssertEquals('requirements.txt', P[0].Manifest);
  C := P[0].Kind.Commands(FDir);
  AssertEquals('install test', Names(C));
  AssertEquals('pip install -r requirements.txt', CommandOf(C, 'install'));
end;

procedure TProjectTest.TestSeveralKinds;
var
  P: TGittanProjects;
begin
  Put('go.mod', 'module x');
  Put('Cargo.toml', '');
  P := DetectProjects(FDir);
  AssertEquals('both, in the registered order', 2, Length(P));
  AssertEquals('Rust', P[0].Name);
  AssertEquals('Go', P[1].Name);
end;

procedure TProjectTest.TestDiscoverLists;
var
  C: TGittanRepoCommands;
  P: TGittanProjects;
  i, Scripts, Rust, Go: integer;
begin
  Put('package.json', '{"scripts": {"dev": "vite"}}');
  Put('Cargo.toml', '');
  Put('go.mod', 'module x');
  C := DiscoverRepoCommands(FDir, P);
  AssertEquals(2, Length(P));
  Scripts := 0;
  Rust := 0;
  Go := 0;
  for i := 0 to High(C) do
    case C[i].Source of
      csPackage: Inc(Scripts);
      csProject:
        if C[i].Project = 'Rust' then
          Inc(Rust)
        else if C[i].Project = 'Go' then
          Inc(Go)
        else
          Fail('a kind of no name: ' + C[i].Project);
    end;
  AssertEquals('the script', 1, Scripts);
  AssertEquals('the rust commands', 6, Rust);
  AssertEquals('the go commands', 4, Go);
  AssertEquals('the script first', 'dev', C[0].Name);
  AssertEquals('then rust', 'Rust', C[1].Project);
  AssertEquals('then go', 'Go', C[High(C)].Project);
  AssertEquals('what runs', 'cargo build', C[1].Command);
end;

procedure TProjectTest.TestDiscoverKeyFromFile;
var
  C: TGittanRepoCommands;
  i: integer;
begin
  Put('Cargo.toml', '');
  Put('.gittan/commands.ini', '[test]' + LineEnding + 'key = T' + LineEnding +
    '[clippy]' + LineEnding + 'terminal = yes' + LineEnding);
  C := DiscoverRepoCommands(FDir);
  AssertEquals('the sections give keys and are not listed', 6, Length(C));
  for i := 0 to High(C) do
  begin
    AssertTrue('all of the kind', C[i].Source = csProject);
    if C[i].Name = 'test' then
      AssertEquals('T', C[i].Key)
    else
      AssertEquals('no key for ' + C[i].Name, #0, C[i].Key);
    AssertEquals('terminal for ' + C[i].Name, C[i].Name = 'clippy', C[i].Terminal);
  end;
  AssertEquals('found by key', 1, CommandByKey(C, 'T'));
end;

procedure TProjectTest.TestProjectLine;
var
  C: TGittanRepoCommands;
  P: TGittanProjects;
  N: TStringArray;
  i: integer;
begin
  AssertFalse('no line', ParseCommandsProjects('[a]' + LineEnding + 'project = rust', N));
  AssertTrue(ParseCommandsProjects('; hi' + LineEnding + 'Project = Rust, go' + LineEnding +
    '[a]' + LineEnding, N));
  AssertEquals(2, Length(N));
  AssertEquals('Rust', N[0]);
  AssertEquals('go', N[1]);
  { The files say Rust and Go; the line keeps Go and asks for Python,
    which has no file and so no manifest, but is listed as asked. }
  Put('Cargo.toml', '');
  Put('go.mod', 'module x');
  Put('.gittan/commands.ini', 'project = go python' + LineEnding);
  C := DiscoverRepoCommands(FDir, P);
  AssertEquals(2, Length(P));
  AssertEquals('Go', P[0].Name);
  AssertEquals('go.mod', P[0].Manifest);
  AssertEquals('Python', P[1].Name);
  AssertEquals('', P[1].Manifest);
  for i := 0 to High(C) do
    AssertTrue('no rust: ' + C[i].Project, C[i].Project <> 'Rust');
end;

procedure TProjectTest.TestProjectLineNone;
var
  C: TGittanRepoCommands;
  P: TGittanProjects;
  N: TStringArray;
begin
  AssertTrue(ParseCommandsProjects('project = none', N));
  AssertEquals(0, Length(N));
  Put('Cargo.toml', '');
  Put('.gittan/commands.ini', 'project = none' + LineEnding + '[x]' + LineEnding +
    'command = echo' + LineEnding);
  C := DiscoverRepoCommands(FDir, P);
  AssertEquals(0, Length(P));
  AssertEquals('the file''s command alone', 1, Length(C));
  AssertEquals('x', C[0].Name);
end;

procedure TProjectTest.TestProjectLineUnknown;
var
  P: TGittanProjects;
begin
  Put('Cargo.toml', '');
  Put('.gittan/commands.ini', 'project = cobol, rust, rust' + LineEnding);
  P := ProjectsOfRoot(FDir);
  AssertEquals('the unknown is skipped, the repeat once', 1, Length(P));
  AssertEquals('Rust', P[0].Name);
end;

initialization
  RegisterTest(TProjectTest);

end.
