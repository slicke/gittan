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
  Classes, SysUtils;

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

{** Writes AText as the whole of AFileName, creating its folder: into a
  temporary file beside it first (AFileName, the process id, a count of
  the writes and .tmp, so two writers never share one), then renamed over
  it in one step, so a failed or cut write leaves the old file as it
  was. AMode is the new file's permissions on Unix (&600 for one with a
  secret in it), less the umask; Windows has none. False when it could
  not be written. }
function WriteFileReplacing(const AFileName: RawByteString; const AText: RawByteString;
  AMode: integer = &644): boolean;

implementation

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

function WriteFileReplacing(const AFileName: RawByteString; const AText: RawByteString;
  AMode: integer): boolean;
var
  Temp: RawByteString;
  F: THandle;
begin
  Result := False;
  Temp := AFileName + '.' + IntToStr(GetProcessID) + '-' +
    IntToStr(InterLockedIncrement(WriteCount)) + '.tmp';
  ForceDirectories(ExtractFileDir(AFileName));
  { One left by an earlier run with the same process id would keep its
    own mode. }
  DeleteFile(Temp);
  F := FileCreate(Temp, AMode);
  if F = THandle(-1) then
    Exit;
  Result := (AText = '') or (FileWrite(F, AText[1], Length(AText)) = Length(AText));
  FileClose(F);
  if not Result then
  begin
    DeleteFile(Temp);
    Exit;
  end;
  {$IFDEF WINDOWS}
  { RenameFile does not replace a file on Windows; MoveFileEx does, in
    one step, so the file on disk stays the old one when it fails. }
  Result := MoveFileExW(PWideChar(UTF8Decode(Temp)), PWideChar(UTF8Decode(AFileName)),
    MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH);
  {$ELSE}
  Result := RenameFile(Temp, AFileName);
  {$ENDIF}
  if not Result then
    DeleteFile(Temp);
end;

end.
