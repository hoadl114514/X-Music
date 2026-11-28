import 'dart:math';

import '../data/models.dart';

/// TTML 歌词解析，对齐 AMLL（Apple Music-like Lyrics）的 TTML 规范和官方解析器
/// （amll-dev/applemusic-like-lyrics 的 packages/ttml）。
///
/// 支持：
/// - 逐字（`itunes:timing="Word"`）和逐行（`"Line"`，或没有计时 span）。
/// - 词间空格：span 之间的空格文本，以及 span 首尾的空格。排版用的换行缩进忽略。
/// - 行内翻译 / 音译（`ttm:role="x-translation"` / `"x-roman"`），以及 `<head>` 里
///   Apple Music 式的 `<translations>` / `<transliterations>`（按 `itunes:key` 对应）。
///   多种语言时优先中文。
/// - 背景人声（`ttm:role="x-bg"`），带自己的逐字时间、翻译和音译；去掉首尾括号。
/// - 对唱（`ttm:agent`）：按 AMLL 的规则在左右两侧交替，合唱（group）不算对唱。
/// - Ruby 注音（`tts:ruby`）：基文本做字，注音文本挂在字上。
///
/// 不支持（解析时忽略）：`amll:obscene`、`amll:empty-beat`、`itunes:song-part`。
///
/// 时间支持 `ss.fff`、`m:ss.fff`、`h:mm:ss.fff`，以及带 `s` / `ms` 后缀的写法。
abstract final class TtmlParser {
  /// 解析不出任何非空行时返回 [Lyrics.empty]。格式错误不抛异常，能解析多少算多少。
  static Lyrics parse(String text, {required LyricSource source, Duration? duration}) {
    final root = _XmlReader(text).read();
    final tt = root.find('tt') ?? root;
    final body = tt.find('body');
    if (body == null) return Lyrics.empty;
    final lineTiming = tt.attr('timing') == 'Line';

    final head = tt.find('head');
    final agents = <String, String>{
      if (head != null)
        for (final a in head.findAll('agent')) ?a.attr('id'): a.attr('type') ?? 'person',
    };
    final headTrans = head == null ? const <String, List<_Sub>>{} : _sidecar(head, 'translation');
    final headRoma = head == null
        ? const <String, List<_Sub>>{}
        : _sidecar(head, 'transliteration');

    // 歌曲段落：`<div itunes:songPart>`（旧写法 `itunes:song-part`），里层的覆盖外层。
    final partOf = Map<_XmlElement, String>.identity();
    for (final div in body.findAll('div')) {
      final part = div.attr('songPart') ?? div.attr('song-part');
      if (part == null || part.isEmpty) continue;
      for (final p in div.findAll('p')) {
        partOf[p] = part;
      }
    }

    final raws = <_Line>[];
    // 对唱判定，和 AMLL 一致：合唱不参与；第一位歌手类型为 other 时放右侧；
    // 换了一位歌手就换一侧。
    String? lastAgent;
    var lastDuet = false;
    for (final p in body.findAll('p')) {
      final c = _Content.read(p);
      final key = p.attr('key');
      final main = c.toLine(
        begin: parseTime(p.attr('begin')),
        end: parseTime(p.attr('end')),
        lineTiming: lineTiming,
        translations: [...c.translations, ...?headTrans[key]?.map((s) => s.main)],
        romanizations: [...c.romanizations, ...?headRoma[key]?.map((s) => s.main)],
      );
      if (main == null) continue;

      final agent = p.attr('agent') ?? 'v1';
      var duet = false;
      if (agents[agent] != 'group') {
        if (lastAgent == null) {
          duet = agents[agent] == 'other';
        } else {
          duet = agent == lastAgent ? lastDuet : !lastDuet;
        }
        lastAgent = agent;
        lastDuet = duet;
      }

      _Line? bg;
      if (c.background case final b?) {
        bg = b.toLine(
          begin: b.begin,
          end: b.end,
          lineTiming: lineTiming,
          translations: [
            ...b.translations,
            ...c.bgTranslations,
            ...?headTrans[key]?.map((s) => s.bg),
          ],
          romanizations: [
            ...b.romanizations,
            ...c.bgRomanizations,
            ...?headRoma[key]?.map((s) => s.bg),
          ],
          stripParens: true,
        );
      }
      raws.add(main.withExtras(duet: duet, background: bg, songPart: partOf[p]));
    }
    raws.sort((a, b) => a.start - b.start);

    final songEnd = duration?.inMilliseconds;
    final lines = <LyricLine>[];
    for (var i = 0; i < raws.length; i++) {
      final l = raws[i];
      if (songEnd != null && songEnd > 0 && l.start >= songEnd) continue;
      final next = i + 1 < raws.length ? raws[i + 1].start : null;
      final fallbackEnd =
          next ?? (songEnd != null && songEnd > l.start ? songEnd : l.start + 10000);
      lines.add(l.build(fallbackEnd));
    }
    if (lines.isEmpty) return Lyrics.empty;
    return Lyrics(lines: lines, source: source, wordSynced: raws.any((l) => l.timedWords));
  }

