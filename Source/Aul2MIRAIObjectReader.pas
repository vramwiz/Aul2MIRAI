unit Aul2MIRAIObjectReader;

// 1回のread section内で現在シーンの全レイヤーをオブジェクト単位に走査する。

interface

uses
  AviUtl2PluginTypes,
  Aul2MIRAIObjectTypes;

// 現在シーンの共通オブジェクト情報を読み取り専用スナップショットへコピーする。
function ReadCurrentSceneObjects(EditHandle: PEditHandle;
  out Snapshot: TAul2MIRAISceneSnapshot; out ErrorMessage: string;
  IncludeSelectedDetails: Boolean = False; DetailObjectIndex: Integer = -1;
  DetailRangeStart: Integer = -1; DetailRangeEnd: Integer = -1): Boolean;

// Copies one object while an AviUtl2 read/edit section is active.  This is
// also used to compare an alias-created object with its source before the
// edit callback is allowed to complete.
function ReadObjectSnapshot(Edit: PEditSection; Obj: TObjectHandle;
  IncludeDetails, Focused: Boolean; out Info: TAul2MIRAIObjectInfo;
  out ErrorMessage: string): Boolean;

implementation

uses
  Winapi.Windows,
  System.Hash,
  System.SysUtils,
  Aul2MIRAIObjectAlias,
  Aul2MIRAIObjectClassifier,
  Aul2MIRAISelection;

const
  MAX_OBJECT_COUNT = 100000;
  MAX_EFFECT_COUNT = 256;
  MAX_SECTION_COUNT = 4096;
  MAX_TRACK_PARAMETER_COUNT = 4096;

type
  TTrackParameterBuffer = array[0..MAX_TRACK_PARAMETER_COUNT - 1] of Double;
  PTrackParameterBuffer = ^TTrackParameterBuffer;

  TObjectReadContext = class
  public
    Snapshot     : TAul2MIRAISceneSnapshot;
    ErrorMessage : string;
    IncludeSelectedDetails: Boolean;
    DetailObjectIndex: Integer;
    DetailRangeStart: Integer;
    DetailRangeEnd: Integer;
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

function ReadLayerStates(Edit: PEditSection;
  var Snapshot: TAul2MIRAISceneSnapshot; out ErrorMessage: string): Boolean;
var
  I: Integer;
begin
  if Snapshot.LayerMax < 0 then
  begin
    SetLength(Snapshot.Layers, 0);
    Exit(True);
  end;
  SetLength(Snapshot.Layers, Snapshot.LayerMax + 1);
  for I := 0 to Snapshot.LayerMax do
  begin
    Snapshot.Layers[I].Index := I;
    Snapshot.Layers[I].Name := CopyWideText(Edit^.GetLayerName(I));
    Snapshot.Layers[I].StateAvailable :=
      Assigned(Edit^.GetLayerEnable) and Assigned(Edit^.GetLayerLock);
    if Snapshot.Layers[I].StateAvailable then
    begin
      Snapshot.Layers[I].Enabled := Edit^.GetLayerEnable(I) <> False;
      Snapshot.Layers[I].Locked := Edit^.GetLayerLock(I) <> False;
    end;
  end;
  Result := True;
end;

function ReadObjectSections(Edit: PEditSection; Obj: TObjectHandle;
  Focused: Boolean; var Info: TAul2MIRAIObjectInfo;
  out ErrorMessage: string): Boolean;
var
  Count: Integer;
  I    : Integer;
begin
  Result := False;
  Info.FocusedSection := -1;
  if not Assigned(Edit^.GetObjectSectionNum) or
     not Assigned(Edit^.GetObjectSectionFrame) or
     not Assigned(Edit^.GetFocusObjectSection) then
  begin
    SetLength(Info.SectionFrames, 0);
    Exit(True);
  end;
  Count := Edit^.GetObjectSectionNum(Obj);
  if (Count < 0) or (Count > MAX_SECTION_COUNT) then
  begin
    ErrorMessage := Format('Invalid object section count: %d.', [Count]);
    Exit;
  end;
  SetLength(Info.SectionFrames, Count);
  for I := 0 to Count - 1 do
  begin
    Info.SectionFrames[I] := Edit^.GetObjectSectionFrame(Obj, I);
    if Info.SectionFrames[I] < 0 then
    begin
      ErrorMessage := Format('Failed to read object section %d.', [I]);
      Exit;
    end;
  end;
  if Focused then
    Info.FocusedSection := Edit^.GetFocusObjectSection;
  Result := True;
