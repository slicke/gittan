unit testsymbolindex;

{** Tests of gittan.symbolindex: the entries, their stamps and the file
  round trip. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.symbols, gittan.symbolindex;

type
  TSymbolIndexTest = class(TTestCase)
  private
    FFileName: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEntries;
    procedure TestStamp;
    procedure TestRoundTrip;
    procedure TestMissingAndDamagedFile;
  end;

implementation

procedure TSymbolIndexTest.SetUp;
begin
  FFileName := GetTempFileName('', 'gittan-index-');
end;

procedure TSymbolIndexTest.TearDown;
begin
  if FileExists(FFileName) then
    DeleteFile(FFileName);
end;

procedure TSymbolIndexTest.TestEntries;
var
  Index: TGittanSymbolIndex;
  Keep: TStringList;
begin
  Index := TGittanSymbolIndex.Create;
  Keep := TStringList.Create;
  try
    AssertNull(Index.Find('a.pp'));
    AssertEquals('a.pp', Index.Add('a.pp').Path);
    AssertTrue(Index.Add('a.pp') = Index.Find('a.pp'));
    Index.Add('b.pp');
    Index.Add('c.pp');
    AssertEquals(3, Index.Count);
    Index.Remove('b.pp');
    AssertEquals(2, Index.Count);
    Keep.Add('c.pp');
    Index.KeepOnly(Keep);
    AssertEquals(1, Index.Count);
    AssertNotNull(Index.Find('c.pp'));
  finally
    Index.Free;
    Keep.Free;
  end;
end;

procedure TSymbolIndexTest.TestStamp;
var
  Index: TGittanSymbolIndex;
  E: TGittanIndexEntry;
  Size, Time: int64;
begin
  AssertFalse('missing file', FileStamp(FFileName + '.nowhere', Size, Time));
  { GetTempFileName only names the file. }
  FileClose(FileCreate(FFileName));
  AssertTrue('existing file', FileStamp(FFileName, Size, Time));
  Index := TGittanSymbolIndex.Create;
  try
    AssertFalse(Index.IsCurrent('x', Size, Time));
    E := Index.Add('x');
    E.Size := Size;
    E.Time := Time;
    AssertFalse('queued only', Index.IsCurrent('x', Size, Time));
    E.Indexed := True;
    AssertTrue(Index.IsCurrent('x', Size, Time));
    AssertFalse(Index.IsCurrent('x', Size + 1, Time));
    AssertFalse(Index.IsCurrent('x', Size, Time + 1));
  finally
    Index.Free;
  end;
end;

procedure TSymbolIndexTest.TestRoundTrip;
var
  Index: TGittanSymbolIndex;
  E: TGittanIndexEntry;
begin
  Index := TGittanSymbolIndex.Create;
  try
    E := Index.Add('dir/a b.pp');
    E.Size := 123;
    E.Time := 456;
    E.Indexed := True;
    SetLength(E.Items, 2);
    E.Items[0].Name := 'TFoo.Bar';
    E.Items[0].Row := 10;
    E.Items[0].Col := 17;
    E.Items[0].Depth := 1;
    E.Items[0].Line := 'procedure TFoo.Bar;'#9'{ tab \ backslash }';
    E.Items[1].Name := 'baz';
    E.Items[1].Row := 20;
    E.Items[1].Line := '';
    Index.Add('queued.pp');
    E := Index.Add('empty.pp');
    E.Indexed := True;
    Index.Save(FFileName);
  finally
    Index.Free;
  end;
  Index := TGittanSymbolIndex.Create;
  try
    Index.Load(FFileName);
    AssertEquals('queued entries are not saved', 2, Index.Count);
    E := Index.Find('dir/a b.pp');
    AssertNotNull(E);
    AssertTrue(E.Indexed);
    AssertTrue(Index.IsCurrent('dir/a b.pp', 123, 456));
    AssertEquals(2, Length(E.Items));
    AssertEquals('TFoo.Bar', E.Items[0].Name);
    AssertEquals(10, E.Items[0].Row);
    AssertEquals(17, E.Items[0].Col);
    AssertEquals(1, E.Items[0].Depth);
    AssertEquals('procedure TFoo.Bar;'#9'{ tab \ backslash }', E.Items[0].Line);
    AssertEquals('baz', E.Items[1].Name);
    AssertEquals('', E.Items[1].Line);
    AssertEquals(0, Length(Index.Find('empty.pp').Items));
  finally
    Index.Free;
  end;
end;

procedure TSymbolIndexTest.TestMissingAndDamagedFile;
var
  Index: TGittanSymbolIndex;
  L: TStringList;
begin
  Index := TGittanSymbolIndex.Create;
  try
    Index.Load(FFileName + '.nowhere');
    AssertEquals(0, Index.Count);
    L := TStringList.Create;
    try
      L.Add('gittan-index 1');
      L.Add('F'#9'a.pp'#9'1'#9'2');
      L.Add('garbage');
      L.SaveToFile(FFileName);
    finally
      L.Free;
    end;
    Index.Load(FFileName);
    AssertEquals('damaged file gives nothing', 0, Index.Count);
  finally
    Index.Free;
  end;
end;

initialization
  RegisterTest(TSymbolIndexTest);

end.
