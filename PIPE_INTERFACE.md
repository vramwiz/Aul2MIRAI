# AI MIRAI Named Pipe通信仕様

この文書は、Aul2MIRAIプラグインと外部呼び出し側の間で使用するNamed Pipe通信の開発者向け仕様を記録する。プロジェクト全体の方針と課題は[`note.md`](note.md)、Codexが実際に使用する操作手順は[`AI_USAGE.md`](AI_USAGE.md)へ記載する。

## 基本構成

- 専用クライアントEXEは作成・配布・使用しない。
- サーバーはAviUtl2に読み込まれた`Aul2MIRAI.aux2`内で動作する。
- 呼び出し側はPowerShell標準の`NamedPipeClientStream`を使用する。
- 要求と応答はUTF-8 JSONとする。
- 現在のプロトコルは読み取り専用とする。

## 接続情報

| 項目 | 値 |
| --- | --- |
| Pipe名 | `Aul2MIRAI.v1` |
| Windows上の完全名 | `\\.\pipe\Aul2MIRAI.v1` |
| 方向 | 双方向 |
| 転送モード | Message |
| 最大インスタンス数 | 1 |
| サーバーバッファ | 65,536 bytes |
| 文字コード | UTF-8 |

要求JSONを1メッセージとして送信し、プラグインは応答JSONを1メッセージとして返す。同時要求は行わず、1件ずつ直列に処理する。

## 処理の流れ

1. `PipeServerTThread`がワーカースレッドで接続と受信を待つ。
2. JSON要求を受信したら、`WM_PIPE_NOTIFY`をAI MIRAIウィンドウへ送る。
3. AviUtl2のUIスレッドで要求を検証する。
4. UIスレッドからAviUtl2 SDKの読み取り処理を呼ぶ。
5. 取得結果を通常のDelphiデータへコピーし、JSON応答を生成する。
6. PipeスレッドがUTF-8 JSONをクライアントへ返す。
7. クライアントは応答全体を読み終えてから接続を閉じる。

AviUtl2 SDKへアクセスする処理はPipeのワーカースレッドで直接実行しない。

## プロトコル

プロトコル名は`Aul2MIRAI`、バージョンは`1`とする。

現在使用できるコマンド:

| コマンド | 内容 |
| --- | --- |
| `get_scene_objects` | 現在編集中のシーンと、そのシーンにあるオブジェクト一覧を取得する。 |

要求例:

```json
{
  "protocol": "Aul2MIRAI",
  "protocol_version": 1,
  "command": "get_scene_objects"
}
```

成功応答とエラー応答のフィールド定義は[`AI_USAGE.md`](AI_USAGE.md)を参照する。

## PowerShellからの接続

配布用の接続コードとCodex向けの注意事項は[`AI_USAGE.md`](AI_USAGE.md)に置く。この文書には通信方式とプラグイン内部の処理だけを記載し、同じPowerShellコードを重複させない。

## 使用ライブラリ

`D:\DelphiProg\Lib\Pipe\PipeServerTThread.pas`を、次の場所へコピーして使用する。

```text
Source\Lib\Pipe\PipeServerTThread.pas
```

コピーしたライブラリはPipeの生成、接続待機、UTF-8送受信、UIスレッドへの通知を担当する。AI MIRAI固有の開始・終了管理とJSON要求処理への接続は`Source\Aul2MIRAIPipeServer.pas`が担当する。

## 終了処理

プラグイン解除時は次の順序を守る。

1. Pipeスレッドへ終了を通知する。
2. 応答待ちイベントを解除する。
3. 接続待ち中の場合はダミー接続で`ConnectNamedPipe`を解除する。
4. Pipeスレッドの終了を待つ。
5. UI、SDKハンドル、GDIリソースを解放する。

## 現在の制限と課題

- 同時接続は1つだけである。
- 1要求が65,536 bytesを超える場合は扱わない。
- 現在は`get_scene_objects`だけを公開している。
- Pipeのアクセス制御はコピー元ライブラリの既定動作を使用しており、明示的なセキュリティ記述子はまだ設定していない。
- 編集コマンドを追加するときは、状態の世代管理、事前確認、Undo単位を通信仕様にも追加する必要がある。
- 応答が大きくなる場合は、上限、分割方式、またはページングを定義する必要がある。

## 確認済み事項

- Windows 11上でPowerShellの`NamedPipeClientStream`から直接接続できる。
- 専用クライアントEXEを使用せずJSON応答を取得できる。
- 実プロジェクトで`get_scene_objects`から4オブジェクトを31 msで取得できた。
