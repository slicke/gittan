unit testrepofiles;

{** Tests of gittan.repofiles: the list of the repository's own files,
  the ignore patterns for a path and writing one to an ignore file. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.repofiles, testhelpers;

type
  TRepoFilesTest = class(TTestCase)
  private
    FDir: string;
    procedure Touch(const ARel: string);
    function ReadAll(const ARel: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestListOrder;
    procedure TestListEmpty;
    procedure TestPatterns;
    procedure TestIsRepoFile;
    procedure TestAddMakesFile;
    procedure TestAddAppends;
    procedure TestAddOnce;
    procedure TestLfsPatterns;
    procedure TestLfsTrack;
  end;

implementation

procedure TRepoFilesTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-repofiles-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
end;

procedure TRepoFilesTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TRepoFilesTest.Touch(const ARel: string);
var
  Name: string;
begin
  Name := IncludeTrailingPathDelimiter(FDir) + SetDirSeparators(ARel);
  ForceDirectories(ExtractFileDir(Name));
  with TStringList.Create do
  try
    Add(ARel);
    SaveToFile(Name);
  finally
    Free;
  end;
end;

function TRepoFilesTest.ReadAll(const ARel: string): string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(IncludeTrailingPathDelimiter(FDir) + ARel, fmOpenRead);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

procedure TRepoFilesTest.TestListOrder;
var
  L: TStringList;
begin
  Touch('.editorconfig');
  Touch('.gitignore');
  Touch('.github/workflows/build.yml');
  Touch('.github/CODEOWNERS');
  Touch('.github/ISSUE_TEMPLATE/bug.md');
  Touch('.gittan/commands.ini');
  Touch('README.md');
  L := TStringList.Create;
  try
    ListRepoFiles(FDir, L);
    AssertEquals(6, L.Count);
    AssertEquals('the root files in their fixed order', '.gitignore', L[0]);
    AssertEquals('.editorconfig', L[1]);
    AssertEquals('then .github sorted by path', '.github/CODEOWNERS', L[2]);
    AssertEquals('.github/ISSUE_TEMPLATE/bug.md', L[3]);
    AssertEquals('.github/workflows/build.yml', L[4]);
    AssertEquals('then .gittan', '.gittan/commands.ini', L[5]);
  finally
    L.Free;
  end;
end;

procedure TRepoFilesTest.TestListEmpty;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Add('stale');
    ListRepoFiles(FDir, L);
    AssertEquals('a root without any is an empty list', 0, L.Count);
    ListRepoFiles('', L);
    AssertEquals(0, L.Count);
  finally
    L.Free;
  end;
end;

procedure TRepoFilesTest.TestPatterns;
var
  P: TStringArray;
begin
  P := IgnorePatterns('src/lib/foo.o');
  AssertEquals(3, Length(P));
  AssertEquals('/src/lib/foo.o', P[0]);
  AssertEquals('*.o', P[1]);
  AssertEquals('/src/lib/', P[2]);
  P := IgnorePatterns('notes');
  AssertEquals('no extension, no folder', 1, Length(P));
  AssertEquals('/notes', P[0]);
  P := IgnorePatterns('.env');
  AssertEquals('a dotfile has no extension to generalize', 1, Length(P));
  AssertEquals('/.env', P[0]);
  AssertEquals(0, Length(IgnorePatterns('')));
end;

procedure TRepoFilesTest.TestIsRepoFile;
begin
  AssertTrue(IsRepoFile('.gitignore'));
  AssertTrue(IsRepoFile('.editorconfig'));
  AssertTrue(IsRepoFile('.github/workflows/ci.yml'));
  AssertTrue(IsRepoFile('.github/CODEOWNERS'));
  AssertTrue(IsRepoFile('.gittan/commands.ini'));
  AssertFalse('a source file', IsRepoFile('src/main.pas'));
  AssertFalse('a root file not in the list', IsRepoFile('README.md'));
  AssertFalse('an ignore file in a folder', IsRepoFile('src/.gitignore'));
  AssertFalse('the folder itself', IsRepoFile('.github'));
  AssertFalse('a name that starts like the folder', IsRepoFile('.githubx/a'));
  AssertFalse(IsRepoFile(''));
end;

procedure TRepoFilesTest.TestAddMakesFile;
var
  Name: string;
begin
  Name := IncludeTrailingPathDelimiter(FDir) + 'info' + PathDelim + 'exclude';
  AssertTrue(AddIgnorePattern(Name, '*.log'));
  AssertEquals('the folder is made too', '*.log' + LineEnding,
    ReadAll('info' + PathDelim + 'exclude'));
end;

procedure TRepoFilesTest.TestAddAppends;
var
  Name: string;
  F: TFileStream;
  S: string;
begin
  Name := IncludeTrailingPathDelimiter(FDir) + '.gitignore';
  S := 'lib/';
  F := TFileStream.Create(Name, fmCreate);
  try
    F.WriteBuffer(S[1], Length(S));
  finally
    F.Free;
  end;
  AssertTrue(AddIgnorePattern(Name, '*.o'));
  AssertEquals('a missing final newline is supplied first',
    'lib/' + LineEnding + '*.o' + LineEnding, ReadAll('.gitignore'));
  AssertTrue(AddIgnorePattern(Name, '/build/'));
  AssertEquals('lib/' + LineEnding + '*.o' + LineEnding + '/build/' + LineEnding,
    ReadAll('.gitignore'));
end;

procedure TRepoFilesTest.TestAddOnce;
var
  Name: string;
begin
  Name := IncludeTrailingPathDelimiter(FDir) + '.gitignore';
  AssertTrue(AddIgnorePattern(Name, '*.o'));
  AssertTrue(AddIgnorePattern(Name, '*.o'));
  AssertEquals('a line already there is not added again', '*.o' + LineEnding,
    ReadAll('.gitignore'));
  AssertTrue(AddIgnorePattern(Name, '*.O'));
  AssertEquals('another case is another pattern', '*.o' + LineEnding + '*.O' + LineEnding,
    ReadAll('.gitignore'));
end;

procedure TRepoFilesTest.TestLfsPatterns;
var
  P: TStringArray;
const
  Text = '# art'#10'*.psd filter=lfs diff=lfs merge=lfs -text'#10'*.txt text'#10 +
    'art/logo.png  filter=lfs -text'#10'/big[[:space:]]file.bin filter=lfs'#10;
begin
  P := LfsTrackPatterns('art/logo.psd');
  AssertEquals(2, Length(P));
  AssertEquals('*.psd', P[0]);
  AssertEquals('/art/logo.psd', P[1]);
  P := LfsTrackPatterns('big file.bin');
  AssertEquals('*.bin', P[0]);
  AssertEquals('/big[[:space:]]file.bin', P[1]);
  { [draft] would be a class of characters to git. }
  P := LfsTrackPatterns('art/[draft]*.psd');
  AssertEquals('/art/\[draft\]\*.psd', P[1]);
  P := LfsTrackPatterns('Makefile');
  AssertEquals(1, Length(P));
  AssertEquals('/Makefile', P[0]);
  AssertEquals(0, Length(LfsTrackPatterns('')));

  P := LfsTrackedPatterns(Text);
  AssertEquals(3, Length(P));
  AssertEquals('*.psd', P[0]);
  AssertEquals('art/logo.png', P[1]);
  AssertEquals('/big[[:space:]]file.bin', P[2]);

  P := LfsPatternsOf(Text, 'art/logo.png');
  AssertEquals('without the leading slash', 1, Length(P));
  AssertEquals('art/logo.png', P[0]);
  P := LfsPatternsOf(Text, 'big file.bin');
  AssertEquals(1, Length(P));
  AssertEquals('/big[[:space:]]file.bin', P[0]);
  AssertEquals('a pattern not its own', 0, Length(LfsPatternsOf(Text, 'docs/a.txt')));
end;

procedure TRepoFilesTest.TestLfsTrack;
var
  Name: string;
  F: TFileStream;
  S: string;
begin
  Name := IncludeTrailingPathDelimiter(FDir) + '.gitattributes';
  AssertTrue(AddLfsTrack(Name, '*.psd'));
  AssertEquals('*.psd filter=lfs diff=lfs merge=lfs -text' + LineEnding,
    ReadAll('.gitattributes'));
  AssertTrue('once', AddLfsTrack(Name, '*.psd'));
  AssertEquals('*.psd filter=lfs diff=lfs merge=lfs -text' + LineEnding,
    ReadAll('.gitattributes'));

  S := '*.txt text'#13#10'*.psd  filter=lfs -text'#13#10'# end'#13#10;
  F := TFileStream.Create(Name, fmCreate);
  try
    F.WriteBuffer(S[1], Length(S));
  finally
    F.Free;
  end;
  AssertTrue('tracked in other words', AddLfsTrack(Name, '*.psd'));
  AssertEquals(S, ReadAll('.gitattributes'));
  AssertTrue(RemoveLfsTrack(Name, '*.psd'));
  AssertEquals('the other lines and their ends kept', '*.txt text'#13#10'# end'#13#10,
    ReadAll('.gitattributes'));
  AssertTrue('a pattern not there', RemoveLfsTrack(Name, '*.zip'));
  AssertEquals('*.txt text'#13#10'# end'#13#10, ReadAll('.gitattributes'));
  AssertFalse('no file', RemoveLfsTrack(Name + '-none', '*.psd'));
end;

initialization
  RegisterTest(TRepoFilesTest);
end.
