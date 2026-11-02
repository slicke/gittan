unit testissuelinks;

{** Tests of gittan.issuelinks: the tracker read from git config's
  output, the references found with one and two regular expressions,
  and the address of an issue. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.issuelinks;

type
  TIssueLinksTest = class(TTestCase)
  published
    procedure TestParseConfig;
    procedure TestOneRegex;
    procedure TestTwoRegexes;
    procedure TestBadRegex;
    procedure TestUrl;
  end;

implementation

procedure TIssueLinksTest.TestParseConfig;
var
  T: TGittanIssueTracker;
begin
  T := ParseIssueTrackerConfig('');
  AssertEquals('', T.Url);
  AssertEquals('', T.LogRegex);
  AssertTrue(IssueTrackerEmpty(T));
  T := ParseIssueTrackerConfig('bugtraq.url'#10'https://example.test/issues/%BUGID%'#0 +
    'bugtraq.logregex'#10'[Ii]ssues?:?(\s*#\d+)+'#10'(\d+)'#0);
  AssertEquals('https://example.test/issues/%BUGID%', T.Url);
  AssertEquals('[Ii]ssues?:?(\s*#\d+)+'#10'(\d+)', T.LogRegex);
  AssertFalse(IssueTrackerEmpty(T));
  { A value with no key is passed over; keys in any case. }
  T := ParseIssueTrackerConfig('junk'#0'Bugtraq.URL'#10'x'#0);
  AssertEquals('x', T.Url);
end;

procedure TIssueLinksTest.TestOneRegex;
var
  T: TGittanIssueTracker;
  L: TGittanIssueLinks;
begin
  T.Url := '';
  T.LogRegex := DefaultIssueRegex;
  L := FindIssueLinks('Fix #12 and #345, not #x', T);
  AssertEquals(2, Length(L));
  { The first group is the id, so the # stays outside the link. }
  AssertEquals('12', L[0].Id);
  AssertEquals(6, L[0].Start);
  AssertEquals(2, L[0].Len);
  AssertEquals('345', L[1].Id);
  AssertEquals(14, L[1].Start);
  AssertEquals(3, L[1].Len);
  { No group: the whole match is the id. }
  T.LogRegex := 'ABC-\d+';
  L := FindIssueLinks('See ABC-7.', T);
  AssertEquals(1, Length(L));
  AssertEquals('ABC-7', L[0].Id);
  AssertEquals(5, L[0].Start);
  AssertEquals(5, L[0].Len);
  AssertEquals(0, Length(FindIssueLinks('', T)));
  T.LogRegex := '';
  AssertEquals(0, Length(FindIssueLinks('ABC-7', T)));
end;

procedure TIssueLinksTest.TestTwoRegexes;
var
  T: TGittanIssueTracker;
  L: TGittanIssueLinks;
begin
  T.Url := '';
  T.LogRegex := '[Ii]ssues?:?(\s*(,|and)?\s*#\d+)+'#10'(\d+)';
  L := FindIssueLinks('Done.'#10'Issues: #4, #56 and #7. Also #99 unrelated.', T);
  AssertEquals(3, Length(L));
  AssertEquals('4', L[0].Id);
  AssertEquals('56', L[1].Id);
  AssertEquals('7', L[2].Id);
  { The positions are in the whole text. }
  AssertEquals(Pos('#4', 'Done.'#10'Issues: #4, #56 and #7.') + 1, L[0].Start);
  AssertEquals(Pos('#56', 'Done.'#10'Issues: #4, #56 and #7.') + 1, L[1].Start);
  AssertEquals(2, L[1].Len);
  { Windows line breaks between the two lines. }
  T.LogRegex := 'bug (\d+)'#13#10'\d+';
  L := FindIssueLinks('bug 12 and bug 13', T);
  AssertEquals(2, Length(L));
  AssertEquals('13', L[1].Id);
end;

procedure TIssueLinksTest.TestBadRegex;
var
  T: TGittanIssueTracker;
begin
  T.Url := '';
  T.LogRegex := '(\d+';
  AssertEquals(0, Length(FindIssueLinks('#12', T)));
  T.LogRegex := '(\d+'#10'\d';
  AssertEquals(0, Length(FindIssueLinks('#12', T)));
end;

procedure TIssueLinksTest.TestUrl;
var
  T: TGittanIssueTracker;
begin
  T.LogRegex := DefaultIssueRegex;
  T.Url := '';
  AssertEquals('', IssueUrl(T, '12'));
  T.Url := 'https://example.test/issues/%BUGID%?x=1';
  AssertEquals('https://example.test/issues/12?x=1', IssueUrl(T, '12'));
  T.Url := 'https://example.test/browse/';
  AssertEquals('https://example.test/browse/ABC-7', IssueUrl(T, 'ABC-7'));
end;

initialization
  RegisterTest(TIssueLinksTest);

end.
