unit Aul2MIRAIObjectEdit;

// 表示名変更・削除の要求を検証し、SDKポインターを持たない変更予定と応答を作る。
interface

uses
  Aul2MIRAIObjectTypes,
  Aul2MIRAISnapshotIdentity;

type
  TMIRAIObjectEditRequest = record
    DeleteObjects: Boolean;         // Trueなら指定対象の削除
    TargetIndices: TArray<Integer>; // 最新スナップショット内の対象番号
    NewName      : string;          // 空文字列は標準名への復帰
  end;

  TMIRAIObjectEditPreview = record
    Request   : TMIRAIObjectEditRequest;     // 検証済み操作
    Targets   : TArray<TAul2MIRAIObjectInfo>; // 対象の配置・内容・変更前名称
    WillChange: Boolean;                    // 実際の編集が必要か
  end;

// JSONの型、対象数、重複、名称、適用指定を検証する。
function ParseObjectEditRequest(const Text: string; DeleteObjects, RequireApply: Boolean;
  out StateToken: string; out Request: TMIRAIObjectEditRequest;
  out ErrorCode, ErrorMessage: string): Boolean;
// 選択状態とロック状態を検証し、対象を現在のスナップショットからコピーする。
function CreateObjectEditPreview(const Snapshot: TAul2MIRAISceneSnapshot;
  const Request: TMIRAIObjectEditRequest; out Preview: TMIRAIObjectEditPreview;
  out ErrorCode, ErrorMessage: string): Boolean;
// 適用後に対象の変更と、対象以外の配置・内容・名前が保持されたことを検証する。
function VerifyObjectEdit(const Before, After: TAul2MIRAISceneSnapshot;
  const Preview: TMIRAIObjectEditPreview; out ErrorMessage: string): Boolean;
// プレビューまたは検証済みの適用結果を既存プロトコル形式へ変換する。
function BuildObjectEditResponse(const Command: string; const Preview: TMIRAIObjectEditPreview;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity; Applied: Boolean): string;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  Aul2MIRAIObjectEquivalence,
  Aul2MIRAIProtocol;

