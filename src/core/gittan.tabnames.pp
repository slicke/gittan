unit gittan.tabnames;

{** Names for the tabs and the window's caption that tell apart folders
  of the same name: a name shared with another path gets its parent
  folders in front, as many as it takes ("Projects/trailhead" and
  "conflict/trailhead"), as editors name files open twice. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

{** A name for each of APaths: its last part, with as many of the parts
  before it as tell it apart from the others' names. An empty path
  gets an empty name; the same path twice gets the same name. }
function DistinctNames(const APaths: array of string): TStringArray;

implementation

type
  TParts = array of string;

{ The parts between the delimiters: a slash, and on Windows a backslash
  too; elsewhere a backslash is a character of a name. }
function SplitPath(const APath: string): TParts;
const
  Delims = {$IFDEF WINDOWS}['/', '\']{$ELSE}['/']{$ENDIF};
var
  i, Start: integer;
  S: string;
begin
  Result := nil;
  S := APath + '/';
  Start := 1;
  for i := 1 to Length(S) do
    if S[i] in Delims then
    begin
      if i > Start then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Copy(S, Start, i - Start);
      end;
      Start := i + 1;
    end;
end;

{ The last ADepth of AParts, joined by the path delimiter. }
function Tail(const AParts: TParts; ADepth: integer): string;
var
  i: integer;
begin
  Result := '';
  for i := Length(AParts) - ADepth to High(AParts) do
    if Result = '' then
      Result := AParts[i]
    else
      Result := Result + PathDelim + AParts[i];
end;

function DistinctNames(const APaths: array of string): TStringArray;
var
  Parts: array of TParts;
  Depth: array of integer;
  Grow: array of boolean;
  i, j: integer;
  Again: boolean;
begin
  Result := nil;
  SetLength(Result, Length(APaths));
  SetLength(Parts, Length(APaths));
  SetLength(Depth, Length(APaths));
  SetLength(Grow, Length(APaths));
  for i := 0 to High(APaths) do
  begin
    Parts[i] := SplitPath(APaths[i]);
    Depth[i] := Ord(Length(Parts[i]) > 0);
    Result[i] := Tail(Parts[i], Depth[i]);
  end;
  repeat
    Again := False;
    for i := 0 to High(APaths) do
    begin
      Grow[i] := False;
      if Depth[i] >= Length(Parts[i]) then
        Continue;
      for j := 0 to High(APaths) do
        if (j <> i) and (Result[j] = Result[i]) and (APaths[j] <> APaths[i]) then
        begin
          Grow[i] := True;
          Break;
        end;
    end;
    for i := 0 to High(APaths) do
      if Grow[i] then
      begin
        Inc(Depth[i]);
        Result[i] := Tail(Parts[i], Depth[i]);
        Again := True;
      end;
  until not Again;
end;

end.
