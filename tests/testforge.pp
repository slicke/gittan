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
  gittan.git, testhelpers;

type
  TForgeTest = class(TTestCase)
  published
    procedure TestParseAnswer;
    procedure TestParseErrors;
    procedure TestNeedsMyReview;
    procedure TestMyReviewFromReviews;
    procedure TestFeedback;
    procedure TestChecks;
    procedure TestReviewNotes;
    procedure TestFilters;
    procedure TestKeys;
    procedure TestPresets;
    procedure TestOrder;
    procedure TestNotes;
    procedure TestFindClones;
    procedure TestSiblingRepositories;
    procedure TestPullRequestOf;
    procedure TestRemoteHost;
    procedure TestRemoteRepoPath;
    procedure TestForgeFor;
    procedure TestSshAlias;
    procedure TestKeepForge;
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
    '"headRefName":"develop","baseRefName":"main","viewerLatestReview":{"state":"COMMENTED"},' +
    '"reviewRequests":{"nodes":[{"requestedReviewer":{"__typename":"User","login":"anna"}},' +
    '{"requestedReviewer":{"__typename":"Team","name":"core"}},{"requestedReviewer":null}]},' +
    '"latestReviews":{"nodes":[{"state":"COMMENTED","author":{"__typename":"Bot",' +
    '"login":"coderabbitai"}},{"state":"APPROVED","author":{"__typename":"User",' +
    '"login":"bob"}}]},' +
    '"comments":{"nodes":[{"author":{"__typename":"Bot","login":"codecov"}},' +
    '{"author":{"__typename":"User","login":"slicke"}}]},' +
    '"reviews":{"nodes":[{"state":"COMMENTED","author":{"__typename":"User","login":"Slicke"}}]},' +
    '"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE","contexts":{' +
    '"pageInfo":{"hasNextPage":true},"nodes":[' +
    '{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"},' +
    '{"__typename":"CheckRun","name":"npm audit","status":"COMPLETED","conclusion":"FAILURE"},' +
    '{"__typename":"CheckRun","name":"lint","status":"IN_PROGRESS","conclusion":null},' +
    '{"__typename":"StatusContext","context":"approval","state":"FAILURE"}]}}}}]}}';
  Review = '{"number":12,"title":"Fix the thing","url":"https://github.com/owner/repo/pull/12",' +
    '"isDraft":true,"state":"OPEN","reviewDecision":null,' +
    '"createdAt":"2026-10-20T12:34:56Z","updatedAt":"2026-10-22T08:00:00Z",' +
    '"author":{"login":"ada"},"repository":{"nameWithOwner":"owner/repo"},' +
    '"headRefName":"fix/thing","baseRefName":"main",' +
    '"viewerLatestReview":{"state":"COMMENTED"},' +
    '"reviewRequests":{"nodes":[{"requestedReviewer":{"__typename":"User","login":"Slicke"}}]},' +
    '"latestReviews":{"nodes":[{"state":"COMMENTED","author":{"login":"slicke"}}]},' +
    '"comments":{"nodes":[]},' +
    '"reviews":{"nodes":[{"state":"APPROVED","author":{"__typename":"User","login":"slicke"}},' +
    '{"state":"COMMENTED","author":{"__typename":"User","login":"slicke"}}]},' +
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
  AssertTrue('checks failed', MinePulls[0].Checks = chkFailed);
  AssertTrue('a comment of mine is no verdict', MinePulls[0].MyReview = rvCommented);
  AssertFalse(MinePulls[0].Requested);
  AssertFalse(MinePulls[0].IsDraft);
  { Who is asked: the user and the team, a request of nobody skipped. }
  AssertEquals(2, Length(MinePulls[0].RequestedOf));
  AssertEquals('anna', MinePulls[0].RequestedOf[0]);
  AssertEquals('core', MinePulls[0].RequestedOf[1]);
  AssertEquals(2, Length(MinePulls[0].Reviews));
  AssertEquals('coderabbitai', MinePulls[0].Reviews[0].Login);
  AssertTrue(MinePulls[0].Reviews[0].Verdict = rvCommented);
  AssertEquals('bob', MinePulls[0].Reviews[1].Login);
  AssertTrue(MinePulls[0].Reviews[1].Verdict = rvApproved);
  { The checks by name: a check run by its conclusion, one still
    running pending, a status context by its state. }
  AssertEquals(4, Length(MinePulls[0].CheckList));
  AssertTrue('more checks than listed', MinePulls[0].ChecksMore);
  AssertFalse(ReviewPulls[0].ChecksMore);
  AssertEquals('build', MinePulls[0].CheckList[0].Name);
  AssertTrue(MinePulls[0].CheckList[0].State = chkPassed);
  AssertEquals('npm audit', MinePulls[0].CheckList[1].Name);
  AssertTrue(MinePulls[0].CheckList[1].State = chkFailed);
  AssertEquals('lint', MinePulls[0].CheckList[2].Name);
  AssertTrue(MinePulls[0].CheckList[2].State = chkPending);
  AssertEquals('approval', MinePulls[0].CheckList[3].Name);
  AssertTrue(MinePulls[0].CheckList[3].State = chkFailed);
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
  AssertEquals(0, Length(ReviewPulls[0].CheckList));
  AssertTrue('approved by me, the comment after it notwithstanding',
    ReviewPulls[0].MyReview = rvApproved);
  AssertTrue('asked in person, the case of the login aside', ReviewPulls[0].Requested);
  AssertEquals(1, Length(ReviewPulls[0].RequestedOf));
  AssertTrue(ReviewPulls[0].Feedback);
