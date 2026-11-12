{ Ported from Trndi (https://github.com/slicke/trndi), GPL-3.0. }
unit gittan.ext.engine;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
SysUtils,
// StrUtils supplies PosEx, which used to arrive via mormot.core.text
StrUtils,
gittan.ext.quickjs,
gittan.ext.modules,
Classes,
gittan.ext.promise,
gittan.ext.functions,
gittan.ext.perm,
gittan.ext.host,
gittan.ext.sys,
gittan.ext.registry,
fpjson,
fgl,
fpTimer,
Math;

resourcestring
  RS_EXT_FILE = 'File "%s" not found';

type
  {** Callback signature invoked when JavaScript code emits output via this engine. }
TOutputCallback = procedure(const Msg: RawUtf8) of object;

  {** Alias to the native-callback type used by the QuickJS binding.
      These are plain Pascal procedures reached through the shim trampoline;
      see @code(TJSNativeFunc) in gittan.ext.quickjs. }
ExtFunction = TJSNativeFunc;

  {** Placeholder alias for argv-like arrays. @fixme Consider removing if unused. }
ExtArgv = array of ExtFunction;

  {** Convenience alias for passing string arguments to JS calls. }
JSArray = array of RawUtf8;

  {** 64-bit integer array helper. }
QWordArray = array of qword;

  {** Descriptor for a registered extension function. Compares by @code(name). }
TGittanExtFunc = record
private
  args: ExtArgv;
  function getArgCount: integer;
public
    {** Function name (identifier exposed to JS). }
  Name: RawUtf8;
    {** Number of arguments registered for this function. }
  property argc: integer read getArgCount;
    {** Synonym of @code(argc). }
  property Count: integer read getArgCount;

    {** Equality operator compares on @code(name) only. }
  class operator =(const a, b: TGittanExtFunc): boolean; overload;
end;

  {** List of known/registered extension functions. }
TExtFuncList = specialize TFPGList<TGittanExtFunc>;

  {** List of registered callbacks (e.g., for Promises and async tasks). }
TCallbacks = specialize TFPGList<PJSCallback>;
  {** Alias: promises are managed as callbacks. }
TPromises = TCallbacks;


  {** Information for a registered JS timer (setTimeout/setInterval). }
TJSTimerInfo = record
  TimerID: integer;           // Unique ID returned to JS
  Due: QWord;                 // GetTickCount64 at which it fires next
  Interval: integer;          // Its delay in ms, again after each run of an interval
  Callback: JSValueRaw;       // Duplicated JS function value; owned, freed on disposal
  Args: array of JSValueRaw;  // Duplicated extra args (setTimeout(fn, ms, ...args)); owned
  IsInterval: boolean;        // True for setInterval, False for setTimeout
  Context: JSContext;         // QuickJS context for calling the function
end;

PJSTimerInfo = ^TJSTimerInfo;

  {** Map of timer ID to timer information. }
TJSTimerMap = specialize TFPGMap<integer, PJSTimerInfo>;

  {** Timers awaiting disposal. A timer (and its handler) must never be freed
      from inside its own OnTimer event, so cancelled/expired timers are parked
      here and disposed later by the engine's job pump. }
TJSTimerInfoList = specialize TFPGList<PJSTimerInfo>;

  {** A promise rejection noted by the QuickJS tracker but not yet reported.
      QuickJS fires the tracker the moment a promise is rejected with no
      handler attached, then fires it again (is_handled=true) if a handler
      arrives later in the same script — so reporting must be deferred until
      the job queue drains. Key holds the promise's raw value bits. }
TPendingRejection = record
  Key: UInt64;
  Msg: string;
end;

  {** Per-extension JavaScript context (Path B isolation).
      Each .js file gets its own JSContext (sharing the runtime), so the
      function registry exposed to one extension is decoupled from another. }
PExtContextInfo = ^TExtContextInfo;
TExtContextInfo = record
  Ctx: JSContext;            // QuickJS context, owned by this record
  FileName: string;          // absolute path to the .js file
  ExtId: string;             // stable id derived from filename
  Hash: string;              // sha256 of file contents (re-prompt on change)
  DisplayName: string;       // parsed from header (first line)
  Author: string;            // parsed from header ("(c) ..." line)
  Granted: TExtPermSet;      // baseline + user-approved promptable perms
  Repos: TStringArray;       // @repos: the repositories it runs for, all when empty
  Forges: TStringArray;      // @forges: the forges it runs for, lower case, all when empty
  Generation: QWord;         // a number of its own, never reused, unlike Ctx's address
end;

TExtContextList = specialize TFPGList<PExtContextInfo>;

  {** Embedded JavaScript engine wrapper using QuickJS via @link(gittan.ext.quickjs).

      Responsibilities:
      - Create and own a JS runtime/context
      - Register Pascal functions and classes to JS global scope
      - Execute JS strings and files
      - Manage Promises/jobs via a periodic timer
      - Provide convenience helpers for globals, calls, and UI alerts

      Pattern:
      - Implemented as a singleton via @code(Instance)/@code(ReleaseInstance).
   }
TGittanExtEngine = class
private
class
  var
    {** Singleton instance. Use @code(Instance) to access. }
  FInstance: TGittanExtEngine;

private
    {** Definition for the 'Gittan' class exposed to JS. }
  TrndiClass: JSClassDef;
    {** Registry of known/added functions (optional bookkeeping). }
  knownfunc: TExtFuncList;
    {** Periodic timer to pump QuickJS job queue (Promises/microtasks). }
  eventTimer: TFPTimer;
    {** QuickJS runtime handle. }
  FRuntime: JSRuntime;
    {** QuickJS context handle. }
  FContext: JSContext;
    {** Accumulated output produced by JS. }
  FOutput: RawUtf8;
    {** Output sink callback invoked by @code(SetOutput). }
  OutCallback: TOutputCallback;
    {** Registered promises. }
  promises: TPromises;
    {** Map of active JS timers (setTimeout/setInterval). }
  FJSTimers: TJSTimerMap;
    {** Counter for generating unique timer IDs. }
  FNextTimerID: integer;
    {** Cancelled/expired timers pending disposal (see TJSTimerInfoList). }
  FDeadTimers: TJSTimerInfoList;
    {** >0 while a JS timer callback is on the stack; blocks FDeadTimers
        draining so a timer is never freed beneath its own event. }
  FInTimerCallback: integer;
  FLastLoadFailed: boolean;
    {** Rejections seen by PromiseRejectionTracker, reported (or cancelled)
        on the next job-pump tick. }
  FPendingRejections: array of TPendingRejection;
    {** Watchdog state for EngineInterruptHandler, in GetTickCount64 ms:
        when the interrupt hook last polled, and when the current
        uninterrupted execution burst began. }
  FLastJSCheck: QWord;
  FJSBurstStart: QWord;

    {** Loaded per-extension contexts (Path B). Each user .js script lives in its own ctx. }
  FExtContexts: TExtContextList;
    {** The commands, listeners and settings the extensions registered. }
  FRegistry: TGittanExtRegistry;
    {** Active "target" context for registration helpers (addFunction/addClassFunction/AddPromise).
        nil means write to FContext (legacy/admin path). Set by BeginRegistration. }
  FCurrentRegCtx: JSContext;
    {** The last context's Generation; each new context takes the next. }
  FContextGeneration: QWord;
    {** Active permissions for the current registration target. Used by *If gated helpers. }
  FCurrentRegPerms: TExtPermSet;
    {** Stable extension id for the current registration target. Empty outside
        per-extension provisioning. }
  FCurrentRegExtId: string;

    {** JSON.parse of @code(Json) in @code(ctx): the one way a payload or a
        command's context reaches an extension, so every value belongs to
        the context it is used in. JS_UNDEFINED (and the error reported)
        when the text is no JSON. }
  function ParseJsonIn(ctx: JSContext; const Json: string): JSValue;
  function GetOutput: RawUtf8;
  procedure SetOutput(const val: RawUtf8);

    {** Dispose timers parked in FDeadTimers. Safe to call anytime; no-ops
        while a timer callback is running. }
  procedure DrainDeadTimers;
  procedure RunDueTimers;

    {** Find a registered callback by name.

        @param(func Callback identifier)
        @returns(TJSCallback record; undefined if not found) }
  function findCallback(const func: string): TJSCallback;

    {** Find a registered promise callback by name.

        @param(func Promise/callback identifier)
        @returns(Pointer to callback record; may raise if not found) }
  function findPromise(const func: string): PJSCallback;
    {** Internal unified call helper dispatching all JS function invocations.

        RawPrefix values are caller-prepared @code(JSValueRaw) arguments (arrays, objects, scalars)
        passed directly without re-marshalling. @code(Rest) is an open array of const which is
        marshalled on-the-fly to temporary JS values (numbers/strings/booleans).

        Freeing semantics:
        - @code(freeRaw=true) frees every element of @code(RawPrefix) after the call returns
          (use only for one-shot arguments you won't reuse).
        - @code(freeRest=true) frees each marshalled temporary produced from @code(Rest).
        - Set corresponding flags to false if you will retain and reuse values (only meaningful for RawPrefix).

        Duplicating the exact same JSValueRaw twice in @code(RawPrefix) while @code(freeRaw=true)
        would cause double-free attempts; avoid by constructing separate values if needed.

        @param(FuncName   Global JS function name to invoke)
        @param(RawPrefix  Pre-built JSValueRaw arguments supplied as-is)
        @param(Rest       Pascal arguments to marshal into JS values)
        @param(freeRaw    Whether to free RawPrefix JS values after invocation)
        @param(freeRest   Whether to free marshalled Rest JS temporaries)
        @returns(Stringified JS return value; empty string on error or if function missing) }
  function InternalCall(const FuncName: RawUtf8; const RawPrefix: array of JSValueRaw;
    const Rest: array of const; freeRaw, freeRest: boolean): RawUtf8;
public
    {** All registered callbacks (promise handlers etc.). }
  callbacks: TCallbacks;

    {** Construct the JS engine: runtime, context, 'Gittan' class, timers, base functions. }
  constructor Create;
    {** Destroy and cleanup: timers, callbacks, context/runtime, singleton instance. }
  destructor Destroy; override;

    {** Execute a JavaScript source string in the global scope.

        @param(Script JavaScript source as UTF-8)
        @param(name   Optional script name for diagnostics; default '<script>')
        @returns(Output or result string; on error returns formatted error text) }
  function Execute(const Script: RawUtf8; Name: string = '<script>'): RawUtf8;

    {** Load a JS file from disk and execute its contents.

        @param(FileName Path to script file)
        @returns(Result string from @code(Execute))
        @raises(Exception if file not found) }
  function ExecuteFile(const FileName: string): RawUtf8;

    {** Get the singleton instance of the engine (creates on first use). }
  class function Instance: TGittanExtEngine;
    {** True when the singleton already exists. Unlike @code(Instance) this
        never lazily creates the engine, so it is safe on shutdown paths. }
  class function HasInstance: boolean;
    {** The engine when one exists and shutdown has not begun; nil otherwise.
        Never constructs one — the guard for every caller that only wants to
        talk to an engine that is already running (callbacks, menu items).
        Boot no longer builds the runtime when no extension is installed, so
        an @code(Assigned(Instance)) test there would build it as a side
        effect of the first glucose update. }
  class function Existing: TGittanExtEngine;
    {** Release the singleton instance (frees resources). }
  class procedure ReleaseInstance;

    {** Append values to @code(Output) by converting JS values to UTF-8.

        @param(ctx  JS context)
        @param(vals Pointer to first JS value)
        @param(len  Number of items-1 to read; iterates inclusive from 0..len) }
  procedure SetOutput(ctx: JSContext; const vals: PJSValues; const len: integer);

    {** Clear the accumulated @code(Output). }
  procedure ClearOutput;

    {** Accessor to accumulated output; writes also trigger @code(OutCallback). }
  property Output: RawUtf8 read GetOutput write SetOutput;

    {** Register a global JS function in the current context.

        @param(id    Function name in global scope)
        @param(func  Native function pointer)
        @param(argc  Declared arity; 0 means variable/unspecified) }
  procedure addFunction(const id: string; const func: ExtFunction;
    const argc: integer = 0);

    {** Register a function as a method of the 'Gittan' JS class.

        @param(id    Method name)
        @param(func  Native function pointer)
        @param(argc  Declared arity; use -1 for variadic) }
  procedure addClassFunction(const id: string; const func: ExtFunction;
    const argc: integer = 0);
    // (Removed prior experimental overload infrastructure)

    {** Call a global JS function by name with string arguments.

        @param(FuncName Global function name)
        @param(Args     Array of string arguments)
        @returns(Stringified result; empty string if call failed/not found) }
  function CallFunction(const FuncName: RawUtf8; const Args: JSArray): RawUtf8;
    overload;

   {** Call a global JS function by name with integer arguments.

        @param(FuncName Global function name)
        @param(Args     Array of integer arguments)
        @returns(Stringified result; empty string if call failed/not found) }
  function CallFunction(const FuncName: RawUtf8;
    const Args: array of integer): RawUtf8;
    overload;

  {** Call a global JS function by name with different arguments.

      @param(FuncName Global function name)
      @param(Args     Array of const arguments)
      @returns(Stringified result; empty string if call failed/not found) }
  function CallFunction(const FuncName: RawUtf8; const Args: array of const): RawUtf8;
    overload;
  {** Build a QuickJS array from a Pascal open array of const values.
    Supported element kinds mirror the mixed CallFunction overload.
    Returns JS_UNDEFINED if context invalid or on allocation failure. }
  function CreateJSArray(const Values: array of const): JSValueRaw;
    {** Build a JS array from values that are already JS values, such as nested
        arrays. Needed because a JSValue is a record now and so cannot appear
        in an "array of const"; under the previous binding it was an integer.
        Deliberately not an overload of @code(CreateJSArray): an array
        constructor always binds to the "array of const" version. }
  function CreateJSArrayOf(const Values: array of JSValue): JSValueRaw;
  {** Convenience: call a JS function passing a single array argument built
    from Values. Equivalent JS: func([v0,v1,...]) }
  function CallFunctionWithArrayArg(const FuncName: RawUtf8;
    const Values: array of const): RawUtf8;
  {** Call where the first argument is a pre-built @code(JSValueRaw) (e.g. Array/Object) and the rest are Pascal values.

      Ownership:
      - @code(autoFree=true) frees ONLY the marshalled @code(Rest) arguments created internally.
      - @code(autoFreeFirst=true) additionally frees @code(FirstArg) (use for one-shot values).
        Leave it false if you will reuse @code(FirstArg).

      @param(FuncName      Global JS function name)
      @param(FirstArg      Pre-built JSValueRaw passed as first argument)
      @param(Rest          Pascal open array of const to marshal into trailing JS args)
      @param(autoFree      Free marshalled Rest JS values after call; default true)
      @param(autoFreeFirst Free supplied FirstArg after call; default false)
      @returns(Stringified result; empty string on failure) }
  function CallFunctionArrayFirst(const FuncName: RawUtf8;
    const FirstArg: JSValueRaw; const Rest: array of const;
    autoFree: boolean = true; autoFreeFirst: boolean = false): RawUtf8;
  {** Call with an array of pre-built @code(JSValueRaw) arguments followed by marshalled Pascal args.

      Freeing rules:
      - @code(rawAutoFree=true)  frees each element of @code(RawArgs) after invocation (one-shot usage).
      - @code(restAutoFree=true) frees each marshalled temporary created from @code(Rest).

      Example:
        raws[0] := eng.CreateJSArray([1,2,3]);
        res := eng.CallFunctionMixed('demo', raws, ['label', 42]);

      @param(FuncName     Global JS function name)
      @param(RawArgs      Array of pre-built JSValueRaw arguments)
      @param(Rest         Pascal values to marshal)
      @param(restAutoFree Free marshalled Rest values; default true)
      @param(rawAutoFree  Free provided RawArgs values; default false)
      @returns(Stringified result or empty string on error) }
  function CallFunctionMixed(const FuncName: RawUtf8;
    const RawArgs: array of JSValueRaw; const Rest: array of const;
    restAutoFree: boolean = true; rawAutoFree: boolean = false): RawUtf8;
  {** Factories to create standalone JS values you can mix with arrays:
       js := eng.MakeJSArray([1,2,3]);
       s  := eng.MakeJSString('hi');
       i  := eng.MakeJSInt64(42);
       eng.CallFunctionJS('foo',[s, js, i]);
     All returned JSValueRaw should normally be freed with JS_FreeValue after use
     unless you pass autoFree=true to CallFunctionJS (default). }
  function MakeJSString(const S: RawUtf8): JSValueRaw; inline;
  function MakeJSInt64(const V: int64): JSValueRaw; inline;
  function MakeJSFloat(const V: double): JSValueRaw; inline;
  function MakeJSBool(const V: boolean): JSValueRaw; inline;
    {** Convenience alias: build a JS array from Pascal values (same as CreateJSArray). }
  function MakeJSArray(const Values: array of const): JSValueRaw; inline;
  {** Call a function with pre-built @code(JSValueRaw) arguments (scalars, arrays, objects).
    @param(FuncName Global JS function name)
    @param(Args     Array of pre-built JSValueRaw values)
    @param(autoFree Free each value in Args after the call; default true for convenience)
    @returns(Stringified result or empty string on error) }
  function CallFunctionJS(const FuncName: RawUtf8; const Args: array of JSValueRaw;
    autoFree: boolean = true): RawUtf8;
  {** Example mixed usage:
      eng.Execute('function demo(label, data, count){ return label+":"+data.length+":"+count; }');
      arr := eng.CreateJSArray([1,2,3]);
      res := eng.CallFunctionJS('demo', [eng.MakeJSString('sizes'), arr, eng.MakeJSInt64(3)]);
      // res -> 'sizes:3:3'
    }
    {** Example:
        // JS side:
        // function sumArr(arr) { return arr.reduce((a,b)=>a+b,0); }

        // Pascal side:
        // eng.Execute('function sumArr(arr){return arr.reduce((a,b)=>a+b,0);}');
        // res := eng.CallFunctionWithArrayArg('sumArr',[1,2,3,4]); // => '10'
      }

    {** Set a global JS variable (string).

        @param(VarName Variable name)
        @param(Value   String value)
        @param(obj     Unused placeholder; reserved) }
  procedure SetGlobalVariable(const VarName: RawUtf8; const Value: RawUtf8;
    const obj: string = '');

    {** Set a global JS variable (int64).

        @param(VarName Variable name)
        @param(Value   64-bit integer value)
        @param(obj     Unused placeholder; reserved) }
  procedure SetGlobalVariable(const VarName: RawUtf8; const Value: int64;
    const obj: string = '');

    {** Create an empty global JS object with the given name.

        @param(name Global identifier for the new object) }
  procedure CreateNewObject(const Name: string);

    {** Register a Promise-style async entry point with fixed arity.

        @param(funcName  Name of the JS function to expose)
        @param(cbfunc    Pascal callback to run when job executes)
        @param(params    Exact number of parameters expected)
        @param(threaded  True to run the callback on the worker thread; the
                         callback must not touch UI or the JS context then) }
  procedure AddPromise(const funcName: string; cbfunc: JSCallbackFunction;
    params: integer = 1; threaded: boolean = false);

    {** Register a Promise-style async entry point with min/max arity.

        @param(funcName  Name of the JS function to expose)
        @param(cbfunc    Pascal callback to run when job executes)
        @param(minParams Minimum number of parameters allowed)
        @param(maxParams Maximum number of parameters allowed)
        @param(threaded  True to run the callback on the worker thread; the
                         callback must not touch UI or the JS context then) }
  procedure AddPromise(const funcName: string; cbfunc: JSCallbackFunction;
    minParams, maxParams: integer; threaded: boolean = false);

    {** Raise an EJSException carrying a message and file name.

        @param(message Error message)
        @param(fn      Source file or logical script name) }
  procedure excepion(const message, fn: string);

    {** Convert an argument at @code(pos) from JS to UTF-8.

        @param(ctx JS context)
        @param(vals Pointer to argument array)
        @param(pos  Index of argument to convert)
        @returns(UTF-8 copy of the argument value) }
  class function ParseArgv(ctx: PJSContext; const vals: PJSValues;
    const pos: integer): RawUtf8;

    {** Show an informational alert dialog to the user. }
  procedure alert(const msg: string; const AName: string = '');

    {** Access a registered callback by name. }
  property callback[f: string]: TJSCallback read findCallback;
    {** Access a registered promise callback pointer by name. }
  property promise[f: string]: PJSCallback read findPromise;

    {** Timer callback to process pending JS jobs (Promises/microtasks). }
  procedure OnJSTimer(Sender: TObject);

    {** Record a rejection with no handler yet (from PromiseRejectionTracker). }
  procedure NoteRejection(key: UInt64; const msg: string);
    {** Cancel a pending rejection report: a handler was attached after all. }
  procedure NoteRejectionHandled(key: UInt64);
    {** Alert any rejections still unhandled once the job queue has drained. }
  procedure FlushPendingRejections;

    {** Check whether a global function with @code(FuncName) exists in JS.

        Looks across all loaded extension contexts; falls back to the admin
        context (FContext) when no extensions are loaded. @returns(True if any
        ext context (or FContext when none) exposes a callable with this name). }
  function FunctionExists(const FuncName: string): boolean;

    {** Active target context for registration helpers. Falls back to FContext when
        no extension is currently being provisioned. }
  function CurrentRegistrationContext: JSContext;

    {** True if the permission is granted for the registration currently in
        progress. Always true outside a BeginRegistration block (legacy/admin path). }
  function CanRegister(const grp: TExtPermGroup): boolean;

    {** Stable id of the extension currently being provisioned. This is empty
        outside a @code(BeginRegistration)..@code(EndRegistration) block. }
  function CurrentRegistrationExtensionId: string;

    {** Create a fresh JSContext for an extension and prep it (intrinsics + Gittan class +
        opaque pointer). Caller is responsible for invoking BeginRegistration / running
        the gated registration block / ExtExecuteFile / EndRegistration. }
  function NewExtensionContext(const ExtId, FileName, Hash, DisplayName,
    Author: string; Granted: TExtPermSet): PExtContextInfo;

    {** Set the registration target to a freshly-created extension context. Subsequent
        addFunction/addClassFunction/AddPromise calls write into Ext.Ctx and are gated
        by Ext.Granted via the *If helpers. }
  procedure BeginRegistration(Ext: PExtContextInfo);

    {** Restore the registration target to the admin/legacy default (FContext). }
  procedure EndRegistration;

    {** Convenience: register a Gittan class method only if @code(grp) is granted
        in the current registration. }
  procedure addClassFunctionIf(const grp: TExtPermGroup; const id: string;
    const func: ExtFunction; const argc: integer = 0);

    {** Convenience: register a global JS function only if @code(grp) is granted. }
  procedure addFunctionIf(const grp: TExtPermGroup; const id: string;
    const func: ExtFunction; const argc: integer = 0);

    {** Convenience: register a promise-style function only if @code(grp) is granted. }
  procedure AddPromiseIf(const grp: TExtPermGroup; const funcName: string;
    cbfunc: JSCallbackFunction; minParams, maxParams: integer;
    threaded: boolean = false); overload;
  procedure AddPromiseIf(const grp: TExtPermGroup; const funcName: string;
    cbfunc: JSCallbackFunction; params: integer = 1;
    threaded: boolean = false); overload;

    {** Evaluate @code(Script) in the current registration context (the extension
        ctx during provisioning, otherwise FContext). Used to inject JS-side
        shims such as fetch(). Returns false if evaluation raised. }
  function ExecuteInCurrent(const Script: RawUtf8;
    const Name: string = '<shim>'): boolean;

    {** Load the file at Ext.FileName into Ext.Ctx and evaluate it. Returns the
        evaluation result (or 'Error: ...' on failure, matching ExecuteFile);
        LastLoadFailed says which, since a script's own last value may be a
        string that starts with Error: too. }
  function ExtExecuteFile(Ext: PExtContextInfo): RawUtf8;
    {** Whether the last ExtExecuteFile threw rather than ran to its end. }
  property LastLoadFailed: boolean read FLastLoadFailed;
    {** Takes one extension's context out and frees it, with what it
        registered and its timers: one whose script threw as it loaded,
        which is not loaded but would otherwise keep its listeners,
        commands and timers. }
  procedure DropExtensionContext(Ext: PExtContextInfo);
    {** Module-shaped extensions are evaluated through @code(import());
        called by @code(ExtExecuteFile) when the file has static
        @code(import)/@code(export) statements. }
  function ExtExecuteModule(Ext: PExtContextInfo): RawUtf8;

    {** Iterate every loaded extension context. Lifetime of returned pointers
        is owned by the engine; do not free. }
  function ExtensionCount: integer;
  function ExtensionAt(idx: integer): PExtContextInfo;

    {** Display name (@code(@name) header, falling back to the filename id)
        of the extension owning @code(ctx), or '' for the admin/template
        context. Wired into @code(ConsoleExtNameLookup) so the shared console
        buffer can attribute entries to their extension. }
  function ExtensionNameForContext(ctx: JSContext): string;

    {** Stable filename-derived id of the extension owning @code(ctx), or ''
        for the admin/template context. Unlike the display name this is
        unique per loaded extension, so it is safe to key registries on. }
  function ExtensionIdForContext(ctx: JSContext): string;
    {** The number the context owning @code(ctx) was made with, 0 for none.
        A context made after another has a new number even when it got
        the freed one's address, so a caller keeps it to tell a reload. }
  function GenerationForContext(ctx: JSContext): QWord;
    {** What the extension owning @code(ctx) was granted; [] for none. }
  function GrantedForContext(ctx: JSContext): TExtPermSet;
  function ContextInScope(ctx: JSContext; const ARoot, ARemoteUrls: string): boolean;
  function FireIn(const AEvent, APayloadJson: string; AScoped: boolean;
    const ARoot, ARemoteUrls: string; out ACancelMessage: string): boolean;

    {** Folder of the extension owning @code(ctx) (its script's directory),
        or '' for the admin/template context. Module imports are confined
        to it. }
  function ModuleRootForContext(ctx: JSContext): string;
    {** The script of the extension owning @code(ctx), '' for none. }
  function ModuleEntryForContext(ctx: JSContext): string;

    {** Tear down every per-extension context: cancel JS timers, drain pending
        jobs, free each @code(JSContext) and clear the registry. The shared
        runtime stays alive so a fresh @code(LoadExtensions) can repopulate
        without recreating the engine singleton. }
  procedure UnloadExtensions;

    {** Invoke the optional global @code(unloadCallback()) in every loaded
        extension context so scripts can flush state before teardown. Runs
        while contexts are still fully alive: at the top of
        @code(UnloadExtensions) (Reload path) and from the app close path in
        @code(TfBG.FormClose) before extension shutdown is signalled. A
        throwing callback is swallowed so it cannot block other extensions. }
  procedure NotifyUnloadAll;

    {** What the extensions registered: the commands for the menus, the
        listeners the events reach, the declared settings. }
  property Registry: TGittanExtRegistry read FRegistry;

    {** Drain the QuickJS job queue (Promise reactions/microtasks) right now
        instead of waiting for the next OnJSTimer tick. Returns False when the
        drain hit its budget with jobs still queued; callers that only want the
        queue advanced can ignore the result. }
  function PumpJobs: boolean;

    {** Raises AEvent (one of GittanExtEvents) in every listener, in the
        order they were added, with APayloadJson parsed in each listener's
        context as its one argument. A listener cancels by returning false,
        a string (the reason) or an object with cancel set (and a message);
        the first reason is ACancelMessage and the result is False. A
        listener that throws is reported and does not cancel. Every
        listener is called even after a cancel. A listener without the
        data permission gets ok, kind, mode and amend alone, none of the
        repository's content. Main thread only. }
  function Fire(const AEvent, APayloadJson: string; out ACancelMessage: string): boolean;
    overload;
    {** Fire for the repository at ARoot with the remotes ARemoteUrls: the
        listeners of an extension whose @repos leaves it out are not
        called (ExtRepoInScope). }
  function Fire(const AEvent, APayloadJson, ARoot, ARemoteUrls: string;
    out ACancelMessage: string): boolean; overload;
    {** Whether AEvent has a listener for the repository at ARoot with the
        remotes ARemoteUrls: a caller asks before it builds a payload that
        costs. }
  function Listens(const AEvent, ARoot, ARemoteUrls: string): boolean;
    {** Whether the extension AExtId runs for the repository at ARoot with
        the remotes ARemoteUrls (its @repos, and its @forges against the
        forge the remotes are on); False for one not loaded. }
  function ExtInScope(const AExtId, ARoot, ARemoteUrls: string): boolean;
    {** Whether the extension AExtId runs for the forge AForgeName (its
        @forges), where no repository decides: the forge view's menu,
        tabs and operations. False for one not loaded. }
  function ExtForgeInScope(const AExtId, AForgeName: string): boolean;
    {** Fire for an event that cannot be cancelled. }
  procedure Emit(const AEvent, APayloadJson: string);
    {** Runs the command AKey (TGittanExtRegistry.CommandKey) with
        AContextJson parsed in its context as its argument; a throw is
        reported. False when there is no such command. }
  function RunCommand(const AKey, AContextJson: string): boolean;

    {** Register the engine-internal baseline (alert/confirm/prompt/select/log,
        setTimeout/setInterval/clear*, console.*) into the current registration
        context, gated by the current registration permissions.

        Called from @code(Create) (writes into FContext with no perm filtering)
        and from @code(NewExtensionContext) inside a Begin/End block (writes
        into the extension's ctx, filtered by its grants). }
  procedure RegisterEngineBaselineForCurrent;
end;

  {** Exception type for JS-related errors with filename context. }
EJSException = class(Exception)
private
  FFilename: string;
public
    {** Create exception with a message and file name context. }
  constructor CreateWithName(const msg: string; const AFileName: string);
    {** Stringify exception as 'ClassName: FileName<newline>Message'. }
  function ToString: string; override;
    {** Name of the source file or logical script name. }
  property Filename: string read FFilename write FFilename;
end;

{** Emergency shutdown control functions }
{** Set the global shutdown flag - call this as early as possible during app termination }
procedure SetGlobalShutdown;
{** Check if application is shutting down }
function IsGlobalShutdown: boolean;

{** Check whether @code(ctx) exposes a callable named @code(FuncName) in its global scope.
    Used by the per-extension broadcast paths in @code(inc/umain_ext.inc). }
function ContextHasFunction(ctx: JSContext; const FuncName: string): boolean;

{** Take the pending exception off @code(ctx) and route its text (plus stack,
    when the thrown value carries one) to the engine output.

    Call this whenever @code(JS_Call) hands back the exception marker: the
    exception stays pending on the context until something retrieves it, and
    the next call into that same context would then fail with an error it never
    raised. Safe on shutdown paths, where no engine instance is left to report
    to - the exception is consumed either way.
    Used by the per-extension broadcast paths in @code(inc/umain_ext.inc). }
procedure DumpJSError(ctx: JSContext);

var
  {** Class ID used for the 'Gittan' class in QuickJS context. }
GittanClassID: JSClassID;

  {** Global flag to indicate application is shutting down - set as early as possible }
GlobalShutdownInProgress: boolean = false;

implementation

uses
  gittan.forge;

const
  { The timers one extension may have at once (setTimeout and
    setInterval together). }
  MaxTimersPerContext = 1000;

{$I gittan.ext.jsbase.inc }

{******************************************************************************
  TJSTimerHandler - Helper class for JS timer events
  Modified: January 16, 2026
******************************************************************************}

{** Free a retired timer record and the duplicated JS values it owns.
    Every call site runs while the timer's context is still alive: DrainDeadTimers
    only fires during normal operation, and Destroy/UnloadExtensions tear timers
    down before freeing any context. }
procedure DisposeTimerInfo(info: PJSTimerInfo);
var
  i: integer;
begin
  if info = nil then
    Exit;
  if info^.Context <> nil then
  begin
    info^.Context^.FreeInlined(PJSValue(@info^.Callback));
    for i := 0 to High(info^.Args) do
      info^.Context^.FreeInlined(PJSValue(@info^.Args[i]));
  end;
  Dispose(info);
end;

{ Runs one timer that is due, from the engine's tick on the main thread.
  The timers have no thread of their own: a TFPTimer had one each, so a
  script could start thousands, and a tick its thread had queued through
  Synchronize ran on the timer after clearTimeout or Reload freed it. }
procedure FireTimer(TimerInfo: PJSTimerInfo);
var
  Engine: TGittanExtEngine;
  RetVal: JSValueRaw;
  idx, nargs: integer;
  argp: PJSValueConstArr;
  err: RawUtf8;
begin
  if TimerInfo = nil then
    Exit;

  Engine := TGittanExtEngine.Instance;
  if (Engine = nil) or IsGlobalShutdown then
    Exit;

  Inc(Engine.FInTimerCallback);
  try
    // Invoke the stored callback value directly (works for anonymous/arrow
    // functions too), forwarding any extra setTimeout/setInterval arguments.
    nargs := Length(TimerInfo^.Args);
    if nargs > 0 then
      argp := PJSValueConstArr(@TimerInfo^.Args[0])
    else
      argp := nil;
    RetVal := JS_UNDEFINED;
    try
      RetVal := JS_Call(TimerInfo^.Context, TimerInfo^.Callback,
        JS_UNDEFINED, nargs, argp);
      if PJSValue(@RetVal)^.IsException then
      begin
        err := '';
        // DumpError, not ErrorMessage: it appends the JS stack trace, so the
        // extension console shows where in the callback the throw happened.
        TimerInfo^.Context^.DumpError(err);
        Engine.SetOutput('Timer callback error: ' + string(err));
      end;
    except on E: Exception do
        TGittanExtEngine.Instance.SetOutput('Timer exception: ' + E.Message);
    end;

    // Release the call result; the callback/args stay owned by TimerInfo.
    TimerInfo^.Context^.FreeInlined(PJSValue(@RetVal));

    // Run promise reactions the callback queued right away. FInTimerCallback
    // is still raised, so a nested pump cannot free this timer beneath us.
    Engine.PumpJobs;

    // If this is a setTimeout (one-shot), retire it. The JS callback may already
    // have cancelled us via clearTimeout, in which case we're no longer in the map.
    if not TimerInfo^.IsInterval then
    begin
      idx := Engine.FJSTimers.IndexOf(TimerInfo^.TimerID);
      if idx >= 0 then
      begin
        Engine.FJSTimers.Delete(idx);
        // Freeing its values here would pull them from beneath this call;
        // park it for the engine's job pump instead.
        Engine.FDeadTimers.Add(TimerInfo);
      end;
    end
    else if Engine.FJSTimers.IndexOf(TimerInfo^.TimerID) >= 0 then
      // An interval not cleared runs again its delay after this run ended.
      TimerInfo^.Due := GetTickCount64 + QWord(TimerInfo^.Interval);
  finally
    Dec(Engine.FInTimerCallback);
  end;
end;

{******************************************************************************
  Global shutdown control functions
******************************************************************************}

procedure SetGlobalShutdown;
begin
  GlobalShutdownInProgress := true;
end;

function IsGlobalShutdown: boolean;
begin
  Result := GlobalShutdownInProgress;
end;

{******************************************************************************
  TGittanExtFunc
******************************************************************************}

{** Compare two function descriptors by @code(name) only. }
class operator TGittanExtFunc.=(const a, b: TGittanExtFunc): boolean; overload;
begin
  Result := a.Name = b.Name;
end;

function TGittanExtFunc.getArgCount: integer;
begin
  Result := length(args);
end;

{******************************************************************************
  EJSException
******************************************************************************}

{** Construct with message and file name. }
constructor EJSException.CreateWithName(const msg: string; const AFileName: string);
begin
  inherited Create(msg);
  FFilename := AFilename;
end;

{** Return 'ClassName: FileName' + newline + message. }
function EJSException.ToString: string;
begin
  Result := ClassName + ': ' + FFilename + LineEnding + Message;
end;

{******************************************************************************
  TGittanExtEngine: dialogs, errors, alerts
******************************************************************************}

{** Show a simple informational alert through the host. }
procedure TGittanExtEngine.alert(const msg: string; const AName: string);
begin
  ExtHost.Alert(AName, msg);
end;

{** Raise JS exception with filename context. }
procedure TGittanExtEngine.excepion(const message, fn: string);
begin
  raise EJSException.CreateWithName(message, fn);
end;

{******************************************************************************
  TGittanExtEngine: callback/promise lookup and registration
******************************************************************************}

{** Find a registered callback by name. Returns default value if not found. }
function TGittanExtEngine.findCallback(const func: string): TJSCallback;
var
  i: integer;
  ok: boolean;
begin
  Result.func := '';
  Result.callback := nil;
  Result.params.min := 0;
  Result.params.max := 0;
  ok := false;
  for i := 0 to callbacks.Count - 1 do
    if (callbacks[i] <> nil) and (callbacks[i]^.func = func) then
    begin
      ok := true;
      break;
    end;

  if ok then
    Result := callbacks[i]^;
  // else leave Result default-initialized
end;

{** Find a registered promise by name or alert if missing.

    Note: The alert dereferences @code(promises[i]) after the loop if not found,
    which could be invalid; consider refactoring to avoid deref when not found. }
function TGittanExtEngine.findPromise(const func: string): PJSCallback;
var
  i: integer;
begin
  for i := 0 to promises.Count - 1 do
    if (promises[i] <> nil) and (promises[i]^.func = func) then
      Exit(promises[i]);

  // Not found: return nil without alerting (safe for teardown paths)
  Result := nil;
end;

{** Add Promise helper with fixed @code(params) expected (min=max). }
procedure TGittanExtEngine.AddPromise(const funcName: string;
cbfunc: JSCallbackFunction; params: integer = 1; threaded: boolean = false);
begin
  AddPromise(funcName, cbfunc, params, params, threaded);
end;

{** Register a Promise entry point by exposing an async task wrapper in JS
    and storing the associated Pascal callback with arity constraints.
    Writes the JS shim into the current registration context (FCurrentRegCtx
    when provisioning an extension, otherwise FContext). The Pascal callback
    record is stored on the shared promises list. }
procedure TGittanExtEngine.AddPromise(const funcName: string;
cbfunc: JSCallbackFunction; minParams, maxParams: integer;
threaded: boolean = false);
var
  cb: PJSCallback;
  ctx: JSContext;
  glob: JSValue;
begin
  ctx := CurrentRegistrationContext;
  if ctx = nil then Exit;

  // Expose an async task function in global scope that routes to our callback.
  // Every promise entry point shares the one AsyncTask procedure and is told
  // apart by its magic, which also carries the name - so the bound func_data
  // string the old binding needed is no longer necessary.
  glob := JS_GetGlobalObject(ctx);
  try
    JS_SetPropertyStr(ctx, glob, RawUtf8(funcname),
      JS_NewFunction(ctx, RawUtf8(funcname), 1,
      RegisterNative(RawUtf8(funcname), @AsyncTask)));
  finally
    JS_FreeValue(ctx, glob);
  end;

  // Track the Pascal callback and expected parameter range. Only add once —
  // promises is keyed by name and re-registration is idempotent.
  if findPromise(funcName) = nil then
  begin
    New(cb);
    cb^.func := funcname;
    cb^.callback := cbfunc;
    cb^.params.min := minParams;
    cb^.params.max := maxParams;
    cb^.threaded := threaded;
    promises.Add(cb);
  end;
end;

procedure TGittanExtEngine.AddPromiseIf(const grp: TExtPermGroup;
const funcName: string; cbfunc: JSCallbackFunction;
minParams, maxParams: integer; threaded: boolean = false);
begin
  if CanRegister(grp) then
    AddPromise(funcName, cbfunc, minParams, maxParams, threaded);
end;

procedure TGittanExtEngine.AddPromiseIf(const grp: TExtPermGroup;
const funcName: string; cbfunc: JSCallbackFunction; params: integer = 1;
threaded: boolean = false);
begin
  if CanRegister(grp) then
    AddPromise(funcName, cbfunc, params, threaded);
end;

{******************************************************************************
  TGittanExtEngine: output helpers
******************************************************************************}

{** Return a UTF-8 copy of argument @code(pos). }
class function TGittanExtEngine.ParseArgv(ctx: PJSContext; const vals: PJSValues;
const pos: integer): RawUtf8;
begin
  Result := ctx^^.ToUtf8(vals^[pos]);
end;

{** Append JS values (0..len) to @code(Output) as UTF-8 strings. }
procedure TGittanExtEngine.SetOutput(ctx: JSContext; const vals: PJSValues;
const len: integer);
var
  i: integer;
  totalLen: integer;
  temp: rawutf8;
  p: PAnsiChar;
begin
  if len < 0 then Exit;
  totalLen := 0;
  for i := 0 to len do
    Inc(totalLen, Length(ctx^.ToUtf8(vals^[i])));
  SetLength(temp, totalLen);
  p := PAnsiChar(temp);
  for i := 0 to len do
  begin
    Move(PAnsiChar(ctx^.ToUtf8(vals^[i]))^, p^, Length(ctx^.ToUtf8(vals^[i])));
    Inc(p, Length(ctx^.ToUtf8(vals^[i])));
  end;
  output := output + temp;
end;

{** Clear accumulated output buffer. }
procedure TGittanExtEngine.ClearOutput();
begin
  output := '';
end;

{** Assign output and notify optional callback. }
procedure TGittanExtEngine.SetOutput(const val: RawUtf8);
begin
  FOutput := val;
  if assigned(OutCallback) then
    OutCallback(val);
end;

{** Read accumulated output. }
function TGittanExtEngine.GetOutput: RawUtf8;
begin
  Result := FOutput;
end;

{******************************************************************************
  Module loader
******************************************************************************}

{** Module name normalizer for QuickJS: maps an import specifier to the
    absolute path the loader will read, confined to the importing extension's
    folder (see @code(ResolveModuleSpecifier)).

    QuickJS gives the normalizer no way to fail with a message - a nil return
    surfaces as a bare exception - so a resolution error is handed back as a
    name carrying @code(ModuleErrorPrefix), which the loader then throws.
    @code(opaque) is the engine. }
function GittanModuleNormalizer(ctx: JSContext; base_name, name: pansichar;
opaque: pointer): pansichar; cdecl;
var
  root, entry, resolved, err: string;
begin
  Result := nil;
  // Runs inside a C frame: no Pascal exception may unwind out of here.
  try
    root := '';
    entry := '';
    if opaque <> nil then
    begin
      root := TGittanExtEngine(opaque).ModuleRootForContext(ctx);
      entry := TGittanExtEngine(opaque).ModuleEntryForContext(ctx);
    end;
    err := ResolveModuleSpecifier(string(base_name), string(name), root, resolved, entry);
    if err <> '' then
      resolved := ModuleErrorPrefix + err;
    Result := js_strdup(ctx, pansichar(RawUtf8(resolved)));
  except
    on E: Exception do
      Result := js_strdup(ctx, pansichar(RawUtf8(ModuleErrorPrefix + E.Message)));
  end;
end;

{** Module loader for QuickJS: compiles a module from disk.

    QuickJS uses the return value as a @code(JSModuleDef*), so the source has to
    be compiled here rather than handed back as text. The name arrives from
    @code(GittanModuleNormalizer): an absolute path, the synthetic
    @code("trndi") module, or a resolution error to throw.

    @returns(JSModuleDef pointer, or nil with an exception pending on @code(ctx)) }
function GittanModuleLoader(ctx: JSContext; module_name: pansichar;
opaque: pointer): pointer; cdecl;
var
  FileName: string;
  Script: RawUtf8;
  FileStream: TFileStream;
  StringStream: TStringStream;
  Compiled: JSValue;

  { Leave a readable error pending on the context: returning nil without one
    surfaces in JS as a bare null rather than as a diagnosable failure. }
  procedure Fail(const reason: string);
  var
    quoted: string;
    thrown: JSValue;
  begin
    quoted := StringReplace(reason, '\', '\\', [rfReplaceAll]);
    quoted := StringReplace(quoted, '"', '\"', [rfReplaceAll]);
    quoted := StringReplace(quoted, #13, ' ', [rfReplaceAll]);
    quoted := StringReplace(quoted, #10, ' ', [rfReplaceAll]);
    thrown := JS_Eval(ctx, RawUtf8('throw new ReferenceError("' + quoted + '")'),
      '<module-loader>', JS_EVAL_TYPE_GLOBAL);
    JS_FreeValue(ctx, thrown);
  end;

begin
  Result := nil;
  FileName := string(module_name);

  if Pos(ModuleErrorPrefix, FileName) = 1 then
  begin
    Fail(Copy(FileName, Length(ModuleErrorPrefix) + 1, MaxInt));
    Exit;
  end;

  if FileName = GittanModuleSpecifier then
    Script := GittanModuleSource
  else if not FileExists(FileName) then
  begin
    Fail('module not found: ' + FileName);
    Exit;
  end
  else
  // Load file contents into Script as UTF-8. This runs inside a C frame, so a
  // Pascal exception must not be allowed to unwind out of it.
  try
    FileStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    StringStream := TStringStream.Create;
    try
      StringStream.CopyFrom(FileStream, FileStream.Size);
      Script := StringStream.DataString;
    finally
      StringStream.Free;
      FileStream.Free;
    end;
  except
    on E: Exception do
    begin
      Fail('cannot read module ' + FileName + ': ' + E.Message);
      Exit;
    end;
  end;

  // Compile only: the result is a JS_TAG_MODULE value wrapping the JSModuleDef.
  Compiled := JS_Eval(ctx, Script, RawUtf8(FileName),
    JS_EVAL_TYPE_MODULE or JS_EVAL_FLAG_COMPILE_ONLY);
  if JS_IsException(Compiled) then
    Exit;                       // the compiler already set the exception

  // The runtime's module list owns the definition, so the value we hold here is
  // ours to drop - the JSModuleDef it points at outlives it.
  Result := JS_VALUE_GET_PTR(Compiled);
  JS_FreeValue(ctx, Compiled);
end;

{******************************************************************************
  Construction / destruction
******************************************************************************}

const
  {** Runaway-extension guards: a script may execute continuously for this
      long before the watchdog aborts it, and the shared runtime heap is
      capped so a leaking extension cannot exhaust the process. }
  JS_WATCHDOG_MS = 10000;
  {** A gap this long between interrupt polls means no JS was executing (or
      it sat inside a native call, e.g. a modal dialog awaiting the user), so
      the watchdog budget restarts rather than count host/user time. }
  JS_WATCHDOG_GAP_MS = 500;
  JS_MEMORY_LIMIT_BYTES = 64 shl 20; // 64 MB across all extension contexts
  { Not on Haiku, where quickjs-ng cannot measure an allocation
    (js__malloc_usable_size gives 0) and counts its overhead alone. }

{** Interrupt hook polled by quickjs-ng between bytecodes; returning 1 aborts
    the running script with an uncatchable InterruptError. "Continuous
    execution" is measured through poll gaps: while JS runs, polls arrive
    every few thousand instructions, so a long gap means the engine was idle
    or parked in a native call - either way the budget restarts. Runs on
    whichever thread executes JS, which in Gittan is always the main thread. }
function EngineInterruptHandler(rt: JSRuntime; opaque: pointer): integer; cdecl;
var
  eng: TGittanExtEngine;
  tick: QWord;
begin
  Result := 0;
  eng := TGittanExtEngine(opaque);
  if eng = nil then
    Exit;
  tick := GetTickCount64;
  if tick - eng.FLastJSCheck > JS_WATCHDOG_GAP_MS then
    eng.FJSBurstStart := tick;
  eng.FLastJSCheck := tick;
  if tick - eng.FJSBurstStart > JS_WATCHDOG_MS then
  begin
    // Zeroing the poll timestamp restarts the burst at the next poll, so the
    // next script (say, another extension in the same broadcast) gets a
    // fresh budget instead of dying to this script's spent one.
    eng.FLastJSCheck := 0;
    Result := 1;
  end;
end;

{ Replacement for quickjs-libc's js_std_dump_error, which the engine does not link:
  the engine routes diagnostics through its own output rather than stderr. }
procedure DumpJSError(ctx: JSContext);
var
  msg: RawUtf8;
  eng: TGittanExtEngine;
begin
  if ctx = nil then
    Exit;
  // DumpError is what actually takes the exception off the context, so it has
  // to run even when there is nowhere left to report to.
  if (not ctx^.DumpError(msg)) or (msg = '') then
    Exit;
  // HasInstance never creates an engine, and Instance still returns nil once
  // shutdown has been signalled - which is exactly when the unload hooks run.
  eng := nil;
  if TGittanExtEngine.HasInstance then
    eng := TGittanExtEngine.Instance;
  if eng <> nil then
    eng.SetOutput(string(msg));
end;

{ For the promise tasks (gittan.ext.promise), which may not use this unit:
  the generation of a context, 0 once it is freed. }
function EngineContextGeneration(ctx: JSContext): QWord;
begin
  Result := 0;
  if TGittanExtEngine.FInstance <> nil then
    Result := TGittanExtEngine.FInstance.GenerationForContext(ctx);
end;

{** Create QuickJS runtime/context, expose 'Gittan', set up promises and timer, register base functions. }
constructor TGittanExtEngine.Create;
var
  glob: JSValue;
begin
  inherited Create;

  // Clear shutdown guard at startup
  SetExtShuttingDown(false);
  ExtContextGeneration := @EngineContextGeneration;

  // Create the QuickJS runtime
  FRuntime := JS_NewRuntime;
  if FRuntime = nil then
    raise Exception.Create('Failed to create JS runtime');

  // Create the context
  FContext := JS_NewContext(FRuntime);
  if FContext = nil then
    raise Exception.Create('Failed to create JS context');

  // Enable module loading via our loader
  // No cast: it was the cast that let a source-text loader pass as a JSModuleDef one.
  // The normalizer confines imports to the extension folder and needs the
  // engine to find that folder from the importing context.
  JS_SetModuleLoaderFunc(FRuntime, @GittanModuleNormalizer, @GittanModuleLoader, Self);

  // Allow callbacks to find this engine from JS context
  JS_SetContextOpaque(FContext, Self);

  // Define 'Gittan' JS class
  TrndiClass := Default(JSClassDef);
  TrndiClass.class_name := 'Gittan';

  // Create class ID and register class on runtime.
  // quickjs-ng takes the runtime as the first argument here.
  JS_NewClassID(FRuntime, @GittanClassID);
  if JS_NewClass(FRuntime, GittanClassID, @TrndiClass) < 0 then
    raise Exception.Create('Failed to create JS class');

  // Note: Do NOT call JS_SetOpaque on a class id. JS_SetOpaque expects a JSValue
  // instance, not a class id. Keeping only the context opaque above is correct.

  // Expose 'Gittan' constructor in global scope
  glob := JS_GetGlobalObject(FContext);
  try
    JS_SetPropertyStr(FContext, glob, 'Gittan',
      JS_NewConstructor(FContext, 'Gittan', 0,
      RegisterNative('Gittan', @GittanConstructor)));
  finally
    JS_FreeValue(FContext, glob);
  end;

  // Add essential intrinsics
  JS_AddIntrinsicPromise(FContext);
  JS_AddIntrinsicRegExp(FContext);
  JS_AddIntrinsicDate(FContext);
  JS_SetHostPromiseRejectionTracker(FRuntime, @PromiseRejectionTracker, nil);

  // Runaway-extension guards: cap the shared heap and abort scripts that
  // execute continuously past the watchdog budget (see EngineInterruptHandler).
  FLastJSCheck := 0;
  FJSBurstStart := 0;
  JS_SetMemoryLimit(FRuntime, JS_MEMORY_LIMIT_BYTES);
  JS_SetInterruptHandler(FRuntime, @EngineInterruptHandler, Self);

  // Initialize timer to pump pending JS jobs (Promises/microtasks)
  eventTimer := TFPTimer.Create(nil);
  eventTimer.Interval := 50;       // run every 50ms
  eventTimer.OnTimer := @self.OnJSTimer;
  eventTimer.Enabled := true;

  // Collections
  promises := TPromises.Create;
  knownfunc := TExtFuncList.Create;
  callbacks := TCallbacks.Create;
  
  // Initialize timer tracking (Modified: January 16, 2026)
  FJSTimers := TJSTimerMap.Create;
  FNextTimerID := 0;
  FDeadTimers := TJSTimerInfoList.Create;
  FInTimerCallback := 0;

  // Per-extension contexts (Path B). FCurrentRegCtx=nil routes legacy
  // bootstrap registrations to FContext (admin/template context).
  FExtContexts := TExtContextList.Create;
  FRegistry := TGittanExtRegistry.Create;
  FCurrentRegCtx := nil;
  FCurrentRegPerms := [];

  // Let the shared console buffer attribute entries to their extension
  ConsoleExtNameLookup := @ExtensionNameForContext;

  // Register baseline engine-internal functions into FContext (admin/template).
  // Per-extension contexts will re-run this gated to their grants in NewExtensionContext.
  RegisterEngineBaselineForCurrent;
end;

{** Register UI/timer/console baseline. Uses CurrentRegistrationContext + CanRegister
    so the same code path drives both the admin-context bootstrap and each
    per-extension provisioning. }
procedure TGittanExtEngine.RegisterEngineBaselineForCurrent;
const
  {** Pure-JS polyfills for common web globals QuickJS lacks: atob/btoa
      (WHATWG base64, Latin1 range) and queueMicrotask. Ungated — they touch
      no native functionality, so every context gets them regardless of
      granted permissions. }
  BASE_SHIM: string =
    '(function () {' + LineEnding +
    '  var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";' + LineEnding +
    '  if (typeof globalThis.btoa !== "function")' + LineEnding +
    '    globalThis.btoa = function (input) {' + LineEnding +
    '      var str = String(input), out = "", i, a, b, c;' + LineEnding +
    '      for (i = 0; i < str.length; i++)' + LineEnding +
    '        if (str.charCodeAt(i) > 255)' + LineEnding +
    '          throw new TypeError("btoa: character out of Latin1 range");' + LineEnding +
    '      for (i = 0; i < str.length; i += 3) {' + LineEnding +
    '        a = str.charCodeAt(i); b = str.charCodeAt(i + 1); c = str.charCodeAt(i + 2);' + LineEnding +
    '        out += chars[a >> 2];' + LineEnding +
    '        out += chars[((a & 3) << 4) | (isNaN(b) ? 0 : b >> 4)];' + LineEnding +
    '        out += isNaN(b) ? "=" : chars[((b & 15) << 2) | (isNaN(c) ? 0 : c >> 6)];' + LineEnding +
    '        out += isNaN(c) ? "=" : chars[c & 63];' + LineEnding +
    '      }' + LineEnding +
    '      return out;' + LineEnding +
    '    };' + LineEnding +
    '  if (typeof globalThis.atob !== "function")' + LineEnding +
    '    globalThis.atob = function (input) {' + LineEnding +
    '      var str = String(input).replace(/[\t\n\f\r ]+/g, "");' + LineEnding +
    '      if (!/^[A-Za-z0-9+/]*={0,2}$/.test(str))' + LineEnding +
    '        throw new TypeError("atob: invalid base64");' + LineEnding +
    '      str = str.replace(/=+$/, "");' + LineEnding +
    '      if (str.length % 4 === 1)' + LineEnding +
    '        throw new TypeError("atob: invalid base64");' + LineEnding +
    '      var out = "", buffer = 0, bits = 0, i;' + LineEnding +
    '      for (i = 0; i < str.length; i++) {' + LineEnding +
    '        buffer = (buffer << 6) | chars.indexOf(str[i]);' + LineEnding +
    '        bits += 6;' + LineEnding +
    '        if (bits >= 8) {' + LineEnding +
    '          bits -= 8;' + LineEnding +
    '          out += String.fromCharCode((buffer >> bits) & 255);' + LineEnding +
    '        }' + LineEnding +
    '      }' + LineEnding +
    '      return out;' + LineEnding +
    '    };' + LineEnding +
    '  if (typeof globalThis.queueMicrotask !== "function")' + LineEnding +
    '    globalThis.queueMicrotask = function (cb) {' + LineEnding +
    '      if (typeof cb !== "function")' + LineEnding +
    '        throw new TypeError("queueMicrotask: argument must be a function");' + LineEnding +
    '      Promise.resolve().then(cb);' + LineEnding +
    '    };' + LineEnding +
    '})();';

  {** ES2019–ES2022 library methods the bundled quickjspp fork predates:
      String.replaceAll, Object.hasOwn/fromEntries, Array/String at,
      Array findLast/findLastIndex, Promise.allSettled/any (+ AggregateError).
      All guarded, added non-enumerable so for..in loops stay clean. Ungated. }
  ES_SHIM: string =
    '(function () {' + LineEnding +
    '  function def(obj, name, fn) {' + LineEnding +
    '    if (!obj[name])' + LineEnding +
    '      Object.defineProperty(obj, name, { value: fn, writable: true, configurable: true });' + LineEnding +
    '  }' + LineEnding +
    '  function escRe(s) { return String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }' + LineEnding +
    '  def(String.prototype, "replaceAll", function (search, replacement) {' + LineEnding +
    '    if (search instanceof RegExp) {' + LineEnding +
    '      if (String(search.flags).indexOf("g") < 0)' + LineEnding +
    '        throw new TypeError("replaceAll must be called with a global RegExp");' + LineEnding +
    '      return this.replace(search, replacement);' + LineEnding +
    '    }' + LineEnding +
    '    return this.replace(new RegExp(escRe(search), "g"), replacement);' + LineEnding +
    '  });' + LineEnding +
    '  def(Object, "hasOwn", function (obj, key) {' + LineEnding +
    '    return Object.prototype.hasOwnProperty.call(obj, key);' + LineEnding +
    '  });' + LineEnding +
    '  def(Object, "fromEntries", function (entries) {' + LineEnding +
    '    var obj = {}, it = entries[Symbol.iterator](), r;' + LineEnding +
    '    for (r = it.next(); !r.done; r = it.next()) obj[r.value[0]] = r.value[1];' + LineEnding +
    '    return obj;' + LineEnding +
    '  });' + LineEnding +
    '  function atImpl(i) {' + LineEnding +
    '    i = Math.trunc(i) || 0;' + LineEnding +
    '    if (i < 0) i += this.length;' + LineEnding +
    '    return (i < 0 || i >= this.length) ? undefined : this[i];' + LineEnding +
    '  }' + LineEnding +
    '  def(Array.prototype, "at", atImpl);' + LineEnding +
    '  def(String.prototype, "at", atImpl);' + LineEnding +
    '  def(Array.prototype, "findLast", function (fn, thisArg) {' + LineEnding +
    '    for (var i = this.length - 1; i >= 0; i--)' + LineEnding +
    '      if (fn.call(thisArg, this[i], i, this)) return this[i];' + LineEnding +
    '    return undefined;' + LineEnding +
    '  });' + LineEnding +
    '  def(Array.prototype, "findLastIndex", function (fn, thisArg) {' + LineEnding +
    '    for (var i = this.length - 1; i >= 0; i--)' + LineEnding +
    '      if (fn.call(thisArg, this[i], i, this)) return i;' + LineEnding +
    '    return -1;' + LineEnding +
    '  });' + LineEnding +
    '  if (typeof globalThis.AggregateError !== "function")' + LineEnding +
    '    globalThis.AggregateError = function (errors, message) {' + LineEnding +
    '      var e = new Error(message === undefined ? "" : String(message));' + LineEnding +
    '      e.name = "AggregateError";' + LineEnding +
    '      e.errors = Array.prototype.slice.call(errors);' + LineEnding +
    '      return e;' + LineEnding +
    '    };' + LineEnding +
    '  def(Promise, "allSettled", function (list) {' + LineEnding +
    '    return Promise.all(Array.prototype.map.call(list, function (p) {' + LineEnding +
    '      return Promise.resolve(p).then(' + LineEnding +
    '        function (v) { return { status: "fulfilled", value: v }; },' + LineEnding +
    '        function (e) { return { status: "rejected", reason: e }; });' + LineEnding +
    '    }));' + LineEnding +
    '  });' + LineEnding +
    '  def(Promise, "any", function (list) {' + LineEnding +
    '    var arr = Array.prototype.slice.call(list);' + LineEnding +
    '    if (arr.length === 0)' + LineEnding +
    '      return Promise.reject(new AggregateError([], "All promises were rejected"));' + LineEnding +
    '    return new Promise(function (resolve, reject) {' + LineEnding +
    '      var errs = new Array(arr.length), pending = arr.length;' + LineEnding +
    '      arr.forEach(function (p, i) {' + LineEnding +
    '        Promise.resolve(p).then(resolve, function (e) {' + LineEnding +
    '          errs[i] = e;' + LineEnding +
    '          pending--;' + LineEnding +
    '          if (pending === 0) reject(new AggregateError(errs, "All promises were rejected"));' + LineEnding +
    '        });' + LineEnding +
    '      });' + LineEnding +
    '    });' + LineEnding +
    '  });' + LineEnding +
    '})();';

  {** URLSearchParams, a basic absolute-URL URL (with searchParams reflection
      and simple relative resolution against a base; no mailto:/data: schemes),
      and UTF-8 TextEncoder/TextDecoder. Pure JS, guarded, ungated. }
  WEB_SHIM: string =
    '(function () {' + LineEnding +
    '  function dec(s) { try { return decodeURIComponent(String(s).replace(/\+/g, " ")); } catch (e) { return String(s); } }' + LineEnding +
    '  function enc(s) { return encodeURIComponent(String(s)).replace(/%20/g, "+"); }' + LineEnding +
    '  function USP(init) {' + LineEnding +
    '    this._pairs = [];' + LineEnding +
    '    var i, k, s, parts, eq;' + LineEnding +
    '    if (init === undefined || init === null) return;' + LineEnding +
    '    if (init instanceof USP) {' + LineEnding +
    '      for (i = 0; i < init._pairs.length; i++)' + LineEnding +
    '        this._pairs.push([init._pairs[i][0], init._pairs[i][1]]);' + LineEnding +
    '    } else if (init instanceof Array) {' + LineEnding +
    '      for (i = 0; i < init.length; i++)' + LineEnding +
    '        this._pairs.push([String(init[i][0]), String(init[i][1])]);' + LineEnding +
    '    } else if (typeof init === "object") {' + LineEnding +
    '      for (k in init) this._pairs.push([k, String(init[k])]);' + LineEnding +
    '    } else {' + LineEnding +
    '      s = String(init);' + LineEnding +
    '      if (s.charAt(0) === "?") s = s.slice(1);' + LineEnding +
    '      parts = s === "" ? [] : s.split("&");' + LineEnding +
    '      for (i = 0; i < parts.length; i++) {' + LineEnding +
    '        if (parts[i] === "") continue;' + LineEnding +
    '        eq = parts[i].indexOf("=");' + LineEnding +
    '        if (eq < 0) this._pairs.push([dec(parts[i]), ""]);' + LineEnding +
    '        else this._pairs.push([dec(parts[i].slice(0, eq)), dec(parts[i].slice(eq + 1))]);' + LineEnding +
    '      }' + LineEnding +
    '    }' + LineEnding +
    '  }' + LineEnding +
    '  USP.prototype.append = function (n, v) { this._pairs.push([String(n), String(v)]); };' + LineEnding +
    '  USP.prototype.delete = function (n) {' + LineEnding +
    '    n = String(n);' + LineEnding +
    '    this._pairs = this._pairs.filter(function (p) { return p[0] !== n; });' + LineEnding +
    '  };' + LineEnding +
    '  USP.prototype.get = function (n) {' + LineEnding +
    '    n = String(n);' + LineEnding +
    '    for (var i = 0; i < this._pairs.length; i++)' + LineEnding +
    '      if (this._pairs[i][0] === n) return this._pairs[i][1];' + LineEnding +
    '    return null;' + LineEnding +
    '  };' + LineEnding +
    '  USP.prototype.getAll = function (n) {' + LineEnding +
    '    n = String(n);' + LineEnding +
    '    return this._pairs.filter(function (p) { return p[0] === n; }).map(function (p) { return p[1]; });' + LineEnding +
    '  };' + LineEnding +
    '  USP.prototype.has = function (n) { return this.get(n) !== null; };' + LineEnding +
    '  USP.prototype.set = function (n, v) {' + LineEnding +
    '    n = String(n); v = String(v);' + LineEnding +
    '    var i, seen = false, out = [];' + LineEnding +
    '    for (i = 0; i < this._pairs.length; i++) {' + LineEnding +
    '      if (this._pairs[i][0] === n) {' + LineEnding +
    '        if (!seen) { out.push([n, v]); seen = true; }' + LineEnding +
    '      } else out.push(this._pairs[i]);' + LineEnding +
    '    }' + LineEnding +
    '    if (!seen) out.push([n, v]);' + LineEnding +
    '    this._pairs = out;' + LineEnding +
    '  };' + LineEnding +
    '  USP.prototype.sort = function () {' + LineEnding +
    '    this._pairs.sort(function (a, b) { return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0; });' + LineEnding +
    '  };' + LineEnding +
    '  USP.prototype.forEach = function (fn, thisArg) {' + LineEnding +
    '    for (var i = 0; i < this._pairs.length; i++)' + LineEnding +
    '      fn.call(thisArg, this._pairs[i][1], this._pairs[i][0], this);' + LineEnding +
    '  };' + LineEnding +
    '  USP.prototype.keys = function () { return this._pairs.map(function (p) { return p[0]; })[Symbol.iterator](); };' + LineEnding +
    '  USP.prototype.values = function () { return this._pairs.map(function (p) { return p[1]; })[Symbol.iterator](); };' + LineEnding +
    '  USP.prototype.entries = function () { return this._pairs.map(function (p) { return [p[0], p[1]]; })[Symbol.iterator](); };' + LineEnding +
    '  USP.prototype[Symbol.iterator] = USP.prototype.entries;' + LineEnding +
    '  USP.prototype.toString = function () {' + LineEnding +
    '    return this._pairs.map(function (p) { return enc(p[0]) + "=" + enc(p[1]); }).join("&");' + LineEnding +
    '  };' + LineEnding +
    '  if (typeof globalThis.URLSearchParams !== "function") globalThis.URLSearchParams = USP;' + LineEnding +
    '  function hostString(p) { return p.hostname + (p.port ? ":" + p.port : ""); }' + LineEnding +
    '  function normPath(path) {' + LineEnding +
    '    var parts = path.split("/"), out = [], i;' + LineEnding +
    '    for (i = 0; i < parts.length; i++) {' + LineEnding +
    '      if (parts[i] === ".") continue;' + LineEnding +
    '      if (parts[i] === "..") { if (out.length > 1) out.pop(); continue; }' + LineEnding +
    '      out.push(parts[i]);' + LineEnding +
    '    }' + LineEnding +
    '    return out.join("/") || "/";' + LineEnding +
    '  }' + LineEnding +
    '  function parseAbs(s) {' + LineEnding +
    '    var m = /^([A-Za-z][A-Za-z0-9+.\-]*):\/\/([^\/?#]*)([^?#]*)(\?[^#]*)?(#.*)?$/.exec(s);' + LineEnding +
    '    if (!m) return null;' + LineEnding +
    '    var auth = m[2], username = "", password = "", host = auth, at, cred, col, close, pc;' + LineEnding +
    '    at = auth.lastIndexOf("@");' + LineEnding +
    '    if (at >= 0) {' + LineEnding +
    '      cred = auth.slice(0, at);' + LineEnding +
    '      host = auth.slice(at + 1);' + LineEnding +
    '      col = cred.indexOf(":");' + LineEnding +
    '      if (col < 0) username = cred;' + LineEnding +
    '      else { username = cred.slice(0, col); password = cred.slice(col + 1); }' + LineEnding +
    '    }' + LineEnding +
    '    var hostname = host, port = "";' + LineEnding +
    '    if (host.charAt(0) === "[") {' + LineEnding +
    '      close = host.indexOf("]");' + LineEnding +
    '      hostname = host.slice(0, close + 1);' + LineEnding +
    '      if (host.charAt(close + 1) === ":") port = host.slice(close + 2);' + LineEnding +
    '    } else {' + LineEnding +
    '      pc = host.indexOf(":");' + LineEnding +
    '      if (pc >= 0) { hostname = host.slice(0, pc); port = host.slice(pc + 1); }' + LineEnding +
    '    }' + LineEnding +
    '    var protocol = m[1].toLowerCase() + ":";' + LineEnding +
    '    if ((protocol === "http:" && port === "80") || (protocol === "https:" && port === "443")) port = "";' + LineEnding +
    '    if (hostname === "") return null;' + LineEnding +
    '    return {' + LineEnding +
    '      protocol: protocol, username: username, password: password,' + LineEnding +
    '      hostname: hostname.toLowerCase(), port: port,' + LineEnding +
    '      pathname: m[3] === "" ? "/" : m[3],' + LineEnding +
    '      search: m[4] || "", hash: m[5] || ""' + LineEnding +
    '    };' + LineEnding +
    '  }' + LineEnding +
    '  function URLCtor(url, base) {' + LineEnding +
    '    url = String(url);' + LineEnding +
    '    var p = parseAbs(url), b, origin, abs, rest, q, h, hi, qi, dir, self = this;' + LineEnding +
    '    if (!p) {' + LineEnding +
    '      if (base === undefined || base === null) throw new TypeError("Invalid URL: " + url);' + LineEnding +
    '      b = parseAbs(base && base.href !== undefined ? String(base.href) : String(base));' + LineEnding +
    '      if (!b) throw new TypeError("Invalid base URL: " + String(base));' + LineEnding +
    '      origin = b.protocol + "//" + hostString(b);' + LineEnding +
    '      if (url.slice(0, 2) === "//") abs = b.protocol + url;' + LineEnding +
    '      else if (url.charAt(0) === "/") abs = origin + url;' + LineEnding +
    '      else if (url.charAt(0) === "?") abs = origin + b.pathname + url;' + LineEnding +
    '      else if (url.charAt(0) === "#") abs = origin + b.pathname + b.search + url;' + LineEnding +
    '      else if (url === "") abs = origin + b.pathname + b.search;' + LineEnding +
    '      else {' + LineEnding +
    '        rest = url; q = ""; h = "";' + LineEnding +
    '        hi = rest.indexOf("#");' + LineEnding +
    '        if (hi >= 0) { h = rest.slice(hi); rest = rest.slice(0, hi); }' + LineEnding +
    '        qi = rest.indexOf("?");' + LineEnding +
    '        if (qi >= 0) { q = rest.slice(qi); rest = rest.slice(0, qi); }' + LineEnding +
    '        dir = b.pathname.slice(0, b.pathname.lastIndexOf("/") + 1);' + LineEnding +
    '        abs = origin + normPath(dir + rest) + q + h;' + LineEnding +
    '      }' + LineEnding +
    '      p = parseAbs(abs);' + LineEnding +
    '      if (!p) throw new TypeError("Invalid URL: " + url);' + LineEnding +
    '    }' + LineEnding +
    '    this.protocol = p.protocol;' + LineEnding +
    '    this.username = p.username;' + LineEnding +
    '    this.password = p.password;' + LineEnding +
    '    this.hostname = p.hostname;' + LineEnding +
    '    this.port = p.port;' + LineEnding +
    '    this.pathname = p.pathname;' + LineEnding +
    '    this.hash = p.hash;' + LineEnding +
    '    this.searchParams = new globalThis.URLSearchParams(p.search);' + LineEnding +
    '    Object.defineProperty(this, "search", {' + LineEnding +
    '      get: function () { var s = self.searchParams.toString(); return s === "" ? "" : "?" + s; },' + LineEnding +
    '      set: function (v) { self.searchParams = new globalThis.URLSearchParams(String(v)); },' + LineEnding +
    '      configurable: true' + LineEnding +
    '    });' + LineEnding +
    '    Object.defineProperty(this, "host", {' + LineEnding +
    '      get: function () { return hostString(self); },' + LineEnding +
    '      configurable: true' + LineEnding +
    '    });' + LineEnding +
    '    Object.defineProperty(this, "origin", {' + LineEnding +
    '      get: function () { return self.protocol + "//" + hostString(self); },' + LineEnding +
    '      configurable: true' + LineEnding +
    '    });' + LineEnding +
    '    Object.defineProperty(this, "href", {' + LineEnding +
    '      get: function () {' + LineEnding +
    '        var cred = "";' + LineEnding +
    '        if (self.username !== "" || self.password !== "")' + LineEnding +
    '          cred = self.username + (self.password !== "" ? ":" + self.password : "") + "@";' + LineEnding +
    '        return self.protocol + "//" + cred + hostString(self) + self.pathname + self.search + self.hash;' + LineEnding +
    '      },' + LineEnding +
    '      configurable: true' + LineEnding +
    '    });' + LineEnding +
    '  }' + LineEnding +
    '  URLCtor.prototype.toString = function () { return this.href; };' + LineEnding +
    '  URLCtor.prototype.toJSON = function () { return this.href; };' + LineEnding +
    '  if (typeof globalThis.URL !== "function") globalThis.URL = URLCtor;' + LineEnding +
    '  function TE() { this.encoding = "utf-8"; }' + LineEnding +
    '  TE.prototype.encode = function (input) {' + LineEnding +
    '    var str = input === undefined ? "" : String(input);' + LineEnding +
    '    var bytes = [], i, c;' + LineEnding +
    '    for (i = 0; i < str.length; i++) {' + LineEnding +
    '      c = str.codePointAt(i);' + LineEnding +
    '      if (c > 0xFFFF) i++;' + LineEnding +
    '      if (c >= 0xD800 && c <= 0xDFFF) c = 0xFFFD;' + LineEnding +
    '      if (c < 0x80) bytes.push(c);' + LineEnding +
    '      else if (c < 0x800) bytes.push(0xC0 | (c >> 6), 0x80 | (c & 63));' + LineEnding +
    '      else if (c < 0x10000) bytes.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));' + LineEnding +
    '      else bytes.push(0xF0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));' + LineEnding +
    '    }' + LineEnding +
    '    return new Uint8Array(bytes);' + LineEnding +
    '  };' + LineEnding +
    '  if (typeof globalThis.TextEncoder !== "function") globalThis.TextEncoder = TE;' + LineEnding +
    '  function TD(label, options) {' + LineEnding +
    '    label = label === undefined ? "utf-8" : String(label).toLowerCase().trim();' + LineEnding +
    '    if (label !== "utf-8" && label !== "utf8" && label !== "unicode-1-1-utf-8")' + LineEnding +
    '      throw new RangeError("TextDecoder: only utf-8 is supported");' + LineEnding +
    '    this.encoding = "utf-8";' + LineEnding +
    '    this.fatal = !!(options && options.fatal);' + LineEnding +
    '  }' + LineEnding +
    '  TD.prototype.decode = function (input) {' + LineEnding +
    '    if (input === undefined) return "";' + LineEnding +
    '    var bytes;' + LineEnding +
    '    if (input instanceof Uint8Array) bytes = input;' + LineEnding +
    '    else if (input instanceof ArrayBuffer) bytes = new Uint8Array(input);' + LineEnding +
    '    else if (ArrayBuffer.isView(input)) bytes = new Uint8Array(input.buffer, input.byteOffset, input.byteLength);' + LineEnding +
    '    else bytes = new Uint8Array(input);' + LineEnding +
    '    var out = "", i = 0, b, c, n, j, valid;' + LineEnding +
    '    while (i < bytes.length) {' + LineEnding +
    '      b = bytes[i];' + LineEnding +
    '      if (b < 0x80) { c = b; n = 0; }' + LineEnding +
    '      else if ((b & 0xE0) === 0xC0) { c = b & 31; n = 1; }' + LineEnding +
    '      else if ((b & 0xF0) === 0xE0) { c = b & 15; n = 2; }' + LineEnding +
    '      else if ((b & 0xF8) === 0xF0) { c = b & 7; n = 3; }' + LineEnding +
    '      else {' + LineEnding +
    '        if (this.fatal) throw new TypeError("TextDecoder: invalid UTF-8");' + LineEnding +
    '        out += String.fromCharCode(0xFFFD); i++; continue;' + LineEnding +
    '      }' + LineEnding +
    '      valid = true;' + LineEnding +
    '      for (j = 1; j <= n; j++) {' + LineEnding +
    '        if (i + j >= bytes.length || (bytes[i + j] & 0xC0) !== 0x80) { valid = false; break; }' + LineEnding +
    '        c = (c << 6) | (bytes[i + j] & 63);' + LineEnding +
    '      }' + LineEnding +
    '      if (valid && n === 1 && c < 0x80) valid = false;' + LineEnding +
    '      if (valid && n === 2 && (c < 0x800 || (c >= 0xD800 && c <= 0xDFFF))) valid = false;' + LineEnding +
    '      if (valid && n === 3 && (c < 0x10000 || c > 0x10FFFF)) valid = false;' + LineEnding +
    '      if (!valid) {' + LineEnding +
    '        if (this.fatal) throw new TypeError("TextDecoder: invalid UTF-8");' + LineEnding +
    '        out += String.fromCharCode(0xFFFD); i++; continue;' + LineEnding +
    '      }' + LineEnding +
    '      out += String.fromCodePoint(c);' + LineEnding +
    '      i += n + 1;' + LineEnding +
    '    }' + LineEnding +
    '    return out;' + LineEnding +
    '  };' + LineEnding +
    '  if (typeof globalThis.TextDecoder !== "function") globalThis.TextDecoder = TD;' + LineEnding +
    '})();';

  {** Wraps console.* so non-string arguments are JSON.stringify''d instead of
      collapsing to "[object Object]". Runs after RegisterConsoleLog; no-op in
      contexts without the console object (epUI not granted). }
  CONSOLE_FMT_SHIM: string =
    '(function () {' + LineEnding +
    '  if (typeof console !== "object" || console === null) return;' + LineEnding +
    '  function fmt(a) {' + LineEnding +
    '    if (typeof a === "string") return a;' + LineEnding +
    '    if (a instanceof Error) return (a.name || "Error") + ": " + a.message;' + LineEnding +
    '    if (typeof a === "object" && a !== null) {' + LineEnding +
    '      try {' + LineEnding +
    '        var s = JSON.stringify(a);' + LineEnding +
    '        if (s !== undefined) return s;' + LineEnding +
    '      } catch (e) { }' + LineEnding +
    '    }' + LineEnding +
    '    return String(a);' + LineEnding +
    '  }' + LineEnding +
    '  var names = ["log", "error", "warn", "info", "debug", "push"], i;' + LineEnding +
    '  for (i = 0; i < names.length; i++)' + LineEnding +
    '    (function (name, orig) {' + LineEnding +
    '      if (typeof orig !== "function") return;' + LineEnding +
    '      console[name] = function () {' + LineEnding +
    '        var out = [], j;' + LineEnding +
    '        for (j = 0; j < arguments.length; j++) out.push(fmt(arguments[j]));' + LineEnding +
    '        return orig.apply(console, out);' + LineEnding +
    '      };' + LineEnding +
    '    })(names[i], console[names[i]]);' + LineEnding +
    '})();';

  {** performance.now() (native monotonic clock, µs precision), WebCrypto
      essentials (crypto.getRandomValues/randomUUID over the native AES-PRNG
      hex source) and structuredClone (deep clone incl. Date/RegExp/Map/Set/
      typed arrays, preserves cycles and shared buffers; functions/symbols
      throw TypeError). Guarded so host-provided versions win; the crypto and
      performance parts no-op if their natives are absent. Ungated. }
  MISC_SHIM: string =
    '(function () {' + LineEnding +
    '  if (typeof globalThis.performance !== "object" || globalThis.performance === null)' + LineEnding +
    '    globalThis.performance = {};' + LineEnding +
    '  if (typeof globalThis.performance.now !== "function" && typeof gittanPerfNow === "function") {' + LineEnding +
    '    globalThis.performance.now = function () { return gittanPerfNow(); };' + LineEnding +
    '    globalThis.performance.timeOrigin = Date.now() - gittanPerfNow();' + LineEnding +
    '  }' + LineEnding +
    '  if (!globalThis.crypto && typeof gittanRandomHex === "function") {' + LineEnding +
    '    var randBytes = function (n) {' + LineEnding +
    '      if (n === 0) return new Uint8Array(0);' + LineEnding +
    '      var hx = gittanRandomHex(n), out = new Uint8Array(n), i;' + LineEnding +
    '      if (typeof hx !== "string" || hx.length !== n * 2)' + LineEnding +
    '        throw new Error("crypto: randomness unavailable");' + LineEnding +
    '      for (i = 0; i < n; i++) out[i] = parseInt(hx.substr(i * 2, 2), 16);' + LineEnding +
    '      return out;' + LineEnding +
    '    };' + LineEnding +
    '    globalThis.crypto = {' + LineEnding +
    '      getRandomValues: function (arr) {' + LineEnding +
    '        if (!ArrayBuffer.isView(arr) || arr instanceof Float32Array || arr instanceof Float64Array || arr instanceof DataView)' + LineEnding +
    '          throw new TypeError("getRandomValues: argument must be an integer typed array");' + LineEnding +
    '        if (arr.byteLength > 65536)' + LineEnding +
    '          throw new RangeError("getRandomValues: quota of 65536 bytes exceeded");' + LineEnding +
    '        new Uint8Array(arr.buffer, arr.byteOffset, arr.byteLength).set(randBytes(arr.byteLength));' + LineEnding +
    '        return arr;' + LineEnding +
    '      },' + LineEnding +
    '      randomUUID: function () {' + LineEnding +
    '        var b = randBytes(16), hx = "", i;' + LineEnding +
    '        b[6] = (b[6] & 15) | 64;' + LineEnding +
    '        b[8] = (b[8] & 63) | 128;' + LineEnding +
    '        for (i = 0; i < 16; i++) {' + LineEnding +
    '          hx += (b[i] < 16 ? "0" : "") + b[i].toString(16);' + LineEnding +
    '          if (i === 3 || i === 5 || i === 7 || i === 9) hx += "-";' + LineEnding +
    '        }' + LineEnding +
    '        return hx;' + LineEnding +
    '      }' + LineEnding +
    '    };' + LineEnding +
    '  }' + LineEnding +
    '  if (typeof globalThis.structuredClone !== "function") {' + LineEnding +
    '    var sc = function (v, seen) {' + LineEnding +
    '      if (v === null || typeof v !== "object") {' + LineEnding +
    '        if (typeof v === "function" || typeof v === "symbol")' + LineEnding +
    '          throw new TypeError("structuredClone: a " + typeof v + " cannot be cloned");' + LineEnding +
    '        return v;' + LineEnding +
    '      }' + LineEnding +
    '      if (seen.has(v)) return seen.get(v);' + LineEnding +
    '      var out, i, k, buf;' + LineEnding +
    '      if (v instanceof Date) return new Date(v.getTime());' + LineEnding +
    '      if (v instanceof RegExp) return new RegExp(v.source, v.flags);' + LineEnding +
    '      if (v instanceof ArrayBuffer) {' + LineEnding +
    '        buf = new ArrayBuffer(v.byteLength);' + LineEnding +
    '        new Uint8Array(buf).set(new Uint8Array(v));' + LineEnding +
    '        seen.set(v, buf);' + LineEnding +
    '        return buf;' + LineEnding +
    '      }' + LineEnding +
    '      if (v instanceof DataView)' + LineEnding +
    '        return new DataView(sc(v.buffer, seen), v.byteOffset, v.byteLength);' + LineEnding +
    '      if (ArrayBuffer.isView(v))' + LineEnding +
    '        return new v.constructor(sc(v.buffer, seen), v.byteOffset, v.length);' + LineEnding +
    '      if (v instanceof Map) {' + LineEnding +
    '        out = new Map(); seen.set(v, out);' + LineEnding +
    '        v.forEach(function (val, key) { out.set(sc(key, seen), sc(val, seen)); });' + LineEnding +
    '        return out;' + LineEnding +
    '      }' + LineEnding +
    '      if (v instanceof Set) {' + LineEnding +
    '        out = new Set(); seen.set(v, out);' + LineEnding +
    '        v.forEach(function (val) { out.add(sc(val, seen)); });' + LineEnding +
    '        return out;' + LineEnding +
    '      }' + LineEnding +
    '      if (v instanceof Error) {' + LineEnding +
    '        out = new Error(v.message);' + LineEnding +
    '        out.name = v.name;' + LineEnding +
    '        return out;' + LineEnding +
    '      }' + LineEnding +
    '      if (v instanceof Array) {' + LineEnding +
    '        out = []; seen.set(v, out);' + LineEnding +
    '        for (i = 0; i < v.length; i++) out[i] = sc(v[i], seen);' + LineEnding +
    '        return out;' + LineEnding +
    '      }' + LineEnding +
    '      out = {}; seen.set(v, out);' + LineEnding +
    '      for (k in v)' + LineEnding +
    '        if (Object.prototype.hasOwnProperty.call(v, k)) out[k] = sc(v[k], seen);' + LineEnding +
    '      return out;' + LineEnding +
    '    };' + LineEnding +
    '    globalThis.structuredClone = function (value) { return sc(value, new Map()); };' + LineEnding +
    '  }' + LineEnding +
    '})();';
  {** Gittan.commands over the two natives: register takes {id, title,
      where, run}, where a list of menu, file and editor (the menu alone
      when left out). }
  COMMANDS_SHIM: string =
    '(function () {' + LineEnding +
    '  var t = Gittan;' + LineEnding +
    '  t.commands = {' + LineEnding +
    '    register: function (o) {' + LineEnding +
    '      if (!o || typeof o.run !== "function" || !o.id)' + LineEnding +
    '        throw new TypeError("Gittan.commands.register: {id, title, run} expected");' + LineEnding +
    '      var w = o.where;' + LineEnding +
    '      if (typeof w === "string") w = [w];' + LineEnding +
    '      if (!w || !w.length) w = ["menu"];' + LineEnding +
    '      return t.registerCommand(String(o.id), String(o.title || o.id), w.join(","), o.run);' + LineEnding +
    '    },' + LineEnding +
    '    unregister: function (id) { return t.unregisterCommand(String(id)); }' + LineEnding +
    '  };' + LineEnding +
    '  var deliver = t._deliver, ANSWER_SECONDS = 300;' + LineEnding +
    '  delete t._deliver;' + LineEnding +
    '  var said = function (e) { try { return String((e && e.message) || e); } catch (x) { return "The extension failed"; } };' + LineEnding +
    '  var answer = function (seq, p) {' + LineEnding +
    '    var done = false, timer = null;' + LineEnding +
    '    var send = function (o) {' + LineEnding +
    '      if (done) return;' + LineEnding +
    '      done = true;' + LineEnding +
    '      if (timer !== null && typeof clearTimeout === "function") clearTimeout(timer);' + LineEnding +
    '      var s;' + LineEnding +
    '      try { s = JSON.stringify(o); } catch (e) { s = JSON.stringify({ error: "The answer is not JSON: " + said(e) }); }' + LineEnding +
    '      deliver(Number(seq), s);' + LineEnding +
    '    };' + LineEnding +
    '    if (typeof setTimeout === "function")' + LineEnding +
    '      timer = setTimeout(function () { send({ error: "The extension did not answer within " + ANSWER_SECONDS + " seconds" }); }, ANSWER_SECONDS * 1000);' + LineEnding +
    '    Promise.resolve().then(p).then(' + LineEnding +
    '      function (v) { send({ value: v === undefined ? null : v }); },' + LineEnding +
    '      function (e) { send({ error: said(e) }); });' + LineEnding +
    '  };' + LineEnding +
    '  t.forgeTabs = {' + LineEnding +
    '    register: function (o) {' + LineEnding +
    '      if (!o || typeof o.render !== "function" || !o.id)' + LineEnding +
    '        throw new TypeError("Gittan.forgeTabs.register: {id, title, render} expected");' + LineEnding +
    '      return t.registerForgeTab(String(o.id), String(o.title || o.id), String(o.description || ""), function (ctx) {' + LineEnding +
    '        var seq = ctx.seq; delete ctx.seq;' + LineEnding +
    '        if (ctx.kind === "action") {' + LineEnding +
    '          var a = ctx.action, row = ctx.row; delete ctx.kind; delete ctx.action; delete ctx.row;' + LineEnding +
    '          answer(seq, function () { return typeof o.action === "function" ? o.action(a, row, ctx) : undefined; });' + LineEnding +
    '        } else {' + LineEnding +
    '          delete ctx.kind;' + LineEnding +
    '          answer(seq, function () { return o.render(ctx); });' + LineEnding +
    '        }' + LineEnding +
    '      });' + LineEnding +
    '    },' + LineEnding +
    '    unregister: function (id) { return t.unregisterForgeTab(String(id)); }' + LineEnding +
    '  };' + LineEnding +
    '  t.batch = {' + LineEnding +
    '    register: function (o) {' + LineEnding +
    '      if (!o || typeof o.run !== "function" || !o.id)' + LineEnding +
    '        throw new TypeError("Gittan.batch.register: {id, title, run} expected");' + LineEnding +
    '      return t.registerBatch(String(o.id), String(o.title || o.id), String(o.description || ""), function (ctx) {' + LineEnding +
    '        var seq = ctx.seq; delete ctx.seq;' + LineEnding +
    '        answer(seq, function () { return o.run(ctx); });' + LineEnding +
    '      });' + LineEnding +
    '    },' + LineEnding +
    '    unregister: function (id) { return t.unregisterBatch(String(id)); }' + LineEnding +
    '  };' + LineEnding +
    '})();';
var
  ctx: JSContext;
begin
  ctx := CurrentRegistrationContext;
  if ctx = nil then Exit;

  // Gittan.alert/.confirm/.prompt/.select/.log and the bare alert() global → UI group.
  addClassFunctionIf(epUI, 'alert',   @JSDoAlert, 1);
  addClassFunctionIf(epUI, 'confirm', @JSDoYesNo, 1);
  addClassFunctionIf(epUI, 'prompt',  @JSInput,   4);
  addClassFunctionIf(epUI, 'select',  @JSCombo,  -1);
  addClassFunctionIf(epUI, 'log',     @JSDoLog,   1);
  addFunctionIf     (epUI, 'alert',   @JSDoAlert, 1);

  // Gittan.on/.off reach every context: an event costs the user nothing.
  // The commands go in the menus, so they are the UI group's.
  addClassFunction('on',  @JSOn,  2);
  addClassFunction('off', @JSOff, 2);
  addClassFunctionIf(epUI, 'registerCommand',   @JSCommandRegister,   4);
  addClassFunctionIf(epUI, 'unregisterCommand', @JSCommandUnregister, 1);
  // The forge view's tabs and the Batch tab's operations, whose functions
  // answer through _deliver, which the shim takes out of reach.
  addClassFunctionIf(epUI, 'registerForgeTab',   @JSForgeTabRegister,   4);
  addClassFunctionIf(epUI, 'unregisterForgeTab', @JSForgeTabUnregister, 1);
  addClassFunctionIf(epUI, 'registerBatch',      @JSBatchRegister,      4);
  addClassFunctionIf(epUI, 'unregisterBatch',    @JSBatchUnregister,    1);
  addClassFunctionIf(epUI, '_deliver',           @JSDeliver,            2);
  if CanRegister(epUI) then
    ExecuteInCurrent(COMMANDS_SHIM, '<commands shim>');

  // Timer family → timers group (baseline, always granted today).
  addFunctionIf(epTimers, 'setTimeout',    @JSSetTimeout,  2);
  addFunctionIf(epTimers, 'setInterval',   @JSSetInterval, 2);
  addFunctionIf(epTimers, 'clearTimeout',  @JSClearTimer,  1);
  addFunctionIf(epTimers, 'clearInterval', @JSClearTimer,  1);

  // console.log/push/logs object — UI group. RegisterConsoleLog writes into ctx directly.
  if CanRegister(epUI) then
    RegisterConsoleLog(@ctx);

  // Native backends for performance.now() and the crypto shim. Permission-free:
  // a monotonic clock and random bytes touch nothing user-sensitive.
  addFunction('gittanPerfNow',   @JSPerfNow,   0);
  addFunction('gittanRandomHex', @JSRandomHex, 1);

  // Permission-free polyfills for every context: ES library methods,
  // atob/btoa/queueMicrotask, URL/URLSearchParams/TextEncoder/TextDecoder,
  // performance/crypto/structuredClone, then the console argument formatter
  // (needs console to exist already).
  ExecuteInCurrent(ES_SHIM, '<es shim>');
  ExecuteInCurrent(BASE_SHIM, '<base shim>');
  ExecuteInCurrent(WEB_SHIM, '<web shim>');
  ExecuteInCurrent(MISC_SHIM, '<misc shim>');
  ExecuteInCurrent(CONSOLE_FMT_SHIM, '<console fmt shim>');
end;

{** Free context/resources, dispose registered callbacks, stop timer, and clear singleton. }
destructor TGittanExtEngine.Destroy;
var
  cb: PJSCallback;
  tmpCtx: JSContext;
  timeoutCounter: integer;
  globalObj, timersObj: JSValueRaw;
  i: integer;
begin
  // Detach the console-attribution hook before anything else so no buffered
  // log can call back into a dying engine (runs on both shutdown paths)
  ConsoleExtNameLookup := nil;

  // ULTRA-EARLY EXIT: If application is terminating or global shutdown flag is set,
  // skip ALL cleanup operations and let OS handle memory deallocation
  if ExtHost.Terminated or IsGlobalShutdown then
  begin
    // The fptimer threads must still be told to stop: TFPTimerThread parks in
    // an event wait it never leaves on its own, and a thread still parked
    // there when the RTL tears down its thread mutexes dies in
    // pthread_mutex_lock — invisible in a plain run (the process is exiting)
    // but a SIGSEGV stop under a debugger. Enabled := false only terminates
    // and signals the thread (StopTimer never joins), so it cannot deadlock,
    // and it makes no QuickJS calls.
    try
      if Assigned(eventTimer) then
        eventTimer.Enabled := false;
    except
    end;

    // Clear references only - no QuickJS API calls whatsoever
    FContext := nil;
    FRuntime := nil;
    FInstance := nil;

    // Clear singleton and exit immediately
    inherited Destroy;
    Exit;
  end;

  // Normal shutdown path - only execute when application is NOT terminating
  // Give extensions their unloadCallback while contexts are still intact.
  // (The FormClose quit path takes the ultra-early exit above and has already
  // notified before signalling shutdown.)
  try
    NotifyUnloadAll;
  except
  end;

  // Stop the job-pumping timer ASAP to avoid re-entrancy during teardown
  try
    if Assigned(eventTimer) then
    begin
      eventTimer.Enabled := false;
      FreeAndNil(eventTimer);
    end;
  except
  end;

  // Clean up all active JS timers (Modified: January 16, 2026)
  if Assigned(FJSTimers) then
  try
    while FJSTimers.Count > 0 do
    begin
      DisposeTimerInfo(FJSTimers.Data[0]);
      FJSTimers.Delete(0);
    end;
    FreeAndNil(FJSTimers);
  except
      // Silently handle any errors during timer cleanup
  end;

  // Dispose retired timers that the job pump hadn't drained yet
  try
    DrainDeadTimers;
    FreeAndNil(FDeadTimers);
  except
  end;

  // Signal extension shutdown to background tasks
  SetExtShuttingDown(true);

  // Give background promise threads time to notice shutdown and complete.
  // ProcessMessages keeps Synchronize() calls draining; exits as soon as the
  // last TJSAsyncTask is gone, with a 2s cap as a safety net.
  timeoutCounter := 0;
  while (ActiveAsyncTaskCount > 0) and (timeoutCounter < 400) do
  begin
    ExtHost.Pump;
    Sleep(5);
    Inc(timeoutCounter);
  end;

  // Unregister host promise rejection tracker and the watchdog hook (its
  // opaque pointer is this instance) to avoid callbacks during teardown
  if FRuntime <> nil then
  begin
    JS_SetHostPromiseRejectionTracker(FRuntime, nil, nil);
    JS_SetInterruptHandler(FRuntime, nil, nil);
  end;

  // Normal shutdown path continues - application is not terminating
  // Drain pending jobs, if any, before freeing context/runtime
  if (FRuntime <> nil) and (FContext <> nil) then
  begin
    // More aggressive job draining with timeout
    timeoutCounter := 0;
    while JS_IsJobPending(FRuntime) and (timeoutCounter < 100) do  // Max 100 iterations
    begin
      if JS_ExecutePendingJob(FRuntime, @tmpCtx) <= 0 then
        Break;
      Inc(timeoutCounter);

      // Give a small pause every few iterations
      if timeoutCounter mod 10 = 0 then
        Sleep(1);
    end;
  end;

  // Force garbage collection to clean up remaining objects
  if (FRuntime <> nil) then
  begin
    // Run garbage collection multiple times to ensure cleanup
    JS_RunGC(FRuntime);
    JS_RunGC(FRuntime);  // Run twice to handle circular references
  end;

  // Dispose dynamically allocated callbacks
  for cb in promises do
    Dispose(cb);
  FreeAndNil(promises);

  for cb in callbacks do
    Dispose(cb);
  FreeAndNil(callbacks);

  // Free per-extension contexts. Each ctx is allocated against FRuntime; we
  // free them here while the runtime is still alive.
  if Assigned(FExtContexts) then
  try
    for i := 0 to FExtContexts.Count - 1 do
      if FExtContexts[i] <> nil then
      begin
        if FExtContexts[i]^.Ctx <> nil then
        try
          FRegistry.RemoveContext(FExtContexts[i]^.Ctx);
          JS_FreeContext(FExtContexts[i]^.Ctx);
        except
        end;
        Dispose(FExtContexts[i]);
      end;
    FreeAndNil(FExtContexts);
  except
  end;

  // Free auxiliary structures
  FreeAndNil(knownfunc);

  // Force final garbage collection before freeing context
  if (FRuntime <> nil) then
    JS_RunGC(FRuntime);

  // Normal context cleanup
  if Assigned(FContext) then
  begin
    try
      // Ensure no more jobs are pending before freeing context
      if (FRuntime <> nil) then
      begin
        // Final check for any remaining jobs
        tmpCtx := FContext;
        timeoutCounter := 0;
        while JS_IsJobPending(FRuntime) and (timeoutCounter < 10) do
        begin
          JS_ExecutePendingJob(FRuntime, @tmpCtx);
          Inc(timeoutCounter);
        end;

        // Final garbage collection before context destruction
        JS_RunGC(FRuntime);
      end;

      // Now free the context
      JS_FreeContext(FContext);
    except
      // If context freeing fails, just continue - the runtime cleanup will handle it
    end;
    FContext := nil;
  end;

  // Normal runtime cleanup
  if Assigned(FRuntime) then
  begin
    try
      {$IFDEF DEBUG}
      // In debug builds, skip QuickJS runtime cleanup to avoid debugger issues
      // This prevents debugger stops at JS_FreeRuntime while maintaining clean shutdown
      // The OS will handle memory cleanup when the process terminates
      {$ELSE}
      // Try to run final garbage collection cycles to clean up remaining objects
      JS_RunGC(FRuntime);
      JS_RunGC(FRuntime);  // Multiple passes for circular references

      // Wait a bit more to ensure all cleanup is done
      Sleep(50);

      // Now attempt to free the runtime
      JS_FreeRuntime(FRuntime);
      {$ENDIF}
    except
      on E: Exception do
      begin
        // Log the error for debugging but don't crash
        {$IFDEF DEBUG}
        // Only log in debug mode to avoid user-facing errors
        try
          ExtError('QuickJS Runtime Cleanup', 'Non-critical cleanup error: ' + E.Message);
        except
          // If even error reporting fails, just ignore completely
        end;
        {$ENDIF}
      end;
    end;
    FRuntime := nil;
  end;

  // Free native helper at the very end

  // Clear singleton reference without freeing again
  FInstance := nil;

  FreeAndNil(FRegistry);
  inherited Destroy;
end;

{******************************************************************************
  Registration helpers and globals
******************************************************************************}

{** Resolve the active registration target. During BeginRegistration..EndRegistration
    this is the extension context being provisioned; otherwise it is FContext
    (the admin/legacy bootstrap context). }
function TGittanExtEngine.CurrentRegistrationContext: JSContext;
begin
  if FCurrentRegCtx <> nil then
    Result := FCurrentRegCtx
  else
    Result := FContext;
end;

{** Permission gate. Outside a BeginRegistration block all groups are
    considered granted so legacy/internal registrations still work. }
function TGittanExtEngine.CanRegister(const grp: TExtPermGroup): boolean;
begin
  if FCurrentRegCtx = nil then
    Exit(true);
  Result := grp in FCurrentRegPerms;
end;

{** Add a global JS function. Writes into the current registration context. }
procedure TGittanExtEngine.addFunction(const id: string; const func: ExtFunction;
const argc: integer = 0);
var
  ctx: JSContext;
begin
  ctx := CurrentRegistrationContext;
  if ctx = nil then Exit;
  ctx^.SetFunction([], pchar(id), func, argc);
end;

{** Add a JS method under the 'Gittan' class in the current registration context. }
procedure TGittanExtEngine.addClassFunction(const id: string;
const func: ExtFunction; const argc: integer = 0);
var
  this: JSValue;
  ctx: JSContext;
begin
  ctx := CurrentRegistrationContext;
  if ctx = nil then Exit;
  if not ctx^.GetValue('Gittan', this) then
  begin
    ExtError('Cannot locate the Gittan class while initializing extensions');
    Exit;
  end;

  ctx^.SetFunction(this, pchar(id), func, argc);
end;

{** Gated variant: only register if the permission group is granted. }
procedure TGittanExtEngine.addClassFunctionIf(const grp: TExtPermGroup;
const id: string; const func: ExtFunction; const argc: integer = 0);
begin
  if CanRegister(grp) then
    addClassFunction(id, func, argc);
end;

procedure TGittanExtEngine.addFunctionIf(const grp: TExtPermGroup;
const id: string; const func: ExtFunction; const argc: integer = 0);
begin
  if CanRegister(grp) then
    addFunction(id, func, argc);
end;

{** Create an empty global object named @code(name) in the current registration context. }
procedure TGittanExtEngine.CreateNewObject(const Name: string);
var
  GlobalObj, JSObject: JSValueRaw;
  ctx: JSContext;
begin
  ctx := CurrentRegistrationContext;
  if ctx = nil then Exit;
  GlobalObj := JS_GetGlobalObject(ctx);
  try
    // JS_SetPropertyStr consumes JSObject (on failure too), so that one is not
    // ours to free - but the global object is a fresh reference and is.
    JSObject := JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, GlobalObj, pansichar(Name), JSObject);
  finally
    JS_FreeValue(ctx, GlobalObj);
  end;
end;

{** Set a global JS string variable in the current registration context. }
procedure TGittanExtEngine.SetGlobalVariable(const VarName: RawUtf8;
const Value: RawUtf8; const obj: string = '');
var
  JValue, GlobalObj: JSValueRaw;
  ctx: JSContext;
begin
  ctx := CurrentRegistrationContext;
  if ctx = nil then Exit;
  GlobalObj := JS_GetGlobalObject(ctx);
  try
    // JValue is consumed by JS_SetPropertyStr; GlobalObj is ours to release.
    JValue := JS_NewString(ctx, pansichar(Value));
    JS_SetPropertyStr(ctx, GlobalObj, pansichar(VarName), JValue);
  finally
    JS_FreeValue(ctx, GlobalObj);
  end;
end;

{** Set a global JS int64 variable in the current registration context. }
procedure TGittanExtEngine.SetGlobalVariable(const VarName: RawUtf8;
const Value: int64; const obj: string = '');
var
  GlobalObj, JValue: JSValueRaw;
  ctx: JSContext;
begin
  ctx := CurrentRegistrationContext;
  if ctx = nil then Exit;
  GlobalObj := JS_GetGlobalObject(ctx);
  try
    // JValue is consumed by JS_SetPropertyStr; GlobalObj is ours to release.
    JValue := JS_NewBigInt64(ctx, Value);
    JS_SetPropertyStr(ctx, GlobalObj, pansichar(VarName), JValue);
  finally
    JS_FreeValue(ctx, GlobalObj);
  end;
end;

{******************************************************************************
  Per-extension contexts (Path B isolation)
******************************************************************************}

function TGittanExtEngine.ExtensionCount: integer;
begin
  if Assigned(FExtContexts) then
    Result := FExtContexts.Count
  else
    Result := 0;
end;

function TGittanExtEngine.ExtensionAt(idx: integer): PExtContextInfo;
begin
  if (not Assigned(FExtContexts)) or (idx < 0) or (idx >= FExtContexts.Count) then
    Exit(nil);
  Result := FExtContexts[idx];
end;

function TGittanExtEngine.ExtensionNameForContext(ctx: JSContext): string;
var
  i: integer;
begin
  Result := '';
  if (ctx = nil) or (not Assigned(FExtContexts)) then
    Exit;
  for i := 0 to FExtContexts.Count - 1 do
    if (FExtContexts[i] <> nil) and (FExtContexts[i]^.Ctx = ctx) then
    begin
      Result := FExtContexts[i]^.DisplayName;
      if Result = '' then
        Result := FExtContexts[i]^.ExtId;
      Exit;
    end;
end;

function TGittanExtEngine.ExtensionIdForContext(ctx: JSContext): string;
var
  i: integer;
begin
  Result := '';
  if (ctx = nil) or (not Assigned(FExtContexts)) then
    Exit;
  for i := 0 to FExtContexts.Count - 1 do
    if (FExtContexts[i] <> nil) and (FExtContexts[i]^.Ctx = ctx) then
      Exit(FExtContexts[i]^.ExtId);
end;

function TGittanExtEngine.GenerationForContext(ctx: JSContext): QWord;
var
  i: integer;
begin
  Result := 0;
  if (ctx = nil) or (not Assigned(FExtContexts)) then
    Exit;
  for i := 0 to FExtContexts.Count - 1 do
    if (FExtContexts[i] <> nil) and (FExtContexts[i]^.Ctx = ctx) then
      Exit(FExtContexts[i]^.Generation);
end;

function TGittanExtEngine.ModuleRootForContext(ctx: JSContext): string;
var
  i: integer;
begin
  Result := '';
  if (ctx = nil) or (not Assigned(FExtContexts)) then
    Exit;
  for i := 0 to FExtContexts.Count - 1 do
    if (FExtContexts[i] <> nil) and (FExtContexts[i]^.Ctx = ctx) then
      Exit(ExtractFilePath(FExtContexts[i]^.FileName));
end;

function TGittanExtEngine.ModuleEntryForContext(ctx: JSContext): string;
var
  i: integer;
begin
  Result := '';
  if (ctx = nil) or (not Assigned(FExtContexts)) then
    Exit;
  for i := 0 to FExtContexts.Count - 1 do
    if (FExtContexts[i] <> nil) and (FExtContexts[i]^.Ctx = ctx) then
      Exit(FExtContexts[i]^.FileName);
end;

procedure TGittanExtEngine.NotifyUnloadAll;
var
  i: integer;
  info: PExtContextInfo;
  ctx: JSContext;
  globalObj, funcObj, retVal: JSValueRaw;
  oldMask: TFPUExceptionMask;
begin
  if not Assigned(FExtContexts) then
    Exit;

  // The listeners first, then the global unloadCallback the module
  // bootstrap and older scripts use.
  Emit('unload', '{}');

  // The quit path runs UX dialogs before we get here, and those can leave the
  // FPU exception mask with traps unmasked; QuickJS float ops then die with
  // STATUS_FLOAT_INVALID_OPERATION. Mask FP traps for the JS calls (same
  // pattern as umain_async.inc) and restore afterwards.
  oldMask := GetExceptionMask;
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
  for i := 0 to FExtContexts.Count - 1 do
  begin
    info := FExtContexts[i];
    if (info = nil) or (info^.Ctx = nil) then
      Continue;
    ctx := info^.Ctx;
    if not ContextHasFunction(ctx, 'unloadCallback') then
      Continue;

    globalObj := JS_GetGlobalObject(ctx);
    funcObj := JS_GetPropertyStr(ctx, globalObj, 'unloadCallback');
    retVal := JS_UNDEFINED;
    try
      try
        if JS_IsFunction(ctx, funcObj) then
        begin
          retVal := JS_Call(ctx, funcObj, globalObj, 0, nil);
          // JS_IsException, not JS_IsError: a throwing unload hook returns the
          // exception marker, and it must not be left pending on a context the
          // teardown below is about to free.
          if JS_IsException(retVal) then
            DumpJSError(ctx);
        end;
      except
        // One extension's failing unload hook must not block the others.
      end;
    finally
      ctx^.FreeInlined(PJSValue(@retVal));
      ctx^.FreeInlined(PJSValue(@funcObj));
      ctx^.FreeInlined(PJSValue(@globalObj));
    end;
  end;
  finally
    SetExceptionMask(oldMask);
  end;
end;

procedure TGittanExtEngine.DropExtensionContext(Ext: PExtContextInfo);
var
  i: integer;
  ctx: JSContext;
begin
  if (Ext = nil) or (Ext^.Ctx = nil) or not Assigned(FExtContexts) then
    Exit;
  i := FExtContexts.IndexOf(Ext);
  if i < 0 then
    Exit;
  ctx := Ext^.Ctx;
  FRegistry.RemoveContext(ctx);
  { Its timers hold values of the context, so they go before it. }
  if Assigned(FJSTimers) then
    for i := FJSTimers.Count - 1 downto 0 do
      if FJSTimers.Data[i]^.Context = ctx then
      begin
        DisposeTimerInfo(FJSTimers.Data[i]);
        FJSTimers.Delete(i);
      end;
  if Assigned(FDeadTimers) then
    for i := FDeadTimers.Count - 1 downto 0 do
      if FDeadTimers[i]^.Context = ctx then
      begin
        DisposeTimerInfo(FDeadTimers[i]);
        FDeadTimers.Delete(i);
      end;
  { Out of the list first: a promise task of it then finds no generation
    and leaves its promise alone. }
  FExtContexts.Remove(Ext);
  JS_FreeContext(ctx);
  Dispose(Ext);
end;

procedure TGittanExtEngine.UnloadExtensions;
var
  i, timeoutCounter: integer;
  tmpCtx: JSContext;
begin
  if IsGlobalShutdown or ExtHost.Terminated then Exit;

  // Let extensions flush state while their contexts (and timers) still exist.
  NotifyUnloadAll;

  // Stop and drop every JS timer (setTimeout/setInterval). All live timers belong
  // to extension contexts since baseline contexts don't schedule any; their
  // held JS values must be released before those contexts die below.
  if Assigned(FJSTimers) then
  try
    while FJSTimers.Count > 0 do
    begin
      DisposeTimerInfo(FJSTimers.Data[0]);
      FJSTimers.Delete(0);
    end;
  except
  end;

  // Dispose retired timers parked for the job pump; their contexts die below.
  try
    DrainDeadTimers;
  except
  end;

  // Signal in-flight promise threads to bail before we free their target ctxs.
  SetExtShuttingDown(true);
  try
    // Wait for in-flight promise threads to finish (up to ~1s); exits
    // immediately when none are running, so reloads stay snappy.
    timeoutCounter := 0;
    while (ActiveAsyncTaskCount > 0) and (timeoutCounter < 200) do
    begin
      ExtHost.Pump;
      Sleep(5);
      Inc(timeoutCounter);
    end;

    // Drain any pending microtasks/promise jobs queued against soon-to-die ctxs.
    if FRuntime <> nil then
    begin
      timeoutCounter := 0;
      while JS_IsJobPending(FRuntime) and (timeoutCounter < 100) do
      begin
        if JS_ExecutePendingJob(FRuntime, @tmpCtx) <= 0 then Break;
        Inc(timeoutCounter);
      end;
      JS_RunGC(FRuntime);
    end;

    // Free per-extension contexts. Runtime stays alive.
    if Assigned(FExtContexts) then
    try
      for i := 0 to FExtContexts.Count - 1 do
        if FExtContexts[i] <> nil then
        begin
          if FExtContexts[i]^.Ctx <> nil then
          try
            FRegistry.RemoveContext(FExtContexts[i]^.Ctx);
            JS_FreeContext(FExtContexts[i]^.Ctx);
          except
          end;
          Dispose(FExtContexts[i]);
        end;
      FExtContexts.Clear;
    except
    end;
  finally
    // Re-arm so a subsequent LoadExtensions can register and run scripts again.
    SetExtShuttingDown(false);
  end;
end;

{** Create a fresh extension JSContext on the shared runtime, with intrinsics, the
    'Gittan' class and the opaque engine pointer set up. The new context is appended
    to FExtContexts and returned to the caller, which should call BeginRegistration
    to set it as the active registration target. }
function TGittanExtEngine.NewExtensionContext(const ExtId, FileName, Hash,
DisplayName, Author: string; Granted: TExtPermSet): PExtContextInfo;
var
  ctx: JSContext;
  Info: PExtContextInfo;
  globalObj: JSValue;
begin
  Result := nil;
  if FRuntime = nil then Exit;

  ctx := JS_NewContext(FRuntime);
  if ctx = nil then Exit;

  // Wire the engine pointer so native callbacks can locate us from a ctx.
  JS_SetContextOpaque(ctx, Self);

  // Standard intrinsics so Promises/RegExp/Date work as in the legacy engine.
  JS_AddIntrinsicPromise(ctx);
  JS_AddIntrinsicRegExp(ctx);
  JS_AddIntrinsicDate(ctx);

  // Expose 'Gittan' constructor in this context's global scope so addClassFunction
  // calls during provisioning can attach methods to Gittan.*
  globalObj := JS_GetGlobalObject(ctx);
  try
    JS_SetPropertyStr(ctx, globalObj, 'Gittan',
      JS_NewConstructor(ctx, 'Gittan', 0,
      RegisterNative('Gittan', @GittanConstructor)));
  finally
    JS_FreeValue(ctx, globalObj);
  end;

  New(Info);
  Info^.Ctx := ctx;
  Info^.FileName := FileName;
  Info^.ExtId := ExtId;
  Info^.Hash := Hash;
  Info^.DisplayName := DisplayName;
  Info^.Author := Author;
  Info^.Granted := Granted;
  Inc(FContextGeneration);
  Info^.Generation := FContextGeneration;

  // Provision engine-internal baselines (alert/confirm/prompt/select/log/timers/console)
  // into this ctx, gated by Granted. Caller will follow up with BeginRegistration to
  // register the umain-level Gittan.* methods and then ExtExecuteFile.
  // Only publish into FExtContexts after baseline provisioning succeeds, so
  // FunctionExists/broadcast loops never observe a half-initialized context.
  try
    BeginRegistration(Info);
    try
      RegisterEngineBaselineForCurrent;
    finally
      EndRegistration;
    end;
  except
    JS_FreeContext(ctx);
    Dispose(Info);
    raise;
  end;

  FExtContexts.Add(Info);

  Result := Info;
end;

procedure TGittanExtEngine.BeginRegistration(Ext: PExtContextInfo);
begin
  if Ext = nil then Exit;
  FCurrentRegCtx := Ext^.Ctx;
  FCurrentRegPerms := Ext^.Granted;
  FCurrentRegExtId := Ext^.ExtId;
end;

procedure TGittanExtEngine.EndRegistration;
begin
  FCurrentRegCtx := nil;
  FCurrentRegPerms := [];
  FCurrentRegExtId := '';
end;

function TGittanExtEngine.CurrentRegistrationExtensionId: string;
begin
  Result := FCurrentRegExtId;
end;

const
  JSIdentChars = ['A'..'Z', 'a'..'z', '0'..'9', '_', '$'];

{** True when a failed eval looks like the parser rejecting top-level await
    (without JS_EVAL_FLAG_ASYNC, await is only legal inside async functions).
    Checks for a SyntaxError plus the word 'await' anywhere in the source; a
    false positive is harmless since the async-mode retry just fails with an
    equivalent error. }
function IsTopLevelAwaitError(const Script, Err: RawUtf8): boolean;
var
  p: integer;
begin
  Result := false;
  if Pos('SyntaxError', Err) = 0 then
    Exit;
  p := Pos('await', Script);
  while p > 0 do
  begin
    if ((p = 1) or not (Script[p - 1] in JSIdentChars)) and
      ((p + 5 > Length(Script)) or not (Script[p + 5] in JSIdentChars)) then
      Exit(true);
    p := PosEx('await', Script, p + 1);
  end;
end;

{** Evaluate a module-shaped extension (static @code(import)/@code(export))
    through the bootstrap script from @code(gittan.ext.modules): a dynamic
    @code(import()) of the file, whose exported functions are then published
    as globals so the name-based callbacks keep working. The module graph is
    loaded and run inside the PumpJobs call, after which the bootstrap's
    error slot tells whether the load failed. A rejection that arrives later
    (a top-level @code(await) still pending) is rethrown by the bootstrap and
    reported by the unhandled-rejection tracker, like a classic async script. }
function TGittanExtEngine.ExtExecuteModule(Ext: PExtContextInfo): RawUtf8;
var
  ctx: JSContext;
  EvalResult: JSValue;
  err, loadErr: RawUtf8;
begin
  Result := '';
  ctx := Ext^.Ctx;

  EvalResult := ctx^.Eval(ModuleBootstrapScript(Ext^.FileName),
    ExtractFileName(Ext^.FileName), JS_EVAL_TYPE_GLOBAL, err);
  if EvalResult.IsException then
  begin
    ctx^.Free(EvalResult);
    ExtError('Error loading', err);
    FLastLoadFailed := true;
    Exit('Error: ' + err);
  end;
  ctx^.Free(EvalResult);

  // Loads, links and evaluates the module graph: the loader runs synchronously
  // inside import(), so a parse error or a throw at module top level has
  // landed in the error slot by the time the queue is drained.
  PumpJobs;

  EvalResult := ctx^.Eval('String(globalThis.' + ModuleBootstrapGlobal + '.error)',
    '<module-bootstrap>', JS_EVAL_TYPE_GLOBAL, err);
  if EvalResult.IsException then
    loadErr := err
  else
    loadErr := JS_ToUtf8(ctx, EvalResult);
  ctx^.Free(EvalResult);

  // Drop the slot: from now on the bootstrap rethrows instead of recording.
  EvalResult := ctx^.Eval('delete globalThis.' + ModuleBootstrapGlobal,
    '<module-bootstrap>', JS_EVAL_TYPE_GLOBAL, err);
  ctx^.Free(EvalResult);

  if loadErr <> '' then
  try
    ExtError('Error loading', loadErr);
    FLastLoadFailed := true;
    Result := 'Error: ' + loadErr;
  except
    on E: Exception do
      ExtError('An extension''s code resulted in an error: ' + e.message);
  end;
end;

{** Read the extension's file and evaluate it in its own context. Mirrors the
    legacy ExecuteFile contract (error string starts with 'Error:'). }
function TGittanExtEngine.ExtExecuteFile(Ext: PExtContextInfo): RawUtf8;
var
  Script: RawUtf8;
  FileStream: TFileStream;
  StringStream: TStringStream;
  EvalResult: JSValue;
  ResultStr: pansichar;
  err: RawUtf8;
  ctx: JSContext;
begin
  Result := '';
  FLastLoadFailed := false;
  if (Ext = nil) or IsGlobalShutdown then Exit;
  ctx := Ext^.Ctx;
  if ctx = nil then Exit;

  if not FileExists(Ext^.FileName) then
    raise Exception.CreateFmt(RS_EXT_FILE, [Ext^.FileName]);

  FileStream := TFileStream.Create(Ext^.FileName, fmOpenRead or fmShareDenyWrite);
  StringStream := TStringStream.Create;
  try
    StringStream.CopyFrom(FileStream, FileStream.Size);
    Script := StringStream.DataString;
  finally
    StringStream.Free;
    FileStream.Free;
  end;

  FOutput := '';
  if ScriptLooksLikeModule(Script) then
    Exit(ExtExecuteModule(Ext));

  EvalResult := ctx^.Eval(Script, ExtractFileName(Ext^.FileName),
    JS_EVAL_TYPE_GLOBAL, err);
  // When the parse fails and the script uses await, retry in async mode:
  // quickjs-ng's JS_EVAL_FLAG_ASYNC allows top-level await while keeping
  // top-level function/var declarations global, so name-based callbacks
  // (clockView, ...) stay visible to Pascal. The eval then returns a promise;
  // a rejection that escapes the top level is reported by the engine's
  // unhandled-rejection tracker once the job queue drains. Non-await scripts
  // keep the plain eval so their result value and semantics are unchanged.
  if EvalResult.IsException and IsTopLevelAwaitError(Script, err) then
  begin
    ctx^.Free(EvalResult);
    EvalResult := ctx^.Eval(Script, ExtractFileName(Ext^.FileName),
      JS_EVAL_TYPE_GLOBAL or JS_EVAL_FLAG_ASYNC, err);
  end;
  if EvalResult.IsException then
  try
    // Eval already took the exception off the context, so err is the only copy
    // that still exists. Fetching it a second time yields [uninitialized], and
    // reading properties off that leaves a fresh TypeError pending.
    ExtError('Error loading', err);
    FLastLoadFailed := true;
    Result := 'Error: ' + err;
  except
    on E: Exception do
      ExtError('An extension''s code resulted in an error: ' + e.message);
  end
  else
  begin
    ResultStr := JS_ToCString(ctx, EvalResult.Raw);
    Result := ResultStr;
    JS_FreeCString(ctx, ResultStr);
  end;
  ctx^.Free(EvalResult);

  // Run whatever the script scheduled (top-level await continuations, .then
  // chains) now rather than at the next timer tick.
  PumpJobs;
end;

{******************************************************************************
  Execution and invocation
******************************************************************************}

{** Load and execute a JS file from disk, returning result as string. }
function TGittanExtEngine.ExecuteFile(const FileName: string): RawUtf8;
var
  Script: RawUtf8;
  FileStream: TFileStream;
  StringStream: TStringStream;
begin
  // Emergency exit if application is shutting down
  if IsGlobalShutdown then
  begin
    Result := '';
    Exit;
  end;

  Result := '';
  if not FileExists(FileName) then
    raise Exception.CreateFmt(RS_EXT_FILE, [FileName]);

  // Read file contents into Script
  FileStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  StringStream := TStringStream.Create;
  try
    StringStream.CopyFrom(FileStream, FileStream.Size);
    Script := StringStream.DataString;
  finally
    StringStream.Free;
    FileStream.Free;
  end;

  // Execute with the file name for better diagnostics
  Result := Execute(Script, ExtractFileName(filename));
end;

{** Execute a JS string in global scope and return its stringified result or error text. }
function TGittanExtEngine.Execute(const Script: RawUtf8;
Name: string = '<script>'): RawUtf8;
var
  EvalResult: JSValue;
  ResultStr: pansichar;
  err: RawUtf8;
begin
  // Emergency exit if application is shutting down
  if IsGlobalShutdown then
  begin
    Result := '';
    Exit;
  end;

  FOutput := '';

  EvalResult := FContext^.Eval(Script, Name, JS_EVAL_TYPE_GLOBAL, err);

  if EvalResult.IsException then
  try
    // Present the error. Eval already cleared the exception and put its message
    // and stack in err; asking the context again returns [uninitialized].
    ExtError('Error loading', err);
    FLastLoadFailed := true;
    Result := 'Error: ' + err;
  except
    on E: Exception do
      ExtError('An extension''s code resulted in an error: ' + e.message);
  end
  else
  begin
    // Convert non-exception value to string
    ResultStr := JS_ToCString(FContext, EvalResult.Raw);
    Result := ResultStr;
    JS_FreeCString(FContext, ResultStr);
  end;

  // Release evaluation result
  FContext^.Free(EvalResult);

  // Resolve any promise chains the script queued without timer latency.
  PumpJobs;
end;

{** Evaluate a script in the current registration context. Unlike Execute this
    targets the extension ctx being provisioned, so shims land in the right
    global scope and are gone when that extension's context is freed. }
function TGittanExtEngine.ExecuteInCurrent(const Script: RawUtf8;
const Name: string = '<shim>'): boolean;
var
  ctx: JSContext;
  EvalResult: JSValue;
  err: RawUtf8;
begin
  Result := false;
  if IsGlobalShutdown then Exit;
  ctx := CurrentRegistrationContext;
  if ctx = nil then Exit;

  EvalResult := ctx^.Eval(Script, Name, JS_EVAL_TYPE_GLOBAL, err);
  Result := not EvalResult.IsException;
  if not Result then
    ExtError('Error loading ' + Name, err);
  ctx^.Free(EvalResult);
  PumpJobs;
end;

{** Call @code(FuncName) on @code(ctx) with string arguments. Returns the call
    result stringified, or '' if the function is missing/not callable. }
function CallStringArgsInContext(ctx: JSContext; const FuncName: RawUtf8;
const Args: JSArray): RawUtf8;
var
  GlobalObj, FuncObj, RetVal: JSValueRaw;
  ArgArray: array of JSValueRaw;
  i: integer;
  StrResult: pansichar;
begin
  Result := '';
  if ctx = nil then Exit;
  if not ContextHasFunction(ctx, string(FuncName)) then Exit;

  GlobalObj := JS_GetGlobalObject(ctx);
  FuncObj := JS_GetPropertyStr(ctx, GlobalObj, pchar(FuncName));
  RetVal := JS_UNDEFINED;
  try
    if not JS_IsFunction(ctx, FuncObj) then Exit;

    SetLength(ArgArray, Length(Args));
    for i := 0 to High(Args) do
      ArgArray[i] := JS_NewString(ctx, pchar(Args[i]));

    RetVal := JS_Call(ctx, FuncObj, GlobalObj, Length(ArgArray), @ArgArray[0]);
    // JS_IsException, not JS_IsError: a throw returns the exception marker
    // rather than an Error object, and DumpJSError has to clear it.
    if JS_IsException(RetVal) then
    begin
      DumpJSError(ctx);
      Exit;
    end;

    StrResult := JS_ToCString(ctx, RetVal);
    if StrResult <> nil then
    begin
      Result := StrResult;
      JS_FreeCString(ctx, StrResult);
    end;
  finally
    for i := 0 to High(ArgArray) do
      ctx^.FreeInlined(PJSValue(@ArgArray[i]));
    ctx^.FreeInlined(PJSValue(@RetVal));
    ctx^.FreeInlined(PJSValue(@FuncObj));
    ctx^.FreeInlined(PJSValue(@GlobalObj));
  end;
end;

{** Call a global JS function with string arguments; broadcasts across every
    loaded extension context. Returns the last non-empty result (last-writer-wins
    semantics for callbacks like clockView). }
function TGittanExtEngine.CallFunction(const FuncName: RawUtf8;
const Args: JSArray): RawUtf8;
var
  i: integer;
  partial: RawUtf8;
begin
  Result := '';
  if IsExtShuttingDown or (FRuntime = nil) then Exit;

  if Assigned(FExtContexts) and (FExtContexts.Count > 0) then
  begin
    for i := 0 to FExtContexts.Count - 1 do
      if FExtContexts[i] <> nil then
      begin
        partial := CallStringArgsInContext(FExtContexts[i]^.Ctx, FuncName, Args);
        if partial <> '' then Result := partial;
      end;
  end
  else
    // Legacy fallback: no extensions loaded.
    Result := CallStringArgsInContext(FContext, FuncName, Args);

  // Promise reactions queued by the callbacks run now, not at the next tick.
  PumpJobs;
end;

{** Call @code(FuncName) on @code(ctx) with integer arguments. }
function CallIntArgsInContext(ctx: JSContext; const FuncName: RawUtf8;
const Args: array of integer): RawUtf8;
var
  GlobalObj, FuncObj, RetVal: JSValueRaw;
  ArgArray: array of JSValueRaw;
  i: integer;
  StrResult: pansichar;
begin
  Result := '';
  if ctx = nil then Exit;
  if not ContextHasFunction(ctx, string(FuncName)) then Exit;

  GlobalObj := JS_GetGlobalObject(ctx);
  FuncObj := JS_GetPropertyStr(ctx, GlobalObj, pchar(FuncName));
  RetVal := JS_UNDEFINED;
  try
    if not JS_IsFunction(ctx, FuncObj) then Exit;

    SetLength(ArgArray, Length(Args));
    for i := 0 to High(Args) do
      ArgArray[i] := JS_NewBigInt64(ctx, Args[i]);

    RetVal := JS_Call(ctx, FuncObj, GlobalObj, Length(ArgArray), @ArgArray[0]);
    // JS_IsException, not JS_IsError: a throw returns the exception marker
    // rather than an Error object, and DumpJSError has to clear it.
    if JS_IsException(RetVal) then
    begin
      DumpJSError(ctx);
      Exit;
    end;

    StrResult := JS_ToCString(ctx, RetVal);
    if StrResult <> nil then
    begin
      Result := StrResult;
      JS_FreeCString(ctx, StrResult);
    end;
  finally
    for i := 0 to High(ArgArray) do
      ctx^.FreeInlined(PJSValue(@ArgArray[i]));
    ctx^.FreeInlined(PJSValue(@RetVal));
    ctx^.FreeInlined(PJSValue(@FuncObj));
    ctx^.FreeInlined(PJSValue(@GlobalObj));
  end;
end;

{** Call a global JS function with integer arguments; broadcasts across loaded
    extension contexts. Integers are marshalled as JS BigInt64. }
function TGittanExtEngine.CallFunction(const FuncName: RawUtf8;
const Args: array of integer): RawUtf8;
var
  i: integer;
  partial: RawUtf8;
begin
  Result := '';
  if IsExtShuttingDown or (FRuntime = nil) then Exit;

  if Assigned(FExtContexts) and (FExtContexts.Count > 0) then
  begin
    for i := 0 to FExtContexts.Count - 1 do
      if FExtContexts[i] <> nil then
      begin
        partial := CallIntArgsInContext(FExtContexts[i]^.Ctx, FuncName, Args);
        if partial <> '' then Result := partial;
      end;
  end
  else
    Result := CallIntArgsInContext(FContext, FuncName, Args);

  PumpJobs;
end;

{** Marshal one Pascal open-array-of-const element into a JS value bound to
    @code(ctx). Numbers/booleans become plain JS values; every string flavour
    becomes a JS string (JS_NewString copies the bytes, so the temporaries can
    go out of scope). Unsupported kinds map to the '{unsupported}' string. }
function VarRecToJS(ctx: JSContext; const v: TVarRec): JSValueRaw;
var
  tmpv: JSValue;
  s: RawUtf8;
begin
  case v.VType of
  vtInteger:
  begin
    tmpv.From32(v.VInteger);
    Result := tmpv.Raw;
  end;
  vtInt64:
  begin
    tmpv.From64(v.VInt64^);
    Result := tmpv.Raw;
  end;
  vtExtended:
  begin
    tmpv.FromFloat(v.VExtended^);
    Result := tmpv.Raw;
  end;
  vtBoolean:
  begin
    tmpv.From(v.VBoolean);
    Result := tmpv.Raw;
  end;
  vtChar:
  begin
    s := RawUtf8(v.VChar);
    Result := JS_NewString(ctx, pchar(s));
  end;
  vtPChar:
    Result := JS_NewString(ctx, v.VPChar);
  vtAnsiString:
  begin
    s := RawUtf8(ansistring(v.VAnsiString));
    Result := JS_NewString(ctx, pchar(s));
  end;
  vtUnicodeString:
  begin
    s := RawUtf8(unicodestring(v.VUnicodeString));
    Result := JS_NewString(ctx, pchar(s));
  end;
  vtWideString:
  begin
    s := RawUtf8(widestring(v.VWideString));
    Result := JS_NewString(ctx, pchar(s));
  end;
  vtString:
  begin
    s := RawUtf8(shortstring(v.VString^));
    Result := JS_NewString(ctx, pchar(s));
  end;
  else
    Result := JS_NewString(ctx, '{unsupported}');
  end;
end;

{** Marshal an array-of-const into JSValueRaw values bound to @code(ctx) and call
    @code(FuncName). Returns the stringified result or '' on absence/error. }
function CallVarRecArgsInContext(ctx: JSContext; const FuncName: RawUtf8;
const Args: array of const): RawUtf8;
var
  GlobalObj, FuncObj, RetVal: JSValueRaw;
  ArgArray: array of JSValueRaw;
  i: integer;
  StrResult: pansichar;
begin
  Result := '';
  if ctx = nil then Exit;
  if not ContextHasFunction(ctx, string(FuncName)) then Exit;

  GlobalObj := JS_GetGlobalObject(ctx);
  FuncObj := JS_GetPropertyStr(ctx, GlobalObj, pchar(FuncName));
  RetVal := JS_UNDEFINED;
  try
    if not JS_IsFunction(ctx, FuncObj) then Exit;

    SetLength(ArgArray, Length(Args));
    for i := 0 to High(Args) do
      ArgArray[i] := VarRecToJS(ctx, Args[i]);

    // An empty array has no element 0: with range checks on, taking its
    // address raises, so zero-argument callbacks pass nil instead.
    if Length(ArgArray) = 0 then
      RetVal := JS_Call(ctx, FuncObj, GlobalObj, 0, nil)
    else
      RetVal := JS_Call(ctx, FuncObj, GlobalObj, Length(ArgArray), @ArgArray[0]);
    // JS_IsException, not JS_IsError: a throw returns the exception marker
    // rather than an Error object, and DumpJSError has to clear it.
    if JS_IsException(RetVal) then
    begin
      DumpJSError(ctx);
      Exit;
    end;
    StrResult := JS_ToCString(ctx, RetVal);
    if StrResult <> nil then
    begin
      Result := StrResult;
      JS_FreeCString(ctx, StrResult);
    end;
  finally
    for i := 0 to High(ArgArray) do
      ctx^.FreeInlined(PJSValue(@ArgArray[i]));
    ctx^.FreeInlined(PJSValue(@RetVal));
    ctx^.FreeInlined(PJSValue(@FuncObj));
    ctx^.FreeInlined(PJSValue(@GlobalObj));
  end;
end;

{** Call a global JS function with mixed Pascal arguments (array of const).
    Broadcasts across all loaded extension contexts; returns the last non-empty
    result (last-writer-wins for callbacks with return values). }
function TGittanExtEngine.CallFunction(const FuncName: RawUtf8;
const Args: array of const): RawUtf8;
var
  i: integer;
  partial: RawUtf8;
begin
  Result := '';
  if IsExtShuttingDown or (FRuntime = nil) then Exit;

  if Assigned(FExtContexts) and (FExtContexts.Count > 0) then
  begin
    for i := 0 to FExtContexts.Count - 1 do
      if FExtContexts[i] <> nil then
      begin
        partial := CallVarRecArgsInContext(FExtContexts[i]^.Ctx, FuncName, Args);
        if partial <> '' then Result := partial;
      end;
  end
  else
    Result := CallVarRecArgsInContext(FContext, FuncName, Args);

  PumpJobs;
end;

{** Build a JS Array value from an array of const. }
function TGittanExtEngine.CreateJSArray(const Values: array of const): JSValueRaw;
var
  arr: JSValueRaw;
  i: integer;
begin
  Result := JS_UNDEFINED;
  if IsExtShuttingDown or (FContext = nil) or (FRuntime = nil) then
    Exit;
  arr := JS_NewArray(FContext);
  // JS_SetPropertyUint32 steals the element reference, so no per-item free.
  for i := 0 to High(Values) do
    JS_SetPropertyUint32(FContext, arr, i, VarRecToJS(FContext, Values[i]));
  Result := arr;
end;

function TGittanExtEngine.CreateJSArrayOf(const Values: array of JSValue): JSValueRaw;
var
  arr: JSValueRaw;
  i: integer;
begin
  Result := JS_UNDEFINED;
  if IsExtShuttingDown or (FContext = nil) or (FRuntime = nil) then
    Exit;
  arr := JS_NewArray(FContext);
  // As above, the property setter takes ownership of each element.
  for i := 0 to High(Values) do
    JS_SetPropertyUint32(FContext, arr, i, Values[i]);
  Result := arr;
end;

{** Call function passing a single JS array argument. InternalCall owns and
    frees the one-shot array (freeRaw=true). }
function TGittanExtEngine.CallFunctionWithArrayArg(const FuncName: RawUtf8;
const Values: array of const): RawUtf8;
begin
  Result := '';
  if IsExtShuttingDown or (FContext = nil) or (FRuntime = nil) then
    Exit;
  Result := InternalCall(FuncName, [CreateJSArray(Values)], [], true, false);
end;

// JS value factories
function TGittanExtEngine.MakeJSString(const S: RawUtf8): JSValueRaw; inline;
begin
  if (FContext = nil) then
    exit(JS_UNDEFINED);
  Result := JS_NewString(FContext, pansichar(S));
end;

function TGittanExtEngine.MakeJSInt64(const V: int64): JSValueRaw; inline;
begin
  if (FContext = nil) then
    exit(JS_UNDEFINED);
  Result := JS_NewBigInt64(FContext, V);
end;

function TGittanExtEngine.MakeJSFloat(const V: double): JSValueRaw; inline;
var
  tmp: JSValue;
begin
  if (FContext = nil) then
    exit(JS_UNDEFINED);
  tmp := JS_UNDEFINED;
  tmp.FromFloat(V);
  Result := tmp.Raw;
end;

function TGittanExtEngine.MakeJSBool(const V: boolean): JSValueRaw; inline;
var
  tmp: JSValue;
begin
  if (FContext = nil) then
    exit(JS_UNDEFINED);
  tmp := JS_UNDEFINED;
  tmp.From(V);
  Result := tmp.Raw;
end;

function TGittanExtEngine.MakeJSArray(const Values: array of const): JSValueRaw; inline;
begin
  Result := CreateJSArray(Values);
end;

{** Call JS with prepared JSValueRaw arguments. }
function TGittanExtEngine.CallFunctionJS(const FuncName: RawUtf8;
const Args: array of JSValueRaw; autoFree: boolean): RawUtf8;
begin
  // Raw only; no Rest
  Result := InternalCall(FuncName, Args, [], autoFree, false);
end;

{** Call a JS function supplying a pre-built first JS argument (e.g. an Array) followed by
  marshalled Pascal open-array-of-const arguments.
  autoFree      => free the marshalled Rest arguments (default true)
  autoFreeFirst => additionally free the supplied FirstArg (default false) }
function TGittanExtEngine.CallFunctionArrayFirst(const FuncName: RawUtf8;
const FirstArg: JSValueRaw; const Rest: array of const; autoFree: boolean;
autoFreeFirst: boolean): RawUtf8;
begin
  Result := InternalCall(FuncName, [FirstArg], Rest, autoFreeFirst, autoFree);
end;

{** Call with an array of pre-built JSValueRaw arguments followed by marshalled Pascal args. }
function TGittanExtEngine.CallFunctionMixed(const FuncName: RawUtf8;
const RawArgs: array of JSValueRaw; const Rest: array of const;
restAutoFree: boolean; rawAutoFree: boolean): RawUtf8;
begin
  Result := InternalCall(FuncName, RawArgs, Rest, rawAutoFree, restAutoFree);
end;

// Internal unified call implementation
function TGittanExtEngine.InternalCall(const FuncName: RawUtf8;
const RawPrefix: array of JSValueRaw; const Rest: array of const;
freeRaw, freeRest: boolean): RawUtf8;
var
  GlobalObj, FuncObj, RetVal: JSValueRaw;
  ArgArray: array of JSValueRaw;
  i, base: integer;
  StrResult: pansichar;
  ctx: JSContext;
begin
  { InternalCall
    Unified backend used by:
      - CallFunctionJS         (raw only)
      - CallFunctionArrayFirst (one raw + marshalled tail)
      - CallFunctionMixed      (N raw + marshalled tail)

    Memory ownership / freeing rules:
      RawPrefix: caller-created JSValueRaw values (via MakeJSString/Int/... or other constructors).
        These are freed here only if freeRaw=true.
      Rest: values provided as "array of const" and marshalled to temporary JS strings/numbers.
        These temporaries are freed here only if freeRest=true.

    Typical usage pattern for callers wanting automatic cleanup of throw-away values:
      - Pass freeRaw=true (or autoFree/autoFreeFirst/rawAutoFree at public wrapper level).
      - Do NOT reuse RawPrefix values after the call when freeRaw=true.

    Reuse scenario:
      - Pass freeRaw=false for any JSValueRaw you intend to call with again later, and free it manually once.

    Edge case note:
      - Do not duplicate the very same JSValueRaw object multiple times inside RawPrefix when freeRaw=true
        (would attempt to free it multiple times). If needed, build separate JS values.
  }
  Result := '';
  if IsExtShuttingDown or (FContext = nil) or (FRuntime = nil) then
    Exit;

  // Prefer the per-extension context (Path B) that actually hosts the function;
  // fall back to FContext for the legacy path. FExtContexts share FRuntime with
  // FContext, so JSValueRaw values constructed via MakeJS* on FContext remain
  // valid in any ctx on the same runtime.
  ctx := nil;
  if Assigned(FExtContexts) and (FExtContexts.Count > 0) then
    for i := 0 to FExtContexts.Count - 1 do
      if (FExtContexts[i] <> nil) and
        ContextHasFunction(FExtContexts[i]^.Ctx, string(FuncName)) then
      begin
        ctx := FExtContexts[i]^.Ctx;
        Break;
      end;
  if ctx = nil then
    ctx := FContext;
  if ctx = nil then Exit;

  GlobalObj := JS_GetGlobalObject(ctx);
  FuncObj := JS_GetPropertyStr(ctx, GlobalObj, pchar(FuncName));
  RetVal := JS_UNDEFINED;
  SetLength(ArgArray, Length(RawPrefix) + Length(Rest));
  for i := 0 to High(RawPrefix) do
    ArgArray[i] := RawPrefix[i];
  base := Length(RawPrefix);
  try
    for i := 0 to High(Rest) do
      ArgArray[base + i] := VarRecToJS(ctx, Rest[i]);

    if JS_IsFunction(ctx, FuncObj) then
    begin
      if Length(ArgArray) = 0 then
        RetVal := JS_Call(ctx, FuncObj, GlobalObj, 0, nil)
      else
        RetVal := JS_Call(ctx, FuncObj, GlobalObj, Length(ArgArray), @ArgArray[0]);
      // JS_IsException, not JS_IsError: a throw returns the exception marker
      // rather than an Error object, and DumpJSError has to clear it.
      if JS_IsException(RetVal) then
        DumpJSError(ctx)
      else
      begin
        StrResult := JS_ToCString(ctx, RetVal);
        if StrResult <> nil then
        begin
          Result := StrResult;
          JS_FreeCString(ctx, StrResult);
        end;
      end;
    end;
  finally
    // Honour the caller's ownership flags on every path (including errors,
    // which previously leaked both the call temporaries and the arguments).
    if freeRest then
      for i := base to High(ArgArray) do
        ctx^.FreeInlined(PJSValue(@ArgArray[i]));
    if freeRaw then
      for i := 0 to base - 1 do
        ctx^.FreeInlined(PJSValue(@ArgArray[i]));
    ctx^.FreeInlined(PJSValue(@RetVal));
    ctx^.FreeInlined(PJSValue(@FuncObj));
    ctx^.FreeInlined(PJSValue(@GlobalObj));
    // Promise reactions queued by the call run now, not at the next tick.
    PumpJobs;
  end;
end;

{******************************************************************************
  Runtime jobs processing and discovery
******************************************************************************}

{** Drain pending Promise jobs immediately. Called after each entry into JS
    (eval, broadcast call, timer callback) so promise chains resolve right
    away instead of waiting for the next 50ms OnJSTimer tick; the timer stays
    on as the safety net for jobs queued outside those paths. Rejection
    reporting stays in OnJSTimer: FlushPendingRejections opens modal dialogs,
    which must not appear beneath an arbitrary JS call frame.
    The loop itself is JS_DrainPendingJobs in the binding, so this pump and the
    one in gittan.ext.promise share an implementation and a budget; see it for
    why the drain is bounded. }
function TGittanExtEngine.PumpJobs: boolean;
begin
  Result := true;
  if IsExtShuttingDown or (FRuntime = nil) then
    Exit;
  Result := DrainPendingJobs(FContext);
end;

{** Pump the QuickJS job queue (Promises/microtasks) on each timer tick. }
procedure TGittanExtEngine.OnJSTimer(Sender: TObject);
begin
  if IsExtShuttingDown or (FRuntime = nil) then
    Exit;

  // Dispose timers retired since the last tick (never while one is firing).
  DrainDeadTimers;

  RunDueTimers;

  // Rejections that survived a full job-queue drain are genuinely unhandled --
  // but only a full one. A budget-truncated pump leaves jobs queued, and one of
  // them may be the .catch() that handles a rejection already on the pending
  // list, so reporting now would open a modal alert for a rejection that is
  // about to be handled. The next tick pumps again and reports it then if it
  // survives; a runaway chain that truncates every tick is ended by the
  // watchdog, after which the queue empties and reporting resumes.
  if PumpJobs then
    FlushPendingRejections;
end;

procedure TGittanExtEngine.NoteRejection(key: UInt64; const msg: string);
var
  i: integer;
begin
  for i := 0 to High(FPendingRejections) do
    if FPendingRejections[i].Key = key then
    begin
      FPendingRejections[i].Msg := msg;
      Exit;
    end;
  SetLength(FPendingRejections, Length(FPendingRejections) + 1);
  FPendingRejections[High(FPendingRejections)].Key := key;
  FPendingRejections[High(FPendingRejections)].Msg := msg;
end;

procedure TGittanExtEngine.NoteRejectionHandled(key: UInt64);
var
  i, j: integer;
begin
  for i := 0 to High(FPendingRejections) do
    if FPendingRejections[i].Key = key then
    begin
      for j := i to High(FPendingRejections) - 1 do
        FPendingRejections[j] := FPendingRejections[j + 1];
      SetLength(FPendingRejections, Length(FPendingRejections) - 1);
      Exit;
    end;
end;

{** The list is detached before alerting: the modal alert pumps messages,
    which re-enters OnJSTimer and would otherwise report entries twice. }
procedure TGittanExtEngine.FlushPendingRejections;
var
  pending: array of TPendingRejection;
  i: integer;
begin
  if Length(FPendingRejections) = 0 then
    Exit;
  pending := FPendingRejections;
  FPendingRejections := nil;
  for i := 0 to High(pending) do
    if pending[i].Msg <> '' then
      alert('Unhandled Promise rejection: ' + pending[i].Msg)
    else
      alert('Unhandled Promise rejection: [no error message]');
end;

{** Runs the extensions' timers that are due. The ids are taken first: a
    callback may clear or set timers, so each is looked up again. }
procedure TGittanExtEngine.RunDueTimers;
var
  Due: array of integer;
  TickNow: QWord;
  i, idx: integer;
begin
  if (not Assigned(FJSTimers)) or (FInTimerCallback > 0) then
    Exit;
  TickNow := GetTickCount64;
  Due := nil;
  for i := 0 to FJSTimers.Count - 1 do
    if (FJSTimers.Data[i] <> nil) and (FJSTimers.Data[i]^.Due <= TickNow) then
    begin
      SetLength(Due, Length(Due) + 1);
      Due[High(Due)] := FJSTimers.Keys[i];
    end;
  for i := 0 to High(Due) do
  begin
    if IsExtShuttingDown or IsGlobalShutdown then
      Exit;
    idx := FJSTimers.IndexOf(Due[i]);
    if (idx >= 0) and (FJSTimers.Data[idx]^.Due <= TickNow) then
      FireTimer(FJSTimers.Data[idx]);
  end;
end;

{** Free retired timers parked by FireTimer / JSClearTimer.
    Skipped while a timer callback is on the stack: a nested message pump
    (e.g. a modal dialog opened from JS) must not free the very timer whose
    OnTimer frame is still live. }
procedure TGittanExtEngine.DrainDeadTimers;
var
  info: PJSTimerInfo;
begin
  if (not Assigned(FDeadTimers)) or (FInTimerCallback > 0) then
    Exit;
  while FDeadTimers.Count > 0 do
  begin
    info := FDeadTimers[0];
    FDeadTimers.Delete(0);
    DisposeTimerInfo(info);
  end;
end;

{** Helper: does a specific context expose @code(FuncName) as a callable? }
function ContextHasFunction(ctx: JSContext; const FuncName: string): boolean;
var
  Func: JSValue;
begin
  if ctx = nil then Exit(false);
  // GetValue hands back an owned reference on success; this runs once per
  // extension per broadcast, so dropping it leaked the function object (and
  // every object it closes over) on every glucose update.
  if not ctx^.GetValue(pchar(FuncName), func) then
    Exit(false);
  try
    // IsFunction, not IsObject: the callers all require a callable and a
    // non-callable global of the same name would otherwise report true here
    // and then be silently skipped at the call itself.
    Result := JS_IsFunction(ctx, func);
  finally
    JS_FreeValue(ctx, func);
  end;
end;

{** Determine whether a global function exists and is callable.

    With Path B isolation, user scripts live in per-extension contexts. This
    method returns true if @i(any) loaded extension context exposes the function.
    When no extensions are loaded it falls back to the admin/template context
    (FContext) so engine-internal/test paths continue to work. }
function TGittanExtEngine.FunctionExists(const FuncName: string): boolean;
var
  i: integer;
begin
  if IsExtShuttingDown or (FRuntime = nil) then
    Exit(false);

  if Assigned(FExtContexts) and (FExtContexts.Count > 0) then
  begin
    for i := 0 to FExtContexts.Count - 1 do
      if (FExtContexts[i] <> nil) and ContextHasFunction(FExtContexts[i]^.Ctx, FuncName) then
        Exit(true);
    Exit(false);
  end;

  // Legacy fallback when no per-extension contexts are loaded.
  Result := ContextHasFunction(FContext, FuncName);
end;

{******************************************************************************
  Events and commands
******************************************************************************}

function TGittanExtEngine.ParseJsonIn(ctx: JSContext; const Json: string): JSValue;
var
  glob, jsonObj, parseFn, text: JSValue;
begin
  Result := JS_UNDEFINED;
  if ctx = nil then
    Exit;
  glob := JS_GetGlobalObject(ctx);
  jsonObj := JS_GetPropertyStr(ctx, glob, 'JSON');
  parseFn := JS_GetPropertyStr(ctx, jsonObj, 'parse');
  text := JS_NewString(ctx, RawUtf8(Json));
  try
    Result := JS_Call(ctx, parseFn, jsonObj, 1, @text);
    if JS_IsException(Result) then
    begin
      DumpJSError(ctx);
      Result := JS_UNDEFINED;
    end;
  finally
    JS_FreeValue(ctx, text);
    JS_FreeValue(ctx, parseFn);
    JS_FreeValue(ctx, jsonObj);
    JS_FreeValue(ctx, glob);
  end;
end;

{ What a listener's return value says: false, a string or {cancel: true,
  message} cancel the event. }
function ReadCancel(ctx: JSContext; const ret: JSValue; out AMessage: string): boolean;
var
  prop: JSValue;
  err: RawUtf8;
begin
  Result := False;
  AMessage := '';
  if ret.tag = JS_TAG_BOOL then
    Result := JS_ToBool(ctx, ret) = 0
  else if JS_IsString(ret) then
  begin
    Result := True;
    AMessage := string(JS_ToUtf8(ctx, ret));
  end
  else if JS_IsObject(ret) and not JS_IsFunction(ctx, ret) then
  begin
    prop := JS_GetPropertyStr(ctx, ret, 'cancel');
    Result := (not JS_IsUndefined(prop)) and (JS_ToBool(ctx, prop) = 1);
    JS_FreeValue(ctx, prop);
    if Result then
    begin
      prop := JS_GetPropertyStr(ctx, ret, 'message');
      if JS_IsString(prop) then
        AMessage := string(JS_ToUtf8(ctx, prop));
      JS_FreeValue(ctx, prop);
    end;
  end;
  { A getter of cancel or message that threw cancels nothing, as a
    listener that throws does, and its exception is taken off the
    context, where the next call into it would have met it. }
  if JS_HasException(ctx) then
  begin
    ctx^.DumpError(err);
    Result := False;
    AMessage := '';
  end;
end;

{ What a listener without the data permission gets of a payload: the
  fields that say what happened, none of the repository's content (the
  files, the message, the commits, the root). }
function ContentFreePayload(const AJson: string): string;
const
  Kept: array[0..3] of string = ('ok', 'kind', 'mode', 'amend');
var
  Data: TJSONData;
  Reduced: TJSONObject;
  Key: string;
begin
  Result := '{}';
  try
    Data := GetJSON(AJson);
  except
    Exit;
  end;
  try
    if not (Data is TJSONObject) then
      Exit;
    Reduced := TJSONObject.Create;
    try
      for Key in Kept do
        if TJSONObject(Data).Find(Key) <> nil then
          Reduced.Add(Key, TJSONObject(Data).Find(Key).Clone);
      Result := Reduced.AsJSON;
    finally
      Reduced.Free;
    end;
  finally
    Data.Free;
  end;
end;

function TGittanExtEngine.GrantedForContext(ctx: JSContext): TExtPermSet;
var
  i: integer;
begin
  Result := [];
  if Assigned(FExtContexts) then
    for i := 0 to FExtContexts.Count - 1 do
      if (FExtContexts[i] <> nil) and (FExtContexts[i]^.Ctx = ctx) then
        Exit(FExtContexts[i]^.Granted);
end;

{ Whether the extension of AExt runs for the repository at ARoot with
  the remotes ARemoteUrls: its @repos, then its @forges against the
  forge of the remotes, which is looked for only when it has @forges. }
function InScope(AExt: PExtContextInfo; const ARoot, ARemoteUrls: string): boolean;
var
  Forge: TGittanForgeClass;
  Name: string;
begin
  Result := ExtRepoInScope(AExt^.Repos, ARoot, ARemoteUrls);
  if not Result or (Length(AExt^.Forges) = 0) then
    Exit;
  Forge := ForgeClassFor(ARemoteUrls);
  if Forge <> nil then
    Name := Forge.Name
  else
    Name := '';
  Result := ExtForgeInScope(AExt^.Forges, Name);
end;

function TGittanExtEngine.ContextInScope(ctx: JSContext;
  const ARoot, ARemoteUrls: string): boolean;
var
  i: integer;
begin
  Result := False;
  if Assigned(FExtContexts) then
    for i := 0 to FExtContexts.Count - 1 do
      if (FExtContexts[i] <> nil) and (FExtContexts[i]^.Ctx = ctx) then
        Exit(InScope(FExtContexts[i], ARoot, ARemoteUrls));
end;

function TGittanExtEngine.ExtInScope(const AExtId, ARoot, ARemoteUrls: string): boolean;
var
  i: integer;
begin
  Result := False;
  if Assigned(FExtContexts) then
    for i := 0 to FExtContexts.Count - 1 do
      if (FExtContexts[i] <> nil) and (FExtContexts[i]^.ExtId = AExtId) then
        Exit(InScope(FExtContexts[i], ARoot, ARemoteUrls));
end;

function TGittanExtEngine.ExtForgeInScope(const AExtId, AForgeName: string): boolean;
var
  i: integer;
begin
  Result := False;
  if Assigned(FExtContexts) then
    for i := 0 to FExtContexts.Count - 1 do
      if (FExtContexts[i] <> nil) and (FExtContexts[i]^.ExtId = AExtId) then
        Exit(gittan.ext.perm.ExtForgeInScope(FExtContexts[i]^.Forges, AForgeName));
end;

function TGittanExtEngine.Listens(const AEvent, ARoot, ARemoteUrls: string): boolean;
var
  i: integer;
begin
  Result := False;
  if FRegistry = nil then
    Exit;
  for i := 0 to FRegistry.ListenerCount - 1 do
    if (FRegistry.Listener(i).Event = AEvent) and
      ContextInScope(FRegistry.Listener(i).Ctx, ARoot, ARemoteUrls) then
      Exit(True);
end;

function TGittanExtEngine.Fire(const AEvent, APayloadJson: string;
  out ACancelMessage: string): boolean;
begin
  Result := FireIn(AEvent, APayloadJson, False, '', '', ACancelMessage);
end;

function TGittanExtEngine.Fire(const AEvent, APayloadJson, ARoot, ARemoteUrls: string;
  out ACancelMessage: string): boolean;
begin
  Result := FireIn(AEvent, APayloadJson, True, ARoot, ARemoteUrls, ACancelMessage);
end;

function TGittanExtEngine.FireIn(const AEvent, APayloadJson: string; AScoped: boolean;
  const ARoot, ARemoteUrls: string; out ACancelMessage: string): boolean;
var
  Listeners: TGittanExtListeners;
  i: integer;
  arg, ret: JSValue;
  Msg, Reduced: string;
begin
  Result := True;
  ACancelMessage := '';
  Reduced := '';
  if IsExtShuttingDown or (FRuntime = nil) or (FRegistry = nil) then
    Exit;
  // A listener may add or remove listeners as it runs, so the list is
  // copied and each function held while it is called.
  Listeners := FRegistry.ListenersOf(AEvent);
  for i := 0 to High(Listeners) do
    Listeners[i].Func := JS_DupValue(Listeners[i].Ctx, Listeners[i].Func);
  try
    for i := 0 to High(Listeners) do
    begin
      if IsExtShuttingDown then
        Break;
      if AScoped and not ContextInScope(Listeners[i].Ctx, ARoot, ARemoteUrls) then
        Continue;
      if epData in GrantedForContext(Listeners[i].Ctx) then
        arg := ParseJsonIn(Listeners[i].Ctx, APayloadJson)
      else
      begin
        if Reduced = '' then
          Reduced := ContentFreePayload(APayloadJson);
        arg := ParseJsonIn(Listeners[i].Ctx, Reduced);
      end;
      ret := JS_Call(Listeners[i].Ctx, Listeners[i].Func, JS_UNDEFINED, 1, @arg);
      if JS_IsException(ret) then
        DumpJSError(Listeners[i].Ctx)
      else if ReadCancel(Listeners[i].Ctx, ret, Msg) and Result then
      begin
        Result := False;
        ACancelMessage := Msg;
      end;
      JS_FreeValue(Listeners[i].Ctx, ret);
      JS_FreeValue(Listeners[i].Ctx, arg);
    end;
  finally
    for i := 0 to High(Listeners) do
      JS_FreeValue(Listeners[i].Ctx, Listeners[i].Func);
  end;
  PumpJobs;
end;

procedure TGittanExtEngine.Emit(const AEvent, APayloadJson: string);
var
  Msg: string;
begin
  Fire(AEvent, APayloadJson, Msg);
end;

function TGittanExtEngine.RunCommand(const AKey, AContextJson: string): boolean;
var
  Cmd: TGittanExtCommand;
  Func, arg, ret: JSValue;
begin
  Result := False;
  if IsExtShuttingDown or (FRuntime = nil) or (FRegistry = nil) then
    Exit;
  if not FRegistry.FindCommand(AKey, Cmd) then
    Exit;
  Result := True;
  Func := JS_DupValue(Cmd.Ctx, Cmd.Func);
  try
    arg := ParseJsonIn(Cmd.Ctx, AContextJson);
    ret := JS_Call(Cmd.Ctx, Func, JS_UNDEFINED, 1, @arg);
    if JS_IsException(ret) then
      DumpJSError(Cmd.Ctx);
    JS_FreeValue(Cmd.Ctx, ret);
    JS_FreeValue(Cmd.Ctx, arg);
  finally
    JS_FreeValue(Cmd.Ctx, Func);
  end;
  PumpJobs;
end;

{******************************************************************************
  Singleton management
******************************************************************************}

{** Retrieve or lazily create the singleton engine instance. }
class function TGittanExtEngine.Instance: TGittanExtEngine;
begin
  // Don't create new instances during shutdown
  if IsExtShuttingDown then
  begin
    Result := nil;
    Exit;
  end;

  if FInstance = nil then
    FInstance := TGittanExtEngine.Create;
  Result := FInstance;
end;

class function TGittanExtEngine.HasInstance: boolean;
begin
  Result := FInstance <> nil;
end;

class function TGittanExtEngine.Existing: TGittanExtEngine;
begin
  if IsExtShuttingDown then
    Exit(nil);
  Result := FInstance;
end;

{** Release the singleton engine instance. }
class procedure TGittanExtEngine.ReleaseInstance;
begin
  // Signal shutdown first to prevent recreation
  SetExtShuttingDown(true);

  // Only free if instance exists (safe for multiple calls)
  if FInstance <> nil then
  try
    FreeAndNil(FInstance);
  except
      // Ignore any errors during shutdown cleanup
      // The OS will clean up remaining resources anyway
  end;
end;

end.
