unit Aul2MIRAICommand;

// 外部要求を検証し、読み取り処理、JSON応答、画面通知を接続する。

interface

function HandleAul2MIRAIRequest(const RequestText: string): string;

implementation

uses
  System.SysUtils,
  AviUtl2PluginCore,
  Aul2MIRAIEditStateReader,
  Aul2MIRAIEditStateTypes,
  Aul2MIRAIObjectFormat,
  Aul2MIRAIObjectQuery,
  Aul2MIRAIObjectReader,
  Aul2MIRAIObjectTypes,
  Aul2MIRAIProtocol,
  Aul2MIRAIView;

function HandleAul2MIRAIRequest(const RequestText: string): string;
var
  Command      : string;                  // 検証済みコマンド名
  ErrorCode    : string;                  // エラー識別子
  ErrorMessage : string;                  // エラー説明
  EditState    : TAul2MIRAIEditState;     // 現在の基本編集状態
  Snapshot     : TAul2MIRAISceneSnapshot; // 取得した現在シーン情報
begin
  try
    if not ParseProtocolRequest(RequestText, Command, ErrorCode, ErrorMessage) then
    begin
      QueueMIRAIViewUpdate('External request rejected', '', 'WARN',
        ErrorCode + ': ' + ErrorMessage);
      Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
    end;

    if SameText(Command, AUL2MIRAI_COMMAND_STATE) then
    begin
      if not ReadCurrentEditState(EditHandle, EditState, ErrorMessage) then
      begin
        QueueMIRAIViewUpdate('External state read failed', '', 'ERROR',
          Command + ': ' + ErrorMessage);
        Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
      end;
      QueueMIRAIViewUpdate(
        Format('External state read - scene %d, frame %d',
          [EditState.SceneId, EditState.CursorFrame]),
        '', 'OK',
        Format('%s -> scene %d, frame %d (%d ms)',
          [Command, EditState.SceneId, EditState.CursorFrame,
           EditState.ElapsedMs]));
      Exit(BuildEditStateResponse(EditState));
    end;

    if not SameText(Command, AUL2MIRAI_COMMAND_OBJECTS) and
       not SameText(Command, AUL2MIRAI_COMMAND_CURSOR_OBJECTS) and
       not SameText(Command, AUL2MIRAI_COMMAND_SELECTED_OBJECTS) then
    begin
      ErrorCode := 'unsupported_command';
      ErrorMessage := 'The requested command is not supported.';
      QueueMIRAIViewUpdate('External request rejected', '', 'WARN',
        Command + ': ' + ErrorMessage);
      Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
    end;

    if not ReadCurrentSceneObjects(EditHandle, Snapshot, ErrorMessage,
      SameText(Command, AUL2MIRAI_COMMAND_CURSOR_OBJECTS) or
      SameText(Command, AUL2MIRAI_COMMAND_SELECTED_OBJECTS)) then
    begin
      QueueMIRAIViewUpdate('External read failed', '', 'ERROR',
        Command + ': ' + ErrorMessage);
      Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
    end;

    if SameText(Command, AUL2MIRAI_COMMAND_CURSOR_OBJECTS) then
      KeepObjectsAtCursor(Snapshot)
    else if SameText(Command, AUL2MIRAI_COMMAND_SELECTED_OBJECTS) then
      KeepSelectedObjects(Snapshot);

    QueueMIRAIViewUpdate(
      Format('External read - %d objects, %d ms',
        [Length(Snapshot.Objects), Snapshot.ElapsedMs]),
      FormatSceneSnapshot(Snapshot),
      'OK',
      Format('%s -> %d objects (%d ms)',
        [Command, Length(Snapshot.Objects), Snapshot.ElapsedMs]));
    Result := BuildSceneObjectsResponse(Command, Snapshot);
  except
    on E: Exception do
    begin
      QueueMIRAIViewUpdate('External request failed', '', 'ERROR',
        E.ClassName + ': ' + E.Message);
      Result := BuildProtocolError('', 'internal_error', E.Message);
    end;
  end;
end;

end.
