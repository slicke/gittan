unit gittan.mdpreview;

{** The preview of a Markdown, HTML or SVG file beside the editor: the
  text drawn as GitHub draws it (headings, lists, tables, quotes,
  highlighted code, images), by the vendored LazInk (vendor/lazink),
  which lays HTML and Markdown out on the canvas with no browser engine.
  LazInk draws no SVG, so an SVG file, and an SVG image a page links to,
  is drawn by BGRABitmap's BGRASVG and handed to the page as a PNG
  through OnResource. A changed SVG is drawn twice, before and after,
  at one scale, each under a caption with its size, the new one telling
  how many of the pixels differ, as the image view does. A changed
  Markdown or HTML page is drawn with its changes marked (see
  gittan.richdiff): a bar beside the blocks that are new or changed, and
  the deleted ones struck through where they were.

  The page takes its colors from the form, as the image view does, and
  keeps its scroll position when the same file is shown again, so it
  follows an edit without jumping to the top. Relative images and links
  are resolved against the file's folder; a link to another local file
  goes to OnOpenFile, one to the web to the browser, and one to a
  heading of the page scrolls there. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, InkPage;

type
  {** A local file a link points at, by its full path. }
  TGittanOpenFileEvent = procedure(Sender: TObject; const AFileName: string) of object;

  { TGittanMarkdownPreview }

  TGittanMarkdownPreview = class(TInkPage)
  private
    FFileName, FText, FOldText: string;
    FCompare: boolean;
    FSvgSerial, FSvgZoom: integer;
    FBack, FFore, FDim, FLink: TColor;
    FDark: boolean;
    FOnOpenFile: TGittanOpenFileEvent;
    procedure ApplyStyle;
    procedure Show(const AFileName, AText, AOldText: string; ACompare: boolean);
    procedure Load;
    procedure ShowSvg(const AText: string);
    procedure ShowSvgChange;
    procedure ShowRichDiff;
    procedure PageResource(Sender: TObject; const URL: string; Destination: TStream;
      var Handled: boolean);
    procedure PageLinkActivate(Sender: TObject; const Link: TInkLinkInfo;
      var Handled: boolean);
  public
    constructor Create(AOwner: TComponent); override;
    {** Shows AText, the text of the file AFileName (a full path, which
      places its relative links and images), as Markdown, HTML or SVG by
      its extension. The same text again does nothing; the same file
      keeps the scroll position. }
    procedure ShowFile(const AFileName, AText: string);
    {** Shows a change of the file AFileName: ANew, its new text, as
      ShowFile does, an SVG as AOld and ANew drawn one above the other,
      before and after, and a Markdown or HTML page with what changed
      since AOld marked. An empty side has no version (an added or a
      deleted file); an added page is shown as it is. }
    procedure ShowChange(const AFileName, AOld, ANew: string);
    {** Forgets the text, so the next ShowFile draws it again. }
    procedure Clear;
    {** The palette: the background, the text, quotes and rules, and
      links. ADark picks the page's color scheme. }
    procedure SetColors(ABack, AText, ADim, ALink: TColor; ADark: boolean);
    {** The size of the body text in points, which the headings and the
      code are measured from. }
    procedure SetFontSize(ASize: integer);
    property FileName: string read FFileName;
    property OnOpenFile: TGittanOpenFileEvent read FOnOpenFile write FOnOpenFile;
  end;

{** Whether APath names a Markdown file, by its extension. }
function IsMarkdownPath(const APath: string): boolean;

{** Whether APath names an HTML file, by its extension. }
function IsHtmlPath(const APath: string): boolean;

{** Whether APath names an SVG file, by its extension. }
function IsSvgPath(const APath: string): boolean;

{** Whether the preview shows APath: Markdown, HTML or SVG. }
function IsPreviewPath(const APath: string): boolean;

implementation

uses
  LCLIntf, URIParser, Math, BGRABitmap, BGRABitmapTypes, BGRASVG, BGRACanvas2D,
  InkMarkdown, gittan.imagediff, gittan.richdiff;

resourcestring
  rsCannotReadSvg = 'The SVG cannot be read.';
  rsCannotDraw = 'Cannot draw this SVG';

const
  { The URL of the SVG file the page shows, numbered per load, since
    LazInk keeps a picture by its URL. }
  SvgScheme = 'gittan-svg:';
  { The end of the URL of the old side of a change. }
  OldSuffix = '-old.png';
  { A small SVG, an icon, is drawn larger: up to this many pixels on its
    longer side, a whole number of times its size. }
  SvgMinSide = 256;
  SvgMaxZoom = 8;

function IsMarkdownPath(const APath: string): boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(APath));
  Result := (Ext = '.md') or (Ext = '.markdown') or (Ext = '.mdown') or
    (Ext = '.mkd') or (Ext = '.mkdn');
end;

function IsHtmlPath(const APath: string): boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(APath));
  Result := (Ext = '.html') or (Ext = '.htm');
