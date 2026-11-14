program ObjectEditCheck;

// SDKを模した編集境界で、対象再検証、削除バッチ、名前復旧と要求検証を確認する。
{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils,
  AviUtl2PluginTypes,
  Aul2MIRAIObjectTypes,
  Aul2MIRAIObjectReader,
  Aul2MIRAIObjectEdit,
  Aul2MIRAIObjectEditor;

type
  TFakeObject = record
    Name    : string;     // カスタム名
    Alias   : UTF8String; // SDKから返すエイリアス
    Layer   : Integer;    // 対象の配置
    Selected: Boolean;    // 編集対象として選択されているか
    Alive   : Boolean;    // 削除済みハンドルを返さないための状態
  end;
  PFakeObject = ^TFakeObject;

var
  Objects: array[0..1] of TFakeObject;
  Section: TEditSection;
  Edit   : TEditHandle;
  Calls, Writes, Deletes, IgnoreDeleteLayer: Integer;
  RejectName, Locked: Boolean;

procedure Require(Condition: Boolean; const MessageText: string);
begin
  if not Condition then raise Exception.Create(MessageText);
end;

function FindObject(Layer, Frame: Integer): TObjectHandle; cdecl;
begin
  Result := nil;
  for var I := 0 to High(Objects) do
    if Objects[I].Alive and (Objects[I].Layer = Layer) and (Frame <= 20) then
      Exit(@Objects[I]);
end;

function GetPosition(Obj: TObjectHandle): TObjectLayerFrame; cdecl;
begin
  Result.Layer := PFakeObject(Obj).Layer;
  Result.StartFrame := 0;
  Result.EndFrame := 20;
end;

function GetAlias(Obj: TObjectHandle): LPCSTR; cdecl;
begin
  Result := PAnsiChar(PFakeObject(Obj).Alias);
end;

function GetName(Obj: TObjectHandle): LPCWSTR; cdecl;
begin
  Result := PWideChar(PFakeObject(Obj).Name);
end;

procedure SetName(Obj: TObjectHandle; Name: LPCWSTR); cdecl;
begin
  Inc(Writes);
  if RejectName and (string(Name) <> 'before') then Exit;
  PFakeObject(Obj).Name := string(Name);
  PFakeObject(Obj).Alias := UTF8String('[0]' + #13#10 + 'name=' + string(Name) + #13#10 +
    '[0.0]' + #13#10 + 'effect.name=図形' + #13#10 + 'サイズ=100' + #13#10);
end;

procedure DeleteObject(Obj: TObjectHandle); cdecl;
begin
  Inc(Deletes);
  if PFakeObject(Obj).Layer <> IgnoreDeleteLayer then PFakeObject(Obj).Alive := False;
end;

function SelectedCount: Integer; cdecl;
begin
  Result := 0;
  for var Obj in Objects do
    if Obj.Alive and Obj.Selected then Inc(Result);
end;

function SelectedObject(Index: Integer): TObjectHandle; cdecl;
begin
  Result := nil;
  for var I := 0 to High(Objects) do
    if Objects[I].Alive and Objects[I].Selected then
    begin
      if Index = 0 then Exit(@Objects[I]);
      Dec(Index);
    end;
end;

function FocusObject: TObjectHandle; cdecl;
begin
  Result := SelectedObject(0);
end;

function LayerLocked(Layer: Integer): BOOL; cdecl;
begin
  Result := Locked;
end;

function EditSection(Param: Pointer; Callback: TProcEditSectionParam): BOOL; cdecl;
begin
  Inc(Calls);
  Callback(Param, @Section);
  Result := True;
end;

procedure Reset;
begin
  Calls := 0;
  Writes := 0;
  Deletes := 0;
  IgnoreDeleteLayer := -1;
  RejectName := False;
  Locked := False;
  for var I := 0 to High(Objects) do
  begin
    Objects[I].Layer := I;
    Objects[I].Alive := True;
    Objects[I].Selected := True;
    SetName(@Objects[I], 'before');
  end;
  Writes := 0;
end;

function Snapshot: TAul2MIRAISceneSnapshot;
begin
  Result := Default(TAul2MIRAISceneSnapshot);
  SetLength(Result.Objects, SelectedCount);
  var Count := 0;
  for var I := 0 to High(Objects) do
    if Objects[I].Alive then
    begin
      SetLength(Result.Objects, Count + 1);
      var MessageText := '';
      Require(ReadObjectSnapshot(@Section, @Objects[I], False, False,
        Result.Objects[Count], MessageText), MessageText);
      Result.Objects[Count].Index := Count;
      Result.Objects[Count].Selected := Objects[I].Selected;
      Inc(Count);
    end;
end;

procedure CheckRequests;
var
  Request: TMIRAIObjectEditRequest;
  Token, Code, MessageText, Prefix: string;
begin
  Prefix := '{"state_token":"sha256:' + StringOfChar('a', 64) + '",';
  Require(ParseObjectEditRequest(Prefix + '"target_index":0,"name":"日本語","apply":true}',
    False, True, Token, Request, Code, MessageText), MessageText);
  Require(Request.NewName = '日本語', 'Japanese name lost');
  Require(ParseObjectEditRequest(Prefix + '"target_index":0,"name":""}',
    False, False, Token, Request, Code, MessageText), 'Empty name reset rejected');
  Require(not ParseObjectEditRequest(Prefix + '"target_index":0,"name":"bad\u0000name"}',
    False, False, Token, Request, Code, MessageText), 'Embedded NUL accepted');
  Require(not ParseObjectEditRequest(Prefix + '"target_index":0,"name":7}',
    False, False, Token, Request, Code, MessageText), 'Non-string name accepted');
  Require(not ParseObjectEditRequest(Prefix + '"target_index":0,"name":"x"}',
    False, True, Token, Request, Code, MessageText), 'Missing apply accepted');
  for var S in ['[]', '[0,0]', '[-1]', '[0.5]', '["0"]'] do
    Require(not ParseObjectEditRequest(Prefix + '"target_indices":' + S + '}',
      True, False, Token, Request, Code, MessageText), 'Invalid targets accepted: ' + S);
  Require(ParseObjectEditRequest(Prefix + '"target_indices":[0,1],"apply":true}',
    True, True, Token, Request, Code, MessageText), MessageText);
  var Indices := '';
  for var I := 0 to 63 do
  begin
    if I > 0 then Indices := Indices + ',';
    Indices := Indices + IntToStr(I);
  end;
  Require(ParseObjectEditRequest(Prefix + '"target_indices":[' + Indices + ']}',
    True, False, Token, Request, Code, MessageText), '64 targets rejected');
  Require(not ParseObjectEditRequest(Prefix + '"target_indices":[' + Indices + ',64]}',
    True, False, Token, Request, Code, MessageText), '65 targets accepted');
  Require(not ParseObjectEditRequest(Prefix + '"target_index":0,"name":"' + StringOfChar('x', 1025) + '"}',
    False, False, Token, Request, Code, MessageText), 'Oversized name accepted');
end;

procedure CheckEdits;
var
  Request: TMIRAIObjectEditRequest;
  Preview: TMIRAIObjectEditPreview;
  Before, After: TAul2MIRAISceneSnapshot;
  Code, MessageText: string;
  Completed: Integer;
begin
  Reset;
  Request := Default(TMIRAIObjectEditRequest);
  Request.TargetIndices := [0];
  Request.NewName := '日本語の名前';
  Before := Snapshot;
  Require(CreateObjectEditPreview(Before, Request, Preview, Code, MessageText), MessageText);
  Require(ApplyObjectEdit(@Edit, Preview, Completed, Code, MessageText), MessageText);
  After := Snapshot;
  Require(VerifyObjectEdit(Before, After, Preview, MessageText), MessageText);
  Require((Calls = 1) and (Writes = 1) and (Completed = 1), 'Rename callback/count incorrect');
  Request.NewName := '';
  Require(CreateObjectEditPreview(After, Request, Preview, Code, MessageText), MessageText);
  Require(ApplyObjectEdit(@Edit, Preview, Completed, Code, MessageText), MessageText);
  Require(Objects[0].Name = '', 'Default name reset failed');
  Before := Snapshot;
  Require(CreateObjectEditPreview(Before, Request, Preview, Code, MessageText), MessageText);
  Require(not Preview.WillChange, 'Same name is not a no-op');
  var BeforeWrites := Writes;
  Require(ApplyObjectEdit(@Edit, Preview, Completed, Code, MessageText), MessageText);
  Require((Completed = 0) and (Writes = BeforeWrites), 'No-op performed a write');

  Reset;
  Before := Snapshot;
  Request.NewName := 'after';
  Require(CreateObjectEditPreview(Before, Request, Preview, Code, MessageText), MessageText);
  Objects[0].Selected := False;
  Require(not ApplyObjectEdit(@Edit, Preview, Completed, Code, MessageText), 'Deselected target edited');
  Require(Writes = 0, 'Deselected target mutated');
  Objects[0].Selected := True;
  SetName(@Objects[0], 'changed');
  Writes := 0;
  Require(not ApplyObjectEdit(@Edit, Preview, Completed, Code, MessageText), 'Stale name accepted');
  Require(Writes = 0, 'Stale target mutated');
  Reset;
  Locked := True;
  Require(not ApplyObjectEdit(@Edit, Preview, Completed, Code, MessageText), 'Locked target edited');
  Require(Writes = 0, 'Locked target mutated');
  Locked := False;
  RejectName := True;
  Require(not ApplyObjectEdit(@Edit, Preview, Completed, Code, MessageText), 'Rejected rename succeeded');
  Require((Objects[0].Name = 'before') and (Code = 'name_verification_failed'), 'Rename restoration failed');

  Reset;
  Request.DeleteObjects := True;
  Request.TargetIndices := [0, 1];
  Before := Snapshot;
  Require(CreateObjectEditPreview(Before, Request, Preview, Code, MessageText), MessageText);
  Objects[1].Selected := False;
  Require(not ApplyObjectEdit(@Edit, Preview, Completed, Code, MessageText), 'Changed batch target accepted');
  Require(Deletes = 0, 'Batch partially deleted before validation completed');
  Objects[1].Selected := True;
  Calls := 0;
  Require(ApplyObjectEdit(@Edit, Preview, Completed, Code, MessageText), MessageText);
  After := Snapshot;
  Require(VerifyObjectEdit(Before, After, Preview, MessageText), MessageText);
  Require((Calls = 1) and (Completed = 2) and (Deletes = 2), 'Batch not in one edit section');
  Reset;
  IgnoreDeleteLayer := 1;
  Require(not ApplyObjectEdit(@Edit, Preview, Completed, Code, MessageText), 'Ignored deletion succeeded');
  Require((Completed = 1) and MessageText.Contains('Undo'), 'Partial deletion not reported');

  Reset;
  Before := Snapshot;
  Request.TargetIndices := [0];
  Require(CreateObjectEditPreview(Before, Request, Preview, Code, MessageText), MessageText);
  Require(ApplyObjectEdit(@Edit, Preview, Completed, Code, MessageText), MessageText);
  Objects[1].Name := 'unexpected';
  After := Snapshot;
  Require(not VerifyObjectEdit(Before, After, Preview, MessageText), 'Unrelated change went undetected');
end;

begin
  try
    Section.FindObject := FindObject;
    Section.GetObjectLayerFrame := GetPosition;
    Section.GetObjectAlias := GetAlias;
    Section.GetObjectName := GetName;
    Section.SetObjectName := SetName;
    Section.DeleteObject := DeleteObject;
    Section.GetSelectedObjectNum := SelectedCount;
    Section.GetSelectedObject := SelectedObject;
    Section.GetFocusObject := FocusObject;
    Section.GetLayerLock := LayerLocked;
    Edit.CallEditSectionParam := EditSection;
    CheckRequests;
    CheckEdits;
    Writeln('PASS: request validation, rename/reset/rollback, stale/selection/lock checks, batch delete and verification');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
