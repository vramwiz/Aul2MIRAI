unit Aul2MIRAIObjectDuplicator;

// Creates validated object copies in one AviUtl2 edit section and removes
// copies already created when a later operation fails.

interface

uses
  AviUtl2PluginTypes,
  Aul2MIRAIObjectDuplicate;

function ApplyObjectDuplicates(EditHandle: PEditHandle;
  const Previews: TArray<TAul2MIRAIObjectDuplicatePreview>;
  out ErrorCode, ErrorMessage: string): Boolean;

implementation

uses
  System.Hash,
  System.SysUtils,
  Aul2MIRAIObjectAlias,
  Aul2MIRAIObjectEquivalence,
  Aul2MIRAIObjectReader,
  Aul2MIRAIObjectTypes,
  Aul2MIRAISelection;

type
  TObjectDuplicateContext = class
  public
    Previews     : TArray<TAul2MIRAIObjectDuplicatePreview>;
    OriginalAliases: TArray<UTF8String>;
    OriginalInfos: TArray<TAul2MIRAIObjectInfo>;
    SourceAliases: TArray<UTF8String>;
    SourceInfos  : TArray<TAul2MIRAIObjectInfo>;
    SourceHandles: TArray<TObjectHandle>;
    SourceFocused: TArray<Boolean>;
    Created      : TArray<TObjectHandle>;
    ReplacementSourceDeleted: Boolean;
    ErrorCode    : string;
    ErrorMessage : string;
  end;

procedure SetFailure(Context: TObjectDuplicateContext; DuplicateIndex: Integer;
  const Code, MessageText: string);
begin
  Context.ErrorCode := Code;
  Context.ErrorMessage := Format('duplicates[%d]: %s',
    [DuplicateIndex, MessageText]);
end;

function AddRepeatedEffectExpectation(var Info: TAul2MIRAIObjectInfo;
  const EffectName: string; out ErrorMessage: string): Boolean;
var
  EffectIndex: Integer;
  I          : Integer;
begin
  Result := False;
  ErrorMessage := '';
  EffectIndex := -1;
  for I := 0 to High(Info.Effects) do
    if Info.Effects[I] = EffectName then
      EffectIndex := I;
  if EffectIndex < 0 then
  begin
    ErrorMessage := 'The requested repeat_effect was not found.';
    Exit;
  end;
  if Length(Info.EffectDetails) <> Length(Info.Effects) then
  begin
    ErrorMessage := 'Complete effect details are required to repeat an effect.';
    Exit;
  end;
  if (Length(Info.EffectStates) <> 0) and
     (Length(Info.EffectStates) <> Length(Info.Effects)) then
  begin
    ErrorMessage := 'Complete effect states are required to repeat an effect.';
    Exit;
  end;

  SetLength(Info.Effects, Length(Info.Effects) + 1);
  Info.Effects[High(Info.Effects)] := EffectName;
  SetLength(Info.EffectDetails, Length(Info.EffectDetails) + 1);
  Info.EffectDetails[High(Info.EffectDetails)] :=
    Info.EffectDetails[EffectIndex];
  if Length(Info.EffectStates) > 0 then
  begin
    SetLength(Info.EffectStates, Length(Info.EffectStates) + 1);
    Info.EffectStates[High(Info.EffectStates)] :=
      Info.EffectStates[EffectIndex];
  end;
  Result := True;
end;

procedure RemoveCreated(Context: TObjectDuplicateContext;
  Edit: PEditSection; LastIndex: Integer);
var
  I: Integer;
begin
  for I := LastIndex downto 0 do
    if Context.Created[I] <> nil then
      Edit^.DeleteObject(Context.Created[I]);
end;

function RestoreReplacementSource(Context: TObjectDuplicateContext;
  Edit: PEditSection; DuplicateIndex: Integer; out RestoreError: string): Boolean;
var
  Difference  : string;
  Restored     : TObjectHandle;
  RestoredInfo : TAul2MIRAIObjectInfo;