end;

function IsSvgPath(const APath: string): boolean;
begin
  Result := LowerCase(ExtractFileExt(APath)) = '.svg';
end;

function IsPreviewPath(const APath: string): boolean;
begin
  Result := IsMarkdownPath(APath) or IsHtmlPath(APath) or IsSvgPath(APath);
end;

{ The size ASvg is drawn at by itself, in pixels; 0 by 0 when
  it cannot be read. }
function SvgSize(ASvg: TBGRASVG): TPointF;
begin
  if ASvg.preserveAspectRatio.Preserve then
    Result := ASvg.ViewSizeInUnit[cuPixel]
  else
    Result := PointF(ASvg.WidthAsPixel, ASvg.HeightAsPixel);
end;

{ The size of AText, an SVG, in pixels; 0 by 0 when it cannot be read. }
function SvgTextSize(const AText: string): TPointF;
var
  Svg: TBGRASVG;
begin
  Result := PointF(0, 0);
  if AText = '' then
    Exit;
  try
    Svg := TBGRASVG.CreateFromString(AText);
    try
      Result := SvgSize(Svg);
    finally
      Svg.Free;
    end;
  except
    Result := PointF(0, 0);
  end;
end;

{ AText, an SVG, drawn AZoom times its size; nil when it cannot be read
  or has no size. }
function SvgBitmap(const AText: string; AZoom: single): TBGRABitmap;
var
  Svg: TBGRASVG;
  C2d: TBGRACanvas2D;
  Size: TPointF;
begin
  Result := nil;
  Svg := nil;
  try
    try
      Svg := TBGRASVG.CreateFromString(AText);
      Size := SvgSize(Svg);
      if (Size.X < 1) or (Size.Y < 1) then
        Exit;
      Result := TBGRABitmap.Create(Ceil(Size.X * AZoom), Ceil(Size.Y * AZoom));
      C2d := TBGRACanvas2D.Create(Result);
      try
        Svg.StretchDraw(C2d, 0, 0, Result.Width, Result.Height, True);
      finally
        C2d.Free;
      end;
    except
      FreeAndNil(Result);
    end;
  finally
    Svg.Free;
  end;
end;

{ AText, an SVG, drawn AZoom times its size as a PNG into ADest. False
  when it cannot be read or has no size. }
function RenderSvg(const AText: string; AZoom: single; ADest: TStream): boolean;
var
  Bmp: TBGRABitmap;
begin
  Bmp := SvgBitmap(AText, AZoom);
  Result := Bmp <> nil;
  if Result then
    try
      Bmp.SaveToStreamAsPng(ADest);
    finally
      Bmp.Free;
    end;
end;

{ A TColor as CSS, system colors resolved. }
function Css(AColor: TColor): string;
var
  c: longint;
begin
  c := ColorToRGB(AColor);
  Result := Format('#%.2x%.2x%.2x', [Red(c), Green(c), Blue(c)]);
end;

{ AFrom moved AWeight of the way to ATo. }
function Mix(AFrom, ATo: TColor; AWeight: double): TColor;
var
  f, t: longint;
begin
  f := ColorToRGB(AFrom);
  t := ColorToRGB(ATo);
  Result := RGBToColor(Round(Red(f) + (Red(t) - Red(f)) * AWeight),
    Round(Green(f) + (Green(t) - Green(f)) * AWeight),
    Round(Blue(f) + (Blue(t) - Blue(f)) * AWeight));
end;

constructor TGittanMarkdownPreview.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BorderStyle := bsNone;
  { A README's badges and <details> are HTML; the text is the user's
    own repository, not something from the web. }
  MarkdownRawHTML := True;
  ImageFit := iifWidth;
  OnLinkActivate := @PageLinkActivate;
  OnResource := @PageResource;
  FBack := clWindow;
  FFore := clWindowText;
  FDim := clGrayText;
  FLink := clHighlight;
end;

