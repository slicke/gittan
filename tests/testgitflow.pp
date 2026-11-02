unit testgitflow;

{** Tests of gittan.gitflow: the config read, the branches told apart
  by prefix and the next version, then git flow set up, a feature, a
  release and a hotfix started and finished in a repository made for
  the test, and a finish that stops on a conflict and goes on. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.git, gittan.gitflow, testhelpers;

type
  TGitFlowTest = class(TTestCase)
  private
    FDir: string;
    procedure Git(const AArgs: array of string);
    function GitOut(const AArgs: array of string): string;
    procedure WriteFile(const AName, AText: string);
    procedure CommitFile(const AName, AText, AMessage: string);
    function NewRepo: TGittanFlow;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestParse;
    procedure TestKindOf;
    procedure TestNextVersion;
    procedure TestInit;
    procedure TestFeature;
    procedure TestRelease;
    procedure TestHotfixIntoRelease;
    procedure TestConflictResumes;
    procedure TestDirtyRefused;
  end;

implementation

procedure TGitFlowTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-gitflow-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
end;

procedure TGitFlowTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TGitFlowTest.Git(const AArgs: array of string);
var
  Output, Err: string;
begin
  if not RunGitIn(FDir, AArgs, Output, Err) then
    Fail('git ' + AArgs[0] + ' failed: ' + Err);
end;

function TGitFlowTest.GitOut(const AArgs: array of string): string;
var
  Err: string;
begin
  if not RunGitIn(FDir, AArgs, Result, Err) then
    Result := '';
  Result := Trim(Result);
end;

procedure TGitFlowTest.WriteFile(const AName, AText: string);
begin
  with TStringList.Create do
    try
      Text := AText;
      SaveToFile(IncludeTrailingPathDelimiter(FDir) + AName);
    finally
      Free;
    end;
end;

{ A file's bytes as they are, and written back as they are (TStringList
  would end the text with a line break). }
function ReadRaw(const APath: string): string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

procedure WriteRaw(const APath, AText: string);
var
  F: TFileStream;
begin
  F := TFileStream.Create(APath, fmCreate);
  try
    if AText <> '' then
      F.WriteBuffer(AText[1], Length(AText));
  finally
    F.Free;
  end;
end;

procedure TGitFlowTest.CommitFile(const AName, AText, AMessage: string);
begin
  WriteFile(AName, AText);
  Git(['add', AName]);
  Git(['commit', '-q', '-m', AMessage]);
end;

function TGitFlowTest.NewRepo: TGittanFlow;
var
  Err: string;
begin
  Git(['init', '-q', '-b', 'main']);
  CommitFile('a.txt', 'a', 'first');
  Result := DefaultFlow('main');
  AssertTrue(Err, InitFlow(FDir, Result, Err));
  Result := ReadFlow(FDir);
  AssertTrue('initialized', Result.Initialized);
end;

procedure TGitFlowTest.TestParse;
var
  Flow: TGittanFlow;
