unit Aul2MIRAIExtensionProvider;

// 同一AviUtl2プロセスに読み込まれた拡張プロバイダーをC ABIで呼び出す。

interface

function InvokeMmdExtensionProvider(const RequestText: string;
  out ResponseText, ErrorCode, ErrorMessage: string): Boolean;

implementation

uses
  Winapi.TlHelp32,
  Winapi.Windows,
  System.SysUtils;

const
  EXPECTED_MMD_PROVIDER_VERSION = 1;
  MAX_PROVIDER_RESPONSE_BYTES = 2 * 1024 * 1024;

type
  TMmdProviderGetVersion = function: Cardinal; cdecl;
  TMmdProviderInvoke = function(RequestUtf8, ResponseUtf8: PAnsiChar;
    ResponseCapacity: Cardinal): Integer; cdecl;

function FindMmdProvider(out Invoke: TMmdProviderInvoke): Boolean;
var
  Address: Pointer;
  Entry: TModuleEntry32;
  GetVersion: TMmdProviderGetVersion;
  Snapshot: THandle;
begin
  Result := False;
  Invoke := nil;
  Snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPMODULE,
    GetCurrentProcessId);
  if Snapshot = INVALID_HANDLE_VALUE then
    Exit;
  try
    Entry.dwSize := SizeOf(Entry);
    if not Module32First(Snapshot, Entry) then
      Exit;
    repeat
      Address := GetProcAddress(Entry.hModule, 'MmdAiProviderGetVersion');
      GetVersion := TMmdProviderGetVersion(Address);
      Address := GetProcAddress(Entry.hModule, 'MmdAiProviderInvoke');
      Invoke := TMmdProviderInvoke(Address);
      if Assigned(GetVersion) and Assigned(Invoke) and
        (GetVersion() = EXPECTED_MMD_PROVIDER_VERSION) then
        Exit(True);
      Invoke := nil;
    until not Module32Next(Snapshot, Entry);
  finally
    CloseHandle(Snapshot);
  end;
end;

function InvokeMmdExtensionProvider(const RequestText: string;
  out ResponseText, ErrorCode, ErrorMessage: string): Boolean;
var
  Buffer: TBytes;
  Invoke: TMmdProviderInvoke;
  Required, Written: Integer;
  RequestUtf8: UTF8String;
begin
  Result := False;
  ResponseText := '';
  ErrorCode := '';
  ErrorMessage := '';
  if not FindMmdProvider(Invoke) then
  begin
    ErrorCode := 'extension_provider_not_found';
    ErrorMessage := 'The MMD pose provider is not loaded.';
    Exit;
  end;
  RequestUtf8 := UTF8String(RequestText);
  Required := Invoke(PAnsiChar(RequestUtf8), nil, 0);
  if (Required <= 0) or (Required > MAX_PROVIDER_RESPONSE_BYTES) then
  begin
    ErrorCode := 'extension_response_too_large';
    ErrorMessage := 'The MMD provider returned an invalid response size.';
    Exit;
  end;
  SetLength(Buffer, Required + 1);
  Written := Invoke(PAnsiChar(RequestUtf8), PAnsiChar(@Buffer[0]),
    Length(Buffer));
  if Written <> Required then
  begin
    ErrorCode := 'extension_response_failed';
    ErrorMessage := 'The MMD provider response size changed.';
    Exit;
  end;
  ResponseText := UTF8ToString(PAnsiChar(@Buffer[0]));
  Result := ResponseText <> '';
  if not Result then
  begin
    ErrorCode := 'extension_response_failed';
    ErrorMessage := 'The MMD provider returned an empty response.';
  end;
end;

end.
