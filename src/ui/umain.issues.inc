{ ---------------------------------------------------------------------------
  Issue tracker
  ---------------------------------------------------------------------------
  References to issues in a commit's message are links in the summary's
  card. The repository names its tracker in git config with the bugtraq
  keys several clients share (gittan.issuelinks): bugtraq.url, the
  address of an issue with %BUGID% for its id, and bugtraq.logregex, how
  a message refers to one. The snapshot reads them (IssueTrackerIn) and
  ApplySnapshot hands them to the summary (UpdateIssueTracker), or,
  when the config names none, the [issues] of .gittan/repo.toml
  (EffectiveIssueTracker); without
  a tracker a forge's issues are still linked as #<number>
  (DefaultIssueRegex), opened on the forge. Repository > Issue Tracker...
  asks for the address and the expression (one, or one for the
  references and one for the ids within them) and writes them into the
  repository's config; everything left empty takes the tracker out. }

{ The summary marks the references with the config's expression, or
  the forge's #<number> when the config names none. }
{ The tracker git config names, else the one .gittan/repo.toml does. }
function TRepoFrame.EffectiveIssueTracker: TGittanIssueTracker;
begin
  Result := FIssueTracker;
  if IssueTrackerEmpty(Result) and not IssueTrackerEmpty(FRepoConfig.Issues) then
    Result := FRepoConfig.Issues;
end;

procedure TRepoFrame.UpdateIssueTracker;
var
  T: TGittanIssueTracker;
begin
  T := EffectiveIssueTracker;
  if IssueTrackerEmpty(T) and Assigned(FForge) then
  begin
    T.Url := '';
    T.LogRegex := DefaultIssueRegex;
  end;
  FSummary.IssueTracker := T;
end;

{ A reference clicked: the tracker's address, else the forge's issue
  page; a number is wanted for that. }
procedure TRepoFrame.SummaryIssueClick(Sender: TObject; const AId: string);
var
  Url: string;
  Number: integer;
begin
  if FRepo.Root = '' then
    Exit;
  { Without an expression the summary marks the forge's #<number>,
    which bugtraq.url alone is no address for. }
  if IssueTrackerEmpty(EffectiveIssueTracker) then
    Url := ''
  else
    Url := IssueUrl(EffectiveIssueTracker, AId);
  if Url <> '' then
    OpenURL(Url)
  else if Assigned(FForge) and TryStrToInt(AId, Number) then
    OpenOnForge(IssueTarget(Number))
  else
    StatusNote(Format(rsIssueNoAddress, [AId]), True);
end;

{ An expression for the ids alone would be dropped, and one TRegExpr
  cannot read would mark nothing, so both are said in the dialog. }
function TRepoFrame.CheckIssueTracker(const AValues: array of string): string;
var
  i: integer;
begin
  Result := '';
  if (Trim(AValues[1]) = '') and (Trim(AValues[2]) <> '') then
    Exit(rsIssueNeedsRegex);
  for i := 1 to 2 do
    if IssueRegexError(Trim(AValues[i])) <> '' then
      Exit(Format(rsIssueBadRegex, [IssueRegexError(Trim(AValues[i]))]));
end;

procedure TRepoFrame.MenuIssueTrackerClick(Sender: TObject);
var
  Values: array of string;
  Lines: TStringArray;
  T: TGittanIssueTracker;
  Note: string;
begin
  if FRepo.Root = '' then
    Exit;
  SetLength(Values, 3);
  Values[0] := FIssueTracker.Url;
  Values[1] := '';
  Values[2] := '';
  Lines := Trim(AdjustLineBreaks(FIssueTracker.LogRegex, tlbsLF)).Split([#10]);
  if Length(Lines) > 0 then
    Values[1] := Trim(Lines[0]);
  if Length(Lines) > 1 then
    Values[2] := Trim(Lines[1]);
  { The tracker repo.toml names stays when these are emptied: the note
    says so, rather than the fields' promise to take it out. }
  Note := rsIssueTrackerNote;
  if not IssueTrackerEmpty(FRepoConfig.Issues) then
    if FRepoConfig.Issues.Url <> '' then
      Note := Note + Format(rsIssueTrackerRepoNote, [FRepoConfig.Issues.Url])
    else
      Note := Note + Format(rsIssueTrackerRepoNote,
        [Trim(AdjustLineBreaks(FRepoConfig.Issues.LogRegex, tlbsLF)).Split([#10])[0]]);
  if not AskInput(rsIssueTrackerTitle, Note, [rsIssueTrackerUrl,
    rsIssueTrackerRegex, rsIssueTrackerIdRegex], Values, @CheckIssueTracker, '', True) then
    Exit;
  T.Url := Trim(Values[0]);
  T.LogRegex := Trim(Values[1]);
  if (T.LogRegex <> '') and (Trim(Values[2]) <> '') then
    T.LogRegex := T.LogRegex + #10 + Trim(Values[2]);
  if FRepo.SetIssueTracker(T) then
  begin
    FIssueTracker := T;
    UpdateIssueTracker;
    StatusNote(rsIssueTrackerSaved);
    RefreshRepository;
  end
  else
    BannerError(rsIssueTrackerFailed, FRepo.Error);
end;
