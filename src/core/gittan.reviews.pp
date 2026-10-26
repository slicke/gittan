unit gittan.reviews;

{** The review comments of a pull request: its threads, the notes of its
  conversation that are on no line, the base of the job that reads them
  in a thread (a forge's, see gittan.forge; GitHub's reads them in
  gittan.github), and the mapping of a line of the pull request's head
  to the same line in the work tree. Nothing here needs the LCL. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.job;

type
  {** One comment of a thread. Created is in UTC, 0 when GitHub gave no
    time. }
  TGittanReviewComment = record
    Author, Body, Url: string;
    Created: TDateTime;
  end;
  TGittanReviewComments = array of TGittanReviewComment;

  {** One review thread: the comments on a line (or the lines StartLine..
    Line) of a file. Line is in the pull request's head, or with LeftSide
    in its base (a removed line); 0 when the thread is outdated (the line
    changed since) or is on the whole file (OnFile). OriginalLine is the
    line in the commit the comment was made on. A thread an AI agent
    wrote (gittan.ai) has the agent's name in Agent and how much the
    finding weighs in Severity (bug, risk, question); its Line is the
    shown diff's own, in the old side with LeftSide, and it has one
    comment, with no address. }
  TGittanReviewThread = record
    Path: string;
    Line, StartLine, OriginalLine: integer;
    LeftSide, Resolved, Outdated, OnFile: boolean;
    Comments: TGittanReviewComments;
    Agent, Severity: string;
  end;
  TGittanReviewThreads = array of TGittanReviewThread;

  {** What a note of the pull request's conversation is: a comment of
    its own, or a submitted review with that outcome. }
  TGittanPullNoteKind = (pnComment, pnCommented, pnApproved, pnChangesRequested,
    pnDismissed);

  {** A note that is on no line: a comment in the pull request's
    conversation, or the text a review was submitted with (what a
    reviewer writes when requesting changes or approving). Created is in
    UTC, 0 when GitHub gave no time. }
  TGittanPullNote = record
    Kind: TGittanPullNoteKind;
    Author, Body, Url: string;
    Created: TDateTime;
  end;
  TGittanPullNotes = array of TGittanPullNote;

{** The line ALine of a file, counted in the old side of ADiff (what
  `git diff -U0` prints for the file), on the new side: shifted by the
  lines added and removed above it, or, for a line ADiff changes, the
  line in the same place of the change (its first line when the change
  only removes). An empty diff leaves the line alone. }
function MapLine(const ADiff: string; ALine: integer): integer;

{** How long ago AThen was at ANow, both in UTC, for the header of a
  comment: just now, 5 minutes ago, 3 hours ago, yesterday, 4 days ago,
  then the date. }
function ReviewAge(AThen, ANow: TDateTime): string;

{** The threads that are neither resolved nor outdated. }
function OpenThreads(const AThreads: TGittanReviewThreads): integer;

type
  {** Reads the review threads of pull request Number of RepoPath
    ("owner/name") and the notes of its conversation, every page of
    them, in a thread. OnDone is called in the main thread when it is
    done, as long as the job has not been stopped; Error is the forge's
    or its tool's message when it failed. A forge (gittan.forge) fills in
    Ask, which sets Threads, Notes and HeadOid through the protected
    fields. }
  TGittanReviewJob = class(TGittanJob)
  private
    FRoot, FRepoPath: string;
    FNumber: integer;
    FError: string;
  protected
    FThreads: TGittanReviewThreads;
    FNotes: TGittanPullNotes;
    FHeadOid: string;
    {** Reads the threads, the notes and the head commit; false with the
      reason in AError when they could not be read. May return early
      when Terminated. }
    function Ask(out AError: string): boolean; virtual; abstract;
    procedure Execute; override;
    property Root: string read FRoot;
  public
    constructor Create(const ARoot, ARepoPath: string; ANumber: integer);
    property Number: integer read FNumber;
    property RepoPath: string read FRepoPath;
    property Threads: TGittanReviewThreads read FThreads;
    {** The conversation, from the first page. }
    property Notes: TGittanPullNotes read FNotes;
    {** The commit at the head of the pull request. }
    property HeadOid: string read FHeadOid;
    property Error: string read FError;
  end;

implementation

uses
  Math, DateUtils;

{ "-12,3" or "+7" of a hunk header: the start and the count (1 when
  left out). }
function ReadRange(const S: string; out AStart, ACount: integer): boolean;
var
  p: integer;
begin
  p := Pos(',', S);
  if p = 0 then
  begin
    ACount := 1;
    Result := TryStrToInt(Copy(S, 2, MaxInt), AStart);
  end
  else
    Result := TryStrToInt(Copy(S, 2, p - 2), AStart) and
      TryStrToInt(Copy(S, p + 1, MaxInt), ACount);
end;

function MapLine(const ADiff: string; ALine: integer): integer;
var
  Lines, Parts: TStringList;
  i, OldStart, OldCount, NewStart, NewCount, OldNext, NewNext: integer;
begin
  Result := ALine;
  Lines := TStringList.Create;
  Parts := TStringList.Create;
  try
    Lines.Text := ADiff;
    Parts.Delimiter := ' ';
    Parts.StrictDelimiter := True;
    for i := 0 to Lines.Count - 1 do
    begin
      if Copy(Lines[i], 1, 3) <> '@@ ' then
        Continue;
      Parts.DelimitedText := Lines[i];
      if (Parts.Count < 3) or not ReadRange(Parts[1], OldStart, OldCount) or
        not ReadRange(Parts[2], NewStart, NewCount) then
        Continue;
      { The hunks come in order, so one past the line is past every
        change that moves it. A count of 0 gives the line before the
        change as its start. }
      if OldCount = 0 then
        OldNext := OldStart + 1
      else
        OldNext := OldStart + OldCount;
      if NewCount = 0 then
        NewNext := NewStart + 1
      else
        NewNext := NewStart + NewCount;
      if (OldCount > 0) and (ALine < OldStart) then
        Break;
      if (OldCount = 0) and (ALine <= OldStart) then
        Break;
      if ALine < OldNext then
      begin
        { A line the change replaced: its place among the new lines. }
        if NewCount > 0 then
          Result := NewStart + Min(ALine - OldStart, NewCount - 1)
        else
          Result := Max(1, NewStart);
        Exit;
      end;
      Result := ALine - OldNext + NewNext;
    end;
  finally
    Parts.Free;
    Lines.Free;
  end;
end;

function ReviewAge(AThen, ANow: TDateTime): string;
var
  Minutes: int64;
begin
  if AThen <= 0 then
    Exit('');
  Minutes := MinutesBetween(ANow, AThen);
  if (ANow < AThen) or (Minutes < 1) then
    Result := 'just now'
  else if Minutes = 1 then
    Result := '1 minute ago'
  else if Minutes < 60 then
    Result := IntToStr(Minutes) + ' minutes ago'
  else if Minutes < 120 then
    Result := '1 hour ago'
  else if Minutes < 24 * 60 then
    Result := IntToStr(Minutes div 60) + ' hours ago'
  else if Minutes < 48 * 60 then
    Result := 'yesterday'
  else if Minutes < 30 * 24 * 60 then
    Result := IntToStr(Minutes div (24 * 60)) + ' days ago'
  else
    Result := FormatDateTime('yyyy-mm-dd', AThen);
end;

function OpenThreads(const AThreads: TGittanReviewThreads): integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to High(AThreads) do
    if not AThreads[i].Resolved and not AThreads[i].Outdated then
      Inc(Result);
end;

{ ---------------------------------------------------------------------------
  The job
  --------------------------------------------------------------------------- }

constructor TGittanReviewJob.Create(const ARoot, ARepoPath: string; ANumber: integer);
begin
  inherited Create(True);
  FRoot := ARoot;
  FRepoPath := ARepoPath;
  FNumber := ANumber;
end;

procedure TGittanReviewJob.Execute;
begin
  if not Ask(FError) and (FError = '') then
    FError := 'Could not read the review comments.';
  if not Terminated then
    Done;
end;

end.
