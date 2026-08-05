unit Aul2MIRAIView;

// 最新の外部操作ログ、短い状態、ヘルプだけを表示するWin32画面を管理する。
interface

uses
  Winapi.Windows,
  Winapi.Messages;

const
  WM_AUL2MIRAI_VIEW_UPDATE = WM_APP + 210;
  MIRAI_BACKGROUND_COLOR   = COLORREF($002D2B2A); // RGB(42, 43, 45)

procedure CreateMIRAIView(ParentWindow: HWND);
procedure DestroyMIRAIView;
procedure ResizeMIRAIView(Width, Height: Integer);
function HandleMIRAIViewCommand(WParam: WPARAM): Boolean;
function HandleMIRAIViewControlColor(DeviceContext: HDC; Control: HWND;
  out Brush: HBRUSH): Boolean;
function HandleMIRAIViewDrawItem(LParam: LPARAM): Boolean;
procedure QueueMIRAIViewUpdate(const StatusText, ObjectText, LogLevel,
  LogMessage: string);
procedure ApplyMIRAIViewUpdates;

implementation

uses
  Winapi.ShellAPI,
  System.Math,
  System.SyncObjs,
  System.SysUtils,
  System.Types;

const
  CONTROL_ID_HELP = 1001;
  CONTROL_MARGIN  = 8;
  CONTROL_HEIGHT  = 26;
  BUTTON_HEIGHT   = 28;
  BUTTON_WIDTH    = 80;
  HELP_URL        = 'https://github.com/vramwiz/Aul2MIRAI';
  TEXT_COLOR      = COLORREF($00F5F5F5); // RGB(245, 245, 245)
  MUTED_COLOR     = COLORREF($00B8B8B8); // RGB(184, 184, 184)
  SUCCESS_COLOR   = COLORREF($0098D89A); // RGB(154, 216, 152)
  WARNING_COLOR   = COLORREF($0074C7FF); // RGB(255, 199, 116)
  ERROR_COLOR     = COLORREF($007A7AFF); // RGB(255, 122, 122)
  BUTTON_COLOR    = COLORREF($00413B37); // RGB(55, 59, 65)
  BUTTON_DOWN     = COLORREF($0037312E); // RGB(46, 49, 55)
  BUTTON_BORDER   = COLORREF($006B625C); // RGB(92, 98, 107)

var
  ParentHandle     : HWND;
  LogHandle        : HWND;
  StatusHandle     : HWND;
  HelpHandle       : HWND;
  BackgroundBrush  : HBRUSH;
  PendingLock      : TCriticalSection;
  PendingLog       : string;
  PendingStatus    : string;
  PendingHasLog    : Boolean;
  PendingHasStatus : Boolean;
  CurrentStatus    : string;

procedure ApplyControlFont(Control: HWND; Font: HGDIOBJ);
begin
  if Control <> 0 then
    SendMessage(Control, WM_SETFONT, WPARAM(Font), LPARAM(1));
end;

procedure SetLog(const Value: string);
begin
  if LogHandle <> 0 then
    SetWindowText(LogHandle, PChar(Value));
end;

procedure SetStatus(const Value: string);
begin
  CurrentStatus := Value;
  if StatusHandle <> 0 then
  begin
    SetWindowText(StatusHandle, PChar('状態: ' + Value));
    InvalidateRect(StatusHandle, nil, True);
  end;
end;

function StatusTextColor: COLORREF;
begin
  if SameText(CurrentStatus, '完了') then
    Result := SUCCESS_COLOR
  else if SameText(CurrentStatus, '拒否') then
    Result := WARNING_COLOR
  else if SameText(CurrentStatus, 'エラー') then
    Result := ERROR_COLOR
  else
    Result := MUTED_COLOR;
end;

procedure OpenHelpPage;
var
  ResultCode: NativeInt;
begin
  ResultCode := NativeInt(ShellExecute(ParentHandle, 'open', HELP_URL,
    nil, nil, SW_SHOWNORMAL));
  if ResultCode <= 32 then
    MessageBox(ParentHandle,
      PChar('ブラウザでヘルプを開けませんでした。' + sLineBreak + HELP_URL),
      'AI MIRAI', MB_OK or MB_ICONERROR);
