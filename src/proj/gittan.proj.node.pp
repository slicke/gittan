unit gittan.proj.node;

{** The Node driver: a package.json at the root. Its scripts are the
  Commands page's Scripts section already (gittan.repocommands), so it
  offers no commands of its own; its section shows the package's name,
  the package manager (the packageManager field, else the lock file
  there), the engines it asks for and its workspaces, beside the
  dependencies resolved by package-lock.json, yarn.lock or
  pnpm-lock.yaml. Tested in tests/testprojnode.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, gittan.manifest, gittan.project;

type
  {** What a package.json says beside its dependencies. }
  TNodeInfo = record
    Name, PackageManager, ModuleType: string;
    {** "node >=20", one per engine. }
    Engines, Workspaces: TStringArray;
  end;

  { TGittanNodeKind }

  TGittanNodeKind = class(TGittanProjectKind)
  public
    class function Name: string; override;
    class function Identify(const ARoot: string; out AManifest: string): boolean; override;
    class function DependencyFile(const ARoot: string): string; override;
    class function LockFile(const ARoot: string): string; override;
    class function LockFileNames: TStringArray; override;
    class function Dependencies(const AText: string): TGittanDependencies; override;
    class function Locked(const AName, AText: string): TGittanDependencies; override;
    class function Version(const AText: string): string; override;
    class function PackageUrl(const AName: string): string; override;
    class function Checks(AContext: TGittanProjectContext): TGittanProjectChecks; override;
    class function Section(AContext: TGittanProjectContext;
      const AManifest: string): TGittanProjectSection; override;
  end;

{** The dependencies of a package.json: dependencies, devDependencies
  (dev), peerDependencies (peer) and optionalDependencies (optional). }
function ParsePackageDependencies(const AJson: string): TGittanDependencies;

{** The version of a package.json; '' without one. }
function PackageVersion(const AJson: string): string;

{** The packages of a package-lock.json (lockfileVersion 2 and 3:
  "packages", the ones right under node_modules; 1: "dependencies"), each
  with its version in Resolved. }
function ParsePackageLock(const AJson: string): TGittanDependencies;

{** The packages of a yarn.lock (the classic form: "name@range:" lines
  with a version line under each, and the berry form with its quoted
  keys), each with its version in Resolved. }
function ParseYarnLock(const AText: string): TGittanDependencies;

{** The packages of a pnpm-lock.yaml: the keys under "packages:",
  "/name@1.2.3:" or "name@1.2.3:", each with its version in Resolved. }
function ParsePnpmLock(const AText: string): TGittanDependencies;

{** The name, packageManager, type, engines and workspaces of a
  package.json's text (workspaces as an array or as {packages: [...]}). }
function ParseNodeInfo(const AJson: string): TNodeInfo;

{** The package manager of the package at ARoot: what packageManager
  says ("pnpm@9.1.0"), else the one whose lock file is there, else npm. }
function NodePackageManager(const ARoot: string): string;

{** The tool of a package manager as NodePackageManager gives it: npm,
  pnpm, yarn or bun, without the version ("pnpm" of "pnpm@9.1.0"); ''
  for any other, which the Install button does not run. }
function NodeTool(const AManager: string): string;

implementation

uses
  gittan.textfile;

resourcestring
  rsNodeModulesTracked = 'Files under node_modules/ are committed. npm install writes them ' +
    'from the lock file.';
  rsNoNodeLock = 'No lock file. npm install writes package-lock.json; commit it so that every ' +
    'clone gets the versions this one has.';
  rsPackage = 'Package';
  rsManager = 'Package manager';
  rsEngines = 'Engines';
  rsModuleType = 'Module type';
  rsWorkspaces = 'Workspaces';
  rsInstall = 'Install';

{ ---------------------------------------------------------------------------
  Node
  --------------------------------------------------------------------------- }

function ParsePackageDependencies(const AJson: string): TGittanDependencies;
var
  Root: TJSONObject;

  procedure Take(const AField, AGroup: string);
  var
    Deps: TJSONData;
    i: integer;
  begin
    Deps := Root.Find(AField);
    if not (Deps is TJSONObject) then
      Exit;
    for i := 0 to TJSONObject(Deps).Count - 1 do
      if TJSONObject(Deps).Items[i].JSONType = jtString then
        AddDependency(Result, TJSONObject(Deps).Names[i], TJSONObject(Deps).Items[i].AsString,
          '', AGroup);
  end;

begin
  Result := nil;
  Root := ParseJsonObject(AJson);
  if Root = nil then
    Exit;
  try
    Take('dependencies', '');
    Take('devDependencies', 'dev');
    Take('peerDependencies', 'peer');
    Take('optionalDependencies', 'optional');
  finally
    Root.Free;
  end;
end;

function PackageVersion(const AJson: string): string;
var
  Root: TJSONObject;
  V: TJSONData;
begin
  Result := '';
  Root := ParseJsonObject(AJson);
  if Root = nil then
    Exit;
  try
    V := Root.Find('version');
    if (V <> nil) and (V.JSONType = jtString) then
      Result := V.AsString;
  finally
    Root.Free;
  end;
end;

function ParsePackageLock(const AJson: string): TGittanDependencies;
const
  Prefix = 'node_modules/';
var
  Root: TJSONObject;
  Packages: TJSONData;
  i: integer;
  Key: string;
  V: TJSONData;
begin
  Result := nil;
  Root := ParseJsonObject(AJson);
  if Root = nil then
    Exit;
  try
    Packages := Root.Find('packages');
    if Packages is TJSONObject then
    begin
      for i := 0 to TJSONObject(Packages).Count - 1 do
      begin
        Key := TJSONObject(Packages).Names[i];
        { The ones right under node_modules: a nested one is another
          version a dependency of its own needs. }
        if (Pos(Prefix, Key) <> 1) or (Pos(Prefix, Copy(Key, Length(Prefix) + 1, MaxInt)) > 0) then
          Continue;
        if not (TJSONObject(Packages).Items[i] is TJSONObject) then
          Continue;
        V := TJSONObject(TJSONObject(Packages).Items[i]).Find('version');
        if (V <> nil) and (V.JSONType = jtString) then
          AddDependency(Result, Copy(Key, Length(Prefix) + 1, MaxInt), '', V.AsString, '');
      end;
      Exit;
    end;
    Packages := Root.Find('dependencies');
    if Packages is TJSONObject then
      for i := 0 to TJSONObject(Packages).Count - 1 do
        if TJSONObject(Packages).Items[i] is TJSONObject then
        begin
          V := TJSONObject(TJSONObject(Packages).Items[i]).Find('version');
          if (V <> nil) and (V.JSONType = jtString) then
            AddDependency(Result, TJSONObject(Packages).Names[i], '', V.AsString, '');
        end;
  finally
    Root.Free;
  end;
end;

{ The package's name of a lock key "name@range" or "@scope/name@range":
  what comes before the last "@" that is not the first character. }
function NameOfLockKey(const AKey: string): string;
var
  i: integer;
begin
  for i := Length(AKey) downto 2 do
    if AKey[i] = '@' then
      Exit(Copy(AKey, 1, i - 1));
  Result := '';
end;

function ParseYarnLock(const AText: string): TGittanDependencies;
var
  Start, P: integer;
  Line, Key, Name, Version: string;
begin
  Result := nil;
  Name := '';
  Start := 1;
  while NextLine(AText, Start, Line) do
  begin
    Line := BareLine(Line);
    if (Line = '') or (Line[1] = '#') then
      Continue;
    if Line[1] <> ' ' then
    begin
      { A key line: one or more "name@range" joined by ", ", quoted or
        not, ending with ":". }
      Key := Line;
      if Key[Length(Key)] = ':' then
        SetLength(Key, Length(Key) - 1);
      P := Pos(',', Key);
      if P > 0 then
        Key := Copy(Key, 1, P - 1);
      Key := BareKey(Key);
      Name := NameOfLockKey(Key);
      Continue;
    end;
    Line := Trim(Line);
    if (Name <> '') and (Pos('version', Line) = 1) then
    begin
      Version := Trim(Copy(Line, 8, MaxInt));
      if (Version <> '') and (Version[1] = ':') then
        Version := Trim(Copy(Version, 2, MaxInt));
      Version := BareKey(Version);
      if Version <> '' then
        AddLocked(Result, Name, Version);
      Name := '';
    end;
  end;
end;

function ParsePnpmLock(const AText: string): TGittanDependencies;
var
  Start, P, i: integer;
  Line, Key, Name, Version: string;
  InPackages: boolean;
begin
  Result := nil;
  InPackages := False;
  Start := 1;
  while NextLine(AText, Start, Line) do
  begin
    if Line = '' then
      Continue;
    if Line[1] <> ' ' then
    begin
      InPackages := Pos('packages:', Line) = 1;
      Continue;
    end;
    if not InPackages then
      Continue;
    { A key two spaces in: "/name@1.2.3:", "'name@1.2.3':",
      "/name/1.2.3:" (the older form), with "(peer)" after the
      version. }
    if (Length(Line) < 3) or (Line[1] <> ' ') or (Line[2] <> ' ') or (Line[3] = ' ') then
      Continue;
    Key := Trim(Line);
    if Key[Length(Key)] <> ':' then
      Continue;
    SetLength(Key, Length(Key) - 1);
    Key := BareKey(Key);
    if (Key <> '') and (Key[1] = '/') then
      Delete(Key, 1, 1);
    P := Pos('(', Key);
    if P > 0 then
      Key := Copy(Key, 1, P - 1);
    Name := NameOfLockKey(Key);
    if Name <> '' then
      Version := Copy(Key, Length(Name) + 2, MaxInt)
    else
    begin
      { "name/1.2.3": the version after the last slash that is not the
        scope's. }
      i := Length(Key);
      while (i > 0) and (Key[i] <> '/') do
        Dec(i);
      if i < 2 then
        Continue;
      Name := Copy(Key, 1, i - 1);
      Version := Copy(Key, i + 1, MaxInt);
    end;
    if (Name <> '') and (Version <> '') then
      AddLocked(Result, Name, Version);
  end;
end;


function ParseNodeInfo(const AJson: string): TNodeInfo;
var
  Root: TJSONObject;
  V: TJSONData;
  i: integer;

  procedure TakeStrings(AData: TJSONData; var AList: TStringArray);
  var
    k: integer;
  begin
    if not (AData is TJSONArray) then
      Exit;
    for k := 0 to TJSONArray(AData).Count - 1 do
      if TJSONArray(AData).Items[k].JSONType = jtString then
      begin
        SetLength(AList, Length(AList) + 1);
        AList[High(AList)] := TJSONArray(AData).Items[k].AsString;
      end;
  end;

  function Str(const AName: string): string;
  var
    D: TJSONData;
  begin
    D := Root.Find(AName);
    if (D <> nil) and (D.JSONType = jtString) then
      Result := D.AsString
    else
      Result := '';
  end;

begin
  Result := Default(TNodeInfo);
  Root := ParseJsonObject(AJson);
  if Root = nil then
    Exit;
  try
    Result.Name := Str('name');
    Result.PackageManager := Str('packageManager');
    Result.ModuleType := Str('type');
    V := Root.Find('engines');
    if V is TJSONObject then
      for i := 0 to TJSONObject(V).Count - 1 do
        if TJSONObject(V).Items[i].JSONType = jtString then
        begin
          SetLength(Result.Engines, Length(Result.Engines) + 1);
          Result.Engines[High(Result.Engines)] := TJSONObject(V).Names[i] + ' ' +
            TJSONObject(V).Items[i].AsString;
        end;
    V := Root.Find('workspaces');
    if V is TJSONObject then
      V := TJSONObject(V).Find('packages');
    TakeStrings(V, Result.Workspaces);
  finally
    Root.Free;
  end;
end;

function NodePackageManager(const ARoot: string): string;
begin
  Result := ParseNodeInfo(TextOf(ARoot, 'package.json')).PackageManager;
  if Result <> '' then
    Exit;
  if HasFile(ARoot, 'pnpm-lock.yaml') then
    Result := 'pnpm'
  else if HasFile(ARoot, 'yarn.lock') then
    Result := 'yarn'
  else if HasFile(ARoot, 'bun.lockb') or HasFile(ARoot, 'bun.lock') then
    Result := 'bun'
  else
    Result := 'npm';
end;

function NodeTool(const AManager: string): string;
const
  Tools: array[0..3] of string = ('npm', 'pnpm', 'yarn', 'bun');
var
  i: integer;
begin
  Result := AManager;
  if Pos('@', Result) > 1 then
    Result := Copy(Result, 1, Pos('@', Result) - 1);
  for i := 0 to High(Tools) do
    if Result = Tools[i] then
      Exit;
  Result := '';
end;

const
  { A typed array, not an array constructor: FPC 3.2.2 gets a for-in
    over a constructor of strings wrong. }
  NodeLockNames: array[0..4] of string = ('package-lock.json', 'pnpm-lock.yaml', 'yarn.lock',
    'bun.lock', 'npm-shrinkwrap.json');

{ TGittanNodeKind }

class function TGittanNodeKind.Name: string;
begin
  Result := 'Node';
end;

class function TGittanNodeKind.Identify(const ARoot: string; out AManifest: string): boolean;
begin
  Result := HasFile(ARoot, 'package.json');
  if Result then
    AManifest := 'package.json'
  else
    AManifest := '';
end;

class function TGittanNodeKind.DependencyFile(const ARoot: string): string;
begin
  Result := 'package.json';
end;

class function TGittanNodeKind.LockFile(const ARoot: string): string;
var
  Tool, FileName: string;
begin
  { The lock of the package manager the page names, when it is there,
    so the versions are the ones its install gives. }
  Tool := NodeTool(NodePackageManager(ARoot));
  if Tool = 'npm' then
  begin
    if HasFile(ARoot, 'package-lock.json') then
      Exit('package-lock.json');
    if HasFile(ARoot, 'npm-shrinkwrap.json') then
      Exit('npm-shrinkwrap.json');
  end
  else if (Tool = 'pnpm') and HasFile(ARoot, 'pnpm-lock.yaml') then
    Exit('pnpm-lock.yaml')
  else if (Tool = 'yarn') and HasFile(ARoot, 'yarn.lock') then
    Exit('yarn.lock')
  else if (Tool = 'bun') and HasFile(ARoot, 'bun.lock') then
    Exit('bun.lock');
  for FileName in NodeLockNames do
    if HasFile(ARoot, FileName) then
      Exit(FileName);
  Result := '';
end;

class function TGittanNodeKind.LockFileNames: TStringArray;
var
  i: integer;
begin
  SetLength(Result, Length(NodeLockNames));
  for i := 0 to High(NodeLockNames) do
    Result[i] := NodeLockNames[i];
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

class function TGittanNodeKind.Checks(AContext: TGittanProjectContext): TGittanProjectChecks;
var
  Path: string;
begin
  Result := nil;
  if AContext.TrackedUnder('node_modules/', Path) then
    AddProjectCheck(Result, ProjectCheck(rsNodeModulesTracked, Path, 'node_modules/'));
  if (LockFile(AContext.Root) = '') and
    (Length(Dependencies(TextOf(AContext.Root, 'package.json'))) > 0) then
    AddProjectCheck(Result, ProjectCheck(rsNoNodeLock, ''));
end;

class function TGittanNodeKind.Section(AContext: TGittanProjectContext;
  const AManifest: string): TGittanProjectSection;
var
  Info: TNodeInfo;
  Facts: TGittanProjectBlock;
  Std: TGittanProjectSection;
  Manager, Tool: string;
  i: integer;
begin
  Std := StandardSection(AContext, AManifest);
  Result := Std;
  Result.Blocks := nil;
  Info := ParseNodeInfo(TextOf(AContext.Root, 'package.json'));
  Manager := NodePackageManager(AContext.Root);
  { The tool without its version, and only one it knows: the field is
    the repository's text, and the button runs it through the shell. }
  Tool := NodeTool(Manager);
  Facts := ProjectBlock(pbFacts);
  AddFact(Facts, rsPackage, Info.Name, psStrong);
  if Tool <> '' then
    AddRow(Facts, ProjectRow([ProjectCell(rsManager, psDim), ProjectCell(Manager),
      ProjectButton(rsInstall, 'install', Tool + ' install')]))
  else
    AddFact(Facts, rsManager, Manager);
  AddFact(Facts, rsModuleType, Info.ModuleType);
  AddFact(Facts, rsEngines, string.Join(', ', Info.Engines));
  AddFact(Facts, rsWorkspaces, string.Join(', ', Info.Workspaces));
  AddBlock(Result, Facts);
  for i := 0 to High(Std.Blocks) do
    AddBlock(Result, Std.Blocks[i]);
end;

initialization
  RegisterProjectKind(TGittanNodeKind);

end.
