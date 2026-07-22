unit Aul2MIRAIParameterBatch;

// Parses, validates, and formats atomic multi-parameter operations without
// accessing AviUtl2 SDK handles.

interface

uses
  Aul2MIRAIObjectTypes,
  Aul2MIRAIParameterPreview,
  Aul2MIRAISnapshotIdentity;

type
  TAul2MIRAIParameterChangeRequest = record
    TargetIndex : Integer;
    EffectIndex : Integer;
    ItemName    : string;
    NewValue    : string;
  end;

function ParseParameterBatchRequest(const RequestText: string;
  RequireApply: Boolean; out StateToken: string;
  out Changes: TArray<TAul2MIRAIParameterChangeRequest>;
  out ErrorCode, ErrorMessage: string): Boolean;
function CreateParameterPreviews(const Snapshot: TAul2MIRAISceneSnapshot;
  const Changes: TArray<TAul2MIRAIParameterChangeRequest>;
  out Previews: TArray<TAul2MIRAIParameterPreview>;
  out ErrorCode, ErrorMessage: string): Boolean;
function BuildParameterBatchPreviewResponse(
  const Previews: TArray<TAul2MIRAIParameterPreview>;
  const Identity: TAul2MIRAISnapshotIdentity): string;
function BuildParameterBatchSetResponse(
  const Previews: TArray<TAul2MIRAIParameterPreview>;
  const VerifiedValues: TArray<string>;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity): string;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  Aul2MIRAIProtocol;

const
  MAX_BATCH_CHANGES = 64;

function RequireString(Root: TJSONObject; const Name: string;
  out Value, ErrorCode, ErrorMessage: string): Boolean;
var
  JsonValue: TJSONValue;
begin
  JsonValue := Root.GetValue(Name);
  Result := JsonValue is TJSONString;
  if Result then
    Value := TJSONString(JsonValue).Value
  else
  begin
    Value := '';
    ErrorCode := 'invalid_' + Name;
    ErrorMessage := Name + ' must be a string.';
  end;
end;

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

