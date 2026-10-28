unit gittan.undo;

{** Undo and Redo of what moved the branches: a commit, an amend, a
  merge, a cherry-pick, a revert, a reset, a pull, a rebase, a switch,
  a branch made, deleted or renamed.

  The frame reads the state of the branches (TGittanRefState: the branch
  HEAD is on, the commit it is on, every local branch's tip and the
  newest entry of HEAD's reflog) with every snapshot and gives it to
  TGittanUndoHistory.Track. A state that differs from the one before is
  a step, named from the reflog's entry or from the branches that came,
  went or moved (DescribeStep). While git is in the middle of something
  (a rebase, a merge with conflicts, a bisect) nothing is noted, so the
  whole of it is one step once it ends.

  A step is undone by putting the branches back as they were before it
  and redone by putting them as they were after (PlanRefChange gives the
  git commands), and only while they are still as the step left them:
  anything that moved them since makes it a step of its own first. A
  commit or an amend is undone with reset --soft, so its changes stay;
  everything else with reset --keep or a switch, which git refuses when
  an uncommitted change is in the way, and branches other than HEAD's
  with update-ref given the tip it expects. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils;

type
  TGittanBranchTip = record
    Name, Id: string;
  end;
  {** Sorted by name. }
  TGittanBranchTips = array of TGittanBranchTip;

  {** Where the branches are. Branch is the one HEAD is on, '' while it
    is detached; Head the commit HEAD is on, '' before the first commit;
    Move the newest entry of HEAD's reflog ("commit: Fix", "checkout:
    moving from main to dev"), which names what moved it. Valid once
    read. }
  TGittanRefState = record
    Valid: boolean;
    Branch, Head, Move: string;
    Tips: TGittanBranchTips;
  end;

  {** How a step moves HEAD's branch back: ukCommit with reset --soft,
    so the commit's changes stay (a commit, an amend), ukOther with
    reset --keep. }
  TGittanUndoKind = (ukCommit, ukOther);

  TGittanUndoStep = record
    Before, After: TGittanRefState;
    Kind: TGittanUndoKind;
    Title: string;
  end;
  TGittanUndoSteps = array of TGittanUndoStep;

  TGittanGitSteps = array of TStringArray;

  { TGittanUndoHistory }

  TGittanUndoHistory = class
  private
    FSteps: TGittanUndoSteps;
    { How many of FSteps are done; those after are undone, for Redo. }
    FDone: integer;
    FBase: TGittanRefState;
    FMax: integer;
  public
    {** A history of at most AMax steps, the oldest dropped first. }
    constructor Create(AMax: integer = 50);
    {** The branches are as AState says: when they differ from the state
      noted last, the change is a step to undo and the steps undone are
      forgotten. ABusy (git in the middle of something) notes nothing,
      so the state from before it stays the one compared with. }
    procedure Track(const AState: TGittanRefState; ABusy: boolean);
    function CanUndo: boolean;
    function CanRedo: boolean;
    {** The step Undo would undo; only while CanUndo. }
    function UndoStep: TGittanUndoStep;
    {** The step Redo would do again; only while CanRedo. }
    function RedoStep: TGittanUndoStep;
    {** UndoStep was undone and the branches are now as AState says. }
    procedure Undone(const AState: TGittanRefState);
    {** RedoStep was done again and the branches are as AState says. }
    procedure Redone(const AState: TGittanRefState);
    {** Forgets every step and the state, as when another repository is
      opened. }
    procedure Clear;
  end;

{** The branch tips of `git for-each-ref --format='%(objectname)
  %(refname)' refs/heads`, sorted by name. }
function ParseBranchTips(const AOutput: string): TGittanBranchTips;

{** Whether the branches and HEAD are the same in A and B (Move aside). }
function SameRefState(const A, B: TGittanRefState): boolean;

{** A name for the step from ABefore to AAfter, for Undo <name> and
  Redo <name>, and how HEAD's branch goes back over it. }
function DescribeStep(const ABefore, AAfter: TGittanRefState;
  out AKind: TGittanUndoKind): string;

{** The git commands that put the branches from AFrom as AKind's step
  left them to ATo: the branches ATo has and AFrom lacks made again,
  the other branches moved, HEAD switched or reset, and the branches
  ATo lacks deleted. False with AError when ACurrent is not AFrom (the
  branches moved since), when ATo is before the first commit, or when
  it would move, delete or switch to a branch of AElsewhere (those
  checked out in another worktree, which git would leave with a HEAD
  that does not match its files, or refuse halfway). }
function PlanRefChange(const ACurrent, AFrom, ATo: TGittanRefState; AKind: TGittanUndoKind;
  const AElsewhere: array of string; out ASteps: TGittanGitSteps;
  out AError: string): boolean;

implementation

resourcestring
  rsUndoCommit = 'Commit "%s"';
  rsUndoAmend = 'Amend "%s"';
  rsUndoMerge = 'Merge %s';
  rsUndoMergeDone = 'Merge';
  rsUndoSwitch = 'Switch to %s';
  rsUndoDetach = 'Switch to %s';
  rsUndoReset = 'Reset to %s';
  rsUndoCherryPick = 'Cherry-pick "%s"';
  rsUndoRevert = 'Revert "%s"';
  rsUndoPull = 'Pull';
  rsUndoRebase = 'Rebase';
  rsUndoCreate = 'Create Branch %s';
  rsUndoDelete = 'Delete Branch %s';
  rsUndoRename = 'Rename Branch %s to %s';
  rsUndoMove = 'Move Branch %s';
  rsUndoChange = 'Branch Changes';
  rsUndoMoved = 'The branches changed since; Refresh and try again';
  rsUndoFirst = 'Nothing comes before the first commit';
  rsUndoElsewhere = '%s is checked out in another worktree';

const
  { The longest subject a title quotes. }
  TitleChars = 40;
  HeadsPrefix = 'refs/heads/';

function ParseBranchTips(const AOutput: string): TGittanBranchTips;
var
  Lines: TStringList;
  i, j, Space: integer;
  Line, Name: string;
  Tip: TGittanBranchTip;
begin
  Result := nil;
  Lines := TStringList.Create;
  try
    Lines.Text := AOutput;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[i]);
      Space := Pos(' ', Line);
      if Space = 0 then
        Continue;
      Name := Copy(Line, Space + 1, MaxInt);
      if not AnsiStartsStr(HeadsPrefix, Name) then
        Continue;
      Tip.Id := Copy(Line, 1, Space - 1);
      Tip.Name := Copy(Name, Length(HeadsPrefix) + 1, MaxInt);
      { Insertion keeps them sorted by name, as CompareStr orders. }
      j := Length(Result);
      SetLength(Result, j + 1);
      while (j > 0) and (CompareStr(Result[j - 1].Name, Tip.Name) > 0) do
      begin
        Result[j] := Result[j - 1];
        Dec(j);
      end;
      Result[j] := Tip;
    end;
  finally
    Lines.Free;
  end;
end;

function TipOf(const AState: TGittanRefState; const AName: string; out AId: string): boolean;
var
  i: integer;
begin
  for i := 0 to High(AState.Tips) do
    if AState.Tips[i].Name = AName then
    begin
      AId := AState.Tips[i].Id;
      Exit(True);
    end;
  AId := '';
  Result := False;
end;

function SameRefState(const A, B: TGittanRefState): boolean;
var
  i: integer;
begin
  Result := (A.Branch = B.Branch) and (A.Head = B.Head) and (Length(A.Tips) = Length(B.Tips));
  if Result then
    for i := 0 to High(A.Tips) do
      if (A.Tips[i].Name <> B.Tips[i].Name) or (A.Tips[i].Id <> B.Tips[i].Id) then
        Exit(False);
end;

function Cut(const AText: string): string;
var
  n: integer;
begin
  Result := Trim(AText);
  if Length(Result) > TitleChars then
  begin
    { At a character's start, not in the bytes of one. }
    n := TitleChars - 1;
    while (n > 0) and (Ord(Result[n + 1]) and $C0 = $80) do
      Dec(n);
    Result := TrimRight(Copy(Result, 1, n)) + '…';
  end;
end;

function Short(const AId: string): string;
begin
  Result := Copy(AId, 1, 7);
end;

{ The subject after "<what>: " in a reflog entry. }
function After(const AMove, APrefix: string): string;
begin
  Result := Copy(AMove, Length(APrefix) + 1, MaxInt);
  if AnsiStartsStr(':', Result) then
    Delete(Result, 1, 1);
  Result := Trim(Result);
end;

{ The branches that came, went and moved between ABefore and AAfter:
  one that went and one that came at the same tip is a rename. }
function DescribeBranches(const ABefore, AAfter: TGittanRefState): string;
var
  Came, Went, Moved: TStringList;
  i: integer;
  Id, CameId, WentId: string;
begin
  Came := TStringList.Create;
  Went := TStringList.Create;
  Moved := TStringList.Create;
  try
    for i := 0 to High(AAfter.Tips) do
      if not TipOf(ABefore, AAfter.Tips[i].Name, Id) then
        Came.Add(AAfter.Tips[i].Name)
      else if Id <> AAfter.Tips[i].Id then
        Moved.Add(AAfter.Tips[i].Name);
    for i := 0 to High(ABefore.Tips) do
      if not TipOf(AAfter, ABefore.Tips[i].Name, Id) then
        Went.Add(ABefore.Tips[i].Name);
    if (Came.Count = 1) and (Went.Count = 1) and (Moved.Count = 0) then
    begin
      TipOf(AAfter, Came[0], CameId);
      TipOf(ABefore, Went[0], WentId);
      if CameId = WentId then
        Exit(Format(rsUndoRename, [Went[0], Came[0]]));
    end;
    if (Came.Count = 1) and (Went.Count = 0) and (Moved.Count = 0) then
      Result := Format(rsUndoCreate, [Came[0]])
    else if (Came.Count = 0) and (Went.Count = 1) and (Moved.Count = 0) then
      Result := Format(rsUndoDelete, [Went[0]])
    else if (Came.Count = 0) and (Went.Count = 0) and (Moved.Count = 1) then
      Result := Format(rsUndoMove, [Moved[0]])
    else
      Result := rsUndoChange;
  finally
    Came.Free;
    Went.Free;
    Moved.Free;
  end;
end;

function DescribeStep(const ABefore, AAfter: TGittanRefState;
  out AKind: TGittanUndoKind): string;
var
  Move, Rest, Id: string;
  p: integer;
begin
  AKind := ukOther;
  Result := '';
  Move := AAfter.Move;
  { HEAD stayed: what the branches did says it, as the reflog does not. }
  if (ABefore.Branch = AAfter.Branch) and (ABefore.Head = AAfter.Head) then
    Exit(DescribeBranches(ABefore, AAfter));
  { A rename of HEAD's own branch moves HEAD's name, not the commit. }
  if (ABefore.Head = AAfter.Head) and (ABefore.Branch <> '') and (AAfter.Branch <> '') and
    not TipOf(AAfter, ABefore.Branch, Id) and not TipOf(ABefore, AAfter.Branch, Id) then
    Exit(DescribeBranches(ABefore, AAfter));
  if AnsiStartsStr('commit (amend)', Move) then
  begin
    AKind := ukCommit;
    Result := Format(rsUndoAmend, [Cut(After(Move, 'commit (amend)'))]);
  end
  else if AnsiStartsStr('commit (merge)', Move) then
    Result := rsUndoMergeDone
  else if AnsiStartsStr('commit (initial)', Move) then
  begin
    AKind := ukCommit;
    Result := Format(rsUndoCommit, [Cut(After(Move, 'commit (initial)'))]);
  end
  else if AnsiStartsStr('commit:', Move) then
  begin
    AKind := ukCommit;
    Result := Format(rsUndoCommit, [Cut(After(Move, 'commit'))]);
  end
  else if AnsiStartsStr('merge ', Move) then
  begin
    Rest := Copy(Move, Length('merge ') + 1, MaxInt);
    p := Pos(':', Rest);
    if p > 0 then
      Rest := Copy(Rest, 1, p - 1);
    Result := Format(rsUndoMerge, [Trim(Rest)]);
  end
  else if AnsiStartsStr('cherry-pick', Move) then
    Result := Format(rsUndoCherryPick, [Cut(After(Move, 'cherry-pick'))])
  else if AnsiStartsStr('revert', Move) then
    Result := Format(rsUndoRevert, [Cut(After(Move, 'revert'))])
  else if AnsiStartsStr('pull', Move) then
    Result := rsUndoPull
  else if AnsiStartsStr('rebase', Move) then
    Result := rsUndoRebase
  else if AnsiStartsStr('reset:', Move) then
    Result := Format(rsUndoReset, [Short(AAfter.Head)])
  else if ABefore.Branch <> AAfter.Branch then
  begin
    { A branch made and switched to at once (switch -c) is its making. }
    if (AAfter.Branch <> '') and not TipOf(ABefore, AAfter.Branch, Id) then
      Result := Format(rsUndoCreate, [AAfter.Branch])
    else if AAfter.Branch <> '' then
      Result := Format(rsUndoSwitch, [AAfter.Branch])
    else
      Result := Format(rsUndoDetach, [Short(AAfter.Head)]);
  end
  else
    Result := DescribeBranches(ABefore, AAfter);
end;

function PlanRefChange(const ACurrent, AFrom, ATo: TGittanRefState; AKind: TGittanUndoKind;
  const AElsewhere: array of string; out ASteps: TGittanGitSteps;
  out AError: string): boolean;
var
  i: integer;
  FromId, ToId: string;

  { Whether ABranch is checked out in another worktree, said in AError. }
  function Elsewhere(const ABranch: string): boolean;
  var
    j: integer;
  begin
    for j := 0 to High(AElsewhere) do
      if AElsewhere[j] = ABranch then
      begin
        AError := Format(rsUndoElsewhere, [ABranch]);
        Exit(True);
      end;
    Result := False;
  end;

  procedure Add(const AArgs: array of string);
  var
    Step: TStringArray;
    j: integer;
  begin
    SetLength(Step, Length(AArgs));
    for j := 0 to High(AArgs) do
      Step[j] := AArgs[j];
    SetLength(ASteps, Length(ASteps) + 1);
    ASteps[High(ASteps)] := Step;
  end;

begin
  ASteps := nil;
  AError := '';
  if not SameRefState(ACurrent, AFrom) then
  begin
    AError := rsUndoMoved;
    Exit(False);
  end;
  if ATo.Head = '' then
  begin
    AError := rsUndoFirst;
    Exit(False);
  end;
  { Nothing is run when a branch to touch is another worktree's. }
  for i := 0 to High(ATo.Tips) do
    if (ATo.Tips[i].Name <> AFrom.Branch) and TipOf(AFrom, ATo.Tips[i].Name, FromId) and
      (FromId <> ATo.Tips[i].Id) and Elsewhere(ATo.Tips[i].Name) then
      Exit(False);
  if (ATo.Branch <> AFrom.Branch) and (ATo.Branch <> '') and Elsewhere(ATo.Branch) then
    Exit(False);
  for i := 0 to High(AFrom.Tips) do
    if not TipOf(ATo, AFrom.Tips[i].Name, ToId) and Elsewhere(AFrom.Tips[i].Name) then
      Exit(False);
  { The branches to make again first, since HEAD may go to one. }
  for i := 0 to High(ATo.Tips) do
    if not TipOf(AFrom, ATo.Tips[i].Name, FromId) then
      Add(['branch', '--no-track', ATo.Tips[i].Name, ATo.Tips[i].Id]);
  { The other branches, given the tip each has now so a branch moved by
    something else meanwhile is left alone; HEAD's own is moved by the
    reset or, when HEAD goes elsewhere, once it has left it. }
  for i := 0 to High(ATo.Tips) do
    if (ATo.Tips[i].Name <> AFrom.Branch) and TipOf(AFrom, ATo.Tips[i].Name, FromId) and
      (FromId <> ATo.Tips[i].Id) then
      Add(['update-ref', HeadsPrefix + ATo.Tips[i].Name, ATo.Tips[i].Id, FromId]);
  if ATo.Branch <> AFrom.Branch then
  begin
    if ATo.Branch <> '' then
      Add(['switch', ATo.Branch])
    else
      Add(['switch', '--detach', ATo.Head]);
    if (AFrom.Branch <> '') and TipOf(AFrom, AFrom.Branch, FromId) and
      TipOf(ATo, AFrom.Branch, ToId) and (FromId <> ToId) then
      Add(['update-ref', HeadsPrefix + AFrom.Branch, ToId, FromId]);
  end
  else if ATo.Head <> AFrom.Head then
  begin
    if AKind = ukCommit then
      Add(['reset', '--soft', ATo.Head])
    else
      Add(['reset', '--keep', ATo.Head]);
  end;
  for i := 0 to High(AFrom.Tips) do
    if not TipOf(ATo, AFrom.Tips[i].Name, ToId) then
      Add(['update-ref', '-d', HeadsPrefix + AFrom.Tips[i].Name, AFrom.Tips[i].Id]);
  Result := True;
end;

{ TGittanUndoHistory }

constructor TGittanUndoHistory.Create(AMax: integer);
begin
  inherited Create;
  FMax := AMax;
end;

procedure TGittanUndoHistory.Track(const AState: TGittanRefState; ABusy: boolean);
var
  Step: TGittanUndoStep;
begin
  if not AState.Valid or ABusy then
    Exit;
  if not FBase.Valid then
  begin
    FBase := AState;
    Exit;
  end;
  if SameRefState(FBase, AState) then
  begin
    FBase.Move := AState.Move;
    Exit;
  end;
  Step := Default(TGittanUndoStep);
  Step.Before := FBase;
  Step.After := AState;
  Step.Title := DescribeStep(FBase, AState, Step.Kind);
  SetLength(FSteps, FDone);
  if (FMax > 0) and (Length(FSteps) >= FMax) then
    Delete(FSteps, 0, Length(FSteps) - FMax + 1);
  SetLength(FSteps, Length(FSteps) + 1);
  FSteps[High(FSteps)] := Step;
  FDone := Length(FSteps);
  FBase := AState;
end;

function TGittanUndoHistory.CanUndo: boolean;
begin
  Result := FDone > 0;
end;

function TGittanUndoHistory.CanRedo: boolean;
begin
  Result := FDone < Length(FSteps);
end;

function TGittanUndoHistory.UndoStep: TGittanUndoStep;
begin
  Result := FSteps[FDone - 1];
end;

function TGittanUndoHistory.RedoStep: TGittanUndoStep;
begin
  Result := FSteps[FDone];
end;

procedure TGittanUndoHistory.Undone(const AState: TGittanRefState);
begin
  if FDone > 0 then
    Dec(FDone);
  FBase := AState;
end;

procedure TGittanUndoHistory.Redone(const AState: TGittanRefState);
begin
  if FDone < Length(FSteps) then
    Inc(FDone);
  FBase := AState;
end;

procedure TGittanUndoHistory.Clear;
begin
  FSteps := nil;
  FDone := 0;
  FBase := Default(TGittanRefState);
end;

end.
