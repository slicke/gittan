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
  Classes, consoletestrunner,
  testworddiff, testgit, testsettings, testsymbols, testlexerpick,
  testsymbolindex, testsnapshots, testblame, testhistory, testsyntaxthemes,
  testgithub, testconflicts, testcli, testsymbolchanges,
  testcallers, testrepofiles, testdiscard, testkeep, testsubmodules, testupdate,
  testreviews, testgraph, testpofile, testcommitjob;

var
  App: TTestRunner;
begin
  {$IFDEF WINDOWS}
  { Strings are UTF-8, as LazUTF8 makes them in the app; without it a
    string reaches CreateProcessW and the file functions in the ANSI code
    page, and "Björn" becomes "BjÃ¶rn". }
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteRTLFileSystemCodePage(CP_UTF8);
  { Git for Windows sets core.autocrlf=true, so a checkout, revert or rebase
    writes CRLF and the tests' LF contents do not match; every git the
    tests start inherits this environment and keeps LF. }
  SetEnvironmentVariable('GIT_CONFIG_COUNT', '1');
  SetEnvironmentVariable('GIT_CONFIG_KEY_0', 'core.autocrlf');
  SetEnvironmentVariable('GIT_CONFIG_VALUE_0', 'false');
  {$ENDIF}
  App := TTestRunner.Create(nil);
  try
    App.Initialize;
    App.Title := 'Gittan tests';
    App.Run;
  finally
    App.Free;
  end;
end.
