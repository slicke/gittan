unit gittan.github;

{** GitHub through gh, GitHub's command line tool: the pull request of a
  branch and the open pull requests of a repository, read from the JSON
  gh prints (with when each was opened and changed, what it changes
  and its labels, for the Pull Requests page), and a job that fetches
  both in a thread. Nothing here needs the LCL. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.job;

type
  {** The latest review a reviewer gave a pull request. }
  TGittanLatestReview = record
    Login, State: string;
  end;

  {** One pull request as gh pr view and gh pr list describe it. State is
    OPEN, CLOSED or MERGED; ReviewDecision is APPROVED, CHANGES_REQUESTED,
    REVIEW_REQUIRED or empty when no review is asked for. }
  TGittanPullRequest = record
    Number: integer;
    Title, State, ReviewDecision, Url, HeadRef, BaseRef, Author: string;
    IsDraft: boolean;
    { The checks of the head commit (statusCheckRollup): how many passed
      (or were skipped or neutral), failed (or were cancelled, timed out,
      or need action) and are still running or queued. }
    ChecksPassed, ChecksFailed, ChecksPending: integer;
    { When it was opened and last changed, in UTC (0 when gh gave
      none), what it changes, and the names of its labels joined with
      ", ". }
    Created, Updated: TDateTime;
    Additions, Deletions, ChangedFiles: integer;
    Labels: string;
    { The latest review of each reviewer (latestReviews): who and its
      state, APPROVED, CHANGES_REQUESTED, COMMENTED or DISMISSED; and
      the logins of the users a review is asked of now
      (reviewRequests, teams left out). }
    Reviews: array of TGittanLatestReview;
    Requested: array of string;
  end;
  TGittanPullRequests = array of TGittanPullRequest;

const
  {** The fields asked of gh, the ones the record holds. }
  PullRequestFields = 'number,title,state,reviewDecision,url,headRefName,baseRefName,' +
    'author,isDraft,statusCheckRollup,createdAt,updatedAt,additions,deletions,changedFiles,' +
    'labels,latestReviews,reviewRequests';

{** Reads the object gh pr view --json prints. }
function ParsePullRequest(const AJson: string; out APull: TGittanPullRequest): boolean;
{** Reads the array gh pr list --json prints. }
function ParsePullRequests(const AJson: string; out APulls: TGittanPullRequests): boolean;
{** APulls without the ones ALogin has already approved or requested
  changes on (their latest review): GitHub's review-requested search
  keeps a pull request asked of a team the user is on after their
  review, which only a personal request loses. A review that only
  commented, or was dismissed, leaves the pull request in, and so does
  a request made of ALogin in person after their review (Requested).
  An empty ALogin leaves all in. }
function WithoutReviewed(const APulls: TGittanPullRequests;
  const ALogin: string): TGittanPullRequests;
{** The short line of the status bar: "PR #12 · Approved", "PR #12 · Draft",
  "PR #12 · Merged", with the review decision in words, and the checks
  after it when there are any: "checks ✓", "2 checks failing" or
  "3 checks pending". }
function PullRequestStatus(const APull: TGittanPullRequest): string;
{** The checks part of PullRequestStatus alone, empty without checks. }
function PullRequestChecks(const APull: TGittanPullRequest): string;
{** The state part of PullRequestStatus alone: Merged, Closed, Draft,
  Approved, Changes requested or Review required, else empty. }
function PullRequestNote(const APull: TGittanPullRequest): string;
{** "owner/repo" of a GitHub address such as https://github.com/owner/repo/pull/12,
  empty when the address is not one. }
function RepoPathOfUrl(const AUrl: string): string;
{** The first issue or pull request number a commit summary names, as
  "#123" (a digit must follow the sign, and the sign must not follow a
  word, so "C#5" is not one); 0 when it names none. }
function IssueNumber(const ASummary: string): integer;

type
  {** Runs gh pr view for the branch checked out in a repository (ABranch
    only says which; empty skips it) and gh pr list, in a thread, since
    both go to the network, and gh pr list again with
    review-requested:@me for the open pull requests waiting for the
    user's review (ReviewPulls), less the ones the user has reviewed
    (WithoutReviewed, by the login gh is logged in as, ALogin, which
    the job asks gh for when none is given: Login after the job for
    the next one). OnDone is called in the main thread
    when all are done, as long as the job has not been stopped. A branch
    with no pull request is not a failure: HasPull is false and Error
    empty. The job also asks the remotes which local branches track a
    branch that is gone from them (GoneBranches), as GitHub deletes a
    merged one. }
  TGittanPullRequestJob = class(TGittanJob)
  private
    FExe, FRoot, FBranch, FLogin: string;
    FPull: TGittanPullRequest;
    FHasPull: boolean;
    FGone: TStringList;
    FPulls, FReviewPulls: TGittanPullRequests;
    FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const AExe, ARoot, ABranch: string; const ALogin: string = '');
    destructor Destroy; override;
    property Branch: string read FBranch;
    {** The login gh is logged in as, as given or as gh answered;
      empty when gh could not say. }
    property Login: string read FLogin;
    property Pull: TGittanPullRequest read FPull;
    property HasPull: boolean read FHasPull;
    {** The local branches whose upstream is deleted on its remote. }
    property GoneBranches: TStringList read FGone;
    property Pulls: TGittanPullRequests read FPulls;
    {** The open pull requests whose review is asked of the user gh is
      logged in as, or of a team they are on (GitHub's own
      review-requested:@me search), without the ones they have reviewed;
      empty when gh could not list them. }
    property ReviewPulls: TGittanPullRequests read FReviewPulls;
    {** gh's message when the list could not be read (no GitHub remote,
      not logged in), else empty. }
    property Error: string read FError;
  end;

