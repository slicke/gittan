unit umain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ComCtrls,
  ExtCtrls, StdCtrls, LCLType, LazLoggerBase, Math, Types,
  ATSynEdit, ATSynEdit_Adapter_EControl, ATSynEdit_Bookmarks, ATSynEdit_Commands,
  ATSynEdit_Carets, ATSynEdit_Gutter_Decor, ATSynEdit_Globals, ATStringProc,
  ATStringProc_WordJump,
  ATSynEdit_Markers, ATSynEdit_LineParts, ATSynEdit_Ranges, ATSynEdit_WrapInfo,
  ec_SyntAnal,
  gittan.lexers, gittan.git, gittan.github, gittan.conflicts, gittan.icons, gittan.theme, gittan.changenav,
  gittan.summary, gittan.welcome, gittan.fileheader, gittan.watch, gittan.settings,
  gittan.findbar, gittan.worddiff, gittan.symbols, gittan.symbolbar,
  gittan.symbolindex, gittan.snapshots, gittan.blame, gittan.history,
  gittan.syntaxthemes, gittan.cli, gittan.symbolchanges, gittan.callers,
  gittan.popuplist, gittan.statusbar, gittan.repofiles, gittan.sectionheader,
  gittan.discard, gittan.submodules, md5;

type
  {** What the space right of the tree shows: the summary, one changed
    file, the raw repository diff, a plain file from File > Open, the
    history of a piece of code (Go > Code History), or a submodule. }
  TGittanView = (gvSummary, gvChanges, gvRepoDiff, gvFile, gvHistory, gvSubmodule);

  {** One row of the change view. Line is the index of its diff line in
    the file's diff, rowGap for a row that stands for the unchanged lines
    GapFrom..GapTo hidden by View > Hide Unchanged Lines, rowFiller for
    the blank row the side-by-side view puts opposite a line the other
    side has, or, in the history view, rowCommit for the header of the
    commit GapFrom and rowMore for the row that fetches older commits. A
    hidden row is in the text, so the lexer sees the whole file, but not
    on screen. }
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
    procedure FileTreeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
    procedure FileTreeMouseLeave(Sender: TObject);
    procedure TreeHintTimerTimer(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
  private
    FAdapter, FAdapterOld: TATAdapterEControl;
    FLexers: TGittanLexers;
    FRepo: TGittanRepo;
    FSettings: TGittanSettings;
    { gh, GitHub's command line tool, as found at startup: its full path
      (run it by that, PATH may not reach it) and whether there is one.
      The features that need GitHub are offered only when it is there. }
    FGitHubCli: string;
    FHasGitHubCli: boolean;
    FSyntaxMenu, FAutoLexerItem, FPlainTextItem: TMenuItem;
    FRecentMenu, FCompareMenu, FTerminalItem, FUninstallCliItem: TMenuItem;
    FSnapshots: TGittanSnapshots;
    FWrapItem, FOnlyChangesItem, FSideItem, FIgnoreSpaceItem: TMenuItem;
    FContextItems: array of TMenuItem;
    {** The View > Syntax Theme items, in SyntaxThemes order. }
    FThemeItems: array of TMenuItem;
    {** The chosen syntax theme, an index into SyntaxThemes. }
    FSyntaxTheme: integer;
    FFilePopup, FStatusPopup, FEditPopup: TPopupMenu;
    FStatus: TGittanStatusBar;
    FRevealItem, FOpenItem: TMenuItem;
    FContextPath: string;
    { The GitHub items of the editor menu, made only when gh is installed
      (the file menu's is enabled with the rest of its items); the editor the editor menu popped up over and the
      row under the mouse then (-1 below the text), and the commit of
      that row, for Open Commit on GitHub. }
    FGitHubEditItem, FGitHubCommitItem, FGitHubIssueItem: TMenuItem;
    FShowCommitItem, FCopyHashItem: TMenuItem;
    FPopupEd: TATSynEdit;
    FPopupRow: integer;
    FPopupHash: string;
    { The row's commit as the history view keys it, -1 elsewhere, and
      the first "#123" of the commit's summary, 0 when it has none. }
    FPopupKey, FPopupIssue: integer;
    { GitHub's view of the repository, read by a TGittanPullRequestJob
      when the repository or its branch changes (FPullKey names the pair
      the data is for) and on View > Refresh: the pull request of the
      branch, if any, and the open pull requests, or gh's message. A
      finished job goes to FBlameZombies, which frees it later. The
      Compare With > Pull Requests submenu lists FPulls; a chosen one is
      fetched and compared as the range FPullRange, numbered
      FPullNumber, which BaseLabel names "PR #12". }
    FPullJob: TGittanPullRequestJob;
    { Asks gh again after PullPollPending ms while checks run, after
      PullPollIdle ms otherwise, so the status bar follows the checks and
      the review; off while no repository is open or gh failed. }
    FPullTimer: TTimer;
    FPull: TGittanPullRequest;
    FHasPull: boolean;
    FPulls: TGittanPullRequests;
    FPullError, FPullKey: string;
    FPullMenu, FOpenPullItem, FCopyPullItem: TMenuItem;
    FPullRange: string;
    FPullNumber: integer;
    { The tree sits in a panel under a filter field (Go > Filter Files):
      FillFileTree keeps only the files whose path holds FTreeFilterText,
      the field's text in lower case. }
    FTreePanel: TPanel;
    FTreeFilter: TEdit;
    FTreeFilterText: string;
    { The Repository section at the bottom of the tree panel
      (umain.repofiles.inc): the repository's own files from
      gittan.repofiles in a second tree under a header that folds it,
      and the "Add to .gitignore" and "Add to .git/info/exclude" submenus
      of the file menu, filled with the patterns for the file on popup. }
    FRepoPanel: TPanel;
    FRepoHeader: TGittanSectionHeader;
    FRepoTree: TTreeView;
    FIgnoreMenu, FExcludeMenu: TMenuItem;
    { The Submodules section under it (umain.submodules.inc): the
      submodules from gittan.submodules, what their jobs found out
      (FSubInfos, one per submodule, smUnknown while its job runs), the
      jobs still running, what they were started for (SubmoduleKey) and
      the path of the submodule the view shows. }
    FSubPanel: TPanel;
    FSubHeader: TGittanSectionHeader;
    FSubTree: TTreeView;
    FSubmodules: TGittanSubmodules;
    FSubInfos: array of TGittanSubmoduleInfo;
    FSubJobs: TList;
    FSubKey, FSubShown: string;
    { Asks the remotes again SubmodulePoll ms after the last job of a
      round finished; off while no repository is open. }
    FSubTimer: TTimer;
    { Editing the repository's own files (umain.repofiles.inc): the full
      name of the file the editor holds open to edits, '' while it shows
      something else; the file's time stamp when it was loaded or saved,
      so a change on disk behind an edit is noticed; the exclude file of
      the open repository, found once when it is opened; and File > Save. }
    FEditPath, FExcludePath: string;
    FEditStamp: LongInt;
    FSaveItem: TMenuItem;
    { Discarding a block of changes (umain.discard.inc): the row of the
      first line of every block (FBlockStarts), found by BuildChangeView;
      the block whose button the mouse is on (-1 for none); the blocks
      discarded, latest last, which File > Undo Discard puts back; and
      the two menu items. }
    FBlockRows: TIntegerDynArray;
    FHotDiscard: integer;
    FDiscards: array of TGittanDiscard;
    FDiscardItem, FUndoDiscardItem: TMenuItem;
    { The default branch of the remote (origin/main) and the merge base
      of the branch with it, Compare With's "origin/main (Merge Base)";
      and the branch's lead on and lag behind its upstream, for the
      status bar. All read by LoadRepository. }
    FDefaultBranch, FMergeBase: string;
    FHasUpstream: boolean;
    FAhead, FBehind: integer;
    { What git is in the middle of ("merging", "rebasing", ...) and how
      many files have conflicts, read by LoadRepository; and the role of
      each line of FChangeLines in a conflict (see gittan.conflicts),
      set by ShowChanges for a conflicted file, nil otherwise. }
    FOperation: string;
    FConflictFiles: integer;
    FConflictRoles: TIntegerDynArray;
    FContextFromSummary: boolean;
    FHeader: TGittanFileHeader;
    FNav: TGittanChangeNav;
    FNavUpdateQueued: boolean;
    FFindBar: TGittanFindBar;
    { The symbol bar and the symbols it lists; the symbol index of the
      repository with the state of its building (see umain.index.inc:
      the files git lists, the next of them, how many there are, the one
      being parsed, the hidden editor and adapter that parse, the timer
      that gives up on a parse, and whether the index has changed since
      it was written); and the word under the mouse, the editor and row
      it is in, whether it is underlined as a link, and the timer that
      shows its definition. }
    FSymbolBar: TGittanSymbolBar;
    FSymbols: TGittanSymbols;
    { The file of each of FSymbols, relative to the root, when the bar
      lists the repository; nil when it lists the shown file. }
    FSymbolFiles: TStringList;
    { Whether each of FSymbols is in the old side's text (Go > Changed
      Symbols in the side-by-side view), nil when none is. }
    FSymbolOnOld: array of boolean;
    { Whether the rows of FSymbols in other files are places to go to as
      they are (the uses Go > Callers of Changed Symbols lists), not
      definitions to look up in the file's text. }
    FSymbolPlaces: boolean;
    FIndex: TGittanSymbolIndex;
    FIndexQueue: TStringList;
    FIndexPos, FIndexTotal: integer;
    FIndexCurrent: string;
    FIndexEdit: TATSynEdit;
    FIndexAdapter: TATAdapterEControl;
    FIndexTimer: TTimer;
    FIndexing, FIndexSaveNeeded: boolean;
    FHoverTimer: TTimer;
    { The hint of the file under the mouse in the tree and the timer
      that shows it, see FileTreeMouseMove. }
    FTreeHint: string;
    FTreeHintNode: TTreeNode;
    FTreeHintTimer: TTimer;
    FHoverEd: TATSynEdit;
    FHoverWord: string;
    { The hint of the blame cell under the mouse, see umain.blame.inc. }
    FHoverBlame: string;
    FHoverRow: integer;
    FHoverLinked: boolean;
    FLinkColor: TColor;
    FSummaryBox: TScrollBox;
    FSummary: TGittanSummary;
    FWelcome: TGittanWelcome;
    { The list that drops down from the branch in the summary, with the
      branch to switch to for each of its items ('' for a header). }
    FBranchPopup: TGittanPopupList;
    FBranchNames: TStringList;
    { The list that drops up from the status bar's ahead/behind counts,
      with the commit each of its items shows ('' for a header). }
    FSyncPopup: TGittanPopupList;
    FSyncHashes: TStringList;
    FEditOld: TATSynEdit;
    { The hidden editor that parses another changed file for Go to
      Definition, with its adapter; made on the first lookup. }
    FScratch: TATSynEdit;
    FScratchAdapter: TATAdapterEControl;
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
    { The rows of the old side, and the number of each diff line in the
      old and the new file (see NumberLines). }
    FRowsOld: TGittanRows;
    FOldNum, FNewNum: TIntegerDynArray;
    FOnlyChanges, FSideBySide, FWordWrap, FIgnoreWhitespace: boolean;
    FContextLines: integer;
    { The spans of the changed lines that differ word by word, one entry
      per line of FChangeLines; see gittan.worddiff. }
    FWordSpans: TGittanLineSpans;
    { The symbols of the change view (see UpdateSymbolHeadings): the first
      diff line of every block of changed lines, the name of the code tree
      range each block is in (a gap row names the block after it), the
      code tree of each side's text (valid, FRangesValid, from the end of
      a parse to the next build), and how often the headings rebuilt the
      view of this file. }
    FBlockStarts: TIntegerDynArray;
    FHeadings: array of string;
    FCodeRanges, FOldRanges: TGittanCodeRanges;
    FRangesValid, FBuildingView: boolean;
    FHeadingRebuilds: integer;
    { Scrolling on past the bottom of a file, or the top: the wheel
      delta pulled so far (positive downwards, towards the next file,
      negative upwards, towards the previous), the time of the last wheel
      event, whether a pull counts (not while the momentum of the gesture
      that just jumped runs on), the timer that forgets a pull left half
      way, and the colors of the pill that shows the pull. }
    FOverscroll: integer;
    FOverscrollTick: QWord;
    FOverscrollArmed: boolean;
    FOverscrollTimer: TTimer;
    FPullFill, FPullBorder, FPullText, FPullBar: TColor;
    { View > Blame (see umain.blame.inc): whether it is on, its menu item,
      the blames of the two sides of the shown file, the job that blames
      a file, the cache of the results (TGittanBlame per side and path,
      nil for a side git could not blame), the jobs given up on, the
      width of the author column in characters, and the time the ages
      are counted from. }
    FBlameOn: boolean;
    FBlameItem: TMenuItem;
    FBlameOld, FBlameNew: TGittanBlame;
    FBlameJob: TGittanBlameJob;
    FBlameCache: TStringList;
    FBlameZombies: TList;
    FBlameCols: integer;
    FBlameNow: int64;
    { The Base a click on the band set, so the summary can name the
      commit instead of the range. }
    FBlameRange: string;
    { Go > Code History (see umain.history.inc): the commits shown, the
      job that fetches them, the file, the commit the lines are counted
      in (empty for HEAD), the lines (From 0 for the whole file), what
      the header calls the piece, how many commits are asked for, whether
      git had more, and the scroll position to restore when the job is
      done. }
    FHistory: TGittanHistory;
    FHistoryJob: TGittanHistoryJob;
    FHistoryPath, FHistoryRef, FHistoryName: string;
    FHistoryFrom, FHistoryTo, FHistoryMax: integer;
    FHistoryMore: boolean;
    FHistoryTopLine, FHistoryCaretY: integer;
    { The layered rows of the history, see TGittanHistory.Layers. }
    FHistoryRows: TGittanHistoryRows;
    procedure ApplyTheme;
    procedure ApplyEditorColors(AEd: TATSynEdit);
    procedure SetupEditor(AEd: TATSynEdit);
    function AdapterOf(AEd: TATSynEdit): TATAdapterEControl;
    procedure MenuRefreshClick(Sender: TObject);
    procedure WatcherChange(Sender: TObject);
    procedure StartWatcher;
    procedure StopWatcher;
    function LoadRepository: boolean;
    procedure ApplySnapshot(const ASnap: TGittanRepoSnapshot);
    procedure RefreshRepository(ASnap: PGittanRepoSnapshot = nil);
    procedure ShowError(const AMessage: string);
    procedure ShowWelcome(const AError: string);
    procedure WelcomeOpen(Sender: TObject);
    procedure WelcomeOpenRecent(Sender: TObject; const ARoot: string);
    function SelectedPath: string;
    function StatIcon(const AStat: TGittanFileStat): integer;
    function StatHint(const AStat: TGittanFileStat): string;
    procedure UpdateStatus;
    {** The checks of a pull request for the status bar: red with the
      failing ones counted, amber with the pending ones, green when all
      passed, or stNormal without checks. }
    function PullChecks(const APull: TGittanPullRequest; out ACount: integer): TGittanStatusTone;
    {** The status bar's hint for a pull request: its number and title,
      the checks by outcome, and what a click does. }
    function PullHint(const APull: TGittanPullRequest): string;
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
    function HistoryColor(AIndex: integer; AStrong: boolean): TColor;
    procedure MarkHeader(AEd: TATSynEdit; ARow: integer);
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
    function GapRowText(ACount: integer; const AHeading: string;
      out ADown, AUp, AAll, AHeadingCol: integer): string;
    function GapHeading(AGapTo: integer): string;
    function RowMarkers(const ARows: TGittanRows; AOldSide: boolean): string;
    function RowTexts(AEd: TATSynEdit): TStringList;
    procedure UpdateSymbolHeadings;
    procedure RebuildForHeadingsAsync(Data: PtrInt);
    procedure UpdateSymbolCrumb;
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
    { umain.blame.inc }
    procedure MenuBlameClick(Sender: TObject);
    procedure StartBlame;
    procedure AbandonBlameJob;
    procedure FreeFinishedBlameJobs(AWait: boolean);
    procedure FreeBlameJobsAsync(Data: PtrInt);
    procedure CacheBlame(const ARef, APath: string; ABlame: TGittanBlame);
    procedure BlameJobDone(Sender: TObject);
    procedure ClearBlameCache;
    procedure StopBlame;
    procedure ApplyBlame;
    procedure SetBlameBand(AEd: TATSynEdit);
    function BlameOfRow(AEd: TATSynEdit; ARow: integer; out ABlame: TGittanBlame): integer;
    function CommitOfRow(AEd: TATSynEdit; ARow: integer; out AInfo: TGittanBlameCommit;
      out AKey: integer; out ASource: TObject): boolean;
    function BlameHintText(const ACommit: TGittanBlameCommit): string;
    function BlameHintAt(AEd: TATSynEdit; X, Y: integer): string;
    procedure DrawBlame(AEd: TATSynEdit; C: TCanvas);
    procedure EditClickGutter(Sender: TObject; ABand, ALine: integer; var AHandled: boolean);
    procedure ShowBlameCommit(const AHash: string);
    procedure HandCursorAsync(Data: PtrInt);
    { umain.discard.inc }
    function CanDiscard: boolean;
    procedure FindBlockRows;
    function BlockAtRow(ARow: integer): integer;
    function DiscardAt(AEd: TATSynEdit; X, Y: integer): integer;
    procedure SetDiscardBand(AEd: TATSynEdit);
    procedure DrawDiscard(AEd: TATSynEdit; C: TCanvas);
    procedure SetHotDiscard(AEd: TATSynEdit; ABlock: integer);
    procedure DiscardBlockAt(ABlock: integer);
    procedure UpdateDiscardItems;
    procedure FileMenuClick(Sender: TObject);
    procedure MenuDiscardClick(Sender: TObject);
    procedure MenuUndoDiscardClick(Sender: TObject);
    function DiscardBackText(ABlock: integer): string;
    function DiscardBaseName: string;
    { umain.history.inc }
    procedure MenuHistoryClick(Sender: TObject);
    function ChunkRows(out AFrom, ATo: integer; out AName: string): boolean;
    function EnclosingRange(AAdapter: TATAdapterEControl; ARow: integer;
      out AFrom, ATo: integer; out AName: string): boolean;
    function ChunkLines(AFromRow, AToRow: integer; out AFrom, ATo: integer): boolean;
    function HistoryRef: string;
    procedure StartHistory;
    procedure AbandonHistoryJob;
    procedure HistoryJobDone(Sender: TObject);
    procedure AddUncommittedHistory;
    procedure ShowHistory;
    procedure BuildHistoryView;
    procedure MarkHistoryWords(AEd: TATSynEdit; ARow: integer;
      const ASpans: TGittanSpans; ACommit: integer);
    procedure MarkSwatch(AEd: TATSynEdit; ARow, ACommit: integer);
    procedure HistoryCounts(AIndex: integer; out AAdded, ADeleted: integer);
    function HistoryHeaderText(AIndex: integer): string;
    procedure HistoryClick(ARow: integer);
    procedure ShowHistoryCommit(AIndex: integer);
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
    procedure MenuSyntaxThemeClick(Sender: TObject);
    procedure MenuSideBySideClick(Sender: TObject);
    procedure MenuIgnoreSpaceClick(Sender: TObject);
    procedure MenuNextFileClick(Sender: TObject);
    procedure MenuPrevFileClick(Sender: TObject);
    function StepFile(ANext: boolean): boolean;
    function WordAt(AEd: TATSynEdit; APos: TPoint; out AStart, AEnd: integer): string;
    function CodeTree(AAdapter: TATAdapterEControl; AEd: TATSynEdit): TGittanSymbols;
    function CodeRanges(AAdapter: TATAdapterEControl; AEd: TATSynEdit): TGittanCodeRanges;
    function ShownSymbolChanges(out ANew, AOld: TGittanSideText): TGittanSymbolChanges;
    procedure MenuChangedSymbolsClick(Sender: TObject);
    procedure MenuCallersClick(Sender: TObject);
    function FileSymbols(const ARelPath: string): TGittanSymbols;
    function IndexFileName: string;
    procedure SaveIndex;
    procedure StartIndexing;
    procedure StopIndexing;
    procedure IndexNext;
    procedure IndexNextAsync(Data: PtrInt);
    procedure IndexParseDone(Sender: TObject; ATime: integer);
    procedure IndexTimerTimer(Sender: TObject);
    function ShownRelPath: string;
    function FindInRepo(const AWord: string; out APath: string;
      out ASymbol: TGittanSymbol): boolean;
    procedure ShowRepoFile(const ARelPath: string);
    function FindDefinition(AAdapter: TATAdapterEControl; AEd: TATSynEdit;
      const AWord: string; ASkipRow: integer): TPoint;
    function ParseScratch(const AFileName: string; ALexer: TecSyntAnalyzer): TATAdapterEControl;
    procedure JumpToDefinition(AEd: TATSynEdit; APos: TPoint; const AWord: string);
    procedure GoToDefinition(AEd: TATSynEdit);
    procedure MenuGoToDefinitionClick(Sender: TObject);
    procedure MenuGoToSymbolClick(Sender: TObject);
    procedure MenuGoToRepoSymbolClick(Sender: TObject);
    procedure SymbolBarPick(Sender: TObject; AIndex: integer);
    procedure SymbolBarClose(Sender: TObject);
    procedure EditMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
    procedure EditMouseLeave(Sender: TObject);
    procedure HoverTimerTimer(Sender: TObject);
    procedure ClearHover;
    function RowLabel(AEd: TATSynEdit; ARow: integer): string;
    procedure AdapterParseBegin(Sender: TObject);
    procedure AdapterParseDone(Sender: TObject; ATime: integer);
    function NeighbourFile(ANext: boolean): TTreeNode;
    procedure EditMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
    procedure SetOverscroll(AValue: integer);
    procedure ShowFileEnd;
    procedure SetWheelScroll(AOn: boolean);
    procedure OverscrollTimerTimer(Sender: TObject);
    procedure EditDrawEditor(Sender: TObject; C: TCanvas; const ARect: TRect);
    procedure BuildPopups;
    procedure FilePopupPopup(Sender: TObject);
    procedure SummaryContextFile(Sender: TObject; const APath: string;
      const AScreenPos: TPoint);
    procedure SummaryBranchClick(Sender: TObject; const AScreenRect: TRect);
    procedure BranchPopupPick(Sender: TObject; AIndex: integer);
    procedure SyncClick(const AScreenRect: TRect);
    procedure SyncPopupPick(Sender: TObject; AIndex: integer);
    procedure SwitchBranch(const ABranch: string);
    function ContextFullPath: string;
    procedure MenuCopyPathClick(Sender: TObject);
    procedure MenuCopyRelativePathClick(Sender: TObject);
    procedure MenuRevealClick(Sender: TObject);
    procedure MenuOpenInEditorClick(Sender: TObject);
    procedure EditPopupPopup(Sender: TObject);
    procedure MenuEditCopyClick(Sender: TObject);
    procedure MenuEditSelectAllClick(Sender: TObject);
    procedure MenuOpenOnGitHubClick(Sender: TObject);
    procedure MenuCopyGitHubUrlClick(Sender: TObject);
    procedure MenuOpenLineOnGitHubClick(Sender: TObject);
    procedure MenuCopyLineGitHubUrlClick(Sender: TObject);
    procedure MenuOpenCommitOnGitHubClick(Sender: TObject);
    procedure MenuOpenIssueOnGitHubClick(Sender: TObject);
    procedure MenuShowCommitClick(Sender: TObject);
    procedure MenuCopyHashClick(Sender: TObject);
    function GitHubUrl(const AArgs: array of string; out AUrl: string): boolean;
    procedure OpenOnGitHub(const AArgs: array of string);
    {** Runs the pull request job. AForce asks again for the same
      repository and branch; AKeep keeps the data shown meanwhile, for a
      poll, where clearing it would blink the chip and the menu. }
    procedure StartPullJob(AForce: boolean; AKeep: boolean = False);
    procedure PullTimerTimer(Sender: TObject);
    procedure SetupTreeFilter;
    procedure SetupRepoFiles;
    procedure ColorRepoHeader;
    procedure FillRepoFiles;
    procedure LayoutRepoFiles;
    procedure RepoHeaderToggle(Sender: TObject);
    procedure TreePanelResize(Sender: TObject);
    procedure RepoTreeSelectionChanged(Sender: TObject);
    procedure SetupSubmodules;
    function SubmoduleKey: string;
    procedure FillSubmodules;
    function SubmoduleRowText(AIndex: integer): string;
    procedure FillSubmoduleTree;
    {** Starts a job per submodule. AKeep keeps what the previous jobs
      found shown meanwhile, for a poll. }
    procedure StartSubmoduleJobs(AKeep: boolean = False);
    procedure SubTimerTimer(Sender: TObject);
    procedure AbandonSubmoduleJobs;
    procedure SubmoduleJobDone(Sender: TObject);
    procedure SubTreeSelectionChanged(Sender: TObject);
    procedure ShowSubmodule(AIndex: integer);
    procedure OpenShownSubmodule;
    procedure RestoreSubmodule;
    procedure FillIgnoreMenus(const APath: string);
    procedure MenuIgnoreClick(Sender: TObject);
    function RepoFileName(const AFileName: string): boolean;
    procedure BeginEdit(const AFileName: string);
    procedure FlushEdit;
    procedure LeaveEdit;
    procedure UpdateEditState;
    function SaveEdit(ARefresh: boolean): boolean;
    procedure RevertEdit;
    procedure SelectRepoNode(const APath: string);
    procedure HeaderAction(Sender: TObject; AIndex: integer);
    procedure EditChangeModified(Sender: TObject);
    procedure MenuSaveClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: boolean);
    procedure TreeFilterChange(Sender: TObject);
    procedure TreeFilterKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure MenuFilterFilesClick(Sender: TObject);
    procedure AbandonPullJob;
    procedure PullJobDone(Sender: TObject);
    procedure RebuildPullMenu;
    procedure StatusPopupPopup(Sender: TObject);
    procedure MenuComparePullClick(Sender: TObject);
    procedure MenuOpenPullClick(Sender: TObject);
    procedure MenuCopyPullUrlClick(Sender: TObject);
    function FileGitHubArgs(const APath: string; ALine: integer): TStringArray;
    function FileLineOfRow(AEd: TATSynEdit; ARow: integer): integer;
    procedure StatusPartClick(Sender: TObject; APart: TGittanStatusPart;
      const AScreenRect: TRect);
    {** Shows AText in the status bar for a while, in red when AError. }
    procedure StatusNote(const AText: string; AError: boolean = False);
    {** The caret's line and column in the status bar while the editor
      shows a file, nothing elsewhere. }
    procedure UpdateStatusPosition;
    procedure MenuCopyBranchClick(Sender: TObject);
    procedure MenuCopyRepoPathClick(Sender: TObject);
    procedure MenuOpenTerminalClick(Sender: TObject);
    procedure MenuInstallCliClick(Sender: TObject);
    procedure MenuUninstallCliClick(Sender: TObject);
    procedure ToolsMenuClick(Sender: TObject);
    procedure RebuildCompareMenu;
    procedure MenuCompareClick(Sender: TObject);
    procedure MenuCompareOtherClick(Sender: TObject);
    procedure MenuTakeSnapshotClick(Sender: TObject);
    procedure SetBase(const ARef: string; ASnapshot: boolean = False);
    function BaseLabel: string;
    function SnapshotsFileName: string;
    procedure LoadSnapshots;
    procedure SaveSnapshots;

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
  Clipbrd, LCLIntf, Process, FileUtil, LazFileUtils, DateUtils;

resourcestring
  rsAppName = 'Git Tree Analyzer & Navigator';
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
  rsTakeSnapshot = 'Take S&napshot';
  rsSnapshot = 'Snapshot %s';
  rsVsSnapshot = 'snapshot %s';
  rsSnapshotFailed = 'Could not take a snapshot: %s';
  rsRefPrompt = 'Branch, tag or commit to compare the working tree against, ' +
    'or two commits: main...feature shows what feature changed since it left main, ' +
    'v1..v2 compares the two.';
  rsOnlyChanges = '&Hide Unchanged Lines';
  rsContextLines = 'Conte&xt Lines';
  rsNLines = '%d lines';
  rsSideBySide = 'Side &by Side';
  rsWordWrap = '&Word Wrap';
  rsIgnoreSpace = 'I&gnore Whitespace';
  rsBlame = '&Blame';
  rsNotCommitted = 'Not committed';
  rsNotCommittedYet = 'Not committed yet';
  rsCommit = 'commit %s';
  rsHistory = 'Code &History';
  rsHistoryTitle = 'History of %s';
  rsHistoryIn = '%s in %s';
  rsHistoryLines = 'lines %d-%d';
  rsHistoryMore = '⋯  ↓ %d older changes  ⋯';
  rsHistoryCounts = '+%d −%d';
  rsHistoryLoading = 'Loading history...';
  rsHistoryNeedsFile = 'Show a file first: the history is of the selected lines, or of the function at the caret.';
  rsNoHistoryYet = 'These lines are not committed yet, so they have no history.';
  rsNoHistory = 'No history of these lines.';
  rsZoomIn = 'Zoom &In';
  rsZoomOut = 'Zoom &Out';
  rsZoomReset = 'Actual Si&ze';
  rsFont = 'Fo&nt...';
  rsSyntaxTheme = 'Syntax T&heme';
  rsTagline = 'See what changed in a git repository';
  rsGo = '&Go';
  rsTools = '&Tools';
  rsInstallCli = 'Install &CLI Command';
  rsUninstallCli = '&Uninstall CLI Command';
  rsFind = '&Find...';
  rsFindNext = 'Find &Next';
  rsFindPrev = 'Find &Previous';
  rsGoToDefinition = 'Go to &Definition';
  rsGoToSymbol = 'Go to S&ymbol...';
  rsGoToRepoSymbol = 'Go to Symbol in Re&pository...';
  rsChangedSymbols = 'Changed S&ymbols...';
  rsChangedSymbolHint = 'Changed symbol';
  rsRepoSymbolHint = 'Symbol in repository';
  rsNoChangedSymbols = 'No changed symbols in this file.';
  rsCallers = 'Ca&llers of Changed Symbols...';
  rsCallerHint = 'Changed symbol or a line that uses it';
  rsCallersAbove = 'same name, listed above';
  rsNoCallers = 'No other file uses the changed symbols.';
  rsCallersStatus = 'The changed symbols are used in %s outside this file.';
  rsLookingFor = 'Looking for a definition of "%s"...';
  rsNoDefinition = 'No definition of "%s" in the repository.';
  rsIndexing = 'Indexing %d/%d';
  rsNextChange = 'Next &Change';
  rsPrevChange = 'Previous C&hange';
  rsNextFile = 'Next F&ile';
  rsPrevFile = 'Previous Fi&le';
  rsRepoFiles = 'Repository';
  rsSubmodules = 'Submodules';
  rsSubmodulesNewer = '%d · ↓%d';
  rsSubUrl = 'URL';
  rsSubBranch = 'Branch';
  rsSubDefaultBranch = 'the remote''s default branch';
  rsSubSameBranch = 'the repository''s own branch (%s)';
  rsSubRecorded = 'Recorded';
  rsSubNoRecorded = 'none: the index records no commit for it';
  rsSubConflict = 'in conflict: the index holds more than one commit';
  rsSubCheckedOut = 'Checked out';
  rsSubSameAsRecorded = 'the recorded commit';
  rsSubNotInitialized = 'nothing: not initialized (git submodule update --init)';
  rsSubRemote = 'Remote';
  rsSubChecking = 'checking...';
  rsSubUpToDate = 'the recorded commit, up to date';
  rsSubBehind = '%d new commits';
  rsSubAhead = 'the recorded commit is %d commits past it';
  rsSubDiverged = '%d new commits; the recorded commit has %d it lacks';
  rsSubNotFetched = 'new commits; fetch in the submodule to list them';
  rsSubFailed = 'could not be asked: %s';
  rsSubIncoming = 'New on the remote';
  rsSubMore = '... and %d more';
  rsSubOpen = 'Open';
  rsAddToIgnore = 'Add to .&gitignore';
  rsAddToExclude = 'Add to .git/info/e&xclude';
  rsIgnoreAdded = 'Added %s to %s';
  rsIgnoreFailed = 'Could not write %s';
  rsSave = '&Save';
  rsEditAction = 'Edit';
  rsSaveAction = 'Save';
  rsRevertAction = 'Revert';
  rsDontSave = 'Don''t Save';
  rsCancelButton = 'Cancel';
  rsSaveAsk = 'Save the changes to %s?';
  rsRevertAsk = 'Drop the changes to %s and load it from disk again?';
  rsSaved = 'Saved %s';
  rsSaveFailed = 'Could not save %s: %s';
  rsChangedOnDisk = 'changed on disk';
  rsDiscardChange = '&Discard Change';
  rsUndoDiscard = '&Undo Discard';
  rsDiscardAction = 'Discard';
  rsDiscardHint = 'Discard this change.' + LineEnding +
    '%s. File > Undo Discard brings it back.';
  rsDiscardAsk = 'Discard this change to %s?' + LineEnding +
    '%s. File > Undo Discard brings it back.';
  rsDiscardBackOne = 'The line goes back to how it is in %s';
  rsDiscardBackMany = 'The %d lines go back to how they are in %s';
  rsDiscarded = 'Discarded the change at line %d of %s';
  rsDiscardUndone = 'Put the change at line %d of %s back';
  rsDiscardFailed = 'Could not discard the change: %s';
  rsUndoDiscardFailed = 'Could not put the change back: %s';
  rsGitignoreLexer = 'Gitignore';
  rsCopyPath = 'Copy &Path';
  rsCopyRelativePath = 'Copy &Relative Path';
  rsOpenInEditor = 'Open in &Editor';
  rsCopyBranch = 'Copy &Branch Name';
  rsCopyRepoPath = 'Copy Repository &Path';
  rsOpenTerminal = 'Open in &Terminal';
  rsPlainText = 'Plain text';
  rsNoLexers = 'No lexers found. Run "make lexlib" or set GITTAN_LEXLIB.';
  rsDiffLexer = 'Diff';
  rsBranches = 'Branches';
  rsRemoteBranches = 'Remote branches';
  rsFilterBranches = 'Filter branches';
  rsVsBase = 'vs %s';
  rsRepoDiffTitle = 'Repository diff';
  rsChangedFiles = '%d changed files';
  rsOneChangedFile = '1 changed file';
  rsNoChanges = 'No changes';
  rsNoLongerChanged = '%s has no changes any more.';
  rsGapLines = '⋯  %d unchanged lines  ⋯';
  rsGapLine = '⋯  1 unchanged line  ⋯';
  rsGapDown = '↓ %d';
  rsGapUp = '↑ %d';
  rsGapAll = 'all';
  rsPullNext = 'Next: %s  ↓';
  rsPullPrev = 'Previous: %s  ↑';
  rsSwitchBranchHint = 'Switch branch';
  rsShowSummaryHint = 'Show the summary';
  rsShowConflictHint = 'Show the first conflicted file';
  rsAheadHint = '%d commits not pushed yet';
  rsBehindHint = '%d commits not pulled yet';
  rsNotPushed = 'Not pushed yet';
  rsNotPulled = 'Not pulled yet';
  rsMoreCommits = '… and %d more';
  rsFilterCommits = 'Filter commits';
  rsPosition = 'Ln %d, Col %d';
  rsPullHintTitle = '#%d %s';
  rsPullHintPassed = '%d checks passed';
  rsPullHintPassedOne = '1 check passed';
  rsPullHintFailed = '%d checks failing';
  rsPullHintFailedOne = '1 check failing';
  rsPullHintPending = '%d checks pending';
  rsPullHintPendingOne = '1 check pending';
  rsPullHintOpen = 'Click to open it on GitHub';
  rsPositionOld = 'Ln %d (old), Col %d';

const
  { Scrolling on past the bottom of a file goes to the next one, and
    past the top to the previous: the wheel delta the pull needs (120 is
    one notch of a mouse wheel, 8 one pixel of a trackpad on macOS), the
    quiet time after which a pull left half way is forgotten, and the
    pause that tells a new gesture from the momentum of the one that
    jumped. Milliseconds. }
  OverscrollNeeded = 600;
  OverscrollForget = 1200;
  OverscrollPause = 300;
  { How long a note in the status bar stays, and an error; seconds. }
  StatusNoteSeconds = 6;
  StatusErrorSeconds = 12;
  { How long the pull request data is kept before gh is asked again,
    while checks run and otherwise; ms. }
  PullPollPending = 30000;
  PullPollIdle = 300000;
  { How often the submodules' remotes are asked again; ms. }
  SubmodulePoll = 300000;
  rsReveal = {$IFDEF DARWIN}'Reveal in &Finder'{$ELSE}
    {$IFDEF WINDOWS}'Show in &Explorer'{$ELSE}'Show in &File Manager'{$ENDIF}{$ENDIF};
  rsEditCopy = '&Copy';
  rsEditSelectAll = 'Select &All';
  rsOpenOnGitHub = 'Open on &GitHub';
  rsOpenCommitOnGitHub = 'Open Co&mmit on GitHub';
  rsCopyGitHubUrl = 'Copy GitHub &URL';
  rsOpenIssueOnGitHub = 'Open #%d on GitHub';
  rsShowCommit = 'Show Comm&it';
  rsCopyHash = 'Copy Commit &Hash';
  rsGitHubFailed = 'gh: %s';
  rsFilterFiles = 'Fi&lter Files';
  rsMergeBase = '%s (Merge Base)';
  rsVsMergeBase = '%s (merge base)';
  rsConflictedFiles = '%d conflicted files';
  rsOneConflictedFile = '1 conflicted file';
  rsFilterHint = 'Filter files';
  rsKindModified = 'Modified';
  rsKindAdded = 'Added';
  rsKindDeleted = 'Deleted';
  rsKindRenamed = 'Renamed';
  rsKindUntracked = 'Untracked';
  rsKindConflict = 'Conflict';
  rsHintStaged = '%s · staged';
  rsHintPartlyStaged = '%s · partly staged';
  rsPullRequests = 'Pull Re&quests';
  rsPullLoading = 'Loading...';
  rsNoPulls = 'No open pull requests';
  rsPullItem = '#%d %s';
  rsPullDraftItem = '#%d %s (draft)';
  rsVsPull = 'PR #%d';
  rsOpenPull = 'Open Pull Re&quest';
  rsCopyPullUrl = 'Copy Pull Request &URL';
  rsFetchingPull = 'Fetching pull request #%d...';
  rsPullFailed = 'Could not fetch pull request #%d: %s';
  { Bookmark kinds in the editor's second bookmark list, used only for the
    line backgrounds of a diff: an added line, a deleted one, a gap row
    standing for hidden lines, and a filler row of the side-by-side
    view. }
  bmAdded = 1;
  bmDeleted = 2;
  bmGap = 3;
  bmFiller = 4;
  { A legend row of the history view, and from bmHistoryBase on the
    rows of the history tinted by their commit: kind bmHistoryBase + the
    commit's index. }
  bmCommit = 5;
  { The lines of a conflict git left in a file: its marker lines, our
    side, the merge base and their side (see gittan.conflicts). }
  bmConflictMarker = 6;
  bmConflictOurs = 7;
  bmConflictBase = 8;
  bmConflictTheirs = 9;
  bmHistoryBase = 100;
  { Tags of the editor's attribs that mark the words that differ inside
    an added or a deleted line. }
  tagWordAdded = 1;
  tagWordDeleted = 2;
  { The attribute that underlines the word under the mouse while Cmd is
    held, as a link to its definition. }
  tagHoverLink = 3;
  { The attributes of the history view: a legend row in bold and the
    plain text color, over the lexer's; a word that changed, shaded in
    its commit's tint (the commit in TagEx); the swatch of a legend row;
    and the italics of an older version or the strike-through of a
    removed line. }
  tagHistoryHeader = 4;
  tagHistoryWord = 5;
  tagHistorySwatch = 6;
  tagHistoryStyle = 7;
  { The gutter band of the blame (see umain.blame.inc), the width of its
    age column in characters and the most the author column takes. }
  gutterTagBlame = 100;
  { The band with the discard buttons (see umain.discard.inc), right of
    the editor's own bands, next to the text. }
  gutterTagDiscard = 101;
  BlameAgeCols = 5;
  BlameMaxAuthorCols = 20;
  { How long the mouse rests on a word before its definition is shown. }
  HoverPause = 600;
  { How long one parse may take before a lookup or the indexer gives up
    on it. }
  ParseTimeout = 3000;
  { Row kinds in TGittanRow.Line. }
  rowGap = -1;
  rowFiller = -2;
  rowCommit = -3;
  rowMore = -4;
  { How many hidden lines a gap row's labels open at a time. }
  GapStep = 20;
  { How many commits the history view shows at a time, and the line
    range that stands for the whole file (git clamps it to the end). }
  HistoryStep = 5;
  WholeFileLines = 1000000;

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
  FGitHubCli := FindGitHubCli;
  FHasGitHubCli := FGitHubCli <> '';
  FChangeLines := TStringList.Create;
  FHotDiscard := -1;
  FBlameCache := TStringList.Create;
  FBlameCache.CaseSensitive := True;
  FBlameZombies := TList.Create;
  FBlameCols := 12;
  FSideRatio := 0.5;
  { The editor comes from umain.lfm. The EControl adapter is not an IDE
    component, so it is created here. Gittan is a viewer, so the editor is
    read-only; ShowText and OpenFile lift that while they replace the text. }
  FAdapter := TATAdapterEControl.Create(Self);
  FAdapter.AddEditor(Edit);
  { Go to Definition waits for a parse through these (see WaitForParse). }
  FAdapter.OnParseBegin := @AdapterParseBegin;
  FAdapter.OnParseDone := @AdapterParseDone;
  SetupEditor(Edit);
  { The minimap shows where in the file the changes are: it paints the
    same line backgrounds as the text. }
  Edit.OptMinimapVisible := True;
  Edit.OptMinimapTooltipVisible := False;
  { A fixed, narrow minimap; the default takes a fifth of the editor. }
  Edit.OptMinimapCharWidth := 30;
  Edit.OnChangeCaretPos := @EditChangeCaretPos;
  Edit.OnChangeModified := @EditChangeModified;
  { Scrolling on past the bottom pulls in the next file, and past the
    top the previous one; the pill that shows the pull is painted over
    the text (see EditMouseWheel). }
  Edit.OnDrawEditor := @EditDrawEditor;
  FOverscrollArmed := True;
  FOverscrollTimer := TTimer.Create(Self);
  FOverscrollTimer.Enabled := False;
  FOverscrollTimer.Interval := OverscrollForget;
  FOverscrollTimer.OnTimer := @OverscrollTimerTimer;
  FPullTimer := TTimer.Create(Self);
  FPullTimer.Enabled := False;
  FPullTimer.OnTimer := @PullTimerTimer;
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
  FEditOld.OnDrawEditor := @EditDrawEditor;
  FAdapterOld := TATAdapterEControl.Create(Self);
  FAdapterOld.AddEditor(FEditOld);
  FAdapterOld.OnParseBegin := @AdapterParseBegin;
  FAdapterOld.OnParseDone := @AdapterParseDone;
  SetupEditor(FEditOld);
  FSideSplitter := TSplitter.Create(Self);
  FSideSplitter.Parent := EditorPanel;
  FSideSplitter.Align := alLeft;
  FSideSplitter.Left := FEditOld.Width + 1;
  FSideSplitter.Visible := False;
  FSideSplitter.OnMoved := @SideSplitterMoved;
  EditorPanel.OnResize := @EditorPanelResize;

  { The status bar along the bottom; its parts answer clicks of their
    own (StatusPartClick). }
  FStatus := TGittanStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alBottom;
  FStatus.OnPartClick := @StatusPartClick;
  FStatus.PartHint[spBranch] := HintSwitch + ' ' + rsSwitchBranchHint;
  FStatus.PartHint[spFiles] := rsShowSummaryHint;
  FStatus.PartHint[spConflicts] := rsShowConflictHint;

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
  FHeader.OnAction := @HeaderAction;
  UpdateChangeNav;
  { The find bar sits under the header, above the editor. }
  FFindBar := TGittanFindBar.Create(Self);
  FFindBar.Parent := EditorPanel;
  FFindBar.Top := FHeader.Height;
  FFindBar.Align := alTop;
  FFindBar.Visible := False;
  FFindBar.OnSearch := @FindBarSearch;
  FFindBar.OnClose := @FindBarClose;
  { The symbol bar sits under the find bar. }
  FIndex := TGittanSymbolIndex.Create;
  FIndexQueue := TStringList.Create;
  FIndexTimer := TTimer.Create(Self);
  FIndexTimer.Enabled := False;
  FIndexTimer.Interval := ParseTimeout;
  FIndexTimer.OnTimer := @IndexTimerTimer;
  FHoverTimer := TTimer.Create(Self);
  FHoverTimer.Enabled := False;
  FHoverTimer.Interval := HoverPause;
  FHoverTimer.OnTimer := @HoverTimerTimer;
  { A file in the tree says what its badge means after a pause. }
  FTreeHintTimer := TTimer.Create(Self);
  FTreeHintTimer.Enabled := False;
  FTreeHintTimer.Interval := Application.HintPause;
  FTreeHintTimer.OnTimer := @TreeHintTimerTimer;
  FileTree.ShowHint := True;
  FileTree.OnMouseMove := @FileTreeMouseMove;
  FileTree.OnMouseLeave := @FileTreeMouseLeave;
  FSymbolBar := TGittanSymbolBar.Create(Self);
  FSymbolBar.Parent := EditorPanel;
  FSymbolBar.Top := FHeader.Height + FFindBar.Height;
  FSymbolBar.Align := alTop;
  FSymbolBar.Visible := False;
  FSymbolBar.OnPick := @SymbolBarPick;
  FSymbolBar.OnClose := @SymbolBarClose;
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
  FSummary.OnBranchClick := @SummaryBranchClick;
  { The branch list pops up over the form, under the branch. }
  FBranchNames := TStringList.Create;
  FBranchPopup := TGittanPopupList.Create(Self);
  FBranchPopup.Parent := Self;
  FBranchPopup.FilterHint := rsFilterBranches;
  FBranchPopup.OnPick := @BranchPopupPick;
  { The commits not pushed or pulled yet pop up over the form, above the
    counts in the status bar. }
  FSyncHashes := TStringList.Create;
  FSyncPopup := TGittanPopupList.Create(Self);
  FSyncPopup.Parent := Self;
  FSyncPopup.FilterHint := rsFilterCommits;
  FSyncPopup.OnPick := @SyncPopupPick;
  { The welcome view shares the summary's box and draws the application
    icon from its own copy: Application.Icon keeps to its small image. }
  FAppIcon := TIcon.Create;
  try
    FAppIcon.LoadFromResourceName(HInstance, 'MAINICON');
  except
    FreeAndNil(FAppIcon);
  end;
  FWelcome := TGittanWelcome.Create(Self);
  FWelcome.Parent := FSummaryBox;
  FWelcome.Title := 'Gittan';
  FWelcome.Tagline := rsTagline;
  FWelcome.Shortcut := {$IFDEF DARWIN}'⇧⌘O'{$ELSE}'Ctrl+Shift+O'{$ENDIF};
  FWelcome.SetIcon(FAppIcon);
  FWelcome.OnOpen := @WelcomeOpen;
  FWelcome.OnOpenRecent := @WelcomeOpenRecent;
  ShowWelcome('');

  FRepo := TGittanRepo.Create;
  FSnapshots := TGittanSnapshots.Create;
  FLexers := TGittanLexers.Create;
  if not FLexers.Load then
    FStatus.ShowMessage(rsNoLexers, stBad, 0);
  if FLexers.Errors <> '' then
    DebugLn(FLexers.Errors);
  FDark := IsDarkMode;
  ApplyTheme;

  SetupTreeFilter;
  SetupRepoFiles;
  SetupSubmodules;
  ApplySettings;
  BuildMenu;
  BuildPopups;
  ApplyWrap;
  OnClose := @FormClose;
  OnCloseQuery := @FormCloseQuery;
  UpdateCaption;
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
  AbandonPullJob;
  AbandonSubmoduleJobs;
  FreeAndNil(FSubJobs);
  FBranchNames.Free;
  FSyncHashes.Free;
  StopBlame;
  StopIndexing;
  SaveIndex;
  FAdapter.Lexer := nil;
  FAdapterOld.Lexer := nil;
  if FScratchAdapter <> nil then
    FScratchAdapter.Lexer := nil;
  if FIndexAdapter <> nil then
    FIndexAdapter.Lexer := nil;
  FreeAndNil(FLexers);
  FreeAndNil(FRepo);
  FreeAndNil(FSnapshots);
  FreeAndNil(FAppIcon);
  FreeAndNil(FChangeLines);
  FreeAndNil(FIndex);
  FreeAndNil(FIndexQueue);
  FreeAndNil(FSymbolFiles);

  FreeAndNil(FSettings);
end;

{ The options both editors share: read-only, every line numbered (the
  change view numbers lines itself, see SetRowNumbers, and the file view
  should look the same), fold icons only under the mouse, and the line
  states band hidden until a diff is shown. }
procedure TForm1.SetupEditor(AEd: TATSynEdit);
var
  Band: integer;
  Actions: TATEditorMouseActions;
begin
  AEd.ModeReadOnly := True;
  { The caret stays within the line: a click past its end lands at the
    end, and typing there (in a repository file open to edits) does not
    pad the line with spaces. }
  AEd.OptCaretVirtual := False;
  { Cmd+click (Ctrl+click elsewhere) goes to the definition of the word
    (see EditMouseUp); the editor's default for it, a second caret, is
    of no use in a viewer. }
  InitEditorMouseActions(Actions, True);
  AEd.MouseActions := Actions;
  AEd.OptNumbersStyle := TATEditorNumbersStyle.All;
  AEd.GutterDecorAlignment := taRightJustify;
  AEd.OnChangeZoom := @EditChangeZoom;
  AEd.OnCalcBookmarkColor := @EditCalcBookmarkColor;
  AEd.OnMouseUp := @EditMouseUp;
  { The word under the mouse shows its definition (see EditMouseMove). }
  AEd.OnMouseMove := @EditMouseMove;
  AEd.OnMouseLeave := @EditMouseLeave;
  AEd.ShowHint := True;
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
  { The blame band, leftmost, hidden until View > Blame; the editor
    leaves its size alone (see SetBlameBand). }
  AEd.Gutter.Add(0, 0, gutterTagBlame, False, False);
  { The discard band, rightmost, shown with a changed file (see
    SetDiscardBand). }
  AEd.Gutter.Add(-1, 0, gutterTagDiscard, False, False);
  AEd.OnClickGutter := @EditClickGutter;
end;

function TForm1.AdapterOf(AEd: TATSynEdit): TATAdapterEControl;
begin
  if AEd = FEditOld then
    Result := FAdapterOld
  else if AEd = FScratch then
    Result := FScratchAdapter
  else if AEd = FIndexEdit then
    Result := FIndexAdapter
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
  FLexers.ApplyTheme(FDark, FSyntaxTheme);
  { The header and the find bar take the gutter's shade; the navigator
    pills sit on it. }
  if FDark then
  begin
    FHeader.SetColors(RGBToColor(37, 37, 38), Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(63, 185, 80), RGBToColor(248, 81, 73),
      RGBToColor(62, 62, 62));
    FNav.SetColors(RGBToColor(37, 37, 38), RGBToColor(50, 50, 51),
      RGBToColor(85, 85, 86), RGBToColor(200, 200, 200), RGBToColor(100, 160, 240));
    FHeader.SetPillColors(RGBToColor(50, 50, 51), RGBToColor(85, 85, 86),
      RGBToColor(100, 160, 240));
    FFindBar.SetColors(RGBToColor(37, 37, 38), Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(62, 62, 62));
    FSymbolBar.SetColors(RGBToColor(37, 37, 38), Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(62, 62, 62));
    FFindBar.Nav.SetColors(RGBToColor(37, 37, 38), RGBToColor(50, 50, 51),
      RGBToColor(85, 85, 86), RGBToColor(200, 200, 200), RGBToColor(100, 160, 240));
    FBranchPopup.SetColors(RGBToColor(37, 37, 38), Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(58, 58, 59), RGBToColor(85, 85, 86),
      RGBToColor(100, 160, 240));
    FSyncPopup.SetColors(RGBToColor(37, 37, 38), Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(58, 58, 59), RGBToColor(85, 85, 86),
      RGBToColor(100, 160, 240));
    FStatus.SetColors(RGBToColor(37, 37, 38), Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(62, 62, 62), RGBToColor(58, 58, 59),
      RGBToColor(100, 160, 240), RGBToColor(63, 185, 80), RGBToColor(227, 179, 65),
      RGBToColor(248, 81, 73));
    FPullFill := RGBToColor(50, 50, 51);
    FPullBorder := RGBToColor(85, 85, 86);
    FPullText := RGBToColor(200, 200, 200);
    FPullBar := RGBToColor(40, 80, 130);
    FLinkColor := RGBToColor(78, 161, 255);
  end
  else
  begin
    FHeader.SetColors(RGBToColor(246, 246, 246), RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(26, 127, 55), RGBToColor(207, 34, 46),
      RGBToColor(222, 222, 222));
    FNav.SetColors(RGBToColor(246, 246, 246), clWhite,
      RGBToColor(205, 205, 205), RGBToColor(70, 70, 70), RGBToColor(0, 110, 230));
    FHeader.SetPillColors(clWhite, RGBToColor(205, 205, 205), RGBToColor(0, 110, 230));
    FFindBar.SetColors(RGBToColor(246, 246, 246), RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(222, 222, 222));
    FSymbolBar.SetColors(RGBToColor(246, 246, 246), RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(222, 222, 222));
    FFindBar.Nav.SetColors(RGBToColor(246, 246, 246), clWhite,
      RGBToColor(205, 205, 205), RGBToColor(70, 70, 70), RGBToColor(0, 110, 230));
    FBranchPopup.SetColors(clWhite, RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(235, 235, 235), RGBToColor(205, 205, 205),
      RGBToColor(0, 110, 230));
    FSyncPopup.SetColors(clWhite, RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(235, 235, 235), RGBToColor(205, 205, 205),
      RGBToColor(0, 110, 230));
    FStatus.SetColors(RGBToColor(246, 246, 246), RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(222, 222, 222), RGBToColor(232, 232, 232),
      RGBToColor(0, 110, 230), RGBToColor(26, 127, 55), RGBToColor(154, 103, 0),
      RGBToColor(207, 34, 46));
    FPullFill := clWhite;
    FPullBorder := RGBToColor(205, 205, 205);
    FPullText := RGBToColor(70, 70, 70);
    FPullBar := RGBToColor(205, 225, 250);
    FLinkColor := RGBToColor(0, 102, 204);
  end;
  FSummaryBox.Color := Edit.Colors.TextBG;
  if FDark then
  begin
    FSummary.SetColors(Edit.Colors.TextBG, Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(45, 45, 46), RGBToColor(38, 38, 39),
      RGBToColor(63, 185, 80), RGBToColor(248, 81, 73), RGBToColor(62, 62, 62));
    FWelcome.SetColors(Edit.Colors.TextBG, Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(45, 45, 46), RGBToColor(85, 85, 86),
      RGBToColor(248, 81, 73));
  end
  else
  begin
    FSummary.SetColors(Edit.Colors.TextBG, RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(243, 243, 243), RGBToColor(248, 248, 248),
      RGBToColor(26, 127, 55), RGBToColor(207, 34, 46), RGBToColor(222, 222, 222));
    FWelcome.SetColors(Edit.Colors.TextBG, RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(243, 243, 243), RGBToColor(205, 205, 205),
      RGBToColor(207, 34, 46));
  end;
  if FRepoHeader <> nil then
    ColorRepoHeader;
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
  open; the header names the file, so the title does not change with it.
  Cocoa reads an ampersand in a window title as an accelerator and drops
  it, so there every ampersand is doubled. }
procedure TForm1.UpdateCaption;
var
  Title: string;
begin
  if FRepo.Root <> '' then
    Title := ExtractFileName(FRepo.Root) + ' - ' + rsAppName
  else if Edit.FileName <> '' then
    Title := ExtractFileName(Edit.FileName) + ' - ' + rsAppName
  else
    Title := rsAppName;
  {$IFDEF LCLCocoa}
  Title := StringReplace(Title, '&', '&&', [rfReplaceAll]);
  {$ENDIF}
  Caption := Title;
end;

{ The status bar shows the repository whenever one is open: its name,
  the branch, the commits ahead and behind, what git is in the middle of,
  the conflicted files, the base, the pull request, the indexing and the
  changed files (the header names the file and its lexer). Without one it
  shows the path of a plain file. Messages and the caret's position are
  set elsewhere and left alone. }
procedure TForm1.UpdateStatus;
var
  Lexer, Sync: string;
  Tone: TGittanStatusTone;
  Checks: integer;
begin
  if FAdapter.Lexer = nil then
    Lexer := rsPlainText
  else
    Lexer := FAdapter.Lexer.LexerName;
  FHeader.SetLexer(Lexer);
  UpdateSyntaxChecks;
  if FRepo.Root = '' then
  begin
    FStatus.SetRepository(Edit.FileName, '');
    if Edit.FileName <> '' then
      FStatus.PartHint[spRepo] := HintFolder + ' ' + Edit.FileName
    else
      FStatus.PartHint[spRepo] := '';
    FStatus.SetSync(0, 0);
    FStatus.SetState('', '');
    FStatus.SetBase('');
    FStatus.SetPull('', '', stNormal, 0);
    FStatus.SetFiles('');
    FStatus.SetProgress('', 0, 0);
    Exit;
  end;
  FStatus.SetRepository(ExtractFileName(FRepo.Root), FBranch);
  FStatus.PartHint[spRepo] := HintFolder + ' ' + FRepo.Root;
  if FHasUpstream then
    FStatus.SetSync(FAhead, FBehind)
  else
    FStatus.SetSync(0, 0);
  Sync := '';
  if FHasUpstream and (FAhead > 0) then
    Sync := Format(rsAheadHint, [FAhead]);
  if FHasUpstream and (FBehind > 0) then
    Sync := Trim(Sync + LineEnding + Format(rsBehindHint, [FBehind]));
  FStatus.PartHint[spSync] := Sync;
  case FConflictFiles of
    0: FStatus.SetState(FOperation, '');
    1: FStatus.SetState(FOperation, rsOneConflictedFile);
    else
      FStatus.SetState(FOperation, Format(rsConflictedFiles, [FConflictFiles]));
  end;
  FStatus.SetBase(BaseLabel);
  if FHasPull then
  begin
    Tone := PullChecks(FPull, Checks);
    FStatus.SetPull('#' + IntToStr(FPull.Number), PullRequestNote(FPull), Tone, Checks);
    FStatus.PartHint[spPull] := PullHint(FPull);
  end
  else
    FStatus.SetPull('', '', stNormal, 0);
  if FIndexing then
    FStatus.SetProgress(Format(rsIndexing, [FIndexPos, FIndexTotal]),
      FIndexPos, FIndexTotal)
  else
    FStatus.SetProgress('', 0, 0);
  case FFileCount of
    0: FStatus.SetFiles(rsNoChanges);
    1: FStatus.SetFiles(rsOneChangedFile);
    else
      FStatus.SetFiles(Format(rsChangedFiles, [FFileCount]));
  end;
end;

procedure TForm1.StatusNote(const AText: string; AError: boolean);
begin
  if AError then
    FStatus.ShowMessage(AText, stBad, StatusErrorSeconds)
  else
    FStatus.ShowMessage(AText, stNormal, StatusNoteSeconds);
end;

{ The line is the file's own: in the change view the new side's number,
  or the old side's for a deleted line, since the rows of the view are
  not the file's lines. The column counts characters from 1. The
  repository diff and the history have no file line to name. }
procedure TForm1.UpdateStatusPosition;
var
  Row, Col, Line: integer;
  Old: boolean;
begin
  { Edit.Visible is no test: a file's view is built before ShowEditor
    shows the editor. }
  if (Edit.Carets.Count = 0) or not (FView in [gvChanges, gvFile]) then
  begin
    FStatus.SetPosition('');
    Exit;
  end;
  Row := Edit.Carets[0].PosY;
  Col := Edit.Carets[0].PosX + 1;
  Old := False;
  Line := FileLineOfRow(Edit, Row);
  if (Line = 0) and (FView = gvChanges) and (Row <= High(FRows)) and
    (FRows[Row].Line >= 0) and (FRows[Row].Line <= High(FOldNum)) then
  begin
    Line := FOldNum[FRows[Row].Line];
    Old := Line > 0;
  end;
  if Line <= 0 then
    FStatus.SetPosition('')
  else if Old then
    FStatus.SetPosition(Format(rsPositionOld, [Line, Col]))
  else
    FStatus.SetPosition(Format(rsPosition, [Line, Col]));
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
  FileMenu, ViewMenu, GoMenu, ToolsMenu, Item, Sub: TMenuItem;
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
  FSaveItem := AddItem(FileMenu, rsSave, ShortCut(VK_S, [ssModifier]), @MenuSaveClick);
  FSaveItem.Enabled := False;
  FileMenu.Add(NewLine);
  FDiscardItem := AddItem(FileMenu, rsDiscardChange, ShortCut(VK_BACK, [ssModifier, ssShift]),
    @MenuDiscardClick);
  FUndoDiscardItem := AddItem(FileMenu, rsUndoDiscard, ShortCut(VK_Z, [ssModifier, ssAlt]),
    @MenuUndoDiscardClick);
  UpdateDiscardItems;
  FileMenu.OnClick := @FileMenuClick;
  FileMenu.Add(NewLine);
  FTerminalItem := AddItem(FileMenu, rsOpenTerminal, ShortCut(VK_T, [ssModifier, ssAlt]),
    @MenuOpenTerminalClick);

  FTerminalItem.Enabled := False;

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
  FBlameItem := AddItem(ViewMenu, rsBlame, ShortCut(VK_B, [ssModifier, ssShift]),
    @MenuBlameClick);
  FBlameItem.Checked := FBlameOn;
  ViewMenu.Add(NewLine);
  AddItem(ViewMenu, rsZoomIn, ShortCut(VK_OEM_PLUS, [ssModifier]), @MenuZoomInClick);
  AddItem(ViewMenu, rsZoomOut, ShortCut(VK_OEM_MINUS, [ssModifier]), @MenuZoomOutClick);
  AddItem(ViewMenu, rsZoomReset, ShortCut(VK_0, [ssModifier]), @MenuZoomResetClick);
  AddItem(ViewMenu, rsFont, 0, @MenuFontClick);
  Sub := AddItem(ViewMenu, rsSyntaxTheme, 0, nil);
  SetLength(FThemeItems, Length(SyntaxThemes));
  for i := 0 to High(SyntaxThemes) do
  begin
    Item := AddItem(Sub, SyntaxThemes[i].Name, 0, @MenuSyntaxThemeClick);
    Item.Tag := i;
    Item.RadioItem := True;
    Item.Checked := i = FSyntaxTheme;
    FThemeItems[i] := Item;
  end;

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
  AddItem(GoMenu, rsFilterFiles, ShortCut(VK_F, [ssModifier, ssShift]), @MenuFilterFilesClick);
  GoMenu.Add(NewLine);
  AddItem(GoMenu, rsGoToDefinition, ShortCut(VK_F12, []), @MenuGoToDefinitionClick);
  AddItem(GoMenu, rsGoToSymbol, ShortCut(VK_T, [ssModifier]), @MenuGoToSymbolClick);
  AddItem(GoMenu, rsGoToRepoSymbol, ShortCut(VK_T, [ssModifier, ssShift]),
    @MenuGoToRepoSymbolClick);
  { Cmd+Y alone is the editor's delete-line key, which gets the key first. }
  AddItem(GoMenu, rsChangedSymbols, ShortCut(VK_Y, [ssModifier, ssShift]),
    @MenuChangedSymbolsClick);
  AddItem(GoMenu, rsCallers, ShortCut(VK_C, [ssModifier, ssShift]), @MenuCallersClick);
  AddItem(GoMenu, rsHistory, ShortCut(VK_H, [ssModifier, ssShift]), @MenuHistoryClick);
  GoMenu.Add(NewLine);
  AddItem(GoMenu, rsNextChange, ShortCut(VK_F7, []), @MenuNextChangeClick);
  AddItem(GoMenu, rsPrevChange, ShortCut(VK_F7, [ssShift]), @MenuPrevChangeClick);
  GoMenu.Add(NewLine);
  AddItem(GoMenu, rsNextFile, ShortCut(VK_F8, []), @MenuNextFileClick);
  AddItem(GoMenu, rsPrevFile, ShortCut(VK_F8, [ssShift]), @MenuPrevFileClick);

  ToolsMenu := TMenuItem.Create(Main);
  ToolsMenu.Caption := rsTools;
  ToolsMenu.OnClick := @ToolsMenuClick;
  Main.Items.Add(ToolsMenu);
  AddItem(ToolsMenu, rsInstallCli, 0, @MenuInstallCliClick);
  FUninstallCliItem := AddItem(ToolsMenu, rsUninstallCli, 0, @MenuUninstallCliClick);
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
    gvChanges: Result := FLexers.ForFile(FCurrentPath, FRepo.Root);
    gvRepoDiff: Result := FLexers.ByName(rsDiffLexer);
    gvFile: Result := FLexers.ForFile(Edit.FileName);
    gvHistory: Result := FLexers.ForFile(FHistoryPath, FRepo.Root);
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
  if AEd = Edit then
  begin
    FlushEdit;
    LeaveEdit;
  end;
  AdapterOf(AEd).Lexer := nil;
  AEd.BookmarkDeleteAll_2;
  ResetLineNumbers(AEd);
  AEd.ModeReadOnly := False;
  AEd.Text := UTF8Decode(AText);
  { Setting Text skips the wrap rebuild while the editor has no fold ranges
    (it is in "virtual" wrap mode then) and never flags one as needed, so
    once the lexer adds folds the wrap items of the previous text are
    reused and lines paint cut off. LoadFromFile clears the wrap info and
    flags the rebuild itself; do the same here. The rebuild must be a full
    one: the editor otherwise applies the line operations it recorded for
    the replacement to the cleared wrap info, which can leave it empty
    and the editor blank (seen when the history view replaced its own
    text), so the recorded operations are dropped too. }
  AEd.WrapInfo.Clear;
  AEd.Strings.WrapStructInvalidate;
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
  FlushEdit;
  LeaveEdit;
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
  { One of the repository's own files is open to edits. }
  if RepoFileName(AFileName) then
    BeginEdit(AFileName);
  { The exclude file has .gitignore's syntax but not its name. }
  if (AFileName <> '') and (AFileName = FExcludePath) then
    SetLexer(FLexers.ByName(rsGitignoreLexer))
  else
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
{ A color from a hue, saturation and lightness, each 0..1. }
function HSLToColor(H, S, L: double): TColor;
var
  C, X, M, R, G, B: double;
  Sector: integer;
begin
  C := (1 - Abs(2 * L - 1)) * S;
  Sector := Trunc(H * 6) mod 6;
  X := C * (1 - Abs(Frac(H * 6) * 2 - 1));
  case Sector of
    0: begin R := C; G := X; B := 0; end;
    1: begin R := X; G := C; B := 0; end;
    2: begin R := 0; G := C; B := X; end;
    3: begin R := 0; G := X; B := C; end;
    4: begin R := X; G := 0; B := C; end;
    else begin R := C; G := 0; B := X; end;
  end;
  M := L - C / 2;
  Result := RGBToColor(Round((R + M) * 255), Round((G + M) * 255), Round((B + M) * 255));
end;

{ The commit index as an attribute's TagEx, which is a byte. }
function HistoryTagEx(ACommit: integer): integer;
begin
  Result := Max(-1, Min(ACommit, 127));
end;

procedure TForm1.EditCalcBookmarkColor(Sender: TObject; ABookmarkKind: integer;
  var AColor: TColor);
begin
  { A faint tint of the editor background, so the syntax colors still
    read on top of it; a gap and a filler row take the gutter's shade, a
    legend row of the history view a cool one, a row of the history
    the tint of its commit, and the lines of a conflict a violet for the
    markers, a blue for our side, a grey for the base and an amber for
    theirs. }
  if ABookmarkKind >= bmHistoryBase then
  begin
    AColor := HistoryColor(ABookmarkKind - bmHistoryBase, False);
    Exit;
  end;
  if FDark then
    case ABookmarkKind of
      bmAdded: AColor := RGBToColor(32, 52, 37);
      bmDeleted: AColor := RGBToColor(66, 38, 38);
      bmGap: AColor := RGBToColor(44, 44, 46);
      bmFiller: AColor := RGBToColor(37, 37, 38);
      bmCommit: AColor := RGBToColor(40, 46, 58);
      bmConflictMarker: AColor := RGBToColor(74, 44, 92);
      bmConflictOurs: AColor := RGBToColor(30, 46, 72);
      bmConflictBase: AColor := RGBToColor(46, 46, 48);
      bmConflictTheirs: AColor := RGBToColor(62, 52, 28);
    end
  else
    case ABookmarkKind of
      bmAdded: AColor := RGBToColor(218, 251, 225);
      bmDeleted: AColor := RGBToColor(255, 235, 233);
      bmGap: AColor := RGBToColor(238, 238, 238);
      bmFiller: AColor := RGBToColor(246, 246, 246);
      bmCommit: AColor := RGBToColor(226, 232, 240);
      bmConflictMarker: AColor := RGBToColor(232, 214, 246);
      bmConflictOurs: AColor := RGBToColor(221, 235, 255);
      bmConflictBase: AColor := RGBToColor(236, 236, 236);
      bmConflictTheirs: AColor := RGBToColor(255, 241, 208);
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
{ The tint of commit AIndex of the history view, or the strong one for
  the words that changed and the swatch: one hue per commit, spread by
  the golden angle so neighbours differ, as a faint tint of the editor
  background in the way of the diff colors. A row older than the history
  (AIndex -1) gets a grey. }
function TForm1.HistoryColor(AIndex: integer; AStrong: boolean): TColor;
var
  Hue, Sat, Light: double;
begin
  if AIndex < 0 then
  begin
    if FDark then
      Sat := 0
    else
      Sat := 0;
    Hue := 0;
  end
  else
  begin
    Hue := ((210 + AIndex * 137) mod 360) / 360;
    if FDark then
      Sat := 0.45
    else
      Sat := 0.65;
  end;
  if FDark then
  begin
    if AStrong then
      Light := 0.36
    else
      Light := 0.22;
  end
  else
  begin
    if AStrong then
      Light := 0.78
    else
      Light := 0.91;
  end;
  Result := HSLToColor(Hue, Sat, Light);
end;

{ Sets row ARow, a legend row of the history view, in bold and in the
  editor's text color: the lexer would otherwise color the words of
  the summary as code. The swatch at its start is colored on top. }
procedure TForm1.MarkHeader(AEd: TATSynEdit; ARow: integer);
var
  Part: TATLinePart;
begin
  InitLinePart(Part);
  Part.ColorFont := AEd.Colors.TextFont;
  Part.FontStyles := afsFontBold;
  AEd.Attribs.Add(Point(0, ARow), Point(AEd.Strings.LinesLen[ARow], 0),
    TATMarkerTags.Init(tagHistoryHeader, 0), @Part);
end;

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
    end
    else if Item.Tag = tagHistoryHeader then
    begin
      Item.LinePart.ColorFont := AEd.Colors.TextFont;
      AEd.Attribs[i] := Item;
    end
    else if Item.Tag = tagHistoryWord then
    begin
      Item.LinePart.ColorBG := HistoryColor(Item.TagEx, True);
      AEd.Attribs[i] := Item;
    end
    else if Item.Tag = tagHistorySwatch then
    begin
      Item.LinePart.ColorFont := HistoryColor(Item.TagEx, True);
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

{ The width of one character of AEd's font, at its zoom, measured here:
  the editor measures its own at its next paint, and the number band is
  sized before that, when the change view of the first file is built
  (the summary hides the editor until then) and on a zoom. Until then
  the editor's TextCharSize is a placeholder, and a band sized from it
  cuts the numbers once the editor applies it. }
{ The size of AEd's font at its zoom, as the editor sets its canvas. }
function EditorFontSize(AEd: TATSynEdit): integer;
begin
  if AEd.OptScaleFont > 0 then
    Result := AEd.Font.Size * AEd.OptScaleFont div 100
  else
    Result := ATEditorScaleFont(AEd.Font.Size);
end;

function EditorCharWidth(AEd: TATSynEdit): integer;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.Canvas.Font.Name := AEd.Font.Name;
    Bmp.Canvas.Font.Size := EditorFontSize(AEd);
    Result := Max(1, Bmp.Canvas.TextWidth(ATEditorOptions.SampleChar));
  finally
    Bmp.Free;
  end;
end;

{ The bookmark band holds the line numbers while the change view is shown:
  room for the widest number (its text has the trailing space) and one
  character of indent. The band width is reapplied by the editor on every
  update, so the option is set rather than the band. }
procedure TForm1.UpdateNumberWidth(AEd: TATSynEdit);
var
  Widest, i: integer;
begin
  if AEd.GutterDecor.Count = 0 then
    Exit;
  Widest := 0;
  for i := 0 to AEd.GutterDecor.Count - 1 do
    Widest := Max(Widest, Length(AEd.GutterDecor.ItemPtr(i)^.Data.TextAll));
  AEd.OptGutterWidthBookmarks := (Widest + 1) * EditorCharWidth(AEd);
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
  ApplyBlame;
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
    if (Marks[i]^.Data.Kind = bmGap) or (Marks[i]^.Data.Kind = bmCommit) then
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
  UpdateSymbolCrumb;
  UpdateStatusPosition;
  UpdateDiscardItems;
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
  FlushEdit;
  LeaveEdit;
  StopWatcher;
  StopIndexing;
  SaveIndex;
  FSummary.Notice := '';
  FCurrentPath := '';
  { The discards of the previous repository are not for this one. }
  FDiscards := nil;
  UpdateDiscardItems;
  FPullRange := '';
  FExcludePath := '';
  AbandonSubmoduleJobs;
  FSubmodules := nil;
  FSubInfos := nil;
  FSubKey := '';
  FSubShown := '';
  if not FRepo.Open(ADir) then
  begin
    ShowError(FRepo.Error);
    Exit;
  end;
  { The exclude file lives in the git directory, which git names (a
    work tree's is elsewhere), once per open: the section lists it and
    Add to .git/info/exclude writes to it. }
  FExcludePath := FRepo.GitDir;
  if FExcludePath <> '' then
    FExcludePath := IncludeTrailingPathDelimiter(FExcludePath) + SetDirSeparators(ExcludeFile);
  UpdateCaption;
  FSummary.Selected := '';
  LoadSnapshots;
  if not LoadRepository then
    ShowError(FLoadError)
  else
  begin
    FSettings.AddRecent(FRepo.Root);
    RebuildRecentMenu;
    ShowSummary;
    StartIndexing;
  end;
  StartWatcher;
end;

{ A failure to open or read a repository is shown where the hint was: in
  the empty view, not in a dialog, so the next attempt is one drop away. }
procedure TForm1.ShowError(const AMessage: string);
begin
  FileTree.Items.Clear;
  FRepoTree.Items.Clear;
  FRepoPanel.Visible := False;
  AbandonSubmoduleJobs;
  FSubmodules := nil;
  FSubInfos := nil;
  FSubKey := '';
  FSubTree.Items.Clear;
  FSubPanel.Visible := False;
  FStats := nil;
  FFileCount := 0;
  ShowWelcome(AMessage);
  ShowSummary;
  UpdateStatus;
  { The welcome view keeps the error; the bar's copy clears itself, so
    it is not left behind when a repository opens. }
  FStatus.ShowMessage(AMessage, stBad, StatusErrorSeconds);
  UpdateCaption;
end;

{ Reads the branch and the changed files of the open repository into the
  tree and the summary. Returns false, with the message in FLoadError,
  when git failed; the views are empty then. }
{ Gathers the repository and draws it, all on this thread: the load when a
  repository is opened, where a short wait is expected. The watcher path
  gathers the snapshot in its own thread and calls ApplySnapshot alone. }
function TForm1.LoadRepository: boolean;
var
  Snap: TGittanRepoSnapshot;
begin
  Result := FRepo.Snapshot(Snap);
  ApplySnapshot(Snap);
end;

{ Draws a snapshot of the repository into the views, on the main thread.
  The git work that built it is ApplySnapshot's caller's business: it is
  done on this thread by LoadRepository, in the watcher thread otherwise. }
procedure TForm1.ApplySnapshot(const ASnap: TGittanRepoSnapshot);
var
  Icons: array of integer;
  i: integer;
  Branch: string;
begin
  if not ASnap.Ok then
    FLoadError := ASnap.Error;
  ClearBlameCache;
  FStats := ASnap.Stats;
  FBranch := ASnap.Branch;
  { The pull request is looked up for the branch HEAD is on, the detached
    id during a rebase, so this runs before the rebase branch stands in. }
  StartPullJob(False);
  FDefaultBranch := ASnap.DefaultBranch;
  FMergeBase := ASnap.MergeBase;
  FHasUpstream := ASnap.HasUpstream;
  FAhead := ASnap.Ahead;
  FBehind := ASnap.Behind;
  FOperation := ASnap.Operation;
  if (FOperation = 'rebasing') and (ASnap.RebaseBranch <> '') then
    { HEAD is detached while a rebase stops; the branch is the one it
      rebases. }
    FBranch := ASnap.RebaseBranch;
  FConflictFiles := 0;
  for i := 0 to High(FStats) do
    if FStats[i].Kind = ckConflict then
      Inc(FConflictFiles);
  FFileCount := Length(FStats);
  FillFileTree(FStats);
  FillRepoFiles;
  FillSubmodules;
  SetLength(Icons, Length(FStats));
  for i := 0 to High(FStats) do
    Icons[i] := StatIcon(FStats[i]);
  Branch := FBranch;
  if FOperation <> '' then
    Branch := Branch + ' · ' + FOperation;
  FSummary.SetRepository(ExtractFileName(FRepo.Root), Branch, BaseLabel, FStats, Icons);
  FWelcome.Visible := False;
  FSummary.Visible := True;
  RebuildCompareMenu;
  FTerminalItem.Enabled := FRepo.Root <> '';
end;

{ The badge of a file: solid when the index holds all of its change,
  ringed when it holds part of it. }
function TForm1.StatIcon(const AStat: TGittanFileStat): integer;
begin
  if AStat.Staged then
    Result := StagedIcon(AStat.Kind, AStat.Unstaged)
  else
    Result := ChangeIcon(AStat.Kind);
end;

{ What a file's badge means: the kind of change, and how much of it is
  staged. }
function TForm1.StatHint(const AStat: TGittanFileStat): string;
const
  KindNames: array[TGittanChangeKind] of string = (rsKindModified,
    rsKindAdded, rsKindDeleted, rsKindRenamed, rsKindUntracked, rsKindConflict);
begin
  Result := KindNames[AStat.Kind];
  if AStat.Staged and AStat.Unstaged then
    Result := Format(rsHintPartlyStaged, [Result])
  else if AStat.Staged then
    Result := Format(rsHintStaged, [Result]);
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
  FWatcher := TGittanWatcher.Create(FRepo.Root, FRepo.Base, FRepo.WholeTree,
    WatchInterval);
  FWatcher.OnChange := @WatcherChange;
  FWatcher.Start;
end;

procedure TForm1.StopWatcher;
begin
  FreeAndNil(FWatcher);
end;

procedure TForm1.WatcherChange(Sender: TObject);
var
  Snap: TGittanRepoSnapshot;
begin
  { Runs on the main thread while the watcher is held in Synchronize, so
    its snapshot, gathered off the main thread, is copied out and applied
    without running any git here. }
  Snap := FWatcher.Snapshot;
  RefreshRepository(@Snap);
end;

procedure TForm1.MenuRefreshClick(Sender: TObject);
begin
  RefreshRepository;
  StartPullJob(True);
  if FRepo.Root <> '' then
  begin
    StartSubmoduleJobs;
    FillSubmoduleTree;
    if FView = gvSubmodule then
      RestoreSubmodule;
  end;
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
  runs the usual selection handler. ASnap nil reads the repository here;
  otherwise it is the snapshot the watcher already gathered off the main
  thread, which is only drawn. }
procedure TForm1.RefreshRepository(ASnap: PGittanRepoSnapshot = nil);
var
  Collapsed: TStringList;
  Node: TTreeNode;
  Path, RepoPath: string;
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
  RepoPath := '';
  if (FRepoTree.Selected <> nil) and (FRepoTree.Selected.Data <> nil) then
    RepoPath := FRepoTree.Selected.GetTextPath;
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
    if ASnap = nil then
    begin
      if not LoadRepository then
        FStatus.ShowMessage(FLoadError, stBad, 0);
    end
    else
    begin
      ApplySnapshot(ASnap^);
      if not ASnap^.Ok then
        FStatus.ShowMessage(FLoadError, stBad, 0);
    end;
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
  SelectRepoNode(RepoPath);
  case View of
    gvFile:
      { A repository file open to edits follows the disk while the
        editor holds it unchanged; an edit in progress is left alone and
        the header says the file changed behind it. }
      if (FEditPath <> '') and FileExists(FEditPath) and
        (FileAge(FEditPath) <> FEditStamp) then
        if Edit.Modified then
          FHeader.SetNote(rsChangedOnDisk)
        else
        begin
          OpenFile(FEditPath);
          RestoreScroll;
        end;
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
    gvSubmodule:
      begin
        RestoreSubmodule;
        if FView = gvSubmodule then
          RestoreScroll;
      end;
    gvHistory:
      begin
        { The view is rebuilt when the job is done, at the same place. }
        FHistoryTopLine := TopLine;
        FHistoryCaretY := CaretY;
        StartHistory;
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
  FlushEdit;
  LeaveEdit;
  Edit.Visible := False;
  FEditOld.Visible := False;
  FSideSplitter.Visible := False;
  FHeader.Visible := False;
  FFindBar.Visible := False;
  FSymbolBar.Visible := False;
  FSummaryBox.Visible := True;
  AbandonHistoryJob;
  FView := gvSummary;
  FStatus.SetPosition('');
  { A file picked again after the summary must fire the selection event. }
  FileTree.Selected := nil;
  FRepoTree.Selected := nil;
  FSubTree.Selected := nil;
  if FRepo.Root <> '' then
    UpdateStatus;
end;

{ FView is set before the call: the layout depends on it. }
procedure TForm1.ShowEditor;
begin
  { A history still being fetched is for a view that is no longer shown. }
  if FView <> gvHistory then
    AbandonHistoryJob;
  { The symbol bar lists the file shown before. }
  FSymbolBar.Visible := False;
  FSummaryBox.Visible := False;
  FHeader.Visible := True;
  ApplyLayout;
  ApplyBlame;
  Edit.Visible := True;
end;

{ The summary paints its own background; it must cover the scroll box. }
procedure TForm1.SummaryBoxResize(Sender: TObject);
begin
  FSummary.FitHeight(FSummaryBox.ClientHeight);
  FWelcome.FitHeight(FSummaryBox.ClientHeight);
end;

{ The welcome view takes the summary's place in the box, with AError
  under its title when opening a repository failed; it stays until a
  repository loads, see LoadRepository. }
procedure TForm1.ShowWelcome(const AError: string);
begin
  FWelcome.SetError(AError);
  FSummary.Visible := False;
  FWelcome.Visible := True;
  FWelcome.FitHeight(FSummaryBox.ClientHeight);
end;

procedure TForm1.WelcomeOpen(Sender: TObject);
begin
  MenuOpenRepoClick(Sender);
end;

procedure TForm1.WelcomeOpenRecent(Sender: TObject; const ARoot: string);
begin
  OpenRepository(ARoot);
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
    Title := Title + ' ' + BaseLabel;
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
  { Asked before the header names the next file, not when the text is
    replaced further down. }
  FlushEdit;
  Lines := TStringList.Create;
  try
    if not FRepo.FileChanges(APath, Lines) then
    begin
      StatusNote(FRepo.Error, True);
      Exit;
    end;
    FChangeLines.Assign(Lines);
  finally
    Lines.Free;
  end;
  if APath <> FCurrentPath then
    FExpanded := nil;
  { The diff may have changed, so the blocks and their headings are
    found again after the parse. }
  FHeadings := nil;
  FHeadingRebuilds := 0;
  FCurrentPath := APath;
  SetOverscroll(0);
  FSummary.Notice := '';
  FHeader.SetFile(APath, -1);
  FConflictRoles := nil;
  for i := 0 to High(FStats) do
    if FStats[i].Path = APath then
    begin
      FHeader.SetFile(APath, StatIcon(FStats[i]));
      FHeader.SetCounts(FStats[i].Added, FStats[i].Deleted, FStats[i].Binary);
      FHeader.SetStage(FStats[i].Staged, FStats[i].Unstaged);
      if FStats[i].Kind = ckConflict then
        FConflictRoles := ConflictRoles(FChangeLines);
      Break;
    end;
  { One of the repository's own files can be opened to edits. }
  if IsRepoFile(APath) then
    FHeader.SetActions([rsEditAction]);
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
  StartBlame;
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
      if (Path = '') or ((FTreeFilterText <> '') and
        (Pos(FTreeFilterText, LowerCase(Path)) = 0)) then
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

{ ---------------------------------------------------------------------------
  The tree filter
  ---------------------------------------------------------------------------
  The tree comes from umain.lfm aligned left on the form; it is moved
  into a panel of the same width under a native edit field, so the
  splitter sizes the panel and the settings keep its width. }
procedure TForm1.SetupTreeFilter;
begin
  FTreePanel := TPanel.Create(Self);
  FTreePanel.BevelOuter := bvNone;
  FTreePanel.Caption := '';
  FTreePanel.Width := FileTree.Width;
  FTreePanel.Left := 0;
  FTreePanel.Align := alLeft;
  FTreePanel.Parent := Self;
  FTreeFilter := TEdit.Create(Self);
  FTreeFilter.TextHint := rsFilterHint;
  FTreeFilter.Align := alTop;
  FTreeFilter.BorderSpacing.Around := 4;
  FTreeFilter.OnChange := @TreeFilterChange;
  FTreeFilter.OnKeyDown := @TreeFilterKeyDown;
  FTreeFilter.Parent := FTreePanel;
  FileTree.Parent := FTreePanel;
  FileTree.Align := alClient;
end;

{ Rebuilds the tree for the new filter and keeps the shown file selected
  without reloading it. }
procedure TForm1.TreeFilterChange(Sender: TObject);
var
  Handler: TNotifyEvent;
begin
  FTreeFilterText := LowerCase(Trim(FTreeFilter.Text));
  Handler := FileTree.OnSelectionChanged;
  FileTree.OnSelectionChanged := nil;
  try
    FillFileTree(FStats);
    if (FView = gvChanges) and (FCurrentPath <> '') then
      SummarySelectFile(nil, FCurrentPath);
  finally
    FileTree.OnSelectionChanged := Handler;
  end;
end;

{ Escape clears the filter, or leaves the field when it is empty; Enter
  and Down go to the tree. }
procedure TForm1.TreeFilterKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE:
      begin
        Key := 0;
        if FTreeFilter.Text <> '' then
          FTreeFilter.Text := ''
        else if FileTree.CanFocus then
          FileTree.SetFocus;
      end;
    VK_RETURN, VK_DOWN:
      begin
        Key := 0;
        if FileTree.CanFocus then
        begin
          if (FileTree.Selected = nil) and (FileTree.Items.Count > 0) then
            FileTree.Selected := FileTree.Items.GetFirstNode;
          FileTree.SetFocus;
        end;
      end;
  end;
end;

procedure TForm1.MenuFilterFilesClick(Sender: TObject);
begin
  if FTreeFilter.CanFocus then
  begin
    FTreeFilter.SetFocus;
    FTreeFilter.SelectAll;
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
  { One selection among the trees. }
  FRepoTree.Selected := nil;
  FSubTree.Selected := nil;
  ShowChanges(Node.GetTextPath);
end;

{ The file under the mouse gets its StatHint after Application.HintPause.
  The tree's own hint is set only when the timer fires and cleared when
  the mouse moves to another row, since the LCL's hint does not follow a
  hint that changes within one control on Cocoa. }
procedure TForm1.FileTreeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
var
  Node: TTreeNode;
  Tip, Path: string;
  i: integer;
begin
  Tip := '';
  Node := FileTree.GetNodeAt(X, Y);
  if (Node <> nil) and (Node.Data <> nil) then
  begin
    Path := Node.GetTextPath;
    for i := 0 to High(FStats) do
      if FStats[i].Path = Path then
      begin
        Tip := StatHint(FStats[i]);
        Break;
      end;
  end;
  if Tip = '' then
    Node := nil;
  if (Node = FTreeHintNode) and (Tip = FTreeHint) then
    Exit;
  FileTreeMouseLeave(Sender);
  FTreeHintNode := Node;
  FTreeHint := Tip;
  FTreeHintTimer.Enabled := Tip <> '';
end;

procedure TForm1.FileTreeMouseLeave(Sender: TObject);
begin
  FTreeHintTimer.Enabled := False;
  if FileTree.Hint <> '' then
  begin
    Application.CancelHint;
    FileTree.Hint := '';
  end;
  FTreeHint := '';
  FTreeHintNode := nil;
end;

procedure TForm1.TreeHintTimerTimer(Sender: TObject);
begin
  FTreeHintTimer.Enabled := False;
  if FTreeHint = '' then
    Exit;
  FileTree.Hint := FTreeHint;
  Application.ActivateHint(Mouse.CursorPos);
end;

{$I umain.diffview.inc}
{$I umain.actions.inc}
{$I umain.gotodef.inc}
{$I umain.blame.inc}
{$I umain.discard.inc}
{$I umain.index.inc}
{$I umain.history.inc}
{$I umain.repofiles.inc}
{$I umain.submodules.inc}

end.
