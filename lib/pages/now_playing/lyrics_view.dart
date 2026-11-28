import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../state/player_controller.dart';
import 'karaoke_text.dart';
import 'lyrics_copy.dart';

/// 歌词列表。当前行白色、放大并逐字填色（正在唱的字微微上浮发光），其他行半透明；
/// [depth] 时离当前行越远越淡（景深效果），手动滚动期间恢复，方便查找。下方附翻译和罗马音。
/// 当前行自动滚动到 [anchor] 处；[interactive] 时可手动滚动（之后暂停跟随几秒）、点行跳转、
/// 长按复制（单句或批量）。
///
/// 只滚动自身，不会带动外层滚动视图，所以可以嵌在播放页的卡片里。
class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.fontSize,
    this.interactive = true,
    this.anchor = 0.3,
    this.padding = EdgeInsets.zero,
    this.depth = false,
  });

  final double fontSize;
  final bool interactive;

  /// 当前行停在视口高度的哪个比例处。
  final double anchor;
  final EdgeInsets padding;
  final bool depth;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> with TickerProviderStateMixin {
  static const _followPause = Duration(seconds: 3);

  /// 每帧更新的歌词时间，逐字填色直接监听它重绘，不用等 50ms 一次的进度、也不重建列表。
  final _clock = ValueNotifier(Duration.zero);
  late final _ticker = createTicker((_) {
    if (_player case final p?) _clock.value = p.liveLyricPosition;
  });
  PlayerController? _player;

  final _scroll = ScrollController();

  /// 跟随滚动的动画。每帧按当时的排版重新算目标位置，所以背景人声收起、展开
  /// 导致上方高度变化时，当前行也会平滑停到锚点，不会跳。
  late final _followAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..addListener(_onFollowFrame);
  int _followTarget = -1;
  double _followFrom = 0;
  List<GlobalKey> _keys = const [];
  List<LyricInterlude> _interludes = const [];
  Lyrics? _lyrics;
  int _lastActive = -2;
  DateTime _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _ticker.dispose();
    _followAnim.dispose();
    _clock.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 换歌或换歌词来源时重建行 key 并回到顶部。
  void _syncKeys(Lyrics lyrics) {
    if (identical(_lyrics, lyrics)) return;
    _lyrics = lyrics;
    _keys = List.generate(lyrics.lines.length, (_) => GlobalKey());
    _interludes = lyricInterludes(lyrics);
    _lastActive = -2;
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _follow(int active, {bool force = false}) {
    if (active == _lastActive && !force) return;
    final first = _lastActive == -2;
    _lastActive = active;
    if (active < 0) return;
    if (!force && DateTime.now().difference(_userScrolledAt) < _followPause) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _followTarget = active;
      if (first) {
        final offset = _offsetFor(active);
        if (offset != null) _scroll.jumpTo(offset);
        return;
      }
      _followFrom = _scroll.offset;
      _followAnim.forward(from: 0);
    });
  }

  /// 让第 [index] 行停在锚点处的滚动位置；行还没排版时返回 null。
  double? _offsetFor(int index) {
    if (index < 0 || index >= _keys.length) return null;
    final target = _keys[index].currentContext?.findRenderObject();
    if (target == null || !target.attached) return null;
    return RenderAbstractViewport.of(target)
        .getOffsetToReveal(target, widget.anchor)
        .offset
        .clamp(_scroll.position.minScrollExtent, _scroll.position.maxScrollExtent);
  }

  void _onFollowFrame() {
    if (!_scroll.hasClients) return;
    final to = _offsetFor(_followTarget);
    if (to == null) return;
    // 略带回弹，接近弹簧滚动的手感。
    final t = Curves.easeOutBack.transform(_followAnim.value);
    _scroll.jumpTo(_followFrom + (to - _followFrom) * t);
  }

  @override
  Widget build(BuildContext context) {
    // 翻译、罗马音开关改了要立即生效（暂停时没有进度刷新）。
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(listenable: settings, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final player = PlayerScope.ticking(context);
    final settings = AppScope.of(context).settings;
    final lyrics = player.lyrics;
    final lines = lyrics.lines;
    _syncKeys(lyrics);
    _player = player;
    final position = player.lyricPosition;
    final interlude = _interludes.where((x) => x.contains(position)).firstOrNull;
    // 播放逐字歌词或间奏点动画时逐帧推进；暂停或逐行歌词时不占用每一帧。
    if (player.isPlaying && (lyrics.wordSynced || interlude != null)) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      if (_ticker.isActive) _ticker.stop();
      _clock.value = player.lyricPosition;
    }
    final active = player.activeLyricIndex;
    // 上一句还没唱完时，界面停在上一句，唱完再滚到下一句。
    final focus = lyricFocusIndex(lyrics, active, player.lyricPosition);
    _follow(focus);

    if (lines.isEmpty) {
      return Center(
        child: Text(
          player.lyricsLoading ? '歌词加载中…' : '暂无歌词，请欣赏音乐 ~',
          style: TextStyle(fontSize: widget.fontSize * 0.7, color: Colors.white70),
        ),
      );
    }
    final showTranslation = settings.showTranslation;
    final showRomaji = settings.showRomaji;
    final mask = settings.obsceneMask;
    final dotsAfter = {for (final x in _interludes) x.after: x};
    Widget dots(LyricInterlude x) => _InterludeDots(
      interlude: x,
      visible: identical(x, interlude),
      clock: _clock,
      size: widget.fontSize,
      right: x.after + 1 < lines.length && lines[x.after + 1].duet,
    );
    final browsing = DateTime.now().difference(_userScrolledAt) < _followPause;
    final depth = widget.depth && !browsing && active >= 0;

    return LayoutBuilder(
      builder: (context, c) {
        final list = SingleChildScrollView(
          controller: _scroll,
          physics: widget.interactive ? null : const NeverScrollableScrollPhysics(),
          // 首尾留白，让第一行和最后一行也能滚到锚点位置。
          padding: widget.padding.add(
            EdgeInsets.only(
              top: c.maxHeight * widget.anchor,
              bottom: c.maxHeight * (1 - widget.anchor),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 前奏的点放在第一行前面，其余的放在间奏前那一行后面。
              if (dotsAfter[-1] case final x?) dots(x),
              for (final (i, line) in lines.indexed) ...[
                _LyricLine(
                  key: _keys[i],
                  line: line,
                  // 间奏时上一句已经唱完，变暗，把焦点让给间奏点。
                  state:
                      (i == active && interlude == null) ||
                          _stillSinging(lyrics, i, active, player.lyricPosition)
                      ? _LineState.active
                      : i <= active
                      ? _LineState.past
                      : _LineState.future,
                  position: player.lyricPosition,
                  clock: _clock,
                  fontSize: widget.fontSize,
                  wordSynced: lyrics.wordSynced,
                  showTranslation: showTranslation,
                  showRomaji: showRomaji,
                  fade: depth ? _fadeFor((i - focus).abs()) : 1,
                  onTap: widget.interactive
                      ? () {
                          player.seek(
                            line.start -
                                player.lyricOffset -
                                (player.trial?.start ?? Duration.zero),
                          );
                          _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);
                          _follow(i, force: true);
                        }
                      : null,
                  onLongPress: widget.interactive
                      ? () => showLyricLineActions(context, player.song, lyrics, i)
                      : null,
                  mask: mask,
                ),
                if (dotsAfter[i] case final x?) dots(x),
              ],
            ],
          ),
        );
        if (!widget.interactive) return list;
        return NotificationListener<UserScrollNotification>(
          onNotification: (_) {
            final wasBrowsing = DateTime.now().difference(_userScrolledAt) < _followPause;
            _userScrolledAt = DateTime.now();
            // 手动滚动时停下跟随动画，交给用户。
            _followAnim.stop();
            // 开始手动滚动时立刻取消淡出（暂停时没有进度刷新来触发重建）。
            if (!wasBrowsing && widget.depth) setState(() {});
            return false;
          },
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: list,
          ),
        );
      },
    );
  }

  /// 和当前行相距 [d] 行时的不透明度：越远越淡，营造景深感。
  /// 不用实时模糊：每行一个 saveLayer + 高斯模糊在滚动时每帧都要重算，中端机会掉帧。
  static double _fadeFor(int d) => d == 0 ? 1 : math.max(0.35, 1 - d * 0.14);
}

