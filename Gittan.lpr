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
  {$IFDEF LCLWin32}
  uDarkStyleParams, uMetaDarkStyle, uDarkStyleSchemes,
  {$ENDIF}
  Forms, uwindow,
  { The forges and the AI agents, which register themselves as they
    load. }
  gittan.github, gittan.agentcli, gittan.openai

  { you can add units after this };

{$R *.res}

begin
  Application.Title:='Git Tree Analyzer & Navigator';
  RequireDerivedFormResource:=True;
  Application.Scaled:=True;
  {$PUSH}{$WARN 5044 OFF}
  Application.MainFormOnTaskbar:=True;
  {$POP}
  {$IFDEF LCLWin32}
  { MetaDarkStyle turns the LCL's native controls, menus, scroll bars and
    dialogs dark when Windows is in dark mode at startup; it does not
    follow a change while Gittan runs (see IsDarkMode). }
  PreferredAppMode := pamAllowDark;
  ApplyMetaDarkStyle(DefaultDark);
  {$ENDIF}
  Application.Initialize;
  {$IFDEF DARWIN}
  { The LCL sets MAINICON, cut for Windows and Linux to fill its canvas, as
    the Dock icon while the app runs. Clearing it keeps the bundle's .icns,
    inset to Apple's grid. }
  Application.Icon.Clear;
  {$ENDIF}
  Application.CreateForm(TGittanWindow, GittanWindow);
  Application.Run;
end.

