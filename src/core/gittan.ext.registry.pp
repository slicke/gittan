unit gittan.ext.registry;

{** What the extensions register with the engine (gittan.ext.engine) and
  the window reads: the commands (Gittan.commands.register), which the
  Extensions menu and the popups show, the listeners (Gittan.on) the
  events reach, and the settings an extension declares
  (Gittan.settings.define) for its page of the settings dialog. A
  command and a listener keep the JS function as a value the registry
  owns (JS_DupValue'd), freed when it is removed or when its context is
  unloaded (RemoveContext), always before the context is freed. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.ext.quickjs;

type
  {** Where a command shows: in the Extensions menu (and so in the
    command palette), in the file tree's popup, in the editor's popup,
    in the forge view's Extensions menu; a tab of the forge view
    (Gittan.forgeTabs.register) and an operation of its Batch tab
    (Gittan.batch.register) are kept as commands too, whose function
    answers through Gittan._deliver, and only their own natives make
    them. }
  TGittanExtCommandWhere = (cwMenu, cwFilePopup, cwEditorPopup, cwForge, cwForgeTab, cwBatch);
  TGittanExtCommandWheres = set of TGittanExtCommandWhere;

  TGittanExtCommand = record
    ExtId, Id, Title: string;
    {** What a tab or an operation is for, a line under its title. }
    Note: string;
    Where: TGittanExtCommandWheres;
    Ctx: JSContext;
    Func: JSValue;
  end;
  TGittanExtCommands = array of TGittanExtCommand;

  TGittanExtListener = record
    ExtId, Event: string;
    Ctx: JSContext;
    Func: JSValue;
  end;
  TGittanExtListeners = array of TGittanExtListener;

  {** A setting an extension declares: a switch, a line of text, a number
    or one of Options. }
  TGittanExtSettingKind = (skBool, skString, skNumber, skChoice);

  TGittanExtSettingDef = record
    ExtId, Key, Caption, Default, Note: string;
    Kind: TGittanExtSettingKind;
    Options: TStringArray;
  end;
  TGittanExtSettingDefs = array of TGittanExtSettingDef;

  { TGittanExtRegistry }

  TGittanExtRegistry = class
  private
    FCommands: TGittanExtCommands;
    FListeners: TGittanExtListeners;
    FSettings: TGittanExtSettingDefs;
    procedure DeleteCommand(AIndex: integer);
    procedure DeleteListener(AIndex: integer);
  public
    destructor Destroy; override;
    {** The key the menu items carry: the extension's id and the
      command's, so a command is found again after a reload. }
    class function CommandKey(const AExtId, AId: string): string;
    {** The key of a tab or an operation: kept apart from the commands'
      by a mark, so the same id may be both. }
    class function KindKey(const AExtId, AId: string; AWhere: TGittanExtCommandWhere): string;
    {** The commands, tabs or operations of AWhere, in the order
      added. }
    function CommandsIn(AWhere: TGittanExtCommandWhere): TGittanExtCommands;
    {** Adds a command, replacing one of the same id of the extension
      (whose function is freed); AFunc is owned from here. }
    procedure AddCommand(const AExtId, AId, ATitle: string;
      AWhere: TGittanExtCommandWheres; ACtx: JSContext; const AFunc: JSValue;
      const ANote: string = '');
    {** Removes the command AId of AExtId; with AWhere, only one that is
      in one of those places, so a tab and a command may share an id. }
    function RemoveCommand(const AExtId, AId: string;
      AWhere: TGittanExtCommandWheres = []): boolean;
    function CommandCount: integer;
    function Command(AIndex: integer): TGittanExtCommand;
    function FindCommand(const AKey: string; out ACommand: TGittanExtCommand): boolean;
    {** Adds a listener; AFunc is owned from here. }
    procedure AddListener(const AExtId, AEvent: string; ACtx: JSContext; const AFunc: JSValue);
    {** Removes the listener of ACtx for AEvent whose function is AFunc
      (the same value), freeing it. }
    function RemoveListener(const AEvent: string; ACtx: JSContext; const AFunc: JSValue): boolean;
    function ListenerCount: integer;
    function Listener(AIndex: integer): TGittanExtListener;
    {** The listeners of AEvent, in the order added. }
    function ListenersOf(const AEvent: string): TGittanExtListeners;
    {** Whether AEvent has a listener: a caller asks before it builds a
      payload that costs (a snapshot, a git run). }
    function HasListener(const AEvent: string): boolean;
    {** Keeps a declared setting, replacing one of the same key. }
    procedure AddSetting(const ADef: TGittanExtSettingDef);
    function SettingsOf(const AExtId: string): TGittanExtSettingDefs;
    {** Drops everything of ACtx, freeing its functions. Call before the
      context is freed. }
    procedure RemoveContext(ACtx: JSContext);
    {** Drops the settings declared by AExtId. }
    procedure RemoveSettingsOf(const AExtId: string);
    procedure Clear;
  end;

const
  {** The events an extension may listen to (Gittan.on). }
  GittanExtEvents: array[0..8] of string = ('repo.opened', 'repo.changed',
    'commit.before', 'commit.after', 'push.before', 'push.after', 'pull.before',
    'pull.after', 'unload');

{** Whether AName is one of GittanExtEvents. }
function IsGittanExtEvent(const AName: string): boolean;
{** The events, joined with commas, for a message. }
function GittanExtEventList: string;
{** "menu,file,editor,forge" as a set; an empty or unknown text is the
  menu. }
function ParseCommandWheres(const ACsv: string): TGittanExtCommandWheres;
{** Whether two JS values are the same value (the same object). }
function SameJSValue(const A, B: JSValue): boolean;

implementation

function IsGittanExtEvent(const AName: string): boolean;
var
  Name: string;
begin
  for Name in GittanExtEvents do
    if Name = AName then
      Exit(True);
  Result := False;
end;

function GittanExtEventList: string;
var
  Name: string;
begin
  Result := '';
  for Name in GittanExtEvents do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Name;
  end;
end;

function ParseCommandWheres(const ACsv: string): TGittanExtCommandWheres;
var
  Part: string;
begin
  Result := [];
  for Part in ACsv.Split([',']) do
    case LowerCase(Trim(Part)) of
      'menu': Include(Result, cwMenu);
      'file': Include(Result, cwFilePopup);
      'editor': Include(Result, cwEditorPopup);
      'forge': Include(Result, cwForge);
    end;
  if Result = [] then
    Result := [cwMenu];
end;

function SameJSValue(const A, B: JSValue): boolean;
begin
  Result := CompareMem(@A, @B, SizeOf(JSValue));
end;

{ TGittanExtRegistry }

destructor TGittanExtRegistry.Destroy;
begin
  Clear;
  inherited Destroy;
end;

{ Each kind has its mark, so a command "tab:x" is not the tab x. The keys
  live only while Gittan runs (the menus' Hint, RunCommand); none is kept
  in the settings. }
class function TGittanExtRegistry.CommandKey(const AExtId, AId: string): string;
begin
  Result := AExtId + #9'cmd:' + AId;
end;

class function TGittanExtRegistry.KindKey(const AExtId, AId: string;
  AWhere: TGittanExtCommandWhere): string;
begin
  case AWhere of
    cwForgeTab: Result := AExtId + #9'tab:' + AId;
    cwBatch: Result := AExtId + #9'batch:' + AId;
    else
      Result := CommandKey(AExtId, AId);
  end;
end;

{ The key a command is found by: a tab's and an operation's carry their
  mark. }
function KeyOf(const ACmd: TGittanExtCommand): string;
begin
  if cwForgeTab in ACmd.Where then
    Result := TGittanExtRegistry.KindKey(ACmd.ExtId, ACmd.Id, cwForgeTab)
  else if cwBatch in ACmd.Where then
    Result := TGittanExtRegistry.KindKey(ACmd.ExtId, ACmd.Id, cwBatch)
  else
    Result := TGittanExtRegistry.CommandKey(ACmd.ExtId, ACmd.Id);
end;

{ Whether a tab or an operation is of the same kind as AWhere: a
  command (any of the menus) is replaced by a command, a tab by a tab. }
function SameKind(AA, AB: TGittanExtCommandWheres): boolean;
const
  Own = [cwForgeTab, cwBatch];
begin
  Result := (AA * Own) = (AB * Own);
end;

function TGittanExtRegistry.CommandsIn(AWhere: TGittanExtCommandWhere): TGittanExtCommands;
var
  i, n: integer;
begin
  Result := nil;
  n := 0;
  for i := 0 to High(FCommands) do
    if AWhere in FCommands[i].Where then
    begin
      SetLength(Result, n + 1);
      Result[n] := FCommands[i];
      Inc(n);
    end;
end;

procedure TGittanExtRegistry.DeleteCommand(AIndex: integer);
var
  i: integer;
begin
  if FCommands[AIndex].Ctx <> nil then
    JS_FreeValue(FCommands[AIndex].Ctx, FCommands[AIndex].Func);
  for i := AIndex to High(FCommands) - 1 do
    FCommands[i] := FCommands[i + 1];
  SetLength(FCommands, Length(FCommands) - 1);
end;

procedure TGittanExtRegistry.DeleteListener(AIndex: integer);
var
  i: integer;
begin
  if FListeners[AIndex].Ctx <> nil then
    JS_FreeValue(FListeners[AIndex].Ctx, FListeners[AIndex].Func);
  for i := AIndex to High(FListeners) - 1 do
    FListeners[i] := FListeners[i + 1];
  SetLength(FListeners, Length(FListeners) - 1);
end;

procedure TGittanExtRegistry.AddCommand(const AExtId, AId, ATitle: string;
  AWhere: TGittanExtCommandWheres; ACtx: JSContext; const AFunc: JSValue;
  const ANote: string);
var
  Cmd: TGittanExtCommand;
  i: integer;
begin
  for i := High(FCommands) downto 0 do
    if (FCommands[i].ExtId = AExtId) and (FCommands[i].Id = AId) and
      SameKind(FCommands[i].Where, AWhere) then
      DeleteCommand(i);
  Cmd.ExtId := AExtId;
  Cmd.Id := AId;
  Cmd.Title := ATitle;
  Cmd.Note := ANote;
  Cmd.Where := AWhere;
  Cmd.Ctx := ACtx;
  Cmd.Func := AFunc;
  SetLength(FCommands, Length(FCommands) + 1);
  FCommands[High(FCommands)] := Cmd;
end;

function TGittanExtRegistry.RemoveCommand(const AExtId, AId: string;
  AWhere: TGittanExtCommandWheres): boolean;
var
  i: integer;
begin
  for i := 0 to High(FCommands) do
    if (FCommands[i].ExtId = AExtId) and (FCommands[i].Id = AId) and
      ((AWhere = []) or SameKind(FCommands[i].Where, AWhere)) then
    begin
      DeleteCommand(i);
      Exit(True);
    end;
  Result := False;
end;

function TGittanExtRegistry.CommandCount: integer;
begin
  Result := Length(FCommands);
end;

function TGittanExtRegistry.Command(AIndex: integer): TGittanExtCommand;
begin
  Result := FCommands[AIndex];
end;

function TGittanExtRegistry.FindCommand(const AKey: string;
  out ACommand: TGittanExtCommand): boolean;
var
  i: integer;
begin
  for i := 0 to High(FCommands) do
    if KeyOf(FCommands[i]) = AKey then
    begin
      ACommand := FCommands[i];
      Exit(True);
    end;
  ACommand := Default(TGittanExtCommand);
  Result := False;
end;

procedure TGittanExtRegistry.AddListener(const AExtId, AEvent: string;
  ACtx: JSContext; const AFunc: JSValue);
var
  L: TGittanExtListener;
begin
  L.ExtId := AExtId;
  L.Event := AEvent;
  L.Ctx := ACtx;
  L.Func := AFunc;
  SetLength(FListeners, Length(FListeners) + 1);
  FListeners[High(FListeners)] := L;
end;

function TGittanExtRegistry.RemoveListener(const AEvent: string; ACtx: JSContext;
  const AFunc: JSValue): boolean;
var
  i: integer;
begin
  for i := 0 to High(FListeners) do
    if (FListeners[i].Ctx = ACtx) and (FListeners[i].Event = AEvent) and
      SameJSValue(FListeners[i].Func, AFunc) then
    begin
      DeleteListener(i);
      Exit(True);
    end;
  Result := False;
end;

function TGittanExtRegistry.ListenerCount: integer;
begin
  Result := Length(FListeners);
end;

function TGittanExtRegistry.Listener(AIndex: integer): TGittanExtListener;
begin
  Result := FListeners[AIndex];
end;

function TGittanExtRegistry.ListenersOf(const AEvent: string): TGittanExtListeners;
var
  i, n: integer;
begin
  Result := nil;
  n := 0;
  for i := 0 to High(FListeners) do
    if FListeners[i].Event = AEvent then
    begin
      SetLength(Result, n + 1);
      Result[n] := FListeners[i];
      Inc(n);
    end;
end;

function TGittanExtRegistry.HasListener(const AEvent: string): boolean;
var
  i: integer;
begin
  for i := 0 to High(FListeners) do
    if FListeners[i].Event = AEvent then
      Exit(True);
  Result := False;
end;

procedure TGittanExtRegistry.AddSetting(const ADef: TGittanExtSettingDef);
var
  i: integer;
begin
  for i := 0 to High(FSettings) do
    if (FSettings[i].ExtId = ADef.ExtId) and (FSettings[i].Key = ADef.Key) then
    begin
      FSettings[i] := ADef;
      Exit;
    end;
  SetLength(FSettings, Length(FSettings) + 1);
  FSettings[High(FSettings)] := ADef;
end;

function TGittanExtRegistry.SettingsOf(const AExtId: string): TGittanExtSettingDefs;
var
  i, n: integer;
begin
  Result := nil;
  n := 0;
  for i := 0 to High(FSettings) do
    if FSettings[i].ExtId = AExtId then
    begin
      SetLength(Result, n + 1);
      Result[n] := FSettings[i];
      Inc(n);
    end;
end;

procedure TGittanExtRegistry.RemoveContext(ACtx: JSContext);
var
  i: integer;
begin
  for i := High(FCommands) downto 0 do
    if FCommands[i].Ctx = ACtx then
      DeleteCommand(i);
  for i := High(FListeners) downto 0 do
    if FListeners[i].Ctx = ACtx then
      DeleteListener(i);
end;

procedure TGittanExtRegistry.RemoveSettingsOf(const AExtId: string);
var
  i, j: integer;
begin
  for i := High(FSettings) downto 0 do
    if FSettings[i].ExtId = AExtId then
    begin
      for j := i to High(FSettings) - 1 do
        FSettings[j] := FSettings[j + 1];
      SetLength(FSettings, Length(FSettings) - 1);
    end;
end;

procedure TGittanExtRegistry.Clear;
begin
  while Length(FCommands) > 0 do
    DeleteCommand(High(FCommands));
  while Length(FListeners) > 0 do
    DeleteListener(High(FListeners));
  FSettings := nil;
end;

end.
