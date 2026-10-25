unit umain;

{$mode objfpc}{$H+}

{ The form draws its own title bar on Windows and GTK 3 (gittan.owntitlebar). }
{$IF DEFINED(LCLWin32) OR DEFINED(LCLGtk3)}{$DEFINE OWNBAR}{$ENDIF}

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
  gittan.sidenav, gittan.repoinfo, gittan.repopage, gittan.subpage,
  gittan.repocommands, gittan.commandpage,
  gittan.settingsdlg, gittan.findbar, gittan.worddiff, gittan.symbols, gittan.symbolbar,
  {$IFDEF LCLCocoa}gittan.toolbar, gittan.memohint,{$ENDIF}
  {$IFDEF OWNBAR}gittan.owntitlebar,{$ENDIF}
  {$IFDEF LCLWin32}gittan.wintitlebar,{$ENDIF}
  {$IFDEF LCLGtk3}gittan.gtktitlebar,{$ENDIF}
  gittan.symbolindex, gittan.snapshots, gittan.blame, gittan.history,
  gittan.syntaxthemes, gittan.cli, gittan.update, gittan.symbolchanges, gittan.callers,
  gittan.popuplist, gittan.statusbar, gittan.repofiles, gittan.sectionheader, gittan.hintbox,
  gittan.discard, gittan.keep, gittan.leaveout, gittan.hoverpills, gittan.submodules, gittan.reviews, gittan.imagediff, gittan.graph,
  gittan.commitgraph, gittan.notice, gittan.banner, gittan.pofile, gittan.binaryview, gittan.commitjob, gittan.ai, gittan.remotejob, gittan.mdpreview,
  gittan.rebase, gittan.rebasedlg, gittan.cleandlg, gittan.patchdlg, gittan.filespage, gittan.pullpage, gittan.clonedlg,
  gittan.remotesdlg, gittan.submoduledlg, gittan.identitydlg, ATSynEdit_Gaps, md5;

