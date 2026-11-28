import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../data/models.dart';

/// 一行歌词正文。所有状态（当前行、已唱、未唱）都用同一次排版，所以切换当前行时不会换行跳动；
/// 整行是一个段落，英文被拆成几个音节的词也会整词换行，不会断在词中间。
///
/// [karaoke] 时逐字填色：未唱的字用 [dimColor]，唱过的部分用 [litColor]，正在唱的字上浮并带柔光。
/// 否则整行用 [color]。
///
/// 有注音（[LyricWord.ruby]）时加大行高，注音画在字的上方。
///
/// 思路参考 Halcyon（Apache-2.0）的歌词渲染：整词换行、注音挂在自己的字上、重叠演唱。
class KaraokeText extends LeafRenderObjectWidget {
  const KaraokeText({
    super.key,
    required this.words,
    required this.style,
    required this.color,
    required this.karaoke,
    required this.position,
    this.dimColor = const Color(0x61FFFFFF),
    this.litColor = const Color(0xFFFFFFFF),
    this.textAlign = TextAlign.left,
  });

  final List<LyricWord> words;
  final TextStyle style;
  final Color color;
  final bool karaoke;
  final Duration position;
  final Color dimColor;
  final Color litColor;
  final TextAlign textAlign;

  @override
  RenderKaraokeText createRenderObject(BuildContext context) => RenderKaraokeText(
    words: words,
    style: DefaultTextStyle.of(context).style.merge(style),
    color: color,
    karaoke: karaoke,
    position: position,
    dimColor: dimColor,
    litColor: litColor,
    textAlign: textAlign,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderKaraokeText renderObject) {
    renderObject
      ..words = words
      ..style = DefaultTextStyle.of(context).style.merge(style)
      ..color = color
      ..karaoke = karaoke
      ..position = position
      ..dimColor = dimColor
      ..litColor = litColor
      ..textAlign = textAlign
      ..textDirection = Directionality.of(context)
      ..textScaler = MediaQuery.textScalerOf(context);
  }
}

class RenderKaraokeText extends RenderBox {
  RenderKaraokeText({
    required this._words,
    required this._style,
    required this._color,
    required this._karaoke,
    required this._position,
    required this._dimColor,
    required this._litColor,
    required this._textAlign,
    required this._textDirection,
    required this._textScaler,
  });

  /// 注音字号相对正文的比例。
  static const rubyScale = 0.42;

  List<LyricWord> _words;
  set words(List<LyricWord> v) {
    if (identical(v, _words)) return;
    _words = v;
    _invalidateLayout();
  }

  TextStyle _style;
  set style(TextStyle v) {
    if (v == _style) return;
    _style = v;
    _invalidateLayout();
  }

  Color _color;
  set color(Color v) {
    if (v == _color) return;
    _color = v;
    markNeedsPaint();
  }

  bool _karaoke;
  set karaoke(bool v) {
    if (v == _karaoke) return;
    _karaoke = v;
    markNeedsPaint();
  }

  Duration _position;
  set position(Duration v) {
    if (v == _position) return;
    _position = v;
    if (_karaoke) markNeedsPaint();
  }

  Color _dimColor;
  set dimColor(Color v) {
    if (v == _dimColor) return;
    _dimColor = v;
    markNeedsPaint();
  }

  Color _litColor;
  set litColor(Color v) {
    if (v == _litColor) return;
    _litColor = v;
    markNeedsPaint();
  }

  TextAlign _textAlign;
  set textAlign(TextAlign v) {
    if (v == _textAlign) return;
    _textAlign = v;
    _invalidateLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection v) {
    if (v == _textDirection) return;
    _textDirection = v;
    _invalidateLayout();
  }

  TextScaler _textScaler;
  set textScaler(TextScaler v) {
    if (v == _textScaler) return;
    _textScaler = v;
    _invalidateLayout();
  }

  // 排版结果。每种颜色一个 TextPainter（文字、样式、宽度相同，所以排版位置一致）。
  // 颜色在淡入淡出时会变，缓存只留最近几种。
  final _painters = <Color, TextPainter>{};
  List<TextPainter?> _rubies = const [];
  List<List<Rect>> _wordBoxes = const [];
  double _layoutWidth = 0;
  String _text = '';

  bool get _hasRuby => _words.any((w) => w.ruby != null);
  double get _fontSize => _textScaler.scale(_style.fontSize ?? 14);

  void _invalidateLayout() {
    _disposePainters();
    markNeedsLayout();
  }

