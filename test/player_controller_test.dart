import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/state/player_controller.dart';
import 'package:netease_client/state/settings.dart';

import 'support/fakes.dart';

void main() {
  late FakeEngine engine;
  late FakeBackend backend;
  late AppSettings settings;
  late PlayerController player;
  final queue = [song('1'), song('2'), song('3')];

  setUp(() async {
    PlayerController.extendRetryDelay = const Duration(milliseconds: 1);
    engine = FakeEngine();
    backend = FakeBackend();
    settings = await testSettings();
    player = PlayerController(
      engine: engine,
      backend: backend,
      settings: settings,
      retryDelays: const [Duration(milliseconds: 1), Duration(milliseconds: 1)],
    );
  });
  tearDown(() => player.dispose());

  test('empty player has no current song', () {
    expect(player.current, isNull);
    expect(player.isPlaying, isFalse);
  });

  test('playQueue picks the best offered quality not above the preference', () async {
    settings.preferredQuality = AudioQuality.lossless;
    backend.qualityMap['2'] = [AudioQuality.standard, AudioQuality.exhigh, AudioQuality.jymaster];
    await player.playQueue(queue, start: 1, title: '测试歌单');
    expect(player.song.id, '2');
    expect(player.queueTitle, '测试歌单');
    expect(backend.urlRequests.single, ('2', AudioQuality.exhigh));
    expect(player.quality, AudioQuality.exhigh);
    expect(player.qualities.map((q) => q.quality), [
      AudioQuality.standard,
      AudioQuality.exhigh,
      AudioQuality.jymaster,
    ]);
    expect(engine.loaded.single, 'https://x/2/exhigh');
    expect(engine.playing, isTrue);
    expect(player.isPlaying, isTrue);
  });

  test('progress ticks notify ticks listeners only', () async {
    await player.playQueue(queue, title: '测试歌单');
    var changes = 0;
    var ticks = 0;
    player.addListener(() => changes++);
    player.ticks.addListener(() => ticks++);
    engine.advance(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 160));
    expect(ticks, greaterThan(0));
    expect(changes, 0);
    expect(player.position, const Duration(seconds: 1));
  });

  test('AudioQuality.pick falls back to the lowest when everything is above', () {
    expect(
      AudioQuality.pick([AudioQuality.lossless, AudioQuality.hires], AudioQuality.standard),
      AudioQuality.lossless,
    );
    expect(AudioQuality.pick(const [], AudioQuality.standard), isNull);
  });

  test('server downgrade is reported and reflected', () async {
    settings.preferredQuality = AudioQuality.hires;
    backend.qualityMap['1'] = [AudioQuality.exhigh, AudioQuality.lossless, AudioQuality.hires];
    backend.accountMax = AudioQuality.exhigh;
    final notices = <String>[];
    player.notices.listen(notices.add);
    await player.playQueue(queue);
    await pumpEventQueue();
    expect(player.quality, AudioQuality.exhigh);
    expect(notices.single, contains('极高'));
  });

  test('setQuality keeps position and play state, and becomes the default', () async {
    backend.qualityMap['1'] = [AudioQuality.standard, AudioQuality.lossless];
    await player.playQueue(queue);
    engine.advance(const Duration(seconds: 42));
    await player.pause();
    await player.setQuality(AudioQuality.lossless);
    expect(engine.loaded.last, 'https://x/1/lossless');
    expect(engine.loadStart, const Duration(seconds: 42));
    expect(player.position, const Duration(seconds: 42));
    expect(engine.playing, isFalse);
    expect(settings.preferredQuality, AudioQuality.lossless);
  });

  test('unavailable songs are skipped while playing, but not forever', () async {
    backend.unavailable.addAll(['1', '2']);
    await player.playQueue(queue);
    await pumpEventQueue();
    expect(player.song.id, '3');
    expect(engine.loaded.single, contains('/3/'));

    backend.unavailable.add('3');
    await player.jumpTo(0);
    await pumpEventQueue();
    // 三首都不能放：试过一圈后停下，不无限循环。
    expect(player.isPlaying, isFalse);
  });

  test('a flaky song URL request is retried', () async {
    backend.urlFailures['1'] = 2;
    await player.playQueue(queue);
    expect(backend.urlRequests.where((r) => r.$1 == '1'), hasLength(3));
    expect(engine.loaded.single, contains('/1/'));
    expect(player.isPlaying, isTrue);
  });

  test('a failed audio load is retried with a fresh URL', () async {
    engine.failLoads = 1;
    await player.playQueue(queue);
    expect(backend.urlRequests, hasLength(2));
    expect(engine.loaded.single, contains('/1/'));
    expect(player.isPlaying, isTrue);
  });

  test('play after a failed load reloads the current song, not the previous one', () async {
    await player.playQueue(queue);
    expect(engine.loaded.single, contains('/1/'));

    // 第二首三次都加载失败：停下并提示，内核里还留着第一首。
    final notices = <String>[];
    player.notices.listen(notices.add);
    engine.failLoads = 3;
    await player.next();
    await pumpEventQueue();
    expect(player.song.id, '2');
    expect(player.isPlaying, isFalse);
    expect(notices, isNotEmpty);
    expect(engine.loaded, hasLength(1));

    // 再点播放：重新加载第二首，而不是接着放内核里的第一首。
    await player.toggle();
    expect(engine.loaded.last, contains('/2/'));
    expect(player.song.id, '2');
    expect(player.isPlaying, isTrue);
  });

  test('an error mid-playback reloads the song where it stopped', () async {
    await player.playQueue(queue);
    engine.advance(const Duration(seconds: 50));
    await player.pause();
    await player.play();
    // 进度由计时器同步；这里直接用 seek 设好。
    await player.seek(const Duration(seconds: 50));
    engine.error(Exception('connection lost'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await pumpEventQueue();
    expect(engine.loaded, hasLength(2));
    expect(engine.loaded.last, contains('/1/'));
    expect(engine.loadStart, const Duration(seconds: 50));
    expect(player.isPlaying, isTrue);
  });

  test('lyrics load with fallback, and source switch keeps old lyrics when empty', () async {
    backend.lyricsMap[('1', LyricSource.qq)] = karaoke(source: LyricSource.qq);
    await player.playQueue(queue);
    await pumpEventQueue();
    expect(player.lyrics.source, LyricSource.qq); // 默认网易云没有，自动换 QQ。

    final notices = <String>[];
    player.notices.listen(notices.add);
    await player.setLyricSource(LyricSource.netease);
    await pumpEventQueue();
    expect(player.lyrics.source, LyricSource.qq);
    expect(notices.single, contains('网易云'));
  });

  test('activeLyricIndex follows position and offset', () async {
    backend.lyricsMap[('1', LyricSource.netease)] = karaoke();
    await player.playQueue(queue);
    await pumpEventQueue();
    final lines = player.lyrics.lines;
    expect(player.activeLyricIndex, -1);

    await player.seek(lines[3].start);
    expect(player.activeLyricIndex, 3);

    await player.seek(lines[3].start - const Duration(milliseconds: 1));
    expect(player.activeLyricIndex, 2);

    // 歌词提前 1 秒后，同一播放位置应落到下一行。
    await player.seek(lines[3].start - const Duration(milliseconds: 500));
    player.adjustLyricOffset(const Duration(seconds: 1));
    expect(player.activeLyricIndex, 3);
  });

  test('trial clips map lyric time back to the full song', () async {
    backend.trials['1'] = (start: const Duration(seconds: 60), end: const Duration(seconds: 90));
    await player.playQueue(queue);
    expect(player.duration, const Duration(seconds: 30));
    await player.seek(const Duration(seconds: 5));
    expect(player.lyricPosition, const Duration(seconds: 65));
  });

  test('seek clamps to song bounds', () async {
    await player.playQueue(queue);
    await player.seek(const Duration(hours: 1));
    expect(player.position, player.duration);
    await player.seek(const Duration(seconds: -1));
    expect(player.position, Duration.zero);
  });

  test('previous restarts after 3 seconds, otherwise wraps the queue', () async {
    await player.playQueue(queue);
    await player.seek(const Duration(seconds: 10));
    await player.previous();
    expect(player.position, Duration.zero);
    expect(player.song.id, '1');

    await player.previous();
    expect(player.song.id, '3');
  });

  test('completion advances; repeat-one replays the same song', () async {
    await player.playQueue(queue);
    engine.complete();
    await pumpEventQueue();
    expect(player.song.id, '2');

    player.toggleRepeat();
    expect(player.repeat, Repeat.one);
    engine.advance(const Duration(seconds: 100));
    engine.complete();
    await pumpEventQueue();
    expect(player.song.id, '2');
    expect(player.position, Duration.zero);
  });

  test('play mode button cycles list -> shuffle -> repeat-one -> list', () async {
    await player.playQueue(queue);
    expect(player.playMode, PlayMode.list);
    player.cyclePlayMode();
    expect(player.playMode, PlayMode.shuffle);
    expect((player.shuffle, player.repeat), (true, Repeat.list));
    player.cyclePlayMode();
    expect(player.playMode, PlayMode.one);
    expect((player.shuffle, player.repeat), (false, Repeat.one));
    player.cyclePlayMode();
    expect(player.playMode, PlayMode.list);
    expect((player.shuffle, player.repeat), (false, Repeat.list));
  });

  test('personal FM only toggles between infinite and repeat-one', () async {
    await player.playRadio(() async => [song('a'), song('b')], title: '私人 FM');
    expect(player.playMode, PlayMode.list);
    player.cyclePlayMode();
    expect(player.playMode, PlayMode.one);
    player.cyclePlayMode();
    expect(player.playMode, PlayMode.list);
    expect(player.shuffle, isFalse);
  });

  test('the chosen play mode is remembered across restarts', () async {
    PlayerController restart() =>
        PlayerController(engine: FakeEngine(), backend: FakeBackend(), settings: settings);
    player.cyclePlayMode(); // 随机
    expect(settings.playMode, 'shuffle');
    final second = restart();
    addTearDown(second.dispose);
    expect(second.playMode, PlayMode.shuffle);

    player.cyclePlayMode(); // 单曲循环
    final third = restart();
    addTearDown(third.dispose);
    expect(third.playMode, PlayMode.one);
    expect(third.repeat, Repeat.one);
  });

  test('personal FM does not overwrite the remembered shuffle', () async {
    player.cyclePlayMode(); // 随机
    await player.playRadio(() async => [song('a'), song('b')], title: '私人 FM');
    expect(player.playMode, PlayMode.list);
    player.cyclePlayMode(); // 单曲循环
    player.cyclePlayMode(); // ∞
    expect(settings.playMode, 'shuffle');
    await player.playQueue(queue);
    expect(player.playMode, PlayMode.shuffle);
  });

  test('turning off repeat-one in personal FM remembers list mode', () async {
    await player.playRadio(() async => [song('a'), song('b')], title: '私人 FM');
    player.cyclePlayMode(); // 单曲循环
    expect(settings.playMode, 'one');
    player.cyclePlayMode(); // ∞
    expect(settings.playMode, 'list');
    await player.playQueue(queue);
    expect(player.playMode, PlayMode.list);
  });

  test('a slow load for an old song does not override the new one', () async {
    final first = player.playQueue(queue); // 不等它。
    final second = player.jumpTo(2);
    await Future.wait([first, second]);
    expect(player.song.id, '3');
    expect(engine.loaded.last, contains('/3/'));
  });

  test('peekNext matches what next plays, also in shuffle', () async {
    await player.playQueue(queue, title: '测试歌单');
    expect(player.peekNext?.id, '2');
    expect(player.peekPrevious?.id, '3');
    player.toggleShuffle();
    for (var i = 0; i < 5; i++) {
      final peek = player.peekNext;
      await player.next();
      expect(player.song.id, peek?.id);
    }
  });

  test('radio prefetches the next batch before the last song and skips duplicates', () async {
    final batches = [
      [song('a'), song('b')],
      [song('b'), song('c')],
    ];
    var calls = 0;
    await player.playRadio(
      () async => calls < batches.length ? batches[calls++] : <Song>[],
      title: '私人 FM',
    );
    expect(player.isRadio, isTrue);
    // 只剩一首没放时就提前取了下一批，去重后追加 c。
    await pumpEventQueue();
    expect(player.queue.map((s) => s.id), ['a', 'b', 'c']);
    await player.next();
    expect(player.song.id, 'b');
    await player.next();
    expect(player.song.id, 'c');

    // 普通队列会退出 FM 模式。
    await player.playQueue(queue);
    expect(player.isRadio, isFalse);
  });

  test('radio retries when the next batch is all duplicates', () async {
    var calls = 0;
    await player.playRadio(() async {
      calls++;
      // 第二、三次全是重复的，第四次才有新歌。
      return calls < 4 ? [song('a'), song('b')] : [song('b'), song('c')];
    }, title: '私人 FM');
    await player.next();
    await player.next();
    expect(player.song.id, 'c');
  });

  test('radio never wraps back to the first song when no new songs come', () async {
    await player.playRadio(
      () async => [song('a'), song('b')], // 第二次起全是重复的。
      title: '私人 FM',
    );
    await player.next();
    expect(player.song.id, 'b');
    await player.next();
    expect(player.song.id, 'b');
  });

  test('radio first song failing skips forward without wrapping', () async {
    backend.unavailable.add('a');
    await player.playRadio(() async => [song('a'), song('b')], title: '私人 FM');
    await pumpEventQueue();
    expect(player.isRadio, isTrue);
    expect(player.song.id, 'b');
  });

  test('pressing next twice while the radio is fetching skips only once', () async {
    final gate = Completer<List<Song>>();
    var calls = 0;
    await player.playRadio(() {
      calls++;
      return calls == 1 ? Future.value([song('a'), song('b')]) : gate.future;
    }, title: '私人 FM');
    await player.next();
    expect(player.song.id, 'b');
    final first = player.next();
    final second = player.next();
    gate.complete([song('c'), song('d')]);
    await Future.wait([first, second]);
    expect(player.song.id, 'c');
    expect(player.queue.map((s) => s.id), ['a', 'b', 'c', 'd']);
  });

  test('radio previous on the first song stays on it', () async {
    await player.playRadio(() async => [song('a'), song('b')], title: '私人 FM');
    await player.previous(restart: false);
    expect(player.song.id, 'a');
  });

  test('previous without restart switches even after 3 seconds', () async {
    await player.playQueue(queue, start: 1);
    await player.seek(const Duration(seconds: 10));
    await player.previous(restart: false);
    expect(player.song.id, '1');
    await player.seek(const Duration(seconds: 10));
    await player.previous();
    expect(player.song.id, '1');
  });

  test('skipAndRemoveCurrent drops the song and plays the next one', () async {
    await player.playRadio(() async => [song('a'), song('b'), song('c')], title: '私人 FM');
    await player.skipAndRemoveCurrent();
    expect(player.queue.map((s) => s.id), ['b', 'c']);
    expect(player.song.id, 'b');
  });

  test('sleep timer pauses playback and can be cancelled', () async {
    await player.playQueue(queue);
    player.setSleepTimer(const Duration(milliseconds: 40));
    expect(player.sleepAt, isNotNull);
    expect(engine.playing, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(engine.playing, isFalse);
    expect(player.sleepAt, isNull);

    await player.play();
    player.setSleepTimer(const Duration(milliseconds: 40));
    player.setSleepTimer(null);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(engine.playing, isTrue);
  });

  group('sync recent plays', () {
    Future<void> listen(WidgetTester tester, int seconds) async {
      for (var i = 0; i < seconds; i++) {
        engine.advance(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    testWidgets('reports a song listened past 30s when moving on', (tester) async {
      await player.playQueue(queue, title: '歌单', sourceId: 'pl1');
      await listen(tester, 31);
      await player.next();
      expect(backend.scrobbles, hasLength(1));
      expect(backend.scrobbles.single.id, '1');
      expect(backend.scrobbles.single.sourceId, 'pl1');
      expect(backend.scrobbles.single.listened, greaterThanOrEqualTo(const Duration(seconds: 30)));
      // 「开始播放」一放就报，进官方的最近播放。
      expect(backend.starts, ['1', '2']);

      // 只听了几秒就切走：不上报。
      await listen(tester, 5);
      await player.next();
      expect(backend.scrobbles, hasLength(1));
      await player.pause();
    });

    testWidgets('seeking does not count as listening', (tester) async {
      await player.playQueue(queue);
      await listen(tester, 3);
      await player.seek(const Duration(seconds: 150));
      engine.advance(const Duration(seconds: 147));
      await tester.pump(const Duration(milliseconds: 60));
      await player.next();
      expect(backend.scrobbles, isEmpty);
      await player.pause();
    });

    testWidgets('repeat-one reports every full play of the same song', (tester) async {
      player.toggleRepeat();
      await player.playQueue(queue);
      await listen(tester, 31);
      engine.complete();
      await tester.pump(const Duration(milliseconds: 60));
      await listen(tester, 31);
      engine.complete();
      await tester.pump(const Duration(milliseconds: 60));
      expect(backend.scrobbles.map((s) => s.id), ['1', '1']);
      expect(backend.starts, ['1', '1', '1']);
      await player.pause();
    });

    testWidgets('can be turned off', (tester) async {
      settings.syncRecentPlays = false;
      await player.playQueue(queue);
      await listen(tester, 40);
      await player.next();
      expect(backend.scrobbles, isEmpty);
      expect(backend.starts, isEmpty);
      await player.pause();
    });
  });

  test('playNext moves a song right after the current one, even in shuffle', () async {
    await player.playQueue(queue, title: '测试');
    player.cyclePlayMode(); // 列表 → 随机
    expect(player.shuffle, isTrue);
    await player.playNext(song('3'));
    expect([for (final s in player.queue) s.id], ['1', '3', '2']);
    expect(player.song.id, '1');
    await player.next();
    expect(player.song.id, '3');

    await player.playNext(song('9'));
    expect([for (final s in player.queue) s.id], ['1', '3', '9', '2']);
  });

  test('playNext on an empty player starts playing the song', () async {
    await player.playNext(song('5'));
    expect(player.song.id, '5');
  });
}
