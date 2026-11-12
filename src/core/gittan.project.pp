unit gittan.project;

{** The kinds of project a repository can be, and what Gittan shows of
  them. A kind is a driver: a class in a unit of its own under src/proj
  (gittan.proj.lazarus, gittan.proj.node, gittan.proj.rust,
  gittan.proj.go, gittan.proj.python) that registers itself as it
  loads, as a forge does. Each driver says whether the files at a root
  make the repository one of its kind (Identify), which commands its
  tools offer (the Commands page lists them under the kind's name), and
  what its section of the Project page holds (Section): the page paints
  whatever blocks a driver gives it, facts, tables, checks and notes,
  so a driver shows what only its kind has (Lazarus its build modes and
  where each package comes from, Go its module and replace lines).

  This unit holds the base class, the registry, the page's model and
  the helpers that build it, the dependency comparison every driver
  with a manifest shares (StandardSection), and the context a driver
  reads git through (TGittanProjectContext; TGittanGitProjectContext
  asks the real git). Nothing here needs the LCL; tested in
  tests/testproject.pp, each driver in tests/testproj<kind>.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.manifest, gittan.submodules;

type
  {** A command of a kind's tools: its name on the tile and the shell
    line that runs it, in a terminal when it keeps running. }
  TGittanProjectCommand = record
    Name: string;
    Command: string;
    Terminal: boolean;
  end;
  TGittanProjectCommands = array of TGittanProjectCommand;

  {** Something a kind warns about: the text, the path it is about
    (relative to the root, '' when it is about no file) and the pattern
    that would put the path in .gitignore ('' when ignoring is not the
    answer). }
  TGittanProjectCheck = record
    Text, Path, IgnorePattern: string;
  end;
  TGittanProjectChecks = array of TGittanProjectCheck;

  {** How the page paints a cell: plain text, dimmed, bold, in the link
    color, in the ok, warning or error color, or as a button (with a
    Command; the page runs it as the Commands page would). }
  TGittanProjectStyle = (psText, psDim, psStrong, psLink, psOk, psWarn, psError, psButton);

  {** A cell of a table or a fact's value. Url makes it a link that
    opens in the browser, Command a button that runs the shell line
    under the name CommandName; Hint is the tooltip. }
  TGittanProjectCell = record
    Text, Hint, Url, Command, CommandName: string;
    Style: TGittanProjectStyle;
  end;
  TGittanProjectCells = array of TGittanProjectCell;

  {** A row of a table: its cells under the columns, or, when Heading is
    set, a subheading over the rows that follow. }
  TGittanProjectRow = record
    Cells: TGittanProjectCells;
    Heading: string;
  end;
  TGittanProjectRows = array of TGittanProjectRow;

  {** What a block is: facts (a label and a value per row, the label
    dimmed), a table (its columns as headers when Columns is set; the
    last column at the right end when RightLast), the checks in a
    card, or a dim note. }
  TGittanProjectBlockKind = (pbFacts, pbTable, pbChecks, pbNote);

  TGittanProjectBlock = record
    Kind: TGittanProjectBlockKind;
    {** Painted as a subheading over the block, '' for none. }
    Title: string;
    Columns: TStringArray;
    Rows: TGittanProjectRows;
    RightLast: boolean;
    Checks: TGittanProjectChecks;
    Text: string;
  end;
  TGittanProjectBlocks = array of TGittanProjectBlock;

  TGittanProjectKind = class;
  TGittanProjectKindClass = class of TGittanProjectKind;

  {** One kind's section of the Project page: its heading (the name, a
    detail after it, a state at the right end in its style) and its
    blocks. }
  TGittanProjectSection = record
    Kind: TGittanProjectKindClass;
    Name, Detail, State: string;
    StateStyle: TGittanProjectStyle;
    Blocks: TGittanProjectBlocks;
  end;
  TGittanProjectSections = array of TGittanProjectSection;

  { TGittanProjectContext }

  {** What a driver may ask of git while it builds its section: the
    root, the tag the page compares with (Since, '' for none), the files
    git tracks, a file's text at the tag, a submodule's commit at a
    ref, the submodules. The base answers from what it was given and
    nothing for the rest, which the tests use; TGittanGitProjectContext
    asks git. }
  TGittanProjectContext = class
  private
    FRoot, FSince: string;
    FTracked: TStringList;
  public
    {** ATracked is copied, sorted; nil for none. }
    constructor Create(const ARoot, ASince: string; ATracked: TStrings);
    destructor Destroy; override;
    {** The text of APath (from the root, "/") at Since; '' when there is
      no Since or the file was not there. }
    function ReadAt(const APath: string): string; virtual;
    {** The commit the submodule at APath records at ARef ('' for
      HEAD); '' when it is no submodule there. }
    function GitlinkAt(const APath, ARef: string): string; virtual;
    {** A name for ACommit of the submodule at APath: its tag, or
      tag-n-gHASH, else the short hash. }
    function Describe(const APath, ACommit: string): string; virtual;
    {** The submodules of the repository, with the commits the index
      records. }
    function Submodules: TGittanSubmodules; virtual;
    {** Whether git tracks APath. }
    function IsTracked(const APath: string): boolean;
    {** Whether git tracks a path that starts with APrefix, the first
      such in AFirst. }
    function TrackedUnder(const APrefix: string; out AFirst: string): boolean;
    {** The first tracked path with the extension AExt, ''. }
    function TrackedWithExt(const AExt: string): string;
    property Root: string read FRoot;
    property Since: string read FSince;
    property Tracked: TStringList read FTracked;
  end;

  { TGittanGitProjectContext }

  {** The context of a real repository: Since is the tag nearest HEAD
    (git describe --tags --abbrev=0: the closest reachable one, not the
    newest by version), the tracked files git ls-files, the files at
    the tag git cat-file. }
  TGittanGitProjectContext = class(TGittanProjectContext)
  private
    FSubmodules: TGittanSubmodules;
    FSubmodulesRead: boolean;
  public
    constructor Create(const ARoot: string);
    function ReadAt(const APath: string): string; override;
    function GitlinkAt(const APath, ARef: string): string; override;
    function Describe(const APath, ACommit: string): string; override;
    function Submodules: TGittanSubmodules; override;
  end;

  { TGittanProjectKind }

  {** One kind of project, a driver. Every method reads files at most
    and asks git only through the context, never the network, since the
    kinds are asked on every snapshot. Only Name and Identify are
    required; the rest have a default of nothing. }
  TGittanProjectKind = class
  public
    {** How the interface names it: "Rust", "Go". Short and stable, as
      the commands file and the settings name a kind by it. }
    class function Name: string; virtual; abstract;
    {** Whether the files at ARoot make the repository one of this kind,
      with the file that tells it in AManifest, as the page shows it
      ("Cargo.toml", "Gittan.lpi"). }
    class function Identify(const ARoot: string; out AManifest: string): boolean;
      virtual; abstract;
    {** The commands the kind's tools offer for the repository at
      ARoot. }
    class function Commands(const ARoot: string): TGittanProjectCommands; virtual;
    {** The file at ARoot that lists the dependencies, from the root;
      '' when the kind lists none. }
    class function DependencyFile(const ARoot: string): string; virtual;
    {** The lock file at ARoot with the resolved versions; ''. }
    class function LockFile(const ARoot: string): string; virtual;
    {** Every name the dependency file and the lock file may have, the
      one preferred first, so the files at Since are read under the
      names they had there; none when there is only the one
      DependencyFile and LockFile give. }
    class function DependencyFileNames: TStringArray; virtual;
    class function LockFileNames: TStringArray; virtual;
    {** The dependencies the dependency file's text asks for. }
    class function Dependencies(const AText: string): TGittanDependencies; virtual;
    {** The packages the text of the lock file AName resolved. }
    class function Locked(const AName, AText: string): TGittanDependencies; virtual;
    {** The project's own version from the dependency file's text. }
    class function Version(const AText: string): string; virtual;
    {** The page of the package AName on the kind's registry; ''. }
    class function PackageUrl(const AName: string): string; virtual;
    {** What is worth a warning. }
    class function Checks(AContext: TGittanProjectContext): TGittanProjectChecks; virtual;
    {** The kind's section of the Project page. The default is
      StandardSection; a driver overrides it to show what its kind has
      beyond dependencies, building on StandardSection or not. }
    class function Section(AContext: TGittanProjectContext;
      const AManifest: string): TGittanProjectSection; virtual;
    {** The section every driver with a manifest can have: the heading
      (the manifest, the version, the count of dependencies, how many
      changed since the tag), the dependencies table and the checks. }
    class function StandardSection(AContext: TGittanProjectContext;
      const AManifest: string): TGittanProjectSection;
  end;

  {** A kind found or chosen at a root, with the file that told it ('',
    for a kind chosen with no file). }
  TGittanProject = record
    Kind: TGittanProjectKindClass;
    Name: string;
    Manifest: string;
  end;
  TGittanProjects = array of TGittanProject;
  TGittanProjectKindClasses = array of TGittanProjectKindClass;

  {** How a dependency differs between two versions of the files. }
  TGittanDependencyChangeKind = (dcAdded, dcRemoved, dcChanged);

  TGittanDependencyChange = record
    Name, Group: string;
    {** The versions as shown: the resolved one when there is one, else
      the one asked for. }
    OldVersion, NewVersion: string;
    Kind: TGittanDependencyChangeKind;
  end;
  TGittanDependencyChanges = array of TGittanDependencyChange;

{** Adds a kind to those DetectProjects asks, in the order registered. }
procedure RegisterProjectKind(AClass: TGittanProjectKindClass);

{** The kinds registered, in that order. }
function ProjectKinds: TGittanProjectKindClasses;

{** The kind named AName, whatever the case; nil for none. }
function ProjectKindByName(const AName: string): TGittanProjectKindClass;

{** Every registered kind that identifies the repository at ARoot, in
  the order registered, each with its manifest. }
function DetectProjects(const ARoot: string): TGittanProjects;

{** The kinds of ANames ("rust", "go"), in the registered order, each
  once, with the manifest its Identify gives at ARoot ('' when it does
  not identify it); an unknown name is skipped. }
function ProjectsNamed(const ARoot: string; const ANames: array of string): TGittanProjects;

{** The names of a choice as written ("rust, go"; commas or spaces),
  "none" left out. }
function SplitProjectChoice(const AValue: string): TStringArray;

{** A command as a kind returns it. }
function ProjectCommand(const AName, ACommand: string; ATerminal: boolean = False):
  TGittanProjectCommand;
procedure AddProjectCommand(var ACommands: TGittanProjectCommands;
  const ACommand: TGittanProjectCommand);

{** A check as a kind returns it. }
function ProjectCheck(const AText, APath: string; const AIgnorePattern: string = ''):
  TGittanProjectCheck;
procedure AddProjectCheck(var AChecks: TGittanProjectChecks; const ACheck: TGittanProjectCheck);

{** The page's model. }
function ProjectCell(const AText: string; AStyle: TGittanProjectStyle = psText;
  const AHint: string = ''; const AUrl: string = ''): TGittanProjectCell;
function ProjectButton(const AText, ACommandName, ACommand: string;
  const AHint: string = ''): TGittanProjectCell;
function ProjectRow(const ACells: array of TGittanProjectCell): TGittanProjectRow;
function ProjectHeadingRow(const AHeading: string): TGittanProjectRow;
function ProjectBlock(AKind: TGittanProjectBlockKind; const ATitle: string = ''):
  TGittanProjectBlock;
procedure AddRow(var ABlock: TGittanProjectBlock; const ARow: TGittanProjectRow);
{** A fact: ALabel dimmed, AValue in AStyle; nothing when AValue is ''. }
procedure AddFact(var ABlock: TGittanProjectBlock; const ALabel, AValue: string;
  AStyle: TGittanProjectStyle = psText; const AUrl: string = '');
{** Adds ABlock, unless it is empty (no rows, no checks, no text). }
procedure AddBlock(var ASection: TGittanProjectSection; const ABlock: TGittanProjectBlock);
{** A note block with AText. }
function ProjectNote(const AText: string): TGittanProjectBlock;
{** The checks as a block. }
function ChecksBlock(const AChecks: TGittanProjectChecks): TGittanProjectBlock;

{** The version of a dependency as shown: the resolved one when the
  lock file has it, else what the manifest asks for. }
function DependencyShown(const ADependency: TGittanDependency): string;

{** Fills each dependency's Resolved from the locked packages of the
  same name. }
procedure ResolveDependencies(var ADependencies: TGittanDependencies;
  const ALocked: TGittanDependencies);

{** How ANew's dependencies differ from AOld's, by name and group: the
  ones added and changed in ANew's order, then the ones removed. }
function DependencyChanges(const AOld, ANew: TGittanDependencies): TGittanDependencyChanges;

{** The dependencies of AKind at the context's root, resolved by the
  lock file, and how they differ from those at Since (none without a
  Since). False when the kind has no dependency file. }
function ReadDependencies(AKind: TGittanProjectKindClass; AContext: TGittanProjectContext;
  out ADependencies: TGittanDependencies; out AChanges: TGittanDependencyChanges): boolean;

{** The table of dependencies: the name (a link to the registry), what
  is asked for, what is resolved, and the change since the tag at the
  right; the groups under subheadings, the removed ones at their group's
  end. }
function DependencyTable(AKind: TGittanProjectKindClass; const ASince: string;
  const ADependencies: TGittanDependencies; const AChanges: TGittanDependencyChanges):
  TGittanProjectBlock;

{** How the page names a dependency group: Development for dev, and so
  on; another as it is, with a capital. }
function GroupTitle(const AGroup: string): string;

{** The sections of the page for AProjects: each kind's Section, or its
  StandardSection when it was picked with no manifest. }
function ProjectSections(const AProjects: TGittanProjects;
  AContext: TGittanProjectContext): TGittanProjectSections;

{ Helpers the drivers share. }

{** ARoot + AName. }
function RootFile(const ARoot, AName: string): string;
function HasFile(const ARoot, AName: string): boolean;
function HasDir(const ARoot, AName: string): boolean;
{** The text of the file AName at ARoot, '' without it. }
function TextOf(const ARoot, AName: string): string;
{** The files at ARoot whose name ends with AExt, by name. }
function FilesWithExt(const ARoot, AExt: string): TStringArray;
{** A name for the shell: quoted when it has a space or a character
  the shell reads, in single quotes for sh (a quote in it as '\''), in
  double quotes on Windows. }
function ShellName(const AName: string): string;

implementation

uses
  gittan.git, gittan.textfile;

resourcestring
  rsChangesSince = '%d changed since %s';
  rsOneChangeSince = '1 changed since %s';
  rsNoChangesSince = 'no changes since %s';
  rsDependencies = '%d dependencies';
  rsOneDependency = '1 dependency';
  rsNoDependencies = 'No dependencies in %s.';
  rsPickedNoFile = 'Picked by hand, but there is no %s at the root.';
  rsPicked = 'picked';
  rsAdded = 'added';
  rsRemoved = 'removed';
  rsChangedHint = '%s was %s at %s';
  rsAddedHint = '%s is new since %s';
  rsRemovedHint = '%s was %s at %s and is gone';
  rsGroupDev = 'Development';
  rsGroupBuild = 'Build';
  rsGroupPeer = 'Peer';
  rsGroupOptional = 'Optional';
  rsGroupIndirect = 'Indirect';

var
  GKinds: TGittanProjectKindClasses;

{ ---------------------------------------------------------------------------
  The registry
  --------------------------------------------------------------------------- }

procedure RegisterProjectKind(AClass: TGittanProjectKindClass);
var
  i: integer;
begin
  for i := 0 to High(GKinds) do
    if GKinds[i] = AClass then
      Exit;
  SetLength(GKinds, Length(GKinds) + 1);
  GKinds[High(GKinds)] := AClass;
end;

function ProjectKinds: TGittanProjectKindClasses;
begin
  Result := Copy(GKinds);
end;

function ProjectKindByName(const AName: string): TGittanProjectKindClass;
var
  i: integer;
begin
  for i := 0 to High(GKinds) do
    if SameText(GKinds[i].Name, Trim(AName)) then
      Exit(GKinds[i]);
  Result := nil;
end;

function DetectProjects(const ARoot: string): TGittanProjects;
var
  i: integer;
  Manifest: string;
begin
  Result := nil;
  if (ARoot = '') or not DirectoryExists(ARoot) then
    Exit;
  for i := 0 to High(GKinds) do
    if GKinds[i].Identify(ARoot, Manifest) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].Kind := GKinds[i];
      Result[High(Result)].Name := GKinds[i].Name;
      Result[High(Result)].Manifest := Manifest;
    end;
end;

function ProjectsNamed(const ARoot: string; const ANames: array of string): TGittanProjects;
var
  i, j: integer;
  Wanted: boolean;
  Manifest: string;
begin
  Result := nil;
  for i := 0 to High(GKinds) do
  begin
    Wanted := False;
    for j := 0 to High(ANames) do
      if SameText(Trim(ANames[j]), GKinds[i].Name) then
        Wanted := True;
    if not Wanted then
      Continue;
    if (ARoot = '') or not DirectoryExists(ARoot) or
      not GKinds[i].Identify(ARoot, Manifest) then
      Manifest := '';
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Kind := GKinds[i];
    Result[High(Result)].Name := GKinds[i].Name;
    Result[High(Result)].Manifest := Manifest;
  end;
end;

function SplitProjectChoice(const AValue: string): TStringArray;
var
  Parts: TStringArray;
  i: integer;
begin
  Result := nil;
  Parts := AValue.Split([',', ' ', ';'], TStringSplitOptions.ExcludeEmpty);
  for i := 0 to High(Parts) do
    if not SameText(Parts[i], 'none') then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Parts[i];
    end;
end;

function ProjectCommand(const AName, ACommand: string; ATerminal: boolean): TGittanProjectCommand;
begin
  Result.Name := AName;
  Result.Command := ACommand;
  Result.Terminal := ATerminal;
end;

procedure AddProjectCommand(var ACommands: TGittanProjectCommands;
  const ACommand: TGittanProjectCommand);
begin
  SetLength(ACommands, Length(ACommands) + 1);
  ACommands[High(ACommands)] := ACommand;
end;

function ProjectCheck(const AText, APath: string; const AIgnorePattern: string):
  TGittanProjectCheck;
begin
  Result.Text := AText;
  Result.Path := APath;
  Result.IgnorePattern := AIgnorePattern;
end;

procedure AddProjectCheck(var AChecks: TGittanProjectChecks; const ACheck: TGittanProjectCheck);
begin
  SetLength(AChecks, Length(AChecks) + 1);
  AChecks[High(AChecks)] := ACheck;
end;

{ ---------------------------------------------------------------------------
  The page's model
  --------------------------------------------------------------------------- }

function ProjectCell(const AText: string; AStyle: TGittanProjectStyle; const AHint: string;
  const AUrl: string): TGittanProjectCell;
begin
  Result := Default(TGittanProjectCell);
  Result.Text := AText;
  Result.Style := AStyle;
  Result.Hint := AHint;
  Result.Url := AUrl;
end;

function ProjectButton(const AText, ACommandName, ACommand: string;
  const AHint: string): TGittanProjectCell;
begin
  Result := Default(TGittanProjectCell);
  Result.Text := AText;
  Result.Style := psButton;
  Result.CommandName := ACommandName;
  Result.Command := ACommand;
  if AHint <> '' then
    Result.Hint := AHint
  else
    Result.Hint := ACommand;
end;

function ProjectRow(const ACells: array of TGittanProjectCell): TGittanProjectRow;
var
  i: integer;
begin
  Result := Default(TGittanProjectRow);
  SetLength(Result.Cells, Length(ACells));
  for i := 0 to High(ACells) do
    Result.Cells[i] := ACells[i];
end;

function ProjectHeadingRow(const AHeading: string): TGittanProjectRow;
begin
  Result := Default(TGittanProjectRow);
  Result.Heading := AHeading;
end;

function ProjectBlock(AKind: TGittanProjectBlockKind; const ATitle: string): TGittanProjectBlock;
begin
  Result := Default(TGittanProjectBlock);
  Result.Kind := AKind;
  Result.Title := ATitle;
end;

procedure AddRow(var ABlock: TGittanProjectBlock; const ARow: TGittanProjectRow);
begin
  SetLength(ABlock.Rows, Length(ABlock.Rows) + 1);
  ABlock.Rows[High(ABlock.Rows)] := ARow;
end;

procedure AddFact(var ABlock: TGittanProjectBlock; const ALabel, AValue: string;
  AStyle: TGittanProjectStyle; const AUrl: string);
begin
  if AValue = '' then
    Exit;
  AddRow(ABlock, ProjectRow([ProjectCell(ALabel, psDim), ProjectCell(AValue, AStyle, AUrl, AUrl)]));
end;

procedure AddBlock(var ASection: TGittanProjectSection; const ABlock: TGittanProjectBlock);
begin
  case ABlock.Kind of
    pbFacts, pbTable:
      if Length(ABlock.Rows) = 0 then
        Exit;
    pbChecks:
      if Length(ABlock.Checks) = 0 then
        Exit;
    pbNote:
      if ABlock.Text = '' then
        Exit;
  end;
  SetLength(ASection.Blocks, Length(ASection.Blocks) + 1);
  ASection.Blocks[High(ASection.Blocks)] := ABlock;
end;

function ProjectNote(const AText: string): TGittanProjectBlock;
begin
  Result := ProjectBlock(pbNote);
  Result.Text := AText;
end;

function ChecksBlock(const AChecks: TGittanProjectChecks): TGittanProjectBlock;
begin
  Result := ProjectBlock(pbChecks);
  Result.Checks := AChecks;
end;

{ ---------------------------------------------------------------------------
  Dependencies
  --------------------------------------------------------------------------- }

function DependencyShown(const ADependency: TGittanDependency): string;
begin
  if ADependency.Resolved <> '' then
    Result := ADependency.Resolved
  else
    Result := ADependency.Version;
end;

{ The numbers of a version: 1, 2, 3 of "1.2.3-beta"; a part that does
  not start with a digit ends them ("1.x" is 1). }
function VersionParts(const AVersion: string): TStringArray;
var
  Parts: TStringArray;
  i, k: integer;
begin
  Result := nil;
  Parts := AVersion.Split(['.']);
  for i := 0 to High(Parts) do
  begin
    k := 1;
    while (k <= Length(Parts[i])) and (Parts[i][k] in ['0'..'9']) do
      Inc(k);
    if k = 1 then
      Break;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Copy(Parts[i], 1, k - 1);
    if k <= Length(Parts[i]) then
      Break;
  end;
end;

{ -1, 0 or 1 as the version A is below, equal to or above B, by their
  numbers, a missing one counted as 0. }
function CompareVersionParts(const A, B: TStringArray): integer;
var
  i, Last: integer;
  X, Y: int64;
begin
  Last := High(A);
  if High(B) > Last then
    Last := High(B);
  for i := 0 to Last do
  begin
    X := 0;
    Y := 0;
    if i <= High(A) then
      X := StrToInt64Def(A[i], 0);
    if i <= High(B) then
      Y := StrToInt64Def(B[i], 0);
    if X < Y then
      Exit(-1);
    if X > Y then
      Exit(1);
  end;
  Result := 0;
end;

{ Whether AVersion starts with the numbers of APrefix. }
function HasVersionPrefix(const AVersion, APrefix: TStringArray): boolean;
var
  i: integer;
begin
  if Length(APrefix) > Length(AVersion) then
    Exit(False);
  for i := 0 to High(APrefix) do
    if StrToInt64Def(AVersion[i], 0) <> StrToInt64Def(APrefix[i], 0) then
      Exit(False);
  Result := True;
end;

{ Whether AVersion meets one constraint of a requirement: ">=1.2",
  "<2", "==1.4", "~1.2" (or ~= of Python: the same 1.2), "^1.2" or a
  bare "1.2" (Cargo's and npm's caret: the same major, the same 0.x
  below 1), "!=1.3". One without a number ("*", "workspace", "latest")
  is met by every version. }
function MeetsConstraint(const AVersion: TStringArray; const AConstraint: string): boolean;
var
  Op: string;
  Want, Prefix: TStringArray;
  i, c: integer;
begin
  i := 1;
  while (i <= Length(AConstraint)) and (AConstraint[i] in ['<', '>', '=', '!', '~', '^']) do
    Inc(i);
  Op := Copy(AConstraint, 1, i - 1);
  { npm's "v1.2". }
  if (i <= Length(AConstraint)) and (AConstraint[i] = 'v') then
    Inc(i);
  Want := VersionParts(Copy(AConstraint, i, MaxInt));
  if Length(Want) = 0 then
    Exit(True);
  c := CompareVersionParts(AVersion, Want);
  if Op = '>=' then
    Result := c >= 0
  else if Op = '>' then
    Result := c > 0
  else if Op = '<=' then
    Result := c <= 0
  else if Op = '<' then
    Result := c < 0
  else if Op = '!=' then
    Result := c <> 0
  else if (Op = '=') or (Op = '==') or (Op = '===') then
    Result := HasVersionPrefix(AVersion, Want)
  else if (Op = '~') or (Op = '~=') then
  begin
    { ~1.2 is 1.2.x, ~1 is 1.x; Python's ~=1.4.2 is 1.4.x. }
    Prefix := Copy(Want, 0, 2);
    if (Op = '~=') and (Length(Want) > 1) then
      Prefix := Copy(Want, 0, Length(Want) - 1);
    Result := HasVersionPrefix(AVersion, Prefix) and (c >= 0);
  end
  else
  begin
    { The caret, written or not: the first number that is not 0 stays. }
    i := 0;
    while (i < High(Want)) and (StrToInt64Def(Want[i], 0) = 0) do
      Inc(i);
    Result := HasVersionPrefix(AVersion, Copy(Want, 0, i + 1)) and (c >= 0);
  end;
end;

{ Whether AVersion meets a requirement as a manifest writes it: any of
  its "||" alternatives, each a list of constraints by commas or spaces
  (">=1.2, <2", ">=1.2 <2"). }
function MeetsRequirement(const AVersion, ARequirement: string): boolean;
var
  Version, Alternatives, Constraints: TStringArray;
  Req: string;
  i, k: integer;
  All: boolean;
begin
  Version := VersionParts(AVersion);
  { An operator and its number are one constraint: ">= 1.2". }
  Req := '';
  for i := 1 to Length(ARequirement) do
    if not ((ARequirement[i] = ' ') and (Req <> '') and
      (Req[Length(Req)] in ['<', '>', '=', '!', '~', '^'])) then
      Req := Req + ARequirement[i];
  Alternatives := Req.Split(['||']);
  for i := 0 to High(Alternatives) do
  begin
    Constraints := Alternatives[i].Split([',', ' '], TStringSplitOptions.ExcludeEmpty);
    All := True;
    for k := 0 to High(Constraints) do
      if not MeetsConstraint(Version, Constraints[k]) then
        All := False;
    if All then
      Exit(True);
  end;
  Result := Length(Alternatives) = 0;
end;

procedure ResolveDependencies(var ADependencies: TGittanDependencies;
  const ALocked: TGittanDependencies);
var
  i, j, Count, Best: integer;
begin
  for i := 0 to High(ADependencies) do
  begin
    Count := 0;
    Best := -1;
    for j := 0 to High(ALocked) do
      if ALocked[j].Name = ADependencies[i].Name then
      begin
        Inc(Count);
        Best := j;
      end;
    if Count > 1 then
    begin
      { Several versions locked: the one the manifest asks for, exactly
        when one is, else the newest that meets the requirement; none
        when none meets it, rather than one that is wrong. }
      Best := -1;
      for j := 0 to High(ALocked) do
        if (ALocked[j].Name = ADependencies[i].Name) and
          MeetsRequirement(ALocked[j].Resolved, ADependencies[i].Version) then
        begin
          if ALocked[j].Resolved = ADependencies[i].Version then
          begin
            Best := j;
            Break;
          end;
          if (Best < 0) or (CompareVersionParts(VersionParts(ALocked[j].Resolved),
            VersionParts(ALocked[Best].Resolved)) > 0) then
            Best := j;
        end;
    end;
    if Best >= 0 then
      ADependencies[i].Resolved := ALocked[Best].Resolved;
  end;
end;

function DependencyChanges(const AOld, ANew: TGittanDependencies): TGittanDependencyChanges;
var
  i, j: integer;
  Found: boolean;

  procedure Add(const AName, AGroup, AOldVersion, ANewVersion: string;
    AKind: TGittanDependencyChangeKind);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Name := AName;
    Result[High(Result)].Group := AGroup;
    Result[High(Result)].OldVersion := AOldVersion;
    Result[High(Result)].NewVersion := ANewVersion;
    Result[High(Result)].Kind := AKind;
  end;

begin
  Result := nil;
  for i := 0 to High(ANew) do
  begin
    Found := False;
    for j := 0 to High(AOld) do
      if (AOld[j].Name = ANew[i].Name) and (AOld[j].Group = ANew[i].Group) then
      begin
        Found := True;
        if DependencyShown(AOld[j]) <> DependencyShown(ANew[i]) then
          Add(ANew[i].Name, ANew[i].Group, DependencyShown(AOld[j]), DependencyShown(ANew[i]),
            dcChanged);
        Break;
      end;
    if not Found then
      Add(ANew[i].Name, ANew[i].Group, '', DependencyShown(ANew[i]), dcAdded);
  end;
  for j := 0 to High(AOld) do
  begin
    Found := False;
    for i := 0 to High(ANew) do
      if (AOld[j].Name = ANew[i].Name) and (AOld[j].Group = ANew[i].Group) then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      Add(AOld[j].Name, AOld[j].Group, DependencyShown(AOld[j]), '', dcRemoved);
  end;
end;

{ The name of the file at Since and its text: ACurrent when it was
  there, else the first of ANames that was; '' for none. }
function FileAtSince(AContext: TGittanProjectContext; const ACurrent: string;
  const ANames: TStringArray; out AText: string): string;
var
  i: integer;
begin
  AText := '';
  if ACurrent <> '' then
  begin
    AText := AContext.ReadAt(ACurrent);
    if AText <> '' then
      Exit(ACurrent);
  end;
  for i := 0 to High(ANames) do
    if ANames[i] <> ACurrent then
    begin
      AText := AContext.ReadAt(ANames[i]);
      if AText <> '' then
        Exit(ANames[i]);
    end;
  Result := '';
end;

function ReadDependencies(AKind: TGittanProjectKindClass; AContext: TGittanProjectContext;
  out ADependencies: TGittanDependencies; out AChanges: TGittanDependencyChanges): boolean;
var
  DepFile, LockName, OldText, OldLockName, OldLock: string;
  Old: TGittanDependencies;
begin
  ADependencies := nil;
  AChanges := nil;
  DepFile := AKind.DependencyFile(AContext.Root);
  if DepFile = '' then
    Exit(False);
  Result := True;
  ADependencies := AKind.Dependencies(TextOf(AContext.Root, DepFile));
  LockName := AKind.LockFile(AContext.Root);
  if LockName <> '' then
    ResolveDependencies(ADependencies, AKind.Locked(LockName, TextOf(AContext.Root, LockName)));
  if AContext.Since = '' then
    Exit;
  { The tag's files under the names they had there: a project that
    moved from requirements.txt to pyproject.toml, or to another lock
    file, is compared with what it had. }
  FileAtSince(AContext, DepFile, AKind.DependencyFileNames, OldText);
  Old := AKind.Dependencies(OldText);
  OldLockName := FileAtSince(AContext, LockName, AKind.LockFileNames, OldLock);
  if OldLockName <> '' then
    ResolveDependencies(Old, AKind.Locked(OldLockName, OldLock));
  AChanges := DependencyChanges(Old, ADependencies);
end;

function GroupTitle(const AGroup: string): string;
begin
  if AGroup = 'dev' then
    Result := rsGroupDev
  else if AGroup = 'build' then
    Result := rsGroupBuild
  else if AGroup = 'peer' then
    Result := rsGroupPeer
  else if AGroup = 'optional' then
    Result := rsGroupOptional
  else if AGroup = 'indirect' then
    Result := rsGroupIndirect
  else if AGroup = '' then
    Result := ''
  else
    Result := UpperCase(Copy(AGroup, 1, 1)) + Copy(AGroup, 2, MaxInt);
end;

function DependencyTable(AKind: TGittanProjectKindClass; const ASince: string;
  const ADependencies: TGittanDependencies; const AChanges: TGittanDependencyChanges):
  TGittanProjectBlock;
var
  Groups: TStringArray;
  g, i, k: integer;
  D: TGittanDependency;
  Note: TGittanProjectCell;
  Resolved, Url: string;

  procedure AddGroup(const AGroup: string);
  var
    n: integer;
  begin
    for n := 0 to High(Groups) do
      if Groups[n] = AGroup then
        Exit;
    SetLength(Groups, Length(Groups) + 1);
    Groups[High(Groups)] := AGroup;
  end;

begin
  Result := ProjectBlock(pbTable);
  Result.RightLast := True;
  Groups := nil;
  AddGroup('');
  for i := 0 to High(ADependencies) do
    AddGroup(ADependencies[i].Group);
  for i := 0 to High(AChanges) do
    if AChanges[i].Kind = dcRemoved then
      AddGroup(AChanges[i].Group);
  for g := 0 to High(Groups) do
  begin
    if Groups[g] <> '' then
      AddRow(Result, ProjectHeadingRow(GroupTitle(Groups[g])));
    for i := 0 to High(ADependencies) do
    begin
      D := ADependencies[i];
      if D.Group <> Groups[g] then
        Continue;
      Note := ProjectCell('');
      for k := 0 to High(AChanges) do
        if (AChanges[k].Name = D.Name) and (AChanges[k].Group = D.Group) then
          case AChanges[k].Kind of
            dcAdded:
              Note := ProjectCell(rsAdded, psOk, Format(rsAddedHint, [D.Name, ASince]));
            dcChanged:
              Note := ProjectCell(AChanges[k].OldVersion + ' → ' + AChanges[k].NewVersion, psLink,
                Format(rsChangedHint, [D.Name, AChanges[k].OldVersion, ASince]));
            dcRemoved: ;
          end;
      { The resolved version when it differs from what is asked for
        (go.mod asks for the exact one). }
      if D.Resolved <> D.Version then
        Resolved := D.Resolved
      else
        Resolved := '';
      Url := AKind.PackageUrl(D.Name);
      AddRow(Result, ProjectRow([ProjectCell(D.Name, psStrong, Url, Url),
        ProjectCell(D.Version, psDim), ProjectCell(Resolved), Note]));
    end;
    for i := 0 to High(AChanges) do
      if (AChanges[i].Kind = dcRemoved) and (AChanges[i].Group = Groups[g]) then
        AddRow(Result, ProjectRow([ProjectCell(AChanges[i].Name, psDim),
          ProjectCell(AChanges[i].OldVersion, psDim), ProjectCell(''),
          ProjectCell(rsRemoved, psError, Format(rsRemovedHint, [AChanges[i].Name,
          AChanges[i].OldVersion, ASince]))]));
    { A heading with nothing under it goes again. }
    if (Length(Result.Rows) > 0) and (Result.Rows[High(Result.Rows)].Heading <> '') then
      SetLength(Result.Rows, Length(Result.Rows) - 1);
  end;
end;

{ ---------------------------------------------------------------------------
  The context
  --------------------------------------------------------------------------- }

constructor TGittanProjectContext.Create(const ARoot, ASince: string; ATracked: TStrings);
begin
  inherited Create;
  FRoot := ARoot;
  FSince := ASince;
  FTracked := TStringList.Create;
  FTracked.CaseSensitive := True;
  if ATracked <> nil then
    FTracked.AddStrings(ATracked);
  FTracked.Sorted := True;
end;

destructor TGittanProjectContext.Destroy;
begin
  FTracked.Free;
  inherited Destroy;
end;

function TGittanProjectContext.ReadAt(const APath: string): string;
begin
  Result := '';
end;

function TGittanProjectContext.GitlinkAt(const APath, ARef: string): string;
begin
  Result := '';
end;

function TGittanProjectContext.Describe(const APath, ACommit: string): string;
begin
  Result := Copy(ACommit, 1, 7);
end;

function TGittanProjectContext.Submodules: TGittanSubmodules;
begin
  Result := nil;
end;

function TGittanProjectContext.IsTracked(const APath: string): boolean;
var
  i: integer;
begin
  Result := FTracked.Find(APath, i);
end;

function TGittanProjectContext.TrackedUnder(const APrefix: string; out AFirst: string): boolean;
var
  i: integer;
begin
  AFirst := '';
  { Sorted, so the first path with the prefix is where it would go. }
  FTracked.Find(APrefix, i);
  if (i < FTracked.Count) and (Pos(APrefix, FTracked[i]) = 1) then
  begin
    AFirst := FTracked[i];
    Exit(True);
  end;
  Result := False;
end;

function TGittanProjectContext.TrackedWithExt(const AExt: string): string;
var
  i: integer;
begin
  for i := 0 to FTracked.Count - 1 do
    if SameText(ExtractFileExt(FTracked[i]), AExt) then
      Exit(FTracked[i]);
  Result := '';
end;

constructor TGittanGitProjectContext.Create(const ARoot: string);
var
  Output, Err, Tag, Path: string;
  List: TStringList;
begin
  Tag := '';
  if RunGitIn(ARoot, ['describe', '--tags', '--abbrev=0'], Output, Err) then
    Tag := Trim(Output);
  List := TStringList.Create;
  try
    if RunGitIn(ARoot, ['ls-files', '-z', '--cached'], Output, Err) then
      for Path in Output.Split([#0], TStringSplitOptions.ExcludeEmpty) do
        List.Add(Path);
    inherited Create(ARoot, Tag, List);
  finally
    List.Free;
  end;
end;

function TGittanGitProjectContext.ReadAt(const APath: string): string;
var
  Err: string;
begin
  if (Since = '') or (APath = '') or not RunGitIn(Root, ['cat-file', 'blob',
    Since + ':' + APath], Result, Err) then
    Result := '';
end;

function TGittanGitProjectContext.GitlinkAt(const APath, ARef: string): string;
var
  Output, Err, Ref: string;
begin
  Ref := ARef;
  if Ref = '' then
    Ref := 'HEAD';
  if RunGitIn(Root, ['ls-tree', '-z', Ref, '--', APath], Output, Err) then
    Result := ParseGitlink(Output)
  else
    Result := '';
end;

function TGittanGitProjectContext.Describe(const APath, ACommit: string): string;
var
  Output, Err: string;
begin
  if (ACommit <> '') and RunGitIn(IncludeTrailingPathDelimiter(Root) + SetDirSeparators(APath),
    ['describe', '--tags', '--always', ACommit], Output, Err) and (Trim(Output) <> '') then
    Result := Trim(Output)
  else
    Result := Copy(ACommit, 1, 7);
end;

function TGittanGitProjectContext.Submodules: TGittanSubmodules;
var
  Err: string;
begin
  if not FSubmodulesRead then
  begin
    FSubmodulesRead := True;
    if not ListSubmodules(Root, FSubmodules, Err) then
      FSubmodules := nil;
  end;
  Result := FSubmodules;
end;

{ ---------------------------------------------------------------------------
  The base class
  --------------------------------------------------------------------------- }

class function TGittanProjectKind.Commands(const ARoot: string): TGittanProjectCommands;
begin
  Result := nil;
end;

class function TGittanProjectKind.DependencyFile(const ARoot: string): string;
begin
  Result := '';
end;

class function TGittanProjectKind.LockFile(const ARoot: string): string;
begin
  Result := '';
end;

class function TGittanProjectKind.DependencyFileNames: TStringArray;
begin
  Result := nil;
end;

class function TGittanProjectKind.LockFileNames: TStringArray;
begin
  Result := nil;
end;

class function TGittanProjectKind.Dependencies(const AText: string): TGittanDependencies;
begin
  Result := nil;
end;

class function TGittanProjectKind.Locked(const AName, AText: string): TGittanDependencies;
begin
  Result := nil;
end;

class function TGittanProjectKind.Version(const AText: string): string;
begin
  Result := '';
end;

class function TGittanProjectKind.PackageUrl(const AName: string): string;
begin
  Result := '';
end;

class function TGittanProjectKind.Checks(AContext: TGittanProjectContext): TGittanProjectChecks;
begin
  Result := nil;
end;

class function TGittanProjectKind.Section(AContext: TGittanProjectContext;
  const AManifest: string): TGittanProjectSection;
begin
  Result := StandardSection(AContext, AManifest);
end;

class function TGittanProjectKind.StandardSection(AContext: TGittanProjectContext;
  const AManifest: string): TGittanProjectSection;
var
  Deps: TGittanDependencies;
  Changes: TGittanDependencyChanges;
  DepFile, Ver: string;
  n: integer;
begin
  Result := Default(TGittanProjectSection);
  Result.Kind := Self;
  Result.Name := Name;
  Result.Detail := AManifest;
  if AManifest = '' then
    Result.Detail := rsPicked;
  Result.StateStyle := psDim;
  DepFile := DependencyFile(AContext.Root);
  { A kind picked with no file of its own has nothing to read, but the
    checks that need no such file still hold. }
  if (DepFile <> '') and not HasFile(AContext.Root, DepFile) then
  begin
    AddBlock(Result, ProjectNote(Format(rsPickedNoFile, [DepFile])));
    AddBlock(Result, ChecksBlock(Checks(AContext)));
    Exit;
  end;
  if ReadDependencies(Self, AContext, Deps, Changes) then
  begin
    Ver := Version(TextOf(AContext.Root, DepFile));
    if Ver <> '' then
      Result.Detail := Result.Detail + ' · ' + Ver;
    n := Length(Deps);
    if n = 1 then
      Result.Detail := Result.Detail + ' · ' + rsOneDependency
    else if n > 1 then
      Result.Detail := Result.Detail + ' · ' + Format(rsDependencies, [n]);
    if AContext.Since <> '' then
    begin
      n := Length(Changes);
      if n = 0 then
        Result.State := Format(rsNoChangesSince, [AContext.Since])
      else
      begin
        if n = 1 then
          Result.State := Format(rsOneChangeSince, [AContext.Since])
        else
          Result.State := Format(rsChangesSince, [n, AContext.Since]);
        Result.StateStyle := psLink;
      end;
    end;
    if (Length(Deps) = 0) and (Length(Changes) = 0) then
      AddBlock(Result, ProjectNote(Format(rsNoDependencies, [DepFile])))
    else
      AddBlock(Result, DependencyTable(Self, AContext.Since, Deps, Changes));
  end;
  AddBlock(Result, ChecksBlock(Checks(AContext)));
end;

function ProjectSections(const AProjects: TGittanProjects;
  AContext: TGittanProjectContext): TGittanProjectSections;
var
  i: integer;
begin
  SetLength(Result, Length(AProjects));
  for i := 0 to High(AProjects) do
    { A kind picked by hand that its files do not tell has nothing of
      its own to show: the standard section says so. }
    if AProjects[i].Manifest = '' then
      Result[i] := AProjects[i].Kind.StandardSection(AContext, '')
    else
      Result[i] := AProjects[i].Kind.Section(AContext, AProjects[i].Manifest);
end;

{ ---------------------------------------------------------------------------
  Helpers the drivers share
  --------------------------------------------------------------------------- }

function RootFile(const ARoot, AName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(ARoot) + SetDirSeparators(AName);
end;

function HasFile(const ARoot, AName: string): boolean;
begin
  Result := (AName <> '') and FileExists(RootFile(ARoot, AName));
end;

function HasDir(const ARoot, AName: string): boolean;
begin
  Result := DirectoryExists(RootFile(ARoot, AName));
end;

function TextOf(const ARoot, AName: string): string;
begin
  Result := '';
  if HasFile(ARoot, AName) then
    try
      Result := ReadFileBytes(RootFile(ARoot, AName));
    except
      { Gone or locked since HasFile looked: as if it were not there. }
      Result := '';
    end;
end;

function FilesWithExt(const ARoot, AExt: string): TStringArray;
var
  Info: TSearchRec;
  Names: TStringList;
  i: integer;
begin
  Result := nil;
  Names := TStringList.Create;
  try
    if FindFirst(RootFile(ARoot, '*' + AExt), faAnyFile and not faDirectory, Info) = 0 then
    begin
      repeat
        if SameText(ExtractFileExt(Info.Name), AExt) then
          Names.Add(Info.Name);
      until FindNext(Info) <> 0;
      FindClose(Info);
    end;
    Names.Sort;
    SetLength(Result, Names.Count);
    for i := 0 to Names.Count - 1 do
      Result[i] := Names[i];
  finally
    Names.Free;
  end;
end;

function ShellName(const AName: string): string;
var
  i: integer;
begin
  for i := 1 to Length(AName) do
    if not (AName[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', '/', '+', '=', ':', ',']) then
      {$IFDEF WINDOWS}
      { cmd.exe reads no \" (a name like x" & calc & " ran calc): a quote
        is doubled, which turns cmd's quoting off and on again and is one
        quote to the program. cmd expands %VAR% inside quotes too, so a %
        stands in quotes of its own: %"PATH"% names no variable. }
      Exit('"' + StringReplace(StringReplace(AName, '"', '""', [rfReplaceAll]), '%', '"%"',
        [rfReplaceAll]) + '"');
      {$ELSE}
      { Single quotes, where sh reads nothing ($, `, \ and " included);
        a quote of the name ends them, is escaped and opens them again. }
      Exit('''' + StringReplace(AName, '''', '''\''''', [rfReplaceAll]) + '''');
      {$ENDIF}
  Result := AName;
end;

end.
