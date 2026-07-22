unit Aul2MIRAIParameterWriter;

// Applies validated parameter changes inside one AviUtl2 edit section.
// AviUtl2 registers every changed item in the callback as one Undo operation.

interface

uses
  AviUtl2PluginTypes,
  Aul2MIRAIParameterPreview;

function ApplyParameterChange(EditHandle: PEditHandle;
  const Preview: TAul2MIRAIParameterPreview; out VerifiedValue,
  ErrorCode, ErrorMessage: string): Boolean;
function ApplyParameterChanges(EditHandle: PEditHandle;
  const Previews: TArray<TAul2MIRAIParameterPreview>;
  out VerifiedValues: TArray<string>; out ErrorCode,
  ErrorMessage: string): Boolean;

implementation

uses
  System.Hash,
  System.SysUtils,
  Aul2MIRAIObjectAlias,
  Aul2MIRAISelection;

type
  TParameterWriteContext = class
  public
    Previews       : TArray<TAul2MIRAIParameterPreview>;
    Handles        : TArray<TObjectHandle>;
    VerifiedValues : TArray<string>;
    ErrorCode      : string;
    ErrorMessage   : string;
    RollbackFailed : Boolean;
    LastAppliedIndex: Integer;
  end;

procedure Fail(Context: TParameterWriteContext; ChangeIndex: Integer;
  const Code, MessageText: string);
begin
  Context.ErrorCode := Code;
  Context.ErrorMessage := Format('changes[%d]: %s',
    [ChangeIndex, MessageText]);
  if Context.RollbackFailed then
    Context.ErrorMessage := Context.ErrorMessage +
      ' Automatic rollback was incomplete.';
end;

procedure RollbackChanges(Context: TParameterWriteContext;
  Edit: PEditSection; LastIndex: Integer);
var
  I         : Integer;
  Utf8Value : UTF8String;
begin
  for I := LastIndex downto 0 do
    if Context.Previews[I].WillChange and (Context.Handles[I] <> nil) then
    begin
      Utf8Value := UTF8String(Context.Previews[I].BeforeValue);
      if not Edit^.SetObjectItemValue(Context.Handles[I],
        PWideChar(Context.Previews[I].EffectSelector),
        PWideChar(Context.Previews[I].ItemName), PAnsiChar(Utf8Value)) then
        Context.RollbackFailed := True;
    end;
end;

function ValidateTarget(Context: TParameterWriteContext;
  Edit: PEditSection; ChangeIndex: Integer;
  const Selected: TObjectHandleArray): Boolean;
var
  AliasText   : string;
  CurrentText : string;
  LayerFrame  : TObjectLayerFrame;
  Obj         : TObjectHandle;
  Preview     : TAul2MIRAIParameterPreview;
  ReadValue   : PAnsiChar;
begin
  Result := False;
  Preview := Context.Previews[ChangeIndex];
  Obj := Edit^.FindObject(Preview.Layer, Preview.StartFrame);
  if Obj = nil then
  begin
    Fail(Context, ChangeIndex, 'target_changed',
      'The target object no longer exists at the expected position.');
    Exit;
  end;

  LayerFrame := Edit^.GetObjectLayerFrame(Obj);
  if (LayerFrame.Layer <> Preview.Layer) or
     (LayerFrame.StartFrame <> Preview.StartFrame) or
     (LayerFrame.EndFrame <> Preview.EndFrame) then
  begin
    Fail(Context, ChangeIndex, 'target_changed',
      'The target object range changed before the edit.');
    Exit;
  end;
  if not ContainsObjectHandle(Selected, Obj) then
  begin
    Fail(Context, ChangeIndex, 'target_not_selected',
      'The target object is not currently selected.');
    Exit;
  end;

  AliasText := CopyUtf8Text(Edit^.GetObjectAlias(Obj));
  if not SameText(LowerCase(THashSHA2.GetHashString(AliasText)),
    Preview.ContentDigest) then
  begin
    Fail(Context, ChangeIndex, 'target_changed',
      'The target object content changed before the edit.');
    Exit;
  end;

  ReadValue := Edit^.GetObjectItemValue(Obj,
    PWideChar(Preview.EffectSelector), PWideChar(Preview.ItemName));
  if ReadValue = nil then
  begin
    Fail(Context, ChangeIndex, 'item_not_found',
      'AviUtl2 could not read the target item before the edit.');
    Exit;
  end;
  CurrentText := CopyUtf8Text(ReadValue);
  if CurrentText <> Preview.BeforeValue then
  begin
    Fail(Context, ChangeIndex, 'value_changed',
      'The target item value changed before the edit.');
    Exit;
  end;

  Context.Handles[ChangeIndex] := Obj;
  Context.VerifiedValues[ChangeIndex] := CurrentText;
  Result := True;
