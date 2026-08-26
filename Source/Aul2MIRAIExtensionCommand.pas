unit Aul2MIRAIExtensionCommand;

// AI MIRAI共通の安全確認を保ったまま、MMD固有操作をプロバイダーへ委譲する。

interface

function HandleExtensionRequest(const RequestText, Command: string): string;

implementation

uses
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  AviUtl2PluginCore,
  Aul2MIRAIEditStateReader,
  Aul2MIRAIEditStateTypes,
  Aul2MIRAIExtensionProvider,
  Aul2MIRAIObjectReader,
  Aul2MIRAIObjectTypes,
  Aul2MIRAIParameterPreview,
  Aul2MIRAIParameterWriter,
  Aul2MIRAIProtocol,
  Aul2MIRAISnapshotIdentity,
  Aul2MIRAIView;

type
  TExtensionRequest = record
    StateToken: string;
    TargetIndex: Integer;
    EffectIndex: Integer;
    ExtensionName: string;
    Operation: string;
    PayloadText: string;
    Apply: Boolean;
  end;

const
  MMD_EFFECT_MODEL: string = #$30E2#$30C7#$30EB#$8868#$793A;
  MMD_EFFECT_POSE: string = #$30DD#$30FC#$30BA;
  MMD_ITEM_MODEL_FILE: string =
    #$30E2#$30C7#$30EB#$30D5#$30A1#$30A4#$30EB;
  MMD_ITEM_STANDARD_POSE: string =
    #$6A19#$6E96#$59FF#$52E2#$30C7#$30FC#$30BF;
  MMD_ITEM_POSE: string = #$59FF#$52E2#$30C7#$30FC#$30BF;