{ The page's own sheet: the body in the editor's colors, with room at
  the sides, at the control's font size (CSS's medium). LazInk adds GitHub's look of Markdown (quotes, code, tables)
  on top, mixed from Color and Font.Color, but shades code toward white,
  which a white page does not show, so code is shaded toward the text
  here. Images are no wider than the
  column, but never stretched past their own size. The blocks a rich
  diff marks get a bar in the margin in the diff's colors (a table row
  and a list item a tint, since a row draws no border and an item's bar
  would fall between its bullet and its text), a deleted one struck
  through. }
procedure TGittanMarkdownPreview.ApplyStyle;
var
  AddedColor, ChangedColor, DeletedColor: TColor;
begin
  if FDark then
  begin
    AddedColor := RGBToColor(63, 185, 80);
    ChangedColor := RGBToColor(210, 153, 34);
    DeletedColor := RGBToColor(248, 81, 73);
  end
  else
  begin
    AddedColor := RGBToColor(26, 127, 55);
    ChangedColor := RGBToColor(154, 103, 0);
    DeletedColor := RGBToColor(207, 34, 46);
  end;
  Color := FBack;
  Font.Color := FFore;
  StyleSheet.Text :=
    'html, body { background: ' + Css(FBack) + '; }' +
    'body { color: ' + Css(FFore) + '; font-family: sans-serif; ' +
    'line-height: 1.5; margin: 0; padding: 16px 24px; }' +
    'h1, h2 { padding-bottom: 0.3em; border-bottom: 1px solid ' + Css(FDim) + '; }' +
    'a { color: ' + Css(FLink) + '; }' +
    'pre, code { background: ' + Css(Mix(FBack, FFore, 0.07)) + '; }' +
    'pre code { background: transparent; }' +
    'img { max-width: 100%; width: auto; }' +
    '.' + RichAddedClass + ', .' + RichChangedClass + ', .' + RichDeletedClass +
    ' { padding-left: 9px; margin-left: -12px; }' +
    '.' + RichAddedClass + ' { border-left: 3px solid ' + Css(AddedColor) + '; }' +
    '.' + RichChangedClass + ' { border-left: 3px solid ' + Css(ChangedColor) + '; }' +
    '.' + RichDeletedClass + ' { border-left: 3px solid ' + Css(DeletedColor) + '; ' +
    'color: ' + Css(Mix(FFore, DeletedColor, 0.6)) + '; text-decoration: line-through; }' +
    'tr.' + RichAddedClass + ' td, li.' + RichAddedClass + ' { background: ' +
    Css(Mix(FBack, AddedColor, 0.18)) + '; }' +
    'tr.' + RichChangedClass + ' td, li.' + RichChangedClass + ' { background: ' +
    Css(Mix(FBack, ChangedColor, 0.18)) + '; }' +
    'tr.' + RichDeletedClass + ' td, li.' + RichDeletedClass + ' { background: ' +
    Css(Mix(FBack, DeletedColor, 0.18)) + '; }' +
    'li.' + RichAddedClass + ', li.' + RichChangedClass + ', li.' + RichDeletedClass +
    ' { border-left: none; padding-left: 0; margin-left: 0; }';
end;

procedure TGittanMarkdownPreview.ShowFile(const AFileName, AText: string);
begin
  Show(AFileName, AText, '', False);
end;

procedure TGittanMarkdownPreview.ShowChange(const AFileName, AOld, ANew: string);
begin
  Show(AFileName, ANew, AOld, IsSvgPath(AFileName) or
    ((AOld <> '') and (AOld <> ANew)));
end;

procedure TGittanMarkdownPreview.Show(const AFileName, AText, AOldText: string;
  ACompare: boolean);
var
  Same: boolean;
  Y: integer;
begin
  if (AFileName = FFileName) and (AText = FText) and (ACompare = FCompare) and
    (AOldText = FOldText) then
    Exit;
  Same := AFileName = FFileName;
  Y := ScrollY;
  FFileName := AFileName;
  FText := AText;
  FOldText := AOldText;
  FCompare := ACompare;
  Load;
  if Same then
    ScrollTo(Y);
end;

