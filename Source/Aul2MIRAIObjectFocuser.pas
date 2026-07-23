unit Aul2MIRAIObjectFocuser;

// Resolves and revalidates an object inside one AviUtl2 edit callback, then
// changes the normal focus. Focus changes are UI state and create no Undo item.

interface

uses
  AviUtl2PluginTypes,
  Aul2MIRAIObjectFocus;

function ApplyObjectFocus(EditHandle: PEditHandle;
  const Preview: TAul2MIRAIObjectFocusPreview;
  out ErrorCode, ErrorMessage: string): Boolean;

implementation

uses
  System.SysUtils,
  Aul2MIRAIObjectReader,
  Aul2MIRAIObjectTypes;

type
  TObjectFocusContext = class
  public
    Preview     : TAul2MIRAIObjectFocusPreview;
    ErrorCode   : string;
    ErrorMessage: string;
  end;

function MatchesTarget(Edit: PEditSection; Obj: TObjectHandle;
  const Expected: TAul2MIRAIObjectFocusTarget;
  out ErrorMessage: string): Boolean;
var
  Current: TAul2MIRAIObjectInfo;
begin
  Result := False;
  ErrorMessage := '';
  if Obj = nil then
  begin
    ErrorMessage := 'The expected object is no longer available.';
    Exit;
  end;
  if not ReadObjectSnapshot(Edit, Obj, False, False, Current,
    ErrorMessage) then
    Exit;
  Result := (Current.Layer = Expected.Layer) and
    (Current.StartFrame = Expected.StartFrame) and
    (Current.EndFrame = Expected.EndFrame) and
    SameText(Current.ContentDigest, Expected.ContentDigest);
  if not Result then
    ErrorMessage := 'The object changed before focus was applied.';
end;

procedure SetObjectFocusCallback(Param: Pointer; Edit: PEditSection); cdecl;
var
  Context     : TObjectFocusContext;
  CurrentFocus: TObjectHandle;
  Target      : TObjectHandle;
begin
  Context := TObjectFocusContext(Param);
  if Context = nil then
    Exit;
  try
    if (Edit = nil) or not Assigned(Edit^.FindObject) or
       not Assigned(Edit^.GetFocusObject) or
       not Assigned(Edit^.SetFocusObject) then
    begin
      Context.ErrorCode := 'edit_unavailable';
      Context.ErrorMessage := 'AviUtl2 object focus API is not available.';
      Exit;
    end;
    CurrentFocus := Edit^.GetFocusObject();
    if Context.Preview.BeforeFocusAvailable then
    begin
      if not MatchesTarget(Edit, CurrentFocus,
        Context.Preview.BeforeFocus, Context.ErrorMessage) then
      begin
        Context.ErrorCode := 'focus_changed';
        Exit;
      end;
    end
    else if CurrentFocus <> nil then
    begin
      Context.ErrorCode := 'focus_changed';
      Context.ErrorMessage :=
        'Object focus changed before the request was applied.';
      Exit;
    end;
    Target := Edit^.FindObject(Context.Preview.Target.Layer,
      Context.Preview.Target.StartFrame);
    if not MatchesTarget(Edit, Target, Context.Preview.Target,
      Context.ErrorMessage) then
    begin
      Context.ErrorCode := 'target_changed';
      Exit;
    end;
    Edit^.SetFocusObject(Target);
  except
    on E: Exception do
    begin
      Context.ErrorCode := 'focus_write_failed';
      Context.ErrorMessage := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

function ApplyObjectFocus(EditHandle: PEditHandle;
  const Preview: TAul2MIRAIObjectFocusPreview;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  Context: TObjectFocusContext;
begin
  Result := False;
  ErrorCode := '';
  ErrorMessage := '';
  if (EditHandle = nil) or
     not Assigned(EditHandle^.CallEditSectionParam) then
  begin
    ErrorCode := 'edit_unavailable';
    ErrorMessage := 'AviUtl2 edit section is not available.';
    Exit;
  end;
  Context := TObjectFocusContext.Create;
  try
    Context.Preview := Preview;
    if not EditHandle^.CallEditSectionParam(Context,
      @SetObjectFocusCallback) then
    begin
      ErrorCode := 'edit_rejected';
      ErrorMessage := 'AviUtl2 rejected the object focus request.';
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
