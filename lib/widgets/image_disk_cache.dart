import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../app/platform.dart';

/// 图片的磁盘缓存：按地址的 MD5 存在系统临时目录的 `image_cache/` 下。
///
/// 内存里的图片缓存装不了多少张大封面，切页面回来常常要重新下载；有了这一层，
/// 下载过的图直接从磁盘读，不用等网络。系统清理临时目录时会一起清掉，启动时也会按
/// 最近使用时间删到 [maxBytes] 以内。取不到目录（网页版、测试）时什么都不做。
abstract final class ImageDiskCache {
  static const maxBytes = 300 * 1024 * 1024;

  static Future<Directory?>? _dir;

  /// 测试里指定目录，或传 null 关掉。
  @visibleForTesting
  static set directory(Directory? dir) => _dir = Future.value(dir);

  @visibleForTesting
  static void resetDirectory() {
    _dir = null;
    memory = null;
  }

  /// 测试里用内存代替磁盘（widget 测试的假时钟里文件读写不会完成）。
  @visibleForTesting
  static Map<String, Uint8List>? memory;

  static Future<Directory?> _directory() => _dir ??= () async {
    if (kIsWeb) return null;
    try {
      // 电脑上的临时目录是所有程序共用的（Windows 的 %TEMP%），放到应用自己的缓存目录。
      final base = isNativeDesktop
          ? await getApplicationCacheDirectory()
          : await getTemporaryDirectory();
      return await Directory('${base.path}/image_cache').create(recursive: true);
    } catch (_) {
      return null;
    }
  }();

  static Future<File?> _file(String url) async {
    final dir = await _directory();
    if (dir == null) return null;
    final name = crypto.md5.convert(utf8.encode(url)).toString();
    return File('${dir.path}/$name');
  }

  /// 缓存里有就返回图片字节，并把它标成最近用过。
  static Future<Uint8List?> read(String url) async {
    if (memory case final m?) return m[url];
    try {
      final f = await _file(url);
      if (f == null || !await f.exists()) return null;
      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) return null;
      unawaited(f.setLastModified(DateTime.now()).catchError((Object _) {}));
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String url, Uint8List bytes) async {
    if (memory case final m?) {
      m[url] = bytes;
      return;
    }
    try {
      final f = await _file(url);
      if (f == null) return;
      // 先写临时文件再改名，写到一半被杀也不会留下坏图。
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(f.path);
    } catch (_) {
      // 写不进去就算了，下次重新下载。
    }
  }

  /// 删掉坏掉（解码失败）的缓存。
  static Future<void> remove(String url) async {
    if (memory case final m?) {
      m.remove(url);
      return;
    }
    try {
      final f = await _file(url);
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// 超过 [limit] 时从最久没用的开始删。
  static Future<void> prune({int limit = maxBytes}) async {
    try {
      final dir = await _directory();
      if (dir == null) return;
      final files = <(File, FileStat)>[];
      await for (final e in dir.list()) {
        if (e is File) files.add((e, await e.stat()));
      }
      var total = files.fold<int>(0, (sum, f) => sum + f.$2.size);
      if (total <= limit) return;
      files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      for (final (file, stat) in files) {
        if (total <= limit) break;
        await file.delete();
        total -= stat.size;
      }
    } catch (_) {}
  }
}
