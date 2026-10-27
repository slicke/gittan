unit gittan.update;

{** Is there a newer Gittan on GitHub? Modelled on Trndi's update check.
  Every push to main publishes a release tagged build-<n>, and CI compiles
  that number into the build it packages (GITTAN_BUILD, see GittanBuild).
  The check asks GitHub's API for the latest release (gittan.http), and a
  release is newer when its tag's number is above ours. A local build has
  no number, so it is never told about one. No LCL: the form shows the
  result. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.job;

const
  {** The build number CI compiled in, from the environment variable
    GITTAN_BUILD at compile time; empty in a local or pull request
    build, which is what the warning that it is not set means. }
  {$PUSH}{$WARN 2054 OFF}
  GittanBuild = {$I %GITTAN_BUILD%};
  {$POP}

  {** The latest release, as GitHub's API answers it. }
  LatestReleaseApi = 'https://api.github.com/repos/slicke/gittan/releases/latest';
  {** The page of the latest release, for when the answer names none. }
  LatestReleasePage = 'https://github.com/slicke/gittan/releases/latest';

type
  {** A release on GitHub: its tag (build-109), its title, its page and
    the build number its tag gives, -1 for a tag of another form. }
  TGittanRelease = record
    Tag, Name, Url: string;
    Build: integer;
  end;

  { TGittanUpdateJob }

  {** Asks GitHub for the latest release in a thread and calls OnDone on
    the main thread with the result. }
  TGittanUpdateJob = class(TGittanJob)
  private
    FRelease: TGittanRelease;
    FOk: boolean;
    FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create;
    {** Whether GitHub answered with a release. }
    property Ok: boolean read FOk;
    property Release: TGittanRelease read FRelease;
    {** Why there is no answer (no network, an error from GitHub), else
      empty. }
    property Error: string read FError;
  end;

{** The build number in a tag such as build-109, -1 for any other tag. }
function BuildOfTag(const ATag: string): integer;

{** This build's number, -1 for a local build. }
function CurrentBuild: integer;

{** Reads GitHub's answer for one release; False when it is not one (an
  error message, say). }
function ParseRelease(const AJson: string; out ARelease: TGittanRelease): boolean;

{** Whether ARelease is newer than build ACurrent; never for a local
  build (ACurrent -1) or a release without a build number. }
function IsNewerRelease(const ARelease: TGittanRelease; ACurrent: integer): boolean;

{** Asks GitHub's API for AUrl and answers whether it answered with a
  success, with the body in ABody and, on failure, why in AError. }
function FetchUrl(const AUrl: string; out ABody, AError: string): boolean;

implementation

uses
  fpjson, jsonparser, gittan.http;

const
  TagPrefix = 'build-';
  { Long enough for a slow network, short enough not to keep a thread
    hanging at exit. }
  FetchSeconds = 10;

function BuildOfTag(const ATag: string): integer;
begin
  Result := -1;
  if SameText(Copy(ATag, 1, Length(TagPrefix)), TagPrefix) then
    Result := StrToIntDef(Copy(ATag, Length(TagPrefix) + 1, MaxInt), -1);
  if Result < 0 then
    Result := -1;
end;

function CurrentBuild: integer;
begin
  Result := StrToIntDef(GittanBuild, -1);
  if Result < 0 then
    Result := -1;
end;

function ParseRelease(const AJson: string; out ARelease: TGittanRelease): boolean;
var
  Data: TJSONData;
  Obj: TJSONObject;
begin
  Result := False;
  ARelease := Default(TGittanRelease);
  ARelease.Build := -1;
  Data := nil;
  try
    try
      Data := GetJSON(AJson);
    except
      Exit;
    end;
    if not (Data is TJSONObject) then
      Exit;
    Obj := TJSONObject(Data);
    ARelease.Tag := Obj.Get('tag_name', '');
    if ARelease.Tag = '' then
      Exit;
    ARelease.Name := Obj.Get('name', '');
    if ARelease.Name = '' then
      ARelease.Name := ARelease.Tag;
    ARelease.Url := Obj.Get('html_url', '');
    if ARelease.Url = '' then
      ARelease.Url := LatestReleasePage;
    ARelease.Build := BuildOfTag(ARelease.Tag);
    Result := True;
  finally
    Data.Free;
  end;
end;

function IsNewerRelease(const ARelease: TGittanRelease; ACurrent: integer): boolean;
begin
  Result := (ACurrent >= 0) and (ARelease.Build > ACurrent);
end;

function FetchUrl(const AUrl: string; out ABody, AError: string): boolean;
var
  Response: TGittanHttpResponse;
begin
  Response := HttpGet(AUrl, ['Accept: application/vnd.github+json'], FetchSeconds);
  Result := HttpOk(Response);
  if Result then
  begin
    ABody := Response.Body;
    AError := '';
  end
  else
  begin
    ABody := '';
    AError := HttpFailure(Response);
  end;
end;

{ TGittanUpdateJob }

constructor TGittanUpdateJob.Create;
begin
  inherited Create(True);
end;

procedure TGittanUpdateJob.Execute;
var
  Body: string;
begin
  if FetchUrl(LatestReleaseApi, Body, FError) then
  begin
    FOk := ParseRelease(Body, FRelease);
    if not FOk then
      FError := 'GitHub did not answer with a release.';
  end;
  Done;
end;

end.