  /// `<translation xml:lang><text for="L1">…</text></translation>`：行 key → 各语言的内容。
  static Map<String, List<_Sub>> _sidecar(_XmlElement head, String tag) {
    final out = <String, List<_Sub>>{};
    for (final group in head.findAll(tag)) {
      final lang = group.attr('lang');
      for (final t in group.findAll('text')) {
        final key = t.attr('for');
        if (key == null) continue;
        final c = _Content.read(t);
        out
            .putIfAbsent(key, () => [])
            .add(_Sub((lang, c.plainText), (lang, c.background?.plainText ?? '')));
      }
    }
    return out;
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

  /// 多种语言时优先简体中文，其次其他中文，最后取第一个。空文本跳过。
  static String? pickLanguage(List<(String?, String)> items) {
    final valid = [
      for (final (lang, text) in items)
        if (text.trim().isNotEmpty) (lang?.toLowerCase() ?? '', text.trim()),
    ];
    if (valid.isEmpty) return null;
    for (final test in <bool Function(String)>[
      (l) => l.startsWith('zh-hans') || l == 'zh-cn' || l.startsWith('zh-cn'),
      (l) => l.startsWith('zh'),
    ]) {
      for (final (lang, text) in valid) {
        if (test(lang)) return text;
      }
    }
    return valid.first.$2;
  }

  static final _space = RegExp(r'\s+');

  /// 空白折叠成一个空格。
  static String _collapse(String s) => s.replaceAll(_space, ' ');

  static Duration _ms(int v) => Duration(milliseconds: v);
}

/// 侧边（head）里一行的翻译或音译：主歌词部分和背景人声部分，各带语言。
class _Sub {
  const _Sub(this.main, this.bg);

  final (String?, String) main;
  final (String?, String) bg;
}

class _Word {
  _Word(this.start, this.end, this.text, {this.ruby, this.obscene = false, this.emptyBeat = 0});

  final int start;
  final int end;
  String text;
  final String? ruby;

  /// `amll:obscene="true"`：不雅用语。
  final bool obscene;

  /// `amll:empty-beat`：空拍数。
  final int emptyBeat;

  /// 换一段文字，其他信息不变。
  _Word copy({String? text, int? start, int? end}) => _Word(
    start ?? this.start,
    end ?? this.end,
    text ?? this.text,
    ruby: ruby,
    obscene: obscene,
    emptyBeat: emptyBeat,
  );

  static bool obsceneOf(_XmlElement el) => el.attr('obscene') == 'true';
  static int emptyBeatOf(_XmlElement el) => int.tryParse(el.attr('empty-beat') ?? '') ?? 0;
}

/// 一个 `<p>`（或背景人声 span、翻译 span、head 里的 `<text>`）里读出来的东西。
class _Content {
  _Content(this.begin, this.end);

  final int? begin;
  final int? end;
  final words = <_Word>[];