implementation

uses
  DateUtils, fpjson, jsonparser, gittan.git;

{ A time as gh prints it, "2026-10-20T12:34:56Z", in UTC; 0 when the
  field is missing or not a time. }
function TimeOf(AObject: TJSONObject; const AName: string): TDateTime;
begin
  if not TryISO8601ToDate(AObject.Get(AName, ''), Result, True) then
    Result := 0;
end;

{ A CheckRun has a status (COMPLETED, IN_PROGRESS, QUEUED, ...) and, once
  completed, a conclusion; a StatusContext (the older commit status API)
  has a state. }
procedure CountCheck(ACheck: TJSONObject; var APull: TGittanPullRequest);
var
  Verdict: string;
begin
  if ACheck.Get('__typename', '') = 'StatusContext' then
    Verdict := ACheck.Get('state', '')
  else if ACheck.Get('status', '') = 'COMPLETED' then
    Verdict := ACheck.Get('conclusion', '')
  else
    Verdict := 'PENDING';
  case Verdict of
    'SUCCESS', 'SKIPPED', 'NEUTRAL':
      Inc(APull.ChecksPassed);
    'FAILURE', 'ERROR', 'CANCELLED', 'TIMED_OUT', 'ACTION_REQUIRED', 'STARTUP_FAILURE':
      Inc(APull.ChecksFailed);
    else
      Inc(APull.ChecksPending);
  end;
end;

function ReadPull(AObject: TJSONObject; out APull: TGittanPullRequest): boolean;
var
  Author, Checks, Labels, Reviews, Reviewer, Requests: TJSONData;
  i, n: integer;
  Name: string;
