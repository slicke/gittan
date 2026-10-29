unit gittan.timelapse;

{** The time-lapse of a file: every version of it that its history has,
  with the commit each line came in with and the commit that took it
  away.

  The commits come from `git log -p -U0 --follow --first-parent` (see
  TGittanRepo.FileTimeline), newest first, and the text from the newest
  of them. Every older version is made from the one after it by undoing
  that commit's hunks, so a line kept from one version to the next is
  the same entry in both. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.git, gittan.history, gittan.job;

const
  {** The most commits a time-lapse goes back over, newest first; each
    keeps a version of the file. }
  TimelapseMax = 1000;
  {** Every how many versions one is kept whole; the ones between are
    made again from it when asked for (TGittanTimelapse.Lines). }
  TimelapseMarkEvery = 32;

type
  TGittanEntryIds = array of integer;

  {** One hunk's change from a version to the one before it: Drop
    entries of the newer version taken out from At on, Put put in their
    place. }
  TGittanLapseEdit = record
    At, Drop: integer;
    Put: TGittanEntryIds;
  end;
  {** A commit's edits, in order, as the version it left becomes the one
    before it. }
  TGittanLapseStep = array of TGittanLapseEdit;

  { TGittanTimelapse }

  {** The versions of a file, one per commit of a TGittanHistory: the
    version of commit C is the file as C left it. A line is an entry,
    shared by the versions that have it; Born is the commit it came in
    with (the oldest one for a line that was there before the history
    begins), Died the one that took it away, -1 for a line still there.
    Commits are counted as in the history, newest first. Only every
    TimelapseMarkEvery-th version is kept whole (FMarks), with each
    commit's edits (FSteps), so a long history of a long file holds about
    as much as its changes rather than a copy of the file per commit. }
  TGittanTimelapse = class
  private
    FTexts: TStringArray;
    FBorn, FDied: TGittanEntryIds;
    FCount: integer;
    FMarks: array of TGittanEntryIds;
    FSteps: array of TGittanLapseStep;
    { The version Lines made last, which the next one older than it in
      the same stretch is made from. }
    FCacheAt: integer;
    FCache: TGittanEntryIds;
    function NewEntry(const AText: string): integer;
  public
    {** Makes the versions from AText, the file as the newest commit of
      AHistory left it, back through the commits. The walk stops at a
      commit whose hunks do not fit the version after it (git should
      not give one), and AHistory is cut to the commits it got through.
      False when not even the newest version could be made. }
    function Build(AHistory: TGittanHistory; const AText: string): boolean;
    {** How many versions there are, one per commit. }
    function Count: integer;
    {** The entries of the version of commit ACommit, in order, made
      from the version kept whole at or after it. }
    function Lines(ACommit: integer): TGittanEntryIds;
    function Text(AEntry: integer): string;
    function Born(AEntry: integer): integer;
    function Died(AEntry: integer): integer;
  end;

  { TGittanTimelapseJob }

  {** Reads the history of APath up to ARef (HEAD when empty) through
    TGittanRepo.FileTimeline in its own thread, through its own
    TGittanRepo on ARoot, and builds the time-lapse; OnDone is called in
    the main thread. History and Timelapse are nil when git failed, the
    file is binary or has no history (Error then says why, or is empty);
    TakeHistory and TakeTimelapse hand them over, else the job frees
    them. }
  TGittanTimelapseJob = class(TGittanJob)
  private
    FRoot, FPath, FRef: string;
    FHistory: TGittanHistory;
    FTimelapse: TGittanTimelapse;
    FError: string;
    FBinary: boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot, APath, ARef: string);
    destructor Destroy; override;
    function TakeHistory: TGittanHistory;
    function TakeTimelapse: TGittanTimelapse;
    property History: TGittanHistory read FHistory;
    property Timelapse: TGittanTimelapse read FTimelapse;
    property Error: string read FError;
    {** The file is binary in ARef: it has no lines to follow. }
    property Binary: boolean read FBinary;
  end;

implementation

uses
  gittan.textfile;

{ ---------------------------------------------------------------------------
  Building
  ---------------------------------------------------------------------------
  With -U0 a hunk holds only the lines it deleted and added. Its new
  start is the first added line, or with none added the line after
  which the deleted ones stood; its lines are taken out of the newer
  version and the deleted ones put back in their place. The text the
  hunk says it added is checked against the version, so a history that
  does not fit is noticed rather than shown wrong. }

