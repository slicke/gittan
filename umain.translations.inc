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
  number, so the navigator and F7 step through the entries that
  need work. The numbers are the lines of the file the original and the
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

{ Fills the two editors with the entries of AText, a .po file. }
procedure TForm1.ShowTranslation(const AText: string);
var
  Rows: TGittanPoRows;
  Count, Fuzzy, Untranslated, i, Row: integer;
  Kinds: TIntegerDynArray;
  Decor: PATGutterDecorItem;

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
  Rows := PoRows(ParsePo(AText), Count, Fuzzy, Untranslated);
  FPoStats := Format(rsTranslationStats, [Count, Fuzzy, Untranslated]);
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
  Data: RawByteString;
begin
  FRepo.DiffSides(OldRef, NewRef);
  if not FRepo.FileBlob(APath, NewRef, Data) and
    not FRepo.FileBlob(APath, OldRef, Data) then
    Data := '';
  FTranslationFile := '';
  ShowTranslation(Data);
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
    ShowTranslation(Stream.DataString);
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
end;
