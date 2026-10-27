{ ---------------------------------------------------------------------------
  Markdown preview
  ---------------------------------------------------------------------------
  Included by umain.pp. With View > Preview on, a Markdown, HTML or SVG
  file in the change view or opened by itself gets FMdPreview right of
  the editor, behind FMdSplitter, at FMdRatio of the panel's width. The
  change view previews the new side (the diff lines that are not
  deleted ones), an SVG both sides, before over after, a page with its
  changes from the old side marked; a file opened to edits its text as
  it is typed, a pause of MdPreviewPause after the last key. ShowEditor
  brings the preview up to date; the views that hide the editor hide it
  too.

  The file header's Preview toggle switches the same setting for these
  files, and View > Translations for a .po file, the other way of
  showing a file the app has. }

{ The full path of the file the editor shows that the preview draws, ''
  when it shows none. }
function TRepoFrame.MarkdownPreviewPath: string;
begin
  Result := '';
  case FView of
    gvChanges:
      if FCurrentPath <> '' then
        Result := IncludeTrailingPathDelimiter(FRepo.Root) +
          SetDirSeparators(FCurrentPath);
    gvFile:
      Result := Edit.FileName;
  end;
  if not IsPreviewPath(Result) then
    Result := '';
end;

procedure TRepoFrame.UpdateMarkdownPreview;
var
  Path, Md, Old: string;
  i: integer;
begin
  Path := '';
  if FMdPreviewOn and Edit.Visible then
    Path := MarkdownPreviewPath;
  if Path = '' then
  begin
    HideMarkdownPreview;
    Exit;
  end;
  Old := '';
  if FView = gvChanges then
  begin
    Md := '';
    for i := 0 to FChangeLines.Count - 1 do
      if FChangeLines[i] <> '' then
      begin
        if FChangeLines[i][1] <> '-' then
          Md := Md + Copy(FChangeLines[i], 2, MaxInt) + LineEnding;
        if FChangeLines[i][1] <> '+' then
          Old := Old + Copy(FChangeLines[i], 2, MaxInt) + LineEnding;
      end;
  end
  else
    Md := UTF8Encode(Edit.Text);
  FMdPreview.SetFontSize(EditorFontSize(Edit));
  if not FMdPreview.Visible then
  begin
    FMdPreview.Width := Round(EditorPanel.ClientWidth * FMdRatio);
    FMdPreview.Visible := True;
    FMdSplitter.Visible := True;
    { Left of the page, where alRight places the later of the two. }
    FMdSplitter.Left := FMdPreview.Left - 1;
    { The old side's share is of what is left. }
    ApplyLayout;
  end;
  if FView = gvChanges then
    FMdPreview.ShowChange(Path, Old, Md)
  else
    FMdPreview.ShowFile(Path, Md);
end;

procedure TRepoFrame.HideMarkdownPreview;
begin
  FMdTimer.Enabled := False;
  if not FMdPreview.Visible then
    Exit;
  FMdPreview.Visible := False;
  FMdSplitter.Visible := False;
  FMdPreview.Clear;
  if Edit.Visible then
    ApplyLayout;
end;

procedure TRepoFrame.MenuMarkdownPreviewClick(Sender: TObject);
begin
  FMdPreviewOn := not FMdPreviewOn;
  FMdPreviewItem.Checked := FMdPreviewOn;
  UpdateMarkdownPreview;
  UpdatePreviewToggle;
end;

{ The file the header's toggle is for: a .po file in the change view
  without conflicts or in the translation view, or a file the preview
  draws; '' for none. }
function TRepoFrame.PreviewTogglePath: string;
begin
  Result := '';
  case FView of
    gvChanges, gvFile:
      begin
        if FView = gvChanges then
          Result := FCurrentPath
        else
          Result := Edit.FileName;
        if IsPoPath(Result) and (FConflictRoles = nil) then
          Exit;
      end;
    gvTranslation:
      if FCurrentPath <> '' then
        Exit(FCurrentPath)
      else
        Exit(FTranslationFile);
  end;
  if not IsPreviewPath(Result) then
    Result := '';
end;

procedure TRepoFrame.UpdatePreviewToggle;
var
  Path: string;
begin
  Path := PreviewTogglePath;
  if Path = '' then
    FHeader.SetToggle('', '', False)
  else if IsPoPath(Path) then
    FHeader.SetToggle(rsPreviewToggle, Format(rsTranslationsHint,
      [ShortCutToText(FTranslationsItem.ShortCut)]), FTranslations)
  else
    FHeader.SetToggle(rsPreviewToggle, Format(rsPreviewHint,
      [ShortCutToText(FMdPreviewItem.ShortCut)]), FMdPreviewOn);
end;

{ The header's toggle does what its menu item does. }
procedure TRepoFrame.HeaderToggle(Sender: TObject);
begin
  if IsPoPath(PreviewTogglePath) then
    MenuTranslationsClick(Sender)
  else
    MenuMarkdownPreviewClick(Sender);
end;

procedure TRepoFrame.MdSplitterMoved(Sender: TObject);
begin
  if EditorPanel.ClientWidth > 0 then
    FMdRatio := FMdPreview.Width / EditorPanel.ClientWidth;
  if FEditOld.Visible then
    FEditOld.Width := Round(SidesWidth * FSideRatio);
end;

{ An edit of the file shown is previewed once typing pauses. }
procedure TRepoFrame.EditChange(Sender: TObject);
begin
  if FMdPreview.Visible and (FView = gvFile) then
  begin
    FMdTimer.Enabled := False;
    FMdTimer.Enabled := True;
  end;
end;

procedure TRepoFrame.MdTimerTimer(Sender: TObject);
begin
  FMdTimer.Enabled := False;
  UpdateMarkdownPreview;
end;

{ A link in the preview to a file of the repository shows it as the tree
  would; any other local file is opened by itself. }
procedure TRepoFrame.MdPreviewOpenFile(Sender: TObject; const AFileName: string);
var
  Root: string;
begin
  Root := IncludeTrailingPathDelimiter(FRepo.Root);
  if (FRepo.Root <> '') and (Copy(AFileName, 1, Length(Root)) = Root) then
    ShowRepoFile(StringReplace(Copy(AFileName, Length(Root) + 1, MaxInt),
      PathDelim, '/', [rfReplaceAll]))
  else
    OpenFile(AFileName);
end;
