unit gittan.github;

{** GitHub through gh, GitHub's command line tool: the pull request of a
  branch and the open pull requests of a repository, read from the JSON
  gh prints, and a job that fetches both in a thread. Nothing here needs
  the LCL. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  {** One pull request as gh pr view and gh pr list describe it. State is
    OPEN, CLOSED or MERGED; ReviewDecision is APPROVED, CHANGES_REQUESTED,
    REVIEW_REQUIRED or empty when no review is asked for. }
  TGittanPullRequest = record
    Number: integer;
    Title, State, ReviewDecision, Url, HeadRef, BaseRef, Author: string;
    IsDraft: boolean;
  end;
  TGittanPullRequests = array of TGittanPullRequest;

const
  {** The fields asked of gh, the ones the record holds. }
  PullRequestFields = 'number,title,state,reviewDecision,url,headRefName,baseRefName,' +
    'author,isDraft';

{** Reads the object gh pr view --json prints. }
function ParsePullRequest(const AJson: string; out APull: TGittanPullRequest): boolean;
{** Reads the array gh pr list --json prints. }
function ParsePullRequests(const AJson: string; out APulls: TGittanPullRequests): boolean;
{** The short line of the status bar: "PR #12 · Approved", "PR #12 · Draft",
  "PR #12 · Merged", with the review decision in words. }
function PullRequestStatus(const APull: TGittanPullRequest): string;
{** "owner/repo" of a GitHub address such as https://github.com/owner/repo/pull/12,
  empty when the address is not one. }
function RepoPathOfUrl(const AUrl: string): string;

type
  {** Runs gh pr view for the branch checked out in a repository (ABranch
    only says which; empty skips it) and gh pr list, in a thread, since
    both go to the network. OnDone is called in the main thread when both are
    done, as long as the job has not been stopped. A branch with no pull
    request is not a failure: HasPull is false and Error empty. }
  TGittanPullRequestJob = class(TThread)
  private
    FExe, FRoot, FBranch: string;
    FPull: TGittanPullRequest;
    FHasPull: boolean;
    FPulls: TGittanPullRequests;
    FError: string;
    FOnDone: TNotifyEvent;
    procedure Notify;
  protected
    procedure Execute; override;
  public
    constructor Create(const AExe, ARoot, ABranch: string);
    {** Drops the handler and ends the thread; a result still on its way
      is thrown away. Waits for a running gh only when AWait is set. }
    procedure Stop(AWait: boolean);
    property Branch: string read FBranch;
    property Pull: TGittanPullRequest read FPull;
    property HasPull: boolean read FHasPull;
    property Pulls: TGittanPullRequests read FPulls;
    {** gh's message when the list could not be read (no GitHub remote,
      not logged in), else empty. }
    property Error: string read FError;
    property OnDone: TNotifyEvent read FOnDone write FOnDone;
  end;

implementation

uses
  fpjson, jsonparser, gittan.git;

function ReadPull(AObject: TJSONObject; out APull: TGittanPullRequest): boolean;
var
  Author: TJSONData;
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

function PullRequestStatus(const APull: TGittanPullRequest): string;
var
  Note: string;
begin
  if APull.State = 'MERGED' then
    Note := 'Merged'
  else if APull.State = 'CLOSED' then
    Note := 'Closed'
  else if APull.IsDraft then
    Note := 'Draft'
  else if APull.ReviewDecision = 'APPROVED' then
    Note := 'Approved'
  else if APull.ReviewDecision = 'CHANGES_REQUESTED' then
    Note := 'Changes requested'
  else if APull.ReviewDecision = 'REVIEW_REQUIRED' then
    Note := 'Review required'
  else
    Note := '';
  Result := 'PR #' + IntToStr(APull.Number);
  if Note <> '' then
    Result := Result + ' · ' + Note;
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

{ ---------------------------------------------------------------------------
  The job
  --------------------------------------------------------------------------- }

constructor TGittanPullRequestJob.Create(const AExe, ARoot, ABranch: string);
begin
  inherited Create(True);
  FExe := AExe;
  FRoot := ARoot;
  FBranch := ABranch;
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
  if not Terminated then
    Queue(@Notify);
end;

procedure TGittanPullRequestJob.Notify;
begin
  if Assigned(FOnDone) and not Terminated then
    FOnDone(Self);
end;

procedure TGittanPullRequestJob.Stop(AWait: boolean);
begin
  FOnDone := nil;
  Terminate;
  if AWait then
    WaitFor;
end;

end.
