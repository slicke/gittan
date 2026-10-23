unit gittan.repofiles;

{** The repository's own files: the ones at the root that tell git and
  GitHub how to treat it (.gitignore and its kin) and everything under
  .github. The Config section under the tree lists them whether or
  not they changed, and the "Add to .gitignore" command writes to one
  of them. Nothing here runs git, so the unit has no LCL dependency and
  is tested in tests/testrepofiles.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  {** The files of the work tree root the section lists, in this order,
    each when it exists. }
  RepoRootFiles: array[0..4] of string = ('.gitignore', '.gitattributes',
    '.gitmodules', '.mailmap', '.editorconfig');
  {** The folder of the work tree root whose files the section lists,
    all of them, after the root files. }
  RepoFolder = '.github';
  {** The ignore file inside the git directory that is not committed. }
  ExcludeFile = 'info/exclude';
  {** What the exclude file is called where it is shown. }
  ExcludeShown = '.git/' + ExcludeFile;

{** Lists the repository's own files under ARoot as paths relative to it
  with "/" separators: the RepoRootFiles that exist, in that order, then
  every file under RepoFolder, folders walked, sorted by path. }
procedure ListRepoFiles(const ARoot: string; AList: TStrings);

{** Whether ARelPath, relative to the root with "/" separators, is one
  of the repository's own files: a RepoRootFiles name or a file under
  RepoFolder. These are the files the editor lets the user change. }
function IsRepoFile(const ARelPath: string): boolean;

{** The gitignore patterns that would hide APath, a path relative to the
  root with "/" separators: the file itself anchored at the root
  ("/dir/name.ext"), every file with its extension ("*.ext", when it has
  one), and its folder ("/dir/", when it is in one). }
function IgnorePatterns(const APath: string): TStringArray;

{** Appends APattern as a line to the ignore file AFileName (a .gitignore
  or the exclude file), making the file and its folder when there is
  none, after a newline when the file lacks one at its end. A file that
  already has the line is left as it is. False when the file could not
  be written. }
function AddIgnorePattern(const AFileName, APattern: string): boolean;

implementation

uses
  gittan.textfile;

{ Adds every file under ADir (a full path) to AList as ARel + its name,
  walking into the folders. }
procedure AddFolder(const ADir, ARel: string; AList: TStrings);
var
  Info: TSearchRec;
begin
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, Info) <> 0 then
    Exit;
  try
    repeat
      if (Info.Name = '.') or (Info.Name = '..') then
        Continue;
      if Info.Attr and faDirectory <> 0 then
        AddFolder(IncludeTrailingPathDelimiter(ADir) + Info.Name,
          ARel + Info.Name + '/', AList)
      else
        AList.Add(ARel + Info.Name);
    until FindNext(Info) <> 0;
  finally
    FindClose(Info);
  end;
end;

procedure ListRepoFiles(const ARoot: string; AList: TStrings);
var
  Root, Name: string;
  Folder: TStringList;
begin
  AList.Clear;
  if ARoot = '' then
    Exit;
  Root := IncludeTrailingPathDelimiter(ARoot);
  for Name in RepoRootFiles do
    if FileExists(Root + Name) then
      AList.Add(Name);
  if not DirectoryExists(Root + RepoFolder) then
    Exit;
  Folder := TStringList.Create;
  try
    AddFolder(Root + RepoFolder, RepoFolder + '/', Folder);
    Folder.CaseSensitive := False;
    Folder.Sort;
    AList.AddStrings(Folder);
  finally
    Folder.Free;
  end;
end;

function IsRepoFile(const ARelPath: string): boolean;
var
  Name: string;
begin
  for Name in RepoRootFiles do
    if ARelPath = Name then
      Exit(True);
  Result := Copy(ARelPath, 1, Length(RepoFolder) + 1) = RepoFolder + '/';
end;

function IgnorePatterns(const APath: string): TStringArray;
var
  Ext, Dir: string;
begin
  Result := nil;
  if APath = '' then
    Exit;
  SetLength(Result, 1);
  Result[0] := '/' + APath;
  Ext := ExtractFileExt(APath);
  { A dotfile's "extension" is its whole name. }
  if (Ext <> '') and (Ext <> ExtractFileName(APath)) then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := '*' + Ext;
  end;
  Dir := ExtractFilePath(APath);
  if Dir <> '' then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := '/' + Dir;
  end;
end;

function AddIgnorePattern(const AFileName, APattern: string): boolean;
var
  Lines: TStringList;
  Text: string;
  F: TFileStream;
begin
  Result := False;
  try
    Text := '';
    if FileExists(AFileName) then
    begin
      Text := ReadFileBytes(AFileName);
      Lines := TStringList.Create;
      try
        { git matches the patterns case-sensitively (core.ignoreCase
          aside), so *.O is another line than *.o. }
        Lines.CaseSensitive := True;
        Lines.Text := Text;
        if Lines.IndexOf(APattern) >= 0 then
          Exit(True);
      finally
        Lines.Free;
      end;
      if (Text <> '') and (Text[Length(Text)] <> #10) then
        Text := Text + LineEnding;
    end
    else
      ForceDirectories(ExtractFileDir(AFileName));
    Text := Text + APattern + LineEnding;
    F := TFileStream.Create(AFileName, fmCreate);
    try
      F.WriteBuffer(Text[1], Length(Text));
    finally
      F.Free;
    end;
    Result := True;
  except
    Result := False;
  end;
end;

end.
