# AI MIRAI 操作ガイド

この文書は、AI MIRAIの外部操作コマンドをCodexなどのAIが作業開始時に理解するための仕様書です。

## 対応バージョン

- プロトコル: `1`
- 接続方式: PowerShell標準の`NamedPipeClientStream`
- 対応機能: 状態・オブジェクト・現在フレーム画像の取得、安全確認付き編集

## 前提条件

- AviUtl2が起動していること。
- AviUtl2が`Aul2MIRAI.aux2`を読み込んでいること。
- 専用クライアントEXEは使用しない。次のPowerShellコードで直接接続すること。

## 使用できるコマンド

| コマンド | 取得内容 |
| --- | --- |
| `get_edit_state` | 現在のプロジェクト、シーン、カーソル、選択範囲、表示範囲 |
| `get_scene_objects` | 現在シーンの全オブジェクト |
| `get_objects_at_cursor` | カーソルフレームと重なるオブジェクトと設定値 |
| `get_objects_in_selection` | 現在の選択範囲と重なるオブジェクトと設定値 |
| `get_selected_objects` | 通常選択・複数選択中のオブジェクトと設定値 |
| `get_object_details` | 最新状態のindexを指定した単一オブジェクトの詳細 |
| `get_current_frame_image` | 現在のカーソルフレームを一時BMPへレンダリング |
| `preview_set_object_parameter` | 選択オブジェクトの設定値変更を実行せず検証 |
| `set_object_parameter` | 選択オブジェクトの単一設定値を安全条件付きで変更 |
| `preview_set_object_parameters` | 最大64件の設定値変更を実行せず一括検証 |
| `set_object_parameters` | 最大64件を1回のUndo単位で一括変更 |
| `preview_move_objects` | 最大64個の選択オブジェクトの移動先を検証 |
| `move_objects` | 最大64個を衝突検査付きで一括移動 |
| `preview_duplicate_objects` | 最大64件の複製元と空き生成先を検証 |
| `duplicate_objects` | 最大64件を1回のUndo単位で一括複製 |
| `preview_set_edit_position` | カーソル位置と選択範囲の変更予定を検証 |
| `set_edit_position` | カーソル位置と選択範囲を設定・解除 |

## 接続と取得

PowerShell:

```powershell
$pipe = [System.IO.Pipes.NamedPipeClientStream]::new(
  '.',
  'Aul2MIRAI.v1',
  [System.IO.Pipes.PipeDirection]::InOut,
  [System.IO.Pipes.PipeOptions]::None)

try {
  $pipe.Connect(5000)
  $pipe.ReadMode = [System.IO.Pipes.PipeTransmissionMode]::Message

  $command = 'get_edit_state'
  $request = @{
    protocol = 'Aul2MIRAI'
    protocol_version = 1
    command = $command
  } | ConvertTo-Json -Compress
  $requestBytes = [System.Text.Encoding]::UTF8.GetBytes($request)
  $pipe.Write($requestBytes, 0, $requestBytes.Length)
  $pipe.Flush()

  $buffer = [byte[]]::new(65536)
  $response = [System.IO.MemoryStream]::new()
  do {
    $count = $pipe.Read($buffer, 0, $buffer.Length)
    if ($count -gt 0) {
      $response.Write($buffer, 0, $count)
    }
  } until ($pipe.IsMessageComplete)

  [System.Text.Encoding]::UTF8.GetString($response.ToArray())
}
finally {
  if ($null -ne $response) { $response.Dispose() }
  $pipe.Dispose()
}
```

最後の式がJSON文字列をPowerShellの標準出力へ出します。`status`が`ok`なら成功、`error`なら要求または読み取りの失敗です。接続そのものに失敗した場合はPowerShell例外として扱います。

`$command`を上表の値へ変更して必要な情報を取得します。

## 編集状態の応答形式

`get_edit_state`は`edit_state`に現在の状態を返します。フレームとレイヤーは0-basedです。

