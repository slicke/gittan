unit testrepocommands;

{** Tests of gittan.repocommands: the commands file, the scripts of a
  package.json, the targets of a Makefile, how DiscoverRepoCommands
  joins them, the file's hash, and a command run by TGittanCommandJob. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.repocommands;

type
  TRepoCommandsTest = class(TTestCase)
  private
    FDir: string;
    FDone: integer;
    FOutputs: integer;
    procedure Put(const ARel, AText: string);
    procedure JobDone(Sender: TObject);
    procedure JobOutput(Sender: TObject);
    procedure RunJob(AJob: TGittanCommandJob; AKillAfterMs: integer = 0);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestParseFile;
    procedure TestParseFileKeys;
    procedure TestPackageScripts;
    procedure TestPackageNotJson;
    procedure TestMakefileTargets;
    procedure TestRunner;
    procedure TestDiscoverOrder;
    procedure TestDiscoverKeysFromFile;
    procedure TestDiscoverOrphan;
    procedure TestHash;
    procedure TestCommandByKey;
    procedure TestJobRuns;
    procedure TestJobFails;
    procedure TestJobKill;
  end;

implementation

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

procedure TRepoCommandsTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-commands-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
  FDone := 0;
  FOutputs := 0;
end;

procedure TRepoCommandsTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TRepoCommandsTest.Put(const ARel, AText: string);
var
  Name: string;
  F: TFileStream;
begin
  Name := IncludeTrailingPathDelimiter(FDir) + SetDirSeparators(ARel);
  ForceDirectories(ExtractFileDir(Name));
  F := TFileStream.Create(Name, fmCreate);
  try
    if AText <> '' then
      F.WriteBuffer(AText[1], Length(AText));
  finally
    F.Free;
  end;
end;

procedure TRepoCommandsTest.JobDone(Sender: TObject);
begin
  Inc(FDone);
end;

procedure TRepoCommandsTest.JobOutput(Sender: TObject);
begin
  Inc(FOutputs);
end;

{ Runs AJob to its end, letting the queued notifications through as
  the application's loop would; with AKillAfterMs it is killed after
  that long. }
procedure TRepoCommandsTest.RunJob(AJob: TGittanCommandJob; AKillAfterMs: integer);
var
  Waited: integer;
begin
  AJob.OnDone := @JobDone;
  AJob.OnOutput := @JobOutput;
  AJob.Start;
  Waited := 0;
  while (FDone = 0) and (Waited < 20000) do
  begin
    CheckSynchronize(10);
    Inc(Waited, 10);
    if (AKillAfterMs > 0) and (Waited >= AKillAfterMs) then
      AJob.Kill;
  end;
  AJob.WaitFor;
  CheckSynchronize(0);
end;

procedure TRepoCommandsTest.TestParseFile;
var
  C: TGittanRepoCommands;
begin
  C := ParseCommandsFile(
    '; a comment' + #10 +
    '[test]' + #10 +
    'command = npm test' + #10 +
    'key = t' + #10 +
    '# another comment' + #10 +
    '' + #10 +
    '[ dev ]' + #13#10 +
    'Command=npm run dev' + #13#10 +
    'terminal = yes' + #13#10 +
    '[build]' + #10 +
    'key = B' + #10);
  AssertEquals(3, Length(C));
  AssertEquals('test', C[0].Name);
  AssertEquals('npm test', C[0].Command);
  AssertEquals('the detail is the command', 'npm test', C[0].Detail);
  AssertEquals('the key is a capital', 'T', C[0].Key);
  AssertFalse(C[0].Terminal);
  AssertTrue(C[0].Source = csFile);
  AssertEquals('the name is trimmed', 'dev', C[1].Name);
  AssertEquals('npm run dev', C[1].Command);
  AssertEquals('no key', #0, C[1].Key);
  AssertTrue('terminal = yes', C[1].Terminal);
  AssertEquals('a section without a command', '', C[2].Command);
  AssertEquals('B', C[2].Key);
end;

procedure TRepoCommandsTest.TestParseFileKeys;
var
  C: TGittanRepoCommands;
begin
  C := ParseCommandsFile('[a]'#10'command = x'#10'key = 7'#10'[b]'#10'command = y'#10'key = F1'#10 +
    '[c]'#10'command = z'#10'key = -'#10'lines before any section = ignored');
  AssertEquals(3, Length(C));
  AssertEquals('a digit is a key', '7', C[0].Key);
  AssertEquals('two characters are none', #0, C[1].Key);
  AssertEquals('punctuation is none', #0, C[2].Key);
  AssertEquals('nothing before a section', 0, Length(ParseCommandsFile('command = x')));
  AssertEquals(0, Length(ParseCommandsFile('')));
end;

procedure TRepoCommandsTest.TestPackageScripts;
var
  C: TGittanRepoCommands;
begin
  C := ParsePackageScripts('{"name": "x", "scripts": {"dev": "vite", "test": "vitest run", ' +
    '"count": 3}, "dependencies": {}}');
  AssertEquals('the strings, in order', 2, Length(C));
  AssertEquals('dev', C[0].Name);
  AssertEquals('vite', C[0].Detail);
  AssertEquals('the runner is filled in later', '', C[0].Command);
  AssertTrue(C[0].Source = csPackage);
  AssertEquals('test', C[1].Name);
  AssertEquals('vitest run', C[1].Detail);
end;

procedure TRepoCommandsTest.TestPackageNotJson;
begin
  AssertEquals(0, Length(ParsePackageScripts('not json')));
  AssertEquals(0, Length(ParsePackageScripts('')));
  AssertEquals(0, Length(ParsePackageScripts('[1, 2]')));
  AssertEquals(0, Length(ParsePackageScripts('{"scripts": "none"}')));
  AssertEquals(0, Length(ParsePackageScripts('{"name": "x"}')));
end;

procedure TRepoCommandsTest.TestMakefileTargets;
var
  T: TStringArray;
begin
  T := ParseMakefileTargets(
    'FPC ?= fpc' + #10 +
    'LEXLIB := lexlib' + #10 +
    '.PHONY: all clean' + #10 +
    '' + #10 +
    'all: deps' + #10 +
    #9'$(LAZBUILD) Gittan.lpi' + #10 +
    'debug run: all' + #10 +
    '$(TESTBIN): tests/gittantests.lpr' + #10 +
    '%.o: %.c' + #10 +
    'lib/%.ppu: src/%.pp' + #10 +
    '# clean: not a rule' + #10 +
    'clean::' + #10 +
    'all:' + #10 +
    'make-lexlib: ; echo' + #10 +
    'ifeq ($(OS),Windows_NT)' + #10 +
    'endif' + #10);
  AssertEquals('a prerequisite alone is no target', 5, Length(T));
  AssertEquals('all', T[0]);
  AssertEquals('a rule with two targets gives both', 'debug', T[1]);
  AssertEquals('run', T[2]);
  AssertEquals('a double-colon rule', 'clean', T[3]);
  AssertEquals('make-lexlib', T[4]);
end;

procedure TRepoCommandsTest.TestRunner;
begin
  AssertEquals('npm run', PackageRunner(FDir));
  Put('yarn.lock', '');
  AssertEquals('yarn run', PackageRunner(FDir));
  Put('pnpm-lock.yaml', '');
  AssertEquals('pnpm first', 'pnpm run', PackageRunner(FDir));
  DeleteFile(IncludeTrailingPathDelimiter(FDir) + 'pnpm-lock.yaml');
  DeleteFile(IncludeTrailingPathDelimiter(FDir) + 'yarn.lock');
  Put('bun.lock', '');
  AssertEquals('bun run', PackageRunner(FDir));
end;

procedure TRepoCommandsTest.TestDiscoverOrder;
var
  C: TGittanRepoCommands;
begin
  AssertEquals('nothing in an empty folder', 0, Length(DiscoverRepoCommands(FDir)));
  AssertEquals(0, Length(DiscoverRepoCommands('')));
  Put('.gittan/commands.ini', '[lint]'#10'command = npm run lint -- --fix'#10'key = L'#10);
  Put('package.json', '{"scripts": {"test": "vitest run"}}');
  Put('Makefile', 'all: deps'#10#9'echo'#10'deps:'#10);
  C := DiscoverRepoCommands(FDir);
  AssertEquals(4, Length(C));
  AssertEquals('the file first', 'lint', C[0].Name);
  AssertEquals('npm run lint -- --fix', C[0].Command);
  AssertEquals('L', C[0].Key);
  AssertEquals('then the scripts', 'test', C[1].Name);
  AssertEquals('npm run test', C[1].Command);
  AssertEquals('vitest run', C[1].Detail);
  AssertEquals('then the targets', 'all', C[2].Name);
  AssertEquals('make all', C[2].Command);
  AssertTrue(C[2].Source = csMake);
  AssertEquals('deps', C[3].Name);
end;

procedure TRepoCommandsTest.TestDiscoverKeysFromFile;
var
  C: TGittanRepoCommands;
begin
  Put('.gittan/commands.ini',
    '[test]'#10'key = T'#10'terminal = true'#10 +
    '[deps]'#10'key = D'#10 +
    '[own]'#10'command = echo own'#10'key = T'#10 +
    '[other]'#10'key = X'#10);
  Put('package.json', '{"scripts": {"test": "vitest run"}}');
  Put('Makefile', 'deps:'#10);
  C := DiscoverRepoCommands(FDir);
  AssertEquals('a keyed section taken by a script or target is no command of its own', 4,
    Length(C));
  AssertEquals('own', C[0].Name);
  AssertEquals('the first with a key keeps it', 'T', C[0].Key);
  AssertEquals('one taken by nothing stays, after the file''s own', 'other', C[1].Name);
  AssertEquals('', C[1].Command);
  AssertEquals('test', C[2].Name);
  AssertEquals('npm run test', C[2].Command);
  AssertEquals('the same key again is dropped', #0, C[2].Key);
  AssertTrue('the terminal flag comes with the section', C[2].Terminal);
  AssertEquals('deps', C[3].Name);
  AssertEquals('D', C[3].Key);
  AssertFalse(C[3].Terminal);
end;

procedure TRepoCommandsTest.TestDiscoverOrphan;
var
  C: TGittanRepoCommands;
begin
  Put('.gittan/commands.ini',
    '[biuld]'#10'key = B'#10 +
    '[own]'#10'command = echo own'#10'key = O'#10 +
    '[build]'#10'key = B'#10);
  Put('Makefile', 'build:'#10);
  C := DiscoverRepoCommands(FDir);
  AssertEquals('the orphan is kept among the file''s', 3, Length(C));
  AssertEquals('biuld', C[0].Name);
  AssertEquals('with nothing to run', '', C[0].Command);
  AssertTrue(C[0].Source = csFile);
  AssertEquals('its key is shown', 'B', C[0].Key);
  AssertEquals('own', C[1].Name);
  AssertEquals('build', C[2].Name);
  AssertEquals('the orphan''s key does not take the target''s', 'B', C[2].Key);
  AssertEquals('and runs the target', 2, CommandByKey(C, 'B'));
end;

procedure TRepoCommandsTest.TestHash;
var
  H: string;
begin
  AssertEquals('no file, no hash', '', CommandsFileHash(FDir));
  AssertEquals('', CommandsFileHash(''));
  Put('.gittan/commands.ini', '[a]'#10'command = x'#10);
  H := CommandsFileHash(FDir);
  AssertEquals('SHA-256 in hex', 64, Length(H));
  AssertEquals('the same text, the same hash', H, CommandsFileHash(FDir));
  Put('.gittan/commands.ini', '[a]'#10'command = y'#10);
  AssertTrue('another text, another hash', H <> CommandsFileHash(FDir));
end;

procedure TRepoCommandsTest.TestCommandByKey;
var
  C: TGittanRepoCommands;
begin
  C := ParseCommandsFile('[a]'#10'command = x'#10'[b]'#10'command = y'#10'key = B'#10);
  AssertEquals(1, CommandByKey(C, 'B'));
  AssertEquals(-1, CommandByKey(C, 'A'));
  AssertEquals('no key matches no command', -1, CommandByKey(C, #0));
end;

procedure TRepoCommandsTest.TestJobRuns;
var
  Job: TGittanCommandJob;
begin
  Job := TGittanCommandJob.Create(FDir, 'echo hello && echo there 1>&2');
  try
    RunJob(Job);
    AssertEquals(1, FDone);
    AssertTrue(Job.Started);
    AssertEquals(0, Job.ExitCode);
    AssertFalse(Job.Killed);
    AssertTrue('both streams, in one', Pos('hello', Job.Output) > 0);
    AssertTrue(Pos('there', Job.Output) > 0);
    AssertTrue('output was told', FOutputs > 0);
    AssertTrue(Job.ElapsedMs >= 0);
  finally
    Job.Free;
  end;
end;

procedure TRepoCommandsTest.TestJobFails;
var
  Job: TGittanCommandJob;
begin
  Job := TGittanCommandJob.Create(FDir, 'exit 3');
  try
    RunJob(Job);
    AssertEquals(1, FDone);
    AssertTrue(Job.Started);
    AssertEquals('the exit code', 3, Job.ExitCode);
  finally
    Job.Free;
  end;
end;

procedure TRepoCommandsTest.TestJobKill;
var
  Job: TGittanCommandJob;
  Started: QWord;
begin
  {$ifdef windows}
  Job := TGittanCommandJob.Create(FDir, 'ping -n 30 127.0.0.1 > NUL');
  {$else}
  Job := TGittanCommandJob.Create(FDir, 'sleep 30; echo late');
  {$endif}
  try
    Started := GetTickCount64;
    RunJob(Job, 300);
    AssertEquals(1, FDone);
    AssertTrue('ended by Kill', Job.Killed);
    AssertTrue('long before the sleep', GetTickCount64 - Started < 15000);
    AssertEquals('the rest of the line did not run', 0, Pos('late', Job.Output));
  finally
    Job.Free;
  end;
end;

initialization
  RegisterTest(TRepoCommandsTest);

end.
