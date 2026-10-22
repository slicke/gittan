unit gittan.submodules;

{** The repository's submodules: the list .gitmodules and the index give
  (ListSubmodules), and what one of them looks like up close (CheckSubmodule):
  the commit the repository records for it, the commit checked out in it,
  and the commit its remote's branch is at, asked with git ls-remote, so
  nothing is fetched and nothing in the submodule changes. When the
  submodule already has the remote's commit, the commits between are
  counted and listed. CompareSubmodule tells how a changed submodule
  moved between the two sides of a comparison, and MovedSubmodules which
  ones an update would move back. TGittanSubmoduleJob runs CheckSubmodule in a thread,
  since ls-remote goes to the network. Nothing here needs the LCL; the
  unit is tested in tests/testsubmodules.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.job;

const
  {** The file at the root that names the submodules. }
  SubmodulesFile = '.gitmodules';
  {** The most incoming commits CheckSubmodule lists. }
  MaxIncoming = 50;
  { How many branches holding the recorded commit CheckSubmodule names. }
  MaxHolding = 3;

type
  {** One submodule as .gitmodules and the index describe it: its name
    (the section name), its path from the root with "/" separators, its
    URL as written (possibly relative to the repository's own remote),
    the branch .gitmodules names (empty for the remote's default branch,
    "." for the repository's own branch), and the commit the index
    records for it, empty when it records none. Conflict is set when the
    index holds the path in more than one stage. }
  TGittanSubmodule = record
    Name, Path, Url, Branch, Recorded: string;
    Conflict: boolean;
  end;
  TGittanSubmodules = array of TGittanSubmodule;

  {** What CheckSubmodule found out about the remote:
    smUnknown before it ran, smUpToDate when the remote's branch is at
    the recorded commit, smBehind when it has commits the recorded one
    lacks (Behind of them), smAhead when the recorded commit is past it,
    smDiverged when both, smNotFetched when the remote is elsewhere but
    the submodule lacks the commit there (or is not initialized), so the
    commits cannot be counted, and smFailed when ls-remote failed. }
  TGittanSubmoduleState = (smUnknown, smUpToDate, smBehind, smAhead,
    smDiverged, smNotFetched, smFailed);

  {** One commit as the submodule view shows it. }
  TGittanSubmoduleCommit = record
    Hash, Short, Date, Author, Subject: string;
  end;
  TGittanSubmoduleCommits = array of TGittanSubmoduleCommit;

  {** What CheckSubmodule found. Initialized is set when the submodule has
    a git directory in its work tree. CheckedOut is the commit its HEAD
    is at (empty when not initialized). RemoteRef is the ref asked of
    the remote ("HEAD" or "refs/heads/<branch>"), Tip the commit it is at.
    Recorded and Current describe the recorded commit and the checked out
    one when the submodule has them (Hash empty otherwise). Behind and
    Ahead count the commits between the recorded commit and Tip, -1 when
    unknown; Incoming lists the remote's commits that the recorded one
    lacks, newest first, at most MaxIncoming, and Outgoing the recorded
    commit's that the remote lacks. TipCommit describes Tip when the
    submodule has it. Holding lists the remote-tracking branches of the
    submodule (origin/main, without origin/HEAD) that have the recorded
    commit, at most MaxHolding, when the remote's branch lacks it; read
    from the submodule's own refs, so as of its last fetch. Error is
    git's message for smFailed. }
  TGittanSubmoduleInfo = record
    Path: string;
    State: TGittanSubmoduleState;
    Initialized: boolean;
    CheckedOut, RemoteRef, Tip, Error: string;
    Recorded, Current, TipCommit: TGittanSubmoduleCommit;
    Behind, Ahead: integer;
    Incoming, Outgoing: TGittanSubmoduleCommits;
    Holding: TStringArray;
  end;

  {** How a submodule moved between the two sides of what is compared:
    FromHash is the commit the left side records for it, ToHash the one
    the right side records, or for the work tree the commit checked out
    (the recorded one when not initialized); either is empty when that
    side has no submodule there. FromCommit and ToCommit describe them
    when the submodule has them (Hash empty otherwise). Added counts the
    commits ToHash has that FromHash lacks, Removed the other way round,
    both -1 when they cannot be counted; Commits lists the added ones and
    Dropped the removed ones, newest first, at most MaxIncoming each. }
  TGittanSubmoduleChange = record
    FromHash, ToHash: string;
    FromCommit, ToCommit: TGittanSubmoduleCommit;
    Added, Removed: integer;
    Commits, Dropped: TGittanSubmoduleCommits;
  end;

{** Reads what `git config -z --get-regexp ^submodule\.` prints for
  .gitmodules into one record per submodule, in the order they come,
  each with its name, path, URL and branch. A submodule without a path
  is left out. }
procedure ParseSubmoduleConfig(const AOutput: string; out AList: TGittanSubmodules);

{** Sets Recorded and Conflict of the submodules in AList from what
  `git ls-files -s -z` prints: the commit of each gitlink (mode 160000)
  at its path. }
procedure ApplyIndexEntries(const AOutput: string; var AList: TGittanSubmodules);

{** The ref CheckSubmodule asks the remote for: "HEAD" for no branch,
  the repository's own branch ASuperBranch for "." (HEAD when it is on
  none), else "refs/heads/<branch>". }
function SubmoduleRemoteRef(const ABranch, ASuperBranch: string): string;

{** The commit `git ls-remote` printed for ARef, empty when it did not
  list ARef. }
function ParseLsRemote(const AOutput, ARef: string): string;

{** The URL of a submodule whose URL AUrl is relative ("./" or "../"),
  taken from ASuperUrl, the URL of the repository's own remote, as git
  does: each "../" drops one part of it, "./" none. Any other URL is
  answered as it is. }
function ResolveSubmoduleUrl(const ASuperUrl, AUrl: string): string;

{** Reads the commits of a `git log` run with SubmoduleLogFormat. }
procedure ParseSubmoduleLog(const AOutput: string; out ACommits: TGittanSubmoduleCommits);

{** The format CheckSubmodule gives git log. }
function SubmoduleLogFormat: string;

{** The commit of the gitlink `git ls-tree -z <ref> -- <path>` printed,
  empty when it printed none (the path is a file, or not there). }
function ParseGitlink(const AOutput: string): string;

{** Lists the submodules of the repository at ARoot: the ones .gitmodules
  names, with the commits the index records. Empty, and true, when there
  is no .gitmodules; false, with git's message in AError, when git
  failed. }
function ListSubmodules(const ARoot: string; out AList: TGittanSubmodules;
  out AError: string): boolean;

{** Looks at ASub of the repository at ARoot: the commit checked out in
  it, the commit its remote's branch is at (ls-remote, the network), and
  how far apart that is from the recorded commit when the submodule has
  both. ASuperBranch is the repository's own branch, for a branch of
  ".". }
function CheckSubmodule(const ARoot: string; const ASub: TGittanSubmodule;
  const ASuperBranch: string): TGittanSubmoduleInfo;

{** How ASub of the repository at ARoot moved from the commit ALeft
  records for it to the one ARight records, or, for an empty ARight, to
  the commit checked out in it. Only the submodule's own objects are
  read, nothing is fetched. }
function CompareSubmodule(const ARoot: string; const ASub: TGittanSubmodule;
  const ALeft, ARight: string): TGittanSubmoduleChange;

{** Reads what `git submodule status` prints into the paths of the
  submodules checked out at another commit than the one recorded for
  them (the lines marked "+"), each followed by "=" and that commit. }
procedure ParseMovedSubmodules(const AOutput: string; AMoved: TStrings);

{** The submodules of the repository at ARoot (APath alone, unless it is
  empty) checked out at another commit than the one recorded, as
  ParseMovedSubmodules gives them: what an update would move back. }
function MovedSubmodules(const ARoot, APath: string; AMoved: TStrings): boolean;

{** The folder every submodule in AList is in, with a trailing "/"
  (vendor/ when they are vendor/a and vendor/b), where a new one likely
  goes too; empty when they are in no common folder. }
function SubmoduleFolder(const AList: TGittanSubmodules): string;

type
  {** Runs CheckSubmodule in a thread. OnDone is called in the main thread
    when it is done, as long as the job has not been stopped. }
  TGittanSubmoduleJob = class(TGittanJob)
  private
    FRoot, FSuperBranch: string;
    FSub: TGittanSubmodule;
    FInfo: TGittanSubmoduleInfo;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: string; const ASub: TGittanSubmodule;
      const ASuperBranch: string);
    property Sub: TGittanSubmodule read FSub;
    property Info: TGittanSubmoduleInfo read FInfo;
  end;

implementation

uses
  Math, StrUtils, gittan.git;

{ The fields of output from a command run with -z; a trailing NUL ends
  the last field and adds none. }
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

{ git config -z prints each entry as the key, a newline and the value.
  The name of a submodule may hold dots, so the key is cut at the first
  dot after "submodule." and at the last one. }
procedure ParseSubmoduleConfig(const AOutput: string; out AList: TGittanSubmodules);
const
  Prefix = 'submodule.';
var
  Fields: TStringList;
  Entry, Key, Value, Name, Field: string;
  i, j, NL, Dot, Found: integer;
begin
  AList := nil;
  Fields := TStringList.Create;
  try
    SplitNul(AOutput, Fields);
    for i := 0 to Fields.Count - 1 do
    begin
      Entry := Fields[i];
      NL := Pos(#10, Entry);
      if NL = 0 then
        Continue;
      Key := Copy(Entry, 1, NL - 1);
      Value := Copy(Entry, NL + 1, MaxInt);
      if Copy(Key, 1, Length(Prefix)) <> Prefix then
        Continue;
      Dot := RPos('.', Key);
      if Dot <= Length(Prefix) + 1 then
        Continue;
      Name := Copy(Key, Length(Prefix) + 1, Dot - Length(Prefix) - 1);
      Field := LowerCase(Copy(Key, Dot + 1, MaxInt));
      Found := -1;
      for j := 0 to High(AList) do
        if AList[j].Name = Name then
        begin
          Found := j;
          Break;
        end;
      if Found < 0 then
      begin
        SetLength(AList, Length(AList) + 1);
        Found := High(AList);
        AList[Found] := Default(TGittanSubmodule);
        AList[Found].Name := Name;
      end;
      case Field of
        'path': AList[Found].Path := ExcludeTrailingPathDelimiter(Value);
        'url': AList[Found].Url := Value;
        'branch': AList[Found].Branch := Value;
      end;
    end;
  finally
    Fields.Free;
  end;
  j := 0;
  for i := 0 to High(AList) do
    if AList[i].Path <> '' then
    begin
      AList[j] := AList[i];
      Inc(j);
    end;
  SetLength(AList, j);
end;

{ Each entry is "<mode> <hash> <stage>\t<path>". }
procedure ApplyIndexEntries(const AOutput: string; var AList: TGittanSubmodules);
var
  Fields: TStringList;
  Entry, Path, Hash, Stage: string;
  i, j, Tab, Sp1, Sp2: integer;
begin
  Fields := TStringList.Create;
  try
    SplitNul(AOutput, Fields);
    for i := 0 to Fields.Count - 1 do
    begin
      Entry := Fields[i];
      if Copy(Entry, 1, 7) <> '160000 ' then
        Continue;
      Tab := Pos(#9, Entry);
      Sp1 := 7;
      Sp2 := PosEx(' ', Entry, Sp1 + 1);
      if (Tab = 0) or (Sp2 = 0) or (Sp2 > Tab) then
        Continue;
      Hash := Copy(Entry, Sp1 + 1, Sp2 - Sp1 - 1);
      Stage := Copy(Entry, Sp2 + 1, Tab - Sp2 - 1);
      Path := Copy(Entry, Tab + 1, MaxInt);
      for j := 0 to High(AList) do
        if AList[j].Path = Path then
        begin
          if Stage = '0' then
            AList[j].Recorded := Hash
          else
          begin
            AList[j].Conflict := True;
            { "ours" stands for the recorded commit while in conflict. }
            if Stage = '2' then
              AList[j].Recorded := Hash;
          end;
          Break;
        end;
    end;
  finally
    Fields.Free;
  end;
end;

function SubmoduleRemoteRef(const ABranch, ASuperBranch: string): string;
begin
  if ABranch = '' then
    Result := 'HEAD'
  else if ABranch = '.' then
  begin
    if ASuperBranch = '' then
      Result := 'HEAD'
    else
      Result := 'refs/heads/' + ASuperBranch;
  end
  else
    Result := 'refs/heads/' + ABranch;
end;

function ParseLsRemote(const AOutput, ARef: string): string;
var
  Lines: TStringList;
  Line: string;
  i, Tab: integer;
begin
  Result := '';
  Lines := TStringList.Create;
  try
    Lines.Text := AOutput;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      Tab := Pos(#9, Line);
      if (Tab > 0) and (Copy(Line, Tab + 1, MaxInt) = ARef) then
        Exit(Copy(Line, 1, Tab - 1));
    end;
  finally
    Lines.Free;
  end;
end;

function ResolveSubmoduleUrl(const ASuperUrl, AUrl: string): string;
var
  Base, Rel: string;
  Cut: integer;
begin
  if (Copy(AUrl, 1, 2) <> './') and (Copy(AUrl, 1, 3) <> '../') then
    Exit(AUrl);
  Base := ASuperUrl;
  while (Base <> '') and (Base[Length(Base)] = '/') do
    Delete(Base, Length(Base), 1);
  Rel := AUrl;
  repeat
    if Copy(Rel, 1, 2) = './' then
      Delete(Rel, 1, 2)
    else if Copy(Rel, 1, 3) = '../' then
    begin
      Delete(Rel, 1, 3);
      { The last part goes; scp-like addresses (host:owner/repo) split at
        the colon too. }
      Cut := Max(RPos('/', Base), RPos(':', Base));
      if Cut > 0 then
        Base := Copy(Base, 1, Cut - 1) + Copy(Base, Cut, 1)
      else
        Base := '';
      if (Base <> '') and (Base[Length(Base)] = '/') then
        Delete(Base, Length(Base), 1);
    end
    else
      Break;
  until False;
  if (Base <> '') and (Base[Length(Base)] = ':') then
    Result := Base + Rel
  else if Base <> '' then
    Result := Base + '/' + Rel
  else
    Result := Rel;
end;

function SubmoduleLogFormat: string;
begin
  Result := '--format=%H%x1f%h%x1f%as%x1f%an%x1f%s';
end;

procedure ParseSubmoduleLog(const AOutput: string; out ACommits: TGittanSubmoduleCommits);
var
  Lines, Parts: TStringList;
  i: integer;
begin
  ACommits := nil;
  Lines := TStringList.Create;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := #31;
    Parts.StrictDelimiter := True;
    Lines.Text := AOutput;
    for i := 0 to Lines.Count - 1 do
    begin
      Parts.DelimitedText := Lines[i];
      if Parts.Count < 5 then
        Continue;
      SetLength(ACommits, Length(ACommits) + 1);
      with ACommits[High(ACommits)] do
      begin
        Hash := Parts[0];
        Short := Parts[1];
        Date := Parts[2];
        Author := Parts[3];
        Subject := Parts[4];
      end;
    end;
  finally
    Parts.Free;
    Lines.Free;
  end;
end;

{ The entry is "<mode> <type> <hash>\t<path>". }
function ParseGitlink(const AOutput: string): string;
var
  Tab: integer;
begin
  Result := '';
  Tab := Pos(#9, AOutput);
  if (Tab = 0) or (Copy(AOutput, 1, 14) <> '160000 commit ') then
    Exit;
  Result := Copy(AOutput, 15, Tab - 15);
end;

function ListSubmodules(const ARoot: string; out AList: TGittanSubmodules;
  out AError: string): boolean;
var
  Output: string;
begin
  AList := nil;
  AError := '';
  if (ARoot = '') or not FileExists(IncludeTrailingPathDelimiter(ARoot) + SubmodulesFile) then
    Exit(True);
  { An empty .gitmodules makes git config fail with status 1 and no
    message; that is no submodules, not a failure. }
  if not RunGitIn(ARoot, ['config', '-z', '-f', SubmodulesFile, '--get-regexp',
    '^submodule\.'], Output, AError) then
    Exit(AError = '');
  ParseSubmoduleConfig(Output, AList);
  if Length(AList) = 0 then
    Exit(True);
  Result := RunGitIn(ARoot, ['ls-files', '-s', '-z'], Output, AError);
  if Result then
    ApplyIndexEntries(Output, AList);
end;

{ Each line is a mark (" ", "-" not initialized, "+" moved, "U" in
  conflict), the commit checked out, the path as it is, and after it
  " (<describe>)" when git could name the commit. }
procedure ParseMovedSubmodules(const AOutput: string; AMoved: TStrings);
var
  Lines: TStringList;
  Line, Hash, Path: string;
  Space, i: integer;
begin
  AMoved.Clear;
  Lines := TStringList.Create;
  try
    Lines.Text := AOutput;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      if (Line = '') or (Line[1] <> '+') then
        Continue;
      Space := Pos(' ', Line);
      if Space = 0 then
        Continue;
      Hash := Copy(Line, 2, Space - 2);
      Path := Copy(Line, Space + 1, MaxInt);
      if (Path <> '') and (Path[Length(Path)] = ')') and (RPos(' (', Path) > 0) then
        SetLength(Path, RPos(' (', Path) - 1);
      if Path <> '' then
        AMoved.Add(Path + '=' + Hash);
    end;
  finally
    Lines.Free;
  end;
end;

function MovedSubmodules(const ARoot, APath: string; AMoved: TStrings): boolean;
var
  Output, Err: string;
begin
  AMoved.Clear;
  if APath = '' then
    Result := RunGitIn(ARoot, ['submodule', 'status'], Output, Err)
  else
    Result := RunGitIn(ARoot, ['submodule', 'status', '--', APath], Output, Err);
  if Result then
    ParseMovedSubmodules(Output, AMoved);
end;

function SubmoduleFolder(const AList: TGittanSubmodules): string;
var
  Folder: string;
  i: integer;
begin
  Result := '';
  for i := 0 to High(AList) do
  begin
    Folder := Copy(AList[i].Path, 1, RPos('/', AList[i].Path));
    if Folder = '' then
      Exit('');
    if i = 0 then
      Result := Folder
    else
      { The longest folder both are in, whole parts only. }
      while (Result <> '') and (Copy(Folder, 1, Length(Result)) <> Result) do
        Result := Copy(Result, 1, RPos('/', Copy(Result, 1, Length(Result) - 1)));
  end;
end;

{ The commit AHash of the repository at ADir, Hash empty when it does not
  have it. }
function DescribeCommit(const ADir, AHash: string): TGittanSubmoduleCommit;
var
  Output, Err: string;
  Commits: TGittanSubmoduleCommits;
begin
  Result := Default(TGittanSubmoduleCommit);
  if (AHash = '') or not RunGitIn(ADir, ['log', '-1', '--no-color',
    SubmoduleLogFormat, AHash + '^{commit}', '--'], Output, Err) then
    Exit;
  ParseSubmoduleLog(Output, Commits);
  if Length(Commits) > 0 then
    Result := Commits[0];
end;

function HasObject(const ADir, AHash: string): boolean;
var
  Output, Err: string;
begin
  Result := (AHash <> '') and RunGitIn(ADir, ['cat-file', '-e', AHash + '^{commit}'],
    Output, Err);
end;

{ Whether the submodule's work tree ADir has a git directory. }
function IsInitialized(const ADir: string): boolean;
begin
  Result := FileExists(IncludeTrailingPathDelimiter(ADir) + '.git') or
    DirectoryExists(IncludeTrailingPathDelimiter(ADir) + '.git');
end;

{ The counts of `git rev-list --left-right --count A...B` in ADir: the
  commits only A has in ALeft, only B has in ARight; false when git
  failed. }
function CountApart(const ADir, A, B: string; out ALeft, ARight: integer): boolean;
var
  Output, Err: string;
  Tab: integer;
begin
  ALeft := -1;
  ARight := -1;
  if not RunGitIn(ADir, ['rev-list', '--left-right', '--count', A + '...' + B],
    Output, Err) then
    Exit(False);
  Output := Trim(Output);
  Tab := Pos(#9, Output);
  Result := (Tab > 0) and TryStrToInt(Copy(Output, 1, Tab - 1), ALeft) and
    TryStrToInt(Copy(Output, Tab + 1, MaxInt), ARight);
  if not Result then
  begin
    ALeft := -1;
    ARight := -1;
  end;
end;

{ The commits of ARange in ADir, newest first, at most MaxIncoming. }
{ The remote-tracking branches of the submodule at ADir that have AHash,
  at most MaxHolding, origin/HEAD left out. }
function HoldingBranches(const ADir, AHash: string): TStringArray;
var
  Output, Err, Name: string;
  Lines: TStringList;
  i: integer;
begin
  Result := nil;
  if not RunGitIn(ADir, ['for-each-ref', '--format=%(refname:short)%09%(symref)',
    '--contains', AHash, 'refs/remotes/'], Output, Err) then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for i := 0 to Lines.Count - 1 do
    begin
      { A symbolic ref, origin/HEAD, names its target after a tab. }
      if Pos(#9, Lines[i]) = 0 then
        Continue;
      Name := Copy(Lines[i], 1, Pos(#9, Lines[i]) - 1);
      if (Name = '') or (Trim(Copy(Lines[i], Pos(#9, Lines[i]) + 1, MaxInt)) <> '') then
        Continue;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Name;
      if Length(Result) = MaxHolding then
        Break;
    end;
  finally
    Lines.Free;
  end;
end;

function LogRange(const ADir, ARange: string): TGittanSubmoduleCommits;
var
  Output, Err: string;
begin
  Result := nil;
  if RunGitIn(ADir, ['log', '--no-color', '-n', IntToStr(MaxIncoming),
    SubmoduleLogFormat, ARange, '--'], Output, Err) then
    ParseSubmoduleLog(Output, Result);
end;

function CompareSubmodule(const ARoot: string; const ASub: TGittanSubmodule;
  const ALeft, ARight: string): TGittanSubmoduleChange;
var
  Dir, Output, Err: string;
  Initialized: boolean;
begin
  Result := Default(TGittanSubmoduleChange);
  Result.Added := -1;
  Result.Removed := -1;
  Dir := IncludeTrailingPathDelimiter(ARoot) + SetDirSeparators(ASub.Path);
  Initialized := IsInitialized(Dir);
  if RunGitIn(ARoot, ['ls-tree', '-z', ALeft, '--', ASub.Path], Output, Err) then
    Result.FromHash := ParseGitlink(Output);
  if ARight <> '' then
  begin
    if RunGitIn(ARoot, ['ls-tree', '-z', ARight, '--', ASub.Path], Output, Err) then
      Result.ToHash := ParseGitlink(Output);
  end
  else if Initialized and RunGitIn(Dir, ['rev-parse', '--verify', '-q', 'HEAD'],
    Output, Err) then
    Result.ToHash := Trim(Output)
  else
    Result.ToHash := ASub.Recorded;
  if Result.FromHash = Result.ToHash then
  begin
    Result.Added := 0;
    Result.Removed := 0;
    Exit;
  end;
  if not Initialized then
    Exit;
  Result.FromCommit := DescribeCommit(Dir, Result.FromHash);
  Result.ToCommit := DescribeCommit(Dir, Result.ToHash);
  if (Result.FromCommit.Hash = '') or (Result.ToCommit.Hash = '') or
    not CountApart(Dir, Result.FromHash, Result.ToHash, Result.Removed, Result.Added) then
    Exit;
  if Result.Added > 0 then
    Result.Commits := LogRange(Dir, Result.FromHash + '..' + Result.ToHash);
  if Result.Removed > 0 then
    Result.Dropped := LogRange(Dir, Result.ToHash + '..' + Result.FromHash);
end;

function CheckSubmodule(const ARoot: string; const ASub: TGittanSubmodule;
  const ASuperBranch: string): TGittanSubmoduleInfo;
var
  Dir, Output, Err, RunDir, Remote, SuperUrl: string;
begin
  Result := Default(TGittanSubmoduleInfo);
  Result.Path := ASub.Path;
  Result.Behind := -1;
  Result.Ahead := -1;
  Dir := IncludeTrailingPathDelimiter(ARoot) + SetDirSeparators(ASub.Path);
  Result.Initialized := IsInitialized(Dir);
  if Result.Initialized and RunGitIn(Dir, ['rev-parse', '--verify', '-q', 'HEAD'],
    Output, Err) then
    Result.CheckedOut := Trim(Output);
  if Result.Initialized then
  begin
    Result.Recorded := DescribeCommit(Dir, ASub.Recorded);
    if Result.CheckedOut <> ASub.Recorded then
      Result.Current := DescribeCommit(Dir, Result.CheckedOut)
    else
      Result.Current := Result.Recorded;
  end;
  Result.RemoteRef := SubmoduleRemoteRef(ASub.Branch, ASuperBranch);
  { An initialized submodule asks its own remote, the one an update
    would fetch from; one that is not asks the URL of .gitmodules, made
    absolute against the repository's own remote when it is relative. }
  if Result.Initialized then
  begin
    Remote := 'origin';
    RunDir := Dir;
  end
  else
  begin
    RunDir := ARoot;
    Remote := ASub.Url;
    if (Copy(Remote, 1, 2) = './') or (Copy(Remote, 1, 3) = '../') then
    begin
      if not RunGitIn(ARoot, ['config', '--get', 'remote.origin.url'], SuperUrl, Err) then
      begin
        Result.State := smFailed;
        Result.Error := 'The URL is relative and the repository has no origin remote.';
        Exit;
      end;
      Remote := ResolveSubmoduleUrl(Trim(SuperUrl), Remote);
    end;
  end;
  if not RunGitIn(RunDir, ['ls-remote', '--', Remote, Result.RemoteRef], Output, Err) then
  begin
    Result.State := smFailed;
    Result.Error := Err;
    Exit;
  end;
  Result.Tip := ParseLsRemote(Output, Result.RemoteRef);
  if Result.Tip = '' then
  begin
    Result.State := smFailed;
    if Result.RemoteRef = 'HEAD' then
      Result.Error := 'The remote has no default branch.'
    else
      Result.Error := Format('The remote has no branch %s.',
        [Copy(Result.RemoteRef, Length('refs/heads/') + 1, MaxInt)]);
    Exit;
  end;
  if Result.Tip = ASub.Recorded then
  begin
    Result.State := smUpToDate;
    Result.Behind := 0;
    Result.Ahead := 0;
    Exit;
  end;
  Result.State := smNotFetched;
  if not Result.Initialized or not HasObject(Dir, Result.Tip) or
    not HasObject(Dir, ASub.Recorded) then
    Exit;
  if not CountApart(Dir, ASub.Recorded, Result.Tip, Result.Ahead, Result.Behind) then
    Exit;
  if (Result.Behind > 0) and (Result.Ahead > 0) then
    Result.State := smDiverged
  else if Result.Behind > 0 then
    Result.State := smBehind
  else
    Result.State := smAhead;
  Result.TipCommit := DescribeCommit(Dir, Result.Tip);
  if Result.Behind > 0 then
    Result.Incoming := LogRange(Dir, ASub.Recorded + '..' + Result.Tip);
  if Result.Ahead > 0 then
  begin
    Result.Outgoing := LogRange(Dir, Result.Tip + '..' + ASub.Recorded);
    Result.Holding := HoldingBranches(Dir, ASub.Recorded);
  end;
end;

{ ---------------------------------------------------------------------------
  The job
  --------------------------------------------------------------------------- }

constructor TGittanSubmoduleJob.Create(const ARoot: string;
  const ASub: TGittanSubmodule; const ASuperBranch: string);
begin
  inherited Create(True);
  FRoot := ARoot;
  FSub := ASub;
  FSuperBranch := ASuperBranch;
end;

procedure TGittanSubmoduleJob.Execute;
begin
  FInfo := CheckSubmodule(FRoot, FSub, FSuperBranch);
  Done;
end;

end.
