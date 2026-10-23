unit gittan.filespage;

{** The Files page: the tree of a commit as it was, one folder at a
  time, as a code host's file list. Under the repository's name and the
  commit (its branch or short id with its subject) a row of crumbs
  names the folder shown, each crumb before the last leading back up,
  over a divider; then a row per entry, folders first as git lists
  them: its icon from the tree's image list, its name, a submodule's
  commit or a link's kind dimmed after it, and at the right its size.
  A row fills under the mouse; a click on a folder opens it here, and
  OnOpen reports a click on anything else (a file, a link, a
  submodule) for the owner to show.

  The folders are read as they are opened through OnRead, which the
  owner answers with TGittanRepo.TreeEntries, and kept per commit, so
  going back up reads nothing again. SetCommit shows another commit:
  the folder shown is kept when that commit has it, else the root.
  With no commit (a repository before its first) the page says so.

  It paints itself in the editor's palette, like the Repository page,
  and sizes its height to its content so it can sit in the same
  TScrollBox: Layout paints the content on a measuring canvas to know
  the height before the control is shown, since a height that changes
  in the first paint leaves the box scrolled wrong on Cocoa. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, ImgList, gittan.git;

type
  {** Asks for the entries of AFolder ('' for the root) in the commit
    shown; false with AError when git could not list it. }
  TGittanTreeReadEvent = function(Sender: TObject; const AFolder: string;
    out AList: TGittanTreeEntries; out AError: string): boolean of object;
  {** A click on an entry that is not a folder. }
  TGittanTreeEntryEvent = procedure(Sender: TObject; const AEntry: TGittanTreeEntry) of object;

  { TGittanFilesPage }

  TGittanFilesPage = class(TCustomControl)
  private
    FName, FRoot: string;
    FCommit, FCommitName, FSubject: string;
    FHasCommit: boolean;
    FFolder: string;
    FEntries: TGittanTreeEntries;
    FError: string;
    FCachePaths: array of string;
    FCacheLists: array of TGittanTreeEntries;
    FImages: TCustomImageList;
    FFolderIcon, FFileIcon: integer;
    FBack, FText, FDim, FHover, FLine, FLink, FErrorColor: TColor;
    FLinkRects: array of TRect;
    FLinkUrls: array of string;
    FHot: integer;
    FContentHeight: integer;
    { The canvas the content is painted on: the control's in Paint, a
      measuring one in Layout. }
    FC: TCanvas;
    FOnRead: TGittanTreeReadEvent;
    FOnOpen: TGittanTreeEntryEvent;
    FOnFolderChange: TNotifyEvent;
    function LinkAt(X, Y: integer): integer;
    procedure SetHot(AValue: integer);
    procedure AddLink(const ARect: TRect; const AUrl: string);
    function Cached(const AFolder: string; out AList: TGittanTreeEntries): boolean;
    procedure LoadFolder(const AFolder: string);
    procedure PaintCrumbs(var Y: integer);
    procedure PaintNote(var Y: integer; const AText: string; AColor: TColor);
    procedure PaintRows(var Y: integer);
    procedure PaintContent;
    procedure Layout;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
      override;
  public
    constructor Create(AOwner: TComponent); override;
    {** The repository shown: its name over its root. Another root
      drops the commit and the folders read. }
    procedure SetRepository(const AName, ARoot: string);
    {** Shows the commit AHash, named ACommitName (its branch, tag or
      short id) with ASubject after it. Another id drops the folders
      read and reads the folder shown again, or the root when the
      commit lacks it; the same id changes nothing. }
    procedure SetCommit(const AHash, ACommitName, ASubject: string);
    {** No commit to show: the page says the repository has none yet. }
    procedure ClearCommit;
    {** The image list the rows draw their icons from, with the index of
      the folder and of a file in it. }
    procedure SetImages(AImages: TCustomImageList; AFolderIcon, AFileIcon: integer);
    {** The palette: the background, the text, the dim text, the fill
      under the mouse, the dividers, the links and the error text. }
    procedure SetColors(ABack, AText, ADim, AHover, ALine, ALink, AError: TColor);
    {** Makes the control at least AMin high (the height of the box it
      sits in, so its background covers the box), and no higher than its
      content needs beyond that. }
    procedure FitHeight(AMin: integer);
    {** The full id of the commit shown, empty without one. }
    property Commit: string read FCommit;
    {** What the commit is called on the page. }
    property CommitName: string read FCommitName;
    {** The folder shown, a path from the root, '' for the root. }
    property Folder: string read FFolder;
    {** The root the page is for. }
    property Root: string read FRoot;
    property OnRead: TGittanTreeReadEvent read FOnRead write FOnRead;
    property OnOpen: TGittanTreeEntryEvent read FOnOpen write FOnOpen;
    {** Another folder is shown, by a crumb or a row. }
    property OnFolderChange: TNotifyEvent read FOnFolderChange write FOnFolderChange;
  end;

implementation

uses
  Math, LCLIntf, LCLType, Forms, gittan.imagediff, gittan.statusbar, gittan.textfit,
  gittan.theme;

resourcestring
  rsPageTitle = 'Files';
  rsNoCommit = 'No commits yet. The files of a commit are listed here once there is one.';
  rsEmptyFolder = 'Nothing in this folder.';
  rsSubmoduleAt = '@ %s';
  rsLinkKind = 'link';

const
  FolderLink = 'gittan:folder:';
  EntryLink = 'gittan:entry:';
  Pad = 24;
  Gap = 12;
  TitleFontSize = 20;
  { The rows: their padding over and under the text, the corner radius
    of the fill under the mouse, and the icon. }
  RowPadY = 6;
  RowRadius = 6;
  IconSize = 16;
  CrumbSep = ' › ';

{ TGittanFilesPage }

constructor TGittanFilesPage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FHot := -1;
  FFolderIcon := -1;
  FFileIcon := -1;
  Align := alTop;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnShadow, clHighlight, clRed);
