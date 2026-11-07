unit gittan.repoconfig;

{** What a repository says of itself in .gittan/repo.toml, committed so
  it holds for everyone who clones it: the kinds of project it is
  (project = ["rust", "go"], as commands.toml's line, which it comes
  before), its issue tracker ([issues], for when git config names none
  with the bugtraq keys), how its commit messages are written ([commit]:
  the subject's limits, a template, sign-off by default, the types and
  scopes of Conventional Commits) and the branches not to commit on
  directly ([branches] protected). The file only describes: nothing in
  it runs, so it needs no trust, unlike the commands files
  (gittan.repocommands). Each value of another type than the one asked
  for is left out, as if it were not there. The TOML is read by toml-fp.
  No LCL; tested in tests/testrepoconfig.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.issuelinks;

const
  {** The file inside .gittan (gittan.repocommands' CommandsFolder). }
  RepoConfigFile = 'repo.toml';
  {** The file as a path relative to the root, with "/". }
  RepoConfigPath = '.gittan/' + RepoConfigFile;
  {** The subject's length past which its count shows. }
  DefaultSubjectSoft = 50;
  {** The subject's length past which the count warns: where git log
    --oneline and GitHub cut it. }
  DefaultSubjectHard = 72;
  {** The longest limit the file may set; a longer one is left out. }
  MaxSubjectLimit = 200;

type
  TGittanRepoConfig = record
    {** Whether the file is there; Error the TOML reader's message when
      it is not TOML, with every value then as if it were missing. }
    Exists: boolean;
    Error: string;
    {** project =, as ParseCommandsTomlProjects reads commands.toml's. }
    HasProjects: boolean;
    Projects: TStringArray;
    {** [issues] url, and regex with ids on a second line when given:
      bugtraq.url and bugtraq.logregex. Empty LogRegex for none. }
    Issues: TGittanIssueTracker;
    {** [commit] subject-limit and subject-max, DefaultSubjectSoft and
      DefaultSubjectHard when not set; never Soft > Hard. }
    SubjectSoft, SubjectHard: integer;
    {** [commit] template: a path from the root, for when git config
      names no commit.template; '' for none. }
    Template: string;
    {** [commit] sign-off: HasSignOff when set, SignOff what it says. }
    HasSignOff, SignOff: boolean;
    {** [commit] types and scopes: with types, a subject is to be
      written as type(scope)!: description (Conventional Commits). }
    Types, Scopes: TStringArray;
    {** [branches] protected: names, or patterns with * and ?. }
    Protected: TStringArray;
  end;

  {** What CheckSubject finds of a subject line: right, no type at its
    start, a type the file does not list, a scope it does not list. }
  TGittanSubjectCheck = (scOk, scNoType, scUnknownType, scUnknownScope);

{** The config of AText, a repo.toml. }
function ParseRepoConfig(const AText: string): TGittanRepoConfig;

{** The config of the repository at ARoot; Exists false, with the
  defaults, without a file. A file that cannot be read gives its error. }
function ReadRepoConfig(const ARoot: string): TGittanRepoConfig;

{** The config with nothing set: the defaults. }
function EmptyRepoConfig: TGittanRepoConfig;

{** Whether ASubject, a message's first line, is written as the
  config's types ask: type(scope)!: description, with the type among
  Types and the scope, when there is one and the config lists any,
  among Scopes, both in any case. scOk when the config lists no types,
  for an empty subject, and for the lines git and the tools write
  themselves (Merge, Revert, fixup!, squash!, amend!). ADetail is the
  type or scope that is not listed. }
function CheckSubject(const AConfig: TGittanRepoConfig; const ASubject: string;
  out ADetail: string): TGittanSubjectCheck;

{** Whether ABranch is one of the config's protected branches: its name,
  or a pattern where * stands for any characters and ? for one. }
function BranchProtected(const AConfig: TGittanRepoConfig; const ABranch: string): boolean;

{** AName matched against APattern: * any characters ("/" too), ? one. }
function GlobMatch(const APattern, AName: string): boolean;

{** What a new repo.toml holds: an example with its lines commented
  out. }
function RepoConfigTemplate: string;

implementation

uses
  TOML.Types, TOML.Parser, gittan.textfile;

function EmptyRepoConfig: TGittanRepoConfig;
begin
  Result := Default(TGittanRepoConfig);
  Result.SubjectSoft := DefaultSubjectSoft;
  Result.SubjectHard := DefaultSubjectHard;
end;

{ The strings of an array value, trimmed, the empty ones left out; a
  string is a list of one. }
function StringsOf(AValue: TTOMLValue): TStringArray;
var
  Item: TTOMLValue;
  S: string;
begin
  Result := nil;
  if AValue is TTOMLString then
  begin
    S := Trim(AValue.AsString);
    if S <> '' then
      Result := [S];
  end
  else if AValue is TTOMLArray then
    for Item in TTOMLArray(AValue).Items do
      if Item is TTOMLString then
      begin
        S := Trim(Item.AsString);
        if S <> '' then
        begin
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := S;
        end;
      end;
end;

{ The names of a project value, as commands.toml's: an array, or one
  string split on commas and spaces; "none" left out. }
function ProjectNames(AValue: TTOMLValue): TStringArray;
var
  Parts: TStringArray;
  S: string;
begin
  Result := nil;
  if AValue is TTOMLString then
    Parts := AValue.AsString.Split([',', ' '], TStringSplitOptions.ExcludeEmpty)
  else
    Parts := StringsOf(AValue);
  for S in Parts do
    if not SameText(S, 'none') then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := S;
    end;
end;

function TableOf(ADoc: TTOMLTable; const AName: string): TTOMLTable;
var
  Value: TTOMLValue;
begin
  if ADoc.TryGetValue(AName, Value) and (Value is TTOMLTable) then
    Result := TTOMLTable(Value)
  else
    Result := nil;
end;

function StringIn(ATable: TTOMLTable; const AName: string): string;
var
  Value: TTOMLValue;
begin
  if (ATable <> nil) and ATable.TryGetValue(AName, Value) and (Value is TTOMLString) then
    Result := Trim(Value.AsString)
  else
    Result := '';
end;

{ A limit of 1 to MaxSubjectLimit, else 0. }
function LimitIn(ATable: TTOMLTable; const AName: string): integer;
var
  Value: TTOMLValue;
begin
  Result := 0;
  if (ATable <> nil) and ATable.TryGetValue(AName, Value) and (Value is TTOMLInteger) and
    (Value.AsInteger >= 1) and (Value.AsInteger <= MaxSubjectLimit) then
    Result := Value.AsInteger;
end;

function ParseRepoConfig(const AText: string): TGittanRepoConfig;
var
  Doc, Table: TTOMLTable;
  Value: TTOMLValue;
  Ids: string;
  Soft, Hard: integer;
begin
  Result := EmptyRepoConfig;
  Result.Exists := True;
  try
    Doc := ParseTOMLString(AText);
  except
    on E: Exception do
    begin
      Result.Error := E.Message;
      Exit;
    end;
  end;
  try
    if Doc.TryGetValue('project', Value) and ((Value is TTOMLString) or (Value is TTOMLArray)) then
    begin
      Result.HasProjects := True;
      Result.Projects := ProjectNames(Value);
    end;

    Table := TableOf(Doc, 'issues');
    Result.Issues.Url := StringIn(Table, 'url');
    Result.Issues.LogRegex := StringIn(Table, 'regex');
    Ids := StringIn(Table, 'ids');
    if (Result.Issues.LogRegex <> '') and (Ids <> '') then
      Result.Issues.LogRegex := Result.Issues.LogRegex + #10 + Ids;

    Table := TableOf(Doc, 'commit');
    if Table <> nil then
    begin
      Soft := LimitIn(Table, 'subject-limit');
      Hard := LimitIn(Table, 'subject-max');
      if Hard > 0 then
        Result.SubjectHard := Hard;
      if Soft > 0 then
        Result.SubjectSoft := Soft;
      { A limit over the default maximum raises it; a maximum under the
        limit, its own or the default, pulls the limit down: a maximum
        the file sets holds. }
      if Result.SubjectSoft > Result.SubjectHard then
        if Hard = 0 then
          Result.SubjectHard := Result.SubjectSoft
        else
          Result.SubjectSoft := Result.SubjectHard;
      Result.Template := StringIn(Table, 'template');
      if Table.TryGetValue('sign-off', Value) and (Value is TTOMLBoolean) then
      begin
        Result.HasSignOff := True;
        Result.SignOff := Value.AsBoolean;
      end;
      if Table.TryGetValue('types', Value) then
        Result.Types := StringsOf(Value);
      if Table.TryGetValue('scopes', Value) then
        Result.Scopes := StringsOf(Value);
    end;

    Table := TableOf(Doc, 'branches');
    if (Table <> nil) and Table.TryGetValue('protected', Value) then
      Result.Protected := StringsOf(Value);
  finally
    Doc.Free;
  end;
end;

function ReadRepoConfig(const ARoot: string): TGittanRepoConfig;
var
  FileName: string;
begin
  Result := EmptyRepoConfig;
  if ARoot = '' then
    Exit;
  FileName := IncludeTrailingPathDelimiter(ARoot) + '.gittan' + PathDelim + RepoConfigFile;
  if not FileExists(FileName) then
    Exit;
  try
    Result := ParseRepoConfig(ReadFileBytes(FileName));
  except
    on E: Exception do
    begin
      Result := EmptyRepoConfig;
      Result.Exists := True;
      Result.Error := E.Message;
    end;
  end;
end;

function Listed(const AList: TStringArray; const AName: string): boolean;
var
  S: string;
begin
  for S in AList do
    if SameText(S, AName) then
      Exit(True);
  Result := False;
end;

function CheckSubject(const AConfig: TGittanRepoConfig; const ASubject: string;
  out ADetail: string): TGittanSubjectCheck;
const
  { What git and the tools write themselves. }
  Exempt: array[0..4] of string = ('Merge ', 'Revert "', 'fixup! ', 'squash! ', 'amend! ');
var
  S, TypeName, Scope, Part: string;
  i, Close: integer;
begin
  Result := scOk;
  ADetail := '';
  S := Trim(ASubject);
  if (Length(AConfig.Types) = 0) or (S = '') then
    Exit;
  for Part in Exempt do
    if Copy(S, 1, Length(Part)) = Part then
      Exit;
  i := 1;
  while (i <= Length(S)) and (S[i] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) do
    Inc(i);
  TypeName := Copy(S, 1, i - 1);
  Scope := '';
  if (i <= Length(S)) and (S[i] = '(') then
  begin
    Close := Pos(')', S, i);
    if Close = 0 then
      Exit(scNoType);
    Scope := Trim(Copy(S, i + 1, Close - i - 1));
    i := Close + 1;
  end;
  if (i <= Length(S)) and (S[i] = '!') then
    Inc(i);
  if (TypeName = '') or (i > Length(S)) or (S[i] <> ':') or
    ((i < Length(S)) and (S[i + 1] <> ' ')) then
    Exit(scNoType);
  if not Listed(AConfig.Types, TypeName) then
  begin
    ADetail := TypeName;
    Exit(scUnknownType);
  end;
  if (Scope <> '') and (Length(AConfig.Scopes) > 0) then
    for Part in Scope.Split([','], TStringSplitOptions.ExcludeEmpty) do
      if not Listed(AConfig.Scopes, Trim(Part)) then
      begin
        ADetail := Trim(Part);
        Exit(scUnknownScope);
      end;
end;

function GlobMatch(const APattern, AName: string): boolean;
var
  P, N, StarP, StarN: integer;

  { The bytes of the UTF-8 character at AName[I], so ? takes one
    character, not one byte of it. }
  function CharLen(I: integer): integer;
  begin
    case Ord(AName[I]) of
      $C0..$DF: Result := 2;
      $E0..$EF: Result := 3;
      $F0..$F7: Result := 4;
      else
        Result := 1;
    end;
    if I + Result > Length(AName) + 1 then
      Result := Length(AName) + 1 - I;
  end;

begin
  { One pass with a step back to the last *, which then takes one more
    character: the time is the pattern's length times the name's,
    whatever the pattern (a recursion over every * was exponential in
    them, and the pattern comes from a cloned file). }
  P := 1;
  N := 1;
  StarP := 0;
  StarN := 0;
  while N <= Length(AName) do
    if (P <= Length(APattern)) and (APattern[P] = '*') then
    begin
      StarP := P;
      StarN := N;
      Inc(P);
    end
    else if (P <= Length(APattern)) and (APattern[P] = '?') then
    begin
      Inc(N, CharLen(N));
      Inc(P);
    end
    else if (P <= Length(APattern)) and (APattern[P] = AName[N]) then
    begin
      Inc(N);
      Inc(P);
    end
    else if StarP > 0 then
    begin
      Inc(StarN, CharLen(StarN));
      N := StarN;
      P := StarP + 1;
    end
    else
      Exit(False);
  while (P <= Length(APattern)) and (APattern[P] = '*') do
    Inc(P);
  Result := P > Length(APattern);
end;

function BranchProtected(const AConfig: TGittanRepoConfig; const ABranch: string): boolean;
var
  S: string;
begin
  if ABranch = '' then
    Exit(False);
  for S in AConfig.Protected do
    if GlobMatch(S, ABranch) then
      Exit(True);
  Result := False;
end;

function RepoConfigTemplate: string;
begin
  Result :=
    '# What this repository says of itself, for everyone who clones it.' + LineEnding +
    '# Nothing here runs, so it needs no trust; git config, where it sets' + LineEnding +
    '# the same (bugtraq.*, commit.template), comes first.' + LineEnding +
    '#' + LineEnding +
    '# The kinds of project the Commands and Project pages list:' + LineEnding +
    '# project = ["rust", "go"]' + LineEnding +
    '#' + LineEnding +
    '# The issue tracker, for the links in commit messages: url with' + LineEnding +
    '# %BUGID% where the id goes, regex how a message refers to one (its' + LineEnding +
    '# first group is the id), and ids, when regex finds a whole' + LineEnding +
    '# reference ("Fixes #12, #13"), the ids within it.' + LineEnding +
    '# [issues]' + LineEnding +
    '# url = "https://tracker.example.com/issue/%BUGID%"' + LineEnding +
    '# regex = ''#(\d+)''' + LineEnding +
    '#' + LineEnding +
    '# How commit messages are written: the subject''s length that shows' + LineEnding +
    '# its count and the one that warns, a template for an empty message,' + LineEnding +
    '# whether commits are signed off unless one turns it off, and with' + LineEnding +
    '# types, the subjects of Conventional Commits, type(scope): text.' + LineEnding +
    '# [commit]' + LineEnding +
    '# subject-limit = 50' + LineEnding +
    '# subject-max = 72' + LineEnding +
    '# template = ".gittan/commit-message.txt"' + LineEnding +
    '# sign-off = true' + LineEnding +
    '# types = ["feat", "fix", "docs", "refactor", "test", "chore"]' + LineEnding +
    '# scopes = ["ui", "core"]' + LineEnding +
    '#' + LineEnding +
    '# The branches to commit on through pull requests only: the Commit' + LineEnding +
    '# section says so while one is checked out.' + LineEnding +
    '# [branches]' + LineEnding +
    '# protected = ["main", "release/*"]' + LineEnding;
end;

end.
