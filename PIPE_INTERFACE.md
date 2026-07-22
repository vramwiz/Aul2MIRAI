# AI MIRAI Named Pipe通信仕様

この文書は、Aul2MIRAIプラグインと外部呼び出し側の間で使用するNamed Pipe通信の開発者向け仕様を記録する。プロジェクト全体の方針と課題は[`note.md`](note.md)、Codexが実際に使用する操作手順は[`AI_USAGE.md`](AI_USAGE.md)へ記載する。

## 基本構成

- 専用クライアントEXEは作成・配布・使用しない。
- サーバーはAviUtl2に読み込まれた`Aul2MIRAI.aux2`内で動作する。
- 呼び出し側はPowerShell標準の`NamedPipeClientStream`を使用する。
- 要求と応答はUTF-8 JSONとする。
- 読み取りに加え、選択中オブジェクトの単一設定値を安全条件付きで変更できる。

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

## 応答の状態識別

成功応答のルートには次のメタデータを付ける。

| フィールド | 内容 |
| --- | --- |
| `snapshot_id` | 要求ごとに生成するUUID。同じ状態を連続取得しても毎回異なる。 |
| `state_token` | 編集状態を正規化してSHA-256で計算した状態指紋。同じ状態では一致する。 |
| `captured_at_utc` | 状態を取得したUTC日時。 |

`state_token`の計算対象:

- プロジェクトパス、シーンID、シーン名
- 解像度、フレームレート、サンプリングレート
- カーソル、表示範囲、選択範囲、BPM
- 通常選択・複数選択の状態
- 全レイヤーの名前、有効・ロック状態
- 全オブジェクトのレイヤー、開始・終了フレーム、表示名
- 各オブジェクトの区間開始フレーム、フォーカス区間
- 各エフェクトの名前、有効・ロック状態
- 各オブジェクトのエイリアス内容をSHA-256化した`content_digest`

取得日時、処理時間、`snapshot_id`は`state_token`へ含めない。編集要求では、呼び出し側が取得時の`state_token`を渡し、現在値と一致しない要求を拒否する。

## 処理の流れ

1. `PipeServerTThread`がワーカースレッドで接続と受信を待つ。
2. JSON要求を受信したら、`WM_PIPE_NOTIFY`をAI MIRAIウィンドウへ送る。
3. AviUtl2のUIスレッドで要求を検証する。
4. UIスレッドからAviUtl2 SDKの読み取り処理を呼ぶ。
5. 画像取得ではUIスレッドからレンダリングを要求し、SDKのレンダリングスレッドから渡されたRGBAを一時BMPへコピーする。
6. 取得結果を通常のDelphiデータへコピーし、JSON応答を生成する。
7. PipeスレッドがUTF-8 JSONをクライアントへ返す。
8. クライアントは応答全体を読み終えてから接続を閉じる。

AviUtl2 SDKへアクセスする処理はPipeのワーカースレッドで直接実行しない。

## プロトコル

プロトコル名は`Aul2MIRAI`、バージョンは`1`とする。

現在使用できるコマンド:

