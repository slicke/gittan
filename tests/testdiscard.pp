unit testdiscard;

{** Tests of gittan.discard, gittan.textfile: reading a block out of a diff and writing
  its old lines over its new ones in the file on disk. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.discard, gittan.textfile;

type
  TDiscardTest = class(TTestCase)
  private
    FFile: string;
    procedure WriteRaw(const AText: string);
    function ReadRaw: string;
    function Block(const ADiff: array of string; AStart: integer): TGittanDiscard;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestBlockLines;
    procedure TestBlockAtStart;
    procedure TestBlockDeletedOnly;
    procedure TestReplace;
    procedure TestRemoveAdded;
    procedure TestInsertDeleted;
    procedure TestInsertAtEnd;
    procedure TestKeepsCrLf;
    procedure TestKeepsNoFinalNewline;
    procedure TestStale;
    procedure TestUndo;
    procedure TestStaleBeside;
    procedure TestBesideLoose;
    procedure TestMakesDeletedFile;
    procedure TestCount;
  end;

implementation

procedure TDiscardTest.SetUp;
begin
  FFile := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-discard-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt)) + '.txt';
end;

procedure TDiscardTest.TearDown;
begin
  if FileExists(FFile) then
    DeleteFile(FFile);
end;

procedure TDiscardTest.WriteRaw(const AText: string);
var
  F: TFileStream;
begin
  F := TFileStream.Create(FFile, fmCreate);
  try
    if AText <> '' then
      F.WriteBuffer(AText[1], Length(AText));
  finally
    F.Free;
  end;
end;

function TDiscardTest.ReadRaw: string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(FFile, fmOpenRead);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

function TDiscardTest.Block(const ADiff: array of string; AStart: integer): TGittanDiscard;
var
  Lines: TStringList;
  Line: string;
