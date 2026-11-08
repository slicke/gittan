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
  settings, BatchRepos): an overview of what is left undone in each,
  read as it is shown and on Check, a card's head opening that
  repository; the identity check, who each commits as and whether it
  signs, read the same way; Maintenance, which scans for a remote's
  HEAD left behind, worktrees whose folder is gone and objects to pack
  and runs the tasks picked; and Gone branches, deleting the branches deleted on the remote, which
  the view scans for and deletes, asking first, all in jobs of its own
  (gittan.batch); one operation shown at a time, its pill kept in the
  settings (BatchOperation),
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

  The extensions reach the view too (spec/extensions.md): their tabs
  after Batch (Gittan.forgeTabs.register, shown in gittan.extpage, each
  rendered as it is shown and on Refresh), their operations in the
  Batch tab after Gittan's own (Gittan.batch.register, called once per
  picked repository in turn: RunExtStep), and their commands for the
  forge view in an Extensions menu (where: "forge"); a tab and a command
  only of the extensions whose @forges has the view's forge. A tab's or
  an operation's answer comes back through the window
  (TRepoWindow.ExtDeliver) by the request's number (NextExtSeq).

  The view has a menu of its own (MainMenu, with AppMenuItem for the
  application menu on macOS), the few items that mean something without
  a repository: New Tab, Open Repository..., Open Recent, Close GitHub,
  Refresh, the tabs, Extensions, Settings..., Check for Updates... and About; the
  global ones go through TRepoWindow, which runs them in the repository
  frame shown under the view. The window sets the menu, the caption and
  the title bar when it shows the view (Shown) and gives the frame's
  back when it hides it (Hidden). See spec/github.md. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Menus, ExtCtrls, Graphics, LCLType, Dialogs,
  Clipbrd, gittan.job, gittan.forge, gittan.forgepage, gittan.batch, gittan.batchpage,
  gittan.askdlg, gittan.extpage, gittan.ext.registry, gittan.banner, fpjson, umain;

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
    FStatusJob: TGittanStatusJob;
    FIdentityJob: TGittanIdentityJob;
    FMaintScanJob: TGittanMaintScanJob;
    FMaintRunJob: TGittanMaintRunJob;
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
    { How many more of each the forge has than it listed. }
    FMineLeft, FReviewLeft: integer;
    FMainMenu: TMainMenu;
    FAppMenuItem: TMenuItem;
    FRecentMenu, FCloseItem: TMenuItem;
    FDark: boolean;
    { The extensions: the tabs of those that run for the forge, the one
      shown (-1 for none), the request it waits for (0 for none), whether
      that is an action, and the context its function was in, so a reload
      asks again; the Extensions menu; the run of a Batch operation, its
      repositories and the one it is at. }
    FExtPage: TGittanExtTabPage;
    FExtTabs: TGittanExtCommands;
    FExtTab, FExtTabSeq: integer;
    FExtTabActing: boolean;
    { Asked for while an action ran (Refresh, the view shown again): the
      tab renders when the action's answer is in, so that answer is
      still taken. }
    FExtTabRenderAfter: boolean;
    { The account changed while a tab was shown: its rows were the old
      account's, asked again once the job says who is logged in now. }
    FExtTabStale: boolean;
    { The generation of the context its function was in (the engine's
      GenerationForContext), not the context's address, which a context
      made on a reload may get again. }
    FExtTabGen: QWord;
    FExtMenu: TMenuItem;
    FExtQueued, FIsShown: boolean;
    FExtRunKey, FExtRunExt: string;
    FExtRunGen: QWord;
    FExtRunPaths, FExtRunCaptions: TStringArray;
    FExtRunIndex, FExtRunSeq: integer;
    FThemeTimer: TTimer;
    { Asks the forge again now and then, shown or not, so the globe's
      count follows. }
    FPollTimer: TTimer;
    { What an action on a pull request did, or the forge's words when
      it failed, over the page. }
    FBanner: TGittanBanner;
    FOnTabsChange, FOnUserChange: TNotifyEvent;
    procedure PollTimerTimer(Sender: TObject);
    procedure BannerChange(Sender: TObject);
    procedure ApplyForgeState;
    function TabOffset: integer;
    function InnerTab: integer;
    procedure SelectInner(AIndex: integer);
    function PageWhere(Sender: TObject; const APull: TGittanForgePull): TGittanPickTarget;
    procedure PageMerge(Sender: TObject; const APull: TGittanForgePull;
      const AScreenPos: TPoint);
    procedure BatchNotice(Sender: TObject);
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
    procedure BatchCheck(Sender: TObject);
    procedure BatchOperationChange(Sender: TObject);
    procedure CheckProgress(Sender: TObject);
    procedure CheckDone(Sender: TObject);
    procedure IdentityCheck;
    procedure IdentityProgress(Sender: TObject);
    procedure IdentityDone(Sender: TObject);
    procedure BatchMaintScan(Sender: TObject);
    procedure MaintScanProgress(Sender: TObject);
    procedure MaintScanDone(Sender: TObject);
    procedure BatchMaintRun(Sender: TObject);
    procedure MaintRunProgress(Sender: TObject);
    procedure MaintRunDone(Sender: TObject);
    procedure BatchOpen(Sender: TObject; const APath: string);
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
    procedure PageLogIn(Sender: TObject);
    procedure PageHostingSettings(Sender: TObject);
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
    procedure MenuFindClick(Sender: TObject);
    procedure MenuNextTabClick(Sender: TObject);
    procedure MenuPrevTabClick(Sender: TObject);
    procedure MenuCheckUpdatesClick(Sender: TObject);
    procedure MenuSettingsClick(Sender: TObject);
    procedure MenuAboutClick(Sender: TObject);
    function CurrentTab: integer;
    function ExtContext: TJSONObject;
    procedure RebuildExt;
    procedure RebuildExtAsync(Data: PtrInt);
    procedure ShowExtTab;
    procedure RenderExtTab;
    { RenderExtTab, or once the running action's answer is in. }
    procedure RenderExtTabSoon;
    procedure RenderExtTabAsync(Data: PtrInt);
    procedure ExtTabRefresh(Sender: TObject);
    procedure ExtTabAction(Sender: TObject; ARow: integer; const AAction: string);
    procedure ExtTabOpenUrl(Sender: TObject; const ATarget: string);
    procedure ExtTabOpenRepo(Sender: TObject; const ATarget: string);
    procedure ExtTabAnswer(const AJson: string);
    procedure BatchExtRun(Sender: TObject);
    procedure BatchOpenUrl(Sender: TObject; const APath: string);
    procedure RunExtStep;
    procedure RunExtStepAsync(Data: PtrInt);
    procedure FinishExtRun(const AError: string);
    procedure ExtCommandClick(Sender: TObject);
    procedure MenuExtReloadClick(Sender: TObject);
    procedure MenuExtFolderClick(Sender: TObject);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** Builds the view, once it is placed in AWindow, which it then
      asks for what needs a repository or the window (FWindow). }
    procedure Init(AWindow: TRepoWindow);
    {** Whether there is a forge. Without one the view has the Batch
      tab (and the extensions' tabs) alone, with a note that a hosting
      service would bring the pull requests. }
    function HasForge: boolean;
    {** The forge's name, '' without one. }
    function ForgeName: string;
    {** The view's name, for the window's caption and Close: the
      forge's, else Batch's. }
    function Title: string;
    {** The pull requests waiting for the user's review, which the
      globe counts. }
    function ReviewCount: integer;
    {** What the chrome's globe says of the forge: its name, with the
      login before it once the forge has said who ("octocat on GitHub"). }
    function ChromeHint: string;
    {** The user's login as the forge last gave it, '' before it has. }
    property Login: string read FLogin;
    {** The bytes of the user's picture (PNG or JPEG) as the forge gave
      it, '' without one, for the chrome's globe. }
    property Picture: string read FAvatar;
    {** The user changed: the login or the picture came, changed or went,
      or the count of pull requests waiting for their review changed, so
      the chrome's globe follows. }
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
    {** The settings dialog was closed with OK: the filters and what
      needs attention as the settings have them now. }
    procedure ReloadFilters;
    {** The active account of the forge's tool changed: what the account
      of before had found goes, and the view asks again. }
    procedure AccountChanged;
    {** The view's tabs, which the window's tab strip shows while the
      view is shown: their names in ACaptions, their tooltips in AHints
      (the extension behind an extension's tab), in AMarks the ones with
      something to do (pull requests waiting for review), in AExts the
      ones an extension added; gives the shown one's index. }
    function Tabs(out ACaptions, AHints: TStringArray;
      out AMarks, AExts: TBooleanDynArray): integer;
    {** The commands, tabs and operations the extensions registered
      changed: the view's follow, from the message loop. }
    procedure ExtensionsChanged;
    {** What an extension's tab or operation answered for the request
      ASeq (gittan.ext.host's Deliver). }
    procedure ExtDeliver(ASeq: integer; const AExtId, AJson: string);
    {** How many tabs: the sections, then Batch, then the extensions'. }
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
  Math, LCLIntf, gittan.app, gittan.theme, gittan.textfit, gittan.git, gittan.ext.engine,
  gittan.ext.views, gittan.cli;

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
  rsFind = '&Find...';
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
  rsExtensions = 'E&xtensions';
  { Under an extension's tab or operation: the extension's name. }
  rsFromExtension = 'From the extension %s';
  rsReloadExtensions = 'Reload Extensions';
  rsOpenExtensionsFolder = 'Open Extensions Folder';
  rsExtTabGone = 'The extension no longer has this tab.';
  rsExtRunGone = 'The extension no longer has this operation.';
  rsExtReloaded = 'The extensions were loaded again, which stopped the run.';
  rsExtAccountChanged = 'The account changed, which stopped the run.';
  { Without a hosting service: the globe's hint and Batch's note. }
  rsNoForgeHint = 'Batch: work in several repositories at once';
  rsNoForgeNote = 'Connect a hosting service such as GitHub to see your pull requests ' +
    'and the ones waiting for your review here as well.';
  rsNoForgeLink = 'Hosting Settings…';
  { The minutes between two looks at the forge. }


const
  { The minutes between two looks at the forge, and the seconds a
    success stays in the banner. }
  ForgePollMinutes = 5;
  BannerSeconds = 8;

var
  { The number of the last request to an extension's tab or operation. }
  ExtSeq: integer = 0;

{ The name of the extension behind ACmd: its @name, else its file's id. }
function ExtNameOf(const ACmd: TGittanExtCommand): string;
var
  Eng: TGittanExtEngine;
begin
  Result := ACmd.ExtId;
  Eng := TGittanExtEngine.Existing;
  if (Eng <> nil) and (Eng.ExtensionNameForContext(ACmd.Ctx) <> '') then
    Result := Eng.ExtensionNameForContext(ACmd.Ctx);
end;

function NextExtSeq: integer;
begin
  Inc(ExtSeq);
  if ExtSeq <= 0 then
    ExtSeq := 1;
  Result := ExtSeq;
end;

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
  if FPollTimer <> nil then
    FPollTimer.Enabled := False;
  AbandonJob;
  AbandonAction;
  { A scan is given up; a deletion runs to its end. }
  if FScanJob <> nil then
  begin
    FScanJob.Stop(False);
    FZombies.Add(FScanJob);
    FScanJob := nil;
  end;
  if FStatusJob <> nil then
  begin
    FStatusJob.Stop(False);
    FZombies.Add(FStatusJob);
    FStatusJob := nil;
  end;
  if FIdentityJob <> nil then
  begin
    FIdentityJob.Stop(False);
    FZombies.Add(FIdentityJob);
    FIdentityJob := nil;
  end;
  if FMaintScanJob <> nil then
  begin
    FMaintScanJob.Stop(False);
    FZombies.Add(FMaintScanJob);
    FMaintScanJob := nil;
  end;
  { A run of maintenance, as a deletion, runs to its end. }
  if FMaintRunJob <> nil then
  begin
    FMaintRunJob.Stop(False);
    FZombies.Add(FMaintRunJob);
    FMaintRunJob := nil;
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
  FBanner := TGittanBanner.Create(Self);
  FBanner.Align := alTop;
  FBanner.Visible := False;
  FBanner.BorderSpacing.Top := AWindow.TitleBarHeight;
  FBanner.OnChange := @BannerChange;
  FBanner.Parent := Self;
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
  FPage.OnMerge := @PageMerge;
  FPage.OnWhere := @PageWhere;
  FCardPopup := TPopupMenu.Create(Self);
  FPage.OnRefresh := @PageRefresh;
  FPage.OnLogIn := @PageLogIn;
  FPage.OnHostingSettings := @PageHostingSettings;
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
  FBatch.OnCheck := @BatchCheck;
  FBatch.OperationKey := App.Settings.BatchOperation;
  FBatch.OnOperationChange := @BatchOperationChange;
  FBatch.OnOpen := @BatchOpen;
  FBatch.OnMaintScan := @BatchMaintScan;
  FBatch.OnMaintRun := @BatchMaintRun;
  FBatch.OnExtRun := @BatchExtRun;
  FBatch.OnOpenUrl := @BatchOpenUrl;
  FBatch.OnNotice := @BatchNotice;
  FExtTab := -1;
  FExtPage := TGittanExtTabPage.Create(Self);
  FExtPage.Visible := False;
  FExtPage.Parent := FBox;
  FExtPage.OnRefresh := @ExtTabRefresh;
  FExtPage.OnAction := @ExtTabAction;
  FExtPage.OnOpenUrl := @ExtTabOpenUrl;
  FExtPage.OnOpenRepo := @ExtTabOpenRepo;
  FThemeTimer := TTimer.Create(Self);
  FThemeTimer.Interval := 2000;
  FThemeTimer.Enabled := False;
  FThemeTimer.OnTimer := @ThemeTimerTimer;
  FPollTimer := TTimer.Create(Self);
  FPollTimer.Interval := ForgePollMinutes * 60 * 1000;
  FPollTimer.Enabled := False;
  FPollTimer.OnTimer := @PollTimerTimer;
  FDark := IsDarkMode;
  ApplyTheme;
  FindForge;
  ApplyForgeState;
  { The picture kept from the last start, then the forge asked once at
    start, so the chrome's globe has the user and the view its lists
    before it is first shown. }
  LoadPicture;
  StartJob;
  BuildMenu;
  RebuildExt;
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
    FCloseItem.Caption := Format(rsCloseForge, [Title]);
end;

{ With a forge the page's sections are tabs and Batch says nothing of
  it; without one Batch stands alone with its note, shown in the page's
  place when a section was, and nothing is asked. }
procedure TForgeView.ApplyForgeState;
begin
  if HasForge then
    FBatch.SetNotice('', '')
  else
  begin
    FBatch.SetNotice(rsNoForgeNote, rsNoForgeLink);
    FPollTimer.Enabled := False;
    if not FBatchShown and (FExtTab < 0) then
    begin
      FBatchShown := True;
      FPage.Visible := False;
      if FIsShown then
        ShowBatch
      else
        FBatch.Visible := True;
    end;
  end;
  if FBatch.Visible then
    FBatch.FitHeight(FBox.ClientHeight);
end;

procedure TForgeView.BatchNotice(Sender: TObject);
begin
  FWindow.ShowHostingSettings;
end;

function TForgeView.Title: string;
begin
  Result := ForgeName;
  if Result = '' then
    Result := rsBatchTab;
end;

function TForgeView.ReviewCount: integer;
begin
  Result := Length(FReview);
end;

procedure TForgeView.PollTimerTimer(Sender: TObject);
begin
  StartJob;
end;

{ The banner takes the strip's height over it while shown, so the box
  under it does not leave a gap; the box takes it back when it goes. }
procedure TForgeView.BannerChange(Sender: TObject);
begin
  DisableAlign;
  try
    if FBanner.Visible then
    begin
      FBanner.BorderSpacing.Top := FWindow.TitleBarHeight;
      FBanner.Top := 0;
      FBox.BorderSpacing.Top := 0;
    end
    else
      FBox.BorderSpacing.Top := FWindow.TitleBarHeight;
  finally
    EnableAlign;
  end;
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
  if Result = '' then
    Result := rsNoForgeHint
  else if FLogin <> '' then
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
  FCloseItem := AddItem(FileMenu, Format(rsCloseForge, [Title]),
    ShortCut(VK_W, [ssModifier]), @MenuCloseClick);

  ViewMenu := TMenuItem.Create(FMainMenu);
  ViewMenu.Caption := rsView;
  FMainMenu.Items.Add(ViewMenu);
  AddItem(ViewMenu, rsRefresh, ShortCut(VK_R, [ssModifier]), @MenuRefreshClick);
  AddItem(ViewMenu, rsFind, ShortCut(VK_F, [ssModifier]), @MenuFindClick);

  GoMenu := TMenuItem.Create(FMainMenu);
  GoMenu.Caption := rsGo;
  FMainMenu.Items.Add(GoMenu);
  AddItem(GoMenu, rsNextTab, ShortCut(VK_OEM_6, [ssModifier, ssShift]), @MenuNextTabClick);
  AddItem(GoMenu, rsPrevTab, ShortCut(VK_OEM_4, [ssModifier, ssShift]), @MenuPrevTabClick);

  { Built by RebuildExt. }
  FExtMenu := TMenuItem.Create(FMainMenu);
  FExtMenu.Caption := rsExtensions;

  ToolsMenu := TMenuItem.Create(FMainMenu);
  ToolsMenu.Caption := rsTools;
  FMainMenu.Items.Add(ToolsMenu);
  AddItem(ToolsMenu, rsCheckUpdates, 0, @MenuCheckUpdatesClick);
  {$IFNDEF LCLCocoa}
  ToolsMenu.Add(NewLine);
  AddItem(ToolsMenu, rsSettings, ShortCut(VK_OEM_COMMA, [ssModifier]), @MenuSettingsClick);
  AddItem(ToolsMenu, rsAbout, 0, @MenuAboutClick);
  {$ENDIF}
  { After Tools, as a repository's. }
  FMainMenu.Items.Add(FExtMenu);
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
  FExtPage.SetTheme(FDark);
  with ForgePalette(FDark) do
    FBanner.SetColors(Card, Text, Dim, Hover, Line, Link, Error, Ok);
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
  FIsShown := True;
  { The extension's tab asked again, as the forge is. }
  if FExtTab >= 0 then
    ShowExtTab;
  FBox.VertScrollBar.Position := 0;
  FThemeTimer.Enabled := True;
end;

procedure TForgeView.Hidden;
begin
  FIsShown := False;
  FThemeTimer.Enabled := False;
end;

procedure TForgeView.SettingsChanged;
begin
  if FindForge then
  begin
    ForgetAnswers;
    { The extensions' tabs and commands are those of the forge. }
    RebuildExt;
  end;
  ApplyForgeState;
  if Assigned(FOnTabsChange) then
    FOnTabsChange(Self);
end;

procedure TForgeView.ReloadFilters;
begin
  LoadFilters;
  FPage.FitHeight(FBox.ClientHeight);
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
  FMineLeft := 0;
  FReviewLeft := 0;
  FLogin := '';
  FAvatarUrl := '';
  FAvatar := '';
  FPictureFresh := False;
  FRestored := False;
  FError := '';
  FPage.ForgetAnswer;
  { An extension's tab keeps nothing of the old account: an answer
    still to come is not taken, the rows go so no action of theirs runs
    as the new account, and it is asked again when the job is done. }
  if FExtTab >= 0 then
  begin
    FExtTabSeq := 0;
    FExtTabActing := False;
    FExtTabRenderAfter := False;
    FExtTabStale := True;
    FExtPage.SetModel(Default(TExtTabModel));
    FExtPage.SetBusy(True, False);
    if FExtPage.Visible then
      FExtPage.FitHeight(FBox.ClientHeight);
  end;
  { A Batch operation's run stops: its next steps would run the forge's
    tool as the new account. FinishExtRun drops its seq, so an answer
    still to come is not taken. }
  if FExtRunKey <> '' then
    FinishExtRun(rsExtAccountChanged);
  { The job first, as in Shown. }
  StartJob;
  { Without a forge no job runs to render the tab again (JobDone), and
    it would wait for one for ever. }
  if not Assigned(FForge) and FExtTabStale then
  begin
    FExtTabStale := False;
    if FExtPage.Visible then
      RenderExtTabSoon;
  end;
  UpdatePage;
  UserChanged;
end;

procedure TForgeView.FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
var
  R: TRect;
begin
  { The keys of the page's cards and its search, while it is shown. }
  if FPage.Visible and (Shift * [ssCtrl, ssAlt, ssMeta] = []) then
    case Key of
      VK_ESCAPE:
        if FPage.SearchText <> '' then
        begin
          FPage.ClearSearch;
          Key := 0;
          Exit;
        end
        else if FPage.SearchFocused then
        begin
          FBox.SetFocus;
          Key := 0;
          Exit;
        end;
      VK_UP, VK_DOWN:
      begin
        if Key = VK_UP then
          FPage.MoveSelection(-1)
        else
          FPage.MoveSelection(1);
        { The ringed card in view. }
        if FPage.SelectedRect(R) then
          with FBox.VertScrollBar do
            if R.Top < Position then
              Position := Max(0, R.Top - Px(8))
            else if R.Bottom > Position + FBox.ClientHeight then
              Position := R.Bottom - FBox.ClientHeight + Px(8);
        Key := 0;
        Exit;
      end;
      VK_RETURN:
        if FPage.PickSelected then
        begin
          Key := 0;
          Exit;
        end;
      VK_APPS:
        if FPage.ContextSelected then
        begin
          Key := 0;
          Exit;
        end;
    end;
  if (Key = VK_ESCAPE) and (Shift = []) then
  begin
    Key := 0;
    FWindow.HideForgeView;
  end;
end;

procedure TForgeView.MenuFindClick(Sender: TObject);
begin
  if FPage.Visible then
    FPage.FocusSearch;
end;

{ What the job last read, to the page, and whether one runs. }
procedure TForgeView.UpdatePage;
begin
  FPage.CanAct := ActsNow;
  FPage.SetLogin(FLogin);
  FPage.SetAvatar(FAvatar);
  FPage.SetLeft(FMineLeft, FReviewLeft);
  if Assigned(FForge) and (FError <> '') and FForge.NeedsLogin(FError) and
    (FForge.LoginArgs <> '') then
    FPage.LoginCommand := FForge.CliName + ' ' + FForge.LoginArgs
  else
    FPage.LoginCommand := '';
  FPage.SetPulls(FMine, FReview, FError, FJob <> nil);
  FPage.FitHeight(FBox.ClientHeight);
  if Assigned(FOnTabsChange) then
    FOnTabsChange(Self);
end;

function TForgeView.Tabs(out ACaptions, AHints: TStringArray;
  out AMarks, AExts: TBooleanDynArray): integer;
var
  i: integer;
begin
  ACaptions := nil;
  AHints := nil;
  AMarks := nil;
  AExts := nil;
  SetLength(ACaptions, TabCount);
  SetLength(AHints, TabCount);
  SetLength(AMarks, TabCount);
  SetLength(AExts, TabCount);
  { The sections only with a forge (TabOffset). }
  if HasForge then
  begin
    for i := 0 to SectionCount - 1 do
      ACaptions[i] := SectionCaption(i);
    AMarks[Ord(fsReview)] := Length(FReview) > 0;
  end;
  ACaptions[BatchTab - TabOffset] := rsBatchTab;
  for i := 0 to High(FExtTabs) do
  begin
    ACaptions[BatchTab + 1 + i - TabOffset] := FExtTabs[i].Title;
    AHints[BatchTab + 1 + i - TabOffset] := Format(rsFromExtension, [ExtNameOf(FExtTabs[i])]);
    AExts[BatchTab + 1 + i - TabOffset] := True;
  end;
  Result := CurrentTab;
end;

{ The tabs the strip shows leave the sections out without a forge: the
  strip's index plus this is the view's own (InnerTab, SelectInner). }
function TForgeView.TabOffset: integer;
begin
  if HasForge then
    Result := 0
  else
    Result := SectionCount;
end;

function TForgeView.TabCount: integer;
begin
  Result := SectionCount + 1 + Length(FExtTabs) - TabOffset;
end;

function TForgeView.CurrentTab: integer;
begin
  Result := InnerTab - TabOffset;
end;

procedure TForgeView.SelectTab(AIndex: integer);
begin
  if (AIndex < 0) or (AIndex >= TabCount) then
    Exit;
  SelectInner(AIndex + TabOffset);
end;

function TForgeView.InnerTab: integer;
begin
  if FExtTab >= 0 then
    Result := BatchTab + 1 + FExtTab
  else if FBatchShown then
    Result := BatchTab
  else
    Result := FPage.Section;
end;

procedure TForgeView.SelectInner(AIndex: integer);
begin
  if (AIndex < TabOffset) or (AIndex >= TabCount + TabOffset) or (AIndex = InnerTab) then
    Exit;
  FExtTab := -1;
  FExtTabSeq := 0;
  FExtTabActing := False;
  FExtTabRenderAfter := False;
  FExtPage.Visible := False;
  if AIndex = BatchTab then
  begin
    FBatchShown := True;
    ShowBatch;
  end
  else if AIndex > BatchTab then
  begin
    FBatchShown := False;
    FExtTab := AIndex - BatchTab - 1;
    ShowExtTab;
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
begin
  SelectTab(((CurrentTab + ADelta) mod TabCount + TabCount) mod TabCount);
end;

procedure TForgeView.BoxResize(Sender: TObject);
begin
  FPage.FitHeight(FBox.ClientHeight);
  if FBatch.Visible then
    FBatch.FitHeight(FBox.ClientHeight);
  if FExtPage.Visible then
    FExtPage.FitHeight(FBox.ClientHeight);
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
  { The overview and the identity check are local and quick: read again
    each time they show. }
  if FBatch.Operation in [BatchOverview, BatchIdentity] then
    BatchCheck(Self);
end;

{ Another operation's pill: kept for the next start, and the overview or
  the identity check read again as it comes into view. }
procedure TForgeView.BatchOperationChange(Sender: TObject);
begin
  App.Settings.BatchOperation := FBatch.OperationKey;
  FBatch.FitHeight(FBox.ClientHeight);
  FBox.VertScrollBar.Position := 0;
  if FBatch.Operation in [BatchOverview, BatchIdentity] then
    BatchCheck(Self);
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

{ Check: what is left undone in the picked repositories, read in a job,
  the page showing each as it is done; one at a time. }
procedure TForgeView.BatchCheck(Sender: TObject);
var
  Paths, Captions: TStringArray;
begin
  if FBatch.Operation = BatchIdentity then
  begin
    IdentityCheck;
    Exit;
  end;
  if FStatusJob <> nil then
    Exit;
  FBatch.ChosenRepos(Paths, Captions);
  if Length(Paths) = 0 then
    Exit;
  FStatusJob := TGittanStatusJob.Create(Paths, Captions);
  FStatusJob.OnProgress := @CheckProgress;
  FStatusJob.OnDone := @CheckDone;
  FBatch.StartCheck(Length(Paths));
  FBatch.FitHeight(FBox.ClientHeight);
  FStatusJob.Start;
end;

procedure TForgeView.CheckProgress(Sender: TObject);
begin
  if Sender <> FStatusJob then
    Exit;
  FBatch.SetStatus(FStatusJob.Repos, FStatusJob.Finished, True);
  FBatch.FitHeight(FBox.ClientHeight);
end;

procedure TForgeView.CheckDone(Sender: TObject);
var
  Job: TGittanStatusJob;
begin
  Job := TGittanStatusJob(Sender);
  if Job <> FStatusJob then
    Exit;
  FStatusJob := nil;
  FZombies.Add(Job);
  Application.QueueAsyncCall(@FreeJobsAsync, 0);
  FBatch.SetStatus(Job.Repos, Job.Finished, False);
  FBatch.FitHeight(FBox.ClientHeight);
end;

{ The identity check of the picked repositories, as the overview's. }
procedure TForgeView.IdentityCheck;
var
  Paths, Captions: TStringArray;
begin
  if FIdentityJob <> nil then
    Exit;
  FBatch.ChosenRepos(Paths, Captions);
  if Length(Paths) = 0 then
    Exit;
  FIdentityJob := TGittanIdentityJob.Create(Paths, Captions);
  FIdentityJob.OnProgress := @IdentityProgress;
  FIdentityJob.OnDone := @IdentityDone;
  FBatch.StartIdentity(Length(Paths));
  FBatch.FitHeight(FBox.ClientHeight);
  FIdentityJob.Start;
end;

procedure TForgeView.IdentityProgress(Sender: TObject);
begin
  if Sender <> FIdentityJob then
    Exit;
  FBatch.SetIdentities(FIdentityJob.Repos, FIdentityJob.Finished, True);
  FBatch.FitHeight(FBox.ClientHeight);
end;

procedure TForgeView.IdentityDone(Sender: TObject);
var
  Job: TGittanIdentityJob;
begin
  Job := TGittanIdentityJob(Sender);
  if Job <> FIdentityJob then
    Exit;
  FIdentityJob := nil;
  FZombies.Add(Job);
  Application.QueueAsyncCall(@FreeJobsAsync, 0);
  FBatch.SetIdentities(Job.Repos, Job.Finished, False);
  FBatch.FitHeight(FBox.ClientHeight);
end;

{ Maintenance's scan of the picked repositories; one batch job that
  changes or fetches at a time (Busy). }
procedure TForgeView.BatchMaintScan(Sender: TObject);
var
  Paths, Captions: TStringArray;
begin
  if FBatch.Busy then
    Exit;
  FBatch.ChosenRepos(Paths, Captions);
  if Length(Paths) = 0 then
    Exit;
  FMaintScanJob := TGittanMaintScanJob.Create(Paths, Captions);
  FMaintScanJob.OnProgress := @MaintScanProgress;
  FMaintScanJob.OnDone := @MaintScanDone;
  FBatch.StartMaintScan(Length(Paths));
  FBatch.FitHeight(FBox.ClientHeight);
  FMaintScanJob.Start;
end;

procedure TForgeView.MaintScanProgress(Sender: TObject);
begin
  if Sender <> FMaintScanJob then
    Exit;
  FBatch.SetMaintScan(FMaintScanJob.Repos, FMaintScanJob.Finished, True);
  FBatch.FitHeight(FBox.ClientHeight);
end;

procedure TForgeView.MaintScanDone(Sender: TObject);
var
  Job: TGittanMaintScanJob;
begin
  Job := TGittanMaintScanJob(Sender);
  if Job <> FMaintScanJob then
    Exit;
  FMaintScanJob := nil;
  FZombies.Add(Job);
  Application.QueueAsyncCall(@FreeJobsAsync, 0);
  FBatch.SetMaintScan(Job.Repos, Job.Finished, False);
  FBatch.FitHeight(FBox.ClientHeight);
end;

{ Run: the tasks picked, without asking, since none of them loses
  anything (a worktree pruned is one whose folder is gone already). }
procedure TForgeView.BatchMaintRun(Sender: TObject);
var
  Refs: TGittanMaintRefs;
begin
  if FBatch.Busy then
    Exit;
  Refs := FBatch.PickedMaintRefs;
  if Length(Refs) = 0 then
    Exit;
  FMaintRunJob := TGittanMaintRunJob.Create(Refs);
  FMaintRunJob.OnProgress := @MaintRunProgress;
  FMaintRunJob.OnDone := @MaintRunDone;
  FBatch.SetMaintRunning(True);
  FMaintRunJob.Start;
end;

procedure TForgeView.MaintRunProgress(Sender: TObject);
begin
  if Sender <> FMaintRunJob then
    Exit;
  FBatch.ApplyMaintRun(FMaintRunJob.Refs, FMaintRunJob.Finished);
  FBatch.FitHeight(FBox.ClientHeight);
end;

procedure TForgeView.MaintRunDone(Sender: TObject);
var
  Job: TGittanMaintRunJob;
begin
  Job := TGittanMaintRunJob(Sender);
  if Job <> FMaintRunJob then
    Exit;
  FMaintRunJob := nil;
  FZombies.Add(Job);
  Application.QueueAsyncCall(@FreeJobsAsync, 0);
  FBatch.ApplyMaintRun(Job.Refs, Job.Finished);
  FBatch.SetMaintRunning(False);
  FBatch.FitHeight(FBox.ClientHeight);
end;

{ A card's head in the overview or a row of the identity check: the
  repository opens, which hides the
  view. }
procedure TForgeView.BatchOpen(Sender: TObject; const APath: string);
begin
  FWindow.OpenRepository(APath);
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
  OldCount: integer;
begin
  OldLogin := FLogin;
  OldAvatar := FAvatar;
  OldAvatarUrl := FAvatarUrl;
  OldCount := ReviewCount;
  Job := TGittanForgeJob(Sender);
  if Job <> FJob then
    Exit;
  FJob := nil;
  { The next look in a while, counted from this answer. }
  FPollTimer.Enabled := False;
  FPollTimer.Enabled := Assigned(FForge);
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
    FMineLeft := Job.MineLeft;
    FReviewLeft := Job.ReviewLeft;
  end
  else if FRestored or (Assigned(FForge) and FForge.NeedsLogin(FError)) then
  begin
    { The kept user is not shown as the forge's when the forge could not
      say who it is, nor the old one when it is logged out, with their
      pull requests and the count of those waiting; the file stays for
      the next start. }
    FLogin := '';
    FAvatarUrl := '';
    FAvatar := '';
    FMine := nil;
    FReview := nil;
    FMineLeft := 0;
    FReviewLeft := 0;
  end;
  FRestored := False;
  UpdatePage;
  { Asked again when it was the old account's, or when it was rendered
    while the job had not yet said who is logged in. }
  if FExtTabStale or (OldLogin <> FLogin) then
  begin
    FExtTabStale := False;
    if FExtPage.Visible then
      RenderExtTabSoon;
  end;
  if (OldLogin <> FLogin) or (OldAvatar <> FAvatar) or (OldAvatarUrl <> FAvatarUrl) then
  begin
    { Kept for the next start (LoadPicture), a write that fails left at
      that; gone when the forge gives no picture any more. }
    if (FLogin <> '') and (FAvatar <> '') then
      SaveForgePicture(App.Settings.ForgePictureFile, ForgeName, FLogin, FAvatarUrl, FAvatar)
    else if (FAvatar = '') and (FError = '') then
      DeleteFile(App.Settings.ForgePictureFile);
    UserChanged;
  end
  else if ReviewCount <> OldCount then
    UserChanged;
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
  FillPullCardMenu(FCardPopup, PullRequestOf(APull), ForgeName, FLogin, ActsNow,
    @CardMenuClick);
  FCardPopup.PopUp(AScreenPos.X, AScreenPos.Y);
end;

{ A card's Merge button: the ways to merge, under it. }
procedure TForgeView.PageMerge(Sender: TObject; const APull: TGittanForgePull;
  const AScreenPos: TPoint);
begin
  FActionPull := APull;
  FillPullMergeMenu(FCardPopup, PullRequestOf(APull), ActsNow, @CardMenuClick);
  if FCardPopup.Items.Count > 0 then
    FCardPopup.PopUp(AScreenPos.X, AScreenPos.Y);
end;

{ Where PagePick goes, for the card's tooltip and its Review button. }
function TForgeView.PageWhere(Sender: TObject; const APull: TGittanForgePull): TGittanPickTarget;
begin
  if FWindow.HasFrameFor(APull.Repo) then
    Result := ptCompare
  else if (APull.Clone <> '') and DirectoryExists(APull.Clone) then
    Result := ptClone
  else
    Result := ptForge;
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
  if not ActsNow or not PullActionFits(PullRequestOf(APull), AAction, FLogin) or
    not AskPullAction(PullRequestOf(APull), AAction, Words) then
    Exit;
  FActionJob := FForge.ActionJob(GetUserDir, APull.Repo, APull.Number, AAction, Words);
  if FActionJob = nil then
    Exit;
  FActionJob.OnDone := @ActionDone;
  FActionJob.Start;
  Screen.Cursor := crAppStart;
  UpdatePage;
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
  { In the banner, as a repository's page has it: what was done, or
    the forge's words. }
  if Job.Ok then
    FBanner.Add(Format(rsPullActionDone, [PullActionDone(Job.Action), Job.Number]), '',
      bkSuccess, BannerSeconds)
  else
    FBanner.Add(Format(rsPullActionFailed, [ForgeName]), Job.Error, bkError);
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

{ The forge's tool logs in in a terminal, as it asks; Refresh, or the
  next look, reads the lists with the account. Its path quoted for the
  shell the terminal runs: cmd.exe's double quotes on Windows. }
procedure TForgeView.PageLogIn(Sender: TObject);
var
  Tool: string;
begin
  if not Assigned(FForge) or (FForge.LoginArgs = '') then
    Exit;
  {$IFDEF WINDOWS}
  Tool := '"' + FForge.Cli + '"';
  {$ELSE}
  Tool := ShellQuote(FForge.Cli);
  {$ENDIF}
  FWindow.RunInTerminal(Tool + ' ' + FForge.LoginArgs);
end;

procedure TForgeView.PageHostingSettings(Sender: TObject);
begin
  FWindow.ShowHostingSettings;
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
  if FExtTab >= 0 then
    RenderExtTabSoon;
end;

{ ---------------------------------------------------------------------------
  The extensions
  --------------------------------------------------------------------------- }

procedure TForgeView.ExtensionsChanged;
begin
  if FExtQueued then
    Exit;
  FExtQueued := True;
  Application.QueueAsyncCall(@RebuildExtAsync, 0);
end;

procedure TForgeView.RebuildExtAsync(Data: PtrInt);
begin
  FExtQueued := False;
  RebuildExt;
end;

{ What every request to an extension gets: the forge and the login. }
function TForgeView.ExtContext: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('forge', ForgeName);
  Result.Add('login', FLogin);
end;

{ The Extensions menu, the tabs and the Batch operations from the
  registry: a command and a tab only of an extension whose @forges has
  the view's forge; an operation of every extension, as its @forges is
  asked of each repository it runs on. A tab or a run whose extension
  was loaded again (another context) is asked again or stopped, since
  the function it waits for is gone. }
procedure TForgeView.RebuildExt;
var
  Eng: TGittanExtEngine;
  Cmd: TGittanExtCommand;
  Item: TMenuItem;
  Ops: TGittanBatchExtOps;
  ShownKey: string;
  ShownGen: QWord;
  i, n: integer;
begin
  Eng := TGittanExtEngine.Existing;
  ShownKey := '';
  ShownGen := 0;
  if FExtTab >= 0 then
  begin
    ShownKey := TGittanExtRegistry.KindKey(FExtTabs[FExtTab].ExtId, FExtTabs[FExtTab].Id,
      cwForgeTab);
    ShownGen := FExtTabGen;
  end;
  FExtTabs := nil;
  Ops := nil;
  if FExtMenu <> nil then
    FExtMenu.Clear;
  if Eng <> nil then
  begin
    n := 0;
    for Cmd in Eng.Registry.CommandsIn(cwForgeTab) do
      if Eng.ExtForgeInScope(Cmd.ExtId, ForgeName) then
      begin
        SetLength(FExtTabs, n + 1);
        FExtTabs[n] := Cmd;
        Inc(n);
      end;
    n := 0;
    for Cmd in Eng.Registry.CommandsIn(cwBatch) do
    begin
      SetLength(Ops, n + 1);
      Ops[n].Key := TGittanExtRegistry.KindKey(Cmd.ExtId, Cmd.Id, cwBatch);
      Ops[n].ExtId := Cmd.ExtId;
      Ops[n].Title := Cmd.Title;
      Ops[n].Note := Cmd.Note;
      Ops[n].Source := Format(rsFromExtension, [ExtNameOf(Cmd)]);
      Inc(n);
    end;
    if FExtMenu <> nil then
      for Cmd in Eng.Registry.CommandsIn(cwForge) do
        if Eng.ExtForgeInScope(Cmd.ExtId, ForgeName) then
        begin
          Item := TMenuItem.Create(FExtMenu);
          Item.Caption := Cmd.Title;
          Item.Hint := TGittanExtRegistry.CommandKey(Cmd.ExtId, Cmd.Id);
          Item.OnClick := @ExtCommandClick;
          FExtMenu.Add(Item);
        end;
  end;
  if FExtMenu <> nil then
  begin
    if FExtMenu.Count > 0 then
      FExtMenu.Add(NewLine);
    Item := TMenuItem.Create(FExtMenu);
    Item.Caption := rsReloadExtensions;
    Item.OnClick := @MenuExtReloadClick;
    FExtMenu.Add(Item);
    Item := TMenuItem.Create(FExtMenu);
    Item.Caption := rsOpenExtensionsFolder;
    Item.OnClick := @MenuExtFolderClick;
    FExtMenu.Add(Item);
  end;

  { The run: stopped when its operation is gone or was loaded again. }
  if FExtRunKey <> '' then
  begin
    if (Eng = nil) or not Eng.Registry.FindCommand(FExtRunKey, Cmd) then
      FinishExtRun(rsExtRunGone)
    else if Eng.GenerationForContext(Cmd.Ctx) <> FExtRunGen then
      FinishExtRun(rsExtReloaded);
  end;
  FBatch.SetExtOps(Ops);
  if FBatch.Visible then
    FBatch.FitHeight(FBox.ClientHeight);

  { The tab shown, where it is now. }
  if ShownKey <> '' then
  begin
    FExtTab := -1;
    for i := 0 to High(FExtTabs) do
      if TGittanExtRegistry.KindKey(FExtTabs[i].ExtId, FExtTabs[i].Id, cwForgeTab) = ShownKey then
        FExtTab := i;
    if FExtTab < 0 then
    begin
      { Gone: the first section in its place, or Batch without a
        forge. }
      FExtTabSeq := 0;
      FExtPage.Visible := False;
      FPage.Section := 0;
      FPage.FitHeight(FBox.ClientHeight);
      FPage.Visible := True;
      ApplyForgeState;
    end
    else if (Eng = nil) or (Eng.GenerationForContext(FExtTabs[FExtTab].Ctx) <> ShownGen) then
    begin
      { Loaded again: what the old context was asked (a render or an
        action) never answers, so it is asked again. }
      FExtTabActing := False;
      FExtTabRenderAfter := False;
      if FIsShown then
        ShowExtTab
      else
        FExtTabSeq := 0;
    end;
  end;
  if Assigned(FOnTabsChange) then
    FOnTabsChange(Self);
end;

procedure TForgeView.ShowExtTab;
begin
  if (FExtTab < 0) or (FExtTab > High(FExtTabs)) then
    Exit;
  FExtPage.SetTab(FExtTabs[FExtTab].Title, FExtTabs[FExtTab].Note,
    Format(rsFromExtension, [ExtNameOf(FExtTabs[FExtTab])]));
  FExtPage.Width := FBox.ClientWidth;
  FPage.Visible := False;
  FBatch.Visible := False;
  FExtPage.Visible := True;
  RenderExtTabSoon;
end;

{ The tab's render, asked with a number of its own; an answer to an
  older request is not taken. }
procedure TForgeView.RenderExtTab;
var
  Eng: TGittanExtEngine;
  Ctx: TJSONObject;
  Key: string;
  Cmd: TGittanExtCommand;
begin
  if (FExtTab < 0) or (FExtTab > High(FExtTabs)) then
    Exit;
  Eng := TGittanExtEngine.Existing;
  Key := TGittanExtRegistry.KindKey(FExtTabs[FExtTab].ExtId, FExtTabs[FExtTab].Id, cwForgeTab);
  if (Eng = nil) or not Eng.Registry.FindCommand(Key, Cmd) then
  begin
    FExtPage.SetError(rsExtTabGone);
    FExtPage.FitHeight(FBox.ClientHeight);
    Exit;
  end;
  FExtTabGen := Eng.GenerationForContext(Cmd.Ctx);
  FExtTabStale := False;
  FExtTabSeq := NextExtSeq;
  FExtTabActing := False;
  FExtTabRenderAfter := False;
  FExtPage.SetBusy(True, False);
  FExtPage.FitHeight(FBox.ClientHeight);
  Ctx := ExtContext;
  try
    Ctx.Add('seq', FExtTabSeq);
    Ctx.Add('kind', 'render');
    Eng.RunCommand(Key, Ctx.AsJSON);
  finally
    Ctx.Free;
  end;
end;

procedure TForgeView.RenderExtTabSoon;
begin
  if FExtTabActing and (FExtTabSeq <> 0) then
    FExtTabRenderAfter := True
  else
    RenderExtTab;
end;

procedure TForgeView.RenderExtTabAsync(Data: PtrInt);
begin
  if (FExtTab >= 0) and FExtPage.Visible and (FExtTabSeq = 0) then
    RenderExtTab;
end;

procedure TForgeView.ExtTabRefresh(Sender: TObject);
begin
  RenderExtTabSoon;
end;

{ An action of a row: the extension's action with the row as it gave
  it; its answer is the new model, or nothing, and the tab renders
  again. }
procedure TForgeView.ExtTabAction(Sender: TObject; ARow: integer; const AAction: string);
var
  Eng: TGittanExtEngine;
  Ctx: TJSONObject;
  Key: string;
  Cmd: TGittanExtCommand;
  Row: TJSONData;
begin
  if (FExtTab < 0) or (FExtTab > High(FExtTabs)) then
    Exit;
  Eng := TGittanExtEngine.Existing;
  Key := TGittanExtRegistry.KindKey(FExtTabs[FExtTab].ExtId, FExtTabs[FExtTab].Id, cwForgeTab);
  if (Eng = nil) or not Eng.Registry.FindCommand(Key, Cmd) then
    Exit;
  FExtTabGen := Eng.GenerationForContext(Cmd.Ctx);
  FExtTabSeq := NextExtSeq;
  FExtTabActing := True;
  FExtTabRenderAfter := False;
  FExtPage.SetBusy(True, True);
  Ctx := ExtContext;
  try
    Ctx.Add('seq', FExtTabSeq);
    Ctx.Add('kind', 'action');
    Ctx.Add('action', AAction);
    try
      Row := GetJSON(FExtPage.RowJson(ARow));
    except
      Row := TJSONNull.Create;
    end;
    Ctx.Add('row', Row);
    Eng.RunCommand(Key, Ctx.AsJSON);
  finally
    Ctx.Free;
  end;
end;

procedure TForgeView.ExtTabOpenUrl(Sender: TObject; const ATarget: string);
begin
  if ExtWebUrl(ATarget) <> '' then
    OpenURL(ATarget);
end;

procedure TForgeView.ExtTabOpenRepo(Sender: TObject; const ATarget: string);
begin
  if DirectoryExists(ATarget) then
    FWindow.OpenRepository(ATarget);
end;

procedure TForgeView.ExtTabAnswer(const AJson: string);
var
  Value: TJSONData;
  Err: string;
  Model: TExtTabModel;
  Acting, RenderAfter: boolean;
begin
  Acting := FExtTabActing;
  RenderAfter := FExtTabRenderAfter;
  FExtTabSeq := 0;
  FExtTabActing := False;
  FExtTabRenderAfter := False;
  if not ReadExtAnswer(AJson, Value, Err) then
    FExtPage.SetError(Err)
  else
    try
      if ExtTabModelOf(Value, Model) then
        FExtPage.SetModel(Model)
      else if Acting then
      begin
        { The action said nothing of the rows: they are asked again. }
        RenderExtTab;
        Exit;
      end
      else
        FExtPage.SetModel(Default(TExtTabModel));
    finally
      Value.Free;
    end;
  FExtPage.FitHeight(FBox.ClientHeight);
  { A render asked for while the action ran (Refresh, the view shown
    again), from the message loop as the answer may come while
    RunCommand is on the stack. }
  if RenderAfter then
    Application.QueueAsyncCall(@RenderExtTabAsync, 0);
end;

procedure TForgeView.ExtDeliver(ASeq: integer; const AExtId, AJson: string);
var
  Value: TJSONData;
  Err: string;
  Res: TExtBatchResult;
begin
  if (ASeq = 0) then
    Exit;
  if (ASeq = FExtTabSeq) and (FExtTab >= 0) and (FExtTab <= High(FExtTabs)) and
    (FExtTabs[FExtTab].ExtId = AExtId) then
    ExtTabAnswer(AJson)
  else if (ASeq = FExtRunSeq) and (FExtRunKey <> '') and (AExtId = FExtRunExt) then
  begin
    FExtRunSeq := 0;
    if ReadExtAnswer(AJson, Value, Err) then
      try
        Res := ExtBatchResultOf(Value);
      finally
        Value.Free;
      end
    else
    begin
      Res := Default(TExtBatchResult);
      Res.Said := True;
      Res.Text := Err;
      Res.Severity := esError;
    end;
    FBatch.SetExtResult(FExtRunKey, FExtRunIndex, Res, False);
    Inc(FExtRunIndex);
    if FBatch.Visible then
      FBatch.FitHeight(FBox.ClientHeight);
    { From the message loop: the answer may come while RunCommand is
      still on the stack. }
    Application.QueueAsyncCall(@RunExtStepAsync, 0);
  end;
end;

{ Run of an extension's operation: once for each picked repository, in
  turn, as each answers; one run at a time. }
procedure TForgeView.BatchExtRun(Sender: TObject);
var
  Op: TGittanBatchExtOp;
  Eng: TGittanExtEngine;
  Cmd: TGittanExtCommand;
begin
  if (FExtRunKey <> '') or not FBatch.ShownExtOp(Op) then
    Exit;
  Eng := TGittanExtEngine.Existing;
  if (Eng = nil) or not Eng.Registry.FindCommand(Op.Key, Cmd) then
    Exit;
  FBatch.ChosenRepos(FExtRunPaths, FExtRunCaptions);
  if Length(FExtRunPaths) = 0 then
    Exit;
  FExtRunKey := Op.Key;
  FExtRunExt := Op.ExtId;
  FExtRunGen := Eng.GenerationForContext(Cmd.Ctx);
  FExtRunIndex := 0;
  FExtRunSeq := 0;
  FBatch.StartExtRun(Op.Key, FExtRunPaths, FExtRunCaptions);
  FBatch.FitHeight(FBox.ClientHeight);
  RunExtStep;
end;

procedure TForgeView.RunExtStepAsync(Data: PtrInt);
begin
  RunExtStep;
end;

{ The next repository: left out when the extension does not run for it
  (@repos, @forges against its remotes), else the operation called with
  the repository, its name and its forge, the answer awaited. One
  repository a call: after one left out the next is taken from the
  message loop, so a run over many repositories that the extension
  leaves out (each a git process for its remotes) keeps the window
  alive. }
procedure TForgeView.RunExtStep;
var
  Eng: TGittanExtEngine;
  Path, Urls: string;
  Forge: TGittanForgeClass;
  Ctx: TJSONObject;
begin
  if (FExtRunKey = '') or (FExtRunSeq <> 0) then
    Exit;
  Eng := TGittanExtEngine.Existing;
  while FExtRunIndex <= High(FExtRunPaths) do
  begin
    if Eng = nil then
    begin
      FinishExtRun(rsExtRunGone);
      Exit;
    end;
    Path := FExtRunPaths[FExtRunIndex];
    Urls := '';
    if DirectoryExists(Path) then
      Urls := ResolvedRemoteUrlsIn(Path);
    if not Eng.ExtInScope(FExtRunExt, Path, Urls) then
    begin
      FBatch.SetExtResult(FExtRunKey, FExtRunIndex, Default(TExtBatchResult), True);
      Inc(FExtRunIndex);
      if FExtRunIndex <= High(FExtRunPaths) then
      begin
        Application.QueueAsyncCall(@RunExtStepAsync, 0);
        Exit;
      end;
      Continue;
    end;
    Forge := ForgeClassFor(Urls);
    FExtRunSeq := NextExtSeq;
    Ctx := ExtContext;
    try
      Ctx.Add('seq', FExtRunSeq);
      Ctx.Add('repo', Path);
      Ctx.Add('name', FExtRunCaptions[FExtRunIndex]);
      if Forge <> nil then
        Ctx.Strings['forge'] := Forge.Name
      else
        Ctx.Nulls['forge'] := True;
      if not Eng.RunCommand(FExtRunKey, Ctx.AsJSON) then
        FinishExtRun(rsExtRunGone);
    finally
      Ctx.Free;
    end;
    if FBatch.Visible then
      FBatch.FitHeight(FBox.ClientHeight);
    Exit;
  end;
  FinishExtRun('');
end;

procedure TForgeView.FinishExtRun(const AError: string);
begin
  if FExtRunKey = '' then
    Exit;
  FBatch.FinishExtRun(FExtRunKey, AError);
  FExtRunKey := '';
  FExtRunExt := '';
  FExtRunSeq := 0;
  FExtRunGen := 0;
  if FBatch.Visible then
    FBatch.FitHeight(FBox.ClientHeight);
end;

procedure TForgeView.BatchOpenUrl(Sender: TObject; const APath: string);
begin
  if ExtWebUrl(APath) <> '' then
    OpenURL(APath);
end;

procedure TForgeView.ExtCommandClick(Sender: TObject);
var
  Eng: TGittanExtEngine;
  Ctx: TJSONObject;
begin
  Eng := TGittanExtEngine.Existing;
  if (Eng = nil) or not (Sender is TMenuItem) then
    Exit;
  Ctx := ExtContext;
  try
    if not Eng.RunCommand(TMenuItem(Sender).Hint, Ctx.AsJSON) then
      ExtensionsChanged;
  finally
    Ctx.Free;
  end;
end;

procedure TForgeView.MenuExtReloadClick(Sender: TObject);
begin
  App.Extensions.Reload;
end;

procedure TForgeView.MenuExtFolderClick(Sender: TObject);
begin
  OpenDocument(App.Extensions.Dir);
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
