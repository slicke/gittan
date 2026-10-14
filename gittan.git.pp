unit gittan.git;

{** Git access for Gittan.

  Runs the git command line tool against a repository and returns its output.
  Nothing is parsed here beyond trimming; the caller decides how to show it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  {** Bits added to the kind in the Objects of ChangedPaths: the index
    holds a change, the work tree differs from the index. }
  flagStaged = 16;
  flagUnstaged = 32;

type
  {** What happened to a changed file, condensed from the two status columns
    of `git status --porcelain`. }
  TGittanChangeKind = (ckModified, ckAdded, ckDeleted, ckRenamed, ckUntracked,
    ckConflict);

  {** One changed file with its line counts. A binary file has no counts.
    Staged is set when the index holds a change to the file, Unstaged when
    the work tree differs from the index; an untracked file has neither.
    Both are false while a Base other than HEAD is compared against. }
  TGittanFileStat = record
    Path: string;
    Kind: TGittanChangeKind;
    Added, Deleted: integer;
    Binary: boolean;
    Staged, Unstaged: boolean;
  end;
  TGittanFileStats = array of TGittanFileStat;

  {** One opened repository. Open finds the work tree root for a folder, and
    the other calls run inside that root. }
  TGittanRepo = class
  private
    FRoot: string;
    FError: string;
    FBase: string;
    FWholeTree: boolean;
    FTempIndex: string;
    FIgnoreWhitespace: boolean;
    function RunGit(const ADir: string; const AArgs: array of string;
      out AOutput: string; const AIndexFile: string = ''): boolean;
    function IndexPath: string;
    function CopyIndex(const ATarget: string): boolean;
    function WholeTreeActive: boolean;
    function CompareIndex: string;
    procedure DropTempIndex;
    procedure SetWholeTree(AValue: boolean);
    function DiffBase: string;
    function EmptyTree: string;
    procedure SplitRange(out ALeft, ARight: string);
    function RunDiff(const AArgs: array of string; out AOutput: string): boolean;
    function FullPath(const APath: string): string;
  public
    {** Opens the repository that contains ADir. Returns false, with the git
      message in Error, when ADir is not inside a work tree. }
    destructor Destroy; override;
    function Open(const ADir: string): boolean;
    {** Forgets the repository. }
    procedure Close;
    {** Unified diff of the work tree against Base (HEAD by default), or
      against the empty tree in a repository without commits, where every
      staged file is new. Empty when there are no changes. }
    function Diff: string;
    {** The branches and tags of the repository, local branches first,
      each most recently committed first: what Base can be set to. }
    function Refs(AList: TStrings): boolean;
    {** Whether ARef names a commit in the repository. }
    function HasCommit(const ARef: string): boolean;
    {** The remote whose URL holds ARepoPath ("owner/repo", compared
      without regard to case), else origin, else the first remote, else
      empty. }
    function RemoteFor(const ARepoPath: string): string;
    {** Fetches pull request ANumber of ARemote (a GitHub remote, which
      serves it as refs/pull/N/head) into refs/gittan/pr/N, the name given
      in AHeadRef, and ABaseRef along with it, so the remote-tracking
      branch of the base is current too. Nothing in the work tree or the
      branches changes. }
    function FetchPullRequest(const ARemote: string; ANumber: integer;
      const ABaseRef: string; out AHeadRef: string): boolean;
    {** Records the work tree as it is now, untracked files included, in
      a commit of its own (parent HEAD when there is one, no branch points
      at it), and returns its id: a Base to compare against later, with
      WholeTree set, to see what changed since. The repository's own
      index is left alone: the tree is built through a temporary copy.
      The commit is reachable from nothing, so git prunes it with the
      other loose objects two weeks or more after it was made. }
    function TakeSnapshot(out AId: string): boolean;
    {** Changed files as "XY path" entries in the shape of `git status
      --porcelain`, untracked files included, one per file: a rename is
      listed under its new path alone. Paths are plain UTF-8 with "/"
      separators, never quoted. Returns false when git failed. }
    function ChangedFiles(AList: TStrings): boolean;
    {** Paths of the changed files from ChangedFiles, relative to Root.
      Each Objects entry holds the file's TGittanChangeKind as
      TObject(PtrUInt(Ord(Kind))), with flagStaged and flagUnstaged added
      from the two status columns. Returns false when git failed. }
    function ChangedPaths(AList: TStrings): boolean;
    {** The changed files of ChangedPaths with their added and deleted line
      counts from `git diff --numstat`. A file git does not know yet has
      every line counted as added. Returns false when git failed. }
    function ChangeStats(out AStats: TGittanFileStats): boolean;
    {** The current branch, the short commit id when HEAD is detached, or
      empty when nothing is open. }
    function Branch: string;
    {** The remote-tracking branch the repository was cloned from, such as
      origin/main: what the remote's HEAD points at, else main or master
      on the remote RemoteFor gives, else empty. }
    function DefaultBranch: string;
    {** The merge base of ARef and HEAD, the commit the branch left ARef
      at; false when either is unknown or they share no history. }
    function MergeBase(const ARef: string; out AHash: string): boolean;
    {** How many commits the branch is ahead of and behind its upstream;
      false when it has none. }
    function AheadBehind(out AAhead, ABehind: integer): boolean;
    {** Whether Base is a range "A..B" or "A...B": the right side of
      every diff is then the commit B instead of the work tree. }
    function IsRange: boolean;
    {** Every file of the work tree git knows or would add: the tracked
      files and the untracked ones that are not ignored, as paths
      relative to Root with "/" separators. Returns false when git
      failed. }
    function Files(AList: TStrings): boolean;
    {** The change kind of a "XY" status from `git status --porcelain`. }
    class function ChangeKind(const AStatus: string): TGittanChangeKind;
    {** flagStaged and flagUnstaged for a "XY" status: X is the index
      column, Y the work tree column; an untracked or ignored file has
      neither flag. }
    class function StageFlags(const AStatus: string): integer;
    {** One changed file as the lines of a unified diff against HEAD with the
      whole file as context: every line starts with ' ', '+' or '-'. A file
      git does not know yet is returned as all added lines; a binary file
      gives no lines. Returns false when git failed. }
    function FileChanges(const APath: string; ALines: TStrings): boolean;
    {** The two commits a diff of a file is between: ALeft is Base (HEAD
      by default), ARight the right commit of a range, or empty for the
      work tree. }
    procedure DiffSides(out ALeft, ARight: string);
    {** The output of `git blame --porcelain` for APath as it is in the
      commit ARef, or in the work tree when ARef is empty, with
      IgnoreWhitespace passed on as -w. Returns false when git failed: a
      file it does not know, or one ARef lacks. }
    function Blame(const APath, ARef: string; out AOutput: string): boolean;
    {** The output of `git log` for the commits that changed the lines
      AFrom..ATo of APath, as they are in the commit ARef (HEAD when
      empty), newest first and at most AMax of them, each with its diff
      of those lines (`git log -L`). With AFrom 0 the whole file is
      followed instead (`git log -p`). Every commit starts with a line
      of #1, the hash, the author, the author time and the summary
      separated by #31 (see TGittanHistory.Parse). IgnoreWhitespace is
      passed on as -w. Returns false when git failed: a file it does not
      know, or a range past the end of the file in ARef. }
    function LineHistory(const APath, ARef: string; AFrom, ATo, AMax: integer;
      out AOutput: string): boolean;
    {** A Base that shows what the commit AHash changed: the range from
      its parent, or from the empty tree for a commit without one. }
    function CommitRange(const AHash: string): string;
    {** A text that changes whenever the branch, the set of changed files
      or the content of a changed file changes: the branch, the commit ids
      of HEAD and Base, the status of every changed file, and the size,
      modification time and content hash of every changed file on disk.
      Empty when nothing is open or git failed. Meant for polling: two
      equal fingerprints mean there is nothing new to show. }
    function Fingerprint: string;
    {** Work tree root, empty when nothing is open. }
    property Root: string read FRoot;
    {** Message from the last git call that failed. }
    property Error: string read FError;
    {** The commit the work tree is compared against: a branch, tag or
      commit id, or empty for HEAD. A range "A..B" compares the commits A
      and B instead, "A...B" the commit B against its merge base with A
      (the changes of a branch since it left A), as git diff reads them;
      an end left out is HEAD. }
    property Base: string read FBase write FBase;
    {** Compare every file of the work tree against Base, the untracked
      ones too: a diff only lists the files of the index, so one is run
      through a temporary index with every file added. An untracked file
      Base holds unchanged is then not a change, one it lacks is added,
      not untracked; the stage flags are off as against any base. Made
      for a snapshot from TakeSnapshot, which holds the untracked files;
      no effect against HEAD or in a range. }
    property WholeTree: boolean read FWholeTree write SetWholeTree;
    {** Leave out changes in whitespace: every diff is run with -w, so a
      line that only changed its spacing counts as unchanged, and a file
      with no other change has no changes. }
    property IgnoreWhitespace: boolean read FIgnoreWhitespace write FIgnoreWhitespace;
  end;

{** Full path of GitHub's command line tool gh, or empty when it is not
  installed. Looked for on PATH and then where Homebrew and the Linux
  packages put it, since an app started from the macOS Finder gets a PATH
  without /opt/homebrew/bin and /usr/local/bin. }
function FindGitHubCli: string;

{** Runs gh (AExe, from FindGitHubCli) in ADir and answers whether it
  succeeded, with its standard output in AOutput and, on failure, its
  message in AError. gh runs with its prompts and its update notice off,
  since nobody could answer the one and the other would land in stderr. }
function RunGitHubCli(const AExe, ADir: string; const AArgs: array of string;
  out AOutput, AError: string): boolean;

implementation

uses
  Process, md5;

{ Gives P the environment of Gittan without the variables whose names
  (with the equals sign) are in ASkip, so the caller can set those. }
procedure CopyEnvironment(P: TProcess; const ASkip: array of string);
var
  Env, Prefix: string;
  i: integer;
  Keep: boolean;
begin
  for i := 1 to GetEnvironmentVariableCount do
  begin
    Env := GetEnvironmentString(i);
    Keep := True;
    for Prefix in ASkip do
      if Pos(Prefix, Env) = 1 then
        Keep := False;
    if Keep then
      P.Environment.Add(Env);
  end;
end;

{ ---------------------------------------------------------------------------
  Running git
  ---------------------------------------------------------------------------
  git is found on PATH. stderr is read apart from stdout: git warns there
  about things that are not failures (with core.autocrlf on, every diff
  of a file with LF line endings says they will be replaced), and a
  warning must not be taken for output. On failure the error message is
  kept in FError: what came on stderr, or on stdout when stderr had
  nothing. git gets
  the environment of Gittan with LC_ALL set to C, so its messages come in
  English whatever the user's locale and the few that are matched on can
  be relied upon, and with prompts turned off, since nobody could answer
  one. Path names come back as plain UTF-8 instead of octal escapes. }
function TGittanRepo.RunGit(const ADir: string; const AArgs: array of string;
  out AOutput: string; const AIndexFile: string): boolean;
var
  P: TProcess;
  Err: string;
  Status, i: integer;
begin
  AOutput := '';
  P := TProcess.Create(nil);
  try
    P.Executable := 'git';
    P.CurrentDirectory := ADir;
    P.Parameters.Add('-c');
    P.Parameters.Add('core.quotepath=false');
    for i := 0 to High(AArgs) do
      P.Parameters.Add(AArgs[i]);
    CopyEnvironment(P, ['LC_ALL=', 'GIT_TERMINAL_PROMPT=', 'GIT_INDEX_FILE=']);
    P.Environment.Add('LC_ALL=C');
    P.Environment.Add('GIT_TERMINAL_PROMPT=0');
    if AIndexFile <> '' then
      P.Environment.Add('GIT_INDEX_FILE=' + AIndexFile);
    P.Options := [poNoConsole];
    if P.RunCommandLoop(AOutput, Err, Status) <> 0 then
    begin
      FError := 'Could not run git. Is it installed?';
      Exit(False);
    end;
  finally
    P.Free;
  end;
  Result := Status = 0;
  if not Result then
  begin
    FError := Trim(Err);
    if FError = '' then
      FError := Trim(AOutput);
    AOutput := '';
  end;
end;

function FindGitHubCli: string;
const
  {$ifdef windows}
  Name = 'gh.exe';
  Extra = '';
  {$else}
  Name = 'gh';
  Extra = '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/home/linuxbrew/.linuxbrew/bin:/snap/bin';
  {$endif}
var
  Path: string;
begin
  Path := GetEnvironmentVariable('PATH');
  if Extra <> '' then
    Path := Path + PathSeparator + Extra;
  Result := ExeSearch(Name, Path);
end;

function RunGitHubCli(const AExe, ADir: string; const AArgs: array of string;
  out AOutput, AError: string): boolean;
var
  P: TProcess;
  Status, i: integer;
begin
  AOutput := '';
  AError := '';
  P := TProcess.Create(nil);
  try
    P.Executable := AExe;
    P.CurrentDirectory := ADir;
    for i := 0 to High(AArgs) do
      P.Parameters.Add(AArgs[i]);
    CopyEnvironment(P, ['GH_PROMPT_DISABLED=', 'GH_NO_UPDATE_NOTIFIER=']);
    P.Environment.Add('GH_PROMPT_DISABLED=1');
    P.Environment.Add('GH_NO_UPDATE_NOTIFIER=1');
    P.Options := [poNoConsole];
    if P.RunCommandLoop(AOutput, AError, Status) <> 0 then
    begin
      AError := 'Could not run ' + AExe;
      Exit(False);
    end;
  finally
    P.Free;
  end;
  Result := Status = 0;
  if not Result then
  begin
    AError := Trim(AError);
    if AError = '' then
      AError := Trim(AOutput);
    AOutput := '';
  end;
end;

{ The NUL-separated fields of the output of a git command run with -z; a
  trailing NUL ends the last field and adds none. }
procedure SplitNul(const AOutput: string; AFields: TStrings);
var
  Start, i: integer;
begin
  AFields.Clear;
  Start := 1;
  for i := 1 to Length(AOutput) do
    if AOutput[i] = #0 then
    begin
      AFields.Add(Copy(AOutput, Start, i - Start));
      Start := i + 1;
    end;
  if Start <= Length(AOutput) then
    AFields.Add(Copy(AOutput, Start, MaxInt));
end;

{ TGittanRepo }

destructor TGittanRepo.Destroy;
begin
  DropTempIndex;
  inherited Destroy;
end;

function TGittanRepo.Open(const ADir: string): boolean;
var
  Top: string;
begin
  Close;
  if not DirectoryExists(ADir) then
  begin
    FError := Format('Folder not found: %s', [ADir]);
    Exit(False);
  end;
  Result := RunGit(ADir, ['rev-parse', '--show-toplevel'], Top);
  if Result then
    FRoot := Trim(Top)
  { git's message is in English (RunGit sets LC_ALL=C), so the common
    case gets a shorter one; any other failure keeps git's own. }
  else if Pos('not a git repository', FError) > 0 then
    FError := Format('Not a git repository: %s', [ADir]);
end;

procedure TGittanRepo.Close;
begin
  DropTempIndex;
  FRoot := '';
  FError := '';
  FBase := '';
  FWholeTree := False;
end;

function TGittanRepo.DiffBase: string;
begin
  if FBase = '' then
    Result := 'HEAD'
  else
    Result := FBase;
end;

function TGittanRepo.IsRange: boolean;
begin
  Result := Pos('..', FBase) > 0;
end;

{ The two ends of a range Base, HEAD for one left out. }
procedure TGittanRepo.SplitRange(out ALeft, ARight: string);
var
  p: integer;
begin
  p := Pos('..', FBase);
  ALeft := Copy(FBase, 1, p - 1);
  ARight := Copy(FBase, p + 2, MaxInt);
  if Copy(ARight, 1, 1) = '.' then
    Delete(ARight, 1, 1);
  if ALeft = '' then
    ALeft := 'HEAD';
  if ARight = '' then
    ARight := 'HEAD';
end;

function TGittanRepo.FullPath(const APath: string): string;
begin
  Result := IncludeTrailingPathDelimiter(FRoot) + SetDirSeparators(APath);
end;

{ The id of the empty tree, which depends on the repository's hash
  function: the base of a diff before the first commit. }
function TGittanRepo.EmptyTree: string;
var
  Format: string;
begin
  if RunGit(FRoot, ['rev-parse', '--show-object-format'], Format) and
    (Trim(Format) = 'sha256') then
    Result := '6ef19b41225c5369f1c104d45d8d85efa9b057b53b14b4b9b939dd74decc5321'
  else
    Result := '4b825dc642cb6eb9a060e54bf8d69288fbee4904';
end;

{ ---------------------------------------------------------------------------
  The whole tree through a temporary index
  ---------------------------------------------------------------------------
  `git diff <commit>` compares the commit with the work tree, but only for
  the paths the index knows: an untracked file is never in it, and a path
  the commit has but the index lacks reads as deleted. So a snapshot that
  holds the untracked files is compared through an index of its own: a
  copy of the repository's, with every file of the work tree added in
  intent (-N: the entry without its content, so no object is written) and
  the deleted ones dropped (-A) before each diff. The copy is made once
  per TGittanRepo and refreshed, since git then re-stats only what moved;
  the repository's own index is never written. The snapshot is built the
  same way, with the contents added (write-tree needs them). }

{ The repository's index file: in the git dir of the work tree (a linked
  work tree has one of its own). }
function TGittanRepo.IndexPath: string;
var
  Dir: string;
begin
  Result := '';
  if RunGit(FRoot, ['rev-parse', '--absolute-git-dir'], Dir) then
    Result := IncludeTrailingPathDelimiter(Trim(Dir)) + 'index';
end;

{ Copies the repository's index to ATarget; no index (nothing staged
  since init) leaves ATarget absent, which git takes as empty. }
