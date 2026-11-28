// AMLL（Apple Music-like Lyrics）社区歌词库：https://beta.amllhub.bikonoo.com/
//
// 接口来自该站前端代码，没有公开文档，属于 beta 站，可能变动：
//   GET {api}/api/v1/lyrics/ncm-lyrics/{网易云歌曲 id}
//   200：TTML 文本（Content-Type 为 text/plain，不带 charset，按 UTF-8 解码）
//   404：库里没有这首歌
// 不需要登录。按网易云 id 精确对应，不做搜索匹配。

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/models.dart';
import 'ttml_parser.dart';

class AmllLyrics {
  AmllLyrics({http.Client? client, this.baseUrl = defaultBaseUrl})
    : _client = client ?? http.Client();

  static const defaultBaseUrl = 'https://api.beta.amllhub.bikonoo.com';
  static const _timeout = Duration(seconds: 10);

  final http.Client _client;
  final String baseUrl;

  void close() => _client.close();

  /// 有歌词时返回解析结果；库里没有这首歌时返回 [Lyrics.empty]；网络或服务出错时抛异常。
  Future<Lyrics> fetch(Song song) async {
    // 只认网易云的数字 id。
    if (!RegExp(r'^\d+$').hasMatch(song.id)) return Lyrics.empty;
    final res = await _client
        .get(Uri.parse('$baseUrl/api/v1/lyrics/ncm-lyrics/${song.id}'))
        .timeout(_timeout);
    if (res.statusCode == 404) return Lyrics.empty;
    if (res.statusCode != 200) {
      throw http.ClientException('AMLL 歌词获取失败：HTTP ${res.statusCode}', res.request?.url);
    }
    return TtmlParser.parse(
      utf8.decode(res.bodyBytes, allowMalformed: true),
      source: LyricSource.amll,
      duration: song.duration,
    );
  }
}
