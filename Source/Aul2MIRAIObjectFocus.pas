unit Aul2MIRAIObjectFocus;

// Parses, validates, and formats a safe object focus change using copied
// scene data. The SDK object handle is resolved again by the writer.

interface

uses
  Aul2MIRAIObjectTypes,
  Aul2MIRAISnapshotIdentity;

type
  TAul2MIRAIObjectFocusTarget = record
    Index        : Integer;
    Layer        : Integer;
    StartFrame   : Integer;
    EndFrame     : Integer;
    ObjectType   : string;
    Name         : string;
    ContentDigest: string;
  end;

  TAul2MIRAIObjectFocusPreview = record
    Target              : TAul2MIRAIObjectFocusTarget;
    BeforeFocusAvailable: Boolean;
    BeforeFocus         : TAul2MIRAIObjectFocusTarget;
    WillChange          : Boolean;
  end;

function ParseObjectFocusRequest(const RequestText: string;
  RequireApply: Boolean; out StateToken: string; out TargetIndex: Integer;
  out ErrorCode, ErrorMessage: string): Boolean;
function CreateObjectFocusPreview(const Snapshot: TAul2MIRAISceneSnapshot;
  TargetIndex: Integer; out Preview: TAul2MIRAIObjectFocusPreview;
  out ErrorCode, ErrorMessage: string): Boolean;
function BuildObjectFocusPreviewResponse(
  const Preview: TAul2MIRAIObjectFocusPreview;
  const Identity: TAul2MIRAISnapshotIdentity): string;
function BuildObjectFocusResponse(
  const Preview: TAul2MIRAIObjectFocusPreview;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity): string;

implementation

uses
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  Aul2MIRAIProtocol;

function CopyFocusTarget(const Item: TAul2MIRAIObjectInfo):
  TAul2MIRAIObjectFocusTarget;
begin
  Result.Index := Item.Index;
  Result.Layer := Item.Layer;
  Result.StartFrame := Item.StartFrame;
  Result.EndFrame := Item.EndFrame;
  Result.ObjectType := Item.ObjectType;
  Result.Name := Item.Name;
  Result.ContentDigest := Item.ContentDigest;
end;

function FindSnapshotObject(const Snapshot: TAul2MIRAISceneSnapshot;
  TargetIndex: Integer; out Item: TAul2MIRAIObjectInfo): Boolean;
var
  Candidate: TAul2MIRAIObjectInfo;
begin
  for Candidate in Snapshot.Objects do
    if Candidate.Index = TargetIndex then
    begin
      Item := Candidate;
      Exit(True);
    end;
  Item := Default(TAul2MIRAIObjectInfo);
  Result := False;
end;

function ParseObjectFocusRequest(const RequestText: string;
  RequireApply: Boolean; out StateToken: string; out TargetIndex: Integer;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  ApplyValue: TJSONValue;
  Json      : TJSONValue;
  Root      : TJSONObject;
  Value     : TJSONValue;
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
    Value := Root.GetValue('state_token');
    if not (Value is TJSONString) then
    begin
      ErrorCode := 'invalid_state_token';
      ErrorMessage := 'state_token must be a string.';
      Exit;
    end;
    StateToken := TJSONString(Value).Value;
    if (Length(StateToken) <> 71) or
       not StartsText('sha256:', StateToken) then
    begin
      ErrorCode := 'invalid_state_token';
      ErrorMessage := 'state_token must be a SHA-256 token.';
      Exit;
    end;
    Value := Root.GetValue('target_index');
    if not ((Value is TJSONNumber) and
      TryStrToInt(Value.Value, TargetIndex)) then
    begin
      ErrorCode := 'invalid_target_index';
      ErrorMessage := 'target_index must be an integer.';
      Exit;
    end;
    if TargetIndex < 0 then
    begin
      ErrorCode := 'invalid_target_index';
      ErrorMessage := 'target_index must be zero or greater.';
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
        ErrorMessage := 'apply must be true to change object focus.';
        Exit;
      end;
    end;
    Result := True;
  finally
    Json.Free;
  end;
end;

function CreateObjectFocusPreview(const Snapshot: TAul2MIRAISceneSnapshot;
  TargetIndex: Integer; out Preview: TAul2MIRAIObjectFocusPreview;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  Item: TAul2MIRAIObjectInfo;
begin
  Result := False;
  Preview := Default(TAul2MIRAIObjectFocusPreview);
  ErrorCode := '';
  ErrorMessage := '';
  if not FindSnapshotObject(Snapshot, TargetIndex, Item) then
  begin
    ErrorCode := 'target_not_found';
    ErrorMessage := Format('Object index %d was not found.', [TargetIndex]);
    Exit;
  end;
  Preview.Target := CopyFocusTarget(Item);
  Preview.WillChange := not Item.Focused;
  for Item in Snapshot.Objects do
    if Item.Focused then
    begin
      Preview.BeforeFocusAvailable := True;
      Preview.BeforeFocus := CopyFocusTarget(Item);
      Break;
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

function BuildTargetJson(const Target: TAul2MIRAIObjectFocusTarget):
  TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('index', TJSONNumber.Create(Target.Index));
  Result.AddPair('object_type', Target.ObjectType);
  Result.AddPair('name', Target.Name);
  Result.AddPair('layer', TJSONNumber.Create(Target.Layer));
  Result.AddPair('start_frame', TJSONNumber.Create(Target.StartFrame));
  Result.AddPair('end_frame', TJSONNumber.Create(Target.EndFrame));
end;

function BuildFocusJson(const Preview: TAul2MIRAIObjectFocusPreview;
  IncludeResult: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('operation', 'set_focus_object');
  Result.AddPair('will_change', TJSONBool.Create(Preview.WillChange));
  Result.AddPair('target', BuildTargetJson(Preview.Target));
  if Preview.BeforeFocusAvailable then
    Result.AddPair('before', BuildTargetJson(Preview.BeforeFocus))
  else
    Result.AddPair('before', TJSONNull.Create);
  if IncludeResult then
    Result.AddPair('applied', TJSONBool.Create(Preview.WillChange));
end;

function BuildObjectFocusPreviewResponse(
  const Preview: TAul2MIRAIObjectFocusPreview;
  const Identity: TAul2MIRAISnapshotIdentity): string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root, Identity, AUL2MIRAI_COMMAND_PREVIEW_FOCUS_OBJECT);
    Root.AddPair('preview', BuildFocusJson(Preview, False));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function BuildObjectFocusResponse(
  const Preview: TAul2MIRAIObjectFocusPreview;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity): string;
var
  ChangeJson: TJSONObject;
  Root      : TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root, AfterIdentity, AUL2MIRAI_COMMAND_SET_FOCUS_OBJECT);
    ChangeJson := BuildFocusJson(Preview, True);
    ChangeJson.AddPair('previous_state_token', BeforeIdentity.StateToken);
    Root.AddPair('change', ChangeJson);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

end.
