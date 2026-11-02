{ ---------------------------------------------------------------------------
  Git flow
  ---------------------------------------------------------------------------
  Branch > Git Flow (gittan.gitflow does the git): while the repository
  has no git flow, Set Up Git Flow... alone, which asks the production
  and development branches, the prefixes and the version tag prefix.
  Then Start Feature..., Start Release... and Start Hotfix..., which
  ask a name (a release or a hotfix the version after the newest
  version tag) and make the branch from its base, switched to; a
  Finish item per branch of git flow, the current branch's first,
  which merges it where it goes, tags a release or a hotfix (with the
  message asked, a plain tag when it is left empty) and deletes it;
  and Git Flow Settings... to change the setup. A right click on a
  branch of git flow in the branch list offers its Finish too.
  The menu is filled as the Branch menu opens (FillFlowMenu), so the
  palette lists its items. Nothing is offered that moves HEAD while git
  is in the middle of something or a job runs. A finish that stops with
  conflicts leaves them to the Commit section; its Finish item, still
  there with the branch, goes on from where it stopped. }

const
  { The tags of the Git Flow menu's items; a Finish item's tag is
    FlowFinishTag plus the index of its branch in FFlowBranches. }
  FlowSetupTag = -1;
  FlowFinishTag = 100;

function FlowKindWord(AKind: TGittanFlowKind): string;
begin
  case AKind of
    fkFeature: Result := rsFlowFeature;
    fkRelease: Result := rsFlowRelease;
    else
      Result := rsFlowHotfix;
  end;
end;

{ A name in a caption, its ampersands doubled. }
function FlowAmp(const AName: string): string;
begin
  Result := StringReplace(AName, '&', '&&', [rfReplaceAll]);
end;

procedure TRepoFrame.FillFlowMenu;
var
  Has, Ready: boolean;
  Kind: TGittanFlowKind;
  i, n: integer;

  procedure AddFinish(AIndex: integer);
  begin
    with FFlowBranches[AIndex] do
      AddMenuItem(FFlowMenu, Format(rsFlowFinishItem, [FlowKindWord(Kind), FlowAmp(Name)]),
        FlowFinishTag + AIndex, Ready, @FlowMenuClick);
  end;

begin
  if FFlowMenu = nil then
    Exit;
  FFlowMenu.Clear;
  Has := (FRepo <> nil) and (FRepo.Root <> '');
  Ready := Has and RepoReady;
  if Has then
    FFlow := ReadFlow(FRepo.Root)
  else
    FFlow := DefaultFlow('');
  FFlowBranches := nil;
  if not FFlow.Initialized then
  begin
    AddMenuItem(FFlowMenu, rsFlowSetupItem, FlowSetupTag, Has and (FOperation = ''),
      @FlowMenuClick);
    Exit;
  end;
  FFlowBranches := ListFlowBranches(FRepo.Root, FFlow);
  for Kind := Low(Kind) to High(Kind) do
    AddMenuItem(FFlowMenu, Format(rsFlowStartItem, [FlowKindWord(Kind)]), Ord(Kind), Ready,
      @FlowMenuClick);
  if Length(FFlowBranches) > 0 then
  begin
    FFlowMenu.Add(NewLine);
    n := 0;
    for i := 0 to High(FFlowBranches) do
      if FFlowBranches[i].Branch = FBranch then
      begin
        AddFinish(i);
        Inc(n);
      end;
    for i := 0 to High(FFlowBranches) do
      if (FFlowBranches[i].Branch <> FBranch) and (n < 20) then
      begin
        AddFinish(i);
        Inc(n);
      end;
  end;
  FFlowMenu.Add(NewLine);
  AddMenuItem(FFlowMenu, rsFlowSettingsItem, FlowSetupTag, Has and (FOperation = ''),
    @FlowMenuClick);
end;

procedure TRepoFrame.FlowMenuClick(Sender: TObject);
var
  ItemTag: integer;
begin
  if FRepo.Root = '' then
    Exit;
  ItemTag := (Sender as TMenuItem).Tag;
  if ItemTag = FlowSetupTag then
    FlowSetupAsk
  else if ItemTag >= FlowFinishTag then
  begin
    if ItemTag - FlowFinishTag <= High(FFlowBranches) then
      FlowFinishAsk(FFlowBranches[ItemTag - FlowFinishTag]);
  end
  else if ItemTag in [Ord(Low(TGittanFlowKind))..Ord(High(TGittanFlowKind))] then
    FlowStartAsk(TGittanFlowKind(ItemTag));
end;

{ The setup's fields: the production branch, the development branch,
  the three prefixes and the version tag prefix. }
function TRepoFrame.CheckFlowSetup(const AValues: array of string): string;
var
  Master, Develop: string;
  i: integer;
