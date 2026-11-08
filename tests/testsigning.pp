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
  AssertTrue(Error, CommitSignatures(FDir, [Signed, Plain], nil, Commits, Error));
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
  AssertTrue(Error, CommitSignatures(FDir, [Plain, Signed], nil, Commits, Error));
  AssertTrue(Commits[0].Signature.State = ssNone);
  AssertTrue('good', Commits[1].Signature.State = ssGood);
  AssertEquals('G', Commits[1].Signature.Code);
  AssertEquals('test@example.invalid', Commits[1].Signature.Signer);
  AssertTrue('a fingerprint: ' + Commits[1].Signature.Key, Pos('SHA256:', Commits[1].Signature.Key) = 1);

  { Another key allowed: a valid signature by a key not known here. }
  WriteFile('allowed', 'other@example.invalid ' + FileText(FDir + PathDelim + 'other.pub'));
  AssertTrue(Error, CommitSignatures(FDir, [Signed], nil, Commits, Error));
  AssertTrue('unknown key', Commits[0].Signature.State = ssUnknownKey);
  AssertEquals('U', Commits[0].Signature.Code);

  { Nothing asked for. }
  AssertTrue(CommitSignatures(FDir, [], nil, Commits, Error));
  AssertEquals(0, Length(Commits));
  { A hash that is no commit fails. }
  AssertFalse(CommitSignatures(FDir, ['0000000000000000000000000000000000000000'], nil, Commits, Error));
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
  Job := TGittanSignJob.Create(FDir, Hashes);
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

initialization
  RegisterTest(TSigningTest);

end.