| コマンド | 内容 |
| --- | --- |
| `get_edit_state` | プロジェクト、シーン、カーソル、選択範囲、表示範囲などの編集状態を取得する。 |
| `get_scene_objects` | 現在編集中のシーンと、そのシーンにあるオブジェクト一覧を取得する。 |
| `get_objects_at_cursor` | 現在のカーソルフレームと重なるオブジェクトと、そのエフェクト設定値を取得する。 |
| `get_objects_in_selection` | 現在の選択範囲と一部でも重なるオブジェクトと、そのエフェクト設定値を取得する。 |
| `get_selected_objects` | 通常選択のフォーカス対象と複数選択対象を統合し、エフェクト設定値とともに取得する。 |
| `get_object_details` | 最新状態の`index`を指定し、単一オブジェクトの詳細を取得する。 |
| `get_current_frame_image` | 現在のカーソルフレームをレンダリングし、一時BMPのパスと寸法を返す。 |
| `preview_set_object_parameter` | 選択オブジェクトの設定値変更を検証し、変更前後の値を返す。実際の変更は行わない。 |
| `set_object_parameter` | 選択オブジェクトの単一設定値を変更し、書込み後の検証値と新しい状態指紋を返す。 |
| `preview_set_object_parameters` | 最大64件の設定値変更を一括検証する。実際の変更は行わない。 |
| `set_object_parameters` | 検証済みの最大64件を1回の編集コールバックで一括変更する。 |
| `preview_move_objects` | 最大64個の選択オブジェクトについて移動先と衝突を検証する。 |
| `move_objects` | 検証済みの最大64個を1回の編集コールバックで移動する。 |
| `preview_duplicate_objects` | 最大64件の複製元と生成先を検証する。 |
| `duplicate_objects` | 検証済みの最大64件を1回の編集コールバックで複製する。 |
| `preview_set_edit_position` | カーソル位置と選択範囲の変更予定を検証する。 |
| `set_edit_position` | カーソル位置と選択範囲を設定または解除する。 |

要求例:

```json
{
  "protocol": "Aul2MIRAI",
  "protocol_version": 1,
  "command": "get_scene_objects"
}
```

成功応答とエラー応答のフィールド定義は[`AI_USAGE.md`](AI_USAGE.md)を参照する。

`get_objects_in_selection`は選択範囲の開始・終了フレームを含む範囲と、1フレーム以上重なるオブジェクトを全レイヤーから返す。選択範囲が設定されていない場合は`selection_range_not_set`として拒否する。オブジェクトの設定詳細も取得する。

`get_object_details`は`state_token`と0-basedの`target_index`を要求する。`state_token`が現在状態と異なる場合は`state_changed`、対象が存在しない場合は`target_not_found`として拒否する。詳細取得は指定した1件だけに限定し、他オブジェクトの設定値は展開しない。応答形式はオブジェクト一覧と共通で、`snapshot.objects`が対象1件だけを含む。

`get_current_frame_image`は`get_edit_info`で取得した現在のカーソルフレームを`rendering_scene_video`へ渡す。参照・編集ロックの外側でレンダリングを要求し、`wait_rendering_task`で完了後に応答する。RGBAはBGRAへ変換して上端から格納する32bit BMPとし、`%TEMP%\Aul2MIRAI`以下へ一意な名前で保存する。要求から出力先を指定する機能は設けず、既存ファイルを上書きしない。応答にはファイルパス、形式、フレーム、幅、高さ、ファイルサイズ、処理時間を返す。

## 設定値変更プレビュー

`preview_set_object_parameter`は次の値を要求する。

| フィールド | 内容 |
| --- | --- |
| `state_token` | 対象を取得したときの状態指紋。現在状態と一致しなければ拒否する。 |
| `target_index` | `get_selected_objects`で返されたオブジェクトの`index`。 |
| `effect_index` | `effect_details`配列内の0-based番号。 |
| `item` | 設定項目名。 |
| `value` | 変更後として検証する文字列。最大16,384文字。 |

プレビューは選択中のオブジェクトだけを対象とする。成功応答の`preview.applied`は常に`false`であり、`before`、`after`、`will_change`を返す。古い状態は`state_changed`、存在しない対象は`target_not_found`、未選択対象は`target_not_selected`として拒否する。

## 設定値の変更

`set_object_parameter`はプレビューと同じフィールドに加えて、JSON Booleanの`apply: true`を必須とする。文字列`"true"`や`apply: false`では変更しない。

処理時は次の条件をすべて確認する。

1. `state_token`が現在状態と一致する。
2. 対象が現在も選択中で、レイヤー、開始・終了フレーム、内容ハッシュが一致する。
3. エフェクトと設定項目が存在し、変更前の値が取得時と一致する。
4. AviUtl2の`call_edit_section_param`内で1件だけ書き込む。
5. 書込み直後に同じ項目を再取得し、要求値と一致する。
6. 編集後の状態を再取得し、新しい`state_token`を応答する。

