unit gittan.job;

{** The base of Gittan's background jobs: a thread that does one piece of
  work (git, gh or curl) and tells the main thread when it is done.

  The form starts a job, and when it is no longer wanted (another file
  shown, the repository left, the app quit) stops it, which drops the
  handler, so a result still on its way is thrown away. A job that may be
  given up (a blame, a history, a list from GitHub) is also told to end,
  and its Execute may give up early; a commit or a push is never broken
  off, its git runs to the end. The notification goes through Queue, so
  the thread does not wait for the main thread; it is let through only
  while the handler is set and the job has not been told to end. Freeing
  a job drops the handler first, since WaitFor in the main thread lets
  queued calls through while it waits, then waits for the thread, and
  only then do the descendants free what the thread works with. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TGittanJob = class(TThread)
  private
    FOnDone: TNotifyEvent;
    FEndOnStop: boolean;
    procedure Notify;
  protected
    {** Tells the main thread the work is done, unless the job was told
      to end; the last thing Execute does. }
    procedure Done;
    {** Drops the handlers. A descendant with more of them drops those
      too. }
    procedure Detach; virtual;
  public
    {** A job created suspended; Start runs it. AEndOnStop: Stop also
      ends the thread, for work that may be given up. }
    constructor Create(AEndOnStop: boolean);
    destructor Destroy; override;
    {** Drops the handler, so a result still on its way is thrown away,
      ends the thread when the job may be given up, and waits for it
      when AWait is set (as on quitting, so git is not left halfway). A
      job never started is not waited for. }
    procedure Stop(AWait: boolean = False);
    {** Called in the main thread when the work is done. }
    property OnDone: TNotifyEvent read FOnDone write FOnDone;
  end;

implementation

constructor TGittanJob.Create(AEndOnStop: boolean);
begin
  inherited Create(True);
  FEndOnStop := AEndOnStop;
end;

destructor TGittanJob.Destroy;
begin
  Detach;
  if FEndOnStop then
    Terminate;
  { Waits for a running thread and removes a Notify still queued. }
  inherited Destroy;
end;

procedure TGittanJob.Notify;
begin
  if Assigned(FOnDone) and not Terminated then
    FOnDone(Self);
end;

procedure TGittanJob.Done;
begin
  if not Terminated then
    Queue(@Notify);
end;

procedure TGittanJob.Detach;
begin
  FOnDone := nil;
end;

procedure TGittanJob.Stop(AWait: boolean);
begin
  Detach;
  if FEndOnStop then
    Terminate;
  if AWait and not Suspended then
    WaitFor;
end;

end.
