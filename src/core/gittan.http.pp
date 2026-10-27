unit gittan.http;

{** HTTP and HTTPS through what each platform has: NSURLSession on macOS,
  WinHTTP on Windows and libcurl elsewhere, loaded when the first request
  is made so Gittan starts without it. Gittan links no TLS library of its
  own; these take the system's certificates and proxy. The backends come
  from Trndi's (nsutils.web.urlrequest, winutils.httpclient, trndi.curl),
  cut down to one request that waits for its answer, which a job's thread
  makes, and gives it up when the caller says to (TGittanHttpCancel).
  Redirects are followed. Defining GITTAN_CURL builds the libcurl one on
  macOS too, which is how it is tested there. No LCL. }

{$mode objfpc}{$H+}
{$IF DEFINED(DARWIN) AND NOT DEFINED(GITTAN_CURL)}
  {$DEFINE GITTAN_COCOA}
  {$modeswitch objectivec1}
{$ELSEIF DEFINED(WINDOWS)}
  {$DEFINE GITTAN_WINHTTP}
{$ELSE}
  {$DEFINE GITTAN_CURL}
{$ENDIF}

interface

uses
  Classes, SysUtils;

const
  {** Seconds a request may take before it is given up. }
  DefaultHttpTimeout = 30;
  {** The User-Agent sent when the headers name none; GitHub's API
    refuses a request without one. }
  HttpUserAgent = 'Gittan';
  {** What carries the requests in this build, for the About page. }
  HttpBackend = {$IF DEFINED(GITTAN_COCOA)}'NSURLSession'
    {$ELSEIF DEFINED(GITTAN_WINHTTP)}'WinHTTP'{$ELSE}'libcurl'{$ENDIF};
  {** The error of a request given up (Status 0). }
  HttpGivenUp = 'The request was given up.';

type
  {** Asked every quarter second while a request waits, when the caller
    gives one: True gives the request up, which comes back with Status 0
    and HttpGivenUp. }
  TGittanHttpCancel = function: boolean of object;


  {** What a server answered: its status (200, 404) and its body, or
    Status 0 and why no answer came (no network, no libcurl, a timeout). }
  TGittanHttpResponse = record
    Status: integer;
    Body: string;
    Error: string;
  end;

{** Sends a request and waits for the answer. AHeaders are lines of the
  form 'Name: value'; ABody, when not empty, is sent as it is (UTF-8 for
  text). Any status counts as an answer: a 404 comes back with its body.
  ACancel, when given, is asked as the request waits and gives it up. }
function HttpRequest(const AMethod, AUrl: string;
  const AHeaders: array of string; const ABody: string = '';
  ATimeoutSeconds: integer = DefaultHttpTimeout;
  ACancel: TGittanHttpCancel = nil): TGittanHttpResponse;

function HttpGet(const AUrl: string; const AHeaders: array of string;
  ATimeoutSeconds: integer = DefaultHttpTimeout;
  ACancel: TGittanHttpCancel = nil): TGittanHttpResponse;

{** Whether the server answered with a 2xx status. }
function HttpOk(const AResponse: TGittanHttpResponse): boolean;

{** Why AResponse is not a success, for a message: the error when no
  answer came, else the status; empty for a 2xx. }
function HttpFailure(const AResponse: TGittanHttpResponse): string;

{** Splits a header line 'Name: value' at its first colon, both halves
  trimmed; False when it has no colon or no name. }
function SplitHeader(const ALine: string; out AName, AValue: string): boolean;

