{ Ported from Trndi (https://github.com/slicke/trndi), GPL-3.0. }

unit gittan.ext.grant;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.ext.perm, gittan.settings;

{** Decide which permissions are granted for an extension before it is loaded.

    Storage (gittan.settings, section ExtPerm:<id>):
      Hash    - SHA-256 of the file contents that was last approved
      Granted - comma-separated promptable groups approved
      Author  - the manifest's author at that approval

    Flow:
      - If the file declares no promptable perms, return baseline silently.
      - If the stored hash matches the current hash, restore baseline + stored
        granted set (no prompt).
      - Otherwise, ask the host with the requested groups. On accept, save
        the hash and granted set and return baseline + requested. On deny,
        return [] so the caller skips loading the extension. ASettings nil
        asks every time and keeps nothing. }
function GrantPermissionsFor(const ExtId, FileName, Hash: string;
  const Manifest: TExtManifest; ASettings: TGittanSettings): TExtPermSet;

implementation

uses
  gittan.ext.host;

function GrantPermissionsFor(const ExtId, FileName, Hash: string;
  const Manifest: TExtManifest; ASettings: TGittanSettings): TExtPermSet;
var
  needed, stored: TExtPermSet;
  storedHash, title: string;
begin
  Result := PermBaseline;
  needed := Manifest.Requested * PermPromptable;

  // Nothing promptable requested: baseline only, no prompt.
  if needed = [] then
    Exit;

  // Restore previous decision when the file is unchanged.
  if ASettings <> nil then
  begin
    storedHash := ASettings.ExtPerm(ExtId, 'Hash');
    if (storedHash <> '') and (storedHash = Hash) then
    begin
      stored := CSVToPermSet(ASettings.ExtPerm(ExtId, 'Granted'));
      Result := PermBaseline + (stored * PermPromptable);
      Exit;
    end;
  end;

  // First load or file changed since last grant: ask the user.
  if Manifest.DisplayName <> '' then
    title := Manifest.DisplayName
  else
    title := ExtractFileName(FileName);

  if ExtHost.AskPermission(title, FileName, Manifest.Author, needed) then
  begin
    Result := PermBaseline + needed;
    if ASettings <> nil then
    begin
      ASettings.SetExtPerm(ExtId, 'Hash', Hash);
      ASettings.SetExtPerm(ExtId, 'Granted', PermSetToCSV(needed));
      ASettings.SetExtPerm(ExtId, 'Author', Manifest.Author);
    end;
  end
  else
    // Denied: skip loading; do not persist (re-ask next launch).
    Result := [];
end;

end.
