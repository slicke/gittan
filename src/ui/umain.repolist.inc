{ ---------------------------------------------------------------------------
  The repository list
  ---------------------------------------------------------------------------
  App.RepoList, shown by the welcome view over the recent repositories.
  File > Repository List shows the welcome view (TRepoWindow.ShowRepoList)
  and File > Add to Repository List adds the repository open; the
  welcome view folds folders and moves rows by dragging itself, and asks
  for the menu of a right-click here (WelcomeListMenu). Every change is
  saved at once and shown in every frame (SaveRepoList). }

const
  { The tags of the list menu's items. }
  lmOpen = 1;
  lmRename = 2;
  lmRemove = 3;
  lmAddRecent = 4;
  lmNewFolder = 5;
  lmAddRepo = 6;
  lmAddFolder = 7;
  lmRemoveRecent = 8;
  lmClearRecent = 9;

procedure TRepoFrame.RepoListChanged;
begin
  FWelcome.ListChanged;
  UpdateRepoListItem;
end;

procedure TRepoFrame.UpdateRepoListItem;
begin
  if FAddListItem <> nil then
    FAddListItem.Enabled := (FRepo.Root <> '') and (App.RepoList.Find(FRepo.Root) = nil);
end;

function TRepoFrame.SaveRepoList: boolean;
begin
  Result := App.RepoList.Save;
  if not Result then
    BannerError(rsListSaveFailed, App.RepoList.FileName);
  FWindow.RepoListChanged;
end;

procedure TRepoFrame.MenuRepoListClick(Sender: TObject);
begin
  FWindow.ShowRepoList;
end;

procedure TRepoFrame.MenuAddListClick(Sender: TObject);
begin
  if FRepo.Root = '' then
    Exit;
  if App.RepoList.AddRepo(nil, FRepo.Root) = nil then
    StatusNote(rsListHasIt, False)
  else if SaveRepoList then
    BannerSuccess(Format(rsListAdded, [ExtractFileName(ExcludeTrailingPathDelimiter(FRepo.Root))]));
end;

procedure TRepoFrame.WelcomeListChanged(Sender: TObject);
begin
  SaveRepoList;
end;

procedure TRepoFrame.WelcomeListMenu(Sender: TObject; AEntry: TGittanRepoEntry;
  const ARoot: string; const APos: TPoint);

  procedure Add(const ACaption: string; ATag: integer; AEnabled: boolean = True);
  var
    Item: TMenuItem;
  begin
    Item := TMenuItem.Create(FListPopup);
    Item.Caption := ACaption;
    Item.Tag := ATag;
    Item.Enabled := AEnabled;
    Item.OnClick := @ListMenuClick;
    FListPopup.Items.Add(Item);
  end;

begin
  if FListPopup = nil then
    FListPopup := TPopupMenu.Create(Self);
  FListPopup.Items.Clear;
  FListEntry := AEntry;
  FListRoot := ARoot;
  if AEntry <> nil then
  begin
    if not AEntry.IsFolder then
      Add(rsListOpen, lmOpen, DirectoryExists(AEntry.Path));
    Add(rsListRename, lmRename);
    if AEntry.IsFolder then
      Add(rsListRemoveFolder, lmRemove)
    else
      Add(rsListRemove, lmRemove);
    FListPopup.Items.Add(NewLine);
  end
  else if ARoot <> '' then
  begin
    Add(rsListAddRecent, lmAddRecent, App.RepoList.Find(ARoot) = nil);
    Add(rsListRemoveRecent, lmRemoveRecent);
    Add(rsListClearRecent, lmClearRecent);
    FListPopup.Items.Add(NewLine);
  end;
  Add(rsListNewFolder, lmNewFolder);
  Add(rsListAddRepo, lmAddRepo);
  Add(rsListAddFolder, lmAddFolder);
  FListPopup.PopUp(APos.X, APos.Y);
end;

{ The folder that what the menu adds goes into: the folder right-clicked,
  the one the repository right-clicked is in, else the top. }
function TRepoFrame.ListMenuFolder: TGittanRepoEntry;
begin
  if FListEntry = nil then
    Result := App.RepoList.Root
  else if FListEntry.IsFolder then
    Result := FListEntry
  else
    Result := FListEntry.Parent;
end;

function TRepoFrame.CheckListName(const AValues: array of string): string;
begin
  if Trim(AValues[0]) = '' then
    Result := rsListNoName
  else
    Result := '';
end;

procedure TRepoFrame.ListMenuClick(Sender: TObject);
var
  E, Folder: TGittanRepoEntry;
  Value, Out, Err, Dir: string;
  Found: TStringArray;
  i, Added: integer;
begin
  E := FListEntry;
  Folder := ListMenuFolder;
  case TMenuItem(Sender).Tag of
    lmOpen:
      FWindow.OpenRepository(E.Path);
    lmRename:
    begin
      Value := E.Caption;
      if E.IsFolder then
      begin
        if not AskText(rsListRenameTitle, rsListFolderPrompt, Value, @CheckListName) then
          Exit;
        E.Name := Trim(Value);
      end
      else
      begin
        if not AskText(rsListRenameTitle, rsListRepoPrompt, Value, nil, '',
          E.Path, True) then
          Exit;
        Value := Trim(Value);
        if Value = ExtractFileName(E.Path) then
          Value := '';
        E.Name := Value;
      end;
      SaveRepoList;
    end;
    lmRemove:
    begin
      if E.IsFolder and (E.RepoCount > 0) and (AskDlg(rsListRemoveTitle,
        Format(rsListRemoveAsk, [E.Caption, E.RepoCount]), mtConfirmation,
        [mrYes, rsListRemoveAction, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'],
        0) <> mrYes) then
        Exit;
      App.RepoList.Remove(E);
      SaveRepoList;
    end;
    lmAddRecent:
      if App.RepoList.AddRepo(nil, FListRoot) <> nil then
        SaveRepoList;
    lmRemoveRecent:
    begin
      App.Settings.RemoveRecent(FListRoot);
      RecentChanged;
    end;
    lmClearRecent:
    begin
      App.Settings.Recent.Clear;
      RecentChanged;
    end;
    lmNewFolder:
    begin
      Value := '';
      if not AskText(rsListNewFolderTitle, rsListFolderPrompt, Value, @CheckListName,
        rsListCreate) then
        Exit;
      App.RepoList.AddFolder(Folder, Trim(Value));
      Folder.Collapsed := False;
      SaveRepoList;
    end;
    lmAddRepo:
    begin
      if not DirDialog.Execute then
        Exit;
      if not RunGitIn(DirDialog.FileName, ['rev-parse', '--show-toplevel'], Out, Err) then
      begin
        BannerError(Format(rsListNotRepo, [DirDialog.FileName]), '');
        Exit;
      end;
      if App.RepoList.AddRepo(Folder, Trim(Out)) = nil then
      begin
        StatusNote(rsListHasIt, False);
        Exit;
      end;
      Folder.Collapsed := False;
      SaveRepoList;
    end;
    lmAddFolder:
    begin
      if not DirDialog.Execute then
        Exit;
      Dir := DirDialog.FileName;
      Found := FindRepositories(Dir);
      if Length(Found) = 0 then
      begin
        BannerError(Format(rsListNoneFound, [Dir]), '');
        Exit;
      end;
      Folder := App.RepoList.AddFolder(Folder, ExtractFileName(RepoListPath(Dir)));
      Added := 0;
      { Each by its root as git gives it, as Add Repository does, so a
        folder reached through a link is not listed twice, and a .git
        that is no repository (a worktree's whose repository is gone)
        is left out. }
      for i := 0 to High(Found) do
        if RunGitIn(Found[i], ['rev-parse', '--show-toplevel'], Out, Err) and
          (App.RepoList.AddRepo(Folder, Trim(Out)) <> nil) then
          Inc(Added);
      if Added = 0 then
      begin
        App.RepoList.Remove(Folder);
        StatusNote(rsListAllListed, False);
        Exit;
      end;
      if Folder.Parent <> nil then
        Folder.Parent.Collapsed := False;
      if SaveRepoList then
        BannerSuccess(Format(rsListFolderAdded, [Added, Folder.Caption]));
    end;
  end;
end;
