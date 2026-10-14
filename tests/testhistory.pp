unit testhistory;

{** Tests of gittan.history: the reading of git log's output as
  TGittanRepo.LineHistory formats it. The history of a real repository
  is tested in testgit. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.history;

type
  THistoryTest = class(TTestCase)
  published
    procedure TestParse;
    procedure TestParseDropsCommitWithoutHunk;
    procedure TestParseEmpty;
    procedure TestPrependTruncate;
    procedure TestLayers;
  end;

implementation

const
  HashA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  HashB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

{ Two commits, newest first: A changed one line of the range in one
  hunk, B added the range in two hunks. The header is followed by a
  blank line and the diff's own header lines; a "no newline" note sits
  after the last line of B, and a blank line between the commits. A
  context line of B holds a bare carriage return. }
function Sample: string;
begin
  Result :=
    #1 + HashA + #31'Anna Andersson'#31'1700086400'#31'Second, with a space'#10 +
    #10 +
    'diff --git a/src/a.txt b/src/a.txt'#10 +
    'index 1111111..2222222 100644'#10 +
    '--- a/src/a.txt'#10 +
    '+++ b/src/a.txt'#10 +
    '@@ -10,3 +12,3 @@ procedure Foo;'#10 +
    ' begin'#10 +
    '-  old;'#10 +
    '+  new;'#10 +
    ' end;'#10 +
    #10 +
    #1 + HashB + #31'Bo'#31'1700000000'#31'First'#10 +
    #10 +
    'diff --git a/src/a.txt b/src/a.txt'#10 +
    'new file mode 100644'#10 +
    '--- /dev/null'#10 +
    '+++ b/src/a.txt'#10 +
    '@@ -0,0 +1,2 @@'#10 +
    '+one'#10 +
    '+tw'#13'o'#10 +
    '@@ -5 +9,2 @@'#10 +
    ' five'#10 +
    '+six'#10 +
    '\ No newline at end of file'#10;
end;

procedure THistoryTest.TestParse;
var
  H: TGittanHistory;
begin
  H := TGittanHistory.Create;
  try
    AssertTrue(H.Parse(Sample));
    AssertEquals(2, H.Count);
    AssertEquals(HashA, H.Commits[0].Info.Hash);
    AssertEquals('Anna Andersson', H.Commits[0].Info.Author);
    AssertEquals(1700086400, H.Commits[0].Info.Time);
    AssertEquals('Second, with a space', H.Commits[0].Info.Summary);
    AssertFalse(H.Commits[0].Info.Uncommitted);
    AssertEquals(1, Length(H.Commits[0].Hunks));
    AssertEquals(10, H.Commits[0].Hunks[0].OldStart);
    AssertEquals(12, H.Commits[0].Hunks[0].NewStart);
    AssertEquals(4, Length(H.Commits[0].Hunks[0].Lines));
    AssertEquals(' begin', H.Commits[0].Hunks[0].Lines[0]);
    AssertEquals('-  old;', H.Commits[0].Hunks[0].Lines[1]);
    AssertEquals('+  new;', H.Commits[0].Hunks[0].Lines[2]);
    AssertEquals(' end;', H.Commits[0].Hunks[0].Lines[3]);

    AssertEquals(HashB, H.Commits[1].Info.Hash);
    AssertEquals('Bo', H.Commits[1].Info.Author);
    AssertEquals(2, Length(H.Commits[1].Hunks));
    AssertEquals(0, H.Commits[1].Hunks[0].OldStart);
    AssertEquals(1, H.Commits[1].Hunks[0].NewStart);
    AssertEquals(2, Length(H.Commits[1].Hunks[0].Lines));
    AssertEquals('+tw'#13'o', H.Commits[1].Hunks[0].Lines[1]);
    AssertEquals(5, H.Commits[1].Hunks[1].OldStart);
    AssertEquals(9, H.Commits[1].Hunks[1].NewStart);
    AssertEquals('the no-newline note is not a line', 2, Length(H.Commits[1].Hunks[1].Lines));
    AssertEquals('+six', H.Commits[1].Hunks[1].Lines[1]);
  finally
    H.Free;
  end;
end;

procedure THistoryTest.TestParseDropsCommitWithoutHunk;
var
  H: TGittanHistory;
begin
  H := TGittanHistory.Create;
  try
    AssertTrue(H.Parse(#1 + HashA + #31'Anna'#31'1'#31'Merge'#10#10 + Sample));
    AssertEquals(2, H.Count);
    AssertEquals('Second, with a space', H.Commits[0].Info.Summary);
  finally
    H.Free;
  end;
end;

procedure THistoryTest.TestParseEmpty;
var
  H: TGittanHistory;
begin
  H := TGittanHistory.Create;
  try
    AssertFalse(H.Parse(''));
    AssertEquals(0, H.Count);
    AssertFalse('a commit without a hunk', H.Parse(#1 + HashA + #31'Anna'#31'1'#31'x'#10));
  finally
    H.Free;
  end;
end;

procedure THistoryTest.TestPrependTruncate;
var
  H: TGittanHistory;
  C: TGittanHistoryCommit;
begin
  H := TGittanHistory.Create;
  try
    AssertTrue(H.Parse(Sample));
    C := Default(TGittanHistoryCommit);
    C.Info.Uncommitted := True;
    SetLength(C.Hunks, 1);
    C.Hunks[0].OldStart := 1;
    C.Hunks[0].NewStart := 1;
    C.Hunks[0].Lines := ['+x'];
    H.Prepend(C);
    AssertEquals(3, H.Count);
    AssertTrue(H.Commits[0].Info.Uncommitted);
    AssertEquals(HashA, H.Commits[1].Info.Hash);
    AssertEquals(HashB, H.Commits[2].Info.Hash);
    H.Truncate(2);
    AssertEquals(2, H.Count);
    AssertEquals(HashA, H.Commits[1].Info.Hash);
    H.Truncate(5);
    AssertEquals(2, H.Count);
  finally
    H.Free;
  end;
end;

{ Newest first: the second commit changed b1 to b2 and added d, the
  first changed b0 to b1 and removed x. The layers are the newest range
  with b's earlier versions under it and x, removed after b1, under
  them. }
procedure THistoryTest.TestLayers;
var
  H: TGittanHistory;
  Rows: TGittanHistoryRows;
begin
  H := TGittanHistory.Create;
  try
    AssertTrue(H.Parse(
      #1 + HashA + #31'Anna'#31'2'#31'second'#10 +
      '@@ -10,3 +10,4 @@'#10 +
      ' a'#10 + '-b1'#10 + '+b2'#10 + ' c'#10 + '+d'#10 +
      #1 + HashB + #31'Bo'#31'1'#31'first'#10 +
      '@@ -10,4 +10,3 @@'#10 +
      ' a'#10 + '-b0'#10 + '+b1'#10 + '-x'#10 + ' c'#10));
    Rows := H.Layers;
    AssertEquals(7, Length(Rows));
    AssertEquals('a', Rows[0].Text);
    AssertTrue(Rows[0].Kind = hrCurrent);
    AssertEquals('older than the history', -1, Rows[0].Commit);
    AssertEquals(10, Rows[0].Line);
    AssertEquals(0, Rows[0].Depth);
    AssertEquals('b2', Rows[1].Text);
    AssertTrue(Rows[1].Kind = hrCurrent);
    AssertEquals(0, Rows[1].Commit);
    AssertEquals(11, Rows[1].Line);
    AssertEquals('b1', Rows[2].Text);
    AssertTrue(Rows[2].Kind = hrOld);
    AssertEquals(1, Rows[2].Commit);
    AssertEquals(1, Rows[2].Depth);
    AssertEquals('b0', Rows[3].Text);
    AssertTrue(Rows[3].Kind = hrOld);
    AssertEquals(-1, Rows[3].Commit);
    AssertEquals(2, Rows[3].Depth);
    AssertEquals('x', Rows[4].Text);
    AssertTrue(Rows[4].Kind = hrRemoved);
    AssertEquals(-1, Rows[4].Commit);
    AssertEquals(1, Rows[4].RemovedBy);
    AssertEquals('c', Rows[5].Text);
    AssertEquals(12, Rows[5].Line);
    AssertEquals('d', Rows[6].Text);
    AssertEquals(0, Rows[6].Commit);
    AssertEquals(13, Rows[6].Line);
    AssertEquals('d is new', 0, Rows[6].Depth);
  finally
    H.Free;
  end;
end;

initialization
  RegisterTest(THistoryTest);

end.
