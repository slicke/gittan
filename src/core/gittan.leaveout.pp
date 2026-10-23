unit gittan.leaveout;

{** Leaving changes out of a commit: a file whose changes are not all
  to be committed is committed as the work tree has it with the changes
  left out put back as HEAD has them. A change left out is a pair of a
  block, as a keep is (gittan.keep): the k-th deleted line with the k-th
  added line, a deleted line past the added ones, or an added line past
  the deleted ones; it is kept by its content and found again in a fresh
  diff by it (MatchKeeps), so it survives the diff being taken again and
  goes by itself when its lines are gone. LeaveOutText writes the file
  by its lines, as DiscardBlock does, not from the diff's text, since
  the diff may have been taken with whitespace ignored: the added lines
  are checked against the file first, so a file that changed since the
  diff was taken is not committed with the wrong lines, and its line
  ends (LF or CRLF) and whether it ends with a newline are kept. No LCL;
  tested in tests/testleaveout.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, gittan.keep;

{** The text to commit for a file: AText, the file as it is, with the
  pairs of ALeftOut found in ALines (its diff against HEAD, the whole
  file as context, ' ', '-' and '+' markers in column 1) as HEAD has
  them: a left out pair's deleted line is put back and its added line
  taken out. AFound is how many of ALeftOut the diff holds. False with
  rsDiscardStale in AError when the file's lines are not the diff's. }
function LeaveOutText(const AText: RawByteString; ALines: TStrings;
  const ALeftOut: array of TGittanKeep; out AResult: RawByteString;
  out AFound: integer; out AError: string): boolean;

{** Whether ALeftOut leaves out every pair of ALines, so nothing of the
  file would be committed. False for a diff without changes. }
function AllLeftOut(ALines: TStrings; const ALeftOut: array of TGittanKeep): boolean;

implementation

uses
  gittan.discard, gittan.textfile;

function LeaveOutText(const AText: RawByteString; ALines: TStrings;
  const ALeftOut: array of TGittanKeep; out AResult: RawByteString;
  out AFound: integer; out AError: string): boolean;
var
  FileLines: TStringList;
  Out: TStringBuilder;
  Match: TIntegerDynArray;
  Pairs: TGittanKeepArray;
  Found: array of boolean;
  Cr: string;
  i, k, Old, Next, Left, Emitted: integer;
  FinalNewline: boolean;

  procedure Emit(const ALine: string);
  begin
    if Emitted > 0 then
      Out.Append(#10);
    Out.Append(ALine);
    Inc(Emitted);
  end;

  { The file's next line, which must be the added line ANew; it is put
    in the result when AUse is set. False when it is not there. }
  function Take(const ANew: string; AUse: boolean): boolean;
  begin
    Result := (Next < FileLines.Count) and (BareLine(FileLines[Next]) = ANew);
    if not Result then
      Exit;
    if AUse then
      Emit(FileLines[Next]);
    Inc(Next);
  end;

begin
  Result := False;
  AResult := '';
  AFound := 0;
  AError := rsDiscardStale;
  Match := MatchKeeps(ALines, ALeftOut);
  Found := nil;
  SetLength(Found, Length(ALeftOut));
  for i := 0 to High(Match) do
    if (Match[i] >= 0) and not Found[Match[i]] then
    begin
      Found[Match[i]] := True;
      Inc(AFound);
    end;
  FileLines := TStringList.Create;
  Out := TStringBuilder.Create;
  try
    { The lines as they are, each with the CR it may end with, split at
      LF; a line put back gets the CR when the file's first line has
      one. }
    FinalNewline := (AText = '') or (AText[Length(AText)] = #10);
    SplitLf(AText, FileLines);
    Cr := '';
    if (FileLines.Count > 0) and (FileLines[0] <> BareLine(FileLines[0])) then
      Cr := #13;
    Next := 0;
    Emitted := 0;
    i := 0;
    while i < ALines.Count do
    begin
      if ALines[i][1] = ' ' then
      begin
        { A context line is not checked: with whitespace ignored, git
          may show it as HEAD has it. }
        if Next >= FileLines.Count then
          Exit;
        Emit(FileLines[Next]);
        Inc(Next);
        Inc(i);
        Continue;
      end;
      Pairs := BlockPairs(ALines, i);
      Old := 0;
      while (i + Old < ALines.Count) and (ALines[i + Old][1] = '-') do
        Inc(Old);
      for k := 0 to High(Pairs) do
      begin
        if Pairs[k].HasOld then
          Left := Match[i + k]
        else
          Left := Match[i + Old + k];
        if Left >= 0 then
        begin
          if Pairs[k].HasOld then
            Emit(Pairs[k].Old + Cr);
          if Pairs[k].HasNew and not Take(Pairs[k].New, False) then
            Exit;
        end
        else if Pairs[k].HasNew and not Take(Pairs[k].New, True) then
          Exit;
      end;
      while (i < ALines.Count) and (ALines[i][1] <> ' ') do
        Inc(i);
    end;
    if Next <> FileLines.Count then
      Exit;
    if (Emitted > 0) and FinalNewline then
      Out.Append(#10);
    AResult := Out.ToString;
    AError := '';
    Result := True;
  finally
    Out.Free;
    FileLines.Free;
  end;
end;

function AllLeftOut(ALines: TStrings; const ALeftOut: array of TGittanKeep): boolean;
var
  Match: TIntegerDynArray;
  i: integer;
begin
  Match := MatchKeeps(ALines, ALeftOut);
  Result := False;
  for i := 0 to ALines.Count - 1 do
    if ALines[i][1] <> ' ' then
    begin
      if Match[i] < 0 then
        Exit(False);
      Result := True;
    end;
end;

end.
