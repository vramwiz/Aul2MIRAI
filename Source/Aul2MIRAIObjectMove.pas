unit Aul2MIRAIObjectMove;

// Parses and validates atomic object move requests using copied scene data.

interface

uses
  Aul2MIRAIObjectTypes,
  Aul2MIRAISnapshotIdentity;

type
  TAul2MIRAIObjectMoveRequest = record
    TargetIndex : Integer;
    Layer       : Integer;
    Frame       : Integer;
  end;

  TAul2MIRAIObjectMovePreview = record
    TargetIndex  : Integer;
    ObjectType   : string;
    Name         : string;
    ContentDigest: string;
    BeforeLayer  : Integer;
    BeforeStart  : Integer;
    BeforeEnd    : Integer;
    AfterLayer   : Integer;
    AfterStart   : Integer;
    AfterEnd     : Integer;
    WillMove     : Boolean;
  end;

function ParseObjectMoveRequest(const RequestText: string;
  RequireApply: Boolean; out StateToken: string;
  out Moves: TArray<TAul2MIRAIObjectMoveRequest>;
  out ErrorCode, ErrorMessage: string): Boolean;
function CreateObjectMovePreviews(const Snapshot: TAul2MIRAISceneSnapshot;
  const Moves: TArray<TAul2MIRAIObjectMoveRequest>;
  out Previews: TArray<TAul2MIRAIObjectMovePreview>;
  out ErrorCode, ErrorMessage: string): Boolean;
function BuildObjectMovePreviewResponse(
  const Previews: TArray<TAul2MIRAIObjectMovePreview>;
  const Identity: TAul2MIRAISnapshotIdentity): string;
function BuildObjectMoveResponse(
  const Previews: TArray<TAul2MIRAIObjectMovePreview>;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity): string;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  Aul2MIRAIProtocol;

const
  MAX_MOVE_COUNT = 64;
  MAX_MOVE_FRAME = 2000000000;
  MAX_MOVE_LAYER = 9999;

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

