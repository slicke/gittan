unit testlfslocks;

{** Tests of gittan.lfslocks: git-lfs's lists of locks read, with and
  without --verify, the clone's own marked by id and path, and a lock
  asked of a repository with no LFS server failing with git-lfs's
  reason, while its list is empty and a read given up fails with none. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, fpcunit, testregistry, gittan.git, gittan.lfslocks, testhelpers;

type
  TLfsLocksTest = class(TTestCase)
  private
    function Cancel: boolean;
  published
    procedure TestParse;
    procedure TestMarkLocal;
    procedure TestNoServer;
  end;

implementation

procedure TLfsLocksTest.TestParse;
var
  Locks: TGittanLfsLocks;
  Verified: boolean;
begin
  AssertTrue(ParseLfsLocks('{"ours":[{"id":"3","path":"art/a.psd","owner":{"name":"Sam"},' +
    '"locked_at":"2026-10-27T09:30:00Z"}],"theirs":[{"id":"7","path":"b.psd",' +
    '"owner":{"name":"Maja"},"locked_at":"2026-10-26T08:00:00+02:00"}]}', Locks, Verified));
  AssertTrue(Verified);
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
    Locks, Verified));
  AssertFalse(Verified);
  AssertEquals(1, Length(Locks));
  AssertFalse(Locks[0].Ours);
  AssertEquals(0, Locks[0].LockedAt, 0);
  AssertTrue(ParseLfsLocks('[]', Locks));
  AssertEquals(0, Length(Locks));
  AssertFalse(ParseLfsLocks('Not in a Git repository.', Locks));
  AssertFalse(ParseLfsLocks('"text"', Locks));
end;

function TLfsLocksTest.Cancel: boolean;
begin
  Result := True;
end;

{ A lock is the clone's own when --local has it with its id on its
  path; the same path under another id was taken by someone else after
  the clone's own went. }
procedure TLfsLocksTest.TestMarkLocal;
var
  Locks, Local: TGittanLfsLocks;
begin
  AssertTrue(ParseLfsLocks('[{"id":"1","path":"a.psd"},{"id":"9","path":"b.psd"},' +
    '{"id":"5","path":"c.psd"}]', Locks));
  AssertTrue(ParseLfsLocks('[{"id":"1","path":"a.psd"},{"id":"2","path":"b.psd"},' +
    '{"id":"5","path":"d.psd"}]', Local));
  MarkLocalLocks(Locks, Local);
  AssertTrue(Locks[0].Ours);
  AssertFalse('the path taken again', Locks[1].Ours);
  AssertFalse('the id on another path', Locks[2].Ours);
  MarkLocalLocks(Locks, nil);
  AssertFalse(Locks[0].Ours);
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
    AssertFalse(ReadLfsLocks(Dir, Locks, Err, @Cancel));
    AssertEquals('', Err);
  finally
    Repo.Free;
    RemoveTree(Dir);
  end;
end;

initialization
  RegisterTest(TLfsLocksTest);
end.
