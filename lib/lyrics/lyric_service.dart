import 'dart:async';

import '../api/netease_api.dart';
import '../data/models.dart';
import '../data/track_cache.dart';
import 'amll_lyrics.dart';
import 'lyric_parser.dart';
import 'qq_lyrics.dart';

/// 按来源取歌词，结果按 (歌曲, 来源) 缓存。
class LyricService {
  LyricService({required this._netease, required this._qq, required this._amll, this._store});

  final NeteaseApi _netease;
  final QqLyrics _qq;
  final AmllLyrics _amll;

  /// 本地缓存（算在听歌缓存里）。有歌词的结果存下来，下次不用联网。为 null 时只存内存。
  final DataCache? _store;

  /// 缓存格式版本。解析逻辑大改时加一，旧缓存自动作废。
  static const _version = 2;
  final _cache = <(String, LyricSource), Lyrics>{};
  final _inFlight = <(String, LyricSource), Future<Lyrics>>{};

  /// 没给顺序时自动换来源的顺序。AMLL 按网易云 id 精确对应，排在要搜索匹配的 QQ 前面。
  static const fallbackOrder = [LyricSource.netease, LyricSource.amll, LyricSource.qq];

  /// 取 [preferred] 的歌词；没有时按 [order]（不给时用 [fallbackOrder]）换其他来源，
  /// 只试 [order] 里有的来源。都没有返回 [Lyrics.empty]。[fallback] 为 false 时只查 [preferred]。
  ///
  /// 各来源同时请求，再按顺序取第一个有歌词的。这样前面的来源慢或超时，
  /// 后面的来源不用排队等，总耗时最多是最慢的那一个。
  Future<Lyrics> fetch(
    Song song,
    LyricSource preferred, {
    bool fallback = true,
    List<LyricSource>? order,
  }) async {
    final rest = order ?? fallbackOrder;
    final tries = [preferred, if (fallback) ...rest.where((s) => s != preferred)];
    final pending = [for (final s in tries) _fetchFrom(song, s)];
    // 先挂上错误处理，排在后面的来源先失败时不会变成未处理的异常。
    for (final f in pending) {
      f.ignore();
    }
    Object? lastError;
    for (final f in pending) {
      try {
        final lyrics = await f;
        if (!lyrics.isEmpty) return lyrics;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null && !fallback) throw lastError;
    return Lyrics.empty;
  }

  /// 同一首歌同一来源只发一次请求：请求中的共用同一个 Future，成功后缓存，失败后下次重试。
  Future<Lyrics> _fetchFrom(Song song, LyricSource source) {
    final key = (song.id, source);
    if (_cache[key] case final cached?) return Future.value(cached);
    return _inFlight[key] ??= _load(song, source).then(
      (lyrics) {
        _cache[key] = lyrics;
        _inFlight.remove(key);
        return lyrics;
      },
      onError: (Object e, StackTrace s) {
        _inFlight.remove(key);
        Error.throwWithStackTrace(e, s);
      },
    );
  }

  Future<Lyrics> _load(Song song, LyricSource source) async {
    final key = 'ly_${song.id}_${source.name}';
    final cached = await _store?.read(key, (j) {
      if (j is! Map || j['v'] != _version) return null;
      return Lyrics.fromJson(j['l']);
    });
    if (cached != null) return cached;
    var complete = true;
    final lyrics = switch (source) {
      LyricSource.netease => await _fromNetease(song),
      LyricSource.qq => await _qq.fetch(song),
      LyricSource.amll => await () async {
        final (l, done) = await _withNeteaseRomaji(song, await _amll.fetch(song));
        complete = done;
        return l;
      }(),
    };
    // 没歌词的不存：之后可能会有。罗马音没等到的也不存，下次再补。
    if (!lyrics.isEmpty && complete) {
      unawaited(_store?.write(key, {'v': _version, 'l': lyrics.toJson()}));
    }
    return lyrics;
  }

  /// 等网易云罗马音的最长时间。超时就先不带罗马音，不让 AMLL 歌词干等。
  static const romajiWait = Duration(seconds: 4);

  /// AMLL 歌词自己没有罗马音时，从网易云拉取罗马音，按时间挂到最近的行上。
  /// 不在本地生成罗马音。网易云取不到时保持原样。
  /// 返回的 bool 表示网易云有没有及时答复（没答复时结果不完整，不写缓存）。
  Future<(Lyrics, bool)> _withNeteaseRomaji(Song song, Lyrics lyrics) async {
    if (lyrics.isEmpty || lyrics.hasRomaji) return (lyrics, true);
    final Lyrics netease;
    try {
      netease = await _fetchFrom(song, LyricSource.netease).timeout(romajiWait);
    } catch (_) {
      return (lyrics, false);
    }
    final romaji = [
      for (final l in netease.lines)
        if (l.romaji case final r?) (l.start, r),
    ];
    if (romaji.isEmpty) return (lyrics, true);
    final merged = Lyrics(
      lines: LyricParser.attachByTime(lyrics.lines, romaji, (l, r) => l.copyWith(romaji: r)),
      source: lyrics.source,
      wordSynced: lyrics.wordSynced,
    );
    return (merged, true);
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
