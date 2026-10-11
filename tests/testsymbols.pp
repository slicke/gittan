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

initialization
  RegisterTest(TSymbolsTest);

end.
