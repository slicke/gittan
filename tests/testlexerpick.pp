unit testlexerpick;

{** Tests of gittan.lexerpick: the sibling votes that settle an
  ambiguous file extension. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.lexerpick;

type
  TLexerPickTest = class(TTestCase)
  private
    FDir: string;
    procedure Touch(const AName: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSiblingExtensions;
    procedure TestSiblingLimit;
    procedure TestMissingFolder;
    procedure TestMostVoted;
    procedure TestTieAndNoVotes;
    procedure TestPreferredLexer;
  end;

implementation

procedure TLexerPickTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-lexerpick-' +
    IntToStr(GetProcessID);
  ForceDirectories(FDir + '/sub');
end;

procedure TLexerPickTest.TearDown;
var
  Info: TSearchRec;
begin
  if FindFirst(FDir + '/*', faAnyFile, Info) = 0 then
  begin
    repeat
      if (Info.Attr and faDirectory) = 0 then
        DeleteFile(FDir + '/' + Info.Name);
    until FindNext(Info) <> 0;
    FindClose(Info);
  end;
  RemoveDir(FDir + '/sub');
  RemoveDir(FDir);
end;

procedure TLexerPickTest.Touch(const AName: string);
begin
  FileClose(FileCreate(FDir + '/' + AName));
end;

procedure TLexerPickTest.TestSiblingExtensions;
var
  L: TStringList;
begin
  Touch('a.pp');
  Touch('b.PP');
  Touch('c.asm');
  Touch('d.inc');
  Touch('e.inc');
  Touch('Makefile');
  L := TStringList.Create;
  try
    SiblingExtensions(FDir, 'inc', L, 100);
    L.Sort;
    AssertEquals('asm,pp,pp', L.CommaText);
  finally
    L.Free;
  end;
end;

procedure TLexerPickTest.TestSiblingLimit;
var
  L: TStringList;
  i: integer;
begin
  for i := 1 to 20 do
    Touch(Format('f%d.pp', [i]));
  L := TStringList.Create;
  try
    SiblingExtensions(FDir, 'inc', L, 5);
    AssertEquals(5, L.Count);
    SiblingExtensions(FDir, 'inc', L, 0);
    AssertEquals(5, L.Count);
  finally
    L.Free;
  end;
end;

procedure TLexerPickTest.TestMissingFolder;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    SiblingExtensions(FDir + '/nowhere', 'inc', L, 100);
    SiblingExtensions('', 'inc', L, 100);
    AssertEquals(0, L.Count);
  finally
    L.Free;
  end;
end;

procedure TLexerPickTest.TestMostVoted;
var
  Votes, Names: TStringList;
begin
  Votes := TStringList.Create;
  Names := TStringList.Create;
  try
    Votes.CommaText := 'Pascal,Makefile,pascal,Assembly AVR';
    Names.CommaText := '"Assembly AVR",Pascal,Pawn';
    AssertEquals(1, MostVoted(Votes, Names));
  finally
    Votes.Free;
    Names.Free;
  end;
end;

procedure TLexerPickTest.TestTieAndNoVotes;
var
  Votes, Names: TStringList;
begin
  Votes := TStringList.Create;
  Names := TStringList.Create;
  try
    Names.CommaText := '"Assembly AVR",Pascal';
    Votes.CommaText := 'Pascal,"Assembly AVR"';
    AssertEquals(-1, MostVoted(Votes, Names));
    Votes.CommaText := 'Makefile,C';
    AssertEquals(-1, MostVoted(Votes, Names));
    Votes.Clear;
    AssertEquals(-1, MostVoted(Votes, Names));
  finally
    Votes.Free;
    Names.Free;
  end;
end;

procedure TLexerPickTest.TestPreferredLexer;
begin
  AssertEquals('Pascal', PreferredLexer('inc'));
  AssertEquals('Pascal', PreferredLexer('INC'));
  AssertEquals('Pascal', PreferredLexer('pp'));
  AssertEquals('', PreferredLexer('xyz'));
end;

initialization
  RegisterTest(TLexerPickTest);

end.
