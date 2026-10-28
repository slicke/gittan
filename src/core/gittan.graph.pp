unit gittan.graph;

{** The commit graph's layout: which lane, a column, each commit sits in
  and the lines that join it to its parents, row by row, for the list of
  commits git log gives in topological order, newest first.

  Every lane waits for the commit it leads to next. A commit takes the
  leftmost lane that waits for it (a new one, the lowest free, when
  none does: a branch's tip), and every other lane that waits for it
  ends in it. Its first parent then continues in its lane, or joins a
  lane left of it that already waits for that parent; each other parent
  (a merge) goes to the lane that waits for it or to a new lane. A lane keeps its
  color from where it starts to where it ends.

  A row is drawn as two halves: the top half from the top of the row to
  the commit's center, the bottom half from there to the bottom of the
  row, each a list of straight lines from one lane to another. No LCL,
  so it is tested on its own. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types;

type
  {** What a ref on a commit is: the branch HEAD is on (or HEAD itself
    when it is detached), another local branch, a remote-tracking branch,
    a tag, or a bisect's mark, named "bad", "good" or "skip". }
  TGittanRefKind = (grHead, grBranch, grRemote, grTag, grBisect);

  TGittanGraphRef = record
    Name: string;
    Kind: TGittanRefKind;
  end;
  TGittanGraphRefs = array of TGittanGraphRef;

  {** A line within half a row, from lane FromLane to lane ToLane, in
    the lane color Color. }
  TGittanGraphEdge = record
    FromLane, ToLane, Color: integer;
  end;
  TGittanGraphEdges = array of TGittanGraphEdge;

  {** A commit of the graph: what git log gives (the id, the short id,
    the parents' ids, the author, the commit time in UTC, the subject,
    the rest of the message and the refs on it), whether it is on HEAD and not on its upstream
    (not pushed) or the other way round (not pulled), and from
    LayoutGraph its lane, its color and the lines of its row. }
  TGittanGraphCommit = record
    Hash, Short, Author, Subject, Body: string;
    Parents: TStringArray;
    Date: TDateTime;
    Refs: TGittanGraphRefs;
    Unpushed, Unpulled: boolean;
    Lane, Color: integer;
    TopEdges, BottomEdges: TGittanGraphEdges;
  end;
  TGittanGraphCommits = array of TGittanGraphCommit;

  {** What the graph's search field asks for, read by ParseGraphFilter:
    the words every commit shown must have (in its subject, its body,
    its author or its id), the authors it may be by (one must match
    when there are any), the first moment its time may be (Since) and
    the first it may not (Before), both in local time and 0 for no
    bound, the paths it must touch, and the changes its diff must make
    (git log -S, or -G for a /regex/; see gittan.pickaxe). The words
    and the authors are kept as typed: a caller that wants no case
    folds them and the texts it matches with MatchesGraphFilter the
    same way. }
  TGittanGraphFilter = record
    Words, Authors, Paths, Changes: TStringArray;
    Since, Before: TDateTime;
  end;

{** Lays out ACommits, newest first and every commit before its parents,
  setting each one's Lane, Color, TopEdges and BottomEdges. A parent
  not in the list keeps its lane open to the end. Colors count up from
  0 as lanes start; the caller takes them modulo its palette. }
procedure LayoutGraph(var ACommits: TGittanGraphCommits);

{** The number of lanes the widest row uses. }
function GraphWidth(const ACommits: TGittanGraphCommits): integer;

{** The refs git log prints with --decorate=full in %D ("HEAD ->
  refs/heads/main, refs/remotes/origin/main, tag: refs/tags/v1"), short
  names and kinds, in that order; a remote's HEAD is left out. }
function ParseGraphRefs(const ADecoration: string): TGittanGraphRefs;

{** Reads AText as words separated by spaces, double quotes keeping a
  phrase together ("path:my file.txt", or path:"my file.txt"), with
  "author:", "since:" (or "after:"), "until:" (or "before:"), "path:"
  and "change:" naming a part; the names are read in any case. A date is a
  year, a year and month or a day (2024, 2024-06, 2024-06-15); since
  is from its start, until to its end. A part with nothing after the
  colon, or a date that does not read as one yet, is left out, so the
  list does not empty while it is typed. }
function ParseGraphFilter(const AText: string): TGittanGraphFilter;

{** Whether the filter asks for nothing at all. }
function GraphFilterEmpty(const AFilter: TGittanGraphFilter): boolean;

{** Whether a commit matches the filter's words, authors and dates:
  AText is the text the words are looked for in (its subject, body,
  author and id), AAuthor its author, ADate its time in UTC. Whether
  it touches the paths or makes the changes is the caller's to find
  out. }
function MatchesGraphFilter(const AFilter: TGittanGraphFilter;
  const AText, AAuthor: string; ADate: TDateTime): boolean;


implementation

uses
  Math, StrUtils, DateUtils;

procedure LayoutGraph(var ACommits: TGittanGraphCommits);
var
  Lanes: array of string;
  LaneColor: array of integer;
  NextColor: integer;

  { The lowest free lane, a new one at the right when none is free; it
    waits for AHash in a color of its own. }
  function Alloc(const AHash: string): integer;
  begin
    Result := 0;
    while (Result < Length(Lanes)) and (Lanes[Result] <> '') do
      Inc(Result);
    if Result = Length(Lanes) then
    begin
      SetLength(Lanes, Result + 1);
      SetLength(LaneColor, Result + 1);
    end;
    Lanes[Result] := AHash;
    LaneColor[Result] := NextColor;
    Inc(NextColor);
  end;

  function Waiting(const AHash: string; AExcept: integer): integer;
  var
    i: integer;
  begin
    for i := 0 to High(Lanes) do
      if (i <> AExcept) and (Lanes[i] = AHash) then
        Exit(i);
    Result := -1;
  end;

  procedure AddEdge(var AEdges: TGittanGraphEdges; AFrom, ATo, AColor: integer);
  begin
    SetLength(AEdges, Length(AEdges) + 1);
    AEdges[High(AEdges)].FromLane := AFrom;
    AEdges[High(AEdges)].ToLane := ATo;
    AEdges[High(AEdges)].Color := AColor;
  end;

var
  r, i, j, N, K, Before: integer;
  Hash: string;
  Through: array of boolean;
begin
  Lanes := nil;
  LaneColor := nil;
  NextColor := 0;
  for r := 0 to High(ACommits) do
    with ACommits[r] do
    begin
      TopEdges := nil;
      BottomEdges := nil;
      Hash := ACommits[r].Hash;
      N := Waiting(Hash, -1);
      { The top half: the lanes that wait for this commit end in it,
        the others pass by. }
      for i := 0 to High(Lanes) do
        if Lanes[i] <> '' then
        begin
          if Lanes[i] = Hash then
            AddEdge(TopEdges, i, N, LaneColor[i])
          else
            AddEdge(TopEdges, i, i, LaneColor[i]);
        end;
      for i := 0 to High(Lanes) do
        if Lanes[i] = Hash then
          Lanes[i] := '';
      { A tip takes a free lane; the lanes free now include those that
        ended in it, which leaves its own lane free when it has one. }
      if N < 0 then
        N := Alloc('')
      else
        Lanes[N] := '';
      Lane := N;
      Color := LaneColor[N];
      { The lanes that pass by go on in the bottom half. }
      Before := Length(Lanes);
      SetLength(Through, Before);
      for i := 0 to Before - 1 do
        Through[i] := Lanes[i] <> '';
      if Length(Parents) > 0 then
      begin
        { The first parent goes straight down, unless a lane left of
          this one waits for it: then it joins that lane, so a branch
          bends into the line it left and the line stays straight. }
        K := Waiting(Parents[0], -1);
        if (K < 0) or (K > N) then
        begin
          Lanes[N] := Parents[0];
          AddEdge(BottomEdges, N, N, Color);
        end
        else
          AddEdge(BottomEdges, N, K, Color);
        for j := 1 to High(Parents) do
        begin
          K := Waiting(Parents[j], -1);
          if K < 0 then
            K := Alloc(Parents[j]);
          AddEdge(BottomEdges, N, K, LaneColor[K]);
        end;
      end;
      for i := 0 to Before - 1 do
        if Through[i] then
          AddEdge(BottomEdges, i, i, LaneColor[i]);
      while (Length(Lanes) > 0) and (Lanes[High(Lanes)] = '') do
      begin
        SetLength(Lanes, Length(Lanes) - 1);
        SetLength(LaneColor, Length(LaneColor) - 1);
      end;
    end;
end;

function GraphWidth(const ACommits: TGittanGraphCommits): integer;
var
  r, i: integer;
begin
  Result := 0;
  for r := 0 to High(ACommits) do
  begin
    Result := Max(Result, ACommits[r].Lane + 1);
    for i := 0 to High(ACommits[r].TopEdges) do
      Result := Max(Result, Max(ACommits[r].TopEdges[i].FromLane,
        ACommits[r].TopEdges[i].ToLane) + 1);
    for i := 0 to High(ACommits[r].BottomEdges) do
      Result := Max(Result, Max(ACommits[r].BottomEdges[i].FromLane,
        ACommits[r].BottomEdges[i].ToLane) + 1);
  end;
end;

function ParseGraphRefs(const ADecoration: string): TGittanGraphRefs;

  procedure Add(const AName: string; AKind: TGittanRefKind);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Name := AName;
    Result[High(Result)].Kind := AKind;
  end;

var
  Parts: TStringArray;
  Part: string;
  i: integer;
begin
  Result := nil;
  if Trim(ADecoration) = '' then
    Exit;
  Parts := ADecoration.Split([', ']);
  for i := 0 to High(Parts) do
  begin
    Part := Trim(Parts[i]);
    if Part = 'HEAD' then
      Add('HEAD', grHead)
    else if AnsiStartsStr('HEAD -> ', Part) then
    begin
      Part := Copy(Part, Length('HEAD -> ') + 1, MaxInt);
      if AnsiStartsStr('refs/heads/', Part) then
        Delete(Part, 1, Length('refs/heads/'));
      Add(Part, grHead);
    end
    else if AnsiStartsStr('tag: ', Part) then
    begin
      Part := Copy(Part, Length('tag: ') + 1, MaxInt);
      if AnsiStartsStr('refs/tags/', Part) then
        Delete(Part, 1, Length('refs/tags/'));
      Add(Part, grTag);
    end
    else if AnsiStartsStr('refs/heads/', Part) then
      Add(Copy(Part, Length('refs/heads/') + 1, MaxInt), grBranch)
    else if AnsiStartsStr('refs/remotes/', Part) then
    begin
      Part := Copy(Part, Length('refs/remotes/') + 1, MaxInt);
      if not AnsiEndsStr('/HEAD', Part) then
        Add(Part, grRemote);
    end
    else if AnsiStartsStr('refs/tags/', Part) then
      Add(Copy(Part, Length('refs/tags/') + 1, MaxInt), grTag)
    else if Part = 'refs/bisect/bad' then
      Add('bad', grBisect)
    else if AnsiStartsStr('refs/bisect/good-', Part) then
      Add('good', grBisect)
    else if AnsiStartsStr('refs/bisect/skip-', Part) then
      Add('skip', grBisect);
    { Anything else (refs/stash, notes) is not shown. }
  end;
end;


{ The tokens of AText: runs of anything but spaces, a quoted phrase kept
  together with its quotes dropped. }
function SplitFilter(const AText: string): TStringArray;
var
  i: integer;
  Token: string;
  Quoted: boolean;

  procedure Flush;
  begin
    if Token = '' then
      Exit;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Token;
    Token := '';
  end;

begin
  Result := nil;
  Token := '';
  Quoted := False;
  for i := 1 to Length(AText) do
    if AText[i] = '"' then
      Quoted := not Quoted
    else if (AText[i] <= ' ') and not Quoted then
      Flush
    else
      Token := Token + AText[i];
  Flush;
end;

{ A year, a year and month or a day, as the start of it in ADate and,
  for the end of it, the start of what follows in ANext. }
function ParseFilterDate(const AText: string; out ADate, ANext: TDateTime): boolean;
var
  Parts: TStringArray;
  Y, M, D: integer;
begin
  Result := False;
  ADate := 0;
  ANext := 0;
  Parts := AText.Split(['-', '/', '.']);
  if (Length(Parts) < 1) or (Length(Parts) > 3) then
    Exit;
  if not TryStrToInt(Parts[0], Y) or (Length(Parts[0]) <> 4) then
    Exit;
  M := 1;
  D := 1;
  if (Length(Parts) >= 2) and not TryStrToInt(Parts[1], M) then
    Exit;
  if (Length(Parts) = 3) and not TryStrToInt(Parts[2], D) then
    Exit;
  if not TryEncodeDate(Y, M, D, ADate) then
    Exit;
  case Length(Parts) of
    1: ANext := IncYear(ADate);
    2: ANext := IncMonth(ADate);
    else
      ANext := IncDay(ADate);
  end;
  Result := True;
end;

function ParseGraphFilter(const AText: string): TGittanGraphFilter;
var
  Tokens: TStringArray;
  Token, Key, Value: string;
  i, Colon: integer;
  From, Next: TDateTime;

  procedure Append(var AList: TStringArray; const AValue: string);
  begin
    SetLength(AList, Length(AList) + 1);
    AList[High(AList)] := AValue;
  end;

begin
  Result := Default(TGittanGraphFilter);
  Tokens := SplitFilter(AText);
  for i := 0 to High(Tokens) do
  begin
    Token := Tokens[i];
    Colon := Pos(':', Token);
    Key := '';
    if Colon > 1 then
      Key := LowerCase(Copy(Token, 1, Colon - 1));
    Value := Copy(Token, Colon + 1, MaxInt);
    if (Key = 'author') or (Key = 'since') or (Key = 'after') or (Key = 'until') or
      (Key = 'before') or (Key = 'path') or (Key = 'change') then
    begin
      { change:// is an empty pattern on the way to a regex. }
      if (Value = '') or ((Key = 'change') and (Value = '//')) then
        Continue;
      if Key = 'author' then
        Append(Result.Authors, Value)
      else if Key = 'path' then
        Append(Result.Paths, Value)
      else if Key = 'change' then
        Append(Result.Changes, Value)
      else if ParseFilterDate(Value, From, Next) then
      begin
        if (Key = 'since') or (Key = 'after') then
          Result.Since := From
        else
          Result.Before := Next;
      end;
    end
    else
      Append(Result.Words, Token);
  end;
end;

function GraphFilterEmpty(const AFilter: TGittanGraphFilter): boolean;
begin
  Result := (Length(AFilter.Words) = 0) and (Length(AFilter.Authors) = 0) and
    (Length(AFilter.Paths) = 0) and (Length(AFilter.Changes) = 0) and
    (AFilter.Since = 0) and (AFilter.Before = 0);
end;

function MatchesGraphFilter(const AFilter: TGittanGraphFilter;
  const AText, AAuthor: string; ADate: TDateTime): boolean;
var
  i: integer;
  Local: TDateTime;
begin
  Result := False;
  for i := 0 to High(AFilter.Words) do
    if Pos(AFilter.Words[i], AText) = 0 then
      Exit;
  if Length(AFilter.Authors) > 0 then
  begin
    i := 0;
    while (i <= High(AFilter.Authors)) and (Pos(AFilter.Authors[i], AAuthor) = 0) do
      Inc(i);
    if i > High(AFilter.Authors) then
      Exit;
  end;
  if (AFilter.Since <> 0) or (AFilter.Before <> 0) then
  begin
    Local := UniversalTimeToLocal(ADate);
    if (AFilter.Since <> 0) and (Local < AFilter.Since) then
      Exit;
    if (AFilter.Before <> 0) and (Local >= AFilter.Before) then
      Exit;
  end;
  Result := True;
end;

end.
