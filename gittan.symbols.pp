unit gittan.symbols;

{** Matching a word against the names of a lexer's code tree.

  EControl lexers name their tree ranges in their own ways: a Pascal
  method is "TForm1.GoToChange", a C function "foo(int a, char b)", a
  JavaScript class "class Foo". So a name is taken as its identifiers
  (runs of letters, digits and underscores; a non-ASCII byte counts as a
  letter) and the word matches when it equals one of them. A match in
  the part before the first parenthesis (the name itself, not a
  parameter) and a match with the same case rank higher. }

{$mode objfpc}{$H+}

interface

const
  { The ranks SymbolRank answers; a higher one is a better match. }
  srNone = 0;
  srAnywhere = 1;
  srNameIgnoringCase = 2;
  srName = 3;

{** How well the code tree name AName stands for the word AWord. }
function SymbolRank(const AName, AWord: string): integer;

{** The identifier that names the symbol in the code tree name AName:
  the last one before the first parenthesis ("foo" in "func foo(int a)",
  "Bar" in "TFoo.Bar", "Foo" in "class Foo"), or '' when there is none. }
function NameIdentifier(const AName: string): string;

implementation

uses
  SysUtils;

function IsWordChar(C: char): boolean;
begin
  Result := C in ['A'..'Z', 'a'..'z', '0'..'9', '_', #128..#255];
end;

function SymbolRank(const AName, AWord: string): integer;
var
  i, Start, ParenAt: integer;
  Ident: string;
  Rank: integer;
begin
  Result := srNone;
  if (AName = '') or (AWord = '') then
    Exit;
  ParenAt := Pos('(', AName);
  if ParenAt = 0 then
    ParenAt := Length(AName) + 1;
  i := 1;
  while i <= Length(AName) do
  begin
    if not IsWordChar(AName[i]) then
    begin
      Inc(i);
      Continue;
    end;
    Start := i;
    while (i <= Length(AName)) and IsWordChar(AName[i]) do
      Inc(i);
    Ident := Copy(AName, Start, i - Start);
    if not SameText(Ident, AWord) then
      Continue;
    if Start >= ParenAt then
      Rank := srAnywhere
    else if Ident = AWord then
      Rank := srName
    else
      Rank := srNameIgnoringCase;
    if Rank > Result then
      Result := Rank;
  end;
end;

function NameIdentifier(const AName: string): string;
var
  i, Start, ParenAt: integer;
begin
  Result := '';
  ParenAt := Pos('(', AName);
  if ParenAt = 0 then
    ParenAt := Length(AName) + 1;
  i := 1;
  while i < ParenAt do
  begin
    if not IsWordChar(AName[i]) then
    begin
      Inc(i);
      Continue;
    end;
    Start := i;
    while (i < ParenAt) and IsWordChar(AName[i]) do
      Inc(i);
    Result := Copy(AName, Start, i - Start);
  end;
end;

end.