  void _disposePainters() {
    for (final p in _painters.values) {
      p.dispose();
    }
    _painters.clear();
    for (final r in _rubies) {
      r?.dispose();
    }
    _rubies = const [];
    _wordBoxes = const [];
  }

  @override
  void dispose() {
    _disposePainters();
    super.dispose();
  }

  TextStyle get _textStyle {
    // 有注音时加高行距，多出的空间大部分在字的上方（按上下伸展比例分配）。
    final height = (_style.height ?? 1.25) + (_hasRuby ? rubyScale * 1.5 : 0);
    return _style.copyWith(
      height: height,
      leadingDistribution: TextLeadingDistribution.proportional,
    );
  }

  TextPainter _make(TextStyle style, String text) => TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: _textAlign,
    textDirection: _textDirection,
    textScaler: _textScaler,
  );

  /// [color] 的正文排版，宽度和其他颜色一致。
  TextPainter _paintFor(Color color) {
    if (_painters[color] case final p?) return p;
    if (_painters.length >= 6) {
      // 保留第一个（量字框用的那个），清掉其他的。
      final keep = _painters.entries.first;
      for (final e in _painters.entries.skip(1)) {
        e.value.dispose();
      }
      _painters
        ..clear()
        ..[keep.key] = keep.value;
    }
    final p = _make(_textStyle.copyWith(color: color), _text)
      ..layout(minWidth: _layoutWidth, maxWidth: _layoutWidth);
    return _painters[color] = p;
  }

  void _layoutPainters(double maxWidth, {bool fill = false}) {
    _disposePainters();
    _text = _words.map((w) => w.text).join();
    final base = _make(_textStyle.copyWith(color: const Color(0xFFFFFFFF)), _text);
    base.layout(maxWidth: maxWidth);
    if (fill) base.layout(minWidth: maxWidth, maxWidth: maxWidth);
    _layoutWidth = fill ? maxWidth : base.width;
    if (!fill) base.layout(minWidth: _layoutWidth, maxWidth: _layoutWidth);
    _painters[const Color(0xFFFFFFFF)] = base;
    _wordBoxes = [];
    var at = 0;
    for (final w in _words) {
      final end = at + w.text.length;
      // 只量去掉首尾空格的部分，填色和注音对准字形。
      final lead = w.text.length - w.text.trimLeft().length;
      final trail = w.text.length - w.text.trimRight().length;
      final boxes = end - trail > at + lead
          ? base
                .getBoxesForSelection(
                  TextSelection(baseOffset: at + lead, extentOffset: end - trail),
                )
                .map((b) => b.toRect())
                .toList()
          : const <Rect>[];
      _wordBoxes.add(boxes);
      at = end;
    }
    if (_hasRuby) {
      final rubyStyle = _style.copyWith(
        color: const Color(0xFFFFFFFF),
        fontSize: (_style.fontSize ?? 14) * rubyScale,
        fontWeight: FontWeight.w600,
        height: 1.1,
      );
      _rubies = [
        for (final w in _words)
          if (w.ruby case final r?) (_make(rubyStyle, r)..layout()) else null,
      ];
    }
  }

  TextPainter get _base => _painters[const Color(0xFFFFFFFF)]!;

  /// 每个字在排版里占的矩形（跨行时多个），测试用。
  @visibleForTesting
  List<List<Rect>> get wordBoxes => _wordBoxes;

  @override
  void performLayout() {
    // 左对齐以外的对齐要撑满宽度，否则对齐没有效果。
    final fill = _textAlign != TextAlign.left && _textAlign != TextAlign.start;
    _layoutPainters(constraints.maxWidth, fill: fill && constraints.hasBoundedWidth);
    size = constraints.constrain(Size(_base.width, _base.height));
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final p = _make(_textStyle, _words.map((w) => w.text).join())..layout(maxWidth: width);
    final h = p.height;
    p.dispose();
    return h;
  }

  @override
  double computeMaxIntrinsicHeight(double width) => computeMinIntrinsicHeight(width);

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _text
      ..textDirection = _textDirection;
  }

  double _progress(LyricWord w) => w.progressAt(_position);

  /// 正在唱的字上浮的距离。
  double _lift(double p) => -0.08 * _fontSize * Curves.easeOut.transform(p.clamp(0.0, 1.0));

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_painters.isEmpty) return;
    final canvas = context.canvas;

    if (!_karaoke) {
      _paintFor(_color).paint(canvas, offset);
      _paintRubies(canvas, offset, (_) => _color, (_) => 0);
      return;
    }

    final dim = _paintFor(_dimColor);
    final lit = _paintFor(_litColor);
    // 有进度的字单独画（会上浮）；底层把它们挖掉，免得留下错位的影子。
    final moving = <int>[
      for (var i = 0; i < _words.length; i++)
        if (_progress(_words[i]) > 0 && _wordBoxes[i].isNotEmpty) i,
    ];
    final pad = _fontSize * 0.4;
    Rect grow(Rect r) => Rect.fromLTRB(r.left, r.top - pad, r.right, r.bottom + pad);
    canvas.save();
    if (moving.isNotEmpty) {
      final hole = Path();
      for (final i in moving) {
        for (final b in _wordBoxes[i]) {
          hole.addRect(grow(b.shift(offset)));
        }
      }
      canvas.clipPath(
        Path.combine(PathOperation.difference, Path()..addRect((offset & size).inflate(pad)), hole),
      );
    }
    dim.paint(canvas, offset);
    canvas.restore();

    for (final i in moving) {
      final p = _progress(_words[i]);
      final lift = _lift(p);
      final boxes = _wordBoxes[i];
      final total = boxes.fold<double>(0, (s, b) => s + b.width);
      // 柔光在唱到一半时最亮，唱完消失。只给不跨行的字加。
      final glow = math.sin(math.pi * p.clamp(0.0, 1.0)) * 0.55;
      if (glow > 0.01 && boxes.length == 1) _paintGlow(canvas, offset, i, boxes.single, lift, glow);
      var before = 0.0;
      for (final b in boxes) {
        final r = grow(b.shift(offset));
        canvas.save();
        canvas.translate(0, lift);
        canvas.clipRect(r);
        if (p >= 1) {
          lit.paint(canvas, offset);
        } else {
          dim.paint(canvas, offset);
          final filled = (p * total - before).clamp(0.0, b.width);
          if (filled > 0) {
            // 填色边缘留一点羽化。
            final feather = math.min(_fontSize * 0.25, b.width * 0.3);
            final edge = r.left + filled;
            canvas.saveLayer(r, Paint());
            lit.paint(canvas, offset);
            canvas.drawRect(
              r,
              Paint()
                ..blendMode = BlendMode.dstIn
                ..shader = ui.Gradient.linear(
                  Offset(edge - feather, 0),
                  Offset(edge + feather, 0),
                  const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                ),
            );
            canvas.restore();
          }
        }
        canvas.restore();
        before += b.width;
      }
    }

    _paintRubies(
      canvas,
      offset,
      (i) => _progress(_words[i]) > 0 ? _litColor : _dimColor,
      (i) => _lift(_progress(_words[i])),
    );
  }

  /// 正在唱的字的柔光：只画这个字的阴影（字本身透明），叠在字形下面。
  void _paintGlow(Canvas canvas, Offset offset, int i, Rect box, double lift, double alpha) {
    final text = _words[i].text.trim();
    final p = _make(
      _textStyle.copyWith(
        color: const Color(0x00000000),
        shadows: [Shadow(color: _litColor.withValues(alpha: alpha), blurRadius: 12)],
      ),
      text,
    )..layout();
    // 单独排的字用它自己的字框对齐到整行里的字框。
    final own = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.length));
    final o = own.isEmpty ? Offset.zero : Offset(own.first.left, own.first.top);
    p.paint(canvas, offset + Offset(box.left - o.dx, box.top - o.dy + lift));
    p.dispose();
  }

  void _paintRubies(
    Canvas canvas,
    Offset offset,
    Color Function(int i) colorOf,
    double Function(int i) liftOf,
  ) {
    if (_rubies.isEmpty) return;
    for (var i = 0; i < _words.length && i < _rubies.length; i++) {
      final ruby = _rubies[i];
      final boxes = _wordBoxes[i];
      if (ruby == null || boxes.isEmpty) continue;
      // 注音放在这个字第一行那部分的正上方。
      final firstRow = boxes.where((b) => (b.top - boxes.first.top).abs() < 1).toList();
      final left = firstRow.map((b) => b.left).reduce(math.min);
      final right = firstRow.map((b) => b.right).reduce(math.max);
      final top = firstRow.map((b) => b.top).reduce(math.min);
      final at = offset + Offset((left + right - ruby.width) / 2, top - ruby.height + liftOf(i));
      canvas.save();
      // 注音只用 ruby 自己的颜色，不另建图层。
      final tinted = _make(
        (ruby.text! as TextSpan).style!.copyWith(color: colorOf(i)),
        (ruby.text! as TextSpan).text!,
      )..layout();
      tinted.paint(canvas, at);
      tinted.dispose();
      canvas.restore();
    }
  }
}
