; Inno Setup script for Gittan: Gittan-windows-x64-setup.exe.
;
; Built by CI after the Windows build, from the repository's root:
;   ISCC.exe dist\windows\gittan.iss
; It packs Gittan.exe and lexlib\ as the build left them and writes the
; installer beside them. The version is the executable's own (Gittan.lpi's
; Major.Minor and the build number CI stamps in as RevisionNr), so it
; matches the packages of the other platforms; /DAppVersion=... overrides it.
;
; Installs for the current user by default (no administrator), with a dialog
; to install for everyone. The settings, the index and Install CLI Command's
; script live in the user's AppData, so either works. The tasks: a desktop
; icon, Open in Gittan on a folder's and a folder background's context menu,
; and gittan.cmd on the PATH.

#define AppName "Gittan"
#define AppPublisher "Björn Lindh"
#define AppURL "https://gittan.app"
#define AppExeName "Gittan.exe"

#ifndef AppVersion
  ; 0.9.123.0 from the version resource, without the fourth number.
  #define ExeVersion GetVersionNumbersString(AddBackslash(SourcePath) + "..\..\" + AppExeName)
  #if ExeVersion == ""
    #define AppVersion "0.0.0"
  #else
    #define AppVersion Copy(ExeVersion, 1, RPos(".", ExeVersion) - 1)
  #endif
#endif

[Setup]
; Never change the AppId: it is how an upgrade finds the installed Gittan.
AppId={{45266703-8240-47CF-8139-A07BE7222BCC}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL=https://github.com/slicke/gittan/issues
AppUpdatesURL=https://github.com/slicke/gittan/releases/latest
SourceDir=..\..
OutputDir=.
OutputBaseFilename=Gittan-windows-x64-setup
DefaultDirName={autopf}\{#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
SetupIconFile=Gittan.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
WizardStyle=modern
SolidCompression=yes
; An upgrade closes a running Gittan rather than failing on a file in use.
CloseApplications=yes
RestartApplications=no
; The PATH task changes the environment; tell running programs.
ChangesEnvironment=yes
VersionInfoVersion={#AppVersion}
VersionInfoProductVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} Setup
VersionInfoProductName={#AppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "contextmenu"; Description: "Add ""Open in Gittan"" to the context menu of folders"; GroupDescription: "Integration:"
Name: "addtopath"; Description: "Add the gittan command to the PATH"; GroupDescription: "Integration:"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
; lexlib\ is replaced as a whole, so a lexer dropped upstream goes too.
Source: "lexlib\*"; DestDir: "{app}\lexlib"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "dist\windows\gittan.cmd"; DestDir: "{app}\bin"; Flags: ignoreversion
; GPLv3 wants the license with the binary.
Source: "LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion

[InstallDelete]
Type: filesandordirs; Name: "{app}\lexlib"

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Registry]
; HKA is HKCU\Software\Classes for a user's install and HKLM's for everyone.
; Gittan opens the folder its first argument names. Windows 11 lists these
; under Show more options.
Root: HKA; Subkey: "Software\Classes\Directory\shell\Gittan"; ValueType: string; ValueName: ""; ValueData: "Open in Gittan"; Flags: uninsdeletekey; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Directory\shell\Gittan"; ValueType: string; ValueName: "Icon"; ValueData: """{app}\{#AppExeName}"",0"; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Directory\shell\Gittan\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%V"""; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\Gittan"; ValueType: string; ValueName: ""; ValueData: "Open in Gittan"; Flags: uninsdeletekey; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\Gittan"; ValueType: string; ValueName: "Icon"; ValueData: """{app}\{#AppExeName}"",0"; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\Gittan\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%V"""; Tasks: contextmenu

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
// {app}\bin on the PATH: the user's for a user's install, the system's for
// everyone's. Added after the files when the task is chosen, taken out
// again when an upgrade leaves it unchosen and when Gittan is removed. The
// context menu's keys go the same way when its task is left unchosen.
const
  UserEnvKey = 'Environment';
  SystemEnvKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';

function EnvRoot: Integer;
begin
  if IsAdminInstallMode then
    Result := HKLM
  else
    Result := HKCU;
end;

function EnvKey: string;
begin
  if IsAdminInstallMode then
    Result := SystemEnvKey
  else
    Result := UserEnvKey;
end;

function ClassesRoot: Integer;
begin
  if IsAdminInstallMode then
    Result := HKLM
  else
    Result := HKCU;
end;

procedure AddToPath(const ADir: string);
var
  Path: string;
begin
  if not RegQueryStringValue(EnvRoot, EnvKey, 'Path', Path) then
    Path := '';
  if Pos(';' + Uppercase(ADir) + ';', ';' + Uppercase(Path) + ';') > 0 then
    Exit;
  if (Path <> '') and (Path[Length(Path)] <> ';') then
    Path := Path + ';';
  RegWriteExpandStringValue(EnvRoot, EnvKey, 'Path', Path + ADir);
end;

procedure RemoveFromPath(const ADir: string);
var
  Path: string;
  P: Integer;
begin
  if not RegQueryStringValue(EnvRoot, EnvKey, 'Path', Path) then
    Exit;
  Path := ';' + Path + ';';
  P := Pos(';' + Uppercase(ADir) + ';', Uppercase(Path));
  if P = 0 then
    Exit;
  Delete(Path, P, Length(ADir) + 1);
  Path := Copy(Path, 2, Length(Path) - 2);
  RegWriteExpandStringValue(EnvRoot, EnvKey, 'Path', Path);
end;

procedure RemoveContextMenu;
begin
  RegDeleteKeyIncludingSubkeys(ClassesRoot, 'Software\Classes\Directory\shell\Gittan');
  RegDeleteKeyIncludingSubkeys(ClassesRoot, 'Software\Classes\Directory\Background\shell\Gittan');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if WizardIsTaskSelected('addtopath') then
      AddToPath(ExpandConstant('{app}\bin'))
    else
      RemoveFromPath(ExpandConstant('{app}\bin'));
    if not WizardIsTaskSelected('contextmenu') then
      RemoveContextMenu;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    RemoveFromPath(ExpandConstant('{app}\bin'));
end;
