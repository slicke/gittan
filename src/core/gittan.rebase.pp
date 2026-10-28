unit gittan.rebase;

{** An interactive rebase as a list of steps: the commits a rebase
  replays, oldest first as git applies them, each with what to do with
  it (pick, reword, edit, squash, fixup or drop) and the message to
  commit it with. BuildRebaseTodo turns the steps into the todo list
  git rebase -i reads, which Gittan hands git through
  GIT_SEQUENCE_EDITOR instead of an editor (see TGittanRepo.
  RebaseInteractive). No step needs an editor while the rebase runs: a
  reword is a pick followed by an exec line that amends the commit
  with its message from a file written beside the todo, and a squash
  is a fixup (which keeps the earlier commit's message without asking)
  followed by the same exec with the messages joined, as git's own
  squash joins them. So the rebase runs through, or stops only where
  git stops anyway: at an edit, or with conflicts. No LCL; tested in
  tests/testrebase.pp. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types;

type
  {** What the rebase does with a commit, as git's todo list names
    them: raPick replays it, raReword with another message, raEdit
    stops after it so it can be amended, raSquash folds it into the
    kept commit before it with the messages joined, raFixup folds it
    in and drops its message, raDrop leaves it out. }
  TGittanRebaseAction = (raPick, raReword, raEdit, raSquash, raFixup, raDrop);

  {** A commit the rebase replays: what git log gives (the id, the
    short id, the author, the time in UTC, the subject and the rest of
    the message), whether it is on the branch's upstream already
    (Pushed, so the push after rewriting it must be forced), the
    action and Message, the message it is committed with: its own
    (OriginalMessage) until the user changes it. }
  TGittanRebaseStep = record
    Hash, Short, Author, Subject, Body: string;
    Date: TDateTime;
    Pushed: boolean;
    Action: TGittanRebaseAction;
    Message: string;
  end;
  TGittanRebaseSteps = array of TGittanRebaseStep;

  {** A file BuildRebaseTodo wants written in the folder beside the
    todo: a commit message an exec line reads with -F. }
  TGittanRebaseFile = record
    Name: string;
    Text: string;
  end;
  TGittanRebaseFiles = array of TGittanRebaseFile;

{** The action's name in the todo list ("pick", "reword", ...). }
function RebaseActionName(AAction: TGittanRebaseAction): string;

{** The commit's own message: the subject, then the body after a blank
  line when there is one. }
function OriginalMessage(const AStep: TGittanRebaseStep): string;

{** Whether the message is the commit's own, blank lines at the end
  and spaces at the ends of lines aside, as git's cleanup leaves them. }
function MessageUnchanged(const AStep: TGittanRebaseStep): boolean;

{** Whether the steps can be run: a squash or fixup needs a commit
  kept before it (in replay order) to fold into. AError says what is
  wrong, naming the step by its short id. }
function CheckRebaseSteps(const ASteps: TGittanRebaseSteps; out AError: string): boolean;

{** The todo list for ASteps, oldest first, and in AFiles the message
  files the exec lines read, to be written in AFolder (an absolute
  path, quoted for the shell git runs exec lines with). A step with a
  message of its own, or with squashes folded in, is amended with the
  message after it is picked. }
function BuildRebaseTodo(const ASteps: TGittanRebaseSteps; const AFolder: string;
  out AFiles: TGittanRebaseFiles): string;

{** APath in double quotes for sh, the shell git runs exec lines with
  on every platform: a backslash, a double quote, a dollar sign and a
  backquote are escaped, which is all sh reads inside double quotes. }
function ShellQuote(const APath: string): string;

{** The messages of a kept step and the squashes folded into it, as
  git's squash joins them: each one that is not blank, a blank line
  between them. }
function JoinedMessage(const AMessages: array of string): string;

{** What a fixup commit's subject names: "fixup! <text>" or
  "squash! <text>" (more than one prefix allowed, as git commit
  --fixup of a fixup writes) gives the text and the action the first
  prefix asks for; another subject gives '' and raPick. }
function FixupTarget(const ASubject: string; out AAction: TGittanRebaseAction): string;

{** Moves the fixup and squash commits (by their subjects, as git
  rebase --autosquash does) after the commit each one names, after the
  ones moved there before it, with raFixup or raSquash as its action
  and, for a squash, the prefix taken off its message. The commit
  named is an earlier step (in replay order) that is no fixup itself,
  with that subject, else whose subject starts with the text, else
  whose id starts with it (four hex digits or more); a fixup of a
  fixup follows it to its commit. One that names no step stays where
  it is, a pick. The actions of the steps not moved stay. }
procedure AutosquashSteps(var ASteps: TGittanRebaseSteps);

implementation

function RebaseActionName(AAction: TGittanRebaseAction): string;
begin
  case AAction of
    raPick: Result := 'pick';
    raReword: Result := 'reword';
    raEdit: Result := 'edit';
    raSquash: Result := 'squash';
    raFixup: Result := 'fixup';
    else
      Result := 'drop';
  end;
end;

function OriginalMessage(const AStep: TGittanRebaseStep): string;
begin
  Result := AStep.Subject;
  if TrimRight(AStep.Body) <> '' then
    Result := Result + LineEnding + LineEnding + TrimRight(AStep.Body);
end;

{ Lines compared with their ends trimmed and the blank ones at the end
  dropped, on either line ending. }
function Cleaned(const AText: string): string;
var
  Lines: TStringArray;
  i: integer;
begin
  Lines := StringReplace(AText, #13#10, #10, [rfReplaceAll]).Split([#10]);
  Result := '';
  for i := 0 to High(Lines) do
    Lines[i] := TrimRight(Lines[i]);
  i := High(Lines);
  while (i >= 0) and (Lines[i] = '') do
    Dec(i);
  Result := string.Join(#10, Lines, 0, i + 1);
end;

function MessageUnchanged(const AStep: TGittanRebaseStep): boolean;
begin
  Result := Cleaned(AStep.Message) = Cleaned(OriginalMessage(AStep));
end;

function CheckRebaseSteps(const ASteps: TGittanRebaseSteps; out AError: string): boolean;
var
  i: integer;
  Kept: boolean;
begin
  AError := '';
  Kept := False;
  for i := 0 to High(ASteps) do
    case ASteps[i].Action of
      raPick, raReword, raEdit:
        Kept := True;
      raSquash, raFixup:
        if not Kept then
        begin
          AError := Format('%s cannot be folded into an earlier commit: there is none kept before it.',
            [ASteps[i].Short]);
          Exit(False);
        end;
    end;
  Result := True;
end;

function ShellQuote(const APath: string): string;
var
  i: integer;
begin
  Result := '"';
  for i := 1 to Length(APath) do
  begin
    if APath[i] in ['\', '"', '$', '`'] then
      Result := Result + '\';
    Result := Result + APath[i];
  end;
  Result := Result + '"';
end;

function JoinedMessage(const AMessages: array of string): string;
var
  i: integer;
  Part: string;
begin
  Result := '';
  for i := 0 to High(AMessages) do
  begin
    Part := Cleaned(AMessages[i]);
    if Trim(Part) = '' then
      Continue;
    if Result <> '' then
      Result := Result + #10 + #10;
    Result := Result + Part;
  end;
end;

function FixupTarget(const ASubject: string; out AAction: TGittanRebaseAction): string;
var
  Found: boolean;
begin
  Result := ASubject;
  AAction := raPick;
  repeat
    Found := False;
    if Copy(Result, 1, 7) = 'fixup! ' then
    begin
      if AAction = raPick then
        AAction := raFixup;
      Delete(Result, 1, 7);
      Found := True;
    end
    else if Copy(Result, 1, 8) = 'squash! ' then
    begin
      if AAction = raPick then
        AAction := raSquash;
      Delete(Result, 1, 8);
      Found := True;
    end;
  until not Found;
  Result := Trim(Result);
  if AAction = raPick then
    Result := '';
end;

{ Whether AText is a prefix of an id: hex digits, four or more. }
function LooksLikeId(const AText: string): boolean;
var
  i: integer;
begin
  Result := Length(AText) >= 4;
  for i := 1 to Length(AText) do
    if not (AText[i] in ['0'..'9', 'a'..'f', 'A'..'F']) then
      Exit(False);
end;

procedure AutosquashSteps(var ASteps: TGittanRebaseSteps);
var
  Target: array of integer;
  Action: array of TGittanRebaseAction;
  Text: string;
  i, j, k: integer;
  Done: TGittanRebaseSteps;

  { The earlier step the text names, -1 for none. }
  function Find(const AText: string; ABefore: integer): integer;
  var
    n: integer;
  begin
    for n := 0 to ABefore - 1 do
      if (Target[n] < 0) and (Action[n] = raPick) and (ASteps[n].Subject = AText) then
        Exit(n);
    for n := 0 to ABefore - 1 do
      if (Target[n] < 0) and (Action[n] = raPick) and
        (Copy(ASteps[n].Subject, 1, Length(AText)) = AText) then
        Exit(n);
    if LooksLikeId(AText) then
      for n := 0 to ABefore - 1 do
        if (Target[n] < 0) and (Action[n] = raPick) and
          SameText(Copy(ASteps[n].Hash, 1, Length(AText)), AText) then
          Exit(n);
    Result := -1;
  end;

begin
  SetLength(Target, Length(ASteps));
  SetLength(Action, Length(ASteps));
  for i := 0 to High(ASteps) do
  begin
    Target[i] := -1;
    FixupTarget(ASteps[i].Subject, Action[i]);
  end;
  { Each fixup names an earlier commit, through a fixup of a fixup. }
  for i := 0 to High(ASteps) do
  begin
    if Action[i] = raPick then
      Continue;
    Text := FixupTarget(ASteps[i].Subject, Action[i]);
    j := Find(Text, i);
    if j < 0 then
      for k := 0 to i - 1 do
        if (Action[k] <> raPick) and (FixupTarget(ASteps[k].Subject, Action[k]) = Text) and
          (Target[k] >= 0) then
        begin
          j := Target[k];
          Break;
        end;
    if j < 0 then
      Continue;
    Target[i] := j;
    ASteps[i].Action := Action[i];
    if Action[i] = raSquash then
      ASteps[i].Message := Text + Copy(ASteps[i].Message, Length(ASteps[i].Subject) + 1, MaxInt);
  end;
  Done := nil;
  for i := 0 to High(ASteps) do
  begin
    if Target[i] >= 0 then
      Continue;
    SetLength(Done, Length(Done) + 1);
    Done[High(Done)] := ASteps[i];
    for j := i + 1 to High(ASteps) do
      if Target[j] = i then
      begin
        SetLength(Done, Length(Done) + 1);
        Done[High(Done)] := ASteps[j];
      end;
  end;
  ASteps := Done;
end;

{ A step's line: the command, the id and the subject, which git shows
  but does not read back. }
function TodoLine(const ACommand: string; const AStep: TGittanRebaseStep): string;
begin
  Result := ACommand + ' ' + AStep.Hash + ' ' + AStep.Subject + #10;
end;

function BuildRebaseTodo(const ASteps: TGittanRebaseSteps; const AFolder: string;
  out AFiles: TGittanRebaseFiles): string;
var
  i, j: integer;
  Messages: array of string;
  NeedMessage: boolean;
  Folder: string;

  procedure AddFile(const AText: string);
  begin
    SetLength(AFiles, Length(AFiles) + 1);
    AFiles[High(AFiles)].Name := Format('msg-%d.txt', [Length(AFiles)]);
    AFiles[High(AFiles)].Text := AText + #10;
    Result := Result + 'exec git commit --amend --allow-empty -F ' +
      ShellQuote(Folder + AFiles[High(AFiles)].Name) + #10;
  end;

begin
  Result := '';
  AFiles := nil;
  Folder := AFolder;
  if (Folder <> '') and not (Folder[Length(Folder)] in ['/', '\']) then
    Folder := Folder + '/';
  i := 0;
  while i <= High(ASteps) do
  begin
    case ASteps[i].Action of
      raDrop:
        Result := Result + TodoLine('drop', ASteps[i]);
      raSquash, raFixup:
        { Without a kept commit before it (CheckRebaseSteps refuses that)
          it would fold into nothing; left out. }
        Result := Result + TodoLine('drop', ASteps[i]);
      else
      begin
        if ASteps[i].Action = raEdit then
          Result := Result + TodoLine('edit', ASteps[i])
        else
          Result := Result + TodoLine('pick', ASteps[i]);
        { A reword with the commit's own message changes nothing. }
        NeedMessage := not MessageUnchanged(ASteps[i]);
        SetLength(Messages, 1);
        Messages[0] := ASteps[i].Message;
        { The squashes and fixups that follow fold into this commit; a
          drop between them is dropped where it stands. }
        j := i + 1;
        while (j <= High(ASteps)) and (ASteps[j].Action in [raSquash, raFixup, raDrop]) do
        begin
          case ASteps[j].Action of
            raDrop:
              Result := Result + TodoLine('drop', ASteps[j]);
            raFixup:
              Result := Result + TodoLine('fixup', ASteps[j]);
            raSquash:
            begin
              Result := Result + TodoLine('fixup', ASteps[j]);
              SetLength(Messages, Length(Messages) + 1);
              Messages[High(Messages)] := ASteps[j].Message;
              NeedMessage := True;
            end;
          end;
          Inc(j);
        end;
        if NeedMessage then
          AddFile(JoinedMessage(Messages));
        i := j;
        Continue;
      end;
    end;
    Inc(i);
  end;
end;

end.
