unit testcommitjob;

{** Tests of gittan.commitjob against a repository made in a temporary
  folder with the real git. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.commitjob;

type
  TCommitJobTest = class(TTestCase)
  private
    FDir: string;
    FDone: integer;
    procedure Git(const AArgs: array of string);
    procedure WriteFile(const AName, AContent: string);
    procedure JobDone(Sender: TObject);
    procedure RunJob(AJob: TGittanCommitJob);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCommits;
    procedure TestFails;
    procedure TestStopped;
  end;

implementation

uses
  Process;

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

procedure TCommitJobTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-commitjob-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
  FDone := 0;
  Git(['init', '-q']);
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
end;

procedure TCommitJobTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TCommitJobTest.Git(const AArgs: array of string);
var
  Output: string;
  Status: integer;
begin
  if RunCommandIndir(FDir, 'git', AArgs, Output, Status, [poStderrToOutPut]) <> 0 then
    Fail('git could not be run');
  if Status <> 0 then
    Fail('git ' + AArgs[0] + ' failed: ' + Trim(Output));
end;

procedure TCommitJobTest.WriteFile(const AName, AContent: string);
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := AContent;
    Lines.SaveToFile(IncludeTrailingPathDelimiter(FDir) + AName);
  finally
    Lines.Free;
  end;
end;

procedure TCommitJobTest.JobDone(Sender: TObject);
begin
  Inc(FDone);
end;

{ Runs the job to its end and lets its queued notification through, as
  the application's message loop would. }
procedure TCommitJobTest.RunJob(AJob: TGittanCommitJob);
begin
  AJob.Start;
  AJob.WaitFor;
  CheckSynchronize(0);
end;

procedure TCommitJobTest.TestCommits;
var
  Paths: TStringList;
  Job: TGittanCommitJob;
begin
  WriteFile('a.txt', 'a');
  Paths := TStringList.Create;
  try
    Paths.Add('a.txt');
    Job := TGittanCommitJob.Create(FDir, 'first', Paths, False);
  finally
    Paths.Free;
  end;
  try
    Job.OnDone := @JobDone;
    RunJob(Job);
    AssertEquals(1, FDone);
    AssertTrue(Job.Error, Job.Ok);
    AssertEquals(40, Length(Job.Id));
    AssertEquals('', Job.Error);
  finally
    Job.Free;
  end;
end;

procedure TCommitJobTest.TestFails;
var
  Paths: TStringList;
  Job: TGittanCommitJob;
begin
  Paths := TStringList.Create;
  try
    Job := TGittanCommitJob.Create(FDir, 'nothing', Paths, False);
  finally
    Paths.Free;
  end;
  try
    Job.OnDone := @JobDone;
    RunJob(Job);
    AssertEquals(1, FDone);
    AssertFalse(Job.Ok);
    AssertEquals('', Job.Id);
    AssertTrue(Job.Error <> '');
  finally
    Job.Free;
  end;
end;

{ A stopped job still commits, but says nothing. }
procedure TCommitJobTest.TestStopped;
var
  Paths: TStringList;
  Job: TGittanCommitJob;
begin
  WriteFile('a.txt', 'a');
  Paths := TStringList.Create;
  try
    Paths.Add('a.txt');
    Job := TGittanCommitJob.Create(FDir, 'first', Paths, False);
  finally
    Paths.Free;
  end;
  try
    Job.OnDone := @JobDone;
    Job.Start;
    Job.Stop(True);
    CheckSynchronize(0);
    AssertEquals(0, FDone);
    AssertTrue(Job.Error, Job.Ok);
  finally
    Job.Free;
  end;
end;

initialization
  Randomize;
  RegisterTest(TCommitJobTest);
end.
