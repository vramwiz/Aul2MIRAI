unit Aul2MIRAIObjectCreate;

// Parses, validates, applies, and reports creation of one object from a
// caller-supplied AviUtl2 alias.

interface

uses
  AviUtl2PluginTypes,
  Aul2MIRAIObjectTypes,
  Aul2MIRAISnapshotIdentity;

type
  TAul2MIRAIObjectCreateRequest = record
    Layer      : Integer;
    Frame      : Integer;
    FrameLength: Integer;
    AliasText  : string;
  end;

  TAul2MIRAIObjectCreatePreview = record
    Layer        : Integer;
    StartFrame   : Integer;
    EndFrame     : Integer;
    FrameLength  : Integer;
    AliasText    : string;
    AliasDigest  : string;
    AliasByteSize: Integer;
    PrimaryEffect: string;
    MaterialPath : string;
    Effects      : TArray<string>;
  end;

function ParseObjectCreateRequest(const RequestText: string;
  RequireApply: Boolean; out StateToken: string;
  out CreateRequest: TAul2MIRAIObjectCreateRequest;
  out ErrorCode, ErrorMessage: string): Boolean;
function CreateObjectCreatePreview(
  const Snapshot: TAul2MIRAISceneSnapshot;
  const CreateRequest: TAul2MIRAIObjectCreateRequest;
  out Preview: TAul2MIRAIObjectCreatePreview;
  out ErrorCode, ErrorMessage: string): Boolean;
function ApplyObjectCreate(EditHandle: PEditHandle;
  const Preview: TAul2MIRAIObjectCreatePreview;
  out CreatedInfo: TAul2MIRAIObjectInfo;
  out ErrorCode, ErrorMessage: string): Boolean;
function ResolveCreatedObjectIndex(const Snapshot: TAul2MIRAISceneSnapshot;
  const Preview: TAul2MIRAIObjectCreatePreview;
  out CreatedIndex: Integer; out ErrorMessage: string): Boolean;
function BuildObjectCreatePreviewResponse(
  const Preview: TAul2MIRAIObjectCreatePreview;
  const Identity: TAul2MIRAISnapshotIdentity): string;
function BuildObjectCreateResponse(
  const Preview: TAul2MIRAIObjectCreatePreview;
  const CreatedInfo: TAul2MIRAIObjectInfo; CreatedIndex: Integer;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity): string;

implementation

uses
  System.Hash,
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  Aul2MIRAIObjectAlias,
  Aul2MIRAIObjectReader,
  Aul2MIRAIProtocol;

const
  MAX_CREATE_ALIAS_BYTES = 1024 * 1024;
  MAX_CREATE_FRAME = 2000000000;
  MAX_CREATE_LAYER = 9999;

type
  TObjectCreateContext = class
  public
    Preview     : TAul2MIRAIObjectCreatePreview;
    CreatedInfo : TAul2MIRAIObjectInfo;
    ErrorCode   : string;
    ErrorMessage: string;
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

