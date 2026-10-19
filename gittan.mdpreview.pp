unit gittan.mdpreview;

{** The preview of a Markdown file beside the editor: the text drawn as
  GitHub draws it (headings, lists, tables, quotes, highlighted code,
  images), by the vendored LazInk (vendor/lazink), which lays HTML and
  Markdown out on the canvas with no browser engine.

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
    FFileName, FText: string;
    FBack, FFore, FDim, FLink: TColor;
    FOnOpenFile: TGittanOpenFileEvent;
    procedure ApplyStyle;
    procedure PageLinkActivate(Sender: TObject; const Link: TInkLinkInfo;
      var Handled: boolean);
  public
    constructor Create(AOwner: TComponent); override;
    {** Shows AText, the Markdown of the file AFileName (a full path,
      which places its relative links and images). The same text again
      does nothing; the same file keeps the scroll position. }
    procedure ShowMarkdown(const AFileName, AText: string);
    {** Forgets the text, so the next ShowMarkdown draws it again. }
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

implementation

uses
  LCLIntf, URIParser;

function IsMarkdownPath(const APath: string): boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(APath));
  Result := (Ext = '.md') or (Ext = '.markdown') or (Ext = '.mdown') or
    (Ext = '.mkd') or (Ext = '.mkdn');
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
  column, but never stretched past their own size. }
procedure TGittanMarkdownPreview.ApplyStyle;
begin
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
    'img { max-width: 100%; width: auto; }';
end;

procedure TGittanMarkdownPreview.ShowMarkdown(const AFileName, AText: string);
var
  Same: boolean;
  Y: integer;
begin
  if (AFileName = FFileName) and (AText = FText) then
    Exit;
  Same := AFileName = FFileName;
  Y := ScrollY;
  FFileName := AFileName;
  FText := AText;
  LoadMarkdown(AText, FilenameToURI(AFileName));
  { Every load is a step of the page's history; the preview has none. }
  ClearHistory;
  if Same then
    ScrollTo(Y);
end;

procedure TGittanMarkdownPreview.Clear;
begin
  FFileName := '';
  FText := '';
end;

procedure TGittanMarkdownPreview.SetColors(ABack, AText, ADim, ALink: TColor;
  ADark: boolean);
begin
  FBack := ABack;
  FFore := AText;
  FDim := ADim;
  FLink := ALink;
  if ADark then
    ColorScheme := icsDark
  else
    ColorScheme := icsLight;
  ApplyStyle;
end;

procedure TGittanMarkdownPreview.SetFontSize(ASize: integer);
begin
  if Font.Size <> ASize then
    Font.Size := ASize;
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
