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
  that has it open already, else opens it in the shown frame while that
  one is empty, else in a new frame. For now no tabs show the frames;
  they come next. }

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
    {$IFDEF LCLCocoa}
    procedure ToolbarName(Sender: TObject);
    {$ENDIF}
  public
    procedure OpenRepository(const ADir: string; AOnOpened: TNotifyEvent = nil);
      override;
    function IsActive(AFrame: TRepoFrame): boolean; override;
    function TitleBarHeight: integer; override;
    {$IFDEF OWNBAR}
    function OwnBar: TGittanOwnTitleBar; override;
    {$ENDIF}
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

resourcestring
  rsAppShortName = 'Gittan';

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
  if StartRepository <> '' then
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
  FToolbar := TGittanToolbar.Install(Handle, rsAppShortName);
  if FToolbar <> nil then
    FToolbar.OnName := @ToolbarName;
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
  Root := RepositoryRootOf(ADir);
  if Root <> '' then
    for i := 0 to FFrames.Count - 1 do
      if SameFileName(ExcludeTrailingPathDelimiter(Frames[i].RepoRoot),
        ExcludeTrailingPathDelimiter(Root)) then
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
begin
  { gittan [file | folder], else the repository of the last run. }
  if not FActive.IsBlank then
    { opened already }
  else if StartRepository <> '' then
    OpenRepository(StartRepository)
  else if ParamCount > 0 then
    FActive.OpenFile(ParamStr(1));
  { After the repository, whose opening clears the banners. }
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
begin
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

{$IFDEF LCLCocoa}
procedure TGittanWindow.ToolbarName(Sender: TObject);
begin
  FActive.ShowCommandsPage;
end;
{$ENDIF}

end.