function TGittanRepo.CopyIndex(const ATarget: string): boolean;
var
  Source: string;
  Stream: TMemoryStream;
begin
  Result := True;
  Source := IndexPath;
  if (Source = '') or not FileExists(Source) then
    Exit;
  Stream := TMemoryStream.Create;
  try
    try
      Stream.LoadFromFile(Source);
      Stream.SaveToFile(ATarget);
    except
      Result := False;
    end;
  finally
    Stream.Free;
  end;
end;

function TGittanRepo.WholeTreeActive: boolean;
begin
  Result := FWholeTree and (FBase <> '') and not IsRange;
end;

{ The temporary index for the whole tree comparison, brought up to date
  with the work tree; empty when the comparison does not apply, or the
  index could not be made (the diff then runs with the repository's). }
function TGittanRepo.CompareIndex: string;
var
  Output: string;
begin
  Result := '';
  if not WholeTreeActive then
    Exit;
  if FTempIndex = '' then
  begin
    FTempIndex := GetTempFileName(GetTempDir, 'gittan-index-');
    if not CopyIndex(FTempIndex) then
    begin
      DropTempIndex;
      Exit;
    end;
  end;
  RunGit(FRoot, ['add', '-A', '-N'], Output, FTempIndex);
  Result := FTempIndex;
end;

procedure TGittanRepo.SetWholeTree(AValue: boolean);
begin
  FWholeTree := AValue;
  if not AValue then
    DropTempIndex;
end;

procedure TGittanRepo.DropTempIndex;
begin
  if FTempIndex <> '' then
  begin
    DeleteFile(FTempIndex);
    DeleteFile(FTempIndex + '.lock');
    FTempIndex := '';
  end;
end;

function TGittanRepo.HasCommit(const ARef: string): boolean;
var
  Id: string;
begin
  Result := (FRoot <> '') and (ARef <> '') and
    RunGit(FRoot, ['rev-parse', '--verify', '-q', ARef + '^{commit}'], Id);
end;

function TGittanRepo.RemoteFor(const ARepoPath: string): string;
var
  Output, Line, Name: string;
  Raw: TStringList;
  p: integer;
  HasOrigin: boolean;
begin
  Result := '';
  HasOrigin := False;
  if (FRoot = '') or not RunGit(FRoot, ['config', '--get-regexp', '^remote\..*\.url$'],
    Output) then
    Exit;
  Raw := TStringList.Create;
  try
    Raw.Text := Output;
    for Line in Raw do
    begin
      { remote.<name>.url <url> }
      p := Pos(' ', Line);
      if (p = 0) or (Pos('remote.', Line) <> 1) then
        Continue;
      Name := Copy(Line, 8, p - 8);
      if Copy(Name, Length(Name) - 3, 4) <> '.url' then
        Continue;
      Name := Copy(Name, 1, Length(Name) - 4);
      if Result = '' then
        Result := Name;
      HasOrigin := HasOrigin or (Name = 'origin');
      if (ARepoPath <> '') and (Pos(LowerCase(ARepoPath), LowerCase(Line)) > p) then
        Exit(Name);
    end;
  finally
    Raw.Free;
  end;
  if HasOrigin then
    Result := 'origin';
end;

function TGittanRepo.FetchPullRequest(const ARemote: string; ANumber: integer;
  const ABaseRef: string; out AHeadRef: string): boolean;
var
  Output: string;
begin
  AHeadRef := 'refs/gittan/pr/' + IntToStr(ANumber);
  Result := (FRoot <> '') and (ARemote <> '') and RunGit(FRoot, ['fetch', '--no-tags',
    '-q', ARemote, ABaseRef, '+refs/pull/' + IntToStr(ANumber) + '/head:' + AHeadRef],
    Output);
end;

function TGittanRepo.TakeSnapshot(out AId: string): boolean;
var
  Index, Tree, Head: string;
begin
  AId := '';
  if FRoot = '' then
    Exit(False);
  Index := GetTempFileName(GetTempDir, 'gittan-snapshot-');
  try
    Result := CopyIndex(Index) and
      RunGit(FRoot, ['add', '-A'], Tree, Index) and
      RunGit(FRoot, ['write-tree'], Tree, Index);
    if not Result then
      Exit;
    Tree := Trim(Tree);
    { commit-tree refuses to run without a name and an e-mail, which a
      fresh machine (or a CI runner) does not have; the snapshot is never
      shared, so it gets an identity of its own. }
    if RunGit(FRoot, ['rev-parse', '--verify', '-q', 'HEAD'], Head) then
      Result := RunGit(FRoot, ['-c', 'user.name=Gittan', '-c',
        'user.email=gittan@localhost', 'commit-tree', Tree, '-p', Trim(Head),
        '-m', 'Gittan snapshot'], AId)
    else
      Result := RunGit(FRoot, ['-c', 'user.name=Gittan', '-c',
        'user.email=gittan@localhost', 'commit-tree', Tree, '-m',
        'Gittan snapshot'], AId);
    AId := Trim(AId);
  finally
    DeleteFile(Index);
    DeleteFile(Index + '.lock');
  end;
end;

{ Runs `git diff AArgs <base>`, with the base before the "--" of a path
  list when AArgs has one. HEAD does not exist before the first commit;
  the empty tree stands in then, so everything staged shows as added.
  Another base that does not resolve is an error. }
function TGittanRepo.RunDiff(const AArgs: array of string; out AOutput: string): boolean;
var
  Args: array of string;
  FirstError: string;
  Sep, i: integer;

  { "diff", -w when whitespace is ignored, then AArgs with ABase put
    before its "--" (or last, without one). }
  procedure Build(const ABase: string);
  var
    i, n: integer;
  begin
    SetLength(Args, Length(AArgs) + 3);
    n := 0;
    Args[n] := 'diff';
    Inc(n);
    if FIgnoreWhitespace then
    begin
      Args[n] := '-w';
      Inc(n);
    end;
    for i := 0 to High(AArgs) do
    begin
      if i = Sep then
      begin
        Args[n] := ABase;
        Inc(n);
      end;
      Args[n] := AArgs[i];
      Inc(n);
    end;
    if Sep = Length(AArgs) then
    begin
      Args[n] := ABase;
      Inc(n);
    end;
    SetLength(Args, n);
  end;

begin
  Sep := Length(AArgs);
  for i := 0 to High(AArgs) do
    if AArgs[i] = '--' then
    begin
      Sep := i;
      Break;
    end;
  Build(DiffBase);
  Result := RunGit(FRoot, Args, AOutput, CompareIndex);
  if not Result and (FBase = '') then
  begin
    { Without HEAD: the same call against the empty tree. When that fails
      too, HEAD was not the problem and the first message is the one to
      show. }
    FirstError := FError;
    Build(EmptyTree);
    Result := RunGit(FRoot, Args, AOutput);
    if not Result then
      FError := FirstError;
  end;
end;

function TGittanRepo.Diff: string;
begin
  Result := '';
  if FRoot = '' then
    Exit;
  RunDiff(['--no-color', '--no-ext-diff'], Result);
end;

{ for-each-ref sorts within each group, so the groups are asked for one
  by one: local branches, remote branches, tags. A symbolic ref such as
  origin/HEAD (short name "origin") is skipped: it only points at
  another one in the list. }
function TGittanRepo.Refs(AList: TStrings): boolean;
var
  Output, Line, Name: string;
  Group: string;
  Raw: TStringList;
  Tab: integer;
begin
  AList.Clear;
  if FRoot = '' then
    Exit(False);
  Result := True;
  Raw := TStringList.Create;
  try
    for Group in ['refs/heads', 'refs/remotes', 'refs/tags'] do
    begin
      if not RunGit(FRoot, ['for-each-ref', '--format=%(refname:short)%09%(symref)',
        '--sort=-committerdate', Group], Output) then
        Exit(False);
      Raw.Text := Output;
      for Line in Raw do
      begin
        Tab := Pos(#9, Line);
        if (Tab = 0) or (Tab < Length(Line)) then
          Continue;
        Name := Copy(Line, 1, Tab - 1);
        if (Name <> '') and (AList.IndexOf(Name) < 0) then
          AList.Add(Name);
      end;
    end;
  finally
    Raw.Free;
  end;
end;

{ Against HEAD the list is git status itself. Against another base it is
  `git diff --name-status` turned into the same "XY path" shape, with the
  letter in the work tree column, plus the untracked files from git
  status, which no diff lists (unless WholeTree is set). Untracked files are asked for one by one
  (--untracked-files=all): by default git folds a directory of them into
  a single "dir/" entry, which no diff or numstat can say anything
  about. Both are read with -z: a path with a space,
  a quote or a control character is quoted C-style in the line form, but
  comes as it is between NULs. A status entry is "XY path"; a rename or
  copy (R or C in either column) is followed by the old path as a field
  of its own, which is dropped. A name-status entry is two fields, the
  letter and the path (renames are off, so there is no third). }
function TGittanRepo.Files(AList: TStrings): boolean;
var
  Output: string;
begin
  AList.Clear;
  if FRoot = '' then
    Exit(False);
  Result := RunGit(FRoot, ['ls-files', '-z', '--cached', '--others',
    '--exclude-standard'], Output);
  if Result then
    SplitNul(Output, AList);
end;

function TGittanRepo.ChangedFiles(AList: TStrings): boolean;
var
  Output, Entry: string;
  Fields: TStringList;
  i: integer;
begin
  AList.Clear;
  if FRoot = '' then
    Exit(False);
  Fields := TStringList.Create;
  try
    { Between two commits the work tree has no say, so git status is
      not asked; nor for the whole tree, where the diff lists the
      untracked files itself. }
    if not IsRange and not WholeTreeActive then
    begin
      Result := RunGit(FRoot, ['status', '--porcelain', '-z',
        '--untracked-files=all'], Output);
      if not Result then
        Exit;
      SplitNul(Output, Fields);
      i := 0;
      while i < Fields.Count do
      begin
        Entry := Fields[i];
        Inc(i);
        if Length(Entry) < 4 then
          Continue;
        if (Entry[1] in ['R', 'C']) or (Entry[2] in ['R', 'C']) then
          Inc(i);
        if (FBase = '') or (Copy(Entry, 1, 2) = '??') then
          AList.Add(Entry);
      end;
      if FBase = '' then
        Exit;
    end;
    Result := RunDiff(['--name-status', '--no-renames', '-z'], Output);
    if not Result then
      Exit;
    SplitNul(Output, Fields);
    i := 0;
    while i + 1 < Fields.Count do
    begin
      if Fields[i] <> '' then
        AList.Add(' ' + Fields[i][1] + ' ' + Fields[i + 1]);
      Inc(i, 2);
    end;
  finally
    Fields.Free;
  end;
end;

class function TGittanRepo.StageFlags(const AStatus: string): integer;
begin
  Result := 0;
  if (Length(AStatus) >= 1) and (AStatus[1] in ['?', '!']) then
    Exit;
  if (Length(AStatus) >= 1) and (AStatus[1] <> ' ') then
    Result := Result or flagStaged;
  if (Length(AStatus) >= 2) and (AStatus[2] <> ' ') then
    Result := Result or flagUnstaged;
end;

function TGittanRepo.ChangedPaths(AList: TStrings): boolean;
var
  i: integer;
begin
  Result := ChangedFiles(AList);
  if not Result then
    Exit;
  for i := 0 to AList.Count - 1 do
  begin
    AList.Objects[i] := TObject(PtrUInt(Ord(ChangeKind(Copy(AList[i], 1, 2))) +
      StageFlags(Copy(AList[i], 1, 2))));
    AList[i] := Copy(AList[i], 4, MaxInt);
  end;
end;

{ Git's own heuristic: a NUL byte in the first 8000 bytes makes a file
  binary. A text file has one line per line feed, plus an unterminated last
  line. }
procedure CountNewFile(const AFileName: string; var AStat: TGittanFileStat);
const
  Probe = 8000;
var
  Stream: TFileStream;
  Buffer: array[0..4095] of byte;
  Got, i, Seen: integer;
  LastByte: byte;
begin
  AStat.Added := 0;
  AStat.Deleted := 0;
  AStat.Binary := False;
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    Seen := 0;
    LastByte := 10;
    repeat
      Got := Stream.Read(Buffer, SizeOf(Buffer));
      for i := 0 to Got - 1 do
      begin
        if (Buffer[i] = 0) and (Seen + i < Probe) then
        begin
          AStat.Binary := True;
          AStat.Added := 0;
          Exit;
        end;
        if Buffer[i] = 10 then
          Inc(AStat.Added);
      end;
      if Got > 0 then
        LastByte := Buffer[Got - 1];
      Inc(Seen, Got);
    until Got = 0;
    if (Seen > 0) and (LastByte <> 10) then
      Inc(AStat.Added);
  finally
    Stream.Free;
  end;
end;

{ A numstat entry is "added<tab>deleted<tab>path", with "-" for both counts
  of a binary file. Renames are turned off so the new path of a rename gets
  its counts; the old path is not in the list and is skipped. The counts
  are against HEAD, so staged and unstaged changes are both in. }
function TGittanRepo.ChangeStats(out AStats: TGittanFileStats): boolean;
var
  Paths, Num: TStringList;
  Output, Entry, Path, Counts, FileName: string;
  i, Tab1, Tab2, Idx: integer;
begin
  AStats := nil;
  Paths := TStringList.Create;
  Num := TStringList.Create;
  try
    Paths.CaseSensitive := True;
    Result := ChangedPaths(Paths);
    if not Result then
      Exit;
    SetLength(AStats, Paths.Count);
    for i := 0 to Paths.Count - 1 do
    begin
      AStats[i] := Default(TGittanFileStat);
      AStats[i].Path := Paths[i];
      AStats[i].Kind := TGittanChangeKind(PtrUInt(Paths.Objects[i]) and 15);
      AStats[i].Staged := PtrUInt(Paths.Objects[i]) and flagStaged <> 0;
      AStats[i].Unstaged := PtrUInt(Paths.Objects[i]) and flagUnstaged <> 0;
    end;
    RunDiff(['--numstat', '--no-renames', '-z'], Output);
    SplitNul(Output, Num);
    for Entry in Num do
    begin
      Tab1 := Pos(#9, Entry);
      if Tab1 = 0 then
        Continue;
      Tab2 := Pos(#9, Entry, Tab1 + 1);
      if Tab2 = 0 then
        Continue;
      Path := Copy(Entry, Tab2 + 1, MaxInt);
      Idx := Paths.IndexOf(Path);
      if Idx < 0 then
        Continue;
      Counts := Copy(Entry, 1, Tab1 - 1);
      if Counts = '-' then
        AStats[Idx].Binary := True
      else
      begin
        AStats[Idx].Added := StrToIntDef(Counts, 0);
        AStats[Idx].Deleted := StrToIntDef(Copy(Entry, Tab1 + 1, Tab2 - Tab1 - 1), 0);
      end;
    end;
    for i := 0 to High(AStats) do
      if AStats[i].Kind = ckUntracked then
      begin
        FileName := FullPath(AStats[i].Path);
        if FileExists(FileName) and not DirectoryExists(FileName) then
          CountNewFile(FileName, AStats[i]);
      end;
  finally
    Num.Free;
    Paths.Free;
  end;
end;

{ symbolic-ref names the branch even before its first commit; it fails
  when HEAD is detached, and the commit id stands in then. }
function TGittanRepo.DefaultBranch: string;
var
  Remote, Name: string;
begin
  Result := '';
  if FRoot = '' then
    Exit;
  Remote := RemoteFor('');
  if Remote = '' then
    Exit;
  if RunGit(FRoot, ['symbolic-ref', '--short', '-q', 'refs/remotes/' + Remote + '/HEAD'],
    Result) then
    Exit(Trim(Result));
  for Name in ['main', 'master'] do
    if HasCommit(Remote + '/' + Name) then
      Exit(Remote + '/' + Name);
  Result := '';
end;

function TGittanRepo.MergeBase(const ARef: string; out AHash: string): boolean;
begin
  AHash := '';
  Result := (FRoot <> '') and (ARef <> '') and
    RunGit(FRoot, ['merge-base', ARef, 'HEAD'], AHash);
  AHash := Trim(AHash);
  Result := Result and (AHash <> '');
end;

function TGittanRepo.AheadBehind(out AAhead, ABehind: integer): boolean;
var
  Output: string;
  Tab: integer;
begin
  AAhead := 0;
  ABehind := 0;
  { left-right counts the commits only on the upstream (behind) and only
    on HEAD (ahead), tab-separated. }
  Result := (FRoot <> '') and
    RunGit(FRoot, ['rev-list', '--left-right', '--count', '@{upstream}...HEAD'], Output);
  if not Result then
    Exit;
  Output := Trim(Output);
  Tab := Pos(#9, Output);
  Result := (Tab > 0) and TryStrToInt(Copy(Output, 1, Tab - 1), ABehind) and
    TryStrToInt(Copy(Output, Tab + 1, MaxInt), AAhead);
end;

function TGittanRepo.Branch: string;
begin
  Result := '';
  if FRoot = '' then
    Exit;
  if RunGit(FRoot, ['symbolic-ref', '--short', '-q', 'HEAD'], Result) then
    Result := Trim(Result)
  else if RunGit(FRoot, ['rev-parse', '--short', 'HEAD'], Result) then
    Result := Trim(Result)
  else
    Result := '';
end;

{ X is the index column, Y the work tree. A "U" in either (or both sides
  added or deleted) is an unmerged file; a deletion on either side wins over
  the rest since the file is gone; a rename or copy keeps its new path. "T"
  (type change) and anything unknown count as modified. }
class function TGittanRepo.ChangeKind(const AStatus: string): TGittanChangeKind;
var
  X, Y: char;
begin
  X := ' ';
  Y := ' ';
  if Length(AStatus) >= 1 then
    X := AStatus[1];
  if Length(AStatus) >= 2 then
    Y := AStatus[2];
  if (X = '?') or (Y = '?') then
    Result := ckUntracked
  else if (X = 'U') or (Y = 'U') or ((X = 'A') and (Y = 'A')) or
    ((X = 'D') and (Y = 'D')) then
    Result := ckConflict
  else if (X = 'D') or (Y = 'D') then
    Result := ckDeleted
  else if X in ['R', 'C'] then
    Result := ckRenamed
  else if (X = 'A') or (Y = 'A') then
    Result := ckAdded
  else
    Result := ckModified;
end;

{ The commit ids of HEAD and the base catch a commit, an amend or a moved
  branch that leaves the status alone; the status catches staging and the
  set of files; the hash of each changed file catches an edit, also one
  that keeps the line count, which the stat alone would miss when it
  falls within the resolution of the modification time. No diff is run:
  hashing the changed files is what one costs in reading, without the
  process and the diff on top. A deleted file is not on disk and adds
  nothing; a directory (a submodule) adds its stat alone. }
function TGittanRepo.Fingerprint: string;
var
  Paths: TStringList;
  Info: TSearchRec;
  FileName, Id, Left, Right: string;

  i: integer;
begin
  Result := '';
  if FRoot = '' then
    Exit;
  Paths := TStringList.Create;
  try
    if not ChangedPaths(Paths) then
      Exit;
    Result := Branch + #10;
    if RunGit(FRoot, ['rev-parse', '--verify', '-q', 'HEAD'], Id) then
      Result := Result + Trim(Id);
    if IsRange then
    begin
      SplitRange(Left, Right);
      if RunGit(FRoot, ['rev-parse', '--verify', '-q', Left + '^{commit}'], Id) then
        Result := Result + ' ' + Trim(Id);
      if RunGit(FRoot, ['rev-parse', '--verify', '-q', Right + '^{commit}'], Id) then
        Result := Result + ' ' + Trim(Id);
    end
    else if (FBase <> '') and RunGit(FRoot, ['rev-parse', '--verify', '-q',
      FBase + '^{commit}'], Id) then
      Result := Result + ' ' + Trim(Id);
    Result := Result + #10;
    for i := 0 to Paths.Count - 1 do
      Result := Result + IntToStr(PtrUInt(Paths.Objects[i])) + ' ' + Paths[i] + #10;
    { Between two commits the files on disk do not matter. }
    if IsRange then
      Exit;
    for i := 0 to Paths.Count - 1 do
    begin
      FileName := FullPath(Paths[i]);
      if FindFirst(FileName, faAnyFile, Info) <> 0 then
        Continue;
      Result := Result + Paths[i] + #9 + FormatDateTime('yyyymmddhhnnsszzz', Info.TimeStamp) + #9 + IntToStr(Info.Size);
      if Info.Attr and faDirectory = 0 then
        try
          Result := Result + #9 + MD5Print(MD5File(FileName));
        except
          { Gone or unreadable between the stat and the read; the stat
            says what it can. }
        end;
      Result := Result + #10;
      FindClose(Info);
    end;
  finally
    Paths.Free;
  end;
end;

{ The hunk header "@@" starts the lines; "\ No newline at end of file"
  notes are dropped. Renames are turned off so a renamed file is a plain new
  file under its new path, which is how the file tree lists it. }
function TGittanRepo.FileChanges(const APath: string; ALines: TStrings): boolean;
var
  Output, Line, FileName, Tracked: string;
  Raw: TStringList;
  InHunk: boolean;
  Marker: char;
begin
  ALines.Clear;
  if FRoot = '' then
    Exit(False);
  Result := RunDiff(['--no-color', '--no-ext-diff', '--no-renames',
    '-U99999999', '--', APath], Output);
  if not Result then
    Exit;
  Raw := TStringList.Create;
  try
    if Output = '' then
    begin
      { Not in HEAD or the index: an untracked file, all of it new. A
        tracked file without a diff (its changes are in whitespace only
        while IgnoreWhitespace is set, or its mode changed) is shown as
        it is, every line unchanged; between two commits as it is in the
        right one. }
      if IsRange then
      begin
        SplitRange(FileName, Tracked);
        if RunGit(FRoot, ['show', Tracked + ':' + APath], Output) then
        begin
          Raw.Text := Output;
          for Line in Raw do
            ALines.Add(' ' + Line);
        end;
        Exit;
      end;
      FileName := FullPath(APath);
      if FileExists(FileName) then
      begin
        if RunGit(FRoot, ['ls-files', '--', APath], Tracked, CompareIndex) and
          (Tracked <> '') then
          Marker := ' '
        else
          Marker := '+';
        Raw.LoadFromFile(FileName);
        for Line in Raw do
          ALines.Add(Marker + Line);
      end;
      Exit;
    end;
    Raw.Text := Output;
    InHunk := False;
    for Line in Raw do
      if not InHunk then
        InHunk := Copy(Line, 1, 2) = '@@'
      else if (Line <> '') and (Line[1] in [' ', '+', '-']) then
        ALines.Add(Line);
  finally
    Raw.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Blame
  --------------------------------------------------------------------------- }
procedure TGittanRepo.DiffSides(out ALeft, ARight: string);
begin
  if IsRange then
    SplitRange(ALeft, ARight)
  else
  begin
    ALeft := DiffBase;
    ARight := '';
  end;
end;

function TGittanRepo.CommitRange(const AHash: string): string;
begin
  if HasCommit(AHash + '^') then
    Result := AHash + '^..' + AHash
  else
    Result := EmptyTree + '..' + AHash;
end;

function TGittanRepo.Blame(const APath, ARef: string; out AOutput: string): boolean;
var
  Args: array of string;
  n: integer;
begin
  AOutput := '';
  if FRoot = '' then
    Exit(False);
  SetLength(Args, 6);
  Args[0] := 'blame';
  Args[1] := '--porcelain';
  n := 2;
  if FIgnoreWhitespace then
  begin
    Args[n] := '-w';
    Inc(n);
  end;
  if ARef <> '' then
  begin
    Args[n] := ARef;
    Inc(n);
  end;
  Args[n] := '--';
  Args[n + 1] := APath;
  SetLength(Args, n + 2);
  Result := RunGit(FRoot, Args, AOutput);
end;

function TGittanRepo.LineHistory(const APath, ARef: string; AFrom, ATo, AMax: integer;
  out AOutput: string): boolean;
var
  Args: array of string;

  procedure Add(const AArg: string);
  begin
    SetLength(Args, Length(Args) + 1);
    Args[High(Args)] := AArg;
  end;

begin
  AOutput := '';
  if FRoot = '' then
    Exit(False);
  Args := nil;
  Add('log');
  Add('--no-color');
  Add('--no-ext-diff');
  Add('-n');
  Add(IntToStr(AMax));
  Add('--format=%x01%H%x1f%an%x1f%at%x1f%s');
  if FIgnoreWhitespace then
    Add('-w');
  if AFrom > 0 then
  begin
    { -L takes no path list: the file is part of the range. }
    Add('-L');
    Add(Format('%d,%d:%s', [AFrom, ATo, APath]));
    if ARef <> '' then
      Add(ARef);
  end
  else
  begin
    Add('-p');
    Add('--no-renames');
    if ARef <> '' then
      Add(ARef);
    Add('--');
    Add(APath);
  end;
  Result := RunGit(FRoot, Args, AOutput);
end;

end.
