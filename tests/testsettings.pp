unit testsettings;

{** Tests of gittan.settings: the round trip through settings.json and
  state.json, the keys kept that Gittan does not know, the old ini file
  found, and the recent list. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, fpjson, jsonparser, gittan.settings,
  gittan.textfile, testhelpers{$IFDEF UNIX}, BaseUnix{$ENDIF};

type
  TSettingsTest = class(TTestCase)
  private
    FDir: string;
    procedure Put(const AName, AText: string);
    function ReadJson(const AName: string): TJSONObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDefaults;
    procedure TestRoundTrip;
    procedure TestStringsAsTheyAre;
    procedure TestRecentList;
    procedure TestSaveRecent;
    procedure TestTabs;
    procedure TestBatchRepos;
    procedure TestCoAuthors;
    procedure TestBatchOperationIndex;
    procedure TestDamagedFileGivesDefaults;
    procedure TestWrongTypesSaved;
    procedure TestDraftUnknownKept;
    procedure TestExtValueList;
    procedure TestDefaultFontSize;
    procedure TestTrust;
    procedure TestProjectKinds;
    procedure TestForgeValues;
    procedure TestExtensions;
    procedure TestLayout;
    procedure TestUnknownKeysKept;
    procedure TestOldIni;
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
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-settings-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(MaxInt));
  ForceDirectories(FDir);
end;

procedure TSettingsTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TSettingsTest.Put(const AName, AText: string);
begin
  AssertTrue(WriteFileReplacing(IncludeTrailingPathDelimiter(FDir) + AName, AText));
end;

function TSettingsTest.ReadJson(const AName: string): TJSONObject;
var
  Data: TJSONData;
begin
  Data := GetJSON(ReadFileBytes(IncludeTrailingPathDelimiter(FDir) + AName));
  AssertTrue(AName + ' is an object', Data is TJSONObject);
  Result := TJSONObject(Data);
end;

procedure TSettingsTest.TestDefaults;
var
  S: TGittanSettings;
