unit gittan.batchpage;

{** The Batch tab of the forge view (uforge): operations run in several
  repositories at once, on the repositories the user picks.

  The page lists the repositories the welcome view shows (SetRows, from
  BatchRows in gittan.batch): the repository list's folders and
  repositories, every folder open, then the recent ones the list does
  not have, each with a check box. A folder's box picks or drops all the
  repositories in it, and shows a dash when only some are picked; All
  and None at the heading pick every one or none. What is picked is
  Chosen, by root, which the owner keeps in the settings
  (OnChosenChange); a picked root no row has stays picked, unseen.

  The list folds to one line naming the picked ones: its heading, with
  a chevron before it as a folder of the welcome view's list has, folds
  and unfolds it, and so does a click on that line; it starts unfolded
  while nothing is picked. Under it the operations, as a row
  of pills, one shown at a time (Operation, OnOperationChange, which the
  owner keeps), each keeping what it found while another is shown.
  First the overview, which reads and changes
  nothing: Check (OnCheck, which the owner also runs as the tab is
  shown) has the owner run TGittanStatusJob over the picked
  repositories and give what it read as it comes (StartCheck,
  SetStatus): a card per repository with something left undone, its
  name, branch and path in a head that opens it (OnOpen), then a line
  each for what git is in the middle of, a detached HEAD, the changed
  and untracked files, the stashes, the branches not pushed and those on
  no remote with their counts, no remote at all, or why it could not be
  read; the clean ones are named on one line under the cards.

  Then Identity, which reads and changes nothing either: Check has the
  owner run TGittanIdentityJob (StartIdentity, SetIdentities), and the
  repositories are shown by who they commit as, a card per name, e-mail
  and signing alike (SameIdentity), most used first: its head names
  them, a line says how commits are signed, and a row per repository
  with its remote's owner opens it; a row is tagged when the e-mail is
  set in the repository itself, and in the warning color when the other
  repositories of its owner commit under another e-mail
  (MarkOddIdentities). A card for a repository that could not be read.

  Then Maintenance: Scan (OnMaintScan) has the owner run
  TGittanMaintScanJob over the picked repositories (StartMaintScan,
  SetMaintScan): a card per repository that needs something, a row per
  task with a check box, all picked as they come: the remote's default
  branch to follow here (only the local refs/remotes/<remote>/HEAD
  changes), the worktrees whose folder is gone
  to forget, the objects to pack, with what was found dim after it; the
  remote that could not be asked in the warning color. Run
  (OnMaintRun) has the owner run TGittanMaintRunJob over the tasks
  picked (PickedMaintRefs, SetMaintRunning, ApplyMaintRun): a task done
  is tagged done (packing with the size after), one that failed with
  git's reason.

  Then Gone branches, the branches deleted on the remote. Scan (OnScan) has the owner run TGittanGoneScanJob over the
  picked repositories (ChosenRepos) and give what it found as it comes
  (StartScan, SetScan): a card per repository with something to say,
  with its gone branches, each with a check box and a tag that says
  whether it is merged, squash-merged or not merged into the default
  branch (the merged ones picked at first, the others not), the fetch's
  failure in the warning color and a repository that could not be read
  in the error color; the repositories with nothing gone are named on
  one line under the cards. Delete (OnDelete) has the owner ask and run
  TGittanGoneDeleteJob over the branches picked (PickedRefs), and give
  what went (SetDeleting, ApplyDeleted): a branch deleted shows the
  commit it was at, one git refused git's reason.

  After them the operations the extensions added (Gittan.batch.register,
  SetExtOps), a pill each: what the extension says it does in a dim line,
  Run (OnExtRun), which has the owner call the extension once for each
  picked repository in turn (StartExtRun, SetExtResult, FinishExtRun):
  a card for each repository it had something to say of, its name and
  path in a head that opens it, the text in the severity it gave and a
  link when it gave one; the ones it said nothing of on one line, the
  ones it does not run for (its @repos and @forges) on another.

  It paints itself in the forge view's palette (ForgePalette) and sizes
  its height to its content so it can sit in the view's TScrollBox as
  the forge page does: Layout paints the content on a measuring canvas
  to know the height before the control is shown. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, gittan.batch, gittan.ext.views,
  gittan.cardpage;

const
  {** The operations, as Operation counts them. }
  BatchOverview = 0;
  BatchGone = 1;
  BatchIdentity = 2;
  BatchMaintenance = 3;
  BatchOperationCount = 4;
  {** The keys of Gittan's own operations, as OperationKey gives them. }
  BatchOperationKeys: array[0..BatchOperationCount - 1] of string =
    ('overview', 'gone', 'identity', 'maintenance');

type
  {** A repository to open, by its root. }
  TGittanBatchOpenEvent = procedure(Sender: TObject; const APath: string) of object;

  {** An operation an extension added: its command's key in the
    registry, the extension, its title and what it is for. }
  TGittanBatchExtOp = record
    Key, ExtId, Title, Note: string;
    {** Which extension it is from, as a line says it. }
    Source: string;
  end;
  TGittanBatchExtOps = array of TGittanBatchExtOp;

  {** A run of an extension's operation: the repositories, what it said
    of the first Done, those it does not run for, an error that ended
    it. }
  TGittanBatchExtRun = record
    Key, Error: string;
    Paths, Captions: TStringArray;
    Results: array of TExtBatchResult;
    Skipped: array of boolean;
    Done, Total: integer;
    Running: boolean;
  end;

  { TGittanBatchPage }

  TGittanBatchPage = class(TGittanCardPage)
  private
    FRows: TGittanBatchRows;
    { Per row: a repository whose folder is gone. }
    FMissing: array of boolean;
    FChosen: TStringList;
    { What the scan found, the first FGoneDone of FGoneTotal repositories;
      FSeen of them had their merged branches picked. }
    FGone: TGittanGoneRepos;
    FGoneDone, FGoneTotal, FSeen: integer;
    FScanning, FScanned, FDeleting: boolean;
    { What the overview read, the first FStatusDone of FStatusTotal. }
    FStatus: TGittanRepoStatuses;
    FStatusDone, FStatusTotal: integer;
    FChecking: boolean;
    { What the identity check read, the first FIdsDone of FIdsTotal,
      MarkOddIdentities applied. }
    FIds: TGittanRepoIdentities;
    FIdsDone, FIdsTotal: integer;
    FReadingIds: boolean;
    { What the maintenance scan found, the first FMaintDone of
      FMaintTotal, FMaintSeen of them had their tasks picked; the tasks
      picked, as MaintKey. }
    FMaint: TGittanMaintRepos;
    FMaintDone, FMaintTotal, FMaintSeen: integer;
    FMaintScanning, FMaintScanned, FMaintRunning: boolean;
    FMaintPicked: TStringList;
    FOnMaintScan, FOnMaintRun: TNotifyEvent;
    { Whether the list is unfolded, and the operation shown. }
    FReposOpen: boolean;
    FOperation: integer;
    { The extension's operation OperationKey asked for before it came. }
    FWantedKey: string;
    FOnOperationChange: TNotifyEvent;
    FOnCheck: TNotifyEvent;
    FOnOpen: TGittanBatchOpenEvent;
    { The branches picked to delete, as PickKey. }
    FPicked: TStringList;
    FOnChosenChange, FOnScan, FOnDelete: TNotifyEvent;
    { The extensions' operations, and their runs, one per key, kept while
      another is shown. }
    FExtOps: TGittanBatchExtOps;
    FExtRuns: array of TGittanBatchExtRun;
    FOnExtRun: TNotifyEvent;
    FOnOpenUrl: TGittanBatchOpenEvent;
    { A note over the list (Notice), with a link that raises OnNotice. }
    FNotice, FNoticeLink: string;
    FOnNotice: TNotifyEvent;
    procedure PaintNotice(var Y: integer; ALeft, ARight: integer);
    function ExtRunIndex(const AKey: string): integer;
    procedure PaintExtCard(var Y: integer; ARun, AIndex, ALeft, ARight: integer);
    procedure PaintExtOp(var Y: integer; ALeft, ARight: integer);
    function IsChosen(const APath: string): boolean;
    procedure SetChosenPath(const APath: string; AOn: boolean);
    function RowState(AIndex: integer): integer;
    function RepoCount: integer;
    function ChosenCount: integer;
    function GoneState(AIndex: integer): integer;
    function Pickable(AIndex: integer): integer;
    function GoneCount(out ARepos: integer): integer;
    procedure ToggleRow(AIndex: integer);
    procedure ToggleGone(AIndex: integer);
    procedure ToggleBranch(AIndex, ABranch: integer);
    procedure ChosenChanged;
    procedure PaintBox(ALeft, ATop, ASize, AState: integer; AEnabled: boolean);
    function PaintTag(ARight, ATop: integer; const AText: string; AColor: TColor): integer;
    procedure PaintHeading(var Y: integer; const ATitle, ADetail: string; ALeft, ARight: integer;
      AChips: boolean);
    procedure PaintRows(var Y: integer; ALeft, ARight: integer);
    procedure PaintPicked(var Y: integer; ALeft, ARight: integer);
    procedure PaintChevron(ALeft, ATop, ASize: integer; AOpen: boolean; AColor: TColor);
    procedure PaintOperations(var Y: integer; ALeft, ARight: integer);
    procedure SetOperation(AValue: integer);
    function GetOperationKey: string;
    procedure SetOperationKey(const AKey: string);
    procedure PaintGoneCard(var Y: integer; AIndex, ALeft, ARight: integer);
    procedure PaintGone(var Y: integer; ALeft, ARight: integer);
    procedure PaintStatusCard(var Y: integer; AIndex, ALeft, ARight: integer);
    procedure PaintStatus(var Y: integer; ALeft, ARight: integer);
    procedure PaintCheckPill(var Y: integer; ALeft: integer; ARunning: boolean;
      ADone, ATotal: integer; const ADetail: string);
    procedure PaintIdentityCard(var Y: integer; const AMembers: array of integer;
      ALeft, ARight: integer);
    procedure PaintIdentity(var Y: integer; ALeft, ARight: integer);
    function MaintCount(out ARepos: integer): integer;
    procedure ToggleMaint(ARepo, AItem: integer);
    procedure PaintMaintCard(var Y: integer; AIndex, ALeft, ARight: integer);
    procedure PaintMaint(var Y: integer; ALeft, ARight: integer);
  protected
    procedure PaintContent; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    {** The repositories to offer, as BatchRows gives them. }
    procedure SetRows(const ARows: TGittanBatchRows);
    {** Picks the repositories at APaths (roots), and no other. }
    procedure SetChosen(APaths: TStrings);
    {** The picked repositories the rows have, in the rows' order, with
      their captions. }
    procedure ChosenRepos(out APaths, ACaptions: TStringArray);
    {** A scan of ATotal repositories starts: what the last one found
      goes. }
    procedure StartScan(ATotal: integer);
    {** What the scan found: the first ADone of ARepos (the others may
      still be written), and whether it still runs. }
    procedure SetScan(const ARepos: TGittanGoneRepos; ADone: integer; ARunning: boolean);
    {** Whether the branches picked are being deleted. }
    procedure SetDeleting(ARunning: boolean);
    {** What the deletion did to the first ADone of ARefs, in AResults. }
    procedure ApplyDeleted(const ARefs: TGittanBranchRefs; const AResults: TGittanGoneBranches;
      ADone: integer);
    {** The branches picked to delete, those deleted already left out. }
    function PickedRefs: TGittanBranchRefs;
    {** How many of PickedRefs are not merged. }
    function PickedNotMerged: integer;
    {** Whether a scan, a deletion or maintenance runs. }
    function Busy: boolean;
    {** An overview of ATotal repositories starts: what the last one read
      goes. }
    procedure StartCheck(ATotal: integer);
    {** What the overview read: the first ADone of ARepos (the others may
      still be written), and whether it still runs. }
    procedure SetStatus(const ARepos: TGittanRepoStatuses; ADone: integer; ARunning: boolean);
    {** Whether the overview runs. }
    property Checking: boolean read FChecking;
    {** An identity check of ATotal repositories starts: what the last
      one read goes. }
    procedure StartIdentity(ATotal: integer);
    {** What the identity check read: the first ADone of ARepos, and
      whether it still runs. }
    procedure SetIdentities(const ARepos: TGittanRepoIdentities; ADone: integer;
      ARunning: boolean);
    {** Whether the identity check runs. }
    property ReadingIdentities: boolean read FReadingIds;
    {** A maintenance scan of ATotal repositories starts: what the last
      one found goes. }
    procedure StartMaintScan(ATotal: integer);
    {** What the maintenance scan found: the first ADone of ARepos, and
      whether it still runs. }
    procedure SetMaintScan(const ARepos: TGittanMaintRepos; ADone: integer; ARunning: boolean);
    {** Whether the tasks picked are being run. }
    procedure SetMaintRunning(ARunning: boolean);
    {** What the run did to the first ADone of ARefs. }
    procedure ApplyMaintRun(const ARefs: TGittanMaintRefs; ADone: integer);
    {** The tasks picked to run, those done already left out. }
    function PickedMaintRefs: TGittanMaintRefs;
    {** A click on Maintenance's Scan: the owner runs the scan. }
    property OnMaintScan: TNotifyEvent read FOnMaintScan write FOnMaintScan;
    {** A click on Run: the owner runs PickedMaintRefs. }
    property OnMaintRun: TNotifyEvent read FOnMaintRun write FOnMaintRun;
    {** The extensions' operations, after the four of Gittan's own; a
      run of one still there is kept. }
    procedure SetExtOps(const AOps: TGittanBatchExtOps);
    {** The extension's operation shown; False while one of Gittan's own
      is. }
    function ShownExtOp(out AOp: TGittanBatchExtOp): boolean;
    {** A run of the operation AKey over APaths starts. }
    procedure StartExtRun(const AKey: string; const APaths, ACaptions: TStringArray);
    {** What the operation AKey said of the repository AIndex, or that it
      does not run for it (ASkipped). }
    procedure SetExtResult(const AKey: string; AIndex: integer; const AResult: TExtBatchResult;
      ASkipped: boolean);
    {** The run of AKey ended, with AError when it was cut short. }
    procedure FinishExtRun(const AKey, AError: string);
    {** Whether the operation AKey runs. }
    function ExtRunning(const AKey: string): boolean;
    {** A click on an extension's Run: the owner runs the operation shown
      (ShownExtOp) over ChosenRepos. }
    property OnExtRun: TNotifyEvent read FOnExtRun write FOnExtRun;
    {** A link an extension gave with a result. }
    property OnOpenUrl: TGittanBatchOpenEvent read FOnOpenUrl write FOnOpenUrl;
    {** The operation shown, BatchOverview (the default), BatchGone or
      BatchIdentity, BatchMaintenance, or an extension's after
      BatchOperationCount. }
    property Operation: integer read FOperation write SetOperation;
    {** The operation shown by its key: one of BatchOperationKeys or an
      extension's (TGittanBatchExtOp.Key). An extension's not there yet
      is waited for: SetExtOps shows it once it comes, unless another
      was picked meanwhile. }
    property OperationKey: string read GetOperationKey write SetOperationKey;
    {** A click on an operation's pill changed Operation. }
    property OnOperationChange: TNotifyEvent read FOnOperationChange write FOnOperationChange;
    {** The roots picked. }
    property Chosen: TStringList read FChosen;
    {** A check box, All or None changed Chosen. }
    property OnChosenChange: TNotifyEvent read FOnChosenChange write FOnChosenChange;
    {** A click on Scan: the owner runs the scan. }
    property OnScan: TNotifyEvent read FOnScan write FOnScan;
    {** A click on Delete: the owner asks and deletes PickedRefs. }
    property OnDelete: TNotifyEvent read FOnDelete write FOnDelete;
    {** A click on Check, in the overview or the identity check: the
      owner reads the picked repositories for the operation shown. }
    property OnCheck: TNotifyEvent read FOnCheck write FOnCheck;
    {** A click on a card's head in the overview, or a repository's row
      in the identity check: open that repository. }
    property OnOpen: TGittanBatchOpenEvent read FOnOpen write FOnOpen;
    {** A note in a card under the head, ALink a link after it that
      raises OnNotice; '' for none. }
    procedure SetNotice(const AText, ALink: string);
    property OnNotice: TNotifyEvent read FOnNotice write FOnNotice;
  end;

implementation

uses
  Math, LCLIntf, LCLType, gittan.forgepage, gittan.textfit, gittan.theme, gittan.repoinfo,
  gittan.puzzle;

resourcestring
  rsTitle = 'Batch';
  rsSubtitle = 'Operations on several repositories at once';
  rsReposHeading = 'Repositories';
  rsPickedOf = '%d of %d picked';
  rsAllChip = 'All';
  rsNoneChip = 'None';
  rsNoRepos = 'No repositories to pick yet. Open some, or add them to the repository list on ' +
    'the welcome page.';
  rsNotFound = 'not found';
  rsNonePicked = 'None picked.';
  { After the names that fit: how many more. }
  rsMorePicked = ' and %d more';
  rsOpGone = 'Gone branches';
  rsGoneAbout = 'Finds local branches that were deleted on the remote. The branch you are on ' +
    'is never touched.';
  rsScanOne = 'Scan 1 repository';
  rsScanMany = 'Scan %d repositories';
  rsScanNone = 'Pick repositories to scan';
  rsScanning = 'Scanning %d of %d…';
  rsGoneOneRepo = '%d in 1 repository';
  rsGoneManyRepos = '%d in %d repositories';
  rsMerged = 'merged';
  rsSquashed = 'squash-merged';
  rsNotMerged = 'not merged';
  rsDeletedWas = 'deleted, was %s';
  rsFetchFailed = 'The fetch failed, so this is as of the last one: %s';
  rsNothingGone = 'Nothing gone in %s.';
  rsAllClean = 'No branch is gone in the repositories scanned.';
  rsDeleteOne = 'Delete 1 branch';
  rsDeleteMany = 'Delete %d branches';
  rsDeleteNone = 'Pick branches to delete';
  rsDeleting = 'Deleting…';
  rsStatusHeading = 'Overview';
  rsStatusAbout = 'What is left undone in each repository: changes, stashes and commits that ' +
    'are not pushed. Nothing is fetched or changed.';
  rsCheckOne = 'Check 1 repository';
  rsCheckMany = 'Check %d repositories';
  rsCheckNone = 'Pick repositories to check';
  rsChecking = 'Checking %d of %d…';
  rsNeedOne = '1 of %d has something left';
  rsNeedMany = '%d of %d have something left';
  rsOnBranch = 'on %s';
  rsOpen = 'Open';
  rsInMiddle = 'In the middle of %s';
  rsDetached = 'HEAD is detached, on no branch';
  rsChangedOne = '1 changed file';
  rsChangedMany = '%d changed files';
  rsUntrackedOne = '1 untracked file';
  rsUntrackedMany = '%d untracked files';
  rsStashOne = '1 stash';
  rsStashMany = '%d stashes';
  rsNotPushed = 'Not pushed: %s';
  rsOnNoRemote = 'On no remote: %s';
  rsNoRemote = 'No remote: nothing here is pushed anywhere';
  { A branch and its count of commits: "feature/x (3)". }
  rsBranchCount = '%s (%d)';
  rsAllDone = 'Nothing is left undone in the repositories checked.';
  rsCleanIn = 'Nothing left undone in %s.';
  rsOpIdentity = 'Identity';
  rsIdentityAbout = 'Who each repository commits as, and whether it signs. A repository is ' +
    'marked when the others of the same owner commit under another e-mail.';
  rsIdOne = 'One identity';
  rsIdOneInAll = 'One identity in all %d';
  rsIdMany = '%d identities in %d repositories';
  rsIdMarked = ', %d marked';
  rsNoIdentity = 'No name or e-mail set';
  rsNoEmail = '%s, no e-mail set';
  rsNoName = '<%s>, no name set';
  rsSigns = 'Signs commits with the %s key %s';
  rsSignsDefault = 'Signs commits with the default %s key';
  rsNoSign = 'Does not sign commits';
  rsSetHere = 'set here';
  rsOdd = 'unlike the rest of %s';
  rsNoOwner = 'no remote on a host';
  rsOpMaint = 'Maintenance';
  rsMaintAbout = 'Tidies up after things that changed: a default branch renamed on the ' +
    'remote, worktrees whose folder you deleted, and repositories worth compressing. Scan ' +
    'checks each remote; nothing changes until you press Run.';
  rsSetHead = 'Update default branch: %s → %s';
  rsSetHeadNew = 'Set default branch: %s';
  rsHeadRenamed = 'renamed on %s';
  rsHeadFrom = 'as on %s';
  rsPruneOne = 'Clean up 1 deleted worktree';
  rsPruneMany = 'Clean up %d deleted worktrees';
  rsPack = 'Compress the repository';
  rsPackDetail = '%s loose objects, %s';
  rsMaintDone = 'done';
  rsPackedTo = 'done, now %s';
  rsRemoteFailed = 'Could not ask the remote: %s';
  rsTaskOne = '1 task in 1 repository';
  rsTasksOneRepo = '%d tasks in 1 repository';
  rsTasksManyRepos = '%d tasks in %d repositories';
  rsNothingToDo = 'Nothing to do in %s.';
  rsAllTidy = 'Nothing to do in the repositories scanned.';
  rsRunOne = 'Run 1 task';
  rsRunMany = 'Run %d tasks';
  rsRunNone = 'Pick tasks to run';
  rsRunning = 'Running…';
  rsExtRunOne = 'Run on 1 repository';
  rsExtRunMany = 'Run on %d repositories';
  rsExtRunNone = 'Pick repositories to run on';
  rsExtRunning = 'Running on %d of %d…';
  rsExtOtherRunning = 'Another operation of an extension is running; this one can run once it is done.';
  rsExtSaidOne = 'Something to say of 1 of %d';
  rsExtSaidMany = 'Something to say of %d of %d';
  rsExtSaidNoneOne = 'Nothing to say of the repository';
  rsExtSaidNone = 'Nothing to say of the %d repositories';
  rsExtNothingIn = 'Nothing to say of %s.';
  rsExtLeftOut = 'Left out, as the extension does not run for them: %s.';
  rsExtOpenLink = 'Open link';

const
  RowLink = 'r:';
  GoneLink = 'g:';
  BranchLink = 'b:';
  AllLink = 'all';
  NoneLink = 'none';
  ScanLink = 'scan';
  DeleteLink = 'delete';
  CheckLink = 'check';
  FoldLink = 'fold';
  UnfoldLink = 'unfold';
  OperationLink = 'op:';
  OpenLink = 'o:';
  IdOpenLink = 'io:';
  MaintScanLink = 'mscan';
  MaintRunLink = 'mrun';
  MaintLink = 'mt:';
  ExtRunLink = 'xrun';
  ExtOpenLink = 'xo:';
  ExtUrlLink = 'xu:';
  NoticeLink = 'notice';
  Pad = 24;
  Gap = 12;
  TitleFontSize = 20;
  MaxContentWidth = 960;
  RowPadY = 5;
  Indent = 20;
  BoxGap = 8;
  CardPadX = 14;
  CardPadY = 10;
  CardRadius = 12;
  CardGap = 8;
  TagPadX = 6;
  TagPadY = 2;
  TagRadius = 6;

{ A task's key among the picked ones: its repository and the task. }
function MaintKey(const APath: string; ATask: TGittanMaintTask): string;
begin
  Result := APath + #0 + IntToStr(Ord(ATask));
end;

{ A branch's key among the picked ones: its repository and its name. }
function PickKey(const APath, ABranch: string): string;
begin
  Result := APath + #0 + ABranch;
end;

{ The first line of AText. }
function FirstLine(const AText: string): string;
var
  p: integer;
begin
  Result := Trim(AText);
  p := Pos(#10, Result);
  if p > 0 then
    Result := Trim(Copy(Result, 1, p - 1));
end;

constructor TGittanBatchPage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FChosen := TStringList.Create;
  FChosen.CaseSensitive := True;
  FPicked := TStringList.Create;
  FPicked.CaseSensitive := True;
  FPicked.Sorted := True;
  FPicked.Duplicates := dupIgnore;
  FMaintPicked := TStringList.Create;
  FMaintPicked.CaseSensitive := True;
  FMaintPicked.Sorted := True;
  FMaintPicked.Duplicates := dupIgnore;
end;

destructor TGittanBatchPage.Destroy;
begin
  FMaintPicked.Free;
  FPicked.Free;
  FChosen.Free;
  inherited Destroy;
end;

{ ---------------------------------------------------------------------------
  The repositories
  --------------------------------------------------------------------------- }

procedure TGittanBatchPage.SetRows(const ARows: TGittanBatchRows);
var
  i: integer;
begin
  FRows := Copy(ARows);
  FMissing := nil;
  SetLength(FMissing, Length(FRows));
  for i := 0 to High(FRows) do
    FMissing[i] := not FRows[i].IsFolder and not DirectoryExists(FRows[i].Path);
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanBatchPage.SetChosen(APaths: TStrings);
begin
  FChosen.Assign(APaths);
  FReposOpen := FChosen.Count = 0;
  Layout;
  Invalidate;
end;

function TGittanBatchPage.IsChosen(const APath: string): boolean;
begin
  Result := (APath <> '') and (FChosen.IndexOf(APath) >= 0);
end;

procedure TGittanBatchPage.SetChosenPath(const APath: string; AOn: boolean);
var
  i: integer;
begin
  if APath = '' then
    Exit;
  i := FChosen.IndexOf(APath);
  if AOn and (i < 0) then
    FChosen.Add(APath)
  else if not AOn and (i >= 0) then
    FChosen.Delete(i);
end;

{ A row's box: 0 empty, 1 checked, 2 a dash (a folder with only some of
  its repositories picked); a folder with none in it is empty. }
function TGittanBatchPage.RowState(AIndex: integer): integer;
var
  Paths: TStringArray;
  Path: string;
  Picked: integer;
begin
  if not FRows[AIndex].IsFolder then
    Exit(Ord(IsChosen(FRows[AIndex].Path)));
  Paths := BatchRowRepos(FRows, AIndex);
  Picked := 0;
  for Path in Paths do
    if IsChosen(Path) then
      Inc(Picked);
  if Picked = 0 then
    Result := 0
  else if Picked = Length(Paths) then
    Result := 1
  else
    Result := 2;
end;

function TGittanBatchPage.RepoCount: integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to High(FRows) do
    if not FRows[i].IsFolder then
      Inc(Result);
end;

function TGittanBatchPage.ChosenCount: integer;
var
  Paths, Captions: TStringArray;
begin
  ChosenRepos(Paths, Captions);
  Result := Length(Paths);
end;

procedure TGittanBatchPage.ChosenRepos(out APaths, ACaptions: TStringArray);
var
  i, n: integer;
  Seen: TStringList;
begin
  APaths := nil;
  ACaptions := nil;
  SetLength(APaths, Length(FRows));
  SetLength(ACaptions, Length(FRows));
  Seen := TStringList.Create;
  try
    Seen.CaseSensitive := True;
    Seen.Sorted := True;
    n := 0;
    for i := 0 to High(FRows) do
      if not FRows[i].IsFolder and IsChosen(FRows[i].Path) and
        (Seen.IndexOf(FRows[i].Path) < 0) then
      begin
        Seen.Add(FRows[i].Path);
        APaths[n] := FRows[i].Path;
        ACaptions[n] := FRows[i].Caption;
        Inc(n);
      end;
  finally
    Seen.Free;
  end;
  SetLength(APaths, n);
  SetLength(ACaptions, n);
end;

procedure TGittanBatchPage.ToggleRow(AIndex: integer);
var
  Paths: TStringArray;
  Path: string;
  TurnOn: boolean;
begin
  if (AIndex < 0) or (AIndex > High(FRows)) then
    Exit;
  TurnOn := RowState(AIndex) <> 1;
  Paths := BatchRowRepos(FRows, AIndex);
  for Path in Paths do
    SetChosenPath(Path, TurnOn);
  ChosenChanged;
end;

procedure TGittanBatchPage.ChosenChanged;
begin
  Layout;
  Invalidate;
  if Assigned(FOnChosenChange) then
    FOnChosenChange(Self);
end;

{ ---------------------------------------------------------------------------
  The gone branches
  --------------------------------------------------------------------------- }

procedure TGittanBatchPage.StartScan(ATotal: integer);
begin
  FGone := nil;
  FGoneDone := 0;
  FGoneTotal := ATotal;
  FSeen := 0;
  FPicked.Clear;
  FScanning := True;
  FScanned := True;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanBatchPage.SetScan(const ARepos: TGittanGoneRepos; ADone: integer;
  ARunning: boolean);
var
  i, j: integer;
begin
  ADone := Min(ADone, Length(ARepos));
  { Only what is done: the thread may still write the rest. }
  FGone := Copy(ARepos, 0, ADone);
  FGoneDone := ADone;
  FScanning := ARunning;
  { The merged branches of what came are picked; what the user picked
    or dropped since stays. }
  for i := FSeen to FGoneDone - 1 do
    for j := 0 to High(FGone[i].Branches) do
      if FGone[i].Branches[j].Merge <> gmNotMerged then
        FPicked.Add(PickKey(FGone[i].Path, FGone[i].Branches[j].Name));
  FSeen := Max(FSeen, FGoneDone);
  Layout;
  Invalidate;
end;

procedure TGittanBatchPage.SetDeleting(ARunning: boolean);
begin
  FDeleting := ARunning;
  Layout;
  Invalidate;
end;

procedure TGittanBatchPage.ApplyDeleted(const ARefs: TGittanBranchRefs;
  const AResults: TGittanGoneBranches; ADone: integer);
var
  i, r, b, k: integer;
begin
  for i := 0 to Min(ADone, Min(Length(ARefs), Length(AResults))) - 1 do
    for r := 0 to High(FGone) do
      if FGone[r].Path = ARefs[i].Path then
        for b := 0 to High(FGone[r].Branches) do
          if FGone[r].Branches[b].Name = ARefs[i].Branch then
          begin
            FGone[r].Branches[b].Deleted := AResults[i].Deleted;
            FGone[r].Branches[b].Was := AResults[i].Was;
            FGone[r].Branches[b].Error := AResults[i].Error;
            k := FPicked.IndexOf(PickKey(ARefs[i].Path, ARefs[i].Branch));
            if AResults[i].Deleted and (k >= 0) then
              FPicked.Delete(k);
          end;
  Layout;
  Invalidate;
end;

function TGittanBatchPage.PickedRefs: TGittanBranchRefs;
var
  r, b, n: integer;
begin
  Result := nil;
  n := 0;
  for r := 0 to High(FGone) do
    for b := 0 to High(FGone[r].Branches) do
      if not FGone[r].Branches[b].Deleted and
        (FPicked.IndexOf(PickKey(FGone[r].Path, FGone[r].Branches[b].Name)) >= 0) then
      begin
        SetLength(Result, n + 1);
        Result[n].Path := FGone[r].Path;
        Result[n].Branch := FGone[r].Branches[b].Name;
        Inc(n);
      end;
end;

function TGittanBatchPage.PickedNotMerged: integer;
var
  r, b: integer;
begin
  Result := 0;
  for r := 0 to High(FGone) do
    for b := 0 to High(FGone[r].Branches) do
      if not FGone[r].Branches[b].Deleted and (FGone[r].Branches[b].Merge = gmNotMerged) and
        (FPicked.IndexOf(PickKey(FGone[r].Path, FGone[r].Branches[b].Name)) >= 0) then
        Inc(Result);
end;

function TGittanBatchPage.Busy: boolean;
begin
  Result := FScanning or FDeleting or FMaintScanning or FMaintRunning;
end;

{ The branches of a card that can still be picked: those not deleted. }
function TGittanBatchPage.Pickable(AIndex: integer): integer;
var
  b: integer;
begin
  Result := 0;
  for b := 0 to High(FGone[AIndex].Branches) do
    if not FGone[AIndex].Branches[b].Deleted then
      Inc(Result);
end;

{ A card's box as RowState's: of its branches not deleted. }
function TGittanBatchPage.GoneState(AIndex: integer): integer;
var
  b, Picked, Total: integer;
begin
  Picked := 0;
  Total := 0;
  for b := 0 to High(FGone[AIndex].Branches) do
    if not FGone[AIndex].Branches[b].Deleted then
    begin
      Inc(Total);
      if FPicked.IndexOf(PickKey(FGone[AIndex].Path, FGone[AIndex].Branches[b].Name)) >= 0 then
        Inc(Picked);
    end;
  if Picked = 0 then
    Result := 0
  else if Picked = Total then
    Result := 1
  else
    Result := 2;
end;

{ The branches not deleted, and in how many repositories. }
function TGittanBatchPage.GoneCount(out ARepos: integer): integer;
var
  r, n: integer;
begin
  Result := 0;
  ARepos := 0;
  for r := 0 to High(FGone) do
  begin
    n := Pickable(r);
    Inc(Result, n);
    if n > 0 then
      Inc(ARepos);
  end;
end;

procedure TGittanBatchPage.ToggleGone(AIndex: integer);
var
  b: integer;
  TurnOn: boolean;
  Key: string;
begin
  if FDeleting or (AIndex < 0) or (AIndex > High(FGone)) then
    Exit;
  TurnOn := GoneState(AIndex) <> 1;
  for b := 0 to High(FGone[AIndex].Branches) do
  begin
    if FGone[AIndex].Branches[b].Deleted then
      Continue;
    Key := PickKey(FGone[AIndex].Path, FGone[AIndex].Branches[b].Name);
    if TurnOn then
      FPicked.Add(Key)
    else if FPicked.IndexOf(Key) >= 0 then
      FPicked.Delete(FPicked.IndexOf(Key));
  end;
  Layout;
  Invalidate;
end;

procedure TGittanBatchPage.ToggleBranch(AIndex, ABranch: integer);
var
  Key: string;
  i: integer;
begin
  if FDeleting or (AIndex < 0) or (AIndex > High(FGone)) or (ABranch < 0) or
    (ABranch > High(FGone[AIndex].Branches)) or FGone[AIndex].Branches[ABranch].Deleted then
    Exit;
  Key := PickKey(FGone[AIndex].Path, FGone[AIndex].Branches[ABranch].Name);
  i := FPicked.IndexOf(Key);
  if i >= 0 then
    FPicked.Delete(i)
  else
    FPicked.Add(Key);
  Layout;
  Invalidate;
end;

{ ---------------------------------------------------------------------------
  Painting
  --------------------------------------------------------------------------- }

{ A check box ASize across: empty (AState 0), checked (1) or with a dash
  (2), in the link color; dim when not AEnabled. }
procedure TGittanBatchPage.PaintBox(ALeft, ATop, ASize, AState: integer; AEnabled: boolean);
var
  R: TRect;
  W: integer;
  Accent: TColor;
begin
  R := Rect(ALeft, ATop, ALeft + ASize, ATop + ASize);
  if AEnabled then
    Accent := FLink
  else
    Accent := MixColor(FBack, FDim, 0.5);
  FC.Pen.Style := psSolid;
  FC.Pen.Width := 1;
  FC.Brush.Style := bsSolid;
  if AState = 0 then
  begin
    if AEnabled then
      FC.Pen.Color := FDim
    else
      FC.Pen.Color := MixColor(FBack, FDim, 0.4);
    FC.Brush.Color := FBack;
    FC.RoundRect(R, Px(5), Px(5));
    FC.Brush.Style := bsClear;
    Exit;
  end;
  FC.Pen.Color := Accent;
  FC.Brush.Color := Accent;
  FC.RoundRect(R, Px(5), Px(5));
  FC.Brush.Style := bsClear;
  W := Max(2, ASize div 7);
  FC.Pen.Color := clWhite;
  FC.Pen.Width := W;
  if AState = 1 then
  begin
    FC.Line(ALeft + ASize * 4 div 15, ATop + ASize * 8 div 15,
      ALeft + ASize * 7 div 15, ATop + ASize * 11 div 15);
    FC.Line(ALeft + ASize * 7 div 15, ATop + ASize * 11 div 15,
      ALeft + ASize * 11 div 15, ATop + ASize * 5 div 15);
  end
  else
    FC.Line(ALeft + ASize * 4 div 15, ATop + ASize div 2, ALeft + ASize * 11 div 15,
      ATop + ASize div 2);
  FC.Pen.Width := 1;
end;

{ A tag ending at ARight in a smaller font, its text in AColor on the
  hover fill, its middle on the line at ATop; gives its left edge. }
function TGittanBatchPage.PaintTag(ARight, ATop: integer; const AText: string;
  AColor: TColor): integer;
var
  W, H, LineH: integer;
  R: TRect;
begin
  FC.Font := Font;
  LineH := FC.TextHeight('Xg');
  FC.Font.Size := Max(7, Font.Size - 2);
  if Font.Size <= 0 then
    FC.Font.Size := 9;
  W := FC.TextWidth(AText) + 2 * Px(TagPadX);
  H := FC.TextHeight(AText) + 2 * Px(TagPadY);
  R := Rect(ARight - W, ATop + (LineH - H) div 2, ARight, ATop + (LineH - H) div 2 + H);
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FHover;
  FC.RoundRect(R, Px(TagRadius), Px(TagRadius));
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;
  FC.Font.Color := AColor;
  FC.TextOut(R.Left + Px(TagPadX), R.Top + Px(TagPadY), AText);
  FC.Font := Font;
  Result := R.Left;
end;

{ A dim bold title with a dim detail after it over a divider, as the
  forge page's; with AChips the list's: a chevron before the title,
  down while it is unfolded, the title and the detail a link that folds
  or unfolds it, and All and None at the right while it is unfolded. }
{ A chevron ASize across in AColor: pointing down with AOpen, else
  right. }
procedure TGittanBatchPage.PaintChevron(ALeft, ATop, ASize: integer; AOpen: boolean;
  AColor: TColor);
var
  M: integer;
begin
  FC.Pen.Style := psSolid;
  FC.Pen.Color := AColor;
  FC.Pen.Width := Max(1, ASize div 6);
  M := ASize div 2;
  if AOpen then
  begin
    FC.Line(ALeft + 1, ATop + ASize * 3 div 10, ALeft + M, ATop + ASize * 7 div 10);
    FC.Line(ALeft + M, ATop + ASize * 7 div 10, ALeft + ASize - 1, ATop + ASize * 3 div 10);
  end
  else
  begin
    FC.Line(ALeft + ASize * 3 div 10, ATop + 1, ALeft + ASize * 7 div 10, ATop + M);
    FC.Line(ALeft + ASize * 7 div 10, ATop + M, ALeft + ASize * 3 div 10, ATop + ASize - 1);
  end;
  FC.Pen.Width := 1;
end;

procedure TGittanBatchPage.PaintHeading(var Y: integer; const ATitle, ADetail: string;
  ALeft, ARight: integer; AChips: boolean);
var
  TextH, X, W: integer;
  Hot: boolean;
begin
  Inc(Y, Px(Pad));
  FC.Font := Font;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FDim;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  X := ALeft;
  Hot := False;
  if AChips then
  begin
    { The link first, so the chevron and the text know it is hot. }
    FC.Font.Style := [];
    W := Px(14) + FC.TextWidth(ADetail) + Px(Gap) div 2;
    FC.Font.Style := [fsBold];
    Inc(W, FC.TextWidth(ATitle));
    if FReposOpen then
      AddLink(Rect(ALeft - Px(4), Y - Px(4), ALeft + W + Px(4), Y + TextH + Px(4)), FoldLink)
    else
      AddLink(Rect(ALeft - Px(4), Y - Px(4), ALeft + W + Px(4), Y + TextH + Px(4)), UnfoldLink);
    Hot := FHot = High(FLinkRects);
    if Hot then
      FC.Font.Color := FText;
    PaintChevron(X, Y + (TextH - Px(10)) div 2, Px(10), FReposOpen, FC.Font.Color);
    Inc(X, Px(14));
  end;
  FC.TextOut(X, Y, ATitle);
  X := X + FC.TextWidth(ATitle) + Px(Gap) div 2;
  FC.Font.Style := [];
  if ADetail <> '' then
    FC.TextOut(X, Y, ADetail);
  if AChips and FReposOpen then
  begin
    X := ARight - PillWidth(rsNoneChip);
    PaintPill(X, Y, rsNoneChip, NoneLink, False, True);
    X := X - Px(6) - PillWidth(rsAllChip);
    PaintPill(X, Y, rsAllChip, AllLink, False, True);
  end;
  Inc(Y, TextH + Px(Gap) div 2);
  FC.Pen.Style := psSolid;
  FC.Pen.Color := FLine;
  FC.Line(ALeft, Y, ARight, Y);
  Inc(Y, Px(Gap) div 2);
end;

{ The repositories, a row each, indented by depth: the box, a folder's
  name in bold with how many it holds, a repository's name with its
  path dim after it ("not found" when its folder is gone). }
procedure TGittanBatchPage.PaintRows(var Y: integer; ALeft, ARight: integer);
var
  i, TextH, RowH, S, X: integer;
  R: TRect;
  Detail: string;
begin
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  RowH := TextH + 2 * Px(RowPadY);
  S := Max(Px(12), TextH - Px(2));
  if Length(FRows) = 0 then
  begin
    Inc(Y, Px(Gap) div 2);
    PaintText(Y, rsNoRepos, FDim, ALeft, ARight);
    Exit;
  end;
  for i := 0 to High(FRows) do
  begin
    R := Rect(ALeft, Y, ARight, Y + RowH);
    AddLink(R, RowLink + IntToStr(i));
    if FHot = High(FLinkRects) then
    begin
      FC.Pen.Style := psClear;
      FC.Brush.Style := bsSolid;
      FC.Brush.Color := FHover;
      FC.RoundRect(R, Px(8), Px(8));
      FC.Pen.Style := psSolid;
    end;
    X := ALeft + Px(6) + FRows[i].Depth * Px(Indent);
    PaintBox(X, Y + (RowH - S) div 2, S, RowState(i),
      not FRows[i].IsFolder or (Length(BatchRowRepos(FRows, i)) > 0));
    Inc(X, S + Px(BoxGap));
    FC.Font := Font;
    FC.Brush.Style := bsClear;
    if FRows[i].IsFolder then
    begin
      FC.Font.Style := [fsBold];
      FC.Font.Color := FText;
      FC.TextOut(X, Y + Px(RowPadY), FitTextLeft(FC, FRows[i].Caption, ARight - X));
      Inc(X, FC.TextWidth(FRows[i].Caption) + Px(Gap) div 2);
      FC.Font.Style := [];
      FC.Font.Color := FDim;
      Detail := IntToStr(Length(BatchRowRepos(FRows, i)));
      if X < ARight - Px(Gap) then
        FC.TextOut(X, Y + Px(RowPadY), Detail);
    end
    else
    begin
      if FMissing[i] then
        FC.Font.Color := FDim
      else
        FC.Font.Color := FText;
      FC.TextOut(X, Y + Px(RowPadY), FitTextLeft(FC, FRows[i].Caption, ARight - X));
      Inc(X, FC.TextWidth(FRows[i].Caption) + Px(Gap));
      FC.Font.Color := FDim;
      if FMissing[i] then
        Detail := rsNotFound
      else
        Detail := ShortPath(FRows[i].Path);
      if X < ARight - Px(Gap) then
        FC.TextOut(X, Y + Px(RowPadY), FitTextLeft(FC, Detail, ARight - Px(6) - X));
    end;
    Inc(Y, RowH);
  end;
end;

{ A repository's card: its box (of its branches), its name in bold and
  its path dim, the fetch's failure and an error under them, then a row
  per gone branch: its box, its name and at the right whether it is
  merged, or what its deletion did. }
procedure TGittanBatchPage.PaintGoneCard(var Y: integer; AIndex, ALeft, ARight: integer);
var
  G: TGittanGoneRepo;
  TextH, RowH, S, H, X, RowTop, b, TagLeft: integer;
  R: TRect;
  Notes: array of string;
  NoteColors: array of TColor;
  TagText: string;
  TagColor: TColor;
  CanPick: boolean;

  procedure AddNote(const AText: string; AColor: TColor);
  begin
    SetLength(Notes, Length(Notes) + 1);
    SetLength(NoteColors, Length(NoteColors) + 1);
    Notes[High(Notes)] := AText;
    NoteColors[High(NoteColors)] := AColor;
  end;

begin
  G := FGone[AIndex];
  Notes := nil;
  NoteColors := nil;
  if G.Error <> '' then
    AddNote(FirstLine(G.Error), FErrorColor);
  if G.FetchError <> '' then
    AddNote(Format(rsFetchFailed, [FirstLine(G.FetchError)]), FWarn);
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  RowH := TextH + 2 * Px(RowPadY);
  S := Max(Px(12), TextH - Px(2));
  H := 2 * Px(CardPadY) + TextH + Length(Notes) * (TextH + Px(4)) +
    Length(G.Branches) * RowH;
  if Length(G.Branches) > 0 then
    Inc(H, Px(4));
  R := Rect(ALeft, Y, ARight, Y + H);
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FCard;
  FC.RoundRect(R, Px(CardRadius), Px(CardRadius));
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;

  RowTop := Y + Px(CardPadY);
  X := ALeft + Px(CardPadX);
  if Length(G.Branches) > 0 then
  begin
    CanPick := not FDeleting and (Pickable(AIndex) > 0);
    if CanPick then
      AddLink(Rect(ALeft, RowTop - Px(4), ARight, RowTop + TextH + Px(4)), GoneLink + IntToStr(AIndex));
    PaintBox(X, RowTop + (TextH - S) div 2, S, GoneState(AIndex), CanPick);
    Inc(X, S + Px(BoxGap));
  end;
  FC.Font := Font;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  FC.TextOut(X, RowTop, FitTextLeft(FC, G.Caption, ARight - Px(CardPadX) - X));
  Inc(X, FC.TextWidth(G.Caption) + Px(Gap));
  FC.Font.Style := [];
  FC.Font.Color := FDim;
  if X < ARight - Px(CardPadX) - Px(Gap) then
    FC.TextOut(X, RowTop, FitTextLeft(FC, ShortPath(G.Path), ARight - Px(CardPadX) - X));
  Inc(RowTop, TextH);
  for b := 0 to High(Notes) do
  begin
    Inc(RowTop, Px(4));
    FC.Font.Color := NoteColors[b];
    FC.TextOut(ALeft + Px(CardPadX), RowTop, FitTextLeft(FC, Notes[b],
      ARight - ALeft - 2 * Px(CardPadX)));
    Inc(RowTop, TextH);
  end;
  if Length(G.Branches) > 0 then
    Inc(RowTop, Px(4));

  for b := 0 to High(G.Branches) do
  begin
    R := Rect(ALeft + Px(CardPadX) div 2, RowTop, ARight - Px(CardPadX) div 2, RowTop + RowH);
    CanPick := not FDeleting and not G.Branches[b].Deleted;
    if CanPick then
    begin
      AddLink(R, BranchLink + IntToStr(AIndex) + ':' + IntToStr(b));
      if FHot = High(FLinkRects) then
      begin
        FC.Pen.Style := psClear;
        FC.Brush.Style := bsSolid;
        FC.Brush.Color := FHover;
        FC.RoundRect(R, Px(8), Px(8));
        FC.Pen.Style := psSolid;
        FC.Brush.Style := bsClear;
      end;
    end;
    X := ALeft + Px(CardPadX) + Px(Indent);
    if G.Branches[b].Deleted then
      PaintBox(X, RowTop + (RowH - S) div 2, S, 0, False)
    else
      PaintBox(X, RowTop + (RowH - S) div 2, S,
        Ord(FPicked.IndexOf(PickKey(G.Path, G.Branches[b].Name)) >= 0), CanPick);
    Inc(X, S + Px(BoxGap));
    if G.Branches[b].Deleted then
    begin
      TagText := Format(rsDeletedWas, [G.Branches[b].Was]);
      TagColor := FDim;
    end
    else if G.Branches[b].Error <> '' then
    begin
      TagText := G.Branches[b].Error;
      TagColor := FErrorColor;
    end
    else
      case G.Branches[b].Merge of
        gmMerged:
        begin
          TagText := rsMerged;
          TagColor := FOk;
        end;
        gmSquashed:
        begin
          TagText := rsSquashed;
          TagColor := FOk;
        end;
        else
        begin
          TagText := rsNotMerged;
          TagColor := FWarn;
        end;
      end;
    { A long reason from git is cut to half the row. }
    FC.Font := Font;
    TagText := FitTextLeft(FC, TagText, (ARight - X) div 2);
    TagLeft := PaintTag(ARight - Px(CardPadX), RowTop + Px(RowPadY), TagText, TagColor);
    FC.Font := Font;
    FC.Brush.Style := bsClear;
    if G.Branches[b].Deleted then
      FC.Font.Color := FDim
    else
      FC.Font.Color := FText;
    FC.TextOut(X, RowTop + Px(RowPadY), FitTextLeft(FC, G.Branches[b].Name, TagLeft - Px(Gap) - X));
    Inc(RowTop, RowH);
  end;
  Inc(Y, H + Px(CardGap));
end;

{ The gone branches: what Scan does, Scan with the progress after it or
  what was found, the cards, the repositories with
  nothing gone, and Delete. }
procedure TGittanBatchPage.PaintGone(var Y: integer; ALeft, ARight: integer);
var
  TextH, n, Repos, i, Picked, Cards: integer;
  Detail, ButtonText, Nothing: string;
  R: TRect;
begin
  n := GoneCount(Repos);
  Detail := '';
  if FScanned and (n > 0) then
    if Repos = 1 then
      Detail := Format(rsGoneOneRepo, [n])
    else
      Detail := Format(rsGoneManyRepos, [n, Repos]);
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  PaintText(Y, rsGoneAbout, FDim, ALeft, ARight);
  Inc(Y, Px(Gap));

  { Scan, and how far it got. }
  i := ChosenCount;
  if i = 0 then
    ButtonText := rsScanNone
  else if i = 1 then
    ButtonText := rsScanOne
  else
    ButtonText := Format(rsScanMany, [i]);
  Inc(Y, Px(PillPadY));
  R := PaintPill(ALeft, Y, ButtonText, ScanLink, True, (i > 0) and not Busy);
  if FScanning then
  begin
    FC.Font.Color := FDim;
    FC.TextOut(R.Right + Px(Gap), Y, Format(rsScanning, [Min(FGoneDone + 1, FGoneTotal),
      FGoneTotal]));
  end
  else if Detail <> '' then
  begin
    FC.Font.Color := FDim;
    FC.TextOut(R.Right + Px(Gap), Y, Detail);
  end;
  Inc(Y, TextH + Px(PillPadY) + Px(Gap));

  Nothing := '';
  Cards := 0;
  for i := 0 to FGoneDone - 1 do
    if (Length(FGone[i].Branches) = 0) and (FGone[i].Error = '') and (FGone[i].FetchError = '')
    then
    begin
      if Nothing <> '' then
        Nothing := Nothing + ', ';
      Nothing := Nothing + FGone[i].Caption;
    end
    else
    begin
      PaintGoneCard(Y, i, ALeft, ARight);
      Inc(Cards);
    end;
  { Every one scanned had nothing to say: one line says so. }
  if (Cards = 0) and (FGoneDone > 0) and not FScanning then
  begin
    PaintText(Y, rsAllClean, FDim, ALeft, ARight);
    Inc(Y, Px(Gap));
  end
  else if Nothing <> '' then
  begin
    PaintText(Y, Format(rsNothingGone, [Nothing]), FDim, ALeft, ARight);
    Inc(Y, Px(Gap));
  end;

  { Delete, once something was found. }
  if n > 0 then
  begin
    Picked := Length(PickedRefs);
    if FDeleting then
      ButtonText := rsDeleting
    else if Picked = 0 then
      ButtonText := rsDeleteNone
    else if Picked = 1 then
      ButtonText := rsDeleteOne
    else
      ButtonText := Format(rsDeleteMany, [Picked]);
    Inc(Y, Px(PillPadY));
    PaintPill(ALeft, Y, ButtonText, DeleteLink, True, (Picked > 0) and not Busy);
    Inc(Y, TextH + Px(PillPadY));
  end;
end;

{ ---------------------------------------------------------------------------
  The overview
  --------------------------------------------------------------------------- }

procedure TGittanBatchPage.StartCheck(ATotal: integer);
begin
  FStatus := nil;
  FStatusDone := 0;
  FStatusTotal := ATotal;
  FChecking := True;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanBatchPage.SetStatus(const ARepos: TGittanRepoStatuses; ADone: integer;
  ARunning: boolean);
begin
  ADone := Min(ADone, Length(ARepos));
  { Only what is done: the thread may still write the rest. }
  FStatus := Copy(ARepos, 0, ADone);
  FStatusDone := ADone;
  FChecking := ARunning;
  Layout;
  Invalidate;
end;

{ The branches with their counts, joined: "keep (1), feature/x (3)". }
function CountsText(const ACounts: TGittanBranchCounts): string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(ACounts) do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Format(rsBranchCount, [ACounts[i].Name, ACounts[i].Count]);
  end;
end;

{ A repository's card in the overview: a head with its name in bold, the
  branch and the path dim and Open at the right, all of it a link that
  opens the repository; then a line, wrapped, for each thing left
  undone, the ones that may lose work in the warning color. }
procedure TGittanBatchPage.PaintStatusCard(var Y: integer; AIndex, ALeft, ARight: integer);
var
  St: TGittanRepoStatus;
  Lines: array of string;
  LineColors: array of TColor;
  TextH, H, X, RowTop, i, Inner, OpenW, Room: integer;
  R, HeadR: TRect;
  Style: TTextStyle;
  Part, Detail: string;
  Hot, CanOpen: boolean;

  procedure AddLine(const AText: string; AColor: TColor);
  begin
    SetLength(Lines, Length(Lines) + 1);
    SetLength(LineColors, Length(LineColors) + 1);
    Lines[High(Lines)] := AText;
    LineColors[High(LineColors)] := AColor;
  end;

begin
  St := FStatus[AIndex];
  Lines := nil;
  LineColors := nil;
  if St.Error <> '' then
    AddLine(FirstLine(St.Error), FErrorColor)
  else
  begin
    if St.Operation <> '' then
      AddLine(Format(rsInMiddle, [St.Operation]), FWarn);
    if St.Detached then
      AddLine(rsDetached, FWarn);
    Part := '';
    if St.Changed = 1 then
      Part := rsChangedOne
    else if St.Changed > 1 then
      Part := Format(rsChangedMany, [St.Changed]);
    if St.Untracked > 0 then
    begin
      if Part <> '' then
        Part := Part + ', ';
      if St.Untracked = 1 then
        Part := Part + rsUntrackedOne
      else
        Part := Part + Format(rsUntrackedMany, [St.Untracked]);
    end;
    if Part <> '' then
      AddLine(Part, FText);
    if St.Stashes = 1 then
      AddLine(rsStashOne, FText)
    else if St.Stashes > 1 then
      AddLine(Format(rsStashMany, [St.Stashes]), FText);
    if Length(St.Unpushed) > 0 then
      AddLine(Format(rsNotPushed, [CountsText(St.Unpushed)]), FText);
    if Length(St.Unshared) > 0 then
      AddLine(Format(rsOnNoRemote, [CountsText(St.Unshared)]), FWarn);
    if St.NoRemote then
      AddLine(rsNoRemote, FWarn);
  end;

  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  Inner := ARight - ALeft - 2 * Px(CardPadX);
  H := 2 * Px(CardPadY) + TextH;
  for i := 0 to High(Lines) do
    Inc(H, Px(4) + WrappedHeight(Lines[i], Inner));
  R := Rect(ALeft, Y, ARight, Y + H);
  HeadR := Rect(ALeft, Y, ARight, Y + Px(CardPadY) + TextH + Px(4));
  { A repository that could not be read has nothing to open. }
  CanOpen := St.Error = '';
  Hot := False;
  if CanOpen then
  begin
    AddLink(HeadR, OpenLink + IntToStr(AIndex));
    Hot := FHot = High(FLinkRects);
  end;
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FCard;
  FC.RoundRect(R, Px(CardRadius), Px(CardRadius));
  if Hot then
  begin
    FC.Brush.Color := FHover;
    FC.RoundRect(HeadR, Px(CardRadius), Px(CardRadius));
  end;
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;

  { The head: Open at the right, the name, the branch, then the path,
    which gives way first (its end kept). }
  RowTop := Y + Px(CardPadY);
  FC.Font := Font;
  OpenW := 0;
  if CanOpen then
  begin
    OpenW := FC.TextWidth(rsOpen);
    if Hot then
      FC.Font.Color := FLink
    else
      FC.Font.Color := FDim;
    FC.TextOut(ARight - Px(CardPadX) - OpenW, RowTop, rsOpen);
  end;
  Room := ARight - Px(CardPadX) - OpenW - Px(Gap);
  X := ALeft + Px(CardPadX);
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  FC.TextOut(X, RowTop, FitTextLeft(FC, St.Caption, Room - X));
  Inc(X, FC.TextWidth(St.Caption) + Px(Gap));
  FC.Font.Style := [];
  FC.Font.Color := FDim;
  if (St.Branch <> '') and (X < Room - Px(Gap)) then
  begin
    Detail := Format(rsOnBranch, [St.Branch]);
    FC.TextOut(X, RowTop, FitTextLeft(FC, Detail, Room - X));
    Inc(X, FC.TextWidth(Detail) + Px(Gap));
  end;
  if X < Room - 3 * Px(Gap) then
    FC.TextOut(X, RowTop, FitTextLeft(FC, ShortPath(St.Path), Room - X));
  Inc(RowTop, TextH);

  { The lines, wrapped. }
  Style := FC.TextStyle;
  Style.Wordbreak := True;
  Style.SingleLine := False;
  Style.Alignment := taLeftJustify;
  Style.Layout := tlTop;
  for i := 0 to High(Lines) do
  begin
    Inc(RowTop, Px(4));
    FC.Font.Color := LineColors[i];
    H := WrappedHeight(Lines[i], Inner);
    R := Rect(ALeft + Px(CardPadX), RowTop, ALeft + Px(CardPadX) + Inner, RowTop + H);
    FC.TextRect(R, R.Left, R.Top, Lines[i], Style);
    Inc(RowTop, H);
  end;
  Y := RowTop + Px(CardPadY) + Px(CardGap);
end;

{ The overview: what Check does, Check with the progress after it, or
  how many need something once it is done, the cards, and the clean
  repositories on one line. }
procedure TGittanBatchPage.PaintStatus(var Y: integer; ALeft, ARight: integer);
var
  i, Cards: integer;
  Detail, Clean: string;
begin
  Cards := 0;
  for i := 0 to FStatusDone - 1 do
    if not StatusClean(FStatus[i]) then
      Inc(Cards);
  Detail := '';
  if (FStatusDone > 0) and not FChecking then
    if Cards = 1 then
      Detail := Format(rsNeedOne, [FStatusDone])
    else
      Detail := Format(rsNeedMany, [Cards, FStatusDone]);
  PaintText(Y, rsStatusAbout, FDim, ALeft, ARight);
  Inc(Y, Px(Gap));

  PaintCheckPill(Y, ALeft, FChecking, FStatusDone, FStatusTotal, Detail);

  Clean := '';
  for i := 0 to FStatusDone - 1 do
    if StatusClean(FStatus[i]) then
    begin
      if Clean <> '' then
        Clean := Clean + ', ';
      Clean := Clean + FStatus[i].Caption;
    end
    else
      PaintStatusCard(Y, i, ALeft, ARight);
  if (Cards = 0) and (FStatusDone > 0) and not FChecking then
  begin
    PaintText(Y, rsAllDone, FDim, ALeft, ARight);
    Inc(Y, Px(Gap));
  end
  else if Clean <> '' then
  begin
    PaintText(Y, Format(rsCleanIn, [Clean]), FDim, ALeft, ARight);
    Inc(Y, Px(Gap));
  end;
end;

{ Check, for the picked repositories, with the progress after it while
  ARunning, else ADetail. }
procedure TGittanBatchPage.PaintCheckPill(var Y: integer; ALeft: integer; ARunning: boolean;
  ADone, ATotal: integer; const ADetail: string);
var
  i, TextH: integer;
  ButtonText: string;
  R: TRect;
begin
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  i := ChosenCount;
  if i = 0 then
    ButtonText := rsCheckNone
  else if i = 1 then
    ButtonText := rsCheckOne
  else
    ButtonText := Format(rsCheckMany, [i]);
  Inc(Y, Px(PillPadY));
  R := PaintPill(ALeft, Y, ButtonText, CheckLink, False, (i > 0) and not ARunning);
  FC.Font.Color := FDim;
  if ARunning then
    FC.TextOut(R.Right + Px(Gap), Y, Format(rsChecking, [Min(ADone + 1, ATotal), ATotal]))
  else if ADetail <> '' then
    FC.TextOut(R.Right + Px(Gap), Y, ADetail);
  Inc(Y, TextH + Px(PillPadY) + Px(Gap));
end;

{ ---------------------------------------------------------------------------
  Identity
  --------------------------------------------------------------------------- }

procedure TGittanBatchPage.StartIdentity(ATotal: integer);
begin
  FIds := nil;
  FIdsDone := 0;
  FIdsTotal := ATotal;
  FReadingIds := True;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanBatchPage.SetIdentities(const ARepos: TGittanRepoIdentities; ADone: integer;
  ARunning: boolean);
begin
  ADone := Min(ADone, Length(ARepos));
  { Only what is done: the thread may still write the rest. }
  FIds := Copy(ARepos, 0, ADone);
  MarkOddIdentities(FIds);
  FIdsDone := ADone;
  FReadingIds := ARunning;
  Layout;
  Invalidate;
end;

{ A signing key as it is shown: a file's name of a path, the start and
  the end of a key given in full, else as it is. }
function KeyText(const AKey: string): string;
var
  Key, Rest: string;
  p: integer;
begin
  Key := Trim(AKey);
  if Copy(Key, 1, 5) = 'key::' then
    Delete(Key, 1, 5);
  if (Pos('/', Key) > 0) or (Pos('\', Key) > 0) then
    Exit(ExtractFileName(StringReplace(Key, '\', '/', [rfReplaceAll])));
  p := Pos(' ', Key);
  if (p > 0) and (Length(Key) > 32) then
  begin
    Rest := Trim(Copy(Key, p + 1, MaxInt));
    Exit(Copy(Key, 1, p - 1) + ' …' + Copy(Rest, Max(1, Length(Rest) - 7), 8));
  end;
  Result := Key;
end;

{ A card of the repositories in AMembers, which commit as the same: the
  name and the e-mail in bold, how commits are signed, then a row per
  repository, which opens it, with its remote's owner and its tags. One
  that could not be read has a card of its own with git's reason. }
procedure TGittanBatchPage.PaintIdentityCard(var Y: integer; const AMembers: array of integer;
  ALeft, ARight: integer);
var
  Id: TGittanRepoIdentity;
  TextH, RowH, H, X, RowTop, m, TagLeft: integer;
  R: TRect;
  Head, Line, Where: string;
  HeadColor, LineColor: TColor;
begin
  Id := FIds[AMembers[0]];
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  RowH := TextH + 2 * Px(RowPadY);
  if Id.Error <> '' then
  begin
    Head := Id.Caption;
    HeadColor := FText;
    Line := FirstLine(Id.Error);
    LineColor := FErrorColor;
  end
  else
  begin
    HeadColor := FText;
    if (Id.Name = '') and (Id.Email = '') then
    begin
      Head := rsNoIdentity;
      HeadColor := FWarn;
    end
    else if Id.Email = '' then
    begin
      Head := Format(rsNoEmail, [Id.Name]);
      HeadColor := FWarn;
    end
    else if Id.Name = '' then
    begin
      Head := Format(rsNoName, [Id.Email]);
      HeadColor := FWarn;
    end
    else
      Head := Id.Name + ' <' + Id.Email + '>';
    if not Id.Sign then
      Line := rsNoSign
    else if Id.SigningKey = '' then
      Line := Format(rsSignsDefault, [Id.SignFormat])
    else
      Line := Format(rsSigns, [Id.SignFormat, KeyText(Id.SigningKey)]);
    LineColor := FDim;
  end;

  H := 2 * Px(CardPadY) + 2 * TextH + Px(4);
  if Id.Error = '' then
    Inc(H, Px(4) + Length(AMembers) * RowH);
  R := Rect(ALeft, Y, ARight, Y + H);
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FCard;
  FC.RoundRect(R, Px(CardRadius), Px(CardRadius));
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;

  RowTop := Y + Px(CardPadY);
  X := ALeft + Px(CardPadX);
  FC.Font := Font;
  FC.Font.Style := [fsBold];
  FC.Font.Color := HeadColor;
  FC.TextOut(X, RowTop, FitTextLeft(FC, Head, ARight - Px(CardPadX) - X));
  Inc(RowTop, TextH + Px(4));
  FC.Font := Font;
  FC.Font.Color := LineColor;
  FC.TextOut(X, RowTop, FitTextLeft(FC, Line, ARight - Px(CardPadX) - X));
  Inc(RowTop, TextH);

  if Id.Error = '' then
  begin
    Inc(RowTop, Px(4));
    for m := 0 to High(AMembers) do
    begin
      Id := FIds[AMembers[m]];
      R := Rect(ALeft + Px(CardPadX) div 2, RowTop, ARight - Px(CardPadX) div 2, RowTop + RowH);
      AddLink(R, IdOpenLink + IntToStr(AMembers[m]));
      if FHot = High(FLinkRects) then
      begin
        FC.Pen.Style := psClear;
        FC.Brush.Style := bsSolid;
        FC.Brush.Color := FHover;
        FC.RoundRect(R, Px(8), Px(8));
        FC.Pen.Style := psSolid;
        FC.Brush.Style := bsClear;
      end;
      TagLeft := ARight - Px(CardPadX);
      if Id.Odd then
        TagLeft := PaintTag(TagLeft, RowTop + Px(RowPadY), Format(rsOdd, [Id.Owner]), FWarn) -
          Px(6);
      if (Id.EmailScope = 'local') or (Id.EmailScope = 'worktree') then
        TagLeft := PaintTag(TagLeft, RowTop + Px(RowPadY), rsSetHere, FDim) - Px(6);
      X := ALeft + Px(CardPadX) + Px(Indent);
      FC.Font := Font;
      FC.Brush.Style := bsClear;
      FC.Font.Color := FText;
      FC.TextOut(X, RowTop + Px(RowPadY), FitTextLeft(FC, Id.Caption, TagLeft - Px(Gap) - X));
      Inc(X, FC.TextWidth(Id.Caption) + Px(Gap));
      Where := Id.Owner;
      if Where = '' then
        Where := rsNoOwner;
      FC.Font.Color := FDim;
      if X < TagLeft - 3 * Px(Gap) then
        FC.TextOut(X, RowTop + Px(RowPadY), FitTextLeft(FC, Where, TagLeft - Px(Gap) - X));
      Inc(RowTop, RowH);
    end;
  end;
  Inc(Y, H + Px(CardGap));
end;

{ The identity check: what it does, Check with the progress after it or
  how many identities once done, then a card per identity, the most
  used first, and one per repository that could not be read. }
procedure TGittanBatchPage.PaintIdentity(var Y: integer; ALeft, ARight: integer);
var
  Groups: array of array of integer;
  Errors: array of integer;
  i, g, j, Marked: integer;
  Detail: string;
  Swap: array of integer;
begin
  Groups := nil;
  Errors := nil;
  Marked := 0;
  for i := 0 to FIdsDone - 1 do
  begin
    if FIds[i].Odd then
      Inc(Marked);
    if FIds[i].Error <> '' then
    begin
      SetLength(Errors, Length(Errors) + 1);
      Errors[High(Errors)] := i;
      Continue;
    end;
    g := 0;
    while (g <= High(Groups)) and not SameIdentity(FIds[Groups[g][0]], FIds[i]) do
      Inc(g);
    if g > High(Groups) then
    begin
      SetLength(Groups, Length(Groups) + 1);
      Groups[g] := nil;
    end;
    SetLength(Groups[g], Length(Groups[g]) + 1);
    Groups[g][High(Groups[g])] := i;
  end;
  { The most used first, in the order they came otherwise. }
  for g := 1 to High(Groups) do
  begin
    j := g;
    while (j > 0) and (Length(Groups[j]) > Length(Groups[j - 1])) do
    begin
      Swap := Groups[j];
      Groups[j] := Groups[j - 1];
      Groups[j - 1] := Swap;
      Dec(j);
    end;
  end;

  Detail := '';
  if (FIdsDone > 0) and not FReadingIds and (Length(Groups) > 0) then
  begin
    if (Length(Groups) = 1) and (FIdsDone = 1) then
      Detail := rsIdOne
    else if Length(Groups) = 1 then
      Detail := Format(rsIdOneInAll, [Length(Groups[0])])
    else
      Detail := Format(rsIdMany, [Length(Groups), FIdsDone - Length(Errors)]);
    if Marked > 0 then
      Detail := Detail + Format(rsIdMarked, [Marked]);
  end;
  PaintText(Y, rsIdentityAbout, FDim, ALeft, ARight);
  Inc(Y, Px(Gap));
  PaintCheckPill(Y, ALeft, FReadingIds, FIdsDone, FIdsTotal, Detail);
  for g := 0 to High(Groups) do
    PaintIdentityCard(Y, Groups[g], ALeft, ARight);
  for i := 0 to High(Errors) do
    PaintIdentityCard(Y, [Errors[i]], ALeft, ARight);
end;

{ ---------------------------------------------------------------------------
  Maintenance
  --------------------------------------------------------------------------- }

procedure TGittanBatchPage.StartMaintScan(ATotal: integer);
begin
  FMaint := nil;
  FMaintDone := 0;
  FMaintTotal := ATotal;
  FMaintSeen := 0;
  FMaintPicked.Clear;
  FMaintScanning := True;
  FMaintScanned := True;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanBatchPage.SetMaintScan(const ARepos: TGittanMaintRepos; ADone: integer;
  ARunning: boolean);
var
  i, j: integer;
begin
  ADone := Min(ADone, Length(ARepos));
  { Only what is done: the thread may still write the rest. }
  FMaint := Copy(ARepos, 0, ADone);
  FMaintDone := ADone;
  FMaintScanning := ARunning;
  { Every task of what came is picked; what the user dropped since
    stays dropped. }
  for i := FMaintSeen to FMaintDone - 1 do
    for j := 0 to High(FMaint[i].Items) do
      FMaintPicked.Add(MaintKey(FMaint[i].Path, FMaint[i].Items[j].Task));
  FMaintSeen := Max(FMaintSeen, FMaintDone);
  Layout;
  Invalidate;
end;

procedure TGittanBatchPage.SetMaintRunning(ARunning: boolean);
begin
  FMaintRunning := ARunning;
  Layout;
  Invalidate;
end;

procedure TGittanBatchPage.ApplyMaintRun(const ARefs: TGittanMaintRefs; ADone: integer);
var
  i, r, t, k: integer;
begin
  for i := 0 to Min(ADone, Length(ARefs)) - 1 do
    for r := 0 to High(FMaint) do
      if FMaint[r].Path = ARefs[i].Path then
        for t := 0 to High(FMaint[r].Items) do
          if FMaint[r].Items[t].Task = ARefs[i].Item.Task then
          begin
            FMaint[r].Items[t] := ARefs[i].Item;
            k := FMaintPicked.IndexOf(MaintKey(ARefs[i].Path, ARefs[i].Item.Task));
            if ARefs[i].Item.Done and (k >= 0) then
              FMaintPicked.Delete(k);
          end;
  Layout;
  Invalidate;
end;

function TGittanBatchPage.PickedMaintRefs: TGittanMaintRefs;
var
  r, t, n: integer;
begin
  Result := nil;
  n := 0;
  for r := 0 to High(FMaint) do
    for t := 0 to High(FMaint[r].Items) do
      if not FMaint[r].Items[t].Done and
        (FMaintPicked.IndexOf(MaintKey(FMaint[r].Path, FMaint[r].Items[t].Task)) >= 0) then
      begin
        SetLength(Result, n + 1);
        Result[n].Path := FMaint[r].Path;
        Result[n].Item := FMaint[r].Items[t];
        Inc(n);
      end;
end;

{ The tasks found, and in how many repositories. }
function TGittanBatchPage.MaintCount(out ARepos: integer): integer;
var
  r: integer;
begin
  Result := 0;
  ARepos := 0;
  for r := 0 to FMaintDone - 1 do
    if Length(FMaint[r].Items) > 0 then
    begin
      Inc(Result, Length(FMaint[r].Items));
      Inc(ARepos);
    end;
end;

procedure TGittanBatchPage.ToggleMaint(ARepo, AItem: integer);
var
  Key: string;
  k: integer;
begin
  if (ARepo < 0) or (ARepo >= FMaintDone) or (AItem < 0) or
    (AItem > High(FMaint[ARepo].Items)) or FMaint[ARepo].Items[AItem].Done or Busy then
    Exit;
  Key := MaintKey(FMaint[ARepo].Path, FMaint[ARepo].Items[AItem].Task);
  k := FMaintPicked.IndexOf(Key);
  if k >= 0 then
    FMaintPicked.Delete(k)
  else
    FMaintPicked.Add(Key);
  Layout;
  Invalidate;
end;

{ A repository's card: its name and path, the remote's failure in the
  warning color or an error in the error color, then a row per task
  with its box, what it does, what was found dim, and once it ran a tag
  at the right. }
procedure TGittanBatchPage.PaintMaintCard(var Y: integer; AIndex, ALeft, ARight: integer);
var
  M: TGittanMaintRepo;
  It: TGittanMaintItem;
  TextH, RowH, S, H, X, RowTop, t, TagLeft, i: integer;
  R: TRect;
  Notes: array of string;
  NoteColors: array of TColor;
  Title, Detail, TagText: string;
  TagColor: TColor;
  CanPick: boolean;

  procedure AddNote(const AText: string; AColor: TColor);
  begin
    SetLength(Notes, Length(Notes) + 1);
    SetLength(NoteColors, Length(NoteColors) + 1);
    Notes[High(Notes)] := AText;
    NoteColors[High(NoteColors)] := AColor;
  end;

begin
  M := FMaint[AIndex];
  Notes := nil;
  NoteColors := nil;
  if M.Error <> '' then
    AddNote(FirstLine(M.Error), FErrorColor);
  if M.RemoteError <> '' then
    AddNote(Format(rsRemoteFailed, [FirstLine(M.RemoteError)]), FWarn);
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  RowH := TextH + 2 * Px(RowPadY);
  S := Max(Px(12), TextH - Px(2));
  H := 2 * Px(CardPadY) + TextH + Length(Notes) * (TextH + Px(4)) + Length(M.Items) * RowH;
  if Length(M.Items) > 0 then
    Inc(H, Px(4));
  R := Rect(ALeft, Y, ARight, Y + H);
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FCard;
  FC.RoundRect(R, Px(CardRadius), Px(CardRadius));
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;

  RowTop := Y + Px(CardPadY);
  X := ALeft + Px(CardPadX);
  FC.Font := Font;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  FC.TextOut(X, RowTop, FitTextLeft(FC, M.Caption, ARight - Px(CardPadX) - X));
  Inc(X, FC.TextWidth(M.Caption) + Px(Gap));
  FC.Font.Style := [];
  FC.Font.Color := FDim;
  if X < ARight - Px(CardPadX) - Px(Gap) then
    FC.TextOut(X, RowTop, FitTextLeft(FC, ShortPath(M.Path), ARight - Px(CardPadX) - X));
  Inc(RowTop, TextH);
  for t := 0 to High(Notes) do
  begin
    Inc(RowTop, Px(4));
    FC.Font.Color := NoteColors[t];
    FC.TextOut(ALeft + Px(CardPadX), RowTop, FitTextLeft(FC, Notes[t],
      ARight - ALeft - 2 * Px(CardPadX)));
    Inc(RowTop, TextH);
  end;
  if Length(M.Items) > 0 then
    Inc(RowTop, Px(4));

  for t := 0 to High(M.Items) do
  begin
    It := M.Items[t];
    case It.Task of
      mtSetHead:
      begin
        if It.Have = '' then
        begin
          Title := Format(rsSetHeadNew, [It.Want]);
          Detail := Format(rsHeadFrom, [It.Remote]);
        end
        else
        begin
          Title := Format(rsSetHead, [It.Have, It.Want]);
          Detail := Format(rsHeadRenamed, [It.Remote]);
        end;
      end;
      mtPruneWorktrees:
      begin
        if Length(It.Worktrees) = 1 then
          Title := rsPruneOne
        else
          Title := Format(rsPruneMany, [Length(It.Worktrees)]);
        Detail := '';
        for i := 0 to High(It.Worktrees) do
        begin
          if Detail <> '' then
            Detail := Detail + ', ';
          Detail := Detail + ShortPath(It.Worktrees[i]);
        end;
      end;
      else
      begin
        Title := rsPack;
        Detail := Format(rsPackDetail, [GroupDigits(It.Loose), FormatKiB(It.SizeKiB)]);
      end;
    end;
    R := Rect(ALeft + Px(CardPadX) div 2, RowTop, ARight - Px(CardPadX) div 2, RowTop + RowH);
    CanPick := not Busy and not It.Done;
    if CanPick then
    begin
      AddLink(R, MaintLink + IntToStr(AIndex) + ':' + IntToStr(t));
      if FHot = High(FLinkRects) then
      begin
        FC.Pen.Style := psClear;
        FC.Brush.Style := bsSolid;
        FC.Brush.Color := FHover;
        FC.RoundRect(R, Px(8), Px(8));
        FC.Pen.Style := psSolid;
        FC.Brush.Style := bsClear;
      end;
    end;
    X := ALeft + Px(CardPadX) + Px(Indent);
    if It.Done then
      PaintBox(X, RowTop + (RowH - S) div 2, S, 0, False)
    else
      PaintBox(X, RowTop + (RowH - S) div 2, S,
        Ord(FMaintPicked.IndexOf(MaintKey(M.Path, It.Task)) >= 0), CanPick);
    Inc(X, S + Px(BoxGap));
    TagLeft := ARight - Px(CardPadX);
    TagText := '';
    if It.Done then
    begin
      if It.Task = mtPack then
        TagText := Format(rsPackedTo, [FormatKiB(It.AfterKiB)])
      else
        TagText := rsMaintDone;
      TagColor := FOk;
    end
    else if It.Error <> '' then
    begin
      TagText := It.Error;
      TagColor := FErrorColor;
    end;
    if TagText <> '' then
    begin
      FC.Font := Font;
      { A long reason from git is cut to half the row. }
      TagText := FitTextLeft(FC, TagText, (ARight - X) div 2);
      TagLeft := PaintTag(TagLeft, RowTop + Px(RowPadY), TagText, TagColor);
    end;
    FC.Font := Font;
    FC.Brush.Style := bsClear;
    if It.Done then
      FC.Font.Color := FDim
    else
      FC.Font.Color := FText;
    FC.TextOut(X, RowTop + Px(RowPadY), FitTextLeft(FC, Title, TagLeft - Px(Gap) - X));
    Inc(X, FC.TextWidth(Title) + Px(Gap));
    FC.Font.Color := FDim;
    if X < TagLeft - 3 * Px(Gap) then
      FC.TextOut(X, RowTop + Px(RowPadY), FitTextLeft(FC, Detail, TagLeft - Px(Gap) - X));
    Inc(RowTop, RowH);
  end;
  Inc(Y, H + Px(CardGap));
end;

{ Maintenance: what it does, Scan with the progress after it or what was
  found, the cards, the repositories with nothing to do, and Run. }
procedure TGittanBatchPage.PaintMaint(var Y: integer; ALeft, ARight: integer);
var
  TextH, n, Repos, i, Picked, Cards: integer;
  Detail, ButtonText, Nothing: string;
  R: TRect;
begin
  n := MaintCount(Repos);
  Detail := '';
  if FMaintScanned and not FMaintScanning and (n > 0) then
    if n = 1 then
      Detail := rsTaskOne
    else if Repos = 1 then
      Detail := Format(rsTasksOneRepo, [n])
    else
      Detail := Format(rsTasksManyRepos, [n, Repos]);
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  PaintText(Y, rsMaintAbout, FDim, ALeft, ARight);
  Inc(Y, Px(Gap));

  i := ChosenCount;
  if i = 0 then
    ButtonText := rsScanNone
  else if i = 1 then
    ButtonText := rsScanOne
  else
    ButtonText := Format(rsScanMany, [i]);
  Inc(Y, Px(PillPadY));
  R := PaintPill(ALeft, Y, ButtonText, MaintScanLink, True, (i > 0) and not Busy);
  FC.Font.Color := FDim;
  if FMaintScanning then
    FC.TextOut(R.Right + Px(Gap), Y, Format(rsScanning, [Min(FMaintDone + 1, FMaintTotal),
      FMaintTotal]))
  else if Detail <> '' then
    FC.TextOut(R.Right + Px(Gap), Y, Detail);
  Inc(Y, TextH + Px(PillPadY) + Px(Gap));

  Nothing := '';
  Cards := 0;
  for i := 0 to FMaintDone - 1 do
    if (Length(FMaint[i].Items) = 0) and (FMaint[i].Error = '') and
      (FMaint[i].RemoteError = '') then
    begin
      if Nothing <> '' then
        Nothing := Nothing + ', ';
      Nothing := Nothing + FMaint[i].Caption;
    end
    else
    begin
      PaintMaintCard(Y, i, ALeft, ARight);
      Inc(Cards);
    end;
  if (Cards = 0) and (FMaintDone > 0) and not FMaintScanning then
  begin
    PaintText(Y, rsAllTidy, FDim, ALeft, ARight);
    Inc(Y, Px(Gap));
  end
  else if Nothing <> '' then
  begin
    PaintText(Y, Format(rsNothingToDo, [Nothing]), FDim, ALeft, ARight);
    Inc(Y, Px(Gap));
  end;

  if n > 0 then
  begin
    Picked := Length(PickedMaintRefs);
    if FMaintRunning then
      ButtonText := rsRunning
    else if Picked = 0 then
      ButtonText := rsRunNone
    else if Picked = 1 then
      ButtonText := rsRunOne
    else
      ButtonText := Format(rsRunMany, [Picked]);
    Inc(Y, Px(PillPadY));
    PaintPill(ALeft, Y, ButtonText, MaintRunLink, True, (Picked > 0) and not Busy);
    Inc(Y, TextH + Px(PillPadY));
  end;
end;

{ The folded list: the picked ones by name, as many as fit, then how
  many more; the line unfolds the list too. }
{ ---------------------------------------------------------------------------
  The extensions' operations
  --------------------------------------------------------------------------- }

procedure TGittanBatchPage.SetExtOps(const AOps: TGittanBatchExtOps);
var
  Shown: string;
  i, j, n: integer;
  Kept: array of TGittanBatchExtRun;
begin
  Shown := '';
  if (FOperation >= BatchOperationCount) and (FOperation - BatchOperationCount <= High(FExtOps)) then
    Shown := FExtOps[FOperation - BatchOperationCount].Key;
  FExtOps := Copy(AOps);
  { The runs of the operations still there. }
  Kept := nil;
  n := 0;
  for i := 0 to High(FExtRuns) do
    for j := 0 to High(FExtOps) do
      if FExtOps[j].Key = FExtRuns[i].Key then
      begin
        SetLength(Kept, n + 1);
        Kept[n] := FExtRuns[i];
        Inc(n);
        Break;
      end;
  FExtRuns := Kept;
  { The one shown, where it is now; Gittan's own stay where they are.
    One asked for before it came is shown once it is here. }
  if FOperation >= BatchOperationCount then
  begin
    FOperation := BatchOverview;
    for i := 0 to High(FExtOps) do
      if FExtOps[i].Key = Shown then
        FOperation := BatchOperationCount + i;
  end;
  if FWantedKey <> '' then
    for i := 0 to High(FExtOps) do
      if FExtOps[i].Key = FWantedKey then
      begin
        FOperation := BatchOperationCount + i;
        FWantedKey := '';
        Break;
      end;
  FHot := -1;
  Layout;
  Invalidate;
end;

function TGittanBatchPage.ShownExtOp(out AOp: TGittanBatchExtOp): boolean;
begin
  AOp := Default(TGittanBatchExtOp);
  Result := (FOperation >= BatchOperationCount) and
    (FOperation - BatchOperationCount <= High(FExtOps));
  if Result then
    AOp := FExtOps[FOperation - BatchOperationCount];
end;

function TGittanBatchPage.ExtRunIndex(const AKey: string): integer;
begin
  for Result := 0 to High(FExtRuns) do
    if FExtRuns[Result].Key = AKey then
      Exit;
  Result := -1;
end;

procedure TGittanBatchPage.StartExtRun(const AKey: string; const APaths, ACaptions: TStringArray);
var
  i: integer;
begin
  i := ExtRunIndex(AKey);
  if i < 0 then
  begin
    i := Length(FExtRuns);
    SetLength(FExtRuns, i + 1);
  end;
  FExtRuns[i] := Default(TGittanBatchExtRun);
  FExtRuns[i].Key := AKey;
  FExtRuns[i].Paths := Copy(APaths);
  FExtRuns[i].Captions := Copy(ACaptions);
  SetLength(FExtRuns[i].Results, Length(APaths));
  SetLength(FExtRuns[i].Skipped, Length(APaths));
  FExtRuns[i].Total := Length(APaths);
  FExtRuns[i].Running := True;
  Layout;
  Invalidate;
end;

procedure TGittanBatchPage.SetExtResult(const AKey: string; AIndex: integer;
  const AResult: TExtBatchResult; ASkipped: boolean);
var
  i: integer;
begin
  i := ExtRunIndex(AKey);
  if (i < 0) or (AIndex < 0) or (AIndex >= FExtRuns[i].Total) then
    Exit;
  FExtRuns[i].Results[AIndex] := AResult;
  FExtRuns[i].Skipped[AIndex] := ASkipped;
  FExtRuns[i].Done := AIndex + 1;
  Layout;
  Invalidate;
end;

procedure TGittanBatchPage.FinishExtRun(const AKey, AError: string);
var
  i: integer;
begin
  i := ExtRunIndex(AKey);
  if i < 0 then
    Exit;
  FExtRuns[i].Running := False;
  FExtRuns[i].Error := AError;
  Layout;
  Invalidate;
end;

function TGittanBatchPage.ExtRunning(const AKey: string): boolean;
var
  i: integer;
begin
  i := ExtRunIndex(AKey);
  Result := (i >= 0) and FExtRuns[i].Running;
end;

{ A repository's card for what the operation said of it: the head as
  the overview's, with its name, its path and Open; the text a line
  each in the severity's color; the link the extension gave. }
procedure TGittanBatchPage.PaintExtCard(var Y: integer; ARun, AIndex, ALeft, ARight: integer);
var
  Res: TExtBatchResult;
  Lines: TStringArray;
  TextH, H, X, RowTop, i, Inner, OpenW, Room: integer;
  R, HeadR: TRect;
  Style: TTextStyle;
  Hot: boolean;
  LineColor: TColor;
begin
  Res := FExtRuns[ARun].Results[AIndex];
  Lines := Res.Text.Split([#10]);
  case Res.Severity of
    esWarn: LineColor := FWarn;
    esError: LineColor := FErrorColor;
    esOk: LineColor := FOk;
    else
      LineColor := FText;
  end;
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  Inner := ARight - ALeft - 2 * Px(CardPadX);
  H := 2 * Px(CardPadY) + TextH;
  for i := 0 to High(Lines) do
    Inc(H, Px(4) + WrappedHeight(Lines[i], Inner));
  if Res.Url <> '' then
    Inc(H, Px(4) + TextH);
  R := Rect(ALeft, Y, ARight, Y + H);
  HeadR := Rect(ALeft, Y, ARight, Y + Px(CardPadY) + TextH + Px(4));
  AddLink(HeadR, ExtOpenLink + IntToStr(ARun) + ':' + IntToStr(AIndex));
  Hot := FHot = High(FLinkRects);
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FCard;
  FC.RoundRect(R, Px(CardRadius), Px(CardRadius));
  if Hot then
  begin
    FC.Brush.Color := FHover;
    FC.RoundRect(HeadR, Px(CardRadius), Px(CardRadius));
  end;
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;

  RowTop := Y + Px(CardPadY);
  FC.Font := Font;
  OpenW := FC.TextWidth(rsOpen);
  if Hot then
    FC.Font.Color := FLink
  else
    FC.Font.Color := FDim;
  FC.TextOut(ARight - Px(CardPadX) - OpenW, RowTop, rsOpen);
  Room := ARight - Px(CardPadX) - OpenW - Px(Gap);
  X := ALeft + Px(CardPadX);
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  FC.TextOut(X, RowTop, FitTextLeft(FC, FExtRuns[ARun].Captions[AIndex], Room - X));
  Inc(X, FC.TextWidth(FExtRuns[ARun].Captions[AIndex]) + Px(Gap));
  FC.Font.Style := [];
  FC.Font.Color := FDim;
  if X < Room - 3 * Px(Gap) then
    FC.TextOut(X, RowTop, FitTextLeft(FC, ShortPath(FExtRuns[ARun].Paths[AIndex]), Room - X));
  Inc(RowTop, TextH);

  Style := FC.TextStyle;
  Style.Wordbreak := True;
  Style.SingleLine := False;
  Style.Alignment := taLeftJustify;
  Style.Layout := tlTop;
  for i := 0 to High(Lines) do
  begin
    Inc(RowTop, Px(4));
    FC.Font.Color := LineColor;
    H := WrappedHeight(Lines[i], Inner);
    R := Rect(ALeft + Px(CardPadX), RowTop, ALeft + Px(CardPadX) + Inner, RowTop + H);
    FC.TextRect(R, R.Left, R.Top, Lines[i], Style);
    Inc(RowTop, H);
  end;
  if Res.Url <> '' then
  begin
    Inc(RowTop, Px(4));
    R := Rect(ALeft + Px(CardPadX), RowTop, ALeft + Px(CardPadX) + FC.TextWidth(rsExtOpenLink),
      RowTop + TextH);
    AddLink(R, ExtUrlLink + IntToStr(ARun) + ':' + IntToStr(AIndex));
    FC.Font.Color := FLink;
    if FHot = High(FLinkRects) then
      FC.Font.Style := [fsUnderline];
    FC.TextOut(R.Left, RowTop, rsExtOpenLink);
    FC.Font.Style := [];
    Inc(RowTop, TextH);
  end;
  Y := RowTop + Px(CardPadY) + Px(CardGap);
end;

{ An extension's operation: what it is for, Run with the progress after
  it or how many it had something to say of, the cards, then the
  repositories it said nothing of and those it does not run for. }
procedure TGittanBatchPage.PaintExtOp(var Y: integer; ALeft, ARight: integer);
var
  Op: TGittanBatchExtOp;
  Run, i, n, Said, Asked, TextH: integer;
  ButtonText, Detail, Quiet, LeftOut: string;
  Running, Other: boolean;
  R: TRect;
begin
  if not ShownExtOp(Op) then
    Exit;
  Run := ExtRunIndex(Op.Key);
  Running := (Run >= 0) and FExtRuns[Run].Running;
  if Op.Note <> '' then
    PaintText(Y, Op.Note, FDim, ALeft, ARight);
  if Op.Source <> '' then
  begin
    { Which extension it is from, after the piece its pill has. }
    FC.Font := Font;
    TextH := FC.TextHeight('Xg');
    Inc(Y, Px(4));
    PaintPuzzle(FC, ALeft, Y + (TextH - Px(PuzzleSide)) div 2, Px(PuzzleSide), FDim);
    FC.Brush.Style := bsClear;
    FC.Font.Color := FDim;
    FC.TextOut(ALeft + Px(PuzzleSide) + Px(PuzzleGap), Y, Op.Source);
    Inc(Y, TextH);
  end;
  if (Op.Note <> '') or (Op.Source <> '') then
    Inc(Y, Px(Gap));
  Said := 0;
  Asked := 0;
  if Run >= 0 then
    for i := 0 to FExtRuns[Run].Done - 1 do
      if not FExtRuns[Run].Skipped[i] then
      begin
        Inc(Asked);
        if FExtRuns[Run].Results[i].Said then
          Inc(Said);
      end;
  Detail := '';
  if (Run >= 0) and not Running and (Asked > 0) then
    if (Said = 0) and (Asked = 1) then
      Detail := rsExtSaidNoneOne
    else if Said = 0 then
      Detail := Format(rsExtSaidNone, [Asked])
    else if Said = 1 then
      Detail := Format(rsExtSaidOne, [Asked])
    else
      Detail := Format(rsExtSaidMany, [Said, Asked]);

  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  n := ChosenCount;
  if n = 0 then
    ButtonText := rsExtRunNone
  else if n = 1 then
    ButtonText := rsExtRunOne
  else
    ButtonText := Format(rsExtRunMany, [n]);
  Inc(Y, Px(PillPadY));
  { One run at a time (the forge view's BatchExtRun): another's running
    keeps this one's pill off too, and says why. }
  Other := False;
  for i := 0 to High(FExtRuns) do
    if (i <> Run) and FExtRuns[i].Running then
      Other := True;
  R := PaintPill(ALeft, Y, ButtonText, ExtRunLink, False, (n > 0) and not Running and not Other);
  FC.Font.Color := FDim;
  if Running then
    FC.TextOut(R.Right + Px(Gap), Y, Format(rsExtRunning,
      [Min(FExtRuns[Run].Done + 1, FExtRuns[Run].Total), FExtRuns[Run].Total]))
  else if Other then
    FC.TextOut(R.Right + Px(Gap), Y, rsExtOtherRunning)
  else if Detail <> '' then
    FC.TextOut(R.Right + Px(Gap), Y, Detail);
  Inc(Y, TextH + Px(PillPadY) + Px(Gap));
  if Run < 0 then
    Exit;

  if FExtRuns[Run].Error <> '' then
  begin
    PaintText(Y, FExtRuns[Run].Error, FErrorColor, ALeft, ARight);
    Inc(Y, Px(Gap));
  end;
  Quiet := '';
  LeftOut := '';
  for i := 0 to FExtRuns[Run].Done - 1 do
    if FExtRuns[Run].Skipped[i] then
    begin
      if LeftOut <> '' then
        LeftOut := LeftOut + ', ';
      LeftOut := LeftOut + FExtRuns[Run].Captions[i];
    end
    else if FExtRuns[Run].Results[i].Said then
      PaintExtCard(Y, Run, i, ALeft, ARight)
    else
    begin
      if Quiet <> '' then
        Quiet := Quiet + ', ';
      Quiet := Quiet + FExtRuns[Run].Captions[i];
    end;
  if (Quiet <> '') and (Said > 0) then
  begin
    PaintText(Y, Format(rsExtNothingIn, [Quiet]), FDim, ALeft, ARight);
    Inc(Y, Px(Gap));
  end;
  if LeftOut <> '' then
  begin
    PaintText(Y, Format(rsExtLeftOut, [LeftOut]), FDim, ALeft, ARight);
    Inc(Y, Px(Gap));
  end;
end;

procedure TGittanBatchPage.PaintPicked(var Y: integer; ALeft, ARight: integer);
var
  Paths, Captions: TStringArray;
  Line, Next, More: string;
  i, TextH: integer;
  R: TRect;
begin
  ChosenRepos(Paths, Captions);
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  Inc(Y, Px(RowPadY));
  if Length(Captions) = 0 then
    Line := rsNonePicked
  else
  begin
    Line := Captions[0];
    for i := 1 to High(Captions) do
    begin
      Next := Line + ', ' + Captions[i];
      More := '';
      if i < High(Captions) then
        More := Format(rsMorePicked, [High(Captions) - i]);
      if FC.TextWidth(Next + More) > ARight - ALeft then
      begin
        Line := Line + Format(rsMorePicked, [Length(Captions) - i]);
        Break;
      end;
      Line := Next;
    end;
  end;
  R := Rect(ALeft, Y - Px(RowPadY), ARight, Y + TextH + Px(RowPadY));
  AddLink(R, UnfoldLink);
  if FHot = High(FLinkRects) then
    FC.Font.Color := FText
  else
    FC.Font.Color := FDim;
  FC.Brush.Style := bsClear;
  FC.TextOut(ALeft, Y, FitTextLeft(FC, Line, ARight - ALeft));
  Inc(Y, TextH + Px(RowPadY));
end;

{ The operations as pills, the one shown in the link color, over a
  divider. }
procedure TGittanBatchPage.PaintOperations(var Y: integer; ALeft, ARight: integer);
var
  i, X, TextH: integer;
  Caption_: string;
begin
  Inc(Y, Px(Pad));
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  Inc(Y, Px(PillPadY));
  X := ALeft;
  for i := 0 to BatchOperationCount + High(FExtOps) do
  begin
    case i of
      BatchOverview: Caption_ := rsStatusHeading;
      BatchGone: Caption_ := rsOpGone;
      BatchIdentity: Caption_ := rsOpIdentity;
      BatchMaintenance: Caption_ := rsOpMaint;
      else
        Caption_ := FExtOps[i - BatchOperationCount].Title;
    end;
    { The extensions' pills may not fit on one row. }
    if (X > ALeft) and (X + PillWidth(Caption_, i >= BatchOperationCount) > ARight) then
    begin
      X := ALeft;
      Inc(Y, TextH + 2 * Px(PillPadY) + Px(6));
    end;
    X := PaintPill(X, Y, Caption_, OperationLink + IntToStr(i), i = FOperation, True,
      i >= BatchOperationCount).Right + Px(6);
  end;
  Inc(Y, TextH + Px(PillPadY) + Px(Gap) div 2);
  FC.Pen.Style := psSolid;
  FC.Pen.Color := FLine;
  FC.Line(ALeft, Y, ARight, Y);
  Inc(Y, Px(Gap));
end;

procedure TGittanBatchPage.SetOperation(AValue: integer);
begin
  if (AValue < 0) or (AValue >= BatchOperationCount + Length(FExtOps)) then
    AValue := BatchOverview;
  if FOperation = AValue then
    Exit;
  FOperation := AValue;
  FHot := -1;
  Layout;
  Invalidate;
end;

function TGittanBatchPage.GetOperationKey: string;
begin
  if FOperation < BatchOperationCount then
    Result := BatchOperationKeys[FOperation]
  else if FOperation - BatchOperationCount <= High(FExtOps) then
    Result := FExtOps[FOperation - BatchOperationCount].Key
  else
    Result := BatchOperationKeys[BatchOverview];
end;

procedure TGittanBatchPage.SetOperationKey(const AKey: string);
var
  i: integer;
begin
  FWantedKey := '';
  for i := 0 to High(BatchOperationKeys) do
    if BatchOperationKeys[i] = AKey then
    begin
      SetOperation(i);
      Exit;
    end;
  for i := 0 to High(FExtOps) do
    if FExtOps[i].Key = AKey then
    begin
      SetOperation(BatchOperationCount + i);
      Exit;
    end;
  SetOperation(BatchOverview);
  FWantedKey := AKey;
end;

procedure TGittanBatchPage.PaintContent;
var
  Y, L, R, TextH, TitleH: integer;
begin
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FBack;
  FC.FillRect(Rect(0, 0, Width, Height));
  FLinkRects := nil;
  FLinkUrls := nil;
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  L := Max(Px(Pad), (Width - Px(MaxContentWidth)) div 2);
  R := Width - L;
  Y := Px(Pad);

  { The head: the title, and what the tab is for under it. }
  FC.Font.Size := TitleFontSize;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  TitleH := FC.TextHeight('Xg');
  FC.TextOut(L, Y, rsTitle);
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  FC.Font.Color := FDim;
  FC.TextOut(L, Y + TitleH + 2, FitTextLeft(FC, rsSubtitle, R - L));
  Inc(Y, TitleH + 2 + TextH);

  PaintNotice(Y, L, R);
  PaintHeading(Y, rsReposHeading, Format(rsPickedOf, [ChosenCount, RepoCount]), L, R,
    Length(FRows) > 0);
  if FReposOpen or (Length(FRows) = 0) then
    PaintRows(Y, L, R)
  else
    PaintPicked(Y, L, R);
  PaintOperations(Y, L, R);
  case FOperation of
    BatchGone: PaintGone(Y, L, R);
    BatchIdentity: PaintIdentity(Y, L, R);
    BatchMaintenance: PaintMaint(Y, L, R);
    else
      if FOperation >= BatchOperationCount then
        PaintExtOp(Y, L, R)
      else
        PaintStatus(Y, L, R);
  end;

  { Layout sets the height from this. }
  FContentHeight := Y + Px(Pad);
end;

procedure TGittanBatchPage.SetNotice(const AText, ALink: string);
begin
  if (FNotice = AText) and (FNoticeLink = ALink) then
    Exit;
  FNotice := AText;
  FNoticeLink := ALink;
  FHot := -1;
  Layout;
  Invalidate;
end;

{ The note in a card with a stripe of the link color at its left, the
  text wrapped and the link under it. }
procedure TGittanBatchPage.PaintNotice(var Y: integer; ALeft, ARight: integer);
var
  R, LinkR: TRect;
  TextH, H, TextW: integer;
begin
  if FNotice = '' then
    Exit;
  Inc(Y, Px(Pad));
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  TextW := ARight - ALeft - 2 * Px(14);
  H := 2 * Px(10) + WrappedHeight(FNotice, TextW);
  if FNoticeLink <> '' then
    Inc(H, TextH + Px(4));
  R := Rect(ALeft, Y, ARight, Y + H);
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FCard;
  FC.RoundRect(R, Px(12), Px(12));
  FC.Brush.Color := FLink;
  FC.FillRect(Rect(R.Left, R.Top + Px(6), R.Left + Px(3), R.Bottom - Px(6)));
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;
  Y := R.Top + Px(10);
  PaintText(Y, FNotice, FText, R.Left + Px(14), R.Right - Px(14));
  if FNoticeLink <> '' then
  begin
    Inc(Y, Px(4));
    FC.Font := Font;
    LinkR := Rect(R.Left + Px(14), Y, R.Left + Px(14) + FC.TextWidth(FNoticeLink), Y + TextH);
    AddLink(LinkR, NoticeLink);
    FC.Font.Color := FLink;
    if FHot = High(FLinkRects) then
      FC.Font.Style := [fsUnderline];
    FC.TextOut(LinkR.Left, LinkR.Top, FNoticeLink);
    FC.Font := Font;
  end;
  Y := R.Bottom;
end;

procedure TGittanBatchPage.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  i, p, a, b: integer;
  Url, Rest: string;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  i := LinkAt(X, Y);
  if i < 0 then
    Exit;
  Url := FLinkUrls[i];
  if Url = NoticeLink then
  begin
    if Assigned(FOnNotice) then
      FOnNotice(Self);
  end
  else if Copy(Url, 1, Length(RowLink)) = RowLink then
    ToggleRow(StrToIntDef(Copy(Url, Length(RowLink) + 1, MaxInt), -1))
  else if Copy(Url, 1, Length(GoneLink)) = GoneLink then
    ToggleGone(StrToIntDef(Copy(Url, Length(GoneLink) + 1, MaxInt), -1))
  else if Copy(Url, 1, Length(BranchLink)) = BranchLink then
  begin
    Rest := Copy(Url, Length(BranchLink) + 1, MaxInt);
    p := Pos(':', Rest);
    a := StrToIntDef(Copy(Rest, 1, p - 1), -1);
    b := StrToIntDef(Copy(Rest, p + 1, MaxInt), -1);
    ToggleBranch(a, b);
  end
  else if Url = AllLink then
  begin
    for i := 0 to High(FRows) do
      if not FRows[i].IsFolder then
        SetChosenPath(FRows[i].Path, True);
    ChosenChanged;
  end
  else if Url = NoneLink then
  begin
    FChosen.Clear;
    ChosenChanged;
  end
  else if Url = ScanLink then
  begin
    if Assigned(FOnScan) then
      FOnScan(Self);
  end
  else if Url = FoldLink then
  begin
    FReposOpen := False;
    FHot := -1;
    Layout;
    Invalidate;
  end
  else if Url = UnfoldLink then
  begin
    FReposOpen := True;
    FHot := -1;
    Layout;
    Invalidate;
  end
  else if Copy(Url, 1, Length(OperationLink)) = OperationLink then
  begin
    a := StrToIntDef(Copy(Url, Length(OperationLink) + 1, MaxInt), -1);
    if (a >= 0) and (a < BatchOperationCount + Length(FExtOps)) and (a <> FOperation) then
    begin
      FWantedKey := '';
      SetOperation(a);
      if Assigned(FOnOperationChange) then
        FOnOperationChange(Self);
    end;
  end
  else if Url = CheckLink then
  begin
    if Assigned(FOnCheck) then
      FOnCheck(Self);
  end
  else if Url = MaintScanLink then
  begin
    if Assigned(FOnMaintScan) then
      FOnMaintScan(Self);
  end
  else if Url = MaintRunLink then
  begin
    if Assigned(FOnMaintRun) then
      FOnMaintRun(Self);
  end
  else if Copy(Url, 1, Length(MaintLink)) = MaintLink then
  begin
    Rest := Copy(Url, Length(MaintLink) + 1, MaxInt);
    p := Pos(':', Rest);
    a := StrToIntDef(Copy(Rest, 1, p - 1), -1);
    b := StrToIntDef(Copy(Rest, p + 1, MaxInt), -1);
    ToggleMaint(a, b);
  end
  else if Copy(Url, 1, Length(IdOpenLink)) = IdOpenLink then
  begin
    a := StrToIntDef(Copy(Url, Length(IdOpenLink) + 1, MaxInt), -1);
    if (a >= 0) and (a < FIdsDone) and Assigned(FOnOpen) then
      FOnOpen(Self, FIds[a].Path);
  end
  else if Copy(Url, 1, Length(OpenLink)) = OpenLink then
  begin
    a := StrToIntDef(Copy(Url, Length(OpenLink) + 1, MaxInt), -1);
    if (a >= 0) and (a < FStatusDone) and Assigned(FOnOpen) then
      FOnOpen(Self, FStatus[a].Path);
  end
  else if Url = DeleteLink then
  begin
    if Assigned(FOnDelete) then
      FOnDelete(Self);
  end
  else if Url = ExtRunLink then
  begin
    if Assigned(FOnExtRun) then
      FOnExtRun(Self);
  end
  else if (Copy(Url, 1, Length(ExtOpenLink)) = ExtOpenLink) or
    (Copy(Url, 1, Length(ExtUrlLink)) = ExtUrlLink) then
  begin
    Rest := Copy(Url, Length(ExtOpenLink) + 1, MaxInt);
    p := Pos(':', Rest);
    a := StrToIntDef(Copy(Rest, 1, p - 1), -1);
    b := StrToIntDef(Copy(Rest, p + 1, MaxInt), -1);
    if (a < 0) or (a > High(FExtRuns)) or (b < 0) or (b >= FExtRuns[a].Done) then
      Exit;
    if Copy(Url, 1, Length(ExtUrlLink)) = ExtUrlLink then
    begin
      if Assigned(FOnOpenUrl) then
        FOnOpenUrl(Self, FExtRuns[a].Results[b].Url);
    end
    else if Assigned(FOnOpen) then
      FOnOpen(Self, FExtRuns[a].Paths[b]);
  end;
end;

end.
