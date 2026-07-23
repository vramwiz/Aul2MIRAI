unit Aul2MIRAICommand;

// 外部要求を検証し、読み取り処理、JSON応答、画面通知を接続する。

interface

function HandleAul2MIRAIRequest(const RequestText: string): string;

implementation

uses
  System.SysUtils,
  AviUtl2PluginCore,
  Aul2MIRAIEditPosition,
  Aul2MIRAIEditPositionWriter,
  Aul2MIRAIEditStateReader,
  Aul2MIRAIEditStateTypes,
  Aul2MIRAIFrameCapture,
  Aul2MIRAIObjectFormat,
  Aul2MIRAIObjectDuplicate,
  Aul2MIRAIObjectDuplicator,
  Aul2MIRAIObjectFocus,
  Aul2MIRAIObjectFocuser,
  Aul2MIRAIObjectMove,
  Aul2MIRAIObjectMover,
  Aul2MIRAIObjectQuery,
  Aul2MIRAIObjectReader,
  Aul2MIRAIObjectTypes,
  Aul2MIRAIParameterBatch,
  Aul2MIRAIParameterPreview,
  Aul2MIRAIParameterWriter,
  Aul2MIRAIProtocol,
  Aul2MIRAISnapshotIdentity,
  Aul2MIRAIView;

function HandleObjectFocusRequest(const RequestText,
  Command: string): string;
var
  AfterEditState : TAul2MIRAIEditState;
  AfterIdentity  : TAul2MIRAISnapshotIdentity;
  AfterSnapshot  : TAul2MIRAISceneSnapshot;
  BeforeIdentity : TAul2MIRAISnapshotIdentity;
  EditState      : TAul2MIRAIEditState;
  ErrorCode      : string;
  ErrorMessage   : string;
  Item           : TAul2MIRAIObjectInfo;
  Preview        : TAul2MIRAIObjectFocusPreview;
  RequireApply   : Boolean;
  Snapshot       : TAul2MIRAISceneSnapshot;
  StateToken     : string;
  TargetIndex    : Integer;
  Verified       : Boolean;
begin
  RequireApply := SameText(Command, AUL2MIRAI_COMMAND_SET_FOCUS_OBJECT);
  if not ParseObjectFocusRequest(RequestText, RequireApply, StateToken,
    TargetIndex, ErrorCode, ErrorMessage) then
  begin
    QueueMIRAIViewUpdate('External focus request rejected', '', 'WARN',
      ErrorCode + ': ' + ErrorMessage);
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  end;
  if not ReadCurrentEditState(EditHandle, EditState, ErrorMessage) then
    Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
  if not ReadCurrentSceneObjects(EditHandle, Snapshot, ErrorMessage) then
    Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
  BeforeIdentity := CreateSnapshotIdentity(EditState, Snapshot);
  if not SameText(StateToken, BeforeIdentity.StateToken) then
  begin
    QueueMIRAIViewUpdate('External focus rejected - state changed', '',
      'WARN', Command + ': state_changed');
    Exit(BuildStateChangedError(Command, StateToken, BeforeIdentity));
  end;
  if not CreateObjectFocusPreview(Snapshot, TargetIndex, Preview,
    ErrorCode, ErrorMessage) then
  begin
    QueueMIRAIViewUpdate('External focus request rejected', '', 'WARN',
      ErrorCode + ': ' + ErrorMessage);
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  end;
  if not RequireApply then
  begin
    QueueMIRAIViewUpdate('Object focus preview', '', 'OK',
      Format('%s -> object %d', [Command, TargetIndex]));
    Exit(BuildObjectFocusPreviewResponse(Preview, BeforeIdentity));
  end;
  if not Preview.WillChange then
  begin
    QueueMIRAIViewUpdate('Object focus skipped - unchanged', '', 'OK',
      Format('%s -> object %d', [Command, TargetIndex]));
    Exit(BuildObjectFocusResponse(Preview, BeforeIdentity,
      BeforeIdentity));
  end;
  if not ApplyObjectFocus(EditHandle, Preview, ErrorCode,
    ErrorMessage) then
  begin
    QueueMIRAIViewUpdate('External focus change failed', '', 'ERROR',
      ErrorCode + ': ' + ErrorMessage);
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  end;
  if not ReadCurrentEditState(EditHandle, AfterEditState,
    ErrorMessage) then
    Exit(BuildProtocolError(Command, 'post_write_read_failed',
      ErrorMessage));
  if not ReadCurrentSceneObjects(EditHandle, AfterSnapshot,
    ErrorMessage) then
    Exit(BuildProtocolError(Command, 'post_write_read_failed',
      ErrorMessage));
  Verified := False;
  for Item in AfterSnapshot.Objects do
    if Item.Index = Preview.Target.Index then
    begin
      Verified := Item.Focused and
        (Item.Layer = Preview.Target.Layer) and
        (Item.StartFrame = Preview.Target.StartFrame) and
        (Item.EndFrame = Preview.Target.EndFrame) and
        SameText(Item.ContentDigest, Preview.Target.ContentDigest);
      Break;
    end;
  if not Verified then
  begin
    ErrorMessage :=
      'The focused object read after the change did not match the request.';
    Exit(BuildProtocolError(Command, 'post_write_verification_failed',
      ErrorMessage));
  end;
  AfterIdentity := CreateSnapshotIdentity(AfterEditState, AfterSnapshot);
  QueueMIRAIViewUpdate('Object focus changed', '', 'OK',
    Format('%s -> object %d', [Command, TargetIndex]));
  Result := BuildObjectFocusResponse(Preview, BeforeIdentity,
    AfterIdentity);
