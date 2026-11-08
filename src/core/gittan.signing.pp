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

const
  SignChunk = 100;

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