function ParseRequest(const Text, Command: string; out Request: TExtensionRequest;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  ApplyValue, Json, Value: TJSONValue;
  Root: TJSONObject;
begin
  Result := False;
  Request := Default(TExtensionRequest);
  ErrorCode := '';
  ErrorMessage := '';
  Json := TJSONObject.ParseJSONValue(Text);
  try
    if not (Json is TJSONObject) then
    begin
      ErrorCode := 'invalid_json';
      ErrorMessage := 'Request must be a JSON object.';
      Exit;
    end;
    Root := TJSONObject(Json);
    Value := Root.GetValue('state_token');
    if not (Value is TJSONString) then
    begin
      ErrorCode := 'invalid_state_token';
      ErrorMessage := 'state_token is required.';
      Exit;
    end;
    Request.StateToken := TJSONString(Value).Value;
    if (Length(Request.StateToken) <> 71) or
       not StartsText('sha256:', Request.StateToken) then
    begin
      ErrorCode := 'invalid_state_token';
      ErrorMessage := 'state_token must be a SHA-256 token.';
      Exit;
    end;
    Value := Root.GetValue('target_index');
    if not (Value is TJSONNumber) or
       not TryStrToInt(Value.Value, Request.TargetIndex) or
       (Request.TargetIndex < 0) then
    begin
      ErrorCode := 'invalid_target';
      ErrorMessage := 'target_index must be zero or greater.';
      Exit;
    end;
    Value := Root.GetValue('effect_index');
    if not (Value is TJSONNumber) or
       not TryStrToInt(Value.Value, Request.EffectIndex) or
       (Request.EffectIndex < 0) then
    begin
      ErrorCode := 'invalid_effect';
      ErrorMessage := 'effect_index must be zero or greater.';
      Exit;
    end;
    Value := Root.GetValue('extension');
    if not (Value is TJSONString) then
    begin
      ErrorCode := 'invalid_extension';
      ErrorMessage := 'extension is required.';
      Exit;
    end;
    Request.ExtensionName := TJSONString(Value).Value;
    Value := Root.GetValue('operation');
    if not (Value is TJSONString) then
    begin
      ErrorCode := 'invalid_operation';
      ErrorMessage := 'operation is required.';
      Exit;
    end;
    Request.Operation := TJSONString(Value).Value;
    Value := Root.GetValue('payload');
    if Value <> nil then
      Request.PayloadText := Value.ToJSON;
    if SameText(Command, AUL2MIRAI_COMMAND_APPLY_EXTENSION) then
    begin
      ApplyValue := Root.GetValue('apply');
      if not (ApplyValue is TJSONBool) or not TJSONBool(ApplyValue).AsBoolean then
      begin
        ErrorCode := 'apply_required';
        ErrorMessage := 'apply must be the JSON Boolean true.';
        Exit;
      end;
      Request.Apply := True;
    end;
    Result := True;
  finally
    Json.Free;
  end;
end;

function FindParameter(const Effect: TAul2MIRAIEffectDetail;
  const Name: string; out Value: string): Boolean;
var
  Parameter: TAul2MIRAIParameterInfo;
begin
  for Parameter in Effect.Parameters do
    if Parameter.Name = Name then
    begin
      Result := not Parameter.Truncated;
      if Result then
        Value := Parameter.Value;
      Exit;
    end;
  Value := '';
  Result := False;
end;

function ResolveMmdTarget(const Snapshot: TAul2MIRAISceneSnapshot;
  const Request: TExtensionRequest; out Effect: TAul2MIRAIEffectDetail;
  out ModelFile, PoseItem, PoseData, ErrorCode, ErrorMessage: string): Boolean;
var
  Item: TAul2MIRAIObjectInfo;
begin
  Result := False;
  ErrorCode := 'target_not_found';
  ErrorMessage := 'The target object does not exist.';
  for Item in Snapshot.Objects do
    if Item.Index = Request.TargetIndex then
    begin
      if not Item.Selected then
      begin
        ErrorCode := 'target_not_selected';
        ErrorMessage := 'The target object is not currently selected.';
        Exit;
      end;
      if Request.EffectIndex > High(Item.EffectDetails) then
      begin
        ErrorCode := 'effect_not_found';
        ErrorMessage := 'The requested effect does not exist.';
        Exit;
      end;
      Effect := Item.EffectDetails[Request.EffectIndex];
      if not SameText(Request.ExtensionName, 'mmd.pose') or
         (not SameText(Effect.Name, MMD_EFFECT_MODEL) and
          not SameText(Effect.Name, MMD_EFFECT_POSE)) then
      begin
        ErrorCode := 'extension_not_supported';
        ErrorMessage := 'The target effect does not support mmd.pose.';
        Exit;
      end;
      if not FindParameter(Effect, MMD_ITEM_MODEL_FILE, ModelFile) or
         (ModelFile = '') then
      begin
        ErrorCode := 'model_file_not_set';
        ErrorMessage := 'The MMD model file is not set or is truncated.';
        Exit;
      end;
      if SameText(Effect.Name, MMD_EFFECT_MODEL) then
        PoseItem := MMD_ITEM_STANDARD_POSE
      else
        PoseItem := MMD_ITEM_POSE;
      if not FindParameter(Effect, PoseItem, PoseData) then
      begin
        ErrorCode := 'pose_data_unavailable';
        ErrorMessage := 'The MMD pose data is missing or truncated.';
        Exit;
      end;
      Result := True;
      Exit;
    end;
end;

function ProviderError(const Command, ProviderText: string): string;
var
  Code, MessageText: string;
  Json: TJSONValue;
begin
  Code := 'extension_error';
  MessageText := 'The MMD provider rejected the request.';
  Json := TJSONObject.ParseJSONValue(ProviderText);
  try
    if Json is TJSONObject then
    begin
      if TJSONObject(Json).GetValue('code') is TJSONString then
        Code := TJSONString(TJSONObject(Json).GetValue('code')).Value;
      if TJSONObject(Json).GetValue('message') is TJSONString then
        MessageText := TJSONString(
          TJSONObject(Json).GetValue('message')).Value;
    end;
  finally
    Json.Free;
  end;
  Result := BuildProtocolError(Command, Code, MessageText);
end;

function BuildProviderRequest(const Operation, ModelFile, PoseData,
  PayloadText: string): string;
var
  Payload: TJSONValue;
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('operation', Operation);
    Root.AddPair('model_file', ModelFile);
    if PoseData <> '' then
      Root.AddPair('current_pose', PoseData);
    if PayloadText <> '' then
    begin
      Payload := TJSONObject.ParseJSONValue(PayloadText);
      if Payload = nil then
        raise EArgumentException.Create('payload is invalid JSON.');
      Root.AddPair('payload', Payload);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

procedure AddHeader(Root: TJSONObject; const Command: string;
  const Identity: TAul2MIRAISnapshotIdentity);
begin
  Root.AddPair('protocol', AUL2MIRAI_PROTOCOL_NAME);
  Root.AddPair('protocol_version', TJSONNumber.Create(
    AUL2MIRAI_PROTOCOL_VERSION));
  Root.AddPair('snapshot_id', Identity.SnapshotId);
  Root.AddPair('state_token', Identity.StateToken);
  Root.AddPair('captured_at_utc', Identity.CapturedAtUtc);
  Root.AddPair('status', 'ok');
  Root.AddPair('command', Command);
end;

function BuildResponse(const Command: string;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity;
  const Request: TExtensionRequest; const ProviderText: string;
  const Preview: TAul2MIRAIParameterPreview; Applied: Boolean;
  const VerifiedValue: string): string;
var
  ExtensionResult: TJSONValue;
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root, Command, AfterIdentity);
    Root.AddPair('previous_state_token', BeforeIdentity.StateToken);
    Root.AddPair('target_index', TJSONNumber.Create(Request.TargetIndex));
    Root.AddPair('effect_index', TJSONNumber.Create(Request.EffectIndex));
    Root.AddPair('extension', Request.ExtensionName);
    Root.AddPair('operation', Request.Operation);
    Root.AddPair('applied', TJSONBool.Create(Applied));
    if Preview.ItemName <> '' then
    begin
      Root.AddPair('will_change', TJSONBool.Create(Preview.WillChange));
      Root.AddPair('pose_item', Preview.ItemName);
      Root.AddPair('before', Preview.BeforeValue);
      Root.AddPair('verified', VerifiedValue);
    end;
    ExtensionResult := TJSONObject.ParseJSONValue(ProviderText);
    if ExtensionResult = nil then
      raise EArgumentException.Create('Provider response is invalid JSON.');
    Root.AddPair('result', ExtensionResult);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function ProviderSucceeded(const Text: string; out PoseData: string): Boolean;