begin
  Flow := ParseFlowConfig('');
  AssertFalse('nothing set', Flow.Initialized);
  AssertEquals('feature/', Flow.Prefix[fkFeature]);
  Flow := ParseFlowConfig('gitflow.branch.master main'#10'gitflow.branch.develop dev'#10 +
    'gitflow.prefix.feature feat/'#10'gitflow.prefix.release rel/'#10 +
    'gitflow.prefix.hotfix fix/'#10'gitflow.prefix.versiontag v'#10);
  AssertTrue(Flow.Initialized);
  AssertEquals('main', Flow.Master);
  AssertEquals('dev', Flow.Develop);
  AssertEquals('feat/', Flow.Prefix[fkFeature]);
  AssertEquals('rel/', Flow.Prefix[fkRelease]);
  AssertEquals('fix/', Flow.Prefix[fkHotfix]);
  AssertEquals('v', Flow.VersionTag);
  { An empty value has no space; a prefix left out has its default. }
  Flow := ParseFlowConfig('gitflow.branch.master main'#10'gitflow.branch.develop develop'#10 +
    'gitflow.prefix.versiontag'#10);
  AssertTrue(Flow.Initialized);
  AssertEquals('', Flow.VersionTag);
  AssertEquals('hotfix/', Flow.Prefix[fkHotfix]);
  AssertFalse('one branch for both', ParseFlowConfig('gitflow.branch.master main'#10 +
    'gitflow.branch.develop main'#10).Initialized);
end;

procedure TGitFlowTest.TestKindOf;
var
  Flow: TGittanFlow;
  Kind: TGittanFlowKind;
  Name: string;
  Names: TStringList;
  List: TGittanFlowBranches;
begin
  Flow := DefaultFlow('main');
  AssertFalse('not set up', FlowKindOf(Flow, 'feature/x', Kind, Name));
  Flow.Initialized := True;
  AssertTrue(FlowKindOf(Flow, 'feature/login/form', Kind, Name));
  AssertTrue(Kind = fkFeature);
  AssertEquals('login/form', Name);
  AssertTrue(FlowKindOf(Flow, 'hotfix/1.2.1', Kind, Name));
  AssertTrue(Kind = fkHotfix);
  AssertEquals('1.2.1', Name);
  AssertFalse('the prefix alone', FlowKindOf(Flow, 'feature/', Kind, Name));
  AssertFalse(FlowKindOf(Flow, 'develop', Kind, Name));
  Flow.Prefix[fkHotfix] := 'release/hot/';
  AssertTrue(FlowKindOf(Flow, 'release/hot/2', Kind, Name));
  AssertTrue('the longest prefix', Kind = fkHotfix);
  AssertEquals('2', Name);
  Flow.Prefix[fkHotfix] := 'hotfix/';
  Names := TStringList.Create;
  try
    Names.CommaText := 'main,hotfix/1.0.1,feature/b,develop,release/1.1,feature/a';
    List := FlowBranchesOf(Flow, Names);
  finally
    Names.Free;
  end;
  AssertEquals(4, Length(List));
  AssertEquals('feature/b', List[0].Branch);
  AssertEquals('a', List[1].Name);
  AssertEquals('release/1.1', List[2].Branch);
  AssertTrue(List[3].Kind = fkHotfix);
end;

procedure TGitFlowTest.TestNextVersion;
begin
  AssertEquals('1.3', NextFlowVersion('1.2', False));
  AssertEquals('1.3.0', NextFlowVersion('1.2.3', False));
  AssertEquals('5', NextFlowVersion('4', False));
  AssertEquals('1.0', NextFlowVersion('', False));
  AssertEquals('1.2.4', NextFlowVersion('1.2.3', True));
  AssertEquals('1.2.1', NextFlowVersion('1.2', True));
  AssertEquals('4.0.1', NextFlowVersion('4', True));
  AssertEquals('1.10', NextFlowVersion('1.9', False));
  AssertEquals('', NextFlowVersion('', True));
  AssertEquals('', NextFlowVersion('1.2-beta', False));
  AssertEquals('', NextFlowVersion('1..2', False));
  AssertEquals('', NextFlowVersion('$10', False));
end;

procedure TGitFlowTest.TestInit;
var
  Flow: TGittanFlow;
  Err, Config, Text: string;
begin
  Git(['init', '-q', '-b', 'master']);
  CommitFile('a.txt', 'a', 'first');
  AssertFalse(ReadFlow(FDir).Initialized);
  AssertEquals('the one that exists', 'master', SuggestFlowMaster(FDir));
  Flow := DefaultFlow('master');
  Flow.VersionTag := 'v';
  Flow.Develop := 'master';
  AssertFalse('one branch for both', InitFlow(FDir, Flow, Err));
  Flow.Develop := 'develop';
  Flow.Prefix[fkRelease] := '';
  AssertFalse('a prefix missing', InitFlow(FDir, Flow, Err));
  Flow.Prefix[fkRelease] := 'release/';
  AssertFalse('no such branch', InitFlow(FDir, DefaultFlow('trunk'), Err));
  AssertTrue(Err, InitFlow(FDir, Flow, Err));
  AssertEquals('develop made from master', GitOut(['rev-parse', 'master']),
    GitOut(['rev-parse', 'develop']));
  Flow := ReadFlow(FDir);
  AssertTrue(Flow.Initialized);
  AssertEquals('master', Flow.Master);
  AssertEquals('v', Flow.VersionTag);
  AssertEquals('what the git-flow command looks for', 'support/',
    GitOut(['config', 'gitflow.prefix.support']));
  AssertEquals('master', SuggestFlowMaster(FDir));
  { The empty prefix is written too, as the command wants it, into a
    config file that may lack its last line break; a setup done again
    adds no second section header. }
  Flow.VersionTag := '';
  Config := IncludeTrailingPathDelimiter(FDir) + '.git' + PathDelim + 'config';
  Text := ReadRaw(Config);
  WriteRaw(Config, TrimRight(Text));
  AssertTrue(Err, InitFlow(FDir, Flow, Err));
  AssertTrue('set, empty', Pos('gitflow.prefix.versiontag',
    GitOut(['config', '--get-regexp', 'versiontag'])) = 1);
  AssertEquals('', ReadFlow(FDir).VersionTag);
  AssertEquals('master', GitOut(['config', 'gitflow.branch.master']));
  Text := ReadRaw(Config);
  AssertTrue('a header', Pos('[gitflow "prefix"]', Text) > 0);
  AssertTrue(Err, InitFlow(FDir, Flow, Err));
  AssertEquals('', ReadFlow(FDir).VersionTag);
  AssertEquals('no header added', Length(Text), Length(ReadRaw(Config)));
  { The prefixes the git-flow command uses and Gittan does not are
    kept as the command set them. }
  Git(['config', 'gitflow.prefix.bugfix', 'fix/']);
  AssertTrue(Err, InitFlow(FDir, Flow, Err));
  AssertEquals('fix/', GitOut(['config', 'gitflow.prefix.bugfix']));
  AssertEquals('support/', GitOut(['config', 'gitflow.prefix.support']));
end;

procedure TGitFlowTest.TestFeature;
var
  Flow: TGittanFlow;
  Err, Stopped: string;
  Conflicts: boolean;
begin
  Flow := NewRepo;
  AssertTrue(Err, StartFlowBranch(FDir, Flow, fkFeature, 'login', Err));
  AssertEquals('feature/login', GitOut(['symbolic-ref', '--short', 'HEAD']));
  AssertEquals(1, Length(ListFlowBranches(FDir, Flow)));
  CommitFile('b.txt', 'b', 'login form');
  AssertTrue(Err, FinishFlowBranch(FDir, Flow, fkFeature, 'login', '', Conflicts, Stopped, Err));
  AssertEquals('on develop', 'develop', GitOut(['symbolic-ref', '--short', 'HEAD']));
  AssertEquals('deleted', '', GitOut(['branch', '--list', 'feature/login']));
  AssertEquals('a merge commit', 'Merge branch ''feature/login'' into develop',
    GitOut(['log', '-1', '--format=%s']));
  AssertTrue('main untouched', GitOut(['rev-parse', 'main']) <> GitOut(['rev-parse', 'develop']));
  AssertEquals(0, Length(ListFlowBranches(FDir, Flow)));
  AssertFalse('gone', FinishFlowBranch(FDir, Flow, fkFeature, 'login', '', Conflicts, Stopped,
    Err));
end;

procedure TGitFlowTest.TestRelease;
var
  Flow: TGittanFlow;
  Err, Stopped: string;
  Conflicts: boolean;
begin
  Flow := NewRepo;
  Flow.VersionTag := 'v';
  AssertTrue(Err, InitFlow(FDir, Flow, Err));
  Git(['tag', 'v1.4']);
  Git(['tag', 'v1.10']);
  Git(['tag', 'vnext']);
  AssertEquals('by version', '1.10', LatestFlowVersion(FDir, Flow));
  Git(['switch', '-q', 'develop']);
  CommitFile('b.txt', 'b', 'work');
  AssertTrue(Err, StartFlowBranch(FDir, Flow, fkRelease, '1.11', Err));
  CommitFile('version.txt', '1.11', 'bump');
  AssertTrue(Err, FinishFlowBranch(FDir, Flow, fkRelease, '1.11', 'Release 1.11', Conflicts,
    Stopped, Err));
  AssertEquals('develop', GitOut(['symbolic-ref', '--short', 'HEAD']));
  AssertEquals('', GitOut(['branch', '--list', 'release/1.11']));
  AssertEquals('tagged on main', GitOut(['rev-parse', 'main']), GitOut(['rev-parse',
    'v1.11^{commit}']));
  AssertEquals('annotated', 'tag', GitOut(['cat-file', '-t', 'v1.11']));
  AssertEquals('Release 1.11', GitOut(['tag', '-l', '--format=%(contents:subject)', 'v1.11']));
  AssertTrue('main has the release', FileExists(IncludeTrailingPathDelimiter(FDir) +
    'version.txt'));
  AssertEquals('the release merged into both', GitOut(['rev-parse', 'main^2']),
    GitOut(['rev-parse', 'develop^2']));
  AssertEquals('1.11', LatestFlowVersion(FDir, Flow));
end;

procedure TGitFlowTest.TestHotfixIntoRelease;
var
  Flow: TGittanFlow;
  Err, Stopped: string;
  Conflicts: boolean;
  Targets: TStringArray;
begin
  Flow := NewRepo;
  AssertTrue(Err, StartFlowBranch(FDir, Flow, fkHotfix, '1.0.1', Err));
  AssertEquals('from main', GitOut(['rev-parse', 'main']), GitOut(['rev-parse', 'HEAD']));
  Targets := FlowTargets(FDir, Flow, fkHotfix);
  AssertEquals('develop without a release', 'develop', Targets[1]);
  CommitFile('fix.txt', 'fix', 'the fix');
  Git(['switch', '-q', 'develop']);
  AssertTrue(Err, StartFlowBranch(FDir, Flow, fkRelease, '1.1', Err));
  Targets := FlowTargets(FDir, Flow, fkHotfix);
  AssertEquals(2, Length(Targets));
  AssertEquals('main', Targets[0]);
  AssertEquals('the release under way', 'release/1.1', Targets[1]);
  AssertTrue(Err, FinishFlowBranch(FDir, Flow, fkHotfix, '1.0.1', '', Conflicts, Stopped, Err));
  AssertEquals('a plain tag', 'commit', GitOut(['cat-file', '-t', '1.0.1']));
  AssertEquals('the fix merged into the release', GitOut(['rev-parse', 'main^2']),
    GitOut(['rev-parse', 'release/1.1^2']));
  AssertFalse('not on develop yet', RunGitIn(FDir, ['merge-base', '--is-ancestor', 'main^2',
    'develop'], Err, Stopped));
  AssertEquals('', GitOut(['branch', '--list', 'hotfix/1.0.1']));
end;

procedure TGitFlowTest.TestConflictResumes;
var
  Flow: TGittanFlow;
  Err, Stopped: string;
  Conflicts: boolean;
begin
  Flow := NewRepo;
  Git(['switch', '-q', 'develop']);
  AssertTrue(Err, StartFlowBranch(FDir, Flow, fkRelease, '2.0', Err));
  CommitFile('a.txt', 'release', 'release change');
  { develop changes the same line meanwhile; main does not. }
  Git(['switch', '-q', 'develop']);
  CommitFile('a.txt', 'develop', 'develop change');
  AssertFalse('stops', FinishFlowBranch(FDir, Flow, fkRelease, '2.0', 'Release 2.0', Conflicts,
    Stopped, Err));
  AssertTrue('conflicts', Conflicts);
  AssertEquals('develop', Stopped);
  AssertEquals('tagged before it stopped', GitOut(['rev-parse', 'main']),
    GitOut(['rev-parse', '2.0^{commit}']));
  AssertTrue('still there', GitOut(['branch', '--list', 'release/2.0']) <> '');
  { Resolved and committed, then finished again. }
  WriteFile('a.txt', 'both');
  Git(['add', 'a.txt']);
  Git(['-c', 'core.editor=true', 'commit', '-q', '--no-edit']);
  AssertTrue(Err, FinishFlowBranch(FDir, Flow, fkRelease, '2.0', 'Release 2.0', Conflicts,
    Stopped, Err));
  AssertEquals('', GitOut(['branch', '--list', 'release/2.0']));
  AssertEquals('one tag, where it was', GitOut(['rev-parse', 'main']),
    GitOut(['rev-parse', '2.0^{commit}']));
  AssertEquals('main merged once', 1, Length(GitOut(['rev-list', '--merges', 'main']).Split(
    [#10])));
end;

procedure TGitFlowTest.TestDirtyRefused;
var
  Flow: TGittanFlow;
  Err, Stopped: string;
  Conflicts: boolean;
begin
  Flow := NewRepo;
  AssertTrue(Err, StartFlowBranch(FDir, Flow, fkFeature, 'x', Err));
  CommitFile('b.txt', 'b', 'x');
  WriteFile('b.txt', 'changed');
  AssertFalse(FinishFlowBranch(FDir, Flow, fkFeature, 'x', '', Conflicts, Stopped, Err));
  AssertFalse(Conflicts);
  AssertTrue(Err, Pos('not committed', Err) > 0);
  AssertEquals('nothing done', 'feature/x', GitOut(['symbolic-ref', '--short', 'HEAD']));
  { An untracked file is no obstacle. }
  Git(['checkout', '--', 'b.txt']);
  WriteFile('new.txt', 'n');
  AssertTrue(Err, FinishFlowBranch(FDir, Flow, fkFeature, 'x', '', Conflicts, Stopped, Err));
end;

initialization
  RegisterTest(TGitFlowTest);
end.
