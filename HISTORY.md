# Aul2MIRAI 開発・検証履歴

完了済みの実装と実機確認結果を日付順に記録する。現在の方針と未解決課題は[`note.md`](note.md)、通信仕様は[`PIPE_INTERFACE.md`](PIPE_INTERFACE.md)を参照する。

## 2026-07-22

- AviUtl2 v2.10で`AI MIRAI`ウィンドウの起動と表示を確認した。
- read section内で全レイヤーをオブジェクト単位に探索し、実プロジェクトの4オブジェクトを31 msで取得した。
- PowerShell標準の`NamedPipeClientStream`から、専用クライアントEXEを使わず接続できることを確認した。
- `get_edit_state`、`get_scene_objects`、`get_objects_at_cursor`、`get_selected_objects`のJSON応答を確認した。
- `audio_test.aup2`でプロジェクトパス、シーン`Root`、カーソル534フレーム、全4オブジェクトを取得した。
- カーソル位置にあるグループ制御、音声、動画の3オブジェクトと、それぞれのエフェクト設定値を取得した。
- SDKの複数選択APIだけでは通常選択が0件になることを確認し、`get_focus_object`の対象と複数選択対象を統合する方式へ変更した。
- 統合後、通常選択されたレイヤー1の`グループ制御(音声)`を`selected: true`、`focused: true`として取得した。
- 同じ選択オブジェクトから2エフェクト、106設定項目を取得し、値の切り捨てがないことを確認した。
