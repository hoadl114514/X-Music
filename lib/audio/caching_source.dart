// StreamAudioSource 在 just_audio 里标着实验性，但它是自定义音频数据的唯一入口。
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';

import 'audio_cache.dart';

/// 边播边缓存的音频源：播放器要的数据从网络取，顺序到达的部分同时写进缓存文件。
///
/// - 文件里已经有的部分直接读文件，只从网络取剩下的，上次没听完的歌接着下载。
/// - 往后拖动到还没下载的位置时，那一段只转发不写入；之后从头播放时再补齐。
/// - 切歌、拖动时播放器会断开连接，这里跟着断开网络请求，不会在后台把整首下完。
///
/// 和 just_audio 自带的 LockCachingAudioSource 相比，主要区别是最后这一点：
/// 自带的会把跳过的歌也整首下完，开着移动网络切歌会白白耗流量。
class CachingAudioSource extends StreamAudioSource {
  CachingAudioSource(this.uri, this.slot);

  final Uri uri;
  final CacheSlot slot;

  final _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..autoUncompress = false;

  /// 当前负责写文件的连接。新请求来时先让它停笔，保证同一时间只有一个写入方。
  _Writer? _writer;

  void dispose() {
    _writer?.stop();
    _client.close();
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0;
    await _writer?.stop();
    _writer = null;

    // 这首已经下完了（例如刚刚写满）：全从文件读。
    final done = slot.file;
    if (await done.exists()) {
      final total = await done.length();
      return _response(total, from, end, done.openRead(from, end ?? total));
    }

    final part = await slot.existingPart();
    final have = part?.length ?? 0;

    // 要的这段文件里全有。
    if (part != null && end != null && end <= have) {
      return _response(part.total, from, end, part.file.openRead(from, end));
    }

    // 从文件已有部分之内（或正好接着）开始：先读文件，再从网络接着取并写入。
    if (part != null && from <= have) {
      final up = await _open(have, end);
      if (up.total != part.total || up.offset != have) {
        // 服务端的文件换了，或者不支持断点续传：半截作废，重新来。
        await up.cancel();
        await slot.discardParts();
        return request(start, end);
      }
      final writer = _writer = _Writer(slot, part.file, part.total, have);
      return _response(
        part.total,
        from,
        end,
        _concat(part.file.openRead(from, have), up.stream(writer), up.cancel),
      );
    }

    final up = await _open(from, end);
    // 从头开始而且知道整首多大：新建半截文件，边播边写。
    final total = up.total;
    if (part == null && from == 0 && up.offset == 0 && total != null) {
      slot.started(total);
      final writer = _writer = _Writer(slot, slot.partFile(total), total, 0);
      return _response(total, 0, end, up.stream(writer));
    }
    // 其他情况（拖到了还没下载的位置等）只转发。
    return _response(up.total, from, end, up.stream(null, skip: from - up.offset));
  }

  StreamAudioResponse _response(int? total, int from, int? end, Stream<List<int>> stream) {
    final stop = end ?? total;
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: stop == null ? null : stop - from,
      offset: from,
      stream: stream,
      contentType: slot.contentType,
    );
  }

  /// 文件部分读完再接网络部分。中途被取消时也要断开网络连接。
  static Stream<List<int>> _concat(
    Stream<List<int>> file,
    Stream<List<int>> network,
    void Function() cancel,
  ) async* {
    try {
      yield* file;
      yield* network;
    } finally {
      cancel();
    }
  }

  Future<_Upstream> _open(int from, int? end) async {
    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    if (from > 0 || end != null) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-${end == null ? '' : end - 1}');
    }
    final response = await request.close();
    if (response.statusCode == HttpStatus.partialContent) {
      // Content-Range: bytes 100-199/1000
      final range = response.headers.value(HttpHeaders.contentRangeHeader) ?? '';
      final m = RegExp(r'bytes (\d+)-\d+/(\d+)').firstMatch(range);
      if (m != null) {
        return _Upstream(response, int.parse(m[1]!), int.parse(m[2]!));
      }
    }
    if (response.statusCode == HttpStatus.ok) {
      // 服务端忽略了 Range，从头给了整个文件。
      return _Upstream(response, 0, response.contentLength < 0 ? null : response.contentLength);
    }
    unawaited(response.drain<void>().catchError((Object _) {}));
    throw HttpException('HTTP ${response.statusCode}', uri: uri);
  }
}

/// 一个网络响应：数据从 [offset] 开始，整首共 [total] 字节（未知时为 null）。
class _Upstream {
  _Upstream(this._response, this.offset, this.total);

  final HttpClientResponse _response;
  final int offset;
  final int? total;
  StreamSubscription<List<int>>? _sub;
  bool _cancelled = false;

  /// 转给播放器的数据流，顺带交给 [writer] 写入。[skip] 是开头要丢掉的字节数。
  Stream<List<int>> stream(_Writer? writer, {int skip = 0}) {
    late final StreamController<List<int>> out;
    var toSkip = skip;
    out = StreamController<List<int>>(
      onListen: () {
        if (_cancelled) {
          out.close();
          return;
        }
        _sub = _response.listen(
          (data) {
            writer?.add(data);
            if (toSkip > 0) {
              if (data.length <= toSkip) {
                toSkip -= data.length;
                return;
              }
              data = data.sublist(toSkip);
              toSkip = 0;
            }
            out.add(data);
          },
          onError: (Object e, StackTrace st) {
            writer?.stop();
            out.addError(e, st);
          },
          onDone: () {
            writer?.stop();
            out.close();
          },
          cancelOnError: true,
        );
      },
      onPause: () => _sub?.pause(),
      onResume: () => _sub?.resume(),
      onCancel: () {
        writer?.stop();
        return cancel();
      },
    );
    return out.stream;
  }

  /// 断开连接。还没开始读时也要读一下再取消，才会关掉底层连接。
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    final sub = _sub ?? _response.listen(null);
    await sub.cancel().catchError((Object _) {});
  }
}

/// 往半截文件末尾追加数据，写满整首后交给 [CacheSlot.completed]。
class _Writer {
  _Writer(this.slot, this.file, this.total, this.length)
    : _sink = file.openWrite(mode: FileMode.append);

  final CacheSlot slot;
  final File file;
  final int total;
  int length;
  final IOSink _sink;
  Future<void>? _stopped;

  void add(List<int> data) {
    if (_stopped != null) return;
    if (length + data.length > total) {
      // 比说好的多，文件不对，作废。
      unawaited(stop().then((_) => slot.discardParts()));
      return;
    }
    _sink.add(data);
    length += data.length;
    slot.grew(total, length);
    if (length == total) unawaited(stop());
  }

  /// 停止写入并落盘；写满了就转正。可以重复调用。
  Future<void> stop() => _stopped ??= () async {
    try {
      await _sink.flush();
      await _sink.close();
    } catch (_) {}
    if (length == total) await slot.completed(file, total);
  }();
}