end;

procedure TForgeTest.TestMyReviewFromReviews;
const
  Head = '{"data":{"viewer":{"login":"me"},"review":{"nodes":[';
  Tail = ']}}}';
  { A dismissal after the approval undoes it; a request for changes
    after a comment stands; a team's request is not one in person;
    a pending review says nothing; without a login the forge's own
    latest review stands. }
  Pulls = '{"number":1,"viewerLatestReview":{"state":"DISMISSED"},"reviews":{"nodes":[' +
    '{"state":"APPROVED","author":{"login":"me"}},{"state":"DISMISSED","author":{"login":"me"}}]}},' +
    '{"number":2,"viewerLatestReview":{"state":"CHANGES_REQUESTED"},"reviews":{"nodes":[' +
    '{"state":"COMMENTED","author":{"login":"me"}},{"state":"CHANGES_REQUESTED",' +
    '"author":{"login":"me"}},{"state":"APPROVED","author":{"login":"other"}}]},' +
    '"reviewRequests":{"nodes":[{"requestedReviewer":{"__typename":"Team","name":"me"}}]}},' +
    '{"number":3,"viewerLatestReview":{"state":"PENDING"},"reviews":{"nodes":[' +
    '{"state":"PENDING","author":{"login":"me"}}]}}';
var
  Login, Error: string;
  MinePulls, ReviewPulls: TGittanForgePulls;
begin
  AssertTrue(ParseForgeAnswer(Head + Pulls + Tail, Login, MinePulls, ReviewPulls, Error));
  AssertEquals(3, Length(ReviewPulls));
  AssertTrue('dismissed', ReviewPulls[0].MyReview = rvDismissed);
  AssertTrue('changes requested', ReviewPulls[1].MyReview = rvChangesRequested);
  AssertFalse('a team of my name is not me', ReviewPulls[1].Requested);
  AssertEquals(1, Length(ReviewPulls[1].RequestedOf));
  AssertTrue('pending says nothing', ReviewPulls[2].MyReview = rvNone);
  AssertTrue(ParseForgeAnswer('{"data":{"review":{"nodes":[{"number":4,"viewerLatestReview":' +
    '{"state":"APPROVED"},"reviews":{"nodes":[{"state":"COMMENTED","author":{"login":"me"}}]}}]}}}',
    Login, MinePulls, ReviewPulls, Error));
  AssertTrue('no login: the forge''s word', ReviewPulls[0].MyReview = rvApproved);
end;

