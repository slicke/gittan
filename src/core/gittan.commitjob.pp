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
    own, AParts with the text they give and AOptions (sign-off, no
    hooks) as asked. OnDone is called in the main
    thread when it is done, unless the job has been stopped. A commit is
    never broken off: Stop only drops the handler, and the commit goes on
    to its end. The thread is not terminated for it, since a thread
    terminated before it starts never runs Execute at all. }
  TGittanCommitJob = class(TGittanJob)
  private
    FRoot, FMessage: string;
    FPaths: TStringList;
    FAmend: boolean;
    FParts: TGittanCommitParts;
    FOptions: TGittanCommitOptions;
    FOk: boolean;
    FId, FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot, AMessage: string; APaths: TStrings;
      AAmend: boolean; const AParts: TGittanCommitParts = nil;
      AOptions: TGittanCommitOptions = []);
    destructor Destroy; override;
    property Root: string read FRoot;
    property Paths: TStringList read FPaths;
    property Amend: boolean read FAmend;
    property Options: TGittanCommitOptions read FOptions;
    property Message: string read FMessage;
    {** Whether the commit was made. }
    property Ok: boolean read FOk;
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

procedure TGittanCommitJob.Execute;
var
  Repo: TGittanRepo;
begin
  Repo := TGittanRepo.Create;
  try
    if Repo.Open(FRoot) then
      FOk := Repo.Commit(FMessage, FPaths, FAmend, FId, FParts, FOptions);
    if not FOk then
      FError := Repo.Error;
  finally
    Repo.Free;
  end;
  Done;
end;

end.
