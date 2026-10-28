unit gittan.lfslocks;

{** Git LFS's file locks: who holds which file on the LFS server.

  `git lfs locks --verify --json` lists them split into the user's own
  and everyone else's; a server that cannot verify gets the plain list,
  the user's own then the locks this clone made (`--local`). The list
  goes to the network, so TGittanLfsLocksJob reads it on a thread, and
  gives it up when it is stopped.
  Locking and unlocking are TGittanRepo.LfsLock and LfsUnlock, run in
  the remote job. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.git, gittan.job;

type
  {** One lock: its id on the server, the file (from the root, with
    forward slashes, as git names it), who holds it, since when (0 when
    the server did not say), and whether the user does. }
  TGittanLfsLock = record
    Id, Path, Owner: string;
    LockedAt: TDateTime;
    Ours: boolean;
  end;
  TGittanLfsLocks = array of TGittanLfsLock;

  {** Reads the locks of the repository at Root (ReadLfsLocks) on a
    thread; OnDone is raised in the main thread with Locks, or Ok false
    and Error. }
  TGittanLfsLocksJob = class(TGittanJob)
  private
    FRoot, FError: string;
    FOk: boolean;
    FLocks: TGittanLfsLocks;
    function Cancelled: boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: string);
    property Root: string read FRoot;
    property Ok: boolean read FOk;
    property Error: string read FError;
    property Locks: TGittanLfsLocks read FLocks;
  end;

{** The locks git-lfs prints with --json: a list, or with --verify an
  object of "ours" and "theirs" lists, which sets Ours (AVerified: it
  was that object, so Ours is known). False when AJson is neither. }
function ParseLfsLocks(const AJson: string; out ALocks: TGittanLfsLocks;
  out AVerified: boolean): boolean;
function ParseLfsLocks(const AJson: string; out ALocks: TGittanLfsLocks): boolean;
{** The index of the lock on APath in ALocks, -1 when none. }
function LfsLockIndex(const ALocks: TGittanLfsLocks; const APath: string): integer;
{** Sets Ours on each lock of ALocks that ALocal, the locks this clone
  made (`--local`), holds with the same id on the same path: one that
  only shares the path was taken by someone else after the clone's own
  went (a force unlock it has not heard of). }
procedure MarkLocalLocks(var ALocks: TGittanLfsLocks; const ALocal: TGittanLfsLocks);
{** The locks of the repository at ARoot, from its LFS server (see the
  unit). False with git-lfs's reason in AError, and when it is not
  known whose they are (`--local` failed). ACancel, when given, is asked
  as git-lfs runs, and True ends it, with no reason. }
function ReadLfsLocks(const ARoot: string; out ALocks: TGittanLfsLocks;
  out AError: string; ACancel: TGittanCancelEvent = nil): boolean;

implementation

uses
  fpjson, jsonparser, DateUtils;

function ParseLfsLocks(const AJson: string; out ALocks: TGittanLfsLocks;
  out AVerified: boolean): boolean;
var
  Data: TJSONData;

  procedure AddList(AList: TJSONData; AOurs: boolean);
  var
    i: integer;
    Item, Owner: TJSONData;
    Lock: TGittanLfsLock;
  begin
    if not (AList is TJSONArray) then
      Exit;
    for i := 0 to AList.Count - 1 do
    begin
      Item := AList.Items[i];
      if not (Item is TJSONObject) then
        Continue;
      Lock := Default(TGittanLfsLock);
      Lock.Id := TJSONObject(Item).Get('id', '');
      Lock.Path := TJSONObject(Item).Get('path', '');
      Owner := TJSONObject(Item).Find('owner');
      if Owner is TJSONObject then
        Lock.Owner := TJSONObject(Owner).Get('name', '');
      if not TryISO8601ToDate(TJSONObject(Item).Get('locked_at', ''), Lock.LockedAt, True) then
        Lock.LockedAt := 0;
      Lock.Ours := AOurs;
      if Lock.Path <> '' then
        ALocks := Concat(ALocks, [Lock]);
    end;
  end;

