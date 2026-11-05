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

  The list folds to one line naming the picked ones, with Change to
  unfold it (and Done at its heading to fold it again); it starts
  unfolded while nothing is picked. Under it the operations, as a row
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

  It paints itself in the forge view's palette (ForgePalette) and sizes
  its height to its content so it can sit in the view's TScrollBox as
  the forge page does: Layout paints the content on a measuring canvas
  to know the height before the control is shown. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, gittan.batch;

const
  {** The operations, as Operation counts them. }
  BatchOverview = 0;
  BatchGone = 1;
  BatchOperationCount = 2;

type
  {** A repository to open, by its root. }
  TGittanBatchOpenEvent = procedure(Sender: TObject; const APath: string) of object;

  { TGittanBatchPage }

  TGittanBatchPage = class(TCustomControl)
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
    { Whether the list is unfolded, and the operation shown. }
    FReposOpen: boolean;
    FOperation: integer;
    FOnOperationChange: TNotifyEvent;
    FOnCheck: TNotifyEvent;
    FOnOpen: TGittanBatchOpenEvent;
    { The branches picked to delete, as PickKey. }
    FPicked: TStringList;
    FBack, FText, FDim, FHover, FLine, FLink, FOk, FWarn, FErrorColor, FCard: TColor;
    FLinkRects: array of TRect;
    FLinkUrls: array of string;
    FHot: integer;
    FContentHeight: integer;
    { The canvas the content is painted on: the control's in Paint, a
      measuring one in Layout. }
    FC: TCanvas;
    FOnChosenChange, FOnScan, FOnDelete: TNotifyEvent;
    function LinkAt(X, Y: integer): integer;
    procedure SetHot(AValue: integer);
    procedure AddLink(const ARect: TRect; const AUrl: string);
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
    function PillWidth(const AText: string): integer;
    function PaintPill(ALeft, ATop: integer; const AText, ALink: string;
      APrimary, AEnabled: boolean): TRect;
    function PaintTag(ARight, ATop: integer; const AText: string; AColor: TColor): integer;
    procedure PaintHeading(var Y: integer; const ATitle, ADetail: string; ALeft, ARight: integer;
      AChips: boolean);
    procedure PaintText(var Y: integer; const AText: string; AColor: TColor;
      ALeft, ARight: integer);
    procedure PaintRows(var Y: integer; ALeft, ARight: integer);
    procedure PaintPicked(var Y: integer; ALeft, ARight: integer);
    procedure PaintOperations(var Y: integer; ALeft, ARight: integer);
    procedure SetOperation(AValue: integer);
    procedure PaintGoneCard(var Y: integer; AIndex, ALeft, ARight: integer);
    procedure PaintGone(var Y: integer; ALeft, ARight: integer);
    function WrappedHeight(const AText: string; AWidth: integer): integer;
    procedure PaintStatusCard(var Y: integer; AIndex, ALeft, ARight: integer);
    procedure PaintStatus(var Y: integer; ALeft, ARight: integer);
    procedure PaintContent;
    procedure Layout;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
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
    {** Whether a scan or a deletion runs. }
    function Busy: boolean;
    {** An overview of ATotal repositories starts: what the last one read
      goes. }
    procedure StartCheck(ATotal: integer);
    {** What the overview read: the first ADone of ARepos (the others may
      still be written), and whether it still runs. }
    procedure SetStatus(const ARepos: TGittanRepoStatuses; ADone: integer; ARunning: boolean);
    {** Whether the overview runs. }
    property Checking: boolean read FChecking;
    {** The operation shown, BatchOverview (the default) or BatchGone. }
    property Operation: integer read FOperation write SetOperation;
    {** A click on an operation's pill changed Operation. }
    property OnOperationChange: TNotifyEvent read FOnOperationChange write FOnOperationChange;
    {** The palette of the dark or the light appearance. }
    procedure SetTheme(ADark: boolean);
    {** Makes the control at least AMin high, and no higher than its
      content needs beyond that. }
    procedure FitHeight(AMin: integer);
    {** The roots picked. }
    property Chosen: TStringList read FChosen;
    {** A check box, All or None changed Chosen. }
    property OnChosenChange: TNotifyEvent read FOnChosenChange write FOnChosenChange;
    {** A click on Scan: the owner runs the scan. }
    property OnScan: TNotifyEvent read FOnScan write FOnScan;
    {** A click on Delete: the owner asks and deletes PickedRefs. }
    property OnDelete: TNotifyEvent read FOnDelete write FOnDelete;
    {** A click on Check: the owner reads the picked repositories. }
    property OnCheck: TNotifyEvent read FOnCheck write FOnCheck;
    {** A click on a card's head in the overview: open that repository. }
    property OnOpen: TGittanBatchOpenEvent read FOnOpen write FOnOpen;
  end;

implementation

uses
  Math, LCLIntf, LCLType, gittan.forgepage, gittan.textfit, gittan.theme;

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
  rsChangeChip = 'Change';
  rsDoneChip = 'Done';
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
  PillPadX = 10;
  PillPadY = 3;
  TagPadX = 6;
  TagPadY = 2;
  TagRadius = 6;

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
  ControlStyle := ControlStyle + [csOpaque];
  FHot := -1;
  Align := alTop;
  FChosen := TStringList.Create;
  FChosen.CaseSensitive := True;
  FPicked := TStringList.Create;
  FPicked.CaseSensitive := True;
  FPicked.Sorted := True;
  FPicked.Duplicates := dupIgnore;
  SetTheme(False);
end;

destructor TGittanBatchPage.Destroy;
begin
  FPicked.Free;
  FChosen.Free;
  inherited Destroy;
end;

procedure TGittanBatchPage.SetTheme(ADark: boolean);
var
  P: TGittanForgePalette;
begin
  P := ForgePalette(ADark);
  FBack := P.Back;
  FText := P.Text;
  FDim := P.Dim;
  FHover := P.Hover;
  FLine := P.Line;
  FLink := P.Link;
  FOk := P.Ok;
  FWarn := P.Warn;
  FErrorColor := P.Error;
  FCard := P.Card;
  Color := FBack;
  Invalidate;
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
  Result := FScanning or FDeleting;
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

procedure TGittanBatchPage.AddLink(const ARect: TRect; const AUrl: string);
begin
  SetLength(FLinkRects, Length(FLinkRects) + 1);
  SetLength(FLinkUrls, Length(FLinkUrls) + 1);
  FLinkRects[High(FLinkRects)] := ARect;
  FLinkUrls[High(FLinkUrls)] := AUrl;
end;

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

function TGittanBatchPage.PillWidth(const AText: string): integer;
begin
  FC.Font := Font;
  Result := FC.TextWidth(AText) + 2 * Px(PillPadX);
end;

{ A button as a pill, its text at ALeft, ATop: APrimary in the link color,
  else outlined; a link only while AEnabled, dim otherwise. Gives its
  rectangle. }
function TGittanBatchPage.PaintPill(ALeft, ATop: integer; const AText, ALink: string;
  APrimary, AEnabled: boolean): TRect;
var
  TextH: integer;
  Hot: boolean;
begin
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  Result := Rect(ALeft, ATop - Px(PillPadY), ALeft + PillWidth(AText),
    ATop + TextH + Px(PillPadY));
  Hot := False;
  if AEnabled then
  begin
    AddLink(Result, ALink);
    Hot := FHot = High(FLinkRects);
  end;
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsSolid;
  if not AEnabled then
  begin
    FC.Pen.Color := MixColor(FBack, FLine, 0.6);
    FC.Brush.Color := FBack;
    FC.Font.Color := MixColor(FBack, FDim, 0.7);
  end
  else if APrimary then
  begin
    FC.Pen.Color := FLink;
    if Hot then
      FC.Brush.Color := MixColor(FBack, FLink, 0.3)
    else
      FC.Brush.Color := MixColor(FBack, FLink, 0.18);
    FC.Font.Color := FLink;
  end
  else
  begin
    FC.Pen.Color := FLine;
    if Hot then
    begin
      FC.Brush.Color := FHover;
      FC.Font.Color := FText;
    end
    else
    begin
      FC.Brush.Color := FBack;
      FC.Font.Color := FDim;
    end;
  end;
  FC.RoundRect(Result, Result.Height, Result.Height);
  FC.Brush.Style := bsClear;
  FC.TextOut(Result.Left + Px(PillPadX), ATop, AText);
  FC.Font := Font;
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
  forge page's; with AChips the list's pills at the right of the title's
  line: All, None and Done while it is unfolded, else Change. }
procedure TGittanBatchPage.PaintHeading(var Y: integer; const ATitle, ADetail: string;
  ALeft, ARight: integer; AChips: boolean);
var
  TextH, X: integer;
begin
  Inc(Y, Px(Pad));
  FC.Font := Font;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FDim;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  FC.TextOut(ALeft, Y, ATitle);
  X := ALeft + FC.TextWidth(ATitle) + Px(Gap) div 2;
  FC.Font.Style := [];
  if ADetail <> '' then
    FC.TextOut(X, Y, ADetail);
  if AChips and FReposOpen then
  begin
    X := ARight - PillWidth(rsDoneChip);
    PaintPill(X, Y, rsDoneChip, FoldLink, True, True);
    X := X - Px(6) - PillWidth(rsNoneChip);
    PaintPill(X, Y, rsNoneChip, NoneLink, False, True);
    X := X - Px(6) - PillWidth(rsAllChip);
    PaintPill(X, Y, rsAllChip, AllLink, False, True);
  end
  else if AChips then
    PaintPill(ARight - PillWidth(rsChangeChip), Y, rsChangeChip, UnfoldLink, False, True);
  Inc(Y, TextH + Px(Gap) div 2);
  FC.Pen.Style := psSolid;
  FC.Pen.Color := FLine;
  FC.Line(ALeft, Y, ARight, Y);
  Inc(Y, Px(Gap) div 2);
end;

{ A paragraph in AColor, wrapped between ALeft and ARight. }
procedure TGittanBatchPage.PaintText(var Y: integer; const AText: string; AColor: TColor;
  ALeft, ARight: integer);
var
  R: TRect;
  Style: TTextStyle;
begin
  FC.Font := Font;
  FC.Font.Color := AColor;
  FC.Brush.Style := bsClear;
  R := Rect(ALeft, Y, ARight, Y);
  DrawText(FC.Handle, PChar(AText), Length(AText), R, DT_CALCRECT or DT_WORDBREAK);
  R.Right := ARight;
  Style := FC.TextStyle;
  Style.Wordbreak := True;
  Style.SingleLine := False;
  Style.Alignment := taLeftJustify;
  Style.Layout := tlTop;
  FC.TextRect(R, R.Left, R.Top, AText, Style);
  Y := R.Bottom;
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

{ The height of AText wrapped in AWidth, in the canvas's font. }
function TGittanBatchPage.WrappedHeight(const AText: string; AWidth: integer): integer;
var
  R: TRect;
begin
  R := Rect(0, 0, AWidth, 0);
  DrawText(FC.Handle, PChar(AText), Length(AText), R, DT_CALCRECT or DT_WORDBREAK);
  Result := Max(R.Bottom, FC.TextHeight('Xg'));
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
  TextH, i, Cards: integer;
  Detail, ButtonText, Clean: string;
  R: TRect;
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
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  PaintText(Y, rsStatusAbout, FDim, ALeft, ARight);
  Inc(Y, Px(Gap));

  i := ChosenCount;
  if i = 0 then
    ButtonText := rsCheckNone
  else if i = 1 then
    ButtonText := rsCheckOne
  else
    ButtonText := Format(rsCheckMany, [i]);
  Inc(Y, Px(PillPadY));
  R := PaintPill(ALeft, Y, ButtonText, CheckLink, False, (i > 0) and not FChecking);
  if FChecking then
  begin
    FC.Font.Color := FDim;
    FC.TextOut(R.Right + Px(Gap), Y, Format(rsChecking, [Min(FStatusDone + 1, FStatusTotal),
      FStatusTotal]));
  end
  else if Detail <> '' then
  begin
    FC.Font.Color := FDim;
    FC.TextOut(R.Right + Px(Gap), Y, Detail);
  end;
  Inc(Y, TextH + Px(PillPadY) + Px(Gap));

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

{ The folded list: the picked ones by name, as many as fit, then how
  many more; the line unfolds the list too. }
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
  for i := 0 to BatchOperationCount - 1 do
  begin
    if i = BatchGone then
      Caption_ := rsOpGone
    else
      Caption_ := rsStatusHeading;
    X := PaintPill(X, Y, Caption_, OperationLink + IntToStr(i), i = FOperation, True).Right +
      Px(6);
  end;
  Inc(Y, TextH + Px(PillPadY) + Px(Gap) div 2);
  FC.Pen.Style := psSolid;
  FC.Pen.Color := FLine;
  FC.Line(ALeft, Y, ARight, Y);
  Inc(Y, Px(Gap));
end;

procedure TGittanBatchPage.SetOperation(AValue: integer);
begin
  if (AValue < 0) or (AValue >= BatchOperationCount) then
    AValue := BatchOverview;
  if FOperation = AValue then
    Exit;
  FOperation := AValue;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanBatchPage.Paint;
begin
  FC := Canvas;
  PaintContent;
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

  PaintHeading(Y, rsReposHeading, Format(rsPickedOf, [ChosenCount, RepoCount]), L, R,
    Length(FRows) > 0);
  if FReposOpen or (Length(FRows) = 0) then
    PaintRows(Y, L, R)
  else
    PaintPicked(Y, L, R);
  PaintOperations(Y, L, R);
  if FOperation = BatchGone then
    PaintGone(Y, L, R)
  else
    PaintStatus(Y, L, R);

  { Layout sets the height from this. }
  FContentHeight := Y + Px(Pad);
end;

procedure TGittanBatchPage.FitHeight(AMin: integer);
begin
  Constraints.MinHeight := AMin;
  Layout;
end;

{ The content painted on the measuring canvas, for its height; the
  height is set here, never in Paint. }
procedure TGittanBatchPage.Layout;
var
  H: integer;
begin
  if (Parent = nil) or (Width <= 0) then
    Exit;
  FC := MeasureCanvas(Font);
  PaintContent;
  H := Max(FContentHeight, Constraints.MinHeight);
  if Height <> H then
    Height := H;
  Invalidate;
end;

procedure TGittanBatchPage.Resize;
begin
  inherited Resize;
  Layout;
end;

function TGittanBatchPage.LinkAt(X, Y: integer): integer;
var
  i: integer;
begin
  { The last link added wins: a card's rows lie on it. }
  for i := High(FLinkRects) downto 0 do
    if PtInRect(FLinkRects[i], Point(X, Y)) then
      Exit(i);
  Result := -1;
end;

procedure TGittanBatchPage.SetHot(AValue: integer);
begin
  if FHot = AValue then
    Exit;
  FHot := AValue;
  if AValue < 0 then
    Cursor := crDefault
  else
    Cursor := crHandPoint;
  Invalidate;
end;

procedure TGittanBatchPage.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(LinkAt(X, Y));
end;

procedure TGittanBatchPage.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1);
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
  if Copy(Url, 1, Length(RowLink)) = RowLink then
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
    if (a >= 0) and (a < BatchOperationCount) and (a <> FOperation) then
    begin
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
  end;
end;

end.