end;

procedure TGittanFilesPage.SetRepository(const AName, ARoot: string);
begin
  if FRoot <> ARoot then
  begin
    FCommit := '';
    FCommitName := '';
    FSubject := '';
    FHasCommit := False;
    FFolder := '';
    FEntries := nil;
    FError := '';
    FCachePaths := nil;
    FCacheLists := nil;
  end;
  FName := AName;
  FRoot := ARoot;
  Layout;
  Invalidate;
end;

procedure TGittanFilesPage.SetCommit(const AHash, ACommitName, ASubject: string);
var
  Shown: string;
begin
  FCommitName := ACommitName;
  FSubject := ASubject;
  if FHasCommit and (FCommit = AHash) then
  begin
    Layout;
    Invalidate;
    Exit;
  end;
  FCommit := AHash;
  FHasCommit := True;
  FCachePaths := nil;
  FCacheLists := nil;
  { The folder shown, when the commit has it. }
  Shown := FFolder;
  FFolder := '';
  LoadFolder(Shown);
  if (FError <> '') and (Shown <> '') then
    LoadFolder('');
end;

procedure TGittanFilesPage.ClearCommit;
begin
  FCommit := '';
  FCommitName := '';
  FSubject := '';
  FHasCommit := False;
  FFolder := '';
  FEntries := nil;
  FError := '';
  FCachePaths := nil;
  FCacheLists := nil;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanFilesPage.SetImages(AImages: TCustomImageList; AFolderIcon, AFileIcon: integer);
begin
  FImages := AImages;
  FFolderIcon := AFolderIcon;
  FFileIcon := AFileIcon;
  Invalidate;
end;

