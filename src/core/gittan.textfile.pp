unit gittan.textfile;

{** Small helpers for text as git and the files have it, byte for byte:
  reading a whole file, splitting at LF with the CRs kept, a line
  without its CR, walking the lines of git's output, and undoing the
  backslash escapes the settings, the symbol index and .po files write.
  No LCL; tested in tests/testtextfile.pp. }

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

end.