```json
{
  "protocol": "Aul2MIRAI",
  "protocol_version": 1,
  "status": "ok",
  "command": "get_edit_state",
  "snapshot_id": "4c5eb24b-b2d9-46ff-90c8-368c4c1f6608",
  "state_token": "sha256:bf4cb47cb3631a94048d10929f0e2dc2b733025f467596d878ec6f3fcfa716cc",
  "captured_at_utc": "2026-07-22T04:12:36.658Z",
  "edit_state": {
    "captured_at_utc": "2026-07-22T04:12:36.658Z",
    "project_path": "D:\\Video\\sample.aup2",
    "project_name": "sample.aup2",
    "scene_id": 0,
    "scene_name": "Root",
    "edit_mode": "edit",
    "width": 1920,
    "height": 1080,
    "rate": 30,
    "scale": 1,
    "sample_rate": 44100,
    "cursor_frame": 120,
    "cursor_seconds": 4.0,
    "cursor_layer": 2,
    "select_range_start": -1,
    "select_range_end": -1,
    "has_select_range": false,
    "selected_count": 0,
    "elapsed_ms": 0
  }
}
```

プロジェクトが未保存、またはパスを取得できない状態では`project_path`と`project_name`は空文字になります。

## 現在フレーム画像の取得

`get_current_frame_image`は、現在のカーソルフレームをAviUtl2でレンダリングし、BMPファイルとして返します。要求に追加フィールドはありません。

```json
{
  "protocol": "Aul2MIRAI",
  "protocol_version": 1,
  "command": "get_current_frame_image"
}
```

成功応答の`image.file_path`は`%TEMP%\Aul2MIRAI`以下に自動生成された一意なファイルです。任意パスの指定や既存ファイルの上書きはできません。

```json
{
  "status": "ok",
  "command": "get_current_frame_image",
  "image": {
    "file_path": "C:\\Users\\user\\AppData\\Local\\Temp\\Aul2MIRAI\\frame_120_uuid.bmp",
    "format": "bmp",
    "frame": 120,
    "width": 1920,
    "height": 1080,
    "file_size": 8294454,
    "elapsed_ms": 42
  }
}
```

取得した画像を確認した後、不要になったファイルは呼び出し側で削除してください。画像取得はプロジェクト内容を変更せず、Undoも発生しません。`state_token`はレンダリング対象を取得した時点の編集状態を示します。

## オブジェクト応答形式

```json
{
  "protocol": "Aul2MIRAI",
  "protocol_version": 1,
  "status": "ok",
  "command": "get_scene_objects",
  "snapshot_id": "c1500c29-fef2-4e31-8f8d-bacf5709e7fe",
  "state_token": "sha256:bf4cb47cb3631a94048d10929f0e2dc2b733025f467596d878ec6f3fcfa716cc",
  "captured_at_utc": "2026-07-22T04:12:36.658Z",
  "snapshot": {
    "scene_id": 0,
    "width": 1920,
    "height": 1080,
    "rate": 30,
    "scale": 1,
    "cursor_frame": 120,
    "layer_max": 4,
    "selected_count": 1,
    "elapsed_ms": 31,
    "layers": [
      {
        "index": 0,
        "name": "Layer 1",
        "state_available": true,
        "enabled": true,
        "locked": false
      }
    ],
    "objects": [
      {
        "index": 0,
        "layer": 2,
        "start_frame": 100,
        "end_frame": 149,
        "selected": true,
        "focused": true,
        "name": "Sample",
        "primary_effect": "画像ファイル",
        "object_type": "image",
        "material_path": "D:\\Video\\background.png",
        "content_digest": "sha256:380b924f8fd5ae5e71a3313be7e001b2ca01ede0b547594f3fd7a1439ab239f4",
        "section_count": 1,
        "focused_section": 0,
        "section_frames": [100],
        "effects": ["画像ファイル", "標準描画"],
        "effect_states": [
          {
            "name": "画像ファイル",
            "enabled": true,
            "locked": false
          }
        ],
        "effect_details": [
          {
            "name": "画像ファイル",
            "state_available": true,
            "enabled": true,
            "locked": false,
            "parameters": [
              {
                "name": "ファイル",
                "value": "D:\\Video\\background.png",
                "truncated": false,
                "track_info": null
              }
            ]
          }
        ]
      }
    ]
  }
}
```