begin
  Result := False;
  RestoreError := '';
  if Context.Created[DuplicateIndex] <> nil then
  begin
    Edit^.DeleteObject(Context.Created[DuplicateIndex]);
    Context.Created[DuplicateIndex] := nil;
  end;
  Restored := Edit^.CreateObjectFromAlias(
    PAnsiChar(Context.OriginalAliases[DuplicateIndex]),
    Context.Previews[DuplicateIndex].SourceLayer,
    Context.Previews[DuplicateIndex].SourceStart,
    Context.Previews[DuplicateIndex].FrameLength);
  if Restored = nil then
  begin
    RestoreError :=
      'CRITICAL: AviUtl2 rejected restoration of the original object.';
    Exit;
  end;
  Context.ReplacementSourceDeleted := False;
  if not ReadObjectSnapshot(Edit, Restored, True, False, RestoredInfo,
    Difference) then
  begin
    RestoreError := 'The restored original could not be verified: ' +
      Difference;
    Exit;
  end;
  if not CompareRecreatedObject(Context.OriginalInfos[DuplicateIndex],
    RestoredInfo, Difference) then
  begin
    RestoreError := 'The restored original did not match: ' + Difference;
    Exit;
  end;
  if Context.SourceFocused[DuplicateIndex] then
    Edit^.SetFocusObject(Restored);
  Result := True;
end;

function ValidateSource(Context: TObjectDuplicateContext;
  Edit: PEditSection; DuplicateIndex: Integer;
  const Selected: TObjectHandleArray): Boolean;
var
  AliasText : string;
  LayerFrame: TObjectLayerFrame;
  Obj       : TObjectHandle;
  Preview   : TAul2MIRAIObjectDuplicatePreview;
  TransformedAlias: string;
begin
  Result := False;
  Preview := Context.Previews[DuplicateIndex];
  Obj := Edit^.FindObject(Preview.SourceLayer, Preview.SourceStart);
  if Obj = nil then
  begin
    SetFailure(Context, DuplicateIndex, 'source_changed',
      'The source object no longer exists at the expected position.');
    Exit;
  end;
  LayerFrame := Edit^.GetObjectLayerFrame(Obj);
  if (LayerFrame.Layer <> Preview.SourceLayer) or
     (LayerFrame.StartFrame <> Preview.SourceStart) or
     (LayerFrame.EndFrame <> Preview.SourceEnd) then
  begin
    SetFailure(Context, DuplicateIndex, 'source_changed',
      'The source object range changed before duplication.');
    Exit;
  end;
  if not ContainsObjectHandle(Selected, Obj) then
  begin
    SetFailure(Context, DuplicateIndex, 'source_not_selected',
      'The source object is not currently selected.');
    Exit;
  end;
  AliasText := CopyUtf8Text(Edit^.GetObjectAlias(Obj));
  if not SameText(LowerCase(THashSHA2.GetHashString(AliasText)),
    Preview.ContentDigest) then
  begin
    SetFailure(Context, DuplicateIndex, 'source_changed',
      'The source object content changed before duplication.');
    Exit;
  end;
  if not ReadObjectSnapshot(Edit, Obj, True, False,
    Context.SourceInfos[DuplicateIndex], Context.ErrorMessage) then
  begin
    Context.ErrorCode := 'source_read_failed';
    Context.ErrorMessage := Format('duplicates[%d]: %s',
      [DuplicateIndex, Context.ErrorMessage]);
    Exit;
  end;
  if Preview.RepeatEffect <> '' then
  begin
    if not AppendRepeatedEffectBlock(AliasText, Preview.RepeatEffect,
      TransformedAlias, Context.ErrorMessage) or
       not AddRepeatedEffectExpectation(Context.SourceInfos[DuplicateIndex],
      Preview.RepeatEffect, Context.ErrorMessage) then
    begin
      Context.ErrorCode := 'repeat_effect_failed';
      Context.ErrorMessage := Format('duplicates[%d]: %s',
        [DuplicateIndex, Context.ErrorMessage]);
      Exit;
    end;
  Context.SourceAliases[DuplicateIndex] := UTF8String(TransformedAlias);
  end
  else
    Context.SourceAliases[DuplicateIndex] := UTF8String(AliasText);
  Context.OriginalAliases[DuplicateIndex] := UTF8String(AliasText);
  Context.OriginalInfos[DuplicateIndex] := Context.SourceInfos[DuplicateIndex];
  if Preview.RepeatEffect <> '' then
  begin
    // SourceInfos is the expected generated state.  Re-read the original
    // because AddRepeatedEffectExpectation changed the expected arrays.
    if not ReadObjectSnapshot(Edit, Obj, True, False,
      Context.OriginalInfos[DuplicateIndex], Context.ErrorMessage) then
    begin
      Context.ErrorCode := 'source_read_failed';
      Context.ErrorMessage := Format('duplicates[%d]: %s',
        [DuplicateIndex, Context.ErrorMessage]);
      Exit;
    end;
  end;
  Context.SourceHandles[DuplicateIndex] := Obj;
  Result := True;
