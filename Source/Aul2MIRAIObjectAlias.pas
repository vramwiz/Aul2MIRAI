unit Aul2MIRAIObjectAlias;

// AviUtl2のUTF-8エイリアスから一覧表示に必要な最小情報だけを取り出す。

interface

uses
  Aul2MIRAIObjectTypes;

function CopyUtf8Text(Value: PAnsiChar): string;
function ExtractPrimaryEffect(const AliasText: string): string;
function ExtractEffectNames(const AliasText: string): TArray<string>;
function ExtractMaterialPath(const AliasText: string): string;
function ExtractEffectDetails(const AliasText: string):
  TArray<TAul2MIRAIEffectDetail>;
function AppendRepeatedEffectBlock(const AliasText, EffectName: string;
  out ResultAlias, ErrorMessage: string): Boolean;

implementation

uses
  System.Classes,
  System.SysUtils,
  System.StrUtils;

const
  EFFECT_KEY = 'effect.name=';
  FILE_KEY   = #$30D5#$30A1#$30A4#$30EB;
  MAX_EFFECT_COUNT = 256;
  MAX_PARAMETER_COUNT = 2048;
  MAX_PARAMETER_VALUE_CHARS = 16384;

function CopyUtf8Text(Value: PAnsiChar): string;
begin
  if Value = nil then
    Exit('');

  Result := UTF8ToString(UTF8String(Value));
end;

function ExtractPrimaryEffect(const AliasText: string): string;
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

function ExtractEffectNames(const AliasText: string): TArray<string>;
var
  Count   : Integer;
  LineEnd : Integer;
  StartAt : Integer;
