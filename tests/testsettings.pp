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
    procedure TestQuotesAndSpaces;
    procedure TestRecentList;
    procedure TestDamagedFileGivesDefaults;
    procedure TestOldDefaultFont;
    procedure TestDefaultFontSize;
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
    AssertFalse(S.MarkdownPreview);
    AssertEquals(0, S.Recent.Count);
    AssertEquals(0, S.UpdateSnoozedUntil, 0);
    AssertTrue(S.CommitOpen);
    AssertEquals('', S.CommitDraft);
    AssertEquals('no tab width picked', 0, S.TabSize);
    AssertEquals('', S.GitPath);
    AssertEquals('', S.GhPath);
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
    S.RepoFilesOpen := True;
    S.SubmodulesOpen := False;
    S.CommitOpen := False;
    S.CommitDraft := 'Subject = x'#10#10'C:\new\nope\\'#10;
    S.CommitDraftRepo := '/tmp/a';
    S.FontName := 'Menlo';
    S.FontSize := 13;
    S.Zoom := 120;
    S.WordWrap := True;
    S.OnlyChanges := True;
    S.ContextLines := 5;
    S.SideBySide := True;
    S.MarkdownPreview := True;
    S.IgnoreWhitespace := True;
    S.EditorCommand := 'code -g';
    S.TabSize := 4;
    S.GitPath := '/opt/homebrew/bin/git';
    S.GhPath := 'C:\Program Files\GitHub CLI\gh.exe';
    S.SyntaxTheme := 'Delphi';
    S.UpdateSnoozedUntil := EncodeDate(2026, 10, 29) + 0.5;
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
    AssertTrue(S.RepoFilesOpen);
    AssertFalse(S.SubmodulesOpen);
    AssertFalse(S.CommitOpen);
    AssertEquals('Subject = x'#10#10'C:\new\nope\\'#10, S.CommitDraft);
    AssertEquals('/tmp/a', S.CommitDraftRepo);
    AssertEquals('Menlo', S.FontName);
    AssertEquals(13, S.FontSize);
    AssertEquals(120, S.Zoom);
    AssertTrue(S.WordWrap);
    AssertTrue(S.OnlyChanges);
    AssertEquals(5, S.ContextLines);
    AssertTrue(S.SideBySide);
    AssertTrue(S.MarkdownPreview);
    AssertTrue(S.IgnoreWhitespace);
    AssertEquals('code -g', S.EditorCommand);
    AssertEquals(4, S.TabSize);
    AssertEquals('/opt/homebrew/bin/git', S.GitPath);
    AssertEquals('C:\Program Files\GitHub CLI\gh.exe', S.GhPath);
    AssertEquals('Delphi', S.SyntaxTheme);
    AssertEquals('the day, without the time', EncodeDate(2026, 10, 29),
      S.UpdateSnoozedUntil, 0);
    AssertEquals(2, S.Recent.Count);
    AssertEquals('newest first', '/tmp/b', S.Recent[0]);
    AssertEquals('/tmp/a', S.Recent[1]);
  finally
    S.Free;
  end;
end;

procedure TSettingsTest.TestQuotesAndSpaces;
var
  S: TGittanSettings;
begin
  S := TGittanSettings.Create(FFileName);
  try
    S.EditorCommand := '"C:\Program Files\Code\Code.exe"';
    S.TerminalCommand := '"wt.exe" -d';
    S.CommitDraft := '"Quoted subject"';
    S.CommitDraftRepo := '  /tmp/a ';
    S.GitPath := '"';
    S.GhPath := '""';
    S.FontName := 'Menlo';
    S.Save;
  finally
    S.Free;
  end;
  S := TGittanSettings.Create(FFileName);
  try
    S.Load;
    AssertEquals('"C:\Program Files\Code\Code.exe"', S.EditorCommand);
    AssertEquals('"wt.exe" -d', S.TerminalCommand);
    AssertEquals('"Quoted subject"', S.CommitDraft);
    AssertEquals('  /tmp/a ', S.CommitDraftRepo);
    AssertEquals('"', S.GitPath);
    AssertEquals('""', S.GhPath);
    AssertEquals('Menlo', S.FontName);
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

procedure TSettingsTest.TestOldDefaultFont;
var
  S: TGittanSettings;
  F: TStringList;
begin
  F := TStringList.Create;
  try
    F.Text := '[View]'#10'FontName=Courier New'#10'FontSize=9'#10;
    F.SaveToFile(FFileName);
  finally
    F.Free;
  end;
  S := TGittanSettings.Create(FFileName);
  try
    S.Load;
    AssertEquals('the old built-in font is no choice', '', S.FontName);
    AssertEquals(0, S.FontSize);
    S.FontName := 'Courier New';
    S.FontSize := 10;
    S.Save;
    S.Load;
    AssertEquals('another size is a choice', 'Courier New', S.FontName);
    AssertEquals(10, S.FontSize);
  finally
    S.Free;
  end;
end;

procedure TSettingsTest.TestDefaultFontSize;
begin
  AssertTrue(DefaultFontSize(1080) >= 9);
  AssertEquals('a large screen gets a size up', DefaultFontSize(1080) + 1,
    DefaultFontSize(1440));
  AssertEquals(DefaultFontSize(1080) + 2, DefaultFontSize(2160));
end;

initialization
  RegisterTest(TSettingsTest);
end.
