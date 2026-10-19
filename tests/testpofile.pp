unit testpofile;

{** Tests of gittan.pofile: reading the entries of a .po file and the
  rows of the translation view. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry, gittan.pofile;

type
  TPoFileTest = class(TTestCase)
  published
    procedure TestPath;
    procedure TestUnescape;
    procedure TestEntries;
    procedure TestContinuation;
    procedure TestPlural;
    procedure TestNoBlankLine;
    procedure TestObsolete;
    procedure TestRows;
    procedure TestRowsPlural;
    procedure TestChanged;
  end;

implementation

const
  Sample =
    '# Swedish translation.' + LineEnding +
    'msgid ""' + LineEnding +
    'msgstr ""' + LineEnding +
    '"Language: sv\n"' + LineEnding +
    '' + LineEnding +
    '#: main.c:12' + LineEnding +
    'msgid "Open"' + LineEnding +
    'msgstr "Öppna"' + LineEnding +
    '' + LineEnding +
    '#, fuzzy, c-format' + LineEnding +
    'msgctxt "menu"' + LineEnding +
    'msgid "Save %s"' + LineEnding +
    'msgstr "Spara %s"' + LineEnding +
    '' + LineEnding +
    'msgid "Quit"' + LineEnding +
    'msgstr ""' + LineEnding;

procedure TPoFileTest.TestPath;
begin
  AssertTrue(IsPoPath('po/sv.po'));
  AssertTrue(IsPoPath('SV.PO'));
  AssertFalse(IsPoPath('po/gittan.pot'));
  AssertFalse(IsPoPath('po/sv.pp'));
end;

procedure TPoFileTest.TestUnescape;
begin
  AssertEquals('a' + #10 + 'b', PoUnescape('a\nb'));
  AssertEquals('say "hi"', PoUnescape('say \"hi\"'));
  AssertEquals('back\slash', PoUnescape('back\\slash'));
  AssertEquals('tab' + #9, PoUnescape('tab\t'));
  AssertEquals('end\', PoUnescape('end\'));
end;

procedure TPoFileTest.TestEntries;
var
  E: TGittanPoEntries;
begin
  E := ParsePo(Sample);
  AssertEquals(4, Length(E));
  AssertTrue(IsPoHeader(E[0]));
  AssertEquals('Language: sv' + #10, E[0].Strs[0]);
  AssertEquals('Open', E[1].Id);
  AssertEquals('Öppna', E[1].Strs[0]);
  AssertEquals(7, E[1].IdLine);
  AssertEquals(8, E[1].StrLines[0]);
  AssertFalse(E[1].Fuzzy);
  AssertTrue(IsTranslated(E[1]));
  AssertTrue(E[2].Fuzzy);
  AssertTrue(E[2].HasContext);
  AssertEquals('menu', E[2].Context);
  AssertEquals('Save %s', E[2].Id);
  AssertFalse(IsPoHeader(E[2]));
  AssertEquals('Quit', E[3].Id);
  AssertFalse(IsTranslated(E[3]));
end;

procedure TPoFileTest.TestContinuation;
var
  E: TGittanPoEntries;
begin
  E := ParsePo('msgid ""' + LineEnding + '"First line\n"' + LineEnding +
    '"second"' + LineEnding + 'msgstr "Första\n"' + LineEnding +
    '"andra"' + LineEnding);
  AssertEquals(1, Length(E));
  AssertEquals('First line' + #10 + 'second', E[0].Id);
  AssertEquals('Första' + #10 + 'andra', E[0].Strs[0]);
  AssertFalse(IsPoHeader(E[0]));
end;

procedure TPoFileTest.TestPlural;
var
  E: TGittanPoEntries;
begin
  E := ParsePo('msgid "%d file"' + LineEnding + 'msgid_plural "%d files"' +
    LineEnding + 'msgstr[0] "%d fil"' + LineEnding + 'msgstr[1] "%d filer"' +
    LineEnding);
  AssertEquals(1, Length(E));
  AssertTrue(E[0].HasPlural);
  AssertEquals('%d files', E[0].IdPlural);
  AssertEquals(2, Length(E[0].Strs));
  AssertEquals('%d filer', E[0].Strs[1]);
  AssertEquals(4, E[0].StrLines[1]);
  AssertTrue(IsTranslated(E[0]));
end;

procedure TPoFileTest.TestNoBlankLine;
var
  E: TGittanPoEntries;
begin
  E := ParsePo('msgid "a"' + LineEnding + 'msgstr "A"' + LineEnding +
    '#, fuzzy' + LineEnding + 'msgid "b"' + LineEnding + 'msgstr "B"' +
    LineEnding + 'msgid "c"' + LineEnding + 'msgstr "C"');
  AssertEquals(3, Length(E));
  AssertFalse(E[0].Fuzzy);
  AssertTrue(E[1].Fuzzy);
  AssertFalse(E[2].Fuzzy);
  AssertEquals('C', E[2].Strs[0]);
end;

procedure TPoFileTest.TestObsolete;
var
  E: TGittanPoEntries;
  Rows: TGittanPoRows;
  Count, Fuzzy, Untranslated: integer;
begin
  E := ParsePo('msgid "a"' + LineEnding + 'msgstr "A"' + LineEnding + '' +
    LineEnding + '#~ msgid "old"' + LineEnding + '#~ msgstr "gammal"' + LineEnding);
  AssertEquals(2, Length(E));
  AssertTrue(E[1].Obsolete);
  AssertEquals('gammal', E[1].Strs[0]);
  Rows := PoRows(E, Count, Fuzzy, Untranslated);
  AssertEquals(1, Count);
  AssertEquals(1, Length(Rows.Left));
end;

procedure TPoFileTest.TestRows;
var
  Rows: TGittanPoRows;
  Count, Fuzzy, Untranslated: integer;
begin
  Rows := PoRows(ParsePo(Sample), Count, Fuzzy, Untranslated);
  AssertEquals(3, Count);
  AssertEquals(1, Fuzzy);
  AssertEquals(1, Untranslated);
  { Open, separator, [menu] + Save over Spara and a pad, separator, Quit. }
  AssertEquals(6, Length(Rows.Left));
  AssertEquals(6, Length(Rows.Right));
  AssertEquals(6, Length(Rows.Kinds));
  AssertEquals('Open', Rows.Left[0]);
  AssertEquals('Öppna', Rows.Right[0]);
  AssertEquals(7, Rows.LeftLines[0]);
  AssertEquals(8, Rows.RightLines[0]);
  AssertTrue(Rows.Kinds[1] = prSeparator);
  AssertEquals('[menu]', Rows.Left[2]);
  AssertEquals('Save %s', Rows.Left[3]);
  AssertEquals(0, Rows.LeftLines[2]);
  AssertEquals(12, Rows.LeftLines[3]);
  AssertEquals('Spara %s', Rows.Right[2]);
  AssertEquals('', Rows.Right[3]);
  AssertTrue(Rows.Context[2]);
  AssertFalse(Rows.Context[3]);
  AssertFalse(Rows.Context[0]);
  AssertEquals(6, Length(Rows.Context));
  AssertTrue(Rows.Kinds[2] = prFuzzy);
  AssertTrue(Rows.Kinds[3] = prFuzzy);
  AssertEquals('Quit', Rows.Left[5]);
  AssertEquals('', Rows.Right[5]);
  AssertTrue(Rows.Kinds[5] = prUntranslated);
end;

procedure TPoFileTest.TestRowsPlural;
var
  Rows: TGittanPoRows;
  Count, Fuzzy, Untranslated: integer;
begin
  Rows := PoRows(ParsePo('msgid "%d file"' + LineEnding +
    'msgid_plural "%d files"' + LineEnding + 'msgstr[0] "%d fil"' + LineEnding +
    'msgstr[1] ""' + LineEnding), Count, Fuzzy, Untranslated);
  AssertEquals(1, Untranslated);
  AssertEquals(2, Length(Rows.Left));
  AssertEquals('%d files', Rows.Left[1]);
  AssertEquals('[0] %d fil', Rows.Right[0]);
  AssertEquals('[1] ', Rows.Right[1]);
end;

procedure TPoFileTest.TestChanged;
var
  Old, New: TGittanPoEntries;
  Changed: TBooleanDynArray;
  Rows: TGittanPoRows;
  Count, Fuzzy, Untranslated: integer;
begin
  Old := ParsePo('msgid "a"' + LineEnding + 'msgstr "A"' + LineEnding + '' +
    LineEnding + 'msgctxt "x"' + LineEnding + 'msgid "b"' + LineEnding +
    'msgstr "B"' + LineEnding + '' + LineEnding + 'msgid "c"' + LineEnding +
    'msgstr "C"' + LineEnding);
  New := ParsePo('msgid "a"' + LineEnding + 'msgstr "A"' + LineEnding + '' +
    LineEnding + 'msgctxt "x"' + LineEnding + 'msgid "b"' + LineEnding +
    'msgstr "Bee"' + LineEnding + '' + LineEnding + '#, fuzzy' + LineEnding +
    'msgid "c"' + LineEnding + 'msgstr "C"' + LineEnding + '' + LineEnding +
    'msgctxt "y"' + LineEnding + 'msgid "a"' + LineEnding + 'msgstr "A"' + LineEnding);
  Changed := ChangedEntries(Old, New);
  AssertEquals(4, Length(Changed));
  AssertFalse(Changed[0]);
  AssertTrue(Changed[1]);
  AssertTrue(Changed[2]);
  AssertTrue(Changed[3]);
  AssertFalse(ChangedEntries(New, New)[1]);
  Rows := PoRows(New, Count, Fuzzy, Untranslated);
  AssertEquals(Length(Rows.Left), Length(Rows.Entries));
  AssertEquals(0, Rows.Entries[0]);
  AssertEquals(-1, Rows.Entries[1]);
  AssertEquals(1, Rows.Entries[2]);
  AssertEquals(1, Rows.Entries[3]);
end;

initialization
  RegisterTest(TPoFileTest);
end.
