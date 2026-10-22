unit testwatch;

{** Tests of gittan.watch: a watcher on a repository made in a temporary
  folder with the real git, polling every 50 ms. Its notification goes
  through Synchronize, which the test lets through as the application's
  message loop would. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.git, gittan.watch;

type
  TWatchTest = class(TTestCase)
  private
    FDir: string;
    FChanges: integer;
    FPaths: string;
    procedure Git(const AArgs: array of string);
    procedure WriteFile(const AName, AContent: string);
    procedure WatcherChange(Sender: TObject);
    procedure Pump(AMilliseconds: integer; AUntil: integer = -1);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestChange;
    procedure TestStop;
  end;

implementation

uses
  Process, DateUtils;

procedure RemoveTree(const ADir: string);
var
  Info: TSearchRec;
begin
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, Info) = 0 then
  try
    repeat
      if (Info.Name = '.') or (Info.Name = '..') then
        Continue;
      if Info.Attr and faDirectory <> 0 then
        RemoveTree(IncludeTrailingPathDelimiter(ADir) + Info.Name)
      else
        DeleteFile(IncludeTrailingPathDelimiter(ADir) + Info.Name);
    until FindNext(Info) <> 0;
  finally
    FindClose(Info);
  end;
  RemoveDir(ADir);
end;

procedure TWatchTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-watch-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
  FChanges := 0;
  FPaths := '';
  Git(['init', '-q']);
  WriteFile('a.txt', 'a');
  Git(['add', 'a.txt']);
  Git(['commit', '-q', '-m', 'first']);
end;

procedure TWatchTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TWatchTest.Git(const AArgs: array of string);
var
  Output: string;
  Code: integer;
begin
  if RunCommandIndir(FDir, 'git', AArgs, Output, Code, [poStderrToOutPut]) <> 0 then
    Fail('git could not be run');
  if Code <> 0 then
    Fail('git ' + AArgs[0] + ' failed: ' + Trim(Output));
end;

procedure TWatchTest.WriteFile(const AName, AContent: string);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(IncludeTrailingPathDelimiter(FDir) + AName, fmCreate);
  try
    Stream.WriteBuffer(AContent[1], Length(AContent));
  finally
    Stream.Free;
  end;
end;

{ Reads the snapshot in the handler, where the thread is held. }
procedure TWatchTest.WatcherChange(Sender: TObject);
var
  Snap: TGittanRepoSnapshot;
  i: integer;
begin
  Inc(FChanges);
  Snap := TGittanWatcher(Sender).Snapshot;
  FPaths := '';
  for i := 0 to High(Snap.Stats) do
    FPaths := FPaths + Snap.Stats[i].Path + ';';
end;

{ Lets the watcher's notifications through for AMilliseconds, or until
  AUntil of them have come. }
procedure TWatchTest.Pump(AMilliseconds: integer; AUntil: integer);
var
  Start: TDateTime;
begin
  Start := Now;
  while (MilliSecondsBetween(Now, Start) < AMilliseconds) and
    ((AUntil < 0) or (FChanges < AUntil)) do
    CheckSynchronize(10);
end;

{ Polls that find the repository as it was say nothing; a write says so
  once, with the snapshot that shows it. }
procedure TWatchTest.TestChange;
var
  Watcher: TGittanWatcher;
  Start: TDateTime;
begin
  Watcher := TGittanWatcher.Create(FDir, '', False, 50);
  try
    Watcher.OnChange := @WatcherChange;
    Watcher.Start;
    Pump(400);
    AssertEquals('unchanged polls', 0, FChanges);
    WriteFile('b.txt', 'b');
    Pump(5000, 1);
    AssertEquals('the new file', 1, FChanges);
    AssertEquals('b.txt;', FPaths);
    Pump(400);
    AssertEquals('once', 1, FChanges);
    WriteFile('a.txt', 'changed');
    Pump(5000, 2);
    AssertEquals('the edit', 2, FChanges);
    AssertEquals('a.txt;b.txt;', FPaths);
  finally
    Watcher.Free;
  end;
end;

{ Free wakes the thread from its wait rather than waiting the interval
  out. }
procedure TWatchTest.TestStop;
var
  Watcher: TGittanWatcher;
  Start: TDateTime;
begin
  Watcher := TGittanWatcher.Create(FDir, '', False, 10000);
  Watcher.OnChange := @WatcherChange;
  Watcher.Start;
  Pump(300);
  Start := Now;
  Watcher.Free;
  AssertTrue('Free waited the interval out', MilliSecondsBetween(Now, Start) < 2000);
  AssertEquals(0, FChanges);
end;

initialization
  RegisterTest(TWatchTest);
end.