同値指定は成功とするが書込みを実行せず、`change.applied=false`、`change.changed=false`を返す。実変更時は`change.applied=true`となり、`before`、`requested`、`verified`を返す。1要求の変更はAviUtl2 SDKにより1つのUndo単位へ登録される。

## 複数設定値の一括変更

`preview_set_object_parameters`と`set_object_parameters`は、単一変更の`target_index`、`effect_index`、`item`、`value`を`changes`配列で指定する。件数は1～64件とする。実変更ではルートに`apply: true`も必要となる。

一括変更では、全項目の対象、選択状態、内容ハッシュ、変更前値を1件も書き込む前に検証する。同じ対象・エフェクト・項目の重複指定は`duplicate_change`として拒否する。検証後は1回の`call_edit_section_param`内で変更し、各項目を直後に再取得する。途中の書込みまたは再取得検証に失敗した場合は、そのコールバック内で適用済み項目を変更前の値へ戻す。

成功応答には`change_count`、実際に値が変わる`changed_count`、各項目の`before`、`requested`、`verified`を返す。全項目が同値なら書込みを行わず、`applied=false`、`changed_count=0`となる。

## オブジェクト移動

`preview_move_objects`と`move_objects`は、`moves`配列へ`target_index`、移動先の0-based `layer`と`frame`を指定する。件数は1～64個とし、実移動ではルートに`apply: true`も必要となる。

移動対象は選択中オブジェクトだけに限定する。対象位置、終了フレーム、内容ハッシュ、選択状態を移動直前にも再検証する。移動後の終了フレームは元の長さを維持して計算し、SDKから再取得した配置範囲が要求と一致することを確認する。

移動先が他オブジェクトの現在範囲と重なる場合は`destination_occupied`、同一要求内の別移動先と重なる場合は`destination_conflict`として、書込み前に拒否する。同じ対象を2回指定した場合は`duplicate_move`とする。途中失敗時は同じ編集コールバック内で適用済み移動を元位置へ戻す。

成功応答には`move_count`、実際に位置が変わる`moved_count`、各対象の`before`と`after`を返す。全対象が同じ位置なら移動を行わず、`applied=false`、`moved_count=0`となる。1要求が1回のUndo単位となる。

現在は安全を優先し、別の移動対象が退避する予定であっても、その現在位置を移動先には指定できない。このためオブジェクト同士の位置交換や連鎖的な詰め替えは未対応とする。

## オブジェクト複製

`preview_duplicate_objects`と`duplicate_objects`は、`duplicates`配列へ`source_index`、生成先の0-based `layer`と`frame`を指定する。件数は1～64件とし、実複製ではルートに`apply: true`も必要となる。同じ複製元を複数の空き位置へ指定できる。

複製元は選択中オブジェクトだけに限定する。元の配置範囲、内容ハッシュ、選択状態を生成直前にも再検証し、SDKの`create_object_from_alias`へ複製元のUTF-8エイリアスとフレーム数を渡す。生成後は配置範囲、表示名、オブジェクト種類、エフェクト順、全設定項目名・値をコールバック内で照合する。

生成先が既存オブジェクトと重なる場合は`destination_occupied`、同一要求内の別生成先と重なる場合は`destination_conflict`として全生成前に拒否する。途中失敗時は同じ編集コールバック内で生成済みオブジェクトを削除する。

成功応答には`duplicate_count`と、各生成物の応答時点の`created_index`、生成範囲を返す。1要求が1回のUndo単位となる。`created_index`は他の`index`と同様に永続識別子ではない。

AviUtl2は生成時にエイリアスの内部記述を正規化するため、設定内容が同じ複製でも`content_digest`が複製元と異なる場合がある。複製の同一性は`content_digest`単独ではなく、生成時に照合した設定内容と配置、種類で判断する。

## カーソル位置と選択範囲

`preview_set_edit_position`と`set_edit_position`は、ルートの`cursor`と`selection`の少なくとも一方を指定する。

```json
{
  "cursor": { "layer": 0, "frame": 100 },
  "selection": { "start_frame": 50, "end_frame": 120 }
}
```

