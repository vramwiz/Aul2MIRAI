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
  Aul2MIRAIObjectTypes,
  Aul2MIRAISelection;

type
  TObjectDuplicateContext = class
  public
    Previews     : TArray<TAul2MIRAIObjectDuplicatePreview>;
    SourceAliases: TArray<UTF8String>;
    Created      : TArray<TObjectHandle>;
    ErrorCode    : string;
    ErrorMessage : string;
  end;

function CopyWideText(Value: PWideChar): string;
begin
  if Value = nil then
    Exit('');
  Result := string(Value);
end;

function AliasesHaveSameEffects(const SourceAlias,
  CreatedAlias: string): Boolean;
var
  CreatedDetails: TArray<TAul2MIRAIEffectDetail>;
  I             : Integer;
  J             : Integer;
  SourceDetails : TArray<TAul2MIRAIEffectDetail>;
begin
  SourceDetails := ExtractEffectDetails(SourceAlias);
  CreatedDetails := ExtractEffectDetails(CreatedAlias);
  if Length(SourceDetails) <> Length(CreatedDetails) then
    Exit(False);
  for I := 0 to High(SourceDetails) do
  begin
    if SourceDetails[I].Name <> CreatedDetails[I].Name then
      Exit(False);
    if Length(SourceDetails[I].Parameters) <>
       Length(CreatedDetails[I].Parameters) then
      Exit(False);
    for J := 0 to High(SourceDetails[I].Parameters) do
      if (SourceDetails[I].Parameters[J].Name <>
          CreatedDetails[I].Parameters[J].Name) or
         (SourceDetails[I].Parameters[J].Value <>
          CreatedDetails[I].Parameters[J].Value) or
         SourceDetails[I].Parameters[J].Truncated or
         CreatedDetails[I].Parameters[J].Truncated then
        Exit(False);
  end;
  Result := True;
end;

procedure SetFailure(Context: TObjectDuplicateContext; DuplicateIndex: Integer;
  const Code, MessageText: string);
begin
  Context.ErrorCode := Code;
  Context.ErrorMessage := Format('duplicates[%d]: %s',
    [DuplicateIndex, MessageText]);
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

function ValidateSource(Context: TObjectDuplicateContext;
  Edit: PEditSection; DuplicateIndex: Integer;
  const Selected: TObjectHandleArray): Boolean;
var
  AliasText : string;
  LayerFrame: TObjectLayerFrame;
  Obj       : TObjectHandle;
  Preview   : TAul2MIRAIObjectDuplicatePreview;
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
  Context.SourceAliases[DuplicateIndex] := UTF8String(AliasText);
  Result := True;
end;

procedure DuplicateObjectsCallback(Param: Pointer; Edit: PEditSection); cdecl;
var
  AliasText  : string;
  Context    : TObjectDuplicateContext;
  FocusHandle: TObjectHandle;
  I          : Integer;
  LayerFrame : TObjectLayerFrame;
  Selected   : TObjectHandleArray;
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
    SetLength(Context.SourceAliases, Length(Context.Previews));
    SetLength(Context.Created, Length(Context.Previews));
    for I := 0 to High(Context.Previews) do
      if not ValidateSource(Context, Edit, I, Selected) then
        Exit;

    for I := 0 to High(Context.Previews) do
    begin
      Context.Created[I] := Edit^.CreateObjectFromAlias(
        PAnsiChar(Context.SourceAliases[I]), Context.Previews[I].TargetLayer,
        Context.Previews[I].TargetStart, Context.Previews[I].FrameLength);
      if Context.Created[I] = nil then
      begin
        RemoveCreated(Context, Edit, I - 1);
        SetFailure(Context, I, 'create_rejected',
          'AviUtl2 rejected the object duplication.');
        Exit;
      end;
      LayerFrame := Edit^.GetObjectLayerFrame(Context.Created[I]);
      if (LayerFrame.Layer <> Context.Previews[I].TargetLayer) or
         (LayerFrame.StartFrame <> Context.Previews[I].TargetStart) or
         (LayerFrame.EndFrame <> Context.Previews[I].TargetEnd) then
      begin
        RemoveCreated(Context, Edit, I);
        SetFailure(Context, I, 'create_verification_failed',
          'The created object range did not match the request.');
        Exit;
      end;
      AliasText := CopyUtf8Text(Edit^.GetObjectAlias(Context.Created[I]));
      if (CopyWideText(Edit^.GetObjectName(Context.Created[I])) <>
          Context.Previews[I].Name) or
         not AliasesHaveSameEffects(
           UTF8ToString(Context.SourceAliases[I]), AliasText) then
      begin
        RemoveCreated(Context, Edit, I);
        SetFailure(Context, I, 'create_verification_failed',
          'The created object settings did not match the source.');
        Exit;
      end;
    end;
  except
    on E: Exception do
    begin
      RemoveCreated(Context, Edit, High(Context.Created));
      Context.ErrorCode := 'create_failed';
      Context.ErrorMessage := E.ClassName + ': ' + E.Message;
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
