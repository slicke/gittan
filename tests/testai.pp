unit testai;

{** Tests of gittan.ai: the changes a commit message is written for and
  a review sees, made against a repository in a temporary folder with
  the real git, the prompts, the reading of the answers, and the file
  list a model that cannot search is given, and the find job's rounds
  with an agent of the test's own (TFakeAI) that answers what it is
  given. The agents themselves are tested in testagentcli and
  testopenai; none is run here. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.git, gittan.reviews, gittan.ai,
  testhelpers{$IFDEF UNIX}, BaseUnix{$ENDIF};

type
  {** An agent that answers Answers in turn (an empty one is a failure,
    "no answer"), keeps what it was asked in Tasks and Inputs, and reads
    files or not as Reads says. The job holds a clone, so all of it is
    the class's. HoldLocate makes the second round wait until the job
    is stopped (for the cancel test), and Cancelled says it was told. }
  TFakeAI = class(TGittanAI)
  public
    class var Reads, HoldLocate, Cancelled: boolean;
    class var Answers, Inputs: array of string;
    class var Tasks: array of TGittanAITask;
    class procedure Reset;
    class function Kind: TGittanAgent; override;
    class function ReadsFiles: boolean; override;
    class function Find(const ASetting: string): string; override;
    function Ask(const ARoot: string; ATask: TGittanAITask; const AInput: string;
      ACancel: TGittanCancelEvent; out AText, AError: string): boolean; override;
    function About: string; override;
  end;

  TAiTest = class(TTestCase)
  private
    FDir: string;
    FDone: integer;
    procedure Git(const AArgs: array of string);
    procedure WriteFile(const AName, AContent: string);
    function Changes(const APaths: array of string; AAmend: boolean = False): string;
    procedure JobDone(Sender: TObject);
    function RunFind(const AQuestion: string): TGittanFindJob;
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
    procedure TestFindLinesInput;
    procedure TestMergeFoundLines;
    procedure TestFindJobRounds;
    procedure TestFindJobSecondFails;
    procedure TestFindJobTool;
    procedure TestFindJobStopped;
  end;

implementation

{ TFakeAI }

class procedure TFakeAI.Reset;
begin
  Reads := False;
  HoldLocate := False;
  Cancelled := False;
  Answers := nil;
  Inputs := nil;
  Tasks := nil;
end;

class function TFakeAI.Kind: TGittanAgent;
begin
  Result := gaOpenAI;
end;

class function TFakeAI.ReadsFiles: boolean;
begin
  Result := Reads;
end;

class function TFakeAI.Find(const ASetting: string): string;
begin
  Result := ASetting;
end;

function TFakeAI.Ask(const ARoot: string; ATask: TGittanAITask; const AInput: string;
  ACancel: TGittanCancelEvent; out AText, AError: string): boolean;
var
  n, Waited: integer;
begin
  n := Length(Tasks);
  SetLength(Tasks, n + 1);
  Tasks[n] := ATask;
  SetLength(Inputs, n + 1);
  Inputs[n] := AInput;
  if (ATask = atLocate) and HoldLocate then
  begin
    Waited := 0;
    while not ACancel() and (Waited < 5000) do
    begin
      Sleep(10);
      Inc(Waited);
    end;
    Cancelled := ACancel();
  end;
  AText := '';
  if n < Length(Answers) then
    AText := Answers[n];
  AError := '';
  Result := AText <> '';
  if not Result then
    AError := 'no answer';
end;

function TFakeAI.About: string;
begin
  Result := '';
end;

{ TAiTest }

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

procedure TAiTest.JobDone(Sender: TObject);
begin
  Inc(FDone);
end;

{ A find job for AQuestion with the fake agent, run to its end, its
  queued notification let through as the application's loop would. }
function TAiTest.RunFind(const AQuestion: string): TGittanFindJob;
var
  AI: TGittanAI;
begin
  AI := TFakeAI.Create('', '', 'fake');
  try
    Result := TGittanFindJob.Create(FDir, AI, AQuestion);
  finally
    AI.Free;
  end;
  Result.OnDone := @JobDone;
  FDone := 0;
  Result.Start;
  Result.WaitFor;
  CheckSynchronize(0);
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
    AssertTrue('an agent that reads files may', (Task = atLocate) or
      (Pos('read the repository''s files', LowerCase(TaskPrompt(Task, True))) > 0));
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
  AssertTrue('the second round says the text follows', Pos('lines numbered',
    TaskPrompt(atLocate, False)) > 0);
  AssertTrue(Pos('JSON array', TaskPrompt(atLocate, False)) > 0);
  AssertEquals('one prompt for the second round, which no tool gets',
    TaskPrompt(atLocate, False), TaskPrompt(atLocate, True));
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
  AssertTrue('the list after its heading, on the platform''s line end', Pos('files:' +
    LineEnding + 'a.txt'#10'b.txt', Text) > 0);
end;

procedure TAiTest.TestFindLinesInput;
const
  List = 'a.pas'#10'missing.txt'#10'sub/b.txt'#10'bin.dat'#10'big.txt'#10'long.txt'#10 +
    'link.txt'#10'sub/link/c.txt'#10;
var
  Files: TGittanFoundFiles;
  Last: TGittanLineCounts;
  Text, Big, Outside: string;
  Stream: TFileStream;
  i: integer;
begin
  WriteFile('a.pas', 'one'#10'two'#10'three');
  ForceDirectories(FDir + PathDelim + 'sub');
  WriteFile('sub' + PathDelim + 'b.txt', 'four');
  Stream := TFileStream.Create(IncludeTrailingPathDelimiter(FDir) + 'bin.dat', fmCreate);
  try
    Text := 'x'#0'y';
    Stream.WriteBuffer(Text[1], Length(Text));
  finally
    Stream.Free;
  end;
  SetLength(Files, 5);
  Files[0].Path := 'a.pas';
  Files[1].Path := 'missing.txt';
  Files[2].Path := 'sub/b.txt';
  Files[3].Path := 'bin.dat';
  Files[4].Path := '../' + ExtractFileName(FDir) + '/a.pas';
  Text := FindLinesInput(FDir, 'the parser', List, Files, Last);
  AssertEquals(1, Pos('The question: the parser', Text));
  AssertEquals('the lines given of each', 3, Last[0]);
  AssertEquals(0, Last[1]);
  AssertEquals(1, Last[2]);
  AssertEquals('none of a binary file', 0, Last[3]);
  AssertEquals(0, Last[4]);
  AssertTrue('each line numbered', Pos('File: a.pas' + LineEnding +
    '1: one'#10'2: two'#10'3: three'#10, Text) > 0);
  AssertTrue('a file in a folder, by its path with /', Pos('File: sub/b.txt' +
    LineEnding + '1: four'#10, Text) > 0);
  AssertEquals('a file that is not there is left out', 0, Pos('missing.txt', Text));
  AssertTrue('a binary file is named without its text', Pos('File: bin.dat' +
    LineEnding + '[A binary file', Text) > 0);
  AssertEquals('no path out of the repository', 0, Pos('..', Text));
  AssertEquals('none there', '', FindLinesInput(FDir, 'q', List, Copy(Files, 1, 1), Last));
  { A file the list does not name, an ignored one, is not read. }
  WriteFile('secret.env', 'key');
  SetLength(Files, 1);
  Files[0].Path := 'secret.env';
  AssertEquals('not in the list', '', FindLinesInput(FDir, 'q', List, Files, Last));
  {$IFDEF UNIX}
  { Nor one through a symbolic link, the file or a folder, which may
    lead out of the repository. }
  Outside := FDir + '-outside';
  ForceDirectories(Outside);
  try
    WriteFile('..' + PathDelim + ExtractFileName(Outside) + PathDelim + 'c.txt', 'out');
    FpSymlink(PChar(Outside + PathDelim + 'c.txt'), PChar(FDir + PathDelim + 'link.txt'));
    FpSymlink(PChar(Outside), PChar(FDir + PathDelim + 'sub' + PathDelim + 'link'));
    SetLength(Files, 2);
    Files[0].Path := 'link.txt';
    Files[1].Path := 'sub/link/c.txt';
    AssertEquals('not through a link', '', FindLinesInput(FDir, 'q', List, Files, Last));
  finally
    RemoveTree(Outside);
  end;
  {$ENDIF}
  { A file past its share of the budget (the whole of it, for one file
    that is there) is cut at a line end before it is numbered: its first
    80000 bytes end in line 3119. }
  Big := '';
  for i := 1 to 10000 do
    Big := Big + 'line ' + IntToStr(i) + ' of the big file' + #10;
  Stream := TFileStream.Create(IncludeTrailingPathDelimiter(FDir) + 'big.txt', fmCreate);
  try
    Stream.WriteBuffer(Big[1], Length(Big));
  finally
    Stream.Free;
  end;
  SetLength(Files, 2);
  Files[0].Path := 'big.txt';
  Files[1].Path := 'missing.txt';
  Text := FindLinesInput(FDir, 'q', List, Files, Last);
  AssertTrue('the lines within the budget; a missing file takes no share of it',
    Pos(#10'3119: line 3119 of', Text) > 0);
  AssertEquals('none past it', 0, Pos(#10'3120: ', Text));
  AssertTrue('says how much is cut', Pos(Format('[The file is cut here: %d of its %d ' +
    'bytes are left out.]', [Length(Big) - Pos('line 3120 of', Big) + 1, Length(Big)]),
    Text) > 0);
  { One line longer than the share is cut where the share ends, not
    left out whole. }
  WriteFile('long.txt', StringOfChar('x', MessageDiffKeep + 100));
  Files[0].Path := 'long.txt';
  Text := FindLinesInput(FDir, 'q', List, Files, Last);
  AssertTrue('the share of the line', Pos('1: ' + StringOfChar('x', MessageDiffKeep) +
    #10'[The file is cut here: ', Text) > 0);
end;

procedure TAiTest.TestMergeFoundLines;
var
  Files, Lines: TGittanFoundFiles;
begin
  SetLength(Files, 2);
  Files[0].Path := 'a.pas';
  Files[0].Why := 'the parser';
  Files[1].Path := 'b.pas';
  Files[1].Why := 'its tests';
  SetLength(Lines, 2);
  Lines[0].Path := 'b.pas';
  Lines[0].Line := 7;
  Lines[1].Path := 'a.pas';
  Lines[1].Line := 42;
  Lines[1].Why := 'ParseIt';
  MergeFoundLines(Files, Lines, [50, 7]);
  AssertEquals('the first answer''s order', 'a.pas', Files[0].Path);
  AssertEquals(42, Files[0].Line);
  AssertEquals('a why given replaces', 'ParseIt', Files[0].Why);
  AssertEquals(7, Files[1].Line);
  AssertEquals('a why not given stays', 'its tests', Files[1].Why);
  Lines[0].Line := 8;
  MergeFoundLines(Files, Lines, [50, 7]);
  AssertEquals('a line past those given is none', 0, Files[1].Line);
  MergeFoundLines(Files, Lines, [50]);
  AssertEquals('nor one of a file not given', 0, Files[1].Line);
  SetLength(Lines, 0);
  MergeFoundLines(Files, Lines, [50, 7]);
  AssertEquals('a file not named again gets 0', 0, Files[0].Line);
end;

{ A model that cannot read files names the files from the list, then
  gets their text and gives the lines. }
procedure TAiTest.TestFindJobRounds;
var
  Job: TGittanFindJob;
begin
  WriteFile('a.pas', 'one'#10'two'#10'three');
  WriteFile('b.pas', 'four');
  TFakeAI.Reset;
  TFakeAI.Answers := ['[{"path":"a.pas","why":"the parser"},{"path":"b.pas","line":9}]',
    '[{"path":"a.pas","line":2,"why":"two"}]'];
  Job := RunFind('the parser');
  try
    AssertEquals(1, FDone);
    AssertTrue(Job.Error, Job.Ok);
    AssertEquals('two rounds', 2, Length(TFakeAI.Tasks));
    AssertTrue(TFakeAI.Tasks[0] = atFind);
    AssertTrue('the first gets the list', Pos('a.pas'#10'b.pas', TFakeAI.Inputs[0]) > 0);
    AssertTrue(TFakeAI.Tasks[1] = atLocate);
    AssertTrue('the second gets the text', Pos('File: a.pas' + LineEnding + '1: one'#10,
      TFakeAI.Inputs[1]) > 0);
    AssertTrue(Pos('File: b.pas', TFakeAI.Inputs[1]) > 0);
    AssertEquals(2, Length(Job.Files));
    AssertEquals('a.pas', Job.Files[0].Path);
    AssertEquals(2, Job.Files[0].Line);
    AssertEquals('two', Job.Files[0].Why);
    AssertEquals('a line guessed from the path is dropped', 0, Job.Files[1].Line);
  finally
    Job.Free;
  end;
end;

{ A second answer that fails leaves the first's files, without lines. }
procedure TAiTest.TestFindJobSecondFails;
var
  Job: TGittanFindJob;
begin
  WriteFile('a.pas', 'one');
  TFakeAI.Reset;
  TFakeAI.Answers := ['[{"path":"a.pas","why":"the parser"}]'];
  Job := RunFind('the parser');
  try
    AssertEquals(1, FDone);
    AssertTrue(Job.Error, Job.Ok);
    AssertEquals(2, Length(TFakeAI.Tasks));
    AssertEquals(1, Length(Job.Files));
    AssertEquals(0, Job.Files[0].Line);
    AssertEquals('the parser', Job.Files[0].Why);
    AssertEquals('', Job.Error);
  finally
    Job.Free;
  end;
end;

{ A tool that reads files gets the question alone, and no second round. }
procedure TAiTest.TestFindJobTool;
var
  Job: TGittanFindJob;
begin
  WriteFile('a.pas', 'one');
  TFakeAI.Reset;
  TFakeAI.Reads := True;
  TFakeAI.Answers := ['[{"path":"a.pas","line":1}]'];
  Job := RunFind('the parser');
  try
    AssertEquals(1, FDone);
    AssertTrue(Job.Ok);
    AssertEquals('one round', 1, Length(TFakeAI.Tasks));
    AssertEquals('the question alone', 'the parser', TFakeAI.Inputs[0]);
    AssertEquals(1, Job.Files[0].Line);
  finally
    Job.Free;
  end;
end;

{ A job stopped during the second round ends without a word. }
procedure TAiTest.TestFindJobStopped;
var
  AI: TGittanAI;
  Job: TGittanFindJob;
  Waited: integer;
begin
  WriteFile('a.pas', 'one');
  TFakeAI.Reset;
  TFakeAI.HoldLocate := True;
  TFakeAI.Answers := ['[{"path":"a.pas"}]', '[{"path":"a.pas","line":1}]'];
  AI := TFakeAI.Create('', '', 'fake');
  try
    Job := TGittanFindJob.Create(FDir, AI, 'the parser');
  finally
    AI.Free;
  end;
  try
    Job.OnDone := @JobDone;
    FDone := 0;
    Job.Start;
    Waited := 0;
    while (Length(TFakeAI.Tasks) < 2) and (Waited < 500) do
    begin
      Sleep(10);
      Inc(Waited);
    end;
    AssertEquals('reached the second round', 2, Length(TFakeAI.Tasks));
    Job.Stop(True);
    CheckSynchronize(0);
    AssertTrue('the agent was told', TFakeAI.Cancelled);
    AssertEquals('no word', 0, FDone);
  finally
    Job.Free;
  end;
end;

initialization
  RegisterTest(TAiTest);
end.
