unit gittan.project;

{** The kinds of project a repository can be, told by the files at its
  root: a Lazarus project (a .lpi), a Rust crate (Cargo.toml), a Go
  module (go.mod), a Python project (pyproject.toml, setup.py or
  requirements.txt). A kind knows what file told it and the commands its
  tools run (cargo build, go test ./..., lazbuild X.lpi), which the
  Commands page lists under the kind's name beside the scripts of a
  package.json and the targets of a Makefile, and which
  DiscoverRepoCommands in gittan.repocommands joins with the rest.

  A kind is a class registered as the unit loads (RegisterProjectKind),
  as a forge is: a kind with more to it than these can move to a unit
  of its own, and an extension can ask for the kinds of a repository
  later. Nothing here needs the LCL or runs a program; tested in
  tests/testproject.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  {** A command of a kind's tools: its name on the tile and the shell
    line that runs it, in a terminal when it keeps running. }
  TGittanProjectCommand = record
    Name: string;
    Command: string;
    Terminal: boolean;
  end;
  TGittanProjectCommands = array of TGittanProjectCommand;

  { TGittanProjectKind }

  {** One kind of project. Every method reads files at most; none runs
    a program or touches the network, since the kinds are asked on
    every snapshot. }
  TGittanProjectKind = class
  public
    {** How the interface names it: "Rust", "Go". Short and stable, as
      the commands file names a kind by it. }
    class function Name: string; virtual; abstract;
    {** The file at ARoot that makes it this kind, as the page shows it
      ("Cargo.toml", "Gittan.lpi"), '' when the repository is not one. }
    class function Manifest(const ARoot: string): string; virtual; abstract;
    {** The commands the kind's tools offer for the repository at
      ARoot, in the order the page sorts anyway. }
    class function Commands(const ARoot: string): TGittanProjectCommands; virtual; abstract;
  end;
  TGittanProjectKindClass = class of TGittanProjectKind;

  {** A kind found at a root, with the file that told it. }
  TGittanProject = record
    Kind: TGittanProjectKindClass;
    {** Kind.Name, kept so a record stands on its own. }
    Name: string;
    Manifest: string;
  end;
  TGittanProjects = array of TGittanProject;
  TGittanProjectKindClasses = array of TGittanProjectKindClass;

{** Adds a kind to those DetectProjects asks, in the order registered. }
procedure RegisterProjectKind(AClass: TGittanProjectKindClass);

{** The kinds registered, in that order. }
function ProjectKinds: TGittanProjectKindClasses;

{** The kind named AName, whatever the case; nil for none. }
function ProjectKindByName(const AName: string): TGittanProjectKindClass;

{** Every registered kind the repository at ARoot is, in the order
  registered, each with its manifest. }
function DetectProjects(const ARoot: string): TGittanProjects;

{** A command as a kind returns it. }
function ProjectCommand(const AName, ACommand: string; ATerminal: boolean = False):
  TGittanProjectCommand;

implementation

uses
  gittan.textfile;

var
  GKinds: TGittanProjectKindClasses;

procedure RegisterProjectKind(AClass: TGittanProjectKindClass);
var
  i: integer;
begin
  for i := 0 to High(GKinds) do
    if GKinds[i] = AClass then
      Exit;
  SetLength(GKinds, Length(GKinds) + 1);
  GKinds[High(GKinds)] := AClass;
end;

function ProjectKinds: TGittanProjectKindClasses;
begin
  Result := Copy(GKinds);
end;

function ProjectKindByName(const AName: string): TGittanProjectKindClass;
var
  i: integer;
begin
  for i := 0 to High(GKinds) do
    if SameText(GKinds[i].Name, Trim(AName)) then
      Exit(GKinds[i]);
  Result := nil;
end;

function DetectProjects(const ARoot: string): TGittanProjects;
var
  i: integer;
  Manifest: string;
begin
  Result := nil;
  if (ARoot = '') or not DirectoryExists(ARoot) then
    Exit;
  for i := 0 to High(GKinds) do
  begin
    Manifest := GKinds[i].Manifest(ARoot);
    if Manifest = '' then
      Continue;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Kind := GKinds[i];
    Result[High(Result)].Name := GKinds[i].Name;
    Result[High(Result)].Manifest := Manifest;
  end;
end;

function ProjectCommand(const AName, ACommand: string; ATerminal: boolean): TGittanProjectCommand;
begin
  Result.Name := AName;
  Result.Command := ACommand;
  Result.Terminal := ATerminal;
end;

{ ---------------------------------------------------------------------------
  Helpers the kinds share
  --------------------------------------------------------------------------- }

function RootFile(const ARoot, AName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(ARoot) + AName;
end;

function HasFile(const ARoot, AName: string): boolean;
begin
  Result := FileExists(RootFile(ARoot, AName));
end;

function HasDir(const ARoot, AName: string): boolean;
begin
  Result := DirectoryExists(RootFile(ARoot, AName));
end;

function TextOf(const ARoot, AName: string): string;
begin
  if HasFile(ARoot, AName) then
    Result := ReadFileBytes(RootFile(ARoot, AName))
  else
    Result := '';
end;

{ The files at ARoot whose name ends with AExt, by name. }
function FilesWithExt(const ARoot, AExt: string): TStringArray;
var
  Info: TSearchRec;
  Names: TStringList;
  i: integer;
begin
  Result := nil;
  Names := TStringList.Create;
  try
    if FindFirst(RootFile(ARoot, '*' + AExt), faAnyFile and not faDirectory, Info) = 0 then
    begin
      repeat
        if SameText(ExtractFileExt(Info.Name), AExt) then
          Names.Add(Info.Name);
      until FindNext(Info) <> 0;
      FindClose(Info);
    end;
    Names.Sort;
    SetLength(Result, Names.Count);
    for i := 0 to Names.Count - 1 do
      Result[i] := Names[i];
  finally
    Names.Free;
  end;
end;

procedure Add(var ACommands: TGittanProjectCommands; const ACommand: TGittanProjectCommand);
begin
  SetLength(ACommands, Length(ACommands) + 1);
  ACommands[High(ACommands)] := ACommand;
end;

{ A name for the shell: quoted when it has a space. }
function ShellName(const AName: string): string;
begin
  if Pos(' ', AName) > 0 then
    Result := '"' + AName + '"'
  else
    Result := AName;
end;

{ ---------------------------------------------------------------------------
  Lazarus
  --------------------------------------------------------------------------- }

type
  {** A Lazarus project: a .lpi at the root, built with lazbuild; a
    .lpr alone is built with fpc. }
  TGittanLazarusKind = class(TGittanProjectKind)
  public
    class function Name: string; override;
    class function Manifest(const ARoot: string): string; override;
    class function Commands(const ARoot: string): TGittanProjectCommands; override;
  end;

class function TGittanLazarusKind.Name: string;
begin
  Result := 'Lazarus';
end;

class function TGittanLazarusKind.Manifest(const ARoot: string): string;
var
  Names: TStringArray;
begin
  Names := FilesWithExt(ARoot, '.lpi');
  if Length(Names) = 0 then
    Names := FilesWithExt(ARoot, '.lpr');
  if Length(Names) = 0 then
    Result := ''
  else if Length(Names) = 1 then
    Result := Names[0]
  else
    Result := Format('%s +%d', [Names[0], Length(Names) - 1]);
end;

{ lazbuild as the shell finds it, or where Lazarus is usually installed
  when it is not on the PATH, as an app started from the Finder has a
  short one. }
function LazbuildCommand: string;
const
  Places: array[0..5] of string = (
    '/Applications/lazarus/lazbuild', '/usr/local/bin/lazbuild', '/usr/bin/lazbuild',
    '/usr/lib/lazarus/lazbuild', 'C:\lazarus\lazbuild.exe', 'C:\fpcupdeluxe\lazarus\lazbuild.exe');
var
  Place, Home: string;
begin
  Result := 'lazbuild';
  Home := GetEnvironmentVariable('HOME');
  if (Home <> '') and FileExists(Home + '/fpcupdeluxe/lazarus/lazbuild') then
    Exit(Home + '/fpcupdeluxe/lazarus/lazbuild');
  for Place in Places do
    if FileExists(Place) then
      Exit(Place);
end;

class function TGittanLazarusKind.Commands(const ARoot: string): TGittanProjectCommands;
var
  Names: TStringArray;
  FileName, Tool, Short: string;
  Several: boolean;
begin
  Result := nil;
  Names := FilesWithExt(ARoot, '.lpi');
  if Length(Names) > 0 then
    Tool := LazbuildCommand
  else
  begin
    Names := FilesWithExt(ARoot, '.lpr');
    Tool := 'fpc';
  end;
  Several := Length(Names) > 1;
  for FileName in Names do
  begin
    Short := ChangeFileExt(FileName, '');
    if Several then
      Add(Result, ProjectCommand('build:' + Short, ShellName(Tool) + ' ' + ShellName(FileName)))
    else
      Add(Result, ProjectCommand('build', ShellName(Tool) + ' ' + ShellName(FileName)));
  end;
end;

{ ---------------------------------------------------------------------------
  Rust
  --------------------------------------------------------------------------- }

type
  {** A Rust crate or workspace: Cargo.toml at the root. }
  TGittanRustKind = class(TGittanProjectKind)
  public
    class function Name: string; override;
    class function Manifest(const ARoot: string): string; override;
    class function Commands(const ARoot: string): TGittanProjectCommands; override;
  end;

class function TGittanRustKind.Name: string;
begin
  Result := 'Rust';
end;

class function TGittanRustKind.Manifest(const ARoot: string): string;
begin
  if HasFile(ARoot, 'Cargo.toml') then
    Result := 'Cargo.toml'
  else
    Result := '';
end;

class function TGittanRustKind.Commands(const ARoot: string): TGittanProjectCommands;
begin
  Result := nil;
  Add(Result, ProjectCommand('build', 'cargo build'));
  { A binary to run: a main.rs, or a [[bin]] the manifest names. }
  if FileExists(RootFile(ARoot, 'src') + PathDelim + 'main.rs') or
    (Pos('[[bin]]', TextOf(ARoot, 'Cargo.toml')) > 0) then
    Add(Result, ProjectCommand('run', 'cargo run'));
  Add(Result, ProjectCommand('test', 'cargo test'));
  Add(Result, ProjectCommand('check', 'cargo check'));
  Add(Result, ProjectCommand('clippy', 'cargo clippy'));
  Add(Result, ProjectCommand('fmt', 'cargo fmt'));
  Add(Result, ProjectCommand('doc', 'cargo doc'));
end;

{ ---------------------------------------------------------------------------
  Go
  --------------------------------------------------------------------------- }

type
  {** A Go module: go.mod at the root. }
  TGittanGoKind = class(TGittanProjectKind)
  public
    class function Name: string; override;
    class function Manifest(const ARoot: string): string; override;
    class function Commands(const ARoot: string): TGittanProjectCommands; override;
  end;

class function TGittanGoKind.Name: string;
begin
  Result := 'Go';
end;

class function TGittanGoKind.Manifest(const ARoot: string): string;
begin
  if HasFile(ARoot, 'go.mod') then
    Result := 'go.mod'
  else
    Result := '';
end;

{ Whether a .go file at the root is of package main, so "go run ." has
  something to run. A line "package main", first on its line, is
  looked for; a comment that says so counts too, which is harmless. }
function RootIsMainPackage(const ARoot: string): boolean;
var
  Name, Text: string;
  Start: integer;
  Line: string;
begin
  for Name in FilesWithExt(ARoot, '.go') do
  begin
    Text := TextOf(ARoot, Name);
    Start := 1;
    while NextLine(Text, Start, Line) do
    begin
      Line := Trim(Line);
      if (Line = 'package main') or (Pos('package main ', Line + ' ') = 1) then
        Exit(True);
    end;
  end;
  Result := False;
end;

class function TGittanGoKind.Commands(const ARoot: string): TGittanProjectCommands;
begin
  Result := nil;
  Add(Result, ProjectCommand('build', 'go build ./...'));
  if RootIsMainPackage(ARoot) then
    Add(Result, ProjectCommand('run', 'go run .'));
  Add(Result, ProjectCommand('test', 'go test ./...'));
  Add(Result, ProjectCommand('vet', 'go vet ./...'));
  Add(Result, ProjectCommand('fmt', 'go fmt ./...'));
end;

{ ---------------------------------------------------------------------------
  Python
  --------------------------------------------------------------------------- }

type
  {** A Python project: pyproject.toml, setup.py or requirements.txt at
    the root, run through uv, poetry or pdm when their lock file is
    there, else plain pip and python. }
  TGittanPythonKind = class(TGittanProjectKind)
  public
    class function Name: string; override;
    class function Manifest(const ARoot: string): string; override;
    class function Commands(const ARoot: string): TGittanProjectCommands; override;
  end;

class function TGittanPythonKind.Name: string;
begin
  Result := 'Python';
end;

class function TGittanPythonKind.Manifest(const ARoot: string): string;
var
  FileName: string;
begin
  for FileName in ['pyproject.toml', 'setup.py', 'requirements.txt'] do
    if HasFile(ARoot, FileName) then
      Exit(FileName);
  Result := '';
end;

class function TGittanPythonKind.Commands(const ARoot: string): TGittanProjectCommands;
var
  Project, Run, Install: string;
begin
  Result := nil;
  Project := TextOf(ARoot, 'pyproject.toml');
  { The tool that owns the environment, by its lock file, or by the
    table it keeps in pyproject.toml before it has locked. }
  if HasFile(ARoot, 'uv.lock') or (Pos('[tool.uv]', Project) > 0) then
  begin
    Run := 'uv run ';
    Install := 'uv sync';
  end
  else if HasFile(ARoot, 'poetry.lock') or (Pos('[tool.poetry]', Project) > 0) then
  begin
    Run := 'poetry run ';
    Install := 'poetry install';
  end
  else if HasFile(ARoot, 'pdm.lock') or (Pos('[tool.pdm]', Project) > 0) then
  begin
    Run := 'pdm run ';
    Install := 'pdm install';
  end
  else
  begin
    Run := '';
    if HasFile(ARoot, 'requirements.txt') then
      Install := 'pip install -r requirements.txt'
    else
      Install := 'pip install -e .';
  end;
  Add(Result, ProjectCommand('install', Install));
  if (Pos('pytest', Project) > 0) or HasDir(ARoot, 'tests') or HasDir(ARoot, 'test') or
    HasFile(ARoot, 'pytest.ini') or HasFile(ARoot, 'conftest.py') then
    Add(Result, ProjectCommand('test', Run + 'pytest'));
  if Pos('ruff', Project) > 0 then
  begin
    Add(Result, ProjectCommand('lint', Run + 'ruff check .'));
    Add(Result, ProjectCommand('fmt', Run + 'ruff format .'));
  end
  else if HasFile(ARoot, '.flake8') or (Pos('flake8', Project) > 0) then
    Add(Result, ProjectCommand('lint', Run + 'flake8'));
  if Pos('mypy', Project) > 0 then
    Add(Result, ProjectCommand('typecheck', Run + 'mypy .'));
  if HasFile(ARoot, 'tox.ini') then
    Add(Result, ProjectCommand('tox', 'tox'));
  if HasFile(ARoot, 'noxfile.py') then
    Add(Result, ProjectCommand('nox', 'nox'));
end;

initialization
  RegisterProjectKind(TGittanLazarusKind);
  RegisterProjectKind(TGittanRustKind);
  RegisterProjectKind(TGittanGoKind);
  RegisterProjectKind(TGittanPythonKind);

end.
