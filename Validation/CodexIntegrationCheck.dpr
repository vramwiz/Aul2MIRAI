program CodexIntegrationCheck;

// 内蔵リソース、閲覧制限、実Codexと既存Pipeの往復、停止・子プロセス終了を確認する。
{$APPTYPE CONSOLE}
{$R '..\Aul2MIRAIKnowledge.res'}

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  System.IOUtils,
  Aul2MIRAICodexClient,
  Aul2MIRAICodexBridge,
  Aul2MIRAIKnowledge;

procedure Require(Condition: Boolean; const Message: string);
begin
  if not Condition then raise Exception.Create(Message);
end;

function PipeRequest(const Request: string): string;
var
  Pipe            : THandle; // 実機の既存外部インターフェース
  Bytes           : TBytes;  // BOMなしUTF-8要求
  Written, Count, Mode: DWORD;
  Buffer          : array[0..65535] of Byte;
  Stream          : TMemoryStream;
begin
  Pipe := CreateFile('\\.\pipe\Aul2MIRAI.v1', GENERIC_READ or GENERIC_WRITE,
    0, nil, OPEN_EXISTING, 0, 0);
  if Pipe = INVALID_HANDLE_VALUE then RaiseLastOSError;
  Stream := TMemoryStream.Create;
  try
    Mode := PIPE_READMODE_MESSAGE;
    if not SetNamedPipeHandleState(Pipe, Mode, nil, nil) then RaiseLastOSError;
    Bytes := TEncoding.UTF8.GetBytes(Request);
    if not WriteFile(Pipe, Bytes[0], Length(Bytes), Written, nil) then RaiseLastOSError;
    Require(Written = DWORD(Length(Bytes)), '要求の書込みが不完全です。');
    repeat
      var Success := ReadFile(Pipe, Buffer[0], SizeOf(Buffer), Count, nil);
      var Error := GetLastError;
      if Count > 0 then Stream.WriteBuffer(Buffer[0], Count);
      if Success then Break;
      if Error <> ERROR_MORE_DATA then RaiseLastOSError(Error);
    until False;
    SetLength(Bytes, Stream.Size);
    Stream.Position := 0;
    if Length(Bytes) > 0 then Stream.ReadBuffer(Bytes[0], Length(Bytes));
    Result := TEncoding.UTF8.GetString(Bytes);
  finally
    Stream.Free;
    CloseHandle(Pipe);
  end;
end;

procedure CheckResources;
const
  Topics: array[0..6] of string = ('guide', 'aliases', 'effects', 'lua', 'scenes', 'voicevox', 'mmd');
  Files: array[0..6] of string = ('AI_USAGE.md', 'ALIAS_CATALOG.md', 'EFFECT_LEARNING.md',
    'LUA_SCRIPTING.md', 'SCENE_LEARNING.md', 'VOICEVOX_PROJECT_LEARNING.md', 'MMD_POSE_LEARNING.md');
begin
  for var I := Low(Topics) to High(Topics) do
    Require(ReadMIRAIKnowledge(Topics[I]) = TFile.ReadAllText(Files[I], TEncoding.UTF8),
      '内蔵知識が資料と一致しません: ' + Topics[I]);
  Writeln('resources: seven topics match source documents');
  Require(QueryMIRAIKnowledge('aliases').Contains('標準オブジェクト: 図形'), '目次がありません。');
  Require(QueryMIRAIKnowledge('aliases:標準オブジェクト: 図形').Contains('effect.name=図形'),
    '図形の節を取得できません。');
  Require(not QueryMIRAIKnowledge('aliases:標準オブジェクト: 図形').Contains('## 標準出力エフェクト'),
    '次の節が混入しています。');
  Require(QueryMIRAIKnowledge('aliases:発光').Contains('具体的に'), '曖昧な節が区別されません。');
end;

procedure CheckReadOnly;
var
  Response: string;
