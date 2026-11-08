unit gittan.signmark;

{** How a commit's signature is shown: the words for its state, the
  color it takes, and the shield drawn before them, in the commit
  graph's rows and on the card of the commit shown. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, gittan.signing;

{** What to say of ASignature: nothing for a commit never signed. A
  verified one names its signer and key, and through which forge the
  key was trusted when it was; one by a key not known here,
  or one git could not check, says so and why, as far as the format
  tells (an SSH signature wants an allowed signers file, an OpenPGP one
  gpg); a bad one says what is wrong with it. }
function SignatureText(const ASignature: TGittanSignature): string;

{** The color for ASignature's state: AOk for a verified one, AError
  for a bad one, ADim for the rest. }
function SignatureColor(const ASignature: TGittanSignature; AOk, ADim, AError: TColor): TColor;

{** A shield ASize high at ALeft, ATop, filled with AColor for a
  verified or bad signature, outlined for one not vouched for, with a
  check mark in ABack across a filled one when ACheck is set (the
  verified one). }
procedure PaintShield(ACanvas: TCanvas; ALeft, ATop, ASize: integer; AColor, ABack: TColor;
  AFilled, ACheck: boolean);

{** Whether the shield for ASignature is filled: a verdict either way,
  good or bad. }
function ShieldFilled(const ASignature: TGittanSignature): boolean;

implementation

resourcestring
  rsSignVerifiedBy = 'Verified signature by %s';
  rsSignVerified = 'Verified signature';
  rsSignKey = 'key %s';
  rsSignTrusted = 'trusted through %s (%s)';
  rsSignUnknownKey = 'Signed with a key not known here';
  rsSignBad = 'Bad signature';
  rsSignExpired = 'Signature expired';
  rsSignExpiredKey = 'Signed with a key that has expired';
  rsSignRevokedKey = 'Signed with a revoked key';
  rsSignBy = 'by %s';
  rsSignUncheckedSsh = 'Signed with SSH, not checked: no allowed signers file is set';
  rsSignUncheckedGpg = 'Signed with GPG, not checked: gpg could not be run';
  rsSignUncheckedX509 = 'Signed with X.509, not checked: gpgsm could not be run';
  rsSignUnchecked = 'Signed, not checked';

function SignatureText(const ASignature: TGittanSignature): string;
var
  Who: string;
begin
  Result := '';
  Who := ASignature.Signer;
  if Who = '' then
    Who := ASignature.Key;
  case ASignature.State of
    ssGood:
    begin
      if ASignature.Signer <> '' then
        Result := Format(rsSignVerifiedBy, [ASignature.Signer])
      else
        Result := rsSignVerified;
      if ASignature.Key <> '' then
        Result := Result + ' · ' + Format(rsSignKey, [ASignature.Key]);
    end;
    ssTrusted:
    begin
      if ASignature.Signer <> '' then
        Result := Format(rsSignVerifiedBy, [ASignature.Signer])
      else
        Result := rsSignVerified;
      if ASignature.Key <> '' then
        Result := Result + ' · ' + Format(rsSignKey, [ASignature.Key]);
      Result := Result + ' · ' + Format(rsSignTrusted, [ASignature.TrustedFrom, ASignature.TrustedUser]);
    end;
    ssUnknownKey:
    begin
      Result := rsSignUnknownKey;
      if Who <> '' then
        Result := Result + ': ' + Who;
    end;
    ssBad:
    begin
      case ASignature.Code of
        'X': Result := rsSignExpired;
        'Y': Result := rsSignExpiredKey;
        'R': Result := rsSignRevokedKey;
      else
        Result := rsSignBad;
      end;
      if Who <> '' then
        Result := Result + ' ' + Format(rsSignBy, [Who]);
    end;
    ssUnchecked:
      case ASignature.Format of
        sfSsh: Result := rsSignUncheckedSsh;
        sfOpenPgp: Result := rsSignUncheckedGpg;
        sfX509: Result := rsSignUncheckedX509;
      else
        Result := rsSignUnchecked;
      end;
  end;
end;

function SignatureColor(const ASignature: TGittanSignature; AOk, ADim, AError: TColor): TColor;
begin
  case ASignature.State of
    ssGood, ssTrusted: Result := AOk;
    ssBad: Result := AError;
  else
    Result := ADim;
  end;
end;

function ShieldFilled(const ASignature: TGittanSignature): boolean;
begin
  Result := ASignature.State in [ssGood, ssTrusted, ssBad];
end;

{ A shield: straight top, sides down to past the middle, and a point at
  the bottom. }
procedure PaintShield(ACanvas: TCanvas; ALeft, ATop, ASize: integer; AColor, ABack: TColor;
  AFilled, ACheck: boolean);
var
  W, H, Mid, Side: integer;
  Points: array[0..4] of TPoint;
  Check: array[0..2] of TPoint;
begin
  H := ASize;
  W := (ASize * 5 + 3) div 6;
  Mid := ALeft + W div 2;
  Side := ATop + (H * 3) div 5;
  Points[0] := Point(ALeft, ATop);
  Points[1] := Point(ALeft + W, ATop);
  Points[2] := Point(ALeft + W, Side);
  Points[3] := Point(Mid, ATop + H);
  Points[4] := Point(ALeft, Side);
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Color := AColor;
  ACanvas.Pen.Width := 1;
  if AFilled then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := AColor;
  end
  else
    ACanvas.Brush.Style := bsClear;
  ACanvas.Polygon(Points);
  if AFilled and ACheck then
  begin
    Check[0] := Point(ALeft + (W * 27) div 100, ATop + (H * 48) div 100);
    Check[1] := Point(ALeft + (W * 45) div 100, ATop + (H * 66) div 100);
    Check[2] := Point(ALeft + (W * 76) div 100, ATop + (H * 28) div 100);
    ACanvas.Pen.Color := ABack;
    ACanvas.Pen.Width := 2;
    ACanvas.Polyline(Check);
    ACanvas.Pen.Width := 1;
  end;
  ACanvas.Brush.Style := bsClear;
end;

end.