`layer`とフレーム番号はSDKと同じ0-basedです。`index`はその応答内だけで有効な連番であり、永続的なオブジェクト識別子ではありません。

`layers`には各レイヤーの名前と状態が入ります。`state_available`が`false`の場合、そのAviUtl2では状態APIを利用できないため、有効・ロック状態を推測しないでください。

`section_count`には基準区間を含み、2以上なら中間点で分割された区間があります。`section_frames`は各区間の開始フレームをSDKと同じ0-basedの絶対フレームで示します。`focused_section`はフォーカス中の区間番号で、対象がフォーカスされていない場合などは`-1`です。

`effect_states`は、取得可能な場合に各エフェクトの有効・ロック状態を返します。古いAviUtl2では空配列となり、`effect_details[].state_available`も`false`になります。この場合も名称や設定値など取得可能な共通情報は利用できます。

`selected`は通常選択のフォーカス対象と複数選択対象を統合した値です。`focused`は、その中でもオブジェクト設定ウィンドウで通常選択されている1件を示します。

通常選択があるのに`get_selected_object_num`相当の複数選択数が0となる場合でも、AI MIRAIはフォーカス対象を統合して`get_selected_objects`へ含めます。

`snapshot_id`は応答そのものの識別子であり、永続的な状態IDではありません。`state_token`は編集状態の比較に使用します。同じ状態を再取得した場合は同じ値となり、カーソル、選択、配置、レイヤー状態、区間、エフェクト状態、設定値などが変わると別の値になります。編集状態が変わり得る操作の前には再取得し、古い`state_token`を現在状態として扱わないでください。

`effect_details`は`get_objects_at_cursor`、`get_objects_in_selection`、`get_selected_objects`で返ります。設定値はエイリアスと同じ文字列表現です。`truncated`が`true`の場合、その値は安全上の上限で省略されています。

各設定項目の`track_info`は、トラックバー項目ならオブジェクト、通常の文字列・チェック項目などでは`null`です。トラックバー情報には`mode`、`parameter_values`、`accelerate`、`decelerate`、`ignore_midpoint`、`time_control`、`group`が入ります。`mode`は移動なしの場合に空文字、`parameter_values`は内部パラメーターがない場合に空配列となります。

`track_info.group`の`name`、`count`、`index`は、XYZなど同じエフェクト内で連動するトラックバー項目のグループです。複数オブジェクト間のグループ関係ではありません。公開SDKから複数オブジェクトのグループ・連結関係は取得できないため、配置や選択状態だけから関係を断定しないでください。

`get_objects_in_selection`は現在の選択範囲と1フレーム以上重なるオブジェクトを全レイヤーから返し、`effect_details`も含みます。開始・終了フレームはともに範囲へ含まれます。選択範囲がない場合は`selection_range_not_set`が返るため、必要なら先に`get_edit_state`の`has_select_range`を確認してください。

## 単一オブジェクトの詳細取得

先に`get_scene_objects`などを実行し、同じ応答の`state_token`と対象の`index`を指定します。

```json
{
  "protocol": "Aul2MIRAI",
  "protocol_version": 1,
  "command": "get_object_details",
  "state_token": "sha256:bf4cb47cb3631a94048d10929f0e2dc2b733025f467596d878ec6f3fcfa716cc",
  "target_index": 0
}
```

成功時は通常のオブジェクト応答形式で、`snapshot.objects`に指定した1件だけが入り、`effect_details`を含みます。`index`は永続識別子ではないため、必ず同じ取得結果の`state_token`と組み合わせてください。`state_changed`が返った場合は自動的に同じindexで再試行せず、一覧を再取得して配置、種類、名称などから対象を選び直してください。

## 設定値変更のプレビュー

先に`get_selected_objects`を実行し、その応答の`state_token`、オブジェクトの`index`、`effect_details`内のエフェクト番号を使用します。

