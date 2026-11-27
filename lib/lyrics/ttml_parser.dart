import 'dart:math';

import '../data/models.dart';

/// TTML 歌词解析，按 AMLL（Apple Music-like Lyrics）社区歌词库的写法。
///
/// - `<p>` 是一行，里面带 `begin`/`end` 的 `<span>` 是一个字（词、音节）。
/// - span 之间的空格文本是词间空格，挂到前一个字后面。
/// - `ttm:role="x-translation"` / `"x-roman"` 的 span 是这一行的翻译 / 罗马音。
/// - Apple Music 写法的翻译放在 `<head>` 的 `<translations>` 里，按 `itunes:key` 对应到行。
/// - `ttm:role="x-bg"` 是背景人声。当前歌词模型不支持多声部，先丢弃。
/// - `<p>` 里没有计时 span 时按逐行歌词处理。
///
/// 时间支持 `ss.fff`、`m:ss.fff`、`h:mm:ss.fff`，以及带 `s` / `ms` 后缀的写法。
abstract final class TtmlParser {
  /// 解析不出任何非空行时返回 [Lyrics.empty]。格式错误不抛异常，能解析多少算多少。
  static Lyrics parse(String text, {required LyricSource source, Duration? duration}) {
    final root = _XmlReader(text).read();
    final tt = root.find('tt') ?? root;
    final body = tt.find('body');
    if (body == null) return Lyrics.empty;

    final headTrans = <String, String>{};
    final headRoma = <String, String>{};
    if (tt.find('head') case final head?) {
      _collectHeadTexts(head, 'translation', headTrans);
      _collectHeadTexts(head, 'transliteration', headRoma);
    }

    final raws = <_Line>[];
    for (final p in body.findAll('p')) {
      final line = _readLine(p);
      if (line == null) continue;
      final key = p.attr('key');
      raws.add(
        _Line(
          line.start,
          line.end,
          line.words,
          line.timedWords,
          line.translation ?? (key == null ? null : headTrans[key]),
          line.romaji ?? (key == null ? null : headRoma[key]),
        ),
      );
    }
    raws.sort((a, b) => a.start - b.start);

    final songEnd = duration?.inMilliseconds;
    final lines = <LyricLine>[];
    for (var i = 0; i < raws.length; i++) {
      final l = raws[i];
      if (songEnd != null && songEnd > 0 && l.start >= songEnd) continue;
      final next = i + 1 < raws.length ? raws[i + 1].start : null;
      final end = max(
        l.end ?? next ?? (songEnd != null && songEnd > l.start ? songEnd : l.start + 10000),
        l.start + 1,
      );
      final words = l.timedWords
          ? l.words
          : [_Word(l.start, end, l.words.map((w) => w.text).join())];
      lines.add(
        LyricLine(
          start: _ms(l.start),
          end: _ms(end),
          words: [
            for (final w in words)
              if (w.text.isNotEmpty) LyricWord(w.text, _ms(w.start), _ms(max(w.end, w.start))),
          ],
          translation: l.translation,
          romaji: l.romaji,
        ),
      );
    }
    if (lines.isEmpty) return Lyrics.empty;
    return Lyrics(lines: lines, source: source, wordSynced: raws.any((l) => l.timedWords));
  }

