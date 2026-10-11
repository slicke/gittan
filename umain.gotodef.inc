{ ---------------------------------------------------------------------------
  Go to Definition
  ---------------------------------------------------------------------------
  Included by umain.pp. The lexer's code tree (the ranges EControl marks
  DisplayInTree: functions, methods, classes, sections) is the only
  symbol table there is: a word is looked up among the names of those
  ranges, in the text the caret is in first and then in the other
  changed files of the repository, each parsed by a hidden editor with
  its own adapter. A hit in another file selects it in the tree, which
  shows it, and the lookup runs again on the text the editor shows, so
  the rows of the change view (deleted lines kept, unchanged lines
  hidden) need no mapping. }

const
  { How long one parse may take before the lookup gives up on it. }
  ParseTimeout = 3000;

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

{ The word under the first caret of AEd (the word before the caret when
  the caret is right after one), as the editor's word jumping sees it. }
function TForm1.WordAtCaret(AEd: TATSynEdit): string;
var
  Caret: TATCaretItem;
  S: UnicodeString;
  N1, N2: integer;
begin
  Result := '';
  if AEd.Carets.Count = 0 then
    Exit;
  Caret := AEd.Carets[0];
  if not AEd.Strings.IsIndexValid(Caret.PosY) then
    Exit;
  S := AEd.Strings.Lines[Caret.PosY];
  SFindWordBounds(S, Caret.PosX, N1, N2, AEd.OptNonWordChars);
  if N2 > N1 then
    Result := UTF8Encode(Copy(S, N1 + 1, N2 - N1));
end;

{ The position (0-based column and row) of the best range of AAdapter's
  code tree named for AWord, Y = -1 when there is none. The range's
  identifier token (the name in its header) gives the position, else
  the range's first token. A range at row ASkipRow is left out, so a
  lookup from the definition itself goes on to the other files. }
function TForm1.FindDefinition(AAdapter: TATAdapterEControl; const AWord: string;
  ASkipRow: integer): TPoint;
var
  Client: TecClientSyntAnalyzer;
  R: TecTextRange;
  i, Rank, Best: integer;
  P: TPoint;
begin
  Result := Point(0, -1);
  Client := AAdapter.AnClient;
  if Client = nil then
    Exit;
  WaitForParse(AAdapter);
  Best := srNone;
  Client.CriSecForData.Enter;
  try
    for i := 0 to Client.PublicData.FoldRanges.Count - 1 do
    begin
      R := TecTextRange(Client.PublicData.FoldRanges[i]);
      if (R.Rule = nil) or not R.Rule.DisplayInTree or (R.StartIdx < 0) then
        Continue;
      Rank := SymbolRank(UTF8Encode(Client.GetRangeName(R, Client.PublicData.Tokens)), AWord);
      if Rank <= Best then
        Continue;
      if R.IdentIdx >= 0 then
        P := Client.PublicData.Tokens._GetItemPtr(R.IdentIdx)^.Range.PointStart
      else
        P := Client.PublicData.Tokens._GetItemPtr(R.StartIdx)^.Range.PointStart;
      if P.Y = ASkipRow then
        Continue;
      Best := Rank;
      Result := P;
    end;
  finally
    Client.CriSecForData.Leave;
  end;
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
        APos := FindDefinition(FAdapter, AWord, -1);
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
  Word, RelPath, FullPath: string;
  P: TPoint;
  Node: TTreeNode;
  Lexer: TecSyntAnalyzer;
begin
  if not AEd.Visible then
    Exit;
  Word := WordAtCaret(AEd);
  if Word = '' then
    Exit;
  P := FindDefinition(AdapterOf(AEd), Word, AEd.Carets[0].PosY);
  if (P.Y >= 0) and not AEd.IsLineFolded(P.Y) then
  begin
    JumpToDefinition(AEd, P, Word);
    Exit;
  end;
  if AEd = FEditOld then
  begin
    P := FindDefinition(FAdapter, Word, -1);
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
  if FRepo.Root <> '' then
  begin
    StatusBar.SimpleText := Format(rsLookingFor, [Word]);
    Node := FileTree.Items.GetFirstNode;
    while Node <> nil do
    begin
      if Node.Data <> nil then
      begin
        RelPath := Node.GetTextPath;
        FullPath := IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(RelPath);
        Lexer := FLexers.ForFile(RelPath);
        if (RelPath <> FCurrentPath) and (Lexer <> nil) and FileExists(FullPath) then
        begin
          P := FindDefinition(ParseScratch(FullPath, Lexer), Word, -1);
          if P.Y >= 0 then
          begin
            FileTree.Selected := Node;
            Node.MakeVisible;
            P := FindDefinition(FAdapter, Word, -1);
            if P.Y >= 0 then
              JumpToDefinition(Edit, P, Word);
            Exit;
          end;
        end;
      end;
      Node := Node.GetNext;
    end;
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
