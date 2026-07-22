unit Aul2MIRAIObjectFormat;

// 取得済みスナップショットを確認画面用の読みやすいテキストへ整形する。

interface

uses
  Aul2MIRAIObjectTypes;

function FormatSceneSnapshot(const Snapshot: TAul2MIRAISceneSnapshot): string;

implementation

uses
  System.SysUtils,
  System.Classes;

function SingleLine(const Value: string): string;
begin
  Result := StringReplace(Value, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
end;

function FormatSceneSnapshot(const Snapshot: TAul2MIRAISceneSnapshot): string;
var
  Fps        : Double;                // 表示用フレームレート
  Item       : TAul2MIRAIObjectInfo;  // 整形中のオブジェクト
  Lines      : TStringList;           // 画面へ渡す行一覧
  SelectMark : string;                // 選択中オブジェクトの印
begin
  Lines := TStringList.Create;
  try
    if Snapshot.Scale <> 0 then
      Fps := Snapshot.Rate / Snapshot.Scale
    else
      Fps := 0;

    Lines.Add(Format(
      'Scene=%d  Size=%dx%d  FPS=%.3f  Cursor=%d  LayerMax=%d',
      [Snapshot.SceneId, Snapshot.Width, Snapshot.Height, Fps,
       Snapshot.CursorFrame, Snapshot.LayerMax]));
    Lines.Add(Format('Objects=%d  Selected=%d  Read=%d ms',
      [Length(Snapshot.Objects), Snapshot.SelectedCount, Snapshot.ElapsedMs]));
    Lines.Add('');

    for Item in Snapshot.Objects do
    begin
      if Item.Selected then
        SelectMark := '*'
      else
        SelectMark := ' ';

      Lines.Add(Format('%s #%4.4d  L=%d  F=%d-%d  Name="%s"  Effect="%s"',
        [SelectMark, Item.Index, Item.Layer, Item.StartFrame, Item.EndFrame,
         SingleLine(Item.Name), SingleLine(Item.PrimaryEffect)]));
    end;

    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

end.