  /// 整行文本（含未计时的文字），逐行模式和翻译用。
  final full = StringBuffer();
  final translations = <(String?, String)>[];
  final romanizations = <(String?, String)>[];

  /// 主歌词的翻译 / 音译 span 里夹带的背景人声部分。
  final bgTranslations = <(String?, String)>[];
  final bgRomanizations = <(String?, String)>[];
  _Content? background;

  String get plainText => TtmlParser._collapse(full.toString()).trim();

  static _Content read(_XmlElement el) {
    final c = _Content(
      TtmlParser.parseTime(el.attr('begin')),
      TtmlParser.parseTime(el.attr('end')),
    );
    c._children(el);
    if (c.words.isNotEmpty) {
      c.words.first.text = c.words.first.text.trimLeft();
      c.words.last.text = c.words.last.text.trimRight();
    }
    return c;
  }

  void _children(_XmlElement el) {
    for (final child in el.children) {
      if (child is String) {
        _textNode(child);
      } else {
        _element(child as _XmlElement);
      }
    }
  }

  void _textNode(String raw) {
    // 带换行的纯空白是排版缩进，不是歌词内容。
    if (raw.contains('\n') && raw.trim().isEmpty) return;
    final t = TtmlParser._collapse(raw);
    full.write(t);
    if (t.trim().isEmpty) {
      _markSpace();
    } else if (words.isNotEmpty) {
      // 逐字行里夹着未计时的文字：并进前一个字，避免丢字。
      words.last.text += t;
    }
  }

  void _markSpace() {
    if (words.isNotEmpty && !words.last.text.endsWith(' ')) words.last.text += ' ';
  }

  void _element(_XmlElement el) {
    if (el.attr('ruby') == 'container') {
      _ruby(el);
      return;
    }
    switch (el.attr('role')) {
      case 'x-bg':
        background = read(el);
      case 'x-translation':
        final sub = read(el);
        translations.add((el.attr('lang'), sub.plainText));
        if (sub.background case final bg?) {
          bgTranslations.add((el.attr('lang'), bg.plainText));
        }
      case 'x-roman':
        final sub = read(el);
        romanizations.add((el.attr('lang'), sub.plainText));
        if (sub.background case final bg?) {
          bgRomanizations.add((el.attr('lang'), bg.plainText));
        }
      default:
        final begin = TtmlParser.parseTime(el.attr('begin'));
        final end = TtmlParser.parseTime(el.attr('end'));
        if (begin == null || end == null || el.name != 'span') {
          // 未计时的包装元素：内容照常读，里面可能还有计时 span。
          _children(el);
          return;
        }
        final raw = el.text;
        final formatting = raw.contains('\n');
        final t = TtmlParser._collapse(raw);
        full.write(formatting ? t.trim() : t);
        final clean = t.trim();
        if (!formatting && t.startsWith(' ')) _markSpace();
        if (clean.isEmpty) return;
        words.add(
          _Word(
            begin,
            end,
            !formatting && t.endsWith(' ') ? '$clean ' : clean,
            obscene: _Word.obsceneOf(el),
            emptyBeat: _Word.emptyBeatOf(el),
          ),
        );
    }
  }

  void _ruby(_XmlElement container) {
    var base = '';
    final rubies = <String>[];
    int? start;
    int? end;
    for (final c in container.children.whereType<_XmlElement>()) {
      switch (c.attr('ruby')) {
        case 'base':
          base = TtmlParser._collapse(c.text);
        case 'textContainer':
          for (final r in c.children.whereType<_XmlElement>()) {
            if (r.attr('ruby') != 'text') continue;
            final text = TtmlParser._collapse(r.text).trim();
            if (text.isEmpty) continue;
            rubies.add(text);
            final b = TtmlParser.parseTime(r.attr('begin'));
            final e = TtmlParser.parseTime(r.attr('end'));
            if (b != null) start = start == null ? b : min(start, b);
            if (e != null) end = end == null ? e : max(end, e);
          }
      }
    }
    final clean = base.trim();
    if (clean.isEmpty) return;
    full.write(base);
    if (base.startsWith(' ')) _markSpace();
    // 注音没有时间时，退回容器自己的时间。
    start ??= TtmlParser.parseTime(container.attr('begin'));
    end ??= TtmlParser.parseTime(container.attr('end'));
    if (start == null || end == null) return;
    words.add(
      _Word(
        start,
        end,
        base.endsWith(' ') ? '$clean ' : clean,
        ruby: rubies.isEmpty ? null : rubies.join(),
        obscene: _Word.obsceneOf(container),
        emptyBeat: _Word.emptyBeatOf(container),
      ),
    );
  }

