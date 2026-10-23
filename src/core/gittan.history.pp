unit gittan.history;

{** The history of a piece of code: the commits that changed a range of
  lines of a file, newest first, each with its diff of those lines.

  Reads the output of `git log -L` (see TGittanRepo.LineHistory) into
  the commits and their hunks, and runs git in a background thread: to
  follow a range back through the history git diffs every commit on the
  way, which takes a while. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, gittan.git, gittan.blame, gittan.job;

type
  {** One hunk of a commit's diff: the lines with their ' ', '+' or '-'
    marker, and the number of the first line in the old and in the new
    version of the file. }
  TGittanHistoryHunk = record
    OldStart, NewStart: integer;
    Lines: TStringArray;
  end;
  TGittanHistoryHunks = array of TGittanHistoryHunk;

  {** One commit of the history: who, when and what it said, and the
    hunks it changed in the range. }
  TGittanHistoryCommit = record
    Info: TGittanBlameCommit;
    Hunks: TGittanHistoryHunks;
  end;
  TGittanHistoryCommits = array of TGittanHistoryCommit;

  {** One row of the layered view of a history (see TGittanHistory.Layers):
    a line of the newest version of the range, an older version of the
    line above it, or a line that was removed. Commit is the commit this
    version of the line comes from, -1 for one older than the history;
    RemovedBy the commit that removed a removed line. Line is the number
    of a current line in the newest version. Depth is 0 for a current
    line and grows with every step back in time. }
  TGittanHistoryRowKind = (hrCurrent, hrOld, hrRemoved);
  TGittanHistoryRow = record
    Text: string;
    Kind: TGittanHistoryRowKind;
    Commit: integer;
    RemovedBy: integer;
    Line: integer;
    Depth: integer;
  end;
  TGittanHistoryRows = array of TGittanHistoryRow;

  { TGittanHistory }

  {** The commits that changed a range of a file, newest first. }
  TGittanHistory = class
  private
    FCommits: TGittanHistoryCommits;
  public
    {** The range as it is in the newest commit, with the earlier versions
      of every line under it: for each line of the newest version its
      row, then the version of it the newest commit that changed it
      replaced, then the one before that, and so on back through the
      commits; a line a commit removed follows the line before it as it
      was then. The hunks of each commit are chained through their old
      and new sides, newest first: the lines a commit deleted are paired
      in order with the lines it added in their place. }
    function Layers: TGittanHistoryRows;
    {** Reads the output of `git log` as TGittanRepo.LineHistory formats
      it. Returns false when no commit with a hunk could be read. }
    function Parse(const AOutput: string): boolean;
    {** Puts ACommit before the others: the changes not committed yet. }
    procedure Prepend(const ACommit: TGittanHistoryCommit);
    {** Keeps the first ACount commits. }
    procedure Truncate(ACount: integer);
    function Count: integer;
    property Commits: TGittanHistoryCommits read FCommits;
  end;

  { TGittanHistoryJob }

  {** Runs TGittanRepo.LineHistory for the lines AFrom..ATo of APath as
    they are in ARef (HEAD when empty), at most AMax commits, in its own
    thread through its own TGittanRepo on ARoot, and calls OnDone in the
    main thread. The result is in History, nil when git failed (its
    message is then in Error) or found nothing; Take hands it over, else
    the job frees it. Set OnDone, then call Start; Stop ends the thread
    without a notification. }
  TGittanHistoryJob = class(TGittanJob)
  private
    FRoot, FPath, FRef: string;
    FFrom, FTo, FMax: integer;
    FIgnoreWhitespace: boolean;
    FHistory: TGittanHistory;
    FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot, APath, ARef: string; AFrom, ATo, AMax: integer;
      AIgnoreWhitespace: boolean);
    destructor Destroy; override;
    function Take: TGittanHistory;
    property History: TGittanHistory read FHistory;
    property Error: string read FError;
  end;

implementation

uses
  gittan.textfile;

{ ---------------------------------------------------------------------------
  Parsing
  ---------------------------------------------------------------------------
  Each commit comes as a header line, #1 then the hash, the author, the
  author time and the summary separated by #31 (the format LineHistory
  asks for), a blank line, the diff's own header lines (diff --git,
  index, ---, +++), then its hunks: "@@ -a,b +c,d @@ ..." and the lines
  with their markers. A "\ No newline at end of file" note is skipped,
  as is a blank line between a diff and the next header. The text is
  read by hand: a line of the file may hold a bare carriage return,
  which TStrings would take for a line break. }

