unit gittan.forgepage;

{** The forge page: the user's pull requests across every repository
  of a forge (gittan.forge; its name from SetForge), a section at a
  time (Section, the owner's tabs, SectionCaption): the open ones they
  wrote, or the open ones waiting for their review, no wider than
  MaxContentWidth, centered in a wider page.
  A card has a pull request glyph (in the ok color, dim for a draft),
  the number and the title, at the right where its review stands
  (Draft, Approved, Changes requested, "Waiting for anna", "Waiting
  for 2 reviewers", Review required; PullReviewNote) and its checks
  ("✓ 5 checks", "2 of 5 checks failing", "checks pending";
  PullChecksNote, the checks the user ignores left out) as chips,
  "Asked again" on one the user is asked to review once more after
  reviewing it, under them the repository, who opened it and how long
  ago it was opened and last changed, with a link to the forge at the
  right end while the card is under the mouse, then a dim line with
  the reviewers ("anna approved · coderabbitai commented · waiting
  for chef"; PullReviewers) and the checks by name ("Failing: npm
  audit · Ignored: approval"; PullChecksDetail) when there is
  something to say, and under that one a link to the pull request's
  local clone (its Clone) when it is not the open repository
  (SetOpenRoot). A click on the checks chip, with either button, opens
  a menu of the checks by name, each a check item that ignores it or
  counts it again (IgnoredChecks, kept by the owner on
  OnFilterChange): an ignored check counts in neither the chip, the
  filters nor the order, for a check that fails for reasons of its
  own, say one that needs an approval the pull request still waits
  for.
  The filters are the forge's (SetFilters; TGittanForge.Filters, the
  base's StandardFilters), as chips in rows under a section's
  heading: the ones for the section, each on or off (MineFilters,
  ReviewFilters, their keys joined with commas; OnFilterChange;
  FilterPulls, every one on must pass), and after them a chip with the
  section's order (MineOrder, ReviewOrder; SortPulls) that opens a
  menu of the orders: the last changed first, the newest first and, of
  the user's own, the ones that need attention first. What needs
  attention is changes asked for or checks failing, either of which
  the user can leave out (AttentionReasons) from the menu of a right
  click on its chip or from the order's; a reason left out shows its
  card chip dim. Over the filters a row of presets: All (no filter),
  the forge's (TGittanForge.Presets) and the user's own (SetFilters'
  APresets holds both, the own ones after; Presets), the one whose
  filters are on highlighted, and, while the filters on match none,
  "Save as preset…", which raises OnSavePreset for the owner to ask a
  name and call AddPreset; a right click on an own preset offers to
  delete it. A card fills under the mouse and a click raises OnPick
  with the pull request, as one on its clone's link does, for the
  owner to compare with it when it is the open repository's, else in
  its clone, else to open it on the forge. An empty section says so in
  a card of its own with a large dim glyph.
  The head has the login's initial in a disc, the forge's name and the
  page's title with Refresh (OnRefresh) after them, a dot pulsing in
  its place while the forge is asked, and under them the login with the
  counts, or that the forge is asked; the forge's failure (not logged
  in) shows in the error color.

  It paints itself in the editor's palette, like the Pull Requests
  page, and sizes its height to its content so it can sit in the same
  TScrollBox: Layout paints the content on a measuring canvas to know
  the height before the control is shown. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, ExtCtrls, Menus, BGRABitmap, gittan.forge,
  gittan.summary;

const
  {** The sections, as the owner's tabs count them: Ord of
    TGittanForgeSection (gittan.forge). }
  SectionCount = 2;

type
  {** A click on a card: the pull request. }
  TGittanForgePickEvent = procedure(Sender: TObject; const APull: TGittanForgePull) of object;
  {** A right click on a card: the pull request and where to show a
    menu, in screen coordinates. }
  TGittanForgeContextEvent = procedure(Sender: TObject; const APull: TGittanForgePull;
    const AScreenPos: TPoint) of object;

  { A chip of a row: its text, the link a click follows, whether it is
    on (in the link color), and whether it is dim (an offer, not a
    state). }
  TGittanChipSpec = record
    Text, Link: string;
    IsOn, Dim: boolean;
  end;
  TGittanChipSpecs = array of TGittanChipSpec;


  { TGittanForgePage }

  TGittanForgePage = class(TCustomControl)
  private
    FForge, FLogin, FError, FOpenRoot: string;
    FMine, FReview: TGittanForgePulls;
    { The forge's filters and the presets, the forge's then the user's
      own; the filters on of each section as their keys; the checks
      ignored by name; and the lists as the filters leave them. }
    FDefs: TGittanForgeFilterDefs;
    FPresets: TGittanForgePresets;
    FMineKeys, FReviewKeys: string;
    FIgnored: TStringList;
    FShownMine, FShownReview: TGittanForgePulls;
    { What needs attention, each section's order, and the menu of the
      order and the reasons, of a card's checks (FMenuPull) or of a
      preset (FMenuPreset). }
    FAttention: TGittanAttentionReasons;
    FMineOrder, FReviewOrder: TGittanPullOrder;
    FMenu: TPopupMenu;
    FMenuPull: TGittanForgePull;
    FMenuPreset: integer;
    { The section shown: Ord(fsMine) or Ord(fsReview). }
    FSection: integer;
    { FLoading while the forge is asked; FAnswered once it has answered,
      so an empty section says so only then. }
    FLoading, FAnswered: boolean;
    FBack, FText, FDim, FHover, FLine, FLink, FOk, FWarn, FErrorColor, FCard: TColor;
    FLinkRects: array of TRect;
    FLinkUrls: array of string;
    FHot: integer;
    FContentHeight: integer;
    { The dot that pulses in Refresh's place while the forge is asked:
      its timer, its step and where it is painted. }
    FPulse: TTimer;
    FPhase: integer;
    FDotRect: TRect;
    { The canvas the content is painted on: the control's in Paint, a
      measuring one in Layout. }
    FC: TCanvas;
    { The user's picture as the forge sent it (FAvatarData, its bytes;
      FAvatar decoded, nil for none or one that could not be read) and
      as painted: resampled to the disc's pixels and cut round. }
    FAvatarData: string;
    FAvatar, FAvatarShown: TBGRABitmap;
    FOnPick: TGittanForgePickEvent;
    FOnRefresh, FOnFilterChange, FOnSavePreset: TNotifyEvent;
    FOnOpenUrl: TGittanOpenUrlEvent;
    FOnContext: TGittanForgeContextEvent;
    {** The pull request whose card is at X, Y; false between them. }
    function CardAt(X, Y: integer; out APull: TGittanForgePull): boolean;
    function LinkAt(X, Y: integer): integer;
    function CurSection: TGittanForgeSection;
    function SectionKeysOf(ASection: TGittanForgeSection): string;
    procedure SetHot(AValue: integer);
    procedure SetMineFilters(const AValue: string);
    procedure SetReviewFilters(const AValue: string);
    procedure SetIgnoredChecks(AValue: TStringList);
    procedure SetSection(AValue: integer);
    procedure SetAttention(AValue: TGittanAttentionReasons);
    procedure SetMineOrder(AValue: TGittanPullOrder);
    procedure SetReviewOrder(AValue: TGittanPullOrder);
    procedure ShowMenu(AOrders: boolean; const AScreenPos: TPoint);
    procedure ShowChecksMenu(const APull: TGittanForgePull; const AScreenPos: TPoint);
    procedure ShowPresetMenu(AIndex: integer; const AScreenPos: TPoint);
    procedure MenuOrderClick(Sender: TObject);
    procedure MenuAttentionClick(Sender: TObject);
    procedure MenuCheckClick(Sender: TObject);
    procedure MenuDeletePresetClick(Sender: TObject);
    procedure FilterChanged;
    procedure PulseTimer(Sender: TObject);
    procedure AddLink(const ARect: TRect; const AUrl: string);
    procedure PaintAvatar(ALeft, ATop, ASize: integer);
    procedure PaintRefresh(ALeft, ATop, ASize: integer);
    procedure PaintPullGlyph(ALeft, ATop, ASize: integer; AColor: TColor);
    procedure PaintCheckGlyph(ALeft, ATop, ASize: integer; AColor: TColor);
    procedure PaintHeading(var Y: integer; const ATitle, ADetail: string;
      AChips: boolean; ALeft, ARight: integer);
    function PresetChips: TGittanChipSpecs;
    function FilterChips: TGittanChipSpecs;
    procedure PaintChipRow(ALeft, ARight: integer; var ATop: integer;
      const AChips: array of TGittanChipSpec);
    procedure PaintNote(var Y: integer; const AText: string; AColor: TColor;
      ALeft, ARight: integer);
    procedure PaintEmpty(var Y: integer; const ATitle, AText: string; ACheck: boolean;
      ALeft, ARight: integer);
    function PaintChip(ARight, ATop: integer; const AText: string; AColor: TColor): TRect;
    procedure PaintCard(var Y: integer; const APull: TGittanForgePull; ALeft, ARight: integer;
      const ALink: string; AIndex: integer);
    function PullLine(const APull: TGittanForgePull): string;
    procedure PaintSection(var Y: integer; const ATitle: string; const APulls: TGittanForgePulls;
      ATotal: integer; const AEmptyTitle, AEmpty, ALinkPrefix: string; AEmptyCheck: boolean;
      ALeft, ARight: integer);
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
    destructor Destroy; override;
    {** The forge shown, by name: the page's title and its links. }
    procedure SetForge(const AName: string);
    {** The login the forge knows the user as; empty before it answered. }
    procedure SetLogin(const ALogin: string);
    {** The user's picture as the forge sent it (PNG or JPEG bytes), in
      the disc of the head in place of the initial; empty, or bytes that
      are not a picture, for the initial. }
    procedure SetAvatar(const AData: string);
    {** The root of the open repository, empty when none is open: a card
      whose clone it is has no link to it, since its click compares
      there. }
    procedure SetOpenRoot(const ARoot: string);
    {** The pull requests the user wrote and those waiting for their
      review, the forge's message when it failed (else ''), and whether
      it is being asked now. }
    procedure SetPulls(const AMine, AReview: TGittanForgePulls; const AError: string;
      ALoading: boolean);
    {** Forgets that the forge answered (another forge or account), so
      an empty section says nothing until the new one has. }
    procedure ForgetAnswer;
    {** The forge's filters (its Filters) and the presets to offer: the
      forge's (its Presets) and the user's own after them (ParsePresets
      of the settings' value). }
    procedure SetFilters(const ADefs: TGittanForgeFilterDefs;
      const APresets: TGittanForgePresets);
    {** Adds a preset of the user's own, of the section shown with the
      filters on now, named AName (PresetName); one of the section with
      that name is replaced. Raises OnFilterChange. }
    procedure AddPreset(const AName: string);
    {** The palette: the background, the text, the dim text, the fill
      under the mouse, the dividers, the links, the ok, the warning and
      the error colors. }
    procedure SetColors(ABack, AText, ADim, AHover, ALine, ALink, AOk, AWarn, AError: TColor);
    {** The fill of the cards. }
    procedure SetCardColor(ACard: TColor);
    {** The palette of the dark or the light appearance: the editor's
      background and text, the dim text, the hover, the dividers, the
      link color and the ok, warning and error tones the Pull Requests
      page has, and the cards' fill. }
    procedure SetTheme(ADark: boolean);
    {** Makes the control at least AMin high (the height of the box it
      sits in, so its background covers the box), and no higher than its
      content needs beyond that. }
    procedure FitHeight(AMin: integer);
    {** The filters on in each section, their keys joined with commas
      (a key the forge lacks is kept but does nothing); a click on a
      chip changes them and raises OnFilterChange. }
    property MineFilters: string read FMineKeys write SetMineFilters;
    property ReviewFilters: string read FReviewKeys write SetReviewFilters;
    {** The checks that do not count, by name; the checks menu changes
      them and raises OnFilterChange. }
    property IgnoredChecks: TStringList read FIgnored write SetIgnoredChecks;
    {** The presets as given to SetFilters, with the ones the user added
      or without the ones they deleted since (the own ones are the
      settings', JoinPresets). }
    property Presets: TGittanForgePresets read FPresets;
    {** What makes one of the user's pull requests need attention, for
      its filter and its order; all of them by default. The menus
      change it and raise OnFilterChange. }
    property AttentionReasons: TGittanAttentionReasons read FAttention write SetAttention;
    {** The order of each section, poUpdated by default; the ones
      waiting for review are never in poAttentionFirst. The order's
      chip changes it and raises OnFilterChange. }
    property MineOrder: TGittanPullOrder read FMineOrder write SetMineOrder;
    property ReviewOrder: TGittanPullOrder read FReviewOrder write SetReviewOrder;
    {** The section shown, Ord(fsMine) (the default) or Ord(fsReview). }
    property Section: integer read FSection write SetSection;
    property OnFilterChange: TNotifyEvent read FOnFilterChange write FOnFilterChange;
    {** A click on "Save as preset…": the owner asks a name and calls
      AddPreset. }
    property OnSavePreset: TNotifyEvent read FOnSavePreset write FOnSavePreset;
    property OnPick: TGittanForgePickEvent read FOnPick write FOnPick;
    {** A right click on a card, for a menu. }
    property OnContext: TGittanForgeContextEvent read FOnContext write FOnContext;
    property OnRefresh: TNotifyEvent read FOnRefresh write FOnRefresh;
    property OnOpenUrl: TGittanOpenUrlEvent read FOnOpenUrl write FOnOpenUrl;
  end;

{** A section's name, for its tab. }
function SectionCaption(ASection: integer): string;

implementation

uses
  Math, DateUtils, LCLIntf, LCLType, BGRABitmapTypes, gittan.reviews, gittan.textfit, gittan.theme;

resourcestring
  rsPageTitle = 'Pull requests';
  rsMineTab = 'Open';
  rsReviewTab = 'Waiting for review';
  rsMineGroup = 'Your open pull requests';
  rsReviewGroup = 'Waiting for your review';
  rsOneOpen = '1 open';
  rsManyOpen = '%d open';
  rsSomeOpen = '%d of %d open';
  rsToReview = '%d to review';
  rsAllChip = 'All';
  rsSavePresetChip = 'Save as preset…';
  rsDeletePreset = 'Delete Preset “%s”';
  rsIgnoreCheck = 'Ignore Check “%s”';
  rsNoMatch = 'None of them match the filters.';
  rsOrderUpdated = 'Last updated';
  rsOrderNewest = 'Newest';
  rsOrderAttention = 'Needs attention first';
  rsMenuUpdated = 'Last Updated First';
  rsMenuNewest = 'Newest First';
  rsMenuAttention = 'Needs Attention First';
  rsChangesAttention = 'Changes Requested Need Attention';
  rsChecksAttention = 'Failing Checks Need Attention';
  rsLoading = 'Asking %s…';
  rsNoMine = 'No open pull requests of yours.';
  rsCaughtUp = 'All caught up';
  rsNoReview = 'Nothing waiting for your review.';
  rsForgeLink = '%s ↗';
  rsCloneLink = 'Open %s';
  rsDraft = 'Draft';
  rsAskedAgain = 'Asked again';
  rsOpened = 'opened %s';
  rsUpdated = 'updated %s';

const
  MineLink = 'gittan:mine:';
  ReviewLink = 'gittan:review:';
  RefreshLink = 'gittan:refresh';
  FilterLink = 'gittan:filter:';
  PresetLink = 'gittan:preset:';
  AllPresetLink = 'gittan:preset:all';
  SavePresetLink = 'gittan:savepreset';
  ChecksLink = 'gittan:checks:';
  OrderLink = 'gittan:order';
  OrderGlyph = ' ▾';
  RefreshGlyph = '↻';
  Pad = 24;
  Gap = 12;
  TitleFontSize = 20;
  { The content no wider than this, centered in a wider page. }
  MaxContentWidth = 960;
  { The cards: their padding and corner radius; the chips at their
    right; the room between the glyph and the text; the room between
    two of their lines. }
  CardPadX = 14;
  CardPadY = 10;
  CardRadius = 12;
  CardGap = 8;
  GlyphGap = 10;
  ChipPadX = 6;
  ChipPadY = 2;
  ChipRadius = 6;
  LineGap = 4;
  { An empty section's card: its glyph and the room above and below. }
  EmptyGlyph = 30;
  EmptyPadY = 22;
  { The filter chips: their padding, and the room between two. }
  FilterPadX = 10;
  FilterPadY = 2;
  FilterGap = 6;
  { The dot pulsing while the forge is asked: its size, its timer's
    step and the steps of one pulse. }
  DotSize = 8;
  PulseStep = 40;
  PulseSteps = 36;

function SectionCaption(ASection: integer): string;
begin
  if ASection = Ord(fsReview) then
    Result := rsReviewTab
  else
    Result := rsMineTab;
end;

{ A chip of a row. }
function Chip(const AText, ALink: string; AOn: boolean; ADim: boolean = False): TGittanChipSpec;
begin
  Result.Text := AText;
  Result.Link := ALink;
  Result.IsOn := AOn;
  Result.Dim := ADim;
end;

constructor TGittanForgePage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FHot := -1;
  Align := alTop;
  SetColors(clWindow, clWindowText, clGrayText, clBtnFace, clBtnShadow, clHighlight,
    clGreen, clOlive, clRed);
  FCard := clBtnFace;
  FAttention := AllAttentionReasons;
  FDefs := StandardFilters;
  FPresets := StandardPresets;
  FIgnored := TStringList.Create;
  FMenu := TPopupMenu.Create(Self);
  FMenuPreset := -1;
  FPulse := TTimer.Create(Self);
  FPulse.Enabled := False;
  FPulse.Interval := PulseStep;
  FPulse.OnTimer := @PulseTimer;
end;

destructor TGittanForgePage.Destroy;
begin
  FAvatarShown.Free;
  FAvatar.Free;
  FIgnored.Free;
  inherited Destroy;
end;

procedure TGittanForgePage.SetAvatar(const AData: string);
var
  Stream: TStringStream;
begin
  if AData = FAvatarData then
    Exit;
  FAvatarData := AData;
  FreeAndNil(FAvatarShown);
  FreeAndNil(FAvatar);
  if AData <> '' then
  begin
    Stream := TStringStream.Create(AData);
    try
      try
        FAvatar := TBGRABitmap.Create(Stream);
        if (FAvatar.Width = 0) or (FAvatar.Height = 0) then
          FreeAndNil(FAvatar);
      except
        FreeAndNil(FAvatar);
      end;
    finally
      Stream.Free;
    end;
  end;
  Invalidate;
end;

procedure TGittanForgePage.SetForge(const AName: string);
begin
  FForge := AName;
  Layout;
  Invalidate;
end;

procedure TGittanForgePage.SetLogin(const ALogin: string);
begin
  if FLogin = ALogin then
    Exit;
  FLogin := ALogin;
  Layout;
  Invalidate;
end;

procedure TGittanForgePage.SetOpenRoot(const ARoot: string);
begin
  if FOpenRoot = ARoot then
    Exit;
  FOpenRoot := ARoot;
  Layout;
  Invalidate;
end;

procedure TGittanForgePage.ForgetAnswer;
begin
  FAnswered := False;
end;

procedure TGittanForgePage.SetPulls(const AMine, AReview: TGittanForgePulls;
  const AError: string; ALoading: boolean);
begin
  FMine := Copy(AMine);
  FReview := Copy(AReview);
  FError := AError;
  FLoading := ALoading;
  FAnswered := FAnswered or not ALoading;
  FHot := -1;
  FPhase := 0;
  FPulse.Enabled := ALoading;
  Layout;
  Invalidate;
end;

procedure TGittanForgePage.SetMineFilters(const AValue: string);
begin
  if FMineKeys = AValue then
    Exit;
  FMineKeys := AValue;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanForgePage.SetReviewFilters(const AValue: string);
begin
  if FReviewKeys = AValue then
    Exit;
  FReviewKeys := AValue;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanForgePage.SetAttention(AValue: TGittanAttentionReasons);
begin
  if FAttention = AValue then
    Exit;
  FAttention := AValue;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanForgePage.SetMineOrder(AValue: TGittanPullOrder);
begin
  if FMineOrder = AValue then
    Exit;
  FMineOrder := AValue;
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanForgePage.SetReviewOrder(AValue: TGittanPullOrder);
begin
  if AValue = poAttentionFirst then
    AValue := poUpdated;
  if FReviewOrder = AValue then
    Exit;
  FReviewOrder := AValue;
  FHot := -1;
  Layout;
  Invalidate;
end;

{ An order's caption. }
function OrderCaption(AOrder: TGittanPullOrder): string;
begin
  case AOrder of
    poNewest: Result := rsOrderNewest;
    poAttentionFirst: Result := rsOrderAttention;
  else
    Result := rsOrderUpdated;
  end;
end;

{ An order's caption in its menu. }
function OrderMenuCaption(AOrder: TGittanPullOrder): string;
begin
  case AOrder of
    poNewest: Result := rsMenuNewest;
    poAttentionFirst: Result := rsMenuAttention;
  else
    Result := rsMenuUpdated;
  end;
end;

{ The menu at AScreenPos: with AOrders the section's orders, the one it
  has checked; for the user's own the reasons that need attention,
  those counted checked. }

procedure TGittanForgePage.ShowMenu(AOrders: boolean; const AScreenPos: TPoint);
var
  Shown, Last: TGittanPullOrder;
  O: TGittanPullOrder;
  Item: TMenuItem;

  procedure AddReason(const ACaption: string; AReason: TGittanAttentionReason);
  begin
    Item := TMenuItem.Create(FMenu);
    Item.Caption := ACaption;
    Item.Tag := Ord(AReason);
    Item.Checked := AReason in FAttention;
    Item.OnClick := @MenuAttentionClick;
    FMenu.Items.Add(Item);
  end;

begin
  FMenu.Items.Clear;
  if CurSection = fsReview then
  begin
    Shown := FReviewOrder;
    Last := poNewest;
  end
  else
  begin
    Shown := FMineOrder;
    Last := poAttentionFirst;
  end;
  if AOrders then
    for O := Low(TGittanPullOrder) to Last do
    begin
      Item := TMenuItem.Create(FMenu);
      Item.Caption := OrderMenuCaption(O);
      Item.Tag := Ord(O);
      Item.RadioItem := True;
      Item.Checked := O = Shown;
      Item.OnClick := @MenuOrderClick;
      FMenu.Items.Add(Item);
    end;
  if CurSection <> fsReview then
  begin
    if AOrders then
      FMenu.Items.Add(NewLine);
    AddReason(rsChangesAttention, arChangesRequested);
    AddReason(rsChecksAttention, arChecksFailing);
  end;
  if FMenu.Items.Count > 0 then
    FMenu.PopUp(AScreenPos.X, AScreenPos.Y);
end;

{ The menu of APull's checks at AScreenPos: each by name as a check
  item, checked while ignored. }

procedure TGittanForgePage.MenuOrderClick(Sender: TObject);
var
  O: TGittanPullOrder;
begin
  O := TGittanPullOrder((Sender as TMenuItem).Tag);
  if CurSection = fsReview then
    SetReviewOrder(O)
  else
    SetMineOrder(O);
  if Assigned(FOnFilterChange) then
    FOnFilterChange(Self);
end;

procedure TGittanForgePage.MenuAttentionClick(Sender: TObject);
begin
  SetAttention(FAttention >< [TGittanAttentionReason((Sender as TMenuItem).Tag)]);
  if Assigned(FOnFilterChange) then
    FOnFilterChange(Self);
end;

procedure TGittanForgePage.SetSection(AValue: integer);
begin
  if FSection = AValue then
    Exit;
  FSection := AValue;
  FHot := -1;
  Layout;
  Invalidate;
end;

function TGittanForgePage.CurSection: TGittanForgeSection;
begin
  if FSection = Ord(fsReview) then
    Result := fsReview
  else
    Result := fsMine;
end;

{ The keys on in ASection, only the ones the forge has for it. }
function TGittanForgePage.SectionKeysOf(ASection: TGittanForgeSection): string;
begin
  if ASection = fsReview then
    Result := KnownKeys(FReviewKeys, FDefs, fsReview)
  else
    Result := KnownKeys(FMineKeys, FDefs, fsMine);
end;

procedure TGittanForgePage.SetIgnoredChecks(AValue: TStringList);
begin
  if AValue = nil then
    FIgnored.Clear
  else
    FIgnored.Assign(AValue);
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanForgePage.SetFilters(const ADefs: TGittanForgeFilterDefs;
  const APresets: TGittanForgePresets);
begin
  FDefs := Copy(ADefs);
  FPresets := Copy(APresets);
  FHot := -1;
  Layout;
  Invalidate;
end;

procedure TGittanForgePage.AddPreset(const AName: string);
var
  PName: string;
  i, n: integer;
begin
  PName := PresetName(AName);
  if PName = '' then
    Exit;
  n := -1;
  for i := 0 to High(FPresets) do
    if FPresets[i].Own and (FPresets[i].Section = CurSection) and
      SameText(FPresets[i].Name, PName) then
      n := i;
  if n < 0 then
  begin
    n := Length(FPresets);
    SetLength(FPresets, n + 1);
  end;
  FPresets[n].Name := PName;
  FPresets[n].Section := CurSection;
  FPresets[n].Keys := SectionKeysOf(CurSection);
  FPresets[n].Own := True;
  FilterChanged;
end;

{ After a change of the filters, the ignored checks or the presets:
  the layout, and the owner told. }

procedure TGittanForgePage.FilterChanged;
begin
  FHot := -1;
  Layout;
  Invalidate;
  if Assigned(FOnFilterChange) then
    FOnFilterChange(Self);
end;

procedure TGittanForgePage.ShowChecksMenu(const APull: TGittanForgePull;
  const AScreenPos: TPoint);
var
  i: integer;
  Item: TMenuItem;
begin
  if Length(APull.CheckList) = 0 then
    Exit;
  FMenuPull := APull;
  FMenu.Items.Clear;
  for i := 0 to High(APull.CheckList) do
  begin
    Item := TMenuItem.Create(FMenu);
    Item.Caption := Format(rsIgnoreCheck, [APull.CheckList[i].Name]);
    Item.Tag := i;
    Item.Checked := IsIgnoredCheck(APull.CheckList[i].Name, FIgnored);
    Item.OnClick := @MenuCheckClick;
    FMenu.Items.Add(Item);
  end;
  FMenu.PopUp(AScreenPos.X, AScreenPos.Y);
end;

{ The menu of the user's own preset AIndex at AScreenPos: deleting it. }
procedure TGittanForgePage.ShowPresetMenu(AIndex: integer; const AScreenPos: TPoint);
var
  Item: TMenuItem;
begin
  if (AIndex < 0) or (AIndex > High(FPresets)) or not FPresets[AIndex].Own then
    Exit;
  FMenuPreset := AIndex;
  FMenu.Items.Clear;
  Item := TMenuItem.Create(FMenu);
  Item.Caption := Format(rsDeletePreset, [FPresets[AIndex].Name]);
  Item.OnClick := @MenuDeletePresetClick;
  FMenu.Items.Add(Item);
  FMenu.PopUp(AScreenPos.X, AScreenPos.Y);
end;

procedure TGittanForgePage.MenuCheckClick(Sender: TObject);
var
  i, n: integer;
  CheckName: string;
begin
  n := (Sender as TMenuItem).Tag;
  if (n < 0) or (n > High(FMenuPull.CheckList)) then
    Exit;
  CheckName := FMenuPull.CheckList[n].Name;
  if IsIgnoredCheck(CheckName, FIgnored) then
    for i := FIgnored.Count - 1 downto 0 do
    begin
      if SameText(FIgnored[i], CheckName) then
        FIgnored.Delete(i);
    end
  else
    FIgnored.Add(CheckName);
  FilterChanged;
end;


procedure TGittanForgePage.MenuDeletePresetClick(Sender: TObject);
var
  i: integer;
begin
  if (FMenuPreset < 0) or (FMenuPreset > High(FPresets)) or not FPresets[FMenuPreset].Own then
    Exit;
  for i := FMenuPreset to High(FPresets) - 1 do
    FPresets[i] := FPresets[i + 1];
  SetLength(FPresets, Length(FPresets) - 1);
  FMenuPreset := -1;
  FilterChanged;
end;

{ A section's heading: ATitle in bold with ADetail dim after it, a
  divider, and with AChips the rows of the presets and the filters
  under it, the order's chip at the end of the filters. }

function TGittanForgePage.PresetChips: TGittanChipSpecs;
var
  Keys: string;
  i, n: integer;
begin
  Keys := SectionKeysOf(CurSection);
  Result := nil;
  SetLength(Result, Length(FPresets) + 2);
  Result[0] := Chip(rsAllChip, AllPresetLink, Keys = '');
  n := 1;
  for i := 0 to High(FPresets) do
    if FPresets[i].Section = CurSection then
    begin
      Result[n] := Chip(FPresets[i].Name, PresetLink + IntToStr(i), SameKeys(FPresets[i].Keys,
        Keys));
      Inc(n);
    end;
  if (Keys <> '') and (FindPreset(FPresets, CurSection, Keys) < 0) then
  begin
    Result[n] := Chip(rsSavePresetChip, SavePresetLink, False, True);
    Inc(n);
  end;
  SetLength(Result, n);
end;

{ The filters row of the section shown: the forge's filters for it,
  the ones on marked, and the order's chip with a glyph for its menu. }

function TGittanForgePage.FilterChips: TGittanChipSpecs;
var
  Defs: TGittanForgeFilterDefs;
  Keys: string;
  i: integer;
  Order: TGittanPullOrder;
begin
  Defs := SectionFilters(FDefs, CurSection);
  Keys := SectionKeysOf(CurSection);
  if CurSection = fsReview then
    Order := FReviewOrder
  else
    Order := FMineOrder;
  Result := nil;
  SetLength(Result, Length(Defs) + 1);
  for i := 0 to High(Defs) do
    Result[i] := Chip(Defs[i].Caption, FilterLink + Defs[i].Key, HasKey(Keys, Defs[i].Key));
  Result[High(Result)] := Chip(OrderCaption(Order) + OrderGlyph, OrderLink, False);
end;

{ The chips of AChips from ALeft, their text on the line at ATop: a
  rounded outline with the caption dim, filled under the mouse; one
  that is on in a tint of the link color with its caption and outline
  in it; a dim one with its caption dimmer still, an offer. A chip
  that would cross ARight starts a line under them at ALeft; ATop
  comes back as the last line's. }

procedure TGittanForgePage.PaintChipRow(ALeft, ARight: integer; var ATop: integer;
  const AChips: array of TGittanChipSpec);
var
  i, TextH, W, LineLeft: integer;
  R: TRect;
begin
  FC.Font := Font;
  TextH := FC.TextHeight('Xg');
  LineLeft := ALeft;
  for i := 0 to High(AChips) do
  begin
    W := FC.TextWidth(AChips[i].Text) + 2 * Px(FilterPadX);
    if (ALeft > LineLeft) and (ALeft + W > ARight) then
    begin
      ALeft := LineLeft;
      Inc(ATop, TextH + 2 * Px(FilterPadY) + Px(FilterGap));
    end;
    R := Rect(ALeft, ATop - Px(FilterPadY), ALeft + W, ATop + TextH + Px(FilterPadY));
    AddLink(R, AChips[i].Link);
    FC.Pen.Style := psSolid;
    FC.Brush.Style := bsSolid;
    if AChips[i].IsOn then
    begin
      FC.Pen.Color := FLink;
      FC.Brush.Color := MixColor(FBack, FLink, 0.18);
    end
    else
    begin
      if AChips[i].Dim then
        FC.Pen.Color := MixColor(FBack, FLine, 0.6)
      else
        FC.Pen.Color := FLine;
      if FHot = High(FLinkRects) then
        FC.Brush.Color := FHover
      else
        FC.Brush.Color := FBack;
    end;
    FC.RoundRect(R, R.Height, R.Height);
    FC.Brush.Style := bsClear;
    if AChips[i].IsOn then
      FC.Font.Color := FLink
    else if FHot = High(FLinkRects) then
      FC.Font.Color := FText
    else if AChips[i].Dim then
      FC.Font.Color := MixColor(FBack, FDim, 0.7)
    else
      FC.Font.Color := FDim;
    FC.TextOut(R.Left + Px(FilterPadX), ATop, AChips[i].Text);
    ALeft := R.Right + Px(FilterGap);
  end;
  FC.Font := Font;
end;

{ A chip ending at ARight with its text in AColor on the hover fill;
  gives its rectangle. }

procedure TGittanForgePage.PulseTimer(Sender: TObject);
begin
  FPhase := (FPhase + 1) mod PulseSteps;
  if HandleAllocated then
    InvalidateRect(Handle, @FDotRect, False);
end;

procedure TGittanForgePage.SetColors(ABack, AText, ADim, AHover, ALine, ALink, AOk, AWarn,
  AError: TColor);
begin
  FBack := ABack;
  FText := AText;
  FDim := ADim;
  FHover := AHover;
  FLine := ALine;
  FLink := ALink;
  FOk := AOk;
  FWarn := AWarn;
  FErrorColor := AError;
  Color := ABack;
  Invalidate;
end;

procedure TGittanForgePage.SetCardColor(ACard: TColor);
begin
  FCard := ACard;
  Invalidate;
end;

procedure TGittanForgePage.SetTheme(ADark: boolean);
begin
  if ADark then
  begin
    SetColors(RGBToColor(30, 30, 30), RGBToColor(224, 224, 224), RGBToColor(150, 150, 150),
      RGBToColor(50, 50, 51), RGBToColor(62, 62, 62), RGBToColor(78, 161, 255),
      RGBToColor(63, 185, 80), RGBToColor(227, 179, 65), RGBToColor(248, 81, 73));
    SetCardColor(RGBToColor(40, 40, 41));
  end
  else
  begin
    SetColors(clWhite, RGBToColor(30, 30, 30), RGBToColor(110, 110, 110),
      RGBToColor(235, 235, 235), RGBToColor(222, 222, 222), RGBToColor(0, 102, 204),
      RGBToColor(26, 127, 55), RGBToColor(154, 103, 0), RGBToColor(207, 34, 46));
    SetCardColor(RGBToColor(245, 245, 246));
  end;
end;

procedure TGittanForgePage.FitHeight(AMin: integer);
begin
  Constraints.MinHeight := AMin;
  Layout;
end;

{ The content painted on the measuring canvas, for its height; the
  height is set here, never in Paint. }

procedure TGittanForgePage.Layout;
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

procedure TGittanForgePage.Resize;
begin
  inherited Resize;
  Layout;
end;

function TGittanForgePage.LinkAt(X, Y: integer): integer;
var
  i: integer;
begin
  { The last link added wins: the forge link lies on its card. }
  for i := High(FLinkRects) downto 0 do
    if PtInRect(FLinkRects[i], Point(X, Y)) then
      Exit(i);
  Result := -1;
end;

procedure TGittanForgePage.SetHot(AValue: integer);
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

procedure TGittanForgePage.AddLink(const ARect: TRect; const AUrl: string);
begin
  SetLength(FLinkRects, Length(FLinkRects) + 1);
  SetLength(FLinkUrls, Length(FLinkUrls) + 1);
  FLinkRects[High(FLinkRects)] := ARect;
  FLinkUrls[High(FLinkUrls)] := AUrl;
end;

{ A disc ASize across with the user's picture in it, resampled to the
  screen's pixels (twice its points on a Retina screen) and cut round,
  on the hover fill;
  without one the login's initial, in the link color; empty in the hover
  fill before the forge has said who. }

procedure TGittanForgePage.PaintAvatar(ALeft, ATop, ASize: integer);
var
  Initial: string;
  Pixels: integer;
  Mask: TBGRABitmap;
begin
  if (FLogin <> '') and (FAvatar <> nil) then
  begin
    Pixels := Max(1, Round(ASize * GetCanvasScaleFactor));
    if (FAvatarShown = nil) or (FAvatarShown.Width <> Pixels) then
    begin
      FreeAndNil(FAvatarShown);
      FAvatar.ResampleFilter := rfBestQuality;
      FAvatarShown := FAvatar.Resample(Pixels, Pixels, rmFineResample) as TBGRABitmap;
      Mask := TBGRABitmap.Create(Pixels, Pixels, BGRAPixelTransparent);
      try
        Mask.FillEllipseAntialias((Pixels - 1) / 2, (Pixels - 1) / 2, Pixels / 2, Pixels / 2,
          BGRAWhite);
        FAvatarShown.ApplyMask(Mask);
      finally
        Mask.Free;
      end;
    end;
    { On the hover fill, so a picture with a clear background still
      reads as a disc. }
    FC.Pen.Style := psClear;
    FC.Brush.Style := bsSolid;
    FC.Brush.Color := FHover;
    FC.Ellipse(ALeft, ATop, ALeft + ASize, ATop + ASize);
    FC.Pen.Style := psSolid;
    FC.Brush.Style := bsClear;
    FAvatarShown.Draw(FC, Rect(ALeft, ATop, ALeft + ASize, ATop + ASize), False);
    Exit;
  end;
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  if FLogin <> '' then
    FC.Brush.Color := FLink
  else
    FC.Brush.Color := FHover;
  FC.Ellipse(ALeft, ATop, ALeft + ASize, ATop + ASize);
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;
  if FLogin = '' then
    Exit;
  Initial := UpperCase(Copy(FLogin, 1, 1));
  FC.Font := Font;
  FC.Font.Height := -ASize div 2;
  FC.Font.Style := [fsBold];
  FC.Font.Color := clWhite;
  FC.TextOut(ALeft + (ASize - FC.TextWidth(Initial)) div 2,
    ATop + (ASize - FC.TextHeight(Initial)) div 2, Initial);
  FC.Font := Font;
end;

{ Refresh as a round button ASize across, filled under the mouse; while
  the forge is asked, a dot pulsing in its place instead. }

procedure TGittanForgePage.PaintRefresh(ALeft, ATop, ASize: integer);
var
  R: TRect;
  D: integer;
begin
  R := Rect(ALeft, ATop, ALeft + ASize, ATop + ASize);
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  if FLoading then
  begin
    FDotRect := R;
    D := Px(DotSize);
    FC.Pen.Style := psClear;
    FC.Brush.Style := bsSolid;
    FC.Brush.Color := MixColor(FHover, FLink,
      0.25 + 0.75 * (1 - Cos(2 * Pi * FPhase / PulseSteps)) / 2);
    FC.Ellipse(R.Left + (ASize - D) div 2, R.Top + (ASize - D) div 2,
      R.Left + (ASize - D) div 2 + D, R.Top + (ASize - D) div 2 + D);
    FC.Pen.Style := psSolid;
    FC.Brush.Style := bsClear;
    Exit;
  end;
  if not Assigned(FOnRefresh) then
    Exit;
  AddLink(R, RefreshLink);
  FC.Font.Color := FDim;
  if FHot = High(FLinkRects) then
  begin
    FC.Pen.Style := psClear;
    FC.Brush.Style := bsSolid;
    FC.Brush.Color := FHover;
    FC.Ellipse(R);
    FC.Pen.Style := psSolid;
    FC.Brush.Style := bsClear;
    FC.Font.Color := FText;
  end;
  FC.TextOut(R.Left + (ASize - FC.TextWidth(RefreshGlyph)) div 2,
    R.Top + (ASize - FC.TextHeight(RefreshGlyph)) div 2, RefreshGlyph);
end;

{ A pull request glyph in a square ASize across: at the left a branch
  between two rings, at the right a ring with a line up from it that
  turns left into an arrow. }

procedure TGittanForgePage.PaintPullGlyph(ALeft, ATop, ASize: integer; AColor: TColor);
var
  W, Rad, X1, X2, YT, YB, XA, A: integer;
begin
  W := Max(1, ASize div 12);
  Rad := Max(2, ASize * 3 div 20);
  X1 := ALeft + ASize div 5;
  X2 := ALeft + ASize * 4 div 5;
  YT := ATop + Rad + W;
  YB := ATop + ASize - Rad - W;
  XA := (X1 + X2) div 2 + W;
  A := Max(2, ASize div 6);
  FC.Pen.Style := psSolid;
  FC.Pen.Color := AColor;
  FC.Pen.Width := W;
  FC.Brush.Style := bsClear;
  FC.Ellipse(X1 - Rad, YT - Rad, X1 + Rad + 1, YT + Rad + 1);
  FC.Ellipse(X1 - Rad, YB - Rad, X1 + Rad + 1, YB + Rad + 1);
  FC.Line(X1, YT + Rad, X1, YB - Rad);
  FC.Ellipse(X2 - Rad, YB - Rad, X2 + Rad + 1, YB + Rad + 1);
  FC.Line(X2, YB - Rad, X2, YT);
  FC.Line(X2, YT, XA, YT);
  FC.Line(XA, YT, XA + A, YT - A);
  FC.Line(XA, YT, XA + A, YT + A);
  FC.Pen.Width := 1;
end;

{ A check in a ring ASize across. }
procedure TGittanForgePage.PaintCheckGlyph(ALeft, ATop, ASize: integer; AColor: TColor);
var
  W: integer;
begin
  W := Max(1, Round(ASize / 12));
  FC.Pen.Style := psSolid;
  FC.Pen.Color := AColor;
  FC.Pen.Width := W;
  FC.Brush.Style := bsClear;
  FC.Ellipse(ALeft + W, ATop + W, ALeft + ASize - W, ATop + ASize - W);
  FC.Line(ALeft + ASize * 3 div 10, ATop + ASize div 2,
    ALeft + ASize * 9 div 20, ATop + ASize * 13 div 20);
  FC.Line(ALeft + ASize * 9 div 20, ATop + ASize * 13 div 20,
    ALeft + ASize * 7 div 10, ATop + ASize * 7 div 20);
  FC.Pen.Width := 1;
end;

{ A dim bold title with a dim detail after it, over a divider, between
  ALeft and ARight; with AChips the filters as chips (those in AOn on)
  and AOrder's after them,
  at the right of the title's line when they fit there, else on lines
  of their own under the divider. }

procedure TGittanForgePage.PaintHeading(var Y: integer; const ATitle, ADetail: string;
  AChips: boolean; ALeft, ARight: integer);
var
  TextH, X: integer;
  Chips: TGittanChipSpecs;
begin
  Inc(Y, Px(Pad));
  FC.Font := Font;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FDim;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  FC.TextOut(ALeft, Y, ATitle);
  X := ALeft + FC.TextWidth(ATitle) + Px(Gap) div 2;
  FC.Font.Style := [];
  if ADetail <> '' then
    FC.TextOut(X, Y, ADetail);
  Inc(Y, TextH + Px(Gap) div 2);
  FC.Pen.Style := psSolid;
  FC.Pen.Color := FLine;
  FC.Line(ALeft, Y, ARight, Y);
  Inc(Y, Px(Gap) div 2);
  if not AChips then
    Exit;
  Chips := PresetChips;
  if Length(Chips) > 1 then
  begin
    Inc(Y, Px(FilterPadY));
    PaintChipRow(ALeft, ARight, Y, Chips);
    Inc(Y, TextH + Px(FilterPadY) + Px(Gap) div 2);
  end;
  Inc(Y, Px(FilterPadY));
  PaintChipRow(ALeft, ARight, Y, FilterChips);
  Inc(Y, TextH + Px(FilterPadY) + Px(Gap) div 2);
end;

{ The presets row of the section shown: All, on while no filter is;
  the presets of the section, the one whose filters are on; and, while
  the filters on match none, Save as preset. Only All when the section
  has no presets. }

{ A paragraph in AColor, wrapped between ALeft and ARight. }
procedure TGittanForgePage.PaintNote(var Y: integer; const AText: string; AColor: TColor;
  ALeft, ARight: integer);
var
  R: TRect;
  Style: TTextStyle;
begin
  Inc(Y, Px(Gap) div 2);
  FC.Font := Font;
  FC.Font.Color := AColor;
  FC.Brush.Style := bsClear;
  R := Rect(ALeft, Y, ARight, Y);
  Style := FC.TextStyle;
  Style.Wordbreak := True;
  Style.SingleLine := False;
  Style.Alignment := taLeftJustify;
  Style.Layout := tlTop;
  DrawText(FC.Handle, PChar(AText), Length(AText), R, DT_CALCRECT or DT_WORDBREAK);
  R.Right := ARight;
  FC.TextRect(R, R.Left, R.Top, AText, Style);
  Y := R.Bottom;
end;

{ An empty section: a card between ALeft and ARight with a large dim
  glyph (a check in a ring with ACheck, else a pull request's), ATitle
  in bold under it when there is one, and AText dim, wrapped, all
  centered. }

procedure TGittanForgePage.PaintEmpty(var Y: integer; const ATitle, AText: string;
  ACheck: boolean; ALeft, ARight: integer);
var
  R, TR: TRect;
  TextH, G, H, TextY: integer;
  Style: TTextStyle;
begin
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  G := Px(EmptyGlyph);
  TR := Rect(ALeft + Px(CardPadX), 0, ARight - Px(CardPadX), 0);
  DrawText(FC.Handle, PChar(AText), Length(AText), TR, DT_CALCRECT or DT_WORDBREAK);
  H := 2 * Px(EmptyPadY) + G + Px(Gap) + TR.Bottom;
  if ATitle <> '' then
    Inc(H, TextH + 4);
  R := Rect(ALeft, Y, ARight, Y + H);
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FCard;
  FC.RoundRect(R, Px(CardRadius), Px(CardRadius));
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;
  if ACheck then
    PaintCheckGlyph((ALeft + ARight - G) div 2, R.Top + Px(EmptyPadY), G, FDim)
  else
    PaintPullGlyph((ALeft + ARight - G) div 2, R.Top + Px(EmptyPadY), G, FDim);
  TextY := R.Top + Px(EmptyPadY) + G + Px(Gap);
  if ATitle <> '' then
  begin
    FC.Font.Style := [fsBold];
    FC.Font.Color := FText;
    FC.TextOut((ALeft + ARight - FC.TextWidth(ATitle)) div 2, TextY, ATitle);
    FC.Font.Style := [];
    Inc(TextY, TextH + 4);
  end;
  FC.Font.Color := FDim;
  TR := Rect(ALeft + Px(CardPadX), TextY, ARight - Px(CardPadX), R.Bottom);
  Style := FC.TextStyle;
  Style.Wordbreak := True;
  Style.SingleLine := False;
  Style.Alignment := taCenter;
  Style.Layout := tlTop;
  FC.TextRect(TR, TR.Left, TR.Top, AText, Style);
  Inc(Y, H + Px(CardGap));
end;

{ A chip ending at ARight with its text in AColor on the hover fill;
  gives its left edge. }

function TGittanForgePage.PaintChip(ARight, ATop: integer; const AText: string;
  AColor: TColor): TRect;
var
  W, H: integer;
begin
  FC.Font := Font;
  FC.Font.Size := Max(7, Font.Size - 2);
  if Font.Size <= 0 then
    FC.Font.Size := 9;
  W := FC.TextWidth(AText) + 2 * Px(ChipPadX);
  H := FC.TextHeight(AText) + 2 * Px(ChipPadY);
  Result := Rect(ARight - W, ATop, ARight, ATop + H);
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FHover;
  FC.RoundRect(Result, Px(ChipRadius), Px(ChipRadius));
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;
  FC.Font.Color := AColor;
  FC.TextOut(Result.Left + Px(ChipPadX), Result.Top + Px(ChipPadY), AText);
  FC.Font := Font;
  FC.Brush.Style := bsClear;
end;

{ A card between ALeft and ARight: the pull request glyph, the number
  dimmed and the title in bold, the chips of the review and the checks
  at the right (the checks' a link to their menu, ChecksLink with
  AIndex, when the forge named them), the second line under them with
  the repository first and the forge link at its right end while the
  card is under the mouse, the reviewers and the checks by name dim
  under that when there is something to say, and the link to its
  clone under those, which ALink, the card's own, picks too. The card
  and its links are under the mouse together. }

function TGittanForgePage.PullLine(const APull: TGittanForgePull): string;
var
  UtcNow: TDateTime;

  procedure Add(const APart: string);
  begin
    if APart = '' then
      Exit;
    if Result <> '' then
      Result := Result + ' · ';
    Result := Result + APart;
  end;

begin
  Result := '';
  UtcNow := LocalTimeToUniversal(Now);
  if not SameText(APull.Author, FLogin) then
    Add(APull.Author);
  if APull.Created > 0 then
    Add(Format(rsOpened, [RelativeAge(APull.Created, UtcNow)]));
  if (APull.Updated > 0) and (MinutesBetween(APull.Updated, APull.Created) >= 1) then
    Add(Format(rsUpdated, [RelativeAge(APull.Updated, UtcNow)]));
end;

{ A card between ALeft and ARight: the pull request glyph, the number
  dimmed and the title in bold, the chips of the state and the checks
  at the right, the second line under them with the repository first
  and the forge link at its right end while the card is under the
  mouse, and the link to its clone under that, which ALink, the card's
  own, picks too. The card and its links are under the mouse
  together. }

procedure TGittanForgePage.PaintCard(var Y: integer; const APull: TGittanForgePull;
  ALeft, ARight: integer; const ALink: string; AIndex: integer);
var
  R, LinkR, ChipR: TRect;
  TextH, CardH, Right, X, TextX, LineY, ChipTop, First, Links: integer;
  Number, Repo, Rest, ForgeLink, CloneLink, Note, Detail, Part: string;
  Lines: integer;
  HasClone, HasForge, HasChecksMenu, Hot: boolean;
  GlyphColor, Tone: TColor;
  Checks: TGittanChecksState;
begin
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  HasClone := (APull.Clone <> '') and Assigned(FOnPick) and
    not SameFileName(APull.Clone, FOpenRoot);
  HasForge := (APull.Url <> '') and Assigned(FOnOpenUrl);
  HasChecksMenu := Length(APull.CheckList) > 0;
  Detail := PullReviewers(APull, FLogin);
  Part := PullChecksDetail(APull, FIgnored);
  if Part <> '' then
  begin
    if Detail <> '' then
      Detail := Detail + ' · ';
    Detail := Detail + Part;
  end;
  Lines := 2;
  if Detail <> '' then
    Inc(Lines);
  if HasClone then
    Inc(Lines);
  CardH := 2 * Px(CardPadY) + Lines * TextH + Px(LineGap) * (Lines - 1);
  R := Rect(ALeft, Y, ARight, Y + CardH);
  First := Length(FLinkRects);
  Links := Ord(Assigned(FOnPick)) + Ord(HasChecksMenu) + Ord(HasForge) + Ord(HasClone);
  Hot := (FHot >= First) and (FHot < First + Links);
  FC.Pen.Style := psClear;
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FCard;
  if Assigned(FOnPick) then
  begin
    AddLink(R, ALink);
    if Hot then
      FC.Brush.Color := FHover;
  end;
  FC.RoundRect(R, Px(CardRadius), Px(CardRadius));
  FC.Pen.Style := psSolid;
  FC.Brush.Style := bsClear;

  if APull.IsDraft then
    GlyphColor := FDim
  else
    GlyphColor := FOk;
  PaintPullGlyph(R.Left + Px(CardPadX), R.Top + Px(CardPadY), TextH, GlyphColor);
  TextX := R.Left + Px(CardPadX) + TextH + Px(GlyphGap);

  { The chips, right to left: the checks, the review, asked again. }
  Right := R.Right - Px(CardPadX);
  ChipTop := R.Top + Px(CardPadY);
  { Of the user's own a reason left out of what needs attention is dim. }
  if (CurSection = fsReview) or (arChecksFailing in FAttention) then
    Tone := FErrorColor
  else
    Tone := FDim;
  Checks := ChecksState(APull, FIgnored);
  Note := PullChecksNote(APull, FIgnored);
  if Note <> '' then
  begin
    case Checks of
      chkFailed: ChipR := PaintChip(Right, ChipTop, Note, Tone);
      chkPending: ChipR := PaintChip(Right, ChipTop, Note, FWarn);
    else
      ChipR := PaintChip(Right, ChipTop, Note, FOk);
    end;
    if HasChecksMenu then
      AddLink(ChipR, ChecksLink + IntToStr(AIndex));
    Right := ChipR.Left - Px(Gap) div 2;
  end
  else if HasChecksMenu then
    AddLink(Rect(Right, ChipTop, Right, ChipTop), ChecksLink + IntToStr(AIndex));
  if APull.IsDraft then
    Right := PaintChip(Right, ChipTop, rsDraft, FDim).Left - Px(Gap) div 2
  else
  begin
    Note := PullReviewNote(APull, FLogin);

    if Note <> '' then
    begin
      case APull.ReviewDecision of
        rdApproved: Tone := FOk;
        rdChangesRequested:
          if (CurSection = fsReview) or (arChangesRequested in FAttention) then
            Tone := FErrorColor
          else
            Tone := FDim;
      else
        Tone := FDim;
      end;
      Right := PaintChip(Right, ChipTop, Note, Tone).Left - Px(Gap) div 2;
    end;
  end;
  if APull.Requested and (APull.MyReview <> rvNone) then
    Right := PaintChip(Right, ChipTop, rsAskedAgain, FWarn).Left - Px(Gap) div 2;

  { The number and the title. }
  X := TextX;
  Number := '#' + IntToStr(APull.Number);
  FC.Font.Color := FDim;
  FC.TextOut(X, R.Top + Px(CardPadY), Number);
  Inc(X, FC.TextWidth(Number) + Px(Gap) div 2);
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  FC.TextOut(X, R.Top + Px(CardPadY), FitTextRight(FC, APull.Title, Max(0, Right - X)));
  FC.Font.Style := [];

  { The second line: the repository, the rest dim, and the forge link
    at its right end, there to click whether shown or not, since the
    mouse on it shows it. }
  LineY := R.Top + Px(CardPadY) + TextH + Px(LineGap);
  Right := R.Right - Px(CardPadX);
  if HasForge then
  begin
    ForgeLink := Format(rsForgeLink, [FForge]);
    LinkR := Rect(Right - FC.TextWidth(ForgeLink), LineY, Right, LineY + TextH);
    AddLink(LinkR, APull.Url);
    if Hot or not Assigned(FOnPick) then
    begin
      FC.Font.Color := FLink;
      if FHot = High(FLinkRects) then
        FC.Font.Style := [fsUnderline];
      FC.TextOut(LinkR.Left, LinkR.Top, ForgeLink);
      FC.Font.Style := [];
      Right := LinkR.Left - Px(Gap);
    end;
  end;
  FC.Font.Color := FText;
  Repo := FitTextRight(FC, APull.Repo, Max(0, Right - TextX));
  FC.TextOut(TextX, LineY, Repo);
  X := TextX + FC.TextWidth(Repo);
  Rest := PullLine(APull);
  if (Rest <> '') and (Repo = APull.Repo) then
  begin
    FC.Font.Color := FDim;
    FC.TextOut(X, LineY, FitTextRight(FC, ' · ' + Rest, Max(0, Right - X)));
  end;

  { The reviewers and the checks by name. }
  if Detail <> '' then
  begin
    Inc(LineY, TextH + Px(LineGap));
    Right := R.Right - Px(CardPadX);
    FC.Font.Color := FDim;
    FC.TextOut(TextX, LineY, FitTextRight(FC, Detail, Max(0, Right - TextX)));
  end;

  { The clone's link, under the forge's, its path cut at its start to
    the card. }
  if HasClone then
  begin
    Inc(LineY, TextH + Px(LineGap));
    Right := R.Right - Px(CardPadX);
    CloneLink := Format(rsCloneLink, [FitTextLeft(FC, ShortPath(APull.Clone),
      Max(0, Right - TextX - FC.TextWidth(Format(rsCloneLink, ['']))))]);
    LinkR := Rect(Right - FC.TextWidth(CloneLink), LineY, Right, LineY + TextH);
    AddLink(LinkR, ALink);
    FC.Font.Color := FLink;
    if FHot = High(FLinkRects) then
      FC.Font.Style := [fsUnderline];
    FC.TextOut(LinkR.Left, LinkR.Top, CloneLink);
    FC.Font.Style := [];
  end;
  Inc(Y, CardH + Px(CardGap));
end;

{ A section: its heading with the count (of ATotal, when some are left
  out) and the presets and the filters while there is something to
  filter, then a card per pull request, or, once the forge has
  answered, an empty card with AEmptyTitle and AEmpty, its glyph a
  check with AEmptyCheck; one that the filters left empty says so. }

procedure TGittanForgePage.PaintSection(var Y: integer; const ATitle: string;
  const APulls: TGittanForgePulls; ATotal: integer; const AEmptyTitle, AEmpty,
  ALinkPrefix: string; AEmptyCheck: boolean; ALeft, ARight: integer);
var
  Detail: string;
  i: integer;
begin
  if ATotal > Length(APulls) then
    Detail := Format(rsSomeOpen, [Length(APulls), ATotal])
  else if Length(APulls) = 1 then
    Detail := rsOneOpen
  else if Length(APulls) > 1 then
    Detail := Format(rsManyOpen, [Length(APulls)])
  else
    Detail := '';
  PaintHeading(Y, ATitle, Detail, ATotal > 0, ALeft, ARight);
  if Length(APulls) = 0 then
  begin
    if ATotal > 0 then
      PaintEmpty(Y, '', rsNoMatch, AEmptyCheck, ALeft, ARight)
    else if FAnswered and (FError = '') then
      PaintEmpty(Y, AEmptyTitle, AEmpty, AEmptyCheck, ALeft, ARight);
  end
  else
    for i := 0 to High(APulls) do
      PaintCard(Y, APulls[i], ALeft, ARight, ALinkPrefix + IntToStr(i), i);
end;

procedure TGittanForgePage.Paint;
begin
  FC := Canvas;
  PaintContent;
end;

procedure TGittanForgePage.PaintContent;
var
  Y, TextH, TitleH, X, L, R, AvatarD, ButtonD: integer;
  Who: string;
  Ctx: TGittanFilterContext;

  procedure AddWho(const APart: string);
  begin
    if Who <> '' then
      Who := Who + ' · ';
    Who := Who + APart;
  end;

begin
  FC.Brush.Style := bsSolid;
  FC.Brush.Color := FBack;
  FC.FillRect(Rect(0, 0, Width, Height));
  FLinkRects := nil;
  FLinkUrls := nil;
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  TextH := FC.TextHeight('Xg');
  L := Max(Px(Pad), (Width - Px(MaxContentWidth)) div 2);
  R := Width - L;
  Y := Px(Pad);

  { The head: the avatar, the forge's name with the page's title and
    Refresh after it, under them the login with the counts, or that
    the forge is asked. }
  FC.Font.Size := TitleFontSize;
  FC.Font.Style := [fsBold];
  FC.Font.Color := FText;
  TitleH := FC.TextHeight('Xg');
  AvatarD := TitleH + 2 + TextH;
  FC.TextOut(L + AvatarD + Px(Gap), Y, FForge);
  X := L + AvatarD + Px(Gap) + FC.TextWidth(FForge) + Px(Gap);
  PaintAvatar(L, Y, AvatarD);
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  FC.Font.Color := FDim;
  FC.TextOut(X, Y + TitleH - TextH - 3, rsPageTitle);
  Inc(X, FC.TextWidth(rsPageTitle) + Px(Gap) div 2);
  ButtonD := TextH + Px(8);
  PaintRefresh(X, Y + TitleH - TextH - 3 + (TextH - ButtonD) div 2, ButtonD);
  Who := FLogin;
  if FLoading then
    AddWho(Format(rsLoading, [FForge]))
  else if FAnswered and (FError = '') then
  begin
    if Length(FMine) = 1 then
      AddWho(rsOneOpen)
    else
      AddWho(Format(rsManyOpen, [Length(FMine)]));
    AddWho(Format(rsToReview, [Length(FReview)]));
  end;
  FC.Font := Font;
  FC.Brush.Style := bsClear;
  FC.Font.Color := FDim;
  X := L + AvatarD + Px(Gap);
  FC.TextOut(X, Y + TitleH + 2, FitTextLeft(FC, Who, R - X));
  Inc(Y, AvatarD);
  if FError <> '' then
    PaintNote(Y, FError, FErrorColor, L, R);

  { The section, as its filters leave it. }
  Ctx := FilterContext(LocalTimeToUniversal(Now), FAttention, FIgnored);
  FShownMine := SortPulls(FilterPulls(FMine, FDefs, SectionKeysOf(fsMine), Ctx), FMineOrder,
    FAttention, FIgnored);
  FShownReview := SortPulls(FilterPulls(FReview, FDefs, SectionKeysOf(fsReview), Ctx),
    FReviewOrder, FAttention, FIgnored);
  if CurSection = fsReview then
    PaintSection(Y, rsReviewGroup, FShownReview, Length(FReview), rsCaughtUp, rsNoReview,
      ReviewLink, True, L, R)
  else
    PaintSection(Y, rsMineGroup, FShownMine, Length(FMine), '', rsNoMine, MineLink, False,
      L, R);

  { Layout sets the height from this. }
  FContentHeight := Y + Px(Pad);
end;

procedure TGittanForgePage.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(LinkAt(X, Y));
end;

procedure TGittanForgePage.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1);
end;

function TGittanForgePage.CardAt(X, Y: integer; out APull: TGittanForgePull): boolean;
var
  i, n: integer;
  Url: string;
begin
  Result := False;
  APull := Default(TGittanForgePull);
  { The card under the forge link that lies on it, too. }
  for i := High(FLinkRects) downto 0 do
  begin
    if not PtInRect(FLinkRects[i], Point(X, Y)) then
      Continue;
    Url := FLinkUrls[i];
    if Copy(Url, 1, Length(MineLink)) = MineLink then
    begin
      n := StrToIntDef(Copy(Url, Length(MineLink) + 1, MaxInt), -1);
      Result := (n >= 0) and (n <= High(FShownMine));
      if Result then
      begin
        APull := FShownMine[n];
        Exit;
      end;
    end
    else if Copy(Url, 1, Length(ReviewLink)) = ReviewLink then
    begin
      n := StrToIntDef(Copy(Url, Length(ReviewLink) + 1, MaxInt), -1);
      Result := (n >= 0) and (n <= High(FShownReview));
      if Result then
      begin
        APull := FShownReview[n];
        Exit;
      end;
    end;
  end;
end;

procedure TGittanForgePage.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  i, n: integer;
  Url, Key: string;
  Card: TGittanForgePull;
  Shown: TGittanForgePulls;
  Screen: TPoint;
begin
  inherited MouseUp(Button, Shift, X, Y);
  i := LinkAt(X, Y);
  Screen := ClientToScreen(Point(X, Y));
  if CurSection = fsReview then
    Shown := FShownReview
  else
    Shown := FShownMine;
  if i >= 0 then
    Url := FLinkUrls[i]
  else
    Url := '';
  { Either button: the menu of a card's checks. }
  if Copy(Url, 1, Length(ChecksLink)) = ChecksLink then
  begin
    n := StrToIntDef(Copy(Url, Length(ChecksLink) + 1, MaxInt), -1);
    if (n >= 0) and (n <= High(Shown)) then
      ShowChecksMenu(Shown[n], ClientToScreen(Point(FLinkRects[i].Left, FLinkRects[i].Bottom)));
    Exit;
  end;
  if Button = mbRight then
  begin
    if (CurSection <> fsReview) and (Url = FilterLink + fkAttention) then
      ShowMenu(False, Screen)
    else if (Copy(Url, 1, Length(PresetLink)) = PresetLink) and (Url <> AllPresetLink) then
      ShowPresetMenu(StrToIntDef(Copy(Url, Length(PresetLink) + 1, MaxInt), -1), Screen)
    else if Assigned(FOnContext) and CardAt(X, Y, Card) then
      FOnContext(Self, Card, Screen);
    Exit;
  end;
  if (Button <> mbLeft) or (i < 0) then
    Exit;
  if Copy(Url, 1, Length(MineLink)) = MineLink then
  begin
    n := StrToIntDef(Copy(Url, Length(MineLink) + 1, MaxInt), -1);
    if (n >= 0) and (n <= High(FShownMine)) and Assigned(FOnPick) then
      FOnPick(Self, FShownMine[n]);
  end
  else if Copy(Url, 1, Length(ReviewLink)) = ReviewLink then
  begin
    n := StrToIntDef(Copy(Url, Length(ReviewLink) + 1, MaxInt), -1);
    if (n >= 0) and (n <= High(FShownReview)) and Assigned(FOnPick) then
      FOnPick(Self, FShownReview[n]);
  end
  else if Copy(Url, 1, Length(FilterLink)) = FilterLink then
  begin
    Key := Copy(Url, Length(FilterLink) + 1, MaxInt);
    if FindFilter(FDefs, Key) < 0 then
      Exit;
    if CurSection = fsReview then
      SetReviewFilters(ToggleKey(SectionKeysOf(fsReview), Key))
    else
      SetMineFilters(ToggleKey(SectionKeysOf(fsMine), Key));
    if Assigned(FOnFilterChange) then
      FOnFilterChange(Self);
  end
  else if Url = AllPresetLink then
  begin
    if CurSection = fsReview then
      SetReviewFilters('')
    else
      SetMineFilters('');
    if Assigned(FOnFilterChange) then
      FOnFilterChange(Self);
  end
  else if Copy(Url, 1, Length(PresetLink)) = PresetLink then
  begin
    n := StrToIntDef(Copy(Url, Length(PresetLink) + 1, MaxInt), -1);
    if (n < 0) or (n > High(FPresets)) or (FPresets[n].Section <> CurSection) then
      Exit;
    if CurSection = fsReview then
      SetReviewFilters(FPresets[n].Keys)
    else
      SetMineFilters(FPresets[n].Keys);
    if Assigned(FOnFilterChange) then
      FOnFilterChange(Self);
  end
  else if Url = SavePresetLink then
  begin
    if Assigned(FOnSavePreset) then
      FOnSavePreset(Self);
  end
  else if Url = OrderLink then
    ShowMenu(True, ClientToScreen(Point(FLinkRects[i].Left, FLinkRects[i].Bottom)))
  else if Url = RefreshLink then
  begin
    if Assigned(FOnRefresh) then
      FOnRefresh(Self);
  end
  else if Assigned(FOnOpenUrl) then
    FOnOpenUrl(Self, Url);
end;

end.
