unit Aul2MIRAIObjectTypes;

// AviUtl2からコピーした読み取り専用スナップショット型を定義する。

interface

type
  TAul2MIRAIParameterInfo = record
    Name      : string;  // エイリアス内の設定項目名
    Value     : string;  // エイリアス内の文字列表現
    Truncated : Boolean; // 安全上の文字数上限で省略したか
  end;

  TAul2MIRAIEffectDetail = record
    Name       : string;
    Parameters : TArray<TAul2MIRAIParameterInfo>;
  end;

  TAul2MIRAIObjectInfo = record
    Index         : Integer; // スナップショット内の連番
    Layer         : Integer; // 0-basedレイヤー番号
    StartFrame    : Integer; // オブジェクト開始フレーム
    EndFrame      : Integer; // オブジェクト終了フレーム
    Selected      : Boolean; // 取得時に選択されていたか
    Focused       : Boolean; // 通常選択のフォーカス対象か
    Name          : string;  // AviUtl2上の表示名
    PrimaryEffect : string;  // エイリアス先頭のeffect.name
    ObjectType    : string;  // 標準オブジェクトの外部向け種類名
    MaterialPath  : string;  // エイリアスにファイル項目がある場合の素材パス
    Effects       : TArray<string>; // 適用されているeffect.name一覧
    EffectDetails : TArray<TAul2MIRAIEffectDetail>; // 詳細要求時の設定一覧
  end;

  TAul2MIRAISceneSnapshot = record
    SceneId       : Integer; // 取得対象のシーンID
    Width         : Integer; // シーン幅
    Height        : Integer; // シーン高さ
    Rate          : Integer; // フレームレート分子
    Scale         : Integer; // フレームレート分母
    CursorFrame   : Integer; // 取得時のカーソルフレーム
    LayerMax      : Integer; // オブジェクトが存在する最大レイヤー番号
    SelectedCount : Integer; // 選択オブジェクト数
    ElapsedMs     : UInt64;  // 読み取り要求全体の経過時間
    Objects       : TArray<TAul2MIRAIObjectInfo>; // コピー済みオブジェクト一覧
  end;

implementation

end.
