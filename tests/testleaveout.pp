unit testleaveout;

{** Tests of gittan.leaveout: the text committed for a file with some of
  its changes left out. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.keep, gittan.leaveout;

type
  TLeaveOutTest = class(TTestCase)
  private
    FLines: TStringList;
    procedure Lines(const ADiff: array of string);
    function Pair(const AOld, ANew: string; ALine: integer): TGittanKeep;
    function Text(const AFile: string; const ALeftOut: array of TGittanKeep): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNothingLeftOut;
    procedure TestPairLeftOut;
    procedure TestOneBlockOfTwo;
    procedure TestPairInsideBlock;
    procedure TestDeletedAndAddedOnly;
    procedure TestLineEnds;
    procedure TestNotFound;
    procedure TestStale;
    procedure TestAllLeftOut;
  end;

implementation

uses
  gittan.discard;

procedure TLeaveOutTest.SetUp;
begin
  FLines := TStringList.Create;
end;

procedure TLeaveOutTest.TearDown;
begin
  FLines.Free;
end;

procedure TLeaveOutTest.Lines(const ADiff: array of string);
var
  s: string;
begin
  FLines.Clear;
  for s in ADiff do
    FLines.Add(s);
end;

{ A pair from its texts, '' for a side that is not there. }
function TLeaveOutTest.Pair(const AOld, ANew: string; ALine: integer): TGittanKeep;
begin
  Result.HasOld := AOld <> '';
  Result.HasNew := ANew <> '';
  Result.Old := AOld;
  Result.New := ANew;
  Result.Line := ALine;
end;

{ The text to commit for AFile with FLines as its diff; the error when
  there is none. }
function TLeaveOutTest.Text(const AFile: string; const ALeftOut: array of TGittanKeep): string;
var
  Found: integer;
  Err: string;
  Res: RawByteString;
begin
  if LeaveOutText(AFile, FLines, ALeftOut, Res, Found, Err) then
    Result := Res
  else
    Result := 'error: ' + Err;
end;

procedure TLeaveOutTest.TestNothingLeftOut;
begin
  Lines([' a', '-b', '+B', ' c']);
  AssertEquals('a'#10'B'#10'c'#10, Text('a'#10'B'#10'c'#10, []));
end;

procedure TLeaveOutTest.TestPairLeftOut;
var
  Found: integer;
  Err: string;
  Res: RawByteString;
begin
  Lines([' a', '-b', '+B', ' c']);
  AssertTrue(LeaveOutText('a'#10'B'#10'c'#10, FLines, [Pair('b', 'B', 2)], Res, Found, Err));
  AssertEquals('a'#10'b'#10'c'#10, Res);
  AssertEquals(1, Found);
end;

{ The block left out goes back, the other goes in. }
procedure TLeaveOutTest.TestOneBlockOfTwo;
begin
  Lines(['-a', '+A', ' b', '-c', '+C']);
  AssertEquals('A'#10'b'#10'c'#10, Text('A'#10'b'#10'C'#10, [Pair('c', 'C', 3)]));
  AssertEquals('a'#10'b'#10'C'#10, Text('A'#10'b'#10'C'#10, [Pair('a', 'A', 1)]));
end;

{ Two deleted and three added lines: the second pair left out puts its
  deleted line where its added one was, between the others. }
procedure TLeaveOutTest.TestPairInsideBlock;
begin
  Lines(['-a', '-b', '+A', '+B', '+C', ' d']);
  AssertEquals('A'#10'b'#10'C'#10'd'#10, Text('A'#10'B'#10'C'#10'd'#10, [Pair('b', 'B', 2)]));
  AssertEquals('a'#10'b'#10'd'#10, Text('A'#10'B'#10'C'#10'd'#10,
    [Pair('a', 'A', 1), Pair('b', 'B', 2), Pair('', 'C', 3)]));
end;

{ A deleted line left out comes back; an added line left out goes. }
procedure TLeaveOutTest.TestDeletedAndAddedOnly;
begin
  Lines([' a', '-x', ' c', '+n']);
  AssertEquals('a'#10'x'#10'c'#10'n'#10, Text('a'#10'c'#10'n'#10, [Pair('x', '', 2)]));
  AssertEquals('a'#10'c'#10, Text('a'#10'c'#10'n'#10, [Pair('', 'n', 3)]));
end;

{ CRLF is kept, and given to a line put back; a file without a final
  newline gets none. }
procedure TLeaveOutTest.TestLineEnds;
begin
  Lines([' a', '-b', '+B', ' c']);
  AssertEquals('a'#13#10'b'#13#10'c'#13#10,
    Text('a'#13#10'B'#13#10'c'#13#10, [Pair('b', 'B', 2)]));
  AssertEquals('a'#10'b'#10'c', Text('a'#10'B'#10'c', [Pair('b', 'B', 2)]));
end;

{ A change left out that the diff does not hold any more is not found,
  and the file goes in as it is. }
procedure TLeaveOutTest.TestNotFound;
var
  Found: integer;
  Err: string;
  Res: RawByteString;
begin
  Lines([' a', '-b', '+B', ' c']);
  AssertTrue(LeaveOutText('a'#10'B'#10'c'#10, FLines, [Pair('b', 'X', 2)], Res, Found, Err));
  AssertEquals('a'#10'B'#10'c'#10, Res);
  AssertEquals(0, Found);
end;

{ The file's added lines must be the diff's. }
procedure TLeaveOutTest.TestStale;
begin
  Lines([' a', '-b', '+B', ' c']);
  AssertEquals('error: ' + rsDiscardStale, Text('a'#10'Q'#10'c'#10, [Pair('b', 'B', 2)]));
  AssertEquals('error: ' + rsDiscardStale, Text('a'#10'B'#10'c'#10'd'#10, []));
end;

procedure TLeaveOutTest.TestAllLeftOut;
begin
  Lines([' a', '-b', '+B', ' c', '+d']);
  AssertFalse(AllLeftOut(FLines, [Pair('b', 'B', 2)]));
  AssertTrue(AllLeftOut(FLines, [Pair('', 'd', 4), Pair('b', 'B', 2)]));
  Lines([' a', ' b']);
  AssertFalse('nothing changed', AllLeftOut(FLines, []));
end;

initialization
  RegisterTest(TLeaveOutTest);
end.
