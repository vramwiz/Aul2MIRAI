# AviUtl2カタログ登録

Aul2MIRAIをAviUtl2カタログへ登録・更新するときに再利用する情報と手順。

## 正本

- 登録用JSONは[`Setup/Aul2MIRAI.catalog.json`](Setup/Aul2MIRAI.catalog.json)とする。
- 公式の登録説明は[AviUtl2カタログ用データベースの登録手順](https://github.com/Neosku/aviutl2-catalog-data/blob/main/register-package.md)を参照する。
- JSON形式は[公式`template.json`](https://github.com/Neosku/aviutl2-catalog-data/blob/main/template.json)に合わせる。
- 現行の配布版v0.3.3では、登録画面下部の`JSON入力`へJSON本文を貼り付けてフォームへ反映する。JSONだけで登録は完了せず、インストーラーテストと送信後の審査が必要である。

## 以前の登録から確認した入力規則

`VRAMWIZ.VW_Media_Input`の登録画面と公開カタログデータから次を確認した。

- IDは`作者名.パッケージ名`形式とし、VRAMの魔術師の作者部分は`VRAMWIZ`を使用する。
- GitHub Releaseは`owner`、`repo`、Release資産名に一致する正規表現`pattern`を指定する。
- 公式`template.json`の旧形式は`source.github`を使用するが、新形式は`source.type=githubRelease`と`source.owner`、`source.repo`、`source.pattern`を使用する。登録用JSONには両方を併記し、旧版と新版のどちらでもGitHub Release設定を復元できるようにする。
- インストールは`download`、`extract`、`copy`の順にする。
- バージョン検出対象は配置後の主DLLとし、`{pluginsDir}`からのパスとXXH3-128を記録する。
- アンインストールはカタログが配置したファイルまたは専用フォルダだけを削除する。
- サムネイルと説明画像はJSON入力後に登録画面から補助的に指定できる。

## Aul2MIRAIの登録値

| 項目 | 値 |
| --- | --- |
| ID | `VRAMWIZ.Aul2MIRAI` |
| パッケージ名 | `AI MIRAI` |
| 作者 | `VRAMの魔術師` |
| 種類 | `汎用プラグイン` |
| サイト | `https://github.com/vramwiz/Aul2MIRAI/` |
| ダウンロード元 | GitHub Release |
| Owner | `vramwiz` |
| Repo | `Aul2MIRAI` |
| 資産名パターン | `^Aul2MIRAI\.zip$` |
| 配置先 | `{pluginsDir}/Aul2MIRAI` |
| バージョン検出対象 | `{pluginsDir}/Aul2MIRAI/Aul2MIRAI.aux2` |

## インストールとアンインストール

Release ZIPは`Aul2MIRAI`フォルダをルートに持つ。カタログのフォルダーコピーはコピー元ディレクトリの内容をコピー先へ再帰的に配置するため、ファイルごとのコピー手順は不要である。

GitHub Releaseの`source`には次の互換形式を使用する。旧版は`github`を、新版は`type`と同階層の値を読み、未使用の項目は無視する。

```json
{
  "type": "githubRelease",
  "owner": "vramwiz",
  "repo": "Aul2MIRAI",
  "pattern": "^Aul2MIRAI\\.zip$",
  "github": {
    "owner": "vramwiz",
    "repo": "Aul2MIRAI",
    "pattern": "^Aul2MIRAI\\.zip$"
  }
}
```

インストール:

1. GitHub Releaseから`Aul2MIRAI.zip`をダウンロードする。
2. `{tmp}`へZIP展開する。
3. `{tmp}/Aul2MIRAI`の内容を`{pluginsDir}/Aul2MIRAI`へコピーする。

アンインストール:

1. `{pluginsDir}/Aul2MIRAI`を再帰削除する。

この削除方式を維持するため、Aul2MIRAI専用フォルダへ利用者固有データを保存しない。将来、保持すべき設定や学習データを同フォルダへ置く場合は、フォルダ一括削除をやめて配布ファイル単位の削除へ変更する。

## バージョン履歴

公開済みRelease資産そのものを取得し、ZIP内の`Aul2MIRAI/Aul2MIRAI.aux2`からXXH3-128を計算した。

| バージョン | 公開日 | サイズ | XXH3-128 |
| --- | --- | ---: | --- |
| `v1.0.0` | 2026-07-22 | 2,086,400 bytes | `65ff1ad13803a5af1cb7c0226d55b84a` |
| `v1.0.1` | 2026-07-24 | 2,086,400 bytes | `65ff1ad13803a5af1cb7c0226d55b84a` |

両Releaseの主DLLは同一内容である。カタログv0.3.3はバージョン配列を末尾から判定するため、このハッシュを持つ環境は末尾の`v1.0.1`として検出される。

## 新しいReleaseを登録するとき

1. Releaseビルド後に`Setup/make_release_zip.bat`を実行する。
2. ZIP内のルートが`Aul2MIRAI`、資産名が`Aul2MIRAI.zip`であることを確認する。
3. Gitタグとカタログのバージョン名を同じにする。
4. GitHub Releaseへ`Aul2MIRAI.zip`を添付する。
5. 公開したZIP内の`Aul2MIRAI.aux2`からXXH3-128を計算する。ローカルの別ビルドを代用しない。
6. `Setup/Aul2MIRAI.catalog.json`の`version`末尾へ、バージョン、公開日、配置パス、ハッシュを追加する。
7. AviUtl2カタログの`JSON入力`へ全文を貼り付け、インストールとアンインストールをテストする。
8. サムネイル、説明画像、ニコニ・コモンズIDなどJSONで確定していない補助情報を画面から追加する。

## 登録前に決める項目

- リポジトリにライセンス宣言が見当たらないため、JSONでは`不明`としている。正式なライセンスを決めた場合は、リポジトリとJSONを同時に更新する。
- サムネイルと説明画像は未指定である。
- ニコニ・コモンズIDは未指定である。
- 概要とタグは登録画面で最終確認し、必要なら調整する。
