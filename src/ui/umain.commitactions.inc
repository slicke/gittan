{ ---------------------------------------------------------------------------
  The commit menu
  ---------------------------------------------------------------------------
  A right click on a commit in the commit graph (or the Menu key) shows
  what can be done with it: show it, compare the work tree with it,
  write it as a patch, switch to a branch on it, make a branch
  or a tag there, merge it, cherry-pick or revert it, reset the branch
  to it, copy its id. The menu is built for the commit each time, since
  what applies depends on it (Rebase Interactively from Here... lists
  the commits after it, see umain.rebase.inc): a merge commit cannot be cherry-picked or
  reverted here (git wants its mainline), a commit already in HEAD's
  history is not merged or cherry-picked again, and nothing that moves
  HEAD is offered while git is in the middle of something or a job runs.
  The graph closes when an item is picked; after an action that changes
  the history it opens again, so the result is in view. A merge,
  cherry-pick or revert that stops with conflicts leaves them to the
  Commit section. The watcher is stopped meanwhile, as for a switch.
  Two commits are compared through a mark: Mark for Comparison keeps
  one (FMarkHash, by the name it goes by in FMarkName, shown in the
  accent in the graph, which stays open), and the menu of another then
  offers Compare with Marked <name>: the base becomes the range from
  the older of the two to the newer (by their times, FMarkDate), so the
  views show what changed between them going forward. The mark also
  bounds a patch series: Create Patch Series with Marked <name>...
  writes every commit between the two (umain.patches.inc). The Bisect
  submenu starts a bisect from the commit, or marks it while git
  bisects (umain.bisect.inc). Export Files as Archive... writes the
  commit's files as a zip or tar.gz where a save dialog says
  (ExportArchive, which the tag menu offers too), and Add or Edit
  Note... the commit's note (git notes), kept beside the commit and
  shown in the summary's card (EditNoteAsk). Neither changes the
  history, so the graph stays open. }
const
  caShow = 1;
  caCompare = 2;
  caSwitch = 3;
  caBranch = 4;
  caTag = 5;
  caMerge = 6;
  caCherryPick = 7;
  caRevert = 8;
  caResetSoft = 9;
  caResetMixed = 10;
  caResetHard = 11;
  caCopy = 12;
  caForge = 13;
  caMark = 14;
  caCompareMarked = 15;
  caRebase = 16;
  caBrowse = 17;
  caBisectStartGood = 18;
  caBisectStartBad = 19;
  caBisectGood = 20;
  caBisectBad = 21;
  caBisectSkip = 22;
  caBisectEnd = 23;
  caPatch = 24;
  caPatchSeries = 25;
  caFixup = 26;
  caArchive = 27;
  caNote = 28;

{ The commit by the name a person knows it by: a local branch on it,
  else a remote one, else a tag, else its short id. }
function TRepoFrame.CommitKnownName(const ACommit: TGittanGraphCommit): string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(ACommit.Refs) do
    if (Result = '') and (ACommit.Refs[i].Kind = grBranch) then
      Result := ACommit.Refs[i].Name;
  for i := 0 to High(ACommit.Refs) do
    if (Result = '') and (ACommit.Refs[i].Kind in [grRemote, grTag]) then
      Result := ACommit.Refs[i].Name;
  if Result = '' then
    Result := ACommit.Short;
end;

{ A commit dragged onto HEAD's row in the graph: a menu with the merge
  of it into the branch, the commit menu's own item, so a drag let go
  by mistake does nothing. A commit HEAD already has says so instead. }
procedure TRepoFrame.GraphDrop(Sender: TObject; const ASource, ATarget: TGittanGraphCommit;
  const AScreenPos: TPoint);
var
  Item: TMenuItem;
begin
  if FRepo.Root = '' then
    Exit;
  FActionCommit := ASource;
  FActionName := CommitKnownName(ASource);
  FCommitPopup.Items.Clear;
  if FRepo.IsAncestor(ASource.Hash, 'HEAD') then
    AddMenuItem(FCommitPopup.Items, Format(rsCaDropInHead,
      [StringReplace(FActionName, '&', '&&', [rfReplaceAll]),
      StringReplace(ResetTarget, '&', '&&', [rfReplaceAll])]), 0, False, nil)
  else
  begin
    Item := AddMenuItem(FCommitPopup.Items, Format(rsCaMerge,
      [StringReplace(FActionName, '&', '&&', [rfReplaceAll]),
      StringReplace(FBranch, '&', '&&', [rfReplaceAll])]), caMerge, not RepoBusy,
      @CommitMenuClick);
    Item.Default := True;
  end;
  FCommitPopup.PopUp(AScreenPos.X, AScreenPos.Y);
