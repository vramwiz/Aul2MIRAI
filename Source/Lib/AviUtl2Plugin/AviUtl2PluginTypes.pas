unit AviUtl2PluginTypes;

{
  AviUtl2PluginTypes.pas
  ----------------------------------------------------------------------
  AviUtl2 beta23a（ExEdit2 汎用プラグイン SDK）完全対応版

  2025  VRAMWIZ Project
}

interface

uses
  Winapi.Windows;

type
  {------------------------------------------------------------------
    基本ポインタ型
  ------------------------------------------------------------------}
  TObjectHandle = Pointer;
  LPCSTR  = PAnsiChar;
  LPCWSTR = PWideChar;

  {------------------------------------------------------------------
    MEDIA_INFO （C++版に完全一致）
  ------------------------------------------------------------------}
  TMediaInfo = record
    VideoTrackNum: Integer;
    AudioTrackNum: Integer;
    TotalTime: Double;   // seconds
    Width: Integer;
    Height: Integer;
  end;
  PMediaInfo = ^TMediaInfo;

  {------------------------------------------------------------------
    OBJECT_LAYER_FRAME（C++版）
  ------------------------------------------------------------------}
  TObjectLayerFrame = record
    Layer     : Integer;
    StartFrame: Integer;
    EndFrame  : Integer;
  end;

  {------------------------------------------------------------------
    EDIT_INFO（C++版と完全一致）
  ------------------------------------------------------------------}
  PEditInfo = ^TEditInfo;
  TEditInfo = record
    Width, Height: Integer;         // 解像度
    Rate, Scale: Integer;           // フレームレート
    SampleRate: Integer;            // 音声サンプリングレート

    Frame, Layer: Integer;          // 現在位置
    FrameMax, LayerMax: Integer;    // 最大値

    DisplayFrameStart: Integer;
    DisplayLayerStart: Integer;
    DisplayFrameNum: Integer;
    DisplayLayerNum: Integer;

    SelectRangeStart: Integer;
    SelectRangeEnd: Integer;

    GridBpmTempo: Single;
    GridBpmBeat: Integer;
    GridBpmOffset: Single;

    SceneId: Integer;               // beta29: シーンID
  end;

  {------------------------------------------------------------------
    PROJECT_FILE（C++版と完全一致）
  ------------------------------------------------------------------}
  PProjectFile = ^TProjectFile;
  TProjectFile = record
    GetParamString: function(Key: LPCSTR): LPCSTR; cdecl;
    SetParamString: procedure(Key, Value: LPCSTR); cdecl;

    GetParamBinary: function(Key: LPCSTR; Data: Pointer; Size: Integer): BOOL; cdecl;
    SetParamBinary: procedure(Key: LPCSTR; Data: Pointer; Size: Integer); cdecl;

    ClearParams: procedure(); cdecl;

    GetProjectFilePath: function(): LPCWSTR; cdecl;
  end;

  {------------------------------------------------------------------
    EDIT_SECTION（C++ SDK の定義を完全に再現）
  ------------------------------------------------------------------}
  PEditSection = ^TEditSection;
  TEditSection = record
    Info: PEditInfo;

    { 1. オブジェクト生成・検索 }
    CreateObjectFromAlias: function(Alias: LPCSTR; Layer, Frame, Length: Integer): TObjectHandle; cdecl;
    FindObject: function(Layer, Frame: Integer): TObjectHandle; cdecl;

    { 2. エフェクト数 }
    CountObjectEffect: function(Obj: TObjectHandle; Effect: LPCWSTR): Integer; cdecl;

    { 3. オブジェクト情報 }
    GetObjectLayerFrame: function(Obj: TObjectHandle): TObjectLayerFrame; cdecl;
    GetObjectAlias: function(Obj: TObjectHandle): LPCSTR; cdecl;

    { 4. 設定項目の参照・更新 }
    GetObjectItemValue: function(Obj: TObjectHandle; Effect, Item: LPCWSTR): LPCSTR; cdecl;
    SetObjectItemValue: function(Obj: TObjectHandle; Effect, Item: LPCWSTR; Value: LPCSTR): BOOL; cdecl;

    { 5. オブジェクト操作 }
    MoveObject: function(Obj: TObjectHandle; Layer, Frame: Integer): BOOL; cdecl;
    DeleteObject: procedure(Obj: TObjectHandle); cdecl;

    { 6. フォーカス操作 }
    GetFocusObject: function(): TObjectHandle; cdecl;
    SetFocusObject: procedure(Obj: TObjectHandle); cdecl;

    { 7. プロジェクトファイル }
    GetProjectFile: function(EditHandle: Pointer): PProjectFile; cdecl;

    { 8. 選択状態 }
    GetSelectedObject: function(Index: Integer): TObjectHandle; cdecl;
    GetSelectedObjectNum: function(): Integer; cdecl;

    { 9. マウス・座標変換 }
    GetMouseLayerFrame: function(Layer, Frame: PInteger): BOOL; cdecl;
    PosToLayerFrame: function(X, Y: Integer; Layer, Frame: PInteger): BOOL; cdecl;

    { 10. メディア関連 }
    IsSupportMediaFile: function(FileName: LPCWSTR; Strict: BOOL): BOOL; cdecl;
    GetMediaInfo: function(FileName: LPCWSTR; Info: PMediaInfo; InfoSize: Integer): BOOL; cdecl;
    CreateObjectFromMediaFile: function(FileName: LPCWSTR; Layer, Frame, Length: Integer): TObjectHandle; cdecl;

    { 11. 汎用オブジェクト生成 }
    CreateObject: function(Effect: LPCWSTR; Layer, Frame, Length: Integer): TObjectHandle; cdecl;

    { 12. カーソル／表示位置 }
    SetCursorLayerFrame: procedure(Layer, Frame: Integer); cdecl;
    SetDisplayLayerFrame: procedure(Layer, Frame: Integer); cdecl;
    SetSelectRange: procedure(StartFrame, EndFrame: Integer); cdecl;

    { 13. グリッド }
    SetGridBpm: procedure(Tempo: Single; Beat: Integer; Offset: Single); cdecl;

    { 14. 名前取得 }
    GetObjectName: function(Obj: TObjectHandle): LPCWSTR; cdecl;
    SetObjectName: procedure(Obj: TObjectHandle; Name: LPCWSTR); cdecl;

    { 15. レイヤー名取得 }
    GetLayerName: function(Layer: Integer): LPCWSTR; cdecl;
    SetLayerName: procedure(Layer: Integer; Name: LPCWSTR); cdecl;

    { 16. シーン名取得 }
    GetSceneName: function(): LPCWSTR; cdecl;
    SetSceneName: procedure(Name: LPCWSTR); cdecl;

    { 17. シーン設定 }
    SetSceneSize: procedure(Width, Height: Integer); cdecl;
    SetSceneFrameRate: procedure(Rate, Scale: Integer); cdecl;
    SetSceneSampleRate: procedure(SampleRate: Integer); cdecl;
  end;


  {------------------------------------------------------------------
    編集ハンドル（C++版完全対応）
  ------------------------------------------------------------------}
  TProcEditSection = procedure(Edit: PEditSection); cdecl;
  TProcEditSectionParam = procedure(Param: Pointer; Edit: PEditSection); cdecl;
  // シーン変更通知コールバック
  TProcSceneChange = procedure(Edit: PEditSection); cdecl;

  PEditHandle = ^TEditHandle;
  TEditHandle = record
    CallEditSection: function(Func: TProcEditSection): BOOL; cdecl;
    CallEditSectionParam: function(Param: Pointer; Func: TProcEditSectionParam): BOOL; cdecl;
    GetEditInfo: procedure(Info: PEditInfo; InfoSize: Integer); cdecl;
    RestartHostApp: procedure; cdecl;
    EnumEffectName: Pointer;
    EnumModuleInfo: Pointer;
    GetHostAppWindow: function: HWND; cdecl;
    GetEditState: function: Integer; cdecl;
  end;

