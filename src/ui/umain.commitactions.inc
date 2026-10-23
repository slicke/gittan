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
  bisects (umain.bisect.inc). }
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
  caGitHub = 13;
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

procedure TForm1.GraphContext(Sender: TObject; const ACommit: TGittanGraphCommit;
  const AScreenPos: TPoint);
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
    Result := TMenuItem.Create(FCommitPopup);
    Result.Caption := ACaption;
    Result.Tag := ATag;
    Result.Enabled := AEnabled;
    Result.OnClick := @CommitMenuClick;
    if AParent = nil then
      FCommitPopup.Items.Add(Result)
    else
      AParent.Add(Result);
  end;

  procedure Line;
  begin
    FCommitPopup.Items.Add(NewLine);
  end;

begin
  if FRepo.Root = '' then
    Exit;
  FActionCommit := ACommit;
  Jobs := (FCommitJob <> nil) or (FRemoteJob <> nil);
  Busy := RepoBusy;
  InHead := FRepo.IsAncestor(ACommit.Hash, 'HEAD');
  IsMerge := Length(ACommit.Parents) > 1;
  IsHead := False;
  for i := 0 to High(ACommit.Refs) do
    if ACommit.Refs[i].Kind = grHead then
      IsHead := True;
  { The commit by the name a person knows it by: a local branch on it,
    else a remote one, else a tag, else its short id. }
  Known := '';
  for i := 0 to High(ACommit.Refs) do
    if (Known = '') and (ACommit.Refs[i].Kind = grBranch) then
      Known := ACommit.Refs[i].Name;
  for i := 0 to High(ACommit.Refs) do
    if (Known = '') and (ACommit.Refs[i].Kind in [grRemote, grTag]) then
      Known := ACommit.Refs[i].Name;
  if Known = '' then
    Known := ACommit.Short;
  FActionName := Known;

  FCommitPopup.Items.Clear;
  Add(nil, rsCaShow, caShow);
  Add(nil, rsCaCompare, caCompare);
  Add(nil, rsCaBrowse, caBrowse);
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
  Add(nil, rsCopyHash, caCopy);
  if FHasGitHubCli then
    Add(nil, rsOpenCommitOnGitHub, caGitHub);
  FCommitPopup.PopUp(AScreenPos.X, AScreenPos.Y);
end;

{ A new branch is asked a name for and switched to; a tag a name and a
  message, which makes it annotated (none, a lightweight one); a reset
  asks first, saying what it keeps. }
procedure TForm1.CommitMenuClick(Sender: TObject);
var
  Hash, Short, Note: string;
  Ok, Conflicts, Reopen: boolean;
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
  { Patches change nothing, so the graph stays open behind the dialog. }
  if (Sender as TMenuItem).Tag = caPatch then
  begin
    CreatePatches('', Hash);
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
    caGitHub:
      OpenOnGitHub([Hash]);
    caRebase:
      RebaseInteractiveAsk(Hash, Short, True);
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
    caMerge, caCherryPick, caRevert:
    begin
      StopWatcher;
      try
        Screen.Cursor := crHourGlass;
        Conflicts := False;
        Reopen := True;
        try
          case (Sender as TMenuItem).Tag of
            caMerge:
            begin
              Ok := FRepo.MergeRef(Hash, Conflicts);
              Note := Format(rsCaMerged, [FActionName]);
            end;
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
function TForm1.ResetTarget: string;
begin
  if FBranch <> '' then
    Result := FBranch
  else
    Result := 'HEAD';
end;

{ Asks before a reset to AHash (AShort), saying which commits leave the
  branch and what AMode keeps. From the reflog the commit may be ahead
  of HEAD, or on another line, and not only behind it. }
function TForm1.ResetAsk(const AHash, AShort: string; AMode: TGittanResetMode): boolean;
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
  Result := QuestionDlg(rsCaResetTitle, Ask, mtWarning, [mrYes, rsCaResetAction, mrCancel,
    rsCancelButton, 'IsCancel', 'IsDefault'], 0) = mrYes;
end;

{ A reset to AHash (AShort) with AMode after ResetAsk, from the commit
  menu and the reflog. True when it was done. }
function TForm1.ResetToAsk(const AHash, AShort: string; AMode: TGittanResetMode): boolean;
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
