unit Aul2MIRAIProtocol;

// Named Pipeで交換するJSONプロトコルの定数、検証、応答生成を担当する。

interface

uses
  Aul2MIRAIEditStateTypes,
  Aul2MIRAIFrameCapture,
  Aul2MIRAIObjectTypes,
  Aul2MIRAIParameterPreview,
  Aul2MIRAISnapshotIdentity;

const
  AUL2MIRAI_PIPE_SHORT_NAME  = 'Aul2MIRAI.v1';
  AUL2MIRAI_PIPE_NAME        = '\\.\pipe\Aul2MIRAI.v1';
  AUL2MIRAI_PROTOCOL_NAME    = 'Aul2MIRAI';
  AUL2MIRAI_PROTOCOL_VERSION = 1;
  AUL2MIRAI_COMMAND_STATE    = 'get_edit_state';
  AUL2MIRAI_COMMAND_OBJECTS  = 'get_scene_objects';
  AUL2MIRAI_COMMAND_CURSOR_OBJECTS = 'get_objects_at_cursor';
  AUL2MIRAI_COMMAND_RANGE_OBJECTS = 'get_objects_in_selection';
  AUL2MIRAI_COMMAND_SELECTED_OBJECTS = 'get_selected_objects';
  AUL2MIRAI_COMMAND_OBJECT_DETAILS = 'get_object_details';
  AUL2MIRAI_COMMAND_PREVIEW_PARAMETER = 'preview_set_object_parameter';
  AUL2MIRAI_COMMAND_SET_PARAMETER = 'set_object_parameter';
  AUL2MIRAI_COMMAND_PREVIEW_PARAMETERS = 'preview_set_object_parameters';
  AUL2MIRAI_COMMAND_SET_PARAMETERS = 'set_object_parameters';
  AUL2MIRAI_COMMAND_PREVIEW_MOVE_OBJECTS = 'preview_move_objects';
  AUL2MIRAI_COMMAND_MOVE_OBJECTS = 'move_objects';
  AUL2MIRAI_COMMAND_PREVIEW_DUPLICATE_OBJECTS = 'preview_duplicate_objects';
  AUL2MIRAI_COMMAND_DUPLICATE_OBJECTS = 'duplicate_objects';
  AUL2MIRAI_COMMAND_PREVIEW_EDIT_POSITION = 'preview_set_edit_position';
  AUL2MIRAI_COMMAND_SET_EDIT_POSITION = 'set_edit_position';
  AUL2MIRAI_COMMAND_CURRENT_FRAME_IMAGE = 'get_current_frame_image';

function BuildProtocolRequest(const Command: string): string;
function ParseProtocolRequest(const RequestText: string;
  out Command, ErrorCode, ErrorMessage: string): Boolean;
function ParseObjectDetailsRequest(const RequestText: string;
  out StateToken: string; out TargetIndex: Integer;
  out ErrorCode, ErrorMessage: string): Boolean;
function ParseParameterPreviewRequest(const RequestText: string;
  out StateToken: string; out TargetIndex, EffectIndex: Integer;
  out ItemName, NewValue, ErrorCode, ErrorMessage: string): Boolean;
function ParseParameterSetRequest(const RequestText: string;
  out StateToken: string; out TargetIndex, EffectIndex: Integer;
  out ItemName, NewValue, ErrorCode, ErrorMessage: string): Boolean;
function BuildEditStateResponse(const State: TAul2MIRAIEditState;
  const Identity: TAul2MIRAISnapshotIdentity): string;
function BuildFrameImageResponse(const Image: TAul2MIRAIFrameImage;
  const Identity: TAul2MIRAISnapshotIdentity): string;
function BuildSceneObjectsResponse(const Command: string;
  const Snapshot: TAul2MIRAISceneSnapshot;
  const Identity: TAul2MIRAISnapshotIdentity): string;
function BuildParameterPreviewResponse(
  const Preview: TAul2MIRAIParameterPreview;
  const Identity: TAul2MIRAISnapshotIdentity): string;
function BuildParameterSetResponse(const Preview: TAul2MIRAIParameterPreview;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity;
  Applied: Boolean; const VerifiedValue: string): string;
function BuildStateChangedError(const Command, ExpectedStateToken: string;
  const Identity: TAul2MIRAISnapshotIdentity): string;
