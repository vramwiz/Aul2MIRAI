unit Aul2MIRAICodexClient;

// RIGMMakerの専用app-server方式を参考に、JSONL通信と構造化命令ループをワーカーで処理する。
interface

uses
  Winapi.Windows,
  System.Classes,
  System.JSON,
  System.SyncObjs;

type
  TMIRAICodexJob = class(TThread)
  private
    FPrompt, FDirectory, FLogPath, FStage, FAnswer, FError: string;
    FThreadId, FTurnId, FCompletedTurn, FCompletedStatus, FDiagnostic: string;
    FRequest, FResponse: string;
    FRequestDeadline: UInt64;
    FProcess, FJob, FInput, FOutput, FStderr: THandle;
    FOutputBytes, FErrorBytes: RawByteString;
    FNextId: Integer;
    FStarted, FSuccess, FAllowEdits: Boolean;
    FLock: TCriticalSection;
    FResponseReady: TEvent;
    FLog: TStreamWriter;
    procedure SetStage(const Value: string);
    function GetStage: string;
    procedure Log(const Kind, Value: string);
    procedure OpenProcess;
    procedure CloseProcess;
    procedure Send(Value: TJSONObject);
    procedure ReadBytes(Pipe: THandle; var Bytes: RawByteString);
    function ReadMessage(Deadline: UInt64): TJSONObject;
    procedure Observe(Value: TJSONObject);
    function Call(const Method: string; Params: TJSONObject): TJSONObject;
    function RunTurn(const Input: string; Deadline: UInt64): string;
    function ExecuteCommand(const Request: string): string;
    procedure Conversation;
  protected
    procedure Execute; override;
  public
    // 文字列と編集許可だけを受け取り、SDK・ウィンドウをワーカーへ持ち込まない。
    constructor Create(const Prompt: string; AllowEdits: Boolean);
    destructor Destroy; override;
    // 全フィールドの準備完了後に通信スレッドを開始する。
    procedure BeginRun;
    // 通信と次の編集を停止する。完了済みの編集は取り消さない。
    procedure RequestStop;
    // UIタイマーから取得する。1要求は一度だけ取り出せる。
    function TakeRequest(out Request: string): Boolean;
    // UIスレッドで実行したコマンドの応答をワーカーへ返す。
    procedure CompleteRequest(const Response: string);
    property Stage: string read GetStage;
    property AllowEdits: Boolean read FAllowEdits;
    // 以下の結果はスレッド終了確認後に参照する。
    property Success: Boolean read FSuccess;
    property Answer: string read FAnswer;
    property ErrorText: string read FError;
    property LogPath: string read FLogPath;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  Aul2MIRAIKnowledge;

function TextOf(Value: TJSONObject; const Key: string): string;
begin
  Result := '';
  if (Value <> nil) and (Value.GetValue(Key) <> nil) and not (Value.GetValue(Key) is TJSONNull) then
    Result := Value.GetValue(Key).Value;
end;

function ObjectOf(Value: TJSONObject; const Key: string): TJSONObject;
begin
  Result := nil;
  if (Value <> nil) and (Value.GetValue(Key) is TJSONObject) then Result := TJSONObject(Value.GetValue(Key));
end;

procedure CloseOwned(var Handle: THandle);
begin
  if (Handle <> 0) and (Handle <> INVALID_HANDLE_VALUE) then CloseHandle(Handle);
  Handle := 0;
end;

function FindCodex: string;
var
  Buffer   : array[0..32767] of Char; // SearchPathの受取領域
  Count    : DWORD;                  // 返されたパス長
  Part     : PChar;                  // SearchPathのファイル名部分
  Root     : string;                 // デスクトップ同梱CLIの配置先
  Candidate: string;                 // 探索中の実行ファイル
  Latest   : TDateTime;              // 最も新しいCLIの更新日時
