unit uwindow;

{** The main window: the shell around the repository frames (TRepoFrame
  in umain), each of which shows one repository. The window makes App
  (gittan.app) first and frees it last, keeps its own place and size in
  the settings, and owns the chrome: on macOS the toolbar (gittan.toolbar)
  and the strip under the title bar (gittan.titlebar), on Windows and
  GTK 3 the title bar it draws itself (gittan.owntitlebar).

  Several frames can be open; one is shown (FActive) and the others go
  on in the background, hidden. The shown one gives the window its menu
  and caption (TRepoFrame.Activated) and gets the window's events:
  the keys (KeyPreview, for the commands' keys from any view),
  activation and dropped files. Closing asks every frame and saves them
  all, the shown one last, since the settings keep its view options.
  App's news goes to every frame: the lexers loaded, a newer build.

  OpenRepository is the one way a repository opens: it shows the frame
  that has it open already (or is opening it), else opens it in the
  shown frame while that one is empty, else in a new frame.

  The tabs show the frames, in the toolbar's tab strip on macOS and in
  the own title bar on Windows and GTK 3, a tab each with the
  frame's TabTitle and TabHint (UpdateTabs, whenever one changes, is
  shown, made or closed); File > New Tab (Cmd+T) and the plus make an
  empty one, File > Close Tab (Cmd+W), the cross and a middle click
  close one, Go > Next Tab and Previous Tab (Cmd+Shift+] and [, and
  Ctrl+Tab and Ctrl+Shift+Tab) step round them, and Cmd with a digit
  (Ctrl elsewhere) shows that tab, 9 the last one. Closing the last tab
  leaves an empty one. The repositories open in the tabs are kept in
  the settings (Tabs, ActiveTab) and open again at the next start. }

{$mode objfpc}{$H+}

{ The form draws its own title bar on Windows and GTK 3, as in umain. }
{$IF DEFINED(LCLWin32) OR DEFINED(LCLGtk3)}{$DEFINE OWNBAR}{$ENDIF}

interface

uses
  Classes, SysUtils, Types, Math, LCLType, Forms, Controls, gittan.app,
  gittan.git, umain
  {$IFDEF LCLCocoa}, gittan.toolbar, gittan.titlebar{$ENDIF}
  {$IFDEF OWNBAR}, gittan.owntitlebar{$ENDIF}
  {$IFDEF LCLWin32}, gittan.wintitlebar{$ENDIF}
  {$IFDEF LCLGtk3}, gittan.gtktitlebar{$ENDIF};

type

  { TGittanWindow }

  TGittanWindow = class(TRepoWindow)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
  private
    FFrames: TList;
    FActive: TRepoFrame;
    FTitleBarHeight: integer;
    {$IFDEF LCLCocoa}
    { The toolbar on macOS 11 and later, nil before. }
    FToolbar: TGittanToolbar;
    {$ENDIF}
    {$IFDEF OWNBAR}
    { A TGittanWinTitleBar or a TGittanGtkTitleBar, above the frames. }
    FOwnBar: TGittanOwnTitleBar;
    {$ENDIF}
    function GetFrame(AIndex: integer): TRepoFrame;
    procedure SetupChrome;
    procedure PlaceWindow;
    procedure SavePlace;
    function StartRepository: string;
    procedure OpenAtStartAsync(Data: PtrInt);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: boolean);
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure FormActivate(Sender: TObject);
    procedure LexersLoaded(Sender: TObject);
    procedure UpdateChecked(Sender: TObject; AManual: boolean);
    procedure UpdateTabs;
    procedure SaveTabs;
    procedure CloseFrameAsync(Data: PtrInt);
    procedure TabSelect(Sender: TObject; AIndex: integer);
    procedure TabClose(Sender: TObject; AIndex: integer);
    procedure TabNew(Sender: TObject);
  public
    procedure OpenRepository(const ADir: string; AOnOpened: TNotifyEvent = nil);
      override;
    function IsActive(AFrame: TRepoFrame): boolean; override;
    function TitleBarHeight: integer; override;
    {$IFDEF OWNBAR}
    function OwnBar: TGittanOwnTitleBar; override;
    {$ENDIF}
    procedure FrameChanged(AFrame: TRepoFrame); override;
    procedure NewTab; override;
    procedure CloseFrame(AFrame: TRepoFrame); override;
    procedure StepTab(ADelta: integer); override;
    {** A new, empty frame, shown. }
    function NewFrame: TRepoFrame;
    {** Shows AFrame and hides the one shown before. }
    procedure ActivateFrame(AFrame: TRepoFrame);
    function FrameCount: integer;
    property Frames[AIndex: integer]: TRepoFrame read GetFrame;
    property ActiveFrame: TRepoFrame read FActive;
  end;