begin
  Result := '';
  Master := Trim(AValues[0]);
  Develop := Trim(AValues[1]);
  if not FRepo.IsBranchName(Master) or not FRepo.IsBranchName(Develop) then
    Exit(rsAskBadBranch);
  if Master = Develop then
    Exit(rsFlowSameBranch);
  if not FlowBranchAvailable(FRepo.Root, Master) then
    Exit(Format(rsFlowNoBranch, [Master]));
  for i := 2 to 4 do
    if (Trim(AValues[i]) = '') or not FRepo.IsBranchName(Trim(AValues[i]) + 'x') then
      Exit(rsFlowBadPrefix);
  if (Trim(AValues[5]) <> '') and not FRepo.IsTagName(Trim(AValues[5]) + '1') then
    Exit(rsFlowBadTagPrefix);
end;

procedure TRepoFrame.FlowSetupAsk;
var
  Values: array of string;
  Flow: TGittanFlow;
  Err: string;
  Ok: boolean;
begin
  if (FRepo.Root = '') or (FOperation <> '') then
    Exit;
  Flow := ReadFlow(FRepo.Root);
  if Flow.Master = '' then
    Flow.Master := SuggestFlowMaster(FRepo.Root);
  if Flow.Develop = '' then
    Flow.Develop := 'develop';
  SetLength(Values, 6);
  Values[0] := Flow.Master;
  Values[1] := Flow.Develop;
  Values[2] := Flow.Prefix[fkFeature];
  Values[3] := Flow.Prefix[fkRelease];
  Values[4] := Flow.Prefix[fkHotfix];
  Values[5] := Flow.VersionTag;
  if not AskInput(rsFlowSetupTitle, rsFlowSetupNote, [rsFlowMasterPrompt, rsFlowDevelopPrompt,
    rsFlowFeaturePrompt, rsFlowReleasePrompt, rsFlowHotfixPrompt, rsFlowTagPrompt], Values,
    @CheckFlowSetup, rsFlowSetupAction) then
    Exit;
  Flow.Master := Trim(Values[0]);
  Flow.Develop := Trim(Values[1]);
  Flow.Prefix[fkFeature] := Trim(Values[2]);
  Flow.Prefix[fkRelease] := Trim(Values[3]);
  Flow.Prefix[fkHotfix] := Trim(Values[4]);
  Flow.VersionTag := Trim(Values[5]);
  StopWatcher;
  try
    Ok := InitFlow(FRepo.Root, Flow, Err);
    RefreshRepository;
  finally
    StartWatcher;
  end;
  if Ok then
    StatusNote(Format(rsFlowSetUp, [Flow.Master, Flow.Develop]))
  else
    BannerError(rsFlowSetupFailed, Err);
end;

function TRepoFrame.CheckFlowStart(const AValues: array of string): string;
var
  FlowName: string;
begin
  FlowName := Trim(AValues[0]);
  Result := BranchNameProblem(FFlow.Prefix[FFlowAskKind] + FlowName);
  if (Result = '') and (FFlowAskKind <> fkFeature) and
    FRepo.HasCommit('refs/tags/' + FlowTag(FFlow, FlowName)) then
    Result := Format(rsFlowTagTaken, [FlowTag(FFlow, FlowName)]);
end;

{ One release and one hotfix at a time, as the git-flow command has it:
  a second is refused while the first is under way. }
procedure TRepoFrame.FlowStartAsk(AKind: TGittanFlowKind);
var
  Value, Err, Base, Note: string;
  Branch: TGittanFlowBranch;
  Ok: boolean;
begin
  if not RepoReady then
    Exit;
  FFlow := ReadFlow(FRepo.Root);
  if not FFlow.Initialized then
    Exit;
  if AKind <> fkFeature then
    for Branch in ListFlowBranches(FRepo.Root, FFlow) do
      if Branch.Kind = AKind then
      begin
        StatusNote(Format(rsFlowUnderWay, [Branch.Branch]), True);
        Exit;
      end;
  Base := FlowBase(FFlow, AKind);
  Value := '';
  if AKind <> fkFeature then
    Value := NextFlowVersion(LatestFlowVersion(FRepo.Root, FFlow), AKind = fkHotfix);
  if AKind = fkFeature then
    Note := ''
  else if FFlow.VersionTag = '' then
    Note := rsFlowStartTagNote
  else
    Note := Format(rsFlowStartTagNotePrefix, [FFlow.VersionTag]);
  FFlowAskKind := AKind;
  if not AskText(Format(rsFlowStartTitle, [FlowKindWord(AKind)]), Format(rsFlowStartPrompt,
    [FFlow.Prefix[AKind], Base]), Value, @CheckFlowStart, rsFlowStartAction, Note) or
    (Trim(Value) = '') then
    Exit;
  Value := Trim(Value);
  StopWatcher;
  try
    Ok := StartFlowBranch(FRepo.Root, FFlow, AKind, Value, Err);
    FSummary.Notice := '';
    RefreshRepository;
  finally
    StartWatcher;
  end;
  if Ok then
    StatusNote(Format(rsFlowStarted, [FFlow.Prefix[AKind] + Value, Base]))
  else
    BannerError(rsFlowStartFailed, Err);
