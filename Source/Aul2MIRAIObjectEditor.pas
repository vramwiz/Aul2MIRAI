unit Aul2MIRAIObjectEditor;

// 表示名変更と削除を1回のSDK編集コールバック内で再検証して実行する。
interface

uses
  AviUtl2PluginTypes,
  Aul2MIRAIObjectEdit;

// 全対象を事前検証する。削除途中のSDK失敗時は完了件数を返し、Undoによる復旧を案内する。
function ApplyObjectEdit(EditHandle: PEditHandle; const Preview: TMIRAIObjectEditPreview;
  out CompletedCount: Integer; out ErrorCode, ErrorMessage: string): Boolean;

implementation

uses
  System.SysUtils,
  Aul2MIRAIObjectAlias,
  Aul2MIRAIObjectReader,
  Aul2MIRAIObjectTypes,
  Aul2MIRAISelection;

type
  TObjectEditContext = class
  public
    Preview       : TMIRAIObjectEditPreview; // ポインターを含まない変更予定
    CompletedCount: Integer;                // SDKで検証済みの完了件数
    ErrorCode     : string;                 // 失敗理由の識別子
    ErrorMessage  : string;                 // 部分完了時の復旧案内を含む説明
  end;

function AliasWithoutName(const Text: string): string;
var
  Line     : string;  // エイリアスの1行
  InEffects: Boolean; // エフェクト設定内のnameは除外しない
