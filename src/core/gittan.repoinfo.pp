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
  Classes, SysUtils, gittan.git, gittan.job;

type
  {** A remote: its name, the URL it fetches from, the one it pushes to
    (the same unless a push URL is set), and the fetch URL as a web
    address when it is one of a hosting site (Web is '' otherwise). }
  TGittanRemote = record
    Name, Url, PushUrl, Web: string;
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

  {** What a file is for, by its path: a test (under a folder named test
    or tests, or named *.test.*), configuration (a package manager's
    manifest or lock file such as package.json or composer.lock, a
    .json, .yaml, .toml, .ini or similar file, a dotfile such as
    .gitignore, or anything under a forge's folder such as .github), documentation (.md or .txt) or code, which is
    everything else. }
  TGittanFileCategory = (fcCode, fcTest, fcDocs, fcConfig);

  {** How many files of a category, and how many lines they have. }
  TGittanCategoryCount = record
    Files: integer;
    Lines: int64;
  end;

  {** The files and lines of a repository, or of a change, per category. }
  TGittanComposition = array[TGittanFileCategory] of TGittanCategoryCount;

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
    {** The tracked files and their lines per category; a binary file
      counts as a file with no lines. }
    Composition: TGittanComposition;
  end;

{** The remotes from `git remote -v`: one per name, with its fetch URL
  and its push URL, the first of each when there are more. }
function ParseRemotes(const AOutput: string): TGittanRemotes;

{** The remotes of the repository at ARoot, read by ParseRemotes; false,
  with git's message in AError, when git failed. }
function ReadRemotes(const ARoot: string; out ARemotes: TGittanRemotes;
  out AError: string): boolean;

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

{** The category of the file at APath, relative to the root with
  forward slashes. }
function FileCategory(const APath: string): TGittanFileCategory;

{** The name of ACategory as a list shows it: "Code files". }
function CategoryName(ACategory: TGittanFileCategory): string;

{** The composition of the files AFiles names (`git ls-files -z`) with
  their lines from ALineCounts (`git grep -I -c -z -e ^`: a path, a
  NUL and the count, a line each); a file without a count has no lines. }
function ParseComposition(const AFiles, ALineCounts: string): TGittanComposition;

{** The lines of the tracked files as they are in the working tree, in
  the form ParseComposition reads, from those of the commit AHead
  (`git grep -I -c -z -e ^ <AHead>`, each path after "<AHead>:") and
  what changed since (`git diff <AHead> --numstat --no-renames -z`): a
  file's lines with those added and less those removed. A file binary
  on either side counts as one with no lines, and goes in ARecount
  when given, for RecountLines: it may be text now. }
function AdjustLineCounts(const AHead, AHeadCounts, ANumstat: string;
  ARecount: TStrings = nil): string;
{** Adds to AInto the files `git ls-files -v -z` marks assume-unchanged
  (a lowercase tag) or skip-worktree (S), which git diff passes over. }
procedure ParseFlaggedFiles(const AOutput: string; AInto: TStrings);
{** ACounts (as AdjustLineCounts gives them) with the lines of APaths
  counted in the working tree under ARoot, as git grep -I counts them:
  none for a binary file (a NUL in its first 8000 bytes) or one that is
  gone. }
function RecountLines(const ACounts, ARoot: string; APaths: TStrings): string;

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
  TGittanRepoInfoJob = class(TGittanJob)
  private
    FRoot: string;
    FMaxContributors, FMaxTags: integer;
    FInfo: TGittanRepoInfo;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: string; AMaxContributors, AMaxTags: integer);
    destructor Destroy; override;
    property Info: TGittanRepoInfo read FInfo;
    property Root: string read FRoot;
  end;

implementation

uses
  StrUtils, DateUtils, Math, gittan.textfile;

resourcestring
  rsCodeFiles = 'Code files';
  rsTestFiles = 'Test files';
  rsDocumentation = 'Documentation';
  rsConfiguration = 'Configuration';

function ParseRemotes(const AOutput: string): TGittanRemotes;
var
  Lines: TStringList;
  Line, Name, Url: string;
  Tab, Space, i, At: integer;
  Push: boolean;
begin
  Result := nil;
  Lines := TStringList.Create;
  try
    Lines.Text := AOutput;
    for Line in Lines do
    begin
      { "origin<tab>https://... (fetch)", then the same with (push) }
      Tab := Pos(#9, Line);
      if Tab <= 1 then
        Continue;
      Name := Copy(Line, 1, Tab - 1);
      Url := Copy(Line, Tab + 1, MaxInt);
      Space := RPos(' ', Url);
      Push := (Space > 0) and (Copy(Url, Space + 1, MaxInt) = '(push)');
      if Space > 0 then
        Url := Copy(Url, 1, Space - 1);
      At := -1;
      for i := 0 to High(Result) do
        if Result[i].Name = Name then
          At := i;
      if At < 0 then
      begin
        SetLength(Result, Length(Result) + 1);
        At := High(Result);
        Result[At].Name := Name;
      end;
      if Push then
      begin
        if Result[At].PushUrl = '' then
          Result[At].PushUrl := Url;
      end
      else if Result[At].Url = '' then
      begin
        Result[At].Url := Url;
        Result[At].Web := RemoteWebUrl(Url);
      end;
    end;
  finally
    Lines.Free;
  end;
end;

function ReadRemotes(const ARoot: string; out ARemotes: TGittanRemotes;
  out AError: string): boolean;
var
  Output: string;
begin
  ARemotes := nil;
  Result := RunGitIn(ARoot, ['remote', '-v'], Output, AError);
  if Result then
    ARemotes := ParseRemotes(Output);
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

const
  { The manifests and lock files of package managers and build tools
    that no extension in ConfigExts gives away, lower case. }
  ConfigNames: array[0..17] of string = ('gemfile', 'go.mod', 'go.sum', 'go.work',
    'pipfile', 'requirements.txt', 'podfile', 'cartfile', 'brewfile', 'procfile',
    'package.swift', 'build.gradle', 'settings.gradle', 'build.gradle.kts',
    'settings.gradle.kts', 'makefile', 'gnumakefile', 'cmakelists.txt');
  { The folders at the top of a repository that a forge or a CI service
    reads, whose files are all configuration: workflows, templates and
    the scripts they run. }
  ConfigFolders: array[0..4] of string = ('.github', '.gitlab', '.gitea', '.forgejo',
    '.circleci');
  ConfigExts: array[0..12] of string = ('.json', '.jsonc', '.json5', '.yaml', '.yml',
    '.toml', '.ini', '.cfg', '.conf', '.lock', '.properties', '.plist', '.editorconfig');

function FileCategory(const APath: string): TGittanFileCategory;
var
  Parts: TStringArray;
  Name, Ext: string;
  i: integer;
begin
  Parts := LowerCase(APath).Split(['/']);
  if Length(Parts) = 0 then
    Exit(fcCode);
  if (Length(Parts) > 1) and MatchStr(Parts[0], ConfigFolders) then
    Exit(fcConfig);
  for i := 0 to High(Parts) - 1 do
    if (Parts[i] = 'test') or (Parts[i] = 'tests') then
      Exit(fcTest);
  Name := Parts[High(Parts)];
  if Pos('.test.', Name) > 0 then
    Exit(fcTest);
  { By name first, so requirements.txt is not documentation; a dotfile
    is one with no dot after its first. }
  if MatchStr(Name, ConfigNames) or ((Name <> '') and (Name[1] = '.') and
    (Pos('.', Name, 2) = 0)) then
    Exit(fcConfig);
  Ext := ExtractFileExt(Name);
  if MatchStr(Ext, ConfigExts) then
    Exit(fcConfig);
  if (Ext = '.md') or (Ext = '.txt') then
    Exit(fcDocs);
  Result := fcCode;
end;

function CategoryName(ACategory: TGittanFileCategory): string;
begin
  case ACategory of
    fcTest: Result := rsTestFiles;
    fcDocs: Result := rsDocumentation;
    fcConfig: Result := rsConfiguration;
    else
      Result := rsCodeFiles;
  end;
end;

function ParseComposition(const AFiles, ALineCounts: string): TGittanComposition;
var
  Path: string;
  P, Nul, Lf: integer;
  Count: int64;
begin
  Result := Default(TGittanComposition);
  for Path in AFiles.Split([#0]) do
    if Path <> '' then
      Inc(Result[FileCategory(Path)].Files);
  { A record is the name up to its NUL and the count up to the line end
    after it, read from the NUL since a name may hold a line feed. }
  P := 1;
  while P <= Length(ALineCounts) do
  begin
    Nul := Pos(#0, ALineCounts, P);
    if Nul = 0 then
      Break;
    Lf := Pos(#10, ALineCounts, Nul);
    if Lf = 0 then
      Lf := Length(ALineCounts) + 1;
    if (Nul > P) and TryStrToInt64(Trim(Copy(ALineCounts, Nul + 1, Lf - Nul - 1)), Count) then
      Inc(Result[FileCategory(Copy(ALineCounts, P, Nul - P))].Lines, Count);
    P := Lf + 1;
  end;
end;

{ The paths of `git grep -c -z` output with their counts, sorted, each
  count in the item's object. APrefix comes off every path. }
procedure ReadLineCounts(const AOutput, APrefix: string; ACounts: TStringList);
var
  P, Nul, Lf: integer;
  Path: string;
  Count: int64;
begin
  P := 1;
  while P <= Length(AOutput) do
  begin
    Nul := Pos(#0, AOutput, P);
    if Nul = 0 then
      Break;
    Lf := Pos(#10, AOutput, Nul);
    if Lf = 0 then
      Lf := Length(AOutput) + 1;
    Path := Copy(AOutput, P, Nul - P);
    if AnsiStartsStr(APrefix, Path) then
      Delete(Path, 1, Length(APrefix));
    if (Path <> '') and TryStrToInt64(Trim(Copy(AOutput, Nul + 1, Lf - Nul - 1)), Count) then
      ACounts.AddObject(Path, TObject(PtrInt(Count)));
    P := Lf + 1;
  end;
end;

{ The counts in the form ParseComposition reads. }
function WriteLineCounts(ACounts: TStringList): string;
var
  Sb: TStringBuilder;
  i: integer;
begin
  Sb := TStringBuilder.Create;
  try
    for i := 0 to ACounts.Count - 1 do
    begin
      Sb.Append(ACounts[i]);
      Sb.Append(#0);
      Sb.Append(IntToStr(PtrInt(ACounts.Objects[i])));
      Sb.Append(#10);
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function NewCountList: TStringList;
begin
  Result := TStringList.Create;
  Result.CaseSensitive := True;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
end;

function AdjustLineCounts(const AHead, AHeadCounts, ANumstat: string;
  ARecount: TStrings): string;
var
  Counts: TStringList;
  P, Nul, Tab1, Tab2, i: integer;
  Path: string;
  Added, Removed, Count: int64;
  Binary: boolean;
begin
  Counts := NewCountList;
  try
    ReadLineCounts(AHeadCounts, AHead + ':', Counts);
    { A record is "<added>\t<removed>\t<path>" up to its NUL. }
    P := 1;
    while P <= Length(ANumstat) do
    begin
      Nul := Pos(#0, ANumstat, P);
      if Nul = 0 then
        Nul := Length(ANumstat) + 1;
      Tab1 := Pos(#9, ANumstat, P);
      Tab2 := 0;
      if (Tab1 > 0) and (Tab1 < Nul) then
        Tab2 := Pos(#9, ANumstat, Tab1 + 1);
      if (Tab2 > 0) and (Tab2 < Nul) then
      begin
        Path := Copy(ANumstat, Tab2 + 1, Nul - Tab2 - 1);
        Binary := not TryStrToInt64(Trim(Copy(ANumstat, P, Tab1 - P)), Added) or
          not TryStrToInt64(Copy(ANumstat, Tab1 + 1, Tab2 - Tab1 - 1), Removed);
        if Path <> '' then
        begin
          Count := 0;
          if Counts.Find(Path, i) then
          begin
            Count := PtrInt(Counts.Objects[i]);
            Counts.Delete(i);
          end;
          if not Binary then
          begin
            Count := Count + Added - Removed;
            if Count > 0 then
              Counts.AddObject(Path, TObject(PtrInt(Count)));
          end
          else if ARecount <> nil then
            ARecount.Add(Path);
        end;
      end;
      P := Nul + 1;
    end;
    Result := WriteLineCounts(Counts);
  finally
    Counts.Free;
  end;
end;

procedure ParseFlaggedFiles(const AOutput: string; AInto: TStrings);
var
  P, Nul: integer;
begin
  P := 1;
  while P <= Length(AOutput) do
  begin
    Nul := Pos(#0, AOutput, P);
    if Nul = 0 then
      Nul := Length(AOutput) + 1;
    if (Nul - P > 2) and (AOutput[P + 1] = ' ') and
      ((AOutput[P] in ['a'..'z']) or (AOutput[P] = 'S')) then
      AInto.Add(Copy(AOutput, P + 2, Nul - P - 2));
    P := Nul + 1;
  end;
end;

function RecountLines(const ACounts, ARoot: string; APaths: TStrings): string;
var
  Counts: TStringList;
  Data: RawByteString;
  FileName: string;
  i, j: integer;
  Count: int64;
begin
  Counts := NewCountList;
  try
    ReadLineCounts(ACounts, '', Counts);
    for i := 0 to APaths.Count - 1 do
    begin
      if Counts.Find(APaths[i], j) then
        Counts.Delete(j);
      FileName := IncludeTrailingPathDelimiter(ARoot) + SetDirSeparators(APaths[i]);
      if not FileExists(FileName) then
        Continue;
      try
        Data := ReadFileBytes(FileName);
      except
        Continue;
      end;
      if Pos(#0, Copy(Data, 1, 8000)) > 0 then
        Continue;
      Count := 0;
      for j := 1 to Length(Data) do
        if Data[j] = #10 then
          Inc(Count);
      if (Data <> '') and (Data[Length(Data)] <> #10) then
        Inc(Count);
      if Count > 0 then
        Counts.AddObject(APaths[i], TObject(PtrInt(Count)));
    end;
    Result := WriteLineCounts(Counts);
  finally
    Counts.Free;
  end;
end;

type
  { The lines of a commit's text files, per root, so that only a new
    commit has every file read again. }
  THeadLines = record
    Root, Head, Counts: string;
  end;

const
  { The repositories whose counts are kept. }
  HeadLinesKept = 8;

var
  HeadLinesCache: array of THeadLines;
  HeadLinesLock: TRTLCriticalSection;

{ The `git grep -c` output of the commit AHead at ARoot, from the cache
  or read and kept. False when git could not read it. }
function HeadLineCounts(const ARoot, AHead: string; out ACounts: string): boolean;
var
  i: integer;
  Err: string;
  Entry: THeadLines;
begin
  EnterCriticalSection(HeadLinesLock);
  try
    for i := 0 to High(HeadLinesCache) do
      if (HeadLinesCache[i].Root = ARoot) and (HeadLinesCache[i].Head = AHead) then
      begin
        ACounts := HeadLinesCache[i].Counts;
        Exit(True);
      end;
  finally
    LeaveCriticalSection(HeadLinesLock);
  end;
  { git grep fails when no file matches, a commit of no text file;
    that is not kept, as it is no failure to tell from one. }
  if not RunGitIn(ARoot, ['grep', '-I', '-c', '-z', '--no-color', '-e', '^', AHead],
    ACounts, Err) then
  begin
    ACounts := '';
    Exit(Err = '');
  end;
  Entry.Root := ARoot;
  Entry.Head := AHead;
  Entry.Counts := ACounts;
  EnterCriticalSection(HeadLinesLock);
  try
    { The root's older commit goes; the oldest root when full. }
    for i := High(HeadLinesCache) downto 0 do
      if HeadLinesCache[i].Root = ARoot then
        Delete(HeadLinesCache, i, 1);
    if Length(HeadLinesCache) >= HeadLinesKept then
      Delete(HeadLinesCache, 0, 1);
    Insert(Entry, HeadLinesCache, Length(HeadLinesCache));
  finally
    LeaveCriticalSection(HeadLinesLock);
  end;
  Result := True;
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
  Output, Err, Line, Counts, Head, HeadCounts, Numstat, Flags: string;
  Cat: TGittanFileCategory;
  Seconds: int64;
  Lines, Recount: TStringList;

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
  if Run(['ls-files', '-z']) then
  begin
    { Every line of every tracked text file as it is in the working
      tree: the commit's, read once per commit, and the changes since,
      so that only the changed files are read each time. Without a
      commit every file is read; git grep fails when there is none,
      which is no failure. }
    Head := '';
    if (Info.Commits > 0) and RunGitIn(ARoot, ['rev-parse', '-q', '--verify', 'HEAD^{commit}'],
      Head, Err) then
      Head := Trim(Head);
    if (Head <> '') and HeadLineCounts(ARoot, Head, HeadCounts) and
      RunGitIn(ARoot, ['diff', Head, '--numstat', '--no-renames', '--no-ext-diff', '-z'],
      Numstat, Err) then
    begin
      { A file binary in the commit may be text now, and git diff says
        nothing of a file it is told to take as unchanged: both are
        read from the disk. }
      Recount := TStringList.Create;
      try
        Counts := AdjustLineCounts(Head, HeadCounts, Numstat, Recount);
        if RunGitIn(ARoot, ['ls-files', '-v', '-z'], Flags, Err) then
          ParseFlaggedFiles(Flags, Recount);
        if Recount.Count > 0 then
          Counts := RecountLines(Counts, ARoot, Recount);
      finally
        Recount.Free;
      end;
    end
    else if not RunGitIn(ARoot, ['grep', '-I', '-c', '-z', '--no-color', '-e', '^'], Counts, Err) then
      Counts := '';
    Info.Composition := ParseComposition(Output, Counts);
    for Cat := Low(Cat) to High(Cat) do
      Inc(Info.Files, Info.Composition[Cat].Files);
  end;
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
  inherited Destroy;
end;

procedure TGittanRepoInfoJob.Execute;
begin
  FInfo := GatherRepoInfo(FRoot, FMaxContributors, FMaxTags);
  Done;
end;

initialization
  InitCriticalSection(HeadLinesLock);

finalization
  DoneCriticalSection(HeadLinesLock);

end.
