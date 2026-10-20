{ ---------------------------------------------------------------------------
  The translation view
  ---------------------------------------------------------------------------
  Included by umain.pp. With View > Translations on, a gettext file (.po,
  gittan.pofile) is shown as its entries, each original on the left in
  FEditOld and its translation on the right in Edit, row for row, as the
  side-by-side change view lays out its two sides: the shorter side of
  an entry is padded with blank rows and a blank row parts the entries.
  A fuzzy entry is tinted amber and one without a translation red, on
  both sides, and a fuzzy one's translation has an amber "!" before its
  number. In the change view the entries that changed since the version
  compared against (paired by context and original, ChangedEntries) get
  the diff's green strip, and the navigator and F7 step through them;
  elsewhere, and for a new file, they step through the entries that
  need work. An entry's context stands in brackets above its original,
  dimmed. The numbers are the lines of the file the original and the
  translation start on. A changed file shows its new version (the old
  one when it is deleted), a file from File > Open its text on disk; a
  file with a conflict keeps the change view, since its markers would
  break the entries. }

{ Whether the two editors stand side by side: the side-by-side change
  view and the translation view. }
function TForm1.SidesShown: boolean;
begin
  Result := (FSideBySide and (FView = gvChanges)) or (FView = gvTranslation);
end;

{ Whether the view is of a file in the tree, which F7 steps on from. }
function TForm1.ShowsChangedFile: boolean;
begin
  Result := (FView in [gvChanges, gvImage]) or
    ((FView in [gvTranslation, gvBinary]) and (FCurrentPath <> ''));
end;

const
  FuzzyMark = '! ';

{ Fills the two editors with the entries of AText, a .po file. With
  ACompare the entries that changed since AOld, the version compared
  against, get the diff's strip and are the blocks the navigator steps
  through; without, the fuzzy and untranslated entries are. }
procedure TForm1.ShowTranslation(const AText, AOld: string; ACompare: boolean);
var
  Rows: TGittanPoRows;
  Entries: TGittanPoEntries;
  EntryChanged: TBooleanDynArray;
  Count, Fuzzy, Untranslated, Edited, i, Row: integer;
  Starts: boolean;
  Kinds: TIntegerDynArray;
  Decor: PATGutterDecorItem;
  Part: TATLinePart;

  function Joined(const ALines: TStringArray): string;
  var
    Lines: TStringList;
    j: integer;
  begin
    Lines := TStringList.Create;
    try
      for j := 0 to High(ALines) do
        Lines.Add(ALines[j]);
      Result := Lines.Text;
    finally
      Lines.Free;
    end;
  end;

