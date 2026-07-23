unit Aul2MIRAIObjectEquivalence;

// Compares an alias-created object with its source while ignoring only the
// placement, selection/focus state, snapshot index, and normalized alias hash.

interface

uses
  Aul2MIRAIObjectTypes;

function CompareRecreatedObject(const Source, Created: TAul2MIRAIObjectInfo;
  out Difference: string): Boolean;

implementation

uses
  System.SysUtils;

function Fail(const Path, Expected, Actual: string;
  out Difference: string): Boolean;
begin
  Difference := Format('%s differs (source="%s", created="%s").',
    [Path, Expected, Actual]);
  Result := False;
end;

function CompareStrings(const Path, Source, Created: string;
  out Difference: string): Boolean;
begin
  if Source <> Created then
    Exit(Fail(Path, Source, Created, Difference));
  Result := True;
end;

function CompareBooleans(const Path: string; Source, Created: Boolean;
  out Difference: string): Boolean;
begin
  if Source <> Created then
    Exit(Fail(Path, BoolToStr(Source, True), BoolToStr(Created, True),
      Difference));
  Result := True;
end;

function CompareIntegers(const Path: string; Source, Created: Integer;
  out Difference: string): Boolean;
begin
  if Source <> Created then
    Exit(Fail(Path, IntToStr(Source), IntToStr(Created), Difference));
  Result := True;
end;

function CompareStringArrays(const Path: string;
  const Source, Created: TArray<string>; out Difference: string): Boolean;
var
  I: Integer;
begin
  if not CompareIntegers(Path + '.count', Length(Source), Length(Created),
    Difference) then
    Exit(False);
  for I := 0 to High(Source) do
    if not CompareStrings(Format('%s[%d]', [Path, I]), Source[I], Created[I],
      Difference) then
      Exit(False);
  Result := True;
end;

function CompareTrackInfo(const Path: string;
  const Source, Created: TAul2MIRAIParameterInfo;
  out Difference: string): Boolean;
var
  I: Integer;
begin
  if not CompareBooleans(Path + '.available', Source.TrackInfoAvailable,
    Created.TrackInfoAvailable, Difference) then
    Exit(False);
  if not Source.TrackInfoAvailable then
    Exit(True);
  if not CompareStrings(Path + '.mode', Source.TrackMode, Created.TrackMode,
    Difference) or
     not CompareBooleans(Path + '.accelerate', Source.TrackAccelerate,
       Created.TrackAccelerate, Difference) or
     not CompareBooleans(Path + '.decelerate', Source.TrackDecelerate,
       Created.TrackDecelerate, Difference) or
     not CompareBooleans(Path + '.ignore_midpoint',
       Source.TrackIgnoreMidpoint, Created.TrackIgnoreMidpoint, Difference) or
     not CompareBooleans(Path + '.time_control', Source.TrackTimeControl,
       Created.TrackTimeControl, Difference) or
     not CompareIntegers(Path + '.group_count', Source.TrackGroupCount,
       Created.TrackGroupCount, Difference) or
     not CompareIntegers(Path + '.group_index', Source.TrackGroupIndex,
       Created.TrackGroupIndex, Difference) or
     not CompareStrings(Path + '.group_name', Source.TrackGroupName,
       Created.TrackGroupName, Difference) or
     not CompareIntegers(Path + '.parameter_count',
       Length(Source.TrackParameters), Length(Created.TrackParameters),
       Difference) then
    Exit(False);
  for I := 0 to High(Source.TrackParameters) do
    if Source.TrackParameters[I] <> Created.TrackParameters[I] then
      Exit(Fail(Format('%s.parameters[%d]', [Path, I]),
        FloatToStr(Source.TrackParameters[I]),
        FloatToStr(Created.TrackParameters[I]), Difference));
  Result := True;
end;

function CompareEffectDetails(const Source, Created: TAul2MIRAIObjectInfo;
  out Difference: string): Boolean;
var
  EffectIndex   : Integer;
  ParameterIndex: Integer;
  Path          : string;
