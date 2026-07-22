unit Aul2MIRAIProtocol;

// Named Pipeで交換するJSONプロトコルの定数、検証、応答生成を担当する。

interface

uses
  Aul2MIRAIObjectTypes;

const
  AUL2MIRAI_PIPE_SHORT_NAME  = 'Aul2MIRAI.v1';
  AUL2MIRAI_PIPE_NAME        = '\\.\pipe\Aul2MIRAI.v1';
  AUL2MIRAI_PROTOCOL_NAME    = 'Aul2MIRAI';
  AUL2MIRAI_PROTOCOL_VERSION = 1;
  AUL2MIRAI_COMMAND_OBJECTS  = 'get_scene_objects';

function BuildProtocolRequest(const Command: string): string;
function ParseProtocolRequest(const RequestText: string;
  out Command, ErrorCode, ErrorMessage: string): Boolean;
function BuildSceneObjectsResponse(const Snapshot: TAul2MIRAISceneSnapshot): string;
function BuildProtocolError(const Command, ErrorCode, ErrorMessage: string): string;
function IsSuccessfulResponse(const ResponseText: string): Boolean;

implementation

uses
  System.SysUtils,
  System.JSON;

procedure AddProtocolHeader(Json: TJSONObject);
begin
  Json.AddPair('protocol', AUL2MIRAI_PROTOCOL_NAME);
  Json.AddPair('protocol_version', TJSONNumber.Create(AUL2MIRAI_PROTOCOL_VERSION));
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

function BuildSceneObjectsResponse(const Snapshot: TAul2MIRAISceneSnapshot): string;
var
  Item        : TAul2MIRAIObjectInfo; // JSONへ追加中のオブジェクト
  ItemJson    : TJSONObject;          // 1オブジェクト分のJSON
  Items       : TJSONArray;           // オブジェクト一覧
  Root        : TJSONObject;          // 応答全体
  SnapshotJson: TJSONObject;          // シーンスナップショット
begin
  Root := TJSONObject.Create;
  try
    AddProtocolHeader(Root);
    Root.AddPair('status', 'ok');
    Root.AddPair('command', AUL2MIRAI_COMMAND_OBJECTS);

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
      ItemJson.AddPair('name', Item.Name);
      ItemJson.AddPair('primary_effect', Item.PrimaryEffect);
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
