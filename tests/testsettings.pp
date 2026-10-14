unit testsettings;

{** Tests of gittan.settings: the ini file round trip and the recent
  list. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.settings;

type
  TSettingsTest = class(TTestCase)
  private
    FFileName: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDefaults;
    procedure TestRoundTrip;
    procedure TestRecentList;
    procedure TestDamagedFileGivesDefaults;
  end;

implementation

procedure TSettingsTest.SetUp;
begin
  FFileName := GetTempFileName('', 'gittan-settings-');
end;

procedure TSettingsTest.TearDown;
begin
  if FileExists(FFileName) then
    DeleteFile(FFileName);
end;

procedure TSettingsTest.TestDefaults;
var
  S: TGittanSettings;
begin
  S := TGittanSettings.Create(FFileName);
  try
    AssertEquals(FFileName, S.FileName);
    S.Load;
    AssertEquals(3, S.ContextLines);
    AssertEquals(0, S.Width);
    AssertFalse(S.SideBySide);
    AssertEquals(0, S.Recent.Count);
  finally
    S.Free;
  end;
end;

procedure TSettingsTest.TestRoundTrip;
var
  S: TGittanSettings;
begin
  S := TGittanSettings.Create(FFileName);
  try
    S.Left := 10;
    S.Top := 20;
    S.Width := 800;
    S.Height := 600;
    S.Maximized := True;
    S.TreeWidth := 240;
    S.FontName := 'Menlo';
    S.FontSize := 13;
    S.Zoom := 120;
    S.WordWrap := True;
    S.OnlyChanges := True;
    S.ContextLines := 5;
    S.SideBySide := True;
    S.IgnoreWhitespace := True;
    S.EditorCommand := 'code -g';
    S.SyntaxTheme := 'Delphi';
    S.AddRecent('/tmp/a');
    S.AddRecent('/tmp/b');
    S.Save;
  finally
    S.Free;
  end;
  S := TGittanSettings.Create(FFileName);
  try
    S.Load;
    AssertEquals(10, S.Left);
    AssertEquals(20, S.Top);
    AssertEquals(800, S.Width);
    AssertEquals(600, S.Height);
    AssertTrue(S.Maximized);
    AssertEquals(240, S.TreeWidth);
    AssertEquals('Menlo', S.FontName);
    AssertEquals(13, S.FontSize);
    AssertEquals(120, S.Zoom);
    AssertTrue(S.WordWrap);
    AssertTrue(S.OnlyChanges);
    AssertEquals(5, S.ContextLines);
    AssertTrue(S.SideBySide);
    AssertTrue(S.IgnoreWhitespace);
    AssertEquals('code -g', S.EditorCommand);
    AssertEquals('Delphi', S.SyntaxTheme);
    AssertEquals(2, S.Recent.Count);
    AssertEquals('newest first', '/tmp/b', S.Recent[0]);
    AssertEquals('/tmp/a', S.Recent[1]);
  finally
    S.Free;
  end;
end;

procedure TSettingsTest.TestRecentList;
var
  S: TGittanSettings;
  i: integer;
begin
  S := TGittanSettings.Create(FFileName);
  try
    for i := 1 to MaxRecent + 3 do
      S.AddRecent('/repo/' + IntToStr(i));
    AssertEquals('capped', MaxRecent, S.Recent.Count);
    AssertEquals('/repo/' + IntToStr(MaxRecent + 3), S.Recent[0]);
    S.AddRecent('/repo/' + IntToStr(MaxRecent));
    AssertEquals('a repeat moves to the front without a duplicate',
      MaxRecent, S.Recent.Count);
    AssertEquals('/repo/' + IntToStr(MaxRecent), S.Recent[0]);
    AssertEquals('/repo/' + IntToStr(MaxRecent + 3), S.Recent[1]);
    AssertEquals(-1, S.Recent.IndexOf('/repo/3'));
  finally
    S.Free;
  end;
end;

procedure TSettingsTest.TestDamagedFileGivesDefaults;
var
  S: TGittanSettings;
  F: TStringList;
begin
  F := TStringList.Create;
  try
    F.Text := '[View]'#10'ContextLines=lots'#10'[Window'#10'Width=';
    F.SaveToFile(FFileName);
  finally
    F.Free;
  end;
  S := TGittanSettings.Create(FFileName);
  try
    S.Load;
    AssertEquals(3, S.ContextLines);
    AssertEquals(0, S.Width);
  finally
    S.Free;
  end;
end;

initialization
  RegisterTest(TSettingsTest);
end.
