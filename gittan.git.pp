unit gittan.git;

{** Git access for Gittan.

  Runs the git command line tool against a repository and returns its output.
  Nothing is parsed here beyond trimming; the caller decides how to show it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  {** What happened to a changed file, condensed from the two status columns
    of `git status --porcelain`. }
  TGittanChangeKind = (ckModified, ckAdded, ckDeleted, ckRenamed, ckUntracked,
    ckConflict);

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
    {** Paths of the changed files from ChangedFiles, relative to Root with
      "/" separators; a rename gives its new path. Each Objects entry holds
      the file's TGittanChangeKind as TObject(PtrUInt(Ord(Kind))). Returns
      false when git failed. }
    function ChangedPaths(AList: TStrings): boolean;
    {** The change kind of a "XY" status from `git status --porcelain`. }
    class function ChangeKind(const AStatus: string): TGittanChangeKind;
    {** One changed file as the lines of a unified diff against HEAD with the
      whole file as context: every line starts with ' ', '+' or '-'. A file
      git does not know yet is returned as all added lines; a binary file
      gives no lines. Returns false when git failed. }
    function FileChanges(const APath: string; ALines: TStrings): boolean;
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

{ A porcelain line is "XY path", or "XY old -> new" for a rename or copy. }
function TGittanRepo.ChangedPaths(AList: TStrings): boolean;
var
  i, Arrow: integer;
  Path: string;
begin
  Result := ChangedFiles(AList);
  if not Result then
    Exit;
  for i := 0 to AList.Count - 1 do
  begin
    Path := Copy(AList[i], 4, MaxInt);
    Arrow := Pos(' -> ', Path);
    if Arrow > 0 then
      Delete(Path, 1, Arrow + 3);
    AList.Objects[i] := TObject(PtrUInt(Ord(ChangeKind(Copy(AList[i], 1, 2)))));
    AList[i] := Path;
  end;
end;

{ X is the index column, Y the work tree. A "U" in either (or both sides
  added or deleted) is an unmerged file; a deletion on either side wins over
  the rest since the file is gone; a rename or copy keeps its new path. "T"
  (type change) and anything unknown count as modified. }
class function TGittanRepo.ChangeKind(const AStatus: string): TGittanChangeKind;
var
  X, Y: char;
begin
  X := ' ';
  Y := ' ';
  if Length(AStatus) >= 1 then
    X := AStatus[1];
  if Length(AStatus) >= 2 then
    Y := AStatus[2];
  if (X = '?') or (Y = '?') then
    Result := ckUntracked
  else if (X = 'U') or (Y = 'U') or ((X = 'A') and (Y = 'A')) or
    ((X = 'D') and (Y = 'D')) then
    Result := ckConflict
  else if (X = 'D') or (Y = 'D') then
    Result := ckDeleted
  else if X in ['R', 'C'] then
    Result := ckRenamed
  else if X = 'A' then
    Result := ckAdded
  else
    Result := ckModified;
end;

{ The hunk header "@@" starts the lines; "\ No newline at end of file"
  notes are dropped. Renames are turned off so a renamed file is a plain new
  file under its new path, which is how the file tree lists it. }
function TGittanRepo.FileChanges(const APath: string; ALines: TStrings): boolean;
var
  Output, Line, FileName: string;
  Raw: TStringList;
  InHunk: boolean;
begin
  ALines.Clear;
  if FRoot = '' then
    Exit(False);
  Result := RunGit(FRoot, ['diff', '--no-color', '--no-ext-diff', '--no-renames',
    '-U99999999', 'HEAD', '--', APath], Output);
  if not Result then
    Result := RunGit(FRoot, ['diff', '--no-color', '--no-ext-diff', '--no-renames',
      '-U99999999', '--', APath], Output);
  if not Result then
    Exit;
  Raw := TStringList.Create;
  try
    if Output = '' then
    begin
      { Not in HEAD or the index: an untracked file, all of it new. }
      FileName := IncludeTrailingPathDelimiter(FRoot) + SetDirSeparators(APath);
      if FileExists(FileName) then
      begin
        Raw.LoadFromFile(FileName);
        for Line in Raw do
          ALines.Add('+' + Line);
      end;
      Exit;
    end;
    Raw.Text := Output;
    InHunk := False;
    for Line in Raw do
      if not InHunk then
        InHunk := Copy(Line, 1, 2) = '@@'
      else if (Line <> '') and (Line[1] in [' ', '+', '-']) then
        ALines.Add(Line);
  finally
    Raw.Free;
  end;
end;

end.
