unit testupdate;

{** Tests of gittan.update: the build number in a tag, GitHub's answer
  for a release and the comparison. The fetch itself is not tested; it
  needs the network. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.update;

type
  TUpdateTest = class(TTestCase)
  published
    procedure TestBuildOfTag;
    procedure TestParseRelease;
    procedure TestParseReleaseWithoutName;
    procedure TestParseNotARelease;
    procedure TestIsNewerRelease;
  end;

implementation

procedure TUpdateTest.TestBuildOfTag;
begin
  AssertEquals(109, BuildOfTag('build-109'));
  AssertEquals(109, BuildOfTag('Build-109'));
  AssertEquals(-1, BuildOfTag('v1.2'));
  AssertEquals(-1, BuildOfTag('build-'));
  AssertEquals(-1, BuildOfTag('build-12a'));
  AssertEquals(-1, BuildOfTag(''));
end;

procedure TUpdateTest.TestParseRelease;
var
  R: TGittanRelease;
begin
  AssertTrue(ParseRelease('{"tag_name":"build-108","name":"Gittan build 108",' +
    '"html_url":"https://github.com/slicke/gittan/releases/tag/build-108",' +
    '"prerelease":false,"body":"## Changes"}', R));
  AssertEquals('build-108', R.Tag);
  AssertEquals('Gittan build 108', R.Name);
  AssertEquals('https://github.com/slicke/gittan/releases/tag/build-108', R.Url);
  AssertEquals(108, R.Build);
end;

procedure TUpdateTest.TestParseReleaseWithoutName;
var
  R: TGittanRelease;
begin
  AssertTrue(ParseRelease('{"tag_name":"build-5","name":null}', R));
  AssertEquals('the tag stands in for the name', 'build-5', R.Name);
  AssertEquals(LatestReleasePage, R.Url);
end;

procedure TUpdateTest.TestParseNotARelease;
var
  R: TGittanRelease;
begin
  AssertFalse('an error', ParseRelease('{"message":"Not Found"}', R));
  AssertFalse('a list', ParseRelease('[]', R));
  AssertFalse('not JSON', ParseRelease('<html>', R));
  AssertFalse('nothing', ParseRelease('', R));
  AssertEquals(-1, R.Build);
end;

procedure TUpdateTest.TestIsNewerRelease;
var
  R: TGittanRelease;
begin
  R := Default(TGittanRelease);
  R.Build := 109;
  AssertTrue(IsNewerRelease(R, 108));
  AssertFalse('the same build', IsNewerRelease(R, 109));
  AssertFalse('an older release', IsNewerRelease(R, 110));
  AssertFalse('a local build is never told', IsNewerRelease(R, -1));
  R.Build := -1;
  AssertFalse('a release without a number', IsNewerRelease(R, 108));
end;

initialization
  RegisterTest(TUpdateTest);
end.
