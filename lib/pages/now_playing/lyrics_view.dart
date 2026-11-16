import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../state/player_controller.dart';
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

class _LyricsViewState extends State<LyricsView> {
  static const _followPause = Duration(seconds: 3);

  final _scroll = ScrollController();
  List<GlobalKey> _keys = const [];
  Lyrics? _lyrics;
  int _lastActive = -2;
  DateTime _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 换歌或换歌词来源时重建行 key 并回到顶部。
  void _syncKeys(Lyrics lyrics) {
    if (identical(_lyrics, lyrics)) return;
    _lyrics = lyrics;
    _keys = List.generate(lyrics.lines.length, (_) => GlobalKey());
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
      final target = _keys[active].currentContext?.findRenderObject();
      if (target == null) return;
      final offset = RenderAbstractViewport.of(target)
          .getOffsetToReveal(target, widget.anchor)
          .offset
          .clamp(_scroll.position.minScrollExtent, _scroll.position.maxScrollExtent);
      if (first) {
        _scroll.jumpTo(offset);
      } else {
        _scroll.animateTo(
          offset,
          duration: const Duration(milliseconds: 700),
          // 略带回弹，接近弹簧滚动的手感。
          curve: Curves.easeOutBack,
        );
      }
    });
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
    final active = player.activeLyricIndex;
    _follow(active);

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
              for (final (i, line) in lines.indexed)
                _LyricLine(
                  key: _keys[i],
                  line: line,
                  state: i < active
                      ? _LineState.past
                      : i == active
                      ? _LineState.active
                      : _LineState.future,
                  position: player.lyricPosition,
                  fontSize: widget.fontSize,
                  wordSynced: lyrics.wordSynced,
                  showTranslation: showTranslation,
                  showRomaji: showRomaji,
                  fade: depth ? _fadeFor((i - active).abs()) : 1,
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
                ),
            ],
          ),
        );
        if (!widget.interactive) return list;
        return NotificationListener<UserScrollNotification>(
          onNotification: (_) {
            final wasBrowsing = DateTime.now().difference(_userScrolledAt) < _followPause;
            _userScrolledAt = DateTime.now();
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
    required this.fontSize,
    required this.wordSynced,
    required this.showTranslation,
    required this.showRomaji,
    required this.fade,
    required this.onTap,
    this.onLongPress,
  });

  final LyricLine line;
  final _LineState state;
  final Duration position;
  final double fontSize;

  /// 逐行歌词时当前行整行点亮，不做逐字填色。
  final bool wordSynced;
  final bool showTranslation;
  final bool showRomaji;
  final double fade;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

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
    final style = TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, height: 1.25);
    final Widget main = switch (state) {
      _LineState.active when !wordSynced => Text(line.text, style: style.copyWith(color: _sung)),
      _LineState.active => Wrap(
        children: [
          for (final w in line.words)
            _KaraokeWord(text: w.text, progress: w.progressAt(position), style: style),
        ],
      ),
      _LineState.past || _LineState.future => Text(line.text, style: style.copyWith(color: dimmed)),
    };
    final active = state == _LineState.active;
    final sub = active ? _sung.withValues(alpha: 0.8) : dimmed;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: fontSize * 0.45),
        child: _effects(
          active,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              main,
              if (line.translation case final t? when showTranslation) ...[
                SizedBox(height: fontSize * 0.2),
                Text(
                  t,
                  style: TextStyle(
                    fontSize: fontSize * 0.6,
                    fontWeight: FontWeight.w600,
                    color: sub,
                  ),
                ),
              ],
              if (line.romaji case final r? when showRomaji)
                Text(
                  r,
                  style: TextStyle(fontSize: fontSize * 0.48, letterSpacing: 0.3, color: sub),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 当前行原尺寸，其他行略小（左对齐缩放，只是变换，不建离屏层）。
  Widget _effects(bool active, Widget child) {
    return AnimatedScale(
      scale: active ? 1 : 0.94,
      alignment: Alignment.centerLeft,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      child: child,
    );
  }
}

/// 单个字的逐字填色：底层半透明文字，上层白色文字按 [progress] 从左往右显现；
/// 唱这个字时整体上浮一点并带柔光，唱完保持上浮。
class _KaraokeWord extends StatelessWidget {
  const _KaraokeWord({required this.text, required this.progress, required this.style});

  final String text;
  final double progress;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final dim = Text(text, style: style.copyWith(color: _dim));
    if (progress <= 0) return dim;
    // 光晕在唱到一半时最亮，唱完消失。
    final glow = math.sin(math.pi * progress.clamp(0.0, 1.0)) * 0.55;
    final lit = Text(
      text,
      style: style.copyWith(
        color: _sung,
        shadows: glow > 0.01
            ? [Shadow(color: Colors.white.withValues(alpha: glow), blurRadius: 12)]
            : null,
      ),
    );
    final lift = Offset(
      0,
      -0.08 * style.fontSize! * Curves.easeOut.transform(progress.clamp(0.0, 1.0)),
    );
    if (progress >= 1) return Transform.translate(offset: lift, child: lit);
    return Transform.translate(offset: lift, child: _fill(dim, lit));
  }

  Widget _fill(Widget dim, Widget lit) {
    return Stack(
      children: [
        dim,
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => LinearGradient(
            colors: const [Colors.white, Colors.white, Colors.transparent, Colors.transparent],
            // 边缘留一点羽化，填色过渡更柔和。
            stops: [0, (progress - 0.06).clamp(0.0, 1.0), (progress + 0.06).clamp(0.0, 1.0), 1],
          ).createShader(r),
          child: lit,
        ),
      ],
    );
  }
}