function ParseObjectMoveRequest(const RequestText: string;
  RequireApply: Boolean; out StateToken: string;
  out Moves: TArray<TAul2MIRAIObjectMoveRequest>;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  ApplyValue: TJSONValue;
  I         : Integer;
  Json      : TJSONValue;
  MoveJson  : TJSONValue;
  MovesJson : TJSONArray;
  Root      : TJSONObject;
begin
  Result := False;
  StateToken := '';
  SetLength(Moves, 0);
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
    MoveJson := Root.GetValue('state_token');
    if not (MoveJson is TJSONString) then
    begin
      ErrorCode := 'invalid_state_token';
      ErrorMessage := 'state_token must be a string.';
      Exit;
    end;
    StateToken := TJSONString(MoveJson).Value;
    if (Length(StateToken) <> 71) or
       not StartsText('sha256:', StateToken) then
    begin
      ErrorCode := 'invalid_state_token';
      ErrorMessage := 'state_token must be a SHA-256 token.';
      Exit;
    end;

    MoveJson := Root.GetValue('moves');
    if not (MoveJson is TJSONArray) then
    begin
      ErrorCode := 'invalid_moves';
      ErrorMessage := 'moves must be an array.';
      Exit;
    end;
    MovesJson := TJSONArray(MoveJson);
    if MovesJson.Count = 0 then
    begin
      ErrorCode := 'empty_moves';
      ErrorMessage := 'At least one move is required.';
      Exit;
    end;
    if MovesJson.Count > MAX_MOVE_COUNT then
    begin
      ErrorCode := 'too_many_moves';
      ErrorMessage := Format('moves exceeds the %d item limit.',
        [MAX_MOVE_COUNT]);
      Exit;
    end;

    SetLength(Moves, MovesJson.Count);
    for I := 0 to MovesJson.Count - 1 do
    begin
      MoveJson := MovesJson.Items[I];
      if not (MoveJson is TJSONObject) then
      begin
        ErrorCode := 'invalid_move';
        ErrorMessage := Format('moves[%d] must be an object.', [I]);
        Exit;
      end;
      if not RequireInteger(TJSONObject(MoveJson), 'target_index',
        Moves[I].TargetIndex, ErrorCode, ErrorMessage) or
         not RequireInteger(TJSONObject(MoveJson), 'layer',
        Moves[I].Layer, ErrorCode, ErrorMessage) or
         not RequireInteger(TJSONObject(MoveJson), 'frame',
        Moves[I].Frame, ErrorCode, ErrorMessage) then
      begin
        ErrorMessage := Format('moves[%d]: %s', [I, ErrorMessage]);
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

function CreateObjectMovePreviews(const Snapshot: TAul2MIRAISceneSnapshot;
  const Moves: TArray<TAul2MIRAIObjectMoveRequest>;
  out Previews: TArray<TAul2MIRAIObjectMovePreview>;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  Duration: Int64;
  I       : Integer;
  J       : Integer;
  Item    : TAul2MIRAIObjectInfo;
  Other   : TAul2MIRAIObjectInfo;
begin
  Result := False;
  SetLength(Previews, Length(Moves));
  ErrorCode := '';
  ErrorMessage := '';
  for I := 0 to High(Moves) do
  begin
    for J := 0 to I - 1 do
      if Moves[J].TargetIndex = Moves[I].TargetIndex then
      begin
        ErrorCode := 'duplicate_move';
        ErrorMessage := Format(
          'moves[%d] duplicates target_index in moves[%d].', [I, J]);
        Exit;
      end;
    if (Moves[I].Layer < 0) or (Moves[I].Layer > MAX_MOVE_LAYER) then
    begin
      ErrorCode := 'invalid_layer';
      ErrorMessage := Format('moves[%d].layer is outside the safe range.',
        [I]);
      Exit;
    end;
    if (Moves[I].Frame < 0) or (Moves[I].Frame > MAX_MOVE_FRAME) then
    begin
      ErrorCode := 'invalid_frame';
      ErrorMessage := Format('moves[%d].frame is outside the safe range.',
        [I]);
      Exit;
    end;
    if not FindSnapshotObject(Snapshot, Moves[I].TargetIndex, Item) then
    begin
      ErrorCode := 'target_not_found';
      ErrorMessage := Format('moves[%d]: target object was not found.', [I]);
      Exit;
    end;
    if not Item.Selected then
    begin
      ErrorCode := 'target_not_selected';
      ErrorMessage := Format('moves[%d]: target object is not selected.', [I]);
      Exit;
    end;

    Duration := Int64(Item.EndFrame) - Item.StartFrame;
    if Int64(Moves[I].Frame) + Duration > MAX_MOVE_FRAME then
    begin
      ErrorCode := 'invalid_frame';
      ErrorMessage := Format('moves[%d] would exceed the safe frame range.',
        [I]);
      Exit;
    end;
    Previews[I].TargetIndex := Item.Index;
    Previews[I].ObjectType := Item.ObjectType;
    Previews[I].Name := Item.Name;
    Previews[I].ContentDigest := Item.ContentDigest;
    Previews[I].BeforeLayer := Item.Layer;
    Previews[I].BeforeStart := Item.StartFrame;
    Previews[I].BeforeEnd := Item.EndFrame;
    Previews[I].AfterLayer := Moves[I].Layer;
    Previews[I].AfterStart := Moves[I].Frame;
    Previews[I].AfterEnd := Moves[I].Frame + Integer(Duration);
    Previews[I].WillMove := (Item.Layer <> Moves[I].Layer) or
      (Item.StartFrame <> Moves[I].Frame);
  end;

  for I := 0 to High(Previews) do
    if Previews[I].WillMove then
    begin
      for Other in Snapshot.Objects do
        if (Other.Index <> Previews[I].TargetIndex) and
           (Other.Layer = Previews[I].AfterLayer) and
           RangesOverlap(Other.StartFrame, Other.EndFrame,
             Previews[I].AfterStart, Previews[I].AfterEnd) then
        begin
          ErrorCode := 'destination_occupied';
          ErrorMessage := Format(
            'moves[%d] overlaps object index %d at the destination.',
            [I, Other.Index]);
          Exit;
        end;
      for J := 0 to I - 1 do
        if (Previews[J].AfterLayer = Previews[I].AfterLayer) and
           RangesOverlap(Previews[J].AfterStart, Previews[J].AfterEnd,
             Previews[I].AfterStart, Previews[I].AfterEnd) then
        begin
          ErrorCode := 'destination_conflict';
          ErrorMessage := Format(
            'moves[%d] overlaps the destination in moves[%d].', [I, J]);
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

function CountMoved(
  const Previews: TArray<TAul2MIRAIObjectMovePreview>): Integer;
var
  Preview: TAul2MIRAIObjectMovePreview;
begin
  Result := 0;
  for Preview in Previews do
    if Preview.WillMove then
      Inc(Result);
end;

function BuildMoveJson(const Preview: TAul2MIRAIObjectMovePreview;
  IncludeResult: Boolean): TJSONObject;
var
  AfterJson : TJSONObject;
  BeforeJson: TJSONObject;
  TargetJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  TargetJson := TJSONObject.Create;
  Result.AddPair('target', TargetJson);
  TargetJson.AddPair('index', TJSONNumber.Create(Preview.TargetIndex));
  TargetJson.AddPair('object_type', Preview.ObjectType);
  TargetJson.AddPair('name', Preview.Name);
  BeforeJson := TJSONObject.Create;
  Result.AddPair('before', BeforeJson);
  BeforeJson.AddPair('layer', TJSONNumber.Create(Preview.BeforeLayer));
  BeforeJson.AddPair('start_frame', TJSONNumber.Create(Preview.BeforeStart));
  BeforeJson.AddPair('end_frame', TJSONNumber.Create(Preview.BeforeEnd));
  AfterJson := TJSONObject.Create;
  Result.AddPair('after', AfterJson);
  AfterJson.AddPair('layer', TJSONNumber.Create(Preview.AfterLayer));
  AfterJson.AddPair('start_frame', TJSONNumber.Create(Preview.AfterStart));
  AfterJson.AddPair('end_frame', TJSONNumber.Create(Preview.AfterEnd));
  Result.AddPair('will_move', TJSONBool.Create(Preview.WillMove));
  if IncludeResult then
    Result.AddPair('applied', TJSONBool.Create(Preview.WillMove));
end;

function BuildObjectMovePreviewResponse(
  const Previews: TArray<TAul2MIRAIObjectMovePreview>;
  const Identity: TAul2MIRAISnapshotIdentity): string;
var
  I          : Integer;
  Items      : TJSONArray;
  PreviewJson: TJSONObject;
  Root       : TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root, Identity, AUL2MIRAI_COMMAND_PREVIEW_MOVE_OBJECTS);
    PreviewJson := TJSONObject.Create;
    Root.AddPair('preview', PreviewJson);
    PreviewJson.AddPair('operation', 'move_objects');
    PreviewJson.AddPair('applied', TJSONBool.Create(False));
    PreviewJson.AddPair('move_count', TJSONNumber.Create(Length(Previews)));
    PreviewJson.AddPair('moved_count', TJSONNumber.Create(CountMoved(Previews)));
    Items := TJSONArray.Create;
    PreviewJson.AddPair('moves', Items);
    for I := 0 to High(Previews) do
      Items.AddElement(BuildMoveJson(Previews[I], False));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function BuildObjectMoveResponse(
  const Previews: TArray<TAul2MIRAIObjectMovePreview>;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity): string;
var
  ChangeJson: TJSONObject;
  I         : Integer;
  Items     : TJSONArray;
  MovedCount: Integer;
  Root      : TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root, AfterIdentity, AUL2MIRAI_COMMAND_MOVE_OBJECTS);
    MovedCount := CountMoved(Previews);
    ChangeJson := TJSONObject.Create;
    Root.AddPair('change', ChangeJson);
    ChangeJson.AddPair('operation', 'move_objects');
    ChangeJson.AddPair('applied', TJSONBool.Create(MovedCount > 0));
    ChangeJson.AddPair('move_count', TJSONNumber.Create(Length(Previews)));
    ChangeJson.AddPair('moved_count', TJSONNumber.Create(MovedCount));
    ChangeJson.AddPair('previous_state_token', BeforeIdentity.StateToken);
    Items := TJSONArray.Create;
    ChangeJson.AddPair('moves', Items);
    for I := 0 to High(Previews) do
      Items.AddElement(BuildMoveJson(Previews[I], True));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

end.