function BuildProtocolError(const Command, ErrorCode, ErrorMessage: string): string;
function IsSuccessfulResponse(const ResponseText: string): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON;

procedure AddProtocolHeader(Json: TJSONObject);
begin
  Json.AddPair('protocol', AUL2MIRAI_PROTOCOL_NAME);
  Json.AddPair('protocol_version', TJSONNumber.Create(AUL2MIRAI_PROTOCOL_VERSION));
end;

function RequireJsonString(Root: TJSONObject; const Name: string;
  out Value, ErrorCode, ErrorMessage: string): Boolean;
var
  JsonValue: TJSONValue;
begin
  JsonValue := Root.GetValue(Name);
  Result := JsonValue is TJSONString;
  if Result then
  begin
    Value := TJSONString(JsonValue).Value;
    Exit;
  end;
  Value := '';
  ErrorCode := 'invalid_' + Name;
  ErrorMessage := Name + ' must be a string.';
end;

function RequireJsonInteger(Root: TJSONObject; const Name: string;
  out Value: Integer; out ErrorCode, ErrorMessage: string): Boolean;
var
  JsonValue: TJSONValue;
begin
  JsonValue := Root.GetValue(Name);
  Result := (JsonValue is TJSONNumber) and
    TryStrToInt(JsonValue.Value, Value);
  if Result then
    Exit;
  Value := -1;
  ErrorCode := 'invalid_' + Name;
  ErrorMessage := Name + ' must be an integer.';
end;

procedure AddSnapshotIdentity(Json: TJSONObject;
  const Identity: TAul2MIRAISnapshotIdentity);
begin
  Json.AddPair('snapshot_id', Identity.SnapshotId);
  Json.AddPair('state_token', Identity.StateToken);
  Json.AddPair('captured_at_utc', Identity.CapturedAtUtc);
end;

function BuildProtocolRequest(const Command: string): string;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    AddProtocolHeader(Json);
    Json.AddPair('command', Command);
    Result := Json.ToJSON;
  finally
    Json.Free;
  end;
end;

function ParseProtocolRequest(const RequestText: string;
  out Command, ErrorCode, ErrorMessage: string): Boolean;
var
  CommandValue : TJSONValue; // commandフィールド
  Json         : TJSONValue; // 解析したJSON全体
  Root         : TJSONObject; // 要求オブジェクト
  Version      : Integer;    // 要求されたプロトコルバージョン
  VersionValue : TJSONValue; // protocol_versionフィールド
begin
  Result := False;
  Command := '';
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
    VersionValue := Root.GetValue('protocol_version');
    if (VersionValue = nil) or
       not TryStrToInt(VersionValue.Value, Version) then
    begin
      ErrorCode := 'invalid_version';
      ErrorMessage := 'protocol_version is required.';
      Exit;
    end;
    if Version <> AUL2MIRAI_PROTOCOL_VERSION then
    begin
      ErrorCode := 'unsupported_version';
      ErrorMessage := Format('Protocol version %d is not supported.', [Version]);
      Exit;
    end;

    CommandValue := Root.GetValue('command');
    if not (CommandValue is TJSONString) then
    begin
      ErrorCode := 'invalid_command';
      ErrorMessage := 'command is required.';
      Exit;
    end;

    Command := TJSONString(CommandValue).Value;
    Result := True;
  finally
    Json.Free;
  end;
end;

