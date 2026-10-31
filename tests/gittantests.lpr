program gittantests;

{** Unit tests for Gittan's non-visual units. Run with `make test`; the
  runner takes fpcunit's console options (--all, --format=plain, ...). }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF WINDOWS}
  Windows,
  {$ENDIF}
  Classes, SysUtils, consoletestrunner,
  testworddiff, testgit, testsettings, testsymbols, testlexerpick,
  testsymbolindex, testsnapshots, testblame, testhistory, testsyntaxthemes,
  testgithub, testconflicts, testcli, testsymbolchanges,
  testcallers, testrepofiles, testdiscard, testkeep, testleaveout, testsubmodules, testupdate,
  testreviews, testgraph, testpofile, testcommitjob, testrepoinfo, testrebase, testcommitstats, testwatch, testjob, testterminal, testhttp,
  testtextfile, testrepocommands, testsha256, testai, testagentcli, testopenai, testforge,
  testlfslocks, testworktrees, testpickaxe, testnavhistory, testtimelapse, testundo, testmerge, testtabnames;

{ Every git the tests start reads this file as the user's config and no
  system config, so what the developer has set (signed commits, a hooks
  path, core.autocrlf=true, which Git for Windows sets system-wide and
  which makes a checkout write CRLF) does not change what git does. The
  settings a parent process passes in the environment (GIT_CONFIG_COUNT
  with its keys and values, and GIT_CONFIG_PARAMETERS, which git -c
  sets for what it runs) come after the config files, so they are
  cleared too. }
function IsolateGitConfig: string;
var
  Lines: TStringList;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-tests-' +
    IntToStr(GetProcessID) + '.gitconfig';
  Lines := TStringList.Create;
  try
    Lines.Add('[user]');
    Lines.Add(#9'name = Gittan Test');
    Lines.Add(#9'email = test@example.invalid');
    Lines.Add('[core]');
    Lines.Add(#9'autocrlf = false');
    Lines.Add('[commit]');
    Lines.Add(#9'gpgsign = false');
    Lines.Add('[tag]');
    Lines.Add(#9'gpgsign = false');
    Lines.SaveToFile(Result);
  finally
    Lines.Free;
  end;
  SetTestVariable('GIT_CONFIG_GLOBAL', Result);
  SetTestVariable('GIT_CONFIG_NOSYSTEM', '1');
  SetTestVariable('GIT_CONFIG_COUNT', '0');
  SetTestVariable('GIT_CONFIG_PARAMETERS', '');
end;

var
  App: TTestRunner;
  GitConfig: string;
begin
  { Strings are UTF-8, as LazUTF8 makes them in the app; without it a
    string reaches CreateProcessW and the file functions on Windows in
    the ANSI code page, and "Björn" becomes "BjÃ¶rn", and on every
    platform one given to fpjson (a UTF8String) is converted from the
    system's page on the way, so "ändrad" comes back broken. }
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteRTLFileSystemCodePage(CP_UTF8);
  GitConfig := IsolateGitConfig;
  App := TTestRunner.Create(nil);
  try
    App.Initialize;
    App.Title := 'Gittan tests';
    App.Run;
  finally
    App.Free;
    DeleteFile(GitConfig);
  end;
end.
