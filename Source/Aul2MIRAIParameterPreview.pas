unit Aul2MIRAIParameterPreview;

// 選択オブジェクトの設定値変更予定を検証し、変更せずに結果を作る。
interface

uses
  Aul2MIRAIObjectTypes;

type
  TAul2MIRAIParameterPreview = record
    TargetIndex   : Integer;
    Layer         : Integer;
    StartFrame    : Integer;
    EndFrame      : Integer;
    ObjectType    : string;
    PrimaryEffect : string;
    ContentDigest : string;
    EffectIndex   : Integer;
    EffectName    : string;
    EffectSelector: string;
    ItemName      : string;
    BeforeValue   : string;
    AfterValue    : string;
    WillChange    : Boolean;
  end;

function CreateParameterPreview(const Snapshot: TAul2MIRAISceneSnapshot;
  TargetIndex, EffectIndex: Integer; const ItemName, NewValue: string;
  out Preview: TAul2MIRAIParameterPreview; out ErrorCode,
  ErrorMessage: string): Boolean;

implementation

uses
  System.SysUtils;

const
  MAX_PREVIEW_VALUE_CHARS = 16384;

function CreateParameterPreview(const Snapshot: TAul2MIRAISceneSnapshot;
  TargetIndex, EffectIndex: Integer; const ItemName, NewValue: string;
  out Preview: TAul2MIRAIParameterPreview; out ErrorCode,
  ErrorMessage: string): Boolean;
var
  Effect   : TAul2MIRAIEffectDetail;
  EffectOccurrence: Integer;
  FoundItem: Boolean;
  I        : Integer;
  Item     : TAul2MIRAIObjectInfo;
  Parameter: TAul2MIRAIParameterInfo;
  Target   : TAul2MIRAIObjectInfo;
  TargetFound: Boolean;
begin
  Preview := Default(TAul2MIRAIParameterPreview);
  ErrorCode := '';
  ErrorMessage := '';
  Result := False;

  if TargetIndex < 0 then
  begin
    ErrorCode := 'invalid_target';
    ErrorMessage := 'target_index must be zero or greater.';
    Exit;
  end;
  if EffectIndex < 0 then
  begin
    ErrorCode := 'invalid_effect';
    ErrorMessage := 'effect_index must be zero or greater.';
    Exit;
  end;
  if ItemName = '' then
  begin
    ErrorCode := 'invalid_item';
    ErrorMessage := 'item must not be empty.';
    Exit;
  end;
  if Length(NewValue) > MAX_PREVIEW_VALUE_CHARS then
  begin
    ErrorCode := 'value_too_large';
    ErrorMessage := Format('value exceeds the %d character limit.',
      [MAX_PREVIEW_VALUE_CHARS]);
    Exit;
  end;

  TargetFound := False;
  for Item in Snapshot.Objects do
    if Item.Index = TargetIndex then
    begin
      Target := Item;
      TargetFound := True;
      Break;
    end;
  if not TargetFound then
  begin
    ErrorCode := 'target_not_found';
    ErrorMessage := 'The target object does not exist in the current scene.';
    Exit;
  end;
  if not Target.Selected then
  begin
    ErrorCode := 'target_not_selected';
    ErrorMessage := 'The target object is not currently selected.';
    Exit;
  end;
  if EffectIndex > High(Target.EffectDetails) then
  begin
    ErrorCode := 'effect_not_found';
    ErrorMessage := 'The requested effect_index does not exist.';
    Exit;
  end;

  Effect := Target.EffectDetails[EffectIndex];
  EffectOccurrence := 0;
  for I := 0 to EffectIndex - 1 do
    if Target.EffectDetails[I].Name = Effect.Name then
      Inc(EffectOccurrence);
  FoundItem := False;
  for Parameter in Effect.Parameters do
    if Parameter.Name = ItemName then
    begin
      if Parameter.Truncated then
      begin
        ErrorCode := 'current_value_truncated';
        ErrorMessage := 'The current value is truncated and cannot be previewed safely.';
        Exit;
      end;
      Preview.BeforeValue := Parameter.Value;
      FoundItem := True;
      Break;
    end;
  if not FoundItem then
  begin
    ErrorCode := 'item_not_found';
    ErrorMessage := 'The requested item does not exist in the effect.';
    Exit;
  end;

  Preview.TargetIndex := Target.Index;
  Preview.Layer := Target.Layer;
  Preview.StartFrame := Target.StartFrame;
  Preview.EndFrame := Target.EndFrame;
  Preview.ObjectType := Target.ObjectType;
  Preview.PrimaryEffect := Target.PrimaryEffect;
  Preview.ContentDigest := Target.ContentDigest;
  Preview.EffectIndex := EffectIndex;
  Preview.EffectName := Effect.Name;
  Preview.EffectSelector := Effect.Name;
  if EffectOccurrence > 0 then
    Preview.EffectSelector := Preview.EffectSelector + ':' +
      IntToStr(EffectOccurrence);
  Preview.ItemName := ItemName;
  Preview.AfterValue := NewValue;
  Preview.WillChange := Preview.BeforeValue <> Preview.AfterValue;
  Result := True;
end;

end.