var
  Json: TJSONValue;
begin
  Result := False;
  PoseData := '';
  Json := TJSONObject.ParseJSONValue(Text);
  try
    if not (Json is TJSONObject) or
       not (TJSONObject(Json).GetValue('status') is TJSONString) or
       not SameText(TJSONString(
         TJSONObject(Json).GetValue('status')).Value, 'ok') then
      Exit;
    if TJSONObject(Json).GetValue('pose_data') is TJSONString then
      PoseData := TJSONString(
        TJSONObject(Json).GetValue('pose_data')).Value;
    Result := True;
  finally
    Json.Free;
  end;
end;

function HandleExtensionRequest(const RequestText, Command: string): string;
var
  AfterState, State: TAul2MIRAIEditState;
  AfterIdentity, Identity: TAul2MIRAISnapshotIdentity;
  AfterSnapshot, Snapshot: TAul2MIRAISceneSnapshot;
  Effect: TAul2MIRAIEffectDetail;
  ErrorCode, ErrorMessage, ModelFile, PoseData, PoseItem: string;
  ProviderOperation, ProviderRequest, ProviderResponse: string;
  Preview: TAul2MIRAIParameterPreview;
  Request: TExtensionRequest;
  VerifiedValue: string;
begin
  if not ParseRequest(RequestText, Command, Request, ErrorCode,
    ErrorMessage) then
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  if not ReadCurrentEditState(EditHandle, State, ErrorMessage) or
     not ReadCurrentSceneObjects(EditHandle, Snapshot, ErrorMessage, True) then
    Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
  Identity := CreateSnapshotIdentity(State, Snapshot);
  if not SameText(Request.StateToken, Identity.StateToken) then
    Exit(BuildStateChangedError(Command, Request.StateToken, Identity));
  if not ResolveMmdTarget(Snapshot, Request, Effect, ModelFile, PoseItem,
    PoseData, ErrorCode, ErrorMessage) then
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  if SameText(Command, AUL2MIRAI_COMMAND_QUERY_EXTENSION) and
     SameText(Request.Operation, 'get_model_schema') then
    ProviderOperation := 'get_model_schema'
  else if (SameText(Command, AUL2MIRAI_COMMAND_PREVIEW_EXTENSION) or
           SameText(Command, AUL2MIRAI_COMMAND_APPLY_EXTENSION)) and
          SameText(Request.Operation, 'set_pose') then
    ProviderOperation := 'preview_pose'
  else
    Exit(BuildProtocolError(Command, 'unsupported_operation',
      'The requested extension operation is not supported.'));
  ProviderRequest := BuildProviderRequest(ProviderOperation, ModelFile,
    PoseData, Request.PayloadText);
  if not InvokeMmdExtensionProvider(ProviderRequest, ProviderResponse,
    ErrorCode, ErrorMessage) then
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  if not ProviderSucceeded(ProviderResponse, PoseData) then
    Exit(ProviderError(Command, ProviderResponse));
  Preview := Default(TAul2MIRAIParameterPreview);
  if SameText(Command, AUL2MIRAI_COMMAND_QUERY_EXTENSION) then
    Exit(BuildResponse(Command, Identity, Identity, Request,
      ProviderResponse, Preview, False, ''));
  if not CreateParameterPreview(Snapshot, Request.TargetIndex,
    Request.EffectIndex, PoseItem, PoseData, Preview, ErrorCode,
    ErrorMessage) then
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  if SameText(Command, AUL2MIRAI_COMMAND_PREVIEW_EXTENSION) then
    Exit(BuildResponse(Command, Identity, Identity, Request,
      ProviderResponse, Preview, False, Preview.BeforeValue));
  if Preview.WillChange and not ApplyParameterChange(EditHandle, Preview,
    VerifiedValue, ErrorCode, ErrorMessage) then
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  if not Preview.WillChange then
    VerifiedValue := Preview.BeforeValue;
  if not ReadCurrentEditState(EditHandle, AfterState, ErrorMessage) or
     not ReadCurrentSceneObjects(EditHandle, AfterSnapshot, ErrorMessage) then
    Exit(BuildProtocolError(Command, 'post_write_read_failed', ErrorMessage));
  AfterIdentity := CreateSnapshotIdentity(AfterState, AfterSnapshot);
  QueueMIRAIViewUpdate('MMD pose extension applied', '', 'OK',
    Format('%s -> object %d', [Command, Request.TargetIndex]));
  Result := BuildResponse(Command, Identity, AfterIdentity, Request,
    ProviderResponse, Preview, Preview.WillChange, VerifiedValue);
end;

end.
