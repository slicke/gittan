unit gittan.app;

{** What every repository Gittan shows shares, one of each per process:
  the settings, the lexers, the application icon and the check for a
  newer build. The window creates it first thing (CreateApp) and frees it
  last (FreeApp); everything else reaches it through App.

  The settings are read as it is created, and the git they name is the
  one run from then on (SetGitExe). The lexers are created but not
  loaded: the window loads them, since it says so when there are none,
  and takes OnLoaded.

  The check for a newer build (gittan.update) starts UpdateFirstCheck ms
  after creation and then every UpdatePoll ms, in a build with a number
  only; CheckForUpdate starts one at once (Tools > Check for Updates).
  OnUpdateChecked tells the window when one ends, whether the menu asked
  for it, and the result is in UpdateOk, UpdateError, UpdateRelease and
  HasUpdate. UpdateDue is whether the badge shows: a newer build and no
  snooze ahead (SnoozeUpdate). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, ExtCtrls, gittan.settings, gittan.lexers,
  gittan.update, gittan.git, gittan.forge;

const
  {** A check for a newer build a little after start, then this far
    apart; ms. Remind Me Later waits UpdateSnoozeDays. }
  UpdateFirstCheck = 5000;
  UpdatePoll = 6 * 60 * 60 * 1000;
  UpdateSnoozeDays = 14;

type
  {** A check for a newer build ended; AManual when the menu asked for it. }
  TGittanUpdateCheckedEvent = procedure(Sender: TObject; AManual: boolean) of object;

  { TGittanApp }

  TGittanApp = class
  private
    FSettings: TGittanSettings;
    FLexers: TGittanLexers;
    FIcon: TIcon;
    { The check under way, the last one done (freed by the next or on
      the way out, since it is still in its thread as it reports), the
      timer that starts the next, whether the menu asked for the one
      under way, and the latest result. }
    FUpdateJob, FDoneUpdateJob: TGittanUpdateJob;
    FUpdateTimer: TTimer;
    FUpdateManual, FUpdateOk, FHasUpdate: boolean;
    FUpdateError: string;
    FUpdateRelease: TGittanRelease;
    FOnUpdateChecked: TGittanUpdateCheckedEvent;
    procedure UpdateTimerTimer(Sender: TObject);
    procedure UpdateJobDone(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    {** Starts a check for a newer build unless one is under way, which
      then answers the menu too when AManual. }
    procedure CheckForUpdate(AManual: boolean);
    {** Whether the badge for a newer build shows: there is one, and
      Remind Me Later was not chosen less than UpdateSnoozeDays ago. }
    function UpdateDue: boolean;
    {** Remind Me Later: no badge for UpdateSnoozeDays. }
    procedure SnoozeUpdate;
    {** The path of the tool of AForge (ForgeClass when nil; gh), as the
      settings give it: its ForgeCliPath when set, else the one on the
      search path; '' while the hosting features are off or its tool is
      not found, and for no forge. Whoever needs the forge makes one of it and keeps it while
      the path stays the same. }
    function ForgeCli(AForge: TGittanForgeClass = nil): string;
    property Settings: TGittanSettings read FSettings;
    property Lexers: TGittanLexers read FLexers;
    {** The application icon at every size (MAINICON), nil when the
      resource cannot be read. Application.Icon keeps to its small
      image. }
    property Icon: TIcon read FIcon;
    {** The last check got an answer; else UpdateError says why. }
    property UpdateOk: boolean read FUpdateOk;
    property UpdateError: string read FUpdateError;
    {** The latest release, from the last check that got an answer. }
    property UpdateRelease: TGittanRelease read FUpdateRelease;
    {** The latest release is newer than this build. }
    property HasUpdate: boolean read FHasUpdate;
    property OnUpdateChecked: TGittanUpdateCheckedEvent
      read FOnUpdateChecked write FOnUpdateChecked;
  end;

{** The one TGittanApp, nil before CreateApp and after FreeApp. }
function App: TGittanApp;
procedure CreateApp;
procedure FreeApp;

implementation

var
  TheApp: TGittanApp;

function App: TGittanApp;
begin
  Result := TheApp;
end;

procedure CreateApp;
begin
  if TheApp = nil then
    TheApp := TGittanApp.Create;
end;

procedure FreeApp;
begin
  FreeAndNil(TheApp);
end;

constructor TGittanApp.Create;
begin
  inherited Create;
  FSettings := TGittanSettings.Create;
  FSettings.Load;
  SetGitExe(FSettings.GitPath);
  FLexers := TGittanLexers.Create;
  FIcon := TIcon.Create;
  try
    FIcon.LoadFromResourceName(HInstance, 'MAINICON');
  except
    FreeAndNil(FIcon);
  end;
  { A local build has no number to compare, so only the menu checks. }
  FUpdateTimer := TTimer.Create(nil);
  FUpdateTimer.Interval := UpdateFirstCheck;
  FUpdateTimer.OnTimer := @UpdateTimerTimer;
  FUpdateTimer.Enabled := CurrentBuild >= 0;
end;

destructor TGittanApp.Destroy;
begin
  FreeAndNil(FUpdateTimer);
  FOnUpdateChecked := nil;
  if FUpdateJob <> nil then
    FUpdateJob.Stop(False);
  { Waits for a check still in its thread. }
  FreeAndNil(FUpdateJob);
  FreeAndNil(FDoneUpdateJob);
  FreeAndNil(FIcon);
  FreeAndNil(FLexers);
  FreeAndNil(FSettings);
  inherited Destroy;
end;

procedure TGittanApp.CheckForUpdate(AManual: boolean);
begin
  FUpdateManual := FUpdateManual or AManual;
  if FUpdateJob <> nil then
    Exit;
  FUpdateTimer.Enabled := False;
  FreeAndNil(FDoneUpdateJob);
  FUpdateJob := TGittanUpdateJob.Create;
  FUpdateJob.OnDone := @UpdateJobDone;
  FUpdateJob.Start;
end;

procedure TGittanApp.UpdateTimerTimer(Sender: TObject);
begin
  FUpdateTimer.Enabled := False;
  CheckForUpdate(False);
end;

procedure TGittanApp.UpdateJobDone(Sender: TObject);
var
  Job: TGittanUpdateJob;
  Manual: boolean;
begin
  Job := TGittanUpdateJob(Sender);
  if Job <> FUpdateJob then
    Exit;
  FUpdateJob := nil;
  FDoneUpdateJob := Job;
  Manual := FUpdateManual;
  FUpdateManual := False;
  if CurrentBuild >= 0 then
  begin
    FUpdateTimer.Interval := UpdatePoll;
    FUpdateTimer.Enabled := True;
  end;
  FUpdateOk := Job.Ok;
  FUpdateError := Job.Error;
  if Job.Ok then
  begin
    FUpdateRelease := Job.Release;
    FHasUpdate := IsNewerRelease(FUpdateRelease, CurrentBuild);
  end;
  if Assigned(FOnUpdateChecked) then
    FOnUpdateChecked(Self, Manual);
end;

function TGittanApp.UpdateDue: boolean;
begin
  Result := FHasUpdate and (Date >= FSettings.UpdateSnoozedUntil);
end;

procedure TGittanApp.SnoozeUpdate;
begin
  FSettings.UpdateSnoozedUntil := Date + UpdateSnoozeDays;
end;

function TGittanApp.ForgeCli(AForge: TGittanForgeClass): string;
begin
  if AForge = nil then
    AForge := ForgeClass;
  if (AForge = nil) or not FSettings.HostingEnabled then
    Result := ''
  else if FSettings.ForgeCliPath(AForge.Name) <> '' then
    Result := FSettings.ForgeCliPath(AForge.Name)
  else
    Result := FindTool(AForge.CliName);
end;

end.