begin
  Count := 0;
  StartAt := 1;
  while True do
  begin
    StartAt := PosEx(EFFECT_KEY, AliasText, StartAt);
    if StartAt <= 0 then
      Break;
    Inc(StartAt, Length(EFFECT_KEY));
    LineEnd := StartAt;
    while (LineEnd <= Length(AliasText)) and
      not CharInSet(AliasText[LineEnd], [#10, #13]) do
      Inc(LineEnd);
    SetLength(Result, Count + 1);
    Result[Count] := Trim(Copy(AliasText, StartAt, LineEnd - StartAt));
    Inc(Count);
    StartAt := LineEnd + 1;
  end;
end;

function ExtractAliasValue(const AliasText, Key: string): string;
var
  LineEnd : Integer;
  Prefix  : string;
  StartAt : Integer;
begin
  Result := '';
  Prefix := Key + '=';
  StartAt := Pos(Prefix, AliasText);
  while StartAt > 0 do
  begin
    if (StartAt = 1) or CharInSet(AliasText[StartAt - 1], [#10, #13]) then
    begin
      Inc(StartAt, Length(Prefix));
      LineEnd := StartAt;
      while (LineEnd <= Length(AliasText)) and
        not CharInSet(AliasText[LineEnd], [#10, #13]) do
        Inc(LineEnd);
      Exit(Trim(Copy(AliasText, StartAt, LineEnd - StartAt)));
    end;
    StartAt := PosEx(Prefix, AliasText, StartAt + Length(Prefix));
  end;
end;

function ExtractMaterialPath(const AliasText: string): string;
begin
  Result := ExtractAliasValue(AliasText, FILE_KEY);
end;

function ExtractEffectDetails(const AliasText: string):
  TArray<TAul2MIRAIEffectDetail>;
var
  CurrentEffect : Integer;
  Detail        : TAul2MIRAIEffectDetail;
  EffectCount   : Integer;
  EqualsAt      : Integer;
  Line          : string;
  Lines         : TStringList;
  Parameter     : TAul2MIRAIParameterInfo;
  ParameterCount: Integer;
  Value         : string;
begin
  SetLength(Result, 0);
  Lines := TStringList.Create;
  try
    Lines.Text := AliasText;
    CurrentEffect := -1;
    EffectCount := 0;
    ParameterCount := 0;
    for Line in Lines do
    begin
      if (Line <> '') and (Line[1] = '[') then
      begin
        CurrentEffect := -1;
        Continue;
      end;

      if StartsText(EFFECT_KEY, Line) then
      begin
        if EffectCount >= MAX_EFFECT_COUNT then
          Break;
        Detail := Default(TAul2MIRAIEffectDetail);
        Detail.Name := Trim(Copy(Line, Length(EFFECT_KEY) + 1, MaxInt));
        SetLength(Result, EffectCount + 1);
        Result[EffectCount] := Detail;
        CurrentEffect := EffectCount;
        Inc(EffectCount);
        Continue;
      end;

      if (CurrentEffect < 0) or (ParameterCount >= MAX_PARAMETER_COUNT) then
        Continue;
      EqualsAt := Pos('=', Line);
      if EqualsAt <= 1 then
        Continue;

      Parameter := Default(TAul2MIRAIParameterInfo);
      Parameter.Name := Copy(Line, 1, EqualsAt - 1);
      Value := Copy(Line, EqualsAt + 1, MaxInt);
      Parameter.Truncated := Length(Value) > MAX_PARAMETER_VALUE_CHARS;
      if Parameter.Truncated then
        SetLength(Value, MAX_PARAMETER_VALUE_CHARS);
      Parameter.Value := Value;

      Detail := Result[CurrentEffect];
      SetLength(Detail.Parameters, Length(Detail.Parameters) + 1);
      Detail.Parameters[High(Detail.Parameters)] := Parameter;
      Result[CurrentEffect] := Detail;
      Inc(ParameterCount);
    end;
  finally
    Lines.Free;
  end;
end;

function ParseEffectSectionHeader(const Line: string; out ObjectPrefix: string;
  out EffectIndex: Integer): Boolean;
var
  DotAt: Integer;
  Inner: string;
begin
  Result := False;
  ObjectPrefix := '';
  EffectIndex := -1;
  if (Length(Line) < 5) or (Line[1] <> '[') or
     (Line[Length(Line)] <> ']') then
    Exit;
  Inner := Copy(Line, 2, Length(Line) - 2);
  DotAt := LastDelimiter('.', Inner);
  if (DotAt <= 1) or (DotAt >= Length(Inner)) or
     not TryStrToInt(Copy(Inner, DotAt + 1, MaxInt), EffectIndex) or
     (EffectIndex < 0) then
    Exit;
  ObjectPrefix := Copy(Inner, 1, DotAt - 1);
  Result := ObjectPrefix <> '';
end;

function AppendRepeatedEffectBlock(const AliasText, EffectName: string;
  out ResultAlias, ErrorMessage: string): Boolean;
var
  BlockEffectName: string;
  BlockEnd       : Integer;
  BlockPrefix    : string;
  BlockStart     : Integer;
  EffectIndex    : Integer;
  I              : Integer;
  J              : Integer;
  MaxEffectIndex : Integer;
  ResultLines    : TStringList;
  SourceEnd      : Integer;
  SourcePrefix   : string;
  SourceStart    : Integer;
  Lines          : TStringList;
begin
  Result := False;
  ResultAlias := '';
  ErrorMessage := '';
  if Trim(EffectName) = '' then
  begin
    ErrorMessage := 'repeat_effect must not be empty.';
    Exit;
  end;
  Lines := TStringList.Create;
  ResultLines := TStringList.Create;
  try
    Lines.Text := AliasText;
    SourceStart := -1;
    SourceEnd := -1;
    SourcePrefix := '';
    MaxEffectIndex := -1;
    I := 0;
    while I < Lines.Count do
    begin
      if not ParseEffectSectionHeader(Lines[I], BlockPrefix,
        EffectIndex) then
      begin
        Inc(I);
        Continue;
      end;
      BlockStart := I;
      BlockEnd := I + 1;
      while (BlockEnd < Lines.Count) and
        not ((Lines[BlockEnd] <> '') and (Lines[BlockEnd][1] = '[')) do
        Inc(BlockEnd);
      if EffectIndex > MaxEffectIndex then
        MaxEffectIndex := EffectIndex;
      BlockEffectName := '';
      for J := BlockStart + 1 to BlockEnd - 1 do
        if StartsText(EFFECT_KEY, Lines[J]) then
        begin
          BlockEffectName := Trim(Copy(Lines[J], Length(EFFECT_KEY) + 1,
            MaxInt));
          Break;
        end;
      if BlockEffectName = EffectName then
      begin
        SourceStart := BlockStart;
        SourceEnd := BlockEnd;
        SourcePrefix := BlockPrefix;
      end;
      I := BlockEnd;
    end;
    if SourceStart < 0 then
    begin
      ErrorMessage := 'The requested repeat_effect was not found in the alias.';
      Exit;
    end;
    if MaxEffectIndex >= High(Integer) then
    begin
      ErrorMessage := 'The alias effect index cannot be extended.';
      Exit;
    end;

    ResultLines.Assign(Lines);
    ResultLines.Add(Format('[%s.%d]', [SourcePrefix, MaxEffectIndex + 1]));
    for I := SourceStart + 1 to SourceEnd - 1 do
      ResultLines.Add(Lines[I]);
    ResultAlias := ResultLines.Text;
    Result := True;
  finally
    ResultLines.Free;
    Lines.Free;
  end;
end;

end.
