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

type
  TGittanEntryIds = array of integer;

  { TGittanTimelapse }

  {** The versions of a file, one per commit of a TGittanHistory: the
    version of commit C is the file as C left it. A line is an entry,
    shared by the versions that have it; Born is the commit it came in
    with (the oldest one for a line that was there before the history
    begins), Died the one that took it away, -1 for a line still there.
    Commits are counted as in the history, newest first. }
  TGittanTimelapse = class
  private
    FTexts: TStringArray;
    FBorn, FDied: TGittanEntryIds;
    FVersions: array of TGittanEntryIds;
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
    {** The entries of the version of commit ACommit, in order. }
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

function TGittanTimelapse.Build(AHistory: TGittanHistory; const AText: string): boolean;
var
  Newer, Older: TGittanEntryIds;
  Hunk: TGittanHistoryHunk;
  Line: string;
  c, h, i, n, At, Adds, Start, Kept: integer;
  Fits: boolean;

  procedure Add(var AList: TGittanEntryIds; var ACount: integer; AEntry: integer);
  begin
    if ACount >= Length(AList) then
      SetLength(AList, ACount * 2 + 16);
    AList[ACount] := AEntry;
    Inc(ACount);
  end;

begin
  FTexts := nil;
  FBorn := nil;
  FDied := nil;
  FVersions := nil;
  Result := AHistory.Count > 0;
  if not Result then
    Exit;
  Newer := nil;
  n := 0;
  i := 1;
  while NextLine(AText, i, Line) do
    Add(Newer, n, NewEntry(Line));
  SetLength(Newer, n);
  Kept := AHistory.Count;
  SetLength(FVersions, Kept);
  for c := 0 to AHistory.Count - 1 do
  begin
    FVersions[c] := Newer;
    for i := 0 to High(Newer) do
      FBorn[Newer[i]] := c;
    if c = AHistory.Count - 1 then
      Break;
    { The version before commit c, which the next older commit left. }
    Older := nil;
    n := 0;
    At := 0;
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
      while At < Start do
      begin
        Add(Older, n, Newer[At]);
        Inc(At);
      end;
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
              Inc(At);
            end;
          '-':
            begin
              Add(Older, n, NewEntry(Line));
              FDied[High(FTexts)] := c;
            end;
          ' ':
            begin
              if At > High(Newer) then
              begin
                Fits := False;
                Break;
              end;
              Add(Older, n, Newer[At]);
              Inc(At);
            end;
        end;
      end;
      if not Fits then
        Break;
    end;
    if not Fits then
    begin
      Kept := c + 1;
      Break;
    end;
    while At <= High(Newer) do
    begin
      Add(Older, n, Newer[At]);
      Inc(At);
    end;
    SetLength(Older, n);
    Newer := Older;
  end;
  SetLength(FVersions, Kept);
  AHistory.Truncate(Kept);
end;

function TGittanTimelapse.Count: integer;
begin
  Result := Length(FVersions);
end;

function TGittanTimelapse.Lines(ACommit: integer): TGittanEntryIds;
begin
  if (ACommit < 0) or (ACommit > High(FVersions)) then
    Exit(nil);
  Result := FVersions[ACommit];
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
  Log, Text: string;
begin
  Repo := TGittanRepo.Create;
  try
    if not Repo.Open(FRoot) then
      Exit;
    if not Repo.FileTimeline(FPath, FRef, Log, Text) then
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
