unit testsyntaxthemes;

{** Tests of gittan.syntaxthemes: theme lookup and the style each theme
  gives a CudaText theme style. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.syntaxthemes;

type
  TSyntaxThemesTest = class(TTestCase)
  published
    procedure TestFindTheme;
    procedure TestNamesAreUnique;
    procedure TestVSCodeColors;
    procedure TestDelphiStyles;
    procedure TestTextStylesKeepTheirFontStyle;
    procedure TestUnknownStyle;
    procedure TestBadIndexFallsBackToDefault;
  end;

implementation

procedure TSyntaxThemesTest.TestFindTheme;
begin
  AssertEquals(DefaultSyntaxTheme, FindSyntaxTheme('VS Code'));
  AssertTrue('case ignored', FindSyntaxTheme('delphi') >= 0);
  AssertEquals(-1, FindSyntaxTheme('Nope'));
  AssertEquals(-1, FindSyntaxTheme(''));
end;

procedure TSyntaxThemesTest.TestNamesAreUnique;
var
  i: integer;
begin
  for i := 0 to High(SyntaxThemes) do
    AssertEquals(SyntaxThemes[i].Name, i, FindSyntaxTheme(SyntaxThemes[i].Name));
end;

procedure TSyntaxThemesTest.TestVSCodeColors;
var
  C: cardinal;
  S: TThemeFontStyles;
begin
  AssertTrue(SyntaxThemeStyle(DefaultSyntaxTheme, 'IdKeyword', False, C, S));
  AssertEquals(Integer($0000FF), Integer(C));
  AssertTrue(S = []);
  AssertTrue(SyntaxThemeStyle(DefaultSyntaxTheme, 'IdKeyword', True, C, S));
  AssertEquals(Integer($569CD6), Integer(C));
  AssertTrue(SyntaxThemeStyle(DefaultSyntaxTheme, 'Comment', True, C, S));
  AssertEquals(Integer($6A9955), Integer(C));
  AssertTrue(SyntaxThemeStyle(DefaultSyntaxTheme, 'Id', False, C, S));
  AssertTrue('plain identifiers keep the text color', C = NoColor);
end;

procedure TSyntaxThemesTest.TestDelphiStyles;
var
  T: integer;
  C: cardinal;
  S: TThemeFontStyles;
begin
  T := FindSyntaxTheme('Delphi');
  AssertTrue(SyntaxThemeStyle(T, 'IdKeyword', False, C, S));
  AssertEquals(Integer($000080), Integer(C));
  AssertTrue('keywords bold', S = [tfsBold]);
  AssertTrue(SyntaxThemeStyle(T, 'Comment', False, C, S));
  AssertEquals(Integer($008000), Integer(C));
  AssertTrue('comments italic', S = [tfsItalic]);
  AssertTrue(SyntaxThemeStyle(T, 'Comment2', False, C, S));
  AssertEquals('directives teal', Integer($008080), Integer(C));
  AssertTrue(SyntaxThemeStyle(T, 'Id2', False, C, S));
  AssertTrue('types plain', C = NoColor);
end;

procedure TSyntaxThemesTest.TestTextStylesKeepTheirFontStyle;
var
  i: integer;
  C: cardinal;
  S: TThemeFontStyles;
begin
  for i := 0 to High(SyntaxThemes) do
  begin
    AssertTrue(SyntaxThemeStyle(i, 'TextBoldItalic', True, C, S));
    AssertTrue(SyntaxThemes[i].Name, S = [tfsBold, tfsItalic]);
    AssertTrue(SyntaxThemes[i].Name, C = NoColor);
  end;
end;

procedure TSyntaxThemesTest.TestUnknownStyle;
var
  C: cardinal;
  S: TThemeFontStyles;
begin
  AssertFalse(SyntaxThemeStyle(0, 'BracketBG', False, C, S));
  AssertFalse(SyntaxThemeStyle(0, '-', False, C, S));
  AssertFalse(SyntaxThemeStyle(0, '', False, C, S));
end;

procedure TSyntaxThemesTest.TestBadIndexFallsBackToDefault;
var
  C: cardinal;
  S: TThemeFontStyles;
begin
  AssertTrue(SyntaxThemeStyle(-1, 'String', False, C, S));
  AssertEquals(Integer($A31515), Integer(C));
  AssertTrue(SyntaxThemeStyle(99, 'String', False, C, S));
  AssertEquals(Integer($A31515), Integer(C));
end;

initialization
  RegisterTest(TSyntaxThemesTest);
end.