function ParseObjectDetailsRequest(const RequestText: string;
  out StateToken: string; out TargetIndex: Integer;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  Json: TJSONValue;
  Root: TJSONObject;
begin
  Result := False;
  StateToken := '';
  TargetIndex := -1;
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
    if not RequireJsonString(Root, 'state_token', StateToken,
      ErrorCode, ErrorMessage) then
      Exit;
    if (Length(StateToken) <> 71) or
       not StartsText('sha256:', StateToken) then
    begin
      ErrorCode := 'invalid_state_token';
      ErrorMessage := 'state_token must be a SHA-256 token.';
      Exit;
    end;
    if not RequireJsonInteger(Root, 'target_index', TargetIndex,
      ErrorCode, ErrorMessage) then
      Exit;
    if TargetIndex < 0 then
    begin
      ErrorCode := 'invalid_target_index';
      ErrorMessage := 'target_index must be zero or greater.';
      Exit;
    end;
    Result := True;
  finally
    Json.Free;
  end;
end;

function ParseParameterPreviewRequest(const RequestText: string;
  out StateToken: string; out TargetIndex, EffectIndex: Integer;
  out ItemName, NewValue, ErrorCode, ErrorMessage: string): Boolean;
var
  Json: TJSONValue;
  Root: TJSONObject;
begin
  Result := False;
  StateToken := '';
  TargetIndex := -1;
  EffectIndex := -1;
  ItemName := '';
  NewValue := '';
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
    if not RequireJsonString(Root, 'state_token', StateToken,
      ErrorCode, ErrorMessage) then
      Exit;
    if (Length(StateToken) <> 71) or
       not StartsText('sha256:', StateToken) then
    begin
      ErrorCode := 'invalid_state_token';
      ErrorMessage := 'state_token must be a SHA-256 token.';
      Exit;
    end;
    if not RequireJsonInteger(Root, 'target_index', TargetIndex,
      ErrorCode, ErrorMessage) then
      Exit;
    if not RequireJsonInteger(Root, 'effect_index', EffectIndex,
      ErrorCode, ErrorMessage) then
      Exit;
    if not RequireJsonString(Root, 'item', ItemName,
      ErrorCode, ErrorMessage) then
      Exit;
    if not RequireJsonString(Root, 'value', NewValue,
      ErrorCode, ErrorMessage) then
      Exit;
    Result := True;
  finally
    Json.Free;
  end;
end;

function ParseParameterSetRequest(const RequestText: string;
  out StateToken: string; out TargetIndex, EffectIndex: Integer;
  out ItemName, NewValue, ErrorCode, ErrorMessage: string): Boolean;
var
  ApplyValue: TJSONValue;
  Json      : TJSONValue;
  Root      : TJSONObject;
begin
  Result := ParseParameterPreviewRequest(RequestText, StateToken,
    TargetIndex, EffectIndex, ItemName, NewValue, ErrorCode, ErrorMessage);
  if not Result then
    Exit;

  Result := False;
  Json := TJSONObject.ParseJSONValue(RequestText);
  try
    if not (Json is TJSONObject) then
    begin
      ErrorCode := 'invalid_json';
      ErrorMessage := 'Request must be a JSON object.';
      Exit;
    end;
    Root := TJSONObject(Json);
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
    Result := True;
  finally
    Json.Free;
  end;
end;

function BuildEditStateResponse(const State: TAul2MIRAIEditState;
  const Identity: TAul2MIRAISnapshotIdentity): string;
var
  CursorSeconds: Double;
  Root         : TJSONObject;
  StateJson    : TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddProtocolHeader(Root);
    AddSnapshotIdentity(Root, Identity);
    Root.AddPair('status', 'ok');
    Root.AddPair('command', AUL2MIRAI_COMMAND_STATE);
    StateJson := TJSONObject.Create;
    Root.AddPair('edit_state', StateJson);
    StateJson.AddPair('captured_at_utc', State.CapturedAtUtc);
    StateJson.AddPair('project_path', State.ProjectPath);
    StateJson.AddPair('project_name', ExtractFileName(State.ProjectPath));
    StateJson.AddPair('scene_id', TJSONNumber.Create(State.SceneId));
    StateJson.AddPair('scene_name', State.SceneName);
    StateJson.AddPair('edit_mode', State.EditMode);
    StateJson.AddPair('width', TJSONNumber.Create(State.Width));
    StateJson.AddPair('height', TJSONNumber.Create(State.Height));
    StateJson.AddPair('rate', TJSONNumber.Create(State.Rate));
    StateJson.AddPair('scale', TJSONNumber.Create(State.Scale));
    StateJson.AddPair('sample_rate', TJSONNumber.Create(State.SampleRate));
    StateJson.AddPair('cursor_frame', TJSONNumber.Create(State.CursorFrame));
    if State.Rate > 0 then
      CursorSeconds := State.CursorFrame * State.Scale / State.Rate
    else
      CursorSeconds := 0;
    StateJson.AddPair('cursor_seconds', TJSONNumber.Create(CursorSeconds));
    StateJson.AddPair('cursor_layer', TJSONNumber.Create(State.CursorLayer));
    StateJson.AddPair('frame_max', TJSONNumber.Create(State.FrameMax));
    StateJson.AddPair('layer_max', TJSONNumber.Create(State.LayerMax));
    StateJson.AddPair('display_frame_start',
      TJSONNumber.Create(State.DisplayFrameStart));
    StateJson.AddPair('display_layer_start',
      TJSONNumber.Create(State.DisplayLayerStart));
    StateJson.AddPair('display_frame_num',
      TJSONNumber.Create(State.DisplayFrameNum));
    StateJson.AddPair('display_layer_num',
      TJSONNumber.Create(State.DisplayLayerNum));
    StateJson.AddPair('select_range_start',
      TJSONNumber.Create(State.SelectRangeStart));
    StateJson.AddPair('select_range_end',
      TJSONNumber.Create(State.SelectRangeEnd));
    StateJson.AddPair('has_select_range', TJSONBool.Create(
      (State.SelectRangeStart >= 0) and (State.SelectRangeEnd >= 0)));
    StateJson.AddPair('selected_count',
      TJSONNumber.Create(State.SelectedCount));
    StateJson.AddPair('grid_bpm_tempo',
      TJSONNumber.Create(State.GridBpmTempo));
    StateJson.AddPair('grid_bpm_beat',
      TJSONNumber.Create(State.GridBpmBeat));
    StateJson.AddPair('grid_bpm_offset',
      TJSONNumber.Create(State.GridBpmOffset));
    StateJson.AddPair('elapsed_ms',
      TJSONNumber.Create(Int64(State.ElapsedMs)));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function BuildFrameImageResponse(const Image: TAul2MIRAIFrameImage;
  const Identity: TAul2MIRAISnapshotIdentity): string;
var
  ImageJson: TJSONObject;
  Root     : TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddProtocolHeader(Root);
    AddSnapshotIdentity(Root, Identity);
    Root.AddPair('status', 'ok');
    Root.AddPair('command', AUL2MIRAI_COMMAND_CURRENT_FRAME_IMAGE);
    ImageJson := TJSONObject.Create;
    Root.AddPair('image', ImageJson);
    ImageJson.AddPair('file_path', Image.FilePath);
    ImageJson.AddPair('format', Image.Format);
    ImageJson.AddPair('captured_at_utc', Image.CapturedAtUtc);
    ImageJson.AddPair('frame', TJSONNumber.Create(Image.Frame));
    ImageJson.AddPair('width', TJSONNumber.Create(Image.Width));
    ImageJson.AddPair('height', TJSONNumber.Create(Image.Height));
    ImageJson.AddPair('file_size', TJSONNumber.Create(Image.FileSize));
    ImageJson.AddPair('elapsed_ms',
      TJSONNumber.Create(Int64(Image.ElapsedMs)));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function BuildSceneObjectsResponse(const Command: string;
  const Snapshot: TAul2MIRAISceneSnapshot;
  const Identity: TAul2MIRAISnapshotIdentity): string;
var
  Detail      : TAul2MIRAIEffectDetail;
  DetailJson  : TJSONObject;
  DetailsJson : TJSONArray;
  EffectName  : string;
  EffectState : TAul2MIRAIEffectState;
  EffectStateJson: TJSONObject;
  EffectStatesJson: TJSONArray;
  EffectsJson : TJSONArray;
  Item        : TAul2MIRAIObjectInfo; // JSONへ追加中のオブジェクト
  ItemJson    : TJSONObject;          // 1オブジェクト分のJSON
  Items       : TJSONArray;           // オブジェクト一覧
  LayerInfo   : TAul2MIRAILayerInfo;
  LayerJson   : TJSONObject;
  LayersJson  : TJSONArray;
  Parameter   : TAul2MIRAIParameterInfo;
  ParameterJson: TJSONObject;
  ParametersJson: TJSONArray;
  Root        : TJSONObject;          // 応答全体
  SectionFrame: Integer;
  SectionsJson: TJSONArray;
  SnapshotJson: TJSONObject;          // シーンスナップショット
  TrackGroupJson: TJSONObject;
  TrackJson   : TJSONObject;
  TrackValue  : Double;
  TrackValuesJson: TJSONArray;
begin
  Root := TJSONObject.Create;
  try
    AddProtocolHeader(Root);
    AddSnapshotIdentity(Root, Identity);
    Root.AddPair('status', 'ok');
    Root.AddPair('command', Command);

    SnapshotJson := TJSONObject.Create;
    Root.AddPair('snapshot', SnapshotJson);
    SnapshotJson.AddPair('scene_id', TJSONNumber.Create(Snapshot.SceneId));
    SnapshotJson.AddPair('width', TJSONNumber.Create(Snapshot.Width));
    SnapshotJson.AddPair('height', TJSONNumber.Create(Snapshot.Height));
    SnapshotJson.AddPair('rate', TJSONNumber.Create(Snapshot.Rate));
    SnapshotJson.AddPair('scale', TJSONNumber.Create(Snapshot.Scale));
    SnapshotJson.AddPair('cursor_frame', TJSONNumber.Create(Snapshot.CursorFrame));
    SnapshotJson.AddPair('layer_max', TJSONNumber.Create(Snapshot.LayerMax));
    SnapshotJson.AddPair('selected_count', TJSONNumber.Create(Snapshot.SelectedCount));
    SnapshotJson.AddPair('elapsed_ms', TJSONNumber.Create(Int64(Snapshot.ElapsedMs)));

    LayersJson := TJSONArray.Create;
    SnapshotJson.AddPair('layers', LayersJson);
    for LayerInfo in Snapshot.Layers do
    begin
      LayerJson := TJSONObject.Create;
      LayerJson.AddPair('index', TJSONNumber.Create(LayerInfo.Index));
      LayerJson.AddPair('name', LayerInfo.Name);
      LayerJson.AddPair('state_available',
        TJSONBool.Create(LayerInfo.StateAvailable));
      if LayerInfo.StateAvailable then
      begin
        LayerJson.AddPair('enabled', TJSONBool.Create(LayerInfo.Enabled));
        LayerJson.AddPair('locked', TJSONBool.Create(LayerInfo.Locked));
      end;
      LayersJson.AddElement(LayerJson);
    end;

    Items := TJSONArray.Create;
    SnapshotJson.AddPair('objects', Items);
    for Item in Snapshot.Objects do
    begin
      ItemJson := TJSONObject.Create;
      ItemJson.AddPair('index', TJSONNumber.Create(Item.Index));
      ItemJson.AddPair('layer', TJSONNumber.Create(Item.Layer));
      ItemJson.AddPair('start_frame', TJSONNumber.Create(Item.StartFrame));
      ItemJson.AddPair('end_frame', TJSONNumber.Create(Item.EndFrame));
      ItemJson.AddPair('selected', TJSONBool.Create(Item.Selected));
      ItemJson.AddPair('focused', TJSONBool.Create(Item.Focused));
      ItemJson.AddPair('name', Item.Name);
      ItemJson.AddPair('primary_effect', Item.PrimaryEffect);
      ItemJson.AddPair('object_type', Item.ObjectType);
      ItemJson.AddPair('material_path', Item.MaterialPath);
      ItemJson.AddPair('content_digest', 'sha256:' + Item.ContentDigest);
      ItemJson.AddPair('section_count',
        TJSONNumber.Create(Length(Item.SectionFrames)));
      ItemJson.AddPair('focused_section',
        TJSONNumber.Create(Item.FocusedSection));
      SectionsJson := TJSONArray.Create;
      ItemJson.AddPair('section_frames', SectionsJson);
      for SectionFrame in Item.SectionFrames do
        SectionsJson.Add(SectionFrame);
      EffectsJson := TJSONArray.Create;
      ItemJson.AddPair('effects', EffectsJson);
      for EffectName in Item.Effects do
        EffectsJson.Add(EffectName);
      EffectStatesJson := TJSONArray.Create;
      ItemJson.AddPair('effect_states', EffectStatesJson);
      for EffectState in Item.EffectStates do
      begin
        EffectStateJson := TJSONObject.Create;
        EffectStateJson.AddPair('name', EffectState.Name);
        EffectStateJson.AddPair('enabled',
          TJSONBool.Create(EffectState.Enabled));
        EffectStateJson.AddPair('locked',
          TJSONBool.Create(EffectState.Locked));
        EffectStatesJson.AddElement(EffectStateJson);
      end;
      if Length(Item.EffectDetails) > 0 then
      begin
        DetailsJson := TJSONArray.Create;
        ItemJson.AddPair('effect_details', DetailsJson);
        for Detail in Item.EffectDetails do
        begin
          DetailJson := TJSONObject.Create;
          DetailJson.AddPair('name', Detail.Name);
          DetailJson.AddPair('state_available',
            TJSONBool.Create(Detail.StateAvailable));
          if Detail.StateAvailable then
          begin
            DetailJson.AddPair('enabled',
              TJSONBool.Create(Detail.Enabled));
            DetailJson.AddPair('locked',
              TJSONBool.Create(Detail.Locked));
          end;
          ParametersJson := TJSONArray.Create;
          DetailJson.AddPair('parameters', ParametersJson);
          for Parameter in Detail.Parameters do
          begin
            ParameterJson := TJSONObject.Create;
            ParameterJson.AddPair('name', Parameter.Name);
            ParameterJson.AddPair('value', Parameter.Value);
            ParameterJson.AddPair('truncated',
              TJSONBool.Create(Parameter.Truncated));
            if Parameter.TrackInfoAvailable then
            begin
              TrackJson := TJSONObject.Create;
              ParameterJson.AddPair('track_info', TrackJson);
              TrackJson.AddPair('mode', Parameter.TrackMode);
              TrackValuesJson := TJSONArray.Create;
              TrackJson.AddPair('parameter_values', TrackValuesJson);
              for TrackValue in Parameter.TrackParameters do
                TrackValuesJson.Add(TrackValue);
              TrackJson.AddPair('accelerate',
                TJSONBool.Create(Parameter.TrackAccelerate));
              TrackJson.AddPair('decelerate',
                TJSONBool.Create(Parameter.TrackDecelerate));
              TrackJson.AddPair('ignore_midpoint',
                TJSONBool.Create(Parameter.TrackIgnoreMidpoint));
              TrackJson.AddPair('time_control',
                TJSONBool.Create(Parameter.TrackTimeControl));
              TrackGroupJson := TJSONObject.Create;
              TrackJson.AddPair('group', TrackGroupJson);
              TrackGroupJson.AddPair('name', Parameter.TrackGroupName);
              TrackGroupJson.AddPair('count',
                TJSONNumber.Create(Parameter.TrackGroupCount));
              TrackGroupJson.AddPair('index',
                TJSONNumber.Create(Parameter.TrackGroupIndex));
            end
            else
              ParameterJson.AddPair('track_info', TJSONNull.Create);
            ParametersJson.AddElement(ParameterJson);
          end;
          DetailsJson.AddElement(DetailJson);
        end;
      end;
      Items.AddElement(ItemJson);
    end;

    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function BuildProtocolError(const Command, ErrorCode, ErrorMessage: string): string;
var
  ErrorJson: TJSONObject;
  Root     : TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddProtocolHeader(Root);
    Root.AddPair('status', 'error');
    Root.AddPair('command', Command);
    ErrorJson := TJSONObject.Create;
    ErrorJson.AddPair('code', ErrorCode);
    ErrorJson.AddPair('message', ErrorMessage);
    Root.AddPair('error', ErrorJson);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function BuildParameterPreviewResponse(
  const Preview: TAul2MIRAIParameterPreview;
  const Identity: TAul2MIRAISnapshotIdentity): string;
var
  EffectJson : TJSONObject;
  PreviewJson: TJSONObject;
  Root       : TJSONObject;
  TargetJson : TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddProtocolHeader(Root);
    AddSnapshotIdentity(Root, Identity);
    Root.AddPair('status', 'ok');
    Root.AddPair('command', AUL2MIRAI_COMMAND_PREVIEW_PARAMETER);
    PreviewJson := TJSONObject.Create;
    Root.AddPair('preview', PreviewJson);
    PreviewJson.AddPair('operation', 'set_object_parameter');
    PreviewJson.AddPair('applied', TJSONBool.Create(False));
    PreviewJson.AddPair('will_change',
      TJSONBool.Create(Preview.WillChange));

    TargetJson := TJSONObject.Create;
    PreviewJson.AddPair('target', TargetJson);
    TargetJson.AddPair('index', TJSONNumber.Create(Preview.TargetIndex));
    TargetJson.AddPair('layer', TJSONNumber.Create(Preview.Layer));
    TargetJson.AddPair('start_frame',
      TJSONNumber.Create(Preview.StartFrame));
    TargetJson.AddPair('end_frame', TJSONNumber.Create(Preview.EndFrame));
    TargetJson.AddPair('object_type', Preview.ObjectType);
    TargetJson.AddPair('primary_effect', Preview.PrimaryEffect);

    EffectJson := TJSONObject.Create;
    PreviewJson.AddPair('effect', EffectJson);
    EffectJson.AddPair('index', TJSONNumber.Create(Preview.EffectIndex));
    EffectJson.AddPair('name', Preview.EffectName);
    PreviewJson.AddPair('item', Preview.ItemName);
    PreviewJson.AddPair('before', Preview.BeforeValue);
    PreviewJson.AddPair('after', Preview.AfterValue);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function BuildParameterSetResponse(const Preview: TAul2MIRAIParameterPreview;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity;
  Applied: Boolean; const VerifiedValue: string): string;
var
  ChangeJson: TJSONObject;
  EffectJson: TJSONObject;
  Root      : TJSONObject;
  TargetJson: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddProtocolHeader(Root);
    AddSnapshotIdentity(Root, AfterIdentity);
    Root.AddPair('status', 'ok');
    Root.AddPair('command', AUL2MIRAI_COMMAND_SET_PARAMETER);
    ChangeJson := TJSONObject.Create;
    Root.AddPair('change', ChangeJson);
    ChangeJson.AddPair('operation', 'set_object_parameter');
    ChangeJson.AddPair('applied', TJSONBool.Create(Applied));
    ChangeJson.AddPair('changed', TJSONBool.Create(Preview.WillChange));
    ChangeJson.AddPair('previous_state_token', BeforeIdentity.StateToken);

    TargetJson := TJSONObject.Create;
    ChangeJson.AddPair('target', TargetJson);
    TargetJson.AddPair('index', TJSONNumber.Create(Preview.TargetIndex));
    TargetJson.AddPair('layer', TJSONNumber.Create(Preview.Layer));
    TargetJson.AddPair('start_frame',
      TJSONNumber.Create(Preview.StartFrame));
    TargetJson.AddPair('end_frame', TJSONNumber.Create(Preview.EndFrame));
    TargetJson.AddPair('object_type', Preview.ObjectType);
    TargetJson.AddPair('primary_effect', Preview.PrimaryEffect);

    EffectJson := TJSONObject.Create;
    ChangeJson.AddPair('effect', EffectJson);
    EffectJson.AddPair('index', TJSONNumber.Create(Preview.EffectIndex));
    EffectJson.AddPair('name', Preview.EffectName);
    ChangeJson.AddPair('item', Preview.ItemName);
    ChangeJson.AddPair('before', Preview.BeforeValue);
    ChangeJson.AddPair('requested', Preview.AfterValue);
    ChangeJson.AddPair('verified', VerifiedValue);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function BuildStateChangedError(const Command, ExpectedStateToken: string;
  const Identity: TAul2MIRAISnapshotIdentity): string;
var
  ErrorJson: TJSONObject;
  Root     : TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddProtocolHeader(Root);
    AddSnapshotIdentity(Root, Identity);
    Root.AddPair('status', 'error');
    Root.AddPair('command', Command);
    ErrorJson := TJSONObject.Create;
    ErrorJson.AddPair('code', 'state_changed');
    ErrorJson.AddPair('message',
      'The current AviUtl2 state does not match state_token.');
    ErrorJson.AddPair('expected_state_token', ExpectedStateToken);
    ErrorJson.AddPair('current_state_token', Identity.StateToken);
    Root.AddPair('error', ErrorJson);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function IsSuccessfulResponse(const ResponseText: string): Boolean;
var
  Json       : TJSONValue;
  StatusValue: TJSONValue;
begin
  Result := False;
  Json := TJSONObject.ParseJSONValue(ResponseText);
  try
    if not (Json is TJSONObject) then
      Exit;

    StatusValue := TJSONObject(Json).GetValue('status');
    Result := (StatusValue is TJSONString) and
      SameText(TJSONString(StatusValue).Value, 'ok');
  finally
    Json.Free;
  end;
end;

end.
