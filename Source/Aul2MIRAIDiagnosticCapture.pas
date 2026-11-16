unit Aul2MIRAIDiagnosticCapture;

// MMD診断表示の開始、フレーム取得、確実な解除を一体の読取操作として扱う。

interface

uses
  Aul2MIRAISnapshotIdentity;

// プロジェクト状態を変更せず、一時的なMMD診断表示をBMPへ取得する。
function CaptureMmdDiagnosticView(const Command: string;
  const Identity: TAul2MIRAISnapshotIdentity; TargetIndex, EffectIndex: Integer;
  const ExtensionName, Operation, ModelFile, PoseData, PayloadText: string;
  Frame: Integer): string;

implementation

uses
  System.IOUtils,
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  AviUtl2PluginCore,
  Aul2MIRAIExtensionProvider,
  Aul2MIRAIFrameCapture,
  Aul2MIRAIProtocol;

function ProviderSucceeded(const Text: string): Boolean;
var
  Json: TJSONValue;
begin
  Json := TJSONObject.ParseJSONValue(Text);
  try
    Result := (Json is TJSONObject) and
      (TJSONObject(Json).GetValue('status') is TJSONString) and
      SameText(TJSONString(TJSONObject(Json).GetValue('status')).Value, 'ok');
  finally
    Json.Free;
  end;
end;

function ProviderError(const Command, ProviderText: string): string;
var
  Code, MessageText: string;
  Json: TJSONValue;
begin
  Code := 'extension_error';
  MessageText := 'The MMD provider rejected the request.';
  Json := TJSONObject.ParseJSONValue(ProviderText);
  try
    if Json is TJSONObject then
    begin
      if TJSONObject(Json).GetValue('code') is TJSONString then
        Code := TJSONString(TJSONObject(Json).GetValue('code')).Value;
      if TJSONObject(Json).GetValue('message') is TJSONString then
        MessageText := TJSONString(
          TJSONObject(Json).GetValue('message')).Value;
    end;
  finally
    Json.Free;
  end;
  Result := BuildProtocolError(Command, Code, MessageText);
end;

function BuildBeginRequest(const ModelFile, PoseData,
  PayloadText: string): string;
var
  Payload: TJSONValue;
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('operation', 'begin_diagnostic_view');
    Root.AddPair('model_file', ModelFile);
    if PoseData <> '' then
      Root.AddPair('current_pose', PoseData);
    Payload := TJSONObject.ParseJSONValue(PayloadText);
    if not (Payload is TJSONObject) then
    begin
      Payload.Free;
      raise EArgumentException.Create('payload must be an object.');
    end;
    Root.AddPair('payload', Payload);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function BuildEndRequest(const ModelFile, Token: string): string;
var
  Payload, Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('operation', 'end_diagnostic_view');
    Root.AddPair('model_file', ModelFile);
    Payload := TJSONObject.Create;
    Payload.AddPair('token', Token);
    Root.AddPair('payload', Payload);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function ParseBeginResponse(const Text: string;
  out Token, PassName: string): Boolean;
var
  Json: TJSONValue;
  Root: TJSONObject;
begin
  Result := False;
  Token := '';
  PassName := '';
  Json := TJSONObject.ParseJSONValue(Text);
  try
    if not (Json is TJSONObject) then
      Exit;
    Root := TJSONObject(Json);
    if not (Root.GetValue('diagnostic_token') is TJSONString) or
       not (Root.GetValue('pass') is TJSONString) then
      Exit;
    Token := TJSONString(Root.GetValue('diagnostic_token')).Value;
    PassName := TJSONString(Root.GetValue('pass')).Value;
    Result := (Token <> '') and (PassName <> '');
  finally
    Json.Free;
  end;
end;

procedure AddImage(Root: TJSONObject; const Image: TAul2MIRAIFrameImage);
var
  ImageJson: TJSONObject;
