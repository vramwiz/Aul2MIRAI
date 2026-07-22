unit Aul2MIRAIEditStateReader;

// EDIT_INFOと読み取り・編集セクションから現在の編集状態をコピーする。
interface

uses
  AviUtl2PluginTypes,
  Aul2MIRAIEditStateTypes;

function ReadCurrentEditState(EditHandle: PEditHandle;
  out State: TAul2MIRAIEditState; out ErrorMessage: string): Boolean;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.DateUtils,
  Aul2MIRAISelection;

type
  TEditStateContext = class
  public
    EditHandle   : PEditHandle;
    SceneName    : string;
    ProjectPath  : string;
    SelectedCount: Integer;
    ErrorMessage : string;
  end;

function CopyWideText(Value: PWideChar): string;
begin
  if Value = nil then
    Exit('');
  Result := string(Value);
end;

function EditModeName(EditHandle: PEditHandle): string;
begin
  case EditHandle^.GetEditState() of
    0: Result := 'edit';
    1: Result := 'play';
    2: Result := 'save';
  else
    Result := 'unknown';
  end;
end;

procedure ReadStateCallback(Param: Pointer; Edit: PEditSection); cdecl;
var
  Context    : TEditStateContext;
  ErrorMessage: string;
  FocusHandle: TObjectHandle;
  Handles    : TObjectHandleArray;
begin
  Context := TEditStateContext(Param);
  if (Context = nil) or (Edit = nil) then
    Exit;
  try
    Context.SceneName := CopyWideText(Edit^.GetSceneName());
    if ReadSelectedObjectHandles(Edit, Handles, FocusHandle, ErrorMessage) then
      Context.SelectedCount := Length(Handles)
    else
      Context.ErrorMessage := ErrorMessage;
  except
    on E: Exception do
      Context.ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

procedure ReadProjectPathCallback(Param: Pointer; Edit: PEditSection); cdecl;
var
  Context: TEditStateContext;
  Project: PProjectFile;
begin
  Context := TEditStateContext(Param);
  if (Context = nil) or (Edit = nil) or
     not Assigned(Edit^.GetProjectFile) then
    Exit;
  try
    Project := Edit^.GetProjectFile(Context.EditHandle);
    if (Project <> nil) and Assigned(Project^.GetProjectFilePath) then
      Context.ProjectPath := CopyWideText(Project^.GetProjectFilePath());
  except
    // 未保存または編集不可の状態では空文字のまま返す。
  end;
end;

function ReadCurrentEditState(EditHandle: PEditHandle;
  out State: TAul2MIRAIEditState; out ErrorMessage: string): Boolean;
var
  Context : TEditStateContext;
  EditInfo: TEditInfo;
  Started : UInt64;
begin
  State := Default(TAul2MIRAIEditState);
  ErrorMessage := '';
  Result := False;
  if EditHandle = nil then
  begin
    ErrorMessage := 'AviUtl2 edit handle is not available.';
    Exit;
  end;

  Context := TEditStateContext.Create;
  try
    Started := GetTickCount64;
    Context.EditHandle := EditHandle;
    FillChar(EditInfo, SizeOf(EditInfo), 0);
    EditHandle^.GetEditInfo(@EditInfo, SizeOf(EditInfo));

    State.SceneId := EditInfo.SceneId;
    State.Width := EditInfo.Width;
    State.Height := EditInfo.Height;
    State.Rate := EditInfo.Rate;
    State.Scale := EditInfo.Scale;
    State.SampleRate := EditInfo.SampleRate;
    State.CursorFrame := EditInfo.Frame;
    State.CursorLayer := EditInfo.Layer;
    State.FrameMax := EditInfo.FrameMax;
    State.LayerMax := EditInfo.LayerMax;
    State.DisplayFrameStart := EditInfo.DisplayFrameStart;
    State.DisplayLayerStart := EditInfo.DisplayLayerStart;
    State.DisplayFrameNum := EditInfo.DisplayFrameNum;
    State.DisplayLayerNum := EditInfo.DisplayLayerNum;
    State.SelectRangeStart := EditInfo.SelectRangeStart;
    State.SelectRangeEnd := EditInfo.SelectRangeEnd;
    State.GridBpmTempo := EditInfo.GridBpmTempo;
    State.GridBpmBeat := EditInfo.GridBpmBeat;
    State.GridBpmOffset := EditInfo.GridBpmOffset;
    State.EditMode := EditModeName(EditHandle);
    State.CapturedAtUtc := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',
      TTimeZone.Local.ToUniversalTime(Now));

    if not EditHandle^.CallReadSectionParam(Context, @ReadStateCallback) then
    begin
      ErrorMessage := 'AviUtl2 rejected the read request.';
      Exit;
    end;
    if Context.ErrorMessage <> '' then
    begin
      ErrorMessage := Context.ErrorMessage;
      Exit;
    end;

    if Assigned(EditHandle^.CallEditSectionParam) then
      EditHandle^.CallEditSectionParam(Context, @ReadProjectPathCallback);

    State.SceneName := Context.SceneName;
    State.ProjectPath := Context.ProjectPath;
    State.SelectedCount := Context.SelectedCount;
    State.ElapsedMs := GetTickCount64 - Started;
    Result := True;
  finally
    Context.Free;
  end;
end;

end.
