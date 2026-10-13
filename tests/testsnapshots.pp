unit testsnapshots;

{** Tests of gittan.snapshots: the list, its file and the captions. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.snapshots;

type
  TSnapshotsTest = class(TTestCase)
  published
    procedure TestAddNewestFirst;
    procedure TestLimit;
    procedure TestSaveLoad;
    procedure TestBrokenFile;
    procedure TestCaption;
  end;

implementation

procedure TSnapshotsTest.TestAddNewestFirst;
var
  L: TGittanSnapshots;
begin
  L := TGittanSnapshots.Create;
  try
    L.Add('a', 1);
    L.Add('b', 2);
    AssertEquals(2, L.Count);
    AssertEquals('b', L[0].Id);
    AssertEquals('a', L[1].Id);
    AssertEquals(1, L.IndexOf('a'));
    AssertEquals(-1, L.IndexOf('c'));
    L.Add('a', 3);
    AssertEquals('the same id moves first', 2, L.Count);
    AssertEquals('a', L[0].Id);
    AssertEquals(3.0, L[0].Time, 0);
    L.Delete(0);
    AssertEquals(1, L.Count);
    AssertEquals('b', L[0].Id);
  finally
    L.Free;
  end;
end;

procedure TSnapshotsTest.TestLimit;
var
  L: TGittanSnapshots;
  i: integer;
begin
  L := TGittanSnapshots.Create;
  try
    for i := 1 to MaxSnapshots + 3 do
      L.Add(IntToStr(i), i);
    AssertEquals(MaxSnapshots, L.Count);
    AssertEquals(IntToStr(MaxSnapshots + 3), L[0].Id);
    AssertEquals('the oldest are dropped', '4', L[L.Count - 1].Id);
  finally
    L.Free;
  end;
end;

procedure TSnapshotsTest.TestSaveLoad;
var
  L: TGittanSnapshots;
  FileName: string;
  T: TDateTime;
begin
  FileName := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-snapshots-test-' +
    IntToStr(GetProcessID) + PathDelim + 'list.txt';
  T := EncodeDate(2026, 10, 13) + EncodeTime(17, 5, 9, 0);
  L := TGittanSnapshots.Create;
  try
    L.Add('1111', T);
    L.Add('2222', T + 1);
    L.Save(FileName);
    L.Clear;
    AssertEquals(0, L.Count);
    L.Load(FileName);
    AssertEquals(2, L.Count);
    AssertEquals('2222', L[0].Id);
    AssertEquals('1111', L[1].Id);
    AssertEquals(T, L[1].Time, 1 / 86400 / 2);
  finally
    L.Free;
    DeleteFile(FileName);
    RemoveDir(ExtractFileDir(FileName));
  end;
end;

procedure TSnapshotsTest.TestBrokenFile;
var
  L: TGittanSnapshots;
  FileName: string;
  Lines: TStringList;
begin
  FileName := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-snapshots-broken-' +
    IntToStr(GetProcessID) + '.txt';
  Lines := TStringList.Create;
  L := TGittanSnapshots.Create;
  try
    L.Load(FileName + '.missing');
    AssertEquals(0, L.Count);
    Lines.Add('gittan-snapshots 1');
    Lines.Add('no tab here');
    Lines.Add('abcd'#9'not a time');
    Lines.Add('ef01'#9'2026-10-13 17:05:09');
    Lines.SaveToFile(FileName);
    L.Load(FileName);
    AssertEquals('only the good line', 1, L.Count);
    AssertEquals('ef01', L[0].Id);
    Lines.Clear;
    Lines.Add('something else');
    Lines.SaveToFile(FileName);
    L.Load(FileName);
    AssertEquals('wrong header', 0, L.Count);
  finally
    L.Free;
    Lines.Free;
    DeleteFile(FileName);
  end;
end;

procedure TSnapshotsTest.TestCaption;
var
  Day: TDateTime;
begin
  Day := EncodeDate(2026, 10, 13);
  AssertEquals('14:32', TGittanSnapshots.Caption(Day + EncodeTime(14, 32, 0, 0),
    Day + EncodeTime(18, 0, 0, 0)));
  AssertEquals(FormatDateTime('mmm', Day) + ' 13 14:32',
    TGittanSnapshots.Caption(Day + EncodeTime(14, 32, 0, 0), Day + 1));
end;

initialization
  RegisterTest(TSnapshotsTest);

end.