要求例:

```json
{
  "protocol": "Aul2MIRAI",
  "protocol_version": 1,
  "command": "preview_set_object_parameter",
  "state_token": "sha256:bf4cb47cb3631a94048d10929f0e2dc2b733025f467596d878ec6f3fcfa716cc",
  "target_index": 0,
  "effect_index": 0,
  "item": "表示番号",
  "value": "1"
}
```

成功応答例:

```json
{
  "status": "ok",
  "command": "preview_set_object_parameter",
  "preview": {
    "operation": "set_object_parameter",
    "applied": false,
    "will_change": true,
    "target": {
      "index": 0,
      "layer": 0,
      "start_frame": 144,
      "end_frame": 224,
      "object_type": "image",
      "primary_effect": "画像ファイル"
    },
    "effect": {
      "index": 0,
      "name": "画像ファイル"
    },
    "item": "表示番号",
    "before": "0",
    "after": "1"
  }
}
```

プレビューはAviUtl2を変更しません。`applied`が`false`であることを確認してください。`state_changed`が返った場合は状態を再取得し、対象と値を改めて確認してください。

## 設定値の変更

ユーザーが変更を求めた場合に限り、先にプレビュー結果を提示または確認してから、同じ対象と値で`set_object_parameter`を要求します。実行直前に`get_selected_objects`を再取得し、その最新`state_token`を使用してください。

```json
{
  "protocol": "Aul2MIRAI",
  "protocol_version": 1,
  "command": "set_object_parameter",
  "state_token": "sha256:bf4cb47cb3631a94048d10929f0e2dc2b733025f467596d878ec6f3fcfa716cc",
  "target_index": 0,
  "effect_index": 0,
  "item": "表示番号",
  "value": "1",
  "apply": true
}
```

成功応答の`change.applied`、`change.changed`、`before`、`requested`、`verified`を確認します。ルートの`state_token`は変更後の状態指紋です。同じ値を指定した場合は成功しますが、`applied=false`、`changed=false`となりUndo項目を作りません。

`apply`はJSON Booleanの`true`が必須です。`state_changed`、`target_changed`、`value_changed`などが返った場合は自動的に再試行せず、状態を再取得して対象と値を確認してください。

## 複数設定値の一括変更

互いに関連する設定値は、一件ずつ変更せず`preview_set_object_parameters`でまとめて確認します。

```json
{
  "protocol": "Aul2MIRAI",
  "protocol_version": 1,
  "command": "preview_set_object_parameters",
  "state_token": "sha256:bf4cb47cb3631a94048d10929f0e2dc2b733025f467596d878ec6f3fcfa716cc",
  "changes": [
    {
      "target_index": 0,
      "effect_index": 0,
      "item": "表示番号",
      "value": "1"
    },
    {
      "target_index": 0,
      "effect_index": 1,
      "item": "X",
      "value": "10.00"
    }
  ]
}
```

適用時はコマンドを`set_object_parameters`へ変更し、`apply: true`を追加します。1～64件を指定でき、すべての項目が書込み前に検証されます。同じ対象・エフェクト・項目を配列内で重複指定してはいけません。

成功応答では`change.changed_count`と各`changes[].verified`を確認してください。一括要求全体がAviUtl2の1回のUndo単位になります。エラー時は一部だけを別要求で自動再試行せず、状態を再取得してください。

## オブジェクトの移動

先に`get_selected_objects`を実行し、最新の`state_token`と対象の`index`を使って`preview_move_objects`を要求します。

```json
{
  "protocol": "Aul2MIRAI",
  "protocol_version": 1,
  "command": "preview_move_objects",
  "state_token": "sha256:bf4cb47cb3631a94048d10929f0e2dc2b733025f467596d878ec6f3fcfa716cc",
  "moves": [
    {
      "target_index": 0,
      "layer": 1,
      "frame": 300
    }
  ]
}
```

`before`と`after`のレイヤー、開始・終了フレーム、`moved_count`を確認します。適用時はコマンドを`move_objects`へ変更し、`apply: true`を追加します。フレームとレイヤーは0-basedで、オブジェクトの長さは維持されます。