procedure TGittanFilesPage.SetColors(ABack, AText, ADim, AHover, ALine, ALink, AError: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
  FLine := ALine;
  FLink := ALink;
  FErrorColor := AError;
  Color := ABack;
  Invalidate;
end;

procedure TGittanFilesPage.FitHeight(AMin: integer);
begin
  Constraints.MinHeight := AMin;
  Layout;
end;

{ The content painted on the measuring canvas, for its height; the
  height is set here, never in Paint. }
procedure TGittanFilesPage.Layout;
var
  H: integer;
begin
  if (Parent = nil) or (Width <= 0) then
    Exit;
  FC := MeasureCanvas(Font);
  PaintContent;
  H := Max(FContentHeight, Constraints.MinHeight);
  if Height <> H then
    Height := H;
  Invalidate;
end;

procedure TGittanFilesPage.Resize;
begin
  inherited Resize;
  Layout;
end;

function TGittanFilesPage.Cached(const AFolder: string; out AList: TGittanTreeEntries): boolean;
var
  i: integer;
begin
  for i := 0 to High(FCachePaths) do
    if FCachePaths[i] = AFolder then
    begin
      AList := FCacheLists[i];
      Exit(True);
    end;
  AList := nil;
  Result := False;
end;

{ Shows AFolder: from what was read before, else through OnRead, whose
  failure the page shows in the folder's place. }
procedure TGittanFilesPage.LoadFolder(const AFolder: string);
var
  List: TGittanTreeEntries;
  Error: string;
begin
  FFolder := AFolder;
  FError := '';
  FHot := -1;
  if not FHasCommit then
    FEntries := nil
  else if Cached(AFolder, List) then
    FEntries := List
  else if not Assigned(FOnRead) then
    FEntries := nil
  else if FOnRead(Self, AFolder, List, Error) then
  begin
    FEntries := List;
    SetLength(FCachePaths, Length(FCachePaths) + 1);
    SetLength(FCacheLists, Length(FCacheLists) + 1);
    FCachePaths[High(FCachePaths)] := AFolder;
    FCacheLists[High(FCacheLists)] := List;
  end
  else
  begin
    FEntries := nil;
    FError := Error;
  end;
  Layout;
  Invalidate;
end;

function TGittanFilesPage.LinkAt(X, Y: integer): integer;
var
  i: integer;
begin
  for i := 0 to High(FLinkRects) do
    if PtInRect(FLinkRects[i], Point(X, Y)) then
      Exit(i);
  Result := -1;
end;

procedure TGittanFilesPage.SetHot(AValue: integer);
begin
  if FHot = AValue then
    Exit;
  FHot := AValue;
  if AValue < 0 then
    Cursor := crDefault
  else
    Cursor := crHandPoint;
  Invalidate;
end;

procedure TGittanFilesPage.AddLink(const ARect: TRect; const AUrl: string);
begin
  SetLength(FLinkRects, Length(FLinkRects) + 1);
  SetLength(FLinkUrls, Length(FLinkUrls) + 1);
  FLinkRects[High(FLinkRects)] := ARect;
  FLinkUrls[High(FLinkUrls)] := AUrl;
end;

{ The crumbs of the folder shown, the repository's name first: every
  one before the last is a link back up; the last stands in bold, as
  a heading's title. A divider under them. }
procedure TGittanFilesPage.PaintCrumbs(var Y: integer);
var
  Parts: TStringArray;
  i, X, TextH, Right: integer;
  Path, Crumb: string;
  R: TRect;
begin
  Inc(Y, Px(Pad));
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  Right := Width - Px(Pad);
  if FFolder = '' then
    Parts := nil
  else
    Parts := FFolder.Split(['/']);
  X := Px(Pad);
  Path := '';
  for i := -1 to High(Parts) do
  begin
    if i < 0 then
      Crumb := FName
    else
    begin
      Crumb := Parts[i];
      if Path = '' then
        Path := Crumb
      else
        Path := Path + '/' + Crumb;
    end;
    FC.Font.Style := [fsBold];
    if i = High(Parts) then
    begin
      FC.Font.Color := FDim;
      FC.TextOut(X, Y, FitTextRight(FC, Crumb, Max(0, Right - X)));
      Break;
    end;
    R := Rect(X, Y, X + FC.TextWidth(Crumb), Y + TextH);
    AddLink(R, FolderLink + Path);
    FC.Font.Color := FLink;
    if FHot = High(FLinkRects) then
      FC.Font.Style := [fsBold, fsUnderline];
    FC.TextOut(X, Y, Crumb);
    X := R.Right;
    FC.Font.Style := [];
    FC.Font.Color := FDim;
    FC.TextOut(X, Y, CrumbSep);
    Inc(X, FC.TextWidth(CrumbSep));
    if X > Right then
      Break;
  end;
  FC.Font.Style := [];
  Inc(Y, TextH + Px(Gap) div 2);
  FC.Pen.Style := psSolid;
  FC.Pen.Color := FLine;
  FC.Line(Px(Pad), Y, Width - Px(Pad), Y);
  Inc(Y, Px(Gap) div 2);
end;

{ A paragraph in AColor, wrapped to the width. }
procedure TGittanFilesPage.PaintNote(var Y: integer; const AText: string; AColor: TColor);
var
  R: TRect;
  Style: TTextStyle;
begin
  Inc(Y, Px(Gap) div 2);
  FC.Font := Font;
  FC.Font.Color := AColor;
  FC.Brush.Style := bsClear;
  R := Rect(Px(Pad), Y, Width - Px(Pad), Y);
  Style := FC.TextStyle;
  Style.Wordbreak := True;
  Style.SingleLine := False;
  Style.Alignment := taLeftJustify;
  Style.Layout := tlTop;
  DrawText(FC.Handle, PChar(AText), Length(AText), R, DT_CALCRECT or DT_WORDBREAK);
  R.Right := Width - Px(Pad);
  FC.TextRect(R, R.Left, R.Top, AText, Style);
  Y := R.Bottom;
end;

{ A row per entry: the icon, the name, a submodule's commit or a link's
  kind dimmed after it, the size at the right. Every row leads on. }
procedure TGittanFilesPage.PaintRows(var Y: integer);
var
  i, TextH, RowH, X, Right, NameW: integer;
  R: TRect;
  Detail, SizeText: string;
  E: TGittanTreeEntry;
begin
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  RowH := Max(TextH, Px(IconSize)) + 2 * Px(RowPadY);
  for i := 0 to High(FEntries) do
  begin
    E := FEntries[i];
    R := Rect(Px(Pad), Y, Width - Px(Pad), Y + RowH);
    if E.Kind = tkFolder then
      AddLink(R, FolderLink + E.Path)
    else
      AddLink(R, EntryLink + IntToStr(i));
    if FHot = High(FLinkRects) then
      FillHover(FC, R, Px(RowRadius), FHover);
    X := R.Left + Px(Gap) div 2;
    if FImages <> nil then
    begin
      if E.Kind in [tkFolder, tkSubmodule] then
        FImages.DrawForPPI(FC, X, Y + (RowH - Px(IconSize)) div 2, FFolderIcon, IconSize,
          Screen.PixelsPerInch, GetCanvasScaleFactor)
      else
        FImages.DrawForPPI(FC, X, Y + (RowH - Px(IconSize)) div 2, FFileIcon, IconSize,
          Screen.PixelsPerInch, GetCanvasScaleFactor);
    end;
    Inc(X, Px(IconSize) + Px(Gap) div 2 + 2);
    Right := R.Right - Px(Gap) div 2;
    { The size at the right, dimmed; none for a folder or a submodule. }
    if E.Size >= 0 then
    begin
      SizeText := ByteSize(E.Size);
      FC.Font.Color := FDim;
      FC.TextOut(Right - FC.TextWidth(SizeText), Y + (RowH - TextH) div 2, SizeText);
      Dec(Right, FC.TextWidth(SizeText) + Px(Gap));
    end;
    case E.Kind of
      tkSubmodule: Detail := Format(rsSubmoduleAt, [Copy(E.Id, 1, 7)]);
      tkLink: Detail := rsLinkKind;
      else
        Detail := '';
    end;
    FC.Font.Color := FText;
    NameW := Min(FC.TextWidth(E.Name), Max(0, Right - X));
    FC.TextOut(X, Y + (RowH - TextH) div 2, FitTextRight(FC, E.Name, Max(0, Right - X)));
    if (Detail <> '') and (X + NameW + Px(Gap) div 2 < Right) then
    begin
      FC.Font.Color := FDim;
      FC.TextOut(X + NameW + Px(Gap) div 2, Y + (RowH - TextH) div 2,
        FitTextRight(FC, Detail, Right - X - NameW - Px(Gap) div 2));
    end;
    Inc(Y, RowH);
  end;
end;

procedure TGittanFilesPage.Paint;
begin
  FC := Canvas;
  PaintContent;
end;

procedure TGittanFilesPage.PaintContent;
var
  Y, TextH, TitleH, X: integer;
  Line: string;
begin
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FBack;
  FC.FillRect(Rect(0, 0, Width, Height));
  FLinkRects := nil;
  FLinkUrls := nil;
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  Y := Px(Pad);

  { The name with the page's title after it, the commit under them:
    the branch icon, its name and its subject. }
  FC.Font.Size := TitleFontSize;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  TitleH := FC.TextHeight('Xg');
  FC.TextOut(Px(Pad), Y, FName);
  X := Px(Pad) + FC.TextWidth(FName) + Px(Gap);
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  FC.Font.Color := FDim;
  FC.TextOut(X, Y + TitleH - TextH - 3, rsPageTitle);
  Inc(Y, TitleH + 2);
  if FHasCommit then
  begin
    X := Px(Pad);
    DrawStatusIcon(FC, HintBranch, X, Y, TextH, FDim);
    Inc(X, TextH + Px(Gap) div 2);
    Line := FCommitName;
    if FSubject <> '' then
      Line := Line + ' · ' + FSubject;
    FC.Font.Color := FDim;
    FC.TextOut(X, Y, FitTextRight(FC, Line, Max(0, Width - Px(Pad) - X)));
  end
  else
    FC.TextOut(Px(Pad), Y, FitTextLeft(FC, FRoot, Width - 2 * Px(Pad)));
  Inc(Y, TextH);

  if not FHasCommit then
  begin
    Inc(Y, Px(Pad));
    PaintNote(Y, rsNoCommit, FDim);
  end
  else
  begin
    PaintCrumbs(Y);
    if FError <> '' then
      PaintNote(Y, FError, FErrorColor)
    else if Length(FEntries) = 0 then
      PaintNote(Y, rsEmptyFolder, FDim)
    else
      PaintRows(Y);
  end;

  { Layout sets the height from this. }
  FContentHeight := Y + Px(Pad);
end;

procedure TGittanFilesPage.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(LinkAt(X, Y));
end;

procedure TGittanFilesPage.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1);
end;

procedure TGittanFilesPage.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  i, n: integer;
  Url: string;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  i := LinkAt(X, Y);
  if i < 0 then
    Exit;
  Url := FLinkUrls[i];
  if Copy(Url, 1, Length(FolderLink)) = FolderLink then
  begin
    LoadFolder(Copy(Url, Length(FolderLink) + 1, MaxInt));
    if Assigned(FOnFolderChange) then
      FOnFolderChange(Self);
  end
  else if Copy(Url, 1, Length(EntryLink)) = EntryLink then
  begin
    n := StrToIntDef(Copy(Url, Length(EntryLink) + 1, MaxInt), -1);
    if Assigned(FOnOpen) and (n >= 0) and (n <= High(FEntries)) then
      FOnOpen(Self, FEntries[n]);
  end;
end;

end.
