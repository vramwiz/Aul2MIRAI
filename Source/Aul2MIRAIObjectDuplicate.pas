unit Aul2MIRAIObjectDuplicate;

// Parses, validates, and formats atomic object duplication requests using
// copied scene snapshots only.

interface

uses
  Aul2MIRAIObjectTypes,
  Aul2MIRAISnapshotIdentity;

type
  TAul2MIRAIObjectDuplicateRequest = record
    SourceIndex : Integer;
    Layer       : Integer;
    Frame       : Integer;
  end;

  TAul2MIRAIObjectDuplicatePreview = record
    SourceIndex  : Integer;
    ObjectType   : string;
    Name         : string;
    PrimaryEffect: string;
    ContentDigest: string;
    SourceLayer  : Integer;
    SourceStart  : Integer;
    SourceEnd    : Integer;
    TargetLayer  : Integer;
    TargetStart  : Integer;
    TargetEnd    : Integer;
    FrameLength  : Integer;
  end;

function ParseObjectDuplicateRequest(const RequestText: string;
  RequireApply: Boolean; out StateToken: string;
  out Duplicates: TArray<TAul2MIRAIObjectDuplicateRequest>;
  out ErrorCode, ErrorMessage: string): Boolean;
function CreateObjectDuplicatePreviews(
  const Snapshot: TAul2MIRAISceneSnapshot;
  const Duplicates: TArray<TAul2MIRAIObjectDuplicateRequest>;
  out Previews: TArray<TAul2MIRAIObjectDuplicatePreview>;
  out ErrorCode, ErrorMessage: string): Boolean;
function ResolveCreatedObjectIndices(
  const Snapshot: TAul2MIRAISceneSnapshot;
  const Previews: TArray<TAul2MIRAIObjectDuplicatePreview>;
  out CreatedIndices: TArray<Integer>; out ErrorMessage: string): Boolean;
function BuildObjectDuplicatePreviewResponse(
  const Previews: TArray<TAul2MIRAIObjectDuplicatePreview>;
  const Identity: TAul2MIRAISnapshotIdentity): string;
function BuildObjectDuplicateResponse(
  const Previews: TArray<TAul2MIRAIObjectDuplicatePreview>;
  const CreatedIndices: TArray<Integer>;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity): string;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  Aul2MIRAIProtocol;

const
  MAX_DUPLICATE_COUNT = 64;
  MAX_DUPLICATE_FRAME = 2000000000;
  MAX_DUPLICATE_LAYER = 9999;

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

function ParseObjectDuplicateRequest(const RequestText: string;
  RequireApply: Boolean; out StateToken: string;
  out Duplicates: TArray<TAul2MIRAIObjectDuplicateRequest>;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  ApplyValue    : TJSONValue;
  DuplicateJson: TJSONValue;
  DuplicatesJson: TJSONArray;
  I             : Integer;
  Json          : TJSONValue;
  Root          : TJSONObject;
begin
  Result := False;
  StateToken := '';
  SetLength(Duplicates, 0);
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
    DuplicateJson := Root.GetValue('state_token');
    if not (DuplicateJson is TJSONString) then
    begin
      ErrorCode := 'invalid_state_token';
      ErrorMessage := 'state_token must be a string.';
      Exit;
    end;
    StateToken := TJSONString(DuplicateJson).Value;
    if (Length(StateToken) <> 71) or
       not StartsText('sha256:', StateToken) then
    begin
      ErrorCode := 'invalid_state_token';
      ErrorMessage := 'state_token must be a SHA-256 token.';
      Exit;
    end;

    DuplicateJson := Root.GetValue('duplicates');
    if not (DuplicateJson is TJSONArray) then
    begin
      ErrorCode := 'invalid_duplicates';
      ErrorMessage := 'duplicates must be an array.';
      Exit;
    end;
    DuplicatesJson := TJSONArray(DuplicateJson);
    if DuplicatesJson.Count = 0 then
    begin
      ErrorCode := 'empty_duplicates';
      ErrorMessage := 'At least one duplicate is required.';
      Exit;
    end;
    if DuplicatesJson.Count > MAX_DUPLICATE_COUNT then
    begin
      ErrorCode := 'too_many_duplicates';
      ErrorMessage := Format('duplicates exceeds the %d item limit.',
        [MAX_DUPLICATE_COUNT]);
      Exit;
    end;

    SetLength(Duplicates, DuplicatesJson.Count);
    for I := 0 to DuplicatesJson.Count - 1 do
    begin
      DuplicateJson := DuplicatesJson.Items[I];
      if not (DuplicateJson is TJSONObject) then
      begin
        ErrorCode := 'invalid_duplicate';
        ErrorMessage := Format('duplicates[%d] must be an object.', [I]);
        Exit;
      end;
      if not RequireInteger(TJSONObject(DuplicateJson), 'source_index',
        Duplicates[I].SourceIndex, ErrorCode, ErrorMessage) or
         not RequireInteger(TJSONObject(DuplicateJson), 'layer',
        Duplicates[I].Layer, ErrorCode, ErrorMessage) or
         not RequireInteger(TJSONObject(DuplicateJson), 'frame',
        Duplicates[I].Frame, ErrorCode, ErrorMessage) then
      begin
        ErrorMessage := Format('duplicates[%d]: %s', [I, ErrorMessage]);
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
  SourceIndex: Integer; out Item: TAul2MIRAIObjectInfo): Boolean;
