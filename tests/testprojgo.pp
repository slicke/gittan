unit testprojgo;

{** Tests of gittan.proj.go: its parsers as functions of the text, and its
  section of the Project page built in a temporary folder. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.manifest, gittan.project,
  gittan.proj.go, testhelpers;

type
  TProjGoTest = class(TTestCase)
  private
    FDir: string;
    procedure Put(const ARel, AText: string);
    function Names(const ADeps: TGittanDependencies): string;
    function Find(const ADeps: TGittanDependencies; const AName: string): TGittanDependency;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestGoMod;
    procedure TestGoModInfo;
    procedure TestGoSection;
    procedure TestGoRunTests;
    procedure TestGoAbsoluteReplace;
  end;

implementation

const
  LE = LineEnding;

procedure TProjGoTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-projgo-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
end;

procedure TProjGoTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TProjGoTest.Put(const ARel, AText: string);
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

function TProjGoTest.Names(const ADeps: TGittanDependencies): string;
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

function TProjGoTest.Find(const ADeps: TGittanDependencies;
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

procedure TProjGoTest.TestGoMod;
var
  D: TGittanDependencies;
begin
  D := ParseGoMod('module example.com/x' + LE + LE + 'go 1.22' + LE + LE +
    'require github.com/one/one v1.2.3' + LE + LE + 'require (' + LE +
    #9'github.com/two/two v2.0.0 // indirect' + LE + #9'golang.org/x/text v0.14.0' + LE +
    ')' + LE + 'replace github.com/two/two => ../two' + LE);
  AssertEquals('github.com/one/one github.com/two/two golang.org/x/text', Names(D));
  AssertEquals('v1.2.3', Find(D, 'github.com/one/one').Version);
  AssertEquals('v1.2.3', Find(D, 'github.com/one/one').Resolved);
  AssertEquals('indirect', Find(D, 'github.com/two/two').Group);
  AssertEquals('', Find(D, 'golang.org/x/text').Group);
end;

procedure TProjGoTest.TestGoModInfo;
var
  I: TGoModInfo;
begin
  I := ParseGoModInfo('module example.com/x' + LE + LE + 'go 1.22.1' + LE + 'toolchain go1.23.0' +
    LE + 'replace github.com/a/a v1.0.0 => ../a' + LE + 'replace (' + LE +
    #9'github.com/b/b => github.com/fork/b v1.2.0 // a fork' + LE + ')' + LE);
  AssertEquals('example.com/x', I.Module);
  AssertEquals('1.22.1', I.Go);
  AssertEquals('go1.23.0', I.Toolchain);
  AssertEquals(2, Length(I.Replaces));
  AssertEquals('github.com/a/a v1.0.0', I.Replaces[0].Old);
  AssertEquals('../a', I.Replaces[0].New);
  AssertEquals('github.com/fork/b v1.2.0', I.Replaces[1].New);
end;

procedure TProjGoTest.TestGoSection;
var
  C: TGittanProjectContext;
  Sec: TGittanProjectSection;
begin
  Put('go.mod', 'module example.com/x' + LE + 'go 1.22' + LE + 'require a.b/c v1.0.0' + LE +
    'replace a.b/c => ./vendor-c' + LE);
  C := TGittanProjectContext.Create(FDir, '', nil);
  try
    Sec := TGittanGoKind.Section(C, 'go.mod');
  finally
    C.Free;
  end;
  AssertEquals('Go', Sec.Name);
  AssertEquals('facts, dependencies, replaced, checks', 4, Length(Sec.Blocks));
  AssertTrue(Sec.Blocks[0].Kind = pbFacts);
  AssertEquals('Module', Sec.Blocks[0].Rows[0].Cells[0].Text);
  AssertEquals('example.com/x', Sec.Blocks[0].Rows[0].Cells[1].Text);
  AssertEquals('https://pkg.go.dev/example.com/x', Sec.Blocks[0].Rows[0].Cells[1].Url);
  AssertTrue(Sec.Blocks[1].Kind = pbTable);
  AssertEquals('Replaced', Sec.Blocks[2].Title);
  AssertTrue('a path is a warning', Sec.Blocks[2].Rows[0].Cells[2].Style = psWarn);
  AssertTrue(Sec.Blocks[3].Kind = pbChecks);
  { No go.sum, and the folder of the replace is not there. }
  AssertEquals(2, Length(Sec.Blocks[3].Checks));
end;

procedure TProjGoTest.TestGoRunTests;
var
  C: TGittanProjectCommands;
  i: integer;
  HasRun: boolean;
begin
  Put('go.mod', 'module x' + LE);
  Put('lib.go', 'package x' + LE);
  Put('main_test.go', 'package main' + LE);
  C := TGittanGoKind.Commands(FDir);
  HasRun := False;
  for i := 0 to High(C) do
    if C[i].Name = 'run' then
      HasRun := True;
  AssertFalse('a _test.go is not what go run builds', HasRun);
  Put('main.go', 'package main' + LE);
  C := TGittanGoKind.Commands(FDir);
  for i := 0 to High(C) do
    if C[i].Name = 'run' then
      HasRun := True;
  AssertTrue(HasRun);
end;

procedure TProjGoTest.TestGoAbsoluteReplace;
var
  Ctx: TGittanProjectContext;
  Abs: string;
begin
  ForceDirectories(IncludeTrailingPathDelimiter(FDir) + 'there');
  Abs := StringReplace(IncludeTrailingPathDelimiter(FDir) + 'there', '\', '/', [rfReplaceAll]);
  Put('go.mod', 'module x' + LE + 'replace a.b/c => ' + Abs + LE +
    'replace d.e/f => ' + Abs + '-gone' + LE);
  Put('go.sum', '');
  Ctx := TGittanProjectContext.Create(FDir, '', nil);
  try
    AssertEquals('the absolute path is read as it is, the missing one warned of', 1,
      Length(TGittanGoKind.Checks(Ctx)));
    AssertTrue(Pos('-gone', TGittanGoKind.Checks(Ctx)[0].Text) > 0);
  finally
    Ctx.Free;
  end;
end;

initialization
  RegisterTest(TProjGoTest);

end.