選択範囲を解除する場合は`selection: null`とする。カーソルのレイヤーとフレーム、選択範囲は現在シーンの`layer_max`と`frame_max`内に限定する。実設定では`state_token`と`apply: true`を必須とし、編集コールバック内でも変更前のカーソルと選択範囲を再確認する。

成功応答にはカーソルと選択範囲それぞれの`requested`、`will_change`、変更前後を返す。同値指定は`applied=false`となる。設定後は編集状態を再取得して要求値と一致することを確認し、新しい`state_token`を返す。

カーソルと選択範囲はプロジェクト内容の編集ではなくUI状態であり、Undo対象にはしない。

## シーン操作のSDK制限

AviUtl2 v2.10の公開SDKには、現在シーンのID・名前取得とシーン変更通知はあるが、シーン一覧の列挙、別シーンへの切り替え、シーン追加を行うAPIはない。AI MIRAIでは非公開内部APIへ依存せず、これらの操作は公開SDKが拡張されるまで未対応とする。

## オブジェクト長変更のSDK制限

AviUtl2 v2.10の公開SDKには、既存オブジェクトの終了フレームまたは長さを直接変更するAPIがない。削除後にエイリアスから再生成する方法は、連結、中間点、外部プラグイン固有情報を損なう可能性があるため、長さ変更の代替手段には使用しない。公開APIで安全に変更できるようになるまで未対応とする。

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
- 読み取り7コマンド、単一・一括の変更プレビューと設定値変更コマンドを公開している。
- Pipeのアクセス制御はコピー元ライブラリの既定動作を使用しており、明示的なセキュリティ記述子はまだ設定していない。
- 現在の一括変更上限は64件であり、これを超える大規模変更やページ分割は扱わない。
- 移動先が別の移動対象の現在位置に重なる入れ替え・連鎖移動は扱わない。
- 複製は単一オブジェクトのエイリアスを対象とし、複数オブジェクトを含む外部エイリアスの投入は扱わない。
- 公開SDKに列挙・切り替え・追加APIがないため、シーン操作は扱わない。
- 公開SDKに既存オブジェクトの終了フレーム・長さ変更APIがないため、長さ変更は扱わない。
- 応答が大きくなる場合は、上限、分割方式、またはページングを定義する必要がある。
- エフェクトは1オブジェクト256件、設定項目は合計2,048件、各設定値は16,384文字を上限とする。上限を超えた設定値は`truncated`で示す。
- 区間開始フレームは1オブジェクト4,096件を上限とする。
- 現在フレーム画像は一時BMPとして残り、自動削除しない。利用後の削除は呼び出し側が行う。
- 古いAviUtl2でエフェクト状態APIが利用できない場合、`effect_states`は空配列、`effect_details[].state_available`は`false`となる。
- 公開SDKには複数オブジェクトのグループ・連結関係を列挙するAPIがない。単一オブジェクトの`get_object_alias`ではプロジェクト内の`group=`情報も返らないため、関係を推測して公開しない。
- `track_info.group`はエフェクト内のトラックバー項目グループであり、複数オブジェクトのグループではない。

## 確認済み事項

