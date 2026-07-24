unit Aul2MIRAIObjectCreate;

// Parses, validates, applies, and reports atomic creation of one or more
// objects from caller-supplied AviUtl2 aliases or default effects.

interface

uses
  AviUtl2PluginTypes,
  Aul2MIRAIObjectTypes,
  Aul2MIRAISnapshotIdentity;

type
  TAul2MIRAIObjectCreateRequest = record
    CreateDefault: Boolean;
    Layer        : Integer;
    Frame        : Integer;
    FrameLength  : Integer;
    AliasText    : string;
    EffectName   : string;
  end;

  TAul2MIRAIObjectCreatePreview = record
    AutoLength    : Boolean;
    CreateDefault : Boolean;
    Layer         : Integer;
    StartFrame    : Integer;
    EndFrame      : Integer;
    FrameLength   : Integer;
    AliasText     : string;
    AliasDigest   : string;
    AliasByteSize : Integer;
    PrimaryEffect : string;
    MaterialPath  : string;
    Effects       : TArray<string>;
  end;

function ParseObjectCreateRequest(const RequestText: string;
  RequireApply: Boolean; out StateToken: string;
  out CreateRequest: TAul2MIRAIObjectCreateRequest;
  out ErrorCode, ErrorMessage: string): Boolean;
function ParseObjectCreateBatchRequest(const RequestText: string;
  RequireApply: Boolean; out StateToken: string;
  out CreateRequests: TArray<TAul2MIRAIObjectCreateRequest>;
  out ErrorCode, ErrorMessage: string): Boolean;
function CreateObjectCreatePreview(
  const Snapshot: TAul2MIRAISceneSnapshot;
  const CreateRequest: TAul2MIRAIObjectCreateRequest;
  out Preview: TAul2MIRAIObjectCreatePreview;
  out ErrorCode, ErrorMessage: string): Boolean;
function CreateObjectCreatePreviews(
  const Snapshot: TAul2MIRAISceneSnapshot;
  const CreateRequests: TArray<TAul2MIRAIObjectCreateRequest>;
  out Previews: TArray<TAul2MIRAIObjectCreatePreview>;
  out ErrorCode, ErrorMessage: string): Boolean;
function ApplyObjectCreate(EditHandle: PEditHandle;
  const Preview: TAul2MIRAIObjectCreatePreview;
  out CreatedInfo: TAul2MIRAIObjectInfo;
  out ErrorCode, ErrorMessage: string): Boolean;
function ApplyObjectCreates(EditHandle: PEditHandle;
  const Previews: TArray<TAul2MIRAIObjectCreatePreview>;
  out CreatedInfos: TArray<TAul2MIRAIObjectInfo>;
  out ErrorCode, ErrorMessage: string): Boolean;
function ResolveCreatedObjectIndex(const Snapshot: TAul2MIRAISceneSnapshot;
  const Preview: TAul2MIRAIObjectCreatePreview;
  out CreatedIndex: Integer; out ErrorMessage: string): Boolean;
function ResolveCreatedCreateObjectIndices(
  const Snapshot: TAul2MIRAISceneSnapshot;
  const Previews: TArray<TAul2MIRAIObjectCreatePreview>;
  out CreatedIndices: TArray<Integer>;
  out ErrorMessage: string): Boolean;
function BuildObjectCreatePreviewResponse(
  const Preview: TAul2MIRAIObjectCreatePreview;
  const Identity: TAul2MIRAISnapshotIdentity): string;
function BuildObjectCreateResponse(
  const Preview: TAul2MIRAIObjectCreatePreview;
  const CreatedInfo: TAul2MIRAIObjectInfo; CreatedIndex: Integer;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity): string;
function BuildObjectCreateBatchPreviewResponse(
  const Previews: TArray<TAul2MIRAIObjectCreatePreview>;
  const Identity: TAul2MIRAISnapshotIdentity): string;
function BuildObjectCreateBatchResponse(
  const Previews: TArray<TAul2MIRAIObjectCreatePreview>;
  const CreatedInfos: TArray<TAul2MIRAIObjectInfo>;
  const CreatedIndices: TArray<Integer>;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity): string;

