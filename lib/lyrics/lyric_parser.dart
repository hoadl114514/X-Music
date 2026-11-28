import 'dart:convert';
import 'dart:math';

import '../data/models.dart';

/// 歌词解析：LRC（逐行）、网易云 YRC（逐字，时间标记在字前）、QQ QRC（逐字，时间标记在字后）。
///
/// 所有时间都是整首歌的绝对时间（毫秒），逐字时间不叠加行首时间。
/// `[offset:N]` 按 LRC 惯例处理：正值表示歌词提前，所以从时间里减去 N。
abstract final class LyricParser {
  /// 翻译 / 罗马音挂到原文行上时，允许的最大时间差。
  static const matchTolerance = Duration(milliseconds: 1500);

  /// 组装一首歌的歌词。[main] 可以是 YRC、QRC 或 LRC；[translation]、[romaji] 同理，只取每行文本。
  /// 解析不出任何非空行时返回 [Lyrics.empty]。
  static Lyrics build({
    required String main,
    String translation = '',
    String romaji = '',
    required LyricSource source,
    Duration? duration,
  }) {
    final words = parseYrc(main);
    final timed = words.isNotEmpty ? words : parseQrc(main);
    final wordSynced = timed.any((l) => l.words != null);
    final lines = timed.isNotEmpty ? timed : parseLrc(main);
    if (lines.every((l) => l.text.trim().isEmpty)) return Lyrics.empty;

    final built = _finish(lines, duration);
    final withTrans = _attach(
      built,
      _anyTextLines(translation),
      (l, t) => l.copyWith(translation: t),
    );
    final withRoma = _attach(withTrans, _anyTextLines(romaji), (l, t) => l.copyWith(romaji: t));
    return Lyrics(lines: withRoma, source: source, wordSynced: wordSynced);
  }

  // ---------------------------------------------------------------- 各格式

  static final _lrcStamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final _offsetTag = RegExp(
    r'^\[offset:\s*([+-]?\d+)\s*\]',
    multiLine: true,
    caseSensitive: false,
  );
  static final _lineHeader = RegExp(r'^\[(\d+),(\d+)\](.*)$');
  static final _yrcWord = RegExp(r'\((\d+),(\d+),-?\d+\)');
  static final _qrcWord = RegExp(r'(.*?)\((\d+),(\d+)\)');

  static int _offset(String text) => int.tryParse(_offsetTag.firstMatch(text)?.group(1) ?? '') ?? 0;