var
  GittanWindow: TGittanWindow;

implementation

{$R *.lfm}

{$IFDEF OWNBAR}
resourcestring
  { The name the own title bar shows. }
  rsAppShortName = 'Gittan';
{$ENDIF}


procedure TGittanWindow.FormCreate(Sender: TObject);
var
  Lexers: boolean;
begin
  { First: everything below reads the settings. }
  CreateApp;
  FFrames := TList.Create;
  PlaceWindow;
  KeyPreview := True;
  OnKeyDown := @FormKeyDown;
  OnActivate := @FormActivate;
  OnClose := @FormClose;
  OnCloseQuery := @FormCloseQuery;
  App.OnUpdateChecked := @UpdateChecked;
  App.Lexers.OnLoaded := @LexersLoaded;
  SetupChrome;
  { Before the first frame builds its Syntax menu, which takes the
    lexers loaded by then and gets the rest from LexersLoaded. }
  Lexers := App.Lexers.Load;
  { The first frame is made here, in FormCreate, so the form scales it
    to the screen with the rest afterwards (TCustomForm.AfterConstruction). }
  NewFrame;
  if not Lexers then
    FActive.ShowNoLexers;
  { The welcome view says what opens, rather than offer its buttons
    until it does. }
  if App.Settings.Tabs.Count > 0 then
    FActive.ShowOpening(App.Settings.Tabs[0])
  else if StartRepository <> '' then
    FActive.ShowOpening(StartRepository);
  Application.QueueAsyncCall(@OpenAtStartAsync, 0);
end;

procedure TGittanWindow.FormDestroy(Sender: TObject);
var
  i: integer;
begin
  Application.RemoveAsyncCalls(Self);
  App.OnUpdateChecked := nil;
  App.Lexers.OnLoaded := nil;
  FActive := nil;
  for i := FFrames.Count - 1 downto 0 do
    TRepoFrame(FFrames[i]).Free;
  FreeAndNil(FFrames);
  {$IFDEF LCLCocoa}
  FreeAndNil(FToolbar);
  {$ENDIF}
  { Last: the lexers go with it, which the frames' editors let go of. }
  FreeApp;
end;

{ The chrome comes before the frames, which keep their content clear of
  the strip under the title bar (TitleBarHeight).

  On macOS the toolbar first, since it makes the strip taller; then the
  content reaches under the title bar. On Windows and GTK 3 the window
  draws its title bar itself, with the name, the menus (those of the
  frame shown) and the caption buttons, above the frames. }
procedure TGittanWindow.SetupChrome;
begin
  {$IFDEF LCLCocoa}
  FToolbar := TGittanToolbar.Install(Handle);
  if FToolbar <> nil then
  begin
    FToolbar.OnSelect := @TabSelect;
    FToolbar.OnClose := @TabClose;
    FToolbar.OnNew := @TabNew;
  end;
  FTitleBarHeight := ExtendUnderTitleBar(Handle);
  {$ENDIF}
  {$IFDEF LCLWin32}
  FOwnBar := TGittanWinTitleBar.Create(Self);
  {$ENDIF}
  {$IFDEF LCLGtk3}
  FOwnBar := TGittanGtkTitleBar.Create(Self);
  {$ENDIF}
  {$IFDEF OWNBAR}
  FOwnBar.Title := rsAppShortName;
  FOwnBar.Align := alTop;
  FOwnBar.Parent := Self;
  FOwnBar.OnTabSelect := @TabSelect;
  FOwnBar.OnTabClose := @TabClose;
  FOwnBar.OnNewTab := @TabNew;
  {$ENDIF}
  {$IFDEF LCLWin32}
  InstallTitleBar(Self, TGittanWinTitleBar(FOwnBar));
  {$ENDIF}
  {$IFDEF LCLGtk3}
  InstallTitleBar(Self, TGittanGtkTitleBar(FOwnBar));
  {$ENDIF}
end;

function TGittanWindow.GetFrame(AIndex: integer): TRepoFrame;
begin
  Result := TRepoFrame(FFrames[AIndex]);
end;

function TGittanWindow.FrameCount: integer;
begin
  Result := FFrames.Count;
end;

{ A frame has no owner, so several can share the name from its resource,
  and the window frees them itself. Its PixelsPerInch is set to the
  window's before it is placed, so placing it does not scale it (the
  controls Init makes would be left out); once Init has made them, the
  frame and all of them are scaled from 96 DPI together, as the form
  scales the first frame after FormCreate. }
