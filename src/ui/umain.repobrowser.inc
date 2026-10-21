{ ---------------------------------------------------------------------------
  The repository browser
  ---------------------------------------------------------------------------
  Browse Files... in the commit menu, the tag menu and the reflog's
  menu shows the tree of that commit as it was (gittan.repobrowser),
  where a file can be looked at, opened in its application or saved.
  It changes nothing, so the commit graph stays open behind it. }

procedure TForm1.BrowseCommit(const AHash, AName, ASubject: string);
var
  Heading, Subject: string;
begin
  if (FRepo.Root = '') or (AHash = '') then
    Exit;
  { A subject on one line, cut as the reflog cuts its own. }
  Subject := ASubject;
  if UTF8Length(Subject) > 100 then
    Subject := UTF8Copy(Subject, 1, 97) + '...';
  Heading := Copy(AHash, 1, 7);
  if Subject <> '' then
    Heading := Heading + ' · ' + Subject;
  BrowseRepository(FRepo, AHash, Format(rsBrowseTitle, [AName]), Heading, TreeImages,
    iconFolder, iconFile, Edit.Font.Name, Edit.Font.Size);
end;
