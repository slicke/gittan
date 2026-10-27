unit gittan.openai;

{** A model at an OpenAI-compatible API (TGittanOpenAI, registered with
  gittan.ai as this unit loads): OpenAI's own, OpenRouter, a local
  Ollama, whichever server the settings name, asked with the user's
  key through gittan.http. A request is a chat completion
  (ChatComplete): POST to the server's /chat/completions
  (ChatEndpoint) with the task's prompt as the system message and the
  input as the user's (ChatRequestBody), the answer the first choice's
  message (ParseChatAnswer). The model has no tools, so it sees what
  it is sent alone (TGittanApi). A request is given up when the job
  asking is (ACancel), so a job stopped does not wait for the answer. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, gittan.git, gittan.ai;

const
  {** Where the API is asked when the settings name no server: its
    base, which /chat/completions follows (ChatEndpoint). }
  OpenAIDefaultUrl = 'https://api.openai.com/v1';
  {** Seconds a request may take: a model answers a review of a long
    diff slowly. }
  ChatTimeout = 180;

type
  TGittanOpenAI = class(TGittanApi)
  public
    class function Kind: TGittanAgent; override;
    class function DefaultUrl: string; override;
    {** ChatComplete with the task's prompt, ACancel giving the request
      up. }
    function Ask(const ARoot: string; ATask: TGittanAITask; const AInput: string;
      ACancel: TGittanCancelEvent; out AText, AError: string): boolean; override;
  end;

{** AUrl, the API's base (OpenAIDefaultUrl), with /chat/completions after
  it, a slash at its end dropped. }
function ChatEndpoint(const AUrl: string): string;

{** The body of a chat completion request to AModel: ASystem as the
  system message, AUser as the user's. }
function ChatRequestBody(const AModel, ASystem, AUser: string): string;

{** The answer in ABody, what the API sent back: the first choice's
  message in AText, trimmed, and True; else False with the API's reason
  in AError (its error's message, which counts even beside a choice, or
  that the model answered with no text), empty when ABody is no answer
  of the API at all. }
function ParseChatAnswer(const ABody: string; out AText, AError: string): boolean;

{** Asks AModel at the API whose base is AUrl, with AKey as the bearer
  token when it is not empty (a local server needs none), for ASystem
  and AUser (ChatRequestBody), waiting up to ChatTimeout, or until
  ACancel (asked as it waits, nil for none) says to give the request
  up: the answer in AText, else why none in AError (no answer, the
  API's error, the status). }
function ChatComplete(const AUrl, AKey, AModel, ASystem, AUser: string;
  ACancel: TGittanCancelEvent; out AText, AError: string): boolean;

resourcestring
  rsChatEmpty = 'The model answered with no text.';
  rsChatNotRead = 'The server answered with no completion: %s';

implementation

uses
  fpjson, jsonparser, gittan.http;

function ChatEndpoint(const AUrl: string): string;
begin
  Result := Trim(AUrl);
  while (Result <> '') and (Result[Length(Result)] = '/') do
    SetLength(Result, Length(Result) - 1);
  Result := Result + '/chat/completions';
end;

function ChatRequestBody(const AModel, ASystem, AUser: string): string;
var
  Request: TJSONObject;
  Messages: TJSONArray;
begin
  Request := TJSONObject.Create(['model', AModel]);
  try
    Messages := TJSONArray.Create;
    Request.Add('messages', Messages);
    Messages.Add(TJSONObject.Create(['role', 'system', 'content', ASystem]));
    Messages.Add(TJSONObject.Create(['role', 'user', 'content', AUser]));
    Result := Request.AsJSON;
  finally
    Request.Free;
  end;
end;

function ParseChatAnswer(const ABody: string; out AText, AError: string): boolean;
var
  Data, Node, Part: TJSONData;
  i: integer;
begin
  AText := '';
  AError := '';
  Result := False;
  try
    Data := GetJSON(ABody);
  except
    Exit;
  end;
  if Data = nil then
    Exit;
  try
    if not (Data is TJSONObject) then
      Exit;
    { The error object OpenAI and OpenRouter send; some servers send a
      string. }
    Node := Data.FindPath('error');
    if Node is TJSONObject then
      AError := Trim(TJSONObject(Node).Get('message', ''))
    else if Node is TJSONString then
      AError := Trim(Node.AsString);
    if (AError = '') and (Node <> nil) and not Node.IsNull then
      AError := Node.AsJSON;
    { The content is a string, or parts with text in some APIs. }
    Node := Data.FindPath('choices[0].message.content');
    if Node is TJSONString then
      AText := Node.AsString
    else if Node is TJSONArray then
      for i := 0 to Node.Count - 1 do
      begin
        Part := Node.Items[i];
        if Part is TJSONObject then
          AText := AText + TJSONObject(Part).Get('text', '');
      end;
    AText := Trim(AText);
    { An error beside a choice (OpenRouter sends both at times) is the
      answer. }
    if AError <> '' then
      AText := '';
    Result := AText <> '';
    if not Result and (AError = '') and (Data.FindPath('choices') <> nil) then
      AError := rsChatEmpty;
  finally
    Data.Free;
  end;
end;

function ChatComplete(const AUrl, AKey, AModel, ASystem, AUser: string;
  ACancel: TGittanCancelEvent; out AText, AError: string): boolean;
var
  Headers: TStringArray;
  Response: TGittanHttpResponse;
begin
  AText := '';
  Headers := ['Content-Type: application/json', 'Accept: application/json'];
  if AKey <> '' then
    Headers := Concat(Headers, ['Authorization: Bearer ' + AKey]);
  Response := HttpRequest('POST', ChatEndpoint(AUrl), Headers,
    ChatRequestBody(AModel, ASystem, AUser), ChatTimeout, ACancel);
  if Response.Status = 0 then
  begin
    AError := Response.Error;
    Exit(False);
  end;
  Result := ParseChatAnswer(Response.Body, AText, AError);
  { A 401 says why in its body; a 404 with a page does not. }
  if not Result and (AError = '') then
    if HttpOk(Response) then
      AError := Format(rsChatNotRead, [Copy(Trim(Response.Body), 1, 300)])
    else
      AError := HttpFailure(Response);
end;

{ TGittanOpenAI }

class function TGittanOpenAI.Kind: TGittanAgent;
begin
  Result := gaOpenAI;
end;

class function TGittanOpenAI.DefaultUrl: string;
begin
  Result := OpenAIDefaultUrl;
end;

function TGittanOpenAI.Ask(const ARoot: string; ATask: TGittanAITask;
  const AInput: string; ACancel: TGittanCancelEvent; out AText, AError: string): boolean;
begin
  Result := ChatComplete(Path, Key, Model, Prompt(ATask), AInput, ACancel, AText, AError);
end;

initialization
  RegisterAI(TGittanOpenAI);
end.
