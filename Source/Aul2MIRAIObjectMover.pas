unit Aul2MIRAIObjectMover;

// Moves validated objects in one AviUtl2 edit section and restores earlier
// moves when a later move fails.

interface

uses
  AviUtl2PluginTypes,
  Aul2MIRAIObjectMove;

function ApplyObjectMoves(EditHandle: PEditHandle;
  const Previews: TArray<TAul2MIRAIObjectMovePreview>;
  out ErrorCode, ErrorMessage: string): Boolean;

implementation

uses
  System.Hash,
  System.SysUtils,
  Aul2MIRAIObjectAlias,
  Aul2MIRAISelection;

type
  TObjectMoveContext = class
  public
    Previews       : TArray<TAul2MIRAIObjectMovePreview>;
    Handles        : TArray<TObjectHandle>;
    LastApplied    : Integer;
    RollbackFailed : Boolean;
    ErrorCode      : string;
    ErrorMessage   : string;
  end;

procedure SetFailure(Context: TObjectMoveContext; MoveIndex: Integer;
  const Code, MessageText: string);
begin
  Context.ErrorCode := Code;
  Context.ErrorMessage := Format('moves[%d]: %s', [MoveIndex, MessageText]);
  if Context.RollbackFailed then
    Context.ErrorMessage := Context.ErrorMessage +
      ' Automatic rollback was incomplete.';
end;

procedure RollbackMoves(Context: TObjectMoveContext; Edit: PEditSection;
  LastIndex: Integer);
var
  I: Integer;
begin
  for I := LastIndex downto 0 do
    if Context.Previews[I].WillMove and (Context.Handles[I] <> nil) then
      if not Edit^.MoveObject(Context.Handles[I],
        Context.Previews[I].BeforeLayer,
        Context.Previews[I].BeforeStart) then
        Context.RollbackFailed := True;
end;

function ValidateMoveTarget(Context: TObjectMoveContext;
  Edit: PEditSection; MoveIndex: Integer;
  const Selected: TObjectHandleArray): Boolean;
var
  AliasText : string;
  LayerFrame: TObjectLayerFrame;
  Obj       : TObjectHandle;
  Preview   : TAul2MIRAIObjectMovePreview;
begin
  Result := False;
  Preview := Context.Previews[MoveIndex];
  Obj := Edit^.FindObject(Preview.BeforeLayer, Preview.BeforeStart);
  if Obj = nil then
  begin
    SetFailure(Context, MoveIndex, 'target_changed',
      'The target object no longer exists at the expected position.');
    Exit;
  end;
  LayerFrame := Edit^.GetObjectLayerFrame(Obj);
  if (LayerFrame.Layer <> Preview.BeforeLayer) or
     (LayerFrame.StartFrame <> Preview.BeforeStart) or
     (LayerFrame.EndFrame <> Preview.BeforeEnd) then
  begin
    SetFailure(Context, MoveIndex, 'target_changed',
      'The target object range changed before the move.');
    Exit;
  end;
  if not ContainsObjectHandle(Selected, Obj) then
  begin
    SetFailure(Context, MoveIndex, 'target_not_selected',
      'The target object is not currently selected.');
    Exit;
  end;
  AliasText := CopyUtf8Text(Edit^.GetObjectAlias(Obj));
  if not SameText(LowerCase(THashSHA2.GetHashString(AliasText)),
    Preview.ContentDigest) then
  begin
    SetFailure(Context, MoveIndex, 'target_changed',
      'The target object content changed before the move.');
    Exit;
  end;
  Context.Handles[MoveIndex] := Obj;
  Result := True;
end;

procedure MoveObjectsCallback(Param: Pointer; Edit: PEditSection); cdecl;
var
  Context    : TObjectMoveContext;
  FocusHandle: TObjectHandle;
  I          : Integer;
  LayerFrame : TObjectLayerFrame;
  Selected   : TObjectHandleArray;
begin
  Context := TObjectMoveContext(Param);
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
    for I := 0 to High(Context.Previews) do
      if not ValidateMoveTarget(Context, Edit, I, Selected) then
        Exit;

    for I := 0 to High(Context.Previews) do
    begin
      if not Context.Previews[I].WillMove then
        Continue;
      if not Edit^.MoveObject(Context.Handles[I],
        Context.Previews[I].AfterLayer,
        Context.Previews[I].AfterStart) then
      begin
        RollbackMoves(Context, Edit, I - 1);
        SetFailure(Context, I, 'move_rejected',
          'AviUtl2 rejected the object move.');
        Exit;
      end;
      Context.LastApplied := I;
      LayerFrame := Edit^.GetObjectLayerFrame(Context.Handles[I]);
      if (LayerFrame.Layer <> Context.Previews[I].AfterLayer) or
         (LayerFrame.StartFrame <> Context.Previews[I].AfterStart) or
         (LayerFrame.EndFrame <> Context.Previews[I].AfterEnd) then
      begin
        RollbackMoves(Context, Edit, I);
        SetFailure(Context, I, 'move_verification_failed',
          'The object range after the move did not match the request.');
        Exit;
      end;
    end;
  except
    on E: Exception do
    begin
      RollbackMoves(Context, Edit, Context.LastApplied);
      Context.ErrorCode := 'move_failed';
      Context.ErrorMessage := E.ClassName + ': ' + E.Message;
      if Context.RollbackFailed then
        Context.ErrorMessage := Context.ErrorMessage +
          ' Automatic rollback was incomplete.';
    end;
  end;
end;

function ApplyObjectMoves(EditHandle: PEditHandle;
  const Previews: TArray<TAul2MIRAIObjectMovePreview>;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  Context: TObjectMoveContext;
begin
  Result := False;
  ErrorCode := '';
  ErrorMessage := '';
  if Length(Previews) = 0 then
  begin
    ErrorCode := 'empty_moves';
    ErrorMessage := 'At least one move is required.';
    Exit;
  end;
  if (EditHandle = nil) or
     not Assigned(EditHandle^.CallEditSectionParam) then
  begin
    ErrorCode := 'edit_unavailable';
    ErrorMessage := 'AviUtl2 edit section is not available.';
    Exit;
  end;
  Context := TObjectMoveContext.Create;
  try
    Context.Previews := Previews;
    Context.LastApplied := -1;
    if not EditHandle^.CallEditSectionParam(Context,
      @MoveObjectsCallback) then
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
