import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// 从 FLAC 文件开头读出位深（bit）。
///
/// 网易云的接口不给位深，只能读文件头里的 STREAMINFO。
/// 只用 HTTP Range 取开头一小段，不下载整首歌。
class FlacProbe {
  FlacProbe({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 8);

  /// 先取的字节数。够覆盖常见的 ID3 标签；更长时再按偏移补取。
  static const _head = 64 * 1024;

  /// 读 [url] 的位深。不是 FLAC 或读不到时返回 null。
  Future<int?> bitDepth(String url) async {
    try {
      final head = await _range(url, 0, _head - 1);
      if (head == null) return null;
      final skip = id3Length(head);
      if (skip == null) return null;
      if (skip + _streamInfoEnd <= head.length) return bitDepthAt(head, skip);
      final tail = await _range(url, skip, skip + _streamInfoEnd - 1);
      return tail == null ? null : bitDepthAt(tail, 0);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _range(String url, int from, int to) async {
    final res = await _client
        .get(Uri.parse(url), headers: {'Range': 'bytes=$from-$to'})
        .timeout(_timeout);
    if (res.statusCode == 206) return res.bodyBytes;
    // 服务端不支持 Range 时会给整个文件；只在确实从 0 开始时用。
    if (res.statusCode == 200 && from == 0) return res.bodyBytes;
    return null;
  }

  /// "fLaC" + 块头 4 字节 + STREAMINFO 前 14 字节。
  static const _streamInfoEnd = 4 + 4 + 14;

  /// 开头 ID3v2 标签的总长度；没有标签时为 0，数据不够判断时为 null。
  static int? id3Length(Uint8List b) {
    if (b.length < 10) return null;
    if (b[0] != 0x49 || b[1] != 0x44 || b[2] != 0x33) return 0; // "ID3"
    final size = (b[6] & 0x7f) << 21 | (b[7] & 0x7f) << 14 | (b[8] & 0x7f) << 7 | (b[9] & 0x7f);
    final footer = b[5] & 0x10 != 0 ? 10 : 0;
    return 10 + size + footer;
  }

  /// 从 [offset] 处的 "fLaC" 开始解析 STREAMINFO，返回位深。格式不对时返回 null。
  static int? bitDepthAt(Uint8List b, int offset) {
    if (b.length < offset + _streamInfoEnd) return null;
    const magic = [0x66, 0x4c, 0x61, 0x43]; // "fLaC"
    for (var i = 0; i < 4; i++) {
      if (b[offset + i] != magic[i]) return null;
    }
    // 第一个元数据块必须是 STREAMINFO（类型 0）。
    if (b[offset + 4] & 0x7f != 0) return null;
    final info = offset + 8;
    // 第 12、13 字节：…| 声道数-1 (3 bit) | 位深-1 (5 bit) |…
    final bits = ((b[info + 12] & 0x01) << 4 | b[info + 13] >> 4) + 1;
    return bits >= 4 ? bits : null;
  }
}
