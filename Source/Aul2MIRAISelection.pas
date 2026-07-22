unit Aul2MIRAISelection;

// 通常選択のフォーカス対象と複数選択対象を重複なしで統合する。
interface

uses
  AviUtl2PluginTypes;

type
  TObjectHandleArray = TArray<TObjectHandle>;

function ReadSelectedObjectHandles(Edit: PEditSection;
  out Handles: TObjectHandleArray; out FocusHandle: TObjectHandle;
  out ErrorMessage: string): Boolean;
function ContainsObjectHandle(const Handles: TObjectHandleArray;
  Value: TObjectHandle): Boolean;

implementation

uses
  System.SysUtils;

const
  MAX_SELECTED_OBJECT_COUNT = 100000;

function ContainsObjectHandle(const Handles: TObjectHandleArray;
  Value: TObjectHandle): Boolean;
var
  Item: TObjectHandle;
begin
  for Item in Handles do
    if Item = Value then
      Exit(True);
  Result := False;
end;

procedure AppendUniqueHandle(var Handles: TObjectHandleArray;
  var Count: Integer; Value: TObjectHandle);
var
  Index: Integer;
begin
  if Value = nil then
    Exit;
  for Index := 0 to Count - 1 do
    if Handles[Index] = Value then
      Exit;
  Handles[Count] := Value;
  Inc(Count);
end;

function ReadSelectedObjectHandles(Edit: PEditSection;
  out Handles: TObjectHandleArray; out FocusHandle: TObjectHandle;
  out ErrorMessage: string): Boolean;
var
  Count       : Integer;
  Index       : Integer;
  MultipleCount: Integer;
begin
  SetLength(Handles, 0);
  FocusHandle := nil;
  ErrorMessage := '';
  Result := False;
  if Edit = nil then
  begin
    ErrorMessage := 'AviUtl2 returned no read section.';
    Exit;
  end;

  MultipleCount := Edit^.GetSelectedObjectNum();
  if (MultipleCount < 0) or
     (MultipleCount > MAX_SELECTED_OBJECT_COUNT) then
  begin
    ErrorMessage := 'AviUtl2 returned an invalid selected object count.';
    Exit;
  end;

  SetLength(Handles, MultipleCount + 1);
  Count := 0;
  FocusHandle := Edit^.GetFocusObject();
  AppendUniqueHandle(Handles, Count, FocusHandle);
  for Index := 0 to MultipleCount - 1 do
    AppendUniqueHandle(Handles, Count, Edit^.GetSelectedObject(Index));
  SetLength(Handles, Count);
  Result := True;
end;

end.