function TGittanWindow.NewFrame: TRepoFrame;
var
  DesignPPI: integer;
begin
  Result := TRepoFrame.Create(nil);
  FFrames.Add(Result);
  DesignPPI := Result.DesignTimePPI;
  Result.PixelsPerInch := PixelsPerInch;
  Result.Visible := False;
  Result.Align := alClient;
  Result.Parent := Self;
  Result.Init(Self);
  if PixelsPerInch <> DesignPPI then
  begin
    Result.PixelsPerInch := DesignPPI;
    Result.AutoAdjustLayout(lapAutoAdjustForDPI, DesignPPI, PixelsPerInch, 0, 0);
  end;
  ActivateFrame(Result);
end;

procedure TGittanWindow.ActivateFrame(AFrame: TRepoFrame);
var
  Old: TRepoFrame;
begin
  if AFrame = FActive then
    Exit;
  Old := FActive;
  FActive := AFrame;
  AFrame.Visible := True;
  AFrame.BringToFront;
  if Old <> nil then
    Old.Visible := False;
  AFrame.Activated;
  UpdateTabs;
end;

function TGittanWindow.IsActive(AFrame: TRepoFrame): boolean;
begin
  Result := (AFrame <> nil) and (AFrame = FActive);
end;

function TGittanWindow.TitleBarHeight: integer;
begin
  Result := FTitleBarHeight;
end;

{$IFDEF OWNBAR}
function TGittanWindow.OwnBar: TGittanOwnTitleBar;
begin
  Result := FOwnBar;
end;
{$ENDIF}

{ The root git names for ADir, which may be a folder inside the work tree,
  so a repository is found open whichever of its folders is asked for;
  '' when ADir is not in one (the frame then says so). }
function RepositoryRootOf(const ADir: string): string;
var
  Probe: TGittanRepo;
begin
  Result := '';
  Probe := TGittanRepo.Create;
  try
    if Probe.Open(ADir) then
      Result := Probe.Root;
  finally
    Probe.Free;
  end;
end;

procedure TGittanWindow.OpenRepository(const ADir: string; AOnOpened: TNotifyEvent);
var
  Root: string;
  Target: TRepoFrame;
  i: integer;
begin
  Root := ExcludeTrailingPathDelimiter(RepositoryRootOf(ADir));
  if Root <> '' then
    for i := 0 to FFrames.Count - 1 do
      if SameFileName(ExcludeTrailingPathDelimiter(Frames[i].RepoRoot), Root) or
        ((Frames[i].OpeningDir <> '') and SameFileName(ExcludeTrailingPathDelimiter(
        RepositoryRootOf(Frames[i].OpeningDir)), Root)) then
      begin
        ActivateFrame(Frames[i]);
        if Assigned(AOnOpened) then
          AOnOpened(Frames[i]);
        Exit;
      end;
  if (FActive <> nil) and FActive.IsBlank then
    Target := FActive
  else
    Target := NewFrame;
  Target.OpenRepository(ADir, AOnOpened);
end;

{ The folder on the command line, else the repository of the last run
  when there is no argument; empty for a file or nothing to open. }
function TGittanWindow.StartRepository: string;
begin
  Result := '';
  if ParamCount > 0 then
  begin
    if DirectoryExists(ParamStr(1)) then
      Result := ParamStr(1);
  end
  else if (App.Settings.Recent.Count > 0) and DirectoryExists(App.Settings.Recent[0]) then
    Result := App.Settings.Recent[0];
