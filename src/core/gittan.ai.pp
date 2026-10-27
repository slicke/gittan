unit gittan.ai;

{** The AI features: a commit message, a review of the changes shown,
  and where something is in the repository. Each is a job here that
  collects what the AI is given, asks it and reads its answer. The AI
  is one of the agents the settings pick (TGittanAgent), each a class
  of TGittanAI that its own unit registers as it loads (RegisterAI,
  AIClassOf), as the forges register with gittan.forge: the command
  line tools, Claude Code's claude (claude -p) and GitHub Copilot's
  copilot, in gittan.agentcli, and a model asked over HTTP at an
  OpenAI-compatible API in gittan.openai, with what an API of any
  shape shares (TGittanApi: a server, a key and a model) here. A tool
  runs with the user's own login and settings, reads the repository's
  own instructions (CLAUDE.md, AGENTS.md, and for Copilot
  .github/copilot-instructions.md) and may read the repository's files,
  but gets no tool that writes, runs a command or goes to the network;
  the API's model sees what it is sent alone. The prompts (TaskPrompt)
  say which (ReadsFiles).

  The commit message: the changes that would be committed are
  collected as a diff (CommitChanges), given to the AI with the
  repository's recent subjects, and its answer goes into the message
  field. The review: the diff the change view shows, its lines numbered
  on both sides (NumberDiff), so the AI names lines as the view counts
  them, and its findings (ParseReviewFindings) are review threads the
  change view shows as it shows a pull request's. Where something is:
  the user's words (with the repository's file list for a model that
  cannot search, FindListInput, which then gets the files it named
  with their lines numbered in a second round, FindLinesInput, for
  their lines), and the files it names (ParseFoundFiles) a list to
  pick from under the filter field. The
  features are off until they are turned on in the settings, since the
  changes go to the agent's provider. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.job, gittan.reviews, gittan.git;

type
  {** The agents Gittan can ask: two command line tools, and a model at
    an OpenAI-compatible API. Each has a class (AIClassOf). }
  TGittanAgent = (gaClaude, gaCopilot, gaOpenAI);

  {** What an agent is asked to do; atLocate is the second round of a
    find for a model that cannot read files, the lines in the files it
    named. }
  TGittanAITask = (atMessage, atReview, atFind, atLocate);