end;

function ReadEffectStates(Edit: PEditSection; Obj: TObjectHandle;
  var Info: TAul2MIRAIObjectInfo; out ErrorMessage: string): Boolean;
var
  Count  : Integer;
  Handles: TArray<Pointer>;
  I      : Integer;
begin
  Result := False;
  if not Assigned(Edit^.GetEffectList) or
     not Assigned(Edit^.GetEffectName) or
     not Assigned(Edit^.GetEffectEnable) or
     not Assigned(Edit^.GetEffectLock) then
  begin
    SetLength(Info.EffectStates, 0);
    Exit(True);
  end;
  Count := Edit^.GetEffectList(Obj, nil, 0);
  if (Count < 0) or (Count > MAX_EFFECT_COUNT) then
  begin
    ErrorMessage := Format('Invalid effect count: %d.', [Count]);
    Exit;
  end;
  SetLength(Handles, Count);
  if Count > 0 then
  begin
    Count := Edit^.GetEffectList(Obj, @Handles[0], Count);
    if (Count < 0) or (Count > Length(Handles)) then
    begin
      ErrorMessage := 'AviUtl2 returned an invalid effect list.';
      Exit;
    end;
    SetLength(Handles, Count);
  end;
  SetLength(Info.EffectStates, Count);
  for I := 0 to Count - 1 do
  begin
    Info.EffectStates[I].Name := CopyWideText(
      Edit^.GetEffectName(Handles[I]));
    Info.EffectStates[I].Enabled :=
      Edit^.GetEffectEnable(Handles[I]) <> False;
    Info.EffectStates[I].Locked :=
      Edit^.GetEffectLock(Handles[I]) <> False;
    if (I <= High(Info.EffectDetails)) and
       (Info.EffectDetails[I].Name = Info.EffectStates[I].Name) then
    begin
      Info.EffectDetails[I].StateAvailable := True;
      Info.EffectDetails[I].Enabled := Info.EffectStates[I].Enabled;
      Info.EffectDetails[I].Locked := Info.EffectStates[I].Locked;
    end;
  end;
  Result := True;
end;

function ReadTrackDetails(Edit: PEditSection; Obj: TObjectHandle;
  var Info: TAul2MIRAIObjectInfo; out ErrorMessage: string): Boolean;
var
  DetailIndex    : Integer;
  EffectOccurrence: Integer;
  EffectSelector : string;
  ParameterIndex : Integer;
  PreviousIndex  : Integer;
  TrackIndex     : Integer;
  TrackInfo      : TTrackInfo;
begin
  Result := False;
  if not Assigned(Edit^.GetObjectTrackInfo) then
    Exit(True);
  for DetailIndex := 0 to High(Info.EffectDetails) do
  begin
    EffectOccurrence := 0;
    for PreviousIndex := 0 to DetailIndex - 1 do
      if Info.EffectDetails[PreviousIndex].Name =
         Info.EffectDetails[DetailIndex].Name then
        Inc(EffectOccurrence);
    EffectSelector := Info.EffectDetails[DetailIndex].Name;
    if EffectOccurrence > 0 then
      EffectSelector := EffectSelector + ':' + IntToStr(EffectOccurrence);
    for ParameterIndex := 0 to
      High(Info.EffectDetails[DetailIndex].Parameters) do
    begin
      FillChar(TrackInfo, SizeOf(TrackInfo), 0);
      if not Edit^.GetObjectTrackInfo(Obj,
        PWideChar(EffectSelector),
        PWideChar(Info.EffectDetails[DetailIndex].Parameters[ParameterIndex].Name),
        @TrackInfo, SizeOf(TrackInfo)) then
        Continue;
      if (TrackInfo.ParamNum < 0) or
         (TrackInfo.ParamNum > MAX_TRACK_PARAMETER_COUNT) or
         ((TrackInfo.ParamNum > 0) and (TrackInfo.Param = nil)) then
      begin
        ErrorMessage := 'AviUtl2 returned invalid track information.';
        Exit;
      end;
      with Info.EffectDetails[DetailIndex].Parameters[ParameterIndex] do
      begin
        TrackInfoAvailable := True;
        TrackMode := CopyWideText(TrackInfo.Mode);
        TrackAccelerate := TrackInfo.Accelerate;
        TrackDecelerate := TrackInfo.Decelerate;
        TrackIgnoreMidpoint := TrackInfo.TwoPoint;
        TrackTimeControl := TrackInfo.TimeControl;
        TrackGroupCount := TrackInfo.GroupNum;
        TrackGroupIndex := TrackInfo.GroupIndex;
        TrackGroupName := CopyWideText(TrackInfo.GroupName);
        SetLength(TrackParameters, TrackInfo.ParamNum);
        for TrackIndex := 0 to TrackInfo.ParamNum - 1 do
          TrackParameters[TrackIndex] :=
            PTrackParameterBuffer(TrackInfo.Param)^[TrackIndex];
      end;
    end;
  end;
  Result := True;
