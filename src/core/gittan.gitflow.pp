unit gittan.gitflow;

{** Git flow: a development branch beside the production one, feature
  branches from the development branch merged back into it, release
  branches from it merged into both and tagged, and hotfix branches
  from the production branch merged into both and tagged. Done with
  plain git, so the git-flow command need not be installed, and kept in
  the same config keys (gitflow.branch.master, gitflow.branch.develop,
  gitflow.prefix.feature and the rest), so a repository set up here
  works with the command and the other way round.
  ReadFlow reads the setup (ParseFlowConfig, tested), InitFlow writes
  it and makes the development branch, StartFlowBranch makes a branch
  and switches to it, FinishFlowBranch merges it where it goes, tags a
  release or a hotfix and deletes it. A finish that stops with
  conflicts is finished by running it again once the merge is
  committed: every step it has done already is seen and left out.
  No LCL; tested in tests/testgitflow.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.git;

type
  {** The kinds of branch git flow starts and finishes. }
  TGittanFlowKind = (fkFeature, fkRelease, fkHotfix);

  {** A repository's git flow: the production branch (Master, as
    git-flow names its key, main as often as not), the development
    branch, the prefix of each kind's branches and the prefix of the
    version tags (often empty, sometimes "v"). Initialized when both
    branches are set and differ; a prefix not set has its default. }
  TGittanFlow = record
    Master, Develop: string;
    Prefix: array[TGittanFlowKind] of string;
    VersionTag: string;
    Initialized: boolean;
  end;

  {** A branch of git flow: its kind, its name after the prefix (the
    version of a release or a hotfix) and the whole branch name. }
  TGittanFlowBranch = record
    Kind: TGittanFlowKind;
    Name, Branch: string;
  end;
  TGittanFlowBranches = array of TGittanFlowBranch;

const
  {** The default prefixes, git-flow's. }
  FlowDefaultPrefix: array[TGittanFlowKind] of string = ('feature/', 'release/', 'hotfix/');

{** The flow with the defaults: AMaster, develop, the default prefixes
  and no version tag prefix; not Initialized. }
function DefaultFlow(const AMaster: string): TGittanFlow;

{** Reads what git config --get-regexp ^gitflow\. prints, a "key value"
  line per key (a key with an empty value has no space). }
function ParseFlowConfig(const AText: string): TGittanFlow;

{** The git flow of the repository at ARoot, not Initialized when it has
  none. }
function ReadFlow(const ARoot: string): TGittanFlow;

{** The production branch to offer when setting git flow up: the
  current setup's, else main or master, the one that exists (main when
  both or neither do). }
function SuggestFlowMaster(const ARoot: string): string;

{** Whether the repository at ARoot has ABranch, or a remote has it so
  InitFlow can make it from there. }
function FlowBranchAvailable(const ARoot, ABranch: string): boolean;

{** Whether AFlow's prefixes are all different, so FlowKindOf can tell
  the kinds apart. }
function FlowPrefixesDiffer(const AFlow: TGittanFlow): boolean;

{** Sets git flow up in the repository at ARoot as AFlow says (local
  config, with git-flow's support and bugfix prefixes too, which its
  command looks for). The production branch must exist, or be on the
  remote, when it is made from there; the development branch is made
  from the production branch (or its own on the remote) when missing.
  False with the reason in AError. }
function InitFlow(const ARoot: string; const AFlow: TGittanFlow; out AError: string): boolean;

{** Whether ABranch is a branch of AFlow, with its kind and its name
  after the prefix. The longest prefix wins, for prefixes such as
  "release/" and "release/hot/". }
function FlowKindOf(const AFlow: TGittanFlow; const ABranch: string; out AKind: TGittanFlowKind;
  out AName: string): boolean;

{** The branches of AFlow among ABranches (local branch names), by kind
  and then as given. }
function FlowBranchesOf(const AFlow: TGittanFlow; ABranches: TStrings): TGittanFlowBranches;

{** The branches of AFlow the repository at ARoot has, as FlowBranchesOf
  orders them. }
function ListFlowBranches(const ARoot: string; const AFlow: TGittanFlow): TGittanFlowBranches;

