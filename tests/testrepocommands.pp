unit testrepocommands;

{** Tests of gittan.repocommands: the commands files (commands.toml
  and the files of .gittan/commands), the
  scripts of a package.json, the targets of a Makefile, how DiscoverRepoCommands
  joins them, the file's hash, and a command run by TGittanCommandJob. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, {$ifndef windows}BaseUnix,{$endif} fpcunit, testregistry,
  gittan.repocommands, gittan.project, gittan.sha256, testhelpers;

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
    procedure TestParseToml;
    procedure TestParseTomlNotToml;
    procedure TestParseTomlFields;
    procedure TestParseTomlPerSystem;
    procedure TestTomlProjects;
    procedure TestCommandsFiles;
    procedure TestCommandsFileNames;
    procedure TestCommandsFileUnreadable;
    procedure TestPackageScripts;
    procedure TestPackageNotJson;
    procedure TestMakefileTargets;
    procedure TestRunner;
    procedure TestDiscoverOrder;
    procedure TestDiscoverKeysFromFile;
    procedure TestDiscoverOrphan;
    procedure TestDiscoverFieldsFromFile;
    procedure TestDiscoverHidden;
    procedure TestDiscoverElsewhere;
    procedure TestDiscoverOverlap;
    procedure TestHash;
    procedure TestHashOfFiles;
    procedure TestHashRenamed;
    procedure TestCommandByKey;
    procedure TestSplitName;
    procedure TestJobRuns;
    procedure TestJobFails;
    procedure TestJobKill;
    procedure TestJobKillForced;
    procedure TestJobKillChild;
  end;

implementation

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

procedure TRepoCommandsTest.TestParseToml;
var
  C: TGittanRepoCommands;
  E: string;
begin
  C := ParseCommandsToml(
    '# a comment'#10 +
    'project = "rust"'#10 +
    '[commands]'#10 +
    'lint = "npm run lint"'#10 +
    '[commands.log]'#10 +
    'run = ''git log --format="%h %s"'''#10 +
    'key = "g"'#10 +
    '[commands."build:run"]'#10 +
    'run = """'#10'make build'#10'./run'#10'"""'#10 +
    'terminal = true'#10 +
    'key = 7'#10 +
    '[commands.wrong]'#10 +
    'run = 3'#10 +
    'key = "F1"'#10 +
    'terminal = "yes"'#10 +
    'other = "kept out"'#10 +
    '[commands.blank]'#10 +
    'run = "  "'#10 +
    'key = "B"'#10 +
    '[elsewhere]'#10 +
    'run = "not a command"'#10, E);
  AssertEquals('no error', '', E);
  AssertEquals(5, Length(C));
  { By name: blank, build:run, lint, log, wrong. }
  AssertEquals('blank', C[0].Name);
  AssertEquals('a run of blanks runs nothing', '', C[0].Command);
  AssertEquals('B', C[0].Key);
  AssertEquals('a quoted name', 'build:run', C[1].Name);
  AssertEquals('a multi-line string, its first newline dropped', 'make build'#10'./run'#10,
    C[1].Command);
  AssertTrue(C[1].Terminal);
  AssertEquals('a digit as a number', '7', C[1].Key);
  AssertTrue(C[1].Source = csFile);
  AssertEquals('a string is the run line', 'lint', C[2].Name);
  AssertEquals('npm run lint', C[2].Command);
  AssertEquals(#0, C[2].Key);
  AssertEquals('log', C[3].Name);
  AssertEquals('a literal string keeps its quotes', 'git log --format="%h %s"', C[3].Command);
  AssertEquals('the detail is the line', C[3].Command, C[3].Detail);
  AssertEquals('a key as a capital', 'G', C[3].Key);
  AssertEquals('wrong', C[4].Name);
  AssertEquals('a run that is no string is none', '', C[4].Command);
  AssertEquals('F1 is no key', #0, C[4].Key);
  AssertFalse('terminal must be a boolean', C[4].Terminal);
  AssertEquals('no [commands], none', 0, Length(ParseCommandsToml('project = "go"', E)));
  AssertEquals('', E);
  AssertEquals(0, Length(ParseCommandsToml('', E)));
  AssertEquals('commands that is no table gives none', 0,
    Length(ParseCommandsToml('commands = "x"', E)));
end;

procedure TRepoCommandsTest.TestParseTomlNotToml;
var
  C: TGittanRepoCommands;
  E: string;
begin
  C := ParseCommandsToml('[commands.a]'#10'run = "x'#10, E);
  AssertEquals('no commands', 0, Length(C));
  AssertTrue('the reader''s message', E <> '');
  C := ParseCommandsToml('[commands.a]'#10'run = "x"'#10'[commands.a]'#10'run = "y"'#10, E);
  AssertEquals('a table twice is no TOML', 0, Length(C));
  AssertTrue(E <> '');
  C := ParseCommandsToml('[test]'#10'command = make test'#10, E);
  AssertEquals('an ini file is no TOML', 0, Length(C));
  AssertTrue(E <> '');
end;

procedure TRepoCommandsTest.TestParseTomlFields;
var
  C: TGittanRepoCommands;
  Err: string;
begin
  C := ParseCommandsToml(
    '[commands.a]'#10'run = "x"'#10'description = "  Does x  "'#10'confirm = true'#10 +
    '[commands.b]'#10'run = "y"'#10'confirm = "Really y?"'#10'hidden = true'#10 +
    '[commands.c]'#10'run = "z"'#10'confirm = ""'#10'hidden = "yes"'#10'description = 3'#10,
    Err);
  AssertEquals(Err, 3, Length(C));
  AssertEquals('the description is trimmed', 'Does x', C[0].Description);
  AssertTrue('confirm = true asks', C[0].Confirm);
  AssertEquals('with the plain question', '', C[0].ConfirmText);
  AssertFalse(C[0].Hidden);
  AssertTrue('a question of its own asks too', C[1].Confirm);
  AssertEquals('Really y?', C[1].ConfirmText);
  AssertTrue(C[1].Hidden);
  AssertFalse('an empty question asks nothing', C[2].Confirm);
  AssertFalse('a value of another type counts as missing', C[2].Hidden);
  AssertEquals('', C[2].Description);
end;

procedure TRepoCommandsTest.TestParseTomlPerSystem;
const
  Text = '[commands.both]'#10'run = { windows = "make.ps1", unix = "make" }'#10 +
    '[commands.mac]'#10'run.macos = "open ."'#10'run.default = "xdg-open ."'#10 +
    '[commands.winonly]'#10'run = { windows = "dir" }'#10'key = "W"'#10;
var
  C: TGittanRepoCommands;
  Err: string;
begin
  C := ParseCommandsToml(Text, Err, 'windows');
  AssertEquals(Err, 3, Length(C));
  AssertEquals('make.ps1', C[0].Command);
  AssertEquals('default when the system has none', 'xdg-open .', C[1].Command);
  AssertEquals('dir', C[2].Command);
  AssertFalse(C[2].Elsewhere);
  C := ParseCommandsToml(Text, Err, 'macos');
  AssertEquals('unix covers macOS', 'make', C[0].Command);
  AssertEquals('the system''s own comes first', 'open .', C[1].Command);
  AssertEquals('no line for this system', '', C[2].Command);
  AssertTrue('says so', C[2].Elsewhere);
  AssertEquals('and keeps its key', 'W', C[2].Key);
  C := ParseCommandsToml(Text, Err, 'linux');
  AssertEquals('make', C[0].Command);
  AssertEquals('xdg-open .', C[1].Command);
  AssertEquals('the detail is the line run', 'make', C[0].Detail);
end;

procedure TRepoCommandsTest.TestTomlProjects;
var
  N: TStringArray;
begin
  AssertFalse('no line', ParseCommandsTomlProjects('[commands.a]'#10'run = "x"'#10, N));
  AssertFalse('in a table it is none', ParseCommandsTomlProjects(
    '[commands]'#10'project = "rust"'#10, N));
  AssertFalse('no TOML', ParseCommandsTomlProjects('project = rust', N));
  AssertTrue(ParseCommandsTomlProjects('project = ["Rust", "go"]', N));
  AssertEquals(2, Length(N));
  AssertEquals('Rust', N[0]);
  AssertEquals('go', N[1]);
  AssertTrue('a string of names', ParseCommandsTomlProjects('project = "rust, go python"', N));
  AssertEquals(3, Length(N));
  AssertEquals('python', N[2]);
  AssertTrue(ParseCommandsTomlProjects('project = "none"', N));
  AssertEquals('none is no kind', 0, Length(N));
  AssertTrue(ParseCommandsTomlProjects('project = []', N));
  AssertEquals(0, Length(N));
  AssertFalse('a number is no list', ParseCommandsTomlProjects('project = 1', N));
end;

procedure TRepoCommandsTest.TestCommandsFiles;
var
  F: TGittanCommandsFiles;
  C: TGittanRepoCommands;
  P: TGittanProjects;
begin
  AssertEquals('none', 0, Length(ReadCommandsFiles(FDir)));
  AssertEquals(0, Length(ReadCommandsFiles('')));
  Put('.gittan/commands.ini', '[old]'#10'command = echo old'#10);
  Put('.gittan/commands/release.toml', '[commands.tag]'#10'run = "git tag"'#10);
  Put('.gittan/commands/Docs.toml', '[commands.docs]'#10'run = "make docs"'#10);
  Put('.gittan/commands/notes.txt', 'not a commands file');
  Put('.gittan/commands/broken.toml', '[commands.x'#10);
  F := ReadCommandsFiles(FDir);
  AssertEquals('the folder''s; an ini is no commands file', 3, Length(F));
  AssertEquals('by name, capitals first', '.gittan/commands/Docs.toml', F[0].Path);
  AssertEquals('.gittan/commands/broken.toml', F[1].Path);
  AssertEquals('no commands from a broken file', 0, Length(F[1].Commands));
  AssertTrue('and why', F[1].Error <> '');
  AssertEquals('.gittan/commands/release.toml', F[2].Path);
  AssertEquals('', F[2].Error);
  AssertEquals('the command knows its file', '.gittan/commands/release.toml',
    F[2].Commands[0].Project);
  Put('.gittan/commands.toml', 'project = "none"'#10'[commands.main]'#10'run = "echo main"'#10);
  F := ReadCommandsFiles(FDir);
  AssertEquals(4, Length(F));
  AssertEquals('commands.toml first', CommandsPath, F[0].Path);
  AssertTrue(F[0].HasProjects);
  C := DiscoverRepoCommands(FDir, P, F);
  AssertEquals('file by file', 3, Length(C));
  AssertEquals('main', C[0].Name);
  AssertEquals(CommandsPath, C[0].Project);
  AssertEquals('docs', C[1].Name);
  AssertEquals('tag', C[2].Name);
  AssertEquals('the files given back', 4, Length(F));
  Put('Cargo.toml', '[package]'#10'name = "x"'#10);
  C := DiscoverRepoCommands(FDir, P, F);
  AssertEquals('project = "none" keeps the kinds out', 0, Length(P));
  Put('.gittan/commands/release.toml', 'project = "none"'#10);
  Put('.gittan/commands.toml', '[commands.main]'#10'run = "echo main"'#10);
  AssertEquals('only commands.toml names the kinds', 1, Length(ProjectsOfRoot(FDir)));
end;

procedure TRepoCommandsTest.TestCommandsFileNames;
var
  F: TGittanCommandsFiles;
begin
  Put('.gittan/commands/CI.TOML', '[commands.ci]'#10'run = "make ci"'#10);
  Put('.gittan/commands/.draft.toml', '[commands.draft]'#10'run = "echo"'#10);
  Put('.gittan/commands/._ci.toml', 'macOS'' resource fork');
  F := ReadCommandsFiles(FDir);
  AssertEquals('a hidden file is left out', 1, Length(F));
  AssertEquals('the extension in any case, on every system', '.gittan/commands/CI.TOML',
    F[0].Path);
  AssertEquals('ci', F[0].Commands[0].Name);
end;

procedure TRepoCommandsTest.TestCommandsFileUnreadable;
{$ifndef windows}
var
  F: TGittanCommandsFiles;
  Name: string;
{$endif}
begin
  {$ifndef windows}
  Put('.gittan/commands/locked.toml', '[commands.x]'#10'run = "echo"'#10);
  Put('.gittan/commands/open.toml', '[commands.y]'#10'run = "echo"'#10);
  Name := IncludeTrailingPathDelimiter(FDir) + '.gittan/commands/locked.toml';
  FpChmod(Name, 0);
  try
    F := ReadCommandsFiles(FDir);
  finally
    FpChmod(Name, &644);
  end;
  AssertEquals('the file is listed still', 2, Length(F));
  { root reads it anyway }
  if FpGetuid <> 0 then
  begin
    AssertEquals('no commands from a file that cannot be read', 0, Length(F[0].Commands));
    AssertTrue('and why', F[0].Error <> '');
  end;
  AssertEquals('the next file is read', 'y', F[1].Commands[0].Name);
  {$endif}
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
  Put('.gittan/commands.toml', '[commands.lint]'#10'run = "npm run lint -- --fix"'#10'key = "L"'#10);
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
  Put('.gittan/commands.toml',
    '[commands.test]'#10'key = "T"'#10'terminal = true'#10 +
    '[commands.deps]'#10'key = "D"'#10 +
    '[commands.own]'#10'run = "echo own"'#10'key = "T"'#10 +
    '[commands.other]'#10'key = "X"'#10);
  Put('package.json', '{"scripts": {"test": "vitest run"}}');
  Put('Makefile', 'deps:'#10);
  C := DiscoverRepoCommands(FDir);
  AssertEquals('a keyed table taken by a script or target is no command of its own', 4,
    Length(C));
  AssertEquals('the file''s by name; one taken by nothing stays', 'other', C[0].Name);
  AssertEquals('', C[0].Command);
  AssertEquals('own', C[1].Name);
  AssertEquals('the first with a key keeps it', 'T', C[1].Key);
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
  Put('.gittan/commands.toml',
    '[commands.biuld]'#10'key = "B"'#10 +
    '[commands.own]'#10'run = "echo own"'#10'key = "O"'#10 +
    '[commands.build]'#10'key = "B"'#10);
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

procedure TRepoCommandsTest.TestDiscoverFieldsFromFile;
var
  C: TGittanRepoCommands;
begin
  Put('.gittan/commands.toml',
    '[commands.clean]'#10'confirm = "Remove lib?"'#10'description = "Removes lib"'#10);
  Put('Makefile', 'clean:'#10'build:'#10);
  C := DiscoverRepoCommands(FDir);
  AssertEquals(2, Length(C));
  AssertEquals('clean', C[0].Name);
  AssertEquals('make clean', C[0].Command);
  AssertTrue('the question comes with the section', C[0].Confirm);
  AssertEquals('Remove lib?', C[0].ConfirmText);
  AssertEquals('so does the description', 'Removes lib', C[0].Description);
  AssertFalse(C[1].Confirm);
end;

procedure TRepoCommandsTest.TestDiscoverHidden;
var
  C: TGittanRepoCommands;
begin
  Put('.gittan/commands.toml',
    '[commands.internal]'#10'hidden = true'#10'key = "I"'#10 +
    '[commands.secret]'#10'run = "echo"'#10'hidden = true'#10'key = "S"'#10 +
    '[commands.gone]'#10'hidden = true'#10 +
    '[commands.elsewhere]'#10'run = { nosuch = "x" }'#10'hidden = true'#10);
  Put('Makefile', 'internal:'#10'build:'#10);
  C := DiscoverRepoCommands(FDir);
  AssertEquals('hidden ones are left out; one naming nothing is kept', 2, Length(C));
  AssertEquals('gone', C[0].Name);
  AssertEquals('', C[0].Command);
  AssertEquals('build', C[1].Name);
  AssertEquals('a hidden one''s key runs nothing', -1, CommandByKey(C, 'I'));
  AssertEquals(-1, CommandByKey(C, 'S'));
end;

procedure TRepoCommandsTest.TestDiscoverElsewhere;
var
  C: TGittanRepoCommands;
begin
  { Lines for a system that is none: no line for this one, so the
    target of the same name is not given the section's key. }
  Put('.gittan/commands.toml', '[commands.build]'#10'run = { nosuch = "x" }'#10'key = "B"'#10);
  Put('Makefile', 'build:'#10);
  C := DiscoverRepoCommands(FDir);
  AssertEquals(2, Length(C));
  AssertTrue(C[0].Elsewhere);
  AssertEquals('', C[0].Command);
  AssertEquals('make build', C[1].Command);
  AssertEquals(#0, C[1].Key);
  AssertEquals('its key runs nothing', -1, CommandByKey(C, 'B'));
end;

procedure TRepoCommandsTest.TestDiscoverOverlap;
var
  C: TGittanRepoCommands;
begin
  Put('.gittan/commands.toml', '[commands.test]'#10'key = "T"'#10);
  Put('.gittan/commands/more.toml', '[commands.test]'#10'key = "X"'#10 +
    '[commands.nosuch]'#10'key = "N"'#10);
  Put('Makefile', 'test:'#10);
  C := DiscoverRepoCommands(FDir);
  AssertEquals(3, Length(C));
  AssertEquals('nosuch', C[0].Name);
  AssertEquals('one that names nothing overlaps nothing', '', C[0].Overlaps);
  AssertEquals('test', C[1].Name);
  AssertEquals('.gittan/commands/more.toml', C[1].Project);
  AssertEquals('the later one runs nothing', '', C[1].Command);
  AssertEquals('and names what the earlier took', 'make test', C[1].Overlaps);
  AssertEquals('make test', C[2].Command);
  AssertEquals('the earlier file''s key', 'T', C[2].Key);
  AssertEquals('', C[2].Overlaps);
  AssertEquals(-1, CommandByKey(C, 'X'));
end;

procedure TRepoCommandsTest.TestHash;
var
  H: string;
begin
  AssertEquals('no file, no hash', '', CommandsFileHash(FDir));
  AssertEquals('', CommandsFileHash(''));
  Put('.gittan/commands.toml', '[commands]'#10'a = "x"'#10);
  H := CommandsFileHash(FDir);
  AssertEquals('SHA-256 in hex', 64, Length(H));
  AssertEquals('the same text, the same hash', H, CommandsFileHash(FDir));
  Put('.gittan/commands.toml', '[commands]'#10'a = "y"'#10);
  AssertTrue('another text, another hash', H <> CommandsFileHash(FDir));
end;

procedure TRepoCommandsTest.TestHashOfFiles;
var
  H, H2: string;
begin
  AssertEquals('none, no hash', '', CommandsHashOf(nil));
  Put('.gittan/commands.toml', '[commands.a]'#10'run = "x"'#10);
  H := CommandsFileHash(FDir);
  AssertEquals(64, Length(H));
  AssertTrue('the TOML hashes with its path',
    H <> SHA256Print(SHA256String('[commands.a]'#10'run = "x"'#10)));
  Put('.gittan/commands/more.toml', '');
  H2 := CommandsFileHash(FDir);
  AssertTrue('a file added asks again, even an empty one', H <> H2);
  Put('.gittan/commands/more.toml', '# a comment'#10);
  AssertTrue('a file changed asks again', H2 <> CommandsFileHash(FDir));
  Put('.gittan/commands/more.toml', '');
  AssertEquals('the same files, the same hash', H2, CommandsFileHash(FDir));
end;

procedure TRepoCommandsTest.TestHashRenamed;
var
  H: string;
begin
  Put('.gittan/commands/a.toml', '[commands.a]'#10'run = "x"'#10);
  H := CommandsFileHash(FDir);
  DeleteFile(IncludeTrailingPathDelimiter(FDir) + SetDirSeparators('.gittan/commands/a.toml'));
  Put('.gittan/commands/b.toml', '[commands.a]'#10'run = "x"'#10);
  AssertTrue('a file renamed asks again', H <> CommandsFileHash(FDir));
end;

procedure TRepoCommandsTest.TestCommandByKey;
var
  C: TGittanRepoCommands;
  E: string;
begin
  C := ParseCommandsToml('[commands]'#10'a = "x"'#10'[commands.b]'#10'run = "y"'#10'key = "B"'#10, E);
  AssertEquals(1, CommandByKey(C, 'B'));
  AssertEquals(-1, CommandByKey(C, 'A'));
  AssertEquals('no key matches no command', -1, CommandByKey(C, #0));
end;

procedure TRepoCommandsTest.TestSplitName;
var
  C: TGittanRepoCommand;
  G, S: string;
begin
  C := Default(TGittanRepoCommand);
  C.Source := csPackage;
  C.Name := 'build:run';
  SplitCommandName(C, G, S);
  AssertEquals('build', G);
  AssertEquals('run', S);
  C.Name := 'build:run:fast';
  SplitCommandName(C, G, S);
  AssertEquals('the first colon splits', 'build', G);
  AssertEquals('run:fast', S);
  C.Name := 'build';
  SplitCommandName(C, G, S);
  AssertEquals('a plain name is its own group', 'build', G);
  AssertEquals('build', S);
  C.Name := ':x';
  SplitCommandName(C, G, S);
  AssertEquals('a leading colon is no group', ':x', G);
  C.Name := 'x:';
  SplitCommandName(C, G, S);
  AssertEquals('nor a trailing one', 'x:', G);
  AssertEquals('x:', S);
  C.Name := 'build-linux';
  SplitCommandName(C, G, S);
  AssertEquals('a dash is no separator for a script', 'build-linux', G);
  C.Source := csMake;
  SplitCommandName(C, G, S);
  AssertEquals('but is for a target', 'build', G);
  AssertEquals('linux', S);
  C.Source := csFile;
  C.Name := 'build-linux';
  SplitCommandName(C, G, S);
  AssertEquals('nor for the file''s', 'build-linux', G);
  C.Name := 'build:linux';
  SplitCommandName(C, G, S);
  AssertEquals('build', G);
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

{ A command that ignores SIGTERM is ended by force after KillGraceMs. }
procedure TRepoCommandsTest.TestJobKillForced;
{$ifndef windows}
var
  Job: TGittanCommandJob;
  Started: QWord;
{$endif}
begin
  {$ifndef windows}
  Job := TGittanCommandJob.Create(FDir, 'trap "" TERM; sleep 30; echo late');
  try
    Started := GetTickCount64;
    RunJob(Job, 300);
    AssertEquals(1, FDone);
    AssertTrue('ended by Kill', Job.Killed);
    AssertTrue('after the grace', GetTickCount64 - Started >= KillGraceMs);
    AssertTrue('long before the sleep', GetTickCount64 - Started < 15000);
    AssertEquals('the rest of the line did not run', 0, Pos('late', Job.Output));
  finally
    Job.Free;
  end;
  {$endif}
end;

{ A child that ignores SIGTERM under a shell that does not is ended by
  force too, after KillGraceMs, though the shell is gone by then. }
procedure TRepoCommandsTest.TestJobKillChild;
{$ifndef windows}
var
  Job: TGittanCommandJob;
  Started: QWord;
  Child, Waited: integer;
  Text: string;
{$endif}
begin
  {$ifndef windows}
  Job := TGittanCommandJob.Create(FDir,
    '/bin/sh -c ''trap "" TERM; echo child=$$; exec sleep 30'' & wait');
  try
    Started := GetTickCount64;
    RunJob(Job, 300);
    AssertEquals(1, FDone);
    AssertTrue('ended by Kill', Job.Killed);
    AssertTrue('after the grace', GetTickCount64 - Started >= KillGraceMs);
    AssertTrue('long before the sleep', GetTickCount64 - Started < 15000);
    Text := Job.Output;
    Text := Copy(Text, Pos('child=', Text) + 6, MaxInt);
    Child := StrToIntDef(Trim(Copy(Text, 1, Pos(#10, Text) - 1)), 0);
    AssertTrue('the child said who it is', Child > 0);
    { Reaped by init once killed, which may take a moment. }
    Waited := 0;
    while (FpKill(Child, 0) = 0) and (Waited < 2000) do
    begin
      Sleep(20);
      Inc(Waited, 20);
    end;
    AssertTrue('the child is gone', FpKill(Child, 0) <> 0);
  finally
    Job.Free;
  end;
  {$endif}
end;

initialization
  RegisterTest(TRepoCommandsTest);

end.
