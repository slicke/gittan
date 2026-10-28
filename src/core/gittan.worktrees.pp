unit gittan.worktrees;

{** Linked worktrees: the work trees a repository has besides its own
  (git worktree), each on a branch of its own, so two branches can be
  worked on side by side. ListWorktrees reads them as git lists them
  (ParseWorktreeList reads the porcelain form, tested), AddWorktree
  makes one, RemoveWorktree, LockWorktree and PruneWorktrees do what
  their names say, each with git's words on failure. No LCL; tested in
  tests/testworktrees.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.git;

type
  {** One worktree as git worktree list gives it: its folder (Path, as
    git prints it, the main one first), the commit checked out (Head,
    empty for a bare one) and the branch (Branch, without refs/heads/,
    empty for a detached HEAD). Main is the repository's own, Bare one
    with no work tree, Detached one on no branch, Locked one git
    worktree lock holds (with LockReason when one was given), Prunable
    one whose folder is gone (PruneReason says why). }
  TGittanWorktree = record
    Path, Head, Branch: string;
    Main, Bare, Detached, Locked, Prunable: boolean;
    LockReason, PruneReason: string;
  end;
  TGittanWorktrees = array of TGittanWorktree;

{** Reads the output of git worktree list --porcelain: a block per
  worktree, "worktree <path>" first, then HEAD, branch, bare, detached,
  locked and prunable lines, a blank line between the blocks. The first
  is the main worktree. }
function ParseWorktreeList(const AText: string): TGittanWorktrees;

{** The worktrees of the repository at ARoot (any of them); false with
  git's words in AError. }
function ListWorktrees(const ARoot: string; out AList: TGittanWorktrees;
  out AError: string): boolean;

{** Adds a worktree at APath (absolute, or from ARoot): on ABranch when
  one is named, made first from AStart (HEAD when empty) with ANew,
  else checked out there as it is; without a branch, git makes one
  named after the folder from HEAD. The folder is made by git. False
  with git's words in AError. }
function AddWorktree(const ARoot, APath, ABranch: string; ANew: boolean;
  const AStart: string; out AError: string): boolean;

{** Removes the worktree at APath, its folder with it; AForce also one
  with changes not committed, or a locked one. The branch stays. False
  with git's words in AError, ADirty set when git refused it for the
  changes (or the lock), which AForce would get past. }
function RemoveWorktree(const ARoot, APath: string; AForce: boolean;
  out AError: string; out ADirty: boolean): boolean;

{** Locks (ALock) or unlocks the worktree at APath, so a prune leaves
  it alone while its folder is away. }
function LockWorktree(const ARoot, APath: string; ALock: boolean; out AError: string): boolean;

{** Forgets the worktrees whose folders are gone. }
function PruneWorktrees(const ARoot: string; out AError: string): boolean;

{** A folder for a new worktree of the repository at ARoot for ABranch
  (may be empty): beside the repository, named after it and the
  branch ("repo-feature-x", a slash in the branch as a dash; "repo-wt"
  with no branch), with a number added while such a folder exists. }
function SuggestWorktreePath(const ARoot, ABranch: string): string;

implementation

function ParseWorktreeList(const AText: string): TGittanWorktrees;
var
  Lines: TStringList;
  i: integer;
  Line: string;
  Open: boolean;

  procedure Close;
  begin
    Open := False;
  end;

begin
  Result := nil;
  Open := False;
  Lines := TStringList.Create;
  try
    Lines.Text := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      if Line = '' then
      begin
        Close;
        Continue;
      end;
      if Copy(Line, 1, 9) = 'worktree ' then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Default(TGittanWorktree);
        Result[High(Result)].Path := Copy(Line, 10, MaxInt);
        Result[High(Result)].Main := Length(Result) = 1;
        Open := True;
        Continue;
      end;
      if not Open then
        Continue;
      with Result[High(Result)] do
        if Copy(Line, 1, 5) = 'HEAD ' then
          Head := Copy(Line, 6, MaxInt)
        else if Copy(Line, 1, 7) = 'branch ' then
        begin
          Branch := Copy(Line, 8, MaxInt);
          if Copy(Branch, 1, 11) = 'refs/heads/' then
            Delete(Branch, 1, 11);
        end
        else if Line = 'bare' then
          Bare := True
        else if Line = 'detached' then
          Detached := True
        else if (Line = 'locked') or (Copy(Line, 1, 7) = 'locked ') then
        begin
          Locked := True;
          LockReason := Copy(Line, 8, MaxInt);
        end
        else if (Line = 'prunable') or (Copy(Line, 1, 9) = 'prunable ') then
        begin
          Prunable := True;
          PruneReason := Copy(Line, 10, MaxInt);
        end;
    end;
  finally
    Lines.Free;
  end;
end;

function ListWorktrees(const ARoot: string; out AList: TGittanWorktrees;
  out AError: string): boolean;
var
  Output: string;
begin
  AList := nil;
  Result := RunGitIn(ARoot, ['worktree', 'list', '--porcelain'], Output, AError);
  if Result then
    AList := ParseWorktreeList(Output);
end;

function AddWorktree(const ARoot, APath, ABranch: string; ANew: boolean;
  const AStart: string; out AError: string): boolean;
var
  Output, Start: string;
begin
  if ABranch = '' then
    Result := RunGitIn(ARoot, ['worktree', 'add', '--', APath], Output, AError)
  else if ANew then
  begin
    Start := AStart;
    if Start = '' then
      Start := 'HEAD';
    Result := RunGitIn(ARoot, ['worktree', 'add', '-b', ABranch, '--', APath, Start],
      Output, AError);
  end
  else
    Result := RunGitIn(ARoot, ['worktree', 'add', '--', APath, ABranch], Output, AError);
end;

function RemoveWorktree(const ARoot, APath: string; AForce: boolean;
  out AError: string; out ADirty: boolean): boolean;
var
  Output: string;
begin
  ADirty := False;
  if AForce then
    Result := RunGitIn(ARoot, ['worktree', 'remove', '--force', '--', APath], Output, AError)
  else
    Result := RunGitIn(ARoot, ['worktree', 'remove', '--', APath], Output, AError);
  { "contains modified or untracked files, use --force to delete it",
    "cannot remove a locked working tree, lock reason: ...". }
  if not Result then
    ADirty := (Pos('--force', AError) > 0) or (Pos('locked working tree', AError) > 0);
end;

function LockWorktree(const ARoot, APath: string; ALock: boolean; out AError: string): boolean;
var
  Output: string;
begin
  if ALock then
    Result := RunGitIn(ARoot, ['worktree', 'lock', '--', APath], Output, AError)
  else
    Result := RunGitIn(ARoot, ['worktree', 'unlock', '--', APath], Output, AError);
end;

function PruneWorktrees(const ARoot: string; out AError: string): boolean;
var
  Output: string;
begin
  Result := RunGitIn(ARoot, ['worktree', 'prune'], Output, AError);
end;

function SuggestWorktreePath(const ARoot, ABranch: string): string;
var
  Base, Name: string;
  n: integer;
begin
  Base := ExcludeTrailingPathDelimiter(ARoot);
  Name := ExtractFileName(Base);
  if ABranch = '' then
    Name := Name + '-wt'
  else
    Name := Name + '-' + StringReplace(StringReplace(ABranch, '/', '-', [rfReplaceAll]),
      '\', '-', [rfReplaceAll]);
  Result := IncludeTrailingPathDelimiter(ExtractFileDir(Base)) + Name;
  n := 1;
  while DirectoryExists(Result) or FileExists(Result) do
  begin
    Inc(n);
    Result := IncludeTrailingPathDelimiter(ExtractFileDir(Base)) + Name + '-' + IntToStr(n);
  end;
end;

end.
