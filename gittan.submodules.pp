unit gittan.submodules;

{** The repository's submodules: the list .gitmodules and the index give
  (ListSubmodules), and what one of them looks like up close (CheckSubmodule):
  the commit the repository records for it, the commit checked out in it,
  and the commit its remote's branch is at, asked with git ls-remote, so
  nothing is fetched and nothing in the submodule changes. When the
  submodule already has the remote's commit, the commits between are
  counted and listed. TGittanSubmoduleJob runs CheckSubmodule in a thread,
  since ls-remote goes to the network. Nothing here needs the LCL; the
  unit is tested in tests/testsubmodules.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  {** The file at the root that names the submodules. }
  SubmodulesFile = '.gitmodules';
  {** The most incoming commits CheckSubmodule lists. }
  MaxIncoming = 50;

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
    lacks, newest first, at most MaxIncoming. Error is git's message for
    smFailed. }
  TGittanSubmoduleInfo = record
    Path: string;
    State: TGittanSubmoduleState;
    Initialized: boolean;
    CheckedOut, RemoteRef, Tip, Error: string;
    Recorded, Current: TGittanSubmoduleCommit;
    Behind, Ahead: integer;
    Incoming: TGittanSubmoduleCommits;
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

type
  {** Runs CheckSubmodule in a thread. OnDone is called in the main thread
    when it is done, as long as the job has not been stopped. }
  TGittanSubmoduleJob = class(TThread)
  private
    FRoot, FSuperBranch: string;
    FSub: TGittanSubmodule;
    FInfo: TGittanSubmoduleInfo;
    FOnDone: TNotifyEvent;
    procedure Notify;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: string; const ASub: TGittanSubmodule;
      const ASuperBranch: string);
    {** Drops the handler and ends the thread; a result still on its way
      is thrown away. Waits for a running git only when AWait is set. }
    procedure Stop(AWait: boolean);
    property Sub: TGittanSubmodule read FSub;
    property Info: TGittanSubmoduleInfo read FInfo;
    property OnDone: TNotifyEvent read FOnDone write FOnDone;
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

function CheckSubmodule(const ARoot: string; const ASub: TGittanSubmodule;
  const ASuperBranch: string): TGittanSubmoduleInfo;
var
  Dir, Output, Err, RunDir, Remote, SuperUrl: string;
  Tab: integer;
begin
  Result := Default(TGittanSubmoduleInfo);
  Result.Path := ASub.Path;
  Result.Behind := -1;
  Result.Ahead := -1;
  Dir := IncludeTrailingPathDelimiter(ARoot) + SetDirSeparators(ASub.Path);
  Result.Initialized := FileExists(IncludeTrailingPathDelimiter(Dir) + '.git') or
    DirectoryExists(IncludeTrailingPathDelimiter(Dir) + '.git');
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
  if not RunGitIn(Dir, ['rev-list', '--left-right', '--count',
    ASub.Recorded + '...' + Result.Tip], Output, Err) then
    Exit;
  Output := Trim(Output);
  Tab := Pos(#9, Output);
  if (Tab = 0) or not TryStrToInt(Copy(Output, 1, Tab - 1), Result.Ahead) or
    not TryStrToInt(Copy(Output, Tab + 1, MaxInt), Result.Behind) then
  begin
    Result.Ahead := -1;
    Result.Behind := -1;
    Exit;
  end;
  if (Result.Behind > 0) and (Result.Ahead > 0) then
    Result.State := smDiverged
  else if Result.Behind > 0 then
    Result.State := smBehind
  else
    Result.State := smAhead;
  if (Result.Behind > 0) and RunGitIn(Dir, ['log', '--no-color', '-n',
    IntToStr(MaxIncoming), SubmoduleLogFormat, ASub.Recorded + '..' + Result.Tip, '--'],
    Output, Err) then
    ParseSubmoduleLog(Output, Result.Incoming);
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
  if not Terminated then
    Queue(@Notify);
end;

procedure TGittanSubmoduleJob.Notify;
begin
  if Assigned(FOnDone) and not Terminated then
    FOnDone(Self);
end;

procedure TGittanSubmoduleJob.Stop(AWait: boolean);
begin
  FOnDone := nil;
  Terminate;
  if AWait then
    WaitFor;
end;

end.
