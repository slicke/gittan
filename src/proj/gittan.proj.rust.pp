unit gittan.proj.rust;

{** The Rust driver: a Cargo.toml at the root. Its commands are cargo
  build, run (with a main.rs or a [[bin]]), test, check, clippy, fmt and
  doc; its section shows the package's name, edition and rust-version,
  the workspace's members, the features with what each turns on and the
  binaries, beside the dependencies resolved by Cargo.lock. Tested in
  tests/testprojrust.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.manifest, gittan.project;

type
  {** A feature of a Cargo.toml: its name and what it turns on. }
  TCargoFeature = record
    Name: string;
    Enables: TStringArray;
  end;
  TCargoFeatures = array of TCargoFeature;

  {** What a Cargo.toml says beside its dependencies. }
  TCargoInfo = record
    Name, Edition, RustVersion, Description, Repository: string;
    Members, Binaries: TStringArray;
    Features: TCargoFeatures;
  end;

  { TGittanRustKind }

  TGittanRustKind = class(TGittanProjectKind)
  public
    class function Name: string; override;
    class function Identify(const ARoot: string; out AManifest: string): boolean; override;
    class function Commands(const ARoot: string): TGittanProjectCommands; override;
    class function DependencyFile(const ARoot: string): string; override;
    class function LockFile(const ARoot: string): string; override;
    class function Dependencies(const AText: string): TGittanDependencies; override;
    class function Locked(const AName, AText: string): TGittanDependencies; override;
    class function Version(const AText: string): string; override;
    class function PackageUrl(const AName: string): string; override;
    class function Checks(AContext: TGittanProjectContext): TGittanProjectChecks; override;
    class function Section(AContext: TGittanProjectContext;
      const AManifest: string): TGittanProjectSection; override;
  end;

{** The dependencies of a Cargo.toml: [dependencies],
  [dev-dependencies] (dev), [build-dependencies] (build), the same under
  [target.X.] and as [dependencies.name] tables, and
  [workspace.dependencies]. A "{ version = ... }" table gives its
  version, "{ workspace = true }" the word workspace, a path or git one
  none. }
function ParseCargoDependencies(const AText: string): TGittanDependencies;

{** The packages of a Cargo.lock, each with its version in Resolved. }
function ParseCargoLock(const AText: string): TGittanDependencies;

{** The version of a Cargo.toml's [package]; '' without one. }
function CargoVersion(const AText: string): string;

{** The [package] name, edition, rust-version, description and
  repository, the [workspace] members, the [features] and the [[bin]]
  names of a Cargo.toml's text. }
function ParseCargoInfo(const AText: string): TCargoInfo;

implementation

uses
  gittan.textfile;

resourcestring
  rsCargoLockUntracked = 'Cargo.lock is not committed. A crate with a binary commits it so ' +
    'that every build uses the versions this one has.';
  rsNoCargoLock = 'No Cargo.lock. cargo build writes it; a crate with a binary commits it so ' +
    'that every build uses the same versions.';
  rsTargetTracked = 'Files under target/ are committed: cargo''s build output.';
  rsPackage = 'Package';
  rsEdition = 'Edition';
  rsRustVersion = 'Rust version';
  rsRepository = 'Repository';
  rsMembers = 'Workspace';
  rsBinaries = 'Binaries';
  rsFeatures = 'Features';
  rsDefaultFeature = 'on by default';
  rsRunBin = 'Run';

{ ---------------------------------------------------------------------------
  Rust
  --------------------------------------------------------------------------- }

{ The dependency group a table's name stands for, or false: the last
  part of "dependencies", "target.X.dev-dependencies",
  "dependencies.serde" (with the name in AName). }
function CargoTable(const ATable: string; out AGroup, AName: string): boolean;
var
  Parts: TStringArray;
  i: integer;

  function GroupOf(const APart: string): boolean;
  begin
    Result := True;
    if APart = 'dependencies' then
      AGroup := ''
    else if APart = 'dev-dependencies' then
      AGroup := 'dev'
    else if APart = 'build-dependencies' then
      AGroup := 'build'
    else
      Result := False;
  end;

begin
  AName := '';
  AGroup := '';
  Parts := ATable.Split(['.']);
  for i := 0 to High(Parts) do
    Parts[i] := BareKey(Parts[i]);
  if Length(Parts) = 0 then
    Exit(False);
  if GroupOf(Parts[High(Parts)]) then
    Exit(True);
  if (Length(Parts) >= 2) and GroupOf(Parts[High(Parts) - 1]) then
  begin
    AName := Parts[High(Parts)];
    Exit(True);
  end;
  Result := False;
end;

{ The version a dependency's value asks for: the string, or the
  version of its inline table, "workspace" for one the workspace sets,
  '' for a path or git one. }
function CargoRequirement(const AValue: string): string;
begin
  Result := TomlString(AValue);
  if Result <> '' then
    Exit;
  Result := TomlString(TomlInlineValue(AValue, 'version'));
  if (Result = '') and (Trim(TomlInlineValue(AValue, 'workspace')) = 'true') then
    Result := 'workspace';
end;

function ParseCargoDependencies(const AText: string): TGittanDependencies;
var
  E: TGittanTomlEntry;
  Group, Name: string;

  { A key of a [dependencies.name] table: the dependency once, with the
    version of whichever key gives one, path and git before version
    as well as after. }
  procedure TakeKey(const AVersion: string);
  var
    i: integer;
  begin
    for i := 0 to High(Result) do
      if (Result[i].Name = Name) and (Result[i].Group = Group) then
      begin
        if AVersion <> '' then
          Result[i].Version := AVersion;
        Exit;
      end;
    AddDependency(Result, Name, AVersion, '', Group);
  end;

begin
  Result := nil;
  for E in ReadToml(AText) do
  begin
    if not CargoTable(E.Table, Group, Name) then
      Continue;
    if Name = '' then
      AddDependency(Result, E.Key, CargoRequirement(E.Value), '', Group)
    else if E.Key = 'version' then
      TakeKey(TomlString(E.Value))
    else if (E.Key = 'workspace') and (Trim(E.Value) = 'true') then
      TakeKey('workspace')
    else if (E.Key = 'path') or (E.Key = 'git') then
      TakeKey('');
  end;
end;

function ParseCargoLock(const AText: string): TGittanDependencies;
begin
  Result := ParseTomlLock(AText);
end;

function CargoVersion(const AText: string): string;
var
  E: TGittanTomlEntry;
begin
  for E in ReadToml(AText) do
    if (E.Table = 'package') and (E.Key = 'version') then
      Exit(TomlString(E.Value));
  Result := '';
end;


function ParseCargoInfo(const AText: string): TCargoInfo;
var
  E: TGittanTomlEntry;

  procedure Add(var AList: TStringArray; const AValue: string);
  begin
    if AValue = '' then
      Exit;
    SetLength(AList, Length(AList) + 1);
    AList[High(AList)] := AValue;
  end;

begin
  Result := Default(TCargoInfo);
  for E in ReadToml(AText) do
    if E.Table = 'package' then
    begin
      if E.Key = 'name' then
        Result.Name := TomlString(E.Value)
      else if E.Key = 'edition' then
        Result.Edition := TomlString(E.Value)
      else if E.Key = 'rust-version' then
        Result.RustVersion := TomlString(E.Value)
      else if E.Key = 'description' then
        Result.Description := TomlString(E.Value)
      else if E.Key = 'repository' then
        Result.Repository := TomlString(E.Value);
    end
    else if (E.Table = 'workspace') and (E.Key = 'members') then
      Result.Members := TomlArrayStrings(E.Value)
    else if E.Table = 'features' then
    begin
      SetLength(Result.Features, Length(Result.Features) + 1);
      Result.Features[High(Result.Features)].Name := E.Key;
      Result.Features[High(Result.Features)].Enables := TomlArrayStrings(E.Value);
    end
    else if (E.Table = 'bin') and (E.Key = 'name') then
      Add(Result.Binaries, TomlString(E.Value));
end;

{ A binary to run: a main.rs, or a [[bin]] the manifest names. }
function RustHasBinary(const ARoot: string): boolean;
begin
  Result := FileExists(RootFile(ARoot, 'src/main.rs')) or
    (Pos('[[bin]]', TextOf(ARoot, 'Cargo.toml')) > 0);
end;

{ TGittanRustKind }

class function TGittanRustKind.Name: string;
begin
  Result := 'Rust';
end;

class function TGittanRustKind.Identify(const ARoot: string; out AManifest: string): boolean;
begin
  Result := HasFile(ARoot, 'Cargo.toml');
  if Result then
    AManifest := 'Cargo.toml'
  else
    AManifest := '';
end;

class function TGittanRustKind.Commands(const ARoot: string): TGittanProjectCommands;
begin
  Result := nil;
  AddProjectCommand(Result, ProjectCommand('build', 'cargo build'));
  if RustHasBinary(ARoot) then
    AddProjectCommand(Result, ProjectCommand('run', 'cargo run'));
  AddProjectCommand(Result, ProjectCommand('test', 'cargo test'));
  AddProjectCommand(Result, ProjectCommand('check', 'cargo check'));
  AddProjectCommand(Result, ProjectCommand('clippy', 'cargo clippy'));
  AddProjectCommand(Result, ProjectCommand('fmt', 'cargo fmt'));
  AddProjectCommand(Result, ProjectCommand('doc', 'cargo doc'));
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

class function TGittanRustKind.Checks(AContext: TGittanProjectContext): TGittanProjectChecks;
var
  Path: string;
begin
  Result := nil;
  if RustHasBinary(AContext.Root) then
    if not HasFile(AContext.Root, 'Cargo.lock') then
      AddProjectCheck(Result, ProjectCheck(rsNoCargoLock, ''))
    else if not AContext.IsTracked('Cargo.lock') then
      AddProjectCheck(Result, ProjectCheck(rsCargoLockUntracked, 'Cargo.lock'));
  if AContext.TrackedUnder('target/', Path) then
    AddProjectCheck(Result, ProjectCheck(rsTargetTracked, Path, '/target/'));
end;

class function TGittanRustKind.Section(AContext: TGittanProjectContext;
  const AManifest: string): TGittanProjectSection;
var
  Info: TCargoInfo;
  Facts, Bins, Feats: TGittanProjectBlock;
  Std: TGittanProjectSection;
  i: integer;
  Default: TStringArray;
  Hint: string;
begin
  Std := StandardSection(AContext, AManifest);
  Result := Std;
  Result.Blocks := nil;
  Info := ParseCargoInfo(TextOf(AContext.Root, 'Cargo.toml'));
  Facts := ProjectBlock(pbFacts);
  if Info.Name <> '' then
    AddFact(Facts, rsPackage, Info.Name, psStrong);
  AddFact(Facts, rsEdition, Info.Edition);
  AddFact(Facts, rsRustVersion, Info.RustVersion);
  AddFact(Facts, rsRepository, Info.Repository, psLink, Info.Repository);
  AddFact(Facts, rsMembers, string.Join(', ', Info.Members));
  AddBlock(Result, Facts);
  { The binaries, each with a button that runs it. }
  Bins := ProjectBlock(pbTable, rsBinaries);
  Bins.RightLast := True;
  for i := 0 to High(Info.Binaries) do
    AddRow(Bins, ProjectRow([ProjectCell(Info.Binaries[i], psStrong), ProjectButton(rsRunBin,
      'run:' + Info.Binaries[i], 'cargo run --bin ' + ShellName(Info.Binaries[i]))]));
  for i := 0 to High(Std.Blocks) do
    if Std.Blocks[i].Kind <> pbChecks then
      AddBlock(Result, Std.Blocks[i]);
  { The features: each with what it turns on, the default ones said. }
  Default := nil;
  for i := 0 to High(Info.Features) do
    if Info.Features[i].Name = 'default' then
      Default := Info.Features[i].Enables;
  Feats := ProjectBlock(pbTable, rsFeatures);
  Feats.RightLast := True;
  for i := 0 to High(Info.Features) do
  begin
    if Info.Features[i].Name = 'default' then
      Continue;
    Hint := '';
    if Pos(' ' + Info.Features[i].Name + ' ', ' ' + string.Join(' ', Default) + ' ') > 0 then
      Hint := rsDefaultFeature;
    AddRow(Feats, ProjectRow([ProjectCell(Info.Features[i].Name, psStrong),
      ProjectCell(string.Join(', ', Info.Features[i].Enables), psDim),
      ProjectCell(Hint, psOk)]));
  end;
  AddBlock(Result, Feats);
  AddBlock(Result, Bins);
  for i := 0 to High(Std.Blocks) do
    if Std.Blocks[i].Kind = pbChecks then
      AddBlock(Result, Std.Blocks[i]);
end;

initialization
  RegisterProjectKind(TGittanRustKind);

end.
