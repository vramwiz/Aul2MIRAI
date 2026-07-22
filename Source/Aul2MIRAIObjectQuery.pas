unit Aul2MIRAIObjectQuery;

// 取得済みシーンスナップショットから要求対象だけを抽出する。
interface

uses
  Aul2MIRAIObjectTypes;

procedure KeepObjectsAtCursor(var Snapshot: TAul2MIRAISceneSnapshot);
procedure KeepObjectsInFrameRange(var Snapshot: TAul2MIRAISceneSnapshot;
  StartFrame, EndFrame: Integer);
procedure KeepSelectedObjects(var Snapshot: TAul2MIRAISceneSnapshot);
function KeepObjectByIndex(var Snapshot: TAul2MIRAISceneSnapshot;
  TargetIndex: Integer): Boolean;

implementation

type
  TObjectPredicate = reference to function(
    const Item: TAul2MIRAIObjectInfo): Boolean;

procedure FilterObjects(var Snapshot: TAul2MIRAISceneSnapshot;
  const Predicate: TObjectPredicate);
var
  Count : Integer;
  Item  : TAul2MIRAIObjectInfo;
  ResultItems: TArray<TAul2MIRAIObjectInfo>;
begin
  SetLength(ResultItems, Length(Snapshot.Objects));
  Count := 0;
  for Item in Snapshot.Objects do
    if Predicate(Item) then
    begin
      ResultItems[Count] := Item;
      Inc(Count);
    end;
  SetLength(ResultItems, Count);
  Snapshot.Objects := ResultItems;
end;

procedure KeepObjectsAtCursor(var Snapshot: TAul2MIRAISceneSnapshot);
var
  CursorFrame: Integer;
begin
  CursorFrame := Snapshot.CursorFrame;
  FilterObjects(Snapshot,
    function(const Item: TAul2MIRAIObjectInfo): Boolean
    begin
      Result := (Item.StartFrame <= CursorFrame) and
        (Item.EndFrame >= CursorFrame);
    end);
end;

procedure KeepObjectsInFrameRange(var Snapshot: TAul2MIRAISceneSnapshot;
  StartFrame, EndFrame: Integer);
begin
  FilterObjects(Snapshot,
    function(const Item: TAul2MIRAIObjectInfo): Boolean
    begin
      Result := (Item.StartFrame <= EndFrame) and
        (Item.EndFrame >= StartFrame);
    end);
end;

procedure KeepSelectedObjects(var Snapshot: TAul2MIRAISceneSnapshot);
begin
  FilterObjects(Snapshot,
    function(const Item: TAul2MIRAIObjectInfo): Boolean
    begin
      Result := Item.Selected;
    end);
end;

function KeepObjectByIndex(var Snapshot: TAul2MIRAISceneSnapshot;
  TargetIndex: Integer): Boolean;
begin
  FilterObjects(Snapshot,
    function(const Item: TAul2MIRAIObjectInfo): Boolean
    begin
      Result := Item.Index = TargetIndex;
    end);
  Result := Length(Snapshot.Objects) = 1;
end;

end.
