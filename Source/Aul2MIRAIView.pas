unit Aul2MIRAIView;

// 命令入力、送信と停止を兼ねるボタン、状態と結果だけを表示するWin32画面を管理する。
interface

uses
  Winapi.Windows,
  Winapi.Messages;

const
  WM_AUL2MIRAI_VIEW_UPDATE = WM_APP + 210;
  MIRAI_BACKGROUND_COLOR = COLORREF($002D2B2A); // RGB(42, 43, 45)

// 指定したホスト子ウィンドウに操作画面と進捗タイマーを作成する。
procedure CreateMIRAIView(ParentWindow: HWND);
// Codexワーカーを停止・回収してからコントロールと表示資源を解放する。
procedure DestroyMIRAIView;
// ホストから通知されたクライアント寸法に画面部品を配置する。
procedure ResizeMIRAIView(Width, Height: Integer);
// 送信・停止ボタンの通知を処理した場合にTrueを返す。
function HandleMIRAIViewCommand(WParam: WPARAM): Boolean;
// 自身のコントロールへ背景と文字色を設定し、所有ブラシを返す。
function HandleMIRAIViewControlColor(DeviceContext: HDC; Control: HWND; out Brush: HBRUSH): Boolean;
// 送信・停止ボタンを描画した場合にTrueを返す。
function HandleMIRAIViewDrawItem(LParam: LPARAM): Boolean;
// 既存コマンドから受け取った短い状態を保持し、UIへ更新を通知する。
procedure QueueMIRAIViewUpdate(const StatusText, ObjectText, LogLevel, LogMessage: string);
// 保持した状態をUIへ反映する。Codex進行中の表示は維持する。
procedure ApplyMIRAIViewUpdates;
// UIタイマーからCodexの要求を実行し、進捗と終了結果を反映する。
procedure PollMIRAICodex;

implementation

uses
  System.Math,
  System.SyncObjs,
  System.SysUtils,
  System.Types,
  Aul2MIRAICodexClient,
  Aul2MIRAICodexBridge,
  Aul2MIRAIProtocol;

const
  CONTROL_ID_ACTION = 1002;                  // 待機中は送信、実行中は停止する唯一のボタン
  CODEX_TIMER_ID    = 210;                   // UIでの要求処理と状態取得用タイマー
  TEXT_COLOR        = COLORREF($00F5F5F5);    // RGB(245, 245, 245)
  MUTED_COLOR       = COLORREF($00B8B8B8);    // RGB(184, 184, 184)
  SUCCESS_COLOR     = COLORREF($0098D89A);    // RGB(154, 216, 152)
  WARNING_COLOR     = COLORREF($0074C7FF);    // RGB(255, 199, 116)
  ERROR_COLOR       = COLORREF($007A7AFF);    // RGB(255, 122, 122)
  BUTTON_COLOR      = COLORREF($00413B37);    // RGB(55, 59, 65)
  BUTTON_DOWN       = COLORREF($0037312E);    // RGB(46, 49, 55)
  BUTTON_BORDER     = COLORREF($006B625C);    // RGB(92, 98, 107)

var
  ParentHandle    : HWND;              // AviUtl2へ登録するクライアント
  PromptLabel     : HWND;              // 命令入力欄の短い見出し
  PromptHandle    : HWND;              // 複数行の命令入力欄
  ActionHandle    : HWND;              // 送信・停止を切り替えるボタン
  StatusHandle    : HWND;              // 1行の進捗表示
  ResultLabel     : HWND;              // 結果欄の見出し
  ResultHandle    : HWND;              // 選択・コピー可能な結果欄
  GuiFont         : HFONT;             // 各コントロールとボタン描画で共有する所有フォント
  ViewDpi         : Integer;           // ホストウィンドウの表示倍率
  CodexJob        : TMIRAICodexJob;    // UIが所有し終了時に回収するワーカー
  BackgroundBrush : HBRUSH;            // 各部品の暗い背景用所有ブラシ
  PendingLock     : TCriticalSection; // 既存コマンドからの通知を保護する
  PendingStatus   : string;           // 次にUIへ反映する短い状態
  PendingHasStatus: Boolean;          // 未反映の状態通知の有無
  CurrentStatus   : string;           // 色の判定にも使用する表示中の状態

function Scaled(Value: Integer): Integer;
begin
  Result := MulDiv(Value, Max(ViewDpi, 96), 96);
end;

procedure SetStatus(const Value: string);
begin
  if CurrentStatus = Value then Exit;
  CurrentStatus := Value;
  if StatusHandle <> 0 then
  begin
    SetWindowText(StatusHandle, PChar(Value));
    InvalidateRect(StatusHandle, nil, True);
  end;
end;

