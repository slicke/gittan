unit uwindow;

{** The main window: a shell around the repository frame (TRepoFrame in
  umain), which shows everything. The window makes App (gittan.app) first
  and frees it last, keeps its own place and size in the settings, and
  passes its events on to the frame: closing, the keys (KeyPreview, for
  the commands' keys from any view), activation and dropped files.

  For now it holds one frame, which still drives the window itself (the
  menu, the caption, the toolbar or own title bar); several repositories
  open at once, a frame each behind tabs, come next. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, LCLType, Forms, Controls, gittan.app, umain;

type

  { TGittanWindow }

  TGittanWindow = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
  private
    FFrame: TRepoFrame;
    procedure PlaceWindow;
    procedure SavePlace;
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: boolean);
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure FormActivate(Sender: TObject);
  end;

var
  GittanWindow: TGittanWindow;

implementation

{$R *.lfm}

procedure TGittanWindow.FormCreate(Sender: TObject);
begin
  { First: everything below reads the settings. }
  CreateApp;
  PlaceWindow;
  KeyPreview := True;
  OnKeyDown := @FormKeyDown;
  OnActivate := @FormActivate;
  OnClose := @FormClose;
  OnCloseQuery := @FormCloseQuery;
  { The frame is made and filled here, in FormCreate, so the form scales
    it to the screen with the rest afterwards (TCustomForm.AfterConstruction):
    placed in a form not yet scaled, the frame does not scale itself. }
  FFrame := TRepoFrame.Create(Self);
  FFrame.Align := alClient;
  FFrame.Parent := Self;
  FFrame.Init(Self);
end;

procedure TGittanWindow.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FFrame);
  { Last: the lexers go with it, which the frame's editors let go of. }
  FreeApp;
end;

{ The window where it was, if that is still on a screen. The sizes are
  kept at 96 DPI: this runs in FormCreate, and the form scales its size
  and the frame's to the screen's after it, its place not. Else
  FirstShare of the main screen's work area, no smaller than the
  designed size and no larger than FirstMaxWidth by FirstMaxHeight, in
  its middle: the place in the screen's pixels, the size at 96 DPI for
  the form to scale. }
procedure TGittanWindow.PlaceWindow;
const
  { The share of the screen's work area a window with no place of its
    own takes. }
  FirstShare = 0.7;
  { At most this at 96 DPI, so it is not a band across a wide screen. }
  FirstMaxWidth = 1600;
  FirstMaxHeight = 1000;
var
  R, Area: TRect;
  W, H: integer;
  Placed: boolean;
begin
  Placed := False;
  if (App.Settings.Width > 0) and (App.Settings.Height > 0) then
  begin
    R := Rect(App.Settings.Left, App.Settings.Top, App.Settings.Left + App.Settings.Width,
      App.Settings.Top + App.Settings.Height);
    Placed := IntersectRect(R, R, Screen.DesktopRect) and (R.Width > 100) and
      (R.Height > 100);
    if Placed then
      SetBounds(App.Settings.Left, App.Settings.Top, App.Settings.Width, App.Settings.Height);
  end;
  if not Placed then
  begin
    Area := Screen.PrimaryMonitor.WorkareaRect;
    W := Min(Area.Width, Max(Scale96ToScreen(Width), Min(Scale96ToScreen(FirstMaxWidth),
      Round(Area.Width * FirstShare))));
    H := Min(Area.Height, Max(Scale96ToScreen(Height), Min(Scale96ToScreen(FirstMaxHeight),
      Round(Area.Height * FirstShare))));
    SetBounds(Area.Left + (Area.Width - W) div 2, Area.Top + (Area.Height - H) div 2,
      MulDiv(W, 96, Screen.PixelsPerInch), MulDiv(H, 96, Screen.PixelsPerInch));
  end;
  if App.Settings.Maximized then
    WindowState := wsMaximized;
end;

{ The place and size go in the settings at 96 DPI; a maximized window
  keeps the place it is restored to. }
procedure TGittanWindow.SavePlace;
begin
  App.Settings.Maximized := WindowState = wsMaximized;
  if App.Settings.Maximized then
  begin
    App.Settings.Left := RestoredLeft;
    App.Settings.Top := RestoredTop;
    App.Settings.Width := RestoredWidth;
    App.Settings.Height := RestoredHeight;
  end
  else
  begin
    App.Settings.Left := Left;
    App.Settings.Top := Top;
    App.Settings.Width := Width;
    App.Settings.Height := Height;
  end;
  App.Settings.Width := MulDiv(App.Settings.Width, 96, Screen.PixelsPerInch);
  App.Settings.Height := MulDiv(App.Settings.Height, 96, Screen.PixelsPerInch);
end;

{ The frame writes the settings, the window's place with them. }
procedure TGittanWindow.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  SavePlace;
  FFrame.FormClose(Sender, CloseAction);
end;

procedure TGittanWindow.FormCloseQuery(Sender: TObject; var CanClose: boolean);
begin
  FFrame.FormCloseQuery(Sender, CanClose);
end;

procedure TGittanWindow.FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  FFrame.FormKeyDown(Sender, Key, Shift);
end;

procedure TGittanWindow.FormActivate(Sender: TObject);
begin
  FFrame.FormActivate(Sender);
end;

{ Also how Cocoa hands over a path Gittan is asked to open (the gittan
  command, the Dock icon). }
procedure TGittanWindow.FormDropFiles(Sender: TObject; const FileNames: array of string);
begin
  if FFrame <> nil then
    FFrame.FormDropFiles(Sender, FileNames);
end;

end.
