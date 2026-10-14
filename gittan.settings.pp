unit gittan.settings;

{** What Gittan remembers between runs: the window, the tree width, the
  last and recent repositories, and the view options. The settings live in
  one ini file in the user's configuration folder (GetAppConfigDir), so a
  broken file costs nothing but the defaults. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  {** How many repositories File > Open Recent lists. }
  MaxRecent = 10;

type

  { TGittanSettings }

  TGittanSettings = class
  private
    FRecent: TStringList;
    FFileName: string;
  public
    {** The window bounds, or a zero Width when none were saved. }
    Left, Top, Width, Height: integer;
    Maximized: boolean;
    {** The width of the file tree, 0 for the default. }
    TreeWidth: integer;
    {** The editor font; an empty name keeps the default. }
    FontName: string;
    FontSize: integer;
    {** The editor's font scale in percent, 0 for the default. }
    Zoom: integer;
    WordWrap: boolean;
    {** Hide the unchanged lines of a file, keeping ContextLines around
      each change. }
    OnlyChanges: boolean;
    ContextLines: integer;
    SideBySide: boolean;
    {** Leave whitespace changes out of every diff. }
    IgnoreWhitespace: boolean;
    {** Show in the gutter who last changed each line. }
    Blame: boolean;
    {** Command that opens a file from the context menu, with the path
      appended; empty opens it with the desktop's default application. }
    EditorCommand: string;
    {** Command that opens a terminal, with the repository root appended;
      empty opens the platform's default terminal. }
    TerminalCommand: string;
    {** AFileName names the ini file; empty picks gittan.ini in the
      user's configuration folder. }
    constructor Create(const AFileName: string = '');
    destructor Destroy; override;
    {** Reads the file; missing keys keep their defaults. }
    procedure Load;
    {** Writes the file, creating its folder. Errors are ignored: a read
      only home must not stop the program from closing. }
    procedure Save;
    {** Puts ARoot first in the recent list, dropping a duplicate and the
      oldest beyond MaxRecent. }
    procedure AddRecent(const ARoot: string);
    {** The recently opened repositories, newest first. }
    property Recent: TStringList read FRecent;
    {** The ini file the settings are read from and written to. }
    property FileName: string read FFileName;
  end;

implementation

uses
  IniFiles;

const
  SecWindow = 'Window';
  SecView = 'View';
  SecRecent = 'Recent';

{ TGittanSettings }

constructor TGittanSettings.Create(const AFileName: string);
begin
  inherited Create;
  FRecent := TStringList.Create;
  FRecent.CaseSensitive := True;
  if AFileName <> '' then
    FFileName := AFileName
  else
    FFileName := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'gittan.ini';
  ContextLines := 3;
end;

destructor TGittanSettings.Destroy;
begin
  FRecent.Free;
  inherited Destroy;
end;

procedure TGittanSettings.Load;
var
  Ini: TIniFile;
  i: integer;
  S: string;
begin
  if not FileExists(FFileName) then
    Exit;
  try
    Ini := TIniFile.Create(FFileName);
    try
      Left := Ini.ReadInteger(SecWindow, 'Left', 0);
      Top := Ini.ReadInteger(SecWindow, 'Top', 0);
      Width := Ini.ReadInteger(SecWindow, 'Width', 0);
      Height := Ini.ReadInteger(SecWindow, 'Height', 0);
      Maximized := Ini.ReadBool(SecWindow, 'Maximized', False);
      TreeWidth := Ini.ReadInteger(SecWindow, 'TreeWidth', 0);
      FontName := Ini.ReadString(SecView, 'FontName', '');
      FontSize := Ini.ReadInteger(SecView, 'FontSize', 0);
      Zoom := Ini.ReadInteger(SecView, 'Zoom', 0);
      WordWrap := Ini.ReadBool(SecView, 'WordWrap', False);
      OnlyChanges := Ini.ReadBool(SecView, 'OnlyChanges', False);
      ContextLines := Ini.ReadInteger(SecView, 'ContextLines', 3);
      SideBySide := Ini.ReadBool(SecView, 'SideBySide', False);
      IgnoreWhitespace := Ini.ReadBool(SecView, 'IgnoreWhitespace', False);
      Blame := Ini.ReadBool(SecView, 'Blame', False);
      EditorCommand := Ini.ReadString(SecView, 'EditorCommand', '');
      TerminalCommand := Ini.ReadString(SecView, 'TerminalCommand', '');
      FRecent.Clear;
      for i := 0 to MaxRecent - 1 do
      begin
        S := Ini.ReadString(SecRecent, 'Repo' + IntToStr(i), '');
        if S <> '' then
          FRecent.Add(S);
      end;
    finally
      Ini.Free;
    end;
  except
    { A damaged file is treated as none. }
  end;
end;

procedure TGittanSettings.Save;
var
  Ini: TIniFile;
  i: integer;
begin
  try
    ForceDirectories(ExtractFileDir(FFileName));
    Ini := TIniFile.Create(FFileName);
    try
      Ini.WriteInteger(SecWindow, 'Left', Left);
      Ini.WriteInteger(SecWindow, 'Top', Top);
      Ini.WriteInteger(SecWindow, 'Width', Width);
      Ini.WriteInteger(SecWindow, 'Height', Height);
      Ini.WriteBool(SecWindow, 'Maximized', Maximized);
      Ini.WriteInteger(SecWindow, 'TreeWidth', TreeWidth);
      Ini.WriteString(SecView, 'FontName', FontName);
      Ini.WriteInteger(SecView, 'FontSize', FontSize);
      Ini.WriteInteger(SecView, 'Zoom', Zoom);
      Ini.WriteBool(SecView, 'WordWrap', WordWrap);
      Ini.WriteBool(SecView, 'OnlyChanges', OnlyChanges);
      Ini.WriteInteger(SecView, 'ContextLines', ContextLines);
      Ini.WriteBool(SecView, 'SideBySide', SideBySide);
      Ini.WriteBool(SecView, 'IgnoreWhitespace', IgnoreWhitespace);
      Ini.WriteBool(SecView, 'Blame', Blame);
      Ini.WriteString(SecView, 'EditorCommand', EditorCommand);
      Ini.WriteString(SecView, 'TerminalCommand', TerminalCommand);
      Ini.EraseSection(SecRecent);
      for i := 0 to FRecent.Count - 1 do
        Ini.WriteString(SecRecent, 'Repo' + IntToStr(i), FRecent[i]);
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
  except
    { Nothing to do; the next run starts with what was saved before. }
  end;
end;

procedure TGittanSettings.AddRecent(const ARoot: string);
var
  i: integer;
begin
  i := FRecent.IndexOf(ARoot);
  if i >= 0 then
    FRecent.Delete(i);
  FRecent.Insert(0, ARoot);
  while FRecent.Count > MaxRecent do
    FRecent.Delete(FRecent.Count - 1);
end;

end.
