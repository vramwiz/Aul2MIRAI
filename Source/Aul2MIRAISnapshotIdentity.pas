unit Aul2MIRAISnapshotIdentity;

// 取得応答の一意IDと編集状態を表す決定的なSHA-256トークンを生成する。
interface

uses
  Aul2MIRAIEditStateTypes,
  Aul2MIRAIObjectTypes;

type
  TAul2MIRAISnapshotIdentity = record
    SnapshotId   : string;
    StateToken   : string;
    CapturedAtUtc: string;
  end;

function CreateSnapshotIdentity(const State: TAul2MIRAIEditState;
  const Snapshot: TAul2MIRAISceneSnapshot): TAul2MIRAISnapshotIdentity;

implementation

uses
  System.Classes,
  System.Hash,
  System.SysUtils;

procedure AppendField(Builder: TStringBuilder; const Name, Value: string);
begin
  Builder.Append(Name);
  Builder.Append('=');
  Builder.Append(Length(Value));
  Builder.Append(':');
  Builder.Append(Value);
  Builder.Append(';');
end;

procedure AppendInteger(Builder: TStringBuilder; const Name: string;
  Value: Int64);
begin
  AppendField(Builder, Name, IntToStr(Value));
end;

procedure AppendFloat(Builder: TStringBuilder; const Name: string;
  Value: Extended);
begin
  AppendField(Builder, Name,
    FloatToStr(Value, TFormatSettings.Invariant));
end;

procedure AppendBoolean(Builder: TStringBuilder; const Name: string;
  Value: Boolean);
begin
  if Value then
    AppendField(Builder, Name, '1')
  else
    AppendField(Builder, Name, '0');
end;

function NewSnapshotId: string;
var
  Value: TGUID;
begin
  if CreateGUID(Value) <> 0 then
    RaiseLastOSError;
  Result := LowerCase(GUIDToString(Value));
  Result := Copy(Result, 2, Length(Result) - 2);
end;

function CreateSnapshotIdentity(const State: TAul2MIRAIEditState;
  const Snapshot: TAul2MIRAISceneSnapshot): TAul2MIRAISnapshotIdentity;
var
  Builder: TStringBuilder;
  EffectIndex: Integer;
  EffectState: TAul2MIRAIEffectState;
  Index  : Integer;
  Item   : TAul2MIRAIObjectInfo;
  Layer  : TAul2MIRAILayerInfo;
  SectionIndex: Integer;
begin
  Result := Default(TAul2MIRAISnapshotIdentity);
  Result.SnapshotId := NewSnapshotId;
  Result.CapturedAtUtc := State.CapturedAtUtc;

  Builder := TStringBuilder.Create(4096);
  try
    AppendField(Builder, 'project_path', State.ProjectPath);
    AppendInteger(Builder, 'scene_id', State.SceneId);
    AppendField(Builder, 'scene_name', State.SceneName);
    AppendField(Builder, 'edit_mode', State.EditMode);
    AppendInteger(Builder, 'width', State.Width);
    AppendInteger(Builder, 'height', State.Height);
    AppendInteger(Builder, 'rate', State.Rate);
    AppendInteger(Builder, 'scale', State.Scale);
    AppendInteger(Builder, 'sample_rate', State.SampleRate);
    AppendInteger(Builder, 'cursor_frame', State.CursorFrame);
    AppendInteger(Builder, 'cursor_layer', State.CursorLayer);
    AppendInteger(Builder, 'frame_max', State.FrameMax);
    AppendInteger(Builder, 'layer_max', State.LayerMax);
    AppendInteger(Builder, 'display_frame_start', State.DisplayFrameStart);
    AppendInteger(Builder, 'display_layer_start', State.DisplayLayerStart);
    AppendInteger(Builder, 'display_frame_num', State.DisplayFrameNum);
    AppendInteger(Builder, 'display_layer_num', State.DisplayLayerNum);
    AppendInteger(Builder, 'select_range_start', State.SelectRangeStart);
    AppendInteger(Builder, 'select_range_end', State.SelectRangeEnd);
    AppendFloat(Builder, 'grid_bpm_tempo', State.GridBpmTempo);
    AppendInteger(Builder, 'grid_bpm_beat', State.GridBpmBeat);
    AppendFloat(Builder, 'grid_bpm_offset', State.GridBpmOffset);
    AppendInteger(Builder, 'selected_count', State.SelectedCount);
    AppendInteger(Builder, 'object_count', Length(Snapshot.Objects));
    AppendInteger(Builder, 'layer_count', Length(Snapshot.Layers));

    for Layer in Snapshot.Layers do
    begin
      AppendInteger(Builder, 'layer_index', Layer.Index);
      AppendField(Builder, 'layer_name', Layer.Name);
      AppendBoolean(Builder, 'layer_state_available', Layer.StateAvailable);
      if Layer.StateAvailable then
      begin
        AppendBoolean(Builder, 'layer_enabled', Layer.Enabled);
        AppendBoolean(Builder, 'layer_locked', Layer.Locked);
      end;
    end;

    for Index := 0 to High(Snapshot.Objects) do
    begin
      Item := Snapshot.Objects[Index];
      AppendInteger(Builder, 'object_index', Index);
      AppendInteger(Builder, 'object_layer', Item.Layer);
      AppendInteger(Builder, 'object_start', Item.StartFrame);
      AppendInteger(Builder, 'object_end', Item.EndFrame);
      AppendBoolean(Builder, 'object_selected', Item.Selected);
      AppendBoolean(Builder, 'object_focused', Item.Focused);
      AppendField(Builder, 'object_name', Item.Name);
      AppendField(Builder, 'object_content', Item.ContentDigest);
      AppendInteger(Builder, 'object_focused_section', Item.FocusedSection);
      AppendInteger(Builder, 'object_section_count',
        Length(Item.SectionFrames));
      for SectionIndex := 0 to High(Item.SectionFrames) do
        AppendInteger(Builder, 'object_section_frame',
          Item.SectionFrames[SectionIndex]);
      AppendInteger(Builder, 'object_effect_state_count',
        Length(Item.EffectStates));
      for EffectIndex := 0 to High(Item.EffectStates) do
      begin
        EffectState := Item.EffectStates[EffectIndex];
        AppendField(Builder, 'object_effect_name', EffectState.Name);
        AppendBoolean(Builder, 'object_effect_enabled',
          EffectState.Enabled);
        AppendBoolean(Builder, 'object_effect_locked',
          EffectState.Locked);
      end;
    end;

    Result.StateToken := 'sha256:' + LowerCase(
      THashSHA2.GetHashString(Builder.ToString));
  finally
    Builder.Free;
  end;
end;

end.