function StatusTextColor: COLORREF;
begin
  if CurrentStatus = '完了' then Result := SUCCESS_COLOR
  else if CurrentStatus = '拒否' then Result := WARNING_COLOR
  else if (CurrentStatus = 'エラー') or (CurrentStatus = '停止 / エラー') then Result := ERROR_COLOR
  else Result := MUTED_COLOR;
end;

function ReadControlText(Control: HWND): string;
var
  Count: Integer; // 終端文字を除く入力長
begin
  Count := GetWindowTextLength(Control);
  SetLength(Result, Count + 1);
  Count := GetWindowText(Control, PChar(Result), Count + 1);
  SetLength(Result, Count);
end;

procedure SetCodexBusy(Busy: Boolean);
begin
  if Busy then SetWindowText(ActionHandle, '停止')
  else SetWindowText(ActionHandle, '送信');
  EnableWindow(ActionHandle, True);
  // 無効化するとOSが文字を灰色にするため、実行中も読み取り専用のまま有効に保つ。
  SendMessage(PromptHandle, EM_SETREADONLY, WPARAM(Ord(Busy)), 0);
  InvalidateRect(ActionHandle, nil, True);
  InvalidateRect(PromptHandle, nil, True);
end;

procedure SendCodexInstruction;
var
  Prompt: string; // 利用者が送信した命令本文
begin
  Prompt := Trim(ReadControlText(PromptHandle));
  if Prompt = '' then
  begin
    SetStatus('命令を入力してください');
    SetFocus(PromptHandle);
    Exit;
  end;
  try
    CodexJob := TMIRAICodexJob.Create(Prompt, True);
    SetWindowText(ResultHandle, '');
    SetCodexBusy(True);
    CodexJob.BeginRun;
    SetStatus('接続中');
  except
    on E: Exception do
    begin
      FreeAndNil(CodexJob);
      SetCodexBusy(False);
      SetStatus('エラー');
      SetWindowText(ResultHandle, PChar(E.Message));
    end;
  end;
end;

procedure PollMIRAICodex;
var
  Request : string; // UIスレッドで処理するJSON要求
  Response: string; // 既存プロトコルのJSON応答
  Text    : string; // 利用者向けの最終結果
begin
  if CodexJob = nil then Exit;
  SetStatus(CodexJob.Stage);
  if CodexJob.TakeRequest(Request) then
  begin
    try Response := ExecuteMIRAICodexRequest(Request, CodexJob.AllowEdits);
    except on E: Exception do Response := BuildProtocolError('', 'internal_error', E.Message); end;
    CodexJob.CompleteRequest(Response);
  end;
  if WaitForSingleObject(CodexJob.Handle, 0) <> WAIT_OBJECT_0 then Exit;
  if CodexJob.Success then
  begin
    Text := CodexJob.Answer;
    SetStatus('完了');
  end
  else
  begin
    Text := CodexJob.ErrorText;
    SetStatus('停止 / エラー');
  end;
  SetWindowText(ResultHandle, PChar(Text));
  FreeAndNil(CodexJob);
  SetCodexBusy(False);
end;

procedure CreateMIRAIView(ParentWindow: HWND);
var
  ClientRect: TRect; // 初期配置用のホストクライアント寸法
begin
  DestroyMIRAIView;
  ParentHandle := ParentWindow;
  ViewDpi := GetDpiForWindow(ParentHandle);
  PendingLock := TCriticalSection.Create;
  BackgroundBrush := CreateSolidBrush(MIRAI_BACKGROUND_COLOR);
  GuiFont := CreateFont(-Scaled(13), 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET,
    OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, 'Yu Gothic UI');
  if (BackgroundBrush = 0) or (GuiFont = 0) then RaiseLastOSError;

  PromptLabel := CreateWindowEx(0, 'STATIC', '命令', WS_CHILD or WS_VISIBLE or SS_LEFT,
    0, 0, 0, 0, ParentHandle, 0, HInstance, nil);
  PromptHandle := CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '',
    WS_CHILD or WS_VISIBLE or WS_TABSTOP or WS_VSCROLL or ES_MULTILINE or ES_AUTOVSCROLL or ES_WANTRETURN,
    0, 0, 0, 0, ParentHandle, 0, HInstance, nil);
  ActionHandle := CreateWindowEx(0, 'BUTTON', '送信',
    WS_CHILD or WS_VISIBLE or WS_TABSTOP or BS_OWNERDRAW,
    0, 0, 0, 0, ParentHandle, HMENU(CONTROL_ID_ACTION), HInstance, nil);
  StatusHandle := CreateWindowEx(0, 'STATIC', '待機中',
    WS_CHILD or WS_VISIBLE or SS_LEFT or SS_CENTERIMAGE or SS_ENDELLIPSIS,
    0, 0, 0, 0, ParentHandle, 0, HInstance, nil);
  ResultLabel := CreateWindowEx(0, 'STATIC', '結果', WS_CHILD or WS_VISIBLE or SS_LEFT,
    0, 0, 0, 0, ParentHandle, 0, HInstance, nil);
  ResultHandle := CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '',
    WS_CHILD or WS_VISIBLE or WS_TABSTOP or WS_VSCROLL or ES_MULTILINE or ES_AUTOVSCROLL or ES_READONLY,
    0, 0, 0, 0, ParentHandle, 0, HInstance, nil);
  if (PromptLabel = 0) or (PromptHandle = 0) or (ActionHandle = 0) or
     (StatusHandle = 0) or (ResultLabel = 0) or (ResultHandle = 0) then RaiseLastOSError;
  SendMessage(PromptHandle, EM_SETLIMITTEXT, 32000, 0);
  SendMessage(ResultHandle, EM_SETLIMITTEXT, 256 * 1024, 0);
  for var Control in [PromptLabel, PromptHandle, ActionHandle, StatusHandle, ResultLabel, ResultHandle] do
    SendMessage(Control, WM_SETFONT, WPARAM(GuiFont), LPARAM(1));
  CurrentStatus := '待機中';
  SetCodexBusy(False);
  if SetTimer(ParentHandle, CODEX_TIMER_ID, 100, nil) = 0 then RaiseLastOSError;
  GetClientRect(ParentHandle, ClientRect);
  ResizeMIRAIView(ClientRect.Right, ClientRect.Bottom);
