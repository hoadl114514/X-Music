# X-Music 对 just_audio 的修改

基于 just_audio 0.10.6（MIT 许可，见 LICENSE），只改了安卓端：

- 新增 `android/src/main/java/com/ryanheise/just_audio/OutputConfig.java`：输出位深（16 位 / 32 位浮点）、
  重采样采样率、优先输出设备。
- 新增 `ToInt24PcmAudioProcessor.java`、`HiResAudioSink.java`：24 位整数输出。HiResAudioSink 用反射
  替换 media3 DefaultAudioSink 的 `toIntPcmAvailableAudioProcessors` 字段，升级 media3 时要确认字段名没变。
  `android/proguard-rules.pro` 保留这个字段不被混淆。
- `AudioPlayer.java`：建 ExoPlayer 时用 `OutputConfig` 的音频输出；创建和释放时登记播放器，
  方便切换输出设备时立即生效。

升级 just_audio 时，把这两处改动搬到新版本上。
