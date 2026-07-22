unit Aul2MIRAIFrameCapture;

// 現在シーンの指定フレームをRGBAから一時BMPへ安全に書き出す。
interface

uses
  AviUtl2PluginTypes;

type
  TAul2MIRAIFrameImage = record
    FilePath      : string;
    Format        : string;
    CapturedAtUtc : string;
    Frame         : Integer;
    Width         : Integer;
    Height        : Integer;
    FileSize      : Int64;
    ElapsedMs     : UInt64;
  end;

// 指定フレームを自動生成した一時BMPへ保存し、保存結果を返す。
function CaptureSceneFrame(EditHandle: PEditHandle; Frame: Integer;
  out Image: TAul2MIRAIFrameImage; out ErrorMessage: string): Boolean;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.DateUtils,
  System.IOUtils,
  System.SysUtils;

const
  MAX_FRAME_IMAGE_DIMENSION = 16384;
  MAX_FRAME_IMAGE_BYTES     = Int64(1024) * 1024 * 1024;

type
  TBmpFileHeader = packed record
    FileType  : Word;
    FileSize  : Cardinal;
    Reserved1 : Word;
    Reserved2 : Word;
    DataOffset: Cardinal;
  end;

  TBmpInfoHeader = packed record
    HeaderSize     : Cardinal;
    Width          : Integer;
    Height         : Integer;
    Planes         : Word;
    BitCount       : Word;
    Compression    : Cardinal;
    ImageSize      : Cardinal;
    XPelsPerMeter  : Integer;
    YPelsPerMeter  : Integer;
    ColorsUsed     : Cardinal;
    ColorsImportant: Cardinal;
  end;

  TFrameCaptureContext = class
  public
    FilePath    : string;
    ErrorMessage: string;
    Completed   : Boolean;
    Width       : Integer;
    Height      : Integer;
    FileSize    : Int64;
  end;

function NewCaptureFilePath(Frame: Integer): string;
var
  Directory: string;
  Id       : TGUID;
  IdText   : string;
begin
  Directory := TPath.Combine(TPath.GetTempPath, 'Aul2MIRAI');
  ForceDirectories(Directory);
  if CreateGUID(Id) <> 0 then
    RaiseLastOSError;
  IdText := LowerCase(GUIDToString(Id));
  IdText := Copy(IdText, 2, Length(IdText) - 2);
  Result := TPath.Combine(Directory,
    Format('frame_%d_%s.bmp', [Frame, IdText]));
end;

procedure SaveRgbaBitmap(const FilePath: string; Buffer: Pointer;
  Width, Height, Pitch: Integer; out FileSize: Int64);
var
  DataSize : Int64;
  Dest     : PByte;
  FileHeader: TBmpFileHeader;
  InfoHeader: TBmpInfoHeader;
  Row      : TBytes;
  Source   : PByte;
  Stream   : TFileStream;
  X        : Integer;
  Y        : Integer;
