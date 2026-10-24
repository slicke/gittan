unit gittan.reviews;

{** The review comments of a pull request: its threads as GitHub's
  GraphQL API gives them through gh, the notes of its conversation that
  are on no line, a job that fetches them in a
  thread, and the mapping of a line of the pull request's head to the
  same line in the work tree. Nothing here needs the LCL. }

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

const
  {** The GraphQL query for one page of the threads of a pull request;
    $after is the cursor of the page before, left out for the first. }
  ReviewThreadsQuery =
    'query($owner:String!,$name:String!,$number:Int!,$after:String){' +
    'repository(owner:$owner,name:$name){pullRequest(number:$number){' +
    'headRefOid reviews(last:100){nodes{state body author{login} submittedAt url}} ' +
    'comments(last:100){nodes{author{login} body createdAt url}} ' +
    'reviewThreads(first:100,after:$after){' +
    'pageInfo{hasNextPage endCursor} nodes{' +
    'isResolved isOutdated path line startLine originalLine diffSide subjectType ' +
    'comments(first:100){nodes{author{login} body createdAt url}}}}}}}';

{** Reads one page of the answer to ReviewThreadsQuery and adds its
  threads to AThreads. AHeadOid is the commit at the head of the pull
  request; ACursor the cursor of the next page when AHasNext. False when
  the text is not such an answer. }
function ParseReviewThreads(const AJson: string; var AThreads: TGittanReviewThreads;
  out AHeadOid: string; out AHasNext: boolean; out ACursor: string): boolean;

{** Reads the conversation of the pull request from an answer to
  ReviewThreadsQuery into ANotes, oldest first: its comments, and its
  reviews that were submitted with text or that approved, requested
  changes or were dismissed; a review that only commented on lines has
  nothing to show here, and a pending one is not submitted yet. False
  when the text is not such an answer. }
function ParsePullNotes(const AJson: string; out ANotes: TGittanPullNotes): boolean;

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
  {** Fetches the review threads of pull request ANumber of ARepoPath
    ("owner/repo") with gh, every page of them, in a thread. OnDone is
    called in the main thread when it is done, as long as the job has
    not been stopped; Error is gh's message when it failed. }
  TGittanReviewJob = class(TGittanJob)
  private
    FExe, FRoot, FRepoPath: string;
    FNumber: integer;
    FThreads: TGittanReviewThreads;
    FNotes: TGittanPullNotes;
    FHeadOid, FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const AExe, ARoot, ARepoPath: string; ANumber: integer);
    property Number: integer read FNumber;
    property RepoPath: string read FRepoPath;
    property Threads: TGittanReviewThreads read FThreads;
    {** The conversation, from the first page. }
    property Notes: TGittanPullNotes read FNotes;
    property HeadOid: string read FHeadOid;
    property Error: string read FError;
  end;

implementation

uses
  Math, fpjson, jsonparser, DateUtils, gittan.git;

{ A path through nested objects, nil when a step is missing or not an
  object. }
function Dig(AData: TJSONData; const ANames: array of string): TJSONData;
var
  i: integer;
begin
  Result := AData;
  for i := 0 to High(ANames) do
  begin
    if (Result = nil) or (Result.JSONType <> jtObject) then
      Exit(nil);
    Result := TJSONObject(Result).Find(ANames[i]);
  end;
end;

{ An integer field that may be null. }
function IntOf(AObject: TJSONObject; const AName: string): integer;
var
  Data: TJSONData;
begin
  Data := AObject.Find(AName);
  if (Data <> nil) and (Data.JSONType = jtNumber) then
    Result := Data.AsInteger
  else
    Result := 0;
end;

function StrOf(AObject: TJSONObject; const AName: string): string;
var
  Data: TJSONData;
begin
  Data := AObject.Find(AName);
  if (Data <> nil) and (Data.JSONType = jtString) then
    Result := Data.AsString
  else
    Result := '';
end;

