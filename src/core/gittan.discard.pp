unit gittan.discard;

{** Discarding one block of changes in a file on disk: the lines the
  diff shows as added are replaced by the lines it shows as deleted, so
  the block goes back to how it is in the version compared against. The
  file is written by line numbers, not from the diff's text, since the
  diff may have been taken with whitespace ignored; the lines to replace
  are checked against the diff first, so a file that changed since the
  diff was taken is left alone. Its line ends (LF or CRLF) and whether
  it ends with a newline are kept. No LCL; tested in tests/testdiscard.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  {** One block of changed lines as the diff shows it: the lines of the
    version compared against (deleted, OldLines) and the lines in their
    place now (added, NewLines), and Line, where the latter start in
    the file as it is (1-based; where the old lines go when nothing was
    added, which may be one past the last line). Discarding the block
    writes the old lines over the new; undoing that is the same block
    with the two swapped (see Swapped). Resolved is the caller's: the
    write took the file's last conflict and the file was marked
    resolved, so undoing it puts the conflict back in the index too.
    Before and After are the lines on either side of NewLines in the
    file, '=' and the line, '^' for the start or '$' for the end of the
    file, '' for not known: a block that adds nothing (a deletion put
    back, or the undo of a discarded addition) has no line of its own
    to check, so they are what tells that the file moved since.
    EndsKnown is set by DiffBlock alone: then OldEndsBare and NewEndsBare
    tell whether the last of OldLines, NewLines ends its side of the
    diff without a newline, which a block at the end of the file writes
    (else the file's own last newline is kept). }
  TGittanDiscard = record
    FileName: string;
    Line: integer;
    OldLines, NewLines: TStringArray;
    Resolved: boolean;
    Before, After: string;
    EndsKnown, OldEndsBare, NewEndsBare: boolean;
  end;

const
  {** The error when the file's lines are not the diff's any more. }
  rsDiscardStale = 'the file changed since the diff was taken';
  rsDiscardNoFile = 'the file is gone';

{** The block of ALines (a diff with ' ', '+' and '-' markers in column
  1, the whole file as context) that starts at diff line AStart: its
  deleted and added lines up to the next unchanged line, and where the
  added lines are in the new file. AFileName is kept for the write. }
function DiffBlock(ALines: TStrings; AStart: integer; const AFileName: string): TGittanDiscard;

{** Writes ABlock.OldLines in place of ABlock.NewLines in the file. False
  with the reason in AError when the file does not hold NewLines at
  Line (rsDiscardStale), when it is gone (rsDiscardNoFile; a file with
  nothing added and Line 1 is made, which brings a deleted file back) or
  when the write fails. }
function DiscardBlock(const ABlock: TGittanDiscard; out AError: string): boolean;

{** The block with its old and new lines swapped: discarding it puts the
  change back. }
function Swapped(const ABlock: TGittanDiscard): TGittanDiscard;

{** The lines of the block as a count for a message: the lines put back,
  or the lines removed when nothing is put back. }
function DiscardCount(const ABlock: TGittanDiscard): integer;

implementation

uses
  gittan.textfile;

function DiffBlock(ALines: TStrings; AStart: integer; const AFileName: string): TGittanDiscard;
var
  i, Old, New: integer;
begin
  Result.FileName := AFileName;
  Result.OldLines := nil;
  Result.NewLines := nil;
  Result.Line := 1;
  Result.Resolved := False;
  Result.EndsKnown := True;
  Result.OldEndsBare := False;
  Result.NewEndsBare := False;
  for i := 0 to AStart - 1 do
    if ALines[i][1] <> '-' then
      Inc(Result.Line);
  Result.Before := '^';
  i := AStart - 1;
  while (i >= 0) and (ALines[i][1] = '-') do
    Dec(i);
  if i >= 0 then
    Result.Before := '=' + Copy(ALines[i], 2, MaxInt);
  Old := 0;
  New := 0;
  i := AStart;
  while (i < ALines.Count) and (ALines[i][1] <> ' ') do
  begin
    if ALines[i][1] = '-' then
    begin
      SetLength(Result.OldLines, Old + 1);
      Result.OldLines[Old] := Copy(ALines[i], 2, MaxInt);
      Result.OldEndsBare := HasNoNewline(ALines, i);
      Inc(Old);
    end
    else
    begin
      SetLength(Result.NewLines, New + 1);
      Result.NewLines[New] := Copy(ALines[i], 2, MaxInt);
      Result.NewEndsBare := HasNoNewline(ALines, i);
      Inc(New);
    end;
    Inc(i);
  end;
  if i < ALines.Count then
    Result.After := '=' + Copy(ALines[i], 2, MaxInt)
  else
    Result.After := '$';
end;

function Swapped(const ABlock: TGittanDiscard): TGittanDiscard;
begin
  Result.FileName := ABlock.FileName;
  Result.Line := ABlock.Line;
  Result.OldLines := ABlock.NewLines;
  Result.NewLines := ABlock.OldLines;
  Result.Resolved := ABlock.Resolved;
  Result.Before := ABlock.Before;
  Result.After := ABlock.After;
  Result.EndsKnown := ABlock.EndsKnown;
  Result.OldEndsBare := ABlock.NewEndsBare;
  Result.NewEndsBare := ABlock.OldEndsBare;
end;

function DiscardCount(const ABlock: TGittanDiscard): integer;
begin
  Result := Length(ABlock.OldLines);
  if Result = 0 then
    Result := Length(ABlock.NewLines);
end;

{ The diff may have been taken with whitespace ignored, which shows an
  unchanged line as the version compared against has it, so a line
  beside the block is matched without its blanks. }
function LooseSame(const A, B: string): boolean;

  function Squeezed(const S: string): string;
  var
    i, n: integer;
  begin
    SetLength(Result, Length(S));
    n := 0;
    for i := 1 to Length(S) do
      if not (S[i] in [' ', #9, #11, #12, #13]) then
      begin
        Inc(n);
        Result[n] := S[i];
      end;
    SetLength(Result, n);
  end;

begin
  Result := Squeezed(A) = Squeezed(B);
end;

{ Whether the line beside the block, as ABeside gives it, is the file's
  line AIndex (-1 or Lines.Count for none there). }
function BesideHolds(Lines: TStrings; AIndex: integer; const ABeside: string): boolean;
begin
  if ABeside = '' then
    Exit(True);
  if (ABeside = '^') or (ABeside = '$') then
    Exit((AIndex < 0) or (AIndex >= Lines.Count));
  Result := (AIndex >= 0) and (AIndex < Lines.Count) and
    LooseSame(Lines[AIndex], Copy(ABeside, 2, MaxInt));
end;

function DiscardBlock(const ABlock: TGittanDiscard; out AError: string): boolean;
var
  F: TFileStream;
  Text, Eol: string;
  Lines: TStringList;
  Out: TStringBuilder;
  i, p, Count: integer;
  FinalNewline: boolean;
begin
  Result := False;
  AError := '';
  try
    Text := '';
    if FileExists(ABlock.FileName) then
      Text := ReadFileBytes(ABlock.FileName)
    else if (ABlock.Line <> 1) or (Length(ABlock.NewLines) > 0) then
    begin
      AError := rsDiscardNoFile;
      Exit;
    end;
    { The lines as they are, each with the CR it may end with, split at
      LF; the file's line end is that of its first line, LF for a file
      without one. }
    Lines := TStringList.Create;
    Out := TStringBuilder.Create;
    try
      FinalNewline := (Text = '') or (Text[Length(Text)] = #10);
      { A block at the end of the file ends it as its old side did: git
        marks a last line without a newline. A block with no old lines
        leaves the line before it last, which had one, or it would have
        been in the block. }
      if ABlock.EndsKnown and (ABlock.After = '$') then
        FinalNewline := (Length(ABlock.OldLines) = 0) or not ABlock.OldEndsBare;
      SplitLf(Text, Lines);
      Eol := #10;
      if (Lines.Count > 0) and (Lines[0] <> BareLine(Lines[0])) then
        Eol := #13#10;
      Count := Length(ABlock.NewLines);
      p := ABlock.Line - 1;
      if (p < 0) or (p + Count > Lines.Count) or ((Count = 0) and (p > Lines.Count)) then
      begin
        AError := rsDiscardStale;
        Exit;
      end;
      for i := 0 to Count - 1 do
        if BareLine(Lines[p + i]) <> ABlock.NewLines[i] then
        begin
          AError := rsDiscardStale;
          Exit;
        end;
      if not BesideHolds(Lines, p - 1, ABlock.Before) or
        not BesideHolds(Lines, p + Count, ABlock.After) then
      begin
        AError := rsDiscardStale;
        Exit;
      end;
      for i := 0 to p - 1 do
        Out.Append(Lines[i]).Append(#10);
      for i := 0 to High(ABlock.OldLines) do
        Out.Append(ABlock.OldLines[i]).Append(Eol);
      for i := p + Count to Lines.Count - 1 do
        Out.Append(Lines[i]).Append(#10);
      Text := Out.ToString;
      if (Text <> '') and not FinalNewline then
      begin
        { The last line had no newline, and the one in its place gets none. }
        if Copy(Text, Length(Text) - 1, 2) = #13#10 then
          SetLength(Text, Length(Text) - 2)
        else
          SetLength(Text, Length(Text) - 1);
      end;
      F := TFileStream.Create(ABlock.FileName, fmCreate or fmShareDenyWrite);
      try
        if Text <> '' then
          F.WriteBuffer(Text[1], Length(Text));
      finally
        F.Free;
      end;
      Result := True;
    finally
      Out.Free;
      Lines.Free;
    end;
  except
    on E: Exception do
      AError := E.Message;
  end;
end;

end.
