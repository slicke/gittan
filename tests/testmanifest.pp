unit testmanifest;

{** Tests of gittan.manifest: the TOML reader and the [[package]] lock
  the drivers share. Each driver's parsers are tested in
  tests/testproj<kind>.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.manifest, fpjson;

type
  TManifestTest = class(TTestCase)
  published
    procedure TestTomlTables;
    procedure TestTomlMultiLine;
    procedure TestTomlValues;
    procedure TestTomlLock;
    procedure TestJsonObject;
  end;

implementation

const
  LE = LineEnding;

procedure TManifestTest.TestTomlTables;
var
  E: TGittanTomlEntries;
begin
  E := ReadToml('top = 1' + LE + '# comment' + LE + '[package]' + LE + 'name = "x" # trailing' +
    LE + '[[bin]]' + LE + 'name = "a"' + LE + '[[bin]]' + LE + 'name = "b"' + LE +
    '[tool."my.thing"]' + LE + '"quoted key" = ''s''' + LE);
  AssertEquals(5, Length(E));
  AssertEquals('', E[0].Table);
  AssertEquals('top', E[0].Key);
  AssertEquals(-1, E[0].Index);
  AssertEquals('package', E[1].Table);
  AssertEquals('"x"', E[1].Value);
  AssertEquals('bin', E[2].Table);
  AssertEquals(0, E[2].Index);
  AssertEquals(1, E[3].Index);
  AssertEquals('tool."my.thing"', E[4].Table);
  AssertEquals('quoted key', E[4].Key);
  AssertEquals('s', TomlString(E[4].Value));
end;

procedure TManifestTest.TestTomlMultiLine;
var
  E: TGittanTomlEntries;
begin
  E := ReadToml('[project]' + LE + 'dependencies = [' + LE + '  "a>=1", # one' + LE +
    '  "b",' + LE + ']' + LE + 'next = 2' + LE);
  AssertEquals(2, Length(E));
  AssertEquals('a>=1 b', string.Join(' ', TomlArrayStrings(E[0].Value)));
  AssertEquals('next', E[1].Key);
end;

procedure TManifestTest.TestTomlValues;
begin
  AssertEquals('1.0', TomlString('"1.0"'));
  AssertEquals('', TomlString('{ version = "1" }'));
  AssertEquals('"1"', TomlInlineValue('{ version = "1", features = ["a", "b"] }', 'version'));
  AssertEquals('["a", "b"]', TomlInlineValue('{ version = "1", features = ["a", "b"] }',
    'features'));
  AssertEquals('', TomlInlineValue('"1"', 'version'));
  AssertEquals(2, Length(TomlArrayStrings('["a", ''b'']')));
  AssertEquals(0, Length(TomlArrayStrings('"a"')));
end;

procedure TManifestTest.TestTomlLock;
var
  D: TGittanDependencies;
begin
  D := ParseTomlLock('[[package]]' + LE + 'name = "a"' + LE + 'version = "1.0"' + LE +
    '[[package]]' + LE + 'name = "a"' + LE + 'version = "2.0"' + LE + '[[package]]' + LE +
    'name = "b"' + LE + 'version = "3"' + LE + '[package.metadata]' + LE + 'x = 1' + LE);
  AssertEquals('a twice keeps the first', 2, Length(D));
  AssertEquals('1.0', D[0].Resolved);
  AssertEquals('b', D[1].Name);
end;

procedure TManifestTest.TestJsonObject;
var
  O: TJSONObject;
begin
  AssertNull(ParseJsonObject('[1]'));
  AssertNull(ParseJsonObject('nope'));
  AssertNull(ParseJsonObject(''));
  O := ParseJsonObject('{"a": 1}');
  try
    AssertEquals(1, O.Count);
  finally
    O.Free;
  end;
end;

initialization
  RegisterTest(TManifestTest);

end.
