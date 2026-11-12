unit gittan.proj.lazarus;

{** The Lazarus driver: a .lpi at the root (a .lpr alone is built with
  fpc). It reads the project with fcl-xml's DOM: the title, the version
  of <VersionInfo>, the build modes with what each builds (the target
  file, the platform, the widgetset, the optimization, the debug info,
  the custom options; a mode with no options of its own, the one marked
  Default, takes the project's), the packages it requires and the units
  in it. Its commands build each mode with lazbuild --bm. Its section
  shows the modes as a table with a Build button each, and the packages
  with where each comes from: a .lpk in the repository (read for its
  version and description), in a submodule at a commit (described by
  its tag, with the move since the last tag), a package of Lazarus
  itself, or nowhere, which a clone then has to install. Tested in
  tests/testprojlazarus.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.manifest, gittan.project;

type
  {** A build mode of a .lpi: its name, whether it is the default
    (Lazarus's own mode, which takes the project's options), and what
    its options say; '' where the .lpi leaves Lazarus's default. }
  TLazBuildMode = record
    Name: string;
    IsDefault: boolean;
    Target, TargetOS, TargetCPU, Widgetset, UnitOutput: string;
    {** The -O level as Lazarus writes it ("2"); '' for its default. }
    Optimization: string;
    {** "off", "DWARF 2", "DWARF 3", "on" (Lazarus's automatic). }
    Debug: string;
    Strip, SmartLink: boolean;
    CustomOptions: string;
  end;
  TLazBuildModes = array of TLazBuildMode;

  {** What a .lpi says. }
  TLazProject = record
    Title, Version, SessionStorage: string;
    Modes: TLazBuildModes;
    {** The required packages, the minimum version as Version (">= 2.4"). }
    Packages: TGittanDependencies;
    Units: integer;
  end;

  {** What a .lpk says. }
  TLazPackage = record
    Name, Version, Description, License, Author: string;
    Requires: TStringArray;
  end;

  { TGittanLazarusKind }

  TGittanLazarusKind = class(TGittanProjectKind)
  public
    class function Name: string; override;
    class function Identify(const ARoot: string; out AManifest: string): boolean; override;
    class function Commands(const ARoot: string): TGittanProjectCommands; override;
    class function DependencyFile(const ARoot: string): string; override;
    class function Dependencies(const AText: string): TGittanDependencies; override;
    class function Version(const AText: string): string; override;
    class function Checks(AContext: TGittanProjectContext): TGittanProjectChecks; override;
    class function Section(AContext: TGittanProjectContext;
      const AManifest: string): TGittanProjectSection; override;
  end;

{** The project a .lpi's text describes; a default record when the text
  is not XML. }
function ReadLazProject(const AXml: string): TLazProject;

{** The package a .lpk's text describes. }
function ReadLazPackage(const AXml: string): TLazPackage;

{** The packages a .lpi requires (ReadLazProject's Packages). }
function ParseLpiPackages(const AXml: string): TGittanDependencies;

{** The version <VersionInfo> gives when it is in use, "1.2.0" (with
  the build when it is not 0); ''. }
function LpiVersion(const AXml: string): string;

{** The .lpk files under ARoot, as paths from it with "/", by name: a
  walk at most LazPackageDepth folders deep that skips hidden folders
  and lib, backup and node_modules. }
function FindLazPackages(const ARoot: string): TStringArray;

{** Whether AName is a package that comes with Lazarus (LCL, FCL,
  LazUtils, SynEdit and the like), whatever the case. }
function IsLazarusPackage(const AName: string): boolean;

{** The command that builds the mode AMode of the project ALpi:
  lazbuild --bm=AMode ALpi, lazbuild found where Lazarus is usually
  installed when it is not on the PATH. }
function LazBuildCommand(const ALpi, AMode: string): string;

const
  {** How deep FindLazPackages looks. }
  LazPackageDepth = 5;

implementation

uses
  DOM, XMLRead, gittan.textfile, gittan.submodules, gittan.git;

resourcestring
  rsLpsTracked = '%s is committed. The session file changes every time the project is opened ' +
    'in Lazarus; it belongs in .gitignore.';
  rsLibTracked = 'Files under lib/ are committed: the compiled units, which every build ' +
    'writes again.';
  rsBackupTracked = 'Files under backup/ are committed: the IDE''s copies of files before ' +
    'an edit.';
  rsPackageMissing = '%s is not in the repository and does not come with Lazarus: a clone ' +
    'builds only where it is installed in the IDE.';
  rsSubmoduleEmpty = '%s is not checked out, so its packages are not found: git submodule ' +
    'update --init.';
  rsTitle = 'Title';
  rsVersion = 'Version';
  rsUnits = 'Units';
  rsSession = 'Session';
  rsSessionInProject = 'kept in the project folder (.lps)';
  rsSessionInIDE = 'kept in the IDE''s configuration';
  rsSessionNone = 'not kept';
  rsModes = 'Build modes';
  rsPackages = 'Packages';
  rsColMode = 'Mode';
  rsColOutput = 'Output';
  rsColPlatform = 'Platform';
  rsColCode = 'Code';
  rsColDebug = 'Debug';
  rsColPackage = 'Package';
  rsColRequires = 'Requires';
  rsColSource = 'From';
  rsColVersion = 'Version';
  rsDefaultMode = 'default';
  rsDefaultModeHint = 'Lazarus''s default mode: the project''s own options';
  rsHost = 'this computer';
  rsDefaultWidgetset = 'default widgetset';
  rsSmartLink = 'smart link';
  rsStripped = 'stripped';
  rsDebugOff = 'off';
  rsDebugOn = 'on';
  rsBuild = 'Build';
  rsFromLazarus = 'Lazarus';
  rsNotFound = 'not found';
  rsSubmoduleAt = '%s @ %s';
  rsMovedHint = '%s moved from %s to %s since %s';
  rsAdded = 'added';
  rsRemoved = 'removed';
  rsAddedHint = '%s is required since %s';
  rsRemovedHint = '%s was required at %s';
  rsMinChangedHint = '%s required %s at %s';
  rsAnyVersion = 'any';
  rsCountModes = '%d build modes';
  rsCountPackages = '%d packages';
  rsChangesSince = '%d changed since %s';
  rsOneChangeSince = '1 changed since %s';
  rsNoChangesSince = 'no changes since %s';

{ ---------------------------------------------------------------------------
  Reading the XML
  --------------------------------------------------------------------------- }

{ No DOCTYPE is read: Lazarus writes none, and its entities would be
  expanded without a limit (a file under a kilobyte can ask for
  gigabytes, the "billion laughs"). }
function LoadXml(const AXml: string): TXMLDocument;
var
  Parser: TDOMParser;
  Source: TXMLInputSource;
begin
  Result := nil;
  if Trim(AXml) = '' then
    Exit;
  Parser := TDOMParser.Create;
  Source := TXMLInputSource.Create(AXml);
  try
    Parser.Options.DisallowDoctype := True;
    try
      Parser.Parse(Source, Result);
    except
      FreeAndNil(Result);
    end;
  finally
    Source.Free;
    Parser.Free;
  end;
end;

{ The child element of AParent named AName, nil. }
function Child(AParent: TDOMNode; const AName: string): TDOMElement;
var
  N: TDOMNode;
begin
  Result := nil;
  if AParent = nil then
    Exit;
  N := AParent.FirstChild;
  while N <> nil do
  begin
    if (N.NodeType = ELEMENT_NODE) and (N.NodeName = UnicodeString(AName)) then
      Exit(TDOMElement(N));
    N := N.NextSibling;
  end;
end;

{ The element at APath ("CodeGeneration/Optimizations/OptimizationLevel")
  under AParent, nil. }
function At(AParent: TDOMNode; const APath: string): TDOMElement;
var
  Part: string;
  N: TDOMNode;
begin
  Result := nil;
  N := AParent;
  for Part in APath.Split(['/']) do
  begin
    N := Child(N, Part);
    if N = nil then
      Exit;
  end;
  Result := TDOMElement(N);
end;

function Attr(AElement: TDOMElement; const AName: string): string;
begin
  if AElement = nil then
    Result := ''
  else
    Result := string(AElement.GetAttribute(UnicodeString(AName)));
end;

{ The Value attribute of the element at APath under AParent. }
function ValueAt(AParent: TDOMNode; const APath: string): string;
begin
  Result := Attr(At(AParent, APath), 'Value');
end;

{ The first element named AName anywhere under ANode, nil. }
function Find(ANode: TDOMNode; const AName: string): TDOMElement;
var
  N: TDOMNode;
begin
  Result := nil;
  if ANode = nil then
    Exit;
  N := ANode.FirstChild;
  while N <> nil do
  begin
    if N.NodeType = ELEMENT_NODE then
    begin
      if N.NodeName = UnicodeString(AName) then
        Exit(TDOMElement(N));
      Result := Find(N, AName);
      if Result <> nil then
        Exit;
    end;
    N := N.NextSibling;
  end;
end;

{ The element children of AParent, whatever their name (Item, Item1,
  Item2: the old and the new form of a list). }
function Items(AParent: TDOMNode): TList;
var
  N: TDOMNode;
begin
  Result := TList.Create;
  if AParent = nil then
    Exit;
  N := AParent.FirstChild;
  while N <> nil do
  begin
    if N.NodeType = ELEMENT_NODE then
      Result.Add(N);
    N := N.NextSibling;
  end;
end;

{ What a <CompilerOptions> says, into AMode. }
procedure ReadOptions(AOptions: TDOMElement; var AMode: TLazBuildMode);
var
  Debug: TDOMElement;
  Gen, Kind: string;
begin
  if AOptions = nil then
    Exit;
  AMode.Target := ValueAt(AOptions, 'Target/Filename');
  AMode.TargetOS := ValueAt(AOptions, 'CodeGeneration/TargetOS');
  AMode.TargetCPU := ValueAt(AOptions, 'CodeGeneration/TargetCPU');
  AMode.UnitOutput := ValueAt(AOptions, 'SearchPaths/UnitOutputDirectory');
  AMode.Optimization := ValueAt(AOptions, 'CodeGeneration/Optimizations/OptimizationLevel');
  AMode.SmartLink := SameText(ValueAt(AOptions, 'CodeGeneration/SmartLinkUnit'), 'True') or
    SameText(ValueAt(AOptions, 'Linking/LinkSmart'), 'True');
  AMode.CustomOptions := Trim(ValueAt(AOptions, 'Other/CustomOptions'));
  Debug := At(AOptions, 'Linking/Debugging');
  Gen := ValueAt(Debug, 'GenerateDebugInfo');
  Kind := ValueAt(Debug, 'DebugInfoType');
  AMode.Strip := SameText(ValueAt(Debug, 'StripSymbols'), 'True');
  if SameText(Gen, 'False') then
    AMode.Debug := rsDebugOff
  else if Kind = 'dsDwarf2' then
    AMode.Debug := 'DWARF 2'
  else if (Kind = 'dsDwarf2Set') then
    AMode.Debug := 'DWARF 2 (sets)'
  else if Kind = 'dsDwarf3' then
    AMode.Debug := 'DWARF 3'
  else if Kind = 'dsStabs' then
    AMode.Debug := 'stabs'
  else
    AMode.Debug := rsDebugOn;
end;

{ The widgetset a mode's <MacroValues> set (LCLWidgetType), ''. }
function WidgetsetOf(AItem: TDOMNode): string;
var
  List: TList;
  i: integer;
begin
  Result := '';
  List := Items(Child(AItem, 'MacroValues'));
  try
    for i := 0 to List.Count - 1 do
      if Attr(TDOMElement(List[i]), 'Name') = 'LCLWidgetType' then
        Exit(Attr(TDOMElement(List[i]), 'Value'));
  finally
    List.Free;
  end;
end;

function ReadLazProject(const AXml: string): TLazProject;
var
  Doc: TXMLDocument;
  Options, Info, Modes, Item, Own: TDOMElement;
  List: TList;
  i: integer;
  Mode: TLazBuildMode;
  Major, Minor, Rev, Build, Name, Min: string;
begin
  Result := Default(TLazProject);
  Doc := LoadXml(AXml);
  if Doc = nil then
    Exit;
  try
    Options := Find(Doc, 'ProjectOptions');
    Result.Title := ValueAt(Options, 'General/Title');
    Result.SessionStorage := ValueAt(Options, 'General/SessionStorage');
    Info := Find(Doc, 'VersionInfo');
    if (Info <> nil) and SameText(ValueAt(Info, 'UseVersionInfo'), 'True') then
    begin
      Major := ValueAt(Info, 'MajorVersionNr');
      Minor := ValueAt(Info, 'MinorVersionNr');
      Rev := ValueAt(Info, 'RevisionNr');
      Build := ValueAt(Info, 'BuildNr');
      if Major = '' then
        Major := '0';
      if Minor = '' then
        Minor := '0';
      if Rev = '' then
        Rev := '0';
      Result.Version := Major + '.' + Minor + '.' + Rev;
      if (Build <> '') and (Build <> '0') then
        Result.Version := Result.Version + '.' + Build;
    end;
    { The modes; one with no options of its own takes the project's,
      the <CompilerOptions> after <ProjectOptions>. }
    Own := Child(Doc.DocumentElement, 'CompilerOptions');
    Modes := Find(Doc, 'BuildModes');
    List := Items(Modes);
    try
      for i := 0 to List.Count - 1 do
      begin
        Item := TDOMElement(List[i]);
        if Attr(Item, 'Name') = '' then
          Continue;
        Mode := Default(TLazBuildMode);
        Mode.Name := Attr(Item, 'Name');
        Mode.IsDefault := SameText(Attr(Item, 'Default'), 'True');
        if Child(Item, 'CompilerOptions') <> nil then
          ReadOptions(Child(Item, 'CompilerOptions'), Mode)
        else
          ReadOptions(Own, Mode);
        Mode.Widgetset := WidgetsetOf(Item);
        SetLength(Result.Modes, Length(Result.Modes) + 1);
        Result.Modes[High(Result.Modes)] := Mode;
      end;
    finally
      List.Free;
    end;
    { A project with no modes listed has Lazarus's one. }
    if Length(Result.Modes) = 0 then
    begin
      Mode := Default(TLazBuildMode);
      Mode.Name := 'Default';
      Mode.IsDefault := True;
      ReadOptions(Own, Mode);
      SetLength(Result.Modes, 1);
      Result.Modes[0] := Mode;
    end;
    List := Items(Find(Doc, 'RequiredPackages'));
    try
      for i := 0 to List.Count - 1 do
      begin
        Item := TDOMElement(List[i]);
        Name := ValueAt(Item, 'PackageName');
        Min := '';
        if Child(Item, 'MinVersion') <> nil then
        begin
          Major := Attr(Child(Item, 'MinVersion'), 'Major');
          Minor := Attr(Child(Item, 'MinVersion'), 'Minor');
          if Major <> '' then
          begin
            Min := '>= ' + Major;
            if Minor <> '' then
              Min := Min + '.' + Minor;
          end;
        end;
        AddDependency(Result.Packages, Name, Min, '', '');
      end;
    finally
      List.Free;
    end;
    List := Items(Find(Doc, 'Units'));
    try
      Result.Units := List.Count;
    finally
      List.Free;
    end;
  finally
    Doc.Free;
  end;
end;

function ReadLazPackage(const AXml: string): TLazPackage;
const
  { A typed array, not an array constructor: FPC 3.2.2 gets a for-in
    over a constructor of strings wrong. }
  VersionParts: array[0..3] of string = ('Major', 'Minor', 'Release', 'Build');
var
  Doc: TXMLDocument;
  Pkg, Ver: TDOMElement;
  List: TList;
  i: integer;
  Parts: TStringArray;
  Part: string;
begin
  Result := Default(TLazPackage);
  Doc := LoadXml(AXml);
  if Doc = nil then
    Exit;
  try
    Pkg := Find(Doc, 'Package');
    Result.Name := ValueAt(Pkg, 'Name');
    Result.Description := ValueAt(Pkg, 'Description');
    Result.License := ValueAt(Pkg, 'License');
    Result.Author := ValueAt(Pkg, 'Author');
    Ver := Child(Pkg, 'Version');
    if Ver <> nil then
    begin
      Parts := nil;
      for Part in VersionParts do
      begin
        SetLength(Parts, Length(Parts) + 1);
        Parts[High(Parts)] := Attr(Ver, Part);
        if Parts[High(Parts)] = '' then
          Parts[High(Parts)] := '0';
      end;
      { Trailing zeros after the minor are left out: 2.28, 11.6.9. }
      while (Length(Parts) > 2) and (Parts[High(Parts)] = '0') do
        SetLength(Parts, Length(Parts) - 1);
      Result.Version := string.Join('.', Parts);
    end;
    List := Items(Child(Pkg, 'RequiredPkgs'));
    try
      for i := 0 to List.Count - 1 do
        if ValueAt(TDOMElement(List[i]), 'PackageName') <> '' then
        begin
          SetLength(Result.Requires, Length(Result.Requires) + 1);
          Result.Requires[High(Result.Requires)] := ValueAt(TDOMElement(List[i]), 'PackageName');
        end;
    finally
      List.Free;
    end;
  finally
    Doc.Free;
  end;
end;

function ParseLpiPackages(const AXml: string): TGittanDependencies;
begin
  Result := ReadLazProject(AXml).Packages;
end;

function LpiVersion(const AXml: string): string;
begin
  Result := ReadLazProject(AXml).Version;
end;

function FindLazPackages(const ARoot: string): TStringArray;
var
  Found: TStringList;
  i: integer;

  procedure Walk(const ARel: string; ADepth: integer);
  var
    Info: TSearchRec;
    Dir, Rel: string;
  begin
    Dir := IncludeTrailingPathDelimiter(RootFile(ARoot, ARel));
    if FindFirst(Dir + '*', faAnyFile, Info) <> 0 then
      Exit;
    try
      repeat
        if (Info.Name = '.') or (Info.Name = '..') then
          Continue;
        if ARel = '' then
          Rel := Info.Name
        else
          Rel := ARel + '/' + Info.Name;
        if (Info.Attr and faDirectory) <> 0 then
        begin
          if (ADepth < LazPackageDepth) and (Info.Name[1] <> '.') and
            not SameText(Info.Name, 'lib') and not SameText(Info.Name, 'backup') and
            not SameText(Info.Name, 'node_modules') then
            Walk(Rel, ADepth + 1);
        end
        else if SameText(ExtractFileExt(Info.Name), '.lpk') then
          Found.Add(Rel);
      until FindNext(Info) <> 0;
    finally
      FindClose(Info);
    end;
  end;

begin
  Found := TStringList.Create;
  try
    if (ARoot <> '') and DirectoryExists(ARoot) then
      Walk('', 0);
    Found.Sort;
    SetLength(Result, Found.Count);
    for i := 0 to Found.Count - 1 do
      Result[i] := Found[i];
  finally
    Found.Free;
  end;
end;

function IsLazarusPackage(const AName: string): boolean;
const
  Builtin: array[0..27] of string = ('LCL', 'LCLBase', 'FCL', 'FCLBase', 'LazUtils',
    'LazControls', 'SynEdit', 'IDEIntf', 'BuildIntf', 'CodeTools', 'RunTimeTypeInfoControls',
    'Printer4Lazarus', 'TurboPowerIPro', 'LazMouseAndKeyInput', 'LazDebuggerGdbmi', 'FpDebug',
    'CairoCanvas_pkg', 'laz.virtualtreeview_package', 'SQLDBLaz', 'DBFLaz', 'LazReport',
    'LazOpenGLContext', 'LazDaemon', 'WebLaz', 'FCLLaz', 'LazControlDsgn', 'SynEditDsgn',
    'Lazarus_ide');
var
  S: string;
begin
  for S in Builtin do
    if SameText(S, AName) then
      Exit(True);
  Result := False;
end;

{ lazbuild as the shell finds it (FindTool, on the PATH the commands
  run with), else where Lazarus is usually installed, as an app started
  from the Finder has a short PATH. }
function LazbuildPath: string;
const
  Places: array[0..5] of string = (
    '/Applications/lazarus/lazbuild', '/usr/local/bin/lazbuild', '/usr/bin/lazbuild',
    '/usr/lib/lazarus/lazbuild', 'C:\lazarus\lazbuild.exe', 'C:\fpcupdeluxe\lazarus\lazbuild.exe');
var
  Place, Home: string;
begin
  Result := 'lazbuild';
  if FindTool('lazbuild') <> '' then
    Exit;
  Home := GetEnvironmentVariable('HOME');
  if (Home <> '') and FileExists(Home + '/fpcupdeluxe/lazarus/lazbuild') then
    Exit(Home + '/fpcupdeluxe/lazarus/lazbuild');
  for Place in Places do
    if FileExists(Place) then
      Exit(Place);
end;

function LazBuildCommand(const ALpi, AMode: string): string;
begin
  Result := ShellName(LazbuildPath);
  if AMode <> '' then
    Result := Result + ' --bm=' + ShellName(AMode);
  Result := Result + ' ' + ShellName(ALpi);
end;

{ ---------------------------------------------------------------------------
  The kind
  --------------------------------------------------------------------------- }

class function TGittanLazarusKind.Name: string;
begin
  Result := 'Lazarus';
end;

class function TGittanLazarusKind.Identify(const ARoot: string; out AManifest: string): boolean;
var
  Names: TStringArray;
begin
  Names := FilesWithExt(ARoot, '.lpi');
  if Length(Names) = 0 then
    Names := FilesWithExt(ARoot, '.lpr');
  Result := Length(Names) > 0;
  if not Result then
    AManifest := ''
  else if Length(Names) = 1 then
    AManifest := Names[0]
  else
    AManifest := Format('%s +%d', [Names[0], Length(Names) - 1]);
end;

class function TGittanLazarusKind.Commands(const ARoot: string): TGittanProjectCommands;
var
  Names: TStringArray;
  FileName: string;
  Project: TLazProject;
  i: integer;
begin
  Result := nil;
  Names := FilesWithExt(ARoot, '.lpi');
  if Length(Names) = 0 then
  begin
    { A program without a project: fpc builds it. }
    for FileName in FilesWithExt(ARoot, '.lpr') do
      if Length(FilesWithExt(ARoot, '.lpr')) > 1 then
        AddProjectCommand(Result, ProjectCommand('build:' + ChangeFileExt(FileName, ''),
          'fpc ' + ShellName(FileName)))
      else
        AddProjectCommand(Result, ProjectCommand('build', 'fpc ' + ShellName(FileName)));
    Exit;
  end;
  if Length(Names) > 1 then
  begin
    { Several projects: each in its default mode. }
    for FileName in Names do
      AddProjectCommand(Result, ProjectCommand('build:' + ChangeFileExt(FileName, ''),
        LazBuildCommand(FileName, '')));
    Exit;
  end;
  { One project: a command per build mode, grouped under build. }
  Project := ReadLazProject(TextOf(ARoot, Names[0]));
  if Length(Project.Modes) <= 1 then
    AddProjectCommand(Result, ProjectCommand('build', LazBuildCommand(Names[0], '')))
  else
    for i := 0 to High(Project.Modes) do
      AddProjectCommand(Result, ProjectCommand('build:' + Project.Modes[i].Name,
        LazBuildCommand(Names[0], Project.Modes[i].Name)));
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

{ Where each required package is: its .lpk among APackages (by file
  name), or ''. }
function PackageFile(const AName: string; const APackages: TStringArray): string;
var
  P: string;
begin
  for P in APackages do
    if SameText(ChangeFileExt(ExtractFileName(P), ''), AName) then
      Exit(P);
  Result := '';
end;

{ Whether the folder ADir has nothing in it: a submodule not checked
  out. }
function DirIsEmpty(const ADir: string): boolean;
var
  Info: TSearchRec;
begin
  Result := True;
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, Info) = 0 then
  try
    repeat
      if (Info.Name <> '.') and (Info.Name <> '..') then
        Exit(False);
    until FindNext(Info) <> 0;
  finally
    FindClose(Info);
  end;
end;

{ The submodule APath is in, or -1. }
function SubmoduleOf(const APath: string; const ASubs: TGittanSubmodules): integer;
var
  i: integer;
begin
  for i := 0 to High(ASubs) do
    if Pos(ASubs[i].Path + '/', APath) = 1 then
      Exit(i);
  Result := -1;
end;

class function TGittanLazarusKind.Checks(AContext: TGittanProjectContext): TGittanProjectChecks;
var
  Path, Lpi: string;
  Project: TLazProject;
  Packages: TStringArray;
  Subs: TGittanSubmodules;
  i: integer;
begin
  Result := nil;
  Path := AContext.TrackedWithExt('.lps');
  if Path <> '' then
    AddProjectCheck(Result, ProjectCheck(Format(rsLpsTracked, [Path]), Path, '*.lps'));
  if AContext.TrackedUnder('lib/', Path) then
    AddProjectCheck(Result, ProjectCheck(rsLibTracked, Path, '/lib/'));
  if AContext.TrackedUnder('backup/', Path) then
    AddProjectCheck(Result, ProjectCheck(rsBackupTracked, Path, '/backup/'));
  { A submodule not checked out hides its packages; say so once for
    each, then the packages found nowhere. }
  Subs := AContext.Submodules;
  for i := 0 to High(Subs) do
    if DirIsEmpty(RootFile(AContext.Root, Subs[i].Path)) then
      AddProjectCheck(Result, ProjectCheck(Format(rsSubmoduleEmpty, [Subs[i].Path]),
        Subs[i].Path));
  Lpi := DependencyFile(AContext.Root);
  if Lpi = '' then
    Exit;
  Project := ReadLazProject(TextOf(AContext.Root, Lpi));
  Packages := FindLazPackages(AContext.Root);
  for i := 0 to High(Project.Packages) do
    if not IsLazarusPackage(Project.Packages[i].Name) and
      (PackageFile(Project.Packages[i].Name, Packages) = '') then
      AddProjectCheck(Result, ProjectCheck(Format(rsPackageMissing, [Project.Packages[i].Name]),
        ''));
end;

{ A minimum version as shown: "any" for none. }
function VersionOrAny(const AVersion: string): string;
begin
  if AVersion = '' then
    Result := rsAnyVersion
  else
    Result := AVersion;
end;

{ A mode's platform: the OS and CPU it targets (this computer when it
  names none) and its widgetset. }
function PlatformOf(const AMode: TLazBuildMode): string;
begin
  if (AMode.TargetOS = '') and (AMode.TargetCPU = '') then
  begin
    { This computer's: the widgetset alone says what differs. }
    if AMode.Widgetset <> '' then
      Exit(AMode.Widgetset);
    Result := rsHost;
  end
  else if AMode.TargetCPU = '' then
    Result := AMode.TargetOS
  else if AMode.TargetOS = '' then
    Result := AMode.TargetCPU
  else
    Result := AMode.TargetCPU + '-' + AMode.TargetOS;
  if AMode.Widgetset <> '' then
    Result := Result + ' · ' + AMode.Widgetset;
end;

function CodeOf(const AMode: TLazBuildMode): string;
begin
  if AMode.Optimization <> '' then
    Result := '-O' + AMode.Optimization
  else
    Result := '-O1';
  if AMode.SmartLink then
    Result := Result + ' · ' + rsSmartLink;
end;

function DebugOf(const AMode: TLazBuildMode): string;
begin
  Result := AMode.Debug;
  if AMode.Strip then
    Result := Result + ' · ' + rsStripped;
end;

class function TGittanLazarusKind.Section(AContext: TGittanProjectContext;
  const AManifest: string): TGittanProjectSection;
var
  Lpi, Source, SourceHint, Old, Now, Ver, Hint: string;
  Project: TLazProject;
  Facts, Modes, Pkgs: TGittanProjectBlock;
  Packages: TStringArray;
  Subs: TGittanSubmodules;
  Deps: TGittanDependencies;
  Changes: TGittanDependencyChanges;
  Pkg: TLazPackage;
  Cell, Note: TGittanProjectCell;
  ModeHint, NameText: string;
  i, k, s, n: integer;
begin
  Result := Default(TGittanProjectSection);
  Result.Kind := Self;
  Result.Name := Name;
  Result.Detail := AManifest;
  Result.StateStyle := psDim;
  Lpi := DependencyFile(AContext.Root);
  if Lpi = '' then
  begin
    { A program alone: nothing to read beyond its commands. }
    AddBlock(Result, ChecksBlock(Checks(AContext)));
    Exit;
  end;
  Project := ReadLazProject(TextOf(AContext.Root, Lpi));
  if Project.Version <> '' then
    Result.Detail := Result.Detail + ' · ' + Project.Version;
  if Length(Project.Modes) > 1 then
    Result.Detail := Result.Detail + ' · ' + Format(rsCountModes, [Length(Project.Modes)]);
  if Length(Project.Packages) > 0 then
    Result.Detail := Result.Detail + ' · ' + Format(rsCountPackages, [Length(Project.Packages)]);

  Facts := ProjectBlock(pbFacts);
  AddFact(Facts, rsTitle, Project.Title, psStrong);
  AddFact(Facts, rsVersion, Project.Version);
  if Project.Units > 0 then
    AddFact(Facts, rsUnits, IntToStr(Project.Units));
  if Project.SessionStorage = 'InProjectDir' then
    AddFact(Facts, rsSession, rsSessionInProject)
  else if Project.SessionStorage = 'InIDEConfig' then
    AddFact(Facts, rsSession, rsSessionInIDE)
  else if Project.SessionStorage = 'None' then
    AddFact(Facts, rsSession, rsSessionNone);
  AddBlock(Result, Facts);

  { The build modes, each with what it builds and a Build button. }
  Modes := ProjectBlock(pbTable, rsModes);
  Modes.Columns := [rsColMode, rsColOutput, rsColPlatform, rsColCode, rsColDebug, ''];
  Modes.RightLast := True;
  for i := 0 to High(Project.Modes) do
  begin
    ModeHint := Project.Modes[i].CustomOptions;
    if Project.Modes[i].IsDefault then
    begin
      if ModeHint <> '' then
        ModeHint := rsDefaultModeHint + LineEnding + ModeHint
      else
        ModeHint := rsDefaultModeHint;
    end;
    NameText := Project.Modes[i].Name;
    Cell := ProjectCell(NameText, psStrong, ModeHint);
    Hint := Project.Modes[i].UnitOutput;
    AddRow(Modes, ProjectRow([Cell,
      ProjectCell(Project.Modes[i].Target, psText, Hint),
      ProjectCell(PlatformOf(Project.Modes[i]), psDim),
      ProjectCell(CodeOf(Project.Modes[i]), psDim),
      ProjectCell(DebugOf(Project.Modes[i]), psDim),
      ProjectButton(rsBuild, 'build:' + Project.Modes[i].Name,
        LazBuildCommand(Lpi, Project.Modes[i].Name))]));
    if Project.Modes[i].IsDefault and (Length(Project.Modes) > 1) and
      not SameText(NameText, 'Default') then
      Modes.Rows[High(Modes.Rows)].Cells[0].Text := NameText + ' · ' + rsDefaultMode;
  end;
  AddBlock(Result, Modes);

  { The packages and where each comes from; the moves since the tag. }
  ReadDependencies(Self, AContext, Deps, Changes);
  Packages := FindLazPackages(AContext.Root);
  Subs := AContext.Submodules;
  Pkgs := ProjectBlock(pbTable, rsPackages);
  Pkgs.Columns := [rsColPackage, rsColRequires, rsColSource, rsColVersion, ''];
  Pkgs.RightLast := True;
  n := Length(Changes);
  for i := 0 to High(Deps) do
  begin
    Source := PackageFile(Deps[i].Name, Packages);
    SourceHint := '';
    Ver := '';
    Hint := '';
    Note := ProjectCell('');
    if Source <> '' then
    begin
      Pkg := ReadLazPackage(TextOf(AContext.Root, Source));
      Ver := Pkg.Version;
      Hint := Pkg.Description;
      SourceHint := Source;
      s := SubmoduleOf(Source, Subs);
      if s >= 0 then
      begin
        Now := Subs[s].Recorded;
        Source := Format(rsSubmoduleAt, [Subs[s].Path, AContext.Describe(Subs[s].Path, Now)]);
        SourceHint := SourceHint + LineEnding + Subs[s].Url;
        if AContext.Since <> '' then
        begin
          Old := AContext.GitlinkAt(Subs[s].Path, AContext.Since);
          if (Old <> '') and (Now <> '') and (Old <> Now) then
          begin
            Note := ProjectCell(AContext.Describe(Subs[s].Path, Old) + ' → ' +
              AContext.Describe(Subs[s].Path, Now), psLink, Format(rsMovedHint,
              [Subs[s].Path, Copy(Old, 1, 7), Copy(Now, 1, 7), AContext.Since]));
            Inc(n);
          end;
        end;
      end;
      Cell := ProjectCell(Source, psText, SourceHint);
    end
    else if IsLazarusPackage(Deps[i].Name) then
      Cell := ProjectCell(rsFromLazarus, psDim)
    else
      Cell := ProjectCell(rsNotFound, psWarn);
    for k := 0 to High(Changes) do
      if Changes[k].Name = Deps[i].Name then
        case Changes[k].Kind of
          dcAdded:
            Note := ProjectCell(rsAdded, psOk, Format(rsAddedHint, [Deps[i].Name,
              AContext.Since]));
          dcChanged:
            Note := ProjectCell(VersionOrAny(Changes[k].OldVersion) + ' → ' +
              VersionOrAny(Changes[k].NewVersion), psLink,
              Format(rsMinChangedHint, [Deps[i].Name, Changes[k].OldVersion, AContext.Since]));
          dcRemoved: ;
        end;
    AddRow(Pkgs, ProjectRow([ProjectCell(Deps[i].Name, psStrong, Hint),
      ProjectCell(Deps[i].Version, psDim), Cell, ProjectCell(Ver), Note]));
  end;
  for k := 0 to High(Changes) do
    if Changes[k].Kind = dcRemoved then
      AddRow(Pkgs, ProjectRow([ProjectCell(Changes[k].Name, psDim),
        ProjectCell(Changes[k].OldVersion, psDim), ProjectCell(''), ProjectCell(''),
        ProjectCell(rsRemoved, psError, Format(rsRemovedHint, [Changes[k].Name,
        AContext.Since]))]));
  AddBlock(Result, Pkgs);
  { The changes: the packages added and removed, and the submodules
    moved. Changes holds a changed MinVersion too. }
  if AContext.Since <> '' then
  begin
    if n = 0 then
      Result.State := Format(rsNoChangesSince, [AContext.Since])
    else
    begin
      if n = 1 then
        Result.State := Format(rsOneChangeSince, [AContext.Since])
      else
        Result.State := Format(rsChangesSince, [n, AContext.Since]);
      Result.StateStyle := psLink;
    end;
  end;
  AddBlock(Result, ChecksBlock(Checks(AContext)));
end;

initialization
  RegisterProjectKind(TGittanLazarusKind);

end.