begin
  if Buffer = nil then
    raise EArgumentNilException.Create('Rendered pixel buffer is nil.');
  if (Width <= 0) or (Height <= 0) or
     (Width > MAX_FRAME_IMAGE_DIMENSION) or
     (Height > MAX_FRAME_IMAGE_DIMENSION) then
    raise ERangeError.Create('Rendered image dimensions are invalid.');
  if Pitch < Width * 4 then
    raise ERangeError.Create('Rendered image pitch is invalid.');

  DataSize := Int64(Width) * Height * 4;
  if DataSize > MAX_FRAME_IMAGE_BYTES then
    raise ERangeError.Create('Rendered image is too large.');

  FileHeader := Default(TBmpFileHeader);
  FileHeader.FileType := $4D42;
  FileHeader.DataOffset := SizeOf(FileHeader) + SizeOf(InfoHeader);
  FileHeader.FileSize := FileHeader.DataOffset + Cardinal(DataSize);

  InfoHeader := Default(TBmpInfoHeader);
  InfoHeader.HeaderSize := SizeOf(InfoHeader);
  InfoHeader.Width := Width;
  InfoHeader.Height := -Height;
  InfoHeader.Planes := 1;
  InfoHeader.BitCount := 32;
  InfoHeader.Compression := BI_RGB;
  InfoHeader.ImageSize := Cardinal(DataSize);

  SetLength(Row, Width * 4);
  Stream := TFileStream.Create(FilePath, fmCreate or fmShareExclusive);
  try
    Stream.WriteBuffer(FileHeader, SizeOf(FileHeader));
    Stream.WriteBuffer(InfoHeader, SizeOf(InfoHeader));
    for Y := 0 to Height - 1 do
    begin
      Source := PByte(NativeInt(Buffer) + NativeInt(Y) * Pitch);
      Dest := Pointer(Row);
      for X := 0 to Width - 1 do
      begin
        PByte(NativeInt(Dest) + 0)^ := PByte(NativeInt(Source) + 2)^;
        PByte(NativeInt(Dest) + 1)^ := PByte(NativeInt(Source) + 1)^;
        PByte(NativeInt(Dest) + 2)^ := PByte(NativeInt(Source) + 0)^;
        PByte(NativeInt(Dest) + 3)^ := PByte(NativeInt(Source) + 3)^;
        Inc(Source, 4);
        Inc(Dest, 4);
      end;
      Stream.WriteBuffer(Row[0], Length(Row));
    end;
    FileSize := Stream.Size;
  finally
    Stream.Free;
  end;
end;

procedure RenderingVideoCallback(Param: Pointer; Frame: Integer;
  Buffer: Pointer; Width, Height, Pitch: Integer); cdecl;
var
  Context: TFrameCaptureContext;
begin
  Context := TFrameCaptureContext(Param);
  if Context = nil then
    Exit;
  try
    SaveRgbaBitmap(Context.FilePath, Buffer, Width, Height, Pitch,
      Context.FileSize);
    Context.Width := Width;
    Context.Height := Height;
  except
    on E: Exception do
      Context.ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
  Context.Completed := True;
end;

function CaptureSceneFrame(EditHandle: PEditHandle; Frame: Integer;
  out Image: TAul2MIRAIFrameImage; out ErrorMessage: string): Boolean;
var
  Context: TFrameCaptureContext;
  Started: UInt64;
begin
  Image := Default(TAul2MIRAIFrameImage);
  ErrorMessage := '';
  Result := False;
  if (EditHandle = nil) or
     not Assigned(EditHandle^.RenderingSceneVideo) or
     not Assigned(EditHandle^.WaitRenderingTask) then
  begin
    ErrorMessage := 'AviUtl2 video rendering API is not available.';
    Exit;
  end;
  if Frame < 0 then
  begin
    ErrorMessage := 'The render frame must be zero or greater.';
    Exit;
  end;

  Context := TFrameCaptureContext.Create;
  try
    Started := GetTickCount64;
    Context.FilePath := NewCaptureFilePath(Frame);
    if not EditHandle^.RenderingSceneVideo(Frame, Context,
      @RenderingVideoCallback) then
    begin
      ErrorMessage := 'AviUtl2 rejected the video rendering request.';
      Exit;
    end;

    EditHandle^.WaitRenderingTask();
    if not Context.Completed then
    begin
      ErrorMessage := 'AviUtl2 completed rendering without a callback.';
      Exit;
    end;
    if Context.ErrorMessage <> '' then
    begin
      ErrorMessage := Context.ErrorMessage;
      Exit;
    end;

    Image.FilePath := Context.FilePath;
    Image.Format := 'bmp';
    Image.CapturedAtUtc := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',
      TTimeZone.Local.ToUniversalTime(Now));
    Image.Frame := Frame;
    Image.Width := Context.Width;
    Image.Height := Context.Height;
    Image.FileSize := Context.FileSize;
    Image.ElapsedMs := GetTickCount64 - Started;
    Result := True;
  finally
    if not Result and (Context.FilePath <> '') and
       TFile.Exists(Context.FilePath) then
      TFile.Delete(Context.FilePath);
    Context.Free;
  end;
end;

end.
