unit gittan.snapshots;

{** The snapshots taken of a repository (TGittanRepo.TakeSnapshot): the
  commit id and the time of each, newest first, kept in a text file per
  repository in the cache folder, beside the symbol index. git prunes a
  snapshot commit two weeks or more after it was made, so the list is
  checked against the repository when it is loaded and never grows past
  MaxSnapshots. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  {** How many snapshots are kept per repository. }
  MaxSnapshots = 10;

type
  TGittanSnapshot = record
    Id: string;
    Time: TDateTime;
  end;

  { TGittanSnapshots }

  TGittanSnapshots = class
  private
    FItems: array of TGittanSnapshot;
    function GetCount: integer;
    function GetItem(AIndex: integer): TGittanSnapshot;
  public
    {** Puts a snapshot first, dropping the oldest beyond MaxSnapshots. }
    procedure Add(const AId: string; ATime: TDateTime);
    procedure Delete(AIndex: integer);
    procedure Clear;
    {** The index of the snapshot with id AId, or -1. }
    function IndexOf(const AId: string): integer;
    {** Reads the file; a missing or broken file leaves the list empty. }
    procedure Load(const AFileName: string);
    {** Writes the file, creating its folder; errors propagate. }
    procedure Save(const AFileName: string);
    {** How a snapshot is named in a menu: its time of day, with the day
      before it when it is not ANow's. }
    class function Caption(ATime, ANow: TDateTime): string;
    property Count: integer read GetCount;
    property Items[AIndex: integer]: TGittanSnapshot read GetItem; default;
  end;

implementation

const
  Header = 'gittan-snapshots 1';
  TimeFormat = 'yyyy-mm-dd hh:nn:ss';

{ TGittanSnapshots }

function TGittanSnapshots.GetCount: integer;
begin
  Result := Length(FItems);
end;

function TGittanSnapshots.GetItem(AIndex: integer): TGittanSnapshot;
begin
  Result := FItems[AIndex];
end;

procedure TGittanSnapshots.Add(const AId: string; ATime: TDateTime);
var
  i: integer;
begin
  i := IndexOf(AId);
  if i >= 0 then
    Delete(i);
  SetLength(FItems, Length(FItems) + 1);
  for i := High(FItems) downto 1 do
    FItems[i] := FItems[i - 1];
  FItems[0].Id := AId;
  FItems[0].Time := ATime;
  if Length(FItems) > MaxSnapshots then
    SetLength(FItems, MaxSnapshots);
end;

procedure TGittanSnapshots.Delete(AIndex: integer);
var
  i: integer;
begin
  for i := AIndex to High(FItems) - 1 do
    FItems[i] := FItems[i + 1];
  SetLength(FItems, Length(FItems) - 1);
end;

procedure TGittanSnapshots.Clear;
begin
  FItems := nil;
end;

function TGittanSnapshots.IndexOf(const AId: string): integer;
var
  i: integer;
begin
  for i := 0 to High(FItems) do
    if FItems[i].Id = AId then
      Exit(i);
  Result := -1;
end;

{ One line per snapshot after the header: the id, a tab and the time as
  TimeFormat (local time, as it is shown). }
procedure TGittanSnapshots.Load(const AFileName: string);
var
  Lines: TStringList;
  Line: string;
  Tab, i: integer;
  Time: TDateTime;
  Fmt: TFormatSettings;
begin
  Clear;
  if not FileExists(AFileName) then
    Exit;
  Fmt := DefaultFormatSettings;
  Fmt.ShortDateFormat := 'yyyy-mm-dd';
  Fmt.DateSeparator := '-';
  Fmt.LongTimeFormat := 'hh:nn:ss';
  Fmt.TimeSeparator := ':';
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(AFileName);
    except
      Exit;
    end;
    if (Lines.Count = 0) or (Lines[0] <> Header) then
      Exit;
    for i := 1 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      Tab := Pos(#9, Line);
      if Tab = 0 then
        Continue;
      if not TryStrToDateTime(Copy(Line, Tab + 1, MaxInt), Time, Fmt) then
        Continue;
      SetLength(FItems, Length(FItems) + 1);
      FItems[High(FItems)].Id := Copy(Line, 1, Tab - 1);
      FItems[High(FItems)].Time := Time;
      if Length(FItems) = MaxSnapshots then
        Break;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TGittanSnapshots.Save(const AFileName: string);
var
  Lines: TStringList;
  i: integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Add(Header);
    for i := 0 to High(FItems) do
      Lines.Add(FItems[i].Id + #9 + FormatDateTime(TimeFormat, FItems[i].Time));
    ForceDirectories(ExtractFileDir(AFileName));
    Lines.SaveToFile(AFileName);
  finally
    Lines.Free;
  end;
end;

class function TGittanSnapshots.Caption(ATime, ANow: TDateTime): string;
begin
  if Trunc(ATime) = Trunc(ANow) then
    Result := FormatDateTime('hh:nn', ATime)
  else
    Result := FormatDateTime('mmm d hh:nn', ATime);
end;

end.