begin
  APull := Default(TGittanPullRequest);
  Result := AObject.IndexOfName('number') >= 0;
  if not Result then
    Exit;
  APull.Number := AObject.Get('number', 0);
  APull.Title := AObject.Get('title', '');
  APull.State := AObject.Get('state', '');
  APull.ReviewDecision := AObject.Get('reviewDecision', '');
  APull.Url := AObject.Get('url', '');
  APull.HeadRef := AObject.Get('headRefName', '');
  APull.BaseRef := AObject.Get('baseRefName', '');
  APull.IsDraft := AObject.Get('isDraft', False);
  Author := AObject.Find('author');
  if (Author <> nil) and (Author.JSONType = jtObject) then
    APull.Author := TJSONObject(Author).Get('login', '');
  Checks := AObject.Find('statusCheckRollup');
  if (Checks <> nil) and (Checks.JSONType = jtArray) then
    for i := 0 to TJSONArray(Checks).Count - 1 do
      if TJSONArray(Checks)[i].JSONType = jtObject then
        CountCheck(TJSONObject(TJSONArray(Checks)[i]), APull);
  APull.Created := TimeOf(AObject, 'createdAt');
  APull.Updated := TimeOf(AObject, 'updatedAt');
  APull.Additions := AObject.Get('additions', 0);
  APull.Deletions := AObject.Get('deletions', 0);
  APull.ChangedFiles := AObject.Get('changedFiles', 0);
  Labels := AObject.Find('labels');
  if (Labels <> nil) and (Labels.JSONType = jtArray) then
    for i := 0 to TJSONArray(Labels).Count - 1 do
      if TJSONArray(Labels)[i].JSONType = jtObject then
      begin
        Name := TJSONObject(TJSONArray(Labels)[i]).Get('name', '');
        if Name = '' then
          Continue;
        if APull.Labels <> '' then
          APull.Labels := APull.Labels + ', ';
        APull.Labels := APull.Labels + Name;
      end;
  Reviews := AObject.Find('latestReviews');
  if (Reviews <> nil) and (Reviews.JSONType = jtArray) then
    for i := 0 to TJSONArray(Reviews).Count - 1 do
      if TJSONArray(Reviews)[i].JSONType = jtObject then
      begin
        Reviewer := TJSONObject(TJSONArray(Reviews)[i]).Find('author');
        if (Reviewer = nil) or (Reviewer.JSONType <> jtObject) then
          Continue;
        n := Length(APull.Reviews);
        SetLength(APull.Reviews, n + 1);
        APull.Reviews[n].Login := TJSONObject(Reviewer).Get('login', '');
        APull.Reviews[n].State := TJSONObject(TJSONArray(Reviews)[i]).Get('state', '');
      end;
  Requests := AObject.Find('reviewRequests');
  if (Requests <> nil) and (Requests.JSONType = jtArray) then
    for i := 0 to TJSONArray(Requests).Count - 1 do
      if TJSONArray(Requests)[i].JSONType = jtObject then
      begin
        Name := TJSONObject(TJSONArray(Requests)[i]).Get('login', '');
        if Name = '' then
          Continue;
        n := Length(APull.Requested);
        SetLength(APull.Requested, n + 1);
        APull.Requested[n] := Name;
      end;
end;

function WithoutReviewed(const APulls: TGittanPullRequests;
  const ALogin: string): TGittanPullRequests;
var
  i, j, n: integer;
  Reviewed: boolean;
begin
  Result := nil;
  if ALogin = '' then
    Exit(Copy(APulls));
  n := 0;
  SetLength(Result, Length(APulls));
  for i := 0 to High(APulls) do
  begin
    Reviewed := False;
    for j := 0 to High(APulls[i].Reviews) do
      if SameText(APulls[i].Reviews[j].Login, ALogin) and
        ((APulls[i].Reviews[j].State = 'APPROVED') or
        (APulls[i].Reviews[j].State = 'CHANGES_REQUESTED')) then
        Reviewed := True;
    { Asked again, in person, after the review. }
    for j := 0 to High(APulls[i].Requested) do
      if SameText(APulls[i].Requested[j], ALogin) then
        Reviewed := False;
    if Reviewed then
      Continue;
    Result[n] := APulls[i];
    Inc(n);
  end;
  SetLength(Result, n);
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
  Items: TJSONArray;
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
    Items := TJSONArray(Data);
    SetLength(APulls, Items.Count);
    n := 0;
    for i := 0 to Items.Count - 1 do
      if (Items[i].JSONType = jtObject) and ReadPull(TJSONObject(Items[i]), APulls[n]) then
        Inc(n);
    SetLength(APulls, n);
    Result := True;
  finally
    Data.Free;
  end;
end;

function PullRequestNote(const APull: TGittanPullRequest): string;
begin
  if APull.State = 'MERGED' then
    Result := 'Merged'
  else if APull.State = 'CLOSED' then
    Result := 'Closed'
  else if APull.IsDraft then
    Result := 'Draft'
  else if APull.ReviewDecision = 'APPROVED' then
    Result := 'Approved'
  else if APull.ReviewDecision = 'CHANGES_REQUESTED' then
    Result := 'Changes requested'
  else if APull.ReviewDecision = 'REVIEW_REQUIRED' then
    Result := 'Review required'
  else
    Result := '';
