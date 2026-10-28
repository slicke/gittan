{ ---------------------------------------------------------------------------
  Back and Forward
  ---------------------------------------------------------------------------
  Go > Back (Cmd+[, Alt+Left elsewhere) and Go > Forward (Cmd+], Alt+Right)
  step through the places the frame has shown (gittan.navhistory). The
  place is read from what the frame shows (NavCurrent) whenever the
  application is idle (NavIdle), so every way of getting somewhere counts
  (the tree, the summary, Go to Definition, a commit picked in the graph,
  Compare With, a page): when it differs from the place noted
  (FNavPlace), that one goes on the back list; while it is the same, its
  caret row is kept up to date, so going back lands where the caret was
  left. A jump within a file (JumpToDefinition: a definition, a symbol, a
  caller) notes the place before it (NavMark). The code history, a
  submodule, the welcome view and the like are no places: while they are
  shown nothing is noted, and what was shown before them stays the place
  to go back to. }

{ What the frame shows as a place; false when it is none. }
function TRepoFrame.NavCurrent(out APlace: TGittanPlace): boolean;
begin
  Result := False;
  APlace := Default(TGittanPlace);
  if FRepo.Root = '' then
    Exit;
  case FView of
    gvSummary:
      APlace.Kind := pkSummary;
    gvChanges, gvImage, gvTranslation, gvBinary:
    begin
      { A translation or a binary file opened from disk is not in the
        tree. }
      if FCurrentPath = '' then
        Exit;
      APlace.Kind := pkChanges;
      APlace.Path := FCurrentPath;
    end;
    gvRepoDiff:
      APlace.Kind := pkRepoDiff;
    gvFile:
    begin
      if Edit.FileName = '' then
        Exit;
      APlace.Kind := pkFile;
      APlace.Path := Edit.FileName;
    end;
    gvBlob:
    begin
      APlace.Kind := pkBlob;
      APlace.Path := FBlobPath;
      APlace.Ref := FBlobCommit;
      APlace.Name := FBlobName;
    end;
    gvFiles:
    begin
      APlace.Kind := pkFiles;
      if not FFilesHead then
      begin
        APlace.Ref := FFilesPage.Commit;
        APlace.Name := FFilesPage.CommitName;
      end;
    end;
    gvRepoInfo:
      APlace.Kind := pkRepoInfo;
    gvCommands:
      APlace.Kind := pkCommands;
    gvPulls:
      APlace.Kind := pkPulls;
    else
      Exit;
  end;
  if APlace.Kind in [pkSummary, pkChanges, pkRepoDiff] then
  begin
    APlace.Base := FRepo.Base;
    APlace.WholeTree := FRepo.WholeTree;
    if (FBlameRange <> '') and (FBlameRange = FRepo.Base) then
      APlace.Commit := FBlameCommit.Hash;
  end;
  if (FView in [gvChanges, gvRepoDiff, gvFile, gvBlob]) and (Edit.Carets.Count > 0) then
  begin
    APlace.Row := Edit.Carets[0].PosY;
    APlace.Col := Edit.Carets[0].PosX;
    APlace.Top := Edit.LineTop;
  end;
  Result := True;
end;

{ Notes what the frame shows: a place other than the one noted puts that
  one on the back list. True when it did. }
function TRepoFrame.NavSync: boolean;
var
  P: TGittanPlace;
begin
  Result := False;
  if FNavBusy or not NavCurrent(P) then
    Exit;
  if not FNavValid then
  begin
    FNavPlace := P;
    FNavValid := True;
    Exit;
  end;
  if SamePlace(P, FNavPlace) then
  begin
    FNavPlace.Row := P.Row;
    FNavPlace.Col := P.Col;
    FNavPlace.Top := P.Top;
    Exit;
  end;
  FNavHistory.Visit(FNavPlace);
  FNavPlace := P;
  NavUpdateItems;
  Result := True;
end;

procedure TRepoFrame.NavIdle(Sender: TObject; var Done: boolean);
begin
  if FWindow.IsActive(Self) then
    NavSync;
end;

{ Before a jump within the shown file: the place with the caret where it
  is goes on the back list. When the file was only just shown (a
  definition in another file), the place before it went there already. }
procedure TRepoFrame.NavMark;
begin
  if FNavBusy or NavSync or not FNavValid then
    Exit;
  FNavHistory.Visit(FNavPlace);
  NavUpdateItems;
end;

{ Forgets every place, as another repository is opened. }
procedure TRepoFrame.NavClear;
begin
  FNavHistory.Clear;
  FNavValid := False;
  NavUpdateItems;
end;

procedure TRepoFrame.NavUpdateItems;
begin
  if FBackItem <> nil then
    FBackItem.Enabled := FNavHistory.CanBack;
  if FForwardItem <> nil then
    FForwardItem.Enabled := FNavHistory.CanForward;
end;

