import '../api/netease_api.dart';
import '../data/models.dart';
import 'amll_lyrics.dart';
import 'lyric_parser.dart';
import 'qq_lyrics.dart';

/// 按来源取歌词，结果按 (歌曲, 来源) 缓存。
class LyricService {
  LyricService({required this._netease, required this._qq, required this._amll});

  final NeteaseApi _netease;
  final QqLyrics _qq;
  final AmllLyrics _amll;
  final _cache = <(String, LyricSource), Lyrics>{};

  /// 自动换来源时的顺序。AMLL 按网易云 id 精确对应，排在要搜索匹配的 QQ 前面。
  static const fallbackOrder = [LyricSource.netease, LyricSource.amll, LyricSource.qq];

  /// 取 [preferred] 的歌词；没有时按 [fallbackOrder] 换其他来源。都没有返回 [Lyrics.empty]。
  /// [fallback] 为 false 时只查 [preferred]。
  Future<Lyrics> fetch(Song song, LyricSource preferred, {bool fallback = true}) async {
    final order = [preferred, if (fallback) ...fallbackOrder.where((s) => s != preferred)];
    Object? lastError;
    for (final source in order) {
      try {
        final lyrics = await _fetchFrom(song, source);
        if (!lyrics.isEmpty) return lyrics;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null && !fallback) throw lastError;
    return Lyrics.empty;
  }

  Future<Lyrics> _fetchFrom(Song song, LyricSource source) async {
    final key = (song.id, source);
    if (_cache[key] case final cached?) return cached;
    final lyrics = switch (source) {
      LyricSource.netease => await _fromNetease(song),
      LyricSource.qq => await _qq.fetch(song),
      LyricSource.amll => await _amll.fetch(song),
    };
    _cache[key] = lyrics;
    return lyrics;
  }

  Future<Lyrics> _fromNetease(Song song) async {
    final t = await _netease.lyricTexts(song.id);
    String pick(String a, String b) => t[a]!.isNotEmpty ? t[a]! : t[b]!;
    // 有逐字歌词时优先，翻译 / 罗马音优先用和逐字歌词对齐的版本。
    final yrc = LyricParser.build(
      main: t['yrc']!,
      translation: pick('ytlrc', 'tlyric'),
      romaji: pick('yromalrc', 'romalrc'),
      source: LyricSource.netease,
      duration: song.duration,
    );
    if (yrc.wordSynced) return yrc;
    return LyricParser.build(
      main: t['lrc']!,
      translation: t['tlyric']!,
      romaji: t['romalrc']!,
      source: LyricSource.netease,
      duration: song.duration,
    );
  }
}