procedure TForgeTest.TestParseErrors;
var
  Login, Error, Url: string;
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
  { The picture's address, when the viewer has one. }
  AssertTrue(ParseForgeAnswer('{"data":{"viewer":{"login":"x","avatarUrl":' +
    '"https://avatars.example.com/u/1?s=128"}}}', Login, Url, MinePulls, ReviewPulls, Error));
  AssertEquals('https://avatars.example.com/u/1?s=128', Url);
  AssertTrue(ParseForgeAnswer('{"data":{"viewer":{"login":"x"}}}', Login, Url, MinePulls,
    ReviewPulls, Error));
  AssertEquals('', Url);
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
  { One merged or closed a moment ago, which the search still lists. }
  Pull.State := prMerged;
  AssertFalse(NeedsMyReview(Pull));
  Pull.State := prClosed;
  AssertFalse(NeedsMyReview(Pull));
  Pull.State := prOpen;
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
  Pulls[1].State := prMerged;
  Pulls[1].MyReview := rvNone;
  Left := OpenPulls(Pulls);
  AssertEquals(2, Length(Left));
  AssertEquals(1, Left[0].Number);
  AssertEquals(3, Left[1].Number);
  AssertEquals(0, Length(OpenPulls(nil)));
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

procedure TForgeTest.TestChecks;
var
  Pull: TGittanForgePull;
  Ignored: TStringList;
begin
  Pull := Default(TGittanForgePull);
  Ignored := TStringList.Create;
  try
    { Without a list the forge's own sum stands. }
    Pull.Checks := chkPending;
    AssertTrue(ChecksState(Pull) = chkPending);
    AssertEquals('checks pending', PullChecksNote(Pull));
    Pull.Checks := chkPassed;
    AssertEquals('✓ checks', PullChecksNote(Pull));
    Pull.Checks := chkFailed;
    AssertEquals('checks failing', PullChecksNote(Pull));
    AssertEquals('', PullChecksDetail(Pull));
    Pull.Checks := chkNone;
    AssertEquals('', PullChecksNote(Pull));
    SetLength(Pull.CheckList, 4);
    Pull.CheckList[0].Name := 'build';
    Pull.CheckList[0].State := chkPassed;
    Pull.CheckList[1].Name := 'npm audit';
    Pull.CheckList[1].State := chkFailed;
    Pull.CheckList[2].Name := 'lint';
    Pull.CheckList[2].State := chkPending;
    Pull.CheckList[3].Name := 'approval';
    Pull.CheckList[3].State := chkFailed;
    AssertTrue('one fails', ChecksState(Pull) = chkFailed);
    AssertEquals('2 of 4 checks failing', PullChecksNote(Pull));
    AssertEquals('npm audit, approval', CheckNames(Pull, chkFailed));
    AssertEquals('Failing: npm audit, approval', PullChecksDetail(Pull));
    AssertTrue(NeedsAttention(Pull, [arChecksFailing]));
    { The ignored ones do not count, whatever their case. }
    Ignored.Add('NPM Audit');
    AssertTrue(IsIgnoredCheck('npm audit', Ignored));
    AssertFalse(IsIgnoredCheck('build', Ignored));
    AssertFalse(IsIgnoredCheck('build', nil));
    AssertTrue(ChecksState(Pull, Ignored) = chkFailed);
    AssertEquals('1 of 3 checks failing', PullChecksNote(Pull, Ignored));
    AssertEquals('Failing: approval · Ignored: npm audit', PullChecksDetail(Pull, Ignored));
    Ignored.Add('approval');
    AssertTrue('one still runs', ChecksState(Pull, Ignored) = chkPending);
    AssertEquals('1 of 2 checks pending', PullChecksNote(Pull, Ignored));
    AssertEquals('Pending: lint · Ignored: npm audit, approval', PullChecksDetail(Pull, Ignored));
    AssertFalse(NeedsAttention(Pull, AllAttentionReasons, Ignored));
    Ignored.Add('lint');
    AssertTrue(ChecksState(Pull, Ignored) = chkPassed);
    AssertEquals('✓ 1 check', PullChecksNote(Pull, Ignored));
    Ignored.Add('build');
    AssertTrue('all ignored is none', ChecksState(Pull, Ignored) = chkNone);
    AssertEquals('', PullChecksNote(Pull, Ignored));
    AssertEquals('Ignored: build, npm audit, lint, approval', PullChecksDetail(Pull, Ignored));
    { All failing. }
    Pull.CheckList[0].State := chkFailed;
    Pull.CheckList[2].State := chkFailed;
    AssertEquals('4 checks failing', PullChecksNote(Pull));
    SetLength(Pull.CheckList, 1);
    AssertEquals('1 check failing', PullChecksNote(Pull));
    { More checks than the list: one past it may fail, which the
      forge's sum tells. }
    Pull.CheckList[0].State := chkPassed;
    Pull.Checks := chkFailed;
    AssertTrue(ChecksState(Pull) = chkPassed);
    Pull.ChecksMore := True;
    AssertTrue('the sum is worse', ChecksState(Pull) = chkFailed);
    AssertEquals('checks failing', PullChecksNote(Pull));
    AssertTrue(NeedsAttention(Pull, [arChecksFailing]));
    Pull.Checks := chkPassed;
    AssertEquals('✓ 1+ checks', PullChecksNote(Pull));
    Pull.CheckList[0].State := chkFailed;
    AssertEquals('1 of 1+ checks failing', PullChecksNote(Pull));
    Pull.ChecksMore := False;
    { The names as one settings value and back. }
    AssertEquals('NPM Audit|approval|lint|build', JoinCheckNames(Ignored));
    SplitCheckNames(' a | |b|', Ignored);
    AssertEquals(2, Ignored.Count);
    AssertEquals('a', Ignored[0]);
    AssertEquals('b', Ignored[1]);
    AssertEquals('a|b', JoinCheckNames(Ignored));
    AssertEquals('', JoinCheckNames(nil));
    { A bar or a backslash in a name comes back. }
    Ignored.Clear;
    Ignored.Add('lint | strict');
    Ignored.Add('C:\path');
    AssertEquals('lint \| strict|C:\\path', JoinCheckNames(Ignored));
    SplitCheckNames(JoinCheckNames(Ignored), Ignored);
    AssertEquals(2, Ignored.Count);
    AssertEquals('lint | strict', Ignored[0]);
    AssertEquals('C:\path', Ignored[1]);
    SplitCheckNames('old\name|x', Ignored);
    AssertEquals('a backslash before anything else stays', 'old\name', Ignored[0]);
  finally
    Ignored.Free;
  end;
end;

procedure TForgeTest.TestReviewNotes;
var
  Pull: TGittanForgePull;
begin
  Pull := Default(TGittanForgePull);
  AssertEquals('', PullReviewNote(Pull));
  AssertEquals('', PullReviewers(Pull));
  AssertFalse(WaitsForReview(Pull));
  Pull.ReviewDecision := rdReviewRequired;
  AssertEquals('Review required', PullReviewNote(Pull));
  SetLength(Pull.RequestedOf, 1);
  Pull.RequestedOf[0] := 'chef';
  AssertEquals('Waiting for chef', PullReviewNote(Pull));
  AssertEquals('waiting for chef', PullReviewers(Pull));
  AssertTrue(WaitsForReview(Pull));
  SetLength(Pull.RequestedOf, 2);
  Pull.RequestedOf[1] := 'core';
  AssertEquals('Waiting for 2 reviewers', PullReviewNote(Pull));
  SetLength(Pull.Reviews, 4);
  Pull.Reviews[0].Login := 'anna';
  Pull.Reviews[0].Verdict := rvApproved;
  Pull.Reviews[1].Login := 'coderabbitai';
  Pull.Reviews[1].Verdict := rvCommented;
  Pull.Reviews[2].Login := 'bob';
  Pull.Reviews[2].Verdict := rvDismissed;
  Pull.Reviews[3].Login := 'carl';
  Pull.Reviews[3].Verdict := rvChangesRequested;
  AssertEquals('anna approved · coderabbitai commented · carl requested changes · ' +
    'waiting for chef, core', PullReviewers(Pull));
  { The user among those asked is "you", first. }
  AssertEquals('anna approved · coderabbitai commented · carl requested changes · ' +
    'waiting for you, chef', PullReviewers(Pull, 'Core'));
  AssertEquals('Waiting for 2 reviewers', PullReviewNote(Pull, 'core'));
  SetLength(Pull.RequestedOf, 1);
  AssertEquals('Waiting for you', PullReviewNote(Pull, 'CHEF'));
  AssertEquals('Waiting for chef', PullReviewNote(Pull, 'anna'));
  SetLength(Pull.RequestedOf, 2);

  { The decision wins over who is asked. }
  Pull.ReviewDecision := rdApproved;
  AssertEquals('Approved', PullReviewNote(Pull));
  AssertTrue(WaitsForReview(Pull));
  Pull.ReviewDecision := rdChangesRequested;
  AssertEquals('Changes requested', PullReviewNote(Pull));
  AssertFalse('changes asked for are not waiting', WaitsForReview(Pull));
end;

procedure TForgeTest.TestFilters;
var
  Pulls, Left: TGittanForgePulls;
  Defs: TGittanForgeFilterDefs;
  Ctx: TGittanFilterContext;
  Ignored: TStringList;
  Now_: TDateTime;
  i: integer;
begin
  Now_ := EncodeDateTime(2026, 10, 27, 12, 0, 0, 0);
  Defs := StandardFilters;
  Ctx := FilterContext(Now_);
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
  Pulls[2].MyReview := rvCommented;
  Pulls[3].ReviewDecision := rdApproved;
  SetLength(Pulls[3].RequestedOf, 1);
  Pulls[3].RequestedOf[0] := 'chef';
  AssertTrue(NeedsAttention(Pulls[0]));
  AssertTrue(NeedsAttention(Pulls[1]));
  AssertFalse(NeedsAttention(Pulls[2]));
  AssertFalse(NeedsAttention(Pulls[3]));
  AssertEquals(4, Length(FilterPulls(Pulls, Defs, '', Ctx)));
  AssertEquals('an unknown key is passed over', 4, Length(FilterPulls(Pulls, Defs, 'xyz', Ctx)));
  Left := FilterPulls(Pulls, Defs, fkAttention, Ctx);
  AssertEquals(2, Length(Left));
  AssertEquals(1, Left[0].Number);
  AssertEquals(2, Left[1].Number);
  { The filters together: every one must pass. }
  Left := FilterPulls(Pulls, Defs, fkAttention + ',' + fkNoDrafts, Ctx);
  AssertEquals(1, Length(Left));
  AssertEquals(1, Left[0].Number);
  Left := FilterPulls(Pulls, Defs, fkAskedOfMe, Ctx);
  AssertEquals(1, Length(Left));
  AssertEquals(3, Left[0].Number);
  AssertEquals(3, Length(FilterPulls(Pulls, Defs, fkNoDrafts, Ctx)));
  AssertEquals(1, Length(FilterPulls(Pulls, Defs, fkFeedback, Ctx)));
  AssertEquals(0, Length(FilterPulls(nil, Defs, fkFeedback, Ctx)));
  Left := FilterPulls(Pulls, Defs, fkApproved, Ctx);
  AssertEquals(1, Length(Left));
  AssertEquals(4, Left[0].Number);
  Left := FilterPulls(Pulls, Defs, fkWaiting, Ctx);
  AssertEquals(1, Length(Left));
  AssertEquals(4, Left[0].Number);
  Left := FilterPulls(Pulls, Defs, fkChanges, Ctx);
  AssertEquals(1, Length(Left));
  AssertEquals(1, Left[0].Number);
  Left := FilterPulls(Pulls, Defs, fkChecksFailing, Ctx);
  AssertEquals(1, Length(Left));
  AssertEquals(2, Left[0].Number);
  { Checks passing: passed or none, not pending. }
  Left := FilterPulls(Pulls, Defs, fkChecksOk, Ctx);
  AssertEquals(2, Length(Left));
  AssertEquals(1, Left[0].Number);
  AssertEquals(4, Left[1].Number);
  Left := FilterPulls(Pulls, Defs, fkNew, Ctx);
  AssertEquals(3, Length(Left));
  AssertEquals(4, Left[2].Number);
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
  Left := FilterPulls(Pulls, Defs, fkStale, Ctx);
  AssertEquals(2, Length(Left));
  AssertEquals(2, Left[0].Number);
  AssertEquals(3, Left[1].Number);
  { Attention for only some reasons: failing checks left out, or
    changes asked for; neither leaves none. }
  AssertTrue(NeedsAttention(Pulls[0], [arChangesRequested]));
  AssertFalse(NeedsAttention(Pulls[1], [arChangesRequested]));
  AssertFalse(NeedsAttention(Pulls[0], [arChecksFailing]));
  AssertTrue(NeedsAttention(Pulls[1], [arChecksFailing]));
  Left := FilterPulls(Pulls, Defs, fkAttention, FilterContext(Now_, [arChangesRequested]));
  AssertEquals(1, Length(Left));
  AssertEquals(1, Left[0].Number);
  AssertEquals(0, Length(FilterPulls(Pulls, Defs, fkAttention, FilterContext(Now_, []))));
  { An ignored check takes a pull request out of the failing ones. }
  SetLength(Pulls[1].CheckList, 1);
  Pulls[1].CheckList[0].Name := 'npm audit';
  Pulls[1].CheckList[0].State := chkFailed;
  Ignored := TStringList.Create;
  try
    Ignored.Add('npm audit');
    Ctx := FilterContext(Now_, AllAttentionReasons, Ignored);
    AssertEquals(0, Length(FilterPulls(Pulls, Defs, fkChecksFailing, Ctx)));
    Left := FilterPulls(Pulls, Defs, fkAttention, Ctx);
    AssertEquals(1, Length(Left));
    AssertEquals(1, Left[0].Number);
    AssertEquals(3, Length(FilterPulls(Pulls, Defs, fkChecksOk, Ctx)));
  finally
    Ignored.Free;
  end;
  { The standard filters: each key once, each section with some. }
  for i := 0 to High(Defs) do
  begin
    AssertEquals(Defs[i].Key, i, FindFilter(Defs, Defs[i].Key));
    AssertTrue(Defs[i].Key, Defs[i].Sections <> []);
    AssertTrue(Defs[i].Key, Defs[i].Caption <> '');
    AssertTrue(Defs[i].Key, Assigned(Defs[i].Passes));
  end;
  AssertEquals(-1, FindFilter(Defs, 'nope'));
  AssertEquals(9, Length(SectionFilters(Defs, fsMine)));
  AssertEquals(7, Length(SectionFilters(Defs, fsReview)));

  AssertEquals(fkFeedback, SectionFilters(Defs, fsMine)[0].Key);
  AssertEquals(fkAskedOfMe, SectionFilters(Defs, fsReview)[0].Key);
end;

procedure TForgeTest.TestKeys;
var
  Defs: TGittanForgeFilterDefs;
begin
  AssertTrue(HasKey('a,b', 'a'));
  AssertTrue(HasKey(' a , b ', 'b'));
  AssertFalse(HasKey('ab,b', 'a'));
  AssertFalse(HasKey('', 'a'));
  AssertFalse(HasKey('a', ''));
  AssertEquals('a,b', ToggleKey('a', 'b'));
  AssertEquals('b', ToggleKey('a,b', 'a'));
  AssertEquals('', ToggleKey('a', 'a'));
  AssertEquals('a', ToggleKey('', 'a'));
  AssertEquals('a', ToggleKey('a,,', ''));
  AssertTrue(SameKeys('a,b', 'b,a'));
  AssertTrue(SameKeys('', ' , '));
  AssertFalse(SameKeys('a,b', 'a'));
  AssertFalse(SameKeys('a', 'a,b'));
  { Only the keys the forge has for the section, in its order. }
  Defs := StandardFilters;
  AssertEquals(fkFeedback + ',' + fkNoDrafts, KnownKeys(fkNoDrafts + ',xyz,' + fkFeedback,
    Defs, fsMine));
  AssertEquals(fkNoDrafts, KnownKeys(fkNoDrafts + ',' + fkFeedback, Defs, fsReview));
  AssertEquals('', KnownKeys('', Defs, fsMine));
end;

procedure TForgeTest.TestPresets;
var
  Presets, Own: TGittanForgePresets;
  Defs: TGittanForgeFilterDefs;
  Key: string;
  i: integer;
begin
  { The standard presets name standard filters of their section. }
  Defs := StandardFilters;
  Presets := StandardPresets;
  AssertEquals(6, Length(Presets));
  for i := 0 to High(Presets) do
  begin
    AssertFalse(Presets[i].Own);
    AssertTrue(Presets[i].Name <> '');
    AssertTrue(Presets[i].Keys <> '');
    for Key in Presets[i].Keys.Split([',']) do
      AssertTrue(Presets[i].Name + ': ' + Key, FindFilter(SectionFilters(Defs,
        Presets[i].Section), Key) >= 0);
  end;
  AssertEquals(0, FindPreset(Presets, fsMine, fkAttention));
  AssertEquals('the keys in any order', 2, FindPreset(Presets, fsMine,
    fkNoDrafts + ',' + fkApproved + ',' + fkChecksOk));
  AssertEquals('the other section', -1, FindPreset(Presets, fsReview, fkAttention));
  AssertEquals(-1, FindPreset(Presets, fsMine, ''));
  { The user's own as one settings value and back: a bad section, a
    name of nothing and a name's bars and semicolons are dropped. }
  Own := ParsePresets('mine|Bot done|feedback,nodrafts;review| Green |checksok;' +
    'x|Bad|a;mine||a;mine|Name only;review|A|b|;mine|No;Semi|a');
  AssertEquals(5, Length(Own));
  AssertEquals('Bot done', Own[0].Name);
  AssertTrue(Own[0].Section = fsMine);
  AssertEquals('feedback,nodrafts', Own[0].Keys);
  AssertTrue(Own[0].Own);
  AssertEquals('Green', Own[1].Name);
  AssertTrue(Own[1].Section = fsReview);
  AssertEquals('checksok', Own[1].Keys);
  AssertEquals('Name only', Own[2].Name);
  AssertEquals('', Own[2].Keys);
  AssertEquals('A', Own[3].Name);
  AssertEquals('b', Own[3].Keys);
  AssertEquals('No', Own[4].Name);
  AssertEquals('mine|Bot done|feedback,nodrafts;review|Green|checksok;mine|Name only|;' +
    'review|A|b;mine|No|', JoinPresets(Own));
  AssertEquals('the forge''s own are not written', '', JoinPresets(Presets));
  AssertEquals(0, Length(ParsePresets('')));
  AssertEquals('Semi', PresetName(' Se|mi; '));
end;

procedure TForgeTest.TestOrder;
var
  Pulls, Sorted: TGittanForgePulls;
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
  { 1 changed last, opened second; 2 failing, the newest; 3 changes
    asked for, opened first and changed never; 4 failing, changed
    second. }
  Pulls[0].Created := IncDay(Now_, -20);
  Pulls[0].Updated := IncDay(Now_, -1);
  Pulls[1].Created := IncDay(Now_, -3);
  Pulls[1].Updated := IncDay(Now_, -3);
  Pulls[1].Checks := chkFailed;
  Pulls[2].Created := IncDay(Now_, -30);
  Pulls[2].ReviewDecision := rdChangesRequested;
  Pulls[3].Created := IncDay(Now_, -10);
  Pulls[3].Updated := IncDay(Now_, -2);
  Pulls[3].Checks := chkFailed;
  Sorted := SortPulls(Pulls, poUpdated);
  AssertEquals(1, Sorted[0].Number);
  AssertEquals(4, Sorted[1].Number);
  AssertEquals(2, Sorted[2].Number);
  AssertEquals('no change counts the opening', 3, Sorted[3].Number);
  Sorted := SortPulls(Pulls, poNewest);
  AssertEquals(2, Sorted[0].Number);
  AssertEquals(4, Sorted[1].Number);
  AssertEquals(1, Sorted[2].Number);
  AssertEquals(3, Sorted[3].Number);
  { Attention first keeps the order among those that need it and among
    the rest. }
  Sorted := SortPulls(Pulls, poAttentionFirst);
  AssertEquals(2, Sorted[0].Number);
  AssertEquals(3, Sorted[1].Number);
  AssertEquals(4, Sorted[2].Number);
  AssertEquals(1, Sorted[3].Number);
  Sorted := SortPulls(Pulls, poAttentionFirst, [arChangesRequested]);
  AssertEquals(3, Sorted[0].Number);
  AssertEquals(1, Sorted[1].Number);
  AssertEquals(2, Sorted[2].Number);
  AssertEquals(4, Sorted[3].Number);
  AssertEquals('the list given is left as it was', 1, Pulls[0].Number);
  AssertEquals(0, Length(SortPulls(nil, poNewest)));
end;

procedure TForgeTest.TestNotes;
begin
  AssertEquals('Approved', ReviewDecisionNote(rdApproved));
  AssertEquals('Changes requested', ReviewDecisionNote(rdChangesRequested));
  AssertEquals('Review required', ReviewDecisionNote(rdReviewRequired));
  AssertEquals('', ReviewDecisionNote(rdNone));
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

procedure TForgeTest.TestRemoteRepoPath;
begin
  AssertEquals('slicke/gittan', RemoteRepoPath('https://github.com/slicke/gittan.git'));
  AssertEquals('slicke/gittan', RemoteRepoPath('https://user:token@github.com/slicke/gittan/'));
  AssertEquals('slicke/gittan', RemoteRepoPath('git@github.com:slicke/gittan.git'));
  AssertEquals('slicke/gittan', RemoteRepoPath('ssh://git@github.com:22/slicke/gittan.git'));
  AssertEquals('group/sub/repo', RemoteRepoPath('gitlab.example.org:group/sub/repo.git'));
  AssertEquals('', RemoteRepoPath('/Volumes/Projects/git/trailhead.git'));
  AssertEquals('', RemoteRepoPath('file:///srv/git/trailhead.git'));
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

procedure TForgeTest.TestSshAlias;
const
  Config = '# work'#10'Host github-work gh-*'#10'  HostName github.com'#10 +
    '  User git'#10#10'Host !nope *.lan'#10'    HostName=%h.example.org'#10 +
    'Match host other'#10'  HostName example.org'#10;
begin
  AssertEquals('github.com', SshHostName('github-work', Config));
  AssertEquals('github.com', SshHostName('GH-two', Config));
  AssertEquals('box.lan.example.org', SshHostName('box.lan', Config));
  AssertEquals('other', SshHostName('other', Config));
  AssertEquals('plain', SshHostName('plain', ''));
  { A value in double quotes, as ssh takes it. }
  AssertEquals('github.com', SshHostName('quoted', 'Host quoted'#10'  HostName "github.com"'#10));
  AssertEquals('github.com', SshHostName('quoted', 'Host quoted'#10'  HostName="github.com"'#10));
  { The alias of an ssh remote is looked up; an https host is not. }
  AssertTrue(ForgeClassFor('remote.origin.url git@github-work:org/repo.git'#10, Config) =
    TGittanGitHubForge);
  AssertTrue(ForgeClassFor('remote.origin.url ssh://git@github-work/org/repo'#10, Config) =
    TGittanGitHubForge);
  AssertTrue(ForgeClassFor('remote.origin.url https://github-work/org/repo'#10, Config) = nil);
  AssertTrue(ForgeClassFor('remote.origin.url git@github-work:org/repo.git'#10, '') = nil);
end;

{ A forge is kept while its class and its tool stay, else made again,
  and there is none without a class or a tool. }
procedure TForgeTest.TestKeepForge;
var
  Forge, Same: TGittanForge;
begin
  Forge := nil;
  AssertFalse(KeepForge(Forge, TExampleForge, ''));
  AssertNull(Forge);
  AssertFalse(KeepForge(Forge, nil, '/usr/bin/ex'));
  AssertNull(Forge);
  AssertTrue(KeepForge(Forge, TExampleForge, '/usr/bin/ex'));
  AssertTrue(Forge is TExampleForge);
  AssertEquals('/usr/bin/ex', Forge.Cli);
  Same := Forge;
  AssertFalse(KeepForge(Forge, TExampleForge, '/usr/bin/ex'));
  AssertTrue(Forge = Same);
  AssertTrue(KeepForge(Forge, TExampleForge, '/opt/ex'));
  AssertEquals('/opt/ex', Forge.Cli);
  AssertTrue(KeepForge(Forge, TGittanGitHubForge, '/opt/gh'));
  AssertTrue(Forge is TGittanGitHubForge);
  AssertTrue(KeepForge(Forge, TGittanGitHubForge, ''));
  AssertNull(Forge);
  AssertTrue(KeepForge(Forge, TGittanGitHubForge, '/opt/gh'));
  AssertTrue(KeepForge(Forge, nil, ''));
  AssertNull(Forge);
end;

initialization
  RegisterForge(TExampleForge);
  RegisterTest(TForgeTest);

end.
