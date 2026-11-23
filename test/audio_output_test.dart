import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/audio/audio_output.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/state/player_controller.dart';

import 'support/fakes.dart';

class FakeOutput extends AudioOutput {
  FakeOutput();

  bool cellular = false;
  final applied =
      <({AudioOutputDevice? device, OutputBitDepth bitDepth, int sampleRate, bool usb})>[];

  @override
  Future<bool> isCellular() async => cellular;

  @override
  Future<List<AudioOutputDevice>> devices() async => const [
    AudioOutputDevice(type: 2, name: 'Pixel'),
    AudioOutputDevice(type: 11, name: 'DAC'),
  ];

  @override
  Future<OutputResult> apply({
    AudioOutputDevice? device,
    required OutputBitDepth bitDepth,
    required int sampleRate,
    required bool usbExclusive,
  }) async {
    applied.add((device: device, bitDepth: bitDepth, sampleRate: sampleRate, usb: usbExclusive));
    return (
      exclusive: usbExclusive ? ExclusiveState.on : ExclusiveState.off,
      deviceFound: true,
      bitDepth: bitDepth.bits,
    );
  }
}

void main() {
  Future<(PlayerController, FakeEngine, FakeBackend, FakeOutput)> setUp() async {
    final settings = await testSettings();
    final engine = FakeEngine();
    final backend = FakeBackend();
    final output = FakeOutput();
    final player = PlayerController(
      engine: engine,
      backend: backend,
      settings: settings,
      output: output,
    );
    return (player, engine, backend, output);
  }

  test('mobile network uses the mobile quality, Wi-Fi the default one', () async {
    final (player, _, backend, output) = await setUp();
    final settings = await testSettings({
      'preferred_quality': 'exhigh',
      'mobile_quality': 'standard',
    });
    final p = PlayerController(
      engine: FakeEngine(),
      backend: backend,
      settings: settings,
      output: output,
    );
    output.cellular = true;
    await p.playQueue([song('1'), song('2')]);
    expect(backend.urlRequests.last, ('1', AudioQuality.standard));

    output.cellular = false;
    await p.next();
    expect(backend.urlRequests.last, ('2', AudioQuality.exhigh));

    // 移动网络下在播放页切音质，改的是移动网络音质。
    output.cellular = true;
    await p.previous(restart: false);
    await p.setQuality(AudioQuality.exhigh);
    expect(settings.mobileQuality, AudioQuality.exhigh);
    expect(settings.preferredQuality, AudioQuality.exhigh);
    player.dispose();
    p.dispose();
  });

  test('no mobile quality set: mobile network uses the default quality', () async {
    final (player, _, backend, output) = await setUp();
    output.cellular = true;
    await player.playQueue([song('1')]);
    expect(backend.urlRequests.last.$2, AudioQuality.exhigh);
    player.dispose();
  });

  test('changing bit depth or sample rate rebuilds the engine and reloads in place', () async {
    final settings = await testSettings();
    final engine = FakeEngine();
    final output = FakeOutput();
    final player = PlayerController(
      engine: engine,
      backend: FakeBackend(),
      settings: settings,
      output: output,
    );
    await player.applyOutput();
    await player.playQueue([song('1')]);
    engine.advance(const Duration(seconds: 30));
    await player.pause();
    final loads = engine.loaded.length;

    // 只换设备：不重建。
    settings.outputDevice = const AudioOutputDevice(type: 11, name: 'DAC');
    await player.applyOutput();
    expect(engine.rebuilds, 0);
    expect(output.applied.last.device?.name, 'DAC');

    settings.outputBitDepth = OutputBitDepth.pcm24;
    await player.applyOutput();
    expect(engine.rebuilds, 1);
    expect(output.applied.last.bitDepth.bits, 24);
    expect(engine.loaded.length, loads + 1);
    expect(engine.loadStart, const Duration(seconds: 30));
    expect(engine.playing, isFalse);

    settings.usbExclusive = true;
    final r = await player.applyOutput();
    expect(r?.exclusive, ExclusiveState.on);
    expect(engine.rebuilds, 1);
    player.dispose();
  });

  test('device labels name the kind of output', () {
    expect(const AudioOutputDevice(type: 2, name: 'Pixel 8').label, '手机扬声器 · Pixel 8');
    expect(const AudioOutputDevice(type: 8, name: 'AirPods').label, '蓝牙 · AirPods');
    expect(AudioOutput.sampleRateLabel(0), '跟随音源');
    expect(AudioOutput.sampleRateLabel(44100), '44.1 kHz');
    expect(AudioOutput.sampleRateLabel(96000), '96 kHz');
  });
}
