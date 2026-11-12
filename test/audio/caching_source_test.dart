import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/audio/audio_cache.dart';
import 'package:netease_client/audio/caching_source.dart';
import 'package:netease_client/data/models.dart';

/// 支持 Range 的本地音频服务器，记下每次请求的 Range 头。
class _Server {
  _Server(this.data);

  final List<int> data;
  final ranges = <String?>[];

  /// 每块之间停一下，模拟网速有限。
  bool slow = false;
  late HttpServer _server;

  Uri get uri => Uri.parse('http://127.0.0.1:${_server.port}/song.mp3');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      final range = req.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range);
      final res = req.response;
      var start = 0, end = data.length - 1;
      if (range != null) {
        final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
        start = int.parse(m[1]!);
        if (m[2]!.isNotEmpty) end = int.parse(m[2]!);
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${data.length}');
      }
      res.contentLength = end - start + 1;
      // 分块发，方便测试中途断开。
      for (var i = start; i <= end; i += 1000) {
        res.add(data.sublist(i, i + 1000 > end + 1 ? end + 1 : i + 1000));
        await res.flush();
        if (slow) await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await res.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late Directory dir;
  late AudioCache cache;
  late _Server server;
  final data = List<int>.generate(10000, (i) => i % 251);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('caching_source_test');
    cache = AudioCache(directory: Future.value(dir), limit: () => 1 << 30);
    server = _Server(data);
    await server.start();
  });
  tearDown(() async {
    await server.stop();
    cache.dispose();
    await dir.delete(recursive: true);
  });

  Future<CachingAudioSource> source() async => CachingAudioSource(
    server.uri,
    (await cache.slot('1', AudioQuality.exhigh, AudioQuality.exhigh, server.uri.toString()))!,
  );

  /// 等后台的写入、改名做完。
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 100));

  test('playing a song through saves the whole file', () async {
    final s = await source();
    final res = await s.request();
    expect(res.sourceLength, data.length);
    expect(res.contentType, 'audio/mpeg');
    final got = await res.stream.expand((b) => b).toList();
    expect(got, data);
    await settle();
    final hit = await cache.lookup('1', AudioQuality.exhigh);
    expect(hit!.file.readAsBytesSync(), data);
    s.dispose();
  });

  test('a song skipped halfway resumes from where it stopped', () async {
    server.slow = true;
    final s = await source();
    final res = await s.request();
    final got = <int>[];
    final done = Completer<void>();
    late StreamSubscription<List<int>> sub;
    sub = res.stream.listen((b) {
      got.addAll(b);
      if (got.length >= 3000 && !done.isCompleted) {
        done.complete();
        sub.cancel();
      }
    });
    await done.future;
    await settle();
    expect(await cache.lookup('1', AudioQuality.exhigh), isNull);
    final part = await (await cache.slot(
      '1',
      AudioQuality.exhigh,
      AudioQuality.exhigh,
      '',
    ))!.existingPart();
    expect(part!.length, greaterThanOrEqualTo(3000));
    expect(part.length, lessThan(data.length));

    // 下次从头放：文件里有的直接读，网络只取剩下的。
    final again = await s.request();
    expect(await again.stream.expand((b) => b).toList(), data);
    expect(server.ranges.last, 'bytes=${part.length}-');
    await settle();
    expect((await cache.lookup('1', AudioQuality.exhigh))!.file.readAsBytesSync(), data);
    s.dispose();
  });

  test('seeking past the downloaded part streams without writing', () async {
    final s = await source();
    final res = await s.request(6000);
    expect(res.offset, 6000);
    expect(await res.stream.expand((b) => b).toList(), data.sublist(6000));
    await settle();
    expect(await cache.lookup('1', AudioQuality.exhigh), isNull);
    expect(cache.usedBytes, 0);
    s.dispose();
  });

  test('bounded range requests (iOS) still fill the cache in order', () async {
    final s = await source();
    for (var start = 0; start < data.length; start += 4000) {
      final end = start + 4000 > data.length ? data.length : start + 4000;
      final res = await s.request(start, end);
      expect(res.contentLength, end - start);
      expect(await res.stream.expand((b) => b).toList(), data.sublist(start, end));
    }
    await settle();
    expect((await cache.lookup('1', AudioQuality.exhigh))!.file.readAsBytesSync(), data);
    // 已经下好的部分再要一次：直接读文件。
    final count = server.ranges.length;
    final res = await s.request(100, 200);
    expect(await res.stream.expand((b) => b).toList(), data.sublist(100, 200));
    expect(server.ranges.length, count);
    s.dispose();
  });
}