end;

{ What finishing does, in words: where the branch is merged and the tag
  it gets. }
function FlowFinishWhat(const AFlow: TGittanFlow; const ABranch: TGittanFlowBranch;
  const ATargets: TStringArray): string;
var
  Into: string;
begin
  if Length(ATargets) > 1 then
    Into := Format(rsFlowIntoTwo, [ATargets[0], ATargets[1]])
  else
    Into := ATargets[0];
  if ABranch.Kind = fkFeature then
    Result := Format(rsFlowFinishFeature, [ABranch.Branch, Into, AFlow.Develop])
  else
    Result := Format(rsFlowFinishTagged, [ABranch.Branch, Into, AFlow.Master,
      FlowTag(AFlow, ABranch.Name), AFlow.Develop]);
end;

procedure TRepoFrame.FlowFinishAsk(const ABranch: TGittanFlowBranch);
var
  Values: array of string;
  Targets: TStringArray;
  Msg, Err, Stopped, Into: string;
  Ok, Conflicts: boolean;
begin
  if not RepoReady then
    Exit;
  FFlow := ReadFlow(FRepo.Root);
  if not FFlow.Initialized then
    Exit;
  Targets := FlowTargets(FRepo.Root, FFlow, ABranch.Kind);
  Msg := FlowFinishWhat(FFlow, ABranch, Targets);
  SetLength(Values, 1);
  Values[0] := '';
  if ABranch.Kind = fkFeature then
  begin
    if AskDlg(Format(rsFlowFinishTitle, [FlowKindWord(ABranch.Kind)]), Msg, mtConfirmation,
      [mrYes, rsFlowFinishAction, 'IsDefault', mrCancel, rsCancelButton, 'IsCancel'], 0) <> mrYes then
      Exit;
  end
  else
  begin
    Values[0] := Format(rsFlowTagMessage, [FlowKindWord(ABranch.Kind), ABranch.Name]);
    if not AskInput(Format(rsFlowFinishTitle, [FlowKindWord(ABranch.Kind)]), Msg,
      [Format(rsFlowTagMessagePrompt, [FlowTag(FFlow, ABranch.Name)])], Values, nil,
      rsFlowFinishAction, True) then
      Exit;
  end;
  StopWatcher;
  try
    Screen.Cursor := crHourGlass;
    try
      Ok := FinishFlowBranch(FRepo.Root, FFlow, ABranch.Kind, ABranch.Name, Trim(Values[0]),
        Conflicts, Stopped, Err);
    finally
      Screen.Cursor := crDefault;
    end;
    FSummary.Notice := '';
    RefreshRepository;
  finally
    StartWatcher;
  end;
  if Length(Targets) > 1 then
    Into := Format(rsFlowIntoTwo, [Targets[0], Targets[1]])
  else
    Into := Targets[0];
  if Ok and (ABranch.Kind = fkFeature) then
    BannerSuccess(Format(rsFlowFinished, [ABranch.Branch, Into]), '')
  else if Ok then
    BannerSuccess(Format(rsFlowFinishedTagged, [ABranch.Branch, Into, FlowTag(FFlow,
      ABranch.Name)]), Format(rsFlowPushNote, [Into, FlowTag(FFlow, ABranch.Name)]))
  else if Conflicts then
    StatusNote(Format(rsFlowConflicts, [ABranch.Branch, Stopped]) + LineEnding +
      Format(rsFlowConflictsDetail, [ABranch.Branch]), True)
  else
    BannerError(Format(rsFlowFinishFailed, [ABranch.Branch]), Err);
end;

{ The branch of git flow ABranch is, for the branch list's menu; False
  when it is none. }
function TRepoFrame.FlowBranchOf(const ABranch: string; out AFlowBranch: TGittanFlowBranch): boolean;
var
  Kind: TGittanFlowKind;
  FlowName: string;
begin
  AFlowBranch := Default(TGittanFlowBranch);
  FFlow := ReadFlow(FRepo.Root);
  Result := FlowKindOf(FFlow, ABranch, Kind, FlowName);
  if Result then
  begin
    AFlowBranch.Kind := Kind;
    AFlowBranch.Name := FlowName;
    AFlowBranch.Branch := ABranch;
  end;
end;

function TRepoFrame.FlowFinishCaption(const ABranch: TGittanFlowBranch): string;
begin
  Result := Format(rsFlowFinishItem, [FlowKindWord(ABranch.Kind), FlowAmp(ABranch.Name)]);
end;
