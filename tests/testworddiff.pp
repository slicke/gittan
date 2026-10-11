unit testworddiff;

{** Tests of gittan.worddiff: the spans that differ between a run of
  deleted lines and the run of added lines after it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.worddiff;

type
  TWordDiffTest = class(TTestCase)
  private
    FLines: TStringList;
    FSpans: TGittanLineSpans;
    procedure Diff(const ALines: array of string; AIgnoreSpace: boolean = False);
    function SpanText(ALine: integer): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestOneWordChanged;
    procedure TestUnchangedAndAddedOnlyLinesHaveNoSpans;
    procedure TestRewrittenBlockHasNoSpans;
    procedure TestSpaceChangeMarkedUnlessIgnored;
    procedure TestEditedPhraseIsOneSpan;
    procedure TestJoinedLines;
    procedure TestSpansCountUtf16Units;
    procedure TestEmptyInput;
  end;

implementation

procedure TWordDiffTest.SetUp;
begin
  FLines := TStringList.Create;
end;

procedure TWordDiffTest.TearDown;
begin
  FLines.Free;
  FSpans := nil;
end;

procedure TWordDiffTest.Diff(const ALines: array of string; AIgnoreSpace: boolean);
var
  S: string;
begin
  FLines.Clear;
  for S in ALines do
    FLines.Add(S);
  WordDiff(FLines, AIgnoreSpace, FSpans);
  AssertEquals('one spans entry per line', FLines.Count, Length(FSpans));
end;

{ The spans of a line as "start:len" pairs, comma separated. }
function TWordDiffTest.SpanText(ALine: integer): string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(FSpans[ALine]) do
  begin
    if i > 0 then
      Result := Result + ',';
    Result := Result + Format('%d:%d', [FSpans[ALine][i].Start, FSpans[ALine][i].Len]);
  end;
end;

procedure TWordDiffTest.TestOneWordChanged;
begin
  Diff(['-foo bar baz', '+foo qux baz']);
  AssertEquals('4:3', SpanText(0));
  AssertEquals('4:3', SpanText(1));
end;

procedure TWordDiffTest.TestUnchangedAndAddedOnlyLinesHaveNoSpans;
begin
  Diff([' same', '+new line', ' same again', '-gone']);
  AssertEquals('', SpanText(0));
  AssertEquals('', SpanText(1));
  AssertEquals('', SpanText(2));
  AssertEquals('', SpanText(3));
end;

procedure TWordDiffTest.TestRewrittenBlockHasNoSpans;
begin
  Diff(['-alpha beta gamma', '+one two three four']);
  AssertEquals('nothing in common: no marks', '', SpanText(0));
  AssertEquals('', SpanText(1));
end;

procedure TWordDiffTest.TestSpaceChangeMarkedUnlessIgnored;
begin
  Diff(['-a  b', '+a b']);
  AssertEquals('1:2', SpanText(0));
  AssertEquals('1:1', SpanText(1));
  Diff(['-a  b', '+a b'], True);
  AssertEquals('', SpanText(0));
  AssertEquals('', SpanText(1));
end;

procedure TWordDiffTest.TestEditedPhraseIsOneSpan;
begin
  { Two words changed next to each other are one mark, bridged over the
    matched space between them. }
  Diff(['-the quick brown fox jumps', '+the slow red fox jumps']);
  AssertEquals('4:11', SpanText(0));
  AssertEquals('4:8', SpanText(1));
end;

procedure TWordDiffTest.TestJoinedLines;
begin
  { The runs are compared as one token sequence each, so the words of
    two deleted lines still match the one added line; only the space
    that joined them is new. }
  Diff(['-ab', '-cd', '+ab cd']);
  AssertEquals('', SpanText(0));
  AssertEquals('', SpanText(1));
  AssertEquals('2:1', SpanText(2));
end;

procedure TWordDiffTest.TestSpansCountUtf16Units;
begin
  { "åäö" is three UTF-16 units but six UTF-8 bytes; the editor counts
    columns in UTF-16 units. }
  Diff(['-åäö bar', '+åäö baz']);
  AssertEquals('4:3', SpanText(0));
  AssertEquals('4:3', SpanText(1));
end;

procedure TWordDiffTest.TestEmptyInput;
begin
  Diff([]);
  AssertEquals(0, Length(FSpans));
end;

initialization
  RegisterTest(TWordDiffTest);
end.
