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
    FIgnoreWhitespace: boolean;
    function RunGit(const ADir: string; const AArgs: array of string;
      out AOutput: string): boolean;
    function DiffBase: string;
    function EmptyTree: string;
    function RunDiff(const AArgs: array of string; out AOutput: string): boolean;
    function FullPath(const APath: string): string;
  public
    {** Opens the repository that contains ADir. Returns false, with the git
      message in Error, when ADir is not inside a work tree. }
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
      commit id, or empty for HEAD. }
    property Base: string read FBase write FBase;
    {** Leave out changes in whitespace: every diff is run with -w, so a
      line that only changed its spacing counts as unchanged, and a file
      with no other change has no changes. }
    property IgnoreWhitespace: boolean read FIgnoreWhitespace write FIgnoreWhitespace;
  end;

implementation

uses
  Process, md5;

{ ---------------------------------------------------------------------------
  Running git
  ---------------------------------------------------------------------------
  git is found on PATH. stderr goes into the same string as stdout, so on
  failure the output is the error message and is kept in FError. git gets
  the environment of Gittan with LC_ALL set to C, so its messages come in
  English whatever the user's locale and the few that are matched on can
  be relied upon, and with prompts turned off, since nobody could answer
  one. Path names come back as plain UTF-8 instead of octal escapes. }
function TGittanRepo.RunGit(const ADir: string; const AArgs: array of string;
  out AOutput: string): boolean;
var
  P: TProcess;
  Err, Env: string;
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
    for i := 1 to GetEnvironmentVariableCount do
    begin
      Env := GetEnvironmentString(i);
      if (Pos('LC_ALL=', Env) <> 1) and (Pos('GIT_TERMINAL_PROMPT=', Env) <> 1) then
        P.Environment.Add(Env);
    end;
    P.Environment.Add('LC_ALL=C');
    P.Environment.Add('GIT_TERMINAL_PROMPT=0');
    P.Options := [poStderrToOutPut, poNoConsole];
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
    FError := Trim(AOutput);
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
  FRoot := '';
  FError := '';
  FBase := '';
end;

function TGittanRepo.DiffBase: string;
begin
  if FBase = '' then
    Result := 'HEAD'
  else
    Result := FBase;
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
  Result := RunGit(FRoot, Args, AOutput);
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
  status, which no diff lists. Untracked files are asked for one by one
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
  Result := RunGit(FRoot, ['status', '--porcelain', '-z',
    '--untracked-files=all'], Output);
  if not Result then
    Exit;
  Fields := TStringList.Create;
  try
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
  else if X = 'A' then
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
  FileName, Id: string;
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
    if (FBase <> '') and RunGit(FRoot, ['rev-parse', '--verify', '-q',
      FBase + '^{commit}'], Id) then
      Result := Result + ' ' + Trim(Id);
    Result := Result + #10;
    for i := 0 to Paths.Count - 1 do
      Result := Result + IntToStr(PtrUInt(Paths.Objects[i])) + ' ' + Paths[i] + #10;
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
        it is, every line unchanged. }
      FileName := FullPath(APath);
      if FileExists(FileName) then
      begin
        if RunGit(FRoot, ['ls-files', '--', APath], Tracked) and (Tracked <> '') then
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

end.
