unit testlfslocks;

{** Tests of gittan.lfslocks: git-lfs's lists of locks read, with and
  without --verify, and a lock asked of a repository with no LFS server
  failing with git-lfs's reason, while its list is empty. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, fpcunit, testregistry, gittan.git, gittan.lfslocks;

type
  TLfsLocksTest = class(TTestCase)
  published
    procedure TestParse;
    procedure TestNoServer;
  end;

implementation

procedure RemoveTree(const ADir: string);
var
  Info: TSearchRec;
begin
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, Info) = 0 then
  try
    repeat
      if (Info.Name = '.') or (Info.Name = '..') then
        Continue;
      if Info.Attr and faDirectory <> 0 then
        RemoveTree(IncludeTrailingPathDelimiter(ADir) + Info.Name)
      else
        DeleteFile(IncludeTrailingPathDelimiter(ADir) + Info.Name);
    until FindNext(Info) <> 0;
  finally
    FindClose(Info);
  end;
  RemoveDir(ADir);
end;

procedure TLfsLocksTest.TestParse;
var
  Locks: TGittanLfsLocks;
begin
  AssertTrue(ParseLfsLocks('{"ours":[{"id":"3","path":"art/a.psd","owner":{"name":"Sam"},' +
    '"locked_at":"2026-10-27T09:30:00Z"}],"theirs":[{"id":"7","path":"b.psd",' +
    '"owner":{"name":"Maja"},"locked_at":"2026-10-26T08:00:00+02:00"}]}', Locks));
  AssertEquals(2, Length(Locks));
  AssertEquals('3', Locks[0].Id);
  AssertEquals('art/a.psd', Locks[0].Path);
  AssertEquals('Sam', Locks[0].Owner);
  AssertTrue(Locks[0].Ours);
  AssertEquals('2026-10-27 09:30', FormatDateTime('yyyy-mm-dd hh:nn', Locks[0].LockedAt));
  AssertFalse(Locks[1].Ours);
  AssertEquals('Maja', Locks[1].Owner);
  { UTC, as the first. }
  AssertEquals('2026-10-26 06:00', FormatDateTime('yyyy-mm-dd hh:nn', Locks[1].LockedAt));
  AssertEquals(1, LfsLockIndex(Locks, 'b.psd'));
  AssertEquals(-1, LfsLockIndex(Locks, 'B.psd'));
  { The plain list knows no owner of its own; a lock without a path is
    left out, a missing date is 0. }
  AssertTrue(ParseLfsLocks('[{"id":"1","path":"c.bin","owner":{"name":"Inés"}},{"id":"2"}]',
    Locks));
  AssertEquals(1, Length(Locks));
  AssertFalse(Locks[0].Ours);
  AssertEquals(0, Locks[0].LockedAt, 0);
  AssertTrue(ParseLfsLocks('[]', Locks));
  AssertEquals(0, Length(Locks));
  AssertFalse(ParseLfsLocks('Not in a Git repository.', Locks));
  AssertFalse(ParseLfsLocks('"text"', Locks));
end;

procedure TLfsLocksTest.TestNoServer;
var
  Dir, Output, Err: string;
  Repo: TGittanRepo;
  Locks: TGittanLfsLocks;
begin
  if FindTool('git-lfs') = '' then
    Exit;
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-lfslocks-' + IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(Dir);
  Repo := TGittanRepo.Create;
  try
    AssertTrue(RunGitIn(Dir, ['init', '-q'], Output, Err));
    AssertTrue(Repo.Open(Dir));
    { No remote, so no LFS server. }
    AssertFalse(Repo.LfsLock('a.psd'));
    AssertTrue(Repo.Error <> '');
    AssertFalse(Repo.LfsUnlock('a.psd', True));
    { git-lfs lists no locks then, rather than fail. }
    AssertTrue(ReadLfsLocks(Dir, Locks, Err));
    AssertEquals(0, Length(Locks));
  finally
    Repo.Free;
    RemoveTree(Dir);
  end;
end;

initialization
  RegisterTest(TLfsLocksTest);
end.