begin
  Result := GetEnvironmentVariable('CODEX_PIPE_EXE');
  if Result <> '' then
  begin
    Result := TPath.GetFullPath(Result);
    if not FileExists(Result) then raise Exception.Create('CODEX_PIPE_EXEのcodex.exeが見つかりません。');
    Exit;
  end;
  // デスクトップ本体もcodex.exeという名前なので、既知のCLI配置をPATHより先に選ぶ。
  Root := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'OpenAI\Codex\bin');
  Latest := 0;
  if DirectoryExists(Root) then
    for var Folder in TDirectory.GetDirectories(Root) do
    begin
      Candidate := TPath.Combine(Folder, 'codex.exe');
      if FileExists(Candidate) and (TFile.GetLastWriteTimeUtc(Candidate) > Latest) then
      begin
        Result := Candidate;
        Latest := TFile.GetLastWriteTimeUtc(Candidate);
      end;
    end;
  if Result <> '' then Exit;
  Part := nil;
  Count := SearchPath(nil, 'codex.exe', nil, Length(Buffer), Buffer, Part);
  if (Count > 0) and (Count < DWORD(Length(Buffer))) then Exit(string(Buffer));
  raise Exception.Create('Codex CLIが見つかりません。Codexを導入しログインしてください。');
end;

constructor TMIRAICodexJob.Create(const Prompt: string; AllowEdits: Boolean);
var
  Id: TGUID; // 実行ごとに分離するログディレクトリの識別子
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FResponseReady := TEvent.Create(nil, True, False, '');
  FPrompt := Prompt;
  FAllowEdits := AllowEdits;
  CreateGUID(Id);
  FDirectory := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'),
    'Aul2MIRAI\Codex\' + GUIDToString(Id));
  FLogPath := TPath.Combine(FDirectory, 'protocol.log');
  FStage := 'Codexへの接続を準備しています';
end;

destructor TMIRAICodexJob.Destroy;
begin
  RequestStop;
  if not FStarted then BeginRun;
  WaitFor;
  FResponseReady.Free;
  FLock.Free;
  inherited;
end;

procedure TMIRAICodexJob.BeginRun;
begin
  FStarted := True;
  Start;
end;

procedure TMIRAICodexJob.RequestStop;
begin
  Terminate;
  // 同期WriteFileが相手の読取り待ちで停止していても終了待ちを解除できる。
  if FStarted then CancelSynchronousIo(Handle);
  if FResponseReady <> nil then FResponseReady.SetEvent;
end;

procedure TMIRAICodexJob.SetStage(const Value: string);
begin
  FLock.Acquire;
  try FStage := Value; finally FLock.Release; end;
end;

function TMIRAICodexJob.GetStage: string;
begin
  FLock.Acquire;
  try Result := FStage; finally FLock.Release; end;
end;

procedure TMIRAICodexJob.Log(const Kind, Value: string);
begin
  if FLog = nil then Exit;
  FLog.WriteLine(FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' ' + Kind + ' ' + Value);
  FLog.Flush;
end;

procedure TMIRAICodexJob.OpenProcess;
var
  Security : TSecurityAttributes;               // 子プロセスへ渡すパイプの継承属性
  Startup  : TStartupInfo;                      // 非表示の標準入出力割当て
  Info     : TProcessInformation;               // 所有する子プロセス
  Limits   : TJobObjectExtendedLimitInformation; // 終了時に子孫も停止するJob設定
  ChildInput, ChildOutput, ChildError: THandle;
  Executable, Command: string;
