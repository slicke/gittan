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
    when it is detached), another local branch, a remote-tracking branch
    or a tag. }
  TGittanRefKind = (grHead, grBranch, grRemote, grTag);

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
    the parents' ids, the author, the commit time in UTC, the subject
    and the refs on it), whether it is on HEAD and not on its upstream
    (not pushed) or the other way round (not pulled), and from
    LayoutGraph its lane, its color and the lines of its row. }
  TGittanGraphCommit = record
    Hash, Short, Author, Subject: string;
    Parents: TStringArray;
    Date: TDateTime;
    Refs: TGittanGraphRefs;
    Unpushed, Unpulled: boolean;
    Lane, Color: integer;
    TopEdges, BottomEdges: TGittanGraphEdges;
  end;
  TGittanGraphCommits = array of TGittanGraphCommit;

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

implementation

uses
  Math, StrUtils;

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
      Add(Copy(Part, Length('refs/tags/') + 1, MaxInt), grTag);
    { Anything else (refs/stash, notes) is not shown. }
  end;
end;

end.
