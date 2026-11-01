{ The extensions in the frame (spec/extensions.md): the Extensions menu
  with the commands the loaded extensions registered (gittan.ext.registry)
  and the items of their own in the file and editor popups, a command's
  context, and what the host (gittan.exthost) puts in the status bar and
  the change view. The menus are built again whenever the registry
  changes (RebuildExtMenu, from TRepoWindow.ExtensionsChanged). }

const
  { Marks the items of the extensions in the popups, so a rebuild takes
    those alone. }
  ExtItemTag = 7001;

procedure TRepoFrame.RebuildExtMenu;
var
  Eng: TGittanExtEngine;
  i: integer;
  Cmd: TGittanExtCommand;
  FileFirst, EditFirst: boolean;

  procedure DropExtItems(APopup: TPopupMenu);
  var
    j: integer;
  begin
    for j := APopup.Items.Count - 1 downto 0 do
      if APopup.Items[j].Tag = ExtItemTag then
        APopup.Items[j].Free;
  end;

  function NewItem(AOwner: TComponent; const ACaption: string): TMenuItem;
  begin
    Result := TMenuItem.Create(AOwner);
    Result.Caption := ACaption;
    Result.Tag := ExtItemTag;
    if ACaption <> '-' then
    begin
      Result.Hint := TGittanExtRegistry.CommandKey(Cmd.ExtId, Cmd.Id);
      Result.OnClick := @ExtCommandClick;
    end;
  end;

begin
  if FExtMenu = nil then
    Exit;
  FExtMenu.Clear;
  DropExtItems(FFilePopup);
  DropExtItems(FEditPopup);
  FileFirst := True;
  EditFirst := True;
  Eng := TGittanExtEngine.Existing;
  if Eng <> nil then
    for i := 0 to Eng.Registry.CommandCount - 1 do
    begin
      Cmd := Eng.Registry.Command(i);
      if cwMenu in Cmd.Where then
        FExtMenu.Add(NewItem(FExtMenu, Cmd.Title));
      if cwFilePopup in Cmd.Where then
      begin
        if FileFirst then
          FFilePopup.Items.Add(NewItem(FFilePopup, '-'));
        FileFirst := False;
        FFilePopup.Items.Add(NewItem(FFilePopup, Cmd.Title));
      end;
      if cwEditorPopup in Cmd.Where then
      begin
        if EditFirst then
          FEditPopup.Items.Add(NewItem(FEditPopup, '-'));
        EditFirst := False;
        FEditPopup.Items.Add(NewItem(FEditPopup, Cmd.Title));
      end;
    end;
  if FExtMenu.Count > 0 then
    FExtMenu.Add(NewLine);
  AddMenuItem(FExtMenu, rsReloadExtensions, 0, True, @MenuExtReloadClick);
  AddMenuItem(FExtMenu, rsOpenExtensionsFolder, 0, True, @MenuExtFolderClick);
  AddMenuItem(FExtMenu, rsExtensionsSettings, 0, True, @MenuExtSettingsClick);
end;

