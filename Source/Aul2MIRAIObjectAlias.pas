unit Aul2MIRAIObjectAlias;

// AviUtl2のUTF-8エイリアスから一覧表示に必要な最小情報だけを取り出す。

interface

function CopyUtf8Text(Value: PAnsiChar): string;
function ExtractPrimaryEffect(const AliasText: string): string;

implementation

uses
  System.SysUtils;

function CopyUtf8Text(Value: PAnsiChar): string;
begin
  if Value = nil then
    Exit('');

  Result := UTF8ToString(UTF8String(Value));
end;

function ExtractPrimaryEffect(const AliasText: string): string;
const
  EFFECT_KEY = 'effect.name=';
var
  LineEnd : Integer; // effect.name行の終端
  StartAt : Integer; // effect.name値の開始位置
begin
  Result := '';
  StartAt := Pos(EFFECT_KEY, AliasText);
  if StartAt <= 0 then
    Exit;

  Inc(StartAt, Length(EFFECT_KEY));
  LineEnd := StartAt;
  while (LineEnd <= Length(AliasText)) and
    not CharInSet(AliasText[LineEnd], [#10, #13]) do
    Inc(LineEnd);

  Result := Trim(Copy(AliasText, StartAt, LineEnd - StartAt));
end;

end.
