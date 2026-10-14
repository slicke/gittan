unit gittan.conflicts;

{** The conflicts git leaves in a file it could not merge, read from the
  lines of the file's diff: which lines are the markers, our side, the
  merge base (with merge.conflictStyle diff3 or zdiff3) and their side.
  Nothing here needs the LCL. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math;

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
var
  i: integer;
begin
  Result := 0;
  for i := 0 to Min(High(ARoles), ALines.Count - 1) do
    if (ARoles[i] = crMarker) and IsMarker(Copy(ALines[i], 2, MaxInt), '<') then
      Inc(Result);
end;

end.
