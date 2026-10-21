unit gittan.remotejob;

{** Fetch, pull, push, clone and the submodules' update and add run in a
  thread: they go to the network, which can take its time, and the
  window must not hang meanwhile. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.git;

type
  {** What a TGittanRemoteJob does. }
  TGittanRemoteKind = (rkFetch, rkPull, rkPush, rkDeleteRemote, rkForcePush, rkPushBranch,
    rkPushTag, rkDeleteRemoteTag, rkClone, rkSubmoduleUpdate, rkSubmoduleAdd);

  {** Runs a fetch, a pull (the way Mode says), a push, a push with
    --force-with-lease, or the deletion of the remote branch Arg stands
    for (a remote-tracking branch such as origin/feature); or with
    Remote, the push of the local branch Arg to it as its upstream, the
    push of the tag Arg (every tag with Arg empty) and the deletion of
    the tag Arg on it; of the repository at ARoot through TGittanRepo,
    on a repository of its own. A clone makes the repository at ARoot
    from the URL Arg, with its submodules when Submodules is set. A
    submodule update updates the submodule at the path Arg, or every one
    with Arg empty; a submodule add clones the URL Arg into Path,
    following Branch.
    OnDone is called in the main thread when it is done, unless the job
    has been stopped. A job is never broken off, as a pull stopped
    halfway would leave a merge behind: Stop only drops the handler, and
    the thread is not terminated for it (a thread terminated before it
    starts never runs Execute). }
  TGittanRemoteJob = class(TThread)
  private
    FRoot, FArg, FRemote, FPath, FBranch: string;
    FKind: TGittanRemoteKind;
    FMode: TGittanPullMode;
    FOk, FDiverged, FRejected, FStale, FUnseen, FSubmodules: boolean;
    FError: string;
    FOnDone, FOnOutput: TNotifyEvent;
    FLock: TRTLCriticalSection;
    FProgress: string;
    FReturn, FOutputPending: boolean;
    function GetProgress: string;
    procedure Output(const AText: string);
    procedure Notify;
    procedure NotifyOutput;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: string; AKind: TGittanRemoteKind;
      AMode: TGittanPullMode = pmAuto; const AArg: string = '';
      const ARemote: string = '');
    destructor Destroy; override;
    {** Drops the handler, and waits for git to end when AWait is set, as
      on quitting. }
    procedure Stop(AWait: boolean);
    property Root: string read FRoot;
    property Kind: TGittanRemoteKind read FKind;
    property Mode: TGittanPullMode read FMode;
    property Arg: string read FArg;
    property Remote: string read FRemote;
    {** Whether a clone brings the submodules too; set before Start. }
    property Submodules: boolean read FSubmodules write FSubmodules;
    {** Where a submodule add puts the submodule, relative to the root;
      set before Start. }
    property Path: string read FPath write FPath;
    {** The branch a submodule add follows, empty for the remote's
      default; set before Start. }
    property Branch: string read FBranch write FBranch;
    {** Whether git did it. }
    property Ok: boolean read FOk;
    {** A pull that failed since the branch has diverged from its
      upstream: a merge or a rebase would do it. }
    property Diverged: boolean read FDiverged;
    {** A push that failed since the remote has commits the branch
      lacks: a pull would bring them first. }
    property Rejected: boolean read FRejected;
    {** A forced push that failed since the remote's branch has moved
      since the last fetch: a fetch would show what the push would lose. }
    property Stale: boolean read FStale;
    {** A forced push that failed since the upstream has commits a fetch
      brought in that were never in the branch: a pull would take them
      in first. }
    property Unseen: boolean read FUnseen;
    {** git's reason, when not Ok. }
    property Error: string read FError;
    {** What git and the hooks it runs have written so far, as a
      terminal would show it (a progress line written over keeps its
      last state), the newest ProgressKeep bytes of it. }
    property Progress: string read GetProgress;
    property OnDone: TNotifyEvent read FOnDone write FOnDone;
    {** Progress has grown; in the main thread, at most once per piece
      read and never after Stop. }
    property OnOutput: TNotifyEvent read FOnOutput write FOnOutput;
  end;

const
  ProgressKeep = 16000;

{** Appends AChunk, a piece of what a process wrote, to AText as a
  terminal would show it: a carriage return starts the line over, so
  the text written after it replaces the line so far (git's "Writing
  objects: 33%" ... "66%" on one line), while one followed by a newline
  is that newline. AReturn carries a return at the end of one chunk to
  the next. }
procedure AppendTerminalText(var AText: string; var AReturn: boolean; const AChunk: string);

{** Whether AProgress, what a push has written so far, shows git itself
  pushing (its object counts, the remote's answer, "Everything
  up-to-date"), which comes after the pre-push hook has had its say. }
function PushTransferStarted(const AProgress: string): boolean;

implementation

procedure AppendTerminalText(var AText: string; var AReturn: boolean; const AChunk: string);
var
  i, LineStart: integer;
  C: char;
begin
  for i := 1 to Length(AChunk) do
  begin
    C := AChunk[i];
    if C = #13 then
    begin
      AReturn := True;
      Continue;
    end;
    if AReturn then
    begin
      AReturn := False;
      if C <> #10 then
      begin
        LineStart := LastDelimiter(#10, AText);
        SetLength(AText, LineStart);
      end;
    end;
    AText := AText + C;
  end;
end;

function PushTransferStarted(const AProgress: string): boolean;
const
  Marks: array[0..5] of string = ('Enumerating objects:', 'Counting objects:',
    'Compressing objects:', 'Writing objects:', 'Everything up-to-date', 'remote: ');
var
  Mark: string;
begin
  Result := False;
  for Mark in Marks do
    if (Pos(Mark, AProgress) = 1) or (Pos(#10 + Mark, AProgress) > 0) then
      Exit(True);
end;

constructor TGittanRemoteJob.Create(const ARoot: string; AKind: TGittanRemoteKind;
  AMode: TGittanPullMode; const AArg, ARemote: string);
begin
  inherited Create(True);
  InitCriticalSection(FLock);
  FRoot := ARoot;
  FArg := AArg;
  FRemote := ARemote;
  FKind := AKind;
  FMode := AMode;
end;

destructor TGittanRemoteJob.Destroy;
begin
  inherited Destroy;
  DoneCriticalSection(FLock);
end;

function TGittanRemoteJob.GetProgress: string;
begin
  EnterCriticalSection(FLock);
  try
    Result := FProgress;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

{ In the job's thread. One notification waits at a time: the handler
  reads Progress, which holds everything so far. }
procedure TGittanRemoteJob.Output(const AText: string);
var
  Cut: integer;
  Tell: boolean;
begin
  EnterCriticalSection(FLock);
  try
    AppendTerminalText(FProgress, FReturn, AText);
    if Length(FProgress) > ProgressKeep then
    begin
      Cut := Length(FProgress) - ProgressKeep div 2;
      while (Cut < Length(FProgress)) and (FProgress[Cut] <> #10) do
        Inc(Cut);
      Delete(FProgress, 1, Cut);
    end;
    Tell := not FOutputPending;
    FOutputPending := True;
  finally
    LeaveCriticalSection(FLock);
  end;
  if Tell then
    Queue(@NotifyOutput);
end;

procedure TGittanRemoteJob.NotifyOutput;
begin
  EnterCriticalSection(FLock);
  FOutputPending := False;
  LeaveCriticalSection(FLock);
  if Assigned(FOnOutput) then
    FOnOutput(Self);
end;

procedure TGittanRemoteJob.Execute;
var
  Repo: TGittanRepo;
begin
  if FKind = rkClone then
  begin
    FOk := CloneRepository(FArg, FRoot, FSubmodules, FError, @Output);
    Queue(@Notify);
    Exit;
  end;
  Repo := TGittanRepo.Create;
  try
    Repo.OnOutput := @Output;
    if Repo.Open(FRoot) then
      case FKind of
        rkFetch: FOk := Repo.Fetch;
        rkPull: FOk := Repo.Pull(FMode, FDiverged);
        rkPush: FOk := Repo.Push(FRejected);
        rkDeleteRemote: FOk := Repo.DeleteRemoteBranch(FArg);
        rkForcePush: FOk := Repo.ForcePush(FStale, FUnseen);
        rkPushBranch: FOk := Repo.PushBranch(FArg, FRemote);
        rkPushTag: FOk := Repo.PushTag(FRemote, FArg);
        rkDeleteRemoteTag: FOk := Repo.DeleteRemoteTag(FRemote, FArg);
        rkSubmoduleUpdate: FOk := Repo.UpdateSubmodules(FArg);
        rkSubmoduleAdd: FOk := Repo.AddSubmodule(FArg, FPath, FBranch);
        rkClone: ;
      end;
    if not FOk then
      FError := Repo.Error;
  finally
    Repo.Free;
  end;
  Queue(@Notify);
end;

{ In the main thread, as Stop is, so the handler cannot go between the
  test and the call. }
procedure TGittanRemoteJob.Notify;
begin
  if Assigned(FOnDone) then
    FOnDone(Self);
end;

procedure TGittanRemoteJob.Stop(AWait: boolean);
begin
  FOnDone := nil;
  FOnOutput := nil;
  if AWait then
    WaitFor;
end;

end.
