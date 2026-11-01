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
    procedure Alert(const AText: string); override;
    function Confirm(const AText: string): boolean; override;
    function Prompt(const ACaption, AText, ADefault: string; out AValue: string): boolean; override;
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
  end;

implementation

uses
  gittan.askdlg, gittan.app;

resourcestring
  rsExtMessage = 'Extension';
  rsExtQuestion = 'Extension question';
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

procedure TGittanExtUIHost.Alert(const AText: string);
begin
  TellDlg(rsExtMessage, AText, mtInformation);
end;

function TGittanExtUIHost.Confirm(const AText: string): boolean;
begin
  Result := AskDlg(rsExtQuestion, AText, mtConfirmation, [mrYes, mrNo]) = mrYes;
end;

function TGittanExtUIHost.Prompt(const ACaption, AText, ADefault: string;
  out AValue: string): boolean;
begin
  AValue := ADefault;
  Result := AskText(ACaption, AText, AValue, nil, '', '', True);
  if not Result then
    AValue := '';
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
begin
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

end.
