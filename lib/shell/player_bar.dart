import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pages/now_playing/now_playing_page.dart';
import '../state/player_controller.dart';
import '../data/models.dart';
import '../theme/app_theme.dart';
import '../widgets/backdrop_color.dart';
import '../widgets/cover_art.dart';
import '../widgets/like_button.dart';
import '../widgets/motion.dart';
import '../widgets/round_icon_button.dart';

/// 底部迷你播放条，参考 Spotify：悬浮圆角卡片，底色取自封面，底边是一条细进度线。
///
/// 点歌曲信息进入播放页。在歌曲信息上左滑切下一首，右滑切上一首，滑动时旁边露出那首歌。
/// 队列为空时不显示。
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key});

  /// 卡片高度。
  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final song = player.current;
    if (song == null) return const SizedBox.shrink();

    // 用封面主色做种子生成一套 M3 配色，卡片取它的 primaryContainer，浅色 / 深色都协调。
    final cover = coverScheme(backdropColorFor(player.palette), Theme.of(context).brightness);
    final fg = cover.onPrimaryContainer;
    // 开始放歌时播放条从下方滑入。
    return Entrance(
      index: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          height: height,
          decoration: BoxDecoration(
            color: cover.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.panel),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            // 撑满卡片高度，歌曲信息和按钮在卡片里垂直居中。
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: _SwipeToSkip(
                        current: song,
                        previous: player.peekPrevious,
                        next: player.peekNext,
                        onPrevious: () => player.previous(restart: false),
                        onNext: player.next,
                        onTap: () => openNowPlaying(context),
                        color: fg,
                      ),
                    ),
                    RoundIconButton(
                      icon: Icons.lyrics_outlined,
                      onPressed: () => openNowPlaying(context, showLyrics: true),
                      tooltip: '歌词',
                      size: 40,
                      iconSize: 22,
                      color: fg,
                    ),
                    LikeButton(songId: song.id, color: fg),
                    RoundIconButton(
                      icon: player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      onPressed: player.toggle,
                      tooltip: player.isPlaying ? '暂停' : '播放',
                      size: 44,
                      iconSize: 28,
                      filled: true,
                      background: cover.primary,
                      color: cover.onPrimary,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 0,
                child: _ProgressLine(color: cover.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 悬浮在页面内容上方的底部区域：迷你播放条，以及可选的底部导航。
///
/// 背景是从透明到页面底色的渐变，内容可以滚到它下面。
/// 搭配 `Scaffold(extendBody: true)` 使用，滚动内容底部用 [floatingBarsInset] 留白。
class FloatingBottomBar extends StatelessWidget {
  const FloatingBottomBar({super.key, this.navigation});

  /// 播放条下方的导航栏。为空时只有播放条，并自己处理底部安全区。
  final Widget? navigation;

  @override
  Widget build(BuildContext context) {
    final nav = navigation;
    final scheme = context.scheme;
    // 有导航栏时渐变的终点用导航栏的底色，播放条和导航栏连成一体。
    final end = nav == null ? scheme.surface : scheme.surfaceContainer;
    final bar = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [end.withValues(alpha: 0), end.withValues(alpha: 0.85), end],
          stops: const [0, 0.4, 1],
        ),
      ),
      // 二级页面没有导航栏：播放条离屏幕底边（手势条）再抬高一点。
      child: nav == null
          ? const SafeArea(
              top: false,
              minimum: EdgeInsets.only(bottom: 12),
              child: Padding(padding: EdgeInsets.only(bottom: 8), child: PlayerBar()),
            )
          : const PlayerBar(),
    );
    return Column(mainAxisSize: MainAxisSize.min, children: [bar, ?nav]);
  }
}

/// 页面延伸到 [FloatingBottomBar] 下方时，滚动内容底部要留出的高度。
///
/// `Scaffold(extendBody: true)` 会把底栏高度算进 body 的 MediaQuery 底部 padding。
/// 不传 padding 的 ListView 会自动留出这段距离，其他滚动视图要手动加上。
double floatingBarsInset(BuildContext context) => MediaQuery.paddingOf(context).bottom;

/// 卡片底边的细进度线，只显示不响应手势（拖动进度到播放页里操作）。
/// 迷你播放条底部的进度线。自己订阅进度，播放时只重建这一小块。
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = PlayerScope.ticking(context).progress;
    return ClipRRect(
      borderRadius: BorderRadius.circular(1),
      child: SizedBox(
        height: 3,
        child: ColoredBox(
          color: color.withValues(alpha: 0.2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              heightFactor: 1,
              child: ColoredBox(color: color),
            ),
          ),
        ),
      ),
    );
  }
}

/// 迷你播放条里的一首歌：封面 + 歌名 + 歌手。[hero] 只给当前这首，和播放页的封面衔接。
class _SongInfo extends StatelessWidget {
  const _SongInfo({required this.song, required this.color, this.hero = false});

