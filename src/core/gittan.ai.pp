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
  pick from under the filter field. A conflict: its lines, the file's
  lines around it and the commits on either side (ConflictInput), and
  the lines the agent puts in its place (ParseResolution). The
  features are off until they are turned on in the settings, since the
  changes go to the agent's provider. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.job, gittan.reviews, gittan.git, gittan.discard;

type
  {** The agents Gittan can ask: two command line tools, and a model at
    an OpenAI-compatible API. Each has a class (AIClassOf). }
  TGittanAgent = (gaClaude, gaCopilot, gaOpenAI);

  {** What an agent is asked to do; atLocate is the second round of a
    find for a model that cannot read files, the lines in the files it
    named; atResolve resolves one conflict; atSplit groups the changed
    files into commits; atFix fixes what a review's finding points out;
    atWhy explains how lines came to be as they are. }
  TGittanAITask = (atMessage, atReview, atFind, atLocate, atResolve, atSplit, atFix,
    atWhy);

  {** How many lines of each file a model was given (FindLinesInput). }
  TGittanLineCounts = array of integer;

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
  {** How many of the file's lines before and after a conflict the agent
    is given with it. }
  ConflictAround = 20;
  {** The most commits of a plan kept; the prompt asks for fewer. }
  SplitMaxCommits = 10;
  {** How many of the commits that changed the lines the agent is given
    to explain them. }
  WhyCommits = 10;
  {** The severity of a thread that explains lines rather than points
    out a problem (TGittanReviewThread.Severity). }
  WhySeverity = 'history';

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

  {** One commit of a plan to split the changes: the changed files it
    takes and its message ('' for the files the agent left out). }
  TGittanPlannedCommit = record
    Files: TStringArray;
    Message: string;
  end;
  TGittanCommitPlan = array of TGittanPlannedCommit;

  {** One edit of a fix: lines of the file to find (once) and the lines
    to put in their place. }
  TGittanFixEdit = record
    Find, Replace: TStringArray;
  end;
  TGittanFixEdits = array of TGittanFixEdit;

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
  (ParseFoundFiles of its first answer) from AList (RepoFileList):
  AQuestion, then each file of AFiles that AList names and that is in
  the work tree at ARoot (none out of it, none through a symbolic link,
  which may lead out of it) with its lines numbered ("12: text"), cut at its share of MessageDiffKeep (at
  a line end, or mid-line when the share holds none) with a line that
  says so, the share split among the files that are there and only
  that much of a file read; a binary file (one with a NUL in
  what is read) is named without its text. ALast gets, for each of
  AFiles, how many of its lines were given, 0 for one left out. Empty
  when none of them is there. }
function FindLinesInput(const ARoot, AQuestion, AList: string;
  const AFiles: TGittanFoundFiles; out ALast: TGittanLineCounts): string;

{** Puts the lines of ALines, the model's second answer, into AFiles by
  path: a file's line, when it is one of the ALast[i] given
  (FindLinesInput), and then its why when given; any other line is 0,
  since a line from the first answer was guessed from the path. }
procedure MergeFoundLines(var AFiles: TGittanFoundFiles; const ALines: TGittanFoundFiles;
  const ALast: array of integer);

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

{** What the agent is given to resolve the conflict ABlock (NewLines its
  lines as the file holds them, markers included, at Line) in APath of
  the repository at ARoot: what git is in the middle of (AOperation, as
  the frame names it, "merging" or "rebasing"), which side of the
  markers is the user's own (the ">>>>>>>" one while ARebase, since a
  rebase replays the user's commits onto the upstream), the commit being
  applied and the commits on either side that changed the file
  (ConflictCommits), ConflictAround lines of the file before and after,
  and the conflict. }
function ConflictInput(const ARoot, APath, AOperation: string; ARebase: boolean;
  const ABlock: TGittanDiscard): string;

{** What the agent gets to split APaths, the changed files of the
  repository at ARoot, into commits: CommitChanges of them all, then
  the paths as they are to be named. False, with git's reason in AError,
  when git failed; an empty AText when nothing would change. }
function SplitInput(const ARoot: string; APaths: TStrings; out AText, AError: string): boolean;

{** The commits of a plan in AText, the agent's answer: a JSON array of
  objects with files and message, which may come inside a code fence or
  after a sentence. Only the paths of APaths are kept, each in the first
  commit that names it ("./", "a/" or "b/" taken off), a message cleaned
  as CleanCommitMessage cleans it, a commit left with no file dropped,
  at most SplitMaxCommits; the paths no commit took go in one more with
  no message, so every file is in the plan. False when AText holds no
  such array. }
function ParseCommitPlan(const AText: string; APaths: TStrings;
  out APlan: TGittanCommitPlan): boolean;

