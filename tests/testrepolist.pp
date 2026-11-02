unit testrepolist;

{** Tests of gittan.repolist: adding, moving and removing entries, the
  rows shown, the file round trip and finding the repositories in a
  folder. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.repolist, testhelpers;

type
  TRepoListTest = class(TTestCase)
  private
    FDir: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAdd;
    procedure TestMove;
    procedure TestRemove;
    procedure TestRows;
    procedure TestRoundTrip;
    procedure TestDamagedFile;
    procedure TestFind;
  end;

implementation

procedure TRepoListTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'gittan-repolist-' +
    IntToStr(Random(1000000));
  ForceDirectories(FDir);
  FDir := RepoListPath(FDir);
end;

procedure TRepoListTest.TearDown;
begin
  RemoveTree(FDir);
end;

function P(const AName: string): string;
begin
  Result := RepoListPath(PathDelim + 'r' + PathDelim + AName);
end;

{ Captions of AFolder's entries, comma separated. }
function Names(AFolder: TGittanRepoEntry): string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to AFolder.Count - 1 do
  begin
    if i > 0 then
      Result := Result + ',';
    Result := Result + AFolder[i].Caption;
  end;
end;

procedure TRepoListTest.TestAdd;
var
  L: TGittanRepoList;
  W: TGittanRepoEntry;
begin
  L := TGittanRepoList.Create('');
  try
    AssertNotNull(L.AddRepo(nil, P('a') + PathDelim));
    AssertEquals('trailing delimiter dropped', P('a'), L.Root[0].Path);
    AssertNull('twice', L.AddRepo(nil, P('a')));
    W := L.AddFolder(nil, 'Work');
    AssertNotNull(L.AddRepo(W, P('b')));
    AssertNull('in another folder', L.AddRepo(nil, P('b')));
    L.AddRepo(nil, P('c'), 0);
    AssertEquals('c,a,Work', Names(L.Root));
    AssertEquals('b', Names(W));
    AssertTrue(L.Find(P('b')) = W[0]);
    AssertNull(L.Find(P('z')));
    W[0].Name := 'Bee';
    AssertEquals('own name', 'Bee', W[0].Caption);
    AssertEquals(3, L.Root.RepoCount);
  finally
    L.Free;
  end;
end;

procedure TRepoListTest.TestMove;
var
  L: TGittanRepoList;
  W, Inner: TGittanRepoEntry;
begin
  L := TGittanRepoList.Create('');
  try
    L.AddRepo(nil, P('a'));
    L.AddRepo(nil, P('b'));
    L.AddRepo(nil, P('c'));
    { Before the entry that is there now, in the same folder. }
    AssertTrue(L.Move(L.Root[0], nil, 2));
    AssertEquals('b,a,c', Names(L.Root));
    AssertTrue(L.Move(L.Root[2], nil, 0));
    AssertEquals('c,b,a', Names(L.Root));
    AssertTrue(L.Move(L.Root[0], nil, -1));
    AssertEquals('b,a,c', Names(L.Root));
    W := L.AddFolder(nil, 'Work');
    AssertTrue(L.Move(L.Root[1], W, -1));
    AssertEquals('b,c,Work', Names(L.Root));
    AssertEquals('a', Names(W));
    AssertTrue(W[0].Parent = W);
    Inner := L.AddFolder(W, 'Inner');
    AssertFalse('a folder into itself', L.Move(W, W, 0));
    AssertFalse('a folder into its own folder', L.Move(W, Inner, 0));
    AssertTrue(L.Move(Inner, nil, 0));
    AssertEquals('Inner,b,c,Work', Names(L.Root));
  finally
    L.Free;
  end;
end;

procedure TRepoListTest.TestRemove;
var
  L: TGittanRepoList;
  W: TGittanRepoEntry;
begin
  L := TGittanRepoList.Create('');
  try
    W := L.AddFolder(nil, 'Work');
    L.AddRepo(W, P('a'));
    L.AddRepo(nil, P('b'));
    L.Remove(W);
    AssertEquals('b', Names(L.Root));
    AssertNull('gone with its folder', L.Find(P('a')));
    AssertNotNull('can come back', L.AddRepo(nil, P('a')));
  finally
    L.Free;
  end;
end;

procedure TRepoListTest.TestRows;
var
  L: TGittanRepoList;
  W, Inner: TGittanRepoEntry;
  R: TGittanRepoRows;
begin
  L := TGittanRepoList.Create('');
  try
    W := L.AddFolder(nil, 'Work');
    L.AddRepo(W, P('a'));
    Inner := L.AddFolder(W, 'Inner');
    L.AddRepo(Inner, P('b'));
    L.AddRepo(nil, P('c'));
    R := L.Rows;
    AssertEquals(5, Length(R));
    AssertEquals('Inner', R[2].Entry.Caption);
    AssertEquals(1, R[2].Depth);
    AssertEquals('b', R[3].Entry.Caption);
    AssertEquals(2, R[3].Depth);
    AssertEquals(0, R[4].Depth);
    Inner.Collapsed := True;
    AssertEquals(4, Length(L.Rows));
    W.Collapsed := True;
    R := L.Rows;
    AssertEquals(2, Length(R));
    AssertEquals('c', R[1].Entry.Caption);
  finally
    L.Free;
  end;
end;

procedure TRepoListTest.TestRoundTrip;
var
  L, Back: TGittanRepoList;
  W: TGittanRepoEntry;
  FileName: string;
begin
  FileName := FDir + PathDelim + 'sub' + PathDelim + RepoListFileName;
  L := TGittanRepoList.Create(FileName);
  Back := TGittanRepoList.Create(FileName);
  try
    W := L.AddFolder(nil, 'Wörk "quoted"');
    W.Collapsed := True;
    L.AddRepo(W, P('a')).Name := 'Named';
    L.AddFolder(W, 'Empty');
    L.AddRepo(nil, P('b'));
    AssertTrue('saved, its folder made', L.Save);
    AssertFalse('no temporary file left', FileExists(FileName + '.tmp'));
    Back.Load;
    AssertEquals(L.ToJson, Back.ToJson);
    AssertEquals('Wörk "quoted"', Back.Root[0].Name);
    AssertTrue(Back.Root[0].Collapsed);
    AssertEquals('Named', Back.Root[0][0].Caption);
    AssertEquals(P('a'), Back.Root[0][0].Path);
    AssertTrue('in its folder', Back.Root[0][0].Parent = Back.Root[0]);
    AssertEquals('Empty', Back.Root[0][1].Name);
    AssertFalse(Back.Root[1].IsFolder);
    { Saved over. }
    L.Remove(L.Root[0]);
    AssertTrue(L.Save);
    Back.Load;
    AssertEquals('b', Names(Back.Root));
  finally
    Back.Free;
    L.Free;
  end;
end;

procedure TRepoListTest.TestDamagedFile;
var
  L: TGittanRepoList;
begin
  L := TGittanRepoList.Create('');
  try
    L.AddRepo(nil, P('a'));
    L.FromJson('{"items": [');
    AssertEquals('not JSON', 0, L.Root.Count);
    L.FromJson('[1, 2]');
    AssertEquals('not a list', 0, L.Root.Count);
    L.FromJson('{"items": [3, {"path": ""}, {"path": "/x"}, {"path": "/x"},' +
      ' {"folder": "F", "items": 7}]}');
    AssertEquals('what can be read of it', 'x,F', Names(L.Root));
  finally
    L.Free;
  end;
  L := TGittanRepoList.Create(FDir + PathDelim + 'missing.json');
  try
    L.Load;
    AssertEquals(0, L.Root.Count);
  finally
    L.Free;
  end;
end;

procedure TRepoListTest.TestFind;

  procedure MakeRepo(const ARel: string);
  begin
    ForceDirectories(FDir + PathDelim + ARel + PathDelim + '.git');
  end;

var
  Found: TStringArray;
  S: TStringList;
begin
  MakeRepo('one');
  MakeRepo('one' + PathDelim + 'nested');
  MakeRepo('group' + PathDelim + 'two');
  MakeRepo('a' + PathDelim + 'b' + PathDelim + 'c' + PathDelim + 'deep');
  MakeRepo('.hidden' + PathDelim + 'three');
  ForceDirectories(FDir + PathDelim + 'plain');
  { A worktree: .git is a file. }
  ForceDirectories(FDir + PathDelim + 'tree');
  S := TStringList.Create;
  try
    S.Add('gitdir: elsewhere');
    S.SaveToFile(FDir + PathDelim + 'tree' + PathDelim + '.git');
  finally
    S.Free;
  end;
  Found := FindRepositories(FDir);
  AssertEquals(3, Length(Found));
  AssertEquals(FDir + PathDelim + 'group' + PathDelim + 'two', Found[0]);
  AssertEquals(FDir + PathDelim + 'one', Found[1]);
  AssertEquals(FDir + PathDelim + 'tree', Found[2]);
  AssertEquals('deeper', 4, Length(FindRepositories(FDir, 4)));
  Found := FindRepositories(FDir + PathDelim + 'one');
  AssertEquals('the folder itself', 1, Length(Found));
  AssertEquals(FDir + PathDelim + 'one', Found[0]);
  AssertEquals(0, Length(FindRepositories(FDir + PathDelim + 'plain')));
  AssertEquals(0, Length(FindRepositories(FDir + PathDelim + 'nowhere')));
end;

initialization
  RegisterTest(TRepoListTest);
end.
