unit gittan.pofile;

{** gettext translation files (.po): the entries read from the text, and
  the rows of the translation view, which shows every entry's original
  text on the left and its translation on the right. The unit has no LCL
  dependency and is tested in tests/testpofile.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math;

type
  {** One entry of a .po file. The strings are unescaped and joined from
    their continuation lines. Strs holds msgstr, or msgstr[0], msgstr[1]
    and so on for an entry with a plural; StrLines the 1-based line of
    each one's keyword, IdLine that of msgid. }
  TGittanPoEntry = record
    Context, Id, IdPlural: string;
    HasContext, HasPlural, Fuzzy, Obsolete: boolean;
    Strs: array of string;
    StrLines: TIntegerDynArray;
    IdLine: integer;
  end;
  TGittanPoEntries = array of TGittanPoEntry;

  {** What a row of the translation view stands for: a line of an entry,
    of a fuzzy one or of one that is not (fully) translated, or the
    blank row between two entries. }
  TGittanPoRowKind = (prEntry, prFuzzy, prUntranslated, prSeparator);

  {** The two sides of the translation view, row for row: the text, the
    line of the file a row starts (0 for none) and the kind of each, and
    which rows of the left side hold a context, which the view dims. The
    shorter side of an entry is padded with blank rows. }
  TGittanPoRows = record
    Left, Right: TStringArray;
    LeftLines, RightLines: TIntegerDynArray;
    Kinds: array of TGittanPoRowKind;
    Context: array of boolean;
    {** The index in the entries of the entry each row belongs to, -1
      for a separator. }
    Entries: TIntegerDynArray;
  end;

{** Whether APath is a gettext translation file, by its extension. A
  template (.pot) has no translations to show and is not one. }
function IsPoPath(const APath: string): boolean;

{** A .po string's escapes (\n, \t, \r, \", \\ ...) as the characters
  they stand for. AText is what stands between the quotes. }
function PoUnescape(const AText: string): string;

{** The entries of AText, a .po file, in the order they come, the
  header (the entry with an empty msgid) and obsolete ones (#~)
  included. }
function ParsePo(const AText: string): TGittanPoEntries;

{** Whether AEntry is the header, the entry that holds the file's
  metadata. }
function IsPoHeader(const AEntry: TGittanPoEntry): boolean;

{** Whether every form of AEntry's translation is there. }
function IsTranslated(const AEntry: TGittanPoEntry): boolean;

{** The rows of the translation view for AEntries, the header and the
  obsolete entries left out: per entry its context (in brackets) and
  original, its plural after it, on the left, its translation on the
  right, each form of a plural marked "[n] ", with a separator row
  between entries. ACount, AFuzzy and AUntranslated count the entries
  shown. }
function PoRows(const AEntries: TGittanPoEntries;
  out ACount, AFuzzy, AUntranslated: integer): TGittanPoRows;

{** Which entries of ANew changed since AOld, one flag per entry of ANew:
  an entry is paired with the one of AOld with the same context and
  original, and it changed when there is none, or when its plural, its
  translation or its fuzzy flag differ. }
function ChangedEntries(const AOld, ANew: TGittanPoEntries): TBooleanDynArray;

implementation

uses
  gittan.textfile;

function IsPoPath(const APath: string): boolean;
begin
  Result := LowerCase(ExtractFileExt(APath)) = '.po';
end;

function PoUnescape(const AText: string): string;
begin
  Result := UnescapeC(AText);
end;

{ What stands between the first and the last quote of ALine, unescaped;
  '' without a quoted string. }
function QuotedPart(const ALine: string): string;
var
  First, Last: integer;
begin
  Result := '';
  First := Pos('"', ALine);
  if First = 0 then
    Exit;
  Last := Length(ALine);
  while (Last > First) and (ALine[Last] <> '"') do
    Dec(Last);
  if Last > First then
    Result := PoUnescape(Copy(ALine, First + 1, Last - First - 1));
end;

{ Whether the flags of a "#," line hold fuzzy. }
function HasFuzzyFlag(const AFlags: string): boolean;
var
  Parts: TStringArray;
  i: integer;
begin
  Result := False;
  Parts := AFlags.Split([',']);
  for i := 0 to High(Parts) do
    if Trim(Parts[i]) = 'fuzzy' then
      Exit(True);
end;

type
  TPoField = (pfNone, pfContext, pfId, pfPlural, pfStr);

function ParsePo(const AText: string): TGittanPoEntries;
var
  Lines: TStringList;
  E: TGittanPoEntry;
  HasId, Started: boolean;
  Field: TPoField;
  StrIndex, n, i, k: integer;
  Line, Rest: string;

  procedure Finish;
  begin
    if HasId then
    begin
      if Length(E.Strs) = 0 then
      begin
        SetLength(E.Strs, 1);
        SetLength(E.StrLines, 1);
        E.Strs[0] := '';
        E.StrLines[0] := 0;
      end;
      SetLength(Result, n + 1);
      Result[n] := E;
      Inc(n);
    end;
    E := Default(TGittanPoEntry);
    HasId := False;
    Started := False;
    Field := pfNone;
  end;

  procedure Append(const AValue: string);
  begin
    case Field of
      pfContext: E.Context := E.Context + AValue;
      pfId: E.Id := E.Id + AValue;
      pfPlural: E.IdPlural := E.IdPlural + AValue;
      pfStr: E.Strs[StrIndex] := E.Strs[StrIndex] + AValue;
    end;
  end;

  { A keyword or a comment after the translation starts the next entry,
    also when no blank line comes between. }
  procedure Begin_;
  begin
    if Field = pfStr then
      Finish;
    Started := True;
  end;

  procedure StartStr(AIndex, ALine: integer);
  begin
    Begin_;
    if AIndex > High(E.Strs) then
    begin
      SetLength(E.Strs, AIndex + 1);
      SetLength(E.StrLines, AIndex + 1);
    end;
    E.StrLines[AIndex] := ALine;
    StrIndex := AIndex;
    Field := pfStr;
  end;

begin
  Result := nil;
  n := 0;
  E := Default(TGittanPoEntry);
  HasId := False;
  Started := False;
  Field := pfNone;
  StrIndex := 0;
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[i]);
      if Line = '' then
      begin
        if Started then
          Finish;
        Continue;
      end;
      { An obsolete entry keeps its lines behind "#~"; its previous
        strings ("#~|") are comments. }
      if Copy(Line, 1, 2) = '#~' then
      begin
        Line := Trim(Copy(Line, 3, MaxInt));
        if (Line = '') or (Line[1] = '|') then
        begin
          Begin_;
          Continue;
        end;
        if Line[1] <> '"' then
          Begin_;
        E.Obsolete := True;
      end
      else if Line[1] = '#' then
      begin
        Begin_;
        if Copy(Line, 1, 2) = '#,' then
          E.Fuzzy := E.Fuzzy or HasFuzzyFlag(Copy(Line, 3, MaxInt));
        Continue;
      end;
      if Line[1] = '"' then
        Append(QuotedPart(Line))
      else if Copy(Line, 1, 7) = 'msgctxt' then
      begin
        Begin_;
        Field := pfContext;
        E.HasContext := True;
        Append(QuotedPart(Line));
      end
      else if Copy(Line, 1, 12) = 'msgid_plural' then
      begin
        Begin_;
        Field := pfPlural;
        E.HasPlural := True;
        Append(QuotedPart(Line));
      end
      else if Copy(Line, 1, 5) = 'msgid' then
      begin
        Begin_;
        Field := pfId;
        HasId := True;
        E.IdLine := i + 1;
        Append(QuotedPart(Line));
      end
      else if Copy(Line, 1, 6) = 'msgstr' then
      begin
        Rest := Copy(Line, 7, MaxInt);
        k := 0;
        if (Rest <> '') and (Rest[1] = '[') then
          k := StrToIntDef(Copy(Rest, 2, Pos(']', Rest) - 2), 0);
        { A form after the first continues the entry it is in. }
        if (Field = pfStr) and (k > 0) then
          Field := pfNone;
        StartStr(k, i + 1);
        Append(QuotedPart(Line));
      end;
    end;
    Finish;
  finally
    Lines.Free;
  end;
end;

function IsPoHeader(const AEntry: TGittanPoEntry): boolean;
begin
  Result := (AEntry.Id = '') and not AEntry.HasContext;
end;

function IsTranslated(const AEntry: TGittanPoEntry): boolean;
var
  i: integer;
begin
  Result := Length(AEntry.Strs) > 0;
  for i := 0 to High(AEntry.Strs) do
    if AEntry.Strs[i] = '' then
      Exit(False);
end;

function PoRows(const AEntries: TGittanPoEntries;
  out ACount, AFuzzy, AUntranslated: integer): TGittanPoRows;
var
  Left, Right: TStringList;
  LeftLines, RightLines: TIntegerDynArray;
  e, i, f, Rows, Base: integer;
  Kind: TGittanPoRowKind;
  Prefix: string;

  { The lines of AText, its last line break leaving no empty line after
    it; one empty line for an empty text. A carriage return would break
    the row in the editor, so it is dropped. }
  procedure AddText(AList: TStringList; var ALines: TIntegerDynArray;
    const AText, APrefix: string; ALine: integer);
  var
    Parts: TStringArray;
    p, First: integer;
  begin
    Parts := StringReplace(AText, #13, '', [rfReplaceAll]).Split([#10]);
    if (Length(Parts) > 1) and (Parts[High(Parts)] = '') then
      SetLength(Parts, Length(Parts) - 1);
    if Length(Parts) = 0 then
    begin
      SetLength(Parts, 1);
      Parts[0] := '';
    end;
    First := AList.Count;
    for p := 0 to High(Parts) do
    begin
      if p = 0 then
        AList.Add(APrefix + Parts[p])
      else
        AList.Add(Parts[p]);
      SetLength(ALines, AList.Count);
      ALines[AList.Count - 1] := 0;
    end;
    ALines[First] := ALine;
  end;

begin
  Result := Default(TGittanPoRows);
  ACount := 0;
  AFuzzy := 0;
  AUntranslated := 0;
  Left := TStringList.Create;
  Right := TStringList.Create;
  try
    LeftLines := nil;
    RightLines := nil;
    for e := 0 to High(AEntries) do
    begin
      if IsPoHeader(AEntries[e]) or AEntries[e].Obsolete then
        Continue;
      if not IsTranslated(AEntries[e]) then
      begin
        Kind := prUntranslated;
        Inc(AUntranslated);
      end
      else if AEntries[e].Fuzzy then
      begin
        Kind := prFuzzy;
        Inc(AFuzzy);
      end
      else
        Kind := prEntry;
      if ACount > 0 then
      begin
        Left.Add('');
        Right.Add('');
        SetLength(LeftLines, Left.Count);
        SetLength(RightLines, Right.Count);
        LeftLines[Left.Count - 1] := 0;
        RightLines[Right.Count - 1] := 0;
        SetLength(Result.Kinds, Left.Count);
        Result.Kinds[Left.Count - 1] := prSeparator;
        SetLength(Result.Entries, Left.Count);
        Result.Entries[Left.Count - 1] := -1;
      end;
      Inc(ACount);
      Base := Left.Count;
      if AEntries[e].HasContext then
      begin
        AddText(Left, LeftLines, '[' + AEntries[e].Context + ']', '', 0);
        { The context's rows are marked through their objects. }
        for i := Base to Left.Count - 1 do
          Left.Objects[i] := Left;
      end;
      AddText(Left, LeftLines, AEntries[e].Id, '', AEntries[e].IdLine);
      if AEntries[e].HasPlural then
        AddText(Left, LeftLines, AEntries[e].IdPlural, '', 0);
      for f := 0 to High(AEntries[e].Strs) do
      begin
        if AEntries[e].HasPlural then
          Prefix := '[' + IntToStr(f) + '] '
        else
          Prefix := '';
        AddText(Right, RightLines, AEntries[e].Strs[f], Prefix,
          AEntries[e].StrLines[f]);
      end;
      { The shorter side is padded to the longer one. }
      Rows := Max(Left.Count, Right.Count);
      while Left.Count < Rows do
      begin
        Left.Add('');
        SetLength(LeftLines, Left.Count);
        LeftLines[Left.Count - 1] := 0;
      end;
      while Right.Count < Rows do
      begin
        Right.Add('');
        SetLength(RightLines, Right.Count);
        RightLines[Right.Count - 1] := 0;
      end;
      SetLength(Result.Kinds, Rows);
      SetLength(Result.Entries, Rows);
      for i := Base to Rows - 1 do
      begin
        Result.Kinds[i] := Kind;
        Result.Entries[i] := e;
      end;
    end;
    Result.Left := Left.ToStringArray;
    Result.Right := Right.ToStringArray;
    Result.LeftLines := LeftLines;
    Result.RightLines := RightLines;
    SetLength(Result.Context, Left.Count);
    for i := 0 to Left.Count - 1 do
      Result.Context[i] := Left.Objects[i] <> nil;
  finally
    Left.Free;
    Right.Free;
  end;
end;

{ The key an entry is paired by: its context and its original. A #4
  parts them, as gettext does in its compiled files. }
function EntryKey(const AEntry: TGittanPoEntry): string;
begin
  if AEntry.HasContext then
    Result := AEntry.Context + #4 + AEntry.Id
  else
    Result := AEntry.Id;
end;

function SameEntry(const A, B: TGittanPoEntry): boolean;
var
  i: integer;
begin
  Result := (A.IdPlural = B.IdPlural) and (A.Fuzzy = B.Fuzzy) and
    (Length(A.Strs) = Length(B.Strs));
  if Result then
    for i := 0 to High(A.Strs) do
      if A.Strs[i] <> B.Strs[i] then
        Exit(False);
end;

function ChangedEntries(const AOld, ANew: TGittanPoEntries): TBooleanDynArray;
var
  Keys: TStringList;
  i, k: integer;
begin
  SetLength(Result, Length(ANew));
  Keys := TStringList.Create;
  try
    Keys.CaseSensitive := True;
    Keys.Sorted := True;
    Keys.Duplicates := dupIgnore;
    for i := 0 to High(AOld) do
      if not AOld[i].Obsolete then
        Keys.AddObject(EntryKey(AOld[i]), TObject(PtrInt(i)));
    for i := 0 to High(ANew) do
    begin
      k := Keys.IndexOf(EntryKey(ANew[i]));
      Result[i] := (k < 0) or
        not SameEntry(AOld[PtrInt(Keys.Objects[k])], ANew[i]);
    end;
  finally
    Keys.Free;
  end;
end;

end.
