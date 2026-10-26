unit testgithub;

{** Tests of gittan.github: the JSON gh prints, read on its own, GitHub's
  words turned into gittan.forge's kinds, the gh browse arguments and
  the forge's names. The jobs need gh and a GitHub repository, so they
  are not run here. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, fpcunit, testregistry, gittan.forge, gittan.github;

type
  TGitHubTest = class(TTestCase)
  published
    procedure TestParsePullRequest;
    procedure TestParsePullRequests;
    procedure TestWithoutReviewed;
    procedure TestParseBad;
    procedure TestStatus;
    procedure TestRepoPathOfUrl;
    procedure TestChecks;
    procedure TestIssueNumber;
    procedure TestWebArgs;
    procedure TestForge;
  end;

implementation

const
  OnePull = '{"author":{"id":"U_1","is_bot":false,"login":"ada","name":"Ada"},' +
    '"baseRefName":"main","headRefName":"fix/thing","isDraft":false,"number":12,' +
    '"reviewDecision":"APPROVED","state":"OPEN","title":"Fix the thing",' +
    '"url":"https://github.com/owner/repo/pull/12",' +
    '"createdAt":"2026-10-20T12:34:56Z","updatedAt":"2026-10-22T08:00:00Z",' +
    '"additions":120,"deletions":30,"changedFiles":4,' +
    '"labels":[{"name":"bug","color":"d73a4a"},{"name":"","color":"ffffff"},' +
    '{"name":"ui","color":"0075ca"}],' +
    '"latestReviews":[{"author":{"login":"bob"},"state":"APPROVED"},' +
    '{"author":null,"state":"COMMENTED"},{"author":{"login":"eve"},"state":"COMMENTED"}],' +
    '"reviewRequests":[{"__typename":"Team","name":"Core","slug":"core"},' +
    '{"__typename":"User","login":"dan"}]}';

procedure TGitHubTest.TestParsePullRequest;
var
  Pull: TGittanPullRequest;
begin
  AssertTrue(ParsePullRequest(OnePull, Pull));
  AssertEquals(12, Pull.Number);
  AssertEquals('Fix the thing', Pull.Title);
  AssertTrue('open', Pull.State = prOpen);
  AssertTrue('approved', Pull.ReviewDecision = rdApproved);
  AssertEquals('https://github.com/owner/repo/pull/12', Pull.Url);
  AssertEquals('owner/repo', Pull.Repo);
  AssertEquals('fix/thing', Pull.HeadRef);
  AssertEquals('main', Pull.BaseRef);
  AssertEquals('ada', Pull.Author);
  AssertFalse(Pull.IsDraft);
  AssertEquals(0, Pull.ChecksPassed + Pull.ChecksFailed + Pull.ChecksPending);
  AssertEquals(EncodeDateTime(2026, 10, 20, 12, 34, 56, 0), Pull.Created);
  AssertEquals(EncodeDateTime(2026, 10, 22, 8, 0, 0, 0), Pull.Updated);
  AssertEquals(120, Pull.Additions);
  AssertEquals(30, Pull.Deletions);
  AssertEquals(4, Pull.ChangedFiles);
  AssertEquals('bug, ui', Pull.Labels);
  AssertEquals(2, Length(Pull.Reviews));
  AssertEquals('bob', Pull.Reviews[0].Login);
  AssertTrue('bob approved', Pull.Reviews[0].Verdict = rvApproved);
  AssertEquals('eve', Pull.Reviews[1].Login);
  AssertTrue('eve commented', Pull.Reviews[1].Verdict = rvCommented);
  AssertEquals(1, Length(Pull.Requested));
  AssertEquals('dan', Pull.Requested[0]);
end;

{ A pull request whose latest review by the login approved it or asked
  for changes is left out, unless the login is asked again in person;
  one only commented on, or whose review was dismissed, stays, as does
  every one without a login. }
procedure TGitHubTest.TestWithoutReviewed;
var
  Pulls, Left: TGittanPullRequests;
begin
  AssertTrue(ParsePullRequests('[' + OnePull +
    ',{"number":3,"title":"Changes","latestReviews":[{"author":{"login":"Bob"},"state":"CHANGES_REQUESTED"}]}' +
    ',{"number":4,"title":"Dismissed","latestReviews":[{"author":{"login":"bob"},"state":"DISMISSED"}]}' +
    ',{"number":5,"title":"Nobody","latestReviews":[]}' +
    ',{"number":6,"title":"No field"}' +
    ',{"number":7,"title":"Asked again","latestReviews":[{"author":{"login":"bob"},"state":"APPROVED"}],' +
    '"reviewRequests":[{"__typename":"User","login":"bob"}]}]', Pulls));
  AssertEquals(6, Length(Pulls));
  Left := WithoutReviewed(Pulls, 'bob');
  AssertEquals(4, Length(Left));
  AssertEquals(4, Left[0].Number);
  AssertEquals(5, Left[1].Number);
  AssertEquals(6, Left[2].Number);
  AssertEquals(7, Left[3].Number);
  Left := WithoutReviewed(Pulls, 'eve');
  AssertEquals(6, Length(Left));
  AssertEquals(6, Length(WithoutReviewed(Pulls, '')));
  AssertEquals(0, Length(WithoutReviewed(nil, 'bob')));
end;

procedure TGitHubTest.TestParsePullRequests;
var
  Pulls: TGittanPullRequests;
begin
  AssertTrue(ParsePullRequests('[]', Pulls));
  AssertEquals(0, Length(Pulls));
  AssertTrue(ParsePullRequests('[' + OnePull + ',{"number":3,"title":"Draft","isDraft":true,' +
    '"state":"OPEN","author":null}]', Pulls));
  AssertEquals(2, Length(Pulls));
  AssertEquals(12, Pulls[0].Number);
  AssertEquals(3, Pulls[1].Number);
  AssertTrue(Pulls[1].IsDraft);
  AssertEquals('', Pulls[1].Author);
  AssertTrue('no decision', Pulls[1].ReviewDecision = rdNone);
  AssertEquals(0, Pulls[1].Created);
  AssertEquals(0, Pulls[1].Additions);
  AssertEquals('', Pulls[1].Labels);
end;

procedure TGitHubTest.TestParseBad;
var
  Pull: TGittanPullRequest;
  Pulls: TGittanPullRequests;
begin
  AssertFalse(ParsePullRequest('', Pull));
  AssertFalse(ParsePullRequest('not json', Pull));
  AssertFalse(ParsePullRequest('[]', Pull));
  AssertFalse(ParsePullRequest('{"title":"no number"}', Pull));
  AssertFalse(ParsePullRequests('{}', Pulls));
  AssertFalse(ParsePullRequests('[', Pulls));
end;

procedure TGitHubTest.TestStatus;
var
  Pull: TGittanPullRequest;
begin
  AssertTrue(ParsePullRequest(OnePull, Pull));
  AssertEquals('PR #12 · Approved', PullRequestStatus(Pull));
  Pull.ReviewDecision := rdChangesRequested;
  AssertEquals('PR #12 · Changes requested', PullRequestStatus(Pull));
  Pull.ReviewDecision := rdReviewRequired;
  AssertEquals('PR #12 · Review required', PullRequestStatus(Pull));
  Pull.ReviewDecision := rdNone;
  AssertEquals('PR #12', PullRequestStatus(Pull));
  Pull.IsDraft := True;
  AssertEquals('PR #12 · Draft', PullRequestStatus(Pull));
  Pull.State := prMerged;
  AssertEquals('PR #12 · Merged', PullRequestStatus(Pull));
  Pull.State := prClosed;
  AssertEquals('PR #12 · Closed', PullRequestStatus(Pull));
end;

procedure TGitHubTest.TestRepoPathOfUrl;
begin
  AssertEquals('owner/repo', RepoPathOfUrl('https://github.com/owner/repo/pull/12'));
  AssertEquals('owner/repo', RepoPathOfUrl('https://github.com/owner/repo'));
  AssertEquals('owner/repo', RepoPathOfUrl('https://ghe.example.com/owner/repo/pull/1'));
  AssertEquals('', RepoPathOfUrl('https://github.com/owner'));
  AssertEquals('', RepoPathOfUrl('owner/repo'));
  AssertEquals('', RepoPathOfUrl(''));
end;

procedure TGitHubTest.TestChecks;
const
  CheckRun = '{"__typename":"CheckRun","status":"%s","conclusion":"%s","name":"x"}';
  Ctx = '{"__typename":"StatusContext","state":"%s","context":"y"}';
var
  Pull: TGittanPullRequest;

  function Parse(const AChecks: string): TGittanPullRequest;
  begin
    AssertTrue(ParsePullRequest('{"number":1,"state":"OPEN","statusCheckRollup":[' +
      AChecks + ']}', Result));
  end;

begin
  Pull := Parse('');
  AssertEquals('', PullRequestChecks(Pull));
  AssertEquals('PR #1', PullRequestStatus(Pull));

  Pull := Parse(Format(CheckRun, ['COMPLETED', 'SUCCESS']) + ',' + Format(CheckRun, ['COMPLETED', 'SKIPPED']) +
    ',' + Format(Ctx, ['SUCCESS']));
  AssertEquals(3, Pull.ChecksPassed);
  AssertEquals('checks ✓', PullRequestChecks(Pull));
  AssertEquals('PR #1 · checks ✓', PullRequestStatus(Pull));

  Pull := Parse(Format(CheckRun, ['COMPLETED', 'SUCCESS']) + ',' + Format(CheckRun, ['IN_PROGRESS', '']) +
    ',' + Format(CheckRun, ['QUEUED', '']));
  AssertEquals(2, Pull.ChecksPending);
  AssertEquals('2 checks pending', PullRequestChecks(Pull));
  Pull := Parse(Format(Ctx, ['PENDING']));
  AssertEquals('1 check pending', PullRequestChecks(Pull));

  Pull := Parse(Format(CheckRun, ['COMPLETED', 'FAILURE']) + ',' + Format(CheckRun, ['IN_PROGRESS', '']) +
    ',' + Format(Ctx, ['ERROR']) + ',' + Format(CheckRun, ['COMPLETED', 'CANCELLED']));
  AssertEquals(3, Pull.ChecksFailed);
  AssertEquals(1, Pull.ChecksPending);
  AssertEquals('3 checks failing', PullRequestChecks(Pull));
  Pull := Parse(Format(CheckRun, ['COMPLETED', 'TIMED_OUT']));
  AssertEquals('1 check failing', PullRequestChecks(Pull));
  Pull.ReviewDecision := rdApproved;
  AssertEquals('PR #1 · Approved · 1 check failing', PullRequestStatus(Pull));
end;

procedure TGitHubTest.TestIssueNumber;
begin
  AssertEquals(123, IssueNumber('Fix the thing (#123)'));
  AssertEquals(7, IssueNumber('#7 first, #8 second'));
  AssertEquals(42, IssueNumber('Merge pull request #42 from x/y'));
  AssertEquals(0, IssueNumber('No number here'));
  AssertEquals(0, IssueNumber('Port to C#5 and #'));
  AssertEquals(0, IssueNumber('item#9 is not one'));
  AssertEquals(0, IssueNumber('#0 is nothing'));
  AssertEquals(0, IssueNumber(''));
end;

procedure TGitHubTest.TestWebArgs;

  function Joined(const AArgs: TStringArray): string;
  begin
    Result := string.Join(' ', AArgs);
  end;

begin
  AssertEquals('src/a.pp', Joined(GitHubWebArgs(FileTarget('src/a.pp', 0, '', ''))));
  AssertEquals('src/a.pp:12 --branch main',
    Joined(GitHubWebArgs(FileTarget('src/a.pp', 12, '', 'main'))));
  { A commit wins over the branch. }
  AssertEquals('src/a.pp:3 --commit=abc123',
    Joined(GitHubWebArgs(FileTarget('src/a.pp', 3, 'abc123', 'main'))));
  AssertEquals('abc123', Joined(GitHubWebArgs(CommitTarget('abc123'))));
  AssertEquals('42', Joined(GitHubWebArgs(IssueTarget(42))));
end;

procedure TGitHubTest.TestForge;
var
  Forge: TGittanForge;
  Version: string;
begin
  Forge := TGittanGitHubForge.Create('');
  try
    AssertEquals('GitHub', Forge.Name);
    AssertEquals('gh', Forge.CliName);
    AssertEquals('refs/pull/12/head', Forge.PullRef(12));
    { No tool, no version. }
    AssertFalse(Forge.Version(Version));
  finally
    Forge.Free;
  end;
end;

initialization
  RegisterTest(TGitHubTest);

end.
