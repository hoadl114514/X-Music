import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models.dart';

/// 本地缓存里的一首歌。
class CachedAudio {
  const CachedAudio(this.file, this.quality);

  final File file;

  /// 缓存文件实际的音质。
  final AudioQuality quality;
}

/// 一首歌正在写入的缓存位置：边播边写到 `.part` 文件，写满后改名成正式文件。
///
/// 半截文件名里带着整首的字节数，下次接着下载前用它确认还是同一个文件。
class CacheSlot {
  CacheSlot._(this._cache, this.base, this.contentType);

  final AudioCache _cache;

  /// 不含目录的文件名，例如 `123_exhigh_exhigh.mp3`。
  final String base;

  /// 交给播放器的 MIME 类型。
  final String contentType;

  File get file => File('${_cache._path}/$base');

  File partFile(int total) => File('${_cache._path}/$base.$total.part');

  /// 上次没下完的半截：文件、整首字节数、已有字节数。
  Future<({File file, int total, int length})?> existingPart() async {
    for (final name in _cache._entries.keys.toList()) {
      final total = _partTotal(name);
      if (total == null || !name.startsWith('$base.')) continue;
      final f = File('${_cache._path}/$name');
      try {
        if (await f.exists()) return (file: f, total: total, length: await f.length());
      } catch (_) {}
      _cache._forget(name);
    }
    return null;
  }

  /// 删掉这首歌所有的半截文件（换了文件、写坏了时）。
  Future<void> discardParts() async {
    for (final name in _cache._entries.keys.toList()) {
      if (name.startsWith('$base.') && name.endsWith('.part')) await _cache._delete(name);
    }
  }

  /// 边写边更新索引里半截文件的大小。
  void grew(int total, int length) => _cache._grow('$base.$total.part', length);

  /// 开始写一个新的半截文件。
  void started(int total) => _cache._record('$base.$total.part', 0);

  /// 半截文件写满了：校验长度后改名成正式文件，然后按上限清理旧缓存。
  Future<void> completed(File part, int total) async {
    final partName = '$base.$total.part';
    try {
      if (await part.length() != total) {
        await _cache._delete(partName);
        return;
      }
      await part.rename(file.path);
      _cache._forget(partName);
      _cache._record(base, total);
      await _cache.prune();
    } catch (_) {
      // 改名失败（例如刚被清空）就算了，下次重新下载。
      _cache._forget(partName);
    }
  }

  static int? _partTotal(String name) {
    if (!name.endsWith('.part')) return null;
    final parts = name.substring(0, name.length - 5).split('.');
    return parts.length < 2 ? null : int.tryParse(parts.last);
  }
}

/// 听歌缓存：听过的歌存在本机，再听时直接读文件，不耗流量。
///
/// 文件放在系统缓存目录的 `audio_cache/` 下，名字是 `歌曲id_请求的音质_实际音质.扩展名`。
/// 总大小超过 [limit] 时，从最久没播放的开始删。正在放的那首不删。
/// 取不到目录（网页版、测试）时什么都不做。
class AudioCache extends ChangeNotifier {
  AudioCache({required Future<Directory?> directory, required this._limit})
    : _dirFuture = directory;

  /// 正式环境：系统缓存目录，系统空间不足时也可以清理它。
  factory AudioCache.system({required int Function() limit}) => AudioCache(
    directory: () async {
      if (kIsWeb) return null;
      try {
        final base = await getApplicationCacheDirectory();
        return await Directory('${base.path}/audio_cache').create(recursive: true);
      } catch (_) {
        return null;
      }
    }(),
    limit: limit,
  );

  static const defaultLimit = 5 << 30;

  final Future<Directory?> _dirFuture;
  final int Function() _limit;
  String _path = '';

  /// 文件名 → 大小和最近播放时间。
  final _entries = <String, ({int size, DateTime used})>{};
  Future<bool>? _loaded;

  /// 正在放的那首（文件名前缀），清理时跳过。
  String? _protected;

  /// 上限（字节）。0 表示不缓存。
  int get limit => _limit();

  /// 已经占用的字节数（包括没下完的半截）。
  int get usedBytes => _entries.values.fold(0, (sum, e) => sum + e.size);