end;

procedure CreateMIRAIView(ParentWindow: HWND);
var
  ClientRect: TRect;
  GuiFont   : HGDIOBJ;
begin
  DestroyMIRAIView;
  ParentHandle := ParentWindow;
  PendingLock := TCriticalSection.Create;
  BackgroundBrush := CreateSolidBrush(MIRAI_BACKGROUND_COLOR);
  if BackgroundBrush = 0 then
    RaiseLastOSError;
  CurrentStatus := '待機中';

  LogHandle := CreateWindowEx(0, 'STATIC',
    'AIからの操作を待っています。',
    WS_CHILD or WS_VISIBLE or SS_LEFT or SS_CENTERIMAGE or SS_ENDELLIPSIS,
    0, 0, 0, 0, ParentHandle, 0, HInstance, nil);
  StatusHandle := CreateWindowEx(0, 'STATIC', '状態: 待機中',
    WS_CHILD or WS_VISIBLE or SS_LEFT or SS_CENTERIMAGE,
    0, 0, 0, 0, ParentHandle, 0, HInstance, nil);
  HelpHandle := CreateWindowEx(0, 'BUTTON', 'ヘルプ',
    WS_CHILD or WS_VISIBLE or WS_TABSTOP or BS_OWNERDRAW,
    0, 0, 0, 0, ParentHandle, HMENU(CONTROL_ID_HELP), HInstance, nil);
  if (LogHandle = 0) or (StatusHandle = 0) or (HelpHandle = 0) then
    RaiseLastOSError;

  GuiFont := GetStockObject(DEFAULT_GUI_FONT);
  ApplyControlFont(LogHandle, GuiFont);
  ApplyControlFont(StatusHandle, GuiFont);
  ApplyControlFont(HelpHandle, GuiFont);

  GetClientRect(ParentHandle, ClientRect);
  ResizeMIRAIView(ClientRect.Right, ClientRect.Bottom);
end;

procedure DestroyMIRAIView;
begin
  if LogHandle <> 0 then
    DestroyWindow(LogHandle);
  if StatusHandle <> 0 then
    DestroyWindow(StatusHandle);
  if HelpHandle <> 0 then
    DestroyWindow(HelpHandle);

  LogHandle := 0;
  StatusHandle := 0;
  HelpHandle := 0;
  ParentHandle := 0;
  if BackgroundBrush <> 0 then
    DeleteObject(BackgroundBrush);
  BackgroundBrush := 0;
  FreeAndNil(PendingLock);
  PendingLog := '';
  PendingStatus := '';
  PendingHasLog := False;
  PendingHasStatus := False;
  CurrentStatus := '';
end;

procedure ResizeMIRAIView(Width, Height: Integer);
var
  ContentWidth: Integer;
  StatusTop   : Integer;
begin
  if ParentHandle = 0 then
    Exit;

  ContentWidth := Max(Width - CONTROL_MARGIN * 2, 1);
  StatusTop := CONTROL_MARGIN * 2 + CONTROL_HEIGHT;
  MoveWindow(LogHandle, CONTROL_MARGIN, CONTROL_MARGIN,
    ContentWidth, CONTROL_HEIGHT, True);
  MoveWindow(StatusHandle, CONTROL_MARGIN, StatusTop,
    Max(ContentWidth - BUTTON_WIDTH - CONTROL_MARGIN, 1), BUTTON_HEIGHT, True);
  MoveWindow(HelpHandle, Max(Width - CONTROL_MARGIN - BUTTON_WIDTH, 0),
    StatusTop, BUTTON_WIDTH, BUTTON_HEIGHT, True);
end;

function HandleMIRAIViewCommand(WParam: WPARAM): Boolean;
begin
  Result := (LOWORD(WParam) = CONTROL_ID_HELP) and
    (HIWORD(WParam) = BN_CLICKED);
  if Result then
    OpenHelpPage;
end;

function HandleMIRAIViewControlColor(DeviceContext: HDC; Control: HWND;
  out Brush: HBRUSH): Boolean;
