unit gittan.manifest;

{** What the manifests and lock files of the kinds of project say: the
  dependencies a Cargo.toml, package.json, go.mod, pyproject.toml,
  requirements.txt or Lazarus .lpi asks for, with the version each
  asks for, the versions a Cargo.lock, package-lock.json, yarn.lock,
  pnpm-lock.yaml, uv.lock, poetry.lock or pdm.lock resolved them to,
  and the project's own version. Everything here is a function of the
  file's text, so a file of a commit is read the same as the work
  tree's; nothing touches a file or runs a program. The TOML reader is
  what the manifests need and no more: tables, array tables, strings,
  inline tables and arrays of strings, with comments stripped and an
  array that runs over several lines joined. Tested in
  tests/testmanifest.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  {** A dependency: what the manifest asks for (Version, as written:
    "^1.2", ">=2.0", "1"; '' when it names no version, as a path
    dependency or a Lazarus package), what the lock file resolved it to
    (Resolved, '' when there is no lock or it is not in it), and its
    group: '' for a plain dependency, "dev", "build", "optional",
    "peer", "indirect", or an extras group's name in Python. }
  TGittanDependency = record
    Name, Version, Resolved, Group: string;
  end;
  TGittanDependencies = array of TGittanDependency;

  {** A key of a TOML file with the table it is in ("package",
    "dependencies", "tool.poetry.dependencies") and its value as
    written, quotes and braces included. }
  TGittanTomlEntry = record
    Table, Key, Value: string;
    {** The table is an array table ([[package]]), and this is the
      index of its element, from 0; -1 in a plain table. }
    Index: integer;
  end;
  TGittanTomlEntries = array of TGittanTomlEntry;

{** The entries of a TOML text, in order. A key's value that opens an
  array or an inline table runs on to the line that closes it. }
function ReadToml(const AText: string): TGittanTomlEntries;

{** The text of a TOML string value, without its quotes; '' for a
  value that is not a string. }
function TomlString(const AValue: string): string;

{** The value of AKey in an inline table value "{ version = "1", ...
  }", as written; '' when it is not there or the value is no table. }
function TomlInlineValue(const AValue, AKey: string): string;

{** The strings of an array value ["a", "b"]; none for a value that is
  no array. }
function TomlArrayStrings(const AValue: string): TStringArray;

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

{** The requirements of a go.mod: "require x v1.2.3" and the require
  block, the version in Version and in Resolved alike, since go.mod
  holds the resolved one; "// indirect" is the group indirect. }
function ParseGoMod(const AText: string): TGittanDependencies;

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

{** The packages a Lazarus .lpi requires (<RequiredPackages>, each
  <Item>'s <PackageName Value="..."/>, with <MinVersion> as the version
  when it has one). }
function ParseLpiPackages(const AXml: string): TGittanDependencies;

{** The version a Lazarus .lpi's <VersionInfo> gives,
  "Major.Minor.Revision" (with ".Build" when it is not 0), when
  <UseVersionInfo Value="True"/>; '' otherwise. }
function LpiVersion(const AXml: string): string;

implementation

uses
  StrUtils, fpjson, jsonparser, gittan.textfile;

{ ---------------------------------------------------------------------------
  TOML
  --------------------------------------------------------------------------- }

{ The line without its comment: a "#" outside quotes ends it. }
function StripComment(const ALine: string): string;
var
  i: integer;
  Quote: char;
begin
  Quote := #0;
  for i := 1 to Length(ALine) do
  begin
    if Quote <> #0 then
    begin
      if ALine[i] = Quote then
        Quote := #0;
    end
    else if ALine[i] in ['"', ''''] then
      Quote := ALine[i]
    else if ALine[i] = '#' then
      Exit(Copy(ALine, 1, i - 1));
  end;
  Result := ALine;
end;

{ How many brackets and braces ALine opens beyond those it closes,
  outside quotes. }
function OpenDepth(const ALine: string): integer;
var
  i: integer;
  Quote: char;
begin
  Result := 0;
  Quote := #0;
  for i := 1 to Length(ALine) do
  begin
    if Quote <> #0 then
    begin
      if ALine[i] = Quote then
        Quote := #0;
    end
    else
      case ALine[i] of
        '"', '''': Quote := ALine[i];
        '[', '{': Inc(Result);
        ']', '}': Dec(Result);
      end;
  end;
end;

{ A key as written, its quotes taken off. }
function BareKey(const AKey: string): string;
begin
  Result := Trim(AKey);
  if (Length(Result) >= 2) and (Result[1] in ['"', '''']) and
    (Result[Length(Result)] = Result[1]) then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

function ReadToml(const AText: string): TGittanTomlEntries;
var
  Start, P, Depth: integer;
  Line, Table, Next: string;
  Index: integer;
  Arrays: TStringList;
begin
  Result := nil;
  Table := '';
  Index := -1;
  Arrays := TStringList.Create;
  try
    Start := 1;
    while NextLine(AText, Start, Line) do
    begin
      Line := Trim(StripComment(Line));
      if Line = '' then
        Continue;
      if Line[1] = '[' then
      begin
        if (Length(Line) > 1) and (Line[2] = '[') then
        begin
          P := Pos(']]', Line);
          if P = 0 then
            Continue;
          Table := Trim(Copy(Line, 3, P - 3));
          { The element's index: how many of this array table came
            before. }
          P := Arrays.IndexOf(Table);
          if P < 0 then
          begin
            Arrays.AddObject(Table, TObject(PtrInt(0)));
            Index := 0;
          end
          else
          begin
            Index := PtrInt(Arrays.Objects[P]) + 1;
            Arrays.Objects[P] := TObject(PtrInt(Index));
          end;
        end
        else
        begin
          P := Pos(']', Line);
          if P = 0 then
            Continue;
          Table := Trim(Copy(Line, 2, P - 2));
          Index := -1;
        end;
        Continue;
      end;
      P := Pos('=', Line);
      if P < 2 then
        Continue;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].Table := Table;
      Result[High(Result)].Index := Index;
      Result[High(Result)].Key := BareKey(Copy(Line, 1, P - 1));
      Line := Trim(Copy(Line, P + 1, MaxInt));
      { An array or an inline table may run on: join the lines until
        it closes. }
      Depth := OpenDepth(Line);
      while (Depth > 0) and NextLine(AText, Start, Next) do
      begin
        Next := Trim(StripComment(Next));
        Line := Line + ' ' + Next;
        Depth := Depth + OpenDepth(Next);
      end;
      Result[High(Result)].Value := Line;
    end;
  finally
    Arrays.Free;
  end;
end;

function TomlString(const AValue: string): string;
var
  S: string;
begin
  S := Trim(AValue);
  if (Length(S) >= 2) and (S[1] in ['"', '''']) and (S[Length(S)] = S[1]) then
    Result := Copy(S, 2, Length(S) - 2)
  else
    Result := '';
end;

{ The parts of a "{ a = 1, b = "x" }" or "[ "a", "b" ]" value, split on
  the commas outside quotes and nested brackets. }
function SplitTomlList(const AValue: string; AOpen, AClose: char): TStringArray;
var
  S, Part: string;
  i, Depth: integer;
  Quote: char;
begin
  Result := nil;
  S := Trim(AValue);
  if (S = '') or (S[1] <> AOpen) or (S[Length(S)] <> AClose) then
    Exit;
  S := Copy(S, 2, Length(S) - 2);
  Part := '';
  Depth := 0;
  Quote := #0;
  for i := 1 to Length(S) do
  begin
    if Quote <> #0 then
    begin
      if S[i] = Quote then
        Quote := #0;
      Part := Part + S[i];
    end
    else if S[i] in ['"', ''''] then
    begin
      Quote := S[i];
      Part := Part + S[i];
    end
    else if S[i] in ['[', '{'] then
    begin
      Inc(Depth);
      Part := Part + S[i];
    end
    else if S[i] in [']', '}'] then
    begin
      Dec(Depth);
      Part := Part + S[i];
    end
    else if (S[i] = ',') and (Depth = 0) then
    begin
      if Trim(Part) <> '' then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Trim(Part);
      end;
      Part := '';
    end
    else
      Part := Part + S[i];
  end;
  if Trim(Part) <> '' then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Trim(Part);
  end;
end;

function TomlInlineValue(const AValue, AKey: string): string;
var
  Part: string;
  P: integer;
begin
  for Part in SplitTomlList(AValue, '{', '}') do
  begin
    P := Pos('=', Part);
    if (P > 1) and (BareKey(Copy(Part, 1, P - 1)) = AKey) then
      Exit(Trim(Copy(Part, P + 1, MaxInt)));
  end;
  Result := '';
end;

function TomlArrayStrings(const AValue: string): TStringArray;
var
  Part, S: string;
begin
  Result := nil;
  for Part in SplitTomlList(AValue, '[', ']') do
  begin
    S := TomlString(Part);
    if S <> '' then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := S;
    end;
  end;
end;

procedure AddDependency(var ADeps: TGittanDependencies; const AName, AVersion, AResolved,
  AGroup: string);
var
  i: integer;
begin
  if AName = '' then
    Exit;
  { Once each: a lock file may list a package twice (two versions), and
    the first is kept. }
  for i := 0 to High(ADeps) do
    if (ADeps[i].Name = AName) and (ADeps[i].Group = AGroup) then
      Exit;
  SetLength(ADeps, Length(ADeps) + 1);
  ADeps[High(ADeps)].Name := AName;
  ADeps[High(ADeps)].Version := AVersion;
  ADeps[High(ADeps)].Resolved := AResolved;
  ADeps[High(ADeps)].Group := AGroup;
end;

{ The packages of a TOML lock with [[package]] of name and version
  (Cargo.lock, uv.lock, poetry.lock, pdm.lock). }
function ParseTomlLock(const AText: string): TGittanDependencies;
var
  E: TGittanTomlEntry;
  Name, Version: string;
  Index: integer;

  procedure Flush;
  begin
    if (Name <> '') and (Version <> '') then
      AddDependency(Result, Name, '', Version, '');
    Name := '';
    Version := '';
  end;

begin
  Result := nil;
  Name := '';
  Version := '';
  Index := -2;
  for E in ReadToml(AText) do
  begin
    if E.Table <> 'package' then
      Continue;
    if E.Index <> Index then
    begin
      Flush;
      Index := E.Index;
    end;
    if E.Key = 'name' then
      Name := TomlString(E.Value)
    else if E.Key = 'version' then
      Version := TomlString(E.Value);
  end;
  Flush;
end;

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
begin
  Result := nil;
  for E in ReadToml(AText) do
  begin
    if not CargoTable(E.Table, Group, Name) then
      Continue;
    if Name = '' then
      AddDependency(Result, E.Key, CargoRequirement(E.Value), '', Group)
    else if E.Key = 'version' then
      AddDependency(Result, Name, TomlString(E.Value), '', Group)
    else if (E.Key = 'workspace') and (Trim(E.Value) = 'true') then
      AddDependency(Result, Name, 'workspace', '', Group)
    else if (E.Key = 'path') or (E.Key = 'git') then
      AddDependency(Result, Name, '', '', Group);
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

{ ---------------------------------------------------------------------------
  Node
  --------------------------------------------------------------------------- }

function ParseJsonObject(const AJson: string): TJSONObject;
var
  Data: TJSONData;
begin
  Result := nil;
  if Trim(AJson) = '' then
    Exit;
  try
    Data := GetJSON(AJson);
  except
    Exit;
  end;
  if Data is TJSONObject then
    Result := TJSONObject(Data)
  else
    Data.Free;
end;

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
        AddDependency(Result, Name, '', Version, '');
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
      AddDependency(Result, Name, '', Version, '');
  end;
end;

{ ---------------------------------------------------------------------------
  Go
  --------------------------------------------------------------------------- }

function ParseGoMod(const AText: string): TGittanDependencies;
var
  Start: integer;
  Line, Group: string;
  Parts: TStringArray;
  InBlock: boolean;

  procedure TakeLine(const ALine: string);
  var
    S: string;
    P: integer;
  begin
    S := ALine;
    Group := '';
    P := Pos('//', S);
    if P > 0 then
    begin
      if Pos('indirect', Copy(S, P, MaxInt)) > 0 then
        Group := 'indirect';
      S := Copy(S, 1, P - 1);
    end;
    Parts := Trim(S).Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
    if Length(Parts) >= 2 then
      AddDependency(Result, Parts[0], Parts[1], Parts[1], Group);
  end;

begin
  Result := nil;
  InBlock := False;
  Start := 1;
  while NextLine(AText, Start, Line) do
  begin
    Line := Trim(Line);
    if Line = '' then
      Continue;
    if InBlock then
    begin
      if Line = ')' then
        InBlock := False
      else
        TakeLine(Line);
      Continue;
    end;
    if Line = 'require (' then
      InBlock := True
    else if Pos('require ', Line) = 1 then
      TakeLine(Copy(Line, 9, MaxInt));
  end;
end;

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

{ ---------------------------------------------------------------------------
  Lazarus
  --------------------------------------------------------------------------- }

{ The Value="..." of the first element named AName in AXml from AFrom,
  with where it was found; '' and 0 for none. }
function XmlValue(const AXml, AName: string; AFrom: integer; out AAt: integer): string;
var
  P, Q: integer;
begin
  Result := '';
  AAt := 0;
  P := AFrom;
  while P > 0 do
  begin
    P := PosEx('<' + AName, AXml, P);
    if P = 0 then
      Exit;
    { The whole name: not <PackageName when <Package is asked for. }
    if (P + Length(AName) < Length(AXml)) and
      (AXml[P + Length(AName) + 1] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
    begin
      Inc(P);
      Continue;
    end;
    AAt := P;
    Q := PosEx('Value="', AXml, P);
    if Q = 0 then
      Exit;
    P := PosEx('"', AXml, Q + 7);
    if P = 0 then
      Exit;
    Exit(Copy(AXml, Q + 7, P - Q - 7));
  end;
end;

function ParseLpiPackages(const AXml: string): TGittanDependencies;
var
  From, P, ItemEnd, At, Q: integer;
  Name, Version, Major, Minor: string;
begin
  Result := nil;
  From := Pos('<RequiredPackages', AXml);
  if From = 0 then
    Exit;
  repeat
    P := PosEx('<Item', AXml, From);
    if P = 0 then
      Break;
    ItemEnd := PosEx('</Item', AXml, P);
    if ItemEnd = 0 then
      ItemEnd := Length(AXml);
    Name := XmlValue(Copy(AXml, P, ItemEnd - P), 'PackageName', 1, At);
    Version := '';
    Q := PosEx('<MinVersion', AXml, P);
    if (Q > 0) and (Q < ItemEnd) then
    begin
      { MinVersion has Major="1" Minor="2" Release="3": read them by
        name. }
      Major := '';
      Minor := '';
      At := PosEx('Major="', AXml, Q);
      if (At > 0) and (At < ItemEnd) then
        Major := Copy(AXml, At + 7, PosEx('"', AXml, At + 7) - At - 7);
      At := PosEx('Minor="', AXml, Q);
      if (At > 0) and (At < ItemEnd) then
        Minor := Copy(AXml, At + 7, PosEx('"', AXml, At + 7) - At - 7);
      if Major <> '' then
      begin
        Version := '>= ' + Major;
        if Minor <> '' then
          Version := Version + '.' + Minor;
      end;
    end;
    AddDependency(Result, Name, Version, '', '');
    From := ItemEnd;
  until False;
end;

function LpiVersion(const AXml: string): string;
var
  From, At: integer;
  Major, Minor, Revision, Build: string;

  function Part(const AName: string): string;
  var
    Where: integer;
  begin
    Result := XmlValue(Copy(AXml, From, MaxInt), AName, 1, Where);
    if Result = '' then
      Result := '0';
  end;

begin
  Result := '';
  From := Pos('<VersionInfo', AXml);
  if From = 0 then
    Exit;
  if not SameText(XmlValue(Copy(AXml, From, MaxInt), 'UseVersionInfo', 1, At), 'True') then
    Exit;
  Major := Part('MajorVersionNr');
  Minor := Part('MinorVersionNr');
  Revision := Part('RevisionNr');
  Build := Part('BuildNr');
  Result := Major + '.' + Minor + '.' + Revision;
  if Build <> '0' then
    Result := Result + '.' + Build;
end;

end.
