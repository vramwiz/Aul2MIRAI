unit Aul2MIRAIView;

// オブジェクト取得確認用の状態表示、一覧、操作ログをWin32子コントロールで構成する。

interface

uses
  Winapi.Windows,
  Winapi.Messages;

const
  WM_AUL2MIRAI_VIEW_UPDATE = WM_APP + 210;

procedure CreateMIRAIView(ParentWindow: HWND);
procedure DestroyMIRAIView;
procedure ResizeMIRAIView(Width, Height: Integer);
function HandleMIRAIViewCommand(WParam: WPARAM): Boolean;
procedure QueueMIRAIViewUpdate(const StatusText, ObjectText, LogLevel,
  LogMessage: string);
procedure ApplyMIRAIViewUpdates;

implementation

uses
  System.Classes,
  System.SyncObjs,
  System.SysUtils,
  AviUtl2PluginCore,
  Aul2MIRAILog,
  Aul2MIRAIObjectFormat,
  Aul2MIRAIObjectReader,
  Aul2MIRAIObjectTypes;

const
  CONTROL_ID_REFRESH = 1001;
  CONTROL_MARGIN     = 8;
  HEADER_HEIGHT      = 26;
  LOG_HEIGHT         = 112;

var
  ParentHandle     : HWND;
  StatusHandle     : HWND;
  RefreshHandle    : HWND;
  ObjectListHandle : HWND;
  LogHandle        : HWND;
  OperationLog     : TAul2MIRAIOperationLog;
  PendingLock      : TCriticalSection;
  PendingLogs      : TStringList;
  PendingStatus    : string;
  PendingObjects   : string;
  PendingHasStatus : Boolean;
  PendingHasObjects: Boolean;

procedure ApplyControlFont(Control: HWND; Font: HGDIOBJ);
begin
  if Control <> 0 then
    SendMessage(Control, WM_SETFONT, WPARAM(Font), LPARAM(1));
end;

procedure SetStatus(const Value: string);
begin
  if StatusHandle <> 0 then
    SetWindowText(StatusHandle, PChar(Value));
end;

procedure UpdateLogControl;
begin
  if (LogHandle <> 0) and (OperationLog <> nil) then
    SetWindowText(LogHandle, PChar(OperationLog.Text));
end;

procedure RefreshObjectList;
var
  ErrorMessage : string;                       // 取得失敗時の理由
  Snapshot     : TAul2MIRAISceneSnapshot;      // 取得した現在シーン情報
begin
  if OperationLog = nil then
    Exit;

  SetStatus('Reading current scene objects...');
  OperationLog.Add('READ', 'get_scene_objects started');
  UpdateLogControl;

  if ReadCurrentSceneObjects(EditHandle, Snapshot, ErrorMessage) then
  begin
    SetWindowText(ObjectListHandle, PChar(FormatSceneSnapshot(Snapshot)));
    SetStatus(Format('Ready - %d objects, %d ms',
      [Length(Snapshot.Objects), Snapshot.ElapsedMs]));
    OperationLog.Add('OK', Format('get_scene_objects -> %d objects (%d ms)',
      [Length(Snapshot.Objects), Snapshot.ElapsedMs]));
  end
  else
  begin
    SetStatus('Read failed');
    OperationLog.Add('ERROR', ErrorMessage);
  end;

  UpdateLogControl;
end;

procedure CreateMIRAIView(ParentWindow: HWND);
var
  ClientRect : TRect;  // 初回レイアウトに使う親領域
  GuiFont    : HGDIOBJ; // 標準UIフォント
begin
  DestroyMIRAIView;
  ParentHandle := ParentWindow;
  OperationLog := TAul2MIRAIOperationLog.Create;
  PendingLock := TCriticalSection.Create;
  PendingLogs := TStringList.Create;

  StatusHandle := CreateWindowEx(0, 'STATIC',
    'Ready - click Refresh to read the current scene.',
    WS_CHILD or WS_VISIBLE or SS_LEFT or SS_CENTERIMAGE,
    0, 0, 0, 0, ParentHandle, 0, HInstance, nil);

  RefreshHandle := CreateWindowEx(0, 'BUTTON', 'Refresh',
    WS_CHILD or WS_VISIBLE or WS_TABSTOP or BS_PUSHBUTTON,
    0, 0, 0, 0, ParentHandle, HMENU(CONTROL_ID_REFRESH), HInstance, nil);

  ObjectListHandle := CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '',
    WS_CHILD or WS_VISIBLE or WS_VSCROLL or ES_LEFT or ES_MULTILINE or
    ES_AUTOVSCROLL or ES_READONLY,
    0, 0, 0, 0, ParentHandle, 0, HInstance, nil);

  LogHandle := CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '',
    WS_CHILD or WS_VISIBLE or WS_VSCROLL or ES_LEFT or ES_MULTILINE or
    ES_AUTOVSCROLL or ES_READONLY,
    0, 0, 0, 0, ParentHandle, 0, HInstance, nil);

  GuiFont := GetStockObject(DEFAULT_GUI_FONT);
  ApplyControlFont(StatusHandle, GuiFont);
  ApplyControlFont(RefreshHandle, GuiFont);
  ApplyControlFont(ObjectListHandle, GetStockObject(SYSTEM_FIXED_FONT));
  ApplyControlFont(LogHandle, GetStockObject(SYSTEM_FIXED_FONT));

  OperationLog.Add('INFO', 'AI MIRAI view initialized');
  UpdateLogControl;
  GetClientRect(ParentHandle, ClientRect);
  ResizeMIRAIView(ClientRect.Right, ClientRect.Bottom);