begin
  Result := (BackgroundBrush <> 0) and
    ((Control = LogHandle) or (Control = StatusHandle));
  if not Result then
  begin
    Brush := 0;
    Exit;
  end;

  SetBkColor(DeviceContext, MIRAI_BACKGROUND_COLOR);
  if Control = StatusHandle then
    SetTextColor(DeviceContext, StatusTextColor)
  else
    SetTextColor(DeviceContext, TEXT_COLOR);
  Brush := BackgroundBrush;
end;

function HandleMIRAIViewDrawItem(LParam: LPARAM): Boolean;
var
  BorderBrush : HBRUSH;
  ButtonBrush : HBRUSH;
  DrawInfo    : PDrawItemStruct;
  DrawRect    : TRect;
  IsPressed   : Boolean;
  TextBuffer  : array[0..63] of Char;
begin
  DrawInfo := PDrawItemStruct(LParam);
  Result := (DrawInfo <> nil) and (DrawInfo^.CtlID = CONTROL_ID_HELP);
  if not Result then
    Exit;

  IsPressed := (DrawInfo^.itemState and ODS_SELECTED) <> 0;
  if IsPressed then
    ButtonBrush := CreateSolidBrush(BUTTON_DOWN)
  else
    ButtonBrush := CreateSolidBrush(BUTTON_COLOR);
  BorderBrush := CreateSolidBrush(BUTTON_BORDER);
  try
    FillRect(DrawInfo^.hDC, DrawInfo^.rcItem, ButtonBrush);
    FrameRect(DrawInfo^.hDC, DrawInfo^.rcItem, BorderBrush);
  finally
    DeleteObject(BorderBrush);
    DeleteObject(ButtonBrush);
  end;

  DrawRect := DrawInfo^.rcItem;
  if IsPressed then
    OffsetRect(DrawRect, 1, 1);
  SetBkMode(DrawInfo^.hDC, TRANSPARENT);
  SetTextColor(DrawInfo^.hDC, TEXT_COLOR);
  GetWindowText(HelpHandle, TextBuffer, Length(TextBuffer));
  DrawText(DrawInfo^.hDC, TextBuffer, -1, DrawRect,
    DT_CENTER or DT_VCENTER or DT_SINGLELINE);

  if (DrawInfo^.itemState and ODS_FOCUS) <> 0 then
  begin
    InflateRect(DrawRect, -3, -3);
    DrawFocusRect(DrawInfo^.hDC, DrawRect);
  end;
end;

procedure QueueMIRAIViewUpdate(const StatusText, ObjectText, LogLevel,
  LogMessage: string);
var
  NewLog   : string;
  NewStatus: string;
begin
  if (PendingLock = nil) or (ParentHandle = 0) then
    Exit;

  if SameText(LogLevel, 'OK') then
    NewStatus := '完了'
  else if SameText(LogLevel, 'WARN') then
    NewStatus := '拒否'
  else if SameText(LogLevel, 'ERROR') then
    NewStatus := 'エラー'
  else
    NewStatus := '待機中';

  NewLog := LogMessage;
  if NewLog = '' then
    NewLog := StatusText;
  if NewLog = '' then
    NewLog := 'AIからの操作を待っています。';

  PendingLock.Acquire;
  try
    PendingStatus := NewStatus;
    PendingLog := NewLog;
    PendingHasStatus := True;
    PendingHasLog := True;
  finally
    PendingLock.Release;
  end;
  PostMessage(ParentHandle, WM_AUL2MIRAI_VIEW_UPDATE, 0, 0);
end;

procedure ApplyMIRAIViewUpdates;
var
  HasLog    : Boolean;
  HasStatus : Boolean;
  LogText   : string;
  StatusText: string;
begin
  if PendingLock = nil then
    Exit;

  PendingLock.Acquire;
  try
    HasStatus := PendingHasStatus;
    HasLog := PendingHasLog;
    StatusText := PendingStatus;
    LogText := PendingLog;
    PendingHasStatus := False;
    PendingHasLog := False;
    PendingStatus := '';
    PendingLog := '';
  finally
    PendingLock.Release;
  end;

  if HasStatus then
    SetStatus(StatusText);
  if HasLog then
    SetLog(LogText);
end;

end.
