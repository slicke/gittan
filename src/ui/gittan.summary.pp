unit gittan.summary;

{** The repository summary: what Gittan shows when a repository is opened,
  before a file is picked. It lists the changed files with their added and
  deleted line counts and a bar that compares the sizes of the changes,
  under a header with the repository name, branch and totals. Between the
  two, the conversation of the pull request when there is one: its
  comments and the text its reviews were submitted with, which are on no
  line, so the change view has no place for them, and a row counting
  the pull requests waiting for the user's review, which drops a list
  of them; or, while a commit is
  compared with its parent, a card with its message, author and age and
  a link back to the working tree. A clean tree shows,
  instead of the totals, a large check with how far the branch is from
  its upstream, and its newest commits instead of rows while some are
  not pushed; otherwise the check stands alone in the middle, as the
  empty view's icon does. A branch behind the default branch gets a row
  under the header that says how far, with Rebase and Merge.

  It paints itself so it matches the editor's palette in both themes. It
  sizes its height to its content and is meant to sit in a TScrollBox,
  which provides the native scrolling. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, ImgList, InkDraw, gittan.git, gittan.icons,
  gittan.reviews, gittan.statusbar, gittan.forge;

type
  TGittanSelectFileEvent = procedure(Sender: TObject; const APath: string) of object;
  {** A right click on a file's row, with the mouse position in screen
    coordinates for a popup menu. }
  TGittanContextFileEvent = procedure(Sender: TObject; const APath: string;
    const AScreenPos: TPoint) of object;
  {** A click on the branch in the header, with its rectangle in screen
    coordinates for a popup to drop down from. }
  TGittanBranchClickEvent = procedure(Sender: TObject; const AScreenRect: TRect) of object;
  {** A click on a commit's row, with its id. }
  TGittanSelectCommitEvent = procedure(Sender: TObject; const AHash: string) of object;
  {** A click on a link to AUrl. }
  TGittanOpenUrlEvent = procedure(Sender: TObject; const AUrl: string) of object;
  {** A click on Rebase (ARebase) or Merge in the row of a branch behind
    the default branch. }
  TGittanBehindActionEvent = procedure(Sender: TObject; ARebase: boolean) of object;
  {** A step from the commit in the card to the next older (AOlder) or
    newer one. }
  TGittanCommitStepEvent = procedure(Sender: TObject; AOlder: boolean) of object;

  {** A part of a note's text as laid out (CommentParts): LazInk's
    markup, how deep in <details> blocks it is, the part it is when it
    is the summary of one (-1 for text), and its top and height below
    the top of the text. }
  TGittanSummaryNoteRow = record
    Markup: string;
    Depth, Detail, Top, Height: integer;
  end;

  {** A note of the conversation as laid out: the parts of its text
    shown, the height they are drawn in (Cut when they are taller and
    an ellipsis follows), and its top and height below the start of the
    section. Long when the text is taller than a card shows, so a line
    under it shows more or less of it (MoreRect, where the last paint
    drew its link). TextRect is where the last paint drew the text. }
  TGittanSummaryNoteBox = record
    Top, Height, TextHeight: integer;
    Rows: array of TGittanSummaryNoteRow;
    Cut, Long: boolean;
    LinkRect, TextRect, MoreRect: TRect;
  end;

  { TGittanSummary }

  TGittanSummary = class(TCustomControl)
  private
    FRepoName, FBranch, FBase, FSelected, FNotice: string;
    FStats: TGittanFileStats;
    FImages: TCustomImageList;
    FIconIndex: array of integer;
    { What a row shows in place of its counts and bar, '' for those. }
    FRowTexts: array of string;
    { A pill after a row's file name, '' for none, such as Resolve on a
      conflicted file; FActionRects are where they were last painted,
      FActionHot the row whose pill is under the mouse, -1 for none. }
    FRowActions: array of string;
    FActionRects: array of TRect;
    FActionHot: integer;
    FOnRowAction: TGittanSelectFileEvent;
    FHot: integer;
    FBack, FText, FDim, FHover, FSelectedBack, FAdded, FDeleted, FLine, FLink: TColor;
    FNotesTitle: string;
    FNotes: TGittanPullNotes;
    FNoteBoxes: array of TGittanSummaryNoteBox;
    { Each note's parts (CommentParts) and their markup (MarkdownToInk,
      the paths linked), made once per SetNotes: a new width lays them
      out again without parsing them or asking for the files again. }
    FNoteParts: array of TGittanCommentParts;
    FNoteMarkup: array of TStringArray;
    { The width the notes were laid out at, -1 when they are to be laid
      out again; their height, title included, 0 without notes. }
    FNotesWidth, FNotesHeight: integer;
    { The note whose link is under the mouse, -1 for none; FMoreHot the
      note whose Show more or Show less is. }
    FLinkHot, FMoreHot: integer;
    { The open pull requests waiting for the user's review, counted in
      a row under the conversation, a chip that drops a list of them
      through OnReviewClick; FReviewRect is the chip as last painted,
      FReviewHot whether the mouse is over it, FReviewHeight the row's
      height, 0 without any. }
    FReviewPulls: TGittanPullRequests;
    FForgeName: string;
    FReviewRect: TRect;
    FReviewHot: boolean;
    FReviewHeight: integer;
    FOnReviewClick: TGittanBranchClickEvent;
    { The commit compared with its parent, shown in a card under the
      header; an empty Hash shows none. FCardSubject is its subject and
      FCardLines its body, wrapped at FCardWidth (-1 to lay them out
      again), FCardHeight the card's
      share of the height, room after it included, 0 without one.
      FBackRect is the card's link back to the working tree. }
    FCommit: TGittanCommitLine;
    FCommitBody: string;
    FCardSubject, FCardLines: TStringArray;
    FCardWidth, FCardHeight: integer;
    FBackRect: TRect;
    FBackHot: boolean;
    FOnBackClick: TNotifyEvent;
    { Newer (0) and Older (1) at the right of the card's author line:
      whether each can be gone to, where it is (empty when not), and
      the one under the mouse, -1 for none. }
    FStepOn: array[0..1] of boolean;
    FStepRects: array[0..1] of TRect;
    FStepHot: integer;
    FOnCommitStep: TGittanCommitStepEvent;
    { The newest commits, shown under a clean tree, with how far the
      branch is from its upstream; FCommitHot is the row under the
      mouse, -1 for none. }
    FCommits: TGittanCommitLines;
    FAhead, FBehind: integer;
    FHasUpstream: boolean;
    { The branch was rewritten here since it was pushed: the upstream's
      commits it lacks are the ones it replaced, not ones to pull. }
    FRewritten: boolean;
    { A branch without an upstream: how many of its commits are on no
      remote, -1 without a remote (or with an upstream). }
    FNotOnRemote: integer;
    { The upstream is deleted on the remote: the sync line says so, in
      red after a cross, in place of the counts. }
    FUpstreamGone: boolean;
    FCommitsTop, FCommitHot: integer;
    FOnSelectCommit: TGittanSelectCommitEvent;
    FMeasure: TBitmap;
    { The layouts of the notes' Markdown. }
    FInk: THTMLLayoutCache;
    { Whether the mouse is on a link in a note's text, or on the summary
      of a <details> block in it. }
    FTextLinkHot, FDetailsHot: boolean;
    { The <details> blocks of the notes that are open (NoteDetailsKey). }
    FNotesOpen: TStringList;
    FOnSelectFile: TGittanSelectFileEvent;
    FOnContextFile: TGittanContextFileEvent;
    FOnBranchClick: TGittanBranchClickEvent;
    FOnOpenUrl: TGittanOpenUrlEvent;
    FOnFileExists: TGittanPathTest;
    FRowsTop: integer;
    { The height the content needs; the control is at least as high as
      the box it fills, see FitHeight. }
    FContentHeight: integer;
    { The branch's chip in the header, in client coordinates; empty
      without a branch. }
    FBranchRect: TRect;
    FBranchHot: boolean;
    { The base label's chip, drawn as one while BaseClickable, with its
      hover state. }
    FBaseRect: TRect;
    FBaseHot, FBaseClickable: boolean;
    FOnBaseClick: TGittanBranchClickEvent;
    { The sync line's chip ("↑ 3 not pushed · ↓ 2 not pulled"), drawn as
      one while OnSyncClick is set and the branch has an upstream, with
      its hover state. }
    FSyncRect: TRect;
    FSyncHot: boolean;
    FOnSyncClick: TGittanBranchClickEvent;
    { The totals' chip ("3 changed files +12 −4"), drawn as one while
      OnTotalsClick is set, with its hover state. }
    FTotalsRect: TRect;
    FTotalsHot: boolean;
    FOnTotalsClick: TGittanBranchClickEvent;
    { How many commits of FBehindRef (the default branch) the branch
      lacks, 0 for no row; the row's Rebase and Merge pills as last
      painted, and the one under the mouse, -1 for none. }
    FBehindCount: integer;
    FBehindRef: string;
    FBehindRects: array[0..1] of TRect;
    FBehindHot: integer;
    FOnBehindAction: TGittanBehindActionEvent;
    procedure SetSyncHot(AValue: boolean);
    procedure SetTotalsHot(AValue: boolean);
    function BehindAt(X, Y: integer): integer;
    procedure SetBehindHot(AValue: integer);
    procedure PaintBehind(var Y: integer);
    function BranchClickable: boolean;
    procedure SetBranchHot(AValue: boolean);
    procedure SetBaseHot(AValue: boolean);
    procedure SetBaseClickable(AValue: boolean);
    function RowAt(Y: integer): integer;
    function CommitAt(Y: integer): integer;
    procedure SetCommitHot(AValue: integer);
    function ShowsCommits: boolean;
    procedure PlaceCommits;
    procedure PaintCommits;
    procedure PaintCommit(AIndex, ATop, AHashWidth: integer);
    procedure SetHot(AValue: integer);
    function ActionAt(X, Y: integer): integer;
    procedure SetActionHot(AValue: integer);
    procedure SetLinkHot(AValue: integer);
    function LinkAt(X, Y: integer): integer;
    function NoteInkOptions: THTMLOptions;
    function TextLinkAt(X, Y: integer): string;
    function NoteDetailsKey(ANote, ADetail: integer): string;
    function NoteDetailsAt(X, Y: integer): string;
    function NoteMoreAt(X, Y: integer): integer;
    procedure SetMoreHot(AValue: integer);
    procedure LayoutNotes;
    procedure PaintNotes(var Y: integer);
    procedure SetReviewHot(AValue: boolean);
    procedure LayoutReview;
    procedure PaintReview(var Y: integer);
    procedure LayoutCard;
    procedure PaintCard(var Y: integer);
    procedure SetBackHot(AValue: boolean);
    procedure SetStepHot(AValue: integer);
    function PaintSteps(ARight, Y: integer): integer;
    function StepAt(X, Y: integer): integer;
    procedure SetSelected(const AValue: string);
    procedure SetNotice(const AValue: string);
    procedure UpdateHeight;
    procedure PaintNotice(var Y: integer);
    function CentersClean: boolean;
    function CleanText: string;
    function HeaderBlockHeight(ACanvas: TCanvas): integer;
    function CenterBlockHeight(ACanvas: TCanvas): integer;
    procedure DrawCheck(X, Y, ASize: integer);
    procedure PaintCleanHeader(Y: integer);
    procedure PaintCleanCentered;
    function PaintSync(X, Y: integer; ADraw: boolean = True): integer;
    function HasSyncLine: boolean;
    procedure PaintHeader(var Y: integer);
    procedure PaintRow(AIndex, ATop: integer);
    procedure PaintBar(X, Y: integer; const AStat: TGittanFileStat; AMax: integer);
    procedure PaintKinds(Y, ALeft, ARight: integer);
    function BarWidth: integer;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** Shows the changed files AStats of repository AName on ABranch,
      with ABase saying what is compared, as it is to be shown ("vs
      main", "main...feature"; empty for the usual HEAD); AIcons holds
      the image index in Images of each file's badge, and ATexts what to
      show in place of a row's counts and bar, such as the commits a
      submodule moved between; empty for the counts. AActions holds a
      pill to show after a row's file name, '' for none; a click on it
      raises OnRowAction. }
    procedure SetRepository(const AName, ABranch, ABase: string;
      const AStats: TGittanFileStats; const AIcons: array of integer;
      const ATexts, AActions: array of string);
    {** Sets the palette: the background, the text, the dim text for paths
      and counts, the hovered row, the selected row, the added and deleted
      colors, and the line color for the divider and the empty part of a
      bar. }
    procedure SetColors(ABack, AText, ADim, AHover, ASelected, AAdded,
      ADeleted, ALine: TColor);
    {** Makes the control at least AMin high (the height of the box it
      sits in, so its background covers the box), and no higher than
      its content needs beyond that: a minimum constraint alone would
      leave it at an old, larger height when the box shrinks, and the
      box would scroll. }
    procedure FitHeight(AMin: integer);
    {** Shows ANotes, the conversation of a pull request, under the
      heading ATitle; no notes shows none. }
    procedure SetNotes(const ATitle: string; const ANotes: TGittanPullNotes);
    {** Counts APulls, the open pull requests waiting for the user's
      review, in a row under the conversation; nil shows none. }
    procedure SetReviewPulls(const APulls: TGittanPullRequests);
    {** Shows ACommit, the commit the files are compared through (with
      its parent), in a card under the header with ABody, the rest of
      its message; an empty Hash shows none. }
    procedure SetCommit(const ACommit: TGittanCommitLine; const ABody: string);
    {** Whether the card offers Newer and Older (OnCommitStep); neither
      shows when both are off. }
    procedure SetCommitSteps(ANewer, AOlder: boolean);
    {** Shows ACommits, the newest commits of HEAD, under "Working tree
      clean", and after it how many commits the branch is ahead of
      (AAhead) and behind (ABehind) its upstream when it has one
      (AHasUpstream), or, without one, how many are on no remote yet
      (ANotOnRemote; -1 says nothing, as without a remote). ARewritten
      says the commits behind were replaced here (a rebase or an amend
      of pushed commits). The commits show only while there are no
      changed files and some are not pushed. }
    procedure SetCommits(const ACommits: TGittanCommitLines;
      AAhead, ABehind: integer; AHasUpstream: boolean; ANotOnRemote: integer = -1;
      ARewritten: boolean = False);
    {** Whether the upstream is deleted on the remote, which the sync
      line then says in place of the counts. }
    procedure SetUpstreamGone(AGone: boolean);
    {** Shows a row under the header saying the branch lacks ACount
      commits of ARef, the default branch, with Rebase and Merge, which
      raise OnBehindAction; 0 shows none. }
    procedure SetBehind(ACount: integer; const ARef: string);
    {** The color of the notes' links. }
    property LinkColor: TColor read FLink write FLink;
    {** The image list the file badges come from. }
    property Images: TCustomImageList read FImages write FImages;
    {** The path of the file whose row is marked: the one the editor last
      showed. Empty marks none. }
    property Selected: string read FSelected write SetSelected;
    {** A line under the header, dimmed: why the summary is shown when
      the user did not ask for it. Empty shows none. }
    property Notice: string read FNotice write SetNotice;
    {** A click on a file's row. }
    property OnSelectFile: TGittanSelectFileEvent read FOnSelectFile write FOnSelectFile;
    {** A click on the pill of a file's row (see SetRepository). }
    property OnRowAction: TGittanSelectFileEvent read FOnRowAction write FOnRowAction;
    {** A right click on a file's row. }
    property OnContextFile: TGittanContextFileEvent read FOnContextFile write FOnContextFile;
    {** A click on the branch in the header. While it is set the branch
      is drawn as a chip with a chevron, highlighted under the mouse. }
    property OnBranchClick: TGittanBranchClickEvent read FOnBranchClick write FOnBranchClick;
    {** A click on the base label in the header, which is drawn as a chip
      with a chevron while BaseClickable is set (for a base that has
      actions, such as a branch to merge). }
    property OnBaseClick: TGittanBranchClickEvent read FOnBaseClick write FOnBaseClick;
    property BaseClickable: boolean read FBaseClickable write SetBaseClickable;
    {** A click on the sync line (the commits not pushed or not pulled),
      which is drawn as a chip under the mouse while this is set and the
      branch has an upstream. }
    property OnSyncClick: TGittanBranchClickEvent read FOnSyncClick write FOnSyncClick;
    {** A click on the totals under the header (the changed files and
      their lines), which are drawn as a chip with a chevron while this
      is set and there are changed files. }
    property OnTotalsClick: TGittanBranchClickEvent read FOnTotalsClick write FOnTotalsClick;
    {** A click on Rebase or Merge in the row of SetBehind. }
    property OnBehindAction: TGittanBehindActionEvent read FOnBehindAction write FOnBehindAction;
    {** A click on a commit's row. }
    property OnSelectCommit: TGittanSelectCommitEvent read FOnSelectCommit write FOnSelectCommit;
    {** The forge the notes are on, by name, for their links. }
    property ForgeName: string read FForgeName write FForgeName;
    {** A click on a note's link to the forge. }
    property OnOpenUrl: TGittanOpenUrlEvent read FOnOpenUrl write FOnOpenUrl;
    {** Whether a path is a file of the repository: a path in a note's
      text that is one becomes a link to it (LinkFilePaths), which goes to
      OnOpenUrl. }
    property OnFileExists: TGittanPathTest read FOnFileExists write FOnFileExists;
    {** A click on the row counting the pull requests waiting for the
      user's review, with the chip's rectangle in screen coordinates
      for a list to drop from; without it the row is not a chip. }
    property OnReviewClick: TGittanBranchClickEvent read FOnReviewClick write FOnReviewClick;
    {** A click on the commit card's link back to the working tree. }
    property OnBackClick: TNotifyEvent read FOnBackClick write FOnBackClick;
    property OnCommitStep: TGittanCommitStepEvent read FOnCommitStep write FOnCommitStep;
  end;

{** A line about a pull request for a list's detail: who opened it, how
  long ago and whether it is a draft, with dots between; short, since
  the detail takes its room from the title. }
function ReviewPullLine(const APull: TGittanPullRequest): string;

implementation

uses
  Math, DateUtils, LazUTF8, StrUtils, InkMarkdown, gittan.textfit, gittan.theme, Forms;

resourcestring
  rsOneFile = '1 changed file';
  rsManyFiles = '%d changed files';
  rsClean = 'Working tree clean';
  rsCleanVs = 'No changes %s';
  rsRecentCommits = 'Recent commits';
  rsNotPushed = '%d not pushed';
  rsNotPulled = '%d not pulled';
  rsReplacedHere = '%d replaced here';
  rsInSync = 'up to date with upstream';
  rsNotOnRemote = '%d not on the remote yet';
  rsBranchNotOnRemote = 'branch not on the remote yet';
  rsBehindOne = '1 commit behind %s';
  rsBehindMany = '%d commits behind %s';
  rsBehindRebase = 'Rebase';
  rsBehindMerge = 'Merge';
  rsUpstreamGone = '✕ upstream deleted on remote';
  rsBinary = 'binary';
  rsStaged = 'staged';
  rsPartlyStaged = 'partly staged';
  rsNoteCommented = 'commented';
  rsNoteApproved = 'approved';
  rsNoteChangesRequested = 'requested changes';
  rsNoteDismissed = 'review dismissed';
  rsNoteLink = '%s ↗';
  rsNoteMore = 'Show more';
  rsNoteLess = 'Show less';
  rsReviewOne = '1 pull request needs your review';
  rsReviewMany = '%d pull requests need your review';
  rsReviewOpened = 'opened %s';
  rsReviewDraft = 'draft';
  rsBackToTree = 'Back to Working Tree';
  rsNewerCommit = '‹ Newer';
  rsOlderCommit = 'Older ›';

const
  { The count of each kind in the header, after a dot in its color. }
  KindCount: array[TGittanChangeKind] of string = ('%d modified', '%d added',
    '%d deleted', '%d renamed', '%d untracked', '%d conflicted');
  Pad = 24;
  RowHeight = 30;
  IconSize = 16;
  { The row bars take a share of the width, within these. }
  MinBarWidth = 96;
  MaxBarWidth = 200;
  TotalBarWidth = 140;
  BarHeight = 6;
  DotSize = 8;
  CountWidth = 56;
  Gap = 12;
  TitleFontSize = 20;
  CheckSize = 20;
  { "Working tree clean", larger than the body; its check in the header
    and alone in the middle. }
  CleanFontSize = 15;
  HeaderCheck = 34;
  CenterCheck = 64;
  ChipPadX = 6;
  ChipPadY = 3;
  ChevronWidth = 14;
  { Between the branch icon and the name, as in the status bar. }
  IconGap = 5;
  { A note's card: room inside it, between cards, the colored stripe at
    its left, and the most lines of text it shows (the rest is on
    the forge). }
  NotePadX = 12;
  NotePadY = 8;
  NoteGap = 8;
  NoteStripe = 3;
  { How far the text in a <details> block is indented, per level. }
  NoteIndent = 14;
  NoteMaxLines = 12;
  { The most lines a commit's subject takes in its card. }
  SubjectMaxLines = 3;

{ TGittanSummary }

constructor TGittanSummary.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FHot := -1;
  FActionHot := -1;
  FLinkHot := -1;
  FStepHot := -1;
  FMoreHot := -1;
  FCommitHot := -1;
  FBehindHot := -1;
  FNotOnRemote := -1;
  FNotesWidth := -1;
  FCardWidth := -1;
  FLink := clHighlight;
  FMeasure := TBitmap.Create;
  FInk := THTMLLayoutCache.Create;
  FNotesOpen := TStringList.Create;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnFace, clGreen,
    clRed, clBtnShadow);
  { The height follows the content; the scroll box it sits in scrolls. }
  Align := alTop;
  UpdateHeight;
end;

destructor TGittanSummary.Destroy;
begin
  FMeasure.Free;
  FInk.Free;
  FNotesOpen.Free;
  inherited Destroy;
end;

procedure TGittanSummary.SetRepository(const AName, ABranch, ABase: string;
  const AStats: TGittanFileStats; const AIcons: array of integer;
  const ATexts, AActions: array of string);
var
  i: integer;
begin
  SetLength(FRowTexts, Length(ATexts));
  for i := 0 to High(ATexts) do
    FRowTexts[i] := ATexts[i];
  SetLength(FRowActions, Length(AActions));
  for i := 0 to High(AActions) do
    FRowActions[i] := AActions[i];
  FActionRects := nil;
  SetLength(FActionRects, Length(AStats));
  FActionHot := -1;
  FRepoName := AName;
  FBranch := ABranch;
  FBase := ABase;
  FStats := Copy(AStats);
  SetLength(FIconIndex, Length(AIcons));
  for i := 0 to High(AIcons) do
    FIconIndex[i] := AIcons[i];
  FHot := -1;
  UpdateHeight;
  Invalidate;
end;

procedure TGittanSummary.SetCommits(const ACommits: TGittanCommitLines;
  AAhead, ABehind: integer; AHasUpstream: boolean; ANotOnRemote: integer;
  ARewritten: boolean);
begin
  FCommits := Copy(ACommits);
  FAhead := AAhead;
  FBehind := ABehind;
  FHasUpstream := AHasUpstream;
  FRewritten := AHasUpstream and ARewritten;
  if AHasUpstream then
    FNotOnRemote := -1
  else
    FNotOnRemote := ANotOnRemote;
  FCommitHot := -1;
  UpdateHeight;
  Invalidate;
end;

{ The commits are listed while some wait to be pushed, to the upstream
  or, for a branch without one, to the remote; a branch that is pushed
  has nothing to act on, so its clean state stands alone. }
procedure TGittanSummary.SetUpstreamGone(AGone: boolean);
begin
  if FUpstreamGone = AGone then
    Exit;
  FUpstreamGone := AGone;
  Invalidate;
end;

procedure TGittanSummary.SetBehind(ACount: integer; const ARef: string);
begin
  if ARef = '' then
    ACount := 0;
  if (FBehindCount = ACount) and (FBehindRef = ARef) then
    Exit;
  FBehindCount := ACount;
  FBehindRef := ARef;
  FBehindHot := -1;
  FBehindRects[0] := Rect(0, 0, 0, 0);
  FBehindRects[1] := Rect(0, 0, 0, 0);
  UpdateHeight;
  Invalidate;
end;

function TGittanSummary.BehindAt(X, Y: integer): integer;
var
  i: integer;
begin
  Result := -1;
  if FBehindCount > 0 then
    for i := 0 to 1 do
      if PtInRect(FBehindRects[i], Point(X, Y)) then
        Exit(i);
end;

procedure TGittanSummary.SetBehindHot(AValue: integer);
begin
  if FBehindHot = AValue then
    Exit;
  FBehindHot := AValue;
  Invalidate;
end;

{ "↓ 12 commits behind origin/main" and the Rebase and Merge pills, as a
  row's pill is drawn, in the row above the files. Y is advanced past
  it. }
procedure TGittanSummary.PaintBehind(var Y: integer);
var
  X, TextY, BodyHeight, W, i: integer;
  Part: string;
  R: TRect;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  BodyHeight := Canvas.TextHeight('Xg');
  TextY := Y + (Px(RowHeight) - BodyHeight) div 2;
  X := Px(Pad);
  if FBehindCount = 1 then
    Part := Format(rsBehindOne, [FBehindRef])
  else
    Part := Format(rsBehindMany, [FBehindCount, FBehindRef]);
  Canvas.Font.Color := FText;
  Canvas.TextOut(X, TextY, '↓ ' + Part);
  Inc(X, Canvas.TextWidth('↓ ' + Part) + Px(Gap));
  for i := 0 to 1 do
  begin
    if i = 0 then
      Part := rsBehindRebase
    else
      Part := rsBehindMerge;
    W := Canvas.TextWidth(Part) + 2 * Px(ChipPadX);
    R := Rect(X, TextY - Px(ChipPadY), X + W, TextY + BodyHeight + Px(ChipPadY));
    FBehindRects[i] := R;
    Canvas.Pen.Color := FLine;
    Canvas.Brush.Style := bsSolid;
    if i = FBehindHot then
      Canvas.Brush.Color := FHover
    else
      Canvas.Brush.Color := FBack;
    Canvas.RoundRect(R, R.Height, R.Height);
    Canvas.Brush.Style := bsClear;
    if i = FBehindHot then
      Canvas.Font.Color := FLink
    else
      Canvas.Font.Color := FText;
    Canvas.TextOut(X + Px(ChipPadX), TextY, Part);
    Inc(X, W + Px(Gap) div 2);
  end;
  Inc(Y, Px(RowHeight));
end;

function TGittanSummary.ShowsCommits: boolean;
begin
  Result := (Length(FStats) = 0) and (Length(FCommits) > 0) and
    ((FHasUpstream and (FAhead > 0)) or (FNotOnRemote > 0));
end;

{ Under a clean tree the commits take the place of the file rows, after
  their heading. Sets FCommitsTop and FContentHeight from FRowsTop. }
procedure TGittanSummary.PlaceCommits;
var
  BodyHeight: integer;
begin
  FMeasure.Canvas.Font := Font;
  BodyHeight := FMeasure.Canvas.TextHeight('Xg');
  FCommitsTop := FRowsTop + BodyHeight + Px(NoteGap);
  if ShowsCommits then
    FContentHeight := FCommitsTop + Length(FCommits) * Px(RowHeight) + Px(Pad)
  else if CentersClean then
    FContentHeight := FRowsTop + CenterBlockHeight(FMeasure.Canvas) + 2 * Px(Pad)
  else
    FContentHeight := FRowsTop + Max(Length(FStats), 2) * Px(RowHeight) + Px(Pad);
end;

{ A clean tree with nothing else to show: no commits, no conversation. }
function TGittanSummary.CentersClean: boolean;
begin
  Result := (Length(FStats) = 0) and not ShowsCommits and (Length(FNotes) = 0) and
    (Length(FReviewPulls) = 0);
end;

{ "Working tree clean", or "No changes vs base" when the tree is
  compared against something other than HEAD. }
function TGittanSummary.CleanText: string;
begin
  if FBase = '' then
    Result := rsClean
  else
    Result := Format(rsCleanVs, [FBase]);
end;

{ The height of the header under the title: the totals line, the clean
  check with its text and the sync line, or nothing when the clean
  state stands in the middle. }
function TGittanSummary.HeaderBlockHeight(ACanvas: TCanvas): integer;
var
  BodyHeight: integer;
begin
  ACanvas.Font := Font;
  BodyHeight := ACanvas.TextHeight('Xg');
  if Length(FStats) > 0 then
    Exit(BodyHeight);
  if CentersClean then
    Exit(0);
  ACanvas.Font.Size := CleanFontSize;
  Result := ACanvas.TextHeight('Xg');
  if HasSyncLine then
    Inc(Result, 2 + BodyHeight);
  Result := Max(Result, Px(HeaderCheck));
end;

{ The height of the clean state in the middle: the check, the text and
  the sync line. }
function TGittanSummary.CenterBlockHeight(ACanvas: TCanvas): integer;
var
  BodyHeight: integer;
begin
  ACanvas.Font := Font;
  BodyHeight := ACanvas.TextHeight('Xg');
  ACanvas.Font.Size := CleanFontSize;
  Result := Px(CenterCheck) + Px(Gap) + ACanvas.TextHeight('Xg');
  if HasSyncLine then
    Inc(Result, 4 + BodyHeight);
end;

procedure TGittanSummary.SetColors(ABack, AText, ADim, AHover, ASelected,
  AAdded, ADeleted, ALine: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
  FSelectedBack := ASelected;
  FAdded := AAdded;
  FDeleted := ADeleted;
  FLine := ALine;
  Color := ABack;
  Invalidate;
end;

{ The header is measured in Paint, so the height is an estimate from the
  font until the first paint settles it. }
procedure TGittanSummary.UpdateHeight;
var
  C: TCanvas;
  TitleHeight, BodyHeight: integer;
begin
  C := MeasureCanvas(Font);
  BodyHeight := C.TextHeight('Xg');
  C.Font.Size := TitleFontSize;
  TitleHeight := C.TextHeight('Xg');
  FRowsTop := Px(Pad) + TitleHeight + 6 + HeaderBlockHeight(FMeasure.Canvas) + Px(Pad);
  if FNotice <> '' then
    Inc(FRowsTop, Px(RowHeight));
  if FBehindCount > 0 then
    Inc(FRowsTop, Px(RowHeight));
  LayoutCard;
  Inc(FRowsTop, FCardHeight);
  LayoutNotes;
  Inc(FRowsTop, FNotesHeight);
  LayoutReview;
  Inc(FRowsTop, FReviewHeight);
  PlaceCommits;
  Height := Max(FContentHeight, Constraints.MinHeight);
end;

procedure TGittanSummary.FitHeight(AMin: integer);
begin
  Constraints.MinHeight := AMin;
  Height := Max(FContentHeight, AMin);
end;

procedure TGittanSummary.SetNotes(const ATitle: string; const ANotes: TGittanPullNotes);
begin
  FNotesTitle := ATitle;
  FNotes := Copy(ANotes);
  FNoteParts := nil;
  FNoteMarkup := nil;
  FNotesWidth := -1;
  FLinkHot := -1;
  FMoreHot := -1;
  UpdateHeight;
  Invalidate;
end;

{ Adds AText to ALines wrapped at AInner pixels on C: at words, and
  inside a word longer than a line. }
procedure WrapText(C: TCanvas; const AText: string; AInner: integer;
  var ALines: TStringArray);
var
  Words: TStringList;
  Line, Part: string;
  w, n: integer;

  procedure Add(const ALine: string);
  begin
    SetLength(ALines, Length(ALines) + 1);
    ALines[High(ALines)] := ALine;
  end;

begin
  if C.TextWidth(AText) <= AInner then
  begin
    Add(AText);
    Exit;
  end;
  Words := TStringList.Create;
  try
    Words.Delimiter := ' ';
    Words.StrictDelimiter := True;
    Words.DelimitedText := AText;
    Line := '';
    for w := 0 to Words.Count - 1 do
    begin
      if Line = '' then
        Part := Words[w]
      else
        Part := Line + ' ' + Words[w];
      if C.TextWidth(Part) <= AInner then
      begin
        Line := Part;
        Continue;
      end;
      if Line <> '' then
        Add(Line);
      Line := Words[w];
      while (C.TextWidth(Line) > AInner) and (UTF8Length(Line) > 1) do
      begin
        n := UTF8Length(Line);
        while (n > 1) and (C.TextWidth(UTF8Copy(Line, 1, n)) > AInner) do
          Dec(n);
        Add(UTF8Copy(Line, 1, n));
        Line := UTF8Copy(Line, n + 1, MaxInt);
      end;
    end;
    if Line <> '' then
      Add(Line);
  finally
    Words.Free;
  end;
end;

{ Where the last paint drew part K of ABox's text, past its indent. }
function NoteRowRect(const ABox: TGittanSummaryNoteBox; K: integer): TRect;
begin
  Result := ABox.TextRect;
  Inc(Result.Left, ABox.Rows[K].Depth * Px(NoteIndent));
  Inc(Result.Top, ABox.Rows[K].Top);
  Result.Bottom := Result.Top + ABox.Rows[K].Height;
end;

{ Lays the notes out at the control's width, when it changed: each
  note's parts (CommentParts) as LazInk lays their Markdown out at that
  width, a <details> block as its summary after "▸", and after "▾" with
  the parts in it indented when it is open (FNotesOpen). The text is at
  most NoteMaxLines lines high with an ellipsis and Show more after,
  unless a block in it is open, since that was asked for, or Show more
  was clicked (NoteDetailsKey with -1 in FNotesOpen), when Show less
  follows it. }
procedure TGittanSummary.LayoutNotes;
var
  C: TCanvas;
  Inner, LineHeight, i, k, At, HideBelow: integer;
  Box: TGittanSummaryNoteBox;
  Parts: TGittanCommentParts;
  Row: TGittanSummaryNoteRow;
  AnyOpen: boolean;
begin
  if FNotesWidth = Width then
    Exit;
  FNotesWidth := Width;
  FNoteBoxes := nil;
  FNotesHeight := 0;
  if Length(FNotes) = 0 then
    Exit;
  C := FMeasure.Canvas;
  C.Font := Font;
  LineHeight := C.TextHeight('Xg');
  Inner := Max(40, Width - 2 * Px(Pad) - 2 * Px(NotePadX) - Px(NoteStripe));
  { The section's heading. }
  At := LineHeight + Px(NoteGap);
  if Length(FNoteParts) <> Length(FNotes) then
  begin
    SetLength(FNoteParts, Length(FNotes));
    SetLength(FNoteMarkup, Length(FNotes));
    for i := 0 to High(FNotes) do
    begin
      Parts := CommentParts(FNotes[i].Body);
      FNoteParts[i] := Parts;
      SetLength(FNoteMarkup[i], Length(Parts));
      for k := 0 to High(Parts) do
        if (Parts[k].Kind = cpText) and Assigned(FOnFileExists) then
          FNoteMarkup[i][k] := MarkdownToInk(LinkFilePaths(Parts[k].Text, FOnFileExists),
            [imoInlineHTML])
        else
          FNoteMarkup[i][k] := MarkdownToInk(Parts[k].Text, [imoInlineHTML]);
    end;
  end;
  SetLength(FNoteBoxes, Length(FNotes));
  for i := 0 to High(FNotes) do
  begin
    Box := Default(TGittanSummaryNoteBox);
    Parts := FNoteParts[i];
    HideBelow := MaxInt;
    AnyOpen := False;
    for k := 0 to High(Parts) do
    begin
      if Parts[k].Depth > HideBelow then
        Continue;
      HideBelow := MaxInt;
      Row := Default(TGittanSummaryNoteRow);
      Row.Depth := Parts[k].Depth;
      Row.Detail := -1;
      Row.Markup := FNoteMarkup[i][k];
      if Parts[k].Kind = cpDetails then
      begin
        Row.Detail := k;
        if FNotesOpen.IndexOf(NoteDetailsKey(i, k)) >= 0 then
        begin
          Row.Markup := '▾ ' + Row.Markup;
          AnyOpen := True;
        end
        else
        begin
          Row.Markup := '▸ ' + Row.Markup;
          HideBelow := Parts[k].Depth;
        end;
      end;
      if Length(Box.Rows) > 0 then
        Inc(Box.TextHeight, Px(4));
      Row.Top := Box.TextHeight;
      Row.Height := HTMLTextExtentOpt(C, Rect(0, 0, Max(40, Inner - Row.Depth * Px(NoteIndent)),
        100000), [], Row.Markup, NoteInkOptions, FInk).cy;
      Inc(Box.TextHeight, Row.Height);
      SetLength(Box.Rows, Length(Box.Rows) + 1);
      Box.Rows[High(Box.Rows)] := Row;
    end;
    Box.Long := not AnyOpen and (Box.TextHeight > NoteMaxLines * LineHeight);
    Box.Cut := Box.Long and (FNotesOpen.IndexOf(NoteDetailsKey(i, -1)) < 0);
    if Box.Cut then
      Box.TextHeight := NoteMaxLines * LineHeight;
    Box.Top := At;
    { The header line, then the text under a little room. }
    Box.Height := 2 * Px(NotePadY) + LineHeight;
    if Box.TextHeight > 0 then
      Inc(Box.Height, 4 + Box.TextHeight);
    if Box.Long then
      Inc(Box.Height, LineHeight);
    FNoteBoxes[i] := Box;
    Inc(At, Box.Height + Px(NoteGap));
  end;
  FNotesHeight := At + Px(Pad) div 2;
end;

{ The key in FNotesOpen of <details> block ADetail (its part) of note
  ANote: the note's address, else its place, and the part; ADetail -1
  is the whole text, shown past NoteMaxLines. }
function TGittanSummary.NoteDetailsKey(ANote, ADetail: integer): string;
begin
  if FNotes[ANote].Url <> '' then
    Result := FNotes[ANote].Url
  else
    Result := IntToStr(ANote);
  Result := Result + '#' + IntToStr(ADetail);
end;

{ The note whose Show more or Show less is at X, Y; -1 elsewhere. }
function TGittanSummary.NoteMoreAt(X, Y: integer): integer;
var
  i: integer;
begin
  Result := -1;
  for i := 0 to High(FNoteBoxes) do
    if PtInRect(FNoteBoxes[i].MoreRect, Point(X, Y)) then
      Exit(i);
end;

{ The key of the <details> block whose summary is at X, Y; '' elsewhere. }
function TGittanSummary.NoteDetailsAt(X, Y: integer): string;
var
  i, k: integer;
begin
  Result := '';
  for i := 0 to High(FNoteBoxes) do
    if PtInRect(FNoteBoxes[i].TextRect, Point(X, Y)) then
    begin
      for k := 0 to High(FNoteBoxes[i].Rows) do
        if (FNoteBoxes[i].Rows[k].Detail >= 0) and
          PtInRect(NoteRowRect(FNoteBoxes[i], k), Point(X, Y)) then
          Exit(NoteDetailsKey(i, FNoteBoxes[i].Rows[k].Detail));
      Exit;
    end;
end;

{ How LazInk draws a note's text: links in the link color. }
function TGittanSummary.NoteInkOptions: THTMLOptions;
begin
  Result := DefaultHTMLOptions;
  Result.LinkColor := FLink;
end;

{ The address of the link in a note's text at X, Y, when it goes to the
  web or to a file of the repository; '' elsewhere. }
function TGittanSummary.TextLinkAt(X, Y: integer): string;
var
  i, k: integer;
  Hit: THTMLHitInfo;
  R: TRect;
begin
  Result := '';
  for i := 0 to High(FNoteBoxes) do
    if PtInRect(FNoteBoxes[i].TextRect, Point(X, Y)) then
    begin
      FMeasure.Canvas.Font := Font;
      for k := 0 to High(FNoteBoxes[i].Rows) do
      begin
        R := NoteRowRect(FNoteBoxes[i], k);
        if not PtInRect(R, Point(X, Y)) then
          Continue;
        Hit := HTMLHitTest(FMeasure.Canvas, R, FNoteBoxes[i].Rows[k].Markup,
          NoteInkOptions, X, Y, FInk);
        if Hit.OnLink and (AnsiStartsText('https://', Hit.LinkName) or
          AnsiStartsText('http://', Hit.LinkName) or AnsiStartsText('mailto:', Hit.LinkName) or
          AnsiStartsText(FileLinkScheme, Hit.LinkName)) then
          Result := Hit.LinkName;
        Exit;
      end;
      Exit;
    end;
end;

{ The heading, then a card per note: a stripe in the color of the
  review's outcome, the author in bold, what they did and when, the link
  to GitHub at the right, and the text under them. Y is advanced past
  the section. }
procedure TGittanSummary.PaintNotes(var Y: integer);
var
  i, k, d, X, LineHeight, At: integer;
  Card, R: TRect;
  What, Age, Link: string;
  Tone: TColor;
begin
  LayoutNotes;
  if Length(FNoteBoxes) = 0 then
    Exit;
  Canvas.Font := Font;
  LineHeight := Canvas.TextHeight('Xg');
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FDim;
  Canvas.TextOut(Px(Pad), Y, FNotesTitle);
  for i := 0 to High(FNoteBoxes) do
  begin
    At := Y + FNoteBoxes[i].Top;
    Card := Rect(Px(Pad), At, Width - Px(Pad), At + FNoteBoxes[i].Height);
    case FNotes[i].Kind of
      pnApproved:
      begin
        What := rsNoteApproved;
        Tone := FAdded;
      end;
      pnChangesRequested:
      begin
        What := rsNoteChangesRequested;
        Tone := FDeleted;
      end;
      pnDismissed:
      begin
        What := rsNoteDismissed;
        Tone := FDim;
      end;
      else
      begin
        What := rsNoteCommented;
        Tone := FLine;
      end;
    end;
    Canvas.Pen.Color := FLine;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FSelectedBack;
    Canvas.RoundRect(Card, 8, 8);
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Color := Tone;
    Canvas.RoundRect(Card.Left, Card.Top, Card.Left + 2 * Px(NoteStripe), Card.Bottom, 4, 4);
    Canvas.Brush.Color := FSelectedBack;
    Canvas.FillRect(Card.Left + Px(NoteStripe), Card.Top + 1, Card.Left + 2 * Px(NoteStripe),
      Card.Bottom - 1);
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsClear;

    X := Card.Left + Px(NoteStripe) + Px(NotePadX);
    At := Card.Top + Px(NotePadY);
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := FText;
    Canvas.TextOut(X, At, FNotes[i].Author);
    Inc(X, Canvas.TextWidth(FNotes[i].Author) + Px(Gap) div 2);
    Canvas.Font.Style := [];
    if FNotes[i].Kind in [pnApproved, pnChangesRequested] then
      Canvas.Font.Color := Tone
    else
      Canvas.Font.Color := FDim;
    Canvas.TextOut(X, At, What);
    Inc(X, Canvas.TextWidth(What));
    Age := ReviewAge(FNotes[i].Created, LocalTimeToUniversal(Now));
    if Age <> '' then
    begin
      Canvas.Font.Color := FDim;
      Canvas.TextOut(X, At, ' · ' + Age);
    end;
    FNoteBoxes[i].LinkRect := Rect(0, 0, 0, 0);
    if FNotes[i].Url <> '' then
    begin
      Link := Format(rsNoteLink, [FForgeName]);
      FNoteBoxes[i].LinkRect := Rect(Card.Right - Px(NotePadX) - Canvas.TextWidth(Link),
        At, Card.Right - Px(NotePadX), At + LineHeight);
      Canvas.Font.Color := FLink;
      if i = FLinkHot then
        Canvas.Font.Style := [fsUnderline];
      Canvas.TextOut(FNoteBoxes[i].LinkRect.Left, At, Link);
      Canvas.Font.Style := [];
    end;

    Inc(At, LineHeight + 4);
    Canvas.Font.Color := FText;
    X := Card.Left + Px(NoteStripe) + Px(NotePadX);
    FNoteBoxes[i].TextRect := Rect(X, At, Card.Right - Px(NotePadX), At + FNoteBoxes[i].TextHeight);
    if FNoteBoxes[i].TextHeight > 0 then
    begin
      Canvas.Clipping := True;
      Canvas.ClipRect := FNoteBoxes[i].TextRect;
      try
        for k := 0 to High(FNoteBoxes[i].Rows) do
        begin
          R := NoteRowRect(FNoteBoxes[i], k);
          { A rule down the left of each level of <details> a part is in. }
          Canvas.Pen.Color := FLine;
          for d := 1 to FNoteBoxes[i].Rows[k].Depth do
            Canvas.Line(X + (d - 1) * Px(NoteIndent) + Px(4), R.Top,
              X + (d - 1) * Px(NoteIndent) + Px(4), R.Bottom);
          Canvas.Font := Font;
          if FNoteBoxes[i].Rows[k].Detail >= 0 then
            Canvas.Font.Color := FDim
          else
            Canvas.Font.Color := FText;
          Canvas.Brush.Style := bsClear;
          HTMLDrawOpt(Canvas, R, [], FNoteBoxes[i].Rows[k].Markup, NoteInkOptions, FInk);
        end;
      finally
        Canvas.Clipping := False;
      end;
      Canvas.Font := Font;
      Canvas.Brush.Style := bsClear;
    end;
    FNoteBoxes[i].MoreRect := Rect(0, 0, 0, 0);
    if FNoteBoxes[i].Long then
    begin
      At := FNoteBoxes[i].TextRect.Bottom;
      if FNoteBoxes[i].Cut then
      begin
        Canvas.Font.Color := FDim;
        Canvas.TextOut(X, At, '… ');
        Inc(X, Canvas.TextWidth('… '));
        Link := rsNoteMore;
      end
      else
        Link := rsNoteLess;
      FNoteBoxes[i].MoreRect := Rect(X, At, X + Canvas.TextWidth(Link), At + LineHeight);
      Canvas.Font.Color := FLink;
      if i = FMoreHot then
        Canvas.Font.Style := [fsUnderline];
      Canvas.TextOut(X, At, Link);
      Canvas.Font.Style := [];
    end;
  end;
  Inc(Y, FNotesHeight);
end;

{ Whether the cards would show the same: the same pull requests, as
  titled and last changed. }
function SamePulls(const A, B: TGittanPullRequests): boolean;
var
  i: integer;
begin
  Result := Length(A) = Length(B);
  if Result then
    for i := 0 to High(A) do
      if (A[i].Number <> B[i].Number) or (A[i].Title <> B[i].Title) or
        (A[i].Author <> B[i].Author) or (A[i].Updated <> B[i].Updated) or
        (A[i].IsDraft <> B[i].IsDraft) then
        Exit(False);
end;

procedure TGittanSummary.SetReviewPulls(const APulls: TGittanPullRequests);
begin
  if SamePulls(APulls, FReviewPulls) then
    Exit;
  FReviewPulls := Copy(APulls);
  FReviewRect := Rect(0, 0, 0, 0);
  FReviewHot := False;
  UpdateHeight;
  Invalidate;
end;

procedure TGittanSummary.SetReviewHot(AValue: boolean);
begin
  if FReviewHot = AValue then
    Exit;
  FReviewHot := AValue;
  if AValue then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  Invalidate;
end;

procedure TGittanSummary.LayoutReview;
begin
  FReviewHeight := 0;
  if Length(FReviewPulls) > 0 then
    FReviewHeight := Px(RowHeight);
end;

function ReviewPullLine(const APull: TGittanPullRequest): string;

  procedure Add(const APart: string);
  begin
    if APart = '' then
      Exit;
    if Result <> '' then
      Result := Result + ' · ';
    Result := Result + APart;
  end;

begin
  Result := '';
  Add(APull.Author);
  if APull.Created > 0 then
    Add(Format(rsReviewOpened, [ReviewAge(APull.Created, LocalTimeToUniversal(Now))]));
  if APull.IsDraft then
    Add(rsReviewDraft);
end;

{ The row counting the pull requests waiting for the user's review:
  the pull request icon and "3 pull requests need your review", a chip
  with a dimmed chevron while a click drops the list, filled under the
  mouse as the branch chip is. Y is advanced past the row. }
procedure TGittanSummary.PaintReview(var Y: integer);
var
  X, TextY, BodyHeight, IconW: integer;
  Line: string;
begin
  FReviewRect := Rect(0, 0, 0, 0);
  if Length(FReviewPulls) = 0 then
    Exit;
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  BodyHeight := Canvas.TextHeight('Xg');
  TextY := Y + (Px(RowHeight) - BodyHeight) div 2;
  X := Px(Pad);
  IconW := BodyHeight - 4 + Px(IconGap);
  if Length(FReviewPulls) = 1 then
    Line := rsReviewOne
  else
    Line := Format(rsReviewMany, [Length(FReviewPulls)]);
  if Assigned(FOnReviewClick) then
  begin
    FReviewRect := Rect(X - Px(ChipPadX), TextY - Px(ChipPadY),
      X + IconW + Canvas.TextWidth(Line) + Px(ChevronWidth) + Px(ChipPadX),
      TextY + BodyHeight + Px(ChipPadY));
    if FReviewHot then
      FillHover(Canvas, FReviewRect, 8, FHover);
  end;
  DrawStatusIcon(Canvas, HintPull, X, TextY, BodyHeight, FDim);
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  Inc(X, IconW);
  Canvas.Font.Color := FText;
  Canvas.TextOut(X, TextY, Line);
  Inc(X, Canvas.TextWidth(Line));
  if Assigned(FOnReviewClick) then
  begin
    Inc(X, Px(ChevronWidth) div 2 + 1);
    DrawChevron(Canvas, X, TextY + BodyHeight div 2, FDim);
  end;
  Inc(Y, Px(RowHeight));
end;

procedure TGittanSummary.SetCommit(const ACommit: TGittanCommitLine; const ABody: string);
begin
  if (FCommit.Hash = ACommit.Hash) and (FCommitBody = ABody) then
    Exit;
  FCommit := ACommit;
  FCommitBody := ABody;
  FCardWidth := -1;
  FBackHot := False;
  FStepHot := -1;
  UpdateHeight;
  Invalidate;
end;

procedure TGittanSummary.SetCommitSteps(ANewer, AOlder: boolean);
begin
  if (FStepOn[0] = ANewer) and (FStepOn[1] = AOlder) then
    Exit;
  FStepOn[0] := ANewer;
  FStepOn[1] := AOlder;
  FStepHot := -1;
  Invalidate;
end;

{ Lays the commit's card out at the control's width, when it changed:
  the subject in bold, wrapped short of the link at the right, at most
  SubjectMaxLines lines; the author and age line; and the body wrapped
  as a note's text is, its blank lines kept but not doubled, at most
  NoteMaxLines lines with an ellipsis after. }
procedure TGittanSummary.LayoutCard;
var
  C: TCanvas;
  Inner, SubjectRoom, LineHeight, i, n: integer;
  Paras: TStringList;
  Para, Last: string;
begin
  if FCardWidth = Width then
    Exit;
  FCardWidth := Width;
  FCardSubject := nil;
  FCardLines := nil;
  FCardHeight := 0;
  if FCommit.Hash = '' then
    Exit;
  C := FMeasure.Canvas;
  C.Font := Font;
  LineHeight := C.TextHeight('Xg');
  Inner := Max(40, Width - 2 * Px(Pad) - 2 * Px(NotePadX) - Px(NoteStripe));
  SubjectRoom := Max(40, Inner - C.TextWidth(rsBackToTree) - Px(Gap));
  C.Font.Style := [fsBold];
  WrapText(C, FCommit.Subject, SubjectRoom, FCardSubject);
  if Length(FCardSubject) > SubjectMaxLines then
  begin
    SetLength(FCardSubject, SubjectMaxLines);
    Last := FCardSubject[High(FCardSubject)];
    n := UTF8Length(Last);
    while (n > 0) and (C.TextWidth(UTF8Copy(Last, 1, n) + '…') > SubjectRoom) do
      Dec(n);
    FCardSubject[High(FCardSubject)] := TrimRight(UTF8Copy(Last, 1, n)) + '…';
  end;
  C.Font.Style := [];
  Paras := TStringList.Create;
  try
    Paras.Text := FCommitBody;
    for i := 0 to Paras.Count - 1 do
    begin
      Para := TrimRight(Paras[i]);
      if Para = '' then
      begin
        if (Length(FCardLines) > 0) and (FCardLines[High(FCardLines)] <> '') then
        begin
          SetLength(FCardLines, Length(FCardLines) + 1);
          FCardLines[High(FCardLines)] := '';
        end;
      end
      else
        WrapText(C, Para, Inner, FCardLines);
      if Length(FCardLines) > NoteMaxLines then
        Break;
    end;
  finally
    Paras.Free;
  end;
  if Length(FCardLines) > NoteMaxLines then
  begin
    SetLength(FCardLines, NoteMaxLines);
    FCardLines[High(FCardLines)] := '…';
  end;
  FCardHeight := 2 * Px(NotePadY) + (Length(FCardSubject) + 1) * LineHeight + 2;
  if Length(FCardLines) > 0 then
    Inc(FCardHeight, 6 + Length(FCardLines) * LineHeight);
  Inc(FCardHeight, Px(NoteGap) + Px(Pad) div 2);
end;

{ A card as a note's, with a stripe in the link color: the subject in
  bold with the link back to the working tree at the right of its first
  line, the author,
  the age and the short id dimmed under it, then the body. Y is
  advanced past it. }
procedure TGittanSummary.PaintCard(var Y: integer);
var
  Card: TRect;
  X, At, LineHeight, k, Room: integer;
  Meta: string;
begin
  LayoutCard;
  FBackRect := Rect(0, 0, 0, 0);
  FStepRects[0] := Rect(0, 0, 0, 0);
  FStepRects[1] := Rect(0, 0, 0, 0);
  if FCardHeight = 0 then
    Exit;
  Canvas.Font := Font;
  LineHeight := Canvas.TextHeight('Xg');
  Card := Rect(Px(Pad), Y, Width - Px(Pad), Y + FCardHeight - Px(NoteGap) - Px(Pad) div 2);
  Canvas.Pen.Color := FLine;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FSelectedBack;
  Canvas.RoundRect(Card, 8, 8);
  Canvas.Pen.Style := psClear;
  Canvas.Brush.Color := FLink;
  Canvas.RoundRect(Card.Left, Card.Top, Card.Left + 2 * Px(NoteStripe), Card.Bottom, 4, 4);
  Canvas.Brush.Color := FSelectedBack;
  Canvas.FillRect(Card.Left + Px(NoteStripe), Card.Top + 1, Card.Left + 2 * Px(NoteStripe),
    Card.Bottom - 1);
  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Style := bsClear;

  X := Card.Left + Px(NoteStripe) + Px(NotePadX);
  At := Card.Top + Px(NotePadY);
  FBackRect := Rect(Card.Right - Px(NotePadX) - Canvas.TextWidth(rsBackToTree), At,
    Card.Right - Px(NotePadX), At + LineHeight);
  Canvas.Font.Color := FLink;
  if FBackHot then
    Canvas.Font.Style := [fsUnderline];
  Canvas.TextOut(FBackRect.Left, At, rsBackToTree);

  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FText;
  for k := 0 to High(FCardSubject) do
  begin
    Canvas.TextOut(X, At, FCardSubject[k]);
    Inc(At, LineHeight);
  end;
  Canvas.Font.Style := [];

  Inc(At, 2);
  Meta := FCommit.Author;
  if FCommit.Date > 0 then
  begin
    if Meta <> '' then
      Meta := Meta + ' · ';
    Meta := Meta + ReviewAge(FCommit.Date, LocalTimeToUniversal(Now));
  end;
  if Meta <> '' then
    Meta := Meta + ' · ';
  Meta := Meta + FCommit.Short;
  { The steps first, so the line is cut short of them. }
  Room := PaintSteps(Card.Right - Px(NotePadX), At) - X;
  Canvas.Font.Color := FDim;
  Canvas.TextOut(X, At, FitTextRight(Canvas, Meta, Room));

  Inc(At, LineHeight + 6);
  Canvas.Font.Color := FText;
  for k := 0 to High(FCardLines) do
  begin
    Canvas.TextOut(X, At, FCardLines[k]);
    Inc(At, LineHeight);
  end;
  Inc(Y, FCardHeight);
end;

{ Newer and Older, right-aligned at ARight on the line at Y: in the link
  color while they lead somewhere, underlined under the mouse, dimmed
  and without a target when not; neither when both are off. Answers
  where the line's other text must end: a gap left of them, ARight
  without them. }
function TGittanSummary.PaintSteps(ARight, Y: integer): integer;
const
  Captions: array[0..1] of string = (rsNewerCommit, rsOlderCommit);
var
  k, X, W: integer;
begin
  FStepRects[0] := Rect(0, 0, 0, 0);
  FStepRects[1] := Rect(0, 0, 0, 0);
  Result := ARight;
  if not Assigned(FOnCommitStep) or not (FStepOn[0] or FStepOn[1]) then
    Exit;
  X := ARight;
  for k := 1 downto 0 do
  begin
    W := Canvas.TextWidth(Captions[k]);
    Dec(X, W);
    if FStepOn[k] then
    begin
      FStepRects[k] := Rect(X, Y, X + W, Y + Canvas.TextHeight('Xg'));
      Canvas.Font.Color := FLink;
    end
    else
      Canvas.Font.Color := FDim;
    if FStepHot = k then
      Canvas.Font.Style := [fsUnderline]
    else
      Canvas.Font.Style := [];
    Canvas.TextOut(X, Y, Captions[k]);
    Dec(X, Px(Gap) * 2);
  end;
  Canvas.Font.Style := [];
  Result := X;
end;

function TGittanSummary.StepAt(X, Y: integer): integer;
var
  k: integer;
begin
  Result := -1;
  if not Assigned(FOnCommitStep) then
    Exit;
  for k := 0 to 1 do
    if FStepOn[k] and PtInRect(FStepRects[k], Point(X, Y)) then
      Exit(k);
end;

procedure TGittanSummary.SetStepHot(AValue: integer);
begin
  if FStepHot = AValue then
    Exit;
  FStepHot := AValue;
  Invalidate;
end;

procedure TGittanSummary.SetBackHot(AValue: boolean);
begin
  if FBackHot = AValue then
    Exit;
  FBackHot := AValue;
  Invalidate;
end;

function TGittanSummary.LinkAt(X, Y: integer): integer;
var
  i: integer;
begin
  Result := -1;
  for i := 0 to High(FNoteBoxes) do
    if PtInRect(FNoteBoxes[i].LinkRect, Point(X, Y)) then
      Exit(i);
end;

procedure TGittanSummary.SetLinkHot(AValue: integer);
begin
  if FLinkHot = AValue then
    Exit;
  FLinkHot := AValue;
  Invalidate;
end;

procedure TGittanSummary.SetMoreHot(AValue: integer);
begin
  if FMoreHot = AValue then
    Exit;
  FMoreHot := AValue;
  Invalidate;
end;

procedure TGittanSummary.SetSelected(const AValue: string);
begin
  if FSelected = AValue then
    Exit;
  FSelected := AValue;
  Invalidate;
end;

procedure TGittanSummary.SetNotice(const AValue: string);
begin
  if FNotice = AValue then
    Exit;
  FNotice := AValue;
  UpdateHeight;
  Invalidate;
end;

function TGittanSummary.BranchClickable: boolean;
begin
  Result := Assigned(FOnBranchClick) and (FBranch <> '');
end;

procedure TGittanSummary.SetBaseClickable(AValue: boolean);
begin
  if FBaseClickable = AValue then
    Exit;
  FBaseClickable := AValue;
  Invalidate;
end;

procedure TGittanSummary.SetSyncHot(AValue: boolean);
begin
  if FSyncHot = AValue then
    Exit;
  FSyncHot := AValue;
  if AValue then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  Invalidate;
end;

procedure TGittanSummary.SetTotalsHot(AValue: boolean);
begin
  if FTotalsHot = AValue then
    Exit;
  FTotalsHot := AValue;
  if AValue then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  Invalidate;
end;

procedure TGittanSummary.SetBaseHot(AValue: boolean);
begin
  if FBaseHot = AValue then
    Exit;
  FBaseHot := AValue;
  if AValue then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  Invalidate;
end;

procedure TGittanSummary.SetBranchHot(AValue: boolean);
begin
  if FBranchHot = AValue then
    Exit;
  FBranchHot := AValue;
  if AValue then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  Invalidate;
end;

function TGittanSummary.RowAt(Y: integer): integer;
begin
  Result := -1;
  if Y < FRowsTop then
    Exit;
  Result := (Y - FRowsTop) div Px(RowHeight);
  if Result > High(FStats) then
    Result := -1;
end;

function TGittanSummary.CommitAt(Y: integer): integer;
begin
  Result := -1;
  if not ShowsCommits or (Y < FCommitsTop) then
    Exit;
  Result := (Y - FCommitsTop) div Px(RowHeight);
  if Result > High(FCommits) then
    Result := -1;
end;

procedure TGittanSummary.SetCommitHot(AValue: integer);
begin
  if FCommitHot = AValue then
    Exit;
  FCommitHot := AValue;
  Invalidate;
end;

function TGittanSummary.ActionAt(X, Y: integer): integer;
var
  Row: integer;
begin
  Result := -1;
  Row := RowAt(Y);
  if (Row >= 0) and (Row <= High(FActionRects)) and (Row <= High(FRowActions)) and
    (FRowActions[Row] <> '') and PtInRect(FActionRects[Row], Point(X, Y)) then
    Result := Row;
end;

procedure TGittanSummary.SetActionHot(AValue: integer);
begin
  if FActionHot = AValue then
    Exit;
  FActionHot := AValue;
  Invalidate;
end;

procedure TGittanSummary.SetHot(AValue: integer);
begin
  if FHot = AValue then
    Exit;
  FHot := AValue;
  Invalidate;
end;

{ Repository name and branch on one line, the file count and totals on the
  next (the clean state instead, unless it stands in the middle), a
  divider below. Y is advanced past the header. }
procedure TGittanSummary.PaintHeader(var Y: integer);
var
  X, TitleHeight, BodyHeight, TextY, IconW, Added, Deleted, i: integer;
  Heading: string;
begin
  Canvas.Brush.Style := bsClear;
  Canvas.Font := Font;
  BodyHeight := Canvas.TextHeight('Xg');
  Canvas.Font.Size := TitleFontSize;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FText;
  TitleHeight := Canvas.TextHeight('Xg');
  Canvas.TextOut(Px(Pad), Y, FRepoName);
  X := Px(Pad) + Canvas.TextWidth(FRepoName) + Px(Gap);
  Canvas.Font.Size := Font.Size;
  Canvas.Font.Style := [];
  FBranchRect := Rect(0, 0, 0, 0);
  { The branch as the status bar shows it: a branch icon, the name in
    the text color, and a dimmed chevron when a click drops the list.
    The chip is filled while the mouse is over it. }
  if FBranch <> '' then
  begin
    TextY := Y + TitleHeight - BodyHeight - 3;
    IconW := BodyHeight - 4 + Px(IconGap);
    if BranchClickable then
    begin
      FBranchRect := Rect(X - Px(ChipPadX), TextY - Px(ChipPadY),
        X + IconW + Canvas.TextWidth(FBranch) + Px(ChevronWidth) + Px(ChipPadX),
        TextY + BodyHeight + Px(ChipPadY));
      if FBranchHot then
        FillHover(Canvas, FBranchRect, 8, FHover);
    end;
    DrawStatusIcon(Canvas, HintBranch, X, TextY, BodyHeight, FDim);
    Canvas.Pen.Width := 1;
    Canvas.Brush.Style := bsClear;
    Inc(X, IconW);
    Canvas.Font.Color := FText;
    Canvas.TextOut(X, TextY, FBranch);
    Inc(X, Canvas.TextWidth(FBranch));
    if BranchClickable then
    begin
      Inc(X, Px(ChevronWidth) div 2 + 1);
      DrawChevron(Canvas, X, TextY + BodyHeight div 2, FDim);
      Inc(X, Px(ChevronWidth) div 2 + Px(ChipPadX));
    end;
    Inc(X, Px(Gap));
  end;
  FBaseRect := Rect(0, 0, 0, 0);
  FSyncRect := Rect(0, 0, 0, 0);
  if FBase <> '' then
  begin
    TextY := Y + TitleHeight - BodyHeight - 3;
    { A base with actions is a chip like the branch, with a chevron. }
    if FBaseClickable and Assigned(FOnBaseClick) then
    begin
      FBaseRect := Rect(X - Px(ChipPadX), TextY - Px(ChipPadY),
        X + Canvas.TextWidth(FBase) + Px(ChevronWidth) + Px(ChipPadX), TextY + BodyHeight + Px(ChipPadY));
      if FBaseHot then
        FillHover(Canvas, FBaseRect, 8, FHover);
    end;
    Canvas.Font.Color := FText;
    Canvas.TextOut(X, TextY, FBase);
    if FBaseRect.Right > FBaseRect.Left then
    begin
      Inc(X, Canvas.TextWidth(FBase) + Px(ChevronWidth) div 2 + 1);
      DrawChevron(Canvas, X, TextY + BodyHeight div 2, FDim);
    end;
  end;
  Inc(Y, TitleHeight + 6);

  Added := 0;
  Deleted := 0;
  for i := 0 to High(FStats) do
  begin
    Inc(Added, FStats[i].Added);
    Inc(Deleted, FStats[i].Deleted);
  end;
  X := Px(Pad);
  FTotalsRect := Rect(0, 0, 0, 0);
  if (Length(FStats) = 0) and not CentersClean then
    PaintCleanHeader(Y);
  if Length(FStats) > 0 then
  begin
    if Length(FStats) = 1 then
      Heading := rsOneFile
    else
      Heading := Format(rsManyFiles, [Length(FStats)]);
    { The totals are a chip while a click drops what the change is made
      of, filled under the mouse as the branch chip is. }
    if Assigned(FOnTotalsClick) then
    begin
      FTotalsRect := Rect(X - Px(ChipPadX), Y - Px(ChipPadY), X + Canvas.TextWidth(Heading) +
        Px(Gap) + Canvas.TextWidth('+' + IntToStr(Added)) + Px(Gap) div 2 +
        Canvas.TextWidth('−' + IntToStr(Deleted)) + Px(ChevronWidth) + Px(ChipPadX),
        Y + BodyHeight + Px(ChipPadY));
      if FTotalsHot then
        FillHover(Canvas, FTotalsRect, 8, FHover);
      Canvas.Brush.Style := bsClear;
    end;
    Canvas.Font.Color := FDim;
    Canvas.TextOut(X, Y, Heading);
    Inc(X, Canvas.TextWidth(Heading) + Px(Gap));
    Canvas.Font.Color := FAdded;
    Heading := '+' + IntToStr(Added);
    Canvas.TextOut(X, Y, Heading);
    Inc(X, Canvas.TextWidth(Heading) + Px(Gap) div 2);
    Canvas.Font.Color := FDeleted;
    Heading := '−' + IntToStr(Deleted);
    Canvas.TextOut(X, Y, Heading);
    Inc(X, Canvas.TextWidth(Heading));
    if FTotalsRect.Right > FTotalsRect.Left then
    begin
      Inc(X, Px(ChevronWidth) div 2 + 1);
      DrawChevron(Canvas, X, Y + BodyHeight div 2, FDim);
      Inc(X, Px(ChevronWidth) div 2 + Px(ChipPadX));
    end;
    Inc(X, Px(Gap));
    { The whole change as one bar: the added share in green, the
      deleted in red. }
    if Added + Deleted > 0 then
    begin
      Canvas.Pen.Style := psClear;
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := FDeleted;
      Canvas.RoundRect(X, Y + (BodyHeight - Px(BarHeight)) div 2, X + Px(TotalBarWidth),
        Y + (BodyHeight + Px(BarHeight)) div 2, Px(BarHeight), Px(BarHeight));
      if Added > 0 then
      begin
        Canvas.Brush.Color := FAdded;
        Canvas.RoundRect(X, Y + (BodyHeight - Px(BarHeight)) div 2,
          X + Max(Px(BarHeight), Round(Added / (Added + Deleted) * Px(TotalBarWidth))),
          Y + (BodyHeight + Px(BarHeight)) div 2, Px(BarHeight), Px(BarHeight));
      end;
      Canvas.Pen.Style := psSolid;
      Canvas.Brush.Style := bsClear;
      Inc(X, Px(TotalBarWidth) + Px(Gap));
    end;
    PaintKinds(Y, X, Width - Px(Pad));
  end;
  Inc(Y, HeaderBlockHeight(Canvas) + Px(Pad) div 2);
  Canvas.Pen.Color := FLine;
  Canvas.Line(Px(Pad), Y, Width - Px(Pad), Y);
  Inc(Y, Px(Pad) div 2);
end;

{ How many files of each kind, as a dot in the kind's color and a dim
  count, right-aligned at ARight on the line at Y; left out when they
  would not fit between ALeft and ARight. }
procedure TGittanSummary.PaintKinds(Y, ALeft, ARight: integer);
var
  Counts: array[TGittanChangeKind] of integer;
  Kind: TGittanChangeKind;
  i, X, BodyHeight, Total: integer;
  KindText: string;
begin
  for Kind := Low(Kind) to High(Kind) do
    Counts[Kind] := 0;
  for i := 0 to High(FStats) do
    Inc(Counts[FStats[i].Kind]);
  Canvas.Font.Color := FDim;
  BodyHeight := Canvas.TextHeight('Xg');
  Total := 0;
  for Kind := Low(Kind) to High(Kind) do
    if Counts[Kind] > 0 then
      Inc(Total, Px(DotSize) + Px(Gap) div 2 + Canvas.TextWidth(Format(KindCount[Kind],
        [Counts[Kind]])) + Px(Gap));
  Dec(Total, Px(Gap));
  if (Total <= 0) or (ALeft + Total > ARight) then
    Exit;
  X := ARight - Total;
  for Kind := Low(Kind) to High(Kind) do
    if Counts[Kind] > 0 then
    begin
      Canvas.Pen.Style := psClear;
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := KindColor(Kind);
      Canvas.Ellipse(X, Y + (BodyHeight - Px(DotSize)) div 2, X + Px(DotSize),
        Y + (BodyHeight + Px(DotSize)) div 2);
      Canvas.Pen.Style := psSolid;
      Canvas.Brush.Style := bsClear;
      Inc(X, Px(DotSize) + Px(Gap) div 2);
      KindText := Format(KindCount[Kind], [Counts[Kind]]);
      Canvas.TextOut(X, Y, KindText);
      Inc(X, Canvas.TextWidth(KindText) + Px(Gap));
    end;
end;

{ The bars of the rows share the width: a sixth of it, within bounds. }
function TGittanSummary.BarWidth: integer;
begin
  Result := Min(Px(MaxBarWidth), Max(Px(MinBarWidth), Width div 6));
end;

{ An info disc with an "i" and the notice text, in the row above the
  files. Y is advanced past it. }
procedure TGittanSummary.PaintNotice(var Y: integer);
var
  X, CenterY: integer;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  X := Px(Pad);
  CenterY := Y + Px(RowHeight) div 2;
  Canvas.Pen.Color := FDim;
  Canvas.Brush.Style := bsClear;
  Canvas.Ellipse(X, CenterY - Px(CheckSize) div 2, X + Px(CheckSize), CenterY + Px(CheckSize) div 2);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FDim;
  Canvas.TextOut(X + (Px(CheckSize) - Canvas.TextWidth('i')) div 2,
    CenterY - Canvas.TextHeight('i') div 2, 'i');
  Canvas.Font.Style := [];
  Canvas.TextOut(X + Px(CheckSize) + Px(Gap) div 2 + 2,
    CenterY - Canvas.TextHeight('Xg') div 2, FNotice);
  Inc(Y, Px(RowHeight));
end;

{ The bar compares this file's change with the largest one: the added part
  in green, the deleted part in red, the rest of the track in the line
  color. A change too small for a pixel still gets one. }
procedure TGittanSummary.PaintBar(X, Y: integer; const AStat: TGittanFileStat;
  AMax: integer);
var
  AddedWidth, DeletedWidth: integer;
begin
  Canvas.Pen.Style := psClear;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FLine;
  Canvas.RoundRect(X, Y, X + BarWidth, Y + Px(BarHeight), Px(BarHeight), Px(BarHeight));
  if AMax = 0 then
    Exit;
  AddedWidth := Round(AStat.Added / AMax * BarWidth);
  if (AStat.Added > 0) and (AddedWidth < 2) then
    AddedWidth := 2;
  DeletedWidth := Round(AStat.Deleted / AMax * BarWidth);
  if (AStat.Deleted > 0) and (DeletedWidth < 2) then
    DeletedWidth := 2;
  DeletedWidth := Min(DeletedWidth, BarWidth - AddedWidth);
  if AddedWidth > 0 then
  begin
    Canvas.Brush.Color := FAdded;
    Canvas.RoundRect(X, Y, X + AddedWidth, Y + Px(BarHeight), Px(BarHeight), Px(BarHeight));
  end;
  if DeletedWidth > 0 then
  begin
    Canvas.Brush.Color := FDeleted;
    Canvas.RoundRect(X + AddedWidth, Y, X + AddedWidth + DeletedWidth,
      Y + Px(BarHeight), Px(BarHeight), Px(BarHeight));
  end;
  Canvas.Pen.Style := psSolid;
end;

{ Badge, directory in dim and file name in full color, then the counts and
  the bar on the right. A path too long for the room loses its directory
  first, then its end. }
procedure TGittanSummary.PaintRow(AIndex, ATop: integer);
var
  Stat: TGittanFileStat;
  X, CountsX, TextY, BodyHeight, Room, MaxChange, i, W: integer;
  Dir, FileName, Count, RowText, RowAction: string;
  R: TRect;
begin
  Stat := FStats[AIndex];
  RowAction := '';
  if AIndex <= High(FRowActions) then
    RowAction := FRowActions[AIndex];
  if AIndex <= High(FActionRects) then
    FActionRects[AIndex] := Rect(0, 0, 0, 0);
  Canvas.Font := Font;
  BodyHeight := Canvas.TextHeight('Xg');
  TextY := ATop + (Px(RowHeight) - BodyHeight) div 2;
  if (AIndex = FHot) or (Stat.Path = FSelected) then
  begin
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    if AIndex = FHot then
      Canvas.Brush.Color := FHover
    else
      Canvas.Brush.Color := FSelectedBack;
    Canvas.RoundRect(Px(Pad) div 2, ATop, Width - Px(Pad) div 2, ATop + Px(RowHeight), 8, 8);
    Canvas.Pen.Style := psSolid;
  end;
  X := Px(Pad);
  if (FImages <> nil) and (AIndex <= High(FIconIndex)) then
    FImages.DrawForPPI(Canvas, X, ATop + (Px(RowHeight) - Px(IconSize)) div 2,
      FIconIndex[AIndex], IconSize, Screen.PixelsPerInch, GetCanvasScaleFactor);
  Inc(X, Px(IconSize) + Px(Gap) div 2 + 2);

  CountsX := Width - Px(Pad) - BarWidth - Px(Gap) - 2 * Px(CountWidth) - Px(Gap) div 2;
  RowText := '';
  if AIndex <= High(FRowTexts) then
    RowText := FRowTexts[AIndex];
  if RowText <> '' then
    CountsX := Min(CountsX, Width - Px(Pad) - Canvas.TextWidth(RowText));
  Room := CountsX - Px(Gap) - X;
  if RowAction <> '' then
    Dec(Room, Canvas.TextWidth(RowAction) + 2 * Px(ChipPadX) + Px(Gap));
  Dir := ExtractFilePath(Stat.Path);
  FileName := ExtractFileName(Stat.Path);
  Canvas.Brush.Style := bsClear;
  if Canvas.TextWidth(Dir + FileName) > Room then
    Dir := '';
  FileName := FitTextRight(Canvas, FileName, Room);
  if Dir <> '' then
  begin
    Canvas.Font.Color := FDim;
    Canvas.TextOut(X, TextY, Dir);
    Inc(X, Canvas.TextWidth(Dir));
  end;
  Canvas.Font.Color := FText;
  Canvas.TextOut(X, TextY, FileName);
  Inc(X, Canvas.TextWidth(FileName) + Px(Gap));
  { The pill, outlined on the row's fill, its text in the link color
    under the mouse. }
  if (RowAction <> '') and (AIndex <= High(FActionRects)) then
  begin
    W := Canvas.TextWidth(RowAction) + 2 * Px(ChipPadX);
    R := Rect(X, TextY - Px(ChipPadY), X + W, TextY + BodyHeight + Px(ChipPadY));
    FActionRects[AIndex] := R;
    Canvas.Pen.Color := FLine;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := FBack;
    Canvas.RoundRect(R, R.Height, R.Height);
    Canvas.Brush.Style := bsClear;
    if AIndex = FActionHot then
      Canvas.Font.Color := FLink
    else
      Canvas.Font.Color := FText;
    Canvas.TextOut(X + Px(ChipPadX), TextY, RowAction);
    Inc(X, W + Px(Gap));
  end;
  { What the index holds, when the path left room for it. }
  if Stat.Staged then
  begin
    if Stat.Unstaged then
      Count := rsPartlyStaged
    else
      Count := rsStaged;
    if X + Canvas.TextWidth(Count) <= CountsX - Px(Gap) then
    begin
      Canvas.Font.Color := FDim;
      Canvas.TextOut(X, TextY, Count);
    end;
  end;

  if RowText <> '' then
  begin
    Canvas.Font.Color := FDim;
    Canvas.TextOut(Width - Px(Pad) - Canvas.TextWidth(RowText), TextY, RowText);
    Exit;
  end;
  if Stat.Binary then
  begin
    Canvas.Font.Color := FDim;
    Canvas.TextOut(CountsX + 2 * Px(CountWidth) + Px(Gap) div 2 - Canvas.TextWidth(rsBinary),
      TextY, rsBinary);
  end
  else
  begin
    { A zero is shown, so the columns stay aligned, but dimmed. }
    if Stat.Added > 0 then
      Canvas.Font.Color := FAdded
    else
      Canvas.Font.Color := FDim;
    Count := '+' + IntToStr(Stat.Added);
    Canvas.TextOut(CountsX + Px(CountWidth) - Canvas.TextWidth(Count), TextY, Count);
    if Stat.Deleted > 0 then
      Canvas.Font.Color := FDeleted
    else
      Canvas.Font.Color := FDim;
    Count := '−' + IntToStr(Stat.Deleted);
    Canvas.TextOut(CountsX + 2 * Px(CountWidth) + Px(Gap) div 2 - Canvas.TextWidth(Count),
      TextY, Count);
  end;

  MaxChange := 0;
  for i := 0 to High(FStats) do
    if (i > High(FRowTexts)) or (FRowTexts[i] = '') then
      MaxChange := Max(MaxChange, FStats[i].Added + FStats[i].Deleted);
  PaintBar(Width - Px(Pad) - BarWidth, ATop + (Px(RowHeight) - Px(BarHeight)) div 2, Stat,
    MaxChange);
end;

{ A green disc ASize across at X, Y with a check mark cut out of it. }
procedure TGittanSummary.DrawCheck(X, Y, ASize: integer);
var
  CenterY: integer;
begin
  CenterY := Y + ASize div 2;
  Canvas.Pen.Style := psClear;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FAdded;
  Canvas.Ellipse(X, Y, X + ASize, Y + ASize);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := FBack;
  Canvas.Pen.Width := Max(2, ASize div 10);
  Canvas.Polyline([Point(X + ASize * 27 div 100, CenterY),
    Point(X + ASize * 44 div 100, CenterY + ASize * 17 div 100),
    Point(X + ASize * 74 div 100, CenterY - ASize * 17 div 100)]);
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
end;

{ The clean state in the header, in place of the totals: a large check,
  the clean text larger than the body, and how far the branch is from
  its upstream under it, so the state of the tree reads before the
  commits below it. }
procedure TGittanSummary.PaintCleanHeader(Y: integer);
var
  X, BlockHeight, BodyHeight, TextHeight, TextY: integer;
begin
  BlockHeight := HeaderBlockHeight(Canvas);
  Canvas.Font := Font;
  BodyHeight := Canvas.TextHeight('Xg');
  Canvas.Font.Size := CleanFontSize;
  TextHeight := Canvas.TextHeight('Xg');
  DrawCheck(Px(Pad), Y + (BlockHeight - Px(HeaderCheck)) div 2, Px(HeaderCheck));
  X := Px(Pad) + Px(HeaderCheck) + Px(Gap);
  TextY := Y + (BlockHeight - TextHeight - IfThen(HasSyncLine, 2 + BodyHeight, 0)) div 2;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := FText;
  Canvas.TextOut(X, TextY, CleanText);
  Canvas.Font := Font;
  PaintSync(X, TextY + TextHeight + 2);
end;

{ The clean state alone, when there is nothing to list: a check as large
  as the empty view's icon, the clean text and the sync line under it,
  centered in the control, below the header. }
procedure TGittanSummary.PaintCleanCentered;
var
  BlockTop, CenterX, TextHeight: integer;
begin
  BlockTop := Max(FRowsTop + Px(Pad), (Height - CenterBlockHeight(Canvas)) div 2);
  CenterX := Width div 2;
  DrawCheck(CenterX - Px(CenterCheck) div 2, BlockTop, Px(CenterCheck));
  Inc(BlockTop, Px(CenterCheck) + Px(Gap));
  Canvas.Font := Font;
  Canvas.Font.Size := CleanFontSize;
  Canvas.Font.Color := FText;
  Canvas.Brush.Style := bsClear;
  TextHeight := Canvas.TextHeight('Xg');
  Canvas.TextOut(CenterX - Canvas.TextWidth(CleanText) div 2, BlockTop, CleanText);
  Inc(BlockTop, TextHeight + 4);
  Canvas.Font := Font;
  PaintSync(CenterX - PaintSync(0, 0, False) div 2, BlockTop);
end;

{ How far the branch is from its upstream at X: the commits not pushed
  in the color their dots have in the list, the ones not pulled in the
  text color, or that there is nothing to either, the parts apart by
  dots. Nothing without an upstream. Returns the width; ADraw False only
  measures. }
function TGittanSummary.PaintSync(X, Y: integer; ADraw: boolean): integer;
var
  StartX: integer;

  procedure Part(const AText: string; AColor: TColor);
  begin
    if X > StartX then
    begin
      if ADraw then
      begin
        Canvas.Font.Color := FDim;
        Canvas.TextOut(X, Y, ' · ');
      end;
      Inc(X, Canvas.TextWidth(' · '));
    end;
    if ADraw then
    begin
      Canvas.Font.Color := AColor;
      Canvas.TextOut(X, Y, AText);
    end;
    Inc(X, Canvas.TextWidth(AText));
  end;

begin
  StartX := X;
  Canvas.Brush.Style := bsClear;
  { The line is a chip while a click drops the sync list: filled under
    the mouse, as the branch chip is. }
  if ADraw and Assigned(FOnSyncClick) and HasSyncLine and not
    (FHasUpstream and FUpstreamGone) then
  begin
    FSyncRect := Rect(X - Px(ChipPadX), Y - Px(ChipPadY), X + PaintSync(0, 0, False) + Px(ChipPadX),
      Y + Canvas.TextHeight('Xg') + Px(ChipPadY));
    if FSyncHot then
      FillHover(Canvas, FSyncRect, 8, FHover);
  end;
  if FHasUpstream and FUpstreamGone then
    Part(rsUpstreamGone, FDeleted)
  else if FHasUpstream then
  begin
    if FAhead > 0 then
      Part('↑ ' + Format(rsNotPushed, [FAhead]), FLink);
    if (FBehind > 0) and FRewritten then
      Part('↓ ' + Format(rsReplacedHere, [FBehind]), FText)
    else if FBehind > 0 then
      Part('↓ ' + Format(rsNotPulled, [FBehind]), FText);
    if (FAhead = 0) and (FBehind = 0) then
      Part(rsInSync, FDim);
  end
  else if FNotOnRemote > 0 then
    Part('↑ ' + Format(rsNotOnRemote, [FNotOnRemote]), FLink)
  else if FNotOnRemote = 0 then
    Part(rsBranchNotOnRemote, FDim);
  Result := X - StartX;
end;

{ A line under the clean text: the upstream's counts, or, for a branch
  without one in a repository with a remote, that it is not there. }
function TGittanSummary.HasSyncLine: boolean;
begin
  Result := FHasUpstream or (FNotOnRemote >= 0);
end;

{ The heading, then a row per commit, the dots joined by a line down the
  icon column so they read as a history. The short ids line up at the
  right, as wide as the widest. }
procedure TGittanSummary.PaintCommits;
var
  i, HashWidth, BodyHeight, LineX: integer;
begin
  Canvas.Font := Font;
  BodyHeight := Canvas.TextHeight('Xg');
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := FDim;
  Canvas.TextOut(Px(Pad), FCommitsTop - Px(NoteGap) - BodyHeight, rsRecentCommits);
  Canvas.Font.Style := [];
  HashWidth := 0;
  for i := 0 to High(FCommits) do
    HashWidth := Max(HashWidth, Canvas.TextWidth(FCommits[i].Short));
  for i := 0 to High(FCommits) do
    if i = FCommitHot then
      FillHover(Canvas, Rect(Px(Pad) div 2, FCommitsTop + i * Px(RowHeight), Width - Px(Pad) div 2,
        FCommitsTop + (i + 1) * Px(RowHeight)), 8, FHover);
  if Length(FCommits) > 1 then
  begin
    LineX := Px(Pad) + Px(IconSize) div 2;
    Canvas.Pen.Color := FLine;
    Canvas.Pen.Width := 2;
    Canvas.Line(LineX, FCommitsTop + Px(RowHeight) div 2, LineX,
      FCommitsTop + High(FCommits) * Px(RowHeight) + Px(RowHeight) div 2);
    Canvas.Pen.Width := 1;
  end;
  for i := 0 to High(FCommits) do
    PaintCommit(i, FCommitsTop + i * Px(RowHeight), HashWidth);
end;

{ A dot on the line, filled in the link color when the commit is not
  pushed, a ring otherwise; the subject, cut to fit with an ellipsis;
  the author and age dimmed, dropped when the subject would get too
  little room; the short id at the right. }
procedure TGittanSummary.PaintCommit(AIndex, ATop, AHashWidth: integer);
var
  Commit: TGittanCommitLine;
  X, CenterX, CenterY, TextY, Right, Room, n: integer;
  Meta, Subject: string;
begin
  Commit := FCommits[AIndex];
  Canvas.Font := Font;
  TextY := ATop + (Px(RowHeight) - Canvas.TextHeight('Xg')) div 2;
  CenterX := Px(Pad) + Px(IconSize) div 2;
  CenterY := ATop + Px(RowHeight) div 2;
  Canvas.Brush.Style := bsSolid;
  if Commit.Unpushed then
  begin
    Canvas.Pen.Color := FLink;
    Canvas.Brush.Color := FLink;
  end
  else
  begin
    Canvas.Pen.Color := FDim;
    if AIndex = FCommitHot then
      Canvas.Brush.Color := FHover
    else
      Canvas.Brush.Color := FBack;
  end;
  Canvas.Pen.Width := 2;
  Canvas.Ellipse(CenterX - Px(DotSize) div 2 - 1, CenterY - Px(DotSize) div 2 - 1,
    CenterX + Px(DotSize) div 2 + 1, CenterY + Px(DotSize) div 2 + 1);
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;

  Right := Width - Px(Pad);
  Canvas.Font.Color := FDim;
  Canvas.TextOut(Right - Canvas.TextWidth(Commit.Short), TextY, Commit.Short);
  Dec(Right, AHashWidth + Px(Gap) + Px(Gap) div 2);

  X := Px(Pad) + Px(IconSize) + Px(Gap) div 2 + 2;
  Meta := Commit.Author;
  if Commit.Date > 0 then
  begin
    if Meta <> '' then
      Meta := Meta + ' · ';
    Meta := Meta + ReviewAge(Commit.Date, LocalTimeToUniversal(Now));
  end;
  if Right - Canvas.TextWidth(Meta) - Px(Gap) - X < Width div 3 then
    Meta := ReviewAge(Commit.Date, LocalTimeToUniversal(Now));
  if Right - Canvas.TextWidth(Meta) - Px(Gap) - X < Width div 4 then
    Meta := '';
  if Meta <> '' then
  begin
    Canvas.TextOut(Right - Canvas.TextWidth(Meta), TextY, Meta);
    Dec(Right, Canvas.TextWidth(Meta) + Px(Gap) + Px(Gap) div 2);
  end;

  Room := Right - X;
  Subject := Commit.Subject;
  if Canvas.TextWidth(Subject) > Room then
  begin
    n := UTF8Length(Subject);
    while (n > 0) and (Canvas.TextWidth(UTF8Copy(Subject, 1, n) + '…') > Room) do
      Dec(n);
    Subject := TrimRight(UTF8Copy(Subject, 1, n)) + '…';
  end;
  Canvas.Font.Color := FText;
  Canvas.TextOut(X, TextY, Subject);
end;

procedure TGittanSummary.Paint;
var
  Y, i: integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBack;
  Canvas.FillRect(ClientRect);
  Y := Px(Pad);
  PaintHeader(Y);
  if FNotice <> '' then
    PaintNotice(Y);
  if FBehindCount > 0 then
    PaintBehind(Y);
  PaintCard(Y);
  PaintNotes(Y);
  PaintReview(Y);
  if Y <> FRowsTop then
  begin
    FRowsTop := Y;
    PlaceCommits;
    Height := Max(FContentHeight, Constraints.MinHeight);
  end;
  if CentersClean then
    PaintCleanCentered;
  if ShowsCommits then
    PaintCommits;
  for i := 0 to High(FStats) do
    PaintRow(i, FRowsTop + i * Px(RowHeight));
end;

procedure TGittanSummary.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(RowAt(Y));
  SetActionHot(ActionAt(X, Y));
  SetCommitHot(CommitAt(Y));
  SetLinkHot(LinkAt(X, Y));
  FTextLinkHot := TextLinkAt(X, Y) <> '';
  FDetailsHot := NoteDetailsAt(X, Y) <> '';
  SetMoreHot(NoteMoreAt(X, Y));
  SetReviewHot((FReviewRect.Right > FReviewRect.Left) and PtInRect(FReviewRect, Point(X, Y)));
  SetBranchHot(BranchClickable and PtInRect(FBranchRect, Point(X, Y)));
  SetBaseHot((FBaseRect.Right > FBaseRect.Left) and PtInRect(FBaseRect, Point(X, Y)));
  SetSyncHot((FSyncRect.Right > FSyncRect.Left) and PtInRect(FSyncRect, Point(X, Y)));
  SetTotalsHot((FTotalsRect.Right > FTotalsRect.Left) and PtInRect(FTotalsRect, Point(X, Y)));
  SetBackHot(Assigned(FOnBackClick) and PtInRect(FBackRect, Point(X, Y)));
  SetStepHot(StepAt(X, Y));
  if Assigned(FOnBehindAction) then
    SetBehindHot(BehindAt(X, Y));
  if (FLinkHot >= 0) or (FActionHot >= 0) or FBackHot or (FStepHot >= 0) or (FBehindHot >= 0) or FTextLinkHot or
    FDetailsHot or (FMoreHot >= 0) then
    Cursor := crHandPoint
  else if not (FBranchHot or FBaseHot or FSyncHot or FTotalsHot or FReviewHot) then
    Cursor := crDefault;
end;

procedure TGittanSummary.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1);
  SetActionHot(-1);
  SetCommitHot(-1);
  SetLinkHot(-1);
  SetMoreHot(-1);
  FTextLinkHot := False;
  FDetailsHot := False;
  SetReviewHot(False);
  SetBranchHot(False);
  SetBaseHot(False);
  SetSyncHot(False);
  SetTotalsHot(False);
  SetBackHot(False);
  SetStepHot(-1);
  SetBehindHot(-1);
end;

procedure TGittanSummary.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: integer);
var
  Row: integer;
  Key: string;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button = mbLeft) and BranchClickable and PtInRect(FBranchRect, Point(X, Y)) then
  begin
    FOnBranchClick(Self, Rect(ClientToScreen(FBranchRect.TopLeft).X,
      ClientToScreen(FBranchRect.TopLeft).Y, ClientToScreen(FBranchRect.BottomRight).X,
      ClientToScreen(FBranchRect.BottomRight).Y));
    Exit;
  end;
  if (Button = mbLeft) and (FBaseRect.Right > FBaseRect.Left) and Assigned(FOnBaseClick) and
    PtInRect(FBaseRect, Point(X, Y)) then
  begin
    FOnBaseClick(Self, Rect(ClientToScreen(FBaseRect.TopLeft).X,
      ClientToScreen(FBaseRect.TopLeft).Y, ClientToScreen(FBaseRect.BottomRight).X,
      ClientToScreen(FBaseRect.BottomRight).Y));
    Exit;
  end;
  if (Button = mbLeft) and Assigned(FOnBackClick) and PtInRect(FBackRect, Point(X, Y)) then
  begin
    FOnBackClick(Self);
    Exit;
  end;
  if (Button = mbLeft) and (StepAt(X, Y) >= 0) then
  begin
    FOnCommitStep(Self, StepAt(X, Y) = 1);
    Exit;
  end;
  if (Button = mbLeft) and (FSyncRect.Right > FSyncRect.Left) and Assigned(FOnSyncClick) and
    PtInRect(FSyncRect, Point(X, Y)) then
  begin
    FOnSyncClick(Self, Rect(ClientToScreen(FSyncRect.TopLeft).X,
      ClientToScreen(FSyncRect.TopLeft).Y, ClientToScreen(FSyncRect.BottomRight).X,
      ClientToScreen(FSyncRect.BottomRight).Y));
    Exit;
  end;
  if (Button = mbLeft) and (FTotalsRect.Right > FTotalsRect.Left) and Assigned(FOnTotalsClick) and
    PtInRect(FTotalsRect, Point(X, Y)) then
  begin
    FOnTotalsClick(Self, Rect(ClientToScreen(FTotalsRect.TopLeft).X,
      ClientToScreen(FTotalsRect.TopLeft).Y, ClientToScreen(FTotalsRect.BottomRight).X,
      ClientToScreen(FTotalsRect.BottomRight).Y));
    Exit;
  end;
  if (Button = mbLeft) and Assigned(FOnBehindAction) and (BehindAt(X, Y) >= 0) then
  begin
    FOnBehindAction(Self, BehindAt(X, Y) = 0);
    Exit;
  end;
  if (Button = mbLeft) and Assigned(FOnOpenUrl) and (LinkAt(X, Y) >= 0) then
  begin
    FOnOpenUrl(Self, FNotes[LinkAt(X, Y)].Url);
    Exit;
  end;
  if (Button = mbLeft) and Assigned(FOnOpenUrl) and (TextLinkAt(X, Y) <> '') then
  begin
    FOnOpenUrl(Self, TextLinkAt(X, Y));
    Exit;
  end;
  { The summary of a <details> block opens or closes it, Show more and
    Show less the whole text. }
  if (Button = mbLeft) and ((NoteDetailsAt(X, Y) <> '') or (NoteMoreAt(X, Y) >= 0)) then
  begin
    if NoteMoreAt(X, Y) >= 0 then
      Key := NoteDetailsKey(NoteMoreAt(X, Y), -1)
    else
      Key := NoteDetailsAt(X, Y);
    if FNotesOpen.IndexOf(Key) >= 0 then
      FNotesOpen.Delete(FNotesOpen.IndexOf(Key))
    else
      FNotesOpen.Add(Key);
    FNotesWidth := -1;
    UpdateHeight;
    Invalidate;
    Exit;
  end;
  if (Button = mbLeft) and (FReviewRect.Right > FReviewRect.Left) and
    Assigned(FOnReviewClick) and PtInRect(FReviewRect, Point(X, Y)) then
  begin
    FOnReviewClick(Self, Rect(ClientToScreen(FReviewRect.TopLeft).X,
      ClientToScreen(FReviewRect.TopLeft).Y, ClientToScreen(FReviewRect.BottomRight).X,
      ClientToScreen(FReviewRect.BottomRight).Y));
    Exit;
  end;
  Row := CommitAt(Y);
  if (Row >= 0) and (Button = mbLeft) and Assigned(FOnSelectCommit) then
  begin
    FOnSelectCommit(Self, FCommits[Row].Hash);
    Exit;
  end;
  Row := ActionAt(X, Y);
  if (Row >= 0) and (Button = mbLeft) and Assigned(FOnRowAction) then
  begin
    FOnRowAction(Self, FStats[Row].Path);
    Exit;
  end;
  Row := RowAt(Y);
  if Row < 0 then
    Exit;
  if (Button = mbLeft) and Assigned(FOnSelectFile) then
    FOnSelectFile(Self, FStats[Row].Path)
  else if (Button = mbRight) and Assigned(FOnContextFile) then
    FOnContextFile(Self, FStats[Row].Path, ClientToScreen(Point(X, Y)));
end;

end.
