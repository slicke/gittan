unit testtextfile;

{** Tests of gittan.textfile: reading a file byte for byte, splitting at
  LF, walking lines and undoing escapes. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, {$IFDEF UNIX}BaseUnix, {$ENDIF}fpcunit, testregistry, testhelpers,
  gittan.textfile;

type
  TTextFileTest = class(TTestCase)
  published
    procedure TestReadFileBytes;
    procedure TestSplitLf;
    procedure TestBareLine;
    procedure TestNextLine;
    procedure TestUnescapeC;
    procedure TestJsonTooDeep;
    procedure TestUtf8Clean;
    procedure TestTomlTooDeep;
    procedure TestWriteThroughLink;
  end;

implementation

procedure TTextFileTest.TestReadFileBytes;
var
  Path: string;
  F: TFileStream;
  Data: RawByteString;
begin
  Path := GetTempFileName;
  Data := 'a'#13#10'b'#0'c'#$C3#$A5;
  F := TFileStream.Create(Path, fmCreate);
  try
    F.WriteBuffer(Data[1], Length(Data));
  finally
    F.Free;
  end;
  try
    AssertEquals(Data, ReadFileBytes(Path));
    F := TFileStream.Create(Path, fmCreate);
    F.Free;
    AssertEquals('', ReadFileBytes(Path));
  finally
    DeleteFile(Path);
  end;
end;

{ A symbolic link stays a link, relative or through another one, and
  the file it leads to gets the text. }
procedure TTextFileTest.TestWriteThroughLink;
{$IFDEF UNIX}
var
  Dir, Target: string;
  Link: RawByteString;
begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-textfile-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(Dir + '/real');
  try
    Target := Dir + '/real/settings.json';
    AssertTrue(WriteFileReplacing(Target, 'old'));
    AssertEquals(0, fpSymlink('real/settings.json', PChar(Dir + '/link')));
    AssertEquals(0, fpSymlink('link', PChar(Dir + '/link2')));
    AssertTrue(WriteFileReplacing(Dir + '/link2', 'new'));
    AssertEquals('new', string(ReadFileBytes(Target)));
    AssertTrue('still a link', FileGetSymLinkTarget(Dir + '/link2', Link));
    AssertEquals('link', string(Link));
    AssertTrue(FileGetSymLinkTarget(Dir + '/link', Link));
    { One that leads nowhere yet gets its file. }
    AssertEquals(0, fpSymlink('real/later.json', PChar(Dir + '/dangling')));
    AssertTrue(WriteFileReplacing(Dir + '/dangling', 'made'));
    AssertEquals('made', string(ReadFileBytes(Dir + '/real/later.json')));
  finally
    RemoveTree(Dir);
  end;
end;
{$ELSE}
begin
end;
{$ENDIF}

procedure TTextFileTest.TestSplitLf;
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    SplitLf('one'#13#10'two'#10#10'three', Lines);
    AssertEquals(4, Lines.Count);
    AssertEquals('one'#13, Lines[0]);
    AssertEquals('two', Lines[1]);
    AssertEquals('', Lines[2]);
    AssertEquals('three', Lines[3]);
    SplitLf('last'#10, Lines);
    AssertEquals(1, Lines.Count);
    SplitLf('', Lines);
    AssertEquals(0, Lines.Count);
  finally
    Lines.Free;
  end;
end;

procedure TTextFileTest.TestBareLine;
begin
  AssertEquals('a', BareLine('a'#13));
  AssertEquals('a', BareLine('a'));
  AssertEquals('', BareLine(''));
  AssertEquals(#13'a', BareLine(#13'a'));
end;

procedure TTextFileTest.TestNextLine;
var
  Start: integer;
  Line: string;
begin
  Start := 1;
  AssertTrue(NextLine('a'#10#10'b', Start, Line));
  AssertEquals('a', Line);
  AssertTrue(NextLine('a'#10#10'b', Start, Line));
  AssertEquals('', Line);
  AssertTrue(NextLine('a'#10#10'b', Start, Line));
  AssertEquals('b', Line);
  AssertFalse(NextLine('a'#10#10'b', Start, Line));
  Start := 1;
  AssertTrue(NextLine('x'#10, Start, Line));
  AssertEquals('x', Line);
  AssertFalse(NextLine('x'#10, Start, Line));
end;

{ Valid UTF-8 comes through as it is; a CP1252 byte, a cut character,
  an overlong form and a surrogate each become U+FFFD. }
procedure TTextFileTest.TestUtf8Clean;
const
  Bad = #$EF#$BF#$BD;
begin
  AssertEquals('', Utf8Clean(''));
  AssertEquals('ändrad ✓ '#$F0#$9F#$98#$80, Utf8Clean('ändrad ✓ '#$F0#$9F#$98#$80));
  AssertEquals('caf' + Bad + ' x', Utf8Clean('caf'#$E9' x'));
  AssertEquals('cut ' + Bad + Bad, Utf8Clean('cut '#$E2#$9C));
  AssertEquals(Bad + Bad + '/', Utf8Clean(#$C0#$AF'/'));
  AssertEquals(Bad + Bad + Bad, Utf8Clean(#$ED#$A0#$80));
  AssertEquals(Bad + 'a', Utf8Clean(#$FF'a'));
end;

procedure TTextFileTest.TestJsonTooDeep;
begin
  AssertFalse(JsonTooDeep('{"a": [1, {"b": [2]}]}'));
  AssertFalse('at the limit', JsonTooDeep(StringOfChar('[', MaxNesting) +
    StringOfChar(']', MaxNesting)));
  AssertTrue('one deeper', JsonTooDeep(StringOfChar('[', MaxNesting + 1)));
  AssertTrue(JsonTooDeep(StringOfChar('[', 100000)));
  AssertFalse('brackets in a string', JsonTooDeep('["' + StringOfChar('[', 500) + '"]'));
  AssertTrue('an escaped quote does not end it',
    JsonTooDeep('["\"", ' + StringOfChar('[', 500)));
  AssertFalse('closers do not go below none', JsonTooDeep(StringOfChar(']', 500) + '[1]'));
end;

procedure TTextFileTest.TestTomlTooDeep;
var
  Deep: string;
begin
  Deep := StringOfChar('[', MaxNesting + 1);
  AssertFalse(TomlTooDeep('[a]'#10'x = [1, [2]]'#10'[[b]]'#10'y = {z = 1}'#10));
  AssertTrue(TomlTooDeep('x = ' + Deep));
  AssertFalse('in a basic string', TomlTooDeep('x = "' + Deep + '"'));
  AssertFalse('in a literal one', TomlTooDeep('x = ''' + Deep + ''''));
  AssertFalse('in a comment', TomlTooDeep('# ' + Deep));
  AssertFalse('in a multi-line string', TomlTooDeep('x = """'#10 + Deep + '"""'));
  AssertFalse('in a multi-line literal', TomlTooDeep('x = '''''''#10 + Deep + ''''''''));
  { What would hide the nesting if the scan took these for strings. }
  AssertTrue('a quote in a multi-line string',
    TomlTooDeep('x = """a"b"""'#10'y = ' + Deep));
  AssertTrue('quotes before the closing three', TomlTooDeep('x = """a""""'#10'y = ' + Deep));
  AssertTrue('a quote in a comment', TomlTooDeep('# "'#10'y = ' + Deep));
  AssertTrue('a string not closed ends at its line', TomlTooDeep('x = "a'#10'y = ' + Deep));
end;

procedure TTextFileTest.TestUnescapeC;
begin
  AssertEquals('a'#10'b'#9'c'#13'\', UnescapeC('a\nb\tc\r\\'));
  AssertEquals('"q"', UnescapeC('\"q\"'));
  AssertEquals(#7#8#12#11, UnescapeC('\a\b\f\v'));
  AssertEquals('end\', UnescapeC('end\'));
  AssertEquals('', UnescapeC(''));
end;

initialization
  RegisterTest(TTextFileTest);
end.