end;

{ Opening a repository runs some twenty git commands one after the other,
  which takes seconds on Windows, where a process is slow to start; queued
  from FormCreate it runs once the window is shown and painted. A folder
  or file dropped on the Dock icon at launch may be open or opening by
  then (FormDropFiles), and stays. }
procedure TGittanWindow.OpenAtStartAsync(Data: PtrInt);
var
  Tabs: TStringList;
  Shown: TRepoFrame;
  i: integer;
begin
  { The tabs of the last run, the one shown then shown again; then
    gittan [file | folder] in its own tab, else, with no tabs kept (a
    settings file from before tabs), the repository of the last run. }
  Shown := nil;
  if FActive.IsBlank then
  begin
    Tabs := TStringList.Create;
    try
      Tabs.Assign(App.Settings.Tabs);
      for i := 0 to Tabs.Count - 1 do
        if DirectoryExists(Tabs[i]) then
        begin
          OpenRepository(Tabs[i]);
          if i = App.Settings.ActiveTab then
            Shown := FActive;
        end;
      if Shown <> nil then
        ActivateFrame(Shown);
      if ParamCount > 0 then
      begin
        if DirectoryExists(ParamStr(1)) then
          OpenRepository(ParamStr(1))
        else if FActive.IsBlank then
          FActive.OpenFile(ParamStr(1))
        else
          NewFrame.OpenFile(ParamStr(1));
      end
      else if (Tabs.Count = 0) and (StartRepository <> '') then
        OpenRepository(StartRepository);
    finally
      Tabs.Free;
    end;
  end;
  { After the repositories, whose opening clears the banners. }
  FActive.CheckGitVersion;
end;

{ The window where it was, if that is still on a screen. The sizes are
  kept at 96 DPI: this runs in FormCreate, and the form scales its size
  and the frame's to the screen's after it, its place not. Else
  FirstShare of the main screen's work area, no smaller than the
  designed size and no larger than FirstMaxWidth by FirstMaxHeight, in
  its middle: the place in the screen's pixels, the size at 96 DPI for
  the form to scale. }
procedure TGittanWindow.PlaceWindow;
const
  { The share of the screen's work area a window with no place of its
    own takes. }
  FirstShare = 0.7;
  { At most this at 96 DPI, so it is not a band across a wide screen. }
  FirstMaxWidth = 1600;
  FirstMaxHeight = 1000;
var
  R, Area: TRect;
  W, H: integer;
  Placed: boolean;
begin
  Placed := False;
  if (App.Settings.Width > 0) and (App.Settings.Height > 0) then
  begin
    R := Rect(App.Settings.Left, App.Settings.Top, App.Settings.Left + App.Settings.Width,
      App.Settings.Top + App.Settings.Height);
    Placed := IntersectRect(R, R, Screen.DesktopRect) and (R.Width > 100) and
      (R.Height > 100);
    if Placed then
      SetBounds(App.Settings.Left, App.Settings.Top, App.Settings.Width, App.Settings.Height);
  end;
  if not Placed then
  begin
    Area := Screen.PrimaryMonitor.WorkareaRect;
    W := Min(Area.Width, Max(Scale96ToScreen(Width), Min(Scale96ToScreen(FirstMaxWidth),
      Round(Area.Width * FirstShare))));
    H := Min(Area.Height, Max(Scale96ToScreen(Height), Min(Scale96ToScreen(FirstMaxHeight),
      Round(Area.Height * FirstShare))));
    SetBounds(Area.Left + (Area.Width - W) div 2, Area.Top + (Area.Height - H) div 2,
      MulDiv(W, 96, Screen.PixelsPerInch), MulDiv(H, 96, Screen.PixelsPerInch));
  end;
  if App.Settings.Maximized then
    WindowState := wsMaximized;
end;

{ The place and size go in the settings at 96 DPI; a maximized window
  keeps the place it is restored to. }
