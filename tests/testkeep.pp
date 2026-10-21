unit testkeep;

{** Tests of gittan.keep: the pairs of a block, and a diff rewritten
  with the kept pairs as plain code. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry, gittan.keep;

type
  TKeepTest = class(TTestCase)
  private
    FLines: TStringList;
    FKeptOf: TIntegerDynArray;
    procedure Lines(const ADiff: array of string);
    function Joined: string;
    function Keep(const AOld, ANew: string; ALine: integer): TGittanKeep;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPairs;
    procedure TestKeepPair;
    procedure TestKeepSplitsBlock;
    procedure TestKeepDeletedOnly;
    procedure TestKeepAddedOnly;
    procedure TestKeepWholeBlock;
    procedure TestNearestWins;
    procedure TestUnmatched;
    procedure TestNoBlocks;
    procedure TestKeeps;
    procedure TestMatch;
  end;

implementation

procedure TKeepTest.SetUp;
begin
  FLines := TStringList.Create;
end;

procedure TKeepTest.TearDown;
begin
  FLines.Free;
end;

procedure TKeepTest.Lines(const ADiff: array of string);
var
  s: string;
begin
  FLines.Clear;
  for s in ADiff do
    FLines.Add(s);
end;

function TKeepTest.Joined: string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to FLines.Count - 1 do
    Result := Result + FLines[i] + '|';
end;

{ A pair from its texts, '' for a side that is not there. }
function TKeepTest.Keep(const AOld, ANew: string; ALine: integer): TGittanKeep;
begin
  Result.HasOld := AOld <> '';
  Result.HasNew := ANew <> '';
  Result.Old := AOld;
  Result.New := ANew;
  Result.Line := ALine;
end;

{ Three deleted and two added lines make three pairs: two full ones and
  a deleted line that goes after the added ones. }
procedure TKeepTest.TestPairs;
var
  P: TGittanKeepArray;
begin
  Lines([' a', '-b', '-c', '-d', '+B', '+C', ' e']);
  P := BlockPairs(FLines, 1);
  AssertEquals('pairs', 3, Length(P));
  AssertEquals('first old', 'b', P[0].Old);
  AssertEquals('first new', 'B', P[0].New);
  AssertEquals('first line', 2, P[0].Line);
  AssertEquals('second line', 3, P[1].Line);
  AssertTrue('third has old', P[2].HasOld);
  AssertFalse('third has no new', P[2].HasNew);
  AssertEquals('third line', 4, P[2].Line);
end;

{ The kept pair's deleted line goes, its added line is plain code; the
  rest of the block stays a block, and KeptOf points at the keep. }
procedure TKeepTest.TestKeepPair;
begin
  Lines([' a', '-b', '-c', '+B', '+C', ' d']);
  AssertEquals(1, ApplyKeeps(FLines, [Keep('b', 'B', 2)], FKeptOf));
  AssertEquals(' a| B|-c|+C| d|', Joined);
  AssertEquals('kept of', 0, FKeptOf[1]);
  AssertEquals('not kept', -1, FKeptOf[2]);
  AssertEquals('kept of length', FLines.Count, Length(FKeptOf));
end;

{ A kept pair in the middle leaves a block on each side of it. }
procedure TKeepTest.TestKeepSplitsBlock;
begin
  Lines([' a', '-b', '-c', '-d', '+B', '+C', '+D', ' e']);
  ApplyKeeps(FLines, [Keep('c', 'C', 3)], FKeptOf);
  AssertEquals(' a|-b|+B| C|-d|+D| e|', Joined);
end;

{ A kept deleted line with no partner leaves nothing behind. }
procedure TKeepTest.TestKeepDeletedOnly;
begin
  Lines([' a', '-b', '-c', '+B', ' d']);
  ApplyKeeps(FLines, [Keep('c', '', 3)], FKeptOf);
  AssertEquals(' a|-b|+B| d|', Joined);
end;

procedure TKeepTest.TestKeepAddedOnly;
begin
  Lines([' a', '+x', '+y', ' d']);
  ApplyKeeps(FLines, [Keep('', 'y', 3)], FKeptOf);
  AssertEquals(' a|+x| y| d|', Joined);
  AssertEquals(0, FKeptOf[2]);
end;

{ Every pair kept: the block is plain code of the new file. }
procedure TKeepTest.TestKeepWholeBlock;
var
  P: TGittanKeepArray;
begin
  Lines([' a', '-b', '-c', '-d', '+B', '+C', ' e']);
  P := BlockPairs(FLines, 1);
  AssertEquals(3, ApplyKeeps(FLines, P, FKeptOf));
  AssertEquals(' a| B| C| e|', Joined);
  AssertEquals(1, FKeptOf[2]);
end;

{ Two pairs with the same text: the keep takes the one nearest the
  line it was made at, and a second keep the other. }
procedure TKeepTest.TestNearestWins;
begin
  Lines([' a', '-x', '+X', ' b', ' c', ' d', '-x', '+X', ' e']);
  ApplyKeeps(FLines, [Keep('x', 'X', 6)], FKeptOf);
  AssertEquals(' a|-x|+X| b| c| d| X| e|', Joined);
  Lines([' a', '-x', '+X', ' b', ' c', ' d', '-x', '+X', ' e']);
  ApplyKeeps(FLines, [Keep('x', 'X', 6), Keep('x', 'X', 6)], FKeptOf);
  AssertEquals(' a| X| b| c| d| X| e|', Joined);
  AssertEquals('second keep', 1, FKeptOf[1]);
end;

{ A keep whose lines are gone changes nothing. }
procedure TKeepTest.TestUnmatched;
begin
  Lines([' a', '-b', '+B', ' c']);
  AssertEquals(0, ApplyKeeps(FLines, [Keep('q', 'Q', 2)], FKeptOf));
  AssertEquals(' a|-b|+B| c|', Joined);
  AssertEquals(-1, FKeptOf[1]);
end;

procedure TKeepTest.TestNoBlocks;
begin
  Lines([' a', ' b']);
  AssertEquals(0, ApplyKeeps(FLines, [Keep('a', 'b', 1)], FKeptOf));
  AssertEquals(' a| b|', Joined);
  AssertEquals(2, Length(FKeptOf));
end;

{ The keeps of a session by path: added, counted, removed by the index
  Apply numbers them with, cleared. }
procedure TKeepTest.TestKeeps;
var
  K: TGittanKeeps;
begin
  K := TGittanKeeps.Create;
  try
    K.Add('a.txt', Keep('b', 'B', 2));
    K.Add('a.txt', Keep('c', 'C', 3));
    K.Add('other.txt', Keep('b', 'B', 2));
    AssertEquals('count', 2, K.Count('a.txt'));
    AssertEquals('none', 0, K.Count('none.txt'));
    Lines([' a', '-b', '-c', '+B', '+C', ' d']);
    K.Apply('a.txt', FLines, FKeptOf);
    AssertEquals(' a| B| C| d|', Joined);
    K.Remove('a.txt', FKeptOf[1]);
    AssertEquals('after remove', 1, K.Count('a.txt'));
    Lines([' a', '-b', '-c', '+B', '+C', ' d']);
    K.Apply('a.txt', FLines, FKeptOf);
    AssertEquals(' a|-b|+B| C| d|', Joined);
    Lines([' a', '-b', '+B', ' d']);
    K.Apply('none.txt', FLines, FKeptOf);
    AssertEquals('untouched', ' a|-b|+B| d|', Joined);
    AssertEquals('kept of for untouched', 4, Length(FKeptOf));
    { Prune drops the keep the diff does not hold, Items gives the rest. }
    K.Add('a.txt', Keep('x', 'X', 9));
    Lines([' a', '-b', '-c', '+B', '+C', ' d']);
    K.Prune('a.txt', FLines);
    AssertEquals('pruned', 1, K.Count('a.txt'));
    AssertEquals('C', K.Items('a.txt')[0].New);
    AssertEquals('no items', 0, Length(K.Items('none.txt')));
    K.Clear('a.txt');
    AssertEquals(0, K.Count('a.txt'));
    AssertEquals(1, K.Count('other.txt'));
    K.ClearAll;
    AssertEquals(0, K.Count('other.txt'));
  finally
    K.Free;
  end;
end;

{ Both lines of a matched pair get the keep's index; a deleted line
  past the added ones is matched on its own. }
procedure TKeepTest.TestMatch;
var
  M: TIntegerDynArray;
begin
  Lines([' a', '-b', '-c', '+B', ' d']);
  M := MatchKeeps(FLines, [Keep('c', '', 3), Keep('b', 'B', 2)]);
  AssertEquals(5, Length(M));
  AssertEquals(-1, M[0]);
  AssertEquals(1, M[1]);
  AssertEquals(0, M[2]);
  AssertEquals(1, M[3]);
  AssertEquals(-1, M[4]);
end;

initialization
  RegisterTest(TKeepTest);

end.
