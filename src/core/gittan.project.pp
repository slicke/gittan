unit gittan.project;

{** The kinds of project a repository can be, told by the files at its
  root: a Lazarus project (a .lpi), a Node package (package.json), a
  Rust crate (Cargo.toml), a Go module (go.mod), a Python project
  (pyproject.toml, setup.py or requirements.txt). A kind knows what file
  told it, the commands its tools run (cargo build, go test ./...,
  lazbuild X.lpi), which the Commands page lists under the kind's name
  beside the scripts of a package.json and the targets of a Makefile and
  which DiscoverRepoCommands in gittan.repocommands joins with the rest,
  and what its manifest and lock file say (gittan.manifest): the
  dependencies with the versions asked for and resolved, the project's
  own version, and the checks worth a warning (a session file or the
  compiled units committed, a lock file missing), which the Project page
  shows with what changed since the last tag (ProjectReport,
  DependencyChanges).

  A kind is a class registered as the unit loads (RegisterProjectKind),
  as a forge is: a kind with more to it than these can move to a unit
  of its own, and an extension can ask for the kinds of a repository
  later. Nothing here needs the LCL or runs a program; tested in
  tests/testproject.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.manifest;

type
  {** A command of a kind's tools: its name on the tile and the shell
    line that runs it, in a terminal when it keeps running. }
  TGittanProjectCommand = record
    Name: string;
    Command: string;
    Terminal: boolean;
  end;
  TGittanProjectCommands = array of TGittanProjectCommand;

  {** Something a kind warns about: the text, the path it is about
    (relative to the root, '' when it is about no file) and the pattern
    that would put the path in .gitignore ('' when ignoring is not the
    answer). }
  TGittanProjectCheck = record
    Text, Path, IgnorePattern: string;
  end;
  TGittanProjectChecks = array of TGittanProjectCheck;

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
    {** The file at ARoot that lists the dependencies ("Cargo.toml",
      "pyproject.toml" else "requirements.txt", the first .lpi), as a
      path relative to the root; '' when the kind lists none. }
    class function DependencyFile(const ARoot: string): string; virtual;
    {** The lock file at ARoot that holds the resolved versions
      ("Cargo.lock", whichever of package-lock.json, yarn.lock,
      pnpm-lock.yaml and bun.lock is there, uv.lock, poetry.lock or
      pdm.lock); '' when there is none or the kind has none. }
    class function LockFile(const ARoot: string): string; virtual;
    {** The dependencies the text of the dependency file asks for. }
    class function Dependencies(const AText: string): TGittanDependencies; virtual;
    {** The packages the text of the lock file AName resolved, each with
      its version in Resolved. }
    class function Locked(const AName, AText: string): TGittanDependencies; virtual;
    {** The project's own version as the dependency file's text gives
      it; '' when it has none. }
    class function Version(const AText: string): string; virtual;
    {** The web page of the package AName on the kind's registry
      (crates.io, npmjs.com, pkg.go.dev, pypi.org); '' for a kind with
      none. }
    class function PackageUrl(const AName: string): string; virtual;
    {** What is worth a warning at ARoot, given the paths git tracks
      (ATracked, sorted, with "/"): none by default. }
    class function Checks(const ARoot: string; ATracked: TStrings): TGittanProjectChecks;
      virtual;
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

  {** How a dependency differs between two versions of the files. }
  TGittanDependencyChangeKind = (dcAdded, dcRemoved, dcChanged);

  TGittanDependencyChange = record
    Name, Group: string;
    {** The versions as shown: the resolved one when there is one, else
      the one asked for. }
    OldVersion, NewVersion: string;
    Kind: TGittanDependencyChangeKind;
  end;
  TGittanDependencyChanges = array of TGittanDependencyChange;

  {** What the Project page shows of one kind: the files, the version,
    the dependencies with their resolved versions, how they differ from
    those at Since (a tag's name, or '' when there was nothing to
    compare with) and the checks. }
  TGittanProjectReport = record
    Name, Manifest, DependencyFile, LockFile, Version, Since: string;
    Dependencies: TGittanDependencies;
    Changes: TGittanDependencyChanges;
    Checks: TGittanProjectChecks;
  end;
  TGittanProjectReports = array of TGittanProjectReport;

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

{** A check as a kind returns it. }
function ProjectCheck(const AText, APath: string; const AIgnorePattern: string = ''):
  TGittanProjectCheck;

{** The version of a dependency as shown: the resolved one when the
  lock file has it, else what the manifest asks for. }
function DependencyShown(const ADependency: TGittanDependency): string;

{** Fills each dependency's Resolved from the locked packages of the
  same name. }
procedure ResolveDependencies(var ADependencies: TGittanDependencies;
  const ALocked: TGittanDependencies);

{** How ANew's dependencies differ from AOld's, by name and group: the
  ones added and changed in ANew's order (changed when the version
  shown differs), then the ones removed in AOld's. }
function DependencyChanges(const AOld, ANew: TGittanDependencies): TGittanDependencyChanges;

{** What the Project page shows of AProject at ARoot: its dependency
  and lock files read from the root, their old texts (AOldManifest,
  AOldLock, as they were at ASince, '' for a file that was not there)
  giving the changes when ASince is not '', and the checks over the
  tracked paths. }
function ProjectReport(const AProject: TGittanProject; const ARoot: string;
  const AOldManifest, AOldLock, ASince: string; ATracked: TStrings): TGittanProjectReport;

implementation

uses
  gittan.textfile;

resourcestring
  rsLpsTracked = '%s is committed. The session file changes every time the project is opened ' +
    'in Lazarus; it belongs in .gitignore.';
  rsLibTracked = 'Files under lib/ are committed: the compiled units, which every build ' +
    'writes again.';
  rsBackupTracked = 'Files under backup/ are committed: the IDE''s copies of files before ' +
    'an edit.';
  rsNodeModulesTracked = 'Files under node_modules/ are committed. npm install writes them ' +
    'from the lock file.';
  rsNoNodeLock = 'No lock file. npm install writes package-lock.json; commit it so that every ' +
    'clone gets the versions this one has.';
  rsCargoLockUntracked = 'Cargo.lock is not committed. A crate with a binary commits it so ' +
    'that every build uses the versions this one has.';
  rsTargetTracked = 'Files under target/ are committed: cargo''s build output.';
  rsNoGoSum = 'No go.sum. go mod tidy writes it; commit it so that every build checks the ' +
    'modules it downloads.';
  rsVenvTracked = 'Files under %s are committed: the virtual environment, which every ' +
    'computer makes for itself.';
  rsPycTracked = '%s is committed: compiled bytecode, which Python writes again.';

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

function ProjectCheck(const AText, APath: string; const AIgnorePattern: string):
  TGittanProjectCheck;
begin
  Result.Text := AText;
  Result.Path := APath;
  Result.IgnorePattern := AIgnorePattern;
end;

function DependencyShown(const ADependency: TGittanDependency): string;
begin
  if ADependency.Resolved <> '' then
    Result := ADependency.Resolved
  else
    Result := ADependency.Version;
end;

procedure ResolveDependencies(var ADependencies: TGittanDependencies;
  const ALocked: TGittanDependencies);
var
  i, j: integer;
begin
  for i := 0 to High(ADependencies) do
    for j := 0 to High(ALocked) do
      if ALocked[j].Name = ADependencies[i].Name then
      begin
        ADependencies[i].Resolved := ALocked[j].Resolved;
        Break;
      end;
end;

function DependencyChanges(const AOld, ANew: TGittanDependencies): TGittanDependencyChanges;
var
  i, j: integer;
  Found: boolean;

  procedure Add(const AName, AGroup, AOldVersion, ANewVersion: string;
    AKind: TGittanDependencyChangeKind);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Name := AName;
    Result[High(Result)].Group := AGroup;
    Result[High(Result)].OldVersion := AOldVersion;
    Result[High(Result)].NewVersion := ANewVersion;
    Result[High(Result)].Kind := AKind;
  end;

begin
  Result := nil;
  for i := 0 to High(ANew) do
  begin
    Found := False;
    for j := 0 to High(AOld) do
      if (AOld[j].Name = ANew[i].Name) and (AOld[j].Group = ANew[i].Group) then
      begin
        Found := True;
        if DependencyShown(AOld[j]) <> DependencyShown(ANew[i]) then
          Add(ANew[i].Name, ANew[i].Group, DependencyShown(AOld[j]), DependencyShown(ANew[i]),
            dcChanged);
        Break;
      end;
    if not Found then
      Add(ANew[i].Name, ANew[i].Group, '', DependencyShown(ANew[i]), dcAdded);
  end;
  for j := 0 to High(AOld) do
  begin
    Found := False;
    for i := 0 to High(ANew) do
      if (AOld[j].Name = ANew[i].Name) and (AOld[j].Group = ANew[i].Group) then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      Add(AOld[j].Name, AOld[j].Group, DependencyShown(AOld[j]), '', dcRemoved);
  end;
end;

{ The base class: a kind without dependencies or checks. }

class function TGittanProjectKind.DependencyFile(const ARoot: string): string;
begin
  Result := '';
end;

class function TGittanProjectKind.LockFile(const ARoot: string): string;
begin
  Result := '';
end;

class function TGittanProjectKind.Dependencies(const AText: string): TGittanDependencies;
begin
  Result := nil;
end;

class function TGittanProjectKind.Locked(const AName, AText: string): TGittanDependencies;
begin
  Result := nil;
end;

class function TGittanProjectKind.Version(const AText: string): string;
begin
  Result := '';
end;

class function TGittanProjectKind.PackageUrl(const AName: string): string;
begin
  Result := '';
end;

class function TGittanProjectKind.Checks(const ARoot: string;
  ATracked: TStrings): TGittanProjectChecks;
begin
  Result := nil;
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

{ Whether git tracks APath (ATracked is sorted, so it is found by
  bisection) and whether it tracks anything under the folder APrefix
  (with its "/"). }
function Tracked(ATracked: TStrings; const APath: string): boolean;
var
  i: integer;
begin
  Result := ATracked <> nil;
  if Result then
    if (ATracked is TStringList) and TStringList(ATracked).Sorted then
      Result := TStringList(ATracked).Find(APath, i)
    else
      Result := ATracked.IndexOf(APath) >= 0;
end;

function TrackedUnder(ATracked: TStrings; const APrefix: string; out AFirst: string): boolean;
var
  i: integer;
begin
  AFirst := '';
  if ATracked = nil then
    Exit(False);
  for i := 0 to ATracked.Count - 1 do
    if Pos(APrefix, ATracked[i]) = 1 then
    begin
      AFirst := ATracked[i];
      Exit(True);
    end;
  Result := False;
end;

{ The first tracked path whose name ends with AExt. }
function TrackedWithExt(ATracked: TStrings; const AExt: string): string;
var
  i: integer;
begin
  if ATracked <> nil then
    for i := 0 to ATracked.Count - 1 do
      if SameText(ExtractFileExt(ATracked[i]), AExt) then
        Exit(ATracked[i]);
  Result := '';
end;

procedure AddCheck(var AChecks: TGittanProjectChecks; const ACheck: TGittanProjectCheck);
begin
  SetLength(AChecks, Length(AChecks) + 1);
  AChecks[High(AChecks)] := ACheck;
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
    class function DependencyFile(const ARoot: string): string; override;
    class function Dependencies(const AText: string): TGittanDependencies; override;
    class function Version(const AText: string): string; override;
    class function Checks(const ARoot: string; ATracked: TStrings): TGittanProjectChecks;
      override;
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

class function TGittanLazarusKind.DependencyFile(const ARoot: string): string;
var
  Names: TStringArray;
begin
  Names := FilesWithExt(ARoot, '.lpi');
  if Length(Names) > 0 then
    Result := Names[0]
  else
    Result := '';
end;

class function TGittanLazarusKind.Dependencies(const AText: string): TGittanDependencies;
begin
  Result := ParseLpiPackages(AText);
end;

class function TGittanLazarusKind.Version(const AText: string): string;
begin
  Result := LpiVersion(AText);
end;

class function TGittanLazarusKind.Checks(const ARoot: string;
  ATracked: TStrings): TGittanProjectChecks;
var
  Path: string;
begin
  Result := nil;
  Path := TrackedWithExt(ATracked, '.lps');
  if Path <> '' then
    AddCheck(Result, ProjectCheck(Format(rsLpsTracked, [Path]), Path, '*.lps'));
  if TrackedUnder(ATracked, 'lib/', Path) then
    AddCheck(Result, ProjectCheck(rsLibTracked, Path, 'lib/'));
  if TrackedUnder(ATracked, 'backup/', Path) then
    AddCheck(Result, ProjectCheck(rsBackupTracked, Path, 'backup/'));
end;

{ ---------------------------------------------------------------------------
  Node
  --------------------------------------------------------------------------- }

type
  {** A Node package: package.json at the root. Its scripts are the
    Commands page's Scripts section already, so it offers no commands
    of its own; it is a kind for its dependencies and its checks. }
  TGittanNodeKind = class(TGittanProjectKind)
  public
    class function Name: string; override;
    class function Manifest(const ARoot: string): string; override;
    class function Commands(const ARoot: string): TGittanProjectCommands; override;
    class function DependencyFile(const ARoot: string): string; override;
    class function LockFile(const ARoot: string): string; override;
    class function Dependencies(const AText: string): TGittanDependencies; override;
    class function Locked(const AName, AText: string): TGittanDependencies; override;
    class function Version(const AText: string): string; override;
    class function PackageUrl(const AName: string): string; override;
    class function Checks(const ARoot: string; ATracked: TStrings): TGittanProjectChecks;
      override;
  end;

class function TGittanNodeKind.Name: string;
begin
  Result := 'Node';
end;

class function TGittanNodeKind.Manifest(const ARoot: string): string;
begin
  if HasFile(ARoot, 'package.json') then
    Result := 'package.json'
  else
    Result := '';
end;

class function TGittanNodeKind.Commands(const ARoot: string): TGittanProjectCommands;
begin
  Result := nil;
end;

class function TGittanNodeKind.DependencyFile(const ARoot: string): string;
begin
  Result := 'package.json';
end;

class function TGittanNodeKind.LockFile(const ARoot: string): string;
var
  FileName: string;
begin
  for FileName in ['package-lock.json', 'pnpm-lock.yaml', 'yarn.lock', 'bun.lock',
      'npm-shrinkwrap.json'] do
    if HasFile(ARoot, FileName) then
      Exit(FileName);
  Result := '';
end;

class function TGittanNodeKind.Dependencies(const AText: string): TGittanDependencies;
begin
  Result := ParsePackageDependencies(AText);
end;

class function TGittanNodeKind.Locked(const AName, AText: string): TGittanDependencies;
begin
  if AName = 'yarn.lock' then
    Result := ParseYarnLock(AText)
  else if AName = 'pnpm-lock.yaml' then
    Result := ParsePnpmLock(AText)
  else if (AName = 'package-lock.json') or (AName = 'npm-shrinkwrap.json') then
    Result := ParsePackageLock(AText)
  else
    Result := nil;
end;

class function TGittanNodeKind.Version(const AText: string): string;
begin
  Result := PackageVersion(AText);
end;

class function TGittanNodeKind.PackageUrl(const AName: string): string;
begin
  Result := 'https://www.npmjs.com/package/' + AName;
end;

class function TGittanNodeKind.Checks(const ARoot: string;
  ATracked: TStrings): TGittanProjectChecks;
var
  Path: string;
begin
  Result := nil;
  if TrackedUnder(ATracked, 'node_modules/', Path) then
    AddCheck(Result, ProjectCheck(rsNodeModulesTracked, Path, 'node_modules/'));
  if (LockFile(ARoot) = '') and (Length(Dependencies(TextOf(ARoot, 'package.json'))) > 0) then
    AddCheck(Result, ProjectCheck(rsNoNodeLock, ''));
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
    class function DependencyFile(const ARoot: string): string; override;
    class function LockFile(const ARoot: string): string; override;
    class function Dependencies(const AText: string): TGittanDependencies; override;
    class function Locked(const AName, AText: string): TGittanDependencies; override;
    class function Version(const AText: string): string; override;
    class function PackageUrl(const AName: string): string; override;
    class function Checks(const ARoot: string; ATracked: TStrings): TGittanProjectChecks;
      override;
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

{ A binary to run: a main.rs, or a [[bin]] the manifest names. }
function RustHasBinary(const ARoot: string): boolean;
begin
  Result := FileExists(RootFile(ARoot, 'src') + PathDelim + 'main.rs') or
    (Pos('[[bin]]', TextOf(ARoot, 'Cargo.toml')) > 0);
end;

class function TGittanRustKind.Commands(const ARoot: string): TGittanProjectCommands;
begin
  Result := nil;
  Add(Result, ProjectCommand('build', 'cargo build'));
  if RustHasBinary(ARoot) then
    Add(Result, ProjectCommand('run', 'cargo run'));
  Add(Result, ProjectCommand('test', 'cargo test'));
  Add(Result, ProjectCommand('check', 'cargo check'));
  Add(Result, ProjectCommand('clippy', 'cargo clippy'));
  Add(Result, ProjectCommand('fmt', 'cargo fmt'));
  Add(Result, ProjectCommand('doc', 'cargo doc'));
end;

class function TGittanRustKind.DependencyFile(const ARoot: string): string;
begin
  Result := 'Cargo.toml';
end;

class function TGittanRustKind.LockFile(const ARoot: string): string;
begin
  if HasFile(ARoot, 'Cargo.lock') then
    Result := 'Cargo.lock'
  else
    Result := '';
end;

class function TGittanRustKind.Dependencies(const AText: string): TGittanDependencies;
begin
  Result := ParseCargoDependencies(AText);
end;

class function TGittanRustKind.Locked(const AName, AText: string): TGittanDependencies;
begin
  Result := ParseCargoLock(AText);
end;

class function TGittanRustKind.Version(const AText: string): string;
begin
  Result := CargoVersion(AText);
end;

class function TGittanRustKind.PackageUrl(const AName: string): string;
begin
  Result := 'https://crates.io/crates/' + AName;
end;

class function TGittanRustKind.Checks(const ARoot: string;
  ATracked: TStrings): TGittanProjectChecks;
var
  Path: string;
begin
  Result := nil;
  if HasFile(ARoot, 'Cargo.lock') and not Tracked(ATracked, 'Cargo.lock') and
    RustHasBinary(ARoot) then
    AddCheck(Result, ProjectCheck(rsCargoLockUntracked, 'Cargo.lock'));
  if TrackedUnder(ATracked, 'target/', Path) then
    AddCheck(Result, ProjectCheck(rsTargetTracked, Path, 'target/'));
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
    class function DependencyFile(const ARoot: string): string; override;
    class function Dependencies(const AText: string): TGittanDependencies; override;
    class function PackageUrl(const AName: string): string; override;
    class function Checks(const ARoot: string; ATracked: TStrings): TGittanProjectChecks;
      override;
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

class function TGittanGoKind.DependencyFile(const ARoot: string): string;
begin
  Result := 'go.mod';
end;

class function TGittanGoKind.Dependencies(const AText: string): TGittanDependencies;
begin
  Result := ParseGoMod(AText);
end;

class function TGittanGoKind.PackageUrl(const AName: string): string;
begin
  Result := 'https://pkg.go.dev/' + AName;
end;

class function TGittanGoKind.Checks(const ARoot: string;
  ATracked: TStrings): TGittanProjectChecks;
begin
  Result := nil;
  if not HasFile(ARoot, 'go.sum') and (Length(ParseGoMod(TextOf(ARoot, 'go.mod'))) > 0) then
    AddCheck(Result, ProjectCheck(rsNoGoSum, ''));
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
    class function DependencyFile(const ARoot: string): string; override;
    class function LockFile(const ARoot: string): string; override;
    class function Dependencies(const AText: string): TGittanDependencies; override;
    class function Locked(const AName, AText: string): TGittanDependencies; override;
    class function Version(const AText: string): string; override;
    class function PackageUrl(const AName: string): string; override;
    class function Checks(const ARoot: string; ATracked: TStrings): TGittanProjectChecks;
      override;
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

class function TGittanPythonKind.DependencyFile(const ARoot: string): string;
begin
  if HasFile(ARoot, 'pyproject.toml') then
    Result := 'pyproject.toml'
  else if HasFile(ARoot, 'requirements.txt') then
    Result := 'requirements.txt'
  else
    Result := '';
end;

class function TGittanPythonKind.LockFile(const ARoot: string): string;
var
  FileName: string;
begin
  for FileName in ['uv.lock', 'poetry.lock', 'pdm.lock'] do
    if HasFile(ARoot, FileName) then
      Exit(FileName);
  Result := '';
end;

{ A pyproject.toml starts with a table or a key; a requirements.txt
  with a requirement. The first "[" at a line's start tells. }
function LooksLikeToml(const AText: string): boolean;
begin
  Result := (Pos('[project]', AText) > 0) or (Pos('[tool.', AText) > 0) or
    (Pos('[build-system]', AText) > 0) or (Pos('[dependency-groups]', AText) > 0);
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

class function TGittanPythonKind.Checks(const ARoot: string;
  ATracked: TStrings): TGittanProjectChecks;
var
  Path, Folder: string;
begin
  Result := nil;
  for Folder in ['.venv/', 'venv/'] do
    if TrackedUnder(ATracked, Folder, Path) then
      AddCheck(Result, ProjectCheck(Format(rsVenvTracked, [Folder]), Path, Folder));
  Path := TrackedWithExt(ATracked, '.pyc');
  if Path <> '' then
    AddCheck(Result, ProjectCheck(Format(rsPycTracked, [Path]), Path, '__pycache__/'));
end;

{ ---------------------------------------------------------------------------
  The report
  --------------------------------------------------------------------------- }

function ProjectReport(const AProject: TGittanProject; const ARoot: string;
  const AOldManifest, AOldLock, ASince: string; ATracked: TStrings): TGittanProjectReport;
var
  Text, LockText: string;
  Old: TGittanDependencies;
begin
  Result := Default(TGittanProjectReport);
  Result.Name := AProject.Name;
  Result.Manifest := AProject.Manifest;
  Result.DependencyFile := AProject.Kind.DependencyFile(ARoot);
  Result.LockFile := AProject.Kind.LockFile(ARoot);
  Text := TextOf(ARoot, Result.DependencyFile);
  if Result.DependencyFile <> '' then
  begin
    Result.Version := AProject.Kind.Version(Text);
    Result.Dependencies := AProject.Kind.Dependencies(Text);
    if Result.LockFile <> '' then
    begin
      LockText := TextOf(ARoot, Result.LockFile);
      ResolveDependencies(Result.Dependencies,
        AProject.Kind.Locked(Result.LockFile, LockText));
    end;
    if ASince <> '' then
    begin
      Result.Since := ASince;
      Old := AProject.Kind.Dependencies(AOldManifest);
      if (Result.LockFile <> '') and (AOldLock <> '') then
        ResolveDependencies(Old, AProject.Kind.Locked(Result.LockFile, AOldLock));
      Result.Changes := DependencyChanges(Old, Result.Dependencies);
    end;
  end;
  Result.Checks := AProject.Kind.Checks(ARoot, ATracked);
end;

initialization
  RegisterProjectKind(TGittanLazarusKind);
  RegisterProjectKind(TGittanNodeKind);
  RegisterProjectKind(TGittanRustKind);
  RegisterProjectKind(TGittanGoKind);
  RegisterProjectKind(TGittanPythonKind);

end.