end;

function HandleEditPositionRequest(const RequestText,
  Command: string): string;
var
  AfterEditState : TAul2MIRAIEditState;
  AfterIdentity  : TAul2MIRAISnapshotIdentity;
  AfterSnapshot  : TAul2MIRAISceneSnapshot;
  BeforeIdentity : TAul2MIRAISnapshotIdentity;
  CursorFrame    : Integer;
  CursorLayer    : Integer;
  EditState      : TAul2MIRAIEditState;
  ErrorCode      : string;
  ErrorMessage   : string;
  Preview        : TAul2MIRAIEditPositionPreview;
  RequireApply   : Boolean;
  SelectEnd      : Integer;
  SelectStart    : Integer;
  SetCursor      : Boolean;
  SetSelection   : Boolean;
  Snapshot       : TAul2MIRAISceneSnapshot;
  StateToken     : string;
begin
  RequireApply := SameText(Command, AUL2MIRAI_COMMAND_SET_EDIT_POSITION);
  if not ParseEditPositionRequest(RequestText, RequireApply, StateToken,
    SetCursor, CursorLayer, CursorFrame, SetSelection, SelectStart,
    SelectEnd, ErrorCode, ErrorMessage) then
  begin
    QueueMIRAIViewUpdate('External position request rejected', '',
      'WARN', ErrorCode + ': ' + ErrorMessage);
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  end;
  if not ReadCurrentEditState(EditHandle, EditState, ErrorMessage) then
    Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
  if not ReadCurrentSceneObjects(EditHandle, Snapshot, ErrorMessage) then
    Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
  BeforeIdentity := CreateSnapshotIdentity(EditState, Snapshot);
  if not SameText(StateToken, BeforeIdentity.StateToken) then
  begin
    QueueMIRAIViewUpdate('External position rejected - state changed', '',
      'WARN', Command + ': state_changed');
    Exit(BuildStateChangedError(Command, StateToken, BeforeIdentity));
  end;
  if not CreateEditPositionPreview(EditState, SetCursor, CursorLayer,
    CursorFrame, SetSelection, SelectStart, SelectEnd, Preview, ErrorCode,
    ErrorMessage) then
  begin
    QueueMIRAIViewUpdate('External position request rejected', '',
      'WARN', ErrorCode + ': ' + ErrorMessage);
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  end;
  if not RequireApply then
  begin
    QueueMIRAIViewUpdate('Edit position preview', '', 'OK',
      Format('%s -> cursor %d:%d, selection %d-%d',
        [Command, Preview.AfterCursorLayer, Preview.AfterCursorFrame,
         Preview.AfterSelectStart, Preview.AfterSelectEnd]));
    Exit(BuildEditPositionPreviewResponse(Preview, BeforeIdentity));
  end;
  if not Preview.CursorWillChange and
     not Preview.SelectionWillChange then
  begin
    QueueMIRAIViewUpdate('Edit position skipped - unchanged', '', 'OK',
      Format('%s -> no change', [Command]));
    Exit(BuildEditPositionResponse(Preview, BeforeIdentity,
      BeforeIdentity));
  end;
  if not ApplyEditPosition(EditHandle, Preview, ErrorCode,
    ErrorMessage) then
  begin
    QueueMIRAIViewUpdate('External position change failed', '', 'ERROR',
      ErrorCode + ': ' + ErrorMessage);
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  end;
  if not ReadCurrentEditState(EditHandle, AfterEditState,
    ErrorMessage) then
    Exit(BuildProtocolError(Command, 'post_write_read_failed',
      ErrorMessage));
  if not ReadCurrentSceneObjects(EditHandle, AfterSnapshot,
    ErrorMessage) then
    Exit(BuildProtocolError(Command, 'post_write_read_failed',
      ErrorMessage));
  if (Preview.SetCursor and
      ((AfterEditState.CursorLayer <> Preview.AfterCursorLayer) or
       (AfterEditState.CursorFrame <> Preview.AfterCursorFrame))) or
     (Preview.SetSelection and
      ((AfterEditState.SelectRangeStart <> Preview.AfterSelectStart) or
       (AfterEditState.SelectRangeEnd <> Preview.AfterSelectEnd))) then
  begin
    ErrorMessage :=
      'The edit position read after the change did not match the request.';
    Exit(BuildProtocolError(Command, 'post_write_verification_failed',
      ErrorMessage));
  end;
  AfterIdentity := CreateSnapshotIdentity(AfterEditState, AfterSnapshot);
  QueueMIRAIViewUpdate('Edit position changed', '', 'OK',
    Format('%s -> cursor %d:%d, selection %d-%d',
      [Command, AfterEditState.CursorLayer, AfterEditState.CursorFrame,
       AfterEditState.SelectRangeStart, AfterEditState.SelectRangeEnd]));
  Result := BuildEditPositionResponse(Preview, BeforeIdentity,
    AfterIdentity);