begin
  ALocks := nil;
  AVerified := False;
  Result := False;
  try
    Data := GetJSON(AJson);
  except
    Exit;
  end;
  try
    if Data is TJSONArray then
    begin
      AddList(Data, False);
      Result := True;
    end
    else if Data is TJSONObject then
    begin
      AddList(TJSONObject(Data).Find('ours'), True);
      AddList(TJSONObject(Data).Find('theirs'), False);
      AVerified := True;
      Result := True;
    end;
  finally
    Data.Free;
  end;
end;

function ParseLfsLocks(const AJson: string; out ALocks: TGittanLfsLocks): boolean;
var
  Verified: boolean;
begin
  Result := ParseLfsLocks(AJson, ALocks, Verified);
end;

function LfsLockIndex(const ALocks: TGittanLfsLocks; const APath: string): integer;
begin
  for Result := 0 to High(ALocks) do
    if ALocks[Result].Path = APath then
      Exit;
  Result := -1;
end;

procedure MarkLocalLocks(var ALocks: TGittanLfsLocks; const ALocal: TGittanLfsLocks);
var
  i, j: integer;
begin
  for i := 0 to High(ALocks) do
  begin
    ALocks[i].Ours := False;
    for j := 0 to High(ALocal) do
      if (ALocal[j].Id = ALocks[i].Id) and (ALocal[j].Path = ALocks[i].Path) then
      begin
        ALocks[i].Ours := True;
        Break;
      end;
  end;
end;

function ReadLfsLocks(const ARoot: string; out ALocks: TGittanLfsLocks;
  out AError: string; ACancel: TGittanCancelEvent): boolean;
var
  Env: TStringArray;
  Output, Err, VerifyErr: string;
  Local: TGittanLfsLocks;
  Verified: boolean;

  function Cancelled: boolean;
  begin
    Result := Assigned(ACancel) and ACancel();
    if Result then
    begin
      ALocks := nil;
      AError := '';
    end;
  end;

begin
  ALocks := nil;
  AError := '';
  Env := RemoteEnvironmentIn(ARoot);
  { Only the split into ours and theirs says whose each lock is; a
    plain list from --verify is marked below as the one without. }
  if RunGitEnv(ARoot, ['lfs', 'locks', '--verify', '--json'], Env, Output, VerifyErr,
    '', nil, ACancel) and ParseLfsLocks(Output, ALocks, Verified) and Verified then
    Exit(True);
  if Cancelled then
    Exit(False);
  Result := RunGitEnv(ARoot, ['lfs', 'locks', '--json'], Env, Output, Err, '', nil, ACancel) and
    ParseLfsLocks(Output, ALocks);
  if Cancelled then
    Exit(False);
  if not Result then
  begin
    AError := Trim(Err);
    if AError = '' then
      AError := Trim(VerifyErr);
    Exit;
  end;
  { Without the clone's own list every lock would look like another
    user's, and the user's own would get Force Unlock and the commit's
    question: a failure, so what was known stays. }
  Result := RunGitEnv(ARoot, ['lfs', 'locks', '--local', '--json'], [], Output, Err, '', nil,
    ACancel) and ParseLfsLocks(Output, Local);
  if Cancelled then
    Exit(False);
  if not Result then
  begin
    ALocks := nil;
    AError := Trim(Err);
    if AError = '' then
      AError := Trim(Output);
    Exit;
  end;
  MarkLocalLocks(ALocks, Local);
end;

{ TGittanLfsLocksJob }

constructor TGittanLfsLocksJob.Create(const ARoot: string);
begin
  inherited Create(True);
  FRoot := ARoot;
end;

{ Given up on Stop: git-lfs is ended while it waits for a server that
  does not answer, so the reaper does not wait for it. }
function TGittanLfsLocksJob.Cancelled: boolean;
begin
  Result := Terminated;
end;

procedure TGittanLfsLocksJob.Execute;
begin
  try
    FOk := not Terminated and ReadLfsLocks(FRoot, FLocks, FError, @Cancelled);
  except
    on E: Exception do
    begin
      FOk := False;
      FError := E.Message;
    end;
  end;
  Done;
end;

end.
