unit testrepoconfig;

{** Tests of gittan.repoconfig: .gittan/repo.toml read with its
  defaults, values of the wrong type left out, the subject's limits,
  the subject checked against the types and scopes of Conventional
  Commits, and the protected branches with their patterns. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.repoconfig, testhelpers;

type
  TRepoConfigTest = class(TTestCase)
  private
    FDir: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDefaults;
    procedure TestParse;
    procedure TestWrongTypes;
    procedure TestLimits;
    procedure TestNotToml;
    procedure TestRead;
    procedure TestCheckSubject;
    procedure TestProtected;
    procedure TestTemplateParses;
  end;

implementation

procedure TRepoConfigTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'gittan-repoconfig-' +
    IntToStr(GetProcessID) + '-' + IntToStr(Random(1000000));
  ForceDirectories(FDir);
end;

procedure TRepoConfigTest.TearDown;
begin
  RemoveTree(FDir);
end;

procedure TRepoConfigTest.TestDefaults;
var
  C: TGittanRepoConfig;
begin
  C := ParseRepoConfig('');
  AssertTrue(C.Exists);
  AssertEquals('', C.Error);
  AssertFalse(C.HasProjects);
  AssertEquals(DefaultSubjectSoft, C.SubjectSoft);
  AssertEquals(DefaultSubjectHard, C.SubjectHard);
  AssertEquals('', C.Issues.LogRegex);
  AssertEquals('', C.Template);
  AssertFalse(C.HasSignOff);
  AssertEquals(0, Length(C.Types));
  AssertEquals(0, Length(C.Protected));
  C := EmptyRepoConfig;
  AssertFalse(C.Exists);
  AssertEquals(DefaultSubjectHard, C.SubjectHard);
end;

procedure TRepoConfigTest.TestParse;
var
  C: TGittanRepoConfig;
begin
  C := ParseRepoConfig('project = ["rust", "go"]'#10 +
    '[issues]'#10'url = "https://t.test/%BUGID%"'#10'regex = ''Fixes:?(\s*#\d+)+'''#10 +
    'ids = ''(\d+)'''#10 +
    '[commit]'#10'subject-limit = 60'#10'subject-max = 80'#10 +
    'template = ".gittan/message.txt"'#10'sign-off = true'#10 +
    'types = ["feat", "fix"]'#10'scopes = ["ui"]'#10 +
    '[branches]'#10'protected = ["main", "release/*"]'#10);
  AssertEquals('', C.Error);
  AssertTrue(C.HasProjects);
  AssertEquals(2, Length(C.Projects));
  AssertEquals('go', C.Projects[1]);
  AssertEquals('https://t.test/%BUGID%', C.Issues.Url);
  AssertEquals('the ids on a second line, as bugtraq.logregex', 'Fixes:?(\s*#\d+)+'#10'(\d+)',
    C.Issues.LogRegex);
  AssertEquals(60, C.SubjectSoft);
  AssertEquals(80, C.SubjectHard);
  AssertEquals('.gittan/message.txt', C.Template);
  AssertTrue(C.HasSignOff);
  AssertTrue(C.SignOff);
  AssertEquals(2, Length(C.Types));
  AssertEquals('ui', C.Scopes[0]);
  AssertEquals('release/*', C.Protected[1]);
  C := ParseRepoConfig('project = "none"'#10'[branches]'#10'protected = "main"'#10);
  AssertTrue('none names no kind', C.HasProjects);
  AssertEquals(0, Length(C.Projects));
  AssertEquals('a string is a list of one', 1, Length(C.Protected));
  C := ParseRepoConfig('[issues]'#10'ids = ''(\d+)'''#10);
  AssertEquals('ids without regex is no tracker', '', C.Issues.LogRegex);
  C := ParseRepoConfig('[issues]'#10'url = "file:///Applications/Calculator.app"'#10 +
    'regex = ''#(\d+)'''#10);
  AssertEquals('a web address only', '', C.Issues.Url);
  AssertEquals('#(\d+)', C.Issues.LogRegex);
  C := ParseRepoConfig('[issues]'#10'url = "HTTP://t.test/%BUGID%"'#10);
  AssertEquals('HTTP://t.test/%BUGID%', C.Issues.Url);
end;

procedure TRepoConfigTest.TestWrongTypes;
var
  C: TGittanRepoConfig;
begin
  C := ParseRepoConfig('project = 3'#10'issues = "x"'#10 +
    '[commit]'#10'subject-max = "72"'#10'sign-off = "yes"'#10'template = 1'#10 +
    'types = [1, "fix", ""]'#10);
  AssertEquals('', C.Error);
  AssertFalse(C.HasProjects);
  AssertEquals('', C.Issues.LogRegex);
  AssertEquals(DefaultSubjectHard, C.SubjectHard);
  AssertFalse(C.HasSignOff);
  AssertEquals('', C.Template);
  AssertEquals('only the strings', 1, Length(C.Types));
  AssertEquals('fix', C.Types[0]);
end;

procedure TRepoConfigTest.TestLimits;
var
  C: TGittanRepoConfig;
begin
  C := ParseRepoConfig('[commit]'#10'subject-max = 40'#10);
  AssertEquals('a maximum under the default limit', 40, C.SubjectHard);
  AssertEquals('pulls the limit down', 40, C.SubjectSoft);
  C := ParseRepoConfig('[commit]'#10'subject-limit = 90'#10);
  AssertEquals(90, C.SubjectSoft);
  AssertEquals('a limit over the default maximum raises it', 90, C.SubjectHard);
  C := ParseRepoConfig('[commit]'#10'subject-limit = 90'#10'subject-max = 60'#10);
  AssertEquals('a maximum set holds', 60, C.SubjectHard);
  AssertEquals('and pulls the limit down', 60, C.SubjectSoft);
  C := ParseRepoConfig('[commit]'#10'subject-limit = 0'#10'subject-max = 1000'#10);
  AssertEquals('out of range is left out', DefaultSubjectSoft, C.SubjectSoft);
  AssertEquals(DefaultSubjectHard, C.SubjectHard);
end;

procedure TRepoConfigTest.TestNotToml;
var
  C: TGittanRepoConfig;
begin
  C := ParseRepoConfig('[commit'#10'types = ["feat"]'#10);
  AssertTrue(C.Exists);
  AssertTrue('why', C.Error <> '');
  AssertEquals('and nothing of it', 0, Length(C.Types));
  AssertEquals(DefaultSubjectHard, C.SubjectHard);
end;

procedure TRepoConfigTest.TestRead;
var
  C: TGittanRepoConfig;
  F: TStringList;
begin
  C := ReadRepoConfig(FDir);
  AssertFalse('no file', C.Exists);
  AssertFalse(ReadRepoConfig('').Exists);
  ForceDirectories(FDir + PathDelim + '.gittan');
  F := TStringList.Create;
  try
    F.Text := '[branches]'#10'protected = ["main"]';
    F.SaveToFile(FDir + PathDelim + '.gittan' + PathDelim + RepoConfigFile);
  finally
    F.Free;
  end;
  C := ReadRepoConfig(FDir);
  AssertTrue(C.Exists);
  AssertTrue(BranchProtected(C, 'main'));
end;

procedure TRepoConfigTest.TestCheckSubject;
var
  C: TGittanRepoConfig;
  D: string;
begin
  C := ParseRepoConfig('');
  AssertTrue('no types, anything goes', CheckSubject(C, 'Whatever', D) = scOk);
  C := ParseRepoConfig('[commit]'#10'types = ["feat", "fix"]'#10'scopes = ["ui", "core"]'#10);
  AssertTrue(CheckSubject(C, 'feat: a thing', D) = scOk);
  AssertTrue('a scope', CheckSubject(C, 'fix(ui): a thing', D) = scOk);
  AssertTrue('breaking', CheckSubject(C, 'feat(core)!: a thing', D) = scOk);
  AssertTrue('breaking, no scope', CheckSubject(C, 'feat!: a thing', D) = scOk);
  AssertTrue('in any case', CheckSubject(C, 'Fix(UI): a thing', D) = scOk);
  AssertTrue('two scopes', CheckSubject(C, 'fix(ui, core): a thing', D) = scOk);
  AssertTrue('empty', CheckSubject(C, '  ', D) = scOk);
  AssertTrue('a merge', CheckSubject(C, 'Merge branch ''x''', D) = scOk);
  AssertTrue('a fixup', CheckSubject(C, 'fixup! feat: a thing', D) = scOk);
  AssertTrue('a revert', CheckSubject(C, 'Revert "feat: a thing"', D) = scOk);
  AssertTrue('no type', CheckSubject(C, 'A thing', D) = scNoType);
  AssertTrue('no space after the colon', CheckSubject(C, 'feat:thing', D) = scNoType);
  AssertTrue('an open scope', CheckSubject(C, 'feat(ui: thing', D) = scNoType);
  AssertTrue('a colon alone', CheckSubject(C, ': thing', D) = scNoType);
  AssertTrue('the type ends the line', CheckSubject(C, 'feat:', D) = scOk);
  AssertTrue(CheckSubject(C, 'docs: a thing', D) = scUnknownType);
  AssertEquals('docs', D);
  AssertTrue(CheckSubject(C, 'fix(api): a thing', D) = scUnknownScope);
  AssertEquals('api', D);
  AssertTrue(CheckSubject(C, 'fix(ui,api): a thing', D) = scUnknownScope);
  AssertEquals('api', D);
  C := ParseRepoConfig('[commit]'#10'types = ["feat"]'#10);
  AssertTrue('no scopes listed, any scope', CheckSubject(C, 'feat(x): y', D) = scOk);
end;

procedure TRepoConfigTest.TestProtected;
var
  C: TGittanRepoConfig;
  S: string;
  i: integer;
begin
  AssertTrue(GlobMatch('main', 'main'));
  AssertFalse(GlobMatch('main', 'mainline'));
  AssertTrue(GlobMatch('release/*', 'release/1.0'));
  AssertTrue('* takes a slash too', GlobMatch('release/*', 'release/1/x'));
  AssertFalse(GlobMatch('release/*', 'releases/1.0'));
  AssertTrue(GlobMatch('v?', 'v1'));
  AssertFalse(GlobMatch('v?', 'v10'));
  AssertTrue(GlobMatch('*', ''));
  AssertTrue(GlobMatch('a**b', 'ab'));
  AssertTrue(GlobMatch('*/*-fix', 'hotfix/x-y-fix'));
  AssertFalse(GlobMatch('*/*-fix', 'hotfix/x-y-fixed'));
  AssertTrue('? is a character, not a byte', GlobMatch('release/?', 'release/'#$C3#$A5));
  AssertFalse(GlobMatch('release/??', 'release/'#$C3#$A5));
  AssertTrue('a character before a star', GlobMatch('*'#$C3#$A5, 'x'#$C3#$A5));
  { Twenty stars before a b that is not there: no exponential search. }
  S := '';
  for i := 1 to 20 do
    S := S + '*a';
  AssertFalse('many stars', GlobMatch(S + 'b', StringOfChar('a', 60)));
  AssertTrue(GlobMatch(S, StringOfChar('a', 60)));
  C := ParseRepoConfig('[branches]'#10'protected = ["main", "release/*"]'#10);
  AssertTrue(BranchProtected(C, 'main'));
  AssertTrue(BranchProtected(C, 'release/2'));
  AssertFalse(BranchProtected(C, 'feature/x'));
  AssertFalse('a detached HEAD', BranchProtected(C, ''));
end;

procedure TRepoConfigTest.TestTemplateParses;
var
  C: TGittanRepoConfig;
  Lines: TStringList;
  i: integer;
  S: string;
begin
  { Every line of it commented out: TOML, and nothing set. }
  C := ParseRepoConfig(RepoConfigTemplate);
  AssertEquals('', C.Error);
  AssertEquals(0, Length(C.Types));
  { Its example lines uncommented are TOML with every value. }
  Lines := TStringList.Create;
  try
    Lines.Text := RepoConfigTemplate;
    for i := 0 to Lines.Count - 1 do
    begin
      S := Copy(Lines[i], 3, MaxInt);
      if (Copy(Lines[i], 1, 2) = '# ') and ((Copy(S, 1, 1) = '[') or (Pos(' = ', S) > 0)) then
        Lines[i] := S;
    end;
    C := ParseRepoConfig(Lines.Text);
  finally
    Lines.Free;
  end;
  AssertEquals('', C.Error);
  AssertEquals(2, Length(C.Projects));
  AssertEquals('#(\d+)', C.Issues.LogRegex);
  AssertEquals(6, Length(C.Types));
  AssertTrue(C.SignOff);
  AssertTrue(BranchProtected(C, 'release/1'));
end;

initialization
  RegisterTest(TRepoConfigTest);
end.