end;

procedure DestroyMIRAIView;
begin
  if ParentHandle <> 0 then KillTimer(ParentHandle, CODEX_TIMER_ID);
  FreeAndNil(CodexJob);
  if PromptLabel <> 0 then DestroyWindow(PromptLabel);
  if PromptHandle <> 0 then DestroyWindow(PromptHandle);
  if ActionHandle <> 0 then DestroyWindow(ActionHandle);
  if StatusHandle <> 0 then DestroyWindow(StatusHandle);
  if ResultLabel <> 0 then DestroyWindow(ResultLabel);
  if ResultHandle <> 0 then DestroyWindow(ResultHandle);
  PromptLabel := 0;
  PromptHandle := 0;
  ActionHandle := 0;
  StatusHandle := 0;
  ResultLabel := 0;
  ResultHandle := 0;
  ParentHandle := 0;
  if GuiFont <> 0 then DeleteObject(GuiFont);
  GuiFont := 0;
  if BackgroundBrush <> 0 then DeleteObject(BackgroundBrush);
  BackgroundBrush := 0;
  FreeAndNil(PendingLock);
  PendingStatus := '';
  PendingHasStatus := False;
  CurrentStatus := '';
end;

procedure ResizeMIRAIView(Width, Height: Integer);
var
  Margin, LabelHeight, ButtonHeight, ButtonWidth: Integer;
  ContentWidth, BodyHeight, PromptHeight, ButtonTop, ResultTop: Integer;
begin
  if ParentHandle = 0 then Exit;
  Margin := Scaled(6);
  LabelHeight := Scaled(18);
  ButtonHeight := Scaled(28);
  ButtonWidth := Min(Scaled(64), Max(Width - Margin * 2, 1));
  ContentWidth := Max(Width - Margin * 2, 1);
  BodyHeight := Max(Height - Margin * 6 - LabelHeight * 2 - ButtonHeight, 2);
  PromptHeight := Max(Scaled(40), BodyHeight div 3);
  MoveWindow(PromptLabel, Margin, Margin, ContentWidth, LabelHeight, True);
  MoveWindow(PromptHandle, Margin, Margin * 2 + LabelHeight, ContentWidth, PromptHeight, True);
  ButtonTop := Margin * 3 + LabelHeight + PromptHeight;
  MoveWindow(StatusHandle, Margin, ButtonTop,
    Max(ContentWidth - ButtonWidth - Margin, 1), ButtonHeight, True);
  MoveWindow(ActionHandle, Max(Width - Margin - ButtonWidth, 0), ButtonTop,
    ButtonWidth, ButtonHeight, True);
  ResultTop := ButtonTop + ButtonHeight + Margin;
  MoveWindow(ResultLabel, Margin, ResultTop, ContentWidth, LabelHeight, True);
  ResultTop := ResultTop + LabelHeight + Margin;
  MoveWindow(ResultHandle, Margin, ResultTop, ContentWidth, Max(Height - ResultTop - Margin, 1), True);
end;

function HandleMIRAIViewCommand(WParam: WPARAM): Boolean;
begin
  Result := (LOWORD(WParam) = CONTROL_ID_ACTION) and (HIWORD(WParam) = BN_CLICKED);
  if not Result then Exit;
  if CodexJob = nil then SendCodexInstruction
  else
  begin
    CodexJob.RequestStop;
    SetWindowText(ActionHandle, '停止中');
    EnableWindow(ActionHandle, False);
    SetStatus('停止中');
  end;
