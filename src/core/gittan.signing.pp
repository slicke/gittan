unit gittan.signing;

{** Commit signatures: what a commit was signed with and what git makes
  of the signature, read for the commit graph's rows and the card of
  the commit shown. git verifies through gpg (OpenPGP and X.509) or
  ssh-keygen (SSH), and when the verifier is missing, or an SSH
  signature has no allowed signers file to check against, it reports
  the commit as unsigned (%G? gives N) and only complains on stderr;
  so the signature header is read apart from the verdict (git rev-list
  --header shows it), and a signed commit git could not check is told
  apart from one that was never signed. Verifying runs gpg or
  ssh-keygen once per signed commit, some milliseconds each, so the
  graph's commits are verified on a thread, a chunk at a time, and
  what was found is kept per commit for the repository's lifetime. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.git, gittan.job;

type
  {** What the signature of a commit came to: none (never signed), good
    (git vouches for it: G), by a key not known here (a valid signature
    whose key or signer git cannot vouch for: U, and gpg's E when the
    public key is missing), bad (B, or an expired or revoked key: X, Y,
    R; Code tells which), or unchecked (signed, but the verifier could
    not run: no gpg, or no allowed signers file for an SSH signature). }
  TGittanSignState = (ssNone, ssGood, ssUnknownKey, ssBad, ssUnchecked);

  {** How a commit was signed, from the first line of its signature. }
  TGittanSignFormat = (sfNone, sfSsh, sfOpenPgp, sfX509);

  TGittanSignature = record
    State: TGittanSignState;
    Format: TGittanSignFormat;
    {** git's own letter (%G?): G, B, U, X, Y, R, E or N; ' ' when it
      was not asked. }
    Code: char;
    {** The signer git names (%GS: the principal of an SSH signature's
      allowed signers entry, a gpg key's user id), the key (%GK: an
      SSH key's fingerprint, a gpg key id) and gpg's trust level (%GT);
      what git gave, '' for nothing. }
    Signer, Key, Trust: string;
  end;

  TGittanSignedCommit = record
    Hash: string;
    Signature: TGittanSignature;
  end;
  TGittanSignedCommits = array of TGittanSignedCommit;

  {** What was found about the commits of a repository, by hash, so a
    commit is verified once however often the graph shows it. }
  TGittanSignatureCache = class
  private
    FHashes: TStringList;
    FSignatures: TGittanSignedCommits;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    {** The signature kept for AHash; false when it is not known yet. }
    function Find(const AHash: string; out ASignature: TGittanSignature): boolean;
    procedure Put(const AHash: string; const ASignature: TGittanSignature);
    procedure PutAll(const ACommits: TGittanSignedCommits; ACount: integer = -1);
    {** Those of AHashes not known yet, in their order. }
    function Unknown(const AHashes: TStringArray): TStringArray;
    function Count: integer;
  end;

  {** Reads the signatures of AHashes in the repository at ARoot on a
    thread, SignChunk at a time, and tells the main thread after each
    chunk (OnProgress) and at the end (OnDone). Results holds them in
    the order of AHashes, the first Finished of them done; what is read
    beyond Finished is not set yet. Stop ends the job between chunks. }
  TGittanSignJob = class(TGittanJob)
  private
    FRoot: string;
    FHashes: TStringArray;
    FResults: TGittanSignedCommits;
    FFinished: integer;
    FError: string;
    FOnProgress: TNotifyEvent;
    procedure NotifyProgress;
    function Cancelled: boolean;
  protected
    procedure Execute; override;
    procedure Detach; override;
  public
    constructor Create(const ARoot: string; const AHashes: TStringArray);
    function Finished: integer;
    property Results: TGittanSignedCommits read FResults;
    {** git's reason when a chunk could not be read; those commits are
      kept as unsigned. }
    property Error: string read FError;
    property OnProgress: TNotifyEvent read FOnProgress write FOnProgress;
  end;

  {** How commits are signed, as git's config has it: whether at all
    (commit.gpgsign), with what (gpg.format: ssh, x509, else OpenPGP,
    git's default), the key (user.signingkey: a gpg key id, the path of
    an SSH public key file, or the key itself), the allowed signers
    file SSH signatures are checked against (gpg.ssh.allowedSignersFile)
    and gpg.program, each as set, '' when it is not. }
  TGittanSigningSetup = record
    Sign: boolean;
    Format: TGittanSignFormat;
    Key, AllowedSigners, GpgProgram: string;
  end;

const
  SignChunk = 100;

{** The setup git would commit with in the repository at ARoot, every
  scope read. }
function ReadSigningSetup(const ARoot: string): TGittanSigningSetup;

{** Saves ASetup in the repository's own config (ALocal) or the global
  one, as SetIdentity does with the identity: commit.gpgsign and
  tag.gpgSign on with gpg.format and user.signingkey, or both unset at
  that scope when Sign is off, and with the global one the repository's
  own values are unset first, since they would go before it. For an
  SSH key the allowed signers file is seen to as well, so Gittan can
  show one's own commits as verified: the one set anywhere, else
  DefaultAllowedSignersFile set globally, gets a line with AEmail and
  the key unless it has one (AddAllowedSigner). False with git's
  reason in AError. }
function WriteSigningSetup(const ARoot: string; const ASetup: TGittanSigningSetup;
  const AEmail: string; ALocal: boolean; out AError: string): boolean;

{** git's name of AFormat for gpg.format: ssh, openpgp or x509. }
function SignFormatName(AFormat: TGittanSignFormat): string;
{** The format gpg.format's AValue names; OpenPGP for an empty one. }
function SignFormatOf(const AValue: string): TGittanSignFormat;

{** The public key files of ADir (*.pub), full paths sorted by name;
  SshPublicKeys those of ~/.ssh. }
function SshPublicKeysIn(const ADir: string): TStringArray;
function SshPublicKeys: TStringArray;

{** The keys the ssh agent holds (ssh-add -L), each a line "type key
  comment"; none when the agent cannot be asked. }
function SshAgentKeys: TStringArray;

{** The gpg to run in the repository at ARoot: gpg.program as set, else
  gpg on PATH when it runs, else (on Windows) the one Git for Windows
  brings beside git; '' when none is found. }
function GpgProgramFor(const ARoot: string): string;

{** The secret keys AProgram lists (--list-secret-keys --with-colons),
  each "key id"#31"user id", the revoked and expired ones left out;
  false with gpg's reason when it could not be run. }
function GpgSecretKeys(const AProgram: string; out AKeys: TStringArray;
  out AError: string): boolean;
{** Reads the keys from gpg's colon-separated AOutput (see GpgSecretKeys). }
function ParseGpgSecretKeys(const AOutput: string): TStringArray;

{** Signs a commit of the empty tree in the repository at ARoot with
  ASetup, through git commit-tree -S, which exercises the whole chain
  (the program, the key, the agent or pinentry) without touching a
  branch; the commit is reachable from nothing and git gc prunes it.
  AId is its id; false with git's reason in AError (gpg failed to sign
  the data, Couldn't load public key, ...). }
function TestSigning(const ARoot: string; const ASetup: TGittanSigningSetup;
  out AId, AError: string): boolean;

{** ~/.ssh/allowed_signers, the file Gittan sets up when none is. }
function DefaultAllowedSignersFile: string;

{** Puts "AEmail <key>" into AFile (made, with its folder, when it does
  not exist) unless the file has the key already. AKey is a .pub file's
  path, whose first line is taken, or the key itself ("key::" before
  it dropped); its comment is left out. False with the reason. }
function AddAllowedSigner(const AFile, AEmail, AKey: string; out AError: string): boolean;

{** The key AKey stands for, as AddAllowedSigner puts it in the file:
  "type base64", read from the file when AKey names one. '' when it
  cannot be read. }
function PublicKeyOf(const AKey: string): string;

{** The format a signature's first line names: "-----BEGIN SSH
  SIGNATURE-----", "-----BEGIN PGP SIGNATURE-----" (or PGP MESSAGE),
  "-----BEGIN SIGNED MESSAGE-----" (X.509 through gpgsm). }
function SignatureFormat(const ALine: string): TGittanSignFormat;

{** The commits in AOutput, git rev-list --header's output (a record
  per commit, NUL-terminated: the hash on its first line, then the
  header lines, a blank line and the message), each with its format
  from the gpgsig header (gpgsig-sha256 too), or sfNone with State
  ssNone without one; a signed one starts as ssUnchecked. }
function ParseSignatureHeaders(const AOutput: string): TGittanSignedCommits;

{** Reads git's verdicts from AOutput, a log in VerifyFormat (-z, a
  record per commit: hash, %G?, %GS, %GK, %GT at unit separators), into
  the commits of ACommits by hash. A verdict of N for a signed commit
  leaves it unchecked, since git says N when the verifier could not
  run; any other letter sets the state (see TGittanSignState). }
procedure ApplyVerdicts(const AOutput: string; var ACommits: TGittanSignedCommits);

{** The state git's letter means for a commit that has a signature. }
function SignStateOf(ACode: char): TGittanSignState;

{** The signatures of AHashes in the repository at ARoot: the headers
  first, then git's verdict on the signed ones alone, so an unsigned
  commit costs no gpg; ACommits comes in AHashes' order. ACancel, when
  given, is asked as git runs. False when git failed, with its reason in
  AError. For threads too. }
function CommitSignatures(const ARoot: string; const AHashes: array of string;
  ACancel: TGittanCancelEvent; out ACommits: TGittanSignedCommits;
  out AError: string): boolean;

const
  VerifyFormat = '--format=%H%x1f%G?%x1f%GS%x1f%GK%x1f%GT';

implementation

function SignatureFormat(const ALine: string): TGittanSignFormat;
var
  S: string;
begin
  S := Trim(ALine);
  if Pos('SSH SIGNATURE', S) > 0 then
    Result := sfSsh
  else if Pos('PGP ', S) > 0 then
    Result := sfOpenPgp
  else if Pos('SIGNED MESSAGE', S) > 0 then
    Result := sfX509
  else
    Result := sfNone;
end;

function ParseSignatureHeaders(const AOutput: string): TGittanSignedCommits;
var
  Records, Lines: TStringArray;
  i, k: integer;
  Line: string;
begin
  Result := nil;
  Records := AOutput.Split([#0]);
  for i := 0 to High(Records) do
  begin
    Lines := AdjustLineBreaks(Records[i], tlbsLF).Split([#10]);
    if (Length(Lines) = 0) or (Trim(Lines[0]) = '') then
      Continue;
    SetLength(Result, Length(Result) + 1);
    with Result[High(Result)] do
    begin
      Hash := Trim(Lines[0]);
      Signature := Default(TGittanSignature);
      Signature.Code := ' ';
      for k := 1 to High(Lines) do
      begin
        Line := Lines[k];
        if Line = '' then
          Break;
        if Line.StartsWith('gpgsig ') or Line.StartsWith('gpgsig-sha256 ') then
        begin
          Signature.Format := SignatureFormat(Copy(Line, Pos(' ', Line) + 1, MaxInt));
          Signature.State := ssUnchecked;
          Break;
        end;
      end;
    end;
  end;
end;

function SignStateOf(ACode: char): TGittanSignState;
begin
  case ACode of
    'G': Result := ssGood;
    'U', 'E': Result := ssUnknownKey;
    'B', 'X', 'Y', 'R': Result := ssBad;
  else
    Result := ssUnchecked;
  end;
end;

procedure ApplyVerdicts(const AOutput: string; var ACommits: TGittanSignedCommits);
var
  Records, Fields: TStringArray;
  i, k: integer;
begin
  Records := AOutput.Split([#0]);
  for i := 0 to High(Records) do
  begin
    Fields := Records[i].Split([#31]);
    if Length(Fields) < 5 then
      Continue;
    Fields[0] := Trim(Fields[0]);
    for k := 0 to High(ACommits) do
      if (ACommits[k].Hash = Fields[0]) and (ACommits[k].Signature.State <> ssNone) then
        with ACommits[k].Signature do
        begin
          if Fields[1] <> '' then
            Code := Fields[1][1];
          State := SignStateOf(Code);
          Signer := Trim(Fields[2]);
          Key := Trim(Fields[3]);
          Trust := Trim(Fields[4]);
          if Trust = 'undefined' then
            Trust := '';
        end;
  end;
end;

{ The hashes go on stdin, so a chunk is not bound by the command line.
  --no-walk=unsorted keeps their order. }
function CommitSignatures(const ARoot: string; const AHashes: array of string;
  ACancel: TGittanCancelEvent; out ACommits: TGittanSignedCommits;
  out AError: string): boolean;
var
  Input, Output: string;
  i, n: integer;
  Found: TGittanSignedCommits;
begin
  ACommits := nil;
  AError := '';
  if Length(AHashes) = 0 then
    Exit(True);
  Input := '';
  for i := 0 to High(AHashes) do
    Input := Input + AHashes[i] + #10;
  Result := RunGitEnv(ARoot, ['rev-list', '--header', '--no-walk=unsorted', '--stdin'], [],
    Output, AError, '', nil, ACancel, Input);
  if not Result then
    Exit;
  Found := ParseSignatureHeaders(Output);
  Input := '';
  n := 0;
  for i := 0 to High(Found) do
    if Found[i].Signature.State <> ssNone then
    begin
      Input := Input + Found[i].Hash + #10;
      Inc(n);
    end;
  if n > 0 then
  begin
    Result := RunGitEnv(ARoot, ['log', '--no-walk=unsorted', '--stdin', '-z', VerifyFormat], [],
      Output, AError, '', nil, ACancel, Input);
    if not Result then
      Exit;
    ApplyVerdicts(Output, Found);
  end;
  { In the order asked for; a hash git did not list is unsigned. }
  SetLength(ACommits, Length(AHashes));
  for i := 0 to High(AHashes) do
  begin
    ACommits[i].Hash := AHashes[i];
    ACommits[i].Signature := Default(TGittanSignature);
    ACommits[i].Signature.Code := ' ';
    for n := 0 to High(Found) do
      if Found[n].Hash = AHashes[i] then
      begin
        ACommits[i].Signature := Found[n].Signature;
        Break;
      end;
  end;
end;

{ ---------------------------------------------------------------------------
  The setup
  --------------------------------------------------------------------------- }

function SignFormatName(AFormat: TGittanSignFormat): string;
begin
  case AFormat of
    sfSsh: Result := 'ssh';
    sfX509: Result := 'x509';
  else
    Result := 'openpgp';
  end;
end;

function SignFormatOf(const AValue: string): TGittanSignFormat;
begin
  case LowerCase(Trim(AValue)) of
    'ssh': Result := sfSsh;
    'x509': Result := sfX509;
  else
    Result := sfOpenPgp;
  end;
end;

{ git config exits with 1 for a key that is not set. }
function ConfigValue(const ARoot: string; const AArgs: array of string): string;
var
  Error: string;
begin
  if not RunGitIn(ARoot, AArgs, Result, Error) then
    Result := '';
  Result := Trim(Result);
end;

function ReadSigningSetup(const ARoot: string): TGittanSigningSetup;
begin
  Result := Default(TGittanSigningSetup);
  Result.Sign := ConfigValue(ARoot, ['config', '--type=bool', '--get', 'commit.gpgsign']) = 'true';
  Result.Format := SignFormatOf(ConfigValue(ARoot, ['config', '--get', 'gpg.format']));
  Result.Key := ConfigValue(ARoot, ['config', '--get', 'user.signingkey']);
  Result.AllowedSigners := ConfigValue(ARoot, ['config', '--get', 'gpg.ssh.allowedSignersFile']);
  Result.GpgProgram := ConfigValue(ARoot, ['config', '--get', 'gpg.program']);
end;

function WriteSigningSetup(const ARoot: string; const ASetup: TGittanSigningSetup;
  const AEmail: string; ALocal: boolean; out AError: string): boolean;
var
  Scope, Output, Allowed, Key: string;
begin
  AError := '';
  if ALocal then
    Scope := '--local'
  else
    Scope := '--global';
  if not ALocal then
    for Key in ['commit.gpgsign', 'tag.gpgSign', 'gpg.format', 'user.signingkey'] do
      RunGitIn(ARoot, ['config', '--local', '--unset-all', Key], Output, AError);
  if ASetup.Sign then
  begin
    Result := RunGitIn(ARoot, ['config', Scope, '--replace-all', 'commit.gpgsign', 'true'],
      Output, AError) and
      RunGitIn(ARoot, ['config', Scope, '--replace-all', 'tag.gpgSign', 'true'], Output, AError) and
      RunGitIn(ARoot, ['config', Scope, '--replace-all', 'gpg.format',
        SignFormatName(ASetup.Format)], Output, AError) and
      RunGitIn(ARoot, ['config', Scope, '--replace-all', 'user.signingkey', ASetup.Key],
        Output, AError);
    if not Result then
      Exit;
    if ASetup.Format = sfSsh then
    begin
      Allowed := ConfigValue(ARoot, ['config', '--get', 'gpg.ssh.allowedSignersFile']);
      if Allowed = '' then
      begin
        Allowed := DefaultAllowedSignersFile;
        if not RunGitIn(ARoot, ['config', '--global', '--replace-all',
          'gpg.ssh.allowedSignersFile', Allowed], Output, AError) then
          Exit(False);
      end
      else if Pos('~/', Allowed) = 1 then
        Allowed := IncludeTrailingPathDelimiter(GetUserDir) + Copy(Allowed, 3, MaxInt);
      Result := AddAllowedSigner(Allowed, AEmail, ASetup.Key, AError);
    end;
  end
  else
  begin
    { git exits with 5 when there is nothing to unset. }
    RunGitIn(ARoot, ['config', Scope, '--unset-all', 'commit.gpgsign'], Output, AError);
    RunGitIn(ARoot, ['config', Scope, '--unset-all', 'tag.gpgSign'], Output, AError);
    AError := '';
    Result := True;
  end;
end;

function SshPublicKeysIn(const ADir: string): TStringArray;
var
  Info: TSearchRec;
  Names: TStringList;
  i: integer;
begin
  Result := nil;
  Names := TStringList.Create;
  try
    if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*.pub', faAnyFile, Info) = 0 then
    begin
      repeat
        if (Info.Attr and faDirectory) = 0 then
          Names.Add(IncludeTrailingPathDelimiter(ADir) + Info.Name);
      until FindNext(Info) <> 0;
      FindClose(Info);
    end;
    Names.Sort;
    SetLength(Result, Names.Count);
    for i := 0 to Names.Count - 1 do
      Result[i] := Names[i];
  finally
    Names.Free;
  end;
end;

function SshPublicKeys: TStringArray;
begin
  Result := SshPublicKeysIn(IncludeTrailingPathDelimiter(GetUserDir) + '.ssh');
end;

function SshAgentKeys: TStringArray;
var
  Output, Error, Line: string;
  Status: integer;
begin
  Result := nil;
  if not RunTool('ssh-add', '', ['-L'], [], [], Output, Error, Status, nil) or (Status <> 0) then
    Exit;
  for Line in Output.Split([#10, #13]) do
    if Pos(' ', Trim(Line)) > 0 then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Trim(Line);
    end;
end;

function GpgRuns(const AProgram: string): boolean;
var
  Output, Error: string;
  Status: integer;
begin
  Result := (AProgram <> '') and RunTool(AProgram, '', ['--version'], [], [], Output, Error,
    Status, nil) and (Status = 0);
end;

function GpgProgramFor(const ARoot: string): string;
{$IFDEF WINDOWS}
var
  Dir, Guess: string;
{$ENDIF}
begin
  Result := ConfigValue(ARoot, ['config', '--get', 'gpg.program']);
  if Result <> '' then
    Exit;
  if GpgRuns('gpg') then
    Exit('gpg');
  {$IFDEF WINDOWS}
  { Git for Windows: cmd\git.exe or mingw64\bin\git.exe, usr\bin\gpg.exe. }
  Dir := ExtractFileDir(ExpandFileName(GitExe));
  for Guess in [Dir + '\..\usr\bin\gpg.exe', Dir + '\..\..\usr\bin\gpg.exe'] do
    if FileExists(Guess) and GpgRuns(Guess) then
      Exit(ExpandFileName(Guess));
  {$ENDIF}
  Result := '';
end;

function ParseGpgSecretKeys(const AOutput: string): TStringArray;
var
  Line, KeyId: string;
  Fields: TStringArray;
begin
  Result := nil;
  KeyId := '';
  for Line in AOutput.Split([#10, #13]) do
  begin
    Fields := Line.Split([':']);
    if Length(Fields) < 10 then
      Continue;
    if Fields[0] = 'sec' then
    begin
      { Validity r (revoked) or e (expired) cannot sign. }
      if (Fields[1] = 'r') or (Fields[1] = 'e') then
        KeyId := ''
      else
        KeyId := Fields[4];
    end
    else if (Fields[0] = 'uid') and (KeyId <> '') then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := KeyId + #31 + Fields[9];
      KeyId := '';
    end;
  end;
end;

function GpgSecretKeys(const AProgram: string; out AKeys: TStringArray;
  out AError: string): boolean;
var
  Output: string;
  Status: integer;
begin
  AKeys := nil;
  Result := (AProgram <> '') and RunTool(AProgram, '', ['--list-secret-keys', '--with-colons',
    '--keyid-format=long'], [], [], Output, AError, Status, nil);
  if Result and (Status <> 0) then
  begin
    Result := False;
    if Trim(AError) = '' then
      AError := Trim(Output);
  end;
  if Result then
    AKeys := ParseGpgSecretKeys(Output);
end;

{ mktree with nothing on its input gives the empty tree. commit-tree
  signs only with -S, and the identity is Gittan's own so it runs
  where none is set. }
function TestSigning(const ARoot: string; const ASetup: TGittanSigningSetup;
  out AId, AError: string): boolean;
var
  Tree: string;
begin
  AId := '';
  Result := RunGitEnv(ARoot, ['mktree'], [], Tree, AError);
  if not Result then
    Exit;
  Result := RunGitIn(ARoot, ['-c', 'user.name=Gittan', '-c', 'user.email=gittan@localhost',
    '-c', 'gpg.format=' + SignFormatName(ASetup.Format), '-c', 'user.signingkey=' + ASetup.Key,
    'commit-tree', '-S', Trim(Tree), '-m', 'Gittan signing test'], AId, AError);
  AId := Trim(AId);
end;

function DefaultAllowedSignersFile: string;
begin
  Result := IncludeTrailingPathDelimiter(GetUserDir) + '.ssh' + PathDelim + 'allowed_signers';
end;

function PublicKeyOf(const AKey: string): string;
var
  Lines: TStringList;
  Parts: TStringArray;
begin
  Result := Trim(AKey);
  if Pos('key::', Result) = 1 then
    Delete(Result, 1, 5)
  else if FileExists(Result) then
  begin
    Lines := TStringList.Create;
    try
      try
        Lines.LoadFromFile(Result);
        if Lines.Count > 0 then
          Result := Trim(Lines[0])
        else
          Result := '';
      except
        Result := '';
      end;
    finally
      Lines.Free;
    end;
  end;
  { The type and the key, without the comment. }
  Parts := Result.Split([' '], TStringSplitOptions.ExcludeEmpty);
  if Length(Parts) < 2 then
    Exit('');
  Result := Parts[0] + ' ' + Parts[1];
end;

function AddAllowedSigner(const AFile, AEmail, AKey: string; out AError: string): boolean;
var
  Lines: TStringList;
  Key: string;
  i: integer;
begin
  AError := '';
  Key := PublicKeyOf(AKey);
  if Key = '' then
  begin
    AError := 'The public key could not be read: ' + AKey;
    Exit(False);
  end;
  Lines := TStringList.Create;
  try
    try
      if FileExists(AFile) then
        Lines.LoadFromFile(AFile);
      for i := 0 to Lines.Count - 1 do
        if Pos(Key, Lines[i]) > 0 then
          Exit(True);
      Lines.Add(AEmail + ' ' + Key);
      ForceDirectories(ExtractFileDir(AFile));
      Lines.SaveToFile(AFile);
      Result := True;
    except
      on E: Exception do
      begin
        AError := E.Message;
        Result := False;
      end;
    end;
  finally
    Lines.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  TGittanSignatureCache
  --------------------------------------------------------------------------- }

constructor TGittanSignatureCache.Create;
begin
  inherited Create;
  FHashes := TStringList.Create;
  FHashes.Sorted := True;
  FHashes.CaseSensitive := True;
  FHashes.Duplicates := dupIgnore;
end;

destructor TGittanSignatureCache.Destroy;
begin
  FHashes.Free;
  inherited Destroy;
end;

procedure TGittanSignatureCache.Clear;
begin
  FHashes.Clear;
  FSignatures := nil;
end;

function TGittanSignatureCache.Find(const AHash: string; out ASignature: TGittanSignature): boolean;
var
  i: integer;
begin
  Result := FHashes.Find(AHash, i);
  if Result then
    ASignature := FSignatures[PtrInt(FHashes.Objects[i])].Signature
  else
    ASignature := Default(TGittanSignature);
end;

procedure TGittanSignatureCache.Put(const AHash: string; const ASignature: TGittanSignature);
var
  i: integer;
begin
  if AHash = '' then
    Exit;
  if FHashes.Find(AHash, i) then
  begin
    FSignatures[PtrInt(FHashes.Objects[i])].Signature := ASignature;
    Exit;
  end;
  SetLength(FSignatures, Length(FSignatures) + 1);
  FSignatures[High(FSignatures)].Hash := AHash;
  FSignatures[High(FSignatures)].Signature := ASignature;
  FHashes.AddObject(AHash, TObject(PtrInt(High(FSignatures))));
end;

procedure TGittanSignatureCache.PutAll(const ACommits: TGittanSignedCommits; ACount: integer);
var
  i: integer;
begin
  if (ACount < 0) or (ACount > Length(ACommits)) then
    ACount := Length(ACommits);
  for i := 0 to ACount - 1 do
    Put(ACommits[i].Hash, ACommits[i].Signature);
end;

function TGittanSignatureCache.Unknown(const AHashes: TStringArray): TStringArray;
var
  i, k: integer;
begin
  Result := nil;
  for i := 0 to High(AHashes) do
    if (AHashes[i] <> '') and not FHashes.Find(AHashes[i], k) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := AHashes[i];
    end;
end;

function TGittanSignatureCache.Count: integer;
begin
  Result := FHashes.Count;
end;

{ ---------------------------------------------------------------------------
  TGittanSignJob
  ---------------------------------------------------------------------------
  The results are written in the hashes' order and the count says how
  many may be read, with a barrier between, as the batch jobs do. }

constructor TGittanSignJob.Create(const ARoot: string; const AHashes: TStringArray);
begin
  inherited Create(True);
  FRoot := ARoot;
  FHashes := Copy(AHashes, 0, Length(AHashes));
  SetLength(FResults, Length(FHashes));
end;

function TGittanSignJob.Cancelled: boolean;
begin
  Result := Terminated;
end;

procedure TGittanSignJob.NotifyProgress;
begin
  if Assigned(FOnProgress) and not Terminated then
    FOnProgress(Self);
end;

procedure TGittanSignJob.Detach;
begin
  FOnProgress := nil;
  inherited Detach;
end;

function TGittanSignJob.Finished: integer;
begin
  Result := FFinished;
  ReadBarrier;
end;

procedure TGittanSignJob.Execute;
var
  At, i, n: integer;
  Chunk: array of string;
  Found: TGittanSignedCommits;
  Reason: string;
begin
  At := 0;
  while (At < Length(FHashes)) and not Terminated do
  begin
    n := Length(FHashes) - At;
    if n > SignChunk then
      n := SignChunk;
    Chunk := Copy(FHashes, At, n);
    if CommitSignatures(FRoot, Chunk, @Cancelled, Found, Reason) then
      for i := 0 to n - 1 do
        FResults[At + i] := Found[i]
    else
    begin
      if Reason <> '' then
        FError := Reason;
      for i := 0 to n - 1 do
      begin
        FResults[At + i].Hash := FHashes[At + i];
        FResults[At + i].Signature := Default(TGittanSignature);
        FResults[At + i].Signature.Code := ' ';
      end;
    end;
    Inc(At, n);
    WriteBarrier;
    InterLockedExchange(FFinished, At);
    if not Terminated then
      Queue(@NotifyProgress);
  end;
  Done;
end;

end.
