unit testsettings;

{** Tests of gittan.settings: the ini file round trip and the recent
  list. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, fpcunit, testregistry, gittan.settings,
  { GitHub registers itself, so the settings keep its section. }
  gittan.github{$IFDEF UNIX}, BaseUnix{$ENDIF};

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
    procedure TestTabs;
    procedure TestDamagedFileGivesDefaults;
    procedure TestOldDefaultFont;
    procedure TestDefaultFontSize;
    procedure TestTrust;
    procedure TestOldGhPath;
    procedure TestOldForgeSwitch;
  end;

implementation

{$IFDEF UNIX}
function FileModeOf(const AName: string): integer;
var
  Info: Stat;
begin
  if FpStat(AName, Info) = 0 then
    Result := Info.st_mode
  else
    Result := -1;
end;
{$ENDIF}

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
    AssertEquals('', S.ForgeCliPath('GitHub'));
    AssertTrue('the hosting features start on', S.HostingEnabled);
    AssertTrue('the background fetch starts on', S.AutoFetch);
    AssertEquals(DefaultAutoFetchMinutes, S.AutoFetchMinutes);
    AssertFalse(S.HideWithoutFeedback);
    AssertFalse(S.OnlyNeedsAttention);
    AssertFalse(S.HideDrafts);
    AssertFalse(S.OnlyAskedOfMe);
    AssertFalse(S.HideReviewDrafts);
    AssertFalse(S.OnlyStale);
    AssertFalse('the AI features start off', S.AIEnabled);
    AssertEquals('', S.ClaudePath);
    AssertEquals('', S.ClaudeModel);
    AssertEquals('', S.AIAgent);
    AssertEquals('', S.CopilotPath);
    AssertEquals('', S.OpenAIUrl);
    AssertEquals('', S.OpenAIKey);
    AssertEquals('', S.OpenAIModel);
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
    S.SetForgeCliPath('GitHub', 'C:\Program Files\GitHub CLI\gh.exe');
    S.HostingEnabled := False;
    S.AutoFetch := False;
    S.AutoFetchMinutes := 30;
    S.HideWithoutFeedback := True;
    S.OnlyNeedsAttention := True;
    S.HideDrafts := True;
    S.OnlyAskedOfMe := True;
    S.HideReviewDrafts := True;
    S.OnlyStale := True;
    S.SyntaxTheme := 'Delphi';
    S.AIEnabled := True;
    S.ClaudePath := '/Users/me/.local/bin/claude';
    S.ClaudeModel := 'haiku';
    S.AIAgent := 'copilot';
    S.CopilotPath := '/opt/homebrew/bin/copilot';
    S.CopilotModel := 'auto';
    S.OpenAIUrl := 'https://openrouter.ai/api/v1';
    S.OpenAIKey := 'sk-or-v1-abc';
    S.OpenAIModel := 'openai/gpt-4o-mini';
    S.UpdateSnoozedUntil := EncodeDate(2026, 10, 29) + 0.5;
    S.AddRecent('/tmp/a');
    S.AddRecent('/tmp/b');
    S.AddPaletteRecent('File: Push');
    S.AddPaletteRecent('View: Blame');
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
    AssertEquals('C:\Program Files\GitHub CLI\gh.exe', S.ForgeCliPath('GitHub'));
    AssertFalse(S.HostingEnabled);
    AssertFalse(S.AutoFetch);
    AssertEquals(30, S.AutoFetchMinutes);
    AssertTrue(S.HideWithoutFeedback);
    AssertTrue(S.OnlyNeedsAttention);
    AssertTrue(S.HideDrafts);
    AssertTrue(S.OnlyAskedOfMe);
    AssertTrue(S.HideReviewDrafts);
    AssertTrue(S.OnlyStale);
    AssertEquals('Delphi', S.SyntaxTheme);
    AssertTrue(S.AIEnabled);
    AssertEquals('/Users/me/.local/bin/claude', S.ClaudePath);
    AssertEquals('haiku', S.ClaudeModel);
    AssertEquals('copilot', S.AIAgent);
    AssertEquals('/opt/homebrew/bin/copilot', S.CopilotPath);
    AssertEquals('auto', S.CopilotModel);
    AssertEquals('https://openrouter.ai/api/v1', S.OpenAIUrl);
    AssertEquals('sk-or-v1-abc', S.OpenAIKey);
    AssertEquals('openai/gpt-4o-mini', S.OpenAIModel);
    {$IFDEF UNIX}
    AssertEquals('with a key the file is its owner''s alone', &600,
      FileModeOf(FFileName) and &777);
    {$ENDIF}
    AssertEquals('the day, without the time', EncodeDate(2026, 10, 29),
      S.UpdateSnoozedUntil, 0);
    AssertEquals(2, S.Recent.Count);
    AssertEquals('newest first', '/tmp/b', S.Recent[0]);
    AssertEquals('/tmp/a', S.Recent[1]);
    AssertEquals(2, S.PaletteRecent.Count);
    AssertEquals('View: Blame', S.PaletteRecent[0]);
    AssertEquals('File: Push', S.PaletteRecent[1]);
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
    S.SetForgeCliPath('GitHub', '""');
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
    AssertEquals('""', S.ForgeCliPath('GitHub'));
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
    for i := 1 to MaxPaletteRecent + 2 do
      S.AddPaletteRecent('Action ' + IntToStr(i));
    S.AddPaletteRecent('Action 5');
    AssertEquals('capped', MaxPaletteRecent, S.PaletteRecent.Count);
    AssertEquals('Action 5', S.PaletteRecent[0]);
    AssertEquals('Action ' + IntToStr(MaxPaletteRecent + 2), S.PaletteRecent[1]);
  finally
    S.Free;
  end;
end;

procedure TSettingsTest.TestTabs;
var
  S: TGittanSettings;
begin
  S := TGittanSettings.Create(FFileName);
  try
    AssertEquals('none by default', 0, S.Tabs.Count);
    S.Tabs.Add('/repo/a');
    S.Tabs.Add('/repo/b c');
    S.Tabs.Add('/repo/d');
    S.ActiveTab := 1;
    S.Save;
  finally
    S.Free;
  end;
  S := TGittanSettings.Create(FFileName);
  try
    S.Load;
    AssertEquals(3, S.Tabs.Count);
    AssertEquals('/repo/b c', S.Tabs[1]);
    AssertEquals(1, S.ActiveTab);
    S.Tabs.Clear;
    S.Tabs.Add('/repo/a');
    S.ActiveTab := 5;
    S.Save;
  finally
    S.Free;
  end;
  S := TGittanSettings.Create(FFileName);
  try
    S.Load;
    AssertEquals('fewer tabs drop the rest', 1, S.Tabs.Count);
    AssertEquals('an active tab past the end is the first', 0, S.ActiveTab);
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

procedure TSettingsTest.TestTrust;
var
  S: TGittanSettings;
begin
  S := TGittanSettings.Create(FFileName);
  try
    AssertTrue('no file needs no trust', S.CommandsTrusted('/tmp/a', ''));
    AssertFalse(S.CommandsTrusted('/tmp/a', 'abc'));
    S.TrustCommands('/tmp/a', 'abc');
    AssertTrue(S.CommandsTrusted('/tmp/a', 'abc'));
    AssertFalse('another text asks again', S.CommandsTrusted('/tmp/a', 'def'));
    AssertFalse('another root', S.CommandsTrusted('/tmp/b', 'abc'));
    S.TrustCommands('/tmp/a', 'def');
    S.TrustCommands('/tmp/b', '');
    S.Save;
  finally
    S.Free;
  end;
  S := TGittanSettings.Create(FFileName);
  try
    S.Load;
    AssertTrue('the newest hash is kept', S.CommandsTrusted('/tmp/a', 'def'));
    AssertFalse(S.CommandsTrusted('/tmp/a', 'abc'));
    AssertFalse('an empty hash trusts nothing', S.CommandsTrusted('/tmp/b', 'x'));
  finally
    S.Free;
  end;
end;

{ gh's path was kept in Tools with git's; it is read from there and
  moved to the GitHub section. }
{ The GitHub features had a switch of their own; off, it turns the
  hosting features off, and moves to the Hosting section. }
procedure TSettingsTest.TestOldForgeSwitch;
var
  S: TGittanSettings;
  Ini: TStringList;
  Cfg: TIniFile;
begin
  Ini := TStringList.Create;
  try
    Ini.Add('[GitHub]');
    Ini.Add('Enabled=0');
    Ini.Add('Cli=/opt/gh/bin/gh');
    Ini.SaveToFile(FFileName);
    S := TGittanSettings.Create(FFileName);
    try
      S.Load;
      AssertFalse(S.HostingEnabled);
      AssertEquals('/opt/gh/bin/gh', S.ForgeCliPath('GitHub'));
      S.Save;
    finally
      S.Free;
    end;
    Cfg := TIniFile.Create(FFileName);
    try
      AssertFalse('the switch is under Hosting', Cfg.ReadBool('Hosting', 'Enabled', True));
      AssertEquals('the old switch is gone', 'none', Cfg.ReadString('GitHub', 'Enabled', 'none'));
    finally
      Cfg.Free;
    end;
  finally
    Ini.Free;
  end;
end;

procedure TSettingsTest.TestOldGhPath;
var
  S: TGittanSettings;
  Ini: TStringList;
begin
  Ini := TStringList.Create;
  try
    Ini.Add('[Tools]');
    Ini.Add('Gh=/opt/gh/bin/gh');
    Ini.SaveToFile(FFileName);
    S := TGittanSettings.Create(FFileName);
    try
      S.Load;
      AssertEquals('/opt/gh/bin/gh', S.ForgeCliPath('GitHub'));
      AssertTrue(S.HostingEnabled);
      S.Save;
    finally
      S.Free;
    end;
    Ini.LoadFromFile(FFileName);
    AssertEquals('the old key is gone', -1, Ini.IndexOf('Gh=/opt/gh/bin/gh'));
    AssertTrue('the path is under GitHub', Ini.IndexOf('Cli=/opt/gh/bin/gh') >= 0);
  finally
    Ini.Free;
  end;
end;

initialization
  RegisterTest(TSettingsTest);
end.
