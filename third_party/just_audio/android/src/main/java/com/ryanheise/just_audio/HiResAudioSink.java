package com.ryanheise.just_audio;

import androidx.annotation.Nullable;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.util.Util;
import androidx.media3.exoplayer.audio.DefaultAudioSink;
import androidx.media3.exoplayer.audio.ForwardingAudioSink;
import com.google.common.collect.ImmutableList;
import io.flutter.Log;
import java.lang.reflect.Field;

/**
 * X-Music：让 DefaultAudioSink 输出 24 位整数 PCM（Android 12+ 的 AudioTrack 支持 24 位）。
 *
 * <p>media3 1.4.1 的 DefaultAudioSink 只会输出 16 位或浮点：非浮点模式下，24 位、浮点输入
 * 都先过 ToInt16PcmAudioProcessor。这里用反射把那一步换成 {@link ToInt24PcmAudioProcessor}，
 * 并告诉解码器可以直接输出浮点，保住 24 位精度。
 *
 * <p>有编码延迟（MP3、AAC）的歌需要 media3 的裁剪处理器，它只支持 16 位，所以这些歌仍走 16 位。
 * 无损的 FLAC 没有编码延迟，走 24 位。
 */
final class HiResAudioSink extends ForwardingAudioSink {
    private static final String TAG = "HiResAudioSink";

    private final DefaultAudioSink sink;
    @Nullable private final Field toIntField;
    @Nullable private final ImmutableList<AudioProcessor> defaultToInt;
    private final ImmutableList<AudioProcessor> toInt24 =
        ImmutableList.of(new ToInt24PcmAudioProcessor());

    HiResAudioSink(DefaultAudioSink sink) {
        super(sink);
        this.sink = sink;
        Field field = null;
        ImmutableList<AudioProcessor> original = null;
        try {
            field = DefaultAudioSink.class.getDeclaredField("toIntPcmAvailableAudioProcessors");
            field.setAccessible(true);
            @SuppressWarnings("unchecked")
            ImmutableList<AudioProcessor> value = (ImmutableList<AudioProcessor>) field.get(sink);
            original = value;
        } catch (Exception e) {
            Log.w(TAG, "24-bit output unavailable, falling back to 16-bit: " + e);
            field = null;
        }
        toIntField = field;
        defaultToInt = original;
    }

    /** 反射成功、系统支持 24 位 AudioTrack 时才走 24 位。 */
    private boolean available() {
        return toIntField != null && Util.SDK_INT >= 31;
    }

    @Override
    public int getFormatSupport(Format format) {
        // 让解码器输出浮点（MediaCodecAudioRenderer 看到浮点被直接支持才会这么请求）。
        if (available()
            && MimeTypes.AUDIO_RAW.equals(format.sampleMimeType)
            && format.pcmEncoding == C.ENCODING_PCM_FLOAT) {
            return SINK_FORMAT_SUPPORTED_DIRECTLY;
        }
        return super.getFormatSupport(format);
    }

    @Override
    public void configure(Format inputFormat, int specifiedBufferSize, @Nullable int[] outputChannels)
        throws ConfigurationException {
        if (available()) {
            boolean raw = MimeTypes.AUDIO_RAW.equals(inputFormat.sampleMimeType);
            boolean noTrim = inputFormat.encoderDelay <= 0 && inputFormat.encoderPadding <= 0;
            boolean use24 = raw && noTrim && outputChannels == null;
            try {
                toIntField.set(sink, use24 ? toInt24 : defaultToInt);
            } catch (IllegalAccessException e) {
                Log.w(TAG, "switching 24-bit output failed: " + e);
            }
        }
        super.configure(inputFormat, specifiedBufferSize, outputChannels);
    }
}
