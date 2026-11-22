package io.github.hoadl114514.netease_client

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioMixerAttributes
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import com.ryanheise.just_audio.OutputConfig
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 音频输出设置：列出输出设备、指定输出设备、位深、采样率、USB DAC 独占（bit-perfect），
 * 以及判断当前是不是移动网络。
 *
 * 位深（16 位、24 位整数、32 位浮点）和采样率写进改过的 just_audio（[OutputConfig]），下次建播放器时生效；
 * 输出设备立即生效；USB 独占用 Android 14 的 setPreferredMixerAttributes。
 */
class AudioOutputChannel(private val context: Context, messenger: BinaryMessenger) {
    private val audio = context.getSystemService(AudioManager::class.java)

    /** 上次设了独占的 USB 设备，关闭或换设备时要清掉。 */
    private var exclusiveDevice: AudioDeviceInfo? = null

    private val mediaAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "devices" -> result.success(devices())
                "isCellular" -> result.success(isCellular())
                "apply" -> result.success(
                    apply(
                        deviceType = call.argument<Int>("deviceType") ?: 0,
                        deviceName = call.argument<String>("deviceName") ?: "",
                        bitDepth = call.argument<Int>("bitDepth") ?: 16,
                        sampleRate = call.argument<Int>("sampleRate") ?: 0,
                        usbExclusive = call.argument<Boolean>("usbExclusive") ?: false,
                    ),
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun outputs(): List<AudioDeviceInfo> =
        audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).filter { it.isSink && it.type in USER_TYPES }

    private fun devices(): List<Map<String, Any>> = outputs().map {
        mapOf("type" to it.type, "name" to "${it.productName ?: ""}")
    }.distinct()

    private fun isCellular(): Boolean {
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return false
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) &&
            !caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    }

    private fun apply(
        deviceType: Int,
        deviceName: String,
        bitDepth: Int,
        sampleRate: Int,
        usbExclusive: Boolean,
    ): Map<String, Any?> {
        // 24 位整数输出要 Android 12（AudioTrack 的 24 位 packed）。不支持时退回 16 位。
        val int24 = bitDepth == 24 && Build.VERSION.SDK_INT >= 31
        OutputConfig.floatOutput = bitDepth == 32
        OutputConfig.int24Output = int24
        // 24 位和浮点都不重采样，跟随音源。
        OutputConfig.sampleRate = if (bitDepth == 16) sampleRate else 0
        val effectiveDepth = if (bitDepth == 24 && !int24) 16 else bitDepth

        val all = outputs()
        var device = if (deviceType == 0) null else
            all.firstOrNull { it.type == deviceType && "${it.productName ?: ""}" == deviceName }
                ?: all.firstOrNull { it.type == deviceType }

        // USB 独占：先清掉旧的，再给 USB 设备设 bit-perfect 混音参数。
        exclusiveDevice?.let { clearExclusive(it) }
        exclusiveDevice = null
        var exclusive = "off"
        if (usbExclusive) {
            val usb = all.firstOrNull { it.type in USB_TYPES }
            exclusive = when {
                Build.VERSION.SDK_INT < 34 -> "unsupported_os"
                usb == null -> "no_usb"
                else -> setExclusive(usb, effectiveDepth, OutputConfig.sampleRate)
            }
            if (exclusive == "on") {
                exclusiveDevice = usb
                device = usb
            }
        }
        OutputConfig.setPreferredDevice(device)
        return mapOf(
            "exclusive" to exclusive,
            "deviceFound" to (deviceType == 0 || device != null),
            "bitDepth" to effectiveDepth,
        )
    }

    private fun setExclusive(usb: AudioDeviceInfo, bitDepth: Int, sampleRate: Int): String {
        if (Build.VERSION.SDK_INT < 34) return "unsupported_os"
        val candidates = audio.getSupportedMixerAttributes(usb).filter {
            it.mixerBehavior == AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT
        }
        if (candidates.isEmpty()) return "unsupported_device"
        val encoding = when (bitDepth) {
            32 -> AudioFormat.ENCODING_PCM_FLOAT
            24 -> AudioFormat.ENCODING_PCM_24BIT_PACKED
            else -> AudioFormat.ENCODING_PCM_16BIT
        }
        // 跟随音源时按 44.1 kHz 设：网易云的歌绝大多数是 44.1 kHz。
        val rate = if (sampleRate > 0) sampleRate else 44100
        fun score(m: AudioMixerAttributes): Int {
            val f = m.format
            var s = 0
            if (f.encoding == encoding) s += 4
            if (f.sampleRate == rate) s += 2
            if (f.channelCount == 2) s += 1
            return s
        }
        val chosen = candidates.maxBy { score(it) }
        return if (audio.setPreferredMixerAttributes(mediaAttributes, usb, chosen)) "on" else "failed"
    }

    private fun clearExclusive(device: AudioDeviceInfo) {
        if (Build.VERSION.SDK_INT >= 34) {
            try {
                audio.clearPreferredMixerAttributes(mediaAttributes, device)
            } catch (_: Exception) {
                // 设备已经拔掉了。
            }
        }
    }

    private companion object {
        const val CHANNEL = "netease_client/audio_output"

        val USB_TYPES = setOf(AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET)

        /** 用户能选的输出设备类型；听筒、电话线路之类的不列出来。 */
        val USER_TYPES = setOf(
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_SPEAKER,
            AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_ACCESSORY,
            AudioDeviceInfo.TYPE_HDMI,
            AudioDeviceInfo.TYPE_LINE_ANALOG,
            AudioDeviceInfo.TYPE_LINE_DIGITAL,
            AudioDeviceInfo.TYPE_AUX_LINE,
            AudioDeviceInfo.TYPE_DOCK,
        )
    }
}