begin
  ImageJson := TJSONObject.Create;
  Root.AddPair('image', ImageJson);
  ImageJson.AddPair('file_path', Image.FilePath);
  ImageJson.AddPair('format', Image.Format);
  ImageJson.AddPair('captured_at_utc', Image.CapturedAtUtc);
  ImageJson.AddPair('frame', TJSONNumber.Create(Image.Frame));
  ImageJson.AddPair('width', TJSONNumber.Create(Image.Width));
  ImageJson.AddPair('height', TJSONNumber.Create(Image.Height));
  ImageJson.AddPair('file_size', TJSONNumber.Create(Image.FileSize));
  ImageJson.AddPair('elapsed_ms', TJSONNumber.Create(Int64(Image.ElapsedMs)));
end;

function BuildResponse(const Command: string;
  const Identity: TAul2MIRAISnapshotIdentity; TargetIndex, EffectIndex: Integer;
  const ExtensionName, Operation, PassName, ProviderText: string;
  const Image: TAul2MIRAIFrameImage): string;
var
  ProviderResult: TJSONValue;
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('protocol', AUL2MIRAI_PROTOCOL_NAME);
    Root.AddPair('protocol_version', TJSONNumber.Create(AUL2MIRAI_PROTOCOL_VERSION));
    Root.AddPair('snapshot_id', Identity.SnapshotId);
    Root.AddPair('state_token', Identity.StateToken);
    Root.AddPair('captured_at_utc', Identity.CapturedAtUtc);
    Root.AddPair('status', 'ok');
    Root.AddPair('command', Command);
    Root.AddPair('target_index', TJSONNumber.Create(TargetIndex));
    Root.AddPair('effect_index', TJSONNumber.Create(EffectIndex));
    Root.AddPair('extension', ExtensionName);
    Root.AddPair('operation', Operation);
    Root.AddPair('pass', PassName);
    Root.AddPair('temporary', TJSONBool.Create(True));
    Root.AddPair('changes_project_state', TJSONBool.Create(False));
    Root.AddPair('diagnostic_view_released', TJSONBool.Create(True));
    AddImage(Root, Image);
    ProviderResult := TJSONObject.ParseJSONValue(ProviderText);
    if ProviderResult = nil then
      raise EArgumentException.Create('Provider response is invalid JSON.');
    Root.AddPair('result', ProviderResult);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function CaptureMmdDiagnosticView(const Command: string;
  const Identity: TAul2MIRAISnapshotIdentity; TargetIndex, EffectIndex: Integer;
  const ExtensionName, Operation, ModelFile, PoseData, PayloadText: string;
  Frame: Integer): string;
var
  BeginResponse, CaptureError, DiagnosticToken, EndResponse: string;
  ErrorCode, ErrorMessage, PassName: string;
  Captured, Released: Boolean;
  Image: TAul2MIRAIFrameImage;
begin
  try
    if not InvokeMmdExtensionProvider(BuildBeginRequest(ModelFile, PoseData,
      PayloadText), BeginResponse, ErrorCode, ErrorMessage, True) then
      Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  except
    on E: Exception do
      Exit(BuildProtocolError(Command, 'invalid_payload', E.Message));
  end;
  if not ProviderSucceeded(BeginResponse) then
    Exit(ProviderError(Command, BeginResponse));
  if not ParseBeginResponse(BeginResponse, DiagnosticToken, PassName) then
    Exit(BuildProtocolError(Command, 'invalid_extension_response',
      'The MMD provider did not return a diagnostic token.'));

  Released := False;
  CaptureError := '';
  try
    Captured := CaptureSceneFrame(EditHandle, Frame, Image, CaptureError);
  finally
    if InvokeMmdExtensionProvider(BuildEndRequest(ModelFile, DiagnosticToken),
      EndResponse, ErrorCode, ErrorMessage, True) then
      Released := ProviderSucceeded(EndResponse);
  end;
  if not Released then
  begin
    if (Image.FilePath <> '') and TFile.Exists(Image.FilePath) then
      TFile.Delete(Image.FilePath);
    Exit(BuildProtocolError(Command, 'diagnostic_release_failed',
      'The temporary MMD diagnostic view could not be released.'));
  end;
  if not Captured then
    Exit(BuildProtocolError(Command, 'render_failed', CaptureError));
  Result := BuildResponse(Command, Identity, TargetIndex, EffectIndex,
    ExtensionName, Operation, PassName, BeginResponse, Image);
end;

end.
