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
  EFFECT_AUDIO_BUFFER  = #$30AA#$30FC#$30C7#$30A3#$30AA#$30D0#$30C3#$30D5#$30A1;
  EFFECT_MODEL         = #$30E2#$30C7#$30EB#$30D5#$30A1#$30A4#$30EB;
  EFFECT_TEXT          = #$30C6#$30AD#$30B9#$30C8;
  EFFECT_FIGURE        = #$56F3#$5F62;
  EFFECT_SCENE         = #$30B7#$30FC#$30F3;
  EFFECT_FRAME_BUFFER  = #$30D5#$30EC#$30FC#$30E0#$30D0#$30C3#$30D5#$30A1;
  EFFECT_PREVIOUS_OBJECT = #$76F4#$524D#$30AA#$30D6#$30B8#$30A7#$30AF#$30C8;
  EFFECT_PARTIAL_FILTER = #$90E8#$5206#$30D5#$30A3#$30EB#$30BF;
  EFFECT_GROUP_CONTROL = #$30B0#$30EB#$30FC#$30D7#$5236#$5FA1;
  EFFECT_AUDIO_GROUP_CONTROL = #$30B0#$30EB#$30FC#$30D7#$5236#$5FA1'('#$97F3#$58F0')';
  EFFECT_CAMERA_CONTROL= #$30AB#$30E1#$30E9#$5236#$5FA1;
  EFFECT_TIME_CONTROL = #$6642#$9593#$5236#$5FA1'('#$30AA#$30D6#$30B8#$30A7#$30AF#$30C8')';
  EFFECT_IMAGE_COMPOSITION = #$753B#$50CF#$5408#$6210'('#$30AA#$30D6#$30B8#$30A7#$30AF#$30C8')';
  EFFECT_SCANLINES = #$8D70#$67FB#$7DDA;
  EFFECT_PERIPHERAL_BLUR_LIGHT = #$5468#$8FBA#$30DC#$30B1#$5149#$91CF;
  EFFECT_FILTER_OBJECT = #$30D5#$30A3#$30EB#$30BF#$30AA#$30D6#$30B8#$30A7#$30AF#$30C8;

function ClassifyObjectType(const PrimaryEffect: string): string;
begin
  if SameText(PrimaryEffect, EFFECT_VIDEO) then
    Exit('video');
  if SameText(PrimaryEffect, EFFECT_IMAGE) then
    Exit('image');
  if SameText(PrimaryEffect, EFFECT_AUDIO) then
    Exit('audio');
  if SameText(PrimaryEffect, EFFECT_AUDIO_BUFFER) then
    Exit('audio_buffer');
  if SameText(PrimaryEffect, EFFECT_MODEL) then
    Exit('model');
  if SameText(PrimaryEffect, EFFECT_TEXT) then
    Exit('text');
  if SameText(PrimaryEffect, EFFECT_FIGURE) then
    Exit('figure');
  if SameText(PrimaryEffect, EFFECT_SCENE) then
    Exit('scene');
  if SameText(PrimaryEffect, EFFECT_FRAME_BUFFER) then
    Exit('frame_buffer');
  if SameText(PrimaryEffect, EFFECT_PREVIOUS_OBJECT) then
    Exit('previous_object');
  if SameText(PrimaryEffect, EFFECT_PARTIAL_FILTER) then
    Exit('partial_filter');
  if SameText(PrimaryEffect, EFFECT_AUDIO_GROUP_CONTROL) then
    Exit('audio_group_control');
  if StartsText(EFFECT_GROUP_CONTROL, PrimaryEffect) then
    Exit('group_control');
  if SameText(PrimaryEffect, EFFECT_CAMERA_CONTROL) then
    Exit('camera_control');
  if SameText(PrimaryEffect, EFFECT_TIME_CONTROL) then
    Exit('time_control');
  if SameText(PrimaryEffect, EFFECT_IMAGE_COMPOSITION) then
    Exit('image_composition');
  if SameText(PrimaryEffect, EFFECT_SCANLINES) or
     SameText(PrimaryEffect, EFFECT_PERIPHERAL_BLUR_LIGHT) then
    Exit('screen_effect');
  if SameText(PrimaryEffect, EFFECT_FILTER_OBJECT) then
    Exit('filter_object');
  Result := 'unknown';
end;

end.