procedure TGittanWindow.SavePlace;
begin
  App.Settings.Maximized := WindowState = wsMaximized;
  if App.Settings.Maximized then
  begin
    App.Settings.Left := RestoredLeft;
    App.Settings.Top := RestoredTop;
    App.Settings.Width := RestoredWidth;
    App.Settings.Height := RestoredHeight;
  end
  else
  begin
    App.Settings.Left := Left;
    App.Settings.Top := Top;
    App.Settings.Width := Width;
    App.Settings.Height := Height;
  end;
  App.Settings.Width := MulDiv(App.Settings.Width, 96, Screen.PixelsPerInch);
  App.Settings.Height := MulDiv(App.Settings.Height, 96, Screen.PixelsPerInch);
end;

{ Every frame saves its own, the shown one last: the view options in
  the settings are its. Each writes the settings. }
procedure TGittanWindow.FormClose(Sender: TObject; var CloseAction: TCloseAction);
var
  i: integer;
begin
  SavePlace;
  SaveTabs;
  for i := 0 to FFrames.Count - 1 do
    if Frames[i] <> FActive then
      Frames[i].FormClose(Sender, CloseAction);
  FActive.FormClose(Sender, CloseAction);
end;

{ A frame with unsaved changes is shown before it asks. }
procedure TGittanWindow.FormCloseQuery(Sender: TObject; var CanClose: boolean);
var
  i: integer;
begin
  FActive.FormCloseQuery(Sender, CanClose);
  for i := 0 to FFrames.Count - 1 do
  begin
    if not CanClose then
      Exit;
    if Frames[i] <> FActive then
    begin
      Frames[i].FormCloseQuery(Sender, CanClose);
      if not CanClose then
        ActivateFrame(Frames[i]);
    end;
  end;
end;

{ The shown frame's keys; on GTK Alt and a letter opens the menu with
  that accelerator from the title bar, as the menu bar would have
  before the bar hid its names. }
procedure TGittanWindow.FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
var
  Index: integer;
begin
  { Cmd with a digit (Ctrl elsewhere) shows that tab, 9 the last one, as
    in a web browser; no menu item has those keys. }
  if (Key >= VK_1) and (Key <= VK_9) and (Shift * [ssShift, ssAlt, ssCtrl, ssMeta] =
    [{$IFDEF DARWIN}ssMeta{$ELSE}ssCtrl{$ENDIF}]) then
  begin
    if Key = VK_9 then
      Index := FFrames.Count - 1
    else
      Index := Key - VK_1;
    if Index < FFrames.Count then
      ActivateFrame(Frames[Index]);
    Key := 0;
    Exit;
  end;
  if (Key = VK_TAB) and (Shift * [ssCtrl, ssAlt, ssMeta] = [ssCtrl]) then
  begin
    if ssShift in Shift then
      StepTab(-1)
    else
      StepTab(1);
    Key := 0;
    Exit;
  end;
  FActive.FormKeyDown(Sender, Key, Shift);
  {$IFDEF LCLGtk3}
  if (Key <> 0) and (Shift * [ssAlt, ssCtrl, ssShift, ssMeta] = [ssAlt]) and
    (Key >= VK_A) and (Key <= VK_Z) and FOwnBar.OpenMenuByKey(Chr(Key)) then
    Key := 0;
  {$ENDIF}
end;

procedure TGittanWindow.FormActivate(Sender: TObject);
begin
  FActive.FormActivate(Sender);
end;

{ Also how Cocoa hands over a path Gittan is asked to open (the gittan
  command, the Dock icon): a folder opens as a repository, a file in
  the frame shown. }
procedure TGittanWindow.FormDropFiles(Sender: TObject; const FileNames: array of string);
begin
  if FActive <> nil then
    FActive.FormDropFiles(Sender, FileNames);
end;

procedure TGittanWindow.LexersLoaded(Sender: TObject);
var
  i: integer;
begin
  for i := 0 to FFrames.Count - 1 do
    Frames[i].LexersLoaded(Sender);
end;

{ Every frame shows the badge; only the shown one answers the menu. }
procedure TGittanWindow.UpdateChecked(Sender: TObject; AManual: boolean);
var
  i: integer;
begin
  for i := 0 to FFrames.Count - 1 do
    if Frames[i] = FActive then
      Frames[i].UpdateChecked(Sender, AManual)
    else if App.UpdateOk then
      Frames[i].ShowUpdateBadge;
