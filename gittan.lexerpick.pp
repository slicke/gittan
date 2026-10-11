unit gittan.lexerpick;

{** Picking one lexer for a file whose extension several lexers claim.

  The lexer collection has 44 such extensions: ".inc" is claimed by Pascal
  and five assemblers, ".h" by C++ and CUDA, ".sql" by six dialects.
  EControl takes the first in alphabetical order, so a Pascal include
  file got "Assembly AVR". The files beside the one in question tell what
  the folder is about: the lexers of the sibling files vote, and the
  candidate with the most votes wins. A folder without a say falls back
  to a short table of preferences, then to EControl's order. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

{** Adds the lower-case extension (without the dot) of every file in ADir
  other than those with extension AExt to AList, one entry per file, up
  to AMax files. }
procedure SiblingExtensions(const ADir, AExt: string; AList: TStrings; AMax: integer);

{** The index in ACandidates of the name that occurs most in AVotes, or
  -1 when no candidate occurs or two share the lead. Names are compared
  ignoring case. }
function MostVoted(AVotes, ACandidates: TStrings): integer;

{** The preferred lexer name for an ambiguous extension (lower case,
  without the dot), or '' when there is none. }
function PreferredLexer(const AExt: string): string;

implementation

procedure SiblingExtensions(const ADir, AExt: string; AList: TStrings; AMax: integer);
var
  Info: TSearchRec;
  Ext: string;
  Seen: integer;
begin
  if (ADir = '') or (AMax <= 0) then
    Exit;
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, Info) <> 0 then
    Exit;
  try
    Seen := 0;
    repeat
      if (Info.Attr and faDirectory) <> 0 then
        Continue;
      Inc(Seen);
      if Seen > AMax then
        Break;
      Ext := LowerCase(ExtractFileExt(Info.Name));
      if (Ext <> '') and (Ext[1] = '.') then
        Delete(Ext, 1, 1);
      if (Ext <> '') and not SameText(Ext, AExt) then
        AList.Add(Ext);
    until FindNext(Info) <> 0;
  finally
    FindClose(Info);
  end;
end;

function MostVoted(AVotes, ACandidates: TStrings): integer;
var
  Counts: array of integer;
  i, j, Best: integer;
begin
  Result := -1;
  SetLength(Counts, ACandidates.Count);
  for i := 0 to High(Counts) do
    Counts[i] := 0;
  for i := 0 to AVotes.Count - 1 do
    for j := 0 to ACandidates.Count - 1 do
      if SameText(AVotes[i], ACandidates[j]) then
        Inc(Counts[j]);
  Best := 0;
  for i := 0 to High(Counts) do
    if Counts[i] > Best then
    begin
      Best := Counts[i];
      Result := i;
    end
    else if (Counts[i] = Best) and (Best > 0) then
      Result := -1;
end;

function PreferredLexer(const AExt: string): string;
const
  Table: array[0..5] of record Ext, Lexer: string; end = (
    (Ext: 'inc'; Lexer: 'Pascal'),
    (Ext: 'p'; Lexer: 'Pascal'),
    (Ext: 'h'; Lexer: 'C++'),
    (Ext: 'c'; Lexer: 'C'),
    (Ext: 'sql'; Lexer: 'SQL'),
    (Ext: 'm'; Lexer: 'Objective-C'));
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Table) do
    if SameText(Table[i].Ext, AExt) then
      Exit(Table[i].Lexer);
end;

end.