{ What a command gets: the repository, the file it was opened on (the
  popup's, else the one shown), the line under the editor's popup or
  the caret, counted in the file, and the selected text. }
function TRepoFrame.ExtContextJson(AItem: TMenuItem): string;
var
  J: TJSONObject;
  Path: string;
  Line: integer;
begin
  Path := FCurrentPath;
  Line := 0;
  if (AItem <> nil) and (AItem.GetParentMenu = FFilePopup) then
    Path := FContextPath
  else if (AItem <> nil) and (AItem.GetParentMenu = FEditPopup) then
  begin
    if (FPopupEd <> nil) and (FPopupRow >= 0) then
      Line := FileLineOfRow(FPopupEd, FPopupRow);
  end
  else if (FCurrentPath <> '') and (Edit.Carets.Count > 0) then
    Line := FileLineOfRow(Edit, Edit.Carets[0].PosY);
  if Line < 0 then
    Line := 0;
  J := TJSONObject.Create;
  try
    J.Add('repo', FRepo.Root);
    J.Add('path', Path);
    J.Add('line', Line);
    J.Add('selection', UTF8Encode(Edit.TextSelected));
    Result := J.AsJSON;
  finally
    J.Free;
  end;
end;

procedure TRepoFrame.ExtCommandClick(Sender: TObject);
var
  Eng: TGittanExtEngine;
  Item: TMenuItem;
begin
  Eng := TGittanExtEngine.Existing;
  if (Eng = nil) or not (Sender is TMenuItem) then
    Exit;
  Item := TMenuItem(Sender);
  if not Eng.RunCommand(Item.Hint, ExtContextJson(Item)) then
    RebuildExtMenu;
end;

{ Raises AEvent in the extensions with AJson (freed here) as its
  payload, the repository's root put in; False when an extension
  stopped it, which the banner says. }
function TRepoFrame.ExtFire(const AEvent: string; AJson: TJSONObject): boolean;
var
  Eng: TGittanExtEngine;
  Msg: string;
begin
  Result := True;
  try
    Eng := TGittanExtEngine.Existing;
    if (Eng = nil) or (Eng.Registry.ListenerCount = 0) then
      Exit;
    AJson.Add('repo', FRepo.Root);
    Result := Eng.Fire(AEvent, AJson.AsJSON, Msg);
    if not Result then
    begin
      if Msg = '' then
        Msg := rsExtCancelledDetail;
      BannerError(rsExtCancelled, Msg);
    end;
  finally
    AJson.Free;
  end;
end;

procedure TRepoFrame.ExtEmit(const AEvent: string; AJson: TJSONObject);
begin
  ExtFire(AEvent, AJson);
end;

{ What the events call a push and a pull. }
function ExtRemoteKind(AKind: TGittanRemoteKind): string;
begin
  case AKind of
    rkPush: Result := 'push';
    rkForcePush: Result := 'force';
    rkPushBranch: Result := 'branch';
    rkPushTag: Result := 'tag';
    rkPull: Result := 'pull';
    else
      Result := '';
  end;
end;

function ExtPullMode(AMode: TGittanPullMode): string;
begin
  case AMode of
    pmMerge: Result := 'merge';
    pmRebase: Result := 'rebase';
    else
      Result := 'auto';
  end;
end;

procedure TRepoFrame.MenuExtReloadClick(Sender: TObject);
begin
  App.Extensions.Reload;
end;

procedure TRepoFrame.MenuExtFolderClick(Sender: TObject);
begin
  OpenDocument(App.Extensions.Dir);
end;

{ The settings page's Reload: the extensions loaded again, and what is
  found now with the settings they declared. }
procedure TRepoFrame.ExtReloadForSettings(out AInfos: TGittanExtInfos;
  out ADefs: TGittanExtSettingDefs);
var
  Eng: TGittanExtEngine;
  i: integer;
begin
  App.Extensions.Reload;
  SetLength(AInfos, App.Extensions.Count);
  ADefs := nil;
  Eng := TGittanExtEngine.Existing;
  for i := 0 to App.Extensions.Count - 1 do
  begin
    AInfos[i] := App.Extensions.Info(i);
    if Eng <> nil then
      ADefs := Concat(ADefs, Eng.Registry.SettingsOf(AInfos[i].Id));
  end;
end;

procedure TRepoFrame.MenuExtSettingsClick(Sender: TObject);
begin
  OpenSettings(pgExtensions);
end;

procedure TRepoFrame.ExtAddCard(const ACard: TGittanReviewThread);
begin
  SetLength(FExtThreads, Length(FExtThreads) + 1);
  FExtThreads[High(FExtThreads)] := ACard;
  CollectShownThreads;
  FileTree.Invalidate;
  RebuildIfChanges;
end;

procedure TRepoFrame.ExtClearCards(const AExtId: string);
var
  Kept: TGittanReviewThreads;
  i, n: integer;
begin
  if Length(FExtThreads) = 0 then
    Exit;
  Kept := nil;
  n := 0;
  if AExtId <> '' then
    for i := 0 to High(FExtThreads) do
      if FExtThreads[i].Extension <> AExtId then
      begin
        SetLength(Kept, n + 1);
        Kept[n] := FExtThreads[i];
        Inc(n);
      end;
  if Length(Kept) = Length(FExtThreads) then
    Exit;
  FExtThreads := Kept;
  CollectShownThreads;
  FileTree.Invalidate;
  RebuildIfChanges;
end;

procedure TRepoFrame.ExtSetStatus(const AText: string; ASeconds: integer);
begin
  if AText = '' then
    FStatus.ClearMessage
  else if ASeconds <= 0 then
    FStatus.ShowMessage(AText, stNormal, MaxInt div 1000)
  else
    FStatus.ShowMessage(AText, stNormal, ASeconds);
end;

procedure TRepoFrame.ExtNotify(const ATitle, ADetail: string; AError: boolean);
begin
  if AError then
    BannerError(ATitle, ADetail)
  else
    BannerInfo(ATitle, ADetail);
end;

procedure TRepoFrame.ExtOpenFile(const APath: string; ALine: integer);
begin
  if APath <> '' then
    ShowFileLine(APath, ALine);
end;