end;

function HandleMIRAIViewControlColor(DeviceContext: HDC; Control: HWND; out Brush: HBRUSH): Boolean;
begin
  Result := (BackgroundBrush <> 0) and ((Control = PromptLabel) or (Control = PromptHandle) or
    (Control = StatusHandle) or (Control = ResultLabel) or (Control = ResultHandle));
  Brush := 0;
  if not Result then Exit;
  SetBkColor(DeviceContext, MIRAI_BACKGROUND_COLOR);
  SetBkMode(DeviceContext, OPAQUE);
  if Control = StatusHandle then SetTextColor(DeviceContext, StatusTextColor)
  else SetTextColor(DeviceContext, TEXT_COLOR);
  Brush := BackgroundBrush;
end;

function HandleMIRAIViewDrawItem(LParam: LPARAM): Boolean;
var
  BorderBrush: HBRUSH;                 // 一時的なボタン枠ブラシ
  ButtonBrush: HBRUSH;                 // 押下状態に応じた一時背景ブラシ
  DrawInfo   : PDrawItemStruct;        // ホストからの描画要求
  DrawRect   : TRect;                  // ボタンの描画領域
  IsPressed  : Boolean;                // 押下中の状態
  SavedDC    : Integer;                // 共有DCのフォントと色を復元する保存位置
  TextBuffer : array[0..31] of Char;   // 送信・停止の現在のラベル
begin
  DrawInfo := PDrawItemStruct(LParam);
  Result := (DrawInfo <> nil) and (DrawInfo^.CtlID = CONTROL_ID_ACTION);
  if not Result then Exit;
  IsPressed := (DrawInfo^.itemState and ODS_SELECTED) <> 0;
  if IsPressed then ButtonBrush := CreateSolidBrush(BUTTON_DOWN)
  else ButtonBrush := CreateSolidBrush(BUTTON_COLOR);
  BorderBrush := CreateSolidBrush(BUTTON_BORDER);
  SavedDC := SaveDC(DrawInfo^.hDC);
  try
    FillRect(DrawInfo^.hDC, DrawInfo^.rcItem, ButtonBrush);
    FrameRect(DrawInfo^.hDC, DrawInfo^.rcItem, BorderBrush);
    DrawRect := DrawInfo^.rcItem;
    if IsPressed then OffsetRect(DrawRect, 1, 1);
    SelectObject(DrawInfo^.hDC, GuiFont);
    SetBkMode(DrawInfo^.hDC, TRANSPARENT);
    if (DrawInfo^.itemState and ODS_DISABLED) <> 0 then SetTextColor(DrawInfo^.hDC, MUTED_COLOR)
    else SetTextColor(DrawInfo^.hDC, TEXT_COLOR);
    GetWindowText(DrawInfo^.hwndItem, TextBuffer, Length(TextBuffer));
    DrawText(DrawInfo^.hDC, TextBuffer, -1, DrawRect, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
    if (DrawInfo^.itemState and ODS_FOCUS) <> 0 then
    begin
      InflateRect(DrawRect, -3, -3);
      DrawFocusRect(DrawInfo^.hDC, DrawRect);
    end;
  finally
    RestoreDC(DrawInfo^.hDC, SavedDC);
    DeleteObject(BorderBrush);
    DeleteObject(ButtonBrush);
  end;
end;

procedure QueueMIRAIViewUpdate(const StatusText, ObjectText, LogLevel, LogMessage: string);
var
  NewStatus: string; // 詳細ログを画面へ出さず、短い状態だけを通知する
begin
  if (PendingLock = nil) or (ParentHandle = 0) then Exit;
  if SameText(LogLevel, 'OK') then NewStatus := '完了'
  else if SameText(LogLevel, 'WARN') then NewStatus := '拒否'
  else if SameText(LogLevel, 'ERROR') then NewStatus := 'エラー'
  else NewStatus := '待機中';
  PendingLock.Acquire;
  try
    PendingStatus := NewStatus;
    PendingHasStatus := True;
  finally
    PendingLock.Release;
  end;
  PostMessage(ParentHandle, WM_AUL2MIRAI_VIEW_UPDATE, 0, 0);
end;

procedure ApplyMIRAIViewUpdates;
var
  HasStatus : Boolean; // 未反映通知を取り出したか
  StatusText: string;  // 取り出した短い状態
begin
  if PendingLock = nil then Exit;
  PendingLock.Acquire;
  try
    HasStatus := PendingHasStatus;
    StatusText := PendingStatus;
    PendingHasStatus := False;
    PendingStatus := '';
  finally
    PendingLock.Release;
  end;
  if HasStatus and (CodexJob = nil) then SetStatus(StatusText);
end;

end.
