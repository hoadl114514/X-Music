import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../api/netease_api.dart';
import 'models.dart';

/// 歌单歌曲的本地存储：一个歌单一个 JSON。
abstract class TrackStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);

  /// 占用的字节数。
  Future<int> usedBytes();

  /// 全部删掉。
  Future<void> clear();
}

/// 存在应用私有目录的 `track_cache/` 下。取不到目录（网页版、测试）时什么都不存。
class FileTrackStore implements TrackStore {
  Future<Directory?>? _dir;

  Future<Directory?> _directory() => _dir ??= () async {
    if (kIsWeb) return null;
    try {
      final base = await getApplicationSupportDirectory();
      return await Directory('${base.path}/track_cache').create(recursive: true);
    } catch (_) {
      return null;
    }
  }();

  Future<File?> _file(String key) async {
    final dir = await _directory();
    return dir == null ? null : File('${dir.path}/$key.json');
  }

  @override
  Future<String?> read(String key) async {
    try {
      final f = await _file(key);
      return f != null && await f.exists() ? await f.readAsString() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      final f = await _file(key);
      if (f == null) return;
      // 先写临时文件再改名，写到一半被杀也不会留下坏文件。
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(value, flush: true);
      await tmp.rename(f.path);
    } catch (_) {
      // 缓存写不进去不影响使用。
    }
  }

  @override
  Future<int> usedBytes() async {
    try {
      final dir = await _directory();
      if (dir == null) return 0;
      var total = 0;
      await for (final e in dir.list()) {
        if (e is File) total += await e.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> clear() async {
    try {
      final dir = await _directory();
      if (dir == null) return;
      await for (final e in dir.list()) {
        if (e is File) await e.delete();
      }
    } catch (_) {}
  }
}

class MemoryTrackStore implements TrackStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<int> usedBytes() async =>
      data.values.fold<int>(0, (sum, v) => sum + utf8.encode(v).length);

  @override
  Future<void> clear() async => data.clear();
}

/// 页面数据的本地缓存：先给缓存，同时后台取最新的，有变化再发一次。
///
/// 和「我喜欢」歌单同一套存储，都算在「听歌缓存」里。
class DataCache {
  DataCache({TrackStore? store}) : store = store ?? MemoryTrackStore();

  final TrackStore store;

  /// 本次运行里读过 / 写过的 JSON 文本，切回来不用再读文件。
  final _memory = <String, String>{};

  /// 读 [key]；没有或格式不对（比如旧版本）时返回 null。
  Future<T?> read<T>(String key, T? Function(Object? json) decode) async {
    final raw = _memory[key] ?? await store.read(key);
    if (raw == null) return null;
    try {
      final value = decode(jsonDecode(raw));
      if (value != null) _memory[key] = raw;
      return value;
    } catch (_) {
      return null;
    }
  }

  /// 写 [key]。[json] 要能被 `jsonEncode` 编码。
  Future<void> write(String key, Object? json) {
    final raw = jsonEncode(json);
    if (_memory[key] == raw) return Future.value();
    _memory[key] = raw;
    return store.write(key, raw);
  }

  /// 先发缓存（有的话，[force] 时跳过），再发 [fetch] 的结果；和缓存一样就不再发。
  /// [fetch] 出错时，已经发过缓存的照样报错，由页面决定是只提示还是显示错误。
  Stream<T> watch<T>(
    String key, {
    required Future<T> Function() fetch,
    required Object? Function(T value) encode,
    required T? Function(Object? json) decode,
    bool force = false,
  }) async* {
    final cached = force ? null : await read(key, decode);
    if (cached != null) yield cached;
    final fresh = await fetch();
    final json = encode(fresh);
    final same = cached != null && _memory[key] == jsonEncode(json);
    if (!same) yield fresh;
    unawaited(write(key, json));
  }

  /// 删掉全部缓存（清空听歌缓存时用）。
  Future<void> clear() async {
    _memory.clear();
    await store.clear();
  }
}

/// 歌单歌曲：先给本地缓存，同时在后台和服务端比对增删。
///
/// 比对只取一次歌单的歌曲 id 列表，只为新增的歌取详情，所以歌很多时同步也快；
/// 下拉刷新时用 `force` 全部重新取，顺便更新歌名、封面这些可能变了的信息。
class PlaylistTracks {
  PlaylistTracks(this._api, {TrackStore? store}) : _store = store ?? MemoryTrackStore();

  final NeteaseApi _api;
  final TrackStore _store;

  /// 本次运行里读过 / 同步过的，切回来不用再读文件。
  final _memory = <String, List<Song>>{};

  static const _version = 1;

  /// 先发缓存（有的话），再发和服务端比对后的列表（和缓存一样就不再发）。
  /// [cache] 为 false 时不读也不写缓存（别人的歌单没必要存）。
  Stream<List<Song>> watch(String playlistId, {bool cache = true, bool force = false}) async* {
    List<Song>? cached;
    if (cache) {
      cached = _memory[playlistId] ?? await _read(playlistId);
      if (cached != null && !force) yield cached;
    }
    final (:playlist, :ids) = await _api.playlistTrackIds(playlistId);
    final known = <String, Song>{
      if (!force)
        for (final s in cached ?? const <Song>[]) s.id: s,
    };
    final missing = [
      for (final id in ids)
        if (!known.containsKey(id)) id,
    ];
    if (missing.isNotEmpty) {
      for (final s in await _api.songDetails(missing)) {
        known[s.id] = s;
      }
    }
    final fresh = [for (final id in ids) ?known[id]];
    if (force || cached == null || !_sameOrder(cached, fresh)) yield fresh;
    if (cache) {
      _memory[playlistId] = fresh;
      unawaited(_write(playlistId, fresh));
    }
  }

  /// 从歌单 [playlistId] 的本地缓存里去掉 [songIds]（删歌成功后调用，免得重进时闪回旧列表）。
  Future<void> removeCached(String playlistId, Set<String> songIds) async {
    final cached = _memory[playlistId] ?? await _read(playlistId);
    if (cached == null) return;
    final kept = [
      for (final s in cached)
        if (!songIds.contains(s.id)) s,
    ];
    _memory[playlistId] = kept;
    await _write(playlistId, kept);
  }

  static bool _sameOrder(List<Song> a, List<Song> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  Future<List<Song>?> _read(String id) async {
    final raw = await _store.read('pl_$id');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map || json['v'] != _version || json['songs'] is! List) return null;
      final songs = [for (final s in json['songs'] as List) ?Song.fromJson(s)];
      _memory[id] = songs;
      return songs;
    } on FormatException {
      return null;
    }
  }

  Future<void> _write(String id, List<Song> songs) => _store.write(
    'pl_$id',
    jsonEncode({
      'v': _version,
      'songs': [for (final s in songs) s.toJson()],
    }),
  );
}
