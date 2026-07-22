unit Aul2MIRAIPipeServer;

// コピーしたPipeライブラリをAI MIRAIのJSON要求処理へ接続する。
interface

uses
  Winapi.Windows;

function StartMIRAIPipeServer(NotifyWindow: HWND;
  out ErrorMessage: string): Boolean;
procedure StopMIRAIPipeServer;
procedure ProcessMIRAIPipeMessage(WParam: WPARAM);

implementation

uses
  System.SysUtils,
  PipeServerTThread,
  Aul2MIRAICommand,
  Aul2MIRAIProtocol,
  Aul2MIRAIView;

const
  PIPE_BUFFER_SIZE = 65536;

type
  TMIRAIPipeServer = class
  private
    FThread: TPipeServerTThread;
    procedure Receive(Sender: TObject; const ReceivedStr: string;
      var SendStr: string);
  public
    constructor Create(NotifyWindow: HWND);
    destructor Destroy; override;
    procedure ProcessMessage(WParam: WPARAM);
  end;

var
  Server: TMIRAIPipeServer;

constructor TMIRAIPipeServer.Create(NotifyWindow: HWND);
begin
  inherited Create;
  FThread := TPipeServerTThread.Create(AUL2MIRAI_PIPE_SHORT_NAME,
    PIPE_BUFFER_SIZE, True, 1000, 1, NotifyWindow);
  FThread.OnReceive := Receive;
end;

destructor TMIRAIPipeServer.Destroy;
var
  PipeHandle: THandle;
begin
  if FThread <> nil then
  begin
    FThread.Terminate;
    FThread.ReleaseWait;

    PipeHandle := CreateFile(PChar(AUL2MIRAI_PIPE_NAME),
      GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0);
    if PipeHandle <> INVALID_HANDLE_VALUE then
      CloseHandle(PipeHandle);

    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  inherited;
end;

procedure TMIRAIPipeServer.Receive(Sender: TObject;
  const ReceivedStr: string; var SendStr: string);
begin
  SendStr := HandleAul2MIRAIRequest(ReceivedStr);
end;

procedure TMIRAIPipeServer.ProcessMessage(WParam: WPARAM);
begin
  if (FThread <> nil) and (WParam = NativeUInt(FThread)) then
    FThread.ProcessMainThread;
end;

function StartMIRAIPipeServer(NotifyWindow: HWND;
  out ErrorMessage: string): Boolean;
begin
  Result := False;
  ErrorMessage := '';
  if Server <> nil then
    Exit(True);

  try
    Server := TMIRAIPipeServer.Create(NotifyWindow);
    QueueMIRAIViewUpdate('待機中', '', 'INFO',
      'AIからの操作を待っています。');
    Result := True;
  except
    on E: Exception do
    begin
      FreeAndNil(Server);
      ErrorMessage := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

procedure StopMIRAIPipeServer;
begin
  FreeAndNil(Server);
end;

procedure ProcessMIRAIPipeMessage(WParam: WPARAM);
begin
  if Server <> nil then
    Server.ProcessMessage(WParam);
end;

end.