end;

function HandleObjectDuplicateRequest(const RequestText,
  Command: string): string;
var
  AfterEditState : TAul2MIRAIEditState;
  AfterIdentity  : TAul2MIRAISnapshotIdentity;
  AfterSnapshot  : TAul2MIRAISceneSnapshot;
  BeforeIdentity : TAul2MIRAISnapshotIdentity;
  CreatedIndices : TArray<Integer>;
  Duplicates     : TArray<TAul2MIRAIObjectDuplicateRequest>;
  EditState      : TAul2MIRAIEditState;
  ErrorCode      : string;
  ErrorMessage   : string;
  Previews       : TArray<TAul2MIRAIObjectDuplicatePreview>;
  RequireApply   : Boolean;
  Snapshot       : TAul2MIRAISceneSnapshot;
  StateToken     : string;
begin
  RequireApply := SameText(Command, AUL2MIRAI_COMMAND_DUPLICATE_OBJECTS);
  if not ParseObjectDuplicateRequest(RequestText, RequireApply, StateToken,
    Duplicates, ErrorCode, ErrorMessage) then
  begin
    QueueMIRAIViewUpdate('External duplicate request rejected', '',
      'WARN', ErrorCode + ': ' + ErrorMessage);
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  end;
  if not ReadCurrentEditState(EditHandle, EditState, ErrorMessage) then
    Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
  if not ReadCurrentSceneObjects(EditHandle, Snapshot, ErrorMessage) then
    Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
  BeforeIdentity := CreateSnapshotIdentity(EditState, Snapshot);
  if not SameText(StateToken, BeforeIdentity.StateToken) then
  begin
    QueueMIRAIViewUpdate('External duplicate rejected - state changed', '',
      'WARN', Command + ': state_changed');
    Exit(BuildStateChangedError(Command, StateToken, BeforeIdentity));
  end;
  if not CreateObjectDuplicatePreviews(Snapshot, Duplicates, Previews,
    ErrorCode, ErrorMessage) then
  begin
    QueueMIRAIViewUpdate('External duplicate request rejected', '',
      'WARN', ErrorCode + ': ' + ErrorMessage);
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  end;
  if not RequireApply then
  begin
    QueueMIRAIViewUpdate(
      Format('Duplicate preview - %d objects', [Length(Previews)]),
      '', 'OK', Format('%s -> %d objects',
        [Command, Length(Previews)]));
    Exit(BuildObjectDuplicatePreviewResponse(Previews, BeforeIdentity));
  end;

  if not ApplyObjectDuplicates(EditHandle, Previews, ErrorCode,
    ErrorMessage) then
  begin
    QueueMIRAIViewUpdate('External duplicate failed', '', 'ERROR',
      ErrorCode + ': ' + ErrorMessage);
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  end;
  if not ReadCurrentEditState(EditHandle, AfterEditState,
    ErrorMessage) then
  begin
    ErrorMessage := 'The duplication was applied, but the updated state ' +
      'could not be read: ' + ErrorMessage;
    Exit(BuildProtocolError(Command, 'post_write_read_failed',
      ErrorMessage));
  end;
  if not ReadCurrentSceneObjects(EditHandle, AfterSnapshot,
    ErrorMessage) then
  begin
    ErrorMessage := 'The duplication was applied, but the updated objects ' +
      'could not be read: ' + ErrorMessage;
    Exit(BuildProtocolError(Command, 'post_write_read_failed',
      ErrorMessage));
  end;
  if not ResolveCreatedObjectIndices(AfterSnapshot, Previews,
    CreatedIndices, ErrorMessage) then
  begin
    ErrorMessage := 'The duplication was applied, but verification failed: ' +
      ErrorMessage;
    Exit(BuildProtocolError(Command, 'post_write_verification_failed',
      ErrorMessage));
  end;
  AfterIdentity := CreateSnapshotIdentity(AfterEditState, AfterSnapshot);
  QueueMIRAIViewUpdate(
    Format('Duplicate applied - %d objects', [Length(Previews)]),
    '', 'OK', Format('%s -> %d objects created',
      [Command, Length(Previews)]));
  Result := BuildObjectDuplicateResponse(Previews, CreatedIndices,
    BeforeIdentity, AfterIdentity);
end;