移動先が既存オブジェクトと重なる要求は拒否されます。現在はオブジェクト同士の位置交換にも対応しません。`destination_occupied`または`destination_conflict`の場合は、ユーザーと別の空き位置を決めてください。

## オブジェクトの複製

先に`get_selected_objects`を実行し、最新の`state_token`と選択中の複製元`index`を使って`preview_duplicate_objects`を要求します。

```json
{
  "protocol": "Aul2MIRAI",
  "protocol_version": 1,
  "command": "preview_duplicate_objects",
  "state_token": "sha256:bf4cb47cb3631a94048d10929f0e2dc2b733025f467596d878ec6f3fcfa716cc",
  "duplicates": [
    {
      "source_index": 0,
      "layer": 1,
      "frame": 300
    }
  ]
}
```

複製元、生成先、終了フレーム、`duplicate_count`を確認します。適用時はコマンドを`duplicate_objects`へ変更し、`apply: true`を追加します。複製元の長さと設定内容は維持されます。

成功応答の`created_index`は応答時点の連番です。後続操作では保存せず、必ず状態を再取得して配置、種類、名称などから対象を確認してください。AviUtl2の内部正規化により、複製元と生成物の`content_digest`が異なる場合があります。

## カーソル位置と選択範囲

カーソルまたは選択範囲を変更する前に`get_edit_state`を取得し、`frame_max`、`layer_max`、現在位置を確認します。

```json
{
  "protocol": "Aul2MIRAI",
  "protocol_version": 1,
  "command": "preview_set_edit_position",
  "state_token": "sha256:bf4cb47cb3631a94048d10929f0e2dc2b733025f467596d878ec6f3fcfa716cc",
  "cursor": {
    "layer": 0,
    "frame": 100
  },
  "selection": {
    "start_frame": 50,
    "end_frame": 120
  }
}
```

適用時はコマンドを`set_edit_position`へ変更し、`apply: true`を追加します。カーソルだけ、または選択範囲だけの指定も可能です。選択範囲を解除する場合は`selection: null`を指定します。

これらはUI状態でありUndo対象ではありません。成功後は返された`state_token`または`get_edit_state`で実際の位置を確認してください。

## シーン操作について

現在の公開SDKでは現在シーンの情報だけを取得できます。シーン一覧、シーン切り替え、シーン追加は利用できません。画面操作の模倣や非公開APIで補完せず、未対応としてユーザーへ伝えてください。

## エラー形式

```json
{
  "protocol": "Aul2MIRAI",
  "protocol_version": 1,
  "status": "error",
  "command": "get_scene_objects",
  "error": {
    "code": "read_failed",
    "message": "AviUtl2 rejected the read request."
  }
}
```

エラー時は、存在しない情報を推測して補完せず、`code`と`message`をユーザーへ伝えてください。

## 操作規則

- 編集はユーザーが明示的に求めた単一設定値だけを対象とし、事前にプレビューしてください。
- `preview_set_object_parameter`は変更予定の検証だけであり、編集操作ではありません。
- `set_object_parameter`では最新の`state_token`と`apply: true`を必須とし、応答の`verified`を確認してください。
- 関連する複数項目は`set_object_parameters`で1回のUndoへまとめてください。
- 移動は必ず`preview_move_objects`で衝突と移動範囲を確認してください。
- 複製は必ず`preview_duplicate_objects`で空き位置と生成範囲を確認してください。
- 編集位置は`preview_set_edit_position`で範囲を確認し、UI状態であることをユーザーへ伝えてください。
- 削除はまだ要求しないでください。
- 取得結果は要求時点のスナップショットです。AviUtl2で編集した後は再取得してください。
- `index`や表示名だけを永続IDとして保存しないでください。
- 素材パス、エフェクト名、カーソル位置または選択中オブジェクトの設定値を取得できます。エイリアス全文は取得対象ではありません。
- 応答が大きい場合でも、JSONの一部だけを切り出して別の有効な状態として扱わないでください。
