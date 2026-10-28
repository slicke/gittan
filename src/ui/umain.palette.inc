{ ---------------------------------------------------------------------------
  Command palette
  ---------------------------------------------------------------------------
  Go > Command Palette... (Cmd+P, Ctrl+P elsewhere) shows a list across
  the top of the frame with every action the menus offer right now: the
  items that are visible and enabled, after the menus' own open handlers
  have brought them up to date, each named by its menu path ("Branch:
  Switch Branch...") with its shortcut on the right and checked as in
  its menu. The Syntax menu,
  hundreds of lexers, is left out. The actions last run from it come
  first (Settings.PaletteRecent, kept across runs); typing keeps the rows
  that have every word typed. A pick lists the menus again and clicks the
  item with that name, so a menu rebuilt meanwhile is no dangling item. }
const
  PaletteSep = ': ';

{ The actions of the menus (and of the application menu on macOS), by
  name, each with its menu item as the object, in menu order. }
procedure TRepoFrame.ListPaletteActions(AList: TStringList);

  procedure Walk(AItem: TMenuItem; const APrefix: string);
  var
    i: integer;
    Child: TMenuItem;
    Path: string;
  begin
    for i := 0 to AItem.Count - 1 do
    begin
      Child := AItem.Items[i];
      if Child.IsLine or not Child.Visible or not Child.Enabled or
        (Child = FSyntaxMenu) or (Child = FPaletteItem) then
        Continue;
      Path := StripHotkey(Child.Caption);
      if Path = '' then
        Continue;
      if APrefix <> '' then
        Path := APrefix + PaletteSep + Path;
      if Child.Count > 0 then
      begin
        { What the menu does as it opens, such as enabling its items. }
        if Assigned(Child.OnClick) then
          Child.OnClick(Child);
        Walk(Child, Path);
      end
      else if Assigned(Child.OnClick) then
        AList.AddObject(Path, Child);
    end;
  end;

begin
  AList.Clear;
  if FMainMenu <> nil then
    Walk(FMainMenu.Items, '');
  {$IFDEF LCLCocoa}
  if FAppMenuItem <> nil then
    Walk(FAppMenuItem, 'Gittan');
  {$ENDIF}
end;

procedure TRepoFrame.MenuPaletteClick(Sender: TObject);
var
  Actions: TStringList;
  Recent: TStringList;
  i, j: integer;
  Added: boolean;

  { A row for the action at AIndex in Actions, checked as in its menu. }
  procedure AddRow(AIndex: integer);
  var
    Item: TMenuItem;
  begin
    Item := TMenuItem(Actions.Objects[AIndex]);
    FPalettePopup.Add(Actions[AIndex], ShortcutLabel(Item.ShortCut), Item.Checked,
      FPaletteNames.Add(Actions[AIndex]));
  end;

begin
  Actions := TStringList.Create;
  try
    ListPaletteActions(Actions);
    FPaletteNames.Clear;
    FPalettePopup.Clear;
    Recent := App.Settings.PaletteRecent;
    Added := False;
    for i := 0 to Recent.Count - 1 do
    begin
      j := Actions.IndexOf(Recent[i]);
      if j < 0 then
        Continue;
      if not Added then
        FPalettePopup.AddHeader(rsPaletteRecent);
      Added := True;
      AddRow(j);
    end;
    if Added then
      FPalettePopup.AddHeader(rsPaletteOther);
    for i := 0 to Actions.Count - 1 do
      if not Added or (Recent.IndexOf(Actions[i]) < 0) then
        AddRow(i);
  finally
    Actions.Free;
  end;
  FPalettePopup.PopupCentered(FTitleBarHeight + Px(8));
  ShowPaletteSides;
end;

{ ---------------------------------------------------------------------------
  The buttons beside the palette
  ---------------------------------------------------------------------------
  Undo, Redo and Stash on the left of the palette, Pull, Push and New
  Branch on the right, while it is open: the menu items themselves,
  dimmed while disabled (the palette has just run the menus' own open
  handlers), the item's whole caption and shortcut as the hint. They
  are the palette's keepers, so a press on one leaves it open until the
  click, which closes it and clicks the item. A window too narrow for
  them beside the palette shows none. }
procedure TRepoFrame.ShowPaletteSides;
const
  Gap = 10;

  procedure Tile(ASide: TGittanPaletteSide; const ACaption, AIcon: string;
    AItem: TMenuItem);
  var
    Tip: string;
  begin
    Tip := StripHotkey(AItem.Caption);
    if AItem.ShortCut <> 0 then
      Tip := Tip + ' (' + ShortcutLabel(AItem.ShortCut) + ')';
    ASide.Add(ACaption, AIcon, Tip, AItem.Visible and AItem.Enabled, AItem);
  end;

begin
  FPaletteLeft.Clear;
  Tile(FPaletteLeft, rsPsUndo, HintUndo, FUndoItem);
  Tile(FPaletteLeft, rsPsRedo, HintRedo, FRedoItem);
  Tile(FPaletteLeft, rsPsStash, HintStash, FStashAllItem);
  FPaletteRight.Clear;
  Tile(FPaletteRight, rsPsPull, HintDown, FPullItem);
  Tile(FPaletteRight, rsPsPush, HintUp, FPushItem);
  Tile(FPaletteRight, rsPsBranch, HintBranch, FNewBranchItem);
  FPaletteLeft.Fit;
  FPaletteRight.Fit;
  if FPalettePopup.Left - Px(Gap) - FPaletteLeft.Width < Px(Gap) then
    Exit;
  FPaletteLeft.SetBounds(FPalettePopup.Left - Px(Gap) - FPaletteLeft.Width,
    FPalettePopup.Top, FPaletteLeft.Width, FPaletteLeft.Height);
  FPaletteRight.SetBounds(FPalettePopup.Left + FPalettePopup.Width + Px(Gap),
    FPalettePopup.Top, FPaletteRight.Width, FPaletteRight.Height);
  FPaletteLeft.Visible := True;
  FPaletteRight.Visible := True;
  FPaletteLeft.BringToFront;
  FPaletteRight.BringToFront;
end;

procedure TRepoFrame.PalettePopupClose(Sender: TObject);
begin
  FPaletteLeft.Visible := False;
  FPaletteRight.Visible := False;
end;

procedure TRepoFrame.PaletteSideClick(Sender: TObject; AIndex: integer);
var
  Item: TObject;
begin
  Item := (Sender as TGittanPaletteSide).DataOf(AIndex);
  FPalettePopup.Close;
  if (Item is TMenuItem) and TMenuItem(Item).Enabled then
    TMenuItem(Item).Click;
end;

procedure TRepoFrame.PalettePopupPick(Sender: TObject; AIndex: integer);
var
  Actions: TStringList;
  Path: string;
  i: integer;
begin
  i := FPalettePopup.TagOf(AIndex);
  if (i < 0) or (i >= FPaletteNames.Count) then
    Exit;
  Path := FPaletteNames[i];
  Actions := TStringList.Create;
  try
    ListPaletteActions(Actions);
    i := Actions.IndexOf(Path);
    if i < 0 then
      Exit;
    App.Settings.AddPaletteRecent(Path);
    TMenuItem(Actions.Objects[i]).Click;
  finally
    Actions.Free;
  end;
end;