function HandleObjectMoveRequest(const RequestText, Command: string): string;
var
  AfterEditState : TAul2MIRAIEditState;
  AfterIdentity  : TAul2MIRAISnapshotIdentity;
  AfterSnapshot  : TAul2MIRAISceneSnapshot;
  BeforeIdentity : TAul2MIRAISnapshotIdentity;
  EditState      : TAul2MIRAIEditState;
  ErrorCode      : string;
  ErrorMessage   : string;
  I              : Integer;
  MovedCount     : Integer;
  Moves          : TArray<TAul2MIRAIObjectMoveRequest>;
  Previews       : TArray<TAul2MIRAIObjectMovePreview>;
  RequireApply   : Boolean;
  Snapshot       : TAul2MIRAISceneSnapshot;
  StateToken     : string;
begin
  RequireApply := SameText(Command, AUL2MIRAI_COMMAND_MOVE_OBJECTS);
  if not ParseObjectMoveRequest(RequestText, RequireApply, StateToken,
    Moves, ErrorCode, ErrorMessage) then
  begin
    QueueMIRAIViewUpdate('External move request rejected', '', 'WARN',
      ErrorCode + ': ' + ErrorMessage);
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  end;
  if not ReadCurrentEditState(EditHandle, EditState, ErrorMessage) then
    Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
  if not ReadCurrentSceneObjects(EditHandle, Snapshot, ErrorMessage) then
    Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
  BeforeIdentity := CreateSnapshotIdentity(EditState, Snapshot);
  if not SameText(StateToken, BeforeIdentity.StateToken) then
  begin
    QueueMIRAIViewUpdate('External move rejected - state changed', '',
      'WARN', Command + ': state_changed');
    Exit(BuildStateChangedError(Command, StateToken, BeforeIdentity));
  end;
  if not CreateObjectMovePreviews(Snapshot, Moves, Previews, ErrorCode,
    ErrorMessage) then
  begin
    QueueMIRAIViewUpdate('External move request rejected', '', 'WARN',
      ErrorCode + ': ' + ErrorMessage);
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  end;

  MovedCount := 0;
  for I := 0 to High(Previews) do
    if Previews[I].WillMove then
      Inc(MovedCount);
  if not RequireApply then
  begin
    QueueMIRAIViewUpdate(
      Format('Move preview - %d objects, %d moves',
        [Length(Previews), MovedCount]), '', 'OK',
      Format('%s -> %d objects', [Command, Length(Previews)]));
    Exit(BuildObjectMovePreviewResponse(Previews, BeforeIdentity));
  end;

  if MovedCount = 0 then
  begin
    QueueMIRAIViewUpdate('Move skipped - all positions unchanged', '',
      'OK', Format('%s -> no move', [Command]));
    Exit(BuildObjectMoveResponse(Previews, BeforeIdentity,
      BeforeIdentity));
  end;
  if not ApplyObjectMoves(EditHandle, Previews, ErrorCode,
    ErrorMessage) then
  begin
    QueueMIRAIViewUpdate('External move failed', '', 'ERROR',
      ErrorCode + ': ' + ErrorMessage);
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  end;
  if not ReadCurrentEditState(EditHandle, AfterEditState,
    ErrorMessage) then
  begin
    ErrorMessage := 'The move was applied, but the updated state could ' +
      'not be read: ' + ErrorMessage;
    Exit(BuildProtocolError(Command, 'post_write_read_failed',
      ErrorMessage));
  end;
  if not ReadCurrentSceneObjects(EditHandle, AfterSnapshot,
    ErrorMessage) then
  begin
    ErrorMessage := 'The move was applied, but the updated objects could ' +
      'not be read: ' + ErrorMessage;
    Exit(BuildProtocolError(Command, 'post_write_read_failed',
      ErrorMessage));
  end;
  AfterIdentity := CreateSnapshotIdentity(AfterEditState, AfterSnapshot);
  QueueMIRAIViewUpdate(
    Format('Move applied - %d objects', [MovedCount]), '', 'OK',
    Format('%s -> %d objects moved', [Command, MovedCount]));
  Result := BuildObjectMoveResponse(Previews, BeforeIdentity,
    AfterIdentity);
end;

function HandleParameterBatchRequest(const RequestText,
  Command: string): string;
var
  AfterEditState : TAul2MIRAIEditState;
  AfterIdentity  : TAul2MIRAISnapshotIdentity;
  AfterSnapshot  : TAul2MIRAISceneSnapshot;
  BeforeIdentity : TAul2MIRAISnapshotIdentity;
  Changes        : TArray<TAul2MIRAIParameterChangeRequest>;
  ChangedCount   : Integer;
  EditState      : TAul2MIRAIEditState;
  ErrorCode      : string;
  ErrorMessage   : string;
  I              : Integer;
  Previews       : TArray<TAul2MIRAIParameterPreview>;
  RequireApply   : Boolean;
  Snapshot       : TAul2MIRAISceneSnapshot;
  StateToken     : string;
  VerifiedValues : TArray<string>;
