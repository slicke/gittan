unit gittan.remotesdlg;

{** The Remotes dialog: the repository's remotes in a native list, the
  name and the URL (and the push URL after it when one is set apart),
  with Add..., Edit... and Remove... under it. Add and Edit open a
  smaller dialog with the name, the URL and the push URL (empty pushes to
  the URL), and, when adding, whether to fetch the new remote; a name
  changed there renames the remote (its remote-tracking branches and the
  upstreams that name them go with it). Remove asks first, naming the
  remote-tracking branches that go. Each change is made with git at once,
  and a refusal is said in red in the dialog it came from. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Dialogs, gittan.git;

{** Shows the remotes of ARepo to change. True when any was changed;
  AFetch then says whether one was added with its fetch asked for. }
function EditRemotes(ARepo: TGittanRepo; out AFetch: boolean): boolean;

implementation

uses
  Math, Graphics, LCLType, Clipbrd, gittan.repoinfo;

resourcestring
  rsRemotesTitle = 'Remotes';
  rsRemotesHint = 'The repositories this one fetches from and pushes to. Changing them ' +
    'changes nothing on the remotes themselves.';
  rsRemotesName = 'Name';
  rsRemotesUrl = 'URL';
  rsRemotesPushTo = '%s  (pushes to %s)';
  rsRemotesNone = 'This repository has no remotes yet.';
  rsRemotesAdd = 'Add…';
  rsRemotesEdit = 'Edit…';
  rsRemotesRemove = 'Remove…';
  rsRemotesClose = 'Close';
  rsRemoteAddTitle = 'Add Remote';
  rsRemoteEditTitle = 'Edit Remote';
  rsRemotePushUrl = 'Push URL';
  rsRemotePushHint = 'Leave empty to push to the URL.';
  rsRemoteFetch = 'Fetch from it after adding';
  rsRemoteAddButton = 'Add';
  rsRemoteSaveButton = 'Save';
  rsRemoteNoName = 'Give the remote a name.';
  rsRemoteNoUrl = 'Give the remote a URL.';
  rsRemoteTaken = 'There is already a remote named %s.';
  rsRemoveTitle = 'Remove Remote';
  rsRemoveAsk = 'Remove the remote %s?';
  rsRemoveNoBranches = 'Nothing changes on the remote itself.';
  rsRemoveOneBranch = 'Its remote-tracking branch goes with it, and a branch that tracks it ' +
    'tracks nothing then. Nothing changes on the remote itself.';
  rsRemoveBranches = 'Its %d remote-tracking branches go with it, and the branches that track ' +
    'them track nothing then. Nothing changes on the remote itself.';
  rsRemoveButton = 'Remove';
  rsCancel = 'Cancel';

const
  DialogWidth = 640;
  DialogHeight = 400;
  EditWidth = 520;
  Margin = 12;
  LabelWidth = 72;

type

  { TRemoteForm: adds a remote, or edits the one named FOld. }

  TRemoteForm = class(TForm)
  private
    FRepo: TGittanRepo;
    FNames: TStrings;
    FOld, FOldUrl, FOldPushUrl: string;
    FName, FUrl, FPushUrl: TEdit;
    FFetch: TCheckBox;
    FError: TLabel;
    FNextTop: integer;
    FChanged: boolean;
    procedure Row(const ACaption: string; AEdit: TEdit);
    procedure Place(AControl: TControl; ASpaceAbove: integer);
    procedure OkClick(Sender: TObject);
    procedure Fail(const AMessage: string);
  protected
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent; ARepo: TGittanRepo; ANames: TStrings;
      const ARemote: TGittanRemote; AAdd: boolean); reintroduce;
  end;

  { TRemotesForm }

  TRemotesForm = class(TForm)
  private
    FRepo: TGittanRepo;
    FRemotes: TGittanRemotes;
    FList: TListView;
    FEmpty, FError: TLabel;
    FEditButton, FRemoveButton: TButton;
    FChanged, FFetch: boolean;
    procedure Fill(const ASelect: string);
    procedure UpdateButtons;
    function SelectedIndex: integer;
    function Names: TStringList;
    procedure AddClick(Sender: TObject);
    procedure EditClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure ListSelectItem(Sender: TObject; Item: TListItem; Selected: boolean);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure ListResize(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

function MakeButton(AOwner: TComponent; const ACaption: string; AParent: TWinControl;
  AAlign: TAlign; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Caption := ACaption;
  Result.AutoSize := True;
  Result.Constraints.MinWidth := AParent.Scale96ToScreen(84);
  Result.Align := AAlign;
  Result.OnClick := AClick;
  Result.Parent := AParent;
end;

{ TRemoteForm }

constructor TRemoteForm.Create(AOwner: TComponent; ARepo: TGittanRepo; ANames: TStrings;
  const ARemote: TGittanRemote; AAdd: boolean);
var
  Buttons: TPanel;
  Ok, Cancel: TButton;
  Note: TLabel;
begin
  inherited CreateNew(AOwner);
  FRepo := ARepo;
  FNames := ANames;
  if AAdd then
    Caption := rsRemoteAddTitle
  else
    Caption := rsRemoteEditTitle;
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  { The height follows the content; the width stays. }
  Constraints.MinWidth := Scale96ToScreen(EditWidth);
  Constraints.MaxWidth := Scale96ToScreen(EditWidth);
  AutoSize := True;

  FName := TEdit.Create(Self);
  Row(rsRemotesName, FName);
  FName.Parent.BorderSpacing.Top := Scale96ToScreen(Margin);
  FUrl := TEdit.Create(Self);
  Row(rsRemotesUrl, FUrl);
  FPushUrl := TEdit.Create(Self);
  Row(rsRemotePushUrl, FPushUrl);
  Note := TLabel.Create(Self);
  Note.Caption := rsRemotePushHint;
  Note.Font.Color := clGrayText;
  Place(Note, 0);

  FFetch := TCheckBox.Create(Self);
  FFetch.Caption := rsRemoteFetch;
  FFetch.Checked := True;
  FFetch.Visible := AAdd;
  Place(FFetch, 10);

  FError := TLabel.Create(Self);
  FError.WordWrap := True;
  FError.Font.Color := clRed;
  FError.ShowAccelChar := False;
  FError.Visible := False;
  Place(FError, 8);

  { The button that does it on the right on macOS, Cancel on the right
    elsewhere. }
  Buttons := TPanel.Create(Self);
  Buttons.BevelOuter := bvNone;
  Buttons.AutoSize := True;
  Buttons.Align := alTop;
  Inc(FNextTop, 1000);
  Buttons.Top := FNextTop;
  Buttons.BorderSpacing.Around := Scale96ToScreen(Margin);
  Buttons.BorderSpacing.Top := Scale96ToScreen(16);
  Buttons.Parent := Self;
  if AAdd then
    Ok := MakeButton(Self, rsRemoteAddButton, Buttons, alRight, @OkClick)
  else
    Ok := MakeButton(Self, rsRemoteSaveButton, Buttons, alRight, @OkClick);
  Ok.Default := True;
  Cancel := MakeButton(Self, rsCancel, Buttons, alRight, nil);
  Cancel.ModalResult := mrCancel;
  Cancel.Cancel := True;
  {$IFDEF DARWIN}
  Cancel.Left := 0;
  Ok.Left := 1000;
  {$ELSE}
  Ok.Left := 0;
  Cancel.Left := 1000;
  {$ENDIF}
  Cancel.BorderSpacing.Left := Scale96ToScreen(8);
  Ok.BorderSpacing.Left := Scale96ToScreen(8);

  FOld := ARemote.Name;
  FOldUrl := ARemote.Url;
  FOldPushUrl := ARemote.PushUrl;
  FName.Text := ARemote.Name;
  FUrl.Text := ARemote.Url;
  if ARemote.PushUrl <> ARemote.Url then
    FPushUrl.Text := ARemote.PushUrl;
end;

{ A row under the ones before it: the caption in a column of its own,
  then AEdit filling the rest. }
procedure TRemoteForm.Row(const ACaption: string; AEdit: TEdit);
var
  Panel: TPanel;
  Lbl: TLabel;
begin
  Panel := TPanel.Create(Self);
  Panel.BevelOuter := bvNone;
  Panel.AutoSize := True;
  Panel.Align := alTop;
  Inc(FNextTop, 1000);
  Panel.Top := FNextTop;
  Panel.BorderSpacing.Left := Scale96ToScreen(Margin);
  Panel.BorderSpacing.Right := Scale96ToScreen(Margin);
  Panel.BorderSpacing.Bottom := Scale96ToScreen(6);
  Panel.Parent := Self;
  Lbl := TLabel.Create(Self);
  Lbl.Caption := ACaption;
  Lbl.AutoSize := False;
  Lbl.Width := Scale96ToScreen(LabelWidth);
  Lbl.Align := alLeft;
  Lbl.Layout := tlCenter;
  Lbl.Parent := Panel;
  AEdit.Align := alClient;
  AEdit.Parent := Panel;
end;

{ Under the rows, set in to the edits' column. }
procedure TRemoteForm.Place(AControl: TControl; ASpaceAbove: integer);
begin
  AControl.Align := alTop;
  Inc(FNextTop, 1000);
  AControl.Top := FNextTop;
  AControl.BorderSpacing.Left := Scale96ToScreen(Margin + LabelWidth);
  AControl.BorderSpacing.Right := Scale96ToScreen(Margin);
  AControl.BorderSpacing.Top := Scale96ToScreen(ASpaceAbove);
  AControl.Parent := Self;
end;

procedure TRemoteForm.DoShow;
begin
  inherited DoShow;
  if FName.Text = '' then
    ActiveControl := FName
  else
    ActiveControl := FUrl;
end;

procedure TRemoteForm.Fail(const AMessage: string);
begin
  FError.Caption := Trim(AMessage);
  FError.Visible := True;
end;

{ Adds, or renames, and then sets the URLs when they changed; the dialog
  stays open on a refusal. What went through counts as made, so trying
  again only does the rest. }
procedure TRemoteForm.OkClick(Sender: TObject);
var
  NewName, Url, PushUrl, Err: string;
  SetUrls: boolean;
begin
  NewName := Trim(FName.Text);
  Url := Trim(FUrl.Text);
  PushUrl := Trim(FPushUrl.Text);
  if PushUrl = Url then
    PushUrl := '';
  Err := '';
  if NewName = '' then
    Err := rsRemoteNoName
  else if Url = '' then
    Err := rsRemoteNoUrl
  else if (NewName <> FOld) and (FNames.IndexOf(NewName) >= 0) then
    Err := Format(rsRemoteTaken, [NewName])
  else if FOld = '' then
  begin
    if FRepo.AddRemote(NewName, Url) then
    begin
      FChanged := True;
      FOld := NewName;
      FOldUrl := Url;
      FOldPushUrl := Url;
    end
    else
      Err := FRepo.Error;
  end
  else if NewName <> FOld then
  begin
    if FRepo.RenameRemote(FOld, NewName) then
    begin
      FChanged := True;
      FOld := NewName;
    end
    else
      Err := FRepo.Error;
  end;
  if Err = '' then
  begin
    { git lists the URL as the push URL when none is set. }
    if PushUrl = '' then
      SetUrls := (Url <> FOldUrl) or (FOldPushUrl <> FOldUrl)
    else
      SetUrls := (Url <> FOldUrl) or (PushUrl <> FOldPushUrl);
    if SetUrls then
    begin
      if FRepo.SetRemoteUrls(NewName, Url, PushUrl) then
        FChanged := True
      else
        Err := FRepo.Error;
    end;
  end;
  if Err <> '' then
    Fail(Err)
  else
    ModalResult := mrOK;
end;

{ TRemotesForm }

constructor TRemotesForm.Create(AOwner: TComponent);
var
  HintLabel: TLabel;
  Bottom: TPanel;
  Col: TListColumn;
  CloseButton, AddButton: TButton;
begin
  inherited CreateNew(AOwner);
  Caption := rsRemotesTitle;
  BorderStyle := bsSizeable;
  Position := poMainFormCenter;
  Width := Scale96ToScreen(DialogWidth);
  Height := Scale96ToScreen(DialogHeight);
  Constraints.MinWidth := Scale96ToScreen(420);
  Constraints.MinHeight := Scale96ToScreen(260);

  HintLabel := TLabel.Create(Self);
  HintLabel.Caption := rsRemotesHint;
  HintLabel.WordWrap := True;
  HintLabel.Align := alTop;
  HintLabel.BorderSpacing.Around := Scale96ToScreen(Margin);
  HintLabel.Parent := Self;

  { Under the list: the error, then Add, Edit and Remove on the left and
    Close on the right. }
  Bottom := TPanel.Create(Self);
  Bottom.BevelOuter := bvNone;
  Bottom.AutoSize := True;
  Bottom.Align := alBottom;
  Bottom.BorderSpacing.Around := Scale96ToScreen(Margin);
  Bottom.Parent := Self;
  AddButton := MakeButton(Self, rsRemotesAdd, Bottom, alLeft, @AddClick);
  AddButton.Left := 0;
  FEditButton := MakeButton(Self, rsRemotesEdit, Bottom, alLeft, @EditClick);
  FEditButton.Left := 1000;
  FEditButton.BorderSpacing.Left := Scale96ToScreen(8);
  FRemoveButton := MakeButton(Self, rsRemotesRemove, Bottom, alLeft, @RemoveClick);
  FRemoveButton.Left := 2000;
  FRemoveButton.BorderSpacing.Left := Scale96ToScreen(8);
  CloseButton := MakeButton(Self, rsRemotesClose, Bottom, alRight, nil);
  CloseButton.ModalResult := mrOK;
  CloseButton.Cancel := True;
  CloseButton.Default := True;

  FError := TLabel.Create(Self);
  FError.WordWrap := True;
  FError.Font.Color := clRed;
  FError.ShowAccelChar := False;
  FError.Visible := False;
  FError.Align := alBottom;
  FError.BorderSpacing.Left := Scale96ToScreen(Margin);
  FError.BorderSpacing.Right := Scale96ToScreen(Margin);
  FError.BorderSpacing.Top := Scale96ToScreen(8);
  FError.Parent := Self;

  FList := TListView.Create(Self);
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.ScrollBars := ssAutoVertical;
  Col := FList.Columns.Add;
  Col.Caption := rsRemotesName;
  Col.Width := Scale96ToScreen(120);
  Col := FList.Columns.Add;
  Col.Caption := rsRemotesUrl;
  FList.Align := alClient;
  FList.BorderSpacing.Left := Scale96ToScreen(Margin);
  FList.BorderSpacing.Right := Scale96ToScreen(Margin);
  FList.OnSelectItem := @ListSelectItem;
  FList.OnDblClick := @ListDblClick;
  FList.OnKeyDown := @ListKeyDown;
  FList.OnResize := @ListResize;
  FList.Parent := Self;

  { In the middle of the list while it is empty. }
  FEmpty := TLabel.Create(Self);
  FEmpty.Caption := rsRemotesNone;
  FEmpty.Font.Color := clGrayText;
  FEmpty.AnchorSideLeft.Control := FList;
  FEmpty.AnchorSideLeft.Side := asrCenter;
  FEmpty.AnchorSideTop.Control := FList;
  FEmpty.AnchorSideTop.Side := asrCenter;
  FEmpty.Parent := Self;
  FEmpty.BringToFront;
end;

{ The selection made before the list was shown does not stick on every
  widgetset, so the first row is selected again once it is. }
procedure TRemotesForm.DoShow;
begin
  inherited DoShow;
  ActiveControl := FList;
  if (FList.Selected = nil) and (FList.Items.Count > 0) then
  begin
    FList.Selected := FList.Items[0];
    FList.ItemFocused := FList.Selected;
  end;
  UpdateButtons;
end;

{ The URL takes the width the name leaves, so the list does not scroll
  sideways: of the list's own width, since on Cocoa the client width
  follows the columns. }
procedure TRemotesForm.ListResize(Sender: TObject);
begin
  FList.Columns[1].Width := Max(Scale96ToScreen(120), FList.Width -
    FList.Columns[0].Width - Scale96ToScreen(28));
end;

{ The remotes as git lists them, ASelect selected, else the first. }
procedure TRemotesForm.Fill(const ASelect: string);
var
  Err, Url: string;
  i, At: integer;
  Item: TListItem;
begin
  if not ReadRemotes(FRepo.Root, FRemotes, Err) then
  begin
    FError.Caption := Trim(Err);
    FError.Visible := True;
  end;
  At := 0;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for i := 0 to High(FRemotes) do
    begin
      Item := FList.Items.Add;
      Item.Caption := FRemotes[i].Name;
      Url := FRemotes[i].Url;
      if (FRemotes[i].PushUrl <> '') and (FRemotes[i].PushUrl <> Url) then
        Url := Format(rsRemotesPushTo, [Url, FRemotes[i].PushUrl]);
      Item.SubItems.Add(Url);
      if FRemotes[i].Name = ASelect then
        At := i;
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if FList.Items.Count > 0 then
  begin
    FList.Selected := FList.Items[At];
    FList.ItemFocused := FList.Selected;
  end;
  FEmpty.Visible := FList.Items.Count = 0;
  UpdateButtons;
end;

function TRemotesForm.SelectedIndex: integer;
begin
  if FList.Selected = nil then
    Result := -1
  else
    Result := FList.Selected.Index;
  if Result > High(FRemotes) then
    Result := -1;
end;

procedure TRemotesForm.UpdateButtons;
begin
  FEditButton.Enabled := SelectedIndex >= 0;
  FRemoveButton.Enabled := SelectedIndex >= 0;
end;

function TRemotesForm.Names: TStringList;
var
  R: TGittanRemote;
begin
  Result := TStringList.Create;
  Result.CaseSensitive := True;
  for R in FRemotes do
    Result.Add(R.Name);
end;

procedure TRemotesForm.AddClick(Sender: TObject);
var
  F: TRemoteForm;
  Taken: TStringList;
  R: TGittanRemote;
  Clip: string;
begin
  Taken := Names;
  try
    R := Default(TGittanRemote);
    { The first remote is origin, as git clone names it. }
    if Taken.Count = 0 then
      R.Name := 'origin';
    Clip := '';
    if Clipboard.HasFormat(CF_TEXT) then
      Clip := Trim(Clipboard.AsText);
    if LooksLikeCloneUrl(Clip) then
      R.Url := Clip;
    F := TRemoteForm.Create(Self, FRepo, Taken, R, True);
    try
      F.ShowModal;
      if F.FChanged then
      begin
        FChanged := True;
        FFetch := FFetch or F.FFetch.Checked;
        Fill(F.FOld);
      end;
    finally
      F.Free;
    end;
  finally
    Taken.Free;
  end;
end;

procedure TRemotesForm.EditClick(Sender: TObject);
var
  F: TRemoteForm;
  Taken: TStringList;
  i: integer;
begin
  i := SelectedIndex;
  if i < 0 then
    Exit;
  Taken := Names;
  try
    F := TRemoteForm.Create(Self, FRepo, Taken, FRemotes[i], False);
    try
      F.ShowModal;
      if F.FChanged then
      begin
        FChanged := True;
        Fill(F.FOld);
      end;
    finally
      F.Free;
    end;
  finally
    Taken.Free;
  end;
end;

procedure TRemotesForm.RemoveClick(Sender: TObject);
var
  Local, Remote: TStringList;
  RemoteName, Msg: string;
  i, Count: integer;
begin
  i := SelectedIndex;
  if i < 0 then
    Exit;
  RemoteName := FRemotes[i].Name;
  Count := 0;
  Local := TStringList.Create;
  Remote := TStringList.Create;
  try
    if FRepo.Branches(Local, Remote) then
      for i := 0 to Remote.Count - 1 do
        if Pos(RemoteName + '/', Remote[i]) = 1 then
          Inc(Count);
  finally
    Local.Free;
    Remote.Free;
  end;
  case Count of
    0: Msg := rsRemoveNoBranches;
    1: Msg := rsRemoveOneBranch;
    else
      Msg := Format(rsRemoveBranches, [Count]);
  end;
  if QuestionDlg(rsRemoveTitle, Format(rsRemoveAsk, [RemoteName]) + LineEnding + LineEnding +
    Msg, mtWarning, [mrYes, rsRemoveButton, mrCancel, rsCancel, 'IsCancel', 'IsDefault'],
    0) <> mrYes then
    Exit;
  if FRepo.RemoveRemote(RemoteName) then
  begin
    FChanged := True;
    FError.Visible := False;
  end
  else
  begin
    FError.Caption := Trim(FRepo.Error);
    FError.Visible := True;
  end;
  Fill('');
end;

procedure TRemotesForm.ListSelectItem(Sender: TObject; Item: TListItem; Selected: boolean);
begin
  UpdateButtons;
end;

procedure TRemotesForm.ListDblClick(Sender: TObject);
begin
  EditClick(Sender);
end;

procedure TRemotesForm.ListKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        EditClick(Sender);
        Key := 0;
      end;
    VK_DELETE, VK_BACK:
      begin
        RemoveClick(Sender);
        Key := 0;
      end;
  end;
end;

function EditRemotes(ARepo: TGittanRepo; out AFetch: boolean): boolean;
var
  F: TRemotesForm;
begin
  F := TRemotesForm.Create(Screen.ActiveForm);
  try
    F.FRepo := ARepo;
    F.Fill('');
    F.ShowModal;
    Result := F.FChanged;
    AFetch := F.FFetch;
  finally
    F.Free;
  end;
end;

end.
