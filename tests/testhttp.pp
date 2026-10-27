unit testhttp;

{** Tests of gittan.http: the header and URL splitting, and requests to
  a server of the test's own on 127.0.0.1, over plain HTTP, through the
  backend this build has (built with -dGITTAN_CURL, through libcurl on
  macOS too). The server answers one connection at a time: /echo with the
  method, the X-Test and User-Agent headers and the body, a line each;
  /missing with a 404; /moved with a redirect to /echo; /slow after
  SlowMs, longer than the timeout the test gives, and before a request
  given up comes back. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, sockets, gittan.http;

type
  TTestServer = class(TThread)
  private
    FSocket: longint;
    FPort: integer;
    FStopping: boolean;
    procedure Serve(AClient: longint);
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    property Port: integer read FPort;
  end;

  THttpTest = class(TTestCase)
  private
    FServer: TTestServer;
    function Url(const APath: string): string;
    function GiveUp: boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSplitHeader;
    procedure TestSplitUrl;
    procedure TestGet;
    procedure TestPost;
    procedure TestUserAgent;
    procedure TestNotFound;
    procedure TestRedirect;
    procedure TestRefused;
    procedure TestTimeout;
    procedure TestGivenUp;
  end;

implementation

const
  SlowMs = 2500;

function LoopbackAddr(APort: integer): TInetSockAddr;
begin
  Result := Default(TInetSockAddr);
  Result.sin_family := AF_INET;
  Result.sin_port := htons(APort);
  Result.sin_addr.s_addr := htonl($7F000001);
end;

{ A port nothing listens on: one the system gave and took back. }
function FreePort: integer;
var
  S: longint;
  Addr: TInetSockAddr;
  Len: TSockLen;
begin
  S := fpSocket(AF_INET, SOCK_STREAM, 0);
  Addr := LoopbackAddr(0);
  fpBind(S, @Addr, SizeOf(Addr));
  Len := SizeOf(Addr);
  fpGetSockName(S, @Addr, @Len);
  Result := ntohs(Addr.sin_port);
  CloseSocket(S);
end;

function HeaderOf(const AHead, AName: string): string;
var
  Lines: TStringList;
  i: integer;
  Name, Value: string;
begin
  Result := '';
  Lines := TStringList.Create;
  try
    Lines.Text := AHead;
    for i := 1 to Lines.Count - 1 do
      if SplitHeader(Lines[i], Name, Value) and SameText(Name, AName) then
        Exit(Value);
  finally
    Lines.Free;
  end;
end;

{ TTestServer }

constructor TTestServer.Create;
var
  Addr: TInetSockAddr;
  Len: TSockLen;
begin
  FSocket := fpSocket(AF_INET, SOCK_STREAM, 0);
  Addr := LoopbackAddr(0);
  if (fpBind(FSocket, @Addr, SizeOf(Addr)) <> 0) or (fpListen(FSocket, 4) <> 0) then
  begin
    CloseSocket(FSocket);
    FSocket := -1;
    raise Exception.Create('The test server could not listen');
  end;
  Len := SizeOf(Addr);
  fpGetSockName(FSocket, @Addr, @Len);
  FPort := ntohs(Addr.sin_port);
  inherited Create(False);
end;

{ accept does not wake for a socket closed under it, so a connection of
  its own lets the thread see FStopping. A server whose Create failed
  has no thread to wait for. }
destructor TTestServer.Destroy;
var
  S: longint;
  Addr: TInetSockAddr;
begin
  if FSocket >= 0 then
  begin
    FStopping := True;
    S := fpSocket(AF_INET, SOCK_STREAM, 0);
    Addr := LoopbackAddr(FPort);
    fpConnect(S, @Addr, SizeOf(Addr));
    CloseSocket(S);
    WaitFor;
    CloseSocket(FSocket);
  end;
  inherited Destroy;
end;

procedure TTestServer.Execute;
var
  Client: longint;
begin
  repeat
    Client := fpAccept(FSocket, nil, nil);
    if Client < 0 then
      Break;
    if not FStopping then
      Serve(Client);
    CloseSocket(Client);
  until FStopping;
end;

procedure TTestServer.Serve(AClient: longint);
var
  Data, Head, Body, Path, Status, Extra, Answer, Chunk: string;
  Buffer: array[0..4095] of char;
  Got, Ends, Wanted: integer;
begin
  Data := '';
  Ends := 0;
  repeat
    Got := fpRecv(AClient, @Buffer[0], SizeOf(Buffer), 0);
    if Got <= 0 then
      Exit;
    SetString(Chunk, PChar(@Buffer[0]), Got);
    Data := Data + Chunk;
    Ends := Pos(#13#10#13#10, Data);
  until Ends > 0;
  Head := Copy(Data, 1, Ends - 1);
  Body := Copy(Data, Ends + 4, MaxInt);
  Wanted := StrToIntDef(HeaderOf(Head, 'Content-Length'), 0);
  while Length(Body) < Wanted do
  begin
    Got := fpRecv(AClient, @Buffer[0], SizeOf(Buffer), 0);
    if Got <= 0 then
      Exit;
    SetString(Chunk, PChar(@Buffer[0]), Got);
    Body := Body + Chunk;
  end;
  { The request line: METHOD /path HTTP/1.1 }
  Path := Copy(Head, Pos(' ', Head) + 1, MaxInt);
  Path := Copy(Path, 1, Pos(' ', Path) - 1);
  Status := '200 OK';
  Extra := '';
  if Path = '/echo' then
    Body := Copy(Head, 1, Pos(' ', Head) - 1) + #10 + HeaderOf(Head, 'X-Test') +
      #10 + HeaderOf(Head, 'User-Agent') + #10 + Body
  else if Path = '/moved' then
  begin
    Status := '302 Found';
    Extra := 'Location: /echo'#13#10;
    Body := '';
  end
  else if Path = '/slow' then
  begin
    Sleep(SlowMs);
    Body := 'late';
  end
  else
  begin
    Status := '404 Not Found';
    Body := 'nothing here';
  end;
  Answer := 'HTTP/1.1 ' + Status + #13#10 + Extra +
    'Content-Type: text/plain'#13#10 +
    'Content-Length: ' + IntToStr(Length(Body)) + #13#10 +
    'Connection: close'#13#10#13#10 + Body;
  fpSend(AClient, PChar(Answer), Length(Answer), 0);
end;

{ THttpTest }

function THttpTest.Url(const APath: string): string;
begin
  Result := Format('http://127.0.0.1:%d%s', [FServer.Port, APath]);
end;

procedure THttpTest.SetUp;
begin
  FServer := TTestServer.Create;
end;

procedure THttpTest.TearDown;
begin
  FServer.Free;
end;

procedure THttpTest.TestSplitHeader;
var
  Name, Value: string;
begin
  AssertTrue(SplitHeader('Accept: application/json', Name, Value));
  AssertEquals('Accept', Name);
  AssertEquals('application/json', Value);
  AssertTrue('the first colon splits', SplitHeader('X-Time:12:30', Name, Value));
  AssertEquals('12:30', Value);
  AssertTrue('an empty value', SplitHeader('Expect:', Name, Value));
  AssertEquals('', Value);
  AssertFalse('no colon', SplitHeader('Accept', Name, Value));
  AssertFalse('no name', SplitHeader(': value', Name, Value));
end;

procedure THttpTest.TestSplitUrl;
var
  Secure: boolean;
  Host, Path: string;
  Port: integer;
begin
  AssertTrue(SplitUrl('https://api.github.com/repos/slicke/gittan?x=1',
    Secure, Host, Port, Path));
  AssertTrue(Secure);
  AssertEquals('api.github.com', Host);
  AssertEquals(443, Port);
  AssertEquals('/repos/slicke/gittan?x=1', Path);

  AssertTrue(SplitUrl('http://127.0.0.1:8080', Secure, Host, Port, Path));
  AssertFalse(Secure);
  AssertEquals('127.0.0.1', Host);
  AssertEquals(8080, Port);
  AssertEquals('/', Path);

  AssertTrue(SplitUrl('HTTP://example.com?q', Secure, Host, Port, Path));
  AssertEquals(80, Port);
  AssertEquals('example.com', Host);
  AssertEquals('/?q', Path);

  AssertTrue('a slash in the query', SplitUrl('http://h?q=/x', Secure, Host, Port, Path));
  AssertEquals('h', Host);
  AssertEquals('/?q=/x', Path);

  AssertTrue(SplitUrl('https://[::1]:8443/x', Secure, Host, Port, Path));
  AssertEquals('::1', Host);
  AssertEquals(8443, Port);
  AssertEquals('/x', Path);

  AssertTrue('a user is dropped',
    SplitUrl('https://me:secret@example.com/', Secure, Host, Port, Path));
  AssertEquals('example.com', Host);

  AssertFalse('another scheme', SplitUrl('ftp://example.com/', Secure, Host, Port, Path));
  AssertFalse('no scheme', SplitUrl('example.com/', Secure, Host, Port, Path));
  AssertFalse('no host', SplitUrl('https:///x', Secure, Host, Port, Path));
  AssertFalse('a bad port', SplitUrl('http://example.com:99999/', Secure, Host, Port, Path));
end;

procedure THttpTest.TestGet;
var
  R: TGittanHttpResponse;
begin
  R := HttpGet(Url('/echo'), ['X-Test: one']);
  AssertEquals(R.Error, 200, R.Status);
  AssertTrue(HttpOk(R));
  AssertEquals('', HttpFailure(R));
  AssertEquals('GET'#10'one'#10 + HttpUserAgent + #10, R.Body);
end;

procedure THttpTest.TestPost;
var
  R: TGittanHttpResponse;
begin
  R := HttpRequest('post', Url('/echo'), ['Content-Type: application/json'],
    '{"text":"Gr'#$C3#$A5'"}');
  AssertEquals(R.Error, 200, R.Status);
  AssertEquals('POST'#10#10 + HttpUserAgent + #10'{"text":"Gr'#$C3#$A5'"}', R.Body);
end;

procedure THttpTest.TestUserAgent;
var
  R: TGittanHttpResponse;
begin
  R := HttpGet(Url('/echo'), ['User-Agent: Other/1.0']);
  AssertEquals(R.Error, 200, R.Status);
  AssertEquals('GET'#10#10'Other/1.0'#10, R.Body);
end;

procedure THttpTest.TestNotFound;
var
  R: TGittanHttpResponse;
begin
  R := HttpGet(Url('/missing'), []);
  AssertEquals(R.Error, 404, R.Status);
  AssertEquals('the body of an error comes too', 'nothing here', R.Body);
  AssertFalse(HttpOk(R));
  AssertEquals('The server answered 404.', HttpFailure(R));
end;

procedure THttpTest.TestRedirect;
var
  R: TGittanHttpResponse;
begin
  R := HttpGet(Url('/moved'), ['X-Test: two']);
  AssertEquals(R.Error, 200, R.Status);
  AssertEquals('GET', Copy(R.Body, 1, 3));
end;

procedure THttpTest.TestRefused;
var
  R: TGittanHttpResponse;
begin
  R := HttpGet(Format('http://127.0.0.1:%d/', [FreePort]), [], 5);
  AssertEquals(0, R.Status);
  AssertTrue('says why', R.Error <> '');
  AssertEquals(R.Error, HttpFailure(R));
end;

procedure THttpTest.TestTimeout;
var
  R: TGittanHttpResponse;
begin
  R := HttpGet(Url('/slow'), [], 1);
  AssertEquals(0, R.Status);
  AssertTrue('says why', R.Error <> '');
  AssertEquals('', R.Body);
end;

function THttpTest.GiveUp: boolean;
begin
  Result := True;
end;

procedure THttpTest.TestGivenUp;
var
  R: TGittanHttpResponse;
  Started: QWord;
begin
  Started := GetTickCount64;
  R := HttpGet(Url('/slow'), [], 10, @GiveUp);
  AssertEquals(0, R.Status);
  AssertEquals(HttpGivenUp, R.Error);
  AssertEquals('', R.Body);
  AssertTrue('at once, before the answer or the timeout',
    GetTickCount64 - Started < SlowMs);
end;

initialization
  RegisterTest(THttpTest);
end.
