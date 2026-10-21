unit testcommitstats;

{** Tests of gittan.commitstats: the commits per week and per author. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, fpcunit, testregistry, gittan.graph, gittan.commitstats;

type
  TCommitStatsTest = class(TTestCase)
  private
    FCommits: TGittanGraphCommits;
    procedure Add(const AAuthor: string; ADate: TDateTime);
  published
    procedure TestWeekStart;
    procedure TestStats;
    procedure TestMaxWeeks;
    procedure TestEmpty;
  end;

implementation

procedure TCommitStatsTest.Add(const AAuthor: string; ADate: TDateTime);
begin
  SetLength(FCommits, Length(FCommits) + 1);
  FCommits[High(FCommits)].Author := AAuthor;
  FCommits[High(FCommits)].Date := ADate;
end;

procedure TCommitStatsTest.TestWeekStart;
begin
  { 2026-10-21 is a Wednesday. }
  AssertEquals(EncodeDate(2026, 10, 19), WeekStart(EncodeDateTime(2026, 10, 21, 15, 30, 0, 0)));
  AssertEquals('a Monday is its own', EncodeDate(2026, 10, 19), WeekStart(EncodeDate(2026, 10, 19)));
  AssertEquals('a Sunday ends the week', EncodeDate(2026, 10, 19),
    WeekStart(EncodeDateTime(2026, 10, 25, 23, 59, 0, 0)));
end;

{ Newest first, as git log gives them; the week of the 12th has none. }
procedure TCommitStatsTest.TestStats;
var
  S: TGittanCommitStats;
begin
  FCommits := nil;
  Add('Björn', EncodeDateTime(2026, 10, 21, 12, 0, 0, 0));
  Add('Ann', EncodeDateTime(2026, 10, 20, 12, 0, 0, 0));
  Add('björn', EncodeDateTime(2026, 10, 19, 0, 30, 0, 0));
  Add('Ann', EncodeDateTime(2026, 10, 7, 12, 0, 0, 0));
  Add('Ann', EncodeDateTime(2026, 10, 5, 12, 0, 0, 0));
  Add('Cy', 0);
  S := CommitStats(FCommits, [0, 1, 2, 3, 4, 5], 0, 0);
  AssertEquals(6, S.Commits);
  AssertEquals(EncodeDate(2026, 10, 5), S.FirstWeek);
  AssertEquals(3, Length(S.Weeks));
  AssertEquals(2, S.Weeks[0]);
  AssertEquals(0, S.Weeks[1]);
  AssertEquals(3, S.Weeks[2]);
  AssertEquals(EncodeDateTime(2026, 10, 5, 12, 0, 0, 0), S.Oldest);
  AssertEquals(EncodeDateTime(2026, 10, 21, 12, 0, 0, 0), S.Newest);
  AssertEquals(3, Length(S.Authors));
  AssertEquals('Ann', S.Authors[0].Name);
  AssertEquals(3, S.Authors[0].Total);
  AssertEquals(2, S.Authors[0].Weeks[0]);
  AssertEquals(1, S.Authors[0].Weeks[2]);
  AssertEquals('one author, spelled as the newest commit does', 'Björn', S.Authors[1].Name);
  AssertEquals(2, S.Authors[1].Total);
  AssertEquals(2, S.Authors[1].Weeks[2]);
  AssertEquals('no time: counted, in no week', 'Cy', S.Authors[2].Name);
  AssertEquals(1, S.Authors[2].Total);
  AssertEquals(0, S.Authors[2].Weeks[0] + S.Authors[2].Weeks[1] + S.Authors[2].Weeks[2]);

  { Only the commits shown, and the offset moves a commit to its local
    week: an hour back puts the 19th's past midnight in the week before. }
  S := CommitStats(FCommits, [2, 4], 0, -1 / 24);
  AssertEquals(2, S.Commits);
  AssertEquals(2, Length(S.Weeks));
  AssertEquals(2, Length(S.Authors));
  AssertEquals(EncodeDate(2026, 10, 5), S.FirstWeek);
  AssertEquals(1, S.Weeks[0]);
  AssertEquals('the 18th, a Sunday', 1, S.Weeks[1]);
end;

procedure TCommitStatsTest.TestMaxWeeks;
var
  S: TGittanCommitStats;
begin
  FCommits := nil;
  Add('Ann', EncodeDateTime(2026, 10, 21, 12, 0, 0, 0));
  Add('Bo', EncodeDateTime(2025, 1, 8, 12, 0, 0, 0));
  S := CommitStats(FCommits, [0, 1], 4, 0);
  AssertEquals(4, Length(S.Weeks));
  AssertEquals('the newest weeks kept', EncodeDate(2026, 9, 28), S.FirstWeek);
  AssertEquals(1, S.Weeks[3]);
  AssertEquals(1, S.Weeks[0] + S.Weeks[1] + S.Weeks[2] + S.Weeks[3]);
  { As many commits: the one with the newer commit first. }
  AssertEquals('Ann', S.Authors[0].Name);
  AssertEquals('Bo', S.Authors[1].Name);
  AssertEquals('an older commit still counts for its author', 1, S.Authors[1].Total);
end;

procedure TCommitStatsTest.TestEmpty;
var
  S: TGittanCommitStats;
begin
  FCommits := nil;
  S := CommitStats(FCommits, [], 10, 0);
  AssertEquals(0, S.Commits);
  AssertEquals(0, Length(S.Weeks));
  AssertEquals(0, Length(S.Authors));
  AssertEquals(0.0, S.FirstWeek);
end;

initialization
  RegisterTest(TCommitStatsTest);
end.