end;

procedure TGittanWindow.FrameChanged(AFrame: TRepoFrame);
begin
  UpdateTabs;
end;

procedure TGittanWindow.UpdateTabs;
var
  Captions, Hints: array of string;
  i: integer;
begin
  if (csDestroying in ComponentState) or (FFrames = nil) then
    Exit;
  Captions := nil;
  Hints := nil;
  SetLength(Captions, FFrames.Count);
  SetLength(Hints, FFrames.Count);
  for i := 0 to FFrames.Count - 1 do
  begin
    Captions[i] := Frames[i].TabTitle;
    Hints[i] := Frames[i].TabHint;
  end;
  {$IFDEF LCLCocoa}
  if FToolbar <> nil then
    FToolbar.SetTabs(Captions, Hints, FFrames.IndexOf(FActive));
  {$ENDIF}
  {$IFDEF OWNBAR}
  FOwnBar.SetTabs(Captions, Hints, FFrames.IndexOf(FActive));
  {$ENDIF}
end;

{ The repositories open in the tabs, left to right, and the shown one's
  place among them; a tab without one is left out. }
procedure TGittanWindow.SaveTabs;
var
  i: integer;
begin
  App.Settings.Tabs.Clear;
  App.Settings.ActiveTab := 0;
  for i := 0 to FFrames.Count - 1 do
    if Frames[i].RepoRoot <> '' then
    begin
      if Frames[i] = FActive then
        App.Settings.ActiveTab := App.Settings.Tabs.Count;
      App.Settings.Tabs.Add(Frames[i].RepoRoot);
    end;
end;

procedure TGittanWindow.NewTab;
begin
  NewFrame;
end;

{ From the message loop: the menu item that asks is the frame's own. }
procedure TGittanWindow.CloseFrame(AFrame: TRepoFrame);
begin
  Application.QueueAsyncCall(@CloseFrameAsync, PtrInt(AFrame));
end;

{ A frame with unsaved changes is shown before it asks, and stays when
  they are kept. It saves what closing the window saves, and the tab to
  its right is shown, else the one to its left, else a new empty one. }
procedure TGittanWindow.CloseFrameAsync(Data: PtrInt);
var
  Frame, Neighbour: TRepoFrame;
  Index: integer;
  CanClose: boolean;
  CloseAction: TCloseAction;
begin
  Frame := TRepoFrame(Data);
  Index := FFrames.IndexOf(Frame);
  if Index < 0 then
    Exit;
  if Frame.NeedsSave then
    ActivateFrame(Frame);
  CanClose := True;
  Frame.FormCloseQuery(Self, CanClose);
  if not CanClose then
    Exit;
  CloseAction := caFree;
  Frame.FormClose(Self, CloseAction);
  FFrames.Delete(Index);
  if Frame = FActive then
  begin
    FActive := nil;
    if Index < FFrames.Count then
      Neighbour := Frames[Index]
    else if Index > 0 then
      Neighbour := Frames[Index - 1]
    else
      Neighbour := nil;
    if Neighbour <> nil then
      ActivateFrame(Neighbour)
    else
      NewFrame;
  end;
  Frame.Free;
  UpdateTabs;
end;

procedure TGittanWindow.StepTab(ADelta: integer);
var
  Index: integer;
begin
  if FFrames.Count < 2 then
    Exit;
  Index := FFrames.IndexOf(FActive) + ADelta;
  Index := ((Index mod FFrames.Count) + FFrames.Count) mod FFrames.Count;
  ActivateFrame(Frames[Index]);
end;

procedure TGittanWindow.TabSelect(Sender: TObject; AIndex: integer);
begin
  if (AIndex >= 0) and (AIndex < FFrames.Count) then
    ActivateFrame(Frames[AIndex]);
end;

procedure TGittanWindow.TabClose(Sender: TObject; AIndex: integer);
begin
  if (AIndex >= 0) and (AIndex < FFrames.Count) then
    CloseFrame(Frames[AIndex]);
end;

procedure TGittanWindow.TabNew(Sender: TObject);
begin
  NewTab;
end;

end.
