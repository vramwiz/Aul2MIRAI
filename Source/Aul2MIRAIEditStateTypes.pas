unit Aul2MIRAIEditStateTypes;

// 外部へ返す現在の編集状態をSDKポインターを含まない値として保持する。
interface

type
  TAul2MIRAIEditState = record
    ProjectPath       : string;
    SceneName         : string;
    EditMode          : string;
    CapturedAtUtc     : string;
    SceneId           : Integer;
    Width             : Integer;
    Height            : Integer;
    Rate              : Integer;
    Scale             : Integer;
    SampleRate        : Integer;
    CursorFrame       : Integer;
    CursorLayer       : Integer;
    FrameMax          : Integer;
    LayerMax          : Integer;
    DisplayFrameStart : Integer;
    DisplayLayerStart : Integer;
    DisplayFrameNum   : Integer;
    DisplayLayerNum   : Integer;
    SelectRangeStart  : Integer;
    SelectRangeEnd    : Integer;
    GridBpmTempo      : Single;
    GridBpmBeat       : Integer;
    GridBpmOffset     : Single;
    SelectedCount     : Integer;
    ElapsedMs         : UInt64;
  end;

implementation

end.
