library Aul2MIRAI;

// AviUtl2 extension plugin: AI MIRAI

{$ALIGN 8}

uses
  Winapi.Windows,
  System.SysUtils,
  AviUtl2PluginTypes in 'Source\Lib\AviUtl2Plugin\AviUtl2PluginTypes.pas',
  AviUtl2PluginCore in 'Source\Lib\AviUtl2Plugin\AviUtl2PluginCore.pas',
  PipeServerTThread in 'Source\Lib\Pipe\PipeServerTThread.pas',
  Aul2MIRAIObjectTypes in 'Source\Aul2MIRAIObjectTypes.pas',
  Aul2MIRAIObjectAlias in 'Source\Aul2MIRAIObjectAlias.pas',
  Aul2MIRAIObjectReader in 'Source\Aul2MIRAIObjectReader.pas',
  Aul2MIRAIObjectFormat in 'Source\Aul2MIRAIObjectFormat.pas',
  Aul2MIRAIProtocol in 'Source\Aul2MIRAIProtocol.pas',
  Aul2MIRAICommand in 'Source\Aul2MIRAICommand.pas',
  Aul2MIRAIPipeServer in 'Source\Aul2MIRAIPipeServer.pas',
  Aul2MIRAILog in 'Source\Aul2MIRAILog.pas',
  Aul2MIRAIView in 'Source\Aul2MIRAIView.pas',
  Aul2MIRAIPlugin in 'Source\Aul2MIRAIPlugin.pas';

function InitializePlugin(Version: DWORD): BOOL; cdecl;
begin
  Result := True;
end;

procedure UninitializePlugin; cdecl;
begin
  UnregisterMIRAIPlugin;
  EditHandle := nil;
  ProjectFile := nil;
  GAviUtl2Plugin := False;
end;

procedure RegisterPlugin(Host: PHostAppTable); cdecl;
begin
  try
    if Host = nil then
      Exit;

    Host^.SetPluginInformation('AI MIRAI');
    EditHandle := Host^.CreateEditHandle;
    if EditHandle = nil then
      raise Exception.Create('AviUtl2 edit handle is not available.');
    GAviUtl2Plugin := True;
    RegisterMIRAIPlugin(Host);
  except
    // Do not allow Delphi exceptions to cross the AviUtl2 SDK boundary.
    UnregisterMIRAIPlugin;
    EditHandle := nil;
    ProjectFile := nil;
    GAviUtl2Plugin := False;
  end;
end;

exports
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  RegisterPlugin name 'RegisterPlugin';

begin
end.
