unit umain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ComCtrls,
  ExtCtrls, StdCtrls, LCLType, LazLoggerBase, Math, Types,
  ATSynEdit, ATSynEdit_Adapter_EControl, ATSynEdit_Bookmarks,
  ATSynEdit_Carets, ATSynEdit_Gutter_Decor, ATSynEdit_Globals, ATStringProc,
  ATSynEdit_Markers, ATSynEdit_LineParts, ATSynEdit_Ranges, ec_SyntAnal,
  gittan.lexers, gittan.git, gittan.icons, gittan.theme, gittan.changenav,
  gittan.summary, gittan.fileheader, gittan.watch, gittan.settings,
  gittan.findbar, gittan.worddiff;

type
  {** What the space right of the tree shows: the summary, one changed
    file, the raw repository diff, or a plain file from File > Open. }
  TGittanView = (gvSummary, gvChanges, gvRepoDiff, gvFile);

  {** One row of the change view. Line is the index of its diff line in
    the file's diff, rowGap for a row that stands for the unchanged lines
    GapFrom..GapTo hidden by View > Hide Unchanged Lines, or rowFiller
    for the blank row the side-by-side view puts opposite a line the
    other side has. A hidden row is in the text, so the lexer sees the
    whole file, but not on screen. }
  TGittanRow = record
    Line: integer;
    GapFrom, GapTo: integer;
    Hidden: boolean;
  end;
  TGittanRows = array of TGittanRow;

  { TForm1 }

  TForm1 = class(TForm)
    Edit: TATSynEdit;
    EditorPanel: TPanel;
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
    FAdapter, FAdapterOld: TATAdapterEControl;
    FLexers: TGittanLexers;
    FRepo: TGittanRepo;
    FSettings: TGittanSettings;
    FSyntaxMenu, FAutoLexerItem, FPlainTextItem: TMenuItem;
    FRecentMenu, FCompareMenu: TMenuItem;
    FWrapItem, FOnlyChangesItem, FSideItem, FIgnoreSpaceItem: TMenuItem;
    FContextItems: array of TMenuItem;
    FFilePopup, FStatusPopup: TPopupMenu;
    FRevealItem, FOpenItem: TMenuItem;
    FContextPath: string;
    FContextFromSummary: boolean;
    FHeader: TGittanFileHeader;
    FNav: TGittanChangeNav;
    FNavUpdateQueued: boolean;
    FFindBar: TGittanFindBar;
    FSummaryBox: TScrollBox;
    FSummary: TGittanSummary;
    FEditOld: TATSynEdit;
    FSideSplitter: TSplitter;
    FSideRatio: double;
    FSyncingScroll: boolean;
    FBranch: string;
    FFileCount: integer;
    FStats: TGittanFileStats;
    FLoadError: string;
    FAppIcon: TIcon;
    FDark: boolean;
    FBookmarkBandWidth: integer;
    FWatcher: TGittanWatcher;
    FView: TGittanView;
    FManualLexer: boolean;
    { The change view: the diff lines of the shown file with their
      markers, the path they belong to, the gaps the user opened (pairs of
      first and last line index) and the rows the editor shows. }
    FChangeLines: TStringList;
    FCurrentPath: string;
    FExpanded: TIntegerDynArray;
    FRows: TGittanRows;
    FOnlyChanges, FSideBySide, FWordWrap, FIgnoreWhitespace: boolean;
    FContextLines: integer;
    { The spans of the changed lines that differ word by word, one entry
      per line of FChangeLines; see gittan.worddiff. }
    FWordSpans: TGittanLineSpans;
    { Scrolling on past the bottom of a file: the wheel delta pulled so
      far, the time of the last wheel event, whether a pull counts (not
      while the momentum of the gesture that just jumped runs on), the
      timer that forgets a pull left half way, and the colors of the
      pill that shows the pull. }
    FOverscroll: integer;
    FOverscrollTick: QWord;
    FOverscrollArmed: boolean;
    FOverscrollTimer: TTimer;
    FPullFill, FPullBorder, FPullText, FPullBar: TColor;
    procedure ApplyTheme;
    procedure ApplyEditorColors(AEd: TATSynEdit);
    procedure SetupEditor(AEd: TATSynEdit);
    function AdapterOf(AEd: TATSynEdit): TATAdapterEControl;
    procedure MenuRefreshClick(Sender: TObject);
    procedure WatcherChange(Sender: TObject);
    procedure StartWatcher;
    procedure StopWatcher;
    function LoadRepository: boolean;
    procedure RefreshRepository;
    procedure ShowError(const AMessage: string);
    function SelectedPath: string;
    function StatIcon(const AStat: TGittanFileStat): integer;
    procedure UpdateStatus;
    procedure UpdateSyntaxChecks;
    procedure UpdateCaption;
    procedure BuildMenu;
    procedure BuildSyntaxMenu;
    procedure MenuOpenClick(Sender: TObject);
    procedure MenuOpenRepoClick(Sender: TObject);
    procedure MenuSyntaxClick(Sender: TObject);
    procedure MenuAutoLexerClick(Sender: TObject);
    procedure MenuSummaryClick(Sender: TObject);
    procedure MenuRepoDiffClick(Sender: TObject);
    procedure SummaryBoxResize(Sender: TObject);
    procedure SummarySelectFile(Sender: TObject; const APath: string);
    procedure ShowSummary;
    procedure ShowEditor;
    procedure ShowRepoDiff;
    procedure MenuPrevChangeClick(Sender: TObject);
    procedure MenuNextChangeClick(Sender: TObject);
    function AutoLexer: TecSyntAnalyzer;
    procedure SetLexer(ALexer: TecSyntAnalyzer);
    procedure SetEditorLexer(AEd: TATSynEdit; ALexer: TecSyntAnalyzer);
    procedure ShowText(AEd: TATSynEdit; const AText: string; ALexer: TecSyntAnalyzer);
    procedure MarkLine(AEd: TATSynEdit; ALine: integer; AChange: char);
    procedure MarkRow(AEd: TATSynEdit; ARow, AKind: integer);
    procedure MarkWords(AEd: TATSynEdit; ARow: integer; const ASpans: TGittanSpans;
      AChange: char; AOffset: integer);
    function WordColor(ATag: integer): TColor;
    procedure RecolorWords(AEd: TATSynEdit);
    procedure SetLineStatesBand(AEd: TATSynEdit; AVisible: boolean);
    procedure SetRowNumbers(AEd: TATSynEdit; const ANumbers, AKinds: TIntegerDynArray);
    function LineNumberColor(AKind: integer): TColor;
    procedure ResetLineNumbers(AEd: TATSynEdit);
    procedure UpdateNumberWidth(AEd: TATSynEdit);
    function ChangeBlocks: TIntegerDynArray;
    procedure UpdateChangeNav;
    procedure GoToChange(ANext: boolean);
    procedure ShowChanges(const APath: string);
    procedure FillFileTree(const AStats: TGittanFileStats);
    function CompareTreeNodes(Node1, Node2: TTreeNode): integer;
    { umain.diffview.inc }
    procedure BuildChangeView;
    procedure FillChangeEditor(AEd: TATSynEdit; const ARows: TGittanRows;
      AOldSide: boolean; const AOldNum, ANewNum: TIntegerDynArray;
      ALexer: TecSyntAnalyzer);
    function VisibleRow(ARow: integer): integer;
    procedure ExpandGap(AFrom, ATo: integer);
    procedure EditMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: integer);
    procedure EditorScroll(Sender: TObject);
    procedure SyncOldSide;
    procedure SyncOldSideAsync(Data: PtrInt);
    procedure EditorPanelResize(Sender: TObject);
    procedure SideSplitterMoved(Sender: TObject);
    procedure ApplyLayout;
    procedure ApplyWrap;
    procedure RebuildIfChanges;
    { umain.actions.inc }
    procedure ApplySettings;
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure RebuildRecentMenu;
    procedure MenuRecentClick(Sender: TObject);
    procedure MenuClearRecentClick(Sender: TObject);
    procedure MenuFindClick(Sender: TObject);
    procedure MenuFindNextClick(Sender: TObject);
    procedure MenuFindPrevClick(Sender: TObject);
    procedure FindBarSearch(Sender: TObject; const AText: string; ANext, AFromStart: boolean);
    procedure FindBarClose(Sender: TObject);
    procedure FindText(const AText: string; ANext, AFromStart: boolean);
    procedure MenuZoomInClick(Sender: TObject);
    procedure MenuZoomOutClick(Sender: TObject);
    procedure MenuZoomResetClick(Sender: TObject);
    procedure MenuFontClick(Sender: TObject);
    procedure MenuWrapClick(Sender: TObject);
    procedure MenuOnlyChangesClick(Sender: TObject);
    procedure MenuContextLinesClick(Sender: TObject);
    procedure MenuSideBySideClick(Sender: TObject);
    procedure MenuIgnoreSpaceClick(Sender: TObject);
    procedure MenuNextFileClick(Sender: TObject);
    procedure MenuPrevFileClick(Sender: TObject);
    function StepFile(ANext: boolean): boolean;
    function NeighbourFile(ANext: boolean): TTreeNode;
    procedure EditMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
    procedure SetOverscroll(AValue: integer);
    procedure OverscrollTimerTimer(Sender: TObject);
    procedure EditDrawEditor(Sender: TObject; C: TCanvas; const ARect: TRect);
    procedure BuildPopups;
    procedure FilePopupPopup(Sender: TObject);
    procedure SummaryContextFile(Sender: TObject; const APath: string;
      const AScreenPos: TPoint);
    function ContextFullPath: string;
    procedure MenuCopyPathClick(Sender: TObject);
    procedure MenuCopyRelativePathClick(Sender: TObject);
    procedure MenuRevealClick(Sender: TObject);
    procedure MenuOpenInEditorClick(Sender: TObject);
    procedure StatusBarClick(Sender: TObject);
    procedure MenuCopyBranchClick(Sender: TObject);
    procedure MenuCopyRepoPathClick(Sender: TObject);
    procedure RebuildCompareMenu;
    procedure MenuCompareClick(Sender: TObject);
    procedure MenuCompareOtherClick(Sender: TObject);
    procedure SetBase(const ARef: string);
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

