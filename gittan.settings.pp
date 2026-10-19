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
    {** Whether the Repository section under the tree is unfolded. }
    RepoFilesOpen: boolean;
    {** Whether the Submodules section under it is unfolded. }
    SubmodulesOpen: boolean;
    {** Whether the Commit section under the tree is unfolded. }
    CommitOpen: boolean;
    {** The commit message being written, kept until it is committed,
      and the repository it is for (its root): another repository's
      section starts empty. The message may have several lines. }
    CommitDraft, CommitDraftRepo: string;
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
    {** Show a Markdown file's preview beside the editor. }
    MarkdownPreview: boolean;
    {** Leave whitespace changes out of every diff. }
    IgnoreWhitespace: boolean;
    {** Show in the gutter who last changed each line. }
    Blame: boolean;
    {** Show the review comments of the pull request in the change view. }
    ReviewComments: boolean;
    {** Show a translation file (.po) as its originals beside its
      translations. }
    Translations: boolean;
    {** The name of the syntax theme (see gittan.syntaxthemes); empty for
      the default. }
    SyntaxTheme: string;
    {** Command that opens a file from the context menu, with the path
      appended; empty opens it with the desktop's default application. }
    EditorCommand: string;
    {** Command that opens a terminal, with the repository root appended;
      empty opens the platform's default terminal. }
    TerminalCommand: string;
    {** The day until which a newer Gittan is not pointed out, 0 for no
      such wait: Remind Me Later in the update dialog sets it. Kept as a
      date alone. }
    UpdateSnoozedUntil: TDateTime;
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
  SecUpdate = 'Update';
  SecCommit = 'Commit';
  ConfigFolder = 'Gittan';

{** The folder the ini file lives in. GetAppConfigDir names it after
  ApplicationName, which the LCL takes from Application.Title, a long name
  with an ampersand; this keeps its parent and names the folder Gittan
  whatever the title says. }
function ConfigDir: string;
begin
  Result := ExtractFilePath(ExcludeTrailingPathDelimiter(GetAppConfigDir(False)))
    + ConfigFolder;
end;

{ A day written yyyy-mm-dd, in no locale's format; 0 for anything else. }
function ReadDay(const AText: string): TDateTime;
begin
  if (Length(AText) <> 10) or not TryEncodeDate(StrToIntDef(Copy(AText, 1, 4), 0),
    StrToIntDef(Copy(AText, 6, 2), 0), StrToIntDef(Copy(AText, 9, 2), 0), Result) then
    Result := 0;
end;

{ An ini value is one line: a line end is written as \n, and so a
  backslash as \\. }
function EscapeLines(const AText: string): string;
begin
  Result := StringReplace(AText, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
end;

function UnescapeLines(const AText: string): string;
var
  i: integer;
begin
  Result := '';
  i := 1;
  while i <= Length(AText) do
  begin
    if (AText[i] = '\') and (i < Length(AText)) then
    begin
      Inc(i);
      if AText[i] = 'n' then
        Result := Result + #10
      else
        Result := Result + AText[i];
    end
    else
      Result := Result + AText[i];
    Inc(i);
  end;
end;

{ TGittanSettings }

constructor TGittanSettings.Create(const AFileName: string);
begin
  inherited Create;
  FRecent := TStringList.Create;
  FRecent.CaseSensitive := True;
  if AFileName <> '' then
    FFileName := AFileName
  else
    FFileName := IncludeTrailingPathDelimiter(ConfigDir) + 'gittan.ini';
  ContextLines := 3;
  SubmodulesOpen := True;
  CommitOpen := True;
  Translations := True;
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
      RepoFilesOpen := Ini.ReadBool(SecWindow, 'RepoFiles', False);
      SubmodulesOpen := Ini.ReadBool(SecWindow, 'Submodules', True);
      CommitOpen := Ini.ReadBool(SecWindow, 'Commit', True);
      CommitDraft := UnescapeLines(Ini.ReadString(SecCommit, 'Draft', ''));
      CommitDraftRepo := Ini.ReadString(SecCommit, 'Repo', '');
      FontName := Ini.ReadString(SecView, 'FontName', '');
      FontSize := Ini.ReadInteger(SecView, 'FontSize', 0);
      Zoom := Ini.ReadInteger(SecView, 'Zoom', 0);
      WordWrap := Ini.ReadBool(SecView, 'WordWrap', False);
      OnlyChanges := Ini.ReadBool(SecView, 'OnlyChanges', False);
      ContextLines := Ini.ReadInteger(SecView, 'ContextLines', 3);
      SideBySide := Ini.ReadBool(SecView, 'SideBySide', False);
      MarkdownPreview := Ini.ReadBool(SecView, 'MarkdownPreview', False);
      IgnoreWhitespace := Ini.ReadBool(SecView, 'IgnoreWhitespace', False);
      ReviewComments := Ini.ReadBool(SecView, 'ReviewComments', True);
      Translations := Ini.ReadBool(SecView, 'Translations', True);
      Blame := Ini.ReadBool(SecView, 'Blame', False);
      SyntaxTheme := Ini.ReadString(SecView, 'SyntaxTheme', '');
      EditorCommand := Ini.ReadString(SecView, 'EditorCommand', '');
      TerminalCommand := Ini.ReadString(SecView, 'TerminalCommand', '');
      UpdateSnoozedUntil := ReadDay(Ini.ReadString(SecUpdate, 'SnoozedUntil', ''));
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
      Ini.WriteBool(SecWindow, 'RepoFiles', RepoFilesOpen);
      Ini.WriteBool(SecWindow, 'Submodules', SubmodulesOpen);
      Ini.WriteBool(SecWindow, 'Commit', CommitOpen);
      if CommitDraft <> '' then
      begin
        Ini.WriteString(SecCommit, 'Draft', EscapeLines(CommitDraft));
        Ini.WriteString(SecCommit, 'Repo', CommitDraftRepo);
      end
      else
        Ini.EraseSection(SecCommit);
      Ini.WriteString(SecView, 'FontName', FontName);
      Ini.WriteInteger(SecView, 'FontSize', FontSize);
      Ini.WriteInteger(SecView, 'Zoom', Zoom);
      Ini.WriteBool(SecView, 'WordWrap', WordWrap);
      Ini.WriteBool(SecView, 'OnlyChanges', OnlyChanges);
      Ini.WriteInteger(SecView, 'ContextLines', ContextLines);
      Ini.WriteBool(SecView, 'SideBySide', SideBySide);
      Ini.WriteBool(SecView, 'MarkdownPreview', MarkdownPreview);
      Ini.WriteBool(SecView, 'IgnoreWhitespace', IgnoreWhitespace);
      Ini.WriteBool(SecView, 'ReviewComments', ReviewComments);
      Ini.WriteBool(SecView, 'Translations', Translations);
      Ini.WriteBool(SecView, 'Blame', Blame);
      Ini.WriteString(SecView, 'SyntaxTheme', SyntaxTheme);
      Ini.WriteString(SecView, 'EditorCommand', EditorCommand);
      Ini.WriteString(SecView, 'TerminalCommand', TerminalCommand);
      if UpdateSnoozedUntil > 0 then
        Ini.WriteString(SecUpdate, 'SnoozedUntil',
          FormatDateTime('yyyy"-"mm"-"dd', UpdateSnoozedUntil))
      else
        Ini.DeleteKey(SecUpdate, 'SnoozedUntil');
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
