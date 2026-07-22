unit Aul2MIRAIObjectClassifier;

// 標準オブジェクトの先頭エフェクト名を外部向けの安定した種類名へ変換する。
interface

function ClassifyObjectType(const PrimaryEffect: string): string;

implementation

uses
  System.SysUtils,
  System.StrUtils;

const
  EFFECT_VIDEO         = #$52D5#$753B#$30D5#$30A1#$30A4#$30EB;
  EFFECT_IMAGE         = #$753B#$50CF#$30D5#$30A1#$30A4#$30EB;
  EFFECT_AUDIO         = #$97F3#$58F0#$30D5#$30A1#$30A4#$30EB;
  EFFECT_TEXT          = #$30C6#$30AD#$30B9#$30C8;
  EFFECT_FIGURE        = #$56F3#$5F62;
  EFFECT_SCENE         = #$30B7#$30FC#$30F3;
  EFFECT_FRAME_BUFFER  = #$30D5#$30EC#$30FC#$30E0#$30D0#$30C3#$30D5#$30A1;
  EFFECT_GROUP_CONTROL = #$30B0#$30EB#$30FC#$30D7#$5236#$5FA1;
  EFFECT_CAMERA_CONTROL= #$30AB#$30E1#$30E9#$5236#$5FA1;

function ClassifyObjectType(const PrimaryEffect: string): string;
begin
  if SameText(PrimaryEffect, EFFECT_VIDEO) then
    Exit('video');
  if SameText(PrimaryEffect, EFFECT_IMAGE) then
    Exit('image');
  if SameText(PrimaryEffect, EFFECT_AUDIO) then
    Exit('audio');
  if SameText(PrimaryEffect, EFFECT_TEXT) then
    Exit('text');
  if SameText(PrimaryEffect, EFFECT_FIGURE) then
    Exit('figure');
  if SameText(PrimaryEffect, EFFECT_SCENE) then
    Exit('scene');
  if SameText(PrimaryEffect, EFFECT_FRAME_BUFFER) then
    Exit('frame_buffer');
  if StartsText(EFFECT_GROUP_CONTROL, PrimaryEffect) then
    Exit('group_control');
  if SameText(PrimaryEffect, EFFECT_CAMERA_CONTROL) then
    Exit('camera_control');
  Result := 'unknown';
end;

end.
