unit testforge;

{** Tests of gittan.forge: which pull requests waiting for the user's
  review still are, and which have had an answer from someone but their
  author; with GitHub's answer to its forge query (gittan.github) read
  into them; and which local clone, among repositories made for the
  test, holds each. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, fpcunit, testregistry, gittan.forge, gittan.github,
  gittan.git;

type
  TForgeTest = class(TTestCase)
  published
    procedure TestParseAnswer;
    procedure TestParseErrors;
    procedure TestNeedsMyReview;
    procedure TestFeedback;
    procedure TestFilters;
    procedure TestNotes;
    procedure TestFindClones;
    procedure TestSiblingRepositories;
    procedure TestPullRequestOf;
    procedure TestRemoteHost;
    procedure TestForgeFor;
  end;

implementation

type
  { A forge on example.org, registered after GitHub, so the forge of a
    repository is picked by its remotes; it is never made. }
  TExampleForge = class(TGittanForge)
  public
    class function Name: string; override;
    class function CliName: string; override;
    class function HostsRemote(const AHost: string): boolean; override;
  end;

class function TExampleForge.Name: string;
begin
  Result := 'Example';
end;

class function TExampleForge.CliName: string;
begin
  Result := 'ex';
end;

class function TExampleForge.HostsRemote(const AHost: string): boolean;
begin
  Result := AHost = 'example.org';
end;

const
  Mine = '{"number":41,"title":"Watcher pace","url":"https://github.com/slicke/gittan/pull/41",' +
    '"isDraft":false,"state":"OPEN","reviewDecision":"REVIEW_REQUIRED",' +
    '"createdAt":"2026-10-24T10:00:00Z","updatedAt":"2026-10-25T10:00:00Z",' +
    '"author":{"login":"slicke"},"repository":{"nameWithOwner":"slicke/gittan"},' +
    '"headRefName":"develop","baseRefName":"main","viewerLatestReview":null,' +
    '"viewerLatestReviewRequest":null,' +
    '"comments":{"nodes":[{"author":{"__typename":"Bot","login":"codecov"}},' +
    '{"author":{"__typename":"User","login":"slicke"}}]},' +
    '"reviews":{"nodes":[{"author":{"__typename":"User","login":"Slicke"}}]},' +
    '"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}}';
  Review = '{"number":12,"title":"Fix the thing","url":"https://github.com/owner/repo/pull/12",' +
    '"isDraft":true,"state":"OPEN","reviewDecision":null,' +
    '"createdAt":"2026-10-20T12:34:56Z","updatedAt":"2026-10-22T08:00:00Z",' +
    '"author":{"login":"ada"},"repository":{"nameWithOwner":"owner/repo"},' +
    '"headRefName":"fix/thing","baseRefName":"main",' +
    '"viewerLatestReview":{"state":"APPROVED"},"viewerLatestReviewRequest":{"id":"RR_1"},' +
    '"comments":{"nodes":[]},' +
    '"reviews":{"nodes":[{"author":{"__typename":"User","login":"slicke"}}]},' +
    '"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}';
  Answer = '{"data":{"viewer":{"login":"slicke"},"mine":{"issueCount":1,"nodes":[' + Mine +
    ']},"review":{"issueCount":2,"nodes":[' + Review + ',{"__typename":"Issue"}]}}}';

procedure TForgeTest.TestParseAnswer;
var
  Login, Error: string;
  MinePulls, ReviewPulls: TGittanForgePulls;
begin
  AssertTrue(ParseForgeAnswer(Answer, Login, MinePulls, ReviewPulls, Error));
  AssertEquals('slicke', Login);
  AssertEquals('', Error);
  AssertEquals(1, Length(MinePulls));
  AssertEquals('slicke/gittan', MinePulls[0].Repo);
  AssertEquals(41, MinePulls[0].Number);
  AssertEquals('Watcher pace', MinePulls[0].Title);
  AssertEquals('https://github.com/slicke/gittan/pull/41', MinePulls[0].Url);
  AssertEquals('slicke', MinePulls[0].Author);
  AssertEquals('develop', MinePulls[0].HeadRef);
  AssertEquals('main', MinePulls[0].BaseRef);
  AssertTrue('open', MinePulls[0].State = prOpen);
  AssertTrue('review required', MinePulls[0].ReviewDecision = rdReviewRequired);
  AssertTrue('checks passed', MinePulls[0].Checks = chkPassed);
  AssertTrue('no review of mine', MinePulls[0].MyReview = rvNone);
  AssertFalse(MinePulls[0].Requested);
  AssertFalse(MinePulls[0].IsDraft);
  { A bot's comment and the author's own do not count. }
  AssertFalse(MinePulls[0].Feedback);
  AssertEquals(EncodeDateTime(2026, 10, 24, 10, 0, 0, 0), MinePulls[0].Created);
  AssertEquals(EncodeDateTime(2026, 10, 25, 10, 0, 0, 0), MinePulls[0].Updated);
  { The issue among the nodes is skipped. }
  AssertEquals(1, Length(ReviewPulls));
  AssertEquals('owner/repo', ReviewPulls[0].Repo);
  AssertEquals(12, ReviewPulls[0].Number);
  AssertTrue(ReviewPulls[0].IsDraft);
  AssertTrue('no decision', ReviewPulls[0].ReviewDecision = rdNone);
  AssertTrue('no checks', ReviewPulls[0].Checks = chkNone);
  AssertTrue('approved by me', ReviewPulls[0].MyReview = rvApproved);
  AssertTrue(ReviewPulls[0].Requested);
  AssertTrue(ReviewPulls[0].Feedback);
end;

procedure TForgeTest.TestParseErrors;
var
  Login, Error: string;
  MinePulls, ReviewPulls: TGittanForgePulls;
begin
  AssertFalse(ParseForgeAnswer('', Login, MinePulls, ReviewPulls, Error));
  AssertFalse(ParseForgeAnswer('not json', Login, MinePulls, ReviewPulls, Error));
  AssertFalse(ParseForgeAnswer('[]', Login, MinePulls, ReviewPulls, Error));
  AssertFalse(ParseForgeAnswer('{"errors":[{"message":"Bad credentials"}]}', Login,
    MinePulls, ReviewPulls, Error));
  AssertEquals('Bad credentials', Error);
  { Data without the searches is an answer with nothing in it. }
  AssertTrue(ParseForgeAnswer('{"data":{"viewer":{"login":"x"}}}', Login, MinePulls,
    ReviewPulls, Error));
  AssertEquals('x', Login);
  AssertEquals(0, Length(MinePulls));
  AssertEquals(0, Length(ReviewPulls));
end;

procedure TForgeTest.TestNeedsMyReview;
var
  Pull: TGittanForgePull;
  Pulls, Left: TGittanForgePulls;
begin
  Pull := Default(TGittanForgePull);
  AssertTrue(NeedsMyReview(Pull));
  Pull.MyReview := rvCommented;
  AssertTrue(NeedsMyReview(Pull));
  Pull.MyReview := rvDismissed;
  AssertTrue(NeedsMyReview(Pull));
  Pull.MyReview := rvApproved;
  AssertFalse(NeedsMyReview(Pull));
  Pull.MyReview := rvChangesRequested;
  AssertFalse(NeedsMyReview(Pull));
  { Asked again after the review. }
  Pull.Requested := True;
  AssertTrue(NeedsMyReview(Pull));
  SetLength(Pulls, 3);
  Pulls[0] := Default(TGittanForgePull);
  Pulls[0].Number := 1;
  Pulls[1] := Default(TGittanForgePull);
  Pulls[1].Number := 2;
  Pulls[1].MyReview := rvApproved;
  Pulls[2] := Pull;
  Pulls[2].Number := 3;
  Left := StillToReview(Pulls);
  AssertEquals(2, Length(Left));
  AssertEquals(1, Left[0].Number);
  AssertEquals(3, Left[1].Number);
  AssertEquals(0, Length(StillToReview(nil)));
end;

procedure TForgeTest.TestFeedback;
const
  Ghost = '{"data":{"mine":{"nodes":[{"number":1,"author":{"login":"me"},' +
    '"comments":{"nodes":[{"author":null}]}},{"number":2,"author":{"login":"me"}}]}}}';
var
  Login, Error: string;
  MinePulls, ReviewPulls, Left: TGittanForgePulls;
begin
  { A deleted user's comment is someone else's; no comments at all is
    no feedback. }
  AssertTrue(ParseForgeAnswer(Ghost, Login, MinePulls, ReviewPulls, Error));
  AssertEquals(2, Length(MinePulls));
  AssertTrue(MinePulls[0].Feedback);
  AssertFalse(MinePulls[1].Feedback);
  Left := WithFeedback(MinePulls);
  AssertEquals(1, Length(Left));
  AssertEquals(1, Left[0].Number);
  AssertEquals(0, Length(WithFeedback(nil)));
end;

procedure TForgeTest.TestFilters;
var
  Pulls, Left: TGittanForgePulls;
  Now_: TDateTime;
  i: integer;
begin
  Now_ := EncodeDateTime(2026, 10, 27, 12, 0, 0, 0);
  Pulls := nil;
  SetLength(Pulls, 4);
  for i := 0 to 3 do
  begin
    Pulls[i] := Default(TGittanForgePull);
    Pulls[i].Number := i + 1;
  end;
  Pulls[0].ReviewDecision := rdChangesRequested;
  Pulls[0].Feedback := True;
  Pulls[1].Checks := chkFailed;
  Pulls[1].IsDraft := True;
  Pulls[2].Requested := True;
  Pulls[2].Checks := chkPending;
  Pulls[3].ReviewDecision := rdApproved;
  AssertTrue(NeedsAttention(Pulls[0]));
  AssertTrue(NeedsAttention(Pulls[1]));
  AssertFalse(NeedsAttention(Pulls[2]));
  AssertFalse(NeedsAttention(Pulls[3]));
  AssertEquals(4, Length(FilterPulls(Pulls, [], Now_)));
  Left := FilterPulls(Pulls, [ffAttention], Now_);
  AssertEquals(2, Length(Left));
  AssertEquals(1, Left[0].Number);
  AssertEquals(2, Left[1].Number);
  { The filters together: every one must pass. }
  Left := FilterPulls(Pulls, [ffAttention, ffNoDrafts], Now_);
  AssertEquals(1, Length(Left));
  AssertEquals(1, Left[0].Number);
  Left := FilterPulls(Pulls, [ffAskedOfMe], Now_);
  AssertEquals(1, Length(Left));
  AssertEquals(3, Left[0].Number);
  AssertEquals(3, Length(FilterPulls(Pulls, [ffNoDrafts], Now_)));
  AssertEquals(1, Length(FilterPulls(Pulls, [ffFeedback], Now_)));
  AssertEquals(0, Length(FilterPulls(nil, [ffFeedback], Now_)));
  { Stale: unchanged for StaleDays, by the last change or else the
    opening; no dates at all is not stale. }
  Pulls[0].Created := IncDay(Now_, -100);
  Pulls[0].Updated := IncDay(Now_, -2);
  Pulls[1].Created := IncDay(Now_, -100);
  Pulls[1].Updated := IncDay(Now_, -31);
  Pulls[2].Created := IncDay(Now_, -40);
  AssertFalse(IsStale(Pulls[0], Now_));
  AssertTrue(IsStale(Pulls[1], Now_));
  AssertTrue(IsStale(Pulls[2], Now_));
  AssertFalse(IsStale(Pulls[3], Now_));
  Left := FilterPulls(Pulls, [ffStale], Now_);
  AssertEquals(2, Length(Left));
  AssertEquals(2, Left[0].Number);
  AssertEquals(3, Left[1].Number);
end;

procedure TForgeTest.TestNotes;
begin
  AssertEquals('Approved', ReviewDecisionNote(rdApproved));
  AssertEquals('Changes requested', ReviewDecisionNote(rdChangesRequested));
  AssertEquals('Review required', ReviewDecisionNote(rdReviewRequired));
  AssertEquals('', ReviewDecisionNote(rdNone));
end;

procedure RemoveTree(const ADir: string);
var
  Info: TSearchRec;
begin
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, Info) = 0 then
  try
    repeat
      if (Info.Name = '.') or (Info.Name = '..') then
        Continue;
      if Info.Attr and faDirectory <> 0 then
        RemoveTree(IncludeTrailingPathDelimiter(ADir) + Info.Name)
      else
        DeleteFile(IncludeTrailingPathDelimiter(ADir) + Info.Name);
    until FindNext(Info) <> 0;
  finally
    FindClose(Info);
  end;
  RemoveDir(ADir);
