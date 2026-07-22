unit Aul2MIRAIEditPosition;

// Parses, validates, and formats cursor and selection range changes without
// accessing AviUtl2 SDK handles.

interface

uses
  Aul2MIRAIEditStateTypes,
  Aul2MIRAISnapshotIdentity;

type
  TAul2MIRAIEditPositionPreview = record
    SetCursor          : Boolean;
    SetSelection       : Boolean;
    BeforeCursorLayer  : Integer;
    BeforeCursorFrame  : Integer;
    AfterCursorLayer   : Integer;
    AfterCursorFrame   : Integer;
    BeforeSelectStart  : Integer;
    BeforeSelectEnd    : Integer;
    AfterSelectStart   : Integer;
    AfterSelectEnd     : Integer;
    CursorWillChange   : Boolean;
    SelectionWillChange: Boolean;
  end;

function ParseEditPositionRequest(const RequestText: string;
  RequireApply: Boolean; out StateToken: string; out SetCursor: Boolean;
  out CursorLayer, CursorFrame: Integer; out SetSelection: Boolean;
  out SelectStart, SelectEnd: Integer; out ErrorCode,
  ErrorMessage: string): Boolean;
function CreateEditPositionPreview(const State: TAul2MIRAIEditState;
  SetCursor: Boolean; CursorLayer, CursorFrame: Integer;
  SetSelection: Boolean; SelectStart, SelectEnd: Integer;
  out Preview: TAul2MIRAIEditPositionPreview; out ErrorCode,
  ErrorMessage: string): Boolean;
function BuildEditPositionPreviewResponse(
  const Preview: TAul2MIRAIEditPositionPreview;
  const Identity: TAul2MIRAISnapshotIdentity): string;
function BuildEditPositionResponse(
  const Preview: TAul2MIRAIEditPositionPreview;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity): string;

implementation

uses
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  Aul2MIRAIProtocol;

function RequireInteger(Root: TJSONObject; const Name: string;
  out Value: Integer; out ErrorCode, ErrorMessage: string): Boolean;
var
  JsonValue: TJSONValue;
begin
  JsonValue := Root.GetValue(Name);
  Result := (JsonValue is TJSONNumber) and
    TryStrToInt(JsonValue.Value, Value);
  if not Result then
  begin
    Value := -1;
    ErrorCode := 'invalid_' + Name;
    ErrorMessage := Name + ' must be an integer.';
  end;
end;

function ParseEditPositionRequest(const RequestText: string;
  RequireApply: Boolean; out StateToken: string; out SetCursor: Boolean;
  out CursorLayer, CursorFrame: Integer; out SetSelection: Boolean;
  out SelectStart, SelectEnd: Integer; out ErrorCode,
  ErrorMessage: string): Boolean;
var
  ApplyValue   : TJSONValue;
  CursorValue  : TJSONValue;
  Json         : TJSONValue;
  Root         : TJSONObject;
  SelectionValue: TJSONValue;
  TokenValue   : TJSONValue;
