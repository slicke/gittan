unit testcommitjob;

{** Tests of gittan.commitjob and gittan.remotejob against a repository made in a temporary
  folder with the real git, and the freeing of a running job, the pull
  request job of gittan.github among them. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.git, gittan.commitjob, gittan.remotejob,
  gittan.forge, gittan.github;

type
  TCommitJobTest = class(TTestCase)
  private
    FDir: string;
    FDone: integer;
    FOutputs: integer;
    procedure JobOutput(Sender: TObject);
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
    procedure TestFreeRunning;
    procedure TestRemoteJob;
    procedure TestRemoteJobProgress;
    procedure TestTerminalText;
  end;

implementation

uses
  {$ifdef unix}BaseUnix,{$endif} Process;

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

{ Waits up to five seconds for AFileName to appear. }
procedure WaitForFile(const AFileName: string);
var
  i: integer;
begin
  for i := 1 to 500 do
  begin
    if FileExists(AFileName) then
      Exit;
    Sleep(10);
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
{ A job freed while it runs waits for its thread before it frees what
  the thread works with, and says nothing. Each job is freed once the git
  it runs has started (a job freed before its thread starts never runs):
  the commit job's in a pre-commit hook, the pull request job's in the
  "pr" alias of the git that stands in for gh, both of which mark that
  they started and then take a while. }
procedure TCommitJobTest.TestFreeRunning;
const
  Slow = 'touch started; sleep 0.3';
var
  Paths: TStringList;
  Job: TGittanCommitJob;
  Pulls: TGittanPullRequestJob;
  Forge: TGittanForge;
  Started: string;
begin
  Started := IncludeTrailingPathDelimiter(FDir) + 'started';
  ForceDirectories(IncludeTrailingPathDelimiter(FDir) + '.git' + PathDelim + 'hooks');
  WriteFile('.git/hooks/pre-commit', '#!/bin/sh' + LineEnding + Slow);
  {$ifdef unix}
  FpChmod(IncludeTrailingPathDelimiter(FDir) + '.git/hooks/pre-commit', &755);
  {$endif}
  WriteFile('a.txt', 'a');
  Paths := TStringList.Create;
  try
    Paths.Add('a.txt');
    Job := TGittanCommitJob.Create(FDir, 'first', Paths, False);
  finally
    Paths.Free;
  end;
  Job.OnDone := @JobDone;
  Job.Start;
  WaitForFile(Started);
  Job.Free;
  CheckSynchronize(0);
  AssertEquals('the commit job', 0, FDone);
  Git(['rev-parse', '--verify', '-q', 'HEAD']);

  DeleteFile(Started);
  Git(['config', 'alias.pr', '!' + Slow + '; true']);
  { The job takes what it needs from the forge, so it outlives it. }
  Forge := TGittanGitHubForge.Create(GitExe);
  Pulls := Forge.PullJob(FDir, 'main', '');
  Forge.Free;
  Pulls.OnDone := @JobDone;
  Pulls.Start;
  WaitForFile(Started);
  Pulls.Free;
  CheckSynchronize(0);
  AssertEquals('the pull request job', 0, FDone);
end;

procedure TCommitJobTest.JobOutput(Sender: TObject);
begin
  Inc(FOutputs);
  AssertTrue('progress so far', TGittanRemoteJob(Sender).Progress <> '');
end;

{ A push reports its progress as it goes (--progress, so git counts its
  objects without a terminal), in the main thread, and the output of a
  pre-push hook is in it. }
procedure TCommitJobTest.TestRemoteJobProgress;
var
  Remote, Text: string;
  Job: TGittanRemoteJob;
  Code: integer;
begin
  WriteFile('a.txt', 'a');
  Git(['add', '-A']);
  Git(['commit', '-q', '-m', 'first']);
  Remote := ExcludeTrailingPathDelimiter(FDir) + '-remote';
  Git(['init', '-q', '--bare', Remote]);
  try
    Git(['remote', 'add', 'origin', Remote]);
    WriteFile('.git/hooks/pre-push', '#!/bin/sh'#10'echo "hook at work"'#10);
    {$ifdef UNIX}
    RunCommandIndir(FDir, 'chmod', ['+x', '.git/hooks/pre-push'], Text, Code, []);
    {$endif}
    Job := TGittanRemoteJob.Create(FDir, rkPush);
    try
      Job.OnDone := @JobDone;
      Job.OnOutput := @JobOutput;
      RunJob(Job);
      AssertEquals(1, FDone);
      AssertTrue(Job.Error, Job.Ok);
      AssertTrue('told of output', FOutputs > 0);
      AssertTrue(Job.Progress, Pos('hook at work', Job.Progress) > 0);
      AssertTrue(Job.Progress, PushTransferStarted(Job.Progress));
      AssertTrue(Job.Progress, Pos(#13, Job.Progress) = 0);
    finally
      Job.Free;
    end;
  except
    RemoveTree(Remote);
    raise;
  end;
  RemoveTree(Remote);
end;

{ A carriage return starts the line over, also across chunks; one before
  a newline is that newline; the transfer marks are known at a line's
  start only. }
procedure TCommitJobTest.TestTerminalText;
var
  Text: string;
  Return: boolean;
begin
  Text := '';
  Return := False;
  AppendTerminalText(Text, Return, 'hook'#10'Writing objects:  33%'#13'Writing objects:  66%');
  AssertEquals('hook'#10'Writing objects:  66%', Text);
  AppendTerminalText(Text, Return, #13);
  AssertTrue(Return);
  AppendTerminalText(Text, Return, 'Writing objects: 100%, done.'#13#10'To origin'#10);
  AssertFalse(Return);
  AssertEquals('hook'#10'Writing objects: 100%, done.'#10'To origin'#10, Text);

  AssertFalse(PushTransferStarted('running tests'));
  AssertFalse(PushTransferStarted('note: Writing objects: is a git phrase'));
  AssertTrue(PushTransferStarted('hook'#10'Enumerating objects: 3, done.'));
  AssertTrue(PushTransferStarted('Everything up-to-date'));
  AssertTrue(PushTransferStarted('x'#10'remote: Resolving deltas'));
  AssertTrue('a deletion', PushTransferStarted('To /git/o.git'#10' - [deleted]         bar'));
  AssertTrue('a deletion of a ref the remote lacks',
    PushTransferStarted('error: unable to delete ''nope'': remote ref does not exist'));
  AssertFalse('the hook said no', PushTransferStarted('hook says no'#10 +
    'error: failed to push some refs to ''/git/o.git'''));
end;

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
