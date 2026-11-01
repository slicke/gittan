unit gittan.ext.api;

{** What an extension can do in Gittan: the natives of the Gittan class
  that read a repository, run git and other programs, make HTTP
  requests, keep an extension's own values, declare its settings and
  put cards, messages and files in the window, and the JS facade over
  them (Gittan.repo, Gittan.git, Gittan.exec, Gittan.net, Gittan.ui,
  Gittan.storage, Gittan.settings, Gittan.app). RegisterGittanApi puts
  them in an extension's context as it is provisioned
  (TGittanExtLoader.OnProvision), each gated by the permission group it
  needs (gittan.ext.perm): data for the repository, exec for git and
  programs, net for HTTP, ui for the window, settings for Gittan's own.
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
  gittan.ext.functions, gittan.ext.perm, gittan.ext.host, gittan.ext.registry,
  gittan.ext.promise, gittan.http, gittan.textfile, gittan.reviews, gittan.forge;

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
    function HttpRequestCb(const ctx: PJSContext; const func: string;
      const params: JSParameters; out res: JSValueVal): boolean;
  end;

var
  Api: TGittanExtApi;
  ApiSettings: TGittanSettings;

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
  else
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
  Data: RawByteString;
begin
  Repo := RepoArg(res, ctx, argc, argv);
  if Repo = nil then
    Exit;
  if Repo.FileBlob(Arg(ctx, argc, argv, 1), Arg(ctx, argc, argv, 2), Data) then
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
  if Repo.Blame(Arg(ctx, argc, argv, 1), Arg(ctx, argc, argv, 2), Output) then
    ReturnString(res, ctx, Output);
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

{ A key goes into gittan.ini as it is, so one that would start a line,
  a section or a pair of its own (ValidExtKey) is refused with an error
  the extension can read, in the getters too, so a typo shows at once. }
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
      if Def.Key = '' then
        Continue;
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
          if ApiSettings.ForgeCliPath(Forge.Name) <> '' then
            ReturnString(res, ctx, ApiSettings.ForgeCliPath(Forge.Name))
          else
            ReturnString(res, ctx, FindTool(Forge.CliName));
        end;
  end;
end;

{ ---------------------------------------------------------------------------
  The window: Gittan._notify, _status, _openFile, _addCard, _clearCards
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
    ExtHost.AddCard(ExtHost.ActiveRoot, Card);
  finally
    Data.Free;
  end;
end;

procedure JSClearCards(res: PJSValue; ctx: JSContext; this_val: PJSValue;
  argc: integer; argv: PJSValues; magic: integer);
begin
  res^ := JS_UNDEFINED;
  ExtHost.ClearCards('', ExtIdOf(ctx));
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

function TGittanExtApi.GitRun(const ctx: PJSContext; const func: string;
  const params: JSParameters; out res: JSValueVal): boolean;
var
  Root, Output, Error: string;
  Args: TStringArray;
  Ok: boolean;
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
  Ok := RunGitEnv(Root, Args, [], Output, Error, '', nil, nil, ParamStr(params, 2));
  if Ok then
    res := StringToValueVal(RunJson(True, 0, Output, Error))
  else
    res := StringToValueVal(RunJson(False, 1, Output, Error));
  Result := True;
end;

function TGittanExtApi.ExecRun(const ctx: PJSContext; const func: string;
  const params: JSParameters; out res: JSValueVal): boolean;
var
  Cmd, Exe, Dir, Output, Error: string;
  Args: TStringArray;
  Ok: boolean;
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
  Ok := RunCli(Exe, Dir, Args, [], Output, Error, ParamStr(params, 3));
  if Ok then
    res := StringToValueVal(RunJson(True, 0, Output, Error))
  else
    res := StringToValueVal(RunJson(False, 1, Output, Error));
  Result := True;
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
    '  var J = function (s) { return s === undefined ? undefined : JSON.parse(s); };' + LineEnding +
    '  var R = function (o) { return (o && o.repo) ? String(o.repo) : t._root(); };' + LineEnding +
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
    '  if (typeof gitRun === "function") {' + LineEnding +
    '    var gitRunF = globalThis.gitRun, execRunF = globalThis.execRun;' + LineEnding +
    '    delete globalThis.gitRun; delete globalThis.execRun;' + LineEnding +
    '    var A = function (a) { return JSON.stringify((a || []).map(String)); };' + LineEnding +
    '    t.git = { run: function (args, o) { return gitRunF(R(o), A(args), String((o && o.input) || "")).then(J); } };' + LineEnding +
    '    t.exec = { run: function (cmd, args, o) { return execRunF(String(cmd), A(args), String((o && o.cwd) || R(o)), String((o && o.input) || "")).then(J); } };' + LineEnding +
    '    t.gh = { run: function (args, o) { var gh = has("_appSetting") ? t._appSetting("GitHubCli") : "gh"; return t.exec.run(gh || "gh", args, o); } };' + LineEnding +
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
    '    notify: function (title, detail) { t._notify(String(title), String(detail === undefined ? "" : detail), false); },' + LineEnding +
    '    error: function (title, detail) { t._notify(String(title), String(detail === undefined ? "" : detail), true); },' + LineEnding +
    '    setStatus: function (text, seconds) { t._status(String(text), seconds === undefined ? 6 : Number(seconds)); },' + LineEnding +
    '    clearStatus: function () { t._status("", 0); },' + LineEnding +
    '    openFile: function (path, line) { t._openFile(String(path), line === undefined ? 0 : Number(line)); },' + LineEnding +
    '    addCard: function (card) { t._addCard(JSON.stringify(card || {})); },' + LineEnding +
    '    clearCards: function () { t._clearCards(); }' + LineEnding +
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
    addClassFunctionIf(epUI, '_status', @JSStatus, 2);
    addClassFunctionIf(epUI, '_openFile', @JSOpenFile, 2);
    addClassFunctionIf(epUI, '_addCard', @JSAddCard, 1);
    addClassFunctionIf(epUI, '_clearCards', @JSClearCards, 0);
    { On the promise thread: strings in, JSON out, nothing of the
      window touched. }
    AddPromiseIf(epExec, 'gitRun', @Api.GitRun, 2, 3, True);
    AddPromiseIf(epExec, 'execRun', @Api.ExecRun, 2, 4, True);
    AddPromiseIf(epNet, 'httpRequest', @Api.HttpRequestCb, 4, 5, True);
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
    ExecuteInCurrent(API_FACADE_1 + ExtId + API_FACADE_2 + Perms + API_FACADE_3,
      '<gittan api>');
  end;
end;

finalization
  FreeAndNil(Api);
end.
