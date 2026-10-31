unit gittan.ext.loader;

{** Finds the extensions and loads them into the engine: every *.js in
  the extensions folder (TGittanSettings.ExtensionsDir), in the order
  of their names, each with its manifest read (gittan.ext.perm), its
  permissions granted or asked for (gittan.ext.grant), its own context
  made and provisioned (OnProvision registers Gittan's natives in it)
  and its script run. What was found, loaded or not, is in Infos for
  the settings dialog: an extension turned off there is listed and
  skipped, one whose manifest is wrong or whose script failed lists why.
  Reload unloads every context and loads again, so an edited file
  is picked up. Nothing here needs the LCL; the host reports the
  errors. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.ext.engine, gittan.ext.perm, gittan.settings;

type
  {** One extension file as found: its manifest, what it asked for and
    got, and whether it runs. }
  TGittanExtInfo = record
    {** ExtIdFromPath: the file's name without .js, in lower case. }
    Id: string;
    FileName: string;
    DisplayName, Author, Version, Description, Homepage, License: string;
    Requested, Granted: TExtPermSet;
    {** On in the settings. }
    Enabled: boolean;
    {** Has a context in the engine now. }
    Loaded: boolean;
    {** Why it is not loaded, when it is on and is not. }
    Error: string;
    Hash: string;
  end;
  TGittanExtInfos = array of TGittanExtInfo;

  {** Registers the natives of the host program in AExt's context, called
    between the engine's BeginRegistration and EndRegistration. }
  TGittanExtProvision = procedure(AEngine: TGittanExtEngine; AExt: PExtContextInfo) of object;

  { TGittanExtLoader }

  TGittanExtLoader = class
  private
    FSettings: TGittanSettings;
    FInfos: TGittanExtInfos;
    FOnProvision: TGittanExtProvision;
    FLoading: boolean;
    procedure LoadOne(const AFileName: string; ASeen: TStrings);
  public
    constructor Create(ASettings: TGittanSettings);
    {** The folder the extensions are read from, made when missing. }
    function Dir: string;
    {** Loads the extensions of Dir into the engine (made when there is
      none yet). Those loaded before stay: call Unload or Reload first
      for a fresh start. }
    procedure Load;
    {** Unloads every extension and loads the folder again. }
    procedure Reload;
    {** Unloads every extension; Infos is emptied. }
    procedure Unload;
    function Count: integer;
    function Info(AIndex: integer): TGittanExtInfo;
    function FindInfo(const AId: string; out AInfo: TGittanExtInfo): boolean;
    {** What registers the host's natives in each context. }
    property OnProvision: TGittanExtProvision read FOnProvision write FOnProvision;
    {** True while Load runs, so a host that rebuilds its menus on every
      registered command can wait for the end. }
    property Loading: boolean read FLoading;
    property Settings: TGittanSettings read FSettings;
  end;

implementation

uses
  gittan.ext.host, gittan.ext.grant, gittan.textfile;

resourcestring
  rsExtReadFailed = 'The extension file could not be read';
  rsExtInvalidManifest = 'The manifest of %s is not valid';
  rsExtDupId = 'The extension file "%s" was not loaded: apart from letter case, its name matches "%s", so both would share the same settings and permissions. Rename one of the files.';
  rsExtDenied = 'The permissions it asks for were not granted';
  rsExtOff = 'Turned off';
  rsExtNoEngine = 'The extension engine could not be started';

constructor TGittanExtLoader.Create(ASettings: TGittanSettings);
begin
  inherited Create;
  FSettings := ASettings;
end;

function TGittanExtLoader.Dir: string;
begin
  Result := FSettings.ExtensionsDir;
  ForceDirectories(Result);
end;

function TGittanExtLoader.Count: integer;
begin
  Result := Length(FInfos);
end;

function TGittanExtLoader.Info(AIndex: integer): TGittanExtInfo;
begin
  Result := FInfos[AIndex];
end;

function TGittanExtLoader.FindInfo(const AId: string; out AInfo: TGittanExtInfo): boolean;
var
  i: integer;
begin
  for i := 0 to High(FInfos) do
    if FInfos[i].Id = AId then
    begin
      AInfo := FInfos[i];
      Exit(True);
    end;
  AInfo := Default(TGittanExtInfo);
  Result := False;
end;

procedure TGittanExtLoader.LoadOne(const AFileName: string; ASeen: TStrings);
var
  Inf: TGittanExtInfo;
  Source: RawByteString;
  Manifest: TExtManifest;
  Engine: TGittanExtEngine;
  Ext: PExtContextInfo;
  Res: string;
  i: integer;
begin
  Inf := Default(TGittanExtInfo);
  Inf.FileName := AFileName;
  Inf.Id := ExtIdFromPath(AFileName);
  Inf.Enabled := FSettings.ExtEnabled(Inf.Id);
  try
    try
      Source := ReadFileBytes(AFileName);
    except
      Source := '';
      Inf.Error := rsExtReadFailed;
      ExtHost.ReportError(ExtractFileName(AFileName), rsExtReadFailed);
      Exit;
    end;
    Manifest := ParseExtManifest(string(Source));
    Inf.DisplayName := Manifest.DisplayName;
    Inf.Author := Manifest.Author;
    Inf.Version := Manifest.Version;
    Inf.Description := Manifest.Description;
    Inf.Homepage := Manifest.Homepage;
    Inf.License := Manifest.License;
    Inf.Requested := Manifest.Requested;
    Inf.Hash := HashScript(string(Source));
    if not Manifest.IsValid then
    begin
      Inf.Error := Manifest.ErrorMessage;
      ExtHost.ReportError(Format(rsExtInvalidManifest, [ExtractFileName(AFileName)]),
        Manifest.ErrorMessage);
      Exit;
    end;
    if Inf.DisplayName = '' then
      Inf.DisplayName := Inf.Id;
    { Ids are the names in lower case, so Test.js and test.js would share
      their settings and grants: the first wins. }
    i := ASeen.IndexOf(Inf.Id);
    if i >= 0 then
    begin
      Inf.Error := Format(rsExtDupId, [ExtractFileName(AFileName), ASeen.ValueFromIndex[i]]);
      ExtHost.ReportError(ExtractFileName(AFileName), Inf.Error);
      Exit;
    end;
    ASeen.Values[Inf.Id] := ExtractFileName(AFileName);
    if not Inf.Enabled then
    begin
      Inf.Error := rsExtOff;
      Exit;
    end;
    Inf.Granted := GrantPermissionsFor(Inf.Id, AFileName, Inf.Hash, Manifest, FSettings);
    if Inf.Granted = [] then
    begin
      Inf.Error := rsExtDenied;
      Exit;
    end;
    { The prompt ran the message loop; the program may be closing. }
    Engine := TGittanExtEngine.Existing;
    if Engine = nil then
      Engine := TGittanExtEngine.Instance;
    if Engine = nil then
    begin
      Inf.Error := rsExtNoEngine;
      Exit;
    end;
    Ext := Engine.NewExtensionContext(Inf.Id, AFileName, Inf.Hash, Inf.DisplayName,
      Inf.Author, Inf.Granted);
    if Ext = nil then
    begin
      Inf.Error := rsExtNoEngine;
      Exit;
    end;
    if Assigned(FOnProvision) then
    begin
      Engine.BeginRegistration(Ext);
      try
        FOnProvision(Engine, Ext);
      finally
        Engine.EndRegistration;
      end;
    end;
    Res := string(Engine.ExtExecuteFile(Ext));
    if Pos('Error:', Res) = 1 then
      { Reported by the engine as it happened. }
      Inf.Error := Copy(Res, 7, MaxInt).Trim
    else
      Inf.Loaded := True;
  finally
    SetLength(FInfos, Length(FInfos) + 1);
    FInfos[High(FInfos)] := Inf;
  end;
end;

procedure TGittanExtLoader.Load;
var
  Folder: string;
  Sr: TSearchRec;
  Files, Seen: TStringList;
  FileName: string;
begin
  Folder := IncludeTrailingPathDelimiter(Dir);
  Files := TStringList.Create;
  Seen := TStringList.Create;
  FLoading := True;
  try
    if FindFirst(Folder + '*.js', faAnyFile and not faDirectory, Sr) = 0 then
    try
      repeat
        if (Sr.Attr and faDirectory) = 0 then
          Files.Add(Folder + Sr.Name);
      until FindNext(Sr) <> 0;
    finally
      FindClose(Sr);
    end;
    { Case-sensitive, so "first file wins" among case twins is the same
      on every file system. }
    Files.CaseSensitive := True;
    Files.Sort;
    if (Files.Count > 0) and (TGittanExtEngine.Instance = nil) then
      Exit;
    for FileName in Files do
    begin
      if ExtHost.Terminated then
        Break;
      LoadOne(FileName, Seen);
    end;
  finally
    FLoading := False;
    Seen.Free;
    Files.Free;
    ExtHost.CommandsChanged;
  end;
end;

procedure TGittanExtLoader.Unload;
var
  Engine: TGittanExtEngine;
begin
  Engine := TGittanExtEngine.Existing;
  if Engine <> nil then
    Engine.UnloadExtensions;
  FInfos := nil;
  { Their cards go with them. }
  ExtHost.ClearCards('', '');
  ExtHost.CommandsChanged;
end;

procedure TGittanExtLoader.Reload;
begin
  Unload;
  Load;
end;

end.
