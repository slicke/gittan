unit testrebase;

{** Tests of gittan.rebase: the todo list of an interactive rebase and
  the message files beside it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.rebase;

type
  TRebaseTest = class(TTestCase)
  private
    FSteps: TGittanRebaseSteps;
    FFiles: TGittanRebaseFiles;
    procedure Add(const AHash, ASubject, ABody: string; AAction: TGittanRebaseAction);
    function Todo: string;
  protected
    procedure SetUp; override;
  published
    procedure TestPicks;
    procedure TestReword;
    procedure TestChangedMessageIsReword;
    procedure TestSquash;
    procedure TestFixup;
    procedure TestDropBetween;
    procedure TestEdit;
    procedure TestCheck;
    procedure TestShellQuote;
    procedure TestJoinedMessage;
    procedure TestOriginalMessage;
  end;

implementation

procedure TRebaseTest.SetUp;
begin
  FSteps := nil;
  FFiles := nil;
end;

procedure TRebaseTest.Add(const AHash, ASubject, ABody: string; AAction: TGittanRebaseAction);
begin
  SetLength(FSteps, Length(FSteps) + 1);
  with FSteps[High(FSteps)] do
  begin
    Hash := AHash;
    Short := Copy(AHash, 1, 7);
    Subject := ASubject;
    Body := ABody;
    Action := AAction;
    Message := OriginalMessage(FSteps[High(FSteps)]);
  end;
end;

function TRebaseTest.Todo: string;
begin
  Result := BuildRebaseTodo(FSteps, '/tmp/x', FFiles);
end;

procedure TRebaseTest.TestPicks;
begin
  Add('aaaaaaa1', 'first', '', raPick);
  Add('bbbbbbb2', 'second', 'body', raPick);
  AssertEquals('pick aaaaaaa1 first'#10'pick bbbbbbb2 second'#10, Todo);
  AssertEquals(0, Length(FFiles));
end;

procedure TRebaseTest.TestReword;
begin
  Add('aaaaaaa1', 'first', '', raReword);
  FSteps[0].Message := 'better first'#10#10'with a body';
  Add('bbbbbbb2', 'second', '', raPick);
  AssertEquals('pick aaaaaaa1 first'#10 +
    'exec git commit --amend --allow-empty -F "/tmp/x/msg-1.txt"'#10 +
    'pick bbbbbbb2 second'#10, Todo);
  AssertEquals(1, Length(FFiles));
  AssertEquals('msg-1.txt', FFiles[0].Name);
  AssertEquals('better first'#10#10'with a body'#10, FFiles[0].Text);
end;

{ A pick whose message was changed is amended too, and a reword whose
  message is the commit's own is a plain pick. }
procedure TRebaseTest.TestChangedMessageIsReword;
begin
  Add('aaaaaaa1', 'first', '', raPick);
  FSteps[0].Message := 'changed';
  Add('bbbbbbb2', 'second', 'body', raReword);
  FSteps[1].Message := 'second'#13#10#13#10'body'#13#10;
  AssertFalse(MessageUnchanged(FSteps[0]));
  AssertTrue(MessageUnchanged(FSteps[1]));
  AssertEquals('pick aaaaaaa1 first'#10 +
    'exec git commit --amend --allow-empty -F "/tmp/x/msg-1.txt"'#10 +
    'pick bbbbbbb2 second'#10, Todo);
end;

{ A squash is a fixup with the messages joined and amended in; two in a
  row fold into the same commit. }
procedure TRebaseTest.TestSquash;
begin
  Add('aaaaaaa1', 'first', 'first body', raPick);
  Add('bbbbbbb2', 'second', '', raSquash);
  Add('ccccccc3', 'third', '', raSquash);
  Add('ddddddd4', 'fourth', '', raPick);
  AssertEquals('pick aaaaaaa1 first'#10'fixup bbbbbbb2 second'#10'fixup ccccccc3 third'#10 +
    'exec git commit --amend --allow-empty -F "/tmp/x/msg-1.txt"'#10 +
    'pick ddddddd4 fourth'#10, Todo);
  AssertEquals(1, Length(FFiles));
  AssertEquals('first'#10#10'first body'#10#10'second'#10#10'third'#10, FFiles[0].Text);
end;

{ A fixup drops its message, so nothing is amended. }
procedure TRebaseTest.TestFixup;
begin
  Add('aaaaaaa1', 'first', '', raPick);
  Add('bbbbbbb2', 'second', '', raFixup);
  AssertEquals('pick aaaaaaa1 first'#10'fixup bbbbbbb2 second'#10, Todo);
  AssertEquals(0, Length(FFiles));
end;

{ A drop between a commit and its fixup stays where it is. }
procedure TRebaseTest.TestDropBetween;
begin
  Add('aaaaaaa1', 'first', '', raPick);
  Add('bbbbbbb2', 'second', '', raDrop);
  Add('ccccccc3', 'third', '', raFixup);
  Add('ddddddd4', 'fourth', '', raDrop);
  AssertEquals('pick aaaaaaa1 first'#10'drop bbbbbbb2 second'#10'fixup ccccccc3 third'#10 +
    'drop ddddddd4 fourth'#10, Todo);
end;

procedure TRebaseTest.TestEdit;
begin
  Add('aaaaaaa1', 'first', '', raEdit);
  Add('bbbbbbb2', 'second', '', raPick);
  AssertEquals('edit aaaaaaa1 first'#10'pick bbbbbbb2 second'#10, Todo);
end;

procedure TRebaseTest.TestCheck;
var
  Error: string;
begin
  Add('aaaaaaa1', 'first', '', raSquash);
  Add('bbbbbbb2', 'second', '', raPick);
  AssertFalse(CheckRebaseSteps(FSteps, Error));
  AssertTrue(Error, Pos('aaaaaaa', Error) > 0);
  FSteps[0].Action := raDrop;
  FSteps[1].Action := raFixup;
  AssertFalse(CheckRebaseSteps(FSteps, Error));
  FSteps[0].Action := raEdit;
  AssertTrue(CheckRebaseSteps(FSteps, Error));
  AssertEquals('', Error);
  FSteps[0].Action := raDrop;
  FSteps[1].Action := raDrop;
  AssertTrue('all dropped', CheckRebaseSteps(FSteps, Error));
end;

procedure TRebaseTest.TestShellQuote;
begin
  AssertEquals('"/a b/c"', ShellQuote('/a b/c'));
  AssertEquals('"C:\\Users\\x\\.git"', ShellQuote('C:\Users\x\.git'));
  AssertEquals('"\$x \"q\" \`t\`"', ShellQuote('$x "q" `t`'));
end;

procedure TRebaseTest.TestJoinedMessage;
begin
  AssertEquals('a'#10#10'b', JoinedMessage(['a'#10#10, '  ', 'b '#13#10]));
  AssertEquals('', JoinedMessage(['', #10]));
end;

procedure TRebaseTest.TestOriginalMessage;
begin
  Add('aaaaaaa1', 'first', '', raPick);
  Add('bbbbbbb2', 'second', 'body'#10'more'#10, raPick);
  AssertEquals('first', OriginalMessage(FSteps[0]));
  AssertEquals('second'#10#10'body'#10'more', StringReplace(OriginalMessage(FSteps[1]),
    LineEnding, #10, [rfReplaceAll]));
end;

initialization
  RegisterTest(TRebaseTest);

end.