end;

procedure DuplicateObjectsCallback(Param: Pointer; Edit: PEditSection); cdecl;
var
  Context    : TObjectDuplicateContext;
  CreatedInfo: TAul2MIRAIObjectInfo;
  Difference : string;
  FocusHandle: TObjectHandle;
  I          : Integer;
  LayerFrame : TObjectLayerFrame;
  Selected   : TObjectHandleArray;
  RestoreError: string;
begin
  Context := TObjectDuplicateContext(Param);
  if Context = nil then
    Exit;
  try
    if Edit = nil then
    begin
      Context.ErrorCode := 'edit_unavailable';
      Context.ErrorMessage := 'AviUtl2 returned no edit section.';
      Exit;
    end;
    if not ReadSelectedObjectHandles(Edit, Selected, FocusHandle,
      Context.ErrorMessage) then
    begin
      Context.ErrorCode := 'selection_read_failed';
      Exit;
    end;
    SetLength(Context.OriginalAliases, Length(Context.Previews));
    SetLength(Context.OriginalInfos, Length(Context.Previews));
    SetLength(Context.SourceAliases, Length(Context.Previews));
    SetLength(Context.SourceInfos, Length(Context.Previews));
    SetLength(Context.SourceHandles, Length(Context.Previews));
    SetLength(Context.SourceFocused, Length(Context.Previews));
    SetLength(Context.Created, Length(Context.Previews));
    for I := 0 to High(Context.Previews) do
    begin
      if not ValidateSource(Context, Edit, I, Selected) then
        Exit;
      Context.SourceFocused[I] := Context.SourceHandles[I] = FocusHandle;
    end;

    for I := 0 to High(Context.Previews) do
    begin
      if Context.Previews[I].ReplaceSource then
      begin
        Edit^.DeleteObject(Context.SourceHandles[I]);
        Context.ReplacementSourceDeleted := True;
      end;
      Context.Created[I] := Edit^.CreateObjectFromAlias(
        PAnsiChar(Context.SourceAliases[I]), Context.Previews[I].TargetLayer,
        Context.Previews[I].TargetStart, Context.Previews[I].FrameLength);
      if Context.Created[I] = nil then
      begin
        if Context.Previews[I].ReplaceSource then
        begin
          if not RestoreReplacementSource(Context, Edit, I,
            RestoreError) then
            SetFailure(Context, I, 'source_restore_failed', RestoreError)
          else
            SetFailure(Context, I, 'create_rejected',
              'AviUtl2 rejected the replacement object; the original was restored.');
        end
        else
        begin
          RemoveCreated(Context, Edit, I - 1);
          SetFailure(Context, I, 'create_rejected',
            'AviUtl2 rejected the object duplication.');
        end;
        Exit;
      end;
      LayerFrame := Edit^.GetObjectLayerFrame(Context.Created[I]);
      if (LayerFrame.Layer <> Context.Previews[I].TargetLayer) or
         (LayerFrame.StartFrame <> Context.Previews[I].TargetStart) or
         (LayerFrame.EndFrame <> Context.Previews[I].TargetEnd) then
      begin
        if Context.Previews[I].ReplaceSource then
        begin
          if not RestoreReplacementSource(Context, Edit, I,
            RestoreError) then
            SetFailure(Context, I, 'source_restore_failed', RestoreError)
          else
            SetFailure(Context, I, 'create_verification_failed',
              'The replacement range did not match; the original was restored.');
        end
        else
        begin
          RemoveCreated(Context, Edit, I);
          SetFailure(Context, I, 'create_verification_failed',
            'The created object range did not match the request.');
        end;
        Exit;
      end;
      if not ReadObjectSnapshot(Edit, Context.Created[I], True, False,
        CreatedInfo, Difference) then
      begin
        if Context.Previews[I].ReplaceSource then
        begin
          if not RestoreReplacementSource(Context, Edit, I,
            RestoreError) then
            SetFailure(Context, I, 'source_restore_failed', RestoreError)
          else
            SetFailure(Context, I, 'create_verification_failed',
              'The replacement could not be verified; the original was restored: ' +
              Difference);
        end
        else
        begin
          RemoveCreated(Context, Edit, I);
          SetFailure(Context, I, 'create_verification_failed',
            'The created object could not be read for verification: ' +
            Difference);
        end;
        Exit;
      end;
      if not CompareRecreatedObject(Context.SourceInfos[I], CreatedInfo,
        Difference) then
      begin
        if Context.Previews[I].ReplaceSource then
        begin
          if not RestoreReplacementSource(Context, Edit, I,
            RestoreError) then
            SetFailure(Context, I, 'source_restore_failed', RestoreError)
          else
            SetFailure(Context, I, 'create_verification_failed',
              'The replacement did not match; the original was restored: ' +
              Difference);
        end
        else
        begin
          RemoveCreated(Context, Edit, I);
          SetFailure(Context, I, 'create_verification_failed',
            'The created object did not match the source: ' + Difference);
        end;
        Exit;
      end;
      if Context.Previews[I].ReplaceSource then
      begin
        Context.ReplacementSourceDeleted := False;
        if Context.SourceFocused[I] then
          Edit^.SetFocusObject(Context.Created[I]);
      end;
    end;
  except
    on E: Exception do
    begin
      if (Length(Context.Previews) = 1) and
         Context.Previews[0].ReplaceSource and
         Context.ReplacementSourceDeleted then
        RestoreReplacementSource(Context, Edit, 0, RestoreError)
      else if (Length(Context.Previews) = 0) or
              not Context.Previews[0].ReplaceSource then
        RemoveCreated(Context, Edit, High(Context.Created));
      Context.ErrorCode := 'create_failed';
      Context.ErrorMessage := E.ClassName + ': ' + E.Message;
      if RestoreError <> '' then
        Context.ErrorMessage := Context.ErrorMessage + '; ' + RestoreError;
    end;
  end;
end;

function ApplyObjectDuplicates(EditHandle: PEditHandle;
  const Previews: TArray<TAul2MIRAIObjectDuplicatePreview>;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  Context: TObjectDuplicateContext;
begin
  Result := False;
  ErrorCode := '';
  ErrorMessage := '';
  if Length(Previews) = 0 then
  begin
    ErrorCode := 'empty_duplicates';
    ErrorMessage := 'At least one duplicate is required.';
    Exit;
  end;
  if (EditHandle = nil) or
     not Assigned(EditHandle^.CallEditSectionParam) then
  begin
    ErrorCode := 'edit_unavailable';
    ErrorMessage := 'AviUtl2 edit section is not available.';
    Exit;
  end;
  Context := TObjectDuplicateContext.Create;
  try
    Context.Previews := Previews;
    if not EditHandle^.CallEditSectionParam(Context,
      @DuplicateObjectsCallback) then
    begin
      ErrorCode := 'edit_rejected';
      ErrorMessage := 'AviUtl2 rejected the edit request.';
      Exit;
    end;
    ErrorCode := Context.ErrorCode;
    ErrorMessage := Context.ErrorMessage;
    Result := ErrorCode = '';
  finally
    Context.Free;
  end;
end;

end.