begin
  Response := ExecuteMIRAICodexRequest(
    '{"protocol_version":1,"command":"set_edit_position","apply":true}', False);
  Require(Response.Contains('read_only'), '閲覧のみで変更が拒否されませんでした。');
  Response := ExecuteMIRAICodexRequest('{"protocol_version":1,"command":"unsupported_test_command"}', True);
  Require(Response.Contains('unsupported_command'), '未対応命令が拒否されませんでした。');
  Response := ExecuteMIRAICodexRequest('[]', True);
  Require(Response.Contains('invalid_json'), '不正JSONが拒否されませんでした。');
  Response := ExecuteMIRAICodexRequest('{"protocol_version":1,"command":"set_object_name"}', False);
  Require(Response.Contains('read_only'), '閲覧のみで名前変更が拒否されませんでした。');
  Response := ExecuteMIRAICodexRequest('{"protocol_version":1,"command":"delete_objects"}', False);
  Require(Response.Contains('read_only'), '閲覧のみで削除が拒否されませんでした。');
  Response := ExecuteMIRAICodexRequest(
    '{"protocol_version":1,"command":"apply_object_extension_change"}', False);
  Require(Response.Contains('read_only'), '閲覧のみでMMD変更が拒否されませんでした。');
  Writeln('bridge: read-only, unsupported command and malformed JSON rejected');
end;

procedure CheckLive;
var
  Job     : TMIRAICodexJob;
  Request, Response, Command: string;
  Json    : TJSONValue;
  Count   : Integer;
  Deadline: UInt64;
  EditLive, Created, Renamed, Deleted: Boolean;
  Prompt, Code: string;
  RequestRoot: TJSONObject;