  static _Line? _readLine(_XmlElement p) {
    final words = <_Word>[];
    final plain = StringBuffer();
    String? translation;
    String? romaji;
    var timed = false;

    void addText(String raw) {
      final t = _normalizeSpace(raw);
      if (t.isEmpty) return;
      if (words.isNotEmpty) {
        words.last = words.last.append(t);
      } else {
        plain.write(t);
      }
    }

    for (final child in p.children) {
      if (child is String) {
        addText(child);
        continue;
      }
      final span = child as _XmlElement;
      if (span.name != 'span') {
        addText(span.text);
        continue;
      }
      switch (span.attr('role')) {
        case 'x-translation':
          translation ??= _nonEmpty(span.text);
        case 'x-roman':
          romaji ??= _nonEmpty(span.text);
        case 'x-bg':
          break;
        default:
          final begin = parseTime(span.attr('begin'));
          final end = parseTime(span.attr('end'));
          final text = _normalizeSpace(span.text);
          if (begin == null || end == null) {
            addText(text);
          } else if (text.isNotEmpty) {
            timed = true;
            // 计时 span 之前的未计时文本并进第一个字。
            final prefix = plain.toString();
            plain.clear();
            words.add(_Word(begin, end, '$prefix$text'));
          }
      }
    }

    final pBegin = parseTime(p.attr('begin'));
    final pEnd = parseTime(p.attr('end'));
    if (!timed) {
      final text = plain.toString().trim();
      if (text.isEmpty || pBegin == null) return null;
      return _Line(pBegin, pEnd, [_Word(pBegin, pEnd ?? pBegin, text)], false, translation, romaji);
    }
    // 行首、行尾的空格去掉；字之间的空格保留。
    words.first = words.first.trimLeft();
    words.last = words.last.trimRight();
    final start = pBegin ?? words.map((w) => w.start).reduce(min);
    final end = max(pEnd ?? 0, words.map((w) => w.end).reduce(max));
    return _Line(start, end, words, true, translation, romaji);
  }

  /// `<translation><text for="L1">…</text></translation>`，取第一种语言。
  static void _collectHeadTexts(_XmlElement head, String tag, Map<String, String> out) {
    final first = head.findAll(tag).firstOrNull;
    if (first == null) return;
    for (final t in first.findAll('text')) {
      final key = t.attr('for');
      final text = _nonEmpty(_normalizeSpace(t.text));
      if (key != null && text != null) out.putIfAbsent(key, () => text);
    }
  }

  /// 毫秒。无法解析时返回 null。
  static int? parseTime(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;
    var scale = 1000.0;
    if (s.endsWith('ms')) {
      s = s.substring(0, s.length - 2);
      scale = 1;
    } else if (s.endsWith('s')) {
      s = s.substring(0, s.length - 1);
    }
    final parts = s.split(':');
    if (parts.length > 3) return null;
    var total = 0.0;
    for (var i = 0; i < parts.length; i++) {
      final v = double.tryParse(parts[i]);
      if (v == null || v < 0) return null;
      total = total * 60 + v;
    }
    if (parts.length > 1 && scale != 1000) return null;
    return (total * scale).round();
  }

  /// 空白折叠成一个空格。带换行的纯空白是排版缩进，不是词间空格，直接丢掉。
  static String _normalizeSpace(String s) {
    if (s.trim().isEmpty && s.contains('\n')) return '';
    return s.replaceAll(RegExp(r'\s+'), ' ');
  }

  static String? _nonEmpty(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  static Duration _ms(int v) => Duration(milliseconds: v);
}

class _Word {
  const _Word(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;

  _Word append(String t) => _Word(start, end, '$text$t');
  _Word trimLeft() => _Word(start, end, text.trimLeft());
  _Word trimRight() => _Word(start, end, text.trimRight());
}

class _Line {
  const _Line(this.start, this.end, this.words, this.timedWords, this.translation, this.romaji);

  final int start;
  final int? end;
  final List<_Word> words;
  final bool timedWords;
  final String? translation;
  final String? romaji;
}

// ------------------------------------------------------------------ 极简 XML 读取

/// 只用来读 TTML 歌词：元素、属性、文本、实体。忽略注释、处理指令、DOCTYPE，CDATA 当文本。
/// 元素名去掉命名空间前缀；属性名保留原样，用 [_XmlElement.attr] 按本地名查。
class _XmlElement {
  _XmlElement(this.name, this.attrs);

  final String name;
  final Map<String, String> attrs;

  /// [String] 或 [_XmlElement]。
  final children = <Object>[];

  String? attr(String local) {
    if (attrs[local] case final v?) return v;
    for (final e in attrs.entries) {
      if (e.key.endsWith(':$local')) return e.value;
    }
    return null;
  }

  String get text {
    final b = StringBuffer();
    void walk(_XmlElement e) {
      for (final c in e.children) {
        if (c is String) {
          b.write(c);
        } else {
          walk(c as _XmlElement);
        }
      }
    }

    walk(this);
    return b.toString();
  }