begin
  S := TGittanSettings.Create(FDir);
  try
    AssertEquals(FDir, S.Dir);
    AssertEquals(IncludeTrailingPathDelimiter(FDir) + 'settings.json', S.SettingsFile);
    AssertEquals(IncludeTrailingPathDelimiter(FDir) + 'state.json', S.StateFile);
    S.Load;
    AssertFalse('no old ini', S.OldIniFound);
    AssertTrue(S.ReviewComments);
    AssertTrue(S.Translations);
    AssertEquals(3, S.ContextLines);
    AssertTrue('the unchanged lines start hidden', S.OnlyChanges);
    AssertEquals(0, S.Width);
    AssertFalse(S.SideBySide);
    AssertFalse(S.MarkdownPreview);
    AssertEquals(0, S.Recent.Count);
    AssertEquals(0, S.UpdateSnoozedUntil, 0);
    AssertTrue(S.CommitOpen);
    AssertTrue('the sidebar''s rows start shown', S.NavOpen);
    AssertFalse('all of the graph''s parents', S.GraphFirstParent);
    AssertFalse('the graph''s merges', S.GraphNoMerges);
    AssertEquals('', S.CommitDraft);
    AssertEquals('no tab width picked', 0, S.TabSize);
    AssertEquals('', S.GitPath);
    AssertEquals('', S.ForgeCliPath('GitHub'));
    AssertTrue('the hosting features start on', S.HostingEnabled);
    AssertTrue('the background fetch starts on', S.AutoFetch);
    AssertEquals(DefaultAutoFetchMinutes, S.AutoFetchMinutes);
    AssertEquals('no filters on', '', S.ForgeValue('GitHub', 'MineFilters'));
    AssertEquals('', S.ForgeValue('GitHub', 'ReviewFilters'));
    AssertEquals('', S.ForgeValue('GitHub', 'IgnoredChecks'));
    AssertEquals('', S.ForgeValue('GitHub', 'Presets'));
    AssertTrue('changes asked for start as needing attention', S.ChangesNeedAttention);
    AssertTrue('failing checks start as needing attention', S.ChecksNeedAttention);
    AssertEquals('the last changed first', 0, S.MineOrder);
    AssertEquals(0, S.ReviewOrder);
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
  S := TGittanSettings.Create(FDir);
  try
    S.Left := 10;
    S.Top := 20;
    S.Width := 800;
    S.Height := 600;
    S.Maximized := True;
    S.MenuBar := True;
    S.TreeWidth := 240;
    S.RepoFilesOpen := True;
    S.SubmodulesOpen := False;
    S.TickHintHidden := True;
    S.GraphTipHidden := True;
    S.GraphFirstParent := True;
    S.GraphNoMerges := True;
    S.CommitOpen := False;
    S.CommitDraft := 'Subject = x'#10#10'C:\new\nope\\'#10;
    S.CommitDraftRepo := '/tmp/a';
    S.FontName := 'Menlo';
    S.FontSize := 13;
    S.Zoom := 120;
    S.WordWrap := True;
    S.OnlyChanges := False;
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
    S.SetForgeValue('GitHub', 'MineFilters', 'feedback,attention,nodrafts,stale');
    S.SetForgeValue('GitHub', 'ReviewFilters', 'askedofme,nodrafts');
    S.SetForgeValue('GitHub', 'IgnoredChecks', 'npm audit|CodeQL');
    S.SetForgeValue('GitHub', 'Presets', 'mine|Bot done|feedback,nodrafts');
    S.ChangesNeedAttention := False;
    S.ChecksNeedAttention := False;
    S.MineOrder := 2;
    S.ReviewOrder := 1;
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
  S := TGittanSettings.Create(FDir);
  try
    S.Load;
    AssertEquals(10, S.Left);
    AssertEquals(20, S.Top);
    AssertEquals(800, S.Width);
    AssertEquals(600, S.Height);
    AssertTrue(S.Maximized);
    AssertTrue(S.MenuBar);
    AssertEquals(240, S.TreeWidth);
    AssertTrue(S.RepoFilesOpen);
    AssertFalse(S.SubmodulesOpen);
    AssertTrue(S.TickHintHidden);
    AssertTrue(S.GraphTipHidden);
    AssertTrue(S.GraphFirstParent);
    AssertTrue(S.GraphNoMerges);
    AssertFalse(S.CommitOpen);
    AssertEquals('Subject = x'#10#10'C:\new\nope\\'#10, S.CommitDraft);
    AssertEquals('/tmp/a', S.CommitDraftRepo);
    AssertEquals('Menlo', S.FontName);
    AssertEquals(13, S.FontSize);
    AssertEquals(120, S.Zoom);
    AssertTrue(S.WordWrap);
    AssertFalse('off is kept', S.OnlyChanges);
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
    AssertEquals('feedback,attention,nodrafts,stale', S.ForgeValue('GitHub', 'MineFilters'));
    AssertEquals('askedofme,nodrafts', S.ForgeValue('GitHub', 'ReviewFilters'));
    AssertEquals('npm audit|CodeQL', S.ForgeValue('GitHub', 'IgnoredChecks'));
    AssertEquals('mine|Bot done|feedback,nodrafts', S.ForgeValue('GitHub', 'Presets'));
    AssertFalse(S.ChangesNeedAttention);
    AssertFalse(S.ChecksNeedAttention);
    AssertEquals(2, S.MineOrder);
    AssertEquals(1, S.ReviewOrder);
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
      FileModeOf(S.SettingsFile) and &777);
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

{ Whatever a string holds comes back as it was: quotes and spaces at
  its edges, backslashes, line ends, a tab, letters past ASCII. }
procedure TSettingsTest.TestStringsAsTheyAre;
var
  S: TGittanSettings;
