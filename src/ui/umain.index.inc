{ ---------------------------------------------------------------------------
  The symbol index
  ---------------------------------------------------------------------------
  Included by umain.pp. FIndex (gittan.symbolindex) holds the code tree
  of every file of the repository that has a lexer, so Go to Definition
  and the hover reach past the changed files. OpenRepository starts the
  indexing: the index of the repository is read from disk (one file per
  repository in the user's cache folder, see IndexCacheDir), the files git lists are
  queued, sorted by extension so files of one lexer follow each other,
  and those whose size or time differ from the index are parsed one at
  a time in FIndexEdit, a hidden editor with its own adapter. The parse
  runs in the adapter's thread; its done event (IndexParseDone) collects
  the symbols and queues the next file from the message loop, so the
  window stays responsive. The adapter keeps its lexer, and with it its
  parser thread, from one file to the next: loading a file into the
  editor starts the parse. It is given a new lexer only when the file
  needs another one, or when a parse is still running (after a timeout,
  or a repository closed mid-parse), since the thread ends with the
  lexer, which takes up to a tenth of a second, and a done event of a
  parse that is still running must not be taken for the next file's.
  A file that never reports (FIndexTimer)
  or is larger than MaxIndexedSize is entered without symbols, so it is
  not tried again. The index is written when the indexing ends and when
  the repository or the window is closed. The changed files are also
  parsed on demand (FileSymbols) when a lookup needs them before the
  indexer gets there, or after they changed. }

const
  { Files larger than this are not parsed for the index. }
  MaxIndexedSize = 2 * 1024 * 1024;
  { How often the status bar shows the indexing progress. }
  IndexReportEvery = 25;

{ Orders the queue by extension, then by path, so the files of one
  lexer come together and the adapter seldom changes lexer. }
function CompareByExt(List: TStringList; Index1, Index2: integer): integer;
begin
  Result := CompareStr(ExtractFileExt(List[Index1]), ExtractFileExt(List[Index2]));
  if Result = 0 then
    Result := CompareStr(List[Index1], List[Index2]);
end;

{ The index file of the open repository: in the cache folder, named by
  a hash of the root. }
function TForm1.IndexFileName: string;
begin
  Result := IndexCacheDir + MD5Print(MD5String(FRepo.Root)) + '.txt';
end;

procedure TForm1.SaveIndex;
begin
  if (FRepo.Root = '') or not FIndexSaveNeeded then
    Exit;
  try
    FIndex.Save(IndexFileName);
    FIndexSaveNeeded := False;
  except
    { The configuration folder cannot be written; the index is rebuilt
      next time. }
  end;
end;

procedure TForm1.StopIndexing;
begin
  FIndexing := False;
  FIndexTimer.Enabled := False;
  FIndexQueue.Clear;
end;

{ Reads the index of the open repository and queues its files; see the
  section comment. }
procedure TForm1.StartIndexing;
begin
  StopIndexing;
  FIndex.Load(IndexFileName);
  FIndexSaveNeeded := False;
  if not FRepo.Files(FIndexQueue) then
  begin
    FIndexQueue.Clear;
    Exit;
  end;
  { Files git no longer lists are dropped. }
  FIndex.KeepOnly(FIndexQueue);
  FIndexQueue.CustomSort(@CompareByExt);
  FIndexPos := 0;
  FIndexTotal := FIndexQueue.Count;
  FIndexing := True;
  if FIndexEdit = nil then
  begin
    FIndexEdit := TATSynEdit.Create(Self);
    FIndexEdit.Visible := False;
    FIndexEdit.Parent := Self;
    FIndexAdapter := TATAdapterEControl.Create(Self);
    FIndexAdapter.AddEditor(FIndexEdit);
    FIndexAdapter.OnParseBegin := @AdapterParseBegin;
    FIndexAdapter.OnParseDone := @IndexParseDone;
  end;
  { From the message loop: OpenRepository runs in FormCreate too, and
    loading a large file pumps messages for its progress, which ran
    calls queued for the shown window (FocusTreeAsync) before it was. }
  Application.QueueAsyncCall(@IndexNextAsync, 0);
end;

{ Takes the next file of the queue that needs parsing and starts its
  parse; ends the indexing when the queue is done. }
procedure TForm1.IndexNext;
var
  Path, Full: string;
  Size, Time: int64;
  Lexer: TecSyntAnalyzer;
  E: TGittanIndexEntry;
begin
  if not FIndexing then
    Exit;
  while FIndexPos < FIndexQueue.Count do
  begin
    Path := FIndexQueue[FIndexPos];
    Inc(FIndexPos);
    if FIndexPos mod IndexReportEvery = 0 then
      UpdateStatus
    else
      UpdateIndexBand;
    Full := IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(Path);
    if not FileStamp(Full, Size, Time) then
    begin
      FIndex.Remove(Path);
      Continue;
    end;
    if FIndex.IsCurrent(Path, Size, Time) then
      Continue;
    Lexer := FLexers.ForFile(Path, FRepo.Root);
    if Lexer = nil then
    begin
      FIndex.Remove(Path);
      Continue;
    end;
    E := FIndex.Add(Path);
    E.Size := Size;
    E.Time := Time;
    E.Items := nil;
    E.Indexed := (Size = 0) or (Size > MaxIndexedSize);
    FIndexSaveNeeded := True;
    if E.Indexed then
      Continue;
    FIndexCurrent := Path;
    { Loading a large file pumps messages for its progress, and the timer
      is not on yet: a queued IndexNextAsync must not load the next file
      into the editor meanwhile. }
    FIndexLoading := True;
    try
      if (FIndexAdapter.Lexer = Lexer) and not FIndexAdapter.IsParsingBusy then
      begin
        { Loading the text starts the parse through the change event. }
        FIndexEdit.LoadFromFile(Full, []);
        FIndexEdit.FileName := Full;
      end
      else
      begin
        FIndexAdapter.Lexer := nil;
        FIndexEdit.LoadFromFile(Full, []);
        FIndexEdit.FileName := Full;
        SetEditorLexer(FIndexEdit, Lexer);
      end;
    finally
      FIndexLoading := False;
    end;
    FIndexTimer.Enabled := True;
    Exit;
  end;
  FIndexing := False;
  SaveIndex;
  UpdateStatus;
end;

procedure TForm1.IndexNextAsync(Data: PtrInt);
begin
  { A second StartIndexing queues a second call; the file it started
    is waited for, and so is one still loading. }
  if FIndexTimer.Enabled or FIndexLoading then
    Exit;
  IndexNext;
end;

{ The parse of the current file is done: its symbols go into the index
  and the next file follows from the message loop, since this runs
  inside the adapter's event. }
procedure TForm1.IndexParseDone(Sender: TObject; ATime: integer);
var
  E: TGittanIndexEntry;
begin
  FIndexAdapter.Tag := 1;
  if not FIndexing or not FIndexTimer.Enabled then
    Exit;
  FIndexTimer.Enabled := False;
  E := FIndex.Find(FIndexCurrent);
  if E <> nil then
  begin
    E.Items := CodeTree(FIndexAdapter, FIndexEdit);
    E.Indexed := True;
  end;
  Application.QueueAsyncCall(@IndexNextAsync, 0);
end;

{ The current file's parse never reported: the file is entered without
  symbols and the indexing goes on. }
procedure TForm1.IndexTimerTimer(Sender: TObject);
var
  E: TGittanIndexEntry;
begin
  FIndexTimer.Enabled := False;
  if not FIndexing then
    Exit;
  E := FIndex.Find(FIndexCurrent);
  if E <> nil then
    E.Indexed := True;
  IndexNext;
end;

{ The symbols of the changed file ARelPath as it is in the work tree:
  from the index when it is current, else parsed now in the scratch
  editor and put there. Nil for a file that is gone or has no lexer. }
function TForm1.FileSymbols(const ARelPath: string): TGittanSymbols;
var
  Full: string;
  Size, Time: int64;
  Lexer: TecSyntAnalyzer;
  E: TGittanIndexEntry;
begin
  Result := nil;
  if FRepo.Root = '' then
    Exit;
  Full := IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(ARelPath);
  if not FileStamp(Full, Size, Time) then
  begin
    FIndex.Remove(ARelPath);
    Exit;
  end;
  if FIndex.IsCurrent(ARelPath, Size, Time) then
    Exit(FIndex.Find(ARelPath).Items);
  Lexer := FLexers.ForFile(ARelPath, FRepo.Root);
  if Lexer = nil then
    Exit;
  if Size <= MaxIndexedSize then
  begin
    { The parse waits with the message loop running; a lookup started
      meanwhile would load another file into the scratch editor and free
      the parser this one reads. It finds nothing now and caches
      nothing, and the file is parsed again when next asked for. }
    if FScratchBusy then
      Exit;
    FScratchBusy := True;
    try
      Result := CodeTree(ParseScratch(Full, Lexer), FScratch);
    finally
      FScratchBusy := False;
    end;
    { Only the symbols of this file go into the index. }
    if FScratch.FileName <> Full then
      Exit(nil);
  end;
  E := FIndex.Add(ARelPath);
  E.Size := Size;
  E.Time := Time;
  E.Items := Result;
  E.Indexed := True;
  FIndexSaveNeeded := True;
end;

{ The path of the shown file relative to the repository root: the
  changed file, or the file opened on its own when it is inside the
  repository; '' otherwise. }
function TForm1.ShownRelPath: string;
var
  Root: string;
begin
  Result := FCurrentPath;
  if (Result = '') and (FRepo.Root <> '') and (Edit.FileName <> '') then
  begin
    Root := IncludeTrailingPathDelimiter(FRepo.Root);
    if Copy(Edit.FileName, 1, Length(Root)) = Root then
      Result := StringReplace(Copy(Edit.FileName, Length(Root) + 1, MaxInt),
        PathDelim, '/', [rfReplaceAll]);
  end;
end;

{ The definition of AWord in the repository outside the shown file: the
  changed files first, in tree order, parsed on demand, then the rest
  of the index as far as it has got. }
function TForm1.FindInRepo(const AWord: string; out APath: string;
  out ASymbol: TGittanSymbol): boolean;
var
  Shown, Path: string;
  Node: TTreeNode;
  Symbols: TGittanSymbols;
  Seen: TStringList;
  E: TGittanIndexEntry;
  i, j: integer;
begin
  Result := False;
  APath := '';
  if FRepo.Root = '' then
    Exit;
  Shown := ShownRelPath;
  Seen := TStringList.Create;
  try
    Seen.CaseSensitive := True;
    Seen.Sorted := True;
    Seen.Duplicates := dupIgnore;
    Seen.Add(Shown);
    Node := FileTree.Items.GetFirstNode;
    while Node <> nil do
    begin
      if Node.Data <> nil then
      begin
        Path := Node.GetTextPath;
        if Seen.IndexOf(Path) < 0 then
        begin
          Seen.Add(Path);
          Symbols := FileSymbols(Path);
          j := BestSymbol(Symbols, AWord, -1);
          if j >= 0 then
          begin
            APath := Path;
            ASymbol := Symbols[j];
            Exit(True);
          end;
        end;
      end;
      Node := Node.GetNext;
    end;
    for i := 0 to FIndex.Count - 1 do
    begin
      E := FIndex[i];
      if not E.Indexed or (Seen.IndexOf(E.Path) >= 0) then
        Continue;
      j := BestSymbol(E.Items, AWord, -1);
      if j >= 0 then
      begin
        APath := E.Path;
        ASymbol := E.Items[j];
        Exit(True);
      end;
    end;
  finally
    Seen.Free;
  end;
end;

{ Shows the file ARelPath of the repository: through the tree when it
  is a changed file, else on its own, as File > Open does. }
procedure TForm1.ShowRepoFile(const ARelPath: string);
var
  Node: TTreeNode;
begin
  Node := FileTree.Items.GetFirstNode;
  while Node <> nil do
  begin
    if (Node.Data <> nil) and (Node.GetTextPath = ARelPath) then
    begin
      FileTree.Selected := Node;
      Node.MakeVisible;
      Exit;
    end;
    Node := Node.GetNext;
  end;
  { A file picked in the tree later must fire the selection event. }
  FileTree.Selected := nil;
  OpenFile(IncludeTrailingPathDelimiter(FRepo.Root) + SetDirSeparators(ARelPath));
end;
