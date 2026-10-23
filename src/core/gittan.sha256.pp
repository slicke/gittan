unit gittan.sha256;

{** SHA-256 of a byte string, for the trust of a repository's commands
  file (gittan.repocommands), where MD5's collisions would let a file
  trusted once be swapped for another of the same hash. FPC 3.2.2, which
  CI builds Windows and Linux with, has no SHA-256 unit of its own.

  From slicke.sha256 in Trndi (github.com/slicke/trndi). }

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TSHA256Digest = array[0..31] of byte;

{** The digest of AData's bytes as they are, no code page conversion. }
function SHA256String(const AData: RawByteString): TSHA256Digest;

{** ADigest in lower case hex, 64 characters. }
function SHA256Print(const ADigest: TSHA256Digest): string;

implementation

type
  TWordArray64 = array[0..63] of longword;

const
  K: TWordArray64 = (
    $428A2F98, $71374491, $B5C0FBCF, $E9B5DBA5, $3956C25B, $59F111F1, $923F82A4, $AB1C5ED5,
    $D807AA98, $12835B01, $243185BE, $550C7DC3, $72BE5D74, $80DEB1FE, $9BDC06A7, $C19BF174,
    $E49B69C1, $EFBE4786, $0FC19DC6, $240CA1CC, $2DE92C6F, $4A7484AA, $5CB0A9DC, $76F988DA,
    $983E5152, $A831C66D, $B00327C8, $BF597FC7, $C6E00BF3, $D5A79147, $06CA6351, $14292967,
    $27B70A85, $2E1B2138, $4D2C6DFC, $53380D13, $650A7354, $766A0ABB, $81C2C92E, $92722C85,
    $A2BFE8A1, $A81A664B, $C24B8B70, $C76C51A3, $D192E819, $D6990624, $F40E3585, $106AA070,
    $19A4C116, $1E376C08, $2748774C, $34B0BCB5, $391C0CB3, $4ED8AA4A, $5B9CCA4F, $682E6FF3,
    $748F82EE, $78A5636F, $84C87814, $8CC70208, $90BEFFFA, $A4506CEB, $BEF9A3F7, $C67178F2);

function ROR32(X, N: longword): longword; inline;
begin
  Result := (X shr N) or (X shl (32 - N));
end;

function Ch(X, Y, Z: longword): longword; inline;
begin
  Result := (X and Y) xor ((not X) and Z);
end;

function Maj(X, Y, Z: longword): longword; inline;
begin
  Result := (X and Y) xor (X and Z) xor (Y and Z);
end;

function BigSigma0(X: longword): longword; inline;
begin
  Result := ROR32(X, 2) xor ROR32(X, 13) xor ROR32(X, 22);
end;

function BigSigma1(X: longword): longword; inline;
begin
  Result := ROR32(X, 6) xor ROR32(X, 11) xor ROR32(X, 25);
end;

function SmallSigma0(X: longword): longword; inline;
begin
  Result := ROR32(X, 7) xor ROR32(X, 18) xor (X shr 3);
end;

function SmallSigma1(X: longword): longword; inline;
begin
  Result := ROR32(X, 17) xor ROR32(X, 19) xor (X shr 10);
end;

{ The sums are taken in QWord and cut to 32 bits, so they wrap as the
  algorithm wants whatever $Q and $R say. }
function SHA256String(const AData: RawByteString): TSHA256Digest;
var
  Data: TBytes;
  BitLen: QWord;
  NewLen, OrigLen, i, t, BlockStart: SizeInt;
  Hash: array[0..7] of longword;
  W: TWordArray64;
  a, b, c, d, e, f, g, h, T1, T2: longword;
begin
  Hash[0] := $6A09E667;
  Hash[1] := $BB67AE85;
  Hash[2] := $3C6EF372;
  Hash[3] := $A54FF53A;
  Hash[4] := $510E527F;
  Hash[5] := $9B05688C;
  Hash[6] := $1F83D9AB;
  Hash[7] := $5BE0CD19;

  OrigLen := Length(AData);
  BitLen := QWord(OrigLen) * 8;
  { $80, then zeros up to 56 mod 64, then the length in bits. }
  NewLen := OrigLen + 1;
  Data := nil;
  while NewLen mod 64 <> 56 do
    Inc(NewLen);
  SetLength(Data, NewLen + 8);
  if OrigLen > 0 then
    Move(AData[1], Data[0], OrigLen);
  Data[OrigLen] := $80;
  for i := OrigLen + 1 to NewLen - 1 do
    Data[i] := 0;
  for i := 0 to 7 do
    Data[NewLen + i] := (BitLen shr (56 - 8 * i)) and $FF;

  BlockStart := 0;
  while BlockStart < Length(Data) do
  begin
    for t := 0 to 15 do
      W[t] := (longword(Data[BlockStart + t * 4]) shl 24) or
        (longword(Data[BlockStart + t * 4 + 1]) shl 16) or
        (longword(Data[BlockStart + t * 4 + 2]) shl 8) or
        longword(Data[BlockStart + t * 4 + 3]);
    for t := 16 to 63 do
      W[t] := longword((QWord(SmallSigma1(W[t - 2])) + W[t - 7] +
        SmallSigma0(W[t - 15]) + W[t - 16]) and $FFFFFFFF);

    a := Hash[0];
    b := Hash[1];
    c := Hash[2];
    d := Hash[3];
    e := Hash[4];
    f := Hash[5];
    g := Hash[6];
    h := Hash[7];
    for t := 0 to 63 do
    begin
      T1 := longword((QWord(h) + BigSigma1(e) + Ch(e, f, g) + K[t] + W[t]) and $FFFFFFFF);
      T2 := longword((QWord(BigSigma0(a)) + Maj(a, b, c)) and $FFFFFFFF);
      h := g;
      g := f;
      f := e;
      e := longword((QWord(d) + T1) and $FFFFFFFF);
      d := c;
      c := b;
      b := a;
      a := longword((QWord(T1) + T2) and $FFFFFFFF);
    end;
    Hash[0] := longword((QWord(Hash[0]) + a) and $FFFFFFFF);
    Hash[1] := longword((QWord(Hash[1]) + b) and $FFFFFFFF);
    Hash[2] := longword((QWord(Hash[2]) + c) and $FFFFFFFF);
    Hash[3] := longword((QWord(Hash[3]) + d) and $FFFFFFFF);
    Hash[4] := longword((QWord(Hash[4]) + e) and $FFFFFFFF);
    Hash[5] := longword((QWord(Hash[5]) + f) and $FFFFFFFF);
    Hash[6] := longword((QWord(Hash[6]) + g) and $FFFFFFFF);
    Hash[7] := longword((QWord(Hash[7]) + h) and $FFFFFFFF);
    Inc(BlockStart, 64);
  end;

  for i := 0 to 7 do
  begin
    Result[i * 4] := (Hash[i] shr 24) and $FF;
    Result[i * 4 + 1] := (Hash[i] shr 16) and $FF;
    Result[i * 4 + 2] := (Hash[i] shr 8) and $FF;
    Result[i * 4 + 3] := Hash[i] and $FF;
  end;
end;

function SHA256Print(const ADigest: TSHA256Digest): string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(ADigest) do
    Result := Result + LowerCase(IntToHex(ADigest[i], 2));
end;

end.
