unit gittan.worddiff;

{** Word-level differences inside the changed lines of a diff.

  A unified diff colors whole lines, so a changed word in a long line
  leaves the reader to compare the two lines by eye. This unit takes the
  lines of a diff (each with its ' ', '+' or '-' marker) and finds, for
  every run of deleted lines followed by added lines, the tokens the two
  runs do not share: the words, punctuation and spaces that were edited.
  The result is a list of character spans per line, which the editor
  paints in a stronger shade on top of the line's color.

  The two runs are compared as one token sequence each, so lines that were
  joined or split still line up, and a run whose sides share too little
  (a block rewritten rather than edited) gets no spans at all, since
  marking nearly everything would say nothing. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math;

type
  {** A span of a line: Start is the index of its first character, counted
    in UTF-16 units from the start of the line's text without the diff
    marker, as the editor counts its columns. }
  TGittanSpan = record
    Start, Len: integer;
  end;
  TGittanSpans = array of TGittanSpan;
  {** One entry per line of the diff, nil for a line without spans. }
  TGittanLineSpans = array of TGittanSpans;

{** The spans that differ, per line of ALines. Every entry of ALines is a
  diff line with its marker in the first character. With AIgnoreSpace a
  change in the amount of whitespace between two words is not marked. }
procedure WordDiff(ALines: TStrings; AIgnoreSpace: boolean;
  out ASpans: TGittanLineSpans);

implementation

const
  { A run of deleted and added lines longer than this is left alone, as
    is a pair of runs with more token comparisons than MaxCells: the
    common subsequence takes a table with one cell per token pair. }
  MaxBlockLines = 400;
  MaxCells = 4000000;
  { The least share of the text, counted in characters of the words and
    punctuation, that the two runs must have in common for their spans
    to be shown. Below it the block is treated as rewritten. }
  MinCommon = 0.35;

type
  TTokenKind = (tkWord, tkSpace, tkPunct, tkBreak);

  TToken = record
    Line: integer;     // index in ALines
    Start, Len: integer;
    Kind: TTokenKind;
    Text: UnicodeString;
    Matched: boolean;
  end;
  TTokens = array of TToken;

function IsWordChar(C: WideChar): boolean; inline;
begin
  Result := ((C >= '0') and (C <= '9')) or ((C >= 'A') and (C <= 'Z')) or
    ((C >= 'a') and (C <= 'z')) or (C = '_') or (Ord(C) > 127);
end;

function IsSpaceChar(C: WideChar): boolean; inline;
begin
  Result := (C = ' ') or (C = #9);
end;

{ The tokens of the diff lines AFrom..ATo, marker left out: runs of word
  characters, runs of spaces and tabs, single other characters, and a
  break token at the end of every line so that line ends line up too. }
procedure Tokenize(ALines: TStrings; AFrom, ATo: integer; var ATokens: TTokens);
var
  S: UnicodeString;
  i, p, q, n: integer;
  Kind: TTokenKind;

  procedure Add(AStart, ALen: integer; AKind: TTokenKind);
  begin
    if n = Length(ATokens) then
      SetLength(ATokens, Max(16, n * 2));
    ATokens[n].Line := i;
    ATokens[n].Start := AStart;
    ATokens[n].Len := ALen;
    ATokens[n].Kind := AKind;
    ATokens[n].Text := Copy(S, AStart + 1, ALen);
    ATokens[n].Matched := False;
    Inc(n);
  end;

begin
  n := Length(ATokens);
  for i := AFrom to ATo do
  begin
    S := UTF8Decode(Copy(ALines[i], 2, MaxInt));
    p := 0;
    while p < Length(S) do
    begin
      if IsWordChar(S[p + 1]) then
        Kind := tkWord
      else if IsSpaceChar(S[p + 1]) then
        Kind := tkSpace
      else
        Kind := tkPunct;
      q := p + 1;
      if Kind <> tkPunct then
        while (q < Length(S)) and
          (((Kind = tkWord) and IsWordChar(S[q + 1])) or
            ((Kind = tkSpace) and IsSpaceChar(S[q + 1]))) do
          Inc(q);
      Add(p, q - p, Kind);
      p := q;
    end;
    Add(Length(S), 0, tkBreak);
  end;
  SetLength(ATokens, n);
end;

function SameToken(const A, B: TToken; AIgnoreSpace: boolean): boolean; inline;
begin
  if A.Kind <> B.Kind then
    Exit(False);
  if AIgnoreSpace and (A.Kind = tkSpace) then
    Exit(True);
  Result := A.Text = B.Text;
end;

{ Marks the tokens of a longest common subsequence of AOld and ANew as
  matched. Returns the number of characters matched, breaks and spaces
  left out. }
function MatchTokens(var AOld, ANew: TTokens; AIgnoreSpace: boolean): integer;
var
  n, m, i, j, w: integer;
  Table: array of word;   // (n + 1) * (m + 1), LCS length of the suffixes
begin
  Result := 0;
  n := Length(AOld);
  m := Length(ANew);
  w := m + 1;
  SetLength(Table, (n + 1) * w);
  for i := 0 to n do
    Table[i * w + m] := 0;
  for j := 0 to m do
    Table[n * w + j] := 0;
  for i := n - 1 downto 0 do
    for j := m - 1 downto 0 do
      if SameToken(AOld[i], ANew[j], AIgnoreSpace) then
        Table[i * w + j] := Table[(i + 1) * w + j + 1] + 1
      else
        Table[i * w + j] := Max(Table[(i + 1) * w + j], Table[i * w + j + 1]);
  i := 0;
  j := 0;
  while (i < n) and (j < m) do
    if SameToken(AOld[i], ANew[j], AIgnoreSpace) then
    begin
      AOld[i].Matched := True;
      ANew[j].Matched := True;
      if not (AOld[i].Kind in [tkSpace, tkBreak]) then
        Inc(Result, AOld[i].Len);
      Inc(i);
      Inc(j);
    end
    else if Table[(i + 1) * w + j] >= Table[i * w + j + 1] then
      Inc(i)
    else
      Inc(j);
end;

{ The characters of the words and punctuation in ATokens. }
function TextLength(const ATokens: TTokens): integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to High(ATokens) do
    if not (ATokens[i].Kind in [tkSpace, tkBreak]) then
      Inc(Result, ATokens[i].Len);
end;

{ The unmatched tokens as spans of their lines. Adjacent spans are joined,
  also over matched spaces between them, so an edited phrase is one
  mark rather than a word-by-word stipple. }
procedure CollectSpans(const ATokens: TTokens; var ASpans: TGittanLineSpans);
var
  i, Line, SpaceEnd: integer;
  Open: boolean;
  Cur: TGittanSpan;

  procedure Close;
  begin
    if Open and (Cur.Len > 0) then
    begin
      SetLength(ASpans[Line], Length(ASpans[Line]) + 1);
      ASpans[Line][High(ASpans[Line])] := Cur;
    end;
    Open := False;
  end;

begin
  Open := False;
  Cur := Default(TGittanSpan);
  Line := -1;
  SpaceEnd := -1;
  for i := 0 to High(ATokens) do
  begin
    if ATokens[i].Line <> Line then
    begin
      Close;
      Line := ATokens[i].Line;
      SpaceEnd := -1;
    end;
    if ATokens[i].Matched or (ATokens[i].Kind = tkBreak) then
    begin
      { A matched run of spaces right after a span may be bridged by the
        next unmatched token; anything else ends the span. }
      if Open and (ATokens[i].Kind = tkSpace) and
        (ATokens[i].Start = Cur.Start + Cur.Len) and (SpaceEnd < 0) then
        SpaceEnd := ATokens[i].Start + ATokens[i].Len
      else
      begin
        Close;
        SpaceEnd := -1;
      end;
      Continue;
    end;
    if Open and ((ATokens[i].Start = Cur.Start + Cur.Len) or
      (ATokens[i].Start = SpaceEnd)) then
      Cur.Len := ATokens[i].Start + ATokens[i].Len - Cur.Start
    else
    begin
      Close;
      Cur.Start := ATokens[i].Start;
      Cur.Len := ATokens[i].Len;
      Open := True;
    end;
    SpaceEnd := -1;
  end;
  Close;
end;

procedure WordDiff(ALines: TStrings; AIgnoreSpace: boolean;
  out ASpans: TGittanLineSpans);
var
  n, i, d0, a0, Common, Total: integer;
  OldTokens, NewTokens: TTokens;
begin
  n := ALines.Count;
  SetLength(ASpans, n);
  for i := 0 to n - 1 do
    ASpans[i] := nil;
  i := 0;
  while i < n do
  begin
    if (ALines[i] = '') or (ALines[i][1] <> '-') then
    begin
      Inc(i);
      Continue;
    end;
    d0 := i;
    while (i < n) and (ALines[i] <> '') and (ALines[i][1] = '-') do
      Inc(i);
    a0 := i;
    while (i < n) and (ALines[i] <> '') and (ALines[i][1] = '+') do
      Inc(i);
    if (i = a0) or (i - d0 > MaxBlockLines) then
      Continue;
    OldTokens := nil;
    NewTokens := nil;
    Tokenize(ALines, d0, a0 - 1, OldTokens);
    Tokenize(ALines, a0, i - 1, NewTokens);
    if Int64(Length(OldTokens) + 1) * (Length(NewTokens) + 1) > MaxCells then
      Continue;
    Common := MatchTokens(OldTokens, NewTokens, AIgnoreSpace);
    Total := TextLength(OldTokens) + TextLength(NewTokens);
    if (Total = 0) or (2 * Common < MinCommon * Total) then
      Continue;
    CollectSpans(OldTokens, ASpans);
    CollectSpans(NewTokens, ASpans);
  end;
end;

end.