end;

procedure WriteParametersCallback(Param: Pointer; Edit: PEditSection); cdecl;
var
  Context     : TParameterWriteContext;
  FocusHandle : TObjectHandle;
  I           : Integer;
  ReadValue   : PAnsiChar;
  Selected    : TObjectHandleArray;
  Utf8Value   : UTF8String;
begin
  Context := TParameterWriteContext(Param);
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

    SetLength(Context.Handles, Length(Context.Previews));
    SetLength(Context.VerifiedValues, Length(Context.Previews));
    for I := 0 to High(Context.Previews) do
      if not ValidateTarget(Context, Edit, I, Selected) then
        Exit;

    for I := 0 to High(Context.Previews) do
    begin
      if not Context.Previews[I].WillChange then
        Continue;
      Utf8Value := UTF8String(Context.Previews[I].AfterValue);
      if not Edit^.SetObjectItemValue(Context.Handles[I],
        PWideChar(Context.Previews[I].EffectSelector),
        PWideChar(Context.Previews[I].ItemName), PAnsiChar(Utf8Value)) then
      begin
        RollbackChanges(Context, Edit, I - 1);
        Fail(Context, I, 'write_rejected',
          'AviUtl2 rejected the parameter change.');
        Exit;
      end;
      Context.LastAppliedIndex := I;

      ReadValue := Edit^.GetObjectItemValue(Context.Handles[I],
        PWideChar(Context.Previews[I].EffectSelector),
        PWideChar(Context.Previews[I].ItemName));
      if ReadValue <> nil then
        Context.VerifiedValues[I] := CopyUtf8Text(ReadValue)
      else
        Context.VerifiedValues[I] := '';
      if Context.VerifiedValues[I] <> Context.Previews[I].AfterValue then
      begin
        RollbackChanges(Context, Edit, I);
        Fail(Context, I, 'write_verification_failed',
          'The value read after the edit did not match the requested value.');
        Exit;
      end;
    end;
  except
    on E: Exception do
    begin
      RollbackChanges(Context, Edit, Context.LastAppliedIndex);
      Context.ErrorCode := 'write_failed';
      Context.ErrorMessage := E.ClassName + ': ' + E.Message;
      if Context.RollbackFailed then
        Context.ErrorMessage := Context.ErrorMessage +
          ' Automatic rollback was incomplete.';
    end;
  end;
end;

function ApplyParameterChanges(EditHandle: PEditHandle;
  const Previews: TArray<TAul2MIRAIParameterPreview>;
  out VerifiedValues: TArray<string>; out ErrorCode,
  ErrorMessage: string): Boolean;
var
  Context: TParameterWriteContext;
begin
  Result := False;
  SetLength(VerifiedValues, 0);
  ErrorCode := '';
  ErrorMessage := '';
  if Length(Previews) = 0 then
  begin
    ErrorCode := 'empty_changes';
    ErrorMessage := 'At least one change is required.';
    Exit;
  end;
  if EditHandle = nil then
  begin
    ErrorCode := 'edit_unavailable';
    ErrorMessage := 'AviUtl2 edit handle is not available.';
    Exit;
  end;
  if not Assigned(EditHandle^.CallEditSectionParam) then
  begin
    ErrorCode := 'edit_unavailable';
    ErrorMessage := 'AviUtl2 does not provide call_edit_section_param.';
    Exit;
  end;

  Context := TParameterWriteContext.Create;
  try
    Context.Previews := Previews;
    Context.LastAppliedIndex := -1;
    if not EditHandle^.CallEditSectionParam(Context,
      @WriteParametersCallback) then
    begin
      ErrorCode := 'edit_rejected';
      ErrorMessage := 'AviUtl2 rejected the edit request.';
      Exit;
    end;
    VerifiedValues := Context.VerifiedValues;
    ErrorCode := Context.ErrorCode;
    ErrorMessage := Context.ErrorMessage;
    Result := ErrorCode = '';
  finally
    Context.Free;
  end;
end;

function ApplyParameterChange(EditHandle: PEditHandle;
  const Preview: TAul2MIRAIParameterPreview; out VerifiedValue,
  ErrorCode, ErrorMessage: string): Boolean;
var
  Previews      : TArray<TAul2MIRAIParameterPreview>;
  VerifiedValues: TArray<string>;
begin
  SetLength(Previews, 1);
  Previews[0] := Preview;
  Result := ApplyParameterChanges(EditHandle, Previews, VerifiedValues,
    ErrorCode, ErrorMessage);
  if Length(VerifiedValues) > 0 then
    VerifiedValue := VerifiedValues[0]
  else
    VerifiedValue := '';
end;

end.
