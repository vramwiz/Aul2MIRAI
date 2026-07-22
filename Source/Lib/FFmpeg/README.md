# FFmpeg runtime for Aul2MIRAI

VideoMinerで使用しているFFmpeg 8.1.1 full shared buildから、`FFmpegApi.pas` がロードする実行時DLLだけをコピーしたもの。

## Delphi API unit

```text
Source\Lib\FFmpeg\FFmpegApi.pas
```

## Runtime DLL

```text
Source\Lib\FFmpeg\bin\avutil-60.dll
Source\Lib\FFmpeg\bin\swresample-6.dll
Source\Lib\FFmpeg\bin\swscale-9.dll
Source\Lib\FFmpeg\bin\avcodec-62.dll
Source\Lib\FFmpeg\bin\avformat-62.dll
Source\Lib\FFmpeg\bin\avfilter-11.dll
```

`FFmpegApi.pas` は `Aul2MIRAI.aux2` 自身のフォルダからDLLをロードする。FFmpeg機能を有効にして配布・実機確認するときは、上記6 DLLを `Aul2MIRAI.aux2` と同じフォルダへコピーする。

`avfilter-11.dll` は純粋なデコードだけなら直接利用しない場合もあるが、現在の `TFFmpegApi.EnsureLoaded` が必須ロードするため含める。

FFmpeg本体のライセンスと配布元説明は、同じフォルダの `LICENSE` と `FFMPEG_README.txt` を参照する。

## コピーしなかったもの

- `avdevice-62.dll`: 現在のAPIユニットがロードしない。
- `ffmpeg.exe` / `ffplay.exe` / `ffprobe.exe`: ライブラリAPIによるデコードには不要。
- C/C++用ヘッダーとimport library: Delphi側は `FFmpegApi.pas` からDLLを動的ロードするため不要。
- VideoMinerの高水準デコーダユニット: VideoMiner固有の設定、ログ、再生UIへの依存があるため、そのままではAul2MIRAIの共通ライブラリにならない。
