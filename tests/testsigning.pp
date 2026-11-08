unit testsigning;

{** Tests of gittan.signing: the signature headers and verdicts read
  from git's output, the cache, and against a repository with an SSH
  key made for the test (skipped where ssh-keygen cannot be run):
  signed and unsigned commits with no allowed signers file, with the
  key allowed and with another key allowed, one by one and through the
  job. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.git, gittan.signing, testhelpers;

type
  TSigningTest = class(TTestCase)
  private
    FDir: string;
    function Git(const AArgs: array of string): string;
    function MakeKey: boolean;
    procedure WriteFile(const AName, AText: string);
    function Commit(const AMessage: string; ASign: boolean): string;
    function FileText(const AName: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestParseHeaders;
    procedure TestVerdicts;
    procedure TestCache;
    procedure TestSshSignatures;
    procedure TestJob;
    procedure TestSetup;
    procedure TestKeys;
    procedure TestTrust;
  end;

implementation

{$IFDEF UNIX}
uses
  BaseUnix;
{$ENDIF}

procedure TSigningTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-signing-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
  Git(['init', '-q']);
  Git(['config', 'user.name', 'Gittan Test']);
  Git(['config', 'user.email', 'test@example.invalid']);
end;

procedure TSigningTest.TearDown;
begin
  RemoveTree(FDir);
end;

function TSigningTest.Git(const AArgs: array of string): string;
var
  Err: string;
begin
  if not RunGitIn(FDir, AArgs, Result, Err) then
    Fail('git ' + AArgs[0] + ' failed: ' + Err);
end;

{ An ed25519 key pair without a passphrase, key and key.pub in the
  folder, and "other" beside it. RunTool refuses an empty argument on
  Unix, so the shell passes -N "" there. False when ssh-keygen cannot
  be run. }
function TSigningTest.MakeKey: boolean;
var
  Output, Error: string;
  Status: integer;
  Name: string;
begin
  Result := True;
  for Name in ['key', 'other'] do
  begin
    {$IFDEF WINDOWS}
    Result := RunTool('ssh-keygen', FDir, ['-q', '-t', 'ed25519', '-N', '', '-f', Name], [], [],
      Output, Error, Status, nil) and (Status = 0);
    {$ELSE}
    Result := RunTool('/bin/sh', FDir, ['-c', 'ssh-keygen -q -t ed25519 -N "" -f ' + Name],
      [], [], Output, Error, Status, nil) and (Status = 0);
    if Result then
      FpChmod(FDir + PathDelim + Name, &600);
    {$ENDIF}
    if not Result then
      Exit;
  end;
end;

procedure TSigningTest.WriteFile(const AName, AText: string);
var
  F: TFileStream;
begin
  F := TFileStream.Create(FDir + PathDelim + AName, fmCreate);
  try
    if AText <> '' then
      F.WriteBuffer(AText[1], Length(AText));
  finally
    F.Free;
  end;
end;

function TSigningTest.FileText(const AName: string): string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(AName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

function TSigningTest.Commit(const AMessage: string; ASign: boolean): string;
begin
  Git(['add', '-A']);
  if ASign then
    Git(['-c', 'gpg.format=ssh', '-c', 'user.signingkey=' + FDir + PathDelim + 'key.pub',
      'commit', '-q', '-S', '-m', AMessage])
  else
    Git(['commit', '-q', '--no-gpg-sign', '-m', AMessage]);
  Result := Trim(Git(['rev-parse', 'HEAD']));
end;

procedure TSigningTest.TestParseHeaders;
const
  Output = 'aaaa'#10'tree 1111'#10'parent 2222'#10'author A <a@x> 1 +0000'#10 +
    'committer A <a@x> 1 +0000'#10'gpgsig -----BEGIN PGP SIGNATURE-----'#10 +
    ' iQEzBAAB'#10' -----END PGP SIGNATURE-----'#10#10'    signed with gpg'#10#0 +
    'bbbb'#10'tree 1111'#10'author A <a@x> 1 +0000'#10'committer A <a@x> 1 +0000'#10#10 +
    '    plain, with a gpgsig word in the body'#10'    gpgsig -----BEGIN SSH SIGNATURE-----'#10#0 +
    'cccc'#10'tree 1111'#10'gpgsig-sha256 -----BEGIN SSH SIGNATURE-----'#10' U1NI'#10 +
    ' -----END SSH SIGNATURE-----'#10#10'    ssh'#10#0 +
    'dddd'#10'tree 1111'#10'gpgsig -----BEGIN SIGNED MESSAGE-----'#10' MII'#10#10'    x509'#10#0;
var
  Commits: TGittanSignedCommits;
begin
  Commits := ParseSignatureHeaders(Output);
  AssertEquals(4, Length(Commits));
  AssertEquals('aaaa', Commits[0].Hash);
  AssertTrue(Commits[0].Signature.Format = sfOpenPgp);
  AssertTrue(Commits[0].Signature.State = ssUnchecked);
  AssertEquals('bbbb', Commits[1].Hash);
  AssertTrue('the body is not a header', Commits[1].Signature.Format = sfNone);
  AssertTrue(Commits[1].Signature.State = ssNone);
  AssertTrue(Commits[2].Signature.Format = sfSsh);
  AssertTrue(Commits[3].Signature.Format = sfX509);
  AssertEquals(0, Length(ParseSignatureHeaders('')));
end;

procedure TSigningTest.TestVerdicts;
var
  Commits: TGittanSignedCommits;
begin
  Commits := ParseSignatureHeaders('aaaa'#10'gpgsig -----BEGIN SSH SIGNATURE-----'#10#10'    a'#0 +
    'bbbb'#10'gpgsig -----BEGIN PGP SIGNATURE-----'#10#10'    b'#0 +
    'cccc'#10'tree 1'#10#10'    c'#0 +
    'dddd'#10'gpgsig -----BEGIN PGP SIGNATURE-----'#10#10'    d'#0 +
    'eeee'#10'gpgsig -----BEGIN PGP SIGNATURE-----'#10#10'    e'#0);
  ApplyVerdicts('aaaa'#31'G'#31'ada@example.invalid'#31'SHA256:abc'#31'fully'#0 +
    'bbbb'#31'E'#31#31'0123ABCD'#31'undefined'#0 +
    'cccc'#31'G'#31'nobody'#31'k'#31'fully'#0 +
    'dddd'#31'Y'#31'Old Key'#31'DEAD'#31'expired'#0 +
    'eeee'#31'N'#31#31#31'undefined'#0, Commits);
  AssertTrue(Commits[0].Signature.State = ssGood);
  AssertEquals('ada@example.invalid', Commits[0].Signature.Signer);
  AssertEquals('SHA256:abc', Commits[0].Signature.Key);
  AssertEquals('fully', Commits[0].Signature.Trust);
  AssertTrue('gpg without the public key', Commits[1].Signature.State = ssUnknownKey);
  AssertEquals('', Commits[1].Signature.Trust);
  AssertTrue('a verdict never makes an unsigned commit signed', Commits[2].Signature.State = ssNone);
  AssertTrue(Commits[3].Signature.State = ssBad);
  AssertEquals('Y', Commits[3].Signature.Code);
  AssertTrue('N on a signed commit: the verifier did not run', Commits[4].Signature.State = ssUnchecked);
  AssertEquals('N', Commits[4].Signature.Code);
  AssertTrue(SignStateOf('B') = ssBad);
  AssertTrue(SignStateOf('X') = ssBad);
  AssertTrue(SignStateOf('R') = ssBad);
  AssertTrue(SignStateOf('U') = ssUnknownKey);
end;

procedure TSigningTest.TestCache;
var
  Cache: TGittanSignatureCache;
  S: TGittanSignature;
  Unknown: TStringArray;
begin
  Cache := TGittanSignatureCache.Create;
  try
    AssertFalse(Cache.Find('aaaa', S));
    S := Default(TGittanSignature);
    S.State := ssGood;
    S.Signer := 'Ada';
    Cache.Put('aaaa', S);
    S.State := ssNone;
    Cache.Put('bbbb', S);
    AssertEquals(2, Cache.Count);
    AssertTrue(Cache.Find('aaaa', S));
    AssertTrue(S.State = ssGood);
    AssertEquals('Ada', S.Signer);
    AssertTrue(Cache.Find('bbbb', S));
    AssertTrue(S.State = ssNone);
    S.State := ssBad;
    Cache.Put('aaaa', S);
    AssertEquals('put again replaces', 2, Cache.Count);
    AssertTrue(Cache.Find('aaaa', S));
    AssertTrue(S.State = ssBad);
    Unknown := Cache.Unknown(['cccc', 'aaaa', '', 'dddd']);
    AssertEquals(2, Length(Unknown));
    AssertEquals('cccc', Unknown[0]);
    AssertEquals('dddd', Unknown[1]);
    Cache.Clear;
    AssertEquals(0, Cache.Count);
    AssertFalse(Cache.Find('aaaa', S));
  finally
    Cache.Free;
  end;
end;

procedure TSigningTest.TestSshSignatures;
var
  Signed, Plain, Error: string;
  Commits: TGittanSignedCommits;
begin
  if not MakeKey then
  begin
    Ignore('ssh-keygen cannot be run here');
    Exit;
  end;
  WriteFile('a.txt', 'a'#10);
  Plain := Commit('plain', False);
  WriteFile('b.txt', 'b'#10);
  Signed := Commit('signed', True);

  { No allowed signers file: git says N, which is not taken for unsigned. }
  AssertTrue(Error, CommitSignatures(FDir, [Signed, Plain], nil, Commits, Error, []));
  AssertEquals(2, Length(Commits));
  AssertEquals('in the order asked for', Signed, Commits[0].Hash);
  AssertTrue(Commits[0].Signature.Format = sfSsh);
  AssertTrue('signed, unchecked', Commits[0].Signature.State = ssUnchecked);
  AssertEquals('N', Commits[0].Signature.Code);
  AssertEquals(Plain, Commits[1].Hash);
  AssertTrue(Commits[1].Signature.State = ssNone);
  AssertTrue(Commits[1].Signature.Format = sfNone);

  { The key allowed for the committer: good, with the principal and the
    key's fingerprint. }
  WriteFile('allowed', 'test@example.invalid ' + FileText(FDir + PathDelim + 'key.pub'));
  Git(['config', 'gpg.ssh.allowedSignersFile', FDir + PathDelim + 'allowed']);
  AssertTrue(Error, CommitSignatures(FDir, [Plain, Signed], nil, Commits, Error, []));
  AssertTrue(Commits[0].Signature.State = ssNone);
  AssertTrue('good', Commits[1].Signature.State = ssGood);
  AssertEquals('G', Commits[1].Signature.Code);
  AssertEquals('test@example.invalid', Commits[1].Signature.Signer);
  AssertTrue('a fingerprint: ' + Commits[1].Signature.Key, Pos('SHA256:', Commits[1].Signature.Key) = 1);

  { Another key allowed: a valid signature by a key not known here. }
  WriteFile('allowed', 'other@example.invalid ' + FileText(FDir + PathDelim + 'other.pub'));
  AssertTrue(Error, CommitSignatures(FDir, [Signed], nil, Commits, Error, []));
  AssertTrue('unknown key', Commits[0].Signature.State = ssUnknownKey);
  AssertEquals('U', Commits[0].Signature.Code);

  { Nothing asked for. }
  AssertTrue(CommitSignatures(FDir, [], nil, Commits, Error, []));
  AssertEquals(0, Length(Commits));
  { A hash that is no commit fails. }
  AssertFalse(CommitSignatures(FDir, ['0000000000000000000000000000000000000000'], nil, Commits, Error, []));
end;

procedure TSigningTest.TestJob;
var
  Hashes: TStringArray;
  i: integer;
  Job: TGittanSignJob;
  Cache: TGittanSignatureCache;
  S: TGittanSignature;
begin
  if not MakeKey then
  begin
    Ignore('ssh-keygen cannot be run here');
    Exit;
  end;
  WriteFile('allowed', 'test@example.invalid ' + FileText(FDir + PathDelim + 'key.pub'));
  Git(['config', 'gpg.ssh.allowedSignersFile', FDir + PathDelim + 'allowed']);
  { More commits than a chunk, every third signed. }
  SetLength(Hashes, SignChunk + 5);
  for i := 0 to High(Hashes) do
  begin
    WriteFile('f.txt', IntToStr(i) + #10);
    Hashes[i] := Commit('c' + IntToStr(i), i mod 3 = 0);
  end;
  Job := TGittanSignJob.Create(FDir, Hashes, []);
  Cache := TGittanSignatureCache.Create;
  try
    Job.Start;
    Job.WaitFor;
    AssertEquals(Length(Hashes), Job.Finished);
    AssertEquals('', Job.Error);
    Cache.PutAll(Job.Results, Job.Finished);
    AssertEquals(Length(Hashes), Cache.Count);
    for i := 0 to High(Hashes) do
    begin
      AssertEquals(Hashes[i], Job.Results[i].Hash);
      AssertTrue(Cache.Find(Hashes[i], S));
      if i mod 3 = 0 then
        AssertTrue('signed ' + IntToStr(i), S.State = ssGood)
      else
        AssertTrue('plain ' + IntToStr(i), S.State = ssNone);
    end;
    AssertEquals(0, Length(Cache.Unknown(Hashes)));
  finally
    Cache.Free;
    Job.Free;
  end;
end;

{ The setup is written to the repository's own config alone, so the
  user's global config is left as it is; the allowed signers file is set
  there first for the same reason. }
procedure TSigningTest.TestSetup;
var
  Cfg: TGittanSigningSetup;
  Error, Id, Allowed: string;
  Commits: TGittanSignedCommits;
begin
  if not MakeKey then
  begin
    Ignore('ssh-keygen cannot be run here');
    Exit;
  end;
  Cfg := ReadSigningSetup(FDir);
  AssertFalse(Cfg.Sign);
  AssertEquals('', Cfg.Key);
  Allowed := FDir + PathDelim + 'allowed';
  Git(['config', 'gpg.ssh.allowedSignersFile', Allowed]);

  Cfg.Sign := True;
  Cfg.Format := sfSsh;
  Cfg.Key := FDir + PathDelim + 'key.pub';
  AssertTrue(Error, WriteSigningSetup(FDir, Cfg, 'test@example.invalid', True, Error));
  Cfg := ReadSigningSetup(FDir);
  AssertTrue(Cfg.Sign);
  AssertTrue(Cfg.Format = sfSsh);
  AssertEquals(FDir + PathDelim + 'key.pub', Cfg.Key);
  AssertEquals('true', Trim(Git(['config', '--local', 'tag.gpgSign'])));
  AssertEquals(Allowed, Cfg.AllowedSigners);
  AssertTrue('the allowed signers file was made', FileExists(Allowed));
  AssertEquals('test@example.invalid ' + PublicKeyOf(Cfg.Key) + LineEnding, FileText(Allowed));
  { Written again: the line is not doubled. }
  AssertTrue(Error, WriteSigningSetup(FDir, Cfg, 'test@example.invalid', True, Error));
  AssertEquals('test@example.invalid ' + PublicKeyOf(Cfg.Key) + LineEnding, FileText(Allowed));

  { A commit signed as set up verifies, and is on no branch. }
  AssertTrue(Error, gittan.signing.TestSigning(FDir, Cfg, Id, Error));
  AssertEquals(40, Length(Id));
  AssertTrue(Error, CommitSignatures(FDir, [Id], nil, Commits, Error, []));
  AssertTrue('verified', Commits[0].Signature.State = ssGood);
  AssertEquals('', Trim(Git(['branch', '--contains', Id])));
  { A key that is not there fails with git's reason. }
  Cfg.Key := FDir + PathDelim + 'nope.pub';
  AssertFalse(gittan.signing.TestSigning(FDir, Cfg, Id, Error));
  AssertTrue(Error, Pos('nope.pub', Error) > 0);

  { Off again: both keys unset, the format and key kept. }
  Cfg.Sign := False;
  AssertTrue(Error, WriteSigningSetup(FDir, Cfg, 'test@example.invalid', True, Error));
  Cfg := ReadSigningSetup(FDir);
  AssertFalse(Cfg.Sign);
  AssertTrue(Cfg.Format = sfSsh);
  AssertFalse(RunGitIn(FDir, ['config', '--local', 'tag.gpgSign'], Id, Error));
end;

procedure TSigningTest.TestKeys;
var
  Keys: TStringArray;
  Error: string;
begin
  AssertEquals('ssh', SignFormatName(sfSsh));
  AssertEquals('openpgp', SignFormatName(sfOpenPgp));
  AssertEquals('x509', SignFormatName(sfX509));
  AssertTrue(SignFormatOf('') = sfOpenPgp);
  AssertTrue(SignFormatOf('SSH') = sfSsh);
  AssertTrue(SignFormatOf('x509') = sfX509);

  Keys := ParseGpgSecretKeys(
    'sec:u:255:22:ABCDEF0123456789:1700000000:::u:::scESC:::+:::ed25519:::0:'#10 +
    'fpr:::::::::FFFF:'#10 +
    'uid:u::::1700000000::HASH::Ada <ada@example.invalid>::::::::::0:'#10 +
    'uid:u::::1700000000::HASH::Ada at work <ada@work.invalid>::::::::::0:'#10 +
    'ssb:u:255:18:SUBKEY:1700000000::::::e:::+:::cv25519:'#10 +
    'sec:e:255:22:0000000000000000:1600000000:1600000001::u:::scESC:::+:::ed25519:::0:'#10 +
    'uid:e::::1600000000::HASH::Old <old@example.invalid>::::::::::0:'#10 +
    'sec:r:255:22:1111111111111111:1600000000:::u:::scESC:::+:::ed25519:::0:'#10 +
    'uid:r::::1600000000::HASH::Gone <gone@example.invalid>::::::::::0:'#10);
  AssertEquals('one key, its first user id, expired and revoked left out', 1, Length(Keys));
  AssertEquals('ABCDEF0123456789'#31'Ada <ada@example.invalid>', Keys[0]);
  AssertEquals(0, Length(ParseGpgSecretKeys('')));

  AssertFalse(GpgSecretKeys('', Keys, Error));
  AssertFalse(GpgSecretKeys(FDir + PathDelim + 'no-such-gpg', Keys, Error));

  WriteFile('b.pub', 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEx bjorn@laptop'#10);
  WriteFile('a.pub', 'ssh-rsa AAAAB3NzaC1yc2E'#10);
  WriteFile('a', 'private');
  Keys := SshPublicKeysIn(FDir);
  AssertEquals(2, Length(Keys));
  AssertEquals(FDir + PathDelim + 'a.pub', Keys[0]);
  AssertEquals(FDir + PathDelim + 'b.pub', Keys[1]);
  AssertEquals(0, Length(SshPublicKeysIn(FDir + PathDelim + 'nowhere')));

  AssertEquals('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEx', PublicKeyOf(FDir + PathDelim + 'b.pub'));
  AssertEquals('ssh-ed25519 AAAA', PublicKeyOf('key::ssh-ed25519 AAAA comment'));
  AssertEquals('ssh-ed25519 AAAA', PublicKeyOf('ssh-ed25519 AAAA'));
  AssertEquals('', PublicKeyOf('ABCDEF'));
  AssertEquals('', PublicKeyOf(FDir + PathDelim + 'nope.pub'));

  AssertTrue(Error, AddAllowedSigner(FDir + PathDelim + 'deep' + PathDelim + 'allowed',
    'a@x', 'ssh-ed25519 AAAA c', Error));
  AssertEquals('a@x ssh-ed25519 AAAA' + LineEnding, FileText(FDir + PathDelim + 'deep' + PathDelim + 'allowed'));
  AssertTrue(Error, AddAllowedSigner(FDir + PathDelim + 'deep' + PathDelim + 'allowed',
    'b@x', 'ssh-ed25519 BBBB', Error));
  AssertTrue(Error, AddAllowedSigner(FDir + PathDelim + 'deep' + PathDelim + 'allowed',
    'c@x', 'key::ssh-ed25519 AAAA', Error));
  AssertEquals('a@x ssh-ed25519 AAAA' + LineEnding + 'b@x ssh-ed25519 BBBB' + LineEnding,
    FileText(FDir + PathDelim + 'deep' + PathDelim + 'allowed'));
  AssertFalse(AddAllowedSigner(FDir + PathDelim + 'allowed2', 'a@x', 'nonsense', Error));
  AssertTrue(Pos('nonsense', Error) > 0);
end;

procedure TSigningTest.TestTrust;
var
  Commits: TGittanSignedCommits;
  Entry: string;
  Fprs: TStringArray;
begin
  Entry := TrustEntry('abcdef0123456789abcdef0123456789abcdef01', 'github.com', 'web-flow');
  AssertEquals('ABCDEF0123456789ABCDEF0123456789ABCDEF01', TrustEntryKey(Entry));
  Commits := ParseSignatureHeaders('aaaa'#10'gpgsig -----BEGIN PGP SIGNATURE-----'#10#10'    a'#0 +
    'bbbb'#10'gpgsig -----BEGIN PGP SIGNATURE-----'#10#10'    b'#0 +
    'cccc'#10'gpgsig -----BEGIN PGP SIGNATURE-----'#10#10'    c'#0 +
    'dddd'#10'gpgsig -----BEGIN PGP SIGNATURE-----'#10#10'    d'#0);
  ApplyVerdicts('aaaa'#31'U'#31'GitHub <noreply@github.com>'#31'B5690EEEBB952194'#31'undefined'#31 +
    'abcdef0123456789abcdef0123456789abcdef01'#31'abcdef0123456789abcdef0123456789abcdef01'#0 +
    'bbbb'#31'U'#31'Sub'#31'1111'#31'undefined'#31'1111111111111111111111111111111111111111'#31 +
    'ABCDEF0123456789ABCDEF0123456789ABCDEF01'#0 +
    'cccc'#31'U'#31'Other'#31'2222'#31'undefined'#31'2222222222222222222222222222222222222222'#31 +
    '2222222222222222222222222222222222222222'#0 +
    'dddd'#31'B'#31'Bad'#31'3333'#31'undefined'#31'abcdef0123456789abcdef0123456789abcdef01'#31 +
    'abcdef0123456789abcdef0123456789abcdef01'#0, Commits);
  AssertEquals('ABCDEF0123456789ABCDEF0123456789ABCDEF01', Commits[0].Signature.Fingerprint);
  ApplyTrust(Commits, [Entry]);
  AssertTrue('the key itself', Commits[0].Signature.State = ssTrusted);
  AssertEquals('github.com', Commits[0].Signature.TrustedFrom);
  AssertEquals('web-flow', Commits[0].Signature.TrustedUser);
  AssertEquals('the signer git names is kept', 'GitHub <noreply@github.com>', Commits[0].Signature.Signer);
  AssertTrue('a subkey of it', Commits[1].Signature.State = ssTrusted);
  AssertTrue('another key', Commits[2].Signature.State = ssUnknownKey);
  AssertTrue('a bad signature is never trusted', Commits[3].Signature.State = ssBad);
  ApplyTrust(Commits, []);
  AssertTrue(Commits[2].Signature.State = ssUnknownKey);

  Fprs := ParseGpgImport('gpg: key B5690EEEBB952194: public key imported'#10 +
    '[GNUPG:] IMPORTED B5690EEEBB952194 GitHub <noreply@github.com>'#10 +
    '[GNUPG:] IMPORT_OK 1 5DE3E0509C47EA3CF04A42D34AEE18F83AFDEB23'#10 +
    '[GNUPG:] IMPORT_OK 0 4AEE18F83AFDEB23'#10 +
    '[GNUPG:] IMPORT_RES 2 0 1 0 1 0 0 0 0 1 0 0 0 0 0 0 0'#10);
  AssertEquals(2, Length(Fprs));
  AssertEquals('5DE3E0509C47EA3CF04A42D34AEE18F83AFDEB23', Fprs[0]);
  AssertEquals(0, Length(ParseGpgImport('gpg: no valid OpenPGP data found.')));
  AssertFalse(ImportGpgKeys('', '-----BEGIN PGP PUBLIC KEY BLOCK-----', Fprs, Entry));
  AssertFalse(ImportGpgKeys(FDir + PathDelim + 'no-such-gpg', 'x', Fprs, Entry));
end;

initialization
  RegisterTest(TSigningTest);

end.
