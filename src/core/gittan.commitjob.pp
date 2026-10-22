unit gittan.commitjob;

{** The commit run in a thread: the repository's hooks can take their
  time (a linter, the tests), and the window must not hang meanwhile. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.git;

type
  {** Commits APaths of the repository at ARoot with AMessage, amending
    HEAD with AAmend, through TGittanRepo.Commit on a repository of its
    own, AParts with the text they give. OnDone is called in the main
    thread when it is done, unless the job has been stopped. A commit is
    never broken off: Stop only drops the handler, and the commit goes on
    to its end. The thread is not terminated for it, since a thread
    terminated before it starts never runs Execute at all. }
  TGittanCommitJob = class(TThread)
  private
    FRoot, FMessage: string;
    FPaths: TStringList;
    FAmend: boolean;
    FParts: TGittanCommitParts;
    FOk: boolean;
    FId, FError: string;
    FOnDone: TNotifyEvent;
    procedure Notify;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot, AMessage: string; APaths: TStrings;
      AAmend: boolean; const AParts: TGittanCommitParts = nil);
    destructor Destroy; override;
    {** Drops the handler, and waits for the commit to end when AWait is
      set, as on quitting, so git is not left halfway. }
    procedure Stop(AWait: boolean);
    property Root: string read FRoot;
    property Paths: TStringList read FPaths;
    property Amend: boolean read FAmend;
    property Message: string read FMessage;
    {** Whether the commit was made. }
    property Ok: boolean read FOk;
    {** The new commit, when Ok. }
    property Id: string read FId;
    {** Why nothing was committed (a hook's output, say), when not Ok. }
    property Error: string read FError;
    property OnDone: TNotifyEvent read FOnDone write FOnDone;
  end;

implementation

constructor TGittanCommitJob.Create(const ARoot, AMessage: string;
  APaths: TStrings; AAmend: boolean; const AParts: TGittanCommitParts);
begin
  inherited Create(True);
  FRoot := ARoot;
  FMessage := AMessage;
  FPaths := TStringList.Create;
  FPaths.AddStrings(APaths);
  FAmend := AAmend;
  FParts := Copy(AParts);
end;

destructor TGittanCommitJob.Destroy;
begin
  FPaths.Free;
  inherited Destroy;
end;

procedure TGittanCommitJob.Execute;
var
  Repo: TGittanRepo;
begin
  Repo := TGittanRepo.Create;
  try
    if Repo.Open(FRoot) then
      FOk := Repo.Commit(FMessage, FPaths, FAmend, FId, FParts);
    if not FOk then
      FError := Repo.Error;
  finally
    Repo.Free;
  end;
  Queue(@Notify);
end;

{ In the main thread, as Stop is, so the handler cannot go between the
  test and the call. }
procedure TGittanCommitJob.Notify;
begin
  if Assigned(FOnDone) then
    FOnDone(Self);
end;

procedure TGittanCommitJob.Stop(AWait: boolean);
begin
  FOnDone := nil;
  if AWait then
    WaitFor;
end;

end.
