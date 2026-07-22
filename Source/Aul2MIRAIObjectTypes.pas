unit Aul2MIRAIObjectTypes;

// AviUtl2からコピーした読み取り専用スナップショット型を定義する。

interface

type
  TAul2MIRAIObjectInfo = record
    Index         : Integer; // スナップショット内の連番
    Layer         : Integer; // 0-basedレイヤー番号
    StartFrame    : Integer; // オブジェクト開始フレーム
    EndFrame      : Integer; // オブジェクト終了フレーム
    Selected      : Boolean; // 取得時に選択されていたか
    Name          : string;  // AviUtl2上の表示名
    PrimaryEffect : string;  // エイリアス先頭のeffect.name
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