{ The login of a comment's author; a deleted account has none. }
function AuthorOf(AObject: TJSONObject): string;
var
  Author: TJSONData;
begin
  Result := '';
  Author := AObject.Find('author');
  if (Author <> nil) and (Author.JSONType = jtObject) then
    Result := StrOf(TJSONObject(Author), 'login');
  if Result = '' then
    Result := 'ghost';
end;

function BodyOf(AObject: TJSONObject): string;
begin
  Result := StringReplace(StrOf(AObject, 'body'), #13#10, #10, [rfReplaceAll]);
end;

function TimeOf(AObject: TJSONObject; const AName: string): TDateTime;
begin
  if not TryISO8601ToDate(StrOf(AObject, AName), Result, True) then
    Result := 0;
end;

function ReadComment(AObject: TJSONObject): TGittanReviewComment;
begin
  Result := Default(TGittanReviewComment);
  Result.Author := AuthorOf(AObject);
  Result.Body := BodyOf(AObject);
  Result.Url := StrOf(AObject, 'url');
  Result.Created := TimeOf(AObject, 'createdAt');
end;

function ReadThread(AObject: TJSONObject; out AThread: TGittanReviewThread): boolean;
var
  Nodes: TJSONData;
  i, n: integer;
begin
  AThread := Default(TGittanReviewThread);
  AThread.Path := StrOf(AObject, 'path');
  Result := AThread.Path <> '';
  if not Result then
    Exit;
  AThread.Line := IntOf(AObject, 'line');
  AThread.StartLine := IntOf(AObject, 'startLine');
  AThread.OriginalLine := IntOf(AObject, 'originalLine');
  AThread.LeftSide := StrOf(AObject, 'diffSide') = 'LEFT';
  AThread.Resolved := AObject.Get('isResolved', False);
  AThread.Outdated := AObject.Get('isOutdated', False);
  AThread.OnFile := StrOf(AObject, 'subjectType') = 'FILE';
  if AThread.OnFile then
    AThread.Line := 0;
  Nodes := Dig(AObject, ['comments', 'nodes']);
  if (Nodes = nil) or (Nodes.JSONType <> jtArray) then
    Exit;
  SetLength(AThread.Comments, Nodes.Count);
  n := 0;
  for i := 0 to Nodes.Count - 1 do
    if Nodes.Items[i].JSONType = jtObject then
    begin
      AThread.Comments[n] := ReadComment(TJSONObject(Nodes.Items[i]));
      Inc(n);
    end;
  SetLength(AThread.Comments, n);
end;

function ParseReviewThreads(const AJson: string; var AThreads: TGittanReviewThreads;
  out AHeadOid: string; out AHasNext: boolean; out ACursor: string): boolean;
var
  Data, Pull, Threads, Info, Nodes: TJSONData;
  Thread: TGittanReviewThread;
  i: integer;
begin
  AHeadOid := '';
  AHasNext := False;
  ACursor := '';
  Result := False;
  try
    Data := GetJSON(AJson);
  except
    Exit;
  end;
  try
    Pull := Dig(Data, ['data', 'repository', 'pullRequest']);
    if (Pull = nil) or (Pull.JSONType <> jtObject) then
      Exit;
    AHeadOid := StrOf(TJSONObject(Pull), 'headRefOid');
    Threads := Dig(Pull, ['reviewThreads']);
    if (Threads = nil) or (Threads.JSONType <> jtObject) then
      Exit;
    Info := Dig(Threads, ['pageInfo']);
    if (Info <> nil) and (Info.JSONType = jtObject) then
    begin
      AHasNext := TJSONObject(Info).Get('hasNextPage', False);
      ACursor := StrOf(TJSONObject(Info), 'endCursor');
      AHasNext := AHasNext and (ACursor <> '');
    end;
    Nodes := Dig(Threads, ['nodes']);
    if (Nodes <> nil) and (Nodes.JSONType = jtArray) then
      for i := 0 to Nodes.Count - 1 do
        if (Nodes.Items[i].JSONType = jtObject) and
          ReadThread(TJSONObject(Nodes.Items[i]), Thread) and (Length(Thread.Comments) > 0) then
        begin
          SetLength(AThreads, Length(AThreads) + 1);
          AThreads[High(AThreads)] := Thread;
        end;
    Result := True;
  finally
    Data.Free;
  end;
end;

function ParsePullNotes(const AJson: string; out ANotes: TGittanPullNotes): boolean;
var
  Data, Pull, Nodes: TJSONData;
  Node: TJSONObject;
  Note: TGittanPullNote;
  State: string;
  i, j: integer;

  procedure Add;
  begin
    SetLength(ANotes, Length(ANotes) + 1);
    ANotes[High(ANotes)] := Note;
  end;

begin
  ANotes := nil;
  Result := False;
  try
    Data := GetJSON(AJson);
  except
    Exit;
  end;
  try
    Pull := Dig(Data, ['data', 'repository', 'pullRequest']);
    if (Pull = nil) or (Pull.JSONType <> jtObject) then
      Exit;
    Nodes := Dig(Pull, ['comments', 'nodes']);
    if (Nodes <> nil) and (Nodes.JSONType = jtArray) then
      for i := 0 to Nodes.Count - 1 do
        if Nodes.Items[i].JSONType = jtObject then
        begin
          Node := TJSONObject(Nodes.Items[i]);
          Note := Default(TGittanPullNote);
          Note.Kind := pnComment;
          Note.Author := AuthorOf(Node);
          Note.Body := Trim(BodyOf(Node));
          Note.Url := StrOf(Node, 'url');
          Note.Created := TimeOf(Node, 'createdAt');
          if Note.Body <> '' then
            Add;
        end;
    Nodes := Dig(Pull, ['reviews', 'nodes']);
    if (Nodes <> nil) and (Nodes.JSONType = jtArray) then
      for i := 0 to Nodes.Count - 1 do
        if Nodes.Items[i].JSONType = jtObject then
        begin
          Node := TJSONObject(Nodes.Items[i]);
          Note := Default(TGittanPullNote);
          State := StrOf(Node, 'state');
          if State = 'APPROVED' then
            Note.Kind := pnApproved
          else if State = 'CHANGES_REQUESTED' then
            Note.Kind := pnChangesRequested
          else if State = 'DISMISSED' then
            Note.Kind := pnDismissed
          else if State = 'COMMENTED' then
            Note.Kind := pnCommented
          else
            Continue;
          Note.Author := AuthorOf(Node);
          Note.Body := Trim(BodyOf(Node));
          Note.Url := StrOf(Node, 'url');
          Note.Created := TimeOf(Node, 'submittedAt');
          if (Note.Body <> '') or (Note.Kind <> pnCommented) then
            Add;
        end;
    { Comments and reviews each come in order; together they are sorted
      by time, keeping that order among equal times. }
    for i := 1 to High(ANotes) do
    begin
      Note := ANotes[i];
      j := i - 1;
      while (j >= 0) and (ANotes[j].Created > Note.Created) do
      begin
        ANotes[j + 1] := ANotes[j];
        Dec(j);
      end;
      ANotes[j + 1] := Note;
    end;
    Result := True;
  finally
    Data.Free;
  end;
end;

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

constructor TGittanReviewJob.Create(const AExe, ARoot, ARepoPath: string; ANumber: integer);
begin
  inherited Create(True);
  FExe := AExe;
  FRoot := ARoot;
  FRepoPath := ARepoPath;
  FNumber := ANumber;
end;

procedure TGittanReviewJob.Execute;
var
  Owner, Name, Output, Err, Cursor, Head: string;
  HasNext: boolean;
  Pages, p: integer;
begin
  p := Pos('/', FRepoPath);
  Owner := Copy(FRepoPath, 1, p - 1);
  Name := Copy(FRepoPath, p + 1, MaxInt);
  Cursor := '';
  Pages := 0;
  repeat
    { -f passes the names as strings even when they look like numbers;
      -F types the number. }
    if Cursor = '' then
      HasNext := RunGitHubCli(FExe, FRoot, ['api', 'graphql', '-f', 'owner=' + Owner,
        '-f', 'name=' + Name, '-F', 'number=' + IntToStr(FNumber),
        '-f', 'query=' + ReviewThreadsQuery], Output, Err)
    else
      HasNext := RunGitHubCli(FExe, FRoot, ['api', 'graphql', '-f', 'owner=' + Owner,
        '-f', 'name=' + Name, '-F', 'number=' + IntToStr(FNumber),
        '-f', 'after=' + Cursor, '-f', 'query=' + ReviewThreadsQuery], Output, Err);
    if Terminated then
      Exit;
    if not HasNext then
    begin
      FError := Err;
      Break;
    end;
    if not ParseReviewThreads(Output, FThreads, Head, HasNext, Cursor) then
    begin
      FError := 'Could not read the review comments gh fetched.';
      Break;
    end;
    if Pages = 0 then
    begin
      FHeadOid := Head;
      ParsePullNotes(Output, FNotes);
    end;
    Inc(Pages);
  until not HasNext or (Pages >= 20);
  Done;
end;

end.