begin
  Result := False;
  StateToken := '';
  SetCursor := False;
  CursorLayer := -1;
  CursorFrame := -1;
  SetSelection := False;
  SelectStart := -1;
  SelectEnd := -1;
  ErrorCode := '';
  ErrorMessage := '';
  Json := TJSONObject.ParseJSONValue(RequestText);
  try
    if not (Json is TJSONObject) then
    begin
      ErrorCode := 'invalid_json';
      ErrorMessage := 'Request must be a JSON object.';
      Exit;
    end;
    Root := TJSONObject(Json);
    TokenValue := Root.GetValue('state_token');
    if not (TokenValue is TJSONString) then
    begin
      ErrorCode := 'invalid_state_token';
      ErrorMessage := 'state_token must be a string.';
      Exit;
    end;
    StateToken := TJSONString(TokenValue).Value;
    if (Length(StateToken) <> 71) or
       not StartsText('sha256:', StateToken) then
    begin
      ErrorCode := 'invalid_state_token';
      ErrorMessage := 'state_token must be a SHA-256 token.';
      Exit;
    end;

    CursorValue := Root.GetValue('cursor');
    if CursorValue <> nil then
    begin
      if not (CursorValue is TJSONObject) then
      begin
        ErrorCode := 'invalid_cursor';
        ErrorMessage := 'cursor must be an object.';
        Exit;
      end;
      SetCursor := True;
      if not RequireInteger(TJSONObject(CursorValue), 'layer', CursorLayer,
        ErrorCode, ErrorMessage) or
         not RequireInteger(TJSONObject(CursorValue), 'frame', CursorFrame,
        ErrorCode, ErrorMessage) then
      begin
        ErrorMessage := 'cursor: ' + ErrorMessage;
        Exit;
      end;
    end;

    SelectionValue := Root.GetValue('selection');
    if SelectionValue <> nil then
    begin
      SetSelection := True;
      if SelectionValue is TJSONNull then
      begin
        SelectStart := -1;
        SelectEnd := -1;
      end
      else if SelectionValue is TJSONObject then
      begin
        if not RequireInteger(TJSONObject(SelectionValue), 'start_frame',
          SelectStart, ErrorCode, ErrorMessage) or
           not RequireInteger(TJSONObject(SelectionValue), 'end_frame',
          SelectEnd, ErrorCode, ErrorMessage) then
        begin
          ErrorMessage := 'selection: ' + ErrorMessage;
          Exit;
        end;
      end
      else
      begin
        ErrorCode := 'invalid_selection';
        ErrorMessage := 'selection must be an object or null.';
        Exit;
      end;
    end;
    if not SetCursor and not SetSelection then
    begin
      ErrorCode := 'empty_position_change';
      ErrorMessage := 'cursor or selection is required.';
      Exit;
    end;

    if RequireApply then
    begin
      ApplyValue := Root.GetValue('apply');
      if not (ApplyValue is TJSONBool) then
      begin
        ErrorCode := 'invalid_apply';
        ErrorMessage := 'apply must be a boolean.';
        Exit;
      end;
      if not TJSONBool(ApplyValue).AsBoolean then
      begin
        ErrorCode := 'apply_required';
        ErrorMessage := 'apply must be true to change the edit position.';
        Exit;
      end;
    end;
    Result := True;
  finally
    Json.Free;
  end;
end;

function CreateEditPositionPreview(const State: TAul2MIRAIEditState;
  SetCursor: Boolean; CursorLayer, CursorFrame: Integer;
  SetSelection: Boolean; SelectStart, SelectEnd: Integer;
  out Preview: TAul2MIRAIEditPositionPreview; out ErrorCode,
  ErrorMessage: string): Boolean;
var
  MaxLayer: Integer;
begin
  Result := False;
  Preview := Default(TAul2MIRAIEditPositionPreview);
  ErrorCode := '';
  ErrorMessage := '';
  MaxLayer := State.LayerMax;
  if MaxLayer < 0 then
    MaxLayer := 0;
  if SetCursor and ((CursorLayer < 0) or (CursorLayer > MaxLayer)) then
  begin
    ErrorCode := 'invalid_cursor_layer';
    ErrorMessage := 'cursor.layer is outside the current scene range.';
    Exit;
  end;
  if SetCursor and ((CursorFrame < 0) or
     (CursorFrame > State.FrameMax)) then
  begin
    ErrorCode := 'invalid_cursor_frame';
    ErrorMessage := 'cursor.frame is outside the current scene range.';
    Exit;
  end;
  if SetSelection and not ((SelectStart = -1) and (SelectEnd = -1)) then
  begin
    if (SelectStart < 0) or (SelectEnd < SelectStart) or
       (SelectEnd > State.FrameMax) then
    begin
      ErrorCode := 'invalid_selection_range';
      ErrorMessage := 'selection range is outside the current scene range.';
      Exit;
    end;
  end;

  Preview.SetCursor := SetCursor;
  Preview.SetSelection := SetSelection;
  Preview.BeforeCursorLayer := State.CursorLayer;
  Preview.BeforeCursorFrame := State.CursorFrame;
  Preview.BeforeSelectStart := State.SelectRangeStart;
  Preview.BeforeSelectEnd := State.SelectRangeEnd;
  if SetCursor then
  begin
    Preview.AfterCursorLayer := CursorLayer;
    Preview.AfterCursorFrame := CursorFrame;
  end
  else
  begin
    Preview.AfterCursorLayer := State.CursorLayer;
    Preview.AfterCursorFrame := State.CursorFrame;
  end;
  if SetSelection then
  begin
    Preview.AfterSelectStart := SelectStart;
    Preview.AfterSelectEnd := SelectEnd;
  end
  else
  begin
    Preview.AfterSelectStart := State.SelectRangeStart;
    Preview.AfterSelectEnd := State.SelectRangeEnd;
  end;
  Preview.CursorWillChange := SetCursor and
    ((Preview.BeforeCursorLayer <> Preview.AfterCursorLayer) or
     (Preview.BeforeCursorFrame <> Preview.AfterCursorFrame));
  Preview.SelectionWillChange := SetSelection and
    ((Preview.BeforeSelectStart <> Preview.AfterSelectStart) or
     (Preview.BeforeSelectEnd <> Preview.AfterSelectEnd));
  Result := True;
