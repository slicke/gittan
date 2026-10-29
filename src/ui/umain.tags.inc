{ ---------------------------------------------------------------------------
  Tags
  ---------------------------------------------------------------------------
  The Branch menu's Tags... drops the tag list from the status bar's
  branch (ShowTagList): New Tag at HEAD... first, then the tags, newest
  first, each with its commit's short id, its age and the subject of
  its message (or of the commit's, for a lightweight tag), the ones on
  HEAD checked. A pick shows the tag's commit against its parent, as a
  pick in the commit graph does, and a right click (or the Menu key)
  offers what can be done with it: show it, compare the work tree with
  it, check it out (HEAD is detached then, which the question says,
  offering a branch at it instead), make a branch at it, push it, and
  delete it here or on the remote. Push All Tags pushes every tag. The
  remote is the one a push of the current branch goes to (PushRemote);
  pushing and deleting there run as remote jobs. The tags are read when
  the list opens, not with every snapshot. }
const
  { The tag of the list's New row; a tag's row has its index. }
  TagRowNew = -2;
  tmShow = 1;
  tmCompare = 2;
  tmCheckout = 3;
  tmBranch = 4;
  tmPush = 5;
  tmCopy = 6;
  tmDelete = 7;
  tmDeleteRemote = 8;
  tmBrowse = 9;

procedure TRepoFrame.ShowTagList(const AScreenRect: TRect);
var
  i: integer;
  Head, Detail, Subject: string;
begin
  if FRepo.Root = '' then
    Exit;
  if not FRepo.Tags(FTags) then
  begin
    BannerError(rsCaFailed, FRepo.Error);
    Exit;
  end;
  FTagRemote := FRepo.PushRemote;
  Head := FRepo.CommitId('HEAD');
  FTagPopup.Clear;
  if Head <> '' then
    FTagPopup.Add(rsTagNewRow, '', False, TagRowNew);
  if Length(FTags) = 0 then
    FTagPopup.AddHeader(rsNoTags)
  else
    FTagPopup.AddHeader(rsTags);
  for i := 0 to High(FTags) do
  begin
    Subject := FTags[i].Subject;
    if Length(Subject) > 50 then
      Subject := UTF8Copy(Subject, 1, 47) + '...';
    Detail := Copy(FTags[i].Commit, 1, 7) + ' · ' +
      BlameAge(FTags[i].Time, DateTimeToUnix(Now, False));
    if Subject <> '' then
      Detail := Detail + ' · ' + Subject;
    FTagPopup.Add(FTags[i].Name, Detail, FTags[i].Commit = Head, i);
  end;
  FTagPopup.Popup(AScreenRect);
end;

procedure TRepoFrame.TagPopupPick(Sender: TObject; AIndex: integer);
var
  Row: PtrInt;
begin
  Row := FTagPopup.TagOf(AIndex);
  if Row = TagRowNew then
    NewTagAsk
  else if (Row >= 0) and (Row <= High(FTags)) then
    ShowBlameCommit(FTags[Row].Commit);
end;

procedure TRepoFrame.TagContext(Sender: TObject; AIndex: integer; const AScreenPos: TPoint);
var
  Busy: boolean;
  Remote: string;
  Row: PtrInt;

  procedure Add(const ACaption: string; ATag: integer; AEnabled: boolean);
  begin
    AddMenuItem(FTagMenu.Items, ACaption, ATag, AEnabled, @TagMenuClick);
  end;

begin
  Row := FTagPopup.TagOf(AIndex);
  if (Row < 0) or (Row > High(FTags)) then
    Exit;
  FMenuTag := FTags[Row];
  Busy := not RepoReady;
  Remote := StringReplace(FTagRemote, '&', '&&', [rfReplaceAll]);
  FTagMenu.Items.Clear;
  Add(rsCaShow, tmShow, True);
  Add(rsCaCompare, tmCompare, True);
  Add(rsCaBrowse, tmBrowse, True);
  FTagMenu.Items.Add(NewLine);
  Add(rsTmCheckout, tmCheckout, not Busy);
  Add(rsCaBranch, tmBranch, FOperation = '');
  FTagMenu.Items.Add(NewLine);
  if FTagRemote <> '' then
    Add(Format(rsTmPush, [Remote]), tmPush, FRemoteJob = nil);
  Add(rsTmCopy, tmCopy, True);
  FTagMenu.Items.Add(NewLine);
  Add(rsBmDelete, tmDelete, True);
  if FTagRemote <> '' then
    Add(Format(rsTmDeleteRemote, [Remote]), tmDeleteRemote, FRemoteJob = nil);
  FTagMenu.PopUp(AScreenPos.X, AScreenPos.Y);
end;

procedure TRepoFrame.TagMenuClick(Sender: TObject);
var
  T: TGittanTag;
begin
  T := FMenuTag;
  if (FRepo.Root = '') or (T.Name = '') then
    Exit;
  FTagPopup.Close;
  case (Sender as TMenuItem).Tag of
    tmShow: ShowBlameCommit(T.Commit);
    tmCompare: SetBase('refs/tags/' + T.Name);
    tmBrowse: BrowseCommit(T.Commit, T.Name, T.Subject);
    tmCheckout: CheckoutTagAsk(T);
    tmBranch: BranchAtAsk(T.Name, T.Commit);
    tmPush: StartRemote(rkPushTag, pmAuto, T.Name, FTagRemote);
    tmCopy: Clipboard.AsText := T.Name;
    tmDelete: DeleteTagAsk(T);
    tmDeleteRemote:
      if QuestionDlg(rsBmDeleteRemoteTitle, Format(rsTagDeleteRemoteAsk,
        [T.Name, FTagRemote]), mtWarning, [mrYes, rsBmDeleteAction, mrCancel,
        rsCancelButton, 'IsCancel', 'IsDefault'], 0) = mrYes then
        StartRemote(rkDeleteRemoteTag, pmAuto, T.Name, FTagRemote);
  end;
end;

{ A name and an optional message, which makes the tag annotated, as
  Create Tag Here... in the commit graph asks. }
procedure TRepoFrame.NewTagAsk;
var
  Short: string;
begin
  if FRepo.Root = '' then
    Exit;
  Short := Copy(FRepo.CommitId('HEAD'), 1, 7);
  if Short <> '' then
    TagAtAsk(Short, 'HEAD');
end;

{ A tag at ACommit (AShort in the question) after a name and an optional
  message, which makes it annotated. True when it was made. }
function TRepoFrame.TagAtAsk(const AShort, ACommit: string): boolean;
var
  Values: array of string;
begin
  Result := False;
  SetLength(Values, 2);
  Values[0] := '';
  Values[1] := '';
  if not InputQuery(rsCaTagTitle, [Format(rsCaTagPrompt, [AShort]), rsCaTagMessage], Values) or
    (Trim(Values[0]) = '') then
    Exit;
  StopWatcher;
  try
    Result := FRepo.CreateTag(Trim(Values[0]), ACommit, Trim(Values[1]));
    if Result then
    begin
      FSummary.Notice := '';
      RefreshRepository;
      StatusNote(Format(rsCaTagged, [AShort, Trim(Values[0])]));
    end
    else
      BannerError(rsCaFailed, FRepo.Error);
  finally
    StartWatcher;
  end;
end;

{ A tag is no branch: checking one out leaves HEAD detached, where a
  commit belongs to no branch, so the question offers a branch at the
  tag too. }
procedure TRepoFrame.CheckoutTagAsk(const ATag: TGittanTag);
begin
  if not RepoReady then
    Exit;
  case QuestionDlg(rsTagCheckoutTitle, Format(rsTagCheckoutAsk, [ATag.Name]), mtConfirmation,
      [mrYes, rsTagCheckoutAction, 'IsDefault', mrNo, rsCaBranch, mrCancel, rsCancelButton,
      'IsCancel'], 0) of
    mrYes: SwitchBranch(ATag.Name, True);
    mrNo: BranchAtAsk(ATag.Name, ATag.Commit);
  end;
end;

{ A branch at ACommit, switched to, after a name; ALabel is what the
  question calls the commit (a tag, a short id). }
procedure TRepoFrame.BranchAtAsk(const ALabel, ACommit: string);
begin
  if (FRepo.Root <> '') and (FOperation = '') then
    NewBranchAsk(Format(rsCaBranchPrompt, [ALabel]), ACommit);
end;

{ Asks a name with APrompt and makes a branch of it at ACommit, switched
  to. True when it was made. }
function TRepoFrame.NewBranchAsk(const APrompt, ACommit: string): boolean;
var
  Values: array of string;
begin
  Result := False;
  SetLength(Values, 1);
  Values[0] := '';
  if not InputQuery(rsCaBranchTitle, [APrompt], Values) or (Trim(Values[0]) = '') then
    Exit;
  StopWatcher;
  try
    Result := FRepo.CreateBranch(Trim(Values[0]), ACommit, True);
    if Result then
    begin
      FSummary.Notice := '';
      RefreshRepository;
      StatusNote(Format(rsCaBranched, [Trim(Values[0])]));
    end
    else
      BannerError(rsCaFailed, FRepo.Error);
  finally
    StartWatcher;
  end;
end;

procedure TRepoFrame.DeleteTagAsk(const ATag: TGittanTag);
begin
  if QuestionDlg(rsTagDeleteTitle, Format(rsTagDeleteAsk, [ATag.Name]), mtConfirmation,
    [mrYes, rsBmDeleteAction, mrCancel, rsCancelButton, 'IsCancel', 'IsDefault'], 0) <> mrYes then
    Exit;
  if FRepo.DeleteTag(ATag.Name) then
  begin
    RefreshRepository;
    StatusNote(Format(rsTagDeleted, [ATag.Name]));
  end
  else
    BannerError(rsCaFailed, FRepo.Error);
end;

procedure TRepoFrame.MenuTagsClick(Sender: TObject);
begin
  if FRepo.Root <> '' then
    ShowTagList(MenuListAnchor);
end;

procedure TRepoFrame.MenuNewTagClick(Sender: TObject);
begin
  NewTagAsk;
end;

procedure TRepoFrame.MenuPushTagsClick(Sender: TObject);
var
  Remote: string;
begin
  if (FRepo.Root = '') or (FRemoteJob <> nil) or (FCommitJob <> nil) then
    Exit;
  Remote := FRepo.PushRemote;
  if Remote = '' then
    StatusNote(rsNoRemote, True)
  else
    StartRemote(rkPushTag, pmAuto, '', Remote);
end;
