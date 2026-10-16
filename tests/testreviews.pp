unit testreviews;

{** Tests of gittan.reviews: GitHub's answer for the review threads of a
  pull request, the mapping of a line through a diff and the age of a
  comment. The fetch itself is not tested; it needs the network. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, fpcunit, testregistry, gittan.reviews;

type
  TReviewsTest = class(TTestCase)
  published
    procedure TestParseThreads;
    procedure TestParsePages;
    procedure TestParseNotAnAnswer;
    procedure TestParseNotes;
    procedure TestMapLineWithoutDiff;
    procedure TestMapLineShifted;
    procedure TestMapLineChanged;
    procedure TestMapLineRemoved;
    procedure TestReviewAge;
  end;

implementation

const
  Answer =
    '{"data":{"repository":{"pullRequest":{"headRefOid":"abc123","reviewThreads":{' +
    '"pageInfo":{"hasNextPage":true,"endCursor":"Y3Vy"},"nodes":[' +
    '{"isResolved":false,"isOutdated":false,"path":"src/a.pas","line":12,"startLine":10,' +
    '"originalLine":11,"diffSide":"RIGHT","subjectType":"LINE","comments":{"nodes":[' +
    '{"author":{"login":"alice"},"body":"Why not\r\nhere?","createdAt":"2026-10-01T08:30:00Z",' +
    '"url":"https://github.com/o/r/pull/3#discussion_r1"},' +
    '{"author":null,"body":"Fixed.","createdAt":"2026-10-02T08:30:00Z","url":""}]}},' +
    '{"isResolved":true,"isOutdated":true,"path":"b.pas","line":null,"startLine":null,' +
    '"originalLine":4,"diffSide":"LEFT","subjectType":"LINE","comments":{"nodes":[' +
    '{"author":{"login":"bob"},"body":"Gone","createdAt":"2026-10-03T00:00:00Z","url":""}]}},' +
    '{"isResolved":false,"isOutdated":false,"path":"c.pas","line":null,"startLine":null,' +
    '"originalLine":null,"diffSide":"RIGHT","subjectType":"FILE","comments":{"nodes":[' +
    '{"author":{"login":"carol"},"body":"Whole file","createdAt":"","url":""}]}},' +
    '{"isResolved":false,"isOutdated":false,"path":"d.pas","line":1,"diffSide":"RIGHT",' +
    '"comments":{"nodes":[]}}' +
    ']}}}}}';

procedure TReviewsTest.TestParseThreads;
var
  T: TGittanReviewThreads;
  Head, Cursor: string;
  HasNext: boolean;
begin
  T := nil;
  AssertTrue(ParseReviewThreads(Answer, T, Head, HasNext, Cursor));
  AssertEquals('abc123', Head);
  AssertTrue(HasNext);
  AssertEquals('Y3Vy', Cursor);
  AssertEquals('a thread without comments is left out', 3, Length(T));
  AssertEquals('src/a.pas', T[0].Path);
  AssertEquals(12, T[0].Line);
  AssertEquals(10, T[0].StartLine);
  AssertEquals(11, T[0].OriginalLine);
  AssertFalse(T[0].LeftSide);
  AssertFalse(T[0].Resolved);
  AssertEquals(2, Length(T[0].Comments));
  AssertEquals('alice', T[0].Comments[0].Author);
  AssertEquals('Why not'#10'here?', T[0].Comments[0].Body);
  AssertEquals('https://github.com/o/r/pull/3#discussion_r1', T[0].Comments[0].Url);
  AssertEquals(EncodeDateTime(2026, 10, 1, 8, 30, 0, 0), T[0].Comments[0].Created);
  AssertEquals('a deleted account', 'ghost', T[0].Comments[1].Author);
  AssertEquals(0, T[1].Line);
  AssertEquals(4, T[1].OriginalLine);
  AssertTrue(T[1].LeftSide);
  AssertTrue(T[1].Resolved);
  AssertTrue(T[1].Outdated);
  AssertTrue(T[2].OnFile);
  AssertEquals(0.0, T[2].Comments[0].Created);
  AssertEquals(2, OpenThreads(T));
end;

procedure TReviewsTest.TestParsePages;
var
  T: TGittanReviewThreads;
  Head, Cursor: string;
  HasNext: boolean;
begin
  T := nil;
  AssertTrue(ParseReviewThreads(Answer, T, Head, HasNext, Cursor));
  AssertTrue(ParseReviewThreads(StringReplace(Answer, '"hasNextPage":true',
    '"hasNextPage":false', []), T, Head, HasNext, Cursor));
  AssertEquals('a page adds to the threads', 6, Length(T));
  AssertFalse(HasNext);
end;

procedure TReviewsTest.TestParseNotAnAnswer;
var
  T: TGittanReviewThreads;
  Head, Cursor: string;
  HasNext: boolean;
begin
  T := nil;
  AssertFalse(ParseReviewThreads('not json', T, Head, HasNext, Cursor));
  AssertFalse(ParseReviewThreads('{"data":{"repository":{"pullRequest":null}}}',
    T, Head, HasNext, Cursor));
  AssertFalse(ParseReviewThreads('{"errors":[{"message":"x"}]}', T, Head, HasNext, Cursor));
  AssertEquals(0, Length(T));
end;

const
  NotesAnswer =
    '{"data":{"repository":{"pullRequest":{"headRefOid":"abc123",' +
    '"reviews":{"nodes":[' +
    '{"state":"COMMENTED","body":"","author":{"login":"alice"},' +
    '"submittedAt":"2026-10-01T09:00:00Z","url":"r1"},' +
    '{"state":"CHANGES_REQUESTED","body":"Please fix\r\nthis.","author":{"login":"bob"},' +
    '"submittedAt":"2026-10-02T09:00:00Z","url":"r2"},' +
    '{"state":"PENDING","body":"Draft","author":{"login":"bob"},"submittedAt":null,"url":"r3"},' +
    '{"state":"APPROVED","body":"","author":null,"submittedAt":"2026-10-04T09:00:00Z","url":"r4"}]},' +
    '"comments":{"nodes":[' +
    '{"author":{"login":"carol"},"body":"Looks big.","createdAt":"2026-10-03T09:00:00Z","url":"c1"},' +
    '{"author":{"login":"carol"},"body":"  ","createdAt":"2026-10-03T10:00:00Z","url":"c2"},' +
    '{"author":{"login":"dave"},"body":"First!","createdAt":"2026-09-30T09:00:00Z","url":"c3"}]},' +
    '"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}';

procedure TReviewsTest.TestParseNotes;
var
  N: TGittanPullNotes;
begin
  AssertTrue(ParsePullNotes(NotesAnswer, N));
  AssertEquals('empty comments, line-only and pending reviews are left out', 4, Length(N));
  AssertEquals('oldest first', 'c3', N[0].Url);
  AssertTrue(N[0].Kind = pnComment);
  AssertEquals('r2', N[1].Url);
  AssertTrue(N[1].Kind = pnChangesRequested);
  AssertEquals('bob', N[1].Author);
  AssertEquals('Please fix'#10'this.', N[1].Body);
  AssertEquals(EncodeDateTime(2026, 10, 2, 9, 0, 0, 0), N[1].Created);
  AssertEquals('c1', N[2].Url);
  AssertEquals('an approval without text is kept', 'r4', N[3].Url);
  AssertTrue(N[3].Kind = pnApproved);
  AssertEquals('ghost', N[3].Author);
  AssertTrue('threads alone have no notes', ParsePullNotes(Answer, N));
  AssertEquals(0, Length(N));
  AssertFalse(ParsePullNotes('not json', N));
end;

procedure TReviewsTest.TestMapLineWithoutDiff;
begin
  AssertEquals(7, MapLine('', 7));
end;

const
  { Two lines added after line 3, line 10 replaced by three, lines 20
    and 21 removed. }
  Diff =
    'diff --git a/f b/f'#10'index 1..2 100644'#10'--- a/f'#10'+++ b/f'#10 +
    '@@ -3,0 +4,2 @@ x'#10'+a'#10'+b'#10 +
    '@@ -10 +12,3 @@ y'#10'-old'#10'+n1'#10'+n2'#10'+n3'#10 +
    '@@ -20,2 +23,0 @@ z'#10'-r1'#10'-r2'#10;

procedure TReviewsTest.TestMapLineShifted;
begin
  AssertEquals('above every change', 3, MapLine(Diff, 3));
  AssertEquals('below the insertion', 6, MapLine(Diff, 4));
  AssertEquals(11, MapLine(Diff, 9));
  AssertEquals('below the replacement', 15, MapLine(Diff, 11));
  AssertEquals(23, MapLine(Diff, 19));
  AssertEquals('below the removal', 24, MapLine(Diff, 22));
end;

procedure TReviewsTest.TestMapLineChanged;
begin
  AssertEquals('a replaced line goes to the first new one', 12, MapLine(Diff, 10));
end;

procedure TReviewsTest.TestMapLineRemoved;
begin
  AssertEquals('a removed line goes to the line before the removal', 23, MapLine(Diff, 20));
  AssertEquals(23, MapLine(Diff, 21));
  AssertEquals(1, MapLine('@@ -1 +0,0 @@'#10'-x'#10, 1));
end;

procedure TReviewsTest.TestReviewAge;
var
  Now_: TDateTime;
begin
  Now_ := EncodeDateTime(2026, 10, 15, 12, 0, 0, 0);
  AssertEquals('', ReviewAge(0, Now_));
  AssertEquals('just now', ReviewAge(IncSecond(Now_, -20), Now_));
  AssertEquals('1 minute ago', ReviewAge(IncMinute(Now_, -1), Now_));
  AssertEquals('5 minutes ago', ReviewAge(IncMinute(Now_, -5), Now_));
  AssertEquals('3 hours ago', ReviewAge(IncHour(Now_, -3), Now_));
  AssertEquals('yesterday', ReviewAge(IncHour(Now_, -30), Now_));
  AssertEquals('4 days ago', ReviewAge(IncDay(Now_, -4), Now_));
  AssertEquals('2026-08-01', ReviewAge(EncodeDateTime(2026, 8, 1, 0, 0, 0, 0), Now_));
end;

initialization
  RegisterTest(TReviewsTest);
end.
