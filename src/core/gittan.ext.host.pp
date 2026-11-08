unit gittan.ext.host;

{** What the extension engine asks of the program around it: the dialogs
  an extension opens, where its errors and console output go, the
  permission prompt, the message loop, the open repositories and the
  window's cards, status bar and banners. The engine (gittan.ext.engine)
  and the units under it reach the host through ExtHost alone, so they
  build without the LCL and the tests give them a host of their own; the
  window gives the real one (gittan.exthost in src/ui) before the engine
  is made. The default host, in place until one is set, answers every
  question with no and shows nothing, so a call never finds nil. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.ext.perm, gittan.git, gittan.reviews;

type

  {** The icon of Gittan.ui.message's dialog. }
  TExtMessageKind = (emkInfo, emkWarning, emkError, emkQuestion);

  { TGittanExtHost }

  TGittanExtHost = class
  public
    {** alert(): a message with an OK button, from the extension AName
      ('' when none is known). }
    procedure Alert(const AName, AText: string); virtual;
    {** confirm(): a yes/no question, from the extension AName. }
    function Confirm(const AName, AText: string): boolean; virtual;
    {** prompt(): a line of text; False when cancelled. }
    function Prompt(const ACaption, AText, ADefault: string; out AValue: string): boolean; virtual;
    {** select(): one of AOptions, its index, -1 when cancelled. }
    function Select(const ACaption, AText: string; const AOptions: array of string): integer; virtual;
    {** Gittan.ui.message(): ATitle over AText from the extension AName,
      with AKind's icon and the buttons AButtons (OK when there is none);
      Return presses ADefault, Escape and the close box ACancel. The index
      of the button pressed, -1 when the dialog was closed without one
      (ACancel -1). }
    function Message(const AName, ATitle, AText: string; AKind: TExtMessageKind;
      const AButtons: array of string; ADefault, ACancel: integer): integer; virtual;
    {** What an extension logged (console.log, console.pop), shown as
      text the user can read and copy. }
    procedure ShowLog(const ATitle, AText: string); virtual;
    {** An error of an extension: a script that fails to load, a native
      that raises. }
    procedure ReportError(const ATitle, ADetail: string); virtual;
    {** Whether the extension AName (AFile by AAuthor) may load with the
      permissions ARequested beyond the baseline. }
    function AskPermission(const AName, AFile, AAuthor: string;
      const ARequested: TExtPermSet): boolean; virtual;
    {** Lets the main thread's queue run while the engine waits for a
      background promise. }
    procedure Pump; virtual;
    {** Whether the program is on its way out, when nothing is shown and
      no JS is run. }
    function Terminated: boolean; virtual;
    {** The root of the repository a command acts on: the one shown. }
    function ActiveRoot: string; virtual;
    {** The open repository at ARoot, nil for none. Main thread only. }
    function RepoFor(const ARoot: string): TGittanRepo; virtual;
    {** The changed files of the repository at ARoot as the window has
      them. }
    function StatsFor(const ARoot: string): TGittanFileStats; virtual;
    {** A card under a line of the change view of ARoot. }
    procedure AddCard(const ARoot: string; const ACard: TGittanReviewThread); virtual;
    {** Drops the cards of the extension AExtId in ARoot, every
      extension's when AExtId is empty, every repository's when ARoot
      is. }
    procedure ClearCards(const ARoot, AExtId: string); virtual;
    {** A line in the status bar for ASeconds, until cleared when 0; an
      empty AText clears it. }
    procedure SetStatus(const ARoot, AText: string; ASeconds: integer); virtual;
    {** A banner, an error's when AError. }
    procedure Notify(const ARoot, ATitle, ADetail: string; AError: boolean); virtual;
    {** Shows APath of ARoot in the change view at ALine (0 for the
      top). }
    procedure OpenFile(const ARoot, APath: string; ALine: integer); virtual;
    {** The commands registered changed: the menus follow. }
    procedure CommandsChanged; virtual;
    {** The forge of the forge view while it is shown ("GitHub"), ''
      while it is not: where no repository is named, Gittan.forge acts
      on it then, else on the shown repository's. }
    function ForgeViewForge: string; virtual;
    {** What a tab's or a Batch operation's function of the extension
      AExtId gave for the request ASeq, as {"value": ...} or
      {"error": "..."}. }
    procedure Deliver(ASeq: integer; const AExtId, AJson: string); virtual;
  end;

{** The host in place; the default one until SetExtHost. }
function ExtHost: TGittanExtHost;
{** Makes AHost the host; the one before is freed unless it is the
  default. nil puts the default back. }
procedure SetExtHost(AHost: TGittanExtHost);

implementation

var
  TheHost, DefaultHost: TGittanExtHost;

function ExtHost: TGittanExtHost;
begin
  if TheHost <> nil then
    Exit(TheHost);
  if DefaultHost = nil then
    DefaultHost := TGittanExtHost.Create;
  Result := DefaultHost;
end;

procedure SetExtHost(AHost: TGittanExtHost);
begin
  if (TheHost <> nil) and (TheHost <> AHost) then
    TheHost.Free;
  TheHost := AHost;
end;

{ TGittanExtHost }

procedure TGittanExtHost.Alert(const AName, AText: string);
begin
end;

function TGittanExtHost.Confirm(const AName, AText: string): boolean;
begin
  Result := False;
end;

function TGittanExtHost.Prompt(const ACaption, AText, ADefault: string;
  out AValue: string): boolean;
begin
  AValue := '';
  Result := False;
end;

function TGittanExtHost.Select(const ACaption, AText: string;
  const AOptions: array of string): integer;
begin
  Result := -1;
end;

function TGittanExtHost.Message(const AName, ATitle, AText: string;
  AKind: TExtMessageKind; const AButtons: array of string;
  ADefault, ACancel: integer): integer;
begin
  Result := -1;
end;

procedure TGittanExtHost.ShowLog(const ATitle, AText: string);
begin
end;

procedure TGittanExtHost.ReportError(const ATitle, ADetail: string);
begin
end;

function TGittanExtHost.AskPermission(const AName, AFile, AAuthor: string;
  const ARequested: TExtPermSet): boolean;
begin
  Result := False;
end;

procedure TGittanExtHost.Pump;
begin
  CheckSynchronize;
  Sleep(5);
end;

function TGittanExtHost.Terminated: boolean;
begin
  Result := False;
end;

function TGittanExtHost.ActiveRoot: string;
begin
  Result := '';
end;

function TGittanExtHost.RepoFor(const ARoot: string): TGittanRepo;
begin
  Result := nil;
end;

function TGittanExtHost.StatsFor(const ARoot: string): TGittanFileStats;
begin
  Result := nil;
end;

procedure TGittanExtHost.AddCard(const ARoot: string; const ACard: TGittanReviewThread);
begin
end;

procedure TGittanExtHost.ClearCards(const ARoot, AExtId: string);
begin
end;

procedure TGittanExtHost.SetStatus(const ARoot, AText: string; ASeconds: integer);
begin
end;

procedure TGittanExtHost.Notify(const ARoot, ATitle, ADetail: string; AError: boolean);
begin
end;

procedure TGittanExtHost.OpenFile(const ARoot, APath: string; ALine: integer);
begin
end;

procedure TGittanExtHost.CommandsChanged;
begin
end;

function TGittanExtHost.ForgeViewForge: string;
begin
  Result := '';
end;

procedure TGittanExtHost.Deliver(ASeq: integer; const AExtId, AJson: string);
begin
end;

finalization
  FreeAndNil(TheHost);
  FreeAndNil(DefaultHost);
end.