/// 重叠演唱：下一行已经开始，但这一行（或它的背景人声）还没唱完时，继续当作当前行显示。
/// 只看逐字歌词，逐行歌词的结束时间多半是推算的。最多往前看 3 行。
bool _stillSinging(Lyrics lyrics, int i, int active, Duration position) =>
    lyrics.wordSynced && i < active && i >= active - 3 && position < lyrics.lines[i].end;

/// 滚动和景深对准的行：还在唱的最早一行（见 [_stillSinging]），没有时就是 [active]。
@visibleForTesting
int lyricFocusIndex(Lyrics lyrics, int active, Duration position) {
  for (var i = math.max(0, active - 3); i < active; i++) {
    if (_stillSinging(lyrics, i, active, position)) return i;
  }
  return active;
}

enum _LineState { past, active, future }

/// 非当前行和未唱部分的颜色。
const _dim = Color(0x61FFFFFF);
const _sung = Colors.white;

class _LyricLine extends StatelessWidget {
  const _LyricLine({
    super.key,
    required this.line,
    required this.state,
    required this.position,
    required this.clock,
    required this.fontSize,
    required this.wordSynced,
    required this.showTranslation,
    required this.showRomaji,
    required this.fade,
    required this.onTap,
    this.onLongPress,
    this.mask = ObsceneMask.off,
  });

