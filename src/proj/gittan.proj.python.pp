unit gittan.proj.python;

{** The Python driver: a pyproject.toml, setup.py or requirements.txt at
  the root. Its commands go through the tool that owns the environment
  (uv, poetry or pdm by its lock file or its table, else pip): install,
  test with pytest, lint and fmt with ruff (lint with flake8),
  typecheck with mypy, tox and nox. Its section shows the Python the
  project requires, the build backend, the tool, and the programs it
  installs ([project.scripts]), beside the dependencies resolved by
  uv.lock, poetry.lock or pdm.lock. Tested in tests/testprojpython.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.manifest, gittan.project;

type
  {** A program a pyproject.toml installs: its name and the function it
    runs ("pkg.cli:main"). }
  TPythonScript = record
    Name, Target: string;
  end;
  TPythonScripts = array of TPythonScript;

  {** What a pyproject.toml says beside its dependencies. }
  TPythonInfo = record
    Name, RequiresPython, BuildBackend: string;
    Scripts: TPythonScripts;
  end;

  { TGittanPythonKind }

  TGittanPythonKind = class(TGittanProjectKind)
  public
    class function Name: string; override;
    class function Identify(const ARoot: string; out AManifest: string): boolean; override;
    class function Commands(const ARoot: string): TGittanProjectCommands; override;
    class function DependencyFile(const ARoot: string): string; override;
    class function LockFile(const ARoot: string): string; override;
    class function DependencyFileNames: TStringArray; override;
    class function LockFileNames: TStringArray; override;
    class function Dependencies(const AText: string): TGittanDependencies; override;
    class function Locked(const AName, AText: string): TGittanDependencies; override;
    class function Version(const AText: string): string; override;
    class function PackageUrl(const AName: string): string; override;
    class function Checks(AContext: TGittanProjectContext): TGittanProjectChecks; override;
    class function Section(AContext: TGittanProjectContext;
      const AManifest: string): TGittanProjectSection; override;
  end;

{** The dependencies of a pyproject.toml: [project] dependencies (PEP
  508: the name, then its version spec), [project.optional-dependencies]
  (the extras' name as the group), [dependency-groups] (the group's
  name), [tool.poetry.dependencies] (python itself left out),
  [tool.poetry.dev-dependencies] and [tool.poetry.group.X.dependencies]
  (dev, or X). }
function ParsePyproject(const AText: string): TGittanDependencies;

{** The version of a pyproject.toml's [project], else [tool.poetry]; ''
  without one. }
function PyprojectVersion(const AText: string): string;

{** The requirements of a requirements.txt: a PEP 508 line each;
  options (-r, -e, --index-url), comments and URLs are left out. }
function ParseRequirements(const AText: string): TGittanDependencies;

{** The packages of a uv.lock, poetry.lock or pdm.lock, all TOML with
  [[package]] of name and version, each with its version in Resolved. }
function ParsePythonLock(const AText: string): TGittanDependencies;

{** A PEP 508 requirement's name and version spec: "requests[security]
  >=2.0, <3 ; python_version > '3'" gives requests and ">=2.0, <3". }
procedure SplitRequirement(const ASpec: string; out AName, AVersion: string);

{** The [project] name and requires-python (poetry's python dependency
  when there is none), the build backend and the [project.scripts] of a
  pyproject.toml's text. }
function ParsePythonInfo(const AText: string): TPythonInfo;

{** The tool that owns the environment at ARoot, "uv", "poetry", "pdm",
  or '' for plain pip, and the prefix its commands run through
  ("uv run "). }
function PythonTool(const ARoot: string; out ARunPrefix: string): string;

implementation

uses
  gittan.textfile;

resourcestring
  rsVenvTracked = 'Files under %s are committed: the virtual environment, which every ' +
    'computer makes for itself.';
  rsPycTracked = '%s is committed: compiled bytecode, which Python writes again.';
  rsProjectName = 'Project';
  rsRequiresPython = 'Python';
  rsBackend = 'Build backend';
  rsTool = 'Environment';
  rsPlainPip = 'pip';
  rsScripts = 'Programs';
  rsRun = 'Run';

{ ---------------------------------------------------------------------------
  Python
  --------------------------------------------------------------------------- }

procedure SplitRequirement(const ASpec: string; out AName, AVersion: string);
var
  S: string;
  i, P: integer;
begin
  S := Trim(ASpec);
  { The marker after ";" and a URL after "@" are not versions. }
  P := Pos(';', S);
  if P > 0 then
    S := Trim(Copy(S, 1, P - 1));
  P := Pos(' @ ', S);
  if P > 0 then
    S := Trim(Copy(S, 1, P - 1));
  i := 1;
  while (i <= Length(S)) and (S[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.']) do
    Inc(i);
  AName := Copy(S, 1, i - 1);
  S := Trim(Copy(S, i, MaxInt));
  { The extras in brackets. }
  if (S <> '') and (S[1] = '[') then
  begin
    P := Pos(']', S);
    if P > 0 then
      S := Trim(Copy(S, P + 1, MaxInt))
    else
      S := '';
  end;
  if (S <> '') and (S[1] = '(') and (S[Length(S)] = ')') then
    S := Trim(Copy(S, 2, Length(S) - 2));
  AVersion := S;
end;

procedure AddRequirements(var ADeps: TGittanDependencies; const AValue, AGroup: string);
var
  Spec, Name, Version: string;
begin
  for Spec in TomlArrayStrings(AValue) do
  begin
    SplitRequirement(Spec, Name, Version);
    AddDependency(ADeps, Name, Version, '', AGroup);
  end;
end;

{ A poetry dependency's version: the string, or the version of its
  inline table; '' for a path or git one. }
function PoetryRequirement(const AValue: string): string;
begin
  Result := TomlString(AValue);
  if Result = '' then
    Result := TomlString(TomlInlineValue(AValue, 'version'));
end;

function ParsePyproject(const AText: string): TGittanDependencies;
var
  E: TGittanTomlEntry;
  Parts: TStringArray;
begin
  Result := nil;
  for E in ReadToml(AText) do
  begin
    if (E.Table = 'project') and (E.Key = 'dependencies') then
      AddRequirements(Result, E.Value, '')
    else if E.Table = 'project.optional-dependencies' then
      AddRequirements(Result, E.Value, E.Key)
    else if E.Table = 'dependency-groups' then
      AddRequirements(Result, E.Value, E.Key)
    else if E.Table = 'tool.poetry.dependencies' then
    begin
      if E.Key <> 'python' then
        AddDependency(Result, E.Key, PoetryRequirement(E.Value), '', '');
    end
    else if E.Table = 'tool.poetry.dev-dependencies' then
      AddDependency(Result, E.Key, PoetryRequirement(E.Value), '', 'dev')
    else if Pos('tool.poetry.group.', E.Table) = 1 then
    begin
      Parts := E.Table.Split(['.']);
      if (Length(Parts) = 5) and (Parts[4] = 'dependencies') then
        AddDependency(Result, E.Key, PoetryRequirement(E.Value), '', BareKey(Parts[3]));
    end;
  end;
end;

function PyprojectVersion(const AText: string): string;
var
  E: TGittanTomlEntry;
begin
  Result := '';
  for E in ReadToml(AText) do
    if (E.Key = 'version') and ((E.Table = 'project') or
      ((E.Table = 'tool.poetry') and (Result = ''))) then
    begin
      Result := TomlString(E.Value);
      if E.Table = 'project' then
        Exit;
    end;
end;

function ParseRequirements(const AText: string): TGittanDependencies;
var
  Start, P: integer;
  Line, Name, Version: string;
begin
  Result := nil;
  Start := 1;
  while NextLine(AText, Start, Line) do
  begin
    P := Pos('#', Line);
    if P > 0 then
      Line := Copy(Line, 1, P - 1);
    Line := Trim(Line);
    if (Line = '') or (Line[1] = '-') or (Pos('://', Line) > 0) or (Line[1] in ['.', '/']) then
      Continue;
    SplitRequirement(Line, Name, Version);
    AddDependency(Result, Name, Version, '', '');
  end;
end;

function ParsePythonLock(const AText: string): TGittanDependencies;
begin
  Result := ParseTomlLock(AText);
end;


function ParsePythonInfo(const AText: string): TPythonInfo;
var
  E: TGittanTomlEntry;
  PoetryPython: string;
begin
  Result := Default(TPythonInfo);
  PoetryPython := '';
  for E in ReadToml(AText) do
    if E.Table = 'project' then
    begin
      if E.Key = 'name' then
        Result.Name := TomlString(E.Value)
      else if E.Key = 'requires-python' then
        Result.RequiresPython := TomlString(E.Value);
    end
    else if (E.Table = 'build-system') and (E.Key = 'build-backend') then
      Result.BuildBackend := TomlString(E.Value)
    else if (E.Table = 'tool.poetry') and (E.Key = 'name') and (Result.Name = '') then
      Result.Name := TomlString(E.Value)
    else if (E.Table = 'tool.poetry.dependencies') and (E.Key = 'python') then
      PoetryPython := TomlString(E.Value)
    else if (E.Table = 'project.scripts') or (E.Table = 'tool.poetry.scripts') then
    begin
      SetLength(Result.Scripts, Length(Result.Scripts) + 1);
      Result.Scripts[High(Result.Scripts)].Name := E.Key;
      Result.Scripts[High(Result.Scripts)].Target := TomlString(E.Value);
    end;
  if Result.RequiresPython = '' then
    Result.RequiresPython := PoetryPython;
end;

function PythonTool(const ARoot: string; out ARunPrefix: string): string;
var
  Project: string;
begin
  Project := TextOf(ARoot, 'pyproject.toml');
  if HasFile(ARoot, 'uv.lock') or (Pos('[tool.uv]', Project) > 0) then
    Result := 'uv'
  else if HasFile(ARoot, 'poetry.lock') or (Pos('[tool.poetry]', Project) > 0) then
    Result := 'poetry'
  else if HasFile(ARoot, 'pdm.lock') or (Pos('[tool.pdm]', Project) > 0) then
    Result := 'pdm'
  else
    Result := '';
  if Result <> '' then
    ARunPrefix := Result + ' run '
  else
    ARunPrefix := '';
end;

{ A pyproject.toml has a table; a requirements.txt has none. }
function LooksLikeToml(const AText: string): boolean;
begin
  Result := (Pos('[project]', AText) > 0) or (Pos('[tool.', AText) > 0) or
    (Pos('[build-system]', AText) > 0) or (Pos('[dependency-groups]', AText) > 0);
end;

{ TGittanPythonKind }

class function TGittanPythonKind.Name: string;
begin
  Result := 'Python';
end;

class function TGittanPythonKind.Identify(const ARoot: string; out AManifest: string): boolean;
const
  { A typed array, not an array constructor: FPC 3.2.2 gets a for-in
    over a constructor of strings wrong. }
  ManifestNames: array[0..2] of string = ('pyproject.toml', 'setup.py', 'requirements.txt');
var
  FileName: string;
begin
  AManifest := '';
  for FileName in ManifestNames do
    if HasFile(ARoot, FileName) then
    begin
      AManifest := FileName;
      Exit(True);
    end;
  Result := False;
end;

class function TGittanPythonKind.Commands(const ARoot: string): TGittanProjectCommands;
var
  Project, Run, Tool, Install: string;
begin
  Result := nil;
  Project := TextOf(ARoot, 'pyproject.toml');
  Tool := PythonTool(ARoot, Run);
  if Tool = 'uv' then
    Install := 'uv sync'
  else if Tool <> '' then
    Install := Tool + ' install'
  else if HasFile(ARoot, 'requirements.txt') then
    Install := 'pip install -r requirements.txt'
  else
    Install := 'pip install -e .';
  AddProjectCommand(Result, ProjectCommand('install', Install));
  if (Pos('pytest', Project) > 0) or HasDir(ARoot, 'tests') or HasDir(ARoot, 'test') or
    HasFile(ARoot, 'pytest.ini') or HasFile(ARoot, 'conftest.py') then
    AddProjectCommand(Result, ProjectCommand('test', Run + 'pytest'));
  if Pos('ruff', Project) > 0 then
  begin
    AddProjectCommand(Result, ProjectCommand('lint', Run + 'ruff check .'));
    AddProjectCommand(Result, ProjectCommand('fmt', Run + 'ruff format .'));
  end
  else if HasFile(ARoot, '.flake8') or (Pos('flake8', Project) > 0) then
    AddProjectCommand(Result, ProjectCommand('lint', Run + 'flake8'));
  if Pos('mypy', Project) > 0 then
    AddProjectCommand(Result, ProjectCommand('typecheck', Run + 'mypy .'));
  if HasFile(ARoot, 'tox.ini') then
    AddProjectCommand(Result, ProjectCommand('tox', 'tox'));
  if HasFile(ARoot, 'noxfile.py') then
    AddProjectCommand(Result, ProjectCommand('nox', 'nox'));
end;

class function TGittanPythonKind.DependencyFile(const ARoot: string): string;
begin
  if HasFile(ARoot, 'pyproject.toml') then
    Result := 'pyproject.toml'
  else if HasFile(ARoot, 'requirements.txt') then
    Result := 'requirements.txt'
  else
    Result := '';
end;

const
  { A typed array, not an array constructor: FPC 3.2.2 gets a for-in
    over a constructor of strings wrong. }
  PythonLockNames: array[0..2] of string = ('uv.lock', 'poetry.lock', 'pdm.lock');

class function TGittanPythonKind.LockFile(const ARoot: string): string;
var
  FileName: string;
begin
  for FileName in PythonLockNames do
    if HasFile(ARoot, FileName) then
      Exit(FileName);
  Result := '';
end;

class function TGittanPythonKind.DependencyFileNames: TStringArray;
begin
  SetLength(Result, 2);
  Result[0] := 'pyproject.toml';
  Result[1] := 'requirements.txt';
end;

class function TGittanPythonKind.LockFileNames: TStringArray;
var
  i: integer;
begin
  SetLength(Result, Length(PythonLockNames));
  for i := 0 to High(PythonLockNames) do
    Result[i] := PythonLockNames[i];
end;

class function TGittanPythonKind.Dependencies(const AText: string): TGittanDependencies;
begin
  if LooksLikeToml(AText) then
    Result := ParsePyproject(AText)
  else
    Result := ParseRequirements(AText);
end;

class function TGittanPythonKind.Locked(const AName, AText: string): TGittanDependencies;
begin
  Result := ParsePythonLock(AText);
end;

class function TGittanPythonKind.Version(const AText: string): string;
begin
  if LooksLikeToml(AText) then
    Result := PyprojectVersion(AText)
  else
    Result := '';
end;

class function TGittanPythonKind.PackageUrl(const AName: string): string;
begin
  Result := 'https://pypi.org/project/' + AName + '/';
end;

class function TGittanPythonKind.Checks(AContext: TGittanProjectContext): TGittanProjectChecks;
const
  { A typed array, not an array constructor: FPC 3.2.2 gets a for-in
    over a constructor of strings wrong. }
  VenvFolders: array[0..1] of string = ('.venv/', 'venv/');
var
  Path, Folder: string;
begin
  Result := nil;
  for Folder in VenvFolders do
    if AContext.TrackedUnder(Folder, Path) then
      AddProjectCheck(Result, ProjectCheck(Format(rsVenvTracked, [Folder]), Path, '/' + Folder));
  Path := AContext.TrackedWithExt('.pyc');
  if Path <> '' then
    AddProjectCheck(Result, ProjectCheck(Format(rsPycTracked, [Path]), Path, '__pycache__/'));
end;

class function TGittanPythonKind.Section(AContext: TGittanProjectContext;
  const AManifest: string): TGittanProjectSection;
var
  Info: TPythonInfo;
  Facts, Scripts: TGittanProjectBlock;
  Std: TGittanProjectSection;
  Tool, Run: string;
  i: integer;
begin
  Std := StandardSection(AContext, AManifest);
  Result := Std;
  Result.Blocks := nil;
  Info := ParsePythonInfo(TextOf(AContext.Root, 'pyproject.toml'));
  Tool := PythonTool(AContext.Root, Run);
  if Tool = '' then
    Tool := rsPlainPip;
  Facts := ProjectBlock(pbFacts);
  AddFact(Facts, rsProjectName, Info.Name, psStrong);
  AddFact(Facts, rsRequiresPython, Info.RequiresPython);
  AddFact(Facts, rsTool, Tool);
  AddFact(Facts, rsBackend, Info.BuildBackend);
  AddBlock(Result, Facts);
  for i := 0 to High(Std.Blocks) do
    if Std.Blocks[i].Kind <> pbChecks then
      AddBlock(Result, Std.Blocks[i]);
  Scripts := ProjectBlock(pbTable, rsScripts);
  Scripts.RightLast := True;
  for i := 0 to High(Info.Scripts) do
    AddRow(Scripts, ProjectRow([ProjectCell(Info.Scripts[i].Name, psStrong),
      ProjectCell(Info.Scripts[i].Target, psDim), ProjectButton(rsRun,
      'run:' + Info.Scripts[i].Name, Run + ShellName(Info.Scripts[i].Name))]));
  AddBlock(Result, Scripts);
  for i := 0 to High(Std.Blocks) do
    if Std.Blocks[i].Kind = pbChecks then
      AddBlock(Result, Std.Blocks[i]);
end;

initialization
  RegisterProjectKind(TGittanPythonKind);

end.