{** What the agent gets to fix AFinding (a review's, on the view's lines
  of its Path) in the repository at ARoot compared with ABase (empty for
  HEAD): the finding, the file's diff against the base, cut at half of
  MessageDiffKeep, and ALines, the file as it is, numbered: whole when
  it fits in what is left, else the lines round the finding's that do. }
function FixInput(const ARoot, ABase: string; const AFinding: TGittanReviewThread;
  const ALines: TStringArray): string;

{** The edits of a fix in AText, the agent's answer: each the lines
  between a line "<find>" and a line "</find>", then those between
  "<replace>" and "</replace>" (none is an answer too, the lines
  dropped), and in AWhy what is between "<why>" and "</why>", on one
  line. False when there is neither an edit nor a why, or an edit finds
  no line. }
function ParseFixEdits(const AText: string; out AEdits: TGittanFixEdits;
  out AWhy: string): boolean;

{** ALines with AEdits made in turn, in ANew: each edit's Find must be
  in the lines once, as they are, else with the spaces at the ends of
  the lines ignored, else without line numbers ("12: ") the agent copied
  from its input before each. False with the reason in AError when an
  edit is found nowhere or in more places than one. }
function ApplyFixEdits(const ALines: TStringArray; const AEdits: TGittanFixEdits;
  out ANew: TStringArray; out AError: string): boolean;

{** The block that turns ABefore, the lines of AFileName, into AAfter:
  the lines between those both begin and end with, as a TGittanDiscard
  whose write (DiscardBlock) puts AAfter's in place of ABefore's, and
  whose undo (Swapped) puts them back. }
function FixBlock(const AFileName: string; const ABefore, AAfter: TStringArray): TGittanDiscard;

{** What the agent gets to explain lines AFrom to ATo of APath in ARef
  of the repository at ARoot: the lines, then the history of their
  changes (git log -L, newest first, WhyCommits of them, each with its
  author, date, whole message and the diff of the lines), cut at
  MessageDiffKeep. False, with git's reason in AError, when git failed
  or found no history. }
function WhyInput(const ARoot, APath, ARef: string; AFrom, ATo: integer;
  out AText, AError: string): boolean;

{** The commits git's conflict in the repository at ARoot comes from, for
  APath: the commit being applied (the first of MERGE_HEAD,
  CHERRY_PICK_HEAD, REVERT_HEAD and REBASE_HEAD there is) with its
  message unless it is a merge's, and the commits since the merge base
  that changed APath on HEAD's side and on its side, MessageSubjects of
  each. Empty when git is applying none. }
function ConflictCommits(const ARoot, APath: string): string;

{** The lines that take a conflict's place in AText, the agent's answer:
  those between a line "<resolved>" and a line "</resolved>" (none is an
  answer too, both sides dropped), a code fence around them taken off,
  and in AWhy what is between "<why>" and "</why>", on one line. False
  when there is no such part, or a line of it is a conflict marker. }
function ParseResolution(const AText: string; out ALines: TStringArray;
  out AWhy: string): boolean;

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
    procedure LocateLines(const AList: string);
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

  {** Resolves the conflict ABlock of APath (see ConflictInput); its
    lines to write go into Block's OldLines, so the frame writes it as
    it writes the conflict's other picks. }
  TGittanConflictJob = class(TGittanAgentJob)
  private
    FPath, FOperation: string;
    FRebase: boolean;
    FBlock: TGittanDiscard;
    FOk: boolean;
    FWhy, FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: string; AAI: TGittanAI; const APath, AOperation: string;
      ARebase: boolean; const ABlock: TGittanDiscard);
    property Path: string read FPath;
    {** The conflict as it was given, with the agent's lines as OldLines
      when Ok. }
    property Block: TGittanDiscard read FBlock;
    {** Whether the agent answered with the lines. }
    property Ok: boolean read FOk;
    {** The agent's few words on what it kept. }
    property Why: string read FWhy;
    {** Why there are none, when not Ok. }
    property Error: string read FError;
  end;

  {** Asks the agent how to split APaths, the changed files, into
    commits (see SplitInput, ParseCommitPlan). }
  TGittanSplitJob = class(TGittanAgentJob)
  private
    FPaths: TStringList;
    FOk: boolean;
    FPlan: TGittanCommitPlan;
    FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: string; AAI: TGittanAI; APaths: TStrings);
    destructor Destroy; override;
    {** Whether the agent answered with a plan. }
    property Ok: boolean read FOk;
    property Plan: TGittanCommitPlan read FPlan;
    {** Why there is none, when not Ok. }
    property Error: string read FError;
  end;

  {** Has the agent fix AFinding, a review's finding of the repository
    compared with ABase (see FixInput); the file is read as it is, and
    the fix (ApplyFixEdits) is Block, for the frame to write as it
    writes a discard. }
  TGittanFixJob = class(TGittanAgentJob)
  private
    FBase: string;
    FFinding: TGittanReviewThread;
    FOk, FChanged: boolean;
    FBlock: TGittanDiscard;
    FWhy, FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: string; AAI: TGittanAI; const ABase: string;
      const AFinding: TGittanReviewThread);
    property Finding: TGittanReviewThread read FFinding;
    {** Whether the agent answered with a fix that fits the file, or
      that none is needed. }
    property Ok: boolean read FOk;
    {** Whether it changes the file: Block holds the change. }
    property Changed: boolean read FChanged;
    property Block: TGittanDiscard read FBlock;
    {** The agent's few words on the fix, or on why there is none. }
    property Why: string read FWhy;
    {** Why there is no fix, when not Ok. }
    property Error: string read FError;
  end;

  {** Has the agent explain lines AFrom to ATo of APath in ARef (see
    WhyInput); the answer is Markdown. }
  TGittanWhyJob = class(TGittanAgentJob)
  private
    FPath, FRef: string;
    FFrom, FTo: integer;
    FOk: boolean;
    FText, FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: string; AAI: TGittanAI; const APath, ARef: string;
      AFrom, ATo: integer);
    property Path: string read FPath;
    property FromLine: integer read FFrom;
    property ToLine: integer read FTo;
    property Ok: boolean read FOk;
    {** The explanation, when Ok. }
    property Text: string read FText;
    {** Why there is none, when not Ok. }
    property Error: string read FError;
  end;

resourcestring
  rsNothingToReview = 'There are no changes to review.';
  rsReviewNotRead = 'The answer was no list of findings: %s';
  rsFoundNotRead = 'The answer was no list of files: %s';
  rsResolutionNotRead = 'The answer held no resolved lines: %s';
  rsPlanNotRead = 'The answer was no list of commits: %s';
  rsFixNotRead = 'The answer held no edits: %s';
  rsFixNotFound = 'edit %d is not in the file as it is';
  rsFixAmbiguous = 'edit %d is in the file %d times';
  rsFixLink = '%s goes through a symbolic link, which a fix does not write through';
  rsNoLineHistory = 'git has no history of these lines.';
  rsNothingToDescribe = 'There are no changes to describe.';
  rsAgentNoAnswer = '%s gave no answer.';
  rsAboutApi = '%s at %s';

