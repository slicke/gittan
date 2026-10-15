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
  testreviews;

var
  App: TTestRunner;
begin
  App := TTestRunner.Create(nil);
  try
    App.Initialize;
    App.Title := 'Gittan tests';
    App.Run;
  finally
    App.Free;
  end;
end.
