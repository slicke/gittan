unit gittan.svgguard;

{** Keeps a hostile SVG from hanging Gittan. BGRASVG draws what a <use>
  or a mask names with no limit but on cycles, so ten groups of ten uses
  of the group before are ten thousand million elements in two kilobytes,
  and a long enough chain of uses overflows the stack. }

{$mode objfpc}{$H+}

interface

uses
  BGRASVG;

{** Whether drawing ASvg draws far more elements than it has, or goes
  deeper than MaxNesting elements, through its uses and masks. }
function SvgTooHeavy(ASvg: TBGRASVG): boolean;

implementation

uses
  SysUtils, fgl, BGRASVGShapes, BGRASVGType, gittan.textfile;

const
  { The elements any SVG may draw again through uses and masks, and what
    it may for each element it has. }
  BaseDraws = 1000;
  DrawsPerElement = 10;
  { A mask is a bitmap as large as the drawing, beside what it draws. }
  MaskDraws = 100;
  { Too many, whatever is added. }
  TooMany = 1e15;

type
  TElementCosts = specialize TFPGMap<Pointer, double>;

  TSvgMeter = class
  private
    FCosts: TElementCosts;
    FElements: int64;
    FDepth: integer;
    FTooDeep: boolean;
    function Named(AElement: TSVGElement): double;
    function Cost(AElement: TSVGElement): double;
    function ContentCost(AContent: TSVGContent): double;
  public
    constructor Create;
    destructor Destroy; override;
  end;

constructor TSvgMeter.Create;
begin
  inherited Create;
  FCosts := TElementCosts.Create;
  FCosts.Sorted := True;
end;

destructor TSvgMeter.Destroy;
begin
  FCosts.Free;
  inherited Destroy;
end;

{ What AElement draws of the element it uses and its mask. }
function TSvgMeter.Named(AElement: TSVGElement): double;
var
  Other: TSVGElement;
  NotFound: boolean;
  Url: string;
begin
  Result := 0;
  if AElement.DataLink = nil then
    Exit;
  if AElement is TSVGUse then
  begin
    Other := AElement.DataLink.FindElementByRef(TSVGUse(AElement).XlinkHref, nil);
    if Other <> nil then
      Result := Cost(Other);
  end;
  Url := AElement.mask;
  if Url <> '' then
  begin
    Other := AElement.DataLink.FindElementByRef(Url, True, TSVGMask, NotFound);
    if Other <> nil then
      Result := Result + MaskDraws + Cost(Other);
  end;
end;

{ The elements drawn for AElement, itself included. One that is being
  counted further up, a cycle, is too many: what BGRASVG draws of it
  depends on the way there. }
function TSvgMeter.Cost(AElement: TSVGElement): double;
var
  i: integer;
begin
  if FCosts.Find(AElement, i) then
    Exit(FCosts.Data[i]);
  if FDepth >= MaxNesting then
    FTooDeep := True;
  if FTooDeep then
    Exit(TooMany);
  Inc(FElements);
  FCosts.Add(AElement, TooMany);
  Inc(FDepth);
  Result := 1 + Named(AElement);
  if AElement is TSVGElementWithContent then
    Result := Result + ContentCost(TSVGElementWithContent(AElement).Content);
  Dec(FDepth);
  if Result > TooMany then
    Result := TooMany;
  if FCosts.Find(AElement, i) then
    FCosts.Data[i] := Result;
end;

function TSvgMeter.ContentCost(AContent: TSVGContent): double;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to AContent.ElementCount - 1 do
    if AContent.IsSVGElement[i] then
      Result := Result + Cost(AContent.Element[i]);
end;

function SvgTooHeavy(ASvg: TBGRASVG): boolean;
var
  Meter: TSvgMeter;
  Draws: double;
begin
  Meter := TSvgMeter.Create;
  try
    Draws := Meter.ContentCost(ASvg.Content);
    Result := Meter.FTooDeep or
      (Draws > Meter.FElements * (DrawsPerElement + 1.0) + BaseDraws);
  finally
    Meter.Free;
  end;
end;

end.
