unit gittan.git;

{** Git access for Gittan.

  Runs the git command line tool against a repository and returns its output.
  Nothing is parsed here beyond trimming; the caller decides how to show it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  {** One opened repository. Open finds the work tree root for a folder, and
    the other calls run inside that root. }
  TGittanRepo = class
  private
    FRoot: string;
    FError: string;
    function RunGit(const ADir: string; const AArgs: array of string;
      out AOutput: string): boolean;
  public
    {** Opens the repository that contains ADir. Returns false, with the git
      message in Error, when ADir is not inside a work tree. }
    function Open(const ADir: string): boolean;
    {** Forgets the repository. }
    procedure Close;
    {** Unified diff of the work tree against HEAD, or against the index in
      a repository without commits. Empty when there are no changes. }
    function Diff: string;
    {** Changed files as "XY path" lines from `git status --porcelain`,
      untracked files included. Returns false when git failed. }
    function ChangedFiles(AList: TStrings): boolean;
    {** Paths of tracked and untracked files, relative to Root with "/"
      separators; ignored files are left out. Returns false when git
      failed. }
    function ListFiles(AList: TStrings): boolean;
    {** Work tree root, empty when nothing is open. }
    property Root: string read FRoot;
    {** Message from the last git call that failed. }
    property Error: string read FError;
  end;

implementation

uses
  Process;

{ ---------------------------------------------------------------------------
  Running git
  ---------------------------------------------------------------------------
  git is found on PATH. stderr goes into the same string as stdout, so on
  failure the output is the error message and is kept in FError. Path names
  come back as plain UTF-8 instead of octal escapes. }
function TGittanRepo.RunGit(const ADir: string; const AArgs: array of string;
  out AOutput: string): boolean;
var
  Args: array of string;
  Status, i: integer;
begin
  AOutput := '';
  SetLength(Args, Length(AArgs) + 2);
  Args[0] := '-c';
  Args[1] := 'core.quotepath=false';
  for i := 0 to High(AArgs) do
    Args[i + 2] := AArgs[i];
  if RunCommandIndir(ADir, 'git', Args, AOutput, Status, [poStderrToOutPut]) <> 0 then
  begin
    FError := 'Could not run git. Is it installed?';
    Exit(False);
  end;
  Result := Status = 0;
  if not Result then
  begin
    FError := Trim(AOutput);
    AOutput := '';
  end;
end;

{ TGittanRepo }

function TGittanRepo.Open(const ADir: string): boolean;
var
  Top: string;
begin
  Close;
  if not DirectoryExists(ADir) then
  begin
    FError := Format('Folder not found: %s', [ADir]);
    Exit(False);
  end;
  Result := RunGit(ADir, ['rev-parse', '--show-toplevel'], Top);
  if Result then
    FRoot := Trim(Top);
end;

procedure TGittanRepo.Close;
begin
  FRoot := '';
  FError := '';
end;

function TGittanRepo.Diff: string;
begin
  Result := '';
  if FRoot = '' then
    Exit;
  { HEAD does not exist before the first commit; the index is the best
    base then. }
  if not RunGit(FRoot, ['diff', '--no-color', '--no-ext-diff', 'HEAD'], Result) then
    RunGit(FRoot, ['diff', '--no-color', '--no-ext-diff'], Result);
end;

function TGittanRepo.ChangedFiles(AList: TStrings): boolean;
var
  Output: string;
begin
  AList.Clear;
  if FRoot = '' then
    Exit(False);
  Result := RunGit(FRoot, ['status', '--porcelain'], Output);
  if Result then
    AList.Text := Output;
end;

function TGittanRepo.ListFiles(AList: TStrings): boolean;
var
  Output: string;
begin
  AList.Clear;
  if FRoot = '' then
    Exit(False);
  Result := RunGit(FRoot, ['ls-files', '--cached', '--others', '--exclude-standard'],
    Output);
  if Result then
    AList.Text := Output;
end;

end.