{** The branch a branch of AKind starts from: the production branch for
  a hotfix, the development branch otherwise. }
function FlowBase(const AFlow: TGittanFlow; AKind: TGittanFlowKind): string;

{** The version after AVersion for a release (the second number up, the
  ones after it 0: 1.2 to 1.3, 1.2.3 to 1.3.0, 4 to 5) or a hotfix
  (the last number up, a third one added to two: 1.2.3 to 1.2.4, 1.2
  to 1.2.1, 4 to 4.0.1). '' when AVersion is not numbers and dots; a
  release after none is 1.0. }
function NextFlowVersion(const AVersion: string; AHotfix: boolean): string;

{** The newest version tagged with AFlow's version tag prefix in the
  repository at ARoot, the prefix left out (by version, as git sorts
  them); '' when there is none. }
function LatestFlowVersion(const ARoot: string; const AFlow: TGittanFlow): string;

{** Makes the branch of AKind named AName from its base and switches to
  it; changes in the work tree come along, as a switch takes them.
  False with git's words in AError. }
function StartFlowBranch(const ARoot: string; const AFlow: TGittanFlow;
  AKind: TGittanFlowKind; const AName: string; out AError: string): boolean;

{** The branches a branch of AKind is merged into when it is finished,
  in order: the development branch for a feature; the production
  branch, then the development branch for a release; the production
  branch, then the release branch under way (as git-flow does, so the
  fix goes out with it and on to development later) or the development
  branch when there is none, for a hotfix. }
function FlowTargets(const ARoot: string; const AFlow: TGittanFlow;
  AKind: TGittanFlowKind): TStringArray;

{** The tag a finished release or hotfix named AName gets: the version
  tag prefix and the name. }
function FlowTag(const AFlow: TGittanFlow; const AName: string): string;

{** Finishes the branch of AKind named AName: merges it (--no-ff) into
  each of FlowTargets that does not have it yet; for a release or a
  hotfix tags the production branch with FlowTag after the merge into
  it (annotated with ATagMessage, plain when it is empty), unless the
  tag is there; then switches to the development branch and deletes
  the branch. The work tree's tracked files must have no changes. A
  merge that stops with conflicts leaves git in the middle of it on
  that target, with AConflicts set and the target in AStoppedAt; once
  it is committed, a second call goes on from there. False with the
  reason in AError. }
function FinishFlowBranch(const ARoot: string; const AFlow: TGittanFlow;
  AKind: TGittanFlowKind; const AName, ATagMessage: string; out AConflicts: boolean;
  out AStoppedAt, AError: string): boolean;

implementation

function DefaultFlow(const AMaster: string): TGittanFlow;
var
  Kind: TGittanFlowKind;
begin
  Result := Default(TGittanFlow);
  Result.Master := AMaster;
  Result.Develop := 'develop';
  for Kind := Low(Kind) to High(Kind) do
    Result.Prefix[Kind] := FlowDefaultPrefix[Kind];
end;

function ParseFlowConfig(const AText: string): TGittanFlow;
var
  Lines: TStringList;
  i, p: integer;
  Key, Value: string;
begin
  Result := DefaultFlow('');
  Result.Develop := '';
  Lines := TStringList.Create;
  try
    Lines.Text := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
    for i := 0 to Lines.Count - 1 do
    begin
      p := Pos(' ', Lines[i]);
      if p > 0 then
      begin
        Key := LowerCase(Copy(Lines[i], 1, p - 1));
        Value := Copy(Lines[i], p + 1, MaxInt);
      end
      else
      begin
        Key := LowerCase(Lines[i]);
        Value := '';
      end;
      if Key = 'gitflow.branch.master' then
        Result.Master := Value
      else if Key = 'gitflow.branch.develop' then
        Result.Develop := Value
      else if Key = 'gitflow.prefix.feature' then
        Result.Prefix[fkFeature] := Value
      else if Key = 'gitflow.prefix.release' then
        Result.Prefix[fkRelease] := Value
      else if Key = 'gitflow.prefix.hotfix' then
        Result.Prefix[fkHotfix] := Value
      else if Key = 'gitflow.prefix.versiontag' then
        Result.VersionTag := Value;
    end;
  finally
    Lines.Free;
  end;
  Result.Initialized := (Result.Master <> '') and (Result.Develop <> '') and
    (Result.Master <> Result.Develop);
end;

{ --get-regexp exits with 1 when no key matches. }
function ReadFlow(const ARoot: string): TGittanFlow;
var
  Output, Err: string;
begin
  if (ARoot <> '') and RunGitIn(ARoot, ['config', '--get-regexp', '^gitflow\.'], Output, Err) then
    Result := ParseFlowConfig(Output)
  else
    Result := ParseFlowConfig('');
end;

function HasRef(const ARoot, ARef: string): boolean;
var
  Output, Err: string;
begin
  Result := RunGitIn(ARoot, ['rev-parse', '--verify', '--quiet', ARef + '^{commit}'],
    Output, Err);
end;

function HasBranch(const ARoot, ABranch: string): boolean;
begin
  Result := (ABranch <> '') and HasRef(ARoot, 'refs/heads/' + ABranch);
end;

function SuggestFlowMaster(const ARoot: string): string;
var
  Flow: TGittanFlow;
begin
  Flow := ReadFlow(ARoot);
  if Flow.Master <> '' then
    Exit(Flow.Master);
  if not HasBranch(ARoot, 'main') and HasBranch(ARoot, 'master') then
    Result := 'master'
  else
    Result := 'main';
end;

{ The remote a branch missing here can be made from: the first that has
  it. }
function RemoteWith(const ARoot, ABranch: string): string;
var
  Output, Err, Remote: string;
begin
  Result := '';
  if not RunGitIn(ARoot, ['remote'], Output, Err) then
    Exit;
  for Remote in Output.Split([#10]) do
    if (Trim(Remote) <> '') and HasRef(ARoot, 'refs/remotes/' + Trim(Remote) + '/' + ABranch) then
      Exit(Trim(Remote));
end;

function FlowBranchAvailable(const ARoot, ABranch: string): boolean;
begin
  Result := (ABranch <> '') and (HasBranch(ARoot, ABranch) or (RemoteWith(ARoot, ABranch) <> ''));
end;

function FlowPrefixesDiffer(const AFlow: TGittanFlow): boolean;
var
  A, B: TGittanFlowKind;
begin
  Result := True;
  for A := Low(A) to High(A) do
    for B := Succ(A) to High(B) do
      if AFlow.Prefix[A] = AFlow.Prefix[B] then
        Exit(False);
end;

{ A local branch ABranch, made from the remote's when only the remote
  has it, or from AFrom when given and no remote has it either. }
function EnsureBranch(const ARoot, ABranch, AFrom: string; out AError: string): boolean;
var
  Output, Remote: string;
begin
  AError := '';
  if HasBranch(ARoot, ABranch) then
    Exit(True);
  Remote := RemoteWith(ARoot, ABranch);
  if Remote <> '' then
    Exit(RunGitIn(ARoot, ['branch', '--track', ABranch, Remote + '/' + ABranch], Output, AError));
  if AFrom = '' then
  begin
    AError := Format('There is no branch %s.', [ABranch]);
    Exit(False);
  end;
  Result := RunGitIn(ARoot, ['branch', '--no-track', ABranch, AFrom], Output, AError);
end;

function InitFlow(const ARoot: string; const AFlow: TGittanFlow; out AError: string): boolean;
var
  Output: string;
  Kind: TGittanFlowKind;

  function SetKey(const AKey, AValue: string): boolean;
  begin
    if AValue = '' then
      Exit(SetEmptyConfigKey(ARoot, AKey, AError));
    Result := RunGitIn(ARoot, ['config', '--local', AKey, AValue], Output, AError);
  end;

  { A key set already is left as it is: the bugfix and support
    prefixes, which the git-flow command uses and Gittan does not, so
    a setup done here keeps what was set there. }
  function KeepKey(const AKey, AValue: string): boolean;
  var
    Err: string;
  begin
    Result := RunGitIn(ARoot, ['config', '--local', '--get', AKey], Output, Err);
    if not Result then
      Result := SetKey(AKey, AValue);
  end;

begin
  AError := '';
  if (AFlow.Master = '') or (AFlow.Develop = '') or (AFlow.Master = AFlow.Develop) then
  begin
    AError := 'The production and the development branch must be two branches.';
    Exit(False);
  end;
  for Kind := Low(Kind) to High(Kind) do
    if AFlow.Prefix[Kind] = '' then
    begin
      AError := 'Every kind of branch needs a prefix.';
      Exit(False);
    end;
  if not FlowPrefixesDiffer(AFlow) then
  begin
    AError := 'Every kind of branch needs a prefix of its own.';
    Exit(False);
  end;
  { The branch keys go last: ReadFlow counts a setup as done once they
    are there, so a write that fails before them leaves none. }
  Result := EnsureBranch(ARoot, AFlow.Master, '', AError) and
    EnsureBranch(ARoot, AFlow.Develop, AFlow.Master, AError) and
    SetKey('gitflow.prefix.feature', AFlow.Prefix[fkFeature]) and
    KeepKey('gitflow.prefix.bugfix', 'bugfix/') and
    SetKey('gitflow.prefix.release', AFlow.Prefix[fkRelease]) and
    SetKey('gitflow.prefix.hotfix', AFlow.Prefix[fkHotfix]) and
    KeepKey('gitflow.prefix.support', 'support/') and
    SetKey('gitflow.prefix.versiontag', AFlow.VersionTag) and
    SetKey('gitflow.branch.master', AFlow.Master) and
    SetKey('gitflow.branch.develop', AFlow.Develop);
end;

function FlowKindOf(const AFlow: TGittanFlow; const ABranch: string; out AKind: TGittanFlowKind;
  out AName: string): boolean;
var
  Kind: TGittanFlowKind;
  Best: integer;
begin
  Result := False;
  AKind := fkFeature;
  AName := '';
  if not AFlow.Initialized or (ABranch = AFlow.Master) or (ABranch = AFlow.Develop) then
    Exit;
  Best := 0;
  for Kind := Low(Kind) to High(Kind) do
    if (AFlow.Prefix[Kind] <> '') and (Length(AFlow.Prefix[Kind]) > Best) and
      (Length(ABranch) > Length(AFlow.Prefix[Kind])) and
      (Copy(ABranch, 1, Length(AFlow.Prefix[Kind])) = AFlow.Prefix[Kind]) then
    begin
      Best := Length(AFlow.Prefix[Kind]);
      AKind := Kind;
      AName := Copy(ABranch, Best + 1, MaxInt);
      Result := True;
    end;
end;

function FlowBranchesOf(const AFlow: TGittanFlow; ABranches: TStrings): TGittanFlowBranches;
var
  Kind, Found: TGittanFlowKind;
  Name: string;
  i: integer;
begin
  Result := nil;
  for Kind := Low(Kind) to High(Kind) do
    for i := 0 to ABranches.Count - 1 do
      if FlowKindOf(AFlow, ABranches[i], Found, Name) and (Found = Kind) then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)].Kind := Kind;
        Result[High(Result)].Name := Name;
        Result[High(Result)].Branch := ABranches[i];
      end;
end;

function ListFlowBranches(const ARoot: string; const AFlow: TGittanFlow): TGittanFlowBranches;
var
  Output, Err: string;
  Names: TStringList;
begin
  Result := nil;
  if not AFlow.Initialized or not RunGitIn(ARoot, ['for-each-ref', '--format=%(refname:short)',
    'refs/heads/'], Output, Err) then
    Exit;
  Names := TStringList.Create;
  try
    Names.Text := StringReplace(Output, #13#10, #10, [rfReplaceAll]);
    Result := FlowBranchesOf(AFlow, Names);
  finally
    Names.Free;
  end;
end;

function FlowBase(const AFlow: TGittanFlow; AKind: TGittanFlowKind): string;
begin
  if AKind = fkHotfix then
    Result := AFlow.Master
  else
    Result := AFlow.Develop;
end;

function NextFlowVersion(const AVersion: string; AHotfix: boolean): string;
var
  Parts: TStringArray;
  Numbers: array of int64;
  i, j: integer;
begin
  Result := '';
  if AVersion = '' then
  begin
    if not AHotfix then
      Result := '1.0';
    Exit;
  end;
  Parts := AVersion.Split(['.']);
  SetLength(Numbers, Length(Parts));
  for i := 0 to High(Parts) do
  begin
    if (Parts[i] = '') or (Length(Parts[i]) > 15) then
      Exit;
    for j := 1 to Length(Parts[i]) do
      if not (Parts[i][j] in ['0'..'9']) then
        Exit;
    Numbers[i] := StrToInt64(Parts[i]);
  end;
  if AHotfix then
  begin
    while Length(Numbers) < 3 do
    begin
      SetLength(Numbers, Length(Numbers) + 1);
      Numbers[High(Numbers)] := 0;
    end;
    Inc(Numbers[High(Numbers)]);
  end
  else if Length(Numbers) = 1 then
    Inc(Numbers[0])
  else
  begin
    Inc(Numbers[1]);
    for i := 2 to High(Numbers) do
      Numbers[i] := 0;
  end;
  for i := 0 to High(Numbers) do
  begin
    if i > 0 then
      Result := Result + '.';
    Result := Result + IntToStr(Numbers[i]);
  end;
end;

{ Tags that are not versions ("build-12" without a prefix) are passed
  over for the newest that is. }
function LatestFlowVersion(const ARoot: string; const AFlow: TGittanFlow): string;
var
  Output, Err, Tag, Version: string;
begin
  Result := '';
  if not RunGitIn(ARoot, ['tag', '--list', '--sort=-v:refname', AFlow.VersionTag + '*'],
    Output, Err) then
    Exit;
  for Tag in Output.Split([#10]) do
  begin
    Version := Copy(Trim(Tag), Length(AFlow.VersionTag) + 1, MaxInt);
    if (Version <> '') and (NextFlowVersion(Version, True) <> '') then
      Exit(Version);
  end;
end;

function StartFlowBranch(const ARoot: string; const AFlow: TGittanFlow;
  AKind: TGittanFlowKind; const AName: string; out AError: string): boolean;
var
  Output, Base: string;
begin
  AError := '';
  Base := FlowBase(AFlow, AKind);
  if not AFlow.Initialized or (Trim(AName) = '') then
  begin
    AError := 'Git flow is not set up.';
    Exit(False);
  end;
  if not EnsureBranch(ARoot, Base, '', AError) then
    Exit(False);
  Result := RunGitIn(ARoot, ['switch', '--no-track', '-c', AFlow.Prefix[AKind] + AName, Base],
    Output, AError);
end;

function FlowTargets(const ARoot: string; const AFlow: TGittanFlow;
  AKind: TGittanFlowKind): TStringArray;
var
  Releases: TGittanFlowBranches;
  Branch: TGittanFlowBranch;
  Release: string;
begin
  case AKind of
    fkFeature: Result := [AFlow.Develop];
    fkRelease: Result := [AFlow.Master, AFlow.Develop];
    else
    begin
      Release := '';
      Releases := ListFlowBranches(ARoot, AFlow);
      for Branch in Releases do
        if Branch.Kind = fkRelease then
        begin
          Release := Branch.Branch;
          Break;
        end;
      if Release = '' then
        Release := AFlow.Develop;
      Result := [AFlow.Master, Release];
    end;
  end;
end;

function FlowTag(const AFlow: TGittanFlow; const AName: string): string;
begin
  Result := AFlow.VersionTag + AName;
end;

{ merge-base --is-ancestor exits with 1 for no, which RunGitIn takes for
  a failure, as it does a real one: either way the merge is still to
  do. }
function IsMergedInto(const ARoot, ABranch, ATarget: string): boolean;
var
  Output, Err: string;
begin
  Result := RunGitIn(ARoot, ['merge-base', '--is-ancestor', 'refs/heads/' + ABranch,
    'refs/heads/' + ATarget], Output, Err);
end;

function CurrentBranch(const ARoot: string): string;
begin
  if not HeadBranchIn(ARoot, Result) then
    Result := '';
end;

function SwitchTo(const ARoot, ABranch: string; out AError: string): boolean;
var
  Output: string;
begin
  AError := '';
  if CurrentBranch(ARoot) = ABranch then
    Exit(True);
  Result := RunGitIn(ARoot, ['switch', ABranch], Output, AError);
end;

{ A merge that does not commit leaves its conflicts in the index (the
  unmerged entries ls-files -u lists). }
function MergeInto(const ARoot, ABranch, ATarget: string; out AConflicts: boolean;
  out AError: string): boolean;
var
  Output, Ignored: string;
begin
  AConflicts := False;
  if not SwitchTo(ARoot, ATarget, AError) then
    Exit(False);
  Result := RunGitEnv(ARoot, WithConflictStyle(ARoot, ['merge', '--no-ff', '--no-edit', ABranch]),
    ['GIT_EDITOR=:'], Output, AError);
  if not Result then
    AConflicts := RunGitIn(ARoot, ['ls-files', '-u'], Output, Ignored) and (Trim(Output) <> '');
end;

function FinishFlowBranch(const ARoot: string; const AFlow: TGittanFlow;
  AKind: TGittanFlowKind; const AName, ATagMessage: string; out AConflicts: boolean;
  out AStoppedAt, AError: string): boolean;
var
  Branch, Tag, Output, Err, Target: string;
  Targets: TStringArray;
  Tagged, Ok: boolean;
begin
  Result := False;
  AConflicts := False;
  AStoppedAt := '';
  AError := '';
  Branch := AFlow.Prefix[AKind] + AName;
  if not AFlow.Initialized or (AName = '') or not HasBranch(ARoot, Branch) then
  begin
    AError := Format('There is no branch %s.', [Branch]);
    Exit;
  end;
  if not RunGitIn(ARoot, ['status', '--porcelain', '--untracked-files=no'], Output, AError) then
    Exit;
  if Trim(Output) <> '' then
  begin
    AError := 'The work tree has changes that are not committed. Commit or stash them first.';
    Exit;
  end;
  Targets := FlowTargets(ARoot, AFlow, AKind);
  for Target in Targets do
    if not EnsureBranch(ARoot, Target, '', AError) then
      Exit;
  { The finish ends on the development branch, which a hotfix into a
    release under way has not among its targets. }
  if not EnsureBranch(ARoot, AFlow.Develop, '', AError) then
    Exit;
  Tagged := AKind in [fkRelease, fkHotfix];
  Tag := FlowTag(AFlow, AName);
  { A tag there already is the one a finish stopped after making, so it
    must hold the branch, merged into the production branch. }
  if Tagged and HasRef(ARoot, 'refs/tags/' + Tag) and
    not (IsMergedInto(ARoot, Branch, AFlow.Master) and
    RunGitIn(ARoot, ['merge-base', '--is-ancestor', 'refs/heads/' + Branch, 'refs/tags/' + Tag],
    Output, Err)) then
  begin
    AError := Format('The tag %s is there already.', [Tag]);
    Exit;
  end;
  for Target in Targets do
  begin
    if not IsMergedInto(ARoot, Branch, Target) then
      if not MergeInto(ARoot, Branch, Target, AConflicts, AError) then
      begin
        if AConflicts then
          AStoppedAt := Target;
        Exit;
      end;
    if Tagged and (Target = AFlow.Master) and not HasRef(ARoot, 'refs/tags/' + Tag) then
    begin
      if ATagMessage <> '' then
        Ok := RunGitIn(ARoot, ['tag', '-a', '-m', ATagMessage, Tag, 'refs/heads/' + Target],
          Output, AError)
      else
        Ok := RunGitIn(ARoot, ['tag', Tag, 'refs/heads/' + Target], Output, AError);
      if not Ok then
        Exit;
    end;
  end;
  { Merged everywhere it goes, which is what -d would check, against
    HEAD alone. }
  Result := SwitchTo(ARoot, AFlow.Develop, AError) and
    RunGitIn(ARoot, ['branch', '-D', Branch], Output, AError);
end;

end.
