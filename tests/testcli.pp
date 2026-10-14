unit testcli;

{** Tests of gittan.cli: the scripts of the gittan command and the PATH
  check. Installing is not tested; it writes outside the repository. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.cli;

type
  TCliTest = class(TTestCase)
  published
    procedure TestShellQuote;
    procedure TestMacScript;
    procedure TestUnixScript;
    procedure TestWindowsScript;
    procedure TestPathListHas;
    procedure TestPathListRemove;
    procedure TestIsGittanScript;
  end;

implementation

procedure TCliTest.TestShellQuote;
begin
  AssertEquals('''/opt/Gittan''', ShellQuote('/opt/Gittan'));
  AssertEquals('''it''\''''s''', ShellQuote('it''s'));
end;

procedure TCliTest.TestMacScript;
var
  S: string;
begin
  S := MacCliScript('/Applications/Gittan.app');
  AssertTrue(Pos('#!/bin/sh', S) = 1);
  AssertTrue('defaults to the current folder', Pos('set -- "$PWD"', S) > 0);
  AssertTrue(Pos('exec open -a ''/Applications/Gittan.app'' "$@"', S) > 0);
end;

procedure TCliTest.TestUnixScript;
var
  S: string;
begin
  S := UnixCliScript('/home/me/My Apps/Gittan');
  AssertTrue(Pos('#!/bin/sh', S) = 1);
  AssertTrue(Pos('nohup ''/home/me/My Apps/Gittan'' "$@" >/dev/null 2>&1 &', S) > 0);
end;

procedure TCliTest.TestWindowsScript;
var
  S: string;
begin
  S := WindowsCliScript('C:\Program Files (x86)\Gittan\100%\Gittan.exe');
  AssertTrue(Pos('@echo off'#13#10, S) = 1);
  AssertTrue('a percent sign is doubled',
    Pos('start "" "C:\Program Files (x86)\Gittan\100%%\Gittan.exe" %*', S) > 0);
  AssertTrue('defaults to the current folder', Pos('Gittan.exe" "%CD%"', S) > 0);
  AssertTrue('no bare line feed', Pos(#10, StringReplace(S, #13#10, '', [rfReplaceAll])) = 0);
end;

procedure TCliTest.TestPathListHas;
begin
  AssertTrue(PathListHas('/usr/bin:/home/me/.local/bin', '/home/me/.local/bin', ':', False));
  AssertTrue('trailing separator', PathListHas('/usr/bin:/home/me/.local/bin/',
    '/home/me/.local/bin', ':', False));
  AssertFalse(PathListHas('/usr/bin:/home/me/.local/binx', '/home/me/.local/bin', ':', False));
  AssertFalse('case counts', PathListHas('/Usr/Bin', '/usr/bin', ':', False));
  AssertTrue('case ignored', PathListHas('/Usr/Bin;/x', '/usr/bin', ';', True));
  AssertFalse(PathListHas('', '/usr/bin', ':', False));
end;

procedure TCliTest.TestPathListRemove;
begin
  AssertEquals('C:\a;D:\b', PathListRemove('C:\a;C:\Users\me\Gittan\bin\;D:\b',
    'c:\users\me\gittan\bin', ';', True));
  AssertEquals('every copy goes', '/a', PathListRemove('/x:/a:/x', '/x', ':', False));
  AssertEquals('case counts', '/X:/a', PathListRemove('/X:/a', '/x', ':', False));
  AssertEquals('', PathListRemove('/x', '/x', ':', False));
end;

procedure TCliTest.TestIsGittanScript;
var
  F: string;

  procedure Put(const AText: string);
  var
    L: TStringList;
  begin
    L := TStringList.Create;
    try
      L.Text := AText;
      L.SaveToFile(F);
    finally
      L.Free;
    end;
  end;

begin
  F := GetTempFileName(GetTempDir, 'gittancli');
  try
    Put(UnixCliScript('/opt/Gittan'));
    AssertTrue(IsGittanScript(F));
    Put(WindowsCliScript('C:\Gittan.exe'));
    AssertTrue(IsGittanScript(F));
    Put('#!/bin/sh' + LineEnding + 'exec /usr/bin/other "$@"');
    AssertFalse('someone else''s gittan', IsGittanScript(F));
  finally
    DeleteFile(F);
  end;
  AssertFalse('missing', IsGittanScript(F));
end;

initialization
  RegisterTest(TCliTest);
end.
