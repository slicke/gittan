unit gittan.ext.api;

{** What an extension can do in Gittan: the natives of the Gittan class
  that read a repository, run git and other programs, make HTTP
  requests, keep an extension's own values, declare its settings and
  put cards, messages and files in the window, and the JS facade over
  them (Gittan.repo, Gittan.git, Gittan.exec, Gittan.forge, Gittan.forges,
  Gittan.net, Gittan.ui, Gittan.storage, Gittan.settings, Gittan.app).
  RegisterGittanApi puts them in an extension's context as it is
  provisioned (TGittanExtLoader.OnProvision), each gated by the
  permission group it needs (gittan.ext.perm): data for the repository,
  exec for git and programs, forge for the forge's tool, net for HTTP,
  ui for the window, settings for Gittan's own.
  The reads run on the main thread against the window's repository
  (ExtHost.RepoFor); the extension's own values and its settings page
  are every extension's (ui); git, programs and HTTP run on the promise thread
  with nothing but strings, so the window is never touched off its
  thread. Every answer crosses as JSON text, which the facade parses in
  the extension's own context. No LCL. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, gittan.ext.engine, gittan.ext.quickjs, gittan.git,
  gittan.settings;

{** Registers the natives and the facade in AExt's context; called between
  the engine's BeginRegistration and EndRegistration. ASettings keeps the
  extensions' values and grants. }
procedure RegisterGittanApi(AEngine: TGittanExtEngine; AExt: PExtContextInfo;
  ASettings: TGittanSettings);

{** A snapshot as the events and Gittan.repo.snapshot() give it. The
  caller frees it. }
function SnapshotJson(const ASnap: TGittanRepoSnapshot): TJSONObject;
{** The changed files as Gittan.repo.files() gives them. }
function FileStatsJson(const AStats: TGittanFileStats): TJSONArray;
{** The lines of AList as a JSON array. }
function ListJson(AList: TStrings): TJSONArray;
{** A commit as the lists give it. }
function CommitJson(const ACommit: TGittanCommitLine): TJSONObject;

implementation

uses
  {$IF DEFINED(UNIX) OR DEFINED(HAIKU)}BaseUnix,{$ENDIF}
  gittan.ext.functions, gittan.ext.perm, gittan.ext.host, gittan.ext.registry,
  gittan.ext.promise, gittan.ext.modules, gittan.http, gittan.textfile, gittan.reviews,
  gittan.forge;

const
  ApiVersion = '1.0';
  ChangeKindName: array[TGittanChangeKind] of string =
    ('modified', 'added', 'deleted', 'renamed', 'untracked', 'conflict');

type
  { The promise callbacks, which run on the promise thread. }
  TGittanExtApi = class
  public
    function GitRun(const ctx: PJSContext; const func: string;
      const params: JSParameters; out res: JSValueVal): boolean;
    function ExecRun(const ctx: PJSContext; const func: string;
      const params: JSParameters; out res: JSValueVal): boolean;
    function ForgeRun(const ctx: PJSContext; const func: string;
      const params: JSParameters; out res: JSValueVal): boolean;
    function HttpRequestCb(const ctx: PJSContext; const func: string;
      const params: JSParameters; out res: JSValueVal): boolean;
    function RepoRead(const ctx: PJSContext; const func: string;
      const params: JSParameters; out res: JSValueVal): boolean;
  end;

var
  Api: TGittanExtApi;
  ApiSettings: TGittanSettings;
  { The tool of each forge as _forgeInfo found it on the main thread,
    "name=path", for forgeRun on the promise thread, which may not read
    the settings while the main thread changes them. }
  ForgeCliSeen: TStringList;
  ForgeCliLock: TRTLCriticalSection;

{ ---------------------------------------------------------------------------
  JSON of the repository's records
  --------------------------------------------------------------------------- }

function TimeJson(ATime: TDateTime): TJSONData;
begin
  if ATime = 0 then
    Result := TJSONNull.Create
  else
    Result := TJSONString.Create(FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"Z"', ATime));
end;

function CommitJson(const ACommit: TGittanCommitLine): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('hash', ACommit.Hash);
  Result.Add('short', ACommit.Short);
  Result.Add('subject', ACommit.Subject);
  Result.Add('author', ACommit.Author);
  Result.Add('date', TimeJson(ACommit.Date));
  Result.Add('unpushed', ACommit.Unpushed);
end;

function CommitsJson(const ACommits: TGittanCommitLines): TJSONArray;
var
  C: TGittanCommitLine;
begin
  Result := TJSONArray.Create;
  for C in ACommits do
    Result.Add(CommitJson(C));
end;

function FileStatsJson(const AStats: TGittanFileStats): TJSONArray;
var
  S: TGittanFileStat;
  O: TJSONObject;
begin
  Result := TJSONArray.Create;
  for S in AStats do
  begin
    O := TJSONObject.Create;
    O.Add('path', S.Path);
    O.Add('kind', ChangeKindName[S.Kind]);
    O.Add('added', S.Added);
    O.Add('deleted', S.Deleted);
    O.Add('binary', S.Binary);
    O.Add('staged', S.Staged);
    O.Add('unstaged', S.Unstaged);
    Result.Add(O);
  end;
end;

function StashesJson(const AStashes: TGittanStashes): TJSONArray;
var
  S: TGittanStash;
  O: TJSONObject;
begin
  Result := TJSONArray.Create;
  for S in AStashes do
  begin
    O := TJSONObject.Create;
    O.Add('id', S.Id);
    O.Add('index', S.Index);
    O.Add('branch', S.Branch);
    O.Add('message', S.Message);
    O.Add('time', S.Time);
    O.Add('untracked', S.Untracked);
    Result.Add(O);
  end;
end;

function TagsJson(const ATags: TGittanTags): TJSONArray;
var
  T: TGittanTag;
  O: TJSONObject;
begin
  Result := TJSONArray.Create;
  for T in ATags do
  begin
    O := TJSONObject.Create;
    O.Add('name', T.Name);
    O.Add('commit', T.Commit);
    O.Add('annotated', T.Annotated);
    O.Add('time', T.Time);
    O.Add('subject', T.Subject);
    Result.Add(O);
  end;
end;

function StringsJson(const AList: TStringArray): TJSONArray;
var
  S: string;
begin
  Result := TJSONArray.Create;
  for S in AList do
    Result.Add(S);
end;

function ListJson(AList: TStrings): TJSONArray;
var
  S: string;
begin
  Result := TJSONArray.Create;
  for S in AList do
    Result.Add(S);
end;

function SnapshotJson(const ASnap: TGittanRepoSnapshot): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('ok', ASnap.Ok);
  Result.Add('error', ASnap.Error);
  Result.Add('branch', ASnap.Branch);
  Result.Add('defaultBranch', ASnap.DefaultBranch);
  Result.Add('detached', ASnap.Detached);
  Result.Add('head', ASnap.Head);
  Result.Add('hasUpstream', ASnap.HasUpstream);
  Result.Add('ahead', ASnap.Ahead);
  Result.Add('behind', ASnap.Behind);
  Result.Add('operation', ASnap.Operation);
  Result.Add('rebaseBranch', ASnap.RebaseBranch);
  Result.Add('rewritten', ASnap.Rewritten);
  Result.Add('files', FileStatsJson(ASnap.Stats));
  Result.Add('stashes', StashesJson(ASnap.Stashes));
  Result.Add('recent', CommitsJson(ASnap.Recent));
  Result.Add('refs', StringsJson(ASnap.Refs));
end;

{ ---------------------------------------------------------------------------
  Helpers for the natives
  --------------------------------------------------------------------------- }

function Arg(ctx: JSContext; argc: integer; argv: PJSValues; AIndex: integer): string;
begin
  if (AIndex < argc) and not JS_IsUndefined(argv^[AIndex]) and not JS_IsNull(argv^[AIndex]) then
    Result := string(ctx^.ToUtf8(argv^[AIndex]))
  else
    Result := '';
end;

function ArgInt(ctx: JSContext; argc: integer; argv: PJSValues; AIndex, ADefault: integer): integer;
var
  n: longint;
begin
  Result := ADefault;
  if (AIndex < argc) and (JS_ToInt32(ctx, n, argv^[AIndex]) = 0) then
    Result := n;
end;

procedure ReturnJson(res: PJSValue; ctx: JSContext; AJson: TJSONData);
begin
  try
    res^ := JS_NewString(ctx, RawUtf8(AJson.AsJSON));
  finally
    AJson.Free;
  end;
end;

procedure ReturnString(res: PJSValue; ctx: JSContext; const AText: string);
begin
  res^ := JS_NewString(ctx, RawUtf8(AText));
end;

{ The repository at the root an argument names, the shown one for '';
  nil, and the result undefined, when none is open. }
function RepoArg(res: PJSValue; ctx: JSContext; argc: integer; argv: PJSValues): TGittanRepo;
var
  Root: string;
begin
  res^ := JS_UNDEFINED;
  Root := Arg(ctx, argc, argv, 0);
  if Root = '' then
    Root := ExtHost.ActiveRoot;
  Result := ExtHost.RepoFor(Root);
end;

function EngineOf(ctx: JSContext): TGittanExtEngine;
begin
  Result := TGittanExtEngine(JS_GetContextOpaque(ctx));
end;

function ExtIdOf(ctx: JSContext): string;
var
  Eng: TGittanExtEngine;
begin
  Result := '';
  Eng := EngineOf(ctx);
  if Eng <> nil then
    Result := Eng.ExtensionIdForContext(ctx);
end;

{ ---------------------------------------------------------------------------
  The data natives: Gittan._root, _snapshot, _files, _diff, _fileText,
  _blame, _commit, _branches, _tags, _stashes, _remotes, _recent
  --------------------------------------------------------------------------- }

procedure JSRoot(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
begin
  ReturnString(res, ctx, ExtHost.ActiveRoot);
end;

procedure JSSnapshot(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Repo: TGittanRepo;
  Snap: TGittanRepoSnapshot;
begin
  Repo := RepoArg(res, ctx, argc, argv);
  if Repo = nil then
    Exit;
  Repo.Snapshot(Snap);
  ReturnJson(res, ctx, SnapshotJson(Snap));
end;

procedure JSFiles(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Root: string;
begin
  res^ := JS_UNDEFINED;
  Root := Arg(ctx, argc, argv, 0);
  if Root = '' then
    Root := ExtHost.ActiveRoot;
  if ExtHost.RepoFor(Root) = nil then
    Exit;
  ReturnJson(res, ctx, FileStatsJson(ExtHost.StatsFor(Root)));
end;

{ Does APath, relative to the repository, name a file inside it? The data
  grant covers the repository, not the files around it. In the work tree
  (no ARef) a link on the way could lead out of it, so none may be there;
  at a commit git gives a link's own text. }
function InsideRepo(ARepo: TGittanRepo; const APath, ARef: string): boolean;
var
  Root, Full: string;
begin
  Root := IncludeTrailingPathDelimiter(ExpandFileName(ARepo.Root));
  Full := ExpandFileName(Root + SetDirSeparators(APath));
  if FileNameCaseSensitive then
    Result := Copy(Full, 1, Length(Root)) = Root
  else
    Result := SameText(Copy(Full, 1, Length(Root)), Root);
  { No "..": ExpandFileName takes link/../secret for <root>/secret, the
    path the link check sees, while the file read is link/../secret,
    which the system resolves past the link. Both separators, since the
    path comes from an extension and Windows takes either. }
  Result := Result and (APath <> '') and
    (Pos('/../', '/' + StringReplace(APath, '\', '/', [rfReplaceAll]) + '/') = 0) and
    ((ARef <> '') or not PathHasLinkBelowRoot(Root, Full));
end;

procedure JSDiff(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Repo: TGittanRepo;
  Path: string;
  Lines: TStringList;
begin
  Repo := RepoArg(res, ctx, argc, argv);
  if Repo = nil then
    Exit;
  Path := Arg(ctx, argc, argv, 1);
  if Path = '' then
    ReturnString(res, ctx, Repo.Diff)
  else if InsideRepo(Repo, Path, '') then
  begin
    Lines := TStringList.Create;
    try
      if Repo.FileChanges(Path, Lines) then
        ReturnString(res, ctx, Lines.Text);
    finally
      Lines.Free;
    end;
  end;
end;

procedure JSFileText(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Repo: TGittanRepo;
  Path: string;
  Data: RawByteString;
begin
  Repo := RepoArg(res, ctx, argc, argv);
  if Repo = nil then
    Exit;
  Path := Arg(ctx, argc, argv, 1);
  if not InsideRepo(Repo, Path, Arg(ctx, argc, argv, 2)) then
    Exit;
  if Repo.FileBlob(Path, Arg(ctx, argc, argv, 2), Data) then
    ReturnString(res, ctx, string(Data));
end;

procedure JSBlame(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Repo: TGittanRepo;
  Output: string;
begin
  Repo := RepoArg(res, ctx, argc, argv);
  if Repo = nil then
    Exit;
  { Blame without a ref reads the work tree's file, as the diff of an
    unchanged or new file does: a link may not lead out of it. }
  if InsideRepo(Repo, Arg(ctx, argc, argv, 1), Arg(ctx, argc, argv, 2)) and
    Repo.Blame(Arg(ctx, argc, argv, 1), Arg(ctx, argc, argv, 2), Output) then
    ReturnString(res, ctx, Output);
end;

{ What the comparison of the repository at a root is, for repoRead's
  thread, which reads it in a repository of its own: root, git folder,
  Base, whole tree, whitespace. }
procedure JSRepoState(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Repo: TGittanRepo;
begin
  Repo := RepoArg(res, ctx, argc, argv);
  if Repo = nil then
    Exit;
  ReturnJson(res, ctx, TJSONObject.Create(['root', Repo.Root, 'gitDir', Repo.GitDir,
    'base', Repo.Base, 'whole', Repo.WholeTree, 'ws', Repo.IgnoreWhitespace]));
end;

procedure JSCommit(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Repo: TGittanRepo;
  Line: TGittanCommitLine;
  Body: string;
  O: TJSONObject;
begin
  Repo := RepoArg(res, ctx, argc, argv);
  if Repo = nil then
    Exit;
  if Repo.CommitDetails(Arg(ctx, argc, argv, 1), Line, Body) then
  begin
    O := CommitJson(Line);
    O.Add('body', Body);
    ReturnJson(res, ctx, O);
  end;
end;

procedure JSBranches(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Repo: TGittanRepo;
  Local, Remote: TStringList;
  O: TJSONObject;
begin
  Repo := RepoArg(res, ctx, argc, argv);
  if Repo = nil then
    Exit;
  Local := TStringList.Create;
  Remote := TStringList.Create;
  try
    if Repo.Branches(Local, Remote) then
    begin
      O := TJSONObject.Create;
      O.Add('local', ListJson(Local));
      O.Add('remote', ListJson(Remote));
      ReturnJson(res, ctx, O);
    end;
  finally
    Remote.Free;
    Local.Free;
  end;
end;

procedure JSTags(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Repo: TGittanRepo;
  Tags: TGittanTags;
begin
  Repo := RepoArg(res, ctx, argc, argv);
  if Repo = nil then
    Exit;
  if Repo.Tags(Tags) then
    ReturnJson(res, ctx, TagsJson(Tags));
end;

procedure JSStashes(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Repo: TGittanRepo;
  Stashes: TGittanStashes;
begin
  Repo := RepoArg(res, ctx, argc, argv);
  if Repo = nil then
    Exit;
  if Repo.Stashes(Stashes) then
    ReturnJson(res, ctx, StashesJson(Stashes));
end;

procedure JSRemotes(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Repo: TGittanRepo;
  List: TStringList;
begin
  Repo := RepoArg(res, ctx, argc, argv);
  if Repo = nil then
    Exit;
  List := TStringList.Create;
  try
    if Repo.Remotes(List) then
      ReturnJson(res, ctx, ListJson(List));
  finally
    List.Free;
  end;
end;

procedure JSRecent(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Repo: TGittanRepo;
  Commits: TGittanCommitLines;
  Max: integer;
begin
  Repo := RepoArg(res, ctx, argc, argv);
  if Repo = nil then
    Exit;
  Max := ArgInt(ctx, argc, argv, 1, 10);
  if Max <= 0 then
    Max := 10;
  if Repo.RecentCommits(Commits, Max) then
    ReturnJson(res, ctx, CommitsJson(Commits))
  else
    ReturnJson(res, ctx, TJSONArray.Create);
end;

{ ---------------------------------------------------------------------------
  Storage and settings: Gittan._storageGet, _storageSet, _settingsDefine,
  _settingsGet, _appSetting
  --------------------------------------------------------------------------- }

{ A key that ValidExtKey refuses (empty, or with a control character)
  is refused with an error the extension can read, in the getters too,
  so a typo shows at once. }
function CheckExtKey(res: PJSValue; ctx: JSContext; const AWho, AKey: string): boolean;
begin
  Result := ValidExtKey(AKey);
  if not Result then
    res^ := JS_ThrowError(ctx, RawUtf8(AWho + ': ' + Format(rsBadExtKey, [AKey])));
end;

procedure JSStorageGet(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Key, Value: string;
begin
  res^ := JS_NULL;
  if (ApiSettings = nil) or (argc < 1) then
    Exit;
  Key := Arg(ctx, argc, argv, 0);
  if not CheckExtKey(res, ctx, 'Gittan.storage.get', Key) then
    Exit;
  Value := ApiSettings.ExtValue(ExtIdOf(ctx), Key);
  if Value <> '' then
    ReturnString(res, ctx, Value);
end;

procedure JSStorageSet(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Key: string;
begin
  res^ := JS_UNDEFINED;
  if (ApiSettings = nil) or (argc < 1) then
    Exit;
  Key := Arg(ctx, argc, argv, 0);
  if not CheckExtKey(res, ctx, 'Gittan.storage.set', Key) then
    Exit;
  ApiSettings.SetExtValue(ExtIdOf(ctx), Key, Arg(ctx, argc, argv, 1));
end;

function SettingKindOf(const AName: string): TGittanExtSettingKind;
begin
  case LowerCase(AName) of
    'bool', 'boolean', 'switch': Result := skBool;
    'number', 'int', 'integer': Result := skNumber;
    'choice', 'select', 'enum': Result := skChoice;
    else
      Result := skString;
  end;
end;

procedure JSSettingsDefine(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Eng: TGittanExtEngine;
  Data: TJSONData;
  Arr: TJSONArray;
  Item: TJSONObject;
  Def: TGittanExtSettingDef;
  i, j: integer;
  Options: TJSONArray;
begin
  res^ := JS_UNDEFINED;
  Eng := EngineOf(ctx);
  if (Eng = nil) or (argc < 1) then
    Exit;
  try
    Data := GetJSON(Arg(ctx, argc, argv, 0));
  except
    res^ := JS_ThrowError(ctx, 'Gittan.settings.define: a list of {key, type, label, default} is expected');
    Exit;
  end;
  try
    if not (Data is TJSONArray) then
    begin
      res^ := JS_ThrowError(ctx, 'Gittan.settings.define: a list of {key, type, label, default} is expected');
      Exit;
    end;
    Arr := TJSONArray(Data);
    for i := 0 to Arr.Count - 1 do
    begin
      if not (Arr[i] is TJSONObject) then
        Continue;
      Item := TJSONObject(Arr[i]);
      Def := Default(TGittanExtSettingDef);
      Def.ExtId := ExtIdOf(ctx);
      Def.Key := Item.Get('key', '');
      if not CheckExtKey(res, ctx, 'Gittan.settings.define', Def.Key) then
        Exit;
      Def.Kind := SettingKindOf(Item.Get('type', 'string'));
      Def.Caption := Item.Get('label', Def.Key);
      Def.Note := Item.Get('note', '');
      if Item.Find('default') <> nil then
        Def.Default := Item.Find('default').AsString;
      if Item.Find('options') is TJSONArray then
      begin
        Options := TJSONArray(Item.Find('options'));
        SetLength(Def.Options, Options.Count);
        for j := 0 to Options.Count - 1 do
          Def.Options[j] := Options[j].AsString;
      end;
      Eng.Registry.AddSetting(Def);
    end;
  finally
    Data.Free;
  end;
end;

procedure JSSettingsGet(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Eng: TGittanExtEngine;
  Key, Value: string;
  Defs: TGittanExtSettingDefs;
  Def: TGittanExtSettingDef;
begin
  res^ := JS_NULL;
  Eng := EngineOf(ctx);
  if (Eng = nil) or (argc < 1) then
    Exit;
  Key := Arg(ctx, argc, argv, 0);
  if not CheckExtKey(res, ctx, 'Gittan.settings.get', Key) then
    Exit;
  Value := '';
  if ApiSettings <> nil then
    Value := ApiSettings.ExtValue(ExtIdOf(ctx), Key);
  if Value = '' then
  begin
    Defs := Eng.Registry.SettingsOf(ExtIdOf(ctx));
    for Def in Defs do
      if Def.Key = Key then
      begin
        Value := Def.Default;
        Break;
      end;
  end;
  if Value <> '' then
    ReturnString(res, ctx, Value);
end;

procedure JSAppSetting(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Name: string;
  Forge: TGittanForgeClass;
begin
  res^ := JS_NULL;
  if (ApiSettings = nil) or (argc < 1) then
    Exit;
  Name := Arg(ctx, argc, argv, 0);
  case Name of
    'GitPath': ReturnString(res, ctx, GitExe);
    'EditorCommand': ReturnString(res, ctx, ApiSettings.EditorCommand);
    'TerminalCommand': ReturnString(res, ctx, ApiSettings.TerminalCommand);
    'AIEnabled': res^ := JS_NewBool(ctx, ApiSettings.AIEnabled);
    'HostingEnabled': res^ := JS_NewBool(ctx, ApiSettings.HostingEnabled);
    'ExtensionsDir': ReturnString(res, ctx, ApiSettings.ExtensionsDir);
    else
      for Forge in RegisteredForges do
        if Name = Forge.Name + 'Cli' then
        begin
          { The tool whether hosting is on or not, as the settings name
            it. }
          ReturnString(res, ctx, ForgeTool(Forge, True, ApiSettings.ForgeCliPath(Forge.Name)));
        end;
  end;
end;

{ ---------------------------------------------------------------------------
  The forge: Gittan._forgeInfo
  --------------------------------------------------------------------------- }

{ The registered forge named AName, without regard to case; nil for
  none. }
function ForgeNamed(const AName: string): TGittanForgeClass;
var
  Forge: TGittanForgeClass;
begin
  for Forge in RegisteredForges do
    if SameText(Forge.Name, AName) then
      Exit(Forge);
  Result := nil;
end;

{ The tool of AForge as the forge features use it (ForgeTool, as
  App.ForgeCli): '' while hosting is off or it is not found. On the
  main thread, as it reads the settings. }
function ForgeCliOf(AForge: TGittanForgeClass): string;
begin
  if AForge = nil then
    Result := ''
  else if ApiSettings = nil then
    Result := ForgeTool(AForge, True, '')
  else
    Result := ForgeTool(AForge, ApiSettings.HostingEnabled, ApiSettings.ForgeCliPath(AForge.Name));
end;

{ Keeps the tool _forgeInfo found for AForge, on the main thread. }
procedure SeeForgeCli(const AForge, ACli: string);
begin
  EnterCriticalSection(ForgeCliLock);
  try
    ForgeCliSeen.Values[AForge] := ACli;
  finally
    LeaveCriticalSection(ForgeCliLock);
  end;
end;

{ The tool _forgeInfo last found for AForge, on any thread; '' for none. }
function SeenForgeCli(const AForge: string): string;
begin
  EnterCriticalSection(ForgeCliLock);
  try
    Result := ForgeCliSeen.Values[AForge];
  finally
    LeaveCriticalSection(ForgeCliLock);
  end;
end;

{ The forge of the repository at ARoot, by its remotes; nil when they
  are on none. }
function ForgeOfRoot(const ARoot: string): TGittanForgeClass;
begin
  Result := nil;
  if (ARoot <> '') and DirectoryExists(ARoot) then
    Result := ForgeClassFor(ResolvedRemoteUrlsIn(ARoot));
end;

{ _forgeInfo(root, forge): the forge Gittan.forge acts on, the one
  named, else the repository's at root, else the forge view's while it
  is shown, else the shown repository's; undefined for none. Its name,
  its tool, whether it can run (ready, else why not), the accounts its
  tool is logged in to, and the folder the tool runs in: the
  repository's, '' (the home folder) for the forge view's. }
procedure JSForgeInfo(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Root, Named, Cwd, Cli: string;
  Forge: TGittanForgeClass;
  O, A: TJSONObject;
  Accounts: TJSONArray;
  Account: TGittanForgeAccount;
begin
  res^ := JS_UNDEFINED;
  Root := Arg(ctx, argc, argv, 0);
  Named := Arg(ctx, argc, argv, 1);
  Cwd := '';
  if Named <> '' then
  begin
    Forge := ForgeNamed(Named);
    if Root <> '' then
      Cwd := Root;
  end
  else if Root <> '' then
  begin
    Forge := ForgeOfRoot(Root);
    Cwd := Root;
  end
  else if ExtHost.ForgeViewForge <> '' then
    Forge := ForgeNamed(ExtHost.ForgeViewForge)
  else
  begin
    Cwd := ExtHost.ActiveRoot;
    Forge := ForgeOfRoot(Cwd);
  end;
  if Forge = nil then
    Exit;
  Cli := ForgeCliOf(Forge);
  SeeForgeCli(Forge.Name, Cli);
  O := TJSONObject.Create;
  O.Add('name', Forge.Name);
  O.Add('tool', Forge.CliName);
  O.Add('ready', Cli <> '');
  if Cli = '' then
    if (ApiSettings <> nil) and not ApiSettings.HostingEnabled then
      O.Add('reason', Forge.Name + ' is turned off in the settings')
    else if (ApiSettings <> nil) and (ApiSettings.ForgeCliPath(Forge.Name) <> '') then
      O.Add('reason', ApiSettings.ForgeCliPath(Forge.Name) + ' was not found')
    else
      O.Add('reason', Forge.CliName + ' was not found');
  O.Add('cwd', Cwd);
  Accounts := TJSONArray.Create;
  for Account in Forge.Accounts do
  begin
    A := TJSONObject.Create;
    A.Add('host', Account.Host);
    A.Add('login', Account.Login);
    A.Add('active', Account.Active);
    Accounts.Add(A);
  end;
  O.Add('accounts', Accounts);
  ReturnJson(res, ctx, O);
end;

{ ---------------------------------------------------------------------------
  The window: Gittan._notify, _message, _status, _openFile, _addCard, _clearCards
  --------------------------------------------------------------------------- }

procedure JSNotify(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  IsError: boolean;
begin
  res^ := JS_UNDEFINED;
  IsError := (argc > 2) and (JS_ToBool(ctx, argv^[2]) = 1);
  ExtHost.Notify(ExtHost.ActiveRoot, Arg(ctx, argc, argv, 0), Arg(ctx, argc, argv, 1), IsError);
end;

procedure JSStatus(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
begin
  res^ := JS_UNDEFINED;
  ExtHost.SetStatus(ExtHost.ActiveRoot, Arg(ctx, argc, argv, 0), ArgInt(ctx, argc, argv, 1, 6));
end;

procedure JSOpenFile(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
begin
  res^ := JS_UNDEFINED;
  ExtHost.OpenFile(ExtHost.ActiveRoot, Arg(ctx, argc, argv, 0), ArgInt(ctx, argc, argv, 1, 0));
end;

procedure JSAddCard(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Eng: TGittanExtEngine;
  Data: TJSONData;
  O: TJSONObject;
  Card: TGittanReviewThread;
begin
  res^ := JS_UNDEFINED;
  Eng := EngineOf(ctx);
  if (Eng = nil) or (argc < 1) then
    Exit;
  try
    Data := GetJSON(Arg(ctx, argc, argv, 0));
  except
    res^ := JS_ThrowError(ctx, 'Gittan.ui.addCard: {path, line, text} is expected');
    Exit;
  end;
  try
    if not (Data is TJSONObject) then
    begin
      res^ := JS_ThrowError(ctx, 'Gittan.ui.addCard: {path, line, text} is expected');
      Exit;
    end;
    O := TJSONObject(Data);
    Card := Default(TGittanReviewThread);
    Card.Path := O.Get('path', '');
    Card.Line := O.Get('line', 0);
    Card.OriginalLine := Card.Line;
    Card.LeftSide := O.Get('side', 'new') = 'old';
    Card.Severity := O.Get('severity', '');
    Card.Extension := Eng.ExtensionIdForContext(ctx);
    Card.Agent := Eng.ExtensionNameForContext(ctx);
    SetLength(Card.Comments, 1);
    Card.Comments[0].Author := Card.Agent;
    Card.Comments[0].Body := O.Get('text', '');
    Card.Comments[0].Created := Now;
    if O.Get('title', '') <> '' then
      Card.Comments[0].Body := '**' + O.Get('title', '') + '**' + LineEnding +
        LineEnding + Card.Comments[0].Body;
    if (Card.Path = '') or (Card.Comments[0].Body = '') then
    begin
      res^ := JS_ThrowError(ctx, 'Gittan.ui.addCard: a path and a text are needed');
      Exit;
    end;
    { The repository the card was made for, a command's ctx.repo, so it
      does not land in another one shown since; else the shown one. }
    if O.Get('repo', '') <> '' then
      ExtHost.AddCard(O.Get('repo', ''), Card)
    else
      ExtHost.AddCard(ExtHost.ActiveRoot, Card);
  finally
    Data.Free;
  end;
end;

{ Gittan.ui.message({title, text, kind, buttons, default, cancel}): the
  dialog's button pressed, by its index; -1 when closed without one.
  The shape is checked here, so an extension learns of a mistake from
  an exception rather than from a dialog that looks wrong. }
const
  MessageMaxButtons = 6;
  { A button's label, so six of them stay within a screen. }
  MessageMaxLabel = 40;

procedure JSMessage(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
var
  Eng: TGittanExtEngine;
  Data: TJSONData;
  O: TJSONObject;
  List: TJSONArray;
  Buttons: array of string;
  Kind: TExtMessageKind;
  KindName, Title, Text: string;
  i, k, n, Default, Cancel: integer;

  procedure Fail(const AWhy: string);
  begin
    res^ := JS_ThrowError(ctx, 'Gittan.ui.message: ' + AWhy);
  end;

  { AMin is 0 for default, which a button always is, -1 for cancel,
    which may be none. }
  function IndexOf(const AKey: string; ADefault, AMin: integer; out AIndex: integer): boolean;
  var
    V: TJSONData;
    Count: integer;
  begin
    Count := Length(Buttons);
    if Count = 0 then
      Count := 1; { OK alone }
    V := O.Find(AKey);
    if (V = nil) or (V.JSONType = jtNull) then
    begin
      AIndex := ADefault;
      Exit(True);
    end;
    Result := (V.JSONType = jtNumber) and (Frac(V.AsFloat) = 0) and
      (V.AsFloat >= AMin) and (V.AsFloat < Count);
    if Result then
      AIndex := V.AsInteger
    else if AMin < 0 then
      Fail(AKey + ' is the index of a button, or -1')
    else
      Fail(AKey + ' is the index of a button');
  end;

begin
  res^ := JS_NewInt32(ctx, -1);
  Eng := EngineOf(ctx);
  if Eng = nil then
    Exit;
  try
    Data := GetJSON(Arg(ctx, argc, argv, 0));
  except
    Fail('{text, title?, kind?, buttons?} is expected');
    Exit;
  end;
  try
    if not (Data is TJSONObject) then
    begin
      Fail('{text, title?, kind?, buttons?} is expected');
      Exit;
    end;
    O := TJSONObject(Data);
    Title := O.Get('title', '');
    Text := O.Get('text', '');
    if (Title = '') and (Text = '') then
    begin
      Fail('a text or a title is needed');
      Exit;
    end;
    KindName := LowerCase(O.Get('kind', 'info'));
    case KindName of
      'info', '': Kind := emkInfo;
      'warn', 'warning': Kind := emkWarning;
      'error': Kind := emkError;
      'question': Kind := emkQuestion;
    else
      Fail('kind is "info", "warn", "error" or "question"');
      Exit;
    end;
    Buttons := nil;
    if (O.Find('buttons') <> nil) and (O.Find('buttons').JSONType <> jtNull) then
    begin
      if not (O.Find('buttons') is TJSONArray) then
      begin
        Fail('buttons is an array of labels');
        Exit;
      end;
      List := TJSONArray(O.Find('buttons'));
      if List.Count > MessageMaxButtons then
      begin
        Fail(Format('no more than %d buttons', [MessageMaxButtons]));
        Exit;
      end;
      SetLength(Buttons, List.Count);
      for i := 0 to List.Count - 1 do
      begin
        if List[i].JSONType = jtString then
          Buttons[i] := Trim(List[i].AsString)
        else
          Buttons[i] := '';
        if Buttons[i] = '' then
        begin
          Fail('a button''s label is a text that is not empty');
          Exit;
        end;
        { Characters, not bytes: a UTF-8 continuation byte is no new one. }
        n := 0;
        for k := 1 to Length(Buttons[i]) do
          if (Ord(Buttons[i][k]) and $C0) <> $80 then
            Inc(n);
        if n > MessageMaxLabel then
        begin
          Fail(Format('a button''s label is no longer than %d characters', [MessageMaxLabel]));
          Exit;
        end;
        { AskDlg would take these for its flags, not a caption. }
        if SameText(Buttons[i], 'IsDefault') or SameText(Buttons[i], 'IsCancel') or
          SameText(Buttons[i], 'NoCancel') then
        begin
          Fail('"' + Buttons[i] + '" cannot be a button''s label');
          Exit;
        end;
      end;
    end;
    if not IndexOf('default', 0, 0, Default) or not IndexOf('cancel', -1, -1, Cancel) then
      Exit;
    res^ := JS_NewInt32(ctx, ExtHost.Message(Eng.ExtensionNameForContext(ctx),
      Title, Text, Kind, Buttons, Default, Cancel));
  finally
    Data.Free;
  end;
end;

procedure JSClearCards(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
begin
  res^ := JS_UNDEFINED;
  ExtHost.ClearCards(Arg(ctx, argc, argv, 0), ExtIdOf(ctx));
end;

{ ---------------------------------------------------------------------------
  The promises, on their thread: gitRun, execRun, httpRequest
  --------------------------------------------------------------------------- }

function ParamStr(const params: JSParameters; AIndex: integer): string;
begin
  if (AIndex < params.Count) and (params[AIndex]^.match(JD_STR)) then
    Result := params[AIndex]^.Data.StrVal
  else if AIndex < params.Count then
    Result := params[AIndex]^.stringify
  else
    Result := '';
end;

{ A JSON array of strings as arguments; False for anything else. }
function ArgsOf(const AJson: string; out AArgs: TStringArray): boolean;
var
  Data: TJSONData;
  i: integer;
begin
  Result := False;
  AArgs := nil;
  if AJson = '' then
    Exit(True);
  try
    Data := GetJSON(AJson);
  except
    Exit;
  end;
  try
    if not (Data is TJSONArray) then
      Exit;
    SetLength(AArgs, Data.Count);
    for i := 0 to Data.Count - 1 do
      AArgs[i] := Data.Items[i].AsString;
    Result := True;
  finally
    Data.Free;
  end;
end;

function RunJson(AOk: boolean; AStatus: integer; const AOut, AErr: string): string;
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  try
    O.Add('ok', AOk);
    O.Add('status', AStatus);
    O.Add('stdout', AOut);
    O.Add('stderr', AErr);
    Result := O.AsJSON;
  finally
    O.Free;
  end;
end;

{ Runs a tool and gives git.run's and exec.run's result: its exit code,
  128 and the signal when one ended it (as a shell says), -1 when it did
  not start. RunTool gives the raw wait status on Unix. }
function ToolJson(const AExe, ADir: string; const AArgs, ASkip, AEnv: array of string;
  const AInput: string): string;
var
  Output, Error: string;
  Status: integer;
begin
  if not RunTool(AExe, ADir, AArgs, ASkip, AEnv, Output, Error, Status, nil, AInput) then
  begin
    Status := -1;
    if Error = '' then
      Error := 'Could not run ' + AExe;
  end
  {$IF DEFINED(UNIX) OR DEFINED(HAIKU)}
  else if wifexited(Status) then
    Status := wexitstatus(Status)
  else if wifsignaled(Status) then
    Status := 128 + wtermsig(Status)
  {$ENDIF};
  Result := RunJson(Status = 0, Status, Output, Error);
end;

function TGittanExtApi.GitRun(const ctx: PJSContext; const func: string;
  const params: JSParameters; out res: JSValueVal): boolean;
var
  Root: string;
  Args, GitArgs: TStringArray;
  i: integer;
begin
  Result := False;
  Root := ParamStr(params, 0);
  if (Root = '') or not DirectoryExists(Root) then
  begin
    res := StringToValueVal('Gittan.git.run: no repository');
    Exit;
  end;
  if not ArgsOf(ParamStr(params, 1), Args) then
  begin
    res := StringToValueVal('Gittan.git.run: the arguments are a list of strings');
    Exit;
  end;
  { RunTool, not RunGitEnv, for git's own exit status and streams; the
    options and variables are RunGitEnv's. }
  SetLength(GitArgs, 4 + Length(Args));
  GitArgs[0] := '-c';
  GitArgs[1] := 'core.quotepath=false';
  GitArgs[2] := '-c';
  GitArgs[3] := 'diff.suppressBlankEmpty=false';
  for i := 0 to High(Args) do
    GitArgs[4 + i] := Args[i];
  res := StringToValueVal(ToolJson(GitExe, Root, GitArgs, ['GIT_INDEX_FILE='],
    ['LC_ALL=C', 'GIT_TERMINAL_PROMPT=0', 'GIT_OPTIONAL_LOCKS=0'], ParamStr(params, 2)));
  Result := True;
end;

function TGittanExtApi.ExecRun(const ctx: PJSContext; const func: string;
  const params: JSParameters; out res: JSValueVal): boolean;
var
  Cmd, Exe, Dir: string;
  Args: TStringArray;
begin
  Result := False;
  Cmd := ParamStr(params, 0);
  if Cmd = '' then
  begin
    res := StringToValueVal('Gittan.exec.run: a command is expected');
    Exit;
  end;
  if not ArgsOf(ParamStr(params, 1), Args) then
  begin
    res := StringToValueVal('Gittan.exec.run: the arguments are a list of strings');
    Exit;
  end;
  if (Pos(PathDelim, Cmd) > 0) or (Pos('/', Cmd) > 0) then
    Exe := Cmd
  else
  begin
    Exe := FindTool(Cmd);
    if Exe = '' then
    begin
      res := StringToValueVal('Gittan.exec.run: ' + Cmd + ' was not found');
      Exit;
    end;
  end;
  Dir := ParamStr(params, 2);
  if Dir = '' then
    Dir := GetCurrentDir;
  res := StringToValueVal(ToolJson(Exe, Dir, Args, [], [], ParamStr(params, 3)));
  Result := True;
end;

{ forgeRun(forge, args, cwd, input) on the promise thread: the tool of
  the forge named, as _forgeInfo found it on the main thread just
  before (the facade asks it first), so nothing but a forge's tool
  runs, and only with the arguments the forge allows (CliAllows), with
  its environment (CliEnv), in cwd or the home folder. }
function TGittanExtApi.ForgeRun(const ctx: PJSContext; const func: string;
  const params: JSParameters; out res: JSValueVal): boolean;
var
  Forge: TGittanForgeClass;
  Exe, Dir, Reason: string;
  Args: TStringArray;
begin
  Result := False;
  Forge := ForgeNamed(ParamStr(params, 0));
  if Forge = nil then
  begin
    res := StringToValueVal('Gittan.forge.cli: no forge');
    Exit;
  end;
  if not ArgsOf(ParamStr(params, 1), Args) then
  begin
    res := StringToValueVal('Gittan.forge.cli: the arguments are a list of strings');
    Exit;
  end;
  if not Forge.CliAllows(Args, Reason) then
  begin
    res := StringToValueVal('Gittan.forge.cli: ' + Reason);
    Exit;
  end;
  Exe := SeenForgeCli(Forge.Name);
  if (Exe = '') or not FileExists(Exe) then
  begin
    res := StringToValueVal('Gittan.forge.cli: ' + Forge.Name +
      ' is turned off or ' + Forge.CliName + ' was not found');
    Exit;
  end;
  { The home folder only when no folder is asked for: one that is gone
    is refused rather than the tool run elsewhere. }
  Dir := ParamStr(params, 2);
  if Dir = '' then
    Dir := ExcludeTrailingPathDelimiter(GetUserDir)
  else if not DirectoryExists(Dir) then
  begin
    res := StringToValueVal('Gittan.forge.cli: ' + Dir + ' is not a folder');
    Exit;
  end;
  res := StringToValueVal(ToolJson(Exe, Dir, Args, [], Forge.CliEnv, ParamStr(params, 3)));
  Result := True;
end;

{ Gittan.repo.diffAsync, blameAsync and fileTextAsync on the promise
  thread: params are the state JSRepoState gave, the kind, the path and the
  ref. A repository of its own with that comparison, so nothing of the
  window's is touched; {"value": text} or {"value": null} for nothing. }
function TGittanExtApi.RepoRead(const ctx: PJSContext; const func: string;
  const params: JSParameters; out res: JSValueVal): boolean;
var
  State: TJSONData;
  O, Envelope: TJSONObject;
  Repo: TGittanRepo;
  Kind, Path, Ref, Text: string;
  Data: RawByteString;
  Lines: TStringList;
  Got: boolean;
begin
  Result := False;
  try
    State := GetJSON(ParamStr(params, 0));
  except
    State := nil;
  end;
  if not (State is TJSONObject) then
  begin
    State.Free;
    res := StringToValueVal('Gittan.repo: no repository');
    Exit;
  end;
  Kind := ParamStr(params, 1);
  Path := ParamStr(params, 2);
  Ref := ParamStr(params, 3);
  O := TJSONObject(State);
  Repo := TGittanRepo.Create;
  try
    Repo.OpenAt(O.Get('root', ''), O.Get('gitDir', ''));
    Repo.Base := O.Get('base', '');
    Repo.WholeTree := O.Get('whole', False);
    Repo.IgnoreWhitespace := O.Get('ws', False);
    Got := False;
    Text := '';
    if Kind = 'diff' then
    begin
      if Path = '' then
      begin
        Text := Repo.Diff;
        Got := True;
      end
      else if InsideRepo(Repo, Path, '') then
      begin
        Lines := TStringList.Create;
        try
          Got := Repo.FileChanges(Path, Lines);
          Text := Lines.Text;
        finally
          Lines.Free;
        end;
      end;
    end
    else if Kind = 'blame' then
      Got := InsideRepo(Repo, Path, Ref) and Repo.Blame(Path, Ref, Text)
    else if Kind = 'fileText' then
    begin
      Got := InsideRepo(Repo, Path, Ref) and Repo.FileBlob(Path, Ref, Data);
      Text := string(Data);
    end;
    Envelope := TJSONObject.Create;
    try
      if Got then
        Envelope.Add('value', Text)
      else
        Envelope.Add('value', TJSONNull.Create);
      res := StringToValueVal(Envelope.AsJSON);
    finally
      Envelope.Free;
    end;
    Result := True;
  finally
    Repo.Free;
    State.Free;
  end;
end;

function TGittanExtApi.HttpRequestCb(const ctx: PJSContext; const func: string;
  const params: JSParameters; out res: JSValueVal): boolean;
var
  Method, Url, HeadersJson, Body: string;
  Headers: TStringArray;
  Data: TJSONData;
  i, TimeoutMs: integer;
  Response: TGittanHttpResponse;
  Envelope: TJSONObject;
begin
  Result := False;
  Method := UpperCase(ParamStr(params, 0));
  Url := ParamStr(params, 1);
  HeadersJson := ParamStr(params, 2);
  Body := ParamStr(params, 3);
  TimeoutMs := 0;
  if params.Count > 4 then
    TimeoutMs := Round(params[4]^.floatify);
  if (Method = '') or (Url = '') then
  begin
    res := StringToValueVal('fetch: a method and a URL are expected');
    Exit;
  end;
  Headers := nil;
  if (HeadersJson <> '') and (HeadersJson <> '{}') then
  try
    Data := GetJSON(HeadersJson);
    try
      if Data is TJSONObject then
      begin
        SetLength(Headers, Data.Count);
        for i := 0 to Data.Count - 1 do
          Headers[i] := TJSONObject(Data).Names[i] + ': ' + Data.Items[i].AsString;
      end;
    finally
      Data.Free;
    end;
  except
    res := StringToValueVal('fetch: invalid headers');
    Exit;
  end;
  if TimeoutMs > 0 then
    Response := HttpRequest(Method, Url, Headers, Body, (TimeoutMs + 999) div 1000)
  else
    Response := HttpRequest(Method, Url, Headers, Body);
  if Response.Status = 0 then
  begin
    res := StringToValueVal('fetch: ' + Response.Error);
    Exit;
  end;
  Envelope := TJSONObject.Create;
  try
    Envelope.Add('status', Response.Status);
    Envelope.Add('url', Url);
    Envelope.Add('redirected', False);
    Envelope.Add('headers', TJSONObject.Create);
    Envelope.Add('body', Response.Body);
    res := StringToValueVal(Envelope.AsJSON);
  finally
    Envelope.Free;
  end;
  Result := True;
end;

{ ---------------------------------------------------------------------------
  Registration and the facade
  --------------------------------------------------------------------------- }

const
  {** The JS-side fetch() over the threaded httpRequest promise, from
      Trndi: fetch(url, init) with init's method, headers, body and timeout
      resolves to a Response-like object with status, ok, url, headers,
      text() and json(). }
  FETCH_SHIM: string =
    '(function () {' + LineEnding +
    '  if (typeof httpRequest !== "function" || typeof globalThis.fetch === "function")' + LineEnding +
    '    return;' + LineEnding +
    '  var request = globalThis.httpRequest;' + LineEnding +
    '  function makeHeaders(obj) {' + LineEnding +
    '    var lower = {};' + LineEnding +
    '    for (var k in obj) lower[k.toLowerCase()] = obj[k];' + LineEnding +
    '    return {' + LineEnding +
    '      get: function (n) { var v = lower[String(n).toLowerCase()]; return v === undefined ? null : v; },' + LineEnding +
    '      has: function (n) { return String(n).toLowerCase() in lower; },' + LineEnding +
    '      keys: function () { return Object.keys(lower); }' + LineEnding +
    '    };' + LineEnding +
    '  }' + LineEnding +
    '  globalThis.fetch = function (url, init) {' + LineEnding +
    '    init = init || {};' + LineEnding +
    '    var method = String(init.method || "GET").toUpperCase();' + LineEnding +
    '    var body = (init.body === undefined || init.body === null) ? "" : String(init.body);' + LineEnding +
    '    var timeout = 0;' + LineEnding +
    '    if (init.timeout !== undefined) {' + LineEnding +
    '      timeout = Number(init.timeout);' + LineEnding +
    '      if (!isFinite(timeout) || timeout < 0)' + LineEnding +
    '        throw new TypeError("fetch: timeout must be a non-negative number of milliseconds");' + LineEnding +
    '      timeout = Math.floor(timeout);' + LineEnding +
    '    }' + LineEnding +
    '    var hdrs = {}, hasCT = false;' + LineEnding +
    '    if (init.headers)' + LineEnding +
    '      for (var k in init.headers) {' + LineEnding +
    '        hdrs[k] = String(init.headers[k]);' + LineEnding +
    '        if (k.toLowerCase() === "content-type") hasCT = true;' + LineEnding +
    '      }' + LineEnding +
    '    if (body !== "" && !hasCT) hdrs["Content-Type"] = "text/plain;charset=UTF-8";' + LineEnding +
    '    return request(method, String(url), JSON.stringify(hdrs), body, timeout).then(' + LineEnding +
    '      function (raw) {' + LineEnding +
    '        var r = JSON.parse(raw);' + LineEnding +
    '        return {' + LineEnding +
    '          status: r.status,' + LineEnding +
    '          ok: r.status >= 200 && r.status < 300,' + LineEnding +
    '          url: r.url,' + LineEnding +
    '          redirected: r.redirected,' + LineEnding +
    '          headers: makeHeaders(r.headers),' + LineEnding +
    '          text: function () { return Promise.resolve(r.body); },' + LineEnding +
    '          json: function () {' + LineEnding +
    '            try { return Promise.resolve(JSON.parse(r.body)); }' + LineEnding +
    '            catch (e) { return Promise.reject(e); }' + LineEnding +
    '          }' + LineEnding +
    '        };' + LineEnding +
    '      },' + LineEnding +
    '      function (err) { throw new TypeError(String(err)); }' + LineEnding +
    '    );' + LineEnding +
    '  };' + LineEnding +
    '})();';

  {** Gittan.* over the natives. The natives that are missing (a
      permission not granted) leave their namespace out, so
      typeof Gittan.git tells an extension what it may do. Every native
      answers JSON text, parsed here. }
  API_FACADE_1: string =
    '(function () {' + LineEnding +
    '  var t = Gittan;' + LineEnding +
    '  var has = function (n) { return typeof t[n] === "function"; };' + LineEnding +
    '  var JP = JSON.parse;' + LineEnding +
    '  var J = function (s) { return s === undefined ? undefined : JP(s); };' + LineEnding +
    '  var R = function (o) { return (o && o.repo) ? String(o.repo) : t._root(); };' + LineEnding +
    '  var A = function (a) { return JSON.stringify((a || []).map(String)); };' + LineEnding +
    '  var FORGES = ';
  API_FACADE_FORGES: string =
    ';' + LineEnding +
    '  var need = function (n) { throw new Error("Gittan permission not granted: " + n + ". Add it to @perms and approve the extension."); };' + LineEnding +
    '  t.api = { version: "' + ApiVersion + '", extensionId: "';
  API_FACADE_2: string =
    '", permissions: [';
  API_FACADE_3: string =
    '] };' + LineEnding +
    '  t.permissions = {' + LineEnding +
    '    has: function (n) { return t.api.permissions.indexOf(String(n)) >= 0; },' + LineEnding +
    '    require: function (n) { if (!this.has(n)) need(n); return true; }' + LineEnding +
    '  };' + LineEnding +
    '  if (has("_snapshot")) t.repo = {' + LineEnding +
    '    root: function (o) { return R(o); },' + LineEnding +
    '    snapshot: function (o) { return J(t._snapshot(R(o))); },' + LineEnding +
    '    files: function (o) { return J(t._files(R(o))); },' + LineEnding +
    '    diff: function (path, o) { return t._diff(R(o), path === undefined ? "" : String(path)); },' + LineEnding +
    '    fileText: function (path, ref, o) { return t._fileText(R(o), String(path), ref === undefined ? "" : String(ref)); },' + LineEnding +
    '    blame: function (path, ref, o) { return t._blame(R(o), String(path), ref === undefined ? "" : String(ref)); },' + LineEnding +
    '    commit: function (hash, o) { return J(t._commit(R(o), String(hash))); },' + LineEnding +
    '    branches: function (o) { return J(t._branches(R(o))); },' + LineEnding +
    '    tags: function (o) { return J(t._tags(R(o))); },' + LineEnding +
    '    stashes: function (o) { return J(t._stashes(R(o))); },' + LineEnding +
    '    remotes: function (o) { return J(t._remotes(R(o))); },' + LineEnding +
    '    recent: function (limit, o) { return J(t._recent(R(o), limit === undefined ? 10 : Number(limit))); }' + LineEnding +
    '  };' + LineEnding +
    '  if (typeof repoRead === "function") {' + LineEnding +
    '    var repoReadF = globalThis.repoRead, repoStateF = t._repoState;' + LineEnding +
    '    delete globalThis.repoRead; delete t._repoState;' + LineEnding +
    '    var RR = function (kind, path, ref, o) {' + LineEnding +
    '      var s = repoStateF(R(o));' + LineEnding +
    '      if (s === undefined) return Promise.resolve(undefined);' + LineEnding +
    '      return repoReadF(s, kind, path === undefined ? "" : String(path), ref === undefined ? "" : String(ref))' + LineEnding +
    '        .then(function (r) { var v = JSON.parse(r).value; return v === null ? undefined : v; });' + LineEnding +
    '    };' + LineEnding +
    '    t.repo.diffAsync = function (path, o) { return RR("diff", path, "", o); };' + LineEnding +
    '    t.repo.blameAsync = function (path, ref, o) { return RR("blame", path, ref, o); };' + LineEnding +
    '    t.repo.fileTextAsync = function (path, ref, o) { return RR("fileText", path, ref, o); };' + LineEnding +
    '  }' + LineEnding +
    '  if (typeof gitRun === "function") {' + LineEnding +
    '    var gitRunF = globalThis.gitRun, execRunF = globalThis.execRun;' + LineEnding +
    '    delete globalThis.gitRun; delete globalThis.execRun;' + LineEnding +
    '    t.git = { run: function (args, o) { return gitRunF(R(o), A(args), String((o && o.input) || "")).then(J); } };' + LineEnding +
    '    t.exec = { run: function (cmd, args, o) { return execRunF(String(cmd), A(args), String((o && o.cwd) || R(o)), String((o && o.input) || "")).then(J); } };' + LineEnding +
    '  }' + LineEnding +
    '  if (has("_forgeInfo") && typeof forgeRun === "function") {' + LineEnding +
    '    var forgeInfoF = t._forgeInfo, forgeRunF = globalThis.forgeRun;' + LineEnding +
    '    delete t._forgeInfo; delete globalThis.forgeRun;' + LineEnding +
    '    var FI = function (o) { return J(forgeInfoF((o && o.repo) ? String(o.repo) : "", (o && o.forge) ? String(o.forge) : "")); };' + LineEnding +
    '    var FR = function (who, want, args, o) {' + LineEnding +
    '      var i = FI(o);' + LineEnding +
    '      var where = (o && o.repo) ? "the repository " + o.repo : "here";' + LineEnding +
    '      if (!i) return Promise.reject(new Error(who + ": " + where + " is on no forge" + (want ? ", not on " + want : "")));' + LineEnding +
    '      if (want && i.name !== want) return Promise.reject(new Error(who + ": " + where + " is on " + i.name + ", not on " + want));' + LineEnding +
    '      if (!i.ready) return Promise.reject(new Error(who + ": " + i.reason));' + LineEnding +
    '      return forgeRunF(i.name, A(args), i.cwd, String((o && o.input) || "")).then(J);' + LineEnding +
    '    };' + LineEnding +
    '    t.forge = {' + LineEnding +
    '      info: function (o) { var i = FI(o); return i ? { name: i.name, cli: i.tool, ready: i.ready, reason: i.reason, accounts: i.accounts } : null; },' + LineEnding +
    '      cli: function (args, o) { return FR("Gittan.forge.cli", "", args, o); }' + LineEnding +
    '    };' + LineEnding +
    '    t.forges = {};' + LineEnding +
    '    FORGES.forEach(function (f) {' + LineEnding +
    '      t.forges[f.cli] = { name: f.name, run: function (args, o) { return FR("Gittan.forges." + f.cli + ".run", f.name, args, o); } };' + LineEnding +
    '    });' + LineEnding +
    '  }' + LineEnding +
    '  if (typeof globalThis.fetch === "function") {' + LineEnding +
    '    var f = globalThis.fetch;' + LineEnding +
    '    t.net = { fetch: function (url, init) { return f(url, init); } };' + LineEnding +
    '    delete globalThis.fetch; delete globalThis.httpRequest;' + LineEnding +
    '  }' + LineEnding +
    '  if (has("_notify")) t.ui = {' + LineEnding +
    '    alert: function () { return t.alert.apply(t, arguments); },' + LineEnding +
    '    confirm: function () { return t.confirm.apply(t, arguments); },' + LineEnding +
    '    prompt: function (caption, text, def) { return t.prompt(String(caption), String(text === undefined ? "" : text), String(def === undefined ? "" : def)); },' + LineEnding +
    '    select: function (caption, text, options) { return Number(t.select.apply(t, [String(caption), String(text)].concat((options || []).map(String)))); },' + LineEnding +
    '    message: function (o) { if (o === null || typeof o !== "object") o = { text: o === undefined ? "" : String(o) }; return t._message(JSON.stringify(o)); },' + LineEnding +
    '    notify: function (title, detail) { t._notify(String(title), String(detail === undefined ? "" : detail), false); },' + LineEnding +
    '    error: function (title, detail) { t._notify(String(title), String(detail === undefined ? "" : detail), true); },' + LineEnding +
    '    setStatus: function (text, seconds) { t._status(String(text), seconds === undefined ? 6 : Number(seconds)); },' + LineEnding +
    '    clearStatus: function () { t._status("", 0); },' + LineEnding +
    '    openFile: function (path, line) { t._openFile(String(path), line === undefined ? 0 : Number(line)); },' + LineEnding +
    '    addCard: function (card) { t._addCard(JSON.stringify(card || {})); },' + LineEnding +
    '    clearCards: function (o) { t._clearCards(o && o.repo ? String(o.repo) : ""); }' + LineEnding +
    '  };' + LineEnding +
    '  if (has("_storageGet")) t.storage = {' + LineEnding +
    '    get: function (k) { return t._storageGet(String(k)); },' + LineEnding +
    '    set: function (k, v) { t._storageSet(String(k), v === undefined || v === null ? "" : String(v)); },' + LineEnding +
    '    remove: function (k) { t._storageSet(String(k), ""); },' + LineEnding +
    '    getJSON: function (k, dflt) { var v = this.get(k); if (v === null || v === "") return dflt === undefined ? null : dflt; try { return JSON.parse(v); } catch (e) { return dflt === undefined ? null : dflt; } },' + LineEnding +
    '    setJSON: function (k, v) { this.set(k, JSON.stringify(v)); }' + LineEnding +
    '  };' + LineEnding +
    '  if (has("_settingsDefine")) t.settings = {' + LineEnding +
    '    define: function (defs) { t._settingsDefine(JSON.stringify(defs || [])); },' + LineEnding +
    '    get: function (k) { return t._settingsGet(String(k)); }' + LineEnding +
    '  };' + LineEnding +
    '  if (has("_appSetting")) t.app = { setting: function (n) { return t._appSetting(String(n)); } };' + LineEnding +
    '})();';

{ The registered forges for the facade, [{"name", "cli"}], so each gets
  Gittan.forges.<its tool>.run (Gittan.forges.gh for GitHub) without
  the facade naming one. }
function ForgesJson: string;
var
  Arr: TJSONArray;
  Forge: TGittanForgeClass;
begin
  Arr := TJSONArray.Create;
  try
    for Forge in RegisteredForges do
      Arr.Add(TJSONObject.Create(['name', Forge.Name, 'cli', Forge.CliName]));
    Result := Arr.AsJSON;
  finally
    Arr.Free;
  end;
end;

procedure RegisterGittanApi(AEngine: TGittanExtEngine; AExt: PExtContextInfo;
  ASettings: TGittanSettings);
var
  ExtId, Perms: string;
  g: TExtPermGroup;
begin
  if (AEngine = nil) or (AExt = nil) then
    Exit;
  ApiSettings := ASettings;
  if Api = nil then
    Api := TGittanExtApi.Create;
  with AEngine do
  begin
    { The shown repository's root is where git.run and exec.run run when
      no repo is named, so exec has it too: git there tells it anyway. }
    if CanRegister(epData) or CanRegister(epExec) then
      addClassFunction('_root', @JSRoot, 0);
    addClassFunctionIf(epData, '_snapshot', @JSSnapshot, 1);
    addClassFunctionIf(epData, '_files', @JSFiles, 1);
    addClassFunctionIf(epData, '_diff', @JSDiff, 2);
    addClassFunctionIf(epData, '_fileText', @JSFileText, 3);
    addClassFunctionIf(epData, '_blame', @JSBlame, 3);
    { Taken into the facade's closure and deleted from Gittan before the
      script runs: the state names the folder repoRead's thread opens, so
      a script may not put its own in its place. }
    addClassFunctionIf(epData, '_repoState', @JSRepoState, 1);
    addClassFunctionIf(epData, '_commit', @JSCommit, 2);
    addClassFunctionIf(epData, '_branches', @JSBranches, 1);
    addClassFunctionIf(epData, '_tags', @JSTags, 1);
    addClassFunctionIf(epData, '_stashes', @JSStashes, 1);
    addClassFunctionIf(epData, '_remotes', @JSRemotes, 1);
    addClassFunctionIf(epData, '_recent', @JSRecent, 2);
    { The extension's own values and settings page touch nothing of the
      repository: every extension has them. }
    addClassFunctionIf(epUI, '_storageGet', @JSStorageGet, 1);
    addClassFunctionIf(epUI, '_storageSet', @JSStorageSet, 2);
    addClassFunctionIf(epUI, '_settingsDefine', @JSSettingsDefine, 1);
    addClassFunctionIf(epUI, '_settingsGet', @JSSettingsGet, 1);
    addClassFunctionIf(epSettings, '_appSetting', @JSAppSetting, 1);
    addClassFunctionIf(epUI, '_notify', @JSNotify, 3);
    addClassFunctionIf(epUI, '_message', @JSMessage, 1);
    addClassFunctionIf(epUI, '_status', @JSStatus, 2);
    addClassFunctionIf(epUI, '_openFile', @JSOpenFile, 2);
    addClassFunctionIf(epUI, '_addCard', @JSAddCard, 1);
    addClassFunctionIf(epUI, '_clearCards', @JSClearCards, 1);
    { On the promise thread: strings in, JSON out, nothing of the
      window touched. }
    AddPromiseIf(epExec, 'gitRun', @Api.GitRun, 2, 3, True);
    AddPromiseIf(epExec, 'execRun', @Api.ExecRun, 2, 4, True);
    { Taken into the facade's closure as repoRead is; it runs nothing but
      a forge's tool anyway. }
    addClassFunctionIf(epForge, '_forgeInfo', @JSForgeInfo, 2);
    AddPromiseIf(epForge, 'forgeRun', @Api.ForgeRun, 2, 4, True);
    AddPromiseIf(epNet, 'httpRequest', @Api.HttpRequestCb, 4, 5, True);
    AddPromiseIf(epData, 'repoRead', @Api.RepoRead, 4, 4, True);
    if CanRegister(epNet) then
      ExecuteInCurrent(FETCH_SHIM, '<fetch shim>');
    { The id and the permissions go into string literals: the id is a
      file's name, so a quote or a backslash in it is escaped. }
    ExtId := StringReplace(CurrentRegistrationExtensionId, '\', '\\', [rfReplaceAll]);
    ExtId := StringReplace(ExtId, '"', '\"', [rfReplaceAll]);
    Perms := '';
    for g := Low(TExtPermGroup) to High(TExtPermGroup) do
      if g in AExt^.Granted then
      begin
        if Perms <> '' then
          Perms := Perms + ', ';
        Perms := Perms + '"' + PermGroupName[g] + '"';
      end;
    ExecuteInCurrent(API_FACADE_1 + ForgesJson + API_FACADE_FORGES + ExtId + API_FACADE_2 +
      Perms + API_FACADE_3,
      '<gittan api>');
  end;
end;

initialization
  InitCriticalSection(ForgeCliLock);
  ForgeCliSeen := TStringList.Create;

finalization
  FreeAndNil(Api);
  FreeAndNil(ForgeCliSeen);
  DoneCriticalSection(ForgeCliLock);
end.
