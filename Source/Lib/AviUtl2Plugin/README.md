# AviUtl2 Plugin SDK

- `plugin2.h`: `C:\Users\vramw\Downloads\aviutl2_sdk_v210\plugin2.h` からコピーしたAviUtl2 v2.10公式SDKヘッダー。
- `AviUtl2PluginTypes.pas`: `D:\DelphiProg\test\Aul2AudioFilter` からコピーしたDelphi用SDK型定義を基に、公式v2.10の読み取りAPIを追加したもの。
- `AviUtl2PluginCore.pas`: 同じ参照元からコピーした編集ハンドル、プロジェクトハンドル、編集状態取得用の共通ユニット。

新しいAPIを使用するときは `plugin2.h` を正とし、構造体のフィールド順、サイズ、アラインメント、関数の呼出規約をDelphi定義へ正確に反映する。

公式ヘッダーは原本の文字コードとバイト列を維持するため、Gitでは `*.h` をbinaryとして扱う。

コピー元の `.dcu` と `__history` はライブラリソースではないため含めない。
