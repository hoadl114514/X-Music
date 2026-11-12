import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/audio/audio_cache.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/state/player_controller.dart';
import 'package:netease_client/state/settings.dart';

import 'support/fakes.dart';

/// 播放器和听歌缓存的配合：有缓存先放本地，没缓存边播边存，断网时退回缓存。
void main() {
  late Directory dir;
  late FakeEngine engine;
  late FakeBackend backend;
  late AppSettings settings;
  late AudioCache cache;
  late PlayerController player;
  final queue = [song('1'), song('2')];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('player_cache_test');
    engine = FakeEngine();
    backend = FakeBackend();
    settings = await testSettings();
    cache = AudioCache(directory: Future.value(dir), limit: () => settings.audioCacheLimit);
    player = PlayerController(
      engine: engine,
      backend: backend,
      settings: settings,
      cache: cache,
      retryDelays: const [Duration(milliseconds: 1)],
    );
  });
  tearDown(() async {
    player.dispose();
    cache.dispose();
    await dir.delete(recursive: true);
  });

  File put(String name) => File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3]);

  test('default cache limit is 5 GB', () {
    expect(settings.audioCacheLimit, 5 << 30);
  });

  test('a cached song plays from disk without asking for a URL', () async {
    settings.preferredQuality = AudioQuality.exhigh;
    final f = put('1_exhigh_exhigh.mp3');
    await player.playQueue(queue);
    expect(engine.loaded.single, Uri.file(f.path).toString());
    expect(engine.cacheSlots.single, isNull);
    expect(backend.urlRequests, isEmpty);
    expect(player.quality, AudioQuality.exhigh);
    expect(player.isPlaying, isTrue);
    // 音质列表在后台取，给播放页切音质用。
    await pumpEventQueue();
    expect(player.qualities, isNotEmpty);
  });

  test('a song without the preferred quality still hits the cache', () async {
    settings.preferredQuality = AudioQuality.lossless;
    // 歌只有 standard / exhigh：实际请求 exhigh，缓存也按 exhigh 存的。
    final f = put('1_exhigh_exhigh.mp3');
    await player.playQueue(queue);
    expect(engine.loaded.single, Uri.file(f.path).toString());
    expect(backend.urlRequests, isEmpty);
  });

  test('an uncached song streams and is handed a cache slot', () async {
    settings.preferredQuality = AudioQuality.exhigh;
    await player.playQueue(queue);
    expect(engine.loaded.single, 'https://x/1/exhigh');
    expect(engine.cacheSlots.single!.base, '1_exhigh_exhigh');
  });

  test('trial clips are not cached', () async {
    backend.trials['1'] = (start: Duration.zero, end: const Duration(seconds: 30));
    await player.playQueue(queue);
    expect(engine.cacheSlots.single, isNull);
  });

  test('cache limit 0 turns caching off', () async {
    settings.audioCacheLimit = 0;
    await player.playQueue(queue);
    expect(engine.cacheSlots.single, isNull);
  });

  test('offline: falls back to a cached copy in another quality', () async {
    settings.preferredQuality = AudioQuality.lossless;
    final f = put('1_standard_standard.mp3');
    backend.offline = true;
    final notices = <String>[];
    player.notices.listen(notices.add);
    await player.playQueue(queue);
    await pumpEventQueue();
    expect(engine.loaded.single, Uri.file(f.path).toString());
    expect(player.isPlaying, isTrue);
    expect(player.quality, AudioQuality.standard);
    expect(notices.single, contains('本地缓存'));
  });

  test('offline without a cached copy still reports the failure', () async {
    backend.offline = true;
    final notices = <String>[];
    player.notices.listen(notices.add);
    await player.playQueue(queue);
    await pumpEventQueue();
    expect(engine.loaded, isEmpty);
    expect(player.isPlaying, isFalse);
    expect(notices, isNotEmpty);
  });
}