  /// 读一遍目录建好索引。之后都以索引为准，文件被系统删掉时按需修正。
  Future<bool> _ready() => _loaded ??= () async {
    final dir = await _dirFuture;
    if (dir == null) return false;
    _path = dir.path;
    try {
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final stat = await e.stat();
        _entries[e.uri.pathSegments.last] = (size: stat.size, used: stat.modified);
      }
    } catch (_) {}
    notifyListeners();
    return true;
  }();

  /// 启动时调用：建索引，按上限清理一次。
  Future<void> init() async {
    if (await _ready()) await prune();
  }

  /// 找这首歌能用的缓存：优先是按 [target] 请求时存下的，其次是不低于 [target] 的最低一档。
  ///
  /// 账号没有会员时服务端会降档，所以按「请求的音质」也能命中，免得每次都重新下载。
  Future<CachedAudio?> lookup(String songId, AudioQuality target) =>
      _find(songId, (requested, served) {
        if (requested == target) return 0;
        if (served.index >= target.index) return 1 + served.index - target.index;
        return null;
      });

  /// 这首歌音质最高的缓存，联网失败时用。
  Future<CachedAudio?> best(String songId) =>
      _find(songId, (_, served) => AudioQuality.values.length - served.index);

  /// [rank] 越小越好，返回 null 表示不要。命中后标成最近播放。
  Future<CachedAudio?> _find(String songId, int? Function(AudioQuality, AudioQuality) rank) async {
    if (!await _ready()) return null;
    while (true) {
      (String, AudioQuality, int)? pick;
      for (final name in _entries.keys) {
        final parsed = _parse(name);
        if (parsed == null || parsed.songId != songId) continue;
        final r = rank(parsed.requested, parsed.served);
        if (r != null && (pick == null || r < pick.$3)) pick = (name, parsed.served, r);
      }
      if (pick == null) return null;
      final file = File('$_path/${pick.$1}');
      if (!await file.exists()) {
        _forget(pick.$1); // 被系统清掉了。
        continue;
      }
      _protected = '${songId}_';
      _touch(pick.$1, file);
      return CachedAudio(file, pick.$2);
    }
  }

  /// 给一首要在线播放的歌分配缓存位置。不缓存（上限为 0、没有目录）时返回 null。
  Future<CacheSlot?> slot(
    String songId,
    AudioQuality requested,
    AudioQuality served,
    String url,
  ) async {
    if (limit <= 0 || !await _ready()) return null;
    _protected = '${songId}_';
    final ext = _extension(url);
    return CacheSlot._(
      this,
      '${songId}_${requested.level}_${served.level}$ext',
      _mime[ext] ?? 'audio/mpeg',
    );
  }

  /// 超过上限时从最久没播放的开始删。正在放的那首不删。
  Future<void> prune() async {
    if (!await _ready()) return;
    final limit = this.limit;
    var total = usedBytes;
    if (total <= limit) return;
    final names = _entries.keys.toList()
      ..sort((a, b) => _entries[a]!.used.compareTo(_entries[b]!.used));
    for (final name in names) {
      if (total <= limit) break;
      final protected = _protected;
      if (protected != null && name.startsWith(protected)) continue;
      total -= _entries[name]!.size;
      await _delete(name);
    }
  }

  /// 清空全部缓存。
  Future<void> clear() async {
    if (!await _ready()) return;
    for (final name in _entries.keys.toList()) {
      await _delete(name);
    }
    // 索引外的残留（例如上次写到一半的临时文件）也一起删。
    try {
      await for (final e in Directory(_path).list()) {
        if (e is File) await e.delete();
      }
    } catch (_) {}
    notifyListeners();
  }

  void _touch(String name, File file) {
    final e = _entries[name];
    if (e == null) return;
    final now = DateTime.now();
    _entries[name] = (size: e.size, used: now);
    unawaited(file.setLastModified(now).catchError((Object _) {}));
  }

  void _record(String name, int size) {
    _entries[name] = (size: size, used: DateTime.now());
    notifyListeners();
  }

  /// 写入半截文件时更新它的大小，不通知界面（太频繁）。
  void _grow(String name, int size) {
    _entries[name] = (size: size, used: DateTime.now());
  }

  void _forget(String name) {
    if (_entries.remove(name) != null) notifyListeners();
  }

  Future<void> _delete(String name) async {
    try {
      final f = File('$_path/$name');
      if (await f.exists()) await f.delete();
    } catch (_) {}
    _forget(name);
  }

  /// `歌曲id_请求的音质_实际音质.扩展名`；半截文件不算。
  static ({String songId, AudioQuality requested, AudioQuality served})? _parse(String name) {
    if (name.endsWith('.part')) return null;
    final dot = name.indexOf('.');
    final parts = (dot < 0 ? name : name.substring(0, dot)).split('_');
    if (parts.length != 3) return null;
    final requested = AudioQuality.fromLevel(parts[1]);
    final served = AudioQuality.fromLevel(parts[2]);
    if (requested == null || served == null) return null;
    return (songId: parts[0], requested: requested, served: served);
  }

  static const _mime = {
    '.mp3': 'audio/mpeg',
    '.flac': 'audio/flac',
    '.m4a': 'audio/mp4',
    '.mp4': 'audio/mp4',
    '.aac': 'audio/aac',
    '.ogg': 'audio/ogg',
  };

  /// 从地址里取扩展名（iOS 播本地文件要靠它识别格式）。不认识的不加。
  static String _extension(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot);
    return _mime.containsKey(ext) ? ext : '';
  }
}
