unit Aul2MIRAIObjectReader;

// 1回のread section内で現在シーンの全レイヤーをオブジェクト単位に走査する。

interface

uses
  AviUtl2PluginTypes,
  Aul2MIRAIObjectTypes;

// 現在シーンの共通オブジェクト情報を読み取り専用スナップショットへコピーする。
function ReadCurrentSceneObjects(EditHandle: PEditHandle;
  out Snapshot: TAul2MIRAISceneSnapshot; out ErrorMessage: string;
  IncludeSelectedDetails: Boolean = False): Boolean;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Aul2MIRAIObjectAlias,
  Aul2MIRAIObjectClassifier,
  Aul2MIRAISelection;

const
  MAX_OBJECT_COUNT = 100000;

type
  TObjectReadContext = class
  public
    Snapshot     : TAul2MIRAISceneSnapshot;
    ErrorMessage : string;
    IncludeSelectedDetails: Boolean;
  end;

procedure AppendObject(var Items: TArray<TAul2MIRAIObjectInfo>;
  var Count: Integer; const Value: TAul2MIRAIObjectInfo);
var
  NewCapacity: Integer;
begin
  if Count >= Length(Items) then
  begin
    NewCapacity := Length(Items) * 2;
    if NewCapacity < 64 then
      NewCapacity := 64;
    SetLength(Items, NewCapacity);
  end;

  Items[Count] := Value;
  Inc(Count);
end;

function CopyWideText(Value: PWideChar): string;
begin
  if Value = nil then
    Exit('');

  Result := string(Value);
end;

procedure ReadSceneCallback(Param: Pointer; Edit: PEditSection); cdecl;
var
  AliasText      : string;                       // コピーしたオブジェクトエイリアス
  Context        : TObjectReadContext;           // 呼び出し元の取得コンテキスト
  FocusHandle    : TObjectHandle;                // 通常選択されているオブジェクト
  Frame          : Integer;                      // 現在レイヤーの探索開始フレーム
  Info           : TAul2MIRAIObjectInfo;         // 現在追加するオブジェクト情報
  Layer          : Integer;                      // 探索中のレイヤー番号
  LayerFrame     : TObjectLayerFrame;            // SDKから取得した配置範囲
  NextFrame      : Integer;                      // 次回の探索開始フレーム
  Obj            : TObjectHandle;                // SDK内でのみ使うオブジェクトハンドル
  ObjectCount    : Integer;                      // Objectsの有効要素数
  Objects        : TArray<TAul2MIRAIObjectInfo>; // コピー済みオブジェクト一覧
  Selected       : TObjectHandleArray;           // コールバック内だけで使う選択ハンドル
