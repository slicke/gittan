unit testjob;

{** Tests of gittan.job: a job whose Execute waits for the test to let it
  go, so the test knows where the thread is when it stops or frees it.
  The notification goes through Queue, which the test lets through as
  the application's message loop would. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.job;

type
  { Waits for Release, then counts its work and says it is done. }
  TWaitingJob = class(TGittanJob)
  private
    FGo, FBusy: PRTLEvent;
    FWorked: boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(AEndOnStop: boolean);
    destructor Destroy; override;
    {** Waits until Execute runs. }
    procedure WaitBusy;
    procedure Release;
    property Worked: boolean read FWorked;
  end;

  TJobTest = class(TTestCase)
  private
    FDone: integer;
    procedure JobDone(Sender: TObject);
  protected
    procedure SetUp; override;
  published
    procedure TestDone;
    procedure TestNeverStarted;
    procedure TestStopEnds;
    procedure TestStopKeepsRunning;
    procedure TestFreeRunning;
  end;

implementation

constructor TWaitingJob.Create(AEndOnStop: boolean);
begin
  inherited Create(AEndOnStop);
  FGo := RTLEventCreate;
  FBusy := RTLEventCreate;
end;

destructor TWaitingJob.Destroy;
begin
  { The thread is let go, or the wait in Destroy would never end. }
  Release;
  inherited Destroy;
  RTLEventDestroy(FGo);
  RTLEventDestroy(FBusy);
end;

procedure TWaitingJob.Execute;
begin
  RTLEventSetEvent(FBusy);
  RTLEventWaitFor(FGo);
  if Terminated then
    Exit;
  FWorked := True;
  Done;
end;

procedure TWaitingJob.WaitBusy;
begin
  RTLEventWaitFor(FBusy, 5000);
end;

procedure TWaitingJob.Release;
begin
  RTLEventSetEvent(FGo);
end;

procedure TJobTest.SetUp;
begin
  FDone := 0;
end;

procedure TJobTest.JobDone(Sender: TObject);
begin
  Inc(FDone);
end;

{ A job that runs to its end tells the handler, once, in the main
  thread. }
procedure TJobTest.TestDone;
var
  Job: TWaitingJob;
begin
  Job := TWaitingJob.Create(True);
  try
    Job.OnDone := @JobDone;
    Job.Start;
    Job.Release;
    { WaitFor in the main thread lets the queue through as well. }
    Job.WaitFor;
    CheckSynchronize(0);
    AssertEquals(1, FDone);
    AssertTrue(Job.Worked);
  finally
    Job.Free;
  end;
end;

{ A job never started is not waited for, and frees. }
procedure TJobTest.TestNeverStarted;
var
  Job: TWaitingJob;
begin
  Job := TWaitingJob.Create(True);
  Job.OnDone := @JobDone;
  Job.Stop(True);
  Job.Free;
  Job := TWaitingJob.Create(False);
  Job.Stop(True);
  Job.Free;
  CheckSynchronize(0);
  AssertEquals(0, FDone);
end;

{ A job that may be given up is told to end by Stop, and says nothing. }
procedure TJobTest.TestStopEnds;
var
  Job: TWaitingJob;
begin
  Job := TWaitingJob.Create(True);
  try
    Job.OnDone := @JobDone;
    Job.Start;
    Job.WaitBusy;
    Job.Stop(False);
    AssertTrue(Job.Terminated);
    Job.Release;
    Job.WaitFor;
    CheckSynchronize(0);
    AssertEquals(0, FDone);
    AssertFalse('it gave up', Job.Worked);
  finally
    Job.Free;
  end;
end;

{ A job that is never broken off runs to its end after Stop, which only
  drops the handler. }
procedure TJobTest.TestStopKeepsRunning;
var
  Job: TWaitingJob;
begin
  Job := TWaitingJob.Create(False);
  try
    Job.OnDone := @JobDone;
    Job.Start;
    Job.WaitBusy;
    Job.Stop(False);
    AssertFalse(Job.Terminated);
    Job.Release;
    Job.Stop(True);
    CheckSynchronize(0);
    AssertEquals(0, FDone);
    AssertTrue('it went on', Job.Worked);
  finally
    Job.Free;
  end;
end;

{ Freeing a running job waits for it, and its notification, queued
  while Free waits, reaches no handler. }
procedure TJobTest.TestFreeRunning;
var
  Job: TWaitingJob;
begin
  Job := TWaitingJob.Create(False);
  Job.OnDone := @JobDone;
  Job.Start;
  Job.WaitBusy;
  Job.Free;
  CheckSynchronize(0);
  AssertEquals(0, FDone);
end;

initialization
  RegisterTest(TJobTest);
end.
