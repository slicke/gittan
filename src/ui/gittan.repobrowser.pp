unit gittan.repobrowser;

{** The repository browser: the tree of a commit as it was, in a native tree on the left whose
  folders are read as they are opened (TGittanRepo.TreeEntries),
  folders first, and on the right what the picked entry holds: a text
  file in a field, an image drawn to fit, else what it is (a binary
  file and its size, one too large to show, a link and its target, a
  submodule and its commit). Open writes the file to a folder of the
  temporary directory named after the commit and opens it in the
  desktop's application for it; Save As... writes it where the user
  chooses. A double click or Return on a file opens it, and a right
  click offers both and Copy Path. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Menus, ImgList,
  gittan.git;

{** Shows the tree of the commit ACommit (a full id) of ARepo in a
  dialog titled ATitle, with AHeading over the tree, the folders and
  files drawn with AImages at AFolderIcon and AFileIcon, and text in
  the font AFontName at AFontSize. }
procedure BrowseRepository(ARepo: TGittanRepo; const ACommit, ATitle, AHeading: string;
  AImages: TCustomImageList; AFolderIcon, AFileIcon: integer; const AFontName: string;
  AFontSize: integer);

implementation

uses
  LCLIntf, LCLType, Dialogs, Clipbrd, Graphics, LazUTF8, LConvEncoding, BGRABitmap,
  gittan.imagediff;

resourcestring
  rsOpenButton = 'Open';
  rsSaveButton = 'Save As...';
  rsCloseButton = 'Close';
  rsCopyPath = 'Copy Path';
  rsPickFile = 'Pick a file to see what it held.';
  rsFolder = 'Folder';
  rsSubmodule = 'A submodule, at commit %s.';
  rsLink = 'A link to %s';
  rsBinary = 'A binary file of %s.';
  rsTooLarge = 'Too large to show here (%s). Open or save it to see it.';
  rsNoImage = 'An image that cannot be shown here (%s).';
  rsReadFailed = 'Could not read %s: %s';
  rsWriteFailed = 'Could not write %s: %s';
  rsListFailed = 'Could not list %s: %s';
  rsRootName = 'the root folder';

const
  DialogWidth = 920;
  DialogHeight = 620;
  TreeWidth = 300;
  Margin = 12;
  { The largest file shown in the field or as an image; bigger ones are
    left to Open. }
  PreviewMax = 2 * 1024 * 1024;

type

  { TBrowserForm }

  TBrowserForm = class(TForm)
  private
    FRepo: TGittanRepo;
    FCommit: string;
    FEntries: TGittanTreeEntries;
    FLoaded: array of boolean;
    FFileIcon, FFolderIcon: integer;
    FHeading, FPathLabel, FNote: TLabel;
    FTree: TTreeView;
    FMemo: TMemo;
    FImage: TImage;
    FOpenButton, FSaveButton: TButton;
    FMenu: TPopupMenu;
    FOpenItem, FSaveItem: TMenuItem;
    FSaveDialog: TSaveDialog;
    function EntryOf(ANode: TTreeNode): integer;
    function Current: integer;
    function CanOpen(AEntry: integer): boolean;
    function AddEntry(const AEntry: TGittanTreeEntry): integer;
    procedure Fill(AParent: TTreeNode; const AFolder: string);
    procedure ShowEntry(AEntry: integer);
    procedure ShowNote(const AText: string);
    function ReadBlob(AEntry: integer; out AData: RawByteString): boolean;
    procedure OpenEntry(AEntry: integer);
    procedure SaveEntry(AEntry: integer);
    procedure TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: boolean);
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure TreeDblClick(Sender: TObject);
    procedure TreeKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure MenuPopup(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure CopyPathClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TBrowserForm.Create(AOwner: TComponent);
var
  Row, Right: TPanel;
  Split: TSplitter;
  CloseButton: TButton;
  Item: TMenuItem;
begin
  inherited CreateNew(AOwner);
  BorderStyle := bsSizeable;
  Position := poMainFormCenter;
  Width := Scale96ToScreen(DialogWidth);
  Height := Scale96ToScreen(DialogHeight);
  Constraints.MinWidth := Scale96ToScreen(560);
  Constraints.MinHeight := Scale96ToScreen(360);

  FHeading := TLabel.Create(Self);
  FHeading.ShowAccelChar := False;
  FHeading.Align := alTop;
  FHeading.BorderSpacing.Around := Scale96ToScreen(Margin);
  FHeading.Parent := Self;

  { Open and Save As... on the left, CloseButton on the right. }
  Row := TPanel.Create(Self);
  Row.BevelOuter := bvNone;
  Row.AutoSize := True;
  Row.Align := alBottom;
  Row.BorderSpacing.Around := Scale96ToScreen(Margin);
  Row.Parent := Self;
  FOpenButton := TButton.Create(Self);
  FOpenButton.Caption := rsOpenButton;
  FOpenButton.AutoSize := True;
  FOpenButton.Constraints.MinWidth := Scale96ToScreen(84);
  FOpenButton.Align := alLeft;
  FOpenButton.OnClick := @OpenClick;
  FOpenButton.Parent := Row;
  FSaveButton := TButton.Create(Self);
  FSaveButton.Caption := rsSaveButton;
  FSaveButton.AutoSize := True;
  FSaveButton.Constraints.MinWidth := Scale96ToScreen(84);
  FSaveButton.Align := alLeft;
  FSaveButton.Left := 1000;
  FSaveButton.BorderSpacing.Left := Scale96ToScreen(8);
  FSaveButton.OnClick := @SaveClick;
  FSaveButton.Parent := Row;
  CloseButton := TButton.Create(Self);
  CloseButton.Caption := rsCloseButton;
  CloseButton.ModalResult := mrClose;
  CloseButton.Cancel := True;
  CloseButton.AutoSize := True;
  CloseButton.Constraints.MinWidth := Scale96ToScreen(84);
  CloseButton.Align := alRight;
  CloseButton.Parent := Row;

  FTree := TTreeView.Create(Self);
  FTree.Align := alLeft;
  FTree.Width := Scale96ToScreen(TreeWidth);
  FTree.BorderSpacing.Left := Scale96ToScreen(Margin);
  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.RightClickSelect := True;
  FTree.Options := FTree.Options + [tvoRightClickSelect, tvoReadOnly] - [tvoThemedDraw];
  FTree.OnExpanding := @TreeExpanding;
  FTree.OnChange := @TreeChange;
  FTree.OnDblClick := @TreeDblClick;
  FTree.OnKeyDown := @TreeKeyDown;
  FTree.Parent := Self;

  Split := TSplitter.Create(Self);
  Split.Align := alLeft;
  Split.Left := FTree.Left + FTree.Width + 1;
  Split.Width := Scale96ToScreen(8);
  Split.Parent := Self;

  { The entry's path over what it holds. }
  Right := TPanel.Create(Self);
  Right.BevelOuter := bvNone;
  Right.Align := alClient;
  Right.BorderSpacing.Right := Scale96ToScreen(Margin);
  Right.Parent := Self;
  FPathLabel := TLabel.Create(Self);
  FPathLabel.Align := alTop;
  FPathLabel.BorderSpacing.Bottom := Scale96ToScreen(6);
  FPathLabel.ShowAccelChar := False;
  FPathLabel.Parent := Right;
  FMemo := TMemo.Create(Self);
  FMemo.Align := alClient;
  FMemo.ReadOnly := True;
  FMemo.WordWrap := False;
  FMemo.ScrollBars := ssAutoBoth;
  FMemo.Visible := False;
  FMemo.Parent := Right;
  FImage := TImage.Create(Self);
  FImage.Align := alClient;
  FImage.Center := True;
  FImage.Proportional := True;
  FImage.Stretch := True;
  FImage.StretchOutEnabled := False;
  FImage.Visible := False;
  FImage.Parent := Right;
  FNote := TLabel.Create(Self);
  FNote.Align := alClient;
  FNote.WordWrap := True;
  FNote.ShowAccelChar := False;
  FNote.Parent := Right;

  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := @MenuPopup;
  FOpenItem := TMenuItem.Create(FMenu);
  FOpenItem.Caption := rsOpenButton;
  FOpenItem.OnClick := @OpenClick;
  FMenu.Items.Add(FOpenItem);
  FSaveItem := TMenuItem.Create(FMenu);
  FSaveItem.Caption := rsSaveButton;
  FSaveItem.OnClick := @SaveClick;
  FMenu.Items.Add(FSaveItem);
  FMenu.Items.Add(NewLine);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := rsCopyPath;
  Item.OnClick := @CopyPathClick;
  FMenu.Items.Add(Item);
  FTree.PopupMenu := FMenu;

  FSaveDialog := TSaveDialog.Create(Self);
  FSaveDialog.Options := FSaveDialog.Options + [ofOverwritePrompt];
end;

procedure TBrowserForm.DoShow;
begin
  inherited DoShow;
  if FTree.Items.Count > 0 then
    FTree.Selected := FTree.Items[0];
  ActiveControl := FTree;
end;

{ A node's Data is its entry's index plus one, so no entry is nil. }
function TBrowserForm.EntryOf(ANode: TTreeNode): integer;
begin
  if ANode = nil then
    Result := -1
  else
    Result := integer(PtrUInt(ANode.Data)) - 1;
end;

function TBrowserForm.Current: integer;
begin
  Result := EntryOf(FTree.Selected);
end;

{ A file, or a link, whose blob is the target. }
function TBrowserForm.CanOpen(AEntry: integer): boolean;
begin
  Result := (AEntry >= 0) and (AEntry <= High(FEntries)) and
    (FEntries[AEntry].Kind in [tkFile, tkLink]);
end;

function TBrowserForm.AddEntry(const AEntry: TGittanTreeEntry): integer;
begin
  Result := Length(FEntries);
  SetLength(FEntries, Result + 1);
  SetLength(FLoaded, Result + 1);
  FEntries[Result] := AEntry;
  FLoaded[Result] := False;
end;

{ The entries of AFolder under AParent (nil for the root), a folder
  marked as having children so it can be opened and read then. }
procedure TBrowserForm.Fill(AParent: TTreeNode; const AFolder: string);
var
  List: TGittanTreeEntries;
  Node: TTreeNode;
  i, Index: integer;
  NodeText: string;
begin
  Screen.Cursor := crHourGlass;
  try
    if not FRepo.TreeEntries(FCommit, AFolder, List) then
    begin
      if AFolder = '' then
        NodeText := rsRootName
      else
        NodeText := AFolder;
      MessageDlg(Format(rsListFailed, [NodeText, FRepo.Error]), mtError, [mbOK], 0);
      Exit;
    end;
    FTree.Items.BeginUpdate;
    try
      for i := 0 to High(List) do
      begin
        Index := AddEntry(List[i]);
        NodeText := List[i].Name;
        if List[i].Kind = tkSubmodule then
          NodeText := NodeText + ' @ ' + Copy(List[i].Id, 1, 7);
        Node := FTree.Items.AddChildObject(AParent, NodeText, Pointer(PtrUInt(Index + 1)));
        if List[i].Kind in [tkFolder, tkSubmodule] then
          Node.ImageIndex := FFolderIcon
        else
          Node.ImageIndex := FFileIcon;
        Node.SelectedIndex := Node.ImageIndex;
        Node.HasChildren := List[i].Kind = tkFolder;
      end;
    finally
      FTree.Items.EndUpdate;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TBrowserForm.TreeExpanding(Sender: TObject; Node: TTreeNode;
  var AllowExpansion: boolean);
var
  E: integer;
begin
  E := EntryOf(Node);
  if (E < 0) or FLoaded[E] then
    Exit;
  FLoaded[E] := True;
  Fill(Node, FEntries[E].Path);
  Node.HasChildren := Node.Count > 0;
  AllowExpansion := Node.Count > 0;
end;

procedure TBrowserForm.TreeChange(Sender: TObject; Node: TTreeNode);
begin
  ShowEntry(EntryOf(Node));
end;

procedure TBrowserForm.TreeDblClick(Sender: TObject);
begin
  if CanOpen(Current) then
    OpenEntry(Current);
end;

procedure TBrowserForm.TreeKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) and CanOpen(Current) then
  begin
    OpenEntry(Current);
    Key := 0;
  end;
end;

procedure TBrowserForm.ShowNote(const AText: string);
begin
  FMemo.Visible := False;
  FMemo.Clear;
  FImage.Visible := False;
  FImage.Picture.Clear;
  FNote.Caption := AText;
  FNote.Visible := True;
end;

function TBrowserForm.ReadBlob(AEntry: integer; out AData: RawByteString): boolean;
begin
  Screen.Cursor := crHourGlass;
  try
    Result := FRepo.FileBlob(FEntries[AEntry].Path, FCommit, AData);
  finally
    Screen.Cursor := crDefault;
  end;
  if not Result then
    MessageDlg(Format(rsReadFailed, [FEntries[AEntry].Path, FRepo.Error]), mtError, [mbOK], 0);
end;

{ What the entry holds on the right, as the unit's comment says. }
procedure TBrowserForm.ShowEntry(AEntry: integer);
var
  E: TGittanTreeEntry;
  Data: RawByteString;
  Shown: string;
  Stream: TStringStream;
  Bmp: TBGRABitmap;
begin
  FOpenButton.Enabled := CanOpen(AEntry);
  FSaveButton.Enabled := CanOpen(AEntry);
  if (AEntry < 0) or (AEntry > High(FEntries)) then
  begin
    FPathLabel.Caption := '';
    ShowNote(rsPickFile);
    Exit;
  end;
  E := FEntries[AEntry];
  FPathLabel.Caption := E.Path;
  if E.Size >= 0 then
    FPathLabel.Caption := FPathLabel.Caption + ' · ' + ByteSize(E.Size);
  case E.Kind of
    tkFolder:
    begin
      FPathLabel.Caption := E.Path + ' · ' + rsFolder;
      ShowNote(rsPickFile);
      Exit;
    end;
    tkSubmodule:
    begin
      ShowNote(Format(rsSubmodule, [Copy(E.Id, 1, 7)]));
      Exit;
    end;
  end;
  if E.Size > PreviewMax then
  begin
    ShowNote(Format(rsTooLarge, [ByteSize(E.Size)]));
    Exit;
  end;
  if not FRepo.FileBlob(E.Path, FCommit, Data) then
  begin
    ShowNote(Format(rsReadFailed, [E.Path, FRepo.Error]));
    Exit;
  end;
  if E.Kind = tkLink then
  begin
    ShowNote(Format(rsLink, [Data]));
    Exit;
  end;
  if IsImagePath(E.Path) then
  begin
    Stream := TStringStream.Create(Data);
    try
      try
        Bmp := TBGRABitmap.Create(Stream);
        try
          ShowNote('');
          FNote.Visible := False;
          FImage.Picture.Assign(Bmp.Bitmap);
          FImage.Visible := True;
        finally
          Bmp.Free;
        end;
      except
        ShowNote(Format(rsNoImage, [ImageFormatName(E.Path)]));
      end;
    finally
      Stream.Free;
    end;
    Exit;
  end;
  { git's own rule for a binary file: a NUL in the first 8000 bytes. }
  if Pos(#0, Copy(Data, 1, 8000)) > 0 then
  begin
    ShowNote(Format(rsBinary, [ByteSize(E.Size)]));
    Exit;
  end;
  Shown := Data;
  if FindInvalidUTF8Codepoint(PChar(Shown), Length(Shown)) >= 0 then
    Shown := CP1252ToUTF8(Shown);
  FNote.Visible := False;
  FImage.Visible := False;
  FImage.Picture.Clear;
  FMemo.Lines.Text := Shown;
  FMemo.Visible := True;
  FMemo.SelStart := 0;
end;

{ Into gittan-<short id> in the temporary directory, under its path,
  so the application names it as it was named and two commits do not
  share a copy. }
procedure TBrowserForm.OpenEntry(AEntry: integer);
var
  Data: RawByteString;
  FileName: string;
  Stream: TFileStream;
begin
  if not CanOpen(AEntry) or not ReadBlob(AEntry, Data) then
    Exit;
  FileName := IncludeTrailingPathDelimiter(GetTempDir) + 'gittan-' + Copy(FCommit, 1, 7) +
    PathDelim + SetDirSeparators(FEntries[AEntry].Path);
  try
    ForceDirectories(ExtractFileDir(FileName));
    Stream := TFileStream.Create(FileName, fmCreate);
    try
      if Length(Data) > 0 then
        Stream.WriteBuffer(Data[1], Length(Data));
    finally
      Stream.Free;
    end;
  except
    on Ex: Exception do
    begin
      MessageDlg(Format(rsWriteFailed, [FileName, Ex.Message]), mtError, [mbOK], 0);
      Exit;
    end;
  end;
  OpenDocument(FileName);
end;

procedure TBrowserForm.SaveEntry(AEntry: integer);
var
  Data: RawByteString;
  Stream: TFileStream;
begin
  if not CanOpen(AEntry) then
    Exit;
  FSaveDialog.FileName := FEntries[AEntry].Name;
  if not FSaveDialog.Execute or not ReadBlob(AEntry, Data) then
    Exit;
  try
    Stream := TFileStream.Create(FSaveDialog.FileName, fmCreate);
    try
      if Length(Data) > 0 then
        Stream.WriteBuffer(Data[1], Length(Data));
    finally
      Stream.Free;
    end;
  except
    on Ex: Exception do
      MessageDlg(Format(rsWriteFailed, [FSaveDialog.FileName, Ex.Message]), mtError, [mbOK], 0);
  end;
end;

procedure TBrowserForm.MenuPopup(Sender: TObject);
begin
  FOpenItem.Enabled := CanOpen(Current);
  FSaveItem.Enabled := CanOpen(Current);
end;

procedure TBrowserForm.OpenClick(Sender: TObject);
begin
  OpenEntry(Current);
end;

procedure TBrowserForm.SaveClick(Sender: TObject);
begin
  SaveEntry(Current);
end;

procedure TBrowserForm.CopyPathClick(Sender: TObject);
begin
  if Current >= 0 then
    Clipboard.AsText := FEntries[Current].Path;
end;

procedure BrowseRepository(ARepo: TGittanRepo; const ACommit, ATitle, AHeading: string;
  AImages: TCustomImageList; AFolderIcon, AFileIcon: integer; const AFontName: string;
  AFontSize: integer);
var
  F: TBrowserForm;
begin
  F := TBrowserForm.Create(Screen.ActiveForm);
  try
    F.Caption := ATitle;
    F.FHeading.Caption := AHeading;
    F.FHeading.Visible := AHeading <> '';
    F.FRepo := ARepo;
    F.FCommit := ACommit;
    F.FTree.Images := AImages;
    F.FFolderIcon := AFolderIcon;
    F.FFileIcon := AFileIcon;
    if AFontName <> '' then
      F.FMemo.Font.Name := AFontName;
    if AFontSize > 0 then
      F.FMemo.Font.Size := AFontSize;
    F.Fill(nil, '');
    F.ShowEntry(-1);
    F.ShowModal;
  finally
    F.Free;
  end;
end;

end.
