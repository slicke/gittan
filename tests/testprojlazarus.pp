unit testprojlazarus;

{** Tests of gittan.proj.lazarus: its parsers as functions of the text, and its
  section of the Project page built in a temporary folder. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.manifest, gittan.project, gittan.submodules,
  gittan.proj.lazarus, testhelpers;

type
  TProjLazarusTest = class(TTestCase)
  private
    FDir: string;
    procedure Put(const ARel, AText: string);
    function Names(const ADeps: TGittanDependencies): string;
    function Find(const ADeps: TGittanDependencies; const AName: string): TGittanDependency;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLpi;
    procedure TestLpiVersion;
    procedure TestReadProject;
    procedure TestReadPackage;
    procedure TestFindPackages;
    procedure TestCommandsPerMode;
    procedure TestSection;
    procedure TestSectionMove;
  end;

implementation

const
  LE = LineEnding;

procedure TProjLazarusTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-projlazarus-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
end;

procedure TProjLazarusTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TProjLazarusTest.Put(const ARel, AText: string);
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

function TProjLazarusTest.Names(const ADeps: TGittanDependencies): string;
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

function TProjLazarusTest.Find(const ADeps: TGittanDependencies;
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

procedure TProjLazarusTest.TestLpi;
var
  D: TGittanDependencies;
begin
  { The old form, Item1 and Item2 with a count; the new one, Item. }
  D := ParseLpiPackages('<CONFIG><ProjectOptions><RequiredPackages Count="2">' +
    '<Item1><PackageName Value="LCL"/></Item1>' +
    '<Item2><PackageName Value="atsynedit_package"/>' +
    '<MinVersion Major="2" Minor="4" Valid="True"/></Item2>' +
    '</RequiredPackages><Units Count="1"><Item><Filename Value="x.pp"/></Item></Units>' +
    '</ProjectOptions></CONFIG>');
  AssertEquals('LCL atsynedit_package', Names(D));
  AssertEquals('', Find(D, 'LCL').Version);
  AssertEquals('>= 2.4', Find(D, 'atsynedit_package').Version);
  D := ParseLpiPackages('<CONFIG><ProjectOptions><RequiredPackages>' +
    '<Item><PackageName Value="LCL"/></Item><Item><PackageName Value="LazUtils"/></Item>' +
    '</RequiredPackages></ProjectOptions></CONFIG>');
  AssertEquals('LCL LazUtils', Names(D));
  AssertEquals(0, Length(ParseLpiPackages('<CONFIG/>')));
end;

procedure TProjLazarusTest.TestLpiVersion;
begin
  AssertEquals('1.2.0', LpiVersion('<CONFIG><ProjectOptions><VersionInfo>' +
    '<UseVersionInfo Value="True"/><MajorVersionNr Value="1"/><MinorVersionNr Value="2"/>' +
    '</VersionInfo></ProjectOptions></CONFIG>'));
  AssertEquals('1.2.3.4', LpiVersion('<VersionInfo><UseVersionInfo Value="True"/>' +
    '<MajorVersionNr Value="1"/><MinorVersionNr Value="2"/><RevisionNr Value="3"/>' +
    '<BuildNr Value="4"/></VersionInfo>'));
  AssertEquals('not in use', '', LpiVersion('<VersionInfo><MajorVersionNr Value="1"/>' +
    '</VersionInfo>'));
  AssertEquals('', LpiVersion('<CONFIG/>'));
end;

const
  { A project as Trndi's: the default mode with the project's options, a
    mode with its own, a mode for GTK3 through a macro. }
  TrndiLpi = '<?xml version="1.0" encoding="UTF-8"?>' + LE + '<CONFIG><ProjectOptions>' +
    '<General><SessionStorage Value="InProjectDir"/><Title Value="Trndi"/></General>' +
    '<VersionInfo><UseVersionInfo Value="True"/><MajorVersionNr Value="23"/>' +
    '<BuildNr Value="248"/></VersionInfo>' +
    '<BuildModes><Item Name="No Ext (Release)" Default="True"/>' +
    '<Item Name="Extensions (Debug)"><CompilerOptions><Target><Filename Value="Trndi"/></Target>' +
    '<SearchPaths><UnitOutputDirectory Value="lib\$(TargetCPU)-$(TargetOS)"/></SearchPaths>' +
    '<CodeGeneration><Optimizations><OptimizationLevel Value="0"/></Optimizations></CodeGeneration>' +
    '<Linking><Debugging><DebugInfoType Value="dsDwarf3"/></Debugging></Linking>' +
    '<Other><CustomOptions Value="-dEXT"/></Other></CompilerOptions></Item>' +
    '<Item Name="GTK3"><MacroValues Count="1"><Macro3 Name="LCLWidgetType" Value="gtk3"/>' +
    '</MacroValues><CompilerOptions><Target><Filename Value="Trndi"/></Target>' +
    '<CodeGeneration><TargetOS Value="linux"/><TargetCPU Value="x86_64"/>' +
    '<SmartLinkUnit Value="True"/><Optimizations><OptimizationLevel Value="3"/></Optimizations>' +
    '</CodeGeneration><Linking><Debugging><GenerateDebugInfo Value="False"/>' +
    '<StripSymbols Value="True"/></Debugging></Linking></CompilerOptions></Item></BuildModes>' +
    '<RequiredPackages><Item><PackageName Value="atsynedit_package"/>' +
    '<MinVersion Major="2" Minor="4" Valid="True"/></Item>' +
    '<Item><PackageName Value="LCL"/></Item><Item><PackageName Value="mypkg"/></Item>' +
    '<Item><PackageName Value="ghostpkg"/></Item></RequiredPackages>' +
    '<Units><Unit><Filename Value="Trndi.lpr"/></Unit><Unit><Filename Value="a.pp"/></Unit></Units>' +
    '</ProjectOptions><CompilerOptions><Target><Filename Value="Trndi"/></Target>' +
    '<CodeGeneration><Optimizations><OptimizationLevel Value="2"/></Optimizations></CodeGeneration>' +
    '<Linking><Debugging><GenerateDebugInfo Value="False"/></Debugging></Linking>' +
    '</CompilerOptions></CONFIG>';

procedure TProjLazarusTest.TestReadProject;
var
  P: TLazProject;
begin
  P := ReadLazProject(TrndiLpi);
  AssertEquals('Trndi', P.Title);
  AssertEquals('23.0.0.248', P.Version);
  AssertEquals('InProjectDir', P.SessionStorage);
  AssertEquals(2, P.Units);
  AssertEquals(3, Length(P.Modes));
  AssertEquals('No Ext (Release)', P.Modes[0].Name);
  AssertTrue(P.Modes[0].IsDefault);
  AssertEquals('the project''s options', '2', P.Modes[0].Optimization);
  AssertEquals('off', P.Modes[0].Debug);
  AssertEquals('Extensions (Debug)', P.Modes[1].Name);
  AssertFalse(P.Modes[1].IsDefault);
  AssertEquals('0', P.Modes[1].Optimization);
  AssertEquals('DWARF 3', P.Modes[1].Debug);
  AssertEquals('-dEXT', P.Modes[1].CustomOptions);
  AssertEquals('lib\$(TargetCPU)-$(TargetOS)', P.Modes[1].UnitOutput);
  AssertEquals('gtk3', P.Modes[2].Widgetset);
  AssertEquals('linux', P.Modes[2].TargetOS);
  AssertEquals('x86_64', P.Modes[2].TargetCPU);
  AssertTrue(P.Modes[2].SmartLink);
  AssertTrue(P.Modes[2].Strip);
  AssertEquals(4, Length(P.Packages));
  AssertEquals('>= 2.4', P.Packages[0].Version);
  AssertEquals('not XML', 0, Length(ReadLazProject('<nope').Modes));
  { No modes listed: Lazarus's one. }
  AssertEquals('Default', ReadLazProject('<CONFIG><ProjectOptions/></CONFIG>').Modes[0].Name);
end;

procedure TProjLazarusTest.TestReadPackage;
var
  P: TLazPackage;
begin
  P := ReadLazPackage('<CONFIG><Package Version="5"><Name Value="atsynedit_package"/>' +
    '<Author Value="Alexey"/><Description Value="Multi-line editor"/>' +
    '<License Value="MPL 2.0"/><Version Major="2" Minor="28"/>' +
    '<RequiredPkgs Count="2"><Item1><PackageName Value="BGRABitmapPack"/></Item1>' +
    '<Item2><PackageName Value="LCL"/></Item2></RequiredPkgs></Package></CONFIG>');
  AssertEquals('atsynedit_package', P.Name);
  AssertEquals('2.28', P.Version);
  AssertEquals('Multi-line editor', P.Description);
  AssertEquals('BGRABitmapPack LCL', string.Join(' ', P.Requires));
  AssertEquals('11.6.9', ReadLazPackage('<CONFIG><Package><Version Major="11" Minor="6" ' +
    'Release="9"/></Package></CONFIG>').Version);
end;

procedure TProjLazarusTest.TestFindPackages;
var
  F: TStringArray;
begin
  Put('vendor/a/pkg/a_package.lpk', '<CONFIG/>');
  Put('lib/x86_64-linux/b.lpk', '<CONFIG/>');
  Put('backup/c.lpk', '<CONFIG/>');
  Put('.hidden/d.lpk', '<CONFIG/>');
  Put('one/two/three/four/five/six/e.lpk', '<CONFIG/>');
  Put('mine.lpk', '<CONFIG/>');
  F := FindLazPackages(FDir);
  AssertEquals('mine.lpk vendor/a/pkg/a_package.lpk', string.Join(' ', F));
  AssertTrue(IsLazarusPackage('lcl'));
  AssertFalse(IsLazarusPackage('atsynedit_package'));
end;

procedure TProjLazarusTest.TestCommandsPerMode;
var
  C: TGittanProjectCommands;
begin
  Put('Trndi.lpi', TrndiLpi);
  C := TGittanLazarusKind.Commands(FDir);
  AssertEquals(3, Length(C));
  AssertEquals('build:No Ext (Release)', C[0].Name);
  AssertTrue('quoted for the shell: ' + C[0].Command,
    Pos('--bm="No Ext (Release)" Trndi.lpi', C[0].Command) > 0);
  AssertEquals('build:GTK3', C[2].Name);
  AssertTrue(Pos('--bm=GTK3 Trndi.lpi', C[2].Command) > 0);
end;

type
  { A context with a submodule at vendor/a that moved since the tag. }
  TFakeContext = class(TGittanProjectContext)
  public
    function Submodules: TGittanSubmodules; override;
    function GitlinkAt(const APath, ARef: string): string; override;
    function Describe(const APath, ACommit: string): string; override;
    function ReadAt(const APath: string): string; override;
  end;

function TFakeContext.Submodules: TGittanSubmodules;
begin
  SetLength(Result, 1);
  Result[0] := Default(TGittanSubmodule);
  Result[0].Path := 'vendor/a';
  Result[0].Url := 'https://example.com/a.git';
  Result[0].Recorded := 'bbbbbbbbbb';
end;

function TFakeContext.GitlinkAt(const APath, ARef: string): string;
begin
  if (APath = 'vendor/a') and (ARef = 'v1') then
    Result := 'aaaaaaaaaa'
  else
    Result := '';
end;

function TFakeContext.Describe(const APath, ACommit: string): string;
begin
  if ACommit = 'aaaaaaaaaa' then
    Result := '2.0'
  else
    Result := '2.1';
end;

function TFakeContext.ReadAt(const APath: string): string;
begin
  { At the tag the project required LCL and a package since dropped. }
  Result := '<CONFIG><ProjectOptions><RequiredPackages><Item><PackageName Value="LCL"/></Item>' +
    '<Item><PackageName Value="atsynedit_package"/></Item>' +
    '<Item><PackageName Value="oldpkg"/></Item></RequiredPackages></ProjectOptions></CONFIG>';
end;

procedure TProjLazarusTest.TestSection;
var
  C: TFakeContext;
  Tracked: TStringList;
  Sec: TGittanProjectSection;
  Modes, Pkgs, Checks: TGittanProjectBlock;
  i: integer;
begin
  Put('Trndi.lpi', TrndiLpi);
  Put('vendor/a/atsynedit/atsynedit_package.lpk', '<CONFIG><Package><Name Value="atsynedit_package"/>' +
    '<Description Value="Editor"/><Version Major="2" Minor="28"/></Package></CONFIG>');
  Put('src/mypkg.lpk', '<CONFIG><Package><Version Major="1"/></Package></CONFIG>');
  Tracked := TStringList.Create;
  try
    Tracked.Add('Trndi.lps');
    C := TFakeContext.Create(FDir, 'v1', Tracked);
  finally
    Tracked.Free;
  end;
  try
    Sec := TGittanLazarusKind.Section(C, 'Trndi.lpi');
  finally
    C.Free;
  end;
  AssertEquals('Trndi.lpi · 23.0.0.248 · 3 build modes · 4 packages', Sec.Detail);
  { mypkg and ghostpkg added, the version of atsynedit asked for, oldpkg
    removed, and the submodule moved. }
  AssertEquals('5 changed since v1', Sec.State);
  for i := 0 to High(Sec.Blocks) do
    if Sec.Blocks[i].Title = 'Build modes' then
      Modes := Sec.Blocks[i]
    else if Sec.Blocks[i].Title = 'Packages' then
      Pkgs := Sec.Blocks[i]
    else if Sec.Blocks[i].Kind = pbChecks then
      Checks := Sec.Blocks[i];
  AssertEquals(3, Length(Modes.Rows));
  AssertEquals('No Ext (Release) · default', Modes.Rows[0].Cells[0].Text);
  AssertEquals('-O2', Modes.Rows[0].Cells[3].Text);
  AssertEquals('x86_64-linux · gtk3', Modes.Rows[2].Cells[2].Text);
  AssertEquals('-O3 · smart link', Modes.Rows[2].Cells[3].Text);
  AssertEquals('off · stripped', Modes.Rows[2].Cells[4].Text);
  AssertTrue(Modes.Rows[1].Cells[5].Style = psButton);
  AssertEquals('build:Extensions (Debug)', Modes.Rows[1].Cells[5].CommandName);
  AssertEquals(5, Length(Pkgs.Rows));
  { atsynedit: in the submodule, its version, the move. }
  AssertEquals('vendor/a @ 2.1', Pkgs.Rows[0].Cells[2].Text);
  AssertEquals('2.28', Pkgs.Rows[0].Cells[3].Text);
  AssertEquals('Editor', Pkgs.Rows[0].Cells[0].Hint);
  AssertEquals('the min version wins over the move: it is the dependency''s own change',
    'any → >= 2.4', Pkgs.Rows[0].Cells[4].Text);
  AssertEquals('Lazarus', Pkgs.Rows[1].Cells[2].Text);
  AssertEquals('src/mypkg.lpk', Pkgs.Rows[2].Cells[2].Text);
  AssertEquals('added', Pkgs.Rows[2].Cells[4].Text);
  AssertEquals('not found', Pkgs.Rows[3].Cells[2].Text);
  AssertTrue(Pkgs.Rows[3].Cells[2].Style = psWarn);
  AssertEquals('oldpkg', Pkgs.Rows[4].Cells[0].Text);
  AssertEquals('removed', Pkgs.Rows[4].Cells[4].Text);
  { The .lps tracked and ghostpkg found nowhere. }
  AssertEquals(2, Length(Checks.Checks));
  AssertEquals('*.lps', Checks.Checks[0].IgnorePattern);
  AssertTrue(Pos('ghostpkg', Checks.Checks[1].Text) > 0);
end;

procedure TProjLazarusTest.TestSectionMove;
var
  C: TFakeContext;
  Sec: TGittanProjectSection;
  i: integer;
begin
  { The same packages as at the tag: the move alone is the change. }
  Put('a.lpi', '<CONFIG><ProjectOptions><RequiredPackages><Item><PackageName Value="LCL"/></Item>' +
    '<Item><PackageName Value="atsynedit_package"/></Item>' +
    '<Item><PackageName Value="oldpkg"/></Item></RequiredPackages></ProjectOptions></CONFIG>');
  Put('vendor/a/atsynedit_package.lpk', '<CONFIG/>');
  Put('oldpkg.lpk', '<CONFIG/>');
  C := TFakeContext.Create(FDir, 'v1', nil);
  try
    Sec := TGittanLazarusKind.Section(C, 'a.lpi');
  finally
    C.Free;
  end;
  AssertEquals('1 changed since v1', Sec.State);
  for i := 0 to High(Sec.Blocks) do
    if Sec.Blocks[i].Title = 'Packages' then
    begin
      AssertEquals('2.0 → 2.1', Sec.Blocks[i].Rows[1].Cells[4].Text);
      AssertTrue(Sec.Blocks[i].Rows[1].Cells[4].Style = psLink);
    end;
end;

initialization
  RegisterTest(TProjLazarusTest);

end.
