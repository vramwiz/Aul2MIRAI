unit Aul2MIRAIPlugin;

interface

uses
  AviUtl2PluginTypes;

procedure RegisterMIRAIPlugin(Host: PHostAppTable);
procedure UnregisterMIRAIPlugin;

implementation

uses
  Winapi.Windows,
  Winapi.Messages,
  System.Types,
  System.SysUtils;

const
  WINDOW_CLASS_NAME = 'Aul2MIRAIClient';
  DISPLAY_NAME      = 'AI MIRAI';

var
  ClientWindow: HWND;
  WindowBrush: HBRUSH;
  WindowClassRegistered: Boolean;

function MIRAIWndProc(WindowHandle: HWND; MessageId: UINT; WParam: WPARAM;
  LParam: LPARAM): LRESULT; stdcall;
var
  Paint: TPaintStruct;
  ClientRect: TRect;
begin
  case MessageId of
    WM_PAINT:
      begin
        BeginPaint(WindowHandle, Paint);
        try
          GetClientRect(WindowHandle, ClientRect);
          SetBkMode(Paint.hdc, TRANSPARENT);
          SetTextColor(Paint.hdc, RGB(230, 230, 230));
          DrawText(Paint.hdc, DISPLAY_NAME, -1, ClientRect,
            DT_CENTER or DT_VCENTER or DT_SINGLELINE);
        finally
          EndPaint(WindowHandle, Paint);
        end;
        Exit(0);
      end;
  end;

  Result := DefWindowProc(WindowHandle, MessageId, WParam, LParam);
end;

procedure RegisterMIRAIWindowClass;
var
  WindowClass: WNDCLASSEX;
begin
  FillChar(WindowClass, SizeOf(WindowClass), 0);
  WindowClass.cbSize := SizeOf(WindowClass);
  WindowClass.lpfnWndProc := @MIRAIWndProc;
  WindowClass.hInstance := HInstance;
  WindowClass.hCursor := LoadCursor(0, IDC_ARROW);
  WindowClass.hbrBackground := WindowBrush;
  WindowClass.lpszClassName := WINDOW_CLASS_NAME;

  if RegisterClassEx(WindowClass) <> 0 then
    WindowClassRegistered := True
  else if GetLastError <> ERROR_CLASS_ALREADY_EXISTS then
    RaiseLastOSError;
end;

procedure MIRAIEditMenuClick(Edit: PEditSection); cdecl;
begin
  if ClientWindow <> 0 then
    ShowWindow(ClientWindow, SW_SHOW);
end;

procedure RegisterMIRAIPlugin(Host: PHostAppTable);
begin
  if (Host = nil) or (ClientWindow <> 0) then
    Exit;

  WindowBrush := CreateSolidBrush(RGB(28, 30, 33));
  if WindowBrush = 0 then
    RaiseLastOSError;

  RegisterMIRAIWindowClass;

  ClientWindow := CreateWindowEx(
    0,
    WINDOW_CLASS_NAME,
    DISPLAY_NAME,
    WS_POPUP,
    CW_USEDEFAULT,
    CW_USEDEFAULT,
    520,
    360,
    0,
    0,
    HInstance,
    nil);

  if ClientWindow = 0 then
    RaiseLastOSError;

  Host^.RegisterWindowClient(DISPLAY_NAME, ClientWindow);
  Host^.RegisterEditMenu(DISPLAY_NAME, @MIRAIEditMenuClick);
end;

procedure UnregisterMIRAIPlugin;
begin
  if ClientWindow <> 0 then
  begin
    DestroyWindow(ClientWindow);
    ClientWindow := 0;
  end;

  if WindowClassRegistered then
  begin
    UnregisterClass(WINDOW_CLASS_NAME, HInstance);
    WindowClassRegistered := False;
  end;

  if WindowBrush <> 0 then
  begin
    DeleteObject(WindowBrush);
    WindowBrush := 0;
  end;
end;

end.
