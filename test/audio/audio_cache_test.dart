import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/audio/audio_cache.dart';
import 'package:netease_client/data/models.dart';

void main() {
  late Directory dir;
  late int limit;
  late AudioCache cache;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('audio_cache_test');
    limit = 1 << 30;
    cache = AudioCache(directory: Future.value(dir), limit: () => limit);
  });
  tearDown(() async {
    cache.dispose();
    await dir.delete(recursive: true);
  });

  /// 直接在目录里放一个缓存文件，[age] 越大越久没播放。
  Future<File> put(String name, int size, {int age = 0}) async {
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(List.filled(size, 1));
    await f.setLastModified(DateTime.now().subtract(Duration(hours: age)));
    return f;
  }

  test('lookup prefers the file stored for the requested quality', () async {
    await put('1_lossless_exhigh.mp3', 10);
    await put('1_hires_hires.flac', 10);
    // 没会员：按无损请求时实际给的极高，下次按无损请求还用它，不重新下载。
    final hit = await cache.lookup('1', AudioQuality.lossless);
    expect(hit!.file.path, endsWith('1_lossless_exhigh.mp3'));
    expect(hit.quality, AudioQuality.exhigh);
  });

  test('lookup falls back to the closest quality not below the target', () async {
    await put('1_standard_standard.mp3', 10);
    await put('1_lossless_lossless.flac', 10);
    await put('1_hires_hires.flac', 10);
    expect((await cache.lookup('1', AudioQuality.exhigh))!.quality, AudioQuality.lossless);
    expect(await cache.lookup('1', AudioQuality.jymaster), isNull);
    expect(await cache.lookup('2', AudioQuality.standard), isNull);
    expect((await cache.best('1'))!.quality, AudioQuality.hires);
  });

  test('half-downloaded files are never played', () async {
    await put('1_exhigh_exhigh.mp3.100.part', 50);
    expect(await cache.lookup('1', AudioQuality.exhigh), isNull);
    expect(await cache.best('1'), isNull);
  });

  test('init prunes the least recently played songs down to the limit', () async {
    await put('1_exhigh_exhigh.mp3', 400, age: 3);
    await put('2_exhigh_exhigh.mp3', 400, age: 1);
    await put('3_exhigh_exhigh.mp3', 400, age: 2);
    limit = 900;
    await cache.init();
    expect(cache.usedBytes, 800);
    expect(File('${dir.path}/1_exhigh_exhigh.mp3').existsSync(), isFalse);
    expect(File('${dir.path}/2_exhigh_exhigh.mp3').existsSync(), isTrue);
  });

  test('playing a song marks it as recently used', () async {
    await put('1_exhigh_exhigh.mp3', 400, age: 3);
    await put('2_exhigh_exhigh.mp3', 400, age: 1);
    await cache.init();
    await cache.lookup('1', AudioQuality.exhigh);
    await cache.lookup('2', AudioQuality.exhigh);
    limit = 500;
    await cache.prune();
    // 2 是正在放的，1 刚刚播放过但比 2 早：删 1。
    expect(File('${dir.path}/1_exhigh_exhigh.mp3').existsSync(), isFalse);
    expect(File('${dir.path}/2_exhigh_exhigh.mp3').existsSync(), isTrue);
  });

  test('the song being played is kept even when it alone is over the limit', () async {
    await put('1_exhigh_exhigh.mp3', 400);
    await cache.lookup('1', AudioQuality.exhigh);
    limit = 100;
    await cache.prune();
    expect(File('${dir.path}/1_exhigh_exhigh.mp3').existsSync(), isTrue);
  });

  test('a completed part becomes a cached song', () async {
    await cache.init();
    final slot = (await cache.slot(
      '7',
      AudioQuality.lossless,
      AudioQuality.exhigh,
      'http://m701.music.126.net/a/b/abc.mp3?x=1',
    ))!;
    expect(slot.base, '7_lossless_exhigh.mp3');
    expect(slot.contentType, 'audio/mpeg');
    slot.started(5);
    final part = slot.partFile(5);
    await part.writeAsBytes([1, 2, 3, 4, 5]);
    expect((await slot.existingPart())!.length, 5);
    await slot.completed(part, 5);
    expect(part.existsSync(), isFalse);
    expect((await cache.lookup('7', AudioQuality.lossless))!.file.readAsBytesSync(), [
      1,
      2,
      3,
      4,
      5,
    ]);
    expect(cache.usedBytes, 5);
  });

  test('a part with the wrong length is thrown away', () async {
    await cache.init();
    final slot = (await cache.slot(
      '7',
      AudioQuality.exhigh,
      AudioQuality.exhigh,
      'http://x/a.mp3',
    ))!;
    slot.started(10);
    final part = slot.partFile(10);
    await part.writeAsBytes([1, 2, 3]);
    await slot.completed(part, 10);
    expect(part.existsSync(), isFalse);
    expect(await cache.lookup('7', AudioQuality.exhigh), isNull);
  });

  test('limit 0 turns caching off', () async {
    limit = 0;
    expect(
      await cache.slot('1', AudioQuality.exhigh, AudioQuality.exhigh, 'http://x/a.mp3'),
      isNull,
    );
  });

  test('clear removes everything', () async {
    await put('1_exhigh_exhigh.mp3', 10);
    await put('2_exhigh_exhigh.mp3.9.part', 3);
    await cache.init();
    expect(cache.usedBytes, 13);
    await cache.clear();
    expect(cache.usedBytes, 0);
    expect(dir.listSync(), isEmpty);
  });

  test('files removed by the system are dropped from the index', () async {
    final f = await put('1_exhigh_exhigh.mp3', 10);
    await cache.init();
    await f.delete();
    expect(await cache.lookup('1', AudioQuality.exhigh), isNull);
    expect(cache.usedBytes, 0);
  });
}