function ParseObjectCreateRequest(const RequestText: string;
  RequireApply: Boolean; out StateToken: string;
  out CreateRequest: TAul2MIRAIObjectCreateRequest;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  AliasValue: TJSONValue;
  ApplyValue: TJSONValue;
  Json      : TJSONValue;
  Root      : TJSONObject;
  TokenValue: TJSONValue;
begin
  Result := False;
  StateToken := '';
  CreateRequest := Default(TAul2MIRAIObjectCreateRequest);
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
    if not RequireInteger(Root, 'layer', CreateRequest.Layer,
      ErrorCode, ErrorMessage) or
       not RequireInteger(Root, 'frame', CreateRequest.Frame,
      ErrorCode, ErrorMessage) or
       not RequireInteger(Root, 'length', CreateRequest.FrameLength,
      ErrorCode, ErrorMessage) then
      Exit;

    AliasValue := Root.GetValue('alias');
    if not (AliasValue is TJSONString) then
    begin
      ErrorCode := 'invalid_alias';
      ErrorMessage := 'alias must be a string.';
      Exit;
    end;
    CreateRequest.AliasText := TJSONString(AliasValue).Value;
    if CreateRequest.AliasText = '' then
    begin
      ErrorCode := 'empty_alias';
      ErrorMessage := 'alias must not be empty.';
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
        ErrorMessage := 'apply must be true to perform an edit.';
        Exit;
      end;
    end;
    Result := True;
  finally
    Json.Free;
  end;
end;

function RangesOverlap(StartA, EndA, StartB, EndB: Integer): Boolean;
begin
  Result := (StartA <= EndB) and (EndA >= StartB);
end;

function CreateObjectCreatePreview(
  const Snapshot: TAul2MIRAISceneSnapshot;
  const CreateRequest: TAul2MIRAIObjectCreateRequest;
  out Preview: TAul2MIRAIObjectCreatePreview;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  AliasUtf8: UTF8String;
  Item     : TAul2MIRAIObjectInfo;
begin
  Result := False;
  Preview := Default(TAul2MIRAIObjectCreatePreview);
  ErrorCode := '';
  ErrorMessage := '';
  if (CreateRequest.Layer < 0) or
     (CreateRequest.Layer > MAX_CREATE_LAYER) then
  begin
    ErrorCode := 'invalid_layer';
    ErrorMessage := 'layer is outside the safe range.';
    Exit;
  end;
  if (CreateRequest.Frame < 0) or
     (CreateRequest.Frame > MAX_CREATE_FRAME) then
  begin
    ErrorCode := 'invalid_frame';
    ErrorMessage := 'frame is outside the safe range.';
    Exit;
  end;
  if (CreateRequest.FrameLength <= 0) or
     (Int64(CreateRequest.Frame) + CreateRequest.FrameLength - 1 >
      MAX_CREATE_FRAME) then
  begin
    ErrorCode := 'invalid_length';
    ErrorMessage := 'length is outside the safe range.';
    Exit;
  end;
  AliasUtf8 := UTF8String(CreateRequest.AliasText);
  if (Length(AliasUtf8) = 0) or
     (Length(AliasUtf8) > MAX_CREATE_ALIAS_BYTES) then
  begin
    ErrorCode := 'invalid_alias_size';
    ErrorMessage := Format('alias must be between 1 and %d UTF-8 bytes.',
      [MAX_CREATE_ALIAS_BYTES]);
    Exit;
  end;

  Preview.PrimaryEffect := ExtractPrimaryEffect(CreateRequest.AliasText);
  if Preview.PrimaryEffect = '' then
  begin
    ErrorCode := 'invalid_alias';
    ErrorMessage := 'alias must contain a non-empty effect.name.';
    Exit;
  end;
  Preview.Effects := ExtractEffectNames(CreateRequest.AliasText);
  if Length(Preview.Effects) = 0 then
  begin
    ErrorCode := 'invalid_alias';
    ErrorMessage := 'alias must contain at least one effect block.';
    Exit;
  end;

  Preview.Layer := CreateRequest.Layer;
  Preview.StartFrame := CreateRequest.Frame;
  Preview.EndFrame := CreateRequest.Frame +
    CreateRequest.FrameLength - 1;
  Preview.FrameLength := CreateRequest.FrameLength;
  Preview.AliasText := CreateRequest.AliasText;
  Preview.AliasDigest :=
    LowerCase(THashSHA2.GetHashString(CreateRequest.AliasText));
  Preview.AliasByteSize := Length(AliasUtf8);
  Preview.MaterialPath := ExtractMaterialPath(CreateRequest.AliasText);

  for Item in Snapshot.Objects do
    if (Item.Layer = Preview.Layer) and
       RangesOverlap(Item.StartFrame, Item.EndFrame,
         Preview.StartFrame, Preview.EndFrame) then
    begin
      ErrorCode := 'destination_occupied';
      ErrorMessage := Format(
        'The destination overlaps object index %d.', [Item.Index]);
      Exit;
    end;
  Result := True;
end;

function EffectValuesMatch(const Expected,
  Actual: TArray<TAul2MIRAIEffectDetail>;
  out Difference: string): Boolean;
var
  EffectIndex: Integer;
  ItemIndex  : Integer;
begin
  Result := False;
  Difference := '';
  if Length(Expected) <> Length(Actual) then
  begin
    Difference := 'effect detail count differs.';
    Exit;
  end;
  for EffectIndex := 0 to High(Expected) do
  begin
    if Expected[EffectIndex].Name <> Actual[EffectIndex].Name then
    begin
      Difference := Format('effect %d name differs.', [EffectIndex]);
      Exit;
    end;
    if Length(Expected[EffectIndex].Parameters) <>
       Length(Actual[EffectIndex].Parameters) then
    begin
      Difference := Format('effect %d parameter count differs.',
        [EffectIndex]);
      Exit;
    end;
    for ItemIndex := 0 to High(Expected[EffectIndex].Parameters) do
    begin
      if Expected[EffectIndex].Parameters[ItemIndex].Name <>
         Actual[EffectIndex].Parameters[ItemIndex].Name then
      begin
        Difference := Format('effect %d parameter %d name differs.',
          [EffectIndex, ItemIndex]);
        Exit;
      end;
      if Expected[EffectIndex].Parameters[ItemIndex].Value <>
         Actual[EffectIndex].Parameters[ItemIndex].Value then
      begin
        Difference := Format(
          'effect %d parameter %s differs (%s -> %s).',
          [EffectIndex,
           Expected[EffectIndex].Parameters[ItemIndex].Name,
           Expected[EffectIndex].Parameters[ItemIndex].Value,
           Actual[EffectIndex].Parameters[ItemIndex].Value]);
        Exit;
      end;
    end;
  end;
  Result := True;
end;

procedure CreateObjectCallback(Param: Pointer; Edit: PEditSection); cdecl;
var
  AliasUtf8     : UTF8String;
  Context       : TObjectCreateContext;
  Created       : TObjectHandle;
  Difference    : string;
  ExpectedDetail: TArray<TAul2MIRAIEffectDetail>;
  LayerFrame    : TObjectLayerFrame;
begin
  Context := TObjectCreateContext(Param);
  if Context = nil then
    Exit;
  try
    if Edit = nil then
    begin
      Context.ErrorCode := 'edit_unavailable';
      Context.ErrorMessage := 'AviUtl2 returned no edit section.';
      Exit;
    end;
    AliasUtf8 := UTF8String(Context.Preview.AliasText);
    Created := Edit^.CreateObjectFromAlias(PAnsiChar(AliasUtf8),
      Context.Preview.Layer, Context.Preview.StartFrame,
      Context.Preview.FrameLength);
    if Created = nil then
    begin
      Context.ErrorCode := 'create_rejected';
      Context.ErrorMessage := 'AviUtl2 rejected the object alias.';
      Exit;
    end;

    LayerFrame := Edit^.GetObjectLayerFrame(Created);
    if (LayerFrame.Layer <> Context.Preview.Layer) or
       (LayerFrame.StartFrame <> Context.Preview.StartFrame) or
       (LayerFrame.EndFrame <> Context.Preview.EndFrame) then
    begin
      Edit^.DeleteObject(Created);
      Context.ErrorCode := 'create_verification_failed';
      Context.ErrorMessage := 'The created object range differs from the request.';
      Exit;
    end;
    if not ReadObjectSnapshot(Edit, Created, True, True,
      Context.CreatedInfo, Difference) then
    begin
      Edit^.DeleteObject(Created);
      Context.ErrorCode := 'create_verification_failed';
      Context.ErrorMessage :=
        'The created object could not be read: ' + Difference;
      Exit;
    end;
    if Context.CreatedInfo.PrimaryEffect <> Context.Preview.PrimaryEffect then
    begin
      Edit^.DeleteObject(Created);
      Context.ErrorCode := 'create_verification_failed';
      Context.ErrorMessage := 'The created primary effect differs from the alias.';
      Exit;
    end;
    if Context.CreatedInfo.MaterialPath <> Context.Preview.MaterialPath then
    begin
      Edit^.DeleteObject(Created);
      Context.ErrorCode := 'create_verification_failed';
      Context.ErrorMessage := 'The created material path differs from the alias.';
      Exit;
    end;
    ExpectedDetail := ExtractEffectDetails(Context.Preview.AliasText);
    if not EffectValuesMatch(ExpectedDetail,
      Context.CreatedInfo.EffectDetails, Difference) then
    begin
      Edit^.DeleteObject(Created);
      Context.ErrorCode := 'create_verification_failed';
      Context.ErrorMessage :=
        'The created effect values differ from the alias: ' + Difference;
      Exit;
    end;
    Edit^.SetFocusObject(Created);
  except
    on E: Exception do
    begin
      Context.ErrorCode := 'create_failed';
      Context.ErrorMessage := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

function ApplyObjectCreate(EditHandle: PEditHandle;
  const Preview: TAul2MIRAIObjectCreatePreview;
  out CreatedInfo: TAul2MIRAIObjectInfo;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  Context: TObjectCreateContext;
begin
  Result := False;
  CreatedInfo := Default(TAul2MIRAIObjectInfo);
  ErrorCode := '';
  ErrorMessage := '';
  if (EditHandle = nil) or
     not Assigned(EditHandle^.CallEditSectionParam) then
  begin
    ErrorCode := 'edit_unavailable';
    ErrorMessage := 'AviUtl2 edit section is not available.';
    Exit;
  end;
  Context := TObjectCreateContext.Create;
  try
    Context.Preview := Preview;
    if not EditHandle^.CallEditSectionParam(Context,
      @CreateObjectCallback) then
    begin
      ErrorCode := 'edit_rejected';
      ErrorMessage := 'AviUtl2 rejected the edit request.';
      Exit;
    end;
    ErrorCode := Context.ErrorCode;
    ErrorMessage := Context.ErrorMessage;
    CreatedInfo := Context.CreatedInfo;
    Result := ErrorCode = '';
  finally
    Context.Free;
  end;
end;

function ResolveCreatedObjectIndex(const Snapshot: TAul2MIRAISceneSnapshot;
  const Preview: TAul2MIRAIObjectCreatePreview;
  out CreatedIndex: Integer; out ErrorMessage: string): Boolean;
var
  Item: TAul2MIRAIObjectInfo;
begin
  Result := False;
  CreatedIndex := -1;
  ErrorMessage := '';
  for Item in Snapshot.Objects do
    if (Item.Layer = Preview.Layer) and
       (Item.StartFrame = Preview.StartFrame) and
       (Item.EndFrame = Preview.EndFrame) and
       (Item.PrimaryEffect = Preview.PrimaryEffect) then
    begin
      CreatedIndex := Item.Index;
      Exit(True);
    end;
  ErrorMessage := 'The created object was not found after the edit.';
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

function BuildCreateJson(const Preview: TAul2MIRAIObjectCreatePreview;
  IncludeResult: Boolean; const CreatedInfo: TAul2MIRAIObjectInfo;
  CreatedIndex: Integer): TJSONObject;
var
  EffectName  : string;
  EffectsJson : TJSONArray;
  TargetJson  : TJSONObject;
  VerifiedJson: TJSONArray;
begin
  Result := TJSONObject.Create;
  TargetJson := TJSONObject.Create;
  Result.AddPair('target', TargetJson);
  TargetJson.AddPair('layer', TJSONNumber.Create(Preview.Layer));
  TargetJson.AddPair('start_frame',
    TJSONNumber.Create(Preview.StartFrame));
  TargetJson.AddPair('end_frame', TJSONNumber.Create(Preview.EndFrame));
  Result.AddPair('frame_length', TJSONNumber.Create(Preview.FrameLength));
  Result.AddPair('primary_effect', Preview.PrimaryEffect);
  Result.AddPair('material_path', Preview.MaterialPath);
  Result.AddPair('alias_sha256', Preview.AliasDigest);
  Result.AddPair('alias_utf8_bytes',
    TJSONNumber.Create(Preview.AliasByteSize));
  EffectsJson := TJSONArray.Create;
  Result.AddPair('effects', EffectsJson);
  for EffectName in Preview.Effects do
    EffectsJson.Add(EffectName);
  if IncludeResult then
  begin
    Result.AddPair('applied', TJSONBool.Create(True));
    Result.AddPair('created_index', TJSONNumber.Create(CreatedIndex));
    Result.AddPair('object_type', CreatedInfo.ObjectType);
    Result.AddPair('content_digest', CreatedInfo.ContentDigest);
    VerifiedJson := TJSONArray.Create;
    Result.AddPair('verified', VerifiedJson);
    VerifiedJson.Add('placement');
    VerifiedJson.Add('primary_effect');
    VerifiedJson.Add('material_path');
    VerifiedJson.Add('effect_order');
    VerifiedJson.Add('effect_parameter_names_and_values');
  end;
end;

function BuildObjectCreatePreviewResponse(
  const Preview: TAul2MIRAIObjectCreatePreview;
  const Identity: TAul2MIRAISnapshotIdentity): string;
var
  PreviewJson: TJSONObject;
  Root       : TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root, Identity,
      AUL2MIRAI_COMMAND_PREVIEW_CREATE_OBJECT_FROM_ALIAS);
    PreviewJson := TJSONObject.Create;
    Root.AddPair('preview', PreviewJson);
    PreviewJson.AddPair('operation', 'create_object_from_alias');
    PreviewJson.AddPair('applied', TJSONBool.Create(False));
    PreviewJson.AddPair('object',
      BuildCreateJson(Preview, False,
        Default(TAul2MIRAIObjectInfo), -1));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function BuildObjectCreateResponse(
  const Preview: TAul2MIRAIObjectCreatePreview;
  const CreatedInfo: TAul2MIRAIObjectInfo; CreatedIndex: Integer;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity): string;
var
  ChangeJson: TJSONObject;
  Root      : TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root, AfterIdentity,
      AUL2MIRAI_COMMAND_CREATE_OBJECT_FROM_ALIAS);
    ChangeJson := TJSONObject.Create;
    Root.AddPair('change', ChangeJson);
    ChangeJson.AddPair('operation', 'create_object_from_alias');
    ChangeJson.AddPair('applied', TJSONBool.Create(True));
    ChangeJson.AddPair('previous_state_token', BeforeIdentity.StateToken);
    ChangeJson.AddPair('object',
      BuildCreateJson(Preview, True, CreatedInfo, CreatedIndex));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

end.
