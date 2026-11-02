unit gittan.repolist;

{** The repository list: the repositories the user keeps at hand, in
  folders of their own naming and in the order they put them, which the
  welcome view shows over the recent repositories. A folder can hold
  folders too, and keeps whether it is collapsed. Unlike the recent
  repositories nothing comes in by itself.

  The list lives in a file of its own beside gittan.ini
  (RepoListFileName), JSON, written whole after every change (through a
  temporary file renamed over it), so an arranged list does not depend on
  Gittan closing normally as the ini does. A file that cannot be read
  leaves the list empty and is not written over until the list changes.

  FindRepositories looks for the repositories in a folder, for Add
  Repositories in Folder. Nothing here needs the LCL; tested in
  tests/testrepolist.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs;

const
  {** The list's file, in ConfigDir. }
  RepoListFileName = 'repositories.json';
  {** How deep FindRepositories looks under the folder it is given. }
  FindDepth = 3;

type
  TGittanRepoEntry = class;
  TGittanRepoList = class;

  { TGittanRepoEntry }

  {** A folder of the list, or a repository in one. }
  TGittanRepoEntry = class
  private
    FIsFolder: boolean;
    FName, FPath: string;
    FCollapsed: boolean;
    FParent: TGittanRepoEntry;
    FItems: TFPObjectList;
    function GetCount: integer;
    function GetItem(AIndex: integer): TGittanRepoEntry;
  public
    constructor Create(AIsFolder: boolean);
    destructor Destroy; override;
    {** The name shown: a folder's name, a repository's own name when it
      has one, else the name of its folder. }
    function Caption: string;
    {** Whether AEntry is this entry or inside it. }
    function Contains(AEntry: TGittanRepoEntry): boolean;
    function IndexOf(AEntry: TGittanRepoEntry): integer;
    {** The repositories in this folder and in the folders inside it. }
    function RepoCount: integer;
    property IsFolder: boolean read FIsFolder;
    {** A folder's name; a repository's own name, '' for its folder's. }
    property Name: string read FName write FName;
    {** A repository's root, without a trailing delimiter; '' for a
      folder. }
    property Path: string read FPath;
    {** A folder whose contents are hidden. }
    property Collapsed: boolean read FCollapsed write FCollapsed;
    {** The folder it is in; the list's Root for the top, nil for Root. }
    property Parent: TGittanRepoEntry read FParent;
    {** A folder's entries, in order; none for a repository. }
    property Count: integer read GetCount;
    property Items[AIndex: integer]: TGittanRepoEntry read GetItem; default;
  end;

  {** A row the list shows: an entry and how deep it is, 0 at the top. }
  TGittanRepoRow = record
    Entry: TGittanRepoEntry;
    Depth: integer;
  end;
  TGittanRepoRows = array of TGittanRepoRow;

  { TGittanRepoList }

  TGittanRepoList = class
  private
    FRoot: TGittanRepoEntry;
    FFileName: string;
    function FindIn(AFolder: TGittanRepoEntry; const APath: string): TGittanRepoEntry;
    function FolderOf(AFolder: TGittanRepoEntry): TGittanRepoEntry;
    procedure Insert(AFolder, AEntry: TGittanRepoEntry; AIndex: integer);
  public
    {** A list kept in AFileName ('' for one kept nowhere, which Save
      does not write); empty until Load. }
    constructor Create(const AFileName: string);
    destructor Destroy; override;
    {** Reads the file; a missing or unreadable one leaves the list
      empty. }
    procedure Load;
    {** Writes the file; False when it could not be written. }
    function Save: boolean;
    {** The list as the file holds it, and back; FromJson leaves the
      list empty for text that is not a list. }
    function ToJson: string;
    procedure FromJson(const AText: string);
    procedure Clear;
    {** The repository at APath anywhere in the list, nil for none. }
    function Find(const APath: string): TGittanRepoEntry;
    {** Adds the repository at APath to AFolder (Root when nil) before
      its entry AIndex, at the end for -1; nil when the list has it
      already. }
    function AddRepo(AFolder: TGittanRepoEntry; const APath: string;
      AIndex: integer = -1): TGittanRepoEntry;
    {** Adds a folder named AName to AFolder (Root when nil) as AddRepo
      does. }
    function AddFolder(AFolder: TGittanRepoEntry; const AName: string;
      AIndex: integer = -1): TGittanRepoEntry;
    {** Moves AEntry to AFolder (Root when nil) before the entry that is
      AIndex there now, at the end for -1 or past the end; False for a
      folder put inside itself. }
    function Move(AEntry, AFolder: TGittanRepoEntry; AIndex: integer): boolean;
    {** Takes AEntry out of the list and frees it, a folder with what it
      holds. }
    procedure Remove(AEntry: TGittanRepoEntry);
    {** The rows shown, top to bottom: every entry but those inside a
      collapsed folder. }
    function Rows: TGittanRepoRows;
    {** The folder the top of the list is in; never shown. }
    property Root: TGittanRepoEntry read FRoot;
    property FileName: string read FFileName;
  end;

{** APath as the list keeps it: expanded, without a trailing
  delimiter. }
function RepoListPath(const APath: string): string;

{** The repositories in ADir and in the folders under it up to ADepth
  deep, sorted by path; ADir alone when it is one. A repository's own
  folders are not looked into, nor hidden folders and links. }
function FindRepositories(const ADir: string; ADepth: integer = FindDepth): TStringArray;

implementation

uses
  fpjson, jsonparser;

function RepoListPath(const APath: string): string;
begin
  Result := APath;
  if Result <> '' then
    Result := ExcludeTrailingPathDelimiter(ExpandFileName(Result));
end;

{ A folder with .git in it, a folder (a repository) or a file (a worktree,
  a submodule). }
function IsRepoFolder(const ADir: string): boolean;
var
  Git: string;
begin
  Git := IncludeTrailingPathDelimiter(ADir) + '.git';
  Result := DirectoryExists(Git) or FileExists(Git);
end;

procedure FindReposIn(const ADir: string; ADepth: integer; AFound: TStrings);
var
  Info: TSearchRec;
  Dir: string;
begin
  if ADepth <= 0 then
    Exit;
  Dir := IncludeTrailingPathDelimiter(ADir);
  if FindFirst(Dir + AllFilesMask, faDirectory or faSymLink, Info) <> 0 then
    Exit;
  try
    repeat
      if (Info.Attr and faDirectory = 0) or (Info.Attr and faSymLink <> 0) or
        (Info.Name = '') or (Info.Name[1] = '.') then
        Continue;
      if IsRepoFolder(Dir + Info.Name) then
        AFound.Add(Dir + Info.Name)
      else
        FindReposIn(Dir + Info.Name, ADepth - 1, AFound);
    until FindNext(Info) <> 0;
  finally
    FindClose(Info);
  end;
end;

function FindRepositories(const ADir: string; ADepth: integer): TStringArray;
var
  Found: TStringList;
  Dir: string;
  i: integer;
begin
  Result := nil;
  Dir := RepoListPath(ADir);
  if not DirectoryExists(Dir) then
    Exit;
  if IsRepoFolder(Dir) then
    Exit([Dir]);
  Found := TStringList.Create;
  try
    FindReposIn(Dir, ADepth, Found);
    Found.Sort;
    SetLength(Result, Found.Count);
    for i := 0 to Found.Count - 1 do
      Result[i] := Found[i];
  finally
    Found.Free;
  end;
end;

{ TGittanRepoEntry }

constructor TGittanRepoEntry.Create(AIsFolder: boolean);
begin
  inherited Create;
  FIsFolder := AIsFolder;
  if AIsFolder then
    FItems := TFPObjectList.Create(True);
end;

destructor TGittanRepoEntry.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TGittanRepoEntry.GetCount: integer;
begin
  if FItems = nil then
    Result := 0
  else
    Result := FItems.Count;
end;

function TGittanRepoEntry.GetItem(AIndex: integer): TGittanRepoEntry;
begin
  Result := TGittanRepoEntry(FItems[AIndex]);
end;

function TGittanRepoEntry.Caption: string;
begin
  Result := FName;
  if (Result = '') and not FIsFolder then
    Result := ExtractFileName(FPath);
end;

function TGittanRepoEntry.Contains(AEntry: TGittanRepoEntry): boolean;
begin
  while AEntry <> nil do
  begin
    if AEntry = Self then
      Exit(True);
    AEntry := AEntry.FParent;
  end;
  Result := False;
end;

function TGittanRepoEntry.IndexOf(AEntry: TGittanRepoEntry): integer;
begin
  if FItems = nil then
    Result := -1
  else
    Result := FItems.IndexOf(AEntry);
end;

function TGittanRepoEntry.RepoCount: integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to Count - 1 do
    if Items[i].IsFolder then
      Inc(Result, Items[i].RepoCount)
    else
      Inc(Result);
end;

{ TGittanRepoList }

constructor TGittanRepoList.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
  FRoot := TGittanRepoEntry.Create(True);
end;

destructor TGittanRepoList.Destroy;
begin
  FRoot.Free;
  inherited Destroy;
end;

procedure TGittanRepoList.Clear;
begin
  FRoot.FItems.Clear;
end;

function TGittanRepoList.FolderOf(AFolder: TGittanRepoEntry): TGittanRepoEntry;
begin
  if AFolder = nil then
    Result := FRoot
  else
    Result := AFolder;
end;

procedure TGittanRepoList.Insert(AFolder, AEntry: TGittanRepoEntry; AIndex: integer);
begin
  AEntry.FParent := AFolder;
  if (AIndex < 0) or (AIndex > AFolder.Count) then
    AFolder.FItems.Add(AEntry)
  else
    AFolder.FItems.Insert(AIndex, AEntry);
end;

function TGittanRepoList.FindIn(AFolder: TGittanRepoEntry;
  const APath: string): TGittanRepoEntry;
var
  i: integer;
begin
  for i := 0 to AFolder.Count - 1 do
  begin
    if AFolder[i].IsFolder then
      Result := FindIn(AFolder[i], APath)
    else if AFolder[i].Path = APath then
      Result := AFolder[i]
    else
      Result := nil;
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

function TGittanRepoList.Find(const APath: string): TGittanRepoEntry;
begin
  if APath = '' then
    Exit(nil);
  Result := FindIn(FRoot, RepoListPath(APath));
end;

function TGittanRepoList.AddRepo(AFolder: TGittanRepoEntry; const APath: string;
  AIndex: integer): TGittanRepoEntry;
begin
  if (APath = '') or (Find(APath) <> nil) then
    Exit(nil);
  Result := TGittanRepoEntry.Create(False);
  Result.FPath := RepoListPath(APath);
  Insert(FolderOf(AFolder), Result, AIndex);
end;

function TGittanRepoList.AddFolder(AFolder: TGittanRepoEntry; const AName: string;
  AIndex: integer): TGittanRepoEntry;
begin
  Result := TGittanRepoEntry.Create(True);
  Result.FName := AName;
  Insert(FolderOf(AFolder), Result, AIndex);
end;

function TGittanRepoList.Move(AEntry, AFolder: TGittanRepoEntry;
  AIndex: integer): boolean;
var
  Old: TGittanRepoEntry;
  At: integer;
begin
  AFolder := FolderOf(AFolder);
  if (AEntry = nil) or (AEntry = FRoot) or AEntry.Contains(AFolder) then
    Exit(False);
  Old := AEntry.FParent;
  At := Old.IndexOf(AEntry);
  { The index names the entry there before the move, which moves up one
    when AEntry comes out ahead of it in the same folder. }
  if (Old = AFolder) and (AIndex > At) then
    Dec(AIndex);
  Old.FItems.Extract(AEntry);
  Insert(AFolder, AEntry, AIndex);
  Result := True;
end;

procedure TGittanRepoList.Remove(AEntry: TGittanRepoEntry);
begin
  if (AEntry = nil) or (AEntry = FRoot) then
    Exit;
  AEntry.FParent.FItems.Remove(AEntry);
end;

function TGittanRepoList.Rows: TGittanRepoRows;
var
  N: integer;

  procedure AddFrom(AFolder: TGittanRepoEntry; ADepth: integer);
  var
    i: integer;
  begin
    for i := 0 to AFolder.Count - 1 do
    begin
      if N = Length(Result) then
        SetLength(Result, 2 * N + 8);
      Result[N].Entry := AFolder[i];
      Result[N].Depth := ADepth;
      Inc(N);
      if AFolder[i].IsFolder and not AFolder[i].Collapsed then
        AddFrom(AFolder[i], ADepth + 1);
    end;
  end;

begin
  Result := nil;
  N := 0;
  AddFrom(FRoot, 0);
  SetLength(Result, N);
end;

{ ---------------------------------------------------------------------------
  The file
  ---------------------------------------------------------------------------
  {"items": [{"folder": "Work", "collapsed": true, "items": [...]},
             {"path": "/Users/me/kod/gittan", "name": "Gittan"}]}
  A repository's name is left out when it has none, a folder's
  collapsed when it is not. }
function EntriesToJson(AFolder: TGittanRepoEntry): TJSONArray;
var
  i: integer;
  Item: TJSONObject;
  E: TGittanRepoEntry;
begin
  Result := TJSONArray.Create;
  for i := 0 to AFolder.Count - 1 do
  begin
    E := AFolder[i];
    Item := TJSONObject.Create;
    if E.IsFolder then
    begin
      Item.Add('folder', E.Name);
      if E.Collapsed then
        Item.Add('collapsed', True);
      Item.Add('items', EntriesToJson(E));
    end
    else
    begin
      Item.Add('path', E.Path);
      if E.Name <> '' then
        Item.Add('name', E.Name);
    end;
    Result.Add(Item);
  end;
end;

function TGittanRepoList.ToJson: string;
var
  Doc: TJSONObject;
begin
  Doc := TJSONObject.Create;
  try
    Doc.Add('items', EntriesToJson(FRoot));
    Result := Doc.FormatJSON;
  finally
    Doc.Free;
  end;
end;

procedure TGittanRepoList.FromJson(const AText: string);
var
  Data: TJSONData;

  procedure ReadInto(AFolder: TGittanRepoEntry; AItems: TJSONData);
  var
    i: integer;
    Item: TJSONObject;
    E: TGittanRepoEntry;
  begin
    if not (AItems is TJSONArray) then
      Exit;
    for i := 0 to TJSONArray(AItems).Count - 1 do
    begin
      if not (TJSONArray(AItems)[i] is TJSONObject) then
        Continue;
      Item := TJSONObject(TJSONArray(AItems)[i]);
      if Item.Find('folder') <> nil then
      begin
        E := AddFolder(AFolder, Item.Get('folder', ''));
        E.Collapsed := Item.Get('collapsed', False);
        ReadInto(E, Item.Find('items'));
      end
      else
      begin
        E := AddRepo(AFolder, Item.Get('path', ''));
        if E <> nil then
          E.Name := Item.Get('name', '');
      end;
    end;
  end;

begin
  Clear;
  try
    Data := GetJSON(AText);
  except
    Exit;
  end;
  try
    if Data is TJSONObject then
      ReadInto(FRoot, TJSONObject(Data).Find('items'));
  finally
    Data.Free;
  end;
end;

procedure TGittanRepoList.Load;
var
  Text: TStringList;
begin
  Clear;
  if (FFileName = '') or not FileExists(FFileName) then
    Exit;
  Text := TStringList.Create;
  try
    try
      Text.LoadFromFile(FFileName);
    except
      Exit;
    end;
    FromJson(Text.Text);
  finally
    Text.Free;
  end;
end;

{$IFDEF WINDOWS}
{ Declared here rather than taken from the Windows unit, whose DeleteFile
  would shadow that of SysUtils. }
function MoveFileExW(AFrom, ATo: PWideChar; AFlags: longword): LongBool; stdcall;
  external 'kernel32' name 'MoveFileExW';

const
  MOVEFILE_REPLACE_EXISTING = 1;
  MOVEFILE_WRITE_THROUGH = 8;
{$ENDIF}

function TGittanRepoList.Save: boolean;
var
  Temp: string;
  S: TFileStream;
  Json: string;
begin
  Result := False;
  if FFileName = '' then
    Exit;
  Temp := FFileName + '.tmp';
  Json := ToJson + LineEnding;
  try
    ForceDirectories(ExtractFileDir(FFileName));
    S := TFileStream.Create(Temp, fmCreate);
    try
      S.WriteBuffer(Json[1], Length(Json));
    finally
      S.Free;
    end;
  except
    DeleteFile(Temp);
    Exit;
  end;
  {$IFDEF WINDOWS}
  { RenameFile does not replace a file on Windows; MoveFileEx does, in
    one step, so the list on disk stays the old one when it fails. }
  Result := MoveFileExW(PWideChar(UTF8Decode(Temp)), PWideChar(UTF8Decode(FFileName)),
    MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH);
  {$ELSE}
  Result := RenameFile(Temp, FFileName);
  {$ENDIF}
  if not Result then
    DeleteFile(Temp);
end;

end.