{** Splits an http or https URL into what WinHTTP connects with: whether
  it is https, the host (an IPv6 one without its brackets), the port (the
  scheme's when none is given) and the path with its query, '/' when
  none. False for another scheme or no host. }
function SplitUrl(const AUrl: string; out ASecure: boolean; out AHost: string;
  out APort: integer; out APath: string): boolean;

implementation

uses
{$IF DEFINED(GITTAN_COCOA)}
  Math, CocoaAll;
{$ELSEIF DEFINED(GITTAN_WINHTTP)}
  Windows;
{$ELSE}
  ctypes, dynlibs;
{$ENDIF}

type
  TGittanHttpRequest = record
    Method, Url, Body: string;
    Headers: array of string;
    TimeoutSeconds: integer;
    Cancel: TGittanHttpCancel;
  end;
  PGittanHttpRequest = ^TGittanHttpRequest;

function SplitHeader(const ALine: string; out AName, AValue: string): boolean;
var
  P: integer;
begin
  P := Pos(':', ALine);
  AName := Trim(Copy(ALine, 1, P - 1));
  AValue := Trim(Copy(ALine, P + 1, MaxInt));
  Result := (P > 0) and (AName <> '');
end;

function SplitUrl(const AUrl: string; out ASecure: boolean; out AHost: string;
  out APort: integer; out APath: string): boolean;
var
  Rest, HostPort: string;
  P, Close: integer;
begin
  Result := False;
  ASecure := False;
  AHost := '';
  APort := 0;
  APath := '/';
  P := Pos('://', AUrl);
  if P = 0 then
    Exit;
  case LowerCase(Copy(AUrl, 1, P - 1)) of
    'http': APort := 80;
    'https':
      begin
        ASecure := True;
        APort := 443;
      end;
  else
    Exit;
  end;
  Rest := Copy(AUrl, P + 3, MaxInt);
  { The path starts at the first slash, or at a query with no path. }
  P := Pos('/', Rest);
  Close := Pos('?', Rest);
  if (Close > 0) and ((P = 0) or (Close < P)) then
    P := Close;
  if P > 0 then
  begin
    HostPort := Copy(Rest, 1, P - 1);
    APath := Copy(Rest, P, MaxInt);
    if APath[1] = '?' then
      APath := '/' + APath;
  end
  else
    HostPort := Rest;
  { user:password@ is not for a request Gittan makes; drop it. }
  P := LastDelimiter('@', HostPort);
  if P > 0 then
    Delete(HostPort, 1, P);
  if (HostPort <> '') and (HostPort[1] = '[') then
  begin
    Close := Pos(']', HostPort);
    if Close = 0 then
      Exit;
    AHost := Copy(HostPort, 2, Close - 2);
    Delete(HostPort, 1, Close);
    if (HostPort <> '') and (HostPort[1] <> ':') then
      Exit;
  end
  else
  begin
    P := Pos(':', HostPort);
    if P = 0 then
      P := Length(HostPort) + 1;
    AHost := Copy(HostPort, 1, P - 1);
    Delete(HostPort, 1, P - 1);
  end;
  if HostPort <> '' then
  begin
    APort := StrToIntDef(Copy(HostPort, 2, MaxInt), -1);
    if (APort < 1) or (APort > 65535) then
      Exit;
  end;
  Result := AHost <> '';
end;

{ The User-Agent the headers name, else HttpUserAgent; the headers
  without it in AOthers. }
function UserAgentOf(const AHeaders: array of string;
  out AOthers: TStringArray): string;
var
  Line, Name, Value: string;
begin
  Result := HttpUserAgent;
  AOthers := nil;
  for Line in AHeaders do
    if SplitHeader(Line, Name, Value) then
      if SameText(Name, 'User-Agent') then
        Result := Value
      else
        AOthers := Concat(AOthers, [Name + ': ' + Value]);
end;

{ Whether the caller gave the request up. }
function GivenUp(const ARequest: TGittanHttpRequest): boolean;
begin
  Result := Assigned(ARequest.Cancel) and ARequest.Cancel();
end;

{$IF DEFINED(GITTAN_COCOA)}

{ Apple's frameworks expect the FPU's exceptions masked, as C code has
  them; FPC unmasks them on its threads, and on a GCD thread it adopts,
  so CFNetwork's float divisions fault on Apple Silicon. }
const
  AppleFpuMask = [exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision];

type
  { Collects the body and says when the task has ended. The session
    calls it on a queue of its own while Send waits for Done. }
  TGittanSessionDelegate = objcclass(NSObject, NSURLSessionDataDelegateProtocol)
  public
    Body: NSMutableData;
    Failure: NSError;
    Completed: boolean;
    Done: PRTLEvent;
    procedure URLSession_dataTask_didReceiveData({%H-}session: NSURLSession;
      {%H-}dataTask: NSURLSessionDataTask; data: NSData);
      message 'URLSession:dataTask:didReceiveData:';
    procedure URLSession_task_didCompleteWithError({%H-}session: NSURLSession;
      {%H-}task: NSURLSessionTask; error: NSError);
      message 'URLSession:task:didCompleteWithError:';
  end;

procedure TGittanSessionDelegate.URLSession_dataTask_didReceiveData(
  {%H-}session: NSURLSession; {%H-}dataTask: NSURLSessionDataTask; data: NSData);
begin
  SetExceptionMask(AppleFpuMask);
  Body.appendData(data);
end;

procedure TGittanSessionDelegate.URLSession_task_didCompleteWithError(
  {%H-}session: NSURLSession; {%H-}task: NSURLSessionTask; error: NSError);
begin
  SetExceptionMask(AppleFpuMask);
  if error <> nil then
    Failure := NSError(error.retain);
  Completed := True;
  RTLEventSetEvent(Done);
end;

{ Never nil, which NSURL.URLWithString would raise an Objective-C
  exception on: a string that is not UTF-8 gives an empty one. }
function NSStr(const S: string): NSString;
begin
  Result := NSString.stringWithUTF8String(PChar(S));
  if Result = nil then
    Result := NSString.stringWithUTF8String('');
end;

{ An ephemeral session per request with a delegate, since FPC 3.2 has no
  blocks for a completion handler; nothing is cached or kept as a cookie. }
procedure Send(const ARequest: TGittanHttpRequest;
  var AResponse: TGittanHttpResponse);
var
  Mask: TFPUExceptionMask;
  Pool: NSAutoreleasePool;
  Url: NSURL;
  Request: NSMutableURLRequest;
  Config: NSURLSessionConfiguration;
  Delegate: TGittanSessionDelegate;
  Session: NSURLSession;
  Task: NSURLSessionDataTask;
  Others: TStringArray;
  Line, Name, Value: string;
  Deadline: QWord;
begin
  Mask := GetExceptionMask;
  SetExceptionMask(AppleFpuMask);
  Pool := NSAutoreleasePool.alloc.init;
  try
    Url := NSURL.URLWithString(NSStr(ARequest.Url));
    if Url = nil then
    begin
      AResponse.Error := 'Not a URL: ' + ARequest.Url;
      Exit;
    end;
    Request := NSMutableURLRequest.requestWithURL_cachePolicy_timeoutInterval(
      Url, NSURLRequestReloadIgnoringLocalCacheData, ARequest.TimeoutSeconds);
    Request.setHTTPMethod(NSStr(ARequest.Method));
    Request.setValue_forHTTPHeaderField(
      NSStr(UserAgentOf(ARequest.Headers, Others)), NSStr('User-Agent'));
    for Line in Others do
      if SplitHeader(Line, Name, Value) then
        Request.addValue_forHTTPHeaderField(NSStr(Value), NSStr(Name));
    if ARequest.Body <> '' then
      Request.setHTTPBody(NSData.dataWithBytes_length(PChar(ARequest.Body),
        Length(ARequest.Body)));

    Config := NSURLSessionConfiguration.ephemeralSessionConfiguration;
    Config.setTimeoutIntervalForResource(ARequest.TimeoutSeconds);
    Delegate := TGittanSessionDelegate.alloc.init;
    Delegate.Body := NSMutableData.alloc.init;
    Delegate.Done := RTLEventCreate;
    Session := NSURLSession.sessionWithConfiguration_delegate_delegateQueue(
      Config, NSURLSessionDelegateProtocol(Pointer(Delegate)), nil);
    Task := Session.dataTaskWithRequest(Request);
    Task.resume;
    { The session's own timeout ends the task; the margin is for one that
      hangs anyway. The wait is in steps, so a request given up is
      cancelled at once. A cancelled task still reports, soon. }
    Deadline := GetTickCount64 + QWord(ARequest.TimeoutSeconds + 5) * 1000;
    while not Delegate.Completed and (GetTickCount64 < Deadline) and
      not GivenUp(ARequest) do
      RTLEventWaitFor(Delegate.Done, 250);
    if not Delegate.Completed then
    begin
      Task.cancel;
      RTLEventWaitFor(Delegate.Done, 5000);
    end;
    if not Delegate.Completed then
    begin
      { It could still call the delegate: keep it rather than free what
        it would touch. }
      Session.invalidateAndCancel;
      AResponse.Error := 'The request timed out.';
      Exit;
    end;

    if Delegate.Failure <> nil then
      AResponse.Error := StrPas(Delegate.Failure.localizedDescription.UTF8String)
    else if (Task.response <> nil) and
      Task.response.isKindOfClass(NSHTTPURLResponse.classClass) then
    begin
      AResponse.Status := NSHTTPURLResponse(Task.response).statusCode;
      SetLength(AResponse.Body, Delegate.Body.length);
      if AResponse.Body <> '' then
        Move(Delegate.Body.bytes^, AResponse.Body[1], Length(AResponse.Body));
    end;
    Session.finishTasksAndInvalidate;
    RTLEventDestroy(Delegate.Done);
    Delegate.Body.release;
    if Delegate.Failure <> nil then
      Delegate.Failure.release;
    Delegate.release;
  finally
    Pool.release;
    SetExceptionMask(Mask);
  end;
end;

{$ELSEIF DEFINED(GITTAN_WINHTTP)}

type
  HINTERNET = Pointer;

const
  WinHttpDll = 'winhttp.dll';
  WINHTTP_ACCESS_TYPE_DEFAULT_PROXY = 0;
  { The system's proxy settings and its auto-configuration, Windows 8.1
    and later. }
  WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY = 4;
  WINHTTP_FLAG_SECURE = $00800000;
  WINHTTP_OPTION_SECURE_PROTOCOLS = 84;
  WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2 = $00000800;
  WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_3 = $00002000;
  WINHTTP_OPTION_DECOMPRESSION = 118;
  WINHTTP_DECOMPRESSION_FLAG_ALL = 3;
  WINHTTP_QUERY_STATUS_CODE = 19;
  WINHTTP_QUERY_FLAG_NUMBER = $20000000;
  ERROR_WINHTTP_TIMEOUT = 12002;

function WinHttpOpen(pszAgent: PWideChar; dwAccessType: DWORD;
  pszProxy, pszProxyBypass: PWideChar; dwFlags: DWORD): HINTERNET;
  stdcall; external WinHttpDll;
function WinHttpSetTimeouts(hInternet: HINTERNET; nResolveTimeout,
  nConnectTimeout, nSendTimeout, nReceiveTimeout: integer): BOOL;
  stdcall; external WinHttpDll;
function WinHttpSetOption(hInternet: HINTERNET; dwOption: DWORD;
  lpBuffer: Pointer; dwBufferLength: DWORD): BOOL;
  stdcall; external WinHttpDll;
function WinHttpConnect(hSession: HINTERNET; pswzServerName: PWideChar;
  nServerPort: word; dwReserved: DWORD): HINTERNET;
  stdcall; external WinHttpDll;
function WinHttpOpenRequest(hConnect: HINTERNET; pwszVerb, pwszObjectName,
  pwszVersion, pwszReferrer: PWideChar; ppwszAcceptTypes: Pointer;
  dwFlags: DWORD): HINTERNET;
  stdcall; external WinHttpDll;
function WinHttpSendRequest(hRequest: HINTERNET; lpszHeaders: PWideChar;
  dwHeadersLength: DWORD; lpOptional: Pointer; dwOptionalLength: DWORD;
  dwTotalLength: DWORD; dwContext: DWORD_PTR): BOOL;
  stdcall; external WinHttpDll;
function WinHttpReceiveResponse(hRequest: HINTERNET; lpReserved: Pointer): BOOL;
  stdcall; external WinHttpDll;
function WinHttpQueryHeaders(hRequest: HINTERNET; dwInfoLevel: DWORD;
  pwszName: PWideChar; lpBuffer: Pointer; var lpdwBufferLength: DWORD;
  lpdwIndex: Pointer): BOOL;
  stdcall; external WinHttpDll;
function WinHttpReadData(hRequest: HINTERNET; lpBuffer: Pointer;
  dwNumberOfBytesToRead: DWORD; var lpdwNumberOfBytesRead: DWORD): BOOL;
  stdcall; external WinHttpDll;
function WinHttpCloseHandle(hInternet: HINTERNET): BOOL;
  stdcall; external WinHttpDll;

{ WinHTTP's 12xxx codes are in winhttp.dll's message table, not the
  system's that SysErrorMessage reads. }
function WinHttpMessage(ACode: DWORD): string;
var
  Buffer: array[0..511] of WideChar;
  Len: DWORD;
  Text: UnicodeString;
begin
  Len := FormatMessageW(FORMAT_MESSAGE_FROM_HMODULE or
    FORMAT_MESSAGE_FROM_SYSTEM or FORMAT_MESSAGE_IGNORE_INSERTS,
    Pointer(GetModuleHandle(WinHttpDll)), ACode, 0, @Buffer[0],
    Length(Buffer), nil);
  if Len = 0 then
    Exit(Format('WinHTTP error %d', [ACode]));
  SetString(Text, PWideChar(@Buffer[0]), Len);
  Result := Trim(UTF8Encode(Text));
end;

procedure SendSync(const ARequest: TGittanHttpRequest;
  var AResponse: TGittanHttpResponse);
var
  Secure: boolean;
  Host, Path, Agent, Line: string;
  Port: integer;
  Others: TStringArray;
  Headers: UnicodeString;
  HeadersPtr: PWideChar;
  Session, Connect, Request: HINTERNET;
  Value, Size, Got: DWORD;
  Buffer: array[0..16383] of byte;
  Body: TMemoryStream;

  procedure Fail;
  var
    Code: DWORD;
  begin
    Code := GetLastError;
    if Code = ERROR_WINHTTP_TIMEOUT then
      AResponse.Error := 'The request timed out.'
    else
      AResponse.Error := WinHttpMessage(Code);
  end;

begin
  if not SplitUrl(ARequest.Url, Secure, Host, Port, Path) then
  begin
    AResponse.Error := 'Not a URL: ' + ARequest.Url;
    Exit;
  end;
  Agent := UserAgentOf(ARequest.Headers, Others);
  Headers := '';
  for Line in Others do
    Headers := Headers + UTF8Decode(Line) + #13#10;

  Session := WinHttpOpen(PWideChar(UTF8Decode(Agent)),
    WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, nil, nil, 0);
  if Session = nil then
    Session := WinHttpOpen(PWideChar(UTF8Decode(Agent)),
      WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, nil, nil, 0);
  if Session = nil then
  begin
    Fail;
    Exit;
  end;
  Connect := nil;
  Request := nil;
  Body := TMemoryStream.Create;
  try
    WinHttpSetTimeouts(Session, ARequest.TimeoutSeconds * 1000,
      ARequest.TimeoutSeconds * 1000, ARequest.TimeoutSeconds * 1000,
      ARequest.TimeoutSeconds * 1000);
    { Windows 7 and 8 leave TLS 1.2 off unless asked; 1.3 is refused
      before Windows 11, so 1.2 alone then. }
    Value := WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2 or WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_3;
    if not WinHttpSetOption(Session, WINHTTP_OPTION_SECURE_PROTOCOLS, @Value,
      SizeOf(Value)) then
    begin
      Value := WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2;
      WinHttpSetOption(Session, WINHTTP_OPTION_SECURE_PROTOCOLS, @Value,
        SizeOf(Value));
    end;
    Value := WINHTTP_DECOMPRESSION_FLAG_ALL;
    WinHttpSetOption(Session, WINHTTP_OPTION_DECOMPRESSION, @Value, SizeOf(Value));

    Connect := WinHttpConnect(Session, PWideChar(UTF8Decode(Host)), Port, 0);
    if Connect = nil then
    begin
      Fail;
      Exit;
    end;
    if Secure then
      Value := WINHTTP_FLAG_SECURE
    else
      Value := 0;
    Request := WinHttpOpenRequest(Connect, PWideChar(UTF8Decode(ARequest.Method)),
      PWideChar(UTF8Decode(Path)), nil, nil, nil, Value);
    if Request = nil then
    begin
      Fail;
      Exit;
    end;
    if Headers <> '' then
      HeadersPtr := PWideChar(Headers)
    else
      HeadersPtr := nil;
    if not WinHttpSendRequest(Request, HeadersPtr, Length(Headers),
      PChar(ARequest.Body), Length(ARequest.Body), Length(ARequest.Body), 0)
      or not WinHttpReceiveResponse(Request, nil) then
    begin
      Fail;
      Exit;
    end;
    Size := SizeOf(Value);
    if not WinHttpQueryHeaders(Request, WINHTTP_QUERY_STATUS_CODE or
      WINHTTP_QUERY_FLAG_NUMBER, nil, @Value, Size, nil) then
    begin
      Fail;
      Exit;
    end;
    repeat
      Got := 0;
      if not WinHttpReadData(Request, @Buffer[0], SizeOf(Buffer), Got) then
      begin
        Fail;
        Exit;
      end;
      Body.WriteBuffer(Buffer[0], Got);
    until Got = 0;
    AResponse.Status := Value;
    SetLength(AResponse.Body, Body.Size);
    if Body.Size > 0 then
      Move(Body.Memory^, AResponse.Body[1], Body.Size);
  finally
    Body.Free;
    if Request <> nil then
      WinHttpCloseHandle(Request);
    if Connect <> nil then
      WinHttpCloseHandle(Connect);
    WinHttpCloseHandle(Session);
  end;
end;

type
  { SendSync in a thread of its own, so a request can be given up while
    a WinHTTP call still waits: WinHTTP's documentation rules out
    closing the handle of a synchronous request from another thread. The
    caller waits for Done in steps; one that gives up (Abandon) leaves
    the thread to end on its own, by its timeouts at the latest, and to
    free itself then. The lock keeps the two from doing both. }
  TGittanWinHttpSender = class(TThread)
  private
    FRequest: TGittanHttpRequest;
    FResponse: TGittanHttpResponse;
    FLock: TRTLCriticalSection;
    FEnded, FAbandoned: boolean;
  protected
    procedure Execute; override;
  public
    Done: PRTLEvent;
    constructor Create(const ARequest: TGittanHttpRequest);
    destructor Destroy; override;
    { Whether the request has ended. }
    function Ended: boolean;
    { Leaves the thread to itself; True when the request had ended
      already, so the caller takes its answer and frees the thread. }
    function Abandon: boolean;
    property Response: TGittanHttpResponse read FResponse;
  end;

constructor TGittanWinHttpSender.Create(const ARequest: TGittanHttpRequest);
begin
  inherited Create(True);
  FRequest := ARequest;
  FRequest.Cancel := nil;
  FResponse := Default(TGittanHttpResponse);
  InitCriticalSection(FLock);
  Done := RTLEventCreate;
end;

destructor TGittanWinHttpSender.Destroy;
begin
  inherited Destroy;
  RTLEventDestroy(Done);
  DoneCriticalSection(FLock);
end;

procedure TGittanWinHttpSender.Execute;
begin
  try
    SendSync(FRequest, FResponse);
  except
    on E: Exception do
    begin
      FResponse.Status := 0;
      FResponse.Error := E.Message;
    end;
  end;
  EnterCriticalSection(FLock);
  try
    FEnded := True;
    FreeOnTerminate := FAbandoned;
  finally
    LeaveCriticalSection(FLock);
  end;
  RTLEventSetEvent(Done);
end;

function TGittanWinHttpSender.Ended: boolean;
begin
  EnterCriticalSection(FLock);
  try
    Result := FEnded;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TGittanWinHttpSender.Abandon: boolean;
begin
  EnterCriticalSection(FLock);
  try
    Result := FEnded;
    FAbandoned := not FEnded;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure Send(const ARequest: TGittanHttpRequest;
  var AResponse: TGittanHttpResponse);
var
  Sender: TGittanWinHttpSender;
begin
  if not Assigned(ARequest.Cancel) then
  begin
    SendSync(ARequest, AResponse);
    Exit;
  end;
  Sender := TGittanWinHttpSender.Create(ARequest);
  Sender.Start;
  while True do
  begin
    RTLEventWaitFor(Sender.Done, 250);
    if Sender.Ended then
      Break;
    if GivenUp(ARequest) and not Sender.Abandon then
      Exit;
  end;
  AResponse := Sender.Response;
  Sender.Free;
end;

{$ELSE}

{ libcurl through dlopen: a Linux without it still starts and says so
  when asked for a request. The values are curl.h's, a stable part of
  its ABI. curl_easy_setopt and curl_easy_getinfo are variadic, which
  Apple's arm64 ABI passes on the stack, so their types say varargs. }
const
  CURLE_OK = 0;
  CURL_GLOBAL_DEFAULT = 3;
  CURL_ERROR_SIZE = 256;
  CURLOPT_WRITEDATA = 10001;
  CURLOPT_URL = 10002;
  CURLOPT_ERRORBUFFER = 10010;
  CURLOPT_WRITEFUNCTION = 20011;
  CURLOPT_TIMEOUT = 13;
  CURLOPT_POSTFIELDS = 10015;
  CURLOPT_USERAGENT = 10018;
  CURLOPT_HTTPHEADER = 10023;
  CURLOPT_CUSTOMREQUEST = 10036;
  CURLOPT_NOPROGRESS = 43;
  CURLOPT_NOBODY = 44;
  CURLOPT_FOLLOWLOCATION = 52;
  CURLOPT_POSTFIELDSIZE = 60;
  CURLOPT_MAXREDIRS = 68;
  CURLOPT_NOSIGNAL = 99;
  CURLOPT_ACCEPT_ENCODING = 10102;
  CURLOPT_XFERINFODATA = 10057;
  CURLOPT_XFERINFOFUNCTION = 20219;
  CURLINFO_RESPONSE_CODE = $200002;
  CurlNames: array[0..2] of string = (
    {$IFDEF DARWIN}'libcurl.4.dylib', 'libcurl.dylib', ''
    {$ELSE}'libcurl.so.4', 'libcurl.so', 'libcurl-gnutls.so.4'{$ENDIF});

type
  PCurlSlist = Pointer;

var
  CurlLock: TRTLCriticalSection;
  CurlTried: boolean;
  CurlLib: TLibHandle = NilHandle;
  curl_global_init: function(flags: clong): cint; cdecl;
  curl_easy_init: function: Pointer; cdecl;
  curl_easy_setopt: function(handle: Pointer; option: cint): cint; cdecl; varargs;
  curl_easy_perform: function(handle: Pointer): cint; cdecl;
  curl_easy_getinfo: function(handle: Pointer; info: cint): cint; cdecl; varargs;
  curl_easy_cleanup: procedure(handle: Pointer); cdecl;
  curl_easy_strerror: function(code: cint): PChar; cdecl;
  curl_slist_append: function(list: PCurlSlist; s: PChar): PCurlSlist; cdecl;
  curl_slist_free_all: procedure(list: PCurlSlist); cdecl;

{ Loads libcurl the first time; the lock keeps two jobs from doing it at
  once, and curl_global_init is not safe to run beside other threads'
  curl calls, which it comes before here. }
function CurlLoaded: boolean;
var
  Name: string;
begin
  EnterCriticalSection(CurlLock);
  try
    if not CurlTried then
    begin
      CurlTried := True;
      for Name in CurlNames do
        if (Name <> '') and (CurlLib = NilHandle) then
          CurlLib := LoadLibrary(Name);
      if CurlLib <> NilHandle then
      begin
        Pointer(curl_global_init) := GetProcAddress(CurlLib, 'curl_global_init');
        Pointer(curl_easy_init) := GetProcAddress(CurlLib, 'curl_easy_init');
        Pointer(curl_easy_setopt) := GetProcAddress(CurlLib, 'curl_easy_setopt');
        Pointer(curl_easy_perform) := GetProcAddress(CurlLib, 'curl_easy_perform');
        Pointer(curl_easy_getinfo) := GetProcAddress(CurlLib, 'curl_easy_getinfo');
        Pointer(curl_easy_cleanup) := GetProcAddress(CurlLib, 'curl_easy_cleanup');
        Pointer(curl_easy_strerror) := GetProcAddress(CurlLib, 'curl_easy_strerror');
        Pointer(curl_slist_append) := GetProcAddress(CurlLib, 'curl_slist_append');
        Pointer(curl_slist_free_all) := GetProcAddress(CurlLib, 'curl_slist_free_all');
        if not Assigned(curl_global_init) or not Assigned(curl_easy_init)
          or not Assigned(curl_easy_setopt) or not Assigned(curl_easy_perform)
          or not Assigned(curl_easy_getinfo) or not Assigned(curl_easy_cleanup)
          or not Assigned(curl_easy_strerror) or not Assigned(curl_slist_append)
          or not Assigned(curl_slist_free_all)
          or (curl_global_init(CURL_GLOBAL_DEFAULT) <> CURLE_OK) then
        begin
          UnloadLibrary(CurlLib);
          CurlLib := NilHandle;
        end;
      end;
    end;
    Result := CurlLib <> NilHandle;
  finally
    LeaveCriticalSection(CurlLock);
  end;
end;

function CurlWrite(ABuffer: PChar; ASize, ACount: csize_t;
  AData: Pointer): csize_t; cdecl;
begin
  Result := ASize * ACount;
  TMemoryStream(AData).WriteBuffer(ABuffer^, Result);
end;

{ Called at least once a second while the request runs, waiting for the
  answer too; not 0 ends it (CURLE_ABORTED_BY_CALLBACK). }
function CurlProgress(AData: Pointer; {%H-}ADownTotal, {%H-}ADown,
  {%H-}AUpTotal, {%H-}AUp: cint64): cint; cdecl;
begin
  Result := Ord(GivenUp(PGittanHttpRequest(AData)^));
end;

procedure Send(const ARequest: TGittanHttpRequest;
  var AResponse: TGittanHttpResponse);
var
  Curl: Pointer;
  List, Next: PCurlSlist;
  Others: TStringArray;
  Agent, Line: string;
  Errors: array[0..CURL_ERROR_SIZE] of char;
  Code: cint;
  Status: clong;
  Body: TMemoryStream;
begin
  if not CurlLoaded then
  begin
    AResponse.Error := 'libcurl is not installed.';
    Exit;
  end;
  Curl := curl_easy_init();
  if Curl = nil then
  begin
    AResponse.Error := 'libcurl could not start a request.';
    Exit;
  end;
  List := nil;
  Body := TMemoryStream.Create;
  try
    Agent := UserAgentOf(ARequest.Headers, Others);
    { Keep curl from waiting a second for a 100 Continue on a big body. }
    for Line in Concat(Others, ['Expect:']) do
    begin
      Next := curl_slist_append(List, PChar(Line));
      if Next <> nil then
        List := Next;
    end;
    Errors[0] := #0;
    curl_easy_setopt(Curl, CURLOPT_URL, PChar(ARequest.Url));
    curl_easy_setopt(Curl, CURLOPT_USERAGENT, PChar(Agent));
    curl_easy_setopt(Curl, CURLOPT_HTTPHEADER, List);
    curl_easy_setopt(Curl, CURLOPT_ERRORBUFFER, @Errors[0]);
    curl_easy_setopt(Curl, CURLOPT_FOLLOWLOCATION, clong(1));
    curl_easy_setopt(Curl, CURLOPT_MAXREDIRS, clong(10));
    curl_easy_setopt(Curl, CURLOPT_TIMEOUT, clong(ARequest.TimeoutSeconds));
    { No SIGALRM for the timeout, which would hit any thread. }
    curl_easy_setopt(Curl, CURLOPT_NOSIGNAL, clong(1));
    curl_easy_setopt(Curl, CURLOPT_ACCEPT_ENCODING, PChar(''));
    curl_easy_setopt(Curl, CURLOPT_WRITEFUNCTION, @CurlWrite);
    curl_easy_setopt(Curl, CURLOPT_WRITEDATA, Pointer(Body));
    if Assigned(ARequest.Cancel) then
    begin
      curl_easy_setopt(Curl, CURLOPT_XFERINFOFUNCTION, @CurlProgress);
      curl_easy_setopt(Curl, CURLOPT_XFERINFODATA, Pointer(@ARequest));
      curl_easy_setopt(Curl, CURLOPT_NOPROGRESS, clong(0));
    end;
    if ARequest.Method = 'HEAD' then
      curl_easy_setopt(Curl, CURLOPT_NOBODY, clong(1))
    else if ARequest.Method <> 'GET' then
    begin
      curl_easy_setopt(Curl, CURLOPT_POSTFIELDSIZE, clong(Length(ARequest.Body)));
      curl_easy_setopt(Curl, CURLOPT_POSTFIELDS, PChar(ARequest.Body));
      if ARequest.Method <> 'POST' then
        curl_easy_setopt(Curl, CURLOPT_CUSTOMREQUEST, PChar(ARequest.Method));
    end;
    Code := curl_easy_perform(Curl);
    if Code <> CURLE_OK then
    begin
      AResponse.Error := StrPas(@Errors[0]);
      if AResponse.Error = '' then
        AResponse.Error := StrPas(curl_easy_strerror(Code));
      Exit;
    end;
    Status := 0;
    curl_easy_getinfo(Curl, CURLINFO_RESPONSE_CODE, @Status);
    AResponse.Status := Status;
    SetLength(AResponse.Body, Body.Size);
    if Body.Size > 0 then
      Move(Body.Memory^, AResponse.Body[1], Body.Size);
  finally
    Body.Free;
    curl_slist_free_all(List);
    curl_easy_cleanup(Curl);
  end;
end;

{$ENDIF}

function HttpRequest(const AMethod, AUrl: string;
  const AHeaders: array of string; const ABody: string;
  ATimeoutSeconds: integer; ACancel: TGittanHttpCancel): TGittanHttpResponse;
var
  Request: TGittanHttpRequest;
  i: integer;
begin
  Result := Default(TGittanHttpResponse);
  Request := Default(TGittanHttpRequest);
  Request.Cancel := ACancel;
  Request.Method := UpperCase(AMethod);
  Request.Url := AUrl;
  Request.Body := ABody;
  SetLength(Request.Headers, Length(AHeaders));
  for i := 0 to High(AHeaders) do
    Request.Headers[i] := AHeaders[i];
  Request.TimeoutSeconds := ATimeoutSeconds;
  if Request.TimeoutSeconds < 1 then
    Request.TimeoutSeconds := 1;
  try
    Send(Request, Result);
  except
    on E: Exception do
    begin
      Result.Status := 0;
      Result.Error := E.Message;
    end;
  end;
  if Result.Status = 0 then
  begin
    Result.Body := '';
    { Given up: whatever the backend said of the task it cancelled. }
    if Assigned(ACancel) and ACancel() then
      Result.Error := HttpGivenUp
    else if Result.Error = '' then
      Result.Error := 'No answer from ' + AUrl;
  end;
end;

function HttpGet(const AUrl: string; const AHeaders: array of string;
  ATimeoutSeconds: integer; ACancel: TGittanHttpCancel): TGittanHttpResponse;
begin
  Result := HttpRequest('GET', AUrl, AHeaders, '', ATimeoutSeconds, ACancel);
end;

function HttpOk(const AResponse: TGittanHttpResponse): boolean;
begin
  Result := (AResponse.Status >= 200) and (AResponse.Status < 300);
end;

function HttpFailure(const AResponse: TGittanHttpResponse): string;
begin
  if HttpOk(AResponse) then
    Result := ''
  else if AResponse.Status = 0 then
    Result := AResponse.Error
  else
    Result := Format('The server answered %d.', [AResponse.Status]);
end;

{$IFDEF GITTAN_CURL}
initialization
  InitCriticalSection(CurlLock);

finalization
  DoneCriticalSection(CurlLock);
{$ENDIF}
end.
