unit testblame;

{** Tests of gittan.blame: the reading of git's porcelain output and
  the age texts. The blame of a real repository is tested in testgit. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.blame;

type
  TBlameTest = class(TTestCase)
  published
    procedure TestParse;
    procedure TestParseUncommitted;
    procedure TestParseSha256;
    procedure TestParseGarbage;
    procedure TestAge;
  end;

implementation

const
  HashA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  HashB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  Zeros = '0000000000000000000000000000000000000000';

{ Two commits over three lines: A has lines 1 and 3, B line 2. The
  details of A come with its first group only. The text of line 2 holds
  a bare carriage return. }
function Sample: string;
begin
  Result :=
    HashA + ' 1 1 1'#10 +
    'author Anna Andersson'#10 +
    'author-mail <anna@example.invalid>'#10 +
    'author-time 1700000000'#10 +
    'author-tz +0100'#10 +
    'committer Anna Andersson'#10 +
    'summary First commit'#10 +
    'filename a.txt'#10 +
    #9'one'#10 +
    HashB + ' 2 2 1'#10 +
    'author Bo'#10 +
    'author-time 1700086400'#10 +
    'summary Second, with a space'#10 +
    'filename a.txt'#10 +
    #9'tw'#13'o'#10 +
    HashA + ' 3 3 1'#10 +
    #9'three'#10;
end;

procedure TBlameTest.TestParse;
var
  Blame: TGittanBlame;
begin
  Blame := TGittanBlame.Create;
  try
    AssertTrue(Blame.Parse(Sample));
    AssertEquals(3, Blame.LineCount);
    AssertEquals(2, Length(Blame.Commits));
    AssertEquals(0, Blame.CommitOf(1));
    AssertEquals(1, Blame.CommitOf(2));
    AssertEquals(0, Blame.CommitOf(3));
    AssertEquals(-1, Blame.CommitOf(0));
    AssertEquals(-1, Blame.CommitOf(4));
    AssertEquals(HashA, Blame.Commits[0].Hash);
    AssertEquals('Anna Andersson', Blame.Commits[0].Author);
    AssertEquals(1700000000, Blame.Commits[0].Time);
    AssertEquals('First commit', Blame.Commits[0].Summary);
    AssertFalse(Blame.Commits[0].Uncommitted);
    AssertEquals('Bo', Blame.Commits[1].Author);
    AssertEquals('Second, with a space', Blame.Commits[1].Summary);
  finally
    Blame.Free;
  end;
end;

procedure TBlameTest.TestParseUncommitted;
var
  Blame: TGittanBlame;
begin
  Blame := TGittanBlame.Create;
  try
    AssertTrue(Blame.Parse(Zeros + ' 1 1 1'#10'author Not Committed Yet'#10 +
      'author-time 1700000000'#10'summary Version of a.txt from a.txt'#10 +
      'filename a.txt'#10#9'x'#10));
    AssertEquals(1, Blame.LineCount);
    AssertTrue(Blame.Commits[0].Uncommitted);
  finally
    Blame.Free;
  end;
end;

{ A repository made with --object-format=sha256 names its commits with
  64 hex digits, the uncommitted lines with 64 zeros. }
procedure TBlameTest.TestParseSha256;
var
  Blame: TGittanBlame;
  Hash: string;
begin
  Hash := StringOfChar('c', 64);
  Blame := TGittanBlame.Create;
  try
    AssertTrue(Blame.Parse(Hash + ' 1 1 1'#10'author Cleo'#10 +
      'author-time 1700000000'#10'summary Long ids'#10'filename a.txt'#10 +
      #9'one'#10 + StringOfChar('0', 64) + ' 2 2 1'#10 +
      'author Not Committed Yet'#10'author-time 1700000000'#10 +
      'summary Version of a.txt from a.txt'#10'filename a.txt'#10#9'two'#10 +
      Hash + ' 3 3 1'#10#9'three'#10));
    AssertEquals(3, Blame.LineCount);
    AssertEquals(2, Length(Blame.Commits));
    AssertEquals(Hash, Blame.Commits[0].Hash);
    AssertEquals('Cleo', Blame.Commits[0].Author);
    AssertFalse(Blame.Commits[0].Uncommitted);
    AssertTrue(Blame.Commits[1].Uncommitted);
    AssertEquals(0, Blame.CommitOf(3));
    { An id of another length is no header. }
    AssertFalse(Blame.Parse(StringOfChar('c', 50) + ' 1 1 1'#10#9'x'#10));
  finally
    Blame.Free;
  end;
end;

procedure TBlameTest.TestParseGarbage;
var
  Blame: TGittanBlame;
begin
  Blame := TGittanBlame.Create;
  try
    AssertFalse(Blame.Parse(''));
    AssertFalse(Blame.Parse('fatal: no such path'#10));
    AssertEquals(0, Blame.LineCount);
  finally
    Blame.Free;
  end;
end;

procedure TBlameTest.TestAge;
const
  Day = 86400;
  Now = 2000000000;
begin
  AssertEquals('today', BlameAge(Now, Now));
  AssertEquals('today', BlameAge(Now - Day + 1, Now));
  AssertEquals('future dates count as today', 'today', BlameAge(Now + Day, Now));
  AssertEquals('1d', BlameAge(Now - Day, Now));
  AssertEquals('13d', BlameAge(Now - 13 * Day, Now));
  AssertEquals('2w', BlameAge(Now - 14 * Day, Now));
  AssertEquals('8w', BlameAge(Now - 59 * Day, Now));
  AssertEquals('2mo', BlameAge(Now - 60 * Day, Now));
  AssertEquals('12mo', BlameAge(Now - 364 * Day, Now));
  AssertEquals('1y', BlameAge(Now - 365 * Day, Now));
  AssertEquals('3y', BlameAge(Now - 3 * 365 * Day - 10 * Day, Now));
end;

initialization
  RegisterTest(TBlameTest);

end.
