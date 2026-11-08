unit gittan.exthost;

{** The extension host of the window (gittan.ext.host): what an
  extension's dialogs, errors and permission prompt show, the open
  repositories a command and the natives act on, and the window's status
  bar, banners and change view for what an extension puts there. The
  window makes one in its FormCreate and gives it to the engine
  (SetExtHost) before the extensions load, and takes it back (SetExtHost
  nil) in its FormDestroy, before the frames go. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Dialogs, gittan.ext.host, gittan.ext.perm,
  gittan.git, gittan.reviews, umain;

type

  { TGittanExtUIHost }

  TGittanExtUIHost = class(TGittanExtHost)
  private
    FWindow: TRepoWindow;
    {** The frame that has ARoot open, the shown one for '' or an
      unknown root; nil before any frame. }
    function FrameOf(const ARoot: string): TRepoFrame;
  public
    constructor Create(AWindow: TRepoWindow);
    procedure Alert(const AName, AText: string); override;
    function Confirm(const AName, AText: string): boolean; override;
    function Prompt(const ACaption, AText, ADefault: string; out AValue: string): boolean; override;
    function Message(const AName, ATitle, AText: string; AKind: TExtMessageKind;
      const AButtons: array of string; ADefault, ACancel: integer): integer; override;
    function Select(const ACaption, AText: string; const AOptions: array of string): integer; override;
    procedure ShowLog(const ATitle, AText: string); override;
    procedure ReportError(const ATitle, ADetail: string); override;
    function AskPermission(const AName, AFile, AAuthor: string;
      const ARequested: TExtPermSet): boolean; override;
    procedure Pump; override;
    function Terminated: boolean; override;
    function ActiveRoot: string; override;
    function RepoFor(const ARoot: string): TGittanRepo; override;
    function StatsFor(const ARoot: string): TGittanFileStats; override;
    procedure AddCard(const ARoot: string; const ACard: TGittanReviewThread); override;
    procedure ClearCards(const ARoot, AExtId: string); override;
    procedure SetStatus(const ARoot, AText: string; ASeconds: integer); override;
    procedure Notify(const ARoot, ATitle, ADetail: string; AError: boolean); override;
    procedure OpenFile(const ARoot, APath: string; ALine: integer); override;
    procedure CommandsChanged; override;
    function ForgeViewForge: string; override;
    procedure Deliver(ASeq: integer; const AExtId, AJson: string); override;
  end;

implementation

uses
  gittan.askdlg, gittan.app;

resourcestring
  rsExtMessage = 'Extension';
  rsExtQuestion = 'Extension question';
  rsExtOK = 'OK';
  rsExtNamed = 'Extension "%s"';
  rsExtError = 'Extension error';
  rsExtPermTitle = 'An extension asks for permissions';
  rsExtPermText = '%s' + LineEnding + LineEnding + 'File: %s' + LineEnding;
  rsExtPermAuthor = 'Author: %s' + LineEnding;
  rsExtPermRequested = LineEnding + 'It asks for:' + LineEnding;
  rsExtPermBaseline = LineEnding + 'Every extension may %s.' + LineEnding +
    LineEnding + 'Load it with these permissions? Gittan asks again when the file changes.';
  rsExtPermAllow = 'Load';
  rsExtPermDeny = 'Do Not Load';

constructor TGittanExtUIHost.Create(AWindow: TRepoWindow);
begin
  inherited Create;
  FWindow := AWindow;
end;

function TGittanExtUIHost.FrameOf(const ARoot: string): TRepoFrame;
begin
  Result := nil;
  if FWindow = nil then
    Exit;
  if ARoot <> '' then
    Result := FWindow.FrameForRoot(ARoot);
  if Result = nil then
    Result := FWindow.ShownFrame;
end;

procedure TGittanExtUIHost.Alert(const AName, AText: string);
begin
  if AName <> '' then
    TellDlg(Format(rsExtNamed, [AName]), AText, mtInformation)
  else
    TellDlg(rsExtMessage, AText, mtInformation);
end;

function TGittanExtUIHost.Confirm(const AName, AText: string): boolean;
var
  Title: string;
begin
  if AName <> '' then
    Title := Format(rsExtNamed, [AName])
  else
    Title := rsExtQuestion;
  Result := AskDlg(Title, AText, mtConfirmation, [mrYes, mrNo]) = mrYes;
end;

function TGittanExtUIHost.Prompt(const ACaption, AText, ADefault: string;
  out AValue: string): boolean;
begin
  AValue := ADefault;
  Result := AskText(ACaption, AText, AValue, nil, '', '', True);
  if not Result then
    AValue := '';
end;

{ The window's title names the extension, as alert's does, so a message
  cannot pass for one of Gittan's own; the extension's title heads the
  text. A button's modal result is ButtonBase plus its index, above the
  LCL's own, so Escape and the close box without a cancel button
  (mrCancel) answer -1. }
function TGittanExtUIHost.Message(const AName, ATitle, AText: string;
  AKind: TExtMessageKind; const AButtons: array of string;
  ADefault, ACancel: integer): integer;
const
  ButtonBase = 1000;
  Kinds: array[TExtMessageKind] of TMsgDlgType =
    (mtInformation, mtWarning, mtError, mtConfirmation);
var
  Caption, Text: string;
  Labels: array of string;
  Args: array of TVarRec;
  i, n: integer;
  Pressed: TModalResult;

  procedure Put(const AValue: TVarRec);
  begin
    SetLength(Args, Length(Args) + 1);
    Args[High(Args)] := AValue;
  end;

  procedure PutInt(AValue: integer);
  var
    V: TVarRec;
  begin
    V := Default(TVarRec);
    V.VType := vtInteger;
    V.VInteger := AValue;
    Put(V);
  end;

  procedure PutStr(const AValue: string);
  var
    V: TVarRec;
  begin
    V := Default(TVarRec);
    V.VType := vtAnsiString;
    V.VAnsiString := Pointer(AValue);
    Put(V);
  end;

begin
  if AName <> '' then
    Caption := Format(rsExtNamed, [AName])
  else
    Caption := rsExtMessage;
  Text := ATitle;
  if (Text <> '') and (AText <> '') then
    Text := Text + LineEnding + LineEnding;
  Text := Text + AText;
  { The labels are kept in Labels while Args points at them. }
  Labels := nil;
  Args := nil;
  if Length(AButtons) = 0 then
  begin
    SetLength(Labels, 1);
    Labels[0] := rsExtOK;
  end
  else
  begin
    SetLength(Labels, Length(AButtons));
    for i := 0 to High(AButtons) do
      Labels[i] := AButtons[i];
  end;
  for i := 0 to High(Labels) do
  begin
    PutInt(ButtonBase + i);
    PutStr(Labels[i]);
    if i = ADefault then
      PutStr('IsDefault');
    if i = ACancel then
      PutStr('IsCancel');
  end;
  Pressed := AskDlg(Caption, Text, Kinds[AKind], Args);
  n := Pressed - ButtonBase;
  if (n >= 0) and (n <= High(Labels)) then
    Result := n
  else
    Result := -1;
end;

function TGittanExtUIHost.Select(const ACaption, AText: string;
  const AOptions: array of string): integer;
var
  List: TStringList;
  Option: string;
begin
  List := TStringList.Create;
  try
    for Option in AOptions do
      List.Add(Option);
    Result := InputCombo(ACaption, AText, List);
  finally
    List.Free;
  end;
end;

procedure TGittanExtUIHost.ShowLog(const ATitle, AText: string);
begin
  TellDlg(ATitle, AText, mtInformation);
end;

procedure TGittanExtUIHost.ReportError(const ATitle, ADetail: string);
var
  Frame: TRepoFrame;
begin
  Frame := FrameOf('');
  if Frame <> nil then
    Frame.ExtNotify(ATitle, ADetail, True)
  else
    TellDlg(rsExtError, ATitle + LineEnding + ADetail, mtError);
end;

function TGittanExtUIHost.AskPermission(const AName, AFile, AAuthor: string;
  const ARequested: TExtPermSet): boolean;
var
  Text: string;
  g: TExtPermGroup;
begin
  Text := Format(rsExtPermText, [AName, ExtractFileName(AFile)]);
  if AAuthor <> '' then
    Text := Text + Format(rsExtPermAuthor, [AAuthor]);
  Text := Text + rsExtPermRequested;
  for g := Low(TExtPermGroup) to High(TExtPermGroup) do
    if g in ARequested then
      Text := Text + '  • ' + PermGroupName[g] + ': ' + PermGroupDesc[g] + LineEnding;
  Text := Text + Format(rsExtPermBaseline, [LowerCase(PermGroupDesc[epUI]) + ' and ' +
    LowerCase(PermGroupDesc[epTimers])]);
  Result := AskDlg(rsExtPermTitle, Text, mtConfirmation,
    [mrYes, rsExtPermAllow, mrNo, rsExtPermDeny, 'IsDefault']) = mrYes;
end;

procedure TGittanExtUIHost.Pump;
begin
  Application.ProcessMessages;
  Sleep(5);
end;

function TGittanExtUIHost.Terminated: boolean;
begin
  Result := Application.Terminated;
end;

function TGittanExtUIHost.ActiveRoot: string;
var
  Frame: TRepoFrame;
begin
  Result := '';
  Frame := FrameOf('');
  if Frame <> nil then
    Result := Frame.RepoRoot;
end;

function TGittanExtUIHost.RepoFor(const ARoot: string): TGittanRepo;
var
  Frame: TRepoFrame;
begin
  Result := nil;
  if FWindow = nil then
    Exit;
  Frame := FWindow.FrameForRoot(ARoot);
  if (Frame <> nil) and (Frame.RepoRoot <> '') then
    Result := Frame.Repository;
end;

function TGittanExtUIHost.StatsFor(const ARoot: string): TGittanFileStats;
var
  Frame: TRepoFrame;
begin
  Result := nil;
  if FWindow = nil then
    Exit;
  Frame := FWindow.FrameForRoot(ARoot);
  if Frame <> nil then
    Result := Frame.Stats;
end;

procedure TGittanExtUIHost.AddCard(const ARoot: string; const ACard: TGittanReviewThread);
var
  Frame: TRepoFrame;
begin
  { A repository no longer open takes no card, not the shown one's. }
  if (ARoot <> '') and (FWindow <> nil) then
    Frame := FWindow.FrameForRoot(ARoot)
  else
    Frame := FrameOf(ARoot);
  if Frame <> nil then
    Frame.ExtAddCard(ACard);
end;

procedure TGittanExtUIHost.ClearCards(const ARoot, AExtId: string);
var
  Frame: TRepoFrame;
  i: integer;
begin
  if FWindow = nil then
    Exit;
  if ARoot = '' then
    for i := 0 to FWindow.FrameCount - 1 do
      FWindow.FrameAt(i).ExtClearCards(AExtId)
  else
  begin
    Frame := FWindow.FrameForRoot(ARoot);
    if Frame <> nil then
      Frame.ExtClearCards(AExtId);
  end;
end;

procedure TGittanExtUIHost.SetStatus(const ARoot, AText: string; ASeconds: integer);
var
  Frame: TRepoFrame;
begin
  Frame := FrameOf(ARoot);
  if Frame <> nil then
    Frame.ExtSetStatus(AText, ASeconds);
end;

procedure TGittanExtUIHost.Notify(const ARoot, ATitle, ADetail: string; AError: boolean);
var
  Frame: TRepoFrame;
  Text: string;
begin
  { The forge view has no banner, and the frame's is under it. }
  if (FWindow <> nil) and (FWindow.ForgeViewForge <> '') and (ARoot = ActiveRoot) then
  begin
    Text := ATitle;
    if ADetail <> '' then
      Text := Text + LineEnding + LineEnding + ADetail;
    if AError then
      TellDlg(rsExtMessage, Text, mtError)
    else
      TellDlg(rsExtMessage, Text, mtInformation);
    Exit;
  end;
  Frame := FrameOf(ARoot);
  if Frame <> nil then
    Frame.ExtNotify(ATitle, ADetail, AError);
end;

procedure TGittanExtUIHost.OpenFile(const ARoot, APath: string; ALine: integer);
var
  Frame: TRepoFrame;
begin
  Frame := FrameOf(ARoot);
  if Frame <> nil then
  begin
    FWindow.ShowFrame(Frame);
    Frame.ExtOpenFile(APath, ALine);
  end;
end;

procedure TGittanExtUIHost.CommandsChanged;
begin
  { Once at the end of a load, rather than for every command a script
    registers. }
  if (App <> nil) and (App.Extensions <> nil) and App.Extensions.Loading then
    Exit;
  if FWindow <> nil then
    FWindow.ExtensionsChanged;
end;

function TGittanExtUIHost.ForgeViewForge: string;
begin
  if FWindow <> nil then
    Result := FWindow.ForgeViewForge
  else
    Result := '';
end;

procedure TGittanExtUIHost.Deliver(ASeq: integer; const AExtId, AJson: string);
begin
  if FWindow <> nil then
    FWindow.ExtDeliver(ASeq, AExtId, AJson);
end;

end.
