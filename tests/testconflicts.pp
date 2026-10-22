unit testconflicts;

{** Tests of gittan.conflicts. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry, gittan.conflicts, gittan.discard;

type
  TConflictsTest = class(TTestCase)
  private
    FLines: TStringList;
    function Roles(const ALines: array of string; out ACount: integer): string;
    procedure Fill(const ALines: array of string);
    function Joined(const ALines: TStringArray): string;
    function Resolved(AStart: integer; APick: TGittanConflictPick): TGittanDiscard;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNone;
    procedure TestMerge;
    procedure TestDiff3;
    procedure TestNotMarkers;
    procedure TestOpenAtEnd;
    procedure TestStarts;
    procedure TestEnds;
    procedure TestSides;
    procedure TestResolvePicks;
    procedure TestResolveSkipsDeleted;
    procedure TestResolveOpenAtEnd;
    procedure TestResolveWrites;
  end;

implementation

procedure TConflictsTest.SetUp;
begin
  FLines := TStringList.Create;
end;

procedure TConflictsTest.TearDown;
begin
  FLines.Free;
end;

procedure TConflictsTest.Fill(const ALines: array of string);
var
  i: integer;
begin
  FLines.Clear;
  for i := 0 to High(ALines) do
    FLines.Add(ALines[i]);
end;

function TConflictsTest.Joined(const ALines: TStringArray): string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(ALines) do
  begin
    if i > 0 then
      Result := Result + '|';
    Result := Result + ALines[i];
  end;
end;

function TConflictsTest.Resolved(AStart: integer; APick: TGittanConflictPick): TGittanDiscard;
begin
  Result := ResolveBlock(FLines, ConflictRoles(FLines), AStart, APick, 'f.txt');
end;

{ The roles as digits, one per line. }
function TConflictsTest.Roles(const ALines: array of string; out ACount: integer): string;
var
  List: TStringList;
  R: TIntegerDynArray;
  i: integer;
begin
  List := TStringList.Create;
  try
    for i := 0 to High(ALines) do
      List.Add(ALines[i]);
    R := ConflictRoles(List);
    ACount := ConflictCount(R, List);
    Result := '';
    for i := 0 to High(R) do
      Result := Result + IntToStr(R[i]);
  finally
    List.Free;
  end;
end;

procedure TConflictsTest.TestNone;
var
  n: integer;
begin
  AssertEquals('000', Roles([' a', '+b', '-c'], n));
  AssertEquals(0, n);
  AssertEquals('', Roles([], n));
end;

procedure TConflictsTest.TestMerge;
var
  n: integer;
begin
  AssertEquals('0122104410', Roles([' a', '+<<<<<<< HEAD', ' ours', ' ours 2', '+=======',
    '-old', '+theirs', '+theirs 2', '+>>>>>>> other', ' z'], n));
  AssertEquals(1, n);
end;

procedure TConflictsTest.TestDiff3;
var
  n: integer;
begin
  AssertEquals('012131410121410', Roles([' a', '+<<<<<<< HEAD', ' B-main', '+||||||| 7a9841f',
    '+b', '+=======', '+B-other', '+>>>>>>> other', ' c', '+<<<<<<<', ' x', '+=======',
    '+y', '+>>>>>>>', ' d'], n));
  AssertEquals(2, n);
end;

procedure TConflictsTest.TestNotMarkers;
var
  n: integer;
begin
  { Six signs, a word after the signs without a space, a lone "=======" or
    ">>>>>>>" outside a conflict, and a deleted marker. }
  AssertEquals('00000', Roles(['+<<<<<<', '+<<<<<<<x', '+=======', '+>>>>>>> a', '-<<<<<<< HEAD'], n));
  AssertEquals(0, n);
end;

procedure TConflictsTest.TestOpenAtEnd;
var
  n: integer;
begin
  AssertEquals('122', Roles(['+<<<<<<< HEAD', ' a', ' b'], n));
  AssertEquals(1, n);
end;

procedure TConflictsTest.TestStarts;
var
  S: TIntegerDynArray;
begin
  Fill([' a', '+<<<<<<< HEAD', ' B', '+=======', '+C', '+>>>>>>> other', ' c', '+<<<<<<<',
    ' x', '+=======', '+y', '+>>>>>>>', ' d']);
  S := ConflictStarts(ConflictRoles(FLines), FLines);
  AssertEquals(2, Length(S));
  AssertEquals(1, S[0]);
  AssertEquals(7, S[1]);
  Fill([' a', '+b']);
  AssertEquals(0, Length(ConflictStarts(ConflictRoles(FLines), FLines)));
end;

procedure TConflictsTest.TestEnds;
var
  R: TIntegerDynArray;
begin
  Fill([' a', '+<<<<<<< HEAD', ' B', '-old', '+=======', '+C', '+>>>>>>> other', '-gone', ' c',
    '+<<<<<<<', ' x', '-y']);
  R := ConflictRoles(FLines);
  AssertEquals(6, ConflictEnd(FLines, R, 1));
  { Open at the end: the last line with a role, not the deleted one. }
  AssertEquals(10, ConflictEnd(FLines, R, 9));
  { No conflict starts here. }
  AssertEquals(0, ConflictEnd(FLines, R, 0));
  AssertEquals(2, ConflictEnd(FLines, R, 2));
end;

procedure TConflictsTest.TestSides;
var
  Ours, Theirs: string;
begin
  AssertEquals('HEAD', MarkerName('+<<<<<<< HEAD'));
  AssertEquals('', MarkerName('+<<<<<<<'));
  AssertEquals('3f2a1c0 (Fix the thing)', MarkerName('+>>>>>>> 3f2a1c0 (Fix the thing)'));
  Fill([' a', '+<<<<<<< HEAD', ' B', '-old', '+||||||| base', '+b', '+=======', '+C',
    '+>>>>>>> feature', ' c', '+<<<<<<< HEAD', ' x']);
  ConflictSides(FLines, ConflictRoles(FLines), 1, Ours, Theirs);
  AssertEquals('HEAD', Ours);
  AssertEquals('feature', Theirs);
  { Open at the end: no name for their side. }
  ConflictSides(FLines, ConflictRoles(FLines), 10, Ours, Theirs);
  AssertEquals('HEAD', Ours);
  AssertEquals('', Theirs);
  { Not a conflict start. }
  ConflictSides(FLines, ConflictRoles(FLines), 0, Ours, Theirs);
  AssertEquals('', Ours);
  AssertEquals('', Theirs);
end;

procedure TConflictsTest.TestResolvePicks;
var
  B: TGittanDiscard;
begin
  Fill([' a', ' b', '+<<<<<<< HEAD', ' ours', ' ours 2', '+||||||| base', '+base',
    '+=======', '+theirs', '+>>>>>>> other', ' z']);
  B := Resolved(2, cpOurs);
  AssertEquals('f.txt', B.FileName);
  AssertEquals(3, B.Line);
  AssertEquals('<<<<<<< HEAD|ours|ours 2|||||||| base|base|=======|theirs|>>>>>>> other',
    Joined(B.NewLines));
  AssertEquals('ours|ours 2', Joined(B.OldLines));
  AssertEquals('theirs', Joined(Resolved(2, cpTheirs).OldLines));
  AssertEquals('ours|ours 2|theirs', Joined(Resolved(2, cpOursThenTheirs).OldLines));
  AssertEquals('theirs|ours|ours 2', Joined(Resolved(2, cpTheirsThenOurs).OldLines));
end;

procedure TConflictsTest.TestResolveSkipsDeleted;
var
  B: TGittanDiscard;
begin
  { HEAD's lines the work tree lost show as deleted, before and inside
    the conflict; they are not in the file, so neither the line nor the
    block counts them. }
  Fill([' a', '-gone', '+<<<<<<< HEAD', '-old', '+ours', '+=======', '-old 2', '+theirs',
    '+>>>>>>> other', '-after', ' z']);
  B := Resolved(2, cpTheirs);
  AssertEquals(2, B.Line);
  AssertEquals('<<<<<<< HEAD|ours|=======|theirs|>>>>>>> other', Joined(B.NewLines));
  AssertEquals('theirs', Joined(B.OldLines));
end;

procedure TConflictsTest.TestResolveOpenAtEnd;
var
  B: TGittanDiscard;
begin
  Fill(['+<<<<<<< HEAD', ' a', '+=======', '+b']);
  B := Resolved(0, cpOursThenTheirs);
  AssertEquals(1, B.Line);
  AssertEquals('<<<<<<< HEAD|a|=======|b', Joined(B.NewLines));
  AssertEquals('a|b', Joined(B.OldLines));
  AssertEquals('b', Joined(Resolved(0, cpTheirs).OldLines));
end;

procedure TConflictsTest.TestResolveWrites;
var
  FileName, Err, Text: string;
  B: TGittanDiscard;
  F: TFileStream;
begin
  FileName := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-conflict-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt)) + '.txt';
  Text := 'a' + #10 + '<<<<<<< HEAD' + #10 + 'ours' + #10 + '=======' + #10 + 'theirs' +
    #10 + '>>>>>>> other' + #10 + 'z' + #10;
  F := TFileStream.Create(FileName, fmCreate);
  try
    F.WriteBuffer(Text[1], Length(Text));
  finally
    F.Free;
  end;
  try
    Fill([' a', '+<<<<<<< HEAD', ' ours', '+=======', '+theirs', '+>>>>>>> other', ' z']);
    B := ResolveBlock(FLines, ConflictRoles(FLines), 1, cpTheirsThenOurs, FileName);
    AssertTrue(DiscardBlock(B, Err));
    F := TFileStream.Create(FileName, fmOpenRead);
    try
      SetLength(Text, F.Size);
      F.ReadBuffer(Text[1], F.Size);
    finally
      F.Free;
    end;
    AssertEquals('a' + #10 + 'theirs' + #10 + 'ours' + #10 + 'z' + #10, Text);
    { The conflict is gone now, so writing it again is refused. }
    AssertFalse(DiscardBlock(B, Err));
    AssertEquals(rsDiscardStale, Err);
    { And Swapped puts it back, keeping whether the file was resolved. }
    B.Resolved := True;
    AssertTrue(Swapped(B).Resolved);
    AssertTrue(DiscardBlock(Swapped(B), Err));
    F := TFileStream.Create(FileName, fmOpenRead);
    try
      SetLength(Text, F.Size);
      F.ReadBuffer(Text[1], F.Size);
    finally
      F.Free;
    end;
    AssertEquals('a' + #10 + '<<<<<<< HEAD' + #10 + 'ours' + #10 + '=======' + #10 +
      'theirs' + #10 + '>>>>>>> other' + #10 + 'z' + #10, Text);
  finally
    DeleteFile(FileName);
  end;
end;

initialization
  RegisterTest(TConflictsTest);

end.
