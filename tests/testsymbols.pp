unit testsymbols;

{** Tests of gittan.symbols: matching a word against code tree names. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.symbols;

type
  TSymbolsTest = class(TTestCase)
  published
    procedure TestWholeIdentifierOnly;
    procedure TestQualifiedName;
    procedure TestParameterRanksLower;
    procedure TestCaseRanks;
    procedure TestEmpty;
    procedure TestNameIdentifier;
    procedure TestBestSymbol;
    procedure TestSymbolLineSpan;
  end;

implementation

procedure TSymbolsTest.TestWholeIdentifierOnly;
begin
  AssertEquals(srName, SymbolRank('GoToChange', 'GoToChange'));
  AssertEquals(srNone, SymbolRank('GoToChanges', 'GoToChange'));
  AssertEquals(srNone, SymbolRank('GoToChange', 'Change'));
  AssertEquals(srName, SymbolRank('class Foo', 'Foo'));
end;

procedure TSymbolsTest.TestQualifiedName;
begin
  AssertEquals(srName, SymbolRank('TForm1.GoToChange', 'GoToChange'));
  AssertEquals(srName, SymbolRank('TForm1.GoToChange', 'TForm1'));
  AssertEquals(srName, SymbolRank('func foo(int a, char b)', 'foo'));
end;

procedure TSymbolsTest.TestParameterRanksLower;
begin
  AssertEquals(srAnywhere, SymbolRank('foo(int a, char b)', 'char'));
  AssertEquals(srAnywhere, SymbolRank('foo(int a, char b)', 'b'));
end;

procedure TSymbolsTest.TestCaseRanks;
begin
  AssertEquals(srNameIgnoringCase, SymbolRank('TForm1.gotochange', 'GoToChange'));
  AssertTrue(SymbolRank('Foo', 'Foo') > SymbolRank('foo', 'Foo'));
end;

procedure TSymbolsTest.TestEmpty;
begin
  AssertEquals(srNone, SymbolRank('', 'Foo'));
  AssertEquals(srNone, SymbolRank('Foo', ''));
  AssertEquals(srNone, SymbolRank('()', 'Foo'));
end;

procedure TSymbolsTest.TestNameIdentifier;
begin
  AssertEquals('foo', NameIdentifier('func foo(int a, char b)'));
  AssertEquals('GoToChange', NameIdentifier('TForm1.GoToChange'));
  AssertEquals('Foo', NameIdentifier('class Foo'));
  AssertEquals('anon', NameIdentifier('func <anon>()'));
  AssertEquals('', NameIdentifier('<>()'));
  AssertEquals('', NameIdentifier(''));
end;

procedure TSymbolsTest.TestBestSymbol;
var
  S: TGittanSymbols;
begin
  SetLength(S, 3);
  S[0].Name := 'foo(int bar)';
  S[0].Row := 1;
  S[1].Name := 'TFoo.Bar';
  S[1].Row := 5;
  S[2].Name := 'bar';
  S[2].Row := 9;
  AssertEquals(1, BestSymbol(S, 'Bar', -1));
  AssertEquals(2, BestSymbol(S, 'bar', -1));
  AssertEquals(1, BestSymbol(S, 'bar', 9));
  AssertEquals(0, BestSymbol(S, 'foo', -1));
  AssertEquals(-1, BestSymbol(S, 'baz', -1));
  AssertEquals(-1, BestSymbol(nil, 'bar', -1));
end;

procedure TSymbolsTest.TestSymbolLineSpan;
var
  From, Count: SizeInt;
begin
  SymbolLineSpan(30, 10, From, Count);
  AssertEquals('short row whole', 1, From);
  AssertEquals(30, Count);
  SymbolLineSpan(MaxSymbolLine, 10, From, Count);
  AssertEquals(1, From);
  AssertEquals(MaxSymbolLine, Count);
  { A minified row: a part around the name, a little before it. }
  SymbolLineSpan(2000000, 1000000, From, Count);
  AssertEquals(MaxSymbolLine, Count);
  AssertTrue('name inside', (From <= 1000001) and (1000001 < From + Count));
  AssertTrue('some text before the name', From < 1000001 - 10);
  SymbolLineSpan(2000000, 5, From, Count);
  AssertEquals('near the start', 1, From);
  AssertEquals(MaxSymbolLine, Count);
  SymbolLineSpan(2000000, 1999999, From, Count);
  AssertEquals('near the end', 2000000 - MaxSymbolLine + 1, From);
  AssertEquals(MaxSymbolLine, Count);
end;

initialization
  RegisterTest(TSymbolsTest);

end.
