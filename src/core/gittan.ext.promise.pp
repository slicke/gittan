{ Ported from Trndi (https://github.com/slicke/trndi), GPL-3.0. }

// JS promise handler
unit gittan.ext.promise;

{$mode ObjFPC}{$H+}

interface

uses
Classes, SysUtils, gittan.ext.quickjs,
gittan.ext.functions, gittan.ext.host;

type
  {** Pair holding QuickJS resolve/reject functions for a Promise.
      Index mapping used in this unit:
      - index 0 = resolve (see JprResolve)
      - index 1 = reject  (see JprReject) }
JSDoubleVal = array[0..1] of JSValueRaw;

  {** Pointer alias used when passing resolve/reject function slots to tasks. }
PJSDoubleVal = ^JSDoubleVal;

  {** Asynchronous task that bridges native (Pascal) callbacks to JS Promises.
      Workflow:
      - Created with a JS context, a registered callback descriptor (PJSCallback),
        and the Promise resolve/reject pair captured in @code(funcs).
      - Runs the callback and captures a JS-compatible result value.
      - Schedules a call to the proper resolve/reject using the QuickJS API.
      - Frees any argument structures allocated during parameter parsing. }
TJSAsyncTask = class(TThread)
private
  FContext: JSContext;      /// QuickJS context for this task
  FRuntime: JSRuntime;      /// Its runtime, which outlives a context unloaded
  funcs: JSDoubleVal;       /// Promise resolve/reject function handles
  FPairHeld: boolean;       /// funcs not yet released
  FPromise: TJSCallback;
    /// Registered callback descriptor (name, handler, params)
  FResult: JSVAlueVal;
    /// Result produced by the callback (QuickJS value wrapper)
  FSuccess: boolean;        /// True if callback indicates success; otherwise reject
  FGeneration: QWord;
    /// The context's generation when the task began; 0 when it had none

protected
      {** Thread entry point. Invokes the registered callback (via ProcessResult),
          then calls resolve or reject with the produced JS value. For callbacks
          registered with threaded=true, the callback itself runs on this worker
          thread and only FinishPromise is synchronized to the main thread. }
  procedure Execute; override;

      {** Run the registered callback, storing success flag and result.
          Executed via Synchronize to ensure safe interaction with GUI/JS context
          if required by the surrounding framework. }
  procedure ProcessResult;

      {** Invoke the native callback and capture status/result. When @code(quiet)
          is true (worker-thread path) errors are captured into FResult as the
          rejection value instead of showing UI dialogs. }
  procedure RunCallback(quiet: boolean);

      {** Resolve or reject the JS promise from FSuccess/FResult and release the
          QuickJS values and parsed parameters. Must run on the main thread. }
  procedure FinishPromise;

      {** Release the resolve/reject pair through the runtime, once. They hold
          their context's realm, so until they go a context freed by an unload
          keeps its whole heap. Main thread only. }
  procedure ReleasePair;

      {** FinishPromise's way when the callback is not run: the parameters and
          the pair are released, the promise left pending. }
  procedure Abandon;
public
      {** Create and start an async task bound to a JS Promise.
          @param(Context) QuickJS context
          @param(func)    Registered callback descriptor with handler and params
          @param(cbfunc)  Pointer to the resolve/reject function pair (JSDoubleVal) }
  constructor Create(Context: JSContext; func: TJSCallback; cbfunc: PJSDoubleVal);
end;

type
  {** The generation of an extension's context (a number never reused,
      unlike the context's address), 0 for a context that is gone. }
  TExtContextGeneration = function(ctx: JSContext): QWord;

var
  {** Set by the engine, which this unit cannot use. A task whose context
      was freed meanwhile, by Reload Extensions while a fetch or git ran,
      does not settle its promise on the freed context, nor on another
      one that took its address. }
  ExtContextGeneration: TExtContextGeneration = nil;
  {** Whether the runtime the tasks' values belong to is there; the engine
      clears it before it frees the runtime, after which a late task leaves
      its values alone. }
  ExtRuntimeAlive: boolean = False;

// Global shutdown guard for extensions/promises
procedure SetExtShuttingDown(const Value: boolean);
function IsExtShuttingDown: boolean;

{** Number of TJSAsyncTask threads created but not yet finished. Shutdown and
    reload paths wait until this drops to zero instead of a fixed delay. }
function ActiveAsyncTaskCount: integer;

const
  {** The most tasks one context may have under way at once: a call past it
      is rejected, so an extension cannot make threads until none can be
      made, for itself and every other one. }
  MaxAsyncTasksPerContext = 64;

{** The tasks of ctx under way. }
function AsyncTasksOf(ctx: JSContext): integer;

{** Drain the runtime's pending Promise job queue, bounded by a small budget.
    Returns False when the budget stopped the drain with jobs still queued, so
    the caller knows the queue is not empty; True when it emptied (or a job
    failed, which ends the drain the way it always did). }
function DrainPendingJobs(ctx: JSContext): boolean;

const
  {** Index of the Promise resolve function in @code(JSDoubleVal). }
JprResolve = 0;
  // const for "async function worked"

  {** Index of the Promise reject function in @code(JSDoubleVal). }
JprReject = 1;
  // for "didnt work"

implementation


var
gExtShuttingDown: boolean = false;
gActiveAsyncTasks: longint = 0;
  { The contexts with tasks under way and how many each, under gTaskLock:
    a task counts itself in on the main thread and out on its own. }
gTaskLock: TRTLCriticalSection;
gTaskContexts: array of JSContext;
gTaskCounts: array of integer;

procedure CountTask(ctx: JSContext; ADelta: integer);
var
  i, n: integer;
begin
  EnterCriticalSection(gTaskLock);
  try
    for i := 0 to High(gTaskContexts) do
      if gTaskContexts[i] = ctx then
      begin
        Inc(gTaskCounts[i], ADelta);
        if gTaskCounts[i] <= 0 then
        begin
          n := High(gTaskContexts);
          gTaskContexts[i] := gTaskContexts[n];
          gTaskCounts[i] := gTaskCounts[n];
          SetLength(gTaskContexts, n);
          SetLength(gTaskCounts, n);
        end;
        Exit;
      end;
    if ADelta > 0 then
    begin
      n := Length(gTaskContexts);
      SetLength(gTaskContexts, n + 1);
      SetLength(gTaskCounts, n + 1);
      gTaskContexts[n] := ctx;
      gTaskCounts[n] := ADelta;
    end;
  finally
    LeaveCriticalSection(gTaskLock);
  end;
end;

function AsyncTasksOf(ctx: JSContext): integer;
var
  i: integer;
begin
  Result := 0;
  EnterCriticalSection(gTaskLock);
  try
    for i := 0 to High(gTaskContexts) do
      if gTaskContexts[i] = ctx then
        Exit(gTaskCounts[i]);
  finally
    LeaveCriticalSection(gTaskLock);
  end;
end;

procedure SetExtShuttingDown(const Value: boolean);
begin
  gExtShuttingDown := Value;
end;

function IsExtShuttingDown: boolean;
begin
  Result := gExtShuttingDown;
end;

function ActiveAsyncTaskCount: integer;
begin
  Result := gActiveAsyncTasks;
end;

{** Construct and launch an asynchronous task bound to a JS Promise.
    Stores the context, callback descriptor, and resolve/reject functions.
    Sets FreeOnTerminate so the thread self-frees after completion. }
constructor TJSAsyncTask.Create(Context: JSContext; func: TJSCallback;
cbfunc: PJSDoubleVal);
begin
  FContext := Context;
  FPromise := func;
  FGeneration := 0;
  if Assigned(ExtContextGeneration) and (Context <> nil) then
    FGeneration := ExtContextGeneration(Context);
  // Copy resolve/reject function refs locally
  FRuntime := nil;
  if Context <> nil then
    FRuntime := JS_GetRuntime(Context);
  if cbfunc <> nil then
  begin
    funcs := cbfunc^;
    FPairHeld := True;
  end;
  FreeOnTerminate := true;
  // Count from creation (on the main thread) so shutdown waiters never observe
  // a started-but-not-yet-counted task; Execute decrements when done.
  InterLockedIncrement(gActiveAsyncTasks);
  CountTask(FContext, 1);
  try
    inherited Create(false);
  except
    { No thread: nothing will count it out, and the caller (AsyncTask)
      rejects the promise and releases its values. }
    CountTask(FContext, -1);
    InterLockedDecrement(gActiveAsyncTasks);
    FPairHeld := False;
    raise;
  end;
end;

{** Thread execution:
    - If a callback is assigned, run ProcessResult (synchronized as needed).
    - Convert the stored @code(FResult) to a JSValue.
    - Call resolve or reject depending on @code(FSuccess).
    - Free parameter data allocated during parsing.
    - Terminate the thread. }
procedure TJSAsyncTask.Execute;
begin
  try
    // The application on its way out: its main thread may never answer a
    // Synchronize again, and the process takes every value with it.
    if ExtHost.Terminated then
      Exit;

    // An unload under way (IsExtShuttingDown) or a missing function: nothing
    // runs, but the parameters and the resolve/reject pair are still let go
    // on the main thread, or the unloaded context could never be freed.
    if IsExtShuttingDown or not Assigned(FPromise.callback) then
    begin
      if not IsExtShuttingDown then
        ExtError('Error: Missing Function');
      FSuccess := false;
      try
        Synchronize(@Abandon);
      except
      end;
      Exit;
    end;

    if FPromise.threaded then
    begin
      // Threaded callback: do the (potentially slow) native work right here on
      // the worker thread so the UI stays responsive; only the JS resolve/reject
      // is synchronized to the main thread, since QuickJS is single-threaded.
      // FinishPromise settles the promise, or only releases its values when an
      // unload began meanwhile.
      RunCallback(true);
      if not ExtHost.Terminated then
      try
        Synchronize(@FinishPromise);
      except
        FSuccess := false;
        Exit;
      end;
    end
    else
    try
      Synchronize(@ProcessResult);
    except
      // If synchronize fails (e.g., main thread shutting down), just exit
      FSuccess := false;
      Exit;
    end;
    self.Terminate;
  finally
    CountTask(FContext, -1);
    InterLockedDecrement(gActiveAsyncTasks);
  end;
end;

procedure TJSAsyncTask.ReleasePair;
var
  Gone: boolean;
begin
  if not FPairHeld then
    Exit;
  FPairHeld := False;
  if (FRuntime = nil) or not ExtRuntimeAlive then
    Exit;
  Gone := (FGeneration <> 0) and Assigned(ExtContextGeneration) and
    (ExtContextGeneration(FContext) <> FGeneration);
  JS_FreeValueRT(FRuntime, funcs[JprResolve]);
  JS_FreeValueRT(FRuntime, funcs[JprReject]);
  // The last hold on a context unloaded meanwhile: what its objects keep of
  // each other goes with a collection.
  if Gone then
    JS_RunGC(FRuntime);
end;

procedure TJSAsyncTask.Abandon;
begin
  FreeJSParameters(FPromise.params.values.Data);
  ReleasePair;
end;

{** Execute the registered native callback and capture status/result.
    On success, @code(FSuccess) is True and @code(FResult) holds the JS value to return.
    On errors/exceptions, sets @code(FSuccess:=False) and reports via UX helpers.
    Runs entirely on the main thread (legacy, non-threaded path). }
procedure TJSAsyncTask.ProcessResult;
begin
  if IsExtShuttingDown then
  begin
    Abandon;
    Exit;
  end;
  RunCallback(false);
  FinishPromise;
end;

{** Invoke the native callback. quiet=true means we are on the worker thread:
    no UI dialogs may be shown, so error text becomes the promise rejection
    value instead. quiet=false preserves the legacy main-thread behavior. }
procedure TJSAsyncTask.RunCallback(quiet: boolean);
begin
  // Avoid doing work if app is shutting down
  if ExtHost.Terminated or IsExtShuttingDown then
  begin
    FSuccess := false;
    Exit;
  end;

  // Additional check: ensure context is still valid
  if (FContext = nil) then
  begin
    FSuccess := false;
    Exit;
  end;

  with FPromise do
    if Assigned(Callback) then
    begin
      try
        FSuccess := FPromise.Callback(@FContext, func, params.values.Data, FResult);
      except
        on E: EInvalidCast do
        begin
          FSuccess := false;
          if quiet then
            FResult := StringToValueVal(E.Message)
          else
          if not (ExtHost.Terminated or IsExtShuttingDown) then
            ExtError(RS_TYPE_ERROR_MSG, e.message);
        end;
        on E: Exception do
        begin
          FSuccess := false;
          if quiet then
            FResult := StringToValueVal(E.Message)
          else
          if not (ExtHost.Terminated or IsExtShuttingDown) then
            ExtError(Format(RS_PROM_ERR_CAPT, [func]), e.Message);
        end;
      end;
    end
    else
      FSuccess := false;
end;

{** Drain the runtime's pending job queue. This unit sits below the engine
    (which owns the 50ms fallback pump), so it drains via the binding alone.

    The loop and its budget live in the binding (JS_DrainPendingJobs) so this
    pump and the engine's share one implementation; all this adds is the
    shutdown guard. The early exits report True because they leave nothing
    un-run of their own. }
function DrainPendingJobs(ctx: JSContext): boolean;
begin
  Result := true;
  if (ctx = nil) or IsExtShuttingDown then
    Exit;
  Result := JS_DrainPendingJobs(JS_GetRuntime(ctx), ctx);
end;

{** Resolve/reject the promise from FSuccess/FResult and free the captured
    QuickJS values and parsed parameters. Main thread only. }
procedure TJSAsyncTask.FinishPromise;
var
  xres: JSValue;
  callRes: JSValueRaw;
begin
  // The parsed parameters go on every path, the early exits too, and so
  // does the resolve/reject pair (ReleasePair).
  FreeJSParameters(FPromise.params.values.Data);

  { No JS is called while an unload is under way, nor once the context
    was freed after the task began (the wait in UnloadExtensions is
    capped, and the shutdown flag is cleared once it is done): resolve
    and reject are not called then, only released through the runtime,
    which lets the freed context's heap go with them. }
  if ExtHost.Terminated or IsExtShuttingDown or (FContext = nil) or
    ((FGeneration <> 0) and Assigned(ExtContextGeneration) and
    (ExtContextGeneration(FContext) <> FGeneration)) then
  begin
    ReleasePair;
    Exit;
  end;

  try
    // Convert and resolve/reject the promise
    xres := JSValueValToValue(FContext, FResult);
    if FSuccess then
      callRes := JS_Call(FContext, funcs[JprResolve], JS_UNDEFINED, 1, @xres)
    else
      callRes := JS_Call(FContext, funcs[JprReject], JS_UNDEFINED, 1, @xres);
    // Release the call result, the marshalled argument, and the resolve/reject
    // pair captured by JS_NewPromiseCapability — all leaked before this fix.
    FContext^.FreeInlined(PJSValue(@callRes));
    FContext^.Free(xres);
    ReleasePair;

    // Settling the promise only queued its .then/.catch reactions; drain the
    // job queue here (main thread) so the extension's continuation runs now
    // instead of up to 50ms later at the engine's timer tick.
    DrainPendingJobs(FContext);
  except
    // Silently ignore JS calls that fail during shutdown
    // This prevents crashes when the runtime is being destroyed
  end;
  ReleasePair;
end;

initialization
  InitCriticalSection(gTaskLock);

finalization
  DoneCriticalSection(gTaskLock);

end.
