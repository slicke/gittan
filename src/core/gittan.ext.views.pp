unit gittan.ext.views;

{** What an extension's tab of the forge view and an operation of the
  Batch tab answer (Gittan.forgeTabs.register, Gittan.batch.register),
  read from the JSON the engine delivers ({"value": ...} or
  {"error": "..."}, gittan.ext.engine's shim): a tab's model, its text
  and its rows with their actions, and a repository's result of an
  operation. Plain functions, no LCL, so the tests read them as the
  pages do (gittan.extpage, gittan.batchpage). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson;

type
  {** How a row or a result reads: plain, fine, worth a look, failed. }
  TExtSeverity = (esInfo, esOk, esWarn, esError);

  TExtRowAction = record
    Id, Title: string;
  end;
  TExtRowActions = array of TExtRowAction;

  {** A row of a tab: a title, opening Url in the browser or the
    repository at Repo when either is given; a detail under it, a tag at
    its right, its actions as pills; Json is the row as the extension
    gave it, which an action gets back. }
  TExtTabRow = record
    Title, Detail, Tag, Url, Repo: string;
    Severity: TExtSeverity;
    Actions: TExtRowActions;
    Json: string;
  end;
  TExtTabRows = array of TExtTabRow;

  {** A tab's model: a paragraph over the rows, the rows, and what to say
    when there are none. }
  TExtTabModel = record
    Text, Empty: string;
    Rows: TExtTabRows;
  end;

  {** What an operation said of one repository: nothing (Said false),
    or a text, a line each, in a severity, with a link. }
  TExtBatchResult = record
    Said: boolean;
    Text, Url: string;
    Severity: TExtSeverity;
  end;

{** "warn", "warning", "error", "ok" and "success"; anything else is
  info. }
function ParseExtSeverity(const AName: string): TExtSeverity;

{** Reads a delivered answer: True with its value (owned by the caller,
  a TJSONNull for null) or False with the error in AError. }
function ReadExtAnswer(const AJson: string; out AValue: TJSONData; out AError: string): boolean;

{** A tab's model from a value: {text, empty, rows: [{title, detail, tag,
  url, repo, severity, actions: [{id, title}]}]}, or a list of rows
  alone, or a string as its text; False when the value has no model
  (null, a number), as an action's answer that asks for a render. }
function ExtTabModelOf(AValue: TJSONData; out AModel: TExtTabModel): boolean;

{** An operation's result from a value: null or an empty string says
  nothing, a string is the text, {text, severity, url} the rest. }
function ExtBatchResultOf(AValue: TJSONData): TExtBatchResult;

implementation

function ParseExtSeverity(const AName: string): TExtSeverity;
begin
  case LowerCase(Trim(AName)) of
    'warn', 'warning': Result := esWarn;
    'error', 'fail', 'failed': Result := esError;
    'ok', 'success', 'done': Result := esOk;
    else
      Result := esInfo;
  end;
end;

function ReadExtAnswer(const AJson: string; out AValue: TJSONData; out AError: string): boolean;
var
  Data: TJSONData;
  O: TJSONObject;
begin
  AValue := nil;
  AError := '';
  try
    Data := GetJSON(AJson);
  except
    AError := 'The extension''s answer could not be read';
    Exit(False);
  end;
  try
    if not (Data is TJSONObject) then
    begin
      AError := 'The extension''s answer could not be read';
      Exit(False);
    end;
    O := TJSONObject(Data);
    if O.Find('error') <> nil then
    begin
      AError := O.Get('error', '');
      if AError = '' then
        AError := 'The extension failed';
      Exit(False);
    end;
    if O.Find('value') <> nil then
      AValue := O.Extract('value')
    else
      AValue := TJSONNull.Create;
    Result := True;
  finally
    Data.Free;
  end;
end;

{ A field as text: a string as it is, a number or a boolean as JSON
  gives it, nothing for null, an object or a list. }
