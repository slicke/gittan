unit gittan.cli;

{** Tools > Install CLI Command: a `gittan` command for the terminal that
  opens a folder or file in Gittan, the current folder when none is given.
  It is a small script that starts the Gittan it was installed from:

  - macOS: /usr/local/bin/gittan runs `open -a` on the bundle, so a running
    Gittan opens the path (Cocoa delivers it to the form's OnDropFiles).
    /usr/local/bin needs an administrator on a fresh system; the copy then
    goes through `osascript ... with administrator privileges`.
  - Windows: gittan.cmd in %LOCALAPPDATA%\Gittan\bin, which is added to
    the user's PATH.
  - Elsewhere: ~/.local/bin/gittan starts the executable in the background.

  The script names the executable by its full path, so installing again
  after moving Gittan updates it. It carries a marker line, and a `gittan`
  without it is never replaced or removed: that one is someone else's.
  Tools > Uninstall CLI Command removes the script (and on Windows the
  folder from the PATH). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils
  {$IFDEF DARWIN}, Process{$ENDIF}
  {$IFDEF WINDOWS}, Windows, Registry{$ELSE}, BaseUnix{$ENDIF};

{** AText in single quotes for sh, a quote inside closed and escaped. }
function ShellQuote(const AText: string): string;

{** The macOS script, which opens ABundle (the .app) with `open -a`. }
function MacCliScript(const ABundle: string): string;

{** The Unix script, which starts AExe in the background. }
function UnixCliScript(const AExe: string): string;

{** The Windows batch file, which starts AExe with `start`. }
function WindowsCliScript(const AExe: string): string;

{** Whether ADir is one of the folders of APath, a PATH value separated by
  ASep. Trailing separators and, with AIgnoreCase, case do not count. }
function PathListHas(const APath, ADir: string; ASep: char;
  AIgnoreCase: boolean): boolean;

{** APath without the folder ADir, compared as PathListHas does; the
  other folders stay as they are, in their order. }
function PathListRemove(const APath, ADir: string; ASep: char;
  AIgnoreCase: boolean): string;

{** Where the command is installed on this platform. }
function CliInstallPath: string;

{** Whether AFile is a script Install CLI Command wrote (it carries the
  marker line near the top). }
function IsGittanScript(const AFile: string): boolean;

{** Whether the command is installed: a script of Gittan's at
  CliInstallPath. }
function CliInstalled: boolean;

{** Installs the command for the executable AExe. Answers whether it
  worked, with what to tell the user in AMessage either way. }
function InstallCli(const AExe: string; out AMessage: string): boolean;

{** Removes the command. Answers whether it worked, with what to tell the
  user in AMessage either way. }
function UninstallCli(out AMessage: string): boolean;

implementation

const
  Marker = 'Installed by Gittan (Tools > Install CLI Command).';

function ShellQuote(const AText: string): string;
begin
  Result := '''' + StringReplace(AText, '''', '''\''''', [rfReplaceAll]) + '''';
end;

function MacCliScript(const ABundle: string): string;
begin
  Result := '#!/bin/sh' + LineEnding +
    '# ' + Marker + LineEnding +
    '# gittan [folder | file] opens it in Gittan, the current folder by default.' + LineEnding +
    '[ $# -eq 0 ] && set -- "$PWD"' + LineEnding +
    'exec open -a ' + ShellQuote(ABundle) + ' "$@"' + LineEnding;
end;

function UnixCliScript(const AExe: string): string;
begin
  Result := '#!/bin/sh' + LineEnding +
    '# ' + Marker + LineEnding +
    '# gittan [folder | file] opens it in Gittan, the current folder by default.' + LineEnding +
    '[ $# -eq 0 ] && set -- "$PWD"' + LineEnding +
    'nohup ' + ShellQuote(AExe) + ' "$@" >/dev/null 2>&1 &' + LineEnding;
end;

{ cmd expands %...% in the path too, so a percent sign is doubled. The
  argument check jumps rather than using a parenthesized block, which a
  parenthesis in the path (Program Files (x86)) would close. }
function WindowsCliScript(const AExe: string): string;
var
  Exe: string;
begin
  Exe := '"' + StringReplace(AExe, '%', '%%', [rfReplaceAll]) + '"';
  Result := '@echo off'#13#10 +
    'rem ' + Marker + #13#10 +
    'rem gittan [folder | file] opens it in Gittan, the current folder by default.'#13#10 +
    'if not "%~1"=="" goto args'#13#10 +
    'start "" ' + Exe + ' "%CD%"'#13#10 +
    'goto :eof'#13#10 +
    ':args'#13#10 +
    'start "" ' + Exe + ' %*'#13#10;
end;

function SameDir(const A, B: string; AIgnoreCase: boolean): boolean;
begin
  if AIgnoreCase then
    Result := SameText(ExcludeTrailingPathDelimiter(A), ExcludeTrailingPathDelimiter(B))
  else
    Result := ExcludeTrailingPathDelimiter(A) = ExcludeTrailingPathDelimiter(B);
end;

function PathListHas(const APath, ADir: string; ASep: char;
  AIgnoreCase: boolean): boolean;
var
  S: string;
begin
  for S in APath.Split([ASep]) do
    if SameDir(S, ADir, AIgnoreCase) then
      Exit(True);
  Result := False;
end;

function PathListRemove(const APath, ADir: string; ASep: char;
  AIgnoreCase: boolean): string;
var
  S: string;
begin
  Result := '';
  for S in APath.Split([ASep]) do
    if not SameDir(S, ADir, AIgnoreCase) then
    begin
      if Result <> '' then
        Result := Result + ASep;
      Result := Result + S;
    end;
end;

function CliInstallPath: string;
begin
  {$IF DEFINED(DARWIN)}
  Result := '/usr/local/bin/gittan';
  {$ELSEIF DEFINED(WINDOWS)}
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('LOCALAPPDATA')) +
    'Gittan\bin\gittan.cmd';
  {$ELSE}
  Result := IncludeTrailingPathDelimiter(GetUserDir) + '.local/bin/gittan';
  {$ENDIF}
end;

function IsGittanScript(const AFile: string): boolean;
var
  F: TFileStream;
  Head: string;
begin
  Result := False;
  try
    F := TFileStream.Create(AFile, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Head, 512);
      SetLength(Head, F.Read(Head[1], Length(Head)));
      Result := Pos(Marker, Head) > 0;
    finally
      F.Free;
    end;
  except
    on Exception do
      Result := False;
  end;
end;

function CliInstalled: boolean;
begin
  Result := IsGittanScript(CliInstallPath);
end;

{ Whether ATarget is someone else's gittan, which is left alone; AMessage
  then says so. }
function Foreign(const ATarget: string; out AMessage: string): boolean;
begin
  Result := FileExists(ATarget) and not IsGittanScript(ATarget);
  if Result then
    AMessage := ATarget + ' was not installed by Gittan; it is left as it is.'
  else
    AMessage := '';
end;

{ Writes AText to AFile as it is, with no line ending conversion. }
function WriteText(const AFile, AText: string): boolean;
var
  F: TFileStream;
begin
  Result := False;
  try
    F := TFileStream.Create(AFile, fmCreate);
    try
      if AText <> '' then
        F.WriteBuffer(AText[1], Length(AText));
    finally
      F.Free;
    end;
    {$IFNDEF WINDOWS}
    FpChmod(AFile, &755);
    {$ENDIF}
    Result := True;
  except
    on Exception do
      Result := False;
  end;
end;

{$IF DEFINED(DARWIN)}
{ AText as an AppleScript string literal. }
function AppleScriptString(const AText: string): string;
begin
  Result := '"' + StringReplace(StringReplace(AText, '\', '\\', [rfReplaceAll]),
    '"', '\"', [rfReplaceAll]) + '"';
end;

{ Runs ACmd through sh as an administrator; macOS asks for the password. }
function RunAsAdmin(const ACmd: string; out AOutput: string): boolean;
begin
  Result := RunCommand('/usr/bin/osascript',
    ['-e', 'do shell script ' + AppleScriptString(ACmd) +
    ' with administrator privileges'], AOutput, [poStderrToOutPut]);
  AOutput := Trim(AOutput);
end;

{ The bundle around AExe (…/Gittan.app/Contents/MacOS/Gittan), or ''. }
function BundleOf(const AExe: string): string;
var
  i: integer;
begin
  i := Pos('.app/Contents/MacOS/', AExe);
  if i = 0 then
    Result := ''
  else
    Result := Copy(AExe, 1, i + 3);
end;

function InstallCli(const AExe: string; out AMessage: string): boolean;
var
  Bundle, Script, Target, Temp, Output, Cmd: string;
begin
  Target := CliInstallPath;
  Bundle := BundleOf(AExe);
  { Run from a disk image, or translocated by Gatekeeper because it was
    never moved, the path is gone once the image is ejected. }
  if (Pos('/AppTranslocation/', AExe) > 0) or (Copy(AExe, 1, 9) = '/Volumes/') then
  begin
    AMessage := 'Move Gittan to the Applications folder and start it from there, ' +
      'then install the command.';
    Exit(False);
  end;
  if Foreign(Target, AMessage) then
    Exit(False);
  if Bundle <> '' then
    Script := MacCliScript(Bundle)
  else
    Script := UnixCliScript(AExe);
  if not (DirectoryExists(ExtractFileDir(Target)) and WriteText(Target, Script)) then
  begin
    { /usr/local/bin belongs to root: copy as an administrator. }
    Temp := GetTempFileName(GetTempDir, 'gittan');
    if not WriteText(Temp, Script) then
    begin
      AMessage := 'Could not write ' + Temp + '.';
      Exit(False);
    end;
    Cmd := 'mkdir -p ' + ShellQuote(ExtractFileDir(Target)) + ' && cp ' +
      ShellQuote(Temp) + ' ' + ShellQuote(Target) + ' && chmod 755 ' + ShellQuote(Target);
    Result := RunAsAdmin(Cmd, Output);
    DeleteFile(Temp);
    if not Result then
    begin
      AMessage := 'The command was not installed. ' + Output;
      Exit;
    end;
  end;
  AMessage := 'Installed ' + Target + '. Type gittan in a terminal to open the ' +
    'current folder, or gittan <folder> to open another.';
  Result := True;
end;

function UninstallCli(out AMessage: string): boolean;
var
  Target, Output: string;
begin
  Target := CliInstallPath;
  if Foreign(Target, AMessage) then
    Exit(False);
  if FileExists(Target) and not DeleteFile(Target) then
  begin
    { /usr/local/bin belongs to root: remove as an administrator. }
    if not RunAsAdmin('rm -f ' + ShellQuote(Target), Output) then
    begin
      AMessage := 'The command was not removed. ' + Output;
      Exit(False);
    end;
  end;
  AMessage := 'Removed ' + Target + '.';
  Result := True;
end;

{$ELSEIF DEFINED(WINDOWS)}
{ Adds ADir to the user's PATH, or with AAdd false removes it, and tells
  running programs; the terminals open already keep the old one. }
function ChangeUserPath(const ADir: string; AAdd: boolean): boolean;
var
  Reg: TRegistry;
  Path, NewPath: string;
  R: DWORD_PTR;
begin
  Result := False;
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKey('Environment', True) then
      Exit;
    if Reg.ValueExists('Path') then
      Path := Reg.ReadString('Path')
    else
      Path := '';
    if AAdd then
    begin
      NewPath := Path;
      if not PathListHas(Path, ADir, ';', True) then
      begin
        if (NewPath <> '') and (NewPath[Length(NewPath)] <> ';') then
          NewPath := NewPath + ';';
        NewPath := NewPath + ADir;
      end;
    end
    else
      NewPath := PathListRemove(Path, ADir, ';', True);
    if NewPath <> Path then
    begin
      Reg.WriteExpandString('Path', NewPath);
      SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
        LPARAM(PChar('Environment')), SMTO_ABORTIFHUNG, 5000, @R);
    end;
    Result := True;
  finally
    Reg.Free;
  end;
end;

function InstallCli(const AExe: string; out AMessage: string): boolean;
var
  Target: string;
begin
  Target := CliInstallPath;
  if Foreign(Target, AMessage) then
    Exit(False);
  Result := ForceDirectories(ExtractFileDir(Target)) and
    WriteText(Target, WindowsCliScript(AExe));
  if not Result then
  begin
    AMessage := 'Could not write ' + Target + '.';
    Exit;
  end;
  Result := ChangeUserPath(ExtractFileDir(Target), True);
  if Result then
    AMessage := 'Installed ' + Target + '. Open a new terminal and type gittan ' +
      'to open the current folder, or gittan <folder> to open another.'
  else
    AMessage := 'Installed ' + Target + ', but could not add ' +
      ExtractFileDir(Target) + ' to PATH.';
end;

{ The bin folder goes too when it is empty; the Gittan folder above it
  also holds the symbol index cache, so it stays. }
function UninstallCli(out AMessage: string): boolean;
var
  Target: string;
begin
  Target := CliInstallPath;
  if Foreign(Target, AMessage) then
    Exit(False);
  if FileExists(Target) and not DeleteFile(Target) then
  begin
    AMessage := 'Could not remove ' + Target + '.';
    Exit(False);
  end;
  RemoveDir(ExtractFileDir(Target));
  Result := ChangeUserPath(ExtractFileDir(Target), False);
  if Result then
    AMessage := 'Removed ' + Target + ' and its folder from PATH.'
  else
    AMessage := 'Removed ' + Target + ', but could not take ' +
      ExtractFileDir(Target) + ' off PATH.';
end;

{$ELSE}
function InstallCli(const AExe: string; out AMessage: string): boolean;
var
  Target: string;
begin
  Target := CliInstallPath;
  if Foreign(Target, AMessage) then
    Exit(False);
  Result := ForceDirectories(ExtractFileDir(Target)) and
    WriteText(Target, UnixCliScript(AExe));
  if not Result then
  begin
    AMessage := 'Could not write ' + Target + '.';
    Exit;
  end;
  AMessage := 'Installed ' + Target + '. Type gittan in a terminal to open the ' +
    'current folder, or gittan <folder> to open another.';
  if not PathListHas(GetEnvironmentVariable('PATH'), ExtractFileDir(Target), ':', False) then
    AMessage := AMessage + LineEnding + LineEnding + ExtractFileDir(Target) +
      ' is not on the PATH Gittan was started with. If the shell does not ' +
      'find gittan, add it in your shell profile:' + LineEnding +
      'export PATH="$HOME/.local/bin:$PATH"';
end;

function UninstallCli(out AMessage: string): boolean;
var
  Target: string;
begin
  Target := CliInstallPath;
  if Foreign(Target, AMessage) then
    Exit(False);
  Result := not FileExists(Target) or DeleteFile(Target);
  if Result then
    AMessage := 'Removed ' + Target + '.'
  else
    AMessage := 'Could not remove ' + Target + '.';
end;
{$ENDIF}

end.