  final LyricLine line;
  final _LineState state;
  final Duration position;

  /// 每帧的歌词时间，逐字填色用。
  final ValueListenable<Duration> clock;
  final double fontSize;

  /// 逐行歌词时当前行整行点亮，不做逐字填色。
  final bool wordSynced;
  final bool showTranslation;
  final bool showRomaji;
  final double fade;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 不雅用语怎么显示。
  final ObsceneMask mask;

  @override
  Widget build(BuildContext context) {
    // 距离淡出直接乘进文字颜色，不建离屏层；用补间让切行时平滑过渡。
    return TweenAnimationBuilder<double>(
      tween: Tween(end: fade),
      duration: const Duration(milliseconds: 450),
      builder: (context, f, _) => _build(f),
    );
  }

  Widget _build(double f) {
    final dimmed = _dim.withValues(alpha: _dim.a * f);
    final active = state == _LineState.active;
    final sub = active ? _sung.withValues(alpha: 0.8) : dimmed;
    final align = line.duet ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final textAlign = line.duet ? TextAlign.right : TextAlign.left;

    List<Widget> extras(LyricLine l, double scale) => [
      if (l.translation case final t? when showTranslation) ...[
        SizedBox(height: fontSize * 0.2 * scale),
        Text(
          t,
          textAlign: textAlign,
          style: TextStyle(
            fontSize: fontSize * 0.6 * scale,
            fontWeight: FontWeight.w600,
            color: sub,
          ),
        ),
      ],
      if (l.romaji case final r? when showRomaji)
        Text(
          r,
          textAlign: textAlign,
          style: TextStyle(fontSize: fontSize * 0.48 * scale, letterSpacing: 0.3, color: sub),
        ),
    ];

    final bg = line.background;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: fontSize * 0.45),
        child: _effects(
          active,
          Column(
            crossAxisAlignment: align,
            children: [
              _text(line, fontSize, dimmed),
              ...extras(line, 1),
              // 背景人声：字号小一些，唱到时同样逐字填色。唱到时展开浮现，其余时候收起。
              if (bg != null)
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 420),
                  sizeCurve: Curves.easeOutCubic,
                  alignment: line.duet ? Alignment.topRight : Alignment.topLeft,
                  crossFadeState: _showBackground(bg)
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: Column(
                    crossAxisAlignment: align,
                    children: [
                      SizedBox(height: fontSize * 0.25),
                      _text(bg, fontSize * 0.62, dimmed),
                      ...extras(bg, 0.8),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 背景人声只在当前行唱到它时显示，没唱到和唱完都收起。
  bool _showBackground(LyricLine bg) => state == _LineState.active && position >= bg.start;

  /// 一行歌词正文。所有状态用同一次排版，当前行逐字填色。
  Widget _text(LyricLine l, double size, Color dimmed) {
    final active = state == _LineState.active;
    return KaraokeText(
      words: _masked(l.words, mask),
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, height: 1.25),
      color: active ? _sung : dimmed,
      karaoke: active && wordSynced,
      position: position,
      clock: clock,
      dimColor: _dim,
      litColor: _sung,
      textAlign: line.duet ? TextAlign.right : TextAlign.left,
    );
  }

  /// 当前行原尺寸，其他行略小（按对齐的一侧缩放，只是变换，不建离屏层）。
  Widget _effects(bool active, Widget child) {
    return AnimatedScale(
      scale: active ? 1 : 0.94,
      alignment: line.duet ? Alignment.centerRight : Alignment.centerLeft,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      child: child,
    );
  }
}

/// 屏蔽后的字。同一行同一模式复用同一个列表，KaraokeText 不用每次重新排版。
final _maskCache = Expando<(ObsceneMask, List<LyricWord>)>();

List<LyricWord> _masked(List<LyricWord> words, ObsceneMask mask) {
  if (mask == ObsceneMask.off || !words.any((w) => w.obscene)) return words;
  if (_maskCache[words] case (final m, final cached) when m == mask) return cached;
  final out = [
    for (final w in words)
      w.obscene
          ? LyricWord(
              w.display(mask),
              w.start,
              w.end,
              ruby: w.ruby,
              obscene: true,
              emptyBeat: w.emptyBeat,
            )
          : w,
  ];
  _maskCache[words] = (mask, out);
  return out;
}

/// 两句歌词之间（或第一句之前）空了很久的地方。
@immutable
class LyricInterlude {
  const LyricInterlude({required this.after, required this.start, required this.end});

  /// 间奏前那一行的序号；前奏为 -1。
  final int after;
  final Duration start;
  final Duration end;

  bool contains(Duration t) => t >= start && t < end;
}

/// 空多久才算间奏、显示浮动的点。
const interludeGap = Duration(seconds: 5);

/// 找出所有间奏：前面所有行都唱完，到下一行开始还有 [minGap] 以上。
/// 歌词行可能重叠，所以「唱完」按前面所有行里最晚的结束时间算，和 AMLL 一样。
@visibleForTesting
List<LyricInterlude> lyricInterludes(Lyrics lyrics, {Duration minGap = interludeGap}) {
  final lines = lyrics.lines;
  final out = <LyricInterlude>[];
  var maxEnd = Duration.zero;
  for (var i = -1; i < lines.length - 1; i++) {
    if (i >= 0 && lines[i].end > maxEnd) maxEnd = lines[i].end;
    final next = lines[i + 1].start;
    if (next - maxEnd >= minGap) {
      out.add(LyricInterlude(after: i, start: maxEnd, end: next));
    }
  }
  return out;
}

/// 间奏时浮在歌词之间的三个点。整段间奏均分成三份，每过一份消失一个（从右往左），
/// 像倒计时：剩 3 份 3 个点，剩 2 份 2 个点，剩 1 份 1 个点。不在间奏里时收起。
class _InterludeDots extends StatelessWidget {
  const _InterludeDots({
    required this.interlude,
    required this.visible,
    required this.clock,
    required this.size,
    required this.right,
  });

  final LyricInterlude interlude;
  final bool visible;
  final ValueListenable<Duration> clock;
  final double size;

  /// 下一句是对唱（靠右）时，点也靠右。
  final bool right;

  @override
  Widget build(BuildContext context) {
    final height = size * 1.4;
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 420),
      sizeCurve: Curves.easeOutCubic,
      alignment: right ? Alignment.topRight : Alignment.topLeft,
      crossFadeState: visible ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      firstChild: const SizedBox(width: double.infinity),
      secondChild: SizedBox(
        width: double.infinity,
        height: height,
        child: CustomPaint(
          painter: InterludeDotsPainter(
            clock: clock,
            start: interlude.start,
            end: interlude.end,
            radius: size * 0.2,
            right: right,
          ),
        ),
      ),
    );
  }
}

/// 画间奏点。监听 [clock] 每帧重画，不重建 widget。
@visibleForTesting
class InterludeDotsPainter extends CustomPainter {
  InterludeDotsPainter({
    required this.clock,
    required this.start,
    required this.end,
    required this.radius,
    required this.right,
  }) : super(repaint: clock);

