unit uforge;

{** The forge view: the user's pull requests across every repository of
  the forge (GitHub), shown in the window over the repository frames
  (TRepoFrame in umain) from the globe at the right end of the window's
  top chrome, the tab strip on macOS and the own title bar on Windows
  and GTK 3, whose tabs are the view's own meanwhile; the globe again,
  Escape or Close GitHub (Cmd+W) goes back to the repository. It is one for the window, since what it
  shows is the user's and not a repository's, and it is there only
  while there is a forge (the first registered that is on and whose
  tool is found: App.ForgeCli), which SettingsChanged finds again.

  The content is the forge page (gittan.forgepage) in a scroll box, as
  the Pull Requests page sits in a repository frame's: the open pull
  requests the user wrote or the open ones waiting for their review, a
  section at a time, which the window's tab strip picks while the view
  is shown (Tabs, SelectTab, StepTab, OnTabsChange), with the Batch tab
  after them (BatchTab): the batch page (gittan.batchpage) in the same
  box in the page's place, operations run in several of the
  repositories the welcome view shows, picked there (kept in the
  settings, BatchRepos); so far deleting the branches deleted on the
  remote, which the view scans for and deletes in jobs of its own
  (gittan.batch), asking first,
  read by the forge's AccountJob (gittan.forge; GitHub's runs one
  GraphQL query through gh) once at start, each time the view is shown,
  on Refresh and when the forge or its account changes, the page keeping
  what it had meanwhile; the login and the user's picture go to the
  chrome's globe as well (Picture, ChromeHint, OnUserChange), the
  picture kept between starts beside the settings. A card of a pull request goes
  to the window (TRepoWindow.ComparePullRequest): a frame with a remote
  for its repository compares with it there, else its local clone among
  the recent repositories (or beside them while CloneSiblings is on;
  the job's FindClones and AddSiblingRepositories) opens in a tab and
  compares, else the pull request opens on the forge.

  The view has a menu of its own (MainMenu, with AppMenuItem for the
  application menu on macOS), the few items that mean something without
  a repository: New Tab, Open Repository..., Open Recent, Close GitHub,
  Refresh, the tabs, Settings..., Check for Updates... and About; the
  global ones go through TRepoWindow, which runs them in the repository
  frame shown under the view. The window sets the menu, the caption and
  the title bar when it shows the view (Shown) and gives the frame's
  back when it hides it (Hidden). See spec/github.md. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Menus, ExtCtrls, Graphics, LCLType, Dialogs,
  Clipbrd, gittan.job, gittan.forge, gittan.forgepage, gittan.batch, gittan.batchpage,
  gittan.askdlg, umain;

const
  {** The Batch tab's index, after the forge page's sections. }
  BatchTab = SectionCount;

type

  { TForgeView }

  TForgeView = class(TCustomControl)
  private
    FWindow: TRepoWindow;
    FBox: TScrollBox;
    FPage: TGittanForgePage;
    { The Batch tab's page, shown in the box in FPage's place while
      FBatchShown; the scan and the deletion it runs, one at a time. }
    FBatch: TGittanBatchPage;
    FBatchShown: boolean;
    FScanJob: TGittanGoneScanJob;
    FDeleteJob: TGittanGoneDeleteJob;
    FForge: TGittanForge;
    { The job under way, and the jobs given up or done, freed once their
      thread has ended. }
    FJob: TGittanForgeJob;
    FZombies: TGittanJobReaper;
    { An action on a pull request from a card's menu (PageContext): the
      job running it, the pull request the menu was opened for and the
      menu. }
    FActionJob: TGittanPullActionJob;
    FActionPull: TGittanForgePull;
    FCardPopup: TPopupMenu;
    FLogin, FError: string;
    { The address of the user's picture as last fetched, and its bytes,
      kept across the jobs so a refresh does not fetch it again. }
    FAvatarUrl, FAvatar: string;
    { Whether the picture was fetched in this run, so a job may skip its
      address; and whether the login and picture are the ones kept from
      the last start (LoadPicture), which the first answer confirms or,
      when it fails, drops. }
    FPictureFresh, FRestored: boolean;
    FMine, FReview: TGittanForgePulls;
    FMainMenu: TMainMenu;
    FAppMenuItem: TMenuItem;
    FRecentMenu, FCloseItem: TMenuItem;
    FDark: boolean;
    FThemeTimer: TTimer;
    FOnTabsChange, FOnUserChange: TNotifyEvent;
    function FindForge: boolean;
    procedure ForgetAnswers;
    procedure LoadPicture;
    procedure UserChanged;
    procedure BuildMenu;
    procedure RebuildRecentMenu;
    procedure ApplyTheme;
    procedure UpdatePage;
    procedure StartJob;
    procedure AbandonJob;
    procedure JobDone(Sender: TObject);
    procedure FreeJobsAsync(Data: PtrInt);
    procedure BoxResize(Sender: TObject);
    procedure ShowBatch;
    procedure BatchChosenChange(Sender: TObject);
    procedure BatchScan(Sender: TObject);
    procedure ScanProgress(Sender: TObject);
    procedure ScanDone(Sender: TObject);
    procedure BatchDelete(Sender: TObject);
    procedure DeleteProgress(Sender: TObject);
    procedure DeleteDone(Sender: TObject);
    procedure PagePick(Sender: TObject; const APull: TGittanForgePull);
    procedure PageContext(Sender: TObject; const APull: TGittanForgePull;
      const AScreenPos: TPoint);
    procedure CardMenuClick(Sender: TObject);
    { Whether an action can be done now: the forge acts and none runs. }
    function ActsNow: boolean;
    procedure StartAction(const APull: TGittanForgePull; AAction: TGittanPullAction);
    procedure ActionDone(Sender: TObject);
    procedure AbandonAction;
    procedure PageRefresh(Sender: TObject);
    procedure LoadFilters;
    procedure PageFilterChange(Sender: TObject);
    procedure PageSavePreset(Sender: TObject);
    procedure PageOpenUrl(Sender: TObject; const AUrl: string);
    procedure ThemeTimerTimer(Sender: TObject);
    procedure FileMenuClick(Sender: TObject);
    procedure MenuNewTabClick(Sender: TObject);
    procedure MenuOpenRepoClick(Sender: TObject);
    procedure MenuRecentClick(Sender: TObject);
    procedure MenuCloseClick(Sender: TObject);
    procedure MenuRefreshClick(Sender: TObject);
    procedure MenuNextTabClick(Sender: TObject);
    procedure MenuPrevTabClick(Sender: TObject);
    procedure MenuCheckUpdatesClick(Sender: TObject);
    procedure MenuSettingsClick(Sender: TObject);
    procedure MenuAboutClick(Sender: TObject);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** Builds the view, once it is placed in AWindow, which it then
      asks for what needs a repository or the window (FWindow). }
    procedure Init(AWindow: TRepoWindow);
    {** Whether there is a forge: the globe shows and the view can be
      shown only then. }
    function HasForge: boolean;
    {** The forge's name, '' without one. }
    function ForgeName: string;
    {** What the chrome's globe says of the forge: its name, with the
      login before it once the forge has said who ("octocat on GitHub"). }
    function ChromeHint: string;
    {** The user's login as the forge last gave it, '' before it has. }
    property Login: string read FLogin;
    {** The bytes of the user's picture (PNG or JPEG) as the forge gave
      it, '' without one, for the chrome's globe. }
    property Picture: string read FAvatar;
    {** The user changed: the login or the picture came, changed or went,
      so the chrome's globe follows. }
    property OnUserChange: TNotifyEvent read FOnUserChange write FOnUserChange;
    {** The window shows the view now: the page follows the appearance,
      shows what the forge last answered and asks it again. }
    procedure Shown;
    {** The window hid the view. }
    procedure Hidden;
    {** The settings dialog was closed with OK and the tools may have
      changed: the forge is found again, and what one that is gone had
      found is dropped (the window hides the view then, HasForge). }
    procedure SettingsChanged;
    {** The active account of the forge's tool changed: what the account
      of before had found goes, and the view asks again. }
    procedure AccountChanged;
    {** The view's tabs, which the window's tab strip shows while the
      view is shown: their names in ACaptions, in AMarks the ones with
      something to do (pull requests waiting for review); gives the
      shown one's index. }
    function Tabs(out ACaptions: TStringArray; out AMarks: TBooleanDynArray): integer;
    {** How many tabs: the sections, then Batch. }
    function TabCount: integer;
    {** Shows the tab at AIndex. }
    procedure SelectTab(AIndex: integer);
    {** The tab ADelta tabs on, round the ends. }
    procedure StepTab(ADelta: integer);
    {** The tabs changed: another one is shown or their marks changed. }
    property OnTabsChange: TNotifyEvent read FOnTabsChange write FOnTabsChange;
    {** The window's keys while the view is shown: Escape closes it. }
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    {** The view's menu, the window's while the view is shown. }
    property MainMenu: TMainMenu read FMainMenu;
    {** The application menu's first items on macOS (About, Settings),
      set before the menu. }
    property AppMenuItem: TMenuItem read FAppMenuItem;
  end;

implementation

uses
  LCLIntf, gittan.app, gittan.theme, gittan.textfit;

resourcestring
  rsSavePresetTitle = 'Save as Preset';
  rsSavePresetPrompt = 'Name for the filters that are on:';
  rsFile = '&File';

  rsNewTab = 'New &Tab';
  rsOpenRepo = 'Open &Repository...';
  rsOpenRecent = 'Open Re&cent';
  rsNoRecent = 'No recent repositories';
  { The forge's name after Close: "Close GitHub". }
  rsCloseForge = 'Close %s';
  rsView = '&View';
  rsRefresh = 'Re&fresh';
  rsGo = '&Go';
  rsNextTab = 'Next Tab';
  rsPrevTab = 'Previous Tab';
  rsTools = '&Tools';
  rsCheckUpdates = 'Check for &Updates...';
  rsSettings = 'Se&ttings...';
  rsAbout = '&About Gittan';
  { The globe's hint: the login, then the forge: "octocat on GitHub". }
  rsUserOnForge = '%s on %s';
  rsBatchTab = 'Batch';
  { The heading of the recent repositories the repository list lacks. }
  rsRecentRepos = 'Recent';
  rsBatchDeleteTitle = 'Delete Branches';
  rsBatchDeleteOne = 'Delete the branch “%s” in %s?';
  rsBatchDeleteMany = 'Delete %d branches in %d repositories?';
  rsBatchDeleteManyOne = 'Delete %d branches in %s?';
  rsBatchNotMerged = '%d of them are not merged into the default branch: commits that only ' +
    'they have are lost.';
  rsBatchNotMergedOne = 'It is not merged into the default branch: commits that only it has ' +
    'are lost.';
  rsBatchDelete = 'Delete';
  rsBatchCancel = 'Cancel';

{ TForgeView }

constructor TForgeView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FZombies := TGittanJobReaper.Create;
end;

destructor TForgeView.Destroy;
begin
  Application.RemoveAsyncCalls(Self);
  if FThemeTimer <> nil then
    FThemeTimer.Enabled := False;
  AbandonJob;
  AbandonAction;
  { A scan is given up; a deletion runs to its end. }
  if FScanJob <> nil then
  begin
    FScanJob.Stop(False);
    FZombies.Add(FScanJob);
    FScanJob := nil;
  end;
  if FDeleteJob <> nil then
  begin
    FDeleteJob.Stop(False);
    FZombies.Add(FDeleteJob);
    FDeleteJob := nil;
  end;
  { Waits for the jobs given up. }
  FreeAndNil(FZombies);
  FreeAndNil(FForge);
  inherited Destroy;
end;

procedure TForgeView.Init(AWindow: TRepoWindow);
begin
  FWindow := AWindow;
  FBox := TScrollBox.Create(Self);
  FBox.BorderStyle := bsNone;
  FBox.HorzScrollBar.Visible := False;
  FBox.Align := alClient;
  { Under the strip the title bar covers on macOS. }
  FBox.BorderSpacing.Top := AWindow.TitleBarHeight;
  FBox.OnResize := @BoxResize;
  FBox.Parent := Self;
  FPage := TGittanForgePage.Create(Self);
  FPage.Parent := FBox;
  FPage.OnPick := @PagePick;
  FPage.OnContext := @PageContext;
  FCardPopup := TPopupMenu.Create(Self);
  FPage.OnRefresh := @PageRefresh;
  LoadFilters;
  FPage.OnFilterChange := @PageFilterChange;
  FPage.OnSavePreset := @PageSavePreset;
  FPage.OnOpenUrl := @PageOpenUrl;
  FBatch := TGittanBatchPage.Create(Self);
  FBatch.Visible := False;
  FBatch.Parent := FBox;
  FBatch.SetChosen(App.Settings.BatchRepos);
  FBatch.OnChosenChange := @BatchChosenChange;
  FBatch.OnScan := @BatchScan;
  FBatch.OnDelete := @BatchDelete;
  FThemeTimer := TTimer.Create(Self);
  FThemeTimer.Interval := 2000;
  FThemeTimer.Enabled := False;
  FThemeTimer.OnTimer := @ThemeTimerTimer;
  FDark := IsDarkMode;
  ApplyTheme;
  FindForge;
  { The picture kept from the last start, then the forge asked once at
    start, so the chrome's globe has the user and the view its lists
    before it is first shown. }
  LoadPicture;
  StartJob;
  BuildMenu;
end;

{ The picture kept from the last start (SaveForgePicture, in JobDone),
  when it is this forge's and its login is the forge's active account:
  none when the forge lists no account (logged out, or one that keeps no
  list) or something else picks the account (AccountsNote, a token in
  the environment). }
procedure TForgeView.LoadPicture;
var
  KeptForge, KeptLogin, KeptUrl, KeptBytes: string;
  Account: TGittanForgeAccount;
  Accounts: TGittanForgeAccounts;
  Known: boolean;
begin
  if not Assigned(FForge) then
    Exit;
  if not LoadForgePicture(App.Settings.ForgePictureFile, KeptForge, KeptLogin, KeptUrl,
    KeptBytes) or (KeptForge <> FForge.Name) then
    Exit;
  if FForge.AccountsNote <> '' then
    Exit;
  Accounts := FForge.Accounts;
  Known := False;
  for Account in Accounts do
    Known := Known or (Account.Active and SameText(Account.Login, KeptLogin));
  if not Known then
    Exit;
  FLogin := KeptLogin;
  FAvatarUrl := KeptUrl;
  FAvatar := KeptBytes;
  FRestored := True;
end;

procedure TForgeView.UserChanged;
begin
  if Assigned(FOnUserChange) then
    FOnUserChange(Self);
end;

{ The first registered forge that is on and whose tool is found, kept
  while it and its tool's path stay the same, as a repository frame
  finds its own. True when it changed. }
function TForgeView.FindForge: boolean;
var
  Forge, Found: TGittanForgeClass;
  Cli: string;
begin
  Found := nil;
  Cli := '';
  for Forge in RegisteredForges do
  begin
    Cli := App.ForgeCli(Forge);
    if Cli <> '' then
    begin
      Found := Forge;
      Break;
    end;
  end;
  Result := KeepForge(FForge, Found, Cli);
  if not Result then
    Exit;
  FPage.SetForge(ForgeName);
  { The filters are the forge's, and what the user kept of them. }
  LoadFilters;
  if FCloseItem <> nil then
    FCloseItem.Caption := Format(rsCloseForge, [ForgeName]);
end;

function TForgeView.HasForge: boolean;
begin
  Result := Assigned(FForge);
end;

function TForgeView.ForgeName: string;
begin
  if Assigned(FForge) then
    Result := FForge.Name
  else
    Result := '';
end;

function TForgeView.ChromeHint: string;
begin
  Result := ForgeName;
  if (Result <> '') and (FLogin <> '') then
    Result := Format(rsUserOnForge, [FLogin, Result]);
end;

{ The items that mean something without a repository; the global ones
  run through the window in the repository frame under the view. }
procedure TForgeView.BuildMenu;
var
  FileMenu, ViewMenu, GoMenu, ToolsMenu, Item: TMenuItem;

  function AddItem(AParent: TMenuItem; const ACaption: string; AShortCut: TShortCut;
    AClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(AParent);
    Result.Caption := ACaption;
    Result.ShortCut := AShortCut;
    Result.OnClick := AClick;
    AParent.Add(Result);
  end;

begin
  FMainMenu := TMainMenu.Create(Self);
  {$IFDEF LCLCocoa}
  Item := TMenuItem.Create(Self);
  AddItem(Item, rsAbout, 0, @MenuAboutClick);
  Item.Add(NewLine);
  AddItem(Item, rsSettings, ShortCut(VK_OEM_COMMA, [ssModifier]), @MenuSettingsClick);
  FAppMenuItem := Item;
  {$ENDIF}

  FileMenu := TMenuItem.Create(FMainMenu);
  FileMenu.Caption := rsFile;
  FileMenu.OnClick := @FileMenuClick;
  FMainMenu.Items.Add(FileMenu);
  AddItem(FileMenu, rsNewTab, ShortCut(VK_T, [ssModifier]), @MenuNewTabClick);
  AddItem(FileMenu, rsOpenRepo, ShortCut(VK_O, [ssModifier, ssShift]), @MenuOpenRepoClick);
  FRecentMenu := AddItem(FileMenu, rsOpenRecent, 0, nil);
  RebuildRecentMenu;
  FCloseItem := AddItem(FileMenu, Format(rsCloseForge, [ForgeName]),
    ShortCut(VK_W, [ssModifier]), @MenuCloseClick);

  ViewMenu := TMenuItem.Create(FMainMenu);
  ViewMenu.Caption := rsView;
  FMainMenu.Items.Add(ViewMenu);
  AddItem(ViewMenu, rsRefresh, ShortCut(VK_R, [ssModifier]), @MenuRefreshClick);

  GoMenu := TMenuItem.Create(FMainMenu);
  GoMenu.Caption := rsGo;
  FMainMenu.Items.Add(GoMenu);
  AddItem(GoMenu, rsNextTab, ShortCut(VK_OEM_6, [ssModifier, ssShift]), @MenuNextTabClick);
  AddItem(GoMenu, rsPrevTab, ShortCut(VK_OEM_4, [ssModifier, ssShift]), @MenuPrevTabClick);

  ToolsMenu := TMenuItem.Create(FMainMenu);
  ToolsMenu.Caption := rsTools;
  FMainMenu.Items.Add(ToolsMenu);
  AddItem(ToolsMenu, rsCheckUpdates, 0, @MenuCheckUpdatesClick);
  {$IFNDEF LCLCocoa}
  ToolsMenu.Add(NewLine);
  AddItem(ToolsMenu, rsSettings, ShortCut(VK_OEM_COMMA, [ssModifier]), @MenuSettingsClick);
  AddItem(ToolsMenu, rsAbout, 0, @MenuAboutClick);
  {$ENDIF}
end;

{ The recent repositories as a repository frame's File menu names them,
  built again as the File menu opens, since the list changes with every
  repository opened. }
procedure TForgeView.RebuildRecentMenu;
var
  Item: TMenuItem;
  i: integer;
begin
  FRecentMenu.Clear;
  for i := 0 to App.Settings.Recent.Count - 1 do
  begin
    Item := TMenuItem.Create(FRecentMenu);
    Item.Caption := ShortPath(App.Settings.Recent[i]);
    Item.Hint := App.Settings.Recent[i];
    Item.OnClick := @MenuRecentClick;
    FRecentMenu.Add(Item);
  end;
  if App.Settings.Recent.Count = 0 then
  begin
    Item := TMenuItem.Create(FRecentMenu);
    Item.Caption := rsNoRecent;
    Item.Enabled := False;
    FRecentMenu.Add(Item);
  end;
end;

procedure TForgeView.FileMenuClick(Sender: TObject);
begin
  RebuildRecentMenu;
end;

{ The page's palette for the appearance; the view and the box take its
  background, which also lies behind the strip under the title bar. }
procedure TForgeView.ApplyTheme;
begin
  FPage.SetTheme(FDark);
  FBatch.SetTheme(FDark);
  Color := FPage.Color;
  FBox.Color := FPage.Color;
  Invalidate;
end;

procedure TForgeView.ThemeTimerTimer(Sender: TObject);
begin
  if IsDarkMode <> FDark then
  begin
    FDark := not FDark;
    ApplyTheme;
  end;
end;

procedure TForgeView.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
end;

procedure TForgeView.Shown;
begin
  if IsDarkMode <> FDark then
  begin
    FDark := not FDark;
    ApplyTheme;
  end;
  { The job first, so the page does not take the lists of before it as
    the forge's answer. }
  StartJob;
  UpdatePage;
  { The repository list or the recent ones may have changed. }
  if FBatchShown then
    ShowBatch;
  FBox.VertScrollBar.Position := 0;
  FThemeTimer.Enabled := True;
end;

procedure TForgeView.Hidden;
begin
  FThemeTimer.Enabled := False;
end;

procedure TForgeView.SettingsChanged;
begin
  if FindForge then
    ForgetAnswers;
end;

procedure TForgeView.AccountChanged;
begin
  if Assigned(FForge) then
    ForgetAnswers;
end;

{ What the forge or the account of before had found or was asking; a
  new one is asked at once, shown or not, so the chrome's globe follows
  the account. }
procedure TForgeView.ForgetAnswers;
begin
  AbandonJob;
  FMine := nil;
  FReview := nil;
  FLogin := '';
  FAvatarUrl := '';
  FAvatar := '';
  FPictureFresh := False;
  FRestored := False;
  FError := '';
  FPage.ForgetAnswer;
  { The job first, as in Shown. }
  StartJob;
  UpdatePage;
  UserChanged;
end;

procedure TForgeView.FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and (Shift = []) then
  begin
    Key := 0;
    FWindow.HideForgeView;
  end;
end;

{ What the job last read, to the page, and whether one runs. }
procedure TForgeView.UpdatePage;
begin
  FPage.SetLogin(FLogin);
  FPage.SetAvatar(FAvatar);
  FPage.SetPulls(FMine, FReview, FError, FJob <> nil);
  FPage.FitHeight(FBox.ClientHeight);
  if Assigned(FOnTabsChange) then
    FOnTabsChange(Self);
end;

function TForgeView.Tabs(out ACaptions: TStringArray; out AMarks: TBooleanDynArray): integer;
var
  i: integer;
begin
  ACaptions := nil;
  AMarks := nil;
  SetLength(ACaptions, TabCount);
  SetLength(AMarks, TabCount);
  for i := 0 to SectionCount - 1 do
    ACaptions[i] := SectionCaption(i);
  ACaptions[BatchTab] := rsBatchTab;
  AMarks[Ord(fsReview)] := Length(FReview) > 0;
  if FBatchShown then
    Result := BatchTab
  else
    Result := FPage.Section;
end;

function TForgeView.TabCount: integer;
begin
  Result := SectionCount + 1;
end;

procedure TForgeView.SelectTab(AIndex: integer);
var
  Current: integer;
begin
  if FBatchShown then
    Current := BatchTab
  else
    Current := FPage.Section;
  if (AIndex < 0) or (AIndex >= TabCount) or (AIndex = Current) then
    Exit;
  if AIndex = BatchTab then
  begin
    FBatchShown := True;
    ShowBatch;
  end
  else
  begin
    FBatchShown := False;
    FPage.Section := AIndex;
    FPage.FitHeight(FBox.ClientHeight);
    FBatch.Visible := False;
    FPage.Visible := True;
  end;
  FBox.VertScrollBar.Position := 0;
  if Assigned(FOnTabsChange) then
    FOnTabsChange(Self);
end;

procedure TForgeView.StepTab(ADelta: integer);
var
  Current: integer;
begin
  if FBatchShown then
    Current := BatchTab
  else
    Current := FPage.Section;
  SelectTab(((Current + ADelta) mod TabCount + TabCount) mod TabCount);
end;

procedure TForgeView.BoxResize(Sender: TObject);
begin
  FPage.FitHeight(FBox.ClientHeight);
  if FBatch.Visible then
    FBatch.FitHeight(FBox.ClientHeight);
end;

{ The batch page in the forge page's place, its rows read again from the
  repository list and the recent repositories, measured before it is
  shown. }
procedure TForgeView.ShowBatch;
begin
  FBatch.SetRows(BatchRows(App.RepoList, App.Settings.Recent, rsRecentRepos));
  FBatch.Width := FBox.ClientWidth;
  FBatch.FitHeight(FBox.ClientHeight);
  FPage.Visible := False;
  FBatch.Visible := True;
end;

procedure TForgeView.BatchChosenChange(Sender: TObject);
begin
  App.Settings.BatchRepos.Assign(FBatch.Chosen);
  FBatch.FitHeight(FBox.ClientHeight);
end;

{ Scan: the picked repositories fetched and their gone branches found,
  in a job, the page showing each repository as it is done. }
procedure TForgeView.BatchScan(Sender: TObject);
var
  Paths, Captions: TStringArray;
begin
  if FBatch.Busy then
    Exit;
  FBatch.ChosenRepos(Paths, Captions);
  if Length(Paths) = 0 then
    Exit;
  FScanJob := TGittanGoneScanJob.Create(Paths, Captions);
  FScanJob.OnProgress := @ScanProgress;
  FScanJob.OnDone := @ScanDone;
  FBatch.StartScan(Length(Paths));
  FBatch.FitHeight(FBox.ClientHeight);
  FScanJob.Start;
end;

procedure TForgeView.ScanProgress(Sender: TObject);
begin
  if Sender <> FScanJob then
    Exit;
  FBatch.SetScan(FScanJob.Repos, FScanJob.Finished, True);
  FBatch.FitHeight(FBox.ClientHeight);
end;

procedure TForgeView.ScanDone(Sender: TObject);
var
  Job: TGittanGoneScanJob;
begin
  Job := TGittanGoneScanJob(Sender);
  if Job <> FScanJob then
    Exit;
  FScanJob := nil;
  FZombies.Add(Job);
  Application.QueueAsyncCall(@FreeJobsAsync, 0);
  FBatch.SetScan(Job.Repos, Job.Finished, False);
  FBatch.FitHeight(FBox.ClientHeight);
end;

{ Delete: the branches picked, after a question that says how many are
  not merged, deleted in a job; the frames of those repositories see
  their branches go through their watchers. }
procedure TForgeView.BatchDelete(Sender: TObject);
var
  Refs: TGittanBranchRefs;
  Repos: TStringList;
  Ask: string;
  NotMerged, i: integer;
  Kind: TMsgDlgType;
begin
  if FBatch.Busy then
    Exit;
  Refs := FBatch.PickedRefs;
  if Length(Refs) = 0 then
    Exit;
  NotMerged := FBatch.PickedNotMerged;
  Repos := TStringList.Create;
  try
    Repos.Sorted := True;
    Repos.Duplicates := dupIgnore;
    for i := 0 to High(Refs) do
      Repos.Add(Refs[i].Path);
    if Length(Refs) = 1 then
      Ask := Format(rsBatchDeleteOne, [Refs[0].Branch, ShortPath(Refs[0].Path)])
    else if Repos.Count = 1 then
      Ask := Format(rsBatchDeleteManyOne, [Length(Refs), ShortPath(Refs[0].Path)])
    else
      Ask := Format(rsBatchDeleteMany, [Length(Refs), Repos.Count]);
  finally
    Repos.Free;
  end;
  Kind := mtConfirmation;
  if NotMerged > 0 then
  begin
    Kind := mtWarning;
    if Length(Refs) = 1 then
      Ask := Ask + LineEnding + LineEnding + rsBatchNotMergedOne
    else
      Ask := Ask + LineEnding + LineEnding + Format(rsBatchNotMerged, [NotMerged]);
  end;
  if AskDlg(rsBatchDeleteTitle, Ask, Kind, [mrYes, rsBatchDelete, mrCancel, rsBatchCancel,
    'IsCancel', 'IsDefault'], 0) <> mrYes then
    Exit;
  FDeleteJob := TGittanGoneDeleteJob.Create(Refs);
  FDeleteJob.OnProgress := @DeleteProgress;
  FDeleteJob.OnDone := @DeleteDone;
  FBatch.SetDeleting(True);
  FDeleteJob.Start;
end;

procedure TForgeView.DeleteProgress(Sender: TObject);
begin
  if Sender <> FDeleteJob then
    Exit;
  FBatch.ApplyDeleted(FDeleteJob.Refs, FDeleteJob.Branches, FDeleteJob.Finished);
  FBatch.FitHeight(FBox.ClientHeight);
end;

procedure TForgeView.DeleteDone(Sender: TObject);
var
  Job: TGittanGoneDeleteJob;
begin
  Job := TGittanGoneDeleteJob(Sender);
  if Job <> FDeleteJob then
    Exit;
  FDeleteJob := nil;
  FZombies.Add(Job);
  Application.QueueAsyncCall(@FreeJobsAsync, 0);
  FBatch.ApplyDeleted(Job.Refs, Job.Branches, Job.Finished);
  FBatch.SetDeleting(False);
  FBatch.FitHeight(FBox.ClientHeight);
end;

{ Asks the forge, one job at a time: a start while one runs waits for
  its answer. The job needs no repository; gh runs in the user's folder. }
procedure TForgeView.StartJob;
begin
  if not Assigned(FForge) or (FJob <> nil) then
    Exit;
  FJob := FForge.AccountJob(GetUserDir);
  { The picture kept from the last start is fetched again once, as the
    forge may give a new one at the same address. }
  if FPictureFresh then
    FJob.KnownAvatarUrl := FAvatarUrl;
  FJob.Clones.Assign(App.Settings.Recent);
  FJob.Siblings := App.Settings.CloneSiblings;
  FJob.OnDone := @JobDone;
  FJob.Start;
  UpdatePage;
end;

procedure TForgeView.AbandonJob;
begin
  if FJob = nil then
    Exit;
  FJob.Stop(False);
  FZombies.Add(FJob);
  FJob := nil;
end;

procedure TForgeView.JobDone(Sender: TObject);
var
  Job: TGittanForgeJob;
  OldLogin, OldAvatar, OldAvatarUrl: string;
begin
  OldLogin := FLogin;
  OldAvatar := FAvatar;
  OldAvatarUrl := FAvatarUrl;
  Job := TGittanForgeJob(Sender);
  if Job <> FJob then
    Exit;
  FJob := nil;
  FZombies.Add(Job);
  Application.QueueAsyncCall(@FreeJobsAsync, 0);
  FError := Job.Error;
  if FError = '' then
  begin
    FLogin := Job.Login;
    { A picture fetched, new or the kept one again; else a new address,
      or none any more, drops the one held, and the same address keeps
      it: the job did not fetch it again, or the fetch of the kept one
      failed and is tried again next time. }
    if Job.Avatar <> '' then
    begin
      FAvatarUrl := Job.PictureUrl;
      FAvatar := Job.Avatar;
      FPictureFresh := True;
    end
    else if Job.PictureUrl <> FAvatarUrl then
    begin
      { A fetch that failed tries again next time. }
      FAvatarUrl := '';
      FAvatar := '';
    end;
    FMine := Job.Mine;
    FReview := Job.Review;
  end
  else if FRestored then
  begin
    { The kept user is not shown as the forge's when the forge could not
      say who it is; the file stays for the next start. }
    FLogin := '';
    FAvatarUrl := '';
    FAvatar := '';
  end;
  FRestored := False;
  UpdatePage;
  if (OldLogin <> FLogin) or (OldAvatar <> FAvatar) or (OldAvatarUrl <> FAvatarUrl) then
  begin
    { Kept for the next start (LoadPicture), a write that fails left at
      that; gone when the forge gives no picture any more. }
    if (FLogin <> '') and (FAvatar <> '') then
      SaveForgePicture(App.Settings.ForgePictureFile, ForgeName, FLogin, FAvatarUrl, FAvatar)
    else if (FAvatar = '') and (FError = '') then
      DeleteFile(App.Settings.ForgePictureFile);
    UserChanged;
  end;
end;

procedure TForgeView.FreeJobsAsync(Data: PtrInt);
begin
  FZombies.FreeFinished(False);
end;

{ A card: the window compares with the pull request in a frame that has
  a remote for its repository, else in its clone when it is still there;
  when neither, the pull request opens on the forge. }
procedure TForgeView.PagePick(Sender: TObject; const APull: TGittanForgePull);
var
  Clone: string;
begin
  Clone := APull.Clone;
  if (Clone <> '') and not DirectoryExists(Clone) then
    Clone := '';
  if not FWindow.ComparePullRequest(PullRequestOf(APull), Clone) and (APull.Url <> '') then
    OpenURL(APull.Url);
end;

{ A right click on a card: compare with the pull request (what a click
  does), open it on the forge, copy its link, and on the forge, while
  it is open: approve it, request changes or comment, merge it (with a
  merge commit, squashed or rebased), or mark a draft ready for review;
  the same the Pull Requests page of a repository offers, with the
  same questions (AskPullAction in umain). The forge does it in a
  thread; when it is done the view asks for the pull requests again,
  and a failure shows the tool's words. One action runs at a time. }
procedure TForgeView.PageContext(Sender: TObject; const APull: TGittanForgePull;
  const AScreenPos: TPoint);
begin
  FActionPull := APull;
  FillPullCardMenu(FCardPopup, PullRequestOf(APull), ForgeName, ActsNow, @CardMenuClick);
  FCardPopup.PopUp(AScreenPos.X, AScreenPos.Y);
end;

procedure TForgeView.CardMenuClick(Sender: TObject);
var
  Picked: TGittanPullAction;
begin
  case (Sender as TMenuItem).Tag of
    pcCompare: PagePick(Sender, FActionPull);
    pcOpen: if FActionPull.Url <> '' then
        OpenURL(FActionPull.Url);
    pcCopy: Clipboard.AsText := FActionPull.Url;
    else
      if PullCardAction((Sender as TMenuItem).Tag, Picked) then
        StartAction(FActionPull, Picked);
  end;
end;

function TForgeView.ActsNow: boolean;
begin
  Result := Assigned(FForge) and FForge.HasPullActions and (FActionJob = nil);
end;

procedure TForgeView.StartAction(const APull: TGittanForgePull; AAction: TGittanPullAction);
var
  Words: string;
begin
  if not ActsNow or not PullActionFits(PullRequestOf(APull), AAction) or
    not AskPullAction(PullRequestOf(APull), AAction, Words) then
    Exit;
  FActionJob := FForge.ActionJob(GetUserDir, APull.Repo, APull.Number, AAction, Words);
  if FActionJob = nil then
    Exit;
  FActionJob.OnDone := @ActionDone;
  FActionJob.Start;
  Screen.Cursor := crAppStart;
end;

procedure TForgeView.ActionDone(Sender: TObject);
var
  Job: TGittanPullActionJob;
begin
  Job := TGittanPullActionJob(Sender);
  if Job <> FActionJob then
    Exit;
  FActionJob := nil;
  Screen.Cursor := crDefault;
  FZombies.Add(Job);
  Application.QueueAsyncCall(@FreeJobsAsync, 0);
  if not Job.Ok then
    TellDlg(Format(rsPullActionFailed, [ForgeName]), Job.Error, mtError);
  { The lists as they are now. }
  AbandonJob;
  StartJob;
end;

procedure TForgeView.AbandonAction;
begin
  if FActionJob = nil then
    Exit;
  FActionJob.Stop(False);
  FZombies.Add(FActionJob);
  FActionJob := nil;
end;

procedure TForgeView.PageRefresh(Sender: TObject);
begin
  StartJob;
end;

{ The forge's filters and presets with the user's own presets after
  them, the filters on, the checks ignored, what needs attention and
  the orders from the settings; the forge's values are kept under its
  name (ForgeValue), the standard ones shown while there is no forge. }
procedure TForgeView.LoadFilters;
var
  Reasons: TGittanAttentionReasons;
  Presets, Own: TGittanForgePresets;
  Ignored: TStringList;
  FName: string;
  i, n: integer;
begin
  FName := ForgeName;
  if Assigned(FForge) then
  begin
    Presets := TGittanForgeClass(FForge.ClassType).Presets;
    Own := ParsePresets(App.Settings.ForgeValue(FName, 'Presets'));
    n := Length(Presets);
    SetLength(Presets, n + Length(Own));
    for i := 0 to High(Own) do
      Presets[n + i] := Own[i];
    FPage.SetFilters(TGittanForgeClass(FForge.ClassType).Filters, Presets);
  end
  else
    FPage.SetFilters(StandardFilters, StandardPresets);
  FPage.MineFilters := App.Settings.ForgeValue(FName, 'MineFilters');
  FPage.ReviewFilters := App.Settings.ForgeValue(FName, 'ReviewFilters');
  Ignored := TStringList.Create;
  try
    SplitCheckNames(App.Settings.ForgeValue(FName, 'IgnoredChecks'), Ignored);
    FPage.IgnoredChecks := Ignored;
  finally
    Ignored.Free;
  end;
  Reasons := [];
  if App.Settings.ChangesNeedAttention then
    Include(Reasons, arChangesRequested);
  if App.Settings.ChecksNeedAttention then
    Include(Reasons, arChecksFailing);
  FPage.AttentionReasons := Reasons;
  FPage.MineOrder := TGittanPullOrder(App.Settings.MineOrder);
  FPage.ReviewOrder := TGittanPullOrder(App.Settings.ReviewOrder);
end;

{ A chip or the page's menu: the settings keep it, and the page's new
  height. }
procedure TForgeView.PageFilterChange(Sender: TObject);
var
  FName: string;
begin
  FName := ForgeName;
  if FName <> '' then
  begin
    App.Settings.SetForgeValue(FName, 'MineFilters', FPage.MineFilters);
    App.Settings.SetForgeValue(FName, 'ReviewFilters', FPage.ReviewFilters);
    App.Settings.SetForgeValue(FName, 'IgnoredChecks', JoinCheckNames(FPage.IgnoredChecks));
    App.Settings.SetForgeValue(FName, 'Presets', JoinPresets(FPage.Presets));
  end;
  App.Settings.ChangesNeedAttention := arChangesRequested in FPage.AttentionReasons;
  App.Settings.ChecksNeedAttention := arChecksFailing in FPage.AttentionReasons;
  App.Settings.MineOrder := Ord(FPage.MineOrder);
  App.Settings.ReviewOrder := Ord(FPage.ReviewOrder);
  FPage.FitHeight(FBox.ClientHeight);
end;

{ Save as preset: the name asked, the preset made of the filters on. }
procedure TForgeView.PageSavePreset(Sender: TObject);
var
  Given: string;
begin
  Given := '';
  if AskText(rsSavePresetTitle, rsSavePresetPrompt, Given) and (PresetName(Given) <> '') then
    FPage.AddPreset(Given);
end;

procedure TForgeView.PageOpenUrl(Sender: TObject; const AUrl: string);

begin
  OpenURL(AUrl);
end;

procedure TForgeView.MenuNewTabClick(Sender: TObject);
begin
  FWindow.NewTab;
end;

procedure TForgeView.MenuOpenRepoClick(Sender: TObject);
begin
  FWindow.AskOpenRepository;
end;

procedure TForgeView.MenuRecentClick(Sender: TObject);
begin
  FWindow.OpenRepository(TMenuItem(Sender).Hint);
end;

procedure TForgeView.MenuCloseClick(Sender: TObject);
begin
  FWindow.HideForgeView;
end;

procedure TForgeView.MenuRefreshClick(Sender: TObject);
begin
  StartJob;
end;

procedure TForgeView.MenuNextTabClick(Sender: TObject);
begin
  StepTab(1);
end;

procedure TForgeView.MenuPrevTabClick(Sender: TObject);
begin
  StepTab(-1);
end;

procedure TForgeView.MenuCheckUpdatesClick(Sender: TObject);
begin
  App.CheckForUpdate(True);
end;

procedure TForgeView.MenuSettingsClick(Sender: TObject);
begin
  FWindow.ShowSettings;
end;

procedure TForgeView.MenuAboutClick(Sender: TObject);
begin
  FWindow.ShowAbout;
end;

end.