begin
  Lines := TStringList.Create;
  try
    { "\" marks the line before as the last of its side without a
      newline, as FileChanges does from git's "\ No newline". }
    for Line in ADiff do
      if Line = '\' then
        Lines.Objects[Lines.Count - 1] := NoNewlineMark
      else
        Lines.Add(Line);
    Result := DiffBlock(Lines, AStart, FFile);
  finally
    Lines.Free;
  end;
end;

{ The block in the middle: the deleted lines, the added ones, and the
  number of the first added line in the new file (the deleted lines
  before it do not count). }
procedure TDiscardTest.TestBlockLines;
var
  B: TGittanDiscard;
begin
  B := Block([' a', '-b', '+B', '+B2', ' c', '-d', '+D'], 1);
  AssertEquals('line', 2, B.Line);
  AssertEquals('old', 1, Length(B.OldLines));
  AssertEquals('old text', 'b', B.OldLines[0]);
  AssertEquals('new', 2, Length(B.NewLines));
  AssertEquals('new text', 'B2', B.NewLines[1]);
  B := Block([' a', '-b', '+B', '+B2', ' c', '-d', '+D'], 5);
  AssertEquals('second line', 5, B.Line);
  AssertEquals('second old', 'd', B.OldLines[0]);
  AssertEquals('second new', 'D', B.NewLines[0]);
end;

procedure TDiscardTest.TestBlockAtStart;
var
  B: TGittanDiscard;
begin
  B := Block(['+x', ' a'], 0);
  AssertEquals(1, B.Line);
  AssertEquals(0, Length(B.OldLines));
  AssertEquals(1, Length(B.NewLines));
end;

{ A block with nothing added: the old lines go before the line after the
  block. }
procedure TDiscardTest.TestBlockDeletedOnly;
var
  B: TGittanDiscard;
begin
  B := Block([' a', ' b', '-c', '-d', ' e'], 2);
  AssertEquals(3, B.Line);
  AssertEquals(2, Length(B.OldLines));
  AssertEquals(0, Length(B.NewLines));
end;

procedure TDiscardTest.TestReplace;
var
  B: TGittanDiscard;
  Err: string;
begin
  WriteRaw('a'#10'B'#10'B2'#10'c'#10);
  B := Block([' a', '-b', '+B', '+B2', ' c'], 1);
  AssertTrue(Err, DiscardBlock(B, Err));
  AssertEquals('a'#10'b'#10'c'#10, ReadRaw);
end;

procedure TDiscardTest.TestRemoveAdded;
var
  B: TGittanDiscard;
  Err: string;
begin
  WriteRaw('a'#10'x'#10'y'#10'c'#10);
  B := Block([' a', '+x', '+y', ' c'], 1);
  AssertTrue(Err, DiscardBlock(B, Err));
  AssertEquals('a'#10'c'#10, ReadRaw);
end;

procedure TDiscardTest.TestInsertDeleted;
var
  B: TGittanDiscard;
  Err: string;
begin
  WriteRaw('a'#10'c'#10);
  B := Block([' a', '-b', ' c'], 1);
  AssertTrue(Err, DiscardBlock(B, Err));
  AssertEquals('a'#10'b'#10'c'#10, ReadRaw);
end;

procedure TDiscardTest.TestInsertAtEnd;
var
  B: TGittanDiscard;
  Err: string;
begin
  WriteRaw('a'#10);
  B := Block([' a', '-b', '-c'], 1);
  AssertEquals(2, B.Line);
  AssertTrue(Err, DiscardBlock(B, Err));
  AssertEquals('a'#10'b'#10'c'#10, ReadRaw);
end;

{ The diff's lines come without the CR; the file keeps its CRLF ends. }
procedure TDiscardTest.TestKeepsCrLf;
var
  B: TGittanDiscard;
  Err: string;
begin
  WriteRaw('a'#13#10'B'#13#10'c'#13#10);
  B := Block([' a', '-b', '-b2', '+B', ' c'], 1);
  AssertTrue(Err, DiscardBlock(B, Err));
  AssertEquals('a'#13#10'b'#13#10'b2'#13#10'c'#13#10, ReadRaw);
end;

procedure TDiscardTest.TestKeepsNoFinalNewline;
var
  B: TGittanDiscard;
  Err: string;
begin
  { Both sides without one. }
  WriteRaw('a'#10'B');
  B := Block([' a', '-b', '\', '+B', '\'], 1);
  AssertTrue(Err, DiscardBlock(B, Err));
  AssertEquals('a'#10'b', ReadRaw);
  { The old side without one, the new with. }
  WriteRaw('a'#10'b'#10);
  B := Block([' a', '-c', '\', '+b'], 1);
  AssertTrue(Err, DiscardBlock(B, Err));
  AssertEquals('a'#10'c', ReadRaw);
  { A line added after a last line that had a newline, the added one
    without: the old end comes back with its newline. }
  WriteRaw('a'#10'b'#10'c');
  B := Block([' a', ' b', '+c', '\'], 2);
  AssertTrue(Err, DiscardBlock(B, Err));
  AssertEquals('a'#10'b'#10, ReadRaw);
  { Only the newline changed. }
  WriteRaw('a'#10'b'#10);
  B := Block([' a', '-b', '\', '+b'], 1);
  AssertTrue(Err, DiscardBlock(B, Err));
  AssertEquals('a'#10'b', ReadRaw);
  { Undone, the newline is back. }
  AssertTrue(Err, DiscardBlock(Swapped(B), Err));
  AssertEquals('a'#10'b'#10, ReadRaw);
  { The file's end changed since the diff: stale, the change left. }
  WriteRaw('a'#10'B');
  B := Block([' a', '-b', '+B'], 1);
  AssertFalse('newline taken away since', DiscardBlock(B, Err));
  AssertEquals(rsDiscardStale, Err);
  AssertEquals('a'#10'B', ReadRaw);
  { A block in the middle keeps the file's end as it is. }
  WriteRaw('a'#10'B'#10'c');
  B := Block([' a', '-b', '+B', ' c', '\'], 1);
  AssertTrue(Err, DiscardBlock(B, Err));
  AssertEquals('a'#10'b'#10'c', ReadRaw);
end;

{ The file changed since the diff: nothing is written. }
procedure TDiscardTest.TestStale;
var
  B: TGittanDiscard;
  Err: string;
begin
  WriteRaw('a'#10'other'#10'c'#10);
  B := Block([' a', '-b', '+B', ' c'], 1);
  AssertFalse(DiscardBlock(B, Err));
  AssertEquals(rsDiscardStale, Err);
  AssertEquals('a'#10'other'#10'c'#10, ReadRaw);
  WriteRaw('a'#10);
  AssertFalse('past the end', DiscardBlock(B, Err));
  AssertEquals(rsDiscardStale, Err);
end;

procedure TDiscardTest.TestUndo;
var
  B: TGittanDiscard;
  Err: string;
begin
  WriteRaw('a'#10'B'#10'c'#10);
  B := Block([' a', '-b', '-b2', '+B', ' c'], 1);
  AssertTrue(Err, DiscardBlock(B, Err));
  AssertEquals('a'#10'b'#10'b2'#10'c'#10, ReadRaw);
  AssertTrue(Err, DiscardBlock(Swapped(B), Err));
  AssertEquals('a'#10'B'#10'c'#10, ReadRaw);
end;

{ A block that adds nothing has no line of its own to check: the lines
  beside it tell that the file moved since. Undoing a discarded added line
  after lines were added above it is refused, not put in the wrong place. }
procedure TDiscardTest.TestStaleBeside;
var
  B: TGittanDiscard;
  Err: string;
begin
  WriteRaw('a'#10'DEBUG'#10'b'#10);
  B := Block([' a', '+DEBUG', ' b'], 1);
  AssertTrue(Err, DiscardBlock(B, Err));
  AssertEquals('a'#10'b'#10, ReadRaw);
  WriteRaw('new1'#10'new2'#10'a'#10'b'#10);
  AssertFalse(DiscardBlock(Swapped(B), Err));
  AssertEquals(rsDiscardStale, Err);
  AssertEquals('new1'#10'new2'#10'a'#10'b'#10, ReadRaw);
  { A deleted line put back where the file has moved. }
  WriteRaw('x'#10'a'#10'c'#10);
  B := Block([' a', '-b', ' c'], 1);
  AssertFalse(DiscardBlock(B, Err));
  AssertEquals(rsDiscardStale, Err);
  { At the end of the file, with a line added after since. }
  WriteRaw('a'#10'z'#10);
  B := Block([' a', '-b'], 1);
  AssertFalse(DiscardBlock(B, Err));
  AssertEquals(rsDiscardStale, Err);
end;

{ A diff taken with whitespace ignored shows a line beside the block as the
  version compared against has it, which may differ in blanks alone. }
procedure TDiscardTest.TestBesideLoose;
var
  B: TGittanDiscard;
  Err: string;
begin
  WriteRaw('  a'#13#10'c'#13#10);
  B := Block([' a', '-b', ' c'], 1);
  AssertTrue(Err, DiscardBlock(B, Err));
  AssertEquals('  a'#13#10'b'#13#10'c'#13#10, ReadRaw);
end;

{ A deleted file is one block of deleted lines at line 1; discarding it
  makes the file again. Any other block needs the file. }
procedure TDiscardTest.TestMakesDeletedFile;
var
  B: TGittanDiscard;
  Err: string;
begin
  B := Block(['-a', '-b'], 0);
  AssertTrue(Err, DiscardBlock(B, Err));
  AssertEquals('a'#10'b'#10, ReadRaw);
  { Its undo deletes it again, rather than leave it empty, when the
    discard made it; an undo that did not leaves an empty file. }
  B.Created := True;
  AssertTrue(Err, DiscardBlock(Swapped(B), Err));
  AssertFalse('deleted again', FileExists(FFile));
  AssertTrue(Err, DiscardBlock(B, Err));
  B.Created := False;
  AssertTrue(Err, DiscardBlock(Swapped(B), Err));
  AssertTrue('emptied', FileExists(FFile));
  AssertEquals('', ReadRaw);
  DeleteFile(FFile);
  B := Block([' a', '-b', '+B'], 1);
  AssertFalse(DiscardBlock(B, Err));
  AssertEquals(rsDiscardNoFile, Err);
  AssertFalse(FileExists(FFile));
end;

procedure TDiscardTest.TestCount;
begin
  AssertEquals(2, DiscardCount(Block([' a', '-b', '-b2', '+B', ' c'], 1)));
  AssertEquals(3, DiscardCount(Block([' a', '+x', '+y', '+z', ' c'], 1)));
end;

initialization
  RegisterTest(TDiscardTest);

end.
