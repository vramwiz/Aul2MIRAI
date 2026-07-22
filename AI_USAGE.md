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

## オブジェクト一覧の取得

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

  $request = '{"protocol":"Aul2MIRAI","protocol_version":1,"command":"get_scene_objects"}'
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

## 応答形式

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
        "name": "Sample",
        "primary_effect": "Text"
      }
    ]
  }
}
```

`layer`とフレーム番号はSDKと同じ0-basedです。`index`はその応答内だけで有効な連番であり、永続的なオブジェクト識別子ではありません。

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
- 素材パス、エイリアス全文、全フィルター設定はまだ取得対象ではありません。
- 応答が大きい場合でも、JSONの一部だけを切り出して別の有効な状態として扱わないでください。
