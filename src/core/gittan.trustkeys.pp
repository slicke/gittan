unit gittan.trustkeys;

{** Taking a forge's word for whose keys are whose: for a commit signed
  with a key not known here, the forge is asked who made it (GitHub's
  commit API names the author's and the committer's logins; a merge
  made on the web is the committer web-flow, GitHub's own key) and
  those users' signing keys are fetched, public endpoints that need no
  login. The GPG keys go into the gpg git uses, and their fingerprints
  into the trusted keys (TGittanSettings.TrustedKeys), which ApplyTrust
  of gittan.signing shows as verified; the SSH keys go into the
  allowed signers file under their owner's e-mails (those GitHub lists
  for the user, and the commit's where GitHub names the user as its
  author or committer), which makes git itself say good. All of it in
  a TGittanTrustJob, since it goes to the network. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.git, gittan.job, gittan.signing;

type
  {** A forge user's signing keys: GPG keys ASCII armored, SSH keys as
    "type base64 [comment]", and the e-mails the forge lists for them. }
  TGittanForgeKeys = record
    Login: string;
    GpgKeys, SshKeys, Emails: TStringArray;
  end;

  {** Does the whole thing for one commit on a thread: who made it,
    their keys, the import and the allowed signers, and tells what
    came of it. Trusted holds the entries for the settings (TrustEntry:
    fingerprint, host, login), SshAdded how many SSH keys were put in
    the allowed signers file, Users the logins asked about, and Error
    why nothing or only part of it could be done. }
  TGittanTrustJob = class(TGittanJob)
  private
    FRoot, FHost, FOwner, FRepo, FHash, FGpgProgram, FAllowedFile: string;
    FTrusted, FUsers: TStringArray;
    FSshAdded: integer;
    FError: string;
    function Cancelled: boolean;
  protected
    procedure Execute; override;
  public
    {** AGpgProgram is the gpg git uses ('' when none, then GPG keys
      are left out), AAllowedFile the allowed signers file as it is or
      is to be made. }
    constructor Create(const ARoot, AHost, AOwner, ARepo, AHash, AGpgProgram,
      AAllowedFile: string);
    property Hash: string read FHash;
    property Host: string read FHost;
    property Trusted: TStringArray read FTrusted;
    property Users: TStringArray read FUsers;
    property SshAdded: integer read FSshAdded;
    property Error: string read FError;
  end;

{** The base of the REST API of the GitHub at AHost: api.github.com
  for github.com, https://host/api/v3 for an Enterprise host. }
function GitHubApiBase(const AHost: string): string;

{** The logins of the author and the committer of the commit AHash in
  AOwner/ARepo, each once, in that order; a commit whose e-mail GitHub
  knows no user for gives none for that one. GitHubCommitPeople gives
  the two apart, '' for one GitHub knows no user for. }
function GitHubCommitLogins(const ABase, AOwner, ARepo, AHash: string;
  out ALogins: TStringArray; out AError: string): boolean;
function GitHubCommitPeople(const ABase, AOwner, ARepo, AHash: string;
  out AAuthor, ACommitter, AError: string): boolean;
function ParseGitHubCommitLogins(const AJson: string): TStringArray;
procedure ParseGitHubCommitPeople(const AJson: string; out AAuthor, ACommitter: string);

{** The signing keys of the GitHub user ALogin (GET /users/{login}/gpg_keys
  and /ssh_signing_keys). }
function GitHubUserKeys(const ABase, ALogin: string; out AKeys: TGittanForgeKeys;
  out AError: string): boolean;
procedure ParseGitHubGpgKeys(const AJson: string; var AKeys: TGittanForgeKeys);
procedure ParseGitHubSshKeys(const AJson: string; var AKeys: TGittanForgeKeys);

{** The e-mails a commit was made under: the author's and the
  committer's, each once; CommitPeople gives the two apart. }
function CommitEmails(const ARoot, AHash: string): TStringArray;
function CommitPeople(const ARoot, AHash: string; out AAuthorEmail, ACommitterEmail: string): boolean;

implementation

uses
  fpjson, jsonparser, gittan.http;

const
  GitHubAccept = 'Accept: application/vnd.github+json';
  FetchSeconds = 20;

function GitHubApiBase(const AHost: string): string;
begin
  if (AHost = 'github.com') or (AHost = 'www.github.com') or (AHost = 'ssh.github.com') or
    (AHost = '') then
    Result := 'https://api.github.com'
  else
    Result := 'https://' + AHost + '/api/v3';
end;

procedure AddOnce(var AList: TStringArray; const AValue: string);
var
  i: integer;
begin
  if Trim(AValue) = '' then
    Exit;
  for i := 0 to High(AList) do
    if AList[i] = Trim(AValue) then
      Exit;
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := Trim(AValue);
end;

function Fetch(const AUrl: string; out ABody, AError: string): boolean;
var
  Response: TGittanHttpResponse;
begin
  Response := HttpGet(AUrl, [GitHubAccept], FetchSeconds);
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
    if Response.Status = 404 then
      AError := 'not found: ' + AUrl;
  end;
end;

function SafeJson(const AJson: string): TJSONData;
begin
  try
    Result := GetJSON(AJson);
  except
    Result := nil;
  end;
end;

function LoginOf(AData: TJSONData; const AName: string): string;
var
  O: TJSONData;
begin
  Result := '';
  if not (AData is TJSONObject) then
    Exit;
  O := TJSONObject(AData).Find(AName);
  if (O is TJSONObject) then
  begin
    O := TJSONObject(O).Find('login');
    if (O <> nil) and not O.IsNull then
      Result := O.AsString;
  end;
end;

procedure ParseGitHubCommitPeople(const AJson: string; out AAuthor, ACommitter: string);
var
  Data: TJSONData;
begin
  AAuthor := '';
  ACommitter := '';
  Data := SafeJson(AJson);
  if Data = nil then
    Exit;
  try
    AAuthor := Trim(LoginOf(Data, 'author'));
    ACommitter := Trim(LoginOf(Data, 'committer'));
  finally
    Data.Free;
  end;
end;

function ParseGitHubCommitLogins(const AJson: string): TStringArray;
var
  Author, Committer: string;
begin
  Result := nil;
  ParseGitHubCommitPeople(AJson, Author, Committer);
  AddOnce(Result, Author);
  AddOnce(Result, Committer);
end;

function GitHubCommitPeople(const ABase, AOwner, ARepo, AHash: string;
  out AAuthor, ACommitter, AError: string): boolean;
var
  Body: string;
begin
  AAuthor := '';
  ACommitter := '';
  Result := Fetch(ABase + '/repos/' + AOwner + '/' + ARepo + '/commits/' + AHash, Body, AError);
  if Result then
    ParseGitHubCommitPeople(Body, AAuthor, ACommitter);
end;

function GitHubCommitLogins(const ABase, AOwner, ARepo, AHash: string;
  out ALogins: TStringArray; out AError: string): boolean;
var
  Author, Committer: string;
begin
  ALogins := nil;
  Result := GitHubCommitPeople(ABase, AOwner, ARepo, AHash, Author, Committer, AError);
  if Result then
  begin
    AddOnce(ALogins, Author);
    AddOnce(ALogins, Committer);
  end;
end;

procedure ParseGitHubGpgKeys(const AJson: string; var AKeys: TGittanForgeKeys);
var
  Data, Item, Raw, Emails, E: TJSONData;
  i, k: integer;
begin
  Data := SafeJson(AJson);
  if not (Data is TJSONArray) then
  begin
    Data.Free;
    Exit;
  end;
  try
    for i := 0 to Data.Count - 1 do
    begin
      Item := Data.Items[i];
      if not (Item is TJSONObject) then
        Continue;
      Raw := TJSONObject(Item).Find('raw_key');
      if (Raw <> nil) and not Raw.IsNull and (Trim(Raw.AsString) <> '') then
        AddOnce(AKeys.GpgKeys, Raw.AsString);
      Emails := TJSONObject(Item).Find('emails');
      if Emails is TJSONArray then
        for k := 0 to Emails.Count - 1 do
          if Emails.Items[k] is TJSONObject then
          begin
            E := TJSONObject(Emails.Items[k]).Find('email');
            if (E <> nil) and not E.IsNull then
              AddOnce(AKeys.Emails, E.AsString);
          end;
    end;
  finally
    Data.Free;
  end;
end;

procedure ParseGitHubSshKeys(const AJson: string; var AKeys: TGittanForgeKeys);
var
  Data, Item, Key: TJSONData;
  i: integer;
begin
  Data := SafeJson(AJson);
  if not (Data is TJSONArray) then
  begin
    Data.Free;
    Exit;
  end;
  try
    for i := 0 to Data.Count - 1 do
    begin
      Item := Data.Items[i];
      if not (Item is TJSONObject) then
        Continue;
      Key := TJSONObject(Item).Find('key');
      if (Key <> nil) and not Key.IsNull then
        AddOnce(AKeys.SshKeys, Key.AsString);
    end;
  finally
    Data.Free;
  end;
end;

function GitHubUserKeys(const ABase, ALogin: string; out AKeys: TGittanForgeKeys;
  out AError: string): boolean;
var
  Body, Err2: string;
  Ok1, Ok2: boolean;
begin
  AKeys := Default(TGittanForgeKeys);
  AKeys.Login := ALogin;
  Ok1 := Fetch(ABase + '/users/' + ALogin + '/gpg_keys', Body, AError);
  if Ok1 then
    ParseGitHubGpgKeys(Body, AKeys);
  Ok2 := Fetch(ABase + '/users/' + ALogin + '/ssh_signing_keys', Body, Err2);
  if Ok2 then
    ParseGitHubSshKeys(Body, AKeys);
  Result := Ok1 or Ok2;
  if Result then
    AError := ''
  else if AError = '' then
    AError := Err2;
end;

function CommitPeople(const ARoot, AHash: string; out AAuthorEmail, ACommitterEmail: string): boolean;
var
  Output, Error: string;
  Parts: TStringArray;
begin
  AAuthorEmail := '';
  ACommitterEmail := '';
  Result := RunGitIn(ARoot, ['log', '-1', '--format=%ae%x1f%ce', AHash], Output, Error);
  if not Result then
    Exit;
  Parts := Trim(Output).Split([#31]);
  if Length(Parts) > 0 then
    AAuthorEmail := Trim(Parts[0]);
  if Length(Parts) > 1 then
    ACommitterEmail := Trim(Parts[1]);
end;

function CommitEmails(const ARoot, AHash: string): TStringArray;
var
  Author, Committer: string;
begin
  Result := nil;
  if CommitPeople(ARoot, AHash, Author, Committer) then
  begin
    AddOnce(Result, Author);
    AddOnce(Result, Committer);
  end;
end;

{ ---------------------------------------------------------------------------
  TGittanTrustJob
  --------------------------------------------------------------------------- }

constructor TGittanTrustJob.Create(const ARoot, AHost, AOwner, ARepo, AHash, AGpgProgram,
  AAllowedFile: string);
begin
  inherited Create(True);
  FRoot := ARoot;
  FHost := AHost;
  FOwner := AOwner;
  FRepo := ARepo;
  FHash := AHash;
  FGpgProgram := AGpgProgram;
  FAllowedFile := AAllowedFile;
end;

function TGittanTrustJob.Cancelled: boolean;
begin
  Result := Terminated;
end;

{ Every key of every user is taken, so the commits of the same people
  elsewhere in the history verify too. An SSH key goes in under the
  e-mails of its owner alone, since git matches the committer's e-mail
  against the principal: the e-mails GitHub lists for the user's GPG
  keys, and the commit's author or committer e-mail where GitHub names
  the user as that one (its word that the e-mail is theirs). Another
  user's e-mail under the key would make a commit forged under that
  e-mail verify as theirs. }
procedure TGittanTrustJob.Execute;
var
  Base, Reason, Login, Armored, Key, Email, Author, Committer, AuthorEmail,
  CommitterEmail: string;
  KeyOk: boolean;
  Logins, Fingerprints, Emails: TStringArray;
  Keys: TGittanForgeKeys;
  i: integer;
begin
  Base := GitHubApiBase(FHost);
  if not GitHubCommitPeople(Base, FOwner, FRepo, FHash, Author, Committer, FError) then
  begin
    { 404 or 422: GitHub has no such commit, as before a push. }
    if (Pos('not found', FError) > 0) or (Pos('422', FError) > 0) then
      FError := FHost + ' has no commit ' + Copy(FHash, 1, 7) + ' in ' + FOwner + '/' + FRepo +
        '. Is it pushed?';
    Done;
    Exit;
  end;
  Logins := nil;
  AddOnce(Logins, Author);
  AddOnce(Logins, Committer);
  if Length(Logins) = 0 then
    FError := 'GitHub knows no user for this commit''s author or committer.';
  CommitPeople(FRoot, FHash, AuthorEmail, CommitterEmail);
  for Login in Logins do
  begin
    if Terminated then
      Break;
    Emails := nil;
    if Login = Author then
      AddOnce(Emails, AuthorEmail);
    if Login = Committer then
      AddOnce(Emails, CommitterEmail);
    if not GitHubUserKeys(Base, Login, Keys, Reason) then
    begin
      FError := Reason;
      Continue;
    end;
    SetLength(FUsers, Length(FUsers) + 1);
    FUsers[High(FUsers)] := Login;
    if (FGpgProgram <> '') and (Length(Keys.GpgKeys) > 0) then
    begin
      Armored := '';
      for Key in Keys.GpgKeys do
        Armored := Armored + Key + #10;
      if ImportGpgKeys(FGpgProgram, Armored, Fingerprints, Reason) then
        for i := 0 to High(Fingerprints) do
        begin
          SetLength(FTrusted, Length(FTrusted) + 1);
          FTrusted[High(FTrusted)] := TrustEntry(Fingerprints[i], FHost, Login);
        end
      else
        FError := Reason;
    end
    else if (FGpgProgram = '') and (Length(Keys.GpgKeys) > 0) then
      FError := 'gpg was not found, so ' + Login + '''s GPG keys could not be taken in.';
    if (FAllowedFile <> '') and (Length(Keys.SshKeys) > 0) then
    begin
      for Email in Keys.Emails do
        AddOnce(Emails, Email);
      for Key in Keys.SshKeys do
      begin
        { With no e-mail to bind it to, the key is not added. }
        KeyOk := Length(Emails) > 0;
        for Email in Emails do
          if not AddAllowedSigner(FAllowedFile, Email, Key, Reason) then
          begin
            FError := Reason;
            KeyOk := False;
          end;
        if KeyOk then
          Inc(FSshAdded);
      end;
    end;
  end;
  Done;
end;

end.
