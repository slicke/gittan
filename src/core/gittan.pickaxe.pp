unit gittan.pickaxe;

{** The commits whose diff adds or removes a text, for the commit graph's
  "change:" filter: git log -S (the commits that change how many times
  a text occurs, so the one that added a line and the one that took it
  away, not one that only moved it) or, for a value between slashes,
  git log -G (every commit with an added or removed line matching the
  regular expression, moves too). The case is ignored unless the text
  has a capital letter, as code search tools do.

  On a large repository the search takes seconds, so the graph asks for
  it through TGittanChangeJob, a thread given up as soon as the filter
  changes: git is ended then, not left to run to the end. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.git, gittan.job;

type
  {** Runs ChangeCommits for AChanges in the repository at ARoot on a
    thread and raises OnDone in the main thread with Hashes (the
    commits that make every change, newest first), Ok false and Error
    git's reason when git failed (a regular expression it cannot read).
    Changes is what it was asked for, for the caller to tell whether
    the answer is still wanted. Stop ends git. }
  TGittanChangeJob = class(TGittanJob)
  private
    FRoot, FError: string;
    FChanges: TStringArray;
    FMax: integer;
    FOk: boolean;
    FHashes: TStringList;
    function Cancelled: boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: string; const AChanges: TStringArray;
      AMax: integer);
    destructor Destroy; override;
    property Changes: TStringArray read FChanges;
    property Ok: boolean read FOk;
    property Error: string read FError;
    property Hashes: TStringList read FHashes;
  end;

{** The git log option that looks for AChange: "-G<regex>" for a value
  between slashes ("/a+b/"), else "-S<text>"; AIgnoreCase when the text
  has no capital letter (a letter after a backslash in a regular
  expression, as in \S or \W, does not count). False for a value with
  nothing to look for ("", "//"). }
function PickaxeOption(const AChange: string; out AOption: string;
  out AIgnoreCase: boolean): boolean;

{** The ids of the commits of every local and remote branch, every tag
  and HEAD whose diff makes each of AChanges (see PickaxeOption), newest
  first, at most AMax; a change with nothing to look for is left out.
  ACancel, when given, is asked as git runs and ends it. False when git
  failed, with its reason in AError (the first line, without "fatal: "),
  or was ended. }
function ChangeCommits(const ARoot: string; const AChanges: array of string;
  AHashes: TStrings; AMax: integer; ACancel: TGittanCancelEvent;
  out AError: string): boolean;

implementation

function PickaxeOption(const AChange: string; out AOption: string;
  out AIgnoreCase: boolean): boolean;
var
  Pattern: string;
  Regex: boolean;
  i: integer;
begin
  Regex := (Length(AChange) >= 2) and (AChange[1] = '/') and
    (AChange[Length(AChange)] = '/');
  if Regex then
    Pattern := Copy(AChange, 2, Length(AChange) - 2)
  else
    Pattern := AChange;
  AOption := '';
  AIgnoreCase := True;
  Result := Pattern <> '';
  if not Result then
    Exit;
  i := 1;
  while i <= Length(Pattern) do
  begin
    if Regex and (Pattern[i] = '\') then
      Inc(i)
    else if Pattern[i] in ['A'..'Z'] then
      AIgnoreCase := False;
    Inc(i);
  end;
  if Regex then
    AOption := '-G' + Pattern
  else
    AOption := '-S' + Pattern;
end;

{ git's message as one line: the first that says something, without the
  "fatal: " git puts before it. }
function GitReason(const AError: string): string;
var
  Lines: TStringArray;
  i: integer;
begin
  Result := '';
  Lines := AError.Split([#10]);
  for i := 0 to High(Lines) do
  begin
    Result := Trim(Lines[i]);
    if Result <> '' then
      Break;
  end;
  if Pos('fatal: ', Result) = 1 then
    Delete(Result, 1, Length('fatal: '));
end;

{ One git log per change, since git takes one -S or -G; the commits of
  the first that the others have too are kept, in the first's order. }
function ChangeCommits(const ARoot: string; const AChanges: array of string;
  AHashes: TStrings; AMax: integer; ACancel: TGittanCancelEvent;
  out AError: string): boolean;
var
  Option, Output, Err: string;
  IgnoreCase, First: boolean;
  Args: array of string;
  Found: TStringList;
  i, j, n: integer;
begin
  AHashes.Clear;
  AError := '';
  Result := True;
  First := True;
  Found := TStringList.Create;
  try
    Found.Sorted := True;
    Found.CaseSensitive := True;
    for i := 0 to High(AChanges) do
    begin
      if not PickaxeOption(AChanges[i], Option, IgnoreCase) then
        Continue;
      SetLength(Args, 11);
      Args[0] := 'log';
      Args[1] := '--format=%H';
      Args[2] := '-n';
      Args[3] := IntToStr(AMax);
      Args[4] := Option;
      n := 5;
      if IgnoreCase then
      begin
        Args[n] := '--regexp-ignore-case';
        Inc(n);
      end;
      Args[n] := '--branches';
      Args[n + 1] := '--remotes';
      Args[n + 2] := '--tags';
      Args[n + 3] := 'HEAD';
      Args[n + 4] := '--';
      SetLength(Args, n + 5);
      if not RunGitEnv(ARoot, Args, [], Output, Err, '', nil, ACancel) then
      begin
        AHashes.Clear;
        AError := GitReason(Err);
        Exit(False);
      end;
      Found.Text := Output;
      if First then
      begin
        AHashes.Text := Output;
        First := False;
      end
      else
        for j := AHashes.Count - 1 downto 0 do
          if Found.IndexOf(AHashes[j]) < 0 then
            AHashes.Delete(j);
    end;
  finally
    Found.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  TGittanChangeJob
  ---------------------------------------------------------------------------
  git runs in the thread and is asked through Cancelled whether to go
  on, so a search the filter no longer wants ends at once. }

constructor TGittanChangeJob.Create(const ARoot: string;
  const AChanges: TStringArray; AMax: integer);
begin
  inherited Create(True);
  FRoot := ARoot;
  FChanges := Copy(AChanges, 0, Length(AChanges));
  FMax := AMax;
  FHashes := TStringList.Create;
end;

destructor TGittanChangeJob.Destroy;
begin
  inherited Destroy;
  FHashes.Free;
end;

function TGittanChangeJob.Cancelled: boolean;
begin
  Result := Terminated;
end;

procedure TGittanChangeJob.Execute;
begin
  FOk := ChangeCommits(FRoot, FChanges, FHashes, FMax, @Cancelled, FError);
  Done;
end;

end.