const
  HeaderMark = #1;
  FieldSep = #31;

{ The first number of "-a,b" or "+c,d" starting at S[AFrom]. }
function HunkStart(const S: string; AFrom: integer): integer;
var
  p: integer;
begin
  Result := 0;
  p := AFrom;
  while (p <= Length(S)) and (S[p] in ['0'..'9']) do
  begin
    Result := Result * 10 + Ord(S[p]) - Ord('0');
    Inc(p);
  end;
end;

{ Whether ALine is a hunk header; AOld and ANew are then its start
  lines. }
function HunkHeader(const ALine: string; out AOld, ANew: integer): boolean;
var
  p: integer;
begin
  Result := False;
  AOld := 0;
  ANew := 0;
  if (Copy(ALine, 1, 4) <> '@@ -') then
    Exit;
  AOld := HunkStart(ALine, 5);
  p := Pos(' +', ALine);
  if p = 0 then
    Exit;
  ANew := HunkStart(ALine, p + 2);
  Result := True;
end;

procedure SplitHeader(const ALine: string; var AInfo: TGittanBlameCommit);
var
  Fields: TStringArray;
begin
  AInfo := Default(TGittanBlameCommit);
  Fields := Copy(ALine, 2, MaxInt).Split([FieldSep]);
  if Length(Fields) > 0 then
    AInfo.Hash := Fields[0];
  if Length(Fields) > 1 then
    AInfo.Author := Fields[1];
  if Length(Fields) > 2 then
    AInfo.Time := StrToInt64Def(Fields[2], 0);
  if Length(Fields) > 3 then
    AInfo.Summary := Fields[3];
end;

function TGittanHistory.Parse(const AOutput: string): boolean;
var
  Start, Current, Hunk, Kept, i: integer;
  Line: string;
  OldStart, NewStart: integer;

  procedure AddLine(var AHunk: TGittanHistoryHunk);
  begin
    SetLength(AHunk.Lines, Length(AHunk.Lines) + 1);
    AHunk.Lines[High(AHunk.Lines)] := Line;
  end;

begin
  FCommits := nil;
  Current := -1;
  Hunk := -1;
  Start := 1;
  while NextLine(AOutput, Start, Line) do
  begin
    if Line = '' then
      Continue;
    if Line[1] = HeaderMark then
    begin
      SetLength(FCommits, Length(FCommits) + 1);
      Current := High(FCommits);
      FCommits[Current].Hunks := nil;
      SplitHeader(Line, FCommits[Current].Info);
      Hunk := -1;
      Continue;
    end;
    if Current < 0 then
      Continue;
    if HunkHeader(Line, OldStart, NewStart) then
    begin
      SetLength(FCommits[Current].Hunks, Length(FCommits[Current].Hunks) + 1);
      Hunk := High(FCommits[Current].Hunks);
      FCommits[Current].Hunks[Hunk].OldStart := OldStart;
      FCommits[Current].Hunks[Hunk].NewStart := NewStart;
      FCommits[Current].Hunks[Hunk].Lines := nil;
      Continue;
    end;
    if (Hunk >= 0) and (Line[1] in [' ', '+', '-']) then
      AddLine(FCommits[Current].Hunks[Hunk]);
  end;
  { A commit without a hunk (a merge, which git log -p shows without a
    diff) says nothing about the range. }
  Kept := 0;
  for i := 0 to High(FCommits) do
    if Length(FCommits[i].Hunks) > 0 then
    begin
      if Kept < i then
        FCommits[Kept] := FCommits[i];
      Inc(Kept);
    end;
  SetLength(FCommits, Kept);
  Result := Kept > 0;
end;

{ ---------------------------------------------------------------------------
  Layers
  ---------------------------------------------------------------------------
  Every version of a line is an entry; Prev links a version to the one
  before it, After lists the removed lines that followed it. The state is
  the range as a list of entries at one point in time: the new side of
  the newest commit to begin with, then, after each commit is walked,
  its old side, which is the new side of the next older commit. }
