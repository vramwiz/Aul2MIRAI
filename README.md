# Aul2MIRAI

AviUtl2用の最小構成の拡張プラグインです。

- AviUtl2上の表示名: `AI MIRAI`
- 対象: Win64
- Release出力: `C:\ProgramData\aviutl2\Plugin\Aul2MIRAI\Aul2MIRAI.aux2`

ビルド時にAviUtl2のPluginフォルダへ `.aux2` が自動配置されます。

## Codexからオブジェクトを取得する

AviUtl2でAI MIRAIを読み込んだ状態で、PowerShell標準のNamed Pipe機能から読み取り専用のJSON要求を送ります。専用EXEは使用しません。接続方法とJSON仕様は[`AI_USAGE.md`](AI_USAGE.md)を参照してください。

プラグインは`Aul2MIRAI.dproj`からRelease / Win64でビルドします。
