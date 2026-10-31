unit gittan.github;

{** GitHub as a forge (gittan.forge), through gh, GitHub's command line
  tool: TGittanGitHubForge, its jobs, and the JSON they read. gh pr view
  and gh pr list --json give the open repository's pull requests
  (ParsePullRequest, ParsePullRequests); gh api graphql with ForgeQuery
  the user's across every repository (ParseForgeAnswer), and with
  ReviewThreadsQuery a pull request's review threads and conversation
  (ParseReviewThreads, ParsePullNotes); gh browse --no-browser the
  address of a file, a commit or an issue (GitHubWebArgs). GitHub's words
  (OPEN, APPROVED, SUCCESS) are turned into gittan.forge's kinds here
  and go no further. Every gh runs through RunGh, with its prompts and
  its update notice off. The unit registers the forge as it loads
  (RegisterForge), so nothing outside it names TGittanGitHubForge.
  Nothing here needs the LCL. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.forge, gittan.reviews, gittan.textfile;

const
  {** The fields asked of gh pr view and gh pr list, the ones
    TGittanPullRequest holds. }
  PullRequestFields = 'number,title,state,reviewDecision,url,headRefName,baseRefName,' +
    'author,isDraft,statusCheckRollup,createdAt,updatedAt,additions,deletions,changedFiles,' +
    'labels,latestReviews,reviewRequests';

  {** The GraphQL query for the user's pull requests across every
    repository: the login, the open pull requests the user wrote and the
    open ones a review is asked of them for (in person or through a
    team), fifty of each, newest first, each with who is asked for a
    review now (users, teams), the latest review of each reviewer, who
    wrote its last thirty comments and what its last thirty reviews
    said, and the head commit's checks by name. }
  ForgeQuery =
    'query { viewer { login avatarUrl(size: 128) } ' +
    'mine: search(query: "is:pr is:open author:@me archived:false sort:updated-desc", ' +
    'type: ISSUE, first: 50) { issueCount nodes { ...pull } } ' +
    'review: search(query: "is:pr is:open review-requested:@me archived:false ' +
    'sort:updated-desc", type: ISSUE, first: 50) { issueCount nodes { ...pull } } } ' +
    'fragment pull on PullRequest { number title url isDraft state reviewDecision ' +
    'createdAt updatedAt author { login } repository { nameWithOwner } ' +
    'headRefName baseRefName viewerLatestReview { state } ' +
    'reviewRequests(first: 20) { nodes { requestedReviewer { __typename ' +
    '... on User { login } ... on Team { name } ... on Bot { login } ' +
    '... on Mannequin { login } } } } ' +
    'latestReviews(first: 20) { nodes { state author { __typename login } } } ' +
    'comments(last: 30) { nodes { author { __typename login } } } ' +
    'reviews(last: 30) { nodes { state author { __typename login } } } ' +
    'commits(last: 1) { nodes { commit { statusCheckRollup { state ' +
    'contexts(first: 60) { pageInfo { hasNextPage } nodes { __typename ' +
    '... on CheckRun { name status conclusion } ' +
    '... on StatusContext { context state } } } } } } } }';

  {** The GraphQL query for one page of the threads of a pull request;
    $after is the cursor of the page before, left out for the first. }
  ReviewThreadsQuery =
    'query($owner:String!,$name:String!,$number:Int!,$after:String){' +
    'repository(owner:$owner,name:$name){pullRequest(number:$number){' +
    'headRefOid reviews(last:100){nodes{state body author{login} submittedAt url}} ' +
    'comments(last:100){nodes{author{login} body createdAt url}} ' +
    'reviewThreads(first:100,after:$after){' +
    'pageInfo{hasNextPage endCursor} nodes{' +
    'isResolved isOutdated path line startLine originalLine diffSide subjectType ' +
    'comments(first:100){nodes{author{login} body createdAt url}}}}}}}';

{** Reads the object gh pr view --json prints. }
function ParsePullRequest(const AJson: string; out APull: TGittanPullRequest): boolean;
{** Reads the array gh pr list --json prints. }
function ParsePullRequests(const AJson: string; out APulls: TGittanPullRequests): boolean;

{** Reads the answer to ForgeQuery: the login, the pull requests the
  user wrote (AMine) and those asked of them (AReview, as GitHub lists
  them, see NeedsMyReview). False when AJson is not the answer, with the
  query's first error message in AError when it carries one. }
function ParseForgeAnswer(const AJson: string; out ALogin: string;
  out AMine, AReview: TGittanForgePulls; out AError: string): boolean; overload;
{** As above, with the address of the user's picture (viewer's
  avatarUrl) in AAvatarUrl, '' when the answer has none. }
function ParseForgeAnswer(const AJson: string; out ALogin, AAvatarUrl: string;
  out AMine, AReview: TGittanForgePulls; out AError: string): boolean; overload;

{** Reads one page of the answer to ReviewThreadsQuery and adds its
  threads to AThreads. AHeadOid is the commit at the head of the pull
  request; ACursor the cursor of the next page when AHasNext. False when
  the text is not such an answer. }
function ParseReviewThreads(const AJson: string; var AThreads: TGittanReviewThreads;
  out AHeadOid: string; out AHasNext: boolean; out ACursor: string): boolean;

{** Reads the conversation of the pull request from an answer to
  ReviewThreadsQuery into ANotes, oldest first: its comments, and its
  reviews that were submitted with text or that approved, requested
  changes or were dismissed; a review that only commented on lines has
  nothing to show here, and a pending one is not submitted yet. False
  when the text is not such an answer. }
function ParsePullNotes(const AJson: string; out ANotes: TGittanPullNotes): boolean;

{** "owner/repo" of a GitHub address such as https://github.com/owner/repo/pull/12,
  empty when the address is not one. }
function RepoPathOfUrl(const AUrl: string): string;

{** The arguments of gh browse --no-browser for ATarget: "path:line"
  with --commit=<id> or --branch <name> for a file, the id for a commit,
  the number for an issue or pull request, none for a new pull request
  (the repository's address, which GitHubNewPullUrl goes on from). }
function GitHubWebArgs(const ATarget: TGittanWebTarget): TStringArray;

{** The page that opens a new pull request from ABranch in the
  repository at ARepoUrl (https://github.com/owner/repo): its compare
  page with the form unfolded, the branch escaped. A branch pushed to
  another repository (AHeadRepo, "owner/repo", a fork) goes in as
  "owner:branch", as GitHub takes it. }
function GitHubNewPullUrl(const ARepoUrl, ABranch, AHeadRepo: string): string;

{** The arguments of gh that do AAction to pull request ANumber of
  ARepo with AText: gh pr review with --approve, --request-changes or
  --comment and the text as --body (left out when empty; a request for
  changes and a comment need one, which gh refuses otherwise), gh pr
  merge with --merge, --squash or --rebase, or gh pr ready; --repo
  names the repository, so the folder it runs in does not matter. }
function GitHubPullActionArgs(const ARepo: string; ANumber: integer;
  AAction: TGittanPullAction; const AText: string): TStringArray;

{** The repository ("owner/name"), the file and the line (0 for none)
  of a GitHub address of a file in a commit or on a branch:
  "https://github.com/owner/name/blob/<ref>/src/a.pp#L10-L20" gives
  owner/name, src/a.pp and 10. The ref is taken as one part of the
  address, so a branch with a / in its name gives a wrong path. }
function GitHubFileOfUrl(const AUrl: string; out ARepo, APath: string;
  out ALine: integer): boolean;

type
  {** GitHub through gh (Cli, a path to it). }
  TGittanGitHubForge = class(TGittanForge)
  public
    class function Name: string; override;
    class function CliName: string; override;
    {** github.com, the GitHub Enterprise hosts gh is logged in to
      (GhHosts of the hosts.yml in GhConfigDir), and the one GH_HOST
      names when gh's environment gives a token for it (GhEnvHost). }
    class function HostsRemote(const AHost: string): boolean; override;
    {** The accounts of hosts.yml (GhAccounts), read again only when the
      file changed. }
    class function Accounts: TGittanForgeAccounts; override;
    {** A note when GH_TOKEN or GITHUB_TOKEN is set, which gh takes over
      the active account on github.com and ghe.com. }
    class function AccountsNote: string; override;
    {** gh auth switch with the host and the user. }
    function SwitchAccount(const AHost, ALogin: string; out AError: string): boolean;
      override;
    function Version(out AVersion: string): boolean; override;
    function PullJob(const ARoot, ABranch, ALogin: string): TGittanPullRequestJob; override;
    function ReviewJob(const ARoot, ARepo: string; ANumber: integer): TGittanReviewJob;
      override;
    function AccountJob(const ARoot: string): TGittanForgeJob; override;
    function WebUrl(const ARoot: string; const ATarget: TGittanWebTarget;
      out AUrl, AError: string): boolean; override;
    function FileOfWebUrl(const AUrl: string; out ARepo, APath: string;
      out ALine: integer): boolean; override;
    function PullRef(ANumber: integer): string; override;
    class function HasPullActions: boolean; override;
    function ActionJob(const ARoot, ARepo: string; ANumber: integer;
      AAction: TGittanPullAction; const AText: string): TGittanPullActionJob; override;
  end;

{** gh's configuration folder: GH_CONFIG_DIR, else "GitHub CLI" in
  AppData on Windows, else gh in XDG_CONFIG_HOME or ~/.config. }
function GhConfigDir: string;

{** The hosts gh is logged in to, the top-level keys of its hosts.yml
  (AText), in lower case. }
function GhHosts(const AText: string): TStringArray;

{** The accounts of gh's hosts.yml (AText): under each host's key the
  logins under "users:" (gh 2.40 and later), the one "user:" names
  active; a host with "user:" alone (an older gh) has that one. Hosts
  and logins in the order of the file, hosts in lower case. }
function GhAccounts(const AText: string): TGittanForgeAccounts;

{** The host gh reaches through the environment with no login in
  hosts.yml: AHost (GH_HOST) in lower case when the token gh takes for
  it is given, AEnterpriseToken (GH_ENTERPRISE_TOKEN or
  GITHUB_ENTERPRISE_TOKEN) for a GitHub Enterprise Server, AToken
  (GH_TOKEN or GITHUB_TOKEN) for one under ghe.com; empty otherwise. }
function GhEnvHost(const AHost, AToken, AEnterpriseToken: string): string;

implementation

uses
  DateUtils, fpjson, jsonparser, gittan.git;

function GhConfigDir: string;
begin
  Result := EnvironmentVariable('GH_CONFIG_DIR');
  if Result <> '' then
    Exit;
  {$ifdef windows}
  Result := EnvironmentVariable('AppData');
  if Result <> '' then
    Result := IncludeTrailingPathDelimiter(Result) + 'GitHub CLI';
  {$else}
  Result := EnvironmentVariable('XDG_CONFIG_HOME');
  if Result = '' then
    Result := IncludeTrailingPathDelimiter(GetUserDir) + '.config';
  Result := IncludeTrailingPathDelimiter(Result) + 'gh';
  {$endif}
end;

function GhHosts(const AText: string): TStringArray;
var
  Line, Host: string;
begin
  Result := nil;
  for Line in AText.Split([#10]) do
  begin
    { A key at the start of a line, "host:"; the settings under it are
      indented. }
    if (Line = '') or (Line[1] in [' ', #9, '#', '-']) then
      Continue;
    Host := Trim(Line);
    if (Host = '') or (Host[Length(Host)] <> ':') then
      Continue;
    Host := LowerCase(Trim(Copy(Host, 1, Length(Host) - 1)));
    if (Length(Host) >= 2) and (Host[1] in ['"', '''']) then
      Host := Copy(Host, 2, Length(Host) - 2);
    if Host <> '' then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Host;
    end;
  end;
end;

{ AText without the quotes YAML may put around a key or a value. }
function Unquoted(const AText: string): string;
begin
  Result := Trim(AText);
  if (Length(Result) >= 2) and (Result[1] in ['"', '''']) and
    (Result[Length(Result)] = Result[1]) then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

function GhAccounts(const AText: string): TGittanForgeAccounts;
var
  Line, Host, Key, Value, Active: string;
  Indent, HostIndent, UserIndent, Colon, First, i: integer;
  InUsers, Found: boolean;

  { The host read so far, its active login marked or added. }
  procedure EndHost;
  var
    j: integer;
  begin
    if (Host = '') or (Active = '') then
      Exit;
    Found := False;
    for j := First to High(Result) do
      if SameText(Result[j].Login, Active) then
      begin
        Result[j].Active := True;
        Found := True;
      end;
    if not Found then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].Host := Host;
      Result[High(Result)].Login := Active;
      Result[High(Result)].Active := True;
    end;
  end;

begin
  Result := nil;
  Host := '';
  Active := '';
  First := 0;
  HostIndent := -1;
  UserIndent := -1;
  InUsers := False;
  for Line in AText.Split([#10]) do
  begin
    if (Trim(Line) = '') or (TrimLeft(Line)[1] in ['#', '-']) then
      Continue;
    Indent := 0;
    while (Indent < Length(Line)) and (Line[Indent + 1] in [' ', #9]) do
      Inc(Indent);
    Colon := Pos(':', Line);
    if Colon = 0 then
      Continue;
    Key := Unquoted(Copy(Line, Indent + 1, Colon - Indent - 1));
    Value := Unquoted(Copy(Line, Colon + 1, MaxInt));
    if Indent = 0 then
    begin
      { A new host, a key with nothing after the colon. }
      EndHost;
      Host := '';
      Active := '';
      if (Key <> '') and (Value = '') then
        Host := LowerCase(Key);
      First := Length(Result);
      HostIndent := -1;
      UserIndent := -1;
      InUsers := False;
      Continue;
    end;
    if Host = '' then
      Continue;
    if HostIndent < 0 then
      HostIndent := Indent;
    if Indent <= HostIndent then
    begin
      InUsers := Key = 'users';
      UserIndent := -1;
      if Key = 'user' then
        Active := Value;
    end
    else if InUsers and (Key <> '') then
    begin
      { A login is a key one level in; its settings are further in. }
      if UserIndent < 0 then
        UserIndent := Indent;
      if Indent = UserIndent then
      begin
        Found := False;
        for i := First to High(Result) do
          Found := Found or SameText(Result[i].Login, Key);
        if not Found then
        begin
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)].Host := Host;
          Result[High(Result)].Login := Key;
          Result[High(Result)].Active := False;
        end;
      end;
    end;
  end;
  EndHost;
end;

function GhEnvHost(const AHost, AToken, AEnterpriseToken: string): string;
begin
  Result := LowerCase(Trim(AHost));
  if (Result = '') or (Result = 'github.com') then
    Exit('');
  if (Result = 'ghe.com') or Result.EndsWith('.ghe.com') then
  begin
    if AToken = '' then
      Result := '';
  end
  else if AEnterpriseToken = '' then
    Result := '';
end;

{ ---------------------------------------------------------------------------
  gh
  --------------------------------------------------------------------------- }

{ Runs gh (AExe) in ADir: true when it succeeded, with its standard
  output in AOutput and, on failure, its message in AError. Its prompts
  and its update notice are off, since nobody could answer the one and
  the other would land in stderr. }
function RunGh(const AExe, ADir: string; const AArgs: array of string;
  out AOutput, AError: string): boolean;
begin
  Result := RunCli(AExe, ADir, AArgs, ['GH_PROMPT_DISABLED=1', 'GH_NO_UPDATE_NOTIFIER=1'],
    AOutput, AError);
end;

{ ---------------------------------------------------------------------------
  Reading JSON
  --------------------------------------------------------------------------- }

{ A path through nested objects, nil when a step is missing or not an
  object. }
function Dig(AData: TJSONData; const ANames: array of string): TJSONData;
var
  i: integer;
begin
  Result := AData;
  for i := 0 to High(ANames) do
  begin
    if (Result = nil) or (Result.JSONType <> jtObject) then
      Exit(nil);
    Result := TJSONObject(Result).Find(ANames[i]);
  end;
end;

{ An integer field that may be null. }
function IntOf(AObject: TJSONObject; const AName: string): integer;
var
  Data: TJSONData;
begin
  Data := AObject.Find(AName);
  if (Data <> nil) and (Data.JSONType = jtNumber) then
    Result := Data.AsInteger
  else
    Result := 0;
end;

{ A string field, empty when it is missing, null or not a string. }
function StrOf(AObject: TJSONObject; const AName: string): string;
var
  Data: TJSONData;
begin
  Data := AObject.Find(AName);
  if (Data <> nil) and (Data.JSONType = jtString) then
    Result := Data.AsString
  else
    Result := '';
end;

{ The string at AName of the object at AField, empty when either is
  missing or null. }
function NestedString(AObject: TJSONObject; const AField, AName: string): string;
var
  Inner: TJSONData;
begin
  Result := '';
  Inner := AObject.Find(AField);
  if (Inner <> nil) and (Inner.JSONType = jtObject) then
    Result := StrOf(TJSONObject(Inner), AName);
end;

{ A time as GitHub gives it, "2026-10-20T12:34:56Z", in UTC; 0 when the
  field is missing or not a time. }
function TimeOf(AObject: TJSONObject; const AName: string): TDateTime;
begin
  if not TryISO8601ToDate(StrOf(AObject, AName), Result, True) then
    Result := 0;
end;

{ GitHub's words, as gittan.forge's kinds. }

function StateOf(const S: string): TGittanPullState;
begin
  case S of
    'MERGED': Result := prMerged;
    'CLOSED': Result := prClosed;
    else
      Result := prOpen;
  end;
end;

function DecisionOf(const S: string): TGittanReviewDecision;
begin
  case S of
    'APPROVED': Result := rdApproved;
    'CHANGES_REQUESTED': Result := rdChangesRequested;
    'REVIEW_REQUIRED': Result := rdReviewRequired;
    else
      Result := rdNone;
  end;
end;

function VerdictOf(const S: string): TGittanReviewVerdict;
begin
  case S of
    'APPROVED': Result := rvApproved;
    'CHANGES_REQUESTED': Result := rvChangesRequested;
    'COMMENTED': Result := rvCommented;
    'DISMISSED': Result := rvDismissed;
    else
      Result := rvNone;
  end;
end;

{ The state of a commit's statusCheckRollup. }
function RollupOf(const S: string): TGittanChecksState;
begin
  case S of
    'SUCCESS': Result := chkPassed;
    'FAILURE', 'ERROR': Result := chkFailed;
    'PENDING', 'EXPECTED': Result := chkPending;
    else
      Result := chkNone;
  end;
end;

{ ---------------------------------------------------------------------------
  The open repository's pull requests
  --------------------------------------------------------------------------- }

{ A CheckRun has a status (COMPLETED, IN_PROGRESS, QUEUED, ...) and, once
  completed, a conclusion; a StatusContext (the older commit status API)
  has a state. }
function CheckStateOf(ACheck: TJSONObject): TGittanChecksState;
var
  Verdict: string;
begin
  if StrOf(ACheck, '__typename') = 'StatusContext' then
    Verdict := StrOf(ACheck, 'state')
  else if StrOf(ACheck, 'status') = 'COMPLETED' then
    Verdict := StrOf(ACheck, 'conclusion')
  else
    Verdict := 'PENDING';
  case Verdict of
    'SUCCESS', 'SKIPPED', 'NEUTRAL':
      Result := chkPassed;
    'FAILURE', 'ERROR', 'CANCELLED', 'TIMED_OUT', 'ACTION_REQUIRED', 'STARTUP_FAILURE':
      Result := chkFailed;
    else
      Result := chkPending;
  end;
end;

{ A check's name: a CheckRun's name, a StatusContext's context. }
function CheckNameOf(ACheck: TJSONObject): string;
begin
  Result := StrOf(ACheck, 'name');
  if Result = '' then
    Result := StrOf(ACheck, 'context');
end;

procedure CountCheck(ACheck: TJSONObject; var APull: TGittanPullRequest);
begin
  case CheckStateOf(ACheck) of
    chkPassed: Inc(APull.ChecksPassed);
    chkFailed: Inc(APull.ChecksFailed);
    else
      Inc(APull.ChecksPending);
  end;
end;

function ReadPull(AObject: TJSONObject; out APull: TGittanPullRequest): boolean;
var
  Checks, Labels, Reviews, Reviewer, Requests: TJSONData;
  i, n: integer;
  Name: string;
begin
  APull := Default(TGittanPullRequest);
  Result := AObject.IndexOfName('number') >= 0;
  if not Result then
    Exit;
  APull.Number := IntOf(AObject, 'number');
  APull.Title := StrOf(AObject, 'title');
  APull.State := StateOf(StrOf(AObject, 'state'));
  APull.ReviewDecision := DecisionOf(StrOf(AObject, 'reviewDecision'));
  APull.Url := StrOf(AObject, 'url');
  APull.Repo := RepoPathOfUrl(APull.Url);
  APull.HeadRef := StrOf(AObject, 'headRefName');
  APull.BaseRef := StrOf(AObject, 'baseRefName');
  APull.IsDraft := AObject.Get('isDraft', False);
  APull.Author := NestedString(AObject, 'author', 'login');
  Checks := AObject.Find('statusCheckRollup');
  if (Checks <> nil) and (Checks.JSONType = jtArray) then
    for i := 0 to Checks.Count - 1 do
      if Checks.Items[i].JSONType = jtObject then
        CountCheck(TJSONObject(Checks.Items[i]), APull);
  APull.Created := TimeOf(AObject, 'createdAt');
  APull.Updated := TimeOf(AObject, 'updatedAt');
  APull.Additions := IntOf(AObject, 'additions');
  APull.Deletions := IntOf(AObject, 'deletions');
  APull.ChangedFiles := IntOf(AObject, 'changedFiles');
  Labels := AObject.Find('labels');
  if (Labels <> nil) and (Labels.JSONType = jtArray) then
    for i := 0 to Labels.Count - 1 do
      if Labels.Items[i].JSONType = jtObject then
      begin
        Name := StrOf(TJSONObject(Labels.Items[i]), 'name');
        if Name = '' then
          Continue;
        if APull.Labels <> '' then
          APull.Labels := APull.Labels + ', ';
        APull.Labels := APull.Labels + Name;
      end;
  Reviews := AObject.Find('latestReviews');
  if (Reviews <> nil) and (Reviews.JSONType = jtArray) then
    for i := 0 to Reviews.Count - 1 do
      if Reviews.Items[i].JSONType = jtObject then
      begin
        Reviewer := TJSONObject(Reviews.Items[i]).Find('author');
        if (Reviewer = nil) or (Reviewer.JSONType <> jtObject) then
          Continue;
        n := Length(APull.Reviews);
        SetLength(APull.Reviews, n + 1);
        APull.Reviews[n].Login := StrOf(TJSONObject(Reviewer), 'login');
        APull.Reviews[n].Verdict := VerdictOf(StrOf(TJSONObject(Reviews.Items[i]), 'state'));
      end;
  Requests := AObject.Find('reviewRequests');
  if (Requests <> nil) and (Requests.JSONType = jtArray) then
    for i := 0 to Requests.Count - 1 do
      if Requests.Items[i].JSONType = jtObject then
      begin
        Name := StrOf(TJSONObject(Requests.Items[i]), 'login');
        if Name = '' then
          Continue;
        n := Length(APull.Requested);
        SetLength(APull.Requested, n + 1);
        APull.Requested[n] := Name;
      end;
end;

function ParsePullRequest(const AJson: string; out APull: TGittanPullRequest): boolean;
var
  Data: TJSONData;
begin
  APull := Default(TGittanPullRequest);
  Result := False;
  try
    Data := GetJSON(AJson);
  except
    Exit;
  end;
  try
    if (Data <> nil) and (Data.JSONType = jtObject) then
      Result := ReadPull(TJSONObject(Data), APull);
  finally
    Data.Free;
  end;
end;

function ParsePullRequests(const AJson: string; out APulls: TGittanPullRequests): boolean;
var
  Data: TJSONData;
  i, n: integer;
begin
  APulls := nil;
  Result := False;
  try
    Data := GetJSON(AJson);
  except
    Exit;
  end;
  try
    if (Data = nil) or (Data.JSONType <> jtArray) then
      Exit;
    SetLength(APulls, Data.Count);
    n := 0;
    for i := 0 to Data.Count - 1 do
      if (Data.Items[i].JSONType = jtObject) and ReadPull(TJSONObject(Data.Items[i]),
        APulls[n]) then
        Inc(n);
    SetLength(APulls, n);
    Result := True;
  finally
    Data.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  The user's pull requests across every repository
  --------------------------------------------------------------------------- }

{ Whether a node of AField's nodes has an author who is not AAuthor
  and not a bot (a deleted user's author is null and counts too, as
  someone else). }
function OthersIn(AObject: TJSONObject; const AField, AAuthor: string): boolean;
var
  Nodes, Author: TJSONData;
  i: integer;
begin
  Result := False;
  Nodes := Dig(AObject, [AField, 'nodes']);
  if (Nodes = nil) or (Nodes.JSONType <> jtArray) then
    Exit;
  for i := 0 to Nodes.Count - 1 do
  begin
    if Nodes.Items[i].JSONType <> jtObject then
      Continue;
    Author := TJSONObject(Nodes.Items[i]).Find('author');
    if (Author = nil) or (Author.JSONType <> jtObject) then
      Exit(True);
    if (StrOf(TJSONObject(Author), '__typename') <> 'Bot') and
      not SameText(StrOf(TJSONObject(Author), 'login'), AAuthor) then
      Exit(True);
  end;
end;

{ The viewer's verdict from their reviews (the last thirty, oldest
  first): the latest that approved or asked for changes, a dismissal
  after it undoing it, a comment or a pending review leaving it be;
  rvNone when none of theirs said anything. }
function ViewerVerdictIn(AObject: TJSONObject; const ALogin: string): TGittanReviewVerdict;
var
  Nodes, Author: TJSONData;
  i: integer;
  Verdict: TGittanReviewVerdict;
begin
  Result := rvNone;
  if ALogin = '' then
    Exit;
  Nodes := Dig(AObject, ['reviews', 'nodes']);
  if (Nodes = nil) or (Nodes.JSONType <> jtArray) then
    Exit;
  for i := 0 to Nodes.Count - 1 do
  begin
    if Nodes.Items[i].JSONType <> jtObject then
      Continue;
    Author := TJSONObject(Nodes.Items[i]).Find('author');
    if (Author = nil) or (Author.JSONType <> jtObject) or
      not SameText(StrOf(TJSONObject(Author), 'login'), ALogin) then
      Continue;
    Verdict := VerdictOf(StrOf(TJSONObject(Nodes.Items[i]), 'state'));
    if Verdict in [rvApproved, rvChangesRequested, rvDismissed] then
      Result := Verdict;
  end;
end;

{ The reviewers asked now: the names in RequestedOf, and whether ALogin
  is among them in person. }
procedure ReadRequests(AObject: TJSONObject; const ALogin: string; var APull: TGittanForgePull);
var
  Nodes, Who: TJSONData;
  i, n: integer;
  Name: string;
begin
  Nodes := Dig(AObject, ['reviewRequests', 'nodes']);
  if (Nodes = nil) or (Nodes.JSONType <> jtArray) then
    Exit;
  for i := 0 to Nodes.Count - 1 do
  begin
    if Nodes.Items[i].JSONType <> jtObject then
      Continue;
    Who := TJSONObject(Nodes.Items[i]).Find('requestedReviewer');
    if (Who = nil) or (Who.JSONType <> jtObject) then
      Continue;
    Name := StrOf(TJSONObject(Who), 'login');
    if Name = '' then
      Name := StrOf(TJSONObject(Who), 'name');
    if Name = '' then
      Continue;
    if (StrOf(TJSONObject(Who), '__typename') <> 'Team') and (ALogin <> '') and
      SameText(Name, ALogin) then
      APull.Requested := True;
    n := Length(APull.RequestedOf);
    SetLength(APull.RequestedOf, n + 1);
    APull.RequestedOf[n] := Name;
  end;
end;

{ The latest review of each reviewer, from latestReviews. }
procedure ReadLatestReviews(AObject: TJSONObject; var APull: TGittanForgePull);
var
  Nodes, Author: TJSONData;
  i, n: integer;
begin
  Nodes := Dig(AObject, ['latestReviews', 'nodes']);
  if (Nodes = nil) or (Nodes.JSONType <> jtArray) then
    Exit;
  for i := 0 to Nodes.Count - 1 do
  begin
    if Nodes.Items[i].JSONType <> jtObject then
      Continue;
    Author := TJSONObject(Nodes.Items[i]).Find('author');
    if (Author = nil) or (Author.JSONType <> jtObject) then
      Continue;
    n := Length(APull.Reviews);
    SetLength(APull.Reviews, n + 1);
    APull.Reviews[n].Login := StrOf(TJSONObject(Author), 'login');
    APull.Reviews[n].Verdict := VerdictOf(StrOf(TJSONObject(Nodes.Items[i]), 'state'));
  end;
end;

{ The head commit's checks: the rollup's state as the forge's sum, and
  each of its contexts by name, with whether there are more. }
procedure ReadChecks(AObject: TJSONObject; var APull: TGittanForgePull);
var
  Nodes, Rollup, Contexts: TJSONData;
  i, n: integer;
begin
  { commits.nodes[0].commit.statusCheckRollup }
  Nodes := Dig(AObject, ['commits', 'nodes']);
  if (Nodes = nil) or (Nodes.JSONType <> jtArray) or (Nodes.Count = 0) then
    Exit;
  Rollup := Dig(Nodes.Items[0], ['commit', 'statusCheckRollup']);
  if (Rollup = nil) or (Rollup.JSONType <> jtObject) then
    Exit;
  APull.Checks := RollupOf(StrOf(TJSONObject(Rollup), 'state'));
  Contexts := Dig(Rollup, ['contexts', 'pageInfo']);
  if (Contexts <> nil) and (Contexts.JSONType = jtObject) then
    APull.ChecksMore := TJSONObject(Contexts).Get('hasNextPage', False);
  Contexts := Dig(Rollup, ['contexts', 'nodes']);
  if (Contexts = nil) or (Contexts.JSONType <> jtArray) then
    Exit;
  for i := 0 to Contexts.Count - 1 do
  begin
    if Contexts.Items[i].JSONType <> jtObject then
      Continue;
    if CheckNameOf(TJSONObject(Contexts.Items[i])) = '' then
      Continue;
    n := Length(APull.CheckList);
    SetLength(APull.CheckList, n + 1);
    APull.CheckList[n].Name := CheckNameOf(TJSONObject(Contexts.Items[i]));
    APull.CheckList[n].State := CheckStateOf(TJSONObject(Contexts.Items[i]));
  end;
end;

function ReadForgePull(AObject: TJSONObject; const ALogin: string;
  out APull: TGittanForgePull): boolean;
var
  Verdict: TGittanReviewVerdict;
begin
  APull := Default(TGittanForgePull);
  Result := AObject.IndexOfName('number') >= 0;
  if not Result then
    Exit;
  APull.Number := IntOf(AObject, 'number');
  APull.Title := StrOf(AObject, 'title');
  APull.Url := StrOf(AObject, 'url');
  APull.IsDraft := AObject.Get('isDraft', False);
  APull.State := StateOf(StrOf(AObject, 'state'));
  APull.ReviewDecision := DecisionOf(StrOf(AObject, 'reviewDecision'));
  APull.Created := TimeOf(AObject, 'createdAt');
  APull.Updated := TimeOf(AObject, 'updatedAt');
  APull.Author := NestedString(AObject, 'author', 'login');
  APull.Repo := NestedString(AObject, 'repository', 'nameWithOwner');
  APull.HeadRef := StrOf(AObject, 'headRefName');
  APull.BaseRef := StrOf(AObject, 'baseRefName');
  { The viewer's latest review as GitHub names it, unless their reviews
    say an earlier approval or request for changes still stands, which
    a comment after it does not undo. }
  APull.MyReview := VerdictOf(NestedString(AObject, 'viewerLatestReview', 'state'));
  Verdict := ViewerVerdictIn(AObject, ALogin);
  if Verdict <> rvNone then
    APull.MyReview := Verdict;
  ReadRequests(AObject, ALogin, APull);
  ReadLatestReviews(AObject, APull);
  APull.Feedback := OthersIn(AObject, 'comments', APull.Author) or
    OthersIn(AObject, 'reviews', APull.Author);
  ReadChecks(AObject, APull);
end;

{ The pull requests of a search's nodes; nodes that are not pull
  requests are skipped. ALogin is the viewer's. }
procedure ReadSearch(AData: TJSONObject; const AName, ALogin: string;
  out APulls: TGittanForgePulls);
var
  Nodes: TJSONData;
  i, n: integer;
  Pull: TGittanForgePull;
begin
  APulls := nil;
  Nodes := Dig(AData, [AName, 'nodes']);
  if (Nodes = nil) or (Nodes.JSONType <> jtArray) then
    Exit;
  SetLength(APulls, Nodes.Count);
  n := 0;
  for i := 0 to Nodes.Count - 1 do
    if (Nodes.Items[i].JSONType = jtObject) and
      ReadForgePull(TJSONObject(Nodes.Items[i]), ALogin, Pull) then
    begin
      APulls[n] := Pull;
      Inc(n);
    end;
  SetLength(APulls, n);
end;

function ParseForgeAnswer(const AJson: string; out ALogin: string;
  out AMine, AReview: TGittanForgePulls; out AError: string): boolean;
var
  AvatarUrl: string;
begin
  Result := ParseForgeAnswer(AJson, ALogin, AvatarUrl, AMine, AReview, AError);
end;

function ParseForgeAnswer(const AJson: string; out ALogin, AAvatarUrl: string;
  out AMine, AReview: TGittanForgePulls; out AError: string): boolean;
var
  Root, Data, Errors: TJSONData;
begin
  ALogin := '';
  AAvatarUrl := '';
  AMine := nil;
  AReview := nil;
  AError := '';
  Result := False;
  try
    Root := GetJSON(AJson);
  except
    Exit;
  end;
  try
    if (Root = nil) or (Root.JSONType <> jtObject) then
      Exit;
    Errors := TJSONObject(Root).Find('errors');
    if (Errors <> nil) and (Errors.JSONType = jtArray) and (Errors.Count > 0) and
      (Errors.Items[0].JSONType = jtObject) then
      AError := StrOf(TJSONObject(Errors.Items[0]), 'message');
    Data := TJSONObject(Root).Find('data');
    if (Data = nil) or (Data.JSONType <> jtObject) then
      Exit;
    ALogin := NestedString(TJSONObject(Data), 'viewer', 'login');
    AAvatarUrl := NestedString(TJSONObject(Data), 'viewer', 'avatarUrl');
    ReadSearch(TJSONObject(Data), 'mine', ALogin, AMine);
    ReadSearch(TJSONObject(Data), 'review', ALogin, AReview);

    Result := True;
  finally
    Root.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Review threads and the conversation
  --------------------------------------------------------------------------- }

{ The login of a comment's author; a deleted account has none. }
function AuthorOf(AObject: TJSONObject): string;
begin
  Result := NestedString(AObject, 'author', 'login');
  if Result = '' then
    Result := 'ghost';
end;

function BodyOf(AObject: TJSONObject): string;
begin
  Result := StringReplace(StrOf(AObject, 'body'), #13#10, #10, [rfReplaceAll]);
end;

function ReadComment(AObject: TJSONObject): TGittanReviewComment;
begin
  Result := Default(TGittanReviewComment);
  Result.Author := AuthorOf(AObject);
  Result.Body := BodyOf(AObject);
  Result.Url := StrOf(AObject, 'url');
  Result.Created := TimeOf(AObject, 'createdAt');
end;

function ReadThread(AObject: TJSONObject; out AThread: TGittanReviewThread): boolean;
var
  Nodes: TJSONData;
  i, n: integer;
begin
  AThread := Default(TGittanReviewThread);
  AThread.Path := StrOf(AObject, 'path');
  Result := AThread.Path <> '';
  if not Result then
    Exit;
  AThread.Line := IntOf(AObject, 'line');
  AThread.StartLine := IntOf(AObject, 'startLine');
  AThread.OriginalLine := IntOf(AObject, 'originalLine');
  AThread.LeftSide := StrOf(AObject, 'diffSide') = 'LEFT';
  AThread.Resolved := AObject.Get('isResolved', False);
  AThread.Outdated := AObject.Get('isOutdated', False);
  AThread.OnFile := StrOf(AObject, 'subjectType') = 'FILE';
  if AThread.OnFile then
    AThread.Line := 0;
  Nodes := Dig(AObject, ['comments', 'nodes']);
  if (Nodes = nil) or (Nodes.JSONType <> jtArray) then
    Exit;
  SetLength(AThread.Comments, Nodes.Count);
  n := 0;
  for i := 0 to Nodes.Count - 1 do
    if Nodes.Items[i].JSONType = jtObject then
    begin
      AThread.Comments[n] := ReadComment(TJSONObject(Nodes.Items[i]));
      Inc(n);
    end;
  SetLength(AThread.Comments, n);
end;

function ParseReviewThreads(const AJson: string; var AThreads: TGittanReviewThreads;
  out AHeadOid: string; out AHasNext: boolean; out ACursor: string): boolean;
var
  Data, Pull, Threads, Info, Nodes: TJSONData;
  Thread: TGittanReviewThread;
  i: integer;
begin
  AHeadOid := '';
  AHasNext := False;
  ACursor := '';
  Result := False;
  try
    Data := GetJSON(AJson);
  except
    Exit;
  end;
  try
    Pull := Dig(Data, ['data', 'repository', 'pullRequest']);
    if (Pull = nil) or (Pull.JSONType <> jtObject) then
      Exit;
    AHeadOid := StrOf(TJSONObject(Pull), 'headRefOid');
    Threads := Dig(Pull, ['reviewThreads']);
    if (Threads = nil) or (Threads.JSONType <> jtObject) then
      Exit;
    Info := Dig(Threads, ['pageInfo']);
    if (Info <> nil) and (Info.JSONType = jtObject) then
    begin
      AHasNext := TJSONObject(Info).Get('hasNextPage', False);
      ACursor := StrOf(TJSONObject(Info), 'endCursor');
      AHasNext := AHasNext and (ACursor <> '');
    end;
    Nodes := Dig(Threads, ['nodes']);
    if (Nodes <> nil) and (Nodes.JSONType = jtArray) then
      for i := 0 to Nodes.Count - 1 do
        if (Nodes.Items[i].JSONType = jtObject) and
          ReadThread(TJSONObject(Nodes.Items[i]), Thread) and (Length(Thread.Comments) > 0) then
        begin
          SetLength(AThreads, Length(AThreads) + 1);
          AThreads[High(AThreads)] := Thread;
        end;
    Result := True;
  finally
    Data.Free;
  end;
end;

function ParsePullNotes(const AJson: string; out ANotes: TGittanPullNotes): boolean;
var
  Data, Pull, Nodes: TJSONData;
  Node: TJSONObject;
  Note: TGittanPullNote;
  i, j: integer;

  procedure Add;
  begin
    SetLength(ANotes, Length(ANotes) + 1);
    ANotes[High(ANotes)] := Note;
  end;

begin
  ANotes := nil;
  Result := False;
  try
    Data := GetJSON(AJson);
  except
    Exit;
  end;
  try
    Pull := Dig(Data, ['data', 'repository', 'pullRequest']);
    if (Pull = nil) or (Pull.JSONType <> jtObject) then
      Exit;
    Nodes := Dig(Pull, ['comments', 'nodes']);
    if (Nodes <> nil) and (Nodes.JSONType = jtArray) then
      for i := 0 to Nodes.Count - 1 do
        if Nodes.Items[i].JSONType = jtObject then
        begin
          Node := TJSONObject(Nodes.Items[i]);
          Note := Default(TGittanPullNote);
          Note.Kind := pnComment;
          Note.Author := AuthorOf(Node);
          Note.Body := Trim(BodyOf(Node));
          Note.Url := StrOf(Node, 'url');
          Note.Created := TimeOf(Node, 'createdAt');
          if Note.Body <> '' then
            Add;
        end;
    Nodes := Dig(Pull, ['reviews', 'nodes']);
    if (Nodes <> nil) and (Nodes.JSONType = jtArray) then
      for i := 0 to Nodes.Count - 1 do
        if Nodes.Items[i].JSONType = jtObject then
        begin
          Node := TJSONObject(Nodes.Items[i]);
          Note := Default(TGittanPullNote);
          case VerdictOf(StrOf(Node, 'state')) of
            rvApproved: Note.Kind := pnApproved;
            rvChangesRequested: Note.Kind := pnChangesRequested;
            rvDismissed: Note.Kind := pnDismissed;
            rvCommented: Note.Kind := pnCommented;
            else
              Continue;
          end;
          Note.Author := AuthorOf(Node);
          Note.Body := Trim(BodyOf(Node));
          Note.Url := StrOf(Node, 'url');
          Note.Created := TimeOf(Node, 'submittedAt');
          if (Note.Body <> '') or (Note.Kind <> pnCommented) then
            Add;
        end;
    { Comments and reviews each come in order; together they are sorted
      by time, keeping that order among equal times. }
    for i := 1 to High(ANotes) do
    begin
      Note := ANotes[i];
      j := i - 1;
      while (j >= 0) and (ANotes[j].Created > Note.Created) do
      begin
        ANotes[j + 1] := ANotes[j];
        Dec(j);
      end;
      ANotes[j + 1] := Note;
    end;
    Result := True;
  finally
    Data.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Addresses
  --------------------------------------------------------------------------- }

function RepoPathOfUrl(const AUrl: string): string;
var
  Rest: string;
  p, Slashes, i: integer;
begin
  Result := '';
  p := Pos('://', AUrl);
  if p = 0 then
    Exit;
  Rest := Copy(AUrl, p + 3, MaxInt);
  p := Pos('/', Rest);
  if p = 0 then
    Exit;
  Rest := Copy(Rest, p + 1, MaxInt);
  { owner/repo: up to the second slash, or the end. }
  Slashes := 0;
  for i := 1 to Length(Rest) do
  begin
    if Rest[i] = '/' then
    begin
      Inc(Slashes);
      if Slashes = 2 then
      begin
        Rest := Copy(Rest, 1, i - 1);
        Break;
      end;
    end;
  end;
  if Pos('/', Rest) > 0 then
    Result := Rest;
end;

function GitHubWebArgs(const ATarget: TGittanWebTarget): TStringArray;
var
  Target: string;
begin
  case ATarget.Kind of
    wtFile:
    begin
      Target := ATarget.Path;
      if ATarget.Line > 0 then
        Target := Target + ':' + IntToStr(ATarget.Line);
      if ATarget.Commit <> '' then
        Result := [Target, '--commit=' + ATarget.Commit]
      else if ATarget.Branch <> '' then
        Result := [Target, '--branch', ATarget.Branch]
      else
        Result := [Target];
    end;
    wtCommit:
      Result := [ATarget.Commit];
    wtIssue:
      Result := [IntToStr(ATarget.Number)];
    else
      Result := nil;
  end;
end;

function GitHubNewPullUrl(const ARepoUrl, ABranch, AHeadRepo: string): string;
var
  Url, Base, Head: string;
  c: char;
begin
  Url := Trim(ARepoUrl);
  while (Url <> '') and (Url[Length(Url)] = '/') do
    SetLength(Url, Length(Url) - 1);
  Head := '';
  for c in ABranch do
    if c in ['A'..'Z', 'a'..'z', '0'..'9', '-', '.', '_', '~', '/'] then
      Head := Head + c
    else
      Head := Head + '%' + IntToHex(Ord(c), 2);
  Base := RepoPathOfUrl(Url);
  if (AHeadRepo <> '') and (Pos('/', AHeadRepo) > 1) and not SameText(AHeadRepo, Base) then
    Head := Copy(AHeadRepo, 1, Pos('/', AHeadRepo) - 1) + ':' + Head;
  Result := Url + '/compare/' + Head + '?expand=1';
end;

{ ---------------------------------------------------------------------------
  The jobs
  --------------------------------------------------------------------------- }

type
  { gh pr view, gh pr list, gh pr list --search review-requested:@me and
    gh api user. }
  TGitHubPullJob = class(TGittanPullRequestJob)
  private
    FExe: string;
  protected
    function AskBranchPull(out APull: TGittanPullRequest): boolean; override;
    function AskOpenPulls(out APulls: TGittanPullRequests; out AError: string): boolean;
      override;
    function AskReviewPulls(out APulls: TGittanPullRequests): boolean; override;
    function AskLogin(out ALogin: string): boolean; override;
  public
    constructor Create(const AExe, ARoot, ABranch, ALogin: string);
  end;

  { gh pr review, gh pr merge or gh pr ready (GitHubPullActionArgs). }
  TGitHubPullActionJob = class(TGittanPullActionJob)
  private
    FExe: string;
  protected
    function Ask(out AError: string): boolean; override;
  public
    constructor Create(const AExe, ARoot, ARepo: string; ANumber: integer;
      AAction: TGittanPullAction; const AText: string);
  end;

  { gh api graphql with ReviewThreadsQuery, a page of 100 threads at a
    time, at most twenty pages. }
  TGitHubReviewJob = class(TGittanReviewJob)
  private
    FExe: string;
  protected
    function Ask(out AError: string): boolean; override;
  public
    constructor Create(const AExe, ARoot, ARepoPath: string; ANumber: integer);
  end;

  { gh api graphql with ForgeQuery. }
  TGitHubAccountJob = class(TGittanForgeJob)
  private
    FExe: string;
  protected
    function Ask(out ALogin: string; out AMine, AReview: TGittanForgePulls;
      out AError: string): boolean; override;
  public
    constructor Create(const AExe, AForgeName, ARoot: string);
  end;

constructor TGitHubPullJob.Create(const AExe, ARoot, ABranch, ALogin: string);
begin
  inherited Create(ARoot, ABranch, ALogin);
  FExe := AExe;
end;

function TGitHubPullJob.AskBranchPull(out APull: TGittanPullRequest): boolean;
var
  Output, Err: string;
begin
  APull := Default(TGittanPullRequest);
  { No selector: gh takes the branch checked out in Root and knows where
    it is pushed, which a name alone would not say for a fork. }
  Result := RunGh(FExe, Root, ['pr', 'view', '--json', PullRequestFields], Output, Err) and
    ParsePullRequest(Output, APull);
end;

function TGitHubPullJob.AskOpenPulls(out APulls: TGittanPullRequests;
  out AError: string): boolean;
var
  Output: string;
begin
  APulls := nil;
  Result := RunGh(FExe, Root, ['pr', 'list', '--state', 'open', '--limit', '50', '--json',
    PullRequestFields], Output, AError);
  if not Result then
    Exit;
  AError := '';
  Result := ParsePullRequests(Output, APulls);
  if not Result then
    AError := 'Could not read the pull requests gh listed.';
end;

{ GitHub's own search knows who gh is logged in as and the teams they
  are on. }
function TGitHubPullJob.AskReviewPulls(out APulls: TGittanPullRequests): boolean;
var
  Output, Err: string;
begin
  APulls := nil;
  Result := RunGh(FExe, Root, ['pr', 'list', '--state', 'open', '--limit', '50', '--search',
    'review-requested:@me', '--json', PullRequestFields], Output, Err) and
    ParsePullRequests(Output, APulls);
end;

function TGitHubPullJob.AskLogin(out ALogin: string): boolean;
var
  Output, Err: string;
begin
  Result := RunGh(FExe, Root, ['api', 'user', '--jq', '.login'], Output, Err);
  ALogin := '';
  if Result then
    ALogin := Trim(Output);
  Result := ALogin <> '';
end;

constructor TGitHubReviewJob.Create(const AExe, ARoot, ARepoPath: string; ANumber: integer);
begin
  inherited Create(ARoot, ARepoPath, ANumber);
  FExe := AExe;
end;

function TGitHubReviewJob.Ask(out AError: string): boolean;
var
  Owner, RepoName, Output, Cursor, Head: string;
  HasNext: boolean;
  Pages, p: integer;
begin
  AError := '';
  Result := True;
  p := Pos('/', RepoPath);
  Owner := Copy(RepoPath, 1, p - 1);
  RepoName := Copy(RepoPath, p + 1, MaxInt);
  Cursor := '';
  Pages := 0;
  repeat
    { -f passes the names as strings even when they look like numbers;
      -F types the number. }
    if Cursor = '' then
      HasNext := RunGh(FExe, Root, ['api', 'graphql', '-f', 'owner=' + Owner,
        '-f', 'name=' + RepoName, '-F', 'number=' + IntToStr(Number),
        '-f', 'query=' + ReviewThreadsQuery], Output, AError)
    else
      HasNext := RunGh(FExe, Root, ['api', 'graphql', '-f', 'owner=' + Owner,
        '-f', 'name=' + RepoName, '-F', 'number=' + IntToStr(Number),
        '-f', 'after=' + Cursor, '-f', 'query=' + ReviewThreadsQuery], Output, AError);
    if Terminated then
      Exit;
    if not HasNext then
      Exit(False);
    if not ParseReviewThreads(Output, FThreads, Head, HasNext, Cursor) then
    begin
      AError := 'Could not read the review comments gh fetched.';
      Exit(False);
    end;
    if Pages = 0 then
    begin
      FHeadOid := Head;
      ParsePullNotes(Output, FNotes);
    end;
    Inc(Pages);
  until not HasNext or (Pages >= 20);
end;

constructor TGitHubAccountJob.Create(const AExe, AForgeName, ARoot: string);
begin
  inherited Create(AForgeName, ARoot);
  FExe := AExe;
end;

function TGitHubAccountJob.Ask(out ALogin: string; out AMine, AReview: TGittanForgePulls;
  out AError: string): boolean;
var
  Output, Url: string;
begin
  ALogin := '';
  AMine := nil;
  AReview := nil;
  { Any folder does; gh needs none in particular for it. }
  Result := RunGh(FExe, Root, ['api', 'graphql', '-f', 'query=' + ForgeQuery], Output, AError)
    and ParseForgeAnswer(Output, ALogin, Url, AMine, AReview, AError);
  AvatarUrl := Url;
end;

{ ---------------------------------------------------------------------------
  The forge
  --------------------------------------------------------------------------- }

var
  { The hosts of gh's hosts.yml as last read, with the file's path and
    text then, so it is parsed again only when it has changed:
    ForgeClassFor asks for every remote of every repository. The file
    is read only when its size or time changed, or when it was written
    in the second it was last read, as its time counts whole seconds
    and an account switched then would be missed; the text read is
    compared, so an unchanged file is not parsed again. Main thread
    only. }
  LoggedHosts: TStringArray;
  LoggedAccounts: TGittanForgeAccounts;
  LoggedHostsPath: string;
  LoggedHostsText: RawByteString;
  LoggedHostsRead: boolean;
  LoggedHostsStamp: TDateTime;
  LoggedHostsSize: int64;
  LoggedHostsAt: TDateTime;

{ The hosts gh is logged in to, the file parsed again when it changed
  (none when it is not there, and none logged in). }
function GhLoggedHosts: TStringArray;
var
  Path: string;
  Text: RawByteString;
  Info: TSearchRec;
  Stamp: TDateTime;
  Size: int64;
begin
  Path := IncludeTrailingPathDelimiter(GhConfigDir) + 'hosts.yml';
  Stamp := 0;
  Size := -1;
  if StatExact(Path, Info) then
  begin
    Stamp := Info.TimeStamp;
    Size := Info.Size;
    FindClose(Info);
  end;
  { Unchanged, and read in a later second than it was written. }
  if LoggedHostsRead and (Path = LoggedHostsPath) and (Stamp = LoggedHostsStamp) and
    (Size = LoggedHostsSize) and (LoggedHostsAt >= Stamp + 2 / SecsPerDay) then
    Exit(LoggedHosts);
  LoggedHostsStamp := Stamp;
  LoggedHostsSize := Size;
  LoggedHostsAt := Now;
  Text := '';
  if Size >= 0 then
    try
      Text := ReadFileBytes(Path);
    except
      Text := '';
    end;
  if not LoggedHostsRead or (Text <> LoggedHostsText) or (Path <> LoggedHostsPath) then
  begin
    LoggedHostsRead := True;
    LoggedHostsText := Text;
    LoggedHostsPath := Path;
    LoggedHosts := GhHosts(Text);
    LoggedAccounts := GhAccounts(Text);
  end;
  Result := LoggedHosts;
end;

class function TGittanGitHubForge.HostsRemote(const AHost: string): boolean;
var
  Host, Token, Enterprise: string;
begin
  Result := (AHost = 'github.com') or (AHost = 'www.github.com') or
    (AHost = 'ssh.github.com');
  if Result then
    Exit;
  for Host in GhLoggedHosts do
    if Host = AHost then
      Exit(True);
  { An Enterprise host gh is given a token for in its environment. }
  Token := EnvironmentVariable('GH_TOKEN');
  if Token = '' then
    Token := EnvironmentVariable('GITHUB_TOKEN');
  Enterprise := EnvironmentVariable('GH_ENTERPRISE_TOKEN');
  if Enterprise = '' then
    Enterprise := EnvironmentVariable('GITHUB_ENTERPRISE_TOKEN');
  Host := GhEnvHost(EnvironmentVariable('GH_HOST'), Token, Enterprise);
  Result := (Host <> '') and (Host = AHost);
end;

class function TGittanGitHubForge.Accounts: TGittanForgeAccounts;
begin
  GhLoggedHosts;
  Result := Copy(LoggedAccounts);
end;

class function TGittanGitHubForge.AccountsNote: string;

  function FirstSet(const AA, AB: string): string;
  begin
    if EnvironmentVariable(AA) <> '' then
      Result := AA
    else if EnvironmentVariable(AB) <> '' then
      Result := AB
    else
      Result := '';
  end;

var
  Token, Enterprise: string;
begin
  Result := '';
  Token := FirstSet('GH_TOKEN', 'GITHUB_TOKEN');
  Enterprise := FirstSet('GH_ENTERPRISE_TOKEN', 'GITHUB_ENTERPRISE_TOKEN');
  if Token <> '' then
    Result := Token + ' is set in Gittan''s environment, so gh uses that token ' +
      'on github.com and ghe.com whichever account is picked here.';
  if Enterprise <> '' then
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + Enterprise + ' is set in Gittan''s environment, so gh uses ' +
      'that token on Enterprise Server hosts whichever account is picked here.';
  end;
end;

function TGittanGitHubForge.SwitchAccount(const AHost, ALogin: string;
  out AError: string): boolean;
var
  Output: string;
begin
  AError := '';
  Result := (Cli <> '') and RunGh(Cli, GetUserDir,
    ['auth', 'switch', '--hostname', AHost, '--user', ALogin], Output, AError);
  { gh marks its failure with an X, a cross on a terminal. }
  AError := Trim(AError);
  if AError.StartsWith('X ') then
    AError := Trim(Copy(AError, 3, MaxInt));
  if not Result and (AError = '') then
    AError := 'gh could not switch to ' + ALogin + ' on ' + AHost + '.';
end;

class function TGittanGitHubForge.Name: string;
begin
  Result := 'GitHub';
end;

class function TGittanGitHubForge.CliName: string;
begin
  Result := 'gh';
end;

{ gh --version prints "gh version 2.62.0 (2024-11-14)" and a link. }
function TGittanGitHubForge.Version(out AVersion: string): boolean;
var
  Output, Err: string;
  i: integer;
begin
  AVersion := '';
  Result := (Cli <> '') and RunGh(Cli, GetUserDir, ['--version'], Output, Err);
  if not Result then
    Exit;
  AVersion := Trim(Output);
  i := Pos(#10, AVersion);
  if i > 0 then
    AVersion := Trim(Copy(AVersion, 1, i - 1));
  if Pos('gh version ', AVersion) = 1 then
    Delete(AVersion, 1, Length('gh version '));
  i := Pos(' ', AVersion);
  if i > 0 then
    AVersion := Copy(AVersion, 1, i - 1);
end;

function GitHubPullActionArgs(const ARepo: string; ANumber: integer;
  AAction: TGittanPullAction; const AText: string): TStringArray;
begin
  case AAction of
    plApprove: Result := ['pr', 'review', IntToStr(ANumber), '--repo', ARepo, '--approve'];
    plRequestChanges: Result := ['pr', 'review', IntToStr(ANumber), '--repo', ARepo,
      '--request-changes'];
    plComment: Result := ['pr', 'review', IntToStr(ANumber), '--repo', ARepo, '--comment'];
    plMerge: Result := ['pr', 'merge', IntToStr(ANumber), '--repo', ARepo, '--merge'];
    plSquash: Result := ['pr', 'merge', IntToStr(ANumber), '--repo', ARepo, '--squash'];
    plRebaseMerge: Result := ['pr', 'merge', IntToStr(ANumber), '--repo', ARepo, '--rebase'];
    else
      Result := ['pr', 'ready', IntToStr(ANumber), '--repo', ARepo];
  end;
  if PullActionIsReview(AAction) and (Trim(AText) <> '') then
    Result := Concat(Result, ['--body', AText]);
end;

constructor TGitHubPullActionJob.Create(const AExe, ARoot, ARepo: string; ANumber: integer;
  AAction: TGittanPullAction; const AText: string);
begin
  inherited Create(ARoot, ARepo, ANumber, AAction, AText);
  FExe := AExe;
end;

function TGitHubPullActionJob.Ask(out AError: string): boolean;
var
  Output: string;
begin
  AError := '';
  Result := RunGh(FExe, Root, GitHubPullActionArgs(Repo, Number, Action, Text), Output, AError);
  AError := Trim(AError);
  if AError.StartsWith('X ') then
    AError := Trim(Copy(AError, 3, MaxInt));
  if not Result and (AError = '') then
    AError := 'gh could not do it.';
end;

class function TGittanGitHubForge.HasPullActions: boolean;
begin
  Result := True;
end;

function TGittanGitHubForge.ActionJob(const ARoot, ARepo: string; ANumber: integer;
  AAction: TGittanPullAction; const AText: string): TGittanPullActionJob;
begin
  Result := TGitHubPullActionJob.Create(Cli, ARoot, ARepo, ANumber, AAction, AText);
end;

function TGittanGitHubForge.PullJob(const ARoot, ABranch, ALogin: string): TGittanPullRequestJob;
begin
  Result := TGitHubPullJob.Create(Cli, ARoot, ABranch, ALogin);
end;

function TGittanGitHubForge.ReviewJob(const ARoot, ARepo: string;
  ANumber: integer): TGittanReviewJob;
begin
  Result := TGitHubReviewJob.Create(Cli, ARoot, ARepo, ANumber);
end;

function TGittanGitHubForge.AccountJob(const ARoot: string): TGittanForgeJob;
begin
  Result := TGitHubAccountJob.Create(Cli, Name, ARoot);
end;

{ gh browse with --no-browser only prints the address. }
function TGittanGitHubForge.WebUrl(const ARoot: string; const ATarget: TGittanWebTarget;
  out AUrl, AError: string): boolean;
var
  Args, Target: TStringArray;
  i: integer;
begin
  AUrl := '';
  Target := GitHubWebArgs(ATarget);
  Args := nil;
  SetLength(Args, Length(Target) + 2);
  Args[0] := 'browse';
  Args[1] := '--no-browser';
  for i := 0 to High(Target) do
    Args[i + 2] := Target[i];
  Result := RunGh(Cli, ARoot, Args, AUrl, AError);
  AUrl := Trim(AUrl);
  Result := Result and (AUrl <> '');
  if Result and (ATarget.Kind = wtNewPull) then
    AUrl := GitHubNewPullUrl(AUrl, ATarget.Branch, ATarget.HeadRepo);
end;

function GitHubFileOfUrl(const AUrl: string; out ARepo, APath: string;
  out ALine: integer): boolean;
var
  Rest, Fragment: string;
  Parts: TStringArray;
  p, i: integer;
begin
  Result := False;
  ARepo := '';
  APath := '';
  ALine := 0;
  p := Pos('://', AUrl);
  if (p = 0) or not SameText(Copy(AUrl, 1, p - 1), 'https') and
    not SameText(Copy(AUrl, 1, p - 1), 'http') then
    Exit;
  Rest := Copy(AUrl, p + 3, MaxInt);
  Fragment := '';
  p := Pos('#', Rest);
  if p > 0 then
  begin
    Fragment := Copy(Rest, p + 1, MaxInt);
    SetLength(Rest, p - 1);
  end;
  p := Pos('?', Rest);
  if p > 0 then
    SetLength(Rest, p - 1);
  Parts := Rest.Split('/');
  { github.com, owner, name, blob, the ref, then the path. }
  if (Length(Parts) < 6) or not (SameText(Parts[0], 'github.com') or
    SameText(Parts[0], 'www.github.com')) or (Parts[1] = '') or (Parts[2] = '') or
    (Parts[3] <> 'blob') or (Parts[4] = '') then
    Exit;
  ARepo := Parts[1] + '/' + Parts[2];
  for i := 5 to High(Parts) do
  begin
    if Parts[i] = '' then
      Exit;
    if APath <> '' then
      APath := APath + '/';
    APath := APath + Parts[i];
  end;
  { A space and the like come escaped. }
  p := Pos('%', APath);
  while (p > 0) and (p + 2 <= Length(APath)) do
  begin
    i := StrToIntDef('$' + Copy(APath, p + 1, 2), -1);
    if i >= 0 then
      APath := Copy(APath, 1, p - 1) + Chr(i) + Copy(APath, p + 3, MaxInt);
    p := Pos('%', APath, p + 1);
  end;
  if (Fragment <> '') and (Fragment[1] = 'L') then
  begin
    p := 2;
    while (p <= Length(Fragment)) and (Fragment[p] in ['0'..'9']) do
      Inc(p);
    ALine := StrToIntDef(Copy(Fragment, 2, p - 2), 0);
  end;
  Result := True;
end;

function TGittanGitHubForge.FileOfWebUrl(const AUrl: string; out ARepo, APath: string;
  out ALine: integer): boolean;
begin
  Result := GitHubFileOfUrl(AUrl, ARepo, APath, ALine);
end;

function TGittanGitHubForge.PullRef(ANumber: integer): string;
begin
  Result := 'refs/pull/' + IntToStr(ANumber) + '/head';
end;

initialization
  RegisterForge(TGittanGitHubForge);

end.
