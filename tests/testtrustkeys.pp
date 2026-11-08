unit testtrustkeys;

{** Tests of gittan.trustkeys: what is read from GitHub's answers about
  a commit and a user's keys, and the API base per host. The network
  is not touched. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.trustkeys;

type
  TTrustKeysTest = class(TTestCase)
  published
    procedure TestApiBase;
    procedure TestCommitLogins;
    procedure TestUserKeys;
  end;

implementation

procedure TTrustKeysTest.TestApiBase;
begin
  AssertEquals('https://api.github.com', GitHubApiBase('github.com'));
  AssertEquals('https://api.github.com', GitHubApiBase(''));
  AssertEquals('https://ghe.example.invalid/api/v3', GitHubApiBase('ghe.example.invalid'));
end;

procedure TTrustKeysTest.TestCommitLogins;
var
  Logins: TStringArray;
  Author, Committer: string;
begin
  Logins := ParseGitHubCommitLogins('{"sha":"abc","author":{"login":"slicke"},' +
    '"committer":{"login":"web-flow"},"commit":{"verification":{"verified":true}}}');
  AssertEquals(2, Length(Logins));
  AssertEquals('slicke', Logins[0]);
  AssertEquals('web-flow', Logins[1]);
  Logins := ParseGitHubCommitLogins('{"author":{"login":"slicke"},"committer":{"login":"slicke"}}');
  AssertEquals('the same person once', 1, Length(Logins));
  Logins := ParseGitHubCommitLogins('{"author":null,"committer":{"login":"web-flow"}}');
  AssertEquals(1, Length(Logins));
  AssertEquals('web-flow', Logins[0]);
  AssertEquals(0, Length(ParseGitHubCommitLogins('{"message":"Not Found"}')));
  AssertEquals(0, Length(ParseGitHubCommitLogins('not json')));
  { The two apart, so a key is bound to its owner's e-mail alone. }
  ParseGitHubCommitPeople('{"author":{"login":"slicke"},"committer":{"login":"web-flow"}}',
    Author, Committer);
  AssertEquals('slicke', Author);
  AssertEquals('web-flow', Committer);
  ParseGitHubCommitPeople('{"author":null,"committer":{"login":"web-flow"}}', Author, Committer);
  AssertEquals('', Author);
  AssertEquals('web-flow', Committer);
  ParseGitHubCommitPeople('not json', Author, Committer);
  AssertEquals('', Author);
  AssertEquals('', Committer);
end;

procedure TTrustKeysTest.TestUserKeys;
var
  Keys: TGittanForgeKeys;
begin
  Keys := Default(TGittanForgeKeys);
  ParseGitHubGpgKeys('[{"id":1,"key_id":"B5690EEEBB952194","raw_key":"-----BEGIN PGP PUBLIC KEY ' +
    'BLOCK-----\nxx\n-----END PGP PUBLIC KEY BLOCK-----","emails":[{"email":"noreply@github.com",' +
    '"verified":true}]},{"id":2,"raw_key":null,"emails":[]},{"id":3,"raw_key":"-----BEGIN PGP ' +
    'PUBLIC KEY BLOCK-----\nyy","emails":[{"email":"ada@example.invalid","verified":true},' +
    '{"email":"noreply@github.com"},{"email":"eve@example.invalid","verified":false}]}]',
    Keys);
  AssertEquals('a null key is left out', 2, Length(Keys.GpgKeys));
  AssertTrue(Pos('xx', Keys.GpgKeys[0]) > 0);
  AssertEquals('only the verified addresses', 2, Length(Keys.Emails));
  AssertEquals('noreply@github.com', Keys.Emails[0]);
  AssertEquals('ada@example.invalid', Keys.Emails[1]);
  ParseGitHubSshKeys('[{"id":5,"key":"ssh-ed25519 AAAAC3 ada","title":"laptop"},{"id":6,"key":' +
    '"ssh-ed25519 AAAAC3 ada"}]', Keys);
  AssertEquals('the same key once', 1, Length(Keys.SshKeys));
  AssertEquals('ssh-ed25519 AAAAC3 ada', Keys.SshKeys[0]);
  ParseGitHubSshKeys('{"message":"Not Found"}', Keys);
  ParseGitHubSshKeys('', Keys);
  AssertEquals(1, Length(Keys.SshKeys));
end;

initialization
  RegisterTest(TTrustKeysTest);

end.