implementation

uses
  System.Generics.Collections,
  System.Hash,
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  Aul2MIRAIObjectAlias,
  Aul2MIRAIObjectReader,
  Aul2MIRAIProtocol;

const
  MAX_CREATE_ALIAS_BYTES = 1024 * 1024;
  MAX_CREATE_COUNT = 64;
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

  TObjectCreateBatchContext = class
  public
    Previews    : TArray<TAul2MIRAIObjectCreatePreview>;
    CreatedInfos: TArray<TAul2MIRAIObjectInfo>;
    Created     : TArray<TObjectHandle>;
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

function ParseCreateItem(Root: TJSONObject;
  out CreateRequest: TAul2MIRAIObjectCreateRequest;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  AliasValue : TJSONValue;
  EffectValue: TJSONValue;
begin
  Result := False;
  CreateRequest := Default(TAul2MIRAIObjectCreateRequest);
  if not RequireInteger(Root, 'layer', CreateRequest.Layer,
    ErrorCode, ErrorMessage) or
     not RequireInteger(Root, 'frame', CreateRequest.Frame,
    ErrorCode, ErrorMessage) or
     not RequireInteger(Root, 'length', CreateRequest.FrameLength,
    ErrorCode, ErrorMessage) then
    Exit;

  AliasValue := Root.GetValue('alias');
  EffectValue := Root.GetValue('effect');
  if (AliasValue is TJSONString) and
     (TJSONString(AliasValue).Value <> '') and
     not (EffectValue is TJSONString) then
  begin
    CreateRequest.AliasText := TJSONString(AliasValue).Value;
    CreateRequest.CreateDefault := False;
  end
  else if (EffectValue is TJSONString) and
          (TJSONString(EffectValue).Value <> '') and
          not (AliasValue is TJSONString) then
  begin
    CreateRequest.EffectName := TJSONString(EffectValue).Value;
    CreateRequest.CreateDefault := True;
  end
  else
  begin
    ErrorCode := 'invalid_alias';
    ErrorMessage :=
      'Specify exactly one non-empty alias or effect string.';
    Exit;
  end;
  Result := True;
end;

function ParseObjectCreateRequest(const RequestText: string;
  RequireApply: Boolean; out StateToken: string;
  out CreateRequest: TAul2MIRAIObjectCreateRequest;
  out ErrorCode, ErrorMessage: string): Boolean;
var
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
    if not ParseCreateItem(Root, CreateRequest, ErrorCode,
      ErrorMessage) then
      Exit;

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

function ParseObjectCreateBatchRequest(const RequestText: string;
  RequireApply: Boolean; out StateToken: string;
  out CreateRequests: TArray<TAul2MIRAIObjectCreateRequest>;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  ApplyValue : TJSONValue;
  CreateValue: TJSONValue;
  CreatesJson: TJSONArray;
  I          : Integer;
  Json       : TJSONValue;
  Root       : TJSONObject;
  TokenValue : TJSONValue;
begin
  Result := False;
  StateToken := '';
  SetLength(CreateRequests, 0);
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

    CreateValue := Root.GetValue('creates');
    if not (CreateValue is TJSONArray) then
    begin
      ErrorCode := 'invalid_creates';
      ErrorMessage := 'creates must be an array.';
      Exit;
    end;
    CreatesJson := TJSONArray(CreateValue);
    if CreatesJson.Count = 0 then
    begin
      ErrorCode := 'empty_creates';
      ErrorMessage := 'At least one create item is required.';
      Exit;
    end;
    if CreatesJson.Count > MAX_CREATE_COUNT then
    begin
      ErrorCode := 'too_many_creates';
      ErrorMessage := Format('creates exceeds the %d item limit.',
        [MAX_CREATE_COUNT]);
      Exit;
    end;
    SetLength(CreateRequests, CreatesJson.Count);
    for I := 0 to CreatesJson.Count - 1 do
    begin
      CreateValue := CreatesJson.Items[I];
      if not (CreateValue is TJSONObject) then
      begin
        ErrorCode := 'invalid_create';
        ErrorMessage := Format('creates[%d] must be an object.', [I]);
        Exit;
      end;
      if not ParseCreateItem(TJSONObject(CreateValue),
        CreateRequests[I], ErrorCode, ErrorMessage) then
      begin
        ErrorMessage := Format('creates[%d]: %s', [I, ErrorMessage]);
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
  if (CreateRequest.FrameLength < 0) or
     ((CreateRequest.FrameLength > 0) and
      (Int64(CreateRequest.Frame) + CreateRequest.FrameLength - 1 >
       MAX_CREATE_FRAME)) then
  begin
    ErrorCode := 'invalid_length';
    ErrorMessage :=
      'length must be zero for automatic sizing or a safe positive value.';
    Exit;
  end;
  if CreateRequest.CreateDefault then
  begin
    Preview.CreateDefault := True;
    Preview.PrimaryEffect := CreateRequest.EffectName;
    SetLength(Preview.Effects, 1);
    Preview.Effects[0] := CreateRequest.EffectName;
    Preview.AliasText := '';
    Preview.AliasDigest := '';
    Preview.AliasByteSize := 0;
    Preview.MaterialPath := '';
  end
  else
  begin
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
    Preview.AliasText := CreateRequest.AliasText;
    Preview.AliasDigest :=
      LowerCase(THashSHA2.GetHashString(CreateRequest.AliasText));
    Preview.AliasByteSize := Length(AliasUtf8);
    Preview.MaterialPath := ExtractMaterialPath(CreateRequest.AliasText);
  end;

  Preview.AutoLength := CreateRequest.FrameLength = 0;
  Preview.Layer := CreateRequest.Layer;
  Preview.StartFrame := CreateRequest.Frame;
  if Preview.AutoLength then
    Preview.EndFrame := -1
  else
    Preview.EndFrame := CreateRequest.Frame +
      CreateRequest.FrameLength - 1;
  Preview.FrameLength := CreateRequest.FrameLength;

  for Item in Snapshot.Objects do
    if (Item.Layer = Preview.Layer) and
       ((Preview.AutoLength and
         (Item.EndFrame >= Preview.StartFrame)) or
        (not Preview.AutoLength and
         RangesOverlap(Item.StartFrame, Item.EndFrame,
           Preview.StartFrame, Preview.EndFrame))) then
    begin
      ErrorCode := 'destination_occupied';
      if Preview.AutoLength then
        ErrorMessage := Format(
          'Automatic sizing requires no later object on the target layer; ' +
          'object index %d is at or after the requested frame.', [Item.Index])
      else
        ErrorMessage := Format(
          'The destination overlaps object index %d.', [Item.Index]);
      Exit;
    end;
  Result := True;
end;

function CreateObjectCreatePreviews(
  const Snapshot: TAul2MIRAISceneSnapshot;
  const CreateRequests: TArray<TAul2MIRAIObjectCreateRequest>;
  out Previews: TArray<TAul2MIRAIObjectCreatePreview>;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  I: Integer;
  J: Integer;
begin
  Result := False;
  ErrorCode := '';
  ErrorMessage := '';
  SetLength(Previews, Length(CreateRequests));
  if Length(CreateRequests) = 0 then
  begin
    ErrorCode := 'empty_creates';
    ErrorMessage := 'At least one create item is required.';
    Exit;
  end;
  for I := 0 to High(CreateRequests) do
  begin
    if CreateRequests[I].FrameLength = 0 then
    begin
      ErrorCode := 'batch_auto_length_unsupported';
      ErrorMessage := Format(
        'creates[%d]: length=0 is not supported in a batch; ' +
        'use an explicit positive length.', [I]);
      Exit;
    end;
    if not CreateObjectCreatePreview(Snapshot, CreateRequests[I],
      Previews[I], ErrorCode, ErrorMessage) then
    begin
      ErrorMessage := Format('creates[%d]: %s', [I, ErrorMessage]);
      Exit;
    end;
    for J := 0 to I - 1 do
      if (Previews[J].Layer = Previews[I].Layer) and
         RangesOverlap(Previews[J].StartFrame, Previews[J].EndFrame,
           Previews[I].StartFrame, Previews[I].EndFrame) then
      begin
        ErrorCode := 'destination_conflict';
        ErrorMessage := Format(
          'creates[%d] overlaps the destination in creates[%d].',
          [I, J]);
        Exit;
      end;
  end;
  Result := True;
end;

function EffectValuesMatch(const Expected,
  Actual: TArray<TAul2MIRAIEffectDetail>;
  AllowScenePlaybackNormalization: Boolean;
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
      if not (AllowScenePlaybackNormalization and
              SameText(Expected[EffectIndex].Name, 'シーン') and
              SameText(Expected[EffectIndex].Parameters[ItemIndex].Name,
                '再生位置')) and
         (Expected[EffectIndex].Parameters[ItemIndex].Value <>
          Actual[EffectIndex].Parameters[ItemIndex].Value) then
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

function CreateAndVerifyObject(Edit: PEditSection;
  const Preview: TAul2MIRAIObjectCreatePreview;
  out Created: TObjectHandle; out CreatedInfo: TAul2MIRAIObjectInfo;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  AliasUtf8     : UTF8String;
  Difference    : string;
  ExpectedDetail: TArray<TAul2MIRAIEffectDetail>;
  LayerFrame    : TObjectLayerFrame;
begin
  Result := False;
  Created := nil;
  CreatedInfo := Default(TAul2MIRAIObjectInfo);
  ErrorCode := '';
  ErrorMessage := '';
  if Edit = nil then
  begin
    ErrorCode := 'edit_unavailable';
    ErrorMessage := 'AviUtl2 returned no edit section.';
    Exit;
  end;
  if Preview.CreateDefault then
    Created := Edit^.CreateObject(PWideChar(Preview.PrimaryEffect),
      Preview.Layer, Preview.StartFrame, Preview.FrameLength)
  else
  begin
    AliasUtf8 := UTF8String(Preview.AliasText);
    Created := Edit^.CreateObjectFromAlias(PAnsiChar(AliasUtf8),
      Preview.Layer, Preview.StartFrame, Preview.FrameLength);
  end;
  if Created = nil then
  begin
    ErrorCode := 'create_rejected';
    if Preview.CreateDefault then
      ErrorMessage := 'AviUtl2 rejected the default effect.'
    else
      ErrorMessage := 'AviUtl2 rejected the object alias.';
    Exit;
  end;

  LayerFrame := Edit^.GetObjectLayerFrame(Created);
  if (LayerFrame.Layer <> Preview.Layer) or
     (LayerFrame.StartFrame <> Preview.StartFrame) or
     (Preview.AutoLength and
      (LayerFrame.EndFrame < LayerFrame.StartFrame)) or
     (not Preview.AutoLength and
      (LayerFrame.EndFrame <> Preview.EndFrame)) then
  begin
    Edit^.DeleteObject(Created);
    Created := nil;
    ErrorCode := 'create_verification_failed';
    ErrorMessage := 'The created object range differs from the request.';
    Exit;
  end;
  if not ReadObjectSnapshot(Edit, Created, True, True,
    CreatedInfo, Difference) then
  begin
    Edit^.DeleteObject(Created);
    Created := nil;
    ErrorCode := 'create_verification_failed';
    ErrorMessage := 'The created object could not be read: ' + Difference;
    Exit;
  end;
  if CreatedInfo.PrimaryEffect <> Preview.PrimaryEffect then
  begin
    Edit^.DeleteObject(Created);
    Created := nil;
    ErrorCode := 'create_verification_failed';
    ErrorMessage :=
      'The created primary effect differs from the request.';
    Exit;
  end;
  if CreatedInfo.MaterialPath <> Preview.MaterialPath then
  begin
    Edit^.DeleteObject(Created);
    Created := nil;
    ErrorCode := 'create_verification_failed';
    ErrorMessage :=
      'The created material path differs from the request.';
    Exit;
  end;
  if not Preview.CreateDefault then
  begin
    ExpectedDetail := ExtractEffectDetails(Preview.AliasText);
    if not EffectValuesMatch(ExpectedDetail, CreatedInfo.EffectDetails,
      Preview.AutoLength and SameText(Preview.PrimaryEffect, 'シーン'),
      Difference) then
    begin
      Edit^.DeleteObject(Created);
      Created := nil;
      ErrorCode := 'create_verification_failed';
      ErrorMessage :=
        'The created effect values differ from the alias: ' + Difference;
      Exit;
    end;
  end;
  Result := True;
end;

procedure CreateObjectCallback(Param: Pointer; Edit: PEditSection); cdecl;
var
  Context: TObjectCreateContext;
  Created: TObjectHandle;
begin
  Context := TObjectCreateContext(Param);
  if Context = nil then
    Exit;
  try
    if not CreateAndVerifyObject(Edit, Context.Preview, Created,
      Context.CreatedInfo, Context.ErrorCode, Context.ErrorMessage) then
      Exit;
    Edit^.SetFocusObject(Created);
  except
    on E: Exception do
    begin
      Context.ErrorCode := 'create_failed';
      Context.ErrorMessage := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

procedure RemoveBatchCreated(Context: TObjectCreateBatchContext;
  Edit: PEditSection; LastIndex: Integer);
var
  I: Integer;
begin
  for I := LastIndex downto 0 do
    if Context.Created[I] <> nil then
    begin
      Edit^.DeleteObject(Context.Created[I]);
      Context.Created[I] := nil;
    end;
end;

procedure CreateObjectsCallback(Param: Pointer; Edit: PEditSection); cdecl;
var
  Context: TObjectCreateBatchContext;
  I      : Integer;
begin
  Context := TObjectCreateBatchContext(Param);
  if Context = nil then
    Exit;
  try
    if Edit = nil then
    begin
      Context.ErrorCode := 'edit_unavailable';
      Context.ErrorMessage := 'AviUtl2 returned no edit section.';
      Exit;
    end;
    SetLength(Context.Created, Length(Context.Previews));
    SetLength(Context.CreatedInfos, Length(Context.Previews));
    for I := 0 to High(Context.Previews) do
      if not CreateAndVerifyObject(Edit, Context.Previews[I],
        Context.Created[I], Context.CreatedInfos[I],
        Context.ErrorCode, Context.ErrorMessage) then
      begin
        Context.ErrorMessage := Format('creates[%d]: %s',
          [I, Context.ErrorMessage]);
        RemoveBatchCreated(Context, Edit, I - 1);
        Exit;
      end;
    if Length(Context.Created) > 0 then
      Edit^.SetFocusObject(Context.Created[High(Context.Created)]);
  except
    on E: Exception do
    begin
      if (Edit <> nil) and (Length(Context.Created) > 0) then
        RemoveBatchCreated(Context, Edit, High(Context.Created));
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

function ApplyObjectCreates(EditHandle: PEditHandle;
  const Previews: TArray<TAul2MIRAIObjectCreatePreview>;
  out CreatedInfos: TArray<TAul2MIRAIObjectInfo>;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  Context: TObjectCreateBatchContext;
begin
  Result := False;
  SetLength(CreatedInfos, 0);
  ErrorCode := '';
  ErrorMessage := '';
  if Length(Previews) = 0 then
  begin
    ErrorCode := 'empty_creates';
    ErrorMessage := 'At least one create item is required.';
    Exit;
  end;
  if (EditHandle = nil) or
     not Assigned(EditHandle^.CallEditSectionParam) then
  begin
    ErrorCode := 'edit_unavailable';
    ErrorMessage := 'AviUtl2 edit section is not available.';
    Exit;
  end;
  Context := TObjectCreateBatchContext.Create;
  try
    Context.Previews := Previews;
    if not EditHandle^.CallEditSectionParam(Context,
      @CreateObjectsCallback) then
    begin
      ErrorCode := 'edit_rejected';
      ErrorMessage := 'AviUtl2 rejected the edit request.';
      Exit;
    end;
    ErrorCode := Context.ErrorCode;
    ErrorMessage := Context.ErrorMessage;
    CreatedInfos := Copy(Context.CreatedInfos);
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

function ResolveCreatedCreateObjectIndices(
  const Snapshot: TAul2MIRAISceneSnapshot;
  const Previews: TArray<TAul2MIRAIObjectCreatePreview>;
  out CreatedIndices: TArray<Integer>;
  out ErrorMessage: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  ErrorMessage := '';
  SetLength(CreatedIndices, Length(Previews));
  for I := 0 to High(Previews) do
    if not ResolveCreatedObjectIndex(Snapshot, Previews[I],
      CreatedIndices[I], ErrorMessage) then
    begin
      ErrorMessage := Format('creates[%d]: %s', [I, ErrorMessage]);
      Exit;
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
  Result.AddPair('creation_source',
    IfThen(Preview.CreateDefault, 'default_effect', 'alias'));
  Result.AddPair('auto_length',
    TJSONBool.Create(Preview.AutoLength));
  TargetJson.AddPair('layer', TJSONNumber.Create(Preview.Layer));
  TargetJson.AddPair('start_frame',
    TJSONNumber.Create(Preview.StartFrame));
  if Preview.AutoLength and not IncludeResult then
    TargetJson.AddPair('end_frame', TJSONNull.Create)
  else
    TargetJson.AddPair('end_frame', TJSONNumber.Create(Preview.EndFrame));
  Result.AddPair('frame_length', TJSONNumber.Create(Preview.FrameLength));
  Result.AddPair('primary_effect', Preview.PrimaryEffect);
  Result.AddPair('material_path', Preview.MaterialPath);
  if Preview.CreateDefault then
    Result.AddPair('effect', Preview.PrimaryEffect)
  else
  begin
    Result.AddPair('alias_sha256', Preview.AliasDigest);
    Result.AddPair('alias_utf8_bytes',
      TJSONNumber.Create(Preview.AliasByteSize));
  end;
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
    if Preview.CreateDefault then
      VerifiedJson.Add('object_snapshot_read')
    else
    begin
      VerifiedJson.Add('effect_order');
      VerifiedJson.Add('effect_parameter_names_and_values');
    end;
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

function BuildObjectCreateBatchPreviewResponse(
  const Previews: TArray<TAul2MIRAIObjectCreatePreview>;
  const Identity: TAul2MIRAISnapshotIdentity): string;
var
  I          : Integer;
  Items      : TJSONArray;
  PreviewJson: TJSONObject;
  Root       : TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root, Identity,
      AUL2MIRAI_COMMAND_PREVIEW_CREATE_OBJECTS_FROM_ALIASES);
    PreviewJson := TJSONObject.Create;
    Root.AddPair('preview', PreviewJson);
    PreviewJson.AddPair('operation', 'create_objects_from_aliases');
    PreviewJson.AddPair('applied', TJSONBool.Create(False));
    PreviewJson.AddPair('create_count',
      TJSONNumber.Create(Length(Previews)));
    Items := TJSONArray.Create;
    PreviewJson.AddPair('creates', Items);
    for I := 0 to High(Previews) do
      Items.AddElement(BuildCreateJson(Previews[I], False,
        Default(TAul2MIRAIObjectInfo), -1));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function BuildObjectCreateBatchResponse(
  const Previews: TArray<TAul2MIRAIObjectCreatePreview>;
  const CreatedInfos: TArray<TAul2MIRAIObjectInfo>;
  const CreatedIndices: TArray<Integer>;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity): string;
var
  ChangeJson: TJSONObject;
  I         : Integer;
  Items     : TJSONArray;
  Root      : TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root, AfterIdentity,
      AUL2MIRAI_COMMAND_CREATE_OBJECTS_FROM_ALIASES);
    ChangeJson := TJSONObject.Create;
    Root.AddPair('change', ChangeJson);
    ChangeJson.AddPair('operation', 'create_objects_from_aliases');
    ChangeJson.AddPair('applied', TJSONBool.Create(True));
    ChangeJson.AddPair('create_count',
      TJSONNumber.Create(Length(Previews)));
    ChangeJson.AddPair('previous_state_token', BeforeIdentity.StateToken);
    Items := TJSONArray.Create;
    ChangeJson.AddPair('creates', Items);
    for I := 0 to High(Previews) do
      Items.AddElement(BuildCreateJson(Previews[I], True,
        CreatedInfos[I], CreatedIndices[I]));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

end.
