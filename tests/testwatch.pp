unit testwatch;

{** Tests of gittan.watch: a watcher on a repository made in a temporary
  folder with the real git, polling every 50 ms. Its notification goes
  through Synchronize, which the test lets through as the application's
  message loop would. The open job's notification goes through Queue,
  let through the same way. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.git, gittan.watch;

type
  TWatchTest = class(TTestCase)
  private
    FDir: string;
    FChanges, FAdded: integer;
    FPaths: string;
    FOpenDone: integer;
    procedure OpenDone(Sender: TObject);
    function RunOpenJob(const ADir: string;
      AIgnoreWhitespace: boolean = False): TGittanOpenJob;
    procedure Git(const AArgs: array of string);
    procedure WriteFile(const AName, AContent: string);
    procedure WatcherChange(Sender: TObject);
    procedure Pump(AMilliseconds: integer; AUntil: integer = -1);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestChange;
    procedure TestIgnoreWhitespace;
    procedure TestStop;
    procedure TestOpenJob;
    procedure TestOpenJobIgnoreWhitespace;
    procedure TestOpenJobNoRepository;
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
  FAdded := 0;
  for i := 0 to High(Snap.Stats) do
  begin
    FPaths := FPaths + Snap.Stats[i].Path + ';';
    FAdded := FAdded + Snap.Stats[i].Added;
  end;
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

{ The watcher's snapshot counts as the form does: with IgnoreWhitespace
  a change of whitespace alone is a changed file with no changed line. }
procedure TWatchTest.TestIgnoreWhitespace;
var
  Watcher: TGittanWatcher;
begin
  Watcher := TGittanWatcher.Create(FDir, '', False, 50);
  try
    Watcher.OnChange := @WatcherChange;
    Watcher.IgnoreWhitespace := True;
    Watcher.Start;
    Pump(400);
    WriteFile('a.txt', 'a  ');
    Pump(5000, 1);
    AssertEquals('the edit', 1, FChanges);
    AssertEquals('a.txt;', FPaths);
    AssertEquals('no line counted', 0, FAdded);
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

procedure TWatchTest.OpenDone(Sender: TObject);
begin
  Inc(FOpenDone);
end;

{ Runs an open job on ADir and lets its notification through. }
function TWatchTest.RunOpenJob(const ADir: string;
  AIgnoreWhitespace: boolean): TGittanOpenJob;
var
  Start: TDateTime;
begin
  FOpenDone := 0;
  Result := TGittanOpenJob.Create(ADir);
  Result.OnDone := @OpenDone;
  Result.IgnoreWhitespace := AIgnoreWhitespace;
  Result.Start;
  Start := Now;
  while (FOpenDone = 0) and (MilliSecondsBetween(Now, Start) < 10000) do
    CheckSynchronize(10);
  AssertEquals('done once', 1, FOpenDone);
end;

{ The job finds the root from a folder inside the work tree and takes
  the snapshot with the changes, the branch and the refs. }
procedure TWatchTest.TestOpenJob;
var
  Job: TGittanOpenJob;
  Snap: TGittanRepoSnapshot;
begin
  ForceDirectories(IncludeTrailingPathDelimiter(FDir) + 'sub');
  WriteFile('b.txt', 'b');
  Job := RunOpenJob(IncludeTrailingPathDelimiter(FDir) + 'sub');
  try
    AssertTrue('opened', Job.Opened);
    AssertEquals('the root', ExtractFileName(FDir), ExtractFileName(Job.Root));
    AssertTrue('the git dir', Job.GitDir <> '');
    Snap := Job.Snapshot;
    AssertTrue('the snapshot', Snap.Ok);
    AssertEquals('the change', 1, Length(Snap.Stats));
    AssertEquals('b.txt', Snap.Stats[0].Path);
    AssertEquals('the branch as the one ref', 1, Length(Snap.Refs));
    AssertEquals(Snap.Branch, Snap.Refs[0]);
  finally
    Job.Free;
  end;
end;

{ The job's snapshot follows the whitespace setting: the counts of a
  change of whitespace alone are zero with it, one line without. }
procedure TWatchTest.TestOpenJobIgnoreWhitespace;
var
  Job: TGittanOpenJob;
  Snap: TGittanRepoSnapshot;
begin
  WriteFile('a.txt', 'a  ');
  Job := RunOpenJob(FDir, True);
  try
    Snap := Job.Snapshot;
    AssertTrue('the snapshot', Snap.Ok);
    AssertEquals('the change', 1, Length(Snap.Stats));
    AssertEquals('added, ignored', 0, Snap.Stats[0].Added);
    AssertEquals('deleted, ignored', 0, Snap.Stats[0].Deleted);
  finally
    Job.Free;
  end;
  Job := RunOpenJob(FDir);
  try
    Snap := Job.Snapshot;
    AssertEquals('added, counted', 1, Snap.Stats[0].Added);
    AssertEquals('deleted, counted', 1, Snap.Stats[0].Deleted);
  finally
    Job.Free;
  end;
end;

procedure TWatchTest.TestOpenJobNoRepository;
var
  Job: TGittanOpenJob;
  Dir: string;
begin
  Dir := FDir + '-none';
  ForceDirectories(Dir);
  try
    Job := RunOpenJob(Dir);
    try
      AssertFalse('opened', Job.Opened);
      AssertEquals('', Job.Root);
      AssertTrue('the reason', Job.Error <> '');
    finally
      Job.Free;
    end;
  finally
    RemoveTree(Dir);
  end;
end;

initialization
  RegisterTest(TWatchTest);
end.