begin
  if not CompareIntegers('effect_details.count',
    Length(Source.EffectDetails), Length(Created.EffectDetails),
    Difference) then
    Exit(False);
  for EffectIndex := 0 to High(Source.EffectDetails) do
  begin
    Path := Format('effect_details[%d]', [EffectIndex]);
    if not CompareStrings(Path + '.name', Source.EffectDetails[EffectIndex].Name,
      Created.EffectDetails[EffectIndex].Name, Difference) or
       not CompareBooleans(Path + '.state_available',
         Source.EffectDetails[EffectIndex].StateAvailable,
         Created.EffectDetails[EffectIndex].StateAvailable, Difference) then
      Exit(False);
    if Source.EffectDetails[EffectIndex].StateAvailable and
       (not CompareBooleans(Path + '.enabled',
          Source.EffectDetails[EffectIndex].Enabled,
          Created.EffectDetails[EffectIndex].Enabled, Difference) or
        not CompareBooleans(Path + '.locked',
          Source.EffectDetails[EffectIndex].Locked,
          Created.EffectDetails[EffectIndex].Locked, Difference)) then
      Exit(False);
    if not CompareIntegers(Path + '.parameter_count',
      Length(Source.EffectDetails[EffectIndex].Parameters),
      Length(Created.EffectDetails[EffectIndex].Parameters), Difference) then
      Exit(False);
    for ParameterIndex := 0 to
      High(Source.EffectDetails[EffectIndex].Parameters) do
    begin
      Path := Format('effect_details[%d].parameters[%d]',
        [EffectIndex, ParameterIndex]);
      if Source.EffectDetails[EffectIndex].Parameters[ParameterIndex].Truncated or
         Created.EffectDetails[EffectIndex].Parameters[ParameterIndex].Truncated then
      begin
        Difference := Path +
          ' is truncated, so recreation equivalence cannot be proven.';
        Exit(False);
      end;
      if not CompareStrings(Path + '.name',
        Source.EffectDetails[EffectIndex].Parameters[ParameterIndex].Name,
        Created.EffectDetails[EffectIndex].Parameters[ParameterIndex].Name,
        Difference) or
         not CompareStrings(Path + '.value',
        Source.EffectDetails[EffectIndex].Parameters[ParameterIndex].Value,
        Created.EffectDetails[EffectIndex].Parameters[ParameterIndex].Value,
        Difference) or
         not CompareTrackInfo(Path + '.track_info',
        Source.EffectDetails[EffectIndex].Parameters[ParameterIndex],
        Created.EffectDetails[EffectIndex].Parameters[ParameterIndex],
        Difference) then
        Exit(False);
    end;
  end;
  Result := True;
end;

function CompareEffectStates(const Source, Created: TAul2MIRAIObjectInfo;
  out Difference: string): Boolean;
var
  I   : Integer;
  Path: string;
begin
  if not CompareIntegers('effect_states.count', Length(Source.EffectStates),
    Length(Created.EffectStates), Difference) then
    Exit(False);
  for I := 0 to High(Source.EffectStates) do
  begin
    Path := Format('effect_states[%d]', [I]);
    if not CompareStrings(Path + '.name', Source.EffectStates[I].Name,
      Created.EffectStates[I].Name, Difference) or
       not CompareBooleans(Path + '.enabled', Source.EffectStates[I].Enabled,
         Created.EffectStates[I].Enabled, Difference) or
       not CompareBooleans(Path + '.locked', Source.EffectStates[I].Locked,
         Created.EffectStates[I].Locked, Difference) then
      Exit(False);
  end;
  Result := True;
end;

function CompareSections(const Source, Created: TAul2MIRAIObjectInfo;
  out Difference: string): Boolean;
var
  CreatedOffset: Integer;
  I            : Integer;
  SourceOffset : Integer;
begin
  if not CompareIntegers('sections.count', Length(Source.SectionFrames),
    Length(Created.SectionFrames), Difference) then
    Exit(False);
  for I := 0 to High(Source.SectionFrames) do
  begin
    SourceOffset := Source.SectionFrames[I] - Source.StartFrame;
    CreatedOffset := Created.SectionFrames[I] - Created.StartFrame;
    if not CompareIntegers(Format('sections[%d].relative_frame', [I]),
      SourceOffset, CreatedOffset, Difference) then
      Exit(False);
  end;
  Result := True;
end;

function CompareRecreatedObject(const Source, Created: TAul2MIRAIObjectInfo;
  out Difference: string): Boolean;
begin
  Difference := '';
  if not CompareIntegers('frame_length',
       Source.EndFrame - Source.StartFrame + 1,
       Created.EndFrame - Created.StartFrame + 1, Difference) or
     not CompareStrings('name', Source.Name, Created.Name, Difference) or
     not CompareStrings('primary_effect', Source.PrimaryEffect,
       Created.PrimaryEffect, Difference) or
     not CompareStrings('object_type', Source.ObjectType,
       Created.ObjectType, Difference) or
     not CompareStrings('material_path', Source.MaterialPath,
       Created.MaterialPath, Difference) or
     not CompareStringArrays('effects', Source.Effects, Created.Effects,
       Difference) or
     not CompareSections(Source, Created, Difference) or
     not CompareEffectStates(Source, Created, Difference) or
     not CompareEffectDetails(Source, Created, Difference) then
    Exit(False);
  Result := True;
end;

end.