  /// 转成一行。没有任何文字时返回 null。
  _Line? toLine({
    required int? begin,
    required int? end,
    required bool lineTiming,
    required List<(String?, String)> translations,
    required List<(String?, String)> romanizations,
    bool stripParens = false,
  }) {
    final timed = !lineTiming && words.isNotEmpty;
    List<_Word> out;
    if (timed) {
      out = [for (final w in words) w.copy()];
    } else {
      final text = plainText;
      final start = begin ?? (words.isEmpty ? null : words.map((w) => w.start).reduce(min));
      if (text.isEmpty || start == null) return null;
      final stop = end ?? (words.isEmpty ? null : words.map((w) => w.end).reduce(max));
      out = [_Word(start, stop ?? start, text)];
    }
    if (stripParens) {
      out.first.text = out.first.text.replaceFirst(RegExp(r'^[(（]+'), '').trimLeft();
      out.last.text = out.last.text.replaceFirst(RegExp(r'[)）]+$'), '').trimRight();
      out = out.where((w) => w.text.isNotEmpty).toList();
      if (out.isEmpty) return null;
    }
    final start = timed ? (begin ?? out.map((w) => w.start).reduce(min)) : out.first.start;
    final wordsEnd = out.map((w) => w.end).reduce(max);
    final stop = timed ? max(end ?? 0, wordsEnd) : end;
    return _Line(
      start: min(start, out.first.start),
      end: stop,
      words: out,
      timedWords: timed,
      translation: TtmlParser.pickLanguage(translations),
      romaji: TtmlParser.pickLanguage(romanizations),
    );
  }
}

class _Line {
  const _Line({
    required this.start,
    required this.end,
    required this.words,
    required this.timedWords,
    this.translation,
    this.romaji,
    this.duet = false,
    this.background,
    this.songPart,
  });

  final int start;
  final int? end;
  final List<_Word> words;
  final bool timedWords;
  final String? translation;
  final String? romaji;
  final bool duet;
  final _Line? background;
  final String? songPart;

  _Line withExtras({required bool duet, _Line? background, String? songPart}) {
    // 背景人声可能比主歌词早开始、晚结束：整行范围要把它包进来。
    final bgEnd = background?.end ?? background?.words.map((w) => w.end).reduce(max);
    return _Line(
      start: background == null ? start : min(start, background.start),
      end: end == null ? null : (bgEnd == null ? end : max(end!, bgEnd)),
      words: words,
      timedWords: timedWords,
      translation: translation,
      romaji: romaji,
      duet: duet,
      background: background,
      songPart: songPart,
    );
  }

  LyricLine build(int fallbackEnd) {
    final stop = max(end ?? fallbackEnd, start + 1);
    final ws = timedWords ? words : [words.single.copy(start: start, end: stop)];
    return LyricLine(
      start: TtmlParser._ms(start),
      end: TtmlParser._ms(stop),
      words: [
        for (final w in ws)
          if (w.text.isNotEmpty)
            LyricWord(
              w.text,
              TtmlParser._ms(w.start),
              TtmlParser._ms(max(w.end, w.start)),
              ruby: w.ruby,
              obscene: w.obscene,
              emptyBeat: w.emptyBeat,
            ),
      ],
      translation: translation,
      romaji: romaji,
      duet: duet,
      background: background?.build(stop),
      songPart: songPart,
    );
  }
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
