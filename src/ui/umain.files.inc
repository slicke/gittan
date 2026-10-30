{ ---------------------------------------------------------------------------
  The Files page
  ---------------------------------------------------------------------------
  The tree of a commit as it was (gittan.filespage), one folder at a
  time, in the box: the sidebar's Files row and View > Files (Cmd+5)
  show HEAD's, and follow HEAD as commits are made; Browse Files... in
  the commit menu, the tag menu and the reflog's menu (BrowseCommit)
  shows that commit's, which stays until the row is picked again. The
  folders are read with TGittanRepo.TreeEntries as they are opened. A
  click on a file (or a link) shows it read-only in the editor under
  its lexer, an image in the image view, a binary file in the binary
  view (ShowBlob; the view gvBlob, the Files row still marked), the
  header naming the commit at its right, with Open, which writes it
  to a folder of the temporary directory named after the commit and
  opens it in the desktop's application for it, and Save As... as its
  pills. A submodule's row shows the submodule's page when it is one
  of the work tree's. See spec/files-page.md. }

procedure TRepoFrame.SetupFilesPage;
begin
  FFilesPage := TGittanFilesPage.Create(Self);
  FFilesPage.Parent := FSummaryBox;
  FFilesPage.Visible := False;
  FFilesPage.SetImages(TreeImages, iconFolder, iconFile);
  FFilesPage.OnRead := @FilesPageRead;
  FFilesPage.OnOpen := @FilesPageOpen;
  FFilesPage.OnFolderChange := @FilesPageFolderChange;
end;

procedure TRepoFrame.MenuFilesClick(Sender: TObject);
begin
  if FRepo.Root <> '' then
    ShowFiles;
end;

{ HEAD's files, named by the branch, or the short id on a detached
  HEAD; before the first commit the page says there is none. }
procedure TRepoFrame.ShowFiles;
var
  Head: TGittanCommitLine;
  Body: string;
begin
  if FRepo.Root = '' then
    Exit;
  FFilesHead := True;
  if not FRepo.CommitDetails('HEAD', Head, Body) then
    ShowFilesAt('', '', '')
  else if FBranch <> '' then
    ShowFilesAt(Head.Hash, FBranch, Head.Subject)
  else
    ShowFilesAt(Head.Hash, Head.Short, Head.Subject);
end;

{ Browse Files... on a commit: its files, under its name. }
procedure TRepoFrame.BrowseCommit(const AHash, AName, ASubject: string);
begin
  if (FRepo.Root = '') or (AHash = '') then
    Exit;
  FFilesHead := False;
  ShowFilesAt(AHash, AName, ASubject);
end;

{ The page takes the summary's place in the box, as the Repository page
  does; an empty AHash is a repository with no commit yet. }
procedure TRepoFrame.ShowFilesAt(const AHash, AName, ASubject: string);
begin
  if FRepo.Root = '' then
    Exit;
  if FGraph.Visible then
    FGraph.Close;
  LeaveEditorViews;
  FView := gvFiles;
  HideBoxPages;
  FFilesPage.SetRepository(ExtractFileName(FRepo.Root), FRepo.Root);
  if AHash = '' then
    FFilesPage.ClearCommit
  else
    FFilesPage.SetCommit(AHash, AName, ASubject);
  FFilesPage.Visible := True;
  FFilesPage.FitHeight(FSummaryBox.ClientHeight);
  FSummaryBox.Visible := True;
  FSummaryBox.VertScrollBar.Position := 0;
  FStatus.SetPosition('');
  { A file picked again after the page must fire the selection event. }
  FileTree.Selected := nil;
  FRepoTree.Selected := nil;
  FSubTree.Selected := nil;
  SetNavRow(navFiles);
  UpdateStatus;
end;

{ After a snapshot while the page shows HEAD: the new HEAD, when a
  commit moved it; the page keeps its folder. }
procedure TRepoFrame.RefreshFilesPage;
var
  Head: TGittanCommitLine;
  Body: string;
begin
  if (FRepo.Root = '') or not FFilesHead then
    Exit;
  FFilesPage.SetRepository(ExtractFileName(FRepo.Root), FRepo.Root);
  if not FRepo.CommitDetails('HEAD', Head, Body) then
    FFilesPage.ClearCommit
  else if FBranch <> '' then
    FFilesPage.SetCommit(Head.Hash, FBranch, Head.Subject)
  else
    FFilesPage.SetCommit(Head.Hash, Head.Short, Head.Subject);
end;

function TRepoFrame.FilesPageRead(Sender: TObject; const AFolder: string;
  out AList: TGittanTreeEntries; out AError: string): boolean;
begin
  AError := '';
  Screen.Cursor := crHourGlass;
  try
    Result := FRepo.TreeEntries(FFilesPage.Commit, AFolder, AList);
  finally
    Screen.Cursor := crDefault;
  end;
  if not Result then
    AError := FRepo.Error;
end;

{ Another folder: from its top. }
procedure TRepoFrame.FilesPageFolderChange(Sender: TObject);
begin
  FSummaryBox.VertScrollBar.Position := 0;
end;

procedure TRepoFrame.FilesPageOpen(Sender: TObject; const AEntry: TGittanTreeEntry);
var
  i: integer;
begin
  if FRepo.Root = '' then
    Exit;
  if AEntry.Kind = tkSubmodule then
  begin
    for i := 0 to High(FSubmodules) do
      if FSubmodules[i].Path = AEntry.Path then
      begin
        ShowSubmodule(i);
        Exit;
      end;
    StatusNote(Format(rsFilesSubmoduleUnknown, [AEntry.Path]), True);
    Exit;
  end;
  ShowBlob(AEntry.Path);
end;

{ APath as it is in the page's commit: text in the editor under the
  file's lexer (not valid UTF-8 read as Windows-1252), an image in the
  image view as a new image, anything else binary in the binary view,
  with its size. }
procedure TRepoFrame.ShowBlob(const APath: string);
var
  Data: RawByteString;
  Shown, Oid: string;
  Size: int64;
begin
  if (FRepo.Root = '') or (FFilesPage.Commit = '') then
    Exit;
  if not FRepo.FileBlob(APath, FFilesPage.Commit, Data) then
  begin
    StatusNote(Format(rsBlobReadFailed, [APath, FRepo.Error]), True);
    Exit;
  end;
  FlushEdit;
  LeaveEdit;
  AbandonHistoryJob;
  FBlobPath := APath;
  FBlobCommit := FFilesPage.Commit;
  FBlobName := FFilesPage.CommitName;
  FSummary.Notice := '';
  FCurrentPath := '';
  FManualLexer := False;
  FView := gvBlob;
  HideMergeView;
  FHeader.SetFile(APath, iconFile);
  FHeader.SetDetail(Format(rsAtCommit, [FBlobName]));
  BlobActions;
  LockNote;
  FHeader.SetChanges(0, 0);
  FHeader.SetConflicts(0, 0);
  FSummaryBox.Visible := False;
  FSymbolBar.Visible := False;
  FFindBar.Visible := False;
  if IsImagePath(APath) then
  begin
    FImageDiff.SetImages('', Data, False, True);
    Edit.Visible := False;
    HideMarkdownPreview;
    FBinaryView.Visible := False;
    FHeader.Visible := True;
    ApplyLayout;
    FImageDiff.Visible := True;
  end
  { git's own rule for a binary file: a NUL in the first 8000 bytes; a
    file in Git LFS not downloaded is one too, of the size its pointer
    gives. }
  else if ParseLfsPointer(Data, Oid, Size) or (Pos(#0, Copy(Data, 1, 8000)) > 0) then
  begin
    if Oid <> '' then
    begin
      FBinaryView.SetFile(APath, Size);
      FBinaryView.SetNote(rsLfsNotDownloaded);
    end
    else
      FBinaryView.SetFile(APath, Length(Data));
    Edit.Visible := False;
    HideMarkdownPreview;
    FImageDiff.Visible := False;
    FHeader.Visible := True;
    ApplyLayout;
    FBinaryView.Visible := True;
  end
  else
  begin
    Shown := Data;
    if FindInvalidUTF8Codepoint(PChar(Shown), Length(Shown)) >= 0 then
      Shown := CP1252ToUTF8(Shown);
    ShowText(Edit, Shown, App.Lexers.ForFile(APath, FRepo.Root));
    UpdateChangeNav;
    ShowEditor;
  end;
  { The Files row stays the view's. }
  SetNavRow(navFiles);
  FSummary.Selected := '';
  FileTree.Selected := nil;
  FStatus.SetPosition('');
  UpdateStatus;
end;

{ The shown file's bytes again, for Open and Save As... }
function TRepoFrame.BlobData(out AData: RawByteString): boolean;
begin
  Result := (FView = gvBlob) and (FRepo.Root <> '') and (FBlobCommit <> '');
  if not Result then
    Exit;
  Screen.Cursor := crHourGlass;
  try
    Result := FRepo.FileBlob(FBlobPath, FBlobCommit, AData);
  finally
    Screen.Cursor := crDefault;
  end;
  if not Result then
    StatusNote(Format(rsBlobReadFailed, [FBlobPath, FRepo.Error]), True);
end;

{ Into gittan-<short id> in the temporary directory, under its path,
  so the application names it as it was named and two commits do not
  share a copy. }
procedure TRepoFrame.OpenBlobOutside;
var
  Data: RawByteString;
  FileName: string;
  Stream: TFileStream;
begin
  if not BlobData(Data) then
    Exit;
  FileName := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-' + Copy(FBlobCommit, 1, 7) +
    PathDelim + SetDirSeparators(FBlobPath);
  try
    ForceDirectories(ExtractFileDir(FileName));
    Stream := TFileStream.Create(FileName, fmCreate);
    try
      if Length(Data) > 0 then
        Stream.WriteBuffer(Data[1], Length(Data));
    finally
      Stream.Free;
    end;
  except
    on E: Exception do
    begin
      StatusNote(Format(rsBlobWriteFailed, [FileName, E.Message]), True);
      Exit;
    end;
  end;
  OpenDocument(FileName);
end;

procedure TRepoFrame.SaveBlobAs;
var
  Dlg: TSaveDialog;
  Data: RawByteString;
  Stream: TFileStream;
begin
  if FView <> gvBlob then
    Exit;
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    Dlg.FileName := ExtractFileName(FBlobPath);
    if not Dlg.Execute or not BlobData(Data) then
      Exit;
    try
      Stream := TFileStream.Create(Dlg.FileName, fmCreate);
      try
        if Length(Data) > 0 then
          Stream.WriteBuffer(Data[1], Length(Data));
      finally
        Stream.Free;
      end;
    except
      on E: Exception do
        StatusNote(Format(rsBlobWriteFailed, [Dlg.FileName, E.Message]), True);
    end;
  finally
    Dlg.Free;
  end;
end;