end;

procedure AddHeader(Root: TJSONObject;
  const Identity: TAul2MIRAISnapshotIdentity; const Command: string);
begin
  Root.AddPair('protocol', AUL2MIRAI_PROTOCOL_NAME);
  Root.AddPair('protocol_version',
    TJSONNumber.Create(AUL2MIRAI_PROTOCOL_VERSION));
  Root.AddPair('snapshot_id', Identity.SnapshotId);
  Root.AddPair('state_token', Identity.StateToken);
  Root.AddPair('captured_at_utc', Identity.CapturedAtUtc);
  Root.AddPair('status', 'ok');
  Root.AddPair('command', Command);
end;

function BuildPositionJson(const Preview: TAul2MIRAIEditPositionPreview;
  IncludeResult: Boolean): TJSONObject;
var
  CursorJson   : TJSONObject;
  SelectionJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('operation', 'set_edit_position');
  Result.AddPair('will_change', TJSONBool.Create(
    Preview.CursorWillChange or Preview.SelectionWillChange));
  CursorJson := TJSONObject.Create;
  Result.AddPair('cursor', CursorJson);
  CursorJson.AddPair('requested', TJSONBool.Create(Preview.SetCursor));
  CursorJson.AddPair('will_change',
    TJSONBool.Create(Preview.CursorWillChange));
  CursorJson.AddPair('before_layer',
    TJSONNumber.Create(Preview.BeforeCursorLayer));
  CursorJson.AddPair('before_frame',
    TJSONNumber.Create(Preview.BeforeCursorFrame));
  CursorJson.AddPair('after_layer',
    TJSONNumber.Create(Preview.AfterCursorLayer));
  CursorJson.AddPair('after_frame',
    TJSONNumber.Create(Preview.AfterCursorFrame));
  SelectionJson := TJSONObject.Create;
  Result.AddPair('selection', SelectionJson);
  SelectionJson.AddPair('requested',
    TJSONBool.Create(Preview.SetSelection));
  SelectionJson.AddPair('will_change',
    TJSONBool.Create(Preview.SelectionWillChange));
  SelectionJson.AddPair('before_start_frame',
    TJSONNumber.Create(Preview.BeforeSelectStart));
  SelectionJson.AddPair('before_end_frame',
    TJSONNumber.Create(Preview.BeforeSelectEnd));
  SelectionJson.AddPair('after_start_frame',
    TJSONNumber.Create(Preview.AfterSelectStart));
  SelectionJson.AddPair('after_end_frame',
    TJSONNumber.Create(Preview.AfterSelectEnd));
  if IncludeResult then
    Result.AddPair('applied', TJSONBool.Create(
      Preview.CursorWillChange or Preview.SelectionWillChange));
end;

function BuildEditPositionPreviewResponse(
  const Preview: TAul2MIRAIEditPositionPreview;
  const Identity: TAul2MIRAISnapshotIdentity): string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root, Identity, AUL2MIRAI_COMMAND_PREVIEW_EDIT_POSITION);
    Root.AddPair('preview', BuildPositionJson(Preview, False));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function BuildEditPositionResponse(
  const Preview: TAul2MIRAIEditPositionPreview;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity): string;
var
  ChangeJson: TJSONObject;
  Root      : TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root, AfterIdentity, AUL2MIRAI_COMMAND_SET_EDIT_POSITION);
    ChangeJson := BuildPositionJson(Preview, True);
    ChangeJson.AddPair('previous_state_token', BeforeIdentity.StateToken);
    Root.AddPair('change', ChangeJson);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

end.