- Windows 11上でPowerShellの`NamedPipeClientStream`から直接接続できる。
- 専用クライアントEXEを使用せずJSON応答を取得できる。
- 実プロジェクトで`get_scene_objects`から4オブジェクトを31 msで取得できた。
- 保存済みプロジェクトからプロジェクトパス、シーン名、表示・選択状態を取得できる。
- カーソルフレームと重なるオブジェクトだけを抽出できる。
- 画像オブジェクトを`image`として分類し、素材パスとエフェクト一覧を取得できる。
- カーソル位置の画像オブジェクトから、画像ファイルと標準描画の設定項目名・値を取得できる。
- `get_focus_object`と複数選択APIを統合し、通常選択のオブジェクトを`selected: true`、`focused: true`として取得できる。
- `audio_test.aup2`で通常選択された`グループ制御(音声)`を1件取得し、2エフェクト、106設定項目、切り捨て0件を確認した。
- 同一状態を3回取得した場合、`state_token`が一致し、`snapshot_id`が3件とも異なることを確認した。
- カーソル変更と、同一プロジェクトパスでのオブジェクト設定値変更のそれぞれで`state_token`が変化することを確認した。
- 画像オブジェクトの`表示番号`を0から1へ変更するプレビューで、`applied=false`、`will_change=true`、実値と`state_token`が不変であることを確認した。
- 同じ値0のプレビューで`will_change=false`、古いトークンで`state_changed`、存在しない対象で`target_not_found`を確認した。
- `set_object_parameter`で画像の`表示番号`を0から1へ変更し、直後の再取得で1、新しい`state_token`、`verified=1`を確認した。
- 更新後トークンを使って1から0へ戻し、再取得で元の値0を確認した。`apply=false`は`apply_required`、古いトークンは`state_changed`として拒否された。
- 一括変更で画像の`表示番号`と`標準描画.X`を同時に変更し、2項目の検証値、状態指紋の変化、再取得値を確認した。同じ一括経路で両方を元の値へ戻した。
- 重複項目は`duplicate_change`、2件目の存在しない項目は全書込み前に`item_not_found`となり、同値2件では`applied=false`、`changed_count=0`となることを確認した。
- 選択画像をレイヤー0・144～224フレームからレイヤー1・300～380フレームへ移動し、再取得後に元位置へ戻した。
- 移動の`apply=false`、重複対象、古いトークン、同位置指定を確認した。既存音声オブジェクトと重なる移動先は`destination_occupied`となり、位置と状態指紋が不変であることを確認した。
- 選択画像をレイヤー1・300～380フレームへ複製し、生成後の2オブジェクト、`created_index`、種類、エフェクト構成、設定値を確認した。
- 複製の`apply=false`、未選択元、古いトークン、既存オブジェクトとの重なり、同一要求内の生成先重複を確認した。テスト終了後に未保存で再起動し、元の1オブジェクトだけであることを確認した。
- カーソルを144から100フレームへ移動し、選択範囲50～120を設定した後、カーソル144と選択解除へ戻した。同値、範囲外、`apply=false`、古いトークンの挙動を確認した。
- `audio_test.aup2`で選択範囲0～49と重なる3オブジェクトを取得し、50フレーム開始のカメラ制御が除外されることを確認した。範囲解除後は`selection_range_not_set`となることも確認した。
- `get_object_details`で`audio_test.aup2`のindex 0を1件だけ取得し、カメラ制御の設定詳細を確認した。存在しないindex、負のindex、古い`state_token`がそれぞれ`target_not_found`、`invalid_target_index`、`state_changed`となることを確認した。
- 選択範囲取得の3オブジェクトすべてに設定詳細が含まれることを確認した。
- v2.1.0の`audio_test.aup2`で158設定項目中106項目のトラックバー情報を取得し、`再生範囲`移動モードと、映像再生のXYZ・回転XYZの各3項目グループを確認した。
- beta50でも同じ106項目のトラックバー情報を取得でき、既存の互換処理と共存することを確認した。
- プロジェクトファイルに`group=1/2`を持つ`serif_test.aup2`で、SDKの`get_object_alias`にはグループ行が含まれないことを確認した。複数オブジェクトのグループ関係取得は未対応とした。
- AviUtl2 v2.1.0でレイヤー名と有効・ロック状態、オブジェクトの区間開始フレームとフォーカス区間、各エフェクトの有効・ロック状態を取得できた。
- `audio_test.aup2`の4オブジェクトで、標準エフェクトに加えて外部エフェクト`Aul2Audio View`の有効・ロック状態も取得できた。
- AviUtl2 beta50では、後から追加されたエフェクト状態APIがなくても要求全体を失敗させず、`state_available=false`として共通情報を取得できた。
- AviUtl2 v2.1.0の空プロジェクトと`audio_test.aup2`で現在フレームを1920×1080のBMPへ保存し、画像の上下方向とRGB色、画像取得前後の状態指紋が正常であることを確認した。
