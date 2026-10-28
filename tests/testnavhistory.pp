unit testnavhistory;

{** Tests of gittan.navhistory: places visited, stepped back and forward
  through, the forward list emptied by a new visit, a place not kept
  twice in a row at the same row, the oldest dropped past the limit,
  and what makes two places the same. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.navhistory;

type
  TNavHistoryTest = class(TTestCase)
  published
    procedure TestSamePlace;
    procedure TestBackForward;
    procedure TestVisitEmptiesForward;
    procedure TestNoRepeat;
    procedure TestLimit;
  end;

implementation

function Place(AKind: TGittanPlaceKind; const APath: string; ARow: integer = 0): TGittanPlace;
begin
  Result := Default(TGittanPlace);
  Result.Kind := AKind;
  Result.Path := APath;
  Result.Row := ARow;
end;

procedure TNavHistoryTest.TestSamePlace;
var
  A, B: TGittanPlace;
begin
  A := Place(pkChanges, 'a.pp', 3);
  B := Place(pkChanges, 'a.pp', 40);
  B.Top := 30;
  AssertTrue('rows aside', SamePlace(A, B));
  AssertFalse(SamePlaceAndRow(A, B));
  B.Row := 3;
  AssertTrue('the top aside', SamePlaceAndRow(A, B));
  B.Base := 'main';
  AssertFalse('another base', SamePlace(A, B));
  AssertFalse('another kind', SamePlace(A, Place(pkFile, 'a.pp', 3)));
  AssertFalse('another file', SamePlace(A, Place(pkChanges, 'b.pp', 3)));
  B := A;
  B.Ref := 'abc';
  AssertFalse('another commit', SamePlace(A, B));
end;

procedure TNavHistoryTest.TestBackForward;
var
  H: TGittanNavHistory;
  P: TGittanPlace;
begin
  H := TGittanNavHistory.Create;
  try
    AssertFalse(H.CanBack);
    AssertFalse(H.CanForward);
    { Summary, then a.pp, then b.pp: at c.pp now. }
    H.Visit(Place(pkSummary, ''));
    H.Visit(Place(pkChanges, 'a.pp', 5));
    H.Visit(Place(pkChanges, 'b.pp'));
    P := H.Back(Place(pkChanges, 'c.pp', 7));
    AssertEquals('b.pp', P.Path);
    P := H.Back(P);
    AssertEquals('a.pp', P.Path);
    AssertEquals('the row it was left at', 5, P.Row);
    AssertTrue(H.CanBack);
    AssertTrue(H.CanForward);
    P := H.Forward(P);
    AssertEquals('b.pp', P.Path);
    P := H.Forward(P);
    AssertEquals('c.pp', P.Path);
    AssertEquals(7, P.Row);
    AssertFalse(H.CanForward);
    AssertEquals(3, Length(H.BackPlaces));
    H.Clear;
    AssertFalse(H.CanBack);
  finally
    H.Free;
  end;
end;

procedure TNavHistoryTest.TestVisitEmptiesForward;
var
  H: TGittanNavHistory;
  P: TGittanPlace;
begin
  H := TGittanNavHistory.Create;
  try
    H.Visit(Place(pkChanges, 'a.pp'));
    P := H.Back(Place(pkChanges, 'b.pp'));
    AssertTrue(H.CanForward);
    H.Visit(P);
    AssertFalse(H.CanForward);
    AssertEquals('a.pp', H.BackPlaces[0].Path);
  finally
    H.Free;
  end;
end;

procedure TNavHistoryTest.TestNoRepeat;
var
  H: TGittanNavHistory;
begin
  H := TGittanNavHistory.Create;
  try
    H.Visit(Place(pkChanges, 'a.pp', 2));
    H.Visit(Place(pkChanges, 'a.pp', 2));
    AssertEquals('same place and row once', 1, Length(H.BackPlaces));
    H.Visit(Place(pkChanges, 'a.pp', 90));
    AssertEquals('a jump in the file is a place', 2, Length(H.BackPlaces));
  finally
    H.Free;
  end;
end;

procedure TNavHistoryTest.TestLimit;
var
  H: TGittanNavHistory;
  i: integer;
begin
  H := TGittanNavHistory.Create(3);
  try
    for i := 1 to 5 do
      H.Visit(Place(pkChanges, IntToStr(i) + '.pp'));
    AssertEquals(3, Length(H.BackPlaces));
    AssertEquals('the oldest dropped', '3.pp', H.BackPlaces[0].Path);
    AssertEquals('5.pp', H.BackPlaces[2].Path);
  finally
    H.Free;
  end;
end;

initialization
  RegisterTest(TNavHistoryTest);
end.
