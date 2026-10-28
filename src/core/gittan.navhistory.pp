unit gittan.navhistory;

{** Back and Forward: the places a repository's frame has shown, as a
  browser keeps the pages it has been to.

  A place is what the frame shows (the summary, a file's changes, a
  file open in the editor, a file of a commit, one of the pages), with
  the comparison base it was shown against and, in an editor, the row
  of the caret and the first row in view. Going somewhere else puts the
  place left on the back list (Visit) and empties the forward list;
  Back and Forward step through them, the place being left going on the
  other list. Two places that differ only in their rows are the same
  place (SamePlace) seen at different rows: the frame keeps the row of
  the place it is on up to date, and a jump within a file (to a
  definition, a symbol) is visited as a place of its own. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  {** What a place shows: the summary; a changed file in the change view
    (or the image, translation or binary view); the repository diff; a
    file open in the editor; a file as it is in a commit (Files page);
    the Files page; the Repository, Commands or Pull Requests page. }
  TGittanPlaceKind = (pkSummary, pkChanges, pkRepoDiff, pkFile, pkBlob, pkFiles,
    pkRepoInfo, pkCommands, pkPulls);

  {** A place. Path is the file (a path from the root, or the full name
    of a file open in the editor); Base and WholeTree the comparison it
    was shown against and Commit the commit picked to be compared with
    its parent, when that is the comparison (for the kinds the base
    matters to: summary, changes, repository diff); Ref and Name the
    commit of a file of a commit or of the Files page ('' for HEAD's
    files) and what it is called; Row, Col and Top the caret's row and
    column and the first row in view, 0 outside an editor. }
  TGittanPlace = record
    Kind: TGittanPlaceKind;
    Path, Base, Commit, Ref, Name: string;
    WholeTree: boolean;
    Row, Col, Top: integer;
  end;

  TGittanPlaces = array of TGittanPlace;

  { TGittanNavHistory }

  TGittanNavHistory = class
  private
    FBack, FForward: TGittanPlaces;
    FMax: integer;
    procedure Push(var AList: TGittanPlaces; const APlace: TGittanPlace);
    function Pop(var AList: TGittanPlaces): TGittanPlace;
  public
    {** A history that keeps at most AMax places on each list, the
      oldest dropped first. }
    constructor Create(AMax: integer = 100);
    {** APlace is left for another: it goes on the back list (not twice
      in a row at the same row) and the forward list is emptied. }
    procedure Visit(const APlace: TGittanPlace);
    {** The place to go back to; ACurrent, the one being left, goes on
      the forward list. Only while CanBack. }
    function Back(const ACurrent: TGittanPlace): TGittanPlace;
    {** The place to go forward to; ACurrent goes on the back list. Only
      while CanForward. }
    function Forward(const ACurrent: TGittanPlace): TGittanPlace;
    function CanBack: boolean;
    function CanForward: boolean;
    {** APlace is shown after steps that found nothing to show: the
      place at the end of either list that is the same goes, since a
      step there would show what is shown. }
    procedure Settled(const APlace: TGittanPlace);
    {** Forgets every place, as when another repository is opened. }
    procedure Clear;
    property BackPlaces: TGittanPlaces read FBack;
    property ForwardPlaces: TGittanPlaces read FForward;
  end;

{** Whether A and B show the same thing, whatever rows they are at. }
function SamePlace(const A, B: TGittanPlace): boolean;

{** Whether A and B are the same place at the same caret row. }
function SamePlaceAndRow(const A, B: TGittanPlace): boolean;

implementation

function SamePlace(const A, B: TGittanPlace): boolean;
begin
  Result := (A.Kind = B.Kind) and (A.Path = B.Path) and (A.Base = B.Base) and
    (A.Commit = B.Commit) and (A.WholeTree = B.WholeTree) and (A.Ref = B.Ref);
end;

function SamePlaceAndRow(const A, B: TGittanPlace): boolean;
begin
  Result := SamePlace(A, B) and (A.Row = B.Row);
end;

constructor TGittanNavHistory.Create(AMax: integer);
begin
  inherited Create;
  if AMax < 1 then
    AMax := 1;
  FMax := AMax;
end;

procedure TGittanNavHistory.Push(var AList: TGittanPlaces; const APlace: TGittanPlace);
begin
  if (Length(AList) > 0) and SamePlaceAndRow(AList[High(AList)], APlace) then
  begin
    AList[High(AList)] := APlace;
    Exit;
  end;
  if Length(AList) >= FMax then
    Delete(AList, 0, Length(AList) - FMax + 1);
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := APlace;
end;

function TGittanNavHistory.Pop(var AList: TGittanPlaces): TGittanPlace;
begin
  Result := AList[High(AList)];
  SetLength(AList, Length(AList) - 1);
end;

procedure TGittanNavHistory.Visit(const APlace: TGittanPlace);
begin
  Push(FBack, APlace);
  FForward := nil;
end;

function TGittanNavHistory.Back(const ACurrent: TGittanPlace): TGittanPlace;
begin
  Result := Pop(FBack);
  Push(FForward, ACurrent);
end;

function TGittanNavHistory.Forward(const ACurrent: TGittanPlace): TGittanPlace;
begin
  Result := Pop(FForward);
  Push(FBack, ACurrent);
end;

function TGittanNavHistory.CanBack: boolean;
begin
  Result := Length(FBack) > 0;
end;

function TGittanNavHistory.CanForward: boolean;
begin
  Result := Length(FForward) > 0;
end;

procedure TGittanNavHistory.Settled(const APlace: TGittanPlace);
begin
  if (Length(FForward) > 0) and SamePlace(FForward[High(FForward)], APlace) then
    Pop(FForward);
  if (Length(FBack) > 0) and SamePlace(FBack[High(FBack)], APlace) then
    Pop(FBack);
end;

procedure TGittanNavHistory.Clear;
begin
  FBack := nil;
  FForward := nil;
end;

end.
