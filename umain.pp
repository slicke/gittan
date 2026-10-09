unit umain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ComCtrls,
  ExtCtrls, StdCtrls, LCLType, LazLoggerBase, Math, Types,
  ATSynEdit, ATSynEdit_Adapter_EControl, ATSynEdit_Bookmarks,
  ATSynEdit_Gutter_Decor, ATSynEdit_Globals, ATStringProc,
  ec_SyntAnal,
  gittan.lexers, gittan.git, gittan.icons, gittan.theme, gittan.changenav,
  gittan.summary, gittan.watch;

type
  {** What the space right of the tree shows: the summary, one changed
    file, the raw repository diff, or a plain file from File > Open. }
  TGittanView = (gvSummary, gvChanges, gvRepoDiff, gvFile);

  { TForm1 }

  TForm1 = class(TForm)
    Edit: TATSynEdit;
    StatusBar: TStatusBar;
    DirDialog: TSelectDirectoryDialog;
    ThemeTimer: TTimer;
    FileTree: TTreeView;
    TreeImages: TImageList;
    TreeSplitter: TSplitter;
    procedure EditCalcBookmarkColor(Sender: TObject; ABookmarkKind: integer;
      var AColor: TColor);
    procedure EditChangeZoom(Sender: TObject);
    procedure EditChangeCaretPos(Sender: TObject);
    procedure UpdateChangeNavAsync(Data: PtrInt);
    procedure ThemeTimerTimer(Sender: TObject);
    procedure FileTreeSelectionChanged(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
  private
    FAdapter: TATAdapterEControl;
    FLexers: TGittanLexers;
    FRepo: TGittanRepo;
    FSyntaxMenu: TMenuItem;
    FNav: TGittanChangeNav;
    FNavUpdateQueued: boolean;
    FSummaryBox: TScrollBox;
    FSummary: TGittanSummary;
    FBranch: string;
    FFileCount: integer;
    FDark: boolean;
    FBookmarkBandWidth: integer;
    FWatcher: TGittanWatcher;
    FView: TGittanView;
    procedure ApplyTheme;
    procedure MenuRefreshClick(Sender: TObject);
    procedure WatcherChange(Sender: TObject);
    procedure StartWatcher;
    procedure StopWatcher;
    function LoadRepository: boolean;
    procedure RefreshRepository;
    function SelectedPath: string;
    procedure UpdateStatus;
    procedure BuildMenu;
    procedure BuildSyntaxMenu;
    procedure MenuOpenClick(Sender: TObject);
    procedure MenuOpenRepoClick(Sender: TObject);
    procedure MenuSyntaxClick(Sender: TObject);
    procedure MenuSummaryClick(Sender: TObject);
    procedure MenuRepoDiffClick(Sender: TObject);
    procedure SummaryBoxResize(Sender: TObject);
    procedure SummarySelectFile(Sender: TObject; const APath: string);
    procedure ShowSummary;
    procedure ShowEditor;
    procedure ShowRepoDiff;
    procedure MenuPrevChangeClick(Sender: TObject);
    procedure MenuNextChangeClick(Sender: TObject);
    procedure SetLexer(ALexer: TecSyntAnalyzer);
    procedure ShowText(const AText: string; ALexer: TecSyntAnalyzer);
    procedure MarkLine(ALine: integer; AChange: char);
    procedure ShowLineNumbers(ALines: TStrings);
    procedure ResetLineNumbers;
    procedure UpdateNumberWidth;
    function ChangeBlocks: TIntegerDynArray;
    procedure UpdateChangeNav;
    procedure GoToChange(ANext: boolean);
    procedure ShowChanges(const APath: string);
    procedure FillFileTree(const AStats: TGittanFileStats);
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
  rsOpenRepo = 'Open &Repository...';
  rsSyntax = '&Syntax';
  rsView = '&View';
  rsSummary = '&Summary';
  rsRepoDiff = '&Repository Diff';
  rsRefresh = 'Re&fresh';
  rsDropHint = 'Open a repository, or drop a folder or file here.';
  rsGo = '&Go';
  rsNextChange = '&Next Change';
  rsPrevChange = '&Previous Change';
  rsPlainText = 'Plain text';
  rsNoLexers = 'No lexers found. Run "make lexlib" or set GITTAN_LEXLIB.';
  rsLexerCount = '%d lexers';
  rsDiffLexer = 'Diff';
  rsRepoOnBranch = '%s on %s';
  rsChangedFiles = '%d changed files';
  rsOneChangedFile = '1 changed file';
  rsNoChanges = 'no changes';

const
  { Bookmark kinds in the editor's second bookmark list, used only for the
    line backgrounds of a diff. }
  bmAdded = 1;
  bmDeleted = 2;
  { How often the watcher asks git whether the repository changed. }
  WatchInterval = 2000;

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
var
  Band: integer;
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
  Edit.OnChangeCaretPos := @EditChangeCaretPos;
  { The minimap shows where in the file the changes are: it paints the
    same line backgrounds as the text. }
  Edit.OptMinimapVisible := True;
  Edit.OptMinimapTooltipVisible := False;
  FBookmarkBandWidth := Edit.OptGutterWidthBookmarks;
  { The line states band marks every line of a freshly set text as new
    with a green bar, which means nothing in a viewer. }
  Band := Edit.Gutter.FindIndexByTag(ATEditorOptions.GutterTagLineStates);
  if Band >= 0 then
    Edit.Gutter[Band].Visible := False;

  FillTreeIcons(TreeImages);
  { The change navigator floats over the editor's lower right corner. It
    is anchored to the editor's edges, so it stays there as it grows with
    its counter. }
  FNav := TGittanChangeNav.Create(Self);
  FNav.Parent := Edit;
  FNav.Anchors := [akRight, akBottom];
  FNav.AnchorSideRight.Control := Edit;
  FNav.AnchorSideRight.Side := asrRight;
  FNav.AnchorSideBottom.Control := Edit;
  FNav.AnchorSideBottom.Side := asrBottom;
  FNav.BorderSpacing.Right := 20;
  FNav.BorderSpacing.Bottom := 20;
  FNav.OnPrev := @MenuPrevChangeClick;
  FNav.OnNext := @MenuNextChangeClick;
  UpdateChangeNav;
  { The summary takes the editor's place until a file is picked. The
    scroll box gives it native scrolling; its resize keeps the summary at
    least as tall as the box, so the summary's background fills it. }
  FSummaryBox := TScrollBox.Create(Self);
  FSummaryBox.Parent := Self;
  FSummaryBox.Align := alClient;
  FSummaryBox.BorderStyle := bsNone;
  FSummaryBox.HorzScrollBar.Visible := False;
  FSummaryBox.OnResize := @SummaryBoxResize;
  FSummary := TGittanSummary.Create(Self);
  FSummary.Parent := FSummaryBox;
  FSummary.Images := TreeImages;
  FSummary.OnSelectFile := @SummarySelectFile;
  FSummary.SetMessage(rsDropHint);

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
  ShowSummary;
  { gittan [file | folder] }
  if ParamCount > 0 then
    if DirectoryExists(ParamStr(1)) then
      OpenRepository(ParamStr(1))
    else
      OpenFile(ParamStr(1));
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  Application.RemoveAsyncCalls(Self);
  StopWatcher;
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
  if FDark then
    FNav.SetColors(Edit.Colors.TextBG, RGBToColor(45, 45, 46),
      RGBToColor(85, 85, 86), RGBToColor(200, 200, 200), RGBToColor(100, 160, 240))
  else
    FNav.SetColors(Edit.Colors.TextBG, RGBToColor(246, 246, 246),
      RGBToColor(205, 205, 205), RGBToColor(70, 70, 70), RGBToColor(0, 110, 230));
  FSummaryBox.Color := Edit.Colors.TextBG;
  if FDark then
    FSummary.SetColors(Edit.Colors.TextBG, Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(45, 45, 46), RGBToColor(63, 185, 80),
      RGBToColor(248, 81, 73), RGBToColor(62, 62, 62))
  else
    FSummary.SetColors(Edit.Colors.TextBG, RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(243, 243, 243), RGBToColor(26, 127, 55),
      RGBToColor(207, 34, 46), RGBToColor(222, 222, 222));
  { The change view's line numbers carry their own color. }
  for i := 0 to Edit.GutterDecor.Count - 1 do
    Edit.GutterDecor.ItemPtr(i)^.Data.TextColor := Edit.Colors.GutterFont;
  Edit.Invalidate;
end;

{ A dropped folder opens as a repository, a dropped file as a file. }
procedure TForm1.FormDropFiles(Sender: TObject; const FileNames: array of string);
begin
  if Length(FileNames) = 0 then
    Exit;
  if DirectoryExists(FileNames[0]) then
    OpenRepository(FileNames[0])
  else
    OpenFile(FileNames[0]);
end;

procedure TForm1.MenuOpenRepoClick(Sender: TObject);
begin
  if FRepo.Root <> '' then
    DirDialog.InitialDir := FRepo.Root;
  if DirDialog.Execute then
    OpenRepository(DirDialog.FileName);
end;

{ The status bar names the repository and branch while the summary or the
  raw diff is shown, and the file and its lexer while a file is shown; the
  full path is in its hint, so the bar stays short. }
procedure TForm1.UpdateStatus;
var
  Lexer, Repo: string;
begin
  if FAdapter.Lexer = nil then
    Lexer := rsPlainText
  else
    Lexer := FAdapter.Lexer.LexerName;
  Repo := '';
  if FRepo.Root <> '' then
  begin
    Repo := Format(rsRepoOnBranch, [ExtractFileName(FRepo.Root), FBranch]);
    if FBranch = '' then
      Repo := ExtractFileName(FRepo.Root);
  end;
  if FSummaryBox.Visible and (Repo <> '') then
  begin
    case FFileCount of
      0: StatusBar.SimpleText := Repo + ' · ' + rsNoChanges;
      1: StatusBar.SimpleText := Repo + ' · ' + rsOneChangedFile;
      else
        StatusBar.SimpleText := Repo + ' · ' + Format(rsChangedFiles, [FFileCount]);
    end;
    StatusBar.Hint := FRepo.Root;
  end
  else if Edit.FileName <> '' then
  begin
    StatusBar.SimpleText := ExtractFileName(Edit.FileName) + ' · ' + Lexer;
    StatusBar.Hint := Edit.FileName;
  end
  else if Repo <> '' then
  begin
    StatusBar.SimpleText := Repo + ' · ' + Lexer;
    StatusBar.Hint := FRepo.Root;
  end
  else
  begin
    StatusBar.SimpleText := Lexer;
    StatusBar.Hint := '';
  end;
end;

{ ---------------------------------------------------------------------------
  Menus
  --------------------------------------------------------------------------- }
procedure TForm1.BuildMenu;
var
  Main: TMainMenu;
  FileMenu, ViewMenu, GoMenu, Item: TMenuItem;
begin
  Main := TMainMenu.Create(Self);
  Menu := Main;

  FileMenu := TMenuItem.Create(Main);
  FileMenu.Caption := rsFile;
  Main.Items.Add(FileMenu);

  Item := TMenuItem.Create(FileMenu);
  Item.Caption := rsOpenRepo;
  Item.ShortCut := ShortCut(VK_O, [ssModifier, ssShift]);
  Item.OnClick := @MenuOpenRepoClick;
  FileMenu.Add(Item);
  Item := TMenuItem.Create(FileMenu);
  Item.Caption := rsOpen;
  Item.ShortCut := ShortCut(VK_O, [ssModifier]);
  Item.OnClick := @MenuOpenClick;
  FileMenu.Add(Item);

  ViewMenu := TMenuItem.Create(Main);
  ViewMenu.Caption := rsView;
  Main.Items.Add(ViewMenu);
  Item := TMenuItem.Create(ViewMenu);
  Item.Caption := rsSummary;
  Item.ShortCut := ShortCut(VK_1, [ssModifier]);
  Item.OnClick := @MenuSummaryClick;
  ViewMenu.Add(Item);
  Item := TMenuItem.Create(ViewMenu);
  Item.Caption := rsRepoDiff;
  Item.ShortCut := ShortCut(VK_2, [ssModifier]);
  Item.OnClick := @MenuRepoDiffClick;
  ViewMenu.Add(Item);
  ViewMenu.Add(NewLine);
  Item := TMenuItem.Create(ViewMenu);
  Item.Caption := rsRefresh;
  Item.ShortCut := ShortCut(VK_R, [ssModifier]);
  Item.OnClick := @MenuRefreshClick;
  ViewMenu.Add(Item);

  FSyntaxMenu := TMenuItem.Create(Main);
  FSyntaxMenu.Caption := rsSyntax;
  Main.Items.Add(FSyntaxMenu);
  BuildSyntaxMenu;

  GoMenu := TMenuItem.Create(Main);
  GoMenu.Caption := rsGo;
  Main.Items.Add(GoMenu);
  Item := TMenuItem.Create(GoMenu);
  Item.Caption := rsNextChange;
  Item.ShortCut := ShortCut(VK_F7, []);
  Item.OnClick := @MenuNextChangeClick;
  GoMenu.Add(Item);
  Item := TMenuItem.Create(GoMenu);
  Item.Caption := rsPrevChange;
  Item.ShortCut := ShortCut(VK_F7, [ssShift]);
  Item.OnClick := @MenuPrevChangeClick;
  GoMenu.Add(Item);
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
  UpdateChangeNav;
  ShowEditor;
  FView := gvFile;
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
  { A faint tint of the editor background, so the syntax colors still
    read on top of it. }
  if FDark then
    case ABookmarkKind of
      bmAdded: AColor := RGBToColor(32, 52, 37);
      bmDeleted: AColor := RGBToColor(66, 38, 38);
    end
  else
    case ABookmarkKind of
      bmAdded: AColor := RGBToColor(218, 251, 225);
      bmDeleted: AColor := RGBToColor(255, 235, 233);
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

{ ---------------------------------------------------------------------------
  Change navigation
  ---------------------------------------------------------------------------
  The navigator floating over the editor's lower right corner, and the Go
  menu, jump between the blocks of changed lines. }

{ The first line of every block of changed lines, in order. The second
  bookmark list is sorted by line; a block starts where the line before is
  not marked. }
function TForm1.ChangeBlocks: TIntegerDynArray;
var
  Marks: TATBookmarks;
  Line, i, n: integer;
begin
  Result := nil;
  Marks := Edit.Strings.Bookmarks2;
  SetLength(Result, Marks.Count);
  n := 0;
  for i := 0 to Marks.Count - 1 do
  begin
    Line := Marks[i]^.Data.LineNum;
    if (i = 0) or (Marks[i - 1]^.Data.LineNum <> Line - 1) then
    begin
      Result[n] := Line;
      Inc(n);
    end;
  end;
  SetLength(Result, n);
end;

{ The navigator is shown only while the text has changes to jump to. Its
  counter names the last block the caret has reached, 0 before the first. }
procedure TForm1.UpdateChangeNav;
var
  Blocks: TIntegerDynArray;
  Cur, Current, i: integer;
begin
  Blocks := ChangeBlocks;
  FNav.Visible := Length(Blocks) > 0;
  if Length(Blocks) = 0 then
    Exit;
  Cur := Edit.Carets[0].PosY;
  Current := 0;
  for i := 0 to High(Blocks) do
    if Blocks[i] <= Cur then
      Current := i + 1
    else
      Break;
  FNav.SetPosition(Current, Length(Blocks));
  { The pill sits left of the minimap, which shares the editor's right
    edge; RectMinimap is empty while the minimap is off or not yet laid
    out. }
  FNav.BorderSpacing.Right := 20 + Max(0, Edit.RectMinimap.Width);
end;

{ The caret event fires from inside the editor's own updates, where
  resizing a child (the navigator grows with its counter) makes the editor
  recompute its scroll position from a half-updated state and scroll
  sideways. So the update waits for the message loop. }
procedure TForm1.EditChangeCaretPos(Sender: TObject);
begin
  if FNavUpdateQueued then
    Exit;
  FNavUpdateQueued := True;
  Application.QueueAsyncCall(@UpdateChangeNavAsync, 0);
end;

procedure TForm1.UpdateChangeNavAsync(Data: PtrInt);
begin
  FNavUpdateQueued := False;
  UpdateChangeNav;
end;

{ Jumps to the first line of the next (or previous) block of changed lines
  from the caret, wrapping around at either end. The block lands a few
  lines below the top edge so its context stays in view. }
procedure TForm1.GoToChange(ANext: boolean);
var
  Blocks: TIntegerDynArray;
  Cur, Target, i: integer;
begin
  Blocks := ChangeBlocks;
  if Length(Blocks) = 0 then
    Exit;
  Cur := Edit.Carets[0].PosY;
  Target := -1;
  if ANext then
  begin
    for i := 0 to High(Blocks) do
      if Blocks[i] > Cur then
      begin
        Target := Blocks[i];
        Break;
      end;
    if Target < 0 then
      Target := Blocks[0];
  end
  else
  begin
    for i := High(Blocks) downto 0 do
      if Blocks[i] < Cur then
      begin
        Target := Blocks[i];
        Break;
      end;
    if Target < 0 then
      Target := Blocks[High(Blocks)];
  end;
  Edit.DoCaretSingle(0, Target);
  Edit.LineTop := Max(0, Target - 3);
  Edit.Update;
  UpdateChangeNav;
end;

procedure TForm1.MenuNextChangeClick(Sender: TObject);
begin
  GoToChange(True);
end;

procedure TForm1.MenuPrevChangeClick(Sender: TObject);
begin
  GoToChange(False);
end;

{ ---------------------------------------------------------------------------
  Repository
  ---------------------------------------------------------------------------
  The editor shows the work tree's uncommitted changes as a unified diff
  under the Diff lexer; the file tree lists the changed files and the status
  bar counts them. }
procedure TForm1.OpenRepository(const ADir: string);
begin
  { Open closes the previous repository even when it fails. }
  StopWatcher;
  if not FRepo.Open(ADir) then
  begin
    MessageDlg(FRepo.Error, mtError, [mbOK], 0);
    Exit;
  end;
  Caption := ExtractFileName(FRepo.Root) + ' - Gittan';
  if not LoadRepository then
    MessageDlg(FRepo.Error, mtError, [mbOK], 0);
  ShowSummary;
  StartWatcher;
end;

{ Reads the branch and the changed files of the open repository into the
  tree and the summary. Returns false, with the message in FRepo.Error,
  when git failed; the views are empty then. }
function TForm1.LoadRepository: boolean;
var
  Stats: TGittanFileStats;
  Icons: array of integer;
  i: integer;
begin
  Result := FRepo.ChangeStats(Stats);
  FBranch := FRepo.Branch;
  FFileCount := Length(Stats);
  FillFileTree(Stats);
  SetLength(Icons, Length(Stats));
  for i := 0 to High(Stats) do
    Icons[i] := ChangeIcon(Stats[i].Kind);
  FSummary.SetRepository(ExtractFileName(FRepo.Root), FBranch, Stats, Icons);
end;

{ ---------------------------------------------------------------------------
  Watching the repository
  ---------------------------------------------------------------------------
  The branch and the changed files are read when the repository is opened.
  A branch switch, a commit or an edit in another program happens behind
  Gittan's back, so a watcher thread polls git and RefreshRepository
  reloads the views in place when something changed. View > Refresh does
  the same by hand. }
procedure TForm1.StartWatcher;
begin
  StopWatcher;
  if FRepo.Root = '' then
    Exit;
  FWatcher := TGittanWatcher.Create(FRepo.Root, WatchInterval);
  FWatcher.OnChange := @WatcherChange;
  FWatcher.Start;
end;

procedure TForm1.StopWatcher;
begin
  FreeAndNil(FWatcher);
end;

procedure TForm1.WatcherChange(Sender: TObject);
begin
  RefreshRepository;
end;

procedure TForm1.MenuRefreshClick(Sender: TObject);
begin
  RefreshRepository;
end;

{ The path of the selected file in the tree, empty when none or a folder
  is selected. }
function TForm1.SelectedPath: string;
begin
  Result := '';
  if (FileTree.Selected <> nil) and (FileTree.Selected.Data <> nil) then
    Result := FileTree.Selected.GetTextPath;
end;

{ Reloads the repository and keeps what the user looks at: the folders
  opened in the tree, the selected file with its scroll position, or the
  repository diff. A selected file that is no longer changed gives way to
  the summary. Filling the tree drops the selection, so the view is noted
  first and restored by selecting the file again, which runs the usual
  selection handler. }
procedure TForm1.RefreshRepository;
var
  Expanded: TStringList;
  Node: TTreeNode;
  Path: string;
  View: TGittanView;
  TopLine, CaretY: integer;

  procedure RestoreScroll;
  begin
    if Edit.Strings.Count = 0 then
      Exit;
    Edit.DoCaretSingle(0, Min(CaretY, Edit.Strings.Count - 1));
    Edit.LineTop := Min(TopLine, Edit.Strings.Count - 1);
    Edit.Update;
  end;

begin
  if FRepo.Root = '' then
    Exit;
  View := FView;
  Path := SelectedPath;
  TopLine := Edit.LineTop;
  CaretY := Edit.Carets[0].PosY;
  Expanded := TStringList.Create;
  try
    Expanded.CaseSensitive := True;
    Node := FileTree.Items.GetFirstNode;
    while Node <> nil do
    begin
      if (Node.Data = nil) and Node.Expanded then
        Expanded.Add(Node.GetTextPath);
      Node := Node.GetNext;
    end;
    if not LoadRepository then
      StatusBar.SimpleText := FRepo.Error;
    Node := FileTree.Items.GetFirstNode;
    while Node <> nil do
    begin
      if (Node.Data = nil) and (Expanded.IndexOf(Node.GetTextPath) >= 0) then
        Node.Expand(False);
      Node := Node.GetNext;
    end;
  finally
    Expanded.Free;
  end;
  case View of
    gvChanges:
      begin
        SummarySelectFile(nil, Path);
        if FileTree.Selected = nil then
        begin
          ShowSummary;
          Caption := ExtractFileName(FRepo.Root) + ' - Gittan';
        end
        else
          RestoreScroll;
      end;
    gvRepoDiff:
      begin
        ShowRepoDiff;
        RestoreScroll;
      end;
  end;
  UpdateStatus;
end;

{ ---------------------------------------------------------------------------
  Summary and editor
  ---------------------------------------------------------------------------
  The summary and the editor share the space right of the tree; one of
  them is shown. The summary is the view of the repository, the editor the
  view of one file or of the raw repository diff. }
procedure TForm1.ShowSummary;
begin
  Edit.Visible := False;
  FSummaryBox.Visible := True;
  FView := gvSummary;
  { A file picked again after the summary must fire the selection event. }
  FileTree.Selected := nil;
  if FRepo.Root <> '' then
    UpdateStatus;
end;

procedure TForm1.ShowEditor;
begin
  FSummaryBox.Visible := False;
  Edit.Visible := True;
end;

{ The summary paints its own background; it must cover the scroll box. }
procedure TForm1.SummaryBoxResize(Sender: TObject);
begin
  FSummary.Constraints.MinHeight := FSummaryBox.ClientHeight;
end;

{ A click on a file in the summary selects it in the tree, which shows its
  changes. The tree's node texts are the path components. }
procedure TForm1.SummarySelectFile(Sender: TObject; const APath: string);
var
  Node: TTreeNode;
begin
  Node := FileTree.Items.GetFirstNode;
  while Node <> nil do
  begin
    if (Node.Data <> nil) and (Node.GetTextPath = APath) then
    begin
      FileTree.Selected := Node;
      Node.MakeVisible;
      Exit;
    end;
    Node := Node.GetNext;
  end;
end;

procedure TForm1.MenuSummaryClick(Sender: TObject);
begin
  if FRepo.Root <> '' then
    ShowSummary;
end;

procedure TForm1.MenuRepoDiffClick(Sender: TObject);
begin
  if FRepo.Root <> '' then
    ShowRepoDiff;
end;

{ The work tree's uncommitted changes as one unified diff under the Diff
  lexer, with the +/- lines colored like the change view. }
procedure TForm1.ShowRepoDiff;
var
  i: integer;
begin
  ShowText(FRepo.Diff, FLexers.ByName(rsDiffLexer));
  { The "---"/"+++" file headers are not changes. }
  for i := 0 to Edit.Strings.Count - 1 do
    if (Edit.Strings.LinesLen[i] > 0) and
      (Copy(Edit.Strings.Lines[i], 1, 3) <> '---') and
      (Copy(Edit.Strings.Lines[i], 1, 3) <> '+++') then
      MarkLine(i, char(Edit.Strings.Lines[i][1]));
  UpdateChangeNav;
  ShowEditor;
  FView := gvRepoDiff;
  FileTree.Selected := nil;
  Caption := ExtractFileName(FRepo.Root) + ' - Gittan';
  UpdateStatus;
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
    UpdateChangeNav;
    ShowEditor;
    FView := gvChanges;
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
procedure TForm1.FillFileTree(const AStats: TGittanFileStats);
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
    for i := 0 to High(AStats) do
    begin
      Path := AStats[i].Path;
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
        Node.ImageIndex := ChangeIcon(AStats[i].Kind);
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
