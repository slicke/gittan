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
    procedure TestTomlEscapes;
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
  AssertEquals('a twice keeps both versions', 3, Length(D));
  AssertEquals('1.0', D[0].Resolved);
  AssertEquals('a', D[1].Name);
  AssertEquals('2.0', D[1].Resolved);
  AssertEquals('b', D[2].Name);
  D := nil;
  AddLocked(D, 'a', '1.0');
  AddLocked(D, 'a', '1.0');
  AssertEquals('the same version once', 1, Length(D));
end;

procedure TManifestTest.TestTomlEscapes;
var
  E: TGittanTomlEntries;
begin
  { An escaped quote does not end the string: the # after it is no
    comment, the bracket in it opens nothing, the comma splits
    nothing. }
  E := ReadToml('a = "x\" # y" # comment' + LE + 'b = ["p\"]", "q"]' + LE +
    'c = { k = "1\",2" }' + LE + 'd = ''lit\'' # done' + LE);
  AssertEquals(4, Length(E));
  AssertEquals('"x\" # y"', E[0].Value);
  AssertEquals('x" # y', TomlString(E[0].Value));
  AssertEquals('c', E[2].Key);
  AssertEquals('p"] q', string.Join(' ', TomlArrayStrings(E[1].Value)));
  AssertEquals('1",2', TomlString(TomlInlineValue(E[2].Value, 'k')));
  AssertEquals('a literal string has no escapes', 'lit\', TomlString(E[3].Value));
  AssertEquals('a\b', TomlString('"a\\b"'));
  AssertEquals('t' + #9 + 'n' + #10, TomlString('"t\tn\n"'));
  AssertEquals('é', TomlString('"\u00E9"'));
  AssertEquals('😀', TomlString('"\U0001F600"'));
  AssertEquals('unknown kept', '\q', TomlString('"\q"'));
  AssertEquals('a\\b', TomlString('''a\\b'''));
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
