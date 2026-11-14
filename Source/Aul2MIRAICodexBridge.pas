unit Aul2MIRAICodexBridge;

// Codexが返したJSONを既存コマンドへ渡す。SDKアクセスは呼出側のUIスレッドだけで行う。
interface

// 閲覧制限と適用直前のプレビューを通して1要求を処理し、既存形式のJSON応答を返す。
function ExecuteMIRAICodexRequest(const RequestText: string; AllowEdits: Boolean): string;

implementation

uses
  System.JSON,
  System.SysUtils,
  Aul2MIRAICommand,
  Aul2MIRAIProtocol;

function ExecuteMIRAICodexRequest(const RequestText: string; AllowEdits: Boolean): string;
var
  Command     : string;     // 検証済みコマンド名
  ErrorCode   : string;     // プロトコルエラー識別子
  ErrorMessage: string;     // プロトコルエラー説明
  Json        : TJSONValue; // プレビュー用に書き換える要求
  Root        : TJSONObject; // JSON要求本体
  Preview     : string;     // 適用直前の検証応答
  IsRead      : Boolean;    // 状態を変更しない要求
begin
  if Length(RequestText) > 1024 * 1024 then
    Exit(BuildProtocolError('', 'request_too_large', 'Codex request exceeds 1 Mi characters.'));
  if not ParseProtocolRequest(RequestText, Command, ErrorCode, ErrorMessage) then
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  IsRead := (Command = 'get_edit_state') or (Command = 'get_scene_objects') or
    (Command = 'get_objects_at_cursor') or (Command = 'get_objects_in_selection') or
    (Command = 'get_selected_objects') or (Command = 'get_object_details') or
    (Command = 'get_current_frame_image') or (Command = 'query_object_extension') or
    Command.StartsWith('preview_');
  if IsRead then Exit(HandleAul2MIRAIRequest(RequestText));
  if not AllowEdits then
    Exit(BuildProtocolError(Command, 'read_only', '閲覧のみです。編集は許可されていません。'));
  if (Command <> 'set_object_parameter') and (Command <> 'set_object_parameters') and
     (Command <> 'move_objects') and (Command <> 'duplicate_objects') and
     (Command <> 'create_object_from_alias') and (Command <> 'create_objects_from_aliases') and
     (Command <> 'set_edit_position') and (Command <> 'set_focus_object') and
     (Command <> 'set_object_name') and (Command <> 'delete_objects') and
     (Command <> 'apply_object_extension_change') then
    Exit(BuildProtocolError(Command, 'unsupported_command', 'Unsupported Codex command.'));
  Json := TJSONObject.ParseJSONValue(RequestText);
  try
    Root := Json as TJSONObject;
    Root.RemovePair('command').Free;
    Root.RemovePair('apply').Free;
    if Command = 'apply_object_extension_change' then
      Root.AddPair('command', 'preview_object_extension_change')
    else
      Root.AddPair('command', 'preview_' + Command);
    Preview := HandleAul2MIRAIRequest(Root.ToJSON);
    if not IsSuccessfulResponse(Preview) then Exit(Preview);
  finally
    Json.Free;
  end;
  // 同一UI呼出内で実行し、既存のstate_token照合・編集後検証も維持する。
  Result := HandleAul2MIRAIRequest(RequestText);
end;

end.
