program Gittan;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, umain
  { you can add units after this };

{$R *.res}

begin
  Application.Title:='Git Tree Analyzer & Navigator';
  RequireDerivedFormResource:=True;
  Application.Scaled:=True;
  {$PUSH}{$WARN 5044 OFF}
  Application.MainFormOnTaskbar:=True;
  {$POP}
  Application.Initialize;
  {$IFDEF DARWIN}
  { The LCL sets MAINICON, cut for Windows and Linux to fill its canvas, as
    the Dock icon while the app runs. Clearing it keeps the bundle's .icns,
    inset to Apple's grid. }
  Application.Icon.Clear;
  {$ENDIF}
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.

