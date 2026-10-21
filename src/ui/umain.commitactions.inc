{ ---------------------------------------------------------------------------
  The commit menu
  ---------------------------------------------------------------------------
  A right click on a commit in the commit graph (or the Menu key) shows
  what can be done with it, as the log of TortoiseGit does: show it,
  compare the work tree with it, switch to a branch on it, make a branch
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
  views show what changed between them going forward. }
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

procedure TForm1.GraphContext(Sender: TObject; const ACommit: TGittanGraphCommit;
  const AScreenPos: TPoint);
var
  Busy, InHead, IsHead, IsMerge: boolean;
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
  Busy := (FOperation <> '') or (FCommitJob <> nil) or (FRemoteJob <> nil);
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
  if FMarkHash = ACommit.Hash then
    Add(nil, rsCaUnmark, caMark)
  else
    Add(nil, rsCaMark, caMark);
  if (FMarkHash <> '') and (FMarkHash <> ACommit.Hash) then
    Add(nil, Format(rsCaCompareMarked, [Amp(FMarkName)]), caCompareMarked);
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
  Values: array of string;
  Ok, Conflicts, Reopen: boolean;
  Mode: TGittanResetMode;
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
    caBranch, caTag, caMerge, caCherryPick, caRevert, caResetSoft, caResetMixed, caResetHard:
    begin
      Values := nil;
      Mode := rmMixed;
      case (Sender as TMenuItem).Tag of
        caBranch:
        begin
          SetLength(Values, 1);
          Values[0] := '';
          if not InputQuery(rsCaBranchTitle, [Format(rsCaBranchPrompt, [Short])], Values) or
            (Trim(Values[0]) = '') then
            Exit;
        end;
        caTag:
        begin
          SetLength(Values, 2);
          Values[0] := '';
          Values[1] := '';
          if not InputQuery(rsCaTagTitle, [Format(rsCaTagPrompt, [Short]), rsCaTagMessage],
            Values) or (Trim(Values[0]) = '') then
            Exit;
        end;
        caResetSoft, caResetMixed, caResetHard:
        begin
          case (Sender as TMenuItem).Tag of
            caResetSoft: Mode := rmSoft;
            caResetHard: Mode := rmHard;
          end;
          if not ResetAsk(Hash, Short, Mode) then
            Exit;
        end;
      end;
      StopWatcher;
      Screen.Cursor := crHourGlass;
      Conflicts := False;
      Reopen := True;
      try
        case (Sender as TMenuItem).Tag of
          caBranch:
          begin
            Ok := FRepo.CreateBranch(Trim(Values[0]), Hash, True);
            Note := Format(rsCaBranched, [Trim(Values[0])]);
          end;
          caTag:
          begin
            Ok := FRepo.CreateTag(Trim(Values[0]), Hash, Trim(Values[1]));
            Note := Format(rsCaTagged, [Short, Trim(Values[0])]);
          end;
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
          caRevert:
          begin
            Ok := FRepo.RevertCommit(Hash, Conflicts);
            Note := Format(rsCaReverted, [Short]);
          end;
          else
          begin
            Ok := FRepo.Reset(Hash, Mode);
            Note := Format(rsCaWasReset, [ResetTarget, Short]);
          end;
        end;
      finally
        Screen.Cursor := crDefault;
      end;
      FLoadError := '';
      FSummary.Notice := '';
      RefreshRepository;
      StartWatcher;
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
