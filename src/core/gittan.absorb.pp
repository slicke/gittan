unit gittan.absorb;

{** Putting changes into the commits they belong to, what the git
  absorb command does: each changed block of the work tree goes into
  the commit of the branch that last wrote the lines it changes, as a
  fixup commit the rebase then folds in, so a review's rounds of small
  fixes end up in the commits they fix rather than in a "fixes" commit
  on top.

  The branch's commits are those since AbsorbBase: the merge base with
  the branch's upstream, else with the default branch (origin/main),
  else the last AbsorbMaxStack commits, so a commit already pushed to
  the upstream or on the default branch is never rewritten. A block's
  commit is found by blaming HEAD's version of the file: a block that
  deletes lines belongs to the commit that wrote them, when it is one
  commit of the branch; a block that only adds lines belongs to the
  commit that wrote the lines round it, when that is one commit of the
  branch; a block whose lines come from an older commit, from several
  commits, or of a new file, cannot be placed and stays in the work
  tree. TGittanAbsorbPlan.Build finds the target of every block of the
  paths given, and AbsorbRun commits the chosen ones as fixup! commits
  (through TGittanRepo.Commit with the file's text holding only the
  blocks for that commit, from gittan.leaveout, so what is left stays
  in the work tree) and replays the branch with the fixups folded in
  (gittan.rebase, TGittanRepo.RebaseInteractive, which stashes the rest
  meanwhile). No LCL; tested in tests/testabsorb.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.git, gittan.keep, gittan.blame, gittan.rebase;

const
  {** How many commits back the branch reaches when it has neither an
    upstream nor a default branch to be measured from. }
  AbsorbMaxStack = 10;

resourcestring
  rsAbsorbOlder = 'its lines were last changed before the branch';
  rsAbsorbMixed = 'its lines come from different commits';
  rsAbsorbNewFile = 'the file is new';
  rsAbsorbDeletedFile = 'the file is deleted';
  rsAbsorbNoNeighbours = 'no commit of the branch wrote the lines round it';
  rsAbsorbBinary = 'the file is binary';
  rsAbsorbNoCommits = 'There are no commits on the branch to put changes into.';
  rsAbsorbMerges = 'The commits of the branch include a merge commit, which an ' +
    'interactive rebase would flatten.';
  rsAbsorbNoBranch = 'HEAD is not on a branch.';
  rsAbsorbNothingChosen = 'No change was chosen.';
  rsAbsorbNoBase = 'Could not find where the branch leaves %s.';
  rsAbsorbMoved = 'The branch has moved since the changes were read; try again.';
  rsAbsorbNotUndone = 'The fixup commits made could not be taken back: %s';
  rsAbsorbSpecFile = 'Could not write %s.';
  rsAbsorbStashConflicts = 'The changes went into their commits, but putting back what ' +
    'was left in the work tree gave conflicts; git keeps it in the stash too.';

type
  {** One block of changed lines of a file: its pairs (as gittan.keep
    pairs them), the line of the file as it is where it starts, and the
    commit it belongs to as an index into the plan's Steps, or -1 with
    Reason saying why it cannot be placed. }
  TGittanAbsorbHunk = record
    Path: string;
    Pairs: TGittanKeepArray;
    Line: integer;
    Target: integer;
    Reason: string;
  end;
  TGittanAbsorbHunks = array of TGittanAbsorbHunk;

  { TGittanAbsorbPlan }

  {** The blocks of some files and the commits they belong to. }
  TGittanAbsorbPlan = class
  private
    FOnto: string;
    FBranch: string;
    FHead: string;
    FSteps: TGittanRebaseSteps;
    FHunks: TGittanAbsorbHunks;
    FDiffs: TStringList;
    FPushed: integer;
    procedure AddHunks(ARepo: TGittanRepo; const APath: string; ALines: TStrings);
  public
    constructor Create;
    destructor Destroy; override;
    {** Finds the branch's commits (AbsorbBase) and the target of every
      block of APaths (each a path of a changed file, relative to the
      root). False with AError when the base cannot be found or a
      file's diff cannot be taken; a file git cannot blame (a new one)
      gives blocks that cannot be placed. }
    function Build(ARepo: TGittanRepo; APaths: TStrings; out AError: string): boolean;
    {** How many of the hunks have a target. }
    function Placeable: integer;
    {** The diff of APath the hunks were read from (the whole file as
      context, as FileChanges gives it), nil for a path not built. }
    function Diff(const APath: string): TStrings;
    {** The hunk that holds the pair APair of APath (the same content at
      the same line), -1 when none does. }
    function HunkOf(const APath: string; const APair: TGittanKeep): integer;
    {** The commit the branch's commits sit on. }
    property Onto: string read FOnto;
    {** The branch and HEAD's id when the plan was built, which the run
      checks before it commits anything. }
    property Branch: string read FBranch;
    property Head: string read FHead;
    {** The branch's commits, oldest first, as a rebase replays them. }
    property Steps: TGittanRebaseSteps read FSteps;
    property Hunks: TGittanAbsorbHunks read FHunks;
    {** How many of the steps are on the branch's upstream already. }
    property Pushed: integer read FPushed;
  end;

{** The commit the branch's own commits sit on: the merge base with the
  branch's upstream, else with the default branch, else the commit
  AbsorbMaxStack back, or the root commit when the branch is shorter.
  An upstream that is gone counts as none. False with AError when HEAD
  is on no branch, the merge base with the upstream or default branch
  cannot be found, or the branch has no commit of its own (AOnto is
  HEAD then). }
function AbsorbBase(ARepo: TGittanRepo; out AOnto: string; out AError: string): boolean;

{** The old file's lines the block at AStart of ALines (a diff with the
  whole file as context) stands for: AFrom..ATo the deleted lines'
  numbers in the old file (ATo under AFrom when none is deleted),
  ABefore the old line before the block (0 at the start of the file)
  and AAfter the one after it (0 at the end). }
procedure BlockOldLines(ALines: TStrings; AStart: integer; out AFrom, ATo, ABefore,
  AAfter: integer);

{** BlockOldLines with AOld, the old file's lines before AStart, counted
  already, so a pass over the blocks need not count from the start. }
procedure BlockOldLinesAt(ALines: TStrings; AStart, AOld: integer; out AFrom, ATo,
  ABefore, AAfter: integer);

{** The step of ASteps the block belongs to by ABlame, the blame of the
  old file: the one commit that wrote the lines AFrom..ATo, or with
  none deleted the one commit that wrote ABefore and AAfter (the one of
  them that is in the file). -1 with AReason when the lines are older
  than the branch, come from several commits, or have no neighbours. }
function AbsorbTarget(ABlame: TGittanBlame; AFrom, ATo, ABefore, AAfter: integer;
  const ASteps: TGittanRebaseSteps; out AReason: string): integer;

{** Commits the chosen hunks of APlan (AChosen by hunk index; a hunk
  without a target is never taken) as fixup commits, one per target
  commit, and replays the branch from the plan's Onto with the fixups
  folded in. ACommits is how many fixup commits were made. True when
  the rebase went through. False with AError when the branch moved since
  the plan was built, a file changed since or cannot be read, a commit
  failed, the branch holds a merge commit, the rebase did not start, or
  nothing was chosen, with the fixup commits made before taken back
  (ACommits 0), so the branch and the work tree are as they were, or
  ACommits as it was and rsAbsorbNotUndone after AError when taking them
  back failed; AConflicts and AStopped as
  RebaseInteractive gives them when the rebase stopped, which the Commit
  section carries on, the fixup commits still on the branch; AConflicts
  with rsAbsorbStashConflicts when the rebase went through but the rest
  of the work tree clashed when it was put back. }
function AbsorbRun(ARepo: TGittanRepo; APlan: TGittanAbsorbPlan;
  const AChosen: array of boolean; AOptions: TGittanCommitOptions;
  out ACommits: integer; out AConflicts, AStopped: boolean; out AError: string): boolean;

implementation

uses
  gittan.leaveout, gittan.textfile;

function AbsorbBase(ARepo: TGittanRepo; out AOnto: string; out AError: string): boolean;
var
  Branch, Ref, Output, Err: string;
  Detached: boolean;
  i: integer;
begin
  AOnto := '';
  AError := '';
  Result := False;
  Branch := ARepo.Branch(Detached);
  if Detached or (Branch = '') then
  begin
    AError := rsAbsorbNoBranch;
    Exit;
  end;
  Ref := ARepo.Upstream(Branch);
  if (Ref <> '') and not ARepo.HasCommit(Ref) then
    Ref := '';
  if Ref = '' then
    Ref := ARepo.DefaultBranch;
  if Ref <> '' then
  begin
    { Never further back than the upstream or the default branch, so
      without a merge base with it there is no base. }
    Result := ARepo.MergeBase(Ref, AOnto);
    if not Result then
      AError := Format(rsAbsorbNoBase, [Ref]);
  end
  else
  begin
    { No upstream and no default branch: the last AbsorbMaxStack
      commits, or every commit after the root. }
    AOnto := '';
    for i := AbsorbMaxStack downto 1 do
      if ARepo.HasCommit('HEAD~' + IntToStr(i)) then
      begin
        AOnto := ARepo.CommitId('HEAD~' + IntToStr(i));
        Break;
      end;
    if AOnto = '' then
    begin
      if not RunGitIn(ARepo.Root, ['rev-list', '--max-parents=0', 'HEAD'], Output, Err) then
      begin
        AError := Err;
        Exit;
      end;
      AOnto := Trim(Output);
      i := Pos(#10, AOnto);
      if i > 0 then
        AOnto := Trim(Copy(AOnto, 1, i - 1));
    end;
    Result := AOnto <> '';
  end;
  if Result and (AOnto = ARepo.CommitId('HEAD')) then
  begin
    AError := rsAbsorbNoCommits;
    Result := False;
  end;
end;

procedure BlockOldLines(ALines: TStrings; AStart: integer; out AFrom, ATo, ABefore,
  AAfter: integer);
var
  i, Old: integer;
begin
  Old := 0;
  for i := 0 to AStart - 1 do
    if ALines[i][1] <> '+' then
      Inc(Old);
  BlockOldLinesAt(ALines, AStart, Old, AFrom, ATo, ABefore, AAfter);
end;

procedure BlockOldLinesAt(ALines: TStrings; AStart, AOld: integer; out AFrom, ATo,
  ABefore, AAfter: integer);
var
  i, Old: integer;
begin
  Old := AOld;
  ABefore := Old;
  AFrom := Old + 1;
  i := AStart;
  while (i < ALines.Count) and (ALines[i][1] <> ' ') do
  begin
    if ALines[i][1] = '-' then
      Inc(Old);
    Inc(i);
  end;
  ATo := Old;
  if i < ALines.Count then
    AAfter := Old + 1
  else
    AAfter := 0;
end;

function AbsorbTarget(ABlame: TGittanBlame; AFrom, ATo, ABefore, AAfter: integer;
  const ASteps: TGittanRebaseSteps; out AReason: string): integer;
var
  Line, Commit: integer;
  Older: boolean;

  { The step whose commit wrote ALine, -1 for one older than the
    branch (Older set) or a line the blame lacks. }
  function StepOf(ALine: integer): integer;
  var
    s: integer;
  begin
    Result := -1;
    Commit := ABlame.CommitOf(ALine);
    if Commit < 0 then
      Exit;
    for s := 0 to High(ASteps) do
      if ASteps[s].Hash = ABlame.Commits[Commit].Hash then
        Exit(s);
    Older := True;
  end;

  { Takes ALine's step into Result: the same as before, or mixed. }
  procedure Take(ALine: integer);
  var
    s: integer;
  begin
    if AReason <> '' then
      Exit;
    s := StepOf(ALine);
    if s < 0 then
    begin
      if Older then
        AReason := rsAbsorbOlder
      else
        AReason := rsAbsorbNoNeighbours;
    end
    else if (Result >= 0) and (Result <> s) then
      AReason := rsAbsorbMixed
    else
      Result := s;
  end;

begin
  Result := -1;
  AReason := '';
  Older := False;
  if ATo >= AFrom then
  begin
    for Line := AFrom to ATo do
      Take(Line);
  end
  else
  begin
    if ABefore > 0 then
      Take(ABefore);
    if AAfter > 0 then
      Take(AAfter);
    if (ABefore = 0) and (AAfter = 0) then
      AReason := rsAbsorbNoNeighbours;
  end;
  if AReason <> '' then
    Result := -1
  else if Result < 0 then
    AReason := rsAbsorbNoNeighbours;
end;

{ TGittanAbsorbPlan }

constructor TGittanAbsorbPlan.Create;
begin
  inherited Create;
  FDiffs := TStringList.Create;
  FDiffs.OwnsObjects := True;
  FDiffs.CaseSensitive := True;
end;

destructor TGittanAbsorbPlan.Destroy;
begin
  FDiffs.Free;
  inherited Destroy;
end;

{ The blocks of ALines, each with its target by the blame of HEAD's
  version of the file; a file HEAD lacks, or one that is gone from
  disk, gives blocks that cannot be placed. }
procedure TGittanAbsorbPlan.AddHunks(ARepo: TGittanRepo; const APath: string; ALines: TStrings);
var
  Blame: TGittanBlame;
  Output, Err: string;
  i, Old, AFrom, ATo, ABefore, AAfter: integer;
  NewFile, Deleted, Blamed: boolean;

  procedure AddHunk(AStart: integer);
  begin
    SetLength(FHunks, Length(FHunks) + 1);
    with FHunks[High(FHunks)] do
    begin
      Path := APath;
      Pairs := BlockPairs(ALines, AStart);
      if Length(Pairs) > 0 then
        Line := Pairs[0].Line
      else
        Line := 1;
      Target := -1;
      if NewFile then
        Reason := rsAbsorbNewFile
      else if Deleted then
        Reason := rsAbsorbDeletedFile
      else if not Blamed then
        Reason := rsAbsorbNoNeighbours
      else
      begin
        BlockOldLinesAt(ALines, AStart, Old, AFrom, ATo, ABefore, AAfter);
        Target := AbsorbTarget(Blame, AFrom, ATo, ABefore, AAfter, FSteps, Reason);
      end;
    end;
  end;

begin
  { Asked of HEAD and the disk, not read from the lines: a file emptied
    has only - lines and one that was empty only + lines. }
  NewFile := (ALines.Count > 0) and
    not RunGitIn(ARepo.Root, ['cat-file', '-e', 'HEAD:' + APath], Output, Err);
  Deleted := (ALines.Count > 0) and not NewFile and
    not FileExists(IncludeTrailingPathDelimiter(ARepo.Root) + SetDirSeparators(APath), False);
  Blame := nil;
  Blamed := False;
  try
    if not NewFile and not Deleted then
    begin
      Blame := TGittanBlame.Create;
      Blamed := ARepo.Blame(APath, 'HEAD', Output) and Blame.Parse(Output);
    end;
    { Old counts the old file's lines before i as it goes. }
    Old := 0;
    for i := 0 to ALines.Count - 1 do
    begin
      if (ALines[i][1] <> ' ') and ((i = 0) or (ALines[i - 1][1] = ' ')) then
        AddHunk(i);
      if ALines[i][1] <> '+' then
        Inc(Old);
    end;
  finally
    Blame.Free;
  end;
end;

function TGittanAbsorbPlan.Build(ARepo: TGittanRepo; APaths: TStrings;
  out AError: string): boolean;
var
  Lines: TStringList;
  Merges: boolean;
  i: integer;
begin
  FHunks := nil;
  FSteps := nil;
  FDiffs.Clear;
  FPushed := 0;
  FBranch := ARepo.Branch;
  FHead := ARepo.CommitId('HEAD');
  Result := AbsorbBase(ARepo, FOnto, AError);
  if not Result then
    Exit;
  if not ARepo.RebaseSteps(FOnto, FSteps, Merges) then
  begin
    AError := ARepo.Error;
    Exit(False);
  end;
  { As the interactive rebase and the fixup fold, which refuse a range
    with a merge commit in it. }
  if Merges then
  begin
    AError := rsAbsorbMerges;
    Exit(False);
  end;
  if Length(FSteps) = 0 then
  begin
    AError := rsAbsorbNoCommits;
    Exit(False);
  end;
  for i := 0 to High(FSteps) do
    if FSteps[i].Pushed then
      Inc(FPushed);
  for i := 0 to APaths.Count - 1 do
  begin
    Lines := TStringList.Create;
    if not ARepo.FileChanges(APaths[i], Lines) then
    begin
      Lines.Free;
      AError := ARepo.Error;
      Exit(False);
    end;
    FDiffs.AddObject(APaths[i], Lines);
    { A binary file gives no lines and so no hunks. }
    AddHunks(ARepo, APaths[i], Lines);
  end;
end;

function TGittanAbsorbPlan.Placeable: integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to High(FHunks) do
    if FHunks[i].Target >= 0 then
      Inc(Result);
end;

function TGittanAbsorbPlan.Diff(const APath: string): TStrings;
var
  i: integer;
begin
  i := FDiffs.IndexOf(APath);
  if i < 0 then
    Result := nil
  else
    Result := TStrings(FDiffs.Objects[i]);
end;

function TGittanAbsorbPlan.HunkOf(const APath: string; const APair: TGittanKeep): integer;
var
  k: integer;
begin
  for Result := 0 to High(FHunks) do
    if FHunks[Result].Path = APath then
      for k := 0 to High(FHunks[Result].Pairs) do
        if SameKeep(FHunks[Result].Pairs[k], APair) and
          (FHunks[Result].Pairs[k].Line = APair.Line) then
          Exit;
  Result := -1;
end;

{ The subject of the fixup commit for the step: "fixup! <subject>",
  which the autosquash reads, or "fixup! <id>" when another step has
  the same subject and would be found first, or when the step is a
  fixup itself, whose subject would name the commit it is for (which
  need not be among the steps) and not the step. }
function FixupSubject(const ASteps: TGittanRebaseSteps; AStep: integer): string;
var
  i: integer;
  Action: TGittanRebaseAction;
begin
  FixupTarget(ASteps[AStep].Subject, Action);
  if Action <> raPick then
    Exit('fixup! ' + ASteps[AStep].Hash);
  for i := 0 to AStep - 1 do
    if ASteps[i].Subject = ASteps[AStep].Subject then
      Exit('fixup! ' + ASteps[AStep].Hash);
  Result := 'fixup! ' + ASteps[AStep].Subject;
end;

function AbsorbRun(ARepo: TGittanRepo; APlan: TGittanAbsorbPlan;
  const AChosen: array of boolean; AOptions: TGittanCommitOptions;
  out ACommits: integer; out AConflicts, AStopped: boolean; out AError: string): boolean;
var
  Paths, Committed: TStringList;
  Parts: TGittanCommitParts;
  Steps: TGittanRebaseSteps;
  Hunks: TGittanAbsorbHunks;
  Taken: array of boolean;
  Merges, Whole, Rebasing: boolean;
  t, h, Found: integer;
  Id, Err, Output, LastFixup: string;
  Text: RawByteString;

  { Whether the hunk is chosen and has a target. }
  function Chosen(AHunk: integer): boolean;
  begin
    Result := (AHunk <= High(AChosen)) and AChosen[AHunk] and (Hunks[AHunk].Target >= 0);
  end;

  { The paths with a chosen hunk for the step ATarget, each once. }
  procedure PathsFor(ATarget: integer);
  var
    i: integer;
  begin
    Paths.Clear;
    for i := 0 to High(Hunks) do
      if Chosen(i) and (Hunks[i].Target = ATarget) and (Paths.IndexOf(Hunks[i].Path) < 0) then
        Paths.Add(Hunks[i].Path);
  end;

  { The text to commit for APath at this point: the work tree's with
    the pairs of every hunk not taken yet put back as HEAD has them,
    so the fixup commit holds only its own hunks and what is left
    stays in the work tree. The whole file when nothing is left out,
    checked against the plan's diff all the same, so a change made
    since is not committed. }
  function PartFor(const APath: string; out AText: RawByteString; out AWhole: boolean): boolean;
  var
    LeftOut: TGittanKeepArray;
    FileText: RawByteString;
    i, k: integer;
  begin
    Result := False;
    AText := '';
    LeftOut := nil;
    for i := 0 to High(Hunks) do
      if (Hunks[i].Path = APath) and not Taken[i] then
        for k := 0 to High(Hunks[i].Pairs) do
        begin
          SetLength(LeftOut, Length(LeftOut) + 1);
          LeftOut[High(LeftOut)] := Hunks[i].Pairs[k];
        end;
    AWhole := Length(LeftOut) = 0;
    try
      FileText := ReadFileBytes(IncludeTrailingPathDelimiter(ARepo.Root) +
        SetDirSeparators(APath));
    except
      on E: Exception do
      begin
        AError := APath + ': ' + E.Message;
        Exit;
      end;
    end;
    Result := LeaveOutText(FileText, APlan.Diff(APath), LeftOut, AText, Found, Err);
    if not Result then
      AError := APath + ': ' + Err;
  end;

  { Takes back the fixup commits made before something failed, while no
    rebase has started: HEAD back where the plan found it and the paths
    committed back in the index as it has them, so the changes are in
    the work tree again, as before, and no stray fixup! commit is left
    on the branch. The paths go to git in a file, as a commit's do, so
    many of them do not grow the command line past what the system
    takes. False, with git's error after AError, when a reset failed. }
  function UndoCommits: boolean;
  var
    SpecFile, Spec: string;
    i: integer;
  begin
    Result := RunGitIn(ARepo.Root, ['reset', '-q', '--soft', APlan.Head], Output, Err);
    if Result and (Committed.Count > 0) then
    begin
      Spec := '';
      for i := 0 to Committed.Count - 1 do
        Spec := Spec + Committed[i] + #0;
      SpecFile := GetTempFileName(GetTempDir, 'gittan-absorb-');
      try
        Result := WriteFileReplacing(SpecFile, Spec);
        if not Result then
          Err := Format(rsAbsorbSpecFile, [SpecFile])
        else
          Result := RunGitIn(ARepo.Root, ['--literal-pathspecs', 'reset', '-q', APlan.Head,
            '--pathspec-from-file=' + SpecFile, '--pathspec-file-nul'], Output, Err);
      finally
        DeleteFile(SpecFile);
      end;
    end;
    if not Result then
    begin
      if AError <> '' then
        AError := AError + LineEnding;
      AError := AError + Format(rsAbsorbNotUndone, [Trim(Err)]);
    end;
  end;

begin
  ACommits := 0;
  AConflicts := False;
  AStopped := False;
  AError := '';
  Result := False;
  Hunks := APlan.Hunks;
  Steps := APlan.Steps;
  Taken := nil;
  SetLength(Taken, Length(Hunks));
  { Nothing is written when the branch moved since the plan was built:
    its steps and diffs would be wrong. }
  if (ARepo.Branch <> APlan.Branch) or (ARepo.CommitId('HEAD') <> APlan.Head) then
  begin
    AError := rsAbsorbMoved;
    Exit;
  end;
  Rebasing := False;
  Committed := TStringList.Create;
  try
    Committed.CaseSensitive := True;
    Committed.Sorted := True;
    Committed.Duplicates := dupIgnore;
    Paths := TStringList.Create;
    try
      Paths.CaseSensitive := True;
      for t := 0 to High(Steps) do
      begin
        PathsFor(t);
        if Paths.Count = 0 then
          Continue;
        { The hunks of this step are taken before the texts are made, so
          they are in them; those of later steps are left out still. }
        for h := 0 to High(Hunks) do
          if Chosen(h) and (Hunks[h].Target = t) then
            Taken[h] := True;
        Parts := nil;
        for h := 0 to Paths.Count - 1 do
        begin
          if not PartFor(Paths[h], Text, Whole) then
            Exit;
          if Whole then
            Continue;
          SetLength(Parts, Length(Parts) + 1);
          Parts[High(Parts)].Path := Paths[h];
          Parts[High(Parts)].Text := Text;
        end;
        if not ARepo.Commit(FixupSubject(Steps, t), Paths, False, Id, Parts, AOptions) then
        begin
          AError := ARepo.Error;
          Exit;
        end;
        Committed.AddStrings(Paths);
        LastFixup := Id;
        Inc(ACommits);
      end;
    finally
      Paths.Free;
    end;
    if ACommits = 0 then
    begin
      AError := rsAbsorbNothingChosen;
      Exit;
    end;
    if not ARepo.RebaseSteps(APlan.Onto, Steps, Merges) then
    begin
      AError := ARepo.Error;
      Exit;
    end;
    if Merges then
    begin
      AError := rsAbsorbMerges;
      Exit;
    end;
    AutosquashSteps(Steps);
    if not CheckRebaseSteps(Steps, AError) then
      Exit;
    Rebasing := True;
    Result := ARepo.RebaseInteractive(APlan.Onto, Steps, AConflicts, AStopped);
    if not Result then
    begin
      AError := ARepo.Error;
      { The rebase never started (its files could not be written, or
        git refused to begin, a pre-rebase hook or the autostash): the
        fixup commits are taken back as for a failed commit. One that
        ran and stopped is left to the Commit section. }
      if not AConflicts and not AStopped then
        Rebasing := (ARepo.Operation <> '') or (ARepo.CommitId('HEAD') <> LastFixup);
      Exit;
    end;
  finally
    if not Rebasing and (ACommits > 0) and UndoCommits then
      ACommits := 0;
    Committed.Free;
  end;
  { --autostash puts the rest back after the rebase, and a clash there
    leaves files in conflict with git's exit code still 0. }
  if RunGitIn(ARepo.Root, ['ls-files', '-u'], Output, Err) and (Trim(Output) <> '') then
  begin
    AConflicts := True;
    AError := rsAbsorbStashConflicts;
    Result := False;
  end;
end;

end.
