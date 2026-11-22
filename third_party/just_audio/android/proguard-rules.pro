# X-Music：HiResAudioSink 用反射替换 DefaultAudioSink 的这个字段，不能被混淆或删掉。
-keepclassmembers class androidx.media3.exoplayer.audio.DefaultAudioSink {
    private final com.google.common.collect.ImmutableList toIntPcmAvailableAudioProcessors;
}
