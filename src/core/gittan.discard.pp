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
    resolved, so undoing it puts the conflict back in the index too. }
  TGittanDiscard = record
    FileName: string;
    Line: integer;
    OldLines, NewLines: TStringArray;
    Resolved: boolean;
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

function DiffBlock(ALines: TStrings; AStart: integer; const AFileName: string): TGittanDiscard;
var
  i, Old, New: integer;
begin
  Result.FileName := AFileName;
  Result.OldLines := nil;
  Result.NewLines := nil;
  Result.Line := 1;
  Result.Resolved := False;
  for i := 0 to AStart - 1 do
    if ALines[i][1] <> '-' then
      Inc(Result.Line);
  Old := 0;
  New := 0;
  i := AStart;
  while (i < ALines.Count) and (ALines[i][1] <> ' ') do
  begin
    if ALines[i][1] = '-' then
    begin
      SetLength(Result.OldLines, Old + 1);
      Result.OldLines[Old] := Copy(ALines[i], 2, MaxInt);
      Inc(Old);
    end
    else
    begin
      SetLength(Result.NewLines, New + 1);
      Result.NewLines[New] := Copy(ALines[i], 2, MaxInt);
      Inc(New);
    end;
    Inc(i);
  end;
end;

function Swapped(const ABlock: TGittanDiscard): TGittanDiscard;
begin
  Result.FileName := ABlock.FileName;
  Result.Line := ABlock.Line;
  Result.OldLines := ABlock.NewLines;
  Result.NewLines := ABlock.OldLines;
  Result.Resolved := ABlock.Resolved;
end;

function DiscardCount(const ABlock: TGittanDiscard): integer;
begin
  Result := Length(ABlock.OldLines);
  if Result = 0 then
    Result := Length(ABlock.NewLines);
end;

{ A line without the CR a CRLF file ends it with. }
function Bare(const ALine: string): string;
begin
  Result := ALine;
  if (Result <> '') and (Result[Length(Result)] = #13) then
    SetLength(Result, Length(Result) - 1);
end;

function DiscardBlock(const ABlock: TGittanDiscard; out AError: string): boolean;
var
  F: TFileStream;
  Text, Eol: string;
  Lines: TStringList;
  Out: TStringBuilder;
  i, p, Start, Count: integer;
  FinalNewline: boolean;
begin
  Result := False;
  AError := '';
  try
    Text := '';
    if FileExists(ABlock.FileName) then
    begin
      F := TFileStream.Create(ABlock.FileName, fmOpenRead or fmShareDenyNone);
      try
        SetLength(Text, F.Size);
        if F.Size > 0 then
          F.ReadBuffer(Text[1], F.Size);
      finally
        F.Free;
      end;
    end
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
      Start := 1;
      for i := 1 to Length(Text) do
        if Text[i] = #10 then
        begin
          Lines.Add(Copy(Text, Start, i - Start));
          Start := i + 1;
        end;
      if Start <= Length(Text) then
        Lines.Add(Copy(Text, Start, MaxInt));
      Eol := #10;
      if (Lines.Count > 0) and (Lines[0] <> Bare(Lines[0])) then
        Eol := #13#10;
      Count := Length(ABlock.NewLines);
      p := ABlock.Line - 1;
      if (p < 0) or (p + Count > Lines.Count) or ((Count = 0) and (p > Lines.Count)) then
      begin
        AError := rsDiscardStale;
        Exit;
      end;
      for i := 0 to Count - 1 do
        if Bare(Lines[p + i]) <> ABlock.NewLines[i] then
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
