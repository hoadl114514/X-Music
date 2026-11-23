import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/data/retry.dart';
import 'package:netease_client/widgets/image_disk_cache.dart';
import 'package:netease_client/widgets/retry_image.dart';

/// 1×1 的 PNG。
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  group('withRetry', () {
    const fast = [Duration.zero, Duration.zero];

    test('retries until it succeeds', () async {
      var calls = 0;
      final v = await withRetry(() async {
        if (++calls < 3) throw Exception('flaky');
        return 'ok';
      }, delays: fast);
      expect(v, 'ok');
      expect(calls, 3);
    });

    test('gives up after the last delay and rethrows', () async {
      var calls = 0;
      await expectLater(
        withRetry<void>(() async {
          calls++;
          throw StateError('down');
        }, delays: fast),
        throwsStateError,
      );
      expect(calls, 3);
    });

    test('does not retry errors that retryIf rejects, and stops when asked', () async {
      var calls = 0;
      await expectLater(
        withRetry<void>(
          () async {
            calls++;
            throw ArgumentError('404');
          },
          delays: fast,
          retryIf: (e) => e is! ArgumentError,
        ),
        throwsArgumentError,
      );
      expect(calls, 1);

      calls = 0;
      await expectLater(
        withRetry<void>(
          () async {
            calls++;
            throw Exception('x');
          },
          delays: fast,
          shouldStop: () => true,
        ),
        throwsException,
      );
      expect(calls, 1);
    });
  });

  group('RetryNetworkImage', () {
    setUp(() => ImageDiskCache.directory = null);
    tearDown(() {
      ImageDiskCache.resetDirectory();
      RetryNetworkImage.clientFactory = null;
      RetryNetworkImage.retryDelays = defaultRetryDelays;
      PaintingBinding.instance.imageCache.clear();
    });

    Future<ui.Image> resolve(ImageProvider provider) {
      final done = Completer<ui.Image>();
      final stream = provider.resolve(ImageConfiguration.empty);
      stream.addListener(
        ImageStreamListener(
          (info, _) => done.complete(info.image),
          onError: (e, _) => done.completeError(e),
        ),
      );
      return done.future;
    }

    testWidgets('retries server errors and truncated bodies, then decodes', (tester) async {
      var calls = 0;
      RetryNetworkImage.retryDelays = const [Duration.zero, Duration.zero];
      RetryNetworkImage.clientFactory = () => MockClient((r) async {
        calls++;
        return switch (calls) {
          1 => http.Response('busy', 503),
          2 => http.Response.bytes(
            _png.sublist(0, 10),
            200,
            headers: {'content-length': '${_png.length}'},
          ),
          _ => http.Response.bytes(_png, 200),
        };
      });
      final image = await tester.runAsync(
        () => resolve(const RetryNetworkImage('https://a/1.png')),
      );
      expect(image!.width, 1);
      expect(calls, 3);
    });

    test('disk cache stores, reads back and removes by URL', () async {
      final dir = Directory.systemTemp.createTempSync('img_cache_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      ImageDiskCache.directory = dir;
      expect(await ImageDiskCache.read('https://a/3.png'), isNull);
      await ImageDiskCache.write('https://a/3.png', _png);
      expect(await ImageDiskCache.read('https://a/3.png'), _png);
      expect(dir.listSync(), hasLength(1));
      await ImageDiskCache.remove('https://a/3.png');
      expect(await ImageDiskCache.read('https://a/3.png'), isNull);
    });

    testWidgets('images are cached after download and read back without the network', (
      tester,
    ) async {
      final store = ImageDiskCache.memory = {};
      var calls = 0;
      RetryNetworkImage.clientFactory = () => MockClient((r) async {
        calls++;
        return http.Response.bytes(_png, 200);
      });
      await tester.runAsync(() => resolve(const RetryNetworkImage('https://a/4.png')));
      await tester.runAsync(pumpEventQueue);
      expect(calls, 1);
      expect(store.keys, ['https://a/4.png']);

      // 内存缓存清掉后再显示：从磁盘读，不再请求网络。
      PaintingBinding.instance.imageCache.clear();
      final image = await tester.runAsync(
        () => resolve(const RetryNetworkImage('https://a/4.png')),
      );
      expect(image!.width, 1);
      expect(calls, 1);

      // 缓存的文件坏了：删掉，走网络重新下。
      store['https://a/5.png'] = Uint8List.fromList([1, 2, 3]);
      await tester.runAsync(() => resolve(const RetryNetworkImage('https://a/5.png')));
      expect(calls, 2);
      expect(store['https://a/5.png'], _png);
    });

    test('prune deletes the least recently used files first', () async {
      final dir = Directory.systemTemp.createTempSync('img_prune_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      ImageDiskCache.directory = dir;
      for (final (i, name) in ['old', 'mid', 'new'].indexed) {
        File('${dir.path}/$name')
          ..writeAsBytesSync(List.filled(100, 0))
          ..setLastModifiedSync(DateTime(2026, 1, i + 1));
      }
      await ImageDiskCache.prune(limit: 250);
      expect(dir.listSync().map((e) => e.uri.pathSegments.last).toSet(), {'mid', 'new'});
    });

    testWidgets('does not retry a 404', (tester) async {
      var calls = 0;
      RetryNetworkImage.retryDelays = const [Duration.zero, Duration.zero];
      RetryNetworkImage.clientFactory = () => MockClient((r) async {
        calls++;
        return http.Response('nope', 404);
      });
      await tester.runAsync(() async {
        await expectLater(
          resolve(const RetryNetworkImage('https://a/2.png')),
          throwsA(isA<ImageHttpException>()),
        );
      });
      expect(calls, 1);
    });

    test('mirror URLs try the other NetEase image hosts, then http', () {
      expect(mirrorUrls('https://p1.music.126.net/a==/1.jpg?param=128y128'), [
        'https://p1.music.126.net/a==/1.jpg?param=128y128',
        'https://p2.music.126.net/a==/1.jpg?param=128y128',
        'https://p3.music.126.net/a==/1.jpg?param=128y128',
        'https://p4.music.126.net/a==/1.jpg?param=128y128',
        'http://p1.music.126.net/a==/1.jpg?param=128y128',
      ]);
      expect(mirrorUrls('https://a/1.png'), ['https://a/1.png']);
    });

    testWidgets('an unreachable NetEase host falls back to another one', (tester) async {
      final hosts = <String>[];
      RetryNetworkImage.retryDelays = const [Duration.zero];
      RetryNetworkImage.clientFactory = () => MockClient((r) async {
        hosts.add(r.url.host);
        if (r.url.host == 'p1.music.126.net') throw http.ClientException('connection reset');
        return http.Response.bytes(_png, 200);
      });
      final image = await tester.runAsync(
        () => resolve(const RetryNetworkImage('https://p1.music.126.net/a==/1.jpg')),
      );
      expect(image!.width, 1);
      // 原域名重试一次，然后换 p2 成功。
      expect(hosts, ['p1.music.126.net', 'p1.music.126.net', 'p2.music.126.net']);
    });
  });
}
