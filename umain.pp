unit umain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ComCtrls,
  ExtCtrls, LCLType, LazLoggerBase,
  ATSynEdit, ATSynEdit_Adapter_EControl,
  ec_SyntAnal,
  gittan.lexers, gittan.git;

type

  {** The two panes of the split view. }
  TPane = (paLeft, paRight);

  { TForm1 }

  TForm1 = class(TForm)
    EditLeft: TATSynEdit;
    Splitter: TSplitter;
    EditRight: TATSynEdit;
    StatusBar: TStatusBar;
    ToolBar: TToolBar;
    ToolOpenRepo: TToolButton;
    DirDialog: TSelectDirectoryDialog;
    FileTree: TTreeView;
    TreeSplitter: TSplitter;
    procedure EditorEnter(Sender: TObject);
    procedure FileTreeSelectionChanged(Sender: TObject);
    procedure SplitterMoved(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure FormResize(Sender: TObject);
    procedure ToolOpenRepoClick(Sender: TObject);
  private
    FEditors: array[TPane] of TATSynEdit;
    FAdapters: array[TPane] of TATAdapterEControl;
    FActive: TPane;
    FSplitRatio: double;
    FLexers: TGittanLexers;
    FRepo: TGittanRepo;
    FSyntaxMenu: TMenuItem;
    function Editor: TATSynEdit;
    function Adapter: TATAdapterEControl;
    function EditorsWidth: integer;
    procedure UpdateStatus;
    procedure BuildMenu;
    procedure BuildSyntaxMenu;
    procedure MenuOpenClick(Sender: TObject);
    procedure MenuSaveClick(Sender: TObject);
    procedure MenuSyntaxClick(Sender: TObject);
    procedure SetLexer(APane: TPane; ALexer: TecSyntAnalyzer);
    procedure ShowText(APane: TPane; const AText: string;
      ALexer: TecSyntAnalyzer);
    procedure LoadFile(APane: TPane; const AFileName: string);
    procedure FillFileTree;
    function CompareTreeNodes(Node1, Node2: TTreeNode): integer;
  public
    {** Loads a file into the active pane and picks its lexer from the file
      name. }
    procedure OpenFile(const AFileName: string);
    {** Opens the git repository containing ADir and shows its uncommitted
      changes as a diff in the right pane. }
    procedure OpenRepository(const ADir: string);
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

resourcestring
  rsFile = '&File';
  rsOpen = '&Open...';
  rsSave = '&Save';
  rsSyntax = '&Syntax';
  rsPlainText = 'Plain text';
  rsNoLexers = 'No lexers found. Run "make lexlib" or set GITTAN_LEXLIB.';
  rsLexerCount = '%d lexers';
  rsDiffLexer = 'Diff';
  rsChangedFiles = '%d changed files in %s';
  rsNoChanges = 'No changes in %s';
  rsFileMissing = 'Not in the work tree: %s';

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
var
  Pane: TPane;
begin
  { The editors and splitter come from umain.lfm. The EControl adapter is not
    an IDE component, so each editor gets its own here; that lets the panes
    use different lexers. }
  FEditors[paLeft] := EditLeft;
  FEditors[paRight] := EditRight;
  for Pane in TPane do
  begin
    FAdapters[Pane] := TATAdapterEControl.Create(Self);
    FAdapters[Pane].AddEditor(FEditors[Pane]);
  end;
  FSplitRatio := 0.5;
  FormResize(nil);
  FActive := paLeft;

  FRepo := TGittanRepo.Create;
  FLexers := TGittanLexers.Create;
  if FLexers.Load then
    StatusBar.SimpleText := Format(rsLexerCount, [0])
  else
    StatusBar.SimpleText := rsNoLexers;
  if FLexers.Errors <> '' then
    DebugLn(FLexers.Errors);

  BuildMenu;
  { gittan [left [right]] }
  if ParamCount > 0 then
    OpenFile(ParamStr(1));
  if ParamCount > 1 then
  begin
    FActive := paRight;
    OpenFile(ParamStr(2));
    FActive := paLeft;
  end;
end;

procedure TForm1.FormDestroy(Sender: TObject);
var
  Pane: TPane;
begin
  for Pane in TPane do
    FAdapters[Pane].Lexer := nil;
  FreeAndNil(FLexers);
  FreeAndNil(FRepo);
end;

procedure TForm1.FormDropFiles(Sender: TObject; const FileNames: array of string);
begin
  if Length(FileNames) > 0 then
    OpenFile(FileNames[0]);
end;

procedure TForm1.ToolOpenRepoClick(Sender: TObject);
begin
  if FRepo.Root <> '' then
    DirDialog.InitialDir := FRepo.Root;
  if DirDialog.Execute then
    OpenRepository(DirDialog.FileName);
end;

{ Keep the editor split at the same proportion when the window is resized or
  the file tree changes width. }
procedure TForm1.FormResize(Sender: TObject);
begin
  if FEditors[paLeft] <> nil then
    FEditors[paLeft].Width := Round(EditorsWidth * FSplitRatio);
end;

{ ---------------------------------------------------------------------------
  Split view
  ---------------------------------------------------------------------------
  Menu commands act on the active pane: the editor that last had focus. }
function TForm1.Editor: TATSynEdit;
begin
  Result := FEditors[FActive];
end;

function TForm1.Adapter: TATAdapterEControl;
begin
  Result := FAdapters[FActive];
end;

procedure TForm1.EditorEnter(Sender: TObject);
begin
  if Sender = FEditors[paRight] then
    FActive := paRight
  else
    FActive := paLeft;
  UpdateStatus;
end;

{ Width shared by the two editors: the client area minus the file tree. }
function TForm1.EditorsWidth: integer;
begin
  Result := ClientWidth - FileTree.Width - TreeSplitter.Width;
  if Result < 1 then
    Result := 1;
end;

procedure TForm1.SplitterMoved(Sender: TObject);
begin
  FSplitRatio := FEditors[paLeft].Width / EditorsWidth;
end;

{ Shows the active pane's file name and lexer. }
procedure TForm1.UpdateStatus;
var
  Shown: string;
begin
  if Adapter.Lexer = nil then
    Shown := rsPlainText
  else
    Shown := Adapter.Lexer.LexerName;
  if Editor.FileName <> '' then
    StatusBar.SimpleText := ExtractFileName(Editor.FileName) + ' - ' + Shown
  else
    StatusBar.SimpleText := Shown;
end;

{ ---------------------------------------------------------------------------
  Menus
  --------------------------------------------------------------------------- }
procedure TForm1.BuildMenu;
var
  Main: TMainMenu;
  FileMenu, Item: TMenuItem;
begin
  Main := TMainMenu.Create(Self);
  Menu := Main;

  FileMenu := TMenuItem.Create(Main);
  FileMenu.Caption := rsFile;
  Main.Items.Add(FileMenu);

  Item := TMenuItem.Create(FileMenu);
  Item.Caption := rsOpen;
  Item.ShortCut := ShortCut(VK_O, [ssModifier]);
  Item.OnClick := @MenuOpenClick;
  FileMenu.Add(Item);

  Item := TMenuItem.Create(FileMenu);
  Item.Caption := rsSave;
  Item.ShortCut := ShortCut(VK_S, [ssModifier]);
  Item.OnClick := @MenuSaveClick;
  FileMenu.Add(Item);

  FSyntaxMenu := TMenuItem.Create(Main);
  FSyntaxMenu.Caption := rsSyntax;
  Main.Items.Add(FSyntaxMenu);
  BuildSyntaxMenu;
end;

{ The lexer list is long (hundreds of entries), so it is grouped into one
  submenu per initial letter. The item caption is the lexer name. }
procedure TForm1.BuildSyntaxMenu;
var
  Names: TStringList;
  Group, Item: TMenuItem;
  LexName, Initial, LastInitial: string;
begin
  Item := TMenuItem.Create(FSyntaxMenu);
  Item.Caption := rsPlainText;
  Item.OnClick := @MenuSyntaxClick;
  FSyntaxMenu.Add(Item);

  Names := TStringList.Create;
  try
    FLexers.GetNames(Names);
    StatusBar.SimpleText := Format(rsLexerCount, [Names.Count]);
    Group := nil;
    LastInitial := '';
    for LexName in Names do
    begin
      Initial := UpperCase(Copy(LexName, 1, 1));
      if not (Initial[1] in ['A'..'Z']) then
        Initial := '#';
      if (Group = nil) or (Initial <> LastInitial) then
      begin
        Group := TMenuItem.Create(FSyntaxMenu);
        Group.Caption := Initial;
        FSyntaxMenu.Add(Group);
        LastInitial := Initial;
      end;
      Item := TMenuItem.Create(Group);
      Item.Caption := LexName;
      Item.OnClick := @MenuSyntaxClick;
      Group.Add(Item);
    end;
  finally
    Names.Free;
  end;
end;

procedure TForm1.MenuOpenClick(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    if Dlg.Execute then
      OpenFile(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TForm1.MenuSaveClick(Sender: TObject);
var
  Dlg: TSaveDialog;
begin
  if Editor.FileName = '' then
  begin
    Dlg := TSaveDialog.Create(nil);
    try
      if not Dlg.Execute then
        Exit;
      Editor.FileName := Dlg.FileName;
    finally
      Dlg.Free;
    end;
  end;
  Editor.SaveToFile(Editor.FileName);
  if Adapter.Lexer = nil then
    SetLexer(FActive, FLexers.ForFile(Editor.FileName));
end;

procedure TForm1.MenuSyntaxClick(Sender: TObject);
var
  LexName: string;
begin
  { Strip the accelerator ampersand the widgetset may have inserted. }
  LexName := StringReplace(TMenuItem(Sender).Caption, '&', '', [rfReplaceAll]);
  if LexName = rsPlainText then
    SetLexer(FActive, nil)
  else
    SetLexer(FActive, FLexers.ByName(LexName));
end;

{ ---------------------------------------------------------------------------
  Files and lexers
  --------------------------------------------------------------------------- }
procedure TForm1.SetLexer(APane: TPane; ALexer: TecSyntAnalyzer);
begin
  FAdapters[APane].Lexer := ALexer;
  { Assigning a lexer does not parse anything yet; a change event from line 0
    starts the adapter's background parse of the whole text. }
  if ALexer <> nil then
    FEditors[APane].DoEventChange(0);
  UpdateStatus;
  FEditors[APane].Update;
end;

{ Replaces a pane's text with generated content that belongs to no file. }
procedure TForm1.ShowText(APane: TPane; const AText: string;
  ALexer: TecSyntAnalyzer);
begin
  FAdapters[APane].Lexer := nil;
  FEditors[APane].Text := UTF8Decode(AText);
  FEditors[APane].FileName := '';
  FEditors[APane].Modified := False;
  FEditors[APane].DoCaretSingle(0, 0);
  SetLexer(APane, ALexer);
end;

procedure TForm1.LoadFile(APane: TPane; const AFileName: string);
begin
  FAdapters[APane].Lexer := nil;
  FEditors[APane].LoadFromFile(AFileName, []);
  FEditors[APane].FileName := AFileName;
  SetLexer(APane, FLexers.ForFile(AFileName));
end;

procedure TForm1.OpenFile(const AFileName: string);
begin
  LoadFile(FActive, AFileName);
  Caption := ExtractFileName(AFileName) + ' - Gittan';
end;

{ ---------------------------------------------------------------------------
  Repository
  ---------------------------------------------------------------------------
  The right pane shows the work tree's uncommitted changes as a unified diff
  under the Diff lexer; the status bar counts the changed files. }
procedure TForm1.OpenRepository(const ADir: string);
var
  Files: TStringList;
begin
  if not FRepo.Open(ADir) then
  begin
    MessageDlg(FRepo.Error, mtError, [mbOK], 0);
    Exit;
  end;
  ShowText(paRight, FRepo.Diff, FLexers.ByName(rsDiffLexer));
  FillFileTree;
  Caption := ExtractFileName(FRepo.Root) + ' - Gittan';
  Files := TStringList.Create;
  try
    if FRepo.ChangedFiles(Files) and (Files.Count > 0) then
      StatusBar.SimpleText := Format(rsChangedFiles, [Files.Count, FRepo.Root])
    else
      StatusBar.SimpleText := Format(rsNoChanges, [FRepo.Root]);
  finally
    Files.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  File tree
  ---------------------------------------------------------------------------
  One node per path component of the repository's file list. A file node has
  Data set; a folder node (or a submodule, which ls-files reports as one
  entry) has Data = nil and is never opened. git lists paths sorted, so the
  folder node of the previous path is reused when the folder repeats. }
procedure TForm1.FillFileTree;
var
  Files: TStringList;
  Path, Dir, Part: string;
  DirNode, Node, LastDir: TTreeNode;
  LastDirPath: string;
  i, Start, Sep: integer;
begin
  Files := TStringList.Create;
  FileTree.BeginUpdate;
  try
    FileTree.Items.Clear;
    if not FRepo.ListFiles(Files) then
      Exit;
    LastDir := nil;
    LastDirPath := '';
    for i := 0 to Files.Count - 1 do
    begin
      Path := Files[i];
      if Path = '' then
        Continue;
      Dir := ExtractFilePath(Path);
      if (i > 0) and (Dir = LastDirPath) then
        DirNode := LastDir
      else
      begin
        DirNode := nil;
        Start := 1;
        repeat
          Sep := Pos('/', Path, Start);
          if Sep = 0 then
            Break;
          Part := Copy(Path, Start, Sep - Start);
          Start := Sep + 1;
          if DirNode = nil then
            Node := FileTree.Items.GetFirstNode
          else
            Node := DirNode.GetFirstChild;
          while (Node <> nil) and (Node.Text <> Part) do
            Node := Node.GetNextSibling;
          if Node = nil then
            Node := FileTree.Items.AddChild(DirNode, Part);
          DirNode := Node;
        until False;
        LastDir := DirNode;
        LastDirPath := Dir;
      end;
      Node := FileTree.Items.AddChild(DirNode, ExtractFileName(Path));
      if not DirectoryExists(IncludeTrailingPathDelimiter(FRepo.Root) +
        SetDirSeparators(Path)) then
        Node.Data := Pointer(1);
    end;
    FileTree.CustomSort(@CompareTreeNodes);
  finally
    FileTree.EndUpdate;
    Files.Free;
  end;
end;

{ Folders before files, then by name ignoring case. }
function TForm1.CompareTreeNodes(Node1, Node2: TTreeNode): integer;
begin
  Result := Ord(Node1.Data <> nil) - Ord(Node2.Data <> nil);
  if Result = 0 then
    Result := CompareText(Node1.Text, Node2.Text);
end;

{ Selecting a file shows it in the left editor. Folders only expand. A file
  deleted from the work tree is still listed from the index, so check first. }
procedure TForm1.FileTreeSelectionChanged(Sender: TObject);
var
  Node: TTreeNode;
  FileName: string;
begin
  Node := FileTree.Selected;
  if (Node = nil) or (Node.Data = nil) or (FRepo.Root = '') then
    Exit;
  FileName := IncludeTrailingPathDelimiter(FRepo.Root) +
    SetDirSeparators(Node.GetTextPath);
  if not FileExists(FileName) then
  begin
    StatusBar.SimpleText := Format(rsFileMissing, [Node.GetTextPath]);
    Exit;
  end;
  LoadFile(paLeft, FileName);
  Caption := Node.Text + ' - ' + ExtractFileName(FRepo.Root) + ' - Gittan';
end;

end.
