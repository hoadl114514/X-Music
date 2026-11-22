package com.ryanheise.just_audio;

import android.content.Context;
import android.media.AudioDeviceInfo;
import androidx.media3.common.audio.SonicAudioProcessor;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.audio.AudioSink;
import androidx.media3.exoplayer.audio.DefaultAudioSink;
import androidx.media3.exoplayer.audio.SilenceSkippingAudioProcessor;
import androidx.media3.common.audio.AudioProcessor;
import java.util.Collections;
import java.util.Set;
import java.util.WeakHashMap;

/**
 * X-Music 加的输出配置（原版 just_audio 没有）。宿主应用在播放器创建前设置好，
 * 播放器建 ExoPlayer 时读取。
 *
 * <ul>
 *   <li>{@link #floatOutput}：高解析音源（24 / 32 位）以 32 位浮点输出，否则统一转成 16 位。</li>
 *   <li>{@link #sampleRate}：重采样到这个采样率；0 表示跟随音源。只在 16 位输出时生效。</li>
 *   <li>{@link #device}：优先使用的输出设备；null 表示交给系统路由。改了立即生效。</li>
 * </ul>
 *
 * 位深和采样率要在 ExoPlayer 创建时决定，改了之后需要重建播放器才生效。
 */
public final class OutputConfig {
    private OutputConfig() {}

    public static volatile boolean floatOutput = false;
    public static volatile int sampleRate = 0;
    private static volatile AudioDeviceInfo device;

    private static final Set<ExoPlayer> livePlayers =
        Collections.synchronizedSet(Collections.newSetFromMap(new WeakHashMap<>()));

    /** 设置优先输出设备，并应用到所有正在用的播放器。要在主线程调用。 */
    public static void setPreferredDevice(AudioDeviceInfo info) {
        device = info;
        synchronized (livePlayers) {
            for (ExoPlayer p : livePlayers) {
                p.setPreferredAudioDevice(info);
            }
        }
    }

    static void register(ExoPlayer player) {
        livePlayers.add(player);
        player.setPreferredAudioDevice(device);
    }

    static void unregister(ExoPlayer player) {
        livePlayers.remove(player);
    }

    /** 按当前配置建音频输出：位深和重采样。 */
    static DefaultRenderersFactory renderersFactory(Context context) {
        final boolean useFloat = floatOutput;
        final int rate = sampleRate;
        return new DefaultRenderersFactory(context) {
            @Override
            protected AudioSink buildAudioSink(
                Context ctx, boolean enableFloatOutput, boolean enableAudioTrackPlaybackParams) {
                SonicAudioProcessor sonic = new SonicAudioProcessor();
                if (rate > 0) {
                    sonic.setOutputSampleRateHz(rate);
                }
                return new DefaultAudioSink.Builder(ctx)
                    .setEnableFloatOutput(useFloat)
                    .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
                    .setAudioProcessorChain(new DefaultAudioSink.DefaultAudioProcessorChain(
                        new AudioProcessor[0], new SilenceSkippingAudioProcessor(), sonic))
                    .build();
            }
        };
    }
}