implementation

uses
  Math, fpjson, jsonparser, DateUtils, gittan.textfile;

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

  { The conflict's lines and how each side came to be: a model told only
    to resolve it takes one side whole, and answers with prose or a fence
    around the code unless the lines are asked for between tags. }
  ResolvePromptStart = 'Resolve the git conflict given below: the lines from ' +
    '"<<<<<<<" to ">>>>>>>" in the file named, the side after "<<<<<<<" (up to ' +
    '"|||||||" or "=======") against the side after "=======", with what both ' +
    'started from between "|||||||" and "=======" when it is there. Keep what each ' +
    'side meant to change: combine them where they change different things, and ' +
    'where they contradict, follow the commits given and keep the other side''s ' +
    'change where it still applies. Keep the file''s indentation and style, and ' +
    'change nothing outside the conflict. ';
  ResolveReadNote = 'You may read the repository''s files to see how the code in the ' +
    'conflict is used. ';
  ResolveSentNote = 'You see the lines given alone and cannot open the files. ';
  ResolvePromptEnd = 'Answer with the lines that take the whole conflict''s place, ' +
    'between a line <resolved> and a line </resolved>, with no conflict markers and ' +
    'no code fences in them, then one short sentence on what you kept between ' +
    '<why> and </why>, and nothing else.';

  { Commits a reviewer can follow, in an order that builds: a model asked
    to split changes otherwise makes a commit per file, or per folder. }
  SplitPromptStart = 'The changes given below are to be committed as a few commits, ' +
    'each one thing a reviewer can follow, such as a refactoring, a fix, a feature or ' +
    'a dependency bump, with the tests of that change in the same commit. Group the ' +
    'changed files into such commits, in the ' +
    'order they should be made, each building on those before; every file listed at ' +
    'the end goes in exactly one commit, a file that serves two things in the one it ' +
    'is most for. One commit for the whole is a fine answer when the change is one ' +
    'thing. Give each commit a message: a subject line of at most 72 characters and, ' +
    'only when it needs explaining, a blank line and a body of a few lines, the style ' +
    '(language, tense, prefixes) taken from the recent commit subjects given. ';
  SplitReadNote = 'Read the repository''s files only when the diff alone leaves a ' +
    'change unclear. ';
  SplitPromptEnd = 'Answer with a JSON array alone, no code fences, at most 8 commits, ' +
    'the first to be made first, each {"files": [the paths as listed], "message": the ' +
    'commit message}.';

  { Edits by the lines they replace, which a model copies reliably,
    rather than a patch, whose hunk headers and counts it gets wrong. }
  FixPromptStart = 'Fix the problem the review finding below points out, in the file ' +
    'it is on, which is given as it is now with its lines numbered, after the change ' +
    'under review. Change as little as needed, keep the file''s style, and change no ' +
    'other file. ';
  FixReadNote = 'You may read the repository''s files to check the finding and how ' +
    'the code is used. ';
  FixPromptEnd = 'Answer with the edits alone, each a line <find>, the lines of the ' +
    'file to replace exactly as they are (whole lines, without their numbers, enough ' +
    'of them to be found once in the file), a line </find>, a line <replace>, the ' +
    'lines to put in their place, a line </replace>; then one short sentence on what ' +
    'you changed between <why> and </why>. When the finding is wrong or needs no ' +
    'change, answer with the <why> alone, saying so.';

  { The history git gives, read as a story: a model asked why lines are
    so otherwise retells the diff, or guesses at reasons no commit gave. }
  WhyPromptStart = 'Explain why the lines given below are as they are, from the ' +
    'history of their changes that follows them (git log -L, newest first, each ' +
    'commit with its message and the diff of the lines). Say what they do, how and ' +
    'why they came to be this way, and what the changes that shaped them were for, ' +
    'naming each commit by its short hash; where the history does not say why, say ' +
    'so rather than guess. ';
  WhyReadNote = 'You may read the repository''s files to see how the lines are used. ';
  WhyPromptEnd = 'Answer with at most three short paragraphs of Markdown alone, the ' +
    'history first, no headings, no preamble.';

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
    atResolve:
      if AReadsFiles then
        Result := ResolvePromptStart + ResolveReadNote + ResolvePromptEnd
      else
        Result := ResolvePromptStart + ResolveSentNote + ResolvePromptEnd;
    atSplit:
      if AReadsFiles then
        Result := SplitPromptStart + SplitReadNote + SplitPromptEnd
      else
        Result := SplitPromptStart + SplitPromptEnd;
    atFix:
      if AReadsFiles then
        Result := FixPromptStart + FixReadNote + FixPromptEnd
      else
        Result := FixPromptStart + FixPromptEnd;
    atWhy:
      if AReadsFiles then
        Result := WhyPromptStart + WhyReadNote + WhyPromptEnd
      else
        Result := WhyPromptStart + WhyPromptEnd;
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

{ AText up to AKeep bytes, cut at a line end, with a line that says it
  was: ANote, with the bytes left out and the whole. }
function KeepText(const AText, ANote: string; AKeep: integer = MessageDiffKeep): string;
var
  Cut: integer;
begin
  if Length(AText) <= AKeep then
    Exit(AText);
  Cut := AKeep;
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

{ AText with its lines numbered from 1, "12: text", and in ACount how
  many lines that is. }
function NumberLines(const AText: string; out ACount: integer): string;
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
    ACount := Lines.Count;
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

{ Whether APath under ARoot goes through a symbolic link, the file or a
  folder on the way to it, which may lead out of the repository however
  APath reads. }
