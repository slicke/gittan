unit gittan.commitjob;

{** The commit run in a thread: the repository's hooks can take their
  time (a linter, the tests), and the window must not hang meanwhile. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.git, gittan.job;

type
  {** Commits APaths of the repository at ARoot with AMessage, amending
    HEAD with AAmend, through TGittanRepo.Commit on a repository of its
    own (or, after MoveTo, on a new branch through MoveToBranch), AParts with the text they give and AOptions (sign-off, no
    hooks) as asked. OnDone is called in the main
    thread when it is done, unless the job has been stopped. A commit is
    never broken off: Stop only drops the handler, and the commit goes on
    to its end. The thread is not terminated for it, since a thread
    terminated before it starts never runs Execute at all. }
  TGittanCommitJob = class(TGittanJob)
  private
    FRoot, FMessage, FDraft: string;
    FPaths: TStringList;
    FAmend: boolean;
    FParts: TGittanCommitParts;
    FOptions: TGittanCommitOptions;
    FBranch: string;
    FRest: TGittanCommitParts;
    FOk, FBack: boolean;
    FId, FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot, AMessage: string; APaths: TStrings;
      AAmend: boolean; const AParts: TGittanCommitParts = nil;
      AOptions: TGittanCommitOptions = []);
    destructor Destroy; override;
    {** Before Start: the commit is made on the new branch ABranch and
      HEAD goes back to where it was, through TGittanRepo.MoveToBranch
      with ARest. }
    procedure MoveTo(const ABranch: string; const ARest: TGittanCommitParts);
    property Root: string read FRoot;
    property Paths: TStringList read FPaths;
    property Amend: boolean read FAmend;
    property Options: TGittanCommitOptions read FOptions;
    property Message: string read FMessage;
    {** The text of the field the message came from, before what was
      added to it (co-authors); '' when it came from no field. }
    property Draft: string read FDraft write FDraft;
    {** The new branch the commit goes to (MoveTo), '' for a commit on
      the current one. }
    property Branch: string read FBranch;
    {** Whether the commit was made. }
    property Ok: boolean read FOk;
    {** After MoveTo, when Ok: whether HEAD is back where it was; Error
      says why when it is not. }
    property Back: boolean read FBack;
    {** The new commit, when Ok. }
    property Id: string read FId;
    {** Why nothing was committed (a hook's output, say), when not Ok. }
    property Error: string read FError;
  end;

implementation

constructor TGittanCommitJob.Create(const ARoot, AMessage: string;
  APaths: TStrings; AAmend: boolean; const AParts: TGittanCommitParts;
  AOptions: TGittanCommitOptions);
begin
  { Never broken off: Stop leaves its git running. }
  inherited Create(False);
  FRoot := ARoot;
  FMessage := AMessage;
  FPaths := TStringList.Create;
  FPaths.AddStrings(APaths);
  FAmend := AAmend;
  FParts := Copy(AParts);
  FOptions := AOptions;
end;

destructor TGittanCommitJob.Destroy;
begin
  inherited Destroy;
  FPaths.Free;
end;

procedure TGittanCommitJob.MoveTo(const ABranch: string; const ARest: TGittanCommitParts);
begin
  FBranch := ABranch;
  FRest := Copy(ARest);
end;

procedure TGittanCommitJob.Execute;
var
  Repo: TGittanRepo;
begin
  Repo := TGittanRepo.Create;
  try
    if not Repo.Open(FRoot) then
      FOk := False
    else if FBranch <> '' then
      FOk := Repo.MoveToBranch(FBranch, FMessage, FPaths, FId, FBack, FParts, FRest, FOptions)
    else
      FOk := Repo.Commit(FMessage, FPaths, FAmend, FId, FParts, FOptions);
    if not FOk or ((FBranch <> '') and not FBack) then
      FError := Repo.Error;
  finally
    Repo.Free;
  end;
  Done;
end;

end.
