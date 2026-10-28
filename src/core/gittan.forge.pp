unit gittan.forge;

{** The service that hosts a repository, a forge (GitHub, GitLab,
  Bitbucket), as Gittan sees it: what a pull request is (TGittanPullRequest
  for the open repository's, TGittanForgePull for the user's across every
  repository), the background jobs that read them (their forge-specific
  part a virtual Ask), and TGittanForge, the class a forge inherits:
  its name, the tool it runs, the jobs it makes, the address of a file,
  a commit or an issue, and where a remote serves a pull request's head.
  Nothing here names a forge; GitHub is TGittanGitHubForge in
  gittan.github, and another forge is a unit of its own beside it,
  which registers its class as it loads (RegisterForge), so the rest of
  Gittan makes one through ForgeClass without naming it. Nothing here
  needs the LCL. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.job, gittan.reviews;

const
  {** A pull request unchanged this many days is stale (IsStale). }
  StaleDays = 30;

type
  {** Where a pull request stands. }
  TGittanPullState = (prOpen, prClosed, prMerged);

  {** What the reviews of a pull request add up to, as the forge decides
    it from its rules: none asked for, a review still required, approved,
    or changes requested. }
  TGittanReviewDecision = (rdNone, rdReviewRequired, rdApproved, rdChangesRequested);

  {** What one reviewer's review said. }
  TGittanReviewVerdict = (rvNone, rvCommented, rvApproved, rvChangesRequested, rvDismissed);

  {** The checks of a commit taken together: none, all passed, some still
    running, or one failed. }
  TGittanChecksState = (chkNone, chkPassed, chkPending, chkFailed);

  {** The latest review a reviewer gave a pull request. }
  TGittanLatestReview = record
    Login: string;
    Verdict: TGittanReviewVerdict;
  end;

  {** One pull request of the open repository. Repo is its repository as
    "owner/name" (the path the forge serves it at). }
  TGittanPullRequest = record
    Number: integer;
    Repo, Title, Url, HeadRef, BaseRef, Author: string;
    State: TGittanPullState;
    ReviewDecision: TGittanReviewDecision;
    IsDraft: boolean;
    { The checks of the head commit: how many passed (or were skipped or
      neutral), failed (or were cancelled, timed out, or need action)
      and are still running or queued. }
    ChecksPassed, ChecksFailed, ChecksPending: integer;
    { When it was opened and last changed, in UTC (0 when the forge gave
      none), what it changes, and the names of its labels joined with
      ", ". }
    Created, Updated: TDateTime;
    Additions, Deletions, ChangedFiles: integer;
    Labels: string;
    { The latest review of each reviewer, and the logins of the users a
      review is asked of now (teams left out). }
    Reviews: array of TGittanLatestReview;
    Requested: array of string;
  end;
  TGittanPullRequests = array of TGittanPullRequest;

  {** One pull request of the user's, as the forge lists them across
    every repository. Repo is "owner/name"; Checks the head commit's
    checks; MyReview what the user's latest review of it said;
    Requested whether the user is asked for a review now, in person (a
    request a review clears, and a new one brings back); Feedback
    whether someone other than its author, and not a bot, has commented
    on it or reviewed it (among its last thirty comments and last thirty
    reviews); Clone the root of a local clone of its repository, from
    the folders the job was given (FindClones), else empty. }
  TGittanForgePull = record
    Repo: string;
    Number: integer;
    Title, Url, Author, HeadRef, BaseRef: string;
    State: TGittanPullState;
    ReviewDecision: TGittanReviewDecision;
    Checks: TGittanChecksState;
    MyReview: TGittanReviewVerdict;
    IsDraft, Requested, Feedback: boolean;
    Created, Updated: TDateTime;
    Clone: string;
  end;
  TGittanForgePulls = array of TGittanForgePull;

  {** What a list of the user's pull requests can be narrowed to: the
    ones with Feedback, the ones that need attention (NeedsAttention),
    no drafts, the ones the user is asked to review in person
    (Requested), the stale ones (IsStale). }
  TGittanForgeFilter = (ffFeedback, ffAttention, ffNoDrafts, ffAskedOfMe, ffStale);
  TGittanForgeFilters = set of TGittanForgeFilter;

  {** What a web address is asked for: a file (Path, at Line when above
    0, in Commit, else on Branch, else the default branch), a commit
    (Commit), an issue or pull request (Number), or the page that opens
    a new pull request from Branch (in HeadRepo, "owner/repo", when it
    is pushed to another repository than the forge's, a fork). }
  TGittanWebKind = (wtFile, wtCommit, wtIssue, wtNewPull);
  TGittanWebTarget = record
    Kind: TGittanWebKind;
    Path, Commit, Branch, HeadRepo: string;
    Line, Number: integer;
  end;

{** A file's TGittanWebTarget. }
function FileTarget(const APath: string; ALine: integer;
  const ACommit, ABranch: string): TGittanWebTarget;
{** A commit's TGittanWebTarget. }
function CommitTarget(const ACommit: string): TGittanWebTarget;
{** An issue's or a pull request's TGittanWebTarget. }
function IssueTarget(ANumber: integer): TGittanWebTarget;
{** The TGittanWebTarget of a new pull request from ABranch, pushed to
  AHeadRepo ("owner/repo"; empty when not known). }
function NewPullTarget(const ABranch, AHeadRepo: string): TGittanWebTarget;

{** APulls without the ones ALogin has already approved or requested
  changes on (their latest review): a forge's search for the reviews
  asked of the user keeps a pull request asked of a team they are on
  after their review, which only a personal request loses. A review
  that only commented, or was dismissed, leaves the pull request in,
  and so does a request made of ALogin in person after their review
  (Requested). An empty ALogin leaves all in. }
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
{** The review decision in words: Approved, Changes requested, Review
  required, empty for none. }
function ReviewDecisionNote(ADecision: TGittanReviewDecision): string;
{** The first issue or pull request number a commit summary names, as
  "#123" (a digit must follow the sign, and the sign must not follow a
  word, so "C#5" is not one); 0 when it names none. }
function IssueNumber(const ASummary: string): integer;

{** Fills in the Clone of each of APulls with the first of ARoots (the
  roots of repositories, the likeliest first) one of whose remotes holds
  its repository; a root that is gone or no repository is passed over.
  Runs git once per root, in the caller's thread. }
procedure FindClones(var APulls: TGittanForgePulls; ARoots: TStrings);
{** Adds to ARoots, after them, the repositories beside them: the
  folders in each of their parent folders that hold a .git (a folder,
  or a file as a worktree or a submodule has), in name order, each once
  and none already in ARoots. }
procedure AddSiblingRepositories(ARoots: TStrings);

{** Whether a pull request listed as waiting for the user's review
  still is: one the user is asked for in person now, whatever they
  said before (a request made again after their review), or one whose
  latest review by the user neither approved it nor asked for changes.
  A forge keeps a request made of a team the user is on after their
  review, which only a personal request loses. }
function NeedsMyReview(const APull: TGittanForgePull): boolean;
{** AReview without the pull requests the user has reviewed, by
  NeedsMyReview. }
function StillToReview(const AReview: TGittanForgePulls): TGittanForgePulls;
{** APulls without the ones nobody but their author has answered (no
  Feedback). }
function WithFeedback(const APulls: TGittanForgePulls): TGittanForgePulls;
{** Whether APull needs its author to act: changes were asked for or
  its checks fail. }
function NeedsAttention(const APull: TGittanForgePull): boolean;
{** Whether APull has not changed for StaleDays at ANow (UTC): its
  last change, or its opening when it has none, that long ago. }
function IsStale(const APull: TGittanForgePull; ANow: TDateTime): boolean;
{** Whether APull passes AFilter at ANow (UTC). }
function PassesFilter(const APull: TGittanForgePull; AFilter: TGittanForgeFilter;
  ANow: TDateTime): boolean;
{** APulls without the ones that fail any of AFilters at ANow (UTC), in
  their order. }
function FilterPulls(const APulls: TGittanForgePulls; AFilters: TGittanForgeFilters;
  ANow: TDateTime): TGittanForgePulls;
{** APull as a TGittanPullRequest, for what works on the repository's
  own pull requests (a comparison): the fields both have, the rest
  empty. }
function PullRequestOf(const APull: TGittanForgePull): TGittanPullRequest;

type
  {** Reads, in a thread since it goes to the network, the pull request
    of the branch checked out in a repository (ABranch only says which;
    empty skips it), the open pull requests of the repository, and the
    open ones waiting for the user's review (ReviewPulls), less the ones
    the user has reviewed (WithoutReviewed, by the login ALogin, which
    the job asks the forge for when none is given: Login after the job
    for the next one). A branch with no pull request is not a failure:
    HasPull is false and Error empty. The job also asks the remotes which
    local branches track a branch that is gone from them (GoneBranches),
    as a forge deletes a merged one. A forge fills in the Ask methods. }
  TGittanPullRequestJob = class(TGittanJob)
  private
    FRoot, FBranch, FLogin: string;
    FPull: TGittanPullRequest;
    FHasPull: boolean;
    FGone: TStringList;
    FPulls, FReviewPulls: TGittanPullRequests;
    FError: string;
  protected
    {** The pull request of the branch checked out in Root; false when it
      has none or the forge could not say. }
    function AskBranchPull(out APull: TGittanPullRequest): boolean; virtual; abstract;
    {** The open pull requests of the repository at Root; false with the
      reason in AError when they could not be read. }
    function AskOpenPulls(out APulls: TGittanPullRequests; out AError: string): boolean;
      virtual; abstract;
    {** The open pull requests whose review is asked of the user, or of a
      team they are on; false when they could not be read. }
    function AskReviewPulls(out APulls: TGittanPullRequests): boolean; virtual; abstract;
    {** The login the forge knows the user by; false when it could not
      say. }
    function AskLogin(out ALogin: string): boolean; virtual; abstract;
    procedure Execute; override;
    property Root: string read FRoot;
  public
    constructor Create(const ARoot, ABranch, ALogin: string);
    destructor Destroy; override;
    property Branch: string read FBranch;
    {** The login the forge knows the user by, as given or as the forge
      answered; empty when it could not say. }
    property Login: string read FLogin;
    property Pull: TGittanPullRequest read FPull;
    property HasPull: boolean read FHasPull;
    {** The local branches whose upstream is deleted on its remote. }
    property GoneBranches: TStringList read FGone;
    property Pulls: TGittanPullRequests read FPulls;
    {** The open pull requests whose review is asked of the user, or of a
      team they are on, without the ones they have reviewed; empty when
      the forge could not list them. }
    property ReviewPulls: TGittanPullRequests read FReviewPulls;
    {** The forge's or its tool's message when the list could not be read
      (no remote on the forge, not logged in), else empty. }
    property Error: string read FError;
  end;

  {** Asks a forge, in a thread, for the user's pull requests across
    every repository. Login, Mine and Review hold the answer, Review
    already without the ones the user has reviewed (StillToReview); Error
    the forge's or its tool's message when it failed. ForgeName names the
    forge in a message. A forge fills in Ask. }
  TGittanForgeJob = class(TGittanJob)
  private
    FForgeName, FRoot, FLogin, FError: string;
    FAvatarUrl, FKnownAvatarUrl, FAvatar: string;
    FMine, FReview: TGittanForgePulls;
    FClones: TStringList;
    FSiblings: boolean;
    function Cancelled: boolean;
    procedure FetchAvatar;
  protected
    {** The login and the two lists, the review list as the forge gives
      it; false with the reason in AError when they could not be read. }
    function Ask(out ALogin: string; out AMine, AReview: TGittanForgePulls;
      out AError: string): boolean; virtual; abstract;
    procedure Execute; override;
    property Root: string read FRoot;
    {** The address of the user's picture, which Ask sets when the forge
      gives one; Execute fetches it (Avatar). }
    property AvatarUrl: string read FAvatarUrl write FAvatarUrl;
  public
    constructor Create(const AForgeName, ARoot: string);
    destructor Destroy; override;
    {** The roots of the repositories to look for clones in, the likeliest
      first (FindClones), set before the job starts; empty looks for none. }
    property Clones: TStringList read FClones;
    {** Whether the repositories beside Clones are looked in too, after
      them (AddSiblingRepositories). }
    property Siblings: boolean read FSiblings write FSiblings;
    property ForgeName: string read FForgeName;
    property Login: string read FLogin;
    {** The address of the picture already held, set before the job
      starts: a picture at the same address is not fetched again, and
      Avatar stays empty. }
    property KnownAvatarUrl: string read FKnownAvatarUrl write FKnownAvatarUrl;
    {** The address of the user's picture as the forge gave it, '' for
      none, and the picture's bytes (PNG or JPEG) when it was fetched;
      empty when it was not (known already, no answer, too large). }
    property PictureUrl: string read FAvatarUrl;
    property Avatar: string read FAvatar;
    property Mine: TGittanForgePulls read FMine;
    property Review: TGittanForgePulls read FReview;
    property Error: string read FError;
  end;

  {** An account the forge's tool is logged in to: Login on Host
    ("github.com"), Active for the one the tool uses on that host. }
  TGittanForgeAccount = record
    Host, Login: string;
    Active: boolean;
  end;
  TGittanForgeAccounts = array of TGittanForgeAccount;
  {** Accounts by forge, one entry per registered forge in their order. }
  TGittanForgeAccountsList = array of TGittanForgeAccounts;

  {** A forge, reached through its command line tool (Cli, a path to it).
    A forge inherits it and fills in the abstract methods; the jobs it
    makes are its own kinds of the jobs above and of TGittanReviewJob,
    which take what they need from it when they are made, so a job may
    outlive the forge (the settings change while it runs). }
  TGittanForge = class
  private
    FCli: string;
  public
    constructor Create(const ACli: string); virtual;
    {** The forge's name, as the interface shows it and the settings
      keep its section under: "GitHub". }
    class function Name: string; virtual; abstract;
    {** The name of its tool, as found on the search path: "gh". }
    class function CliName: string; virtual; abstract;
    {** Whether a remote on AHost (as RemoteHost gives it, "github.com")
      is on this forge, so a repository with it gets this forge
      (ForgeClassFor). }
    class function HostsRemote(const AHost: string): boolean; virtual; abstract;
    {** The accounts the tool is logged in to, each host's in the tool's
      order, read from the tool's own files without running it (cheap,
      main thread only, as a poll asks). None for a forge that keeps no
      such list, the base's answer. }
    class function Accounts: TGittanForgeAccounts; virtual;
    {** Why the account on a host is not the tool's active one, when
      something outside the tool's login decides it (a token in the
      environment); empty otherwise, the base's answer. }
    class function AccountsNote: string; virtual;
    property Cli: string read FCli;
    {** Makes ALogin the tool's active account on AHost, for the tool
      everywhere (a terminal too); false with the reason in AError. The
      base cannot. Runs the tool and waits for it. }
    function SwitchAccount(const AHost, ALogin: string; out AError: string): boolean;
      virtual;
    {** The tool's version, from its own --version, as "gh 2.62.0"; false
      when it could not be run. }
    function Version(out AVersion: string): boolean; virtual; abstract;
    {** A job for the open repository at ARoot's pull requests, see
      TGittanPullRequestJob. Not started. }
    function PullJob(const ARoot, ABranch, ALogin: string): TGittanPullRequestJob;
      virtual; abstract;
    {** A job for the review threads and the conversation of pull request
      ANumber of ARepo ("owner/name"), see TGittanReviewJob. Not started. }
    function ReviewJob(const ARoot, ARepo: string; ANumber: integer): TGittanReviewJob;
      virtual; abstract;
    {** A job for the user's pull requests across every repository, see
      TGittanForgeJob; ARoot is a folder to run in. Not started. }
    function AccountJob(const ARoot: string): TGittanForgeJob; virtual; abstract;
    {** The web address of ATarget for the repository at ARoot; false with
      the reason in AError when there is none (no remote on the forge). }
    function WebUrl(const ARoot: string; const ATarget: TGittanWebTarget;
      out AUrl, AError: string): boolean; virtual; abstract;
    {** The repository ("owner/name"), the file and the line (0 for none)
      of the web address of a file on the forge in some commit or on some
      branch, as a comment links to it; false for any other address. }
    function FileOfWebUrl(const AUrl: string; out ARepo, APath: string;
      out ALine: integer): boolean; virtual; abstract;
    {** The ref a remote of the forge serves pull request ANumber's head
      at, for git fetch: "refs/pull/12/head". }
    function PullRef(ANumber: integer): string; virtual; abstract;
  end;
  TGittanForgeClass = class of TGittanForge;
  TGittanForgeClasses = array of TGittanForgeClass;

{** Adds AClass to the forges Gittan knows; a forge's unit calls it in
  its initialization. }
procedure RegisterForge(AClass: TGittanForgeClass);
{** The forge Gittan uses where no repository decides, as for the
  user's pull requests across every repository: the first registered
  (GitHub, the one forge so far); nil while none is. }
function ForgeClass: TGittanForgeClass;
{** Every forge registered, in the order they were. }
function RegisteredForges: TGittanForgeClasses;
{** The forge of a repository whose remotes are AUrls (as
  ResolvedRemoteUrlsIn gives them, a "remote.<name>.url <url>" line
  each): the first registered that hosts one of them, the remotes taken
  in order; a host of an ssh URL no forge takes is looked up in ASshConfig
  (SshHostName; the text of ~/.ssh/config, UserSshConfig) and asked
  again, so github-work aliasing github.com is GitHub. Nil when none
  does (no remote, or none on a known forge). }
function ForgeClassFor(const AUrls: string; const ASshConfig: string): TGittanForgeClass;
  overload;
{** As above with the user's ~/.ssh/config, read only when the hosts as
  they are give no forge and one of them is an ssh remote's, and then
  only the aliases looked up. }
function ForgeClassFor(const AUrls: string): TGittanForgeClass; overload;
{** The active accounts of AAccounts as one string, "host=login" a line
  each, for telling whether the user switched: equal keys, the same
  accounts in use. }
function ActiveAccountsKey(const AAccounts: TGittanForgeAccounts): string;
{** Keeps AForge as the forge of AClass with the tool ACli: left as it
  is when it already is, else freed and made again, or left nil without
  a class or a tool. True when it changed, so what the old one found can
  be dropped. }
function KeepForge(var AForge: TGittanForge; AClass: TGittanForgeClass;
  const ACli: string): boolean;
{** The host name ssh connects to for AHost by AConfig (an ssh_config's
  text): the HostName of the first Host block whose patterns match it
  (* and ? wildcards, ! to exclude, case ignored; %h is AHost; the
  value may be in double quotes), the lines before the first Host applying to all; AHost itself when none
  sets one. Match blocks and Include are not followed. }
function SshHostName(const AHost, AConfig: string): string;
{** The text of the user's ~/.ssh/config, empty when there is none. }
function UserSshConfig: string;
{** The host of a remote's URL in lower case, without the user and the
  port: "github.com" of https://github.com/o/r.git, git@github.com:o/r.git
  and ssh://git@github.com:22/o/r; empty for a local path or a file://
  URL. }
function RemoteHost(const AUrl: string): string;
{** The repository's path on its host of a remote's URL, without ".git"
  and the slashes around it: "o/r" of https://github.com/o/r.git,
  git@github.com:o/r and ssh://git@github.com:22/o/r/; empty where
  RemoteHost is. }
function RemoteRepoPath(const AUrl: string): string;

implementation

uses
  gittan.git, gittan.http;

const
  { The largest picture taken, in bytes; a forge's are a few KB. }
  MaxAvatarBytes = 1024 * 1024;

var
  Forges: array of TGittanForgeClass;

procedure RegisterForge(AClass: TGittanForgeClass);
begin
  SetLength(Forges, Length(Forges) + 1);
  Forges[High(Forges)] := AClass;
end;

function ForgeClass: TGittanForgeClass;
begin
  if Length(Forges) = 0 then
    Exit(nil);
  Result := Forges[0];
end;

function RegisteredForges: TGittanForgeClasses;
begin
  Result := Copy(Forges);
end;

{ The registered forge that hosts AHost, nil for none. }
function ForgeOfHost(const AHost: string): TGittanForgeClass;
var
  i: integer;
begin
  for i := 0 to High(Forges) do
    if Forges[i].HostsRemote(AHost) then
      Exit(Forges[i]);
  Result := nil;
end;

{ Whether AUrl goes over ssh: user@host:path, or an ssh:// URL. }
function IsSshUrl(const AUrl: string): boolean;
var
  p: integer;
begin
  p := Pos('://', AUrl);
  if p = 0 then
    Result := RemoteHost(AUrl) <> ''
  else
    Result := Pos('ssh', LowerCase(Copy(AUrl, 1, p - 1))) > 0;
end;

{ The remotes in order, each host asked of the forges as it is, unless
  AAliasesOnly (a pass that did so already), then an ssh remote's host
  as ASshConfig resolves it when that differs. }
function ForgeClassIn(const AUrls, ASshConfig: string; AAliasesOnly: boolean): TGittanForgeClass;
var
  Line, Url, Host, Alias: string;
  p: integer;
begin
  for Line in AUrls.Split([#10]) do
  begin
    p := Pos(' ', Line);
    if p = 0 then
      Continue;
    Url := Trim(Copy(Line, p + 1, MaxInt));
    Host := RemoteHost(Url);
    if Host = '' then
      Continue;
    if not AAliasesOnly then
    begin
      Result := ForgeOfHost(Host);
      if Result <> nil then
        Exit;
    end;
    if IsSshUrl(Url) and (ASshConfig <> '') then
    begin
      Alias := LowerCase(SshHostName(Host, ASshConfig));
      if Alias <> Host then
      begin
        Result := ForgeOfHost(Alias);
        if Result <> nil then
          Exit;
      end;
    end;
  end;
  Result := nil;
end;

{ Whether one of AUrls is an ssh remote's, whose host may be an alias. }
function HasSshUrl(const AUrls: string): boolean;
var
  Line: string;
  p: integer;
begin
  for Line in AUrls.Split([#10]) do
  begin
    p := Pos(' ', Line);
    if (p > 0) and IsSshUrl(Trim(Copy(Line, p + 1, MaxInt))) then
      Exit(True);
  end;
  Result := False;
end;

function ForgeClassFor(const AUrls: string; const ASshConfig: string): TGittanForgeClass;
begin
  Result := ForgeClassIn(AUrls, ASshConfig, False);
end;

function ForgeClassFor(const AUrls: string): TGittanForgeClass;
begin
  { The config only when a host is not known as it is, and only the
    aliases then: the hosts were asked already. }
  Result := ForgeClassIn(AUrls, '', False);
  if (Result = nil) and HasSshUrl(AUrls) then
    Result := ForgeClassIn(AUrls, UserSshConfig, True);
end;

function KeepForge(var AForge: TGittanForge; AClass: TGittanForgeClass;
  const ACli: string): boolean;
begin
  if Assigned(AForge) then
    Result := (AForge.ClassType <> AClass) or (AForge.Cli <> ACli)
  else
    Result := (AClass <> nil) and (ACli <> '');
  if not Result then
    Exit;
  FreeAndNil(AForge);
  if (AClass <> nil) and (ACli <> '') then
    AForge := AClass.Create(ACli);
end;

{ Whether AText matches APattern, * any run and ? any one character,
  case ignored. }
function GlobMatch(const AText, APattern: string): boolean;

  function Match(t, p: integer): boolean;
  begin
    while p <= Length(APattern) do
    begin
      case APattern[p] of
        '*':
          begin
            while (p <= Length(APattern)) and (APattern[p] = '*') do
              Inc(p);
            if p > Length(APattern) then
              Exit(True);
            while t <= Length(AText) do
            begin
              if Match(t, p) then
                Exit(True);
              Inc(t);
            end;
            Exit(False);
          end;
        '?':
          if t > Length(AText) then
            Exit(False);
      else
        if (t > Length(AText)) or (LowerCase(AText[t]) <> LowerCase(APattern[p])) then
          Exit(False);
      end;
      Inc(t);
      Inc(p);
    end;
    Result := t > Length(AText);
  end;

begin
  Result := Match(1, 1);
end;

function SshHostName(const AHost, AConfig: string): string;
var
  Line, Keyword, Args, Pattern: string;
  Applies, Any, Excluded: boolean;
  p: integer;
begin
  Applies := True;
  for Line in AConfig.Split([#10]) do
  begin
    Args := Trim(Line);
    p := Pos('#', Args);
    if p > 0 then
      Args := Trim(Copy(Args, 1, p - 1));
    if Args = '' then
      Continue;
    { "Keyword value" or "Keyword=value". }
    p := 1;
    while (p <= Length(Args)) and not (Args[p] in [' ', #9, '=']) do
      Inc(p);
    Keyword := LowerCase(Copy(Args, 1, p - 1));
    Args := Trim(Copy(Args, p, MaxInt));
    if (Args <> '') and (Args[1] = '=') then
      Args := Trim(Copy(Args, 2, MaxInt));
    if Keyword = 'host' then
    begin
      Any := False;
      Excluded := False;
      for Pattern in Args.Split([' ', #9], TStringSplitOptions.ExcludeEmpty) do
        if (Pattern[1] = '!') and GlobMatch(AHost, Copy(Pattern, 2, MaxInt)) then
          Excluded := True
        else if (Pattern[1] <> '!') and GlobMatch(AHost, Pattern) then
          Any := True;
      Applies := Any and not Excluded;
    end
    else if Keyword = 'match' then
      Applies := False
    else if Applies and (Keyword = 'hostname') and (Args <> '') then
    begin
      { ssh takes a value in double quotes as well. }
      if (Length(Args) >= 2) and (Args[1] = '"') and (Args[Length(Args)] = '"') then
        Args := Trim(Copy(Args, 2, Length(Args) - 2));
      if Args <> '' then
        Exit(StringReplace(Args, '%h', AHost, [rfReplaceAll]));
    end;
  end;
  Result := AHost;
end;

function UserSshConfig: string;
var
  Lines: TStringList;
begin
  Result := '';
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(IncludeTrailingPathDelimiter(GetUserDir) + '.ssh' +
        PathDelim + 'config');
      Result := Lines.Text;
    except
      Result := '';
    end;
  finally
    Lines.Free;
  end;
end;

function RemoteHost(const AUrl: string): string;
var
  S: string;
  p, Colon, Slash: integer;
begin
  S := Trim(AUrl);
  p := Pos('://', S);
  if p > 0 then
  begin
    if SameText(Copy(S, 1, p - 1), 'file') then
      Exit('');
    S := Copy(S, p + 3, MaxInt);
    Slash := Pos('/', S);
    if Slash > 0 then
      S := Copy(S, 1, Slash - 1);
  end
  else
  begin
    { user@host:path; a colon after a slash, or a drive letter's, is a
      local path's. }
    Colon := Pos(':', S);
    Slash := Pos('/', S);
    if (Colon <= 2) or ((Slash > 0) and (Slash < Colon)) then
      Exit('');
  end;
  p := LastDelimiter('@', S);
  if p > 0 then
    S := Copy(S, p + 1, MaxInt);
  Colon := Pos(':', S);
  if Colon > 0 then
    S := Copy(S, 1, Colon - 1);
  Result := LowerCase(S);
end;

function RemoteRepoPath(const AUrl: string): string;
var
  S: string;
  p: integer;
begin
  Result := '';
  if RemoteHost(AUrl) = '' then
    Exit;
  S := Trim(AUrl);
  p := Pos('://', S);
  if p > 0 then
  begin
    S := Copy(S, p + 3, MaxInt);
    p := Pos('/', S);
    if p = 0 then
      Exit;
    S := Copy(S, p + 1, MaxInt);
  end
  else
    S := Copy(S, Pos(':', S) + 1, MaxInt);
  while (S <> '') and (S[Length(S)] = '/') do
    SetLength(S, Length(S) - 1);
  while (S <> '') and (S[1] = '/') do
    Delete(S, 1, 1);
  if SameText(Copy(S, Length(S) - 3, 4), '.git') then
    SetLength(S, Length(S) - 4);
  Result := S;
end;

function FileTarget(const APath: string; ALine: integer;
  const ACommit, ABranch: string): TGittanWebTarget;
begin
  Result := Default(TGittanWebTarget);
  Result.Kind := wtFile;
  Result.Path := APath;
  Result.Line := ALine;
  Result.Commit := ACommit;
  Result.Branch := ABranch;
end;

function CommitTarget(const ACommit: string): TGittanWebTarget;
begin
  Result := Default(TGittanWebTarget);
  Result.Kind := wtCommit;
  Result.Commit := ACommit;
end;

function IssueTarget(ANumber: integer): TGittanWebTarget;
begin
  Result := Default(TGittanWebTarget);
  Result.Kind := wtIssue;
  Result.Number := ANumber;
end;

function NewPullTarget(const ABranch, AHeadRepo: string): TGittanWebTarget;
begin
  Result := Default(TGittanWebTarget);
  Result.Kind := wtNewPull;
  Result.Branch := ABranch;
  Result.HeadRepo := AHeadRepo;
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
        (APulls[i].Reviews[j].Verdict in [rvApproved, rvChangesRequested]) then
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

function ReviewDecisionNote(ADecision: TGittanReviewDecision): string;
begin
  case ADecision of
    rdApproved: Result := 'Approved';
    rdChangesRequested: Result := 'Changes requested';
    rdReviewRequired: Result := 'Review required';
    else
      Result := '';
  end;
end;

function PullRequestNote(const APull: TGittanPullRequest): string;
begin
  if APull.State = prMerged then
    Result := 'Merged'
  else if APull.State = prClosed then
    Result := 'Closed'
  else if APull.IsDraft then
    Result := 'Draft'
  else
    Result := ReviewDecisionNote(APull.ReviewDecision);
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

procedure AddSiblingRepositories(ARoots: TStrings);
var
  Parents, Found: TStringList;
  Info: TSearchRec;
  Parent, Dir: string;
  i, j: integer;
begin
  Parents := TStringList.Create;
  Found := TStringList.Create;
  try
    for i := 0 to ARoots.Count - 1 do
    begin
      Parent := ExtractFileDir(ExcludeTrailingPathDelimiter(ARoots[i]));
      if (Parent = '') or (Parents.IndexOf(Parent) >= 0) then
        Continue;
      Parents.Add(Parent);
      Found.Clear;
      if FindFirst(IncludeTrailingPathDelimiter(Parent) + '*', faDirectory, Info) = 0 then
      try
        repeat
          if (Info.Attr and faDirectory = 0) or (Info.Name = '.') or (Info.Name = '..') then
            Continue;
          Dir := IncludeTrailingPathDelimiter(Parent) + Info.Name;
          if FileExists(Dir + PathDelim + '.git') or DirectoryExists(Dir + PathDelim + '.git') then
            Found.Add(Dir);
        until FindNext(Info) <> 0;
      finally
        FindClose(Info);
      end;
      Found.Sort;
      for j := 0 to Found.Count - 1 do
        if ARoots.IndexOf(Found[j]) < 0 then
          ARoots.Add(Found[j]);
    end;
  finally
    Parents.Free;
    Found.Free;
  end;
end;

procedure FindClones(var APulls: TGittanForgePulls; ARoots: TStrings);
var
  Urls: string;
  i, j: integer;
begin
  for j := 0 to High(APulls) do
    APulls[j].Clone := '';
  for i := 0 to ARoots.Count - 1 do
  begin
    if not DirectoryExists(ARoots[i]) then
      Continue;
    Urls := RemoteUrlsIn(ARoots[i]);
    if Urls = '' then
      Continue;
    for j := 0 to High(APulls) do
      if (APulls[j].Clone = '') and RemoteUrlsHold(Urls, APulls[j].Repo) then
        APulls[j].Clone := ARoots[i];
  end;
end;

function NeedsMyReview(const APull: TGittanForgePull): boolean;
begin
  Result := APull.Requested or not (APull.MyReview in [rvApproved, rvChangesRequested]);
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

function WithFeedback(const APulls: TGittanForgePulls): TGittanForgePulls;
var
  i, n: integer;
begin
  Result := nil;
  SetLength(Result, Length(APulls));
  n := 0;
  for i := 0 to High(APulls) do
    if APulls[i].Feedback then
    begin
      Result[n] := APulls[i];
      Inc(n);
    end;
  SetLength(Result, n);
end;

function NeedsAttention(const APull: TGittanForgePull): boolean;
begin
  Result := (APull.ReviewDecision = rdChangesRequested) or (APull.Checks = chkFailed);
end;

function IsStale(const APull: TGittanForgePull; ANow: TDateTime): boolean;
var
  Changed: TDateTime;
begin
  Changed := APull.Updated;
  if Changed <= 0 then
    Changed := APull.Created;
  Result := (Changed > 0) and (ANow - Changed >= StaleDays);
end;

function PassesFilter(const APull: TGittanForgePull; AFilter: TGittanForgeFilter;
  ANow: TDateTime): boolean;
begin
  case AFilter of
    ffFeedback: Result := APull.Feedback;
    ffAttention: Result := NeedsAttention(APull);
    ffNoDrafts: Result := not APull.IsDraft;
    ffAskedOfMe: Result := APull.Requested;
    ffStale: Result := IsStale(APull, ANow);
  else
    Result := True;
  end;
end;

function FilterPulls(const APulls: TGittanForgePulls; AFilters: TGittanForgeFilters;
  ANow: TDateTime): TGittanForgePulls;
var
  i, n: integer;
  F: TGittanForgeFilter;
  Keep: boolean;
begin
  Result := nil;
  SetLength(Result, Length(APulls));
  n := 0;
  for i := 0 to High(APulls) do
  begin
    Keep := True;
    for F in AFilters do
      Keep := Keep and PassesFilter(APulls[i], F, ANow);
    if Keep then
    begin
      Result[n] := APulls[i];
      Inc(n);
    end;
  end;
  SetLength(Result, n);
end;

function PullRequestOf(const APull: TGittanForgePull): TGittanPullRequest;
begin
  Result := Default(TGittanPullRequest);
  Result.Number := APull.Number;
  Result.Repo := APull.Repo;
  Result.Title := APull.Title;
  Result.Url := APull.Url;
  Result.HeadRef := APull.HeadRef;
  Result.BaseRef := APull.BaseRef;
  Result.Author := APull.Author;
  Result.State := APull.State;
  Result.ReviewDecision := APull.ReviewDecision;
  Result.IsDraft := APull.IsDraft;
  Result.Created := APull.Created;
  Result.Updated := APull.Updated;
end;

{ ---------------------------------------------------------------------------
  The jobs
  --------------------------------------------------------------------------- }

constructor TGittanPullRequestJob.Create(const ARoot, ABranch, ALogin: string);
begin
  inherited Create(True);
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
  Asked: string;
begin
  if FBranch <> '' then
    FHasPull := AskBranchPull(FPull);
  if Terminated then
    Exit;
  if not AskOpenPulls(FPulls, FError) then
    FPulls := nil;
  if Terminated then
    Exit;
  { A review given clears a personal request but not a team's, so the
    ones the user has reviewed are taken out by their login, asked of
    the forge once. }
  if (FError = '') and not AskReviewPulls(FReviewPulls) then
    FReviewPulls := nil;
  if Terminated then
    Exit;
  if (FLogin = '') and (Length(FReviewPulls) > 0) and AskLogin(Asked) then
    FLogin := Asked;
  FReviewPulls := WithoutReviewed(FReviewPulls, FLogin);
  if not Terminated then
    GoneUpstreamsIn(FRoot, FGone);
  Done;
end;

constructor TGittanForgeJob.Create(const AForgeName, ARoot: string);
begin
  inherited Create(True);
  FForgeName := AForgeName;
  FRoot := ARoot;
  FClones := TStringList.Create;
end;

destructor TGittanForgeJob.Destroy;
begin
  inherited Destroy;
  FClones.Free;
end;

procedure TGittanForgeJob.Execute;
begin
  if not Ask(FLogin, FMine, FReview, FError) then
  begin
    if FError = '' then
      FError := 'Could not read the answer of ' + FForgeName + '.';
  end
  else
  begin
    FReview := StillToReview(FReview);
    if FSiblings then
      AddSiblingRepositories(FClones);
    FindClones(FMine, FClones);
    FindClones(FReview, FClones);
  end;
  FetchAvatar;
  if Terminated then
    Exit;
  if (FError = '') and (Length(FMine) = 0) and (Length(FReview) = 0) and (FLogin = '') then
    FError := 'The answer of ' + FForgeName + ' had no login in it.';
  Done;
end;

function TGittanForgeJob.Cancelled: boolean;
begin
  Result := Terminated;
end;

{ The user's picture, unless it is the one held; a failure leaves it
  empty, and the page keeps the initial. }
procedure TGittanForgeJob.FetchAvatar;
var
  Response: TGittanHttpResponse;
begin
  if (FAvatarUrl = '') or (FAvatarUrl = FKnownAvatarUrl) or Terminated then
    Exit;
  Response := HttpGet(FAvatarUrl, [], 15, @Cancelled);
  if HttpOk(Response) and (Length(Response.Body) <= MaxAvatarBytes) then
    FAvatar := Response.Body;
end;

constructor TGittanForge.Create(const ACli: string);
begin
  inherited Create;
  FCli := ACli;
end;

class function TGittanForge.Accounts: TGittanForgeAccounts;
begin
  Result := nil;
end;

class function TGittanForge.AccountsNote: string;
begin
  Result := '';
end;

function TGittanForge.SwitchAccount(const AHost, ALogin: string;
  out AError: string): boolean;
begin
  AError := Name + ' cannot switch accounts.';
  Result := False;
end;

function ActiveAccountsKey(const AAccounts: TGittanForgeAccounts): string;
var
  Account: TGittanForgeAccount;
begin
  Result := '';
  for Account in AAccounts do
    if Account.Active then
      Result := Result + Account.Host + '=' + Account.Login + #10;
end;

end.