end;

{ A fork's clone has the repository it was forked from as a remote of
  its own; the first root that holds a repository wins, and a folder
  that is gone or no repository is passed over. }
procedure TForgeTest.TestFindClones;
var
  Dir, Output, Err: string;
  Roots: TStringList;
  Pulls: TGittanForgePulls;

  function MakeRepo(const AName: string; const AUrls: array of string): string;
  var
    i: integer;
  begin
    Result := Dir + AName;
    ForceDirectories(Result);
    AssertTrue(Err, RunGitIn(Result, ['init', '-q'], Output, Err));
    for i := 0 to High(AUrls) do
      AssertTrue(Err, RunGitIn(Result, ['remote', 'add', 'r' + IntToStr(i), AUrls[i]], Output,
        Err));
  end;

begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-forge-' + IntToStr(GetProcessID) +
    '-' + IntToStr(Random(MaxInt)) + PathDelim;
  Roots := TStringList.Create;
  try
    Roots.Add(Dir + 'gone');
    Roots.Add(MakeRepo('plain', []));
    ForceDirectories(Dir + 'folder');
    Roots.Add(Dir + 'folder');
    Roots.Add(MakeRepo('fork', ['git@github.com:me/bar.git', 'https://github.com/Foo/Bar.git']));
    Roots.Add(MakeRepo('second', ['https://github.com/foo/bar']));
    Roots.Add(MakeRepo('other', ['https://github.com/foo/barn.git']));
    SetLength(Pulls, 3);
    Pulls[0].Repo := 'foo/bar';
    Pulls[1].Repo := 'foo/barn';
    Pulls[2].Repo := 'foo/ba';
    Pulls[2].Clone := 'stale';
    FindClones(Pulls, Roots);
    AssertEquals(Dir + 'fork', Pulls[0].Clone);
    AssertEquals(Dir + 'other', Pulls[1].Clone);
    AssertEquals('', Pulls[2].Clone);
    Roots.Clear;
    FindClones(Pulls, Roots);
    AssertEquals('', Pulls[0].Clone);
  finally
    Roots.Free;
    RemoveTree(ExcludeTrailingPathDelimiter(Dir));
  end;