uses
  Clipbrd, LCLIntf, Process;

resourcestring
  rsFile = '&File';
  rsOpen = '&Open...';
  rsOpenRepo = 'Open &Repository...';
  rsOpenRecent = 'Open Re&cent';
  rsClearMenu = 'Clear Menu';
  rsSyntax = '&Syntax';
  rsAutomatic = '&Automatic';
  rsView = '&View';
  rsSummary = '&Summary';
  rsRepoDiff = '&Repository Diff';
  rsRefresh = 'Re&fresh';
  rsCompareWith = '&Compare With';
  rsWorkingTree = 'HEAD (Working Tree)';
  rsOtherRef = 'Other...';
  rsRefPrompt = 'Branch, tag or commit to compare the working tree against:';
  rsOnlyChanges = '&Hide Unchanged Lines';
  rsContextLines = 'Conte&xt Lines';
  rsNLines = '%d lines';
  rsSideBySide = 'Side &by Side';
  rsWordWrap = '&Word Wrap';
  rsIgnoreSpace = 'I&gnore Whitespace';
  rsZoomIn = 'Zoom &In';
  rsZoomOut = 'Zoom &Out';
  rsZoomReset = 'Actual Si&ze';
  rsFont = 'Fo&nt...';
  rsDropHint = 'Open a repository, or drop a folder or file here.';
  rsDropShortcut = 'File > Open Repository    %s';
  rsGo = '&Go';
  rsFind = '&Find...';
  rsFindNext = 'Find &Next';
  rsFindPrev = 'Find &Previous';
  rsNextChange = 'Next &Change';
  rsPrevChange = 'Previous C&hange';
  rsNextFile = 'Next F&ile';
  rsPrevFile = 'Previous Fi&le';
  rsCopyPath = 'Copy &Path';
  rsCopyRelativePath = 'Copy &Relative Path';
  rsOpenInEditor = 'Open in &Editor';
  rsCopyBranch = 'Copy &Branch Name';
  rsCopyRepoPath = 'Copy Repository &Path';
  rsPlainText = 'Plain text';
  rsNoLexers = 'No lexers found. Run "make lexlib" or set GITTAN_LEXLIB.';
  rsLexerCount = '%d lexers';
  rsDiffLexer = 'Diff';
  rsRepoOnBranch = '%s on %s';
  rsVsBase = 'vs %s';
  rsRepoDiffTitle = 'Repository diff';
  rsChangedFiles = '%d changed files';
  rsOneChangedFile = '1 changed file';
  rsNoChanges = 'no changes';
  rsNoLongerChanged = '%s has no changes any more.';
  rsGapLines = '⋯  %d unchanged lines  ⋯';
  rsGapLine = '⋯  1 unchanged line  ⋯';
  rsPullNext = 'Next: %s  ↓';

