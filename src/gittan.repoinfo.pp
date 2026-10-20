unit gittan.repoinfo;

{** What the Repository page tells about a repository: its remotes, how
  many commits, branches, tags and tracked files it has, when the first
  and the latest commit were made, who made the commits and how much
  room its objects take. GatherRepoInfo asks git for all of it in one
  pass, and TGittanRepoInfoJob runs that pass off the main thread, as a
  shortlog of a large repository takes a moment. The parsing of what
  git prints is on its own, so it can be tested without a repository. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.git;

type
  {** A remote: its name, the URL it fetches from, and the same as a web
    address when the URL is one of a hosting site (Web is '' otherwise). }
  TGittanRemote = record
    Name, Url, Web: string;
  end;
  TGittanRemotes = array of TGittanRemote;

  {** An author and the number of commits in their name. }
  TGittanContributor = record
    Name: string;
    Commits: integer;
  end;
  TGittanContributors = array of TGittanContributor;

  {** A tag and when it was made. }
  TGittanTagInfo = record
    Name: string;
    Date: TDateTime;
  end;
  TGittanTagInfos = array of TGittanTagInfo;

  {** The facts of a repository. Ok is false when git failed, with the
    message in Error; what was read before the failure is kept. The
    dates are universal time. }
  TGittanRepoInfo = record
    Ok: boolean;
    Error: string;
    Branch, Upstream: string;
    Commits, LocalBranches, RemoteBranches, Tags, Files, Submodules, Authors: integer;
    FirstCommit, LastCommit: TDateTime;
    {** The size of the objects, loose and packed, in KiB. }
    SizeKiB: int64;
    Remotes: TGittanRemotes;
    {** The authors with the most commits, at most the number asked for. }
    Contributors: TGittanContributors;
    {** The newest tags, at most the number asked for. }
    NewestTags: TGittanTagInfos;
  end;

{** The remotes from `git remote -v`: one per name, with its fetch URL. }
function ParseRemotes(const AOutput: string): TGittanRemotes;

{** The web address of a remote URL: an https URL of a hosting site
  without its .git, the same for an scp-like (git@host:owner/name.git)
  or ssh:// URL; '' for a local path or anything else. }
function RemoteWebUrl(const AUrl: string): string;

{** The authors from `git shortlog -sn`, most commits first, the first
  AMax of them; ATotal is how many there were. Names that differ only in
  how their letters are composed (an ö as one code point or as an o with
  a combining mark, which git keeps apart) or in case are one author, with
  the name of the one with more commits. }
function ParseShortlog(const AOutput: string; AMax: integer;
  out ATotal: integer): TGittanContributors;

{** AName as it compares: lowercase, combining marks dropped, and the
  accented Latin letters reduced to their base letter, so the two forms
  of "Björn" meet. }
function NameKey(const AName: string): string;

{** The size in KiB from `git count-objects -v`: size plus size-pack. }
function ParseCountObjects(const AOutput: string): int64;

{** The tags from `for-each-ref` lines of a name, a tab and a unix time. }
function ParseTags(const AOutput: string): TGittanTagInfos;

{** The number of non-empty lines. }
function CountLines(const AOutput: string): integer;

{** A count with its thousands grouped by a thin space: 1 234 567. }
function GroupDigits(AValue: int64): string;

{** AKiB as git's count-objects -H prints it: "312.00 KiB", "4.21 MiB",
  "1.02 GiB", with the fraction dropped when it is zero. }
function FormatKiB(AKiB: int64): string;

{** Reads the facts of the repository at ARoot, with at most
  AMaxContributors authors and AMaxTags tags. }
function GatherRepoInfo(const ARoot: string; AMaxContributors, AMaxTags: integer): TGittanRepoInfo;

type

  { TGittanRepoInfoJob }

  {** GatherRepoInfo on a thread, with OnDone raised in the main thread
    once the facts are in. }
  TGittanRepoInfoJob = class(TThread)
  private
    FRoot: string;
    FMaxContributors, FMaxTags: integer;
    FInfo: TGittanRepoInfo;
    FOnDone: TNotifyEvent;
    procedure Notify;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: string; AMaxContributors, AMaxTags: integer);
    destructor Destroy; override;
    {** Drops the handler and ends the thread; a result still on its way
      is thrown away. Waits for a running git only when AWait is set. }
    procedure Stop(AWait: boolean);
    property Info: TGittanRepoInfo read FInfo;
    property Root: string read FRoot;
    {** Called in the main thread when git is done. }
    property OnDone: TNotifyEvent read FOnDone write FOnDone;
  end;

implementation

uses
  StrUtils, DateUtils, Math;

function ParseRemotes(const AOutput: string): TGittanRemotes;
var
  Lines: TStringList;
  Line, Name, Url: string;
  Tab, Space, i: integer;
  Seen: boolean;
begin
  Result := nil;
  Lines := TStringList.Create;
  try
    Lines.Text := AOutput;
    for Line in Lines do
    begin
      { "origin<tab>https://... (fetch)" }
      Tab := Pos(#9, Line);
      if Tab = 0 then
        Continue;
      Name := Copy(Line, 1, Tab - 1);
      Url := Copy(Line, Tab + 1, MaxInt);
      Space := RPos(' ', Url);
      if (Space > 0) and (Copy(Url, Space + 1, MaxInt) = '(push)') then
        Continue;
      if Space > 0 then
        Url := Copy(Url, 1, Space - 1);
      Seen := False;
      for i := 0 to High(Result) do
        Seen := Seen or (Result[i].Name = Name);
      if Seen or (Name = '') then
        Continue;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].Name := Name;
      Result[High(Result)].Url := Url;
      Result[High(Result)].Web := RemoteWebUrl(Url);
    end;
  finally
    Lines.Free;
  end;
end;

function RemoteWebUrl(const AUrl: string): string;
var
  Rest, Host, Path: string;
  Colon, Slash, At: integer;
begin
  Result := '';
  if (Pos('https://', AUrl) = 1) or (Pos('http://', AUrl) = 1) then
    Result := AUrl
  else if Pos('ssh://', AUrl) = 1 then
  begin
    { ssh://git@host[:port]/owner/name.git }
    Rest := Copy(AUrl, 7, MaxInt);
    At := Pos('@', Rest);
    if At > 0 then
      Delete(Rest, 1, At);
    Slash := Pos('/', Rest);
    if Slash = 0 then
      Exit;
    Host := Copy(Rest, 1, Slash - 1);
    Colon := Pos(':', Host);
    if Colon > 0 then
      Host := Copy(Host, 1, Colon - 1);
    Path := Copy(Rest, Slash, MaxInt);
    Result := 'https://' + Host + Path;
  end
  else
  begin
    { git@host:owner/name.git; a path has no colon before its first
      slash, and a Windows drive is one letter. }
    Colon := Pos(':', AUrl);
    Slash := Pos('/', AUrl);
    if (Colon < 2) or ((Slash > 0) and (Slash < Colon)) or (Pos('\', AUrl) > 0) then
      Exit;
    Host := Copy(AUrl, 1, Colon - 1);
    At := Pos('@', Host);
    if At > 0 then
      Host := Copy(Host, At + 1, MaxInt);
    if (Host = '') or (Pos('.', Host) = 0) then
      Exit;
    Path := Copy(AUrl, Colon + 1, MaxInt);
    if Path = '' then
      Exit;
    if Path[1] <> '/' then
      Path := '/' + Path;
    Result := 'https://' + Host + Path;
  end;
  if Result = '' then
    Exit;
  if Copy(Result, Length(Result), 1) = '/' then
    Delete(Result, Length(Result), 1);
  if (Length(Result) > 4) and (Copy(Result, Length(Result) - 3, 4) = '.git') then
    Delete(Result, Length(Result) - 3, 4);
  { An address with user info (user@ or user:token@) is not for a browser. }
  Rest := Copy(Result, 9, MaxInt);
  Slash := Pos('/', Rest);
  if Slash = 0 then
    Slash := Length(Rest) + 1;
  At := Pos('@', Copy(Rest, 1, Slash - 1));
  if At > 0 then
    Result := 'https://' + Copy(Rest, At + 1, MaxInt);
end;

{ The base letter of a precomposed Latin letter U+00C0..U+017F, or '' for
  a code point that is none: the Latin-1 Supplement letters and Latin
  Extended-A, two code points per base letter (upper, lower) mostly. }
function BaseLetter(ACode: cardinal): string;
const
  Latin1: string = 'AAAAAAACEEEEIIIIDNOOOOO' + '*' + 'OUUUUYTsaaaaaaaceeeeiiiidnooooo' + '*' + 'ouuuuyty';
  ExtA: string = 'AaAaAaCcCcCcCcDdDdEeEeEeEeEeGgGgGgGgHhHhIiIiIiIiIiJjJjKkkLlLlLlLlLlNnNnNnnNnOoOoOoOoRrRrRrSsSsSsSsTtTtTtUuUuUuUuUuUuWwYyYZzZzZzs';
begin
  Result := '';
  if (ACode >= $C0) and (ACode <= $FF) and (ACode - $C0 < Length(Latin1)) then
    Result := Latin1[ACode - $C0 + 1]
  else if (ACode >= $100) and (ACode <= $17F) and (ACode - $100 < Length(ExtA)) then
    Result := ExtA[ACode - $100 + 1];
  if Result = '*' then
    Result := '';
end;

function NameKey(const AName: string): string;
var
  i, Len, k: integer;
  Code: cardinal;
  Base: string;
begin
  Result := '';
  i := 1;
  while i <= Length(AName) do
  begin
    { The code point and its length, by hand: the names are UTF-8. }
    Code := Ord(AName[i]);
    Len := 1;
    if (Code and $E0) = $C0 then
    begin
      Len := 2;
      Code := Code and $1F;
    end
    else if (Code and $F0) = $E0 then
    begin
      Len := 3;
      Code := Code and $0F;
    end
    else if (Code and $F8) = $F0 then
    begin
      Len := 4;
      Code := Code and $07;
    end;
    if i + Len - 1 > Length(AName) then
      Break;
    for k := 1 to Len - 1 do
      Code := (Code shl 6) or (Ord(AName[i + k]) and $3F);
    { A combining mark is dropped. }
    if (Code < $300) or (Code > $36F) then
    begin
      Base := BaseLetter(Code);
      if Base <> '' then
        Result := Result + LowerCase(Base)
      else if Code < $80 then
        Result := Result + LowerCase(Chr(Code))
      else
        Result := Result + Copy(AName, i, Len);
    end;
    Inc(i, Len);
  end;
end;

function ParseShortlog(const AOutput: string; AMax: integer;
  out ATotal: integer): TGittanContributors;
var
  Lines: TStringList;
  Line, Name, Key: string;
  Tab, Count, i, j: integer;
  Keys: TStringList;
  All: TGittanContributors;
  Swap: TGittanContributor;
begin
  Result := nil;
  ATotal := 0;
  All := nil;
  Lines := TStringList.Create;
  Keys := TStringList.Create;
  try
    Lines.Text := AOutput;
    for Line in Lines do
    begin
      { "   123<tab>Name" }
      Tab := Pos(#9, Line);
      if Tab = 0 then
        Continue;
      if not TryStrToInt(Trim(Copy(Line, 1, Tab - 1)), Count) then
        Continue;
      Name := Trim(Copy(Line, Tab + 1, MaxInt));
      if Name = '' then
        Continue;
      Key := NameKey(Name);
      i := Keys.IndexOf(Key);
      if i >= 0 then
      begin
        { The same author under another spelling: the counts add up,
          and the name with more commits stands. }
        if Count > All[i].Commits then
          All[i].Name := Name;
        Inc(All[i].Commits, Count);
        Continue;
      end;
      Keys.Add(Key);
      SetLength(All, Length(All) + 1);
      All[High(All)].Name := Name;
      All[High(All)].Commits := Count;
    end;
  finally
    Keys.Free;
    Lines.Free;
  end;
  { Most commits first again, since a merge may have moved one up; the
    order git gave is kept among equals. }
  for i := 1 to High(All) do
  begin
    Swap := All[i];
    j := i;
    while (j > 0) and (All[j - 1].Commits < Swap.Commits) do
    begin
      All[j] := All[j - 1];
      Dec(j);
    end;
    All[j] := Swap;
  end;
  ATotal := Length(All);
  if Length(All) > AMax then
    SetLength(All, Max(0, AMax));
  Result := All;
end;

function ParseCountObjects(const AOutput: string): int64;
var
  Lines: TStringList;
  Line: string;
  Value: int64;
begin
  Result := 0;
  Lines := TStringList.Create;
  try
    Lines.Text := AOutput;
    for Line in Lines do
      if (Pos('size: ', Line) = 1) or (Pos('size-pack: ', Line) = 1) then
        if TryStrToInt64(Trim(Copy(Line, Pos(':', Line) + 1, MaxInt)), Value) then
          Inc(Result, Value);
  finally
    Lines.Free;
  end;
end;

function ParseTags(const AOutput: string): TGittanTagInfos;
var
  Lines: TStringList;
  Line: string;
  Tab: integer;
  Seconds: int64;
begin
  Result := nil;
  Lines := TStringList.Create;
  try
    Lines.Text := AOutput;
    for Line in Lines do
    begin
      Tab := Pos(#9, Line);
      if Tab < 2 then
        Continue;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].Name := Copy(Line, 1, Tab - 1);
      if TryStrToInt64(Trim(Copy(Line, Tab + 1, MaxInt)), Seconds) then
        Result[High(Result)].Date := UnixToDateTime(Seconds)
      else
        Result[High(Result)].Date := 0;
    end;
  finally
    Lines.Free;
  end;
end;

function CountLines(const AOutput: string): integer;
var
  Lines: TStringList;
  Line: string;
begin
  Result := 0;
  Lines := TStringList.Create;
  try
    Lines.Text := AOutput;
    for Line in Lines do
      if Trim(Line) <> '' then
        Inc(Result);
  finally
    Lines.Free;
  end;
end;

function GroupDigits(AValue: int64): string;
var
  Digits: string;
  i: integer;
begin
  Digits := IntToStr(Abs(AValue));
  Result := '';
  for i := 1 to Length(Digits) do
  begin
    if (i > 1) and ((Length(Digits) - i + 1) mod 3 = 0) then
      Result := Result + #$E2#$80#$89;
    Result := Result + Digits[i];
  end;
  if AValue < 0 then
    Result := '-' + Result;
end;

function FormatKiB(AKiB: int64): string;
const
  Units: array[0..2] of string = ('KiB', 'MiB', 'GiB');
var
  Value: double;
  i: integer;
  Settings: TFormatSettings;
begin
  Value := AKiB;
  i := 0;
  while (Value >= 1024) and (i < High(Units)) do
  begin
    Value := Value / 1024;
    Inc(i);
  end;
  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := '.';
  if (i = 0) or (Frac(Value) = 0) then
    Result := IntToStr(Trunc(Value)) + ' ' + Units[i]
  else
    Result := FormatFloat('0.00', Value, Settings) + ' ' + Units[i];
end;

function GatherRepoInfo(const ARoot: string; AMaxContributors, AMaxTags: integer): TGittanRepoInfo;
var
  Info: TGittanRepoInfo;
  Repo: TGittanRepo;
  Output, Err, Line: string;
  Seconds: int64;
  Lines: TStringList;

  { Runs git at the root; a failure is kept as the error, the first one. }
  function Run(const AArgs: array of string): boolean;
  begin
    Result := RunGitIn(ARoot, AArgs, Output, Err);
    if not Result and Info.Ok then
    begin
      Info.Ok := False;
      Info.Error := Err;
    end;
  end;

begin
  Info := Default(TGittanRepoInfo);
  Info.Ok := True;
  Repo := TGittanRepo.Create;
  try
    if not Repo.Open(ARoot) then
    begin
      Info.Ok := False;
      Info.Error := Repo.Error;
      Exit(Info);
    end;
    Info.Branch := Repo.Branch;
    if Info.Branch <> '' then
      Info.Upstream := Repo.Upstream(Info.Branch);
  finally
    Repo.Free;
  end;
  if Run(['remote', '-v']) then
    Info.Remotes := ParseRemotes(Output);
  { A repository without a commit yet has no HEAD to count; that is no
    failure. }
  if RunGitIn(ARoot, ['rev-list', '--count', 'HEAD'], Output, Err) then
    Info.Commits := StrToIntDef(Trim(Output), 0);
  if Info.Commits > 0 then
  begin
    { The root commits, oldest first; the first one's time. }
    if Run(['log', '--max-parents=0', '--format=%ct', '--reverse', 'HEAD']) then
    begin
      Lines := TStringList.Create;
      try
        Lines.Text := Output;
        if (Lines.Count > 0) and TryStrToInt64(Trim(Lines[0]), Seconds) then
          Info.FirstCommit := UnixToDateTime(Seconds);
      finally
        Lines.Free;
      end;
    end;
    if Run(['log', '-1', '--format=%ct', 'HEAD']) then
      if TryStrToInt64(Trim(Output), Seconds) then
        Info.LastCommit := UnixToDateTime(Seconds);
    if Run(['shortlog', '-sn', 'HEAD']) then
      Info.Contributors := ParseShortlog(Output, AMaxContributors, Info.Authors);
  end;
  if Run(['for-each-ref', '--format=%(refname)', 'refs/heads']) then
    Info.LocalBranches := CountLines(Output);
  if Run(['for-each-ref', '--format=%(refname)', 'refs/remotes']) then
  begin
    { origin/HEAD is a pointer, not a branch. }
    Info.RemoteBranches := CountLines(Output);
    Lines := TStringList.Create;
    try
      Lines.Text := Output;
      for Line in Lines do
        if (Line <> '') and (Copy(Line, Length(Line) - 4, 5) = '/HEAD') then
          Dec(Info.RemoteBranches);
    finally
      Lines.Free;
    end;
  end;
  if Run(['for-each-ref', '--format=%(refname)', 'refs/tags']) then
    Info.Tags := CountLines(Output);
  if (Info.Tags > 0) and Run(['for-each-ref', '--sort=-creatordate',
    '--format=%(refname:short)%09%(creatordate:unix)', '--count=' + IntToStr(AMaxTags),
    'refs/tags']) then
    Info.NewestTags := ParseTags(Output);
  if Run(['ls-files']) then
    Info.Files := CountLines(Output);
  if FileExists(IncludeTrailingPathDelimiter(ARoot) + '.gitmodules') then
    if RunGitIn(ARoot, ['config', '--file', '.gitmodules', '--get-regexp',
      '^submodule\..*\.path$'], Output, Err) then
      Info.Submodules := CountLines(Output);
  if Run(['count-objects', '-v']) then
    Info.SizeKiB := ParseCountObjects(Output);
  Result := Info;
end;

{ TGittanRepoInfoJob }

constructor TGittanRepoInfoJob.Create(const ARoot: string; AMaxContributors,
  AMaxTags: integer);
begin
  inherited Create(True);
  FRoot := ARoot;
  FMaxContributors := AMaxContributors;
  FMaxTags := AMaxTags;
end;

destructor TGittanRepoInfoJob.Destroy;
begin
  if not Finished then
    Stop(True);
  { Removes a Notify still waiting in the thread queue. }
  inherited Destroy;
end;

procedure TGittanRepoInfoJob.Execute;
begin
  FInfo := GatherRepoInfo(FRoot, FMaxContributors, FMaxTags);
  if not Terminated then
    Queue(@Notify);
end;

procedure TGittanRepoInfoJob.Notify;
begin
  if Assigned(FOnDone) and not Terminated then
    FOnDone(Self);
end;

procedure TGittanRepoInfoJob.Stop(AWait: boolean);
begin
  FOnDone := nil;
  Terminate;
  if AWait then
    WaitFor;
end;

end.