  _XmlElement? find(String name) => findAll(name).firstOrNull;

  /// 深度优先找所有同名后代，找到后不再进入它的子树。
  Iterable<_XmlElement> findAll(String name) sync* {
    for (final c in children) {
      if (c is! _XmlElement) continue;
      if (c.name == name) {
        yield c;
      } else {
        yield* c.findAll(name);
      }
    }
  }
}

class _XmlReader {
  _XmlReader(this.s);

  final String s;
  var _i = 0;

  static final _attr = RegExp(r'''([^\s=/>]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''');

  _XmlElement read() {
    final root = _XmlElement('#document', const {});
    final stack = [root];
    while (_i < s.length) {
      final lt = s.indexOf('<', _i);
      if (lt < 0) {
        stack.last.children.add(_decode(s.substring(_i)));
        break;
      }
      if (lt > _i) stack.last.children.add(_decode(s.substring(_i, lt)));
      _i = lt;
      if (s.startsWith('<!--', _i)) {
        _skipPast('-->');
      } else if (s.startsWith('<![CDATA[', _i)) {
        final end = s.indexOf(']]>', _i);
        final stop = end < 0 ? s.length : end;
        stack.last.children.add(s.substring(_i + 9, stop));
        _i = end < 0 ? s.length : end + 3;
      } else if (s.startsWith('<?', _i)) {
        _skipPast('?>');
      } else if (s.startsWith('<!', _i)) {
        _skipPast('>');
      } else if (s.startsWith('</', _i)) {
        final gt = s.indexOf('>', _i);
        final name = _local(s.substring(_i + 2, gt < 0 ? s.length : gt).trim());
        _i = gt < 0 ? s.length : gt + 1;
        // 容错：关到最近的同名元素；找不到就忽略这个结束标签。
        final at = stack.lastIndexWhere((e) => e.name == name);
        if (at > 0) stack.removeRange(at, stack.length);
      } else {
        final gt = _tagEnd(_i);
        if (gt < 0) break; // 标签没写完，后面不要了。
        final inner = s.substring(_i + 1, gt);
        _i = gt + 1;
        final selfClosing = inner.endsWith('/');
        final body = selfClosing ? inner.substring(0, inner.length - 1) : inner;
        final nameEnd = body.indexOf(RegExp(r'\s'));
        final name = _local(nameEnd < 0 ? body : body.substring(0, nameEnd));
        final attrs = <String, String>{
          if (nameEnd >= 0)
            for (final m in _attr.allMatches(body.substring(nameEnd)))
              m.group(1)!: _decode(m.group(2) ?? m.group(3) ?? ''),
        };
        final el = _XmlElement(name, attrs);
        stack.last.children.add(el);
        if (!selfClosing) stack.add(el);
      }
    }
    return root;
  }

  /// 标签结束的 `>`，跳过引号里的 `>`。没有时返回 -1。
  int _tagEnd(int from) {
    String? quote;
    for (var j = from + 1; j < s.length; j++) {
      final c = s[j];
      if (quote != null) {
        if (c == quote) quote = null;
      } else if (c == '"' || c == "'") {
        quote = c;
      } else if (c == '>') {
        return j;
      }
    }
    return -1;
  }

  void _skipPast(String end) {
    final at = s.indexOf(end, _i);
    _i = at < 0 ? s.length : at + end.length;
  }

  static String _local(String name) {
    final colon = name.indexOf(':');
    return colon < 0 ? name : name.substring(colon + 1);
  }

  static final _entity = RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);');

  static String _decode(String t) {
    if (!t.contains('&')) return t;
    return t.replaceAllMapped(_entity, (m) {
      final e = m.group(1)!;
      switch (e) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
      }
      final code = e.startsWith('#x')
          ? int.tryParse(e.substring(2), radix: 16)
          : int.tryParse(e.substring(1));
      if (code == null || code > 0x10FFFF) return m.group(0)!;
      return String.fromCharCode(code);
    });
  }
}
