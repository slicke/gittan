unit uforge;

{** The forge view: the user's pull requests across every repository of
  the forge (GitHub), shown in the window over the repository frames
  (TRepoFrame in umain) from the globe at the right end of the window's
  top chrome, the tab strip on macOS and the own title bar on Windows
  and GTK 3, whose tabs are the view's own meanwhile; the globe again,
  Escape or Close GitHub (Cmd+W) goes back to the repository. It is one for the window, since what it
  shows is the user's and not a repository's, and it is there only
  while there is a forge (gh found and GitHub on in the settings:
  App.ForgeCli), which SettingsChanged finds again.

  The content is the forge page (gittan.forgepage) in a scroll box, as
  the Pull Requests page sits in a repository frame's: the open pull
  requests the user wrote or the open ones waiting for their review, a
  section at a time, which the window's tab strip picks while the view
  is shown (Tabs, SelectTab, StepTab, OnTabsChange),
  read by the forge's AccountJob (gittan.forge; GitHub's runs one
  GraphQL query through gh) each time the view is shown and on Refresh,
  the page keeping what it had meanwhile. A card of a pull request goes
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
  Classes, SysUtils, Types, Controls, Forms, Menus, ExtCtrls, Graphics, LCLType,
  gittan.forge, gittan.forgepage, umain;