function TGittanHistory.Layers: TGittanHistoryRows;
type
  TEntry = record
    Text: string;
    Commit, RemovedBy, Prev: integer;
    Removed: boolean;
    After: array of integer;
  end;
var
  Entries: array of TEntry;
  State, Mapped, OldState, TopRemoved, Current: array of integer;
  Rows: TGittanHistoryRows;
  RowCount: integer;

  function NewEntry(const AText: string): integer;
  begin
    SetLength(Entries, Length(Entries) + 1);
    Result := High(Entries);
    Entries[Result].Text := AText;
    Entries[Result].Commit := -1;
    Entries[Result].RemovedBy := -1;
    Entries[Result].Prev := -1;
    Entries[Result].Removed := False;
    Entries[Result].After := nil;
  end;

  { The lines of every hunk of commit AIndex, in order. }
  function HunkLines(AIndex: integer): TStringArray;
  var
    h, i, n: integer;
  begin
    Result := nil;
    n := 0;
    for h := 0 to High(FCommits[AIndex].Hunks) do
      Inc(n, Length(FCommits[AIndex].Hunks[h].Lines));
    SetLength(Result, n);
    n := 0;
    for h := 0 to High(FCommits[AIndex].Hunks) do
      for i := 0 to High(FCommits[AIndex].Hunks[h].Lines) do
      begin
        Result[n] := FCommits[AIndex].Hunks[h].Lines[i];
        Inc(n);
      end;
  end;

  procedure Emit(AEntry, ADepth: integer; AKind: TGittanHistoryRowKind; ALine: integer);
  var
    i: integer;
  begin
    if RowCount >= Length(Rows) then
      SetLength(Rows, RowCount * 2 + 16);
    Rows[RowCount].Text := Entries[AEntry].Text;
    Rows[RowCount].Kind := AKind;
    Rows[RowCount].Commit := Entries[AEntry].Commit;
    Rows[RowCount].RemovedBy := Entries[AEntry].RemovedBy;
    Rows[RowCount].Line := ALine;
    Rows[RowCount].Depth := ADepth;
    Inc(RowCount);
    if Entries[AEntry].Prev >= 0 then
      Emit(Entries[AEntry].Prev, ADepth + 1, hrOld, 0);
    for i := 0 to High(Entries[AEntry].After) do
      Emit(Entries[AEntry].After[i], ADepth + 1, hrRemoved, 0);
  end;

var
  Lines: TStringArray;
  c, i, j, k, li, p, Adds, Anchor, e: integer;
  Dels: TStringArray;
  Text: string;
