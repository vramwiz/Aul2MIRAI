unit Aul2MIRAIView;

// 最新の外部操作ログ、短い状態、ヘルプだけを表示するWin32画面を管理する。
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
function HandleMIRAIControlColor(DeviceContext: HDC;
  ControlHandle: HWND): HBRUSH;
function HandleMIRAIDrawItem(DrawItem: PDrawItemStruct): Boolean;
function PaintMIRAIViewBackground(DeviceContext: HDC): Boolean;
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
  COLOR_BACKGROUND = $00202020;
  COLOR_CONTROL    = $00303030;
  COLOR_BUTTON     = $00383838;
  COLOR_BUTTON_DOWN = $00282828;
  COLOR_BORDER     = $00585858;
  COLOR_TEXT       = $00F0F0F0;
  COLOR_TEXT_DISABLED = $00808080;

var
  ParentHandle     : HWND;
  LogHandle        : HWND;
  StatusHandle     : HWND;
  HelpHandle       : HWND;
  PendingLock      : TCriticalSection;
  PendingLog       : string;
  PendingStatus    : string;
  PendingHasLog    : Boolean;
  PendingHasStatus : Boolean;
  BackgroundBrush  : HBRUSH;
  ControlBrush     : HBRUSH;

procedure CreateDarkBrushes;
begin
  if BackgroundBrush = 0 then
    BackgroundBrush := CreateSolidBrush(COLOR_BACKGROUND);
  if ControlBrush = 0 then
    ControlBrush := CreateSolidBrush(COLOR_CONTROL);
end;

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
  if StatusHandle <> 0 then
    SetWindowText(StatusHandle, PChar('状態: ' + Value));
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
  CreateDarkBrushes;

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
  FreeAndNil(PendingLock);
  PendingLog := '';
  PendingStatus := '';
  PendingHasLog := False;
  PendingHasStatus := False;
  if ControlBrush <> 0 then
    DeleteObject(ControlBrush);
  if BackgroundBrush <> 0 then
    DeleteObject(BackgroundBrush);
  ControlBrush := 0;
  BackgroundBrush := 0;
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

function HandleMIRAIControlColor(DeviceContext: HDC;
  ControlHandle: HWND): HBRUSH;
begin
  Result := 0;
  if (ControlHandle <> LogHandle) and (ControlHandle <> StatusHandle) then
    Exit;

  CreateDarkBrushes;
  SetTextColor(DeviceContext, COLOR_TEXT);
  SetBkColor(DeviceContext, COLOR_CONTROL);
  SetBkMode(DeviceContext, OPAQUE);
  Result := ControlBrush;
end;

function HandleMIRAIDrawItem(DrawItem: PDrawItemStruct): Boolean;
var
  BorderBrush: HBRUSH;
  ButtonBrush: HBRUSH;
  ButtonText : array[0..255] of Char;
  TextColor  : COLORREF;
  TextRect   : TRect;
begin
  Result := (DrawItem <> nil) and (DrawItem^.CtlID = CONTROL_ID_HELP);
  if not Result then
    Exit;

  if (DrawItem^.itemState and ODS_SELECTED) <> 0 then
    ButtonBrush := CreateSolidBrush(COLOR_BUTTON_DOWN)
  else
    ButtonBrush := CreateSolidBrush(COLOR_BUTTON);
  BorderBrush := CreateSolidBrush(COLOR_BORDER);
  try
    FillRect(DrawItem^.hDC, DrawItem^.rcItem, BorderBrush);
    TextRect := DrawItem^.rcItem;
    InflateRect(TextRect, -1, -1);
    FillRect(DrawItem^.hDC, TextRect, ButtonBrush);

    if (DrawItem^.itemState and ODS_DISABLED) <> 0 then
      TextColor := COLOR_TEXT_DISABLED
    else
      TextColor := COLOR_TEXT;
    SetTextColor(DrawItem^.hDC, TextColor);
    SetBkMode(DrawItem^.hDC, TRANSPARENT);
    GetWindowText(DrawItem^.hwndItem, ButtonText, Length(ButtonText));
    DrawText(DrawItem^.hDC, ButtonText, -1, TextRect,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE);

    if (DrawItem^.itemState and ODS_FOCUS) <> 0 then
    begin
      InflateRect(TextRect, -3, -3);
      DrawFocusRect(DrawItem^.hDC, TextRect);
    end;
  finally
    DeleteObject(BorderBrush);
    DeleteObject(ButtonBrush);
  end;
end;

function PaintMIRAIViewBackground(DeviceContext: HDC): Boolean;
var
  ClientRect: TRect;
begin
  Result := (ParentHandle <> 0) and (DeviceContext <> 0);
  if not Result then
    Exit;

  CreateDarkBrushes;
  GetClientRect(ParentHandle, ClientRect);
  FillRect(DeviceContext, ClientRect, BackgroundBrush);
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