begin
  Result := '';
  InEffects := False;
  for Line in Text.Replace(#13, '').Split([#10]) do
  begin
    if Line.StartsWith('[') and Line.Contains('.') then InEffects := True;
    if not InEffects and Line.StartsWith('name=') then Continue;
    Result := Result + Line + #10;
  end;
end;

function ResolveTarget(Edit: PEditSection; const Expected: TAul2MIRAIObjectInfo;
  const Selected: TObjectHandleArray; out Obj: TObjectHandle; out MessageText: string): Boolean;
var
  Current: TAul2MIRAIObjectInfo; // SDK編集直前の実体
begin
  Result := False;
  Obj := Edit^.FindObject(Expected.Layer, Expected.StartFrame);
  MessageText := 'The target object is no longer selected.';
  if (Obj = nil) or not ContainsObjectHandle(Selected, Obj) then Exit;
  if not ReadObjectSnapshot(Edit, Obj, False, False, Current, MessageText) then Exit;
  MessageText := 'The target object changed before the edit.';
  if (Current.Layer <> Expected.Layer) or (Current.StartFrame <> Expected.StartFrame) or
    (Current.EndFrame <> Expected.EndFrame) or (Current.ContentDigest <> Expected.ContentDigest) or
    (Current.Name <> Expected.Name) then Exit;
  MessageText := 'The target layer became locked.';
  if Assigned(Edit^.GetLayerLock) and Edit^.GetLayerLock(Current.Layer) then Exit;
  MessageText := '';
  Result := True;
end;

procedure RenameObject(Context: TObjectEditContext; Edit: PEditSection; Obj: TObjectHandle);
var
  BeforeAlias, AfterAlias: string; // 名前以外の全エイリアス内容の比較
  NameChanged           : Boolean; // 失敗時に元の名前へ戻す必要があるか
begin
  BeforeAlias := CopyUtf8Text(Edit^.GetObjectAlias(Obj));
  NameChanged := False;
  try
    NameChanged := True;
    Edit^.SetObjectName(Obj, PWideChar(Context.Preview.Request.NewName));
    AfterAlias := CopyUtf8Text(Edit^.GetObjectAlias(Obj));
    if (string(Edit^.GetObjectName(Obj)) <> Context.Preview.Request.NewName) or
      (AliasWithoutName(BeforeAlias) <> AliasWithoutName(AfterAlias)) then
      raise Exception.Create('The name or object content did not match after renaming.');
    Context.CompletedCount := 1;
  except
    on E: Exception do
    begin
      Context.ErrorCode := 'name_verification_failed';
      Context.ErrorMessage := E.ClassName + ': ' + E.Message;
      if NameChanged then
      begin
        try
          Edit^.SetObjectName(Obj, PWideChar(Context.Preview.Targets[0].Name));
          if (string(Edit^.GetObjectName(Obj)) <> Context.Preview.Targets[0].Name) or
            (CopyUtf8Text(Edit^.GetObjectAlias(Obj)) <> BeforeAlias) then
            raise Exception.Create('The original object could not be verified.');
        except
          Context.ErrorCode := 'name_rollback_failed';
          Context.ErrorMessage := Context.ErrorMessage + ' Restore the original object with Undo.';
        end;
      end;
    end;
  end;
end;

procedure EditObjectsCallback(Param: Pointer; Edit: PEditSection); cdecl;
var
  Context : TObjectEditContext; // 呼出し元が所有する実行状態
  Selected: TObjectHandleArray; // 編集開始時の選択状態
  Focus, Obj, Remaining: TObjectHandle; // コールバック内だけで有効なハンドル
  Position: TObjectLayerFrame; // 削除後に同じ位置のオブジェクトが残っていないか
  I       : Integer;          // 対象の実行順
begin
  Context := TObjectEditContext(Param);
  if Context = nil then Exit;
  try
    Context.ErrorCode := 'edit_unavailable';
    Context.ErrorMessage := 'The required AviUtl2 object editing API is unavailable.';
    if (Edit = nil) or not Assigned(Edit^.FindObject) or not Assigned(Edit^.GetObjectLayerFrame) or
      not Assigned(Edit^.GetObjectAlias) or not Assigned(Edit^.GetObjectName) then Exit;
    if Context.Preview.Request.DeleteObjects then
    begin
      if not Assigned(Edit^.DeleteObject) then Exit;
    end
    else if not Assigned(Edit^.SetObjectName) then Exit;
    Context.ErrorCode := 'selection_read_failed';
    if not ReadSelectedObjectHandles(Edit, Selected, Focus, Context.ErrorMessage) then Exit;
    Context.ErrorCode := 'target_changed';
    // 途中の対象不一致で先頭だけを削除しないよう、まず全件を確認する。
    for I := 0 to High(Context.Preview.Targets) do
      if not ResolveTarget(Edit, Context.Preview.Targets[I], Selected, Obj, Context.ErrorMessage) then Exit;
    Context.ErrorCode := '';
    Context.ErrorMessage := '';
    if not Context.Preview.WillChange then Exit;
    if not Context.Preview.Request.DeleteObjects then
    begin
      RenameObject(Context, Edit, Obj);
      Exit;
    end;
    for I := 0 to High(Context.Preview.Targets) do
    begin
      // 削除に伴うSDK内部の関連変更があっても古いハンドルを再利用しない。
      if not ResolveTarget(Edit, Context.Preview.Targets[I], Selected, Obj, Context.ErrorMessage) then
      begin
        Context.ErrorCode := 'target_changed';
        Exit;
      end;
      Edit^.DeleteObject(Obj);
      Remaining := Edit^.FindObject(Context.Preview.Targets[I].Layer, Context.Preview.Targets[I].StartFrame);
      if Remaining <> nil then
      begin
        Position := Edit^.GetObjectLayerFrame(Remaining);
        if (Position.Layer = Context.Preview.Targets[I].Layer) and
          (Position.StartFrame = Context.Preview.Targets[I].StartFrame) then
        begin
          Context.ErrorCode := 'delete_verification_failed';
          Context.ErrorMessage := 'AviUtl2 did not delete the requested object.';
          Exit;
        end;
      end;
      Inc(Context.CompletedCount);
    end;
  except
    on E: Exception do
    begin
      Context.ErrorCode := 'object_edit_failed';
      Context.ErrorMessage := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

function ApplyObjectEdit(EditHandle: PEditHandle; const Preview: TMIRAIObjectEditPreview;
  out CompletedCount: Integer; out ErrorCode, ErrorMessage: string): Boolean;
var
  Context: TObjectEditContext; // 同期SDK呼出しの間だけ保持する状態
begin
  Result := False;
  CompletedCount := 0;
  ErrorCode := 'edit_unavailable';
  ErrorMessage := 'AviUtl2 edit section is unavailable.';
  if (EditHandle = nil) or not Assigned(EditHandle^.CallEditSectionParam) then Exit;
  Context := TObjectEditContext.Create;
  try
    Context.Preview := Preview;
    if not EditHandle^.CallEditSectionParam(Context, @EditObjectsCallback) then
    begin
      if Context.ErrorCode = '' then
      begin
        Context.ErrorCode := 'edit_rejected';
        Context.ErrorMessage := 'AviUtl2 rejected the edit request.';
      end;
    end;
    CompletedCount := Context.CompletedCount;
    ErrorCode := Context.ErrorCode;
    ErrorMessage := Context.ErrorMessage;
    if (ErrorCode <> '') and Preview.Request.DeleteObjects then
      ErrorMessage := ErrorMessage + Format(
        ' Verified deletions: %d. Changes may remain; reacquire state and use Undo to recover.', [CompletedCount]);
    Result := ErrorCode = '';
  finally
    Context.Free;
  end;
end;

end.
