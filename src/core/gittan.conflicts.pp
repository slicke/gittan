unit gittan.conflicts;

{** The conflicts git leaves in a file it could not merge, read from the
  lines of the file's diff: which lines are the markers, our side, the
  merge base (with merge.conflictStyle diff3 or zdiff3) and their side;
  and one conflict resolved as a block to write over it (ResolveBlock,
  a TGittanDiscard that gittan.discard writes). Nothing here needs the
  LCL; tested in tests/testconflicts.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, gittan.discard;

const
  {** The role of a line, as ConflictRoles answers it. }
  crNone = 0;
  crMarker = 1;
  crOurs = 2;
  crBase = 3;
  crTheirs = 4;

{** The role of every line of ALines, diff lines with their one-character
  prefix (' ', '+' or '-'). A deleted line is never part of a conflict,
  since the conflict is in the work tree. A conflict runs from a
  "<<<<<<<" line through "|||||||" (the base, when there is one) and
  "=======" to ">>>>>>>"; one left open at the end keeps its roles. }
function ConflictRoles(ALines: TStrings): TIntegerDynArray;
{** How many conflicts ConflictRoles found: the "<<<<<<<" lines. }
function ConflictCount(const ARoles: TIntegerDynArray; ALines: TStrings): integer;
{** The diff line of every conflict's "<<<<<<<". }
function ConflictStarts(const ARoles: TIntegerDynArray; ALines: TStrings): TIntegerDynArray;
{** The diff line the conflict that starts at AStart ends on: its
  ">>>>>>>", or its last line while it is open at the end; AStart itself
  for a line that starts no conflict. }
function ConflictEnd(ALines: TStrings; const ARoles: TIntegerDynArray; AStart: integer): integer;

type
  {** What takes the place of a conflict: our side, their side, or both
    in either order. }
  TGittanConflictPick = (cpOurs, cpTheirs, cpOursThenTheirs, cpTheirsThenOurs);

{** The name git wrote after a marker ("<<<<<<< HEAD" gives "HEAD"), ''
  for a bare one. ALine is a diff line, with its prefix. }
function MarkerName(const ALine: string): string;
{** The names on the markers of the conflict that starts at diff line
  AStart: of the "<<<<<<<" (ours) and the ">>>>>>>" (theirs, '' while
  the conflict is open at the end). }
procedure ConflictSides(ALines: TStrings; const ARoles: TIntegerDynArray; AStart: integer;
  out AOurs, ATheirs: string);
{** The conflict that starts at diff line AStart as a block to write:
  NewLines are its lines as they are in the file, the markers, our
  side, the base and their side (a deleted line is not in the file, so
  it is skipped), OldLines what APick puts in their place, and Line
  where the conflict is in the file (1-based). DiscardBlock writes it,
  checking the file still holds the conflict; Swapped puts it back. }
function ResolveBlock(ALines: TStrings; const ARoles: TIntegerDynArray; AStart: integer;
  APick: TGittanConflictPick; const AFileName: string): TGittanDiscard;

implementation

{ A marker is seven of its character at the start of the line, then the
  end of the line or a space (git adds the side's name). }
function IsMarker(const AText: string; AChar: char): boolean;
begin
  Result := (Length(AText) >= 7) and (AText = StringOfChar(AChar, 7) + Copy(AText, 8, MaxInt)) and
    ((Length(AText) = 7) or (AText[8] = ' '));
end;

function ConflictRoles(ALines: TStrings): TIntegerDynArray;
var
  i, State: integer;
  Text: string;
begin
  Result := nil;
  SetLength(Result, ALines.Count);
  State := crNone;
  for i := 0 to ALines.Count - 1 do
  begin
    Result[i] := crNone;
    if (ALines[i] = '') or (ALines[i][1] = '-') then
      Continue;
    Text := Copy(ALines[i], 2, MaxInt);
    if IsMarker(Text, '<') and (State = crNone) then
    begin
      Result[i] := crMarker;
      State := crOurs;
    end
    else if IsMarker(Text, '|') and (State = crOurs) then
    begin
      Result[i] := crMarker;
      State := crBase;
    end
    else if IsMarker(Text, '=') and (State in [crOurs, crBase]) then
    begin
      Result[i] := crMarker;
      State := crTheirs;
    end
    else if IsMarker(Text, '>') and (State = crTheirs) then
    begin
      Result[i] := crMarker;
      State := crNone;
    end
    else
      Result[i] := State;
  end;
end;

function ConflictCount(const ARoles: TIntegerDynArray; ALines: TStrings): integer;
begin
  Result := Length(ConflictStarts(ARoles, ALines));
end;

function ConflictStarts(const ARoles: TIntegerDynArray; ALines: TStrings): TIntegerDynArray;
var
  i, n: integer;
begin
  Result := nil;
  n := 0;
  for i := 0 to Min(High(ARoles), ALines.Count - 1) do
    if (ARoles[i] = crMarker) and IsMarker(Copy(ALines[i], 2, MaxInt), '<') then
    begin
      SetLength(Result, n + 1);
      Result[n] := i;
      Inc(n);
    end;
end;

function MarkerName(const ALine: string): string;
begin
  Result := Trim(Copy(ALine, 9, MaxInt));
end;

{ Whether diff line AIndex is a deleted one, which is not in the file. }
function Deleted(ALines: TStrings; AIndex: integer): boolean;
begin
  Result := (ALines[AIndex] <> '') and (ALines[AIndex][1] = '-');
end;

function ConflictEnd(ALines: TStrings; const ARoles: TIntegerDynArray; AStart: integer): integer;
var
  i: integer;
begin
  Result := AStart;
  if (AStart < 0) or (AStart > High(ARoles)) or (AStart >= ALines.Count) or
    (ARoles[AStart] <> crMarker) or not IsMarker(Copy(ALines[AStart], 2, MaxInt), '<') then
    Exit;
  for i := AStart + 1 to Min(High(ARoles), ALines.Count - 1) do
  begin
    if Deleted(ALines, i) then
      Continue;
    if ARoles[i] = crNone then
      Exit;
    Result := i;
    if (ARoles[i] = crMarker) and IsMarker(Copy(ALines[i], 2, MaxInt), '>') then
      Exit;
  end;
end;

procedure ConflictSides(ALines: TStrings; const ARoles: TIntegerDynArray; AStart: integer;
  out AOurs, ATheirs: string);
var
  i: integer;
begin
  AOurs := '';
  ATheirs := '';
  if (AStart < 0) or (AStart > High(ARoles)) or (AStart >= ALines.Count) or
    (ARoles[AStart] <> crMarker) or not IsMarker(Copy(ALines[AStart], 2, MaxInt), '<') then
    Exit;
  AOurs := MarkerName(ALines[AStart]);
  for i := AStart + 1 to Min(High(ARoles), ALines.Count - 1) do
  begin
    if Deleted(ALines, i) then
      Continue;
    if ARoles[i] = crNone then
      Exit;
    if (ARoles[i] = crMarker) and IsMarker(Copy(ALines[i], 2, MaxInt), '>') then
    begin
      ATheirs := MarkerName(ALines[i]);
      Exit;
    end;
  end;
end;

procedure Append(var ALines: TStringArray; const AText: string);
begin
  SetLength(ALines, Length(ALines) + 1);
  ALines[High(ALines)] := AText;
end;

function ResolveBlock(ALines: TStrings; const ARoles: TIntegerDynArray; AStart: integer;
  APick: TGittanConflictPick; const AFileName: string): TGittanDiscard;
var
  i: integer;
  Ours, Theirs: TStringArray;
  Text: string;
begin
  Result.FileName := AFileName;
  Result.Resolved := False;
  Result.OldLines := nil;
  Result.NewLines := nil;
  Result.Line := 1;
  Ours := nil;
  Theirs := nil;
  for i := 0 to Min(AStart, ALines.Count) - 1 do
    if not Deleted(ALines, i) then
      Inc(Result.Line);
  for i := AStart to Min(High(ARoles), ALines.Count - 1) do
  begin
    if Deleted(ALines, i) then
      Continue;
    if ARoles[i] = crNone then
      Break;
    Text := Copy(ALines[i], 2, MaxInt);
    Append(Result.NewLines, Text);
    case ARoles[i] of
      crOurs: Append(Ours, Text);
      crTheirs: Append(Theirs, Text);
    end;
    if (ARoles[i] = crMarker) and IsMarker(Text, '>') then
      Break;
  end;
  case APick of
    cpOurs: Result.OldLines := Ours;
    cpTheirs: Result.OldLines := Theirs;
    cpOursThenTheirs: Result.OldLines := Concat(Ours, Theirs);
    cpTheirsThenOurs: Result.OldLines := Concat(Theirs, Ours);
  end;
end;

end.
