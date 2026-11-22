import 'package:flutter/services.dart';

/// 一个音频输出设备（安卓 AudioDeviceInfo）。[type] 是 AudioDeviceInfo.TYPE_* 的值。
class AudioOutputDevice {
  const AudioOutputDevice({required this.type, required this.name});

  final int type;
  final String name;

  /// 设置里显示的名字：类型 + 设备名。
  String get label {
    final kind = typeLabel(type);
    if (name.isEmpty || name == kind) return kind;
    return '$kind · $name';
  }

  static String typeLabel(int type) => switch (type) {
    2 => '手机扬声器',
    3 || 4 => '有线耳机',
    8 || 26 || 27 => '蓝牙',
    11 || 22 || 12 => 'USB',
    9 || 10 => 'HDMI',
    5 || 6 || 19 => '线路输出',
    13 => '底座',
    _ => '其他设备',
  };

  @override
  bool operator ==(Object other) =>
      other is AudioOutputDevice && other.type == type && other.name == name;

  @override
  int get hashCode => Object.hash(type, name);
}

/// 输出位深。
enum OutputBitDepth {
  pcm16('16 位', 16),
  pcm24('24 位', 24),
  float32('32 位浮点', 32);

  const OutputBitDepth(this.label, this.bits);

  final String label;
  final int bits;

  /// 16 位以外都不重采样，采样率跟随音源。
  bool get followsSourceRate => this != pcm16;

  static OutputBitDepth byName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => pcm16);
}

/// USB DAC 独占模式的结果。
enum ExclusiveState {
  off(''),
  on('USB 独占已开启'),
  noUsb('没有检测到 USB 音频设备'),
  unsupportedOs('独占模式需要 Android 14 及以上'),
  unsupportedDevice('这个 USB 设备不支持独占（bit-perfect）'),
  failed('系统拒绝了独占请求');

  const ExclusiveState(this.message);

  final String message;

  static ExclusiveState parse(Object? v) => switch (v) {
    'on' => on,
    'no_usb' => noUsb,
    'unsupported_os' => unsupportedOs,
    'unsupported_device' => unsupportedDevice,
    'failed' => failed,
    _ => off,
  };
}

/// 一次应用输出设置的结果。[bitDepth] 是实际生效的位深（系统不支持 24 位时退回 16 位）。
typedef OutputResult = ({ExclusiveState exclusive, bool deviceFound, int bitDepth});

/// 音频输出的原生接口：输出设备、位深、采样率、USB 独占，以及当前网络类型。
///
/// 只有安卓实现；其他平台和测试里调用都安全返回默认值。
class AudioOutput {
  const AudioOutput();

  static const _channel = MethodChannel('netease_client/audio_output');

  /// 常用的输出采样率；0 表示跟随音源。
  static const sampleRates = [0, 44100, 48000, 88200, 96000, 176400, 192000];

  static String sampleRateLabel(int rate) =>
      rate == 0 ? '跟随音源' : '${(rate / 1000).toStringAsFixed(rate % 1000 == 0 ? 0 : 1)} kHz';

  Future<List<AudioOutputDevice>> devices() async {
    try {
      final list = await _channel.invokeListMethod<Map<Object?, Object?>>('devices') ?? const [];
      return [
        for (final m in list)
          AudioOutputDevice(type: (m['type'] as int?) ?? 0, name: '${m['name'] ?? ''}'),
      ];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// 当前是不是移动网络（没有 Wi-Fi）。
  Future<bool> isCellular() async {
    try {
      return await _channel.invokeMethod<bool>('isCellular') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 应用输出设置。[device] 为 null 表示交给系统选择。
  Future<OutputResult> apply({
    AudioOutputDevice? device,
    required OutputBitDepth bitDepth,
    required int sampleRate,
    required bool usbExclusive,
  }) async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('apply', {
        'deviceType': device?.type ?? 0,
        'deviceName': device?.name ?? '',
        'bitDepth': bitDepth.bits,
        'sampleRate': sampleRate,
        'usbExclusive': usbExclusive,
      });
      return (
        exclusive: ExclusiveState.parse(r?['exclusive']),
        deviceFound: r?['deviceFound'] != false,
        bitDepth: (r?['bitDepth'] as int?) ?? bitDepth.bits,
      );
    } on MissingPluginException {
      return (exclusive: ExclusiveState.off, deviceFound: true, bitDepth: bitDepth.bits);
    } on PlatformException {
      return (exclusive: ExclusiveState.failed, deviceFound: true, bitDepth: bitDepth.bits);
    }
  }
}
