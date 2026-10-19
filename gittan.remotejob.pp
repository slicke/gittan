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
    FOnDone: TNotifyEvent;
    procedure Notify;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: string; AKind: TGittanRemoteKind;
      AMode: TGittanPullMode = pmAuto; const AArg: string = '');
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
    property OnDone: TNotifyEvent read FOnDone write FOnDone;
  end;

implementation

constructor TGittanRemoteJob.Create(const ARoot: string; AKind: TGittanRemoteKind;
  AMode: TGittanPullMode; const AArg: string);
begin
  inherited Create(True);
  FRoot := ARoot;
  FArg := AArg;
  FKind := AKind;
  FMode := AMode;
end;

procedure TGittanRemoteJob.Execute;
var
  Repo: TGittanRepo;
begin
  Repo := TGittanRepo.Create;
  try
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
  if AWait then
    WaitFor;
end;

end.
