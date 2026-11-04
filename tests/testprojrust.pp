unit testprojrust;

{** Tests of gittan.proj.rust: its parsers as functions of the text, and its
  section of the Project page built in a temporary folder. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.manifest, gittan.project,
  gittan.proj.rust, testhelpers;

type
  TProjRustTest = class(TTestCase)
  private
    FDir: string;
    procedure Put(const ARel, AText: string);
    function Names(const ADeps: TGittanDependencies): string;
    function Find(const ADeps: TGittanDependencies; const AName: string): TGittanDependency;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCargo;
    procedure TestCargoTables;
    procedure TestCargoLock;
    procedure TestCargoInfo;
    procedure TestRustSection;
    procedure TestRustNoLock;
  end;

implementation

const
  LE = LineEnding;

procedure TProjRustTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-projrust-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
end;

procedure TProjRustTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TProjRustTest.Put(const ARel, AText: string);
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

function TProjRustTest.Names(const ADeps: TGittanDependencies): string;
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

function TProjRustTest.Find(const ADeps: TGittanDependencies;
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

procedure TProjRustTest.TestCargo;
var
  D: TGittanDependencies;
begin
  D := ParseCargoDependencies('[package]' + LE + 'name = "x"' + LE + 'version = "0.3.1"' + LE +
    '[dependencies]' + LE + 'serde = "1.0"' + LE +
    'tokio = { version = "1", features = ["full"] }' + LE + 'local = { path = "../local" }' + LE +
    'shared = { workspace = true }' + LE + '[dev-dependencies]' + LE + 'criterion = "0.5"' + LE +
    '[build-dependencies]' + LE + 'cc = "1"' + LE);
  AssertEquals('serde tokio local shared criterion cc', Names(D));
  AssertEquals('1.0', Find(D, 'serde').Version);
  AssertEquals('1', Find(D, 'tokio').Version);
  AssertEquals('', Find(D, 'local').Version);
  AssertEquals('workspace', Find(D, 'shared').Version);
  AssertEquals('dev', Find(D, 'criterion').Group);
  AssertEquals('build', Find(D, 'cc').Group);
  AssertEquals('', Find(D, 'serde').Group);
  AssertEquals('0.3.1', CargoVersion('[package]' + LE + 'version = "0.3.1"'));
  AssertEquals('', CargoVersion('[dependencies]' + LE + 'version = "9"'));
end;

procedure TProjRustTest.TestCargoTables;
var
  D: TGittanDependencies;
begin
  D := ParseCargoDependencies('[dependencies.serde]' + LE + 'version = "1.0"' + LE +
    'features = ["derive"]' + LE + '[target.''cfg(unix)''.dependencies]' + LE + 'libc = "0.2"' +
    LE + '[workspace.dependencies]' + LE + 'anyhow = "1"' + LE + '[dependencies.mine]' + LE +
    'path = "mine"' + LE);
  AssertEquals('serde libc anyhow mine', Names(D));
  AssertEquals('1.0', Find(D, 'serde').Version);
  AssertEquals('0.2', Find(D, 'libc').Version);
  AssertEquals('', Find(D, 'mine').Version);
  { A version after path or git still counts. }
  D := ParseCargoDependencies('[dependencies.both]' + LE + 'path = "../both"' + LE +
    'version = "0.3"' + LE + '[dev-dependencies.g]' + LE + 'git = "https://x/g"' + LE +
    'version = "1.2"' + LE);
  AssertEquals('both g', Names(D));
  AssertEquals('0.3', Find(D, 'both').Version);
  AssertEquals('1.2', Find(D, 'g').Version);
  AssertEquals('dev', Find(D, 'g').Group);
end;

procedure TProjRustTest.TestCargoLock;
var
  D: TGittanDependencies;
begin
  D := ParseCargoLock('version = 3' + LE + LE + '[[package]]' + LE + 'name = "serde"' + LE +
    'version = "1.0.210"' + LE + 'source = "registry"' + LE + LE + '[[package]]' + LE +
    'name = "tokio"' + LE + 'version = "1.40.0"' + LE);
  AssertEquals('serde tokio', Names(D));
  AssertEquals('1.0.210', Find(D, 'serde').Resolved);
  AssertEquals('', Find(D, 'serde').Version);
end;

procedure TProjRustTest.TestCargoInfo;
var
  I: TCargoInfo;
begin
  I := ParseCargoInfo('[package]' + LE + 'name = "x"' + LE + 'edition = "2021"' + LE +
    'rust-version = "1.75"' + LE + 'repository = "https://github.com/a/x"' + LE +
    '[workspace]' + LE + 'members = ["crates/a", "crates/b"]' + LE + '[features]' + LE +
    'default = ["std"]' + LE + 'std = []' + LE + 'serde = ["dep:serde", "std"]' + LE +
    '[[bin]]' + LE + 'name = "one"' + LE + '[[bin]]' + LE + 'name = "two"' + LE);
  AssertEquals('x', I.Name);
  AssertEquals('2021', I.Edition);
  AssertEquals('1.75', I.RustVersion);
  AssertEquals('https://github.com/a/x', I.Repository);
  AssertEquals('crates/a crates/b', string.Join(' ', I.Members));
  AssertEquals(3, Length(I.Features));
  AssertEquals('serde', I.Features[2].Name);
  AssertEquals('dep:serde std', string.Join(' ', I.Features[2].Enables));
  AssertEquals('one two', string.Join(' ', I.Binaries));
end;

procedure TProjRustTest.TestRustSection;
var
  C: TGittanProjectContext;
  Sec: TGittanProjectSection;
  i: integer;
  Feats, Bins: integer;
begin
  Put('Cargo.toml', '[package]' + LE + 'name = "x"' + LE + 'version = "0.2.0"' + LE +
    'edition = "2021"' + LE + '[dependencies]' + LE + 'serde = "1"' + LE + '[features]' + LE +
    'default = ["std"]' + LE + 'std = []' + LE + 'fast = []' + LE + '[[bin]]' + LE +
    'name = "tool"' + LE);
  C := TGittanProjectContext.Create(FDir, '', nil);
  try
    Sec := TGittanRustKind.Section(C, 'Cargo.toml');
  finally
    C.Free;
  end;
  AssertEquals('Cargo.toml · 0.2.0 · 1 dependency', Sec.Detail);
  Feats := -1;
  Bins := -1;
  for i := 0 to High(Sec.Blocks) do
    if Sec.Blocks[i].Title = 'Features' then
      Feats := i
    else if Sec.Blocks[i].Title = 'Binaries' then
      Bins := i;
  AssertTrue(Sec.Blocks[0].Kind = pbFacts);
  AssertTrue('features', Feats > 0);
  AssertEquals('default is not a row', 2, Length(Sec.Blocks[Feats].Rows));
  AssertEquals('on by default', Sec.Blocks[Feats].Rows[0].Cells[2].Text);
  AssertEquals('', Sec.Blocks[Feats].Rows[1].Cells[2].Text);
  AssertTrue('binaries', Bins > 0);
  AssertTrue(Sec.Blocks[Bins].Rows[0].Cells[1].Style = psButton);
  AssertEquals('cargo run --bin tool', Sec.Blocks[Bins].Rows[0].Cells[1].Command);
  AssertEquals('run:tool', Sec.Blocks[Bins].Rows[0].Cells[1].CommandName);
end;

procedure TProjRustTest.TestRustNoLock;
var
  C: TGittanProjectContext;
  Checks: TGittanProjectChecks;
begin
  Put('Cargo.toml', '[package]' + LE + 'name = "x"' + LE);
  Put('src/main.rs', '');
  C := TGittanProjectContext.Create(FDir, '', nil);
  try
    Checks := TGittanRustKind.Checks(C);
    AssertEquals('a binary with no Cargo.lock at all', 1, Length(Checks));
    AssertTrue(Pos('No Cargo.lock', Checks[0].Text) = 1);
    AssertEquals('', Checks[0].Path);
    DeleteFile(IncludeTrailingPathDelimiter(FDir) + 'src' + PathDelim + 'main.rs');
    Put('src/lib.rs', '');
    AssertEquals('a library needs none', 0, Length(TGittanRustKind.Checks(C)));
  finally
    C.Free;
  end;
end;

initialization
  RegisterTest(TProjRustTest);

end.
