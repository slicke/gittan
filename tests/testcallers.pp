unit testcallers;

{** Tests of gittan.callers: reading the uses of changed symbols out of
  what git grep printed, and the words for them. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.symbols, gittan.callers;

type
  TCallersTest = class(TTestCase)
  private
    FIdents: TStringList;
    function Grep(const ARows: array of string): string;
    function Symbol(const AName: string; ARow: integer): TGittanSymbol;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRowsAndColumns;
    procedure TestWholeWordsOnly;
    procedure TestTwoIdentsOnOneRow;
    procedure TestIgnoreCase;
    procedure TestSkipPaths;
    procedure TestDamagedOutput;
    procedure TestDefinitionRow;
    procedure TestEnclosingSymbol;
    procedure TestCounts;
    procedure TestDetails;
    procedure TestLexerIgnoresCase;
    procedure TestLexerIsProse;
  end;

implementation

procedure TCallersTest.SetUp;
begin
  FIdents := TStringList.Create;
  FIdents.Add('Parse');
  FIdents.Add('Status');
end;

procedure TCallersTest.TearDown;
begin
  FIdents.Free;
end;

{ Rows as "path:row:text", made into what git grep -z -n prints. }
function TCallersTest.Grep(const ARows: array of string): string;
var
  i, p, q: integer;
  S: string;
begin
  Result := '';
  for i := 0 to High(ARows) do
  begin
    S := ARows[i];
    p := Pos(':', S);
    q := Pos(':', S, p + 1);
    Result := Result + Copy(S, 1, p - 1) + #0 + Copy(S, p + 1, q - p - 1) + #0 +
      Copy(S, q + 1, MaxInt) + #10;
  end;
end;

function TCallersTest.Symbol(const AName: string; ARow: integer): TGittanSymbol;
begin
  Result := Default(TGittanSymbol);
  Result.Name := AName;
  Result.Row := ARow;
end;

procedure TCallersTest.TestRowsAndColumns;
var
  C: TGittanCallers;
begin
  C := ParseGrep(Grep(['a/b.pp:12:  Result := Parse(S);', 'c.pp:3:Status := 1;'#13]),
    FIdents, False, nil);
  AssertEquals(2, Length(C));
  AssertEquals('a/b.pp', C[0].Path);
  AssertEquals('row is 0-based', 11, C[0].Row);
  AssertEquals('byte column of the word', 12, C[0].Col);
  AssertEquals('  Result := Parse(S);', C[0].Line);
  AssertEquals(0, C[0].Ident);
  AssertEquals('c.pp', C[1].Path);
  AssertEquals(2, C[1].Row);
  AssertEquals(0, C[1].Col);
  AssertEquals('CR dropped', 'Status := 1;', C[1].Line);
  AssertEquals(1, C[1].Ident);
end;

procedure TCallersTest.TestWholeWordsOnly;
var
  C: TGittanCallers;
begin
  C := ParseGrep(Grep(['a.pp:1:Parser.Parse2(StatusBar)', 'a.pp:2:x.Parse']),
    FIdents, False, nil);
  AssertEquals(1, Length(C));
  AssertEquals(1, C[0].Row);
  AssertEquals(2, C[0].Col);
end;

{ One use per identifier on a row, in the order they stand, a repeated
  word once. }
procedure TCallersTest.TestTwoIdentsOnOneRow;
var
  C: TGittanCallers;
begin
  C := ParseGrep(Grep(['a.pp:5:Status := Parse(Status);']), FIdents, False, nil);
  AssertEquals(2, Length(C));
  AssertEquals(1, C[0].Ident);
  AssertEquals(0, C[0].Col);
  AssertEquals(0, C[1].Ident);
  AssertEquals(10, C[1].Col);
end;

procedure TCallersTest.TestIgnoreCase;
var
  C: TGittanCallers;
begin
  C := ParseGrep(Grep(['a.pp:1:PARSE(1)']), FIdents, False, nil);
  AssertEquals(0, Length(C));
  C := ParseGrep(Grep(['a.pp:1:PARSE(1)']), FIdents, True, nil);
  AssertEquals(1, Length(C));
  AssertEquals(0, C[0].Ident);
end;

procedure TCallersTest.TestSkipPaths;
var
  C: TGittanCallers;
  Skip: TStringList;
begin
  Skip := TStringList.Create;
  try
    Skip.Add('changed.pp');
    C := ParseGrep(Grep(['changed.pp:1:Parse', 'other.pp:1:Parse']), FIdents, False, Skip);
    AssertEquals(1, Length(C));
    AssertEquals('other.pp', C[0].Path);
  finally
    Skip.Free;
  end;
end;

{ A line without the two separators, or without a row, is passed over. }
procedure TCallersTest.TestDamagedOutput;
var
  C: TGittanCallers;
begin
  C := ParseGrep('a.pp'#0'Parse'#10#10'b.pp'#0'x'#0'Parse'#10'c.pp'#0'2'#0'Parse', FIdents,
    False, nil);
  AssertEquals(1, Length(C));
  AssertEquals('c.pp', C[0].Path);
  AssertEquals('last line without newline', 1, C[0].Row);
  AssertEquals(0, Length(ParseGrep('', FIdents, False, nil)));
end;

procedure TCallersTest.TestDefinitionRow;
var
  S: TGittanSymbols;
begin
  SetLength(S, 2);
  S[0] := Symbol('TReader.Parse(const S: string)', 10);
  S[1] := Symbol('class Status', 20);
  AssertTrue(IsDefinitionRow(S, 10, 'Parse', False));
  AssertFalse('another row', IsDefinitionRow(S, 11, 'Parse', False));
  AssertFalse('another word', IsDefinitionRow(S, 10, 'Status', False));
  AssertFalse(IsDefinitionRow(S, 20, 'status', False));
  AssertTrue(IsDefinitionRow(S, 20, 'status', True));
  AssertFalse(IsDefinitionRow(nil, 0, 'Parse', False));
end;

procedure TCallersTest.TestEnclosingSymbol;
var
  S: TGittanSymbols;
begin
  SetLength(S, 3);
  S[0] := Symbol('uses', 2);
  S[1] := Symbol('A', 10);
  S[2] := Symbol('A.B', 12);
  AssertEquals(-1, EnclosingSymbol(S, 1));
  AssertEquals(0, EnclosingSymbol(S, 2));
  AssertEquals(1, EnclosingSymbol(S, 11));
  AssertEquals(2, EnclosingSymbol(S, 12));
  AssertEquals(2, EnclosingSymbol(S, 100));
  AssertEquals(-1, EnclosingSymbol(nil, 5));
end;

procedure TCallersTest.TestCounts;
var
  C: TGittanCallers;
  Files, Lines: integer;
begin
  C := ParseGrep(Grep(['a.pp:1:Parse', 'a.pp:2:Parse Status', 'b.pp:1:Parse']),
    FIdents, False, nil);
  CountCallers(C, 0, Files, Lines);
  AssertEquals(2, Files);
  AssertEquals(3, Lines);
  CountCallers(C, 1, Files, Lines);
  AssertEquals(1, Files);
  AssertEquals(1, Lines);
  AssertEquals(2, CallerFileCount(C));
  AssertEquals(0, CallerFileCount(nil));
end;

procedure TCallersTest.TestDetails;
begin
  AssertEquals('used in 4 files, 7 lines', CallersDetail(4, 7, False));
  AssertEquals('used in 1 file, 1 line', CallersDetail(1, 1, False));
  AssertEquals('removed, still used in 2 files, 2 lines', CallersDetail(2, 2, True));
  AssertEquals('not used elsewhere', CallersDetail(0, 0, False));
  AssertEquals('not used elsewhere', CallersDetail(0, 0, True));
  AssertEquals('1 file', FilesText(1));
  AssertEquals('3 files', FilesText(3));
end;

procedure TCallersTest.TestLexerIgnoresCase;
begin
  AssertTrue(LexerIgnoresCase('Pascal'));
  AssertTrue(LexerIgnoresCase('Free Pascal'));
  AssertTrue(LexerIgnoresCase('PL/SQL'));
  AssertTrue(LexerIgnoresCase('Visual Basic'));
  AssertTrue(LexerIgnoresCase('Fortran 90'));
  AssertFalse(LexerIgnoresCase('C++'));
  AssertFalse(LexerIgnoresCase('JavaScript'));
  AssertFalse(LexerIgnoresCase('Adagio'));
  AssertFalse(LexerIgnoresCase(''));
end;

procedure TCallersTest.TestLexerIsProse;
begin
  AssertTrue(LexerIsProse('Markdown'));
  AssertTrue(LexerIsProse('reStructuredText'));
  AssertTrue(LexerIsProse('Text files'));
  AssertFalse(LexerIsProse('Pascal'));
  AssertFalse(LexerIsProse('CSS'));
  AssertFalse(LexerIsProse(''));
end;

initialization
  RegisterTest(TCallersTest);

end.