begin
  EditLive := ParamStr(1) = '--edit-live';
  Created := False;
  Renamed := False;
  Deleted := False;
  if EditLive then
  begin
    Json := TJSONObject.ParseJSONValue(PipeRequest('{"protocol_version":1,"command":"get_scene_objects"}'));
    try
      Require((Json is TJSONObject) and
        (TJSONObject(Json).GetValue<TJSONArray>('snapshot.objects').Count = 0),
        '--edit-liveは空の検証用シーンだけで実行してください。');
    finally
      Json.Free;
    end;
    Prompt := '編集連携の実機確認です。空の現在シーンのレイヤー2、フレーム0へ、' +
      'effect=図形、length=30で標準初期値オブジェクトを1個だけ生成し、' +
      '選択後、表示名を「Codex編集検証」へ変更し、その1個だけを削除してください。' +
      '名前変更と削除には必ず関連guideの節をknowledgeで取得し、事前プレビューしてください。' +
      '最後にget_scene_objectsで空へ戻ったことを確認し、日本語で結果を答えてください。' +
      'この検証以外の編集は不要です。';
  end
  else
    Prompt :=
    '通信確認です。必ずget_edit_stateを実行し、次にknowledgeでaliases:標準オブジェクト: 図形と' +
    'aliases:標準出力エフェクト: 標準描画を取得してください。' +
    '最後に現在のシーン名と図形（円）の確認済み生成形式を読み取れたかを短く答えてください。' +
    '編集、カーソル変更、画像取得は不要です。';
  Job := TMIRAICodexJob.Create(Prompt, EditLive);
  try
    Count := 0;
    Job.BeginRun;
    Deadline := GetTickCount64 + 180000;
    while WaitForSingleObject(Job.Handle, 25) <> WAIT_OBJECT_0 do
    begin
      if GetTickCount64 >= Deadline then
      begin
        Job.RequestStop;
        raise Exception.Create('通信確認が180秒を超えました: ' + Job.LogPath);
      end;
      if not Job.TakeRequest(Request) then Continue;
      Json := TJSONObject.ParseJSONValue(Request);
      try
        Require(Json is TJSONObject, '要求がJSONオブジェクトではありません。');
        Command := TJSONObject(Json).GetValue('command').Value;
        RequestRoot := TJSONObject(Json);
        if not EditLive then
          Require((Command = 'get_edit_state') or (Command = 'get_scene_objects'),
            '読取試験で想定外の操作が要求されました: ' + Command)
        else if not Command.StartsWith('get_') then
        begin
          Code := Command;
          if Code.StartsWith('preview_') then Delete(Code, 1, Length('preview_'));
          if Code = 'create_object_from_alias' then
            Require((RequestRoot.GetValue<Integer>('layer') = 2) and
              (RequestRoot.GetValue<Integer>('frame') = 0) and
              (RequestRoot.GetValue<Integer>('length') = 30) and
              (RequestRoot.GetValue<string>('effect') = '図形') and
              (RequestRoot.GetValue('alias') = nil) and not Created,
              '検証の範囲外の新規生成です。')
          else if (Code = 'set_focus_object') or (Code = 'set_object_name') then
          begin
            Require(Created and not Deleted and (RequestRoot.GetValue<Integer>('target_index') = 0),
              '検証用オブジェクト以外への操作です。');
            if Code = 'set_object_name' then
              Require(RequestRoot.GetValue<string>('name') = 'Codex編集検証', '検証用の名前ではありません。');
          end
          else if Code = 'delete_objects' then
          begin
            Require(Created and Renamed and not Deleted, '検証用オブジェクトが変更されていません。');
            var Targets := RequestRoot.GetValue<TJSONArray>('target_indices');
            Require((Targets.Count = 1) and (Targets.Items[0].Value = '0'), '検証の範囲外の削除です。');
          end
          else raise Exception.Create('検証で想定外の操作です: ' + Command);
        end;
      finally
        Json.Free;
      end;
      Response := PipeRequest(Request);
      Require(Response.Contains('"status":"ok"'), '実機Pipeが失敗しました: ' + Response);
      if Command = 'create_object_from_alias' then Created := True;
      if Command = 'set_object_name' then Renamed := True;
      if Command = 'delete_objects' then Deleted := True;
      Writeln('command: ', Command);
      Inc(Count);
      Job.CompleteRequest(Response);
    end;
    Require(Job.Success, 'Codexが失敗しました: ' + Job.ErrorText + ' / ' + Job.LogPath);
    Require(Count >= 1, '実機への要求が実行されませんでした。');
    if EditLive then
    begin
      Require(Created and Renamed and Deleted, '生成・名前変更・削除がすべて完了していません。');
      Json := TJSONObject.ParseJSONValue(PipeRequest('{"protocol_version":1,"command":"get_scene_objects"}'));
      try
        Require(TJSONObject(Json).GetValue<TJSONArray>('snapshot.objects').Count = 0,
          '検証後にオブジェクトが残っています。');
      finally
        Json.Free;
      end;
    end;
    Require(TFile.ReadAllText(Job.LogPath).Contains('\"action\":\"knowledge\"'),
      '内蔵知識が要求されませんでした: ' + Job.LogPath);
    Writeln('live: ', Count, ' command(s), knowledge retrieval and finish succeeded');
    Writeln('answer: ', Job.Answer);
    Writeln('log: ', Job.LogPath);
  finally
    Job.Free;
  end;
end;

procedure CheckCancel;
var
  Job  : TMIRAICodexJob;
  Start: UInt64;
begin
  Job := TMIRAICodexJob.Create('get_edit_stateで現在状態を取得してください。', False);
  try
    Job.BeginRun;
    Start := GetTickCount64;
    while (GetTickCount64 - Start < 1500) and
      (WaitForSingleObject(Job.Handle, 25) <> WAIT_OBJECT_0) do ;
    Job.RequestStop;
    Require(WaitForSingleObject(Job.Handle, 5000) = WAIT_OBJECT_0, '停止が5秒以内に完了しませんでした。');
    Require(not Job.Success, '停止したジョブが成功扱いになっています。');
    Writeln('cancel: worker stopped within five seconds');
  finally
    Job.Free;
  end;
end;

begin
  try
    CheckResources;
    CheckReadOnly;
    if ParamStr(1) <> '--static' then
    begin
      CheckLive;
      CheckCancel;
    end;
    Writeln('PASS');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