type
  {** What the space right of the tree shows: the summary, one changed
    file, the raw repository diff, a plain file from File > Open, the
    history of a piece of code (Go > Code History), a submodule, a
    changed image, side by side (gittan.imagediff), a translation file
    with its originals beside its translations (umain.translations.inc),
    a binary file, changed or opened (gittan.binaryview), the Commands
    page, the Files page (gittan.filespage, umain.files.inc), a file of
    the commit it lists, read-only in the editor (or in the image or the
    binary view), or the Pull Requests page (gittan.pullpage,
    umain.pulls.inc). }
  TGittanView = (gvSummary, gvRepoInfo, gvChanges, gvRepoDiff, gvFile, gvHistory, gvSubmodule,
    gvImage, gvTranslation, gvBinary, gvCommands, gvFiles, gvBlob, gvPulls);

  {** The three strengths of a commit's color in the history view: the
    faint tint of its rows, the shade of the words it changed, and the
    swatch of its legend row, which is text and must read on the
    background. }
  THistoryTone = (htRow, htWord, htSwatch);

  {** What picking a branch from the branch list does: switch to it,
    merge it into the current branch, rebase the current branch onto it,
    show what it changed since it left the current branch, or what the
    current branch changed since it left it (umain.branches.inc). }
  TGittanBranchListMode = (blSwitch, blMerge, blRebase, blBranchSince, blCurrentSince);

  {** A bisect command RunBisect runs (umain.bisect.inc). }
  TBisectStep = (bsStart, bsMark, bsEnd);

  {** What a transport button of the status bar does: UpdateStatusTransport
    puts the steps there, StatusStepClick runs them. }
  TStatusStep = (stepNone, stepFetch, stepPull, stepPush, stepForcePush, stepContinue,
    stepCommit, stepAbort, stepSkip, stepResolve);

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

  {** The tree views of the form, the one from umain.lfm included, with a
    click on a node's check box (its state image) told apart: it goes to
    OnStateClick instead of selecting the row, so choosing files to
    commit does not show each one. }
  TTreeView = class(ComCtrls.TTreeView)
  private
    FOnStateClick: TTVExpandedEvent;
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    property OnStateClick: TTVExpandedEvent read FOnStateClick write FOnStateClick;
  end;

  {** The colors the self-painted controls share in one appearance
    (TForm1.Palette): the gutter's shade the bars and headers sit on,
    the text and its dim kind, the divider lines, the popup lists'
    background, hovered row and border, a raised part of a bar, the
    accent, the added, deleted and warning tones, the pills, and the
    note boxes of the Commit section (info, error, each with its border). }
  TGittanPalette = record
    Shade, Text, Dim, Line: TColor;
    Popup, Hover, Border, Raised: TColor;
    Accent, Added, Deleted, Warning: TColor;
    Pill, PillText: TColor;
    NoteInfo, NoteInfoLine, NoteError, NoteErrorLine: TColor;
  end;

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
    { The editor's font size when none was picked (DefaultFontSize for
      the screen the window opened on). }
    FDefaultFontSize: integer;
    { gh, GitHub's command line tool: the path the settings give, else
      the one FindTool gives (run it by that, PATH may not reach it), and
      whether there is one. The features that need GitHub are offered
      only when it is there: the menu items in FGitHubItems are shown
      then, hidden otherwise (UpdateGitHubItems). }
    FGitHubCli: string;
    FHasGitHubCli: boolean;
    FGitHubItems: array of TMenuItem;
    { The AI features (umain.ai.inc, gittan.ai), shown only once the
      settings turn them on and the agent's command is found: the agent
      the settings pick, its command and model, File > Write Commit
      Message (the Commit header's AI does the same), the job writing
      it, and the field's text when it started, which the message
      replaces only while it is unchanged. }
    FAgent: TGittanAgent;
    FAgentCli, FAgentModel: string;
    FMessageItem: TMenuItem;
    FMessageJob: TGittanMessageJob;
    FMessageFrom: string;
    { The AI review (umain.ai.inc): View > Review Changes with AI and
      Clear AI Review, the job while it runs, and its findings with the
      comparison they were made for (AIReviewKey), which the change view
      shows among the threads (FShown) while that comparison is shown. }
    FAIReviewItem, FAIClearItem: TMenuItem;
    FAIReviewJob: TGittanAIReviewJob;
    FAIThreads: TGittanReviewThreads;
    FAIThreadsKey: string;
    { The width of a tab in the editors, in characters. }
    FTabSize: integer;
    FSyntaxMenu, FAutoLexerItem, FPlainTextItem: TMenuItem;
    FRecentMenu, FCompareMenu, FTerminalItem, FUninstallCliItem: TMenuItem;
    FSnapshots: TGittanSnapshots;
    FWrapItem, FOnlyChangesItem, FSideItem, FIgnoreSpaceItem, FMdPreviewItem: TMenuItem;
    {** View > Folding, enabled where FoldingShown (see ViewMenuClick). }
    FFoldMenu: TMenuItem;
    {** The file lines the folded ranges started on before a rebuild of
      the text of FKeptFoldsPath (see KeepFolds). }
    FKeptFolds: TIntegerDynArray;
    FKeptFoldsPath: string;
    FContextItems: array of TMenuItem;
    {** The View > Syntax Theme items, in SyntaxThemes order. }
    FThemeItems: array of TMenuItem;
    {** The chosen syntax theme, an index into SyntaxThemes. }
    FSyntaxTheme: integer;
    FFilePopup, FStatusPopup, FEditPopup: TPopupMenu;
    FStatus: TGittanStatusBar;
    {** What the status bar's transport buttons do now. }
    FStatusSteps: array[spLeft..spRight] of TStatusStep;
    FRevealItem, FOpenItem: TMenuItem;
    { The file menu's conflict items (umain.conflicts.inc). }
    FResolveMineItem, FResolveTheirsItem, FMarkResolvedItem: TMenuItem;
    FContextPath: string;
    { Reverting (umain.revert.inc): the folder of the tree the file menu
      was opened on, '' for a file; the menu items; and per revert, its
      label with what RevertFiles saved (a TStringList), latest last. }
    FContextFolder: string;
    FRevertItem, FRevertFileItem, FUndoRevertItem: TMenuItem;
    FFileHistoryItem: TMenuItem;
    FRevertUndo: TStringList;
    { Rename or Move and Remove from Git in the file menu
      (umain.movefiles.inc). }
    FMoveItem, FRemoveItem: TMenuItem;
    { Clean (umain.clean.inc): the File menu's item and what the dialog
      deleted last (untracked, ignored or both), offered first again. }
    FCleanItem: TMenuItem;
    FCloneItem, FInitItem, FRemotesItem: TMenuItem;
    { Where the last clone went, and whether it brought the submodules:
      what the clone dialog starts with. }
    FCloneParent: string;
    FCloneSubmodules: boolean;
    FCleanKind: TGittanCleanKind;
    { Patches (umain.patches.inc): the File menu's Apply Patches...,
      where the last series went and whether it had a cover letter,
      where the last patch applied was picked from and whether patches
      were committed or went into the work tree alone. }
    FApplyPatchesItem: TMenuItem;
    FPatchFolder, FApplyFolder: string;
    FPatchCover, FApplyCommit: boolean;
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
    { The local branches the job found tracking a branch deleted on
      the remote, which the branch list marks and the summary says for
      the current one. }
    FGoneBranches: TStringList;
    FPulls: TGittanPullRequests;
    { The open pull requests waiting for the user's review, which the
      summary lists and the Pull Requests page marks. }
    FReviewPulls: TGittanPullRequests;
    FPullError, FPullKey: string;
    FPullMenu, FOpenPullItem, FCopyPullItem: TMenuItem;
    FPullRange: string;
    FPullNumber: integer;
    { A newer Gittan (umain.update.inc): the check under way, the timer
      that starts the next, whether the menu asked for the one under way,
      and the latest release, FHasUpdate when it is newer than this
      build. }
    FUpdateJob: TGittanUpdateJob;
    FUpdateTimer: TTimer;
    FUpdateManual, FHasUpdate: boolean;
    FUpdateRelease: TGittanRelease;
    { The tree sits in a panel under a filter field (Go > Filter Files):
      FillFileTree keeps only the files whose path holds FTreeFilterText,
      the field's text in lower case. }
    FTreePanel: TPanel;
    FTreeFilter: TEdit;
    FTreeFilterText: string;
    { Whether git reported no change, for the check FileTreeAdvancedCustomDraw
      paints in the empty tree; a filter that hides every file does not
      count. }
    FTreeClean: boolean;
    {$IFDEF LCLCocoa}
    { The window's toolbar on macOS 11 and later (SetupTitleBar): the
      name, the filter as a native search field in place of FTreeFilter,
      and the header's navigator and pills. nil before macOS 11. }
    FToolbar: TGittanToolbar;
    {$ENDIF}
    {$IFDEF OWNBAR}
    { The window's own title bar on Windows and GTK 3 (SetupTitleBar): the
      name, the menus, the filter field, the header's navigator and pills
      and the caption buttons, in the strip the window system's title bar
      had. A TGittanWinTitleBar or a TGittanGtkTitleBar. }
    FOwnBar: TGittanOwnTitleBar;
    {$ENDIF}
    { The height of the strip the title bar covers on macOS, where the
      content reaches under it (SetupTitleBar); 0 elsewhere. }
    FTitleBarHeight: integer;
    { The track and the fill of the indexing's band over the title bar
      (ShowTitleBand, or FOwnBar.SetBand on Windows and GTK 3, from UpdateIndexBand), set by ApplyTheme. }
    FBandTrack, FBandFill: TColor;
    { The Config section at the bottom of the tree panel
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
      the path of the submodule the view shows. FSubChanges holds, one
      per submodule, how a changed one moved between the sides compared
      (FromHash empty and ToHash empty for one git status leaves out). }
    { The Commit section under the tree (umain.commit.inc): the check
      boxes of the tree (FCheckImages), the files flipped from what is
      chosen by default, the section's controls, the commit job while it
      runs, the repository the message was written in, and the message
      Amend took from HEAD. }
    FCheckImages: TImageList;
    FCommitOn, FCommitOff: TStringList;
    FCommitPanel, FCommitBox, FCommitRow: TPanel;
    FCommitHeader: TGittanSectionHeader;
    FCommitMemo: TMemo;
    FCommitAmend: TCheckBox;
    FCommitButton: TButton;
    { The length of the message's first line, by the Commit button, once
      it is past SubjectSoftLimit; in the warning color past
      SubjectHardLimit. }
    FSubjectCount: TLabel;
    { How many changed files are chosen and how many could be (not the
      conflicts), as UpdateCommitState last counted them. }
    FChosenCount, FChoosableCount: integer;
    { Tick All Files and Untick All Files in the file menu, over the
      tree while it chooses what to commit. }
    FTickSepItem, FTickAllItem, FUntickAllItem: TMenuItem;
    FCommitNote: TGittanHintBox;
    FCommitItem: TMenuItem;
    FCommitJob: TGittanCommitJob;
    { The commits still running in a repository no longer open, for
      their draft (DroppedCommitDone). }
    FDroppedCommits: TList;
    FCommitDraftFor, FAmendMessage: string;
    { FocusTreeAsync ran before the window was shown; FormActivate tries
      again. }
    FFocusTreePending: boolean;
    { Abort and Skip for what git is in the middle of, and the merge
      message filled into the field (umain.conflicts.inc). }
    FAbortButton, FSkipButton: TButton;
    { Where the bisect stands, and its box over the message
      (umain.bisect.inc). }
    FBisect: TGittanBisect;
    FBisectBox, FBisectRow, FBisectEndRow: TPanel;
    FBisectNote: TGittanHintBox;
    FBisectGood, FBisectBad, FBisectSkip, FBisectShow, FBisectEnd: TButton;
    { The commit graph's menu (umain.commitactions.inc), built for the
      commit it is shown for, with that commit and the name it goes by. }
    FCommitPopup: TPopupMenu;
    FActionCommit: TGittanGraphCommit;
    FActionName: string;
    { The commit marked in the commit graph for a comparison, and the
      name it goes by (see umain.commitactions.inc). }
    FMarkHash, FMarkName: string;
    FMarkDate: TDateTime;
    FMergeMessage: string;
    { Fetch, pull and push (umain.remote.inc): the job while it runs,
      the commits ahead and HEAD when it started, the menu items, and
      the list the status bar's counts drop up. }
    FRemoteJob: TGittanRemoteJob;
    FRemoteAhead: integer;
    FRemoteHead: string;
    FFetchItem, FPullItem, FPushItem, FForcePushItem: TMenuItem;
    FSyncPopup: TGittanPopupList;
    FRecentPopup: TGittanPopupList;
    { The actions of a base that is a branch compared through the merge
      base with the current one (umain.branches.inc): the list dropped
      from the base label in the summary and the status bar, and the
      branch it is for. }
    FBasePopup: TGittanPopupList;
    FBaseActionRef: string;
    FBaseMergeIndex, FBaseRebaseIndex: integer;
    { The base popup's items while a commit is shown (see BlameShown):
      back to the working tree and copy its id; -1 otherwise. }
    FBaseBackIndex, FBaseCopyIndex: integer;
    FSubPanel: TPanel;
    FSubHeader: TGittanSectionHeader;
    FSubTree: TTreeView;
    FSubmodules: TGittanSubmodules;
    FSubInfos: array of TGittanSubmoduleInfo;
    FSubChanges: array of TGittanSubmoduleChange;
    FSubJobs: TList;
    FSubKey, FSubShown: string;
    { Asks the remotes again SubmodulePoll ms after the last job of a
      round finished; off while no repository is open. }
    FSubTimer: TTimer;
    { The submodules' actions: File > Submodules, the section's menu with
      the items it enables, and the index of the shown submodule's
      Update pill in the header (-1 when it has none). }
    FSubUpdateAllItem, FSubSyncAllItem, FSubAddItem: TMenuItem;
    FSubPopup: TPopupMenu;
    FSubUpdateItem, FSubSyncItem, FSubOpenItem: TMenuItem;
    FSubUpdatePill: integer;
    { Editing the repository's own files (umain.repofiles.inc): the full
      name of the file the editor holds open to edits, '' while it shows
      something else; the file's time stamp when it was loaded or saved,
      so a change on disk behind an edit is noticed; the exclude file of
      the open repository, found once when it is opened; and File > Save. }
    FEditPath, FExcludePath: string;
    FEditStamp: LongInt;
    FSaveItem: TMenuItem;
    { Discarding a block of changes (umain.discard.inc): the block the
      mouse is on and the row it is on (-1 for none; for a conflicted
      file the conflict whose button it is on), the timer that shows the
      pills at the row's end after a pause and the pills; the blocks
      discarded, latest last, which File > Undo Discard puts back; and
      the two menu items. }
    FHotDiscard, FHotRow: integer;
    FPillTimer: TTimer;
    FDiscardPills: TGittanHoverPills;
    { Keeping changes as code for the session (gittan.keep): the keeps
      of every file, the diff as git gave it for the shown file (the
      keeps are applied to a copy, FChangeLines), for each of its lines
      the keep it comes from or -1, the keep the mouse is on (-1 for
      none), and the index of the header's Unkeep pill (-1 for none). }
    FKeeps: TGittanKeeps;
    FRawChangeLines: TStringList;
    FKeptOf: TIntegerDynArray;
    FHotKeep: integer;
    FHeaderUnkeep: integer;
    { Leaving changes out of the commit (umain.leaveout.inc): the
      changes left out of every file, for each line of FChangeLines the
      one it is or -1, the index of the header's Include All pill (-1
      for none), and whether the pills shown have Leave Out or Include. }
    FLeftOut: TGittanKeeps;
    FLeftOutOf: TIntegerDynArray;
    FHeaderInclude: integer;
    FPillChoose: boolean;
    FDiscards: array of TGittanDiscard;
    FDiscardItem, FUndoDiscardItem, FLeaveOutItem: TMenuItem;
    { Resolving one conflict at a time (umain.conflicts.inc): the diff
      line of each conflict's "<<<<<<<" (set by ShowChanges with the
      roles) and its row in the view (found with the block rows), which
      take the discard band's buttons for a conflicted file; the list
      the button drops down (the sides to take) or the conflict badge
      drops down (the conflicted files), what it holds, and the conflict
      a pick resolves; and the File and editor menu items. }
    FConflictStarts, FConflictEnds, FConflictRows, FConflictEndRows: TIntegerDynArray;
    FConflictPopup: TGittanPopupList;
    FConflictPopupFiles: boolean;
    FConflictPaths: TStringArray;
    FConflictPicks: array of TGittanConflictPick;
    FResolveIndex: integer;
    FResolveItem, FResolveEditItem: TMenuItem;
    { The default branch of the remote (origin/main) and the merge base
      of the branch with it, Compare With's "origin/main (Merge Base)";
      and the branch's lead on and lag behind its upstream, for the
      status bar. All read by LoadRepository. }
    FDefaultBranch, FMergeBase: string;
    FHasUpstream: boolean;
    FAhead, FBehind: integer;
    { The branch was rewritten since it was pushed (the snapshot's
      Rewritten): Force Push is the next step, not Pull. }
    FRewritten: boolean;
    { A branch without an upstream: its commits on no remote, -1 without
      a remote (the snapshot's NotOnRemote). }
    FNotOnRemote: integer;
    { Rebase or Merge in the summary's row of a branch behind the default
      branch fetches first: the ref to rebase onto (FAfterFetchRebase) or
      merge once the fetch is done, and the branch it is for; '' while
      none waits. }
    FAfterFetchRef, FAfterFetchBranch: string;
    FAfterFetchRebase: boolean;
    { What git is in the middle of ("merging", "rebasing", ...) and how
      many files have conflicts, read by LoadRepository; and the role of
      each line of FChangeLines in a conflict (see gittan.conflicts),
      set by ShowChanges for a conflicted file, nil otherwise. }
    FOperation: string;
    {** The branch the rebase in progress is of (head-name), '' for none
      or a rebase of a detached HEAD. }
    FRebaseBranch: string;
    FConflictFiles: integer;
    FConflictRoles: TIntegerDynArray;
    FContextFromSummary: boolean;
    FHeader: TGittanFileHeader;
    FNav: TGittanChangeNav;
    FNavUpdateQueued: boolean;
    FFindBar: TGittanFindBar;
    { The last match Find selected is in the old side of Side by Side. }
    FFindInOld: boolean;
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
    { A file is being loaded into FIndexEdit, which pumps messages for a
      large one (IndexNext). }
    FIndexLoading: boolean;
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
    { The rows at the top of the sidebar, the page about the repository
      and the job that reads its facts; see umain.repopage.inc. }
    FSideNav: TGittanSideNav;
    { The sidebar row of the view shown, which the Graph row stands in
      for while the commit graph is open. }
    FNavViewRow: integer;
    FRepoPage: TGittanRepoPage;
    { The Commands page, in the box too, the repository's commands
      shown on it, the hash of its commands file and the command
      running (umain.commands.inc). }
    FCommandPage: TGittanCommandPage;
    FRepoCommands: TGittanRepoCommands;
    FCommandsHash: string;
    FCommandJob: TGittanCommandJob;
    FCommandName: string;
    FCommandRead: integer;
    { The Files page, in the box too (umain.files.inc): whether it
      follows HEAD (else it shows the commit Browse Files... picked),
      and the file of its commit shown in the editor: its path, its
      commit and what the page calls it. }
    FFilesPage: TGittanFilesPage;
    FFilesHead: boolean;
    FBlobPath, FBlobCommit, FBlobName: string;
    { The Pull Requests page, in the box too, and its View menu item,
      both there only with gh (umain.pulls.inc). }
    FPullPage: TGittanPullPage;
    FPullsItem: TMenuItem;
    { The page of a submodule, in the box too (umain.submodules.inc). }
    FSubPage: TGittanSubPage;
    FRepoInfoJob: TGittanRepoInfoJob;
    FRepoInfoAgain: boolean;
    { The list that drops down from the branch in the summary, with the
      branch to switch to for each of its items ('' for a header). }
    FBranchPopup: TGittanPopupList;
    FBranchNames: TStringList;
    { Branch management (umain.branches.inc): per row of the branch list
      the remote-tracking branch of a remote row, the branches Delete
      Gone Branches deletes, the menu of a branch and the branch it is
      for (its name, its ref, and the remote branch it deletes). }
    FBranchRefs, FGoneToDelete: TStringList;
    FBranchMenu: TPopupMenu;
    FMenuBranch, FMenuBranchRef, FMenuBranchUpstream: string;
    { What the branch list drops down for, and the Branch menu's items,
      whose captions name the current branch. }
    FBranchListMode: TGittanBranchListMode;
    FSwitchItem, FNewBranchItem, FMergeItem, FRebaseItem, FCompareBranchItem,
      FCompareBackItem, FUpstreamItem: TMenuItem;
    { The upstream list (umain.branches.inc), the branch it is for, and
      per row what a pick does: '' nothing, '+' and a remote to push
      there, '-' to stop tracking, '=' and a remote-tracking branch to
      track it. }
    FUpstreamPopup: TGittanPopupList;
    FUpstreamRows: TStringList;
    FUpstreamBranch: string;
    { Tags (umain.tags.inc): what the list read when it opened, the list
      with, as each row's tag, the index in FTags of its tag (TagRowNew
      for the New row), the menu of a tag and the one it is
      for, the remote pushes and deletions go to, and the Branch menu's
      items. }
    FTags: TGittanTags;
    FTagPopup: TGittanPopupList;
    { The file header's View chip drops this: the view's modes and the
      history of the file, as the menu items they stand for
      (FViewItems), each at its row (FViewRows). }
    FViewPopup: TGittanPopupList;
    FViewItems: array of TMenuItem;
    FViewRows: array of integer;
    FCodeHistoryItem, FGoFileHistoryItem: TMenuItem;
    { The submodules, dropped from the Repository page's tile when there
      is more than one; a pick shows that one's page. }
    FSubListPopup: TGittanPopupList;
    { The popup's index of each submodule's row, in FSubmodules' order. }
    FSubListRows: array of integer;
    FTagMenu: TPopupMenu;
    FMenuTag: TGittanTag;
    FTagRemote: string;
    FTagsItem, FNewTagItem, FPushTagsItem: TMenuItem;
    { The reflog (umain.reflog.inc): HEAD's reflog as the list read it
      when it opened, the list with, as each row's tag, the index in
      FReflog of its line, the menu of a line and
      the line it is for, and the Branch menu's item. }
    FReflog: TGittanReflog;
    FReflogPopup: TGittanPopupList;
    FReflogMenu: TPopupMenu;
    FMenuReflog: TGittanReflogEntry;
    FReflogItem: TMenuItem;
    { Stashes (umain.stash.inc): what the last snapshot listed, the list
      that drops from the status bar's stash chip with the stashes it
      shows (FListedStashes, a copy, since a snapshot replaces FStashes
      while the list is up) and, as each row's tag, the index in them of
      its stash (StashRowNew for the New row), the menu of a stash and the one it is for, the range
      a compared stash is the base as and the stash it is of, the stash
      the base chip's list is for with its rows, and the Stash menu's
      items. }
    FStashes: TGittanStashes;
    FStashPopup: TGittanPopupList;
    FListedStashes: TGittanStashes;
    FStashMenu: TPopupMenu;
    FMenuStash: TGittanStash;
    FStashRange, FStashRangeId, FBaseStashId: string;
    FBaseApplyIndex, FBasePopIndex, FBaseDropIndex: integer;
    FStashAllItem, FStashChosenItem, FPopStashItem, FApplyStashItem,
      FStashListItem: TMenuItem;
    { The commit graph, in the middle of the form, from the status bar's
      ahead/behind counts or View > Commit Graph. }
    FGraph: TGittanCommitGraph;
    { The notice over the form while a fetch, pull or push runs: at once
      when a pre-push hook has to run first, else after NoticeDelay; and
      what a failed one or a failed commit said. }
    FNotice: TGittanNotice;
    FNoticeTimer: TTimer;
    FNoticeHook: boolean;
    { The notice tells of a failed commit: its first button commits
      again. }
    FNoticeCommit: boolean;
    { The banner over the file header and the summary: what failed, until
      it is closed (BannerError). }
    FBanner: TGittanBanner;
    { What a failure notice's first button runs again. }
    FRetryKind: TGittanRemoteKind;
    FRetryMode: TGittanPullMode;
    FRetryArg, FRetryRemote: string;
    { A clone's folder and submodules, for Clone Again; a submodule's
      path and branch, for Try Again after an add. }
    FRetryRoot, FRetryPath, FRetryBranch: string;
    FRetrySubmodules: boolean;
    { The list a click on the status bar's pull request drops down, and
      what each of its rows does (the pa* constants). }
    FPullPopup: TGittanPopupList;
    FPullActions: TIntegerDynArray;
    FEditOld: TATSynEdit;
    { The hidden editor that parses another changed file for Go to
      Definition, with its adapter; made on the first lookup. }
    FScratch: TATSynEdit;
    { A lookup runs in the scratch editor, or the hover's lookup runs:
      both wait for parses with the message loop running, and must not
      start again inside themselves. }
    FScratchBusy, FHoverBusy: boolean;
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
    { How many callers are inside a stretch the watcher's refresh must
      not run under (a modal question, a wait that pumps messages, a
      refresh), and whether one came meanwhile (HoldRefresh). }
    FRefreshHold: integer;
    FRefreshPending, FRefreshQueued: boolean;
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
    { The commit FBlameRange shows and the rest of its message, for the
      summary's card (see ShowBlameCommit). }
    FBlameCommit: TGittanCommitLine;
    FBlameBody: string;
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
    { The name the changes not committed yet are made under, for their
      initial (see DrawInitials). }
    FHistoryUser: string;
    { The change view of an image, in the editor's place (see
      ShowImageChanges). }
    FImageDiff: TGittanImageDiff;
    { A binary file, in the editor's place (see ShowBinaryChanges). }
    FBinaryView: TGittanBinaryView;
    { View > Markdown Preview (see umain.mdpreview.inc): whether it is on,
      the page right of the editor, its splitter, its share of the width
      and the pause after an edit before the page follows. }
    FMdPreviewOn: boolean;
    FMdPreview: TGittanMarkdownPreview;
    FMdSplitter: TSplitter;
    FMdRatio: double;
    FMdTimer: TTimer;
    { View > Translations (see umain.translations.inc): whether it is on,
      its menu item, the file shown from disk ('' for a changed file) and
      the counts the header shows. }
    FTranslations: boolean;
    FTranslationsItem: TMenuItem;
    FTranslationFile, FPoStats: string;
    { The first row of each entry the navigator steps through. }
    FPoBlocks: TIntegerDynArray;
    { View > Review Comments (see umain.reviews.inc): whether it is on,
      its menu item, the job that fetches the threads, the threads of the
      pull request FThreadsNumber of FThreadsRepo with its head commit,
      what they hold (FThreadsKey) and gh's message when the last fetch
      failed; the diff line of each thread in the shown file
      (FThreadRows), the diff from the head to the work tree the lines
      are mapped through (for FMapDiffKey, head and path), the threads
      folded or unfolded against their default, the width the cards of
      each editor were laid out for and a canvas to measure text on. }
    FShowComments: boolean;
    FReviewItem: TMenuItem;
    FReviewJob: TGittanReviewJob;
    FThreads: TGittanReviewThreads;
    { The threads the change view shows: the pull request's while they
      apply, then the AI review's (CollectShownThreads). FThreadRows and
      the gaps' Tags index it. }
    FShown: TGittanReviewThreads;
    FThreadsNumber: integer;
    FThreadsRepo, FThreadsHead, FThreadsKey, FReviewError: string;
    FThreadRows: TIntegerDynArray;
    FMapDiff, FMapDiffKey: string;
    FThreadFlips: TStringList;
    FReviewWidths: array[0..1] of integer;
    FReviewMeasure: TBitmap;
    { The thread a click on its card folds when the button comes up. }
    FGapToggle: string;
    function Palette: TGittanPalette;
    procedure ApplyTheme;
    procedure ApplyEditorColors(AEd: TATSynEdit);
    procedure SetupEditor(AEd: TATSynEdit);
    function AdapterOf(AEd: TATSynEdit): TATAdapterEControl;
    procedure MenuRefreshClick(Sender: TObject);
    procedure WatcherChange(Sender: TObject);
    procedure HoldRefresh;
    procedure ReleaseRefresh;
    procedure RefreshPendingAsync(Data: PtrInt);
    procedure StartWatcher;
    procedure StopWatcher;
    function LoadRepository: boolean;
    procedure ApplySnapshot(const ASnap: TGittanRepoSnapshot);
    procedure RefreshRepository(ASnap: PGittanRepoSnapshot = nil);
    procedure RefreshRepositoryHeld(ASnap: PGittanRepoSnapshot);
    procedure ShowError(const AMessage: string);
    procedure ShowWelcome(const AError: string);
    procedure WelcomeOpen(Sender: TObject);
    procedure WelcomeOpenRecent(Sender: TObject; const ARoot: string);
    procedure WelcomeClone(Sender: TObject);
    procedure WelcomeInit(Sender: TObject);
    function SelectedPath: string;
    function StatIcon(const AStat: TGittanFileStat): integer;
    function StatHint(const AStat: TGittanFileStat): string;
    procedure UpdateStatus;
    procedure UpdateStatusTransport;
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
    procedure LeaveEditorViews;
    procedure SetupSideNav;
    procedure SideNavPick(Sender: TObject; AIndex: integer);
    procedure SetNavRow(ARow: integer);
    procedure GraphClosed(Sender: TObject);
    procedure ShowRecentList(const AAnchor: TRect);
    procedure RecentPopupPick(Sender: TObject; AIndex: integer);
    procedure MenuRepoInfoClick(Sender: TObject);
    procedure RepoPageOpenTarget(Sender: TObject; ATarget: TGittanRepoTarget;
      const AName: string; const AScreenRect: TRect);
    procedure SubListPopupPick(Sender: TObject; AIndex: integer);
    procedure ShowRepoInfo;
    procedure StartRepoInfoJob;
    procedure AbandonRepoInfoJob;
    procedure RepoInfoJobDone(Sender: TObject);
    procedure HideBoxPages;
    procedure SetupPullPage;
    procedure MenuPullsClick(Sender: TObject);
    procedure ShowPulls;
    procedure UpdatePullPage;
    procedure PullPageCompare(Sender: TObject; const APull: TGittanPullRequest);
    procedure SummarySelectPull(Sender: TObject; const APull: TGittanPullRequest);
    procedure PullPageWorkingTree(Sender: TObject);
    procedure PullPageRefresh(Sender: TObject);
    procedure SetupFilesPage;
    procedure MenuFilesClick(Sender: TObject);
    procedure ShowFiles;
    procedure ShowFilesAt(const AHash, AName, ASubject: string);
    procedure RefreshFilesPage;
    function FilesPageRead(Sender: TObject; const AFolder: string;
      out AList: TGittanTreeEntries; out AError: string): boolean;
    procedure FilesPageOpen(Sender: TObject; const AEntry: TGittanTreeEntry);
    procedure FilesPageFolderChange(Sender: TObject);
    procedure ShowBlob(const APath: string);
    function BlobData(out AData: RawByteString): boolean;
    procedure OpenBlobOutside;
    procedure SaveBlobAs;
    procedure SetupCommandPage;
    function CommandsTrusted: boolean;
    procedure LoadRepoCommands;
    procedure MenuCommandsClick(Sender: TObject);
    procedure ShowCommands;
    procedure CommandPageRun(Sender: TObject; AIndex: integer);
    procedure RunRepoCommand(AIndex: integer; AByKey: boolean);
    procedure CommandJobOutput(Sender: TObject);
    procedure CommandJobDone(Sender: TObject);
    procedure AbandonCommandJob(AWait: boolean);
    procedure CommandPageStop(Sender: TObject);
    procedure CommandPageTrust(Sender: TObject);
    procedure CommandPageEditFile(Sender: TObject);
    procedure CommandPageCopyOutput(Sender: TObject);
    function CommandKey(AKey: word; AShift: TShiftState): boolean;
    procedure OpenTerminal(const ACommand: string);
    procedure ShowEditor;
    procedure ShowImageChanges(const APath: string);
    procedure ShowBinaryChanges(const APath: string);
    procedure ShowBinaryFile(const AFileName: string);
    function SidesShown: boolean;
    function ShowsChangedFile: boolean;
    procedure ShowTranslation(const AText, AOld: string; ACompare: boolean);
    procedure ShowTranslationChanges(const APath: string);
    procedure ShowTranslationFile(const AFileName: string);
    procedure MenuTranslationsClick(Sender: TObject);
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
    function HistoryColor(AIndex: integer; ATone: THistoryTone): TColor;
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
    procedure ShowChangeAt(ARow: integer);
    procedure GoToFirstChange;
    function ShowChanges(const APath: string): boolean;
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
    function SidesWidth: integer;
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
    function LineAtRow(ARow: integer): integer;
    function BlockAtRow(ARow: integer): integer;
    function DiscardAt(AEd: TATSynEdit; X, Y: integer; out ARow: integer;
      out AKeep: integer): integer;
    procedure SetDiscardBand(AEd: TATSynEdit);
    procedure DrawDiscard(AEd: TATSynEdit; C: TCanvas);
    procedure SetHotDiscard(AEd: TATSynEdit; ABlock, AKeep, ARow: integer);
    procedure KeepBlockAt(ABlock: integer);
    procedure UnkeepAt(AKeep: integer);
    procedure UnkeepFile;
    procedure RebuildKeeps;
    procedure SetChangeActions;
    procedure PillTimerTimer(Sender: TObject);
    procedure ShowDiscardPills;
    function MouseOnDiscardPills: boolean;
    function MouseOnDiscardRows: boolean;
    procedure DiscardPillsPick(Sender: TObject; AIndex: integer);
    procedure DiscardPillsLeave(Sender: TObject);
    procedure DiscardThis(const ABlock: TGittanDiscard);
    { umain.leaveout.inc }
    function CanLeaveOut: boolean;
    function StatIndexOf(const APath: string): integer;
    function ShownFileChosen: boolean;
    procedure ApplyLeftOut;
    function LineLeftOut(ALine: integer): boolean;
    function BlockLeftOut(ABlock: integer): boolean;
    function LeaveOutCaption(ABlock: integer): string;
    function LeaveOutHint(ABlock: integer): string;
    procedure ToggleLeaveOutAt(ABlock: integer);
    procedure LeaveOutBlockAt(ABlock: integer);
    procedure IncludeBlockAt(ABlock: integer);
    procedure IncludeFile;
    procedure IncludeKept(const APairs: TGittanKeepArray);
    procedure LeftOutChanged;
    procedure DropLeftOut(const APath: string);
    function CommitParts(APaths: TStrings; out AParts: TGittanCommitParts;
      out AError: string): boolean;
    procedure MenuLeaveOutClick(Sender: TObject);
    procedure UpdateLeaveOutItem;
    procedure DiscardBlockAt(ABlock: integer);
    procedure UpdateDiscardItems;
    procedure FileMenuClick(Sender: TObject);
    procedure MenuDiscardClick(Sender: TObject);
    procedure MenuUndoDiscardClick(Sender: TObject);
    function DiscardBackText(const ABlock: TGittanDiscard): string;
    function DiscardBaseName: string;
    { umain.reviews.inc }
    procedure MenuReviewCommentsClick(Sender: TObject);
    function ReviewTarget(out ANumber: integer; out ARepoPath: string): boolean;
    function ReviewExact: boolean;
    procedure ClearReviews;
    procedure StartReviewJob(AForce: boolean);
    procedure AbandonReviewJob;
    procedure ReviewJobDone(Sender: TObject);
    procedure PlaceThreads;
    function PullThreadsShown: boolean;
    procedure CollectShownThreads;
    function ThreadAuthor(AThread, AComment: integer): string;
    function AgentColor: TColor;
    function ThreadId(AThread: integer): string;
    function ThreadOpen(AThread: integer): boolean;
    procedure ReviewFont(C: TCanvas; AKind: integer);
    function ReviewLineHeight(AKind: integer): integer;
    procedure ReviewLayout(AThread, AInner: integer; ALines: TStrings);
    function ReviewCardHeight(AThread, AWidth: integer): integer;
    function ReviewGapWidth(AEd: TATSynEdit): integer;
    procedure ApplyReviewGaps;
    procedure ReviewRelayoutAsync(Data: PtrInt);
    procedure RevealTopGapAsync(Data: PtrInt);
    procedure MatchScrollPixels(ASrc, ADst: TATSynEdit);
    procedure DrawGapGutter(AEd: TATSynEdit; C: TCanvas);
    procedure EditDrawGap(Sender: TObject; C: TCanvas; const ARect: TRect;
      AGap: TATGapItem);
    procedure EditClickGap(Sender: TObject; AGapItem: TATGapItem; APos: TPoint);
    procedure ToggleThreadNow;
    function ReviewHint(ANumber: integer): string;
    procedure FileThreads(const APath: string; out AOpen, AAll: integer);
    function FileThreadsHint(const APath: string): string;
    procedure FileTreeAdvancedCustomDrawItem(Sender: TCustomTreeView;
      Node: TTreeNode; State: TCustomDrawState; Stage: TCustomDrawStage;
      var PaintImages, DefaultDraw: boolean);
    procedure FileTreeAdvancedCustomDraw(Sender: TCustomTreeView;
      const ARect: TRect; Stage: TCustomDrawStage; var DefaultDraw: boolean);
    { umain.history.inc }
    procedure MenuHistoryClick(Sender: TObject);
    procedure MenuGoFileHistoryClick(Sender: TObject);
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
    procedure SetInitialBand(AEd: TATSynEdit);
    procedure DrawInitials(AEd: TATSynEdit; C: TCanvas);
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
    procedure OpenSettings(APage: TSettingsPage);
    procedure MenuSettingsClick(Sender: TObject);
    procedure MenuAboutClick(Sender: TObject);
    procedure CheckGitVersion;
    procedure PreviewSettings(AFont: TFont; ATheme, ATabSize: integer);
    procedure ApplyEditorFont(AFont: TFont);
    procedure EditorMetricsChanged;
    procedure ApplyTabSize(ASize: integer);
    procedure FindGitHubCli;
    procedure UpdateGitHubItems;
    procedure FindAgentCli;
    {** Whether the AI features are on and the agent's command is there. }
    function AIAvailable: boolean;
    {** Shows AI in the Commit header and File > Write Commit Message
      when AIAvailable, enabled as the commit section allows; from
      UpdateCommitState. }
    procedure UpdateMessageAction;
    procedure MessageActionClick(Sender: TObject);
    procedure StartMessageJob;
    procedure MessageJobDone(Sender: TObject);
    {** Stops a message being written: the agent is ended and its answer
      thrown away. }
    procedure AbandonMessageJob;
    {** What the change view compares, for the AI review's findings: the
      repository, the base and whether the whole tree is compared. }
    function AIReviewKey: string;
    procedure UpdateAIReviewItems;
    procedure MenuAIReviewClick(Sender: TObject);
    procedure MenuAIClearClick(Sender: TObject);
    procedure StartAIReview;
    procedure AIReviewDone(Sender: TObject);
    procedure AbandonAIReview;
    procedure MenuWrapClick(Sender: TObject);
    procedure MenuFoldClick(Sender: TObject);
    procedure ViewMenuClick(Sender: TObject);
    function FoldingShown: boolean;
    procedure SetFoldBand(AEd: TATSynEdit; AVisible: boolean);
    function FoldAction: TATEditorActionIfFolded;
    function FileLineOfRow(ARow: integer): integer;
    function RepoBusy: boolean;
    function RepoReady: boolean;
    function FoldPath: string;
    procedure KeepFolds;
    procedure RestoreFolds;
    procedure MenuOnlyChangesClick(Sender: TObject);
    procedure MenuContextLinesClick(Sender: TObject);
    procedure MenuSyntaxThemeClick(Sender: TObject);
    procedure SetSyntaxTheme(ATheme: integer);
    procedure MenuSideBySideClick(Sender: TObject);
    procedure MenuMarkdownPreviewClick(Sender: TObject);
    function MarkdownPreviewPath: string;
    procedure UpdateMarkdownPreview;
    procedure HideMarkdownPreview;
    function PreviewTogglePath: string;
    procedure UpdatePreviewToggle;
    procedure HeaderToggle(Sender: TObject);
    procedure HeaderMenu(Sender: TObject; const AScreenRect: TRect);
    procedure ViewPopupPick(Sender: TObject; AIndex: integer);
    procedure MdSplitterMoved(Sender: TObject);
    procedure MdTimerTimer(Sender: TObject);
    procedure EditChange(Sender: TObject);
    procedure MdPreviewOpenFile(Sender: TObject; const AFileName: string);
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
    procedure HoverLookup(Ed: TATSynEdit; const Word: string);
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
    procedure SummaryOpenUrl(Sender: TObject; const AUrl: string);
    procedure SummarySelectCommit(Sender: TObject; const AHash: string);
    procedure BranchPopupPick(Sender: TObject; AIndex: integer);
    procedure ShowCommitGraph(const AFilter: string = '');
    procedure GraphMore(Sender: TObject);
    procedure GraphPathCommits(Sender: TObject; const APath: string; AHashes: TStrings);
    procedure MenuCommitGraphClick(Sender: TObject);
    procedure GraphPick(Sender: TObject; const AHash: string);
    procedure PullChipClick(const AScreenRect: TRect);
    procedure PullPopupPick(Sender: TObject; AIndex: integer);
    procedure ComparePull(const APull: TGittanPullRequest);
    procedure StartPullFetch(ANumber: integer; const ARemote, ABaseRef: string);
    procedure PullFetchDone(AJob: TGittanRemoteJob);
    procedure SwitchBranch(const ABranch: string; ADetach: boolean = False);
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
    procedure SetupTitleBar;
    procedure ColorSidebar;
    procedure UpdateIndexBand;
    procedure SetupRepoFiles;
    procedure ColorRepoHeader;
    procedure FillRepoFiles;
    procedure LayoutRepoFiles;
    procedure RepoHeaderToggle(Sender: TObject);
    procedure TreePanelResize(Sender: TObject);
    procedure RepoTreeSelectionChanged(Sender: TObject);
    procedure SetupSubmodules;
    procedure SetupCommit;
    procedure FocusTreeAsync(Data: PtrInt);
    procedure FormActivate(Sender: TObject);
    procedure CommitHintAsync(Data: PtrInt);
    procedure CommitHeaderCheck(Sender: TObject);
    procedure SetAllChosen(AValue: boolean);
    procedure MenuTickAllClick(Sender: TObject);
    procedure MenuUntickAllClick(Sender: TObject);
    procedure UpdateSubjectCount;
    procedure CommitPushClick(Sender: TObject);
    procedure ColorCommit;
    procedure CommitHeaderToggle(Sender: TObject);
    function CommitChoosing: boolean;
    function CommitChosen(AIndex: integer): boolean;
    procedure SetCommitChosen(AIndex: integer; AValue: boolean);
    function CommitStatOf(ANode: TTreeNode): integer;
    procedure ApplyCommitChecks;
    procedure FlipCommitNode(ANode: TTreeNode);
    procedure FileTreeStateClick(Sender: TObject; Node: TTreeNode);
    procedure FileTreeKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure ChosenCommitPaths(AList: TStrings);
    procedure UpdateCommitState;
    procedure CommitMemoChange(Sender: TObject);
    procedure CommitMemoKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure CommitAmendClick(Sender: TObject);
    procedure CommitButtonClick(Sender: TObject);
    procedure MenuCommitClick(Sender: TObject);
    {** Asks for the name and e-mail to commit under, the global ones
      or the repository's own; False when cancelled or git failed. }
    function EditIdentity: boolean;
    function EnsureIdentity: boolean;
    procedure IdentityClick(Sender: TObject);
    procedure CommitHeaderEnter(Sender: TObject);
    procedure StartCommit;
    {** The notice with a failed commit's reason (a hook's output, in
      its colors), Commit Again and Copy Output. }
    procedure ShowCommitFailure(const AError: string);
    procedure CommitJobDone(Sender: TObject);
    procedure StopCommitJob(AWait: boolean);
    procedure DroppedCommitDone(Sender: TObject);
    procedure ForgetCommitted(AJob: TGittanCommitJob);
    procedure SaveCommitDraft;
    procedure LoadCommitDraft;
    procedure UpdateRemoteItems;
    procedure RevertTargets(AList: TStrings);
    function CanRevert: boolean;
    procedure RevertPaths(APaths: TStrings; const ALabel: string);
    procedure MenuRevertChangesClick(Sender: TObject);
    function CanMoveFiles: boolean;
    procedure MenuMoveFileClick(Sender: TObject);
    procedure MenuRemoveFileClick(Sender: TObject);
    procedure MenuFileHistoryClick(Sender: TObject);
    procedure MenuRevertFileClick(Sender: TObject);
    procedure MenuUndoRevertClick(Sender: TObject);
    function CanClean: boolean;
    procedure MenuCleanClick(Sender: TObject);
    function CloneParent: string;
    procedure StartClone(const AUrl, ATarget: string; ASubmodules: boolean);
    procedure CloneDone(AJob: TGittanRemoteJob);
    procedure MenuCloneClick(Sender: TObject);
    procedure MenuInitClick(Sender: TObject);
    function CanEditRemotes: boolean;
    procedure EditRemotesAsk;
    procedure MenuRemotesClick(Sender: TObject);
    procedure RepoPageEditRemotes(Sender: TObject);
    procedure SubPageCopyCommit(Sender: TObject; const AHash: string);
    procedure BrowseCommit(const AHash, AName, ASubject: string);
    function PatchFolder: string;
    procedure CreatePatches(const AOlder, ANewer: string);
    function CanApplyPatches: boolean;
    procedure MenuApplyPatchesClick(Sender: TObject);
    function IsChangedPath(const APath: string): boolean;
    procedure ClearRevertUndo;
    procedure BranchContext(Sender: TObject; AIndex: integer; const AScreenPos: TPoint);
    procedure BranchMenuClick(Sender: TObject);
    function BranchAction(const AName: string): boolean;
    procedure RenameBranchAsk(const AName: string);
    procedure DeleteBranchAsk(const AName: string);
    procedure DeleteGoneBranches;
    procedure MergeIntoCurrent(const ARef: string);
    procedure RebaseOntoAsk(const ARef: string);
    {** Rebase (ARebase) or Merge in the summary's row of a branch behind
      the default branch: a fetch, then the rebase's question or the
      merge (AfterFetch). }
    procedure SummaryBehindAction(Sender: TObject; ARebase: boolean);
    {** Runs the rebase or merge SummaryBehindAction waits with, after a
      fetch that went through, when the branch is still the one it was
      for. }
    procedure AfterFetch;
    procedure RebaseInteractiveAsk(const AOnto, AName: string; AFromGraph: boolean);
    procedure CompareSince(const ARef: string);
    procedure CompareCurrentSince(const ARef: string);
    procedure ShowBranchList(AMode: TGittanBranchListMode; const AScreenRect: TRect);
    procedure UpdateBranchItems;
    procedure BranchMenuOpen(Sender: TObject);
    procedure MenuBranchListClick(Sender: TObject);
    procedure MenuNewBranchClick(Sender: TObject);
    procedure ShowUpstreamList(const ABranch: string; const AScreenRect: TRect);
    procedure UpstreamPopupPick(Sender: TObject; AIndex: integer);
    procedure MenuUpstreamClick(Sender: TObject);
    procedure ShowTagList(const AScreenRect: TRect);
    procedure TagPopupPick(Sender: TObject; AIndex: integer);
    procedure TagContext(Sender: TObject; AIndex: integer; const AScreenPos: TPoint);
    procedure TagMenuClick(Sender: TObject);
    procedure NewTagAsk;
    procedure CheckoutTagAsk(const ATag: TGittanTag);
    procedure BranchAtAsk(const ALabel, ACommit: string);
    function NewBranchAsk(const APrompt, ACommit: string): boolean;
    function TagAtAsk(const AShort, ACommit: string): boolean;
    procedure DeleteTagAsk(const ATag: TGittanTag);
    procedure MenuTagsClick(Sender: TObject);
    procedure MenuNewTagClick(Sender: TObject);
    procedure MenuPushTagsClick(Sender: TObject);
    procedure ShowReflogList(const AScreenRect: TRect);
    procedure ReflogPopupPick(Sender: TObject; AIndex: integer);
    procedure ReflogContext(Sender: TObject; AIndex: integer; const AScreenPos: TPoint);
    procedure ReflogMenuClick(Sender: TObject);
    procedure MenuReflogClick(Sender: TObject);
    function ResetTarget: string;
    function ResetAsk(const AHash, AShort: string; AMode: TGittanResetMode): boolean;
    function ResetToAsk(const AHash, AShort: string; AMode: TGittanResetMode): boolean;
    function StashLabel(const AStash: TGittanStash): string;
    function StashOfBase: integer;
    procedure ShowStashList(const AScreenRect: TRect);
    procedure StashPopupPick(Sender: TObject; AIndex: integer);
    procedure StashContext(Sender: TObject; AIndex: integer; const AScreenPos: TPoint);
    procedure StashMenuClick(Sender: TObject);
    procedure StashChangesAsk(AChosenOnly: boolean);
    procedure ApplyStash(AStash: TGittanStash; APop: boolean);
    procedure DropStashAsk(AStash: TGittanStash);
    procedure BranchFromStashAsk(AStash: TGittanStash);
    function ComparingStash(const AId: string): boolean;
    procedure CompareStash(AStash: TGittanStash);
    procedure StashBaseClick(const AScreenRect: TRect);
    procedure StashBasePick(AIndex: integer);
    procedure UpdateStashItems;
    procedure StashMenuOpen(Sender: TObject);
    procedure MenuStashAllClick(Sender: TObject);
    procedure MenuStashChosenClick(Sender: TObject);
    procedure MenuPopStashClick(Sender: TObject);
    procedure MenuApplyStashClick(Sender: TObject);
    procedure MenuStashListClick(Sender: TObject);
    procedure GraphContext(Sender: TObject; const ACommit: TGittanGraphCommit;
      const AScreenPos: TPoint);
    procedure CommitMenuClick(Sender: TObject);
    function ContinueMode: boolean;
    function StrayRebase: boolean;
    function OperationLabel: string;
    function IsConflictPath(const APath: string): boolean;
    function MarkersLeft(const APath: string): integer;
    procedure ResolvePath(const APath: string; AAction: integer);
    function ConflictHeaderAction(AIndex: integer): boolean;
    function CanResolveBlocks: boolean;
    procedure FindConflictRows;
    function ConflictAtRow(ARow: integer): integer;
    procedure ResolveConflictAt(AIndex: integer);
    procedure ApplyConflictPick(AIndex: integer; APick: TGittanConflictPick);
    procedure ConflictPopupPick(Sender: TObject; AIndex: integer);
    procedure ConflictBadgeClick(const AScreenRect: TRect);
    function ConflictDetail(const APath: string): string;
    function NextConflictFile(const AAfter: string; ANext: boolean): string;
    procedure ShowNextConflict(const AAfter: string; AAdvance: boolean);
    procedure GoToConflict(ANext: boolean);
    procedure SummaryRowAction(Sender: TObject; const APath: string);
    procedure CommitNoteLink(Sender: TObject);
    procedure MenuNextConflictClick(Sender: TObject);
    procedure MenuPrevConflictClick(Sender: TObject);
    procedure UpdateResolveItems;
    procedure MenuResolveHereClick(Sender: TObject);
    procedure MenuResolveEditClick(Sender: TObject);
    procedure MenuResolveMineClick(Sender: TObject);
    procedure MenuResolveTheirsClick(Sender: TObject);
    procedure MenuMarkResolvedClick(Sender: TObject);
    procedure ContinueOperationClick;
    procedure SkipOperationClick(Sender: TObject);
    procedure AbortOperationClick(Sender: TObject);
    procedure SetupBisect;
    procedure UpdateBisectState;
    procedure BisectButtonClick(Sender: TObject);
    function RunBisect(AStep: TBisectStep; const ACommit: string;
      AMark: TGittanBisectMark; const AGood: string): boolean;
    procedure BisectReport(const ADone: string);
    procedure BisectMarkCommit(const ACommit: string; AMark: TGittanBisectMark);
    function BisectStartAt(const ABad, AGood: string): boolean;
    procedure BisectEndClick;
    procedure StartRemote(AKind: TGittanRemoteKind; AMode: TGittanPullMode = pmAuto;
      const AArg: string = ''; const ARemote: string = '');
    procedure RemoteJobDone(Sender: TObject);
    procedure RemoteJobOutput(Sender: TObject);
    procedure NoticeTimerTimer(Sender: TObject);
    procedure NoticeButton(Sender: TObject; AIndex: integer);
    procedure ShowRemoteFailure(AJob: TGittanRemoteJob; AHookFailed: boolean);
    procedure ShowRemoteNotice;
    function RemoteNoticeTitle: string;
    procedure StopRemoteJob(AWait: boolean);
    procedure MenuFetchClick(Sender: TObject);
    procedure MenuPullClick(Sender: TObject);
    procedure MenuPushClick(Sender: TObject);
    procedure ForcePushAsk;
    procedure MenuForcePushClick(Sender: TObject);
    procedure SyncClick(const AScreenRect: TRect);
    function BaseActionRef: string;
    procedure BaseClick(const AScreenRect: TRect);
    procedure SummaryBaseClick(Sender: TObject; const AScreenRect: TRect);
    function BlameShown: boolean;
    procedure SummaryBackClick(Sender: TObject);
    procedure SummarySyncClick(Sender: TObject; const AScreenRect: TRect);
    procedure BasePopupPick(Sender: TObject; AIndex: integer);
    procedure SyncPopupPick(Sender: TObject; AIndex: integer);
    function SubmoduleKey: string;
    procedure FillSubmodules;
    {** The index in FSubmodules of the submodule at APath, -1 for none. }
    function SubmoduleAt(const APath: string): integer;
    {** "6a1f2c0 → 1a377b1" for submodule AIndex when it moved, else
      empty. }
    function SubmoduleMoveText(AIndex: integer): string;
    procedure SelectShownSubmodule;
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
    function CanSubmoduleAction: boolean;
    procedure UpdateSubmoduleItems;
    procedure RecheckSubmodules;
    procedure UpdateSubmodulesAsk(const APath: string);
    procedure SyncSubmodulesNow(const APath: string);
    procedure AddSubmoduleAsk(const AUrl, APath, ABranch: string);
    procedure SubmoduleRemoteDone(AJob: TGittanRemoteJob);
    function PopupSubmodule: integer;
    function PopupSubmodulePath: string;
    procedure SubPopupPopup(Sender: TObject);
    procedure MenuSubUpdateAllClick(Sender: TObject);
    procedure MenuSubSyncAllClick(Sender: TObject);
    procedure MenuSubAddClick(Sender: TObject);
    procedure MenuSubUpdateClick(Sender: TObject);
    procedure MenuSubSyncClick(Sender: TObject);
    procedure MenuSubOpenClick(Sender: TObject);
    procedure MenuSubCopyPathClick(Sender: TObject);
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
    function TreeFilterQuery: string;
    {$IFDEF LCLCocoa}
    procedure ToolbarSearchKey(Sender: TObject; var Key: word);
    {$ENDIF}
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure HeaderControlsChange(Sender: TObject);
    procedure MenuFilterFilesClick(Sender: TObject);
    procedure AbandonPullJob;
    procedure StartUpdateCheck(AManual: boolean);
    procedure UpdateTimerTimer(Sender: TObject);
    procedure AbandonUpdateJob;
    procedure UpdateJobDone(Sender: TObject);
    procedure ShowUpdateBadge;
    procedure UpdateDialog;
    procedure MenuCheckUpdatesClick(Sender: TObject);
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
    procedure StatusStepClick(AStep: TStatusStep; const AScreenRect: TRect);
    {** Shows AText in the status bar for a while, or an error in the
      banner, its first line as the title. }
    procedure StatusNote(const AText: string; AError: boolean = False);
    {** Shows a failure in the banner until it is closed: ATitle in bold,
      ADetail (git's error, say) after it and unfolded on demand. }
    procedure BannerError(const ATitle, ADetail: string);
    {** Shows a note in the banner for a few seconds. }
    procedure BannerInfo(const ATitle: string; const ADetail: string = '');
    {** Shows in green for a few seconds that something went through. }
    procedure BannerSuccess(const ATitle: string; const ADetail: string = '');
    procedure BannerChange(Sender: TObject);
    {** Gives the space under the macOS title bar to the top control of
      the editor panel: the banner while it is shown, else the file
      header and the summary. }
    procedure PlaceUnderTitleBar;
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
    procedure OpenFile(AFileName: string);
    {** Opens the git repository containing ADir, lists its changed files in
      the tree and shows the uncommitted changes as a diff in the editor. }
    procedure OpenRepository(const ADir: string);
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

uses
  Clipbrd, LCLIntf, Process, FileUtil, LazFileUtils, DateUtils, StrUtils, LazUTF8, LCLProc,
  LConvEncoding, gittan.textfit
  {$IFDEF LCLCocoa}, CocoaConfig, gittan.titlebar{$ENDIF};

resourcestring
  rsAppName = 'Git Tree Analyzer & Navigator';
  rsAppShortName = 'Gittan';
  rsFile = '&File';
  rsOpen = '&Open...';
  rsOpenRepo = 'Open &Repository...';
  rsOpenRecent = 'Open Re&cent';
  rsCloneItem = 'Clo&ne Repository...';
  rsInitItem = '&Init Repository...';
  rsInitTitle = 'Init Repository';
  rsInitInside = 'The folder %s is inside the repository %s. Make a repository of its own ' +
    'in it anyway? The outer repository then no longer sees its files.';
  rsInitAction = 'Init';
  rsInitFailed = 'Could not make a repository in %s';
  rsInitAlready = '%s is a repository already';
  rsInitDone = 'Made %s a new repository';
  rsRemotesItem = 'Re&motes...';
  rsCloning = 'Cloning %s...';
  rsNoticeCloning = 'Cloning %s';
  rsCloneFailed = 'The clone failed';
  rsCloneAgain = 'Clone Again';
  rsCloned = 'Cloned %s';
  rsClearMenu = 'Clear Menu';
  rsSyntax = '&Syntax';
  rsAutomatic = '&Automatic';
  rsView = '&View';
  rsSummary = '&Summary';
  rsRepoDiff = '&Repository Diff';
  rsRepoInfo = 'Repository &Info';
  rsCommandsMenu = '&Commands';
  rsCommandStillRunning = '%s is still running';
  rsCommandDone = '%s finished in %s';
  rsCommandFailed = '%s failed with exit code %d';
  rsCommandStopped = '%s was stopped';
  rsCommandNoStart = '%s could not be started';
  rsNavHome = 'Home';
  rsNavGraph = 'Graph';
  rsNavRepository = 'Repository';
  rsNavRecent = 'Recent';
  rsNavCommands = 'Commands';
  rsNavChanges = 'Changes';
  rsNavPulls = 'Pull Requests';
  rsAllPulls = 'All Pull Requests';
  rsFilesMenu = '&Files';
  rsAtCommit = 'at %s';
  rsBlobOpen = 'Open';
  rsBlobSaveAs = 'Save As…';
  rsBlobReadFailed = 'Could not read %s: %s';
  rsBlobWriteFailed = 'Could not write %s: %s';
  rsFilesSubmoduleUnknown = '%s is not among the submodules of this work tree';
  rsNoRecent = 'No recent repositories';
  rsNavFiles = 'Files';
  rsNavHide = 'Hide navigation';
  rsNavShow = 'Show navigation';
  rsTreeClean = 'No changes';
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
  rsTranslations = 'T&ranslations';
  rsTranslationStats = '%d entries · %d fuzzy · %d untranslated';
  rsTranslationChanged = '%d changed · ';
  rsContextLines = 'Conte&xt Lines';
  rsNLines = '%d lines';
  rsSideBySide = 'Side &by Side';
  rsWordWrap = '&Word Wrap';
  rsMarkdownPreview = '&Preview';
  rsPreviewToggle = 'Preview';
  rsPreviewHint = 'Show the file drawn beside its text (%s)';
  rsTranslationsHint = 'Show the originals beside the translations (%s)';
  rsIgnoreSpace = 'I&gnore Whitespace';
  rsFolding = 'F&olding';
  rsFold = '&Fold';
  rsUnfold = '&Unfold';
  rsFoldAll = 'Fold &All';
  rsUnfoldAll = 'U&nfold All';
  rsBlame = '&Blame';
  rsNotCommitted = 'Not committed';
  rsNotCommittedYet = 'Not committed yet';
  rsCommit = 'commit %s';
  rsHistory = 'Code &History';
  rsGoFileHistory = 'Fi&le History';
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
  rsCheckUpdates = 'Check for &Updates...';
  rsSettings = 'Se&ttings...';
  rsAbout = '&About Gittan';
  rsUpdateTitle = 'Gittan Updates';
  rsUpdateBadge = 'Build %d available';
  rsUpdateHint = '%s is out; this is build %d.';
  rsUpdateHintClick = 'Click to download it';
  rsUpdateAvailable = '%s is out; this is build %d. Download it from GitHub?';
  rsUpdateDownload = 'Download';
  rsUpdateLater = 'Remind Me in %d Days';
  rsUpdateNotNow = 'Not Now';
  rsUpdateCurrent = 'Gittan is up to date: build %d is the latest.';
  rsUpdateNoBuild = 'The latest release, %s, has no build number to compare build %d with.';
  rsUpdateLocalBuild = 'This is a local build, so it is not compared with the releases. The latest release is %s.';
  rsUpdateOpenPage = 'Open Release Page';
  rsUpdateClose = 'Close';
  rsUpdateFailed = 'Could not ask GitHub for the latest release: %s';
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
  rsNextConflict = 'Next Conflic&t';
  rsPrevConflict = 'Pre&vious Conflict';
  rsConflictsSuffix = 'conflicts';
  rsNextFile = 'Next F&ile';
  rsPrevFile = 'Previous Fi&le';
  rsRepoFiles = 'Config';
  rsCommitSection = 'Commit';
  rsCommitMenu = 'Co&mmit...';
  rsCommitButton = 'Commit';
  rsCommitAmendButton = 'Amend Commit';
  rsCommitAmend = 'Amend';
  rsWriteMessage = '✦ AI';
  rsAIReviewMenu = 'Review Changes with AI';
  rsAIReviewStopMenu = 'Stop AI Review';
  rsAIClearMenu = 'Clear AI Review';
  rsAIReviewing = '%s is reviewing the changes...';
  rsAIReviewFailed = '%s could not review the changes';
  rsAIReviewNone = '%s found nothing to point out.';
  rsAIReviewOne = '%s found one thing to look at.';
  rsAIReviewMany = '%s found %d things to look at.';
  rsSeverityBug = 'Bug';
  rsSeverityRisk = 'Risk';
  rsSeverityQuestion = 'Question';
  rsWriteMessageMenu = 'Write Commit Message';
  rsStopMessageMenu = 'Stop Writing Commit Message';
  rsWriteMessageHint = 'Write the message with %s from the ticked files';
  rsWritingMessage = 'Stop';
  rsWritingMessageHint = '%s is writing the message; click to stop';
  rsWritingStatus = '%s is writing the message...';
  rsMessageFailed = '%s wrote no message';
  rsMessageChanged = '%s''s message was not used: the field changed meanwhile.';
  rsCommitting = 'Committing...';
  rsCommitMessageHint = {$IFDEF DARWIN}'Message (⌘↩ to commit)'{$ELSE}'Message (Ctrl+Enter to commit)'{$ENDIF};
  rsCommitCount = '%d of %d';
  rsCommitNotHead = 'Commits go on HEAD. Compare with HEAD to choose files.';
  rsCommitConflicts = 'Resolve the conflicts first (%d files).';
  rsCommitConflictOne = 'Resolve the conflict first.';
  rsNextConflictLink = 'Next Conflict (%s)';
  rsResolvePill = 'Resolve';
  rsCommitWhole = 'While %s, everything staged goes into the commit too.';
  rsCommitNothing = 'Tick the files to commit.';
  rsCommitted = 'Committed %s: %s';
  rsCommittedTitle = 'Committed %s';
  rsTickAllItem = 'Tick All Files';
  rsUntickAllItem = 'Untick All Files';
  rsPushAction = 'Push';
  rsSubjectCount = '%d/%d';
  rsSubjectCountHint = 'Characters in the first line. git log and GitHub cut it after %d.';
  rsCommitFailed = 'The commit failed';
  rsCommitAgain = 'Commit Again';
  rsFetchMenu = '&Fetch';
  rsPullMenu = '&Pull';
  rsPushMenu = 'P&ush';
  rsFetchItem = 'Fetch';
  rsGitPullItem = 'Pull';
  rsPushItem = 'Push';
  rsCommitGraphItem = 'Commit Graph';
  rsPushNewBranch = 'new on the remote';
  rsFetching = 'Fetching...';
  rsPulling = 'Pulling...';
  rsPushing = 'Pushing...';
  rsRunningHook = 'Running the pre-push hook...';
  rsNoticeFetching = 'Fetching';
  rsNoticePulling = 'Pulling';
  rsNoticePushing = 'Pushing';
  rsNoticeHook = 'Running the pre-push hook';
  rsNoticeDeleting = 'Deleting %s on the remote';
  rsHookFailed = 'The pre-push hook failed';
  rsPushAgain = 'Push Again';
  rsPullAgain = 'Pull Again';
  rsFetchAgain = 'Fetch Again';
  rsTryAgain = 'Try Again';
  rsCopyOutput = 'Copy Output';
  rsOutputCopied = 'Copied the output';
  rsFetched = 'Fetched';
  rsFetchedBehind = 'Fetched: %d commits to pull';
  rsFetchedBehindOne = 'Fetched: 1 commit to pull';
  rsPulled = 'Pulled';
  rsPulledOne = 'Pulled 1 commit into %s';
  rsPulledCount = 'Pulled %d commits into %s';
  rsPulledNothing = 'Pulled: %s was up to date';
  rsPushed = 'Pushed %d commits on %s';
  rsPushedOne = 'Pushed 1 commit on %s';
  rsPushedBranch = 'Pushed %s';
  rsFetchFailed = 'The fetch failed';
  rsGitPullFailed = 'The pull failed';
  rsPushFailed = 'The push failed';
  rsPullDivergedTitle = 'The Branch Has Diverged';
  rsPullDiverged = 'The branch and its upstream both have commits the other lacks. ' +
    'Merge them with a merge commit, or rebase your commits onto the upstream''s?';
  rsMergeAction = 'Merge';
  rsRebaseAction = 'Rebase';
  rsPushRejectedTitle = 'The Push Was Rejected';
  rsPushRejected = 'The remote has commits the branch does not have yet. Pull them first?';
  rsPushRejectedDiverged = '%s has %d commits the branch lacks. Pull them in?';
  rsPushRejectedDivergedOne = '%s has a commit the branch lacks. Pull it in?';
  rsPushRejectedForce = 'If the branch was rewritten (rebased or amended) after it was ' +
    'pushed, force the push instead, which puts the branch''s commits in their place.';
  rsPullAction = 'Pull';
  rsForcePushMenu = 'Force Push (with &Lease)...';
  rsForcePushItem = 'Force Push';
  rsForcePushDetail = 'replaces ↓%d';
  rsForcePushAction = 'Force Push';
  rsForcePushTitle = 'Force Push';
  rsForceAsk = 'Force push %s over %s? The %d commits %s has that the branch lacks are ' +
    'taken off it. If someone pushed since the last fetch, the push is refused (--force-with-lease).';
  rsForceAskOne = 'Force push %s over %s? The commit %s has that the branch lacks is ' +
    'taken off it. If someone pushed since the last fetch, the push is refused (--force-with-lease).';
  rsForceNoUpstream = '%s has no upstream to force a push over';
  rsForcePushing = 'Force pushing...';
  rsNoticeForcePushing = 'Force pushing';
  rsForcePushed = 'Force pushed %s';
  rsForceStaleTitle = 'The Remote Has Moved';
  rsForceStale = '%s has commits pushed since the last fetch, which the forced push would ' +
    'lose. Fetch them first, to see what they are?';
  rsForceUnseenTitle = 'The Remote Has Commits Not Taken In';
  rsForceUnseen = '%s has commits that were fetched but were never in the branch, ' +
    'someone else''s work maybe, which the forced push would lose. Pull them in first?';
  rsGitTooOld = 'git %s is older than %d.%d';
  rsGitTooOldDetail = 'Gittan needs git %d.%d or later, and some of what it does fails with ' +
    'this one (%s). Update git, or set a newer one in Settings > Tools.';
  rsPushingTo = 'Pushing %s to %s...';
  rsPushingTags = 'Pushing the tags to %s...';
  rsNoticePushingTo = 'Pushing %s to %s';
  rsTheTags = 'the tags';
  rsNoticeDeletingOn = 'Deleting %s on %s';
  rsPushedBranchTo = 'Pushed %s to %s, which it now tracks';
  rsUpstreamDetached = 'HEAD is on no branch';
  rsPushedTag = 'Pushed the tag %s to %s';
  rsPushedTags = 'Pushed the tags to %s';
  rsDeletedRemoteTag = 'Deleted the tag %s on %s';
  rsNoRemote = 'The repository has no remote';
  rsCaShow = 'Show Commit';
  rsCaCompare = 'Compare with Working Tree';
  rsCaBrowse = 'Browse Files...';
  rsCaPatch = 'Create Patch...';
  rsCaPatchSeries = 'Create Patch Series with Marked %s...';
  rsBrowseTitle = 'Files at %s';
  rsCaMark = 'Mark for Comparison';
  rsCaUnmark = 'Unmark';
  rsCaCompareMarked = 'Compare with Marked %s';
  rsCaSwitch = 'Switch to %s';
  rsCaBranch = 'Create Branch Here...';
  rsCaTag = 'Create Tag Here...';
  rsCaMerge = 'Merge %s into %s';
  rsCaCherryPick = 'Cherry-pick into %s';
  rsCaRevert = 'Revert Commit';
  rsCaReset = 'Reset %s to Here';
  rsCaResetSoft = 'Soft: keep the changes staged...';
  rsCaResetMixed = 'Mixed: keep the changes in the files...';
  rsCaResetHard = 'Hard: discard all changes...';
  rsCaBranchTitle = 'Create Branch';
  rsCaBranchPrompt = 'Name of the new branch at %s';
  rsCaTagTitle = 'Create Tag';
  rsCaTagPrompt = 'Name of the tag on %s';
  rsCaTagMessage = 'Message (optional, makes it annotated)';
  rsCaResetTitle = 'Reset';
  rsCaResetAsk = 'Move %s to %s? The commits after it leave the branch.';
  rsCaResetForwardAsk = 'Move %s forward to %s? No commit leaves the branch.';
  rsCaResetAwayAsk = 'Move %s to %s? The commits it has that %1:s lacks leave the branch.';
  rsCaResetSoftAsk = 'Their changes stay staged.';
  rsCaResetMixedAsk = 'Their changes stay in the files, unstaged.';
  rsCaResetHardAsk = 'Their changes and every uncommitted change to a tracked file are lost.';
  rsCaResetForwardHardAsk = 'Every uncommitted change to a tracked file is lost.';
  rsCaResetAction = 'Reset';
  rsCaBranched = 'Created and switched to %s';
  rsCaTagged = 'Tagged %s as %s';
  rsCaMerged = 'Merged %s';
  rsCaPicked = 'Cherry-picked %s';
  rsCaReverted = 'Reverted %s';
  rsCaWasReset = 'Reset %s to %s';
  rsCaConflicts = 'Stopped with conflicts: resolve them, then continue';
  rsCaRebase = 'Rebase Interactively from Here...';
  rsCaBisect = 'Bisect';
  rsCaBisectStartGood = 'Start Bisect: This Is Good, %s Is Bad';
  rsCaBisectStartBad = 'Start Bisect: This Is Bad';
  rsCaBisectGood = 'Mark as Good';
  rsCaBisectBad = 'Mark as Bad';
  rsCaBisectSkip = 'Skip: cannot be tested';
  rsCaBisectEnd = 'End Bisect';
  rsBisectGood = 'Good';
  rsBisectBad = 'Bad';
  rsBisectSkip = 'Skip';
  rsBisectShow = 'Show Commit';
  rsBisectEnd = 'End Bisect';
  rsBisectWaitBoth = 'Bisecting: mark a commit with the problem as bad and one from before it as good, in the commit graph, or the one checked out here.';
  rsBisectWaitGood = 'Bisecting: %s is bad. Mark a commit from before the problem as good, in the commit graph, or the one checked out here.';
  rsBisectWaitBad = 'Bisecting: mark a commit with the problem as bad, in the commit graph, or the one checked out here.';
  rsBisectTest = 'Test %s, the commit checked out, then mark it Good or Bad, or Skip it when it cannot be tested. %d commits are left to test, about %d steps.';
  rsBisectTestLast = 'Test %s, the commit checked out, then mark it Good or Bad, or Skip it when it cannot be tested. It is the last one left to test.';
  rsBisectFound = '%s is the first bad commit: %s';
  rsBisectSuspects = 'Only skipped commits are left to test: the first bad commit is one of %s.';
  rsBisectOnlySkipped = 'The bisect cannot narrow it down further';
  rsBisectStarted = 'Started bisecting';
  rsBisectMarkedGood = 'Marked %s as good';
  rsBisectMarkedBad = 'Marked %s as bad';
  rsBisectSkipped = 'Skipped %s';
  rsBisectEnded = 'Ended the bisect, back on %s';
  rsBisectEndedDetached = 'Ended the bisect';
  rsRebaseChoose = 'Choose Commits...';
  rsRiTitleFrom = 'Commits of %s after %s';
  rsRiNothing = '%s has no commits after %s: nothing to rewrite';
  rsRiMerges = 'The commits of %s since %s include a merge commit, which an interactive rebase would flatten.';
  rsRiPushed = '%d of these commits are already pushed, so the next push must be forced.';
  rsRiPushedOne = 'One of these commits is already pushed, so the next push must be forced.';
  rsRiDone = 'Rebased %s';
  rsRiStopped = 'The rebase stopped';
  rsRebaseStoppedAt = 'Stopped at %s to edit it: change the files, then Continue amends them into it';
  rsRebaseEditNote = 'Stopped at %s to edit it. Continue amends the changes into it and goes on.';
  rsCaFailed = 'Git refused';
  rsSwitched = 'Switched to %s';
  rsSwitchedAlong = 'Switched to %s with your changes';
  rsStashedSwitched = 'Stashed your changes and switched to %s';
  rsSwitchFailed = 'Could not switch to %s';
  rsSwitchBlockedTitle = 'Local Changes';
  rsSwitchBlocked = 'Your changes to these files would be overwritten by switching to %s:';
  rsSwitchMore = 'and %d more';
  rsStashAndSwitch = 'Stash and Switch';
  rsBringChanges = 'Bring Changes Along';
  rsStashMessage = 'Gittan: before switching to %s';
  rsStashFailed = 'Could not stash the changes';
  rsStashKept = 'Your changes are in the stash.';
  rsBmNew = 'New Branch...';
  rsBmGone = 'Delete Gone Branches...';
  rsBmNewPrompt = 'Name of the new branch, made at HEAD and switched to';
  rsBmSwitch = 'Switch to %s';
  rsBmMerge = 'Merge %s into %s';
  rsBmCompareSince = 'Show What %s Changed Since %s';
  rsBmCompareTree = 'Compare with Working Tree';
  rsBmRebase = 'Rebase %s onto %s';
  rsBranchMenu = '&Branch';
  rsBmSwitchItem = '&Switch to Branch...';
  rsBmNewItem = '&New Branch...';
  rsBmMergeItem = '&Merge into %s...';
  rsBmRebaseItem = '&Rebase %s onto...';
  rsBmCompareItem = 'Show What a Branch &Changed Since It Left %s...';
  rsBmCompareBackItem = 'Show What %s Changed Since It &Left...';
  rsBmCurrent = 'the Current Branch';
  rsBmMergeHeader = 'Merge into %s';
  rsBmRebaseHeader = 'Rebase %s onto';
  rsBmCompareHeader = 'Show what a branch changed since it left %s';
  rsBmCompareBackHeader = 'Show what %s changed since it left';
  rsBmRebaseTitle = 'Rebase';
  rsBmRebaseAsk = 'Rebase %s onto %s? Its %d commits since they parted are replayed on top of %s.';
  rsBmRebaseAskOne = 'Rebase %s onto %s? Its one commit since they parted is replayed on top of %s.';
  rsBmRebasePushed = '%d of them are already pushed, so the next push must be forced.';
  rsBmRebasePushedOne = 'One of them is already pushed, so the next push must be forced.';
  rsBmRebaseNothing = '%s has no commits since it left %s: nothing to rebase';
  rsBmRebased = 'Rebased %s onto %s';
  rsBmRename = 'Rename...';
  rsBmDelete = 'Delete...';
  rsBmDeleteRemote = 'Delete %s on the Remote...';
  rsBmRenameTitle = 'Rename Branch';
  rsBmRenamePrompt = 'New name for %s';
  rsBmRenamed = 'Renamed %s to %s';
  rsBmDeleteTitle = 'Delete Branch';
  rsBmDeleteAsk = 'Delete the branch %s?';
  rsBmNotMerged = '%s has commits that are in no other branch. Delete it anyway? ' +
    'Those commits are then only in the reflog.';
  rsBmDeleteAction = 'Delete';
  rsBmDeleted = 'Deleted %s';
  rsBmDeleteRemoteTitle = 'Delete on the Remote';
  rsBmDeleteRemoteAsk = 'Delete %s on the remote, for everyone who uses it?';
  rsBmGoneTitle = 'Delete Gone Branches';
  rsBmGoneAsk = 'Delete these %d branches, whose upstream was deleted on the remote?';
  rsBmGoneUnmerged = 'These %d have commits that are in no other branch. Delete them too?';
  rsBmGoneDeleted = 'Deleted %d branches';
  rsBmGoneDeletedOne = 'Deleted 1 branch';
  rsBmUpstream = 'Set Upstream...';
  rsBmUpstreamItem = 'Set &Upstream of %s...';
  rsUpstreamHeader = 'Upstream of %s';
  rsUpstreamPush = 'Push to %s/%s';
  rsUpstreamStop = 'Stop Tracking %s';
  rsUpstreamTrack = 'Track a remote branch';
  rsUpstreamSet = '%s now tracks %s';
  rsUpstreamStopped = '%s tracks no upstream now';
  rsFilterUpstreams = 'Filter remote branches';
  rsTagsItem = '&Tags...';
  rsNewTagItem = 'New Tag at &HEAD...';
  rsPushTagsItem = 'Push All Tags';
  rsTags = 'Tags';
  rsNoTags = 'No tags';
  rsTagNewRow = 'New Tag at HEAD...';
  rsFilterTags = 'Filter tags';
  rsViewChip = 'View';
  rsViewChipHint = 'How the file is shown, and its history';
  rsFilterView = 'Filter';
  rsViewHeader = 'View';
  rsHistoryHeader = 'History';
  rsFilterSubmodules = 'Filter submodules';
  rsSubmodulesHeader = 'Submodules';
  rsReflogItem = 'Re&flog...';
  rsReflog = 'Where HEAD has been';
  rsNoReflog = 'The reflog is empty';
  rsReflogLost = 'only in the reflog';
  rsFilterReflog = 'Filter the reflog';
  rsTmCheckout = 'Check Out...';
  rsTmPush = 'Push to %s';
  rsTmCopy = 'Copy Name';
  rsTmDeleteRemote = 'Delete on %s...';
  rsTagCheckoutTitle = 'Check Out Tag';
  rsTagCheckoutAsk = 'Check out %s? HEAD is then on no branch, and commits made there ' +
    'belong to none. To work on from the tag, create a branch at it instead.';
  rsTagCheckoutAction = 'Check Out';
  rsCheckedOutDetached = 'Checked out %s: HEAD is on no branch';
  rsTagDeleteTitle = 'Delete Tag';
  rsTagDeleteAsk = 'Delete the tag %s here? The remotes keep theirs.';
  rsTagDeleted = 'Deleted the tag %s';
  rsTagDeleteRemoteAsk = 'Delete the tag %s on %s, for everyone who uses it? The local one stays.';
  rsStashMenu = 'Stas&h';
  rsStashAllItem = '&Stash Changes...';
  rsStashChosenItem = 'Stash &Ticked Files...';
  rsPopStashItem = '&Pop Latest Stash';
  rsApplyStashItem = '&Apply Latest Stash';
  rsStashListItem = 'Stas&hes...';
  rsStashes = 'Stashes';
  rsNoStashes = 'No stashes';
  rsStashNewRow = 'Stash Changes...';
  rsFilterStashes = 'Filter stashes';
  rsStashUntracked = 'with untracked files';
  rsStashTitle = 'Stash Changes';
  rsStashPrompt = 'A message for the stash of every change (may be left empty)';
  rsStashPromptChosen = 'A message for the stash of the %d ticked files (may be left empty)';
  rsStashed = 'Stashed the changes of %d files';
  rsStashedOne = 'Stashed the changes of 1 file';
  rsNothingToStash = 'Nothing to stash';
  rsSmApply = 'Apply';
  rsSmPop = 'Pop (Apply and Drop)';
  rsSmBranch = 'Create Branch from Stash...';
  rsSmCompare = 'Show the Stash';
  rsSmDrop = 'Drop...';
  rsStashApplied = 'Applied the stash: %s';
  rsStashPopped = 'Popped the stash: %s';
  rsStashApplyFailed = 'Could not apply the stash';
  rsStashConflictsTitle = 'The stash clashed with your changes';
  rsStashConflictsKept = 'The files are left in conflict, to resolve as after a merge. ' +
    'The stash is kept.';
  rsDropStashTitle = 'Drop Stash';
  rsDropStashAsk = 'Drop the stash "%s"? Its changes are then only in the reflog.';
  rsDropAction = 'Drop';
  rsStashDropped = 'Dropped the stash: %s';
  rsStashBranchTitle = 'Create Branch from Stash';
  rsStashBranchPrompt = 'Name of the branch, made where the stash was made and given its changes';
  rsStashBranched = 'Created %s from the stash and switched to it';
  rsVsStash = 'stash: %s';
  rsStashesHint = '%d stashes';
  rsStashHintOne = '1 stash';
  rsStashListHint = 'Click to list them';
  rsStashActionsHint = 'Apply, pop or drop the stash';
  rsDeletingRemote = 'Deleting %s...';
  rsDeletedRemote = 'Deleted %s on the remote';
  rsDeleteRemoteFailed = 'Could not delete %s on the remote';
  rsUseMine = 'Use Mine';
  rsUseTheirs = 'Use Theirs';
  rsMarkResolved = 'Mark Resolved';
  rsResolveMineItem = 'Resolve Using Mine';
  rsResolveTheirsItem = 'Resolve Using Theirs';
  rsMarkResolvedItem = 'Mark as Resolved';
  rsResolveTitle = 'Resolve the Conflict';
  rsResolveAsk = 'Replace %s with %s? Edits made to it since the conflict are lost.';
  rsResolveAction = 'Replace';
  rsSideMine = 'your version';
  rsSideTheirs = 'the incoming version';
  rsMarkResolvedTitle = 'Conflicts Left';
  rsMarkersLeft = '%s still has %d conflicts. Mark it resolved anyway?';
  rsResolved = 'Resolved %s';
  rsResolveFailed = 'Could not resolve %s: %s';
  rsResolveHere = 'Resolve &Conflict...';
  rsResolveBlockHint = 'Resolve this conflict.' + LineEnding +
    'Click to take mine, theirs or both';
  rsResolveBlockTitle = 'Conflict %d of %d';
  rsUseBothMineFirst = 'Use Both, Mine First';
  rsUseBothTheirsFirst = 'Use Both, Theirs First';
  rsResolvedBlock = 'Resolved the conflict at line %d of %s; %d left in the file';
  rsResolvedBlockOne = 'Resolved the conflict at line %d of %s; 1 left in the file';
  rsResolvedLast = 'Resolved the last conflict in %s and marked it resolved';
  rsResolveBlockFailed = 'Could not resolve the conflict: %s';
  rsConflictsInFile = '%d conflicts';
  rsConflictInFile = '1 conflict';
  rsConflictNoMarkers = 'no markers left';
  rsConflictGone = 'deleted';
  rsAllResolved = 'All conflicts resolved';
  rsAllResolvedCommit = 'All conflicts resolved: commit the merge';
  rsAllResolvedContinue = 'All conflicts resolved: continue %s';
  rsNounMerge = 'the merge';
  rsNounRebase = 'the rebase';
  rsNounCherryPick = 'the cherry-pick';
  rsNounRevert = 'the revert';
  rsNounPatches = 'applying the patches';
  rsContinueButton = 'Continue';
  rsSkipButton = 'Skip';
  rsAbortButton = 'Abort';
  rsCommitMergeButton = 'Commit Merge';
  rsContinueNote = 'Continue goes on with %s.';
  rsContinueFailed = 'Could not continue %s';
  rsContinueExtrasTitle = 'Other Changes';
  rsContinueExtrasAsk = 'Besides the resolved conflicts, these files have changes that ' +
    'Continue puts in the commit too:%s' + LineEnding + LineEnding +
    'To keep them out, cancel and put them away first, in a stash or with Discard.';
  rsContinueExtrasButton = 'Take Them Too';
  rsContinued = 'Finished %s';
  rsContinuedOn = 'Went on with %s';
  rsStoppedAgain = 'Stopped again with conflicts';
  rsSkipTitle = 'Skip the Commit';
  rsSkipAsk = 'Leave out the commit git stopped at, with its changes, and go on with the rest?';
  rsSkipped = 'Skipped the commit';
  rsSkipFailed = 'Could not skip the commit';
  rsAbortTitle = 'Abort';
  rsAbortAsk = 'Abort %s? The branch and the files go back to how they were before it started.';
  rsAborted = 'Aborted %s';
  rsAbortFailed = 'Could not abort %s';
  rsStrayRebaseNote = 'git is still rebasing %0:s, but HEAD is on %1:s. Abort takes %0:s back; ' +
    'Continue would make %0:s what %1:s is.';
  rsStrayAbortAsk = 'git is still rebasing %0:s, but HEAD is on %1:s.' + LineEnding + LineEnding +
    'Abort takes %0:s back to how it was before the rebase and checks it out again, ' +
    'the files with it; %1:s keeps its commits.' + LineEnding + LineEnding +
    'Forget the Rebase stays on %1:s and keeps the files as they are; git just stops rebasing.';
  rsQuitButton = 'Forget the Rebase';
  rsQuit = 'Forgot %s';
  rsQuitFailed = 'Could not forget %s';
  rsOperationOf = '%s %s';
  rsIdentityHint = 'Commits as %s <%s>%s. Click to change.';
  rsIdentityHintLocal = ' (this repository only)';
  rsIdentityNone = 'Git has no name or e-mail to commit under. Click to set them.';
  rsSubmodules = 'Submodules';
  rsSubmodulesNewer = '%d · ↓%d';
  rsSubOpen = 'Open';
  rsSubUpdateAction = 'Update';
  rsSubmodulesMenu = 'Su&bmodules';
  rsSubUpdateAllItem = '&Update Submodules';
  rsSubSyncAllItem = '&Sync Submodule URLs';
  rsSubAddItem = '&Add Submodule...';
  rsSubUpdateItem = '&Update';
  rsSubSyncItem = '&Sync URL';
  rsSubOpenItem = '&Open as Repository';
  rsSubUpdateTitle = 'Update Submodules';
  rsSubUpdateMoved = 'These submodules are checked out at another commit than the one ' +
    'the repository records; Update checks out the recorded one:';
  rsSubUpdateMovedKeep = 'Their commits stay in them, and a branch checked out in one stays ' +
    'where it is.';
  rsSubUpdating = 'Updating %s...';
  rsSubUpdatingAll = 'Updating the submodules...';
  rsNoticeSubUpdating = 'Updating %s';
  rsNoticeSubUpdatingAll = 'Updating the submodules';
  rsSubUpdated = 'Updated %s';
  rsSubUpdatedAll = 'Updated the submodules';
  rsSubUpdateFailed = 'The submodule update failed';
  rsSubUpdateAgain = 'Update Again';
  rsSubSynced = 'Synced the URL of %s';
  rsSubSyncedAll = 'Synced the URLs of the submodules';
  rsSubSyncFailed = 'Could not sync the submodule URLs';
  rsSubAdding = 'Adding the submodule %s...';
  rsNoticeSubAdding = 'Adding the submodule %s';
  rsNoticeFetchingPull = 'Fetching pull request #%d';
  rsSubAddedOk = 'Added the submodule %s; commit it with .gitmodules';
  rsSubAddFailed = 'The submodule could not be added';
  rsSubNone = 'none';
  rsSubCopied = 'Copied %s';
  rsHintSubmodule = 'Submodule moved %s; click to see the commits';
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
  rsLeaveOutItem = '&Leave Change Out of Commit';
  rsIncludeItem = '&Include Change in Commit';
  rsRevertFile = 'Re&vert File...';
  rsUndoRevert = 'Undo Re&vert';
  rsCleanItem = 'C&lean...';
  rsCleaned = 'Deleted %d files and folders';
  rsCleanedOne = 'Deleted %s';
  rsCleanFailed = 'Could not clean';
  rsApplyPatchesItem = 'Appl&y Patches...';
  rsPatchFailed = 'Could not create the patches';
  rsPatchOnlyMerges = 'git makes no patches of merge commits, and there are only those.';
  rsPatchWritten = 'Wrote %s';
  rsPatchesWritten = 'Wrote %d patch files to %s';
  rsPatchCommitted = 'Committed the patch';
  rsPatchesCommitted = 'Committed %d patches';
  rsPatchApplied = 'Applied the patch to the work tree';
  rsPatchesApplied = 'Applied %d patches to the work tree';
  rsPatchAmConflicts = 'The patch stopped with conflicts: resolve them, then Continue in the ' +
    'Commit section';
  rsPatchConflicts = '%s went in with conflicts to resolve';
  rsPatchStopped = '%s does not apply: skip it or abort in the Commit section';
  rsPatchPartly = 'Applied %d of %d patches: %s does not apply';
  rsApplyFailed = 'Could not apply the patches';
  rsRevertChangesItem = 'Revert Changes...';
  rsFileHistoryItem = 'Show History';
  rsRevertTitle = 'Revert';
  rsRevertFilesAsk = 'Revert %s to how HEAD has it? Your changes are undone, and a new ' +
    'file is deleted. File > Undo Revert brings them back.';
  rsRevertFilesAction = 'Revert';
  rsRevertCount = '%d files in %s';
  rsReverted = 'Reverted %s';
  rsRevertFailed = 'Could not revert';
  rsRevertUndone = 'Brought back %s';
  rsRevertUndoFailed = 'Could not bring everything back: %s';
  rsMoveItem = 'Rename or Move...';
  rsMoveTitle = 'Rename or Move';
  rsMovePrompt = 'New path of %s, from the top of the repository';
  rsMoveBadPath = 'A path inside the repository, such as docs/notes.txt';
  rsMoved = 'Renamed %s to %s; the rename goes in with the next commit';
  rsMoveFailed = 'Could not rename %s';
  rsRemoveItem = 'Remove from Git...';
  rsRemoveTitle = 'Remove from Git';
  rsRemoveAsk = 'Take %s out of the repository? Stop Tracking keeps the file on disk, ' +
    'untracked from now on; Delete deletes it too. Either goes in with the next commit.';
  rsRemoveKeepAction = 'Stop Tracking';
  rsRemoveDeleteAction = 'Delete';
  rsUntracked = 'Stopped tracking %s; commit it to take it out of the repository';
  rsRemoved = 'Deleted %s; commit it to take it out of the repository';
  rsRemoveFailed = 'Could not remove %s';
  rsDiscardAction = 'Discard';
  rsKeepPill = 'Reviewed';
  rsKeepPillHint = 'Mark the change reviewed: it shows as plain code for the rest of ' +
    'the session. The file and the commit are not touched.';
  rsUnkeepPill = 'Not Reviewed';
  rsUnkeepPillHint = 'Show the change as a change again';
  rsUnkeepAction = 'Show %d Reviewed';
  rsKeptBlock = 'Marked the change at line %d of %s reviewed';
  rsUnkept = 'Shows the change at line %d of %s again';
  rsUnkeptAll = 'Shows every change of %s again';
  rsLeaveOutPill = 'Skip in Commit';
  rsLeaveOutPillHint = 'Leave the change out of the next commit; it stays in the file';
  rsIncludePill = 'Include in Commit';
  rsIncludePillHint = 'Put the change back into the next commit';
  rsDiscardPillHint = 'Put the lines back as they were, after asking; ' +
    'File > Undo Discard brings them back';
  rsIncludeAllAction = 'Include All';
  rsLeftOutBlock = 'Left the change at line %d of %s out of the commit';
  rsLeftOutFile = 'Left every change of %s out of the commit';
  rsIncludedBlock = 'The change at line %d of %s goes into the commit';
  rsIncludedAll = 'Every change of %s goes into the commit';
  rsDiscardAsk = 'Discard this change to %s?' + LineEnding +
    '%s. File > Undo Discard brings it back.';
  rsDiscardBackOne = 'The line goes back to how it is in %s';
  rsDiscardBackMany = 'The %d lines go back to how they are in %s';
  rsDiscarded = 'Discarded the change at line %d of %s';
  rsDiscardUndone = 'Put the change at line %d of %s back';
  rsDiscardFailed = 'Could not discard the change: %s';
  rsUndoDiscardFailed = 'Could not put the change back: %s';
  rsUnresolveFailed = 'The markers are back in %s, but git still counts it resolved: %s';
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
  rsBranchGone = 'deleted on remote';
  rsFilterBranches = 'Filter branches';
  rsVsBase = 'vs %s';
  rsVsSince = '%s since %s';
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
  rsBaseActionsHint = 'Merge or rebase';
  rsBlameActionsHint = 'Back to the working tree, or copy the commit id';
  rsBackToTree = 'Back to Working Tree';
  rsCopyCommitId = 'Copy Commit ID';
  rsShowSummaryHint = 'Show the summary';
  rsShowConflictHint = 'Show the conflicted files';
  rsAheadHint = '%d commits not pushed yet';
  rsBehindHint = '%d commits not pulled yet';
  rsInSyncHint = 'Up to date with upstream';
  rsNoUpstreamHint = 'No upstream branch';
  rsNotOnRemoteHint = '%d commits on no remote yet';
  rsGraphHint = 'Click to pull, push or show the commit graph';
  rsOperationStep = '%s · %d of %d';
  rsResolveStep = 'Resolve %d conflicts';
  rsResolveOneStep = 'Resolve 1 conflict';
  rsUpToDateStep = 'Up to date';
  rsFetchStepHint = 'Fetch from the remote';
  rsPullStepHint = 'Click to pull them';
  rsPushStepHint = 'Click to push them';
  rsPushNewBranchHint = 'Click to push the branch to the remote';
  rsDivergedHint = 'The branch and its upstream have both moved on';
  rsRewrittenHint = 'Rewritten since it was pushed (rebased or amended)';
  rsRewrittenReplacesOne = 'A force push replaces the 1 commit only the upstream has';
  rsRewrittenReplaces = 'A force push replaces the %d commits only the upstream has';
  rsForcePushStepHint = 'Click to force push (with lease)';
  rsAbortStepHint = 'Abort %s';
  rsSkipStepHint = 'Skip the commit %s stopped at';
  rsCommitGraph = 'Commit &Graph';
  rsPosition = 'Ln %d, Col %d';
  rsPullHintTitle = '#%d %s';
  rsPullHintPassed = '%d checks passed';
  rsPullHintPassedOne = '1 check passed';
  rsPullHintFailed = '%d checks failing';
  rsPullHintFailedOne = '1 check failing';
  rsPullHintPending = '%d checks pending';
  rsPullHintPendingOne = '1 check pending';
  rsPullHintOpen = 'Click to compare with it or open it on GitHub';
  rsComparePull = 'Compare With This Pull Request';
  rsCompareWorkingTree = 'Compare With the Working Tree';
  rsOpenPullOnGitHub = 'Open on GitHub';
  rsCopyPullLink = 'Copy Link';
  rsPositionOld = 'Ln %d (old), Col %d';
  rsReviewComments = 'Review &Comments';
  rsReviewResolved = 'Resolved';
  rsReviewOutdated = 'Outdated';
  rsReviewOnFile = 'On the file';
  rsReviewLine = 'On line %d';
  rsReviewLines = 'Lines %d–%d';
  rsReviewRemovedLine = 'On removed line %d';
  rsReviewReplies = ' (+%d)';
  rsReviewSuggestion = 'Suggested change:';
  rsReviewLink = 'GitHub ↗';
  rsReviewOpen = '%d open review threads';
  rsReviewOpenOne = '1 open review thread';
  rsReviewFailed = 'Could not fetch the review comments';
  rsConversation = 'Conversation of pull request #%d';
  rsTreeThreadOpen = ' · 1 open review thread';
  rsTreeThreadsOpen = ' · %d open review threads';
  rsTreeThreadsDone = ' · review comments, all resolved';

const
  { The rows of the sidebar's pages (umain.repopage.inc). }
  navHome = 0;
  navGraph = 1;
  navRepository = 2;
  navCommands = 3;
  navFiles = 4;
  navPulls = 5;
  { The last row: a list, never selected. }
  navRecent = 6;
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
  { How long a note stays in the banner, and one that offers an action. }
  BannerInfoSeconds = 8;
  BannerActionSeconds = 20;
  { The commit message's first line: its length shows past the soft
    limit, the usual 50, and warns past the hard one, where git log
    --oneline and GitHub cut it. }
  SubjectSoftLimit = 50;
  SubjectHardLimit = 72;
  { How long the pull request data is kept before gh is asked again,
    while checks run and otherwise; ms. }
  PullPollPending = 30000;
  PullPollIdle = 300000;
  { How often the submodules' remotes are asked again; ms. }
  SubmodulePoll = 300000;
  { The first look for a newer Gittan after start, then how often it is
    looked for again; ms. Remind Me Later waits UpdateSnoozeDays. }
  UpdateFirstCheck = 5000;
  UpdatePoll = 6 * 60 * 60 * 1000;
  UpdateSnoozeDays = 14;
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
  rsPullFailed = 'Could not fetch pull request #%d';
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
  { An entry of the translation view that is fuzzy, and one that is not
    translated (see umain.translations.inc). }
  bmFuzzy = 10;
  bmUntranslated = 11;
  { An added and a deleted line left out of the commit (see
    umain.leaveout.inc). }
  bmLeftOutAdded = 12;
  bmLeftOutDeleted = 13;
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
  { The context of an entry in the translation view, dimmed to the
    gutter's color (see umain.translations.inc). }
  tagPoContext = 8;
  { The gutter band of the blame (see umain.blame.inc), the width of its
    age column in characters and the most the author column takes. }
  gutterTagBlame = 100;
  { The band with the discard buttons (see umain.discard.inc), right of
    the editor's own bands, next to the text. }
  gutterTagDiscard = 101;
  { The band of the history view with the author's initial on every
    row (see umain.history.inc), next to the text, and its width in
    characters. }
  gutterTagInitial = 102;
  InitialCols = 3;
  BlameAgeCols = 5;
  BlameMaxAuthorCols = 20;
  { How long the mouse rests on a word before its definition is shown. }
  HoverPause = 600;
  { How long the mouse rests on a changed row before the pills show. }
  PillPause = 250;
  { Before the notice shows for a fetch, pull or push without a hook. }
  NoticeDelay = 1000;
  { How long one parse may take before a lookup or the indexer gives up
    on it. }
  ParseTimeout = 3000;
  { How long typing pauses before the Markdown preview follows it. }
  MdPreviewPause = 300;
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

{ A menu item under AParent, owned by AParent's menu, for the context
  menus that are filled as they open. }
function AddMenuItem(AParent: TMenuItem; const ACaption: string; ATag: integer;
  AEnabled: boolean; AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(AParent.Owner);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.Enabled := AEnabled;
  Result.OnClick := AOnClick;
  AParent.Add(Result);
end;

{ TForm1 }

{ TTreeView }

procedure TTreeView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  Node: TTreeNode;
begin
  if (Button = mbLeft) and Assigned(FOnStateClick) and (StateImages <> nil) then
  begin
    Node := GetNodeAt(X, Y);
    if (Node <> nil) and (Node.StateIndex >= 0) and
      (htOnStateIcon in GetHitTestInfoAt(X, Y)) then
    begin
      if not Focused and CanFocus then
        SetFocus;
      FOnStateClick(Self, Node);
      Exit;
    end;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  FSettings := TGittanSettings.Create;
  FSettings.Load;
  SetGitExe(FSettings.GitPath);
  FindGitHubCli;
  FindAgentCli;
  FTabSize := FSettings.TabSize;
  if FTabSize <= 0 then
    FTabSize := DefaultTabSize;
  FChangeLines := TStringList.Create;
  FHotDiscard := -1;
  FHotRow := -1;
  FHotKeep := -1;
  FHeaderUnkeep := -1;
  FKeeps := TGittanKeeps.Create;
  FLeftOut := TGittanKeeps.Create;
  FHeaderInclude := -1;
  FRawChangeLines := TStringList.Create;
  FBlameCache := TStringList.Create;
  FBlameCache.CaseSensitive := True;
  FBlameZombies := TList.Create;
  FDroppedCommits := TList.Create;
  FThreadFlips := TStringList.Create;
  FReviewMeasure := TBitmap.Create;
  FReviewMeasure.SetSize(1, 1);
  FBlameCols := 12;
  FSideRatio := 0.5;
  FMdRatio := 0.5;
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
  Edit.OnChange := @EditChange;
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
  { A local build has no number to compare, so only the menu checks. }
  FUpdateTimer := TTimer.Create(Self);
  FUpdateTimer.Interval := UpdateFirstCheck;
  FUpdateTimer.OnTimer := @UpdateTimerTimer;
  FUpdateTimer.Enabled := CurrentBuild >= 0;
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
  FHeader.ConflictNav.Suffix := rsConflictsSuffix;
  FHeader.ConflictNav.OnPrev := @MenuPrevConflictClick;
  FHeader.ConflictNav.OnNext := @MenuNextConflictClick;
  FHeader.OnAction := @HeaderAction;
  FHeader.OnToggle := @HeaderToggle;
  FHeader.OnMenu := @HeaderMenu;
  FHeader.SetMenu(rsViewChip, rsViewChipHint);
  UpdateChangeNav;
  { The banner sits over the header, hidden until something fails. }
  FBanner := TGittanBanner.Create(Self);
  FBanner.Parent := EditorPanel;
  FBanner.Top := 0;
  FBanner.Align := alTop;
  FBanner.Visible := False;
  FBanner.OnChange := @BannerChange;
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
  { Files with review comments get a speech bubble (umain.reviews.inc). }
  FileTree.OnAdvancedCustomDrawItem := @FileTreeAdvancedCustomDrawItem;
  FileTree.OnAdvancedCustomDraw := @FileTreeAdvancedCustomDraw;
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
  FImageDiff := TGittanImageDiff.Create(Self);
  FImageDiff.Parent := EditorPanel;
  FImageDiff.Align := alClient;
  FImageDiff.Visible := False;
  FBinaryView := TGittanBinaryView.Create(Self);
  FBinaryView.Parent := EditorPanel;
  FBinaryView.Align := alClient;
  FBinaryView.Visible := False;
  { The Markdown preview sits right of the editor, its splitter between
    them; both are created before the editor's alClient takes the rest. }
  FMdPreview := TGittanMarkdownPreview.Create(Self);
  FMdPreview.Parent := EditorPanel;
  FMdPreview.Align := alRight;
  FMdPreview.Width := EditorPanel.ClientWidth div 2;
  FMdPreview.Visible := False;
  FMdPreview.OnOpenFile := @MdPreviewOpenFile;
  FMdSplitter := TSplitter.Create(Self);
  FMdSplitter.Parent := EditorPanel;
  FMdSplitter.Align := alRight;
  FMdSplitter.Visible := False;
  FMdSplitter.OnMoved := @MdSplitterMoved;
  FMdTimer := TTimer.Create(Self);
  FMdTimer.Enabled := False;
  FMdTimer.Interval := MdPreviewPause;
  FMdTimer.OnTimer := @MdTimerTimer;
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
  FSummary.OnBaseClick := @SummaryBaseClick;
  FSummary.OnSyncClick := @SummarySyncClick;
  FSummary.OnBehindAction := @SummaryBehindAction;
  FSummary.OnOpenUrl := @SummaryOpenUrl;
  FSummary.OnSelectPull := @SummarySelectPull;
  FSummary.OnSelectCommit := @SummarySelectCommit;
  FSummary.OnBackClick := @SummaryBackClick;
  FSummary.OnRowAction := @SummaryRowAction;
  { The branch list pops up over the form, under the branch. }
  FRevertUndo := TStringList.Create;
  FBranchNames := TStringList.Create;
  FBranchRefs := TStringList.Create;
  FGoneToDelete := TStringList.Create;
  FBranchMenu := TPopupMenu.Create(Self);
  FGoneBranches := TStringList.Create;
  FBranchPopup := TGittanPopupList.Create(Self);
  FBranchPopup.Parent := Self;
  FBranchPopup.FilterHint := rsFilterBranches;
  FBranchPopup.OnPick := @BranchPopupPick;
  FBranchPopup.OnContext := @BranchContext;
  { The upstream list and the tag list drop from the status bar's
    branch. }
  FUpstreamRows := TStringList.Create;
  FUpstreamPopup := TGittanPopupList.Create(Self);
  FUpstreamPopup.Parent := Self;
  FUpstreamPopup.FilterHint := rsFilterUpstreams;
  FUpstreamPopup.OnPick := @UpstreamPopupPick;
  FTagMenu := TPopupMenu.Create(Self);
  FTagPopup := TGittanPopupList.Create(Self);
  FTagPopup.Parent := Self;
  FTagPopup.FilterHint := rsFilterTags;
  FTagPopup.OnPick := @TagPopupPick;
  FTagPopup.OnContext := @TagContext;
  FViewPopup := TGittanPopupList.Create(Self);
  FViewPopup.Parent := Self;
  FViewPopup.FilterHint := rsFilterView;
  FViewPopup.OnPick := @ViewPopupPick;
  FSubListPopup := TGittanPopupList.Create(Self);
  FSubListPopup.Parent := Self;
  FSubListPopup.FilterHint := rsFilterSubmodules;
  FSubListPopup.OnPick := @SubListPopupPick;
  FReflogMenu := TPopupMenu.Create(Self);
  FReflogPopup := TGittanPopupList.Create(Self);
  FReflogPopup.Parent := Self;
  FReflogPopup.FilterHint := rsFilterReflog;
  FReflogPopup.OnPick := @ReflogPopupPick;
  FReflogPopup.OnContext := @ReflogContext;
  { The stash list pops up under the status bar's stash chip. }
  FStashMenu := TPopupMenu.Create(Self);
  FStashPopup := TGittanPopupList.Create(Self);
  FStashPopup.Parent := Self;
  FStashPopup.FilterHint := rsFilterStashes;
  FStashPopup.OnPick := @StashPopupPick;
  FStashPopup.OnContext := @StashContext;
  { The commit graph pops up in the middle of the form. }
  FGraph := TGittanCommitGraph.Create(Self);
  FGraph.Parent := Self;
  FGraph.OnPick := @GraphPick;
  FGraph.OnContext := @GraphContext;
  FGraph.OnMore := @GraphMore;
  FGraph.OnPathCommits := @GraphPathCommits;
  FCommitPopup := TPopupMenu.Create(Self);
  FPullPopup := TGittanPopupList.Create(Self);
  FPullPopup.Parent := Self;
  FPullPopup.OnPick := @PullPopupPick;
  FSyncPopup := TGittanPopupList.Create(Self);
  FSyncPopup.Parent := Self;
  FSyncPopup.OnPick := @SyncPopupPick;
  FRecentPopup := TGittanPopupList.Create(Self);
  FRecentPopup.Parent := Self;
  FRecentPopup.OnPick := @RecentPopupPick;
  FBasePopup := TGittanPopupList.Create(Self);
  FBasePopup.Parent := Self;
  FBasePopup.OnPick := @BasePopupPick;
  FConflictPopup := TGittanPopupList.Create(Self);
  FConflictPopup.Parent := Self;
  FConflictPopup.OnPick := @ConflictPopupPick;
  { The pills beside the row the mouse is on in the discard band. }
  FDiscardPills := TGittanHoverPills.Create(Self);
  FDiscardPills.Parent := Self;
  FDiscardPills.OnPick := @DiscardPillsPick;
  FDiscardPills.OnLeave := @DiscardPillsLeave;
  FPillTimer := TTimer.Create(Self);
  FPillTimer.Enabled := False;
  FPillTimer.Interval := PillPause;
  FPillTimer.OnTimer := @PillTimerTimer;
  FResolveIndex := -1;
  { The welcome view shares the summary's box and draws the application
    icon from its own copy: Application.Icon keeps to its small image. }
  FAppIcon := TIcon.Create;
  try
    FAppIcon.LoadFromResourceName(HInstance, 'MAINICON');
  except
    FreeAndNil(FAppIcon);
  end;
  FCloneSubmodules := True;
  FWelcome := TGittanWelcome.Create(Self);
  FWelcome.Parent := FSummaryBox;
  FWelcome.Title := 'Gittan';
  FWelcome.Tagline := rsTagline;
  FWelcome.Shortcut := {$IFDEF DARWIN}'⇧⌘O'{$ELSE}'Ctrl+Shift+O'{$ENDIF};
  FWelcome.SetIcon(FAppIcon);
  FWelcome.OnOpen := @WelcomeOpen;
  FWelcome.OnOpenRecent := @WelcomeOpenRecent;
  FWelcome.OnClone := @WelcomeClone;
  FWelcome.OnInit := @WelcomeInit;
  { The Repository page shares the box too; its links open as the
    summary's do. }
  FRepoPage := TGittanRepoPage.Create(Self);
  FRepoPage.Parent := FSummaryBox;
  FRepoPage.Visible := False;
  FRepoPage.OnOpenUrl := @SummaryOpenUrl;
  FRepoPage.OnEditRemotes := @RepoPageEditRemotes;
  FRepoPage.OnOpenTarget := @RepoPageOpenTarget;
  { And the Commands page, and the Files page. }
  SetupCommandPage;
  SetupFilesPage;
  SetupPullPage;
  { So does the page of a submodule. }
  FSubPage := TGittanSubPage.Create(Self);
  FSubPage.Parent := FSummaryBox;
  FSubPage.Visible := False;
  FSubPage.OnOpenUrl := @SummaryOpenUrl;
  FSubPage.OnCopyCommit := @SubPageCopyCommit;
  { The notice over the form, with the same icon. }
  FNotice := TGittanNotice.Create(Self);
  FNotice.Parent := Self;
  FNotice.SetIcon(FAppIcon);
  FNotice.OnButton := @NoticeButton;
  FNoticeTimer := TTimer.Create(Self);
  FNoticeTimer.Enabled := False;
  FNoticeTimer.Interval := NoticeDelay;
  FNoticeTimer.OnTimer := @NoticeTimerTimer;
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
  SetupCommit;
  SetupTitleBar;
  ApplySettings;
  BuildMenu;
  {$IFDEF OWNBAR}
  { The title bar lists the menus. }
  FOwnBar.Layout;
  {$ENDIF}
  {$IFDEF LCLGtk3}
  TGittanGtkTitleBar(FOwnBar).HideNativeMenu;
  {$ENDIF}
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
  { After the repository, whose opening clears the banners. }
  CheckGitVersion;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  Application.RemoveAsyncCalls(Self);
  AbandonMessageJob;
  AbandonAIReview;
  StopCommitJob(True);
  FreeAndNil(FDroppedCommits);
  StopRemoteJob(True);
  StopWatcher;
  AbandonPullJob;
  AbandonReviewJob;
  AbandonUpdateJob;
  AbandonSubmoduleJobs;
  FreeAndNil(FSubJobs);
  ClearRevertUndo;
  FreeAndNil(FKeeps);
  FreeAndNil(FLeftOut);
  FreeAndNil(FRawChangeLines);
  FRevertUndo.Free;
  FBranchNames.Free;
  FBranchRefs.Free;
  FGoneToDelete.Free;
  FUpstreamRows.Free;
  FGoneBranches.Free;
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
  {$IFDEF LCLCocoa}
  FreeAndNil(FToolbar);
  {$ENDIF}
  FreeAndNil(FChangeLines);
  FreeAndNil(FIndex);
  FreeAndNil(FIndexQueue);
  FreeAndNil(FSymbolFiles);
  FreeAndNil(FThreadFlips);
  FreeAndNil(FReviewMeasure);
  FreeAndNil(FCommitOn);
  FreeAndNil(FCommitOff);

  FreeAndNil(FSettings);
end;

{ The options both editors share: read-only, every line numbered (the
  change view numbers lines itself, see SetRowNumbers, and the file view
  should look the same), fold icons only under the mouse, and the line
  states band hidden until a diff is shown. }
procedure TForm1.SetupEditor(AEd: TATSynEdit);
var
  Actions: TATEditorMouseActions;
begin
  AEd.ModeReadOnly := True;
  {$IFDEF LCLGtk3}
  { ATSynEdit paints into a bitmap of its own only where the widgetset
    can draw outside Paint (EditorDoubleBufferedNeeded), and straight
    onto the control elsewhere. gtk3 cannot, and unbuffered every blink
    of the caret invalidated the editor, which GTK cleared to its
    background before ATSynEdit painted it again: a repository file open
    to edits flickered. With the bitmap a blink only blits it. The caret
    does not blink either: on a blink ATSynEdit first inverts the caret
    straight on the control's canvas, outside Paint, which gtk3 draws
    onto the window outside its frame, so the caret flashed out of step
    with the bitmap blitted after it; a still caret is drawn from the
    bitmap alone. }
  AEd.DoubleBuffered := True;
  AEd.OptCaretBlinkEnabled := False;
  {$ENDIF}
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
  AEd.OptTabSize := FTabSize;
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
  { The fold band is shown where FoldingShown allows (see SetFoldBand),
    its icons only under the mouse. Folding itself stays enabled everywhere,
    since the wrap info skips hidden lines only then, and only while a
    fold range exists (see FillChangeEditor). }
  AEd.OptGutterShowFoldAlways := False;
  SetFoldBand(AEd, False);
  { A row followed by hidden lines gets a dashed underline; the gap row
    already says what is left out. }
  ATEditorOptions.FoldedUnderlineStyle := TATEditorFoldedUnderlineStyle.None;
  SetLineStatesBand(AEd, False);
  { The blame band, leftmost, hidden until View > Blame; the editor
    leaves its size alone (see SetBlameBand). }
  AEd.Gutter.Add(0, 0, gutterTagBlame, False, False);
  { The initials band, next to the text, shown in the history view (see
    SetInitialBand). }
  AEd.Gutter.Add(-1, 0, gutterTagInitial, False, False);
  { The discard band, rightmost, shown with a changed file (see
    SetDiscardBand). }
  AEd.Gutter.Add(-1, 0, gutterTagDiscard, False, False);
  AEd.OnClickGutter := @EditClickGutter;
  { The cards of the review comments (see umain.reviews.inc). }
  AEd.OnDrawGap := @EditDrawGap;
  AEd.OnClickGap := @EditClickGap;
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
  it, so the timer asks every other second; the check is a system color or
  registry lookup. }
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
  The native controls follow the desktop theme by themselves, on Windows
  through MetaDarkStyle (Gittan.lpr). The editor has
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
      { A folded range in the file view: its first line, dimmed, in a
        grey frame like the navigator pills. }
      CollapseLine := RGBToColor(85, 85, 86);
      CollapseMarkFont := RGBToColor(150, 150, 150);
      CollapseMarkBG := RGBToColor(50, 50, 51);
      CollapseMarkBorder := RGBToColor(85, 85, 86);
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

function TForm1.Palette: TGittanPalette;
begin
  Result.Shade := SidebarShade(FDark);
  if FDark then
  begin
    Result.Text := Edit.Colors.TextFont;
    Result.Dim := RGBToColor(150, 150, 150);
    Result.Line := RGBToColor(62, 62, 62);
    Result.Popup := Result.Shade;
    Result.Hover := RGBToColor(58, 58, 59);
    Result.Border := RGBToColor(85, 85, 86);
    Result.Raised := RGBToColor(58, 58, 59);
    Result.Accent := RGBToColor(100, 160, 240);
    Result.Added := RGBToColor(63, 185, 80);
    Result.Deleted := RGBToColor(248, 81, 73);
    Result.Warning := RGBToColor(227, 179, 65);
    Result.Pill := RGBToColor(50, 50, 51);
    Result.PillText := RGBToColor(200, 200, 200);
    Result.NoteInfo := RGBToColor(33, 44, 58);
    Result.NoteInfoLine := RGBToColor(44, 66, 92);
    Result.NoteError := RGBToColor(56, 34, 36);
    Result.NoteErrorLine := RGBToColor(100, 50, 54);
  end
  else
  begin
    Result.Text := RGBToColor(30, 30, 30);
    Result.Dim := RGBToColor(110, 110, 110);
    Result.Line := RGBToColor(222, 222, 222);
    Result.Popup := clWhite;
    Result.Hover := RGBToColor(235, 235, 235);
    Result.Border := RGBToColor(205, 205, 205);
    Result.Raised := RGBToColor(232, 232, 232);
    Result.Accent := RGBToColor(0, 110, 230);
    Result.Added := RGBToColor(26, 127, 55);
    Result.Deleted := RGBToColor(207, 34, 46);
    Result.Warning := RGBToColor(154, 103, 0);
    Result.Pill := clWhite;
    Result.PillText := RGBToColor(70, 70, 70);
    Result.NoteInfo := RGBToColor(234, 243, 252);
    Result.NoteInfoLine := RGBToColor(200, 222, 245);
    Result.NoteError := RGBToColor(253, 236, 236);
    Result.NoteErrorLine := RGBToColor(242, 198, 198);
  end;
end;

procedure TForm1.ApplyTheme;
var
  P: TGittanPalette;
  List: TGittanPopupList;
begin
  ApplyEditorColors(Edit);
  ApplyEditorColors(FEditOld);
  FLexers.ApplyTheme(FDark, FSyntaxTheme);
  { The graph's lanes take the history view's hues. }
  FGraph.SetLaneColors([HistoryColor(0, htSwatch), HistoryColor(1, htSwatch),
    HistoryColor(2, htSwatch), HistoryColor(3, htSwatch), HistoryColor(4, htSwatch),
    HistoryColor(5, htSwatch)]);
  { The header and the find bar take the gutter's shade; the navigator
    pills sit on it. }
  P := Palette;
  FHeader.SetColors(P.Shade, P.Text, P.Dim, P.Added, P.Deleted, P.Line);
  FHeader.SetPillColors(P.Pill, P.Border, P.Accent);
  FNav.SetColors(P.Shade, P.Pill, P.Border, P.PillText, P.Accent);
  FFindBar.SetColors(P.Shade, P.Text, P.Dim, P.Line);
  FFindBar.Nav.SetColors(P.Shade, P.Pill, P.Border, P.PillText, P.Accent);
  FSymbolBar.SetColors(P.Shade, P.Text, P.Dim, P.Line);
  for List in [FBranchPopup, FStashPopup, FUpstreamPopup, FTagPopup, FViewPopup,
    FSubListPopup, FReflogPopup, FPullPopup, FSyncPopup, FRecentPopup, FBasePopup,
    FConflictPopup] do
    List.SetColors(P.Popup, P.Text, P.Dim, P.Hover, P.Border, P.Accent);
  FGraph.SetColors(P.Popup, P.Text, P.Dim, P.Hover, P.Border, P.Accent, P.Warning);
  FBanner.SetColors(P.Shade, P.Text, P.Dim, P.Line, P.Line, P.Accent, P.Deleted, P.Added);
  FDiscardPills.SetColors(P.Popup, P.Text, P.Border, P.Accent, P.Added, P.Deleted);
  FStatus.SetColors(P.Shade, P.Text, P.Dim, P.Line, P.Raised, P.Accent, P.Added,
    P.Warning, P.Deleted);
  FPullFill := P.Pill;
  FPullBorder := P.Border;
  FPullText := P.PillText;
  FBandTrack := P.Line;
  FBandFill := P.Accent;
  if FDark then
  begin
    FImageDiff.SetColors(Edit.Colors.TextBG, Edit.Colors.TextFont, P.Dim, P.Line, P.Deleted,
      P.Added, RGBToColor(58, 58, 60), RGBToColor(44, 44, 46));
    FBinaryView.SetColors(Edit.Colors.TextBG, Edit.Colors.TextFont, P.Dim,
      RGBToColor(44, 44, 46));
    FHeader.ConflictNav.SetColors(P.Shade, RGBToColor(58, 46, 68),
      RGBToColor(120, 80, 160), RGBToColor(210, 170, 245), RGBToColor(240, 215, 255));
    { The notice's accent is the light one in both, its red a softer one. }
    FNotice.SetColors(P.Popup, P.Text, P.Dim, P.Hover, P.Border, RGBToColor(0, 110, 230),
      RGBToColor(241, 112, 112));
    FPullBar := RGBToColor(40, 80, 130);
    FLinkColor := RGBToColor(78, 161, 255);
  end
  else
  begin
    FImageDiff.SetColors(Edit.Colors.TextBG, Edit.Colors.TextFont, P.Dim, P.Line, P.Deleted,
      P.Added, RGBToColor(255, 255, 255), RGBToColor(230, 230, 230));
    FBinaryView.SetColors(Edit.Colors.TextBG, Edit.Colors.TextFont, P.Dim, P.Shade);
    FHeader.ConflictNav.SetColors(P.Shade, RGBToColor(248, 240, 255),
      RGBToColor(190, 160, 220), RGBToColor(110, 50, 160), RGBToColor(155, 63, 200));
    FNotice.SetColors(P.Popup, P.Text, P.Dim, P.Hover, P.Border, P.Accent,
      RGBToColor(200, 40, 40));
    FPullBar := RGBToColor(205, 225, 250);
    FLinkColor := RGBToColor(0, 102, 204);
  end;
  FSummaryBox.Color := Edit.Colors.TextBG;
  if FDark then
    FMdPreview.SetColors(Edit.Colors.TextBG, Edit.Colors.TextFont,
      RGBToColor(62, 62, 62), FLinkColor, True)
  else
    FMdPreview.SetColors(Edit.Colors.TextBG, RGBToColor(30, 30, 30),
      RGBToColor(222, 222, 222), FLinkColor, False);
  FSummary.LinkColor := FLinkColor;
  if FDark then
  begin
    FSummary.SetColors(Edit.Colors.TextBG, Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(45, 45, 46), RGBToColor(38, 38, 39),
      RGBToColor(63, 185, 80), RGBToColor(248, 81, 73), RGBToColor(62, 62, 62));
    FWelcome.SetColors(Edit.Colors.TextBG, Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(45, 45, 46), RGBToColor(85, 85, 86),
      RGBToColor(248, 81, 73));
    FRepoPage.SetColors(Edit.Colors.TextBG, Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(50, 50, 51), RGBToColor(62, 62, 62),
      FLinkColor, FLinkColor, RGBToColor(248, 81, 73));
    FRepoPage.SetCardColor(RGBToColor(40, 40, 41));
    FCommandPage.SetColors(Edit.Colors.TextBG, Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(50, 50, 51), RGBToColor(62, 62, 62),
      FLinkColor, RGBToColor(63, 185, 80), RGBToColor(248, 81, 73));
    FCommandPage.SetCardColor(RGBToColor(40, 40, 41));
    FCommandPage.Console.SetColors(Edit.Colors.TextBG, Edit.Colors.TextFont,
      RGBToColor(62, 62, 62));
    FFilesPage.SetColors(Edit.Colors.TextBG, Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(50, 50, 51), RGBToColor(62, 62, 62),
      FLinkColor, RGBToColor(248, 81, 73));
    FPullPage.SetColors(Edit.Colors.TextBG, Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(50, 50, 51), RGBToColor(62, 62, 62),
      FLinkColor, RGBToColor(63, 185, 80), RGBToColor(227, 179, 65), RGBToColor(248, 81, 73));
    FPullPage.SetCardColor(RGBToColor(40, 40, 41));
    FSubPage.SetColors(Edit.Colors.TextBG, Edit.Colors.TextFont,
      RGBToColor(150, 150, 150), RGBToColor(45, 45, 46), RGBToColor(62, 62, 62),
      RGBToColor(40, 40, 41), FLinkColor, RGBToColor(63, 185, 80),
      RGBToColor(227, 179, 65), RGBToColor(248, 81, 73));
  end
  else
  begin
    FSummary.SetColors(Edit.Colors.TextBG, RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(243, 243, 243), RGBToColor(248, 248, 248),
      RGBToColor(26, 127, 55), RGBToColor(207, 34, 46), RGBToColor(222, 222, 222));
    FWelcome.SetColors(Edit.Colors.TextBG, RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(243, 243, 243), RGBToColor(205, 205, 205),
      RGBToColor(207, 34, 46));
    FRepoPage.SetColors(Edit.Colors.TextBG, RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(235, 235, 235), RGBToColor(222, 222, 222),
      FLinkColor, FLinkColor, RGBToColor(207, 34, 46));
    FRepoPage.SetCardColor(RGBToColor(245, 245, 246));
    FCommandPage.SetColors(Edit.Colors.TextBG, RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(235, 235, 235), RGBToColor(222, 222, 222),
      FLinkColor, RGBToColor(26, 127, 55), RGBToColor(207, 34, 46));
    FCommandPage.SetCardColor(RGBToColor(245, 245, 246));
    FCommandPage.Console.SetColors(Edit.Colors.TextBG, RGBToColor(30, 30, 30),
      RGBToColor(222, 222, 222));
    FFilesPage.SetColors(Edit.Colors.TextBG, RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(235, 235, 235), RGBToColor(222, 222, 222),
      FLinkColor, RGBToColor(207, 34, 46));
    FPullPage.SetColors(Edit.Colors.TextBG, RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(235, 235, 235), RGBToColor(222, 222, 222),
      FLinkColor, RGBToColor(26, 127, 55), RGBToColor(154, 103, 0), RGBToColor(207, 34, 46));
    FPullPage.SetCardColor(RGBToColor(245, 245, 246));
    FSubPage.SetColors(Edit.Colors.TextBG, RGBToColor(30, 30, 30),
      RGBToColor(110, 110, 110), RGBToColor(243, 243, 243), RGBToColor(222, 222, 222),
      RGBToColor(245, 245, 246), FLinkColor, RGBToColor(26, 127, 55),
      RGBToColor(154, 103, 0), RGBToColor(207, 34, 46));
  end;
  { The contributors take the graph's lane colors. }
  FRepoPage.SetLaneColors([HistoryColor(0, htSwatch), HistoryColor(1, htSwatch),
    HistoryColor(2, htSwatch), HistoryColor(3, htSwatch), HistoryColor(4, htSwatch),
    HistoryColor(5, htSwatch)]);
  if FRepoHeader <> nil then
    ColorRepoHeader;
  ColorCommit;
  ColorSidebar;
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
  Lexer, Sync, Op: string;
  Tone: TGittanStatusTone;
  Checks, OpPos, OpTotal: integer;
begin
  if FView = gvImage then
    Lexer := ImageFormatName(FCurrentPath)
  else if (FView = gvBlob) and FImageDiff.Visible then
    Lexer := ImageFormatName(FBlobPath)
  else if FView = gvTranslation then
    Lexer := FPoStats
  else if (FView in [gvBinary, gvSubmodule]) or ((FView = gvBlob) and FBinaryView.Visible) then
    Lexer := ''
  else if FAdapter.Lexer = nil then
    Lexer := rsPlainText
  else
    Lexer := FAdapter.Lexer.LexerName;
  FHeader.SetLexer(Lexer);
  UpdatePreviewToggle;
  UpdateSyntaxChecks;
  if FRepo.Root = '' then
  begin
    FStatus.SetRepository(Edit.FileName, '');
    if Edit.FileName <> '' then
      FStatus.PartHint[spRepo] := HintFolder + ' ' + Edit.FileName
    else
      FStatus.PartHint[spRepo] := '';
    FStatus.SetSync(0, 0, False);
    FStatus.SetStashes(0);
    FStatus.SetOperation('', 0, 0);
    FStatus.SetTransport(StatusButton('', ''), StatusButton('', ''), StatusButton('', ''));
    FStatus.SetBase('');
    FStatus.SetPull('', '', stNormal, 0);
    FStatus.SetPullThreads(0, 0);
    FStatus.SetFiles('');
    FStatus.SetProgress('', 0, 0);
    Exit;
  end;
  FStatus.SetRepository(ExtractFileName(FRepo.Root), FBranch);
  FStatus.PartHint[spRepo] := HintFolder + ' ' + FRepo.Root;
  if FHasUpstream then
    FStatus.SetSync(FAhead, FBehind, True)
  else
    FStatus.SetSync(Max(0, FNotOnRemote), 0, True);
  { The counts, or that there is nothing to push or pull, then what a
    click does. }
  Sync := '';
  if FHasUpstream and (FAhead > 0) then
    Sync := Format(rsAheadHint, [FAhead]);
  if FHasUpstream and (FBehind > 0) then
    Sync := Trim(Sync + LineEnding + Format(rsBehindHint, [FBehind]));
  if Sync = '' then
  begin
    if FHasUpstream then
      Sync := rsInSyncHint
    else if FNotOnRemote > 0 then
      Sync := rsNoUpstreamHint + LineEnding + Format(rsNotOnRemoteHint, [FNotOnRemote])
    else
      Sync := rsNoUpstreamHint;
  end;
  FStatus.PartHint[spSync] := HintSync + ' ' + Sync + LineEnding + rsGraphHint;
  FStatus.SetStashes(Length(FStashes));
  if Length(FStashes) = 1 then
    FStatus.PartHint[spStash] := HintStash + ' ' + rsStashHintOne + LineEnding + rsStashListHint
  else
    FStatus.PartHint[spStash] := HintStash + ' ' + Format(rsStashesHint, [Length(FStashes)]) +
      LineEnding + rsStashListHint;
  { What git is in the middle of, on the track, with a rebase's steps. }
  if FOperation = '' then
    FStatus.SetOperation('', 0, 0)
  else
  begin
    Op := OperationLabel;
    Op := UpperCase(Copy(Op, 1, 1)) + Copy(Op, 2, MaxInt);
    if FRepo.OperationProgress(OpPos, OpTotal) then
      Op := Format(rsOperationStep, [Op, OpPos, OpTotal]);
    FStatus.SetOperation(Op, OpPos, OpTotal);
  end;
  UpdateStatusTransport;
  FStatus.SetBase(BaseLabel, (BaseActionRef <> '') or (StashOfBase >= 0) or BlameShown);
  if BaseActionRef <> '' then
    FStatus.PartHint[spBase] := rsBaseActionsHint
  else if BlameShown then
    FStatus.PartHint[spBase] := rsBlameActionsHint
  else if StashOfBase >= 0 then
    FStatus.PartHint[spBase] := rsStashActionsHint
  else
    FStatus.PartHint[spBase] := '';
  { The page marks the pull request compared against. }
  if FPullPage <> nil then
    if (FPullRange <> '') and (FRepo.Base = FPullRange) and FRepo.IsRange then
      FPullPage.SetComparing(FPullNumber)
    else
      FPullPage.SetComparing(0);
  if FHasPull then
  begin
    Tone := PullChecks(FPull, Checks);
    FStatus.SetPull('#' + IntToStr(FPull.Number), PullRequestNote(FPull), Tone, Checks);
    FStatus.PartHint[spPull] := PullHint(FPull);
    if FShowComments and (FThreadsNumber = FPull.Number) then
      FStatus.SetPullThreads(OpenThreads(FThreads), Length(FThreads))
    else
      FStatus.SetPullThreads(0, 0);
  end
  else
  begin
    FStatus.SetPull('', '', stNormal, 0);
    FStatus.SetPullThreads(0, 0);
  end;
  if FIndexing then
    FStatus.SetProgress(Format(rsIndexing, [FIndexPos, FIndexTotal]),
      FIndexPos, FIndexTotal)
  else
    FStatus.SetProgress('', 0, 0);
  UpdateIndexBand;
  case FFileCount of
    0: FStatus.SetFiles(rsNoChanges);
    1: FStatus.SetFiles(rsOneChangedFile);
    else
      FStatus.SetFiles(Format(rsChangedFiles, [FFileCount]));
  end;
end;

function OperationNoun(const AOperation: string): string; forward;

{ The transport in the middle of the status bar: the primary button is
  the next step, with what else can be done on its sides. While git is
  in the middle of something they are Abort, then Resolve (the
  conflicts) or Continue (Commit Merge for a merge), then Skip where
  the operation can skip a commit. Otherwise Fetch, then Pull with
  commits to pull (also when both sides moved on), Force Push when the
  branch was rewritten since it was pushed (then Pull beside it), Push
  with commits to push or no upstream yet, or Up to date, which does
  nothing, then Push or Pull as the other one. The buttons rest while a remote job or a
  commit runs. The side buttons' captions are their hints. }
procedure TForm1.UpdateStatusTransport;
var
  L, P, R: TGittanStatusButton;
  Busy: boolean;
  Noun, Tip: string;
begin
  Busy := (FRemoteJob <> nil) or (FCommitJob <> nil);
  FStatusSteps[spLeft] := stepNone;
  FStatusSteps[spPrimary] := stepNone;
  FStatusSteps[spRight] := stepNone;
  R := StatusButton('', '');
  if (FOperation <> '') and (FOperation <> 'bisecting') then
  begin
    Noun := OperationNoun(FOperation);
    L := StatusButton(Format(rsAbortStepHint, [Noun]), HintFailed, stNormal, not Busy);
    FStatusSteps[spLeft] := stepAbort;
    if FConflictFiles > 0 then
    begin
      if FConflictFiles = 1 then
        P := StatusButton(rsResolveOneStep, HintWarn, stBad, not Busy)
      else
        P := StatusButton(Format(rsResolveStep, [FConflictFiles]), HintWarn, stBad, not Busy);
      FStatusSteps[spPrimary] := stepResolve;
      Tip := rsShowConflictHint;
    end
    else if FOperation = 'merging' then
    begin
      P := StatusButton(rsCommitMergeButton, HintPlay, stNormal, not Busy);
      FStatusSteps[spPrimary] := stepCommit;
      Tip := rsCommitMergeButton;
    end
    else
    begin
      P := StatusButton(rsContinueButton, HintPlay, stNormal, not Busy and ContinueMode);
      FStatusSteps[spPrimary] := stepContinue;
      if StrayRebase then
        Tip := Format(rsStrayRebaseNote, [FRebaseBranch, FBranch])
      else
        Tip := Format(rsContinueNote, [Noun]);
    end;
    if ContinueMode then
    begin
      R := StatusButton(Format(rsSkipStepHint, [Noun]), HintSkip, stNormal, not Busy);
      FStatusSteps[spRight] := stepSkip;
    end;
  end
  else
  begin
    L := StatusButton(rsFetchStepHint, HintFetch, stNormal, not Busy);
    FStatusSteps[spLeft] := stepFetch;
    if not FHasUpstream then
    begin
      P := StatusButton(rsPushItem, HintUp, stNormal, not Busy);
      FStatusSteps[spPrimary] := stepPush;
      Tip := HintSync + ' ' + rsNoUpstreamHint + LineEnding + rsPushNewBranchHint;
      R := StatusButton(rsGitPullItem, HintDown, stNormal, False);
      FStatusSteps[spRight] := stepPull;
    end
    else if FRewritten and (FAhead > 0) and (FBehind > 0) then
    begin
      { Pulling would bring the replaced commits back. }
      P := StatusButton(rsForcePushItem, HintUp, stNormal, not Busy);
      FStatusSteps[spPrimary] := stepForcePush;
      Tip := HintSync + ' ' + rsRewrittenHint + LineEnding;
      if FBehind = 1 then
        Tip := Tip + rsRewrittenReplacesOne
      else
        Tip := Tip + Format(rsRewrittenReplaces, [FBehind]);
      Tip := Tip + LineEnding + rsForcePushStepHint;
      R := StatusButton(rsGitPullItem, HintDown, stNormal, not Busy);
      FStatusSteps[spRight] := stepPull;
    end
    else if FBehind > 0 then
    begin
      P := StatusButton(rsGitPullItem, HintDown, stNormal, not Busy);
      FStatusSteps[spPrimary] := stepPull;
      Tip := HintSync + ' ' + Format(rsBehindHint, [FBehind]);
      if FAhead > 0 then
        Tip := Tip + LineEnding + Format(rsAheadHint, [FAhead]) + LineEnding + rsDivergedHint;
      Tip := Tip + LineEnding + rsPullStepHint;
      R := StatusButton(rsPushItem, HintUp, stNormal, not Busy and (FAhead > 0));
      FStatusSteps[spRight] := stepPush;
    end
    else if FAhead > 0 then
    begin
      P := StatusButton(rsPushItem, HintUp, stNormal, not Busy);
      FStatusSteps[spPrimary] := stepPush;
      Tip := HintSync + ' ' + Format(rsAheadHint, [FAhead]) + LineEnding + rsPushStepHint;
      R := StatusButton(rsGitPullItem, HintDown, stNormal, not Busy);
      FStatusSteps[spRight] := stepPull;
    end
    else
    begin
      P := StatusButton(rsUpToDateStep, HintPassed, stGood, False);
      Tip := HintPassed + ' ' + rsInSyncHint;
      R := StatusButton(rsPushItem, HintUp, stNormal, False);
      FStatusSteps[spRight] := stepPush;
    end;
  end;
  FStatus.SetTransport(L, P, R);
  FStatus.PartHint[spLeft] := L.Caption;
  FStatus.PartHint[spPrimary] := Tip;
  FStatus.PartHint[spRight] := R.Caption;
end;

procedure TForm1.StatusNote(const AText: string; AError: boolean);
var
  S: string;
  i: integer;
begin
  if AError then
  begin
    S := Trim(AText);
    i := Pos(LineEnding, S);
    if i > 0 then
      BannerError(Copy(S, 1, i - 1), Copy(S, i + Length(LineEnding), MaxInt))
    else
      BannerError(S, '');
  end
  else
    FStatus.ShowMessage(AText, stNormal, StatusNoteSeconds);
end;

procedure TForm1.BannerError(const ATitle, ADetail: string);
begin
  FBanner.DetailFont.Assign(Edit.Font);
  FBanner.Add(ATitle, ADetail, bkError);
end;

procedure TForm1.BannerInfo(const ATitle: string; const ADetail: string);
begin
  FBanner.DetailFont.Assign(Edit.Font);
  FBanner.Add(ATitle, ADetail, bkInfo, BannerInfoSeconds);
end;

procedure TForm1.BannerSuccess(const ATitle: string; const ADetail: string);
begin
  FBanner.DetailFont.Assign(Edit.Font);
  FBanner.Add(ATitle, ADetail, bkSuccess, BannerInfoSeconds);
end;

procedure TForm1.BannerChange(Sender: TObject);
begin
  PlaceUnderTitleBar;
end;

{ The banner is the first alTop control of the panel when shown (Top 0
  puts it before the header), and takes the strip's height as its own
  spacing so the header under it does not leave a gap. }
procedure TForm1.PlaceUnderTitleBar;
begin
  EditorPanel.DisableAlign;
  try
    if FBanner.Visible then
    begin
      FBanner.BorderSpacing.Top := FTitleBarHeight;
      FBanner.Top := 0;
      FHeader.BorderSpacing.Top := 0;
      FSummaryBox.BorderSpacing.Top := 0;
    end
    else
    begin
      FBanner.BorderSpacing.Top := 0;
      FHeader.BorderSpacing.Top := FTitleBarHeight;
      { The page of a submodule has the header over the box. }
      if FHeader.Visible then
        FSummaryBox.BorderSpacing.Top := 0
      else
        FSummaryBox.BorderSpacing.Top := FTitleBarHeight;
    end;
  finally
    EditorPanel.EnableAlign;
  end;
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
  if (Edit.Carets.Count = 0) or not ((FView in [gvChanges, gvFile]) or
    ((FView = gvBlob) and not FImageDiff.Visible and not FBinaryView.Visible)) then
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
  FileMenu, BranchMenu, StashMenu, ViewMenu, GoMenu, ToolsMenu, Item, Sub: TMenuItem;
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
  { On macOS About Gittan and Settings are in the application menu,
    which the LCL builds when the menu is set, with these items first,
    before Services. }
  {$IFDEF LCLCocoa}
  Item := TMenuItem.Create(Self);
  AddItem(Item, rsAbout, 0, @MenuAboutClick);
  Item.Add(NewLine);
  AddItem(Item, rsSettings, ShortCut(VK_OEM_COMMA, [ssModifier]), @MenuSettingsClick);
  CocoaConfigMenu.appMenu.customMenus := Item;
  {$ENDIF}
  Menu := Main;

  FileMenu := TMenuItem.Create(Main);
  FileMenu.Caption := rsFile;
  Main.Items.Add(FileMenu);
  AddItem(FileMenu, rsOpenRepo, ShortCut(VK_O, [ssModifier, ssShift]), @MenuOpenRepoClick);
  FRecentMenu := AddItem(FileMenu, rsOpenRecent, 0, nil);
  RebuildRecentMenu;
  FCloneItem := AddItem(FileMenu, rsCloneItem, 0, @MenuCloneClick);
  FInitItem := AddItem(FileMenu, rsInitItem, 0, @MenuInitClick);
  AddItem(FileMenu, rsOpen, ShortCut(VK_O, [ssModifier]), @MenuOpenClick);
  FSaveItem := AddItem(FileMenu, rsSave, ShortCut(VK_S, [ssModifier]), @MenuSaveClick);
  FSaveItem.Enabled := False;
  FileMenu.Add(NewLine);
  FCommitItem := AddItem(FileMenu, rsCommitMenu, ShortCut(VK_K, [ssModifier]),
    @MenuCommitClick);
  FCommitItem.Enabled := False;
  FMessageItem := AddItem(FileMenu, rsWriteMessageMenu, ShortCut(VK_K, [ssModifier,
    ssShift]), @MessageActionClick);
  FMessageItem.Visible := False;
  FPullItem := AddItem(FileMenu, rsPullMenu, ShortCut(VK_L, [ssModifier, ssShift]),
    @MenuPullClick);
  FPushItem := AddItem(FileMenu, rsPushMenu, ShortCut(VK_P, [ssModifier, ssShift]),
    @MenuPushClick);
  FForcePushItem := AddItem(FileMenu, rsForcePushMenu, ShortCut(VK_P, [ssModifier, ssShift,
    ssAlt]), @MenuForcePushClick);
  FFetchItem := AddItem(FileMenu, rsFetchMenu, ShortCut(VK_F, [ssModifier, ssAlt]),
    @MenuFetchClick);
  FRemotesItem := AddItem(FileMenu, rsRemotesItem, 0, @MenuRemotesClick);
  Sub := AddItem(FileMenu, rsSubmodulesMenu, 0, nil);
  FSubUpdateAllItem := AddItem(Sub, rsSubUpdateAllItem, 0, @MenuSubUpdateAllClick);
  FSubSyncAllItem := AddItem(Sub, rsSubSyncAllItem, 0, @MenuSubSyncAllClick);
  Sub.Add(NewLine);
  FSubAddItem := AddItem(Sub, rsSubAddItem, 0, @MenuSubAddClick);
  UpdateRemoteItems;
  FileMenu.Add(NewLine);
  FDiscardItem := AddItem(FileMenu, rsDiscardChange, ShortCut(VK_BACK, [ssModifier, ssShift]),
    @MenuDiscardClick);
  FUndoDiscardItem := AddItem(FileMenu, rsUndoDiscard, ShortCut(VK_Z, [ssModifier, ssAlt]),
    @MenuUndoDiscardClick);
  FLeaveOutItem := AddItem(FileMenu, rsLeaveOutItem, ShortCut(VK_K, [ssModifier, ssAlt]),
    @MenuLeaveOutClick);
  FResolveItem := AddItem(FileMenu, rsResolveHere, ShortCut(VK_R, [ssModifier, ssShift]),
    @MenuResolveHereClick);
  FRevertFileItem := AddItem(FileMenu, rsRevertFile, ShortCut(VK_BACK, [ssModifier, ssAlt]),
    @MenuRevertFileClick);
  FUndoRevertItem := AddItem(FileMenu, rsUndoRevert, 0, @MenuUndoRevertClick);
  FCleanItem := AddItem(FileMenu, rsCleanItem, 0, @MenuCleanClick);
  FApplyPatchesItem := AddItem(FileMenu, rsApplyPatchesItem, 0, @MenuApplyPatchesClick);
  UpdateDiscardItems;
  FileMenu.OnClick := @FileMenuClick;
  FileMenu.Add(NewLine);
  FTerminalItem := AddItem(FileMenu, rsOpenTerminal, ShortCut(VK_T, [ssModifier, ssAlt]),
    @MenuOpenTerminalClick);

  FTerminalItem.Enabled := False;

  { The Branch menu: the verb first, then the branch from the list
    (umain.branches.inc). }
  BranchMenu := TMenuItem.Create(Main);
  BranchMenu.Caption := rsBranchMenu;
  BranchMenu.OnClick := @BranchMenuOpen;
  Main.Items.Add(BranchMenu);
  FSwitchItem := AddItem(BranchMenu, rsBmSwitchItem, ShortCut(VK_B, [ssModifier]),
    @MenuBranchListClick);
  FSwitchItem.Tag := Ord(blSwitch);
  FNewBranchItem := AddItem(BranchMenu, rsBmNewItem, 0, @MenuNewBranchClick);
  BranchMenu.Add(NewLine);
  FMergeItem := AddItem(BranchMenu, '', 0, @MenuBranchListClick);
  FMergeItem.Tag := Ord(blMerge);
  FRebaseItem := AddItem(BranchMenu, '', 0, @MenuBranchListClick);
  FRebaseItem.Tag := Ord(blRebase);
  BranchMenu.Add(NewLine);
  FCompareBranchItem := AddItem(BranchMenu, '', 0, @MenuBranchListClick);
  FCompareBranchItem.Tag := Ord(blBranchSince);
  FCompareBackItem := AddItem(BranchMenu, '', 0, @MenuBranchListClick);
  FCompareBackItem.Tag := Ord(blCurrentSince);
  BranchMenu.Add(NewLine);
  FUpstreamItem := AddItem(BranchMenu, '', 0, @MenuUpstreamClick);
  BranchMenu.Add(NewLine);
  FTagsItem := AddItem(BranchMenu, rsTagsItem, 0, @MenuTagsClick);
  FNewTagItem := AddItem(BranchMenu, rsNewTagItem, 0, @MenuNewTagClick);
  FPushTagsItem := AddItem(BranchMenu, rsPushTagsItem, 0, @MenuPushTagsClick);
  BranchMenu.Add(NewLine);
  FReflogItem := AddItem(BranchMenu, rsReflogItem, 0, @MenuReflogClick);
  UpdateBranchItems;

  { The Stash menu (umain.stash.inc). }
  StashMenu := TMenuItem.Create(Main);
  StashMenu.Caption := rsStashMenu;
  StashMenu.OnClick := @StashMenuOpen;
  Main.Items.Add(StashMenu);
  FStashAllItem := AddItem(StashMenu, rsStashAllItem, ShortCut(VK_S, [ssModifier, ssAlt]),
    @MenuStashAllClick);
  FStashChosenItem := AddItem(StashMenu, rsStashChosenItem, 0, @MenuStashChosenClick);
  StashMenu.Add(NewLine);
  FPopStashItem := AddItem(StashMenu, rsPopStashItem,
    ShortCut(VK_S, [ssModifier, ssAlt, ssShift]), @MenuPopStashClick);
  FApplyStashItem := AddItem(StashMenu, rsApplyStashItem, 0, @MenuApplyStashClick);
  StashMenu.Add(NewLine);
  FStashListItem := AddItem(StashMenu, rsStashListItem, 0, @MenuStashListClick);
  UpdateStashItems;

  ViewMenu := TMenuItem.Create(Main);
  ViewMenu.Caption := rsView;
  Main.Items.Add(ViewMenu);
  AddItem(ViewMenu, rsSummary, ShortCut(VK_1, [ssModifier]), @MenuSummaryClick);
  AddItem(ViewMenu, rsRepoInfo, ShortCut(VK_I, [ssModifier, ssShift]), @MenuRepoInfoClick);
  AddItem(ViewMenu, rsRepoDiff, ShortCut(VK_2, [ssModifier]), @MenuRepoDiffClick);
  AddItem(ViewMenu, rsCommitGraph, ShortCut(VK_3, [ssModifier]), @MenuCommitGraphClick);
  AddItem(ViewMenu, rsCommandsMenu, ShortCut(VK_4, [ssModifier]), @MenuCommandsClick);
  AddItem(ViewMenu, rsFilesMenu, ShortCut(VK_5, [ssModifier]), @MenuFilesClick);
  FPullsItem := AddItem(ViewMenu, rsPullRequests, ShortCut(VK_6, [ssModifier]),
    @MenuPullsClick);
  FPullsItem.Visible := FHasGitHubCli;
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
  FMdPreviewItem := AddItem(ViewMenu, rsMarkdownPreview, ShortCut(VK_V, [ssModifier, ssShift]),
    @MenuMarkdownPreviewClick);
  FMdPreviewItem.Checked := FMdPreviewOn;
  FWrapItem := AddItem(ViewMenu, rsWordWrap, ShortCut(VK_W, [ssModifier, ssAlt]),
    @MenuWrapClick);
  FWrapItem.Checked := FWordWrap;
  FFoldMenu := AddItem(ViewMenu, rsFolding, 0, nil);
  AddItem(FFoldMenu, rsFold, ShortCut(VK_OEM_MINUS, [ssModifier, ssAlt]),
    @MenuFoldClick).Tag := cCommand_FoldingFoldAtCurLine;
  AddItem(FFoldMenu, rsUnfold, ShortCut(VK_OEM_PLUS, [ssModifier, ssAlt]),
    @MenuFoldClick).Tag := cCommand_FoldingUnfoldAtCurLine;
  AddItem(FFoldMenu, rsFoldAll, ShortCut(VK_OEM_MINUS, [ssModifier, ssAlt, ssShift]),
    @MenuFoldClick).Tag := cCommand_FoldAll;
  AddItem(FFoldMenu, rsUnfoldAll, ShortCut(VK_OEM_PLUS, [ssModifier, ssAlt, ssShift]),
    @MenuFoldClick).Tag := cCommand_UnfoldAll;
  ViewMenu.OnClick := @ViewMenuClick;
  FIgnoreSpaceItem := AddItem(ViewMenu, rsIgnoreSpace, ShortCut(VK_I, [ssModifier, ssAlt]),
    @MenuIgnoreSpaceClick);
  FIgnoreSpaceItem.Checked := FIgnoreWhitespace;
  FBlameItem := AddItem(ViewMenu, rsBlame, ShortCut(VK_B, [ssModifier, ssShift]),
    @MenuBlameClick);
  FBlameItem.Checked := FBlameOn;
  FTranslationsItem := AddItem(ViewMenu, rsTranslations, ShortCut(VK_L, [ssModifier, ssAlt]),
    @MenuTranslationsClick);
  FTranslationsItem.Checked := FTranslations;
  FReviewItem := AddItem(ViewMenu, rsReviewComments, ShortCut(VK_M, [ssModifier, ssShift]),
    @MenuReviewCommentsClick);
  FReviewItem.Checked := FShowComments;
  FReviewItem.Enabled := FHasGitHubCli;
  FAIReviewItem := AddItem(ViewMenu, rsAIReviewMenu, ShortCut(VK_R, [ssModifier, ssAlt]),
    @MenuAIReviewClick);
  FAIReviewItem.Visible := False;
  FAIClearItem := AddItem(ViewMenu, rsAIClearMenu, 0, @MenuAIClearClick);
  FAIClearItem.Visible := False;
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
  FCodeHistoryItem := AddItem(GoMenu, rsHistory, ShortCut(VK_H, [ssModifier, ssShift]),
    @MenuHistoryClick);
  FGoFileHistoryItem := AddItem(GoMenu, rsGoFileHistory, 0, @MenuGoFileHistoryClick);
  GoMenu.Add(NewLine);
  AddItem(GoMenu, rsNextChange, ShortCut(VK_F7, []), @MenuNextChangeClick);
  AddItem(GoMenu, rsPrevChange, ShortCut(VK_F7, [ssShift]), @MenuPrevChangeClick);
  AddItem(GoMenu, rsNextConflict, ShortCut(VK_F6, []), @MenuNextConflictClick);
  AddItem(GoMenu, rsPrevConflict, ShortCut(VK_F6, [ssShift]), @MenuPrevConflictClick);
  GoMenu.Add(NewLine);
  AddItem(GoMenu, rsNextFile, ShortCut(VK_F8, []), @MenuNextFileClick);
  AddItem(GoMenu, rsPrevFile, ShortCut(VK_F8, [ssShift]), @MenuPrevFileClick);

  ToolsMenu := TMenuItem.Create(Main);
  ToolsMenu.Caption := rsTools;
  ToolsMenu.OnClick := @ToolsMenuClick;
  Main.Items.Add(ToolsMenu);
  AddItem(ToolsMenu, rsInstallCli, 0, @MenuInstallCliClick);
  FUninstallCliItem := AddItem(ToolsMenu, rsUninstallCli, 0, @MenuUninstallCliClick);
  ToolsMenu.Add(NewLine);
  AddItem(ToolsMenu, rsCheckUpdates, 0, @MenuCheckUpdatesClick);
  {$IFNDEF LCLCocoa}
  ToolsMenu.Add(NewLine);
  AddItem(ToolsMenu, rsSettings, ShortCut(VK_OEM_COMMA, [ssModifier]), @MenuSettingsClick);
  AddItem(ToolsMenu, rsAbout, 0, @MenuAboutClick);
  {$ENDIF}
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
    gvBlob: Result := FLexers.ForFile(FBlobPath, FRepo.Root);
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
  AEd.Gaps.Clear;
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

{ AFileName is not a const: callers pass FEditPath, which LeaveEdit
  clears, and a const would then name freed memory. }
procedure TForm1.OpenFile(AFileName: string);
begin
  FlushEdit;
  LeaveEdit;
  if FTranslations and IsPoPath(AFileName) then
  begin
    ShowTranslationFile(AFileName);
    UpdateChangeNav;
    Exit;
  end;
  if IsBinaryFile(AFileName) then
  begin
    ShowBinaryFile(AFileName);
    UpdateChangeNav;
    Exit;
  end;
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
    AColor := HistoryColor(ABookmarkKind - bmHistoryBase, htRow);
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
      bmFuzzy: AColor := RGBToColor(62, 52, 28);
      bmUntranslated: AColor := RGBToColor(66, 38, 38);
      bmLeftOutAdded: AColor := RGBToColor(38, 43, 39);
      bmLeftOutDeleted: AColor := RGBToColor(47, 39, 39);
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
      bmFuzzy: AColor := RGBToColor(255, 241, 208);
      bmUntranslated: AColor := RGBToColor(255, 235, 233);
      bmLeftOutAdded: AColor := RGBToColor(240, 245, 241);
      bmLeftOutDeleted: AColor := RGBToColor(248, 242, 241);
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
type
  THistoryPalette = array[0..5, THistoryTone] of array[0..2] of byte;

const
  { The colors of the history view's commits, taken in turn. Six hues
    in OKLCH (245 blue, 55 orange, 285 violet, 195 teal, 330 pink, 110
    olive), each tone at one lightness and chroma, so every hue looks as
    light as the others: the rows at L 0.935 (light) and 0.32 (dark),
    the words at 0.86 and 0.42, the swatch at 0.60 and 0.75, which
    keeps it at 3.4:1 or more against the background. The hues keep
    away from the diff's red and green, which mean deleted and added
    elsewhere, and are ordered so that neighbours differ the most. }
  HistoryLight: THistoryPalette = (
    ((204, 238, 255), (152, 216, 255), (4, 134, 211)),
    ((255, 225, 199), (255, 192, 145), (194, 99, 0)),
    ((229, 229, 255), (202, 200, 255), (121, 112, 213)),
    ((191, 246, 245), (122, 230, 229), (0, 154, 156)),
    ((255, 221, 251), (247, 185, 240), (176, 91, 170)),
    ((235, 237, 195), (213, 215, 137), (135, 134, 0)));
  HistoryDark: THistoryPalette = (
    ((21, 54, 79), (25, 81, 123), (96, 182, 250)),
    ((74, 42, 18), (114, 62, 20), (237, 150, 88)),
    ((48, 46, 80), (73, 69, 124), (166, 161, 253)),
    ((0, 60, 60), (0, 91, 92), (0, 199, 199)),
    ((68, 39, 65), (104, 57, 100), (220, 143, 213)),
    ((53, 53, 11), (80, 81, 3), (179, 181, 73)));
  { A line older than the history (commit -1) in the same lightness. }
  HistoryGreyLight: array[THistoryTone] of byte = (233, 209, 128);
  HistoryGreyDark: array[THistoryTone] of byte = (51, 77, 174);

{ The color of commit AIndex of the history view in tone ATone: the
  palette's colors in turn, as tints of the editor background in the
  way of the diff colors. A line older than the history (AIndex -1)
  gets a grey. }
function TForm1.HistoryColor(AIndex: integer; ATone: THistoryTone): TColor;
var
  C: array[0..2] of byte;
begin
  if AIndex < 0 then
  begin
    if FDark then
      C[0] := HistoryGreyDark[ATone]
    else
      C[0] := HistoryGreyLight[ATone];
    Exit(RGBToColor(C[0], C[0], C[0]));
  end;
  if FDark then
    C := HistoryDark[AIndex mod Length(HistoryDark), ATone]
  else
    C := HistoryLight[AIndex mod Length(HistoryLight), ATone];
  Result := RGBToColor(C[0], C[1], C[2]);
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
      Item.LinePart.ColorBG := HistoryColor(Item.TagEx, htWord);
      AEd.Attribs[i] := Item;
    end
    else if Item.Tag = tagHistorySwatch then
    begin
      Item.LinePart.ColorFont := HistoryColor(Item.TagEx, htSwatch);
      AEd.Attribs[i] := Item;
    end
    else if Item.Tag = tagPoContext then
    begin
      Item.LinePart.ColorFont := AEd.Colors.GutterFont;
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

{ Whether the shown text may be folded: in the file view, and in the
  unified change view while it hides no lines. Hide Unchanged Lines hides
  them through the folding mechanism (see BuildChangeView), which a fold
  or unfold of a lexer range would disturb; Side by Side would lose its
  row alignment; the history view hides lines as the change view does. }
function TForm1.FoldingShown: boolean;
begin
  Result := (FView in [gvFile, gvBlob]) or ((FView = gvChanges) and not FOnlyChanges and
    not FSideBySide);
end;

{ The fold band lets the ranges of the lexer (functions, classes,
  blocks) be folded by a click; it is shown where FoldingShown allows. }
procedure TForm1.SetFoldBand(AEd: TATSynEdit; AVisible: boolean);
var
  Band: integer;
begin
  Band := AEd.Gutter.FindIndexByTag(ATEditorOptions.GutterTagFolding);
  if (Band >= 0) and (AEd.Gutter[Band].Visible <> AVisible) then
  begin
    AEd.Gutter[Band].Visible := AVisible;
    AEd.Gutter.Update;
  end;
end;

{ A jump to a folded line unfolds it where folding is shown; elsewhere a
  hidden line is the diff's, which a jump must leave hidden. }
function TForm1.FoldAction: TATEditorActionIfFolded;
begin
  if FoldingShown then
    Result := TATEditorActionIfFolded.Unfold
  else
    Result := TATEditorActionIfFolded.Ignore;
end;

{ The line of the file shown in ARow, 1-based, for KeepFolds: the row
  itself in the file view, the line of the new file in the change view
  (0 for a deleted line, a gap or a filler). }
function TForm1.FileLineOfRow(ARow: integer): integer;
begin
  Result := 0;
  if FView in [gvFile, gvBlob] then
    Result := ARow + 1
  else if (FView = gvChanges) and (ARow >= 0) and (ARow <= High(FRows)) and
    (FRows[ARow].Line >= 0) and (FRows[ARow].Line <= High(FNewNum)) then
    Result := FNewNum[FRows[ARow].Line];
end;

{ An operation (merge, rebase, cherry-pick, bisect...) is under way, or a
  commit or a remote job runs: nothing that moves HEAD or the index may
  start. }
function TForm1.RepoBusy: boolean;
begin
  Result := (FOperation <> '') or (FCommitJob <> nil) or (FRemoteJob <> nil);
end;

{ A repository is open and not busy. }
function TForm1.RepoReady: boolean;
begin
  Result := (FRepo.Root <> '') and not RepoBusy;
end;

{ The index in FStats of APath, -1 when it is not changed. }
function TForm1.StatIndexOf(const APath: string): integer;
begin
  for Result := 0 to High(FStats) do
    if FStats[Result].Path = APath then
      Exit;
  Result := -1;
end;

{ The path of the shown text, for KeepFolds. }
function TForm1.FoldPath: string;
begin
  if FView = gvFile then
    Result := Edit.FileName
  else if FView = gvBlob then
    Result := FBlobPath
  else
    Result := FCurrentPath;
end;

{ Remembers the folded ranges before the shown text is replaced by the
  same file again (a refresh, a view option), by the file line they
  start on; RestoreFolds folds them again once the lexer has parsed the
  new text. }
procedure TForm1.KeepFolds;
var
  i, Line: integer;
  R: PATFoldRange;
begin
  FKeptFolds := nil;
  FKeptFoldsPath := '';
  if not FoldingShown then
    Exit;
  for i := 0 to Edit.Fold.Count - 1 do
  begin
    R := Edit.Fold.ItemPtr(i);
    if not R^.Folded then
      Continue;
    Line := FileLineOfRow(R^.Y);
    if Line > 0 then
    begin
      SetLength(FKeptFolds, Length(FKeptFolds) + 1);
      FKeptFolds[High(FKeptFolds)] := Line;
    end;
  end;
  if FKeptFolds <> nil then
    FKeptFoldsPath := FoldPath;
end;

{ From AdapterParseDone: folds the first range on each line KeepFolds
  remembered, when the text is the same file's and may be folded. }
procedure TForm1.RestoreFolds;
var
  i, j, Line: integer;
  R: PATFoldRange;
  Folded: boolean;
begin
  if FKeptFolds = nil then
    Exit;
  if FoldingShown and (FoldPath = FKeptFoldsPath) then
  begin
    Folded := False;
    for i := 0 to Edit.Fold.Count - 1 do
    begin
      R := Edit.Fold.ItemPtr(i);
      if R^.Folded or R^.IsSimple then
        Continue;
      Line := FileLineOfRow(R^.Y);
      for j := 0 to High(FKeptFolds) do
        if FKeptFolds[j] = Line then
        begin
          FKeptFolds[j] := 0;
          Edit.DoRangeFold(i);
          Folded := True;
          Break;
        end;
    end;
    if Folded then
      Edit.Update;
  end;
  FKeptFolds := nil;
  FKeptFoldsPath := '';
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
  the old side) its red, a fuzzy entry's in the translation view an
  amber; the rest the gutter's usual color. }
function TForm1.LineNumberColor(AKind: integer): TColor;
begin
  case AKind of
    bmAdded: Result := Edit.Colors.StateAdded;
    bmDeleted: Result := Edit.Colors.StateChanged;
    bmFuzzy:
      if FDark then
        Result := RGBToColor(224, 176, 72)
      else
        Result := RGBToColor(168, 112, 0);
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
  C: TCanvas;
begin
  C := MeasureCanvas(AEd.Font);
  C.Font.Size := EditorFontSize(AEd);
  Result := Max(1, C.TextWidth(ATEditorOptions.SampleChar));
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

{ The two editors zoom together. }
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
  EditorMetricsChanged;
end;

{ The editors' font or zoom changed: the number and blame bands are
  sized from the character width, and the preview's text follows the
  editor's size. EditChangeZoom calls it, which the wheel and the
  editor's own keys reach through OnChangeZoom and the menu's Zoom In
  and Out directly; Actual Size and a new font call it themselves. }
procedure TForm1.EditorMetricsChanged;
begin
  UpdateNumberWidth(Edit);
  UpdateNumberWidth(FEditOld);
  ApplyBlame;
  if FMdPreview.Visible then
    FMdPreview.SetFontSize(EditorFontSize(Edit));
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
  { The editor keeps the text of the file before an image or a binary
    file. }
  if (FView in [gvImage, gvBinary]) or ((FView = gvBlob) and not Edit.Visible) then
    Exit;
  { The translation view keeps its own blocks: the changed entries, or
    the ones that need work. }
  if FView = gvTranslation then
    Exit(FPoBlocks);
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
    FHeader.SetConflicts(0, 0);
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
  { The conflict navigator counts the conflicts of a conflicted file the
    same way. }
  if (FView = gvChanges) and IsConflictPath(FCurrentPath) then
  begin
    Current := 0;
    for i := 0 to High(FConflictRows) do
      if FConflictRows[i] <= Cur then
        Current := i + 1
      else
        Break;
    FHeader.SetConflicts(Current, Length(FConflictRows));
  end
  else
    FHeader.SetConflicts(0, 0);
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
    if ShowsChangedFile then
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
      if ShowsChangedFile and StepFile(True) then
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
      if ShowsChangedFile and StepFile(False) then
      begin
        Blocks := ChangeBlocks;
        if Length(Blocks) = 0 then
          Exit;
      end;
      Target := Blocks[High(Blocks)];
    end;
  end;
  ShowChangeAt(Target);
end;

{ The caret goes to ARow, which lands a few lines below the top edge so
  the context above it stays in view. }
procedure TForm1.ShowChangeAt(ARow: integer);
begin
  if FoldingShown then
    Edit.DoUnfoldLine(ARow);
  Edit.DoCaretSingle(0, ARow);
  Edit.LineTop := Max(0, ARow - 3);
  Edit.Update;
  SyncOldSide;
  UpdateChangeNav;
end;

{ A file chosen in the tree opens at its first change, or its first
  conflict, with the caret on it so that Next Change goes on to the
  second. A change that is already on the first screen leaves the top of
  the file in view. }
procedure TForm1.GoToFirstChange;
var
  Blocks: TIntegerDynArray;
  Target, Row: integer;
begin
  if (FView = gvChanges) and IsConflictPath(FCurrentPath) and (Length(FConflictRows) > 0) then
    Blocks := FConflictRows
  else
    Blocks := ChangeBlocks;
  if Length(Blocks) = 0 then
    Exit;
  Target := Blocks[0];
  ShowChangeAt(Target);
  { Setting LineTop above has filled the wrap info, which counts the
    screen rows down to the change past any folds. }
  if Target > 3 then
  begin
    Row := Edit.WrapInfo.FindIndexOfLineNumber(Target);
    if (Row >= 0) and (Row < Edit.GetVisibleLines - 1) then
    begin
      Edit.LineTop := 0;
      Edit.Update;
      SyncOldSide;
    end;
  end;
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
  SaveCommitDraft;
  AbandonMessageJob;
  AbandonAIReview;
  FAIThreads := nil;
  FAIThreadsKey := '';
  StopCommitJob(False);
  StopRemoteJob(False);
  { A failure's notice, which Try Again would run on this one. }
  FNotice.Close;
  StopWatcher;
  StopIndexing;
  SaveIndex;
  FSummary.Notice := '';
  FCurrentPath := '';
  { The discards, the keeps and the changes left out of the previous
    repository are not for this one. }
  FDiscards := nil;
  FKeeps.ClearAll;
  FLeftOut.ClearAll;
  ClearRevertUndo;
  UpdateDiscardItems;
  FPullRange := '';
  FMarkHash := '';
  FCleanKind := cnUntracked;
  FPatchFolder := '';
  FApplyFolder := '';
  FPatchCover := False;
  FApplyCommit := True;
  FMarkName := '';
  AbandonReviewJob;
  ClearReviews;
  FThreadFlips.Clear;
  FExcludePath := '';
  AbandonSubmoduleJobs;
  FSubmodules := nil;
  FSubInfos := nil;
  FSubKey := '';
  FSubShown := '';
  { Its failures are not this one's. }
  FBanner.Clear;
  if not FRepo.Open(ADir) then
  begin
    FCommitDraftFor := '';
    ShowError(FRepo.Error);
    UpdateCommitState;
    Exit;
  end;
  LoadCommitDraft;
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
  Texts, Actions: array of string;
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
  FRewritten := ASnap.Rewritten;
  FOperation := ASnap.Operation;
  FBisect := ASnap.Bisect;
  FRebaseBranch := ASnap.RebaseBranch;
  if (FOperation = 'rebasing') and (FRebaseBranch <> '') and ASnap.Detached then
    { HEAD is detached while a rebase stops; the branch is the one it
      rebases. A checkout in a terminal meanwhile leaves the rebase
      behind on its way: HEAD is on that branch then, and the summary
      says which branch the rebase is of (OperationLabel). }
    FBranch := FRebaseBranch;
  FConflictFiles := 0;
  for i := 0 to High(FStats) do
    if FStats[i].Kind = ckConflict then
      Inc(FConflictFiles);
  FFileCount := Length(FStats);
  FStashes := ASnap.Stashes;
  FillFileTree(FStats);
  UpdateCommitState;
  FillRepoFiles;
  FillSubmodules;
  SetLength(Icons, Length(FStats));
  SetLength(Texts, Length(FStats));
  SetLength(Actions, Length(FStats));
  for i := 0 to High(FStats) do
  begin
    Icons[i] := StatIcon(FStats[i]);
    Texts[i] := SubmoduleMoveText(SubmoduleAt(FStats[i].Path));
    if FStats[i].Kind = ckConflict then
      Actions[i] := rsResolvePill
    else
      Actions[i] := '';
  end;
  Branch := FBranch;
  if FOperation <> '' then
    Branch := Branch + ' · ' + OperationLabel;
  FNotOnRemote := ASnap.NotOnRemote;
  FSummary.SetCommits(ASnap.Recent, FAhead, FBehind, FHasUpstream, FNotOnRemote);
  { Not in the middle of a merge or rebase, which the Commit section
    finishes first. }
  if FOperation = '' then
    FSummary.SetBehind(ASnap.BehindDefault, FDefaultBranch)
  else
    FSummary.SetBehind(0, '');
  FSummary.BaseClickable := (BaseActionRef <> '') or (StashOfBase >= 0) or BlameShown;
  if BlameShown then
    FSummary.SetCommit(FBlameCommit, FBlameBody)
  else
    FSummary.SetCommit(Default(TGittanCommitLine), '');
  FSummary.SetRepository(ExtractFileName(FRepo.Root), Branch, BaseLabel, FStats, Icons,
    Texts, Actions);
  FWelcome.Visible := False;
  { The page of a submodule keeps the box; RefreshRepository shows it
    again. }
  FSummary.Visible := FView <> gvSubmodule;
  { The Repository page keeps the box, and reads the repository again,
    since the snapshot says it changed. }
  if FView = gvRepoInfo then
  begin
    HideBoxPages;
    FRepoPage.SetRepository(ExtractFileName(FRepo.Root), FRepo.Root);
    FRepoPage.Visible := True;
    StartRepoInfoJob;
  end;
  { The commands follow the files: an edit of the file or a pull. }
  LoadRepoCommands;
  if FView = gvCommands then
  begin
    HideBoxPages;
    FCommandPage.Visible := True;
    FCommandPage.FitHeight(FSummaryBox.ClientHeight);
  end;
  { The Files page follows HEAD, which a commit moved. }
  if FView = gvFiles then
  begin
    HideBoxPages;
    FFilesPage.Visible := True;
    RefreshFilesPage;
    FFilesPage.FitHeight(FSummaryBox.ClientHeight);
  end;
  if FView = gvPulls then
  begin
    HideBoxPages;
    FPullPage.Visible := True;
    FPullPage.FitHeight(FSummaryBox.ClientHeight);
  end;
  RebuildCompareMenu;
  FTerminalItem.Enabled := FRepo.Root <> '';
  UpdateBranchItems;
  UpdateStashItems;
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
    without running any git here. Under a hold it would run in the middle
    of what holds (a modal question pumps messages, Synchronize's
    among them): it waits for the hold to end instead. }
  if FRefreshHold > 0 then
  begin
    FRefreshPending := True;
    Exit;
  end;
  Snap := FWatcher.Snapshot;
  RefreshRepository(@Snap);
end;

{ A stretch the watcher's refresh must not run under: FlushEdit's
  question, which ShowChanges, OpenFile and OpenRepository ask in the
  middle of their work, a wait that pumps messages (WaitForParse), and
  RefreshRepository itself. A change the watcher brings meanwhile is
  read again when the last hold ends, from the message loop, once the
  callers have returned. }
procedure TForm1.HoldRefresh;
begin
  Inc(FRefreshHold);
end;

procedure TForm1.ReleaseRefresh;
begin
  Dec(FRefreshHold);
  if (FRefreshHold = 0) and FRefreshPending and not FRefreshQueued then
  begin
    FRefreshQueued := True;
    Application.QueueAsyncCall(@RefreshPendingAsync, 0);
  end;
end;

{ Another hold may have begun before the queue ran it (a second modal
  question); its end queues this again. }
procedure TForm1.RefreshPendingAsync(Data: PtrInt);
begin
  FRefreshQueued := False;
  if (FRefreshHold > 0) or not FRefreshPending then
    Exit;
  FRefreshPending := False;
  RefreshRepository;
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
  the summary, which says so; one the tree filter hides is shown again
  without being selected. Filling the tree drops the selection, so
  the view is noted first and restored by selecting the file again, which
  runs the usual selection handler. ASnap nil reads the repository here;
  otherwise it is the snapshot the watcher already gathered off the main
  thread, which is only drawn. The refresh holds the watcher's (see
  HoldRefresh): one that came under it would rebuild the view while
  this one does. }
procedure TForm1.RefreshRepository(ASnap: PGittanRepoSnapshot = nil);
begin
  HoldRefresh;
  try
    RefreshRepositoryHeld(ASnap);
  finally
    ReleaseRefresh;
  end;
end;

procedure TForm1.RefreshRepositoryHeld(ASnap: PGittanRepoSnapshot);
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
    { Moving the caret here fires no caret event, and the navigator and
      the status bar still show where the view was built with it. }
    UpdateChangeNav;
  end;

begin
  if FRepo.Root = '' then
    Exit;
  View := FView;
  Path := SelectedPath;
  { The tree filter may hide the file shown; the tree then selects
    nothing. }
  if (Path = '') and (View in [gvChanges, gvImage, gvTranslation, gvBinary]) then
    Path := FCurrentPath;
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
          KeepFolds;
          OpenFile(FEditPath);
          RestoreScroll;
        end;
    gvChanges, gvImage, gvTranslation, gvBinary:
      { A translation or a binary file opened from disk is not in the
        tree. }
      if not (View in [gvTranslation, gvBinary]) or (FCurrentPath <> '') then
      begin
        KeepFolds;
        SummarySelectFile(nil, Path);
        if FileTree.Selected <> nil then
          RestoreScroll
        { Else the summary is shown when the selection's ShowChanges
          failed. }
        else if FView <> gvSummary then
          if IsChangedPath(Path) then
          begin
            if ShowChanges(Path) then
              RestoreScroll;
          end
          else
          begin
            FSummary.Notice := Format(rsNoLongerChanged, [Path]);
            ShowSummary;
          end;
      end;
    gvRepoDiff:
      begin
        ShowRepoDiff;
        RestoreScroll;
      end;
    gvSubmodule:
      RestoreSubmodule;
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
  LeaveEditorViews;
  FSummaryBox.Visible := True;
  FView := gvSummary;
  { The Repository, Commands, Files and Pull Requests pages and the
    page of a submodule give the box back. }
  if FRepoPage.Visible or FSubPage.Visible or FCommandPage.Visible or FFilesPage.Visible or
    FPullPage.Visible then
  begin
    HideBoxPages;
    FSummary.Visible := FRepo.Root <> '';
  end;
  if FRepo.Root <> '' then
    SetNavRow(navHome)
  else
    SetNavRow(-1);
  FStatus.SetPosition('');
  { A file picked again after the summary must fire the selection event. }
  FileTree.Selected := nil;
  FRepoTree.Selected := nil;
  FSubTree.Selected := nil;
  if FRepo.Root <> '' then
    UpdateStatus;
end;

{ Hides every page of the box, for the one about to show. The welcome
  view is shown at startup, before the later pages exist. }
procedure TForm1.HideBoxPages;
begin
  FWelcome.Visible := False;
  FSummary.Visible := False;
  FRepoPage.Visible := False;
  FSubPage.Visible := False;
  if FCommandPage <> nil then
    FCommandPage.Visible := False;
  if FFilesPage <> nil then
    FFilesPage.Visible := False;
  if FPullPage <> nil then
    FPullPage.Visible := False;
end;

{ Hides the editor and what goes with it, for a page in the box. }
procedure TForm1.LeaveEditorViews;
begin
  FlushEdit;
  LeaveEdit;
  Edit.Visible := False;
  FEditOld.Visible := False;
  FSideSplitter.Visible := False;
  FImageDiff.Visible := False;
  FBinaryView.Visible := False;
  HideMarkdownPreview;
  FHeader.Visible := False;
  FFindBar.Visible := False;
  FSymbolBar.Visible := False;
  AbandonHistoryJob;
  if FBanner <> nil then
    PlaceUnderTitleBar;
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
  SetNavRow(-1);
  FImageDiff.Visible := False;
  FBinaryView.Visible := False;
  FHeader.Visible := True;
  SetFoldBand(Edit, FoldingShown);
  ApplyLayout;
  ApplyBlame;
  Edit.Visible := True;
  UpdateMarkdownPreview;
end;

{ An image in the change view: the version compared against and the new
  one side by side in FImageDiff, in the editor's place, under the file
  header. The editor's text is left as it was; FView keeps the views
  of text (find, blame, the navigator) away from it. }
procedure TForm1.ShowImageChanges(const APath: string);
var
  OldRef, NewRef: string;
  OldData, NewData: RawByteString;
  HasOld, HasNew: boolean;
begin
  AbandonHistoryJob;
  FRepo.DiffSides(OldRef, NewRef);
  HasOld := FRepo.FileBlob(APath, OldRef, OldData);
  HasNew := FRepo.FileBlob(APath, NewRef, NewData);
  FImageDiff.SetImages(OldData, NewData, HasOld, HasNew);
  FView := gvImage;
  FSymbolBar.Visible := False;
  FFindBar.Visible := False;
  FSummaryBox.Visible := False;
  SetNavRow(-1);
  FBinaryView.Visible := False;
  Edit.Visible := False;
  HideMarkdownPreview;
  FHeader.Visible := True;
  ApplyLayout;
  FImageDiff.Visible := True;
  FSummary.Selected := APath;
  FStatus.SetPosition('');
end;

{ A binary file in the change view: its sizes before and after in
  FBinaryView, in the editor's place, as an image is shown. }
procedure TForm1.ShowBinaryChanges(const APath: string);
var
  OldRef, NewRef: string;
  OldSize, NewSize: int64;
  HasOld, HasNew: boolean;
begin
  AbandonHistoryJob;
  FRepo.DiffSides(OldRef, NewRef);
  HasOld := FRepo.FileSize(APath, OldRef, OldSize);
  HasNew := FRepo.FileSize(APath, NewRef, NewSize);
  FBinaryView.SetChange(APath, HasOld, HasNew, OldSize, NewSize);
  FView := gvBinary;
  FSymbolBar.Visible := False;
  FFindBar.Visible := False;
  FSummaryBox.Visible := False;
  SetNavRow(-1);
  FImageDiff.Visible := False;
  Edit.Visible := False;
  HideMarkdownPreview;
  FHeader.Visible := True;
  ApplyLayout;
  FBinaryView.Visible := True;
  FSummary.Selected := APath;
  FStatus.SetPosition('');
end;

{ A binary file from File > Open: its size, in the editor's place. }
procedure TForm1.ShowBinaryFile(const AFileName: string);
var
  Info: TSearchRec;
  Size: int64;
begin
  AbandonHistoryJob;
  Size := 0;
  if FindFirst(AFileName, faAnyFile, Info) = 0 then
  begin
    Size := Info.Size;
    FindClose(Info);
  end;
  FBinaryView.SetFile(AFileName, Size);
  FHeader.SetFile(AFileName, -1);
  FSummary.Selected := '';
  FCurrentPath := '';
  FView := gvBinary;
  Edit.FileName := AFileName;
  FSymbolBar.Visible := False;
  FFindBar.Visible := False;
  FSummaryBox.Visible := False;
  SetNavRow(-1);
  FImageDiff.Visible := False;
  Edit.Visible := False;
  HideMarkdownPreview;
  FHeader.Visible := True;
  ApplyLayout;
  FBinaryView.Visible := True;
  FStatus.SetPosition('');
  UpdateStatus;
  UpdateCaption;
end;

{ The summary paints its own background; it must cover the scroll box. }
procedure TForm1.SummaryBoxResize(Sender: TObject);
begin
  FSummary.FitHeight(FSummaryBox.ClientHeight);
  FWelcome.FitHeight(FSummaryBox.ClientHeight);
  FRepoPage.FitHeight(FSummaryBox.ClientHeight);
  FSubPage.FitHeight(FSummaryBox.ClientHeight);
  FCommandPage.FitHeight(FSummaryBox.ClientHeight);
  FFilesPage.FitHeight(FSummaryBox.ClientHeight);
  FPullPage.FitHeight(FSummaryBox.ClientHeight);
end;

{ The welcome view takes the summary's place in the box, with AError
  under its title when opening a repository failed; it stays until a
  repository loads, see LoadRepository. }
procedure TForm1.ShowWelcome(const AError: string);
begin
  FWelcome.SetError(AError);
  AbandonRepoInfoJob;
  { The welcome view is shown at startup, before the pages exist. }
  if FCommandPage <> nil then
    AbandonCommandJob(False);
  FRepoCommands := nil;
  HideBoxPages;
  SetNavRow(-1);
  FTreeClean := False;
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

procedure TForm1.WelcomeClone(Sender: TObject);
begin
  MenuCloneClick(Sender);
end;

procedure TForm1.WelcomeInit(Sender: TObject);
begin
  MenuInitClick(Sender);
end;

{ A click on a file in the summary selects it in the tree, which shows its
  changes. The tree's node texts are the path components. }
procedure TForm1.SummarySelectFile(Sender: TObject; const APath: string);
var
  Node: TTreeNode;
  Sub: integer;
begin
  { A submodule is shown whether or not the filter leaves its node in
    the tree; ShowSubmodule selects the node when it is there. }
  Sub := SubmoduleAt(APath);
  if Sub >= 0 then
  begin
    FileTree.Selected := nil;
    FSubTree.Selected := nil;
    ShowSubmodule(Sub);
    Exit;
  end;
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
  InHeader: boolean;
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
  { The words that differ, as in the change view. The diff's own lines
    (hunk and file headers) are given a blank marker so they do not
    count as changes; the text keeps its marker column, so the spans
    are shifted by one. A file's header runs from its "diff" line to
    its first hunk, so a "---"/"+++" line is a header only there: in a
    hunk it is a deleted "-- comment" or an added "++i;". }
  Lines := TStringList.Create;
  try
    Lines.Text := DiffText;
    InHeader := False;
    for i := 0 to Lines.Count - 1 do
    begin
      if Copy(Lines[i], 1, 5) = 'diff ' then
        InHeader := True
      else if Copy(Lines[i], 1, 2) = '@@' then
        InHeader := False;
      if (Lines[i] = '') or not (Lines[i][1] in ['+', '-']) or InHeader then
        Lines[i] := ' ' + Lines[i]
      else if i < Edit.Strings.Count then
        MarkLine(Edit, i, Lines[i][1]);
    end;
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
  the same file is shown again, as on a refresh. False when git could
  not give the diff: the banner says why and the summary is shown, so
  the tree and the view do not tell of different files. }
function TForm1.ShowChanges(const APath: string): boolean;
var
  Lines: TStringList;
  i, c: integer;
  Binary: boolean;
begin
  { Asked before the header names the next file, not when the text is
    replaced further down. }
  FlushEdit;
  i := StatIndexOf(APath);
  Result := False;
  { A binary file has no lines to diff; a new one would be read as
    text. }
  Binary := (i >= 0) and FStats[i].Binary;
  Lines := TStringList.Create;
  try
    if not Binary and not FRepo.FileChanges(APath, Lines) then
    begin
      StatusNote(FRepo.Error, True);
      FSummary.Notice := '';
      ShowSummary;
      Exit;
    end;
    Result := True;
    FChangeLines.Assign(Lines);
    FRawChangeLines.Assign(Lines);
  finally
    Lines.Free;
  end;
  { The changes kept as code this session are plain lines from here on
    (see umain.discard.inc). }
  FKeeps.Apply(APath, FChangeLines, FKeptOf);
  if APath <> FCurrentPath then
    FExpanded := nil;
  { The file may have changed since the head was mapped onto it. }
  FMapDiffKey := '';
  { The diff may have changed, so the blocks and their headings are
    found again after the parse. }
  FHeadings := nil;
  FHeadingRebuilds := 0;
  FCurrentPath := APath;
  SetOverscroll(0);
  FSummary.Notice := '';
  FHeader.SetFile(APath, -1);
  FConflictRoles := nil;
  FConflictStarts := nil;
  FConflictEnds := nil;
  if i >= 0 then
  begin
    FHeader.SetFile(APath, StatIcon(FStats[i]));
    FHeader.SetCounts(FStats[i].Added, FStats[i].Deleted, FStats[i].Binary);
    FHeader.SetStage(FStats[i].Staged, FStats[i].Unstaged);
    if FStats[i].Kind = ckConflict then
    begin
      FConflictRoles := ConflictRoles(FChangeLines);
      FConflictStarts := ConflictStarts(FConflictRoles, FChangeLines);
      SetLength(FConflictEnds, Length(FConflictStarts));
      for c := 0 to High(FConflictStarts) do
        FConflictEnds[c] := ConflictEnd(FChangeLines, FConflictRoles, FConflictStarts[c]);
      FHeader.SetActions([rsUseMine, rsUseTheirs, rsMarkResolved]);
    end;
  end;
  if IsImagePath(APath) then
  begin
    ShowImageChanges(APath);
    UpdateChangeNav;
    UpdateStatus;
    Exit;
  end;
  if Binary then
  begin
    ShowBinaryChanges(APath);
    UpdateChangeNav;
    UpdateStatus;
    Exit;
  end;
  if FTranslations and IsPoPath(APath) and (FConflictRoles = nil) then
  begin
    ShowTranslationChanges(APath);
    Exit;
  end;
  FManualLexer := False;
  FView := gvChanges;
  ApplyLeftOut;
  SetChangeActions;
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
  folder icon. A folder is never opened; a submodule shows ShowSubmodule.
  git lists paths sorted, so the folder node of the previous
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
  if FTreeClean <> (Length(AStats) = 0) then
  begin
    FTreeClean := Length(AStats) = 0;
    FileTree.Invalidate;
  end;
  if FCommitOn <> nil then
    ApplyCommitChecks;
end;

{ The empty tree of a clean repository shows the summary's mark for it
  in gray, so it stays quiet beside the green one in the summary: a
  large disc with a check cut out of it, with "No changes" under it, in
  the middle of the tree. }
procedure TForm1.FileTreeAdvancedCustomDraw(Sender: TCustomTreeView;
  const ARect: TRect; Stage: TCustomDrawStage; var DefaultDraw: boolean);
const
  Disc = 40;
  Gap = 10;
var
  C: TCanvas;
  X, Y, CenterY, TextH: integer;
begin
  DefaultDraw := True;
  if (Stage <> cdPostPaint) or not FTreeClean or (Sender.Items.Count > 0) then
    Exit;
  C := Sender.Canvas;
  C.Font := Sender.Font;
  TextH := C.TextHeight('Xg');
  X := (Sender.ClientWidth - Disc) div 2;
  Y := (Sender.ClientHeight - Disc - Gap - TextH) div 2;
  C.Pen.Style := psClear;
  C.Brush.Style := bsSolid;
  if FDark then
    C.Brush.Color := RGBToColor(85, 85, 87)
  else
    C.Brush.Color := RGBToColor(196, 196, 198);
  C.Ellipse(X, Y, X + Disc, Y + Disc);
  CenterY := Y + Disc div 2;
  C.Pen.Style := psSolid;
  C.Pen.Color := Sender.BackgroundColor;
  C.Pen.Width := 4;
  C.Polyline([Point(X + Disc * 27 div 100, CenterY),
    Point(X + Disc * 44 div 100, CenterY + Disc * 17 div 100),
    Point(X + Disc * 74 div 100, CenterY - Disc * 17 div 100)]);
  C.Pen.Width := 1;
  C.Brush.Style := bsClear;
  if FDark then
    C.Font.Color := RGBToColor(150, 150, 150)
  else
    C.Font.Color := RGBToColor(110, 110, 110);
  C.TextOut((Sender.ClientWidth - C.TextWidth(rsTreeClean)) div 2,
    Y + Disc + Gap, rsTreeClean);
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
  SetupSideNav;
  FileTree.Parent := FTreePanel;
  FileTree.Align := alClient;
end;

{ ---------------------------------------------------------------------------
  The title bar
  ---------------------------------------------------------------------------
  On macOS the content reaches under the title bar, which is made
  transparent (gittan.titlebar.pp), so the tree panel's shade runs up to
  the top edge on the left and the editor's background on the right, as
  a sidebar does in Finder or Mail. The title bar still takes the mouse
  in the strip (a drag moves the window, a double click zooms it), so
  the controls at the top of both, the filter field and the header or
  the summary, are moved down by the strip's height, and the splitter
  too, which otherwise showed its cursor where a drag moved the window.
  On Windows and GTK 3 the form draws the title bar itself
  (gittan.owntitlebar; gittan.wintitlebar and gittan.gtktitlebar), with
  the name, the menus, the filter field, the header's navigator and
  pills and the caption buttons in it. }
procedure TForm1.SetupTitleBar;
begin
  {$IFDEF LCLCocoa}
  { The toolbar first: it makes the strip taller. }
  FToolbar := TGittanToolbar.Install(Handle, rsAppShortName, rsFilterHint);
  if FToolbar <> nil then
  begin
    FTreeFilter.Visible := False;
    FToolbar.OnSearchChange := @TreeFilterChange;
    FToolbar.OnSearchKey := @ToolbarSearchKey;
    FToolbar.OnAction := @HeaderAction;
    FToolbar.OnName := @MenuCommandsClick;
    FToolbar.OnPrev := @MenuPrevChangeClick;
    FToolbar.OnNext := @MenuNextChangeClick;
    FToolbar.OnConflictPrev := @MenuPrevConflictClick;
    FToolbar.OnConflictNext := @MenuNextConflictClick;
    FHeader.ShowControls := False;
    FHeader.OnControlsChange := @HeaderControlsChange;
    HeaderControlsChange(nil);
  end;
  FTitleBarHeight := ExtendUnderTitleBar(Handle);
  {$ENDIF}
  {$IFDEF LCLWin32}
  FOwnBar := TGittanWinTitleBar.Create(Self);
  {$ENDIF}
  {$IFDEF LCLGtk3}
  FOwnBar := TGittanGtkTitleBar.Create(Self);
  {$ENDIF}
  { The keys of the commands (umain.commands.inc) from any view, and on
    GTK Alt and a letter, which opens the menu it underlines as the
    hidden menu bar would. }
  KeyPreview := True;
  OnKeyDown := @FormKeyDown;
  {$IFDEF OWNBAR}
  FOwnBar.Title := rsAppShortName;
  FOwnBar.Align := alTop;
  FOwnBar.Parent := Self;
  FOwnBar.SplitControl := TreeSplitter;
  FOwnBar.Search := FTreeFilter;
  FOwnBar.OnAction := @HeaderAction;
  FOwnBar.Nav.OnPrev := @MenuPrevChangeClick;
  FOwnBar.Nav.OnNext := @MenuNextChangeClick;
  FOwnBar.ConflictNav.Suffix := rsConflictsSuffix;
  FOwnBar.ConflictNav.OnPrev := @MenuPrevConflictClick;
  FOwnBar.ConflictNav.OnNext := @MenuNextConflictClick;
  FHeader.ShowControls := False;
  FHeader.OnControlsChange := @HeaderControlsChange;
  HeaderControlsChange(nil);
  {$ENDIF}
  {$IFDEF LCLWin32}
  InstallTitleBar(Self, TGittanWinTitleBar(FOwnBar));
  {$ENDIF}
  {$IFDEF LCLGtk3}
  InstallTitleBar(Self, TGittanGtkTitleBar(FOwnBar));
  {$ENDIF}
  FTreeFilter.BorderSpacing.Top := FTitleBarHeight;
  { With the toolbar's field in its place the page rows are at the top. }
  if not FTreeFilter.Visible then
    FSideNav.BorderSpacing.Top := FTitleBarHeight;
  PlaceUnderTitleBar;
  TreeSplitter.BorderSpacing.Top := FTitleBarHeight;
  ColorSidebar;
end;

{ The indexing's progress as a band along the top edge of the window,
  over the title bar (macOS) or in the form's own title bar (Windows and
  GTK 3; the status bar has its own bar). It is
  shown for every file, not only when the status bar is updated: the
  big files of a large repository take seconds between those. }
procedure TForm1.UpdateIndexBand;
begin
  {$IFDEF LCLCocoa}
  if FIndexing then
    ShowTitleBand(Handle, FIndexPos, FIndexTotal, ColorToRGB(FBandTrack),
      ColorToRGB(FBandFill))
  else
    HideTitleBand(Handle);
  {$ENDIF}
  {$IFDEF OWNBAR}
  if FOwnBar = nil then
    Exit;
  if FIndexing then
    FOwnBar.SetBand(FIndexPos, FIndexTotal, FBandTrack, FBandFill)
  else
    FOwnBar.SetBand(0, 0, FBandTrack, FBandFill);
  {$ENDIF}
end;

{ The tree panel and its trees take the gutter's shade, as the section
  headers do, so the sidebar is one block from the title bar down to the
  status bar, and the form too, for the notch above the splitter; the
  editor panel takes the editor's background, which shows in the strip
  above the header or the summary. }
procedure TForm1.ColorSidebar;
var
  Shade: TColor;
begin
  if FTreePanel = nil then
    Exit;
  Shade := SidebarShade(FDark);
  FTreePanel.Color := Shade;
  Color := Shade;
  FileTree.BackgroundColor := Shade;
  ThemeSideNav(FSideNav, FDark, Edit.Colors.TextFont);
  if FRepoTree <> nil then
    FRepoTree.BackgroundColor := Shade;
  if FSubTree <> nil then
    FSubTree.BackgroundColor := Shade;
  EditorPanel.Color := Edit.Colors.TextBG;
  {$IFDEF OWNBAR}
  { The title bar runs the sidebar's shade over the sidebar and the
    editor's background over the rest, with the header's pills. }
  if FOwnBar <> nil then
    if FDark then
    begin
      FOwnBar.SetColors(Shade, Edit.Colors.TextBG, Edit.Colors.TextFont,
        RGBToColor(150, 150, 150), RGBToColor(50, 50, 51), RGBToColor(85, 85, 86),
        RGBToColor(100, 160, 240), RGBToColor(50, 50, 51), RGBToColor(70, 70, 71),
        RGBToColor(62, 62, 63));
      FOwnBar.Nav.SetColors(Edit.Colors.TextBG, RGBToColor(50, 50, 51),
        RGBToColor(85, 85, 86), RGBToColor(200, 200, 200), RGBToColor(100, 160, 240));
      FOwnBar.ConflictNav.SetColors(Edit.Colors.TextBG, RGBToColor(58, 46, 68),
        RGBToColor(120, 80, 160), RGBToColor(210, 170, 245), RGBToColor(240, 215, 255));
    end
    else
    begin
      FOwnBar.SetColors(Shade, Edit.Colors.TextBG, RGBToColor(30, 30, 30),
        RGBToColor(110, 110, 110), clWhite, RGBToColor(205, 205, 205),
        RGBToColor(0, 110, 230), clWhite, RGBToColor(205, 205, 205),
        RGBToColor(229, 229, 229));
      FOwnBar.Nav.SetColors(Edit.Colors.TextBG, clWhite,
        RGBToColor(205, 205, 205), RGBToColor(70, 70, 70), RGBToColor(0, 110, 230));
      FOwnBar.ConflictNav.SetColors(Edit.Colors.TextBG, RGBToColor(248, 240, 255),
        RGBToColor(190, 160, 220), RGBToColor(110, 50, 160), RGBToColor(155, 63, 200));
    end;
  {$ENDIF}
end;

{ Rebuilds the tree for the new filter and keeps the shown file selected
  without reloading it. }
procedure TForm1.TreeFilterChange(Sender: TObject);
var
  Handler: TNotifyEvent;
begin
  FTreeFilterText := LowerCase(Trim(TreeFilterQuery));
  {$IFDEF OWNBAR}
  { The clear button shows while there is text. }
  if FOwnBar <> nil then
    FOwnBar.Invalidate;
  {$ENDIF}
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
        if TreeFilterQuery <> '' then
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

{ The filter's text: the toolbar's search field on macOS, else the
  field over the tree. }
function TForm1.TreeFilterQuery: string;
begin
  {$IFDEF LCLCocoa}
  if FToolbar <> nil then
    Exit(FToolbar.SearchText);
  {$ENDIF}
  Result := FTreeFilter.Text;
end;

{ A command's key runs it (CommandKey). On GTK Alt and a letter opens
  the menu with that accelerator from the title bar, as the menu bar
  would have before the bar hid its names. }
procedure TForm1.FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if CommandKey(Key, Shift) then
  begin
    Key := 0;
    Exit;
  end;
  {$IFDEF LCLGtk3}
  if (Shift * [ssAlt, ssCtrl, ssShift, ssMeta] = [ssAlt]) and (Key >= VK_A) and
    (Key <= VK_Z) and (FOwnBar <> nil) and FOwnBar.OpenMenuByKey(Chr(Key)) then
    Key := 0;
  {$ENDIF}
end;

{$IFDEF LCLCocoa}
{ The search field passes Escape (when it is empty), Enter and Down on
  as the field over the tree takes them. The form does not know the
  field and still has the control focused before it as the active one,
  so focusing that again would do nothing. }
procedure TForm1.ToolbarSearchKey(Sender: TObject; var Key: word);
begin
  ActiveControl := nil;
  TreeFilterKeyDown(Sender, Key, []);
end;
{$ENDIF}

{ The toolbar (macOS) or the title bar (Windows, GTK 3) shows the header's
  navigator and pills, none while the header is hidden (the summary). }
procedure TForm1.HeaderControlsChange(Sender: TObject);
var
  Captions: array of string;
  States: array of boolean;
  i, Current, Total, ConflictCurrent, ConflictTotal: integer;
begin
  Captions := nil;
  States := nil;
  Current := 0;
  Total := 0;
  ConflictCurrent := 0;
  ConflictTotal := 0;
  if FHeader.Visible then
  begin
    SetLength(Captions, FHeader.ActionCount);
    SetLength(States, FHeader.ActionCount);
    for i := 0 to FHeader.ActionCount - 1 do
    begin
      Captions[i] := FHeader.ActionCaption[i];
      States[i] := FHeader.ActionEnabled[i];
    end;
    Current := FHeader.ChangeCurrent;
    Total := FHeader.ChangeTotal;
    ConflictCurrent := FHeader.ConflictCurrent;
    ConflictTotal := FHeader.ConflictTotal;
  end;
  {$IFDEF LCLCocoa}
  if FToolbar <> nil then
  begin
    FToolbar.SetConflicts(ConflictCurrent, ConflictTotal, rsConflictsSuffix);
    FToolbar.SetChanges(Current, Total);
    FToolbar.SetActions(Captions, States);
  end;
  {$ENDIF}
  {$IFDEF OWNBAR}
  if FOwnBar <> nil then
  begin
    FOwnBar.SetConflicts(ConflictCurrent, ConflictTotal);
    FOwnBar.SetChanges(Current, Total);
    FOwnBar.SetActions(Captions, States);
  end;
  {$ENDIF}
end;

procedure TForm1.MenuFilterFilesClick(Sender: TObject);
begin
  {$IFDEF LCLCocoa}
  if FToolbar <> nil then
  begin
    FToolbar.FocusSearch;
    Exit;
  end;
  {$ENDIF}
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

{ Selecting a file shows its changes, a submodule how it moved. Folders
  only expand. A deleted file still has a diff: every line of it,
  deleted. }
procedure TForm1.FileTreeSelectionChanged(Sender: TObject);
var
  Node: TTreeNode;
  Sub: integer;
begin
  Node := FileTree.Selected;
  if (Node = nil) or (FRepo.Root = '') then
    Exit;
  Sub := -1;
  if Node.Data = nil then
  begin
    Sub := SubmoduleAt(Node.GetTextPath);
    if Sub < 0 then
      Exit;
  end;
  { One selection among the trees. }
  FRepoTree.Selected := nil;
  FSubTree.Selected := nil;
  if Sub >= 0 then
    ShowSubmodule(Sub)
  else
  begin
    if ShowChanges(Node.GetTextPath) then
      GoToFirstChange;
  end;
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
    i := StatIndexOf(Path);
    if i >= 0 then
      Tip := StatHint(FStats[i]) + FileThreadsHint(Path);
  end
  else if Node <> nil then
  begin
    i := SubmoduleAt(Node.GetTextPath);
    if (i >= 0) and (SubmoduleMoveText(i) <> '') then
      Tip := Format(rsHintSubmodule, [SubmoduleMoveText(i)]);
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

const
  { The branch list's action rows (umain.branches.inc), in FBranchNames:
    no branch name holds a colon. }
  BranchNew = ':new';
  BranchGone = ':gone';

{$I umain.diffview.inc}
{$I umain.actions.inc}
{$I umain.gotodef.inc}
{$I umain.blame.inc}
{$I umain.discard.inc}
{$I umain.leaveout.inc}
{$I umain.index.inc}
{$I umain.history.inc}
{$I umain.repofiles.inc}
{$I umain.repopage.inc}
{$I umain.commands.inc}
{$I umain.submodules.inc}
{$I umain.update.inc}
{$I umain.reviews.inc}
{$I umain.translations.inc}
{$I umain.conflicts.inc}
{$I umain.commitactions.inc}
{$I umain.branches.inc}
{$I umain.rebase.inc}
{$I umain.stash.inc}
{$I umain.tags.inc}
{$I umain.reflog.inc}
{$I umain.bisect.inc}
{$I umain.revert.inc}
{$I umain.movefiles.inc}
{$I umain.clean.inc}
{$I umain.patches.inc}
{$I umain.clone.inc}
{$I umain.files.inc}
{$I umain.pulls.inc}
{$I umain.commit.inc}
{$I umain.ai.inc}
{$I umain.remote.inc}
{$I umain.mdpreview.inc}

end.
