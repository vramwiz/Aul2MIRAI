library Aul2MIRAI;

// AviUtl2 extension plugin: AI MIRAI

{$ALIGN 8}

uses
  Winapi.Windows,
  System.SysUtils,
  AviUtl2PluginTypes in 'Source\Lib\AviUtl2Plugin\AviUtl2PluginTypes.pas',
  Aul2MIRAIPlugin in 'Source\Aul2MIRAIPlugin.pas';

function InitializePlugin(Version: DWORD): BOOL; cdecl;
begin
  Result := True;
end;

procedure UninitializePlugin; cdecl;
begin
  UnregisterMIRAIPlugin;
end;

procedure RegisterPlugin(Host: PHostAppTable); cdecl;
begin
  try
    if Host = nil then
      Exit;

    Host^.SetPluginInformation('AI MIRAI');
    RegisterMIRAIPlugin(Host);
  except
    // Do not allow Delphi exceptions to cross the AviUtl2 SDK boundary.
    UnregisterMIRAIPlugin;
  end;
end;

exports
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  RegisterPlugin name 'RegisterPlugin';

begin
end.
