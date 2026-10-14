unit testgithub;

{** Tests of gittan.github: the JSON gh prints, read on its own. The job
  needs gh and a GitHub repository, so it is not run here. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.github;

type
  TGitHubTest = class(TTestCase)
  published
    procedure TestParsePullRequest;
    procedure TestParsePullRequests;
    procedure TestParseBad;
    procedure TestStatus;
    procedure TestRepoPathOfUrl;
  end;

implementation

const
  OnePull = '{"author":{"id":"U_1","is_bot":false,"login":"ada","name":"Ada"},' +
    '"baseRefName":"main","headRefName":"fix/thing","isDraft":false,"number":12,' +
    '"reviewDecision":"APPROVED","state":"OPEN","title":"Fix the thing",' +
    '"url":"https://github.com/owner/repo/pull/12"}';

procedure TGitHubTest.TestParsePullRequest;
var
  Pull: TGittanPullRequest;
begin
  AssertTrue(ParsePullRequest(OnePull, Pull));
  AssertEquals(12, Pull.Number);
  AssertEquals('Fix the thing', Pull.Title);
  AssertEquals('OPEN', Pull.State);
  AssertEquals('APPROVED', Pull.ReviewDecision);
  AssertEquals('https://github.com/owner/repo/pull/12', Pull.Url);
  AssertEquals('fix/thing', Pull.HeadRef);
  AssertEquals('main', Pull.BaseRef);
  AssertEquals('ada', Pull.Author);
  AssertFalse(Pull.IsDraft);
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
  AssertEquals('', Pulls[1].ReviewDecision);
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
  Pull.ReviewDecision := 'CHANGES_REQUESTED';
  AssertEquals('PR #12 · Changes requested', PullRequestStatus(Pull));
  Pull.ReviewDecision := 'REVIEW_REQUIRED';
  AssertEquals('PR #12 · Review required', PullRequestStatus(Pull));
  Pull.ReviewDecision := '';
  AssertEquals('PR #12', PullRequestStatus(Pull));
  Pull.IsDraft := True;
  AssertEquals('PR #12 · Draft', PullRequestStatus(Pull));
  Pull.State := 'MERGED';
  AssertEquals('PR #12 · Merged', PullRequestStatus(Pull));
  Pull.State := 'CLOSED';
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

initialization
  RegisterTest(TGitHubTest);

end.
