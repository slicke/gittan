unit gittan.blame;

{** Blame for Gittan: who last changed each line of a file.

  Reads the output of `git blame --porcelain` (see TGittanRepo.Blame)
  into the commits of a file and the commit of each line, formats the
  age of a commit short enough for a gutter, and runs the blame of the
  two sides of a file's diff in a background thread: on a long history
  git blame takes a while, and the view must not wait for it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, gittan.git;

type
  {** One commit a blame names. Uncommitted is set for the lines the
    work tree holds beyond the last commit, which git lists under a hash
    of zeros and the author "Not Committed Yet". }
  TGittanBlameCommit = record
    Hash: string;
    Author: string;
    {** The author time in Unix seconds. }
    Time: int64;
    Summary: string;
    Uncommitted: boolean;
  end;
  TGittanBlameCommits = array of TGittanBlameCommit;

  { TGittanBlame }

  {** The blame of one file: its commits, and for each line the commit
    that last changed it. }
  TGittanBlame = class
  private
    FCommits: TGittanBlameCommits;
    FLines: TIntegerDynArray;
    function IndexOf(const AHash: string): integer;
  public
    {** Reads the output of `git blame --porcelain`. Returns false when
      no line of it could be read. }
    function Parse(const AOutput: string): boolean;
    {** The index in Commits of the commit of line ALine (counted from
      1), or -1 for a line the blame does not cover. }
    function CommitOf(ALine: integer): integer;
    {** How many lines the blame covers. }
    function LineCount: integer;
    property Commits: TGittanBlameCommits read FCommits;
  end;

  { TGittanBlameJob }

  {** Blames APath as it is in the commit AOldRef and in ANewRef (or in
    the work tree when ANewRef is empty), in its own thread through its
    own TGittanRepo on ARoot, and calls OnDone in the main thread. The
    results are in OldBlame and NewBlame, nil for a side git could not
    blame (a file it does not know, or one the commit lacks); TakeOld
    and TakeNew hand them over, else the job frees them. Set OnDone,
    then call Start; Stop ends the thread without a notification. }
  TGittanBlameJob = class(TThread)
  private
    FRoot, FPath, FOldRef, FNewRef: string;
    FIgnoreWhitespace: boolean;
    FOld, FNew: TGittanBlame;
    FOnDone: TNotifyEvent;
    procedure Notify;
    function Run(ARepo: TGittanRepo; const ARef: string): TGittanBlame;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot, APath, AOldRef, ANewRef: string;
      AIgnoreWhitespace: boolean);
    destructor Destroy; override;
    {** Drops the handler and ends the thread; a result still on its way
      is thrown away. Waits for a running git only when AWait is set. }
    procedure Stop(AWait: boolean);
    function TakeOld: TGittanBlame;
    function TakeNew: TGittanBlame;
    property Path: string read FPath;
    property OldRef: string read FOldRef;
    property NewRef: string read FNewRef;
    property OldBlame: TGittanBlame read FOld;
    property NewBlame: TGittanBlame read FNew;
    {** Called in the main thread when both sides are done. }
    property OnDone: TNotifyEvent read FOnDone write FOnDone;
  end;

{** The age of a commit made at ATime as seen at ANow, both in Unix
  seconds, in a form short enough for a gutter: today, 3d, 2w, 5mo
  or 3y. }
function BlameAge(ATime, ANow: int64): string;

{** The time of a commit, ATime in Unix seconds, as a local date and
  time: 2026-10-14 09:30. }
function BlameDate(ATime: int64): string;

implementation

uses
  DateUtils;

const
  HashLength = 40;

