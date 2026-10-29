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
    procedure TestRegistered;
    procedure TestHosts;
    procedure TestAccounts;
    procedure TestParsePullRequest;
    procedure TestParsePullRequests;
    procedure TestWithoutReviewed;
    procedure TestParseBad;
    procedure TestStatus;
    procedure TestRepoPathOfUrl;
    procedure TestChecks;
    procedure TestIssueNumber;
    procedure TestWebArgs;
    procedure TestPullActionArgs;
    procedure TestPullActionFits;
    procedure TestNewPullUrl;
    procedure TestFileOfUrl;
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

procedure TGitHubTest.TestRegistered;
var
  Forge: TGittanForge;
begin
  { The unit registers its forge as it loads, which the rest of Gittan
    makes through ForgeClass without naming it. }
  AssertTrue(ForgeClass = TGittanGitHubForge);
  AssertEquals('gh', ForgeClass.CliName);
  Forge := ForgeClass.Create('/usr/bin/gh');
  try
    AssertEquals('GitHub', Forge.Name);
    AssertEquals('/usr/bin/gh', Forge.Cli);
  finally
    Forge.Free;
  end;
end;

procedure TGitHubTest.TestHosts;
var
  Hosts: TStringArray;
begin
  Hosts := GhHosts('github.com:'#10'    user: me'#10'    git_protocol: ssh'#10 +
    '# a comment:'#10'GHE.Example.com:'#10'    users:'#10'        me:'#10 +
    '"quoted.example.com":'#10);
  AssertEquals(3, Length(Hosts));
  AssertEquals('github.com', Hosts[0]);
  AssertEquals('ghe.example.com', Hosts[1]);
  AssertEquals('quoted.example.com', Hosts[2]);
  AssertEquals(0, Length(GhHosts('')));
  AssertTrue(TGittanGitHubForge.HostsRemote('github.com'));
  AssertTrue(TGittanGitHubForge.HostsRemote('ssh.github.com'));
  AssertFalse(TGittanGitHubForge.HostsRemote('gitlab.com'));
  { GH_HOST with the token gh takes for it in the environment. }
  AssertEquals('ghe.example.com', GhEnvHost('GHE.Example.com', '', 'secret'));
  AssertEquals('', GhEnvHost('ghe.example.com', 'secret', ''));
  AssertEquals('acme.ghe.com', GhEnvHost('acme.ghe.com', 'secret', ''));
  AssertEquals('', GhEnvHost('acme.ghe.com', '', 'secret'));
  AssertEquals('', GhEnvHost('github.com', 'secret', 'secret'));
  AssertEquals('', GhEnvHost('', 'secret', 'secret'));
end;

procedure TGitHubTest.TestAccounts;
var
  Accounts: TGittanForgeAccounts;
begin
  { gh 2.40 and later: the logins under users:, user: the active one,
    each login's own settings further in. }
  Accounts := GhAccounts('github.com:'#10'    git_protocol: https'#10 +
    '    users:'#10'        ada:'#10'            oauth_token: x'#10 +
    '        bob:'#10'    user: bob'#10 +
    'GHE.Example.com:'#10'    user: "carl"'#10'    oauth_token: y'#10 +
    'empty.example.com:'#10'    git_protocol: ssh'#10);
  AssertEquals(3, Length(Accounts));
  AssertEquals('github.com', Accounts[0].Host);
  AssertEquals('ada', Accounts[0].Login);
  AssertFalse(Accounts[0].Active);
  AssertEquals('bob', Accounts[1].Login);
  AssertTrue(Accounts[1].Active);
  { An older gh, user: alone. }
  AssertEquals('ghe.example.com', Accounts[2].Host);
  AssertEquals('carl', Accounts[2].Login);
  AssertTrue(Accounts[2].Active);
  AssertEquals('github.com=bob'#10'ghe.example.com=carl'#10, ActiveAccountsKey(Accounts));
  { The switch shows in the key. }
  Accounts := GhAccounts('github.com:'#13#10'    users:'#13#10'        ada:'#13#10 +
    '        bob:'#13#10'    user: ada'#13#10);
  AssertEquals(2, Length(Accounts));
  AssertTrue(Accounts[0].Active);
  AssertFalse(Accounts[1].Active);
  AssertEquals('github.com=ada'#10, ActiveAccountsKey(Accounts));
  AssertEquals(0, Length(GhAccounts('')));
  AssertEquals('', ActiveAccountsKey(nil));
end;

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

procedure TGitHubTest.TestPullActionArgs;

  { Joined with a bar, so an argument with a space stays one. }
  function Joined(const AArgs: TStringArray): string;
  begin
    Result := string.Join('|', AArgs);
  end;

begin
  AssertEquals('pr|review|12|--repo|o/r|--approve',
    Joined(GitHubPullActionArgs('o/r', 12, plApprove, '')));
  AssertEquals('pr|review|12|--repo|o/r|--approve|--body|Nice',
    Joined(GitHubPullActionArgs('o/r', 12, plApprove, 'Nice')));
  AssertEquals('pr|review|12|--repo|o/r|--request-changes|--body|Not yet',
    Joined(GitHubPullActionArgs('o/r', 12, plRequestChanges, 'Not yet')));
  AssertEquals('pr|review|12|--repo|o/r|--comment|--body|Hm',
    Joined(GitHubPullActionArgs('o/r', 12, plComment, 'Hm')));
  AssertEquals('pr|merge|12|--repo|o/r|--merge', Joined(GitHubPullActionArgs('o/r', 12, plMerge, 'x')));
  AssertEquals('pr|merge|12|--repo|o/r|--squash', Joined(GitHubPullActionArgs('o/r', 12, plSquash, '')));
  AssertEquals('pr|merge|12|--repo|o/r|--rebase',
    Joined(GitHubPullActionArgs('o/r', 12, plRebaseMerge, '')));
  AssertEquals('pr|ready|12|--repo|o/r', Joined(GitHubPullActionArgs('o/r', 12, plReady, '')));
  AssertTrue(TGittanGitHubForge.HasPullActions);
  AssertEquals('Approved', PullActionDone(plApprove));
  AssertTrue(PullActionMerges(plSquash));
  AssertFalse(PullActionIsReview(plReady));
end;

procedure TGitHubTest.TestPullActionFits;
var
  Pull: TGittanPullRequest;
begin
  Pull := Default(TGittanPullRequest);
  Pull.Number := 12;
  Pull.Repo := 'o/r';
  Pull.State := prOpen;
  AssertTrue(PullActionFits(Pull, plApprove));
  AssertTrue(PullActionFits(Pull, plSquash));
  AssertFalse('only a draft is marked ready', PullActionFits(Pull, plReady));
  Pull.IsDraft := True;
  AssertTrue(PullActionFits(Pull, plReady));
  AssertTrue('a draft is reviewed', PullActionFits(Pull, plComment));
  AssertFalse('a draft is not merged', PullActionFits(Pull, plMerge));
  Pull.State := prMerged;
  AssertFalse('not open', PullActionFits(Pull, plComment));
  Pull.IsDraft := False;
  AssertFalse('a closed pull is not merged', PullActionFits(Pull, plMerge));
  AssertFalse(PullActionFits(Pull, plSquash));
  AssertFalse(PullActionFits(Pull, plRebaseMerge));
  Pull.State := prOpen;
  Pull.Repo := '';
  AssertFalse('no repository', PullActionFits(Pull, plComment));
  Pull.Repo := 'o/r';
  Pull.Number := 0;
  AssertFalse('no number', PullActionFits(Pull, plComment));
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
  { A new pull request asks for the repository's address. }
  AssertEquals('', Joined(GitHubWebArgs(NewPullTarget('feature', ''))));
end;

procedure TGitHubTest.TestNewPullUrl;
begin
  AssertEquals('https://github.com/o/r/compare/feature/x?expand=1',
    GitHubNewPullUrl('https://github.com/o/r' + LineEnding, 'feature/x', ''));
  { The same repository as the head, in another case, is no fork. }
  AssertEquals('https://github.com/o/r/compare/fix?expand=1',
    GitHubNewPullUrl('https://github.com/o/r/', 'fix', 'O/R'));
  { A fork's branch goes in under its owner. }
  AssertEquals('https://github.com/o/r/compare/me:fix?expand=1',
    GitHubNewPullUrl('https://github.com/o/r', 'fix', 'me/r'));
  { What an address cannot hold is escaped, UTF-8 by its bytes. }
  AssertEquals('https://github.com/o/r/compare/a%23b%2Bc%C3%B6?expand=1',
    GitHubNewPullUrl('https://github.com/o/r', 'a#b+c' + #$C3#$B6, ''));
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

procedure TGitHubTest.TestFileOfUrl;
var
  Repo, Path: string;
  Line: integer;
begin
  AssertTrue(GitHubFileOfUrl('https://github.com/owner/repo/blob/abc123/src/a%20b.pp#L10-L20',
    Repo, Path, Line));
  AssertEquals('owner/repo', Repo);
  AssertEquals('src/a b.pp', Path);
  AssertEquals(10, Line);
  AssertTrue(GitHubFileOfUrl('https://github.com/o/r/blob/main/README.md?plain=1', Repo, Path, Line));
  AssertEquals('README.md', Path);
  AssertEquals(0, Line);
  AssertFalse('a folder', GitHubFileOfUrl('https://github.com/o/r/tree/main/src', Repo, Path, Line));
  AssertFalse('a pull request', GitHubFileOfUrl('https://github.com/o/r/pull/3', Repo, Path, Line));
  AssertFalse('another host', GitHubFileOfUrl('https://example.com/o/r/blob/main/a.pp',
    Repo, Path, Line));
end;

initialization
  RegisterTest(TGitHubTest);

end.
