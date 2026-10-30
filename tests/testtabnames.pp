unit testtabnames;

{** Tests of gittan.tabnames: folders of the same name told apart by
  their parents, as far as it takes, and names left alone otherwise. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.tabnames;

type
  TTabNamesTest = class(TTestCase)
  published
    procedure TestUnique;
    procedure TestParent;
    procedure TestDeeper;
    procedure TestSamePathAndEmpty;
  end;

implementation

function P(const AParts: array of string): string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(AParts) do
    Result := Result + PathDelim + AParts[i];
end;

procedure TTabNamesTest.TestUnique;
var
  N: TStringArray;
begin
  N := DistinctNames([P(['Volumes', 'Projects', 'trailhead']), P(['Users', 'me', 'gittan']) + PathDelim]);
  AssertEquals('trailhead', N[0]);
  AssertEquals('a trailing delimiter aside', 'gittan', N[1]);
end;

procedure TTabNamesTest.TestParent;
var
  N: TStringArray;
begin
  N := DistinctNames([P(['Volumes', 'Projects', 'trailhead']),
    P(['Volumes', 'Projects', 'conflict', 'trailhead']), P(['src', 'gittan'])]);
  AssertEquals('Projects' + PathDelim + 'trailhead', N[0]);
  AssertEquals('conflict' + PathDelim + 'trailhead', N[1]);
  AssertEquals('gittan', N[2]);
end;

procedure TTabNamesTest.TestDeeper;
var
  N: TStringArray;
begin
  N := DistinctNames([P(['a', 'x', 'src', 'app']), P(['b', 'x', 'src', 'app']),
    P(['c', 'y', 'src', 'app'])]);
  AssertEquals('a' + PathDelim + 'x' + PathDelim + 'src' + PathDelim + 'app', N[0]);
  AssertEquals('b' + PathDelim + 'x' + PathDelim + 'src' + PathDelim + 'app', N[1]);
  AssertEquals('y' + PathDelim + 'src' + PathDelim + 'app', N[2]);
end;

procedure TTabNamesTest.TestSamePathAndEmpty;
var
  N: TStringArray;
begin
  N := DistinctNames([P(['p', 'app']), P(['p', 'app']), '', P(['app'])]);
  AssertEquals('the same path twice', 'p' + PathDelim + 'app', N[0]);
  AssertEquals('p' + PathDelim + 'app', N[1]);
  AssertEquals('an empty path', '', N[2]);
  AssertEquals('as far as it goes', 'app', N[3]);
end;

initialization
  RegisterTest(TTabNamesTest);
end.