{ Puts the text kept in the fields on the page. Every load is a step of
  the page's history; the preview has none. }
procedure TGittanMarkdownPreview.Load;
begin
  if FCompare and IsSvgPath(FFileName) then
    ShowSvgChange
  else if FCompare then
    ShowRichDiff
  else if IsSvgPath(FFileName) then
    ShowSvg(FText)
  else if IsHtmlPath(FFileName) then
    LoadHTML(FText, FilenameToURI(FFileName))
  else
    LoadMarkdown(FText, FilenameToURI(FFileName));
  ClearHistory;
end;

{ The SVG centered on a page of its own, at its size or, a small one, a
  whole number of times larger; PageResource draws it at the screen's
  pixels. One that cannot be read says so. }
procedure TGittanMarkdownPreview.ShowSvg(const AText: string);
var
  Size: TPointF;
begin
  Size := SvgTextSize(AText);
  Inc(FSvgSerial);
  if (Size.X < 1) or (Size.Y < 1) then
  begin
    LoadHTML('<p style="text-align: center; color: ' + Css(FDim) + '">' +
      rsCannotReadSvg + '</p>');
    Exit;
  end;
  FSvgZoom := EnsureRange(Trunc(SvgMinSide / Max(Size.X, Size.Y)), 1, SvgMaxZoom);
  LoadHTML(Format('<p style="text-align: center"><img src="%s%d.png" ' +
    'style="width: %dpx"></p>', [SvgScheme, FSvgSerial, Ceil(Size.X * FSvgZoom)]),
    FilenameToURI(FFileName));
end;

{ Both sides of a changed SVG, before over after, at one scale: the
  zoom ShowSvg would give the larger of the two. Each has a caption with
  its size in pixels and bytes, the new side how many of the pixels
  differ when the sizes match (counted at the SVG's own size); a side
  without a version, or one that cannot be drawn, says so in a dotted
  box. }
procedure TGittanMarkdownPreview.ShowSvgChange;
const
  Suffix: array[0..1] of string = (OldSuffix, '.png');
var
  Texts: array[0..1] of string;
  Sizes: array[0..1] of TPointF;
  Bmps: array[0..1] of TBGRABitmap;
  Differing: int64;
  Html, Detail, Faint: string;
  Side: integer;
  Longest: single;
  Drawn: boolean;
begin
  Texts[0] := FOldText;
  Texts[1] := FText;
  Longest := 0;
  for Side := 0 to 1 do
  begin
    Sizes[Side] := SvgTextSize(Texts[Side]);
    if (Sizes[Side].X >= 1) and (Sizes[Side].Y >= 1) then
      Longest := Max(Longest, Max(Sizes[Side].X, Sizes[Side].Y));
  end;
  FSvgZoom := 1;
  if Longest > 0 then
    FSvgZoom := EnsureRange(Trunc(SvgMinSide / Longest), 1, SvgMaxZoom);
  Differing := -1;
  if (Sizes[0].X >= 1) and (Sizes[1].X >= 1) then
  begin
    Bmps[0] := SvgBitmap(Texts[0], 1);
    Bmps[1] := SvgBitmap(Texts[1], 1);
    try
      Differing := DifferingPixels(Bmps[0], Bmps[1]);
    finally
      Bmps[0].Free;
      Bmps[1].Free;
    end;
  end;
  Inc(FSvgSerial);
  Faint := Css(Mix(FBack, FFore, 0.55));
  Html := '';
  for Side := 0 to 1 do
  begin
    if Side = 0 then
      Html := Html + '<p style="margin: 0 0 4px 0"><b>' + rsBefore + '</b>'
    else
      Html := Html + '<p style="margin: 24px 0 4px 0"><b>' + rsAfter + '</b>';
    Detail := '';
    Drawn := (Texts[Side] <> '') and (Sizes[Side].X >= 1) and (Sizes[Side].Y >= 1);
    if Drawn then
    begin
      Detail := Format(rsImageSize, [Ceil(Sizes[Side].X), Ceil(Sizes[Side].Y)]) +
        ' · ' + ByteSize(Length(Texts[Side]));
      if (Side = 1) and (Differing >= 0) then
        Detail := Detail + ' · ' + DifferingNote(Differing,
          int64(Ceil(Sizes[1].X)) * Ceil(Sizes[1].Y));
    end
    else if Texts[Side] <> '' then
      Detail := ByteSize(Length(Texts[Side]));
    if Detail <> '' then
      Html := Html + '<br><span style="color: ' + Faint + '">' + Detail + '</span>';
    Html := Html + '</p>';
    if Texts[Side] = '' then
      Html := Html + '<p style="text-align: center; color: ' + Faint +
        '; border: 1px dashed ' + Faint + '; padding: 24px">' + rsNotInVersion + '</p>'
    else if not Drawn then
      Html := Html + '<p style="text-align: center; color: ' + Faint +
        '; border: 1px dashed ' + Faint + '; padding: 24px">' + rsCannotDraw + '</p>'
    else
      Html := Html + Format('<p style="text-align: center"><img src="%s%d%s" ' +
        'style="width: %dpx"></p>', [SvgScheme, FSvgSerial, Suffix[Side],
        Ceil(Sizes[Side].X * FSvgZoom)]);
  end;
  LoadHTML(Html, FilenameToURI(FFileName));
end;

{ The new page with its changes from the old marked, the classes of
  gittan.richdiff drawn by the style sheet. It is loaded as HTML, which
  LazInk does not give the look of Markdown (MarkdownSheet), so a
  Markdown page carries that sheet itself, followed by ours again, since
  a page's own sheet wins over the host's. The sheet is in the control's
  colors, so SetColors loads the page again. }
procedure TGittanMarkdownPreview.ShowRichDiff;
var
  Html: string;
  p: integer;
begin
  if IsHtmlPath(FFileName) then
  begin
    LoadHTML(MarkRichDiff(FOldText, FText), FilenameToURI(FFileName));
    Exit;
  end;
  Html := MarkRichDiff(MarkdownToHTML(FOldText, [imoRawHTML]),
    MarkdownToHTML(FText, [imoRawHTML]));
  p := Pos('<head>', Html);
  if p > 0 then
    Insert('<style>' + MarkdownSheet + StyleSheet.Text + '</style>', Html,
      p + Length('<head>'));
  LoadHTML(Html, FilenameToURI(FFileName));
end;

{ The SVG file shown, both sides of a changed one, and an SVG image of a
  page, drawn as a PNG: the file at the screen's pixels at the width
  ShowSvg or ShowSvgChange set, an image at its own size, since the
  page draws it at the PNG's. }
procedure TGittanMarkdownPreview.PageResource(Sender: TObject; const URL: string;
  Destination: TStream; var Handled: boolean);
var
  Path: string;
  Lines: TStringList;
begin
  if Copy(URL, 1, Length(SvgScheme)) = SvgScheme then
  begin
    if Copy(URL, Length(URL) - Length(OldSuffix) + 1, MaxInt) = OldSuffix then
      Handled := RenderSvg(FOldText, FSvgZoom * GetCanvasScaleFactor, Destination)
    else
      Handled := RenderSvg(FText, FSvgZoom * GetCanvasScaleFactor, Destination);
    Exit;
  end;
  if not IsSvgPath(URL) or not URIToFilename(URL, Path) or not FileExists(Path) then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(Path);
    Handled := RenderSvg(Lines.Text, 1, Destination);
  finally
    Lines.Free;
  end;
end;

procedure TGittanMarkdownPreview.Clear;
begin
  FFileName := '';
  FText := '';
  FOldText := '';
  FCompare := False;
end;

procedure TGittanMarkdownPreview.SetColors(ABack, AText, ADim, ALink: TColor;
  ADark: boolean);
var
  Y: integer;
begin
  FBack := ABack;
  FFore := AText;
  FDim := ADim;
  FLink := ALink;
  FDark := ADark;
  if ADark then
    ColorScheme := icsDark
  else
    ColorScheme := icsLight;
  ApplyStyle;
  if FCompare and not IsSvgPath(FFileName) then
  begin
    Y := ScrollY;
    ShowRichDiff;
    ClearHistory;
    ScrollTo(Y);
  end;
end;

{ The page takes the size as it loads, so a page shown is loaded again
  at the new size, where it was scrolled to. }
procedure TGittanMarkdownPreview.SetFontSize(ASize: integer);
var
  Y: integer;
begin
  if Font.Size = ASize then
    Exit;
  Font.Size := ASize;
  if FFileName = '' then
    Exit;
  Y := ScrollY;
  Load;
  ScrollTo(Y);
end;

{ A heading of this page scrolls there; another local file goes to the
  form, anything else to the browser. }
procedure TGittanMarkdownPreview.PageLinkActivate(Sender: TObject;
  const Link: TInkLinkInfo; var Handled: boolean);
var
  Url, Anchor, Path: string;
  p: integer;
begin
  Handled := True;
  Url := Link.URL;
  Anchor := '';
  p := Pos('#', Url);
  if p > 0 then
  begin
    Anchor := Copy(Url, p + 1, MaxInt);
    Url := Copy(Url, 1, p - 1);
  end;
  if (Url = '') or (Url = Location) then
  begin
    if Anchor <> '' then
      JumpToAnchor(Anchor);
    Exit;
  end;
  if URIToFilename(Url, Path) then
  begin
    if Assigned(FOnOpenFile) and FileExists(Path) then
      FOnOpenFile(Self, Path);
    Exit;
  end;
  OpenURL(Link.URL);
end;

end.