end;

procedure TRepoFrame.GraphContext(Sender: TObject; const ACommit: TGittanGraphCommit;
  const AScreenPos: TPoint);
begin
  if FRepo.Root = '' then
    Exit;
  FillCommitMenu(FCommitPopup.Items, ACommit);
  FCommitPopup.PopUp(AScreenPos.X, AScreenPos.Y);
end;

{ The commit menu's items for ACommit, under ARoot: the graph's popup,
  or Commit > Commit abc1234 for the commit shown (FillBranchCommitMenu). }
procedure TRepoFrame.FillCommitMenu(ARoot: TMenuItem; const ACommit: TGittanGraphCommit);
var
  Busy, Jobs, InHead, IsHead, IsMerge: boolean;
  Known: string;
  i: integer;
  Item, Sub: TMenuItem;

  { A name in a caption, its ampersands doubled so none is taken for an
    accelerator. }
  function Amp(const AName: string): string;
  begin
    Result := StringReplace(AName, '&', '&&', [rfReplaceAll]);
  end;

  function Add(AParent: TMenuItem; const ACaption: string; ATag: integer;
    AEnabled: boolean = True): TMenuItem;
  begin
    if AParent = nil then
      AParent := ARoot;
    Result := AddMenuItem(AParent, ACaption, ATag, AEnabled, @CommitMenuClick);
  end;

  procedure Line;
  begin
    ARoot.Add(NewLine);
  end;

