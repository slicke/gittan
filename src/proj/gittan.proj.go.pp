unit gittan.proj.go;

{** The Go driver: a go.mod at the root. Its commands are go build,
  run (when a root file is package main), test, vet and fmt over ./...;
  its section shows the module's path, the Go version and toolchain it
  asks for and its replace lines beside the requirements, which go.mod
  holds resolved (go.sum only checks them). Tested in
  tests/testprojgo.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.manifest, gittan.project;

type
  {** A replace line of a go.mod: the module (with its version when the
    line names one) and what it is replaced with, a path or a module
    at a version. }
  TGoReplace = record
    Old, New: string;
  end;
  TGoReplaces = array of TGoReplace;

  {** What a go.mod says beside its requirements. }
  TGoModInfo = record
    Module, Go, Toolchain: string;
    Replaces: TGoReplaces;
  end;

  { TGittanGoKind }

  TGittanGoKind = class(TGittanProjectKind)
  public
    class function Name: string; override;
    class function Identify(const ARoot: string; out AManifest: string): boolean; override;
    class function Commands(const ARoot: string): TGittanProjectCommands; override;
    class function DependencyFile(const ARoot: string): string; override;
    class function Dependencies(const AText: string): TGittanDependencies; override;
    class function PackageUrl(const AName: string): string; override;
    class function Checks(AContext: TGittanProjectContext): TGittanProjectChecks; override;
    class function Section(AContext: TGittanProjectContext;
      const AManifest: string): TGittanProjectSection; override;
  end;

{** The requirements of a go.mod: "require x v1.2.3" and the require
  block, the version in Version and in Resolved alike, since go.mod
  holds the resolved one; "// indirect" is the group indirect. }
function ParseGoMod(const AText: string): TGittanDependencies;

{** The module line, the go and toolchain lines and the replace lines
  (one or a block) of a go.mod's text. }
function ParseGoModInfo(const AText: string): TGoModInfo;

implementation

uses
  gittan.textfile;

resourcestring
  rsNoGoSum = 'No go.sum. go mod tidy writes it; commit it so that every build checks the ' +
    'modules it downloads.';
  rsModule = 'Module';
  rsGoVersion = 'Go';
  rsToolchain = 'Toolchain';
  rsReplaces = 'Replaced';
  rsLocalReplace = 'A replace with a path builds against a folder on this computer; a clone ' +
    'without it does not build. %s';

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


function ParseGoModInfo(const AText: string): TGoModInfo;
var
  Start, P: integer;
  Line: string;
  InReplace: boolean;

  procedure TakeReplace(const ALine: string);
  var
    S: string;
    Q: integer;
  begin
    S := ALine;
    Q := Pos('//', S);
    if Q > 0 then
      S := Copy(S, 1, Q - 1);
    Q := Pos('=>', S);
    if Q = 0 then
      Exit;
    SetLength(Result.Replaces, Length(Result.Replaces) + 1);
    Result.Replaces[High(Result.Replaces)].Old := Trim(Copy(S, 1, Q - 1));
    Result.Replaces[High(Result.Replaces)].New := Trim(Copy(S, Q + 2, MaxInt));
  end;

begin
  Result := Default(TGoModInfo);
  InReplace := False;
  Start := 1;
  while NextLine(AText, Start, Line) do
  begin
    Line := Trim(Line);
    if InReplace then
    begin
      if Line = ')' then
        InReplace := False
      else if Line <> '' then
        TakeReplace(Line);
      Continue;
    end;
    P := Pos('//', Line);
    if P = 1 then
      Continue;
    if Pos('module ', Line) = 1 then
      Result.Module := Trim(Copy(Line, 8, MaxInt))
    else if Pos('go ', Line) = 1 then
      Result.Go := Trim(Copy(Line, 4, MaxInt))
    else if Pos('toolchain ', Line) = 1 then
      Result.Toolchain := Trim(Copy(Line, 11, MaxInt))
    else if (Line = 'replace (') or (Line = 'replace(') then
      InReplace := True
    else if Pos('replace ', Line) = 1 then
      TakeReplace(Copy(Line, 9, MaxInt));
  end;
  Result.Module := StringReplace(Result.Module, '"', '', [rfReplaceAll]);
end;

{ Whether a .go file at the root is of package main, so "go run ." has
  something to run; a _test.go file is not built by go run. }
function RootIsMainPackage(const ARoot: string): boolean;
var
  FileName, Text, Line: string;
  Start: integer;
begin
  for FileName in FilesWithExt(ARoot, '.go') do
  begin
    if SameText(Copy(FileName, Length(FileName) - 7, 8), '_test.go') then
      Continue;
    Text := TextOf(ARoot, FileName);
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

{ A replacement that is an absolute folder: /x, \x, or C:\x and C:/x. }
function IsAbsolutePath(const ATarget: string): boolean;
begin
  Result := (Pos('/', ATarget) = 1) or (Pos('\', ATarget) = 1) or
    ((Length(ATarget) >= 3) and (UpCase(ATarget[1]) in ['A'..'Z']) and (ATarget[2] = ':') and
    (ATarget[3] in ['/', '\']));
end;

{ A replacement that is a folder, as go reads it: ., .., one that
  starts with ./ or ../ (.\ and ..\ too), or an absolute one. }
function IsLocalPath(const ATarget: string): boolean;
begin
  Result := (ATarget = '.') or (ATarget = '..') or (Pos('./', ATarget) = 1) or
    (Pos('../', ATarget) = 1) or (Pos('.\', ATarget) = 1) or (Pos('..\', ATarget) = 1) or
    IsAbsolutePath(ATarget);
end;

{ The folder of a local replacement: an absolute one as it is, else
  from the root. }
function LocalPathDir(const ARoot, ATarget: string): string;
begin
  if IsAbsolutePath(ATarget) then
    Result := SetDirSeparators(ATarget)
  else
    Result := RootFile(ARoot, ATarget);
end;

{ TGittanGoKind }

class function TGittanGoKind.Name: string;
begin
  Result := 'Go';
end;

class function TGittanGoKind.Identify(const ARoot: string; out AManifest: string): boolean;
begin
  Result := HasFile(ARoot, 'go.mod');
  if Result then
    AManifest := 'go.mod'
  else
    AManifest := '';
end;

class function TGittanGoKind.Commands(const ARoot: string): TGittanProjectCommands;
begin
  Result := nil;
  AddProjectCommand(Result, ProjectCommand('build', 'go build ./...'));
  if RootIsMainPackage(ARoot) then
    AddProjectCommand(Result, ProjectCommand('run', 'go run .'));
  AddProjectCommand(Result, ProjectCommand('test', 'go test ./...'));
  AddProjectCommand(Result, ProjectCommand('vet', 'go vet ./...'));
  AddProjectCommand(Result, ProjectCommand('fmt', 'go fmt ./...'));
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

class function TGittanGoKind.Checks(AContext: TGittanProjectContext): TGittanProjectChecks;
var
  Info: TGoModInfo;
  i: integer;
begin
  Result := nil;
  if not HasFile(AContext.Root, 'go.sum') and
    (Length(ParseGoMod(TextOf(AContext.Root, 'go.mod'))) > 0) then
    AddProjectCheck(Result, ProjectCheck(rsNoGoSum, ''));
  Info := ParseGoModInfo(TextOf(AContext.Root, 'go.mod'));
  for i := 0 to High(Info.Replaces) do
    if IsLocalPath(Info.Replaces[i].New) and
      not DirectoryExists(LocalPathDir(AContext.Root, Info.Replaces[i].New)) then
      AddProjectCheck(Result, ProjectCheck(Format(rsLocalReplace, [Info.Replaces[i].Old +
        ' => ' + Info.Replaces[i].New]), ''));
end;

class function TGittanGoKind.Section(AContext: TGittanProjectContext;
  const AManifest: string): TGittanProjectSection;
var
  Info: TGoModInfo;
  Facts, Replaced: TGittanProjectBlock;
  Std: TGittanProjectSection;
  i: integer;
  Style: TGittanProjectStyle;
begin
  Std := StandardSection(AContext, AManifest);
  Result := Std;
  Result.Blocks := nil;
  Info := ParseGoModInfo(TextOf(AContext.Root, 'go.mod'));
  Facts := ProjectBlock(pbFacts);
  AddFact(Facts, rsModule, Info.Module, psStrong, PackageUrl(Info.Module));
  AddFact(Facts, rsGoVersion, Info.Go);
  AddFact(Facts, rsToolchain, Info.Toolchain);
  AddBlock(Result, Facts);
  for i := 0 to High(Std.Blocks) do
    if Std.Blocks[i].Kind <> pbChecks then
      AddBlock(Result, Std.Blocks[i]);
  Replaced := ProjectBlock(pbTable, rsReplaces);
  for i := 0 to High(Info.Replaces) do
  begin
    if IsLocalPath(Info.Replaces[i].New) then
      Style := psWarn
    else
      Style := psText;
    AddRow(Replaced, ProjectRow([ProjectCell(Info.Replaces[i].Old, psStrong),
      ProjectCell('→', psDim), ProjectCell(Info.Replaces[i].New, Style)]));
  end;
  AddBlock(Result, Replaced);
  for i := 0 to High(Std.Blocks) do
    if Std.Blocks[i].Kind = pbChecks then
      AddBlock(Result, Std.Blocks[i]);
end;

initialization
  RegisterProjectKind(TGittanGoKind);

end.
