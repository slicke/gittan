unit testundo;

{** Tests of gittan.undo: branch tips read and sorted, the steps named,
  a plan refused once the branches moved, and against a real repository
  a commit, an amend, a merge, a switch, a branch made, deleted and
  renamed undone and redone, a commit's changes kept, and an undo git
  refuses over an uncommitted change. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.git, gittan.undo, testhelpers;

type
  TUndoTest = class(TTestCase)
  private
    FDir: string;
    FRepo: TGittanRepo;
    FHistory: TGittanUndoHistory;
    procedure Git(const AArgs: array of string);
    function Rev(const ARev: string): string;
    procedure WriteFile(const AName, AText: string);
    function ReadFile(const AName: string): string;
    procedure Commit(const AName, AText, AMessage: string);
    procedure Track;
    procedure Undo;
    procedure Redo;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestParseBranchTips;
    procedure TestDescribe;
    procedure TestParseHeadMove;
    procedure TestPlanStale;
    procedure TestCommit;
    procedure TestAmend;
    procedure TestCommitThenStash;
    procedure TestMerge;
    procedure TestSwitchAndCreate;
    procedure TestDeleteAndRename;
    procedure TestRefused;
    procedure TestRedoForgotten;
  end;

implementation

procedure TUndoTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-undo-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
  Git(['init', '-q', '-b', 'main']);
  Commit('a.txt', 'one', 'First');
  FRepo := TGittanRepo.Create;
  AssertTrue(FRepo.Open(FDir));
  FHistory := TGittanUndoHistory.Create;
  Track;
end;

procedure TUndoTest.TearDown;
begin
  FHistory.Free;
  FRepo.Free;
  RemoveTree(FDir);
end;

procedure TUndoTest.Git(const AArgs: array of string);
var
  Output, Err: string;
begin
  if not RunGitIn(FDir, AArgs, Output, Err) then
    Fail('git ' + AArgs[0] + ' failed: ' + Err);
end;

function TUndoTest.Rev(const ARev: string): string;
var
  Err: string;
begin
  if not RunGitIn(FDir, ['rev-parse', '-q', '--verify', ARev], Result, Err) then
    Result := '';
  Result := Trim(Result);
end;

procedure TUndoTest.WriteFile(const AName, AText: string);
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    Lines.SaveToFile(IncludeTrailingPathDelimiter(FDir) + AName);
  finally
    Lines.Free;
  end;
end;

function TUndoTest.ReadFile(const AName: string): string;
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(IncludeTrailingPathDelimiter(FDir) + AName);
    Result := Trim(Lines.Text);
  finally
    Lines.Free;
  end;
end;

procedure TUndoTest.Commit(const AName, AText, AMessage: string);
begin
  WriteFile(AName, AText);
  Git(['add', '-A']);
  Git(['commit', '-q', '-m', AMessage]);
end;

procedure TUndoTest.Track;
var
  S: TGittanRefState;
begin
  AssertTrue('read', FRepo.ReadRefState(S));
  FHistory.Track(S, False);
end;

procedure TUndoTest.Undo;
var
  Cur, S: TGittanRefState;
  Step: TGittanUndoStep;
  Steps: TGittanGitSteps;
  Err: string;
begin
  AssertTrue('can undo', FHistory.CanUndo);
  Step := FHistory.UndoStep;
  AssertTrue(FRepo.ReadRefState(Cur));
  AssertTrue('plan: ' + Err, PlanRefChange(Cur, Step.After, Step.Before, Step.Kind, [], Steps, Err));
  AssertTrue('run: ' + FRepo.Error, FRepo.RunSteps(Steps));
  AssertTrue(FRepo.ReadRefState(S));
  AssertTrue('as before', SameRefState(S, Step.Before));
  FHistory.Undone(S);
end;

procedure TUndoTest.Redo;
var
  Cur, S: TGittanRefState;
  Step: TGittanUndoStep;
  Steps: TGittanGitSteps;
  Err: string;
begin
  AssertTrue('can redo', FHistory.CanRedo);
  Step := FHistory.RedoStep;
  AssertTrue(FRepo.ReadRefState(Cur));
  AssertTrue('plan: ' + Err, PlanRefChange(Cur, Step.Before, Step.After, Step.Kind, [], Steps, Err));
  AssertTrue('run: ' + FRepo.Error, FRepo.RunSteps(Steps));
  AssertTrue(FRepo.ReadRefState(S));
  AssertTrue('as after', SameRefState(S, Step.After));
  FHistory.Redone(S);
end;

procedure TUndoTest.TestParseBranchTips;
var
  T: TGittanBranchTips;
begin
  T := ParseBranchTips('bbb refs/heads/zeta' + LineEnding + 'aaa refs/heads/alpha' +
    LineEnding + 'ccc refs/tags/v1' + LineEnding + LineEnding + 'ddd refs/heads/mid/dle');
  AssertEquals(3, Length(T));
  AssertEquals('alpha', T[0].Name);
  AssertEquals('aaa', T[0].Id);
  AssertEquals('mid/dle', T[1].Name);
  AssertEquals('zeta', T[2].Name);
end;

procedure TUndoTest.TestDescribe;
var
  A, B: TGittanRefState;
  Kind: TGittanUndoKind;

  function State(const ABranch, AHead, AMove: string; const ATips: array of string): TGittanRefState;
  var
    i: integer;
    Text: string;
  begin
    Text := '';
    for i := 0 to High(ATips) div 2 do
      Text := Text + ATips[2 * i + 1] + ' refs/heads/' + ATips[2 * i] + LineEnding;
    Result := Default(TGittanRefState);
    Result.Valid := True;
    Result.Branch := ABranch;
    Result.Head := AHead;
    Result.Move := AMove;
    Result.Tips := ParseBranchTips(Text);
  end;

begin
  A := State('main', '1111111aaa', '', ['main', '1111111aaa']);
  B := State('main', '2222222bbb', 'commit: Fix the thing', ['main', '2222222bbb']);
  AssertEquals('Commit "Fix the thing"', DescribeStep(A, B, Kind));
  AssertTrue(Kind = ukCommit);
  B.Move := 'commit (amend): Fix it';
  AssertEquals('Amend "Fix it"', DescribeStep(A, B, Kind));
  AssertTrue(Kind = ukCommit);
  B.Move := 'merge feature: Merge made by the ''ort'' strategy.';
  AssertEquals('Merge feature', DescribeStep(A, B, Kind));
  AssertTrue(Kind = ukOther);
  B.Move := 'reset: moving to HEAD~1';
  AssertEquals('Reset to 2222222', DescribeStep(A, B, Kind));
  B.Move := 'pull: Fast-forward';
  AssertEquals('Pull', DescribeStep(A, B, Kind));
  B.Move := 'rebase (finish): returning to refs/heads/main';
  AssertEquals('Rebase', DescribeStep(A, B, Kind));
  B.Move := 'cherry-pick: Port it';
  AssertEquals('Cherry-pick "Port it"', DescribeStep(A, B, Kind));
  B.Move := 'commit: ' + StringOfChar('x', 60);
  AssertEquals('a long subject is cut', 'Commit "' + StringOfChar('x', 39) + '…"',
    DescribeStep(A, B, Kind));
  { A character across the cut is left out whole. }
  B.Move := 'commit: ' + StringOfChar('x', 38) + 'ä' + StringOfChar('x', 20);
  AssertEquals('cut at a character', 'Commit "' + StringOfChar('x', 38) + '…"',
    DescribeStep(A, B, Kind));

  A := State('main', '1111111aaa', '', ['dev', '3333333ccc', 'main', '1111111aaa']);
  B := State('dev', '3333333ccc', 'checkout: moving from main to dev',
    ['dev', '3333333ccc', 'main', '1111111aaa']);
  AssertEquals('Switch to dev', DescribeStep(A, B, Kind));
  B := State('', '3333333ccc', 'checkout: moving from main to 3333333ccc',
    ['dev', '3333333ccc', 'main', '1111111aaa']);
  AssertEquals('Switch to 3333333', DescribeStep(A, B, Kind));
  B := State('new', '1111111aaa', 'checkout: moving from main to new',
    ['dev', '3333333ccc', 'main', '1111111aaa', 'new', '1111111aaa']);
  AssertEquals('switch -c', 'Create Branch new', DescribeStep(A, B, Kind));

  B := State('main', '1111111aaa', '', ['dev', '3333333ccc', 'main', '1111111aaa',
    'topic', '3333333ccc']);
  AssertEquals('Create Branch topic', DescribeStep(A, B, Kind));
  B := State('main', '1111111aaa', '', ['main', '1111111aaa']);
  AssertEquals('Delete Branch dev', DescribeStep(A, B, Kind));
  B := State('main', '1111111aaa', '', ['main', '1111111aaa', 'work', '3333333ccc']);
  AssertEquals('Rename Branch dev to work', DescribeStep(A, B, Kind));
  B := State('main', '1111111aaa', '', ['dev', '4444444ddd', 'main', '1111111aaa']);
  AssertEquals('Move Branch dev', DescribeStep(A, B, Kind));
  B := State('trunk', '1111111aaa', 'Branch: renamed refs/heads/main to refs/heads/trunk',
    ['dev', '3333333ccc', 'trunk', '1111111aaa']);
  AssertEquals('HEAD''s own branch', 'Rename Branch main to trunk', DescribeStep(A, B, Kind));
end;

procedure TUndoTest.TestPlanStale;
var
  A, B, C: TGittanRefState;
  Steps: TGittanGitSteps;
  Err: string;
begin
  A := Default(TGittanRefState);
  A.Valid := True;
  A.Branch := 'main';
  A.Head := '1111111';
  A.Tips := ParseBranchTips('1111111 refs/heads/main');
  B := A;
  B.Head := '2222222';
  B.Tips := ParseBranchTips('2222222 refs/heads/main');
  C := B;
  C.Head := '3333333';
  C.Tips := ParseBranchTips('3333333 refs/heads/main');
  AssertFalse('moved since', PlanRefChange(C, B, A, ukCommit, [], Steps, Err));
  AssertTrue(Err <> '');
  AssertTrue(PlanRefChange(B, B, A, ukCommit, [], Steps, Err));
  AssertEquals(1, Length(Steps));
  AssertEquals('reset', Steps[0][0]);
  AssertEquals('--soft', Steps[0][1]);
  AssertTrue(PlanRefChange(B, B, A, ukOther, [], Steps, Err));
  AssertEquals('--keep', Steps[0][1]);
  A.Head := '';
  A.Tips := nil;
  AssertFalse('before the first commit', PlanRefChange(B, B, A, ukCommit, [], Steps, Err));

  { A branch another worktree has checked out is not moved, deleted or
    switched to; HEAD's own is reset as before. }
  A := Default(TGittanRefState);
  A.Valid := True;
  A.Branch := 'main';
  A.Head := '1111111';
  A.Tips := ParseBranchTips('1111111 refs/heads/main'#10'4444444 refs/heads/wt');
  B := A;
  B.Tips := ParseBranchTips('1111111 refs/heads/main'#10'5555555 refs/heads/wt');
  AssertFalse('moved elsewhere', PlanRefChange(B, B, A, ukOther, ['wt'], Steps, Err));
  AssertEquals('wt is checked out in another worktree', Err);
  AssertEquals(0, Length(Steps));
  AssertTrue(PlanRefChange(B, B, A, ukOther, ['other'], Steps, Err));
  B := A;
  B.Tips := ParseBranchTips('1111111 refs/heads/main');
  AssertFalse('deleted elsewhere', PlanRefChange(A, A, B, ukOther, ['wt'], Steps, Err));
  B := A;
  B.Branch := 'wt';
  B.Head := '4444444';
  AssertFalse('switched to elsewhere', PlanRefChange(A, A, B, ukOther, ['wt'], Steps, Err));
  B := A;
  B.Head := '2222222';
  B.Tips := ParseBranchTips('2222222 refs/heads/main'#10'4444444 refs/heads/wt');
  AssertTrue('HEAD''s own', PlanRefChange(B, B, A, ukCommit, ['wt'], Steps, Err));
end;

procedure TUndoTest.TestCommit;
var
  First, Second: string;
begin
  First := Rev('HEAD');
  Commit('a.txt', 'two', 'Second');
  Second := Rev('HEAD');
  Track;
  AssertEquals('Commit "Second"', FHistory.UndoStep.Title);
  Undo;
  AssertEquals('back', First, Rev('HEAD'));
  AssertEquals('the change stays in the file', 'two', ReadFile('a.txt'));
  AssertFalse(FHistory.CanUndo);
  Redo;
  AssertEquals('again', Second, Rev('HEAD'));
  Track;
  AssertFalse('the redo is no new step', FHistory.CanRedo);
  AssertTrue(FHistory.CanUndo);
end;

procedure TUndoTest.TestParseHeadMove;
begin
  AssertEquals('the newest', 'commit: Two',
    ParseHeadMove('bbb commit: Two'#10'aaa commit (initial): One', 'bbb'));
  AssertEquals('past the resets that moved nothing', 'commit: Two',
    ParseHeadMove('bbb reset: moving to HEAD'#10'bbb reset: moving to HEAD'#10 +
    'bbb commit: Two'#10'aaa commit (initial): One', 'bbb'));
  AssertEquals('a reset that moved HEAD', 'reset: moving to HEAD~1',
    ParseHeadMove('aaa reset: moving to HEAD'#10'aaa reset: moving to HEAD~1'#10 +
    'bbb commit: Two', 'aaa'));
  AssertEquals('a switch at the same commit stays', 'checkout: moving from main to dev',
    ParseHeadMove('bbb checkout: moving from main to dev'#10'bbb commit: Two', 'bbb'));
  AssertEquals('the oldest read stands', 'reset: moving to HEAD',
    ParseHeadMove('bbb reset: moving to HEAD', 'bbb'));
  AssertEquals('not where HEAD is', '', ParseHeadMove('bbb commit: Two', 'ccc'));
  AssertEquals('none', '', ParseHeadMove('', 'bbb'));
end;

procedure TUndoTest.TestCommitThenStash;
var
  First: string;
begin
  { A commit and then a stash and an unstaging reset elsewhere, all
    before a snapshot: the step is still the commit, undone softly. }
  First := Rev('HEAD');
  Commit('a.txt', 'two', 'Second');
  WriteFile('a.txt', 'three');
  Git(['stash', '-q']);
  WriteFile('b.txt', 'new');
  Git(['add', 'b.txt']);
  Git(['reset', '-q']);
  Track;
  AssertEquals('Commit "Second"', FHistory.UndoStep.Title);
  AssertTrue('soft', FHistory.UndoStep.Kind = ukCommit);
  Undo;
  AssertEquals(First, Rev('HEAD'));
  AssertEquals('the commit''s change stays in the file', 'two', ReadFile('a.txt'));
end;

procedure TUndoTest.TestAmend;
var
  First: string;
begin
  First := Rev('HEAD');
  WriteFile('a.txt', 'amended');
  Git(['commit', '-q', '-a', '--amend', '-m', 'First, amended']);
  Track;
  AssertEquals('Amend "First, amended"', FHistory.UndoStep.Title);
  Undo;
  AssertEquals(First, Rev('HEAD'));
  AssertEquals('amended', ReadFile('a.txt'));
end;

procedure TUndoTest.TestMerge;
var
  Before: string;
begin
  Git(['switch', '-q', '-c', 'feature']);
  Commit('b.txt', 'feature', 'Feature');
  Git(['switch', '-q', 'main']);
  Commit('a.txt', 'main', 'Main');
  Before := Rev('HEAD');
  Track;
  Git(['merge', '-q', '--no-edit', 'feature']);
  Track;
  AssertEquals('Merge feature', FHistory.UndoStep.Title);
  Undo;
  AssertEquals(Before, Rev('HEAD'));
  AssertFalse('the merge''s file is gone', FileExists(IncludeTrailingPathDelimiter(FDir) +
    'b.txt'));
  Redo;
  AssertTrue(FileExists(IncludeTrailingPathDelimiter(FDir) + 'b.txt'));
end;

procedure TUndoTest.TestSwitchAndCreate;
var
  S: TGittanRefState;
begin
  Git(['switch', '-q', '-c', 'topic']);
  Track;
  AssertEquals('Create Branch topic', FHistory.UndoStep.Title);
  Undo;
  AssertTrue(FRepo.ReadRefState(S));
  AssertEquals('main', S.Branch);
  AssertEquals('topic is gone', '', Rev('refs/heads/topic'));
  Redo;
  AssertTrue(FRepo.ReadRefState(S));
  AssertEquals('topic', S.Branch);
  Commit('t.txt', 't', 'On topic');
  Track;
  Git(['switch', '-q', 'main']);
  Track;
  AssertEquals('Switch to main', FHistory.UndoStep.Title);
  Undo;
  AssertTrue(FRepo.ReadRefState(S));
  AssertEquals('topic', S.Branch);
end;

procedure TUndoTest.TestDeleteAndRename;
var
  Tip, Output, Err: string;
begin
  Git(['branch', 'old']);
  Git(['switch', '-q', 'old']);
  Commit('o.txt', 'o', 'On old');
  Tip := Rev('HEAD');
  Git(['switch', '-q', 'main']);
  Track;
  Git(['branch', '-D', 'old']);
  Track;
  AssertEquals('Delete Branch old', FHistory.UndoStep.Title);
  Undo;
  AssertEquals('made again at its tip', Tip, Rev('refs/heads/old'));
  Git(['config', 'branch.old.merge', 'refs/heads/old']);
  Git(['branch', '-m', 'old', 'renamed']);
  Track;
  AssertEquals('Rename Branch old to renamed', FHistory.UndoStep.Title);
  Undo;
  AssertEquals(Tip, Rev('refs/heads/old'));
  AssertEquals('', Rev('refs/heads/renamed'));
  AssertTrue(RunGitIn(FDir, ['config', 'branch.old.merge'], Output, Err));
  AssertEquals('its config back with it', 'refs/heads/old', Trim(Output));
  { HEAD's own branch. }
  Git(['branch', '-m', 'main', 'trunk']);
  Track;
  AssertEquals('Rename Branch main to trunk', FHistory.UndoStep.Title);
  Undo;
  AssertTrue(Rev('refs/heads/main') <> '');
  AssertEquals('', Rev('refs/heads/trunk'));
end;

procedure TUndoTest.TestRefused;
var
  Cur: TGittanRefState;
  Step: TGittanUndoStep;
  Steps: TGittanGitSteps;
  Err: string;
begin
  Git(['switch', '-q', '-c', 'feature']);
  Commit('b.txt', 'feature', 'Feature');
  Git(['switch', '-q', 'main']);
  Track;
  Git(['merge', '-q', '--no-edit', 'feature']);
  Track;
  { An uncommitted change to the file the merge brought: --keep refuses
    to take it away. }
  WriteFile('b.txt', 'mine');
  Step := FHistory.UndoStep;
  AssertTrue(FRepo.ReadRefState(Cur));
  AssertTrue(PlanRefChange(Cur, Step.After, Step.Before, Step.Kind, [], Steps, Err));
  AssertFalse('git refuses', FRepo.RunSteps(Steps));
  AssertTrue(FRepo.Error <> '');
  AssertEquals('the change is kept', 'mine', ReadFile('b.txt'));
end;

procedure TUndoTest.TestRedoForgotten;
begin
  Commit('a.txt', 'two', 'Second');
  Track;
  Undo;
  AssertTrue(FHistory.CanRedo);
  Commit('a.txt', 'three', 'Third');
  Track;
  AssertFalse('a new step forgets what was undone', FHistory.CanRedo);
  AssertEquals('Commit "Third"', FHistory.UndoStep.Title);
end;

initialization
  RegisterTest(TUndoTest);
end.
