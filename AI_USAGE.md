# AI MIRAI 操作ガイド

この文書は、AI MIRAIの外部操作コマンドをCodexなどのAIが作業開始時に理解するための仕様書です。

## 対応バージョン

- プロトコル: `1`
- 接続方式: PowerShell標準の`NamedPipeClientStream`
- 対応機能: 読み取り専用

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
| `get_selected_objects` | 通常選択・複数選択中のオブジェクトと設定値 |

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

## オブジェクト応答形式

```json
{
  "protocol": "Aul2MIRAI",
  "protocol_version": 1,
  "status": "ok",
  "command": "get_scene_objects",
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
        "effects": ["画像ファイル", "標準描画"],
        "effect_details": [
          {
            "name": "画像ファイル",
            "parameters": [
              {
                "name": "ファイル",
                "value": "D:\\Video\\background.png",
                "truncated": false
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

`selected`は通常選択のフォーカス対象と複数選択対象を統合した値です。`focused`は、その中でもオブジェクト設定ウィンドウで通常選択されている1件を示します。

通常選択があるのに`get_selected_object_num`相当の複数選択数が0となる場合でも、AI MIRAIはフォーカス対象を統合して`get_selected_objects`へ含めます。

`effect_details`は`get_objects_at_cursor`と`get_selected_objects`で返ります。設定値はエイリアスと同じ文字列表現です。`truncated`が`true`の場合、その値は安全上の上限で省略されています。

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

- 現在のバージョンは読み取り専用です。編集操作は要求しないでください。
- 取得結果は要求時点のスナップショットです。AviUtl2で編集した後は再取得してください。
- `index`や表示名だけを永続IDとして保存しないでください。
- 素材パス、エフェクト名、カーソル位置または選択中オブジェクトの設定値を取得できます。エイリアス全文は取得対象ではありません。
- 応答が大きい場合でも、JSONの一部だけを切り出して別の有効な状態として扱わないでください。
