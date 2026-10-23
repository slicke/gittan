unit testsha256;

{** Tests of gittan.sha256 against the FIPS 180-2 examples and inputs
  around the 56 byte padding edge, checked with shasum. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, gittan.sha256;

type
  TSHA256Test = class(TTestCase)
  published
    procedure TestKnown;
    procedure TestPaddingEdges;
    procedure TestBytes;
  end;

implementation

function Hex(const AData: RawByteString): string;
begin
  Result := SHA256Print(SHA256String(AData));
end;

procedure TSHA256Test.TestKnown;
begin
  AssertEquals('empty',
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', Hex(''));
  AssertEquals('abc',
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', Hex('abc'));
  AssertEquals('two blocks',
    '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    Hex('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'));
end;

procedure TSHA256Test.TestPaddingEdges;
begin
  AssertEquals('55 bytes',
    '9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318',
    Hex(StringOfChar('a', 55)));
  AssertEquals('56 bytes',
    'b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a',
    Hex(StringOfChar('a', 56)));
  AssertEquals('64 bytes',
    'ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb',
    Hex(StringOfChar('a', 64)));
end;

{ Bytes above 127 and NUL go in as they are. }
procedure TSHA256Test.TestBytes;
begin
  AssertEquals('c3 a5 00 ff',
    '6eb47a0602b3e56717648848f99455bcc0e3916f62ad78054349c07e023fae5b',
    Hex(#$C3#$A5#0#$FF));
end;

initialization
  RegisterTest(TSHA256Test);
end.