end;

procedure DestroyMIRAIView;
begin
  if StatusHandle <> 0 then
    DestroyWindow(StatusHandle);
  if RefreshHandle <> 0 then
    DestroyWindow(RefreshHandle);
  if ObjectListHandle <> 0 then
    DestroyWindow(ObjectListHandle);
  if LogHandle <> 0 then
    DestroyWindow(LogHandle);

  StatusHandle := 0;
  RefreshHandle := 0;
  ObjectListHandle := 0;
  LogHandle := 0;
  ParentHandle := 0;
  FreeAndNil(OperationLog);
  FreeAndNil(PendingLogs);
  FreeAndNil(PendingLock);
end;

procedure ResizeMIRAIView(Width, Height: Integer);
var
  ContentHeight : Integer; // 一覧領域として利用できる高さ
  RefreshWidth  : Integer; // 更新ボタン幅
begin
  if ParentHandle = 0 then
    Exit;

  RefreshWidth := 84;
  ContentHeight := Height - HEADER_HEIGHT - LOG_HEIGHT - CONTROL_MARGIN * 4;
  if ContentHeight < 40 then
    ContentHeight := 40;

  MoveWindow(StatusHandle, CONTROL_MARGIN, CONTROL_MARGIN,
    Width - RefreshWidth - CONTROL_MARGIN * 3, HEADER_HEIGHT, True);
  MoveWindow(RefreshHandle, Width - RefreshWidth - CONTROL_MARGIN,
    CONTROL_MARGIN, RefreshWidth, HEADER_HEIGHT, True);
  MoveWindow(ObjectListHandle, CONTROL_MARGIN,
    HEADER_HEIGHT + CONTROL_MARGIN * 2,
    Width - CONTROL_MARGIN * 2, ContentHeight, True);
  MoveWindow(LogHandle, CONTROL_MARGIN,
    HEADER_HEIGHT + ContentHeight + CONTROL_MARGIN * 3,
    Width - CONTROL_MARGIN * 2, LOG_HEIGHT, True);
end;

function HandleMIRAIViewCommand(WParam: WPARAM): Boolean;
begin
  Result := (LOWORD(WParam) = CONTROL_ID_REFRESH) and
    (HIWORD(WParam) = BN_CLICKED);
  if Result then
    RefreshObjectList;
end;

procedure QueueMIRAIViewUpdate(const StatusText, ObjectText, LogLevel,
  LogMessage: string);
begin
  if (PendingLock = nil) or (ParentHandle = 0) then
    Exit;

  PendingLock.Acquire;
  try
    if StatusText <> '' then
    begin
      PendingStatus := StatusText;
      PendingHasStatus := True;
    end;
    if ObjectText <> '' then
    begin
      PendingObjects := ObjectText;
      PendingHasObjects := True;
    end;
    if (LogLevel <> '') or (LogMessage <> '') then
      PendingLogs.Add(LogLevel + #1 + LogMessage);
  finally
    PendingLock.Release;
  end;

  PostMessage(ParentHandle, WM_AUL2MIRAI_VIEW_UPDATE, 0, 0);
end;

procedure ApplyMIRAIViewUpdates;
var
  HasObjects : Boolean;     // オブジェクト一覧更新の有無
  HasStatus  : Boolean;     // 状態表示更新の有無
  Index      : Integer;     // 保留ログの列挙番号
  Level      : string;      // ログレベル
  Lines      : TStringList; // UIスレッドへコピーした保留ログ
  MessageText: string;      // ログ本文
  ObjectText : string;      // UIスレッドへコピーした一覧
  Separator  : Integer;     // ログレベルと本文の区切り位置
  StatusText : string;      // UIスレッドへコピーした状態
begin
  if (PendingLock = nil) or (PendingLogs = nil) then
    Exit;

  Lines := TStringList.Create;
  try
    PendingLock.Acquire;
    try
      HasStatus := PendingHasStatus;
      HasObjects := PendingHasObjects;
      StatusText := PendingStatus;
      ObjectText := PendingObjects;
      Lines.Assign(PendingLogs);
      PendingHasStatus := False;
      PendingHasObjects := False;
      PendingStatus := '';
      PendingObjects := '';
      PendingLogs.Clear;
    finally
      PendingLock.Release;
    end;

    if HasStatus then
      SetStatus(StatusText);
    if HasObjects and (ObjectListHandle <> 0) then
      SetWindowText(ObjectListHandle, PChar(ObjectText));

    if OperationLog <> nil then
      for Index := 0 to Lines.Count - 1 do
      begin
        Separator := Pos(#1, Lines[Index]);
        if Separator > 0 then
        begin
          Level := Copy(Lines[Index], 1, Separator - 1);
          MessageText := Copy(Lines[Index], Separator + 1, MaxInt);
        end
        else
        begin
          Level := 'INFO';
          MessageText := Lines[Index];
        end;
        OperationLog.Add(Level, MessageText);
      end;
    UpdateLogControl;
  finally
    Lines.Free;
  end;
end;

end.