function ThroughLink(const ARoot, APath: string): boolean;
var
  Name, Rest: string;
  Cut, Attr: integer;
begin
  Name := ExcludeTrailingPathDelimiter(ARoot);
  Rest := APath;
  repeat
    Cut := Pos('/', Rest);
    if Cut = 0 then
      Cut := Length(Rest) + 1;
    Name := Name + PathDelim + Copy(Rest, 1, Cut - 1);
    Delete(Rest, 1, Cut);
    Attr := FileGetAttr(Name);
    {$WARN SYMBOL_PLATFORM OFF}
    if (Attr <> -1) and (Attr and faSymLink <> 0) then
      Exit(True);
    {$WARN SYMBOL_PLATFORM ON}
  until Rest = '';
  Result := False;
end;

function FindLinesInput(const ARoot, AQuestion, AList: string;
  const AFiles: TGittanFoundFiles; out ALast: TGittanLineCounts): string;
var
  Names: array of string;
  Count, Share, i: integer;
  Whole: int64;
  Text: string;
  Stream: TFileStream;
begin
  Result := '';
  SetLength(ALast, Length(AFiles));
  for i := 0 to High(ALast) do
    ALast[i] := 0;
  { The files that are there share the budget; one named but not in the
    list (an ignored file), out of the repository or missing takes none
    of it. }
  Count := 0;
  SetLength(Names, Length(AFiles));
  for i := 0 to High(AFiles) do
    if InsideRepo(AFiles[i].Path) and (Pos(#10 + AFiles[i].Path + #10,
      #10 + AList + #10) > 0) and not ThroughLink(ARoot, AFiles[i].Path) then
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
      Result := Result + NumberLines(Text, ALast[i]);
      if Whole > Share then
        Result := Result + Format('[The file is cut here: %d of its %d bytes are ' +
          'left out.]', [Whole - Length(Text), Whole]) + LineEnding;
    end;
    Result := Result + LineEnding;
  end;
  if Result <> '' then
    Result := 'The question: ' + AQuestion + LineEnding + LineEnding + Result;
end;

procedure MergeFoundLines(var AFiles: TGittanFoundFiles; const ALines: TGittanFoundFiles;
  const ALast: array of integer);
var
  i, j: integer;
begin
  for i := 0 to High(AFiles) do
  begin
    AFiles[i].Line := 0;
    if i > High(ALast) then
      Continue;
    for j := 0 to High(ALines) do
      if (ALines[j].Path = AFiles[i].Path) and (ALines[j].Line > 0) and
        (ALines[j].Line <= ALast[i]) then
      begin
        AFiles[i].Line := ALines[j].Line;
        if ALines[j].Why <> '' then
          AFiles[i].Why := ALines[j].Why;
        Break;
      end;
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

var
  { Numbers IndexDiff's temporary index, unique in the process: the
    message and the review job can make one at once. }
  IndexSerial: longint = 0;

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
    IntToStr(GetProcessID) + '-' + IntToStr(InterLockedIncrement(IndexSerial));
  List := Index + '.paths';
  Index := Index + '.index';
  { Left by a run of an earlier process with the same id that ended
    before it cleaned up; no live one has this name, and git would
    refuse the index while its lock is there. }
  DeleteFile(Index + '.lock');
  DeleteFile(Index);
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

function SplitInput(const ARoot: string; APaths: TStrings; out AText, AError: string): boolean;
var
  i: integer;
begin
  Result := CommitChanges(ARoot, APaths, False, AText, AError);
  if not Result or (AText = '') then
    Exit;
  { The summary cuts long paths; these are what the plan names. }
  AText := AText + LineEnding + 'The changed files:' + LineEnding;
  for i := 0 to APaths.Count - 1 do
    AText := AText + APaths[i] + LineEnding;
end;

{ The index of APath in APaths: as it is spelled, else in another case
  when that names one path alone; -1 for none, or for two paths that
  differ in case alone. }
function PlanPathIndex(APaths: TStrings; const APath: string): integer;
var
  i: integer;
begin
  for i := 0 to APaths.Count - 1 do
    if APaths[i] = APath then
      Exit(i);
  Result := -1;
  for i := 0 to APaths.Count - 1 do
    if SameText(APaths[i], APath) then
    begin
      if Result >= 0 then
        Exit(-1);
      Result := i;
    end;
end;

function ParseCommitPlan(const AText: string; APaths: TStrings;
  out APlan: TGittanCommitPlan): boolean;
var
  Data, Files: TJSONData;
  Item: TJSONObject;
  Taken: TStringList;
  Commit: TGittanPlannedCommit;
  First, Last, i, j, k, n: integer;
  Path: string;
begin
  APlan := nil;
  First := Pos('[', AText);
  Last := LastDelimiter(']', AText);
  if (First = 0) or (Last < First) then
    Exit(False);
  try
    Data := GetJSON(Copy(AText, First, Last - First + 1));
  except
    Exit(False);
  end;
  Taken := TStringList.Create;
  try
    Result := Data is TJSONArray;
    if not Result then
      Exit;
    Taken.Sorted := True;
    Taken.CaseSensitive := True;
    n := 0;
    for i := 0 to Data.Count - 1 do
    begin
      if n >= SplitMaxCommits then
        Break;
      if not (Data.Items[i] is TJSONObject) then
        Continue;
      Item := TJSONObject(Data.Items[i]);
      Files := Item.Find('files');
      if not (Files is TJSONArray) then
        Continue;
      Commit := Default(TGittanPlannedCommit);
      for j := 0 to Files.Count - 1 do
      begin
        if not (Files.Items[j] is TJSONString) then
          Continue;
        Path := StringReplace(Trim(Files.Items[j].AsString), '\', '/', [rfReplaceAll]);
        if (Copy(Path, 1, 2) = './') or (((Copy(Path, 1, 2) = 'a/') or
          (Copy(Path, 1, 2) = 'b/')) and (PlanPathIndex(APaths, Path) < 0)) then
          Delete(Path, 1, 2);
        { The list's own spelling: PlanPathIndex finds a path in another
          case when no other path has it, Taken only in the one it holds. }
        k := PlanPathIndex(APaths, Path);
        if k < 0 then
          Continue;
        Path := APaths[k];
        if Taken.IndexOf(Path) >= 0 then
          Continue;
        Taken.Add(Path);
        Insert(Path, Commit.Files, Length(Commit.Files));
      end;
      if Commit.Files = nil then
        Continue;
      Commit.Message := CleanCommitMessage(Item.Get('message', ''));
      Insert(Commit, APlan, n);
      Inc(n);
    end;
    { What the agent left out, or what came after the most it may plan,
      is one more commit for the user to describe. }
    Commit := Default(TGittanPlannedCommit);
    for i := 0 to APaths.Count - 1 do
      if Taken.IndexOf(APaths[i]) < 0 then
        Insert(APaths[i], Commit.Files, Length(Commit.Files));
    if Commit.Files <> nil then
      Insert(Commit, APlan, Length(APlan));
  finally
    Taken.Free;
    Data.Free;
  end;
end;

function WhyInput(const ARoot, APath, ARef: string; AFrom, ATo: integer;
  out AText, AError: string): boolean;
var
  Blob, Log: string;
  Lines: TStringList;
  i: integer;
begin
  AText := '';
  Result := RunGitIn(ARoot, ['show', ARef + ':' + APath], Blob, AError) and
    RunGitIn(ARoot, ['log', '--no-color', '-n', IntToStr(WhyCommits), '-L',
    IntToStr(AFrom) + ',' + IntToStr(ATo) + ':' + APath,
    '--format=commit %h%nAuthor: %an%nDate: %as%n%n%B', ARef], Log, AError);
  if not Result then
    Exit;
  if Trim(Log) = '' then
  begin
    AError := rsNoLineHistory;
    Exit(False);
  end;
  Lines := TStringList.Create;
  try
    SplitLf(Blob, Lines);
    AText := 'The lines ' + IntToStr(AFrom) + ' to ' + IntToStr(ATo) + ' of ' + APath +
      ':' + LineEnding;
    for i := AFrom - 1 to Min(ATo, Lines.Count) - 1 do
      AText := AText + BareLine(Lines[i]) + LineEnding;
  finally
    Lines.Free;
  end;
  AText := AText + LineEnding + 'Their history (git log -L):' + LineEnding +
    KeepText(Log, '[The history is cut here: %d of its %d bytes are left out.]');
end;

function ConflictCommits(const ARoot, APath: string): string;
const
  Heads: array[0..3] of string = ('MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD',
    'REBASE_HEAD');
var
  Head, Base, Output, Error: string;
  i: integer;
begin
  Result := '';
  Head := '';
  for i := 0 to High(Heads) do
    if RunGitIn(ARoot, ['rev-parse', '--verify', '-q', Heads[i] + '^{commit}'], Output,
      Error) then
    begin
      Head := Heads[i];
      Break;
    end;
  if Head = '' then
    Exit;
  { A merge's head is only the tip of the branch merged; the commit a
    cherry-pick, revert or rebase applies is the change itself. }
  if (Head <> 'MERGE_HEAD') and RunGitIn(ARoot, ['log', '-1', '--format=%B', Head], Output,
    Error) and (Trim(Output) <> '') then
    Result := 'The commit being applied (' + Head + '):' + LineEnding + Trim(Output) +
      LineEnding + LineEnding;
  if not RunGitIn(ARoot, ['merge-base', 'HEAD', Head], Base, Error) then
    Exit;
  Base := Trim(Base);
  if RunGitIn(ARoot, ['log', '-n', IntToStr(MessageSubjects), '--format=%h %s',
    Base + '..HEAD', '--', APath], Output, Error) and (Trim(Output) <> '') then
    Result := Result + 'Commits on the "<<<<<<<" side (HEAD) that changed the file, ' +
      'newest first:' + LineEnding + Output + LineEnding;
  if RunGitIn(ARoot, ['log', '-n', IntToStr(MessageSubjects), '--format=%h %s',
    Base + '..' + Head, '--', APath], Output, Error) and (Trim(Output) <> '') then
    Result := Result + 'Commits on the ">>>>>>>" side (' + Head + ') that changed the ' +
      'file, newest first:' + LineEnding + Output + LineEnding;
end;

function ConflictInput(const ARoot, APath, AOperation: string; ARebase: boolean;
  const ABlock: TGittanDiscard): string;
var
  Lines: TStringList;
  Text: TStringBuilder;
  i, First, Last: integer;
begin
  Text := TStringBuilder.Create;
  Lines := TStringList.Create;
  try
    Text.Append('The file: ' + APath + LineEnding);
    if AOperation <> '' then
      Text.Append('Git is ' + AOperation + '. ');
    if ARebase then
      Text.Append('The "<<<<<<<" side is the upstream the user''s commits are replayed ' +
        'onto; the ">>>>>>>" side is the user''s own commit being replayed.')
    else
      Text.Append('The "<<<<<<<" side is the user''s own work; the ">>>>>>>" side is ' +
        'what comes in.');
    Text.Append(LineEnding + LineEnding);
    Text.Append(ConflictCommits(ARoot, APath));
    try
      Lines.LoadFromFile(ABlock.FileName);
    except
      Lines.Clear;
    end;
    { The lines around it, as the file has them now. }
    First := Max(0, ABlock.Line - 1 - ConflictAround);
    if First < ABlock.Line - 1 then
    begin
      Text.Append('The lines before the conflict:' + LineEnding);
      for i := First to Min(ABlock.Line - 2, Lines.Count - 1) do
        Text.Append(Lines[i] + LineEnding);
      Text.Append(LineEnding);
    end;
    Text.Append('The conflict:' + LineEnding);
    for i := 0 to High(ABlock.NewLines) do
      Text.Append(ABlock.NewLines[i] + LineEnding);
    First := ABlock.Line - 1 + Length(ABlock.NewLines);
    Last := Min(First + ConflictAround, Lines.Count) - 1;
    if First <= Last then
    begin
      Text.Append(LineEnding + 'The lines after the conflict:' + LineEnding);
      for i := First to Last do
        Text.Append(Lines[i] + LineEnding);
    end;
    Result := Text.ToString;
  finally
    Lines.Free;
    Text.Free;
  end;
end;

{ The text between the first AOpen and the last AClose in AText (case
  ignored), '' with False when there is none. }
function Between(const AText, AOpen, AClose: string; out APart: string): boolean;
var
  Low: string;
  First, Last: integer;
begin
  APart := '';
  Low := LowerCase(AText);
  First := Pos(AOpen, Low);
  if First = 0 then
    Exit(False);
  First := First + Length(AOpen);
  Last := Length(Low) - Length(AClose) + 1;
  while (Last >= First) and (Copy(Low, Last, Length(AClose)) <> AClose) do
    Dec(Last);
  Result := Last >= First;
  if Result then
    APart := Copy(AText, First, Last - First);
end;

{ The lines of APart, the text between two tags on lines of their own:
  the line ends next to the tags are theirs, a blank line at the end is
  one of the lines, and a code fence around them is taken off. }
function TagLines(const APart: string): TStringArray;
var
  Part: string;
begin
  Result := nil;
  Part := StringReplace(APart, #13#10, #10, [rfReplaceAll]);
  if Copy(Part, 1, 1) = #10 then
    Delete(Part, 1, 1);
  if Copy(Part, Length(Part), 1) = #10 then
    SetLength(Part, Length(Part) - 1);
  if Part <> '' then
    Result := Part.Split([#10]);
  if (Length(Result) >= 2) and (Copy(Trim(Result[0]), 1, 3) = '```') and
    (Trim(Result[High(Result)]) = '```') then
    Result := Copy(Result, 1, Length(Result) - 2);
end;

{ What is between "<why>" and "</why>" in AText, on one line. }
function WhyOf(const AText: string): string;
var
  Part: string;
begin
  Result := '';
  if Between(AText, '<why>', '</why>', Part) then
    Result := Trim(StringReplace(StringReplace(Part, #13, '', [rfReplaceAll]), #10, ' ',
      [rfReplaceAll]));
end;

function ParseResolution(const AText: string; out ALines: TStringArray;
  out AWhy: string): boolean;
var
  Part: string;
  i: integer;
begin
  ALines := nil;
  AWhy := WhyOf(AText);
  if not Between(AText, '<resolved>', '</resolved>', Part) then
    Exit(False);
  ALines := TagLines(Part);
  for i := 0 to High(ALines) do
    if (Copy(ALines[i], 1, 7) = '<<<<<<<') or (Copy(ALines[i], 1, 7) = '>>>>>>>') or
      (ALines[i] = '=======') or (ALines[i] = '|||||||') or
      (Copy(ALines[i], 1, 8) = '||||||| ') then
    begin
      ALines := nil;
      Exit(False);
    end;
  Result := True;
end;

function FixInput(const ARoot, ABase: string; const AFinding: TGittanReviewThread;
  const ALines: TStringArray): string;
var
  Text: TStringBuilder;
  Diff, Error, Side: string;
  Numbered: TStringArray;
  i, Size, Room, First, Last: integer;
  Grew: boolean;
begin
  Text := TStringBuilder.Create;
  try
    if AFinding.LeftSide then
      Side := 'line %d of the old side (a line the change removed)'
    else
      Side := 'line %d';
    Text.Append('The finding, on ' + Format(Side, [AFinding.Line]) + ' of ' +
      AFinding.Path);
    if AFinding.Severity <> '' then
      Text.Append(', a ' + AFinding.Severity);
    Text.Append(':' + LineEnding);
    if AFinding.Comments <> nil then
      Text.Append(AFinding.Comments[0].Body + LineEnding);
    Text.Append(LineEnding);
    if ABase <> '' then
      RunGitIn(ARoot, ['diff', '--no-ext-diff', ABase, '--', AFinding.Path], Diff, Error)
    else if not RunGitIn(ARoot, ['diff', '--no-ext-diff', 'HEAD', '--', AFinding.Path],
      Diff, Error) then
      Diff := '';
    { The diff takes half the budget at most, so the file's lines at the
      finding always come: a model that cannot read files has only them
      to find the lines to change. }
    if Trim(Diff) <> '' then
      Text.Append('The change under review in the file:' + LineEnding +
        KeepText(Diff, '[The diff is cut here: %d of its %d bytes are left out.]',
        MessageDiffKeep div 2) + LineEnding);
    Text.Append('The file as it is now:' + LineEnding);
    SetLength(Numbered, Length(ALines));
    Size := 0;
    for i := 0 to High(ALines) do
    begin
      Numbered[i] := IntToStr(i + 1) + ': ' + ALines[i] + #10;
      Inc(Size, Length(Numbered[i]));
    end;
    { Room for the notes of the lines left out. }
    Room := MessageDiffKeep - Text.Length - 200;
    First := 0;
    Last := High(ALines);
    if Size > Room then
    begin
      First := Max(0, Min(AFinding.Line - 1, High(ALines)));
      Last := First - 1;
      Size := 0;
      { Down and up from the finding's line in turn while lines fit,
        each way on its own: a line too long below does not stop the
        lines above. }
      repeat
        Grew := False;
        if (Last < High(ALines)) and (Size + Length(Numbered[Last + 1]) <= Room) then
        begin
          Inc(Last);
          Inc(Size, Length(Numbered[Last]));
          Grew := True;
        end;
        if (First > 0) and (Size + Length(Numbered[First - 1]) <= Room) then
        begin
          Dec(First);
          Inc(Size, Length(Numbered[First]));
          Grew := True;
        end;
      until not Grew;
    end;
    if First > 0 then
      Text.Append(Format('[Lines 1 to %d are left out.]', [First]) + LineEnding);
    for i := First to Last do
      Text.Append(Numbered[i]);
    if Last < High(ALines) then
      Text.Append(Format('[Lines %d to %d are left out.]', [Last + 2, Length(ALines)]) +
        LineEnding);
    Result := KeepText(Text.ToString, '[The file is cut here: %d of the %d bytes are ' +
      'left out.]');
  finally
    Text.Free;
  end;
end;

function ParseFixEdits(const AText: string; out AEdits: TGittanFixEdits;
  out AWhy: string): boolean;
var
  Low, Part: string;
  At, Open, Close, n: integer;
  Edit: TGittanFixEdit;

  { The part between AOpen and AClose from At on, At moved past it. }
  function Next(const AOpen, AClose: string; out APart: string): boolean;
  begin
    Result := False;
    APart := '';
    Open := Pos(AOpen, Low, At);
    if Open = 0 then
      Exit;
    Close := Pos(AClose, Low, Open + Length(AOpen));
    if Close = 0 then
      Exit;
    APart := Copy(AText, Open + Length(AOpen), Close - Open - Length(AOpen));
    At := Close + Length(AClose);
    Result := True;
  end;

begin
  AEdits := nil;
  AWhy := WhyOf(AText);
  Low := LowerCase(AText);
  At := 1;
  n := 0;
  while Next('<find>', '</find>', Part) do
  begin
    Edit := Default(TGittanFixEdit);
    Edit.Find := TagLines(Part);
    if (Edit.Find = nil) or not Next('<replace>', '</replace>', Part) then
    begin
      AEdits := nil;
      Exit(False);
    end;
    Edit.Replace := TagLines(Part);
    Insert(Edit, AEdits, n);
    Inc(n);
  end;
  Result := (AEdits <> nil) or (AWhy <> '');
end;

{ Where AFind is in ALines, compared as AMode says: 0 as they are, 1
  with the spaces at the ends ignored, 2 without a line number before
  each of AFind's; -1 for nowhere, and ACount how many places. }
function FindLines(const ALines, AFind: TStringArray; AMode: integer;
  out ACount: integer): integer;
var
  i, j, k: integer;
  Want: TStringArray;
  Same: boolean;
begin
  Result := -1;
  ACount := 0;
  Want := Copy(AFind);
  if AMode = 2 then
    for j := 0 to High(Want) do
    begin
      k := 1;
      while (k <= Length(Want[j])) and (Want[j][k] in ['0'..'9']) do
        Inc(k);
      if (k = 1) or (Copy(Want[j], k, 2) <> ': ') then
        Exit;
      Want[j] := Copy(Want[j], k + 2, MaxInt);
    end;
  for i := 0 to Length(ALines) - Length(Want) do
  begin
    Same := True;
    for j := 0 to High(Want) do
    begin
      if AMode = 0 then
        Same := ALines[i + j] = Want[j]
      else
        Same := TrimRight(ALines[i + j]) = TrimRight(Want[j]);
      if not Same then
        Break;
    end;
    if Same then
    begin
      if Result < 0 then
        Result := i;
      Inc(ACount);
    end;
  end;
end;

function ApplyFixEdits(const ALines: TStringArray; const AEdits: TGittanFixEdits;
  out ANew: TStringArray; out AError: string): boolean;
var
  e, Mode, At, Count: integer;
begin
  AError := '';
  ANew := Copy(ALines);
  for e := 0 to High(AEdits) do
  begin
    At := -1;
    Count := 0;
    for Mode := 0 to 2 do
    begin
      At := FindLines(ANew, AEdits[e].Find, Mode, Count);
      if Count > 0 then
        Break;
    end;
    if Count = 0 then
      AError := Format(rsFixNotFound, [e + 1])
    else if Count > 1 then
      AError := Format(rsFixAmbiguous, [e + 1, Count]);
    if AError <> '' then
    begin
      ANew := nil;
      Exit(False);
    end;
    ANew := Concat(Copy(ANew, 0, At), AEdits[e].Replace,
      Copy(ANew, At + Length(AEdits[e].Find), MaxInt));
  end;
  Result := True;
end;

function FixBlock(const AFileName: string; const ABefore, AAfter: TStringArray): TGittanDiscard;
var
  Head, Tail: integer;
begin
  Head := 0;
  while (Head < Length(ABefore)) and (Head < Length(AAfter)) and
    (ABefore[Head] = AAfter[Head]) do
    Inc(Head);
  Tail := 0;
  while (Tail < Length(ABefore) - Head) and (Tail < Length(AAfter) - Head) and
    (ABefore[High(ABefore) - Tail] = AAfter[High(AAfter) - Tail]) do
    Inc(Tail);
  { An insert keeps a line beside it in the block, so that DiscardBlock
    has a line to find where it was and refuses a file changed there. }
  if (Head + Tail = Length(ABefore)) and (Head + Tail < Length(AAfter)) then
    if Head > 0 then
      Dec(Head)
    else if Tail > 0 then
      Dec(Tail);
  Result := Default(TGittanDiscard);
  Result.FileName := AFileName;
  Result.Line := Head + 1;
  Result.NewLines := Copy(ABefore, Head, Length(ABefore) - Head - Tail);
  Result.OldLines := Copy(AAfter, Head, Length(AAfter) - Head - Tail);
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
      LocateLines(List);
  end;
  if Terminated then
    Exit;
  Done;
end;

{ The second round for a model that cannot read files: the files it
  named from AList with their text, for their lines. The first answer's
  lines were guessed from the paths and are dropped; an answer that is
  none leaves the files without lines, since they are still worth
  showing. }
procedure TGittanFindJob.LocateLines(const AList: string);
var
  Input, Answer, Why: string;
  Lines: TGittanFoundFiles;
  Last: TGittanLineCounts;
  i: integer;
begin
  for i := 0 to High(FFiles) do
    FFiles[i].Line := 0;
  Input := FindLinesInput(FRoot, FQuestion, AList, FFiles, Last);
  if (Input = '') or Terminated then
    Exit;
  if Ask(atLocate, Input, Answer, Why) and ParseFoundFiles(Answer, Lines) then
    MergeFoundLines(FFiles, Lines, Last);
end;

{ TGittanConflictJob }

constructor TGittanConflictJob.Create(const ARoot: string; AAI: TGittanAI;
  const APath, AOperation: string; ARebase: boolean; const ABlock: TGittanDiscard);
begin
  inherited Create(ARoot, AAI);
  FPath := APath;
  FOperation := AOperation;
  FRebase := ARebase;
  FBlock := ABlock;
end;

procedure TGittanConflictJob.Execute;
var
  Input, Answer: string;
  Lines: TStringArray;
begin
  Input := ConflictInput(FRoot, FPath, FOperation, FRebase, FBlock);
  if Terminated then
    Exit;
  FOk := Ask(atResolve, Input, Answer, FError);
  if Terminated then
    Exit;
  if FOk then
  begin
    FOk := ParseResolution(Answer, Lines, FWhy);
    if FOk then
      FBlock.OldLines := Lines
    else
      FError := Format(rsResolutionNotRead, [Copy(Trim(Answer), 1, 300)]);
  end;
  Done;
end;

{ TGittanSplitJob }

constructor TGittanSplitJob.Create(const ARoot: string; AAI: TGittanAI; APaths: TStrings);
begin
  inherited Create(ARoot, AAI);
  FPaths := TStringList.Create;
  FPaths.AddStrings(APaths);
end;

destructor TGittanSplitJob.Destroy;
begin
  inherited Destroy;
  FPaths.Free;
end;

procedure TGittanSplitJob.Execute;
var
  Changes, Answer: string;
begin
  if not SplitInput(FRoot, FPaths, Changes, FError) then
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
  FOk := Ask(atSplit, Changes, Answer, FError);
  if Terminated then
    Exit;
  if FOk then
  begin
    FOk := ParseCommitPlan(Answer, FPaths, FPlan);
    if not FOk then
      FError := Format(rsPlanNotRead, [Copy(Trim(Answer), 1, 300)]);
  end;
  Done;
end;

{ TGittanFixJob }

constructor TGittanFixJob.Create(const ARoot: string; AAI: TGittanAI; const ABase: string;
  const AFinding: TGittanReviewThread);
begin
  inherited Create(ARoot, AAI);
  FBase := ABase;
  FFinding := AFinding;
end;

procedure TGittanFixJob.Execute;
var
  FileName, Answer: string;
  Lines: TStringList;
  Before, After: TStringArray;
  Edits: TGittanFixEdits;
  i: integer;
begin
  FileName := IncludeTrailingPathDelimiter(FRoot) + StringReplace(FFinding.Path, '/',
    PathDelim, [rfReplaceAll]);
  { The write would follow the link, maybe out of the repository. }
  if ThroughLink(FRoot, FFinding.Path) then
  begin
    FError := Format(rsFixLink, [FFinding.Path]);
    Done;
    Exit;
  end;
  Lines := TStringList.Create;
  try
    try
      SplitLf(ReadFileBytes(FileName), Lines);
    except
      on E: Exception do
      begin
        FError := E.Message;
        Done;
        Exit;
      end;
    end;
    SetLength(Before, Lines.Count);
    for i := 0 to Lines.Count - 1 do
      Before[i] := BareLine(Lines[i]);
  finally
    Lines.Free;
  end;
  if Terminated then
    Exit;
  FOk := Ask(atFix, FixInput(FRoot, FBase, FFinding, Before), Answer, FError);
  if Terminated then
    Exit;
  if FOk then
  begin
    FOk := ParseFixEdits(Answer, Edits, FWhy);
    if not FOk then
      FError := Format(rsFixNotRead, [Copy(Trim(Answer), 1, 300)])
    else if Edits <> nil then
    begin
      FOk := ApplyFixEdits(Before, Edits, After, FError);
      if FOk then
      begin
        FBlock := FixBlock(FileName, Before, After);
        FChanged := (FBlock.NewLines <> nil) or (FBlock.OldLines <> nil);
      end;
    end;
  end;
  Done;
end;

{ TGittanWhyJob }

constructor TGittanWhyJob.Create(const ARoot: string; AAI: TGittanAI;
  const APath, ARef: string; AFrom, ATo: integer);
begin
  inherited Create(ARoot, AAI);
  FPath := APath;
  FRef := ARef;
  FFrom := AFrom;
  FTo := ATo;
end;

procedure TGittanWhyJob.Execute;
var
  Input, Answer: string;
begin
  if not WhyInput(FRoot, FPath, FRef, FFrom, FTo, Input, FError) then
  begin
    Done;
    Exit;
  end;
  if Terminated then
    Exit;
  FOk := Ask(atWhy, Input, Answer, FError);
  if Terminated then
    Exit;
  if FOk then
  begin
    FText := Trim(StringReplace(Answer, #13#10, #10, [rfReplaceAll]));
    FOk := FText <> '';
    if not FOk then
      FError := Format(rsAgentNoAnswer, [AgentName]);
  end;
  Done;
end;

end.