end;

{ A folder holding .git, a folder or a file, is a repository; others,
  and plain files, are not, and the folders of the repositories added
  are not looked beside again. }
procedure TForgeTest.TestSiblingRepositories;
var
  Dir: string;
  Roots: TStringList;

  procedure Touch(const APath: string);
  begin
    with TStringList.Create do
    try
      SaveToFile(APath);
    finally
      Free;
    end;
  end;

begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-siblings-' + IntToStr(GetProcessID) +
    '-' + IntToStr(Random(MaxInt)) + PathDelim;
  Roots := TStringList.Create;
  try
    ForceDirectories(Dir + 'kod' + PathDelim + 'b' + PathDelim + '.git');
    ForceDirectories(Dir + 'kod' + PathDelim + 'a' + PathDelim + '.git');
    ForceDirectories(Dir + 'kod' + PathDelim + 'here' + PathDelim + '.git');
    ForceDirectories(Dir + 'kod' + PathDelim + 'notes');
    ForceDirectories(Dir + 'kod' + PathDelim + 'wt');
    Touch(Dir + 'kod' + PathDelim + 'wt' + PathDelim + '.git');
    Touch(Dir + 'kod' + PathDelim + 'file.txt');
    ForceDirectories(Dir + 'kod' + PathDelim + 'a' + PathDelim + 'inner' + PathDelim + '.git');
    ForceDirectories(Dir + 'other' + PathDelim + 'c' + PathDelim + '.git');
    Roots.Add(Dir + 'kod' + PathDelim + 'here');
    Roots.Add(Dir + 'other' + PathDelim + 'c');
    Roots.Add(Dir + 'gone' + PathDelim + 'x');
    AddSiblingRepositories(Roots);
    AssertEquals(6, Roots.Count);
    AssertEquals(Dir + 'kod' + PathDelim + 'here', Roots[0]);
    AssertEquals(Dir + 'other' + PathDelim + 'c', Roots[1]);
    AssertEquals(Dir + 'gone' + PathDelim + 'x', Roots[2]);
    AssertEquals(Dir + 'kod' + PathDelim + 'a', Roots[3]);
    AssertEquals(Dir + 'kod' + PathDelim + 'b', Roots[4]);
    AssertEquals(Dir + 'kod' + PathDelim + 'wt', Roots[5]);
  finally
    Roots.Free;
    RemoveTree(ExcludeTrailingPathDelimiter(Dir));
  end;
