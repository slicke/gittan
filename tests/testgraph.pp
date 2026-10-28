unit testgraph;

{** Tests of gittan.graph: the lanes of the commit graph and the refs. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, fpcunit, testregistry, gittan.graph;

type
  TGraphTest = class(TTestCase)
  private
    FCommits: TGittanGraphCommits;
    procedure Add(const AHash, AParents: string);
    function HasEdge(const AEdges: TGittanGraphEdges; AFrom, ATo: integer): boolean;
  published
    procedure TestLine;
    procedure TestBranchAndMerge;
    procedure TestTwoTips;
    procedure TestMissingParent;
    procedure TestRefs;
    procedure TestFilter;
  end;

implementation

procedure TGraphTest.Add(const AHash, AParents: string);
begin
  SetLength(FCommits, Length(FCommits) + 1);
  FCommits[High(FCommits)].Hash := AHash;
  if AParents = '' then
    FCommits[High(FCommits)].Parents := nil
  else
    FCommits[High(FCommits)].Parents := AParents.Split([' ']);
end;

function TGraphTest.HasEdge(const AEdges: TGittanGraphEdges; AFrom, ATo: integer): boolean;
var
  i: integer;
begin
  for i := 0 to High(AEdges) do
    if (AEdges[i].FromLane = AFrom) and (AEdges[i].ToLane = ATo) then
      Exit(True);
  Result := False;
end;

{ c - b - a: one lane, a line between each pair, none above the tip or
  below the root. }
procedure TGraphTest.TestLine;
begin
  FCommits := nil;
  Add('c', 'b');
  Add('b', 'a');
  Add('a', '');
  LayoutGraph(FCommits);
  AssertEquals(1, GraphWidth(FCommits));
  AssertEquals(0, FCommits[0].Lane);
  AssertEquals(0, Length(FCommits[0].TopEdges));
  AssertTrue(HasEdge(FCommits[0].BottomEdges, 0, 0));
  AssertTrue(HasEdge(FCommits[1].TopEdges, 0, 0));
  AssertEquals(0, Length(FCommits[2].BottomEdges));
  AssertEquals('one color', FCommits[0].Color, FCommits[2].Color);
end;

{ m merges f into b; f branched from a:
    m        lane 0
    | \
    f  |     f in lane 1
    b  |     b in lane 0, f's lane passes
    | /
    a        f's lane ends in a }
procedure TGraphTest.TestBranchAndMerge;
begin
  FCommits := nil;
  Add('m', 'b f');
  Add('f', 'a');
  Add('b', 'a');
  Add('a', '');
  LayoutGraph(FCommits);
  AssertEquals(2, GraphWidth(FCommits));
  AssertEquals(0, FCommits[0].Lane);
  AssertTrue('first parent below', HasEdge(FCommits[0].BottomEdges, 0, 0));
  AssertTrue('merged parent to a new lane', HasEdge(FCommits[0].BottomEdges, 0, 1));
  AssertEquals(1, FCommits[1].Lane);
  AssertTrue(HasEdge(FCommits[1].TopEdges, 1, 1));
  AssertTrue('b passes by f', HasEdge(FCommits[1].TopEdges, 0, 0));
  AssertEquals(0, FCommits[2].Lane);
  AssertTrue('f passes by b', HasEdge(FCommits[2].BottomEdges, 1, 1));
  AssertEquals(0, FCommits[3].Lane);
  AssertTrue('f ends in a', HasEdge(FCommits[3].TopEdges, 1, 0));
  AssertTrue(HasEdge(FCommits[3].TopEdges, 0, 0));
  AssertFalse('the branch has its own color', FCommits[1].Color = FCommits[0].Color);
end;

{ Two tips on a: the second takes a lane of its own, and its line joins
  the first's lane, which already waits for a. }
procedure TGraphTest.TestTwoTips;
begin
  FCommits := nil;
  Add('x', 'a');
  Add('y', 'a');
  Add('a', '');
  LayoutGraph(FCommits);
  AssertEquals(0, FCommits[0].Lane);
  AssertEquals(1, FCommits[1].Lane);
  AssertTrue('y joins the lane waiting for a', HasEdge(FCommits[1].BottomEdges, 1, 0));
  AssertEquals(0, FCommits[2].Lane);
  AssertEquals('a has one line in', 1, Length(FCommits[2].TopEdges));
end;

{ A parent cut off by the log's limit keeps its lane open to the end. }
procedure TGraphTest.TestMissingParent;
begin
  FCommits := nil;
  Add('b', 'a');
  Add('c', 'z');
  Add('a', '');
  LayoutGraph(FCommits);
  AssertEquals(1, FCommits[1].Lane);
  AssertTrue(HasEdge(FCommits[2].TopEdges, 1, 1));
  AssertTrue('still open below the last row', HasEdge(FCommits[2].BottomEdges, 1, 1));
end;

procedure TGraphTest.TestRefs;
var
  Refs: TGittanGraphRefs;
begin
  Refs := ParseGraphRefs('HEAD -> refs/heads/main, refs/remotes/origin/main, ' +
    'refs/remotes/origin/HEAD, tag: refs/tags/v1.0, refs/heads/feature/x, refs/stash');
  AssertEquals(4, Length(Refs));
  AssertEquals('main', Refs[0].Name);
  AssertTrue(Refs[0].Kind = grHead);
  AssertEquals('origin/main', Refs[1].Name);
  AssertTrue(Refs[1].Kind = grRemote);
  AssertEquals('v1.0', Refs[2].Name);
  AssertTrue(Refs[2].Kind = grTag);
  AssertEquals('feature/x', Refs[3].Name);
  AssertTrue(Refs[3].Kind = grBranch);
  Refs := ParseGraphRefs('refs/bisect/bad, refs/bisect/good-0123abc, refs/bisect/skip-0123abc');
  AssertEquals(3, Length(Refs));
  AssertEquals('bad', Refs[0].Name);
  AssertTrue(Refs[0].Kind = grBisect);
  AssertEquals('good', Refs[1].Name);
  AssertEquals('skip', Refs[2].Name);
  Refs := ParseGraphRefs('HEAD');
  AssertEquals(1, Length(Refs));
  AssertTrue('detached', Refs[0].Kind = grHead);
  AssertEquals(0, Length(ParseGraphRefs('')));
end;

{ The parts of a typed filter, and what a commit must have to match it;
  the words and texts are matched as given, here in lower case. }
procedure TGraphTest.TestFilter;
var
  F: TGittanGraphFilter;
  D: TDateTime;
begin
  AssertTrue(GraphFilterEmpty(ParseGraphFilter('')));
  AssertTrue(GraphFilterEmpty(ParseGraphFilter('  author:  since:20 ')));
  F := ParseGraphFilter('fix Author:ann since:2024-06 until:2024-06-15 ' +
    'path:"src/a b.pp" "two words" after:2024 path:c.pp');
  AssertFalse(GraphFilterEmpty(F));
  AssertEquals(2, Length(F.Words));
  AssertEquals('fix', F.Words[0]);
  AssertEquals('two words', F.Words[1]);
  AssertEquals(1, Length(F.Authors));
  AssertEquals('ann', F.Authors[0]);
  AssertEquals(2, Length(F.Paths));
  AssertEquals('src/a b.pp', F.Paths[0]);
  AssertEquals('c.pp', F.Paths[1]);
  { The later since wins. }
  AssertEquals(EncodeDate(2024, 1, 1), F.Since);
  AssertEquals(EncodeDate(2024, 6, 16), F.Before);
  F := ParseGraphFilter('Change:ParseList change:"a b" change: change:// change:/x+/');
  AssertFalse(GraphFilterEmpty(F));
  AssertEquals(0, Length(F.Words));
  AssertEquals(3, Length(F.Changes));
  AssertEquals('ParseList', F.Changes[0]);
  AssertEquals('a b', F.Changes[1]);
  AssertEquals('/x+/', F.Changes[2]);
  F := ParseGraphFilter('until:2023');
  AssertEquals(0.0, F.Since);
  AssertEquals(EncodeDate(2024, 1, 1), F.Before);

  F := ParseGraphFilter('fix two author:ann since:2024-06-01 until:2024-06-15');
  D := LocalTimeToUniversal(EncodeDate(2024, 6, 10) + 0.5);
  AssertTrue(MatchesGraphFilter(F, 'fix one two ann abc1234', 'ann', D));
  AssertFalse('a word missing', MatchesGraphFilter(F, 'fix one ann abc1234', 'ann', D));
  AssertFalse('another author', MatchesGraphFilter(F, 'fix two', 'bob', D));
  AssertFalse('too early', MatchesGraphFilter(F, 'fix two', 'ann',
    LocalTimeToUniversal(EncodeDate(2024, 5, 31) + 0.9)));
  AssertTrue('the last day counts', MatchesGraphFilter(F, 'fix two', 'ann',
    LocalTimeToUniversal(EncodeDate(2024, 6, 15) + 0.9)));
  AssertFalse('too late', MatchesGraphFilter(F, 'fix two', 'ann',
    LocalTimeToUniversal(EncodeDate(2024, 6, 16))));
  F := ParseGraphFilter('author:ann author:bob');
  AssertTrue('any author', MatchesGraphFilter(F, '', 'bob', D));
  AssertTrue('nothing asked', MatchesGraphFilter(ParseGraphFilter(''), '', '', 0));
end;

initialization
  RegisterTest(TGraphTest);
end.