begin
  Context := TObjectReadContext(Param);
  if Context = nil then
    Exit;

  try
    if Edit = nil then
    begin
      Context.ErrorMessage := 'AviUtl2 returned no read section.';
      Exit;
    end;
    if not ReadSelectedObjectHandles(Edit, Selected, FocusHandle,
      Context.ErrorMessage) then
    begin
      Exit;
    end;
    Context.Snapshot.SelectedCount := Length(Selected);

    if Context.Snapshot.LayerMax < 0 then
      Exit;

    ObjectCount := 0;
    for Layer := 0 to Context.Snapshot.LayerMax do
    begin
      Frame := 0;
      while True do
      begin
        Obj := Edit^.FindObject(Layer, Frame);
        if Obj = nil then
          Break;

        LayerFrame := Edit^.GetObjectLayerFrame(Obj);
        if (LayerFrame.Layer <> Layer) or
           (LayerFrame.StartFrame < 0) or
           (LayerFrame.EndFrame < LayerFrame.StartFrame) then
        begin
          Context.ErrorMessage := Format(
            'Invalid object range at layer %d, frame %d.', [Layer, Frame]);
          Exit;
        end;

        Info := Default(TAul2MIRAIObjectInfo);
        Info.Index := ObjectCount;
        Info.Layer := LayerFrame.Layer;
        Info.StartFrame := LayerFrame.StartFrame;
        Info.EndFrame := LayerFrame.EndFrame;
        Info.Selected := ContainsObjectHandle(Selected, Obj);
        Info.Focused := Obj = FocusHandle;
        Info.Name := CopyWideText(Edit^.GetObjectName(Obj));
        AliasText := CopyUtf8Text(Edit^.GetObjectAlias(Obj));
        Info.PrimaryEffect := ExtractPrimaryEffect(AliasText);
        Info.ObjectType := ClassifyObjectType(Info.PrimaryEffect);
        Info.MaterialPath := ExtractMaterialPath(AliasText);
        Info.Effects := ExtractEffectNames(AliasText);
        if Context.IncludeSelectedDetails and
           (Info.Selected or
            ((Info.StartFrame <= Context.Snapshot.CursorFrame) and
             (Info.EndFrame >= Context.Snapshot.CursorFrame))) then
          Info.EffectDetails := ExtractEffectDetails(AliasText);
        AppendObject(Objects, ObjectCount, Info);

        if ObjectCount >= MAX_OBJECT_COUNT then
        begin
          Context.ErrorMessage := Format(
            'Object count exceeded the safety limit (%d).', [MAX_OBJECT_COUNT]);
          Exit;
        end;

        if LayerFrame.EndFrame = High(Integer) then
          Break;
        NextFrame := LayerFrame.EndFrame + 1;
        if NextFrame <= Frame then
        begin
          Context.ErrorMessage := Format(
            'Object scan did not advance at layer %d, frame %d.', [Layer, Frame]);
          Exit;
        end;
        Frame := NextFrame;
      end;
    end;

    SetLength(Objects, ObjectCount);
    Context.Snapshot.Objects := Objects;
  except
    on E: Exception do
      Context.ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

function ReadCurrentSceneObjects(EditHandle: PEditHandle;
  out Snapshot: TAul2MIRAISceneSnapshot; out ErrorMessage: string;
  IncludeSelectedDetails: Boolean): Boolean;
var
  Context : TObjectReadContext; // SDKコールバックへ渡す取得コンテキスト
  EditInfo : TEditInfo;         // get_edit_infoからコピーする基本編集情報
  Started : UInt64;             // 経過時間計測の開始tick
begin
  Snapshot := Default(TAul2MIRAISceneSnapshot);
  ErrorMessage := '';
  Result := False;
  if EditHandle = nil then
  begin
    ErrorMessage := 'AviUtl2 edit handle is not available.';
    Exit;
  end;
  if not Assigned(EditHandle^.CallReadSectionParam) then
  begin
    ErrorMessage := 'AviUtl2 does not provide call_read_section_param.';
    Exit;
  end;

  Context := TObjectReadContext.Create;
  try
    Context.IncludeSelectedDetails := IncludeSelectedDetails;
    Started := GetTickCount64;
    FillChar(EditInfo, SizeOf(EditInfo), 0);
    EditHandle^.GetEditInfo(@EditInfo, SizeOf(EditInfo));
    Context.Snapshot.SceneId := EditInfo.SceneId;
    Context.Snapshot.Width := EditInfo.Width;
    Context.Snapshot.Height := EditInfo.Height;
    Context.Snapshot.Rate := EditInfo.Rate;
    Context.Snapshot.Scale := EditInfo.Scale;
    Context.Snapshot.CursorFrame := EditInfo.Frame;
    Context.Snapshot.LayerMax := EditInfo.LayerMax;

    if not EditHandle^.CallReadSectionParam(Context, @ReadSceneCallback) then
    begin
      ErrorMessage := 'AviUtl2 rejected the read request.';
      Exit;
    end;

    Context.Snapshot.ElapsedMs := GetTickCount64 - Started;
    Snapshot := Context.Snapshot;
    ErrorMessage := Context.ErrorMessage;
    Result := ErrorMessage = '';
  finally
    Context.Free;
  end;
end;

end.
