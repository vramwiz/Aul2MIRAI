unit Aul2MIRAIObjectTypes;

// AviUtl2からコピーした読み取り専用スナップショット型を定義する。

interface

type
  TAul2MIRAILayerInfo = record
    Index   : Integer;
    Name    : string;
    StateAvailable: Boolean;
    Enabled : Boolean;
    Locked  : Boolean;
  end;

  TAul2MIRAIEffectState = record
    Name    : string;
    Enabled : Boolean;
    Locked  : Boolean;
  end;

  TAul2MIRAIParameterInfo = record
    Name      : string;  // エイリアス内の設定項目名
    Value     : string;  // エイリアス内の文字列表現
    Truncated : Boolean; // 安全上の文字数上限で省略したか
    TrackInfoAvailable: Boolean;
    TrackMode : string;
    TrackParameters: TArray<Double>;
    TrackAccelerate: Boolean;
    TrackDecelerate: Boolean;
    TrackIgnoreMidpoint: Boolean;
    TrackTimeControl: Boolean;
    TrackGroupCount: Integer;
    TrackGroupIndex: Integer;
    TrackGroupName: string;
  end;

  TAul2MIRAIEffectDetail = record
    Name       : string;
    StateAvailable: Boolean;
    Enabled    : Boolean;
    Locked     : Boolean;
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
    EffectStates  : TArray<TAul2MIRAIEffectState>; // 全エフェクトの有効・ロック状態
    SectionFrames : TArray<Integer>; // 各区間（中間点を含む）の開始フレーム
    FocusedSection: Integer; // 選択中の区間番号。対象外は-1
    ContentDigest : string;  // エイリアス内容のSHA-256
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
    Layers        : TArray<TAul2MIRAILayerInfo>; // レイヤー名・表示・ロック状態
  end;

implementation

end.
