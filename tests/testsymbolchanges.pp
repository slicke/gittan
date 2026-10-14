unit testsymbolchanges;

{** Tests of gittan.symbolchanges: which symbols a diff changed. The texts
  are rows of a change view: one marker per row, and the code tree ranges
  given by hand as a lexer would find them. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.symbols, gittan.symbolchanges;

type
  TSymbolChangesTest = class(TTestCase)
  private
    FLines, FOldLines: TStringList;
    FNew, FOld: TGittanSideText;
    procedure Range(var ASide: TGittanSideText; const AName: string; AFrom, ATo: integer;
      ADepth: integer = 0);
    procedure Text(var ASide: TGittanSideText; ALines: TStringList; const ARows: array of string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestInnermostRange;
    procedure TestChangedLinesBelongToInnermost;
    procedure TestWholeRangeSwallowsInner;
    procedure TestDeletedWhole;
    procedure TestRewriteIsOneChange;
    procedure TestMoved;
    procedure TestMovedAndChanged;
    procedure TestRenamed;
    procedure TestOneRowBodyIsNoRename;
    procedure TestTwoSides;
    procedure TestNothingChanged;
    procedure TestDetails;
  end;

implementation

{ Rows are given as the marker followed by the text. }
procedure TSymbolChangesTest.Text(var ASide: TGittanSideText; ALines: TStringList;
  const ARows: array of string);
var
  i: integer;
begin
  ALines.Clear;
  ASide.Markers := '';
  for i := 0 to High(ARows) do
  begin
    ASide.Markers := ASide.Markers + ARows[i][1];
    ALines.Add(Copy(ARows[i], 2, MaxInt));
  end;
  ASide.Lines := ALines;
end;

procedure TSymbolChangesTest.Range(var ASide: TGittanSideText; const AName: string;
  AFrom, ATo: integer; ADepth: integer);
begin
  SetLength(ASide.Ranges, Length(ASide.Ranges) + 1);
  with ASide.Ranges[High(ASide.Ranges)] do
  begin
    Symbol.Name := AName;
    Symbol.Row := AFrom;
    Symbol.Col := 0;
    Symbol.Depth := ADepth;
    Symbol.Line := ASide.Lines[AFrom];
    FromRow := AFrom;
    ToRow := ATo;
  end;
end;

procedure TSymbolChangesTest.SetUp;
begin
  FLines := TStringList.Create;
  FOldLines := TStringList.Create;
  FNew := Default(TGittanSideText);
  FOld := Default(TGittanSideText);
end;

procedure TSymbolChangesTest.TearDown;
begin
  FLines.Free;
  FOldLines.Free;
end;

procedure TSymbolChangesTest.TestInnermostRange;
begin
  Text(FNew, FLines, [' class A', ' method B', ' body', ' end', ' end', ' free']);
  Range(FNew, 'A', 0, 4);
  Range(FNew, 'A.B', 1, 3, 1);
  AssertEquals(1, InnermostRange(FNew.Ranges, 2));
  AssertEquals(0, InnermostRange(FNew.Ranges, 4));
  AssertEquals(-1, InnermostRange(FNew.Ranges, 5));
  AssertEquals(-1, InnermostRange(nil, 0));
end;

{ A changed row counts for the innermost range only; the class around
  the method is not reported. }
procedure TSymbolChangesTest.TestChangedLinesBelongToInnermost;
var
  Changes: TGittanSymbolChanges;
begin
  Text(FNew, FLines, [' class A', ' method B', '-old', '+new', '+more', ' end', ' end']);
  Range(FNew, 'A', 0, 6);
  Range(FNew, 'A.B', 1, 5, 1);
  Changes := SymbolChanges(FNew, FOld, False);
  AssertEquals(1, Length(Changes));
  AssertEquals(1, Changes[0].Range);
  AssertTrue(Changes[0].Kind = scChanged);
  AssertEquals(2, Changes[0].Added);
  AssertEquals(1, Changes[0].Deleted);
  AssertEquals(-1, Changes[0].Other);
end;

{ A class added as a whole is reported once, its methods not again; a
  change at the class level beside it is reported for the class. }
procedure TSymbolChangesTest.TestWholeRangeSwallowsInner;
var
  Changes: TGittanSymbolChanges;
begin
  Text(FNew, FLines, [' class C', '+field', ' end', '+class A', '+method B', '+body',
    '+end', '+end']);
  Range(FNew, 'C', 0, 2);
  Range(FNew, 'A', 3, 7);
  Range(FNew, 'A.B', 4, 6, 1);
  Changes := SymbolChanges(FNew, FOld, False);
  AssertEquals(2, Length(Changes));
  AssertEquals(0, Changes[0].Range);
  AssertTrue(Changes[0].Kind = scChanged);
  AssertEquals(1, Changes[0].Added);
  AssertEquals(1, Changes[1].Range);
  AssertTrue(Changes[1].Kind = scAdded);
  AssertEquals(5, Changes[1].Added);
end;

procedure TSymbolChangesTest.TestDeletedWhole;
var
  Changes: TGittanSymbolChanges;
begin
  Text(FNew, FLines, [' keep', '-procedure Gone;', '-begin', '-end;', ' keep']);
  Range(FNew, 'Gone', 1, 3);
  Changes := SymbolChanges(FNew, FOld, False);
  AssertEquals(1, Length(Changes));
  AssertTrue(Changes[0].Kind = scDeleted);
  AssertEquals(3, Changes[0].Deleted);
end;

{ The old and the new copy of a function next to each other are one
  rewritten function. }
procedure TSymbolChangesTest.TestRewriteIsOneChange;
var
  Changes: TGittanSymbolChanges;
begin
  Text(FNew, FLines, [' keep', '-procedure F;', '-begin', '-  a;', '-end;', '+procedure F;',
    '+begin', '+  b;', '+  c;', '+end;', ' keep']);
  Range(FNew, 'F', 1, 4);
  Range(FNew, 'F', 5, 9);
  Changes := SymbolChanges(FNew, FOld, False);
  AssertEquals(1, Length(Changes));
  AssertEquals(1, Changes[0].Range);
  AssertTrue(Changes[0].Kind = scChanged);
  AssertEquals(5, Changes[0].Added);
  AssertEquals(4, Changes[0].Deleted);
end;

procedure TSymbolChangesTest.TestMoved;
var
  Changes: TGittanSymbolChanges;
begin
  Text(FNew, FLines, ['-procedure F;', '-begin', '-  a;', '-end;', ' procedure G;', ' begin',
    ' end;', '+procedure F;', '+begin', '+    a;', '+end;']);
  Range(FNew, 'F', 0, 3);
  Range(FNew, 'G', 4, 6);
  Range(FNew, 'F', 7, 10);
  Changes := SymbolChanges(FNew, FOld, False);
  AssertEquals(2, Length(Changes));
  AssertTrue(Changes[0].Kind = scMovedFrom);
  AssertEquals(0, Changes[0].Range);
  AssertEquals(1, Changes[0].Other);
  AssertTrue(Changes[1].Kind = scMoved);
  AssertEquals(2, Changes[1].Range);
  AssertEquals(0, Changes[1].Other);
  { Indentation does not count. }
  AssertTrue(Changes[1].Same);
end;

procedure TSymbolChangesTest.TestMovedAndChanged;
var
  Changes: TGittanSymbolChanges;
begin
  Text(FNew, FLines, ['-procedure F;', '-begin', '-  a;', '-end;', ' procedure G;', ' begin',
    ' end;', '+procedure F;', '+begin', '+  b;', '+end;']);
  Range(FNew, 'F', 0, 3);
  Range(FNew, 'G', 4, 6);
  Range(FNew, 'F', 7, 10);
  Changes := SymbolChanges(FNew, FOld, False);
  AssertEquals(2, Length(Changes));
  AssertTrue(Changes[1].Kind = scMoved);
  AssertFalse(Changes[1].Same);
end;

procedure TSymbolChangesTest.TestRenamed;
var
  Changes: TGittanSymbolChanges;
begin
  Text(FNew, FLines, ['-procedure Old;', '-begin', '-  a;', '-  b;', '-end;', '+procedure New;',
    '+begin', '+  a;', '+  b;', '+end;']);
  Range(FNew, 'Old', 0, 4);
  Range(FNew, 'New', 5, 9);
  Changes := SymbolChanges(FNew, FOld, False);
  AssertEquals(2, Length(Changes));
  AssertTrue(Changes[0].Kind = scRenamedFrom);
  AssertEquals(1, Changes[0].Other);
  AssertTrue(Changes[1].Kind = scRenamed);
  AssertEquals(0, Changes[1].Other);
end;

procedure TSymbolChangesTest.TestOneRowBodyIsNoRename;
var
  Changes: TGittanSymbolChanges;
begin
  Text(FNew, FLines, ['-procedure Old;', '-begin end;', '+procedure New;', '+begin end;']);
  Range(FNew, 'Old', 0, 1);
  Range(FNew, 'New', 2, 3);
  Changes := SymbolChanges(FNew, FOld, False);
  AssertEquals(2, Length(Changes));
  AssertTrue(Changes[0].Kind = scDeleted);
  AssertTrue(Changes[1].Kind = scAdded);
end;

{ Side by side: a filler row on the new side stands for a deleted line
  and is marked '-', one on the old side for an added line, marked '+'.
  The wholly deleted function is only on the old side; the function
  with a line deleted is reported from the new side, where its rows are
  fillers. }
procedure TSymbolChangesTest.TestTwoSides;
var
  Changes: TGittanSymbolChanges;
begin
  Text(FNew, FLines, ['-', '-', '-', ' procedure G;', ' begin', '-', '+  b;', ' end;']);
  Range(FNew, 'G', 3, 7);
  Text(FOld, FOldLines, ['-procedure F;', '-begin', '-end;', ' procedure G;', ' begin',
    '-  a;', '+', ' end;']);
  Range(FOld, 'F', 0, 2);
  Range(FOld, 'G', 3, 7);
  Changes := SymbolChanges(FNew, FOld, True);
  AssertEquals(2, Length(Changes));
  AssertTrue(Changes[0].OnOld);
  AssertTrue(Changes[0].Kind = scDeleted);
  AssertEquals('F', ChangeRange(Changes[0], FNew, FOld).Symbol.Name);
  AssertFalse(Changes[1].OnOld);
  AssertTrue(Changes[1].Kind = scChanged);
  AssertEquals('G', ChangeRange(Changes[1], FNew, FOld).Symbol.Name);
  AssertEquals(1, Changes[1].Added);
  AssertEquals(1, Changes[1].Deleted);
end;

procedure TSymbolChangesTest.TestNothingChanged;
begin
  Text(FNew, FLines, [' procedure F;', ' begin', ' end;']);
  Range(FNew, 'F', 0, 2);
  AssertEquals(0, Length(SymbolChanges(FNew, FOld, False)));
  { A changed row outside every range names no symbol. }
  Text(FNew, FLines, ['+uses x;', ' procedure F;', ' begin', ' end;']);
  FNew.Ranges := nil;
  Range(FNew, 'F', 1, 3);
  AssertEquals(0, Length(SymbolChanges(FNew, FOld, False)));
end;

procedure TSymbolChangesTest.TestDetails;
var
  C: TGittanSymbolChange;
begin
  C := Default(TGittanSymbolChange);
  C.Kind := scChanged;
  C.Added := 3;
  C.Deleted := 1;
  AssertEquals('+3  −1', ChangeDetail(C, ''));
  C.Kind := scAdded;
  AssertEquals('added  +3', ChangeDetail(C, ''));
  C.Kind := scDeleted;
  AssertEquals('deleted  −1', ChangeDetail(C, ''));
  C.Kind := scMoved;
  AssertEquals('moved here, changed', ChangeDetail(C, ''));
  C.Same := True;
  AssertEquals('moved here', ChangeDetail(C, ''));
  C.Kind := scMovedFrom;
  AssertEquals('moved away', ChangeDetail(C, ''));
  C.Kind := scRenamed;
  AssertEquals('renamed from Old', ChangeDetail(C, 'Old'));
  C.Kind := scRenamedFrom;
  AssertEquals('renamed to New', ChangeDetail(C, 'New'));
end;

initialization
  RegisterTest(TSymbolChangesTest);

end.