  /// LRC。一行多个时间戳会展开成多行；网易云的 JSON 署名行（作词、作曲）也当成普通行。
  static List<RawLine> parseLrc(String text) {
    final offset = _offset(text);
    final out = <RawLine>[];
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (_jsonLine(line) case final j?) {
        out.add(j);
        continue;
      }
      final stamps = _lrcStamp.allMatches(line).toList();
      if (stamps.isEmpty || stamps.first.start != 0) continue;
      final body = line.substring(stamps.last.end).trim();
      for (final m in stamps) {
        final frac = (m.group(3) ?? '0').padRight(3, '0').substring(0, 3);
        final ms = (int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!)) * 1000 + int.parse(frac);
        out.add(RawLine(max(0, ms - offset), null, body));
      }
    }
    out.sort((a, b) => a.start - b.start);
    return out;
  }

  /// 网易云 YRC：`[行首,行长](字首,字长,0)字(字首,字长,0)字`。
  static List<RawLine> parseYrc(String text) {
    final out = <RawLine>[];
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (_jsonLine(line) case final j?) {
        out.add(j);
        continue;
      }
      final header = _lineHeader.firstMatch(line);
      if (header == null) continue;
      final body = header.group(3)!;
      final marks = _yrcWord.allMatches(body).toList();
      if (marks.isEmpty || marks.first.start != 0) continue;
      final words = <RawWord>[];
      for (var i = 0; i < marks.length; i++) {
        final m = marks[i];
        final end = i + 1 < marks.length ? marks[i + 1].start : body.length;
        final start = int.parse(m.group(1)!);
        words.add(RawWord(start, start + int.parse(m.group(2)!), body.substring(m.end, end)));
      }
      final lineStart = int.parse(header.group(1)!);
      out.add(_wordLine(lineStart, lineStart + int.parse(header.group(2)!), words));
    }
    // 只有署名行、没有任何逐字行时不算 YRC。
    if (!out.any((l) => l.words != null)) return const [];
    out.sort((a, b) => a.start - b.start);
    return out;
  }

  /// QQ QRC：`[行首,行长]字(字首,字长)字(字首,字长)`。整行必须被时间标记完整覆盖，否则丢弃该行。
  static List<RawLine> parseQrc(String text) {
    final offset = _offset(text);
    final out = <RawLine>[];
    for (final raw in const LineSplitter().convert(text)) {
      final header = _lineHeader.firstMatch(raw.trim());
      if (header == null) continue;
      final body = header.group(3)!;
      final marks = _qrcWord.allMatches(body).toList();
      if (marks.isEmpty || marks.last.end != body.length) continue;
      final words = <RawWord>[];
      int? prev;
      var valid = true;
      for (final m in marks) {
        final start = int.parse(m.group(2)!) - offset;
        final dur = int.parse(m.group(3)!);
        if ((prev != null && start < prev) || m.group(1)!.isEmpty) {
          valid = false;
          break;
        }
        prev = start;
        if (start + dur < 0) continue;
        words.add(RawWord(max(0, start), max(0, start + dur), m.group(1)!));
      }
      if (!valid || words.isEmpty) continue;
      // 和 Lyricify 一致：QRC 的行时间由字时间推出，不信任行头。
      out.add(_wordLine(words.first.start, words.map((w) => w.end).reduce(max), words));
    }
    out.sort((a, b) => a.start - b.start);
    return out;
  }

  /// 网易云歌词里的 `{"t":0,"c":[{"tx":"作词: "},{"tx":"某某"}]}`。
  static RawLine? _jsonLine(String line) {
    if (!line.startsWith('{')) return null;
    try {
      final v = jsonDecode(line);
      if (v is! Map || v['t'] is! num || v['c'] is! List) return null;
      final text = [
        for (final c in v['c'] as List)
          if (c is Map) '${c['tx'] ?? ''}',
      ].join();
      return RawLine((v['t'] as num).toInt(), null, text.trim());
    } on FormatException {
      return null;
    }
  }

  static RawLine _wordLine(int start, int end, List<RawWord> words) {
    final lineEnd = max(end, words.isEmpty ? end : words.map((w) => w.end).reduce(max));
    return RawLine(start, lineEnd, words.map((w) => w.text).join(), words);
  }

  /// 翻译、罗马音只需要每行文本，格式不限。
  static List<RawLine> _anyTextLines(String text) {
    if (text.trim().isEmpty) return const [];
    final lrc = parseLrc(text).where((l) => l.text.isNotEmpty).toList();
    if (lrc.isNotEmpty) return lrc;
    final yrc = parseYrc(text);
    return yrc.isNotEmpty ? yrc : parseQrc(text);
  }

  // ---------------------------------------------------------------- 组装

  static List<LyricLine> _finish(List<RawLine> lines, Duration? duration) {
    final songEnd = duration?.inMilliseconds;
    final out = <LyricLine>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.text.trim().isEmpty) continue; // 空行只用来给上一行定结束时间。
      if (songEnd != null && songEnd > 0 && l.start >= songEnd) continue;
      final next = i + 1 < lines.length ? lines[i + 1].start : null;
      var end = l.end ?? next ?? (songEnd != null && songEnd > l.start ? songEnd : l.start + 10000);
      end = max(end, l.start + 1);
      final words = l.words == null
          ? [LyricWord(l.text, _ms(l.start), _ms(end))]
          : [
              for (final w in l.words!)
                if (w.text.isNotEmpty) LyricWord(w.text, _ms(w.start), _ms(max(w.end, w.start))),
            ];
      out.add(LyricLine(start: _ms(l.start), end: _ms(end), words: words));
    }
    return out;
  }

  /// 把带时间的文本（如另一个来源的罗马音）挂到时间最近的行上，规则同翻译。
  static List<LyricLine> attachByTime(
    List<LyricLine> lines,
    List<(Duration, String)> extra,
    LyricLine Function(LyricLine line, String text) apply,
  ) => _attach(lines, [for (final (at, t) in extra) RawLine(at.inMilliseconds, null, t)], apply);

  /// 每条附加行最多用一次，挂到时间最近的原文行上。
  static List<LyricLine> _attach(
    List<LyricLine> lines,
    List<RawLine> extra,
    LyricLine Function(LyricLine line, String text) apply,
  ) {
    if (extra.isEmpty) return lines;
    final used = List.filled(extra.length, false);
    return [
      for (final line in lines)
        () {
          final at = line.start.inMilliseconds;
          var best = -1;
          for (var j = 0; j < extra.length; j++) {
            if (used[j]) continue;
            if (best < 0 || (extra[j].start - at).abs() < (extra[best].start - at).abs()) best = j;
          }
          if (best < 0 || (extra[best].start - at).abs() > matchTolerance.inMilliseconds) {
            return line;
          }
          used[best] = true;
          final t = extra[best].text.trim();
          // 网易云用 "//" 表示这一行没有翻译。
          return t.isEmpty || t == '//' ? line : apply(line, t);
        }(),
    ];
  }

  static Duration _ms(int v) => Duration(milliseconds: v);
}

/// 解析中间结果，时间单位毫秒。逐行歌词 [end] 和 [words] 为 null。
class RawLine {
  const RawLine(this.start, this.end, this.text, [this.words]);

  final int start;
  final int? end;
  final String text;
  final List<RawWord>? words;
}

class RawWord {
  const RawWord(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;
}
