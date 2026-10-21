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
  { The rows of the list that are no tag, in FTagRows. }
  TagRowHeader = -1;
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

function TForm1.TagBusy: boolean;
begin
  Result := (FRepo.Root = '') or (FCommitJob <> nil) or (FRemoteJob <> nil) or
    (FOperation <> '');
end;

procedure TForm1.ShowTagList(const AScreenRect: TRect);
var
  i: integer;
  Head, Detail, Subject: string;

  procedure AddRow(ARow: integer);
  begin
    SetLength(FTagRows, Length(FTagRows) + 1);
    FTagRows[High(FTagRows)] := ARow;
  end;

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
  FTagRows := nil;
  if Head <> '' then
  begin
    FTagPopup.Add(rsTagNewRow);
    AddRow(TagRowNew);
  end;
  if Length(FTags) = 0 then
    FTagPopup.AddHeader(rsNoTags)
  else
    FTagPopup.AddHeader(rsTags);
  AddRow(TagRowHeader);
  for i := 0 to High(FTags) do
  begin
    Subject := FTags[i].Subject;
    if Length(Subject) > 50 then
      Subject := UTF8Copy(Subject, 1, 47) + '...';
    Detail := Copy(FTags[i].Commit, 1, 7) + ' · ' +
      BlameAge(FTags[i].Time, DateTimeToUnix(Now, False));
    if Subject <> '' then
      Detail := Detail + ' · ' + Subject;
    FTagPopup.Add(FTags[i].Name, Detail, FTags[i].Commit = Head);
    AddRow(i);
  end;
  FTagPopup.Popup(AScreenRect);
end;

procedure TForm1.TagPopupPick(Sender: TObject; AIndex: integer);
begin
  if (AIndex < 0) or (AIndex > High(FTagRows)) then
    Exit;
  case FTagRows[AIndex] of
    TagRowHeader: ;
    TagRowNew: NewTagAsk;
    else
      if FTagRows[AIndex] <= High(FTags) then
        ShowBlameCommit(FTags[FTagRows[AIndex]].Commit);
  end;
end;

procedure TForm1.TagContext(Sender: TObject; AIndex: integer; const AScreenPos: TPoint);
var
  Busy: boolean;
  Remote: string;

  procedure Add(const ACaption: string; ATag: integer; AEnabled: boolean);
  var
    Item: TMenuItem;
  begin
    Item := TMenuItem.Create(FTagMenu);
    Item.Caption := ACaption;
    Item.Tag := ATag;
    Item.Enabled := AEnabled;
    Item.OnClick := @TagMenuClick;
    FTagMenu.Items.Add(Item);
  end;

begin
  if (AIndex < 0) or (AIndex > High(FTagRows)) or (FTagRows[AIndex] < 0) or
    (FTagRows[AIndex] > High(FTags)) then
    Exit;
  FMenuTag := FTags[FTagRows[AIndex]];
  Busy := TagBusy;
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

procedure TForm1.TagMenuClick(Sender: TObject);
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
procedure TForm1.NewTagAsk;
var
  Values: array of string;
  Short: string;
begin
  if FRepo.Root = '' then
    Exit;
  Short := Copy(FRepo.CommitId('HEAD'), 1, 7);
  if Short = '' then
    Exit;
  SetLength(Values, 2);
  Values[0] := '';
  Values[1] := '';
  if not InputQuery(rsCaTagTitle, [Format(rsCaTagPrompt, [Short]), rsCaTagMessage], Values) or
    (Trim(Values[0]) = '') then
    Exit;
  if FRepo.CreateTag(Trim(Values[0]), 'HEAD', Trim(Values[1])) then
  begin
    RefreshRepository;
    StatusNote(Format(rsCaTagged, [Short, Trim(Values[0])]));
  end
  else
    BannerError(rsCaFailed, FRepo.Error);
end;

{ A tag is no branch: checking one out leaves HEAD detached, where a
  commit belongs to no branch, so the question offers a branch at the
  tag too. }
procedure TForm1.CheckoutTagAsk(const ATag: TGittanTag);
begin
  if TagBusy then
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
procedure TForm1.BranchAtAsk(const ALabel, ACommit: string);
var
  Values: array of string;
begin
  if (FRepo.Root = '') or (FOperation <> '') then
    Exit;
  SetLength(Values, 1);
  Values[0] := '';
  if not InputQuery(rsCaBranchTitle, [Format(rsCaBranchPrompt, [ALabel])], Values) or
    (Trim(Values[0]) = '') then
    Exit;
  StopWatcher;
  if FRepo.CreateBranch(Trim(Values[0]), ACommit, True) then
  begin
    FSummary.Notice := '';
    RefreshRepository;
    StatusNote(Format(rsCaBranched, [Trim(Values[0])]));
  end
  else
    BannerError(rsCaFailed, FRepo.Error);
  StartWatcher;
end;

procedure TForm1.DeleteTagAsk(const ATag: TGittanTag);
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

procedure TForm1.MenuTagsClick(Sender: TObject);
begin
  if FRepo.Root <> '' then
    ShowTagList(FStatus.PartScreenRect(spBranch));
end;

procedure TForm1.MenuNewTagClick(Sender: TObject);
begin
  NewTagAsk;
end;

procedure TForm1.MenuPushTagsClick(Sender: TObject);
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
