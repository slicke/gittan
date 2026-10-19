unit testcommitjob;

{** Tests of gittan.commitjob and gittan.remotejob against a repository made in a temporary
  folder with the real git. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.git, gittan.commitjob, gittan.remotejob;

type
  TCommitJobTest = class(TTestCase)
  private
    FDir: string;
    FDone: integer;
    procedure Git(const AArgs: array of string);
    procedure WriteFile(const AName, AContent: string);
    procedure JobDone(Sender: TObject);
    procedure RunJob(AJob: TThread);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCommits;
    procedure TestFails;
    procedure TestStopped;
    procedure TestRemoteJob;
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
  Code: integer;
begin
  if RunCommandIndir(FDir, 'git', AArgs, Output, Code, [poStderrToOutPut]) <> 0 then
    Fail('git could not be run');
  if Code <> 0 then
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
procedure TCommitJobTest.RunJob(AJob: TThread);
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

{ A push to a bare repository beside the test's, then one with no
  remote left, which fails with git's reason. }
procedure TCommitJobTest.TestRemoteJob;
var
  Remote: string;
  Job: TGittanRemoteJob;
begin
  WriteFile('a.txt', 'a');
  Git(['add', '-A']);
  Git(['commit', '-q', '-m', 'first']);
  Remote := ExcludeTrailingPathDelimiter(FDir) + '-remote';
  Git(['init', '-q', '--bare', Remote]);
  try
    Git(['remote', 'add', 'origin', Remote]);
    Job := TGittanRemoteJob.Create(FDir, rkPush);
    try
      Job.OnDone := @JobDone;
      RunJob(Job);
      AssertEquals(1, FDone);
      AssertTrue(Job.Error, Job.Ok);
      AssertFalse(Job.Rejected);
    finally
      Job.Free;
    end;
    { Removing the remote drops the branch's upstream too. }
    Git(['remote', 'remove', 'origin']);
    Job := TGittanRemoteJob.Create(FDir, rkPush);
    try
      Job.OnDone := @JobDone;
      RunJob(Job);
      AssertEquals(2, FDone);
      AssertFalse(Job.Ok);
      AssertTrue(Job.Error <> '');
    finally
      Job.Free;
    end;
  except
    RemoveTree(Remote);
    raise;
  end;
  RemoveTree(Remote);
end;

initialization
  Randomize;
  RegisterTest(TCommitJobTest);
end.
