# Aul2MIRAI

AviUtl2用の最小構成の拡張プラグインです。

- AviUtl2上の表示名: `AI MIRAI`
- 対象: Win64
- Release出力: `C:\ProgramData\aviutl2\Plugin\Aul2MIRAI\Aul2MIRAI.aux2`

ビルド時にAviUtl2のPluginフォルダへ `.aux2` が自動配置されます。

## Codexからオブジェクトを取得する

AviUtl2でAI MIRAIを読み込んだ状態で、PowerShell標準のNamed Pipe機能から読み取り専用のJSON要求を送ります。専用EXEは使用しません。接続方法とJSON仕様は[`AI_USAGE.md`](AI_USAGE.md)を参照してください。

確認済みの取得機能:

- 現在のプロジェクト、シーン、カーソル、選択範囲などの編集状態
- 現在シーンの全オブジェクト
- カーソル位置に存在するオブジェクト
- 通常選択および複数選択中のオブジェクト
- 標準オブジェクトの種類、素材パス、適用エフェクト名
- カーソル位置または選択中オブジェクトのエフェクト設定値

AviUtl2 v2.10の実プロジェクトで、通常選択したオブジェクトの取得と設定詳細の読み取りまで確認済みです。開発・検証履歴は[`HISTORY.md`](HISTORY.md)を参照してください。

プラグインは`Aul2MIRAI.dproj`からRelease / Win64でビルドします。
