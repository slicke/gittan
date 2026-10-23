unit gittan.terminal;

{** Terminal text: what a program writes for a terminal, such as a git
  hook run with FORCE_COLOR, turned into lines of text with the colors
  and the bold, underline and the like its escape sequences ask for, as
  a terminal shows them, for a control to draw (TGittanConsole) or to
  copy without the sequences (PlainText).

  A carriage return starts the line over, as AppendTerminalText does,
  a tab goes to the next column that is a multiple of 8 and a backspace
  takes the character before it away. SGR sequences (ESC [ ... m) set
  the style: the 16 colors, the 256 of xterm, 24-bit ones (with ";" or
  ":" between the numbers), bold, dim, italic, underline, inverse and
  strike. Every other CSI sequence (cursor moves, erasing), OSC strings
  (titles, hyperlinks), the other ESC sequences and control characters
  are left out. Text comes in pieces with Append, and a sequence cut
  between two pieces is read on in the next. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

const
  {** The color of the view the text is drawn in, its text or its
    background. }
  TermDefault = -1;
  {** A color with this bit holds $RRGGBB in its low 24 bits; one
    without it from 0 to 255 is the xterm palette's: 0 to 7 the
    colors, 8 to 15 their bright ones, then the 6x6x6 cube and the 24
    grays. }
  TermRGB = $1000000;

type
  TGittanTermAttr = (taBold, taDim, taItalic, taUnderline, taInverse, taStrike);
  TGittanTermAttrs = set of TGittanTermAttr;

  TGittanTermStyle = record
    Fore, Back: longint;
    Attrs: TGittanTermAttrs;
  end;

  {** Len bytes of a line's Text from Start (1-based) in one style. }
  TGittanTermSpan = record
    Start, Len: integer;
    Style: TGittanTermStyle;
  end;

  {** A line, without its line end, and its spans, which cover Text in
    order. }
  TGittanTermLine = record
    Text: string;
    Spans: array of TGittanTermSpan;
  end;

  { TGittanTerminal }

  TGittanTerminal = class
  private
    type
    TState = (tsText, tsEsc, tsCsi, tsString, tsStringEsc, tsCharset);
  private
    FLines: array of TGittanTermLine;
    FCount: integer;
    FStyle: TGittanTermStyle;
    FState: TState;
    FParams: string;
    FIntermediate, FReturn: boolean;
    { The characters (not bytes) in the last line, for tabs. }
    FColumn: integer;
    function GetLine(AIndex: integer): TGittanTermLine;
    procedure NewLine;
    procedure ClearLine;
    procedure AddText(const AText: string);
    procedure DeleteLastChar;
    procedure ApplySgr(const AParams: string);
  public
    constructor Create;
    procedure Clear;
    {** Reads AChunk on from where the text so far ended. }
    procedure Append(const AChunk: string);
    {** The lines; there is always one, the last perhaps empty. }
    property Count: integer read FCount;
    property Lines[AIndex: integer]: TGittanTermLine read GetLine; default;
    {** The lines' text with #10 between them, no sequences. }
    function PlainText: string;
  end;

{** The style of text no sequence has touched. }
function DefaultTermStyle: TGittanTermStyle;

function SameTermStyle(const A, B: TGittanTermStyle): boolean;

{** AText as a terminal shows it, without its escape sequences. }
function TerminalPlainText(const AText: string): string;

{** The $RRGGBB of xterm palette color AIndex from 16 to 255, the cube
  and the grays; the first 16 are the view's to choose. }
function TermPaletteRGB(AIndex: integer): longint;

implementation

uses
  Math;

const
  TabSize = 8;

function DefaultTermStyle: TGittanTermStyle;
begin
  Result.Fore := TermDefault;
  Result.Back := TermDefault;
  Result.Attrs := [];
end;

function SameTermStyle(const A, B: TGittanTermStyle): boolean;
begin
  Result := (A.Fore = B.Fore) and (A.Back = B.Back) and (A.Attrs = B.Attrs);
end;

function TerminalPlainText(const AText: string): string;
var
  Terminal: TGittanTerminal;
begin
  Terminal := TGittanTerminal.Create;
  try
    Terminal.Append(AText);
    Result := Terminal.PlainText;
  finally
    Terminal.Free;
  end;
end;

function TermPaletteRGB(AIndex: integer): longint;

  function Level(V: integer): integer;
  begin
    if V = 0 then
      Result := 0
    else
      Result := 55 + 40 * V;
  end;

var
  N, G: integer;
begin
  if AIndex >= 232 then
  begin
    G := 8 + 10 * (Min(AIndex, 255) - 232);
    Exit((G shl 16) or (G shl 8) or G);
  end;
  N := Max(AIndex, 16) - 16;
  Result := (Level(N div 36) shl 16) or (Level(N div 6 mod 6) shl 8) or Level(N mod 6);
end;

{ TGittanTerminal }

constructor TGittanTerminal.Create;
begin
  inherited Create;
  Clear;
end;

procedure TGittanTerminal.Clear;
begin
  FLines := nil;
  FCount := 0;
  FStyle := DefaultTermStyle;
  FState := tsText;
  FParams := '';
  FReturn := False;
  NewLine;
end;

function TGittanTerminal.GetLine(AIndex: integer): TGittanTermLine;
begin
  Result := FLines[AIndex];
end;

procedure TGittanTerminal.NewLine;
begin
  if FCount = Length(FLines) then
    SetLength(FLines, Max(16, 2 * FCount));
  FLines[FCount].Text := '';
  FLines[FCount].Spans := nil;
  Inc(FCount);
  FColumn := 0;
end;

procedure TGittanTerminal.ClearLine;
begin
  FLines[FCount - 1].Text := '';
  FLines[FCount - 1].Spans := nil;
  FColumn := 0;
end;

{ To the last line in the current style, the last span made longer when
  it has the style already. }
procedure TGittanTerminal.AddText(const AText: string);
var
  i, N: integer;
begin
  if AText = '' then
    Exit;
  with FLines[FCount - 1] do
  begin
    N := Length(Spans);
    if (N > 0) and SameTermStyle(Spans[N - 1].Style, FStyle) then
      Inc(Spans[N - 1].Len, Length(AText))
    else
    begin
      SetLength(Spans, N + 1);
      Spans[N].Start := Length(Text) + 1;
      Spans[N].Len := Length(AText);
      Spans[N].Style := FStyle;
    end;
    Text := Text + AText;
  end;
  for i := 1 to Length(AText) do
    if (Ord(AText[i]) and $C0) <> $80 then
      Inc(FColumn);
end;

{ The last character with its UTF-8 continuation bytes, out of the text
  and its last span. }
procedure TGittanTerminal.DeleteLastChar;
var
  Cut, N: integer;
begin
  with FLines[FCount - 1] do
  begin
    Cut := Length(Text);
    if Cut = 0 then
      Exit;
    while (Cut > 1) and ((Ord(Text[Cut]) and $C0) = $80) do
      Dec(Cut);
    N := Length(Text) - Cut + 1;
    SetLength(Text, Cut - 1);
    while N > 0 do
    begin
      if Spans[High(Spans)].Len <= N then
      begin
        Dec(N, Spans[High(Spans)].Len);
        SetLength(Spans, Length(Spans) - 1);
      end
      else
      begin
        Dec(Spans[High(Spans)].Len, N);
        N := 0;
      end;
    end;
  end;
  Dec(FColumn);
end;

procedure TGittanTerminal.ApplySgr(const AParams: string);
var
  Parts, Subs: TStringArray;
  i: integer;

  function Num(const S: string): integer;
  begin
    Result := StrToIntDef(S, 0);
  end;

  function Channel(const S: string): longint;
  begin
    Result := EnsureRange(Num(S), 0, 255);
  end;

  { 38 and 48 with ";" between the numbers: 5;n or 2;r;g;b after them,
    which i is moved past; TermDefault when they are not there. }
  function Extended: longint;
  begin
    Result := TermDefault;
    if i + 1 > High(Parts) then
      Exit;
    case Num(Parts[i + 1]) of
      5:
        if i + 2 <= High(Parts) then
        begin
          Result := Channel(Parts[i + 2]);
          Inc(i, 2);
        end;
      2:
        if i + 4 <= High(Parts) then
        begin
          Result := TermRGB or (Channel(Parts[i + 2]) shl 16) or
            (Channel(Parts[i + 3]) shl 8) or Channel(Parts[i + 4]);
          Inc(i, 4);
        end;
    end;
  end;

  { The same with ":": 38:5:n, 38:2:r:g:b or 38:2:<color space>:r:g:b. }
  function ExtendedSubs: longint;
  var
    First: integer;
  begin
    Result := TermDefault;
    if Length(Subs) < 3 then
      Exit;
    case Num(Subs[1]) of
      5: Result := Channel(Subs[2]);
      2:
        begin
          if Length(Subs) >= 6 then
            First := 3
          else
            First := 2;
          if First + 2 <= High(Subs) then
            Result := TermRGB or (Channel(Subs[First]) shl 16) or
              (Channel(Subs[First + 1]) shl 8) or Channel(Subs[First + 2]);
        end;
    end;
  end;

var
  Code: integer;
begin
  Parts := AParams.Split([';']);
  if Length(Parts) = 0 then
  begin
    FStyle := DefaultTermStyle;
    Exit;
  end;
  i := 0;
  while i <= High(Parts) do
  begin
    if Pos(':', Parts[i]) > 0 then
    begin
      Subs := Parts[i].Split([':']);
      case Num(Subs[0]) of
        38: FStyle.Fore := ExtendedSubs;
        48: FStyle.Back := ExtendedSubs;
        4: if (Length(Subs) > 1) and (Num(Subs[1]) = 0) then
            Exclude(FStyle.Attrs, taUnderline)
          else
            Include(FStyle.Attrs, taUnderline);
      end;
      Inc(i);
      Continue;
    end;
    Code := Num(Parts[i]);
    case Code of
      0: FStyle := DefaultTermStyle;
      1: Include(FStyle.Attrs, taBold);
      2: Include(FStyle.Attrs, taDim);
      3: Include(FStyle.Attrs, taItalic);
      4: Include(FStyle.Attrs, taUnderline);
      7: Include(FStyle.Attrs, taInverse);
      9: Include(FStyle.Attrs, taStrike);
      22: FStyle.Attrs := FStyle.Attrs - [taBold, taDim];
      23: Exclude(FStyle.Attrs, taItalic);
      24: Exclude(FStyle.Attrs, taUnderline);
      27: Exclude(FStyle.Attrs, taInverse);
      29: Exclude(FStyle.Attrs, taStrike);
      30..37: FStyle.Fore := Code - 30;
      38: FStyle.Fore := Extended;
      39: FStyle.Fore := TermDefault;
      40..47: FStyle.Back := Code - 40;
      48: FStyle.Back := Extended;
      49: FStyle.Back := TermDefault;
      90..97: FStyle.Fore := Code - 90 + 8;
      100..107: FStyle.Back := Code - 100 + 8;
    end;
    Inc(i);
  end;
end;

procedure TGittanTerminal.Append(const AChunk: string);
var
  i, RunStart: integer;
  C: char;
begin
  i := 1;
  while i <= Length(AChunk) do
  begin
    C := AChunk[i];
    case FState of
      tsText:
        begin
          if FReturn and (C <> #10) and (C <> #13) then
          begin
            FReturn := False;
            ClearLine;
          end;
          case C of
            #10:
              begin
                FReturn := False;
                NewLine;
              end;
            #13: FReturn := True;
            #9: AddText(StringOfChar(' ', TabSize - FColumn mod TabSize));
            #8: if FColumn > 0 then
                DeleteLastChar;
            #27: FState := tsEsc;
            #0..#7, #11, #12, #14..#26, #28..#31, #127: ;
            else
            begin
              { The printable run at once. }
              RunStart := i;
              while (i < Length(AChunk)) and (AChunk[i + 1] >= ' ') and
                (AChunk[i + 1] <> #127) do
                Inc(i);
              AddText(Copy(AChunk, RunStart, i - RunStart + 1));
            end;
          end;
        end;
      tsEsc:
        case C of
          '[':
            begin
              FState := tsCsi;
              FParams := '';
              FIntermediate := False;
            end;
          ']', 'P', 'X', '^', '_': FState := tsString;
          '(', ')', '*', '+', '-', '.', '/', '#', '%': FState := tsCharset;
          else
            FState := tsText;
        end;
      tsCsi:
        case C of
          '0'..'?': FParams := FParams + C;
          ' '..'/': FIntermediate := True;
          '@'..'~':
            begin
              FState := tsText;
              if (C = 'm') and not FIntermediate and
                ((FParams = '') or not (FParams[1] in ['<', '=', '>', '?'])) then
                ApplySgr(FParams);
            end;
          #27: FState := tsEsc;
          else
            FState := tsText;
        end;
      { An OSC, DCS and the like end at BEL or ESC \. }
      tsString:
        case C of
          #7: FState := tsText;
          #27: FState := tsStringEsc;
        end;
      tsStringEsc:
        if C = '\' then
          FState := tsText
        else if C = '[' then
        begin
          FState := tsCsi;
          FParams := '';
          FIntermediate := False;
        end
        else
          FState := tsText;
      tsCharset: FState := tsText;
    end;
    Inc(i);
  end;
end;

function TGittanTerminal.PlainText: string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to FCount - 1 do
  begin
    if i > 0 then
      Result := Result + #10;
    Result := Result + FLines[i].Text;
  end;
end;

end.
