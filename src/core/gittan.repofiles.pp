unit gittan.repofiles;

{** The repository's own files: the ones at the root that tell git and
  GitHub how to treat it (.gitignore and its kin) and everything under
  .github. The Config section under the tree lists them whether or
  not they changed, and the "Add to .gitignore" and "Track with Git
  LFS" commands write to them. Nothing here runs git, so the unit has no LCL dependency and
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
  {** The folders of the work tree root whose files the section lists,
    all of them, after the root files, in this order: GitHub's and
    Gittan's own (see repo-commands.md). }
  RepoFolders: array[0..1] of string = ('.github', '.gittan');
  {** The ignore file inside the git directory that is not committed. }
  ExcludeFile = 'info/exclude';
  {** What the exclude file is called where it is shown. }
  ExcludeShown = '.git/' + ExcludeFile;

{** Lists the repository's own files under ARoot as paths relative to it
  with "/" separators: the RepoRootFiles that exist, in that order, then
  every file under each of RepoFolders, folders walked, sorted by path. }
procedure ListRepoFiles(const ARoot: string; AList: TStrings);

{** Whether ARelPath, relative to the root with "/" separators, is one
  of the repository's own files: a RepoRootFiles name or a file under
  one of RepoFolders. These are the files the editor lets the user
  change. }
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

const
  {** The attributes Git LFS gives a pattern it tracks, as `git lfs
    track` writes them. }
  LfsAttributes = 'filter=lfs diff=lfs merge=lfs -text';

{** The .gitattributes patterns that would put APath, relative to the
  root with "/" separators, in Git LFS: every file with its extension
  ("*.psd", when it has one) and the file itself anchored at the root
  ("/art/logo.psd"); a space is [[:space:]], as git lfs track writes
  it, since a pattern ends at whitespace. }
function LfsTrackPatterns(const APath: string): TStringArray;

{** The patterns of the .gitattributes text AText that have filter=lfs,
  in their order. }
function LfsTrackedPatterns(const AText: string): TStringArray;

{** Those of LfsTrackedPatterns(AText) that are among
  LfsTrackPatterns(APath), the file's also without its leading slash:
  what Stop Tracking offers for the file. }
function LfsPatternsOf(const AText, APath: string): TStringArray;

{** Appends APattern with LfsAttributes to the attributes file AFileName
  as AddIgnorePattern appends a pattern; a file that tracks the pattern
  in Git LFS already is left as it is. False when it could not be
  written. }
function AddLfsTrack(const AFileName, APattern: string): boolean;

{** Takes the lines that track APattern in Git LFS out of the attributes
  file AFileName, keeping the others and the file's line ends. False
  when it could not be read or written. }
function RemoveLfsTrack(const AFileName, APattern: string): boolean;

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
  for Name in RepoFolders do
  begin
    if not DirectoryExists(Root + Name) then
      Continue;
    Folder := TStringList.Create;
    try
      AddFolder(Root + Name, Name + '/', Folder);
      Folder.CaseSensitive := False;
      Folder.Sort;
      AList.AddStrings(Folder);
    finally
      Folder.Free;
    end;
  end;
end;

function IsRepoFile(const ARelPath: string): boolean;
var
  Name: string;
begin
  for Name in RepoRootFiles do
    if ARelPath = Name then
      Exit(True);
  for Name in RepoFolders do
    if Copy(ARelPath, 1, Length(Name) + 1) = Name + '/' then
      Exit(True);
  Result := False;
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

function LfsTrackPatterns(const APath: string): TStringArray;
var
  Ext: string;
begin
  Result := nil;
  if APath = '' then
    Exit;
  Ext := ExtractFileExt(APath);
  if (Ext <> '') and (Ext <> ExtractFileName(APath)) then
    Result := ['*' + StringReplace(Ext, ' ', '[[:space:]]', [rfReplaceAll])];
  Result := Concat(Result, ['/' + StringReplace(APath, ' ', '[[:space:]]', [rfReplaceAll])]);
end;

{ The pattern of a line of attributes and whether it has filter=lfs; a
  comment or a blank line has none. }
function LfsLine(const ALine: string; out APattern: string): boolean;
var
  Fields: TStringArray;
  Field: string;
begin
  APattern := '';
  Result := False;
  Fields := Trim(ALine).Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  if (Length(Fields) < 2) or (Fields[0][1] = '#') then
    Exit;
  APattern := Fields[0];
  for Field in Fields do
    if Field = 'filter=lfs' then
      Exit(True);
end;

function LfsTrackedPatterns(const AText: string): TStringArray;
var
  Lines: TStringList;
  Line, Pattern: string;
begin
  Result := nil;
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    for Line in Lines do
      if LfsLine(Line, Pattern) then
        Result := Concat(Result, [Pattern]);
  finally
    Lines.Free;
  end;
end;

function LfsPatternsOf(const AText, APath: string): TStringArray;
var
  Tracked, Wanted: TStringArray;
  Pattern, Want: string;
begin
  Result := nil;
  Tracked := LfsTrackedPatterns(AText);
  Wanted := LfsTrackPatterns(APath);
  if Wanted <> nil then
    Wanted := Concat(Wanted, [Copy(Wanted[High(Wanted)], 2, MaxInt)]);
  for Pattern in Tracked do
    for Want in Wanted do
      if Pattern = Want then
      begin
        Result := Concat(Result, [Pattern]);
        Break;
      end;
end;

function AddLfsTrack(const AFileName, APattern: string): boolean;
var
  Pattern: string;
begin
  try
    if FileExists(AFileName) then
      for Pattern in LfsTrackedPatterns(ReadFileBytes(AFileName)) do
        if Pattern = APattern then
          Exit(True);
  except
    Exit(False);
  end;
  Result := AddIgnorePattern(AFileName, APattern + ' ' + LfsAttributes);
end;

function RemoveLfsTrack(const AFileName, APattern: string): boolean;
var
  Text, Line, Pattern, Kept, Ending: string;
  Lines: TStringArray;
  i: integer;
  F: TFileStream;
begin
  Result := False;
  try
    Text := ReadFileBytes(AFileName);
    if Pos(#13#10, Text) > 0 then
      Ending := #13#10
    else
      Ending := #10;
    Lines := StringReplace(Text, #13#10, #10, [rfReplaceAll]).Split([#10]);
    Kept := '';
    for i := 0 to High(Lines) do
    begin
      Line := Lines[i];
      if LfsLine(Line, Pattern) and (Pattern = APattern) then
        Continue;
      { The last piece is what follows the last line end: nothing in a
        file that ends with one. }
      if i < High(Lines) then
        Kept := Kept + Line + Ending
      else
        Kept := Kept + Line;
    end;
    F := TFileStream.Create(AFileName, fmCreate);
    try
      if Kept <> '' then
        F.WriteBuffer(Kept[1], Length(Kept));
    finally
      F.Free;
    end;
    Result := True;
  except
    Result := False;
  end;
end;

end.
