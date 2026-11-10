unit testabsorb;

{** Tests of gittan.absorb: the old lines a block stands for, and
  against a real repository the base of the branch (with and without an
  upstream), the target of every block (a changed line, an addition
  between lines of one commit, a line older than the branch, a new
  file), and the run that puts them into their commits, all of them or
  some, with what is left staying in the work tree. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.git, gittan.absorb, testhelpers;

type
  TAbsorbTest = class(TTestCase)
  private
    FDir: string;
    FRepo: TGittanRepo;
    procedure Git(const AArgs: array of string);
    function GitOut(const AArgs: array of string): string;
    procedure WriteLines(const AName: string; const ALines: array of string);
    function ReadLines(const AName: string): string;
    procedure Commit(const AMessage: string);
    procedure MakeBranch;
    procedure ChangeWorkTree;
    function Build(APlan: TGittanAbsorbPlan; const APaths: array of string): string;
    function Subjects: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestBlockOldLines;
    procedure TestBaseRoot;
    procedure TestBaseUpstream;
    procedure TestBaseNoMergeBase;
    procedure TestBuild;
    procedure TestBuildEmptiedFile;
    procedure TestRunAll;
    procedure TestRunIntoFixup;
    procedure TestRunSome;
    procedure TestRunNothing;
    procedure TestRunStale;
    procedure TestRunMoved;
    procedure TestBuildMerges;
    procedure TestRunUndone;
    procedure TestRunRebaseRefused;
  end;

implementation

uses
  {$ifdef unix}BaseUnix,{$endif} gittan.keep, gittan.discard;

procedure TAbsorbTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-absorb-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
  Git(['init', '-q', '-b', 'main']);
  WriteLines('a.txt', ['one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
    'nine', 'ten']);
  WriteLines('b.txt', ['alpha', 'beta', 'gamma']);
  Commit('Base');
  FRepo := TGittanRepo.Create;
  AssertTrue(FRepo.Open(FDir));
end;

procedure TAbsorbTest.TearDown;
begin
  FRepo.Free;
  RemoveTree(FDir);
end;

procedure TAbsorbTest.Git(const AArgs: array of string);
var
  Output, Err: string;
begin
  if not RunGitIn(FDir, AArgs, Output, Err) then
    Fail('git ' + AArgs[0] + ' failed: ' + Err);
end;

function TAbsorbTest.GitOut(const AArgs: array of string): string;
var
  Err: string;
begin
  if not RunGitIn(FDir, AArgs, Result, Err) then
    Fail('git ' + AArgs[0] + ' failed: ' + Err);
  Result := Trim(Result);
end;

procedure TAbsorbTest.WriteLines(const AName: string; const ALines: array of string);
var
  Lines: TStringList;
  s: string;
begin
  Lines := TStringList.Create;
  try
    { LF on every system, so git show gives back what the asserts split. }
    Lines.LineBreak := #10;
    for s in ALines do
      Lines.Add(s);
    Lines.SaveToFile(IncludeTrailingPathDelimiter(FDir) + AName);
  finally
    Lines.Free;
  end;
end;

{ The file's lines joined with '|'. }
function TAbsorbTest.ReadLines(const AName: string): string;
var
  Lines: TStringList;
  i: integer;
begin
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(IncludeTrailingPathDelimiter(FDir) + AName);
    Result := '';
    for i := 0 to Lines.Count - 1 do
    begin
      if i > 0 then
        Result := Result + '|';
      Result := Result + Lines[i];
    end;
  finally
    Lines.Free;
  end;
end;

procedure TAbsorbTest.Commit(const AMessage: string);
begin
  Git(['add', '-A']);
  Git(['commit', '-q', '-m', AMessage]);
end;

{ Three commits on top of Base: "Change two" writes line 2 of a.txt,
  "Change five" lines 5 and 6, "Change beta" line 2 of b.txt. }
procedure TAbsorbTest.MakeBranch;
begin
  WriteLines('a.txt', ['one', 'two!', 'three', 'four', 'five', 'six', 'seven', 'eight',
    'nine', 'ten']);
  Commit('Change two');
  WriteLines('a.txt', ['one', 'two!', 'three', 'four', 'five!', 'six!', 'seven', 'eight',
    'nine', 'ten']);
  Commit('Change five');
  WriteLines('b.txt', ['alpha', 'beta!', 'gamma']);
  Commit('Change beta');
end;

{ The work tree: line 2 of a.txt again (Change two's), a line between
  5 and 6 (between Change five's), line 10 (Base's), line 2 of b.txt
  (Change beta's) and a new file. }
procedure TAbsorbTest.ChangeWorkTree;
begin
  WriteLines('a.txt', ['one', 'two!!', 'three', 'four', 'five!', 'five-b', 'six!', 'seven',
    'eight', 'nine', 'ten!']);
  WriteLines('b.txt', ['alpha', 'beta!!', 'gamma']);
  WriteLines('c.txt', ['new']);
end;

{ Builds the plan for APaths; the error, '' when it went through. }
function TAbsorbTest.Build(APlan: TGittanAbsorbPlan; const APaths: array of string): string;
var
  Paths: TStringList;
  s: string;
begin
  Paths := TStringList.Create;
  try
    for s in APaths do
      Paths.Add(s);
    if APlan.Build(FRepo, Paths, Result) then
      Result := '';
  finally
    Paths.Free;
  end;
end;

{ The subjects of the branch, newest first, joined with '|'. }
function TAbsorbTest.Subjects: string;
begin
  Result := StringReplace(GitOut(['log', '--format=%s']), #10, '|', [rfReplaceAll]);
end;

procedure TAbsorbTest.TestBlockOldLines;
var
  Lines: TStringList;
  AFrom, ATo, ABefore, AAfter: integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Add(' one');
    Lines.Add('-two');
    Lines.Add('-three');
    Lines.Add('+two!');
    Lines.Add(' four');
    Lines.Add('+four-b');
    Lines.Add(' five');
    Lines.Add('-six');
    { Lines 2 and 3 deleted, between 1 and 4. }
    BlockOldLines(Lines, 1, AFrom, ATo, ABefore, AAfter);
    AssertEquals('from', 2, AFrom);
    AssertEquals('to', 3, ATo);
    AssertEquals('before', 1, ABefore);
    AssertEquals('after', 4, AAfter);
    { An addition between 4 and 5. }
    BlockOldLines(Lines, 5, AFrom, ATo, ABefore, AAfter);
    AssertTrue('none deleted', ATo < AFrom);
    AssertEquals('before', 4, ABefore);
    AssertEquals('after', 5, AAfter);
    { Line 6 deleted at the end of the file. }
    BlockOldLines(Lines, 7, AFrom, ATo, ABefore, AAfter);
    AssertEquals('from', 6, AFrom);
    AssertEquals('to', 6, ATo);
    AssertEquals('before', 5, ABefore);
    AssertEquals('after', 0, AAfter);
    { An addition at the start of the file. }
    Lines.Clear;
    Lines.Add('+zero');
    Lines.Add(' one');
    BlockOldLines(Lines, 0, AFrom, ATo, ABefore, AAfter);
    AssertEquals('before', 0, ABefore);
    AssertEquals('after', 1, AAfter);
  finally
    Lines.Free;
  end;
end;

{ Without an upstream or a default branch the branch reaches back to
  the root; with only the root commit there is nothing to put changes
  into. }
procedure TAbsorbTest.TestBaseRoot;
var
  Onto, Err: string;
begin
  AssertFalse('root alone', AbsorbBase(FRepo, Onto, Err));
  AssertEquals(rsAbsorbNoCommits, Err);
  MakeBranch;
  AssertTrue('base: ' + Err, AbsorbBase(FRepo, Onto, Err));
  AssertEquals('the root', GitOut(['rev-parse', 'HEAD~3']), Onto);
end;

{ With an upstream the branch's commits are those since the merge base
  with it, so pushed commits are never rewritten. }
procedure TAbsorbTest.TestBaseUpstream;
var
  Origin, Onto, Err: string;
begin
  Origin := FDir + '-origin';
  Git(['init', '-q', '--bare', Origin]);
  try
    Git(['remote', 'add', 'origin', Origin]);
    Git(['push', '-q', '-u', 'origin', 'main']);
    MakeBranch;
    AssertTrue('base: ' + Err, AbsorbBase(FRepo, Onto, Err));
    AssertEquals('the pushed commit', GitOut(['rev-parse', 'origin/main']), Onto);
    Git(['push', '-q']);
    AssertFalse('all pushed', AbsorbBase(FRepo, Onto, Err));
    AssertEquals(rsAbsorbNoCommits, Err);
  finally
    RemoveTree(Origin);
  end;
end;

{ An upstream with no history in common gives no base rather than the
  last commits; one that is gone counts as none. }
procedure TAbsorbTest.TestBaseNoMergeBase;
var
  Origin, Other, Onto, Err: string;
begin
  Origin := FDir + '-origin';
  Other := FDir + '-other';
  Git(['init', '-q', '--bare', Origin]);
  Git(['init', '-q', '-b', 'main', Other]);
  try
    Git(['-C', Other, 'commit', '-q', '--allow-empty', '-m', 'Elsewhere']);
    Git(['-C', Other, 'push', '-q', Origin, 'main']);
    Git(['remote', 'add', 'origin', Origin]);
    Git(['fetch', '-q', 'origin']);
    Git(['branch', '-q', '-u', 'origin/main']);
    MakeBranch;
    AssertFalse('no merge base', AbsorbBase(FRepo, Onto, Err));
    AssertEquals(Format(rsAbsorbNoBase, ['origin/main']), Err);
    Git(['update-ref', '-d', 'refs/remotes/origin/main']);
    AssertTrue('gone: ' + Err, AbsorbBase(FRepo, Onto, Err));
    AssertEquals('the root', GitOut(['rev-parse', 'HEAD~3']), Onto);
  finally
    RemoveTree(Other);
    RemoveTree(Origin);
  end;
end;

procedure TAbsorbTest.TestBuild;
var
  Plan: TGittanAbsorbPlan;
  Pair: TGittanKeep;
begin
  MakeBranch;
  ChangeWorkTree;
  Plan := TGittanAbsorbPlan.Create;
  try
    AssertEquals('', Build(Plan, ['a.txt', 'b.txt', 'c.txt']));
    AssertEquals('steps', 3, Length(Plan.Steps));
    AssertEquals('Change two', Plan.Steps[0].Subject);
    AssertEquals('pushed', 0, Plan.Pushed);
    AssertEquals('hunks', 5, Length(Plan.Hunks));
    AssertEquals('a.txt', Plan.Hunks[0].Path);
    AssertEquals('line 2', 2, Plan.Hunks[0].Line);
    AssertEquals('two!! goes to Change two', 0, Plan.Hunks[0].Target);
    AssertEquals('five-b goes to Change five', 1, Plan.Hunks[1].Target);
    AssertEquals('ten! is older', -1, Plan.Hunks[2].Target);
    AssertEquals(rsAbsorbOlder, Plan.Hunks[2].Reason);
    AssertEquals('b.txt', Plan.Hunks[3].Path);
    AssertEquals('beta!! goes to Change beta', 2, Plan.Hunks[3].Target);
    AssertEquals('c.txt', Plan.Hunks[4].Path);
    AssertEquals('new file', -1, Plan.Hunks[4].Target);
    AssertEquals(rsAbsorbNewFile, Plan.Hunks[4].Reason);
    AssertEquals('placeable', 3, Plan.Placeable);
    AssertNotNull('diff kept', Plan.Diff('a.txt'));
    Pair.HasOld := True;
    Pair.HasNew := True;
    Pair.Old := 'two!';
    Pair.New := 'two!!';
    Pair.Line := 2;
    AssertEquals('found by its pair', 0, Plan.HunkOf('a.txt', Pair));
    Pair.Line := 3;
    AssertEquals('not at another line', -1, Plan.HunkOf('a.txt', Pair));
  finally
    Plan.Free;
  end;
end;

{ Every placeable hunk into its commit: three fixup commits folded in,
  the branch the same three commits with the changes in them, and the
  older line and the new file still in the work tree. }
procedure TAbsorbTest.TestRunAll;
var
  Plan: TGittanAbsorbPlan;
  Commits: integer;
  Conflicts, Stopped: boolean;
  Err: string;
begin
  MakeBranch;
  ChangeWorkTree;
  Plan := TGittanAbsorbPlan.Create;
  try
    AssertEquals('', Build(Plan, ['a.txt', 'b.txt', 'c.txt']));
    AssertTrue('run: ' + Err, AbsorbRun(FRepo, Plan, [True, True, True, True, True], [],
      Commits, Conflicts, Stopped, Err));
    AssertEquals('fixups', 3, Commits);
    AssertFalse(Conflicts);
    AssertFalse(Stopped);
    AssertEquals('Change beta|Change five|Change two|Base', Subjects);
    AssertEquals('Change two holds two!!', 'one|two!!|three|four|five|six|seven|eight|nine|ten',
      StringReplace(GitOut(['show', 'HEAD~2:a.txt']), #10, '|', [rfReplaceAll]));
    AssertEquals('Change five holds five-b',
      'one|two!!|three|four|five!|five-b|six!|seven|eight|nine|ten',
      StringReplace(GitOut(['show', 'HEAD~1:a.txt']), #10, '|', [rfReplaceAll]));
    AssertEquals('Change beta holds beta!!', 'alpha|beta!!|gamma',
      StringReplace(GitOut(['show', 'HEAD:b.txt']), #10, '|', [rfReplaceAll]));
    AssertEquals('the rest stays in the work tree', 'M a.txt|?? c.txt',
      StringReplace(GitOut(['status', '--porcelain']), #10, '|', [rfReplaceAll]));
    AssertEquals('one|two!!|three|four|five!|five-b|six!|seven|eight|nine|ten!',
      ReadLines('a.txt'));
    AssertEquals('', GitOut(['stash', 'list']));
  finally
    Plan.Free;
  end;
end;

{ A change of a commit that is a fixup of one not on the branch goes
  into that fixup, which stays a commit. }
procedure TAbsorbTest.TestRunIntoFixup;
var
  Plan: TGittanAbsorbPlan;
  Commits: integer;
  Conflicts, Stopped: boolean;
  Err: string;
begin
  WriteLines('b.txt', ['alpha', 'beta!', 'gamma']);
  Commit('fixup! Elsewhere');
  WriteLines('b.txt', ['alpha', 'beta!!', 'gamma']);
  Plan := TGittanAbsorbPlan.Create;
  try
    AssertEquals('', Build(Plan, ['b.txt']));
    AssertTrue('run: ' + Err, AbsorbRun(FRepo, Plan, [True], [], Commits, Conflicts,
      Stopped, Err));
    AssertEquals('fixup! Elsewhere|Base', Subjects);
    AssertEquals('alpha|beta!!|gamma',
      StringReplace(GitOut(['show', 'HEAD:b.txt']), #10, '|', [rfReplaceAll]));
    AssertEquals('', GitOut(['status', '--porcelain']));
  finally
    Plan.Free;
  end;
end;

{ Only b.txt's hunk chosen: one fixup, a.txt's changes all left in the
  work tree. }
procedure TAbsorbTest.TestRunSome;
var
  Plan: TGittanAbsorbPlan;
  Commits: integer;
  Conflicts, Stopped: boolean;
  Err: string;
begin
  MakeBranch;
  ChangeWorkTree;
  Plan := TGittanAbsorbPlan.Create;
  try
    AssertEquals('', Build(Plan, ['a.txt', 'b.txt', 'c.txt']));
    AssertTrue('run: ' + Err, AbsorbRun(FRepo, Plan, [False, False, False, True, True], [],
      Commits, Conflicts, Stopped, Err));
    AssertEquals('fixups', 1, Commits);
    AssertEquals('Change beta|Change five|Change two|Base', Subjects);
    AssertEquals('alpha|beta!!|gamma',
      StringReplace(GitOut(['show', 'HEAD:b.txt']), #10, '|', [rfReplaceAll]));
    AssertEquals('one|two!|three|four|five!|six!|seven|eight|nine|ten',
      StringReplace(GitOut(['show', 'HEAD:a.txt']), #10, '|', [rfReplaceAll]));
    AssertEquals('M a.txt|?? c.txt',
      StringReplace(GitOut(['status', '--porcelain']), #10, '|', [rfReplaceAll]));
    AssertEquals('one|two!!|three|four|five!|five-b|six!|seven|eight|nine|ten!',
      ReadLines('a.txt'));
  finally
    Plan.Free;
  end;
end;

{ Nothing chosen, or only hunks without a target: no commit, the
  branch untouched. }
procedure TAbsorbTest.TestRunNothing;
var
  Plan: TGittanAbsorbPlan;
  Commits: integer;
  Conflicts, Stopped: boolean;
  Err: string;
begin
  MakeBranch;
  ChangeWorkTree;
  Plan := TGittanAbsorbPlan.Create;
  try
    AssertEquals('', Build(Plan, ['a.txt', 'c.txt']));
    AssertFalse(AbsorbRun(FRepo, Plan, [False, False, True, True], [], Commits, Conflicts,
      Stopped, Err));
    AssertEquals(0, Commits);
    AssertEquals(rsAbsorbNothingChosen, Err);
    AssertEquals('Change beta|Change five|Change two|Base', Subjects);
  finally
    Plan.Free;
  end;
end;

{ A file changed since the plan was built stops the run, a file whose
  every hunk is chosen too, and so does one that is gone; nothing is
  committed. }
procedure TAbsorbTest.TestRunStale;
var
  Plan: TGittanAbsorbPlan;
  Commits: integer;
  Conflicts, Stopped: boolean;
  Err: string;
begin
  MakeBranch;
  ChangeWorkTree;
  Plan := TGittanAbsorbPlan.Create;
  try
    AssertEquals('', Build(Plan, ['a.txt', 'b.txt', 'c.txt']));
    WriteLines('b.txt', ['alpha', 'beta!!!', 'gamma']);
    AssertFalse('changed', AbsorbRun(FRepo, Plan, [False, False, False, True, True], [],
      Commits, Conflicts, Stopped, Err));
    AssertEquals('b.txt: ' + rsDiscardStale, Err);
    AssertEquals(0, Commits);
    DeleteFile(IncludeTrailingPathDelimiter(FDir) + 'b.txt');
    AssertFalse('gone', AbsorbRun(FRepo, Plan, [False, False, False, True, True], [],
      Commits, Conflicts, Stopped, Err));
    AssertTrue('the path in the error: ' + Err, Pos('b.txt: ', Err) = 1);
    AssertEquals(0, Commits);
    AssertEquals('Change beta|Change five|Change two|Base', Subjects);
  finally
    Plan.Free;
  end;
end;

{ A commit made after the plan was built stops the run before it writes
  anything. }
procedure TAbsorbTest.TestRunMoved;
var
  Plan: TGittanAbsorbPlan;
  Commits: integer;
  Conflicts, Stopped: boolean;
  Err: string;
begin
  MakeBranch;
  ChangeWorkTree;
  Plan := TGittanAbsorbPlan.Create;
  try
    AssertEquals('', Build(Plan, ['a.txt', 'b.txt']));
    Git(['add', 'c.txt']);
    Git(['commit', '-q', '-m', 'Add c']);
    AssertFalse(AbsorbRun(FRepo, Plan, [True, True, True, True], [], Commits, Conflicts,
      Stopped, Err));
    AssertEquals(rsAbsorbMoved, Err);
    AssertEquals(0, Commits);
    AssertEquals('Add c|Change beta|Change five|Change two|Base', Subjects);
  finally
    Plan.Free;
  end;
end;

{ A merge commit among the branch's commits: no plan, as the
  interactive rebase refuses such a range. }
{ A file emptied has only removed lines and is still there: blamed, not
  refused as deleted; one gone from disk is. }
procedure TAbsorbTest.TestBuildEmptiedFile;
var
  Plan: TGittanAbsorbPlan;
begin
  MakeBranch;
  WriteLines('b.txt', []);
  Plan := TGittanAbsorbPlan.Create;
  try
    AssertEquals('', Build(Plan, ['b.txt']));
    AssertEquals('hunks', 1, Length(Plan.Hunks));
    AssertTrue(Plan.Hunks[0].Reason, Plan.Hunks[0].Reason <> rsAbsorbDeletedFile);
    DeleteFile(IncludeTrailingPathDelimiter(FDir) + 'b.txt');
    AssertEquals('', Build(Plan, ['b.txt']));
    AssertEquals('hunks', 1, Length(Plan.Hunks));
    AssertEquals(rsAbsorbDeletedFile, Plan.Hunks[0].Reason);
  finally
    Plan.Free;
  end;
end;

procedure TAbsorbTest.TestBuildMerges;
var
  Plan: TGittanAbsorbPlan;
begin
  MakeBranch;
  Git(['switch', '-q', '-c', 'side', 'HEAD~1']);
  WriteLines('d.txt', ['side']);
  Commit('Side');
  Git(['switch', '-q', 'main']);
  Git(['merge', '-q', '--no-ff', '--no-edit', 'side']);
  ChangeWorkTree;
  Plan := TGittanAbsorbPlan.Create;
  try
    AssertEquals(rsAbsorbMerges, Build(Plan, ['a.txt', 'b.txt']));
  finally
    Plan.Free;
  end;
end;

{ The second fixup commit refused by a hook: the first is taken back,
  so the branch is as it was, nothing is staged and the work tree still
  has every change. }
procedure TAbsorbTest.TestRunUndone;
var
  Plan: TGittanAbsorbPlan;
  Commits: integer;
  Conflicts, Stopped: boolean;
  Err, Hook, Before: string;
begin
  MakeBranch;
  ChangeWorkTree;
  Before := GitOut(['rev-parse', 'HEAD']);
  Hook := IncludeTrailingPathDelimiter(FDir) + '.git' + PathDelim + 'hooks' + PathDelim +
    'commit-msg';
  ForceDirectories(ExtractFileDir(Hook));
  with TStringList.Create do
  try
    Add('#!/bin/sh');
    Add('if grep -q "Change five" "$1"; then exit 1; fi');
    Add('exit 0');
    TextLineBreakStyle := tlbsLF;
    SaveToFile(Hook);
  finally
    Free;
  end;
  {$ifdef unix}
  FpChmod(Hook, &755);
  {$endif}
  Plan := TGittanAbsorbPlan.Create;
  try
    AssertEquals('', Build(Plan, ['a.txt', 'b.txt', 'c.txt']));
    AssertFalse('refused', AbsorbRun(FRepo, Plan, [True, True, True, True, True], [],
      Commits, Conflicts, Stopped, Err));
    AssertEquals('no fixup left', 0, Commits);
    AssertEquals('HEAD as it was', Before, GitOut(['rev-parse', 'HEAD']));
    AssertEquals('Change beta|Change five|Change two|Base', Subjects);
    AssertEquals('nothing staged', '', GitOut(['diff', '--cached', '--name-only']));
    AssertEquals('one|two!!|three|four|five!|five-b|six!|seven|eight|nine|ten!',
      ReadLines('a.txt'));
    AssertEquals('alpha|beta!!|gamma', ReadLines('b.txt'));
  finally
    Plan.Free;
  end;
end;

{ A pre-rebase hook that refuses: git does not start the rebase, so the
  fixup commits are taken back as for a refused commit, and the branch,
  the index and the work tree are as they were. }
procedure TAbsorbTest.TestRunRebaseRefused;
var
  Plan: TGittanAbsorbPlan;
  Commits: integer;
  Conflicts, Stopped: boolean;
  Err, Hook, Before: string;
begin
  MakeBranch;
  ChangeWorkTree;
  Before := GitOut(['rev-parse', 'HEAD']);
  Hook := IncludeTrailingPathDelimiter(FDir) + '.git' + PathDelim + 'hooks' + PathDelim +
    'pre-rebase';
  ForceDirectories(ExtractFileDir(Hook));
  with TStringList.Create do
  try
    Add('#!/bin/sh');
    Add('exit 1');
    TextLineBreakStyle := tlbsLF;
    SaveToFile(Hook);
  finally
    Free;
  end;
  {$ifdef unix}
  FpChmod(Hook, &755);
  {$endif}
  Plan := TGittanAbsorbPlan.Create;
  try
    AssertEquals('', Build(Plan, ['a.txt', 'b.txt', 'c.txt']));
    AssertFalse('refused', AbsorbRun(FRepo, Plan, [True, True, True, True, True], [],
      Commits, Conflicts, Stopped, Err));
    AssertFalse('no conflicts', Conflicts);
    AssertFalse('not stopped', Stopped);
    AssertEquals('no fixup left', 0, Commits);
    AssertEquals('HEAD as it was', Before, GitOut(['rev-parse', 'HEAD']));
    AssertEquals('Change beta|Change five|Change two|Base', Subjects);
    AssertEquals('nothing staged', '', GitOut(['diff', '--cached', '--name-only']));
    AssertEquals('one|two!!|three|four|five!|five-b|six!|seven|eight|nine|ten!',
      ReadLines('a.txt'));
    AssertEquals('alpha|beta!!|gamma', ReadLines('b.txt'));
    AssertEquals('no stash left', '', GitOut(['stash', 'list']));
  finally
    Plan.Free;
  end;
end;

initialization
  RegisterTest(TAbsorbTest);

end.