function ParseParameterBatchRequest(const RequestText: string;
  RequireApply: Boolean; out StateToken: string;
  out Changes: TArray<TAul2MIRAIParameterChangeRequest>;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  ApplyValue : TJSONValue;
  ChangeJson : TJSONValue;
  ChangesJson: TJSONArray;
  I          : Integer;
  Json       : TJSONValue;
  Root       : TJSONObject;
begin
  Result := False;
  StateToken := '';
  SetLength(Changes, 0);
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
    if not RequireString(Root, 'state_token', StateToken,
      ErrorCode, ErrorMessage) then
      Exit;
    if (Length(StateToken) <> 71) or
       not StartsText('sha256:', StateToken) then
    begin
      ErrorCode := 'invalid_state_token';
      ErrorMessage := 'state_token must be a SHA-256 token.';
      Exit;
    end;

    ChangeJson := Root.GetValue('changes');
    if not (ChangeJson is TJSONArray) then
    begin
      ErrorCode := 'invalid_changes';
      ErrorMessage := 'changes must be an array.';
      Exit;
    end;
    ChangesJson := TJSONArray(ChangeJson);
    if ChangesJson.Count = 0 then
    begin
      ErrorCode := 'empty_changes';
      ErrorMessage := 'At least one change is required.';
      Exit;
    end;
    if ChangesJson.Count > MAX_BATCH_CHANGES then
    begin
      ErrorCode := 'too_many_changes';
      ErrorMessage := Format('changes exceeds the %d item limit.',
        [MAX_BATCH_CHANGES]);
      Exit;
    end;

    SetLength(Changes, ChangesJson.Count);
    for I := 0 to ChangesJson.Count - 1 do
    begin
      ChangeJson := ChangesJson.Items[I];
      if not (ChangeJson is TJSONObject) then
      begin
        ErrorCode := 'invalid_change';
        ErrorMessage := Format('changes[%d] must be an object.', [I]);
        Exit;
      end;
      if not RequireInteger(TJSONObject(ChangeJson), 'target_index',
        Changes[I].TargetIndex, ErrorCode, ErrorMessage) then
      begin
        ErrorMessage := Format('changes[%d]: %s', [I, ErrorMessage]);
        Exit;
      end;
      if not RequireInteger(TJSONObject(ChangeJson), 'effect_index',
        Changes[I].EffectIndex, ErrorCode, ErrorMessage) then
      begin
        ErrorMessage := Format('changes[%d]: %s', [I, ErrorMessage]);
        Exit;
      end;
      if not RequireString(TJSONObject(ChangeJson), 'item',
        Changes[I].ItemName, ErrorCode, ErrorMessage) then
      begin
        ErrorMessage := Format('changes[%d]: %s', [I, ErrorMessage]);
        Exit;
      end;
      if not RequireString(TJSONObject(ChangeJson), 'value',
        Changes[I].NewValue, ErrorCode, ErrorMessage) then
      begin
        ErrorMessage := Format('changes[%d]: %s', [I, ErrorMessage]);
        Exit;
      end;
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
        ErrorMessage := 'apply must be true to perform an edit.';
        Exit;
      end;
    end;
    Result := True;
  finally
    Json.Free;
  end;
end;

function CreateParameterPreviews(const Snapshot: TAul2MIRAISceneSnapshot;
  const Changes: TArray<TAul2MIRAIParameterChangeRequest>;
  out Previews: TArray<TAul2MIRAIParameterPreview>;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  I: Integer;
  J: Integer;
begin
  Result := False;
  SetLength(Previews, 0);
  ErrorCode := '';
  ErrorMessage := '';
  SetLength(Previews, Length(Changes));
  for I := 0 to High(Changes) do
  begin
    for J := 0 to I - 1 do
      if (Changes[J].TargetIndex = Changes[I].TargetIndex) and
         (Changes[J].EffectIndex = Changes[I].EffectIndex) and
         SameText(Changes[J].ItemName, Changes[I].ItemName) then
      begin
        ErrorCode := 'duplicate_change';
        ErrorMessage := Format(
          'changes[%d] duplicates the target item in changes[%d].', [I, J]);
        Exit;
      end;
    if not CreateParameterPreview(Snapshot, Changes[I].TargetIndex,
      Changes[I].EffectIndex, Changes[I].ItemName, Changes[I].NewValue,
      Previews[I], ErrorCode, ErrorMessage) then
    begin
      ErrorMessage := Format('changes[%d]: %s', [I, ErrorMessage]);
      Exit;
    end;
  end;
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

function CountChanged(
  const Previews: TArray<TAul2MIRAIParameterPreview>): Integer;
var
  Preview: TAul2MIRAIParameterPreview;
begin
  Result := 0;
  for Preview in Previews do
    if Preview.WillChange then
      Inc(Result);
end;

function BuildChangeJson(const Preview: TAul2MIRAIParameterPreview;
  IncludeResult: Boolean; const VerifiedValue: string): TJSONObject;
var
  EffectJson: TJSONObject;
  TargetJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  TargetJson := TJSONObject.Create;
  Result.AddPair('target', TargetJson);
  TargetJson.AddPair('index', TJSONNumber.Create(Preview.TargetIndex));
  TargetJson.AddPair('layer', TJSONNumber.Create(Preview.Layer));
  TargetJson.AddPair('start_frame', TJSONNumber.Create(Preview.StartFrame));
  TargetJson.AddPair('end_frame', TJSONNumber.Create(Preview.EndFrame));
  TargetJson.AddPair('object_type', Preview.ObjectType);
  TargetJson.AddPair('primary_effect', Preview.PrimaryEffect);
  EffectJson := TJSONObject.Create;
  Result.AddPair('effect', EffectJson);
  EffectJson.AddPair('index', TJSONNumber.Create(Preview.EffectIndex));
  EffectJson.AddPair('name', Preview.EffectName);
  Result.AddPair('item', Preview.ItemName);
  Result.AddPair('before', Preview.BeforeValue);
  Result.AddPair('requested', Preview.AfterValue);
  Result.AddPair('will_change', TJSONBool.Create(Preview.WillChange));
  if IncludeResult then
  begin
    Result.AddPair('applied', TJSONBool.Create(Preview.WillChange));
    Result.AddPair('verified', VerifiedValue);
  end;
end;

function BuildParameterBatchPreviewResponse(
  const Previews: TArray<TAul2MIRAIParameterPreview>;
  const Identity: TAul2MIRAISnapshotIdentity): string;
var
  ChangeJson : TJSONObject;
  ChangesJson: TJSONArray;
  I          : Integer;
  PreviewJson: TJSONObject;
  Root       : TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root, Identity, AUL2MIRAI_COMMAND_PREVIEW_PARAMETERS);
    PreviewJson := TJSONObject.Create;
    Root.AddPair('preview', PreviewJson);
    PreviewJson.AddPair('operation', 'set_object_parameters');
    PreviewJson.AddPair('applied', TJSONBool.Create(False));
    PreviewJson.AddPair('change_count',
      TJSONNumber.Create(Length(Previews)));
    PreviewJson.AddPair('changed_count',
      TJSONNumber.Create(CountChanged(Previews)));
    ChangesJson := TJSONArray.Create;
    PreviewJson.AddPair('changes', ChangesJson);
    for I := 0 to High(Previews) do
    begin
      ChangeJson := BuildChangeJson(Previews[I], False, '');
      ChangesJson.AddElement(ChangeJson);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function BuildParameterBatchSetResponse(
  const Previews: TArray<TAul2MIRAIParameterPreview>;
  const VerifiedValues: TArray<string>;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity): string;
var
  ChangeJson : TJSONObject;
  ChangesJson: TJSONArray;
  ChangedCount: Integer;
  I          : Integer;
  Root       : TJSONObject;
  ResultJson : TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root, AfterIdentity, AUL2MIRAI_COMMAND_SET_PARAMETERS);
    ChangedCount := CountChanged(Previews);
    ResultJson := TJSONObject.Create;
    Root.AddPair('change', ResultJson);
    ResultJson.AddPair('operation', 'set_object_parameters');
    ResultJson.AddPair('applied', TJSONBool.Create(ChangedCount > 0));
    ResultJson.AddPair('change_count',
      TJSONNumber.Create(Length(Previews)));
    ResultJson.AddPair('changed_count',
      TJSONNumber.Create(ChangedCount));
    ResultJson.AddPair('previous_state_token', BeforeIdentity.StateToken);
    ChangesJson := TJSONArray.Create;
    ResultJson.AddPair('changes', ChangesJson);
    for I := 0 to High(Previews) do
    begin
      ChangeJson := BuildChangeJson(Previews[I], True, VerifiedValues[I]);
      ChangesJson.AddElement(ChangeJson);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

end.