{ Puts the caret on ARow at ACol with ATop the first row in view, as far
  as the text reaches. The editor may only just have been shown: the
  scroll needs the wrap info of its text, which the first paint would
  build, and the line top kept from the resize of showing it would win
  at that paint (as for the symbol bar's pick). }
procedure TRepoFrame.NavRestoreRow(ARow, ACol, ATop: integer);
begin
  if not Edit.Visible or (Edit.Strings.Count = 0) then
    Exit;
  Edit.UpdateWrapInfo(True);
  Edit.LineTopTodo := 0;
  ARow := Max(0, Min(ARow, Edit.Strings.Count - 1));
  Edit.DoCaretSingle(Max(0, Min(ACol, Length(Edit.Strings.Lines[ARow]))), ARow);
  Edit.LineTop := Max(0, Min(ATop, Edit.Strings.Count - 1));
  Edit.Update;
  SyncOldSide;
  UpdateChangeNav;
end;

{ Shows APlace: the comparison it was shown against first, for the
  places it matters to, then the place itself. False when it is gone: a
  file no longer changed or no longer there. }
function TRepoFrame.NavRestore(const APlace: TGittanPlace): boolean;
var
  Line: TGittanCommitLine;
  Body: string;
begin
  Result := False;
  if FRepo.Root = '' then
    Exit;
  if FGraph.Visible then
    FGraph.Close;
  if (APlace.Kind in [pkSummary, pkChanges, pkRepoDiff]) and
    ((APlace.Base <> FRepo.Base) or (APlace.WholeTree <> FRepo.WholeTree)) then
  begin
    if APlace.Commit <> '' then
      ShowBlameCommit(APlace.Commit)
    else
      SetBase(APlace.Base, APlace.WholeTree);
    if (FRepo.Base <> APlace.Base) or (FRepo.WholeTree <> APlace.WholeTree) then
      Exit;
  end;
  case APlace.Kind of
    pkSummary:
    begin
      FSummary.Notice := '';
      ShowSummary;
    end;
    pkChanges:
    begin
      if not IsChangedPath(APlace.Path) then
        Exit;
      if (FCurrentPath <> APlace.Path) or not (FView in [gvChanges, gvImage,
        gvTranslation, gvBinary]) then
      begin
        SummarySelectFile(nil, APlace.Path);
        { The tree filter may hide the file. }
        if (FCurrentPath <> APlace.Path) and not ShowChanges(APlace.Path) then
          Exit;
      end;
      if FView = gvChanges then
        NavRestoreRow(APlace.Row, APlace.Col, APlace.Top);
    end;
    pkRepoDiff:
    begin
      if FView <> gvRepoDiff then
        ShowRepoDiff;
      NavRestoreRow(APlace.Row, APlace.Col, APlace.Top);
    end;
    pkFile:
    begin
      if not FileExists(APlace.Path) then
        Exit;
      if (FView <> gvFile) or (Edit.FileName <> APlace.Path) then
      begin
        { A file picked in the tree later must fire the selection event. }
        FileTree.Selected := nil;
        OpenFile(APlace.Path);
      end;
      if FView = gvFile then
        NavRestoreRow(APlace.Row, APlace.Col, APlace.Top);
    end;
    pkBlob:
    begin
      if (FView <> gvBlob) or (FBlobCommit <> APlace.Ref) or (FBlobPath <> APlace.Path) then
      begin
        if not FRepo.CommitDetails(APlace.Ref, Line, Body) then
          Exit;
        FFilesHead := False;
        ShowFilesAt(APlace.Ref, APlace.Name, Line.Subject);
        ShowBlob(APlace.Path);
        if FView <> gvBlob then
          Exit;
      end;
      NavRestoreRow(APlace.Row, APlace.Col, APlace.Top);
    end;
    pkFiles:
      if APlace.Ref = '' then
        ShowFiles
      else
      begin
        if not FRepo.CommitDetails(APlace.Ref, Line, Body) then
          Exit;
        BrowseCommit(APlace.Ref, APlace.Name, Line.Subject);
      end;
    pkRepoInfo:
      ShowRepoInfo;
    pkCommands:
      ShowCommands;
    pkPulls:
      ShowPulls;
  end;
  Result := True;
end;

{ Goes back (or forward) to the nearest place that is still there; one
  that is gone (a file committed since) is passed over, and the status
  bar says so when none is left. }
procedure TRepoFrame.NavStep(AForward: boolean);
var
  P: TGittanPlace;
  Shown: boolean;
begin
  if FRepo.Root = '' then
    Exit;
  NavSync;
  if not FNavValid then
    Exit;
  Shown := False;
  FNavBusy := True;
  try
    while not Shown and ((AForward and FNavHistory.CanForward) or
      (not AForward and FNavHistory.CanBack)) do
    begin
      if AForward then
        P := FNavHistory.Forward(FNavPlace)
      else
        P := FNavHistory.Back(FNavPlace);
      Shown := NavRestore(P);
    end;
  finally
    FNavBusy := False;
  end;
  if Shown then
  begin
    if not NavCurrent(FNavPlace) then
      FNavPlace := P;
  end
  else
  begin
    { What is shown now may not be the place noted, if a place gone
      left the frame elsewhere. }
    FNavValid := False;
    NavSync;
    StatusNote(rsNavGone);
  end;
  NavUpdateItems;
end;

procedure TRepoFrame.MenuBackClick(Sender: TObject);
begin
  NavStep(False);
end;

procedure TRepoFrame.MenuForwardClick(Sender: TObject);
begin
  NavStep(True);
end;