function ParseObjectEditRequest(const Text: string; DeleteObjects, RequireApply: Boolean;
  out StateToken: string; out Request: TMIRAIObjectEditRequest;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  Json, Value: TJSONValue; // 解析した要求と検証中の値
  Root       : TJSONObject; // 要求のルート
  Indices    : TJSONArray; // 削除対象一覧
  I, J       : Integer;    // 対象と重複の検証位置
begin
  Result := False;
  StateToken := '';
  Request := Default(TMIRAIObjectEditRequest);
  Request.DeleteObjects := DeleteObjects;
  ErrorCode := 'invalid_json';
  ErrorMessage := 'Request must be a JSON object.';
  Json := TJSONObject.ParseJSONValue(Text);
  try
    if not (Json is TJSONObject) then Exit;
    Root := TJSONObject(Json);
    ErrorCode := 'invalid_state_token';
    ErrorMessage := 'state_token must be a SHA-256 token.';
    Value := Root.GetValue('state_token');
    if not (Value is TJSONString) then Exit;
    StateToken := Value.Value;
    if (Length(StateToken) <> 71) or not StartsText('sha256:', StateToken) then Exit;
    for I := 8 to Length(StateToken) do
      if not CharInSet(StateToken[I], ['0'..'9', 'a'..'f', 'A'..'F']) then Exit;
    ErrorCode := 'invalid_target_index';
    ErrorMessage := 'Target indices must be nonnegative integers.';
    if DeleteObjects then
    begin
      Value := Root.GetValue('target_indices');
      ErrorCode := 'invalid_target_indices';
      if not (Value is TJSONArray) then Exit;
      Indices := TJSONArray(Value);
      ErrorMessage := 'target_indices must contain between 1 and 64 objects.';
      if (Indices.Count < 1) or (Indices.Count > 64) then Exit;
      SetLength(Request.TargetIndices, Indices.Count);
      for I := 0 to Indices.Count - 1 do
      begin
        Value := Indices.Items[I];
        ErrorMessage := 'target_indices must contain nonnegative integers.';
        if not ((Value is TJSONNumber) and TryStrToInt(Value.Value, Request.TargetIndices[I])) then Exit;
        if Request.TargetIndices[I] < 0 then Exit;
        for J := 0 to I - 1 do
          if Request.TargetIndices[J] = Request.TargetIndices[I] then
          begin
            ErrorCode := 'duplicate_target';
            ErrorMessage := 'target_indices must not contain duplicates.';
            Exit;
          end;
      end;
    end
    else
    begin
      SetLength(Request.TargetIndices, 1);
      Value := Root.GetValue('target_index');
      if not ((Value is TJSONNumber) and TryStrToInt(Value.Value, Request.TargetIndices[0])) then Exit;
      if Request.TargetIndices[0] < 0 then Exit;
      ErrorCode := 'invalid_name';
      ErrorMessage := 'name must be a string of at most 1024 UTF-16 units without control characters.';
      Value := Root.GetValue('name');
      if not (Value is TJSONString) then Exit;
      Request.NewName := Value.Value;
      if Length(Request.NewName) > 1024 then Exit;
      for I := 1 to Length(Request.NewName) do
        if (Ord(Request.NewName[I]) < 32) or (Ord(Request.NewName[I]) = 127) then Exit;
    end;
    if RequireApply then
    begin
      ErrorCode := 'apply_required';
      ErrorMessage := 'apply must be true to perform an edit.';
      Value := Root.GetValue('apply');
      if not (Value is TJSONBool) then Exit;
      if not TJSONBool(Value).AsBoolean then Exit;
    end;
    ErrorCode := '';
    ErrorMessage := '';
    Result := True;
  finally
    Json.Free;
  end;
end;

function CreateObjectEditPreview(const Snapshot: TAul2MIRAISceneSnapshot;
  const Request: TMIRAIObjectEditRequest; out Preview: TMIRAIObjectEditPreview;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  I, J : Integer;                // 要求とスナップショットの位置
  Found: Boolean;                // 対象が現在も存在するか
  Layer: TAul2MIRAILayerInfo;     // 対象レイヤーのロック状態
begin
  Result := False;
  Preview := Default(TMIRAIObjectEditPreview);
  Preview.Request := Request;
  ErrorCode := 'invalid_target_indices';
  ErrorMessage := 'An edit requires between 1 and 64 targets; rename requires exactly one.';
  if (Length(Request.TargetIndices) < 1) or (Length(Request.TargetIndices) > 64) or
    (not Request.DeleteObjects and (Length(Request.TargetIndices) <> 1)) then Exit;
  SetLength(Preview.Targets, Length(Request.TargetIndices));
  for I := 0 to High(Request.TargetIndices) do
  begin
    for J := 0 to I - 1 do
      if Request.TargetIndices[I] = Request.TargetIndices[J] then
      begin
        ErrorCode := 'duplicate_target';
        ErrorMessage := 'An object must only be edited once per request.';
        Exit;
      end;
    Found := False;
    for J := 0 to High(Snapshot.Objects) do
      if Snapshot.Objects[J].Index = Request.TargetIndices[I] then
      begin
        Preview.Targets[I] := Snapshot.Objects[J];
        Found := True;
        Break;
      end;
    ErrorCode := 'target_not_found';
    ErrorMessage := Format('Object index %d was not found.', [Request.TargetIndices[I]]);
    if not Found then Exit;
    ErrorCode := 'target_not_selected';
    ErrorMessage := 'The target object must be selected before it is renamed or deleted.';
    if not Preview.Targets[I].Selected then Exit;
    ErrorCode := 'target_locked';
    ErrorMessage := 'The target layer is locked.';
    for Layer in Snapshot.Layers do
      if (Layer.Index = Preview.Targets[I].Layer) and Layer.StateAvailable and Layer.Locked then Exit;
  end;
  Preview.WillChange := Request.DeleteObjects or (Preview.Targets[0].Name <> Request.NewName);
  ErrorCode := '';
  ErrorMessage := '';
  Result := True;
end;

function VerifyObjectEdit(const Before, After: TAul2MIRAISceneSnapshot;
  const Preview: TMIRAIObjectEditPreview; out ErrorMessage: string): Boolean;
var
  Item, Current, Expected: TAul2MIRAIObjectInfo; // 比較中の変更前後の値
  TargetIndex  : Integer;             // 変更前オブジェクトの対象位置
  I            : Integer;             // 対象の探索位置
  Found        : Boolean;             // 変更後の同じ配置に対象が存在するか
begin
  Result := False;
  ErrorMessage := 'The object count after the edit did not match the request. Use Undo to recover.';
  I := Length(Before.Objects);
  if Preview.Request.DeleteObjects then Dec(I, Length(Preview.Targets));
  if (Before.SceneId <> After.SceneId) or (Length(After.Objects) <> I) then Exit;
  for Item in Before.Objects do
  begin
    TargetIndex := -1;
    for I := 0 to High(Preview.Targets) do
      if Preview.Targets[I].Index = Item.Index then TargetIndex := I;
    Found := False;
    for Current in After.Objects do
      if (Current.Layer = Item.Layer) and (Current.StartFrame = Item.StartFrame) then
      begin
        Found := True;
        Break;
      end;
    ErrorMessage := 'A deleted target is still present. Use Undo to recover.';
    if (TargetIndex >= 0) and Preview.Request.DeleteObjects then
    begin
      if Found then Exit;
      Continue;
    end;
    ErrorMessage := 'An object outside the requested change was modified. Use Undo to recover.';
    if not Found or (Current.EndFrame <> Item.EndFrame) then Exit;
    Expected := Item;
    if (TargetIndex >= 0) and not Preview.Request.DeleteObjects then
    begin
      ErrorMessage := 'The renamed object did not retain its requested name.';
      if Current.Name <> Preview.Request.NewName then Exit;
      Expected.Name := Preview.Request.NewName;
      // 名前がエイリアスに含まれる場合の内容検証はSDK書込み直後に行う。
    end
    else if (Current.Name <> Item.Name) or (Current.ContentDigest <> Item.ContentDigest) then Exit;
    if not CompareRecreatedObject(Expected, Current, ErrorMessage) then
    begin
      ErrorMessage := ErrorMessage + ' Use Undo to recover.';
      Exit;
    end;
  end;
  ErrorMessage := '';
  Result := True;
end;

function BuildObjectEditResponse(const Command: string; const Preview: TMIRAIObjectEditPreview;
  const BeforeIdentity, AfterIdentity: TAul2MIRAISnapshotIdentity; Applied: Boolean): string;
var
  Root, Change, Target: TJSONObject; // プロトコル応答と操作内容
  Targets             : TJSONArray; // 操作対象の明示的な一覧
  Item                : TAul2MIRAIObjectInfo; // 対象の変更前情報
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('protocol', AUL2MIRAI_PROTOCOL_NAME);
    Root.AddPair('protocol_version', TJSONNumber.Create(AUL2MIRAI_PROTOCOL_VERSION));
    Root.AddPair('command', Command);
    Root.AddPair('status', 'ok');
    Root.AddPair('snapshot_id', AfterIdentity.SnapshotId);
    Root.AddPair('state_token', AfterIdentity.StateToken);
    Root.AddPair('captured_at_utc', AfterIdentity.CapturedAtUtc);
    Change := TJSONObject.Create;
    if Applied then Root.AddPair('change', Change) else Root.AddPair('preview', Change);
    Change.AddPair('will_change', TJSONBool.Create(Preview.WillChange));
    Targets := TJSONArray.Create;
    Change.AddPair('targets', Targets);
    for Item in Preview.Targets do
    begin
      Target := TJSONObject.Create;
      Targets.AddElement(Target);
      Target.AddPair('index', TJSONNumber.Create(Item.Index));
      Target.AddPair('name', Item.Name);
      Target.AddPair('primary_effect', Item.PrimaryEffect);
      Target.AddPair('layer', TJSONNumber.Create(Item.Layer));
      Target.AddPair('start_frame', TJSONNumber.Create(Item.StartFrame));
      Target.AddPair('end_frame', TJSONNumber.Create(Item.EndFrame));
    end;
    if not Preview.Request.DeleteObjects then Change.AddPair('name', Preview.Request.NewName);
    if Applied then
    begin
      Change.AddPair('applied', TJSONBool.Create(Preview.WillChange));
      Change.AddPair('verified', TJSONBool.Create(True));
      Change.AddPair('previous_state_token', BeforeIdentity.StateToken);
      if Preview.Request.DeleteObjects then
        Change.AddPair('deleted_count', TJSONNumber.Create(Length(Preview.Targets)));
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

end.
