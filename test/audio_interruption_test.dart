import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/state/player_controller.dart';
import 'package:netease_client/state/settings.dart';

import 'support/fakes.dart';

/// 其他应用抢走音频焦点时，内核会自己暂停。界面要跟着变成暂停，不能显示播放中却没声音（issue 32）。
void main() {
  late FakeEngine engine;
  late AppSettings settings;
  late PlayerController player;
  final queue = [song('1'), song('2')];

  setUp(() async {
    engine = FakeEngine();
    settings = await testSettings();
    player = PlayerController(engine: engine, backend: FakeBackend(), settings: settings);
  });
  tearDown(() => player.dispose());

  test('engine pausing itself (focus lost) shows paused, and play resumes', () async {
    await player.playQueue(queue, title: '测试');
    expect(player.isPlaying, isTrue);
    engine.advance(const Duration(seconds: 5));

    engine.interrupt(playing: false);
    await pumpEventQueue();
    expect(player.isPlaying, isFalse);
    expect(player.position, const Duration(seconds: 5));

    // 回到应用点播放：要真的叫内核播放，而不是以为已经在放。
    await player.play();
    expect(engine.playing, isTrue);
    expect(player.isPlaying, isTrue);
  });

  test('engine resuming itself (focus regained) shows playing', () async {
    await player.playQueue(queue, title: '测试');
    engine.interrupt(playing: false);
    await pumpEventQueue();
    engine.interrupt(playing: true);
    await pumpEventQueue();
    expect(player.isPlaying, isTrue);
  });

  test('engine state changes while loading are ignored', () async {
    await player.playQueue(queue, title: '测试');
    final loading = player.next();
    engine.interrupt(playing: true);
    await loading;
    await pumpEventQueue();
    expect(player.song.id, '2');
    expect(player.isPlaying, isTrue);
  });

  test('mix-with-others setting is saved and rebuilds the engine, keeping playback', () async {
    await player.playQueue(queue, title: '测试');
    await player.setMixWithOthers(true);
    expect(settings.mixWithOthers, isTrue);
    expect(engine.rebuilds, 1);
    expect(player.isPlaying, isTrue);
    await player.setMixWithOthers(true);
    expect(engine.rebuilds, 1);
  });
}