begin
  RequireApply := SameText(Command, AUL2MIRAI_COMMAND_SET_PARAMETERS);
  if not ParseParameterBatchRequest(RequestText, RequireApply, StateToken,
    Changes, ErrorCode, ErrorMessage) then
  begin
    QueueMIRAIViewUpdate('External batch request rejected', '', 'WARN',
      ErrorCode + ': ' + ErrorMessage);
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  end;
  if not ReadCurrentEditState(EditHandle, EditState, ErrorMessage) then
    Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
  if not ReadCurrentSceneObjects(EditHandle, Snapshot, ErrorMessage,
    True) then
    Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
  BeforeIdentity := CreateSnapshotIdentity(EditState, Snapshot);
  if not SameText(StateToken, BeforeIdentity.StateToken) then
  begin
    QueueMIRAIViewUpdate('External batch rejected - state changed', '',
      'WARN', Command + ': state_changed');
    Exit(BuildStateChangedError(Command, StateToken, BeforeIdentity));
  end;
  if not CreateParameterPreviews(Snapshot, Changes, Previews, ErrorCode,
    ErrorMessage) then
  begin
    QueueMIRAIViewUpdate('External batch request rejected', '', 'WARN',
      ErrorCode + ': ' + ErrorMessage);
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  end;

  ChangedCount := 0;
  for I := 0 to High(Previews) do
    if Previews[I].WillChange then
      Inc(ChangedCount);
  if not RequireApply then
  begin
    QueueMIRAIViewUpdate(
      Format('Batch preview - %d items, %d changes',
        [Length(Previews), ChangedCount]), '', 'OK',
      Format('%s -> %d items', [Command, Length(Previews)]));
    Exit(BuildParameterBatchPreviewResponse(Previews, BeforeIdentity));
  end;

  if ChangedCount = 0 then
  begin
    SetLength(VerifiedValues, Length(Previews));
    for I := 0 to High(Previews) do
      VerifiedValues[I] := Previews[I].BeforeValue;
    QueueMIRAIViewUpdate('Batch edit skipped - all values unchanged', '',
      'OK', Format('%s -> no change', [Command]));
    Exit(BuildParameterBatchSetResponse(Previews, VerifiedValues,
      BeforeIdentity, BeforeIdentity));
  end;

  if not ApplyParameterChanges(EditHandle, Previews, VerifiedValues,
    ErrorCode, ErrorMessage) then
  begin
    QueueMIRAIViewUpdate('External batch edit failed', '', 'ERROR',
      ErrorCode + ': ' + ErrorMessage);
    Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
  end;
  if not ReadCurrentEditState(EditHandle, AfterEditState,
    ErrorMessage) then
  begin
    ErrorMessage := 'The batch edit was applied, but the updated state ' +
      'could not be read: ' + ErrorMessage;
    Exit(BuildProtocolError(Command, 'post_write_read_failed',
      ErrorMessage));
  end;
  if not ReadCurrentSceneObjects(EditHandle, AfterSnapshot,
    ErrorMessage) then
  begin
    ErrorMessage := 'The batch edit was applied, but the updated objects ' +
      'could not be read: ' + ErrorMessage;
    Exit(BuildProtocolError(Command, 'post_write_read_failed',
      ErrorMessage));
  end;
  AfterIdentity := CreateSnapshotIdentity(AfterEditState, AfterSnapshot);
  QueueMIRAIViewUpdate(
    Format('Batch edit applied - %d changes', [ChangedCount]), '', 'OK',
    Format('%s -> %d items, %d changes',
      [Command, Length(Previews), ChangedCount]));
  Result := BuildParameterBatchSetResponse(Previews, VerifiedValues,
    BeforeIdentity, AfterIdentity);
end;

function HandleAul2MIRAIRequest(const RequestText: string): string;
var
  AfterEditState: TAul2MIRAIEditState;
  AfterIdentity : TAul2MIRAISnapshotIdentity;
  AfterSnapshot : TAul2MIRAISceneSnapshot;
  Command      : string;                  // 検証済みコマンド名
  DetailRangeEnd: Integer;                // 詳細取得する選択範囲の終了
  DetailRangeStart: Integer;              // 詳細取得する選択範囲の開始
  ErrorCode    : string;                  // エラー識別子
  ErrorMessage : string;                  // エラー説明
  EditState    : TAul2MIRAIEditState;     // 現在の基本編集状態
  EffectIndex  : Integer;                 // プレビュー対象エフェクト番号
  Identity     : TAul2MIRAISnapshotIdentity; // 応答と状態の識別情報
  FrameImage   : TAul2MIRAIFrameImage;       // 現在フレームの画像ファイル
  ItemName     : string;                  // プレビュー対象設定項目名
  NewValue     : string;                  // プレビューする変更後文字列
  Preview      : TAul2MIRAIParameterPreview; // 検証済み変更予定
  RequestedStateToken: string;            // 呼び出し側が取得した状態指紋
  Snapshot     : TAul2MIRAISceneSnapshot; // 取得した現在シーン情報
  TargetIndex  : Integer;                 // シーン一覧内の対象番号
  VerifiedValue: string;