function TGittanTimelapse.NewEntry(const AText: string): integer;
begin
  Result := Length(FTexts);
  SetLength(FTexts, Result + 1);
  SetLength(FBorn, Result + 1);
  SetLength(FDied, Result + 1);
  FTexts[Result] := AText;
  FBorn[Result] := -1;
  FDied[Result] := -1;
end;

{ ANewer with AStep's edits: the version before it. }
function ApplyStep(const ANewer: TGittanEntryIds; const AStep: TGittanLapseStep): TGittanEntryIds;
var
  e, i, n, From: integer;
begin
  n := Length(ANewer);
  for e := 0 to High(AStep) do
    n := n + Length(AStep[e].Put) - AStep[e].Drop;
  SetLength(Result, n);
  n := 0;
  From := 0;
  for e := 0 to High(AStep) do
  begin
    for i := From to AStep[e].At - 1 do
    begin
      Result[n] := ANewer[i];
      Inc(n);
    end;
    for i := 0 to High(AStep[e].Put) do
    begin
      Result[n] := AStep[e].Put[i];
      Inc(n);
    end;
    From := AStep[e].At + AStep[e].Drop;
  end;
  for i := From to High(ANewer) do
  begin
    Result[n] := ANewer[i];
    Inc(n);
  end;
end;

function TGittanTimelapse.Build(AHistory: TGittanHistory; const AText: string): boolean;
var
  Newer: TGittanEntryIds;
  Step: TGittanLapseStep;
  Edit: TGittanLapseEdit;
  Hunk: TGittanHistoryHunk;
  Line: string;
  c, h, i, n, Puts, At, Adds, Start: integer;
  Fits: boolean;

  procedure Add(var AList: TGittanEntryIds; var ACount: integer; AEntry: integer);
  begin
    if ACount >= Length(AList) then
      SetLength(AList, ACount * 2 + 16);
    AList[ACount] := AEntry;
    Inc(ACount);
  end;

  { The edit under way, when it changes anything, as the step's next;
    the next edit starts at At. }
  procedure Flush;
  begin
    if (Edit.Drop > 0) or (Puts > 0) then
    begin
      SetLength(Edit.Put, Puts);
      Insert(Edit, Step, Length(Step));
    end;
    Edit := Default(TGittanLapseEdit);
    Edit.At := At;
    Puts := 0;
  end;

begin
  FTexts := nil;
  FBorn := nil;
  FDied := nil;
  FMarks := nil;
  FSteps := nil;
  FCount := 0;
  FCacheAt := -1;
  FCache := nil;
  Result := AHistory.Count > 0;
  if not Result then
    Exit;
  Newer := nil;
  n := 0;
  i := 1;
  while NextLine(AText, i, Line) do
    Add(Newer, n, NewEntry(Line));
  SetLength(Newer, n);
  FCount := AHistory.Count;
  SetLength(FSteps, FCount);
  for c := 0 to AHistory.Count - 1 do
  begin
    if c mod TimelapseMarkEvery = 0 then
      Insert(Newer, FMarks, Length(FMarks));
    for i := 0 to High(Newer) do
      FBorn[Newer[i]] := c;
    if c = AHistory.Count - 1 then
      Break;
    { The version before commit c, which the next older commit left. }
    Step := nil;
    At := 0;
    Edit := Default(TGittanLapseEdit);
    Puts := 0;
    Fits := True;
    for h := 0 to High(AHistory.Commits[c].Hunks) do
    begin
      Hunk := AHistory.Commits[c].Hunks[h];
      Adds := 0;
      for i := 0 to High(Hunk.Lines) do
        if Hunk.Lines[i][1] = '+' then
          Inc(Adds);
      if Adds > 0 then
        Start := Hunk.NewStart - 1
      else
        Start := Hunk.NewStart;
      if (Start < At) or (Start > Length(Newer)) then
      begin
        Fits := False;
        Break;
      end;
      At := Start;
      Flush;
      for i := 0 to High(Hunk.Lines) do
      begin
        Line := Copy(Hunk.Lines[i], 2, MaxInt);
        case Hunk.Lines[i][1] of
          '+':
            begin
              if (At > High(Newer)) or (FTexts[Newer[At]] <> Line) then
              begin
                Fits := False;
                Break;
              end;
              Inc(Edit.Drop);
              Inc(At);
            end;
          '-':
            begin
              Add(Edit.Put, Puts, NewEntry(Line));
              FDied[High(FTexts)] := c;
            end;
          ' ':
            begin
              if At > High(Newer) then
              begin
                Fits := False;
                Break;
              end;
              Flush;
              Inc(At);
              Edit.At := At;
            end;
        end;
      end;
      if not Fits then
        Break;
      Flush;
    end;
    if not Fits then
    begin
      FCount := c + 1;
      Break;
    end;
    FSteps[c] := Step;
    Newer := ApplyStep(Newer, Step);
  end;
  SetLength(FSteps, FCount);
  AHistory.Truncate(FCount);
end;

function TGittanTimelapse.Count: integer;
begin
  Result := FCount;
end;

{ A version is made from the last one asked for when that is newer in
  the same stretch, which stepping back through the history is, else
  from the stretch's mark. }
function TGittanTimelapse.Lines(ACommit: integer): TGittanEntryIds;
var
  From, s: integer;
begin
  if (ACommit < 0) or (ACommit >= FCount) then
    Exit(nil);
  if (FCacheAt >= 0) and (FCacheAt <= ACommit) and
    (FCacheAt div TimelapseMarkEvery = ACommit div TimelapseMarkEvery) then
  begin
    From := FCacheAt;
    Result := FCache;
  end
  else
  begin
    From := ACommit div TimelapseMarkEvery * TimelapseMarkEvery;
    Result := FMarks[ACommit div TimelapseMarkEvery];
  end;
  for s := From to ACommit - 1 do
    Result := ApplyStep(Result, FSteps[s]);
  FCacheAt := ACommit;
  FCache := Result;
end;

function TGittanTimelapse.Text(AEntry: integer): string;
begin
  Result := FTexts[AEntry];
end;

function TGittanTimelapse.Born(AEntry: integer): integer;
begin
  Result := FBorn[AEntry];
end;

function TGittanTimelapse.Died(AEntry: integer): integer;
begin
  Result := FDied[AEntry];
end;

{ ---------------------------------------------------------------------------
  The job
  --------------------------------------------------------------------------- }
constructor TGittanTimelapseJob.Create(const ARoot, APath, ARef: string);
begin
  inherited Create(True);
  FRoot := ARoot;
  FPath := APath;
  FRef := ARef;
end;

destructor TGittanTimelapseJob.Destroy;
begin
  inherited Destroy;
  FHistory.Free;
  FTimelapse.Free;
end;

procedure TGittanTimelapseJob.Execute;
var
  Repo: TGittanRepo;
  Log, Text, Ref: string;
  Size: int64;
begin
  Repo := TGittanRepo.Create;
  try
    if not Repo.Open(FRoot) then
    begin
      FError := Repo.Error;
      Exit;
    end;
    { A file the commit lacks (untracked, or added since) has no history
      to play: no time-lapse and no error, rather than git's "exists on
      disk, but not in 'HEAD'". }
    Ref := FRef;
    if Ref = '' then
      Ref := 'HEAD';
    if not Repo.FileSize(FPath, Ref, Size) then
      Exit;
    if not Repo.FileTimeline(FPath, FRef, TimelapseMax, Log, Text) or Terminated then
    begin
      FError := Repo.Error;
      Exit;
    end;
    { A NUL is what git takes for a binary file too. }
    if Pos(#0, Text) > 0 then
    begin
      FBinary := True;
      Exit;
    end;
    FHistory := TGittanHistory.Create;
    FTimelapse := TGittanTimelapse.Create;
    if not FHistory.Parse(Log) or not FTimelapse.Build(FHistory, Text) then
    begin
      FreeAndNil(FHistory);
      FreeAndNil(FTimelapse);
    end;
  finally
    Repo.Free;
    Done;
  end;
end;

function TGittanTimelapseJob.TakeHistory: TGittanHistory;
begin
  Result := FHistory;
  FHistory := nil;
end;

function TGittanTimelapseJob.TakeTimelapse: TGittanTimelapse;
begin
  Result := FTimelapse;
  FTimelapse := nil;
end;

end.
