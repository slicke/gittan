unit gittan.watch;

{** Repository watcher for Gittan.

  Polls a repository from a background thread and tells the main thread
  when the branch, the set of changed files or the content of a changed
  file has changed, so the views can be refreshed. Opens one in a thread
  too, with its first snapshot. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.git, gittan.job;

type
  {** Polls the repository rooted at ARoot, compared against ABase (empty
    for HEAD), every AInterval milliseconds
    through its own TGittanRepo and fires OnChange, in the main thread,
    whenever the repository's Fingerprint differs from the previous one.
    The first poll only takes the baseline. Set OnChange (and
    IgnoreWhitespace, which the snapshot's counts follow), then call
    Start; Free stops the thread and drops any pending notification. }
  TGittanWatcher = class(TThread)
  private
    FRoot, FBase: string;
    FWholeTree, FIgnoreWhitespace: boolean;
    FRepo: TGittanRepo;
    FWake: PRTLEvent;
    FInterval: integer;
    FLast: string;
    FFailed: boolean;
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
    {** Passed on to the thread's TGittanRepo before the first poll, so
      the snapshot counts changed lines as the form does. Set it before
      Start. }
    property IgnoreWhitespace: boolean read FIgnoreWhitespace write FIgnoreWhitespace;
    {** The repository as it was when the last OnChange fired, gathered in
      the watcher thread so the main thread only draws it. Read it from the
      OnChange handler; the thread is held in Synchronize meanwhile, so it
      is not overwritten until the handler returns. }
    property Snapshot: TGittanRepoSnapshot read FSnapshot;
  end;

  {** Opens the repository that contains ADir and takes its snapshot on a
    thread, through its own TGittanRepo, with OnDone raised in the main
    thread once both are in: opening a repository runs some twenty git
    commands, which take seconds on Windows. The main thread then takes
    the repository with TGittanRepo.OpenAt and draws the snapshot. Set
    IgnoreWhitespace before Start, as the form's own repository has it. }
  TGittanOpenJob = class(TGittanJob)
  private
    FDir, FRoot, FGitDir, FError: string;
    FOpened, FIgnoreWhitespace: boolean;
    FSnapshot: TGittanRepoSnapshot;
  protected
    procedure Execute; override;
  public
    constructor Create(const ADir: string);
    property Dir: string read FDir;
    {** Whether ADir is in a repository; Error says why not. }
    property Opened: boolean read FOpened;
    property Root: string read FRoot;
    property GitDir: string read FGitDir;
    property Error: string read FError;
    {** The snapshot of the opened repository, compared against HEAD. }
    property Snapshot: TGittanRepoSnapshot read FSnapshot;
    {** Given to the job's TGittanRepo before Open, so the snapshot's
      counts leave whitespace changes out when the setting is on. }
    property IgnoreWhitespace: boolean read FIgnoreWhitespace write FIgnoreWhitespace;
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
  thread reads FSnapshot and does not overwrite it on the next tick. A poll
  that fails (a file gone between git's listing and the read, say) is
  tried again on the next tick instead of ending the thread. So is a
  snapshot that fails: its fingerprint is not kept, and the form hears
  of the failure once, not on every tick it goes on failing. }
procedure TGittanWatcher.Execute;
var
  Fingerprint: string;
  Ok: boolean;
begin
  if not FRepo.Open(FRoot) then
    Exit;
  FRepo.Base := FBase;
  FRepo.WholeTree := FWholeTree;
  FRepo.IgnoreWhitespace := FIgnoreWhitespace;
  FLast := FRepo.Fingerprint;
  while not Terminated do
  begin
    RTLEventWaitFor(FWake, FInterval);
    if Terminated then
      Break;
    try
      Fingerprint := FRepo.Fingerprint;
      if Fingerprint <> FLast then
      begin
        Ok := FRepo.Snapshot(FSnapshot);
        if Terminated then
          Break;
        if Ok then
          FLast := Fingerprint;
        if Ok or not FFailed then
          Synchronize(@Notify);
        FFailed := not Ok;
      end;
    except
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

{ TGittanOpenJob }

constructor TGittanOpenJob.Create(const ADir: string);
begin
  inherited Create(True);
  FDir := ADir;
end;

{ An exception out of the open or the snapshot (a file gone under the
  read, say) is a failed open with its message, not the end of the
  thread: without Done the form would wait for the job for ever, with
  nothing open meanwhile. }
procedure TGittanOpenJob.Execute;
var
  Repo: TGittanRepo;
begin
  Repo := TGittanRepo.Create;
  try
    try
      Repo.IgnoreWhitespace := FIgnoreWhitespace;
      FOpened := Repo.Open(FDir);
      if FOpened then
      begin
        FRoot := Repo.Root;
        FGitDir := Repo.GitDir;
        if not Terminated then
          Repo.Snapshot(FSnapshot);
      end
      else
        FError := Repo.Error;
    except
      on E: Exception do
      begin
        FOpened := False;
        FError := E.Message;
      end;
    end;
  finally
    Repo.Free;
  end;
  Done;
end;

end.