type
  { プロジェクト保存・読込コールバック }
  TProjectCallback = procedure(Project: PProjectFile); cdecl;

  { Config メニューのコールバック }
  TConfigMenuCallback = procedure(hWnd: HWND; hInst: HINST); cdecl;

  {------------------------------------------------------------------
    プラグイン登録テーブル（C++ SDK 完全再現）
  ------------------------------------------------------------------}
  PInputPluginTable  = Pointer;
  POutputPluginTable = Pointer;
  PFilterPluginTable = Pointer;
  PScriptModuleTable = Pointer;

  PHostAppTable = ^THostAppTable;
  THostAppTable = record
    SetPluginInformation: procedure(Information: LPCWSTR); cdecl;

    RegisterInputPlugin: procedure(Table: PInputPluginTable); cdecl;
    RegisterOutputPlugin: procedure(Table: POutputPluginTable); cdecl;
    RegisterFilterPlugin: procedure(Table: PFilterPluginTable); cdecl;
    RegisterScriptModule: procedure(Table: PScriptModuleTable); cdecl;

    RegisterImportMenu: procedure(Name: LPCWSTR; Func: TProcEditSection); cdecl;
    RegisterExportMenu: procedure(Name: LPCWSTR; Func: TProcEditSection); cdecl;

    RegisterWindowClient: procedure(Name: LPCWSTR; HWnd: HWND); cdecl;

    CreateEditHandle: function(): PEditHandle; cdecl;

    // ★ 修正済み：無名プロシージャは不可
    RegisterProjectLoadHandler: procedure(Func: TProjectCallback); cdecl;
    RegisterProjectSaveHandler: procedure(Func: TProjectCallback); cdecl;

    RegisterLayerMenu: procedure(Name: LPCWSTR; Func: TProcEditSection); cdecl;
    RegisterObjectMenu: procedure(Name: LPCWSTR; Func: TProcEditSection); cdecl;

    // ★ 修正済み：ConfigMenu コールバックも型化
    RegisterConfigMenu: procedure(Name: LPCWSTR; Func: TConfigMenuCallback); cdecl;
    // 編集メニューを登録する
    // name					: 編集メニューの名称 ※名称に'\'を入れると表示を階層に出来ます
    // func_proc_edit_menu	: 編集メニュー選択時のコールバック関数
    RegisterEditMenu: procedure(Name: LPCWSTR; Func: TProcEditSection); cdecl;

    // キャッシュを破棄の操作時に呼ばれる関数を登録する
    // func_proc_clear_cache	: キャッシュの破棄時のコールバック関数
    RegisterClearCacheHandler: procedure(Func: TProcEditSection); cdecl;
    RegisterChangeSceneHandler: procedure(Func: TProcSceneChange); cdecl;
  end;

implementation
end.

