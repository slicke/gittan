unit testterminal;

{** Tests of gittan.terminal: what a hook writes for a terminal, read
  into lines and styles. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.terminal;

type
  TTerminalTest = class(TTestCase)
  private
    FTerminal: TGittanTerminal;
    procedure CheckSpan(ALine, AIndex: integer; const AText: string; AFore: longint;
      AAttrs: TGittanTermAttrs = []);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPlain;
    procedure TestColors;
    procedure TestExtendedColors;
    procedure TestAttributes;
    procedure TestSplitSequence;
    procedure TestOtherSequences;
    procedure TestReturnTabBackspace;
    procedure TestPaletteRGB;
  end;

implementation

procedure TTerminalTest.SetUp;
begin
  FTerminal := TGittanTerminal.Create;
end;

procedure TTerminalTest.TearDown;
begin
  FTerminal.Free;
end;

procedure TTerminalTest.CheckSpan(ALine, AIndex: integer; const AText: string;
  AFore: longint; AAttrs: TGittanTermAttrs);
var
  Line: TGittanTermLine;
begin
  Line := FTerminal[ALine];
  AssertTrue('span ' + IntToStr(AIndex), AIndex < Length(Line.Spans));
  with Line.Spans[AIndex] do
  begin
    AssertEquals('text', AText, Copy(Line.Text, Start, Len));
    AssertEquals('fore', AFore, Style.Fore);
    AssertTrue('attrs', Style.Attrs = AAttrs);
  end;
end;

procedure TTerminalTest.TestPlain;
begin
  FTerminal.Append('one'#10'two'#10);
  AssertEquals(3, FTerminal.Count);
  AssertEquals('one', FTerminal[0].Text);
  AssertEquals('', FTerminal[2].Text);
  AssertEquals('one'#10'two'#10, FTerminal.PlainText);
  CheckSpan(0, 0, 'one', TermDefault);
  AssertEquals('ok', TerminalPlainText(#27'[32mok'#27'[0m'));
end;

procedure TTerminalTest.TestColors;
begin
  { husky and lint-staged: a red cross, then plain text; the style goes
    on over the line end. }
  FTerminal.Append(#27'[31m✖'#27'[39m eslint'#10#27'[1;93mwarn'#10'still'#27'[m.');
  CheckSpan(0, 0, '✖', 1);
  CheckSpan(0, 1, ' eslint', TermDefault);
  CheckSpan(1, 0, 'warn', 11, [taBold]);
  CheckSpan(2, 0, 'still', 11, [taBold]);
  CheckSpan(2, 1, '.', TermDefault);
  FTerminal.Clear;
  FTerminal.Append(#27'[44;97mx'#27'[49my');
  AssertEquals(4, FTerminal[0].Spans[0].Style.Back);
  CheckSpan(0, 0, 'x', 15);
  AssertEquals(TermDefault, FTerminal[0].Spans[1].Style.Back);
end;

procedure TTerminalTest.TestExtendedColors;
begin
  FTerminal.Append(#27'[38;5;208ma'#27'[38;2;10;20;30mb'#27'[38:2::1:2:3mc' +
    #27'[38:5:42md'#27'[48;2;255;0;0;1me');
  CheckSpan(0, 0, 'a', 208);
  CheckSpan(0, 1, 'b', TermRGB or $0A141E);
  CheckSpan(0, 2, 'c', TermRGB or $010203);
  CheckSpan(0, 3, 'd', 42);
  CheckSpan(0, 4, 'e', 42, [taBold]);
  AssertEquals(TermRGB or $FF0000, FTerminal[0].Spans[4].Style.Back);
end;

procedure TTerminalTest.TestAttributes;
begin
  FTerminal.Append(#27'[1;2;3;4;7;9ma'#27'[22;23mb'#27'[24;27;29mc');
  CheckSpan(0, 0, 'a', TermDefault, [taBold, taDim, taItalic, taUnderline, taInverse,
    taStrike]);
  CheckSpan(0, 1, 'b', TermDefault, [taUnderline, taInverse, taStrike]);
  CheckSpan(0, 2, 'c', TermDefault);
end;

procedure TTerminalTest.TestSplitSequence;
begin
  FTerminal.Append('a'#27);
  FTerminal.Append('[3');
  FTerminal.Append('2mb'#27']8;;https://x');
  FTerminal.Append('.invalid'#27'\c'#27']8;;'#7);
  AssertEquals('abc', FTerminal[0].Text);
  CheckSpan(0, 0, 'a', TermDefault);
  CheckSpan(0, 1, 'bc', 2);
end;

procedure TTerminalTest.TestOtherSequences;
begin
  { Erasing, the cursor hidden and shown, a private SGR, a charset and
    a bell: none of them shows. }
  FTerminal.Append(#27'[2K'#27'[1G'#27'[?25lok'#27'[?25h'#27'[>4;2m'#27'(B!'#7);
  AssertEquals('ok!', FTerminal.PlainText);
  CheckSpan(0, 0, 'ok!', TermDefault);
end;

procedure TTerminalTest.TestReturnTabBackspace;
begin
  FTerminal.Append('Writing objects:  33%'#13'Writing');
  FTerminal.Append(' objects: 100%'#13#10'a'#9'b'#10'ab'#9'c'#10'xö'#8'y');
  AssertEquals('Writing objects: 100%'#10'a       b'#10'ab      c'#10'xy',
    FTerminal.PlainText);
  { A spinner redrawn in color: the old frame's span goes with it. }
  FTerminal.Clear;
  FTerminal.Append(#27'[36m-'#27'[0m'#13#27'[36m\'#27'[0m'#13'done');
  AssertEquals('done', FTerminal.PlainText);
  AssertEquals(1, Length(FTerminal[0].Spans));
  CheckSpan(0, 0, 'done', TermDefault);
end;

procedure TTerminalTest.TestPaletteRGB;
begin
  AssertEquals(0, TermPaletteRGB(16));
  AssertEquals($FFFFFF, TermPaletteRGB(231));
  AssertEquals($FF8700, TermPaletteRGB(208));
  AssertEquals($080808, TermPaletteRGB(232));
  AssertEquals($EEEEEE, TermPaletteRGB(255));
end;

initialization
  RegisterTest(TTerminalTest);
end.