end;

{ The forge page's pull request as the repository's own are kept: what
  both records have, the rest empty. }
procedure TForgeTest.TestPullRequestOf;
var
  Login, Error: string;
  MinePulls, ReviewPulls: TGittanForgePulls;
  Pull: TGittanPullRequest;
begin
  AssertTrue(ParseForgeAnswer(Answer, Login, MinePulls, ReviewPulls, Error));
  Pull := PullRequestOf(ReviewPulls[0]);
  AssertEquals(12, Pull.Number);
  AssertEquals('owner/repo', Pull.Repo);
  AssertEquals('Fix the thing', Pull.Title);
  AssertEquals('https://github.com/owner/repo/pull/12', Pull.Url);
  AssertEquals('fix/thing', Pull.HeadRef);
  AssertEquals('main', Pull.BaseRef);
  AssertEquals('ada', Pull.Author);
  AssertTrue(Pull.IsDraft);
  AssertTrue(Pull.State = ReviewPulls[0].State);
  AssertEquals(EncodeDateTime(2026, 10, 20, 12, 34, 56, 0), Pull.Created);
  AssertEquals(0, Pull.ChecksPending);
  AssertEquals('', Pull.Labels);
end;

procedure TForgeTest.TestRemoteHost;
begin
  AssertEquals('github.com', RemoteHost('https://github.com/slicke/gittan.git'));
  AssertEquals('github.com', RemoteHost('https://user:token@GitHub.com/slicke/gittan'));
  AssertEquals('github.com', RemoteHost('git@github.com:slicke/gittan.git'));
  AssertEquals('github.com', RemoteHost('ssh://git@github.com:22/slicke/gittan.git'));
  AssertEquals('gitlab.example.org', RemoteHost('gitlab.example.org:group/sub/repo.git'));
  AssertEquals('', RemoteHost('/Volumes/Projects/git/trailhead.git'));
  AssertEquals('', RemoteHost('../trailhead.git'));
  AssertEquals('', RemoteHost('C:\git\trailhead.git'));
  AssertEquals('', RemoteHost('C:/git/trailhead.git'));
  AssertEquals('', RemoteHost('file:///srv/git/trailhead.git'));
  AssertEquals('', RemoteHost('./a:b'));
end;

procedure TForgeTest.TestForgeFor;
begin
  AssertTrue(ForgeClassFor('remote.origin.url git@github.com:slicke/gittan.git'#10) =
    TGittanGitHubForge);
  AssertTrue(ForgeClassFor('remote.origin.url https://example.org/a/b.git'#10) =
    TExampleForge);
  { The remotes in order: the first on a known forge decides. }
  AssertTrue(ForgeClassFor('remote.local.url /srv/git/b.git'#10 +
    'remote.origin.url https://example.org/a/b.git'#10 +
    'remote.up.url https://github.com/a/b'#10) = TExampleForge);
  AssertTrue(ForgeClassFor('remote.origin.url https://bitbucket.org/a/b.git'#10) = nil);
  AssertTrue(ForgeClassFor('') = nil);
  { Where no repository decides, the first registered. }
  AssertTrue(ForgeClass = TGittanGitHubForge);
end;

initialization
  RegisterForge(TExampleForge);
  RegisterTest(TForgeTest);

end.
