unit gittan.callers;

{** Where the rest of the repository uses the symbols a diff changed: the
  impact of a change, for review. The symbol index knows definitions
  only, so the uses are found by `git grep` for the identifiers as whole
  words over the work tree, and this unit reads what it printed, leaves
  out the files that changed themselves (their uses are in the diff) and
  tells a definition the index knows from a use. A use is a row of a file
  with the identifier on it; the rows of a lexer that reads identifiers
  without regard to case (Pascal, SQL, Basic) are matched that way. The
  words for the symbol bar ("used in 4 files, 7 lines") are made here
  too. Nothing here needs the LCL. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.symbols;

type
  {** One use of a changed symbol: the file (relative to the root, "/"
    separators), the row (0-based), the byte column of the identifier on
    it (0-based), the text of the row, and the index of the identifier in
    the list ParseGrep got. }
  TGittanCaller = record
    Path: string;
    Row, Col: integer;
    Line: string;
    Ident: integer;
  end;
  TGittanCallers = array of TGittanCaller;

{** Whether the lexer named ALexer reads identifiers without regard to
  case: Pascal, SQL, Basic, Fortran, Ada and Cobol in their variants. }
function LexerIgnoresCase(const ALexer: string): boolean;

{** Whether the lexer named ALexer is for prose rather than code
  (Markdown, reStructuredText, AsciiDoc, Textile, plain text): a file of
  it mentions a symbol, it does not call it. }
function LexerIsProse(const ALexer: string): boolean;

{** The uses in AOutput, what `git grep -z -n -w` printed (path, row and
  text, NUL separated, one row per line) when run for the words AIdents:
  one per identifier found as a whole word on a row, in the order of the
  output and, on a row, of the identifiers' places on it. The rows of
  the files in ASkipPaths (nil for none) are left out. }
function ParseGrep(const AOutput: string; AIdents: TStrings; AIgnoreCase: boolean;
  ASkipPaths: TStrings): TGittanCallers;

{** Whether a symbol of ASymbols on row ARow is named by AWord: the row
  defines the word and does not use it. }
function IsDefinitionRow(const ASymbols: TGittanSymbols; ARow: integer; const AWord: string;
  AIgnoreCase: boolean): boolean;

{** The index of the last symbol of ASymbols that starts on or before row
  ARow (the innermost one around it, as the index knows no ends), -1 when
  none does. }
function EnclosingSymbol(const ASymbols: TGittanSymbols; ARow: integer): integer;

{** How many files and rows among ACallers use the identifier AIdent. }
procedure CountCallers(const ACallers: TGittanCallers; AIdent: integer;
  out AFiles, ALines: integer);

{** How many files ACallers span. }
function CallerFileCount(const ACallers: TGittanCallers): integer;

{** "1 file" or "4 files". }
function FilesText(ACount: integer): string;

{** What to say about a changed symbol used in AFiles files on ALines rows:
  "used in 4 files, 7 lines", "removed, still used in 1 file, 1 line" when
  AGone (the symbol or its name is no longer defined), or "not used
  elsewhere". }
function CallersDetail(AFiles, ALines: integer; AGone: boolean): string;

implementation

resourcestring
  rsFile = '%d file';
  rsFiles = '%d files';
  rsLine = '%d line';
  rsLines = '%d lines';
  rsUsedIn = 'used in %s, %s';
  rsStillUsedIn = 'removed, still used in %s, %s';
  rsNotUsedElsewhere = 'not used elsewhere';

{ Whether a word of ALexer (runs of letters and digits, ignoring case)
  is one of AWords. }
function LexerHasWord(const ALexer: string; const AWords: array of string): boolean;
var
  Low, Word: string;
  i, Start, j: integer;
begin
  Result := False;
  Low := LowerCase(ALexer);
  i := 1;
  while i <= Length(Low) do
  begin
    if not (Low[i] in ['a'..'z', '0'..'9']) then
    begin
      Inc(i);
      Continue;
    end;
    Start := i;
    while (i <= Length(Low)) and (Low[i] in ['a'..'z', '0'..'9']) do
      Inc(i);
    Word := Copy(Low, Start, i - Start);
    for j := 0 to High(AWords) do
      if Word = AWords[j] then
        Exit(True);
  end;
end;

function LexerIgnoresCase(const ALexer: string): boolean;
begin
  Result := LexerHasWord(ALexer, ['pascal', 'delphi', 'sql', 'plsql', 'tsql',
    'basic', 'vb', 'vbs', 'vba', 'vbscript', 'fortran', 'ada', 'cobol', 'freebasic']);
end;

function LexerIsProse(const ALexer: string): boolean;
begin
  Result := LexerHasWord(ALexer, ['markdown', 'restructuredtext', 'rst', 'asciidoc',
    'textile', 'text', 'txt', 'org', 'wiki', 'mediawiki', 'changelog']);
end;

function SameWord(const A, B: string; AIgnoreCase: boolean): boolean;
begin
  if AIgnoreCase then
    Result := SameText(A, B)
  else
    Result := A = B;
end;

{ The identifiers of AIdents found as whole words in ALine, each at its
  first place, in the order of those places. }
procedure WordsOn(const ALine: string; AIdents: TStrings; AIgnoreCase: boolean;
  out AFound: TGittanCallers);
var
  Seen: array of boolean;
  i, Start, j, n: integer;
  Word: string;
begin
  AFound := nil;
  n := 0;
  SetLength(Seen, AIdents.Count);
  for j := 0 to High(Seen) do
    Seen[j] := False;
  i := 1;
  while i <= Length(ALine) do
  begin
    if not IsWordChar(ALine[i]) then
    begin
      Inc(i);
      Continue;
    end;
    Start := i;
    while (i <= Length(ALine)) and IsWordChar(ALine[i]) do
      Inc(i);
    Word := Copy(ALine, Start, i - Start);
    for j := 0 to AIdents.Count - 1 do
      if not Seen[j] and SameWord(Word, AIdents[j], AIgnoreCase) then
      begin
        Seen[j] := True;
        SetLength(AFound, n + 1);
        AFound[n].Col := Start - 1;
        AFound[n].Ident := j;
        Inc(n);
        Break;
      end;
  end;
end;

function ParseGrep(const AOutput: string; AIdents: TStrings; AIgnoreCase: boolean;
  ASkipPaths: TStrings): TGittanCallers;
var
  Found: TGittanCallers;
  Path, Text: string;
  Row, p, q, LineStart, LineEnd, n, i: integer;
begin
  Result := nil;
  n := 0;
  LineStart := 1;
  while LineStart <= Length(AOutput) do
  begin
    LineEnd := LineStart;
    while (LineEnd <= Length(AOutput)) and (AOutput[LineEnd] <> #10) do
      Inc(LineEnd);
    { path NUL row NUL text }
    p := LineStart;
    while (p < LineEnd) and (AOutput[p] <> #0) do
      Inc(p);
    q := p + 1;
    while (q < LineEnd) and (AOutput[q] <> #0) do
      Inc(q);
    if q < LineEnd then
    begin
      Path := Copy(AOutput, LineStart, p - LineStart);
      Row := StrToIntDef(Copy(AOutput, p + 1, q - p - 1), 0) - 1;
      Text := Copy(AOutput, q + 1, LineEnd - q - 1);
      if (Text <> '') and (Text[Length(Text)] = #13) then
        SetLength(Text, Length(Text) - 1);
      if (Row >= 0) and ((ASkipPaths = nil) or (ASkipPaths.IndexOf(Path) < 0)) then
      begin
        WordsOn(Text, AIdents, AIgnoreCase, Found);
        if Length(Found) > 0 then
        begin
          SetLength(Result, n + Length(Found));
          for i := 0 to High(Found) do
          begin
            Result[n + i] := Found[i];
            Result[n + i].Path := Path;
            Result[n + i].Row := Row;
            Result[n + i].Line := Text;
          end;
          Inc(n, Length(Found));
        end;
      end;
    end;
    LineStart := LineEnd + 1;
  end;
end;

function IsDefinitionRow(const ASymbols: TGittanSymbols; ARow: integer; const AWord: string;
  AIgnoreCase: boolean): boolean;
var
  i: integer;
begin
  Result := False;
  for i := 0 to High(ASymbols) do
    if (ASymbols[i].Row = ARow) and
      SameWord(NameIdentifier(ASymbols[i].Name), AWord, AIgnoreCase) then
      Exit(True);
end;

function EnclosingSymbol(const ASymbols: TGittanSymbols; ARow: integer): integer;
var
  i: integer;
begin
  Result := -1;
  for i := 0 to High(ASymbols) do
    if ASymbols[i].Row <= ARow then
      Result := i
    else
      Break;
end;

procedure CountCallers(const ACallers: TGittanCallers; AIdent: integer;
  out AFiles, ALines: integer);
var
  Paths: TStringList;
  i: integer;
begin
  AFiles := 0;
  ALines := 0;
  Paths := TStringList.Create;
  try
    Paths.CaseSensitive := True;
    Paths.Sorted := True;
    Paths.Duplicates := dupIgnore;
    for i := 0 to High(ACallers) do
      if ACallers[i].Ident = AIdent then
      begin
        Inc(ALines);
        Paths.Add(ACallers[i].Path);
      end;
    AFiles := Paths.Count;
  finally
    Paths.Free;
  end;
end;

function CallerFileCount(const ACallers: TGittanCallers): integer;
var
  Paths: TStringList;
  i: integer;
begin
  Paths := TStringList.Create;
  try
    Paths.CaseSensitive := True;
    Paths.Sorted := True;
    Paths.Duplicates := dupIgnore;
    for i := 0 to High(ACallers) do
      Paths.Add(ACallers[i].Path);
    Result := Paths.Count;
  finally
    Paths.Free;
  end;
end;

function FilesText(ACount: integer): string;
begin
  if ACount = 1 then
    Result := Format(rsFile, [ACount])
  else
    Result := Format(rsFiles, [ACount]);
end;

function LinesText(ACount: integer): string;
begin
  if ACount = 1 then
    Result := Format(rsLine, [ACount])
  else
    Result := Format(rsLines, [ACount]);
end;

function CallersDetail(AFiles, ALines: integer; AGone: boolean): string;
begin
  if AFiles = 0 then
    Result := rsNotUsedElsewhere
  else if AGone then
    Result := Format(rsStillUsedIn, [FilesText(AFiles), LinesText(ALines)])
  else
    Result := Format(rsUsedIn, [FilesText(AFiles), LinesText(ALines)]);
end;

end.
