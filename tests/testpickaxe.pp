unit testpickaxe;

{** Tests of gittan.pickaxe: the option a "change:" value becomes, and
  the commits found in a repository made for the test (an added and a
  removed line found by text, a moved one only by a regular expression,
  the case ignored unless a capital letter is typed, two changes kept
  together, and git's reason for a regular expression it cannot read). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.git, gittan.pickaxe, testhelpers;

type
  TPickaxeTest = class(TTestCase)
  private
    FDir: string;
    procedure Git(const AArgs: array of string);
    function Head(const ARev: string): string;
    procedure WriteFile(const AText: string);
    procedure Commit(const AMessage: string);
    function Cancel: boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestOption;
    procedure TestChangeCommits;
  end;

implementation

function TPickaxeTest.Cancel: boolean;
begin
  Result := True;
end;

procedure TPickaxeTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-pickaxe-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
end;

procedure TPickaxeTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TPickaxeTest.Git(const AArgs: array of string);
var
  Output, Err: string;
begin
  if not RunGitIn(FDir, AArgs, Output, Err) then
    Fail('git ' + AArgs[0] + ' failed: ' + Err);
end;

function TPickaxeTest.Head(const ARev: string): string;
var
  Err: string;
begin
  if not RunGitIn(FDir, ['rev-parse', ARev], Result, Err) then
    Fail('rev-parse failed: ' + Err);
  Result := Trim(Result);
end;

procedure TPickaxeTest.WriteFile(const AText: string);
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    Lines.SaveToFile(IncludeTrailingPathDelimiter(FDir) + 'a.txt');
  finally
    Lines.Free;
  end;
end;

procedure TPickaxeTest.Commit(const AMessage: string);
begin
  Git(['add', '-A']);
  Git(['commit', '-q', '-m', AMessage]);
end;

procedure TPickaxeTest.TestOption;
var
  Option: string;
  IgnoreCase: boolean;
begin
  AssertTrue(PickaxeOption('parse', Option, IgnoreCase));
  AssertEquals('-Sparse', Option);
  AssertTrue('no capital', IgnoreCase);
  AssertTrue(PickaxeOption('ParseList', Option, IgnoreCase));
  AssertEquals('-SParseList', Option);
  AssertFalse('a capital', IgnoreCase);
  AssertTrue(PickaxeOption('/cmd\+p/', Option, IgnoreCase));
  AssertEquals('-Gcmd\+p', Option);
  AssertTrue(IgnoreCase);
  AssertTrue(PickaxeOption('/a\Sb/', Option, IgnoreCase));
  AssertTrue('an escape is no capital', IgnoreCase);
  AssertTrue(PickaxeOption('/Ab/', Option, IgnoreCase));
  AssertFalse(IgnoreCase);
  { A slash on one side only is text. }
  AssertTrue(PickaxeOption('/usr', Option, IgnoreCase));
  AssertEquals('-S/usr', Option);
  AssertTrue(PickaxeOption('/', Option, IgnoreCase));
  AssertEquals('-S/', Option);
  AssertFalse(PickaxeOption('', Option, IgnoreCase));
  AssertFalse(PickaxeOption('//', Option, IgnoreCase));
end;

procedure TPickaxeTest.TestChangeCommits;
var
  Hashes: TStringList;
  Error: string;
  Added, Moved, Removed: string;
begin
  Hashes := TStringList.Create;
  try
    Git(['init', '-q']);
    WriteFile('alpha'#10'beta'#10);
    Commit('start');
    WriteFile('alpha'#10'beta'#10'ParseList(x)'#10);
    Commit('added');
    Added := Head('HEAD');
    WriteFile('ParseList(x)'#10'alpha'#10'beta'#10);
    Commit('moved');
    Moved := Head('HEAD');
    WriteFile('alpha'#10'beta'#10);
    Commit('removed');
    Removed := Head('HEAD');

    AssertTrue(ChangeCommits(FDir, ['ParseList'], Hashes, 100, nil, Error));
    AssertEquals('the move is not counted', 2, Hashes.Count);
    AssertEquals(Removed, Hashes[0]);
    AssertEquals(Added, Hashes[1]);
    AssertTrue(ChangeCommits(FDir, ['parselist'], Hashes, 100, nil, Error));
    AssertEquals('the case ignored', 2, Hashes.Count);
    AssertTrue(ChangeCommits(FDir, ['PARSELIST'], Hashes, 100, nil, Error));
    AssertEquals('a capital keeps the case', 0, Hashes.Count);
    AssertTrue(ChangeCommits(FDir, ['/Parse[A-Z]/'], Hashes, 100, nil, Error));
    AssertEquals('a regular expression sees the move', 3, Hashes.Count);
    AssertEquals(Moved, Hashes[1]);
    AssertTrue(ChangeCommits(FDir, ['/parse/', 'ParseList'], Hashes, 100, nil, Error));
    AssertEquals('both changes', 2, Hashes.Count);
    AssertEquals(Removed, Hashes[0]);
    AssertEquals(Added, Hashes[1]);
    AssertTrue(ChangeCommits(FDir, ['/parse/', 'alpha'], Hashes, 100, nil, Error));
    AssertEquals('one change but not the other', 0, Hashes.Count);
    AssertTrue(ChangeCommits(FDir, ['', 'ParseList'], Hashes, 100, nil, Error));
    AssertEquals('an empty change is left out', 2, Hashes.Count);
    AssertTrue(ChangeCommits(FDir, ['ParseList'], Hashes, 1, nil, Error));
    AssertEquals('at most AMax', 1, Hashes.Count);
    AssertFalse('cancelled', ChangeCommits(FDir, ['ParseList'], Hashes, 100, @Cancel, Error));

    AssertFalse(ChangeCommits(FDir, ['/a(/'], Hashes, 100, nil, Error));
    AssertEquals(0, Hashes.Count);
    AssertTrue('git''s reason: ' + Error, Pos('invalid regex', Error) = 1);
  finally
    Hashes.Free;
  end;
end;

initialization
  RegisterTest(TPickaxeTest);
end.