begin
  S := TGittanSettings.Create(FDir);
  try
    S.EditorCommand := '"C:\Program Files\Code\Code.exe"';
    S.TerminalCommand := '"wt.exe" -d';
    S.CommitDraft := '"Quoted subject"'#13#10#13#10'body\n'#9'åäö 🙂'#10;
    S.CommitDraftRepo := '  /tmp/a ';
    S.GitPath := '"';
    S.SetForgeCliPath('GitHub', '""');
    S.FontName := 'Menlo';
    S.Save;
  finally
    S.Free;
  end;
  S := TGittanSettings.Create(FDir);
  try
    S.Load;
    AssertEquals('"C:\Program Files\Code\Code.exe"', S.EditorCommand);
    AssertEquals('"wt.exe" -d', S.TerminalCommand);
    AssertEquals('"Quoted subject"'#13#10#13#10'body\n'#9'åäö 🙂'#10, S.CommitDraft);
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
  S := TGittanSettings.Create(FDir);
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
    S.RemoveRecent('/repo/' + IntToStr(MaxRecent + 3));
    S.RemoveRecent('/repo/none');
    AssertEquals('removed', MaxRecent - 1, S.Recent.Count);
    AssertEquals('/repo/' + IntToStr(MaxRecent + 2), S.Recent[1]);
    for i := 1 to MaxPaletteRecent + 2 do
      S.AddPaletteRecent('Action ' + IntToStr(i));
    S.AddPaletteRecent('Action 5');
    AssertEquals('capped', MaxPaletteRecent, S.PaletteRecent.Count);
    AssertEquals('Action 5', S.PaletteRecent[0]);
    AssertEquals('Action ' + IntToStr(MaxPaletteRecent + 2), S.PaletteRecent[1]);
    AssertEquals('a repeat is not kept twice', 'Action 3',
      S.PaletteRecent[MaxPaletteRecent - 1]);
  finally
    S.Free;
  end;
end;

{ SaveRecent writes the recent list alone, leaving what else the file
  holds as it is. }
procedure TSettingsTest.TestSaveRecent;
var
  S, Back: TGittanSettings;
begin
  S := TGittanSettings.Create(FDir);
  try
    S.EditorCommand := '/usr/bin/editor';
    S.AddRecent('/repo/a');
    S.AddRecent('/repo/b');
    S.Save;
    S.EditorCommand := '/changed';
    { Another instance saves its draft and width meanwhile. }
    Back := TGittanSettings.Create(FDir);
    try
      Back.Load;
      Back.CommitDraft := 'newer';
      Back.Width := 1234;
      Back.Save;
    finally
      Back.Free;
    end;
    S.RemoveRecent('/repo/b');
    S.SaveRecent;
  finally
    S.Free;
  end;
  Back := TGittanSettings.Create(FDir);
  try
    Back.Load;
    AssertEquals(1, Back.Recent.Count);
    AssertEquals('/repo/a', Back.Recent[0]);
    AssertEquals('the rest untouched', '/usr/bin/editor', Back.EditorCommand);
    AssertEquals('the other instance''s draft kept', 'newer', Back.CommitDraft);
    AssertEquals('and its width', 1234, Back.Width);
  finally
    Back.Free;
  end;
end;

procedure TSettingsTest.TestTabs;
var
  S: TGittanSettings;
begin
  S := TGittanSettings.Create(FDir);
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
  S := TGittanSettings.Create(FDir);
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
  S := TGittanSettings.Create(FDir);
  try
    S.Load;
    AssertEquals('fewer tabs drop the rest', 1, S.Tabs.Count);
    AssertEquals('an active tab past the end is the first', 0, S.ActiveTab);
  finally
    S.Free;
  end;
end;

procedure TSettingsTest.TestCoAuthors;
var
  S: TGittanSettings;
  i: integer;
begin
  S := TGittanSettings.Create(FDir);
  try
    AssertEquals(0, S.CoAuthors.Count);
    S.AddCoAuthor('Ada <ada@example.invalid>');
    S.AddCoAuthor('Bo <bo@example.invalid>');
    S.AddCoAuthor(' Ada <ada@example.invalid> ');
    AssertEquals('once, moved first', 2, S.CoAuthors.Count);
    AssertEquals('Ada <ada@example.invalid>', S.CoAuthors[0]);
    for i := 1 to MaxCoAuthors + 3 do
      S.AddCoAuthor('P' + IntToStr(i) + ' <p@example.invalid>');
    AssertEquals(MaxCoAuthors, S.CoAuthors.Count);
    S.Save;
  finally
    S.Free;
  end;
  S := TGittanSettings.Create(FDir);
  try
    S.Load;
    AssertEquals(MaxCoAuthors, S.CoAuthors.Count);
    AssertEquals('P' + IntToStr(MaxCoAuthors + 3) + ' <p@example.invalid>', S.CoAuthors[0]);
  finally
    S.Free;
  end;
end;

procedure TSettingsTest.TestBatchRepos;
var
  S: TGittanSettings;
begin
  S := TGittanSettings.Create(FDir);
  try
    AssertEquals('none by default', 0, S.BatchRepos.Count);
    AssertEquals('the overview by default', '', S.BatchOperation);
    S.BatchOperation := 'ext:forge-overview:b';
    S.BatchRepos.Add('/repo/a');
    S.BatchRepos.Add('/repo/b c');
    S.Save;
  finally
    S.Free;
  end;
  S := TGittanSettings.Create(FDir);
  try
    S.Load;
    AssertEquals(2, S.BatchRepos.Count);
    AssertEquals('/repo/b c', S.BatchRepos[1]);
    AssertEquals('ext:forge-overview:b', S.BatchOperation);
  finally
    S.Free;
  end;
end;

{ batch.operation kept by its index before: 1 to 3 the operations, 0
  and an unknown one the overview. }
procedure TSettingsTest.TestBatchOperationIndex;
const
  Keys: array[0..4] of string = ('', 'gone', 'identity', 'maintenance', '');
var
  S: TGittanSettings;
  i: integer;
begin
  for i := 0 to High(Keys) do
  begin
    Put('state.json', '{"batch": {"operation": ' + IntToStr(i) + '}}');
    S := TGittanSettings.Create(FDir);
    try
      S.Load;
      AssertEquals('index ' + IntToStr(i), Keys[i], S.BatchOperation);
    finally
      S.Free;
    end;
  end;
end;

procedure TSettingsTest.TestDamagedFileGivesDefaults;
var
  S: TGittanSettings;
begin
  Put('settings.json', '{"diff": {"contextLines": 5,');
  Put('state.json', '["not", "an", "object"]');
  S := TGittanSettings.Create(FDir);
  try
    S.Load;
    AssertEquals('a file cut short is none', 3, S.ContextLines);
    AssertEquals(0, S.Width);
  finally
    S.Free;
  end;
  { A member of another type keeps the default, the rest are read. }
  Put('settings.json', '{"diff": {"contextLines": "lots", "sideBySide": 1, "blame": true},' +
    '"editor": [], "tools": {"autoFetchMinutes": 100000}}');
  Put('state.json', '{"window": {"width": 1.5e30, "height": 700}, "recent": ["/a", 3, "", "/b"],' +
    '"tabs": {"open": "/a", "active": 2}}');
  S := TGittanSettings.Create(FDir);
  try
    S.Load;
    AssertEquals(3, S.ContextLines);
    AssertFalse('a number is no boolean', S.SideBySide);
    AssertTrue(S.Blame);
    AssertEquals('kept in its range', MaxAutoFetchMinutes, S.AutoFetchMinutes);
    AssertEquals('a float is no width', 0, S.Width);
    AssertEquals(700, S.Height);
    AssertEquals('the strings of the list', '/a,/b', S.Recent.CommaText);
    AssertEquals('no tabs', 0, S.Tabs.Count);
    AssertEquals(0, S.ActiveTab);
  finally
    S.Free;
  end;
end;

{ A member of another type is written back as the field has it, and the
  file read again gives what was saved. }
procedure TSettingsTest.TestWrongTypesSaved;
var
  S: TGittanSettings;
  Doc: TJSONObject;
begin
  Put('settings.json', '{"diff": {"contextLines": "lots", "sideBySide": 1},' +
    '"editor": [], "ai": {"claude": "x"}}');
  Put('state.json', '{"window": {"width": "wide"}, "commitDraft": 7}');
  S := TGittanSettings.Create(FDir);
  try
    S.Load;
    AssertEquals(3, S.ContextLines);
    S.FontName := 'Menlo';
    S.ClaudeModel := 'sonnet';
    S.Height := 500;
    S.Save;
  finally
    S.Free;
  end;
  S := TGittanSettings.Create(FDir);
  try
    S.Load;
    AssertEquals('the default, saved', 3, S.ContextLines);
    AssertFalse(S.SideBySide);
    AssertEquals('the other setting', 'Menlo', S.FontName);
    AssertEquals('in place of a string', 'sonnet', S.ClaudeModel);
    AssertEquals(0, S.Width);
    AssertEquals(500, S.Height);
    AssertEquals('', S.CommitDraft);
  finally
    S.Free;
  end;
  Doc := ReadJson('settings.json');
  try
    AssertEquals('a number now', 3, Doc.FindPath('diff.contextLines').AsInteger);
    AssertTrue('a boolean now', Doc.FindPath('diff.sideBySide') is TJSONBoolean);
  finally
    Doc.Free;
  end;
end;

{ With no draft, the draft's text and repository go, a member of a newer
  build's stays. }
procedure TSettingsTest.TestDraftUnknownKept;
var
  S: TGittanSettings;
  Doc: TJSONObject;
begin
  Put('state.json', '{"commitDraft": {"text": "wip", "repo": "/a", "later": 1}}');
  S := TGittanSettings.Create(FDir);
  try
    S.Load;
    AssertEquals('wip', S.CommitDraft);
    S.CommitDraft := '';
    S.Save;
  finally
    S.Free;
  end;
  Doc := ReadJson('state.json');
  try
    AssertNull('no text', Doc.FindPath('commitDraft.text'));
    AssertNull('no repo', Doc.FindPath('commitDraft.repo'));
    AssertEquals('kept', 1, Doc.FindPath('commitDraft.later').AsInteger);
  finally
    Doc.Free;
  end;
end;

{ The settings dialog's list of values: a key with an = and keys that
  differ in case alone go there and back whole. }
procedure TSettingsTest.TestExtValueList;
var
  S: TGittanSettings;
  L, Keys: TStringList;
  Key, Id: string;
  i: integer;
begin
  S := TGittanSettings.Create(FDir);
  L := NewExtValueList;
  Keys := TStringList.Create;
  try
    S.SetExtValue('a=b', 'x=y', 'old=1');
    S.SetExtValue('a=b', 'Token', 'upper');
    S.SetExtValue('a=b', 'token', 'lower');
    S.ExtValueKeys('a=b', Keys);
    for Key in Keys do
      L.Values['a=b' + #9 + Key] := S.ExtValue('a=b', Key);
    AssertEquals(3, L.Count);
    AssertEquals('old=1', L.Values['a=b' + #9 + 'x=y']);
    AssertEquals('upper', L.Values['a=b' + #9 + 'Token']);
    AssertEquals('lower', L.Values['a=b' + #9 + 'token']);
    L.Values['a=b' + #9 + 'token'] := 'edited';
    for i := 0 to L.Count - 1 do
    begin
      Id := L.Names[i];
      Key := Copy(Id, Pos(#9, Id) + 1, MaxInt);
      Id := Copy(Id, 1, Pos(#9, Id) - 1);
      S.SetExtValue(Id, Key, L.ValueFromIndex[i]);
    end;
    AssertEquals('old=1', S.ExtValue('a=b', 'x=y'));
    AssertEquals('upper', S.ExtValue('a=b', 'Token'));
    AssertEquals('edited', S.ExtValue('a=b', 'token'));
    AssertEquals('no key made of a part', '', S.ExtValue('a=b', 'x'));
    AssertEquals('no extension made of a part', '', S.ExtValue('a', 'x=y'));
  finally
    Keys.Free;
    L.Free;
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
  S := TGittanSettings.Create(FDir);
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
  S := TGittanSettings.Create(FDir);
  try
    S.Load;
    AssertTrue('the newest hash is kept', S.CommandsTrusted('/tmp/a', 'def'));
    AssertFalse(S.CommandsTrusted('/tmp/a', 'abc'));
    AssertFalse('an empty hash trusts nothing', S.CommandsTrusted('/tmp/b', 'x'));
  finally
    S.Free;
  end;
end;

procedure TSettingsTest.TestProjectKinds;
var
  S: TGittanSettings;
begin
  S := TGittanSettings.Create(FDir);
  try
    AssertEquals('none picked', '', S.ProjectKindsOf('/tmp/a'));
    S.SetProjectKinds('/tmp/a', 'Lazarus,Node');
    S.SetProjectKinds('/tmp/b', 'none');
    S.SetProjectKinds('/tmp/c', 'Go');
    S.SetProjectKinds('/tmp/c', '');
    S.Save;
  finally
    S.Free;
  end;
  S := TGittanSettings.Create(FDir);
  try
    S.Load;
    AssertEquals('Lazarus,Node', S.ProjectKindsOf('/tmp/a'));
    AssertEquals('none', S.ProjectKindsOf('/tmp/b'));
    AssertEquals('forgotten', '', S.ProjectKindsOf('/tmp/c'));
  finally
    S.Free;
  end;
end;

{ A forge's values live in its object; a value cleared goes from the
  file, and so the object once it is empty. }
procedure TSettingsTest.TestForgeValues;
var
  S: TGittanSettings;
  Doc: TJSONObject;
begin
  S := TGittanSettings.Create(FDir);
  try
    S.SetForgeValue('GitHub', 'MineFilters', 'attention');
    S.SetForgeValue('GitHub', 'ReviewFilters', 'nodrafts');
    S.SetForgeValue('GitLab', 'MineFilters', 'stale');
    S.SetForgeValue('GitLab', 'MineFilters', '');
    S.SetForgeValue('Gitea', 'MineFilters', '');
    S.SetForgeValue('GitHub', 'ReviewFilters', '');
    S.Save;
  finally
    S.Free;
  end;
  Doc := ReadJson('settings.json');
  try
    AssertEquals('attention', Doc.FindPath('hosting.forges.GitHub.mineFilters').AsString);
    AssertNull('a cleared value is not written', Doc.FindPath('hosting.forges.GitHub.reviewFilters'));
    AssertNull('nor an empty forge', Doc.FindPath('hosting.forges.GitLab'));
    AssertNull(Doc.FindPath('hosting.forges.Gitea'));
  finally
    Doc.Free;
  end;
  S := TGittanSettings.Create(FDir);
  try
    S.Load;
    AssertEquals('attention', S.ForgeValue('GitHub', 'MineFilters'));
    AssertEquals('', S.ForgeValue('GitHub', 'ReviewFilters'));
    AssertEquals('', S.ForgeValue('GitLab', 'MineFilters'));
  finally
    S.Free;
  end;
end;

procedure TSettingsTest.TestExtensions;
var
  S: TGittanSettings;
  Keys: TStringList;
begin
  S := TGittanSettings.Create(FDir);
  try
    AssertTrue('on by default', S.ExtEnabled('hello'));
    AssertFalse('no grant', S.HasExtPerm('hello'));
    AssertEquals('no value', '', S.ExtValue('hello', 'url'));
    AssertEquals('its folder', IncludeTrailingPathDelimiter(FDir) +
      'extensions', S.ExtensionsDir);
    AssertEquals(IncludeTrailingPathDelimiter(FDir) + 'forge-picture', S.ForgePictureFile);
    S.SetExtEnabled('hello', False);
    S.SetExtEnabled('other', False);
    S.SetExtEnabled('other', True);
    S.SetExtPerm('hello', 'Hash', 'abc');
    S.SetExtPerm('hello', 'Granted', 'net,exec');
    S.SetExtPerm('hello', 'Author', '(c) Someone');
    S.SetExtValue('hello', 'url', ' https://example.com/hook ');
    S.SetExtValue('hello', 'json', '{"a": "b c"}');
    S.SetExtValue('hello', 'gone', 'x');
    S.SetExtValue('hello', 'gone', '');
    S.SetExtValue('hello', 'lines', 'a' + #10 + '[Trust]' + #13#10 + 'x=1' + #13 + 'c:\d\n');
    S.SetExtValue('hello', 'a=b', 'eq');
    S.SetExtValue('hello', 'URL', 'upper');
    try
      S.SetExtValue('hello', '', 'v');
      Fail('an empty key is refused');
    except
      on EArgumentException do;
    end;
    try
      S.SetExtValue('hello', 'k' + #10 + 'x', 'v');
      Fail('a key with a line end is refused');
    except
      on EArgumentException do;
    end;
    S.Save;
  finally
    S.Free;
  end;
  S := TGittanSettings.Create(FDir);
  Keys := TStringList.Create;
  try
    S.Load;
    AssertEquals('line ends and backslashes as they were',
      'a' + #10 + '[Trust]' + #13#10 + 'x=1' + #13 + 'c:\d\n', S.ExtValue('hello', 'lines'));
    AssertEquals('= in a key', 'eq', S.ExtValue('hello', 'a=b'));
    AssertEquals('a key tells case', 'upper', S.ExtValue('hello', 'URL'));
    AssertEquals(' https://example.com/hook ', S.ExtValue('hello', 'url'));
    AssertFalse('off kept', S.ExtEnabled('hello'));
    AssertTrue('on again', S.ExtEnabled('other'));
    AssertTrue('grant kept', S.HasExtPerm('hello'));
    AssertEquals('hash', 'abc', S.ExtPerm('hello', 'Hash'));
    AssertEquals('granted', 'net,exec', S.ExtPerm('hello', 'Granted'));
    AssertEquals('author', '(c) Someone', S.ExtPerm('hello', 'Author'));
    AssertEquals('value with its edges', ' https://example.com/hook ', S.ExtValue('hello', 'url'));
    AssertEquals('json as it was', '{"a": "b c"}', S.ExtValue('hello', 'json'));
    AssertEquals('empty dropped', '', S.ExtValue('hello', 'gone'));
    S.ExtValueKeys('hello', Keys);
    AssertEquals('the keys', 'url,json,lines,a=b,URL', Keys.CommaText);
    S.ClearExtPerm('hello');
    AssertFalse('grant cleared', S.HasExtPerm('hello'));
    AssertEquals('values stay', '{"a": "b c"}', S.ExtValue('hello', 'json'));
    S.Save;
  finally
    Keys.Free;
    S.Free;
  end;
  S := TGittanSettings.Create(FDir);
  try
    S.Load;
    AssertFalse('cleared grant gone from the file', S.HasExtPerm('hello'));
    AssertEquals('value still there', '{"a": "b c"}', S.ExtValue('hello', 'json'));
  finally
    S.Free;
  end;
end;

{ Where each value goes: what the user picks in settings.json, what
  Gittan keeps in state.json, both with the version of the layout. }
procedure TSettingsTest.TestLayout;
var
  S: TGittanSettings;
  Doc: TJSONObject;
  Found: TSearchRec;
begin
  S := TGittanSettings.Create(FDir);
  try
    S.FontName := 'Menlo';
    S.OpenAIKey := 'sk';
    S.Width := 900;
    S.AddRecent('/repo/a');
    S.Tabs.Add('/repo/a');
    S.TrustCommands('/repo/a', 'abc');
    S.SetExtValue('hello', 'k', 'v');
    S.SetExtPerm('hello', 'Hash', 'h');
    S.Save;
  finally
    S.Free;
  end;
  Doc := ReadJson('settings.json');
  try
    AssertEquals(SettingsVersion, Doc.Get('version', 0));
    AssertEquals('Menlo', Doc.FindPath('editor.fontName').AsString);
    AssertEquals('sk', Doc.FindPath('ai.openai.key').AsString);
    AssertEquals('v', Doc.FindPath('extensions.hello.values.k').AsString);
    AssertNull('no state in the settings', Doc.Find('window'));
  finally
    Doc.Free;
  end;
  Doc := ReadJson('state.json');
  try
    AssertEquals(SettingsVersion, Doc.Get('version', 0));
    AssertEquals(900, Doc.FindPath('window.width').AsInteger);
    AssertEquals('/repo/a', Doc.FindPath('recent[0]').AsString);
    AssertEquals('/repo/a', Doc.FindPath('tabs.open[0]').AsString);
    AssertEquals('the root as the key', 'abc', TJSONObject(Doc.Find('trust')).Strings['/repo/a']);
    AssertEquals('h', Doc.FindPath('extensionGrants.hello.hash').AsString);
    AssertNull('no settings in the state', Doc.Find('editor'));
    AssertNull('no draft written', Doc.Find('commitDraft'));
  finally
    Doc.Free;
  end;
  AssertFalse('no temporary file left', FileExists(IncludeTrailingPathDelimiter(FDir) +
    'settings.json.tmp'));
  if FindFirst(IncludeTrailingPathDelimiter(FDir) + '*.tmp', faAnyFile, Found) = 0 then
  begin
    FindClose(Found);
    Fail('no temporary file left: ' + Found.Name);
  end;
end;

{ A key Gittan does not know, a newer build's or one written by hand,
  is written back as it was. }
procedure TSettingsTest.TestUnknownKeysKept;
var
  S: TGittanSettings;
  Doc: TJSONObject;
begin
  Put('settings.json', '{"future": {"x": [1, 2]}, "editor": {"fontName": "A", "later": true}}');
  Put('state.json', '{"window": {"width": 640, "dock": "left"}, "notes": "mine"}');
  S := TGittanSettings.Create(FDir);
  try
    S.Load;
    AssertEquals('A', S.FontName);
    AssertEquals(640, S.Width);
    S.FontName := 'B';
    S.Width := 700;
    S.Save;
    S.Save;
  finally
    S.Free;
  end;
  Doc := ReadJson('settings.json');
  try
    AssertEquals('B', Doc.FindPath('editor.fontName').AsString);
    AssertTrue('beside a known key', Doc.FindPath('editor.later').AsBoolean);
    AssertEquals('an object of its own', 2, Doc.FindPath('future.x[1]').AsInteger);
  finally
    Doc.Free;
  end;
  Doc := ReadJson('state.json');
  try
    AssertEquals(700, Doc.FindPath('window.width').AsInteger);
    AssertEquals('left', Doc.FindPath('window.dock').AsString);
    AssertEquals('mine', Doc.Get('notes', ''));
  finally
    Doc.Free;
  end;
end;

{ An earlier build's gittan.ini with neither JSON file: the settings
  started over, which the window says once; nothing is read from it. }
procedure TSettingsTest.TestOldIni;
var
  S: TGittanSettings;
begin
  Put('gittan.ini', '[View]'#10'ContextLines=9'#10);
  S := TGittanSettings.Create(FDir);
  try
    S.Load;
    AssertTrue(S.OldIniFound);
    AssertEquals('not read', 3, S.ContextLines);
    S.Save;
  finally
    S.Free;
  end;
  AssertTrue('the old file is left alone', FileExists(IncludeTrailingPathDelimiter(FDir) +
    'gittan.ini'));
  S := TGittanSettings.Create(FDir);
  try
    S.Load;
    AssertFalse('once saved, said', S.OldIniFound);
  finally
    S.Free;
  end;
end;

initialization
  RegisterTest(TSettingsTest);
end.
