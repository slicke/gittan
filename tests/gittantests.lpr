program gittantests;

{** Unit tests for Gittan's non-visual units. Run with `make test`; the
  runner takes fpcunit's console options (--all, --format=plain, ...). }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, consoletestrunner,
  testworddiff, testgit, testsettings, testsymbols, testlexerpick,
  testsymbolindex, testsnapshots, testblame, testhistory, testsyntaxthemes,
  testgithub, testconflicts, testcli, testsymbolchanges,
  testcallers, testrepofiles, testdiscard, testsubmodules, testupdate,
  testreviews, testgraph;

var
  App: TTestRunner;
begin
  {$IFDEF WINDOWS}
  { Strings are UTF-8, as LazUTF8 makes them in the app; without it a
    string reaches CreateProcessW and the file functions in the ANSI code
    page, and "Björn" becomes "BjÃ¶rn". }
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteRTLFileSystemCodePage(CP_UTF8);
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
