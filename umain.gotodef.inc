{ ---------------------------------------------------------------------------
  Go to Definition, Go to Symbol, hover
  ---------------------------------------------------------------------------
  Included by umain.pp. The lexer's code tree (the ranges EControl marks
  DisplayInTree: functions, methods, classes, sections) is the only
  symbol table there is. CodeTree reads it from an adapter as a flat
  list of symbols (gittan.symbols). A word is looked up among them, in
  the text the caret or mouse is in first and then in the other changed
  files of the repository through the symbol index (umain.index.inc).
  A hit in another file shows it, through the tree when it is a changed
  file, and the lookup runs again on the text the editor shows, so the
  rows of the change view (deleted lines kept, unchanged lines hidden)
  need no mapping. The word under the mouse shows its definition's line in a
  hint after a pause, and is underlined as a link while Cmd is held. }

{ The adapters report the start and the end of a parse; the adapter's
  Tag keeps whether its data is complete (1) or not (0), which
  WaitForParse polls. The end is reported from the message loop, after
  the parser's public data is updated. }
procedure TForm1.AdapterParseBegin(Sender: TObject);
begin
  TComponent(Sender).Tag := 0;
end;

procedure TForm1.AdapterParseDone(Sender: TObject; ATime: integer);
begin
  TComponent(Sender).Tag := 1;
end;

{ Waits for the adapter's background parse of its text. }
procedure WaitForParse(AAdapter: TATAdapterEControl);
var
  Start: QWord;
begin
  if AAdapter.AnClient = nil then
    Exit;
  Start := GetTickCount64;
  while (AAdapter.Tag = 0) and not Application.Terminated and
    (GetTickCount64 - Start < ParseTimeout) do
  begin
    Sleep(10);
    Application.ProcessMessages;
  end;
end;

{ The word at APos in AEd (the word before it when APos is right after
  one), as the editor's word jumping sees it, with its bounds on the
  line. }
function TForm1.WordAt(AEd: TATSynEdit; APos: TPoint; out AStart, AEnd: integer): string;
var
  S: UnicodeString;
begin
  Result := '';
  AStart := 0;
  AEnd := 0;
  if not AEd.Strings.IsIndexValid(APos.Y) then
    Exit;
  S := AEd.Strings.Lines[APos.Y];
  SFindWordBounds(S, APos.X, AStart, AEnd, AEd.OptNonWordChars);
  if AEnd > AStart then
    Result := UTF8Encode(Copy(S, AStart + 1, AEnd - AStart));
end;

{ Whether R is a range the lexer shows in its code tree, as CudaText
  shows it: with a tree rule, and from the main lexer, not a sub-lexer. }
function InCodeTree(Client: TecClientSyntAnalyzer; R: TecTextRange): boolean;
begin
  Result := (R.Rule <> nil) and R.Rule.DisplayInTree and (R.StartIdx >= 0) and
    (R.Rule.SyntOwner.LexerName = Client.Owner.LexerName);
end;

{ The code tree of AAdapter's text, which AEd shows, as a flat list in
  file order: each range's name on one line, the position of its
  identifier token (the name in its header, else its first token), its
  nesting depth and the text of its row. Waits for the parse. }
function TForm1.CodeTree(AAdapter: TATAdapterEControl; AEd: TATSynEdit): TGittanSymbols;
var
  Client: TecClientSyntAnalyzer;
  R, Outer: TecTextRange;
  Title: string;
  P: TPoint;
  i, Count: integer;
begin
  Result := nil;
  Client := AAdapter.AnClient;
  if Client = nil then
    Exit;
  WaitForParse(AAdapter);
  Count := 0;
  Client.CriSecForData.Enter;
  try
    SetLength(Result, Client.PublicData.FoldRanges.Count);
    for i := 0 to Client.PublicData.FoldRanges.Count - 1 do
    begin
      R := TecTextRange(Client.PublicData.FoldRanges[i]);
      if not InCodeTree(Client, R) then
        Continue;
      Title := Trim(UTF8Encode(Client.GetRangeName(R, Client.PublicData.Tokens)));
      Title := StringReplace(Title, #13, ' ', [rfReplaceAll]);
      Result[Count].Name := StringReplace(Title, #10, ' ', [rfReplaceAll]);
      if R.IdentIdx >= 0 then
        P := Client.PublicData.Tokens._GetItemPtr(R.IdentIdx)^.Range.PointStart
      else
        P := Client.PublicData.Tokens._GetItemPtr(R.StartIdx)^.Range.PointStart;
      Result[Count].Row := P.Y;
      Result[Count].Col := P.X;
      if AEd.Strings.IsIndexValid(P.Y) then
        Result[Count].Line := UTF8Encode(AEd.Strings.Lines[P.Y]);
      Result[Count].Depth := 0;
      Outer := R.Parent;
      while Outer <> nil do
      begin
        if InCodeTree(Client, Outer) then
          Inc(Result[Count].Depth);
        Outer := Outer.Parent;
      end;
      Inc(Count);
    end;
  finally
    Client.CriSecForData.Leave;
  end;
  SetLength(Result, Count);
end;

{ The position of the best symbol of AAdapter's code tree named for
  AWord, Y = -1 when there is none. A symbol at row ASkipRow is left
  out, so a lookup from the definition itself goes on to the other
  files. }
function TForm1.FindDefinition(AAdapter: TATAdapterEControl; AEd: TATSynEdit;
  const AWord: string; ASkipRow: integer): TPoint;
var
  Symbols: TGittanSymbols;
  i: integer;
begin
  Result := Point(0, -1);
  Symbols := CodeTree(AAdapter, AEd);
  i := BestSymbol(Symbols, AWord, ASkipRow);
  if i >= 0 then
    Result := Point(Symbols[i].Col, Symbols[i].Row);
end;

{ Parses the file at AFileName with ALexer in the hidden editor, made on
  the first lookup, and answers its adapter. }
function TForm1.ParseScratch(const AFileName: string; ALexer: TecSyntAnalyzer): TATAdapterEControl;
begin
  if FScratch = nil then
  begin
    FScratch := TATSynEdit.Create(Self);
    FScratch.Visible := False;
    FScratch.Parent := Self;
    FScratchAdapter := TATAdapterEControl.Create(Self);
    FScratchAdapter.AddEditor(FScratch);
    FScratchAdapter.OnParseBegin := @AdapterParseBegin;
    FScratchAdapter.OnParseDone := @AdapterParseDone;
  end;
  FScratchAdapter.Lexer := nil;
  FScratch.LoadFromFile(AFileName, []);
  FScratch.FileName := AFileName;
  SetEditorLexer(FScratch, ALexer);
  Result := FScratchAdapter;
end;

{ The 0-based offset of AWord as a whole word in S, ignoring case, or
  -1. }
function WordPos(const S, AWord: UnicodeString; const ANonWordChars: UnicodeString): integer;
var
  Low, LowWord: UnicodeString;
  p: integer;
begin
  Result := -1;
  Low := UnicodeLowerCase(S);
  LowWord := UnicodeLowerCase(AWord);
  p := Pos(LowWord, Low);
  while p > 0 do
  begin
    if ((p = 1) or not IsCharWord(S[p - 1], ANonWordChars)) and
      ((p + Length(AWord) > Length(S)) or not IsCharWord(S[p + Length(AWord)], ANonWordChars)) then
      Exit(p - 1);
    p := Pos(LowWord, Low, p + 1);
  end;
end;

{ Moves AEd to the word at APos and selects it. A definition on a hidden
  row of the change view opens the gap that hides it; the view is built
  anew then, so the lookup runs again on the new rows. }
procedure TForm1.JumpToDefinition(AEd: TATSynEdit; APos: TPoint; const AWord: string);
var
  S: UnicodeString;
  N1, N2, i: integer;
begin
  if (AEd = Edit) and (FView = gvChanges) and Edit.IsLineFolded(APos.Y) and
    (APos.Y <= High(FRows)) then
  begin
    for i := 0 to High(FRows) do
      if (FRows[i].Line = rowGap) and (FRows[i].GapFrom <= FRows[APos.Y].Line) and
        (FRows[APos.Y].Line <= FRows[i].GapTo) then
      begin
        ExpandGap(FRows[i].GapFrom, FRows[i].GapTo);
        APos := FindDefinition(FAdapter, Edit, AWord, -1);
        if APos.Y < 0 then
          Exit;
        Break;
      end;
  end;
  { The lexer's position is the range's header, which may start with a
    keyword; the name itself is the word on that line. }
  S := AEd.Strings.Lines[APos.Y];
  N1 := WordPos(S, UTF8Decode(AWord), AEd.OptNonWordChars);
  if N1 >= 0 then
    N2 := N1 + Length(AWord)
  else
  begin
    N1 := APos.X;
    N2 := APos.X;
  end;
  { The caret lands after the name, the selection covers it. }
  AEd.DoGotoPos(Point(N2, APos.Y), Point(N1, APos.Y), 10, 5, True,
    TATEditorActionIfFolded.Ignore);
  { The old side follows the new one (SyncOldSide), so a jump in the old
    side scrolls the new side there first. }
  if AEd = FEditOld then
  begin
    Edit.LineTop := FEditOld.LineTop;
    Edit.ColumnLeft := FEditOld.ColumnLeft;
    Edit.Update;
  end;
  SyncOldSide;
  UpdateChangeNav;
end;

{ Go > Go to Definition, and Cmd+click (Ctrl+click elsewhere) in an
  editor: looks the word under the caret up in the text of AEd, then in
  the new side when AEd is the old one, then in the other changed files
  of the repository. }
procedure TForm1.GoToDefinition(AEd: TATSynEdit);
var
  Word, RelPath: string;
  P: TPoint;
  Caret: TATCaretItem;
  N1, N2: integer;
  Symbol: TGittanSymbol;
begin
  if not AEd.Visible or (AEd.Carets.Count = 0) then
    Exit;
  Caret := AEd.Carets[0];
  Word := WordAt(AEd, Point(Caret.PosX, Caret.PosY), N1, N2);
  if Word = '' then
    Exit;
  P := FindDefinition(AdapterOf(AEd), AEd, Word, Caret.PosY);
  if (P.Y >= 0) and not AEd.IsLineFolded(P.Y) then
  begin
    JumpToDefinition(AEd, P, Word);
    Exit;
  end;
  if AEd = FEditOld then
  begin
    P := FindDefinition(FAdapter, Edit, Word, -1);
    if P.Y >= 0 then
    begin
      JumpToDefinition(Edit, P, Word);
      Exit;
    end;
  end
  else if P.Y >= 0 then
  begin
    JumpToDefinition(AEd, P, Word);
    Exit;
  end;
  StatusBar.SimpleText := Format(rsLookingFor, [Word]);
  if FindInRepo(Word, RelPath, Symbol) then
  begin
    ShowRepoFile(RelPath);
    P := FindDefinition(FAdapter, Edit, Word, -1);
    if P.Y >= 0 then
      JumpToDefinition(Edit, P, Word)
    else
      UpdateStatus;
    Exit;
  end;
  StatusBar.SimpleText := Format(rsNoDefinition, [Word]);
end;

procedure TForm1.MenuGoToDefinitionClick(Sender: TObject);
begin
  if FEditOld.Visible and FEditOld.Focused then
    GoToDefinition(FEditOld)
  else
    GoToDefinition(Edit);
end;

{ Go > Go to Symbol: lists the symbols of the shown file in the symbol
  bar. }
procedure TForm1.MenuGoToSymbolClick(Sender: TObject);
var
  Names: TStringList;
  Depths: TIntegerDynArray;
  i: integer;
begin
  if not Edit.Visible then
    Exit;
  FreeAndNil(FSymbolFiles);
  FSymbols := CodeTree(FAdapter, Edit);
  Names := TStringList.Create;
  try
    SetLength(Depths, Length(FSymbols));
    for i := 0 to High(FSymbols) do
    begin
      Names.Add(FSymbols[i].Name);
      Depths[i] := FSymbols[i].Depth;
    end;
    FSymbolBar.SetSymbols(Names, Depths);
  finally
    Names.Free;
  end;
  FSymbolBar.Activate;
end;

{ Go > Go to Symbol in Repository: lists the symbols of every file of
  the repository in the symbol bar, each with its file and line: the
  changed files first, in tree order, parsed on demand as the index may
  not have reached them, then the rest of the index as far as it has
  got. FSymbolFiles keeps the file of each. }
procedure TForm1.MenuGoToRepoSymbolClick(Sender: TObject);
var
  Names, Details: TStringList;
  Seen: TStringList;
  Node: TTreeNode;
  E: TGittanIndexEntry;
  Path: string;
  i: integer;

  procedure AddFile(const APath: string; const ASymbols: TGittanSymbols);
  var
    j: integer;
  begin
    if Names.Count + Length(ASymbols) > Length(FSymbols) then
      SetLength(FSymbols, 2 * (Names.Count + Length(ASymbols)));
    for j := 0 to High(ASymbols) do
    begin
      FSymbols[Names.Count] := ASymbols[j];
      Names.Add(ASymbols[j].Name);
      Details.Add(Format('%s:%d', [APath, ASymbols[j].Row + 1]));
      FSymbolFiles.Add(APath);
    end;
  end;

begin
  if FRepo.Root = '' then
    Exit;
  FreeAndNil(FSymbolFiles);
  FSymbolFiles := TStringList.Create;
  Names := TStringList.Create;
  Details := TStringList.Create;
  Seen := TStringList.Create;
  try
    Seen.CaseSensitive := True;
    Seen.Sorted := True;
    Seen.Duplicates := dupIgnore;
    { FSymbols grows as AddFile needs and is cut to size after. }
    SetLength(FSymbols, 0);
    Node := FileTree.Items.GetFirstNode;
    while Node <> nil do
    begin
      if Node.Data <> nil then
      begin
        Path := Node.GetTextPath;
        if Seen.IndexOf(Path) < 0 then
        begin
          Seen.Add(Path);
          AddFile(Path, FileSymbols(Path));
        end;
      end;
      Node := Node.GetNext;
    end;
    Path := ShownRelPath;
    if (Path <> '') and (Seen.IndexOf(Path) < 0) then
    begin
      Seen.Add(Path);
      AddFile(Path, FileSymbols(Path));

    end;
    for i := 0 to FIndex.Count - 1 do
    begin
      E := FIndex[i];
      if E.Indexed and (Seen.IndexOf(E.Path) < 0) then
        AddFile(E.Path, E.Items);
    end;
    SetLength(FSymbols, Names.Count);
    FSymbolBar.SetSymbols(Names, nil, Details);
  finally
    Seen.Free;
    Details.Free;
    Names.Free;
  end;
  FSymbolBar.Activate;
end;

{ A symbol of the shown file is jumped to; one of another file shows
  the file first and is looked up again in the text the editor shows,
  by its full name (several overloads may share the identifier), else
  by its identifier, as Go to Definition does. }
procedure TForm1.SymbolBarPick(Sender: TObject; AIndex: integer);
var
  Symbol: TGittanSymbol;
  Path, Ident: string;
  Shown: TGittanSymbols;
  P: TPoint;
  i: integer;
begin
  SymbolBarClose(Sender);
  if (AIndex < 0) or (AIndex > High(FSymbols)) then
    Exit;
  Symbol := FSymbols[AIndex];
  Ident := NameIdentifier(Symbol.Name);
  if (FSymbolFiles = nil) or (AIndex >= FSymbolFiles.Count) then
  begin
    JumpToDefinition(Edit, Point(Symbol.Col, Symbol.Row), Ident);
    Exit;
  end;
  Path := FSymbolFiles[AIndex];
  if Path <> ShownRelPath then
    ShowRepoFile(Path);
  if not Edit.Visible then
    Exit;
  Shown := CodeTree(FAdapter, Edit);
  P := Point(0, -1);
  for i := 0 to High(Shown) do
    if Shown[i].Name = Symbol.Name then
    begin
      P := Point(Shown[i].Col, Shown[i].Row);
      Break;
    end;
  if P.Y < 0 then
    P := FindDefinition(FAdapter, Edit, Ident, -1);
  if P.Y >= 0 then
    JumpToDefinition(Edit, P, Ident);
end;


procedure TForm1.SymbolBarClose(Sender: TObject);
begin
  FSymbolBar.Visible := False;
  if Edit.Visible and Edit.CanFocus then
    Edit.SetFocus;
end;

{ ---------------------------------------------------------------------------
  Hover
  --------------------------------------------------------------------------- }

{ The number the gutter shows for ARow: the change view's own (the decor
  text, see SetRowNumbers), else the editor's. }
function TForm1.RowLabel(AEd: TATSynEdit; ARow: integer): string;
var
  i: integer;
begin
  for i := 0 to AEd.GutterDecor.Count - 1 do
    if AEd.GutterDecor.ItemPtr(i)^.Data.LineNum = ARow then
      Exit(Trim(AEd.GutterDecor.ItemPtr(i)^.Data.TextAll));
  Result := IntToStr(ARow + 1);
end;

{ Forgets the word under the mouse: the hint, the timer and the link
  underline. }
procedure TForm1.ClearHover;
begin
  FHoverTimer.Enabled := False;
  if FHoverEd <> nil then
  begin
    Application.CancelHint;
    FHoverEd.Hint := '';
    if FHoverLinked then
    begin
      FHoverEd.Attribs.DeleteWithTag(tagHoverLink);
      FHoverEd.Cursor := crDefault;
      FHoverEd.Invalidate;
    end;
  end;
  FHoverLinked := False;
  FHoverWord := '';
  FHoverBlame := '';
  FHoverEd := nil;
end;

{ Follows the mouse over the text: a new word under it starts the hover
  timer over; with Cmd (Ctrl elsewhere) held the word is underlined and
  the cursor is a hand, as a link to its definition. }
procedure TForm1.EditMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
var
  Ed: TATSynEdit;
  Details: TATEditorPosDetails;
  P: TPoint;
  Word: string;
  N1, N2: integer;
  Part: TATLinePart;
  Link: boolean;
begin
  Ed := TATSynEdit(Sender);
  { On the blame band the cell under the mouse is the hover, see
    umain.blame.inc. }
  Word := BlameHintAt(Ed, X, Y);
  if Word <> '' then
  begin
    if (Word <> FHoverBlame) or (Ed <> FHoverEd) then
    begin
      ClearHover;
      FHoverEd := Ed;
      FHoverBlame := Word;
      FHoverTimer.Enabled := True;
    end;
    Exit;
  end;
  P := Ed.ClientPosToCaretPos(ATPoint(X, Y), Details);
  Word := '';
  if (P.Y >= 0) and not Details.BelowAllText and not Details.EndOfWrappedLine and
    (Details.OnGapItem = nil) then
    Word := WordAt(Ed, P, N1, N2);
  if (Word <> FHoverWord) or (Ed <> FHoverEd) or (P.Y <> FHoverRow) or
    (FHoverBlame <> '') then
  begin
    ClearHover;
    if Word = '' then
      Exit;
    FHoverEd := Ed;
    FHoverWord := Word;
    FHoverRow := P.Y;
    FHoverTimer.Enabled := True;
  end;
  Link := (ssModifier in Shift) and (Word <> '');
  if Link <> FHoverLinked then
  begin
    FHoverLinked := Link;
    if Link then
    begin
      InitLinePart(Part);
      Part.ColorFont := FLinkColor;
      Part.ColorBorder := FLinkColor;
      Part.BorderDown := TATLineStyle.Solid;
      Ed.Attribs.Add(Point(N1, P.Y), Point(N2 - N1, 0),
        TATMarkerTags.Init(tagHoverLink, 0), @Part);
      Ed.Cursor := crHandPoint;
    end
    else
    begin
      Ed.Attribs.DeleteWithTag(tagHoverLink);
      Ed.Cursor := crDefault;
    end;
    Ed.Invalidate;
  end;
end;

procedure TForm1.EditMouseLeave(Sender: TObject);
begin
  if Sender = FHoverEd then
    ClearHover;
end;

{ The mouse has rested on a word: its definition, in the text under the
  mouse first (skipping the word's own row, so a definition shows no
  hint for itself), then in the new side when the mouse is on the old
  one, then in the other changed files, is shown as a hint: where it
  is, and the line that defines it. }
procedure TForm1.HoverTimerTimer(Sender: TObject);
var
  Ed: TATSynEdit;
  Word, Where, Line, RelPath: string;
  P: TPoint;
  Symbol: TGittanSymbol;
begin
  FHoverTimer.Enabled := False;
  if (FHoverEd <> nil) and (FHoverBlame <> '') then
  begin
    FHoverEd.Hint := FHoverBlame;
    Application.ActivateHint(Mouse.CursorPos);
    Exit;
  end;
  Ed := FHoverEd;
  Word := FHoverWord;
  if (Ed = nil) or (Word = '') or not Ed.Visible then
    Exit;
  Where := '';
  P := FindDefinition(AdapterOf(Ed), Ed, Word, FHoverRow);
  if (P.Y < 0) and (Ed = FEditOld) then
  begin
    Ed := Edit;
    P := FindDefinition(FAdapter, Edit, Word, -1);
  end;
  if P.Y >= 0 then
  begin
    if FCurrentPath <> '' then
      Where := ExtractFileName(FCurrentPath)
    else
      Where := ExtractFileName(Edit.FileName);
    Where := Format('%s:%s', [Where, RowLabel(Ed, P.Y)]);
    Line := UTF8Encode(Ed.Strings.Lines[P.Y]);
  end
  else if FindInRepo(Word, RelPath, Symbol) then
  begin
    Where := Format('%s:%d', [RelPath, Symbol.Row + 1]);
    Line := Symbol.Line;
  end;
  { The mouse may have moved on while the files were parsed. }
  if (Where = '') or (FHoverEd = nil) or (FHoverWord <> Word) then
    Exit;
  FHoverEd.Hint := Where + LineEnding + Trim(Line);
  Application.ActivateHint(Mouse.CursorPos);
end;
