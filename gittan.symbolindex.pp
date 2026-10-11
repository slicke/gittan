unit gittan.symbolindex;

{** The symbol index of a repository: the code tree of every file with a
  lexer, by path, with the file's size and time so a stale entry is
  told from a current one. The index is kept on disk between runs as a
  text file, one line per file ("F", path, size, time) followed by one
  line per symbol ("S", row, column, depth, name, line), tab separated
  with tabs and backslashes in the texts escaped. Who parses the files
  is the caller's business; the index only holds the results. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.symbols;

type
  {** One file of the index: its stamp (size and time, see FileStamp)
    and its symbols. Indexed is false for a file that is only queued. }
  TGittanIndexEntry = class
  public
    Path: string;
    Size, Time: int64;
    Indexed: boolean;
    Items: TGittanSymbols;
  end;

  { TGittanSymbolIndex }

  TGittanSymbolIndex = class
  private
    FList: TStringList;
    function GetCount: integer;
    function GetEntry(AIndex: integer): TGittanIndexEntry;
  public
    constructor Create;
    destructor Destroy; override;
    {** The entry of APath, or nil. }
    function Find(const APath: string): TGittanIndexEntry;
    {** The entry of APath, made when there is none. }
    function Add(const APath: string): TGittanIndexEntry;
    {** Drops the entry of APath, if any. }
    procedure Remove(const APath: string);
    {** Drops every entry whose path is not in AKeep. }
    procedure KeepOnly(AKeep: TStrings);
    {** Whether APath has an indexed entry with the stamp ASize, ATime. }
    function IsCurrent(const APath: string; ASize, ATime: int64): boolean;
    procedure Clear;
    {** Reads the index from AFileName; a missing or damaged file gives
      an empty index. }
    procedure Load(const AFileName: string);
    {** Writes the indexed entries to AFileName, making its folder. }
    procedure Save(const AFileName: string);
    property Count: integer read GetCount;
    property Entries[AIndex: integer]: TGittanIndexEntry read GetEntry; default;
  end;

{** The size and modification time of the file at AFileName, false when
  it does not exist. }
function FileStamp(const AFileName: string; out ASize, ATime: int64): boolean;

implementation

const
  IndexHeader = 'gittan-index 1';

function Escape(const S: string): string;
begin
  Result := StringReplace(S, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, #9, '\t', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\r', [rfReplaceAll]);
end;

function Unescape(const S: string): string;
var
  i: integer;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if (S[i] = '\') and (i < Length(S)) then
    begin
      Inc(i);
      case S[i] of
        't': Result += #9;
        'n': Result += #10;
        'r': Result += #13;
        else
          Result += S[i];
      end;
    end
    else
      Result += S[i];
    Inc(i);
  end;
end;

function FileStamp(const AFileName: string; out ASize, ATime: int64): boolean;
var
  Info: TSearchRec;
begin
  ASize := 0;
  ATime := 0;
  Result := FindFirst(AFileName, faAnyFile, Info) = 0;
  if Result then
  begin
    ASize := Info.Size;
    ATime := Info.Time;
    FindClose(Info);
  end;
end;

{ TGittanSymbolIndex }

constructor TGittanSymbolIndex.Create;
begin
  inherited Create;
  FList := TStringList.Create;
  FList.CaseSensitive := True;
  FList.Sorted := True;
  FList.Duplicates := dupIgnore;
  FList.OwnsObjects := True;
end;

destructor TGittanSymbolIndex.Destroy;
begin
  FList.Free;
  inherited Destroy;
end;

function TGittanSymbolIndex.GetCount: integer;
begin
  Result := FList.Count;
end;

function TGittanSymbolIndex.GetEntry(AIndex: integer): TGittanIndexEntry;
begin
  Result := TGittanIndexEntry(FList.Objects[AIndex]);
end;

function TGittanSymbolIndex.Find(const APath: string): TGittanIndexEntry;
var
  i: integer;
begin
  if FList.Find(APath, i) then
    Result := TGittanIndexEntry(FList.Objects[i])
  else
    Result := nil;
end;

function TGittanSymbolIndex.Add(const APath: string): TGittanIndexEntry;
begin
  Result := Find(APath);
  if Result <> nil then
    Exit;
  Result := TGittanIndexEntry.Create;
  Result.Path := APath;
  FList.AddObject(APath, Result);
end;

procedure TGittanSymbolIndex.Remove(const APath: string);
var
  i: integer;
begin
  if FList.Find(APath, i) then
    FList.Delete(i);
end;

procedure TGittanSymbolIndex.KeepOnly(AKeep: TStrings);
var
  Keep: TStringList;
  i: integer;
begin
  Keep := TStringList.Create;
  try
    Keep.CaseSensitive := True;
    Keep.Sorted := True;
    Keep.Duplicates := dupIgnore;
    Keep.AddStrings(AKeep);
    for i := FList.Count - 1 downto 0 do
      if Keep.IndexOf(FList[i]) < 0 then
        FList.Delete(i);
  finally
    Keep.Free;
  end;
end;

function TGittanSymbolIndex.IsCurrent(const APath: string; ASize, ATime: int64): boolean;
var
  E: TGittanIndexEntry;
begin
  E := Find(APath);
  Result := (E <> nil) and E.Indexed and (E.Size = ASize) and (E.Time = ATime);
end;

procedure TGittanSymbolIndex.Clear;
begin
  FList.Clear;
end;

procedure TGittanSymbolIndex.Load(const AFileName: string);
var
  Lines, Fields: TStringList;
  E: TGittanIndexEntry;
  i, n: integer;
begin
  Clear;
  if not FileExists(AFileName) then
    Exit;
  Lines := TStringList.Create;
  Fields := TStringList.Create;
  try
    Fields.Delimiter := #9;
    Fields.StrictDelimiter := True;
    try
      Lines.LoadFromFile(AFileName);
    except
      Exit;
    end;
    if (Lines.Count = 0) or (Lines[0] <> IndexHeader) then
      Exit;
    E := nil;
    for i := 1 to Lines.Count - 1 do
    begin
      Fields.DelimitedText := Lines[i];
      if (Fields.Count = 4) and (Fields[0] = 'F') then
      begin
        E := Add(Unescape(Fields[1]));
        E.Size := StrToInt64Def(Fields[2], -1);
        E.Time := StrToInt64Def(Fields[3], -1);
        E.Indexed := True;
        E.Items := nil;
      end
      else if (Fields.Count = 6) and (Fields[0] = 'S') and (E <> nil) then
      begin
        n := Length(E.Items);
        SetLength(E.Items, n + 1);
        E.Items[n].Row := StrToIntDef(Fields[1], 0);
        E.Items[n].Col := StrToIntDef(Fields[2], 0);
        E.Items[n].Depth := StrToIntDef(Fields[3], 0);
        E.Items[n].Name := Unescape(Fields[4]);
        E.Items[n].Line := Unescape(Fields[5]);
      end
      else
      begin
        { A damaged file is not trusted at all. }
        Clear;
        Exit;
      end;
    end;
  finally
    Lines.Free;
    Fields.Free;
  end;
end;

procedure TGittanSymbolIndex.Save(const AFileName: string);
var
  Lines: TStringList;
  E: TGittanIndexEntry;
  i, j: integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Add(IndexHeader);
    for i := 0 to FList.Count - 1 do
    begin
      E := Entries[i];
      if not E.Indexed then
        Continue;
      Lines.Add(Format('F'#9'%s'#9'%d'#9'%d', [Escape(E.Path), E.Size, E.Time]));
      for j := 0 to High(E.Items) do
        Lines.Add(Format('S'#9'%d'#9'%d'#9'%d'#9'%s'#9'%s', [E.Items[j].Row,
          E.Items[j].Col, E.Items[j].Depth, Escape(E.Items[j].Name),
          Escape(E.Items[j].Line)]));
    end;
    ForceDirectories(ExtractFileDir(AFileName));
    Lines.SaveToFile(AFileName);
  finally
    Lines.Free;
  end;
end;

end.
