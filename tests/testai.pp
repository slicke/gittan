unit testai;

{** Tests of gittan.ai: the changes a commit message is written for and
  a review sees, made against a repository in a temporary folder with
  the real git, the prompts, the reading of the answers, and the file
  list a model that cannot search is given. The agents themselves are
  tested in testagentcli and testopenai; none is run here. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.git, gittan.reviews, gittan.ai,
  testhelpers;

type
  TAiTest = class(TTestCase)
  private
    FDir: string;
    procedure Git(const AArgs: array of string);
    procedure WriteFile(const AName, AContent: string);
    function Changes(const APaths: array of string; AAmend: boolean = False): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestChangesOfChosenPaths;
    procedure TestChangesBeforeFirstCommit;
    procedure TestChangesAmend;
    procedure TestNoChanges;
    procedure TestLongDiffIsCut;
    procedure TestCleanMessage;
    procedure TestAgentOfKey;
    procedure TestNumberDiff;
    procedure TestParseFindings;
    procedure TestParseFindingsAround;
    procedure TestReviewChangesWorkTree;
    procedure TestReviewChangesRange;
    procedure TestParseFoundFiles;
    procedure TestTaskPrompt;
    procedure TestRepoFileList;
    procedure TestFindListInput;
  end;

implementation

procedure TAiTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-ai-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
  Git(['init', '-q']);
end;

procedure TAiTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TAiTest.Git(const AArgs: array of string);
var
  Output, Error: string;
begin
  Error := '';
  AssertTrue('git ' + AArgs[0] + ': ' + Error, RunGitIn(FDir, AArgs, Output, Error));
end;

procedure TAiTest.WriteFile(const AName, AContent: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Text := AContent;
    L.SaveToFile(IncludeTrailingPathDelimiter(FDir) + AName);
  finally
    L.Free;
  end;
end;

function TAiTest.Changes(const APaths: array of string; AAmend: boolean): string;
var
  Paths: TStringList;
  Error: string;
  S: string;
begin
  Error := '';
  Paths := TStringList.Create;
  try
    for S in APaths do
      Paths.Add(S);
    AssertTrue('CommitChanges: ' + Error, CommitChanges(FDir, Paths, AAmend, Result, Error));
  finally
    Paths.Free;
  end;
end;

procedure TAiTest.TestChangesOfChosenPaths;
var
  Text, Output, Error: string;
begin
  WriteFile('a.txt', 'one');
  WriteFile('b.txt', 'two');
  Git(['add', '.']);
  Git(['commit', '-q', '-m', 'Add a and b']);
  WriteFile('a.txt', 'one changed');
  WriteFile('b.txt', 'two changed');
  WriteFile('new file.txt', 'brand new');
  Git(['add', 'b.txt']);
  Text := Changes(['a.txt', 'new file.txt']);
  AssertTrue('the subjects', Pos('Add a and b', Text) > 0);
  AssertTrue('a tracked file', Pos('+one changed', Text) > 0);
  AssertTrue('an untracked file', Pos('+brand new', Text) > 0);
  AssertTrue('the summary', Pos('git diff --stat', Text) > 0);
  AssertEquals('a file not chosen is left out', 0, Pos('two changed', Text));
  { The real index is left as it was. }
  AssertTrue(RunGitIn(FDir, ['diff', '--cached', '--name-only'], Output, Error));
  AssertEquals('b.txt', Trim(Output));
end;

procedure TAiTest.TestChangesBeforeFirstCommit;
var
  Text: string;
begin
  WriteFile('first.txt', 'hello');
  Text := Changes(['first.txt']);
  AssertTrue(Pos('+hello', Text) > 0);
  AssertEquals('no subjects without a commit', 0, Pos('Recent commit', Text));
end;

procedure TAiTest.TestChangesAmend;
var
  Text: string;
begin
  WriteFile('a.txt', 'one');
  Git(['add', '.']);
  Git(['commit', '-q', '-m', 'First']);
  WriteFile('a.txt', 'two');
  Git(['commit', '-q', '-am', 'Second']);
  { Amending with nothing new describes HEAD's own change. }
  Text := Changes([], True);
  AssertTrue(Pos('-one', Text) > 0);
  AssertTrue(Pos('+two', Text) > 0);
  AssertTrue(Pos('amends HEAD', Text) > 0);
end;

procedure TAiTest.TestNoChanges;
begin
  WriteFile('a.txt', 'one');
  Git(['add', '.']);
  Git(['commit', '-q', '-m', 'First']);
  AssertEquals('', Changes(['a.txt']));
end;

procedure TAiTest.TestLongDiffIsCut;
var
  Text, Big: string;
  i: integer;
begin
  Big := '';
  for i := 1 to MessageDiffKeep div 20 do
    Big := Big + Format('line number %8d', [i]) + LineEnding;
  WriteFile('big.txt', Big);
  Text := Changes(['big.txt']);
  AssertTrue('said to be cut', Pos('The diff is cut here', Text) > 0);
  AssertTrue('near the limit', Length(Text) < MessageDiffKeep + 2000);
  AssertTrue('the summary is whole', Pos('big.txt', Text) > 0);
end;

procedure TAiTest.TestCleanMessage;
begin
  AssertEquals('Subject'#10#10'Body', CleanCommitMessage(#10'Subject'#10#10'Body'#10#10));
  AssertEquals('Subject'#10#10'Body', CleanCommitMessage('```'#10'Subject'#10#10'Body'#10'```'));
  AssertEquals('Subject', CleanCommitMessage('```text'#10'Subject'#10'```'#10));
  { An agent on Windows ends its lines in CRLF; the message ends them in
    LF there too. }
  AssertEquals('Subject'#10#10'Body', CleanCommitMessage('Subject'#13#10#13#10'Body'#13#10));
  { A fence inside the body stays. }
  AssertEquals('Subject'#10#10'```'#10'code'#10'```', CleanCommitMessage(
    'Subject'#10#10'```'#10'code'#10'```'));
end;

procedure TAiTest.TestAgentOfKey;
begin
  AssertTrue(AgentOfKey('copilot') = gaCopilot);
  AssertTrue(AgentOfKey('Copilot') = gaCopilot);
  AssertTrue(AgentOfKey('claude') = gaClaude);
  AssertTrue(AgentOfKey('openai') = gaOpenAI);
  AssertTrue('an unknown key is Claude Code', AgentOfKey('') = gaClaude);
end;

procedure TAiTest.TestNumberDiff;
var
  Text: string;
begin
  Text := NumberDiff('diff --git a/x.txt b/x.txt'#10'--- a/x.txt'#10'+++ b/x.txt'#10 +
    '@@ -10,3 +10,3 @@ func'#10' keep'#10'-old'#10'+new'#10' tail'#10 +
    '@@ -40 +40,2 @@'#10' same'#10'+added'#10);
  AssertTrue('headers stay', Pos(#10'--- a/x.txt'#10, Text) > 0);
  AssertTrue('hunk headers stay', Pos(#10'@@ -10,3 +10,3 @@ func'#10, Text) > 0);
  AssertTrue('context on the new side', Pos(#10'N10  keep'#10, Text) > 0);
  AssertTrue('a removed line on the old side', Pos(#10'O11 -old'#10, Text) > 0);
  AssertTrue('an added line on the new side', Pos(#10'N11 +new'#10, Text) > 0);
  AssertTrue('both sides go on after it', Pos(#10'N12  tail'#10, Text) > 0);
  AssertTrue('a hunk without a count', Pos(#10'N40  same'#10'N41 +added'#10, Text) > 0);
end;

procedure TAiTest.TestParseFindings;
var
  T: TGittanReviewThreads;
begin
  AssertTrue(ParseReviewFindings('[{"path":"src/a.pp","line":12,"side":"new",' +
    '"severity":"Bug","body":"Off by one."},{"path":"b/src/b.pp","line":"7",' +
    '"side":"old","severity":"risk","body":"Gone check."},{"path":"","line":3,' +
    '"body":"no path"},{"path":"c","line":0,"body":"no line"},{"path":"d","line":4,' +
    '"body":"  "}]', 'Claude Code', T));
  AssertEquals('the ones without a path, a line or a body are left out', 2, Length(T));
  AssertEquals('src/a.pp', T[0].Path);
  AssertEquals(12, T[0].Line);
  AssertFalse(T[0].LeftSide);
  AssertEquals('bug', T[0].Severity);
  AssertEquals('Claude Code', T[0].Agent);
  AssertEquals('Claude Code', T[0].Comments[0].Author);
  AssertEquals('Off by one.', T[0].Comments[0].Body);
  AssertEquals('', T[0].Comments[0].Url);
  AssertEquals('a diff path loses its prefix', 'src/b.pp', T[1].Path);
  AssertEquals('a line given as text', 7, T[1].Line);
  AssertTrue(T[1].LeftSide);
  AssertTrue('no findings', ParseReviewFindings('[]', 'Claude Code', T));
  AssertEquals(0, Length(T));
end;

procedure TAiTest.TestParseFindingsAround;
var
  T: TGittanReviewThreads;
  Many: string;
  i: integer;
begin
  AssertTrue('in a fence after a sentence', ParseReviewFindings('Here they are:'#10 +
    '```json'#10'[{"path":"a","line":1,"body":"x [y]"}]'#10'```', 'GitHub Copilot', T));
  AssertEquals(1, Length(T));
  AssertEquals('x [y]', T[0].Comments[0].Body);
  AssertFalse('no array', ParseReviewFindings('Nothing to point out.', 'Claude Code', T));
  AssertFalse('not JSON', ParseReviewFindings('[oops', 'Claude Code', T));
  Many := '[';
  for i := 1 to 15 do
  begin
    if i > 1 then
      Many := Many + ',';
    Many := Many + Format('{"path":"a","line":%d,"body":"b"}', [i]);
  end;
  AssertTrue(ParseReviewFindings(Many + ']', 'Claude Code', T));
  AssertEquals('at most the limit', ReviewMaxFindings, Length(T));
end;

procedure TAiTest.TestReviewChangesWorkTree;
var
  Paths: TStringList;
  Text, Error: string;
begin
  WriteFile('a.txt', 'one'#10'two');
  Git(['add', '.']);
  Git(['commit', '-q', '-m', 'First']);
  WriteFile('a.txt', 'one'#10'two'#10'three');
  WriteFile('new.txt', 'fresh');
  Paths := TStringList.Create;
  try
    Paths.Add('a.txt');
    Paths.Add('new.txt');
    Error := '';
    AssertTrue(Error, ReviewChanges(FDir, '', False, Paths, Text, Error));
  finally
    Paths.Free;
  end;
  AssertTrue('numbered', Pos('N3 +three', Text) > 0);
  AssertTrue('an untracked file is in it', Pos('N1 +fresh', Text) > 0);
  AssertTrue('the summary', Pos('git diff --stat', Text) > 0);
end;

procedure TAiTest.TestReviewChangesRange;
var
  Paths: TStringList;
  Text, Error: string;
begin
  WriteFile('a.txt', 'one');
  Git(['add', '.']);
  Git(['commit', '-q', '-m', 'First']);
  Git(['tag', 'start']);
  WriteFile('a.txt', 'two');
  Git(['commit', '-q', '-am', 'Second']);
  WriteFile('a.txt', 'not committed');
  Paths := TStringList.Create;
  try
    Error := '';
    AssertTrue(Error, ReviewChanges(FDir, 'start..HEAD', True, Paths, Text, Error));
  finally
    Paths.Free;
  end;
  AssertTrue('the range', Pos('O1 -one', Text) > 0);
  AssertTrue(Pos('N1 +two', Text) > 0);
  AssertEquals('the work tree is no part of a range', 0, Pos('not committed', Text));
end;

procedure TAiTest.TestParseFoundFiles;
var
  F: TGittanFoundFiles;
  Many: string;
  i: integer;
begin
  AssertTrue(ParseFoundFiles('Here:'#10'```json'#10'[{"path":"src/a.pp","line":12,' +
    '"why":" The parser "},{"path":"./src\\b.pp","line":"7"},{"path":"","line":3},' +
    '{"path":"c.pp","line":-4}]'#10'```', F));
  AssertEquals('the one without a path is left out', 3, Length(F));
  AssertEquals('src/a.pp', F[0].Path);
  AssertEquals(12, F[0].Line);
  AssertEquals('The parser', F[0].Why);
  AssertEquals('./ off, backslashes made /', 'src/b.pp', F[1].Path);
  AssertEquals('a line given as text', 7, F[1].Line);
  AssertEquals('no why', '', F[1].Why);
  AssertEquals('a negative line is the file', 0, F[2].Line);
  AssertTrue('none', ParseFoundFiles('[]', F));
  AssertEquals(0, Length(F));
  AssertFalse('no array', ParseFoundFiles('It is in the parser.', F));
  Many := '[';
  for i := 1 to 15 do
  begin
    if i > 1 then
      Many := Many + ',';
    Many := Many + Format('{"path":"f%d"}', [i]);
  end;
  AssertTrue(ParseFoundFiles(Many + ']', F));
  AssertEquals('at most the limit', FindMaxFiles, Length(F));
end;

procedure TAiTest.TestTaskPrompt;
var
  Task: TGittanAITask;
begin
  for Task in TGittanAITask do
  begin
    AssertTrue('an agent that reads files may', Pos('read the repository''s files',
      LowerCase(TaskPrompt(Task, True))) > 0);
    AssertEquals('one that sees what it is sent may not', 0,
      Pos('read the repository''s files', LowerCase(TaskPrompt(Task, False))));
    AssertEquals('both get the same task', Copy(TaskPrompt(Task, True), 1, 30),
      Copy(TaskPrompt(Task, False), 1, 30));
  end;
  AssertTrue('the message is asked to be short', Pos('at most 72 characters',
    TaskPrompt(atMessage, True)) > 0);
  AssertTrue(Pos('JSON array', TaskPrompt(atReview, True)) > 0);
  AssertTrue(Pos('cannot open the files', TaskPrompt(atReview, False)) > 0);
  AssertTrue('the find prompt says the list follows', Pos('paths of the repository',
    TaskPrompt(atFind, False)) > 0);
  AssertTrue(Pos('JSON array', TaskPrompt(atFind, False)) > 0);
end;


procedure TAiTest.TestRepoFileList;
var
  List, Error: string;
begin
  WriteFile('a.txt', 'one');
  WriteFile('.gitignore', '*.log');
  Git(['add', '.']);
  Git(['commit', '-q', '-m', 'Add a']);
  WriteFile('new file.txt', 'brand new');
  WriteFile('build.log', 'noise');
  AssertTrue(RepoFileList(FDir, List, Error));
  AssertTrue('a tracked file', Pos('a.txt'#10, List) > 0);
  AssertTrue('an untracked file', Pos('new file.txt'#10, List) > 0);
  AssertEquals('an ignored file is left out', 0, Pos('build.log', List));
  AssertFalse('no repository', RepoFileList(FDir + '-none', List, Error));
end;

procedure TAiTest.TestFindListInput;
var
  Text: string;
begin
  Text := FindListInput('the parser', 'a.txt'#10'b.txt'#10);
  AssertEquals(1, Pos('The question: the parser', Text));
  AssertTrue(Pos('files:'#10'a.txt'#10'b.txt', Text) > 0);
end;

initialization

  RegisterTest(TAiTest);
end.
