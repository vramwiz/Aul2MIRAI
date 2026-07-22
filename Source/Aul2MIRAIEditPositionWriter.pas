unit Aul2MIRAIEditPositionWriter;

// Applies a validated cursor and selection range change through one AviUtl2
// edit callback. These UI-state changes are not Undo operations.

interface

uses
  AviUtl2PluginTypes,
  Aul2MIRAIEditPosition;

function ApplyEditPosition(EditHandle: PEditHandle;
  const Preview: TAul2MIRAIEditPositionPreview;
  out ErrorCode, ErrorMessage: string): Boolean;

implementation

uses
  System.SysUtils;

type
  TEditPositionContext = class
  public
    Preview     : TAul2MIRAIEditPositionPreview;
    ErrorCode   : string;
    ErrorMessage: string;
  end;

procedure SetEditPositionCallback(Param: Pointer; Edit: PEditSection); cdecl;
var
  Context: TEditPositionContext;
begin
  Context := TEditPositionContext(Param);
  if Context = nil then
    Exit;
  try
    if (Edit = nil) or (Edit^.Info = nil) then
    begin
      Context.ErrorCode := 'edit_unavailable';
      Context.ErrorMessage := 'AviUtl2 returned no editable state.';
      Exit;
    end;
    if (Edit^.Info^.Layer <> Context.Preview.BeforeCursorLayer) or
       (Edit^.Info^.Frame <> Context.Preview.BeforeCursorFrame) or
       (Edit^.Info^.SelectRangeStart <>
          Context.Preview.BeforeSelectStart) or
       (Edit^.Info^.SelectRangeEnd <> Context.Preview.BeforeSelectEnd) then
    begin
      Context.ErrorCode := 'position_changed';
      Context.ErrorMessage :=
        'The cursor or selection changed before the request was applied.';
      Exit;
    end;
    if Context.Preview.SetCursor and Context.Preview.CursorWillChange then
      Edit^.SetCursorLayerFrame(Context.Preview.AfterCursorLayer,
        Context.Preview.AfterCursorFrame);
    if Context.Preview.SetSelection and
       Context.Preview.SelectionWillChange then
      Edit^.SetSelectRange(Context.Preview.AfterSelectStart,
        Context.Preview.AfterSelectEnd);
  except
    on E: Exception do
    begin
      Context.ErrorCode := 'position_write_failed';
      Context.ErrorMessage := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

function ApplyEditPosition(EditHandle: PEditHandle;
  const Preview: TAul2MIRAIEditPositionPreview;
  out ErrorCode, ErrorMessage: string): Boolean;
var
  Context: TEditPositionContext;
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
  Context := TEditPositionContext.Create;
  try
    Context.Preview := Preview;
    if not EditHandle^.CallEditSectionParam(Context,
      @SetEditPositionCallback) then
    begin
      ErrorCode := 'edit_rejected';
      ErrorMessage := 'AviUtl2 rejected the edit position request.';
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
