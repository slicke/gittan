unit testforge;

{** Tests of gittan.forge: the answer of the forge query read into pull
  requests, and which of those waiting for the user's review still
  are. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, fpcunit, testregistry, gittan.forge;

type
  TForgeTest = class(TTestCase)
  published
    procedure TestParseAnswer;
    procedure TestParseErrors;
    procedure TestNeedsMyReview;
    procedure TestForgeName;
  end;

implementation

const
  Mine = '{"number":41,"title":"Watcher pace","url":"https://github.com/slicke/gittan/pull/41",' +
    '"isDraft":false,"state":"OPEN","reviewDecision":"REVIEW_REQUIRED",' +
    '"createdAt":"2026-10-24T10:00:00Z","updatedAt":"2026-10-25T10:00:00Z",' +
    '"author":{"login":"slicke"},"repository":{"nameWithOwner":"slicke/gittan"},' +
    '"headRefName":"develop","baseRefName":"main","viewerLatestReview":null,' +
    '"viewerLatestReviewRequest":null,' +
    '"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}}';
  Review = '{"number":12,"title":"Fix the thing","url":"https://github.com/owner/repo/pull/12",' +
    '"isDraft":true,"state":"OPEN","reviewDecision":null,' +
    '"createdAt":"2026-10-20T12:34:56Z","updatedAt":"2026-10-22T08:00:00Z",' +
    '"author":{"login":"ada"},"repository":{"nameWithOwner":"owner/repo"},' +
    '"headRefName":"fix/thing","baseRefName":"main",' +
    '"viewerLatestReview":{"state":"APPROVED"},"viewerLatestReviewRequest":{"id":"RR_1"},' +
    '"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}';
  Answer = '{"data":{"viewer":{"login":"slicke"},"mine":{"issueCount":1,"nodes":[' + Mine +
    ']},"review":{"issueCount":2,"nodes":[' + Review + ',{"__typename":"Issue"}]}}}';

procedure TForgeTest.TestParseAnswer;
var
  Login, Error: string;
  MinePulls, ReviewPulls: TGittanForgePulls;
begin
  AssertTrue(ParseForgeAnswer(Answer, Login, MinePulls, ReviewPulls, Error));
  AssertEquals('slicke', Login);
  AssertEquals('', Error);
  AssertEquals(1, Length(MinePulls));
  AssertEquals('slicke/gittan', MinePulls[0].Repo);
  AssertEquals(41, MinePulls[0].Number);
  AssertEquals('Watcher pace', MinePulls[0].Title);
  AssertEquals('https://github.com/slicke/gittan/pull/41', MinePulls[0].Url);
  AssertEquals('slicke', MinePulls[0].Author);
  AssertEquals('develop', MinePulls[0].HeadRef);
  AssertEquals('main', MinePulls[0].BaseRef);
  AssertEquals('OPEN', MinePulls[0].State);
  AssertEquals('REVIEW_REQUIRED', MinePulls[0].ReviewDecision);
  AssertEquals('SUCCESS', MinePulls[0].Checks);
  AssertEquals('', MinePulls[0].MyReview);
  AssertFalse(MinePulls[0].Requested);
  AssertFalse(MinePulls[0].IsDraft);
  AssertEquals(EncodeDateTime(2026, 10, 24, 10, 0, 0, 0), MinePulls[0].Created);
  AssertEquals(EncodeDateTime(2026, 10, 25, 10, 0, 0, 0), MinePulls[0].Updated);
  { The issue among the nodes is skipped. }
  AssertEquals(1, Length(ReviewPulls));
  AssertEquals('owner/repo', ReviewPulls[0].Repo);
  AssertEquals(12, ReviewPulls[0].Number);
  AssertTrue(ReviewPulls[0].IsDraft);
  AssertEquals('', ReviewPulls[0].ReviewDecision);
  AssertEquals('', ReviewPulls[0].Checks);
  AssertEquals('APPROVED', ReviewPulls[0].MyReview);
  AssertTrue(ReviewPulls[0].Requested);
end;

procedure TForgeTest.TestParseErrors;
var
  Login, Error: string;
  MinePulls, ReviewPulls: TGittanForgePulls;
begin
  AssertFalse(ParseForgeAnswer('', Login, MinePulls, ReviewPulls, Error));
  AssertFalse(ParseForgeAnswer('not json', Login, MinePulls, ReviewPulls, Error));
  AssertFalse(ParseForgeAnswer('[]', Login, MinePulls, ReviewPulls, Error));
  AssertFalse(ParseForgeAnswer('{"errors":[{"message":"Bad credentials"}]}', Login,
    MinePulls, ReviewPulls, Error));
  AssertEquals('Bad credentials', Error);
  { Data without the searches is an answer with nothing in it. }
  AssertTrue(ParseForgeAnswer('{"data":{"viewer":{"login":"x"}}}', Login, MinePulls,
    ReviewPulls, Error));
  AssertEquals('x', Login);
  AssertEquals(0, Length(MinePulls));
  AssertEquals(0, Length(ReviewPulls));
end;

procedure TForgeTest.TestNeedsMyReview;
var
  Pull: TGittanForgePull;
  Pulls, Left: TGittanForgePulls;
begin
  Pull := Default(TGittanForgePull);
  AssertTrue(NeedsMyReview(Pull));
  Pull.MyReview := 'COMMENTED';
  AssertTrue(NeedsMyReview(Pull));
  Pull.MyReview := 'DISMISSED';
  AssertTrue(NeedsMyReview(Pull));
  Pull.MyReview := 'APPROVED';
  AssertFalse(NeedsMyReview(Pull));
  Pull.MyReview := 'CHANGES_REQUESTED';
  AssertFalse(NeedsMyReview(Pull));
  { Asked again after the review. }
  Pull.Requested := True;
  AssertTrue(NeedsMyReview(Pull));
  SetLength(Pulls, 3);
  Pulls[0] := Default(TGittanForgePull);
  Pulls[0].Number := 1;
  Pulls[1] := Default(TGittanForgePull);
  Pulls[1].Number := 2;
  Pulls[1].MyReview := 'APPROVED';
  Pulls[2] := Pull;
  Pulls[2].Number := 3;
  Left := StillToReview(Pulls);
  AssertEquals(2, Length(Left));
  AssertEquals(1, Left[0].Number);
  AssertEquals(3, Left[1].Number);
  AssertEquals(0, Length(StillToReview(nil)));
end;

procedure TForgeTest.TestForgeName;
begin
  AssertEquals('GitHub', ForgeName(fkGitHub));
end;

initialization
  RegisterTest(TForgeTest);

end.