begin
  Executable := FindCodex;
  Command := '"' + Executable + '" app-server --listen stdio://';
  UniqueString(Command);
  Log('START', Command);
  ChildInput := 0;
  ChildOutput := 0;
  ChildError := 0;
  ZeroMemory(@Security, SizeOf(Security));
  Security.nLength := SizeOf(Security);
  Security.bInheritHandle := True;
  try
    if not CreatePipe(ChildInput, FInput, @Security, 65536) then RaiseLastOSError;
    if not SetHandleInformation(FInput, HANDLE_FLAG_INHERIT, 0) then RaiseLastOSError;
    if not CreatePipe(FOutput, ChildOutput, @Security, 65536) then RaiseLastOSError;
    if not SetHandleInformation(FOutput, HANDLE_FLAG_INHERIT, 0) then RaiseLastOSError;
    if not CreatePipe(FStderr, ChildError, @Security, 65536) then RaiseLastOSError;
    if not SetHandleInformation(FStderr, HANDLE_FLAG_INHERIT, 0) then RaiseLastOSError;
    FJob := CreateJobObject(nil, nil);
    if FJob = 0 then RaiseLastOSError;
    ZeroMemory(@Limits, SizeOf(Limits));
    Limits.BasicLimitInformation.LimitFlags := JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if not SetInformationJobObject(FJob, JobObjectExtendedLimitInformation, @Limits, SizeOf(Limits)) then
      RaiseLastOSError;
    ZeroMemory(@Startup, SizeOf(Startup));
    Startup.cb := SizeOf(Startup);
    Startup.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    Startup.wShowWindow := SW_HIDE;
    Startup.hStdInput := ChildInput;
    Startup.hStdOutput := ChildOutput;
    Startup.hStdError := ChildError;
    ZeroMemory(@Info, SizeOf(Info));
    if not CreateProcess(PChar(Executable), PChar(Command), nil, nil, True,
      CREATE_NO_WINDOW or CREATE_SUSPENDED, nil, PChar(FDirectory), Startup, Info) then RaiseLastOSError;
    FProcess := Info.hProcess;
    try
      if not AssignProcessToJobObject(FJob, FProcess) then
      begin
        var Error := GetLastError;
        TerminateProcess(FProcess, 1);
        RaiseLastOSError(Error);
      end;
      if ResumeThread(Info.hThread) = DWORD(-1) then RaiseLastOSError;
    finally
      CloseHandle(Info.hThread);
    end;
  finally
    CloseOwned(ChildInput);
    CloseOwned(ChildOutput);
    CloseOwned(ChildError);
  end;
end;

procedure TMIRAICodexJob.CloseProcess;
begin
  CloseOwned(FInput);
  if FProcess <> 0 then WaitForSingleObject(FProcess, 200);
  CloseOwned(FJob);
  CloseOwned(FProcess);
  CloseOwned(FOutput);
  CloseOwned(FStderr);
end;

procedure TMIRAICodexJob.Send(Value: TJSONObject);
var
  Bytes          : TBytes; // LF終端のUTF-8フレーム
  Written, Offset: DWORD;  // 分割書込みの進行位置
