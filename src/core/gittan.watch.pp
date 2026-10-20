unit gittan.watch;

{** Repository watcher for Gittan.

  Polls a repository from a background thread and tells the main thread
  when the branch, the set of changed files or the content of a changed
  file has changed, so the views can be refreshed. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.git;

type
  {** Polls the repository rooted at ARoot, compared against ABase (empty
    for HEAD), every AInterval milliseconds
    through its own TGittanRepo and fires OnChange, in the main thread,
    whenever the repository's Fingerprint differs from the previous one.
    The first poll only takes the baseline. Set OnChange, then call Start;
    Free stops the thread and drops any pending notification. }
  TGittanWatcher = class(TThread)
  private
    FRoot, FBase: string;
    FWholeTree: boolean;
    FRepo: TGittanRepo;
    FWake: PRTLEvent;
    FInterval: integer;
    FLast: string;
    FSnapshot: TGittanRepoSnapshot;
    FOnChange: TNotifyEvent;
    procedure Notify;
  protected
    procedure Execute; override;
    procedure TerminatedSet; override;
  public
    constructor Create(const ARoot, ABase: string; AWholeTree: boolean;
      AInterval: integer);
    destructor Destroy; override;
    {** Drops the handler, ends the thread and waits for it. }
    procedure Stop;
    {** Called in the main thread after the repository changed. }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    {** The repository as it was when the last OnChange fired, gathered in
      the watcher thread so the main thread only draws it. Read it from the
      OnChange handler; the thread is held in Synchronize meanwhile, so it
      is not overwritten until the handler returns. }
    property Snapshot: TGittanRepoSnapshot read FSnapshot;
  end;

implementation

{ TGittanWatcher }

constructor TGittanWatcher.Create(const ARoot, ABase: string; AWholeTree: boolean;
  AInterval: integer);
begin
  inherited Create(True);
  FRoot := ARoot;
  FInterval := AInterval;
  FRepo := TGittanRepo.Create;
  FWake := RTLEventCreate;
  { The thread's repository is opened in Execute; the base must be set
    after Open, which clears it. }
  FBase := ABase;
  FWholeTree := AWholeTree;
end;

destructor TGittanWatcher.Destroy;
begin
  if not Finished then
    Stop;
  { Removes any Notify still waiting in the thread queue. }
  inherited Destroy;
  RTLEventDestroy(FWake);
  FRepo.Free;
end;

{ ---------------------------------------------------------------------------
  Polling
  ---------------------------------------------------------------------------
  The thread sleeps on an event with the interval as timeout, so Terminate
  wakes it at once instead of after a whole interval. git runs in this
  thread, the snapshot too; only Notify reaches the main thread. It goes
  through Synchronize, not Queue, so the thread is held while the main
  thread reads FSnapshot and does not overwrite it on the next tick. }
procedure TGittanWatcher.Execute;
var
  Fingerprint: string;
begin
  if not FRepo.Open(FRoot) then
    Exit;
  FRepo.Base := FBase;
  FRepo.WholeTree := FWholeTree;
  FLast := FRepo.Fingerprint;
  while not Terminated do
  begin
    RTLEventWaitFor(FWake, FInterval);
    if Terminated then
      Break;
    Fingerprint := FRepo.Fingerprint;
    if Fingerprint <> FLast then
    begin
      FLast := Fingerprint;
      FRepo.Snapshot(FSnapshot);
      if Terminated then
        Break;
      Synchronize(@Notify);
    end;
  end;
end;

procedure TGittanWatcher.TerminatedSet;
begin
  RTLEventSetEvent(FWake);
end;

procedure TGittanWatcher.Notify;
begin
  if Assigned(FOnChange) and not Terminated then
    FOnChange(Self);
end;

{ WaitFor on the main thread runs the pending Synchronize while it waits,
  so the handler is dropped first: a Notify already waiting then does
  nothing and the thread it holds is let go. }
procedure TGittanWatcher.Stop;
begin
  FOnChange := nil;
  Terminate;
  WaitFor;
end;

end.
