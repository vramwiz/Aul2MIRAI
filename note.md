# Aul2MIRAI note

作業再開時に最初に見る開発メモ。現在の方針、開発方法、コメントルール、ビルド方法を置く。

- 利用者向けの概要、配置、配布説明は `README.md` に置く。
- 完了済みの開発記録、検証結果、試行錯誤、日付付きの作業履歴は、必要になった時点で `HISTORY.md` を作って記録する。
- 実装途中では文書を逐次更新せず、ビルド、AviUtl2上の表示、実機確認まで完了してから現状を反映する。

## 現在の方針

- プロジェクト名は `Aul2MIRAI`、AviUtl2上の表示名は `AI MIRAI` とする。
- `D:\DelphiProg\test\Aul2MIRAI` で、Delphi Win64のAviUtl2拡張プラグインとして開発する。
- `Aul2AudioController` の拡張プラグイン境界を参考にするが、必要になるまで機能や依存ユニットを増やさない。
- AviUtl2 SDK型定義など、共通利用できるコードは `Source\Lib` に置く。
- AviUtl2へ公開する入口とUI・機能実装を分け、`.dpr` を肥大化させない。
- SDKコールバックは `cdecl` を維持する。Delphi例外をAviUtl2側へ漏らさない。
- 初期化解除では、AviUtl2やSDKへの参照が無効になる前にウィンドウやGDIリソースを解放する。

## プロジェクト構成

- `Aul2MIRAI.dpr`: `InitializePlugin`、`RegisterPlugin`、`UninitializePlugin` をexportする入口。
- `Aul2MIRAI.dproj`: Delphi Win64 Debug / Releaseビルド設定。ビルド後にDLLを `.aux2` へコピーする。
- `Source\Aul2MIRAIPlugin.pas`: `AI MIRAI` の編集メニュー、クライアントウィンドウ、表示リソースを管理する。
- `Source\Lib\AviUtl2Plugin\AviUtl2PluginTypes.pas`: AviUtl2汎用プラグインSDKのDelphi型定義。
- `Source\Lib\FFmpeg\FFmpegApi.pas`: FFmpeg 8.1系DLLの型定義、関数ポインタ、動的ロード処理。
- `Lib\FFmpeg`: FFmpeg 8.1.1の実行時DLLとライセンス文書。詳細は同フォルダの `README.md` を参照する。
- `Win64\Debug` / `Win64\Release`: Delphiの中間ファイルとビルド出力。

## ユニット分割方針

- `Aul2MIRAI.dpr` はAviUtl2のexport境界と登録開始・解除だけを担当する。
- `Aul2MIRAIPlugin.pas` はウィンドウ登録とプラグイン全体のライフサイクルを担当する。
- 新しい機能が独立した責務を持つ場合だけ、`Source\Aul2MIRAIXxx.pas` として分割する。
- 複数機能から再利用できる処理だけを `Source\Lib` へ移す。プロジェクト固有処理は安易にライブラリ化しない。
- `uses` と `.dproj` の `DCCReference` には、実際のビルドで必要なユニットだけを登録する。

## ビルド方法

Delphi 37.0を使用する。

Debug Win64:

```powershell
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && msbuild ""D:\DelphiProg\test\Aul2MIRAI\Aul2MIRAI.dproj"" /t:Build /p:Config=Debug /p:Platform=Win64"
```

Release Win64:

```powershell
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && msbuild ""D:\DelphiProg\test\Aul2MIRAI\Aul2MIRAI.dproj"" /t:Build /p:Config=Release /p:Platform=Win64"
```

出力先:

```text
D:\DelphiProg\test\Aul2MIRAI\Win64\Debug\Aul2MIRAI.aux2
D:\DelphiProg\test\Aul2MIRAI\Win64\Release\Aul2MIRAI.aux2
```

