unit umain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ComCtrls,
  ExtCtrls, StdCtrls, Buttons, LCLType, LazLoggerBase, Math,
  ATSynEdit, ATSynEdit_Adapter_EControl, ATSynEdit_Bookmarks,
  ATSynEdit_Gutter_Decor, ATSynEdit_Globals, ATStringProc,
  ec_SyntAnal,
  gittan.lexers, gittan.git, gittan.icons, gittan.theme;

type

  { TForm1 }

  TForm1 = class(TForm)
    Edit: TATSynEdit;
    StatusBar: TStatusBar;
    ToolBar: TToolBar;
    ToolOpenRepo: TToolButton;
    DirDialog: TSelectDirectoryDialog;
    ThemeTimer: TTimer;
    FileTree: TTreeView;
    TreeImages: TImageList;
    ButtonImages: TImageList;
    TreeSplitter: TSplitter;
    NextChangeButton: TBitBtn;
    procedure NextChangeButtonClick(Sender: TObject);
    procedure EditCalcBookmarkColor(Sender: TObject; ABookmarkKind: integer;
      var AColor: TColor);
    procedure EditChangeZoom(Sender: TObject);
    procedure ThemeTimerTimer(Sender: TObject);
    procedure FileTreeSelectionChanged(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure ToolOpenRepoClick(Sender: TObject);
  private
    FAdapter: TATAdapterEControl;
    FLexers: TGittanLexers;
    FRepo: TGittanRepo;
    FSyntaxMenu: TMenuItem;
    FDark: boolean;
    FBookmarkBandWidth: integer;
    procedure ApplyTheme;
    procedure UpdateStatus;
    procedure BuildMenu;
    procedure BuildSyntaxMenu;
    procedure MenuOpenClick(Sender: TObject);
    procedure MenuSyntaxClick(Sender: TObject);
    procedure SetLexer(ALexer: TecSyntAnalyzer);
    procedure ShowText(const AText: string; ALexer: TecSyntAnalyzer);
    procedure MarkLine(ALine: integer; AChange: char);
    procedure ShowLineNumbers(ALines: TStrings);
    procedure ResetLineNumbers;
    procedure UpdateNumberWidth;
    procedure UpdateNextChange;
    procedure ShowChanges(const APath: string);
    procedure FillFileTree(AFiles: TStrings);
    function CompareTreeNodes(Node1, Node2: TTreeNode): integer;
  public
    {** Loads a file into the editor and picks its lexer from the file
      name. }
    procedure OpenFile(const AFileName: string);
    {** Opens the git repository containing ADir, lists its changed files in
      the tree and shows the uncommitted changes as a diff in the editor. }
    procedure OpenRepository(const ADir: string);
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

resourcestring
  rsFile = '&File';
  rsOpen = '&Open...';
  rsSyntax = '&Syntax';
  rsPlainText = 'Plain text';
  rsNoLexers = 'No lexers found. Run "make lexlib" or set GITTAN_LEXLIB.';
  rsLexerCount = '%d lexers';
  rsDiffLexer = 'Diff';
  rsChangedFiles = '%d changed files in %s';
  rsNoChanges = 'No changes in %s';
  rsNextChange = 'Next change';

const
  { Bookmark kinds in the editor's second bookmark list, used only for the
    line backgrounds of a diff. }
  bmAdded = 1;
  bmDeleted = 2;

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  { The editor comes from umain.lfm. The EControl adapter is not an IDE
    component, so it is created here. Gittan is a viewer, so the editor is
    read-only; ShowText and OpenFile lift that while they replace the text. }
  FAdapter := TATAdapterEControl.Create(Self);
  FAdapter.AddEditor(Edit);
  Edit.ModeReadOnly := True;
  { Every line gets its number: the change view numbers lines itself (see
    ShowLineNumbers) and the file view should look the same. }
  Edit.OptNumbersStyle := TATEditorNumbersStyle.All;
  Edit.GutterDecorAlignment := taRightJustify;
  Edit.OnChangeZoom := @EditChangeZoom;
  FBookmarkBandWidth := Edit.OptGutterWidthBookmarks;

  FillTreeIcons(TreeImages);
  FillButtonIcons(ButtonImages);
  NextChangeButton.Images := ButtonImages;
  NextChangeButton.ImageIndex := iconArrowDown;
  NextChangeButton.GlyphShowMode := gsmAlways;
  NextChangeButton.Hint := rsNextChange;
  UpdateNextChange;

  FRepo := TGittanRepo.Create;
  FLexers := TGittanLexers.Create;
  if FLexers.Load then
    StatusBar.SimpleText := Format(rsLexerCount, [0])
  else
    StatusBar.SimpleText := rsNoLexers;
  if FLexers.Errors <> '' then
    DebugLn(FLexers.Errors);
  FDark := IsDarkMode;
  ApplyTheme;

  BuildMenu;
  { gittan [file | folder] }
  if ParamCount > 0 then
    if DirectoryExists(ParamStr(1)) then
      OpenRepository(ParamStr(1))
    else
      OpenFile(ParamStr(1));
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  FAdapter.Lexer := nil;
  FreeAndNil(FLexers);
  FreeAndNil(FRepo);
end;

{ The desktop theme can change while Gittan runs. The LCL has no event for
  it, so the timer asks every other second; the check is two system color
  lookups. }
procedure TForm1.ThemeTimerTimer(Sender: TObject);
begin
  if IsDarkMode <> FDark then
  begin
    FDark := not FDark;
    ApplyTheme;
  end;
end;

{ ---------------------------------------------------------------------------
  Theme
  ---------------------------------------------------------------------------
  The native controls follow the desktop theme by themselves. The editor has
  its own palette, light by default, and the lexer colors are tuned for a
  white background, so both are set here from FDark. }
procedure TForm1.ApplyTheme;
var
  i: integer;
begin
  Edit.Colors.Init;
  if FDark then
    with Edit.Colors do
    begin
      TextFont := RGBToColor(224, 224, 224);
      TextBG := RGBToColor(30, 30, 30);
      TextSelFont := clNone;
      TextSelBG := RGBToColor(38, 79, 120);
      TextDisabledFont := RGBToColor(128, 128, 128);
      TextDisabledBG := RGBToColor(40, 40, 40);
      GutterFont := RGBToColor(133, 133, 133);
      GutterBG := RGBToColor(37, 37, 38);
      GutterCaretFont := RGBToColor(200, 200, 200);
      GutterCaretBG := RGBToColor(55, 55, 56);
      GutterFoldLine := RGBToColor(133, 133, 133);
      GutterFoldLine2 := RGBToColor(160, 120, 120);
      GutterFoldBG := RGBToColor(55, 55, 56);
      GutterSeparatorBG := RGBToColor(60, 60, 60);
      CurrentLineBG := RGBToColor(42, 42, 42);
      IndentVertLines := RGBToColor(70, 70, 70);
      BlockStaple := RGBToColor(70, 70, 70);
      BlockSepLine := RGBToColor(70, 70, 70);
      MarginRight := RGBToColor(60, 60, 60);
      CollapseLine := RGBToColor(160, 120, 120);
      CollapseMarkFont := RGBToColor(200, 160, 160);
      CollapseMarkBG := RGBToColor(55, 55, 56);
      CollapseMarkBorder := RGBToColor(160, 120, 120);
      UnprintedFont := RGBToColor(110, 110, 160);
      UnprintedBG := RGBToColor(55, 55, 56);
      Links := RGBToColor(100, 160, 240);
      LockedBG := RGBToColor(40, 40, 40);
      MarkedLinesBG := RGBToColor(70, 60, 30);
      MinimapBorder := RGBToColor(60, 60, 60);
      BorderLine := RGBToColor(60, 60, 60);
      BorderLineFocused := RGBToColor(38, 79, 120);
      ComboboxArrow := RGBToColor(133, 133, 133);
      ComboboxArrowBG := RGBToColor(40, 40, 40);
    end;
  FLexers.ApplyTheme(FDark);
  { The change view's line numbers carry their own color. }
  for i := 0 to Edit.GutterDecor.Count - 1 do
    Edit.GutterDecor.ItemPtr(i)^.Data.TextColor := Edit.Colors.GutterFont;
  Edit.Invalidate;
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

{ Shows the editor's file name and lexer. }
procedure TForm1.UpdateStatus;
var
  Shown: string;
begin
  if FAdapter.Lexer = nil then
    Shown := rsPlainText
  else
    Shown := FAdapter.Lexer.LexerName;
  if Edit.FileName <> '' then
    StatusBar.SimpleText := ExtractFileName(Edit.FileName) + ' - ' + Shown
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

procedure TForm1.MenuSyntaxClick(Sender: TObject);
var
  LexName: string;
begin
  { Strip the accelerator ampersand the widgetset may have inserted. }
  LexName := StringReplace(TMenuItem(Sender).Caption, '&', '', [rfReplaceAll]);
  if LexName = rsPlainText then
    SetLexer(nil)
  else
    SetLexer(FLexers.ByName(LexName));
end;

{ ---------------------------------------------------------------------------
  Files and lexers
  --------------------------------------------------------------------------- }
procedure TForm1.SetLexer(ALexer: TecSyntAnalyzer);
begin
  FAdapter.Lexer := ALexer;
  { Assigning a lexer does not parse anything yet; a change event from line 0
    starts the adapter's background parse of the whole text. }
  if ALexer <> nil then
    Edit.DoEventChange(0);
  UpdateStatus;
  Edit.Update;
end;

{ Replaces the text with generated content that belongs to no file. A
  read-only ATSynEdit ignores assignments to Text, so read-only mode is
  lifted while the text is replaced. Loading does not clear the second
  bookmark list, so the diff colors are dropped here. }
procedure TForm1.ShowText(const AText: string; ALexer: TecSyntAnalyzer);
begin
  FAdapter.Lexer := nil;
  Edit.BookmarkDeleteAll_2;
  ResetLineNumbers;
  Edit.ModeReadOnly := False;
  Edit.Text := UTF8Decode(AText);
  { Setting Text skips the wrap rebuild while the editor has no fold ranges
    (it is in "virtual" wrap mode then) and never flags one as needed, so
    once the lexer adds folds the wrap items of the previous text are
    reused and lines paint cut off. LoadFromFile clears the wrap info and
    flags the rebuild itself; do the same here. }
  Edit.WrapInfo.Clear;
  Edit.Update(True);
  Edit.ModeReadOnly := True;
  Edit.FileName := '';
  Edit.Modified := False;
  Edit.DoCaretSingle(0, 0);
  SetLexer(ALexer);
end;

procedure TForm1.OpenFile(const AFileName: string);
begin
  FAdapter.Lexer := nil;
  Edit.BookmarkDeleteAll_2;
  ResetLineNumbers;
  Edit.ModeReadOnly := False;
  Edit.LoadFromFile(AFileName, []);
  Edit.ModeReadOnly := True;
  Edit.FileName := AFileName;
  SetLexer(FLexers.ForFile(AFileName));
  UpdateNextChange;
  Caption := ExtractFileName(AFileName) + ' - Gittan';
end;

{ ---------------------------------------------------------------------------
  Diff colors
  ---------------------------------------------------------------------------
  Added and deleted lines get a background through the editor's second
  bookmark list: a bookmark there colors its line but draws no gutter icon.
  The kind picks the color. }
procedure TForm1.EditCalcBookmarkColor(Sender: TObject; ABookmarkKind: integer;
  var AColor: TColor);
begin
  if FDark then
    case ABookmarkKind of
      bmAdded: AColor := RGBToColor(28, 66, 34);
      bmDeleted: AColor := RGBToColor(84, 30, 30);
    end
  else
    case ABookmarkKind of
      bmAdded: AColor := RGBToColor(214, 245, 214);
      bmDeleted: AColor := RGBToColor(252, 215, 215);
    end;
end;

{ AChange is the first character of a unified diff line. }
procedure TForm1.MarkLine(ALine: integer; AChange: char);
var
  Kind: integer;
begin
  case AChange of
    '+': Kind := bmAdded;
    '-': Kind := bmDeleted;
    else
      Exit;
  end;
  Edit.BookmarkSetForLine_2(ALine, Kind, '', TATBookmarkAutoDelete.DontDelete,
    False, 0);
end;

{ ---------------------------------------------------------------------------
  Line numbers of the change view
  ---------------------------------------------------------------------------
  The change view keeps deleted lines in the text, so the editor's own
  numbering counts them and every line below a deletion shows a number
  too high. ATSynEdit has no hook for the number text, but its gutter
  "decor" draws a text per line in the bookmark band. So the number band
  is hidden, the bookmark band is widened to the number width, and each
  kept line gets its number in the new file as decor text; a deleted line
  gets none. The file view uses the editor's own numbering. }

{ ALines are the diff lines with their +/- markers, one per editor line. }
procedure TForm1.ShowLineNumbers(ALines: TStrings);
var
  Decor: TATGutterDecorData;
  Band, Line, i: integer;
begin
  Line := 0;
  for i := 0 to ALines.Count - 1 do
  begin
    if (ALines[i] <> '') and (ALines[i][1] = '-') then
      Continue;
    Inc(Line);
    Decor := Default(TATGutterDecorData);
    Decor.LineNum := i;
    Decor.ImageIndex := -1;
    { The trailing space keeps the right-aligned number off the next band. }
    Decor.TextAll := IntToStr(Line) + ' ';
    Decor.TextColor := Edit.Colors.GutterFont;
    Edit.GutterDecor.Add(Decor);
  end;
  Band := Edit.Gutter.FindIndexByTag(ATEditorOptions.GutterTagNumbers);
  if Band >= 0 then
    Edit.Gutter[Band].Visible := False;
  Band := Edit.Gutter.FindIndexByTag(ATEditorOptions.GutterTagBookmarks);
  if Band >= 0 then
    Edit.Gutter[Band].Scaled := False;
  UpdateNumberWidth;
end;

{ Back to the editor's own numbering. }
procedure TForm1.ResetLineNumbers;
var
  Band: integer;
begin
  Edit.GutterDecor.Clear;
  Band := Edit.Gutter.FindIndexByTag(ATEditorOptions.GutterTagNumbers);
  if Band >= 0 then
    Edit.Gutter[Band].Visible := True;
  Band := Edit.Gutter.FindIndexByTag(ATEditorOptions.GutterTagBookmarks);
  if Band >= 0 then
    Edit.Gutter[Band].Scaled := True;
  Edit.OptGutterWidthBookmarks := FBookmarkBandWidth;
end;

{ The bookmark band holds the line numbers while the change view is shown:
  room for the digits of the last number, the trailing space and one
  character of indent. The band width is reapplied by the editor on every
  update, so the option is set rather than the band. }
procedure TForm1.UpdateNumberWidth;
var
  CharWidth: integer;
begin
  if Edit.GutterDecor.Count = 0 then
    Exit;
  CharWidth := Edit.TextCharSize.XScaled div ATEditorCharXScale;
  Edit.OptGutterWidthBookmarks :=
    (Length(IntToStr(Edit.GutterDecor.Count)) + 2) * CharWidth;
end;

{ Zooming changes the character width the number band is sized from. }
procedure TForm1.EditChangeZoom(Sender: TObject);
begin
  UpdateNumberWidth;
end;

{ The arrow floating over the editor's lower right corner is shown only
  while the text has changes to jump to. }
procedure TForm1.UpdateNextChange;
begin
  NextChangeButton.Visible := Edit.Strings.Bookmarks2.Count > 0;
end;

{ Jumps to the first line of the next block of changed lines after the
  caret, wrapping around to the first block. The block lands a few lines
  below the top edge so its context stays in view. }
procedure TForm1.NextChangeButtonClick(Sender: TObject);
var
  Marks: TATBookmarks;
  Cur, Line, Target, i: integer;
begin
  Marks := Edit.Strings.Bookmarks2;
  if Marks.Count = 0 then
    Exit;
  Cur := Edit.Carets[0].PosY;
  Target := Marks[0]^.Data.LineNum;
  { The list is sorted by line; a block starts where the line before is
    not marked. }
  for i := 0 to Marks.Count - 1 do
  begin
    Line := Marks[i]^.Data.LineNum;
    if (Line > Cur) and ((i = 0) or (Marks[i - 1]^.Data.LineNum <> Line - 1)) then
    begin
      Target := Line;
      Break;
    end;
  end;
  Edit.DoCaretSingle(0, Target);
  Edit.LineTop := Max(0, Target - 3);
  Edit.Update;
end;

{ ---------------------------------------------------------------------------
  Repository
  ---------------------------------------------------------------------------
  The editor shows the work tree's uncommitted changes as a unified diff
  under the Diff lexer; the file tree lists the changed files and the status
  bar counts them. }
procedure TForm1.OpenRepository(const ADir: string);
var
  Files: TStringList;
  i: integer;
begin
  if not FRepo.Open(ADir) then
  begin
    MessageDlg(FRepo.Error, mtError, [mbOK], 0);
    Exit;
  end;
  ShowText(FRepo.Diff, FLexers.ByName(rsDiffLexer));
  { The "---"/"+++" file headers are not changes. }
  for i := 0 to Edit.Strings.Count - 1 do
    if (Edit.Strings.LinesLen[i] > 0) and
      (Copy(Edit.Strings.Lines[i], 1, 3) <> '---') and
      (Copy(Edit.Strings.Lines[i], 1, 3) <> '+++') then
      MarkLine(i, char(Edit.Strings.Lines[i][1]));
  UpdateNextChange;
  Caption := ExtractFileName(FRepo.Root) + ' - Gittan';
  Files := TStringList.Create;
  try
    FRepo.ChangedPaths(Files);
    FillFileTree(Files);
    if Files.Count > 0 then
      StatusBar.SimpleText := Format(rsChangedFiles, [Files.Count, FRepo.Root])
    else
      StatusBar.SimpleText := Format(rsNoChanges, [FRepo.Root]);
  finally
    Files.Free;
  end;
end;

{ Shows one changed file with its deleted lines kept in place: the diff with
  the whole file as context, the +/- markers turned into line colors. The
  lexer comes from the file name. }
procedure TForm1.ShowChanges(const APath: string);
var
  Lines, Plain: TStringList;
  i: integer;
begin
  Lines := TStringList.Create;
  Plain := TStringList.Create;
  try
    if not FRepo.FileChanges(APath, Lines) then
    begin
      StatusBar.SimpleText := FRepo.Error;
      Exit;
    end;
    for i := 0 to Lines.Count - 1 do
      Plain.Add(Copy(Lines[i], 2, MaxInt));
    ShowText(Plain.Text, FLexers.ForFile(APath));
    for i := 0 to Lines.Count - 1 do
      MarkLine(i, Lines[i][1]);
    ShowLineNumbers(Lines);
    UpdateNextChange;
    Edit.FileName := IncludeTrailingPathDelimiter(FRepo.Root) +
      SetDirSeparators(APath);
    UpdateStatus;
    Edit.Update;
  finally
    Plain.Free;
    Lines.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  File tree
  ---------------------------------------------------------------------------
  One node per path component of each changed file. A file node has Data
  set and a badge for its change kind; a folder node (or a submodule, which
  git status reports as one entry) has Data = nil, the folder icon, and is
  never opened. git lists paths sorted, so the folder node of the previous
  path is reused when the folder repeats. }
procedure TForm1.FillFileTree(AFiles: TStrings);
var
  Path, Dir, Part: string;
  DirNode, Node, LastDir: TTreeNode;
  LastDirPath: string;
  i, Start, Sep: integer;
begin
  FileTree.BeginUpdate;
  try
    FileTree.Items.Clear;
    LastDir := nil;
    LastDirPath := '';
    for i := 0 to AFiles.Count - 1 do
    begin
      Path := AFiles[i];
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
          begin
            Node := FileTree.Items.AddChild(DirNode, Part);
            Node.ImageIndex := iconFolder;
            Node.SelectedIndex := iconFolder;
          end;
          DirNode := Node;
        until False;
        LastDir := DirNode;
        LastDirPath := Dir;
      end;
      Node := FileTree.Items.AddChild(DirNode, ExtractFileName(Path));
      if DirectoryExists(IncludeTrailingPathDelimiter(FRepo.Root) +
        SetDirSeparators(Path)) then
        Node.ImageIndex := iconFolder
      else
      begin
        Node.Data := Pointer(1);
        Node.ImageIndex := ChangeIcon(TGittanChangeKind(PtrUInt(AFiles.Objects[i])));
      end;
      Node.SelectedIndex := Node.ImageIndex;
    end;
    FileTree.CustomSort(@CompareTreeNodes);
  finally
    FileTree.EndUpdate;
  end;
end;

{ Folders before files, then by name ignoring case. }
function TForm1.CompareTreeNodes(Node1, Node2: TTreeNode): integer;
begin
  Result := Ord(Node1.Data <> nil) - Ord(Node2.Data <> nil);
  if Result = 0 then
    Result := CompareText(Node1.Text, Node2.Text);
end;

{ Selecting a file shows its changes. Folders only expand. A deleted file
  still has a diff: every line of it, deleted. }
procedure TForm1.FileTreeSelectionChanged(Sender: TObject);
var
  Node: TTreeNode;
begin
  Node := FileTree.Selected;
  if (Node = nil) or (Node.Data = nil) or (FRepo.Root = '') then
    Exit;
  ShowChanges(Node.GetTextPath);
  Caption := Node.Text + ' - ' + ExtractFileName(FRepo.Root) + ' - Gittan';
end;

end.
