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
  {** What a part of a comment's body is: Markdown, or a <details> block
    (its summary). }
  TGittanCommentPartKind = (cpText, cpDetails);

  {** A part of a comment's body. Text is Markdown, or for a cpDetails
    its summary, on one line ("Details" when it has none). A cpDetails
    at Depth d holds the parts after it deeper than d, up to the next
    one at d or above. }
  TGittanCommentPart = record
    Kind: TGittanCommentPartKind;
    Depth: integer;
    Text: string;
  end;
  TGittanCommentParts = array of TGittanCommentPart;

{** A comment's body as a card shows it, cut at its <details> blocks,
  the HTML a bot writes in it (CodeRabbit's, say) made Markdown or taken
  out: HTML comments go, an <img> becomes its alt text, an <a href> a
  Markdown link, and the block tags (p, div, table, lists, headings and
  the like) go with a line break or a blank line in their place; a
  heading is bold, as a card has no room for a big one. Code (fenced or
  between backticks) is left as it is, and inline tags and anything
  else that looks like a tag (Vec<T>) are left for the Markdown
  converter to pass or show. }
function CommentParts(const ABody: string): TGittanCommentParts;

{** The Markdown of a comment's body with its <details> blocks folded:
  the parts of CommentParts at the top, a block as "▸ " and its summary
  on a line of its own. }
function CommentMarkdown(const ABody: string): string;

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
  The body as a card shows it
  --------------------------------------------------------------------------- }

