unit gittan.manifest;

{** What the project drivers (src/proj) share to read their manifests
  and lock files: the dependency record, a TOML reader of what the
  manifests need and no more (tables, array tables, strings, inline
  tables and arrays of strings, with comments stripped and an array
  that runs over several lines joined), the [[package]] lock that
  Cargo.lock, uv.lock, poetry.lock and pdm.lock share, and a JSON
  object reader. Each driver parses its own files with these as
  functions of the text, so a file of a commit is read the same as the
  work tree's; nothing here touches a file or runs a program. Tested in
  tests/testmanifest.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson;

type
  {** A dependency: what the manifest asks for (Version, as written:
    "^1.2", ">=2.0", "1"; '' when it names no version, as a path
    dependency or a Lazarus package), what the lock file resolved it to
    (Resolved, '' when there is no lock or it is not in it), and its
    group: '' for a plain dependency, "dev", "build", "optional",
    "peer", "indirect", or an extras group's name in Python. }
  TGittanDependency = record
    Name, Version, Resolved, Group: string;
  end;
  TGittanDependencies = array of TGittanDependency;

  {** A key of a TOML file with the table it is in ("package",
    "dependencies", "tool.poetry.dependencies") and its value as
    written, quotes and braces included. }
  TGittanTomlEntry = record
    Table, Key, Value: string;
    {** The table is an array table ([[package]]), and this is the
      index of its element, from 0; -1 in a plain table. }
    Index: integer;
  end;
  TGittanTomlEntries = array of TGittanTomlEntry;

{** The entries of a TOML text, in order. A key's value that opens an
  array or an inline table runs on to the line that closes it. }
function ReadToml(const AText: string): TGittanTomlEntries;

{** The text of a TOML string value, without its quotes; '' for a
  value that is not a string. }
function TomlString(const AValue: string): string;

{** The value of AKey in an inline table value "{ version = "1", ...
  }", as written; '' when it is not there or the value is no table. }
function TomlInlineValue(const AValue, AKey: string): string;

{** The strings of an array value ["a", "b"]; none for a value that is
  no array. }
function TomlArrayStrings(const AValue: string): TStringArray;

{** A key as written, its quotes taken off. }
function BareKey(const AKey: string): string;

{** Adds a dependency to ADeps, once per name and group; a second one
  of the same name and group is left out. }
procedure AddDependency(var ADeps: TGittanDependencies; const AName, AVersion, AResolved,
  AGroup: string);

{** Adds a package of a lock file, with its version in Resolved, once
  per name and version: a lock may hold two versions of a package, and
  ResolveDependencies of gittan.project picks the one the manifest
  asks for. }
procedure AddLocked(var ADeps: TGittanDependencies; const AName, AResolved: string);

{** The packages of a TOML lock with [[package]] of name and version
  (Cargo.lock, uv.lock, poetry.lock, pdm.lock), each with its version
  in Resolved, every version of a package listed twice. }
function ParseTomlLock(const AText: string): TGittanDependencies;

{** The JSON object of AJson, nil when it is not one; the caller frees
  it. }
function ParseJsonObject(const AJson: string): TJSONObject;

implementation

uses
  StrUtils, jsonparser, gittan.textfile;


{ ---------------------------------------------------------------------------
  TOML
  --------------------------------------------------------------------------- }

{ Whether the character at AIndex of AText closes the string AQuote
  opened. In a basic ("...") string a backslash escapes the character
  after it, which AIndex then steps over; a literal ('...') string has
  no escapes. }
function EndsQuote(const AText: string; var AIndex: integer; AQuote: char): boolean;
begin
  if (AQuote = '"') and (AText[AIndex] = '\') and (AIndex < Length(AText)) then
  begin
    Inc(AIndex);
    Exit(False);
  end;
  Result := AText[AIndex] = AQuote;
end;

{ The line without its comment: a "#" outside quotes ends it. }
function StripComment(const ALine: string): string;
var
  i: integer;
  Quote: char;
begin
  Quote := #0;
  i := 1;
  while i <= Length(ALine) do
  begin
    if Quote <> #0 then
    begin
      if EndsQuote(ALine, i, Quote) then
        Quote := #0;
    end
    else if ALine[i] in ['"', ''''] then
      Quote := ALine[i]
    else if ALine[i] = '#' then
      Exit(Copy(ALine, 1, i - 1));
    Inc(i);
  end;
  Result := ALine;
end;

{ How many brackets and braces ALine opens beyond those it closes,
  outside quotes. }
function OpenDepth(const ALine: string): integer;
var
  i: integer;
  Quote: char;
begin
  Result := 0;
  Quote := #0;
  i := 1;
  while i <= Length(ALine) do
  begin
    if Quote <> #0 then
    begin
      if EndsQuote(ALine, i, Quote) then
        Quote := #0;
    end
    else
      case ALine[i] of
        '"', '''': Quote := ALine[i];
        '[', '{': Inc(Result);
        ']', '}': Dec(Result);
      end;
    Inc(i);
  end;
end;

{ A key as written, its quotes taken off. }
function BareKey(const AKey: string): string;
begin
  Result := Trim(AKey);
  if (Length(Result) >= 2) and (Result[1] in ['"', '''']) and
    (Result[Length(Result)] = Result[1]) then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

function ReadToml(const AText: string): TGittanTomlEntries;
var
  Start, P, Depth: integer;
  Line, Table, Next: string;
  Index: integer;
  Arrays: TStringList;
begin
  Result := nil;
  Table := '';
  Index := -1;
  Arrays := TStringList.Create;
  try
    Start := 1;
    while NextLine(AText, Start, Line) do
    begin
      Line := Trim(StripComment(Line));
      if Line = '' then
        Continue;
      if Line[1] = '[' then
      begin
        if (Length(Line) > 1) and (Line[2] = '[') then
        begin
          P := Pos(']]', Line);
          if P = 0 then
            Continue;
          Table := Trim(Copy(Line, 3, P - 3));
          { The element's index: how many of this array table came
            before. }
          P := Arrays.IndexOf(Table);
          if P < 0 then
          begin
            Arrays.AddObject(Table, TObject(PtrInt(0)));
            Index := 0;
          end
          else
          begin
            Index := PtrInt(Arrays.Objects[P]) + 1;
            Arrays.Objects[P] := TObject(PtrInt(Index));
          end;
        end
        else
        begin
          P := Pos(']', Line);
          if P = 0 then
            Continue;
          Table := Trim(Copy(Line, 2, P - 2));
          Index := -1;
        end;
        Continue;
      end;
      P := Pos('=', Line);
      if P < 2 then
        Continue;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].Table := Table;
      Result[High(Result)].Index := Index;
      Result[High(Result)].Key := BareKey(Copy(Line, 1, P - 1));
      Line := Trim(Copy(Line, P + 1, MaxInt));
      { An array or an inline table may run on: join the lines until
        it closes. }
      Depth := OpenDepth(Line);
      while (Depth > 0) and NextLine(AText, Start, Next) do
      begin
        Next := Trim(StripComment(Next));
        Line := Line + ' ' + Next;
        Depth := Depth + OpenDepth(Next);
      end;
      Result[High(Result)].Value := Line;
    end;
  finally
    Arrays.Free;
  end;
end;

{ The UTF-8 of the code point ACode; '' for a surrogate or one beyond
  Unicode. }
function CodePointUtf8(ACode: longword): string;
begin
  if ACode < $80 then
    Result := Chr(ACode)
  else if ACode < $800 then
    Result := Chr($C0 or (ACode shr 6)) + Chr($80 or (ACode and $3F))
  else if (ACode >= $D800) and (ACode <= $DFFF) then
    Result := ''
  else if ACode < $10000 then
    Result := Chr($E0 or (ACode shr 12)) + Chr($80 or ((ACode shr 6) and $3F)) +
      Chr($80 or (ACode and $3F))
  else if ACode <= $10FFFF then
    Result := Chr($F0 or (ACode shr 18)) + Chr($80 or ((ACode shr 12) and $3F)) +
      Chr($80 or ((ACode shr 6) and $3F)) + Chr($80 or (ACode and $3F))
  else
    Result := '';
end;

{ The inside of a basic string with its escapes decoded: \" \\ \b \t
  \n \f \r \e, and \uXXXX and \UXXXXXXXX as UTF-8; an escape TOML does
  not know stays as written. }
function UnescapeBasic(const S: string): string;
var
  i, n: integer;
  Code: longword;
  Hex: string;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if (S[i] <> '\') or (i = Length(S)) then
    begin
      Result := Result + S[i];
      Inc(i);
      Continue;
    end;
    Inc(i);
    case S[i] of
      '"': Result := Result + '"';
      '\': Result := Result + '\';
      'b': Result := Result + #8;
      't': Result := Result + #9;
      'n': Result := Result + #10;
      'f': Result := Result + #12;
      'r': Result := Result + #13;
      'e': Result := Result + #27;
      'u', 'U':
      begin
        if S[i] = 'u' then
          n := 4
        else
          n := 8;
        Hex := Copy(S, i + 1, n);
        if (Length(Hex) = n) and TryStrToDWord('$' + Hex, Code) then
        begin
          Result := Result + CodePointUtf8(Code);
          Inc(i, n);
        end
        else
          Result := Result + '\' + S[i];
      end;
      else
        Result := Result + '\' + S[i];
    end;
    Inc(i);
  end;
end;

function TomlString(const AValue: string): string;
var
  S: string;
begin
  S := Trim(AValue);
  if (Length(S) >= 2) and (S[1] in ['"', '''']) and (S[Length(S)] = S[1]) then
  begin
    Result := Copy(S, 2, Length(S) - 2);
    if S[1] = '"' then
      Result := UnescapeBasic(Result);
  end
  else
    Result := '';
end;

{ The parts of a "{ a = 1, b = "x" }" or "[ "a", "b" ]" value, split on
  the commas outside quotes and nested brackets. }
function SplitTomlList(const AValue: string; AOpen, AClose: char): TStringArray;
var
  S, Part: string;
  i, Depth: integer;
  Quote: char;
begin
  Result := nil;
  S := Trim(AValue);
  if (S = '') or (S[1] <> AOpen) or (S[Length(S)] <> AClose) then
    Exit;
  S := Copy(S, 2, Length(S) - 2);
  Part := '';
  Depth := 0;
  Quote := #0;
  i := 0;
  while i < Length(S) do
  begin
    Inc(i);
    if Quote <> #0 then
    begin
      { An escape stays as written, the backslash and what it escapes. }
      if (Quote = '"') and (S[i] = '\') and (i < Length(S)) then
      begin
        Part := Part + S[i];
        Inc(i);
      end
      else if S[i] = Quote then
        Quote := #0;
      Part := Part + S[i];
    end
    else if S[i] in ['"', ''''] then
    begin
      Quote := S[i];
      Part := Part + S[i];
    end
    else if S[i] in ['[', '{'] then
    begin
      Inc(Depth);
      Part := Part + S[i];
    end
    else if S[i] in [']', '}'] then
    begin
      Dec(Depth);
      Part := Part + S[i];
    end
    else if (S[i] = ',') and (Depth = 0) then
    begin
      if Trim(Part) <> '' then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Trim(Part);
      end;
      Part := '';
    end
    else
      Part := Part + S[i];
  end;
  if Trim(Part) <> '' then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Trim(Part);
  end;
end;

function TomlInlineValue(const AValue, AKey: string): string;
var
  Part: string;
  P: integer;
begin
  for Part in SplitTomlList(AValue, '{', '}') do
  begin
    P := Pos('=', Part);
    if (P > 1) and (BareKey(Copy(Part, 1, P - 1)) = AKey) then
      Exit(Trim(Copy(Part, P + 1, MaxInt)));
  end;
  Result := '';
end;

function TomlArrayStrings(const AValue: string): TStringArray;
var
  Part, S: string;
begin
  Result := nil;
  for Part in SplitTomlList(AValue, '[', ']') do
  begin
    S := TomlString(Part);
    if S <> '' then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := S;
    end;
  end;
end;

procedure AddDependency(var ADeps: TGittanDependencies; const AName, AVersion, AResolved,
  AGroup: string);
var
  i: integer;
begin
  if AName = '' then
    Exit;
  for i := 0 to High(ADeps) do
    if (ADeps[i].Name = AName) and (ADeps[i].Group = AGroup) then
      Exit;
  SetLength(ADeps, Length(ADeps) + 1);
  ADeps[High(ADeps)].Name := AName;
  ADeps[High(ADeps)].Version := AVersion;
  ADeps[High(ADeps)].Resolved := AResolved;
  ADeps[High(ADeps)].Group := AGroup;
end;

procedure AddLocked(var ADeps: TGittanDependencies; const AName, AResolved: string);
var
  i: integer;
begin
  if AName = '' then
    Exit;
  for i := 0 to High(ADeps) do
    if (ADeps[i].Name = AName) and (ADeps[i].Resolved = AResolved) then
      Exit;
  SetLength(ADeps, Length(ADeps) + 1);
  ADeps[High(ADeps)] := Default(TGittanDependency);
  ADeps[High(ADeps)].Name := AName;
  ADeps[High(ADeps)].Resolved := AResolved;
end;

{ The packages of a TOML lock with [[package]] of name and version
  (Cargo.lock, uv.lock, poetry.lock, pdm.lock). }
function ParseTomlLock(const AText: string): TGittanDependencies;
var
  E: TGittanTomlEntry;
  Name, Version: string;
  Index: integer;

  procedure Flush;
  begin
    if (Name <> '') and (Version <> '') then
      AddLocked(Result, Name, Version);
    Name := '';
    Version := '';
  end;

begin
  Result := nil;
  Name := '';
  Version := '';
  Index := -2;
  for E in ReadToml(AText) do
  begin
    if E.Table <> 'package' then
      Continue;
    if E.Index <> Index then
    begin
      Flush;
      Index := E.Index;
    end;
    if E.Key = 'name' then
      Name := TomlString(E.Value)
    else if E.Key = 'version' then
      Version := TomlString(E.Value);
  end;
  Flush;
end;

function ParseJsonObject(const AJson: string): TJSONObject;
var
  Data: TJSONData;
begin
  Result := nil;
  if (Trim(AJson) = '') or JsonTooDeep(AJson) then
    Exit;
  try
    Data := GetJSON(AJson);
  except
    Exit;
  end;
  if Data is TJSONObject then
    Result := TJSONObject(Data)
  else
    Data.Free;
end;

end.