  final Song song;
  final Color color;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final cover = CoverArt(
      palette: song.palette,
      seed: song.id,
      imageUrl: song.coverUrl,
      radius: AppRadius.small,
    );
    return Row(
      children: [
        SizedBox.square(
          dimension: 48,
          child: hero ? Hero(tag: 'now-playing-cover', child: cover) : cover,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
              ),
              const SizedBox(height: 1),
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: color.withValues(alpha: 0.72)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 水平滑动切歌，和主流播放器一致：左滑（手指向左）切下一首，右滑切上一首。
///
/// 当前这首跟手移动，旁边露出上一首 / 下一首的信息；松手时滑够距离或速度够快，
/// 就滑到底再切歌，否则回弹。没有上一首 / 下一首时拉起来有阻尼，也不会切。
class _SwipeToSkip extends StatefulWidget {
  const _SwipeToSkip({
    required this.current,
    required this.previous,
    required this.next,
    required this.onPrevious,
    required this.onNext,
    required this.onTap,
    required this.color,
  });

  final Song current;
  final Color color;
  final Song? previous;
  final Song? next;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onTap;

  @override
  State<_SwipeToSkip> createState() => _SwipeToSkipState();
}

class _SwipeToSkipState extends State<_SwipeToSkip> with SingleTickerProviderStateMixin {
  /// 触发切歌的最小滑动比例（相对宽度）。
  static const _fraction = 0.3;

  /// 触发切歌的最小甩动速度（逻辑像素/秒）。
  static const _velocity = 600.0;

  /// 两首歌之间的间隔。
  static const _gap = 24.0;

  late final _offset = AnimationController.unbounded(vsync: this);
  double _width = 0;

  /// 已经滑出去、等新歌顶上来的方向（-1 下一首，1 上一首）。
  int _committed = 0;

  /// 切歌没生效时把卡片滑回来的计时器。
  Timer? _fallback;

  @override
  void didUpdateWidget(_SwipeToSkip old) {
    super.didUpdateWidget(old);
    // 歌换好了：新的当前歌就是刚才露出来的那首，直接归位，看起来是连续的。
    if (old.current.id != widget.current.id) {
      _fallback?.cancel();
      _committed = 0;
      _offset.value = 0;
    }
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _offset.dispose();
    super.dispose();
  }

  /// 没有可切的歌时，拉动有阻尼（只走三分之一）。
  void _onUpdate(DragUpdateDetails d) {
    if (_committed != 0) return;
    final delta = d.primaryDelta ?? 0;
    final dx = _offset.value + delta;
    final blocked =
        (dx < 0 && widget.next == null && !_canFetchNext) || (dx > 0 && widget.previous == null);
    _offset.value = _offset.value + (blocked ? delta / 3 : delta);
  }

  /// 私人 FM 放到最后一首时下一首还没取到（next 为 null），但按下一首会去取，照样让切。
  bool get _canFetchNext => PlayerScope.read(context).isRadio;

  Future<void> _onEnd(DragEndDetails d) async {
    if (_committed != 0) return;
    final dx = _offset.value;
    final v = d.primaryVelocity ?? 0;
    final span = _width + _gap;
    final toNext = (dx <= -_width * _fraction || v <= -_velocity) && dx < 0;
    final toPrevious = (dx >= _width * _fraction || v >= _velocity) && dx > 0;
    if (toNext && (widget.next != null || _canFetchNext)) {
      _committed = -1;
      unawaited(HapticFeedback.selectionClick());
      await _offset.animateTo(
        -span,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
      widget.onNext();
    } else if (toPrevious && widget.previous != null) {
      _committed = 1;
      unawaited(HapticFeedback.selectionClick());
      await _offset.animateTo(
        span,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
      widget.onPrevious();
    } else {
      _settle();
      return;
    }
    // 切歌没生效（例如私人 FM 没取到新歌）：过一会儿还在原来那首就滑回来。
    final from = widget.current.id;
    _fallback?.cancel();
    _fallback = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && _committed != 0 && widget.current.id == from) {
        _committed = 0;
        _settle();
      }
    });
  }

  void _settle() =>
      _offset.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _width = c.maxWidth;
        final span = _width + _gap;
        Widget panel(Song song, double shift, {bool hero = false}) => Positioned(
          left: shift,
          width: _width,
          top: 0,
          bottom: 0,
          child: _SongInfo(song: song, hero: hero, color: widget.color),
        );
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onTap,
          onHorizontalDragStart: (_) {
            if (_committed == 0) _offset.stop();
          },
          onHorizontalDragUpdate: _onUpdate,
          onHorizontalDragEnd: _onEnd,
          onHorizontalDragCancel: () {
            if (_committed == 0) _settle();
          },
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _offset,
              builder: (context, _) {
                final dx = _offset.value;
                final prev = widget.previous;
                final next = widget.next;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 只在露出来时才建旁边那首，平时不多画。
                    if (dx > 0 && prev != null) panel(prev, dx - span),
                    panel(widget.current, dx, hero: true),
                    if (dx < 0 && next != null) panel(next, dx + span),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

final _coverSchemes = <(int, Brightness), ColorScheme>{};

/// 以封面主色为种子的 M3 配色。按颜色缓存，切歌回到听过的封面不用重新算。
ColorScheme coverScheme(Color seed, Brightness brightness) {
  if (_coverSchemes.length > 64) _coverSchemes.clear();
  return _coverSchemes.putIfAbsent(
    (seed.toARGB32(), brightness),
    () => ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    ),
  );
}
