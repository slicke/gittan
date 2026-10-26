unit gittan.forge;

{** The user's pull requests across every repository of a forge, the
  service that hosts them: the open ones they wrote and the open ones
  waiting for their review, for the forge page. A forge is named by
  TGittanForgeKind; GitHub is the only one so far, read through gh
  with one GraphQL query (ForgeQuery), and another forge adds a kind,
  a job that fills the same records and a name. Nothing here needs the
  LCL. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.job;

type
  {** The forges: GitHub through gh. }
  TGittanForgeKind = (fkGitHub);

  {** One pull request as a forge lists it. Repo is "owner/name"; State
    is OPEN, CLOSED or MERGED; ReviewDecision APPROVED,
    CHANGES_REQUESTED, REVIEW_REQUIRED or empty; Checks the state of
    the head commit's checks as one word, SUCCESS, FAILURE, PENDING,
    ERROR or EXPECTED, empty without checks; MyReview the state of the
    user's latest review of it, empty without one; Requested whether
    the user is asked for a review now, in person (a request a review
    clears, and a new one brings back). }
  TGittanForgePull = record
    Repo: string;
    Number: integer;
    Title, Url, Author, HeadRef, BaseRef, State, ReviewDecision, Checks, MyReview: string;
    IsDraft, Requested: boolean;
    Created, Updated: TDateTime;
  end;
  TGittanForgePulls = array of TGittanForgePull;

const
  {** The GraphQL query gh runs: the login, the open pull requests the
    user wrote and the open ones a review is asked of them for (in
    person or through a team), fifty of each, newest first. }
  ForgeQuery =
    'query { viewer { login } ' +
    'mine: search(query: "is:pr is:open author:@me archived:false sort:updated-desc", ' +
    'type: ISSUE, first: 50) { issueCount nodes { ...pull } } ' +
    'review: search(query: "is:pr is:open review-requested:@me archived:false ' +
    'sort:updated-desc", type: ISSUE, first: 50) { issueCount nodes { ...pull } } } ' +
    'fragment pull on PullRequest { number title url isDraft state reviewDecision ' +
    'createdAt updatedAt author { login } repository { nameWithOwner } ' +
    'headRefName baseRefName viewerLatestReview { state } ' +
    'viewerLatestReviewRequest { id } ' +
    'commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } }';

{** The name of a forge, "GitHub". }
function ForgeName(AKind: TGittanForgeKind): string;

{** Reads the answer to ForgeQuery: the login, the pull requests the
  user wrote (AMine) and those asked of them (AReview, as the forge
  lists them, see NeedsMyReview). False when AJson is not the answer,
  with the query's first error message in AError when it carries one. }
function ParseForgeAnswer(const AJson: string; out ALogin: string;
  out AMine, AReview: TGittanForgePulls; out AError: string): boolean;

{** Whether a pull request listed as waiting for the user's review
  still is: one the user is asked for in person now, whatever they
  said before (a request made again after their review), or one whose
  latest review by the user neither approved it nor asked for changes.
  The forge keeps a request made of a team the user is on after their
  review, which only a personal request loses. }
function NeedsMyReview(const APull: TGittanForgePull): boolean;

{** AReview without the pull requests the user has reviewed, by
  NeedsMyReview. }
function StillToReview(const AReview: TGittanForgePulls): TGittanForgePulls;

type
  {** Asks a forge for the user's pull requests in a thread. Kind says
    which forge; Login, Mine and Review hold the answer, Review already
    without the ones the user has reviewed (StillToReview); Error the
    forge's or its tool's message when it failed. }
  TGittanForgeJob = class(TGittanJob)
  private
    FKind: TGittanForgeKind;
    FLogin, FError: string;
    FMine, FReview: TGittanForgePulls;
  protected
    procedure Ask(out AOutput, AError: string; out AOk: boolean); virtual; abstract;
    procedure Execute; override;
  public
    constructor Create(AKind: TGittanForgeKind);
    property Kind: TGittanForgeKind read FKind;
    property Login: string read FLogin;
    property Mine: TGittanForgePulls read FMine;
    property Review: TGittanForgePulls read FReview;
    property Error: string read FError;
  end;

  {** GitHub through gh: `gh api graphql` with ForgeQuery, run in ARoot
    (any folder does; gh needs none in particular for it). }
  TGittanGitHubForgeJob = class(TGittanForgeJob)
  private
    FExe, FRoot: string;
  protected
    procedure Ask(out AOutput, AError: string; out AOk: boolean); override;
  public
    constructor Create(const AExe, ARoot: string);
  end;

implementation

uses
  DateUtils, fpjson, jsonparser, gittan.git;

function ForgeName(AKind: TGittanForgeKind): string;
begin
  case AKind of
    fkGitHub: Result := 'GitHub';
    else
      Result := '';
  end;
end;

{ A time as the forge prints it, "2026-10-20T12:34:56Z", in UTC; 0
  when the field is missing or not a time. }
function TimeOf(AObject: TJSONObject; const AName: string): TDateTime;
var
  S: string;
begin
  Result := 0;
  S := AObject.Get(AName, '');
  if S = '' then
    Exit;
  try
    Result := ISO8601ToDate(S, True);
  except
    Result := 0;
  end;
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
    Result := TJSONObject(Inner).Get(AName, '');
end;

function ReadForgePull(AObject: TJSONObject; out APull: TGittanForgePull): boolean;
var
  Request, Commits, Node, Commit, Rollup: TJSONData;
begin
  APull := Default(TGittanForgePull);
  Result := AObject.IndexOfName('number') >= 0;
  if not Result then
    Exit;
  APull.Number := AObject.Get('number', 0);
  APull.Title := AObject.Get('title', '');
  APull.Url := AObject.Get('url', '');
  APull.IsDraft := AObject.Get('isDraft', False);
  APull.State := AObject.Get('state', '');
  APull.ReviewDecision := AObject.Get('reviewDecision', '');
  APull.Created := TimeOf(AObject, 'createdAt');
  APull.Updated := TimeOf(AObject, 'updatedAt');
  APull.Author := NestedString(AObject, 'author', 'login');
  APull.Repo := NestedString(AObject, 'repository', 'nameWithOwner');
  APull.HeadRef := AObject.Get('headRefName', '');
  APull.BaseRef := AObject.Get('baseRefName', '');
  APull.MyReview := NestedString(AObject, 'viewerLatestReview', 'state');
  Request := AObject.Find('viewerLatestReviewRequest');
  APull.Requested := (Request <> nil) and (Request.JSONType = jtObject);
  { commits.nodes[0].commit.statusCheckRollup.state }
  Commits := AObject.Find('commits');
  if (Commits <> nil) and (Commits.JSONType = jtObject) then
  begin
    Node := TJSONObject(Commits).Find('nodes');
    if (Node <> nil) and (Node.JSONType = jtArray) and (TJSONArray(Node).Count > 0) and
      (TJSONArray(Node)[0].JSONType = jtObject) then
    begin
      Commit := TJSONObject(TJSONArray(Node)[0]).Find('commit');
      if (Commit <> nil) and (Commit.JSONType = jtObject) then
      begin
        Rollup := TJSONObject(Commit).Find('statusCheckRollup');
        if (Rollup <> nil) and (Rollup.JSONType = jtObject) then
          APull.Checks := TJSONObject(Rollup).Get('state', '');
      end;
    end;
  end;
end;

{ The pull requests of a search's nodes; nodes that are not pull
  requests are skipped. }
procedure ReadSearch(AData: TJSONObject; const AName: string; out APulls: TGittanForgePulls);
var
  Search, Nodes: TJSONData;
  i, n: integer;
  Pull: TGittanForgePull;
begin
  APulls := nil;
  Search := AData.Find(AName);
  if (Search = nil) or (Search.JSONType <> jtObject) then
    Exit;
  Nodes := TJSONObject(Search).Find('nodes');
  if (Nodes = nil) or (Nodes.JSONType <> jtArray) then
    Exit;
  SetLength(APulls, TJSONArray(Nodes).Count);
  n := 0;
  for i := 0 to TJSONArray(Nodes).Count - 1 do
    if (TJSONArray(Nodes)[i].JSONType = jtObject) and
      ReadForgePull(TJSONObject(TJSONArray(Nodes)[i]), Pull) then
    begin
      APulls[n] := Pull;
      Inc(n);
    end;
  SetLength(APulls, n);
end;

function ParseForgeAnswer(const AJson: string; out ALogin: string;
  out AMine, AReview: TGittanForgePulls; out AError: string): boolean;
var
  Root: TJSONData;
  Data, Errors: TJSONData;
begin
  ALogin := '';
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
    if (Errors <> nil) and (Errors.JSONType = jtArray) and (TJSONArray(Errors).Count > 0) and
      (TJSONArray(Errors)[0].JSONType = jtObject) then
      AError := TJSONObject(TJSONArray(Errors)[0]).Get('message', '');
    Data := TJSONObject(Root).Find('data');
    if (Data = nil) or (Data.JSONType <> jtObject) then
      Exit;
    ALogin := NestedString(TJSONObject(Data), 'viewer', 'login');
    ReadSearch(TJSONObject(Data), 'mine', AMine);
    ReadSearch(TJSONObject(Data), 'review', AReview);
    Result := True;
  finally
    Root.Free;
  end;
end;

function NeedsMyReview(const APull: TGittanForgePull): boolean;
begin
  Result := APull.Requested or not ((APull.MyReview = 'APPROVED') or
    (APull.MyReview = 'CHANGES_REQUESTED'));
end;

function StillToReview(const AReview: TGittanForgePulls): TGittanForgePulls;
var
  i, n: integer;
begin
  Result := nil;
  SetLength(Result, Length(AReview));
  n := 0;
  for i := 0 to High(AReview) do
    if NeedsMyReview(AReview[i]) then
    begin
      Result[n] := AReview[i];
      Inc(n);
    end;
  SetLength(Result, n);
end;

{ ---------------------------------------------------------------------------
  The jobs
  --------------------------------------------------------------------------- }

constructor TGittanForgeJob.Create(AKind: TGittanForgeKind);
begin
  inherited Create(True);
  FKind := AKind;
end;

procedure TGittanForgeJob.Execute;
var
  Output, Err: string;
  Ok: boolean;
begin
  Ask(Output, Err, Ok);
  if Terminated then
    Exit;
  if not Ok then
    FError := Err
  else if not ParseForgeAnswer(Output, FLogin, FMine, FReview, FError) then
  begin
    if FError = '' then
      FError := 'Could not read the answer of ' + ForgeName(FKind) + '.';
  end
  else
    FReview := StillToReview(FReview);
  if (FError = '') and (Length(FMine) = 0) and (Length(FReview) = 0) and (FLogin = '') then
    FError := 'The answer of ' + ForgeName(FKind) + ' had no login in it.';
  Done;
end;

constructor TGittanGitHubForgeJob.Create(const AExe, ARoot: string);
begin
  inherited Create(fkGitHub);
  FExe := AExe;
  FRoot := ARoot;
end;

procedure TGittanGitHubForgeJob.Ask(out AOutput, AError: string; out AOk: boolean);
begin
  AOk := RunGitHubCli(FExe, FRoot, ['api', 'graphql', '-f', 'query=' + ForgeQuery],
    AOutput, AError);
end;

end.