begin
  FActionCommit := ACommit;
  Jobs := (FCommitJob <> nil) or (FRemoteJob <> nil);
  Busy := RepoBusy;
  InHead := FRepo.IsAncestor(ACommit.Hash, 'HEAD');
  IsMerge := Length(ACommit.Parents) > 1;
  IsHead := False;
  for i := 0 to High(ACommit.Refs) do
    if ACommit.Refs[i].Kind = grHead then
      IsHead := True;
  Known := CommitKnownName(ACommit);
  FActionName := Known;

  ARoot.Clear;
  Add(nil, rsCaShow, caShow);
  Add(nil, rsCaCompare, caCompare);
  Add(nil, rsCaBrowse, caBrowse);
  Add(nil, rsCaArchive, caArchive);
  if FMarkHash = ACommit.Hash then
    Add(nil, rsCaUnmark, caMark)
  else
    Add(nil, rsCaMark, caMark);
  if (FMarkHash <> '') and (FMarkHash <> ACommit.Hash) then
    Add(nil, Format(rsCaCompareMarked, [Amp(FMarkName)]), caCompareMarked);
  Add(nil, rsCaPatch, caPatch, not IsMerge);
  { A series runs along one line of history, so one of the two must be
    in the other's. }
  if (FMarkHash <> '') and (FMarkHash <> ACommit.Hash) then
    Add(nil, Format(rsCaPatchSeries, [Amp(FMarkName)]), caPatchSeries,
      FRepo.IsAncestor(FMarkHash, ACommit.Hash) or FRepo.IsAncestor(ACommit.Hash, FMarkHash));
  Line;
  for i := 0 to High(ACommit.Refs) do
    if (ACommit.Refs[i].Kind = grBranch) and (ACommit.Refs[i].Name <> FBranch) then
    begin
      Item := Add(nil, Format(rsCaSwitch, [Amp(ACommit.Refs[i].Name)]), caSwitch, not Busy);
      Item.Hint := ACommit.Refs[i].Name;
    end;
  Add(nil, rsCaBranch, caBranch, not Busy);
  Add(nil, rsCaTag, caTag);
  Line;
  Add(nil, Format(rsCaMerge, [Amp(Known), Amp(FBranch)]), caMerge, not Busy and not InHead);
  Add(nil, Format(rsCaCherryPick, [Amp(FBranch)]), caCherryPick,
    not Busy and not InHead and not IsMerge);
  Add(nil, rsCaRevert, caRevert, not Busy and InHead and not IsMerge);
  Add(nil, rsCaRebase, caRebase, not Busy and InHead and not IsHead);
  { The ticked files as a fixup of this commit, for the rebase to fold
    in; of a commit on the branch, while the tree chooses a commit
    without Amend and no file is in conflict. }
  Add(nil, rsCaFixup, caFixup, not Busy and not Jobs and InHead and CommitChoosing and
    (FChosenCount > 0) and not FCommitAmend.Checked and (FConflictFiles = 0));
  Sub := Add(nil, Format(rsCaReset, [Amp(ResetTarget)]), 0, not Busy);
  Sub.OnClick := nil;
  Add(Sub, rsCaResetSoft, caResetSoft);
  Add(Sub, rsCaResetMixed, caResetMixed);
  Add(Sub, rsCaResetHard, caResetHard);
  Sub := Add(nil, rsCaBisect, 0, not Jobs and ((FOperation = '') or (FOperation = 'bisecting')));
  Sub.OnClick := nil;
  if FOperation = 'bisecting' then
  begin
    Add(Sub, rsCaBisectGood, caBisectGood);
    Add(Sub, rsCaBisectBad, caBisectBad);
    Add(Sub, rsCaBisectSkip, caBisectSkip);
    Sub.Add(NewLine);
    Add(Sub, rsCaBisectEnd, caBisectEnd);
  end
  else
  begin
    { A good commit for the bisect is one HEAD has, so HEAD is bad. }
    Add(Sub, Format(rsCaBisectStartGood, [Amp(ResetTarget)]), caBisectStartGood,
      InHead and not IsHead);
    Add(Sub, rsCaBisectStartBad, caBisectStartBad);
  end;
  Line;
  if ACommit.Note = '' then
    Add(nil, rsCaNoteAdd, caNote, not Jobs)
  else
    Add(nil, rsCaNoteEdit, caNote, not Jobs);
  Add(nil, rsCopyHash, caCopy);
  if Assigned(FForge) then
    Add(nil, Format(rsOpenCommitOnForge, [ForgeName]), caForge);
end;

{ Commit > Commit, filled as the Branch menu opens (and for the command
  palette): the commit menu of the commit shown against its parent
  (picked in the graph, the blame band or Older and Newer), named by
  its short id; without one, an item that opens the graph to pick one
  in. }
procedure TRepoFrame.FillBranchCommitMenu;
var
  Commit: TGittanGraphCommit;
begin
  if FBranchCommitMenu = nil then
    Exit;
  { The menu is built before the repository object is. }
  if (FRepo <> nil) and (FRepo.Root <> '') and BlameShown and
    (FBranchCommit.Hash <> FBlameCommit.Hash) then
    if not FRepo.GraphCommit(FBlameCommit.Hash, FBranchCommit) then
      FBranchCommit := Default(TGittanGraphCommit);
  if (FRepo <> nil) and (FRepo.Root <> '') and BlameShown and
    (FBranchCommit.Hash = FBlameCommit.Hash) and (FBranchCommit.Hash <> '') then
  begin
    Commit := FBranchCommit;
    FBranchCommitMenu.Caption := Format(rsBmCommitMenu, [Commit.Short]);
    FillCommitMenu(FBranchCommitMenu, Commit);
    FBranchCommitMenu.Visible := True;
    FPickCommitItem.Visible := False;
    Exit;
  end;
  { No commit shown: a plain item in its place, so neither the menu nor
    the palette says "Commit: Commit". }
  FBranchCommitMenu.Clear;
  FBranchCommitMenu.Visible := False;
  FPickCommitItem.Visible := True;
  FPickCommitItem.Enabled := (FRepo <> nil) and (FRepo.Root <> '');
end;

procedure TRepoFrame.MenuPickCommitClick(Sender: TObject);
begin
  ShowCommitGraph;
end;

{ A new branch is asked a name for and switched to; a tag a name and a
  message, which makes it annotated (none, a lightweight one); a reset
  asks first, saying what it keeps. }
procedure TRepoFrame.CommitMenuClick(Sender: TObject);
var
  Hash, Short, Note, Ref: string;
  Ok, Conflicts, Reopen: boolean;
  Way: TGittanMergeWay;
begin
  Hash := FActionCommit.Hash;
  Short := FActionCommit.Short;
  if (FRepo.Root = '') or (Hash = '') then
    Exit;
  if (Sender as TMenuItem).Tag = caMark then
  begin
    if FMarkHash = Hash then
    begin
      FMarkHash := '';
      FMarkName := '';
    end
    else
    begin
      FMarkHash := Hash;
      FMarkName := FActionName;
      FMarkDate := FActionCommit.Date;
    end;
    FGraph.Marked := FMarkHash;
    Exit;
  end;
  if (Sender as TMenuItem).Tag = caBrowse then
  begin
    BrowseCommit(Hash, FActionName, FActionCommit.Subject);
    Exit;
  end;
  { Patches, an archive and a note change no history, so the graph stays
    open behind the dialog. }
  if (Sender as TMenuItem).Tag = caPatch then
  begin
    CreatePatches('', Hash);
    Exit;
  end;
  if (Sender as TMenuItem).Tag = caArchive then
  begin
    ExportArchive(Hash, FActionName);
    Exit;
  end;
  if (Sender as TMenuItem).Tag = caNote then
  begin
    EditNoteAsk(FActionCommit);
    Exit;
  end;
  if (Sender as TMenuItem).Tag = caPatchSeries then
  begin
    if FRepo.IsAncestor(FMarkHash, Hash) then
      CreatePatches(FMarkHash, Hash)
    else
      CreatePatches(Hash, FMarkHash);
    Exit;
  end;
  FGraph.Close;
  case (Sender as TMenuItem).Tag of
    caShow:
      ShowBlameCommit(Hash);
    caCompare:
      SetBase(Hash);
    caCompareMarked:
      if FMarkDate > FActionCommit.Date then
        SetBase(FActionName + '..' + FMarkName)
      else
        SetBase(FMarkName + '..' + FActionName);
    caSwitch:
      SwitchBranch((Sender as TMenuItem).Hint);
    caCopy:
      Clipboard.AsText := Hash;
    caForge:
      OpenOnForge(CommitTarget(Hash));
    caRebase:
      RebaseInteractiveAsk(Hash, Short, True);
    caFixup:
      StartFixupCommit(FActionCommit);
    caBisectStartGood, caBisectStartBad, caBisectGood, caBisectBad, caBisectSkip:
    begin
      case (Sender as TMenuItem).Tag of
        caBisectStartGood: BisectStartAt('HEAD', Hash);
        caBisectStartBad: BisectStartAt(Hash, '');
        caBisectGood: BisectMarkCommit(Hash, bmGood);
        caBisectBad: BisectMarkCommit(Hash, bmBad);
        else
          BisectMarkCommit(Hash, bmSkip);
      end;
      { The graph again for the next mark, until the bisect is done. }
      if (FOperation = 'bisecting') and (FBisect.Found = '') and
        (Length(FBisect.Suspects) = 0) then
        ShowCommitGraph;
    end;
    caBisectEnd:
      BisectEndClick;
    caBranch:
      if NewBranchAsk(Format(rsCaBranchPrompt, [Short]), Hash) then
        ShowCommitGraph;
    caTag:
      if TagAtAsk(Short, Hash) then
        ShowCommitGraph;
    caResetSoft:
      if ResetToAsk(Hash, Short, rmSoft) then
        ShowCommitGraph;
    caResetMixed:
      if ResetToAsk(Hash, Short, rmMixed) then
        ShowCommitGraph;
    caResetHard:
      if ResetToAsk(Hash, Short, rmHard) then
        ShowCommitGraph;
    caMerge:
    begin
      { By the name it goes by while that is still the commit, so git's
        message says "Merge branch 'feature'". The question and the
        merge are the branch list's. }
      if FRepo.CommitId(FActionName) = Hash then
        Ref := FActionName
      else
        Ref := Hash;
      if AskMergeWay(Ref, FActionName, Way) and RunMerge(Ref, FActionName, Way) then
        ShowCommitGraph;
    end;
    caCherryPick, caRevert:
    begin
      StopWatcher;
      try
        Screen.Cursor := crHourGlass;
        Conflicts := False;
        Reopen := True;
        try
          case (Sender as TMenuItem).Tag of
            caCherryPick:
            begin
              Ok := FRepo.CherryPick(Hash, Conflicts);
              Note := Format(rsCaPicked, [Short]);
            end;
            else
            begin
              Ok := FRepo.RevertCommit(Hash, Conflicts);
              Note := Format(rsCaReverted, [Short]);
            end;
          end;
        finally
          Screen.Cursor := crDefault;
        end;
        FLoadError := '';
        FSummary.Notice := '';
        RefreshRepository;
      finally
        StartWatcher;
      end;
      if Ok then
        StatusNote(Note)
      else if Conflicts then
      begin
        StatusNote(rsCaConflicts, True);
        Reopen := False;
      end
      else
      begin
        BannerError(rsCaFailed, FRepo.Error);
        Reopen := False;
      end;
      if Reopen then
        ShowCommitGraph;
    end;
  end;
end;

{ What a reset moves: the current branch, or HEAD while it is on none. }
function TRepoFrame.ResetTarget: string;
begin
  if FBranch <> '' then
    Result := FBranch
  else
    Result := 'HEAD';
end;

{ Asks before a reset to AHash (AShort), saying which commits leave the
  branch and what AMode keeps. From the reflog the commit may be ahead
  of HEAD, or on another line, and not only behind it. }
function TRepoFrame.ResetAsk(const AHash, AShort: string; AMode: TGittanResetMode): boolean;
var
  Ask, Note: string;
  Forward: boolean;
begin
  Forward := False;
  if FRepo.IsAncestor(AHash, 'HEAD') then
    Ask := rsCaResetAsk
  else if FRepo.IsAncestor('HEAD', AHash) then
  begin
    Ask := rsCaResetForwardAsk;
    Forward := True;
  end
  else
    Ask := rsCaResetAwayAsk;
  { Going forward no commit leaves, so only a hard reset loses something. }
  case AMode of
    rmSoft: Note := rsCaResetSoftAsk;
    rmHard: Note := rsCaResetHardAsk;
    else
      Note := rsCaResetMixedAsk;
  end;
  if Forward then
    if AMode = rmHard then
      Note := rsCaResetForwardHardAsk
    else
      Note := '';
  Ask := Format(Ask, [ResetTarget, AShort]);
  if Note <> '' then
    Ask := Ask + LineEnding + LineEnding + Note;
  Result := AskDlg(rsCaResetTitle, Ask, mtWarning, [mrYes, rsCaResetAction, mrCancel,
    rsCancelButton, 'IsCancel', 'IsDefault'], 0) = mrYes;
end;

{ A reset to AHash (AShort) with AMode after ResetAsk, from the commit
  menu and the reflog. True when it was done. }
function TRepoFrame.ResetToAsk(const AHash, AShort: string; AMode: TGittanResetMode): boolean;
begin
  Result := False;
  if RepoBusy or not ResetAsk(AHash, AShort, AMode) then
    Exit;
  StopWatcher;
  try
    Screen.Cursor := crHourGlass;
    try
      Result := FRepo.Reset(AHash, AMode);
    finally
      Screen.Cursor := crDefault;
    end;
    FLoadError := '';
    FSummary.Notice := '';
    RefreshRepository;
  finally
    StartWatcher;
  end;
  if Result then
    StatusNote(Format(rsCaWasReset, [ResetTarget, AShort]))
  else
    BannerError(rsCaFailed, FRepo.Error);
end;

{ The files of AHash as an archive: a save dialog offers a zip and a
  tar.gz, named after the repository and AName (the name the commit
  goes by), and git writes the format the extension names, every path
  under a folder named as the file. The file is shown in Finder (or
  the file manager) when written. }
procedure TRepoFrame.ExportArchive(const AHash, AName: string);
var
  Dlg: TSaveDialog;
  Base, Target, Prefix: string;
  Ok: boolean;
  i: integer;
begin
  if (FRepo.Root = '') or (AHash = '') then
    Exit;
  Base := ExtractFileName(ExcludeTrailingPathDelimiter(FRepo.Root));
  if AName <> '' then
    Base := Base + '-' + AName;
  { A ref's slash or space is no file name. }
  for i := 1 to Length(Base) do
    if Base[i] in ['/', '\', ':', ' ', '"', '*', '?', '<', '>', '|'] then
      Base[i] := '-';
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title := rsArchiveTitle;
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    Dlg.Filter := rsArchiveFilter;
    Dlg.DefaultExt := 'zip';
    Dlg.FileName := Base + '.zip';
    Dlg.InitialDir := ExtractFileDir(ExcludeTrailingPathDelimiter(FRepo.Root));
    if not Dlg.Execute then
      Exit;
    Target := Dlg.FileName;
    { The second filter picked but the name left without its extension,
      or with the .gz alone that the Cocoa panel adds for it. }
    if (Dlg.FilterIndex = 2) and not AnsiEndsText('.tar.gz', Target) and
      not AnsiEndsText('.tgz', Target) and not AnsiEndsText('.tar', Target) then
    begin
      if AnsiEndsText('.zip', Target) then
        Target := Copy(Target, 1, Length(Target) - 4)
      else if AnsiEndsText('.gz', Target) then
        Target := Copy(Target, 1, Length(Target) - 3);
      Target := Target + '.tar.gz';
      { The dialog asked about the name before it got the extension. }
      if FileExists(Target) and (AskDlg(rsArchiveTitle, Format(rsArchiveReplace,
        [ExtractFileName(Target)]), mtWarning, [mrYes, rsArchiveReplaceAction, mrCancel,
        rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes) then
        Exit;
    end;
    Prefix := ExtractFileName(Target);
    if AnsiEndsText('.tar.gz', Prefix) then
      Prefix := Copy(Prefix, 1, Length(Prefix) - 7)
    else
      Prefix := ChangeFileExt(Prefix, '');
    if Prefix = '' then
      Prefix := Base;
    Screen.Cursor := crHourGlass;
    try
      Ok := FRepo.Archive(AHash, Target, Prefix + '/');
    finally
      Screen.Cursor := crDefault;
    end;
    if Ok then
    begin
      StatusNote(Format(rsArchiveWritten, [ShortPath(Target)]));
      RevealFile(Target);
    end
    else
      BannerError(rsArchiveFailed, FRepo.Error);
  finally
    Dlg.Free;
  end;
end;

{ Shows AFile selected in Finder, Explorer or, where neither is, its
  folder in the file manager. }
procedure TRepoFrame.RevealFile(const AFile: string);
begin
  {$IFDEF DARWIN}
  RunDetached('open', ['-R', AFile]);
  {$ELSE}
  {$IFDEF WINDOWS}
  RunDetached('explorer.exe', ['/select,' + AFile]);
  {$ELSE}
  RunDetached('xdg-open', [ExtractFileDir(AFile)]);
  {$ENDIF}
  {$ENDIF}
end;

{ The note of ACommit in a dialog; saved, the card of the commit shown
  and the graph's rows read it again (a note is searched with the
  message). }
procedure TRepoFrame.EditNoteAsk(const ACommit: TGittanGraphCommit);
var
  NoteText: string;
  Ok: boolean;
begin
  if (FRepo.Root = '') or (ACommit.Hash = '') then
    Exit;
  NoteText := ACommit.Note;
  if not EditCommitNote(CommitKnownName(ACommit), NoteText) or (NoteText = ACommit.Note) then
    Exit;
  Screen.Cursor := crHourGlass;
  try
    Ok := FRepo.SetNote(ACommit.Hash, NoteText);
  finally
    Screen.Cursor := crDefault;
  end;
  if not Ok then
  begin
    BannerError(rsNoteFailed, FRepo.Error);
    Exit;
  end;
  if NoteText = '' then
    StatusNote(Format(rsNoteRemoved, [ACommit.Short]))
  else
    StatusNote(Format(rsNoteSaved, [ACommit.Short]));
  { The card of the commit shown reads the note again: the base is the
    same, so SetBase alone would leave it. }
  if BlameShown and (FBlameCommit.Hash = ACommit.Hash) then
  begin
    ShowBlameCommit(ACommit.Hash);
    FSummary.SetCommit(FBlameCommit, FBlameBody, FBlameSignature);
  end;
  if FGraph.Visible then
    GraphReload(nil);
  { Commit > Commit names the note's item by whether there is one. }
  FBranchCommit := Default(TGittanGraphCommit);
end;