end;

function PullRequestStatus(const APull: TGittanPullRequest): string;
var
  Note: string;
begin
  Note := PullRequestNote(APull);
  Result := 'PR #' + IntToStr(APull.Number);
  if Note <> '' then
    Result := Result + ' · ' + Note;
  Note := PullRequestChecks(APull);
  if Note <> '' then
    Result := Result + ' · ' + Note;
end;

function PullRequestChecks(const APull: TGittanPullRequest): string;
begin
  if APull.ChecksFailed > 0 then
    Result := IntToStr(APull.ChecksFailed) + ' checks failing'
  else if APull.ChecksPending > 0 then
    Result := IntToStr(APull.ChecksPending) + ' checks pending'
  else if APull.ChecksPassed > 0 then
    Result := 'checks ✓'
  else
    Result := '';
  if (APull.ChecksFailed = 1) or ((APull.ChecksFailed = 0) and (APull.ChecksPending = 1)) then
    Result := StringReplace(Result, 'checks', 'check', []);
end;

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

function IssueNumber(const ASummary: string): integer;
var
  i, j: integer;
begin
  Result := 0;
  i := 1;
  while i < Length(ASummary) do
  begin
    if (ASummary[i] = '#') and (ASummary[i + 1] in ['0'..'9']) and
      ((i = 1) or not (ASummary[i - 1] in ['0'..'9', 'a'..'z', 'A'..'Z', '_'])) then
    begin
      j := i + 1;
      while (j <= Length(ASummary)) and (ASummary[j] in ['0'..'9']) do
        Inc(j);
      Result := StrToIntDef(Copy(ASummary, i + 1, j - i - 1), 0);
      if Result > 0 then
        Exit;
    end;
    Inc(i);
  end;
end;

{ ---------------------------------------------------------------------------
  The job
  --------------------------------------------------------------------------- }

constructor TGittanPullRequestJob.Create(const AExe, ARoot, ABranch: string;
  const ALogin: string);
begin
  inherited Create(True);
  FExe := AExe;
  FRoot := ARoot;
  FBranch := ABranch;
  FLogin := ALogin;
  FGone := TStringList.Create;
end;

destructor TGittanPullRequestJob.Destroy;
begin
  inherited Destroy;
  FGone.Free;
end;

procedure TGittanPullRequestJob.Execute;
var
  Output, Err: string;
begin
  { No selector: gh takes the branch checked out in FRoot and knows
    where it is pushed, which a name alone would not say for a fork. }
  if (FBranch <> '') and RunGitHubCli(FExe, FRoot, ['pr', 'view', '--json',
    PullRequestFields], Output, Err) then
    FHasPull := ParsePullRequest(Output, FPull);
  if Terminated then
    Exit;
  if RunGitHubCli(FExe, FRoot, ['pr', 'list', '--state', 'open', '--limit', '50',
    '--json', PullRequestFields], Output, Err) then
  begin
    if not ParsePullRequests(Output, FPulls) then
      FError := 'Could not read the pull requests gh listed.';
  end
  else
    FError := Err;
  if Terminated then
    Exit;
  { Those waiting for the user's review, by GitHub's own search, which
    knows who gh is logged in as and the teams they are on. A review
    given clears a personal request but not a team's, so the ones the
    user has reviewed are taken out by their login, asked of gh once. }
  if (FError = '') and RunGitHubCli(FExe, FRoot, ['pr', 'list', '--state', 'open',
    '--limit', '50', '--search', 'review-requested:@me', '--json', PullRequestFields],
    Output, Err) then
  begin
    if not ParsePullRequests(Output, FReviewPulls) then
      FReviewPulls := nil;
  end;
  if Terminated then
    Exit;
  if (FLogin = '') and (Length(FReviewPulls) > 0) and
    RunGitHubCli(FExe, FRoot, ['api', 'user', '--jq', '.login'], Output, Err) then
    FLogin := Trim(Output);
  FReviewPulls := WithoutReviewed(FReviewPulls, FLogin);
  if not Terminated then
    GoneUpstreamsIn(FRoot, FGone);
  Done;
end;

end.
