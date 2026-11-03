{ Ported from Trndi (https://github.com/slicke/trndi), GPL-3.0. }

unit gittan.ext.perm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils,
  gittan.sha256;

type
  {** Coarse permission groups. ui/timers are baseline (granted without prompt);
      data (the repository's content), net, exec and settings must be declared
      in the extension manifest and approved. }
  TExtPermGroup = (epData, epUI, epTimers, epNet, epExec, epSettings);
  TExtPermSet = set of TExtPermGroup;

  {** Parsed manifest from an extension's leading /* ... */ comment block.
      @name and @copyright are preferred; the historical first-line and (c)
      forms remain supported for existing extensions. }
  TExtManifest = record
    DisplayName: string;
    Author: string;
    Version: string;
    Description: string;
    Homepage: string;
    License: string;
    Requested: TExtPermSet;
    {** The repositories it runs for (@repos), every one when empty. }
    Repos: TStringArray;
    IsValid: boolean;
    ErrorMessage: string;
  end;

const
  {** Always granted, no prompt. }
  PermBaseline: TExtPermSet = [epUI, epTimers];
  {** Must appear in @perms and be approved by the user. }
  PermPromptable: TExtPermSet = [epData, epNet, epExec, epSettings];
  {** Human-readable names. Order matches TExtPermGroup. }
  PermGroupName: array[TExtPermGroup] of string =
    ('data', 'ui', 'timers', 'net', 'exec', 'settings');
  PermGroupDesc: array[TExtPermGroup] of string =
    ('Read the repositories: the files and their content, changes and history',
     'Show dialogs, cards and messages, add commands to the menus, keep its own settings',
     'Schedule timers',
     'Make network requests (fetch)',
     'Run git and other programs',
     'Read Gittan''s own settings');

{** Parse the leading /* ... */ block from an extension source. A UTF-8 BOM
    and a single compiler-emitted "use strict"; prologue line are tolerated
    before it. Invalid directives make IsValid False and explain the reason
    in ErrorMessage. }
function ParseExtManifest(const Script: string): TExtManifest;

{** SHA-256 hex digest of the script source. Used to detect edits and force re-prompt. }
function HashScript(const Script: string): string;

{** Stable extension id derived from the file path. Lower-case basename, no extension. }
function ExtIdFromPath(const FileName: string): string;

{** Convert a permission set to comma-separated names, baseline excluded. }
function PermSetToCSV(const s: TExtPermSet): string;

{** Parse "net, exec, settings" into a set. Unknown names are ignored.
    ParseExtManifest validates permission names for extension manifests. }
function CSVToPermSet(const s: string): TExtPermSet;

{** Map a name like "net" to epNet. Returns False if unknown. }
function ParsePermName(const s: string; out g: TExtPermGroup): boolean;

{** A remote's URL as @repos compares it: host and path in lower case,
    without the scheme, the user, the port, a trailing slash or ".git",
    so https://github.com/a/b.git and git@github.com:a/b are both
    github.com/a/b. }
function RemoteUrlKey(const AUrl: string): string;

{** Whether the repository at ARoot, with the remotes ARemoteUrls (a line
    each, "remote.<name>.url <url>" as RemoteUrlsIn gives them), is one of
    APatterns (@repos): a pattern that starts with /, ~, \\ or a drive is
    a root (~ the home folder), any other a remote (RemoteUrlKey); * and ?
    are wildcards. True when APatterns is empty. }
function ExtRepoInScope(const APatterns: TStringArray; const ARoot, ARemoteUrls: string): boolean;

implementation

function ParsePermName(const s: string; out g: TExtPermGroup): boolean;
var
  gi: TExtPermGroup;
  lc: string;
begin
  Result := False;
  lc := LowerCase(Trim(s));
  for gi := Low(TExtPermGroup) to High(TExtPermGroup) do
    if PermGroupName[gi] = lc then
    begin
      g := gi;
      Exit(True);
    end;
end;

function PermSetToCSV(const s: TExtPermSet): string;
var
  g: TExtPermGroup;
begin
  Result := '';
  for g := Low(TExtPermGroup) to High(TExtPermGroup) do
    if g in s then
    begin
      if Result <> '' then Result := Result + ',';
      Result := Result + PermGroupName[g];
    end;
end;

function CSVToPermSet(const s: string): TExtPermSet;
var
  parts: TStringArray;
  i: integer;
  g: TExtPermGroup;
begin
  Result := [];
  parts := s.Split([',', ' ', #9], TStringSplitOptions.ExcludeEmpty);
  for i := 0 to High(parts) do
    if ParsePermName(parts[i], g) then
      Include(Result, g);
end;

function HashScript(const Script: string): string;
var
  digest: TSHA256Digest;
  i: integer;
const
  HexChars: array[0..15] of char = '0123456789abcdef';
begin
  digest := SHA256String(Script);
  SetLength(Result, SizeOf(digest) * 2);
  for i := 0 to SizeOf(digest) - 1 do
  begin
    Result[1 + i * 2]     := HexChars[digest[i] shr 4];
    Result[2 + i * 2 + 0] := HexChars[digest[i] and $0F];
  end;
end;

function ExtIdFromPath(const FileName: string): string;
var
  base: string;
begin
  base := ExtractFileName(FileName);
  if LowerCase(ExtractFileExt(base)) = '.js' then
    base := Copy(base, 1, Length(base) - 3);
  Result := LowerCase(base);
end;

{ The first colon of S outside an IPv6 host's brackets ([::1]:22), 0
  when there is none. }
function HostColon(const S: string): integer;
var
  i: integer;
  InBrackets: boolean;
begin
  InBrackets := False;
  for i := 1 to Length(S) do
    case S[i] of
      '[': InBrackets := True;
      ']': InBrackets := False;
      ':': if not InBrackets then Exit(i);
    end;
  Result := 0;
end;

function RemoteUrlKey(const AUrl: string): string;
var
  s: string;
  p, Slash: integer;
begin
  s := LowerCase(Trim(AUrl));
  p := Pos('://', s);
  if p > 0 then
  begin
    Delete(s, 1, p + 2);
    Slash := Pos('/', s);
    if Slash = 0 then
      Slash := Length(s) + 1;
    p := Pos('@', s);
    if (p > 0) and (p < Slash) then
    begin
      Delete(s, 1, p);
      Dec(Slash, p);
    end;
    p := HostColon(s);
    if (p > 0) and (p < Slash) then
      Delete(s, p, Slash - p);
  end
  else if (s <> '') and not (s[1] in ['/', '.', '~', '\']) then
  begin
    { user@host:owner/repo, git's scp form: the colon comes before any
      slash. }
    Slash := Pos('/', s);
    if Slash = 0 then
      Slash := Length(s) + 1;
    p := HostColon(s);
    if (p > 0) and (p < Slash) then
    begin
      s[p] := '/';
      p := Pos('@', s);
      if (p > 0) and (p < Slash) then
        Delete(s, 1, p);
    end;
  end;
  while (s <> '') and (s[Length(s)] = '/') do
    SetLength(s, Length(s) - 1);
  if Copy(s, Length(s) - 3, 4) = '.git' then
    SetLength(s, Length(s) - 4);
  Result := s;
end;

{ A root or a root pattern with / for a separator and no trailing one. }
function ScopePath(const APath: string): string;
begin
  Result := StringReplace(APath, '\', '/', [rfReplaceAll]);
  while (Length(Result) > 1) and (Result[Length(Result)] = '/') do
    SetLength(Result, Length(Result) - 1);
end;

function IsPathPattern(const APattern: string): boolean;
begin
  Result := (APattern <> '') and ((APattern[1] in ['/', '~', '\']) or
    ((Length(APattern) >= 3) and (APattern[1] in ['A'..'Z', 'a'..'z']) and
    (APattern[2] = ':') and (APattern[3] in ['/', '\'])));
end;

function ExtRepoInScope(const APatterns: TStringArray; const ARoot, ARemoteUrls: string): boolean;
var
  Pattern, Root, Line, Url: string;
  p: integer;
begin
  if Length(APatterns) = 0 then
    Exit(True);
  Root := ScopePath(ARoot);
  for Pattern in APatterns do
    if IsPathPattern(Pattern) then
    begin
      { GetUserDir ends in a separator, so ~/x would give two. }
      if Pattern[1] = '~' then
        Url := ScopePath(ExcludeTrailingPathDelimiter(GetUserDir) + Copy(Pattern, 2, MaxInt))
      else
        Url := ScopePath(Pattern);
      if (Root <> '') and IsWild(Root, Url, not FileNameCaseSensitive) then
        Exit(True);
    end
    else
      for Line in ARemoteUrls.Split([#10]) do
      begin
        p := Pos(' ', Line);
        if p = 0 then
          Continue;
        Url := RemoteUrlKey(Copy(Line, p + 1, MaxInt));
        if (Url <> '') and IsWild(Url, RemoteUrlKey(Pattern), False) then
          Exit(True);
      end;
  Result := False;
end;

{ Strip leading "*" decoration from a manifest body line. }
function StripLineDecoration(const line: string): string;
var
  s: string;
begin
  s := Trim(line);
  if (Length(s) >= 1) and (s[1] = '*') then
    s := Trim(Copy(s, 2, MaxInt));
  Result := s;
end;

function ParseExtManifest(const Script: string): TExtManifest;
const
  STRICT_DQ = '"use strict"';
  STRICT_SQ = '''use strict''';
var
  s, body: string;
  startIdx, endIdx: integer;
  prologueLen: integer;
  lines, parts: TStringArray;
  i, j: integer;
  trimmed, lc, value: string;
  haveName, named: boolean;
  g: TExtPermGroup;

  function DirectiveValue(const Directive: string; out AValue: string): boolean;
  var
    rest: string;
  begin
    Result := False;
    if Copy(lc, 1, Length(Directive)) <> Directive then Exit;
    rest := Copy(trimmed, Length(Directive) + 1, MaxInt);
    if (rest <> '') and not (rest[1] in [' ', #9]) then Exit;
    AValue := Trim(rest);
    Result := True;
  end;

  procedure AddError(const Msg: string);
  begin
    Result.IsValid := False;
    if Result.ErrorMessage <> '' then
      Result.ErrorMessage := Result.ErrorMessage + sLineBreak;
    Result.ErrorMessage := Result.ErrorMessage + Msg;
  end;

begin
  Result.DisplayName := '';
  Result.Author := '';
  Result.Version := '';
  Result.Description := '';
  Result.Homepage := '';
  Result.License := '';
  Result.Requested := [];
  Result.Repos := nil;
  Result.IsValid := True;
  Result.ErrorMessage := '';

  s := Script;
  if s = '' then Exit;
  if Copy(s, 1, 3) = #$EF#$BB#$BF then
    Delete(s, 1, 3); // Permit UTF-8 files saved with a BOM.

  // Permit a compiler-emitted strict-mode prologue before the manifest.
  // TypeScript (unconditionally since 6.0) and Babel prepend '"use strict";'
  // when emitting a plain script, which would otherwise push the manifest off
  // byte one and silently strip a compiled extension of its name and perms.
  prologueLen := 0;
  if Copy(s, 1, Length(STRICT_DQ)) = STRICT_DQ then
    prologueLen := Length(STRICT_DQ)
  else if Copy(s, 1, Length(STRICT_SQ)) = STRICT_SQ then
    prologueLen := Length(STRICT_SQ);
  if prologueLen > 0 then
  begin
    Delete(s, 1, prologueLen);
    if (s <> '') and (s[1] = ';') then
      Delete(s, 1, 1);
    // Consume exactly one line ending (CRLF, CR or LF): the prologue excuses
    // its own line only. A blank line after it is still rejected, as it
    // would be in a file without one.
    if Copy(s, 1, 2) = #13#10 then
      Delete(s, 1, 2)
    else if (s <> '') and (s[1] in [#13, #10]) then
      Delete(s, 1, 1);
  end;

  startIdx := Pos('/*', s);
  if startIdx <> 1 then Exit;
  endIdx := PosEx('*/', s, startIdx + 2);
  if endIdx = 0 then Exit;

  body := Copy(s, startIdx + 2, endIdx - startIdx - 2);
  lines := body.Split([#13, #10], TStringSplitOptions.None);
  haveName := False;
  for i := 0 to High(lines) do
  begin
    trimmed := StripLineDecoration(lines[i]);
    if trimmed = '' then Continue;
    lc := LowerCase(trimmed);

    if DirectiveValue('@name', value) then
    begin
      Result.DisplayName := value;
      haveName := value <> '';
    end
    else if DirectiveValue('@copyright', value) then
      Result.Author := value
    else if DirectiveValue('@version', value) then
      Result.Version := value
    else if DirectiveValue('@description', value) then
      Result.Description := value
    else if DirectiveValue('@homepage', value) then
      Result.Homepage := value
    else if DirectiveValue('@license', value) then
      Result.License := value
    else if DirectiveValue('@perms', value) then
    begin
      parts := value.Split([',', ' ', #9], TStringSplitOptions.ExcludeEmpty);
      for j := 0 to High(parts) do
        if ParsePermName(parts[j], g) then
          Include(Result.Requested, g)
        else
          AddError('Unknown permission: ' + parts[j]);
    end
    else if DirectiveValue('@repos', value) then
    begin
      { An empty Repos means every repository, so a line of commas and
        blanks is refused as an empty one is. }
      named := False;
      parts := value.Split([','], TStringSplitOptions.ExcludeEmpty);
      for j := 0 to High(parts) do
        if Trim(parts[j]) <> '' then
        begin
          Result.Repos := Concat(Result.Repos, [Trim(parts[j])]);
          named := True;
        end;
      if not named then
        AddError('@repos names no repository');
    end
    else if (Pos('(c)', lc) = 1) or (Pos('copyright', lc) = 1) then
    begin
      if Result.Author = '' then Result.Author := trimmed;
    end
    else if trimmed[1] = '@' then
      AddError('Unknown manifest directive: ' + trimmed)
    else if not haveName then
    begin
      Result.DisplayName := trimmed;
      haveName := True;
    end;
  end;
end;

end.
