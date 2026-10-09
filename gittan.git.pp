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

  {** One changed file with its line counts. A binary file has no counts. }
  TGittanFileStat = record
    Path: string;
    Kind: TGittanChangeKind;
    Added, Deleted: integer;
    Binary: boolean;
  end;
  TGittanFileStats = array of TGittanFileStat;

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
    {** The changed files of ChangedPaths with their added and deleted line
      counts from `git diff --numstat`. A file git does not know yet has
      every line counted as added. Returns false when git failed. }
    function ChangeStats(out AStats: TGittanFileStats): boolean;
    {** The current branch, the short commit id when HEAD is detached, or
      empty when nothing is open. }
    function Branch: string;
    {** The change kind of a "XY" status from `git status --porcelain`. }
    class function ChangeKind(const AStatus: string): TGittanChangeKind;
    {** One changed file as the lines of a unified diff against HEAD with the
      whole file as context: every line starts with ' ', '+' or '-'. A file
      git does not know yet is returned as all added lines; a binary file
      gives no lines. Returns false when git failed. }
    function FileChanges(const APath: string; ALines: TStrings): boolean;
    {** A text that changes whenever the branch, the set of changed files
      or the content of a changed file changes: the branch, the status of
      every changed file, the diff against HEAD, and the size and
      modification time of every untracked file (the diff does not cover
      them). Empty when nothing is open or git failed. Meant for polling:
      two equal fingerprints mean there is nothing new to show. }
    function Fingerprint: string;
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

{ Git's own heuristic: a NUL byte in the first 8000 bytes makes a file
  binary. A text file has one line per line feed, plus an unterminated last
  line. }
procedure CountNewFile(const AFileName: string; var AStat: TGittanFileStat);
const
  Probe = 8000;
var
  Stream: TFileStream;
  Buffer: array[0..4095] of byte;
  Got, i, Seen: integer;
  LastByte: byte;
begin
  AStat.Added := 0;
  AStat.Deleted := 0;
  AStat.Binary := False;
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    Seen := 0;
    LastByte := 10;
    repeat
      Got := Stream.Read(Buffer, SizeOf(Buffer));
      for i := 0 to Got - 1 do
      begin
        if (Buffer[i] = 0) and (Seen + i < Probe) then
        begin
          AStat.Binary := True;
          AStat.Added := 0;
          Exit;
        end;
        if Buffer[i] = 10 then
          Inc(AStat.Added);
      end;
      if Got > 0 then
        LastByte := Buffer[Got - 1];
      Inc(Seen, Got);
    until Got = 0;
    if (Seen > 0) and (LastByte <> 10) then
      Inc(AStat.Added);
  finally
    Stream.Free;
  end;
end;

{ A numstat line is "added<tab>deleted<tab>path", with "-" for both counts
  of a binary file. Renames are turned off so the new path of a rename gets
  its counts; the old path is not in the list and is skipped. The counts
  are against HEAD, so staged and unstaged changes are both in. }
function TGittanRepo.ChangeStats(out AStats: TGittanFileStats): boolean;
var
  Paths, Num: TStringList;
  Output, Line, Path, Counts, FileName: string;
  i, Tab1, Tab2, Idx: integer;
begin
  AStats := nil;
  Paths := TStringList.Create;
  Num := TStringList.Create;
  try
    Paths.CaseSensitive := True;
    Result := ChangedPaths(Paths);
    if not Result then
      Exit;
    SetLength(AStats, Paths.Count);
    for i := 0 to Paths.Count - 1 do
    begin
      AStats[i] := Default(TGittanFileStat);
      AStats[i].Path := Paths[i];
      AStats[i].Kind := TGittanChangeKind(PtrUInt(Paths.Objects[i]));
    end;
    if not RunGit(FRoot, ['diff', '--numstat', '--no-renames', 'HEAD'], Output) then
      RunGit(FRoot, ['diff', '--numstat', '--no-renames'], Output);
    Num.Text := Output;
    for Line in Num do
    begin
      Tab1 := Pos(#9, Line);
      if Tab1 = 0 then
        Continue;
      Tab2 := Pos(#9, Line, Tab1 + 1);
      if Tab2 = 0 then
        Continue;
      Path := Copy(Line, Tab2 + 1, MaxInt);
      Idx := Paths.IndexOf(Path);
      if Idx < 0 then
        Continue;
      Counts := Copy(Line, 1, Tab1 - 1);
      if Counts = '-' then
        AStats[Idx].Binary := True
      else
      begin
        AStats[Idx].Added := StrToIntDef(Counts, 0);
        AStats[Idx].Deleted := StrToIntDef(Copy(Line, Tab1 + 1, Tab2 - Tab1 - 1), 0);
      end;
    end;
    for i := 0 to High(AStats) do
      if AStats[i].Kind = ckUntracked then
      begin
        FileName := IncludeTrailingPathDelimiter(FRoot) + SetDirSeparators(AStats[i].Path);
        if FileExists(FileName) and not DirectoryExists(FileName) then
          CountNewFile(FileName, AStats[i]);
      end;
  finally
    Num.Free;
    Paths.Free;
  end;
end;

{ symbolic-ref names the branch even before its first commit; it fails
  when HEAD is detached, and the commit id stands in then. }
function TGittanRepo.Branch: string;
begin
  Result := '';
  if FRoot = '' then
    Exit;
  if RunGit(FRoot, ['symbolic-ref', '--short', '-q', 'HEAD'], Result) then
    Result := Trim(Result)
  else if RunGit(FRoot, ['rev-parse', '--short', 'HEAD'], Result) then
    Result := Trim(Result)
  else
    Result := '';
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

{ The diff covers every tracked change in full, so an edit that keeps the
  line counts still shows. An untracked file is not in the diff and is not
  read (it may be large); its size and time stand in, from one stat. }
function TGittanRepo.Fingerprint: string;
var
  Paths: TStringList;
  Info: TSearchRec;
  FileName: string;
  i: integer;
begin
  Result := '';
  if FRoot = '' then
    Exit;
  Paths := TStringList.Create;
  try
    if not ChangedPaths(Paths) then
      Exit;
    Result := Branch + #10;
    for i := 0 to Paths.Count - 1 do
      Result := Result + IntToStr(PtrUInt(Paths.Objects[i])) + ' ' + Paths[i] + #10;
    Result := Result + Diff;
    for i := 0 to Paths.Count - 1 do
      if TGittanChangeKind(PtrUInt(Paths.Objects[i])) = ckUntracked then
      begin
        FileName := IncludeTrailingPathDelimiter(FRoot) + SetDirSeparators(Paths[i]);
        if FindFirst(FileName, faAnyFile, Info) = 0 then
        begin
          Result := Result + #10 + Paths[i] + #9 + IntToStr(Info.Time) + #9 +
            IntToStr(Info.Size);
          FindClose(Info);
        end;
      end;
  finally
    Paths.Free;
  end;
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