function TextOf(AObject: TJSONObject; const AName: string): string;
var
  D: TJSONData;
begin
  D := AObject.Find(AName);
  if (D = nil) or (D.JSONType in [jtNull, jtObject, jtArray]) then
    Result := ''
  else
    Result := D.AsString;
end;

function RowOf(AData: TJSONData; out ARow: TExtTabRow): boolean;
var
  O, A: TJSONObject;
  Acts: TJSONArray;
  i, n: integer;
begin
  ARow := Default(TExtTabRow);
  if AData is TJSONString then
  begin
    ARow.Title := AData.AsString;
    ARow.Json := AData.AsJSON;
    Exit(ARow.Title <> '');
  end;
  if not (AData is TJSONObject) then
    Exit(False);
  O := TJSONObject(AData);
  ARow.Title := TextOf(O, 'title');
  ARow.Detail := TextOf(O, 'detail');
  ARow.Tag := TextOf(O, 'tag');
  ARow.Url := TextOf(O, 'url');
  ARow.Repo := TextOf(O, 'repo');
  ARow.Severity := ParseExtSeverity(TextOf(O, 'severity'));
  ARow.Json := O.AsJSON;
  if O.Find('actions') is TJSONArray then
  begin
    Acts := TJSONArray(O.Find('actions'));
    n := 0;
    for i := 0 to Acts.Count - 1 do
      if Acts[i] is TJSONObject then
      begin
        A := TJSONObject(Acts[i]);
        if TextOf(A, 'id') = '' then
          Continue;
        SetLength(ARow.Actions, n + 1);
        ARow.Actions[n].Id := TextOf(A, 'id');
        ARow.Actions[n].Title := TextOf(A, 'title');
        if ARow.Actions[n].Title = '' then
          ARow.Actions[n].Title := ARow.Actions[n].Id;
        Inc(n);
      end;
  end;
  Result := (ARow.Title <> '') or (ARow.Detail <> '');
end;

function ExtTabModelOf(AValue: TJSONData; out AModel: TExtTabModel): boolean;
var
  Rows: TJSONArray;
  Row: TExtTabRow;
  i, n: integer;
begin
  AModel := Default(TExtTabModel);
  Rows := nil;
  if AValue is TJSONString then
  begin
    AModel.Text := AValue.AsString;
    Exit(True);
  end
  else if AValue is TJSONArray then
    Rows := TJSONArray(AValue)
  else if AValue is TJSONObject then
  begin
    AModel.Text := TextOf(TJSONObject(AValue), 'text');
    AModel.Empty := TextOf(TJSONObject(AValue), 'empty');
    if TJSONObject(AValue).Find('rows') is TJSONArray then
      Rows := TJSONArray(TJSONObject(AValue).Find('rows'))
    else if (AModel.Text = '') and (AModel.Empty = '') then
      Exit(False);
  end
  else
    Exit(False);
  if Rows <> nil then
  begin
    n := 0;
    for i := 0 to Rows.Count - 1 do
      if RowOf(Rows[i], Row) then
      begin
        SetLength(AModel.Rows, n + 1);
        AModel.Rows[n] := Row;
        Inc(n);
      end;
  end;
  Result := True;
end;

function ExtBatchResultOf(AValue: TJSONData): TExtBatchResult;
var
  O: TJSONObject;
begin
  Result := Default(TExtBatchResult);
  if (AValue = nil) or (AValue.JSONType = jtNull) then
    Exit;
  if AValue is TJSONObject then
  begin
    O := TJSONObject(AValue);
    Result.Text := TextOf(O, 'text');
    Result.Url := TextOf(O, 'url');
    Result.Severity := ParseExtSeverity(TextOf(O, 'severity'));
  end
  else if AValue.JSONType in [jtString, jtNumber, jtBoolean] then
    Result.Text := AValue.AsString;
  Result.Text := Trim(Result.Text);
  Result.Said := (Result.Text <> '') or (Result.Url <> '');
end;

end.
