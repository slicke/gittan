unit gittan.textfile;

{** Small helpers for text as git and the files have it, byte for byte:
  reading a whole file, splitting at LF with the CRs kept, a line
  without its CR, walking the lines of git's output, and undoing the
  backslash escapes the symbol index and .po files write, and writing a
  whole file through a temporary one renamed over it. No LCL; tested in
  tests/testtextfile.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson;

{** The bytes of the file AFileName, unconverted; raises when it cannot
  be read. }
function ReadFileBytes(const AFileName: string): RawByteString;

{** AText's lines into ALines (cleared first), split at LF only, so each
  keeps the CR a CRLF file ends it with. A final LF starts no line. }
procedure SplitLf(const AText: RawByteString; ALines: TStrings);

{** ALine without the CR a CRLF file ends it with. }
function BareLine(const ALine: string): string;

{** The line of S that starts at AStart, without its LF, in ALine;
  AStart moves past it. False at the end of S. }
function NextLine(const S: string; var AStart: integer; out ALine: string): boolean;

{** S with the C escapes read: \n, \t, \r, \a, \b, \f, \v and a
  backslash before any other character for that character. }
function UnescapeC(const S: string): string;

{** The deepest a JSON, TOML or XML file a repository holds may nest its
  arrays, tables and elements. fpjson, toml-fp and fcl-xml (with the
  code that walks its tree) read nesting by recursion, and
  100 000 levels end the process on a stack overflow that no except
  catches, so a deeper text is refused before it is parsed. }
const
  MaxNesting = 200;

resourcestring
  rsNestedTooDeep = 'Nested deeper than %d levels.';

{** Whether AJson nests arrays and objects deeper than MaxNesting, its
  strings left out. }
function JsonTooDeep(const AJson: string): boolean;

{** GetJSON of AJson, which raises as on text that is not JSON when it
  nests deeper than MaxNesting; for JSON that others write, an
  extension's included. }
function GetJSONLimited(const AJson: string): TJSONData;

{** The same for TOML: its basic, literal and multi-line strings and its
  comments left out, inline tables and arrays counted, and the parts of
  a dotted key or table header (a.b.c, [a.b.c]) as one level each. }
function TomlTooDeep(const AToml: string): boolean;

{** The same for XML: its elements counted, an empty one (<a/>) not,
  comments, CDATA sections, processing instructions and the quoted
  values of attributes left out. Text with a NUL byte counts as too
  deep: UTF-16 or UTF-32, which the scan of bytes cannot read (a
  character with a byte of 22h would pass for a quote) and the parser
  can. }
function XmlTooDeep(const AXml: string): boolean;

{** S with every byte that does not start a valid UTF-8 character (a
  CP1252 é, a character cut in half, an overlong form or a surrogate)
  replaced by U+FFFD, so a JSON body built from it is valid UTF-8. }
function Utf8Clean(const S: RawByteString): RawByteString;

{** The object TGittanRepo.FileChanges gives the line of a diff that
  ends its side without a newline (git's "\ No newline at end of file"
  after it): a mark, never an object to use or free. }
function NoNewlineMark: TObject;

{** Whether ALines' line AIndex has NoNewlineMark. }
function HasNoNewline(ALines: TStrings; AIndex: integer): boolean;

{** A path in the temporary folder that no other call, in this process
  or another, gets: APrefix, the process id and a count. Nothing is
  there (a file an earlier run with the same id left is deleted); the
  caller writes it, or git makes it. GetTempFileName only skips names
  that exist, so two threads asking before either wrote got the same.
  On Unix the folder is one of the user's own inside the temporary one
  (PrivateTempDir), since /tmp is shared: another user could otherwise
  put a file or a link at the name first and read or redirect what is
  written there, a partial commit's text among it. }
function TempFileName(const APrefix: string): string;

{** Writes AText as the whole of AFileName, creating its folder: into a
  temporary file beside it first (AFileName, the process id, a count of
  the writes and .tmp, so two writers never share one), then renamed over
  it in one step, so a failed or cut write leaves the old file as it
  was. A symbolic link at AFileName stays: the file it leads to is the
  one replaced (a settings file linked into a folder of dotfiles).
  AMode is the new file's permissions on Unix (&600 for one with a
  secret in it), less the umask; Windows has none. False when it could
  not be written. }
function WriteFileReplacing(const AFileName: RawByteString; const AText: RawByteString;
  AMode: integer = &644): boolean;

implementation

uses
  {$IF DEFINED(UNIX) OR DEFINED(HAIKU)}BaseUnix,{$ENDIF}
  { The parser GetJSON reads with. }
  jsonparser;

function ReadFileBytes(const AFileName: string): RawByteString;
var
  F: TFileStream;
begin
  Result := '';
  F := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

procedure SplitLf(const AText: RawByteString; ALines: TStrings);
var
  i, Start: integer;
begin
  ALines.Clear;
  Start := 1;
  for i := 1 to Length(AText) do
    if AText[i] = #10 then
    begin
      ALines.Add(Copy(AText, Start, i - Start));
      Start := i + 1;
    end;
  if Start <= Length(AText) then
    ALines.Add(Copy(AText, Start, MaxInt));
end;

function BareLine(const ALine: string): string;
begin
  Result := ALine;
  if (Result <> '') and (Result[Length(Result)] = #13) then
    SetLength(Result, Length(Result) - 1);
end;

function NextLine(const S: string; var AStart: integer; out ALine: string): boolean;
var
  Stop: integer;
begin
  Result := AStart <= Length(S);
  if not Result then
  begin
    ALine := '';
    Exit;
  end;
  Stop := Pos(#10, S, AStart);
  if Stop = 0 then
    Stop := Length(S) + 1;
  ALine := Copy(S, AStart, Stop - AStart);
  AStart := Stop + 1;
end;

function UnescapeC(const S: string): string;
var
  i, n: integer;
begin
  Result := '';
  SetLength(Result, Length(S));
  n := 0;
  i := 1;
  while i <= Length(S) do
  begin
    Inc(n);
    if (S[i] = '\') and (i < Length(S)) then
    begin
      Inc(i);
      case S[i] of
        'n': Result[n] := #10;
        't': Result[n] := #9;
        'r': Result[n] := #13;
        'a': Result[n] := #7;
        'b': Result[n] := #8;
        'f': Result[n] := #12;
        'v': Result[n] := #11;
        else
          Result[n] := S[i];
      end;
    end
    else
      Result[n] := S[i];
    Inc(i);
  end;
  SetLength(Result, n);
end;

function JsonTooDeep(const AJson: string): boolean;
var
  i, Depth: integer;
  Quote: char;
begin
  Depth := 0;
  i := 1;
  while i <= Length(AJson) do
  begin
    case AJson[i] of
      { GetJSON is not strict and reads a string in single quotes too. }
      '"', '''':
      begin
        Quote := AJson[i];
        Inc(i);
        while (i <= Length(AJson)) and (AJson[i] <> Quote) do
        begin
          if AJson[i] = '\' then
            Inc(i);
          Inc(i);
        end;
      end;
      '[', '{':
      begin
        Inc(Depth);
        if Depth > MaxNesting then
          Exit(True);
      end;
      ']', '}':
        if Depth > 0 then
          Dec(Depth);
    end;
    Inc(i);
  end;
  Result := False;
end;

function Utf8Clean(const S: RawByteString): RawByteString;
const
  Bad = #$EF#$BF#$BD;
var
  i, n, Len, k: integer;
  b: byte;
  Code, Least: longword;
  Ok: boolean;
  Out: integer;
begin
  Len := Length(S);
  { A bad byte grows to three. }
  SetLength(Result, Len * 3);
  Out := 0;
  i := 1;
  while i <= Len do
  begin
    b := Ord(S[i]);
    if b < $80 then
    begin
      n := 0;
      Least := 0;
      Code := b;
    end
    else if b and $E0 = $C0 then
    begin
      n := 1;
      Least := $80;
      Code := b and $1F;
    end
    else if b and $F0 = $E0 then
    begin
      n := 2;
      Least := $800;
      Code := b and $0F;
    end
    else if b and $F8 = $F0 then
    begin
      n := 3;
      Least := $10000;
      Code := b and $07;
    end
    else
      n := -1;
    Ok := (n >= 0) and (i + n <= Len);
    if Ok then
      for k := 1 to n do
        if Ord(S[i + k]) and $C0 <> $80 then
        begin
          Ok := False;
          Break;
        end
        else
          Code := (Code shl 6) or (Ord(S[i + k]) and $3F);
    { Overlong forms, surrogates and code points past U+10FFFF are not
      UTF-8 either. }
    if Ok and ((Code < Least) or (Code > $10FFFF) or
      ((Code >= $D800) and (Code <= $DFFF))) then
      Ok := False;
    if Ok then
    begin
      Move(S[i], Result[Out + 1], n + 1);
      Inc(Out, n + 1);
      Inc(i, n + 1);
    end
    else
    begin
      Move(Bad[1], Result[Out + 1], 3);
      Inc(Out, 3);
      Inc(i);
    end;
  end;
  SetLength(Result, Out);
end;

function GetJSONLimited(const AJson: string): TJSONData;
begin
  if JsonTooDeep(AJson) then
    raise EJSON.CreateFmt(rsNestedTooDeep, [MaxNesting]);
  Result := GetJSON(AJson);
end;

function TomlTooDeep(const AToml: string): boolean;
var
  i, Depth, Dots, Carried: integer;
  { What Carried was outside each bracket open. }
  Outer: array[1..MaxNesting] of integer;

  function At(const AQuote: string): boolean;
  begin
    Result := Copy(AToml, i, Length(AQuote)) = AQuote;
  end;

  { Past a multi-line string opened at i: to its closing three quotes
    and the one or two quotes of the content TOML lets stand before
    them. A backslash escapes in the basic kind only. }
  procedure SkipMultiLine(AQuote: char; AEscapes: boolean);
  begin
    Inc(i, 3);
    while (i <= Length(AToml)) and not At(StringOfChar(AQuote, 3)) do
    begin
      if AEscapes and (AToml[i] = '\') then
        Inc(i);
      Inc(i);
    end;
    Inc(i, 3);
    while (i <= Length(AToml)) and (AToml[i] = AQuote) do
      Inc(i);
  end;

  { Past a one-line string opened at i, to its quote or the end of the
    line, where a string that is not closed ends. }
  procedure SkipLine(AQuote: char; AEscapes: boolean);
  begin
    Inc(i);
    while (i <= Length(AToml)) and not (AToml[i] in [AQuote, #10]) do
    begin
      if AEscapes and (AToml[i] = '\') and (i < Length(AToml)) and
        (AToml[i + 1] <> #10) then
        Inc(i);
      Inc(i);
    end;
    Inc(i);
  end;

{ toml-fp makes a table of every part of a dotted key, a.b.c = 1 or
  [a.b.c], and frees them by recursion too, so the dots count as levels:
  those of the key and value being read (Dots, which a comma, a line or
  a bracket starts again) on top of the brackets open and of the keys
  that led into them (Carried). A dot in a value, the one of 1.5, adds
  one to its key's. }
begin
  Depth := 0;
  Dots := 0;
  Carried := 0;
  i := 1;
  while i <= Length(AToml) do
    if At('"""') then
      SkipMultiLine('"', True)
    else if At('''''''') then
      SkipMultiLine('''', False)
    else
    begin
      case AToml[i] of
        '"': SkipLine('"', True);
        '''': SkipLine('''', False);
        '#':
          while (i <= Length(AToml)) and (AToml[i] <> #10) do
            Inc(i);
        '.':
        begin
          Inc(Dots);
          if Depth + Carried + Dots > MaxNesting then
            Exit(True);
          Inc(i);
        end;
        ',', #10:
        begin
          Dots := 0;
          Inc(i);
        end;
        '[', '{':
        begin
          Inc(Depth);
          if Depth + Carried + Dots > MaxNesting then
            Exit(True);
          Outer[Depth] := Carried;
          Inc(Carried, Dots);
          Dots := 0;
          Inc(i);
        end;
        ']', '}':
        begin
          if Depth > 0 then
          begin
            Carried := Outer[Depth];
            Dec(Depth);
          end;
          Dots := 0;
          Inc(i);
        end;
        else
          Inc(i);
      end;
    end;
  Result := False;
end;

function XmlTooDeep(const AXml: string): boolean;
var
  i, Depth: integer;

  function At(const AText: string): boolean;
  begin
    Result := Copy(AXml, i, Length(AText)) = AText;
  end;

  { Past the first AEnd from i on, or to the end of the text. }
  procedure SkipPast(const AEnd: string);
  var
    Found: SizeInt;
  begin
    Found := Pos(AEnd, AXml, i);
    if Found = 0 then
      i := Length(AXml) + 1
    else
      i := Found + Length(AEnd);
  end;

  { Past the tag opened at i, to its >; a > in a quoted value does not
    end it. Whether it ends in />. }
  function SkipTag: boolean;
  var
    Quote: char;
  begin
    Result := False;
    Inc(i);
    while (i <= Length(AXml)) and (AXml[i] <> '>') do
    begin
      if AXml[i] in ['"', ''''] then
      begin
        Quote := AXml[i];
        Inc(i);
        while (i <= Length(AXml)) and (AXml[i] <> Quote) do
          Inc(i);
      end;
      Inc(i);
    end;
    Result := (i <= Length(AXml)) and (AXml[i - 1] = '/');
    Inc(i);
  end;

begin
  if Pos(#0, AXml) > 0 then
    Exit(True);
  Depth := 0;
  i := 1;
  while i <= Length(AXml) do
    if AXml[i] <> '<' then
      Inc(i)
    else if At('<!--') then
      SkipPast('-->')
    else if At('<![CDATA[') then
      SkipPast(']]>')
    else if At('<?') then
      SkipPast('?>')
    else if At('<!') then
      SkipPast('>')
    else if At('</') then
    begin
      if Depth > 0 then
        Dec(Depth);
      SkipPast('>');
    end
    else if not SkipTag then
    begin
      Inc(Depth);
      if Depth > MaxNesting then
        Exit(True);
    end;
  Result := False;
end;

{$IFDEF WINDOWS}
{ Declared here rather than taken from the Windows unit, whose DeleteFile
  would shadow that of SysUtils. }
function MoveFileExW(AFrom, ATo: PWideChar; AFlags: longword): LongBool; stdcall;
  external 'kernel32' name 'MoveFileExW';

const
  MOVEFILE_REPLACE_EXISTING = 1;
  MOVEFILE_WRITE_THROUGH = 8;
{$ENDIF}

var
  { The writes so far, which name each one's temporary file. }
  WriteCount: longint = 0;
{$IFDEF UNIX}
  { The private folder PrivateTempDir settled on, '' before the first. }
  PrivateTemp: string = '';
{$ENDIF}

{ AFileName, or the file the symbolic link there leads to, through a
  few links at most (a loop of them ends there); a relative target
  counts from the link's folder. }
function ThroughLinks(const AFileName: RawByteString): RawByteString;
var
  Target: RawByteString;
  n: integer;
begin
  Result := AFileName;
  for n := 1 to 8 do
  begin
    {$IF DEFINED(UNIX) OR DEFINED(HAIKU)}
    { readlink itself: FileGetSymLinkTarget reads no link whose file is
      not there yet. '' for what is no link. }
    Target := fpReadLink(Result);
    if Target = '' then
      Exit;
    {$ELSE}
    Target := '';
    { It raises for a name that is not there, a file not yet written. }
    try
      if not FileGetSymLinkTarget(Result, Target) or (Target = '') then
        Exit;
    except
      Exit;
    end;
    {$ENDIF}
    if (Target[1] in AllowDirectorySeparators) or
      ((Length(Target) > 1) and (Target[2] = ':')) then
      Result := Target
    else
      Result := ExpandFileName(ExtractFilePath(ExpandFileName(Result)) + Target);
  end;
end;

function NoNewlineMark: TObject;
begin
  Result := TObject(PtrUInt(1));
end;

function HasNoNewline(ALines: TStrings; AIndex: integer): boolean;
begin
  Result := (AIndex >= 0) and (AIndex < ALines.Count) and (ALines.Objects[AIndex] = NoNewlineMark);
end;

{$IFDEF UNIX}
{ Whether ADir is a folder (not a link to one) of this user that no one
  else may enter. }
function OwnPrivateDir(const ADir: string): boolean;
var
  Info: Stat;
begin
  Result := (fpLStat(ADir, Info) = 0) and fpS_ISDIR(Info.st_mode) and
    (Info.st_uid = fpGetUID) and ((Info.st_mode and &077) = 0);
end;

{ The temporary folder's gittan-<uid>, made 0700 when it is not there;
  when someone else's or a link is there, a new folder of the user's
  own with a name nobody can tell in advance. The temporary folder
  itself only when no folder can be made, as before. }
function PrivateTempDir: string;
var
  Base, Dir, Name: string;
  i: integer;
begin
  Dir := PrivateTemp;
  if (Dir <> '') and OwnPrivateDir(Dir) then
    Exit(IncludeTrailingPathDelimiter(Dir));
  Base := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-' + IntToStr(fpGetUID);
  fpMkdir(Base, &700);
  if OwnPrivateDir(Base) then
    Dir := Base
  else
  begin
    Dir := '';
    Randomize;
    for i := 1 to 20 do
    begin
      Name := Base + '-' + IntToHex(Random($7FFFFFFF), 8);
      if fpMkdir(Name, &700) = 0 then
      begin
        Dir := Name;
        Break;
      end;
    end;
  end;
  if Dir = '' then
    Exit(IncludeTrailingPathDelimiter(GetTempDir));
  PrivateTemp := Dir;
  Result := IncludeTrailingPathDelimiter(Dir);
end;
{$ENDIF}

function TempFileName(const APrefix: string): string;
begin
  {$IFDEF UNIX}
  Result := PrivateTempDir;
  {$ELSE}
  Result := IncludeTrailingPathDelimiter(GetTempDir);
  {$ENDIF}
  Result := Result + APrefix + IntToStr(GetProcessID) + '-' +
    IntToStr(InterLockedIncrement(WriteCount)) + '.tmp';
  DeleteFile(Result);
end;

function WriteFileReplacing(const AFileName: RawByteString; const AText: RawByteString;
  AMode: integer): boolean;
var
  Name, Temp: RawByteString;
  F: THandle;
begin
  Result := False;
  { The rename would put the new file in the link's place. }
  Name := ThroughLinks(AFileName);
  Temp := Name + '.' + IntToStr(GetProcessID) + '-' +
    IntToStr(InterLockedIncrement(WriteCount)) + '.tmp';
  ForceDirectories(ExtractFileDir(Name));
  { One left by an earlier run with the same process id would keep its
    own mode. }
  DeleteFile(Temp);
  F := FileCreate(Temp, AMode);
  if F = THandle(-1) then
    Exit;
  Result := (AText = '') or (FileWrite(F, AText[1], Length(AText)) = Length(AText));
  { On the disk before the rename: a crash after it could otherwise leave
    the new name on a file whose bytes never got there, and the old one
    gone. }
  { A flush that fails leaves the old file: the new one may not be on
    the disk. }
  if Result then
    Result := FileFlush(F);
  FileClose(F);
  if not Result then
  begin
    DeleteFile(Temp);
    Exit;
  end;
  {$IFDEF WINDOWS}
  { RenameFile does not replace a file on Windows; MoveFileEx does, in
    one step, so the file on disk stays the old one when it fails. }
  Result := MoveFileExW(PWideChar(UTF8Decode(Temp)), PWideChar(UTF8Decode(Name)),
    MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH);
  {$ELSE}
  Result := RenameFile(Temp, Name);
  {$ENDIF}
  if not Result then
    DeleteFile(Temp);
end;

end.