begin
  Result := nil;
  if Length(FCommits) = 0 then
    Exit;
  Entries := nil;
  State := nil;
  TopRemoved := nil;
  Current := nil;
  for c := 0 to High(FCommits) do
  begin
    Lines := HunkLines(c);
    { The entries of the new side of this commit: the ones of the state,
      found in order by their text, or new ones for lines the state does
      not have (git's hunks should chain exactly; a line that does not
      is a new entry without a past). }
    Mapped := nil;
    p := 0;
    for li := 0 to High(Lines) do
    begin
      if Lines[li][1] = '-' then
        Continue;
      Text := Copy(Lines[li], 2, MaxInt);
      if c = 0 then
        e := NewEntry(Text)
      else
      begin
        k := p;
        while (k <= High(State)) and (Entries[State[k]].Text <> Text) do
          Inc(k);
        if k <= High(State) then
        begin
          e := State[k];
          p := k + 1;
        end
        else
          e := NewEntry(Text);
      end;
      SetLength(Mapped, Length(Mapped) + 1);
      Mapped[High(Mapped)] := e;
    end;
    if c = 0 then
      Current := Copy(Mapped);
    { Walk the hunk: a context line goes on, a block of deleted lines
      followed by added lines pairs them in order; the state after is
      the old side. }
    OldState := nil;
    i := 0;
    li := 0;
    while li <= High(Lines) do
    begin
      if Lines[li][1] = ' ' then
      begin
        SetLength(OldState, Length(OldState) + 1);
        OldState[High(OldState)] := Mapped[i];
        Inc(i);
        Inc(li);
        Continue;
      end;
      Dels := nil;
      while (li <= High(Lines)) and (Lines[li][1] = '-') do
      begin
        SetLength(Dels, Length(Dels) + 1);
        Dels[High(Dels)] := Copy(Lines[li], 2, MaxInt);
        Inc(li);
      end;
      Adds := 0;
      while (li <= High(Lines)) and (Lines[li][1] = '+') do
      begin
        Inc(Adds);
        Inc(li);
      end;
      if Adds > 0 then
        Anchor := Mapped[i + Adds - 1]
      else if i > 0 then
        Anchor := Mapped[i - 1]
      else
        Anchor := -1;
      for j := 0 to Max(Length(Dels), Adds) - 1 do
      begin
        if j < Adds then
        begin
          e := Mapped[i + j];
          if Entries[e].Commit < 0 then
            Entries[e].Commit := c;
          if j <= High(Dels) then
          begin
            k := NewEntry(Dels[j]);
            Entries[e].Prev := k;
            SetLength(OldState, Length(OldState) + 1);
            OldState[High(OldState)] := k;
          end;
        end
        else
        begin
          k := NewEntry(Dels[j]);
          Entries[k].Removed := True;
          Entries[k].RemovedBy := c;
          if Anchor >= 0 then
          begin
            SetLength(Entries[Anchor].After, Length(Entries[Anchor].After) + 1);
            Entries[Anchor].After[High(Entries[Anchor].After)] := k;
          end
          else
          begin
            SetLength(TopRemoved, Length(TopRemoved) + 1);
            TopRemoved[High(TopRemoved)] := k;
          end;
          SetLength(OldState, Length(OldState) + 1);
          OldState[High(OldState)] := k;
        end;
      end;
      Inc(i, Adds);
    end;
    State := OldState;
  end;
  Rows := nil;
  RowCount := 0;
  for i := 0 to High(TopRemoved) do
    Emit(TopRemoved[i], 1, hrRemoved, 0);
  for i := 0 to High(Current) do
    Emit(Current[i], 0, hrCurrent, FCommits[0].Hunks[0].NewStart + i);
  SetLength(Rows, RowCount);
  Result := Rows;
end;

procedure TGittanHistory.Prepend(const ACommit: TGittanHistoryCommit);
var
  i: integer;
begin
  SetLength(FCommits, Length(FCommits) + 1);
  for i := High(FCommits) downto 1 do
    FCommits[i] := FCommits[i - 1];
  FCommits[0] := ACommit;
end;

procedure TGittanHistory.Truncate(ACount: integer);
begin
  if (ACount >= 0) and (ACount < Length(FCommits)) then
    SetLength(FCommits, ACount);
end;

function TGittanHistory.Count: integer;
begin
  Result := Length(FCommits);
end;

{ ---------------------------------------------------------------------------
  The job
  --------------------------------------------------------------------------- }
constructor TGittanHistoryJob.Create(const ARoot, APath, ARef: string;
  AFrom, ATo, AMax: integer; AIgnoreWhitespace: boolean);
begin
  inherited Create(True);
  FRoot := ARoot;
  FPath := APath;
  FRef := ARef;
  FFrom := AFrom;
  FTo := ATo;
  FMax := AMax;
  FIgnoreWhitespace := AIgnoreWhitespace;
end;

destructor TGittanHistoryJob.Destroy;
begin
  inherited Destroy;
  FHistory.Free;
end;

procedure TGittanHistoryJob.Execute;
var
  Repo: TGittanRepo;
  Output: string;
begin
  Repo := TGittanRepo.Create;
  try
    if not Repo.Open(FRoot) then
      Exit;
    Repo.IgnoreWhitespace := FIgnoreWhitespace;
    if Repo.LineHistory(FPath, FRef, FFrom, FTo, FMax, Output) then
    begin
      FHistory := TGittanHistory.Create;
      if not FHistory.Parse(Output) then
        FreeAndNil(FHistory);
    end
    else
      FError := Repo.Error;
  finally
    Repo.Free;
  end;
  Done;
end;

{ WaitFor on the main thread runs the queued calls while it waits, so the
  handler is dropped first: a Notify already queued then does nothing. }
function TGittanHistoryJob.Take: TGittanHistory;
begin
  Result := FHistory;
  FHistory := nil;
end;

end.
