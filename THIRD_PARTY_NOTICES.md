# 第三方代码说明

## Lyricify Lyrics Helper

`lib/lyrics/qrc_decrypter.dart` 与 `lib/lyrics/qq_lyrics.dart` 中的 QQ 音乐歌词搜索、下载接口、
QRC 解密（QQ 修改版三重 DES + zlib）以及 QRC 时间语义，改编自：

- 项目：[WXRIW/Lyricify-Lyrics-Helper](https://github.com/WXRIW/Lyricify-Lyrics-Helper)
- 参考提交：e875781e2e889d97c3c518fe388decd14805a56f
- Copyright 2023 XY Wang, WXRIW
- 许可证：Apache License 2.0（与本项目相同，全文见 [LICENSE](LICENSE)）

涉及的上游文件：`Providers/Web/QQMusic/Api.cs`、`Decrypter/Qrc/Decrypter.cs`、`DESHelper.cs`、
`Parsers/QrcParser.cs`、`Helpers/OffsetHelper.cs`。

本项目的 Dart 版本经由作者此前的 Python 改编版（astrbot_plugin_163music）移植，
并非直接分发上游 C# 源码。歌曲版本识别与置信度判定来自该 Python 版本。
测试中的加密样本由上游算法独立编译后生成，不包含账号信息或完整歌词。

## Netease_url

`lib/api/eapi_crypto.dart` 与 `lib/api/netease_api.dart` 中的 EAPI 加密格式和播放地址接口参数参考了
[Suxiaoqinx/Netease_url](https://github.com/Suxiaoqinx/Netease_url)（MIT License，Copyright (c) 2024 Suxiaoqinx）。

## NeteaseCloudMusicApiEnhanced

`lib/api/xeapi_crypto.dart` 中的 XEAPI 加密（公钥注册、请求封装、响应解密）和
`lib/api/netease_api.dart` 中走 XEAPI 取播放地址的请求头、Cookie 字段，参照
[NeteaseCloudMusicApiEnhanced/api-enhanced](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced)
（MIT License，Copyright (c) 2013-2022 Binaryify）的 `util/crypto.js`、`util/request.js`、
`module/register_xeapikey.js` 与 `module/song_url_v1.js` 移植。
参考提交：984cc02

## just_audio

`third_party/just_audio/` 是 just_audio 0.10.6 的副本，安卓端加了输出位深、重采样、
输出设备的配置钩子（改动见 `third_party/just_audio/NOTICE_X_MUSIC.md`）。

- 项目：[ryanheise/just_audio](https://github.com/ryanheise/just_audio)
- 许可证：MIT（全文见 `third_party/just_audio/LICENSE`）