begin
  try
    if not ParseProtocolRequest(RequestText, Command, ErrorCode, ErrorMessage) then
    begin
      QueueMIRAIViewUpdate('External request rejected', '', 'WARN',
        ErrorCode + ': ' + ErrorMessage);
      Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
    end;

    if SameText(Command, AUL2MIRAI_COMMAND_STATE) then
    begin
      if not ReadCurrentEditState(EditHandle, EditState, ErrorMessage) then
      begin
        QueueMIRAIViewUpdate('External state read failed', '', 'ERROR',
          Command + ': ' + ErrorMessage);
        Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
      end;
      if not ReadCurrentSceneObjects(EditHandle, Snapshot, ErrorMessage) then
      begin
        QueueMIRAIViewUpdate('External state scan failed', '', 'ERROR',
          Command + ': ' + ErrorMessage);
        Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
      end;
      Identity := CreateSnapshotIdentity(EditState, Snapshot);
      QueueMIRAIViewUpdate(
        Format('External state read - scene %d, frame %d',
          [EditState.SceneId, EditState.CursorFrame]),
        '', 'OK',
        Format('%s -> scene %d, frame %d (%d ms)',
          [Command, EditState.SceneId, EditState.CursorFrame,
           EditState.ElapsedMs]));
      Exit(BuildEditStateResponse(EditState, Identity));
    end;

    if SameText(Command, AUL2MIRAI_COMMAND_CURRENT_FRAME_IMAGE) then
    begin
      if not ReadCurrentEditState(EditHandle, EditState, ErrorMessage) then
        Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
      if not ReadCurrentSceneObjects(EditHandle, Snapshot,
        ErrorMessage) then
        Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
      Identity := CreateSnapshotIdentity(EditState, Snapshot);
      if not CaptureSceneFrame(EditHandle, EditState.CursorFrame,
        FrameImage, ErrorMessage) then
      begin
        QueueMIRAIViewUpdate('External frame capture failed', '', 'ERROR',
          Command + ': ' + ErrorMessage);
        Exit(BuildProtocolError(Command, 'render_failed', ErrorMessage));
      end;
      QueueMIRAIViewUpdate(
        Format('External frame capture - frame %d', [FrameImage.Frame]),
        '', 'OK',
        Format('%s -> %dx%d, %d bytes (%d ms)',
          [Command, FrameImage.Width, FrameImage.Height,
           FrameImage.FileSize, FrameImage.ElapsedMs]));
      Exit(BuildFrameImageResponse(FrameImage, Identity));
    end;

    if SameText(Command, AUL2MIRAI_COMMAND_PREVIEW_PARAMETERS) or
       SameText(Command, AUL2MIRAI_COMMAND_SET_PARAMETERS) then
      Exit(HandleParameterBatchRequest(RequestText, Command));

    if SameText(Command, AUL2MIRAI_COMMAND_PREVIEW_MOVE_OBJECTS) or
       SameText(Command, AUL2MIRAI_COMMAND_MOVE_OBJECTS) then
      Exit(HandleObjectMoveRequest(RequestText, Command));

    if SameText(Command, AUL2MIRAI_COMMAND_PREVIEW_DUPLICATE_OBJECTS) or
       SameText(Command, AUL2MIRAI_COMMAND_DUPLICATE_OBJECTS) then
      Exit(HandleObjectDuplicateRequest(RequestText, Command));

    if SameText(Command, AUL2MIRAI_COMMAND_PREVIEW_EDIT_POSITION) or
       SameText(Command, AUL2MIRAI_COMMAND_SET_EDIT_POSITION) then
      Exit(HandleEditPositionRequest(RequestText, Command));

    if SameText(Command, AUL2MIRAI_COMMAND_PREVIEW_FOCUS_OBJECT) or
       SameText(Command, AUL2MIRAI_COMMAND_SET_FOCUS_OBJECT) then
      Exit(HandleObjectFocusRequest(RequestText, Command));

    if SameText(Command, AUL2MIRAI_COMMAND_OBJECT_DETAILS) then
    begin
      if not ParseObjectDetailsRequest(RequestText, RequestedStateToken,
        TargetIndex, ErrorCode, ErrorMessage) then
      begin
        QueueMIRAIViewUpdate('External object detail rejected', '', 'WARN',
          ErrorCode + ': ' + ErrorMessage);
        Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
      end;
      if not ReadCurrentEditState(EditHandle, EditState, ErrorMessage) then
        Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
      if not ReadCurrentSceneObjects(EditHandle, Snapshot, ErrorMessage,
        True, TargetIndex) then
        Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
      Identity := CreateSnapshotIdentity(EditState, Snapshot);
      if not SameText(RequestedStateToken, Identity.StateToken) then
      begin
        QueueMIRAIViewUpdate('External object detail rejected - state changed',
          '', 'WARN', Command + ': state_changed');
        Exit(BuildStateChangedError(Command, RequestedStateToken, Identity));
      end;
      if not KeepObjectByIndex(Snapshot, TargetIndex) then
      begin
        ErrorCode := 'target_not_found';
        ErrorMessage := Format('Object index %d was not found.', [TargetIndex]);
        QueueMIRAIViewUpdate('External object detail rejected', '', 'WARN',
          Command + ': ' + ErrorMessage);
        Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
      end;
      QueueMIRAIViewUpdate(
        Format('External object detail - object %d', [TargetIndex]),
        FormatSceneSnapshot(Snapshot), 'OK',
        Format('%s -> object %d (%d ms)',
          [Command, TargetIndex, Snapshot.ElapsedMs]));
      Exit(BuildSceneObjectsResponse(Command, Snapshot, Identity));
    end;

    if SameText(Command, AUL2MIRAI_COMMAND_PREVIEW_PARAMETER) then
    begin
      if not ParseParameterPreviewRequest(RequestText, RequestedStateToken,
        TargetIndex, EffectIndex, ItemName, NewValue, ErrorCode,
        ErrorMessage) then
      begin
        QueueMIRAIViewUpdate('External preview rejected', '', 'WARN',
          ErrorCode + ': ' + ErrorMessage);
        Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
      end;
      if not ReadCurrentEditState(EditHandle, EditState, ErrorMessage) then
      begin
        QueueMIRAIViewUpdate('External preview state read failed', '',
          'ERROR', Command + ': ' + ErrorMessage);
        Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
      end;
      if not ReadCurrentSceneObjects(EditHandle, Snapshot, ErrorMessage,
        True) then
      begin
        QueueMIRAIViewUpdate('External preview object read failed', '',
          'ERROR', Command + ': ' + ErrorMessage);
        Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
      end;
      Identity := CreateSnapshotIdentity(EditState, Snapshot);
      if not SameText(RequestedStateToken, Identity.StateToken) then
      begin
        QueueMIRAIViewUpdate('External preview rejected - state changed', '',
          'WARN', Command + ': state_changed');
        Exit(BuildStateChangedError(Command, RequestedStateToken, Identity));
      end;
      if not CreateParameterPreview(Snapshot, TargetIndex, EffectIndex,
        ItemName, NewValue, Preview, ErrorCode, ErrorMessage) then
      begin
        QueueMIRAIViewUpdate('External preview rejected', '', 'WARN',
          ErrorCode + ': ' + ErrorMessage);
        Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
      end;
      QueueMIRAIViewUpdate(
        Format('Preview - object %d, %s', [TargetIndex, ItemName]),
        '', 'OK',
        Format('%s -> object %d, effect %d, %s (%s -> %s)',
          [Command, TargetIndex, EffectIndex, ItemName,
           Preview.BeforeValue, Preview.AfterValue]));
      Exit(BuildParameterPreviewResponse(Preview, Identity));
    end;

    if SameText(Command, AUL2MIRAI_COMMAND_SET_PARAMETER) then
    begin
      if not ParseParameterSetRequest(RequestText, RequestedStateToken,
        TargetIndex, EffectIndex, ItemName, NewValue, ErrorCode,
        ErrorMessage) then
      begin
        QueueMIRAIViewUpdate('External edit rejected', '', 'WARN',
          ErrorCode + ': ' + ErrorMessage);
        Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
      end;
      if not ReadCurrentEditState(EditHandle, EditState, ErrorMessage) then
      begin
        QueueMIRAIViewUpdate('External edit state read failed', '',
          'ERROR', Command + ': ' + ErrorMessage);
        Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
      end;
      if not ReadCurrentSceneObjects(EditHandle, Snapshot, ErrorMessage,
        True) then
      begin
        QueueMIRAIViewUpdate('External edit object read failed', '',
          'ERROR', Command + ': ' + ErrorMessage);
        Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
      end;
      Identity := CreateSnapshotIdentity(EditState, Snapshot);
      if not SameText(RequestedStateToken, Identity.StateToken) then
      begin
        QueueMIRAIViewUpdate('External edit rejected - state changed', '',
          'WARN', Command + ': state_changed');
        Exit(BuildStateChangedError(Command, RequestedStateToken, Identity));
      end;
      if not CreateParameterPreview(Snapshot, TargetIndex, EffectIndex,
        ItemName, NewValue, Preview, ErrorCode, ErrorMessage) then
      begin
        QueueMIRAIViewUpdate('External edit rejected', '', 'WARN',
          ErrorCode + ': ' + ErrorMessage);
        Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
      end;

      if not Preview.WillChange then
      begin
        QueueMIRAIViewUpdate(
          Format('Edit skipped - object %d, %s unchanged',
            [TargetIndex, ItemName]), '', 'OK',
          Format('%s -> no change', [Command]));
        Exit(BuildParameterSetResponse(Preview, Identity, Identity, False,
          Preview.BeforeValue));
      end;

      if not ApplyParameterChange(EditHandle, Preview, VerifiedValue,
        ErrorCode, ErrorMessage) then
      begin
        QueueMIRAIViewUpdate('External edit failed', '', 'ERROR',
          ErrorCode + ': ' + ErrorMessage);
        Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
      end;

      if not ReadCurrentEditState(EditHandle, AfterEditState,
        ErrorMessage) then
      begin
        ErrorMessage := 'The edit was applied, but the updated state could ' +
          'not be read: ' + ErrorMessage;
        QueueMIRAIViewUpdate('External edit verification failed', '',
          'ERROR', ErrorMessage);
        Exit(BuildProtocolError(Command, 'post_write_read_failed',
          ErrorMessage));
      end;
      if not ReadCurrentSceneObjects(EditHandle, AfterSnapshot,
        ErrorMessage) then
      begin
        ErrorMessage := 'The edit was applied, but the updated objects ' +
          'could not be read: ' + ErrorMessage;
        QueueMIRAIViewUpdate('External edit verification failed', '',
          'ERROR', ErrorMessage);
        Exit(BuildProtocolError(Command, 'post_write_read_failed',
          ErrorMessage));
      end;
      AfterIdentity := CreateSnapshotIdentity(AfterEditState,
        AfterSnapshot);
      QueueMIRAIViewUpdate(
        Format('Edit applied - object %d, %s', [TargetIndex, ItemName]),
        '', 'OK',
        Format('%s -> object %d, effect %d, %s (%s -> %s)',
          [Command, TargetIndex, EffectIndex, ItemName,
           Preview.BeforeValue, VerifiedValue]));
      Exit(BuildParameterSetResponse(Preview, Identity, AfterIdentity,
        True, VerifiedValue));
    end;

    if not SameText(Command, AUL2MIRAI_COMMAND_OBJECTS) and
       not SameText(Command, AUL2MIRAI_COMMAND_CURSOR_OBJECTS) and
       not SameText(Command, AUL2MIRAI_COMMAND_RANGE_OBJECTS) and
       not SameText(Command, AUL2MIRAI_COMMAND_SELECTED_OBJECTS) then
    begin
      ErrorCode := 'unsupported_command';
      ErrorMessage := 'The requested command is not supported.';
      QueueMIRAIViewUpdate('External request rejected', '', 'WARN',
        Command + ': ' + ErrorMessage);
      Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
    end;

    if not ReadCurrentEditState(EditHandle, EditState, ErrorMessage) then
    begin
      QueueMIRAIViewUpdate('External state read failed', '', 'ERROR',
        Command + ': ' + ErrorMessage);
      Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
    end;

    DetailRangeStart := -1;
    DetailRangeEnd := -1;
    if SameText(Command, AUL2MIRAI_COMMAND_RANGE_OBJECTS) then
    begin
      DetailRangeStart := EditState.SelectRangeStart;
      DetailRangeEnd := EditState.SelectRangeEnd;
    end;
    if not ReadCurrentSceneObjects(EditHandle, Snapshot, ErrorMessage,
      SameText(Command, AUL2MIRAI_COMMAND_CURSOR_OBJECTS) or
      SameText(Command, AUL2MIRAI_COMMAND_RANGE_OBJECTS) or
      SameText(Command, AUL2MIRAI_COMMAND_SELECTED_OBJECTS), -1,
      DetailRangeStart, DetailRangeEnd) then
    begin
      QueueMIRAIViewUpdate('External read failed', '', 'ERROR',
        Command + ': ' + ErrorMessage);
      Exit(BuildProtocolError(Command, 'read_failed', ErrorMessage));
    end;
    Identity := CreateSnapshotIdentity(EditState, Snapshot);

    if SameText(Command, AUL2MIRAI_COMMAND_CURSOR_OBJECTS) then
      KeepObjectsAtCursor(Snapshot)
    else if SameText(Command, AUL2MIRAI_COMMAND_RANGE_OBJECTS) then
    begin
      if (EditState.SelectRangeStart < 0) or
         (EditState.SelectRangeEnd < EditState.SelectRangeStart) then
      begin
        ErrorCode := 'selection_range_not_set';
        ErrorMessage := 'No valid selection range is set.';
        QueueMIRAIViewUpdate('External range read rejected', '', 'WARN',
          Command + ': ' + ErrorMessage);
        Exit(BuildProtocolError(Command, ErrorCode, ErrorMessage));
      end;
      KeepObjectsInFrameRange(Snapshot, EditState.SelectRangeStart,
        EditState.SelectRangeEnd);
    end
    else if SameText(Command, AUL2MIRAI_COMMAND_SELECTED_OBJECTS) then
      KeepSelectedObjects(Snapshot);

    QueueMIRAIViewUpdate(
      Format('External read - %d objects, %d ms',
        [Length(Snapshot.Objects), Snapshot.ElapsedMs]),
      FormatSceneSnapshot(Snapshot),
      'OK',
      Format('%s -> %d objects (%d ms)',
        [Command, Length(Snapshot.Objects), Snapshot.ElapsedMs]));
    Result := BuildSceneObjectsResponse(Command, Snapshot, Identity);
  except
    on E: Exception do
    begin
      QueueMIRAIViewUpdate('External request failed', '', 'ERROR',
        E.ClassName + ': ' + E.Message);
      Result := BuildProtocolError('', 'internal_error', E.Message);
    end;
  end;
end;

end.