begin
  try
    if Terminated then raise EAbort.Create('停止しました。完了済みの編集は残っています。');
    Log('SEND', Value.ToJSON);
    Bytes := TEncoding.UTF8.GetBytes(Value.ToJSON + #10);
    Offset := 0;
    while Offset < DWORD(Length(Bytes)) do
    begin
      if Terminated then raise EAbort.Create('停止しました。完了済みの編集は残っています。');
      if not WriteFile(FInput, Bytes[Offset], Length(Bytes) - Offset, Written, nil) then RaiseLastOSError;
      if Written = 0 then raise Exception.Create('Codexへの送信が途中で終了しました。');
      Inc(Offset, Written);
    end;
  finally
    Value.Free;
  end;
end;

procedure TMIRAICodexJob.ReadBytes(Pipe: THandle; var Bytes: RawByteString);
var
  Available, Count: DWORD;                  // パイプから読めるバイト数と読取実績
  Buffer          : array[0..65535] of Byte; // 一度の読取上限
  Part            : RawByteString;          // UTF-8の未復号部分
begin
  if not PeekNamedPipe(Pipe, nil, 0, nil, @Available, nil) or (Available = 0) then Exit;
  if Available > SizeOf(Buffer) then Available := SizeOf(Buffer);
  if not ReadFile(Pipe, Buffer[0], Available, Count, nil) then RaiseLastOSError;
  SetString(Part, PAnsiChar(@Buffer[0]), Count);
  Bytes := Bytes + Part;
  if Length(Bytes) > 4 * 1024 * 1024 then raise Exception.Create('Codexの応答が4 MiBを超えました。');
end;

function TMIRAICodexJob.ReadMessage(Deadline: UInt64): TJSONObject;
var
  Position  : Integer;    // 完成したJSONL行の末尾
  Line      : RawByteString; // 分割UTF-8を保持した1行
  Parsed    : TJSONValue; // 解析したフレーム
  ExitStatus: DWORD;      // 子プロセスの終了コード
begin
  repeat
    if Terminated then raise EAbort.Create('停止しました。完了済みの編集は残っています。');
    ReadBytes(FStderr, FErrorBytes);
    Position := Pos(AnsiChar(#10), FErrorBytes);
    while Position > 0 do
    begin
      Line := Copy(FErrorBytes, 1, Position - 1);
      Delete(FErrorBytes, 1, Position);
      if Trim(UTF8ToString(Line)) <> '' then FDiagnostic := Trim(UTF8ToString(Line));
      Log('STDERR', UTF8ToString(Line));
      Position := Pos(AnsiChar(#10), FErrorBytes);
    end;
    ReadBytes(FOutput, FOutputBytes);
    Position := Pos(AnsiChar(#10), FOutputBytes);
    if Position > 0 then
    begin
      Line := Copy(FOutputBytes, 1, Position - 1);
      Delete(FOutputBytes, 1, Position);
      if Trim(UTF8ToString(Line)) = '' then Continue;
      Parsed := TJSONObject.ParseJSONValue(UTF8ToString(Line));
      if not (Parsed is TJSONObject) then
      begin
        Parsed.Free;
        raise Exception.Create('CodexのJSON応答が不正です。');
      end;
      Log('RECV', TJSONObject(Parsed).ToJSON);
      Exit(TJSONObject(Parsed));
    end;
    if WaitForSingleObject(FProcess, 0) = WAIT_OBJECT_0 then
    begin
      GetExitCodeProcess(FProcess, ExitStatus);
      raise Exception.CreateFmt('Codexが終了しました（%d）。%s', [ExitStatus, FDiagnostic]);
    end;
    if GetTickCount64 >= Deadline then
      raise Exception.Create('Codexがタイムアウトしました。完了済みの編集は残っています。');
    Sleep(10);
  until False;
end;

procedure TMIRAICodexJob.Observe(Value: TJSONObject);
var
  Method          : string;     // JSON-RPC通知またはサーバー要求名
  Params, Item, Turn: TJSONObject; // フレーム所有の参照
begin
  Method := TextOf(Value, 'method');
  Params := ObjectOf(Value, 'params');
  if (Method <> '') and (Value.GetValue('id') <> nil) then
  begin
    Send(TJSONObject.Create.AddPair('id', Value.GetValue('id').Clone as TJSONValue)
      .AddPair('error', TJSONObject.Create.AddPair('code', TJSONNumber.Create(-32601))
      .AddPair('message', 'Use the structured AI MIRAI command loop. Client tools are not supported.')));
    Exit;
  end;
  if (Params = nil) or (TextOf(Params, 'threadId') <> FThreadId) then Exit;
  if (FTurnId <> '') and (TextOf(Params, 'turnId') <> '') and
     (TextOf(Params, 'turnId') <> FTurnId) then Exit;
  if Method = 'turn/completed' then
  begin
    Turn := ObjectOf(Params, 'turn');
    FCompletedTurn := TextOf(Turn, 'id');
    FCompletedStatus := TextOf(Turn, 'status');
    if ObjectOf(Turn, 'error') <> nil then FDiagnostic := ObjectOf(Turn, 'error').ToJSON;
  end
  else if Method = 'item/completed' then
  begin
    Item := ObjectOf(Params, 'item');
    if (TextOf(Item, 'type') = 'agentMessage') and (TextOf(Item, 'phase') <> 'commentary') then
      FAnswer := TextOf(Item, 'text');
  end;
end;

function TMIRAICodexJob.Call(const Method: string; Params: TJSONObject): TJSONObject;
var
  Id      : Integer;     // このクライアントの要求番号
  Value   : TJSONObject; // 受信したフレーム
  Deadline: UInt64;      // RPC応答の待機期限
begin
  Inc(FNextId);
  Id := FNextId;
  Send(TJSONObject.Create.AddPair('id', TJSONNumber.Create(Id)).AddPair('method', Method).AddPair('params', Params));
  Deadline := GetTickCount64 + 30000;
  repeat
    Value := ReadMessage(Deadline);
    if (TextOf(Value, 'id') = Id.ToString) and (TextOf(Value, 'method') = '') then
    begin
      if Value.GetValue('error') <> nil then
      begin
        var Error := Value.GetValue('error').ToJSON;
        Value.Free;
        raise Exception.Create(Method + ': ' + Error);
      end;
      Exit(Value);
    end;
    try Observe(Value); finally Value.Free; end;
  until False;
end;

function ActionSchema: TJSONObject;
begin
  Result := TJSONObject.Create.AddPair('type', 'object').AddPair('additionalProperties', TJSONBool.Create(False))
    .AddPair('properties', TJSONObject.Create
      .AddPair('action', TJSONObject.Create.AddPair('type', 'string')
        .AddPair('enum', TJSONArray.Create.Add('command').Add('knowledge').Add('finish')))
      .AddPair('content', TJSONObject.Create.AddPair('type', 'string')))
    .AddPair('required', TJSONArray.Create('action', 'content'));
end;

function TMIRAICodexJob.RunTurn(const Input: string; Deadline: UInt64): string;
var
  Reply, Params, Value: TJSONObject; // 所有するRPCメッセージ
begin
  FTurnId := '';
  FCompletedTurn := '';
  FCompletedStatus := '';
  FAnswer := '';
  Params := TJSONObject.Create.AddPair('threadId', FThreadId)
    .AddPair('input', TJSONArray.Create(TJSONObject.Create.AddPair('type', 'text').AddPair('text', Input)))
    .AddPair('outputSchema', ActionSchema);
  Reply := Call('turn/start', Params);
  try FTurnId := TextOf(ObjectOf(ObjectOf(Reply, 'result'), 'turn'), 'id'); finally Reply.Free; end;
  if FTurnId = '' then raise Exception.Create('Codexの処理IDを取得できません。');
  repeat
    if FCompletedTurn = FTurnId then
    begin
      if FCompletedStatus <> 'completed' then
        raise Exception.Create('Codexの処理が完了しませんでした: ' + FCompletedStatus + ' ' + FDiagnostic);
      if FAnswer.Trim = '' then raise Exception.Create('Codexの応答が空です。');
      Exit(FAnswer);
    end;
    Value := ReadMessage(Deadline);
    try Observe(Value); finally Value.Free; end;
  until False;
end;

function TMIRAICodexJob.ExecuteCommand(const Request: string): string;
var
  Deadline: UInt64; // UIが利用できなくなった場合の待機上限
begin
  FLock.Acquire;
  try
    FResponseReady.ResetEvent;
    FResponse := '';
    FRequestDeadline := GetTickCount64 + 120000;
    FRequest := Request;
  finally
    FLock.Release;
  end;
  SetStage('AviUtl2の操作結果を確認しています');
  Deadline := FRequestDeadline;
  while FResponseReady.WaitFor(25) <> wrSignaled do
  begin
    if Terminated then raise EAbort.Create('停止しました。完了済みの編集は残っています。');
    if GetTickCount64 >= Deadline then
      raise Exception.Create('AviUtl2の応答待ちがタイムアウトしました。編集結果を確認してください。');
  end;
  if Terminated then raise EAbort.Create('停止しました。完了済みの編集は残っています。');
  FLock.Acquire;
  try Result := FResponse; finally FLock.Release; end;
end;

function TMIRAICodexJob.TakeRequest(out Request: string): Boolean;
begin
  FLock.Acquire;
  try
    Result := not Terminated and (FRequest <> '') and (GetTickCount64 < FRequestDeadline);
    Request := '';
    if Result then
    begin
      Request := FRequest;
      FRequest := '';
    end;
  finally
    FLock.Release;
  end;
end;

procedure TMIRAICodexJob.CompleteRequest(const Response: string);
begin
  FLock.Acquire;
  try
    FResponse := Response;
    FResponseReady.SetEvent;
  finally
    FLock.Release;
  end;
end;

procedure TMIRAICodexJob.Conversation;
var
  Reply, Params: TJSONObject; // 所有する初期化メッセージ
  Json        : TJSONValue;  // 構造化応答の検証対象
  Action, Content, Input, Model: string;
  Deadline    : UInt64;      // 命令全体の生成・待機期限
begin
  SetStage('Codexへ接続しています');
  Reply := Call('initialize', TJSONObject.Create.AddPair('clientInfo', TJSONObject.Create
    .AddPair('name', 'aul2mirai').AddPair('title', 'AI MIRAI').AddPair('version', '0.2.0')));
  Reply.Free;
  Send(TJSONObject.Create.AddPair('method', 'initialized'));
  Params := TJSONObject.Create.AddPair('cwd', FDirectory).AddPair('approvalPolicy', 'never')
    .AddPair('sandbox', 'read-only').AddPair('ephemeral', TJSONBool.Create(True))
    .AddPair('developerInstructions', MIRAICodexInstructions)
    .AddPair('config', TJSONObject.Create.AddPair('web_search', 'disabled'));
  Model := GetEnvironmentVariable('CODEX_PIPE_MODEL');
  if Model <> '' then Params.AddPair('model', Model);
  Reply := Call('thread/start', Params);
  try FThreadId := TextOf(ObjectOf(ObjectOf(Reply, 'result'), 'thread'), 'id'); finally Reply.Free; end;
  if FThreadId = '' then raise Exception.Create('Codexの会話IDを取得できません。');
  if FAllowEdits then Input := '操作権限: この命令に必要な編集を許可。'
  else Input := '操作権限: 閲覧のみ。変更を行わないこと。';
  Input := Input + sLineBreak + '利用者の命令:' + sLineBreak + FPrompt;
  Deadline := GetTickCount64 + 600000;
  for var Step := 1 to 64 do
  begin
    if Terminated then raise EAbort.Create('停止しました。完了済みの編集は残っています。');
    if GetTickCount64 >= Deadline then raise Exception.Create('命令の実行時間が10分を超えました。');
    SetStage(Format('Codexが命令を処理しています（%d）', [Step]));
    Json := TJSONObject.ParseJSONValue(RunTurn(Input, Deadline));
    try
      if not (Json is TJSONObject) then raise Exception.Create('構造化応答がJSONオブジェクトではありません。');
      if not (TJSONObject(Json).GetValue('content') is TJSONString) then
        raise Exception.Create('構造化応答にcontent文字列がありません。');
      Action := TextOf(TJSONObject(Json), 'action');
      Content := TextOf(TJSONObject(Json), 'content');
    finally
      Json.Free;
    end;
    if Action = 'finish' then
    begin
      if Content.Trim = '' then raise Exception.Create('最終結果が空です。');
      FAnswer := Content;
      FSuccess := True;
      SetStage('完了');
      Exit;
    end;
    if Action = 'knowledge' then
    begin
      // 学習知識の不足もモデルへ返す。ファイルやシェルによる代用はさせない。
      try Input := '内蔵知識（' + Content + '）:' + sLineBreak + QueryMIRAIKnowledge(Content);
      except on E: Exception do Input := '内蔵知識の取得エラー: ' + E.Message; end;
    end
    else if Action = 'command' then Input := 'プラグインの実行応答:' + sLineBreak + ExecuteCommand(Content)
    else raise Exception.Create('未知の構造化応答action: ' + Action);
  end;
  raise Exception.Create('命令の処理が64ステップを超えました。完了済みの編集は残っています。');
end;

procedure TMIRAICodexJob.Execute;
begin
  if Terminated then Exit;
  try
    try
      ForceDirectories(FDirectory);
      FLog := TStreamWriter.Create(FLogPath, False, TEncoding.UTF8);
      OpenProcess;
      Conversation;
    except
      on E: Exception do
      begin
        if Terminated then FError := '停止しました。完了済みの編集は残っています。'
        else FError := E.Message;
        SetStage(FError);
        try Log('ERROR', FError); except end;
      end;
    end;
  finally
    FLock.Acquire;
    try FRequest := ''; finally FLock.Release; end;
    CloseProcess;
    FreeAndNil(FLog);
  end;
end;

end.