  final ValueListenable<Duration> clock;
  final Duration start;
  final Duration end;
  final double radius;
  final bool right;

  static const count = 3;

  /// 每个点在它那一份的最后这段时间里淡出、缩小。
  static const _fadeShare = 0.35;

  /// 第 [k] 个点（从左数，0 起）在 [t] 时的不透明度，0–1。
  static double opacityAt(int k, Duration t, Duration start, Duration end) {
    final total = (end - start).inMicroseconds;
    if (total <= 0) return 0;
    final f = ((t - start).inMicroseconds / total).clamp(0.0, 1.0);
    // 还剩几份（0–3），第 k 个点在剩下不到 k+1 份时开始消失。
    final left = (1 - f) * count - k;
    return (left / _fadeShare).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final ms = t.inMilliseconds;
    final gap = radius * 3.2;
    final width = gap * (count - 1);
    final x0 = right ? size.width - radius * 1.5 - width : radius * 1.5;
    final cy = size.height / 2;
    // 整体轻轻呼吸。
    final breathe = 1 + 0.06 * math.sin(ms / 1000 * math.pi * 2 / 2.4);
    for (var k = 0; k < count; k++) {
      final a = opacityAt(k, t, start, end);
      if (a <= 0) continue;
      // 每个点错开相位上下浮动。
      final dy = math.sin(ms / 1000 * math.pi * 2 / 1.6 - k * 0.6) * radius * 0.35;
      final r = radius * breathe * (0.55 + 0.45 * a);
      canvas.drawCircle(
        Offset(x0 + gap * k, cy + dy),
        r,
        Paint()..color = Colors.white.withValues(alpha: 0.85 * a),
      );
    }
  }

  @override
  bool shouldRepaint(InterludeDotsPainter old) =>
      old.start != start || old.end != end || old.radius != radius || old.right != right;
}