const
  { Scrolling on past the bottom of a file goes to the next one: the
    wheel delta the pull needs (120 is one notch of a mouse wheel, 8 one
    pixel of a trackpad on macOS), the quiet time after which a pull left
    half way is forgotten, and the pause that tells a new gesture from
    the momentum of the one that jumped. Milliseconds. }
  OverscrollNeeded = 600;
  OverscrollForget = 1200;
  OverscrollPause = 300;
  rsReveal = {$IFDEF DARWIN}'Reveal in &Finder'{$ELSE}
    {$IFDEF WINDOWS}'Show in &Explorer'{$ELSE}'Show in &File Manager'{$ENDIF}{$ENDIF};
  { Bookmark kinds in the editor's second bookmark list, used only for the
    line backgrounds of a diff: an added line, a deleted one, a gap row
    standing for hidden lines, and a filler row of the side-by-side
    view. }
  bmAdded = 1;
  bmDeleted = 2;
  bmGap = 3;
  bmFiller = 4;
  { Tags of the editor's attribs that mark the words that differ inside
    an added or a deleted line. }
  tagWordAdded = 1;
  tagWordDeleted = 2;
  { Row kinds in TGittanRow.Line. }
  rowGap = -1;
  rowFiller = -2;
  { How often the watcher asks git whether the repository changed. }
  WatchInterval = 2000;
  { The choices of View > Context Lines. }
  ContextChoices: array[0..3] of integer = (1, 3, 5, 10);
  { Matches beyond this are not counted; the find bar says "10000+". }
  MaxMatches = 10000;

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  FSettings := TGittanSettings.Create;
  FSettings.Load;
  FChangeLines := TStringList.Create;
  FSideRatio := 0.5;
  { The editor comes from umain.lfm. The EControl adapter is not an IDE
    component, so it is created here. Gittan is a viewer, so the editor is
    read-only; ShowText and OpenFile lift that while they replace the text. }
  FAdapter := TATAdapterEControl.Create(Self);
  FAdapter.AddEditor(Edit);
  SetupEditor(Edit);
  { The minimap shows where in the file the changes are: it paints the
    same line backgrounds as the text. }
  Edit.OptMinimapVisible := True;
  Edit.OptMinimapTooltipVisible := False;
  { A fixed, narrow minimap; the default takes a fifth of the editor. }
  Edit.OptMinimapCharWidth := 30;
  Edit.OnChangeCaretPos := @EditChangeCaretPos;
  { Scrolling on past the bottom pulls in the next file; the pill that
    shows the pull is painted over the text (see EditMouseWheel). }
  Edit.OnDrawEditor := @EditDrawEditor;
  FOverscrollArmed := True;
  FOverscrollTimer := TTimer.Create(Self);
  FOverscrollTimer.Enabled := False;
  FOverscrollTimer.Interval := OverscrollForget;
  FOverscrollTimer.OnTimer := @OverscrollTimerTimer;
  FBookmarkBandWidth := Edit.OptGutterWidthBookmarks;
  { The second editor shows the old side of the side-by-side view, left
    of the first, which then shows the new side. It has its own adapter,
    since an adapter parses one text. }
  FEditOld := TATSynEdit.Create(Self);
  FEditOld.Parent := EditorPanel;
  FEditOld.Align := alLeft;
  FEditOld.Width := EditorPanel.ClientWidth div 2;
  FEditOld.Visible := False;
  FEditOld.OptRulerVisible := False;
  FEditOld.OptUnprintedVisible := False;
  FEditOld.OptMinimapVisible := False;
  FAdapterOld := TATAdapterEControl.Create(Self);
  FAdapterOld.AddEditor(FEditOld);
  SetupEditor(FEditOld);
  FSideSplitter := TSplitter.Create(Self);
  FSideSplitter.Parent := EditorPanel;
  FSideSplitter.Align := alLeft;
  FSideSplitter.Left := FEditOld.Width + 1;
  FSideSplitter.Visible := False;
  FSideSplitter.OnMoved := @SideSplitterMoved;
  EditorPanel.OnResize := @EditorPanelResize;

  FillTreeIcons(TreeImages);
  FileTree.Options := FileTree.Options + [tvoRightClickSelect];
  { The header names what the editor shows and holds the change
    navigator; it sits above the editor in the panel the two share with
    the summary. }
  FHeader := TGittanFileHeader.Create(Self);
  FHeader.Parent := EditorPanel;
  FHeader.Align := alTop;
  FHeader.Images := TreeImages;
  FHeader.Visible := False;
  FNav := FHeader.Nav;
  FNav.OnPrev := @MenuPrevChangeClick;
  FNav.OnNext := @MenuNextChangeClick;
  UpdateChangeNav;
  { The find bar sits under the header, above the editor. }
  FFindBar := TGittanFindBar.Create(Self);
  FFindBar.Parent := EditorPanel;
  FFindBar.Top := FHeader.Height;
  FFindBar.Align := alTop;
  FFindBar.Visible := False;
  FFindBar.OnSearch := @FindBarSearch;
  FFindBar.OnClose := @FindBarClose;
  { The summary takes the editor's place until a file is picked. The
    scroll box gives it native scrolling; its resize keeps the summary at
    least as tall as the box, so the summary's background fills it. }
  FSummaryBox := TScrollBox.Create(Self);
  FSummaryBox.Parent := EditorPanel;
  FSummaryBox.Align := alClient;
  FSummaryBox.BorderStyle := bsNone;
  FSummaryBox.HorzScrollBar.Visible := False;
  FSummaryBox.OnResize := @SummaryBoxResize;
  FSummary := TGittanSummary.Create(Self);
  FSummary.Parent := FSummaryBox;
  FSummary.Images := TreeImages;
  FSummary.OnSelectFile := @SummarySelectFile;
  FSummary.OnContextFile := @SummaryContextFile;
  { The summary draws the application icon in its empty view, from its
    own copy: Application.Icon keeps to its small image. }
  FAppIcon := TIcon.Create;
  try
    FAppIcon.LoadFromResourceName(HInstance, 'MAINICON');
  except
    FreeAndNil(FAppIcon);
  end;
  FSummary.SetMessage(rsDropHint, Format(rsDropShortcut,
    [{$IFDEF DARWIN}'⇧⌘O'{$ELSE}'Ctrl+Shift+O'{$ENDIF}]), FAppIcon);

  FRepo := TGittanRepo.Create;
  FLexers := TGittanLexers.Create;
  if FLexers.Load then
    StatusBar.SimpleText := Format(rsLexerCount, [0])
  else
    StatusBar.SimpleText := rsNoLexers;
  if FLexers.Errors <> '' then
    DebugLn(FLexers.Errors);
  StatusBar.OnClick := @StatusBarClick;
  FDark := IsDarkMode;
  ApplyTheme;

  ApplySettings;
  BuildMenu;
  BuildPopups;
  ApplyWrap;
  OnClose := @FormClose;
  ShowSummary;
  { gittan [file | folder], else the repository of the last run. }
  if ParamCount > 0 then
  begin
    if DirectoryExists(ParamStr(1)) then
      OpenRepository(ParamStr(1))
    else
      OpenFile(ParamStr(1));
  end
  else if (FSettings.Recent.Count > 0) and DirectoryExists(FSettings.Recent[0]) then
    OpenRepository(FSettings.Recent[0]);
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  Application.RemoveAsyncCalls(Self);
  StopWatcher;
  FAdapter.Lexer := nil;
  FAdapterOld.Lexer := nil;
  FreeAndNil(FLexers);
  FreeAndNil(FRepo);
  FreeAndNil(FAppIcon);
  FreeAndNil(FChangeLines);
  FreeAndNil(FSettings);
end;

{ The options both editors share: read-only, every line numbered (the
  change view numbers lines itself, see SetRowNumbers, and the file view
  should look the same), fold icons only under the mouse, and the line
  states band hidden until a diff is shown. }
procedure TForm1.SetupEditor(AEd: TATSynEdit);
var
  Band: integer;
begin
  AEd.ModeReadOnly := True;
  AEd.OptNumbersStyle := TATEditorNumbersStyle.All;
  AEd.GutterDecorAlignment := taRightJustify;
  AEd.OnChangeZoom := @EditChangeZoom;
  AEd.OnCalcBookmarkColor := @EditCalcBookmarkColor;
  AEd.OnMouseUp := @EditMouseUp;
  AEd.OnScroll := @EditorScroll;
  AEd.OnMouseWheel := @EditMouseWheel;
  { The fold band is hidden: in a viewer the fold icons are noise, and
    the change view hides lines through the folding mechanism (see
    BuildChangeView), which a fold or unfold of a lexer range would
    disturb. Folding itself stays enabled, since the wrap info skips
    hidden lines only then, and only while a fold range exists (see
    FillChangeEditor). }
  AEd.OptGutterShowFoldAlways := False;
  Band := AEd.Gutter.FindIndexByTag(ATEditorOptions.GutterTagFolding);
  if Band >= 0 then
    AEd.Gutter[Band].Visible := False;
  { A row followed by hidden lines gets a dashed underline; the gap row
    already says what is left out. }
  ATEditorOptions.FoldedUnderlineStyle := TATEditorFoldedUnderlineStyle.None;
  SetLineStatesBand(AEd, False);
end;

function TForm1.AdapterOf(AEd: TATSynEdit): TATAdapterEControl;
begin
  if AEd = FEditOld then
    Result := FAdapterOld
  else
    Result := FAdapter;
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
procedure TForm1.ApplyEditorColors(AEd: TATSynEdit);
var
  i: integer;
begin
  AEd.Colors.Init;
  { The strip in the gutter: added lines green, deleted (the "changed"
    state) red, in the summary's colors. }
  if FDark then
  begin
    AEd.Colors.StateAdded := RGBToColor(63, 185, 80);
    AEd.Colors.StateChanged := RGBToColor(248, 81, 73);
  end
  else
  begin
    AEd.Colors.StateAdded := RGBToColor(26, 127, 55);
    AEd.Colors.StateChanged := RGBToColor(207, 34, 46);
  end;
  if FDark then
    with AEd.Colors do
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
  { The change view's line numbers carry their own color: the strip's
    green on an added line. }
  for i := 0 to AEd.GutterDecor.Count - 1 do
    AEd.GutterDecor.ItemPtr(i)^.Data.TextColor := LineNumberColor(
      AEd.GutterDecor.ItemPtr(i)^.Data.Tag);
  AEd.Invalidate;
end;

procedure TForm1.ApplyTheme;
begin
  ApplyEditorColors(Edit);
  ApplyEditorColors(FEditOld);
  FLexers.ApplyTheme(FDark);
  { The header and the find bar take the gutter's shade; the navigator
    pills sit on it. }
  if FDark then
  begin
    FHeader.SetColors(RGBToColor(37, 37, 38), Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(63, 185, 80), RGBToColor(248, 81, 73),
      RGBToColor(62, 62, 62));
    FNav.SetColors(RGBToColor(37, 37, 38), RGBToColor(50, 50, 51),
      RGBToColor(85, 85, 86), RGBToColor(200, 200, 200), RGBToColor(100, 160, 240));
    FFindBar.SetColors(RGBToColor(37, 37, 38), Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(62, 62, 62));
    FFindBar.Nav.SetColors(RGBToColor(37, 37, 38), RGBToColor(50, 50, 51),
      RGBToColor(85, 85, 86), RGBToColor(200, 200, 200), RGBToColor(100, 160, 240));
    FPullFill := RGBToColor(50, 50, 51);
    FPullBorder := RGBToColor(85, 85, 86);
    FPullText := RGBToColor(200, 200, 200);
    FPullBar := RGBToColor(40, 80, 130);
  end
  else
  begin
    FHeader.SetColors(RGBToColor(246, 246, 246), RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(26, 127, 55), RGBToColor(207, 34, 46),
      RGBToColor(222, 222, 222));
    FNav.SetColors(RGBToColor(246, 246, 246), clWhite,
      RGBToColor(205, 205, 205), RGBToColor(70, 70, 70), RGBToColor(0, 110, 230));
    FFindBar.SetColors(RGBToColor(246, 246, 246), RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(222, 222, 222));
    FFindBar.Nav.SetColors(RGBToColor(246, 246, 246), clWhite,
      RGBToColor(205, 205, 205), RGBToColor(70, 70, 70), RGBToColor(0, 110, 230));
    FPullFill := clWhite;
    FPullBorder := RGBToColor(205, 205, 205);
    FPullText := RGBToColor(70, 70, 70);
    FPullBar := RGBToColor(205, 225, 250);
  end;
  FSummaryBox.Color := Edit.Colors.TextBG;
  if FDark then
    FSummary.SetColors(Edit.Colors.TextBG, Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(45, 45, 46), RGBToColor(38, 38, 39),
      RGBToColor(63, 185, 80), RGBToColor(248, 81, 73), RGBToColor(62, 62, 62))
  else
    FSummary.SetColors(Edit.Colors.TextBG, RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(243, 243, 243), RGBToColor(248, 248, 248),
      RGBToColor(26, 127, 55), RGBToColor(207, 34, 46), RGBToColor(222, 222, 222));
  RecolorWords(Edit);
  RecolorWords(FEditOld);
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

{ The window is named after the repository, or the file when none is
  open; the header names the file, so the title does not change with it. }
procedure TForm1.UpdateCaption;
begin
  if FRepo.Root <> '' then
    Caption := ExtractFileName(FRepo.Root) + ' - Gittan'
  else if Edit.FileName <> '' then
    Caption := ExtractFileName(Edit.FileName) + ' - Gittan'
  else
    Caption := 'Gittan';
end;

{ The status bar names the repository, its branch and the base it is
  compared against while one is open (the header names the file and its
  lexer); the full file path when a plain file is open without a
  repository; else the lexer name. The full path is in the hint. }
procedure TForm1.UpdateStatus;
var
  Lexer, Repo: string;
begin
  if FAdapter.Lexer = nil then
    Lexer := rsPlainText
  else
    Lexer := FAdapter.Lexer.LexerName;
  FHeader.SetLexer(Lexer);
  UpdateSyntaxChecks;
  Repo := '';
  if FRepo.Root <> '' then
  begin
    Repo := Format(rsRepoOnBranch, [ExtractFileName(FRepo.Root), FBranch]);
    if FBranch = '' then
      Repo := ExtractFileName(FRepo.Root);
    if FRepo.Base <> '' then
      Repo := Repo + ' ' + Format(rsVsBase, [FRepo.Base]);
  end;
  if Repo <> '' then
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
    StatusBar.SimpleText := Edit.FileName;
    StatusBar.Hint := Edit.FileName;
  end
  else
  begin
    StatusBar.SimpleText := Lexer;
    StatusBar.Hint := '';
  end;
end;

{ The Syntax menu marks the lexer in use and, when it was picked from the
  file name, Automatic as well. }
procedure TForm1.UpdateSyntaxChecks;
var
  Group, Item: TMenuItem;
  Current: string;
  i, j: integer;
begin
  if FAutoLexerItem = nil then
    Exit;
  FAutoLexerItem.Checked := not FManualLexer;
  if FAdapter.Lexer = nil then
    Current := ''
  else
    Current := FAdapter.Lexer.LexerName;
  FPlainTextItem.Checked := Current = '';
  for i := 0 to FSyntaxMenu.Count - 1 do
  begin
    Group := FSyntaxMenu.Items[i];
    for j := 0 to Group.Count - 1 do
    begin
      Item := Group.Items[j];
      Item.Checked := Item.Hint = Current;
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  Menus
  --------------------------------------------------------------------------- }
procedure TForm1.BuildMenu;
var
  Main: TMainMenu;
  FileMenu, ViewMenu, GoMenu, Item, Sub: TMenuItem;
  i: integer;

  function AddItem(AParent: TMenuItem; const ACaption: string; AShortCut: TShortCut;
    AClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(AParent);
    Result.Caption := ACaption;
    Result.ShortCut := AShortCut;
    Result.OnClick := AClick;
    AParent.Add(Result);
  end;

begin
  Main := TMainMenu.Create(Self);
  Menu := Main;

  FileMenu := TMenuItem.Create(Main);
  FileMenu.Caption := rsFile;
  Main.Items.Add(FileMenu);
  AddItem(FileMenu, rsOpenRepo, ShortCut(VK_O, [ssModifier, ssShift]), @MenuOpenRepoClick);
  FRecentMenu := AddItem(FileMenu, rsOpenRecent, 0, nil);
  RebuildRecentMenu;
  AddItem(FileMenu, rsOpen, ShortCut(VK_O, [ssModifier]), @MenuOpenClick);

  ViewMenu := TMenuItem.Create(Main);
  ViewMenu.Caption := rsView;
  Main.Items.Add(ViewMenu);
  AddItem(ViewMenu, rsSummary, ShortCut(VK_1, [ssModifier]), @MenuSummaryClick);
  AddItem(ViewMenu, rsRepoDiff, ShortCut(VK_2, [ssModifier]), @MenuRepoDiffClick);
  ViewMenu.Add(NewLine);
  FCompareMenu := AddItem(ViewMenu, rsCompareWith, 0, nil);
  RebuildCompareMenu;
  AddItem(ViewMenu, rsRefresh, ShortCut(VK_R, [ssModifier]), @MenuRefreshClick);
  ViewMenu.Add(NewLine);
  FOnlyChangesItem := AddItem(ViewMenu, rsOnlyChanges, ShortCut(VK_U, [ssModifier, ssShift]),
    @MenuOnlyChangesClick);
  FOnlyChangesItem.Checked := FOnlyChanges;
  Sub := AddItem(ViewMenu, rsContextLines, 0, nil);
  SetLength(FContextItems, Length(ContextChoices));
  for i := 0 to High(ContextChoices) do
  begin
    Item := AddItem(Sub, Format(rsNLines, [ContextChoices[i]]), 0, @MenuContextLinesClick);
    Item.Tag := ContextChoices[i];
    Item.RadioItem := True;
    Item.Checked := ContextChoices[i] = FContextLines;
    FContextItems[i] := Item;
  end;
  FSideItem := AddItem(ViewMenu, rsSideBySide, ShortCut(VK_S, [ssModifier, ssShift]),
    @MenuSideBySideClick);
  FSideItem.Checked := FSideBySide;
  FWrapItem := AddItem(ViewMenu, rsWordWrap, ShortCut(VK_W, [ssModifier, ssAlt]),
    @MenuWrapClick);
  FWrapItem.Checked := FWordWrap;
  FIgnoreSpaceItem := AddItem(ViewMenu, rsIgnoreSpace, ShortCut(VK_I, [ssModifier, ssAlt]),
    @MenuIgnoreSpaceClick);
  FIgnoreSpaceItem.Checked := FIgnoreWhitespace;
  ViewMenu.Add(NewLine);
  AddItem(ViewMenu, rsZoomIn, ShortCut(VK_OEM_PLUS, [ssModifier]), @MenuZoomInClick);
  AddItem(ViewMenu, rsZoomOut, ShortCut(VK_OEM_MINUS, [ssModifier]), @MenuZoomOutClick);
  AddItem(ViewMenu, rsZoomReset, ShortCut(VK_0, [ssModifier]), @MenuZoomResetClick);
  AddItem(ViewMenu, rsFont, 0, @MenuFontClick);

  FSyntaxMenu := TMenuItem.Create(Main);
  FSyntaxMenu.Caption := rsSyntax;
  Main.Items.Add(FSyntaxMenu);
  BuildSyntaxMenu;

  GoMenu := TMenuItem.Create(Main);
  GoMenu.Caption := rsGo;
  Main.Items.Add(GoMenu);
  AddItem(GoMenu, rsFind, ShortCut(VK_F, [ssModifier]), @MenuFindClick);
  AddItem(GoMenu, rsFindNext, ShortCut(VK_G, [ssModifier]), @MenuFindNextClick);
  AddItem(GoMenu, rsFindPrev, ShortCut(VK_G, [ssModifier, ssShift]), @MenuFindPrevClick);
  GoMenu.Add(NewLine);
  AddItem(GoMenu, rsNextChange, ShortCut(VK_F7, []), @MenuNextChangeClick);
  AddItem(GoMenu, rsPrevChange, ShortCut(VK_F7, [ssShift]), @MenuPrevChangeClick);
  GoMenu.Add(NewLine);
  AddItem(GoMenu, rsNextFile, ShortCut(VK_F8, []), @MenuNextFileClick);
  AddItem(GoMenu, rsPrevFile, ShortCut(VK_F8, [ssShift]), @MenuPrevFileClick);
end;

{ Automatic and Plain text first, then the lexer list, which is long
  (hundreds of entries), grouped into one submenu per initial letter. The
  item caption is the lexer name; the hint keeps it without the
  accelerator ampersands the widgetset may insert. }
procedure TForm1.BuildSyntaxMenu;
var
  Names: TStringList;
  Group, Item: TMenuItem;
  LexName, Initial, LastInitial: string;
begin
  FAutoLexerItem := TMenuItem.Create(FSyntaxMenu);
  FAutoLexerItem.Caption := rsAutomatic;
  FAutoLexerItem.OnClick := @MenuAutoLexerClick;
  FSyntaxMenu.Add(FAutoLexerItem);
  FPlainTextItem := TMenuItem.Create(FSyntaxMenu);
  FPlainTextItem.Caption := rsPlainText;
  FPlainTextItem.OnClick := @MenuSyntaxClick;
  FSyntaxMenu.Add(FPlainTextItem);
  FSyntaxMenu.Add(NewLine);

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
      Item.Hint := LexName;
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
begin
  FManualLexer := True;
  if Sender = FPlainTextItem then
    SetLexer(nil)
  else
    SetLexer(FLexers.ByName(TMenuItem(Sender).Hint));
end;

procedure TForm1.MenuAutoLexerClick(Sender: TObject);
begin
  FManualLexer := False;
  SetLexer(AutoLexer);
end;

{ ---------------------------------------------------------------------------
  Files and lexers
  --------------------------------------------------------------------------- }

{ The lexer the shown text gets by itself: from the file name, or the
  Diff lexer for the repository diff. }
function TForm1.AutoLexer: TecSyntAnalyzer;
begin
  case FView of
    gvChanges: Result := FLexers.ForFile(FCurrentPath);
    gvRepoDiff: Result := FLexers.ByName(rsDiffLexer);
    gvFile: Result := FLexers.ForFile(Edit.FileName);
    else
      Result := nil;
  end;
end;

procedure TForm1.SetEditorLexer(AEd: TATSynEdit; ALexer: TecSyntAnalyzer);
begin
  AdapterOf(AEd).Lexer := ALexer;
  { Assigning a lexer does not parse anything yet; a change event from line 0
    starts the adapter's background parse of the whole text. }
  if ALexer <> nil then
    AEd.DoEventChange(0);
  AEd.Update;
end;

{ Both editors show the same file, so they get the same lexer; the old
  side only while it is shown. }
procedure TForm1.SetLexer(ALexer: TecSyntAnalyzer);
begin
  SetEditorLexer(Edit, ALexer);
  if FEditOld.Visible then
    SetEditorLexer(FEditOld, ALexer);
  UpdateStatus;
end;

{ Replaces the text with generated content that belongs to no file. A
  read-only ATSynEdit ignores assignments to Text, so read-only mode is
  lifted while the text is replaced. Loading does not clear the second
  bookmark list, so the diff colors are dropped here. }
procedure TForm1.ShowText(AEd: TATSynEdit; const AText: string;
  ALexer: TecSyntAnalyzer);
var
  i: integer;
begin
  AdapterOf(AEd).Lexer := nil;
  AEd.BookmarkDeleteAll_2;
  ResetLineNumbers(AEd);
  AEd.ModeReadOnly := False;
  AEd.Text := UTF8Decode(AText);
  { Setting Text skips the wrap rebuild while the editor has no fold ranges
    (it is in "virtual" wrap mode then) and never flags one as needed, so
    once the lexer adds folds the wrap items of the previous text are
    reused and lines paint cut off. LoadFromFile clears the wrap info and
    flags the rebuild itself; do the same here. }
  AEd.WrapInfo.Clear;
  AEd.Update(True);
  AEd.ModeReadOnly := True;
  AEd.FileName := '';
  AEd.Modified := False;
  AEd.DoCaretSingle(0, 0);
  AEd.LineTop := 0;
  { The text comes with every line in the "added" state; MarkLine sets
    the states of the diff. }
  for i := 0 to AEd.Strings.Count - 1 do
    AEd.Strings.LinesState[i] := TATLineState.None;
  SetLineStatesBand(AEd, True);
  SetEditorLexer(AEd, ALexer);
end;

procedure TForm1.OpenFile(const AFileName: string);
begin
  FAdapter.Lexer := nil;
  Edit.BookmarkDeleteAll_2;
  ResetLineNumbers(Edit);
  Edit.ModeReadOnly := False;
  Edit.LoadFromFile(AFileName, []);
  Edit.ModeReadOnly := True;
  SetLineStatesBand(Edit, False);
  Edit.FileName := AFileName;
  FHeader.SetFile(AFileName, -1);
  FSummary.Selected := '';
  FCurrentPath := '';
  FManualLexer := False;
  FView := gvFile;
  SetLexer(FLexers.ForFile(AFileName));
  UpdateChangeNav;
  ShowEditor;
  UpdateCaption;
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
    read on top of it; a gap and a filler row take the gutter's shade. }
  if FDark then
    case ABookmarkKind of
      bmAdded: AColor := RGBToColor(32, 52, 37);
      bmDeleted: AColor := RGBToColor(66, 38, 38);
      bmGap: AColor := RGBToColor(44, 44, 46);
      bmFiller: AColor := RGBToColor(37, 37, 38);
    end
  else
    case ABookmarkKind of
      bmAdded: AColor := RGBToColor(218, 251, 225);
      bmDeleted: AColor := RGBToColor(255, 235, 233);
      bmGap: AColor := RGBToColor(238, 238, 238);
      bmFiller: AColor := RGBToColor(246, 246, 246);
    end;
end;

{ The shade of a word that differs, on top of the line's tint: the same
  hue, strong enough to be told from the line, faint enough for the
  syntax colors to read. }
function TForm1.WordColor(ATag: integer): TColor;
begin
  Result := clNone;
  if FDark then
    case ATag of
      tagWordAdded: Result := RGBToColor(38, 98, 54);
      tagWordDeleted: Result := RGBToColor(124, 52, 52);
    end
  else
    case ATag of
      tagWordAdded: Result := RGBToColor(171, 242, 188);
      tagWordDeleted: Result := RGBToColor(255, 196, 194);
    end;
end;

{ Marks ASpans of row ARow, an added ('+') or deleted ('-') line, through
  the editor's attribs: a line part with only a background color, so the
  lexer's text color stays. AOffset is added to every span, for a text
  that keeps the diff marker in its first column. }
procedure TForm1.MarkWords(AEd: TATSynEdit; ARow: integer; const ASpans: TGittanSpans;
  AChange: char; AOffset: integer);
var
  Part: TATLinePart;
  WordTag, i: integer;
begin
  if ASpans = nil then
    Exit;
  case AChange of
    '+': WordTag := tagWordAdded;
    '-': WordTag := tagWordDeleted;
    else
      Exit;
  end;
  InitLinePart(Part);
  Part.ColorBG := WordColor(WordTag);
  for i := 0 to High(ASpans) do
    AEd.Attribs.Add(Point(ASpans[i].Start + AOffset, ARow), Point(ASpans[i].Len, 0),
      TATMarkerTags.Init(WordTag, 0), @Part);
end;

{ After a theme change: the word marks take the colors of the new theme. }
procedure TForm1.RecolorWords(AEd: TATSynEdit);
var
  Item: TATMarkerItem;
  i: integer;
begin
  for i := 0 to AEd.Attribs.Count - 1 do
  begin
    Item := AEd.Attribs[i];
    if (Item.Tag = tagWordAdded) or (Item.Tag = tagWordDeleted) then
    begin
      Item.LinePart.ColorBG := WordColor(Item.Tag);
      AEd.Attribs[i] := Item;
    end;
  end;
end;

{ AChange is the first character of a unified diff line. Besides the
  background, the line gets a state for the gutter's line states band,
  which paints a strip in the state's color: "added" for an added line,
  "changed" for a deleted one. ShowText clears the states and shows the
  band. }
procedure TForm1.MarkLine(AEd: TATSynEdit; ALine: integer; AChange: char);
begin
  case AChange of
    '+':
      begin
        AEd.Strings.LinesState[ALine] := TATLineState.Added;
        MarkRow(AEd, ALine, bmAdded);
      end;
    '-':
      begin
        AEd.Strings.LinesState[ALine] := TATLineState.Changed;
        MarkRow(AEd, ALine, bmDeleted);
      end;
  end;
end;

{ The background alone, for a gap or filler row. }
procedure TForm1.MarkRow(AEd: TATSynEdit; ARow, AKind: integer);
begin
  AEd.BookmarkSetForLine_2(ARow, AKind, '', TATBookmarkAutoDelete.DontDelete,
    False, 0);
end;

{ The line states band is meant for an editor, where it marks the lines
  changed since the file was loaded or saved; a freshly set text has every
  line marked as new. Gittan shows it only for a diff, with the states set
  by MarkLine. }
procedure TForm1.SetLineStatesBand(AEd: TATSynEdit; AVisible: boolean);
var
  Band: integer;
begin
  Band := AEd.Gutter.FindIndexByTag(ATEditorOptions.GutterTagLineStates);
  if Band >= 0 then
    AEd.Gutter[Band].Visible := AVisible;
end;

{ ---------------------------------------------------------------------------
  Line numbers of the change view
  ---------------------------------------------------------------------------
  The change view keeps deleted lines in the text, so the editor's own
  numbering counts them and every line below a deletion shows a number
  too high. ATSynEdit has no hook for the number text, but its gutter
  "decor" draws a text per line in the bookmark band. So the number band
  is hidden, the bookmark band is widened to the number width, and each
  row gets its number in the file as decor text; a row without one (a
  deleted line in the unified view, a gap, a filler) gets none. The file
  view uses the editor's own numbering. }

{ ANumbers holds one number per row, 0 for none; AKinds the bookmark
  kind of the row, which colors the number. }
procedure TForm1.SetRowNumbers(AEd: TATSynEdit; const ANumbers, AKinds: TIntegerDynArray);
var
  Decor: TATGutterDecorData;
  Band, i: integer;
begin
  for i := 0 to High(ANumbers) do
  begin
    if ANumbers[i] = 0 then
      Continue;
    Decor := Default(TATGutterDecorData);
    Decor.LineNum := i;
    Decor.ImageIndex := -1;
    { The trailing space keeps the right-aligned number off the next band. }
    Decor.TextAll := IntToStr(ANumbers[i]) + ' ';
    { The tag keeps the kind, so ApplyTheme can recolor the number. }
    Decor.Tag := AKinds[i];
    Decor.TextColor := LineNumberColor(Decor.Tag);
    AEd.GutterDecor.Add(Decor);
  end;
  Band := AEd.Gutter.FindIndexByTag(ATEditorOptions.GutterTagNumbers);
  if Band >= 0 then
    AEd.Gutter[Band].Visible := False;
  Band := AEd.Gutter.FindIndexByTag(ATEditorOptions.GutterTagBookmarks);
  if Band >= 0 then
    AEd.Gutter[Band].Scaled := False;
  UpdateNumberWidth(AEd);
end;

{ An added line's number takes the strip's green, a deleted line's (on
  the old side) its red; the rest the gutter's usual color. }
function TForm1.LineNumberColor(AKind: integer): TColor;
begin
  case AKind of
    bmAdded: Result := Edit.Colors.StateAdded;
    bmDeleted: Result := Edit.Colors.StateChanged;
    else
      Result := Edit.Colors.GutterFont;
  end;
end;

{ Back to the editor's own numbering. }
procedure TForm1.ResetLineNumbers(AEd: TATSynEdit);
var
  Band: integer;
begin
  AEd.GutterDecor.Clear;
  Band := AEd.Gutter.FindIndexByTag(ATEditorOptions.GutterTagNumbers);
  if Band >= 0 then
    AEd.Gutter[Band].Visible := True;
  Band := AEd.Gutter.FindIndexByTag(ATEditorOptions.GutterTagBookmarks);
  if Band >= 0 then
    AEd.Gutter[Band].Scaled := True;
  AEd.OptGutterWidthBookmarks := FBookmarkBandWidth;
end;

{ The bookmark band holds the line numbers while the change view is shown:
  room for the widest number (its text has the trailing space) and one
  character of indent. The band width is reapplied by the editor on every
  update, so the option is set rather than the band. }
procedure TForm1.UpdateNumberWidth(AEd: TATSynEdit);
var
  CharWidth, Widest, i: integer;
begin
  if AEd.GutterDecor.Count = 0 then
    Exit;
  Widest := 0;
  for i := 0 to AEd.GutterDecor.Count - 1 do
    Widest := Max(Widest, Length(AEd.GutterDecor.ItemPtr(i)^.Data.TextAll));
  CharWidth := AEd.TextCharSize.XScaled div ATEditorCharXScale;
  AEd.OptGutterWidthBookmarks := (Widest + 1) * CharWidth;
end;

{ Zooming changes the character width the number band is sized from. The
  two editors zoom together. }
procedure TForm1.EditChangeZoom(Sender: TObject);
var
  Other: TATSynEdit;
begin
  if Sender = FEditOld then
    Other := Edit
  else
    Other := FEditOld;
  if Other.OptScaleFont <> TATSynEdit(Sender).OptScaleFont then
    Other.OptScaleFont := TATSynEdit(Sender).OptScaleFont;
  UpdateNumberWidth(Edit);
  UpdateNumberWidth(FEditOld);
end;

{ ---------------------------------------------------------------------------
  Change navigation
  ---------------------------------------------------------------------------
  The navigator in the header, and the Go menu, jump between the blocks of
  changed lines. }

{ The first line of every block of changed lines, in order. The second
  bookmark list is sorted by line; a block starts where the line before is
  not marked. A gap row is not a change; a filler row of the side-by-side
  view stands for a deleted line and is part of its block. }
function TForm1.ChangeBlocks: TIntegerDynArray;
var
  Marks: TATBookmarks;
  Line, Prev, i, n: integer;
begin
  Result := nil;
  Marks := Edit.Strings.Bookmarks2;
  SetLength(Result, Marks.Count);
  n := 0;
  Prev := -2;
  for i := 0 to Marks.Count - 1 do
  begin
    if Marks[i]^.Data.Kind = bmGap then
      Continue;
    Line := Marks[i]^.Data.LineNum;
    if Prev <> Line - 1 then
    begin
      Result[n] := Line;
      Inc(n);
    end;
    Prev := Line;
  end;
  SetLength(Result, n);
end;

{ The navigator in the header is shown only while the text has changes to
  jump to. Its counter names the last block the caret has reached, 0
  before the first. }
procedure TForm1.UpdateChangeNav;
var
  Blocks: TIntegerDynArray;
  Cur, Current, i: integer;
begin
  Blocks := ChangeBlocks;
  if Length(Blocks) = 0 then
  begin
    FHeader.SetChanges(0, 0);
    Exit;
  end;
  Cur := Edit.Carets[0].PosY;
  Current := 0;
  for i := 0 to High(Blocks) do
    if Blocks[i] <= Cur then
      Current := i + 1
    else
      Break;
  FHeader.SetChanges(Current, Length(Blocks));
end;

{ The caret event fires from inside the editor's own updates, where
  resizing the header's navigator (it grows with its counter) made the
  editor, while the navigator was its child, recompute its scroll position
  from a half-updated state and scroll sideways. So the update waits for
  the message loop. }
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
  from the caret. Past the last block (or before the first) it goes on to
  the next (or previous) changed file in the tree, and wraps around in
  the file only when there is no other. The block lands a few lines below
  the top edge so its context stays in view. }
procedure TForm1.GoToChange(ANext: boolean);
var
  Blocks: TIntegerDynArray;
  Cur, Target, i: integer;
begin
  Blocks := ChangeBlocks;
  if Length(Blocks) = 0 then
  begin
    if FView = gvChanges then
      StepFile(ANext);
    Exit;
  end;
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
    begin
      if (FView = gvChanges) and StepFile(True) then
      begin
        Blocks := ChangeBlocks;
        if Length(Blocks) = 0 then
          Exit;
      end;
      Target := Blocks[0];
    end;
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
    begin
      if (FView = gvChanges) and StepFile(False) then
      begin
        Blocks := ChangeBlocks;
        if Length(Blocks) = 0 then
          Exit;
      end;
      Target := Blocks[High(Blocks)];
    end;
  end;
  Edit.DoCaretSingle(0, Target);
  Edit.LineTop := Max(0, Target - 3);
  Edit.Update;
  SyncOldSide;
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
  FSummary.Notice := '';
  FCurrentPath := '';
  if not FRepo.Open(ADir) then
  begin
    ShowError(FRepo.Error);
    Exit;
  end;
  UpdateCaption;
  FSummary.Selected := '';
  if not LoadRepository then
    ShowError(FLoadError)
  else
  begin
    FSettings.AddRecent(FRepo.Root);
    RebuildRecentMenu;
    ShowSummary;
  end;
  StartWatcher;
end;

{ A failure to open or read a repository is shown where the hint was: in
  the empty view, not in a dialog, so the next attempt is one drop away. }
procedure TForm1.ShowError(const AMessage: string);
begin
  FileTree.Items.Clear;
  FStats := nil;
  FFileCount := 0;
  FSummary.SetMessage(AMessage, Format(rsDropShortcut,
    [{$IFDEF DARWIN}'⇧⌘O'{$ELSE}'Ctrl+Shift+O'{$ENDIF}]), FAppIcon);
  ShowSummary;
  StatusBar.SimpleText := AMessage;
  UpdateCaption;
end;

{ Reads the branch and the changed files of the open repository into the
  tree and the summary. Returns false, with the message in FLoadError,
  when git failed; the views are empty then. }
function TForm1.LoadRepository: boolean;
var
  Stats: TGittanFileStats;
  Icons: array of integer;
  i: integer;
begin
  Result := FRepo.ChangeStats(Stats);
  if not Result then
    FLoadError := FRepo.Error;
  FStats := Stats;
  FBranch := FRepo.Branch;
  FFileCount := Length(Stats);
  FillFileTree(Stats);
  SetLength(Icons, Length(Stats));
  for i := 0 to High(Stats) do
    Icons[i] := StatIcon(Stats[i]);
  FSummary.SetRepository(ExtractFileName(FRepo.Root), FBranch, FRepo.Base, Stats, Icons);
  RebuildCompareMenu;
end;

{ The badge of a file: with the staged mark when the index holds any of
  its change. }
function TForm1.StatIcon(const AStat: TGittanFileStat): integer;
begin
  if AStat.Staged then
    Result := StagedIcon(AStat.Kind)
  else
    Result := ChangeIcon(AStat.Kind);
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
  FWatcher := TGittanWatcher.Create(FRepo.Root, FRepo.Base, WatchInterval);
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
  closed in the tree, the selected file with its scroll position, or the
  repository diff. A selected file that is no longer changed gives way to
  the summary, which says so. Filling the tree drops the selection, so
  the view is noted first and restored by selecting the file again, which
  runs the usual selection handler. }
procedure TForm1.RefreshRepository;
var
  Collapsed: TStringList;
  Node: TTreeNode;
  Path: string;
  View: TGittanView;
  TopLine, CaretY: integer;

  procedure RestoreScroll;
  begin
    if Edit.Strings.Count = 0 then
      Exit;
    Edit.DoCaretSingle(0, VisibleRow(CaretY));
    Edit.LineTop := Min(TopLine, Edit.Strings.Count - 1);
    Edit.Update;
    SyncOldSide;
  end;

begin
  if FRepo.Root = '' then
    Exit;
  View := FView;
  Path := SelectedPath;
  TopLine := Edit.LineTop;
  CaretY := Edit.Carets[0].PosY;
  Collapsed := TStringList.Create;
  try
    Collapsed.CaseSensitive := True;
    Node := FileTree.Items.GetFirstNode;
    while Node <> nil do
    begin
      if (Node.Data = nil) and not Node.Expanded then
        Collapsed.Add(Node.GetTextPath);
      Node := Node.GetNext;
    end;
    if not LoadRepository then
      StatusBar.SimpleText := FLoadError;
    Node := FileTree.Items.GetFirstNode;
    while Node <> nil do
    begin
      if (Node.Data = nil) and (Collapsed.IndexOf(Node.GetTextPath) >= 0) then
        Node.Collapse(False);
      Node := Node.GetNext;
    end;
  finally
    Collapsed.Free;
  end;
  case View of
    gvChanges:
      begin
        SummarySelectFile(nil, Path);
        if FileTree.Selected = nil then
        begin
          FSummary.Notice := Format(rsNoLongerChanged, [Path]);
          ShowSummary;
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
  FEditOld.Visible := False;
  FSideSplitter.Visible := False;
  FHeader.Visible := False;
  FFindBar.Visible := False;
  FSummaryBox.Visible := True;
  FView := gvSummary;
  { A file picked again after the summary must fire the selection event. }
  FileTree.Selected := nil;
  if FRepo.Root <> '' then
    UpdateStatus;
end;

{ FView is set before the call: the layout depends on it. }
procedure TForm1.ShowEditor;
begin
  FSummaryBox.Visible := False;
  FHeader.Visible := True;
  ApplyLayout;
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
  begin
    FSummary.Notice := '';
    ShowSummary;
  end;
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
  i, Added, Deleted: integer;
  Title, DiffText: string;
  Lines: TStringList;
  Spans: TGittanLineSpans;
begin
  Title := rsRepoDiffTitle;
  if FRepo.Base <> '' then
    Title := Title + ' ' + Format(rsVsBase, [FRepo.Base]);
  FHeader.SetTitle(Title);
  Added := 0;
  Deleted := 0;
  for i := 0 to High(FStats) do
  begin
    Inc(Added, FStats[i].Added);
    Inc(Deleted, FStats[i].Deleted);
  end;
  FHeader.SetCounts(Added, Deleted, False);
  FSummary.Notice := '';
  FCurrentPath := '';
  FManualLexer := False;
  FView := gvRepoDiff;
  DiffText := FRepo.Diff;
  ShowText(Edit, DiffText, FLexers.ByName(rsDiffLexer));
  { The "---"/"+++" file headers are not changes. }
  for i := 0 to Edit.Strings.Count - 1 do
    if (Edit.Strings.LinesLen[i] > 0) and
      (Copy(Edit.Strings.Lines[i], 1, 3) <> '---') and
      (Copy(Edit.Strings.Lines[i], 1, 3) <> '+++') then
      MarkLine(Edit, i, char(Edit.Strings.Lines[i][1]));
  { The words that differ, as in the change view. The diff's own lines
    (hunk and file headers) are given a blank marker so they do not
    count as changes; the text keeps its marker column, so the spans
    are shifted by one. }
  Lines := TStringList.Create;
  try
    Lines.Text := DiffText;
    for i := 0 to Lines.Count - 1 do
      if (Lines[i] = '') or not (Lines[i][1] in ['+', '-']) or
        (Copy(Lines[i], 1, 3) = '---') or (Copy(Lines[i], 1, 3) = '+++') then
        Lines[i] := ' ' + Lines[i];
    WordDiff(Lines, FIgnoreWhitespace, Spans);
    for i := 0 to Min(High(Spans), Edit.Strings.Count - 1) do
      if Spans[i] <> nil then
        MarkWords(Edit, i, Spans[i], Lines[i][1], 1);
  finally
    Lines.Free;
  end;
  UpdateChangeNav;
  ShowEditor;
  FileTree.Selected := nil;
  FSummary.Selected := '';
  UpdateStatus;
end;

{ Shows one changed file with its deleted lines kept in place: the diff
  with the whole file as context, built into rows by BuildChangeView. The
  lexer comes from the file name. The gaps the user opened are kept when
  the same file is shown again, as on a refresh. }
procedure TForm1.ShowChanges(const APath: string);
var
  Lines: TStringList;
  i: integer;
begin
  Lines := TStringList.Create;
  try
    if not FRepo.FileChanges(APath, Lines) then
    begin
      StatusBar.SimpleText := FRepo.Error;
      Exit;
    end;
    FChangeLines.Assign(Lines);
  finally
    Lines.Free;
  end;
  if APath <> FCurrentPath then
    FExpanded := nil;
  FCurrentPath := APath;
  SetOverscroll(0);
  FSummary.Notice := '';
  FHeader.SetFile(APath, -1);
  for i := 0 to High(FStats) do
    if FStats[i].Path = APath then
    begin
      FHeader.SetFile(APath, StatIcon(FStats[i]));
      FHeader.SetCounts(FStats[i].Added, FStats[i].Deleted, FStats[i].Binary);
      FHeader.SetStage(FStats[i].Staged, FStats[i].Unstaged);
      Break;
    end;
  FManualLexer := False;
  FView := gvChanges;
  ApplyLayout;
  BuildChangeView;
  { The summary marks the row of the file the editor showed last. }
  FSummary.Selected := APath;
  UpdateChangeNav;
  ShowEditor;
  Edit.FileName := IncludeTrailingPathDelimiter(FRepo.Root) +
    SetDirSeparators(APath);
  UpdateStatus;
  Edit.Update;
end;

{ ---------------------------------------------------------------------------
  File tree
  ---------------------------------------------------------------------------
  One node per path component of each changed file. A file node has Data
  set and a badge for its change kind; a folder node has Data = nil and
  the folder icon with a dot for the worst change inside; a submodule,
  which git status reports as one entry, has Data = nil and the plain
  folder icon. Neither is ever opened. git lists paths sorted, so the folder node of the previous
  path is reused when the folder repeats. }
procedure TForm1.FillFileTree(const AStats: TGittanFileStats);
var
  Path, Dir, Part: string;
  DirNode, Node, LastDir: TTreeNode;
  LastDirPath: string;
  i, Start, Sep: integer;
  Kind, FolderKind: TGittanChangeKind;
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
        Node.ImageIndex := StatIcon(AStats[i]);
      end;
      Node.SelectedIndex := Node.ImageIndex;
      { Every folder above carries a dot in the color of the most severe
        change inside it. }
      Kind := AStats[i].Kind;
      Node := DirNode;
      while Node <> nil do
      begin
        if FolderIconKind(Node.ImageIndex, FolderKind) then
          Kind := WorseKind(Kind, FolderKind);
        Node.ImageIndex := FolderIcon(Kind);
        Node.SelectedIndex := Node.ImageIndex;
        Node := Node.Parent;
      end;
    end;
    FileTree.CustomSort(@CompareTreeNodes);
    { Every changed file is in view from the start. }
    FileTree.FullExpand;
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
end;

{$I umain.diffview.inc}
{$I umain.actions.inc}

end.
