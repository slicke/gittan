unit gittan.issuelinks;

{** Issue references in commit messages. A repository names its issue
  tracker in git config with the bugtraq keys that several git clients
  share: bugtraq.url is the address of an issue with %BUGID% where its
  id goes, and bugtraq.logregex says how a message refers to one, as
  one regular expression (its first group, or the whole match, is the
  id) or two on two lines (the first finds each reference in the
  message, "Fixes #12 and #13" say, and the second the ids within it).
  FindIssueLinks marks the references in a text, and IssueUrl gives the
  address of one. Without a tracker a forge's issues are referred to
  as #<number>, DefaultIssueRegex. No LCL; tested in
  tests/testissuelinks.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  {** The id's place in bugtraq.url. }
  IssueIdMarker = '%BUGID%';
  {** How a forge's issues are referred to when no tracker is set up. }
  DefaultIssueRegex = '#(\d+)';

type
  {** An issue tracker as bugtraq.url and bugtraq.logregex name it; an
    empty LogRegex is no tracker. }
  TGittanIssueTracker = record
    Url, LogRegex: string;
  end;

  {** A reference to an issue in a text: where it starts (1-based) and
    how long it is, in bytes, and the id it names. }
  TGittanIssueLink = record
    Start, Len: integer;
    Id: string;
  end;
  TGittanIssueLinks = array of TGittanIssueLink;

{** Reads the tracker from the output of
  `git config -z --get-regexp ^bugtraq\.`: a key, a line break, its
  value, a NUL after each. }
function ParseIssueTrackerConfig(const AOutput: string): TGittanIssueTracker;

{** Whether ATracker marks nothing: no regular expression. }
function IssueTrackerEmpty(const ATracker: TGittanIssueTracker): boolean;

{** The references to issues in AText, in order; none when the regular
  expression cannot be read. }
function FindIssueLinks(const AText: string;
  const ATracker: TGittanIssueTracker): TGittanIssueLinks;

{** The address of issue AId: ATracker's Url with the id in place of
  %BUGID% (appended when the marker is missing); '' without a Url. }
function IssueUrl(const ATracker: TGittanIssueTracker; const AId: string): string;

implementation

uses
  RegExpr;

function ParseIssueTrackerConfig(const AOutput: string): TGittanIssueTracker;
var
  Entries: TStringArray;
  Key, Value: string;
  i, p: integer;
begin
  Result.Url := '';
  Result.LogRegex := '';
  Entries := AOutput.Split([#0]);
  for i := 0 to High(Entries) do
  begin
    p := Pos(#10, Entries[i]);
    if p = 0 then
      Continue;
    Key := Copy(Entries[i], 1, p - 1);
    Value := Copy(Entries[i], p + 1, MaxInt);
    if SameText(Key, 'bugtraq.url') then
      Result.Url := Trim(Value)
    else if SameText(Key, 'bugtraq.logregex') then
      Result.LogRegex := Trim(AdjustLineBreaks(Value, tlbsLF));
  end;
end;

function IssueTrackerEmpty(const ATracker: TGittanIssueTracker): boolean;
begin
  Result := Trim(ATracker.LogRegex) = '';
end;

{ The ids the regular expression ARegex finds in AText, each as the
  first group when it has one, else the whole match; AOffset is added
  to every position, for a match within a match. }
procedure AddIds(const AText, ARegex: string; AOffset: integer; var ALinks: TGittanIssueLinks);
var
  R: TRegExpr;
  Group: integer;
begin
  if (AText = '') or (ARegex = '') then
    Exit;
  R := TRegExpr.Create(ARegex);
  try
    if not R.Exec(AText) then
      Exit;
    repeat
      if R.SubExprMatchCount >= 1 then
        Group := 1
      else
        Group := 0;
      { An empty match would never move on. }
      if (R.MatchLen[0] > 0) and (R.MatchLen[Group] > 0) then
      begin
        SetLength(ALinks, Length(ALinks) + 1);
        ALinks[High(ALinks)].Start := R.MatchPos[Group] + AOffset;
        ALinks[High(ALinks)].Len := R.MatchLen[Group];
        ALinks[High(ALinks)].Id := R.Match[Group];
      end;
    until (R.MatchLen[0] = 0) or not R.ExecNext;
  finally
    R.Free;
  end;
end;

function FindIssueLinks(const AText: string;
  const ATracker: TGittanIssueTracker): TGittanIssueLinks;
var
  Lines: TStringArray;
  Outer: TRegExpr;
begin
  Result := nil;
  if (AText = '') or IssueTrackerEmpty(ATracker) then
    Exit;
  Lines := Trim(AdjustLineBreaks(ATracker.LogRegex, tlbsLF)).Split([#10]);
  try
    if Length(Lines) < 2 then
      AddIds(AText, Trim(Lines[0]), 0, Result)
    else
    begin
      { The first expression finds each reference, the second the ids
        within it. }
      Outer := TRegExpr.Create(Trim(Lines[0]));
      try
        if Outer.Exec(AText) then
          repeat
            if Outer.MatchLen[0] > 0 then
              AddIds(Outer.Match[0], Trim(Lines[1]), Outer.MatchPos[0] - 1, Result);
          until (Outer.MatchLen[0] = 0) or not Outer.ExecNext;
      finally
        Outer.Free;
      end;
    end;
  except
    { A regular expression that cannot be read marks nothing. }
    Result := nil;
  end;
end;

function IssueUrl(const ATracker: TGittanIssueTracker; const AId: string): string;
begin
  Result := Trim(ATracker.Url);
  if Result = '' then
    Exit;
  if Pos(IssueIdMarker, Result) > 0 then
    Result := StringReplace(Result, IssueIdMarker, AId, [rfReplaceAll, rfIgnoreCase])
  else
    Result := Result + AId;
end;

end.
