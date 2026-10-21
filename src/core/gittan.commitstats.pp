unit gittan.commitstats;

{** The statistics of the commit graph: for the commits it shows, how
  many there are per week and per author, and for each author per week,
  so the graph can draw a bar for every week and a row for every author.
  A week starts on Monday, in local time. Authors whose names differ
  only in case or in how their letters are composed are one, as in the
  repository page's list (NameKey). No LCL, so it is tested on its own. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, gittan.graph;

type
  {** An author's commits: the name as their newest commit spells it,
    how many there are, and how many in each week of the statistics. }
  TGittanAuthorStat = record
    Name: string;
    Total: integer;
    Weeks: TIntegerDynArray;
  end;
  TGittanAuthorStats = array of TGittanAuthorStat;

  {** The commits counted (Commits), the first moment of the oldest
    week counted (FirstWeek, a Monday at midnight in local time, 0 when
    no commit has a time), the commits in each week from it on, the
    newest week last (Weeks), the times of the oldest and newest commit
    (local time), and the authors, the most commits first. }
  TGittanCommitStats = record
    Commits: integer;
    FirstWeek: TDateTime;
    Weeks: TIntegerDynArray;
    Oldest, Newest: TDateTime;
    Authors: TGittanAuthorStats;
  end;

{** The statistics of the commits of ACommits whose indexes AShown
  lists. The weeks run from the oldest commit's to the newest one's, at
  most AMaxWeeks of them, the newest kept; a commit in an older week is
  counted in its author's total but in no week. ACommits' times are in
  UTC, as git log gives them; AOffset (days) is added to make them local,
  so a caller passes the local zone's offset and a test passes 0. }
function CommitStats(const ACommits: TGittanGraphCommits; const AShown: array of integer;
  AMaxWeeks: integer; AOffset: TDateTime): TGittanCommitStats;

{** The Monday at midnight of the week ADate falls in. }
function WeekStart(ADate: TDateTime): TDateTime;

implementation

uses
  DateUtils, gittan.repoinfo;

function WeekStart(ADate: TDateTime): TDateTime;
begin
  Result := Trunc(ADate) - (DayOfTheWeek(ADate) - 1);
end;

function CommitStats(const ACommits: TGittanGraphCommits; const AShown: array of integer;
  AMaxWeeks: integer; AOffset: TDateTime): TGittanCommitStats;
var
  Keys: TStringList;
  i, j, k, n, Week: integer;
  Local, First, Last: TDateTime;
  Key: string;
  Swap: TGittanAuthorStat;
begin
  Result := Default(TGittanCommitStats);
  First := 0;
  Last := 0;
  for i := 0 to High(AShown) do
    if ACommits[AShown[i]].Date > 0 then
    begin
      Local := ACommits[AShown[i]].Date + AOffset;
      if (First = 0) or (Local < First) then
        First := Local;
      if Local > Last then
        Last := Local;
    end;
  Result.Oldest := First;
  Result.Newest := Last;
  if Last > 0 then
  begin
    n := Round((WeekStart(Last) - WeekStart(First)) / 7) + 1;
    if (AMaxWeeks > 0) and (n > AMaxWeeks) then
      n := AMaxWeeks;
    Result.FirstWeek := WeekStart(Last) - 7 * (n - 1);
    SetLength(Result.Weeks, n);
  end;

  { The authors in the order their newest commit comes, which is the
    order the log gives; sorted by their totals after. }
  Keys := TStringList.Create;
  try
    Keys.CaseSensitive := True;
    Keys.Sorted := True;
    for i := 0 to High(AShown) do
    begin
      Inc(Result.Commits);
      Key := NameKey(ACommits[AShown[i]].Author);
      k := Keys.IndexOf(Key);
      if k >= 0 then
        k := PtrInt(Keys.Objects[k])
      else
      begin
        k := Length(Result.Authors);
        SetLength(Result.Authors, k + 1);
        Result.Authors[k].Name := ACommits[AShown[i]].Author;
        SetLength(Result.Authors[k].Weeks, Length(Result.Weeks));
        Keys.AddObject(Key, TObject(PtrInt(k)));
      end;
      Inc(Result.Authors[k].Total);
      if ACommits[AShown[i]].Date <= 0 then
        Continue;
      Local := ACommits[AShown[i]].Date + AOffset;
      Week := Round((WeekStart(Local) - Result.FirstWeek) / 7);
      if (Week >= 0) and (Week <= High(Result.Weeks)) then
      begin
        Inc(Result.Weeks[Week]);
        Inc(Result.Authors[k].Weeks[Week]);
      end;
    end;
  finally
    Keys.Free;
  end;

  { The most commits first; a stable insertion sort, so authors with as
    many keep the order of their newest commit. }
  for i := 1 to High(Result.Authors) do
  begin
    Swap := Result.Authors[i];
    j := i;
    while (j > 0) and (Result.Authors[j - 1].Total < Swap.Total) do
    begin
      Result.Authors[j] := Result.Authors[j - 1];
      Dec(j);
    end;
    Result.Authors[j] := Swap;
  end;
end;

end.