end;

function ReadObjectSnapshot(Edit: PEditSection; Obj: TObjectHandle;
  IncludeDetails, Focused: Boolean; out Info: TAul2MIRAIObjectInfo;
  out ErrorMessage: string): Boolean;
var
  AliasText : string;
  LayerFrame: TObjectLayerFrame;
begin
  Result := False;
  Info := Default(TAul2MIRAIObjectInfo);
  Info.FocusedSection := -1;
  ErrorMessage := '';
  if (Edit = nil) or (Obj = nil) then
  begin
    ErrorMessage := 'Object snapshot requires a valid edit section and object.';
    Exit;
  end;

  LayerFrame := Edit^.GetObjectLayerFrame(Obj);
  if (LayerFrame.Layer < 0) or (LayerFrame.StartFrame < 0) or
     (LayerFrame.EndFrame < LayerFrame.StartFrame) then
  begin
    ErrorMessage := Format('Invalid object range at layer %d, frame %d.',
      [LayerFrame.Layer, LayerFrame.StartFrame]);
    Exit;
  end;
  Info.Layer := LayerFrame.Layer;
  Info.StartFrame := LayerFrame.StartFrame;
  Info.EndFrame := LayerFrame.EndFrame;
  Info.Name := CopyWideText(Edit^.GetObjectName(Obj));
  AliasText := CopyUtf8Text(Edit^.GetObjectAlias(Obj));
  if AliasText = '' then
  begin
    ErrorMessage := 'AviUtl2 returned no object alias data.';
    Exit;
  end;
  Info.PrimaryEffect := ExtractPrimaryEffect(AliasText);
  Info.ObjectType := ClassifyObjectType(Info.PrimaryEffect);
  Info.MaterialPath := ExtractMaterialPath(AliasText);
  Info.Effects := ExtractEffectNames(AliasText);
  Info.ContentDigest := LowerCase(THashSHA2.GetHashString(AliasText));
  if IncludeDetails then
    Info.EffectDetails := ExtractEffectDetails(AliasText);
  if not ReadObjectSections(Edit, Obj, Focused, Info, ErrorMessage) or
     not ReadEffectStates(Edit, Obj, Info, ErrorMessage) or
     not ReadTrackDetails(Edit, Obj, Info, ErrorMessage) then
    Exit;
  Result := True;
end;

procedure ReadSceneCallback(Param: Pointer; Edit: PEditSection); cdecl;
var
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

    if not ReadLayerStates(Edit, Context.Snapshot,
      Context.ErrorMessage) then
      Exit;

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

        if not ReadObjectSnapshot(Edit, Obj,
          Context.IncludeSelectedDetails and
          (ContainsObjectHandle(Selected, Obj) or
           ((LayerFrame.StartFrame <= Context.Snapshot.CursorFrame) and
            (LayerFrame.EndFrame >= Context.Snapshot.CursorFrame)) or
           (ObjectCount = Context.DetailObjectIndex) or
           ((Context.DetailRangeStart >= 0) and
            (Context.DetailRangeEnd >= Context.DetailRangeStart) and
            (LayerFrame.StartFrame <= Context.DetailRangeEnd) and
            (LayerFrame.EndFrame >= Context.DetailRangeStart))),
          Obj = FocusHandle, Info, Context.ErrorMessage) then
          Exit;
        Info.Index := ObjectCount;
        Info.Selected := ContainsObjectHandle(Selected, Obj);
        Info.Focused := Obj = FocusHandle;
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
  IncludeSelectedDetails: Boolean; DetailObjectIndex: Integer;
  DetailRangeStart, DetailRangeEnd: Integer): Boolean;
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
    Context.DetailObjectIndex := DetailObjectIndex;
    Context.DetailRangeStart := DetailRangeStart;
    Context.DetailRangeEnd := DetailRangeEnd;
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