type

  { TForgeView }

  TForgeView = class(TCustomControl)
  private
    FWindow: TRepoWindow;
    FBox: TScrollBox;
    FPage: TGittanForgePage;
    FForge: TGittanForge;
    { The job under way, and the jobs given up or done, freed once their
      thread has ended. }
    FJob: TGittanForgeJob;
    FZombies: TList;
    FLogin, FError: string;
    FMine, FReview: TGittanForgePulls;
    FMainMenu: TMainMenu;
    FAppMenuItem: TMenuItem;
    FRecentMenu, FCloseItem: TMenuItem;
    FDark: boolean;
    FThemeTimer: TTimer;
    FOnTabsChange: TNotifyEvent;
    procedure FindForge;
    procedure BuildMenu;
    procedure RebuildRecentMenu;
    procedure ApplyTheme;
    procedure UpdatePage;
    procedure StartJob;
    procedure AbandonJob;
    procedure JobDone(Sender: TObject);
    procedure FreeFinishedJobs(AWait: boolean);
    procedure FreeJobsAsync(Data: PtrInt);
    procedure BoxResize(Sender: TObject);
    procedure PagePick(Sender: TObject; const APull: TGittanForgePull);
    procedure PageRefresh(Sender: TObject);
    procedure LoadFilters;
    procedure PageFilterChange(Sender: TObject);
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
    {** The window shows the view now: the page follows the appearance,
      shows what the forge last answered and asks it again. }
    procedure Shown;
    {** The window hid the view. }
    procedure Hidden;
    {** The settings dialog was closed with OK and the tools may have
      changed: the forge is found again, and what one that is gone had
      found is dropped (the window hides the view then, HasForge). }
    procedure SettingsChanged;
    {** The view's tabs, which the window's tab strip shows while the
      view is shown: their names in ACaptions, in AMarks the ones with
      something to do (pull requests waiting for review); gives the
      shown one's index. }
    function Tabs(out ACaptions: TStringArray; out AMarks: TBooleanDynArray): integer;
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
  LCLIntf, gittan.app, gittan.github, gittan.theme, gittan.textfit;

resourcestring
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

{ TForgeView }

constructor TForgeView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FZombies := TList.Create;
end;

destructor TForgeView.Destroy;
begin
  Application.RemoveAsyncCalls(Self);
  if FThemeTimer <> nil then
    FThemeTimer.Enabled := False;
  AbandonJob;
  FreeFinishedJobs(True);
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
  FPage.OnRefresh := @PageRefresh;
  LoadFilters;
  FPage.OnFilterChange := @PageFilterChange;
  FPage.OnOpenUrl := @PageOpenUrl;
  FThemeTimer := TTimer.Create(Self);
  FThemeTimer.Interval := 2000;
  FThemeTimer.Enabled := False;
  FThemeTimer.OnTimer := @ThemeTimerTimer;
  FDark := IsDarkMode;
  ApplyTheme;
  FindForge;
  BuildMenu;
end;

{ The forge from the settings, kept while its tool's path stays the
  same, as a repository frame finds its own. }
procedure TForgeView.FindForge;
var
  Cli: string;
begin
  Cli := App.ForgeCli;
  if Assigned(FForge) and (FForge.Cli = Cli) then
    Exit;
  FreeAndNil(FForge);
  if Cli <> '' then
    FForge := TGittanGitHubForge.Create(Cli);
  FPage.SetForge(ForgeName);
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
  FBox.VertScrollBar.Position := 0;
  FThemeTimer.Enabled := True;
end;

procedure TForgeView.Hidden;
begin
  FThemeTimer.Enabled := False;
end;

procedure TForgeView.SettingsChanged;
begin
  FindForge;
  if Assigned(FForge) then
    Exit;
  { What the forge that is gone had found. }
  AbandonJob;
  FMine := nil;
  FReview := nil;
  FLogin := '';
  FError := '';
  UpdatePage;
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
  SetLength(ACaptions, SectionCount);
  SetLength(AMarks, SectionCount);
  for i := 0 to SectionCount - 1 do
    ACaptions[i] := SectionCaption(i);
  AMarks[fsReview] := Length(FReview) > 0;
  Result := FPage.Section;
end;

procedure TForgeView.SelectTab(AIndex: integer);
begin
  if (AIndex < 0) or (AIndex >= SectionCount) or (AIndex = FPage.Section) then
    Exit;
  FPage.Section := AIndex;
  FPage.FitHeight(FBox.ClientHeight);
  FBox.VertScrollBar.Position := 0;
  if Assigned(FOnTabsChange) then
    FOnTabsChange(Self);
end;

procedure TForgeView.StepTab(ADelta: integer);
begin
  SelectTab(((FPage.Section + ADelta) mod SectionCount + SectionCount) mod SectionCount);
end;

procedure TForgeView.BoxResize(Sender: TObject);
begin
  FPage.FitHeight(FBox.ClientHeight);
end;

{ Asks the forge, one job at a time: a start while one runs waits for
  its answer. The job needs no repository; gh runs in the user's folder. }
procedure TForgeView.StartJob;
begin
  if not Assigned(FForge) or (FJob <> nil) then
    Exit;
  FJob := FForge.AccountJob(GetUserDir);
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
begin
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
    FMine := Job.Mine;
    FReview := Job.Review;
  end;
  UpdatePage;
end;

{ Frees the jobs whose thread has ended; all of them, waiting, when
  AWait (on the way out). }
procedure TForgeView.FreeFinishedJobs(AWait: boolean);
var
  i: integer;
begin
  for i := FZombies.Count - 1 downto 0 do
    if AWait or TThread(FZombies[i]).Finished then
    begin
      TThread(FZombies[i]).Free;
      FZombies.Delete(i);
    end;
end;

procedure TForgeView.FreeJobsAsync(Data: PtrInt);
begin
  FreeFinishedJobs(False);
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

procedure TForgeView.PageRefresh(Sender: TObject);
begin
  StartJob;
end;

{ The checkbox: the settings keep it, and the page's new height. }
{ The page's filters from the settings, a flag each. }
procedure TForgeView.LoadFilters;
var
  Mine, Review: TGittanForgeFilters;
begin
  Mine := [];
  if App.Settings.HideWithoutFeedback then
    Include(Mine, ffFeedback);
  if App.Settings.OnlyNeedsAttention then
    Include(Mine, ffAttention);
  if App.Settings.HideDrafts then
    Include(Mine, ffNoDrafts);
  Review := [];
  if App.Settings.OnlyAskedOfMe then
    Include(Review, ffAskedOfMe);
  if App.Settings.HideReviewDrafts then
    Include(Review, ffNoDrafts);
  FPage.MineFilters := Mine;
  FPage.ReviewFilters := Review;
end;

procedure TForgeView.PageFilterChange(Sender: TObject);
begin
  App.Settings.HideWithoutFeedback := ffFeedback in FPage.MineFilters;
  App.Settings.OnlyNeedsAttention := ffAttention in FPage.MineFilters;
  App.Settings.HideDrafts := ffNoDrafts in FPage.MineFilters;
  App.Settings.OnlyAskedOfMe := ffAskedOfMe in FPage.ReviewFilters;
  App.Settings.HideReviewDrafts := ffNoDrafts in FPage.ReviewFilters;
  FPage.FitHeight(FBox.ClientHeight);
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