begin
  AbandonHistoryJob;
  Entries := ParsePo(AText);
  Rows := PoRows(Entries, Count, Fuzzy, Untranslated);
  FPoStats := Format(rsTranslationStats, [Count, Fuzzy, Untranslated]);
  EntryChanged := nil;
  if ACompare then
    EntryChanged := ChangedEntries(ParsePo(AOld), Entries);
  FView := gvTranslation;
  FManualLexer := False;
  FSymbolBar.Visible := False;
  ApplyLayout;
  ShowText(FEditOld, Joined(Rows.Left), nil);
  ShowText(Edit, Joined(Rows.Right), nil);
  SetLength(Kinds, Length(Rows.Kinds));
  for i := 0 to High(Rows.Kinds) do
  begin
    case Rows.Kinds[i] of
      prFuzzy: Kinds[i] := bmFuzzy;
      prUntranslated: Kinds[i] := bmUntranslated;
      else
        Kinds[i] := 0;
    end;
    if Kinds[i] <> 0 then
    begin
      MarkRow(FEditOld, i, Kinds[i]);
      MarkRow(Edit, i, Kinds[i]);
    end;
  end;
  { The context, which a Lazarus project fills with the resource
    string's name, is dimmed so the original stands out. }
  InitLinePart(Part);
  Part.ColorFont := FEditOld.Colors.GutterFont;
  for i := 0 to High(Rows.Context) do
    if Rows.Context[i] and (FEditOld.Strings.LinesLen[i] > 0) then
      FEditOld.Attribs.Add(Point(0, i), Point(FEditOld.Strings.LinesLen[i], 0),
        TATMarkerTags.Init(tagPoContext, 0), @Part);
  SetRowNumbers(FEditOld, Rows.LeftLines, Kinds);
  SetRowNumbers(Edit, Rows.RightLines, Kinds);
  { A fuzzy entry's translation has a "!" before its number. }
  for i := 0 to Edit.GutterDecor.Count - 1 do
  begin
    Decor := Edit.GutterDecor.ItemPtr(i);
    Row := Decor^.Data.LineNum;
    if (Kinds[Row] = bmFuzzy) and ((Row = 0) or (Kinds[Row - 1] <> bmFuzzy)) then
      Decor^.Data.TextAll := FuzzyMark + Decor^.Data.TextAll;
  end;
  UpdateNumberWidth(Edit);
  { The blocks: the first row of every changed entry, which gets the
    diff's strip on the new side, or of every entry that needs work. }
  FPoBlocks := nil;
  Edited := 0;
  for i := 0 to High(Rows.Entries) do
  begin
    Row := Rows.Entries[i];
    if Row < 0 then
      Continue;
    Starts := (i = 0) or (Rows.Entries[i - 1] <> Row);
    if ACompare then
    begin
      if not EntryChanged[Row] then
        Continue;
      Edit.Strings.LinesState[i] := TATLineState.Added;
    end
    else if Kinds[i] = 0 then
      Continue;
    if Starts then
    begin
      SetLength(FPoBlocks, Length(FPoBlocks) + 1);
      FPoBlocks[High(FPoBlocks)] := i;
      Inc(Edited);
    end;
  end;
  if ACompare then
    FPoStats := Format(rsTranslationChanged, [Edited]) + FPoStats;
  FEditOld.LineTop := 0;
  UpdateChangeNav;
  ShowEditor;
  SyncOldSide;
end;

{ A changed .po file in the translation view: the version the change
  view would show on its new side, the old one when the file is gone. }
procedure TForm1.ShowTranslationChanges(const APath: string);
var
  OldRef, NewRef: string;
  Data, OldData: RawByteString;
  HasOld, HasNew: boolean;
begin
  FRepo.DiffSides(OldRef, NewRef);
  HasOld := FRepo.FileBlob(APath, OldRef, OldData);
  HasNew := FRepo.FileBlob(APath, NewRef, Data);
  FTranslationFile := '';
  { A new file has nothing to compare with, and a deleted one shows its
    old version. }
  if HasNew then
    ShowTranslation(Data, OldData, HasOld)
  else
    ShowTranslation(OldData, '', False);
  FSummary.Selected := APath;
  Edit.FileName := IncludeTrailingPathDelimiter(FRepo.Root) +
    SetDirSeparators(APath);
  UpdateStatus;
end;

{ A .po file from File > Open in the translation view. }
procedure TForm1.ShowTranslationFile(const AFileName: string);
var
  Stream: TStringStream;
begin
  Stream := TStringStream.Create('');
  try
    try
      Stream.LoadFromFile(AFileName);
    except
      on E: Exception do
      begin
        StatusNote(E.Message, True);
        Exit;
      end;
    end;
    FHeader.SetFile(AFileName, -1);
    FSummary.Selected := '';
    FCurrentPath := '';
    FTranslationFile := AFileName;
    ShowTranslation(Stream.DataString, '', False);
  finally
    Stream.Free;
  end;
  Edit.FileName := AFileName;
  UpdateStatus;
  UpdateCaption;
end;

{ View > Translations: the shown .po file is shown again the other way. }
procedure TForm1.MenuTranslationsClick(Sender: TObject);
begin
  FTranslations := not FTranslations;
  FTranslationsItem.Checked := FTranslations;
  if (FView in [gvChanges, gvTranslation]) and (FCurrentPath <> '') then
    ShowChanges(FCurrentPath)
  else if FView = gvTranslation then
    OpenFile(FTranslationFile)
  else if (FView = gvFile) and IsPoPath(Edit.FileName) then
    OpenFile(Edit.FileName);
  UpdatePreviewToggle;
end;
