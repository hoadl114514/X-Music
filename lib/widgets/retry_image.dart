import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import '../data/retry.dart';
import 'image_disk_cache.dart';

/// 和 [NetworkImage] 一样按地址取图，但网络抖动、服务端 5xx、图片没传完导致解码失败时
/// 会自动重试（默认两次）。404 这类重试也没用的直接失败。
///
/// 下载过的图存进 [ImageDiskCache]，下次直接从磁盘读。
/// 失败的结果不进图片缓存，下次显示同一张图时会重新请求。
@immutable
class RetryNetworkImage extends ImageProvider<RetryNetworkImage> {
  const RetryNetworkImage(this.url, {this.scale = 1.0});

  final String url;
  final double scale;

  /// 测试里可以换成假的；为 null 时每次请求新建一个。
  @visibleForTesting
  static http.Client Function()? clientFactory;

  /// 重试间隔，测试里可以调短。
  @visibleForTesting
  static List<Duration> retryDelays = defaultRetryDelays;

  static const _timeout = Duration(seconds: 20);

  @override
  Future<RetryNetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<RetryNetworkImage>(this);

  @override
  ImageStreamCompleter loadImage(RetryNetworkImage key, ImageDecoderCallback decode) {
    final chunks = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _load(key, chunks, decode),
      chunkEvents: chunks.stream,
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => [
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<RetryNetworkImage>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _load(
    RetryNetworkImage key,
    StreamController<ImageChunkEvent> chunks,
    ImageDecoderCallback decode,
  ) async {
    try {
      // 先看磁盘缓存；缓存的文件坏了就删掉，走网络重新下。
      if (await ImageDiskCache.read(key.url) case final cached?) {
        try {
          return await decode(await ui.ImmutableBuffer.fromUint8List(cached));
        } catch (_) {
          await ImageDiskCache.remove(key.url);
        }
      }
      // 网易云图片在 p1–p4 几个域名上都有，有的网络（比如部分代理）连不上其中某个。
      // 当前地址重试完还不行，就换其他域名各试一次；存缓存仍用原地址。
      Object? firstError;
      for (final (i, url) in mirrorUrls(key.url).indexed) {
        try {
          return await _fetchDecoded(key, url, chunks, decode, retry: i == 0);
        } catch (e) {
          firstError ??= e;
          if (e is ImageHttpException && e.statusCode == 404) break;
        }
      }
      throw firstError!;
    } catch (_) {
      // 失败的不要留在缓存里，下次重新取。
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    } finally {
      unawaited(chunks.close());
    }
  }

  Future<ui.Codec> _fetchDecoded(
    RetryNetworkImage key,
    String url,
    StreamController<ImageChunkEvent> chunks,
    ImageDecoderCallback decode, {
    required bool retry,
  }) => withRetry(
    () async {
      final bytes = await _fetch(url, chunks);
      final codec = await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
      // 能解码才存，免得存进坏图。
      unawaited(ImageDiskCache.write(key.url, bytes));
      return codec;
    },
    delays: retry ? retryDelays : const [],
    retryIf: isRetryableImageError,
  );

  static Future<Uint8List> _fetch(String url, StreamController<ImageChunkEvent> chunks) async {
    final client = clientFactory?.call() ?? http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(url))).timeout(_timeout);
      if (res.statusCode != 200) {
        await res.stream.drain<void>();
        throw ImageHttpException(res.statusCode, url);
      }
      final total = res.contentLength;
      final builder = BytesBuilder(copy: false);
      await for (final part in res.stream.timeout(_timeout)) {
        builder.add(part);
        chunks.add(
          ImageChunkEvent(cumulativeBytesLoaded: builder.length, expectedTotalBytes: total),
        );
      }
      if (builder.isEmpty) throw ImageHttpException(res.statusCode, url, empty: true);
      if (total != null && builder.length < total) {
        throw ImageHttpException(res.statusCode, url, truncated: true);
      }
      return builder.takeBytes();
    } finally {
      client.close();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RetryNetworkImage && other.url == url && other.scale == scale;

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() => '${objectRuntimeType(this, 'RetryNetworkImage')}("$url", scale: $scale)';
}

class ImageHttpException implements Exception {
  const ImageHttpException(this.statusCode, this.url, {this.empty = false, this.truncated = false});

  final int statusCode;
  final String url;
  final bool empty;
  final bool truncated;

  @override
  String toString() => empty
      ? '图片内容为空：$url'
      : truncated
      ? '图片没有下载完整：$url'
      : '图片请求失败（HTTP $statusCode）：$url';
}

/// 4xx（除了超时和限流）说明地址本身有问题，重试没用；其余（断网、超时、5xx、解码失败）都重试。
bool isRetryableImageError(Object e) {
  if (e is ImageHttpException) {
    final s = e.statusCode;
    return e.empty || e.truncated || s >= 500 || s == 408 || s == 429;
  }
  return true;
}

/// 同一张网易云图片的几个地址：先原地址，再换 p1–p4 里的其他域名，最后试 http。
/// 不是网易云图床的地址只返回它自己。
@visibleForTesting
List<String> mirrorUrls(String url) {
  final m = RegExp(r'^(https?)://p(\d)\.music\.126\.net/').firstMatch(url);
  if (m == null) return [url];
  final rest = url.substring(m.end);
  final scheme = m[1]!;
  final n = m[2]!;
  return [
    url,
    for (final h in ['1', '2', '3', '4'])
      if (h != n) '$scheme://p$h.music.126.net/$rest',
    if (scheme == 'https') 'http://p$n.music.126.net/$rest',
  ];
}

/// 带自动重试的网络图片。[cacheWidth] 和 [Image.network] 里的一样，按这个宽度解码省内存。
ImageProvider retryImage(String url, {int? cacheWidth, int? cacheHeight}) =>
    ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight, RetryNetworkImage(url));
