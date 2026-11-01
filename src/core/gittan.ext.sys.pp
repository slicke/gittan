unit gittan.ext.sys;

{** What the extension engine takes from the system: a monotonic clock
  for performance.now and random bytes for crypto.getRandomValues. Both
  are what Trndi's native layer gave its engine, kept apart from it here
  so the engine needs nothing of the platform units. }

{$mode objfpc}{$H+}

interface

{** Microseconds of a clock that only goes forward, from no fixed
  start. }
function MonotonicMicroseconds: int64;

{** ACount random bytes from the system's secure source into ABuf;
  False when it has none, never weaker bytes. }
function RandomBytes(ABuf: PByte; ACount: integer): boolean;

implementation

uses
  SysUtils{$IFDEF WINDOWS}, Windows{$ELSE}, BaseUnix{$ENDIF};

{$IFDEF WINDOWS}
{ Present since Windows XP, with no provider handle to open. }
function RtlGenRandom(RandomBuffer: pointer; RandomBufferLength: ULONG): ByteBool;
  stdcall; external 'advapi32.dll' name 'SystemFunction036';

function MonotonicMicroseconds: int64;
var
  Freq, Count: int64;
begin
  if QueryPerformanceFrequency(Freq) and (Freq > 0) and QueryPerformanceCounter(Count) then
    { In two parts, so the product does not overflow on a long uptime. }
    Result := (Count div Freq) * 1000000 + ((Count mod Freq) * 1000000) div Freq
  else
    Result := int64(GetTickCount64) * 1000;
end;

function RandomBytes(ABuf: PByte; ACount: integer): boolean;
begin
  if (ABuf = nil) or (ACount <= 0) then
    Exit(False);
  try
    Result := RtlGenRandom(ABuf, ULONG(ACount));
  except
    Result := False;
  end;
end;
{$ELSE}
type
  TTimespec = record
    tv_sec: clong;
    tv_nsec: clong;
  end;

function sys_clock_gettime(clk_id: cint; tp: pointer): cint;
  cdecl; external 'c' name 'clock_gettime';

function MonotonicMicroseconds: int64;
const
  { CLOCK_MONOTONIC: 6 on Darwin, 4 on FreeBSD, 0 on Haiku, 1 on Linux. }
  ClockMonotonic = {$IF DEFINED(DARWIN)}6{$ELSEIF DEFINED(FREEBSD)}4{$ELSEIF DEFINED(HAIKU)}0{$ELSE}1{$ENDIF};
var
  ts: TTimespec;
begin
  ts := Default(TTimespec);
  if sys_clock_gettime(ClockMonotonic, @ts) = 0 then
    Result := int64(ts.tv_sec) * 1000000 + int64(ts.tv_nsec) div 1000
  else
    Result := int64(GetTickCount64) * 1000;
end;

function RandomBytes(ABuf: PByte; ACount: integer): boolean;
var
  fd: cint;
  Got, n: integer;
begin
  Result := False;
  if (ABuf = nil) or (ACount <= 0) then
    Exit;
  fd := FpOpen('/dev/urandom', O_RDONLY);
  if fd < 0 then
    Exit;
  try
    Got := 0;
    while Got < ACount do
    begin
      n := FpRead(fd, ABuf[Got], ACount - Got);
      if (n < 0) and (fpgeterrno = ESysEINTR) then
        Continue;
      if n <= 0 then
        Exit;
      Inc(Got, n);
    end;
    Result := True;
  finally
    FpClose(fd);
  end;
end;
{$ENDIF}

end.
