unit testtextfile;

{** Tests of gittan.textfile: reading a file byte for byte, splitting at
  LF, walking lines and undoing escapes. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.textfile;

type
  TTextFileTest = class(TTestCase)
  published
    procedure TestReadFileBytes;
    procedure TestSplitLf;
    procedure TestBareLine;
    procedure TestNextLine;
    procedure TestUnescapeC;
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
