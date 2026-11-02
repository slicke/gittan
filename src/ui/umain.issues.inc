{ ---------------------------------------------------------------------------
  Issue tracker
  ---------------------------------------------------------------------------
  References to issues in a commit's message are links in the summary's
  card. The repository names its tracker in git config with the bugtraq
  keys several clients share (gittan.issuelinks): bugtraq.url, the
  address of an issue with %BUGID% for its id, and bugtraq.logregex, how
  a message refers to one. The snapshot reads them (IssueTrackerIn) and
  ApplySnapshot hands them to the summary (UpdateIssueTracker); without
  a tracker a forge's issues are still linked as #<number>
  (DefaultIssueRegex), opened on the forge. File > Issue Tracker...
  asks for the address and the expression (one, or one for the
  references and one for the ids within them) and writes them into the
  repository's config; everything left empty takes the tracker out. }

{ The summary marks the references with the config's expression, or
  the forge's #<number> when the config names none. }
procedure TRepoFrame.UpdateIssueTracker;
var
  T: TGittanIssueTracker;
begin
  T := FIssueTracker;
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
  Url := IssueUrl(FIssueTracker, AId);
  if Url <> '' then
    OpenURL(Url)
  else if Assigned(FForge) and TryStrToInt(AId, Number) then
    OpenOnForge(IssueTarget(Number))
  else
    StatusNote(Format(rsIssueNoAddress, [AId]), True);
end;

procedure TRepoFrame.MenuIssueTrackerClick(Sender: TObject);
var
  Values: array of string;
  Lines: TStringArray;
  T: TGittanIssueTracker;
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
  if not AskInput(rsIssueTrackerTitle, rsIssueTrackerNote, [rsIssueTrackerUrl,
    rsIssueTrackerRegex, rsIssueTrackerIdRegex], Values, nil, '', True) then
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