{ ---------------------------------------------------------------------------
  Parsing
  ---------------------------------------------------------------------------
  Every line of the file comes as a group: a header "<hash> <line in
  the commit> <line in the file> [<lines in the group>]", then, the
  first time the commit appears, its details one per line ("author
  Name", "author-time 1700000000", "summary Message", and others), then
  the line's text after a tab. Later groups of the same commit have the
  header alone. The text is read by hand: a line of the file may hold a
  bare carriage return, which TStrings would take for a line break. }

function IsHex(const S: string; AFrom, ATo: integer): boolean;
var
  i: integer;
begin
  for i := AFrom to ATo do
    if not (S[i] in ['0'..'9', 'a'..'f']) then
      Exit(False);
  Result := True;
end;

{ Whether ALine is a group header; AFinal is then the line's number in
  the file. }
function HeaderLine(const ALine: string; out AFinal: integer): boolean;
var
  p, q: integer;
begin
  Result := False;
  AFinal := 0;
  if (Length(ALine) < HashLength + 4) or (ALine[HashLength + 1] <> ' ') or
    not IsHex(ALine, 1, HashLength) then
    Exit;
  p := Pos(' ', ALine, HashLength + 2);
  if p = 0 then
    Exit;
  q := Pos(' ', ALine, p + 1);
  if q = 0 then
    q := Length(ALine) + 1;
  Result := TryStrToInt(Copy(ALine, p + 1, q - p - 1), AFinal) and (AFinal > 0);
end;

function TGittanBlame.IndexOf(const AHash: string): integer;
var
  i: integer;
begin
  for i := 0 to High(FCommits) do
    if FCommits[i].Hash = AHash then
      Exit(i);
  Result := -1;
end;

function TGittanBlame.Parse(const AOutput: string): boolean;
var
  Start, Stop, Final, Current, p: integer;
  Line, Key, Value: string;
begin
  FCommits := nil;
  FLines := nil;
  Current := -1;
  Start := 1;
  while Start <= Length(AOutput) do
  begin
    Stop := Pos(#10, AOutput, Start);
    if Stop = 0 then
      Stop := Length(AOutput) + 1;
    Line := Copy(AOutput, Start, Stop - Start);
    Start := Stop + 1;
    if (Line <> '') and (Line[1] = #9) then
      Continue;
    if HeaderLine(Line, Final) then
    begin
      Current := IndexOf(Copy(Line, 1, HashLength));
      if Current < 0 then
      begin
        SetLength(FCommits, Length(FCommits) + 1);
        Current := High(FCommits);
        FCommits[Current] := Default(TGittanBlameCommit);
        FCommits[Current].Hash := Copy(Line, 1, HashLength);
        FCommits[Current].Uncommitted := FCommits[Current].Hash =
          StringOfChar('0', HashLength);
      end;
      if Final > Length(FLines) then
      begin
        p := Length(FLines);
        SetLength(FLines, Final);
        while p < Final do
        begin
          FLines[p] := -1;
          Inc(p);
        end;
      end;
      FLines[Final - 1] := Current;
      Continue;
    end;
    if Current < 0 then
      Continue;
    p := Pos(' ', Line);
    if p = 0 then
      Continue;
    Key := Copy(Line, 1, p - 1);
    Value := Copy(Line, p + 1, MaxInt);
    if Key = 'author' then
      FCommits[Current].Author := Value
    else if Key = 'author-time' then
      FCommits[Current].Time := StrToInt64Def(Value, 0)
    else if Key = 'summary' then
      FCommits[Current].Summary := Value;
  end;
  Result := Length(FLines) > 0;
end;

function TGittanBlame.CommitOf(ALine: integer): integer;
begin
  if (ALine >= 1) and (ALine <= Length(FLines)) then
    Result := FLines[ALine - 1]
  else
    Result := -1;
end;

function TGittanBlame.LineCount: integer;
begin
  Result := Length(FLines);
end;

{ ---------------------------------------------------------------------------
  Ages
  --------------------------------------------------------------------------- }
function BlameAge(ATime, ANow: int64): string;
var
  Days: int64;
begin
  Days := (ANow - ATime) div 86400;
  if Days < 1 then
    Result := 'today'
  else if Days < 14 then
    Result := IntToStr(Days) + 'd'
  else if Days < 60 then
    Result := IntToStr(Days div 7) + 'w'
  else if Days < 365 then
    Result := IntToStr(Days div 30) + 'mo'
  else
    Result := IntToStr(Days div 365) + 'y';
end;

function BlameDate(ATime: int64): string;
begin
  Result := FormatDateTime('yyyy-mm-dd hh:nn', UnixToDateTime(ATime, False));
end;

{ ---------------------------------------------------------------------------
  The job
  ---------------------------------------------------------------------------
  git runs in the thread; only Notify reaches the main thread, through
  the thread queue, and only while the handler is still set. }

constructor TGittanBlameJob.Create(const ARoot, APath, AOldRef, ANewRef: string;
  AIgnoreWhitespace: boolean);
begin
  inherited Create(True);
  FRoot := ARoot;
  FPath := APath;
  FOldRef := AOldRef;
  FNewRef := ANewRef;
  FIgnoreWhitespace := AIgnoreWhitespace;
end;

destructor TGittanBlameJob.Destroy;
begin
  if not Finished then
    Stop(True);
  { Removes a Notify still waiting in the thread queue. }
  inherited Destroy;
  FOld.Free;
  FNew.Free;
end;

function TGittanBlameJob.Run(ARepo: TGittanRepo; const ARef: string): TGittanBlame;
var
  Output: string;
begin
  Result := nil;
  if Terminated or not ARepo.Blame(FPath, ARef, Output) then
    Exit;
  Result := TGittanBlame.Create;
  if not Result.Parse(Output) then
    FreeAndNil(Result);
end;

procedure TGittanBlameJob.Execute;
var
  Repo: TGittanRepo;
begin
  Repo := TGittanRepo.Create;
  try
    if not Repo.Open(FRoot) then
      Exit;
    Repo.IgnoreWhitespace := FIgnoreWhitespace;
    FOld := Run(Repo, FOldRef);
    FNew := Run(Repo, FNewRef);
  finally
    Repo.Free;
  end;
  if not Terminated then
    Queue(@Notify);
end;

procedure TGittanBlameJob.Notify;
begin
  if Assigned(FOnDone) and not Terminated then
    FOnDone(Self);
end;

{ WaitFor on the main thread runs the queued calls while it waits, so the
  handler is dropped first: a Notify already queued then does nothing. }
procedure TGittanBlameJob.Stop(AWait: boolean);
begin
  FOnDone := nil;
  Terminate;
  if AWait then
    WaitFor;
end;

function TGittanBlameJob.TakeOld: TGittanBlame;
begin
  Result := FOld;
  FOld := nil;
end;

function TGittanBlameJob.TakeNew: TGittanBlame;
begin
  Result := FNew;
  FNew := nil;
end;

end.
