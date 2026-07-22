unit Aul2MIRAILog;

// AI MIRAI画面に表示する短い操作ログを件数制限付きで保持する。

interface

uses
  System.Classes;

type
  TAul2MIRAIOperationLog = class
  private
    FLines: TStringList;
    procedure TrimOldLines;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const Level, MessageText: string);
    procedure Clear;
    function Text: string;
  end;

implementation

uses
  System.SysUtils;

const
  MAX_LOG_LINES = 200;

constructor TAul2MIRAIOperationLog.Create;
begin
  inherited Create;
  FLines := TStringList.Create;
end;

destructor TAul2MIRAIOperationLog.Destroy;
begin
  FLines.Free;
  inherited;
end;

procedure TAul2MIRAIOperationLog.TrimOldLines;
begin
  while FLines.Count > MAX_LOG_LINES do
    FLines.Delete(0);
end;

procedure TAul2MIRAIOperationLog.Add(const Level, MessageText: string);
begin
  FLines.Add(Format('%s  %-5s  %s',
    [FormatDateTime('hh:nn:ss.zzz', Now), Level, MessageText]));
  TrimOldLines;
end;

procedure TAul2MIRAIOperationLog.Clear;
begin
  FLines.Clear;
end;

function TAul2MIRAIOperationLog.Text: string;
begin
  Result := FLines.Text;
end;

end.
