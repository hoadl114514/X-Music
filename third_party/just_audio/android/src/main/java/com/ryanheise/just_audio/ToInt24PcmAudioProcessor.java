package com.ryanheise.just_audio;

import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor.UnhandledAudioFormatException;
import androidx.media3.common.audio.BaseAudioProcessor;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * X-Music：把 16 位、32 位整数和 32 位浮点 PCM 转成 24 位整数（小端、3 字节一个采样）。
 *
 * <p>24 位音源被解码器解成浮点后，浮点能精确表示 24 位整数，这里乘回去是无损的。
 * 16 位音源左移 8 位，数值不变。
 */
final class ToInt24PcmAudioProcessor extends BaseAudioProcessor {
    private static final float SCALE = 8388608f; // 2^23

    @Override
    public AudioFormat onConfigure(AudioFormat inputAudioFormat)
        throws UnhandledAudioFormatException {
        switch (inputAudioFormat.encoding) {
            case C.ENCODING_PCM_24BIT:
                // 已经是 24 位，不用处理。
                return AudioFormat.NOT_SET;
            case C.ENCODING_PCM_16BIT:
            case C.ENCODING_PCM_32BIT:
            case C.ENCODING_PCM_FLOAT:
                return new AudioFormat(
                    inputAudioFormat.sampleRate, inputAudioFormat.channelCount, C.ENCODING_PCM_24BIT);
            default:
                throw new UnhandledAudioFormatException(inputAudioFormat);
        }
    }

    @Override
    public void queueInput(ByteBuffer inputBuffer) {
        inputBuffer.order(ByteOrder.LITTLE_ENDIAN);
        int position = inputBuffer.position();
        int limit = inputBuffer.limit();
        int size = limit - position;
        int encoding = inputAudioFormat.encoding;
        int samples = encoding == C.ENCODING_PCM_16BIT ? size / 2 : size / 4;
        ByteBuffer out = replaceOutputBuffer(samples * 3);
        switch (encoding) {
            case C.ENCODING_PCM_16BIT:
                for (int i = position; i + 1 < limit; i += 2) {
                    out.put((byte) 0);
                    out.put(inputBuffer.get(i));
                    out.put(inputBuffer.get(i + 1));
                }
                break;
            case C.ENCODING_PCM_32BIT:
                // 取高 24 位。
                for (int i = position; i + 3 < limit; i += 4) {
                    out.put(inputBuffer.get(i + 1));
                    out.put(inputBuffer.get(i + 2));
                    out.put(inputBuffer.get(i + 3));
                }
                break;
            case C.ENCODING_PCM_FLOAT:
                for (int i = position; i + 3 < limit; i += 4) {
                    float f = inputBuffer.getFloat(i);
                    long v = Math.round((double) f * SCALE);
                    if (v > 8388607L) v = 8388607L;
                    if (v < -8388608L) v = -8388608L;
                    int s = (int) v;
                    out.put((byte) s);
                    out.put((byte) (s >> 8));
                    out.put((byte) (s >> 16));
                }
                break;
            default:
                throw new IllegalStateException();
        }
        inputBuffer.position(limit);
        out.flip();
    }
}
