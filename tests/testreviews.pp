unit testreviews;

{** Tests of gittan.reviews: the review threads of a pull request as
  gittan.github reads them from GitHub's answer, the mapping of a line
  through a diff and the age of a comment. The fetch itself is not
  tested; it needs the network. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, fpcunit, testregistry, gittan.reviews, gittan.github;

type
  TReviewsTest = class(TTestCase)
  private
    function IsFile(const APath: string): boolean;
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
    procedure TestCommentMarkdown;
    procedure TestCommentMarkdownCode;
    procedure TestCommentParts;
    procedure TestLinkFilePaths;
    procedure TestLinkFilePathsLeftAlone;
    procedure TestFileOfLink;
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

procedure TReviewsTest.TestCommentMarkdown;
const
  NL = LineEnding;
begin
  AssertEquals('plain Markdown as it is', '**Bug**: off by one.' + NL + NL + 'Use `<=`.',
    CommentMarkdown('**Bug**: off by one.'#10#10'Use `<=`.'));
  AssertEquals('comments go', 'Before' + NL + NL + 'after',
    CommentMarkdown('Before'#10'<!-- fingerprinting:abc'#10'more -->'#10#10'after<!-- x -->'));
  AssertEquals('a details block folds to its summary',
    'Intro' + NL + NL + '▸ 🤖 Prompt for AI Agents' + NL + NL + 'Outro',
    CommentMarkdown('Intro'#10'<details>'#10'<summary>🤖 Prompt for AI Agents</summary>'#10#10 +
    'Inside'#10'<details><summary>Nested</summary>Deeper</details>'#10'```'#10'</details>'#10'```'#10 +
    '</details>'#10'Outro'));
  AssertEquals('a details block without summary', '▸ Details',
    CommentMarkdown('<details>Hidden</details>'));
  AssertEquals('one left open', 'A' + NL + NL + '▸ Open',
    CommentMarkdown('A'#10'<details><summary>Open</summary>'#10'never closed'));
  AssertEquals('img and a', 'See [the docs](https://x.y/d) logo',
    CommentMarkdown('See <a href="https://x.y/d">the docs</a> <img src="l.png" alt="logo"/>'));
  AssertEquals('block tags break lines', 'One' + NL + NL + 'Two' + NL + NL + '- three',
    CommentMarkdown('<p>One</p><div>Two<ul><li>three</li></ul></div>'));
  AssertEquals('headings are bold', '**Summary by CodeRabbit**' + NL + NL + '**Walk** x' + NL + '#hashtag',
    CommentMarkdown('## Summary by CodeRabbit ##'#10#10'**Walk** x'#10'#hashtag'));
  AssertEquals('other tags are left', 'Vec<T> and <b>bold</b><br> a < b',
    CommentMarkdown('Vec<T> and <b>bold</b><br/> a < b'));
end;

procedure TReviewsTest.TestCommentMarkdownCode;
const
  NL = LineEnding;
begin
  AssertEquals('a fence keeps its tags and blank lines',
    '```html' + NL + '<p>x</p>' + NL + NL + NL + '<!-- y -->' + NL + '```',
    CommentMarkdown('```html'#10'<p>x</p>'#10#10#10'<!-- y -->'#10'```'));
  AssertEquals('a heading in a fence stays', '```' + NL + '# not a heading' + NL + '```',
    CommentMarkdown('```'#10'# not a heading'#10'```'));
  AssertEquals('a code span too', 'Write `<details>` here',
    CommentMarkdown('Write `<details>` here'));
  AssertEquals('a suggestion stays', '```suggestion' + NL + 'x := 1;' + NL + '```',
    CommentMarkdown('```suggestion'#10'x := 1;'#10'```'));
end;

procedure TReviewsTest.TestCommentParts;
var
  P: TGittanCommentParts;
begin
  P := CommentParts('Intro'#10'<details>'#10'<summary>Outer <b>one</b></summary>'#10#10 +
    'Inside'#10'<details><summary>Nested</summary>Deeper</details>'#10'```'#10'</details>'#10'```'#10 +
    'After'#10'</details>'#10'<details>Bare</details>'#10'Outro');
  AssertEquals(9, Length(P));
  AssertTrue(P[0].Kind = cpText);
  AssertEquals(0, P[0].Depth);
  AssertEquals('Intro', P[0].Text);
  AssertTrue(P[1].Kind = cpDetails);
  AssertEquals(0, P[1].Depth);
  AssertEquals('Outer <b>one</b>', P[1].Text);
  AssertEquals(1, P[2].Depth);
  AssertEquals('Inside', P[2].Text);
  AssertTrue(P[3].Kind = cpDetails);
  AssertEquals(1, P[3].Depth);
  AssertEquals('Nested', P[3].Text);
  AssertEquals(2, P[4].Depth);
  AssertEquals('Deeper', P[4].Text);
  AssertEquals('a fence inside keeps its tag', 1, P[5].Depth);
  AssertEquals('```' + LineEnding + '</details>' + LineEnding + '```' + LineEnding + 'After', P[5].Text);
  AssertTrue(P[6].Kind = cpDetails);
  AssertEquals(0, P[6].Depth);
  AssertEquals('Details', P[6].Text);
  AssertEquals('the text of a block without summary', 1, P[7].Depth);
  AssertEquals('Bare', P[7].Text);
  AssertEquals(0, P[8].Depth);
  AssertEquals('Outro', P[8].Text);
end;

{ The files of a pretend repository. }
function TReviewsTest.IsFile(const APath: string): boolean;
begin
  Result := (APath = 'src/ui/umain.pp') or (APath = 'README.md') or (APath = 'a/b-c.pp');
end;

procedure TReviewsTest.TestLinkFilePaths;
begin
  AssertEquals('See [src/ui/umain.pp](gittan-file:src/ui/umain.pp) here.',
    LinkFilePaths('See src/ui/umain.pp here.', @IsFile));
  AssertEquals('the line', '[src/ui/umain.pp:42](gittan-file:src/ui/umain.pp#L42), then',
    LinkFilePaths('src/ui/umain.pp:42, then', @IsFile));
  AssertEquals('a range', 'In [src/ui/umain.pp:42-50](gittan-file:src/ui/umain.pp#L42).',
    LinkFilePaths('In src/ui/umain.pp:42-50.', @IsFile));
  AssertEquals('GitHub''s anchor', '[./src/ui/umain.pp#L7-L9](gittan-file:src/ui/umain.pp#L7)',
    LinkFilePaths('./src/ui/umain.pp#L7-L9', @IsFile));
  AssertEquals('a name alone with a dot', '([README.md](gittan-file:README.md))',
    LinkFilePaths('(README.md)', @IsFile));
  AssertEquals('a dash in it', '[a/b-c.pp](gittan-file:a/b-c.pp)', LinkFilePaths('a/b-c.pp', @IsFile));
  AssertEquals('code', 'Open [`src/ui/umain.pp:3`](gittan-file:src/ui/umain.pp#L3)',
    LinkFilePaths('Open `src/ui/umain.pp:3`', @IsFile));
  AssertEquals('escaped backticks', '\`[README.md](gittan-file:README.md)\`',
    LinkFilePaths('\`README.md\`', @IsFile));
  AssertEquals('lines', 'x [README.md](gittan-file:README.md)' + LineEnding +
    'y [README.md](gittan-file:README.md)' + LineEnding,
    LinkFilePaths('x README.md'#10'y README.md'#10, @IsFile));
end;

procedure TReviewsTest.TestLinkFilePathsLeftAlone;
const
  Fenced = '```' + LineEnding + 'src/ui/umain.pp' + LineEnding + '```';
begin
  AssertEquals('not a file', 'see src/ui/other.pp and 1.2.3',
    LinkFilePaths('see src/ui/other.pp and 1.2.3', @IsFile));
  AssertEquals('a link', '[x](src/ui/umain.pp) and [src/ui/umain.pp](https://a.b)',
    LinkFilePaths('[x](src/ui/umain.pp) and [src/ui/umain.pp](https://a.b)', @IsFile));
  AssertEquals('a URL', 'https://example.com/src/ui/umain.pp done',
    LinkFilePaths('https://example.com/src/ui/umain.pp done', @IsFile));
  AssertEquals('a tag', '<a href="README.md">', LinkFilePaths('<a href="README.md">', @IsFile));
  AssertEquals('fenced code', Fenced, LinkFilePaths(Fenced, @IsFile));
  AssertEquals('code with more in it', '`cat README.md`', LinkFilePaths('`cat README.md`', @IsFile));
  AssertEquals('part of a word', 'x@README.md', LinkFilePaths('x@README.md', @IsFile));
  AssertEquals('out of the repository', '../README.md /README.md',
    LinkFilePaths('../README.md /README.md', @IsFile));
end;

procedure TReviewsTest.TestFileOfLink;
var
  Path: string;
  Line: integer;
begin
  AssertTrue(FileOfLink('gittan-file:src/a.pp#L42', Path, Line));
  AssertEquals('src/a.pp', Path);
  AssertEquals(42, Line);
  AssertTrue(FileOfLink('gittan-file:README.md', Path, Line));
  AssertEquals('README.md', Path);
  AssertEquals(0, Line);
  AssertFalse(FileOfLink('https://github.com/o/r', Path, Line));
  AssertFalse(FileOfLink('gittan-file:', Path, Line));
end;

initialization
  RegisterTest(TReviewsTest);
end.