- ビルド後イベントで生成された `Aul2MIRAI.dll` を同じ出力フォルダの `Aul2MIRAI.aux2` にコピーする。
- AviUtl2へ配置するファイルは `.aux2` とする。
- Release確定前に、警告とエラーがないこと、および `.aux2` が最新DLLと同一内容であることを確認する。
- 必須exportは `InitializePlugin`、`RegisterPlugin`、`UninitializePlugin` の3つとする。

## FFmpeg

- VideoMinerからコピーした `FFmpegApi.pas` を低レベルAPI境界として使う。
- FFmpeg機能を有効にするまでは `Aul2MIRAI.dpr` と `.dproj` のビルド対象へ追加しない。
- 現在のAPIユニットは、`avutil-60.dll`、`swresample-6.dll`、`swscale-9.dll`、`avcodec-62.dll`、`avformat-62.dll`、`avfilter-11.dll` をロードする。
- FFmpeg DLLは `Aul2MIRAI.aux2` と同じフォルダへ配置する。`Source\Lib` やサブフォルダのままではロードされない。
- FFmpegのレコード配置と関数宣言はFFmpeg 8.1系DLLに対応している。DLLのメジャーバージョンだけを入れ替えない。
- FFmpeg呼び出しから返されたフレーム、パケット、コンテキストは、対応するFFmpeg APIで確実に解放する。
- デコードはAviUtl2のUIスレッドを長時間ブロックしない構成にする。終了処理ではデコード処理を止めてからDLL利用リソースを解放する。
- FFmpegを同梱して配布するときは `Lib\FFmpeg\LICENSE` と配布元の説明を確認し、必要なライセンス文書を同梱する。

## AviUtl2実機確認

- AviUtl2が `Aul2MIRAI.aux2` を正常に読み込むことを確認する。
- プラグイン情報、編集メニュー、クライアントウィンドウの表示名がすべて `AI MIRAI` であることを確認する。
- 編集メニューからウィンドウを表示できることを確認する。
- AviUtl2終了時とプラグイン解除時に例外やアクセス違反が発生しないことを確認する。
- 実機確認が終わるまでは、コンパイル成功だけで完成扱いにしない。

## コメントルール

- コメントは、処理を読めば分かることではなく、目的、責務、注意点、状態の意味を補うために書く。
- 古い仕様や現在の実装と食い違うコメントは、見つけた時点で更新する。
- 不要なコメントや重複したコメントを増やしすぎない。
- `var` ブロック内にローカル関数やローカル手続きを入れ子にしない。必要な補助処理は同じ `implementation` 内の独立した関数・手続きとして分ける。
- ユニット先頭には、そのユニットの目的や担当範囲を `//` コメントで記述する。
- フィールドや定数のコメントは右側に1行で置き、同じブロック内では `:`、`=`、`//` の位置を揃える。
- レコード定義ではフィールド名、`:`、型名、行末の `//` の位置を揃え、各フィールドの用途や値の意味を書く。
- コメントと対象の宣言・実装の間には空行を入れない。
- `interface` に公開する `procedure` / `function` には、呼び出し側から見た責務、入出力、重要な副作用を宣言直前の `//` コメントで書く。
- `property`、`procedure`、`function` 宣言は、横幅112文字以内に収まる場合は折り返さない。
- 日本語の文字列リテラルを持つ `.pas` はUTF-8 BOM付きで保存する。BOMなしUTF-8ではDelphiの文字コード判定が揺れ、GUI表示が文字化けする場合がある。

## 保守ルール

- `README.md` には利用者向けの情報だけを置き、細かい開発メモを増やさない。
- `note.md` には作業再開時に必要な、現在有効な情報だけを置く。
- 完了済みの経緯や検証ログは `HISTORY.md` に移し、`note.md` を肥大化させない。
- コピーした `Source\Lib` のコードを変更する場合は、変更理由とAviUtl2 SDKとの互換性を確認する。
- SDK境界の関数シグネチャ、レコード配置、アラインメント、呼出規約を推測で変更しない。
- 未使用ユニット、古いコピー、ビルド対象外コードをプロジェクト内へ残さない。
