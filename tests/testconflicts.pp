unit testconflicts;

{** Tests of gittan.conflicts. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry, gittan.conflicts;

type
  TConflictsTest = class(TTestCase)
  private
    function Roles(const ALines: array of string; out ACount: integer): string;
  published
    procedure TestNone;
    procedure TestMerge;
    procedure TestDiff3;
    procedure TestNotMarkers;
    procedure TestOpenAtEnd;
  end;

implementation

{ The roles as digits, one per line. }
function TConflictsTest.Roles(const ALines: array of string; out ACount: integer): string;
var
  List: TStringList;
  R: TIntegerDynArray;
  i: integer;
begin
  List := TStringList.Create;
  try
    for i := 0 to High(ALines) do
      List.Add(ALines[i]);
    R := ConflictRoles(List);
    ACount := ConflictCount(R, List);
    Result := '';
    for i := 0 to High(R) do
      Result := Result + IntToStr(R[i]);
  finally
    List.Free;
  end;
end;

procedure TConflictsTest.TestNone;
var
  n: integer;
begin
  AssertEquals('000', Roles([' a', '+b', '-c'], n));
  AssertEquals(0, n);
  AssertEquals('', Roles([], n));
end;

procedure TConflictsTest.TestMerge;
var
  n: integer;
begin
  AssertEquals('0122104410', Roles([' a', '+<<<<<<< HEAD', ' ours', ' ours 2', '+=======',
    '-old', '+theirs', '+theirs 2', '+>>>>>>> other', ' z'], n));
  AssertEquals(1, n);
end;

procedure TConflictsTest.TestDiff3;
var
  n: integer;
begin
  AssertEquals('012131410121410', Roles([' a', '+<<<<<<< HEAD', ' B-main', '+||||||| 7a9841f',
    '+b', '+=======', '+B-other', '+>>>>>>> other', ' c', '+<<<<<<<', ' x', '+=======',
    '+y', '+>>>>>>>', ' d'], n));
  AssertEquals(2, n);
end;

procedure TConflictsTest.TestNotMarkers;
var
  n: integer;
begin
  { Six signs, a word after the signs without a space, a lone "=======" or
    ">>>>>>>" outside a conflict, and a deleted marker. }
  AssertEquals('00000', Roles(['+<<<<<<', '+<<<<<<<x', '+=======', '+>>>>>>> a', '-<<<<<<< HEAD'], n));
  AssertEquals(0, n);
end;

procedure TConflictsTest.TestOpenAtEnd;
var
  n: integer;
begin
  AssertEquals('122', Roles(['+<<<<<<< HEAD', ' a', ' b'], n));
  AssertEquals(1, n);
end;

initialization
  RegisterTest(TConflictsTest);

end.