const
  {** What the agents are called in the interface; an API's model is
    named instead where one is set (TGittanAI.Title). }
  AgentNames: array[TGittanAgent] of string = ('Claude Code', 'GitHub Copilot',
    'OpenAI-compatible API');
  {** The agents' keys in the settings (AgentOfKey), the names of the
    tools' commands; the API has no command, only its key. }
  AgentCommands: array[TGittanAgent] of string = ('claude', 'copilot', 'openai');
  {** The most of the diff given to the agent, in bytes; the rest is cut
    at a line end and said to be, the summary of every file still whole. }
  MessageDiffKeep = 80000;
  {** How many of the recent subjects show the agent the repository's
    style. }
  MessageSubjects = 10;
  {** The most findings of a review kept; the prompt asks for fewer. }
  ReviewMaxFindings = 10;
  {** The most files of an answer to where something is kept. }
  FindMaxFiles = 10;

type
  {** A file the agent named for where something is: its path in the
    repository (with /), the line it is at (0 for the file as a whole)
    and a few words on what is there. }
  TGittanFoundFile = record
    Path: string;
    Line: integer;
    Why: string;
  end;
  TGittanFoundFiles = array of TGittanFoundFile;

  {** An agent as the settings set it up, made once from them (FindAI
    in the frame) and copied into each job (Clone), since a job may
    outlive the settings it was made from. What it is made of: APath,
    the tool's command or the API's server (Find gives it from the
    setting); AKey, the API's key, empty for a tool or a server that
    takes none; AModel, the model, empty for a tool's own choice. It
    changes nothing after it is made, so a copy may be asked from any
    thread. }
  TGittanAI = class
  private
    FPath, FKey, FModel: string;
  public
    constructor Create(const APath, AKey, AModel: string); virtual;
    {** The same agent again, for a job of its own. }
    function Clone: TGittanAI;
    {** Which of the agents this is. }
    class function Kind: TGittanAgent; virtual; abstract;
    {** AgentNames of it. }
    class function Name: string;
    {** Whether it is a model at an API (a server, a key and a model in
      the settings) rather than a command. }
    class function IsApi: boolean; virtual;
    {** Whether it reads the repository's files itself, as a tool does,
      or sees only what it is sent, as a model at an API does; the
      prompts say which, and the find gives such a model the file list. }
    class function ReadsFiles: boolean; virtual; abstract;
    {** The command, or the server, from ASetting, the setting's text:
      the path as given, else the command found on ToolSearchPath (and
      wherever the tool's own installer puts it), or the API's default
      server. Empty when there is none. }
    class function Find(const ASetting: string): string; virtual; abstract;
    {** Whether it can be asked: the command found, or the server and
      a model set. }
    function Available: boolean; virtual;
    {** Its name for a message: the agent's, or the model's for an API,
      since that is who answers. }
    function Title: string; virtual;
    {** TaskPrompt as it reads files or not. }
    function Prompt(ATask: TGittanAITask): string;
    {** Puts ATask to it with AInput (the changes, the question) for the
      repository at ARoot, asking ACancel as it waits (True ends the
      command, or gives the request up): the answer as the agent gave
      it in AText, else why none in AError
      (the agent's own, what it wrote on standard error, or that it gave
      no answer). }
    function Ask(const ARoot: string; ATask: TGittanAITask; const AInput: string;
      ACancel: TGittanCancelEvent; out AText, AError: string): boolean; virtual; abstract;
    {** A line for the About page: the agent and its version, asked of
      the command (a second or more, so from a thread), or the model and
      its server; empty when the command answered no version. }
    function About: string; virtual; abstract;
    property Path: string read FPath;
    property Key: string read FKey;
    property Model: string read FModel;
  end;
  TGittanAIClass = class of TGittanAI;

  {** A model at an API: Path is the server's base URL, Key goes with
    every request, Model is asked and must be set. It sees what it is
    sent alone. }
  TGittanApi = class(TGittanAI)
  public
    {** The server when the settings name none. }
    class function DefaultUrl: string; virtual; abstract;
    class function IsApi: boolean; override;
    class function ReadsFiles: boolean; override;
    {** ASetting, else DefaultUrl. }
    class function Find(const ASetting: string): string; override;
    function Available: boolean; override;
    {** The model, when one is set. }
    function Title: string; override;
    {** The model at the server. }
    function About: string; override;
  end;

{** Registers AClass as the agent of its Kind, from its unit's
  initialization; the last registered for a kind counts. }
procedure RegisterAI(AClass: TGittanAIClass);

{** The class registered for AAgent, nil when none is. }
function AIClassOf(AAgent: TGittanAgent): TGittanAIClass;

{** The agent whose key (AgentCommands) is AKey; Claude Code for any
  other, the first the settings offered. }
function AgentOfKey(const AKey: string): TGittanAgent;

{** The prompt for ATask, for an agent that reads the repository's files
  itself (AReadsFiles: it is told it may, where that helps) or one that
  sees what it is sent alone (told it cannot, and for where something
  is to judge by the file list it is given); atLocate is such a
  model's alone, whatever AReadsFiles says. }
function TaskPrompt(ATask: TGittanAITask; AReadsFiles: boolean): string;

{** What a commit of APaths in the work tree of the repository at ARoot
  would change, amending HEAD with AAmend, as the agent is given it: the
  recent subjects, the summary (diff --stat) and the diff, cut at
  MessageDiffKeep. The diff is made in a temporary index (HEAD's tree,
  the paths added as they are on disk), so untracked files show as the
  commit would take them and the real index is left alone. False, with
  git's reason in AError, when git failed; an empty AText when nothing
  would change. }
function CommitChanges(const ARoot: string; APaths: TStrings; AAmend: boolean;
  out AText, AError: string): boolean;

{** What the change view shows of the repository at ARoot compared with
  ABase (empty for HEAD; ARange when it is a range, A..B or A...B), as
  the agent is given it for a review: the summary and the diff, its
  lines numbered (NumberDiff), cut at MessageDiffKeep. Against a commit
  the diff is the work tree's, made as CommitChanges makes it for
  APaths, every changed file, so untracked files are in it; a range is
  diffed as it is. False, with git's reason in AError, when git failed;
  an empty AText when nothing differs. }
function ReviewChanges(const ARoot, ABase: string; ARange: boolean; APaths: TStrings;
  out AText, AError: string): boolean;

{** ADiff, a unified diff, with every line of its hunks numbered as the
  change view numbers it: a context or added line with "N" and its line
  in the new side, a removed line with "O" and its line in the old side
  ("N12 +text", "O7 -text"); the file headers and hunk headers are left
  as they are. }
function NumberDiff(const ADiff: string): string;

{** The findings of a review in AText, the agent's answer: a JSON array
  of objects with path, line, side ("old" for a line of the old side),
  severity and body, which may come inside a code fence or after a
  sentence. Each with a path, a line and a body is a thread in AThreads
  with AAgent as its agent and its comment's author, at most
  ReviewMaxFindings. False when AText holds no such array; an empty
  array is no finding. }
function ParseReviewFindings(const AText, AAgent: string;
  out AThreads: TGittanReviewThreads): boolean;

{** The repository's files at ARoot, tracked and untracked but not
  ignored, a path a line, cut at MessageDiffKeep with a line that says
  so: what a model that cannot search is given to find where something
  is. False, with git's reason in AError, when git failed. }
function RepoFileList(const ARoot: string; out AList, AError: string): boolean;

{** What such a model gets for where AQuestion is: the question, then
  AFiles (RepoFileList). }
function FindListInput(const AQuestion, AFiles: string): string;

{** What such a model gets for the lines, once it named AFiles
  (ParseFoundFiles of its first answer): AQuestion, then each file of
  AFiles that is in the work tree at ARoot (none out of it) with its
  lines numbered ("12: text"), cut at its share of MessageDiffKeep (at
  a line end, or mid-line when the share holds none) with a line that
  says so, the share split among the files that are there and only
  that much of a file read; a binary file (one with a NUL in
  what is read) is named without its text. Empty when none of them is
  there. }
function FindLinesInput(const ARoot, AQuestion: string;
  const AFiles: TGittanFoundFiles): string;

{** Puts the lines of ALines, the model's second answer, into AFiles by
  path: a file's line and, when given, its why; a file ALines does not
  name keeps line 0. }
procedure MergeFoundLines(var AFiles: TGittanFoundFiles; const ALines: TGittanFoundFiles);

{** The files of an answer to where something is in AText: a JSON array
  of objects with path, line and why, which may come inside a code fence
  or after a sentence. Each with a path is kept, "./" taken off it and
  its backslashes made /, a missing or negative line 0, at most
  FindMaxFiles. False when AText holds no such array; an empty array is
  no file. }
function ParseFoundFiles(const AText: string; out AFiles: TGittanFoundFiles): boolean;

{** AText as a commit message: blank lines around it trimmed, and a code
  fence around the whole of it taken off, which a model adds at times. }
function CleanCommitMessage(const AText: string): string;

type
  {** What the jobs below share: the repository at ARoot and the agent,
    its own copy of AAI (Clone), and Ask. Each runs in a thread, since
    the agent takes some seconds, and may be given up: Stop ends a
    command and gives up a request to an API, so leaving the repository
    or quitting does not wait for an answer. }
  TGittanAgentJob = class(TGittanJob)
  private
    function GetAgentName: string;
  protected
    FRoot: string;
    FAI: TGittanAI;
    function Cancelled: boolean;
    {** Puts ATask to the agent with AInput (the changes, the question);
      the answer as the agent gave it in AText, else why none in AError.
      False too when the job was stopped meanwhile. }
    function Ask(ATask: TGittanAITask; const AInput: string;
      out AText, AError: string): boolean;
  public
    constructor Create(const ARoot: string; AAI: TGittanAI);
    destructor Destroy; override;
    property Root: string read FRoot;
    property AI: TGittanAI read FAI;
    {** The agent's name for a message (TGittanAI.Title). }
    property AgentName: string read GetAgentName;
  end;

  {** Writes a commit message for APaths of the repository (see
    CommitChanges), amending HEAD with AAmend. }
  TGittanMessageJob = class(TGittanAgentJob)
  private
    FPaths: TStringList;
    FAmend: boolean;
    FOk: boolean;
    FMessage, FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: string; AAI: TGittanAI; APaths: TStrings;
      AAmend: boolean);
    destructor Destroy; override;
    {** Whether a message was written. }
    property Ok: boolean read FOk;
    {** The message, when Ok. }
    property Message: string read FMessage;
    {** Why there is none, when not Ok: git's or the agent's reason, or
      that there is nothing to describe. }
    property Error: string read FError;
  end;

  {** Reviews what the change view shows of the repository against
    ABase (see ReviewChanges). AViewKey is the caller's, to tell whether
    the findings are still for what is shown when they come. }
  TGittanAIReviewJob = class(TGittanAgentJob)
  private
    FBase, FViewKey: string;
    FRange: boolean;
    FPaths: TStringList;
    FOk: boolean;
    FThreads: TGittanReviewThreads;
    FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: string; AAI: TGittanAI; const ABase: string;
      ARange: boolean; APaths: TStrings; const AViewKey: string);
    destructor Destroy; override;
    property Key: string read FViewKey;
    {** Whether the agent answered with findings, none among them too. }
    property Ok: boolean read FOk;
    property Threads: TGittanReviewThreads read FThreads;
    {** Why there are none, when not Ok. }
    property Error: string read FError;
  end;

  {** Asks the agent where AQuestion is in the repository (a model that
    cannot search gets the file list with it, RepoFileList, and then
    the files it named with their text, for their lines). }
  TGittanFindJob = class(TGittanAgentJob)
  private
    FQuestion: string;
    FOk: boolean;
    FFiles: TGittanFoundFiles;
    FError: string;
    procedure LocateLines;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: string; AAI: TGittanAI; const AQuestion: string);
    property Question: string read FQuestion;
    {** Whether the agent answered with files, none among them too. }
    property Ok: boolean read FOk;
    property Files: TGittanFoundFiles read FFiles;
    {** Why there are none, when not Ok. }
    property Error: string read FError;
  end;

resourcestring
  rsNothingToReview = 'There are no changes to review.';
  rsReviewNotRead = 'The answer was no list of findings: %s';
  rsFoundNotRead = 'The answer was no list of files: %s';
  rsNothingToDescribe = 'There are no changes to describe.';
  rsAgentNoAnswer = '%s gave no answer.';
  rsAboutApi = '%s at %s';

implementation

uses
  Math, fpjson, jsonparser, DateUtils;

const
  { Short, whatever the repository's own messages are like: a model told
    only to follow the conventions wrote pages, describing every file it
    read. A tool may read a file when the diff leaves the change
    unclear; a model at an API sees the diff alone. }
  CommitPromptStart = 'Write the git commit message for the changes given below, ' +
    'which are what will be committed. Keep it short: a subject line of at most 72 ' +
    'characters and, only when the change needs explaining, a blank line and a body ' +
    'of a few lines wrapped at 72 columns. Say what changed and why, not what each ' +
    'file or line does. Take the style (language, tense, prefixes) from the recent ' +
    'commit subjects given. ';
  CommitReadNote = 'Read the repository''s files only when the diff alone leaves the ' +
    'change unclear. ';
  CommitPromptEnd = 'Answer with the message alone, ready for git commit: no ' +
    'preamble, no explanation, no code fences, no trailers.';

  { Only what matters, as a list the change view can place: a model
    asked to review without a limit lists style and praise, and counts
    lines in a hunk wrongly unless they are numbered for it. }
  ReviewPromptStart = 'Review the changes given below: a diff with each line ' +
    'numbered, N for a line of the new side and O for a line of the old side. ' +
    'Point out only real problems: bugs, wrong results, crashes, data loss, ' +
    'security holes, races, edge cases the change misses. Leave out style, naming, ' +
    'formatting, praise and summaries. At most 10 findings, fewer is better, and ' +
    'none is a fine answer. ';
  ReviewReadNote = 'You may read the repository''s files to check a finding. ';
  ReviewSentNote = 'You see the diff alone and cannot open the files, so say so in a ' +
    'finding that would need checking against the rest of its file. ';
  ReviewPromptEnd = 'Answer with a JSON array alone, no code fences, each finding ' +
    '{"path": the file as the diff names it, "line": the number after N or O, ' +
    '"side": "new" for N or "old" for O, "severity": "bug", "risk" or "question", ' +
    '"body": a few sentences in Markdown}.';

  { The files that hold it, as a list to pick from: a model asked where
    something is otherwise answers in prose, and names a folder or a
    file it has not opened. A model that cannot search is given the
    paths alone. }
  FindPromptStart = 'Find where in this repository the thing asked about below is: ' +
    'the files that define, implement or handle it. ';
  FindReadNote = 'Search and read the repository''s files to be sure; name only files ' +
    'that are there. ';
  FindSentNote = 'The question is followed by the paths of the repository''s files; ' +
    'you cannot open them, so judge by their paths and names alone, and name only ' +
    'paths from the list. ';
  FindPromptEnd = 'Answer with a JSON array alone, no code fences, the best match ' +
    'first, at most 10 files, fewer is better, and an empty array when nothing ' +
    'fits, each {"path": the file relative to the repository root with /, "line": ' +
    'the line where it is, 0 for the file as a whole, "why": a few words on what ' +
    'is there}.';

  { The lines, once a model that cannot search has named the files from
    their paths: their text, numbered, which it reads as a tool would
    have. A tool never gets this round, so there is no read note. }
  LocatePromptStart = 'Find the lines where the thing asked about below is: the ' +
    'question is followed by the files that may hold it, each with its lines ' +
    'numbered. Judge by the text given alone. ';
  LocatePromptEnd = 'Answer with a JSON array alone, no code fences, the best match ' +
    'first, one entry for a file at most and none for a file that does not hold ' +
    'it, each {"path": the file as given, "line": the number of the line where ' +
    'it is defined, implemented or handled, "why": a few words on what is there}.';

var
  AIClasses: array[TGittanAgent] of TGittanAIClass;

procedure RegisterAI(AClass: TGittanAIClass);
begin
  AIClasses[AClass.Kind] := AClass;
end;

function AIClassOf(AAgent: TGittanAgent): TGittanAIClass;
begin
  Result := AIClasses[AAgent];
end;

function AgentOfKey(const AKey: string): TGittanAgent;
var
  A: TGittanAgent;
begin
  for A in TGittanAgent do
    if SameText(AKey, AgentCommands[A]) then
      Exit(A);
  Result := gaClaude;
end;

function TaskPrompt(ATask: TGittanAITask; AReadsFiles: boolean): string;
begin
  case ATask of
    atMessage:
      if AReadsFiles then
        Result := CommitPromptStart + CommitReadNote + CommitPromptEnd
      else
        Result := CommitPromptStart + CommitPromptEnd;
    atReview:
      if AReadsFiles then
        Result := ReviewPromptStart + ReviewReadNote + ReviewPromptEnd
      else
        Result := ReviewPromptStart + ReviewSentNote + ReviewPromptEnd;
    atFind:
      if AReadsFiles then
        Result := FindPromptStart + FindReadNote + FindPromptEnd
      else
        Result := FindPromptStart + FindSentNote + FindPromptEnd;
    else { atLocate }
      Result := LocatePromptStart + LocatePromptEnd;
  end;
end;

{ TGittanAI }

constructor TGittanAI.Create(const APath, AKey, AModel: string);
begin
  inherited Create;
  FPath := APath;
  FKey := AKey;
  FModel := AModel;
end;

function TGittanAI.Clone: TGittanAI;
begin
  Result := TGittanAIClass(ClassType).Create(FPath, FKey, FModel);
end;

class function TGittanAI.Name: string;
begin
  Result := AgentNames[Kind];
end;

class function TGittanAI.IsApi: boolean;
begin
  Result := False;
end;

function TGittanAI.Available: boolean;
begin
  Result := FPath <> '';
end;

function TGittanAI.Title: string;
begin
  Result := Name;
end;

function TGittanAI.Prompt(ATask: TGittanAITask): string;
begin
  Result := TaskPrompt(ATask, ReadsFiles);
end;

{ TGittanApi }

class function TGittanApi.IsApi: boolean;
begin
  Result := True;
end;

class function TGittanApi.ReadsFiles: boolean;
begin
  Result := False;
end;

class function TGittanApi.Find(const ASetting: string): string;
begin
  Result := Trim(ASetting);
  if Result = '' then
    Result := DefaultUrl;
end;

function TGittanApi.Available: boolean;
begin
  Result := (FPath <> '') and (FModel <> '');
end;

function TGittanApi.Title: string;
begin
  if FModel <> '' then
    Result := FModel
  else
    Result := Name;
end;

function TGittanApi.About: string;
begin
  Result := Format(rsAboutApi, [Title, FPath]);
end;

{ AText up to MessageDiffKeep bytes, cut at a line end, with a line that
  says it was: ANote, with the bytes left out and the whole. }
function KeepText(const AText, ANote: string): string;
var
  Cut: integer;
begin
  if Length(AText) <= MessageDiffKeep then
    Exit(AText);
  Cut := MessageDiffKeep;
  while (Cut > 0) and (AText[Cut] <> #10) do
    Dec(Cut);
  Result := Copy(AText, 1, Cut) + Format(ANote, [Length(AText) - Cut, Length(AText)]) +
    LineEnding;
end;

function KeepDiff(const ADiff: string): string;
begin
  Result := KeepText(ADiff, '[The diff is cut here: %d of its %d bytes are left out. ' +
    'The summary above lists every file.]');
end;

function RepoFileList(const ARoot: string; out AList, AError: string): boolean;
begin
  Result := RunGitIn(ARoot, ['ls-files', '--cached', '--others', '--exclude-standard'],
    AList, AError);
  if Result then
    AList := KeepText(AList, '[The list is cut here: %d of its %d bytes are left out.]');
end;

function FindListInput(const AQuestion, AFiles: string): string;
begin
  Result := 'The question: ' + AQuestion + LineEnding + LineEnding +
    'The repository''s files:' + LineEnding + AFiles;
end;

{ AText with its lines numbered from 1, "12: text". }
function NumberLines(const AText: string): string;
var
  Lines: TStringList;
  Text: TStringBuilder;
  i: integer;
begin
  Lines := TStringList.Create;
  Text := TStringBuilder.Create;
  try
    Lines.Text := AText;
    for i := 0 to Lines.Count - 1 do
    begin
      Text.Append(IntToStr(i + 1));
      Text.Append(': ');
      Text.Append(Lines[i]);
      Text.Append(#10);
    end;
    Result := Text.ToString;
  finally
    Text.Free;
    Lines.Free;
  end;
end;

{ Where AText, a file's share, is cut: at its last line end, or at its
  end when it holds none (one long line), so something is kept. }
function CutAt(const AText: string): integer;
begin
  Result := Length(AText);
  while (Result > 0) and (AText[Result] <> #10) do
    Dec(Result);
  if Result = 0 then
    Result := Length(AText);
end;

{ Whether APath, as the model gave it, stays in the repository: not
  absolute, no .. in it. }
function InsideRepo(const APath: string): boolean;
begin
  Result := (APath <> '') and (APath[1] <> '/') and (Pos(':', APath) = 0) and
    (Pos('/../', '/' + APath + '/') = 0);
end;

function FindLinesInput(const ARoot, AQuestion: string;
  const AFiles: TGittanFoundFiles): string;
var
  Names: array of string;
  Count, Share, i: integer;
  Whole: int64;
  Text: string;
  Stream: TFileStream;
begin
  Result := '';
  { The files that are there share the budget; one named but out of the
    repository or missing takes none of it. }
  Count := 0;
  SetLength(Names, Length(AFiles));
  for i := 0 to High(AFiles) do
    if InsideRepo(AFiles[i].Path) then
    begin
      Names[i] := IncludeTrailingPathDelimiter(ARoot) +
        StringReplace(AFiles[i].Path, '/', PathDelim, [rfReplaceAll]);
      if FileExists(Names[i]) then
        Inc(Count)
      else
        Names[i] := '';
    end;
  if Count = 0 then
    Exit;
  Share := MessageDiffKeep div Count;
  for i := 0 to High(AFiles) do
  begin
    if Names[i] = '' then
      Continue;
    { Only the share is read: a big file is neither loaded nor numbered
      whole. }
    try
      Stream := TFileStream.Create(Names[i], fmOpenRead or fmShareDenyNone);
      try
        Whole := Stream.Size;
        SetLength(Text, Min(Whole, Share));
        if Text <> '' then
          Stream.ReadBuffer(Text[1], Length(Text));
      finally
        Stream.Free;
      end;
    except
      Continue;
    end;
    Result := Result + 'File: ' + AFiles[i].Path + LineEnding;
    if Pos(#0, Text) > 0 then
      Result := Result + '[A binary file; its text is not shown.]' + LineEnding
    else
    begin
      { Cut at a line end (CutAt) before it is numbered. }
      if Whole > Share then
        SetLength(Text, CutAt(Text));
      Result := Result + NumberLines(Text);
      if Whole > Share then
        Result := Result + Format('[The file is cut here: %d of its %d bytes are ' +
          'left out.]', [Whole - Length(Text), Whole]) + LineEnding;
    end;
    Result := Result + LineEnding;
  end;
  if Result <> '' then
    Result := 'The question: ' + AQuestion + LineEnding + LineEnding + Result;
end;

procedure MergeFoundLines(var AFiles: TGittanFoundFiles; const ALines: TGittanFoundFiles);
var
  i, j: integer;
begin
  for i := 0 to High(AFiles) do
    for j := 0 to High(ALines) do
      if (ALines[j].Path = AFiles[i].Path) and (ALines[j].Line > 0) then
      begin
        AFiles[i].Line := ALines[j].Line;
        if ALines[j].Why <> '' then
          AFiles[i].Why := ALines[j].Why;
        Break;
      end;
end;

const
  EmptyTreeId = '4b825dc642cb6eb9a060e54bf8d69288fbee4904';

{ Whether the repository at ARoot has HEAD, and HEAD a parent. }
procedure HeadState(const ARoot: string; out AHasHead, AHasParent: boolean);
var
  Output, Error: string;
begin
  AHasHead := RunGitIn(ARoot, ['rev-parse', '--verify', '-q', 'HEAD^{commit}'], Output,
    Error);
  AHasParent := AHasHead and RunGitIn(ARoot, ['rev-parse', '--verify', '-q',
    'HEAD~1^{commit}'], Output, Error);
end;

{ The summary and the diff of the work tree's APaths against ABase,
  made in a temporary index (HEAD's tree, or none without AHasHead,
  with the paths added as they are on disk), so untracked files are in
  it and the real index is left alone. }
function IndexDiff(const ARoot, ABase: string; AHasHead: boolean; APaths: TStrings;
  out AStat, ADiff, AError: string): boolean;
var
  Index, List, Output, Entry: string;
  Stream: TFileStream;
  i: integer;
begin
  AStat := '';
  ADiff := '';
  AError := '';
  Index := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-ai-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  List := Index + '.paths';
  Index := Index + '.index';
  try
    if AHasHead then
      Result := RunGitIn(ARoot, ['read-tree', 'HEAD'], Output, AError, Index)
    else
      Result := RunGitIn(ARoot, ['read-tree', '--empty'], Output, AError, Index);
    if not Result then
      Exit;
    if APaths.Count > 0 then
    begin
      { The paths in a file, NUL separated, as TGittanRepo.Commit gives
        them, so no command line grows with them. }
      Stream := TFileStream.Create(List, fmCreate);
      try
        for i := 0 to APaths.Count - 1 do
        begin
          Entry := APaths[i] + #0;
          Stream.WriteBuffer(Entry[1], Length(Entry));
        end;
      finally
        Stream.Free;
      end;
      Result := RunGitIn(ARoot, ['--literal-pathspecs', 'add', '-A',
        '--pathspec-from-file=' + List, '--pathspec-file-nul'], Output, AError, Index);
      if not Result then
        Exit;
    end;
    Result := RunGitIn(ARoot, ['diff', '--cached', '--stat=100', ABase], AStat, AError,
      Index) and RunGitIn(ARoot, ['diff', '--cached', '--no-ext-diff', '-M', ABase], ADiff,
      AError, Index);
  finally
    DeleteFile(Index);
    DeleteFile(List);
  end;
end;

function CommitChanges(const ARoot: string; APaths: TStrings; AAmend: boolean;
  out AText, AError: string): boolean;
var
  Base, Stat, Diff, Subjects, Output: string;
  HasHead, HasParent: boolean;
begin
  AText := '';
  HeadState(ARoot, HasHead, HasParent);
  { What the commit is compared with: HEAD, or HEAD's parent for an amend,
    which replaces HEAD; the empty tree before the first commit. }
  if AAmend and HasParent then
    Base := 'HEAD~1'
  else if HasHead and not AAmend then
    Base := 'HEAD'
  else
    Base := EmptyTreeId;
  Result := IndexDiff(ARoot, Base, HasHead, APaths, Stat, Diff, AError);
  if not Result or (Trim(Diff) = '') then
    Exit;
  Subjects := '';
  if HasHead then
    RunGitIn(ARoot, ['log', '-n', IntToStr(MessageSubjects), '--format=%s', 'HEAD'],
      Subjects, Output);
  if Trim(Subjects) <> '' then
    AText := 'Recent commit subjects of the repository, newest first:' + LineEnding +
      Subjects + LineEnding;
  if AAmend then
    AText := AText + 'The commit amends HEAD, so its changes are those of HEAD and ' +
      'the work tree together.' + LineEnding + LineEnding;
  AText := AText + 'The changes (git diff --stat):' + LineEnding + Stat + LineEnding +
    'The diff:' + LineEnding + KeepDiff(Diff);
end;

function ReviewChanges(const ARoot, ABase: string; ARange: boolean; APaths: TStrings;
  out AText, AError: string): boolean;
var
  Base, Stat, Diff: string;
  HasHead, HasParent: boolean;
begin
  AText := '';
  if ARange then
    Result := RunGitIn(ARoot, ['diff', '--stat=100', ABase], Stat, AError) and
      RunGitIn(ARoot, ['diff', '--no-ext-diff', '-M', ABase], Diff, AError)
  else
  begin
    HeadState(ARoot, HasHead, HasParent);
    Base := ABase;
    if Base = '' then
      if HasHead then
        Base := 'HEAD'
      else
        Base := EmptyTreeId;
    Result := IndexDiff(ARoot, Base, HasHead, APaths, Stat, Diff, AError);
  end;
  if not Result or (Trim(Diff) = '') then
    Exit;
  AText := 'The changes (git diff --stat):' + LineEnding + Stat + LineEnding +
    'The diff, each line numbered (N for the new side, O for the old):' + LineEnding +
    KeepDiff(NumberDiff(Diff));
end;

{ The number after AMark ('-' or '+') in the hunk header AHeader. }
function HunkStart(const AHeader: string; AMark: char): integer;
var
  p, q: integer;
begin
  Result := 0;
  p := Pos(' ' + AMark, AHeader);
  if p = 0 then
    Exit;
  q := p + 2;
  while (q <= Length(AHeader)) and (AHeader[q] in ['0'..'9']) do
    Inc(q);
  Result := StrToIntDef(Copy(AHeader, p + 2, q - p - 2), 0);
end;

function NumberDiff(const ADiff: string): string;
var
  Lines: TStringList;
  Text: TStringBuilder;
  i, OldLine, NewLine: integer;
  S: string;
  InHunk: boolean;
begin
  Lines := TStringList.Create;
  Text := TStringBuilder.Create;
  try
    Lines.Text := ADiff;
    InHunk := False;
    OldLine := 0;
    NewLine := 0;
    for i := 0 to Lines.Count - 1 do
    begin
      S := Lines[i];
      if Copy(S, 1, 2) = '@@' then
      begin
        InHunk := True;
        OldLine := HunkStart(S, '-');
        NewLine := HunkStart(S, '+');
      end
      else if Copy(S, 1, 5) = 'diff ' then
        InHunk := False
      else if InHunk and (S <> '') and (S[1] = '-') then
      begin
        S := 'O' + IntToStr(OldLine) + ' ' + S;
        Inc(OldLine);
      end
      else if InHunk and (S <> '') and (S[1] = '+') then
      begin
        S := 'N' + IntToStr(NewLine) + ' ' + S;
        Inc(NewLine);
      end
      else if InHunk and ((S = '') or (S[1] = ' ')) then
      begin
        S := 'N' + IntToStr(NewLine) + ' ' + S;
        Inc(OldLine);
        Inc(NewLine);
      end;
      Text.Append(S);
      Text.Append(#10);
    end;
    Result := Text.ToString;
  finally
    Text.Free;
    Lines.Free;
  end;
end;

function ParseReviewFindings(const AText, AAgent: string;
  out AThreads: TGittanReviewThreads): boolean;
var
  Data: TJSONData;
  Item: TJSONObject;
  Thread: TGittanReviewThread;
  First, Last, i, n: integer;
  Body: string;
begin
  AThreads := nil;
  { The array from its first bracket to its last, whatever is around it. }
  First := Pos('[', AText);
  Last := LastDelimiter(']', AText);
  if (First = 0) or (Last < First) then
    Exit(False);
  try
    Data := GetJSON(Copy(AText, First, Last - First + 1));
  except
    Exit(False);
  end;
  try
    Result := Data is TJSONArray;
    if not Result then
      Exit;
    n := 0;
    SetLength(AThreads, Min(Data.Count, ReviewMaxFindings));
    for i := 0 to Data.Count - 1 do
    begin
      if n >= Length(AThreads) then
        Break;
      if not (Data.Items[i] is TJSONObject) then
        Continue;
      Item := TJSONObject(Data.Items[i]);
      Body := Trim(Item.Get('body', ''));
      Thread := Default(TGittanReviewThread);
      Thread.Path := Item.Get('path', '');
      { A path as git prints it in a diff header. }
      if (Copy(Thread.Path, 1, 2) = 'a/') or (Copy(Thread.Path, 1, 2) = 'b/') then
        Delete(Thread.Path, 1, 2);
      if Item.Find('line') is TJSONNumber then
        Thread.Line := Item.Get('line', 0)
      else
        Thread.Line := StrToIntDef(Item.Get('line', ''), 0);
      if (Thread.Path = '') or (Thread.Line <= 0) or (Body = '') then
        Continue;
      Thread.OriginalLine := Thread.Line;
      Thread.LeftSide := SameText(Item.Get('side', ''), 'old');
      Thread.Agent := AAgent;
      Thread.Severity := LowerCase(Item.Get('severity', ''));
      SetLength(Thread.Comments, 1);
      Thread.Comments[0].Author := AAgent;
      Thread.Comments[0].Body := StringReplace(Body, #13#10, #10, [rfReplaceAll]);
      Thread.Comments[0].Created := LocalTimeToUniversal(Now);
      AThreads[n] := Thread;
      Inc(n);
    end;
    SetLength(AThreads, n);
  finally
    Data.Free;
  end;
end;

function ParseFoundFiles(const AText: string; out AFiles: TGittanFoundFiles): boolean;
var
  Data: TJSONData;
  Item: TJSONObject;
  Found: TGittanFoundFile;
  First, Last, i, n: integer;
begin
  AFiles := nil;
  { The array from its first bracket to its last, whatever is around it. }
  First := Pos('[', AText);
  Last := LastDelimiter(']', AText);
  if (First = 0) or (Last < First) then
    Exit(False);
  try
    Data := GetJSON(Copy(AText, First, Last - First + 1));
  except
    Exit(False);
  end;
  try
    Result := Data is TJSONArray;
    if not Result then
      Exit;
    n := 0;
    SetLength(AFiles, Min(Data.Count, FindMaxFiles));
    for i := 0 to Data.Count - 1 do
    begin
      if n >= Length(AFiles) then
        Break;
      if not (Data.Items[i] is TJSONObject) then
        Continue;
      Item := TJSONObject(Data.Items[i]);
      Found := Default(TGittanFoundFile);
      Found.Path := StringReplace(Trim(Item.Get('path', '')), '\', '/', [rfReplaceAll]);
      if Copy(Found.Path, 1, 2) = './' then
        Delete(Found.Path, 1, 2);
      if Found.Path = '' then
        Continue;
      if Item.Find('line') is TJSONNumber then
        Found.Line := Max(0, Item.Get('line', 0))
      else
        Found.Line := Max(0, StrToIntDef(Item.Get('line', ''), 0));
      Found.Why := Trim(Item.Get('why', ''));
      AFiles[n] := Found;
      Inc(n);
    end;
    SetLength(AFiles, n);
  finally
    Data.Free;
  end;
end;

function CleanCommitMessage(const AText: string): string;
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := Trim(AText); //split on LF, CR or CRLF, whatever the agent wrote
    if (Lines.Count >= 2) and (Copy(Trim(Lines[0]), 1, 3) = '```') and
      (Trim(Lines[Lines.Count - 1]) = '```') then
    begin
      Lines.Delete(Lines.Count - 1);
      Lines.Delete(0);
    end;
    Lines.LineBreak := #10; //a commit message's lines end in LF on Windows too
    Result := Trim(Lines.Text);
  finally
    Lines.Free;
  end;
end;

{ TGittanAgentJob }

constructor TGittanAgentJob.Create(const ARoot: string; AAI: TGittanAI);
begin
  { Given up on Stop: Execute asks Cancelled while the command runs. }
  inherited Create(True);
  FRoot := ARoot;
  FAI := AAI.Clone;
end;

destructor TGittanAgentJob.Destroy;
begin
  inherited Destroy;
  FAI.Free;
end;

function TGittanAgentJob.GetAgentName: string;
begin
  Result := FAI.Title;
end;

function TGittanAgentJob.Cancelled: boolean;
begin
  Result := Terminated;
end;

function TGittanAgentJob.Ask(ATask: TGittanAITask; const AInput: string;
  out AText, AError: string): boolean;
begin
  Result := FAI.Ask(FRoot, ATask, AInput, @Cancelled, AText, AError);
  if Terminated then
  begin
    AText := '';
    AError := '';
    Result := False;
  end;
end;

{ TGittanMessageJob }

constructor TGittanMessageJob.Create(const ARoot: string; AAI: TGittanAI;
  APaths: TStrings; AAmend: boolean);
begin
  inherited Create(ARoot, AAI);
  FPaths := TStringList.Create;
  FPaths.AddStrings(APaths);
  FAmend := AAmend;
end;

destructor TGittanMessageJob.Destroy;
begin
  inherited Destroy;
  FPaths.Free;
end;

procedure TGittanMessageJob.Execute;
var
  Changes, Answer: string;
begin
  if not CommitChanges(FRoot, FPaths, FAmend, Changes, FError) then
  begin
    Done;
    Exit;
  end;
  if Changes = '' then
  begin
    FError := rsNothingToDescribe;
    Done;
    Exit;
  end;
  if Terminated then
    Exit;
  FOk := Ask(atMessage, Changes, Answer, FError);
  if Terminated then
    Exit;
  if FOk then
  begin
    FMessage := CleanCommitMessage(Answer);
    FOk := FMessage <> '';
    if not FOk then
      FError := Format(rsAgentNoAnswer, [AgentName]);
  end;
  Done;
end;

{ TGittanAIReviewJob }

constructor TGittanAIReviewJob.Create(const ARoot: string; AAI: TGittanAI;
  const ABase: string; ARange: boolean; APaths: TStrings; const AViewKey: string);
begin
  inherited Create(ARoot, AAI);
  FBase := ABase;
  FRange := ARange;
  FPaths := TStringList.Create;
  FPaths.AddStrings(APaths);
  FViewKey := AViewKey;
end;

destructor TGittanAIReviewJob.Destroy;
begin
  inherited Destroy;
  FPaths.Free;
end;

procedure TGittanAIReviewJob.Execute;
var
  Changes, Answer: string;
begin
  if not ReviewChanges(FRoot, FBase, FRange, FPaths, Changes, FError) then
  begin
    Done;
    Exit;
  end;
  if Changes = '' then
  begin
    FError := rsNothingToReview;
    Done;
    Exit;
  end;
  if Terminated then
    Exit;
  FOk := Ask(atReview, Changes, Answer, FError);
  if Terminated then
    Exit;
  if FOk then
  begin
    FOk := ParseReviewFindings(Answer, AgentName, FThreads);
    if not FOk then
      FError := Format(rsReviewNotRead, [Copy(Trim(Answer), 1, 300)]);
  end;
  Done;
end;

{ TGittanFindJob }

constructor TGittanFindJob.Create(const ARoot: string; AAI: TGittanAI;
  const AQuestion: string);
begin
  inherited Create(ARoot, AAI);
  FQuestion := AQuestion;
end;

procedure TGittanFindJob.Execute;
var
  Input, List, Answer: string;
begin
  { A model that cannot search gets the file list to pick from. }
  Input := FQuestion;
  if not FAI.ReadsFiles then
  begin
    if not RepoFileList(FRoot, List, FError) then
    begin
      Done;
      Exit;
    end;
    Input := FindListInput(FQuestion, List);
  end;
  if Terminated then
    Exit;
  FOk := Ask(atFind, Input, Answer, FError);
  if Terminated then
    Exit;
  if FOk then
  begin
    FOk := ParseFoundFiles(Answer, FFiles);
    if not FOk then
      FError := Format(rsFoundNotRead, [Copy(Trim(Answer), 1, 300)])
    else if not FAI.ReadsFiles and (Length(FFiles) > 0) then
      LocateLines;
  end;
  if Terminated then
    Exit;
  Done;
end;

{ The second round for a model that cannot read files: the files it
  named with their text, for their lines. An answer that is none leaves
  the files as they are, without lines, since they are still worth
  showing. }
procedure TGittanFindJob.LocateLines;
var
  Input, Answer, Why: string;
  Lines: TGittanFoundFiles;
begin
  Input := FindLinesInput(FRoot, FQuestion, FFiles);
  if (Input = '') or Terminated then
    Exit;
  if Ask(atLocate, Input, Answer, Why) and ParseFoundFiles(Answer, Lines) then
    MergeFoundLines(FFiles, Lines);
end;

end.