{ The value of attribute AName in the tag ATag ("<img alt="x" ...>"),
  quoted with " or ' or not at all; '' when it has none. }
function TagAttr(const ATag, AName: string): string;
var
  L: string;
  p, q: integer;
  Quote: char;
begin
  Result := '';
  L := LowerCase(ATag);
  p := Pos(' ' + AName + '=', L);
  if p = 0 then
    Exit;
  Inc(p, Length(AName) + 2);
  if (p <= Length(ATag)) and (ATag[p] in ['"', '''']) then
  begin
    Quote := ATag[p];
    Inc(p);
    q := p;
    while (q <= Length(ATag)) and (ATag[q] <> Quote) do
      Inc(q);
  end
  else
  begin
    q := p;
    while (q <= Length(ATag)) and not (ATag[q] in [' ', '>', '/']) do
      Inc(q);
  end;
  Result := Copy(ATag, p, q - p);
end;

function CommentParts(const ABody: string): TGittanCommentParts;
const
  { Tags that stand for a blank line, and for a line break. }
  ParaTags: array[0..13] of string = ('p', 'div', 'table', 'blockquote', 'ul', 'ol',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'center', 'hr');
  LineTags: array[0..2] of string = ('tr', 'li', 'dt');
  { Tags that go without a trace. }
  GoneTags: array[0..8] of string = ('td', 'th', 'thead', 'tbody', 'tfoot', 'picture',
    'source', 'dd', 'dl');
var
  Lines: TStringList;
  Out, Summary, Href, Tag, Name, S, Fence: string;
  i, p, q, Depth: integer;
  InComment, InSummary, Closing: boolean;
  { The parts of the <details> blocks open, innermost last. }
  Open: array of integer;

  function IsIn(const AName: string; const AList: array of string): boolean;
  var
    k: integer;
  begin
    for k := 0 to High(AList) do
      if AList[k] = AName then
        Exit(True);
    Result := False;
  end;

  { Text that goes to the part being read, or to the summary being
    read. }
  procedure Emit(const AText: string);
  begin
    if InSummary then
      Summary := Summary + AText
    else
      Out := Out + AText;
  end;

  { The fence a line opens or closes, ``` or ~~~ and longer; '' for a
    line that is not one. }
  function FenceOf(const ALine: string): string;
  var
    T: string;
    n: integer;
  begin
    Result := '';
    T := TrimLeft(ALine);
    if (Length(ALine) - Length(T) > 3) or (Length(T) < 3) or not (T[1] in ['`', '~']) then
      Exit;
    n := 1;
    while (n < Length(T)) and (T[n + 1] = T[1]) do
      Inc(n);
    if n >= 3 then
      Result := Copy(T, 1, n);
  end;

  { AText with one blank line between paragraphs, none at the start or
    the end, since what was taken out leaves blank lines, and its
    headings bold. Code keeps its own. }
  function Tidy(const AText: string): string;
  var
    L: TStringList;
    T, Last, Code: string;
    k, n: integer;
  begin
    Result := '';
    L := TStringList.Create;
    try
      L.Text := AText;
      Code := '';
      Last := '';
      for k := 0 to L.Count - 1 do
      begin
        if Code <> '' then
        begin
          if (FenceOf(L[k]) <> '') and (Copy(TrimLeft(L[k]), 1, Length(Code)) = Code) then
            Code := '';
        end
        else
        begin
          if Trim(L[k]) = '' then
          begin
            if (Result <> '') and (Last <> '') then
              Result := Result + LineEnding;
            Last := '';
            Continue;
          end;
          Code := FenceOf(L[k]);
          { A heading is bold text: a card has no room for a big one. }
          if Code = '' then
          begin
            T := TrimLeft(L[k]);
            n := 1;
            while (n <= Length(T)) and (n <= 6) and (T[n] = '#') do
              Inc(n);
            if (n > 1) and (n <= Length(T)) and (T[n] = ' ') and
              (Length(L[k]) - Length(T) < 4) then
            begin
              T := Trim(Copy(T, n + 1, MaxInt));
              while (T <> '') and (T[Length(T)] = '#') do
                Delete(T, Length(T), 1);
              L[k] := '**' + Trim(T) + '**';
            end;
          end;
        end;
        Last := L[k];
        Result := Result + L[k] + LineEnding;
      end;
      Result := TrimRight(Result);
    finally
      L.Free;
    end;
  end;

  { The text read so far as a part at the depth it is in. }
  procedure Flush;
  begin
    Out := Tidy(Out);
    if Out <> '' then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].Kind := cpText;
      Result[High(Result)].Depth := Depth;
      Result[High(Result)].Text := Out;
    end;
    Out := '';
  end;

begin
  Result := nil;
  Open := nil;
  Out := '';
  Summary := '';
  Href := '';
  Fence := '';
  Depth := 0;
  InComment := False;
  InSummary := False;
  Lines := TStringList.Create;
  try
    Lines.Text := ABody;
    for i := 0 to Lines.Count - 1 do
    begin
      S := Lines[i];
      { A line of code, or the fence around it, as it is. }
      if not InComment then
      begin
        if Fence <> '' then
        begin
          if (FenceOf(S) <> '') and (Copy(TrimLeft(S), 1, Length(Fence)) = Fence) and
            (Trim(Copy(TrimLeft(S), Length(Fence) + 1, MaxInt)) = '') then
            Fence := '';
          Emit(S + LineEnding);
          Continue;
        end;
        if FenceOf(S) <> '' then
        begin
          Fence := FenceOf(S);
          Emit(S + LineEnding);
          Continue;
        end;
      end;
      p := 1;
      while p <= Length(S) do
      begin
        if InComment then
        begin
          q := Pos('-->', Copy(S, p, MaxInt));
          if q = 0 then
            p := Length(S) + 1
          else
          begin
            Inc(p, q + 2);
            InComment := False;
          end;
          Continue;
        end;
        if Copy(S, p, 4) = '<!--' then
        begin
          InComment := True;
          Inc(p, 4);
          Continue;
        end;
        { A code span, as it is. }
        if S[p] = '`' then
        begin
          q := p + 1;
          while (q <= Length(S)) and (S[q] <> '`') do
            Inc(q);
          if q > Length(S) then
          begin
            Emit(Copy(S, p, MaxInt));
            Break;
          end;
          Emit(Copy(S, p, q - p + 1));
          p := q + 1;
          Continue;
        end;
        if S[p] <> '<' then
        begin
          Emit(S[p]);
          Inc(p);
          Continue;
        end;
        { A tag: "<", maybe "/", a name, anything up to ">" on the line. }
        q := p + 1;
        Closing := (q <= Length(S)) and (S[q] = '/');
        if Closing then
          Inc(q);
        Name := '';
        while (q <= Length(S)) and (S[q] in ['a'..'z', 'A'..'Z', '0'..'9']) and
          ((Name <> '') or (S[q] in ['a'..'z', 'A'..'Z'])) do
        begin
          Name := Name + LowerCase(S[q]);
          Inc(q);
        end;
        while (q <= Length(S)) and (S[q] <> '>') and (S[q] <> '<') do
          Inc(q);
        if (Name = '') or (q > Length(S)) or (S[q] <> '>') or
          not ((S[p + 1 + Ord(Closing) + Length(Name)] in [' ', '>', '/', #9])) then
        begin
          Emit('<');
          Inc(p);
          Continue;
        end;
        Tag := Copy(S, p, q - p + 1);
        p := q + 1;
        if Name = 'details' then
        begin
          InSummary := False;
          if not Closing then
          begin
            Flush;
            SetLength(Result, Length(Result) + 1);
            Result[High(Result)].Kind := cpDetails;
            Result[High(Result)].Depth := Depth;
            Result[High(Result)].Text := '';
            SetLength(Open, Length(Open) + 1);
            Open[High(Open)] := High(Result);
            Inc(Depth);
          end
          else if Depth > 0 then
          begin
            Flush;
            SetLength(Open, Length(Open) - 1);
            Dec(Depth);
          end;
        end
        else if Name = 'summary' then
        begin
          if not Closing and (Length(Open) > 0) then
          begin
            InSummary := True;
            Summary := '';
          end
          else if Closing and InSummary then
          begin
            InSummary := False;
            Result[Open[High(Open)]].Text :=
              Trim(StringReplace(Summary, LineEnding, ' ', [rfReplaceAll]));
          end;
        end
        else if Name = 'img' then
          Emit(TagAttr(Tag, 'alt'))
        else if Name = 'a' then
        begin
          if not Closing then
          begin
            Href := TagAttr(Tag, 'href');
            if Href <> '' then
              Emit('[');
          end
          else if Href <> '' then
          begin
            Emit('](' + Href + ')');
            Href := '';
          end;
        end
        else if Name = 'br' then
          Emit('<br>')
        else if IsIn(Name, ParaTags) then
          Emit(LineEnding + LineEnding)
        else if IsIn(Name, LineTags) then
        begin
          Emit(LineEnding);
          if (Name = 'li') and not Closing then
            Emit('- ');
        end
        else if IsIn(Name, GoneTags) then
          Emit(' ')
        else
          Emit(Tag);
      end;
      Emit(LineEnding);
    end;
  finally
    Lines.Free;
  end;
  { A <details> left open holds the rest. }
  Flush;
  for i := 0 to High(Result) do
    if (Result[i].Kind = cpDetails) and (Result[i].Text = '') then
      Result[i].Text := 'Details';
end;

function CommentMarkdown(const ABody: string): string;
var
  Parts: TGittanCommentParts;
  i: integer;
begin
  Result := '';
  Parts := CommentParts(ABody);
  for i := 0 to High(Parts) do
    if Parts[i].Depth = 0 then
    begin
      if Result <> '' then
        Result := Result + LineEnding + LineEnding;
      if Parts[i].Kind = cpDetails then
        Result := Result + '▸ ' + Parts[i].Text
      else
        Result := Result + Parts[i].Text;
    end;
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
