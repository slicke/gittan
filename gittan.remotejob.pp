unit gittan.remotejob;

{** Fetch, pull and push run in a thread: they go to the network, which
  can take its time, and the window must not hang meanwhile. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.git;

type
  {** What a TGittanRemoteJob does. }
  TGittanRemoteKind = (rkFetch, rkPull, rkPush, rkDeleteRemote);

  {** Runs a fetch, a pull (the way Mode says), a push, or the deletion
    of the remote branch Arg stands for (a remote-tracking branch such
    as origin/feature) of the repository at ARoot through TGittanRepo, on a repository of its own.
    OnDone is called in the main thread when it is done, unless the job
    has been stopped. A job is never broken off, as a pull stopped
    halfway would leave a merge behind: Stop only drops the handler, and
    the thread is not terminated for it (a thread terminated before it
    starts never runs Execute). }
  TGittanRemoteJob = class(TThread)
  private
    FRoot, FArg: string;
    FKind: TGittanRemoteKind;
    FMode: TGittanPullMode;
    FOk, FDiverged, FRejected: boolean;
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
      AMode: TGittanPullMode = pmAuto; const AArg: string = '');
    destructor Destroy; override;
    {** Drops the handler, and waits for git to end when AWait is set, as
      on quitting. }
    procedure Stop(AWait: boolean);
    property Root: string read FRoot;
    property Kind: TGittanRemoteKind read FKind;
    property Mode: TGittanPullMode read FMode;
    property Arg: string read FArg;
    {** Whether git did it. }
    property Ok: boolean read FOk;
    {** A pull that failed since the branch has diverged from its
      upstream: a merge or a rebase would do it. }
    property Diverged: boolean read FDiverged;
    {** A push that failed since the remote has commits the branch
      lacks: a pull would bring them first. }
    property Rejected: boolean read FRejected;
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
  AMode: TGittanPullMode; const AArg: string);
begin
  inherited Create(True);
  InitCriticalSection(FLock);
  FRoot := ARoot;
  FArg := AArg;
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
  Repo := TGittanRepo.Create;
  try
    Repo.OnOutput := @Output;
    if Repo.Open(FRoot) then
      case FKind of
        rkFetch: FOk := Repo.Fetch;
        rkPull: FOk := Repo.Pull(FMode, FDiverged);
        rkPush: FOk := Repo.Push(FRejected);
        rkDeleteRemote: FOk := Repo.DeleteRemoteBranch(FArg);
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