var
  Candidate: TAul2MIRAIObjectInfo;
begin
  for Candidate in Snapshot.Objects do
    if Candidate.Index = SourceIndex then
    begin
      Item := Candidate;
      Exit(True);
    end;
  Item := Default(TAul2MIRAIObjectInfo);
  Result := False;
end;

function CreateObjectDuplicatePreviews(
  const Snapshot: TAul2MIRAISceneSnapshot;
  const Duplicates: TArray<TAul2MIRAIObjectDuplicateRequest>;
  out Previews: TArray<TAul2MIRAIObjectDuplicatePreview>;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  I    : Integer;
  Item : TAul2MIRAIObjectInfo;
  J    : Integer;
  Other: TAul2MIRAIObjectInfo;
begin
  Result := False;
  SetLength(Previews, Length(Duplicates));
  ErrorCode := '';
  ErrorMessage := '';
  for I := 0 to High(Duplicates) do
  begin
    if (Duplicates[I].Layer < 0) or
       (Duplicates[I].Layer > MAX_DUPLICATE_LAYER) then
    begin
      ErrorCode := 'invalid_layer';
      ErrorMessage := Format(
        'duplicates[%d].layer is outside the safe range.', [I]);
      Exit;
    end;
    if (Duplicates[I].Frame < 0) or
       (Duplicates[I].Frame > MAX_DUPLICATE_FRAME) then
    begin
      ErrorCode := 'invalid_frame';
      ErrorMessage := Format(
        'duplicates[%d].frame is outside the safe range.', [I]);
      Exit;
    end;
    if not FindSnapshotObject(Snapshot, Duplicates[I].SourceIndex,
      Item) then
    begin
      ErrorCode := 'source_not_found';
      ErrorMessage := Format(
        'duplicates[%d]: source object was not found.', [I]);
      Exit;
    end;
    if not Item.Selected then
    begin
      ErrorCode := 'source_not_selected';
      ErrorMessage := Format(
        'duplicates[%d]: source object is not selected.', [I]);
      Exit;
    end;
    Previews[I].FrameLength := Item.EndFrame - Item.StartFrame + 1;
    if Int64(Duplicates[I].Frame) + Previews[I].FrameLength - 1 >
       MAX_DUPLICATE_FRAME then
    begin
      ErrorCode := 'invalid_frame';
      ErrorMessage := Format(
        'duplicates[%d] would exceed the safe frame range.', [I]);
      Exit;
    end;
    Previews[I].SourceIndex := Item.Index;
    Previews[I].ObjectType := Item.ObjectType;
    Previews[I].Name := Item.Name;
    Previews[I].PrimaryEffect := Item.PrimaryEffect;
    Previews[I].ContentDigest := Item.ContentDigest;
    Previews[I].SourceLayer := Item.Layer;
    Previews[I].SourceStart := Item.StartFrame;
    Previews[I].SourceEnd := Item.EndFrame;
    Previews[I].TargetLayer := Duplicates[I].Layer;
    Previews[I].TargetStart := Duplicates[I].Frame;
    Previews[I].TargetEnd := Duplicates[I].Frame +
      Previews[I].FrameLength - 1;

    for Other in Snapshot.Objects do
      if (Other.Layer = Previews[I].TargetLayer) and
         RangesOverlap(Other.StartFrame, Other.EndFrame,
           Previews[I].TargetStart, Previews[I].TargetEnd) then
      begin
        ErrorCode := 'destination_occupied';
        ErrorMessage := Format(
          'duplicates[%d] overlaps object index %d at the destination.',
          [I, Other.Index]);
        Exit;
      end;
    for J := 0 to I - 1 do
      if (Previews[J].TargetLayer = Previews[I].TargetLayer) and
         RangesOverlap(Previews[J].TargetStart, Previews[J].TargetEnd,
           Previews[I].TargetStart, Previews[I].TargetEnd) then
      begin
        ErrorCode := 'destination_conflict';
        ErrorMessage := Format(
          'duplicates[%d] overlaps the destination in duplicates[%d].',
          [I, J]);
        Exit;
      end;
  end;
  Result := True;
end;

function ResolveCreatedObjectIndices(
  const Snapshot: TAul2MIRAISceneSnapshot;
  const Previews: TArray<TAul2MIRAIObjectDuplicatePreview>;
  out CreatedIndices: TArray<Integer>; out ErrorMessage: string): Boolean;
var
  Found  : Boolean;
  I      : Integer;
  Item   : TAul2MIRAIObjectInfo;
begin
  Result := False;
  ErrorMessage := '';
  SetLength(CreatedIndices, Length(Previews));
  for I := 0 to High(Previews) do
  begin
    Found := False;
    for Item in Snapshot.Objects do
      if (Item.Layer = Previews[I].TargetLayer) and
         (Item.StartFrame = Previews[I].TargetStart) and
         (Item.EndFrame = Previews[I].TargetEnd) and
         SameText(Item.PrimaryEffect, Previews[I].PrimaryEffect) and
         SameText(Item.ObjectType, Previews[I].ObjectType) and
         (Item.Name = Previews[I].Name) then
      begin
        CreatedIndices[I] := Item.Index;
        Found := True;
        Break;
      end;
    if not Found then
    begin
      ErrorMessage := Format(
        'Created object for duplicates[%d] was not found after the edit.',
        [I]);
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

function BuildDuplicateJson(
  const Preview: TAul2MIRAIObjectDuplicatePreview;
  IncludeResult: Boolean; CreatedIndex: Integer): TJSONObject;
var
  SourceJson: TJSONObject;
  TargetJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  SourceJson := TJSONObject.Create;
  Result.AddPair('source', SourceJson);
  SourceJson.AddPair('index', TJSONNumber.Create(Preview.SourceIndex));
  SourceJson.AddPair('object_type', Preview.ObjectType);
  SourceJson.AddPair('name', Preview.Name);
  SourceJson.AddPair('primary_effect', Preview.PrimaryEffect);
  SourceJson.AddPair('layer', TJSONNumber.Create(Preview.SourceLayer));
  SourceJson.AddPair('start_frame', TJSONNumber.Create(Preview.SourceStart));
  SourceJson.AddPair('end_frame', TJSONNumber.Create(Preview.SourceEnd));
  TargetJson := TJSONObject.Create;
  Result.AddPair('target', TargetJson);
  TargetJson.AddPair('layer', TJSONNumber.Create(Preview.TargetLayer));
  TargetJson.AddPair('start_frame', TJSONNumber.Create(Preview.TargetStart));
  TargetJson.AddPair('end_frame', TJSONNumber.Create(Preview.TargetEnd));
  Result.AddPair('frame_length', TJSONNumber.Create(Preview.FrameLength));
  if IncludeResult then
  begin
    Result.AddPair('applied', TJSONBool.Create(True));
    Result.AddPair('created_index', TJSONNumber.Create(CreatedIndex));
  end;
end;

function BuildObjectDuplicatePreviewResponse(
  const Previews: TArray<TAul2MIRAIObjectDuplicatePreview>;
  const Identity: TAul2MIRAISnapshotIdentity): string;
var
  I          : Integer;
  Items      : TJSONArray;
  PreviewJson: TJSONObject;
  Root       : TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root, Identity, AUL2MIRAI_COMMAND_PREVIEW_DUPLICATE_OBJECTS);
    PreviewJson := TJSONObject.Create;
    Root.AddPair('preview', PreviewJson);
    PreviewJson.AddPair('operation', 'duplicate_objects');
    PreviewJson.AddPair('applied', TJSONBool.Create(False));
    PreviewJson.AddPair('duplicate_count',
      TJSONNumber.Create(Length(Previews)));
    Items := TJSONArray.Create;
    PreviewJson.AddPair('duplicates', Items);
    for I := 0 to High(Previews) do
      Items.AddElement(BuildDuplicateJson(Previews[I], False, -1));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function BuildObjectDuplicateResponse(
  const Previews: TArray<TAul2MIRAIObjectDuplicatePreview>;
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
    AddHeader(Root, AfterIdentity, AUL2MIRAI_COMMAND_DUPLICATE_OBJECTS);
    ChangeJson := TJSONObject.Create;
    Root.AddPair('change', ChangeJson);
    ChangeJson.AddPair('operation', 'duplicate_objects');
    ChangeJson.AddPair('applied', TJSONBool.Create(True));
    ChangeJson.AddPair('duplicate_count',
      TJSONNumber.Create(Length(Previews)));
    ChangeJson.AddPair('previous_state_token', BeforeIdentity.StateToken);
    Items := TJSONArray.Create;
    ChangeJson.AddPair('duplicates', Items);
    for I := 0 to High(Previews) do
      Items.AddElement(BuildDuplicateJson(Previews[I], True,
        CreatedIndices[I]));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

end.
